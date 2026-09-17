--!strict
-- ServerScriptService/ChunkBuilder.server.lua
-- ONE-TIME BOOTSTRAP SCRIPT. Procedurally constructs all 13 prototype chunk
-- Models: geometry, sub-region grids, per-material appearance, corner bevels.
--
-- NOTE: SKIPS any chunk already present in ServerStorage/ChunkTemplates. After
-- changing anything in here you MUST delete the children of
-- ServerStorage.ChunkTemplates and ReplicatedStorage.Assets.Chunks, or the old
-- geometry stays and none of your changes appear.
--
-- === Construction model ===
-- Every platform is two layers:
--   1. a base slab, SLAB_THICKNESS thick, opaque and matte, which is what gives
--      the platform visible mass from the side;
--   2. a top surface. On material platforms that surface is the sub-region tile
--      grid (deformable, collidable, touch-sensing). On stable platforms it is a
--      single inset cap plate with no triggers.
-- The tiles are COLLIDABLE, so when one sinks the player physically rides it
-- down. The slab sits TILE_THICKNESS below the tile tops, so a fully sunk tile
-- still leaves solid floor underneath and nobody falls through.
--
-- === Coordinate convention ===
-- Chunks are authored with their entry edge at local Z = 0 and grow along +Z.
-- Each model publishes EntryZ / EntrySurfaceY / Rise / Length attributes, and
-- ChunkService aligns on those rather than guessing from a bounding box, which
-- is what keeps the sloped and stepped chunks seam-free against flat ones.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SubRegionGrid = require(Shared:WaitForChild("SubRegionGrid"))
local ChunkDefinitions = require(Shared:WaitForChild("ChunkDefinitions"))
local MaterialAppearance = require(Shared:WaitForChild("MaterialAppearance"))
local MaterialConfig = require(Shared:WaitForChild("MaterialConfig"))
local PlanShapes = require(Shared:WaitForChild("PlanShapes"))

-- === Scale ===
-- DEVIATION FROM GDD v1.1: the doc's chunk sizes (6x4 to 12x4 studs) are about
-- a quarter of usable scale for a Roblox character, and they put the long axis
-- across the path instead of along it, so a 12-slot level came to 48 studs of
-- travel. These numbers keep the GDD's proportions and material layout but put
-- travel along Z and roughly quadruple the area.
local PATH_WIDTH = 16 -- lateral, X
local SLAB_THICKNESS = 4
local TILE_THICKNESS = 0.9
local CAP_THICKNESS = 0.9
local CAP_INSET = 0.6 -- stable cap plate is inset so the slab edge reads

-- Default JumpPower 50 against gravity 196.2 gives ~6.4 studs of height and
-- ~8.2 studs of horizontal reach at WalkSpeed 16. Gaps stay under that with
-- margin; step rises stay at 2 so they are walkable without jumping at all.
local GAP_LENGTH = 6
local STEP_RISE = 2
local RAMP_RISE = 6
local RAMP_RUN = 24

local SURFACE_Y = SLAB_THICKNESS / 2 + TILE_THICKNESS -- slab centre 0 -> walkable top

-- Nominal size the Blender tile meshes are authored at, in studs. Must match TILE
-- in blender/gen_tile_meshes.py or every mesh comes in mis-scaled.
local TILE_AUTHORED = 3.2

-- How far a boundary tile mesh is pushed past the slab edge so its drips hang in
-- open air instead of inside the slab. The drip lobes sit within roughly 0.7 studs
-- of the authored outer edge, so this needs to exceed that to expose them.
local BOUNDARY_OVERHANG = 0.9

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local templatesFolder = ensureFolder(ServerStorage, "ChunkTemplates")
local assetsFolder = ensureFolder(ReplicatedStorage, "Assets")
local chunksFolder = ensureFolder(assetsFolder, "Chunks")

-- Cosmetic corner bevels: four 45-degree wedges at the slab corners. Not a true
-- fillet (parts cannot round without a mesh asset) but at play-camera distance
-- it softens the silhouette, which is what the pastel/rounded direction wants.
local function addCornerBevels(slab: BasePart, materialName: string?)
	local halfX, halfZ = slab.Size.X / 2, slab.Size.Z / 2
	local bevel = math.min(1.4, halfX * 0.25, halfZ * 0.25)
	if bevel <= 0.1 then
		return
	end
	local corners = {
		{ x = -halfX, z = -halfZ, rot = 0 },
		{ x = halfX, z = -halfZ, rot = 90 },
		{ x = halfX, z = halfZ, rot = 180 },
		{ x = -halfX, z = halfZ, rot = 270 },
	}
	for i, corner in ipairs(corners) do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "CornerBevel" .. i
		wedge.Size = Vector3.new(bevel, slab.Size.Y, bevel)
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.CanTouch = false
		wedge.CFrame = slab.CFrame
			* CFrame.new(corner.x - math.sign(corner.x) * bevel / 2, 0, corner.z - math.sign(corner.z) * bevel / 2)
			* CFrame.Angles(0, math.rad(corner.rot), 0)
		MaterialAppearance.applyBase(wedge, materialName)
		wedge.Parent = slab
	end
end

-- === Tile mesh visuals ===
--
-- Optional. Meshes are cloned from ReplicatedStorage/Assets/TileMeshes, which the
-- Blender exports are imported into by hand. If a mesh is missing the tile keeps
-- its plain Part look, so the game runs identically before any asset exists and
-- degrades one material at a time rather than all at once.
--
-- MeshPart.MeshId cannot be assigned at runtime, which is why these are cloned
-- from pre-imported templates instead of built with Instance.new.
--
-- Meshes are visual only: CanCollide is false and the Part tile underneath stays
-- the collider, trigger and deformation target. That matters because the honey and
-- slime boundary tiles hang drips 2 studs below their surface, and any box collider
-- fitted to that would be solid invisible floor outside the platform.
local MESH_FOLDER = "TileMeshes"

-- Materials whose tiles must form one unbroken surface. Their meshes are authored
-- edge-matched (shared borders at a fixed height, meniscus only on the platform
-- boundary), which only works if the tiles physically touch.
--
-- Bubble wrap was briefly listed here, to close the seam so the tiles themselves could
-- act as the sheet. That is obsolete: it has a skinned rig now, so its tiles are
-- invisible sensors and the sheet is the mesh. Adding it back would do nothing except
-- make taperGuard warn about a taper that is genuinely fine.
-- Needoh joins these: a bag of dough sinks under you the whole time you stand on it, it
-- does not give way in steps. The discrete materials are the ones that BREAK -- ice, butter
-- wax, bubble wrap -- and nothing in a sealed toy breaks.
local CONTINUOUS: { [string]: boolean } = { Honey = true, Slime = true, Soap = true, JelloSoda = true, Needoh = true, ButterStick = true, LavaKeys = true }

-- Of those, the ones that hang something off the platform edge. Kept SEPARATE from
-- CONTINUOUS because soap is edge-matched but solid: it wants the Interior/Edge/Corner
-- variants so a platform reads as one bar with a rounded outline, and it wants no
-- overhang at all, because the overhang exists purely to swing drips clear of the slab.
-- Applying it to soap pushes every boundary cell a stud outward for nothing and breaks
-- the outline it was authored to produce.
local DRIPPING: { [string]: boolean } = { Honey = true, Slime = true }

-- === Granular materials ===
--
-- Soap is not a surface with an effect on it, it is a PRESSED BAR OF SMALL CUBES, and
-- it is built that way: every cell carries a GRANULE_DIV x GRANULE_DIV block of little
-- anchored cubes instead of one tile mesh. Standing on it breaks cubes off, they fall
-- as real physics debris you can kick out of the way, and when enough have gone the
-- cell stops being floor and you drop through the hole they left.
--
-- Two earlier attempts failed for the same underlying reason. A tile mesh and then a
-- skinned rig were both ONE piece of geometry per cell, so the only failure they could
-- express was the whole cell vanishing at once -- and a rig could not even do that,
-- because skinning stretches rather than breaks. Crumbling needs the pieces to exist
-- before they break off.
--
-- THE SLAB UNDER A GRANULAR PLATFORM IS NOT FLOOR. This is the part that made every
-- previous version pointless: every platform is a 4-stud slab with thin tiles on top,
-- so a dissolved soap cell dropped you 0.9 studs onto the slab and stopped you dead.
-- The hole was real in the tiles and closed underneath. For soap the slab is kept as
-- the anchor object the tiles hang off, and made invisible and non-colliding.
local GRANULAR: { [string]: boolean } = { Soap = true }

-- === Shelled materials ===
--
-- Butter-wax is a stick of butter under a WAX COATING, and the platform is built as
-- both: the tile is the butter body, and a layer of thin plates on top of it is the
-- shell. At rest the plates sit flush and it reads as one smooth surface. Stepping on
-- it cracks the shell -- the plates tilt and slide apart -- and the gaps between them
-- expose the butter underneath, which is a different colour and sits lower.
--
-- This exists because the crack had nowhere to get DEPTH from. Drawn on a SurfaceGui
-- it is unlit and reads as a sticker; built out of parts laid on the surface it reads
-- as a stick lying on the floor (both tried, both rejected). A gap between two real
-- plates is neither: it is an absence, lit by whatever is beneath it.
--
-- BOTH LAYERS COLLIDE. The plates are what you stand on and the butter is the floor
-- under them, so cracking never opens a hole -- unlike soap, wax does not drop you
-- through, it lets you sink.

-- HOW THE COATING IS FINISHED, per material. MaterialAppearance.apply runs first and
-- these three values overwrite what it set, so a material missing from here silently
-- wears wax's finish -- which is what ice did: a white wash at 0.62 toward white, barely
-- translucent, and almost no reflectance. That is butter with a cold name on it.
--
-- KEEP TRANSPARENCY LOWER THAN SEEMS RIGHT. The coating WRAPS the block, so a line of
-- sight crosses several of its faces at once. Wax at 0.45 let the number of layers you
-- happened to be looking through set the apparent colour -- greyer where the front band,
-- the back band and the top plate stacked up, paler at the ends where fewer did -- and
-- that reads as the coating being present in some places and missing in others, when it
-- was complete throughout and only the layering varied. Ice can afford 0.45 because its
-- own texture is high-contrast enough to survive the mottling, and because seeing through
-- to no floor is the entire point of the material.
--
-- `whiten` is the one that matters. Wax needs it because a wax bloom really is the butter
-- colour drained toward white. Ice must NOT have it: the pale parts of ice are the
-- fractures, and those already come from Ice_Color, so whitening the whole sheet erases
-- exactly the contrast the texture was drawn to provide.
local SHELL_FINISH: { [string]: { whiten: number, transparency: number, reflectance: number } } = {
	-- The wax film: butter taken most of the way to white, translucent enough that the
	-- butter reads THROUGH it. Opaque, the platform is a white slab on something yellow.
	ButterWax = { whiten = 0.62, transparency = 0.3, reflectance = 0.10 },
	-- A frozen sheet with water under it. Clearer than the wax and far more reflective,
	-- because ice reads by what it bounces back rather than by its own colour -- and the
	-- player has to be able to see that there is no floor beneath it.
	Ice = { whiten = 0.15, transparency = 0.45, reflectance = 0.34 },
}

local SHELL_THICKNESS = 0.3  -- how deep the wax coating is

-- One fractured coating per platform size. The shard pattern lives in the MESH, not
-- here: gen_wax_shell.py cuts it and names a bone per shard.
type WaxSpec = { sizeX: number, sizeZ: number, surfaceOffset: number, mesh: string }

local WAX_SHELLS: { [string]: { WaxSpec } } = {
	ButterWax = {
		{ sizeX = 16, sizeZ = 8, surfaceOffset = 2.385, mesh = "Wax_Shell_16x8_A" },
		{ sizeX = 16, sizeZ = 8, surfaceOffset = 2.385, mesh = "Wax_Shell_16x8_B" },
		{ sizeX = 12, sizeZ = 10, surfaceOffset = 2.385, mesh = "Wax_Shell_12x10_A" },
		{ sizeX = 12, sizeZ = 10, surfaceOffset = 2.385, mesh = "Wax_Shell_12x10_B" },
	},
	-- THE STICKS ARE WRAPPED, which they were not and should have been from the start: a
	-- stick of butter that arrives bare is a stick somebody has already unwrapped.
	--
	-- A FLAT shell over a ridged surface is right rather than a compromise. One wrapper
	-- spans all three sticks, the tops are flat and level end to end so the plates lie on
	-- them exactly as they lie on a flat butter slab, and the two grooves are simply
	-- bridged -- which is what a sheet of paper does over three bars.
	-- DRAPED, NOT LAID FLAT. The first attempt reused the flat 16x12 plates on the grounds
	-- that a wrapper spans three sticks, and in the game that was simply a white lid: a flat
	-- sheet across three ridges bridges them completely and the chunk underneath disappeared.
	--
	-- These are the same shards, the same rig and the same cracking, generated with the stick
	-- height field as a relief so every plate sits a constant thickness above the butter and
	-- dips into both grooves. gen_wax_shell_sticks.py, and the offset below is measured off
	-- the result rather than carried over from the flat one.
	ButterStick = {
		-- 2.385, not the 3.860 this briefly carried. That larger figure was measured off a
		-- shell whose UNDERSIDE plate had also been draped -- the bug that hung a tangle of
		-- shards below the butter. With the underside flat again the bounding box is back to
		-- the same shape every other shell has, and so is the offset.
		{ sizeX = 16, sizeZ = 12, surfaceOffset = 2.385, mesh = "Wax_Shell_Sticks_16x12_A" },
		{ sizeX = 16, sizeZ = 12, surfaceOffset = 2.385, mesh = "Wax_Shell_Sticks_16x12_B" },
	},
	-- ICE REUSES THE WAX PLATES, and that is the point rather than a shortcut.
	--
	-- gen_wax_shell.py cuts an irregular fractured coating with a bone per shard. That IS
	-- a sheet of cracking ice -- the shard pattern has nothing butter-specific in it, and
	-- the difference between the two materials is colour, transparency, friction and
	-- sound, none of which live in the mesh. Reusing it means ice needs no new Blender
	-- work and no new imports at all.
	-- ITS OWN MESH NAMES, exported separately by blender/gen_ice_jello.py.
	--
	-- The geometry is byte-for-byte what gen_wax_shell.py builds -- ice reuses the wax
	-- plates because a fractured coating with a bone per shard IS a sheet of cracking ice.
	-- But a SurfaceAppearance is a child of the template MeshPart and both materials clone
	-- the same template, so sharing a mesh NAME would mean sharing a texture: ice would
	-- wear wax's crazing or wax would wear ice's, with no third option.
	--
	-- Roblox reads a MeshPart's name from the object inside the FBX rather than from the
	-- filename, so gen_ice_jello.py renames the object, its mesh data and its rig before
	-- exporting. Re-run it whenever gen_wax_shell.py changes: these are copies, and a copy
	-- that is not regenerated has silently diverged.
	Ice = {
		{ sizeX = 16, sizeZ = 8, surfaceOffset = 2.385, mesh = "Ice_Shell_16x8_A" },
		{ sizeX = 16, sizeZ = 8, surfaceOffset = 2.385, mesh = "Ice_Shell_16x8_B" },
		{ sizeX = 12, sizeZ = 10, surfaceOffset = 2.385, mesh = "Ice_Shell_12x10_A" },
		{ sizeX = 12, sizeZ = 10, surfaceOffset = 2.385, mesh = "Ice_Shell_12x10_B" },
	},
}

-- DERIVED, never hand-written. This gates attachShell, and for a while it was its own
-- literal listing ButterWax alone. Ice got its plates generated, exported, imported and
-- registered in WAX_SHELLS above, and still came out as a bare slab, because the one
-- table that decides whether a coating is attached at all had never heard of it. Two
-- tables holding the same fact will disagree eventually; reading it off the mesh table
-- means "has shells authored" and "wears a shell" cannot come apart again.
local SHELLED: { [string]: boolean } = {}
for shelledMaterial in pairs(WAX_SHELLS) do
	SHELLED[shelledMaterial] = true
end

local GRANULE_DIV = 3        -- cubes per cell per axis
local GRANULE_GAP = 0.05     -- so individual cubes read as separate at rest
-- Chosen so a granule comes out roughly CUBIC against its own footprint, which runs
-- 0.78 to 1.12 studs across the sizes soap actually appears at. Taller than that and
-- the bar reads as a row of blocks standing on end rather than as pressed cubes.
local GRANULE_DEPTH = 1.15   -- height of ONE cube

-- Depth comes from stacking, not from taller cubes. Making the cubes deep enough to
-- give the bar body would make them standing blocks, and the whole point is that they
-- read as cubes. Two layers also make the crush legible: breaking the top exposes the
-- layer under it, so you crash INTO the bar instead of straight through a shell.
local GRANULE_LAYERS = 2

-- How far the OUTERMOST ring of top-layer cubes sits below the rest of the surface.
--
-- This is the stronger of the two soap-bar cues by a wide margin. Plan rounding barely
-- registers at this cube size -- a 2-stud radius on a 14-wide bar only clips the four
-- corner cubes -- but rolling the rim off in profile is visible from every angle you
-- actually play at, and it is what stops the bar ending in a vertical wall like a slab.
--
-- Kept small because the entry and exit rims are jump targets: 0.35 studs is a step you
-- do not feel landing, where a proper dome would drop the edge far enough to catch you.
local GRANULE_RIM_DROP = 0.35

-- THERE IS ONE CUBE SIZE AND IT DOES NOT VARY.
--
-- A `grain` system lived here briefly: per-chunk profiles that changed how many pieces
-- filled a cell, from 4 up to 25. It was a mistake twice over.
--
-- It was SLOW. The finest profile put 25 pieces in a cell across four layers -- 100 parts
-- per cell, 2576 on one hexagon, against 552 for the heaviest platform in the rest of the
-- game. That is visible lag on sight, and nothing in a table reading `div = 5, layers = 4`
-- warns you it multiplies out to two thousand parts.
--
-- It was also the WRONG KNOB. Soap's cube size is the material: a bar of soap has the grain
-- it has, and platforms of the same substance with different-sized pieces read as different
-- substances rather than as variety. Shape is the axis worth varying, and shape is free.
--
-- The budget below is what stops the first half happening again. check_plan_shapes
-- multiplies the cell grid, the layer count and the outline's fill for every granular chunk
-- and fails over this figure, which sits just above the heaviest platform that ever shipped.
local GRANULE_BUDGET = 600

-- WHICH MATERIALS ARE BUILT OUT OF LOOSE PIECES rather than out of one surface.
--
-- Soap is granular in the same spirit but not the same way: its cubes are a field of many
-- per cell, and losing one is losing a crumb. A lego cell is ONE brick, and losing it is
-- losing the floor.
local BRICKED: { [string]: boolean } = { Lego = true }

-- MATERIALS THAT SHED SOMETHING WHILE NOBODY IS TOUCHING THEM.
--
-- Everything else in this game is event-driven: a surface answers a footfall and is
-- otherwise still. These two are not still, and that is the point of them. Chocolate is
-- warm enough to run, and ice is warm enough to melt, and both facts are true before the
-- player arrives -- so a platform that only drips when stepped on would be telling you the
-- drip is about you rather than about the temperature.
--
-- Attached to the slab at BUILD time rather than driven by the renderer, because it is a
-- property of the platform rather than of an interaction, and because a chunk that is
-- dripping before you reach it is doing the one job ambient detail has: telling you what
-- you are walking towards.
--
-- FIVE EMITTERS, NOT ONE. The first version put a single emitter on the underside, which
-- was the right place for a drop to FALL from and the wrong place for the effect to read:
-- from a player's eye level the underside of a platform is barely visible, so a block that
-- was visibly melting from below looked completely dry from where anyone stood. The sides
-- are what you actually see, so the sides are where most of this now happens -- runnels
-- creeping down the four faces, with the underside keeping the drops that let go.
type AmbientSpec = {
	colour: Color3,
	under: number,     -- drops per second leaving the underside
	side: number,      -- and creeping down each of the four sides
	mist: number,      -- haze clinging to the block, 0 for none
	size: number,
	life: NumberRange,
}

