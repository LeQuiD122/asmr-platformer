--!strict
-- ServerScriptService/Services/SkyPoolsService.lua
-- Level 2, Sky Pools: everything round the route.
--
-- === What the level is ===
--
-- Calm, bright, and silent apart from water: the one level with no scares at all. LevelService lays
-- the route as one wide ring that goes DOWN (see `ring` on LevelDefinitions.Level2), and this builds
-- the place it runs through:
--
--   POOL TERRACES beside the route, stepping off checkpoint chunks: a deck with a pool, loungers, a
--   parasol, a towel somebody left, a ladder, and on one of them a diving board out over the water.
--   Each pool spills off its outer edge in a waterfall.
--   THE FOUNTAIN TOWER in the middle of the ring, rising out of the final pool to a basin above the
--   start. The basin overflows all the way round, and that curtain of water is what fills the pool.
--   THE CLOUD SEA, one soft flat layer under the whole level. The route goes down toward it, so the
--   clouds come closer as you go; a fall ends in them.
--   THE FINALE DECK at the end of the route, and THE SLIDE from it: round the tower, down through
--   the clouds, into the final pool. The splash ends the level.
--   THE SEA far below everything, which the final pool drains into, and SCENERY POOLS out in the
--   sky on their own columns.
--
-- === Rules this follows ===
--
--   NOTHING FLOATS. Every terrace stands on columns that go down through the clouds to the sea. The
--   final pool stands on the tower and on a ring of columns, the tower stands in the sea, and the
--   slide hangs from the tower on rods. The chunks are the route and float as they do on every
--   level; everything built HERE has something holding it up, all the way down.
--   CLOUDS ARE FLAT. City Shore's cloud banks were balls, and from the level they were white eggs in
--   front of everything. These are wide, low ellipsoids laid edge to edge as a floor, and none of
--   them is ever at eye level.
--   THE WATER GOES SOMEWHERE. Basin to curtain to final pool to the sea; terrace pools spill to the
--   sea. A waterfall that stops in mid-air is the same mistake as a wall that floats.
--   ONLY THE SLIDE ENDS THE LEVEL. It is a ride -- the rider is moved, as on the Flooded Halls'
--   flume -- and its parts do not collide, so a player who falls onto it drops through into the
--   clouds and is caught like any fall. See ownsFall for why a rider is not.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")

local SkyPoolsService = {}

-- ===== The terraces =====
local NECK = 9 -- the strip joining a terrace to its chunk; see terraceBeside for why nine
-- THE NECK IS DEEPER THAN THE DECK. The straight chunk has side shelves two studs under its top that
-- reach 13.4 out and hang six under it; a neck only as deep as the deck would leave their undersides
-- showing beneath it. 7.4 covers them from the cap's top down.
local NECK_THICK = 7.4
local TERRACE_W, TERRACE_L = 46, 36 -- outward from the neck, and along the route
local POOL_W, POOL_L = 22, 14 -- the pool's opening, the same two ways
local POOL_DEPTH = 3.5 -- shallow enough to stand in: a pool you walk through, not a hole
local DECK_THICK = POOL_DEPTH + 1 -- the deck is the pool's walls, so it is as deep as the pool
local COLUMN_D = 6

-- ===== The cloud sea, the final pool, the tower, the sea =====
-- The cloud sea's top sits this far above the kill plane, so a fall sinks into cloud just as it is
-- caught -- and since the route goes down, the last terraces are only a little way above it.
local CLOUD_ABOVE_KILL = 14
local CLOUD_THICK = 70
local CLOUD_REACH = 2400 -- far enough that its edge is lost in the haze rather than seen
local CLOUD_UNDER_REACH = 900 -- the underside only matters where you can see it: from the final pool
local FINAL_BELOW = 150 -- the final pool's surface, this far under the cloud sea's bottom
local FINAL_RADIUS = 105
local FINAL_DEEP = 3 -- waist deep
local TOWER_D = 34
local TOWER_ABOVE = 90 -- the basin tops out this far above the start
local BASIN_D = 76
local SEA_BELOW = 520 -- the sea, this far under the final pool
-- THE POOL STAYS WELL ABOVE THE DELETE LINE. Roblox deletes a falling character below
-- Workspace.FallenPartsDestroyHeight (-500 unless the place changes it), and a long run goes down far
-- enough that the pool would sit eleven studs above it. So the pool rises to stay this far over it,
-- which on a long run only brings it nearer the clouds' underside. The sea and the columns under it
-- are anchored and the engine leaves those alone.
local POOL_ABOVE_DESTROY = 60
local LONGEST = 2000 -- a part stops at 2048 studs; anything longer is built in pieces

-- ===== The slide =====
local SLIDE_TURNS = 0.85 -- round the tower from the finale deck to the pool; never under itself
local SLIDE_END_RADIUS = 70 -- where it lands: well inside the final pool, clear of the curtain
local SLIDE_WIDE = 8
local SLIDE_STEP = 9 -- studs of trough per segment
-- A SPEED, NOT A DURATION. The slide's length depends on how big the ring came out, and a fixed
-- time made a long slide a cannon. Clamped so a small ring is still a ride and a huge one ends.
local SLIDE_SPEED = 70
local SLIDE_MIN_SECONDS, SLIDE_MAX_SECONDS = 8, 15
local SLIDE_RAMP = 0.15 -- the share of the ride spent speeding up from standing
local WALK_L, WALK_W = 30, 18 -- the finale walkway, along the route and across it

-- ===== The pump room, under one terrace =====
--
-- A hatch in the deck with its lid standing open, a ladder down, and a small room slung under the
-- deck on its own walls: two pumps feeding the pool above, a pipe carrying the overflow down to the
-- sea, a lamp, and the log on the wall. The one closed-off place in the level, for whoever looks.
local HATCH = 4
local HATCH_FROM = 1.5 -- the hatch's inner edge, this far out from the terrace's inner edge
local HATCH_Z = -5.5 -- and its near side, this far along
local ROOM_DOWN = 10 -- the room's floor, this far under the deck's underside
local ROOM_LONG = 22 -- outward, from the terrace's inner edge
local ROOM_Z0, ROOM_Z1 = -9, 7 -- along the route: clear of the terrace's inner columns at +-13

-- ===== More on the decks =====
local CABANA_FROM = 7 -- the changing hut starts this far out from the pool's inner edge
local CABANA_W = 8 -- and is this wide; it runs from the pool's side to the terrace's edge
local LIFEGUARD_BACK = 5 -- the lifeguard's chair stands this far back from the pool's far side
local BALLOONS = 3 -- hot air balloons drifting round the level, far out and high up
local GULLS = 7 -- in each of two flocks the client flies round the tower (SkyPoolsClient)

-- The water sound everywhere else in the project, pitched per use.
local WATER_SOUND = "rbxasset://sounds/impact_water.mp3"

-- ===== Colours =====
local DECK = Color3.fromRGB(240, 242, 238)
local COPING = Color3.fromRGB(252, 252, 250)
local TILE = Color3.fromRGB(116, 200, 214)
local WATER = Color3.fromRGB(96, 196, 218)
local FALL = Color3.fromRGB(184, 232, 244)
local STONE = Color3.fromRGB(234, 238, 242)
local BAND = Color3.fromRGB(200, 222, 236)
local SLIDE = Color3.fromRGB(180, 164, 236)
local RAIL = Color3.fromRGB(246, 244, 252)
local SEA = Color3.fromRGB(58, 132, 176)
local CLOUD_TOP = Color3.fromRGB(255, 255, 255)
local CLOUD_UNDER = Color3.fromRGB(224, 234, 248)
local PASTELS = {
	Color3.fromRGB(244, 176, 164),
	Color3.fromRGB(168, 220, 200),
	Color3.fromRGB(166, 206, 232),
	Color3.fromRGB(246, 226, 160),
	Color3.fromRGB(204, 186, 230),
}

-- The pool tile MaterialVariant BackdropService's aquapark asks for, on the pool floors, when it
-- exists. A MaterialVariant only shows on a part of its own BaseMaterial, so the floor takes that
-- material from the variant rather than assuming one. Looked up once per build.
local TILE_VARIANT = "PoolTileBackdrop"
local tileMaterial: Enum.Material? = nil

local rng = Random.new(20260918)

-- ===== Parts =====

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3,
	material: Enum.Material, solid: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = colour
	part.Material = material
	part.Anchored = true
	part.CanCollide = solid
	part.CanTouch = false
	part.CanQuery = solid
	part.CastShadow = solid
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- AN ELLIPSOID, which a Ball part cannot be: Roblox forces a ball's three sizes equal. A block with
-- a sphere mesh takes the block's size on all three axes, so a cloud can be wide and low.
local function ellipsoid(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3): Part
	local part = block(parent, name, size, cf, colour, Enum.Material.SmoothPlastic, false)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- An upright cylinder from `bottom` to `top` (Y values) at `at` (X and Z). Roblox's cylinders lie
-- along X, so every upright one needs the roll, and doing it here once is how none of them ends up
-- lying down. In pieces when it is longer than a part can be.
local function column(parent: Instance, name: string, diameter: number, at: Vector3, bottom: number,
	top: number, colour: Color3, material: Enum.Material, solid: boolean): Part?
	local height = top - bottom
	if height <= 0.05 then
		return nil
	end
	local pieces = math.ceil(height / LONGEST)
	local each = height / pieces
	local last: Part? = nil
	for index = 1, pieces do
		local y = bottom + (index - 0.5) * each
		local part = block(parent, name, Vector3.new(each, diameter, diameter),
			CFrame.new(at.X, y, at.Z) * CFrame.Angles(0, 0, math.pi / 2), colour, material, solid)
		part.Shape = Enum.PartType.Cylinder
		last = part
	end
	return last
