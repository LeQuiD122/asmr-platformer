--!strict
-- StarterPlayerScripts/Services/DeformationRenderer.lua
-- Per-material deformation. Each material gets its own visual vocabulary rather
-- than sharing one "sink the box" tween:
--
--   Honey        sags deeply and leaves persistent amber smears where you stood
--   KineticSand  barely moves; stamps oriented footprints and sheds crumbs
--   ButterWax    barely moves; fractures into radiating crack lines
--   Slime        stretches down and snaps back elastic
--   Soap         sinks while cracking, then bursts into falling fragments
--   BubbleWrap   a film of pockets; the ones under your foot burst, neighbours flex
--
-- Everything here is client-local and cosmetic. The server owns state, physics
-- and collision; nothing spawned in this file replicates or affects gameplay.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MaterialAppearance = require(Shared:WaitForChild("MaterialAppearance"))
local MaterialConfigModule = require(Shared:WaitForChild("MaterialConfig"))
local Materials = MaterialConfigModule.Materials

local AudioService = require(script.Parent:WaitForChild("AudioService"))
local ScreenEffects = require(script.Parent:WaitForChild("ScreenEffects"))

local player = Players.LocalPlayer

local DeformationRenderer = {}

-- === Per-tile bookkeeping ===

local restCFrame: { [BasePart]: CFrame } = {}
local restSize: { [BasePart]: Vector3 } = {}
local lastState: { [BasePart]: string } = {}
local activeTweens: { [BasePart]: { Tween } } = {}
local marks: { [BasePart]: { BasePart } } = {} -- smears, footprints, cracks
-- Bubble wrap keeps no per-tile state here any more. Its pockets are bones in the
-- skinned sheet, so what has burst is recorded per BONE, next to the code that drives
-- them (see `burstBones`) -- there is nothing left that is owned by a tile.

local MAX_MARKS_PER_TILE = 8

-- A tile may carry a "Visual" MeshPart child (see ChunkBuilder.attachMeshVisual).
-- Parenting one BasePart to another does NOT create a transform hierarchy in
-- Roblox, so moving the tile leaves the mesh behind. Every tile movement therefore
-- has to drive the mesh explicitly, using the fixed offset captured at rest.
local visualOffset: { [BasePart]: CFrame } = {}

-- A slime mesh's UNDEFORMED size. Captured on the first press rather than read back
-- when it is needed, because by then the mesh is mid-stretch and reading its Size
-- would ratchet: each press would scale from the last press's stretched value and
-- the cell would grow without bound.
local slimeVisualRest: { [BasePart]: Vector3 } = {}

local function visualOf(tile: BasePart): BasePart?
	local child = tile:FindFirstChild("Visual")
	return (child and child:IsA("BasePart")) and child or nil
end

-- Captures a tile's rest transform the first time anything needs it. Idempotent.
--
-- Declared up here rather than beside moveTile because the per-tile ripple reaches
-- cells the player has never stood on, and those have no rest transform yet. A
-- `local function` is only in scope AFTER its declaration, so a later definition
-- would compile every earlier reference to a nil global instead.
local function remember(tile: BasePart)
	if not restCFrame[tile] then
		restCFrame[tile] = tile.CFrame
		restSize[tile] = tile.Size
		local visual = visualOf(tile)
		if visual then
			visualOffset[tile] = tile.CFrame:Inverse() * visual.CFrame
		end
	end
end

local function cancelTweens(tile: BasePart)
	local list = activeTweens[tile]
	if list then
		for _, tween in ipairs(list) do
			tween:Cancel()
		end
	end
	activeTweens[tile] = {}
end

local function play(tile: BasePart, target: Instance, info: TweenInfo, goal: { [string]: any })
	local tween = TweenService:Create(target, info, goal)
	activeTweens[tile] = activeTweens[tile] or {}
	table.insert(activeTweens[tile], tween)
	tween:Play()
	return tween
end

-- === Collider, on skinned platforms only ===
--
-- The collider is a separate "Floor" child rather than the tile itself, because a
-- part cannot both sense touch and collide while being moved: shifting it under a
-- standing player re-fires Touched/TouchEnded as the contact manifold changes, a
-- spurious TouchEnded commits an exit after the grace period, the cell reports
-- decaying, the collider returns to rest, that re-contacts the player, and it presses
-- again. See ChunkBuilder.buildSubRegions.
--
-- So the tile stays put as a pure sensor and this moves instead.

local floorCache: { [BasePart]: BasePart? } = {}
local floorChecked: { [BasePart]: boolean } = {}
local floorRest: { [BasePart]: CFrame } = {}

local function floorOf(tile: BasePart): BasePart?
	if not floorChecked[tile] then
		floorChecked[tile] = true
		local child = tile:FindFirstChild("Floor")
		local floor = (child and child:IsA("BasePart")) and child or nil
		floorCache[tile] = floor
		if floor then
			floorRest[floor] = floor.CFrame
		end
	end
	return floorCache[tile]
end

local function driveFloor(tile: BasePart, info: TweenInfo, sink: number)
	local floor = floorOf(tile)
	local rest = floor and floorRest[floor]
	if not floor or not rest then
		return
	end
	play(tile, floor, info, { CFrame = rest * CFrame.new(0, sink, 0) })
end

-- === Skinned platforms ===
--
-- When a platform carries a SkinnedVisual, deformation is expressed by moving that
-- mesh's bones rather than by moving the tile. Bone "Cell_<col>_<row>" corresponds
-- to the sub-region of the same coordinates, and because bone influences overlap
-- (see INFLUENCE in gen_honey_skinned.py) a single bone's movement dents the
-- surface with a smooth falloff instead of displacing a rectangle.
--
-- The tile still moves nothing visible: it is transparent and exists only to
-- collide and to fire Touched.
local boneCache: { [BasePart]: Bone? } = {}
local boneChecked: { [BasePart]: boolean } = {}

local boneMatchWarned = false

-- Bones are matched to tiles by WORLD POSITION, not by name.
--
-- Name matching required the rig's row/column order to agree with
-- SubRegionGrid's, and it did not: the FBX conversion flips Blender Y to Roblox
-- Z, so authored row 1 arrived where row N belongs and every dent appeared
-- mirrored across the platform. Correcting the authoring order fixed one axis and
-- left the other, and each attempt cost a full re-export and re-import to test.
--
-- Nearest-bone-by-position cannot be wrong. It is immune to axis flips, mirroring,
-- renaming and re-authoring, and it needs no round trip to verify. Only XZ is
-- compared, so it also stays correct for bones that have already been pressed
-- down.
local function boneFor(tile: BasePart): Bone?
	if boneChecked[tile] then
		return boneCache[tile]
	end
	boneChecked[tile] = true

	local slab = tile.Parent
	if not slab or not slab:IsA("BasePart") or not slab:GetAttribute("SkinnedVisual") then
		return nil
	end
	local visual = slab:FindFirstChild("SkinnedVisual")
	if not visual then
		return nil
	end

	local target = tile.Position
	local best: Bone? = nil
	local bestDistance = math.huge

	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("Bone") and descendant.Name:match("^Cell_") then
			local position = descendant.WorldPosition
			local dx = position.X - target.X
			local dz = position.Z - target.Z
			local distance = dx * dx + dz * dz
			if distance < bestDistance then
				best, bestDistance = descendant, distance
			end
		end
	end

	-- A correct match lands well inside one cell. Anything further means the rig's
	-- bone grid does not correspond to this platform's cell grid at all, which name
	-- matching would have hidden by silently picking a wrong-but-existing bone.
	if best and bestDistance > 9 and not boneMatchWarned then
		boneMatchWarned = true
		warn(("DeformationRenderer: nearest bone to %s is %.1f studs away; the rig's grid may not match this platform."):format(
			tile.Name,
			math.sqrt(bestDistance)
		))
	end

	boneCache[tile] = best
	return best
end

-- === Ripples ===
--
-- A footfall on a liquid does not just dent the contact point, it sends a wave
-- outward. Because the platform is one skinned mesh, that can be REAL geometry:
-- press the neighbouring bones in a delayed, decaying sequence and a wave visibly
-- travels through the surface. No decal can do this; a growing disc is only ever a
-- circle appearing and vanishing in place.
--
-- Each ring does a damped oscillation (down, back up past rest, settle) rather than
-- a single dip, which is what makes it read as a wave passing under the surface
-- instead of a dimple switching on and off.

-- === Viscosity ===
--
-- Water and honey differ in three ways, and all three are tuned here. Water carries
-- many wavefronts, they travel FAR before dying, and they OSCILLATE (a struck
-- surface bounces past rest several times). Honey produces one slow bulge that dies
-- close to the impact and settles without bouncing at all.
--
-- Of the three, the overshoot matters most. A crest that rises back above rest is
-- the single most water-like cue there is, so for a viscous material it is nearly
-- removed rather than merely reduced.
--
-- Slime sits at the far end of every one of those axes, which is the whole reason
-- these are a per-material table now rather than the module-level constants they
-- started as. Honey's values are unchanged; the axes just have a second occupant.

export type RippleProfile = {
	-- Studs/second the wavefront travels. This ALSO sets the expansion rate of the
	-- visible rings (see ringTravel), so the drawn outline rides the crest of the
	-- real surface displacement instead of drifting away from it.
	speed: number,
	-- Amplitude e-folding distance. Short means the energy dissipates locally
	-- instead of being carried across the platform.
	falloff: number,
	-- Height of the travelling ridge, in studs, at the footfall. This is what makes
	-- the wave read as displaced material rather than as a drawn line, so it is
	-- deliberately large relative to the mesh's own surface detail.
	amplitude: number,
	-- Seconds for the rise stroke.
	dip: number,
	-- Height the surface rebounds ABOVE rest, as a fraction of the rise.
	overshoot: number,
	-- Rings per footfall, and how far apart in time they leave.
	rings: number,
	ringStagger: number,
	-- Ring diameter in studs at the end of its travel.
	ringEnd: number,
}

local RippleProfiles: { [string]: RippleProfile } = {
	-- Viscous. One slow bulge, dying close to the impact, settling without bouncing.
	-- At an overshoot of 0.38 the surface visibly bounced, which is water behaviour.
	Honey = {
		speed = 0.9,
		falloff = 3.2,
		amplitude = 0.8,
		dip = 0.5,
		overshoot = 0.10,
		rings = 1,
		ringStagger = 0.18,
		ringEnd = 5.0,
	},
	-- Springy. Deliberately the inverse of honey on every axis, because slime and
	-- honey are the two materials a player is most likely to confuse: both are
	-- glossy, translucent and slow you down on contact, so the DEFORMATION is what
	-- has to tell them apart.
	--
	-- The overshoot carries most of that. Honey's is 0.10 precisely because a
	-- rebound reads as water; slime wants the rebound, so at 0.85 the crest returns
	-- most of the way back up before settling and the surface visibly rings.
	--
	-- Three rings rather than one for the same reason. A train of rings implies the
	-- surface is still oscillating after the impact has passed, which is exactly
	-- wrong for honey and exactly right here.
	--
	-- Speed is set from how long the RING takes, since that is the part you watch:
	-- travel is ringEnd/2 over speed, so 11 studs at 6.5 completes in 0.85s against
	-- honey's 2.8s, and the whole platform has responded inside 1.5s.
	--
	-- AMPLITUDE IS CAPPED BY THE MEDIUM, NOT BY TASTE, and this is the one place
	-- slime cannot match the brief. Honey's wave runs through a skinned mesh whose
	-- bone influences overlap, so neighbouring cells blend and nothing tears. Slime
	-- is per-tile meshes that are EDGE-MATCHED: they are authored to meet flush at a
	-- fixed height, so any two adjacent tiles at different heights open a visible
	-- seam in what is supposed to be one unbroken pour. Past roughly 0.6 studs the
	-- wave stops reading as a surface and starts reading as loose tiles. Raising it
	-- further needs a skinned slime rig, not a bigger number here.
	-- DOUGH IN A SKIN. The wave has to die close to the foot: a NeeDoh does not transmit a
	-- press across itself the way a liquid does, because what is inside it is packed rather
	-- than free to move. So: short falloff, and an overshoot near zero because the one thing
	-- it must not do is RING -- a ringing NeeDoh is a jelly, which is the material sitting
	-- next to it in the level pool.
	--
	-- One ring rather than slime's three, for the same reason. A train of rings says the
	-- surface is still moving after the step has passed, and this surface is not.
	Needoh = {
		speed = 3.4,
		falloff = 4.6,
		amplitude = 0.62,
		dip = 0.34,
		overshoot = 0.06,
		rings = 1,
		ringStagger = 0.14,
		ringEnd = 6.0,
	},
	-- Softer than the Needoh and slower to give it back. Butter has no spring at all: the
	-- overshoot is zero, not merely small, because a bounce is the single thing that would
	-- stop this reading as butter. What travels is a slow sag rather than a wave.
	ButterStick = {
		speed = 1.6,
		falloff = 3.0,
		amplitude = 0.5,
		dip = 0.62,
		overshoot = 0,
		rings = 1,
		ringStagger = 0.2,
		ringEnd = 4.6,
	},
	Slime = {
		speed = 6.5,
		falloff = 7.0,
		amplitude = 0.6,
		dip = 0.13,
		overshoot = 0.85,
		rings = 3,
		ringStagger = 0.09,
		ringEnd = 11.0,
	},
}

local RIPPLE_MIN = 0.02        -- below this a ring is invisible; skip the tweens

-- DERIVED from the wave speed, not set independently. The drawn ring has to expand
-- at exactly the rate the surface wavefront travels, or the outline and the actual
-- displacement drift apart and the rings read as flat decals sliding over a
-- separately-wobbling surface. Tying them together is what gives the rings depth.
local function ringTravel(profile: RippleProfile): number
	return (profile.ringEnd / 2) / profile.speed
end

-- How much of the visual dent the COLLIDER follows, so the player physically sinks
-- into the surface instead of standing on top of a depression.
--
-- Collision does not follow a skinned mesh, so without this your feet stay on the
-- original plane while the honey visibly caves in beneath them, which is the single
-- biggest thing undermining "walking on honey". Only a fraction, because the full
-- 1.55 studs would be a hole rather than a soft surface, and because the tile is
-- what the character is standing on while it moves.
local COLLIDER_SINK_FRACTION = 0.26

-- Bones a player is actively standing on. Ripples must not fight a held dent, and
-- must not release one back to rest on their way past.
local heldSink: { [Bone]: number } = {}
-- The impression a foot LEFT BEHIND: a shallower dent the surface keeps after the
-- player has moved on, until the cell's decay window closes and it levels out.
--
-- Tracked separately from heldSink on purpose. Residual cells must still carry
-- ripples, because after a few steps most of the honey behind you has a print in it
-- and a wave that could not cross those cells would die immediately.
local residualSink: { [Bone]: number } = {}
-- Supersedes stale ripples: many footfalls schedule many delayed tweens, and
-- without a generation check an old wave can undo a newer one.
local rippleToken: { [Bone]: number } = {}

-- Every bone on a platform, cached per slab.
--
-- REVERTED from a split into all-bones plus a coarse subset. That existed because a 2x
-- finer rig had 120 bones and sweeping them all for a ripple was 360 tweens per step. At
-- one bone per cell there are 30 and no subset is needed.
local platformBones: { [BasePart]: { Bone } } = {}

local function bonesForPlatform(slab: BasePart): { Bone }
	local cached = platformBones[slab]
	if cached then
		return cached
	end
	local list: { Bone } = {}
	local visual = slab:FindFirstChild("SkinnedVisual")
	if visual then
		for _, descendant in ipairs(visual:GetDescendants()) do
			if descendant:IsA("Bone") and descendant.Name:match("^Cell_") then
				table.insert(list, descendant)
			end
		end
	end
	platformBones[slab] = list
	return list
end

local function boneOffset(bone: Bone, info: TweenInfo, sink: number)
	TweenService:Create(bone, info, { Transform = CFrame.new(0, sink, 0) }):Play()
end