local AMBIENT: { [string]: AmbientSpec } = {
	-- Slow and heavy. Chocolate at this temperature runs rather than drips, so the drops
	-- are big, few and unhurried -- a fast spatter would read as rain. The mist is what
	-- sells "warm": a faint sheen hanging at the surface, the way a bar sweats.
	Chocolate = {
		colour = Color3.fromRGB(78, 44, 24),
		under = 2.6,
		side = 3.4,
		mist = 1.4,
		size = 0.34,
		life = NumberRange.new(1.4, 2.2),
	},
	-- LAVA DOES NOT DRIP, IT RISES. Every other row here is meltwater or syrup running down
	-- a face; this is the only one where the ambient goes UP, because what comes off molten
	-- rock is heat and the ash it carries. The sign on `mist` acceleration below is what
	-- makes the difference, and it is the whole reason this row is worth having: the hottest
	-- thing in the game was the only chunk that announced nothing before you reached it.
	Lava = {
		colour = Color3.fromRGB(255, 158, 68),
		-- The drops are EMBERS falling back after being carried up, so there are few of them
		-- and they are bright. A heavy drip would read as something leaking.
		under = 1.2,
		side = 2.0,
		mist = 4.5,
		size = 0.20,
		life = NumberRange.new(1.2, 2.0),
	},
	-- Charcoal sheds without being touched. A lump of it dusts everything near it, and that
	-- is a property of the material rather than of walking on it -- which is exactly what
	-- ambient is for.
	Charcoal = {
		colour = Color3.fromRGB(46, 43, 42),
		under = 2.2,
		side = 2.8,
		mist = 2.0,
		size = 0.13,
		life = NumberRange.new(1.0, 1.8),
	},
	-- A cloud is only ever in the act of dispersing. The mistiest row by a distance and the
	-- only one whose falling half is almost nothing: vapour does not drip.
	Cloud = {
		colour = Color3.fromRGB(250, 252, 255),
		under = 0.8,
		side = 1.4,
		mist = 6.0,
		size = 0.22,
		life = NumberRange.new(1.6, 2.6),
	},
	-- The heaviest drip in the game, and the only one where it is the POINT rather than a
	-- detail. A snow chunk should look like it is going whether you are on it or not, so it
	-- runs faster than the ice beside it and mists harder.
	Snow = {
		colour = Color3.fromRGB(226, 240, 252),
		under = 6.0,
		side = 7.5,
		mist = 3.6,
		size = 0.15,
		life = NumberRange.new(0.8, 1.4),
	},
	-- Faster, smaller and mistier, because meltwater is thin where chocolate is thick and
	-- because cold air over a warm room is the one place real fog forms. This is the detail
	-- that says the ice is ABOVE freezing and therefore already failing, which is the whole
	-- premise of the chunk.
	Ice = {
		colour = Color3.fromRGB(196, 226, 245),
		under = 4.4,
		side = 5.2,
		mist = 3.0,
		size = 0.16,
		life = NumberRange.new(0.9, 1.5),
	},
}

local function dripEmitter(spec: AmbientSpec, rate: number, sideways: boolean): ParticleEmitter
	local drips = Instance.new("ParticleEmitter")
	drips.Name = "Drips"
	drips.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	drips.Color = ColorSequence.new(spec.colour)
	drips.Size = NumberSequence.new(spec.size)
	drips.Lifetime = spec.life
	drips.Rate = rate
	-- Emitted with almost no speed of their own and then pulled down: a drop leaves a
	-- surface at rest and is accelerated by gravity, and giving it launch speed is what
	-- makes CG droplets look sprayed.
	--
	-- A RUNNEL IS NOT A DROP. On the sides the gravity is gentler and the spread narrower,
	-- so the particle creeps down the face instead of falling clear of it -- which is what
	-- separates something running down a wall from something dripping off a ledge.
	drips.Speed = NumberRange.new(0, if sideways then 0.2 else 0.4)
	drips.Acceleration = Vector3.new(0, if sideways then -7 else -34, 0)
	drips.SpreadAngle = if sideways then Vector2.new(4, 4) else Vector2.new(12, 12)
	drips.LightEmission = 0.1
	return drips
end

local function attachAmbient(slab: BasePart, materialName: string)
	local spec = AMBIENT[materialName]
	if not spec then
		return
	end

	-- The underside, where a drop that has run to an edge finally lets go.
	local under = Instance.new("Attachment")
	under.Name = "DripOrigin"
	under.Position = Vector3.new(0, -slab.Size.Y / 2, 0)
	under.Parent = slab
	local falling = dripEmitter(spec, spec.under, false)
	falling.EmissionDirection = Enum.NormalId.Bottom
	falling.Parent = under

	-- And the four faces, which is what anyone standing on the level can actually see.
	local faces = {
		{ Vector3.new(slab.Size.X / 2, 0, 0), Enum.NormalId.Right },
		{ Vector3.new(-slab.Size.X / 2, 0, 0), Enum.NormalId.Left },
		{ Vector3.new(0, 0, slab.Size.Z / 2), Enum.NormalId.Front },
		{ Vector3.new(0, 0, -slab.Size.Z / 2), Enum.NormalId.Back },
	}
	for index, face in ipairs(faces) do
		local at = Instance.new("Attachment")
		at.Name = "RunnelOrigin" .. index
		-- Slightly above centre: a runnel starts near the top edge, where the melt comes
		-- over, and travels down. Starting at mid-height would have them appearing out of
		-- nothing in the middle of a wall.
		at.Position = (face[1] :: Vector3) + Vector3.new(0, slab.Size.Y * 0.28, 0)
		at.Parent = slab
		local runnel = dripEmitter(spec, spec.side, true)
		runnel.EmissionDirection = face[2] :: Enum.NormalId
		runnel.Parent = at
	end

	if spec.mist <= 0 then
		return
	end

	-- The haze that clings to the block itself. Wide, slow, and nearly transparent: this
	-- is not meant to be seen as particles, only to stop the surface reading bone dry.
	local hazeAt = Instance.new("Attachment")
	hazeAt.Name = "MistOrigin"
	hazeAt.Position = Vector3.new(0, slab.Size.Y * 0.35, 0)
	hazeAt.Parent = slab
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "Mist"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(spec.colour:Lerp(Color3.new(1, 1, 1), 0.75))
	mist.Size = NumberSequence.new(3.2)
	mist.Lifetime = NumberRange.new(1.6, 2.8)
	mist.Rate = spec.mist
	mist.Speed = NumberRange.new(0.2, 0.9)
	-- Ice's haze sinks, chocolate's rises. Cold air off a melting block falls down the
	-- sides; warm air off a soft one lifts, and getting that backwards is the single
	-- clearest tell that a fog effect was not thought about.
	-- WHICH WAY THE HAZE GOES, and it is per material rather than a constant because the two
	-- directions mean opposite things. Cold air off a melting block SINKS down the sides;
	-- warm air off a soft or hot one LIFTS. Getting it backwards is the clearest sign a fog
	-- effect was not thought about.
	local sinks = materialName == "Ice" or materialName == "Snow"
	local lift = if materialName == "Lava" then 3.5 elseif sinks then -1.2 else 0.8
	mist.Acceleration = Vector3.new(0, lift, 0)
	mist.SpreadAngle = Vector2.new(70, 70)
	mist.Transparency = NumberSequence.new(0.82)
	mist.LightEmission = 0.25
	mist.Parent = hazeAt
end

-- MATERIALS WHOSE MOVING PART IS A RIGID CAP sitting in a well cut into the mesh.
--
-- Only the buttons, and for the same reason lego is built out of parts: a cap modelled into
-- a skinned mesh cannot be pressed. Moving a bone drags every vertex within a cell and a
-- quarter along a smooth falloff, so the plate flexes and the neighbouring buttons sag with
-- it -- and a button is the one object in this game that MUST move rigidly, because the
-- whole appeal is a hard cap on a spring travelling straight down and stopping dead.
--
-- So the mesh carries the housings and nothing else, and this drops a real Part into each
-- one. The renderer moves that Part; the plate never moves at all.
local CAPPED: { [string]: boolean } = { Buttons = true }

local CAP_R = 0.36        -- of the cell's short side, and inside the well the mesh cut
local CAP_H = 0.46        -- how tall the cap is
-- HOW FAR IT STANDS PROUD of the plate. This is the number that makes a button look
-- pressable: flush with its housing it reads as a disc set into a panel, and there is
-- nothing to suggest it moves. Its travel (Button.drop in the renderer) takes the cap down
-- to about flush with its bezel, where the lit core still shows.
local CAP_STAND = 0.26

-- ===== AN ARCADE BUTTON, NOT A DISC =====
--
-- Every button was one violet cylinder, the plate's own colour lightened a little, sitting in a
-- well of the same violet: from any distance a purple slab with paler dots on it. A button you
-- want to press is three things. A dark BEZEL that frames it; a glossy, see-through CAP; and a lit
-- CORE inside the cap, so the button glows from within and a pressed one can flash. The bezel
-- stays put. The cap and the core travel together.
local BEZEL_LIP = 0.15    -- of the cap's radius: how far the bezel ring shows beyond the cap
local BEZEL_H = 0.14
local BEZEL_SINK = 0.10   -- how far the bezel sits down into its well
local BEZEL = Color3.fromRGB(26, 20, 38)
local CORE_R = 0.58       -- of the cap's radius
local CORE_H = 0.30       -- studs; its top sits just under the cap's
local CORE_TOP = 0.04     -- how far under the cap's top face the core's top sits

-- THREE SWITCHES, the way a switch tester has them. What each one does to your feet is
-- `switchSpeeds` in MaterialConfig; what each one looks like is here. No red anywhere, which was
-- asked for, and violet stays the family colour.
local SWITCH_LOOK: { [string]: { cap: Color3, core: Color3 } } = {
	clicky = { cap = Color3.fromRGB(156, 238, 255), core = Color3.fromRGB(56, 222, 255) },
	linear = { cap = Color3.fromRGB(204, 176, 255), core = Color3.fromRGB(146, 92, 255) },
	tactile = { cap = Color3.fromRGB(255, 184, 226), core = Color3.fromRGB(255, 92, 192) },
}

-- WHICH SWITCH A CELL CARRIES. Symmetric about the keypad's centre line, and a different route
-- on each keypad:
--   the pad and the dome run a clicky lane straight down the middle -- over the summit, on the
--   dome -- with linear either side and tactile on the outside columns;
--   the dense keypad BRAIDS its lane: on alternate rows the clicky cells step out either side of
--   centre, so walking straight down the middle collects half of them and weaving collects all.
local function switchFor(form: string?, col: number, row: number, cols: number): string
	local centre = (cols + 1) / 2
	local off = math.abs(col - centre)
	if off >= centre - 1 then
		return "tactile"
	end
	local lane = if form == "dense" and row % 2 == 1 then off >= 1 and off < 2 else off < 1
	return if lane then "clicky" else "linear"
end

-- A CELL CAN CARRY MORE THAN ONE BUTTON, and `div` is the difference between one keypad and
-- another: div x div buttons per cell, on the same sub-lattice the mesh cuts its wells on. The two
-- agree because they are computed from the same numbers -- cell size over div -- rather than
-- because someone kept two tables in step.
--
-- SUBDIVIDING THE CELL rather than laying an independent pitch over the plate is what makes the
-- pattern come out symmetric about the platform's centre and leaves no half button at any edge.
--
-- Every cap is named "Cap" and every core "CapLed". Duplicate names are legal in Roblox and the
-- renderer collects them by name, so a cell with four buttons presses all four together -- which
-- is right: what goes down is what your foot is on, and your foot is on a cell. The cell's switch
-- is written on the tile as `Switch`, for DeformationService and the renderer both.
local function attachCap(tile: BasePart, slab: BasePart, div: number, col: number, row: number, cols: number)
	local pitchX, pitchZ = tile.Size.X / div, tile.Size.Z / div
	local radius = math.min(pitchX, pitchZ) * CAP_R
	local switch = switchFor(slab:GetAttribute("Form") :: string?, col, row, cols)
	local look = SWITCH_LOOK[switch]
	tile:SetAttribute("Switch", switch)
	local top = tile.Size.Y / 2
	-- Cylinders point along their own X, so this stands each one on its end.
	local roll = CFrame.Angles(0, 0, math.rad(90))

	for ix = 1, div do
		for iz = 1, div do
			-- In the TILE's frame, so up is the platform's own up -- which matters on the curved
			-- parts of the spiral, where world up and platform up are not the same thing.
			local at = tile.CFrame * CFrame.new((ix - (div + 1) / 2) * pitchX, 0, (iz - (div + 1) / 2) * pitchZ)
			local lip = radius * BEZEL_LIP

			local bezel = Instance.new("Part")
			bezel.Name = "CapBezel"
			bezel.Shape = Enum.PartType.Cylinder
			bezel.Size = Vector3.new(BEZEL_H, (radius + lip) * 2, (radius + lip) * 2)
			bezel.CFrame = at * CFrame.new(0, top - BEZEL_SINK + BEZEL_H / 2, 0) * roll
			bezel.Color = BEZEL
			bezel.Material = Enum.Material.SmoothPlastic
			bezel.Reflectance = 0.22

			local cap = Instance.new("Part")
			cap.Name = "Cap"
			cap.Shape = Enum.PartType.Cylinder
			cap.Size = Vector3.new(CAP_H, radius * 2, radius * 2)
			cap.CFrame = at * CFrame.new(0, top + CAP_STAND - CAP_H / 2, 0) * roll
			cap.Color = look.cap
			cap.Material = Enum.Material.SmoothPlastic
			cap.Transparency = 0.3
			cap.Reflectance = 0.16

			local core = Instance.new("Part")
			core.Name = "CapLed"
			core.Shape = Enum.PartType.Cylinder
			core.Size = Vector3.new(CORE_H, radius * 2 * CORE_R, radius * 2 * CORE_R)
			core.CFrame = at * CFrame.new(0, top + CAP_STAND - CORE_TOP - CORE_H / 2, 0) * roll
			core.Color = look.core
			core.Material = Enum.Material.Neon
			core.Transparency = 0.3

			for _, piece in ipairs({ bezel, cap, core }) do
				piece.Anchored = true
				-- The tile's Floor is the collider, as everywhere else. A collidable cap would
				-- fight it and re-fire Touched every time one moved, which for a material that
				-- moves on every step would be constant.
				piece.CanCollide = false
				piece.CanTouch = false
				piece.CanQuery = false
				piece.CastShadow = false
				piece.TopSurface = Enum.SurfaceType.Smooth
				piece.BottomSurface = Enum.SurfaceType.Smooth
				piece.Parent = tile
			end
		end
	end
end

local BRICK_INSET = 0.05    -- the vertical seam between neighbouring cells

-- COURSES, not one tall block. A cell spans the whole depth of the platform, which is over
-- four studs, and a single part that size is a COLUMN -- lego is never one piece that tall.
-- Splitting it into courses with a groove between them puts horizontal seams down every
-- outside face, and a stack of courses with seams is the single most recognisable thing
-- about a lego wall seen from the side.
local BRICK_COURSE = 1.45   -- target height of one course; the real count is fitted below
local BRICK_GROOVE = 0.07   -- the seam between two courses

-- Real lego is a 4.8mm stud on an 8mm pitch, standing 1.8mm proud: a radius of 0.30 of the
-- pitch and a height of 0.225 of it. With two studs across a cell the pitch is half the
-- cell, so these are that ratio and not a guess. The first version had them at 0.30 studs
-- tall against a 1.6 pitch, barely half as proud as they should be, which is most of why
-- the top read as dimpled rather than studded.
local BRICK_STUD_R = 0.30   -- of the stud pitch
local BRICK_STUD_H = 0.225  -- of the stud pitch

-- ONE STACK OF BRICK COURSES PER CELL, FULL DEPTH OF THE PLATFORM.
--
-- Third arrangement, and the first two are worth recording because each was a reasonable
-- idea that the screenshots killed.
--
-- 1. Lego was a skinned mesh like everything else. A bone on a skinned mesh drags every
--    vertex within a cell and a quarter, so a brick "lifting" rippled the whole plate and
--    the platform read as rubber. A material whose entire identity is rigidity cannot be a
--    deformable surface.
-- 2. Bricks became real parts, but only the top 0.9 studs, standing on the slab. That left
--    a four-stud-thick slab of plain plastic underneath -- a solid red centre with lego
--    only on its lid, and bevelled wedges at the corners that belong on a rounded platform.
--
-- So the cell is now the whole platform through its own footprint, built as a stack: top
-- face at the walkable plane, bottom face at the underside of the slab, and the slab and
-- its bevels hidden exactly as soap's are. The platform is nothing but bricks.
--
-- EVERYTHING IS WELDED TO THE TOP COURSE. Parenting a Part to a Part does NOT put them in
-- one assembly in Roblox -- only a joint does -- so an earlier version that unanchored a
-- brick and its studs together had them fall as separate loose bodies that happened to
-- start in the same place. WeldConstraints are inert while everything is anchored and are
-- what makes the stack come away as one piece.
local function attachBrick(
	tile: BasePart,
	slab: BasePart,
	materialName: string,
	col: number,
	row: number,
	cols: number,
	rows: number
)
	-- Worked out in the SLAB's frame rather than the world's. Platforms are rotated to face
	-- along the spiral, so a brick placed by world Y would be upright while its platform
	-- was not -- and the error only shows on the curved parts of the level.
	local localTile = slab.CFrame:ToObjectSpace(tile.CFrame)
	local topLocal = localTile.Y + tile.Size.Y / 2
	local bottomLocal = -slab.Size.Y / 2
	local depth = topLocal - bottomLocal
	if depth <= 0 then
		return
	end

	-- Fitted rather than fixed, so the courses divide the depth exactly and the bottom one
	-- is not a sliver. A stack whose last course is a third the height of the others reads
	-- as a mistake, and platform depth is not guaranteed to be a round number.
	local courses = math.max(1, math.floor(depth / BRICK_COURSE + 0.5))
	local courseH = depth / courses
	local width = tile.Size.X - BRICK_INSET
	local length = tile.Size.Z - BRICK_INSET
	local studPitch = math.min(tile.Size.X, tile.Size.Z) / 2

	local top: BasePart? = nil
	local courseParts: { BasePart } = {}
	local topHalf = 0
	for index = 1, courses do
		-- Counted from the top down, so index 1 is the course you walk on.
		local centre = topLocal - courseH * (index - 0.5)
		local course = Instance.new("Part")
		course.Name = if index == 1 then "Brick" else "Course" .. index
		course.Size = Vector3.new(width, courseH - BRICK_GROOVE, length)
		course.CFrame = slab.CFrame * CFrame.new(localTile.X, centre, localTile.Z)
		course.Anchored = true
		-- The tile's Floor child is the collider, as on every other platform. Collidable
		-- courses would fight it and re-fire Touched every time one moved.
		course.CanCollide = false
		course.CanTouch = false
		course.CanQuery = false
		course.Parent = if index == 1 then tile else top
		-- Textures reach a Part through MaterialVariant, never SurfaceAppearance. Going
		-- through apply() is what writes the variant, so every course is textured on all
		-- six faces the moment LegoABS exists.
		MaterialAppearance.apply(course, materialName)

		table.insert(courseParts, course)
		if index == 1 then
			top = course
		elseif top then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = top
			weld.Part1 = course
			weld.Parent = course
		end
	end

	local brick = top
	if not brick then
		return
	end

	-- One stud, wherever it is pointing. `spin` turns the cylinder's own X axis onto the
	-- face it belongs to: none for the two X faces, a quarter turn about Y for the Z faces,
	-- a quarter turn about Z for the top.
	local function addStud(host: BasePart, offset: Vector3, spin: CFrame)
		local stud = Instance.new("Part")
		stud.Name = "Stud"
		stud.Shape = Enum.PartType.Cylinder
		stud.Size = Vector3.new(studPitch * BRICK_STUD_H, studPitch * BRICK_STUD_R * 2,
			studPitch * BRICK_STUD_R * 2)
		stud.CFrame = host.CFrame * CFrame.new(offset) * spin
		stud.Anchored = true
		stud.CanCollide = false
		stud.CanTouch = false
		stud.CanQuery = false
		stud.Parent = brick
		MaterialAppearance.apply(stud, materialName)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = host
		weld.Part1 = stud
		weld.Parent = stud
	end

	-- STUDS ON THE OUTWARD FACES TOO, on every course, not only on the lid.
	--
	-- Real bricks only have studs on top, and a platform built from them is therefore
	-- smooth-sided -- which is exactly the complaint: from anywhere but directly above it
	-- stopped reading as lego at all. Turning bricks to face outward is a real technique
	-- (builders call it studs-not-on-top) and it is what makes a lego wall look like lego
	-- from the side, so the perimeter courses wear their studs outward.
	--
	-- PERIMETER ONLY. An interior cell's sides are pressed against its neighbours, and
	-- studs there would be buried inside the platform -- invisible, and four more parts per
	-- cell for nothing.
	local halfW, halfL = width / 2, length / 2
	local faceStud = studPitch * BRICK_STUD_H / 2
	for index, course in ipairs(courseParts) do
		local courseHalf = (courseH - BRICK_GROOVE) / 2
		-- Two studs along each face, at the same pitch as the top ones.
		for _, along in ipairs({ -studPitch / 2, studPitch / 2 }) do
			if col == 1 then
				addStud(course, Vector3.new(-halfW - faceStud, 0, along), CFrame.identity)
			end
			if col == cols then
				addStud(course, Vector3.new(halfW + faceStud, 0, along), CFrame.identity)
			end
			if row == 1 then
				addStud(course, Vector3.new(along, 0, -halfL - faceStud), CFrame.Angles(0, math.rad(90), 0))
			end
			if row == rows then
				addStud(course, Vector3.new(along, 0, halfL + faceStud), CFrame.Angles(0, math.rad(90), 0))
			end
		end
		-- `courseHalf` is only needed by the top course below; referenced here so the loop
		-- reads in one piece rather than recomputing it twice.
		if index == 1 then
			topHalf = courseHalf
		end
	end

	-- Studs on the TOP COURSE ONLY. A stud is where one brick clips into the next, so a
	-- stack has them on the piece nothing sits on and nowhere else -- studs on every course
	-- would read as a shelf unit rather than as bricks pressed together.
	for ix = 0, 1 do
		for iz = 0, 1 do
			addStud(
				brick,
				Vector3.new((ix - 0.5) * studPitch, topHalf + faceStud, (iz - 0.5) * studPitch),
				CFrame.Angles(0, 0, math.rad(90))
			)
		end
	end