end

-- A cylinder from one point to another: rods, rails, the ladder.
local function rod(parent: Instance, name: string, from: Vector3, to: Vector3, diameter: number, colour: Color3)
	local length = (to - from).Magnitude
	if length < 0.05 then
		return
	end
	local part = block(parent, name, Vector3.new(length, diameter, diameter),
		CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.pi / 2, 0), colour, Enum.Material.Metal, false)
	part.Shape = Enum.PartType.Cylinder
end

local function water(parent: Instance, name: string, size: Vector3, cf: CFrame): Part
	local part = block(parent, name, size, cf, WATER, Enum.Material.Glass, false)
	part.Transparency = 0.32
	part.Reflectance = 0.12
	return part
end

-- Words on a face of a part, for signs.
local function label(part: BasePart, face: Enum.NormalId, words: string, ink: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	gui.Parent = part
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = words
	text.TextScaled = true
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = ink
	text.Parent = gui
end

-- A looped water sound, positional: full out to `near`, gone by `far`.
local function waterSound(parent: Instance, name: string, speed: number, volume: number, near: number, far: number): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = WATER_SOUND
	s.Looped = true
	s.PlaybackSpeed = speed
	s.Volume = volume
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = near
	s.RollOffMaxDistance = far
	s.Parent = parent
	s:Play()
	return s
end

-- A FALL OF WATER: a thin sheet from `top` straight down to `bottomY`, `wide` across, facing
-- `facing`, with droplets coming off its lip. Pale and see-through, because a sheet of water this
-- thin is mostly light. With `roar`, the fall is heard out to that many studs from its lip: the
-- project's water sample pitched down, a little differently for every fall so no two beat together.
local function waterfall(parent: Instance, top: Vector3, facing: Vector3, wide: number, bottomY: number, roar: number?)
	local height = top.Y - bottomY
	if height <= 1 then
		return
	end
	local pieces = math.ceil(height / LONGEST)
	local each = height / pieces
	for index = 1, pieces do
		local centre = Vector3.new(top.X, top.Y - (index - 0.5) * each, top.Z)
		local sheet = block(parent, "Waterfall", Vector3.new(wide, each, 1.2), CFrame.lookAt(centre, centre + facing),
			FALL, Enum.Material.Glass, false)
		sheet.Transparency = 0.5
		sheet.Reflectance = 0.08
		if index == 1 then
			local lip = Instance.new("Attachment")
			lip.Name = "Lip"
			lip.Position = Vector3.new(0, each / 2, 0)
			lip.Parent = sheet
			local drops = Instance.new("ParticleEmitter")
			drops.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			drops.Color = ColorSequence.new(Color3.fromRGB(236, 250, 255))
			drops.LightEmission = 0.4
			drops.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1) })
			drops.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			drops.Lifetime = NumberRange.new(1.2, 2.4)
			drops.Speed = NumberRange.new(2, 5)
			drops.SpreadAngle = Vector2.new(25, 10)
			drops.Acceleration = Vector3.new(0, -40, 0)
			drops.EmissionDirection = Enum.NormalId.Front
			drops.Rate = math.clamp(wide * 1.2, 6, 30)
			drops.Parent = lip
			if roar then
				waterSound(lip, "Roar", rng:NextNumber(0.38, 0.47), if roar > 150 then 0.35 else 0.3, 10, roar)
			end
		end
	end
end