local function rippleFrom(slab: BasePart, originPos: Vector3, profile: RippleProfile)

	for _, bone in ipairs(bonesForPlatform(slab)) do
		if heldSink[bone] then
			continue
		end

		local position = bone.WorldPosition
		local dx = position.X - originPos.X
		local dz = position.Z - originPos.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		local amplitude = profile.amplitude * math.exp(-distance / profile.falloff)
		if amplitude < RIPPLE_MIN then
			continue
		end

		-- Ripples oscillate around whatever this cell already holds, so a wave
		-- crossing a footprint raises and lowers it without erasing it.
		local base = residualSink[bone] or 0

		local token = (rippleToken[bone] or 0) + 1
		rippleToken[bone] = token

		-- Delay proportional to distance is what makes it a travelling wave rather
		-- than the whole platform flexing at once.
		task.delay(distance / profile.speed, function()
			if rippleToken[bone] ~= token or heldSink[bone] or not bone.Parent then
				return
			end

			-- RISES first, and this is the important part.
			--
			-- A foot pressing into honey displaces material, and that material has to
			-- go somewhere: it piles up as a ridge AROUND the contact point and the
			-- ridge travels outward. Dipping first (what this did before) is what a
			-- struck drum skin does, not what a displaced viscous fluid does, and it
			-- is most of why the wave read as a flat ring rather than as displacement.
			local crest = TweenService:Create(
				bone,
				TweenInfo.new(profile.dip, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Transform = CFrame.new(0, base + amplitude, 0) }
			)
			crest.Completed:Once(function()
				if rippleToken[bone] ~= token or heldSink[bone] or not bone.Parent then
					return
				end
				-- Sag below rest as the ridge passes and the material drains back,
				-- then settle. Slight for honey, where a pronounced rebound is water;
				-- large for anything springy, where it is the point.
				local sag = TweenService:Create(
					bone,
					TweenInfo.new(profile.dip * 2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Transform = CFrame.new(0, base - amplitude * profile.overshoot, 0) }
				)
				sag.Completed:Once(function()
					if rippleToken[bone] ~= token or heldSink[bone] or not bone.Parent then
						return
					end
					-- Returns to the cell's residual level, not to flat, so a passing
					-- wave cannot iron out a footprint that has not decayed yet.
					boneOffset(
						bone,
						TweenInfo.new(profile.dip * 2.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
						residualSink[bone] or 0
					)
				end)
				sag:Play()
			end)
			crest:Play()
		end)
	end
end

-- === Ripples on per-tile platforms ===
--
-- The same travelling wave for materials that have no rig. There is one tile per
-- sub-region cell and one bone per sub-region cell, so the two are the same grid and
-- the wave is the same algorithm; only the thing being moved differs.
--
-- IT MOVES THE "Visual" MESH CHILDREN, NEVER THE TILES. That is not an optimisation,
-- it is the only safe option. A tile is the collider AND the touch sensor, and
-- DeformationService runs tryLaunch on EVERY Touched contact, not just on first
-- occupancy. A crest that lifted a tile into a player standing on a neighbouring
-- cell would fire Touched, and on slime that is a launch the player never earned --
-- a 100 stud/s throw arriving out of nowhere, rate-limited only by a 0.35s cooldown.
-- The Visual children are CanCollide, CanTouch and CanQuery false, so moving them
-- cannot signal anything.
--
-- This mirrors what the skinned path already does: the mesh carries the whole
-- deformation and the collider follows only a fraction, only under the standing
-- foot. Here the collider does not follow at all, because a per-tile platform has
-- no separate Floor child to move independently of the sensor.
local platformTiles: { [BasePart]: { BasePart } } = {}
local visualToken: { [BasePart]: number } = {}
-- Tiles under a foot right now. A wave must not fight a held press, and must not
-- release one back to rest on its way past.
local heldVisual: { [BasePart]: boolean } = {}
local visualWarned = false

local function tilesForPlatform(slab: BasePart): { BasePart }
	local cached = platformTiles[slab]
	if cached then
		return cached
	end
	local list: { BasePart } = {}
	for _, child in ipairs(slab:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^SubRegion_") then
			table.insert(list, child)
		end
	end
	platformTiles[slab] = list
	return list
end

-- Drives one tile's mesh to a height above its rest position. Mirrors the offset
-- maths in moveTile: the mesh sits at a fixed transform from the tile, captured at
-- rest, because parenting a part to a part creates no transform hierarchy in Roblox.
local function offsetVisual(tile: BasePart, info: TweenInfo, height: number)
	local visual, offset = visualOf(tile), visualOffset[tile]
	local rest = restCFrame[tile]
	if not visual or not offset or not rest then
		return
	end
	TweenService:Create(visual, info, { CFrame = rest * CFrame.new(0, height, 0) * offset }):Play()
end

local function rippleVisualsFrom(slab: BasePart, originPos: Vector3, profile: RippleProfile)
	local tiles = tilesForPlatform(slab)
	local drove = false

	for _, tile in ipairs(tiles) do
		if heldVisual[tile] then
			continue
		end
		-- A neighbouring cell may never have been stepped on, so its rest transform
		-- may not have been captured yet. remember() is idempotent and cheap.
		remember(tile)
		if not visualOf(tile) then
			continue
		end
		drove = true

		local position = tile.Position
		local dx = position.X - originPos.X
		local dz = position.Z - originPos.Z
		local distance = math.sqrt(dx * dx + dz * dz)
		local amplitude = profile.amplitude * math.exp(-distance / profile.falloff)
		if amplitude < RIPPLE_MIN then
			continue
		end

		local token = (visualToken[tile] or 0) + 1
		visualToken[tile] = token

		task.delay(distance / profile.speed, function()
			if visualToken[tile] ~= token or heldVisual[tile] or not tile.Parent then
				return
			end

			-- Rises first, for the same reason the skinned wave does: a foot pressing
			-- in displaces material, and it piles up as a ridge AROUND the contact
			-- point. Dipping first is a struck drum skin, not displaced matter.
			offsetVisual(tile, TweenInfo.new(profile.dip, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), amplitude)

			task.delay(profile.dip, function()
				if visualToken[tile] ~= token or heldVisual[tile] or not tile.Parent then
					return
				end
				offsetVisual(
					tile,
					TweenInfo.new(profile.dip * 2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					-amplitude * profile.overshoot
				)

				task.delay(profile.dip * 2.2, function()
					if visualToken[tile] ~= token or heldVisual[tile] or not tile.Parent then
						return
					end
					-- Back to flat rather than to a residual level. Per-tile platforms
					-- keep no residual: that is a honey behaviour, and it lives in the
					-- bone path because only a rig can hold a print without also
					-- holding the collider down.
					offsetVisual(
						tile,
						TweenInfo.new(profile.dip * 2.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
						0
					)
				end)
			end)
		end)
	end

	-- Degrades to the pre-mesh behaviour rather than to something subtly wrong, but
	-- says so once: without the tile meshes imported there is nothing to carry a wave,
	-- and silence here is indistinguishable from the tuning being bad.
	if not drove and not visualWarned then
		visualWarned = true
		warn(
			("DeformationRenderer: %s has no tile meshes, so its ripple has nothing to move. Import the tile meshes into ReplicatedStorage/Assets/TileMeshes; the surface rings still draw without them."):format(
				slab.Name
			)
		)
	end
end

-- Bones are authored pointing along Roblox +Y, so their local Y is up and a
-- negative Y offset presses straight down with no per-bone axis maths.
local function driveBone(tile: BasePart, bone: Bone, info: TweenInfo, sink: number)
	if sink ~= 0 then
		heldSink[bone] = sink
		-- Cancels any ripple mid-flight on this bone, so a wave cannot pull the
		-- surface back up from under a standing player.
		rippleToken[bone] = (rippleToken[bone] or 0) + 1
	else
		heldSink[bone] = nil
	end
	boneOffset(bone, info, sink)
end

-- Leaves (or clears) the impression a foot left behind. Not "held": ripples must
-- still cross a cell holding a print, they just oscillate around it.
local function setResidualBone(bone: Bone, info: TweenInfo, sink: number)
	heldSink[bone] = nil
	residualSink[bone] = if sink ~= 0 then sink else nil
	boneOffset(bone, info, sink)
end

local function setResidual(tile: BasePart, bone: Bone, info: TweenInfo, sink: number)
	setResidualBone(bone, info, sink)

	-- The COLLIDER always comes back to rest here, whatever the visual residual is.
	-- Only an occupied cell sinks. Leaving it down would strand the collider low for
	-- the whole decay window (this path never calls settleTile), and holding it at
	-- the residual would bob the player over every old print they walked back across.
	driveFloor(tile, info, 0)
end

local function moveTile(tile: BasePart, info: TweenInfo, sink: number, scaleXZ: number, scaleY: number)
	-- Skinned platform: the surface is one mesh, so drive its bone and leave the
	-- (invisible) tile alone. Scaling is meaningless here; a bone offset is the
	-- whole deformation.
	local bone = boneFor(tile)
	if bone then
		driveBone(tile, bone, info, sink)
		-- Collision follows a fraction of the visual dent, so the player physically
		-- sinks in rather than standing on top of a depression. The Floor child is
		-- what moves; the tile must not, or it re-triggers its own touch events.
		driveFloor(tile, info, sink * COLLIDER_SINK_FRACTION)
		return
	end

	local base = restCFrame[tile]
	local size = restSize[tile]
	local target = base * CFrame.new(0, sink, 0)

	play(tile, tile, info, {
		CFrame = target,
		Size = Vector3.new(size.X * scaleXZ, size.Y * scaleY, size.Z * scaleXZ),
	})

	local visual, offset = visualOf(tile), visualOffset[tile]
	if visual and offset then
		-- Position follows; the mesh is not squashed with the tile. Scaling a mesh
		-- per frame is expensive and stretching bubbles or drips out of proportion
		-- looks worse than simply letting the cell sink.
		play(tile, visual, info, { CFrame = target * offset })
	end
end

local function settleTile(tile: BasePart, duration: number)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local bone = boneFor(tile)
	if bone then
		driveBone(tile, bone, info, 0)
		-- Collider back to rest with it. Residual prints deliberately do NOT hold the
		-- collider down: walking back across a field of old footprints would bob the
		-- player up and down over marks that are only meant to be seen.
		driveFloor(tile, info, 0)
		return
	end

	play(tile, tile, info, { CFrame = restCFrame[tile], Size = restSize[tile] })

	local visual, offset = visualOf(tile), visualOffset[tile]
	if visual and offset then
		play(tile, visual, info, { CFrame = restCFrame[tile] * offset })
	end
end

-- === Marks (smears / footprints / cracks) ===

local function addMark(tile: BasePart, mark: BasePart, lifetime: number)
	marks[tile] = marks[tile] or {}
	local list = marks[tile]
	table.insert(list, mark)
	-- Hard cap: a player can loiter on one cell indefinitely, and unbounded
	-- decoration parts would be a slow memory and render leak.
	while #list > MAX_MARKS_PER_TILE do
		local oldest = table.remove(list, 1)
		if oldest then
			oldest:Destroy()
		end
	end

	task.delay(lifetime * 0.5, function()
		if mark.Parent then
			TweenService:Create(
				mark,
				TweenInfo.new(lifetime * 0.5, Enum.EasingStyle.Linear),
				{ Transparency = 1 }
			):Play()
		end
	end)
	Debris:AddItem(mark, lifetime + 0.5)
end

local function clearMarks(tile: BasePart)
	local list = marks[tile]
	if not list then
		return
	end
	for _, mark in ipairs(list) do
		mark:Destroy()
	end
	marks[tile] = nil
end

-- Top face of the tile in world space, plus its own orientation.
local function tileTop(tile: BasePart): CFrame
	return restCFrame[tile] * CFrame.new(0, restSize[tile].Y / 2, 0)
end

-- Where the local player's feet are, in the tile's local XZ. Returns nil when
-- the character is not this client's (other players' marks are not drawn: the
-- server does not replicate contact positions, and guessing them would put
-- footprints in the wrong place).
local function localFootOffsets(tile: BasePart): { Vector3 }
	local character = player.Character
	if not character then
		return {}
	end
	local result = {}
	for _, name in ipairs({ "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }) do
		local foot = character:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then
			local localPos = restCFrame[tile]:PointToObjectSpace(foot.Position)
			local half = restSize[tile] * 0.5
			if math.abs(localPos.X) <= half.X + 1 and math.abs(localPos.Z) <= half.Z + 1 then
				table.insert(result, Vector3.new(localPos.X, 0, localPos.Z))
			end
		end
	end
	return result
end

-- World positions of the local player's feet, but only while they are genuinely on
-- this tile.
--
-- Used for ripple centring in preference to localFootOffsets, which returns
-- tile-LOCAL offsets and accepts a foot up to a stud outside the tile. Stepping onto
-- a new cell fires that cell's event while your feet are still partly on the
-- previous one, so the local-offset route pulled ring centres backwards behind you.
-- A world position needs no round trip and lands exactly under the foot.
-- Each hit carries the foot part's own SIZE and HEADING, not just a position.
--
-- The print should be the shape of the thing that made it, and the default avatar's
-- foot is a blocky rounded box roughly 0.72 by 1.24 studs. Guessed dimensions were
-- more than twice that, and a guessed heading taken from the torso ignores that feet
-- splay outward as you walk.
export type FootHit = { position: Vector3, left: boolean, size: Vector3, look: Vector3, distance: number }

local function localFootWorldPoints(tile: BasePart): { FootHit }
	local character = player.Character
	if not character then
		return {}
	end
	local rest = restCFrame[tile]
	local half = restSize[tile] * 0.5
	local result: { FootHit } = {}

	for _, name in ipairs({ "LeftFoot", "RightFoot", "Left Leg", "Right Leg" }) do
		local foot = character:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then
			local localPos = rest:PointToObjectSpace(foot.Position)

			-- OVERLAP, not centre-inside.
			--
			-- Requiring the centre to be strictly inside the cell rejected the very foot
			-- that triggered the event: a foot is about 0.72 by 1.24 studs, so when a cell
			-- first reports deformed the touching foot's centre is usually still over the
			-- previous cell. The list came back empty and everything downstream, rings and
			-- prints alike, silently did nothing.
			--
			-- The margin is half the foot's own extent, so a foot whose BODY overlaps the
			-- cell counts even when its centre has not crossed the boundary yet.
			local margin = math.max(foot.Size.X, foot.Size.Z) * 0.5
			if math.abs(localPos.X) <= half.X + margin and math.abs(localPos.Z) <= half.Z + margin then
				table.insert(result, {
					position = foot.Position,
					left = name:find("Left") ~= nil,
					size = foot.Size,
					look = foot.CFrame.LookVector,
					-- Distance to the cell centre, used to order the results below.
					distance = math.sqrt(localPos.X * localPos.X + localPos.Z * localPos.Z),
				})
			end
		end
	end

	-- Nearest the cell centre first. This is what the earlier tightening was actually
	-- reaching for: with both feet accepted, the ring should centre on whichever one this
	-- cell's event belongs to rather than on whichever the loop happened to see first.
	table.sort(result, function(a, b)
		return a.distance < b.distance
	end)
	return result
end

local function newMarkPart(tile: BasePart, size: Vector3, cframe: CFrame): BasePart
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cframe
	part.Parent = tile.Parent
	return part
end

-- === Cracks ===
--
-- Cracks are DRAWN onto the surface with a SurfaceGui, not built out of parts.
--
-- Every part-based attempt failed for the same structural reason: a box has
-- thickness and side faces that catch light, so it reads as a stick lying on the
-- floor. Thinning it does not fix that, it just makes a thinner stick. And parts
-- positioned by offset from the tile centre can walk past the tile edge, which is
-- how cracks ended up overhanging the platform rim.
--
-- A SurfaceGui Frame has zero thickness and no side faces to catch light, and a
-- ClipsDescendants container makes rendering outside the tile impossible rather
-- than merely unlikely. Both problems were properties of the primitive, so they
-- needed a different primitive.

local crackGuis: { [BasePart]: SurfaceGui } = {}
local CRACK_PPS = 64 -- GUI pixels per stud

local function getCrackCanvas(tile: BasePart): Frame?
	local existing = crackGuis[tile]
	if existing and existing.Parent then
		return existing:FindFirstChild("Clip") :: Frame?
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "CrackOverlay"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = CRACK_PPS
	gui.AlwaysOnTop = false
	gui.ZOffset = 0.02 -- clears the face without z-fighting against it
	gui.Adornee = tile
	gui.Parent = tile

	local clip = Instance.new("Frame")
	clip.Name = "Clip"
	clip.Size = UDim2.fromScale(1, 1)
	clip.BackgroundTransparency = 1
	-- This is what makes escaping the perimeter impossible rather than unlikely.
	clip.ClipsDescendants = true
	clip.Parent = gui

	crackGuis[tile] = gui
	return clip
end

local function clearCracks(tile: BasePart)
	local gui = crackGuis[tile]
	if gui then
		gui:Destroy()
	end
	crackGuis[tile] = nil
end

-- One fracture: a chain of flat segments walked across the face with angle
-- jitter, tapering and fading toward the tip, throwing off the occasional
-- branch. Branches are what separate a fracture from a scratch.
local function drawCrack(
	canvas: Frame,
	wPx: number,
	hPx: number,
	startX: number,
	startY: number,
	heading: number,
	totalPx: number,
	color: Color3,
	thickness: number,
	depth: number
)
	local segments = 4
	local segPx = totalPx / segments
	local x, y = startX, startY
	local angle = heading

	for i = 1, segments do
		angle += (math.random() - 0.5) * 0.7
		local taper = 1 - (i - 1) / segments * 0.55
		local thick = math.max(1, math.floor(thickness * taper + 0.5))

		local midX = x + math.cos(angle) * segPx / 2
		local midY = y + math.sin(angle) * segPx / 2

		local seg = Instance.new("Frame")
		seg.Name = "CrackSeg"
		seg.AnchorPoint = Vector2.new(0.5, 0.5)
		seg.Position = UDim2.fromScale(midX / wPx, midY / hPx)
		seg.Size = UDim2.fromOffset(math.max(2, math.floor(segPx + 0.5)), thick)
		seg.Rotation = math.deg(angle)
		seg.BackgroundColor3 = color
		seg.BackgroundTransparency = 0.1 + (i - 1) * 0.12
		seg.BorderSizePixel = 0
		seg.Parent = canvas

		x += math.cos(angle) * segPx
		y += math.sin(angle) * segPx

		if depth < 1 and i <= 2 and math.random() < 0.5 then
			local turn = (if math.random() < 0.5 then 1 else -1) * (0.6 + math.random() * 0.5)
			drawCrack(canvas, wPx, hPx, x, y, angle + turn, segPx * 1.6, color, thickness * 0.7, depth + 1)
		end
	end
end

local function addCrackNetwork(tile: BasePart, count: number, color: Color3, lifetime: number)
	local canvas = getCrackCanvas(tile)
	if not canvas then
		return
	end
	local size = restSize[tile]
	local wPx, hPx = size.X * CRACK_PPS, size.Z * CRACK_PPS
	local span = math.min(wPx, hPx)

	for _ = 1, count do
		-- Origins in the middle 60% so most of a crack's run lands on the tile.
		-- The clip frame handles anything that still overshoots.
		local sx = wPx * (0.2 + math.random() * 0.6)
		local sy = hPx * (0.2 + math.random() * 0.6)
		drawCrack(canvas, wPx, hPx, sx, sy, math.random() * math.pi * 2, span * (0.28 + math.random() * 0.28), color, 3, 0)
	end

	-- Fade the overlay across the back half of the decay window.
	task.delay(lifetime * 0.5, function()
		if not canvas.Parent then
			return
		end
		for _, seg in ipairs(canvas:GetChildren()) do
			if seg:IsA("Frame") then
				TweenService:Create(
					seg,
					TweenInfo.new(lifetime * 0.5, Enum.EasingStyle.Linear),
					{ BackgroundTransparency = 1 }
				):Play()
			end
		end
	end)
end

-- === Micro-heightfield ===
--
-- A flat decal lying on top of a surface can never read as a dent, because the
-- surface plane is visibly unbroken. To get real displacement each granular tile
-- is overlaid with a MICRO_DIV x MICRO_DIV grid of thin plates, and the plate
-- under your foot is pushed down and darkened. The plates are about a stud
-- across, so one pressed plate is footprint-scale rather than tile-scale, which
-- is what keeps it from reading as another sinking square.
--
-- Plates are cosmetic and non-colliding: the parent tile stays the collision
-- surface, so pressing them cannot desync the player from the floor.

local MICRO_DIV = 3
local MICRO_THICKNESS = 0.34
local microTiles: { [BasePart]: { BasePart } } = {}
local microRest: { [BasePart]: CFrame } = {}

-- Hard ceiling on plates across the whole session. A player can walk every cell
-- of every granular platform, and 9 parts per tile adds up.
local microBudget = 900

local function ensureMicroTiles(tile: BasePart, materialName: string): { BasePart }?
	local existing = microTiles[tile]
	if existing then
		return existing
	end
	-- Skipped entirely when any mesh is drawing this tile. The plates were a stand-in
	-- for real surface geometry; laid over a mesh they would float above the actual
	-- visible surface, and the mesh already provides the relief they were faking.
	--
	-- The skinned check matters separately: on a skinned platform the mesh hangs off
	-- the SLAB, not the tile, so visualOf() sees nothing and plates would be built
	-- on an invisible tile and left hovering over the real surface.
	if visualOf(tile) or boneFor(tile) then
		return nil
	end
	if microBudget < MICRO_DIV * MICRO_DIV then
		return nil
	end
	microBudget -= MICRO_DIV * MICRO_DIV

	local size = restSize[tile]
	local top = tileTop(tile)
	local cellX, cellZ = size.X / MICRO_DIV, size.Z / MICRO_DIV
	local list: { BasePart } = {}

	for row = 1, MICRO_DIV do
		for col = 1, MICRO_DIV do
			local cx = -size.X / 2 + (col - 0.5) * cellX
			local cz = -size.Z / 2 + (row - 0.5) * cellZ
			local plate = Instance.new("Part")
			plate.Name = ("Micro_%d_%d"):format(col, row)
			plate.Size = Vector3.new(cellX - 0.06, MICRO_THICKNESS, cellZ - 0.06)
			plate.CFrame = top * CFrame.new(cx, MICRO_THICKNESS / 2, cz)
			plate.Anchored = true
			plate.CanCollide = false
			plate.CanTouch = false
			plate.CanQuery = false
			plate.CastShadow = false
			MaterialAppearance.apply(plate, materialName)
			plate.Parent = tile
			microRest[plate] = plate.CFrame
			list[(row - 1) * MICRO_DIV + col] = plate
		end
	end

	microTiles[tile] = list
	return list
end

-- Pushes the plate under a local XZ offset down by `depth`, darkened to sell the
-- shadow of a real recess.
local function pressMicro(tile: BasePart, list: { BasePart }, offset: Vector3, depth: number, tint: number)
	local size = restSize[tile]
	local col = math.clamp(math.floor((offset.X + size.X / 2) / (size.X / MICRO_DIV)) + 1, 1, MICRO_DIV)
	local row = math.clamp(math.floor((offset.Z + size.Z / 2) / (size.Z / MICRO_DIV)) + 1, 1, MICRO_DIV)
	local plate = list[(row - 1) * MICRO_DIV + col]
	if not plate then
		return
	end
	local rest = microRest[plate]
	if not rest then
		return
	end
	local info = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(plate, info, {
		CFrame = rest * CFrame.new(0, -depth, 0),
		Color = plate.Color:Lerp(Color3.new(0, 0, 0), tint),
	}):Play()
end

local function releaseMicro(tile: BasePart, materialName: string, duration: number)
	local list = microTiles[tile]
	if not list then
		return
	end
	local restColor = MaterialAppearance.Appearances[materialName]
	for _, plate in ipairs(list) do
		local rest = microRest[plate]
		if rest and plate.Parent then
			TweenService:Create(
				plate,
				TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ CFrame = rest, Color = restColor and restColor.color or plate.Color }
			):Play()
		end
	end
end

-- === Surface ripple rings ===
--
-- Expanding circle OUTLINES spreading from the footfall, staggered so several
-- travel outward at once.
--
-- A filled disc cannot read as a ripple no matter how it is animated: it is a
-- circle appearing and vanishing in place. A ripple is a thin ring that travels.
-- Roblox parts have no ring primitive, so these are drawn instead: a Frame with a
-- UICorner of 0.5 is a circle, and giving it a UIStroke with a transparent
-- background leaves only the outline.
--
-- The canvas is one invisible plate per platform, sitting a hair above the surface
-- and spanning the whole thing, so rings can travel well past the cell that spawned
-- them. Drawing on the tile's own face would clip them at 1.6 studs.

-- How many rings a footfall leaves, how far apart, and how far they travel all come
-- from the material's RippleProfile: a train of rings is water, implying the surface
-- is still oscillating after the impact has passed, so honey spawns exactly one and
-- slime spawns three.
local RING_START = 0.8       -- studs diameter
local RIPPLE_PPS = 22        -- GUI pixels per stud

-- Surface-GUI axis convention for Face = Top, established by observation rather
-- than assumption.
--
-- Roblox rotates the GUI 90 degrees on the top face: its X axis runs along the
-- part's Z and its Y axis along the part's X. So the mapping needs a TRANSPOSE,
-- not a flip.
--
-- The giveaway was that one corner rendered correctly while the corner adjacent to
-- it landed at the opposite adjacent corner. That is a reflection about the
-- diagonal, and the diagonal's endpoints are exactly the fixed points of a
-- transpose, which is why flipping the axes independently could never fix it and
-- why one corner looked right through several attempts.
local RING_U_FLIP = false
local RING_V_FLIP = true
local RING_SWAP_UV = true

local rippleCanvas: { [BasePart]: Frame } = {}

local function ensureRippleCanvas(slab: BasePart, tile: BasePart): Frame?
    local existing = rippleCanvas[slab]
    if existing and existing.Parent then
        return existing
    end

    -- Height taken from the tile's own top face, so the plate lands on the walkable
    -- plane rather than on a guessed offset.
    local topCF = restCFrame[tile] * CFrame.new(0, restSize[tile].Y / 2, 0)
    local localTop = slab.CFrame:ToObjectSpace(topCF)

    local plate = Instance.new("Part")
    plate.Name = "RippleCanvas"
    plate.Size = Vector3.new(slab.Size.X, 0.05, slab.Size.Z)
    plate.CFrame = slab.CFrame * CFrame.new(0, localTop.Position.Y + 0.06, 0)
    plate.Anchored = true
    plate.CanCollide = false
    plate.CanTouch = false
    plate.CanQuery = false
    plate.CastShadow = false
    plate.Transparency = 1 -- a SurfaceGui still draws on a fully transparent part
    plate.Parent = slab

    local gui = Instance.new("SurfaceGui")
    gui.Name = "RippleGui"
    gui.Face = Enum.NormalId.Top
    gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
    gui.PixelsPerStud = RIPPLE_PPS
    gui.AlwaysOnTop = false
    gui.ZOffset = 0.01
    gui.Adornee = plate
    gui.Parent = plate

    local canvas = Instance.new("Frame")
    canvas.Name = "Canvas"
    canvas.Size = UDim2.fromScale(1, 1)
    canvas.BackgroundTransparency = 1
    canvas.ClipsDescendants = true
    canvas.Parent = gui

    rippleCanvas[slab] = canvas
    return canvas
end

-- World point to canvas UV. The single place the surface-GUI axis convention lives.
local function canvasUV(slab: BasePart, worldPoint: Vector3): (number, number)
    local localPoint = slab.CFrame:PointToObjectSpace(worldPoint)
    local u = (localPoint.X + slab.Size.X / 2) / slab.Size.X
    local v = (localPoint.Z + slab.Size.Z / 2) / slab.Size.Z
    if RING_U_FLIP then
        u = 1 - u
    end
    if RING_V_FLIP then
        v = 1 - v
    end
    -- Swap LAST: the transpose is applied to the already-oriented pair, which is
    -- what makes the bottom-left corner (correct before this change) stay correct.
    if RING_SWAP_UV then
        u, v = v, u
    end
    return u, v
end

-- === Growing cracks ===
--
-- addCrackNetwork draws a set of cracks all at once wherever they happen to fall, and that is right for
-- salt, whose crust is pushed from underneath and cracks all over. Soap and charcoal break UNDER A FOOT,
-- and lines appearing whole in a random corner did not say that. Soap was worse: it drew a fresh nine
-- every time a cell was stepped on, until a busy cell was a scribble, and they went on hanging in the
-- air over cubes that had already fallen out.
--
-- These GROW. A crack starts at the foot that made it and runs out a segment at a time; a later step runs
-- the cracks already there further instead of drawing new ones on top, and one surface holds only so
-- many. Every segment knows where it is, so a piece of the surface falling out takes the cracks over it,
-- and the ones at the rim of the hole open up.
--
-- Drawn on the same overlay as addCrackNetwork, so clearCracks still clears them. Positions are studs in
-- the plane of the SurfaceGui: `x` runs along the part's Z and `y` along its X, the transpose canvasUV
-- describes. One table rather than a family of locals, for the module's register budget.
local Fissure = {}
do
	local SEG = 0.42 -- studs a segment
	local JAG = 0.5 -- radians a crack can wander at each joint
	local CAP = 48 -- segments one surface holds; past that its cracks only open wider
	local runs = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: any }

	-- The cracks on a surface, unless its overlay has been cleared since they were drawn.
	local function current(tile: BasePart): any
		local run = runs[tile]
		if run and run.gui == crackGuis[tile] and run.gui.Parent then
			return run
		end
		return nil
	end

	local function runFor(tile: BasePart): any
		local run = current(tile)
		if run then
			return run
		end
		local gui = crackGuis[tile]
		if not gui or not gui.Parent then
			getCrackCanvas(tile)
			gui = crackGuis[tile]
		end
		local clip = if gui then gui:FindFirstChild("Clip") else nil
		local part = if gui then gui.Adornee else nil
		if not clip or not part or not part:IsA("BasePart") then
			return nil
		end
		run = { gui = gui, clip = clip, part = part, segs = {}, tips = {}, color = Color3.new(0, 0, 0) }
		runs[tile] = run
		return run
	end

	local function thicken(seg: any, factor: number, time: number)
		seg.thick *= factor
		TweenService:Create(seg.frame, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(math.floor(seg.length * CRACK_PPS + 1.5), math.max(1, math.floor(seg.thick + 0.5))),
		}):Play()
	end

	-- One segment from (x0, y0) to (x1, y1), `delay` seconds from now, at `speed` studs a second. It starts
	-- as a point and runs out to its length. A GuiObject turns about its centre, so the centre travels
	-- with the growing end, half as far over the same time.
	local function lay(run: any, x0: number, y0: number, x1: number, y1: number, thick: number, delay: number,
		speed: number)
		local wide, high = run.part.Size.Z, run.part.Size.X
		local length = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
		local px = math.max(1, math.floor(thick + 0.5))
		local frame = Instance.new("Frame")
		frame.Name = "CrackSeg"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = run.color
		frame.BackgroundTransparency = 0.05
		frame.Rotation = math.deg(math.atan2(y1 - y0, x1 - x0))
		frame.Position = UDim2.fromScale(x0 / wide, y0 / high)
		frame.Size = UDim2.fromOffset(0, px)
		frame.Parent = run.clip
		local time = length / speed
		TweenService:Create(frame, TweenInfo.new(time, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, delay), {
			Position = UDim2.fromScale((x0 + x1) / 2 / wide, (y0 + y1) / 2 / high),
			-- A pixel and a half over, so the joints meet instead of leaving a gap at every bend.
			Size = UDim2.fromOffset(math.floor(length * CRACK_PPS + 1.5), px),
		}):Play()
		table.insert(run.segs, {
			frame = frame,
			x = (x0 + x1) / 2,
			y = (y0 + y1) / 2,
			length = length,
			thick = thick,
			ready = os.clock() + delay + time,
		})
	end

	-- One crack from (x, y) heading `angle`, about `reach` studs, laid from `delay` on at `speed`. It thins
	-- as it goes and may split; where it stops short of the edge its tip is kept, so a later step can run
	-- it further. Returns when its last segment lands.
	local function walk(run: any, x: number, y: number, angle: number, reach: number, thick: number,
		delay: number, speed: number, splits: number): number
		local wide, high = run.part.Size.Z, run.part.Size.X
		local steps = math.max(1, math.floor(reach / SEG + 0.5))
		local at = delay
		for index = 1, steps do
			if #run.segs >= CAP then
				break
			end
			angle += (math.random() - 0.5) * JAG
			local nx, ny = x + math.cos(angle) * SEG, y + math.sin(angle) * SEG
			lay(run, x, y, nx, ny, thick, at, speed)
			at += SEG / speed
			x, y = nx, ny
			if x <= 0 or y <= 0 or x >= wide or y >= high then
				-- THROUGH TO THE EDGE, with nowhere further to run.
				return at
			end
			thick = math.max(1, thick * 0.92)
			if splits > 0 and index < steps and math.random() < 0.35 then
				splits -= 1
				local turn = (if math.random() < 0.5 then 1 else -1) * (0.5 + math.random() * 0.5)
				walk(run, x, y, angle + turn, reach * 0.5, thick * 0.75, at, speed, 0)
			end
		end
		table.insert(run.tips, { x = x, y = y, angle = angle, thick = thick, ready = os.clock() + at })
		return at
	end

	function Fissure.has(tile: BasePart): boolean
		local run = current(tile)
		return run ~= nil and #run.segs > 0
	end

	-- Where a player's cracks start: this client's own foot on the surface, or anyone else's root.
	function Fissure.footOf(tile: BasePart, who: Player?): Vector3?
		if who == player then
			local feet = localFootWorldPoints(tile)
			if feet[1] then
				return feet[1].position
			end
		end
		local character = if who then who.Character else nil
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root.Position else nil
	end

	-- NEW CRACKS from `options.from`, a world point (nil is somewhere near the middle): `arms` of them
	-- spread round it, each about `reach` studs and `thick` pixels, at `speed` studs a second, allowed
	-- `splits` branches each. `color` is kept for everything drawn on this surface after.
	function Fissure.grow(tile: BasePart, options: any)
		local run = runFor(tile)
		if not run then
			return
		end
		run.color = options.color or run.color
		local wide, high = run.part.Size.Z, run.part.Size.X
		local u, v = 0.3 + math.random() * 0.4, 0.3 + math.random() * 0.4
		if options.from then
			u, v = canvasUV(run.part, options.from)
		end
		-- A little in from the edge, so a foot on the rim still sends its cracks across the surface.
		local x, y = math.clamp(u, 0.1, 0.9) * wide, math.clamp(v, 0.1, 0.9) * high
		-- AIMED INWARD from off-centre. Spread evenly round a start by the edge, one crack runs straight off
		-- the surface and the rest look scattered; fanned toward the middle they run across it. The fan
		-- closes from a full circle at the centre to about half of one at the rim.
		local inX, inY = wide / 2 - x, high / 2 - y
		local off = math.clamp(math.sqrt(inX * inX + inY * inY) / (0.5 * math.min(wide, high)), 0, 1)
		local turn = if off > 0.15 then math.atan2(inY, inX) else math.random() * math.pi * 2
		local spread = math.pi * 2 * (1 - 0.5 * off)
		local arms = options.arms or 3
		for index = 1, arms do
			local share = if arms > 1 then (index - 1) / (arms - 1) - 0.5 else 0
			local angle = turn + share * spread * (arms - 1) / arms + (math.random() - 0.5) * 0.6
			walk(run, x, y, angle, (options.reach or 1) * (0.75 + math.random() * 0.5), options.thick or 3, 0,
				options.speed or 5, options.splits or 1)
		end
	end

	-- THE CRACKS RUN ON: every live tip goes `reach` further, once its own crack has finished growing.
	function Fissure.extend(tile: BasePart, reach: number, speed: number)
		local run = current(tile)
		if not run then
			return
		end
		local tips = run.tips
		run.tips = {}
		local now = os.clock()
		for _, tip in ipairs(tips) do
			walk(run, tip.x, tip.y, tip.angle, reach, tip.thick, math.max(0, tip.ready - now), speed,
				if math.random() < 0.35 then 1 else 0)
		end
	end

	-- THEY OPEN: every crack that has finished growing thickens by `factor`, and so will their tips.
	function Fissure.widen(tile: BasePart, factor: number, time: number)
		local run = current(tile)
		if not run then
			return
		end
		local now = os.clock()
		for _, seg in ipairs(run.segs) do
			if seg.ready <= now and seg.frame.Parent then
				thicken(seg, factor, time)
			end
		end
		for _, tip in ipairs(run.tips) do
			tip.thick *= factor
		end
	end

	-- THEY CHANGE COLOUR, the ones drawn and the ones still to come.
	function Fissure.tint(tile: BasePart, color: Color3, time: number)
		local run = current(tile)
		if not run then
			return
		end
		run.color = color
		for _, seg in ipairs(run.segs) do
			if seg.frame.Parent then
				TweenService:Create(seg.frame, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ BackgroundColor3 = color }):Play()
			end
		end
	end

	-- THE GLOW BREATHES, on an overlay drawn unlit (charcoal's): its brightness swings between `low` and
	-- `high` every `period`. Called with nothing after the surface, it stops.
	function Fissure.glow(tile: BasePart, low: number?, high: number?, period: number?)
		local run = current(tile)
		if not run then
			return
		end
		run.glowToken = (run.glowToken or 0) + 1
		if run.breathing then
			run.breathing:Cancel()
			run.breathing = nil
		end
		run.breath = nil
		if not (low and high and period) then
			return
		end
		run.breath = { low, high, period }
		run.gui.Brightness = low
		local breathing = TweenService:Create(run.gui,
			TweenInfo.new(period, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Brightness = high })
		breathing:Play()
		run.breathing = breathing
	end

	-- A FLARE: the glow jumps to `peak`, falls back over `time`, and breathes again as it was.
	function Fissure.flare(tile: BasePart, peak: number, time: number)
		local run = current(tile)
		if not run then
			return
		end
		local breath = run.breath
		if run.breathing then
			run.breathing:Cancel()
			run.breathing = nil
		end
		local token = (run.glowToken or 0) + 1
		run.glowToken = token
		run.gui.Brightness = peak
		TweenService:Create(run.gui, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = if breath then breath[1] else 1 }):Play()
		task.delay(time, function()
			if breath and run.glowToken == token and current(tile) == run then
				Fissure.glow(tile, breath[1], breath[2], breath[3])
			end
		end)
	end

	-- A PIECE OF THE SURFACE FALLS OUT: the cracks drawn over `piece` go with it, and the cracks round the
	-- hole it leaves open up. `piece` has to sit square to the surface, as soap's cubes do.
	function Fissure.shatter(tile: BasePart, piece: BasePart)
		local run = current(tile)
		if not run then
			return
		end
		local u, v = canvasUV(run.part, piece.Position)
		local cx, cy = u * run.part.Size.Z, v * run.part.Size.X
		local halfX, halfY = piece.Size.Z / 2, piece.Size.X / 2
		local now = os.clock()
		local kept = {}
		for _, seg in ipairs(run.segs) do
			local dx, dy = math.abs(seg.x - cx), math.abs(seg.y - cy)
			if dx <= halfX and dy <= halfY then
				seg.frame:Destroy()
			else
				if dx <= halfX + SEG and dy <= halfY + SEG and seg.ready <= now and seg.frame.Parent then
					thicken(seg, 1.6, 0.12)
				end
				table.insert(kept, seg)
			end
		end
		run.segs = kept
		local tips = {}
		for _, tip in ipairs(run.tips) do
			if math.abs(tip.x - cx) > halfX or math.abs(tip.y - cy) > halfY then
				table.insert(tips, tip)
			end
		end
		run.tips = tips
	end

	-- THE CRACKS CLOSE: they fade over `time` and the overlay goes with them. Anything cracking this
	-- surface in the meantime starts a new overlay rather than drawing onto one on its way out.
	function Fissure.heal(tile: BasePart, time: number)
		local gui = crackGuis[tile]
		runs[tile] = nil
		if not gui then
			return
		end
		crackGuis[tile] = nil
		local clip = gui:FindFirstChild("Clip")
		if clip then
			for _, child in ipairs(clip:GetChildren()) do
				if child:IsA("Frame") then
					TweenService:Create(child, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{ BackgroundTransparency = 1 }):Play()
				end
			end
		end
		Debris:AddItem(gui, time + 0.05)
	end
end

local function spawnRipple(
    slab: BasePart,
    tile: BasePart,
    worldPoint: Vector3,
    colour: Color3,
    profile: RippleProfile
)
    local canvas = ensureRippleCanvas(slab, tile)
    if not canvas then
        return
    end

    local u, v = canvasUV(slab, worldPoint)
    local travel = ringTravel(profile)

    for index = 1, profile.rings do
        task.delay((index - 1) * profile.ringStagger, function()
            if not canvas.Parent then
                return
            end

            local ring = Instance.new("Frame")
            ring.Name = "Ripple"
            ring.AnchorPoint = Vector2.new(0.5, 0.5)
            ring.Position = UDim2.fromScale(u, v)
            ring.Size = UDim2.fromOffset(RING_START * RIPPLE_PPS, RING_START * RIPPLE_PPS)
            ring.BackgroundTransparency = 1
            ring.BorderSizePixel = 0
            ring.Parent = canvas

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0.5, 0)
            corner.Parent = ring

            local stroke = Instance.new("UIStroke")
            stroke.Color = colour
            -- Later rings start fainter, which reads as the wave losing energy.
            stroke.Transparency = 0.35 + (index - 1) * 0.15
            stroke.Thickness = 4 - (index - 1)
            stroke.Parent = ring

            local size = profile.ringEnd * RIPPLE_PPS
            TweenService:Create(
                ring,
                TweenInfo.new(travel, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { Size = UDim2.fromOffset(size, size) }
            ):Play()

            -- Thinning as it expands: a real wavefront spreads its energy over a
            -- longer circumference, so it gets fainter the further it goes.
            TweenService:Create(
                stroke,
                TweenInfo.new(travel, Enum.EasingStyle.Linear),
                { Transparency = 1, Thickness = 1 }
            ):Play()

            Debris:AddItem(ring, travel + 0.1)
        end)
    end
end

-- === Footprints ===
--
-- A MeshPart, not a drawn GUI shape.
--
-- The GUI version had the right silhouette but could never look right: GUI elements are
-- UNLIT. They take no lighting, have no Material and no Reflectance, so on a glossy
-- honey surface a drawn print reads as a flat sticker whatever colour it is given. As a
-- part it takes the material's own appearance and catches the same specular highlight as
-- the surface around it.
--
-- Two things come back for free. The print sits DOWN in the depression again, which the
-- GUI version had to give up because a SurfaceGui is a flat plane above the surface. And
-- there is no canvas UV mapping or rotation derivation involved: it is placed in world
-- space, so the surface-GUI axis convention that caused so much trouble is irrelevant
-- here.
--
-- The mesh (blender/gen_footprint.py) is a stadium with one flat end: straight sides, a
-- semicircular toe, a square heel, dished in the middle. Per-corner rounding is not
-- expressible on any Roblox primitive, so the shape has to be authored.

-- Must match the generator's WIDTH / LENGTH / bbox height, or prints come out mis-scaled.
-- How much larger than the foot the print is.
--
-- Two reasons it exceeds 1: material squeezes out sideways under load, and the avatar
-- wears SHOES. foot.Size is the bare foot part; the sole that actually meets the ground
-- is wider than it.
--
-- This declaration was lost when the footprint section was rewritten from GUI frames to a
-- MeshPart, while spawnFootprint kept using it. It resolved to a nil global, so
-- hit.size.X * FOOT.PRINT_SPREAD threw on every single step.
-- Footprint mesh and placement. ONE table rather than a family of separate top-level locals: this
-- module runs close to Luau's 200-register limit for a single scope, and constants
-- are the cheapest thing to fold. Every name and comment below is unchanged.
local FOOT = {}
FOOT.PRINT_SPREAD = 1.34

FOOT.MESH_NAME = "Footprint_Sole"
FOOT.MESH_WIDTH = 1.0
FOOT.MESH_LENGTH = 1.7
FOOT.MESH_HEIGHT = 0.52

-- How far the print's rim sits ABOVE the undeformed surface.
--
-- Small and POSITIVE, which is the fix for the print being invisible. It was previously
-- placed relative to hit.position.Y, but that is the foot part's CENTRE, about 0.41 studs
-- above the ground; sinking 0.53 below that put the rim roughly 0.12 studs UNDER the
-- honey surface, and the honey mesh is nearly opaque at 0.10 transparency, so the print
-- was inside it and could not be seen.
--
-- Sitting proud of the surface also cannot be wrong as the cell deforms: the surface only
-- ever moves DOWN from here, so the print is progressively revealed rather than swallowed.
FOOT.LIFT = 0.08
-- Nearly solid. At 0.32 the print was translucent honey sitting on honey, which is close
-- to no print at all.
FOOT.TRANSPARENCY = 0.12
-- MUCH less reflective than the honey around it (0.38).
--
-- This is what makes the print visible while keeping the colour contrast low, which is
-- otherwise a contradiction: matching the surface's material AND its hue leaves nothing
-- to distinguish. Depressed material is duller than the smooth surface it sits in, so the
-- print reads as a change in surface QUALITY rather than as a patch of different colour.
-- It also stops the print mirroring the sky, which was washing it out toward the honey.
FOOT.REFLECTANCE = 0.08

-- How the print closes up: honey flows in from the edges and the hollow becomes
-- shallower, so the mark SHRINKS and FLATTENS rather than fading. Fading out is a mark
-- being erased; seeping is a hollow being filled, and the difference is that one is
-- opacity and the other is geometry.
local SEEP_SHRINK = 0.18    -- final footprint of the mark, as a fraction of full size
local SEEP_FLATTEN = 0.06   -- final dish depth, as a fraction of full depth
-- The last stretch fades what is left. Without it the shrunken remnant would still be
-- visible when Debris removes it, which pops.
local SEEP_FADE_AT = 0.72

-- Per-material print. `depth` scales the hollow's height, and it is the whole reason
-- this is a table: slime takes the same print as honey but SHALLOWER, because slime
-- is elastic and pushes back where honey simply gives way. A honey-depth print in
-- slime reads as the wrong substance more loudly than any colour would.
--
-- `transparency` tracks each material's own surface (honey 0.10, slime 0.30) and
-- `reflectance` sits well BELOW it (honey's surface is 0.38, slime's 0.12). That gap
-- is what makes a print readable without colour contrast: depressed material is
-- duller than the smooth surface around it, so the mark reads as a change in surface
-- quality rather than as a patch of different colour. `tint` stays in the 0.20-0.30
-- band for the same reason -- far enough to darken, not far enough to look painted.
export type FootprintProfile = {
	depth: number,
	transparency: number,
	reflectance: number,
	tint: number,
	-- Which sole to stamp. Absent means the plain dished one.
	mesh: string?,
	-- Whether the hollow closes over its lifetime. A viscous material flows back in; a
	-- granular one does not, and animating sand shut is what made it read as soft.
	seep: boolean?,
	-- For a non-seeping print: the fraction of its depth it settles to, once, and then
	-- holds. A cohesive material sags a little under its own weight and stops.
	slump: number?,
	-- Never expires. Retired by a per-material budget rather than a timer, so tracks
	-- survive the cell decaying underneath them.
	permanent: boolean?,
}

-- SAND DOES NOT HEAL. Every other material here recovers on the server's decay timer,
-- and sand should not: the pleasure of the stuff is crossing a platform and looking back
-- at where you have been, which a seven-second reset destroys. This is all client-local,
-- so the tracks are the local player's own and cost nothing to anyone else.
--
-- A LIFETIME IS REPLACED BY A BUDGET. "Permanent" and "unbounded" are the same thing
-- without one, and a player can cross every sand cell of every sand platform: prints
-- would accumulate for as long as the level runs. The oldest is retired when the cap is
-- reached, so the tracks behind you fade from the far end rather than all at once.
-- Kinetic sand: the bowl, the berm and the stamped sole. ONE table rather than a family of separate top-level locals: this
-- module runs close to Luau's 200-register limit for a single scope, and constants
-- are the cheapest thing to fold. Every name and comment below is unchanged.
local SAND = {}
SAND.PRINT_LIFE = 1e6
SAND.PRINT_CAP = 90
local sandPrints: { { part: BasePart, tile: BasePart } } = {}

local function retireOldestPrint()
	while #sandPrints > SAND.PRINT_CAP do
		local oldest = table.remove(sandPrints, 1)
		if oldest and oldest.part.Parent then
			TweenService:Create(oldest.part, TweenInfo.new(1.2), { Transparency = 1 }):Play()
			Debris:AddItem(oldest.part, 1.4)
		end
	end
end

local FootprintProfiles: { [string]: FootprintProfile } = {
	Honey = { depth = 1.00, transparency = 0.12, reflectance = 0.08, tint = 0.24, seep = true },
	Slime = { depth = 0.55, transparency = 0.30, reflectance = 0.03, tint = 0.22, seep = true },
	-- SAND WAS NOT IN THIS TABLE AT ALL, which is why the one material whose whole
	-- identity is holding a footprint was the only one that never stamped one. It had a
	-- grid of little square plates pressing down instead.
	--
	-- Deepest of the three, and it does NOT seep: the print stays exactly as it was made
	-- until the cell decays. It also stamps its own sole, the one with a berm of
	-- displaced material around the rim.
	-- THE NAP MARK, and it is a GLOSS mark rather than a colour one.
	--
	-- Every other print here is a dent with a tint: honey and slime seep, sand keeps a
	-- sole with a berm round it. Brushed velvet is not a dent at all -- the hairs are bent
	-- over, and bent hairs reflect differently from upright ones. So the depth is almost
	-- nothing, the reflectance is the highest in this table, and the tint is small and
	-- toward the darker green the blade shows when the silver nap is pressed aside.
	--
	-- `permanent`, like sand's, because a brushed nap does not recover on its own. What
	-- clears it is the server decaying the cell after decayDuration, which is six seconds
	-- -- long enough to look back and see the whole line you walked.
	LambsEar = {
		depth = 0.30,
		transparency = 0.42,
		reflectance = 0.16,
		tint = 0.18,
		seep = false,
		permanent = true,
	},
	-- CLAY KEEPS EVERYTHING. Deeper than sand's print and with a harder edge, because wet
	-- clay takes a sharp impression where sand's collapses inward as it is made -- and
	-- unlike sand's it is never cleared by the cell failing, because clay never fails. The
	-- server holds the cell for 600 seconds, so in practice these last the whole session
	-- and a clay platform accumulates every route every player took across it.
	Clay = {
		depth = 1.15,
		transparency = 0,
		reflectance = 0.02,
		tint = 0.30,
		seep = false,
		slump = 0.94,
		permanent = true,
	},
	-- Grease does not take a print, it takes a SMEAR: shallow, glossy and short-lived,
	-- because warm wax closes over its own mark. The lowest depth in this table by a long
	-- way, and the only one that seeps.
	ButterWax = {
		depth = 0.42,
		transparency = 0.30,
		reflectance = 0.16,
		tint = 0.14,
		seep = true,
	},
	-- MEMORY FOAM, and the print is the whole reason the material is called that. Deep and
	-- soft-edged, and it outlives the cell's own five second decay so the hollow is the last
	-- thing to go -- which is exactly what memory foam does.
	Foam = {
		depth = 1.25,
		transparency = 0.18,
		reflectance = 0,
		tint = 0.16,
		seep = false,
		slump = 0.90,
	},
	-- A print in something that is melting. Glossy, and it seeps -- the mark closes over as
	-- the chocolate keeps softening, which no other print here does.
	Chocolate = {
		depth = 0.85,
		transparency = 0.12,
		reflectance = 0.22,
		tint = 0.26,
		seep = true,
	},
	-- Deeper than jello and completely opaque. Dough takes a real print rather than a trace,
	-- and there is no transparency to inherit -- you cannot see into a Needoh, so a hollow in
	-- one is read entirely by its shading. That puts all the work on tint, which is why it is
	-- the highest here.
	--
	-- It still seeps. A NeeDoh does close back over a dent -- slowly, and because the skin
	-- pulls it back rather than because anything flows -- but the animation is the same
	-- animation and inventing a second one to express the difference would be inventing it
	-- for nobody: at this size the two are indistinguishable on screen.
	-- Shallow and glassy: a keycap does not take a print, it goes down and comes back. The
	-- entry exists so the fallback to Honey's deep viscous hollow never happens here.
	LavaKeys = {
		depth = 0.22,
		transparency = 0.10,
		reflectance = 0.06,
		tint = 0.40,
		seep = true,
	},
	-- The deepest print in the table, and the only one that barely closes. Butter at room
	-- temperature takes the shape of whatever pressed it and keeps it.
	ButterStick = {
		depth = 0.86,
		transparency = 0,
		reflectance = 0.02,
		tint = 0.34,
		seep = false,
		slump = 0.88,
	},
	Needoh = {
		depth = 0.72,
		transparency = 0,
		reflectance = 0.04,
		tint = 0.30,
		seep = true,
	},
	-- Jelly barely holds anything: it springs back almost at once, so the print is a trace
	-- rather than a dent and the highest transparency in the table.
	JelloSoda = {
		depth = 0.55,
		transparency = 0.42,
		reflectance = 0.10,
		tint = 0.20,
		seep = true,
	},
	-- SNOW TAKES THE BEST PRINT OF ANYTHING HERE, and it is the one material where that is
	-- the popular image of it rather than a design decision -- a line of footprints across
	-- fresh snow is the picture everybody already has.
	--
	-- Deeper than clay and with a harder edge than sand. Sand's print collapses inward as it
	-- is made, which is why its `slump` is 0.86; snow packs against the sole instead and
	-- holds a crisp rim, so it slumps barely at all. Not `permanent` though, unlike clay and
	-- sand: this chunk is melting, and a print that outlived the snow around it would be the
	-- one thing on the platform that was not going anywhere.
	Snow = {
		depth = 1.45,
		transparency = 0,
		reflectance = 0.03,
		tint = 0.20,
		seep = false,
		slump = 0.96,
		permanent = false,
	},
	KineticSand = {
		depth = 1.30,
		transparency = 0,
		reflectance = 0,
		tint = 0.26,
		mesh = "Footprint_Sand",
		seep = false,
		slump = 0.86,
		permanent = true,
	},
}

-- Reported once if a footfall produces no usable foot. Without this the whole footprint
-- path can be skipped in complete silence, which is exactly what happened: no prints, no
-- rings, and no warning because the code that would warn was never reached.
local noFeetWarned = false

-- Cached PER NAME now that there is more than one sole. A single slot cached whichever
-- mesh was asked for first and then handed it to every material after, so the second
-- sole would silently never appear.
local footTemplates: { [string]: BasePart } = {}
local footTemplatesChecked: { [string]: boolean } = {}

local function footprintTemplate(meshName: string?): BasePart?
    local name = meshName or FOOT.MESH_NAME
    if footTemplatesChecked[name] then
        return footTemplates[name]
    end
    footTemplatesChecked[name] = true

    local assets = ReplicatedStorage:FindFirstChild("Assets")
    local folder = assets and assets:FindFirstChild("TileMeshes")
    local found = folder and folder:FindFirstChild(name)
    -- The importer commonly wraps a MeshPart in a Model, same as the tile meshes.
    if found and not found:IsA("BasePart") then
        found = found:FindFirstChildWhichIsA("BasePart", true)
    end

    if found and found:IsA("BasePart") then
        footTemplates[name] = found
    else
        warn(
            ("DeformationRenderer: no '%s' in ReplicatedStorage.Assets.TileMeshes; those footprints are disabled. Import meshes/%s.obj."):format(
                name,
                name
            )
        )
    end
    return footTemplates[name]
end

-- ONE print, closing as a single hollow.
--
-- REVERTED from four pooled dishes that closed on staggered windows. That was a better
-- model of how honey actually fills a hollow (shallow parts first, the print breaking into
-- islands, the deepest part last) but it read worse, and it cost four parts per print
-- instead of one. The pool table is preserved in git history if it is ever wanted.

-- `sink` lowers the print below the walkable plane, for a material whose surface has
-- ALREADY given way under it. Sand's rig opens a shallow bowl first, and a sole stamped
-- at plane height would then float over the hollow it is supposed to be lying in.
-- WHERE THE SURFACE ACTUALLY IS under a point, rather than where one flat plane says.
--
-- A footprint used to be placed on its own tile's top face, which is a single height for the
-- whole cell. That was invisible while every rigged platform was nearly flat and became
-- obvious the moment they were sculpted: prints stood clear of the snow and hung off the
-- side of the honey dome.
--
-- THE NEIGHBOURING TILES ARE THE SURFACE. Each cell's collider is placed at that cell's own
-- height (SkinnedSpec.drops in ChunkBuilder), so the tile tops across a platform already
-- describe its shape at collider resolution -- and collider resolution is the right answer
-- here by definition, because a print that sits on the collider is a print that sits where
-- you are standing.
--
-- Bones were the obvious first idea and are wrong: a Cell_ bone's head is at a CONSTANT
-- height in the armature, not on the surface. Every bone on a platform is at the same Y at
-- rest, so weighting them would have produced one flat plane in place of another.
local function tileTopY(part: BasePart): number
	local rest = restCFrame[part] or part.CFrame
	local size = restSize[part] or part.Size
	return (rest * CFrame.new(0, size.Y / 2, 0)).Position.Y
end

local function surfaceHeightAt(tile: BasePart, x: number, z: number): number
	local slab = tile.Parent
	if not (slab and slab:IsA("BasePart")) then
		return tileTopY(tile)
	end

	local total, weighted = 0.0, 0.0
	for _, child in ipairs(slab:GetChildren()) do
		if child:IsA("BasePart") and child.Name:sub(1, 10) == "SubRegion_" then
			local at = child.Position
			local dx, dz = at.X - x, at.Z - z
			local d2 = dx * dx + dz * dz
			if d2 < 0.01 then
				return tileTopY(child)
			end
			-- Inverse FOURTH power, so the cell you are actually in dominates and the
			-- others only round off the step at its edges. Plain inverse distance drags
			-- every print toward the platform's average height, which on a domed or
			-- terraced surface is a height that exists nowhere.
			local weight = 1.0 / (d2 * d2)
			total += weight
			weighted += tileTopY(child) * weight
		end
	end
	return if total > 0 then weighted / total else tileTopY(tile)
end

local function spawnFootprint(
    tile: BasePart,
    hit: FootHit,
    materialName: string,
    lifetime: number,
    sink: number?
)
    local profile = FootprintProfiles[materialName] or FootprintProfiles.Honey
    local template = footprintTemplate(profile.mesh)
    if not template then
        return
    end

    -- Heading straight from the FOOT, so a splayed foot prints splayed.
    local flat = Vector3.new(hit.look.X, 0, hit.look.Z)
    if flat.Magnitude < 1e-4 then
        flat = Vector3.new(0, 0, 1) -- foot pointing straight up or down: no heading
    end
    flat = flat.Unit
    local facing = CFrame.Angles(0, math.atan2(flat.X, flat.Z), 0)

    -- Sized from the foot part itself. foot.Size is the bare foot; the sole that actually
    -- meets the ground is wider, and material squeezes out sideways under load.
    local width = hit.size.X * FOOT.PRINT_SPREAD
    local length = hit.size.Z * FOOT.PRINT_SPREAD
    local heightScale = (width / FOOT.MESH_WIDTH + length / FOOT.MESH_LENGTH) * 0.5

    local mark = template:Clone() :: BasePart
    mark.Name = "Footprint"
    mark.Size = Vector3.new(width, FOOT.MESH_HEIGHT * heightScale * profile.depth, length)
    mark.Anchored = true
    mark.CanCollide = false
    mark.CanTouch = false
    mark.CanQuery = false
    mark.CastShadow = false

    -- Height from the SURFACE under this exact point -- see surfaceHeightAt. X and Z come
    -- from the foot, so the print lands where you trod, at the height the mesh is there
    -- rather than at the foot's centre, which is about 0.4 studs above the ground.
    local surfaceY = surfaceHeightAt(tile, hit.position.X, hit.position.Z)
    local rim = surfaceY + FOOT.LIFT - (sink or 0)
    local startSize = mark.Size
    mark.CFrame = CFrame.new(hit.position.X, rim - startSize.Y / 2, hit.position.Z) * facing

    -- Material and reflectance from the surface it sits in, so it catches the same
    -- highlight; the colour is pulled down and the gloss dropped well below the honey's, so
    -- it reads as duller rather than as a different colour.
    MaterialAppearance.apply(mark, materialName)
    local surface = MaterialAppearance.Appearances[materialName]
    mark.Color = (surface and surface.color or mark.Color):Lerp(Color3.new(0, 0, 0), profile.tint)
    mark.Transparency = profile.transparency
    mark.Reflectance = profile.reflectance
    mark.Parent = tile.Parent

    -- Seep: shrink inward and flatten. Size and CFrame are tweened TOGETHER with one easing,
    -- which is what keeps the rim pinned at the surface: the centre has to rise by exactly
    -- half of whatever the height loses, or the mark sinks out of sight instead of filling.
    local endSize = Vector3.new(
        startSize.X * SEEP_SHRINK,
        startSize.Y * SEEP_FLATTEN,
        startSize.Z * SEEP_SHRINK
    )
    local endCFrame = CFrame.new(hit.position.X, rim - endSize.Y / 2, hit.position.Z) * facing

    -- GRANULAR MATERIAL DOES NOT SEEP. Honey and slime close their hollow over the
    -- print's life because they flow; sand has no reason to, and animating it shut is
    -- exactly what would make it read as soft.
    if profile.seep ~= false then
        TweenService:Create(
            mark,
            TweenInfo.new(lifetime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
            { Size = endSize, CFrame = endCFrame }
        ):Play()
    elseif profile.slump then
        -- IT SLUMPS INSTEAD, and this is the beat that says cohesive.
        --
        -- Kinetic sand is not a solid and not a powder. A cut face holds its shape --
        -- which is what the crisp wall is for -- and then, over about a second, settles
        -- under its own weight and stops. Frozen at full depth it reads as carved stone;
        -- closing over it reads as honey. The whole character is in the small sag
        -- between the two, and then nothing.
        local settled = Vector3.new(startSize.X, startSize.Y * profile.slump, startSize.Z)
        TweenService:Create(
            mark,
            TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {
                Size = settled,
                CFrame = CFrame.new(hit.position.X, rim - settled.Y / 2, hit.position.Z) * facing,
            }
        ):Play()
    end

    -- A print that never expires is handed to its material's own keeper instead of to
    -- Debris, and must NOT be scheduled to fade: a timed fade is a lifetime by another
    -- name. Sand is retired by budget (see SAND.PRINT_CAP), oldest first.
    if profile.permanent then
        table.insert(sandPrints, { part = mark, tile = tile })
        retireOldestPrint()
        return
    end

    -- Only the tail fades, so nearly all of the life is the hollow closing rather than the
    -- mark thinning away.
    task.delay(lifetime * SEEP_FADE_AT, function()
        if mark.Parent then
            TweenService:Create(
                mark,
                TweenInfo.new(lifetime * (1 - SEEP_FADE_AT), Enum.EasingStyle.Linear),
                { Transparency = 1 }
            ):Play()
        end
    end)

    Debris:AddItem(mark, lifetime + 0.2)
end

-- === Effects ===

type Ctx = { tile: BasePart, state: string, material: string, popCount: number?, layer: number?, stepCount: number?,
	depth: number?, push: number?, lean: Vector3?, cause: string?, combo: string?, charge: number?,
	fire: string?, wade: number?, origin: Vector2?, mine: boolean?, who: Player? }

-- EVERY KIND OF DEBRIS THIS GAME THROWS, and what it weighs.
--
-- This replaced seven positional arguments, which was already one too many before weight and
-- glow needed adding. Naming the kinds also puts the whole physical vocabulary in one place,
-- and the differences between the rows are the point: a lump of foam and a shard of obsidian
-- should not fall the same way, and until now they did.
--
-- === buoyancy, and why it exists at all ===
--
-- ROBLOX HAS NO AIR RESISTANCE. Every unanchored part falls at exactly the same rate
-- whatever its size or density, because that is what gravity does in a vacuum -- so making
-- foam "lighter" by giving it a low density changes its mass and nothing you can see.
--
-- What actually makes light things fall slowly in the real world is drag, and the cheapest
-- honest stand-in is to cancel part of gravity: a VectorForce pushing up with
-- `mass * gravity * buoyancy` leaves an effective gravity of `(1 - buoyancy) * g`. At 0.72,
-- foam falls at a bit over a quarter the speed of obsidian, which is roughly the difference
-- between a torn scrap of packing foam and a stone.
--
-- Zero means no force and no instances -- most rows are zero, and the code skips the whole
-- branch for them, so the common case costs nothing.
type DebrisKind = {
	colour: Color3,
	material: Enum.Material,
	scale: number,      -- of the cell, per piece
	speed: number,      -- how hard it is thrown
	spin: number,
	buoyancy: number,   -- 0 falls like a rock, 0.9 drifts
	glow: number,       -- PointLight brightness, 0 for none
	chunky: boolean,    -- one clean rectangular piece rather than a scatter of splinters
	life: number,
}

local DEBRIS: { [string]: DebrisKind } = {
	-- LEGO IS NOT HERE, deliberately: it throws a CLONE of its real brick, studs and welds
	-- and all, because the thing that comes away has to be the thing that was there.
	-- Everything below is rubble that never existed as an object until it broke off.
	--
	-- HEAVY: these drop like what they are made of.
	Obsidian = { colour = Color3.fromRGB(28, 22, 24), material = Enum.Material.Slate,
		scale = 0.5, speed = 19, spin = 18, buoyancy = 0, glow = 0, chunky = false, life = 3.5 },
	ChocolateShard = { colour = Color3.fromRGB(70, 42, 24), material = Enum.Material.SmoothPlastic,
		scale = 0.62, speed = 17, spin = 16, buoyancy = 0, glow = 0, chunky = false, life = 3.5 },
	-- Dense slurry. It arcs and lands; it does not tumble far.
	OoblGob = { colour = Color3.fromRGB(236, 234, 226), material = Enum.Material.SmoothPlastic,
		scale = 0.22, speed = 12, spin = 8, buoyancy = 0, glow = 0, chunky = false, life = 3.0 },
	-- MOLTEN ROCK, and the only debris in the game that carries its own light.
	--
	-- Neon alone makes a part render bright, but it lights NOTHING -- so a glowing gob falls
	-- past a dark platform without touching it, which reads as a decal rather than as
	-- something hot. A PointLight on each one is what makes the platform underneath flicker
	-- as they go by, and that moving light is most of what sells the heat.
	Melt = { colour = Color3.fromRGB(255, 148, 52), material = Enum.Material.Neon,
		scale = 0.34, speed = 15, spin = 10, buoyancy = 0.18, glow = 2.4, chunky = false, life = 4.0 },
	-- WET: these land with a weight to them and do not tumble far.
	--
	-- Buoyancy near zero for all of them. A drop of anything liquid is dense, and the thing
	-- that makes it read as liquid is the SIZE and the slowness of the throw, not the fall --
	-- a gob that floats down looks like polystyrene painted amber.
	HoneyString = { colour = Color3.fromRGB(228, 158, 40), material = Enum.Material.Glass,
		scale = 0.20, speed = 9, spin = 5, buoyancy = 0.05, glow = 0, life = 4.0 },
	SlimeGob = { colour = Color3.fromRGB(120, 216, 86), material = Enum.Material.Glass,
		scale = 0.26, speed = 13, spin = 9, buoyancy = 0.08, glow = 0, life = 3.5 },
	JelloBit = { colour = Color3.fromRGB(246, 158, 92), material = Enum.Material.Glass,
		scale = 0.24, speed = 14, spin = 12, buoyancy = 0.06, glow = 0, life = 3.2 },
	-- Warm chocolate is the heaviest liquid here and the slowest thrown: it barely leaves
	-- the surface at all, which is what separates a melt from a splash.
	ChocGlob = { colour = Color3.fromRGB(88, 52, 28), material = Enum.Material.SmoothPlastic,
		scale = 0.22, speed = 8, spin = 6, buoyancy = 0.04, glow = 0, life = 4.0 },

	-- GRANULAR AND BRITTLE.
	SandClod = { colour = Color3.fromRGB(206, 180, 132), material = Enum.Material.Sand,
		scale = 0.20, speed = 14, spin = 18, buoyancy = 0.28, glow = 0, life = 3.0 },
	ClayChip = { colour = Color3.fromRGB(166, 104, 74), material = Enum.Material.Sandstone,
		scale = 0.24, speed = 13, spin = 14, buoyancy = 0.12, glow = 0, life = 4.0 },
	-- Thin, bright and sharp. Glass so it catches light on the way down, which is the whole
	-- difference between a shard of ice and a chip of stone.
	IceShard = { colour = Color3.fromRGB(214, 238, 250), material = Enum.Material.Glass,
		scale = 0.28, speed = 17, spin = 20, buoyancy = 0.14, glow = 0, life = 3.2 },
	-- Wax flakes are soft and opaque where ice is hard and bright, and they fall slower.
	WaxFlake = { colour = Color3.fromRGB(246, 232, 168), material = Enum.Material.SmoothPlastic,
		scale = 0.26, speed = 12, spin = 11, buoyancy = 0.34, glow = 0, life = 3.6 },

	-- LIGHT: these hang before they fall.
	-- Packed snow leaves the surface in clumps rather than powder -- powder is the particle
	-- puff that goes with it, and the two together are what a boot actually kicks up.
	SnowClump = { colour = Color3.fromRGB(250, 251, 255), material = Enum.Material.Snow,
		scale = 0.28, speed = 11, spin = 9, buoyancy = 0.58, glow = 0, life = 4.0 },
	-- A single hair, and the second-lightest thing in the table.
	LeafHair = { colour = Color3.fromRGB(196, 212, 168), material = Enum.Material.Fabric,
		scale = 0.16, speed = 6, spin = 14, buoyancy = 0.78, glow = 0, life = 5.0 },
	-- THE LIGHTEST THING IN THE GAME, at a tenth of normal gravity. A torn scrap of cloud
	-- should barely fall at all -- it should hang and drift, and anything that reads as
	-- falling reads as polystyrene.
	CloudWisp = { colour = Color3.fromRGB(252, 253, 255), material = Enum.Material.SmoothPlastic,
		scale = 0.34, speed = 5, spin = 4, buoyancy = 0.90, glow = 0, life = 6.0 },
	-- Salt is a crystal, so it is not weightless -- just small.
	SaltCrystal = { colour = Color3.fromRGB(244, 245, 246), material = Enum.Material.Sand,
		scale = 0.24, speed = 16, spin = 20, buoyancy = 0.18, glow = 0, chunky = false, life = 3.0 },
	-- Charcoal is mostly air by volume, which is why a lump of it feels wrong in the hand.
	CharcoalFlake = { colour = Color3.fromRGB(42, 39, 38), material = Enum.Material.Slate,
		scale = 0.26, speed = 15, spin = 22, buoyancy = 0.42, glow = 0, chunky = false, life = 3.5 },
	-- The lightest thing here by a distance. Torn open-cell foam drifts, and at 0.72 it
	-- takes nearly twice as long to reach the sea as a shard of obsidian thrown just as hard.
	FoamBit = { colour = Color3.fromRGB(248, 244, 232), material = Enum.Material.Foil,
		scale = 0.30, speed = 7, spin = 6, buoyancy = 0.72, glow = 0, chunky = false, life = 5.0 },
}

local function flingDebris(tile: BasePart, kindName: string, count: number)
	local kind = DEBRIS[kindName]
	if not kind then
		return
	end
	local base = restSize[tile] or Vector3.new(2, 1, 2)
	local origin = restCFrame[tile] or tile.CFrame

	for index = 1, count do
		local piece: BasePart
		-- Half the splinters are wedges. A field of boxes at random angles still reads as
		-- boxes; mixing in a shape with a sloped face is what makes a pile look fractured
		-- rather than diced.
		if not kind.chunky and index % 2 == 0 then
			piece = Instance.new("WedgePart")
		else
			piece = Instance.new("Part")
		end
		piece.Name = "Debris"
		piece.Size = if kind.chunky
			then Vector3.new(base.X * 0.78, 0.85, base.Z * 0.78)
			else Vector3.new(
				base.X * kind.scale * (0.4 + math.random() * 0.7),
				base.Y * kind.scale * (0.5 + math.random() * 0.8),
				base.Z * kind.scale * (0.4 + math.random() * 0.7)
			)
		piece.CFrame = origin
			* CFrame.new((math.random() - 0.5) * base.X * 0.5, 0.4, (math.random() - 0.5) * base.Z * 0.5)
			* (if kind.chunky then CFrame.identity else CFrame.Angles(
				math.random() * math.pi, math.random() * math.pi, math.random() * math.pi))
		piece.Color = kind.colour:Lerp(Color3.new(0, 0, 0),
			math.random() * (if kind.chunky then 0.08 else 0.35))
		piece.Material = kind.material
		piece.Anchored = false
		-- NOT collidable. A dozen tumbling parts that can push the player is a physics
		-- accident waiting to happen on a platform you are already falling through.
		piece.CanCollide = false
		piece.CanTouch = false
		piece.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * kind.speed,
			kind.speed * (0.45 + math.random() * 0.4),
			(math.random() - 0.5) * kind.speed)
		piece.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * kind.spin,
			(math.random() - 0.5) * kind.spin,
			(math.random() - 0.5) * kind.spin)
		piece.Parent = workspace

		if kind.buoyancy > 0 then
			-- Read AFTER parenting: AssemblyMass is only meaningful once the part is in the
			-- world and unanchored, and reading it earlier returns a figure the force would
			-- then be wrong by.
			local lift = Instance.new("Attachment")
			lift.Parent = piece
			local force = Instance.new("VectorForce")
			force.Attachment0 = lift
			force.RelativeTo = Enum.ActuatorRelativeTo.World
			force.Force = Vector3.new(0, piece.AssemblyMass * workspace.Gravity * kind.buoyancy, 0)
			force.Parent = piece
		end

		if kind.glow > 0 then
			local light = Instance.new("PointLight")
			light.Color = kind.colour
			light.Brightness = kind.glow
			light.Range = 12
			light.Shadows = false
			light.Parent = piece
		end

		Debris:AddItem(piece, kind.life)
	end