end

local function attachGranules(
	tile: BasePart,
	materialName: string,
	col: number,
	row: number,
	cols: number,
	rows: number,
	form: string?
)
	local size = tile.Size
	local stepX, stepZ = size.X / GRANULE_DIV, size.Z / GRANULE_DIV
	local top = size.Y / 2

	-- The whole platform's extent, reconstructed from this cell's place in the grid.
	-- A cell cannot see the platform it belongs to, but it knows its own index and the
	-- grid dimensions, and every cell of a slab is the same size -- which is enough to
	-- put each cube in platform coordinates and shape the outline across all of them.
	local platformX, platformZ = cols * size.X, rows * size.Z
	local halfX, halfZ = platformX / 2, platformZ / 2
	local outline = PlanShapes.get(form)
	local originX = (col - 1) * size.X - halfX
	local originZ = (row - 1) * size.Z - halfZ

	for layer = 1, GRANULE_LAYERS do
		for ix = 1, GRANULE_DIV do
			for iz = 1, GRANULE_DIV do
				-- THE OUTLINE, and it is now whatever the chunk asked for.
				--
				-- The comment that used to sit here said swapping this test would give a
				-- granular platform any outline with no new assets. That turned out to be
				-- exactly true: `form` names a function in PlanShapes and the same loop
				-- produces a heart, a star or a turtle. Nothing is size-locked because
				-- there is no mesh to lock -- the cubes ARE the shape.
				--
				-- Normalised to [-1, 1] over the whole platform, not this cell, so a shape
				-- spans every tile of a multi-cell slab instead of repeating per cell.
				local px = originX + (ix - 0.5) * stepX
				local pz = originZ + (iz - 0.5) * stepZ
				if not outline(px / halfX, pz / halfZ) then
					continue
				end

				-- Deterministic jitter, from the cell and cube indices rather than
				-- math.random. A bar has to look identically worn on every client, and
				-- rebuilt chunks have to match the ones already placed.
				local seed = (col * 31 + row * 17 + ix * 7 + iz * 3 + layer * 5) % 11
				local seed2 = (col * 13 + row * 29 + ix * 11 + iz * 19 + layer * 23) % 13
				-- The rim rolls off: the outer ring of the TOP layer sits lower, so the
				-- bar's edge steps down instead of ending in a vertical wall.
				local onRim = math.abs(px) > halfX - stepX * 1.01
					or math.abs(pz) > halfZ - stepZ * 1.01
				local drop = if layer == 1 and onRim then GRANULE_RIM_DROP else 0

				-- Jitter only ever makes a cube TALLER, never shorter, so a layer
				-- always reaches at least to the top of the one beneath it. Letting it
				-- shorten opens a gap between the layers that you can see through. The
				-- rim drop is added to the height for the same reason: the top comes
				-- down, the bottom stays where it was.
				local height = GRANULE_DEPTH * (1.0 + seed / 60) + drop
				local layerTop = top - (layer - 1) * GRANULE_DEPTH - drop

				local granule = Instance.new("Part")
				granule.Name = ("Granule_%d_%d_%d"):format(layer, ix, iz)
				-- Footprint varies too, not just height. Identical footprints on a
				-- regular grid read as tiling, which is the look this whole approach
				-- exists to get away from; a pressed bar is packed, not laid out.
				granule.Size = Vector3.new(
					(stepX - GRANULE_GAP) * (1.0 - (seed2 % 5) * 0.018),
					height,
					(stepZ - GRANULE_GAP) * (1.0 - (seed % 5) * 0.018)
				)
				granule.CFrame = tile.CFrame
					* CFrame.new(
						(ix - (GRANULE_DIV + 1) / 2) * stepX,
						layerTop - height / 2,
						(iz - (GRANULE_DIV + 1) / 2) * stepZ
					)
					-- Rotated about Y ONLY. That leaves every top face horizontal, so
					-- the walking surface stays flat while the grid stops lining up.
					-- Any other axis would tilt the faces you stand on.
					* CFrame.Angles(0, math.rad((seed2 - 6) * 0.7), 0)
				granule.Anchored = true
				-- THE CUBES ARE THE FLOOR. Not the tile.
				--
				-- With the tile carrying collision, the cubes under your feet could all
				-- be gone while a full-cell collider still held you up, and you only
				-- dropped when the server's dissolve timer fired. Standing on the cubes
				-- themselves means the floor disappears exactly where and when the cube
				-- does -- and falling through a hole in the top layer lands you on the
				-- layer below, so the two-stage crush is something you feel rather than
				-- only see.
				granule.CanCollide = true
				granule.CanTouch = false
				granule.CanQuery = false
				granule.CastShadow = false
				MaterialAppearance.apply(granule, materialName)
				-- A pressed bar is not one flat colour: each cube catches the light
				-- slightly differently. Varied by VALUE and gloss rather than by hue, so
				-- it still reads as one material and not as a mosaic.
				-- Value varies BOTH WAYS around the material colour, not just toward
				-- white. Lightening only makes a bar look like it is fading out; a
				-- pressed solid has cubes that catch the light and cubes that sit in
				-- shadow. This carries all the per-cube variation now that soap is
				-- opaque and the transparency jitter has nothing to act on.
				local tint = (seed - 5) / 5
				granule.Color = granule.Color:Lerp(
					if tint >= 0 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0),
					math.abs(tint) * 0.13
				)
				granule.Reflectance = granule.Reflectance * (0.7 + seed / 22)
				-- Transparency varies DOWNWARD only, never above the material's own
				-- value, so a cube can only ever be denser than the material and never
				-- washed out. A no-op while soap is opaque; it matters the moment a
				-- granular material is given any transparency at all.
				granule.Transparency = granule.Transparency * (0.72 + seed2 / 46)
				granule.Parent = tile
			end
		end
	end

	tile.Transparency = 1

	-- The tile is now a PURE SENSOR: the cubes carry collision, and it only still
	-- exists to fire the Touched/TouchEnded that DeformationService binds per cell.
	--
	-- It has to be grown upward to keep doing that. With collision moved to the cubes,
	-- a character stands ON the cube tops -- which is exactly the tile's own top face --
	-- and two surfaces that merely graze each other do not reliably fire Touched. A
	-- little height above the walkable plane guarantees the overlap, and costs nothing
	-- because the tile is invisible and no longer collides.
	local grow = 0.25
	tile.Size = Vector3.new(tile.Size.X, tile.Size.Y + grow, tile.Size.Z)
	tile.CFrame = tile.CFrame * CFrame.new(0, grow / 2, 0)
	tile.CanCollide = false
end

-- Materials that deliberately get NO mesh.
--
-- A tile mesh is rigid, so it can only carry identity that lives in its shape.
-- Where a material's identity is instead something that HAPPENS on the surface,
-- the mesh actively gets in the way:
--
--   KineticSand  footprints need sub-cell displacement. The micro-plate
--                heightfield presses a ~1-stud cell under each foot; a rigid mesh
--                can only sink whole. Adding the mesh silently removed footprints.
--   ButterWax    cracks are drawn with a SurfaceGui on the tile's flat top face.
--                Over a bumpy mesh that plane cuts through the relief.
--   BubbleWrap   bubbles must pop one at a time, which means individually animated
--                parts. With a mesh you get the mesh's baked caps AND the spawned
--                domes at once, which is why it stopped reading as bubble wrap.
--
-- Honey, slime and soap keep their meshes: their identity is pooled or moulded
-- form, which is exactly what a rigid mesh is good at.
local MESHLESS: { [string]: boolean } = {
	KineticSand = true,
	ButterWax = true,
	BubbleWrap = true,
}

-- Skinned rigs that COVER the slab rather than replace it, so the slab stays visible
-- underneath. Every other rig is the platform itself and the slab is hidden behind it.
-- Sand is NOT here any more. Its skin used to be a 0.9-thick lid with the slab showing
-- below it; now it is a block of sand wrapping the slab entirely, so leaving the slab
-- visible would only put concrete inside a closed sand box.
-- OVERLAY means the slab stays VISIBLE under the rig, as the thing being covered.
--
-- Bubble wrap is the obvious case: film wrapped round a block. The keyboard is here for a
-- different reason -- it is how the material gets TWO COLOURS. A MeshPart has one Color,
-- so caps and case could never differ while the mesh enclosed the whole platform. With the
-- mesh cut back to a plate, the slab underneath is the case and takes `baseColor` while
-- the caps take `color`.
-- MATERIALS WHOSE SLAB STAYS VISIBLE, because the slab is part of what you are looking at
-- rather than a carrier for something laid over it.
--
-- Bubble wrap and the keyboard are here because you have to see the body under the sheet or
-- the caps. Lego was briefly here too, on the reasoning that its slab was the baseplate
-- body -- and that is exactly what produced a solid red block with lego only on its lid.
-- Its bricks now span the full depth of the platform, so there is nothing left for a slab
-- to be.
local OVERLAY: { [string]: boolean } = { BubbleWrap = true, CreamyKeyboard = true }

-- === Skinned platform visuals (prototype) ===
--
-- One continuous mesh for the WHOLE platform, with a bone per sub-region cell.
-- The renderer moves bones instead of moving tiles, so a footfall dents the
-- surface with a smooth falloff into undisturbed material. This is what removes
-- the grid look: nothing moves as a rectangle any more.
--
-- Gameplay is untouched. The Part tiles still collide, still fire Touched, and
-- DeformationService still owns cell state; collision does not follow a skinned
-- mesh, so the tiles have to stay.
--
-- SIZE-LOCKED. A rig has a fixed bone grid, so a mesh is only valid for platforms
-- whose SubRegionGrid comes out the same shape. Honey_Platform_Skinned is authored
-- for 16 x 18 (a 5 x 6 grid), which is P1_HoneyCorridor. The honey sections of P4
-- and C1 are 16 x 12, a 5 x 4 grid, and need their own rig before they can use
-- this; until then they fall back to per-tile meshes automatically.
-- meshHeight is the authored bounding-box height, and it is what makes the import
-- scale irrelevant. FBX is centimetre-native while Blender exports metres, so
-- Roblox imports these at roughly 100x. Forcing Size from the authored numbers
-- normalises that instead of depending on importer settings, which is the same
-- thing that already kept the per-tile meshes correct.
-- `surfaceOffset` is the distance from the mesh's bounding-box centre up to the
-- plane you walk on. PER MESH, not shared: the hanging detail is what drags the
-- bounding box down, and slime's tendrils reach 4.0 studs where honey's drips reach
-- 2.6, so one constant put slime nearly a stud into the floor. Each generator PRINTS
-- the entry it needs -- run it and paste, do not measure by eye.
--
-- A LIST PER MATERIAL, not one entry, because a material does not appear at one size.
-- Soap is the clearest case: R2_SoapBridge is a tapered run, so its soap arrives as
-- 14 x 5 and 8 x 5 slabs, and C3 adds 8 x 12 -- three rigs for one material. With a
-- single entry per material, two of those three would have silently fallen back to
-- per-tile meshes, which is the grid these rigs exist to remove, showing up on some
-- platforms and not others.
type SkinnedSpec = {
	sizeX: number,
	sizeZ: number,
	meshHeight: number,
	surfaceOffset: number,
	-- How much WIDER the mesh is than its slab, total across both sides. Absent for a rig
	-- that IS the platform. Non-zero for a wrap, which legitimately stands proud of the
	-- thing it wraps: bubble wrap's pockets bulge off all four walls, so its mesh is
	-- about a stud wider than the slab underneath. DECLARED rather than absorbed into a
	-- looser tolerance, so the import check keeps its ability to catch a real mistake.
	meshPad: number?,
	-- nil means the plain sheet. Anything else is matched against the slab's Form.
	form: string?,
	-- WHERE THE FLOOR IS, cell by cell, as a drop below the walkable plane.
	--
	-- `surfaceOffset` puts that plane at the mesh's HIGHEST point, and every tile used to sit
	-- on it. On a plain bed that is invisible -- lava's relief is a third of a stud. On a
	-- sculpted one the peak is nearly three studs above the bed, so you stood level with the
	-- top of the ridge with the whole platform under your feet and nothing touching them.
	--
	-- Every value is zero or negative, so the plane stays the ceiling and no cell can ever
	-- push a collider up through the surface -- they only come DOWN to meet it. Indexed
	-- (row - 1) * cols + col, which is the order the generator writes them in.
	--
	-- Collider data, not geometry: changing these needs a paste and no re-import.
	drops: { number }?,
	-- HOW MANY BUTTONS TO A CELL, per axis. Absent or 1 is one big cap per cell. The mesh
	-- cuts its wells on the same sub-lattice, so this and the FBX are two readings of one
	-- number and cannot drift.
	capDiv: number?,
	-- How many stacked sheets of pockets the mesh carries. Absent or 1 is an ordinary
	-- sheet. More than that makes the platform a genuine hazard: see DeformationService.
	popLayers: number?,
	mesh: string,
}