-- ===== POOL TOYS =====
--
-- A rubber duck or a swim ring, floating at `surface` (a frame on the water's top), free to drift up
-- to `halfX` and `halfZ` either way. The client does the drifting and bobbing (SkyPoolsClient); it
-- stands still here. Supported by the water, which is the one thing in the level allowed to.
local function poolToy(parent: Instance, surface: CFrame, halfX: number, halfZ: number, kind: string)
	local toy = Instance.new("Model")
	toy.Name = if kind == "duck" then "RubberDuck" else "SwimRing"
	if kind == "duck" then
		local yellow = Color3.fromRGB(246, 214, 80)
		ellipsoid(toy, "DuckBody", Vector3.new(2.6, 1.8, 3.2), surface * CFrame.new(0, 0.5, 0), yellow)
		ellipsoid(toy, "DuckHead", Vector3.new(1.6, 1.6, 1.6), surface * CFrame.new(0, 1.8, -1), yellow)
		block(toy, "DuckBeak", Vector3.new(0.8, 0.35, 0.8), surface * CFrame.new(0, 1.7, -1.95), Color3.fromRGB(236, 130, 50),
			Enum.Material.SmoothPlastic, false)
		for _, side in ipairs({ -1, 1 }) do
			ellipsoid(toy, "DuckEye", Vector3.new(0.25, 0.25, 0.25), surface * CFrame.new(side * 0.45, 2.1, -1.6),
				Color3.fromRGB(30, 30, 34))
		end
	else
		for index = 0, 9 do
			local a = index * 2 * math.pi / 10
			ellipsoid(toy, "RingPiece", Vector3.new(1.1, 0.9, 1.3), surface * CFrame.Angles(0, a, 0) * CFrame.new(1.6, 0.25, 0),
				if index % 2 == 0 then Color3.fromRGB(244, 150, 170) else Color3.fromRGB(250, 250, 248))
		end
	end
	toy.WorldPivot = surface
	toy:SetAttribute("Drift", Vector2.new(halfX, halfZ))
	toy.Parent = parent
	CollectionService:AddTag(toy, "SkyPoolToy")
end

-- ===== THE CABANA =====
--
-- A changing hut on the deck beside the pool, its door facing the water: the second small place to
-- step into (ROADMAP section 6). The shower in the corner is running and nobody is in it, there is a
-- robe on a hook, a bench, three lockers and one of them open, with a towel folded in it and a note.
-- The lamp inside shows through the doorway from the deck. In the terrace's frame; `px0` and `pz`
-- are the pool's inner edge and half its length, `lz` half the terrace's.
local function cabana(parent: Instance, frame: CFrame, px0: number, pz: number, lz: number)
	local x0, x1 = px0 + CABANA_FROM, px0 + CABANA_FROM + CABANA_W
	local z0, z1 = pz + 1.5, lz - 0.5
	local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
	local h = 8
	local wall = Color3.fromRGB(250, 246, 238)
	local stripe = PASTELS[rng:NextInteger(1, #PASTELS)]
	local function put(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y, z)
	end
	-- Walls: the front with its doorway, the back and the two sides.
	for _, side in ipairs({ -1, 1 }) do
		local piece = (x1 - x0) / 2 - 1.5
		block(parent, "CabanaWall", Vector3.new(piece, h, 0.5), put(cx + side * (1.5 + piece / 2), h / 2, z0 + 0.25), wall,
			Enum.Material.SmoothPlastic, true)
		block(parent, "CabanaWall", Vector3.new(0.5, h, z1 - z0), put(if side < 0 then x0 + 0.25 else x1 - 0.25, h / 2, cz), wall,
			Enum.Material.SmoothPlastic, true)
	end
	block(parent, "CabanaLintel", Vector3.new(3, 1, 0.5), put(cx, h - 0.5, z0 + 0.25), wall, Enum.Material.SmoothPlastic, true)
	block(parent, "CabanaWall", Vector3.new(x1 - x0, h, 0.5), put(cx, h / 2, z1 - 0.25), wall, Enum.Material.SmoothPlastic, true)
	block(parent, "CabanaRoof", Vector3.new(x1 - x0 + 1.6, 0.5, z1 - z0 + 1.6), put(cx, h + 0.25, cz), stripe, Enum.Material.SmoothPlastic, true)
	-- A striped fascia along the front, which is what makes it a beach hut and not a shed.
	for index = 0, 3 do
		block(parent, "CabanaStripe", Vector3.new((x1 - x0 + 1.6) / 4, 0.8, 0.3), put(x0 - 0.8 + (index + 0.5) * (x1 - x0 + 1.6) / 4, h - 0.1, z0 - 0.8),
			if index % 2 == 0 then stripe else COPING, Enum.Material.SmoothPlastic, false)
	end
	-- THE SHOWER, in the back corner, running: a head on an arm off the back wall, water falling from
	-- it, a little steam, and its sound, heard from the deck.
	local sx, sz = x0 + 1.6, z1 - 1.6
	block(parent, "ShowerTray", Vector3.new(2.8, 0.2, 2.8), put(sx, 0.1, sz), TILE, Enum.Material.SmoothPlastic, true)
	rod(parent, "ShowerArm", put(sx, h - 1.2, z1 - 0.5).Position, put(sx, h - 1.2, sz).Position, 0.2, RAIL)
	local head = block(parent, "ShowerHead", Vector3.new(0.8, 0.3, 0.8), put(sx, h - 1.45, sz), RAIL, Enum.Material.Metal, false)
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(226, 244, 252))
	spray.Size = NumberSequence.new(0.18)
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.8) })
	spray.Lifetime = NumberRange.new(0.5, 0.7)
	spray.Speed = NumberRange.new(10, 12)
	spray.SpreadAngle = Vector2.new(8, 8)
	spray.EmissionDirection = Enum.NormalId.Bottom
	spray.Rate = 60
	spray.Parent = head
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	steam.Color = ColorSequence.new(Color3.fromRGB(250, 250, 250))
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 1) })
	steam.Lifetime = NumberRange.new(2, 3)
	steam.Speed = NumberRange.new(0.5, 1)
	steam.EmissionDirection = Enum.NormalId.Top
	steam.Rate = 3
	steam.Parent = head
	waterSound(head, "Shower", 1.4, 0.25, 3, 25)
	-- Three lockers on the side wall, the middle one open, with a towel and the note inside.
	for index = 0, 2 do
		local z = z0 + 2 + index * 1.7
		local locker = put(x1 - 1.2, 3, z)
		local metal = Color3.fromRGB(150, 196, 214)
		if index ~= 1 then
			block(parent, "Locker", Vector3.new(1.4, 6, 1.6), locker, metal, Enum.Material.Metal, true)
		else
			-- The open one is a shell, so what is in it can be seen.
			for _, piece in ipairs({ { 0.65, 0, 0, 0.1, 6, 1.6 }, { 0, 0, -0.75, 1.4, 6, 0.1 }, { 0, 0, 0.75, 1.4, 6, 0.1 },
				{ 0, 2.95, 0, 1.4, 0.1, 1.6 }, { 0, -2.95, 0, 1.4, 0.1, 1.6 } }) do
				block(parent, "Locker", Vector3.new(piece[4], piece[5], piece[6]), locker * CFrame.new(piece[1], piece[2], piece[3]), metal,
					Enum.Material.Metal, true)
			end
			block(parent, "LockerDoor", Vector3.new(0.1, 5.6, 1.5), locker * CFrame.new(-0.7, 0, -0.75) * CFrame.Angles(0, math.rad(70), 0)
				* CFrame.new(0, 0, 0.75), Color3.fromRGB(170, 212, 226), Enum.Material.Metal, false)
			block(parent, "FoldedTowel", Vector3.new(1, 0.5, 1.2), locker * CFrame.new(-0.45, -1, 0), PASTELS[rng:NextInteger(1, #PASTELS)],
				Enum.Material.Fabric, false)
			local note = block(parent, "LockerNote", Vector3.new(0.05, 1, 1.1), locker * CFrame.new(0.58, 1.2, 0), Color3.fromRGB(250, 248, 236),
				Enum.Material.SmoothPlastic, false)
			label(note, Enum.NormalId.Left, "LOST PROPERTY\none flip-flop (left)\nask at Pump Room 2", Color3.fromRGB(60, 60, 80))
		end
	end
	-- A bench, and a robe on a hook.
	block(parent, "Bench", Vector3.new(1.2, 0.5, 3.5), put(cx, 1.4, cz + 0.5), Color3.fromRGB(190, 160, 120), Enum.Material.Wood, true)
	for _, dz in ipairs({ -1.4, 1.4 }) do
		block(parent, "BenchLeg", Vector3.new(0.9, 1.15, 0.3), put(cx, 0.58, cz + 0.5 + dz), RAIL, Enum.Material.Metal, false)
	end
	block(parent, "Hook", Vector3.new(0.4, 0.2, 0.2), put(x0 + 0.6, 6, cz + 1.5), RAIL, Enum.Material.Metal, false)
	ellipsoid(parent, "Robe", Vector3.new(0.8, 3.6, 1.6), put(x0 + 0.95, 4.3, cz + 1.5), stripe)
	-- The lamp in the ceiling, showing through the doorway.
	local fixture = block(parent, "CabanaLamp", Vector3.new(1, 0.3, 1), put(cx, h - 0.2, cz), COPING, Enum.Material.SmoothPlastic, false)
	local light = Instance.new("PointLight")
	light.Brightness = 0.5
	light.Range = 14
	light.Color = Color3.fromRGB(255, 226, 190)
	light.Parent = fixture
end

-- ===== THE LIFEGUARD'S CHAIR =====
--
-- On the far side of the pool from the diving board, facing the water, tall enough to see the whole
-- pool from: four posts, a seat you can stand on, a backrest, a ladder up the front, a little shade
-- over it, and a lifebuoy on its own post beside it. In the terrace's frame.
local function lifeguard(parent: Instance, frame: CFrame, poolX: number, pz: number)
	local cz = -pz - LIFEGUARD_BACK
	local seatY = 6
	local white = COPING
	for _, corner in ipairs({ { -1.2, -1.2 }, { 1.2, -1.2 }, { -1.2, 1.2 }, { 1.2, 1.2 } }) do
		local at = (frame * CFrame.new(poolX + corner[1], 0, cz + corner[2])).Position
		column(parent, "ChairPost", 0.4, at, at.Y, at.Y + seatY, white, Enum.Material.SmoothPlastic, true)
	end
	block(parent, "ChairSeat", Vector3.new(3, 0.4, 3), frame * CFrame.new(poolX, seatY + 0.2, cz), white, Enum.Material.SmoothPlastic, true)
	block(parent, "ChairBack", Vector3.new(3, 2.6, 0.3), frame * CFrame.new(poolX, seatY + 1.7, cz - 1.35), white, Enum.Material.SmoothPlastic, true)
	local ladder = Instance.new("TrussPart")
	ladder.Name = "ChairLadder"
	ladder.Size = Vector3.new(2, 6, 2)
	ladder.CFrame = frame * CFrame.new(poolX, seatY / 2, cz + 2.5)
	ladder.Anchored = true
	ladder.Color = white
	ladder.Material = Enum.Material.SmoothPlastic
	ladder.Parent = parent
	local pole = (frame * CFrame.new(poolX - 1.3, seatY + 0.4, cz - 1.3)).Position
	column(parent, "ChairShadePole", 0.3, pole, pole.Y, pole.Y + 4.5, white, Enum.Material.Metal, false)
	-- The shade over the middle of the seat, in the terrace's frame rather than the world's.
	local shadeAt = (frame * CFrame.new(poolX, 0, cz)).Position
	column(parent, "ChairShade", 5, shadeAt, pole.Y + 4.4, pole.Y + 4.8, Color3.fromRGB(236, 110, 90), Enum.Material.Fabric, false)
	local sign = block(parent, "ChairSign", Vector3.new(2.4, 1, 0.1), frame * CFrame.new(poolX, seatY - 1.2, cz + 1.3), Color3.fromRGB(236, 110, 90),
		Enum.Material.SmoothPlastic, false)
	label(sign, Enum.NormalId.Back, "NO RUNNING", Color3.fromRGB(255, 255, 255))
	-- THE LIFEBUOY on its post: eight pieces round, red and white.
	local buoyPost = (frame * CFrame.new(poolX + 4, 0, cz)).Position
	column(parent, "BuoyPost", 0.35, buoyPost, buoyPost.Y, buoyPost.Y + 4.2, white, Enum.Material.Metal, false)
	-- Hung on the pool side of its post, facing the water.
	local hangAt = buoyPost + Vector3.new(0, 3, 0) - frame.LookVector * 0.3
	local ring = CFrame.lookAt(hangAt, hangAt - frame.LookVector)
	for index = 0, 7 do
		local a = index * math.pi / 4
		ellipsoid(parent, "Lifebuoy", Vector3.new(0.8, 0.8, 0.5), ring * CFrame.new(math.cos(a) * 1.1, math.sin(a) * 1.1, 0),
			if index % 2 == 0 then Color3.fromRGB(230, 70, 60) else Color3.fromRGB(250, 250, 248))
	end
end

-- ===== HOT AIR BALLOONS =====
--
-- Far out and high up, drifting slowly round the level: the one thing here that floats, because
-- floating is what it is for. The client moves them (SkyPoolsClient) from the orbit on each; here they
-- only stand where they start. Each is an envelope with a band round it, ropes, a wicker basket, and
-- a burner with a real light in it that the client flares now and then.
local function balloons(parent: Instance, centre: Vector3, radius: number, startY: number)
	for index = 1, BALLOONS do
		local orbit = radius + rng:NextNumber(600, 1000)
		local height = startY + rng:NextNumber(90, 140) -- baskets clear of the highest scenery pool's parasol
		local phase = (index / BALLOONS) * 2 * math.pi + rng:NextNumber(-0.3, 0.3)
		local at = CFrame.new(centre + Vector3.new(math.cos(phase) * orbit, height, math.sin(phase) * orbit))
		local balloon = Instance.new("Model")
		balloon.Name = "Balloon"
		local colour = PASTELS[(index - 1) % #PASTELS + 1]
		local band = PASTELS[index % #PASTELS + 1]
		ellipsoid(balloon, "Envelope", Vector3.new(26, 30, 26), at, colour)
		ellipsoid(balloon, "EnvelopeBand", Vector3.new(26.6, 8, 26.6), at * CFrame.new(0, 2, 0), band)
		ellipsoid(balloon, "Skirt", Vector3.new(10, 10, 10), at * CFrame.new(0, -14, 0), colour)
		local basketAt = at * CFrame.new(0, -26, 0)
		block(balloon, "Basket", Vector3.new(4, 3.4, 4), basketAt, Color3.fromRGB(150, 110, 70), Enum.Material.Wood, false)
		for _, corner in ipairs({ { -1.8, -1.8 }, { 1.8, -1.8 }, { -1.8, 1.8 }, { 1.8, 1.8 } }) do
			local from = (basketAt * CFrame.new(corner[1], 1.7, corner[2])).Position
			local to = (at * CFrame.new(corner[1] * 1.6, -17, corner[2] * 1.6)).Position
			local length = (to - from).Magnitude
			block(balloon, "Rope", Vector3.new(0.15, 0.15, length), CFrame.lookAt((from + to) / 2, to), Color3.fromRGB(120, 100, 80),
				Enum.Material.SmoothPlastic, false)
		end
		local burner = block(balloon, "Burner", Vector3.new(1.2, 1, 1.2), basketAt * CFrame.new(0, 3.2, 0), RAIL, Enum.Material.Metal, false)
		local flame = Instance.new("PointLight")
		flame.Name = "Flame"
		flame.Brightness = 0.6
		flame.Range = 16
		flame.Color = Color3.fromRGB(255, 180, 110)
		flame.Parent = burner
		balloon.WorldPivot = at
		balloon:SetAttribute("Centre", centre)
		balloon:SetAttribute("Orbit", orbit)
		balloon:SetAttribute("Height", height)
		balloon:SetAttribute("Phase", phase)
		balloon.Parent = parent
		CollectionService:AddTag(balloon, "SkyBalloon")
	end
end

-- ===== THE PUMP ROOM =====
--
-- In the terrace's frame (see terrace). `x0` is the terrace's inner edge, `px1` the pool's outer one.
local function pumpRoom(parent: Instance, frame: CFrame, x0: number, px1: number, groundY: number)
	local hx0 = x0 + HATCH_FROM
	local top = -DECK_THICK
	local floorTop = top - ROOM_DOWN
	local rx0, rx1 = x0 + 0.5, math.min(px1 - 2, x0 + ROOM_LONG)
	local midX, midZ = (rx0 + rx1) / 2, (ROOM_Z0 + ROOM_Z1) / 2
	local lenX, lenZ = rx1 - rx0, ROOM_Z1 - ROOM_Z0
	local grey = Color3.fromRGB(196, 202, 206)
	block(parent, "PumpRoomFloor", Vector3.new(lenX, 1, lenZ), frame * CFrame.new(midX, floorTop - 0.5, midZ), grey,
		Enum.Material.Concrete, true)
	for _, wall in ipairs({ { rx0 + 0.4, midZ, 0.8, lenZ }, { rx1 - 0.4, midZ, 0.8, lenZ }, { midX, ROOM_Z0 + 0.4, lenX, 0.8 },
		{ midX, ROOM_Z1 - 0.4, lenX, 0.8 } }) do
		block(parent, "PumpRoomWall", Vector3.new(wall[3], ROOM_DOWN + 1, wall[4]),
			frame * CFrame.new(wall[1], (top + floorTop - 1) / 2, wall[2]), grey, Enum.Material.Concrete, true)
	end

	-- The hatch: a rim, the lid standing open with a word on it, and a ladder that climbs out past the deck.
	for _, edge in ipairs({ { hx0 + HATCH / 2, HATCH_Z - 0.15, HATCH + 0.6, 0.3 }, { hx0 + HATCH / 2, HATCH_Z + HATCH + 0.15, HATCH + 0.6, 0.3 },
		{ hx0 - 0.15, HATCH_Z + HATCH / 2, 0.3, HATCH }, { hx0 + HATCH + 0.15, HATCH_Z + HATCH / 2, 0.3, HATCH } }) do
		block(parent, "HatchRim", Vector3.new(edge[3], 0.2, edge[4]), frame * CFrame.new(edge[1], 0.1, edge[2]), RAIL,
			Enum.Material.Metal, false)
	end
	local lid = block(parent, "HatchLid", Vector3.new(0.3, HATCH, HATCH), frame * CFrame.new(hx0 + HATCH + 0.45, HATCH / 2, HATCH_Z + HATCH / 2),
		BAND, Enum.Material.SmoothPlastic, true)
	label(lid, Enum.NormalId.Left, "STAFF ONLY", Color3.fromRGB(60, 70, 80))
	local ladder = Instance.new("TrussPart")
	ladder.Name = "HatchLadder"
	ladder.Size = Vector3.new(2, 16, 2)
	ladder.CFrame = frame * CFrame.new(hx0 + 1, floorTop + 8, HATCH_Z + HATCH / 2)
	ladder.Anchored = true
	ladder.Color = RAIL
	ladder.Material = Enum.Material.Metal
	ladder.Parent = parent

	-- Two pumps feeding the pool overhead, each with its pipe up into the pool's floor.
	for _, z in ipairs({ -4.5, 2.5 }) do
		local at = frame * CFrame.new(rx1 - 7, floorTop, z)
		block(parent, "PumpBase", Vector3.new(6, 1, 3), at * CFrame.new(0, 0.5, 0), Color3.fromRGB(90, 96, 104), Enum.Material.Metal, true)
		local body = block(parent, "Pump", Vector3.new(5, 3, 3), at * CFrame.new(0, 2.5, 0), Color3.fromRGB(70, 130, 170),
			Enum.Material.Metal, true)
		body.Shape = Enum.PartType.Cylinder
		block(parent, "PumpMotor", Vector3.new(2, 2.2, 2.2), at * CFrame.new(-3.4, 2.5, 0), Color3.fromRGB(60, 64, 70),
			Enum.Material.Metal, true)
		local riser = at * Vector3.new(1.5, 4, 0)
		column(parent, "PumpPipe", 1, riser, riser.Y, (frame * Vector3.new(0, top, 0)).Y, RAIL, Enum.Material.Metal, false)
		waterSound(body, "PumpHum", 0.2, 0.25, 6, 30)
	end
	-- THE OVERFLOW, down through the floor and all the way to the sea.
	local downpipe = frame * Vector3.new(rx1 - 1.5, 0, ROOM_Z0 + 1.5)
	column(parent, "Downpipe", 1.2, downpipe, groundY, (frame * Vector3.new(0, floorTop + 3, 0)).Y, RAIL, Enum.Material.Metal, false)
	-- The panel, its three buttons, the lamp, the log, a drain in the floor, and a mop somebody left.
	block(parent, "Panel", Vector3.new(3, 2.2, 0.4), frame * CFrame.new(midX - 3, floorTop + 4, ROOM_Z1 - 1), Color3.fromRGB(210, 214, 216),
		Enum.Material.SmoothPlastic, false)
	for index, tone in ipairs({ Color3.fromRGB(200, 70, 60), Color3.fromRGB(80, 170, 90), Color3.fromRGB(220, 170, 60) }) do
		block(parent, "PanelButton", Vector3.new(0.4, 0.4, 0.2), frame * CFrame.new(midX - 4.4 + index * 0.7, floorTop + 4.3, ROOM_Z1 - 1.3),
			tone, Enum.Material.SmoothPlastic, false)
	end
	local log = block(parent, "PumpLog", Vector3.new(5, 3, 0.1), frame * CFrame.new(midX + 3, floorTop + 4.5, ROOM_Z1 - 0.85),
		Color3.fromRGB(236, 232, 218), Enum.Material.SmoothPlastic, false)
	label(log, Enum.NormalId.Front, "PUMP ROOM 2\nKeep the water moving.\nOverflow runs to the sea.\nThe sea runs to the drain.",
		Color3.fromRGB(50, 50, 60))
	local fixture = block(parent, "PumpLamp", Vector3.new(1.2, 0.6, 1.2), frame * CFrame.new(midX, top - 0.3, midZ),
		Color3.fromRGB(240, 230, 200), Enum.Material.SmoothPlastic, false)
	local light = Instance.new("PointLight")
	light.Brightness = 0.8
	light.Range = 18
	light.Color = Color3.fromRGB(255, 220, 180)
	light.Shadows = true
	light.Parent = fixture
	local drainAt = frame * Vector3.new(midX, floorTop, midZ)
	column(parent, "FloorDrain", 2, drainAt, drainAt.Y, drainAt.Y + 0.06, Color3.fromRGB(50, 54, 58), Enum.Material.Metal, false)
	local bucketAt = frame * Vector3.new(rx0 + 2, floorTop, ROOM_Z1 - 2.5)
	column(parent, "Bucket", 1.4, bucketAt, bucketAt.Y, bucketAt.Y + 1.4, Color3.fromRGB(90, 140, 190), Enum.Material.SmoothPlastic, false)
	rod(parent, "Mop", bucketAt + Vector3.new(0, 0.4, 0), (frame * CFrame.new(rx0 + 1.1, floorTop + 5, ROOM_Z1 - 1.2)).Position, 0.2,
		Color3.fromRGB(170, 140, 100))
end

-- ===== A POOL TERRACE =====
--
-- Built in `frame`: its origin is the terrace's inner edge at deck height, +X runs outward away from
-- the level, +Z along the route. The deck is laid as four strips round the pool's opening, so their
-- inner faces ARE the pool's walls, and the pool has a floor POOL_DEPTH down you can stand on.
-- Columns and the spill go down to `groundY`, the sea.
local function terrace(parent: Instance, frame: CFrame, x0: number, wide: number, long: number,
	groundY: number, dressing: { string })
	local x1 = x0 + wide
	local poolX = x0 + wide * 0.55
	local px0, px1 = poolX - POOL_W / 2, poolX + POOL_W / 2
	local pz = POOL_L / 2
	local lz = long / 2

	local function strip(ax: number, bx: number, az: number, bz: number)
		block(parent, "Deck", Vector3.new(bx - ax, DECK_THICK, bz - az),
			frame * CFrame.new((ax + bx) / 2, -DECK_THICK / 2, (az + bz) / 2), DECK, Enum.Material.SmoothPlastic, true)
	end
	-- The inner strip, with the pump room's hatch cut out of it when this terrace has one.
	local hasRoom = table.find(dressing, "pumproom") ~= nil
	if hasRoom then
		local hx0, hx1 = x0 + HATCH_FROM, x0 + HATCH_FROM + HATCH
		strip(x0, hx0, -lz, lz)
		strip(hx1, px0, -lz, lz)
		strip(hx0, hx1, -lz, HATCH_Z)
		strip(hx0, hx1, HATCH_Z + HATCH, lz)
	else
		strip(x0, px0, -lz, lz)
	end
	strip(px1, x1, -lz, lz)
	strip(px0, px1, -lz, -pz)
	strip(px0, px1, pz, lz)

	-- The pool: its floor, its water, and a coping flush with the deck round the opening.
	local floor = block(parent, "PoolFloor", Vector3.new(POOL_W, 1, POOL_L),
		frame * CFrame.new(poolX, -POOL_DEPTH - 0.5, 0), TILE, tileMaterial or Enum.Material.SmoothPlastic, true)
	if tileMaterial then
		floor.MaterialVariant = TILE_VARIANT
	end
	-- Tagged, so the client can splash and ripple when someone walks into it.
	CollectionService:AddTag(water(parent, "PoolWater", Vector3.new(POOL_W, 0.3, POOL_L), frame * CFrame.new(poolX, -0.55, 0)),
		"SkyPoolWater")
	for _, edge in ipairs({ { 0, -pz, POOL_W + 2, 1.2 }, { 0, pz, POOL_W + 2, 1.2 },
		{ -POOL_W / 2, 0, 1.2, POOL_L + 2 }, { POOL_W / 2, 0, 1.2, POOL_L + 2 } }) do
		block(parent, "Coping", Vector3.new(edge[3], 0.14, edge[4]),
			frame * CFrame.new(poolX + edge[1], 0.07, edge[2]), COPING, Enum.Material.SmoothPlastic, false)
	end

	-- The overflow: a shallow channel from the pool to the outer edge, and the fall off it.
	local channel = 8
	water(parent, "Spill", Vector3.new(x1 - px1, 0.2, channel), frame * CFrame.new((px1 + x1) / 2, 0.05, 0))
	waterfall(parent, frame * Vector3.new(x1 + 0.7, -0.2, 0), frame.RightVector, channel, groundY, 90)

	-- COLUMNS to the sea, under the terrace's four corners, each with a collar at the top.
	for _, corner in ipairs({ { x0 + 5, -lz + 5 }, { x0 + 5, lz - 5 }, { x1 - 5, -lz + 5 }, { x1 - 5, lz - 5 } }) do
		local top = frame * Vector3.new(corner[1], -DECK_THICK, corner[2])
		column(parent, "Column", COLUMN_D, top, groundY, top.Y, STONE, Enum.Material.SmoothPlastic, true)
		column(parent, "Collar", COLUMN_D + 2, top, top.Y - 2.4, top.Y, BAND, Enum.Material.SmoothPlastic, false)
	end

	-- ===== Furniture: things people leave by a pool =====
	local colour = PASTELS[rng:NextInteger(1, #PASTELS)]
	local innerX = (x0 + px0) / 2
	for _, what in ipairs(dressing) do
		if what == "loungers" then
			-- Backrest at the inner end, so whoever lies here faces the pool and the sky past it.
			for _, z in ipairs({ -lz * 0.45, lz * 0.45 }) do
				local at = frame * CFrame.new(innerX, 0, z) * CFrame.Angles(0, math.pi / 2, 0)
				block(parent, "Lounger", Vector3.new(2.6, 0.6, 6.2), at * CFrame.new(0, 0.9, 0), COPING,
					Enum.Material.SmoothPlastic, true)
				block(parent, "Cushion", Vector3.new(2.4, 0.3, 4.2), at * CFrame.new(0, 1.35, 0.9), colour,
					Enum.Material.Fabric, false)
				block(parent, "Backrest", Vector3.new(2.6, 0.5, 2.8),
					at * CFrame.new(0, 2.0, -2.4) * CFrame.Angles(math.rad(-38), 0, 0), colour, Enum.Material.Fabric, false)
				for _, leg in ipairs({ { -1, -2.6 }, { 1, -2.6 }, { -1, 2.6 }, { 1, 2.6 } }) do
					block(parent, "LoungerLeg", Vector3.new(0.3, 0.6, 0.3), at * CFrame.new(leg[1] * 1.1, 0.3, leg[2]),
						RAIL, Enum.Material.Metal, false)
				end
			end
		elseif what == "parasol" then
			local foot = frame * Vector3.new(innerX, 0, 0)
			column(parent, "ParasolPole", 0.5, foot, foot.Y, foot.Y + 9, COPING, Enum.Material.Metal, false)
			column(parent, "ParasolBase", 2.2, foot, foot.Y, foot.Y + 0.4, BAND, Enum.Material.SmoothPlastic, false)
			column(parent, "Parasol", 10, foot, foot.Y + 8.9, foot.Y + 9.5, colour, Enum.Material.Fabric, false)
		elseif what == "towel" then
			-- A TOWEL SOMEBODY LEFT, half over the coping.
			local at = frame * CFrame.new(px0 + 2, 0.12, pz + 2.6) * CFrame.Angles(0, math.rad(rng:NextNumber(-25, 25)), 0)
			block(parent, "Towel", Vector3.new(3.2, 0.12, 5.4), at, colour, Enum.Material.Fabric, false)
			block(parent, "TowelStripe", Vector3.new(3.22, 0.13, 0.8), at * CFrame.new(0, 0, 1.4), COPING,
				Enum.Material.Fabric, false)
		elseif what == "ladder" then
			-- On the inner wall, so you climb out on the side you came from.
			local x = px0 + 0.6
			for _, side in ipairs({ -1, 1 }) do
				local rail = frame * Vector3.new(x, 0, side * 1.2)
				rod(parent, "LadderRail", rail + Vector3.new(0, -POOL_DEPTH, 0), rail + Vector3.new(0, 2.8, 0), 0.35, RAIL)
			end
			for index = 1, 3 do
				local rung = frame * Vector3.new(x, -POOL_DEPTH + index * 1.1, 0)
				rod(parent, "LadderRung", rung - frame.LookVector * 1.2, rung + frame.LookVector * 1.2, 0.25, RAIL)
			end
		elseif what == "board" then
			-- A DIVING BOARD, from the inner deck out over the pool. You can walk out on it and
			-- jump off it into the water, which is all it is for.
			local foot = frame * CFrame.new(px0 - 3, 0, -pz * 0.5)
			block(parent, "BoardStand", Vector3.new(3, 1.4, 3), foot * CFrame.new(0, 0.7, 0), BAND,
				Enum.Material.SmoothPlastic, true)
			block(parent, "DivingBoard", Vector3.new(12, 0.5, 3), foot * CFrame.new(4, 1.65, 0), COPING,
				Enum.Material.SmoothPlastic, true)
		elseif what == "duck" or what == "swimring" then
			poolToy(parent, frame * CFrame.new(poolX, -0.4, 0), POOL_W / 2 - 3, POOL_L / 2 - 3, what)
		elseif what == "pumproom" then
			pumpRoom(parent, frame, x0, px1, groundY)
		elseif what == "cabana" then
			cabana(parent, frame, px0, pz, lz)
		elseif what == "lifeguard" then
			lifeguard(parent, frame, poolX, pz)
		end
	end
end

-- ===== THE CAP of a stable chunk, which is its walkable top =====
local function capOf(model: Instance): BasePart?
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") and item.Name == "SurfaceCap" then
			return item
		end
	end
	return nil
end

-- A terrace BESIDE a checkpoint chunk, on its outer side, flush with its top.
--
-- The neck meets the chunk's cap edge and is only as long as the chunk. The terrace proper starts
-- NECK studs further out, 16.4 from the route's centre line, because the widest chunk this level
-- can put next door reaches 13.4 (the straight chunk's own shelves) -- so the terrace, which is
-- longer than the chunk, overhangs its neighbours' ends with three studs to spare.
-- blender/check_skypools.py holds that true for the whole chunk pool.
local function terraceBeside(parent: Instance, chunk: Instance, centre: Vector3, groundY: number,
	dressing: { string }): boolean
	local cap = capOf(chunk)
	if not cap then
		return false
	end
	local flat = Vector3.new(cap.Position.X - centre.X, 0, cap.Position.Z - centre.Z)
	if flat.Magnitude < 1 then
		return false
	end
	local outward = flat.Unit
	local capCF = cap.CFrame
	local halfOut = math.abs(capCF.RightVector:Dot(outward)) * cap.Size.X / 2
		+ math.abs(capCF.LookVector:Dot(outward)) * cap.Size.Z / 2
	local along = Vector3.yAxis:Cross(outward)
	local halfAlong = math.abs(capCF.RightVector:Dot(along)) * cap.Size.X / 2
		+ math.abs(capCF.LookVector:Dot(along)) * cap.Size.Z / 2
	local top = cap.Position.Y + cap.Size.Y / 2
	local edge = Vector3.new(cap.Position.X, top, cap.Position.Z) + outward * halfOut
	local frame = CFrame.fromMatrix(edge, outward, Vector3.yAxis)

	block(parent, "Deck", Vector3.new(NECK, NECK_THICK, halfAlong * 2), frame * CFrame.new(NECK / 2, -NECK_THICK / 2, 0),
		DECK, Enum.Material.SmoothPlastic, true)
	terrace(parent, frame, NECK, TERRACE_W, TERRACE_L, groundY, dressing)
	return true
end

-- ===== THE CLOUD SEA =====
--
-- Wide, low ellipsoids in rings round the middle, bigger further out, their tops near one height,
-- and a second, bluer layer under them nearer the middle, so the ceiling over the final pool has
-- depth. Flat on purpose: see the header.
local function cloudSea(parent: Instance, centre: Vector3, top: number)
	local folder = Instance.new("Folder")
	folder.Name = "CloudSea"
	folder.Parent = parent
	local radius = 0
	while radius < CLOUD_REACH do
		local size = 120 + radius * 0.22
		local count = math.max(1, math.floor(2 * math.pi * radius / (size * 0.62)))
		for index = 1, count do
			local angle = (index + rng:NextNumber(-0.35, 0.35)) / count * math.pi * 2
			local reach = radius + rng:NextNumber(-size * 0.2, size * 0.2)
			local wide = size * rng:NextNumber(0.85, 1.25)
			local tall = wide * rng:NextNumber(0.16, 0.24)
			local at = centre + Vector3.new(math.cos(angle) * reach, top - tall * 0.5 + rng:NextNumber(-6, 4),
				math.sin(angle) * reach)
			local puff = ellipsoid(folder, "Cloud", Vector3.new(wide, tall, wide * rng:NextNumber(0.8, 1.0)),
				CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
				CLOUD_TOP:Lerp(CLOUD_UNDER, rng:NextNumber(0, 0.35)))
			puff.Transparency = rng:NextNumber(0.03, 0.12)
			if radius < CLOUD_UNDER_REACH and rng:NextNumber() < 0.7 then
				local under = ellipsoid(folder, "Cloud", Vector3.new(wide * 1.1, tall * 1.2, wide),
					CFrame.new(Vector3.new(at.X, top - CLOUD_THICK * 0.6, at.Z)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
					CLOUD_UNDER)
				under.Transparency = rng:NextNumber(0.1, 0.25)
			end
		end
		radius += size * 0.62
	end
end

-- ===== THE FOUNTAIN TOWER, from the sea to the basin =====
local function tower(parent: Instance, centre: Vector3, seaY: number, poolY: number, topY: number)
	column(parent, "Tower", TOWER_D, centre, seaY, topY - 8, STONE, Enum.Material.SmoothPlastic, true)
	-- Bands every seventy studs, so a column this tall has a scale you can read it by.
	local y = seaY + 40
	while y < topY - 30 do
		column(parent, "TowerBand", TOWER_D + 4, centre, y - 1.5, y + 1.5, BAND, Enum.Material.SmoothPlastic, false)
		y += 70
	end
	-- The capital, the basin, its water, and a jet in the middle of it.
	column(parent, "Capital", TOWER_D + 14, centre, topY - 14, topY - 8, STONE, Enum.Material.SmoothPlastic, true)
	column(parent, "Basin", BASIN_D, centre, topY - 8, topY, COPING, Enum.Material.SmoothPlastic, true)
	local basinWater = column(parent, "BasinWater", BASIN_D - 6, centre, topY - 0.1, topY + 0.3, WATER,
		Enum.Material.Glass, false)
	if basinWater then
		basinWater.Transparency = 0.3
	end
	local jet = column(parent, "Jet", 3, centre, topY, topY + 16, FALL, Enum.Material.Glass, false)
	if jet then
		jet.Transparency = 0.45
		local spray = Instance.new("ParticleEmitter")
		spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		spray.Color = ColorSequence.new(Color3.fromRGB(236, 250, 255))
		spray.LightEmission = 0.4
		spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.2) })
		spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		spray.Lifetime = NumberRange.new(1.4, 2.2)
		spray.Speed = NumberRange.new(18, 26)
		spray.SpreadAngle = Vector2.new(14, 14)
		spray.Acceleration = Vector3.new(0, -30, 0)
		-- The cylinder lies along X before its roll, so its Right face points up once it stands.
		spray.EmissionDirection = Enum.NormalId.Right
		spray.Rate = 40
		spray.Parent = jet
	end
	-- THE CURTAIN: the basin overflows all the way round, down through the clouds, into the pool.
	local sheets = 12
	local ring = BASIN_D / 2 + 0.8
	for index = 1, sheets do
		local angle = (index / sheets) * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		-- Every fourth sheet carries the sound, heard faintly all round the ring.
		waterfall(parent, centre + out * ring + Vector3.new(0, topY - 1, 0), out, 2 * math.pi * ring / sheets + 1, poolY,
			if index % 4 == 0 then 260 else nil)
	end
end

-- ===== THE FINAL POOL, under the clouds, and the sea it drains into =====
local function finalPool(parent: Instance, centre: Vector3, surfaceY: number, seaY: number)
	local floor = column(parent, "FinalPoolFloor", FINAL_RADIUS * 2, centre, surfaceY - FINAL_DEEP - 2,
		surfaceY - FINAL_DEEP, TILE, tileMaterial or Enum.Material.SmoothPlastic, true)
	if floor and tileMaterial then
		floor.MaterialVariant = TILE_VARIANT
	end
	-- The dish under the floor, and the ring of columns under the dish: the tower carries the middle
	-- and these carry the rim, down to the sea.
	column(parent, "FinalPoolDish", FINAL_RADIUS * 2 - 16, centre, surfaceY - FINAL_DEEP - 10, surfaceY - FINAL_DEEP - 2,
		STONE, Enum.Material.SmoothPlastic, true)
	for index = 1, 8 do
		local angle = (index / 8) * math.pi * 2 + math.pi / 8
		local at = centre + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (FINAL_RADIUS - 20)
		column(parent, "FinalPoolColumn", 12, at, seaY, surfaceY - FINAL_DEEP - 10, STONE, Enum.Material.SmoothPlastic, true)
	end
	local surface = column(parent, "FinalPoolWater", FINAL_RADIUS * 2 - 2, centre, surfaceY - 0.4, surfaceY, WATER,
		Enum.Material.Glass, false)
	if surface then
		surface.Transparency = 0.3
		surface.Reflectance = 0.12
		CollectionService:AddTag(surface, "SkyPoolWater")
	end
	-- Where the tower's curtain comes down into the pool: the loudest water in the level, heard from
	-- the slide on the way down.
	local landing = block(parent, "CurtainSound", Vector3.new(1, 1, 1), CFrame.new(centre + Vector3.new(BASIN_D / 2, surfaceY, 0)),
		WATER, Enum.Material.SmoothPlastic, false)
	landing.Transparency = 1
	waterSound(landing, "CurtainSplash", 0.5, 0.5, 20, 200)
	-- Three toys adrift in it.
	for index = 0, 2 do
		local a = index * 2.1 + 0.4
		poolToy(parent, CFrame.new(centre + Vector3.new(math.cos(a) * 50, surfaceY, math.sin(a) * 50)), 10, 10,
			if index == 1 then "duck" else "swimring")
	end
	local pieces = 40
	for index = 1, pieces do
		local angle = (index / pieces) * math.pi * 2
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local at = centre + out * (FINAL_RADIUS + 1.5) + Vector3.new(0, surfaceY - FINAL_DEEP / 2 - 0.2, 0)
		block(parent, "FinalPoolRim", Vector3.new(2 * math.pi * (FINAL_RADIUS + 1.5) / pieces + 0.6, FINAL_DEEP + 3.6, 3),
			CFrame.lookAt(at, at + out), COPING, Enum.Material.SmoothPlastic, true)
	end
	-- IT DRAINS INTO THE SEA: six falls off the rim, all the way down.
	for index = 1, 6 do
		local angle = (index / 6) * math.pi * 2 + 0.3
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		waterfall(parent, centre + out * (FINAL_RADIUS + 3.4) + Vector3.new(0, surfaceY + 0.6, 0), out, 16, seaY,
			if index % 3 == 1 then 140 else nil)
	end
	-- And the sea: nine plates, because a part stops at 2048 studs a side.
	for gx = -1, 1 do
		for gz = -1, 1 do
			local plate = block(parent, "Sea", Vector3.new(2048, 4, 2048),
				CFrame.new(centre + Vector3.new(gx * 2048, seaY - 2, gz * 2048)), SEA, Enum.Material.SmoothPlastic, false)
			plate.Reflectance = 0.3
		end
	end
end

-- ===== THE SLIDE =====

export type SlideSpec = {
	centre: Vector3,
	angle0: number,
	radius0: number,
	radius1: number,
	y0: number,
	y1: number,
	turns: number,
}

-- A point on the slide's floor at f in [0, 1]. Round the tower the way the route was going, in from
-- the finale deck to over the pool, and DOWN on a smoothstep, so it leaves the deck level, is
-- steepest in the clouds, and levels out over the water.
local function slidePoint(spec: SlideSpec, f: number): Vector3
	local theta = spec.angle0 + f * spec.turns * math.pi * 2
	local radius = spec.radius0 + (spec.radius1 - spec.radius0) * f
	local ease = f * f * (3 - 2 * f)
	return Vector3.new(spec.centre.X + math.cos(theta) * radius, spec.y0 + (spec.y1 - spec.y0) * ease,
		spec.centre.Z + math.sin(theta) * radius)
end

-- The trough's up, banked into the turn so a rider leans the way a slide makes you lean.
local function slideUp(spec: SlideSpec, f: number): Vector3
	local here = slidePoint(spec, f)
	local inward = Vector3.new(spec.centre.X - here.X, 0, spec.centre.Z - here.Z)
	if inward.Magnitude < 0.01 then
		return Vector3.yAxis
	end
	return (Vector3.yAxis + inward.Unit * 0.28).Unit
end

-- Distance along the slide at 200 even steps of f, for riding it at a speed rather than a rate of
-- f: the ring is three times further round at the top than at the bottom, and riding f evenly
-- would be fastest at the start and slowest into the pool, which is backwards.
local SAMPLES = 200
local function slideTable(spec: SlideSpec): { number }
	local distances = { 0 }
	local last = slidePoint(spec, 0)
	for index = 1, SAMPLES do
		local here = slidePoint(spec, index / SAMPLES)
		distances[index + 1] = distances[index] + (here - last).Magnitude
		last = here
	end
	return distances
end

local function fAtDistance(distances: { number }, s: number): number
	if s <= 0 then
		return 0
	end
	local total = distances[#distances]
	if s >= total then
		return 1
	end
	local low, high = 1, #distances
	while high - low > 1 do
		local mid = (low + high) // 2
		if distances[mid] <= s then
			low = mid
		else
			high = mid
		end
	end
	local span = distances[high] - distances[low]
	local within = if span > 0 then (s - distances[low]) / span else 0
	return ((low - 1) + within) / SAMPLES
end

local function buildSlide(parent: Instance, spec: SlideSpec, towerTopY: number): number
	local folder = Instance.new("Folder")
	folder.Name = "Slide"
	folder.Parent = parent
	local distances = slideTable(spec)
	local count = math.max(8, math.ceil(distances[#distances] / SLIDE_STEP))
	local rodEvery = math.max(1, math.floor(count / 18))
	for index = 0, count - 1 do
		local a, b = slidePoint(spec, index / count), slidePoint(spec, (index + 1) / count)
		local long = (b - a).Magnitude * 1.08 + 0.6
		local frame = CFrame.lookAt((a + b) / 2, b, slideUp(spec, (index + 0.5) / count))
		local floor = block(folder, "SlideFloor", Vector3.new(SLIDE_WIDE, 0.8, long), frame * CFrame.new(0, -0.4, 0), SLIDE,
			Enum.Material.SmoothPlastic, false)
		floor.Reflectance = 0.15
		for _, side in ipairs({ -1, 1 }) do
			block(folder, "SlideWall", Vector3.new(0.8, 2.6, long), frame * CFrame.new(side * (SLIDE_WIDE / 2 + 0.4), 0.9, 0),
				RAIL, Enum.Material.SmoothPlastic, false)
		end
		-- HUNG FROM THE TOWER: a rod from the trough up and in to the tower's face, every so often,
		-- climbing about one stud for every two it crosses, the way a cable-stayed deck is hung.
		if index % rodEvery == 0 and index > 0 then
			local inner = frame * Vector3.new(0, 2.2, 0)
			local toward = Vector3.new(spec.centre.X - inner.X, 0, spec.centre.Z - inner.Z)
			local reach = toward.Magnitude - TOWER_D / 2
			if reach > 2 then
				local anchor = inner + toward.Unit * reach
				anchor = Vector3.new(anchor.X, math.min(inner.Y + reach * 0.45, towerTopY - 20), anchor.Z)
				rod(folder, "SlideRod", inner, anchor, 1.2, RAIL)
			end
		end
	end
	return distances[#distances]
end

-- ===== THE FINALE DECK, at the end of the route =====
--
-- Built in the finish frame, where +X points away from the middle and +Z runs on along the route.
-- A walkway straight on from the last chunk, at its height, with the slide's mouth under an arch at
-- its far end; a pool terrace off its outer side; a rail along its inner side and its end, so the
-- natural thing -- walking forward -- does not walk you off it. Returns the mouth.
local function finaleDeck(parent: Instance, finish: CFrame, groundY: number): CFrame
	local halfW = WALK_W / 2
	block(parent, "Deck", Vector3.new(WALK_W, DECK_THICK, WALK_L), finish * CFrame.new(0, -DECK_THICK / 2, WALK_L / 2),
		DECK, Enum.Material.SmoothPlastic, true)
	for _, corner in ipairs({ { -halfW + 4, 4 }, { -halfW + 4, WALK_L - 4 } }) do
		local top = finish * Vector3.new(corner[1], -DECK_THICK, corner[2])
		column(parent, "Column", COLUMN_D, top, groundY, top.Y, STONE, Enum.Material.SmoothPlastic, true)
		column(parent, "Collar", COLUMN_D + 2, top, top.Y - 2.4, top.Y, BAND, Enum.Material.SmoothPlastic, false)
	end
	-- The terrace, sharing the walkway's outer edge; its own inner columns carry that side.
	terrace(parent, finish * CFrame.new(halfW, 0, WALK_L / 2), 0, 34, WALK_L, groundY, { "loungers", "parasol", "towel", "swimring" })

	-- The rail: along the inner side, and across the end either side of the mouth.
	local function railRun(from: Vector3, to: Vector3)
		rod(parent, "Railing", from + Vector3.new(0, 3, 0), to + Vector3.new(0, 3, 0), 0.4, RAIL)
		local posts = math.max(1, math.floor((to - from).Magnitude / 5))
		for index = 0, posts do
			local at = from:Lerp(to, index / posts)
			column(parent, "RailPost", 0.35, at, at.Y, at.Y + 3, RAIL, Enum.Material.Metal, false)
		end
		-- The one part of the rail that stops you: an invisible wall along it, as high as the rail.
		local mid = (from + to) / 2 + Vector3.new(0, 1.6, 0)
		local guard = block(parent, "RailGuard", Vector3.new(0.6, 3.2, (to - from).Magnitude),
			CFrame.lookAt(mid, to + Vector3.new(0, 1.6, 0)), RAIL, Enum.Material.SmoothPlastic, true)
		guard.Transparency = 1
	end
	railRun(finish * Vector3.new(-halfW + 0.4, 0, 1), finish * Vector3.new(-halfW + 0.4, 0, WALK_L - 0.4))
	railRun(finish * Vector3.new(-halfW + 0.4, 0, WALK_L - 0.4), finish * Vector3.new(-SLIDE_WIDE / 2 - 1, 0, WALK_L - 0.4))
	railRun(finish * Vector3.new(SLIDE_WIDE / 2 + 1, 0, WALK_L - 0.4), finish * Vector3.new(halfW - 0.4, 0, WALK_L - 0.4))

	-- An arch over the mouth, so the one way down reads as a way.
	local mouth = finish * CFrame.new(0, 0, WALK_L)
	for _, side in ipairs({ -1, 1 }) do
		local foot = (mouth * CFrame.new(side * (SLIDE_WIDE / 2 + 1.6), 0, -1)).Position
		column(parent, "ArchPost", 1.6, foot, foot.Y, foot.Y + 12, COPING, Enum.Material.SmoothPlastic, true)
	end
	block(parent, "ArchBeam", Vector3.new(SLIDE_WIDE + 6, 1.6, 2), mouth * CFrame.new(0, 12.6, -1), SLIDE,
		Enum.Material.SmoothPlastic, false)
	return mouth
end

-- ===== THE SCENERY POOLS =====
local function sceneryPools(parent: Instance, centre: Vector3, radius: number, lowY: number, highY: number,
	groundY: number)
	for index = 1, 8 do
		local angle = (index / 8) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local reach = radius + rng:NextNumber(300, 760)
		local at = centre + out * reach + Vector3.new(0, rng:NextNumber(lowY, highY), 0)
		local frame = CFrame.fromMatrix(at, out, Vector3.yAxis)
		local dressing = if index % 2 == 0 then { "loungers", "parasol" } else { "parasol" }
		terrace(parent, frame, 0, rng:NextNumber(34, 46), rng:NextNumber(28, 38), groundY, dressing)
	end
end

-- ===== WHERE IT ALL GOES =====
--
-- Every height in the level, from the route LevelService laid. Shared by build and by the check in
-- blender/check_skypools.py, which restates it: change one, change both.
function SkyPoolsService.heights(startY: number, killY: number, destroyY: number)
	local cloudTop = killY + CLOUD_ABOVE_KILL
	local poolY = math.max(cloudTop - CLOUD_THICK - FINAL_BELOW, destroyY + POOL_ABOVE_DESTROY)
	return {
		cloudTop = cloudTop,
		poolY = poolY,
		seaY = poolY - SEA_BELOW,
		topY = startY + TOWER_ABOVE,
	}
end

-- ===== BUILDING IT =====
--
-- From the level LevelService just laid: its chunks, its centre and radius, where it finishes and
-- where its kill plane is. Parented under `parent` (workspace.Levels), so it goes when the level
-- does. Returns the model, with the slide's shape recorded on it for attachSlide.
function SkyPoolsService.build(level: any, parent: Instance): Model?
	if not level or not level.placedChunks or #level.placedChunks == 0 or not level.finishFrame then
		warn("SkyPoolsService: the level has no chunks or no finish, so there is nothing to build round.")
		return nil
	end
	local variant = MaterialService:FindFirstChild(TILE_VARIANT)
	tileMaterial = if variant and variant:IsA("MaterialVariant") then variant.BaseMaterial else nil

	local base: Vector3 = level.centre or Vector3.zero
	-- Heights below are world heights. The chunks' surfaceY is measured from the route's base, the
	-- kill plane is compared against world height as it stands (Bootstrap), and the centre is used
	-- flat -- so nothing here depends on the base being at zero.
	local centre = Vector3.new(base.X, 0, base.Z)
	local chunks = level.placedChunks
	local startY = base.Y + chunks[1].surfaceY
	local killY: number = level.killY or (startY - 200)
	-- Readable by a script, though only settable by a plugin; in a pcall anyway, so a place where it
	-- cannot be read falls back to the default rather than failing the build.
	local readOk, destroyY = pcall(function()
		return workspace.FallenPartsDestroyHeight
	end)
	local h = SkyPoolsService.heights(startY, killY, if readOk and typeof(destroyY) == "number" then destroyY else -500)

	local model = Instance.new("Model")
	model.Name = "SkyPools"

	-- ===== The terraces, off the start and off four checkpoints spread along the route =====
	--
	-- Every stable chunk is a checkpoint; these are the ones that get a pool. The first, and the
	-- stable chunks nearest a fifth, two fifths, three fifths and four fifths of the way -- never
	-- the last, which the finale deck continues from.
	local stable = {}
	for index, entry in ipairs(chunks) do
		if entry.chunkId == "S1_Straight" and index < #chunks then
			table.insert(stable, entry)
		end
	end
	local chosen: { any } = {}
	if #stable > 0 then
		table.insert(chosen, stable[1])
		for _, share in ipairs({ 0.2, 0.4, 0.6, 0.8 }) do
			local wanted = share * #chunks
			local best: any, gap = nil, math.huge
			for _, entry in ipairs(stable) do
				local miss = math.abs(entry.index - wanted)
				if miss < gap and not table.find(chosen, entry) then
					best, gap = entry, miss
				end
			end
			if best then
				table.insert(chosen, best)
			end
		end
	end
	-- The second terrace has no parasol, because its inner deck is where the pump room's hatch is.
	local dressings = {
		{ "loungers", "parasol", "ladder", "swimring" },
		{ "loungers", "towel", "ladder", "pumproom", "duck" },
		{ "parasol", "towel", "board", "duck", "lifeguard" },
		{ "loungers", "parasol", "towel", "swimring", "cabana" },
		{ "loungers", "ladder", "parasol", "duck" },
	}
	local terraces = 0
	for index, entry in ipairs(chosen) do
		if terraceBeside(model, entry.model, centre, h.seaY, dressings[(index - 1) % #dressings + 1]) then
			terraces += 1
		end
	end

	-- ===== The finale deck and the slide =====
	--
	-- Level with the last chunk's cap where it has one, so the walkway meets it without a step.
	local finish: CFrame = level.finishFrame
	local lastCap = capOf(chunks[#chunks].model)
	if lastCap then
		local capTop = lastCap.Position.Y + lastCap.Size.Y / 2
		finish = finish + Vector3.new(0, capTop - finish.Position.Y, 0)
	end
	local mouth = finaleDeck(model, finish, h.seaY)
	local start = mouth.Position
	local flat = Vector3.new(start.X - centre.X, 0, start.Z - centre.Z)
	local spec: SlideSpec = {
		centre = centre,
		angle0 = math.atan2(flat.Z, flat.X),
		radius0 = flat.Magnitude,
		radius1 = SLIDE_END_RADIUS,
		y0 = start.Y,
		y1 = h.poolY + 0.4,
		turns = SLIDE_TURNS,
	}
	local slideLong = buildSlide(model, spec, h.topY)

	-- ===== The tower, the pool it stands in, the clouds, the sky round it =====
	finalPool(model, centre, h.poolY, h.seaY)
	tower(model, centre, h.seaY, h.poolY, h.topY)
	cloudSea(model, centre, h.cloudTop)
	local radius: number = level.radius or flat.Magnitude
	sceneryPools(model, centre, radius, h.cloudTop + 50, startY + 40, h.seaY)
	balloons(model, centre, radius, startY)

	-- The slide's shape, for attachSlide.
	model:SetAttribute("SlideCentre", spec.centre)
	model:SetAttribute("SlideAngle0", spec.angle0)
	model:SetAttribute("SlideRadius0", spec.radius0)
	model:SetAttribute("SlideRadius1", spec.radius1)
	model:SetAttribute("SlideY0", spec.y0)
	model:SetAttribute("SlideY1", spec.y1)
	model:SetAttribute("SlideTurns", spec.turns)
	model:SetAttribute("SlideMouth", mouth)
	-- For the gulls the client flies round the tower (SkyPoolsClient).
	model:SetAttribute("TowerTop", h.topY)
	model:SetAttribute("Gulls", GULLS)
	CollectionService:AddTag(model, "SkyPoolsLevel")

	-- PERSISTENT, like the City Shore backdrop: the clouds and the far pools are further out than
	-- streaming would keep, and scenery that loads late and leaves again is worse than none.
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	model.Parent = parent
	print(("SkyPoolsService: %d pool terraces, a %d-stud slide from %d down to the pool at %d, clouds at %d, "
		.. "%d parts."):format(terraces, math.floor(slideLong), math.floor(spec.y0), math.floor(h.poolY),
		math.floor(h.cloudTop), #model:GetDescendants()))
	return model
end

-- ===== RIDING IT =====
--
-- Hold E at the mouth and the slide carries you round the tower, down through the clouds, and into
-- the pool. Held, not pressed, for the reason the Flooded Halls' flume is: a tap can happen by
-- accident while running past, and this ends the level.
--
-- The rider is moved by writing the root's CFrame each frame, as on the flume: a physical slide
-- this long needs a tube tuned never to snag, and a ride nobody steers gains nothing from physics.

local riding: { [Player]: boolean } = {}
local arrivedAt: { [Player]: number } = {}

-- THE SLIDE OWNS ITS RIDER'S FALL. It ends in a pool a long way under the kill plane, which is set
-- just under the lowest chunk so an ordinary fall is caught in the clouds. From the moment a rider
-- leaves the mouth until the lobby takes them back, the kill plane must leave them alone -- the same
-- exemption the City Shore dive has. Fifteen seconds is well past the four the return waits.
function SkyPoolsService.ownsFall(player: Player): boolean
	if riding[player] then
		return true
	end
	local landed = arrivedAt[player]
	return landed ~= nil and os.clock() - landed < 15
end

local function splash(at: Vector3)
	local host = Instance.new("Part")
	host.Name = "Splash"
	host.Size = Vector3.new(1, 1, 1)
	host.CFrame = CFrame.new(at)
	host.Anchored = true
	host.CanCollide = false
	host.CanTouch = false
	host.CanQuery = false
	host.Transparency = 1
	host.Parent = workspace
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(236, 250, 255))
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0.2) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.6, 1.3)
	spray.Speed = NumberRange.new(14, 30)
	spray.SpreadAngle = Vector2.new(40, 40)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Acceleration = Vector3.new(0, -60, 0)
	spray.Rate = 0
	spray.Parent = host
	spray:Emit(70)
	local s = Instance.new("Sound")
	s.SoundId = WATER_SOUND
	s.PlaybackSpeed = 0.9
	s.Volume = 0.9
	s.RollOffMaxDistance = 150
	s.Parent = host
	s:Play()
	Debris:AddItem(host, 3)
end

function SkyPoolsService.attachSlide(model: Model, onArrive: ((Player) -> ())?): () -> ()
	local mouthValue = model:GetAttribute("SlideMouth")
	local centre = model:GetAttribute("SlideCentre")
	if typeof(mouthValue) ~= "CFrame" or typeof(centre) ~= "Vector3" then
		return function() end
	end
	local mouth: CFrame = mouthValue
	local spec: SlideSpec = {
		centre = centre,
		angle0 = model:GetAttribute("SlideAngle0") :: number,
		radius0 = model:GetAttribute("SlideRadius0") :: number,
		radius1 = model:GetAttribute("SlideRadius1") :: number,
		y0 = model:GetAttribute("SlideY0") :: number,
		y1 = model:GetAttribute("SlideY1") :: number,
		turns = model:GetAttribute("SlideTurns") :: number,
	}
	local distances = slideTable(spec)
	local total = distances[#distances]
	local seconds = math.clamp(total / SLIDE_SPEED, SLIDE_MIN_SECONDS, SLIDE_MAX_SECONDS)

	-- THE PROMPT SITS ON THE DECK, just short of the mouth, where you are standing when you see it.
	local mount = Instance.new("Part")
	mount.Name = "SlideMount"
	mount.Size = Vector3.new(12, 6, 12)
	mount.CFrame = mouth * CFrame.new(0, 3, -5)
	mount.Anchored = true
	mount.CanCollide = false
	mount.CanTouch = false
	mount.CanQuery = false
	mount.Transparency = 1
	mount.Parent = model

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Slide"
	prompt.ObjectText = "Down through the clouds"
	prompt.HoldDuration = 0.8
	prompt.MaxActivationDistance = 20
	prompt.RequiresLineOfSight = false
	prompt.Parent = mount

	local connection = prompt.Triggered:Connect(function(player: Player)
		if riding[player] then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and root:IsA("BasePart") and humanoid) then
			return
		end
		riding[player] = true
		arrivedAt[player] = nil

		task.spawn(function()
			-- PLATFORMSTAND, not Anchored, for the flume's reason: an anchored root arrives as a statue.
			humanoid.PlatformStand = true
			-- The rush of the slide, riding with you.
			local rush = waterSound(root, "SlideRush", 0.8, 0.45, 10, 60)
			local started = os.clock()
			local norm = 1 - SLIDE_RAMP / 2
			while true do
				local u = (os.clock() - started) / seconds
				if u >= 1 or not root.Parent then
					break
				end
				-- Distance along the slide: speeding up from standing over the first stretch, then
				-- steady, so it sets off like a slide and does not fire you off the deck.
				local share = if u < SLIDE_RAMP then (u * u / (2 * SLIDE_RAMP)) / norm else (u - SLIDE_RAMP / 2) / norm
				local f = fAtDistance(distances, share * total)
				local up = slideUp(spec, f)
				local here = slidePoint(spec, f) + up * 2.6
				local ahead = slidePoint(spec, fAtDistance(distances, share * total + 4)) + up * 2.6
				if (ahead - here).Magnitude > 0.05 then
					root.CFrame = CFrame.lookAt(here, ahead, up)
				end
				task.wait()
			end
			local landing = slidePoint(spec, 1)
			if root.Parent then
				splash(landing)
				-- Standing in the pool, where the slide ran out, facing on the way it was going.
				local onward = landing - slidePoint(spec, 0.99)
				onward = Vector3.new(onward.X, 0, onward.Z)
				local facing = if onward.Magnitude > 0.01 then onward.Unit else Vector3.new(0, 0, -1)
				local stand = landing + Vector3.new(0, 3, 0)
				root.CFrame = CFrame.lookAt(stand, stand + facing)
			end
			rush:Destroy()
			humanoid.PlatformStand = false
			riding[player] = nil
			arrivedAt[player] = os.clock()
			if onArrive then
				onArrive(player)
			end
		end)
	end)

	return function()
		connection:Disconnect()
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	riding[player] = nil
	arrivedAt[player] = nil
end)

return SkyPoolsService