end

-- A short-lived cloud of something at the surface of a cell.
--
-- Nine materials wanted a puff and each was about to grow its own twenty-line emitter,
-- which is how a file gets to five thousand lines. The four arguments are the only things
-- that actually differed between them: what colour it is, how big, how fast it leaves, and
-- whether it rises or falls.
--
-- `rise` is the one worth naming. Anything warm or airborne goes UP -- steam, dust kicked
-- loose, fibres -- and anything wet or heavy goes down. Getting that backwards is the single
-- clearest tell that a particle effect was not thought about, and it is one sign flip.
local function puff(tile: BasePart, colour: Color3, size: number, speed: number, rise: number, count: number)
	local origin = Instance.new("Attachment")
	origin.Name = "PuffOrigin"
	origin.Position = Vector3.new(0, (restSize[tile] and restSize[tile].Y or 1) / 2, 0)
	origin.Parent = tile

	-- Written as a statement rather than the if-expression this codebase normally uses, and
	-- that is deliberate. check_lua tells a statement `if` from an expression `if` by what
	-- follows the matching `then` on its line -- but strip_noise blanks string bodies first,
	-- so a multi-line if-expression whose branch is a BARE STRING looks like a statement that
	-- ends its line, and the whole file reports as one block open. The Lua was valid; the
	-- heuristic has a blind spot for exactly this shape. Sidestepping it is cheaper and
	-- clearer than widening a check that has been right about everything else.
	local texture = "rbxasset://textures/particles/sparkles_main.dds"
	if rise > 0 then
		texture = "rbxasset://textures/particles/smoke_main.dds"
	end

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = texture
	emitter.Color = ColorSequence.new(colour)
	emitter.Size = NumberSequence.new(size)
	emitter.Lifetime = NumberRange.new(0.25, 0.7)
	emitter.Speed = NumberRange.new(speed * 0.4, speed)
	emitter.SpreadAngle = Vector2.new(70, 70)
	emitter.Rate = 0
	emitter.Acceleration = Vector3.new(0, rise, 0)
	emitter.Transparency = NumberSequence.new(if rise > 0 then 0.5 else 0.15)  -- single line: safe
	emitter.Parent = origin
	emitter:Emit(count)
	Debris:AddItem(origin, 1.6)
end

local Effects: { [string]: (Ctx) -> () } = {}

-- Honey: deep slow sag, and an amber smear at each footfall that outlives the
-- contact. The smear is the "slippery trail" read.
-- How deep a footprint stays after the foot leaves, as a fraction of the press.
-- Honey is viscous enough to hold a print rather than levelling out immediately;
-- this is what makes stepping leave a trace instead of a momentary dip.
-- Honey: the deep slow sag. ONE table rather than a family of separate top-level locals: this
-- module runs close to Luau's 200-register limit for a single scope, and constants
-- are the cheapest thing to fold. Every name and comment below is unchanged.
local HONEY = {}
HONEY.PRESS = 1.55
HONEY.RESIDUAL_FRACTION = 0.38
HONEY.RIPPLE = RippleProfiles.Honey

Effects.Honey = function(ctx: Ctx)
	local tile = ctx.tile
	local slab = tile.Parent
	local onSlab = (slab and slab:IsA("BasePart")) and slab or nil

	if ctx.state == "deformed" then
		puff(tile, MaterialAppearance.Appearances.Honey.color, 0.20, 3, -22, 5)
		-- Honey does not spatter, it STRINGS: a couple of slow heavy drops that barely
		-- leave the surface. Throwing it hard would make it juice.
		flingDebris(tile, "HoneyString", 2)
		-- Deep, slow press at the contact point. Roughly twice the travelling ridge's
		-- height, so the footfall is unmistakably the origin of the wave: the material has
		-- to come from somewhere for the surrounding ridge to be believable.
		moveTile(tile, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), -HONEY.PRESS, 0.93, 1.15)

		-- Skinned platform: a real wave through the surface geometry, spreading from the
		-- cell that was stepped on.
		local bone = boneFor(tile)
		if bone and onSlab then
			rippleFrom(onSlab, bone.WorldPosition, HONEY.RIPPLE)
		end

		local plates = ensureMicroTiles(tile, "Honey")
		-- Derived from the material's own colour so the rings always belong to the surface
		-- they spread across, and darkened rather than saturated: pooled honey differs from
		-- the honey around it by depth, not by hue.
		local ringColour = MaterialAppearance.Appearances.Honey.color:Lerp(Color3.new(0, 0, 0), 0.28)

		-- Sub-cell depression, only available on non-skinned honey platforms.
		if plates then
			for _, offset in ipairs(localFootOffsets(tile)) do
				pressMicro(tile, plates, offset, MICRO_THICKNESS * 1.1, 0.22)
			end
		end

		if onSlab then
			local feet = localFootWorldPoints(tile)

			if #feet == 0 and not noFeetWarned then
				noFeetWarned = true
				warn(
					("DeformationRenderer: %s reported deformed but no foot overlaps it, so no ripple or print was drawn. If this repeats, the foot-to-cell test is rejecting the foot that triggered the event."):format(
						tile.Name
					)
				)
			end

			-- ONE ripple per footfall, from the foot NEAREST this cell's centre, which is
			-- the one the event most likely belongs to.
			if feet[1] then
				spawnRipple(onSlab, tile, feet[1].position, ringColour, HONEY.RIPPLE)
			end

			for _, foot in ipairs(feet) do
				-- Lifetime DERIVED from the ring's, so retuning the wave keeps prints and
				-- rings disappearing together.
				spawnFootprint(tile, foot, "Honey", ringTravel(HONEY.RIPPLE))
			end
		end
	elseif ctx.state == "decaying" then
		-- Stepped off. The surface does NOT level out: it keeps a shallower print for the
		-- cell's decay window, which is the whole point of a viscous material.
		local bone = boneFor(tile)
		if bone then
			setResidual(
				tile,
				bone,
				TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				-HONEY.PRESS * HONEY.RESIDUAL_FRACTION
			)
		else
			settleTile(tile, 0.9)
		end
	else
		-- pristine: the decay window closed, so the honey has flowed back and covered the
		-- print. Slow on purpose; a quick snap would throw away everything the residual
		-- bought.
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, TweenInfo.new(3.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), 0)
		else
			settleTile(tile, 0.9)
		end
		releaseMicro(tile, "Honey", 1.4)
	end
end

-- Kinetic sand: the tile itself hardly moves, so it does not read as a sinking
-- square. What you see is the footprint stamped into it, oriented to your
-- facing, plus a puff of dislodged grains.
-- Clumps sheared off the edge of a print, as anchored parts that tumble a short way and
-- then stop. Budgeted for the session the same way the micro plates are: a player can
-- cross every cell of every sand platform, and a few parts per footfall adds up fast.
local CLUMPS_PER_STEP = 3
local CLUMP_LIFETIME = 3.5
local clumpBudget = 240

local function shedClumps(tile: BasePart, offset: Vector3)
	if clumpBudget < CLUMPS_PER_STEP then
		return
	end
	clumpBudget -= CLUMPS_PER_STEP
	local top = tileTop(tile)
	local look = MaterialAppearance.Appearances.KineticSand

	for _ = 1, CLUMPS_PER_STEP do
		local size = 0.16 + math.random() * 0.16
		local clump = Instance.new("Part")
		clump.Name = "SandClump"
		clump.Size = Vector3.new(size, size * 0.7, size * (0.8 + math.random() * 0.5))
		clump.Anchored = true
		clump.CanCollide = false
		clump.CanTouch = false
		clump.CanQuery = false
		clump.CastShadow = false
		clump.Material = Enum.Material.Sand
		-- Pulled slightly darker than the surface: a clump that broke out of the pack is
		-- damp inside, and it has to separate from the sand it is lying on somehow.
		clump.Color = (look and look.color or clump.Color):Lerp(Color3.new(0, 0, 0), 0.12)

		-- Thrown from the rim of the print, not from its centre, since that is the edge
		-- that failed.
		local angle = math.random() * math.pi * 2
		local throw = 0.75 + math.random() * 0.7
		local from = top * CFrame.new(offset.X, size * 0.5, offset.Z)
		local to = top
			* CFrame.new(
				offset.X + math.cos(angle) * throw,
				size * 0.5,
				offset.Z + math.sin(angle) * throw
			)
			* CFrame.Angles(math.random() * 3, math.random() * 3, math.random() * 3)
		clump.CFrame = from
		clump.Parent = tile

		-- One short hop out and down, then it is done. No physics: an unanchored part
		-- rolls, and a rolling clump of kinetic sand is a pebble.
		TweenService:Create(
			clump,
			TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = to }
		):Play()
		Debris:AddItem(clump, CLUMP_LIFETIME)
	end
end

-- === Sand: the SURFACE dents, rather than a print being laid on it ===
--
-- Sand used to stamp a sole-shaped part onto a flat plane. However well that part was
-- modelled it read as a sticker, for the reason this file already records against
-- decals: the surface around it is visibly unbroken, so nothing about it says the
-- ground gave way. A rigid mesh cannot help, because a rigid mesh cannot move.
--
-- The skin is skinned now, at a 0.9-stud bone pitch -- fine enough to resolve a
-- footprint, which a per-cell rig like honey's never could. A footfall drives the bones
-- under the foot DOWN and the bones in a ring just outside them UP. That ring is the
-- berm: material displaced out of the hollow, and the single thing that separates a
-- granular print from a dish pressed into rubber.
-- TWO PRIMITIVES, EACH DOING WHAT IT IS GOOD AT, because neither works alone.
--
-- The rig alone cannot make a footprint. At a 0.9-stud pitch only about three bones fall
-- inside a sole, and each one's influence spreads 1.5 studs, so a press comes out a vague
-- smudge -- verified by render, not guessed. That is the lesson soap already taught this
-- project: SKINNING STRETCHES, and a stretch cannot hold a sharp edge. Resolving a print
-- with bones alone would need a ~0.45 pitch, which is 450 bones on the biggest slab.
--
-- The stamp alone cannot make displacement. A sole-shaped part laid on an unbroken plane
-- reads as a sticker however well it is modelled, which is what the last version looked
-- like and why this one exists.
--
-- So the RIG presses a broad, soft bowl with a raised rim -- real give, which is exactly
-- what skinning is for -- and the STAMP puts the crisp sole detail down inside it. The
-- stamp stops reading as a sticker because the ground around it genuinely dropped.
-- CAPPED BY THE SKIN, not chosen freely. The resting relief already hangs 0.4 below the
-- walkable plane and the skin's floor is at 0.9, so a press past ~0.45 drives the
-- deepest lumps through the bottom of the skin and into the slab it lies on.
--
-- That ceiling is fine, because depth is not what makes a print readable here. On a
-- surface of clumps the print reads by being SMOOTH -- see the stamp below. Depth alone
-- would just be another lump-sized dip in a field of lump-sized dips.
-- THE CEILING MOVED. This was capped at 0.45 because the skin was a 0.9-thick lid, and a
-- deeper press drove the resting lumps through its floor into the slab underneath. The
-- skin is a 4.9-deep block of sand now, so the material under the surface has stopped
-- being the constraint -- which is the real reason wrapping the sides was worth doing,
-- beyond how they look.
--
-- Depth is still not what makes a print READABLE on a clumped surface; smoothness is,
-- and that is the stamp's job. Depth is what makes it look like it took weight.
SAND.PRESS = 0.85    -- the bowl, now that there is a body to press into
SAND.BERM = 0.35     -- the displaced rim around it
SAND.BERM_TO = 2.2   -- how far the berm reaches, in bowl-widths
SAND.SPREAD = 1.9    -- the bowl is much wider than the sole that sits in it
-- How far the stamped sole sits below the walkable plane.
--
-- IT HAS TO BE SUNK, and this is the opposite call from the flat-surface version, for a
-- reason that changed with the surface. On a flat plane sinking the sole buried it and
-- lost the only crisp edge sand had. On a surface whose own lumps stand 0.4 proud, a
-- sole at plane height perches ON TOP of those lumps instead of sitting in the ground.
-- Just under the lump tops is where it reads as a compacted patch pressed into them.
SAND.STAMP_SINK = 0.42

-- HOW FAR IN THE BOWL ALREADY IS, per footfall on the same cell.
--
-- Sand collapses on the third step and looked identical on all three: its effect never read
-- ctx.stepCount. The oldest material in the game with a step counter was still doing the
-- exact thing ice was rebuilt to stop doing -- giving way on a number the player cannot see.
--
-- Scales the press AND the berm together, because they are the same event: material coming
-- out of a hole has to go somewhere, and a deeper bowl with an unchanged rim reads as the
-- sand being deleted rather than displaced.
local SAND_STAGE = { 0.55, 0.8, 1.0 }


local sandBones: { [BasePart]: { Bone } } = {}
local sandOffset: { [Bone]: number } = {}
local sandWarned = false

-- Says EXACTLY which link is broken, once. Falling back to a stamp on flat ground and
-- saying nothing is the failure mode this project keeps rediscovering: the sand looks
-- almost unchanged, nothing errors, and there is no way to tell from inside the game
-- whether the mesh is missing, unrigged, or simply not being driven.
local function warnNoSandRig(tile: BasePart, reason: string)
	if sandWarned then
		return
	end
	sandWarned = true
	warn(
		("DeformationRenderer: kinetic sand is NOT deforming -- %s. Only the stamped print will show, on flat ground. Check that the Sand_Surface_* FBXs are in ReplicatedStorage/Assets/TileMeshes WITH their Bone children, and that no leftover .obj of the same name is shadowing them."):format(
			reason
		)
	)
end

local function sandBonesFor(tile: BasePart): ({ Bone }, BasePart?)
	local slab = tile.Parent
	if not (slab and slab:IsA("BasePart")) then
		return {}, nil
	end
	if not slab:GetAttribute("SkinnedVisual") then
		warnNoSandRig(tile, "this slab has no rig attached at all (ChunkBuilder could not find or accept the mesh for its size)")
		return {}, nil
	end
	local skin = slab:FindFirstChild("SkinnedVisual")
	if not (skin and skin:IsA("BasePart")) then
		warnNoSandRig(tile, "the slab is flagged as rigged but carries no SkinnedVisual part")
		return {}, nil
	end
	local cached = sandBones[skin]
	if cached then
		return cached, skin
	end
	local list: { Bone } = {}
	for _, descendant in ipairs(skin:GetDescendants()) do
		if descendant:IsA("Bone") and descendant.Name:match("^Grain_") then
			table.insert(list, descendant)
		end
	end
	if #list == 0 then
		warnNoSandRig(
			tile,
			("'%s' has no Grain_* bones (it has %d descendants). The FBX imported without its armature"):format(
				skin.Name,
				#skin:GetDescendants()
			)
		)
	end
	sandBones[skin] = list
	return list, skin
end

-- Where a point sits relative to a foot, as 1.0 at the sole's edge.
--
-- ELLIPTICAL, in the FOOT'S OWN FRAME. A circular falloff would press a round dish, and
-- a round dish is not a footprint -- a foot is roughly 1.0 by 1.7 and points somewhere.
-- Measuring along the foot's heading is what makes the hollow come out foot-shaped and
-- splayed the way the foot that made it was.
local function footField(hit: FootHit, at: Vector3): number
	local look = Vector3.new(hit.look.X, 0, hit.look.Z)
	if look.Magnitude < 1e-4 then
		look = Vector3.new(0, 0, 1)
	end
	look = look.Unit
	local side = Vector3.new(-look.Z, 0, look.X)
	local offset = Vector3.new(at.X - hit.position.X, 0, at.Z - hit.position.Z)
	local along = offset:Dot(look) / math.max(hit.size.Z * 0.5 * SAND.SPREAD, 0.1)
	local across = offset:Dot(side) / math.max(hit.size.X * 0.5 * SAND.SPREAD, 0.1)
	return math.sqrt(along * along + across * across)
end

local function pressSand(tile: BasePart, hits: { FootHit }, deepen: number?)
	local bones = sandBonesFor(tile)
	if #bones == 0 then
		return false
	end
	local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local touched = false

	for _, bone in ipairs(bones) do
		local at = bone.WorldPosition
		local want = sandOffset[bone] or 0
		-- How far out the rim goes this time. At the first, shallow press it hugs the bowl;
		-- by the third it reaches the full BERM_TO, so the print visibly grows outward as
		-- well as downward.
		local reach = 1.0 + (SAND.BERM_TO - 1.0) * (deepen or 1)
		for _, hit in ipairs(hits) do
			local t = footField(hit, at)
			if t <= 1.0 then
				-- Flat-bottomed rather than a smooth dish. The stamp supplies the sole's
				-- own shape, so the bowl only has to be the GROUND GIVING WAY under it --
				-- and a bowl that eases all the way from its centre would round off the
				-- floor the stamp has to sit flush on.
				local shear = math.min(1.0, (1.0 - t) * 3.0)
				want = math.min(want, -SAND.PRESS * shear * (deepen or 1))
			elseif t <= reach then
				-- Outside it: the material that came out, piled against the rim and
				-- falling away. Never applied to a bone already inside a hollow, or a
				-- second footfall's berm would fill in the first one's print.
				local u = (t - 1.0) / (reach - 1.0)
				local lift = SAND.BERM * math.sin(math.pi * (1.0 - u)) * (1.0 - u) * (deepen or 1)
				if want >= 0 then
					want = math.max(want, lift)
				end
			end
		end
		if want ~= (sandOffset[bone] or 0) then
			sandOffset[bone] = want
			TweenService:Create(bone, info, { Transform = CFrame.new(0, want, 0) }):Play()
			touched = true
		end
	end
	return touched
end

-- Smooths over only the bones this cell owns. Sand decays per sub-region, so releasing
-- every bone on the platform would erase prints in cells the player is still standing in.
local function releaseSand(tile: BasePart)
	local bones = sandBonesFor(tile)
	if #bones == 0 then
		return
	end
	local half = restSize[tile] * 0.5
	local centre = restCFrame[tile].Position
	local info = TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	for _, bone in ipairs(bones) do
		if sandOffset[bone] then
			local at = bone.WorldPosition
			if math.abs(at.X - centre.X) <= half.X and math.abs(at.Z - centre.Z) <= half.Z then
				sandOffset[bone] = nil
				TweenService:Create(bone, info, { Transform = CFrame.identity }):Play()
			end
		end
	end
end

-- The cell giving way: cohesion lost, the sand under you drops out.
--
-- NOT a deeper footprint. A print and a collapse have to look like different events, so
-- this drives to the full depth of the skin rather than to a dent -- the cell stops
-- being there rather than sagging.
--
-- What makes it read as sand and not a trapdoor is that the drop is UNEVEN. Every bone
-- takes its own share, keyed to its position, so the surface tears down in lumps at
-- slightly different rates the way a handful of the stuff crumbles. A flat descent is a
-- lift, not a collapse.
--
-- 6.4 CLEARS THE BLOCK, which 3.2 did not. The sand skin is about 5.1 deep, so dropping
-- the surface 3.2 dug a pit inside a block that still had a floor and four walls -- a
-- crater, with visibly nowhere to fall to. Past the block's own depth the surface passes
-- out through the underside and the cell is empty; what faces you then is the inside of
-- the far wall, whose backfaces Roblox culls, so you see straight through.
local COLLAPSE_DROP = 6.4
-- How far toward the cell's centre a collapsing bone is dragged, as a fraction of its
-- distance from it. Near 1 the whole cell converges to a point and the surface pinches
-- out of existence, which is as close to a real hole as a rig gets.
local COLLAPSE_PINCH = 0.92

-- Sand pouring through the hole you just made, and going down with you.
--
-- SEPARATE FROM shedClumps, which throws a lump onto the surface and lets it settle.
-- Nothing here settles: these fall, and they have to fall the way you do, or you drop
-- past a cloud of stationary debris.
--
-- The staging is the point. The first handful goes at once from the MIDDLE of the cell,
-- because that is the sand that was under your feet and it should be moving before you
-- have registered the floor is gone. The rest come from the RIM over the following
-- second, because an edge left unsupported keeps crumbling after the middle has dropped.
-- One burst reads as an explosion; a burst and then a trickle read as a collapse.
-- The ground around a hole, sagging toward it once its support is gone. Studs beyond the
-- collapsed cell that this reaches, how far it sinks at the lip, and how long after the
-- collapse it starts -- the delay being the whole reason it reads as a consequence
-- rather than as part of the same event.
local SLUMP_REACH = 2.2
local SLUMP_DEPTH = 0.7
local SLUMP_AFTER = 0.22

local SPILL_FIRST = 5       -- from the centre, immediately
local SPILL_RIM = 9         -- from the edges, trailing
local SPILL_TAIL = 1.15     -- seconds the rim goes on giving way for
local SPILL_FALL = 34       -- how far a chunk drops before it is retired

local function spillThroughHole(tile: BasePart)
	if clumpBudget < SPILL_FIRST + SPILL_RIM then
		return
	end
	clumpBudget -= SPILL_FIRST + SPILL_RIM
	local top = tileTop(tile)
	local size = restSize[tile]
	local look = MaterialAppearance.Appearances.KineticSand

	local function drop(atX: number, atZ: number, wait: number, scale: number)
		task.delay(wait, function()
			if not tile.Parent then
				return
			end
			local side = (0.22 + math.random() * 0.3) * scale
			local chunk = Instance.new("Part")
			chunk.Name = "SandSpill"
			chunk.Size = Vector3.new(side, side * 0.75, side * (0.8 + math.random() * 0.5))
			chunk.Anchored = true
			chunk.CanCollide = false
			chunk.CanTouch = false
			chunk.CanQuery = false
			chunk.CastShadow = false
			chunk.Material = Enum.Material.Sand
			chunk.Color = (look and look.color or chunk.Color):Lerp(Color3.new(0, 0, 0), 0.1)
			local from = top * CFrame.new(atX, -0.2, atZ)
			chunk.CFrame = from
			chunk.Parent = tile

			-- ACCELERATING, not linear. Quad In is close enough to gravity over this
			-- distance that a chunk keeps pace with a falling character; a linear tween
			-- visibly lags behind you after the first few studs, which is the one thing
			-- this must not do.
			local drift = CFrame.new(
				(math.random() - 0.5) * 1.6,
				-SPILL_FALL,
				(math.random() - 0.5) * 1.6
			)
			local spin = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
			TweenService:Create(
				chunk,
				TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = from * drift * spin }
			):Play()
			Debris:AddItem(chunk, 1.7)
		end)
	end

	-- What was under your feet: the centre of the cell, now.
	for _ = 1, SPILL_FIRST do
		drop(
			(math.random() - 0.5) * size.X * 0.45,
			(math.random() - 0.5) * size.Z * 0.45,
			math.random() * 0.06,
			1.0
		)
	end

	-- The rim letting go afterwards, from the edges, smaller as it goes.
	for i = 1, SPILL_RIM do
		local angle = math.random() * math.pi * 2
		local reach = 0.34 + math.random() * 0.16
		drop(
			math.cos(angle) * size.X * reach,
			math.sin(angle) * size.Z * reach,
			0.12 + (i / SPILL_RIM) * SPILL_TAIL,
			0.85
		)
	end
end

