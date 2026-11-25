--!strict
-- StarterPlayerScripts/Services/CosmeticsClient.lua
-- THE SHOP'S TRAILS AND AURAS AS THINGS (the ninety-seventh pass, from "way better quality items in my shop ... blender
-- meshes and animations ... make all of the cosmetics in the shop look better").
--
-- They were particles only: flat sprites in Roblox's four stock textures, the same few on everything. On top of them
-- now (the particles stay, as their haze and glints), every trail and aura is made of small modelled things, seen by
-- everyone near: blender/gen_cosmetics.py's meshes (ReplicatedStorage.Assets.Cosmetics), coloured and moved here.
--
--   A TRAIL lets one go behind you every few studs you cover, and it does what that thing would: sprinkles are tossed
--   and tumble and bounce and lie there; honey drips, falls and spreads where it lands; soap bubbles float up wobbling
--   and pop; slime lands with a splat that wobbles; cloud puffs swell and thin; jelly beads bounce; sea glass and the
--   swatch's chips tumble; embers fall glowing and cool to ash; the green ribbon's glints flutter down.
--   AN AURA carries a few round you, always: stars and gold circling and twinkling, snowflakes falling and turning,
--   bubbles and embers rising, fireflies wandering with their wings beating (two of them lit), mist drifting at your
--   feet.
--
-- THE HUNDRED-AND-SEVENTH PASS ("the trail should be less wide ... more creative", "auras ... more pronounced"): a
-- trail's ribbon is thin strands now, each moved here every frame about its wearer by its own motion (a helix round
-- you, a wave, a hop, a crackle, a flutter); and an aura has a ring of its things lying round your feet, or a halo of
-- them over your head, turning.
--
-- WHAT EACH IS, in ShopCatalog (PIECES): its meshes, sizes, colours, material and motion, so the shop and this cannot
-- disagree. WHAT YOU WEAR is read off your character, where ShopCatalog.wear tags it (PieceTrail, PieceAura) for the
-- server's look and for the shop's try-on alike: so the preview is the real thing, as the particles are.
--
-- CHEAP BY DESIGN: on this screen only (nothing is sent), anchored and touching nothing, players within NEAR only, at
-- most TRAIL_MAX of a trail's and AURA_MAX of an aura's, and PIECES_MAX in all; a piece is put back in a pool, not
-- destroyed. Without the meshes imported, nothing here is drawn and the particles carry it alone (said once).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShopCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopCatalog")) :: any

local CosmeticsClient = {}
CosmeticsClient.VERSION = "the two-hundred-and-sixteenth pass (pals), 2026-11-14"

local NEAR = 120 -- studs: further off, nothing is drawn
local TRAIL_MAX = 22 -- a trail's pieces alive at once, per player
local JUMPED = 12 -- studs moved between two frames that can only be a teleport (a fall at full speed is about 4)
local AURA_MAX = 8 -- an aura's, per player
local RING_MAX = 12 -- an aura's ring or halo, per player
local PIECES_MAX = 260 -- in all, on this screen
local GRAVITY = 34
local FLAP = 22 -- a firefly's wingbeats, a second

type Live = { part: BasePart, wings: BasePart?, born: number, life: number, motion: string, from: Vector3, vel: Vector3,
	spin: Vector3, angle: Vector3, ground: number, landed: boolean, bounces: number, size: Vector3, colour: Color3,
	cool: Color3?, alpha: number, phase: number, owner: Player, aura: boolean, slot: number, seed: number, landedAt: number,
	ring: boolean, hairAt: number?, hairTop: number? }
type Strand = { top: Attachment, bottom: Attachment, motion: string, at: Vector3, half: number, radius: number,
	speed: number, phase: number }
type Wearer = { trail: string?, aura: string?, last: Vector3?, travelled: number, auraSet: { Live }, ringSet: { Live },
	drop: number, strands: { Strand }, strandsFor: string?, strandsRoot: BasePart?, strandsAt: number, pace: number }

-- STILL, NOTHING DRAWN (the hundred-and-ninety-fifth pass). A trail's strands wave, bob and wind about you every frame,
-- and a ribbon draws wherever its two ends go: standing still, each strand drew its own sway as a flat pale bar either
-- side of you, a pair of wings that never went. Now the sway is as much as you are travelling (none below STILL studs a
-- second, all of it at MOVING), so a strand at rest stays at rest and draws nothing; the shop's try-on keeps it all, so
-- a trail can still be seen there standing.
local STRANDS = { still = 1, moving = 8, ease = 6, jump = 60 }

local live: { Live } = {}
local wearers: { [Player]: Wearer } = {}
local pool: { [string]: { BasePart } } = {}
local folder: Folder? = nil
local templates: Folder? = nil
local warned = false -- the meshes missing, said once
local failed = false -- a step that went wrong, said once
local rng = Random.new()
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function holder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "CosmeticPieces"
	made.Parent = workspace
	folder = made
	return made
end