local SKINNED_PLATFORMS: { [string]: { SkinnedSpec } } = {
	-- BOTH sizes honey appears at. There was only the 16x18, so P4 and C1 -- both
	-- 16x12 -- fell back to per-tile meshes and never deformed. The rig audit is what
	-- found it, reporting "Honey -- ONLY 1/3 slabs rigged".
	Honey = {
		{ sizeX = 16, sizeZ = 18, meshHeight = 4.5, surfaceOffset = 1.82, mesh = "Honey_Platform_Skinned" },
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.52, surfaceOffset = 1.83, mesh = "Honey_Platform_16x12" },
		-- A honeycomb, and the one decorative idea here that also moves your feet. The comb's
		-- pitch is CELL SCALE, so the collider grid can follow it: the walls come out as
		-- raised footing and the cells as dips you step down into. A finer comb would be
		-- prettier and would be pure decal.
		{ sizeX = 16, sizeZ = 12, meshHeight = 5.02, surfaceOffset = 2.53, mesh = "Honey_Platform_16x12_Comb", form = "comb", drops = { -0.556, -0.165, -0.082, -0.169, -0.546, -0.384, -0.066, -0.08, 0, -0.394, -0.384, -0.066, -0.08, 0, -0.394, -0.556, -0.165, -0.082, -0.169, -0.546 } },
		-- The pour that collected. The middle sits a stud below the rim, so the short way
		-- across is downhill into the deepest, slowest honey on the platform and back out.
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.59, surfaceOffset = 2.32, mesh = "Honey_Platform_16x12_Pool", form = "pool", drops = { -0.152, 0, -0.097, -0.007, -0.135, -0.047, -0.053, -1.065, -0.041, -0.056, -0.047, -0.053, -1.065, -0.041, -0.056, -0.152, 0, -0.097, -0.007, -0.135 } },
	},
	Slime = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 6.78, surfaceOffset = 2.72, mesh = "Slime_Platform_Skinned" },
		-- Bubbles risen under the skin, a cell across each. Your footing is on top of one or
		-- down in the gap between two, and on the material that LAUNCHES you that decides
		-- where you are standing at the moment it throws you.
		{ sizeX = 16, sizeZ = 12, meshHeight = 8.72, surfaceOffset = 4.38, mesh = "Slime_Platform_16x12_Blister", form = "blister", drops = { -2.266, -2.042, -0.643, -1.878, -2.335, -0.988, -0.268, -0.699, -0.515, -0.426, -2.404, -0.749, 0, -0.822, -1.364, -2.328, -1.693, -1.906, -0.077, -1.923 } },
		-- A trough down the travel axis with a bank either side. The one form that shapes the
		-- ROUTE rather than the surface -- and it takes nothing away, so unlike a hole
		-- nobody can fall through it.
		{ sizeX = 16, sizeZ = 12, meshHeight = 7.74, surfaceOffset = 3.89, mesh = "Slime_Platform_16x12_Channel", form = "channel", drops = { -0.246, -0.517, -2.324, -0.526, -0.446, -0.261, -0.43, -2.457, -0.147, 0, -0.303, -0.292, -2.612, -0.192, -0.13, -0.353, -0.368, -2.379, -0.444, -0.456 } },
	},
	-- Jello borrows slime's rig. Both are a soft body that deforms and springs back, and
	-- the bones are positional -- nothing in that mesh knows it is slime. What separates
	-- them is that slime THROWS you a fixed distance and jello returns what you put in.
	JelloSoda = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 6.78, surfaceOffset = 2.72, mesh = "Jello_Platform_Skinned" },
	},
	-- A BED OF SIX BLOCKS, not a slab. The tops stand 1.19 studs above the grooves between
	-- them, which is why this carries drops where jello does not: one flat plane through a
	-- surface that lumpy would bury you on every blob and float you over every seam.
	--
	-- The drops come out tiny (0.145 at worst) and that is the measurement doing its job
	-- rather than a sign it was unnecessary. Every collider cell happens to contain a blob
	-- top, so the floor is effectively flat and the grooves stay purely visual -- you see a
	-- pack of Needohs and you walk across it without tripping down every seam.
	-- ROUNDER AND FULLER than the first build. At a squareness of 4.5 the blobs were nearly
	-- flat-topped out to a hard shoulder, which is a rounded paving slab: correct geometry,
	-- wrong object. A NeeDoh is a ball squashed until its sides meet its neighbours, so the
	-- top is domed and the corners generous. 2.8 with a much smaller flat gets that, and the
	-- numbers below are re-measured from the new mesh rather than nudged.
	-- FOUR LAYOUTS, not one. A single 3x2 bed is a texture: a player learns it in one crossing
	-- and stops looking at it, which is the opposite of what a surface in this game is for.
	-- These differ in the two things the eye reads at walking speed -- how many blobs and how
	-- round -- and each puts the flat landings somewhere else, so each walks differently.
	--
	-- Every row measured from its own mesh. The drops matter more here than on the flat beds:
	-- `boulders` has a 1.35-stud groove between its four, and a collider that ignored it would
	-- have you walking on air over the gaps.
	Needoh = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 7.66, surfaceOffset = 3.85, mesh = "Needoh_Platform_Skinned", drops = { -0.023, -0.081, -0.145, -0.075, -0.017, -0.023, -0.081, -0.145, -0.075, -0.017, -0.114, -0.169, -0.078, -0.058, 0, -0.114, -0.169, -0.078, -0.058, 0 } },
		{ sizeX = 16, sizeZ = 12, meshHeight = 8.28, surfaceOffset = 4.16, mesh = "Needoh_Platform_Skinned_Boulders", form = "boulders", drops = { 0, 0, -1.347, -0.122, -0.122, 0, 0, -1.347, -0.122, -0.122, -0.091, -0.091, -1.37, -0.054, -0.054, -0.091, -0.091, -1.37, -0.054, -0.054 } },
		{ sizeX = 16, sizeZ = 12, meshHeight = 7.11, surfaceOffset = 3.57, mesh = "Needoh_Platform_Skinned_Grid", form = "grid", drops = { -0.023, -0.145, -0.017, -0.019, -0.152, -0.114, -0.077, 0, -0.105, -0.077, -0.114, -0.077, 0, -0.105, -0.077, -0.049, -0.125, -0.009, -0.045, -0.135 } },
		{ sizeX = 16, sizeZ = 12, meshHeight = 7.79, surfaceOffset = 3.91, mesh = "Needoh_Platform_Skinned_Drift", form = "drift", drops = { -0.177, -0.121, -0.473, -0.403, -0.611, -1.337, -0.579, -0.526, -0.181, -1.169, -1.337, -0.579, -0.526, -0.181, -1.169, -0.629, -0.544, -0.376, 0, -0.167 } },
	},
	-- Three sticks lengthwise, so the two grooves run WITH the route and are never something
	-- to step over. No drops: the tops are flat and level end to end, which is what a cut
	-- stick is, so every collider cell already sits on the surface under it.
	-- DROPPED BY SHELL_THICKNESS, exactly as the butter and ice bodies are. The measured
	-- walkable plane of this mesh is 3.69; the wrapper now occupies the top 0.3 of that, so
	-- the butter itself is authored below it and the plate seams open onto something lower
	-- than themselves rather than onto more of the same height.
	ButterStick = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 7.34, surfaceOffset = 3.39, mesh = "ButterSticks_Platform_Skinned" },
	},
	-- The BUTTER BODY only. The wax shell on top is not a mesh at all -- it is the
	-- irregular plates attachShell lays over this, and they are what crack. These
	-- surfaces are authored SHELL_THICKNESS below the walkable plane so the plate seams
	-- open onto something lower than themselves.
	ButterWax = {
		{ sizeX = 16, sizeZ = 8, meshHeight = 4.17, surfaceOffset = 2.41, mesh = "Butter_Platform_16x8" },
		{ sizeX = 12, sizeZ = 10, meshHeight = 4.17, surfaceOffset = 2.41, mesh = "Butter_Platform_12x10" },
	},
	-- And ice borrows the butter BODY, for the same reason it borrows the shell: what is
	-- under a fractured coating is a smooth slab authored below the walkable plane, and
	-- that is as true of ice as of butter.
	Ice = {
		{ sizeX = 16, sizeZ = 8, meshHeight = 4.17, surfaceOffset = 2.41, mesh = "Ice_Platform_16x8" },
		{ sizeX = 12, sizeZ = 10, meshHeight = 4.17, surfaceOffset = 2.41, mesh = "Ice_Platform_12x10" },
	},
	Salt = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.61, surfaceOffset = 2.32, mesh = "Salt_Platform_16x12", drops = { -0.023, -0.099, -0.117, -0.032, -0.02, -0.074, -0.033, -0.028, -0.106, -0.011, -0.025, -0.032, 0, -0.03, -0.131, -0.113, -0.012, -0, -0.024, -0.019 } },
	},
	Lava = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.44, surfaceOffset = 2.24, mesh = "Lava_Platform_16x12", drops = { -0.13, 0, 0, -0.34, -0.195, 0, -0.335, 0, -0.01, 0, -0.186, -0.331, -0.148, 0, 0, -0.291, -0.205, 0, 0, -0.155 } },
		-- A vent. The one sculpt whose middle goes DOWN as well as up, which is what
		-- separates a crater from a hill.
		{ sizeX = 16, sizeZ = 12, meshHeight = 5.95, surfaceOffset = 2.99, mesh = "Lava_Platform_16x12_Crater", form = "crater", drops = { -1.635, -0.238, -0.007, -0.238, -1.7, -1.358, -0, -0.634, 0, -1.369, -1.506, -0, -0.634, 0, -1.431, -1.797, -0.238, -0.007, -0.238, -1.66 } },
	},
	Oobleck = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.25, surfaceOffset = 2.15, mesh = "Oobleck_Platform_16x12" },
	},
	Buttons = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.10, surfaceOffset = 2.07, mesh = "Buttons_Platform_16x12" },
		-- Four to a cell. See attachCap: capDiv drives the caps and the same number cut
		-- the wells, so the plastic and the parts are one figure read twice.
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.10, surfaceOffset = 2.07, mesh = "Buttons_Platform_16x12_Dense", form = "dense", capDiv = 2 },
		-- A domed plate, buttons intact and riding it.
		{ sizeX = 16, sizeZ = 12, meshHeight = 6.38, surfaceOffset = 3.21, mesh = "Buttons_Platform_16x12_Dome", form = "dome", drops = { -2.085, -2.064, -1.994, -2.064, -2.085, -2.084, -0.631, 0, -0.631, -2.084, -2.084, -0.631, 0, -0.631, -2.084, -2.085, -2.064, -1.994, -2.064, -2.085 } },
	},
	Snow = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.66, surfaceOffset = 2.35, mesh = "Snow_Platform_16x12", drops = { -0.07, -0.216, -0.276, -0.366, -0.255, -0.122, -0.112, -0.02, -0.141, -0.221, -0.263, 0, -0.021, -0.016, -0.154, -0.308, -0.139, -0.077, -0.026, -0.024 } },
		-- A drift: long windward climb, short lee face. The asymmetry is the whole read --
		-- a symmetric bank is a mound, and only a pushed one is a drift.
		{ sizeX = 16, sizeZ = 12, meshHeight = 6.90, surfaceOffset = 3.47, mesh = "Snow_Platform_16x12_Dune", form = "dune", drops = { -2.294, -2.44, -2.5, -2.59, -2.479, -1.163, -0.725, -0.642, -0.725, -1.163, -0.678, -0.108, 0, -0.108, -0.678, -2.527, -2.363, -2.301, -2.184, -2.214 } },
	},
	-- The seven beds from gen_material_beds.py, all at one size because each is a single
	-- straight platform. Every number here is PRINTED by that script rather than typed:
	-- surfaceOffset depends on how tall the surface came out, which moves whenever a field
	-- constant is touched, and a stale value floats the bed off its slab with no warning.
	Foam = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.16, surfaceOffset = 2.10, mesh = "Foam_Platform_16x12", drops = { -0.023, -0.102, -0.076, -0.016, -0.023, -0.048, -0.038, -0.033, -0.039, -0.042, 0, -0.076, -0.006, -0.021, -0.047, -0.03, -0.022, -0.055, -0.039, -0.031 } },
	},
	Clay = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.14, surfaceOffset = 2.09, mesh = "Clay_Platform_16x12" },
		-- Pressed in three steps, like a thumb into a slab.
		-- Pressed in three steps, like a thumb into a slab.
		{ sizeX = 16, sizeZ = 12, meshHeight = 6.65, surfaceOffset = 3.35, mesh = "Clay_Platform_16x12_Terrace", form = "terrace", drops = { -1.704, -1.701, -1.701, -1.701, -1.704, -1.7, -0.473, 0, -0.473, -1.7, -1.7, -0.473, 0, -0.473, -1.7, -1.704, -1.701, -1.701, -1.701, -1.704 } },
	},
	Charcoal = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.42, surfaceOffset = 2.23, mesh = "Charcoal_Platform_16x12", drops = { -0.095, -0.191, -0.161, -0.125, -0.273, -0.09, 0, -0.104, -0.062, -0.229, -0.091, -0.044, -0.068, -0.191, -0.124, -0.17, -0.294, -0.032, -0.187, -0.061 } },
		-- A spine corner to corner with a notch in the middle, so it is something you walk
		-- through rather than a wall you walk around.
		{ sizeX = 16, sizeZ = 12, meshHeight = 6.50, surfaceOffset = 3.27, mesh = "Charcoal_Platform_16x12_Ridge", form = "ridge", drops = { -0.216, -0.083, -2.262, -2.225, -2.374, -1.39, 0, -0.928, -2.163, -2.329, -2.192, -2.144, -0.928, 0, -1.39, -2.271, -2.394, -2.133, -0.083, -0.216 } },
	},
	Cloud = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 5.91, surfaceOffset = 2.97, mesh = "Cloud_Platform_16x12", drops = { -0.128, -0.439, -0.622, -0.165, -0.158, -0.309, -0.331, -0.837, -0.559, -0.329, 0, -0.45, -0.102, -0.516, -0.293, -0.095, -0.44, -0.41, -0.377, -0.115 } },
		-- One cumulus swell, and the only variant that does NOT damp the bed under it --
		-- a smooth dome in a field of metaball lumps reads as a bald patch, not a cloud.
		{ sizeX = 16, sizeZ = 12, meshHeight = 6.51, surfaceOffset = 3.28, mesh = "Cloud_Platform_16x12_Mound", form = "mound", drops = { -0.694, -1.005, -1.188, -0.732, -0.725, -0.875, -0.13, -0.097, -0.523, -0.895, -0.566, -0.389, 0, -0.637, -0.859, -0.661, -0.985, -0.888, -0.943, -0.681 } },
	},
	-- LEGO IS NOT HERE ANY MORE, and the empty comment is left deliberately so nobody
	-- adds it back. It has no mesh at all: the platform is the slab plus a real brick per
	-- cell (attachBrick), the same way soap is the slab plus a field of cubes. A material
	-- whose whole identity is that it is RIGID has no business being a deformable surface,
	-- and every problem lego had came from being one.

	LightSwitch = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.57, surfaceOffset = 2.30, mesh = "LightSwitch_Platform_16x12", drops = { -0.058, -0.083, -0.108, 0, -0.025, -0.074, -0.097, -0.121, -0.018, -0.042, -0.074, -0.097, -0.121, -0.018, -0.042, -0.058, -0.083, -0.108, 0, -0.025 } },
	},
	Chocolate = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.45, surfaceOffset = 2.25, mesh = "Chocolate_Platform_16x12" },
		-- Piped, like icing, and the middle of it is a blob for the same reason real
		-- piping is: a nozzle cannot make a spiral tighter than its own bore.
		{ sizeX = 16, sizeZ = 12, meshHeight = 5.75, surfaceOffset = 2.89, mesh = "Chocolate_Platform_16x12_Swirl", form = "swirl", drops = { -1.314, -1.314, -1.092, -1.314, -1.314, -1.345, -0.882, -0.057, -0.879, -1.345, -1.345, -0.259, 0, -0.476, -1.345, -1.314, -1.314, -1.292, -1.314, -1.314 } },
	},
	-- THE SAME MESH, and that is the point rather than an oversight. A shared mesh means a
	-- shared SurfaceAppearance, which is normally the thing to avoid -- but these two are
	-- one substance at two temperatures and ought to be indistinguishable standing still.
	-- No extra import, no second texture set.
	ChocolateSolid = {
		{ sizeX = 16, sizeZ = 12, meshHeight = 4.45, surfaceOffset = 2.25, mesh = "Chocolate_Platform_16x12" },
	},
	-- The leaf bed. Both sizes are printed by gen_lambs_ear.py rather than typed: the
	-- surface offset depends on how tall the tallest leaf came out, which changes every
	-- time LEAF_RISE or LEAF_LIFT is touched, and a stale number here floats the bed off
	-- its slab with nothing to warn you.
	LambsEar = {
		{ sizeX = 16, sizeZ = 8, meshHeight = 4.75, surfaceOffset = 2.39, mesh = "LambsEar_Platform_16x8" },
		{ sizeX = 12, sizeZ = 10, meshHeight = 4.73, surfaceOffset = 2.39, mesh = "LambsEar_Platform_12x10" },
	},
	-- SIX, because bubble wrap appears at six distinct slab sizes -- three stair treads
	-- in R3 and three taper pieces in C4. The list is printed by gen_bubble_wrap.py,
	-- which reads those sizes back out of THIS file rather than having them typed in, so
	-- resizing a bubble wrap slab cannot silently leave a rig missing.
	--
	-- Every sheet puts a pocket at x = 0 on a fixed 1.3 pitch whatever its width, so the
	-- three taper pieces line up across their joins instead of each restarting the
	-- lattice from its own centre.
	-- One rig per sand slab size. The bone lattice is 0.9 studs, fine enough to resolve a
	-- FOOTPRINT -- which is why sand could not use a per-cell rig like honey's and spent
	-- so long meshless.
	KineticSand = {
		{ sizeX = 10, sizeZ = 6.18, meshHeight = 5.08, surfaceOffset = 2.36, mesh = "Sand_Surface_10x6_18" },
		{ sizeX = 11, sizeZ = 4, meshHeight = 5.10, surfaceOffset = 2.35, mesh = "Sand_Surface_11x4" },
		{ sizeX = 12, sizeZ = 4, meshHeight = 5.09, surfaceOffset = 2.35, mesh = "Sand_Surface_12x4" },
		{ sizeX = 12, sizeZ = 6.18, meshHeight = 5.11, surfaceOffset = 2.35, mesh = "Sand_Surface_12x6_18" },
		{ sizeX = 13.5, sizeZ = 4, meshHeight = 5.09, surfaceOffset = 2.36, mesh = "Sand_Surface_13_5x4" },
		{ sizeX = 14, sizeZ = 4, meshHeight = 5.10, surfaceOffset = 2.35, mesh = "Sand_Surface_14x4" },
		{ sizeX = 14, sizeZ = 6.18, meshHeight = 5.09, surfaceOffset = 2.36, mesh = "Sand_Surface_14x6_18" },
		{ sizeX = 16, sizeZ = 4, meshHeight = 5.08, surfaceOffset = 2.36, mesh = "Sand_Surface_16x4" },
		{ sizeX = 16, sizeZ = 6.18, meshHeight = 5.10, surfaceOffset = 2.35, mesh = "Sand_Surface_16x6_18" },
		-- Sculpted. One slab, untapered, so the shape cannot be cut in half at a join.
		{ sizeX = 16, sizeZ = 16, meshHeight = 5.46, surfaceOffset = 2.17, mesh = "Sand_Turtle_16x16", form = "turtle" },
	},
	-- One bone per keycap, and the caps are RIGID: every vertex of a cap carries weight
	-- 1.0 from its own bone, so a key travels without changing shape. Contrast the sheet
	-- below, whose pockets are weighted by dome height because a bubble collapses.
	CreamyKeyboard = {
		{ sizeX = 16, sizeZ = 16, meshHeight = 0.90, surfaceOffset = 0.45, mesh = "Keyboard_Field_16x16" },
	},
	-- THE SAME RIG, A DIFFERENT MATERIAL. Nothing about the geometry of a keyboard changes
	-- when the keys are molten, so this points at the identical mesh -- the difference is
	-- entirely in how it behaves and what it does with light, which is where the difference
	-- between two materials belongs.
	LavaKeys = {
		{ sizeX = 16, sizeZ = 16, meshHeight = 0.90, surfaceOffset = 0.45, mesh = "Keyboard_Field_16x16" },
	},
	BubbleWrap = {
		{ sizeX = 10, sizeZ = 8, meshHeight = 5.89, surfaceOffset = 2.90, meshPad = 2.10, mesh = "BubbleWrap_Sheet_10x8" },
		{ sizeX = 12, sizeZ = 4, meshHeight = 5.89, surfaceOffset = 2.90, meshPad = 2.11, mesh = "BubbleWrap_Sheet_12x4" },
		{ sizeX = 13, sizeZ = 8, meshHeight = 5.89, surfaceOffset = 2.90, meshPad = 2.09, mesh = "BubbleWrap_Sheet_13x8" },
		{ sizeX = 14, sizeZ = 4, meshHeight = 5.89, surfaceOffset = 2.90, meshPad = 2.10, mesh = "BubbleWrap_Sheet_14x4" },
		{ sizeX = 16, sizeZ = 4, meshHeight = 5.89, surfaceOffset = 2.90, meshPad = 2.12, mesh = "BubbleWrap_Sheet_16x4" },
		{ sizeX = 16, sizeZ = 8, meshHeight = 5.89, surfaceOffset = 2.90, meshPad = 2.12, mesh = "BubbleWrap_Sheet_16x8" },
		-- Twice the pitch and twice the radius. The renderer needs no telling: it finds
		-- bones by world position, so a different lattice is just a different mesh.
		{ sizeX = 16, sizeZ = 16, meshHeight = 5.15, surfaceOffset = 2.54, meshPad = 0.72, mesh = "BubbleWrap_Giant_16x16", form = "giant", popLayers = 2 },
	},
	-- SOAP IS DELIBERATELY NOT HERE, and the rigs for it were removed rather than
	-- left unused.
	--
	-- A rig cannot open a hole in itself: MeshId is fixed at import, a Bone carries
	-- only a CFrame, and there is no per-cell transparency. Soap's whole mechanic is
	-- cells vanishing and dropping you through, so the best a rig could do was sink
	-- the cell's bone and let the skin stretch after it -- and skinning STRETCHES,
	-- which is the one thing a dry brittle solid never does. A 9-stud pull against a
	-- ~3.5-stud bone influence radius pulled the surface into vertical sheets and left
	-- the collision nowhere near what you could see.
	--
	-- So soap keeps per-cell meshes, and its cells are edge-matched (see CONTINUOUS)
	-- so the platform still reads as one bar rather than a field of tiles. The grid is
	-- not a compromise here: soap is a bar that fractures into pieces, and the cell
	-- boundaries are where it fractures.
}

-- Forward-declared: skinnedSpecFor reports a missing form variant and is defined above
-- the diagnostics block. Declaring the local here and defining it below assigns THIS
-- local, so there is still no global.
local warnOnce: (string, string) -> ()