local function collapseSand(tile: BasePart)
	local bones, skin = sandBonesFor(tile)
	if #bones == 0 or not skin then
		return
	end
	local half = restSize[tile] * 0.5
	local centre = restCFrame[tile].Position

	for _, bone in ipairs(bones) do
		local at = bone.WorldPosition
		local dx = math.abs(at.X - centre.X) - half.X
		local dz = math.abs(at.Z - centre.Z) - half.Z
		if dx <= 0 and dz <= 0 then
			-- Per-bone, deterministic from where it sits, so the same cell always
			-- crumbles the same way and neighbouring bones differ.
			local ragged = 0.72 + math.abs(math.noise(at.X * 0.6, at.Z * 0.6, 3.1)) * 0.9
			local delay = math.abs(math.noise(at.X * 0.4, at.Z * 0.4, 7.7)) * 0.1
			local drop = -COLLAPSE_DROP * ragged
			sandOffset[bone] = drop

			-- IT PINCHES AS IT FALLS, and that is what opens the hole.
			--
			-- A rig cannot cut a hole in itself -- this project already learned that on
			-- soap: MeshId is fixed at import and skinning STRETCHES, so a cell driven
			-- straight down stays joined to its neighbours and hangs underneath as a
			-- curtain of sand as wide as the cell. Trading a flat plane blocking the
			-- hole for a fat sheet blocking it is not a fix.
			--
			-- Pulling each bone toward the cell's centre as it drops converges the
			-- collapsing surface to a narrow spike instead, which reads as sand
			-- funnelling out of the hole and, more to the point, leaves the opening
			-- clear to see through.
			local pull = Vector3.new(centre.X - at.X, 0, centre.Z - at.Z) * COLLAPSE_PINCH
			local inward = skin.CFrame:VectorToObjectSpace(pull)
			task.delay(delay, function()
				if bone.Parent then
					TweenService:Create(
						bone,
						TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{ Transform = CFrame.new(inward.X, drop, inward.Z) }
					):Play()
				end
			end)
		elseif dx <= SLUMP_REACH and dz <= SLUMP_REACH then
			-- THE GROUND AROUND THE HOLE, a beat later.
			--
			-- Sand that has lost its neighbour does not stay level; it sags toward the
			-- gap once there is nothing holding that edge up. Delaying it is the whole
			-- effect -- simultaneous, it is just a wider hole, and the point is that the
			-- collapse has a CONSEQUENCE that arrives after you have already fallen.
			--
			-- Never applied to a bone already collapsed, so a second cell going nearby
			-- cannot haul a hole's edge back up.
			local outside = math.max(dx, dz, 0)
			local falloff = 1.0 - outside / SLUMP_REACH
			local sag = -SLUMP_DEPTH * falloff * falloff
			if (sandOffset[bone] or 0) > sag then
				sandOffset[bone] = sag
				task.delay(SLUMP_AFTER + math.random() * 0.3, function()
					if bone.Parent and (sandOffset[bone] or 0) >= sag then
						TweenService:Create(
							bone,
							TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{ Transform = CFrame.new(0, sag, 0) }
						):Play()
					end
				end)
			end
		end
	end

	spillThroughHole(tile)
end

Effects.KineticSand = function(ctx: Ctx)
	local tile = ctx.tile

	if ctx.state == "deformed" then
		flingDebris(tile, "SandClod", 3)
		local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

		-- THE SURFACE ITSELF TAKES THE PRINT, so the cell barely gives. Sand is packed:
		-- it holds a sharp impression of whatever pressed it and the ground around that
		-- does not move.
		-- The COLLIDER follows, some of the way. It is the whole cell, so it cannot track
		-- a hollow the size of one foot -- but leaving it at 0.08 under an 0.85 dent
		-- would have you visibly standing on air above your own footprint.
		-- Deeper each time this cell is worked. By the third the bowl is at full depth and
		-- obviously will not take another -- which is the warning sand never gave: it used
		-- to look identical on all three steps and then simply vanish under you.
		local stage = math.clamp(ctx.stepCount or 1, 1, #SAND_STAGE)
		local deepen = SAND_STAGE[stage]

		moveTile(tile, info, -0.3 * deepen, 1.0, 1.0)

		-- BOTH, always. The rig drops the ground and raises a rim; the stamp puts the
		-- sole's own shape down on it. If the rig is missing the stamp still lands, just
		-- on flat ground -- degraded, but not invisible.
		--
		-- The stamp is the SMOOTH part, and on a clumped surface that is the whole signal.
		-- The reference photographs read as footprints not because the hollows are deep
		-- but because the sand inside them has been compacted flat while everything
		-- around stays lumpy. The rig cannot do that -- bones translate vertices, they
		-- cannot un-rough a surface -- so the smooth patch has to be a part.
		local hits = localFootWorldPoints(tile)
		pressSand(tile, hits, deepen)
		for _, hit in ipairs(hits) do
			-- The stamp rides the bowl down. Sinking it the full 0.42 into a hollow only
			-- 0.47 deep would bury the one crisp edge this material has.
			spawnFootprint(tile, hit, "KineticSand", SAND.PRINT_LIFE, SAND.STAMP_SINK * deepen)
		end

		for _, offset in ipairs(localFootOffsets(tile)) do
			-- Parented to an Attachment so the burst originates at the footfall.
			-- A ParticleEmitter is not a BasePart and has no CFrame of its own;
			-- parenting it straight to the tile would emit from the whole cell
			-- volume instead of from under your foot.
			local anchor = Instance.new("Attachment")
			anchor.Name = "SandCrumbOrigin"
			anchor.Position = Vector3.new(offset.X, restSize[tile].Y / 2, offset.Z)
			anchor.Parent = tile

			-- FEWER, SLOWER, HEAVIER than a dust puff. Loose grains flying off is dry
			-- beach sand; kinetic sand is cohesive and sheds small CLUMPS that travel a
			-- short way and stop dead. The old settings threw twelve fast specks on a
			-- wide cone, which is the one reading this material must not have.
			local crumbs = Instance.new("ParticleEmitter")
			crumbs.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			crumbs.Color = ColorSequence.new(Color3.fromRGB(186, 158, 112))
			crumbs.Size = NumberSequence.new(0.22)
			crumbs.Lifetime = NumberRange.new(0.2, 0.35)
			crumbs.Speed = NumberRange.new(0.8, 2)
			crumbs.SpreadAngle = Vector2.new(28, 28)
			crumbs.Rate = 0
			crumbs.Acceleration = Vector3.new(0, -70, 0)
			crumbs.Parent = anchor
			crumbs:Emit(5)
			Debris:AddItem(anchor, 1.2)

			-- The lumps that actually shear off the cut, as real parts rather than
			-- particles: a particle cannot come to rest and sit there, and sand that
			-- does not STAY where it fell is sand that never had any weight.
			shedClumps(tile, offset)
		end
	elseif ctx.state == "exhausted" then
		-- IT LOSES COHESION AND GOES. The server has already taken the floor away by the
		-- time this arrives, so this is the visual for a hole opening under you.
		collapseSand(tile)
	else
		-- NOTHING IS RELEASED on a decay. The server still cycles this cell back to
		-- pristine on its timer and the client simply declines to undo the sand -- the
		-- two disagree on purpose. `releaseSand` is kept for a level teardown, which is
		-- the only moment tracks should ever be erased.
		settleTile(tile, 0.5)
	end
end

-- Butter-wax: a hard shell that fractures. The tile snaps once, shallow, and
-- crack lines fan out from the contact point.
-- === Butter-wax: a wax shell over butter ===
--
-- The plates are built by ChunkBuilder (attachShell) and already form the surface, so
-- nothing here draws a crack. It CRACKS one: each plate tilts and slides outward on
-- its own, and the gaps that opens expose the butter body underneath, which is warmer
-- and sits SHELL_THICKNESS lower. That is where the depth comes from -- a gap between
-- two real plates is an absence lit by what is beneath it, which is the one thing a
-- drawn line and a part laid on the surface both failed to be.
-- Deep enough to SEE yourself drop. Butter gives a long way under weight, and at 0.85
-- the settle was a step you could miss; the whole point of a soft body under a brittle
-- shell is that once the shell fails there is nothing holding you up.
-- Raised with the block: gen_butter_skinned THICK went 2.3 -> 3.6, and a dent can only
-- be as deep as the body it is pressed into. At 1.5 into a 2.3-thick block the dent
-- floor was already near the underside, so there was no room to make the drop plainer.
-- Still a gentle slope underfoot -- this falls off over ~4 studs of cell, not a step.
-- Butter under the wax coating. ONE table rather than a family of separate top-level locals: this
-- module runs close to Luau's 200-register limit for a single scope, and constants
-- are the cheapest thing to fold. Every name and comment below is unchanged.
local WAX = {}
WAX.SINK = 2.3
WAX.SQUASH = 0.9    -- the cell flattens as it takes the load
WAX.RESIDUAL = 0.6  -- fraction of that dent the butter keeps after you step off
-- Matches INFLUENCE in gen_butter_skinned: the radius, as a multiple of cell size, that
-- the butter's own bone weights fall off over. The coating has to use the same one or
-- it curves at a different rate from the surface it sits on.
WAX.INFLUENCE = 1.25
-- HOW EACH COATING COMES APART. One table because ice and wax are the same rig driven
-- to opposite ends: wax is a film over something SOFT, so its plates ride a dent down and
-- barely separate, while ice is a sheet over NOTHING, so its plates hardly sink at all
-- until they let go completely and then swing wide.
--
-- `sideSpread` is above 1 for wax because a squashed block bulges at its walls, and the
-- side band leaving faster than the lid is the secondary effect of the top being pressed.
-- Ice keeps it near 1: nothing underneath is bulging, so the rim opens no faster than
-- anywhere else.
local SHELL_FEEL = {
	ButterWax = {
		spread = 0.16,      -- how far a plate slides off its rest position
		sideSpread = 2.2,
		tilt = 0.13,        -- radians, the lift on one edge of a plate
	},

	-- ICE FAILS IN STAGES, and each stage is a promise about the next one. The first
	-- step is a hairline you could walk away from; the second is a crack you can see
	-- daylight through and should not test again. Then it goes. If stages 1 and 2 looked
	-- alike the material would just be a floor that vanishes on a hidden counter.
	Ice = {
		snapTime = 0.07,    -- brittle: no ease in, no settle, it is done before you see it
		stages = {
			-- Hairline. Almost no slide, almost no tilt, no drop at all -- a frozen
			-- sheet does not sag under one step, and giving it any sink here made it
			-- read as thin butter.
			{ spread = 0.05, sideSpread = 1.0, tilt = 0.06, sink = 0, burst = 4 },
			-- Open. Now the plates visibly part and one edge lifts, and the sheet takes
			-- its only dip -- a quarter of a stud, which is the sheet bending, not the
			-- body denting.
			{ spread = 0.30, sideSpread = 1.15, tilt = 0.30, sink = -0.25, burst = 12 },
		},
		-- The give-way. Everything at once and downward: the plates are no longer held
		-- by anything, so they do not slide aside politely, they drop out of the frame.
		--
		-- `sink` is the PLATES and `bodySink` is what they were sitting on, and they are
		-- not the same number. The plates are loose fragments with nothing holding them,
		-- so they fall out of sight. The body is a 3.6-stud block being pulled down by one
		-- bone, and past about 3 studs the surface passes through its own underside and
		-- the mesh turns inside out -- so it goes just far enough to stop looking solid.
		give = { spread = 1.05, sideSpread = 1.3, tilt = 0.95, sink = -4.0, bodySink = -2.8, burst = 26, time = 0.18 },
	},
}

-- Shards live on ONE skinned MeshPart (WaxShell) with a bone each, not on separate
-- parts. Matched to cells by WORLD POSITION rather than by name: the fracture is a
-- Voronoi partition and knows nothing about the sub-region grid, so a shard belongs to
-- whichever cell happens to contain it.
-- Shards live on ONE skinned MeshPart (WaxShell) with a bone each, named by TIER:
-- Shard_T_* on the top, Shard_S_* around the sides, Shard_U_* underneath. All three
-- behave differently, so the whole platform's bones are collected once and sorted at
-- the point of use rather than being bucketed per cell.
--
-- Per cell was wrong twice over. Side bones sit at the platform's outer edge, OUTSIDE
-- every cell's bounds, so they were never collected and the sides never moved. And the
-- test only looked at XZ, so underside bones -- which are directly below a cell -- were
-- collected and driven, sinking the bottom of the block along with the top.
-- What each cell is currently doing to the coating it sits under.
type ShellProfile = { spread: number, sideSpread: number, tilt: number }
type Dent = { sink: number, crack: boolean, profile: ShellProfile }

-- ONE table rather than three top-level locals, because this module is close to Luau's
-- 200-register limit for a single scope and three more would have to come out of
-- something else. Weak keys throughout: shells and tiles are destroyed when a chunk is
-- torn down, and nothing else would ever remove them from here.
local shellCache = {
	bones = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: { Bone } },
	-- Per-bone tilt, drawn ONCE and kept. It used to be re-rolled on every application,
	-- which was invisible while a step only ever drove its own cell -- but a dent is now
	-- re-applied whenever ANY cell on the platform changes, and re-rolling would make
	-- every already-broken plate on the platform twitch each time someone stepped
	-- anywhere else on it.
	jitter = (setmetatable({}, { __mode = "k" }) :: any) :: { [Bone]: Vector3 },
	-- EVERY dent a shell is holding, not just the newest.
	--
	-- This is the fix for cracks disappearing as you walked on. driveShell used to take
	-- one cell and push every bone outside that cell's radius back to CFrame.identity, on
	-- the reasoning that a step elsewhere should release what the previous one moved. But
	-- the cell it moved away FROM is still broken -- the server holds it deformed for the
	-- material's whole decayDuration, nine seconds on ice -- so the shell was contradicting
	-- the state underneath it, and you could only ever see the single most recent break.
	-- Now a bone goes back to rest only when NO held dent claims it.
	dents = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: { [BasePart]: Dent } },
}

local function shellOf(tile: BasePart): BasePart?
	local slab = tile.Parent
	if not (slab and slab:IsA("BasePart")) then
		return nil
	end
	local shell = slab:FindFirstChild("WaxShell")
	return (shell and shell:IsA("BasePart")) and shell or nil
end

local function shardsFor(tile: BasePart): { Bone }
	local shell = shellOf(tile)
	if not shell then
		return {}
	end
	local cached = shellCache.bones[shell]
	if cached then
		return cached
	end

	local list: { Bone } = {}
	for _, descendant in ipairs(shell:GetDescendants()) do
		if descendant:IsA("Bone") and descendant.Name:match("^Shard_") then
			table.insert(list, descendant)
		end
	end
	shellCache.bones[shell] = list
	return list
end

-- Poses the whole coating from every dent it is currently holding.
--
-- Bones are authored pointing along Roblox +Y and every shard shares the mesh's
-- orientation, so a Transform in plain world axes moves them all correctly.
--
-- The sink FALLS OFF WITH DISTANCE instead of being applied flat to one cell's shards.
-- The body underneath is a skinned mesh whose bone influences overlap, so it dents in a
-- smooth curve; a coating driven a cell at a time stepped at every cell boundary and sat
-- visibly off the surface it is supposed to be lying on. Matching the body's own
-- cos-squared falloff over the same radius makes the coating follow the dip.
local function applyShell(shell: BasePart, info: TweenInfo)
	local dents = shellCache.dents[shell]
	local bones = shellCache.bones[shell]
	if not (dents and bones) then
		return
	end

	for _, bone in ipairs(bones) do
		-- THE UNDERSIDE NEVER MOVES. A block squashed from above does not also lift its
		-- own base, and watching the bottom drop with the top made it read as the whole
		-- platform sinking rather than as the surface giving way.
		if bone.Name:match("^Shard_U_") then
			continue
		end

		-- WORST DAMAGE WINS, PER COMPONENT -- not the nearest cell's opinion.
		--
		-- This loop used to pick a single winning dent by falloff and pose the shard from
		-- it alone, which meant the CLOSEST cell decided, whatever it was doing. Step on
		-- fresh ice beside a patch you had already broken and the fresh cell's stage-one
		-- hairline outranked the neighbour's open crack simply by being nearer, so every
		-- shard along the boundary snapped shut. On a cell that had already given way it
		-- was worse: plates that had dropped out came back up, while the body under them
		-- stayed where it had fallen -- a platform reporting itself intact over a hole you
		-- could still drop through. Moving fast made it obvious because that is when you
		-- put a fresh cell next to a broken one soonest.
		--
		-- Taking the maximum of each component instead makes damage MONOTONE: another
		-- cell breaking can only ever add to what a shard is already doing, and the only
		-- thing that reduces it is a dent being dropped from the books, which happens when
		-- the server decays that cell back to pristine. A broken plate stays broken.
		--
		-- Maximum rather than sum, because summing overlapping dents drove the plates
		-- twice as far as either cell asked for and a shard between three breaks left the
		-- mesh entirely.
		local side = bone.Name:match("^Shard_S_") ~= nil
		local sink, spread, tilt = 0, 0, 0
		local push = Vector3.zero

		for tile, dent in pairs(dents) do
			if not tile.Parent then
				-- The chunk was torn down under us.
				dents[tile] = nil
				continue
			end
			local offset = bone.WorldPosition - tile.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			-- Same radius the body rig weights its bones over (INFLUENCE * cell size),
			-- so the two surfaces curve together rather than one lagging the other.
			local radius = math.max(tile.Size.X, tile.Size.Z) * WAX.INFLUENCE
			local distance = flat.Magnitude
			if distance > radius then
				continue
			end

			local falloff = math.cos(math.pi * 0.5 * (distance / radius)) ^ 2
			-- Sinks are negative, so the DEEPEST is the smallest.
			sink = math.min(sink, dent.sink * falloff)

			if dent.crack then
				local profile = dent.profile
				local reach = profile.spread * (if side then profile.sideSpread else 1) * falloff
				if reach > spread then
					spread = reach
					-- The direction comes from whichever cell is opening this shard
					-- widest. A shard cannot slide two ways at once, and the widest
					-- claim is the one whose gap you can actually see.
					push = if distance > 0.01 then flat.Unit else Vector3.zero
				end
				tilt = math.max(tilt, profile.tilt * falloff)
			end
		end

		if sink == 0 and spread == 0 and tilt == 0 then
			-- Nothing on this platform is broken here any more. Note what this is NOT:
			-- it is not "the cell you just left", which is still deformed on the server
			-- for the whole of its decayDuration.
			TweenService:Create(bone, info, { Transform = CFrame.identity }):Play()
			continue
		end

		local transform = CFrame.new(0, sink, 0)
		if spread > 0 or tilt > 0 then
			-- Converted into the MESH's own space: a Bone's Transform is relative to its
			-- rest pose, so on a shell ChunkBuilder yawed 180 degrees a world-space push
			-- would come out pointing inward and close the shards instead of opening
			-- them. The sink needs no conversion -- the yaw is about Y.
			local local_ = shell.CFrame:VectorToObjectSpace(push)
			local jitter = shellCache.jitter[bone]
			if not jitter then
				jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
				shellCache.jitter[bone] = jitter
			end
			transform = CFrame.new(local_.X * spread, sink, local_.Z * spread)
				* CFrame.Angles(jitter.X * tilt, jitter.Y * tilt, jitter.Z * tilt)
		end
		TweenService:Create(bone, info, { Transform = transform }):Play()
	end
end

-- Records what ONE cell is doing to its coating, then re-poses the whole shell.
--
-- Recording rather than driving is the entire point: the shell is one mesh shared by every
-- cell on the platform, so it can only ever show one pose, and that pose has to be the
-- union of every break currently held -- not whichever cell reported last.
local function driveShell(tile: BasePart, info: TweenInfo, sink: number, crack: boolean, profile: ShellProfile?)
	local shell = shellOf(tile)
	local bones = shardsFor(tile)
	if #bones == 0 or not shell then
		return
	end

	local dents = shellCache.dents[shell]
	if not dents then
		dents = (setmetatable({}, { __mode = "k" }) :: any)
		shellCache.dents[shell] = dents
	end

	if not crack and math.abs(sink) < 0.001 then
		-- Closed AND flat: this cell is genuinely back to pristine, so drop it entirely
		-- and let its shards be claimed by another break or fall back to rest. Anything
		-- else -- butter holding its residual dent, ice sitting open -- stays on the
		-- books, which is what keeps it visible while you walk around on the rest of the
		-- platform.
		dents[tile] = nil
	else
		dents[tile] = {
			sink = sink,
			crack = crack,
			profile = profile or SHELL_FEEL.ButterWax,
		}
	end

	applyShell(shell, info)
end

-- Water thrown up through a hole in the ice.
--
-- Deliberately unlike iceBurst, which is dry, fast and falls hard. Water is heavier, so it
-- goes up slower and comes down sooner; it is also translucent and catches light, where
-- frost chips are opaque. Two bursts that behaved the same would make the fracture and the
-- fall read as one event, when they are a lid failing and then what was under it answering.
local function iceSplash(tile: BasePart)
	local origin = Instance.new("Attachment")
	origin.Name = "SplashOrigin"
	origin.Position = Vector3.new(0, -(restSize[tile] and restSize[tile].Y or 1) / 2, 0)
	origin.Parent = tile

	local water = Instance.new("ParticleEmitter")
	water.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	water.Color = ColorSequence.new(Color3.fromRGB(178, 214, 238))
	water.Size = NumberSequence.new(0.42)
	water.Lifetime = NumberRange.new(0.45, 0.85)
	-- Upward and narrow: water forced through a hole comes up as a column, not a cloud.
	water.Speed = NumberRange.new(9, 17)
	water.SpreadAngle = Vector2.new(26, 26)
	water.Rate = 0
	water.Acceleration = Vector3.new(0, -62, 0)
	water.Transparency = NumberSequence.new(0.25)
	water.LightEmission = 0.35
	water.Parent = origin
	water:Emit(24)
	Debris:AddItem(origin, 2)
end

-- Frost thrown off a fracture. Sharper and faster than butter's crumbs, and it falls
-- hard: these are chips of something rigid, not a soft material shaking loose.
local function iceBurst(tile: BasePart, count: number)
	local origin = Instance.new("Attachment")
	origin.Name = "IceChipOrigin"
	origin.Position = Vector3.new(0, (restSize[tile] and restSize[tile].Y or 1) / 2, 0)
	origin.Parent = tile

	local chips = Instance.new("ParticleEmitter")
	chips.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	chips.Color = ColorSequence.new(Color3.fromRGB(226, 244, 255))
	chips.Size = NumberSequence.new(0.08)
	chips.Lifetime = NumberRange.new(0.2, 0.45)
	-- Flat and fast. Ice chips skitter ACROSS a surface rather than puffing up off it,
	-- which is the difference between a fracture and a crumble.
	chips.Speed = NumberRange.new(4, 11)
	chips.SpreadAngle = Vector2.new(85, 85)
	chips.Rate = 0
	chips.Acceleration = Vector3.new(0, -70, 0)
	chips.Parent = origin
	chips:Emit(count)
	Debris:AddItem(origin, 1)
end

Effects.ButterWax = function(ctx: Ctx)
	local tile = ctx.tile

	if ctx.state == "deformed" then
		flingDebris(tile, "WaxFlake", 3)
		if not marks[tile] or #marks[tile] == 0 then
			for _, hit in ipairs(localFootWorldPoints(tile)) do
				spawnFootprint(tile, hit, ctx.material, 3.5)
			end
		end
		if not marks[tile] or #marks[tile] == 0 then
			-- TWO PHASES, and the order is the whole feel of the material.
			--
			-- The shell goes first and fast: a brittle film does not bend, it lets go
			-- all at once, so the shards snap apart on a Back ease in under a tenth of
			-- a second. Only then does the butter give, slowly and without rebound,
			-- carrying you down with it. One combined motion read as a single soft
			-- surface, which is the opposite of what a coating over a soft body does.
			--
			-- Nothing here DRAWS a crack. The shards are already cut into the shell
			-- mesh; this only pulls them apart, and the gaps that opens expose the
			-- butter beneath. An actual gap needs no contrast trick to read, because it
			-- is darker for the physical reason that it is a hole with butter at the
			-- bottom -- which is what neither the drawn fissures nor a part laid on the
			-- surface could ever be.
			local snap = TweenInfo.new(0.09, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			driveShell(tile, snap, 0, true)

			task.delay(0.09, function()
				if not tile.Parent or lastState[tile] ~= "deformed" then
					return
				end
				local settle = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
				moveTile(tile, settle, -WAX.SINK, 1, WAX.SQUASH)
				driveShell(tile, settle, -WAX.SINK, true)
			end)

			-- Fine crumbs shaken loose along the fracture.
			local shards = Instance.new("Attachment")
			shards.Name = "WaxCrumbOrigin"
			shards.Position = Vector3.new(0, restSize[tile].Y / 2, 0)
			shards.Parent = tile

			local crumbs = Instance.new("ParticleEmitter")
			crumbs.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			crumbs.Color = ColorSequence.new(Color3.fromRGB(246, 238, 214))
			crumbs.Size = NumberSequence.new(0.1)
			crumbs.Lifetime = NumberRange.new(0.25, 0.5)
			crumbs.Speed = NumberRange.new(2, 6)
			crumbs.SpreadAngle = Vector2.new(70, 70)
			crumbs.Rate = 0
			crumbs.Acceleration = Vector3.new(0, -50, 0)
			crumbs.Parent = shards
			crumbs:Emit(8)
			Debris:AddItem(shards, 1)

		end
	else
		-- BUTTER IS PLASTIC. It does not spring back -- warm butter keeps the shape it
		-- was pushed into, which is the property that separates it from every other
		-- material here: honey recovers slowly, slime snaps, soap is simply gone. So
		-- stepping off closes the shell but leaves most of the dent, and only the
		-- server's decay to pristine takes the surface fully back.
		local recover = TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local held = if ctx.state == "pristine" then 0 else -WAX.SINK * WAX.RESIDUAL
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, recover, held)
		else
			moveTile(tile, recover, held, 1, 1)
		end
		-- The shell settles at whatever the butter under it is holding, and STAYS BROKEN.
		-- It used to close as you stepped off, which was wrong twice: a brittle film that
		-- has snapped does not knit back together under its own weight, and the server
		-- still holds the cell deformed for the whole decayDuration, so the coating was
		-- reporting intact over a surface the game considered broken. Walk a diagonal
		-- across a platform and every break behind you healed the moment your foot left
		-- it, leaving one crack travelling around under you.
		--
		-- Only pristine closes it, and pristine means the server decayed the cell.
		-- Returning the plates to rest over a dented body would float them anyway.
		driveShell(tile, recover, held, ctx.state ~= "pristine")
		if ctx.state == "pristine" then
			clearMarks(tile)
			clearCracks(tile)
		end
	end
end

-- Slime: stretches, then rings. Sinks far while thinning in XZ and growing in Y,
-- which reads as goo drawn down under weight, and throws a fast springy wave out
-- across the rest of the platform.
--
-- The wave is the half that distinguishes it. Slime and honey are the two materials
-- most easily confused -- both glossy, both translucent, both slowing you on contact
-- -- and honey's identity is almost entirely in how its surface moves. Slime having
-- no surface motion at all beyond its own cell left the comparison one-sided.
-- Slime: the stretch, and how little of it survives. ONE table rather than a family of separate top-level locals: this
-- module runs close to Luau's 200-register limit for a single scope, and constants
-- are the cheapest thing to fold. Every name and comment below is unchanged.
local SLIME = {}
SLIME.RIPPLE = RippleProfiles.Slime
-- Shallower than honey's 1.55. Slime is elastic and pushes back; honey simply gives
-- way, and a press of the same depth in both makes them feel like one substance.
SLIME.PRESS = 1.05
-- And it barely holds the print at all. Honey keeps 38% of its press for the whole
-- decay window, which is the point of a viscous material; slime springs back to
-- almost flat, so what survives a footfall is a trace rather than a dent.
SLIME.RESIDUAL_FRACTION = 0.14
SLIME.NECK = 0.72   -- XZ scale under load, per-tile fallback only
SLIME.STRETCH = 2.6 -- Y scale under load, per-tile fallback only