local function meshes(): Folder?
	local found = templates
	if found and found.Parent then
		return found
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local cosmetics = assets and assets:FindFirstChild("Cosmetics")
	if cosmetics and cosmetics:IsA("Folder") then
		templates = cosmetics
		return cosmetics
	end
	if not warned then
		warned = true
		warn("[client] CosmeticsClient: no ReplicatedStorage.Assets.Cosmetics, so the shop's trails and auras are particles "
			.. "only. Import meshes/cosmetics/*.fbx into it (see HANDOFF).")
	end
	return nil
end

-- A part of the right kind, from the pool or new: a mesh (its largest side `size` studs) or a ball.
local function take(mesh: string, size: number): BasePart?
	local list = pool[mesh]
	local part: BasePart? = if list and #list > 0 then table.remove(list) else nil
	if not part then
		if mesh == "Ball" then
			local ball = Instance.new("Part")
			ball.Shape = Enum.PartType.Ball
			part = ball
		else
			local source = meshes()
			local found = source and source:FindFirstChild(mesh)
			local template = if found and found:IsA("MeshPart") then found
				elseif found then found:FindFirstChildWhichIsA("MeshPart", true) else nil
			if not template then
				return nil
			end
			part = (template :: MeshPart):Clone()
		end
		local made = part :: BasePart
		made.Anchored = true
		made.CanCollide = false
		made.CanQuery = false
		made.CanTouch = false
		made.CastShadow = false
		made.Massless = true
		made:SetAttribute("Mesh", mesh)
		-- Its own proportions, kept: a piece back from the pool may have been squashed where it landed.
		made:SetAttribute("Base", made.Size)
	end
	local made = part :: BasePart
	local kept = made:GetAttribute("Base")
	local base = if typeof(kept) == "Vector3" then kept else made.Size
	local largest = math.max(base.X, base.Y, base.Z)
	if mesh == "Ball" then
		made.Size = Vector3.new(size, size, size)
	elseif largest > 0 then
		made.Size = base * (size / largest)
	end
	made.Parent = holder()
	return made
end

local function give(part: BasePart)
	local mesh = part:GetAttribute("Mesh")
	part.Parent = nil
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Light") then
			child:Destroy()
		end
	end
	if typeof(mesh) == "string" then
		pool[mesh] = pool[mesh] or {}
		if #pool[mesh] < 64 then
			table.insert(pool[mesh], part)
		else
			part:Destroy()
		end
	else
		part:Destroy()
	end
end

local function groundUnder(at: Vector3): number
	local ignore: { Instance } = { holder() }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(at, Vector3.new(0, -10, 0), rayParams)
	return if hit then hit.Position.Y else at.Y - 3.2
end

local function dress(part: BasePart, piece: any, colour: Color3)
	part.Color = colour
	part.Material = if piece.material == "Glass" then Enum.Material.Glass
		elseif piece.material == "Neon" then Enum.Material.SmoothPlastic -- never Neon (no fake light)
		else Enum.Material.SmoothPlastic
	part.Reflectance = piece.shine or 0.05
	part.Transparency = piece.alpha or 0
end