local function skinnedSpecFor(slab: BasePart, materialName: string): SkinnedSpec?
	local variants = SKINNED_PLATFORMS[materialName]
	if not variants then
		return nil
	end
	-- SIZE IS NOT THE ONLY KEY ANY MORE. A form variant is a different mesh at the
	-- same size, so a plain size match would hand a turtle chunk the ordinary sheet --
	-- silently, since both are valid rigs of the right dimensions. Match the form
	-- first, and fall back to the form-less spec only if there is no shaped one, so a
	-- form named in the segment table but never generated degrades to plain sand
	-- rather than to no mesh at all.
	local form = slab:GetAttribute("Form")
	local fallback: SkinnedSpec? = nil
	for _, spec in ipairs(variants) do
		-- Tolerance is tight on purpose: a near-miss means a different cell grid, and
		-- bones would silently drive the wrong parts of the surface.
		if math.abs(slab.Size.X - spec.sizeX) <= 0.1 and math.abs(slab.Size.Z - spec.sizeZ) <= 0.1 then
			if spec.form == form then
				return spec
			elseif spec.form == nil then
				fallback = spec
			end
		end
	end
	if form ~= nil and fallback ~= nil then
		warnOnce(
			("noform:%s:%s"):format(materialName, tostring(form)),
			("no '%s' mesh for %s at %.4gx%.4g; using the plain sheet. Generate it and add a spec with form = \"%s\"."):format(
				tostring(form), materialName, slab.Size.X, slab.Size.Z, tostring(form)
			)
		)
	end
	return fallback
end

-- Diagnostics state. Everything below reports what it looked for and what it
-- actually found, once each. The first version of this fell back to plain Parts in
-- silence, which is indistinguishable from "the meshes did not work" and gives you
-- nothing to act on.
local warned: { [string]: boolean } = {}

-- ===== ONE LINE, NOT SIXTY =====
--
-- Nearly every imported mesh arrives wrapped in a Model, because that is what the 3D Importer
-- produces. It is harmless and resolveTemplate reaches through it, but it used to warn once per
-- NAME -- which is sixty-odd identical lines every boot.
--
-- That is not a cosmetic problem. The Output is where this project reports the things that
-- actually matter, and a missing flume mesh -- which makes the level impossible to finish --
-- printed exactly one line into the middle of that wall of text and was never seen. Noise in a
-- log costs you the signal in it.
local wrappedMeshes: { string } = {}

function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("ChunkBuilder: " .. message)
end

local function describeChildren(parent: Instance): string
	local names = {}
	for _, child in ipairs(parent:GetChildren()) do
		table.insert(names, ("%s (%s)"):format(child.Name, child.ClassName))
	end
	return #names > 0 and table.concat(names, ", ") or "<empty>"
end

-- FindFirstChild is case-SENSITIVE. A folder named "tilemeshes" or "assets" will
-- not be found by an exact lookup, so match loosely and say so rather than
-- pretending nothing is there.
local function findLoose(parent: Instance, name: string): Instance?
	local direct = parent:FindFirstChild(name)
	if direct then
		return direct
	end
	local lower = name:lower()
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name:lower() == lower then
			warnOnce(
				"case:" .. name,
				("found '%s' but expected '%s'. Names are case-sensitive; using it anyway, but rename it."):format(
					child.Name,
					name
				)
			)
			return child
		end
	end
	return nil
end

local function meshFolder(): Instance?
	local assets = findLoose(ReplicatedStorage, "Assets")
	if not assets then
		warnOnce("noassets", "no ReplicatedStorage.Assets folder; tile meshes disabled, using plain Parts.")
		return nil
	end

	local folder = findLoose(assets, MESH_FOLDER)
	if not folder then
		warnOnce(
			"nofolder",
			("no '%s' folder under %s. Its children are: %s"):format(
				MESH_FOLDER,
				assets:GetFullName(),
				describeChildren(assets)
			)
		)
		return nil
	end
	return folder
end

-- Resolves one tile mesh, tolerating the two shapes the 3D Importer commonly
-- produces: a bare MeshPart, or a Model wrapping one.
local function resolveTemplate(folder: Instance, name: string): BasePart?
	local found = findLoose(folder, name)

	if not found then
		-- The importer often keeps the file extension in the instance name.
		found = findLoose(folder, name .. ".obj")
	end

	if not found then
		warnOnce(
			"missing:" .. name,
			("no mesh named '%s' in %s. Its children are: %s"):format(name, folder:GetFullName(), describeChildren(folder))
		)
		return nil
	end

	if found:IsA("BasePart") then
		return found
	end

	local inner = found:FindFirstChildWhichIsA("BasePart", true)
	if inner then
		-- COLLECTED, NOT WARNED. See wrappedMeshes: this is the common case, it is harmless,
		-- and one line per name buried every warning that was not harmless.
		if not warned["wrapped:" .. name] then
			warned["wrapped:" .. name] = true
			table.insert(wrappedMeshes, name)
		end
		return inner
	end

	warnOnce("notapart:" .. name, ("'%s' is a %s with no BasePart inside it."):format(name, found.ClassName))
	return nil
end

-- Which authored variant covers this cell, and the Y rotation that turns its
-- outer side outward.
--
-- The meshes are authored in Blender with the outer side on -Y, and the OBJ export
-- maps Blender -Y to Roblox +Z (verified against the exported vertex data: the
-- drips all land at +Z). So the authored outer direction is +Z, and rotating about
-- Y maps it: 0 -> +Z, 90 -> +X, 180 -> -Z, 270 -> -X.
local function variantFor(col: number, row: number, cols: number, rows: number): (string, number)
	local minX, maxX = col == 1, col == cols
	local minZ, maxZ = row == 1, row == rows

	if (minX or maxX) and (minZ or maxZ) then
		-- Corner authored with outer sides on +Z and -X.
		if minX and maxZ then
			return "Corner", 0
		elseif maxX and maxZ then
			return "Corner", 90
		elseif maxX and minZ then
			return "Corner", 180
		else
			return "Corner", 270
		end
	end

	if maxZ then
		return "Edge", 0
	elseif maxX then
		return "Edge", 90
	elseif minZ then
		return "Edge", 180
	elseif minX then
		return "Edge", 270
	end

	return "Interior", 0
end

local function attachMeshVisual(tile: BasePart, materialName: string, col: number, row: number, cols: number, rows: number)
	if MESHLESS[materialName] then
		return
	end

	local folder = meshFolder()
	if not folder then
		return
	end

	local name, rotation, variant
	if CONTINUOUS[materialName] then
		local v, rot = variantFor(col, row, cols, rows)
		name, rotation, variant = ("%s_Tile_%s"):format(materialName, v), rot, v
	else
		name, rotation, variant = ("%s_Tile"):format(materialName), 0, "Interior"
	end

	local template = resolveTemplate(folder, name)
	if not template then
		return
	end

	-- Authored at TILE_AUTHORED studs square. A wildly different footprint means
	-- the importer rescaled on the way in, and every mesh would come out
	-- proportionally wrong with nothing to indicate why.
	if math.abs(template.Size.X - TILE_AUTHORED) > 0.5 then
		warnOnce(
			"scale:" .. name,
			("'%s' is %.2f studs wide but the meshes are authored at %.1f. Check the import scale."):format(
				name,
				template.Size.X,
				TILE_AUTHORED
			)
		)
	end

	local visual = template:Clone() :: BasePart
	visual.Name = "Visual"
	visual.Anchored = true
	visual.CanCollide = false
	visual.CanTouch = false
	visual.CanQuery = false

	-- Authored at 3.2 studs square. Cells run smaller than that on most platforms,
	-- so scale XZ to the cell and take the mean for height, which keeps drips and
	-- bubble caps in proportion instead of squashing one axis.
	local authored = template.Size
	local scaleX = tile.Size.X / TILE_AUTHORED
	local scaleZ = tile.Size.Z / TILE_AUTHORED
	local scaleY = (scaleX + scaleZ) * 0.5
	visual.Size = Vector3.new(authored.X * scaleX, authored.Y * scaleY, authored.Z * scaleZ)

	-- Boundary tiles are pushed outward so their drips clear the base slab.
	--
	-- Without this the drips are invisible: they hang 2.1 studs below the walkable
	-- face, but the slab's top is only 0.9 below it and the slab is 4 studs thick
	-- directly underneath, so the whole drip sits inside solid geometry. Offsetting
	-- along the authored outer direction (+Z before rotation, so the rotation
	-- carries it to the correct world side) puts them past the slab edge in open
	-- air. The walkable surface overhangs by the same amount, which reads correctly
	-- for a viscous pour spilling over a ledge.
	local outX, outZ = 0.0, 0.0
	if DRIPPING[materialName] then
		if variant == "Edge" then
			outZ = BOUNDARY_OVERHANG
		elseif variant == "Corner" then
			outZ = BOUNDARY_OVERHANG
			outX = -BOUNDARY_OVERHANG -- authored corner is outer on +Z and -X
		end
	end

	-- Bounding-box TOP flush with the tile's walkable face, so the visible surface
	-- and the collision surface agree.
	visual.CFrame = tile.CFrame
		* CFrame.new(0, TILE_THICKNESS / 2 - visual.Size.Y / 2, 0)
		* CFrame.Angles(0, math.rad(rotation), 0)
		* CFrame.new(outX, 0, outZ)

	MaterialAppearance.apply(visual, materialName)
	visual.Parent = tile

	-- The Part tile becomes a pure collider/trigger once a mesh is drawing it.
	tile.Transparency = 1
end

-- Attaches the single skinned mesh for a platform, if one is authored for this
-- material at this exact size. Returns true when it took over the visuals.
-- Returns the SPEC rather than a boolean, because the tile loop needs `drops` off it and
-- calling skinnedSpecFor twice would warn twice about the same missing rig.
local function attachSkinnedVisual(slab: BasePart, materialName: string): SkinnedSpec?
	local spec = skinnedSpecFor(slab, materialName)
	if not spec then
		return nil
	end

	local folder = meshFolder()
	if not folder then
		return nil
	end

	local template = resolveTemplate(folder, spec.mesh)
	if not template then
		return nil
	end

	if not (template :: any).HasSkinnedMesh then
		-- A LEFTOVER OBJ CAN SHADOW ITS OWN FBX. resolveTemplate falls back to
		-- `name .. ".obj"`, and a mesh that has been shipped in both formats under one
		-- name leaves two candidates in the folder -- so the rigid one can win the lookup
		-- and the rig silently never attaches. Rather than fail on the first candidate,
		-- look for any sibling of that name that IS skinned.
		local rescued: BasePart? = nil
		for _, child in ipairs(folder:GetChildren()) do
			local candidate = if child:IsA("BasePart")
				then child
				else child:FindFirstChildWhichIsA("BasePart", true)
			if candidate and (candidate :: any).HasSkinnedMesh then
				local base = child.Name:gsub("%.%a+$", "")
				if base == spec.mesh then
					rescued = candidate
					break
				end
			end
		end
		if not rescued then
			warnOnce(
				"notskinned:" .. spec.mesh,
				("'%s' has no skinned mesh data, so this platform will NOT deform. An OBJ or a bone-less FBX cannot. If you imported both an .obj and an .fbx under this name, DELETE THE OBJ -- it shadows the rig."):format(
					spec.mesh
				)
			)
			return nil
		end
		warnOnce(
			"shadowed:" .. spec.mesh,
			("'%s' resolved to a non-skinned copy first; using the skinned one instead. Delete the leftover OBJ."):format(
				spec.mesh
			)
		)
		template = rescued
	end

	local visual = template:Clone() :: BasePart
	visual.Name = "SkinnedVisual"
	visual.Anchored = true
	visual.CanCollide = false
	visual.CanTouch = false
	visual.CanQuery = false
	-- A skinned mesh must be imported at the right size. It CANNOT be corrected here.
	--
	-- Setting Size rescales the rendered mesh, but a Bone is an Attachment carrying
	-- an explicit CFrame, and those offsets do not scale with it. Resizing therefore
	-- leaves every bone stranded at its pre-scale position, so deformation lands
	-- nowhere near the cell that triggered it. That is what produced dents "on the
	-- opposite side", and then no visible dent at all once bones were matched by
	-- position and the nearest one was hundreds of studs away.
	--
	-- So: refuse, explain, and fall back to per-tile meshes, which are visually worse
	-- but correct. Silently rendering a rig whose bones are in the wrong place is the
	-- one outcome with no way to diagnose from inside the game.
	local imported = visual.Size
	local pad = spec.meshPad or 0
	if math.abs(imported.X - (spec.sizeX + pad)) > 0.5
		or math.abs(imported.Z - (spec.sizeZ + pad)) > 0.5
	then
		warnOnce(
			"skinnedsize",
			("'%s' imported at %.1f x %.1f x %.1f but must be %.1f x %.1f x %.1f. Re-import the FBX: resizing a skinned mesh moves its geometry but NOT its bones, so it cannot be fixed in code. Falling back to per-tile meshes."):format(
				spec.mesh,
				imported.X, imported.Y, imported.Z,
				spec.sizeX, spec.meshHeight, spec.sizeZ
			)
		)
		visual:Destroy()
		return nil
	end
	-- SURFACE_Y is ALREADY measured from the slab centre (it is
	-- SLAB_THICKNESS/2 + TILE_THICKNESS), so subtracting half the slab again put
	-- the mesh two studs low and buried it inside the slab.
	visual.CFrame = slab.CFrame * CFrame.new(0, SURFACE_Y - spec.surfaceOffset, 0)
	MaterialAppearance.apply(visual, materialName)
	visual.Parent = slab

	-- The mesh becomes the entire visible platform, so the slab and its bevels are
	-- hidden. They stay as collision. This is also what lets the drips read: with
	-- the slab visible, anything hanging below the honey surface is swallowed by
	-- four studs of opaque concrete directly underneath it.
	--
	-- EXCEPT FOR AN OVERLAY, where the rig is a covering rather than the platform. A
	-- bubble wrap sheet is 0.6 studs thick and lives in the tile layer: hide the slab
	-- under it and the platform becomes a sheet of plastic floating over a four-stud
	-- drop. Bubble wrap is the one material whose own appearance already defines a
	-- separate baseColour and baseMaterial, which is the slab showing through as the
	-- thing being wrapped.
	-- A MULTI-LAYER SHEET IS NOT AN OVERLAY, whatever its material says.
	--
	-- The overlay rule exists because a single 0.6-stud sheet hides nothing, so the slab
	-- has to show through as the thing being wrapped. A two-layer sheet is 1.7 studs deep
	-- and its lower pockets hang BELOW the slab's top face -- leave the slab opaque and
	-- the entire second layer is buried inside four studs of concrete, so the player has
	-- no way of seeing what they are about to fall through. Nothing is being wrapped
	-- here; the stack IS the platform.
	local layered = (spec.popLayers or 1) > 1
	if layered then
		slab:SetAttribute("PopLayers", spec.popLayers)
	end
	if layered or not OVERLAY[materialName] then
		slab.Transparency = 1
		for _, child in ipairs(slab:GetChildren()) do
			if child:IsA("BasePart") and child.Name:match("^CornerBevel") then
				child.Transparency = 1
			end
		end
	end

	slab:SetAttribute("SkinnedVisual", true)
	return spec
end

-- The printed wrapper text, showing THROUGH the translucent wax from above and from
-- below. It is a SurfaceGui, and being unlit is right for once: this is matte ink on
-- paper, not a feature of the surface, so it should not catch a highlight.
-- WHOSE WRAPPER, and what it says. Ice was reading "BUTTER" across both faces, because
-- this printed unconditionally on anything wearing a shell and butter was the only thing
-- that ever did. A frozen sheet is not a packaged good and has no print at all, so a
-- material missing from here gets no plates and no SurfaceGuis built for it.
local WRAPPER_PRINT: { [string]: { text: string, color: Color3 } } = {
	-- The blue of printed wrapper ink, softened well down: it sits under a wax film and
	-- is stamped on soft butter, so a crisp saturated blue would look applied rather
	-- than printed.
	ButterWax = { text = "BUTTER", color = Color3.fromRGB(96, 126, 178) },
}

local function attachWrapperText(slab: BasePart, surfaceLocalY: number, materialName: string)
	local print_ = WRAPPER_PRINT[materialName]
	if not print_ then
		return
	end
	for _, face in ipairs({ Enum.NormalId.Top, Enum.NormalId.Bottom }) do
		local plate = Instance.new("Part")
		plate.Name = "WrapperPrint_" .. face.Name
		plate.Size = Vector3.new(slab.Size.X * 0.92, 0.05, slab.Size.Z * 0.92)
		plate.CFrame = slab.CFrame
			* CFrame.new(0, if face == Enum.NormalId.Top then surfaceLocalY else -slab.Size.Y / 2 - 0.05, 0)
		plate.Anchored = true
		plate.CanCollide = false
		plate.CanTouch = false
		plate.CanQuery = false
		plate.CastShadow = false
		plate.Transparency = 1
		plate.Parent = slab

		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 48
		gui.AlwaysOnTop = false
		gui.Adornee = plate
		gui.Parent = plate

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = print_.text
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = print_.color
		label.TextTransparency = 0.35
		label.Parent = gui
	end
end

-- Lays the platform's wax coating: ONE skinned MeshPart, fractured into Voronoi
-- shards in Blender (gen_wax_shell.py), plus the printed wrapper text under it.
--
-- It replaces three generations of Part-based shells, all of which read as squares.
-- The reason was structural: exact tiling with boxes forces AXIS-ALIGNED RECTANGLES,
-- because rotating a box breaks the tiling. However much the sizes varied, every crack
-- line still ran parallel to the platform's own edges. A Voronoi partition has edges at
-- whatever angle its seeds dictate, and being one mesh it has no part boundaries to
-- draw outlines of their own -- the only lines are the grooves, which are the cracks.
-- MATERIALS WHOSE SOLID BODY IS A MESH IN ITS OWN RIGHT.
--
-- Only bubble wrap, and only because it is the one OVERLAY material: its pocket sheet is a
-- mesh and the slab underneath is left VISIBLE, so that you can see the layer you are about
-- to burst through. Everywhere else the slab is hidden and the surface mesh is the whole
-- visual, so there is nothing for a body mesh to do.
--
-- A visible slab is a plain Part, and a plain Part cannot carry PBR: SurfaceAppearance is
-- attached by hand to the imported mesh TEMPLATES in this project and inherited by clones,
-- which is why every mesh in the game has maps and nothing built at runtime does. Making
-- the body a mesh is the only route to texturing it.
--
-- The offset is the same for every size, because the film is flat -- but it is looked up
-- per size rather than assumed, so that a body with real relief could be added later
-- without this becoming quietly wrong.
local BODY_MESHES: { [string]: { [string]: { offset: number } } } = {
	BubbleWrap = {
		["10x8"] = { offset = 2.09 },
		["12x4"] = { offset = 2.09 },
		["13x8"] = { offset = 2.09 },
		["14x4"] = { offset = 2.09 },
		["16x4"] = { offset = 2.09 },
		["16x8"] = { offset = 2.09 },
	},
}