Effects.Slime = function(ctx: Ctx)
	local tile = ctx.tile
	local size = restSize[tile]
	local slab = tile.Parent
	local onSlab = (slab and slab:IsA("BasePart")) and slab or nil
	-- Non-nil exactly when Slime_Platform_Skinned took over this platform.
	local bone = boneFor(tile)

	if ctx.state == "deformed" then
		flingDebris(tile, if ctx.material == "JelloSoda" then "JelloBit" else "SlimeGob", 3)
		-- The fine spray that goes with the gobs. Downward and fast: slime flicks, it does
		-- not drift, and this is the half of the shed that is too small to be a part.
		--
		-- Colour comes from ctx.material for the same reason the debris kind does -- this
		-- function is ALSO Effects.JelloSoda, and a jello platform spraying green would be
		-- the one bug a shared effect exists to cause.
		puff(tile, MaterialAppearance.Appearances[ctx.material].color, 0.16, 6, -26, 5)
		-- Sags far, necks inward in XZ and stretches tall in Y: mass being drawn
		-- downward rather than a box being scaled. This is the opposite of every
		-- other material here, which all compress.
		heldVisual[tile] = true
		-- Supersedes any wave in flight on this cell, so a crest cannot pull the
		-- surface back up from under a standing player.
		visualToken[tile] = (visualToken[tile] or 0) + 1
		moveTile(
			tile,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			-SLIME.PRESS,
			SLIME.NECK,
			SLIME.STRETCH
		)

		-- The stretch has to be applied to the MESH as well, not just the tile.
		--
		-- moveTile deliberately moves a Visual without scaling it, because scaling a
		-- mesh per frame is expensive and stretching honey's drips or bubble wrap's
		-- caps out of proportion looks worse than letting the cell sink. But once the
		-- slime meshes are imported the tile underneath is transparent, so on a
		-- correctly set-up game that rule made slime's entire "drawn downward"
		-- identity invisible -- the neck and stretch above were only ever visible
		-- with the meshes MISSING. Stretching is the one case where the deviation is
		-- right: it is the material's defining behaviour, not incidental detail.
		local visual, offset = visualOf(tile), visualOffset[tile]
		if visual and offset then
			if not slimeVisualRest[tile] then
				slimeVisualRest[tile] = visual.Size
			end
			local base = slimeVisualRest[tile] :: Vector3
			play(tile, visual, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(base.X * SLIME.NECK, base.Y * SLIME.STRETCH, base.Z * SLIME.NECK),
			})
		end

		-- The springy wave, and the ring train that rides its crest.
		--
		-- Two paths, picked the same way Effects.Honey picks: boneFor returns non-nil
		-- exactly when a skinned rig took over the platform. On the rig the wave runs
		-- through real geometry with overlapping bone influences, so it can be as
		-- deep as it likes; the per-tile fallback has to stay under the amplitude
		-- where edge-matched tiles visibly tear apart, and RippleProfiles.Slime is
		-- tuned for that lower ceiling.
		if onSlab then
			if bone then
				rippleFrom(onSlab, bone.WorldPosition, SLIME.RIPPLE)
			else
				rippleVisualsFrom(onSlab, tile.Position, SLIME.RIPPLE)
			end

			-- Derived from the material's own colour, darkened rather than saturated:
			-- a disturbance in slime differs from the slime around it by depth, not
			-- by hue.
			local ringColour = MaterialAppearance.Appearances.Slime.color:Lerp(Color3.new(0, 0, 0), 0.26)
			local feet = localFootWorldPoints(tile)
			spawnRipple(onSlab, tile, feet[1] and feet[1].position or tile.Position, ringColour, SLIME.RIPPLE)

			-- Prints, same as honey's but shallower (see FootprintProfiles.Slime).
			for _, foot in ipairs(feet) do
				spawnFootprint(tile, foot, ctx.material, ringTravel(SLIME.RIPPLE))
			end
		end

		-- Goo strands trailing off the underside of the sagging cell. Thin,
		-- tapering, slightly random, and they hang below the platform, which is
		-- what makes it read as viscous rather than springy.
		if not marks[tile] or #marks[tile] < 3 then
			local top = tileTop(tile)
			for _ = 1, 3 do
				local ox = (math.random() - 0.5) * size.X * 0.5
				local oz = (math.random() - 0.5) * size.Z * 0.5
				-- Centred 1.2 below the surface because the Size tween grows the
				-- cylinder symmetrically about its centre; at -0.4 a 2.2-long
				-- strand would poke 0.7 studs up through the tile it hangs from.
				local strand = newMarkPart(tile, Vector3.new(0.3, 0.3, 0.3), top * CFrame.new(ox, -1.2, oz))
				strand.Name = "SlimeStrand"
				strand.Shape = Enum.PartType.Cylinder
				-- Cylinders extend along their X axis, so roll 90 degrees about Z
				-- to make that axis vertical.
				strand.CFrame = top * CFrame.new(ox, -1.2, oz) * CFrame.Angles(0, 0, math.rad(90))
				MaterialAppearance.apply(strand, "Slime")
				strand.Transparency = 0.25
				addMark(tile, strand, 1.2)

				TweenService:Create(
					strand,
					TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Size = Vector3.new(2.2, 0.12, 0.12) }
				):Play()
			end
		end
	elseif bone then
		-- Skinned platform. Springs back to nearly flat rather than holding the dent
		-- honey holds: setResidual leaves a trace for the decay window and takes the
		-- collider back to rest on its own.
		clearMarks(tile)
		setResidual(
			tile,
			bone,
			TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			-SLIME.PRESS * SLIME.RESIDUAL_FRACTION
		)
	else
		-- Snap back with a real wobble: an Elastic return on a cell that was
		-- stretched 2.6x in Y overshoots visibly, which is the payoff.
		clearMarks(tile)
		heldVisual[tile] = nil
		-- Any wave still in flight on this cell was scheduled before the press and
		-- would drive the mesh somewhere else mid-return.
		visualToken[tile] = (visualToken[tile] or 0) + 1

		local info = TweenInfo.new(0.75, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
		play(tile, tile, info, { CFrame = restCFrame[tile], Size = restSize[tile] })

		-- The MESH has to come back too. This branch deliberately bypasses
		-- settleTile to get the Elastic wobble, and settleTile is what returns a
		-- Visual to rest for every other material -- so without this the mesh stayed
		-- wherever the press left it and slime sank one step further into the
		-- platform on every footfall, permanently, while the invisible tile
		-- underneath returned to rest exactly as intended.
		local visual, offset = visualOf(tile), visualOffset[tile]
		if visual and offset then
			local goal: { [string]: any } = { CFrame = restCFrame[tile] * offset }
			if slimeVisualRest[tile] then
				goal.Size = slimeVisualRest[tile]
			end
			play(tile, visual, info, goal)
		end
	end
end

-- === Soap: a bar that crumbles into loose cubes ===
--
-- The granules already exist in the built platform (see attachGranules in
-- ChunkBuilder), one 3 x 3 block per cell. Nothing here creates the look of soap
-- breaking; it breaks the pieces off the thing that was already made of pieces. That
-- is the difference from both earlier attempts: a tile mesh and a skinned rig were
-- each ONE piece of geometry per cell, so the only failure they could express was the
-- whole cell disappearing at once.
--
-- Seconds between cubes breaking off while you stand on a cell. Slow enough that you
-- watch it going, fast enough that the cell is visibly hollow before the server calls
-- it exhausted (Materials.Soap.dissolveTime).
local GRANULE_FALL_INTERVAL = 0.14

-- How far a cell has settled by the time the last cube goes. Applied in proportion to
-- how much is left, so you ride the surface down as it gives way instead of standing
-- at a fixed height on a cell that is visibly half gone.
-- Soap: how far it gives, and the crumbs it sheds. ONE table rather than a family of separate top-level locals: this
-- module runs close to Luau's 200-register limit for a single scope, and constants
-- are the cheapest thing to fold. Every name and comment below is unchanged.
local SOAP = {}
SOAP.MAX_SINK = 1.7
SOAP.PRESS = 0.2   -- immediate give on contact, before anything has broken

-- Landing hard bursts a patch at once. Below IMPACT_MIN (walking on, or stepping down
-- a stud) nothing extra happens; above it, one extra cube per IMPACT_PER studs/second.
-- A default jump lands at roughly 50 studs/second, so it costs about four cubes.
SOAP.IMPACT_MIN, SOAP.IMPACT_PER, SOAP.IMPACT_MAX = 18, 12, 6

-- Physics parts are the expensive thing here, and a player can stand on a bridge for a
-- long time. Past the cap the cube still disappears from the bar, it just does not get
-- a physical copy -- the platform still fails correctly, only the debris thins out.
SOAP.CRUMB_CAP = 90
SOAP.CRUMB_LIFE = 8
SOAP.CRUMB_FADE = 1.2

-- THE CRACKS (see Fissure): how many run out from the first foot on a cell and about how far, how much
-- further a later step runs them, and each cube falling out, and how fast they run.
SOAP.CRACK_ARMS, SOAP.CRACK_REACH, SOAP.CRACK_STEP, SOAP.CRACK_CREEP, SOAP.CRACK_SPEED = 3, 1.0, 0.45, 0.25, 5

local granuleRest: { [BasePart]: CFrame } = {}
-- Each cube's authored transparency, captured before it is ever hidden, so a cell that
-- decays back comes back with its own variation rather than one flat value.
local granuleLook: { [BasePart]: number } = {}
local granuleTotal: { [BasePart]: number } = {}
local crumbling: { [BasePart]: boolean } = {}
local liveCrumbs = 0

local function eachGranule(tile: BasePart, fn: (BasePart) -> ())
	for _, child in ipairs(tile:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^Granule_") then
			fn(child)
		end
	end
end

local function standingGranules(tile: BasePart): { BasePart }
	local list = {}
	eachGranule(tile, function(granule)
		if granule.Transparency < 1 then
			table.insert(list, granule)
		end
	end)
	return list
end

-- Granules are children of the tile, but parenting a Part to a Part creates no
-- transform hierarchy in Roblox, so they do NOT follow it down. Same problem
-- visualOffset solves for meshes, and without this the bar stays put while the
-- collider you are standing on sinks out from under it.
local function sinkGranules(tile: BasePart, info: TweenInfo, sink: number)
	eachGranule(tile, function(granule)
		local rest = granuleRest[granule]
		if not rest then
			rest = granule.CFrame
			granuleRest[granule] = rest
		end
		TweenService:Create(granule, info, { CFrame = rest * CFrame.new(0, sink, 0) }):Play()
	end)
end

local function dropGranule(tile: BasePart, granule: BasePart)
	if not granuleLook[granule] then
		granuleLook[granule] = granule.Transparency
	end
	-- A TOP CUBE TAKES THE CRACKS DRAWN OVER IT, and the cracks round the hole open up. See Fissure.
	if granule.Name:sub(1, 10) == "Granule_1_" then
		Fissure.shatter(tile, granule)
	end
	-- Cloned BEFORE the original is hidden. The clone is what carries this cube's own
	-- colour, gloss and transparency over to the crumb, and copying it after hiding
	-- would carry the hidden state instead.
	local frag = if liveCrumbs < SOAP.CRUMB_CAP then granule:Clone() else nil

	-- HIDDEN, not destroyed. Soap that never reaches exhausted decays back to pristine
	-- on the server, and the cell has to be able to come back whole.
	--
	-- COLLISION GOES WITH THE VISIBILITY. The cubes are the floor now, so a hidden
	-- granule that still collided would be invisible floor -- exactly the "no cubes
	-- left but I am still standing" problem, moved down a level and made harder to see.
	granule.Transparency = 1
	granule.CanCollide = false

	if not frag then
		return
	end
	liveCrumbs += 1

	frag.Name = "SoapCrumb"
	frag.Anchored = false
	-- COLLIDABLE on purpose, and this is the point of the whole approach: a fallen
	-- crumb is debris you can kick out of your way. Density well under default so the
	-- exchange only goes one way -- you shove it, it never shoves you off a bridge.
	frag.CanCollide = true
	frag.CanTouch = false
	frag.CanQuery = false
	frag.CustomPhysicalProperties = PhysicalProperties.new(0.25, 0.4, 0.15)
	-- No MaterialAppearance.apply here: it would overwrite Colour, Reflectance and
	-- Transparency with the material defaults and flatten out the per-cube variation
	-- the clone was taken for.
	frag.Parent = tile.Parent
	frag.AssemblyLinearVelocity = Vector3.new(
		(math.random() - 0.5) * 3,
		-math.random() * 2,
		(math.random() - 0.5) * 3
	)
	frag.AssemblyAngularVelocity = Vector3.new(
		(math.random() - 0.5) * 8,
		(math.random() - 0.5) * 8,
		(math.random() - 0.5) * 8
	)

	-- Dust falling WITH the cube rather than puffing at the break point: the emitter
	-- rides the crumb down, so the powder shares its trajectory instead of hanging in
	-- the air above it. Acceleration is a little stronger than gravity so the dust
	-- trails behind rather than drifting up.
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(
		MaterialAppearance.Appearances.Soap.color:Lerp(Color3.new(1, 1, 1), 0.35)
	)
	dust.Size = NumberSequence.new(0.16, 0.5)
	dust.Transparency = NumberSequence.new(0.45, 1)
	dust.Lifetime = NumberRange.new(0.3, 0.7)
	dust.Speed = NumberRange.new(0.5, 2)
	dust.SpreadAngle = Vector2.new(35, 35)
	dust.Rate = 0
	dust.Acceleration = Vector3.new(0, -24, 0)
	dust.Parent = frag
	dust:Emit(5)

	-- Shrink and fade over the last stretch. Popping out of existence mid-air is what
	-- the fixed Debris lifetime did on its own, and it is the one moment the debris
	-- stops looking physical.
	task.delay(SOAP.CRUMB_LIFE - SOAP.CRUMB_FADE, function()
		if frag.Parent then
			TweenService:Create(
				frag,
				TweenInfo.new(SOAP.CRUMB_FADE, Enum.EasingStyle.Linear),
				{ Transparency = 1, Size = frag.Size * 0.35 }
			):Play()
		end
	end)
	task.delay(SOAP.CRUMB_LIFE, function()
		liveCrumbs -= 1
	end)
	Debris:AddItem(frag, SOAP.CRUMB_LIFE)
end

-- The cube that goes next is the one nearest your foot, not a random one in the cell.
-- Picking at random spreads the collapse evenly across a cell however you stand on it,
-- which reads as the platform being on a timer rather than as you breaking it. Chosen
-- from the three nearest rather than strictly the closest, so repeated steps in one
-- spot do not drill a single clean column.
local function nextGranule(tile: BasePart, left: { BasePart }): BasePart
	local feet = localFootWorldPoints(tile)
	if #feet == 0 then
		return left[math.random(1, #left)]
	end

	local ranked = table.clone(left)
	local distance: { [BasePart]: number } = {}
	for _, granule in ipairs(ranked) do
		local best = math.huge
		for _, foot in ipairs(feet) do
			local d = (granule.Position - foot.position).Magnitude
			if d < best then
				best = d
			end
		end
		distance[granule] = best
	end
	table.sort(ranked, function(a, b)
		return distance[a] < distance[b]
	end)
	return ranked[math.random(1, math.min(3, #ranked))]
end

-- Settle the cell in proportion to how much of it is gone.
local function settleCrumbling(tile: BasePart, remaining: number)
	local total = granuleTotal[tile]
	if not total or total == 0 then
		return
	end
	-- Runs from the initial contact press down to the full sink, so it only ever
	-- deepens. Scaling the whole range from zero instead would lift the cell back up
	-- on the first cube, because the contact press is already deeper than one cube's
	-- worth of collapse.
	local sink = -SOAP.PRESS - (SOAP.MAX_SINK - SOAP.PRESS) * (1 - remaining / total)
	local info = TweenInfo.new(GRANULE_FALL_INTERVAL, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	moveTile(tile, info, sink, 1, 1)
	sinkGranules(tile, info, sink)
end

-- Extra cubes burst by the impact of landing, on top of the steady crumbling.
local function impactCubes(): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return 0
	end
	local falling = -root.AssemblyLinearVelocity.Y
	if falling < SOAP.IMPACT_MIN then
		return 0
	end
	return math.min(SOAP.IMPACT_MAX, 1 + math.floor((falling - SOAP.IMPACT_MIN) / SOAP.IMPACT_PER))
end

local function startCrumbling(tile: BasePart)
	if crumbling[tile] then
		return
	end
	crumbling[tile] = true

	if not granuleTotal[tile] then
		granuleTotal[tile] = #standingGranules(tile)
	end

	task.spawn(function()
		-- Landing hard takes a patch out immediately, before the steady rhythm starts.
		for _ = 1, impactCubes() do
			local left = standingGranules(tile)
			if #left == 0 then
				break
			end
			dropGranule(tile, nextGranule(tile, left))
		end

		-- DERIVED from the server's dissolve timer and the actual cube count, not set
		-- independently. The two have to finish together: the last cube leaving is the
		-- moment the cell stops being floor, and if the crumbling ran slower the cell
		-- would drop out from under a bar that still looked half solid. Hardcoding an
		-- interval happened to line up at 18 cubes and a 2.5s timer, and would have
		-- quietly stopped lining up the moment either changed.
		local total = granuleTotal[tile] or 0
		local interval = total > 0 and (Materials.Soap.dissolveTime / total) or GRANULE_FALL_INTERVAL

		while crumbling[tile] and tile.Parent do
			local left = standingGranules(tile)
			if #left == 0 then
				break
			end
			dropGranule(tile, nextGranule(tile, left))
			settleCrumbling(tile, #left - 1)
			-- The cracks run on ahead of the crumbling.
			Fissure.extend(tile, SOAP.CRACK_CREEP, SOAP.CRACK_SPEED)
			task.wait(interval)
		end
		crumbling[tile] = nil
	end)
end

local function soapDust(tile: BasePart)
	local rest = restCFrame[tile]
	local soap = MaterialAppearance.Appearances.Soap

	-- An invisible carrier for the emitter. A ParticleEmitter is not a BasePart and has no
	-- position of its own, so it needs something in the world to hang off.
	local host = Instance.new("Part")
	host.Name = "SoapDust"
	host.Size = Vector3.new(0.2, 0.2, 0.2)
	host.CFrame = rest
	host.Anchored = true
	host.CanCollide = false
	host.CanTouch = false
	host.CanQuery = false
	host.CastShadow = false
	host.Transparency = 1
	host.Parent = tile.Parent

	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(soap.color:Lerp(Color3.new(1, 1, 1), 0.35))
	dust.Size = NumberSequence.new(0.3, 1.2)
	dust.Transparency = NumberSequence.new(0.4, 1)
	dust.Lifetime = NumberRange.new(0.35, 0.85)
	dust.Speed = NumberRange.new(1, 4)
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.Rate = 0
	dust.Acceleration = Vector3.new(0, -14, 0)
	dust.Parent = host
	dust:Emit(14)
	-- The HOST goes, not the emitter: removing the part takes its child with it, and
	-- removing only the emitter would leave an invisible part behind on every footfall.
	Debris:AddItem(host, 1.5)
end

-- Soap: crumbles away under you a cube at a time while you stand on it, and when the
-- server calls the cell exhausted whatever is left goes at once. The slab beneath a
-- granular platform is non-colliding (see GRANULAR in ChunkBuilder), so the hole the
-- crumbs leave is a hole you fall through rather than a dent onto solid slab.
Effects.Soap = function(ctx: Ctx)
	local tile = ctx.tile

	if ctx.state == "exhausted" then
		crumbling[tile] = nil
		cancelTweens(tile)
		clearMarks(tile)
		clearCracks(tile)
		tile.Transparency = 1

		for _, granule in ipairs(standingGranules(tile)) do
			dropGranule(tile, granule)
		end
		soapDust(tile)
		return
	end

	if ctx.state == "deformed" then
		-- Soap flakes come off dry and drift: the one granular material here that does not
		-- throw grit downward.
		puff(tile, MaterialAppearance.Appearances.Soap.color, 0.16, 4, 3, 7)
		-- Only the contact press here. The rest of the sink is driven by how much of
		-- the cell has actually crumbled (settleCrumbling), so the surface gives at the
		-- rate it is failing rather than dropping one fixed step and then holding.
		local press = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		moveTile(tile, press, -SOAP.PRESS, 1, 1)
		-- The bar has to come down with the collider, or you sink into a surface that
		-- stays where it was.
		sinkGranules(tile, press, -SOAP.PRESS)

		-- THE CRACKS RUN FROM YOUR FOOT (see Fissure). The first step on a cell starts them where the foot
		-- came down; a step on a cell already cracked runs those on and starts a short new set under the new
		-- foot, instead of drawing nine more on top -- which is what turned a busy cell into a scribble. They
		-- keep running as the bar crumbles, and every cube that falls out takes the cracks over it.
		--
		-- The colour is DERIVED from the soap's and taken most of the way to black. A fixed blue-grey looked
		-- right on near-white soap and wrong the moment it went pink, and a crack is a gap: it carries the
		-- warning that a cell is about to drop out, whatever colour the bar is.
		local crack = MaterialAppearance.Appearances.Soap.color:Lerp(Color3.new(0, 0, 0), 0.72)
		local from = Fissure.footOf(tile, ctx.who)
		if Fissure.has(tile) then
			Fissure.extend(tile, SOAP.CRACK_STEP, SOAP.CRACK_SPEED)
			Fissure.grow(tile, { from = from, arms = 2, reach = SOAP.CRACK_STEP, thick = 3,
				speed = SOAP.CRACK_SPEED, color = crack, splits = 0 })
		else
			Fissure.grow(tile, { from = from, arms = SOAP.CRACK_ARMS, reach = SOAP.CRACK_REACH, thick = 3,
				speed = SOAP.CRACK_SPEED, color = crack, splits = 1 })
		end
		-- AFTER the cracks, not before: the first cube goes the moment crumbling starts, and it has to find
		-- the cracks over it already drawn to take them with it.
		startCrumbling(tile)
	else
		crumbling[tile] = nil
		settleTile(tile, 0.5)
		sinkGranules(tile, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), 0)
		if ctx.state == "pristine" then
			-- Decayed back before it ever exhausted, so the cell comes back whole.
			-- The TILE stays hidden: on a granular platform the granules are the
			-- surface and the tile is only the collider.
			clearMarks(tile)
			-- The cracks close as the bar mends, rather than vanishing a frame before it does.
			Fissure.heal(tile, 0.5)
			eachGranule(tile, function(granule)
				-- ONLY cubes that actually broke off are restored, and only to the
				-- exact value they were authored with.
				--
				-- Falling back to the material default for the rest is what made the
				-- bar go translucent as you walked on it. granuleLook is recorded in
				-- dropGranule, so a cube that never broke has no entry -- and the
				-- fallback then slammed it to 0.3 when ChunkBuilder had authored
				-- anywhere from 0.24 to 0.41. Half the bar got lighter, it happened on
				-- every decay cycle to every cube in a cell merely walked across, and
				-- the per-cube variation flattened out along with it.
				local look = granuleLook[granule]
				if look then
					granule.Transparency = look
					granule.CanCollide = true
				end
			end)
		end
	end
end

-- === Bubble wrap: pockets moulded into the sheet, driven by bones ===
--
-- This used to spawn a Part per bubble, and that could never be bubble wrap for three
-- reasons no amount of tuning reaches. The spheres sat ON the surface instead of being
-- part of it. A Part cannot deform -- it scales, so a "pop" was a whole ball shrinking
-- rather than a dome flattening while its rim stayed put. And there was no film between
-- them at all, so the material read as a tray of marbles on a plate.
--
-- The sheet is a skinned mesh now, with one bone per pocket: the same move honey, slime
-- and butter each ended up making. Each pocket's vertices are weighted by how far up its
-- own dome they sit (apex 1.0, rim 0.0, film 0.0), so pulling one bone straight down by
-- POCKET.H collapses that pocket into the sheet and moves nothing else in the mesh.
--
-- Pockets are matched to a footfall by WORLD POSITION, never by name or index. The
-- lattice is a fixed 1.3-stud pitch anchored at the mesh origin and knows nothing about
-- the sub-region grid, so which pockets sit under a given cell is a question only
-- geometry can answer.

-- Must match BUBBLE_H in gen_bubble_wrap.py: the distance a bone travels to put its
-- apex exactly on the film.
-- Bubble wrap pockets. ONE table rather than a family of separate top-level locals: this
-- module runs close to Luau's 200-register limit for a single scope, and constants
-- are the cheapest thing to fold. Every name and comment below is unchanged.
local POCKET = {}
POCKET.H = 0.64
-- How far past flat a pocket snaps at the instant it goes, and what it keeps afterwards.
-- The residual is NOT zero. A burst pocket is slack film puckered slightly inward, and
-- settling it to exactly flat read as the bubble being deleted rather than emptied.
POCKET.PUNCH = 1.15
-- What a burst pocket keeps, and it is deliberately well short of flat: 0.68 leaves
-- about a third of the height standing as a low crumpled mound.
--
-- At 0.9 a popped pocket was 0.06 studs proud of the film, which is nothing -- popped
-- sheet was indistinguishable from sheet that never had a pocket there, so you could
-- not see where you had already walked. Every other material leaves a trail (honey
-- smears, sand footprints, wax cracks) and this one was erasing its own.
POCKET.SLACK = 0.68
-- How far the pocket bulges under the weight before it goes. This is the anticipation
-- beat and it is the visible half of the pop, since everything below flat is hidden
-- inside the film.
POCKET.SWELL = 0.26
-- Burst radius around a footfall, in studs. ONLY WHAT YOU ACTUALLY TROD ON.
--
-- This was 2.4, deliberately, to burst a knot of three or four at a time -- and that
-- was wrong: at a 2.0 pitch it reaches a 4.8-stud circle, so a single step took out
-- pockets more than a bubble's width away from your foot and the sheet appeared to pop
-- itself. 1.05 is a foot half-width plus a pocket radius, so a pocket goes when the
-- foot is genuinely over it and not otherwise.
POCKET.REACH = 1.05

-- REACH IS MEASURED OFF THE SHEET, not taken from the constant above.
--
-- 1.05 studs was right for the only lattice that existed: pockets every 2 studs, so a
-- foot anywhere on the sheet is within reach of one. The giant sheet spaces them every
-- 4, and at a fixed 1.05 you would be standing in the gap between pockets most of the
-- time and bursting nothing -- the platform would eat your steps, spend its pop budget
-- and collapse under you with almost nothing having visibly popped.
--
-- The lattice describes itself: the closest two pockets on a regular grid ARE one pitch
-- apart, so the pitch can be measured rather than declared, and any future sheet at any
-- spacing gets a sensible reach without being told. Cached per bone list, and only ever
-- as large as needed to cover half the diagonal of one cell.
local reachCache: { [any]: number } = {}

local function reachFor(pockets: { Bone }): number
	local cached = reachCache[pockets]
	if cached then
		return cached
	end
	local closest = math.huge
	for i = 1, #pockets do
		local a = pockets[i].WorldPosition
		for j = i + 1, #pockets do
			local b = pockets[j].WorldPosition
			local dx, dz = a.X - b.X, a.Z - b.Z
			local distance = dx * dx + dz * dz
			if distance < closest then
				closest = distance
			end
		end
	end
	-- A single pocket has no neighbour to measure against, so fall back to the constant.
	local reach = if closest == math.huge then POCKET.REACH else math.sqrt(closest) * 0.55
	reachCache[pockets] = reach
	return reach
end

-- How far a burst reaches into the film around it, and how hard. A sheet is under
-- tension: one pocket letting go snatches at its neighbours, and they wobble without
-- bursting. This is most of what makes a pop feel like an event rather than a state
-- change, because it is the only part that happens to something you did not step on.
-- Pulled in with the burst radius. The shock is a WOBBLE, never a burst -- nothing
-- outside your foot ever pops -- but at 3.4 it reached most of a platform's width and
-- the whole sheet twitched at once, which is its own kind of "it did that by itself".
-- 2.4 is a little over one pitch: the ring of pockets immediately around the one that
-- went, and nothing further.
local SHOCK_RADIUS = 2.4
local SHOCK_DEPTH = 0.45

-- Seconds between one pocket going and the next in the same footfall. Bursting a knot
-- of them on the same frame is one dull thud; a few tens of milliseconds apart is a
-- crackle, which is the sound bubble wrap actually makes.
local POP_STAGGER = 0.035

local sheetBones: { [BasePart]: { Bone } } = {}
local burstBones: { [Bone]: boolean } = {}
local warnedNoSheet = false
local function pocketsFor(tile: BasePart, layer: number?): { Bone }
	local slab = tile.Parent
	if not (slab and slab:IsA("BasePart") and slab:GetAttribute("SkinnedVisual")) then
		return {}
	end
	local sheet = slab:FindFirstChild("SkinnedVisual")
	if not (sheet and sheet:IsA("BasePart")) then
		return {}
	end
	-- ONE CACHE PER SHEET PER LAYER. A stacked sheet carries two independent sets of
	-- pockets and a cell works its way down them, so caching only the first set would
	-- pin every platform to its top layer forever.
	local prefix = if (layer or 1) > 1 then ("Bubble" .. tostring(layer) .. "_") else "Bubble_"
	local byLayer = sheetBones[sheet]
	if byLayer and byLayer[prefix] then
		return byLayer[prefix]
	end
	if not byLayer then
		byLayer = {}
		sheetBones[sheet] = byLayer
	end
	-- Collected for the WHOLE PLATFORM once, not per cell. A pocket near a cell border
	-- is driven by whichever foot is nearest it, and bucketing by cell first would stop
	-- a step near an edge from touching the pockets just across that line.
	local list: { Bone } = {}
	for _, descendant in ipairs(sheet:GetDescendants()) do
		-- An exact prefix match, so "Bubble_3" never answers a request for "Bubble2_".
		if descendant:IsA("Bone") and descendant.Name:sub(1, #prefix) == prefix then
			table.insert(list, descendant)
		end
	end
	byLayer[prefix] = list
	return list
end

-- The film around a burst pocket snatches taut, so its neighbours dip and spring back
-- without bursting. Elastic on the way out: the sheet is under tension and overshoots.
local function shockNeighbours(pockets: { Bone }, origin: Vector3)
	for _, other in ipairs(pockets) do
		if not burstBones[other] then
			local at = other.WorldPosition
			local dx, dz = at.X - origin.X, at.Z - origin.Z
			local distance = math.sqrt(dx * dx + dz * dz)
			if distance <= SHOCK_RADIUS then
				-- Squared cosine, the same falloff the butter and the wax use, so a
				-- shock dies away at the same rate the other materials' dents do.
				local falloff = math.cos(math.pi * 0.5 * (distance / SHOCK_RADIUS)) ^ 2
				local dip = -POCKET.H * SHOCK_DEPTH * falloff
				TweenService:Create(other, TweenInfo.new(0.06), {
					Transform = CFrame.new(0, dip, 0),
				}):Play()
				task.delay(0.07, function()
					if other.Parent and not burstBones[other] then
						TweenService:Create(
							other,
							TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
							{ Transform = CFrame.identity }
						):Play()
					end
				end)
			end
		end
	end
end

-- The puff of air a pocket lets go of. Tiny, fast, and gone: the point is a flicker at
-- the instant of the burst, not a cloud.
local function popPuff(tile: BasePart, at: Vector3)
	local anchor = Instance.new("Attachment")
	anchor.Name = "PopPuff"
	anchor.WorldPosition = at
	anchor.Parent = tile

	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/smoke_main.dds"
	burst.Color = ColorSequence.new(Color3.fromRGB(244, 250, 255))
	burst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1.1),
	})
	burst.Lifetime = NumberRange.new(0.12, 0.2)
	burst.Speed = NumberRange.new(3, 6)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Rate = 0
	burst.Parent = anchor
	burst:Emit(5)
	Debris:AddItem(anchor, 0.6)
end

-- One pocket going: SWELL, snap, then settle to slack film.
--
-- Three stages rather than one tween, because a pop is not a movement, it is a failure,
-- and a single ease to the final height is the shape of something deflating.
--
-- The swell is where the drama actually lives, and it took a render to work out why.
-- The obvious dramatic beat is to overshoot PAST flat and recoil -- but the cap cannot
-- be seen below the film, because the film is a solid box and the collapsed pocket
-- simply hides inside it. All that motion is invisible. Anticipation is the half that
-- shows: the pocket swells under the weight, THEN lets go, and the eye reads the swell
-- as pressure and the drop as failure. It also happens to be what bubble wrap does.
--
-- 85ms of wind-up before the collapse, which is under the threshold where a response to
-- your own footfall starts to feel disconnected from it.
local function burstPocket(tile: BasePart, pockets: { Bone }, bone: Bone)
	if burstBones[bone] then
		return
	end
	burstBones[bone] = true
	local origin = bone.WorldPosition

	TweenService:Create(bone, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transform = CFrame.new(0, POCKET.H * POCKET.SWELL, 0),
	}):Play()

	task.delay(0.05, function()
		if not (bone.Parent and burstBones[bone]) then
			return
		end
		TweenService:Create(bone, TweenInfo.new(0.035, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			Transform = CFrame.new(0, -POCKET.H * POCKET.PUNCH, 0),
		}):Play()
		popPuff(tile, origin)
		shockNeighbours(pockets, origin)

		task.delay(0.04, function()
			-- Still burst: a decay to pristine in between clears the flag and
			-- re-inflates, and this must not then drag it back down.
			if bone.Parent and burstBones[bone] then
				TweenService:Create(
					bone,
					TweenInfo.new(0.34, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
					{ Transform = CFrame.new(0, -POCKET.H * POCKET.SLACK, 0) }
				):Play()
			end
		end)
	end)
end

-- ===== Creamy keyboard =====
--
-- ONE LOCAL FOR THE WHOLE MATERIAL, and that is a hard constraint rather than a style.
--
-- Luau allocates at most 200 local registers per function scope, and this module's main
-- chunk was already within a handful of that ceiling. The keyboard originally declared
-- eight top-level locals and the compiler gave up partway through them:
--
--   Out of local registers when trying to allocate keysFor: exceeded limit 200
--
-- which is a COMPILE error, so the module never loaded and every client service that
-- requires it went down with it.
--
-- Wrapping the section in a `do` block did NOT fix it, and the reason is worth writing
-- down: a block releases its registers when it ENDS. The failure is at the peak, inside
-- the block, where the main chunk's own locals are all still live and the block's are
-- stacked on top of them. Scoping changes what is reachable afterwards, never the high
-- water mark during.
--
-- Collapsing everything into a single table is what actually reduces the count -- eight
-- registers become one, and the fields cost nothing because they live in the table rather
-- than in the enclosing scope. Any future material added to this file should be written
-- the same way; there is no room left for the obvious style.
do
	local Keys = {
		-- How far a key travels, as a fraction of its height. Not all the way: a cap that
		-- sank until its top was level with the chassis would read as a hole in the field,
		-- and real switches bottom out with the cap still proud of the plate.
		PRESS = 0.42,
		-- gen_keyboard.py's KEY_HEIGHT. A plain number rather than read off the mesh: an
		-- attribute nothing sets is not configuration, it is a lie with a default behind it.
		HEIGHT = 0.75,
		-- Reach as a fraction of the measured lattice pitch. See the note where it is used.
		REACH_SCALE = 0.55,

		-- THE TIMING IS THE MATERIAL. "Creamy" is a keyboard word for a specific feel:
		-- smooth travel, damped bottom-out, no ping and no bounce. So the press is fast and
		-- the return is slower and completely overshoot-free -- a Back or Elastic curve
		-- here would turn a creamy linear into a rattly clicky, which is a different
		-- keyboard and a worse ASMR.
		--
		-- 90ms down is inside the 100ms window a tap needs its feedback in; 380ms up sits
		-- just past the 150-300ms micro-interaction band on purpose, because the SLOW
		-- return is what the eye and ear read as damping.
		DOWN = TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		UP = TweenInfo.new(0.38, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),

		cache = {},
		held = {},
		warned = false,
	}

	function Keys.bonesFor(tile: BasePart)
		local slab = tile.Parent
		if not (slab and slab:IsA("BasePart") and slab:GetAttribute("SkinnedVisual")) then
			return {}
		end
		local field = slab:FindFirstChild("SkinnedVisual")
		if not (field and field:IsA("BasePart")) then
			return {}
		end
		local cached = Keys.cache[field]
		if cached then
			return cached
		end
		local list = {}
		for _, descendant in ipairs(field:GetDescendants()) do
			if descendant:IsA("Bone") and descendant.Name:sub(1, 4) == "Key_" then
				table.insert(list, descendant)
			end
		end
		Keys.cache[field] = list
		return list
	end

	-- Reach measured off the lattice, so no constant here has to be kept in step with the
	-- generator: the two closest keys on a regular grid are exactly one pitch apart.
	function Keys.reachFor(keys)
		local closest = math.huge
		for i = 1, #keys do
			local a = keys[i].WorldPosition
			for j = i + 1, #keys do
				local b = keys[j].WorldPosition
				local dx, dz = a.X - b.X, a.Z - b.Z
				local distance = dx * dx + dz * dz
				if distance < closest then
					closest = distance
				end
			end
		end
		return if closest == math.huge then 2.0 else math.sqrt(closest) * Keys.REACH_SCALE
	end

	Effects.CreamyKeyboard = function(ctx: Ctx)
		local tile = ctx.tile
		local keys = Keys.bonesFor(tile)
		if #keys == 0 then
			if not Keys.warned then
				Keys.warned = true
				warn(
					"DeformationRenderer: a CreamyKeyboard tile has no skinned field, so no keys will press. "
						.. "Import Keyboard_Field_*.fbx into ReplicatedStorage/Assets/TileMeshes WITH its Bone children."
				)
			end
			return
		end

		local points = {}
		for _, hit in ipairs(localFootWorldPoints(tile)) do
			table.insert(points, hit.position)
		end
		if #points == 0 then
			table.insert(points, tile.Position)
		end

		local reach = Keys.reachFor(keys)
		local depth = Keys.HEIGHT * Keys.PRESS

		for _, bone in ipairs(keys) do
			local at = bone.WorldPosition
			local nearest = math.huge
			for _, foot in ipairs(points) do
				local dx, dz = at.X - foot.X, at.Z - foot.Z
				nearest = math.min(nearest, dx * dx + dz * dz)
			end
			if nearest <= reach * reach then
				-- A token per key, so a second footfall on a key that is still returning
				-- takes it over cleanly instead of the two tweens fighting and the key
				-- stalling half pressed.
				local token = (Keys.held[bone] or 0) + 1
				Keys.held[bone] = token

				TweenService:Create(bone, Keys.DOWN, { Transform = CFrame.new(0, -depth, 0) }):Play()
				task.delay(0.11, function()
					if bone.Parent and Keys.held[bone] == token then
						TweenService:Create(bone, Keys.UP, { Transform = CFrame.identity }):Play()
					end
				end)
			end
		end

		-- The chassis takes the weight too, very slightly. A field of keys moving over a
		-- perfectly rigid plate reads as a screen; a plate that gives a hundredth of a stud
		-- reads as a board sitting on a desk.
		moveTile(tile, Keys.DOWN, -0.05, 0.98, 1.0)
		task.delay(0.14, function()
			if tile.Parent then
				settleTile(tile, 0.3)
			end
		end)
	end
end

-- ICE CRACKS LIKE WAX; JELLO WOBBLES LIKE SLIME.
--
-- Both are aliases rather than copies, and neither is a shortcut. Effects.ButterWax
-- fractures a shell of plates over a soft body -- read the description without the name
-- attached and it is a sheet of ice. Effects.Slime deforms a soft rig and lets it spring
-- back. Nothing in either function is specific to its material: the one place Slime's was
-- (a hardcoded "Slime" passed to spawnFootprint) now reads ctx.material, which was a
-- latent bug of its own -- any future material sharing that effect would have got slime's
-- footprints.
--
-- Aliasing also keeps this file's top-level local count flat, which matters: it is five
-- away from Luau's 200-register ceiling.
-- ICE: a sheet over open water, failing in three stages.
--
-- Butter and ice share a rig and nothing else. Butter is a brittle film over something
-- SOFT: the film snaps, and then the body under it gives slowly and keeps the shape.
-- Ice is a sheet over NOTHING, so it has no give at all -- it holds, holds, and then
-- stops holding. Pointing Effects.Ice at Effects.ButterWax made it a cold-coloured
-- butter: it sagged under the first step, which is the one thing ice must never do,
-- because a surface that visibly deforms is a surface telling you it will hold.
--
-- What warns you instead is the FRACTURE WIDENING. Stage one is a hairline, stage two
-- is a gap, and the third step is not a stage at all.
Effects.Ice = function(ctx: Ctx)
	local tile = ctx.tile
	local feel = SHELL_FEEL.Ice

	if ctx.state == "pristine" then
		-- Refrozen. The only state that closes the sheet.
		local settle = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		driveShell(tile, settle, 0, false)
		moveTile(tile, settle, 0, 1, 1)
		clearMarks(tile)
		clearCracks(tile)
		return
	end

	if ctx.state == "exhausted" then
		-- Shards as well as frost. iceBurst throws dust, and dust is what a surface sheds
		-- when it is ground; a sheet that FRACTURES has to leave pieces with an edge on them.
		flingDebris(tile, "IceShard", 6)
		-- THE SPLASH. What is under a frozen sheet is water, and until now falling through
		-- one produced a shower of dry frost chips and nothing else -- which said the ice
		-- was sitting over more ice. A burst of water thrown UP through the hole is the
		-- thing that makes the sheet read as a lid on something rather than as a slab.
		iceSplash(tile)
		-- IT LETS GO. Quint easing IN, so the plates barely move for the first half of
		-- the tween and then leave -- an accelerating failure, which is how something
		-- brittle actually goes. Ease Out here read as the plates being lowered.
		local give = feel.give
		local drop = TweenInfo.new(give.time, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		driveShell(tile, drop, give.sink, true, give)
		-- The body goes with them. The server has already cleared collision, so this is
		-- only about not leaving a solid-looking surface under the hole you fell through.
		moveTile(tile, drop, give.bodySink, 1, 1)
		iceBurst(tile, give.burst)
		return
	end

	-- "deformed" on the way in, "decaying" once you step off -- and they pose the SAME,
	-- which is the point. The crack you made stays exactly as wide as you made it until
	-- the server decays the cell, rather than easing shut behind you.
	local stage = math.clamp(ctx.stepCount or 1, 1, #feel.stages)
	local plan = feel.stages[stage]
	local snap = TweenInfo.new(feel.snapTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	driveShell(tile, snap, plan.sink, true, plan)
	if ctx.state == "deformed" then
		iceBurst(tile, plan.burst)
	end
end
-- LAMB'S EAR: a soft press that stays pressed.
--
-- The whole material is one idea -- DRY SOFT THINGS HOLD A MARK -- and it is the only
-- surface in the game that answers a footfall with almost nothing at the moment of
-- contact and almost everything afterwards. Honey and slime move dramatically and recover;
-- this barely moves and does not recover at all until the cell decays.
--
-- One table rather than six top-level locals: this module sits five short of Luau's
-- 200-register limit for a single scope, and constants are the cheapest thing to fold.
local LAMBS = {
	-- Shallower than slime's 1.05 and much shallower than honey's 1.55. A mat of leaves
	-- compresses, it does not swallow you, and a deep dent here would read as standing in
	-- something rather than on it.
	press = 1.15,
	-- HOW MUCH OF THE PRESS SURVIVES THE FOOT LEAVING, and it is nearly all of it. Honey
	-- keeps 38% because it is viscous, slime keeps 14% because it is elastic. Crushed
	-- foliage springs back least of the three: the leaves under your weight are bent, and
	-- bent is where they stay.
	residual = 0.72,
	-- Slow both ways. Nothing about this material is sudden -- a fast tween on a soft
	-- surface reads as a hard one, which is the whole thing this is trying not to be.
	pressTime = 0.30,
	releaseTime = 0.85,
	-- Long enough to outlast the cell's six second decay, so the mark never vanishes
	-- before the surface under it has actually recovered.
	markLife = 6.5,
}

Effects.LambsEar = function(ctx: Ctx)
	local tile = ctx.tile

	if ctx.state == "deformed" then
		-- Fibres lift rather than fall. The gentlest emit in the game.
		puff(tile, MaterialAppearance.Appearances.LambsEar.color, 0.14, 2, 4, 4)
		flingDebris(tile, "LeafHair", 3)
		local press = TweenInfo.new(LAMBS.pressTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, press, -LAMBS.press)
		else
			moveTile(tile, press, -LAMBS.press, 1, 1)
		end

		-- ONE MARK PER VISIT, not one per replicated event. The cell re-announces itself
		-- every time you re-enter it, and stamping each time would stack prints on the
		-- same spot until the nap read as a solid patch.
		if not marks[tile] or #marks[tile] == 0 then
			-- Every foot in contact, the way sand does it, rather than one print per
			-- cell. A stride puts two feet on a wide platform and the trail is the whole
			-- point of the material, so a single mark per cell would lose half of it.
			for _, hit in ipairs(localFootWorldPoints(tile)) do
				spawnFootprint(tile, hit, ctx.material, LAMBS.markLife, LAMBS.press * 0.5)
			end
		end
	else
		local release = TweenInfo.new(LAMBS.releaseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local held = if ctx.state == "pristine" then 0 else -LAMBS.press * LAMBS.residual
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, release, held)
		else
			moveTile(tile, release, held, 1, 1)
		end
		if ctx.state == "pristine" then
			clearMarks(tile)
		end
	end
end

-- The seven newest materials, in ONE table. Seven separate families of top-level
-- constants would be about thirty registers, and this module has a hard ceiling of 200
-- for the whole chunk scope -- the seven existing families were folded into tables for
-- the same reason before any of this was written.
local NEW_MATS = {
	-- Foam keeps giving for as long as you stand on it. `dwell` is how deep it gets to,
	-- `rate` is how long that takes, and `rebound` is the slow rise afterwards -- slower
	-- than the press, because memory foam recovers visibly slower than it compresses and
	-- that asymmetry is the entire character of the material.
	Foam = { press = 0.9, dwell = 2.6, rate = 2.2, rebound = 1.6, tick = 0.1,
		-- Torn cell walls. Slow and few: foam is almost weightless, so what comes off it
		-- drifts rather than flies, and `throw` is the lowest here by a distance.
		shed = 3, throw = 7 },
	-- A switch throws in under a tenth of a second and then holds. No easing worth the
	-- name: a rocker has an over-centre spring and it is either one way or the other.
	--
	-- BRIGHTNESS AND RANGE BOTH CUT HARD, from 1.6 and 11. The arithmetic was the thing
	-- missed: there is one of these per CELL, and a 16 x 12 platform is a 5 x 4 lattice, so
	-- twenty lights were overlapping on one slab. Each looked reasonable alone and together
	-- they blew the whole platform to flat white and washed out the two chunks either side.
	-- At 0.85 and 7 a single switch is a warm pool with a clear edge, and twenty lit at once
	-- still sit well short of the flat white the first version produced. 0.5 turned out to
	-- be an over-correction -- readable, but so faint that a switch you had thrown from a
	-- distance was hard to pick out from one you had not.
	Switch = { drop = 0.55, time = 0.07, glow = Color3.fromRGB(255, 226, 150), range = 7, bright = 0.85 },
	-- LEGO NEVER MOVES ITS MESH, and now it does not need to.
	--
	-- Two wrong answers came before this one. First the cell bone was lifted a few
	-- hundredths of a stud per step -- but a bone on a SKINNED mesh drags every vertex
	-- within a cell and a quarter along a cos-squared falloff, so the whole plate rolled in
	-- waves and the platform read as rubber. Then the lift was dropped and a dark plate was
	-- faded in over the cell instead, which deformed nothing but was a PICTURE of a missing
	-- brick rather than a missing brick.
	--
	-- ChunkBuilder now gives every lego cell its own anchored Part with its own studs
	-- (attachBrick), spanning the FULL depth of the platform -- there is no slab visual
	-- left underneath, so a brick that comes away leaves a hole straight through it.
	--
	-- `lift` and `cant` are per step. The lift goes UPWARD, which no other material here
	-- does -- everything else gives way downward under load, and a brick being levered out
	-- of a baseplate rises. `cant` is the tilt in radians, because a brick working loose
	-- comes up on one corner first rather than straight.
	Lego = {
		lift = { 0.04, 0.13, 0.30 },
		cant = { 0.010, 0.035, 0.085 },
		time = 0.09,
		fly = 22,
		spin = 15,
		-- Small pieces that go down with you. Six: enough to fill the frame beside a
		-- falling player, few enough that a chunk collapsing does not fill the sky.
		companions = 6,
		-- Radians the neighbours tip toward a fresh hole. Small: the plate should look
		-- loosened, not damaged.
		jostle = 0.055,
	},
	-- `flake` per step against `shards` on failure. Charcoal sheds the whole time it is
	-- being walked on -- that is why it gets on everything -- and the difference between
	-- the two numbers is the difference between shedding and breaking.
	Charcoal = { jolt = 0.10, drop = 2.9, time = 0.13, dust = 22, flake = 3, shards = 7, throw = 21,
		-- THE EMBERS. Spark and smoke rates and the light's low and high as it flickers, for a smouldering
		-- coal and a burning one, and how fast it flickers; the burst when a coal catches or is stamped
		-- on, and how long a fresh coal takes to settle into its hole.
		smoulderSparks = 2, smoulderSmoke = 0.6, smoulderLow = 0.25, smoulderHigh = 0.75,
		burnSparks = 10, burnSmoke = 2.4, burnLow = 1.1, burnHigh = 2.3,
		flicker = 0.16, lightRange = 9, catchBurst = 12, stompBurst = 18, regrow = 0.55,
		-- THE CRACKS, which grow (see Fissure). How bright they draw, how far the glow in them swings
		-- either way as it breathes, and how long a breath is; how many creep out from where the coal
		-- caught, how far and how thick; how far they run on and how much they open when it bursts into
		-- flame, and how fast; how far into the burn they go white-hot; a stamp's new cracks, how far and
		-- how fast; and their colours, smouldering, burning, white-hot and ash.
		crackBright = 2.4, glowSwing = 0.4, breath = 0.45,
		catchArms = 3, catchReach = 0.9, catchThick = 2,
		burnReach = 1.6, burnWiden = 1.6, burnSpeed = 4.5, whiteAt = 0.62,
		stompReach = 0.8, stompSpeed = 9,
		warm = Color3.fromRGB(196, 62, 18), hot = Color3.fromRGB(255, 176, 64),
		white = Color3.fromRGB(255, 238, 196), ash = Color3.fromRGB(96, 92, 90) },
	-- Chocolate's melt is a GLOSS change first and a shape change second: it loses its
	-- temper before it loses its form, which is what melting actually looks like. `gloss`
	-- is the tempered mirror it starts at and `wet` is where it ends up -- higher, not
	-- lower, because melted chocolate is shinier than set chocolate, not duller.
	Chocolate = {
		melt = 2.4, time = 0.5, gloss = 0.20, wet = 0.42,
		stages = {
			{ gloss = 0.28, sink = 0.10 },   -- just off tempered; you would not notice alone
			{ gloss = 0.36, sink = 0.32 },   -- visibly wet, and starting to give underfoot
			{ gloss = 0.42, sink = 0.70 },   -- soft. The next step is not going to hold.
		},
	},
	-- CLAY MOVES. `press` is how far a cell goes down per squeeze, and `rise` how far each squeeze
	-- of clay pushed INTO a cell lifts it, up to `riseCap` of them. `slide` and `curl` are how far a
	-- lip bulges out over its edge and droops by the time it tears. `collide` is how much of the
	-- shape your feet follow -- most of it, because walking over the ridges is the point. The peel
	-- is the lip tearing off: its thickness, how far it swings on its hinge, how long that takes,
	-- and how far the bed under it funnels away.
	Clay = { press = 0.42, rise = 0.26, riseCap = 4, slide = 0.5, curl = 0.32, collide = 0.8,
		time = 0.22, pushTime = 0.6, markLife = 1e6,
		peelThick = 1.1, peelAngle = 1.9, peelTime = 0.5, hole = 7, holeSlide = 0.9 },
	-- Salt PACKS, and the crust beside it HEAVES. `steps` is the depth packed so far, a running
	-- total rather than a pose. `heave` is the lift one push of brine gives a plate, and `lift` and
	-- `tilt` the plate once it is floating. `collide` is near what the bed's own surface does under
	-- a bone, so cracks drawn on the collider sit on the crust. `shed` is crystals thrown clear per
	-- step, and like `crunch` it falls off as the cell packs. The sink is a plate going under: the
	-- funnel, how far under the surface the crust sinks to, and how many pieces of it go under.
	Salt = { steps = { 0.16, 0.30, 0.42 }, time = 0.14, crunch = 10, shed = 4, throw = 16,
		heave = 0.05, lift = 0.3, tilt = 0.17, collide = 0.62, heaveTime = 0.7,
		hairlines = 2, tiltCracks = 3, crackLife = 1200,
		hole = 6.5, sinkTime = 0.45, brineDepth = 1.2, floes = 3 },
	-- Lava CRUSTS. `cool` is how far the colour is dragged toward obsidian per step, and it
	-- is the whole read: the shape barely moves, the glow goes out.
	-- `shards` per step and `burst` when the raft fails. Two kinds of debris, because two
	-- things are coming off: black crust that has already set, and melt from underneath it
	-- that has not.
	Lava = { cool = { 0.45, 0.75, 0.92 }, sink = 0.18, time = 0.30, embers = 14, drop = 3.4,
		shards = 3, burst = 7, throw = 19 },
	-- Oobleck STIFFENS. A sharp upward jolt on contact -- the surface pushing back harder
	-- than it was pushed -- and then nothing at all until you stop.
	-- Oobleck does NOTHING while you keep moving, which is the whole material. `rate` is
	-- studs per second of sink and it only runs while a foot is continuously on the cell.
	-- `shed` is PARTICLES ONLY. The surface still does not move on contact -- that is the
	-- whole material -- but a foot landing on a slurry does throw a little of it, and
	-- flecks leaving the cell say nothing about the cell yielding.
	Oobleck = { rate = 1.1, cap = 2.4, tick = 0.1, sink = 3.2, splash = 26, shed = 3, throw = 12,
		-- WADING AND STAMPING. How deep the surface and the collider go at a full wade, how fast a wade
		-- step lands, the pop of a hardening shock spreading a cell every `shockStep`, the gobs a stamp
		-- throws, how fast a player goes under, how a hole fills, how the surface levels. No cracks: it
		-- is a liquid that goes hard for a moment, not a crust.
		deep = 2.3, floorDeep = 1.2, wadeTime = 0.3, pop = 0.22, shockStep = 0.045,
		stampGobs = 6, through = 0.2, heal = 0.7, level = 0.6 },
	-- THE KEYPAD'S THREE SWITCHES, and the numbers are how each one feels. Each travels `drop`, down
	-- to about flush with its bezel, where the lit core still shows; how it gets there is the switch.
	-- CLICKY goes down in a twentieth of a second on a Quart ease IN, so it accelerates into the stop,
	-- and comes back up past where it started. LINEAR is smooth both ways. TACTILE stops `bump` of the
	-- way down against its leaf, holds, and gives. `flash` is how far toward white a pressed core
	-- goes, `ripple` how strongly the lights around it answer; `breath` and `dim` are the idle glow.
	Button = {
		clicky = { drop = 0.18, down = 0.045, up = 0.16, overshoot = 0.05, settle = 0.12, bump = 1,
			flash = 0.75, hold = 0.06, fade = 0.4, ripple = 0.5 },
		linear = { drop = 0.18, down = 0.12, up = 0.18, overshoot = 0, settle = 0, bump = 1,
			flash = 0.35, hold = 0, fade = 0.35, ripple = 0.22 },
		tactile = { drop = 0.18, down = 0.05, up = 0.1, overshoot = 0, settle = 0, bump = 0.45,
			flash = 0.5, hold = 0.07, fade = 0.3, ripple = 0.3 },
		rippleStep = 0.05, rippleFade = 0.32,
		-- THE ELECTRICITY. Sparks off a clicky cap and how fast; the arc that jumps to the next lane button
		-- ahead and how long it hangs; how bright that button answers; the overload a full circuit sets
		-- off, and the camera shake a combo or a circuit gives the player who made it.
		sparks = 14, sparkSpeed = 16, arcTime = 0.16, aheadFlash = 0.6, aheadFade = 0.35,
		overloadBurst = 5, overloadRange = 26, overloadTime = 1.1, shake = 0.35, shakeTime = 0.35,
		burst = 2.2, burstRange = 9, burstTime = 0.4,
		ringGrow = 2.8, ringTime = 0.42,
		comboFlash = 0.9, comboBurst = 3.4, comboRange = 18, comboTime = 0.9,
		breath = 1.3, dim = 0.72,
		-- THE CAPACITOR (violet). Sparks a second, per charge, in the crackle a charged player carries,
		-- its light per charge and how far that reaches; the discharge into a clicky button, its light at
		-- three charges and how far, and its flash wave.
		auraSparks = 6, auraLight = 0.45, auraRange = 7, dischargeBurst = 3, dischargeRange = 16, dischargeWave = 18,
		-- THE SPRING (pink). How bright a set spring's cores flash per level; on a launch, how far the caps
		-- fly up past rest per level, the flash wave, sparks per level, and seconds of pink streak under
		-- the jumper per level.
		springGlow = 0.3, springFling = 0.06, springWave = 12, springSparks = 8, springStreak = 0.3,
	},
	-- Snow PACKS. Like salt it accumulates, but it is going somewhere: the last step drops
	-- the cell out rather than levelling it off.
	-- `printLife` outlasts the cell's own nine second decay, so a print never fades off a
	-- surface that is still holding it -- the snow goes first, which is the right order.
	Snow = { steps = { 0.30, 0.55, 0.78 }, time = 0.22, drop = 2.6, puff = 16, printLife = 11 },
	-- Cold chocolate breaks into SEGMENTS, and that is why the pieces are big and few
	-- where charcoal's are small and many. A bar snaps along its moulded grooves, so what
	-- comes off is a handful of recognisable rectangles -- not splinters, which would say
	-- it shattered, and not one brick, which would say it came away whole.
	ChocolateSolid = { jolt = 0.08, drop = 3.0, time = 0.12, pieces = 4, throw = 17 },
	-- Cloud never stops. `rate` is studs per second of sink and it runs the whole time a
	-- foot is on the cell.
	-- Faster than it was (1.5), with the cloud's own clock shortened to match, and `drop` for the moment
	-- it finally gives out.
	Cloud = { rate = 2.1, cap = 3.2, tick = 0.1, recover = 1.2, drop = 3.6 },
	-- EVERY COLLAPSE UNDER YOU. The downward speed you start falling at, the extra weight for the first
	-- moment of the fall as a multiple of gravity, and how long that lasts.
	Fall = { snap = 34, pull = 1.1, pullTime = 0.55 },
}

-- Sinks a cell further the longer someone stands on it, and stops the moment they leave.
--
-- Foam and cloud are the only two materials whose depth is a function of TIME rather than
-- of events, so they are the only two that need a loop at all. It is guarded on lastState
-- rather than on a flag of its own: the server already announces the cell leaving
-- "deformed", and a second source of truth about whether a foot is still there is a second
-- thing that can disagree with the first.
local function dwellSink(tile: BasePart, rate: number, cap: number, tick: number)
	task.spawn(function()
		local depth = 0
		while tile.Parent and lastState[tile] == "deformed" and depth < cap do
			depth = math.min(cap, depth + rate * tick)
			local bone = boneFor(tile)
			local info = TweenInfo.new(tick, Enum.EasingStyle.Linear)
			if bone then
				setResidual(tile, bone, info, -depth)
			else
				moveTile(tile, info, -depth, 1, 1)
			end
			task.wait(tick)
		end
	end)
end

-- Which switches are currently thrown. Weak-keyed, because tiles are destroyed when a
-- chunk is torn down and nothing else would ever clear them from here.
local switchOn = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: boolean }

-- Where each lego brick started, so a lifted one can be put back when its cell decays.
-- Read once and kept: reading it live would return the pose the last tween left, and the
-- brick would settle a little further out of its socket on every pass.
local brickRest = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: CFrame }

-- Where each button cap sits at rest. Read once and kept, for the reason brickRest is:
-- reading it live returns whatever the last tween left, so the cap would settle a little
-- further down on every press.
local capRest = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: CFrame }

-- Throws pieces of the platform into the air.
--
-- Shared by lego and charcoal because the mechanic is the same one -- a cell that fails by
-- SHEDDING rather than by sinking -- and they are the only two here that do it. Everything
-- else in the game deforms, dissolves or drops; these two come apart, and the difference is
-- worth having one place to express.
--
-- `chunky` is what separates them. Lego throws ONE clean rectangular brick, because that is
-- what a brick is; charcoal throws a handful of angular splinters at random orientations,
-- because charcoal has no shape of its own -- it only has the shape it broke into.
Effects.Foam = function(ctx: Ctx)
	local tile = ctx.tile
	if ctx.state == "deformed" then
		puff(tile, MaterialAppearance.Appearances.Foam.color, 0.26, 2, 5, 4)
		local press = TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, press, -NEW_MATS.Foam.press)
		else
			moveTile(tile, press, -NEW_MATS.Foam.press, 1, 1)
		end
		-- ...and then keeps going, which is the whole material.
		dwellSink(tile, (NEW_MATS.Foam.dwell - NEW_MATS.Foam.press) / NEW_MATS.Foam.rate, NEW_MATS.Foam.dwell, NEW_MATS.Foam.tick)

		-- Torn cell walls, drifting off. Foam does not spatter or crumble -- open-cell
		-- structure tears, and the pieces are light enough that they hang for a moment
		-- before they fall. That is why `throw` is a third of everything else here.
		flingDebris(tile, "FoamBit", NEW_MATS.Foam.shed)

		-- THE HOLLOW OUTLIVES THE CELL, which is the only reason this material is called
		-- memory foam. Seven seconds against the cell's five: the platform is back to
		-- pristine underneath while the shape of your foot is still sitting in it.
		if not marks[tile] or #marks[tile] == 0 then
			for _, hit in ipairs(localFootWorldPoints(tile)) do
				spawnFootprint(tile, hit, ctx.material, 7)
			end
		end
	else
		-- SLOWER COMING BACK THAN GOING DOWN. Memory foam's name is about this: the hollow
		-- outlives the thing that made it, and rising at the speed it sank would make it
		-- ordinary upholstery.
		local rise = TweenInfo.new(NEW_MATS.Foam.rebound, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local held = if ctx.state == "pristine" then 0 else -NEW_MATS.Foam.press * 0.5
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, rise, held)
		else
			moveTile(tile, rise, held, 1, 1)
		end
	end
end

Effects.LightSwitch = function(ctx: Ctx)
	local tile = ctx.tile

	if ctx.state == "pristine" then
		-- The server decayed the cell, so the switch resets whatever the player left it at.
		switchOn[tile] = nil
	elseif ctx.state == "deformed" then
		-- TOGGLED, NOT LATCHED ON. Latching made every switch a one-way trip, so a platform
		-- filled up with light and could never be emptied -- and a switch you cannot turn
		-- off is not a switch, it is a button that sticks.
		--
		-- The flip happens ONLY on "deformed", which the server sends once per genuine
		-- entry into the cell. Stepping off sends "decaying" and is deliberately not handled
		-- below, because a rocker does not throw itself back when you take your foot away.
		switchOn[tile] = not switchOn[tile]
	end

	local on = switchOn[tile] == true
	local throw = TweenInfo.new(NEW_MATS.Switch.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local bone = boneFor(tile)
	local drop = if on then -NEW_MATS.Switch.drop else 0
	if bone then
		setResidual(tile, bone, throw, drop)
	else
		moveTile(tile, throw, drop, 1, 1)
	end

	local glow = tile:FindFirstChild("SwitchGlow")
	if on then
		if not glow then
			local light = Instance.new("PointLight")
			light.Name = "SwitchGlow"
			light.Color = NEW_MATS.Switch.glow
			light.Brightness = 0
			light.Range = NEW_MATS.Switch.range
			light.Shadows = false
			light.Parent = tile
			glow = light
		end
		TweenService:Create(glow, throw, { Brightness = NEW_MATS.Switch.bright }):Play()
	elseif glow then
		TweenService:Create(glow, throw, { Brightness = 0 }):Play()
		Debris:AddItem(glow, NEW_MATS.Switch.time + 0.05)
	end
end

-- Shakes the bricks around one that has just gone.
--
-- A LEGO PLATE COMES APART, it does not lose one square in isolation. Pulling a brick out of
-- a real plate loosens its neighbours, and without that the platform reads as a grid of
-- independent tiles that happen to be adjacent -- which is the difference between something
-- falling apart and something being deleted a cell at a time.
--
-- Neighbours are found by distance among the slab's own tiles rather than by grid index,
-- because a cell knows its own position and nothing about the lattice it sits in. One and a
-- half cells reaches the four orthogonal neighbours and the diagonals without going further.
local function jostleNeighbours(tile: BasePart)
	local slab = tile.Parent
	if not (slab and slab:IsA("BasePart")) then
		return
	end
	local reach = math.max(tile.Size.X, tile.Size.Z) * 1.5
	for _, other in ipairs(slab:GetChildren()) do
		if other ~= tile and other:IsA("BasePart") then
			local brick = other:FindFirstChild("Brick")
			if brick and brick:IsA("BasePart") and brick.Transparency < 1 then
				local away = brick.Position - tile.Position
				local flat = Vector3.new(away.X, 0, away.Z)
				local distance = flat.Magnitude
				if distance > 0.01 and distance <= reach then
					local rest = brickRest[brick] or brick.CFrame
					brickRest[brick] = rest
					-- Falls off with distance, and tips AWAY from the hole -- a brick
					-- settles into the gap its neighbour left, so the edge nearest the
					-- hole is the one that drops.
					local amount = NEW_MATS.Lego.jostle * (1 - distance / reach)
					local axis = flat.Unit
					TweenService:Create(
						brick,
						TweenInfo.new(0.22, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
						{ CFrame = rest * CFrame.Angles(axis.Z * amount, 0, -axis.X * amount) }
					):Play()
				end
			end
		end
	end
end

-- Loose pieces that fall alongside the player.
--
-- Started at the PLAYER's velocity rather than at rest, which is the whole trick. A piece
-- dropped from the platform is immediately left behind, because you have been accelerating
-- since the floor went and it has not. Matching your velocity first puts them in your frame,
-- and their smaller size and drag pulls them apart from you gradually -- which reads as
-- falling together, where anything else reads as debris being left above.
local function fallingCompanions(tile: BasePart)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local velocity = (root and root:IsA("BasePart")) and root.AssemblyLinearVelocity or Vector3.zero
	local origin = restCFrame[tile] or tile.CFrame
	local colour = MaterialAppearance.Appearances.Lego.color

	for index = 1, NEW_MATS.Lego.companions do
		local piece = Instance.new("Part")
		piece.Name = "FallingBrick"
		-- Assorted small pieces rather than copies of one brick: a 1x1, a 1x2 and a flat
		-- plate are the shapes that actually come loose off a lego build, and three
		-- silhouettes tumbling at different rates look like debris where one repeated
		-- silhouette looks like a spawner.
		local kind = index % 3
		piece.Size = if kind == 0 then Vector3.new(0.9, 0.9, 0.9)
			elseif kind == 1 then Vector3.new(1.8, 0.9, 0.9)
			else Vector3.new(1.6, 0.32, 1.6)
		piece.CFrame = origin
			* CFrame.new(
				(math.random() - 0.5) * tile.Size.X * 1.6,
				-1 - math.random() * 2,
				(math.random() - 0.5) * tile.Size.Z * 1.6)
			* CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
		piece.Color = colour:Lerp(Color3.new(0, 0, 0), math.random() * 0.18)
		piece.Material = Enum.Material.Plastic
		piece.Anchored = false
		piece.CanCollide = false
		piece.CanTouch = false
		piece.CanQuery = false
		piece.AssemblyLinearVelocity = velocity + Vector3.new(
			(math.random() - 0.5) * 6, 0, (math.random() - 0.5) * 6)
		piece.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 10, (math.random() - 0.5) * 10, (math.random() - 0.5) * 10)
		piece.Parent = workspace
		-- Longer than the brick's own debris: these are meant to be company for the whole
		-- fall, and the fall to the kill plane takes a while.
		Debris:AddItem(piece, 9)
	end
end

Effects.Lego = function(ctx: Ctx)
	local tile = ctx.tile
	local brick = tile:FindFirstChild("Brick")
	if not (brick and brick:IsA("BasePart")) then
		-- No brick means the platform was built before attachBrick existed, or the cell is
		-- not lego at all. Nothing here degrades into a mesh deformation on purpose: a
		-- silent no-op is better than reintroducing the rubber-plate bug on a stale build.
		return
	end
	local rest = brickRest[brick]
	if not rest then
		rest = brick.CFrame
		brickRest[brick] = rest
	end

	if ctx.state == "exhausted" then
		-- IT COMES OFF -- BUT NOT BY UNANCHORING THIS PART.
		--
		-- That was the first attempt and it produced the exact symptom reported: the brick
		-- rose, sat there, and vanished four seconds later. The reason is ownership. This
		-- file is a CLIENT script and the brick is a server-created anchored Part, so
		-- clearing Anchored here does not hand the client a body to simulate -- the server
		-- still owns it and still considers it anchored, so it does not fall. Then the
		-- Debris call, which DID work locally, deleted it. Rise, freeze, disappear.
		--
		-- A client can only simulate physics on a part it created. So the server's brick is
		-- hidden locally and a local copy is thrown in its place. The copy is genuinely
		-- client-owned and falls properly; hiding the original is a local property change,
		-- which is allowed and is undone when the cell decays.
		local loose = brick:Clone()
		loose.Name = "LooseBrick"
		loose.CFrame = brick.CFrame
		loose.Anchored = false
		loose.CanCollide = false
		loose.CanTouch = false
		loose.CanQuery = false
		-- Mostly SIDEWAYS and only a little up. A brick prised out of a plate is pushed
		-- out of its socket, not launched -- throwing it straight up reads as an explosion,
		-- and this material is meant to come apart rather than detonate.
		loose.AssemblyLinearVelocity = Vector3.new(
			(math.random() - 0.5) * NEW_MATS.Lego.fly,
			NEW_MATS.Lego.fly * 0.22,
			(math.random() - 0.5) * NEW_MATS.Lego.fly)
		loose.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * NEW_MATS.Lego.spin,
			(math.random() - 0.5) * NEW_MATS.Lego.spin,
			(math.random() - 0.5) * NEW_MATS.Lego.spin)
		-- DESCENDANTS, not children, and every one of them.
		--
		-- This is what left studs hanging in the air over a hole. GetChildren reaches one
		-- level, and the stack is deeper than that now -- courses hang off the top brick and
		-- studs hang off the courses -- so anything below the first level kept its Anchored
		-- flag and simply stayed where the brick had been.
		--
		-- The welds ChunkBuilder puts on the stack are what make these fall as ONE piece
		-- rather than as a shower of separate parts that happen to start together: parenting
		-- alone does not build an assembly in Roblox, only a joint does.
		for _, piece in ipairs(loose:GetDescendants()) do
			if piece:IsA("BasePart") then
				piece.Anchored = false
				piece.CanCollide = false
				piece.CanTouch = false
			end
		end
		loose.Parent = workspace
		Debris:AddItem(loose, 6)

		-- The rest of the plate feels it.
		jostleNeighbours(tile)

		-- ...and a handful of loose pieces go down WITH the player.
		--
		-- The brick that came away is thrown sideways, which is right for the brick and
		-- wrong for the moment: what you see from inside the fall is the platform receding
		-- above you and nothing else. Sending a few small pieces down alongside gives the
		-- drop something to measure itself against -- they hang beside you at first because
		-- they start at your speed, then separate as air resistance tells on the small ones.
		-- It is the difference between falling and the camera simply moving down.
		fallingCompanions(tile)

		-- And a scatter of chips off the join. Small, hard and dry: ABS does not crumble,
		-- it snaps, so these are few and sharp rather than a puff of dust.
		local origin = Instance.new("Attachment")
		origin.Name = "BrickChipOrigin"
		origin.Position = Vector3.new(0, (restSize[tile] and restSize[tile].Y or 1) / 2, 0)
		origin.Parent = tile
		local chips = Instance.new("ParticleEmitter")
		chips.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		chips.Color = ColorSequence.new(MaterialAppearance.Appearances.Lego.color)
		chips.Size = NumberSequence.new(0.12)
		chips.Lifetime = NumberRange.new(0.3, 0.6)
		chips.Speed = NumberRange.new(5, 12)
		chips.SpreadAngle = Vector2.new(80, 80)
		chips.Rate = 0
		chips.Acceleration = Vector3.new(0, -80, 0)
		chips.Parent = origin
		chips:Emit(9)
		Debris:AddItem(origin, 1.5)

		-- The socket is empty now. Hiding rather than destroying, because the server owns
		-- this part and will want it back when the cell decays -- and a Destroy() here is
		-- local-only, so the brick would return on the next replication anyway.
		brick.Transparency = 1
		for _, piece in ipairs(brick:GetDescendants()) do
			if piece:IsA("BasePart") then
				piece.Transparency = 1
			end
		end
		brick.CFrame = rest
		return
	end

	if ctx.state == "pristine" then
		-- Back in its socket and visible again. A brick that was thrown is a brick that was
		-- only ever hidden, so this un-hides it rather than rebuilding anything.
		brick.Transparency = 0
		for _, piece in ipairs(brick:GetDescendants()) do
			if piece:IsA("BasePart") then
				piece.Transparency = 0
			end
		end
		TweenService:Create(
			brick,
			TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = rest }
		):Play()
		return
	end

	if ctx.state == "deformed" then
		-- IT WORKS LOOSE BEFORE IT GOES. Four steps with nothing to see for three of them
		-- is a floor that vanishes on a hidden counter, which is what ice was redesigned to
		-- stop doing. By the third step this brick is visibly proud of its neighbours and
		-- sitting crooked, and nothing else on the platform has moved at all.
		local stage = math.clamp(ctx.stepCount or 1, 1, #NEW_MATS.Lego.lift)
		local cant = NEW_MATS.Lego.cant[stage]
		-- Canted about a different axis each step, so a brick does not simply rise on a
		-- hinge -- it rocks the way something being prised out actually does.
		local goal = rest
			* CFrame.new(0, NEW_MATS.Lego.lift[stage], 0)
			* CFrame.Angles(cant * (if stage % 2 == 0 then 1 else -0.6), cant * 0.3, cant * 0.8)
		TweenService:Create(
			brick,
			TweenInfo.new(NEW_MATS.Lego.time, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ CFrame = goal }
		):Play()
	end
end

-- ===== CHARCOAL: the grill =====
--
-- The server says which coals are cold, smouldering, burning or ash (see CHARCOAL in
-- DeformationService); this makes them look it. A smouldering coal gets a dim flickering light, a few
-- sparks, a wisp of smoke and dull red cracks; a burning one bright orange cracks, a hot flicker, a
-- shower of sparks and a column of smoke. Ash gives way: the coal snaps down and out in soot and
-- flakes. A fresh coal settles back into the hole.
--
-- The cracks are drawn on the COLLIDER, like salt's, and unlit, so they read as heat rather than as
-- lines painted on the coal. They GROW (see Fissure): out from the foot that lit a coal, or in from the
-- side of the burning coal that spread to it; on through the coal, opening and going orange, when it
-- bursts into flame, with the glow in them breathing; white-hot just before it goes; ash grey as it
-- breaks. A stamp on burning coal splits new ones out from under the foot and flares the lot.
do
	local C = NEW_MATS.Charcoal
	local rigs = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: any }
	local shownFire = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: string }
	local holes = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: boolean }

	local function emberCanvas(tile: BasePart)
		local existing = crackGuis[tile]
		if existing and existing.Parent then
			return
		end
		local gui = Instance.new("SurfaceGui")
		gui.Name = "CrackOverlay"
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = CRACK_PPS
		gui.LightInfluence = 0
		gui.Brightness = C.crackBright
		gui.ZOffset = 0.03
		gui.Adornee = floorOf(tile) or tile
		gui.Parent = tile
		local clip = Instance.new("Frame")
		clip.Name = "Clip"
		clip.Size = UDim2.fromScale(1, 1)
		clip.BackgroundTransparency = 1
		clip.ClipsDescendants = true
		clip.Parent = gui
		crackGuis[tile] = gui
	end

	local function rigFor(tile: BasePart): any
		local rig = rigs[tile]
		if rig and rig.origin.Parent then
			return rig
		end
		local origin = Instance.new("Attachment")
		origin.Name = "EmberOrigin"
		origin.Position = Vector3.new(0, (restSize[tile] and restSize[tile].Y or 1) / 2 + 0.1, 0)
		origin.Parent = tile

		local sparksOut = Instance.new("ParticleEmitter")
		sparksOut.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparksOut.Color = ColorSequence.new(Color3.fromRGB(255, 214, 120), Color3.fromRGB(255, 90, 20))
		sparksOut.LightEmission = 1
		sparksOut.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0) })
		sparksOut.Lifetime = NumberRange.new(0.5, 1.1)
		sparksOut.Speed = NumberRange.new(2, 6)
		sparksOut.SpreadAngle = Vector2.new(40, 40)
		sparksOut.Acceleration = Vector3.new(0, 3, 0)
		sparksOut.Drag = 1.5
		sparksOut.Rate = 0
		sparksOut.Parent = origin

		local smoke = Instance.new("ParticleEmitter")
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(70, 66, 64))
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 3.2) })
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		smoke.Lifetime = NumberRange.new(1.2, 2.2)
		smoke.Speed = NumberRange.new(1, 2.5)
		smoke.SpreadAngle = Vector2.new(20, 20)
		smoke.Acceleration = Vector3.new(0, 1.5, 0)
		smoke.Rate = 0
		smoke.Parent = origin

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 120, 40)
		light.Brightness = 0
		light.Range = C.lightRange
		light.Shadows = false
		light.Parent = origin

		rig = { origin = origin, sparks = sparksOut, smoke = smoke, light = light, flicker = nil }
		rigs[tile] = rig
		return rig
	end

	local function flickerBetween(rig: any, low: number, high: number)
		if rig.flicker then
			rig.flicker:Cancel()
		end
		rig.light.Brightness = low
		local flicker = TweenService:Create(rig.light,
			TweenInfo.new(C.flicker, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Brightness = high })
		flicker:Play()
		rig.flicker = flicker
	end

	local function douse(tile: BasePart)
		local rig = rigs[tile]
		if not rig then
			return
		end
		if rig.flicker then
			rig.flicker:Cancel()
			rig.flicker = nil
		end
		rig.sparks.Rate = 0
		rig.smoke.Rate = 0
		TweenService:Create(rig.light, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0 }):Play()
	end

	-- Where a coal's cracks start: under the foot that lit it, or on the side facing the burning coal that
	-- spread to it, so a fire is seen crawling across the grill from one coal to the next.
	local function crackFrom(tile: BasePart, who: Player?): Vector3?
		if who then
			return Fissure.footOf(tile, who)
		end
		local slab = tile.Parent
		local col, row = tile:GetAttribute("Col"), tile:GetAttribute("Row")
		if slab and typeof(col) == "number" and typeof(row) == "number" then
			for _, offset in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
				local found = slab:FindFirstChild(("SubRegion_%d_%d"):format(col + offset[1], row + offset[2]))
				if found and found:IsA("BasePart") and shownFire[found] == "burning" then
					return (tile.Position + found.Position) / 2
				end
			end
		end
		return nil
	end

	local function showFire(tile: BasePart, fire: string?, who: Player?)
		if shownFire[tile] == fire then
			return
		end
		shownFire[tile] = fire
		if fire == "smoulder" then
			local rig = rigFor(tile)
			rig.sparks.Rate = C.smoulderSparks
			rig.smoke.Rate = C.smoulderSmoke
			flickerBetween(rig, C.smoulderLow, C.smoulderHigh)
			emberCanvas(tile)
			-- IT CATCHES WHERE YOU STOOD: dull red hairlines creeping out from the foot, slowly enough that
			-- they are still going when the coal bursts into flame.
			local def = Materials.Charcoal
			local catch = def and def.igniteAfter or 1
			Fissure.grow(tile, { from = crackFrom(tile, who), arms = C.catchArms, reach = C.catchReach,
				thick = C.catchThick, speed = C.catchReach / catch, color = C.warm, splits = 0 })
			Fissure.glow(tile, C.crackBright * (1 - C.glowSwing), C.crackBright, C.breath * 2)
		elseif fire == "burning" then
			local rig = rigFor(tile)
			rig.sparks.Rate = C.burnSparks
			rig.smoke.Rate = C.burnSmoke
			flickerBetween(rig, C.burnLow, C.burnHigh)
			emberCanvas(tile)
			if not Fissure.has(tile) then
				-- Caught before this client saw it smoulder: its cracks start now.
				Fissure.grow(tile, { from = crackFrom(tile, who), arms = C.catchArms, reach = C.catchReach,
					thick = C.catchThick, speed = C.burnSpeed, color = C.warm, splits = 0 })
			end
			-- IT BURNS THROUGH: the cracks run on toward the edges and split, open up, go from red to
			-- orange, and the glow in them breathes.
			Fissure.tint(tile, C.hot, 0.3)
			Fissure.extend(tile, C.burnReach, C.burnSpeed)
			Fissure.widen(tile, C.burnWiden, 0.3)
			Fissure.glow(tile, C.crackBright * (1 - C.glowSwing), C.crackBright * (1 + C.glowSwing), C.breath)
			rig.sparks:Emit(C.catchBurst)
			-- AND WHITE-HOT JUST BEFORE IT GOES, breathing fast: the last warning to get off it.
			local def = Materials.Charcoal
			local burn = def and def.burnFor or 2
			task.delay(burn * C.whiteAt, function()
				if shownFire[tile] == "burning" then
					Fissure.tint(tile, C.white, 0.35)
					Fissure.widen(tile, C.burnWiden, 0.35)
					Fissure.glow(tile, C.crackBright, C.crackBright * (1 + 2 * C.glowSwing), C.breath * 0.4)
				end
			end)
		else
			douse(tile)
		end
	end

	Effects.Charcoal = function(ctx: Ctx)
		local tile = ctx.tile
		if ctx.state == "exhausted" then
			-- ASH GIVES WAY. The coal snaps down and out -- Quint IN, so it holds for a moment and then
			-- goes -- in soot, flakes and a last shower of embers. The glow goes out of its cracks in the
			-- same instant, ash grey, and they fade as it falls.
			local rig = rigs[tile]
			if rig then
				rig.sparks:Emit(C.stompBurst)
			end
			Fissure.glow(tile)
			Fissure.tint(tile, C.ash, 0.05)
			Fissure.heal(tile, C.time + 0.08)
			showFire(tile, nil)
			holes[tile] = true
			local snap = TweenInfo.new(C.time, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
			local bone = boneFor(tile)
			if bone then
				setResidual(tile, bone, snap, -C.drop)
			else
				moveTile(tile, snap, -C.drop, 1, 1)
			end
			puff(tile, Color3.fromRGB(58, 54, 52), 1.4, 3.5, 1.2, C.dust)
			flingDebris(tile, "CharcoalFlake", C.shards)
			return
		end

		if holes[tile] and ctx.state == "pristine" then
			-- A FRESH COAL settles back into the hole.
			holes[tile] = nil
			local settle = TweenInfo.new(C.regrow, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local bone = boneFor(tile)
			if bone then
				setResidual(tile, bone, settle, 0)
			else
				moveTile(tile, settle, 0, 1, 1)
			end
			puff(tile, Color3.fromRGB(46, 42, 40), 0.9, 2, 1, 6)
		end

		local stamped = ctx.state == "deformed" and ctx.cause == nil and shownFire[tile] == "burning"
		showFire(tile, ctx.fire, ctx.who)
		if ctx.state == "deformed" and ctx.cause == nil then
			-- A FOOTSTEP. The shape barely moves -- a quick jolt -- and it sheds flakes; on burning coal
			-- it kicks up a shower of embers as well, which is the coal being stamped out sooner.
			moveTile(tile, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), -C.jolt, 1, 1)
			flingDebris(tile, "CharcoalFlake", C.flake)
			local rig = rigs[tile]
			if stamped and rig then
				rig.sparks:Emit(C.stompBurst)
			end
			if stamped then
				-- A STAMP splits new cracks out from under the foot, in whatever colour the coal has
				-- reached, and flares the lot.
				Fissure.grow(tile, { from = Fissure.footOf(tile, ctx.who), arms = 2, reach = C.stompReach,
					thick = 3, speed = C.stompSpeed, splits = 1 })
				Fissure.flare(tile, C.crackBright * 3, 0.3)
			end
		end
	end
end

Effects.Chocolate = function(ctx: Ctx)
	local tile = ctx.tile
	-- THE SKINNED MESH, NOT THE SLAB. On a rigged platform the slab is an invisible carrier
	-- and the SkinnedVisual child is the thing on screen, so a reflectance tween aimed at
	-- the slab changes a part nobody can see. Falls back to the slab for the unrigged case.
	local slab = tile.Parent
	local surface = if slab and slab:IsA("BasePart")
		then (slab:FindFirstChild("SkinnedVisual") or slab)
		else nil

	if ctx.state == "exhausted" then
		local run = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, run, -NEW_MATS.Chocolate.melt)
		else
			moveTile(tile, run, -NEW_MATS.Chocolate.melt, 1, 1)
		end
		if surface and surface:IsA("BasePart") then
			TweenService:Create(surface, run, { Reflectance = NEW_MATS.Chocolate.wet }):Play()
		end
		return
	end

	if ctx.state == "pristine" then
		local set = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, set, 0)
		else
			moveTile(tile, set, 0, 1, 1)
		end
		if surface and surface:IsA("BasePart") then
			TweenService:Create(surface, set, { Reflectance = NEW_MATS.Chocolate.gloss }):Play()
		end
		return
	end

	-- "deformed" and "decaying" pose the same, because chocolate does not re-temper when
	-- you step off it. Warmth only goes one way.
	--
	-- THREE STAGES OF ALMOST-MELTED, and this is the material's whole read now. It used to
	-- look identical from the first step to the last and then fail on a count you could not
	-- see. What each stage moves is the GLOSS first and the shape second, because that is
	-- the order chocolate actually goes: it looks wet well before it looks soft, so the
	-- earliest warning the player gets is a surface that has started shining too much.
	local stage = math.clamp(ctx.stepCount or 1, 1, #NEW_MATS.Chocolate.stages)

	-- WHAT COMES OFF IT, and it is all one event: globs flung loose, a print left in what
	-- stays, and the warmth coming off the surface that caused both.
	flingDebris(tile, "ChocGlob", 2)
	-- Rising, and slowly. This is the only puff in the game whose point is TEMPERATURE
	-- rather than material coming loose -- warm air off a softening bar, which is why it is
	-- barely tinted and drifts up instead of being thrown.
	puff(tile, Color3.fromRGB(214, 186, 164), 0.26, 2, 6, 3)
	if not marks[tile] or #marks[tile] == 0 then
		for _, hit in ipairs(localFootWorldPoints(tile)) do
			spawnFootprint(tile, hit, ctx.material, 6)
		end
	end

	local plan = NEW_MATS.Chocolate.stages[stage]
	local warm = TweenInfo.new(NEW_MATS.Chocolate.time, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local bone = boneFor(tile)
	if bone then
		setResidual(tile, bone, warm, -plan.sink)
	else
		moveTile(tile, warm, -plan.sink, 1, 1)
	end
	if surface and surface:IsA("BasePart") then
		TweenService:Create(surface, warm, { Reflectance = plan.gloss }):Play()
	end
end

Effects.ChocolateSolid = function(ctx: Ctx)
	local tile = ctx.tile
	if ctx.state == "exhausted" then
		puff(tile, MaterialAppearance.Appearances.ChocolateSolid.color, 0.18, 6, -30, 8)
		-- Quint IN, like ice: barely moves for the first half of the tween and then goes.
		-- Brittle things accelerate into failure; easing out would read as being lowered.
		local snap = TweenInfo.new(NEW_MATS.ChocolateSolid.time, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, snap, -NEW_MATS.ChocolateSolid.drop)
		else
			moveTile(tile, snap, -NEW_MATS.ChocolateSolid.drop, 1, 1)
		end
		flingDebris(tile, "ChocolateShard", NEW_MATS.ChocolateSolid.pieces)
		return
	end
	if ctx.state == "deformed" then
		-- One step in, nothing has happened. Cold chocolate has no soft stage to show, so
		-- the only warning is the sound -- which is the same bargain charcoal makes.
		moveTile(tile, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			-NEW_MATS.ChocolateSolid.jolt, 1, 1)
	end
end

-- How far each cell has been compacted, for the two materials that accumulate. Weak-keyed:
-- tiles are destroyed when a chunk is torn down and nothing else would clear this.
local packed = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: number }

-- Effects.Salt lives with Effects.Clay further down. Both move material between cells and share the
-- code that draws it: see CLAY AND SALT.

Effects.Lava = function(ctx: Ctx)
	local tile = ctx.tile
	local slab = tile.Parent
	local surface = if slab and slab:IsA("BasePart")
		then (slab:FindFirstChild("SkinnedVisual") or slab)
		else nil
	local hot = MaterialAppearance.Appearances.Lava.color
	local cold = MaterialAppearance.Appearances.Lava.baseColor

	if ctx.state == "exhausted" then
		-- The raft fails and what is under it is still molten. Straight back to full heat,
		-- fast, because the give-way is the moment the crust stops being a floor.
		local fail = TweenInfo.new(0.18, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, fail, -NEW_MATS.Lava.drop)
		else
			moveTile(tile, fail, -NEW_MATS.Lava.drop, 1, 1)
		end
		if surface and surface:IsA("BasePart") then
			TweenService:Create(surface, fail, { Color = hot }):Play()
		end
		local origin = Instance.new("Attachment")
		origin.Name = "EmberOrigin"
		origin.Position = Vector3.new(0, (restSize[tile] and restSize[tile].Y or 1) / 2, 0)
		origin.Parent = tile
		local embers = Instance.new("ParticleEmitter")
		embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		embers.Color = ColorSequence.new(Color3.fromRGB(255, 176, 72))
		embers.Size = NumberSequence.new(0.22)
		embers.Lifetime = NumberRange.new(0.6, 1.3)
		-- UP, and slowly. Embers are carried on rising heat, so they drift rather than
		-- spray -- anything fast reads as sparks off an angle grinder.
		embers.Speed = NumberRange.new(2, 6)
		embers.SpreadAngle = Vector2.new(35, 35)
		embers.Rate = 0
		embers.Acceleration = Vector3.new(0, 6, 0)
		embers.LightEmission = 1
		embers.Parent = origin
		embers:Emit(NEW_MATS.Lava.embers)
		Debris:AddItem(origin, 2)

		-- The raft comes apart, and now BOTH halves go: black shards of the crust that had
		-- formed, and glowing gobs of the melt it was sitting on. Two flings rather than one
		-- with a blended colour, because a single mid-orange chunk reads as rusty metal --
		-- what makes it lava is the two temperatures being visibly separate things.
		flingDebris(tile, "Obsidian", NEW_MATS.Lava.burst)
		flingDebris(tile, "Melt", math.max(2, math.floor(NEW_MATS.Lava.burst / 2)))
		return
	end

	if ctx.state == "pristine" then
		if surface and surface:IsA("BasePart") then
			TweenService:Create(surface, TweenInfo.new(1.2), { Color = hot }):Play()
		end
		return
	end

	-- YOUR OWN HEAT LOSS MAKES THE FLOOR. Each step drags the colour further toward
	-- obsidian and drops the surface a little, so the raft you are standing on visibly
	-- forms under you -- and stops being molten in the only way a Neon material can show.
	local stage = math.clamp(ctx.stepCount or 1, 1, #NEW_MATS.Lava.cool)
	local chill = NEW_MATS.Lava.cool[stage]
	local crust = TweenInfo.new(NEW_MATS.Lava.time, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	if surface and surface:IsA("BasePart") then
		TweenService:Create(surface, crust, { Color = hot:Lerp(cold, chill) }):Play()
	end
	local bone = boneFor(tile)
	if bone then
		setResidual(tile, bone, crust, -NEW_MATS.Lava.sink * stage)
	else
		moveTile(tile, crust, -NEW_MATS.Lava.sink * stage, 1, 1)
	end

	-- CRUST BREAKS OFF AS IT FORMS. A raft freezing on moving rock does not set cleanly --
	-- it buckles, and pieces of it snap away round the edges and fall. Black shards, because
	-- what is breaking has already set; the glowing half comes later when the raft fails and
	-- what is under it is exposed.
	-- Crust AND a little of what is under it: even a raft that is only buckling lets some
	-- melt through at its edges, and one glowing piece per step is what keeps a forming
	-- crust from reading as ordinary rock breaking.
	flingDebris(tile, "Obsidian", NEW_MATS.Lava.shards)
	flingDebris(tile, "Melt", 1)
end

-- Splash thrown up when something goes through the oobleck.
--
-- Big, slow, and heavy: it is a dense slurry, so what comes up is thick gobs rather than
-- droplets, and they arc rather than spray. High drag and low speed against ice's water,
-- which is thin and fast -- the two splashes are built the same way and read as completely
-- different substances entirely because of that.
local function ooblSplash(tile: BasePart)
	local origin = Instance.new("Attachment")
	origin.Name = "OoblSplashOrigin"
	origin.Position = Vector3.new(0, (restSize[tile] and restSize[tile].Y or 1) / 2, 0)
	origin.Parent = tile

	local gobs = Instance.new("ParticleEmitter")
	gobs.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	gobs.Color = ColorSequence.new(MaterialAppearance.Appearances.Oobleck.color)
	gobs.Size = NumberSequence.new(0.6)
	gobs.Lifetime = NumberRange.new(0.5, 1.0)
	gobs.Speed = NumberRange.new(6, 13)
	gobs.SpreadAngle = Vector2.new(45, 45)
	gobs.Rate = 0
	gobs.Acceleration = Vector3.new(0, -48, 0)
	-- Drag is what makes it read as thick. Without it these are water.
	gobs.Drag = 3
	gobs.Transparency = NumberSequence.new(0.1)
	gobs.Parent = origin
	gobs:Emit(NEW_MATS.Oobleck.splash)
	Debris:AddItem(origin, 2)
end

-- ===== OOBLECK: stamp it hard =====
--
-- The server says how deep each player is wading and when a landing has hardened the pool (see
-- OOBLECK in DeformationService). Wading, the cell under a player sinks to their depth, collider and
-- all, so you are IN it; a hardening shock spreads across the pool from the landing, a cell every
-- `shockStep`, each one popping up flat. No cracks: it is a liquid going hard for a moment, not a crust.
-- Going under throws the slurry up; a hole fills back in with a gloopy overshoot.
do
	local O = NEW_MATS.Oobleck
	local holes = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: boolean }

	Effects.Oobleck = function(ctx: Ctx)
		local tile = ctx.tile

		if ctx.cause == "shock" then
			local col, row = tile:GetAttribute("Col"), tile:GetAttribute("Row")
			local origin = ctx.origin
			local ring = 0
			if origin and typeof(col) == "number" and typeof(row) == "number" then
				ring = math.max(math.abs(col - origin.X), math.abs(row - origin.Y))
			end
			task.delay(ring * O.shockStep, function()
				if not tile.Parent or lastState[tile] == "exhausted" then
					return
				end
				moveTile(tile, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), O.pop, 1, 1)
				task.delay(0.07, function()
					if tile.Parent and lastState[tile] ~= "exhausted" then
						local flat = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
						moveTile(tile, flat, 0, 1, 1)
						driveFloor(tile, flat, 0)
					end
				end)
				if ring == 0 then
					flingDebris(tile, "OoblGob", O.stampGobs)
					ooblSplash(tile)
				end
			end)
			return
		end

		if ctx.state == "exhausted" then
			-- UNDER: it lets go all at once and throws the slurry up around you.
			holes[tile] = true
			local through = TweenInfo.new(O.through, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			local bone = boneFor(tile)
			if bone then
				setResidual(tile, bone, through, -O.sink)
			else
				moveTile(tile, through, -O.sink, 1, 1)
			end
			ooblSplash(tile)
			return
		end

		if ctx.state == "pristine" and holes[tile] then
			-- FILLED BACK IN: the slurry flows into the hole, overshoots, and levels.
			holes[tile] = nil
			local fill = TweenInfo.new(O.heal, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local bone = boneFor(tile)
			if bone then
				setResidual(tile, bone, fill, 0)
			else
				moveTile(tile, fill, 0, 1, 1)
			end
			flingDebris(tile, "OoblGob", 2)
			return
		end

		if ctx.state == "deformed" then
			-- WADING, as deep as the player on it is. Most of the depth goes to the collider too.
			local level = ctx.wade or 0
			local info = TweenInfo.new(if ctx.cause == "wade" then O.wadeTime else 0.12,
				Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
			moveTile(tile, info, -level * O.deep, 1, 1)
			driveFloor(tile, info, -level * O.floorDeep)
			if ctx.cause == nil then
				-- A foot striking it throws a little slurry, however hard the pool is.
				flingDebris(tile, "OoblGob", O.shed)
			end
			return
		end

		-- Stepped off: the slurry levels behind you.
		settleTile(tile, O.level)
	end
end

-- ===== THE KEYPADS =====
--
-- Every cell is a switch -- clicky, linear or tactile; see KEYPADS in DeformationService for what each
-- does to your feet -- and this is where the three FEEL different: how the cap travels, how hard the
-- lit core flashes, how far the light spreads. The cap and its core travel together; the bezel never
-- moves. A clicky press rings the bezel with light, three in a row light the whole pad from your foot,
-- and between presses the pad breathes.
--
-- In a do-block for the reason clay and salt are: this module sits close to Luau's limit of 200
-- locals in one scope.
do
	local B = NEW_MATS.Button
	local WHITE = Color3.new(1, 1, 1)
	local LANE = Color3.fromRGB(56, 222, 255)
	local VIOLET = Color3.fromRGB(146, 92, 255)
	local PINK = Color3.fromRGB(255, 92, 192)

	-- Where each core's colour rests, read once: read live it could be caught mid-flash.
	local coreBase = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: Color3 }
	local breathing = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: boolean }

	-- EACH MOVING PART REMEMBERS ITS OWN REST. They sit at different places within the cell, so a
	-- single shared rest would slam every button in it onto the first one's position.
	local function restOf(part: BasePart): CFrame
		local rest = capRest[part]
		if not rest then
			rest = part.CFrame
			capRest[part] = rest
		end
		return rest
	end

	-- EVERY CAP AND CORE IN THE CELL: the dense keypad puts four buttons to a cell, and all of them
	-- press, because what goes down is what your foot is on and your foot is on a cell.
	local function partsOf(tile: BasePart): ({ BasePart }, { BasePart })
		local moving: { BasePart } = {}
		local cores: { BasePart } = {}
		for _, child in ipairs(tile:GetChildren()) do
			if child:IsA("BasePart") and (child.Name == "Cap" or child.Name == "CapLed") then
				table.insert(moving, child)
				if child.Name == "CapLed" then
					table.insert(cores, child)
				end
			end
		end
		return moving, cores
	end

	-- ALONG LOCAL -X, WHICH IS DOWN. A cap is a cylinder rolled 90 degrees about Z so its length axis
	-- stands upright, and that roll maps local +X onto the platform's up. Translating along local Z --
	-- the obvious spelling -- is untouched by a roll about Z, so an earlier version slid the button
	-- sideways out of its housing instead of pressing it.
	local function travel(tile: BasePart, parts: { BasePart }, info: TweenInfo, offset: number)
		for _, part in ipairs(parts) do
			play(tile, part, info, { CFrame = restOf(part) * CFrame.new(offset, 0, 0) })
		end
	end

	-- A core lit toward `to` by `amount`, held, and faded back to its own colour. Not through `play`:
	-- the next press cancels the tile's tweens, and a flash has to outlive the press that lit it.
	local function flash(core: BasePart, to: Color3, amount: number, hold: number, fade: number)
		local base = coreBase[core]
		if not base then
			base = core.Color
			coreBase[core] = base
		end
		core.Color = base:Lerp(to, math.clamp(amount, 0, 1))
		TweenService:Create(core, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, hold),
			{ Color = base }):Play()
	end

	local function burst(at: BasePart, colour: Color3, brightness: number, range: number, time: number)
		local light = Instance.new("PointLight")
		light.Color = colour
		light.Brightness = brightness
		light.Range = range
		light.Shadows = false
		light.Parent = at
		TweenService:Create(light, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0 }):Play()
		Debris:AddItem(light, time + 0.1)
	end

	-- A RING OF LIGHT spreading from a clicky cap's rim, just above its bezel.
	local function clickRing(tile: BasePart, cap: BasePart, colour: Color3)
		local ring = Instance.new("Part")
		ring.Name = "ClickRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.04, cap.Size.Y * 1.1, cap.Size.Z * 1.1)
		-- Local +X is up on a rolled cap: from its centre down to just above the bezel's top face.
		ring.CFrame = restOf(cap) * CFrame.new(-cap.Size.X / 2 + 0.26, 0, 0)
		ring.Material = Enum.Material.Neon
		ring.Color = colour
		ring.Transparency = 0.35
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanTouch = false
		ring.CanQuery = false
		ring.CastShadow = false
		ring.Parent = tile
		TweenService:Create(ring, TweenInfo.new(B.ringTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.04, cap.Size.Y * B.ringGrow, cap.Size.Z * B.ringGrow),
			Transparency = 1,
		}):Play()
		Debris:AddItem(ring, B.ringTime + 0.1)
	end

	local function tileAt(slab: Instance, col: number, row: number): BasePart?
		local found = slab:FindFirstChild(("SubRegion_%d_%d"):format(col, row))
		return if found and found:IsA("BasePart") then found else nil
	end

	-- SPARKS off the top of a lit core. The core is a rolled cylinder, so its +X is up: the emitter
	-- sits on that face and fires out of it.
	local function sparks(core: BasePart, colour: Color3, count: number, speed: number)
		local origin = Instance.new("Attachment")
		origin.Name = "SparkOrigin"
		origin.Position = Vector3.new(core.Size.X / 2 + 0.05, 0, 0)
		origin.Parent = core
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(WHITE, colour)
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.24), NumberSequenceKeypoint.new(1, 0) })
		emitter.Lifetime = NumberRange.new(0.12, 0.34)
		emitter.Speed = NumberRange.new(speed * 0.45, speed)
		emitter.SpreadAngle = Vector2.new(75, 75)
		emitter.EmissionDirection = Enum.NormalId.Right
		emitter.Acceleration = Vector3.new(0, -60, 0)
		emitter.Drag = 5
		emitter.Rate = 0
		emitter.Parent = origin
		emitter:Emit(count)
		Debris:AddItem(origin, 0.7)
	end

	-- AN ARC: a jagged bolt of light between two points, hanging for a blink and thinning out.
	local function bolt(tile: BasePart, from: Vector3, to: Vector3, colour: Color3)
		local span = to - from
		local length = span.Magnitude
		if length < 0.1 then
			return
		end
		local side = span:Cross(Vector3.yAxis)
		side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
		local points = { from }
		for index = 1, 4 do
			local jitter = side * (math.random() - 0.5) * length * 0.2
				+ Vector3.new(0, 0.3 + math.random() * 0.5, 0)
			table.insert(points, from:Lerp(to, index / 5) + jitter)
		end
		table.insert(points, to)
		for index = 1, #points - 1 do
			local a, b = points[index], points[index + 1]
			local segment = Instance.new("Part")
			segment.Name = "Arc"
			segment.Size = Vector3.new(0.09, 0.09, (b - a).Magnitude)
			segment.CFrame = CFrame.lookAt((a + b) / 2, b)
			segment.Material = Enum.Material.Neon
			segment.Color = colour:Lerp(WHITE, 0.35)
			segment.Anchored = true
			segment.CanCollide = false
			segment.CanTouch = false
			segment.CanQuery = false
			segment.CastShadow = false
			segment.Parent = tile
			TweenService:Create(segment, TweenInfo.new(B.arcTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
				Size = Vector3.new(0.02, 0.02, segment.Size.Z),
			}):Play()
			Debris:AddItem(segment, B.arcTime + 0.05)
		end
	end

	-- A FLASH WAVE across the pad from a button: a flat disc of light spreading and fading.
	local function shockwave(tile: BasePart, colour: Color3, span: number, time: number, after: number)
		task.delay(after, function()
			if not tile.Parent then
				return
			end
			local disc = Instance.new("Part")
			disc.Name = "Shockwave"
			disc.Shape = Enum.PartType.Cylinder
			disc.Size = Vector3.new(0.05, 1, 1)
			disc.CFrame = tile.CFrame * CFrame.new(0, tile.Size.Y / 2 + 0.14, 0) * CFrame.Angles(0, 0, math.rad(90))
			disc.Material = Enum.Material.Neon
			disc.Color = colour
			disc.Transparency = 0.25
			disc.Anchored = true
			disc.CanCollide = false
			disc.CanTouch = false
			disc.CanQuery = false
			disc.CastShadow = false
			disc.Parent = tile
			TweenService:Create(disc, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.05, span, span),
				Transparency = 1,
			}):Play()
			Debris:AddItem(disc, time + 0.1)
		end)
	end

	-- A SHORT CAMERA SHAKE for the player who set it off, through the humanoid's camera offset, which
	-- nothing else in the game uses.
	local function shake(strength: number, time: number)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		task.spawn(function()
			local started = os.clock()
			while os.clock() - started < time and humanoid.Parent do
				local fade = 1 - (os.clock() - started) / time
				humanoid.CameraOffset = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
					* strength * fade
				task.wait(0.03)
			end
			if humanoid.Parent then
				humanoid.CameraOffset = Vector3.zero
			end
		end)
	end

	-- The clicky button in the next row along the route, nearest this one's column.
	local function nextLane(tile: BasePart): BasePart?
		local slab = tile.Parent
		local col, row = tile:GetAttribute("Col"), tile:GetAttribute("Row")
		if not slab or typeof(col) ~= "number" or typeof(row) ~= "number" then
			return nil
		end
		local cols = slab:GetAttribute("GridCols")
		local lastCol = if typeof(cols) == "number" then cols else 5
		local best: BasePart? = nil
		local gap = math.huge
		for c = 1, lastCol do
			local other = tileAt(slab, c, row + 1)
			if other and other:GetAttribute("Switch") == "clicky" and math.abs(c - col) < gap then
				best, gap = other, math.abs(c - col)
			end
		end
		return best
	end

	-- THE LIGHTS ANSWER A PRESS, nearest first: the cores around a pressed button flash in rings
	-- spreading out from it, dimmer the further out they are. `reach` is in cells.
	local function rippleLights(tile: BasePart, reach: number, amount: number, to: Color3)
		local slab = tile.Parent
		local col, row = tile:GetAttribute("Col"), tile:GetAttribute("Row")
		if not slab or typeof(col) ~= "number" or typeof(row) ~= "number" then
			return
		end
		local cols = slab:GetAttribute("GridCols")
		local rows = slab:GetAttribute("GridRows")
		local lastCol = if typeof(cols) == "number" then cols else 5
		local lastRow = if typeof(rows) == "number" then rows else 4
		for c = math.max(1, col - reach), math.min(lastCol, col + reach) do
			for r = math.max(1, row - reach), math.min(lastRow, row + reach) do
				local ring = math.max(math.abs(c - col), math.abs(r - row))
				local other = if ring > 0 then tileAt(slab, c, r) else nil
				if other then
					local lit: BasePart = other
					task.delay(ring * B.rippleStep, function()
						if not lit.Parent then
							return
						end
						for _, child in ipairs(lit:GetChildren()) do
							if child.Name == "CapLed" and child:IsA("BasePart") then
								flash(child, to, amount / ring, 0, B.rippleFade)
							end
						end
					end)
				end
			end
		end
	end

	-- THE PAD BREATHES. Each lit core dims and brightens on a slow cycle that starts a little later
	-- the further along the route it sits, so a soft wave of light keeps running across the keypad
	-- the way you are going. Transparency only: a flash owns the colour and a press owns the position,
	-- so the three never fight over one property.
	local function breathe(core: BasePart)
		if breathing[core] then
			return
		end
		breathing[core] = true
		local tile = core.Parent
		local slab = tile and tile.Parent
		local along = 0.5
		if slab and slab:IsA("BasePart") and slab.Size.Z > 0 then
			along = math.clamp(slab.CFrame:PointToObjectSpace(core.Position).Z / slab.Size.Z + 0.5, 0, 1)
		end
		task.delay(along * B.breath, function()
			if core.Parent then
				TweenService:Create(core, TweenInfo.new(B.breath, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Transparency = B.dim }):Play()
			end
		end)
	end
	for _, found in ipairs(workspace:GetDescendants()) do
		if found.Name == "CapLed" and found:IsA("BasePart") then
			breathe(found)
		end
	end
	workspace.DescendantAdded:Connect(function(found: Instance)
		if found.Name == "CapLed" and found:IsA("BasePart") then
			breathe(found)
		end
	end)

	local function rootOf(who: Player?): BasePart?
		local character = if who then who.Character else nil
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root else nil
	end

	-- THE CHARGE YOU CARRY: a violet crackle and glow round whoever holds the capacitor's charges, brighter
	-- for each, until a clicky button spends them or they run out on the server's clock. One per player.
	local auras = (setmetatable({}, { __mode = "k" }) :: any) :: { [Player]: any }

	local function spend(who: Player?)
		local held = if who then auras[who] else nil
		if not who or not held then
			return
		end
		auras[who] = nil
		held.token += 1
		held.crackle.Rate = 0
		if held.origin.Parent then
			held.crackle:Emit(12)
		end
		TweenService:Create(held.light, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0 }):Play()
		Debris:AddItem(held.origin, 0.7)
	end

	local function carry(who: Player?, count: number)
		local root = rootOf(who)
		if not who or not root then
			return
		end
		local held = auras[who]
		if held and held.origin.Parent ~= root then
			-- Respawned since: the old crackle went with the old character.
			auras[who] = nil
			held = nil
		end
		if not held then
			local origin = Instance.new("Attachment")
			origin.Name = "ChargeAura"
			origin.Parent = root
			local crackle = Instance.new("ParticleEmitter")
			crackle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			crackle.Color = ColorSequence.new(WHITE, VIOLET)
			crackle.LightEmission = 1
			crackle.LightInfluence = 0
			crackle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0) })
			crackle.Lifetime = NumberRange.new(0.12, 0.3)
			crackle.Speed = NumberRange.new(3, 7)
			crackle.SpreadAngle = Vector2.new(180, 180)
			crackle.Drag = 6
			crackle.Rate = 0
			crackle.Parent = origin
			local light = Instance.new("PointLight")
			light.Color = VIOLET
			light.Brightness = 0
			light.Range = B.auraRange
			light.Shadows = false
			light.Parent = origin
			held = { origin = origin, crackle = crackle, light = light, token = 0 }
			auras[who] = held
		end
		held.token += 1
		local token = held.token
		held.crackle.Rate = B.auraSparks * count
		held.crackle:Emit(3 * count)
		TweenService:Create(held.light, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = B.auraLight * count }):Play()
		-- IT RUNS OUT when the server forgets it: capacitorHold after the last violet press.
		local def = Materials.Buttons
		task.delay(def and def.capacitorHold or 4, function()
			if auras[who] == held and held.token == token then
				spend(who)
			end
		end)
	end

	-- A PINK STREAK under a player the spring throws, for as long as the throw lasts.
	local function springTrail(who: Player?, level: number)
		local root = rootOf(who)
		if not root then
			return
		end
		local origin = Instance.new("Attachment")
		origin.Name = "SpringStreak"
		origin.Position = Vector3.new(0, -2.5, 0)
		origin.Parent = root
		local trail = Instance.new("ParticleEmitter")
		trail.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		trail.Color = ColorSequence.new(WHITE, PINK)
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.34), NumberSequenceKeypoint.new(1, 0) })
		trail.Lifetime = NumberRange.new(0.25, 0.5)
		trail.Speed = NumberRange.new(0.5, 2)
		trail.SpreadAngle = Vector2.new(25, 25)
		trail.EmissionDirection = Enum.NormalId.Bottom
		trail.Rate = 40 + 20 * level
		trail.Parent = origin
		task.delay(B.springStreak * level, function()
			trail.Enabled = false
		end)
		Debris:AddItem(origin, B.springStreak * level + 0.6)
	end

	Effects.Buttons = function(ctx: Ctx)
		local tile = ctx.tile
		local moving, cores = partsOf(tile)
		if #moving == 0 then
			-- No cap means a platform built before attachCap existed. A silent no-op rather than
			-- driving the bone: that flexes the whole plate, which this material was rebuilt to stop.
			return
		end
		local switch = tile:GetAttribute("Switch")
		local feel: any = if switch == "clicky" then B.clicky elseif switch == "tactile" then B.tactile else B.linear
		local glow = cores[1]
		local base = if glow then coreBase[glow] or glow.Color else WHITE

		if ctx.state == "deformed" then
			-- DOWN AND STAYS DOWN while your weight is on it: the buttons you are standing on are
			-- visibly down, so a glance tells you where your feet are.
			if switch == "tactile" then
				-- THE BUMP. Part way down it meets the tactile leaf, holds, and gives.
				travel(tile, moving, TweenInfo.new(feel.down, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					-feel.drop * feel.bump)
				task.delay(feel.down + feel.hold, function()
					if tile.Parent and lastState[tile] == "deformed" then
						travel(tile, moving, TweenInfo.new(feel.down, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
							-feel.drop)
					end
				end)
			elseif switch == "clicky" then
				travel(tile, moving, TweenInfo.new(feel.down, Enum.EasingStyle.Quart, Enum.EasingDirection.In), -feel.drop)
			else
				travel(tile, moving, TweenInfo.new(feel.down, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), -feel.drop)
			end

			for _, core in ipairs(cores) do
				flash(core, WHITE, feel.flash, feel.hold, feel.fade)
			end
			if switch == "clicky" then
				if glow then
					burst(glow, base, B.burst, B.burstRange, B.burstTime)
					sparks(glow, base, B.sparks, B.sparkSpeed)
				end
				for _, part in ipairs(moving) do
					if part.Name == "Cap" then
						clickRing(tile, part, base)
					end
				end
				-- THE LANE LIGHTS AHEAD. An arc jumps from this button to the next clicky one along the
				-- route, and that one flashes: where to put your next foot, in electricity.
				local ahead = nextLane(tile)
				if ahead and glow then
					local _, aheadCores = partsOf(ahead)
					local target = aheadCores[1]
					if target then
						bolt(tile, glow.Position + glow.CFrame.RightVector * (glow.Size.X / 2),
							target.Position + target.CFrame.RightVector * (target.Size.X / 2), base)
						for _, core in ipairs(aheadCores) do
							flash(core, WHITE, B.aheadFlash, 0.05, B.aheadFade)
						end
					end
				end
			end
			-- WHAT THE PRESS DID, which the server sends as `charge`: see KEYPADS in DeformationService.
			local held = ctx.charge
			if switch == "linear" and held then
				-- THE CAPACITOR TAKES A CHARGE: it arcs up out of the button into whoever pressed it, and
				-- the crackle they carry grows. The cores hold their flash longer at every charge.
				local root = rootOf(ctx.who)
				if glow and root then
					bolt(tile, glow.Position + glow.CFrame.RightVector * (glow.Size.X / 2),
						root.Position - Vector3.new(0, 1.5, 0), VIOLET)
				end
				for _, core in ipairs(cores) do
					flash(core, WHITE, 0.45 + 0.18 * held, 0.08 * held, feel.fade)
				end
				carry(ctx.who, held)
			elseif switch == "clicky" and held then
				-- DISCHARGE: every charge jumps out of the player into the button in an arc of its own, the
				-- button throws violet light and sparks, and a violet wave runs out across the pad.
				local root = rootOf(ctx.who)
				if glow and root then
					local top = glow.Position + glow.CFrame.RightVector * (glow.Size.X / 2)
					for _ = 1, held do
						local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.2
						bolt(tile, root.Position + jitter, top, VIOLET)
					end
				end
				spend(ctx.who)
				if glow then
					burst(glow, VIOLET, 1 + B.dischargeBurst * held / 3, B.dischargeRange, 0.6)
					sparks(glow, VIOLET, B.sparks * held, B.sparkSpeed * 1.25)
				end
				shockwave(tile, VIOLET, B.dischargeWave, 0.45, 0.04)
				rippleLights(tile, 1 + held, 0.6, VIOLET)
				if ctx.mine then
					shake(B.shake * 0.25 * held, B.shakeTime * 0.5)
				end
			elseif switch == "tactile" and held then
				-- THE SPRING IS SET: its cores flash brighter at every level of a bounce chain, and from the
				-- second level on the caps ring with pink light.
				for _, core in ipairs(cores) do
					flash(core, WHITE, math.min(1, B.springGlow * (held + 1)), 0.1, feel.fade)
				end
				if held >= 2 then
					for _, part in ipairs(moving) do
						if part.Name == "Cap" then
							clickRing(tile, part, PINK)
						end
					end
					if glow then
						burst(glow, PINK, held, 8 + 3 * held, 0.4)
					end
				end
			end
			rippleLights(tile, 1, feel.ripple, WHITE)

			if ctx.combo == "circuit" then
				-- OVERLOAD: the whole lane, pressed in one streak. Two waves of light across the pad, two
				-- flash waves spreading from your foot, sparks off every clicky button on it, the brightest
				-- light in the level, and the camera shakes for whoever did it.
				rippleLights(tile, 8, 1, WHITE)
				task.delay(0.12, function()
					if tile.Parent then
						rippleLights(tile, 8, 0.9, LANE)
					end
				end)
				shockwave(tile, WHITE, 30, 0.55, 0)
				shockwave(tile, LANE, 22, 0.5, 0.1)
				if glow then
					burst(glow, LANE, B.overloadBurst, B.overloadRange, B.overloadTime)
				end
				local slab = tile.Parent
				if slab then
					for _, other in ipairs(slab:GetChildren()) do
						if other:IsA("BasePart") and other:GetAttribute("Switch") == "clicky" then
							local _, otherCores = partsOf(other)
							if otherCores[1] then
								sparks(otherCores[1], LANE, B.sparks, B.sparkSpeed * 1.3)
							end
						end
					end
				end
				if ctx.mine then
					shake(B.shake, B.shakeTime)
				end
			elseif ctx.combo then
				-- THE COMBO: the whole pad answers, in a wave of lane-cyan from this button outward.
				rippleLights(tile, 8, B.comboFlash, LANE)
				shockwave(tile, LANE, 16, 0.45, 0)
				if glow then
					burst(glow, LANE, B.comboBurst, B.comboRange, B.comboTime)
					sparks(glow, LANE, B.sparks * 2, B.sparkSpeed * 1.2)
				end
				if ctx.mine then
					shake(B.shake * 0.4, B.shakeTime * 0.6)
				end
			end
			return
		end

		if ctx.state == "decaying" then
			-- THE RELEASE, when the server says your foot has genuinely left the cell -- not a timer
			-- guessing -- so the cap comes up exactly when you step off and not a moment before.
			if switch == "clicky" then
				-- Back OUT past rest and settle: a spring under a cap does not glide home, it rings.
				travel(tile, moving, TweenInfo.new(feel.up, Enum.EasingStyle.Back, Enum.EasingDirection.Out), feel.overshoot)
				task.delay(feel.up, function()
					if tile.Parent and lastState[tile] == "decaying" then
						travel(tile, moving, TweenInfo.new(feel.settle, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), 0)
					end
				end)
			elseif switch == "tactile" and ctx.cause == "spring" then
				-- THE LAUNCH: whoever was on it jumped, and the spring throws them. The caps fly up past rest
				-- and ring back down, a pink wave and a shower of sparks go off the pad, and a pink streak
				-- follows the jumper up -- all of it bigger at every level of a bounce chain.
				local level = ctx.charge or 1
				travel(tile, moving, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					B.springFling * level)
				task.delay(0.07, function()
					if tile.Parent and lastState[tile] == "decaying" then
						travel(tile, moving, TweenInfo.new(0.5, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), 0)
					end
				end)
				for _, core in ipairs(cores) do
					flash(core, WHITE, 1, 0.06, 0.5)
				end
				if glow then
					burst(glow, PINK, 1.5 + level, 10 + 3 * level, 0.5)
					sparks(glow, PINK, B.springSparks * level, B.sparkSpeed * 1.4)
				end
				shockwave(tile, PINK, B.springWave + 4 * level, 0.4, 0)
				springTrail(ctx.who, level)
			elseif switch == "tactile" then
				-- The bump again, on the way up.
				travel(tile, moving, TweenInfo.new(feel.up, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					-feel.drop * feel.bump)
				task.delay(feel.up + feel.hold, function()
					if tile.Parent and lastState[tile] == "decaying" then
						travel(tile, moving, TweenInfo.new(feel.up, Enum.EasingStyle.Back, Enum.EasingDirection.Out), 0)
					end
				end)
			else
				travel(tile, moving, TweenInfo.new(feel.up, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), 0)
			end
			return
		end

		-- pristine, or anything else: sit still at rest.
		travel(tile, moving, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), 0)
	end
end

Effects.Snow = function(ctx: Ctx)
	local tile = ctx.tile
	if ctx.state == "exhausted" then
		local give = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, give, -NEW_MATS.Snow.drop)
		else
			moveTile(tile, give, -NEW_MATS.Snow.drop, 1, 1)
		end
		return
	end
	if ctx.state == "pristine" then
		packed[tile] = nil
		clearMarks(tile)
		local fresh = TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, fresh, 0)
		else
			moveTile(tile, fresh, 0, 1, 1)
		end
		return
	end
	if ctx.state ~= "deformed" then
		return
	end

	-- Packs like salt, but it is on the way somewhere. Salt levels off and holds; snow keeps
	-- going until the cell drops out from under you.
	local stage = math.clamp(ctx.stepCount or 1, 1, #NEW_MATS.Snow.steps)
	local depth = NEW_MATS.Snow.steps[stage]
	packed[tile] = depth
	local press = TweenInfo.new(NEW_MATS.Snow.time, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	local bone = boneFor(tile)
	if bone then
		setResidual(tile, bone, press, -depth)
	else
		moveTile(tile, press, -depth, 1, 1)
	end

	-- ONE SET PER VISIT, not one per replicated event: the cell re-announces itself every
	-- time you re-enter it, and stamping each time stacks prints on the same spot until the
	-- surface reads as a solid trench.
	if not marks[tile] or #marks[tile] == 0 then
		for _, hit in ipairs(localFootWorldPoints(tile)) do
			spawnFootprint(tile, hit, ctx.material, NEW_MATS.Snow.printLife, depth * 0.6)
		end
	end

	local origin = Instance.new("Attachment")
	origin.Name = "SnowOrigin"
	origin.Position = Vector3.new(0, (restSize[tile] and restSize[tile].Y or 1) / 2, 0)
	origin.Parent = tile
	local powder = Instance.new("ParticleEmitter")
	powder.Texture = "rbxasset://textures/particles/smoke_main.dds"
	powder.Color = ColorSequence.new(Color3.fromRGB(250, 252, 255))
	powder.Size = NumberSequence.new(0.9)
	powder.Lifetime = NumberRange.new(0.4, 0.8)
	-- Slow and buoyant. Powder hangs; anything fast reads as spray.
	powder.Speed = NumberRange.new(1, 4)
	powder.SpreadAngle = Vector2.new(65, 65)
	powder.Rate = 0
	powder.Acceleration = Vector3.new(0, -6, 0)
	powder.Transparency = NumberSequence.new(0.4)
	powder.Parent = origin
	powder:Emit(NEW_MATS.Snow.puff)
	Debris:AddItem(origin, 1.6)
	-- Clumps alongside the powder. A boot in packed snow kicks up both, and powder
	-- alone reads as dust rather than as snow.
	flingDebris(tile, "SnowClump", 3)
end

-- ===== CLAY AND SALT: material that moves =====
--
-- The server moves material between cells (see DISPLACEMENT in DeformationService) and tells every
-- cell it touched how far it has gone down (`depth`), how much has been pushed into it (`push`),
-- which way it leans (`lean`), and whether the update is a foot landing on it, a foot standing on it
-- or a neighbour's weight arriving (`cause`). So these two draw a SHAPE from numbers rather than
-- playing an animation per event: a cell nobody stood on still rises, curls, cracks or tilts,
-- because the weight next to it went somewhere.
--
-- In a do-block on purpose. This module sits a dozen registers under Luau's limit of 200 locals in
-- one scope, and nothing in here is wanted by anything outside it.
do
	local CLAY = NEW_MATS.Clay
	local SALT = NEW_MATS.Salt
	local BRINE = Color3.fromRGB(70, 98, 108)
	local HAIRLINE = Color3.fromRGB(150, 158, 162)

	-- The push each cell was last drawn at, so a warning plays once on the way up rather than on
	-- every update that repeats it.
	local shownPush = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: number }

	-- A world direction in a bone's own frame, from its REST frame: the Transform is the thing being
	-- set, and reading through it would stack every update onto the one before.
	local function boneLocal(bone: Bone, world: Vector3): Vector3
		return (bone.WorldCFrame * bone.Transform:Inverse()):VectorToObjectSpace(world)
	end

	local function flatUnit(lean: Vector3?): Vector3?
		if not lean then
			return nil
		end
		local flat = Vector3.new(lean.X, 0, lean.Z)
		return if flat.Magnitude > 0.05 then flat.Unit else nil
	end

	-- Moves a cell's bone and its collider to a shape: `rise` studs up (negative is down), `slide`
	-- studs along `lean`, and `tilt` radians tipping the lean side down. The Floor follows `collide`
	-- of the rise, and of the tilt when `tiltFloor` is set: a salt plate tips under your feet, a
	-- clay lip only looks as if it is about to.
	local function shape(tile: BasePart, info: TweenInfo, rise: number, lean: Vector3?, slide: number,
		tilt: number, collide: number, tiltFloor: boolean)
		local out = flatUnit(lean)
		-- Turning about up-cross-out takes the OUT side down and the near side up.
		local axis = if out then Vector3.yAxis:Cross(out) else nil

		local bone = boneFor(tile)
		if bone then
			local offset = boneLocal(bone, Vector3.yAxis) * rise
			if out then
				offset += boneLocal(bone, out) * slide
			end
			local goal = CFrame.new(offset)
			if axis and tilt ~= 0 then
				goal *= CFrame.fromAxisAngle(boneLocal(bone, axis), tilt)
			end
			play(tile, bone, info, { Transform = goal })
		end

		local floor = floorOf(tile)
		local rest = floor and floorRest[floor]
		if floor and rest then
			local goal = rest * CFrame.new(0, rise * collide, 0)
			if tiltFloor and axis and tilt ~= 0 then
				goal *= CFrame.fromAxisAngle(rest:VectorToObjectSpace(axis), tilt * collide)
			end
			play(tile, floor, info, { CFrame = goal })
		end
	end

	-- === Clay ===

	local function clayLimit(): number
		return Materials.Clay and Materials.Clay.displaceLimit or 3
	end

	local function clayShape(ctx: Ctx, time: number)
		local depth, push = ctx.depth or 0, ctx.push or 0
		local fill = math.min(push, clayLimit()) / clayLimit()
		local rise = -CLAY.press * depth + CLAY.rise * math.min(push, CLAY.riseCap)
		shape(ctx.tile, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			rise, ctx.lean, CLAY.slide * fill, CLAY.curl * fill, CLAY.collide, false)
	end

	-- THE LIP TEARS OFF. A slab of clay the size of the cell swings out over the edge on a hinge
	-- along its inner side, lets go and falls, turning over; the bed under it funnels away so the
	-- gap it leaves reads as a gap rather than as a dent.
	local function peelClay(tile: BasePart, lean: Vector3?)
		local size = restSize[tile]
		local top = tileTop(tile)
		local out = flatUnit(lean) or top.RightVector
		local colour = MaterialAppearance.Appearances.Clay.color

		local start = top * CFrame.new(0, -CLAY.peelThick / 2, 0)
		local along = start:VectorToObjectSpace(out)
		local reach = math.abs(along.X) * size.X / 2 + math.abs(along.Z) * size.Z / 2
		local hinge = CFrame.new(start.Position - out * reach) * start.Rotation
		local offset = hinge:Inverse() * start
		local axis = hinge:VectorToObjectSpace(Vector3.yAxis:Cross(out))

		local lip = Instance.new("Part")
		lip.Name = "ClayPeel"
		lip.Size = Vector3.new(size.X, CLAY.peelThick, size.Z)
		lip.CFrame = start
		lip.Anchored = true
		lip.CanCollide = false
		lip.CanTouch = false
		lip.CanQuery = false
		lip.Material = Enum.Material.Sandstone
		lip.Color = colour
		lip.Parent = workspace

		-- Driven through a value rather than tweened as a CFrame: a CFrame tween blends straight
		-- from one pose to the other and cuts across the arc, so the slab would slide through the
		-- edge instead of swinging over it.
		local swing = Instance.new("NumberValue")
		swing.Parent = lip
		swing.Changed:Connect(function(angle: number)
			if lip.Parent then
				lip.CFrame = hinge * CFrame.fromAxisAngle(axis, angle) * offset
			end
		end)
		TweenService:Create(swing, TweenInfo.new(CLAY.peelTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Value = CLAY.peelAngle }):Play()
		task.delay(CLAY.peelTime, function()
			if lip.Parent then
				lip.Anchored = false
				lip.AssemblyLinearVelocity = out * 8 - Vector3.new(0, 6, 0)
				lip.AssemblyAngularVelocity = Vector3.yAxis:Cross(out) * 2.5
			end
		end)
		Debris:AddItem(lip, CLAY.peelTime + 3)

		local bone = boneFor(tile)
		if bone then
			play(tile, bone, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transform = CFrame.new(boneLocal(bone, Vector3.yAxis) * -CLAY.hole + boneLocal(bone, out) * CLAY.holeSlide),
			})
		end
		flingDebris(tile, "ClayChip", 6)
		puff(tile, colour, 0.3, 6, -20, 10)
	end

	Effects.Clay = function(ctx: Ctx)
		local tile = ctx.tile
		if ctx.state == "exhausted" then
			shownPush[tile] = nil
			peelClay(tile, ctx.lean)
			return
		end

		local depth, push = ctx.depth or 0, ctx.push or 0
		clayShape(ctx, if ctx.cause == "push" then CLAY.pushTime else CLAY.time)

		if ctx.state == "pristine" and depth == 0 and push == 0 then
			-- The session-long hold ran out, or a restart put the slab back: the prints go too.
			clearMarks(tile)
			shownPush[tile] = nil
			return
		end

		if ctx.cause == "step" then
			puff(tile, MaterialAppearance.Appearances.Clay.color, 0.22, 5, -14, 6)
			flingDebris(tile, "ClayChip", 2)
			for _, hit in ipairs(localFootWorldPoints(tile)) do
				spawnFootprint(tile, hit, ctx.material, CLAY.markLife, CLAY.press * math.max(depth, 1) * 0.65)
			end
		elseif ctx.cause == "creep" then
			-- Standing still: no new print, only the clay going on giving under you.
			flingDebris(tile, "ClayChip", 1)
		end

		-- ONE SQUEEZE FROM TEARING. The lip sheds as it gets there, once, and that is the warning.
		local warnAt = clayLimit() - 1
		if ctx.lean and push >= warnAt and (shownPush[tile] or 0) < warnAt then
			flingDebris(tile, "ClayChip", 4)
			puff(tile, MaterialAppearance.Appearances.Clay.color, 0.18, 3, -26, 6)
		end
		shownPush[tile] = push
	end

	-- === Salt ===

	local function saltTilt(): number
		return Materials.Salt and Materials.Salt.displaceTilt or 2
	end

	local function saltShape(ctx: Ctx, time: number)
		local depth, push = ctx.depth or 0, ctx.push or 0
		local rise = 0
		local lean: Vector3? = nil
		local tilt = 0
		if depth > 0 then
			rise = -SALT.steps[math.clamp(depth, 1, #SALT.steps)]
		elseif push >= saltTilt() then
			-- FLOATING: lifted, and tipped up on the side the brine came in from. The lean points
			-- away from the push, so taking its far side down raises the near one.
			rise, lean, tilt = SALT.lift, ctx.lean, SALT.tilt
		elseif push > 0 then
			rise = SALT.heave
		end
		shape(ctx.tile, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			rise, lean, 0, tilt, SALT.collide, true)
	end

	-- Cracks drawn on the COLLIDER rather than on the sensor, because a salt plate moves: a crack
	-- left on the sensor would stay at the old surface while the crust it belongs to lifts off it.
	local function saltCanvas(tile: BasePart)
		local existing = crackGuis[tile]
		if existing and existing.Parent then
			return
		end
		local floor = floorOf(tile)
		if not floor then
			return
		end
		local gui = Instance.new("SurfaceGui")
		gui.Name = "CrackOverlay"
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = CRACK_PPS
		gui.AlwaysOnTop = false
		gui.ZOffset = 0.02
		gui.Adornee = floor
		gui.Parent = tile
		local clip = Instance.new("Frame")
		clip.Name = "Clip"
		clip.Size = UDim2.fromScale(1, 1)
		clip.BackgroundTransparency = 1
		clip.ClipsDescendants = true
		clip.Parent = gui
		crackGuis[tile] = gui
	end

	local function bubbles(at: BasePart, count: number)
		local origin = Instance.new("Attachment")
		origin.Name = "BrineOrigin"
		origin.Position = Vector3.new(0, at.Size.Y / 2, 0)
		origin.Parent = at
		local rise = Instance.new("ParticleEmitter")
		rise.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		rise.Color = ColorSequence.new(Color3.fromRGB(214, 232, 236))
		rise.Size = NumberSequence.new(0.14)
		rise.Lifetime = NumberRange.new(0.5, 1.1)
		rise.Speed = NumberRange.new(0.6, 1.8)
		rise.SpreadAngle = Vector2.new(35, 35)
		rise.Rate = 0
		rise.Acceleration = Vector3.new(0, 2.5, 0)
		rise.Transparency = NumberSequence.new(0.35)
		rise.Parent = origin
		rise:Emit(count)
		Debris:AddItem(origin, 1.6)
	end

	-- THE PLATE BREAKS AND GOES UNDER. Sinking, rather than dropping out the way sand does: the bed
	-- funnels down slowly, brine bubbles up through the gap, and the crust goes under in pieces.
	--
	-- NO SHEET OF BRINE. There was one -- a translucent blue-grey part the size of the cell closing
	-- over the hole -- and in play it read as dark blue squares floating beside the salt, not as
	-- liquid. Reported, and removed; the bubbles and the sinking crust say it on their own.
	local function sinkSalt(tile: BasePart)
		clearCracks(tile)
		local size = restSize[tile]
		local top = tileTop(tile)

		local bone = boneFor(tile)
		if bone then
			play(tile, bone, TweenInfo.new(SALT.sinkTime, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
				{ Transform = CFrame.new(boneLocal(bone, Vector3.yAxis) * -SALT.hole) })
		end

		bubbles(tile, 14)

		for index = 1, SALT.floes do
			local floe = Instance.new("Part")
			floe.Name = "SaltFloe"
			floe.Size = Vector3.new(size.X * (0.3 + math.random() * 0.2), 0.22, size.Z * (0.3 + math.random() * 0.2))
			local from = top * CFrame.new((math.random() - 0.5) * size.X * 0.45, -0.12, (math.random() - 0.5) * size.Z * 0.45)
			floe.CFrame = from
			floe.Anchored = true
			floe.CanCollide = false
			floe.CanTouch = false
			floe.CanQuery = false
			floe.Material = Enum.Material.Sand
			floe.Color = MaterialAppearance.Appearances.Salt.color
			floe.Parent = tile.Parent
			local under = SALT.sinkTime + index * 0.4
			TweenService:Create(floe, TweenInfo.new(under, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				CFrame = from * CFrame.new(0, -SALT.brineDepth - 1.2, 0)
					* CFrame.Angles((math.random() - 0.5) * 1.1, (math.random() - 0.5) * 0.6, (math.random() - 0.5) * 1.1),
			}):Play()
			Debris:AddItem(floe, under + 0.05)
		end
		flingDebris(tile, "SaltCrystal", 3)
	end

	Effects.Salt = function(ctx: Ctx)
		local tile = ctx.tile
		if ctx.state == "exhausted" then
			shownPush[tile] = nil
			sinkSalt(tile)
			return
		end

		local depth, push = ctx.depth or 0, ctx.push or 0
		saltShape(ctx, if ctx.cause == "push" then SALT.heaveTime else SALT.time)

		if depth > 0 or push == 0 then
			-- Packed crust has no cracks left to show, and crust nothing has pushed never had any.
			clearCracks(tile)
		end

		if depth > 0 and (ctx.cause == "step" or ctx.cause == "creep") then
			-- FEWER EACH TIME. The first step shatters loose crystals; by the last there is nothing
			-- left up there to throw, which is what packed means.
			local stage = math.clamp(depth, 1, #SALT.steps)
			local origin = Instance.new("Attachment")
			origin.Name = "SaltOrigin"
			origin.Position = Vector3.new(0, (restSize[tile] and restSize[tile].Y or 1) / 2, 0)
			origin.Parent = tile
			local grains = Instance.new("ParticleEmitter")
			grains.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			grains.Color = ColorSequence.new(Color3.fromRGB(250, 250, 252))
			grains.Size = NumberSequence.new(0.07)
			grains.Lifetime = NumberRange.new(0.25, 0.5)
			grains.Speed = NumberRange.new(3, 8)
			grains.SpreadAngle = Vector2.new(75, 75)
			grains.Rate = 0
			grains.Acceleration = Vector3.new(0, -70, 0)
			grains.Parent = origin
			grains:Emit(math.max(2, SALT.crunch - stage * 2))
			Debris:AddItem(origin, 1.2)
			-- Whole crystals as well as the dust: the cubes are what identify the material.
			flingDebris(tile, "SaltCrystal", math.max(1, SALT.shed - stage))
		end

		-- THE CRUST BESIDE A TRAIL: cracked by the first push of brine, floating on the second.
		if depth == 0 and push > (shownPush[tile] or 0) then
			saltCanvas(tile)
			if push >= saltTilt() then
				addCrackNetwork(tile, SALT.tiltCracks, BRINE, SALT.crackLife)
				bubbles(tile, 6)
			else
				addCrackNetwork(tile, SALT.hairlines, HAIRLINE, SALT.crackLife)
			end
			flingDebris(tile, "SaltCrystal", 1)
		end
		shownPush[tile] = if depth == 0 then push else 0
	end
end

Effects.Cloud = function(ctx: Ctx)
	local tile = ctx.tile
	if ctx.state == "exhausted" then
		-- IT GIVES OUT. There was no picture for this at all: the cell had been sinking, the server took
		-- its collision away, and the surface simply stayed where the sink had left it. Now it drops out
		-- fast, in a burst of vapour.
		local give = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, give, -NEW_MATS.Cloud.drop)
		else
			moveTile(tile, give, -NEW_MATS.Cloud.drop, 1, 1)
		end
		puff(tile, Color3.fromRGB(250, 252, 255), 2.2, 3, 1.5, 14)
		flingDebris(tile, "CloudWisp", 5)
		return
	end
	if ctx.state == "deformed" then
		flingDebris(tile, "CloudWisp", 3)
		-- NO THRESHOLD ANYWHERE IN HERE. Ice counts your steps and shows you the crack
		-- widening; cloud has nothing to count, so there is nothing to read and nothing to
		-- plan around. You are descending from the moment you land.
		dwellSink(tile, NEW_MATS.Cloud.rate, NEW_MATS.Cloud.cap, NEW_MATS.Cloud.tick)
		local origin = Instance.new("Attachment")
		origin.Name = "VapourOrigin"
		origin.Position = Vector3.new(0, (restSize[tile] and restSize[tile].Y or 1) / 2, 0)
		origin.Parent = tile
		local vapour = Instance.new("ParticleEmitter")
		vapour.Texture = "rbxasset://textures/particles/smoke_main.dds"
		vapour.Color = ColorSequence.new(Color3.fromRGB(250, 252, 255))
		vapour.Size = NumberSequence.new(2.6)
		vapour.Lifetime = NumberRange.new(0.6, 1.3)
		vapour.Speed = NumberRange.new(0.5, 1.8)
		vapour.SpreadAngle = Vector2.new(50, 50)
		vapour.Rate = 0
		vapour.Acceleration = Vector3.new(0, 1.5, 0)   -- vapour rises; dust does not
		vapour.Transparency = NumberSequence.new(0.6)
		vapour.Parent = origin
		vapour:Emit(10)
		Debris:AddItem(origin, 2)
	elseif ctx.state == "pristine" then
		local reform = TweenInfo.new(NEW_MATS.Cloud.recover, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		local bone = boneFor(tile)
		if bone then
			setResidual(tile, bone, reform, 0)
		else
			moveTile(tile, reform, 0, 1, 1)
		end
	end
end

-- ===== The two skinned beds that had no driver =====
--
-- Effects is not decoration. It is what MOVES THE BONES: a material with no entry here is
-- rigged, reports its deformations, and never visibly changes, which is exactly how the
-- Needoh bed shipped last round. Both of these are modelled on Honey rather than Slime
-- because both are ONE skinned mesh with overlapping bone influences, where neighbouring
-- cells blend and a real wave can run; slime's driver is written for edge-matched per-tile
-- meshes that tear if you push them.
--
-- Neither sheds anything. There is no puff and no debris in either, and that is the whole
-- difference from Honey: a sealed toy and a cut stick do not spray.
local NEEDOH = {}
NEEDOH.PRESS = 1.30
NEEDOH.RESIDUAL_FRACTION = 0.42
NEEDOH.RIPPLE = RippleProfiles.Needoh

local BUTTER_STICK = {}
-- Deeper than the Needoh and it gives most of it back far more slowly. Butter is the softest
-- thing here; it should feel like standing in it rather than on it.
BUTTER_STICK.PRESS = 1.62
BUTTER_STICK.RESIDUAL_FRACTION = 0.74
BUTTER_STICK.RIPPLE = RippleProfiles.ButterStick

-- ONE DRIVER, TWO MATERIALS. They differ by four numbers and a name, so writing them out
-- twice would mean two places to fix the next time the press is retuned.
local function softBedEffect(profile: any)
	return function(ctx: Ctx)
		local tile = ctx.tile
		local slab = tile.Parent
		local onSlab = (slab and slab:IsA("BasePart")) and slab or nil
		local bone = boneFor(tile)

		if ctx.state == "deformed" then
			-- Quick down, because the give is immediate on both of these -- there is no
			-- viscosity holding your foot up the way honey has.
			moveTile(tile, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				-profile.PRESS, 0.95, 1.08)
			if bone and onSlab then
				rippleFrom(onSlab, bone.WorldPosition, profile.RIPPLE)
			end
		elseif ctx.state == "decaying" then
			-- Stepped off, and the dent stays. On the Needoh it eases back most of the way;
			-- on butter it barely moves, which is what the two fractions above encode.
			if bone then
				setResidual(tile, bone,
					TweenInfo.new(1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
					-profile.PRESS * profile.RESIDUAL_FRACTION)
			else
				settleTile(tile, 0.8)
			end
		else
			-- pristine: the decay window closed and the surface has come back.
			if bone then
				setResidual(tile, bone,
					TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), 0)
			else
				settleTile(tile, 0.8)
			end
		end
	end
end

-- MOLTEN KEYS: the squish of a soft bed, plus lava's heat on top.
--
-- Written as a wrapper rather than as a whole new effect, because the two halves are
-- genuinely independent -- one moves the geometry, the other moves the colour -- and the
-- movement half is already solved by softBedEffect. Anything that retunes the press later
-- retunes this for free.
local LAVA_KEYS = {}
-- Shallow. A keycap bottoms out on its chassis; the give is a fraction of a stud and
-- pretending otherwise turns the keyboard into a mattress.
LAVA_KEYS.PRESS = 0.55
LAVA_KEYS.RESIDUAL_FRACTION = 0.20
LAVA_KEYS.RIPPLE = RippleProfiles.Needoh

local HOT_KEY = Color3.fromRGB(255, 138, 44)
local COOL_KEY = Color3.fromRGB(46, 40, 38)

local pressKeys = softBedEffect(LAVA_KEYS)

Effects.LavaKeys = function(ctx: Ctx)
	pressKeys(ctx)
	local tile = ctx.tile
	if ctx.state == "deformed" then
		-- Set instantly and cooled slowly. Heat arrives at the speed of the foot and leaves
		-- at the speed of the material, and reversing those is what makes a glow read as a
		-- light being switched rather than as something being heated.
		tile.Color = HOT_KEY
		TweenService:Create(tile,
			TweenInfo.new(2.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Color = COOL_KEY }):Play()
	end
end

-- ===== NEEDOH: the squeeze =====
--
-- The soft bed's press -- a footfall, and a footprint that lingers and closes -- and three things only a
-- Needoh does, all driven by `charge` from DeformationService. STAND STILL and the hollow goes on
-- deepening while the bed swells up around it. At full squeeze the hollow shivers and glows teal:
-- the jump out of it is loaded. LET GO -- jump out, or walk off -- and the hollow pops back past its
-- footprint while the swell drains away.
do
	local SQUEEZE = { deep = 2.5, swell = 0.36, reach = 7, rebound = 0.6,
		glow = Color3.fromRGB(120, 255, 236), glowBrightness = 1.4, glowRange = 7 }
	local press = softBedEffect(NEEDOH)
	local shownCharge = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: number }
	local glows = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: PointLight }

	-- THE DOUGH HAS TO GO SOMEWHERE. Every bone within `reach` of the hollow that is not itself held
	-- down under a foot rises by up to `amount`, less the further away it is.
	local function swellAround(slab: BasePart, origin: Vector3, amount: number, time: number)
		for _, bone in ipairs(bonesForPlatform(slab)) do
			if not heldSink[bone] then
				local at = bone.WorldPosition
				local distance = Vector3.new(at.X - origin.X, 0, at.Z - origin.Z).Magnitude
				if distance > 1.8 and distance < SQUEEZE.reach then
					local lift = amount * (1 - (distance - 1.8) / (SQUEEZE.reach - 1.8))
					-- Supersedes a ripple in flight, which would otherwise pull this back to rest.
					rippleToken[bone] = (rippleToken[bone] or 0) + 1
					boneOffset(bone, TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
						(residualSink[bone] or 0) + lift)
				end
			end
		end
	end

	local function setGlow(tile: BasePart, on: boolean)
		local light = glows[tile]
		if on and not light then
			local made = Instance.new("PointLight")
			made.Color = SQUEEZE.glow
			made.Brightness = 0
			made.Range = SQUEEZE.glowRange
			made.Shadows = false
			made.Parent = tile
			glows[tile] = made
			TweenService:Create(made, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Brightness = SQUEEZE.glowBrightness }):Play()
		elseif not on and light then
			glows[tile] = nil
			TweenService:Create(light, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Brightness = 0 }):Play()
			Debris:AddItem(light, 0.35)
		end
	end

	-- LOADED: a tight shiver in the hollow, the dough saying the jump is ready.
	local function shiver(tile: BasePart, bone: Bone, sink: number)
		task.spawn(function()
			for index = 1, 4 do
				if not bone.Parent or (shownCharge[tile] or 0) < 1 then
					return
				end
				boneOffset(bone, TweenInfo.new(0.05, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					sink + (if index % 2 == 1 then 0.08 else -0.08))
				task.wait(0.05)
			end
			if bone.Parent and (shownCharge[tile] or 0) >= 1 then
				boneOffset(bone, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), sink)
			end
		end)
	end

	Effects.Needoh = function(ctx: Ctx)
		local tile = ctx.tile
		local slab = tile.Parent
		local onSlab = if slab and slab:IsA("BasePart") then slab else nil
		local bone = boneFor(tile)
		local charge = ctx.charge or 0
		local before = shownCharge[tile] or 0
		shownCharge[tile] = charge

		if ctx.cause == "charge" then
			if charge > 0 then
				local sink = -(NEEDOH.PRESS + (SQUEEZE.deep - NEEDOH.PRESS) * charge)
				moveTile(tile, TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), sink, 0.95, 1.08)
				if bone and onSlab then
					swellAround(onSlab, bone.WorldPosition, SQUEEZE.swell * charge, 0.45)
				end
				setGlow(tile, charge >= 1)
				if charge >= 1 and bone then
					local held: Bone = bone
					task.delay(0.35, function()
						if held.Parent then
							shiver(tile, held, sink)
						end
					end)
				end
			else
				-- Moved without jumping: back to an ordinary footprint, and the swell drains.
				moveTile(tile, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), -NEEDOH.PRESS, 0.95, 1.08)
				if bone and onSlab then
					swellAround(onSlab, bone.WorldPosition, 0, 0.7)
				end
				setGlow(tile, false)
			end
			return
		end

		press(ctx)

		if ctx.state ~= "deformed" then
			setGlow(tile, false)
			-- LET GO AFTER A SQUEEZE: the hollow pops back past its footprint and settles, and the swell
			-- around it drains. The skin pulling the hollow shut is the only spring a Needoh has.
			if before > 0.3 and bone then
				setResidual(tile, bone, TweenInfo.new(SQUEEZE.rebound, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					-NEEDOH.PRESS * NEEDOH.RESIDUAL_FRACTION)
				if onSlab then
					swellAround(onSlab, bone.WorldPosition, 0, 0.9)
				end
			end
		end
	end
end

Effects.ButterStick = softBedEffect(BUTTER_STICK)

Effects.JelloSoda = Effects.Slime

Effects.BubbleWrap = function(ctx: Ctx)
	local tile = ctx.tile
	local pockets = pocketsFor(tile, ctx.layer)
	-- THE AIR OUT OF THE POCKET, and the only reason this material has particles at all --
	-- the plastic itself sheds nothing. Guarded here rather than in a branch because this
	-- effect has no plain "deformed" arm: it is driven by pop index, not by state.
	if ctx.state == "deformed" then
		puff(tile, Color3.fromRGB(236, 250, 254), 0.30, 7, 6, 3)
	end
	if #pockets == 0 and (ctx.layer or 1) <= 1 then
		if not warnedNoSheet then
			warnedNoSheet = true
			warn(
				"DeformationRenderer: a BubbleWrap tile has no skinned sheet, so nothing will pop. "
					.. "Import the BubbleWrap_Sheet_* FBXs into ReplicatedStorage/Assets/TileMeshes WITH their Bone children."
			)
		end
		return
	end

	if ctx.state == "pristine" then
		local info = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		for _, bone in ipairs(pockets) do
			if burstBones[bone] then
				burstBones[bone] = nil
				TweenService:Create(bone, info, { Transform = CFrame.identity }):Play()
			end
		end
		settleTile(tile, 0.25)
		return
	end

	-- BURST WHERE YOU TROD, which is the whole reason this is position-driven. The
	-- pockets belong to the platform rather than to this cell, so bursting by index
	-- would collapse pockets on the far side of the sheet from where you are standing --
	-- the same mistake soap and wax both had.
	local feet = localFootWorldPoints(tile)
	local points: { Vector3 } = {}
	for _, hit in ipairs(feet) do
		table.insert(points, hit.position)
	end
	if #points == 0 then
		-- Not the local player's step, so there is no contact point to centre on. The
		-- cell centre keeps the burst compact instead of scattering it.
		table.insert(points, tile.Position)
	end

	-- Collected with their distance, then burst NEAREST FIRST and staggered. Firing the
	-- whole knot on one frame is a single dull thud; a few tens of milliseconds apart it
	-- crackles, and running outward from the foot makes the crackle travel away from
	-- you, which is what sells that your own weight caused it.
	local reach = reachFor(pockets)
	local hit: { { bone: Bone, distance: number } } = {}
	for _, bone in ipairs(pockets) do
		if not burstBones[bone] then
			local at = bone.WorldPosition
			local nearest = math.huge
			for _, foot in ipairs(points) do
				local dx, dz = at.X - foot.X, at.Z - foot.Z
				nearest = math.min(nearest, dx * dx + dz * dz)
			end
			if nearest <= reach * reach then
				table.insert(hit, { bone = bone, distance = nearest })
			end
		end
	end

	if #hit == 0 then
		return -- everything underfoot is already flat; do not re-jolt the tile
	end
	table.sort(hit, function(a, b)
		return a.distance < b.distance
	end)

	for index, entry in ipairs(hit) do
		if index == 1 then
			burstPocket(tile, pockets, entry.bone)
		else
			-- Claimed NOW rather than inside the delay, so a second footfall arriving
			-- during the stagger cannot queue the same pocket a second time.
			burstBones[entry.bone] = true
			local bone = entry.bone
			task.delay(POP_STAGGER * (index - 1), function()
				if bone.Parent and burstBones[bone] then
					burstBones[bone] = nil
					burstPocket(tile, pockets, bone)
				end
			end)
		end
	end

	-- The sheet gives where it collapsed. The pockets carry the event themselves now, so
	-- this only has to be the give underfoot rather than the whole punch.
	local jolt = TweenInfo.new(0.05, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	moveTile(tile, jolt, -0.3, 0.95, 1.0)
	task.delay(0.09, function()
		if tile.Parent then
			settleTile(tile, 0.16)
		end
	end)
end

-- === Entry point ===

function DeformationRenderer.onDeformationUpdate(payload)
	local tile = payload.part
	if typeof(tile) ~= "Instance" or not tile:IsA("BasePart") or not tile.Parent then
		return
	end

	local material = payload.material
	local state = payload.state
	remember(tile)

	-- THE FLOOR GOES AND YOU GO WITH IT, AT ONCE, on every material that can drop you. When a cell
	-- gives way under this client's own character, the character goes straight into free fall with a
	-- hard downward start and a moment of extra weight. Otherwise it stands on a collider that is still
	-- waiting for the server's CanCollide to arrive, then drifts off it at the start of a fall that
	-- reads as floating.
	if state == "exhausted" then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rest, size = restCFrame[tile], restSize[tile]
		if root and root:IsA("BasePart") and humanoid and rest and size then
			local over = rest:PointToObjectSpace(root.Position)
			if math.abs(over.X) <= size.X / 2 and math.abs(over.Z) <= size.Z / 2 and over.Y > -1.5 and over.Y < 7 then
				local floor = tile:FindFirstChild("Floor")
				if floor and floor:IsA("BasePart") then
					floor.CanCollide = false
				end
				tile.CanCollide = false
				humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
				local velocity = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(velocity.X * 0.5, math.min(velocity.Y, -NEW_MATS.Fall.snap), velocity.Z * 0.5)
				local anchor: Attachment? = nil
				local found = root:FindFirstChild("RootAttachment")
				if found and found:IsA("Attachment") then
					anchor = found
				else
					local made = Instance.new("Attachment")
					made.Name = "FallPull"
					made.Parent = root
					anchor = made
					Debris:AddItem(made, NEW_MATS.Fall.pullTime)
				end
				local pull = Instance.new("VectorForce")
				pull.Name = "FallPull"
				pull.Attachment0 = anchor
				pull.RelativeTo = Enum.ActuatorRelativeTo.World
				pull.ApplyAtCenterOfMass = true
				pull.Force = Vector3.new(0, -root.AssemblyMass * workspace.Gravity * NEW_MATS.Fall.pull, 0)
				pull.Parent = root
				Debris:AddItem(pull, NEW_MATS.Fall.pullTime)
			end
		end
	end

	-- Bubble wrap is driven by pop index, not by state transitions: four pops
	-- all arrive as "deformed" and each one has to land.
	local isRepeat = lastState[tile] == state
	-- KEYBOARD REPEATS, like bubble wrap does. Most materials announce a state change
	-- once and the renderer would be re-playing the same dent to no effect -- but both of
	-- these are made of discrete THINGS you act on individually, so a second crossing has
	-- to press the keys under your feet this time rather than being deduplicated away as
	-- "already deformed".
	-- SOUND FIRES BEFORE THE REPEAT GUARD, and this is the bug it was behind.
	--
	-- The guard exists for VISUALS: re-playing a dent tween on a cell that is already
	-- dented achieves nothing, so a repeat is dropped. But it sat above the audio call, so
	-- dropping the repeat dropped the sound too -- and a cell stays "deformed" for its
	-- whole decay window, seven seconds on sand. Walk out over fresh cells and every step
	-- sounds; turn round and walk back over your own footprints and the platform is
	-- SILENT until they decay. That is the "plays twice then nothing for about four
	-- seconds" -- it was never the id list, and adding ids could not have fixed it.
	--
	-- Audio has no reason to dedupe by state: stepping on a dented cell is still a step,
	-- and it should still make a noise. Spam is the sfxMinGap gate's job, not this one's.
	-- NOT FOR A NEIGHBOUR'S WEIGHT ARRIVING, AND NOT FOR A SQUEEZE BUILDING. Clay and salt redraw
	-- cells nobody stepped on (see DISPLACEMENT in DeformationService), and a Needoh announces how far
	-- it is squeezed while you stand still; none of those is a footstep, so no sound and no lens. A
	-- foot standing still on clay or salt ("creep") is still pressing, so it sounds, but it does not
	-- flick the lens.
	local cause = payload.cause
	local mine = payload.who == Players.LocalPlayer
	-- A KEYPAD PLAYS NOTES. Major pentatonic, so any run of them sounds as if it meant to: a row
	-- further along the route is a step up the scale, and a column further out from the centre lane
	-- is another. Walking the lane plays a rising run; weaving plays a tune.
	--
	-- AND EACH SWITCH HAS ITS OWN ELECTRIC SOUND (audio/buttons, synthesised by gen_button_sfx.py): the
	-- clicky zap, the linear vwomp, the tactile double pulse, a rising pew on release, and a combo or a
	-- circuit replacing the click that made it. Those recordings rise GENTLY along the route instead
	-- of up a scale -- a zap pitched a sixth up is a different zap. Until they are uploaded the keypad
	-- keeps the keyboard's thock, on the scale.
	local note: number? = nil
	local event: string? = nil
	local loud = payload.combo ~= nil
	if material == "Buttons" and typeof(payload.col) == "number" and typeof(payload.row) == "number" then
		local grid = tile.Parent
		local cols = if grid then grid:GetAttribute("GridCols") else nil
		local centre = ((if typeof(cols) == "number" then cols else 5) + 1) / 2
		local degree = (payload.row - 1) + math.floor(math.abs(payload.col - centre) + 0.5)
		local switch = tile:GetAttribute("Switch")
		-- What the press did (see KEYPADS in DeformationService): charges a violet press stored or a clicky
		-- one spent, or the level a pink spring is at.
		local stored = if typeof(payload.charge) == "number" then payload.charge else nil
		event = "buttonClick"
		if payload.combo == "circuit" then
			event = "buttonCircuit"
		elseif payload.combo == "combo" then
			event = "buttonCombo"
		elseif switch == "clicky" and stored then
			-- A DISCHARGE, the capacitor going out through a lane button, is a combo's zap, and never skipped.
			event = "buttonCombo"
			loud = true
		elseif switch == "tactile" then
			event = "buttonTactile"
		elseif switch == "linear" then
			event = "buttonLinear"
		end
		if AudioService.hasTakes("buttonClick") then
			note = 1 + 0.035 * degree
		else
			local scale = { 0, 2, 4, 7, 9 }
			note = 0.72 * 2 ^ ((scale[degree % 5 + 1] + 12 * (degree // 5)) / 12)
		end
		-- A CHARGE OR A SPRING WINDS UP: every charge stored and every level of a bounce plays a step higher.
		if stored and switch ~= "clicky" and note then
			note = note * (1 + 0.07 * (stored - 1))
		end
	end
	local footfall = cause == nil or cause == "step" or cause == "creep"
	if material and ((state == "deformed" and footfall) or state == "exhausted") then
		AudioService.playSfx(material, tile, mine, { pitch = note, event = event, force = loud })
		-- The screen, alongside the sound and for the same reasons: it sits ABOVE the
		-- repeat guard so re-crossing your own footprints still registers, and it is gated
		-- on `mine` so nobody else's steps tint your view.
		if cause == nil or cause == "step" or state == "exhausted" then
			ScreenEffects.onStep(material, mine)
		end
	elseif note and state == "decaying" then
		-- THE RELEASE CLICKS TOO, quieter: a spring coming back is not a press. On the thock it is a fifth
		-- higher; the recorded release already rises. A LAUNCH off a pink spring is the same release at
		-- full voice, pitched by its level, and it is never skipped.
		local recorded = AudioService.hasTakes("buttonRelease")
		local launch = cause == "spring"
		AudioService.playSfx(material, tile, mine, {
			pitch = if recorded then note else note * 1.5,
			gain = if launch then 1.3 elseif recorded then 0.9 else 0.45,
			event = "buttonRelease",
			force = launch,
		})
	end

	-- ICE REPEATS TOO, for a third reason. It is not made of discrete things like the
	-- other two; it fails in STAGES, and the second step on a cell arrives as "deformed"
	-- exactly like the first did. Deduplicated away, the crack that is supposed to widen
	-- under you never widened, and the platform gave out on step three with no more
	-- warning than it had shown on step one.
	-- LEGO AND CHOCOLATE JOIN THE LIST, and for ice's reason rather than bubble wrap's:
	-- both fail in visible STAGES, so a second step on the same cell is a different picture
	-- from the first and must not be deduplicated into it. A brick working loose and a bar
	-- going soft are both warnings, and a warning you only get once is not one.
	-- CLAY JOINS for salt's reason: both redraw a cell whose state has not changed, because the
	-- material pushed into it has. And the NEEDOH, because a squeeze deepening under a player standing
	-- still is a new picture of a cell that is still "deformed".
	local staged = material == "Ice" or material == "Lego" or material == "Chocolate"
		or material == "Salt" or material == "Lava" or material == "Snow" or material == "Clay"
		or material == "Needoh" or material == "Charcoal" or material == "Oobleck"
	if isRepeat and material ~= "BubbleWrap" and material ~= "CreamyKeyboard" and not staged then
		return
	end
	lastState[tile] = state

	local effect = material and Effects[material]
	if effect then
		if not isRepeat then
			cancelTweens(tile)
		end
		effect({
			tile = tile,
			state = state,
			material = material,
			popCount = payload.popCount,
			layer = payload.layer,
			stepCount = payload.stepCount,
			depth = payload.depth,
			push = payload.push,
			lean = payload.lean,
			cause = payload.cause,
			combo = payload.combo,
			charge = payload.charge,
			fire = payload.fire,
			wade = payload.wade,
			origin = payload.origin,
			mine = payload.who == Players.LocalPlayer,
			who = payload.who,
		})
	else
		-- No material (or an unknown one): plain settle, nothing decorative.
		cancelTweens(tile)
		settleTile(tile, 0.2)
	end

end

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local DeformationUpdate = RemoteEvents:WaitForChild("DeformationUpdate")
DeformationUpdate.OnClientEvent:Connect(DeformationRenderer.onDeformationUpdate)

return DeformationRenderer