-- One piece of `look`, let go at `at` (a trail's) or placed in an aura's `slot`.
local function spawn(owner: Player, look: any, at: Vector3, heading: Vector3, aura: boolean, slot: number): Live?
	if #live >= PIECES_MAX then
		return nil
	end
	local piece = look.pieces[rng:NextInteger(1, #look.pieces)]
	local part = take(piece.mesh, piece.size * rng:NextNumber(0.85, 1.15))
	if not part then
		return nil
	end
	local colour = piece.colours[rng:NextInteger(1, #piece.colours)]
	dress(part, piece, colour)
	local wings: BasePart? = nil
	if piece.wings then
		wings = take(piece.wings, piece.size * 1.1)
		if wings then
			dress(wings, { material = "Glass", alpha = 0.55, shine = 0.2 }, Color3.fromRGB(230, 240, 255))
		end
	end
	if piece.light and slot <= (piece.lights or 2) then
		local glow = Instance.new("PointLight")
		glow.Color = piece.light
		glow.Brightness = 0.7
		glow.Range = 5
		glow.Shadows = false
		glow.Parent = part
	end
	local side = heading:Cross(Vector3.yAxis)
	local motion = look.motion
	local vel = Vector3.zero
	if motion == "toss" then
		vel = side * rng:NextNumber(-3, 3) + Vector3.new(0, rng:NextNumber(4, 7), 0) - heading * rng:NextNumber(0.5, 2)
	elseif motion == "flutter" then
		vel = Vector3.new(0, -1.2, 0)
	end
	local one: Live = { part = part, wings = wings, born = os.clock(), life = look.life * rng:NextNumber(0.85, 1.15),
		motion = motion, from = at, vel = vel, spin = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6)),
		angle = Vector3.new(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28)),
		ground = if aura then 0 else groundUnder(at), landed = false, bounces = 0, size = part.Size, colour = colour,
		cool = piece.cool, alpha = piece.alpha or 0, phase = rng:NextNumber(0, 6.28), owner = owner, aura = aura, slot = slot,
		seed = rng:NextNumber(0, 100), landedAt = 0, ring = false }
	part.CFrame = CFrame.new(at)
	table.insert(live, one)
	return one
end

-- AN AURA'S RING OR HALO (ShopCatalog's `ring`), as a look of its own, made once an aura.
local rings: { [string]: any } = {}
local function ringOf(id: string?): any
	if not id then
		return nil
	end
	local cached = rings[id]
	if cached ~= nil then
		return cached or nil
	end
	local look = ShopCatalog.pieces(id)
	local ring = look and look.ring
	local made = if ring then { motion = if ring.halo then "halo" else "ring", life = 1, count = ring.count,
		radius = ring.radius, spin = ring.spin, height = ring.height, pieces = { ring.piece } } else false
	rings[id] = made
	return made or nil
end

-- How far below its root a character's feet are (its hips, and half the root), within reason. An R6 body's HipHeight is
-- 0, and its 2-stud legs are what stand it up.
local function feetDrop(character: Model, root: BasePart): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid and humanoid.RigType ~= Enum.HumanoidRigType.R6 then humanoid.HipHeight else 2
	return math.clamp(hip + root.Size.Y / 2, 2, 4)
end

-- WHERE A STRAND OF A TRAIL IS NOW, about the root (its own frame): a helix round you, a wave side to side, a bob, a
-- hop, a crackle, a figure of eight, or still.
local function strandPlace(s: Strand, now: number): Vector3
	local t = now * s.speed + s.phase
	local r = s.radius
	if s.motion == "helix" then
		return s.at + Vector3.new(math.cos(t) * r, 0, math.sin(t) * r)
	elseif s.motion == "wave" then
		return s.at + Vector3.new(math.sin(t) * r, 0, 0)
	elseif s.motion == "bob" then
		return s.at + Vector3.new(0, math.sin(t) * r, 0)
	elseif s.motion == "bounce" then
		return s.at + Vector3.new(0, math.abs(math.sin(t)) * r, 0)
	elseif s.motion == "zigzag" then
		local tri = 2 * math.abs(2 * ((t / (2 * math.pi)) % 1) - 1) - 1
		return s.at + Vector3.new(tri * r, math.noise(t * 0.7, s.phase) * r, 0)
	elseif s.motion == "flutter" then
		return s.at + Vector3.new(math.sin(t) * r, math.sin(t * 2) * r * 0.4, math.cos(t) * r * 0.3)
	end
	return s.at
end

-- A WEARER'S STRANDS, found on their root (looked for again when the trail changes, and every two seconds), and moved.
local function moveStrands(w: Wearer, root: BasePart, now: number)
	if w.trail ~= w.strandsFor or root ~= w.strandsRoot or now - w.strandsAt > 2 then
		table.clear(w.strands)
		for _, child in ipairs(root:GetChildren()) do
			local motion = child:GetAttribute("StrandMotion")
			if child:IsA("Attachment") and typeof(motion) == "string" then
				local bottom = root:FindFirstChild((string.gsub(child.Name, "TrailTop", "TrailBottom")))
				local at = child:GetAttribute("StrandAt")
				if bottom and bottom:IsA("Attachment") and typeof(at) == "Vector3" then
					table.insert(w.strands, { top = child, bottom = bottom, motion = motion, at = at,
						half = tonumber(child:GetAttribute("StrandHalf")) or 0.15,
						radius = tonumber(child:GetAttribute("StrandRadius")) or 0,
						speed = tonumber(child:GetAttribute("StrandSpeed")) or 0,
						phase = tonumber(child:GetAttribute("StrandPhase")) or 0 })
				end
			end
		end
		w.strandsFor, w.strandsRoot, w.strandsAt = w.trail, root, now
	end
	local trying = root:FindFirstChild("ShopPreviewTrailTop") ~= nil
	local sway = if trying then 1 else math.clamp((w.pace - STRANDS.still) / (STRANDS.moving - STRANDS.still), 0, 1)
	for _, s in ipairs(w.strands) do
		if s.top.Parent and s.motion ~= "still" then
			local centre = s.at:Lerp(strandPlace(s, now), sway)
			s.top.Position = centre + Vector3.new(0, s.half, 0)
			s.bottom.Position = centre - Vector3.new(0, s.half, 0)
		end
	end
end

-- Where a thing of an aura is, `t` seconds into its round, about a root at `root` whose feet are `drop` below it.
local function auraPlace(one: Live, look: any, root: Vector3, now: number, drop: number): (Vector3, number)
	local count = math.max(1, look.count or 6)
	local radius = look.radius or 2.4
	local a = one.slot / count * math.pi * 2 + one.phase
	local motion = one.motion
	if motion == "ring" or motion == "halo" then
		-- Evenly round, turning together: lying at your feet, or over your head.
		local turn = now * (look.spin or 0.4) + one.slot / count * math.pi * 2
		local y = if motion == "halo" then (look.height or 3) + math.sin(now * 1.5) * 0.06
			else -drop + 0.15 + math.sin(now * 2 + one.slot) * 0.04
		return root + Vector3.new(math.cos(turn) * radius, y, math.sin(turn) * radius), 0
	elseif motion == "orbit" then
		local turn = now * (look.spin or 0.5) + a
		local height = math.sin(now * 1.3 + one.phase) * 0.6 + 0.4
		return root + Vector3.new(math.cos(turn) * radius, height, math.sin(turn) * radius), 0
	elseif motion == "hover" then
		local wander = Vector3.new(math.noise(now * 0.4, one.seed, 0), math.noise(0, now * 0.4, one.seed) * 0.6,
			math.noise(one.seed, 0, now * 0.4))
		return root + Vector3.new(math.cos(a) * radius, 0.6, math.sin(a) * radius) + wander * 2.4, 0
	elseif motion == "drift" then
		local turn = now * 0.12 + a
		return root + Vector3.new(math.cos(turn) * radius, -2.4, math.sin(turn) * radius), 0
	end
	-- "rise" and "fall": round their life, each its own way round, from the bottom up or the top down.
	local life = one.life
	-- Each its own way through its round (its phase), so they do not rise or fall all together.
	local u = (((now - one.born) + one.phase / (2 * math.pi) * life) % life) / life
	local y = if motion == "fall" then 3.2 - 5.6 * u else -2.2 + 4.6 * u
	local sway = math.sin(now * 2 + one.phase) * 0.25
	return root + Vector3.new(math.cos(a) * (radius + sway), y, math.sin(a) * (radius + sway)), u
end

-- ===== THE PALS (the two-hundred-and-sixteenth pass, from your note of 2026-11-14: "add more stuff to the shop for
-- tokens, make it good quality") =====
--
-- A pal keeps to your side (ShopCatalog.pal: `side` to your right, `back` behind), catching you up as it can (`follow`),
-- turned the way it is going or, standing, the way you face. The hoppers hop after you along the ground (found by a ray,
-- so they go up a step and down into a hollow), squashing as they land and stretching as they leave, with a small hop now
-- and then while you stand; the bee hovers and darts; the cloud drifts high and slow; the lava rock bobs at your
-- shoulder, warm, throwing sparks. Set down somewhere new (a checkpoint, home), it is set down beside you, not dragged.
-- One part each, on this screen only, within NEAR.
type PalState = { id: string, part: BasePart, base: Vector3, at: Vector3, yaw: number, phase: number, last: Vector3,
	hopFrom: number, ground: number, still: number }
local pals: { [Player]: PalState } = {}
local PAL_JUMP = 24 -- studs between it and where it should be that can only be a teleport

local function dropPal(player: Player)
	local state = pals[player]
	if state then
		state.part:Destroy()
		pals[player] = nil
	end
end

local function makePal(id: string, spec: any): PalState?
	local source = meshes()
	local found = source and source:FindFirstChild(spec.mesh)
	local template = if found and found:IsA("MeshPart") then found
		elseif found then found:FindFirstChildWhichIsA("MeshPart", true) else nil
	if not template then
		return nil
	end
	local part = (template :: MeshPart):Clone()
	part.Name = "Pal"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
	local largest = math.max(part.Size.X, part.Size.Y, part.Size.Z)
	if largest > 0 then
		part.Size = part.Size * (spec.size / largest)
	end
	if spec.light then
		local light = Instance.new("PointLight")
		light.Color = spec.light
		light.Brightness = 0.9
		light.Range = 9
		light.Shadows = false
		light.Parent = part
	end
	if spec.sparks then
		local sparks = Instance.new("ParticleEmitter")
		sparks.Texture = "rbxasset://textures/particles/fire_sparks_main.dds"
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 110), Color3.fromRGB(255, 110, 40))
		sparks.Size = NumberSequence.new(0.12, 0)
		sparks.Lifetime = NumberRange.new(0.5, 1)
		sparks.Rate = 5
		sparks.Speed = NumberRange.new(1, 2.5)
		sparks.SpreadAngle = Vector2.new(60, 60)
		sparks.Acceleration = Vector3.new(0, 3, 0)
		sparks.LightEmission = 0.8
		sparks.Parent = part
	end
	part.Parent = holder()
	return { id = id, part = part, base = part.Size, at = Vector3.zero, yaw = 0, phase = rng:NextNumber(0, 6), last = Vector3.zero,
		hopFrom = 0, ground = 0, still = 0 }