local function attachBodyMesh(slab: BasePart, materialName: string): boolean
	local sizes = BODY_MESHES[materialName]
	if not sizes then
		return false
	end
	local key = ("%dx%d"):format(math.floor(slab.Size.X + 0.5), math.floor(slab.Size.Z + 0.5))
	local spec = sizes[key]
	if not spec then
		-- Not a warning. A bubble wrap slab at a size nobody generated a body for still
		-- works -- it falls back to the plain visible slab, which is what it did before
		-- this existed -- so shouting about it would be noise on a working platform.
		return false
	end

	local folder = meshFolder()
	local template = folder and resolveTemplate(folder, "BubbleWrap_Body_" .. key)
	if not template then
		return false
	end

	local body = template:Clone() :: BasePart
	body.Name = "BodyMesh"
	body.Anchored = true
	-- The tiles and their Floor children carry collision, exactly as under a skinned
	-- visual. This is scenery.
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = false
	-- SURFACE_Y is already measured from the slab centre, so this is the same placement
	-- the skinned visuals use.
	body.CFrame = slab.CFrame * CFrame.new(0, SURFACE_Y - spec.offset, 0)
	MaterialAppearance.apply(body, materialName)
	body.Parent = slab

	-- The slab was only visible because it WAS the body. It is not any more.
	slab.Transparency = 1
	for _, child in ipairs(slab:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^CornerBevel") then
			child.Transparency = 1
		end
	end
	return true
end

local function attachShell(slab: BasePart, materialName: string, grid, skinned: boolean)
	-- Every shell authored for this size, then one chosen from them. Two platforms of
	-- the same size sitting next to each other used to carry the SAME fracture, which is
	-- the one thing that gives a generated pattern away however good it is.
	local fits = {}
	for _, candidate in ipairs(WAX_SHELLS[materialName] or {}) do
		if math.abs(slab.Size.X - candidate.sizeX) <= 0.1
			and math.abs(slab.Size.Z - candidate.sizeZ) <= 0.1 then
			table.insert(fits, candidate)
		end
	end

	-- Picked from the slab's own position rather than at random: chunk templates are
	-- built once and cloned, so a random choice would be identical on every copy of a
	-- chunk anyway, while position differs between the slabs WITHIN one.
	local hash = math.abs(math.floor(slab.CFrame.Position.X * 7 + slab.CFrame.Position.Z * 13))
	local spec = if #fits > 0 then fits[hash % #fits + 1] else nil
	-- A 180 degree yaw doubles the number of distinct looks for free. Only 180: the
	-- footprint is a rectangle, so a quarter turn would not line up with the platform.
	local flipped = (#fits > 0) and (math.floor(hash / #fits) % 2 == 1) or false

	local surfaceLocalY = SURFACE_Y - SHELL_THICKNESS / 2
	attachWrapperText(slab, surfaceLocalY, materialName)

	if not spec then
		warnOnce(
			"noshell:" .. tostring(slab.Size),
			("no %s shell authored for a %.0f x %.0f platform. Add the size to SIZES in gen_wax_shell.py, re-run it (and gen_ice_jello.py for the ice copies), then import the mesh; the platform is a bare slab until then."):format(
				materialName, slab.Size.X, slab.Size.Z
			)
		)
		return
	end

	local folder = meshFolder()
	local template = folder and resolveTemplate(folder, spec.mesh)
	if not template then
		return
	end
	if not (template :: any).HasSkinnedMesh then
		warnOnce(
			"waxnotskinned:" .. spec.mesh,
			("'%s' has no skinned mesh data. Re-import the FBX with its armature; without bones the shards cannot separate and the coating is a solid lid."):format(spec.mesh)
		)
		return
	end

	local shell = template:Clone() :: BasePart
	shell.Name = "WaxShell"
	shell.Anchored = true
	-- Collision does not follow a skinned mesh, so this is purely visual; the tile's
	-- Floor child under it is the actual ground, as on every other rigged platform.
	shell.CanCollide = false
	shell.CanTouch = false
	shell.CanQuery = false
	-- Placed by the shell's OWN offset, not by surfaceLocalY. The coating wraps the
	-- sides and the underside now, so its bounding box reaches well below its top face
	-- and the centre is nowhere near the walkable plane. surfaceLocalY still positions
	-- the wrapper text, which does sit in the wax layer.
	shell.CFrame = slab.CFrame
		* CFrame.new(0, SURFACE_Y - spec.surfaceOffset, 0)
		* CFrame.Angles(0, if flipped then math.pi else 0, 0)
	MaterialAppearance.apply(shell, materialName)
	local finish = SHELL_FINISH[materialName] or SHELL_FINISH.ButterWax
	shell.Color = MaterialAppearance.Appearances[materialName].color:Lerp(Color3.new(1, 1, 1), finish.whiten)
	shell.Transparency = finish.transparency
	shell.Reflectance = finish.reflectance
	shell.Parent = slab
end

-- The deformable tile grid. Only ever called with a real material: stable
-- platforms have nothing to deform and get a cap plate instead.
local function buildSubRegions(slab: BasePart, materialName: string)
	local grid = SubRegionGrid.compute(slab.Size.X, slab.Size.Z)
	local seam = if CONTINUOUS[materialName] then 0 else nil

	-- THE OUTLINE AT CELL RESOLUTION, for the two forms that build one part per cell.
	--
	-- Granules test every cube against the shape, so their outline is as fine as the cube
	-- grid -- eighteen across on a typical slab. A bricked or capped platform has ONE part
	-- per cell and the finest cut it can make is a whole cell, at most six across.
	--
	-- That is a limitation for a heart and exactly right for the two materials that have it.
	-- A lego shape IS pixelated: real plates are a grid of studs and anything built out of
	-- them steps in whole bricks. A keypad is the same argument -- buttons sit on a pitch,
	-- and a ring of them is a ring of whole buttons or it is not a keypad.
	local form = slab:GetAttribute("Form") :: string?
	-- RESOLVED ONLY FOR THE MATERIALS THAT CUT ONE, because `form` means two different
	-- things. On a parts-built platform it names a function in PlanShapes; on a rigged one it
	-- names an FBX variant -- "crater", "dune", bubble wrap's "giant" -- and asking PlanShapes
	-- for those produced a startup warning per rigged form for a lookup nothing wanted.
	local cuts = GRANULAR[materialName] or BRICKED[materialName]
	local outline = if form ~= nil and cuts then PlanShapes.get(form) else nil
	local function cellInside(col: number, row: number): boolean
		if not outline then
			return true
		end
		return outline((col - 0.5) / grid.cols * 2 - 1, (row - 0.5) / grid.rows * 2 - 1)
	end

	-- Attempted first: when a skinned mesh takes over, the tiles become pure
	-- invisible colliders and must not also carry per-tile meshes.
	local skinnedSpec = attachSkinnedVisual(slab, materialName)
	local skinned = skinnedSpec ~= nil

	for col = 1, grid.cols do
		for row = 1, grid.rows do
			local cf, size = SubRegionGrid.getRegionCFrame(slab.CFrame, grid, col, row, seam)
			local tile = Instance.new("Part")
			tile.Name = ("SubRegion_%d_%d"):format(col, row)
			tile.Anchored = true
			tile.CanCollide = true
			tile.CanTouch = true
			tile.Size = Vector3.new(size.X, TILE_THICKNESS, size.Z)
			-- HOW FAR THIS CELL SITS BELOW THE WALKABLE PLANE. See SkinnedSpec.drops: the
			-- plane is the mesh's high point, so a cell over a valley has to come down to
			-- the surface or you stand on air above it.
			--
			-- Applied to the TILE, which carries the Floor child copied from its CFrame
			-- below, so the collider and the sensor move together. They have to: a sensor
			-- left up at the plane would report footsteps from above the floor.
			local drop = 0
			if skinnedSpec and skinnedSpec.drops then
				drop = skinnedSpec.drops[(row - 1) * grid.cols + col] or 0
			end

			-- Local-space offset, not world Y: the ramp's slab is pitched, and a
			-- world-Y offset would float its tiles off the slope.
			tile.CFrame = cf * CFrame.new(0, SLAB_THICKNESS / 2 + TILE_THICKNESS / 2 + drop, 0)
			MaterialAppearance.apply(tile, materialName)
			tile:SetAttribute("Col", col)
			tile:SetAttribute("Row", row)
			tile.Parent = slab

			-- A BRICKED TILE IS INVISIBLE BUT STILL THE FLOOR.
			--
			-- Tiles are created with the material's own colour on them, and until now the
			-- only thing that ever hid one was being on a skinned platform. Lego stopped
			-- being skinned, so its tile grid stayed visible -- a flat coloured panel per
			-- cell sitting exactly at the walkable plane, capping the studs underneath it.
			-- That is the smooth top with no studs on it: not a brick at all, but the
			-- sensor grid painted red.
			--
			-- It keeps CanCollide, unlike the skinned case. There is no separate Floor
			-- child here and nothing moves this tile, so it can safely be both the collider
			-- and the sensor -- the oscillation the skinned path splits them to avoid comes
			-- from MOVING a part that senses touch, and this one never moves.
			if BRICKED[materialName] then
				tile.Transparency = 1
			end

			if skinned then
				-- On a skinned platform the tile becomes a pure SENSOR: invisible,
				-- non-colliding, and never moved. A separate Floor child carries
				-- collision and is what the renderer sinks.
				--
				-- They must be separate parts. A part that both senses touch and
				-- collides cannot be moved under a standing player without re-firing
				-- Touched/TouchEnded as the contact manifold shifts. A spurious
				-- TouchEnded then commits an exit, the cell reports decaying, the
				-- collider returns to rest, that re-contacts the player, and it
				-- presses again: a self-sustaining oscillation that floods the
				-- DeformationUpdate remote with two events per cycle per cell.
				tile.Transparency = 1
				tile.CanCollide = false

				local floor = Instance.new("Part")
				floor.Name = "Floor"
				floor.Size = tile.Size
				floor.CFrame = tile.CFrame
				floor.Anchored = true
				floor.CanCollide = true
				floor.CanTouch = false
				floor.CanQuery = false
				floor.CastShadow = false
				floor.Transparency = 1
				floor.Parent = tile
			end

			-- Deliberately NOT chained onto the `skinned` branch above. Butter-wax is
			-- both: a skinned butter body AND a wax shell laid over it. Every other
			-- material picks one visual, so this used to be one if/elseif chain and a
			-- skinned platform never got its shell.
			local inside = cellInside(col, row)

			if BRICKED[materialName] then
				if inside then
					attachBrick(tile, slab, materialName, col, row, grid.cols, grid.rows)
				else
					-- A REAL HOLE. On a bricked platform the bricks are the only thing you
					-- can see and the tile is the only thing you can stand on, so a cell
					-- with neither has to stop being floor AND stop being a sensor --
					-- otherwise you get a cell that reports footsteps from thin air.
					tile.CanCollide = false
					tile.CanTouch = false
				end
			end

			if CAPPED[materialName] then
				-- NOT CUT TO THE OUTLINE, and this used to be. A form on buttons ran the
				-- same PlanShapes test soap and lego use and skipped the caps it fell
				-- outside -- but the plate underneath is a rigged mesh that stays a full
				-- rectangle, so nothing about the PLATFORM changed. All it did was leave
				-- gaps in a keypad, which is not a variation on a keypad.
				--
				-- Keypads vary by DENSITY instead: capDiv comes off the mesh spec, so the
				-- caps sit on exactly the sub-lattice the wells were cut on.
				local div = if skinnedSpec then skinnedSpec.capDiv or 1 else 1
				attachCap(tile, slab, div, col, row, grid.cols)
			end

			if GRANULAR[materialName] then
				-- Read off the SLAB, not off `spec`. `spec` here is the skinned-mesh spec,
				-- which is nil for every granular material -- soap has no rig -- so
				-- reaching for a field on it would throw on the one path that needs it.
				attachGranules(tile, materialName, col, row, grid.cols, grid.rows, form)
			elseif not skinned and not SHELLED[materialName] and not BRICKED[materialName] then
				-- BRICKED IS EXCLUDED, and it had to be added the moment lego stopped being
				-- a skinned mesh. This branch is the per-tile fallback: a material with no
				-- surface of its own gets one small mesh per cell, named <Material>_Tile.
				-- Lego has no such mesh and never will -- its cell already carries a whole
				-- brick built out of parts -- so the fallback fired anyway and spent every
				-- build asking for a 'Lego_Tile' that does not exist.
				--
				-- Harmless in the sense that nothing broke, which is exactly why it is worth
				-- fixing: a warning that appears on every launch and never matters teaches
				-- people to skim past the ones that do.
				attachMeshVisual(tile, materialName, col, row, grid.cols, grid.rows)
			end
		end
	end
	-- AFTER the tile loop, not inside it: the wax partition covers the whole platform at
	-- once and needs every cell to exist before it can hand shards out to them.
	if SHELLED[materialName] then
		attachShell(slab, materialName, grid, skinned)
	end

	-- Per SLAB, not per cell: twenty emitters on one platform is twenty times the drips
	-- and twenty times the cost, for an effect whose whole character is that it is sparse.
	attachAmbient(slab, materialName)

	-- After the sheet, so the sheet's own placement has already run and this only replaces
	-- what is under it.
	attachBodyMesh(slab, materialName)

	slab:SetAttribute("GridCols", grid.cols)
	slab:SetAttribute("GridRows", grid.rows)
end

-- Flat inset cap for stable platforms, so they read as the same construction
-- as material platforms without carrying triggers or deformation state.
local function buildStableCap(slab: BasePart)
	local cap = Instance.new("Part")
	cap.Name = "SurfaceCap"
	cap.Anchored = true
	cap.CanCollide = true
	cap.CanTouch = false
	cap.Size = Vector3.new(slab.Size.X - CAP_INSET * 2, CAP_THICKNESS, slab.Size.Z - CAP_INSET * 2)
	cap.CFrame = slab.CFrame * CFrame.new(0, SLAB_THICKNESS / 2 + CAP_THICKNESS / 2, 0)
	MaterialAppearance.apply(cap, nil)
	cap.Parent = slab
end

-- Builds one platform: base slab, attributes, bevels, and top surface.
-- `noBevel` suppresses the corner wedges. Used for the interior pieces of a
-- tapered run, whose end faces are internal to the platform: bevelling those
-- scatters wedges across the middle of a continuous surface instead of softening
-- the silhouette, which is the only thing the bevels are for.
local function makePlatform(
	model: Model,
	name: string,
	sizeX: number,
	sizeZ: number,
	materialName: string?,
	cframe: CFrame,
	noBevel: boolean?,
	form: string?
): BasePart
	local slab = Instance.new("Part")
	slab.Name = name
	slab.Size = Vector3.new(sizeX, SLAB_THICKNESS, sizeZ)
	slab.Anchored = true
	slab.CFrame = cframe
	MaterialAppearance.applyBase(slab, materialName)

	if materialName then
		slab:SetAttribute("Material", materialName)
		slab:SetAttribute("Materials", materialName)
		-- The outline this platform is cut to, if the chunk asked for one. An attribute
		-- rather than a parameter passed down because buildSubRegions is reached from
		-- several places and only sees the slab.
		if form then
			slab:SetAttribute("Form", form)
		end
	end
	slab.Parent = model

	if not noBevel then
		addCornerBevels(slab, materialName)
	end
	if materialName then
		buildSubRegions(slab, materialName)
	else
		buildStableCap(slab)
	end

	-- ANY PLATFORM THAT CAN OPEN A HOLE IN ITSELF has to give up its slab as floor.
	--
	-- Keyed on the material having a `dissolveTime`, which is the same field that opens
	-- the hole, so the two cannot drift apart. It used to be keyed on GRANULAR, which was
	-- true of soap alone -- and when sand learned to collapse, its cells stopped
	-- colliding while the slab underneath did not. The slab's top face sits 0.9 studs
	-- below the walkable plane, so a player over a "hole" fell that 0.9 and landed on
	-- solid concrete: standing on nothing, in mid-air, exactly as reported.
	-- EVERY WAY A CELL CAN OPEN, not only the clock. Ash from charcoal, a hole in oobleck, a torn clay
	-- lip and a sunk salt plate are holes too, and a slab that still collided under any of them was a
	-- 0.9-stud step down onto concrete.
	local holeDef = if materialName then MaterialConfig.Materials[materialName] else nil
	local dissolves = holeDef ~= nil
		and (holeDef.dissolveTime ~= nil or holeDef.stepsToCollapse ~= nil or holeDef.displacement ~= nil
			or holeDef.wadeStill ~= nil or holeDef.igniteAfter ~= nil)
	--
	-- A SHAPED BRICKED PLATFORM JOINS THEM, and for exactly the reason above. Cutting cells
	-- out of a lego plate leaves the slab as the only thing under the gap, and a player over
	-- a "hole" would fall 0.9 studs and land on solid concrete -- standing in mid-air, which
	-- is the same bug sand hit, arrived at from a different direction.
	local shapedBrick = form ~= nil and materialName ~= nil and BRICKED[materialName]
	if materialName and (GRANULAR[materialName] or dissolves or shapedBrick) then
		slab.CanCollide = false
	end
	-- BRICKED joins GRANULAR here. Both build their whole visual out of parts, so the slab
	-- is a carrier and its corner bevels are wedges shaped for a platform nobody can see --
	-- which is what those stray triangles at the corners of the lego chunk were.
	if materialName and (GRANULAR[materialName] or BRICKED[materialName]) then
		slab.Transparency = 1
		for _, child in ipairs(slab:GetChildren()) do
			if child:IsA("BasePart") and child.Name:match("^CornerBevel") then
				child.Transparency = 1
			end
		end
	end
	return slab
end

local function buildConnectionAttachments(slab: BasePart, connections: { string })
	local halfX, halfZ = slab.Size.X / 2, slab.Size.Z / 2
	local offsets: { [string]: Vector3 } = {
		south = Vector3.new(0, 0, -halfZ),
		north = Vector3.new(0, 0, halfZ),
		east = Vector3.new(halfX, 0, 0),
		west = Vector3.new(-halfX, 0, 0),
	}
	for _, dir in ipairs(connections) do
		local offset = offsets[dir]
		if offset then
			local att = Instance.new("Attachment")
			att.Name = "Connection_" .. dir
			att.Position = offset
			att.Parent = slab
		end
	end
end

-- Publishes the placement contract LevelService/ChunkService rely on.
local function finalize(model: Model, primary: BasePart, length: number, rise: number)
	model.PrimaryPart = primary
	model:SetAttribute("EntryZ", 0)
	model:SetAttribute("EntrySurfaceY", SURFACE_Y)
	model:SetAttribute("Rise", rise)
	model:SetAttribute("Length", length)
end

-- === Silhouette ===
--
-- Every chunk used to be a 16-wide rectangle, so a level read as one corridor of
-- identical boxes no matter which materials were in it. Two additions give a chunk
-- a shape of its own: a width that walks along the run (`widthEnd`) and lateral
-- tiers alongside it (`shelf`). Both only ever add or resize slabs BETWEEN the
-- entry and exit faces, so neither touches the placement contract: EntryZ,
-- EntrySurfaceY, Rise and Length are unchanged by either.
--
-- Two rules constrain every silhouette authored below.
--
-- 1. ENTRY AND EXIT FACES STAY WIDE AND CENTRED ON X = 0. Chunks are islands
--    separated by CHUNK_GAP, so both faces are jump targets and LevelService
--    always leaves from and arrives at the centre line. Narrowing belongs in the
--    middle of a chunk, never at its ends; nothing here goes below 10 studs at a
--    face, against a character roughly 2 wide.
--
-- 2. NEVER TAPER HONEY OR SLIME. A tapered run is several slabs, so it gets
--    several sub-region grids. That is invisible on granular materials, but honey
--    and slime tiles are edge-matched (see CONTINUOUS): a new grid is a new
--    platform boundary, and a boundary draws a meniscus lip straight across the
--    middle of what should be one unbroken pour. taperGuard warns rather than
--    letting that happen quietly.

-- A tapered run is approximated by rectangles, so the piece count trades
-- silhouette smoothness against cell shape: more pieces means a finer taper but
-- shorter ones, and SubRegionGrid floors to MIN_CELLS below about 5 studs, past
-- which cells stop being roughly square and any tile mesh on them is squashed
-- along Z. Deriving the count from the length rather than fixing it keeps pieces
-- near that bound whatever the segment measures.
--
-- 4 studs sits deliberately UNDER the bound, because the constraint only binds on
-- material segments: stable platforms get a single cap plate and no grid at all,
-- and the meshless materials carry no tile mesh to squash, so on those a short
-- piece costs nothing but a slightly oblong seam. Soap is the one tapered
-- material with a mesh, and it overrides taperPieces instead of paying for this.
local TAPER_PIECE_LENGTH = 4.0
local TAPER_MIN_PIECES, TAPER_MAX_PIECES = 2, 6

-- Lateral tiers. A shelf is a slab running alongside the main one, dropped by
-- `drop` studs, which turns a flat rectangle into a stepped cross-section. At
-- drop = STEP_RISE it is walkable in both directions without jumping, so on a risk
-- chunk a shelf is a genuine run-off lane and on a stable one it is pure profile.
-- Shelves follow a taper: their inner edge is placed off the piece they sit beside,
-- so a narrowing run pulls its shelves inward with it.
type Shelf = {
	width: number,
	drop: number?,
	gap: number?,
	material: string?,
	sides: string?, -- "both" (default) | "west" | "east"
}

-- === Linear chunks ===
-- A segment list walked along +Z. `gap` inserts empty space (a jump). `rise`
-- raises the running surface height before the segment is placed. `sameZ`
-- places the segment beside the previous one instead of after it. `widthEnd`
-- tapers the segment from `width` to `widthEnd` across its length.
type Segment = {
	name: string,
	material: string?,
	width: number?,
	widthEnd: number?,
	taperPieces: number?,
	length: number?,
	gap: number?,
	rise: number?,
	sameZ: boolean?,
	offsetX: number?,
	shelf: Shelf?,
	-- The outline this segment is cut to. It was read off `seg` before it was ever declared
	-- here, which type-checks as `any` and means a typo in a chunk recipe -- `from` for
	-- `form` -- reads as nil and builds a plain platform rather than failing.
	form: string?,
}

local function taperGuard(seg: Segment)
	if seg.material and CONTINUOUS[seg.material] then
		warnOnce(
			"taper:" .. seg.name,
			("segment '%s' tapers a continuous material (%s). Its tiles are edge-matched, so each taper piece draws a meniscus lip across the middle of the surface. Build the taper out of a neighbouring stable segment instead."):format(
				seg.name,
				seg.material
			)
		)
	end
end

local function buildShelf(
	model: Model,
	seg: Segment,
	label: string,
	y: number,
	zCentre: number,
	length: number,
	mainWidth: number,
	offsetX: number
)
	local shelf = seg.shelf
	if not shelf then
		return
	end
	local sides = shelf.sides or "both"
	local dx = mainWidth / 2 + (shelf.gap or 0.4) + shelf.width / 2
	local shelfY = y - (shelf.drop or STEP_RISE)

	for _, side in ipairs({ "west", "east" }) do
		if sides == "both" or sides == side then
			local sign = if side == "west" then -1 else 1
			makePlatform(
				model,
				("%sShelf_%s%s"):format(seg.name, side == "west" and "W" or "E", label),
				shelf.width,
				length,
				shelf.material,
				CFrame.new(offsetX + sign * dx, shelfY, zCentre)
			)
		end
	end
end

local function buildLinear(model: Model, segments: { Segment }): (BasePart, number, number)
	local z = 0
	local y = 0 -- running slab-centre height
	local primary: BasePart? = nil
	local lastLength = 0

	for _, seg in ipairs(segments) do
		if seg.gap then
			z += seg.gap
			continue
		end
		if seg.rise then
			y += seg.rise
		end

		local width = seg.width or PATH_WIDTH
		local length = seg.length or 12
		local offsetX = seg.offsetX or 0
		local zStart = seg.sameZ and (z - lastLength) or z

		local pieces = 1
		if seg.widthEnd and math.abs(seg.widthEnd - width) > 0.01 then
			taperGuard(seg)
			pieces = seg.taperPieces
				or math.clamp(
					math.floor(length / TAPER_PIECE_LENGTH + 0.5),
					TAPER_MIN_PIECES,
					TAPER_MAX_PIECES
				)
		end

		local pieceLength = length / pieces
		for i = 1, pieces do
			-- Sampled so the FIRST piece is exactly `width` and the LAST is exactly
			-- `widthEnd`. Sampling at piece centres instead looks more natural on
			-- paper but never realises either authored number -- a 16 -> 11 run in
			-- two pieces comes out 14.75 -> 12.25 -- which quietly weakens every
			-- taper and, worse, silently narrows entry and exit faces that rule 1
			-- says are jump targets. The authored widths have to mean what they say.
			local t = if pieces > 1 then (i - 1) / (pieces - 1) else 0
			local pieceWidth = width + ((seg.widthEnd or width) - width) * t
			local zCentre = zStart + (i - 0.5) * pieceLength
			local name = if pieces == 1 then seg.name else ("%s_%d"):format(seg.name, i)
			local interior = pieces > 1 and i > 1 and i < pieces

			local slab = makePlatform(
				model,
				name,
				pieceWidth,
				pieceLength,
				seg.material,
				CFrame.new(offsetX, y, zCentre),
				interior,
				-- Only a single-piece segment gets a shape. A shape is normalised over one
				-- slab, so applying it to each piece of a split segment would stamp three
				-- small hearts in a row rather than one large one -- and the pieces exist
				-- precisely because the segment was too long to be one slab.
				if pieces == 1 then seg.form else nil
			)
			primary = primary or slab

			buildShelf(
				model,
				seg,
				if pieces == 1 then "" else ("_%d"):format(i),
				y,
				zCentre,
				pieceLength,
				pieceWidth,
				offsetX
			)
		end

		if not seg.sameZ then
			z += length
			lastLength = length
		end
	end

	return primary :: BasePart, z, y
end

local LinearChunks: { [string]: { Segment } } = {
	-- Stable chunks are the rest beats and the only place LevelService applies an
	-- elevation step, so their variety has to be profile only: never narrow the
	-- walking line, never introduce a gap. Flanking shelves do exactly that. The
	-- route through the middle is the same flat 16 studs it always was; the
	-- cross-section is a stepped plateau instead of a slab.
	S1_Straight = {
		{ name = "Platform", length = 20, shelf = { width = 5, drop = STEP_RISE } },
	},
	-- SIZE-LOCKED at 16 x 18. This is the one platform Honey_Platform_Skinned is
	-- rigged for (see SKINNED_PLATFORMS), and a rig cannot be resized: setting Size
	-- moves the rendered mesh but leaves every Bone where it was. So the honey slab
	-- is untouchable, and the variety is bought entirely OUTSIDE its footprint.
	-- Shelves are separate slabs, so the lock holds and the corridor now reads as
	-- honey pooled in a channel between two lower ledges.
	P1_HoneyCorridor = {
		{ name = "Platform", material = "Honey", length = 18, shelf = { width = 4, drop = STEP_RISE } },
	},
	-- SHAPED LIKE A BAR OF SOAP: widest through the middle, both ends drawn in.
	--
	-- This used to pinch to an 8-wide waist, which is the same silhouette upside down
	-- -- an hourglass, and from above an I-beam. That came from treating the chunk as
	-- a "pinched bridge" for tension, back when soap had no form of its own. Now that
	-- the material is a pressed bar, the platform is the shape of the thing.
	--
	-- ONE slab, and the ROUNDING IS DONE BY THE CUBES (see GRANULE_ROUND), not by the
	-- segment list. A taper cannot round anything: pieces have to stay about 5 studs
	-- long or the cubes they carry come out under half a stud, so a 20-stud span gets
	-- four pieces at most and 11 -> 14 -> 14 -> 11 reads as a cross, not a bar.
	--
	-- A granular platform can round its own outline at CUBE resolution instead, which
	-- is both finer than any taper and free. It also means this chunk gets its variety
	-- from the material's form rather than from a silhouette imposed on it.
	-- PLAIN, and it stays plain. The shaped soaps below are ADDITIONS -- giving the one
	-- existing soap chunk a heart replaced the ordinary bar rather than adding to the set,
	-- so a run had three shaped soaps in it and no plain one.
	R2_SoapBridge = {
		{ name = "Platform", material = "Soap", width = 14, length = 20 },
	},
	R6_SoapHeart = {
		{ name = "Platform", material = "Soap", width = 18, length = 22, form = "heart" },
	},
	-- The same platform in two other outlines. All three cost exactly one word in this
	-- table, because a granular platform's shape IS its cube-placement test -- there is no
	-- mesh to author, size-lock or re-import. This is the only material that can do it.
	-- 22 WIDE, and it used to be 18. One of the star's five points lands on the exit centre
	-- line, so the last cubes on the platform are the tip of that point -- and the wider the
	-- slab, the more studs those same few cubes are worth. Blunting the point (see the
	-- exponent in PlanShapes) did the other half; between them the exit went from 2 studs to
	-- nearly 4.
	R4_SoapStar = {
		{ name = "Platform", material = "Soap", width = 22, length = 22, form = "star" },
	},
	-- Three discs with narrow waists between them, so crossing it is a route rather than a
	-- walk. The shape is doing gameplay work here, not only decoration.
	R5_SoapPebbles = {
		{ name = "Platform", material = "Soap", width = 12, length = 22, form = "pebbles" },
	},
	-- THE ONE WITH A HOLE IN IT. The middle of this platform is open air down to the sea,
	-- because the slab under a granular chunk does not collide -- so the shape is not a
	-- silhouette here, it is the level.
	--
	-- 18 wide rather than 16 for a reason the checker supplies: the band each side of the
	-- hole is 0.56 of the half-width, which is 5 studs at 18 and only 4.4 at 16.
	R18_SoapRing = {
		{ name = "Platform", material = "Soap", width = 18, length = 20, form = "ring" },
	},
	-- The only chunk in the game that makes you TURN. The lane snakes a full 0.55 of the
	-- half-width to each side and comes back to the middle at both faces, so it enters and
	-- leaves square with its neighbours however much it wanders in between.
	R19_SoapWave = {
		{ name = "Platform", material = "Soap", width = 18, length = 22, form = "wave" },
	},
	-- Two landings and a beam. Pebbles is the gentle version of this idea; here the waist is
	-- 0.20 of the half-width, which at 18 studs is 3.6 -- just over the 3.4 a character can
	-- walk, and deliberately close to it.
	R20_SoapBone = {
		{ name = "Platform", material = "Soap", width = 18, length = 22, form = "bone" },
	},
	-- FIRST OF THE GRAIN CHUNKS, and the pair below is the argument for grain existing:
	-- three platforms of the same material, at the same size, that do not look alike.
	--
	-- Rubble. Four pieces to a cell instead of nine, a deep broken rim, and enough rotation
	-- and height variation that the top face is visibly uneven -- a bar that has been
	-- dropped rather than pressed. The crescent's bite suits it: both say "damaged".
	R21_SoapCrescent = {
		{ name = "Platform", material = "Soap", width = 18, length = 20, form = "crescent" },
	},
	-- The one outline in the file that is nothing but two long curves, so it is the one that
	-- most wants the finest grain available -- which is now the default, because finer than
	-- that was not affordable.
	R31_SoapLeaf = {
		{ name = "Platform", material = "Soap", width = 18, length = 22, form = "leaf" },
	},
	-- THE SAME TRICK ON LEGO, and the resolution is the whole story.
	--
	-- A granular platform tests every cube against the shape and gets an outline eighteen
	-- steps across. Lego has ONE brick per cell, so the finest cut it can make is a whole
	-- cell -- six across at this size. A heart at six steps is a blob; a cross and a hole
	-- are unmistakable, so those are the two lego gets and the rest stay with soap.
	--
	-- It is also the right limitation for the material. Real plates are a grid of studs and
	-- anything built out of them steps in whole bricks, so a pixelated lego shape is not a
	-- compromise -- it is what lego looks like.
	--
	-- 20 WIDE, NOT 16, and the difference is a whole brick. At 16 the grid comes out five
	-- cells across, the middle lane of the cross is the one centre cell, and that is 3.2
	-- studs -- under what a character can walk. Six cells puts TWO in the middle and the
	-- lane doubles to 6.7.
	R23_LegoCross = {
		{ name = "Platform", material = "Lego", width = 20, length = 20, form = "cross" },
	},
	-- A lego plate with a 2 x 2 brick hole punched through the middle. Same outline as the
	-- soap ring and a completely different thing to cross, because the pieces are the size
	-- of the hole rather than a fraction of it.
	R24_LegoRing = {
		{ name = "Platform", material = "Lego", width = 20, length = 20, form = "ring" },
	},
	-- === KEYPADS ===
	--
	-- A keypad varies by DENSITY, not by outline, and the three chunks that used to sit here
	-- proved why. They ran the same PlanShapes test soap and lego use and skipped the caps
	-- that fell outside it -- but the plate underneath is a rigged mesh that stays a full
	-- rectangle whatever the outline says, so nothing about the platform changed shape. All
	-- it did was leave gaps in a keypad, and a keypad with buttons missing is not a variation
	-- on a keypad.
	--
	-- Four buttons to a cell instead of one, on the sub-lattice the mesh cuts its wells on.
	-- Eighty whole buttons, even spacing, symmetric about the centre, edge to edge.
	P14_ButtonDense = {
		{ name = "Platform", material = "Buttons", length = 12, form = "dense" },
	},
	-- And a plate that IS a different shape, with its buttons still complete and still
	-- symmetric. They ride the dome because each cap sits on its cell's collider and the
	-- collider now follows the mesh -- see SkinnedSpec.drops.
	P15_ButtonDome = {
		{ name = "Platform", material = "Buttons", length = 12, form = "dome" },
	},
	-- === THE TWO THAT POUR ===
	--
	-- Honey and slime predate the shared bed pipeline and have their own generators, so these
	-- four took a hook in each rather than a row in a table. The SCULPTS themselves are the
	-- same ones the beds use: a sculpt is a pure height function of x and y and knows nothing
	-- about the surface it lands on, so there is one vocabulary and every generator draws
	-- from it.
	--
	-- All four are 16 x 12, the size both rigs already exist at.
	P18_HoneyComb = {
		{ name = "Platform", material = "Honey", length = 12, form = "comb" },
	},
	P19_HoneyPool = {
		{ name = "Platform", material = "Honey", length = 12, form = "pool" },
	},
	R37_SlimeBlister = {
		{ name = "Platform", material = "Slime", length = 12, form = "blister" },
	},
	R38_SlimeChannel = {
		{ name = "Platform", material = "Slime", length = 12, form = "channel" },
	},
	-- === SCULPTED RIGS ===
	--
	-- The other half of the shape system, and the half that needs an FBX.
	--
	-- Soap, lego and buttons cut their outline out of a field of parts, so a shape there is
	-- one word and no asset. Every material below is a SKINNED MESH: one rig covering the
	-- whole slab, bones matched to cells by position, size-locked to the dimensions it was
	-- authored at. Cutting a plan out of one is not possible -- the mesh does not collide,
	-- the slab does, so a cut-out shape would leave you walking on air around it.
	--
	-- So the shape lives in the RELIEF instead, exactly as the sand turtle does. The bed
	-- stays a full rectangle underfoot and the form is a sculpture standing on it, which is
	-- what these things are anyway: nobody cuts a crater-shaped hole in a lava field.
	--
	-- ALL SIZE-LOCKED at 16 x 12, the size their plain rigs already exist at. Change either
	-- number and the material silently drops to per-tile fallback; check_chunk_forms catches
	-- that, which is why it exists.
	R32_LavaVent = {
		{ name = "Platform", material = "Lava", length = 12, form = "crater" },
	},
	R33_ChocolateSwirl = {
		{ name = "Platform", material = "Chocolate", length = 12, form = "swirl" },
	},
	R34_SnowDrift = {
		{ name = "Platform", material = "Snow", length = 12, form = "dune" },
	},
	P17_ClayTerrace = {
		{ name = "Platform", material = "Clay", length = 12, form = "terrace" },
	},
	R35_CharcoalSpine = {
		{ name = "Platform", material = "Charcoal", length = 12, form = "ridge" },
	},
	R36_CloudSwell = {
		{ name = "Platform", material = "Cloud", length = 12, form = "mound" },
	},

	-- TWO MORE AT BRICK RESOLUTION, and both were picked by measuring rather than by taste.
	-- Of the fourteen outlines, only six survive being cut six steps across with a crossing
	-- left in them, and of those six the heart, circle and cog all collapse into the same
	-- rounded square. A dumbbell and a C are what is actually left.
	R29_LegoBone = {
		{ name = "Platform", material = "Lego", width = 20, length = 20, form = "bone" },
	},
	R30_LegoCrescent = {
		{ name = "Platform", material = "Lego", width = 20, length = 20, form = "crescent" },
	},
	-- The same idea carried to the two materials that CANNOT do it the cheap way.
	--
	-- Soap gets a shape for one word because it is granular: the outline is the
	-- cube-placement test. Sand and bubble wrap are skinned meshes, so their shape is
	-- baked into an FBX at import time -- which means a form here is a whole new mesh,
	-- and the platform has to be ONE slab or the shape gets cut in half at the join.
	-- That is why both are square-ish and untapered: a taper is sliced into 4-stud
	-- pieces, and a turtle sawn into three strips is not a turtle.
	--
	-- The sand turtle is SCULPTED, not cut out. The slab underneath is what you stand
	-- on (`CanCollide` is false on every mesh here), so cutting a turtle silhouette out
	-- of the plan would leave you walking on air around the flippers. A sand turtle on
	-- a beach is a sculpture in a flat bed anyway, so the shape lives in the relief and
	-- the platform stays a full rectangle underfoot.
	-- ONE SLAB, UNTAPERED, like every other rigged form -- but here it is the LATTICE
	-- that needs it rather than a silhouette. Keys sit on a fixed pitch anchored to the
	-- mesh origin, so two slabs of different widths still agree about where a key goes;
	-- a taper sliced into 4-stud pieces would be fine for the grid and wrong for the
	-- read, since each piece would carry two rows and the platform would look like a
	-- stack of narrow keyboards rather than one.
	--
	-- SQUARE, AND THAT IS WHAT LETS THE CAPS FILL IT.
	--
	-- At 14 x 16 the field could not fill both axes at once: with square caps and one gap
	-- size, the two axes want different cap widths, so whichever is chosen leaves the
	-- other short and the difference shows up as an asymmetric bezel -- a wide empty
	-- border down two sides. A square slab makes both axes agree exactly, so a 5 x 5 grid
	-- of 2.8-stud caps reaches the same 0.3 bezel all the way round.
	-- SIZED TO THE RIGS IT BORROWS. 16 x 8 then 12 x 10 are exactly the two slab sizes
	-- the wax shell and butter body already exist at, so this chunk is playable with the
	-- meshes already imported. Change either number and ice silently drops to per-tile
	-- fallback -- check_chunk_forms.py catches that, which is why it exists.
	R9_IceCrack = {
		{ name = "Platform", material = "Ice", length = 8 },
		{ name = "Shelf", material = "Ice", width = 12, length = 10 },
	},
	P11_SaltFlat = {
		{ name = "Platform", material = "Salt", length = 12 },
	},
	P12_ButtonPad = {
		{ name = "Platform", material = "Buttons", length = 12 },
	},
	R15_LavaCrust = {
		{ name = "Platform", material = "Lava", length = 12 },
	},
	R16_Oobleck = {
		{ name = "Platform", material = "Oobleck", length = 12 },
	},
	R17_MeltingSnow = {
		{ name = "Platform", material = "Snow", length = 12 },
	},
	-- All seven new beds are ONE 16 x 12 platform, the shape P6_JelloSoda already connects
	-- at, so the level generator needs no new case for any of them.
	R14_ChocolateSnap = {
		{ name = "Platform", material = "ChocolateSolid", length = 12 },
	},
	P8_Foam = {
		{ name = "Platform", material = "Foam", length = 12 },
	},
	P9_LightSwitches = {
		{ name = "Platform", material = "LightSwitch", length = 12 },
	},
	P10_ClayPress = {
		{ name = "Platform", material = "Clay", length = 12 },
	},
	R10_LegoStuds = {
		{ name = "Platform", material = "Lego", length = 12 },
	},
	R11_CharcoalSnap = {
		{ name = "Platform", material = "Charcoal", length = 12 },
	},
	R12_ChocolateMelt = {
		{ name = "Platform", material = "Chocolate", length = 12 },
	},
	R13_CloudSink = {
		{ name = "Platform", material = "Cloud", length = 12 },
	},
	-- SIZED TO ITS OWN RIGS, 16 x 8 then 12 x 10, which is also butter's and ice's pair.
	-- Sharing the sizes is not sharing the mesh -- lamb's ear has its own, because a leaf
	-- bed is nothing like a slab of butter -- but it does mean the shelf-after-platform
	-- shape is one the level already knows how to connect.
	P7_LambsEar = {
		{ name = "Platform", material = "LambsEar", length = 8 },
		{ name = "Shelf", material = "LambsEar", width = 12, length = 10 },
	},
	-- 16 x 12, matching slime's rig for the same reason.
	P6_JelloSoda = {
		{ name = "Platform", material = "JelloSoda", length = 12 },
	},
	P5_KeyboardRun = {
		{ name = "Platform", material = "CreamyKeyboard", width = 16, length = 16 },
	},
	-- The imported asset-pack chunks. The keyboard palettes are an existing rig that
	-- ChunkProps recolours; the Needoh field is not, any more -- it is its own material on
	-- its own skinned mesh, which is why nothing dresses it.
	P20_NeedohField = {
		{ name = "Platform", material = "Needoh", length = 12 },
	},
	P25_ButterStick = {
		{ name = "Platform", material = "ButterStick", length = 12 },
	},
	P26_NeedohBoulders = {
		{ name = "Platform", material = "Needoh", length = 12, form = "boulders" },
	},
	P27_NeedohGrid = {
		{ name = "Platform", material = "Needoh", length = 12, form = "grid" },
	},
	P28_NeedohDrift = {
		{ name = "Platform", material = "Needoh", length = 12, form = "drift" },
	},
	P21_KeyboardDusk = {
		{ name = "Platform", material = "CreamyKeyboard", width = 16, length = 16 },
	},
	P22_KeyboardMint = {
		{ name = "Platform", material = "CreamyKeyboard", width = 16, length = 16 },
	},
	P23_KeyboardLava = {
		{ name = "Platform", material = "LavaKeys", width = 16, length = 16 },
	},
	P24_ButterBlocks = {
		{ name = "Platform", material = "ButterWax", width = 16, length = 8 },
	},
	R7_SandTurtle = {
		{ name = "Platform", material = "KineticSand", width = 16, length = 16, form = "turtle" },
	},
	-- Pockets at twice the pitch and twice the radius. Nothing else changes -- the
	-- renderer finds bones by world position, so a different lattice needs no code.
	R8_BubbleWrapGiant = {
		{ name = "Platform", material = "BubbleWrap", width = 16, length = 16, form = "giant" },
	},
	-- Tiered pace chain: you step DOWN off the honey onto the sand rather than
	-- crossing a seam on one flat plane, so the material change is legible before
	-- you feel it. The honey stays 16 x 12, which is deliberately NOT a rig size:
	-- this is the chunk that keeps the per-tile fallback visible in every run.
	P4_PaceChain_H_KS = {
		{ name = "Platform", material = "Honey", length = 12 },
		{
			name = "SandSection",
			material = "KineticSand",
			length = 12,
			rise = -STEP_RISE,
			width = 16,
			widthEnd = 12,
		},
	},
	-- Funnel out. Sand narrows to a neck, then the stable half opens past the
	-- standard corridor width, which reads as arriving somewhere rather than as
	-- more of the same passage.
	C2_PaceToStable = {
		{ name = "Platform", material = "KineticSand", width = 16, widthEnd = 11, length = 12 },
		{ name = "StableSection", width = 11, widthEnd = 20, length = 12 },
	},
	C4_BubbleWrapToStable = {
		{ name = "Platform", material = "BubbleWrap", width = 16, widthEnd = 12, length = 12 },
		-- A step UP onto the landing, so the safe ground is the high ground.
		{ name = "StableLanding", width = 12, widthEnd = 16, length = 12, rise = STEP_RISE },
	},
	-- The launch pad keeps its full width and no shelf: the slime IS the chunk,
	-- and a lane around it would make the launch optional. The shaping goes into
	-- the landing, which is stable and therefore free to taper. Wide where you come
	-- down out of a ~25-stud arc, narrowing back to the corridor once you are safe.
	R1_SlimeLaunch = {
		{ name = "Platform", material = "Slime", length = 12 },
		{ gap = GAP_LENGTH, name = "gap" },
		{ name = "Landing", width = 20, widthEnd = 16, length = 14 },
	},
	-- Same launch, but the honey landing sits a step below the slime, so the arc
	-- ends in a drop onto a slow material. Honey stays 16 x 12 (per-tile fallback,
	-- as in P4).
	--
	-- Both materials here are locked out of tapering -- slime is continuous, and
	-- resizing the honey would cost the fallback comparison -- so this is the one
	-- chunk whose footprint cannot be shaped at all. Shelves are the way in: they
	-- are separate slabs, so they touch neither constraint, and catching a
	-- mistimed landing one step down is exactly what a chunk that ends in a
	-- 25-stud arc should be doing.
	--
	-- The slime pad is 12 long, not the 10 it used to be, so that it matches
	-- R1_SlimeLaunch exactly. Slime_Platform_Skinned is rigged for 16 x 12 and a rig
	-- cannot be resized, so at 10 this chunk would have been the only slime in the
	-- game still falling back to per-tile meshes -- the grid look the rig exists to
	-- remove, showing up on one platform out of two.
	C1_SlimeToPace = {
		{ name = "Platform", material = "Slime", length = 12 },
		{ gap = GAP_LENGTH, name = "gap" },
		{
			name = "HoneyLanding",
			material = "Honey",
			length = 12,
			rise = -STEP_RISE,
			shelf = { width = 4, drop = STEP_RISE },
		},
	},
	-- Each step is its own slab already, so narrowing the climb costs nothing and
	-- turns three identical treads into a ziggurat. 10 at the top is the floor set
	-- by rule 1: it is the exit face.
	R3_BubbleWrapStairs = {
		{ name = "Platform", material = "BubbleWrap", length = 8, width = 16 },
		{ name = "Step2", material = "BubbleWrap", length = 8, width = 13, rise = STEP_RISE },
		{ name = "Step3", material = "BubbleWrap", length = 8, width = 10, rise = STEP_RISE },
	},
	-- Lateral jog rather than the GDD's south-to-east curve. A chunk that exits
	-- east dead-ends the route, because LevelService chains strictly along +Z
	-- and has no notion of facing. Jogging east and back keeps a real
	-- directional bend (which slippery butter-wax wants: you carry sideways
	-- momentum through it) while still entering and exiting on the axis.
	--
	-- The bend is narrowed to 12, which cuts the overlap with the entry slab from
	-- 8 studs to 6 and makes the jog something you have to steer rather than drift
	-- through. The catch shelf is on the OUTSIDE of the bend only: that is the
	-- direction butter-wax throws you, and one step down is a recoverable mistake
	-- where the open air behind it is not.
	P2_ButterWaxCurve = {
		{ name = "Platform", material = "ButterWax", length = 8 },
		{
			name = "BendSection",
			material = "ButterWax",
			length = 10,
			offsetX = 8,
			width = 12,
			shelf = { width = 4, drop = STEP_RISE, sides = "east" },
		},
		{ name = "ExitSection", material = "ButterWax", length = 8 },
	},
	-- Soap spine with stable flanks, so the chunk stays passable once the soap has
	-- dissolved. The flanks used to be full-height sameZ segments, which made three
	-- equal lanes and no reason to take the middle one. Dropping them to real
	-- shelves makes the spine the high road and the flanks the bail-out.
	C3_SoapWithWideLanding = {
		{ name = "Platform", length = 8 },
		{
			name = "SoapSection",
			material = "Soap",
			width = 8,
			length = 12,
			shelf = { width = 5, drop = STEP_RISE },
		},
		{ name = "PostLanding", length = 14 },
	},
}

-- === Special-geometry chunks ===
local specialBuilders: { [string]: (Model) -> () } = {}

-- Sloped ramp, narrowing as it climbs. The slab is pitched about X so its far
-- edge rises; tiles follow the slope because buildSubRegions offsets in the
-- slab's local space.
--
-- Built as a run of pitched pieces rather than one slab, so the width can walk
-- down the climb. A ramp is the one place where narrowing costs nothing in
-- safety -- you are moving in a straight line up a fixed grade with no lateral
-- decision to make -- and it buys the strongest silhouette in the set, because
-- unlike every flat chunk the taper is visible in profile from anywhere on the
-- level rather than only from above.
local RAMP_WIDTH_BOTTOM, RAMP_WIDTH_TOP = PATH_WIDTH, 10
local RAMP_PIECES = 4

specialBuilders["P3_KineticSandRamp"] = function(model: Model)
	local angle = math.atan2(RAMP_RISE, RAMP_RUN)
	local slopeLength = math.sqrt(RAMP_RUN * RAMP_RUN + RAMP_RISE * RAMP_RISE)

	-- Negative X rotation lifts the +Z end: rotating (0,0,1) by theta about X
	-- gives y' = -sin(theta), so theta must be negative for the far end to rise.
	local orient = CFrame.Angles(-angle, 0, 0)

	local first: BasePart? = nil
	local last: BasePart? = nil

	for i = 1, RAMP_PIECES do
		-- Position along the climb, 0 at the entry and 1 at the top. Sampled at the
		-- piece CENTRE here (unlike the flat taper) because this places geometry,
		-- not just a width: the piece has to sit ON the slope, and its midpoint is
		-- the only parameter that puts it there.
		local t = (i - 0.5) / RAMP_PIECES

		-- Centre of this piece's TOP FACE, derived rather than measured. The
		-- walkable height at t is SURFACE_Y + t*RAMP_RISE, and the top face is
		-- TILE_THICKNESS below that, which reduces to SLAB_THICKNESS/2 + t*RAMP_RISE.
		-- At t = 0 that is SLAB_THICKNESS/2, so the entry surface lands on SURFACE_Y
		-- exactly and the ramp meets a flat chunk flush.
		--
		-- The -SLAB_THICKNESS/2 translation is applied AFTER the rotation on
		-- purpose: the slab hangs perpendicular to its own top face, not straight
		-- down, or a pitched piece would sit skewed inside the slope.
		local topCentre = Vector3.new(0, SLAB_THICKNESS / 2 + t * RAMP_RISE, t * RAMP_RUN)
		local cframe = CFrame.new(topCentre) * orient * CFrame.new(0, -SLAB_THICKNESS / 2, 0)

		local width = RAMP_WIDTH_BOTTOM
			+ (RAMP_WIDTH_TOP - RAMP_WIDTH_BOTTOM) * ((i - 1) / (RAMP_PIECES - 1))

		local slab = Instance.new("Part")
		slab.Name = ("Platform_%d"):format(i)
		slab.Size = Vector3.new(width, SLAB_THICKNESS, slopeLength / RAMP_PIECES)
		slab.Anchored = true
		slab.CFrame = cframe
		slab:SetAttribute("Material", "KineticSand")
		slab:SetAttribute("Materials", "KineticSand")
		MaterialAppearance.applyBase(slab, "KineticSand")
		slab.Parent = model
		if i == 1 or i == RAMP_PIECES then
			addCornerBevels(slab, "KineticSand")
		end
		buildSubRegions(slab, "KineticSand")

		first = first or slab
		last = slab
	end

	local entry = first :: BasePart
	buildConnectionAttachments(entry, { "south" })
	buildConnectionAttachments(last :: BasePart, { "north" })
	finalize(model, entry, RAMP_RUN, RAMP_RISE)
end

-- L-shaped junction: main run plus an east arm, with a diagonal fill softening
-- the inner corner.
specialBuilders["S2_Junction"] = function(model: Model)
	local main = makePlatform(model, "Platform", PATH_WIDTH, 20, nil, CFrame.new(0, 0, 10))
	buildConnectionAttachments(main, { "south", "north" })

	local arm = makePlatform(model, "EastArm", 16, 16, nil, CFrame.new(PATH_WIDTH, 0, 12))
	buildConnectionAttachments(arm, { "east" })

	-- West shelf only. The east side of the main run is where the arm attaches, so
	-- a matching shelf there would bury itself inside it. One-sided is also the
	-- better read: the junction's whole point is that it is not symmetric, and a
	-- low ledge opposite the arm says so from the side as well as from above.
	local SHELF_WIDTH, SHELF_GAP = 5, 0.4
	makePlatform(
		model,
		"PlatformShelf_W",
		SHELF_WIDTH,
		20,
		nil,
		CFrame.new(-(PATH_WIDTH / 2 + SHELF_GAP + SHELF_WIDTH / 2), -STEP_RISE, 10)
	)

	local fill = Instance.new("WedgePart")
	fill.Name = "CornerFill"
	fill.Size = Vector3.new(6, SLAB_THICKNESS, 6)
	fill.Anchored = true
	fill.CanCollide = true
	fill.CFrame = CFrame.new(PATH_WIDTH / 2 + 2, 0, 3) * CFrame.Angles(0, math.rad(180), 0)
	MaterialAppearance.applyBase(fill, nil)
	fill.Parent = model

	finalize(model, main, 20, 0)
end

-- === Main build loop ===
local builtCount, mirrored = 0, 0
-- WHAT TO BUILD, and a guard on it, because the failure without one is unreadable.
--
-- ChunkDefinitions derives `AllIds` from its own keys at the bottom of the module and it is
-- the only thing this loop iterates. When it came back nil the error was
-- "invalid argument #1 to 'ipairs' (table expected, got nil)" at this line -- which says
-- nothing about which module is wrong, whether it was pasted, or what to do about it, and
-- the whole level then failed with 73 separate "no template found" warnings that all had the
-- same single cause.
--
-- Deriving the list here as a fallback is deliberate duplication. ChunkDefinitions owns this
-- logic and should keep it; this exists so that a stale or half-pasted module produces a
-- level you can walk plus one loud sentence, instead of nothing at all plus a stack trace.
local buildOrder = ChunkDefinitions.AllIds
if type(buildOrder) ~= "table" then
	local recovered = {}
	for name, def in pairs(ChunkDefinitions) do
		if type(def) == "table" and (def :: any).id == name then
			table.insert(recovered, name)
		end
	end
	table.sort(recovered)
	buildOrder = recovered
	warn(("ChunkBuilder: ChunkDefinitions.AllIds is %s, not a table. That module is stale or was not pasted -- AllIds is derived at the BOTTOM of ChunkDefinitions, so an older copy, a truncated paste, or a paste into the wrong object all produce this. Recovered %d ids by reading the module's own keys; paste the current ChunkDefinitions into ReplicatedStorage.Shared.ChunkDefinitions to fix it properly."):format(
		typeof(ChunkDefinitions.AllIds), #buildOrder
	))
end

if #buildOrder == 0 then
	warn("ChunkBuilder: ChunkDefinitions contains no chunk definitions at all. Nothing can be built. Check that ReplicatedStorage.Shared.ChunkDefinitions is the current file and is a ModuleScript.")
end

for _, chunkId in ipairs(buildOrder) do
	local def = ChunkDefinitions[chunkId]
	if not def then
		warn("ChunkBuilder: missing definition for " .. chunkId)
		continue
	end

	-- ALREADY BUILT? THEN MAKE SURE BOTH FOLDERS HAVE IT.
	--
	-- This guard used to check `templatesFolder` alone and then `continue`, which is a silent
	-- trap, because the loop is responsible for filling TWO folders: the template goes to
	-- ServerStorage.ChunkTemplates and a visual copy to ReplicatedStorage.Assets.Chunks. The
	-- instruction after any ChunkBuilder change is to clear both -- and clearing only the
	-- second one produced a level with NO CHUNKS AT ALL and no error to explain it: every
	-- chunk matched the guard, skipped, and never re-mirrored its copy across.
	--
	-- So a template without its copy now repairs itself instead of being skipped. The two
	-- folders cannot drift apart any more, and clearing either one is enough.
	local existing = templatesFolder:FindFirstChild(chunkId)
	if existing then
		if not chunksFolder:FindFirstChild(chunkId) then
			local repaired = existing:Clone()
			repaired.Parent = chunksFolder
			mirrored += 1
		end
		continue
	end

	local model = Instance.new("Model")
	model.Name = chunkId
	model:SetAttribute("ChunkId", chunkId)
	model:SetAttribute("Category", def.category)

	if specialBuilders[chunkId] then
		specialBuilders[chunkId](model)
	elseif LinearChunks[chunkId] then
		local primary, length, endY = buildLinear(model, LinearChunks[chunkId])
		buildConnectionAttachments(primary, def.connections)
		finalize(model, primary, length, endY)
	else
		warn("ChunkBuilder: no geometry recipe for " .. chunkId)
		model:Destroy()
		continue
	end

	model.Parent = templatesFolder
	local visualCopy = model:Clone()
	visualCopy.Parent = chunksFolder

	builtCount += 1
end

print(("ChunkBuilder: built %d chunk template(s) into ServerStorage.ChunkTemplates"):format(builtCount))
if #wrappedMeshes > 0 then
	-- The whole point of collecting these: one line you can read, with enough of the names to
	-- act on and a count for the rest.
	local shown = {}
	for index = 1, math.min(3, #wrappedMeshes) do
		table.insert(shown, wrappedMeshes[index])
	end
	print(("ChunkBuilder: %d imported mesh(es) are Models wrapping a MeshPart (%s%s). Using the "
		.. "inner part in each; unwrapping them in Assets would tidy this up."):format(
		#wrappedMeshes, table.concat(shown, ", "),
		if #wrappedMeshes > #shown then (", and %d more"):format(#wrappedMeshes - #shown) else ""))
end
if mirrored > 0 then
	-- Worth saying out loud rather than repairing quietly: it means the two folders had
	-- drifted apart, which is almost always a half-finished clear before a paste.
	print(("ChunkBuilder: re-mirrored %d existing template(s) into ReplicatedStorage.Assets.Chunks"):format(mirrored))
end
if builtCount == 0 and mirrored == 0 and #buildOrder > 0 then
	warn("ChunkBuilder: nothing was built and nothing needed mirroring, so every template already existed. If the level is empty, the templates are stale -- delete the children of ServerStorage.ChunkTemplates AND ReplicatedStorage.Assets.Chunks, then Play again.")
end

-- RIG AUDIT, printed on every build whether or not anything went wrong.
--
-- Every rig failure so far has been silent by construction: the platform still builds,
-- still collides and still looks like the material, it just never deforms -- so the only
-- symptom is "it looks the same", which is indistinguishable from a tuning problem and
-- has now cost several rounds of guessing. A slab either got its rig or it did not, and
-- that is a fact the builder knows at build time and was throwing away.
do
	local wanted, got = {}, {}
	for _, template in ipairs(templatesFolder:GetChildren()) do
		for _, part in ipairs(template:GetDescendants()) do
			if part:IsA("BasePart") then
				local material = part:GetAttribute("Material")
				if material and SKINNED_PLATFORMS[material] then
					wanted[material] = (wanted[material] or 0) + 1
					if part:GetAttribute("SkinnedVisual") then
						got[material] = (got[material] or 0) + 1
					end
				end
			end
		end
	end
	local names = {}
	for material in pairs(wanted) do
		table.insert(names, material)
	end
	table.sort(names)
	for _, material in ipairs(names) do
		local have, want = got[material] or 0, wanted[material]
		if have == want then
			print(("ChunkBuilder:   %s -- %d/%d slabs rigged"):format(material, have, want))
		else
			warn(
				("ChunkBuilder:   %s -- ONLY %d/%d slabs rigged. The rest will not deform. Look above for a 'no mesh named' or 'has no skinned mesh data' warning naming the size that failed."):format(
					material, have, want
				)
			)
		end
	end
end