end

local function movePals(dt: number, now: number, eye: Vector3)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local tag = root and (root:FindFirstChild("ShopPreviewPal") or root:FindFirstChild("CosmeticPal"))
		local id = tag and tag:GetAttribute("PiecePal")
		local spec = if typeof(id) == "string" then ShopCatalog.pal(id) else nil
		if not (root and root:IsA("BasePart") and spec and (root.Position - eye).Magnitude < NEAR) then
			dropPal(player)
			continue
		end
		local state = pals[player]
		if state and state.id ~= id then
			dropPal(player)
			state = nil
		end
		local fresh = false
		if not state then
			state = makePal(id :: string, spec)
			if not state then
				continue
			end
			pals[player] = state
			fresh = true
		end
		local pal = state :: PalState
		local face = root.CFrame.LookVector
		face = Vector3.new(face.X, 0, face.Z)
		face = if face.Magnitude > 0.01 then face.Unit else Vector3.new(0, 0, -1)
		local right = face:Cross(Vector3.yAxis)
		local spot = root.Position + right * spec.side - face * spec.back
		local hopper = spec.motion == "hop"
		-- Where it should be: on the ground for a hopper, up by your middle (and its own height) for the rest.
		local wantY = if hopper then 0 else root.Position.Y + (spec.height or 1)
		local want = Vector3.new(spot.X, if hopper then pal.at.Y else wantY, spot.Z)
		if fresh or (pal.at - want).Magnitude > PAL_JUMP then
			pal.at = Vector3.new(want.X, if hopper then root.Position.Y else want.Y, want.Z)
			pal.last = pal.at
			pal.yaw = math.atan2(-face.X, -face.Z)
		end
		local ease = 1 - math.exp(-dt * spec.follow)
		local flat = Vector3.new(want.X - pal.at.X, 0, want.Z - pal.at.Z) * ease
		pal.at += flat
		if not hopper then
			pal.at = Vector3.new(pal.at.X, pal.at.Y + (wantY - pal.at.Y) * ease, pal.at.Z)
		end
		local speed = if dt > 0 then Vector3.new(pal.at.X - pal.last.X, 0, pal.at.Z - pal.last.Z).Magnitude / dt else 0
		pal.last = pal.at
		-- TURNED the way it goes, or standing, the way you face; and LOOKING UP AT YOU now and then while you stand (the
		-- two-hundred-and-seventeenth pass): after a few seconds still, it turns to you for a moment, then away again.
		pal.still = if speed < 0.6 then pal.still + dt else 0
		local toYou = Vector3.new(root.Position.X - pal.at.X, 0, root.Position.Z - pal.at.Z)
		local glance = pal.still > 2.5 and (pal.still % 7) < 3 and toYou.Magnitude > 0.5
		local heading = if speed > 1.5 and flat.Magnitude > 1e-4 then flat.Unit elseif glance then toYou.Unit else face
		local wantYaw = math.atan2(-heading.X, -heading.Z)
		local turn = (wantYaw - pal.yaw + math.pi) % (2 * math.pi) - math.pi
		pal.yaw += turn * math.min(1, dt * 8)
		local size = pal.base
		local offset = Vector3.zero
		local tilt = CFrame.identity
		if hopper then
			-- THE GROUND under it, eased so a step is climbed in a hop, not snapped up.
			-- (Its own ray, which says when there is nothing: groundUnder's guess for nothing is near enough your feet to
			-- pass for a floor.)
			rayParams.FilterDescendantsInstances = { holder(), character :: Model }
			local hit = workspace:Raycast(Vector3.new(pal.at.X, root.Position.Y + 2, pal.at.Z), Vector3.new(0, -10, 0), rayParams)
			local feet = root.Position.Y - feetDrop(character :: Model, root)
			local ground = if hit then hit.Position.Y else feet
			-- OVER A GAP OR UP WITH YOU (the two-hundred-and-seventeenth pass): between two chunks the ground under it is
			-- the far floor, or none, and it would drop into the void; there it hops along at your feet' height, on the air,
			-- as a cartoon would. And when you jump it goes up with you, never further below your feet than a stud.
			if ground < feet - 4 or ground > feet + 4 then
				ground = feet
			end
			local humanoid = (character :: Model):FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
				ground = math.max(ground, feet - 1)
			end
			pal.ground += (ground - pal.ground) * (if math.abs(ground - pal.ground) > 8 then 1 else math.min(1, dt * 10))
			-- Hops at 2.6 a second going, a small one every two seconds standing.
			local going = math.clamp(speed / 8, 0, 1)
			pal.phase += dt * (0.55 + 2.1 * going)
			local u = pal.phase % 1
			local height = (0.25 + 0.95 * going) * math.sin(u * math.pi)
			-- Squashed flat as it lands and as it leaves (the first and last tenth of a hop), stretched tall in the air.
			local squash = spec.squash or 0.3
			local land = if u < 0.1 then 1 - u / 0.1 elseif u > 0.9 then (u - 0.9) / 0.1 else 0
			local stretch = math.sin(u * math.pi) * going * 0.12
			local s = squash * land - stretch
			size = Vector3.new(pal.base.X * (1 + s * 0.6), pal.base.Y * (1 - s), pal.base.Z * (1 + s * 0.6))
			pal.at = Vector3.new(pal.at.X, pal.ground + size.Y / 2 + height, pal.at.Z)
			tilt = CFrame.Angles(-0.18 * going * math.cos(u * math.pi), 0, 0)
		elseif spec.motion == "buzz" then
			pal.phase += dt
			offset = Vector3.new(0.12 * math.sin(pal.phase * 7.3), 0.3 * math.sin(pal.phase * 1.8) + 0.06 * math.sin(pal.phase * 23),
				0.1 * math.cos(pal.phase * 5.1))
			tilt = CFrame.Angles(0.12 * math.sin(pal.phase * 2.3), 0, 0.1 * math.sin(pal.phase * 3.1))
		elseif spec.motion == "drift" then
			pal.phase += dt
			offset = Vector3.new(0.2 * math.sin(pal.phase * 0.7), 0.3 * math.sin(pal.phase * 0.9), 0)
			tilt = CFrame.Angles(0, 0, 0.06 * math.sin(pal.phase * 0.8))
			local breathe = 1 + 0.03 * math.sin(pal.phase * 1.6)
			size = pal.base * breathe
		else
			pal.phase += dt
			offset = Vector3.new(0, 0.22 * math.sin(pal.phase * 2.1), 0)
			tilt = CFrame.Angles(0.06 * math.sin(pal.phase * 1.3), 0, 0.08 * math.sin(pal.phase * 1.7))
		end
		local part = pal.part
		if part.Size ~= size then
			part.Size = size
		end
		part.CFrame = CFrame.new(pal.at + offset) * CFrame.Angles(0, pal.yaw + math.rad(spec.yaw or 0), 0) * tilt
	end
	for player in pairs(pals) do
		if not player.Parent then
			dropPal(player)
		end
	end
end

local function step(dt: number)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	movePals(dt, now, eye)
	-- WHO WEARS WHAT, near enough to see.
	local seen: { [Player]: boolean } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - eye).Magnitude < NEAR then
			seen[player] = true
			local w = wearers[player] or { trail = nil, aura = nil, last = nil, travelled = 0, auraSet = {}, ringSet = {},
				drop = 3, strands = {}, strandsFor = nil, strandsRoot = nil, strandsAt = 0, pace = 0 }
			wearers[player] = w
			-- MOVED, NOT TRAVELLED (the hundred-and-eighty-first pass, from your test of 2026-11-04: "big white horizontal
			-- columns"): set down at a checkpoint, taken home, carried by a ride, a ribbon drew itself the whole way from where
			-- you were to where you are, a white bar across the level for a second and more. Any jump further than a frame's
			-- running starts every ribbon on you again from where you are now.
			local lastAt = w.last
			if lastAt and (root.Position - lastAt).Magnitude > JUMPED then
				for _, child in ipairs(root:GetChildren()) do
					if child:IsA("Trail") then
						child:Clear()
					end
				end
			end
			w.drop = feetDrop(character :: Model, root)
			local trailTag = root:FindFirstChild("ShopPreviewTrailTop") or root:FindFirstChild("CosmeticTrailTop")
			local auraTag = root:FindFirstChild("ShopPreviewAura") or root:FindFirstChild("CosmeticAura")
			local trail = trailTag and trailTag:GetAttribute("PieceTrail")
			local aura = auraTag and auraTag:GetAttribute("PieceAura")
			w.trail = if typeof(trail) == "string" then trail else nil
			local wantAura = if typeof(aura) == "string" then aura else nil
			if wantAura ~= w.aura then
				for _, one in ipairs(w.auraSet) do
					one.life = 0
				end
				for _, one in ipairs(w.ringSet) do
					one.life = 0
				end
				table.clear(w.auraSet)
				table.clear(w.ringSet)
				w.aura = wantAura
			end
			-- THE TRAIL'S STRANDS, each moved its own way about you, as far as you are travelling (a jump is not travel).
			local pace = if lastAt and dt > 0 then Vector3.new(root.Position.X - lastAt.X, 0, root.Position.Z - lastAt.Z).Magnitude / dt else 0
			w.pace += ((if pace > STRANDS.jump then 0 else math.min(pace, STRANDS.moving)) - w.pace) * math.min(1, dt * STRANDS.ease)
			moveStrands(w, root, now)
			-- THE TRAIL: one let go every `every` studs covered, behind you, a little to one side or the other.
			local look = w.trail and ShopCatalog.pieces(w.trail)
			local here = root.Position
			if look and meshes() then
				local last = w.last or here
				local moved = Vector3.new(here.X - last.X, 0, here.Z - last.Z).Magnitude
				w.travelled += if moved < 8 then moved else 0
				local count = 0
				for _, one in ipairs(live) do
					if one.owner == player and not one.aura then
						count += 1
					end
				end
				local heading = root.CFrame.LookVector
				heading = Vector3.new(heading.X, 0, heading.Z)
				heading = if heading.Magnitude > 0.01 then heading.Unit else Vector3.zAxis
				while w.travelled >= look.every and count < TRAIL_MAX do
					w.travelled -= look.every
					local side = heading:Cross(Vector3.yAxis) * rng:NextNumber(-0.6, 0.6)
					spawn(player, look, here - heading * 0.9 + side + Vector3.new(0, rng:NextNumber(-0.6, 0.4), 0), heading, false, 0)
					count += 1
				end
				w.travelled = math.min(w.travelled, look.every)
			end
			w.last = here
			-- THE AURA: its set, kept full.
			local auraLook = w.aura and ShopCatalog.pieces(w.aura)
			if auraLook and meshes() then
				local want = math.min(AURA_MAX, auraLook.count or 6)
				for slot = #w.auraSet + 1, want do
					local one = spawn(player, auraLook, here, Vector3.zAxis, true, slot)
					if one then
						table.insert(w.auraSet, one)
					else
						break
					end
				end
			end
			-- ITS RING OR HALO, kept full.
			local ringLook = ringOf(w.aura)
			if ringLook and meshes() then
				local want = math.min(RING_MAX, ringLook.count or 8)
				for slot = #w.ringSet + 1, want do
					local one = spawn(player, ringLook, here, Vector3.zAxis, true, slot)
					if one then
						one.ring = true
						table.insert(w.ringSet, one)
					else
						break
					end
				end
			end
		end
	end
	for player, w in pairs(wearers) do
		if not seen[player] then
			for _, one in ipairs(w.auraSet) do
				one.life = 0
			end
			for _, one in ipairs(w.ringSet) do
				one.life = 0
			end
			wearers[player] = nil
		end
	end
	-- EVERY PIECE MOVED, and the spent ones put away.
	local k = 1
	while k <= #live do
		local one = live[k]
		local age = now - one.born
		local done = not one.part.Parent or not one.owner.Parent
		local part = one.part
		one.angle += one.spin * dt
		if one.aura then
			local w = wearers[one.owner]
			local root = one.owner.Character and one.owner.Character:FindFirstChild("HumanoidRootPart")
			local look = w and w.aura and (if one.ring then ringOf(w.aura) else ShopCatalog.pieces(w.aura))
			if one.life <= 0 or not (w and look and root and root:IsA("BasePart")) then
				done = true
			else
				local at, u = auraPlace(one, look, (root :: BasePart).Position, now, (w :: Wearer).drop)
				-- (Not the crown: a crown that swells and shrinks four times a second read as wobbling. The two-hundred-and-
				-- forty-second pass.)
				local twinkle = if one.motion == "orbit" or one.motion == "ring"
					then 0.75 + 0.25 * math.sin(now * 5 + one.phase * 3) else 1
				part.Size = one.size * twinkle
				local fadeIn = math.clamp(age / 0.6, 0, 1)
				local edge = if one.motion == "rise" or one.motion == "fall" then math.clamp(math.min(u, 1 - u) / 0.15, 0, 1) else 1
				part.Transparency = 1 - (1 - one.alpha) * fadeIn * edge
				if one.cool then
					part.Color = one.colour:Lerp(one.cool, math.clamp(u * 1.2, 0, 1))
				end
				-- (Over the head, worn upright and turning: a crown tilted at random read as dropped. The two-hundred-and-
				-- fourteenth pass.)
				local tilt = if one.motion == "halo" then 0 else 0.3
				part.CFrame = CFrame.new(at) * CFrame.fromEulerAnglesXYZ(one.angle.X * tilt,
					if one.motion == "halo" then now * 0.6 + one.slot else one.angle.Y, one.angle.Z * tilt)
				-- WORN ON THE HEAD (the two-hundred-and-fifteenth pass, from your note of 2026-11-14: the crown "falls back a
				-- bit when I'm moving"): placed from the root, it stayed where the head would be standing still, and running
				-- leans the head forward of the root. Now on the head itself: on its top, leaning with it, turning slowly.
				local head = if one.motion == "halo" and one.owner.Character then one.owner.Character:FindFirstChild("Head") else nil
				if head and head:IsA("BasePart") and look.radius == 0 then
					-- ON THE HAIR, NOT IN IT (the two-hundred-and-forty-second pass, from your note of 2026-11-22: "my vip
					-- crown is covered by my hair"). It sat on the head's own top, and hair stands well above that. Now it
					-- sits on the highest of what is worn on the head (hair and hats), a little settled into it; measured
					-- in the head's own up, so it holds as the head leans, and again every two seconds for a change of look.
					if not one.hairAt or now - one.hairAt > 2 then
						one.hairAt = now
						local top = head.Size.Y * 0.5
						for _, item in ipairs(one.owner.Character:GetChildren()) do
							local handle = item:IsA("Accessory") and item:FindFirstChild("Handle")
							if handle and handle:IsA("BasePart") and handle.Transparency < 1 then
								local rel = head.CFrame:ToObjectSpace(handle.CFrame)
								local up = rel:VectorToObjectSpace(Vector3.yAxis)
								local reach = 0.5 * (math.abs(up.X) * handle.Size.X + math.abs(up.Y) * handle.Size.Y
									+ math.abs(up.Z) * handle.Size.Z)
								local over = rel.Position.Y + reach
								-- (Only what is on the head: a back accessory or a sword stands no higher than this.)
								if over > top and over < head.Size.Y * 0.5 + 3 and math.abs(rel.Position.X) < 2
									and math.abs(rel.Position.Z) < 2 then
									top = over
								end
							end
						end
						one.hairTop = top
					end
					local settle = if (one.hairTop or 0) > head.Size.Y * 0.5 + 0.05 then 0.18 else 0
					local lift = (one.hairTop or head.Size.Y * 0.5) - settle + part.Size.Y * 0.42
					part.CFrame = head.CFrame * CFrame.new(0, lift, 0) * CFrame.Angles(0, now * 0.6 + one.slot, 0)
					-- NOT IN YOUR OWN EYES (same pass: "in first person it's wobbling in front of my face"). Roblox hides
					-- your hats when the camera is in your head; your crown is hidden the same way, and only on your screen.
					if one.owner == Players.LocalPlayer then
						local camera = workspace.CurrentCamera
						if camera and (camera.CFrame.Position - head.Position).Magnitude < 2 then
							part.Transparency = 1
						end
					end
				end
				if one.wings then
					local beat = math.sin(now * FLAP * math.pi * 2 + one.phase) * 0.7
					one.wings.CFrame = part.CFrame * CFrame.new(0, part.Size.Y * 0.3, 0) * CFrame.Angles(0, 0, beat)
					one.wings.Transparency = math.max(part.Transparency, 0.55)
				end
			end
		else
			local u = age / one.life
			if u >= 1 then
				done = true
			else
				local pos = part.Position
				local motion = one.motion
				local scale = 1
				local fade = math.clamp((u - 0.7) / 0.3, 0, 1)
				if motion == "rise" then
					-- A bubble: up, wobbling, growing a little; then it pops.
					pos = one.from + Vector3.new(math.sin(age * 3 + one.phase) * 0.25, age * 1.4, math.cos(age * 2.6 + one.phase) * 0.25)
					scale = 1 + 0.25 * u + 0.06 * math.sin(age * 9)
					if u > 0.88 then
						scale *= 1 + (u - 0.88) * 4
						fade = (u - 0.88) / 0.12
					else
						fade = 0
					end
				elseif motion == "puff" then
					-- A cloud puff: hangs where it was left, swelling and thinning, lifting a little.
					pos = one.from + Vector3.new(0, age * 0.35, 0)
					scale = 1 + 0.9 * u
					fade = u ^ 1.5
				elseif motion == "flutter" then
					-- A glint: drifting down, side to side, turning.
					pos = one.from + Vector3.new(math.sin(age * 4 + one.phase) * 0.5, -age * 1.1, math.cos(age * 3 + one.phase) * 0.3)
					fade = u ^ 2
				else
					-- "toss", "drip", "splat", "bounce": falling under gravity, to the ground, and what it does there.
					if not one.landed then
						one.vel -= Vector3.new(0, GRAVITY * dt, 0)
						pos += one.vel * dt
						local half = one.size.Y * 0.5
						if pos.Y - half <= one.ground then
							pos = Vector3.new(pos.X, one.ground + half, pos.Z)
							local bounce = if motion == "bounce" then 0.45 elseif motion == "toss" then 0.3 else 0
							local most = if motion == "bounce" then 2 else 1
							if bounce > 0 and one.bounces < most and math.abs(one.vel.Y) > 2 then
								one.vel = Vector3.new(one.vel.X * 0.6, -one.vel.Y * bounce, one.vel.Z * 0.6)
								one.bounces += 1
							else
								one.landed = true
								one.vel = Vector3.zero
								one.spin = Vector3.zero
								one.landedAt = age
							end
						end
					end
					if one.landed then
						local since = age - one.landedAt
						if motion == "drip" or motion == "splat" then
							-- It spreads where it lands: flattening, widening, a wobble going out of it.
							local spread = math.clamp(since / 0.25, 0, 1)
							local wobble = 1 + 0.15 * math.sin(since * 22) * math.exp(-since * 5)
							part.Size = Vector3.new(one.size.X * (1 + 0.5 * spread) * wobble, one.size.Y * (1 - 0.6 * spread),
								one.size.Z * (1 + 0.5 * spread) * wobble)
							one.angle = Vector3.new(0, one.angle.Y, 0)
						end
					end
				end
				if motion == "rise" or motion == "puff" or motion == "flutter" then
					part.Size = one.size * scale
				end
				if one.cool then
					part.Color = one.colour:Lerp(one.cool, math.clamp(u * 1.6, 0, 1))
				end
				part.Transparency = 1 - (1 - one.alpha) * (1 - fade)
				part.CFrame = CFrame.new(pos) * CFrame.fromEulerAnglesXYZ(one.angle.X, one.angle.Y, one.angle.Z)
			end
		end
		if done then
			give(part)
			if one.wings then
				give(one.wings)
			end
			live[k] = live[#live]
			live[#live] = nil
		else
			k += 1
		end
	end
end

-- One frame by hand (`dt` seconds), for a test run while Studio's view is not drawing (RenderStepped does not fire then).
function CosmeticsClient.tick(dt: number)
	step(math.min(dt, 0.1))
end

function CosmeticsClient.start()
	RunService.RenderStepped:Connect(function(dt: number)
		local ok, err = pcall(step, math.min(dt, 0.1))
		if not ok and not failed then
			failed = true
			warn("[client] CosmeticsClient: " .. tostring(err) .. " (shown once)")
		end
	end)
	print("CosmeticsClient: running, " .. CosmeticsClient.VERSION)
end

CosmeticsClient.STAMP = "d8c7c6f3"
return CosmeticsClient
