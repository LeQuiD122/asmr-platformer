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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- THE SLIDE'S SHAPE AND TIMING ARE SHARED with the client, which draws the ride from them, so they
-- live in one module both sides read. Looked for with a timeout for SunkenPath's reason: a bare
-- WaitForChild here would stop the whole server if the file had not been pasted in.
local skyPathModule = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SkyPath", 10)
local SkyPath: any = if skyPathModule and skyPathModule:IsA("ModuleScript") then require(skyPathModule) else nil
if not SkyPath then
	warn("SkyPoolsService: no ReplicatedStorage.Shared.SkyPath, so there is no slide. Paste "
		.. "src/Shared/SkyPath.lua in as a ModuleScript named exactly SkyPath.")
end

local SkyPoolsService = {}

-- ===== The terraces =====
--
-- A terrace is NOT A SQUARE. It is a narrow walk off the checkpoint, a wide middle with its corners
-- taken off where the pool and the sun decks are, and a rounded nose past the pool where the water
-- spills off into the clouds. The numbers below are shares of its width and length, so the scenery
-- pools further out come out the same shape at their own sizes.
local NECK = 9 -- the strip joining a terrace to its chunk; see terraceBeside for why nine
-- THE NECK IS DEEPER THAN THE DECK, so the chunk's own underside does not show beneath it. The
-- straight chunk used to carry side shelves reaching 13.4 out and hanging six under its top, and
-- this was 7.4 to swallow them; the shelves are gone (ChunkBuilder: they let you walk past the
-- honey and caught you falling off the Needoh), so what is left to cover is the slab itself, which
-- hangs 4.9 under the cap's top. blender/check_skypools.py holds this against the chunk's layout.
local NECK_THICK = 5.4
local TERRACE_W, TERRACE_L = 46, 36 -- outward from the neck, and along the route
local POOL_W, POOL_L = 22, 14 -- the pool's opening, the same two ways
-- DEEP ENOUGH TO SWIM IN. The pool used to be waist deep because it was a sheet of glass you walked
-- through; it is terrain water now, and you only swim once the water is over you. Getting out is
-- what the steps at the inner end are for, and the ladder at the deep one.
local POOL_DEPTH = 9
local DECK_THICK = POOL_DEPTH + 1 -- the deck is the pool's walls, so it is as deep as the pool
local COLUMN_D = 6
local ENTRY_SHARE = 0.33 -- the entry walk's half width, as a share of the terrace's length
local POOL_FROM = 0.26 -- where the pool starts, as a share of the terrace's width
local BEACH_STEPS = 4 -- the steps you walk in down at the inner end; each rise is under two studs
local STEP_RUN = 2 -- and each tread is this deep
local WATER_DROP = 0.35 -- the water's surface, this far under the deck

-- ===== The cloud sea, the final pool, the tower, the sea =====
-- The cloud sea's top sits this far above the kill plane, so a fall sinks into cloud just as it is
-- caught -- and since the route goes down, the last terraces are only a little way above it.
local CLOUD_ABOVE_KILL = 14
local CLOUD_THICK = 70
local CLOUD_REACH = 2400 -- far enough that its edge is lost in the haze rather than seen
local CLOUD_UNDER_REACH = 900 -- the underside only matters where you can see it: from the final pool
local FINAL_BELOW = 150 -- the final pool's surface, this far under the cloud sea's bottom
local FINAL_RADIUS = 105
-- DEEP ENOUGH TO SWIM IN, like the terrace pools: you land in it off the slide, and coming down
-- through the clouds into water you sink into is the ending this level was always describing.
local FINAL_DEEP = 10
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
--
-- How wide it is, how fast it is ridden and how long that takes are SkyPath's, because the client
-- works the ride out from the same numbers. What is left here is where it is put.
local SLIDE_TURNS = 0.85 -- round the tower from the finale deck to the pool; never under itself
local SLIDE_END_RADIUS = 70 -- where it lands: well inside the final pool, clear of the curtain
-- WHERE THE TOWER STANDS on a route that goes somewhere: this far to the SIDE of the slide's mouth,
-- not ahead of it. The slide is an arc round the tower, and an arc's tangent is across its radius --
-- so a tower straight ahead would send the first stud of the ride sideways off the end of the deck.
-- Beside it, the ride leaves the mouth going the way the walkway points and curves round the tower
-- from there.
local TOWER_ASIDE = 150
local SLIDE_WIDE = if SkyPath then SkyPath.WIDE else 10
-- THE MOUTH IS KEPT CLEAR. Nothing is built within this of the first stretch of the trough, so
-- nothing is in the way of the one thing you came down here to do.
local MOUTH_CLEAR = 16
local WALK_L, WALK_W = 34, 22 -- the finale walkway, along the route and across it

-- ===== The pump room, under one terrace =====
--
-- A hatch in the deck with its lid standing open, a ladder down, and a small room slung under the
-- deck on its own walls: two pumps feeding the pool above, a pipe carrying the overflow down to the
-- sea, a lamp, and the log on the wall. The one closed-off place in the level, for whoever looks.
-- BIG ENOUGH TO CLIMB OUT OF. It was four studs square, and the deck it is cut through is ten deep
-- now that the pool is deep enough to swim in -- so getting out was a character-width shaft with a
-- ladder in it, and it was reported as a place you get stuck. Six studs is wider than the ladder
-- plus a shoulder either side, and the rim is chamfered so the last step up has somewhere to go.
local HATCH = 6
local HATCH_FROM = 1.5 -- the hatch's inner edge, this far out from the terrace's inner edge
local HATCH_Z = -3 -- and its near side, this far along: the hatch is centred over the room
local ROOM_DOWN = 10 -- the room's floor, this far under the deck's underside
local ROOM_LONG = 22 -- outward, from the terrace's inner edge
-- ALONG THE ROUTE, THE ROOM IS NARROW. The columns that carry the pool's inner corners come down
-- either side of it at +-8, so the room keeps inside +-4.5 and they pass it with half a stud to
-- spare. blender/check_skypools.py holds that gap open.
local ROOM_Z0, ROOM_Z1 = -4.5, 4.5

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
local MOSAIC = Color3.fromRGB(58, 142, 172) -- the darker tile at the waterline and in the deck's inlay
local SLIDE = Color3.fromRGB(180, 164, 236)
local RAIL = Color3.fromRGB(246, 244, 252)
local SEA = Color3.fromRGB(58, 132, 176)
-- THE CLOUDS ARE NOT PAPER WHITE, and this is the other half of the same fix.
--
-- Everything in this level that you look DOWN at is seen against the cloud sea, and the chunks the
-- route is made of are translucent -- honey, jello, slime, ice. Pure white behind a pale translucent
-- surface leaves nothing for the eye: from above the chunk was a faint outline and from the side it
-- was itself. Taking the clouds two steps off white gives the material something to sit against,
-- costs nothing, and still reads as cloud because cloud in daylight is never actually white.
local CLOUD_TOP = Color3.fromRGB(236, 242, 250)
local CLOUD_UNDER = Color3.fromRGB(202, 214, 234)
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
-- A SEAT: furniture you can actually use. Roblox sits a character on any Seat it touches or that is
-- clicked, and that is the whole of what was missing from the loungers and the lifeguard's chair --
-- they were shapes of furniture rather than furniture.
--
-- The pad is the seat itself and it is the same size and place the cushion was, so nothing moves;
-- what changes is that standing on it sits you down. A lounger is a seat lying back, so its pad is
-- tipped with the frame it is part of and the character reclines with it.
local function seat(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3,
	material: Enum.Material): Seat
	local pad = Instance.new("Seat")
	pad.Name = name
	pad.Size = size
	pad.CFrame = cf
	pad.Color = colour
	pad.Material = material
	pad.Anchored = true
	pad.CanCollide = true
	pad.CanTouch = true
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.BottomSurface = Enum.SurfaceType.Smooth
	-- Nobody is thrown off it: this is a calm level, and a seat that ejects you at the first bump
	-- would be the opposite of what a sun lounger is for.
	pad.Disabled = false
	pad.Parent = parent
	return pad
end

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

-- ===== THE WATER YOU CAN SWIM IN =====
--
-- The pools used to be a glass plate you walked through. They are Roblox terrain water now, filled
-- into the part-built basins, so you swim in them with the engine's own strokes, waves and
-- underwater view.
--
-- Terrain is GLOBAL and it is not built per run, so every fill is remembered here and cleared when
-- the level is torn down. Without that, the next level would start with pools of water hanging in
-- its sky. The look (colour, waves, how far you can see) is global too, so the old values are kept
-- and put back the same way LightingService puts the lobby's air back.
local filled: { { cf: CFrame, size: Vector3 } } = {}
local terrainWas: { [string]: any } = {}

local function fillWater(cf: CFrame, size: Vector3)
	local terrain = workspace.Terrain
	terrain:FillBlock(cf, size, Enum.Material.Water)
	table.insert(filled, { cf = cf, size = size })
end

local function fillWaterCylinder(cf: CFrame, height: number, radius: number)
	local terrain = workspace.Terrain
	terrain:FillCylinder(cf, height, radius, Enum.Material.Water)
	-- Cleared as a block round it: FillBlock with Air over the cylinder's extent takes it all, and a
	-- box of air where there is nothing anyway costs nothing.
	table.insert(filled, { cf = cf, size = Vector3.new(radius * 2 + 4, height + 4, radius * 2 + 4) })
end

-- Puts every drop back. Called by Bootstrap before the next run is built, and by build() first, so
-- a place that was stopped mid-run does not keep the water.
function SkyPoolsService.clearWater()
	local terrain = workspace.Terrain
	for _, region in ipairs(filled) do
		pcall(function()
			terrain:FillBlock(region.cf, region.size + Vector3.new(2, 2, 2), Enum.Material.Air)
		end)
	end
	table.clear(filled)
	for name, value in pairs(terrainWas) do
		pcall(function()
			(terrain :: any)[name] = value
		end)
	end
	table.clear(terrainWas)
end

-- The look of the water, for this level: pale tropical blue, small waves, and clear enough to see
-- the tiles through. Remembered first, so clearWater can put the place back as it found it.
local function poolWaterLook()
	local terrain = workspace.Terrain
	for name, value in pairs({
		WaterColor = Color3.fromRGB(96, 200, 214),
		WaterTransparency = 0.55,
		WaterReflectance = 0.25,
		WaterWaveSize = 0.05,
		WaterWaveSpeed = 8,
	}) do
		pcall(function()
			if terrainWas[name] == nil then
				terrainWas[name] = (terrain :: any)[name]
			end
			(terrain :: any)[name] = value
		end)
	end
end

-- A FALL OF WATER: a veil from `top` down to `bottomY`, `wide` across, leaving the edge towards
-- `facing`, with a rolled lip of foam on the edge and spray coming off it.
--
-- Three sheets rather than one. Water leaving an edge is bright and nearly solid where it goes over,
-- and spreads and thins the further it falls, so each sheet behind the first is wider, softer and
-- widens faster, and the whole thing reads as depth instead of a pane of glass. With `roar`, the
-- fall is heard out to that many studs from its lip: the project's water sample pitched down, a
-- little differently for every fall so no two beat together.
local VEILS = {
	{ out = 0, alpha = 0.42, spread = 0.08, thick = 1.1 },
	{ out = 0.9, alpha = 0.64, spread = 0.3, thick = 2, tone = 0.4 },
	{ out = -0.9, alpha = 0.8, spread = 0.55, thick = 2.8, tone = 0.7 },
}
local function waterfall(parent: Instance, top: Vector3, facing: Vector3, wide: number, bottomY: number, roar: number?)
	local height = top.Y - bottomY
	if height <= 1 then
		return
	end
	local pieces = math.ceil(height / LONGEST)
	local each = height / pieces
	for veilIndex, veil in ipairs(VEILS) do
		for index = 1, pieces do
			local deep = (index - 0.5) * each
			local centre = Vector3.new(top.X, top.Y - deep, top.Z) + facing * veil.out
			local sheet = block(parent, "Waterfall",
				Vector3.new(wide * (1 + veil.spread * deep / height), each, veil.thick),
				CFrame.lookAt(centre, centre + facing), FALL:Lerp(Color3.new(1, 1, 1), veil.tone or 0),
				Enum.Material.Glass, false)
			sheet.Transparency = veil.alpha
			sheet.Reflectance = 0.08
			sheet.CastShadow = false
			-- TAGGED, so the client can run the shimmer down it (SkyPoolsClient). A sheet of glass
			-- is the right shape for falling water and the wrong amount of nothing: what says
			-- "moving" is the light travelling down it, and that is done where it costs nobody
			-- anything.
			sheet:SetAttribute("Veil", index + veilIndex * 0.37)
			sheet:SetAttribute("Alpha", veil.alpha)
			CollectionService:AddTag(sheet, "SkyFall")
		end
	end

	-- THE LIP: the foam on the edge itself, and the spray that comes off it. Only a fall with a real
	-- edge gets the foam -- a shower head over a queue is a fall too, and a slab of white on it
	-- would read as a mistake -- but every fall gets the spray.
	local lipAt = CFrame.lookAt(Vector3.new(top.X, top.Y, top.Z), top + facing)
	local foam = block(parent, "FallLip", if wide >= 4 then Vector3.new(wide + 1.4, 0.7, 2.8)
		else Vector3.new(wide, 0.2, 0.6), lipAt, Color3.fromRGB(250, 254, 255), Enum.Material.Glass, false)
	foam.Transparency = if wide >= 4 then 0.25 else 1
	foam.CastShadow = false
	local lip = Instance.new("Attachment")
	lip.Name = "Lip"
	lip.Position = Vector3.new(0, -0.4, 0)
	lip.Parent = foam
	local drops = Instance.new("ParticleEmitter")
	drops.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	drops.Color = ColorSequence.new(Color3.fromRGB(236, 250, 255))
	drops.LightEmission = 0.4
	drops.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) })
	drops.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	drops.Lifetime = NumberRange.new(1.2, 2.4)
	drops.Speed = NumberRange.new(2, 5)
	drops.SpreadAngle = Vector2.new(25, 10)
	drops.Acceleration = Vector3.new(0, -40, 0)
	drops.EmissionDirection = Enum.NormalId.Front
	drops.Rate = math.clamp(wide * 1.2, 6, 30)
	drops.Parent = lip

	-- THE WATER ITSELF, LEAVING. Long thin streaks thrown off the lip and pulled down, living long
	-- enough to travel a good stretch of the fall: this is the part that reads as moving water,
	-- because it is the only part that moves. Stretched by their own speed rather than drawn long,
	-- so they lengthen as they gather pace the way falling water does.
	local streaks = Instance.new("ParticleEmitter")
	streaks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	streaks.Color = ColorSequence.new(Color3.fromRGB(224, 246, 252))
	streaks.LightEmission = 0.35
	streaks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(0.3, 2.4),
		NumberSequenceKeypoint.new(1, 1.2) })
	streaks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.75, 0.6), NumberSequenceKeypoint.new(1, 1) })
	streaks.Lifetime = NumberRange.new(2.2, 3.6)
	streaks.Speed = NumberRange.new(12, 22)
	streaks.SpreadAngle = Vector2.new(8, 4)
	streaks.Acceleration = Vector3.new(0, -60, 0)
	streaks.EmissionDirection = Enum.NormalId.Bottom
	streaks.Rate = math.clamp(wide * 2.5, 12, 70)
	-- SQUASHED BY SPEED: a drop is round when it leaves the lip and a streak by the time it has
	-- fallen, which is what falling water looks like and what a round sprite never does.
	streaks.Squash = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 2.2) })
	streaks.Parent = lip

	-- THE MIST it makes further down, drifting back up the way mist off a fall does, on its own
	-- marker so it sits in the fall rather than on the lip. Only for a fall with room to make any:
	-- a shower head over a queue does not need weather.
	if height < 40 then
		if roar then
			waterSound(lip, "Roar", rng:NextNumber(0.38, 0.47), 0.3, 10, roar)
		end
		return
	end
	local mistAt = Vector3.new(top.X, top.Y - math.min(height * 0.35, 60), top.Z)
	local marker = block(parent, "FallMist", Vector3.new(wide, 1, 1), CFrame.lookAt(mistAt, mistAt + facing), FALL,
		Enum.Material.Glass, false)
	marker.Transparency = 1
	marker.CastShadow = false
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.fromRGB(244, 252, 255))
	mist.LightEmission = 0.6
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 22) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.86), NumberSequenceKeypoint.new(0.4, 0.92),
		NumberSequenceKeypoint.new(1, 1) })
	mist.Lifetime = NumberRange.new(3, 6)
	mist.Speed = NumberRange.new(1, 4)
	mist.SpreadAngle = Vector2.new(40, 40)
	mist.Acceleration = Vector3.new(0, 2, 0)
	mist.Rate = 4
	mist.Parent = marker
	-- WHERE IT LANDS. A fall that simply stops at the sea is a sheet with an end; water arriving
	-- makes foam, throws spray back up and boils for a few studs round the point it hits.
	local at = Vector3.new(top.X, bottomY + 1.5, top.Z) + facing * (wide * 0.12)
	local foamDisc = column(parent, "FallFoam", wide * 2.4, at, bottomY + 0.2, bottomY + 1.6,
		Color3.fromRGB(246, 253, 255), Enum.Material.Glass, false)
	if foamDisc then
		foamDisc.Transparency = 0.35
		foamDisc.CastShadow = false
	end
	local boil = block(parent, "FallBoil", Vector3.new(wide * 1.6, 1, wide * 1.6), CFrame.new(at),
		Color3.fromRGB(236, 250, 255), Enum.Material.Glass, false)
	boil.Transparency = 1
	boil.CastShadow = false
	local up = Instance.new("ParticleEmitter")
	up.Texture = "rbxasset://textures/particles/smoke_main.dds"
	up.Color = ColorSequence.new(Color3.fromRGB(250, 254, 255))
	up.LightEmission = 0.55
	up.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, wide * 0.5),
		NumberSequenceKeypoint.new(1, wide * 1.6) })
	up.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.5, 0.78), NumberSequenceKeypoint.new(1, 1) })
	up.Lifetime = NumberRange.new(2.4, 4.4)
	up.Speed = NumberRange.new(6, 14)
	up.SpreadAngle = Vector2.new(50, 50)
	up.Acceleration = Vector3.new(0, 3, 0)
	up.EmissionDirection = Enum.NormalId.Top
	up.Rate = math.clamp(wide * 0.8, 4, 22)
	up.Parent = boil
	if roar then
		waterSound(lip, "Roar", rng:NextNumber(0.38, 0.47), if roar > 150 then 0.35 else 0.3, 10, roar)
		waterSound(boil, "FallLanding", rng:NextNumber(0.3, 0.38), 0.3, 20, roar)
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
	seat(parent, "ChairSeat", Vector3.new(3, 0.4, 3), frame * CFrame.new(poolX, seatY + 0.2, cz), white,
		Enum.Material.SmoothPlastic)
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
	-- THE LADDER RUNS PAST THE DECK, not up to it. A ladder that stops level with the floor you are
	-- climbing to leaves nothing to hold while you step off, which is the other half of why this
	-- hole was hard to leave. TrussPart sizes come in twos, so this is the drop rounded up.
	local ladderTop = 3.5
	local ladderHigh = math.ceil((ladderTop - (floorTop - 1)) / 2) * 2
	local ladder = Instance.new("TrussPart")
	ladder.Name = "HatchLadder"
	ladder.Size = Vector3.new(2, ladderHigh, 2)
	ladder.CFrame = frame * CFrame.new(hx0 + 1.4, floorTop - 1 + ladderHigh / 2, HATCH_Z + HATCH / 2)
	ladder.Anchored = true
	ladder.Color = RAIL
	ladder.Material = Enum.Material.Metal
	ladder.Parent = parent
	-- A GRAB RAIL either side of the opening, at hand height, and a chamfer round the rim so the
	-- last pull up meets a slope rather than a lip.
	for _, side in ipairs({ -1, 1 }) do
		local railAt = frame * Vector3.new(hx0 + HATCH / 2, 0, HATCH_Z + HATCH / 2 + side * (HATCH / 2 + 0.6))
		rod(parent, "HatchRail", railAt + Vector3.new(0, 1.1, 0) - frame.RightVector * (HATCH / 2 - 0.4),
			railAt + Vector3.new(0, 1.1, 0) + frame.RightVector * (HATCH / 2 - 0.4), 0.3, RAIL)
		for _, post in ipairs({ -1, 1 }) do
			local foot = railAt + frame.RightVector * (post * (HATCH / 2 - 0.4))
			column(parent, "HatchRailPost", 0.3, foot, foot.Y, foot.Y + 1.1, RAIL, Enum.Material.Metal, false)
		end
	end

	-- Two pumps feeding the pool overhead, each with its pipe up into the pool's floor.
	for _, back in ipairs({ 6.5, 13.5 }) do
		local at = frame * CFrame.new(rx1 - back, floorTop, -0.6)
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
	local drainAt = frame * Vector3.new(rx0 + 4, floorTop, ROOM_Z1 - 2)
	column(parent, "FloorDrain", 2, drainAt, drainAt.Y, drainAt.Y + 0.06, Color3.fromRGB(50, 54, 58), Enum.Material.Metal, false)
	local bucketAt = frame * Vector3.new(rx0 + 2, floorTop, ROOM_Z1 - 2.5)
	column(parent, "Bucket", 1.4, bucketAt, bucketAt.Y, bucketAt.Y + 1.4, Color3.fromRGB(90, 140, 190), Enum.Material.SmoothPlastic, false)
	rod(parent, "Mop", bucketAt + Vector3.new(0, 0.4, 0), (frame * CFrame.new(rx0 + 1.1, floorTop + 5, ROOM_Z1 - 1.2)).Position, 0.2,
		Color3.fromRGB(170, 140, 100))
end

-- ===== A SUN LOUNGER =====
--
-- Not a slab with a cushion on it. A frame on four feet, slats across it, a back tipped up on its
-- own hinge with a prop under it and a pillow at the top, and a folded towel over the foot. Built
-- in `at`, a frame standing on the deck whose +Z runs from the foot of the bed to its head, so
-- whoever lies on it faces whatever is at -Z: the pool.
local function lounger(parent: Instance, at: CFrame, colour: Color3)
	local rail = Color3.fromRGB(246, 246, 244)
	local shade = colour:Lerp(Color3.new(0, 0, 0), 0.12)
	-- Feet, and the rails they hold up.
	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -2.3, 2.1 }) do
			block(parent, "LoungerFoot", Vector3.new(0.3, 1.1, 0.3), at * CFrame.new(side * 1.1, 0.55, z), rail,
				Enum.Material.Metal, false)
		end
		rod(parent, "LoungerRail", (at * CFrame.new(side * 1.1, 1.2, -2.9)).Position,
			(at * CFrame.new(side * 1.1, 1.2, 2.5)).Position, 0.3, rail)
	end
	-- The bed: slats across the rails, with a cushion over them you can lie on.
	for index = 0, 6 do
		block(parent, "LoungerSlat", Vector3.new(2.4, 0.16, 0.5), at * CFrame.new(0, 1.34, -2.6 + index * 0.84), rail,
			Enum.Material.SmoothPlastic, false)
	end
	-- THE CUSHION IS THE SEAT. Tipped back a few degrees with the bed, so lying on it puts you at the
	-- angle the back is set to rather than bolt upright on a flat pad.
	seat(parent, "LoungerCushion", Vector3.new(2.3, 0.32, 5.1),
		at * CFrame.new(0, 1.56, -0.2) * CFrame.Angles(math.rad(-6), 0, 0), colour, Enum.Material.Fabric)
	-- The back, leaning on its hinge over the head end, with the prop that holds it there.
	local hinge = at * CFrame.new(0, 1.4, 2.3) * CFrame.Angles(math.rad(34), 0, 0)
	for index = 0, 3 do
		block(parent, "LoungerBackSlat", Vector3.new(2.4, 0.16, 0.5), hinge * CFrame.new(0, 0.5 + index * 0.75, 0) *
			CFrame.Angles(math.rad(-90), 0, 0), rail, Enum.Material.SmoothPlastic, false)
	end
	block(parent, "LoungerBackCushion", Vector3.new(2.3, 2.8, 0.3), hinge * CFrame.new(0, 1.5, 0.22), colour,
		Enum.Material.Fabric, false)
	block(parent, "LoungerPillow", Vector3.new(1.8, 0.5, 0.9), hinge * CFrame.new(0, 2.7, 0.5), shade,
		Enum.Material.Fabric, false)
	rod(parent, "LoungerProp", (hinge * CFrame.new(0, 0.4, -0.1)).Position, (at * CFrame.new(0, 1.3, 0.9)).Position,
		0.18, rail)
	-- The towel somebody folded over the foot of it.
	block(parent, "LoungerTowel", Vector3.new(2.2, 0.2, 1.3), at * CFrame.new(0, 1.8, -2.1), shade,
		Enum.Material.Fabric, false)
end

-- ===== A PARASOL =====
--
-- A pole in a weighted base, eight ribs, eight panels in two tones with a scallop hung off each
-- outer edge, a vent at the crown and a finial over it. At `x`, `z` on the deck, in the terrace's
-- frame. The canopy is nine studs up, which clears anyone walking under it.
local PARASOL_R = 5
local function parasol(parent: Instance, frame: CFrame, x: number, z: number, colour: Color3)
	local foot = (frame * CFrame.new(x, 0, z)).Position
	local second = colour:Lerp(Color3.new(1, 1, 1), 0.55)
	column(parent, "ParasolBase", 2.6, foot, foot.Y, foot.Y + 0.5, BAND, Enum.Material.Slate, true)
	column(parent, "ParasolPole", 0.45, foot, foot.Y, foot.Y + 9.3, COPING, Enum.Material.Metal, true)
	local hub = foot + Vector3.new(0, 8.3, 0)
	for index = 0, 7 do
		local rib = index * math.pi / 4
		local out = Vector3.new(math.cos(rib), 0, math.sin(rib))
		rod(parent, "ParasolRib", hub, hub + out * PARASOL_R - Vector3.new(0, 1, 0), 0.2, COPING)
		local mid = rib + math.pi / 8
		local dir = Vector3.new(math.cos(mid), -0.2, math.sin(mid)).Unit
		local centre = hub + dir * (PARASOL_R / 2)
		local panel = block(parent, "ParasolPanel", Vector3.new(2.5, 0.16, PARASOL_R + 0.4),
			CFrame.lookAt(centre, centre + dir), if index % 2 == 0 then colour else second, Enum.Material.Fabric, false)
		panel.CastShadow = false
		-- The scallop on the panel's outer edge, which is what a parasol's hem actually looks like.
		block(parent, "ParasolScallop", Vector3.new(2.5, 0.5, 0.3), panel.CFrame * CFrame.new(0, -0.2, -PARASOL_R / 2 - 0.1),
			if index % 2 == 0 then colour else second, Enum.Material.Fabric, false)
	end
	column(parent, "ParasolVent", 2, foot, hub.Y + 0.5, hub.Y + 0.7, second, Enum.Material.Fabric, false)
	ellipsoid(parent, "ParasolFinial", Vector3.new(0.7, 0.9, 0.7), CFrame.new(foot + Vector3.new(0, 9.5, 0)), COPING)
end

-- ===== A PERGOLA =====
--
-- Posts, beams across them and slats over the beams: shade that is drawn on the deck in stripes
-- rather than thrown by a solid roof. Every post stands on the deck and carries the beams over it,
-- which is the whole structure. `x`, `z` is its middle in the terrace's frame.
local function pergola(parent: Instance, frame: CFrame, x: number, z: number, wide: number, long: number, colour: Color3)
	local wood = Color3.fromRGB(226, 214, 192)
	local high = 9
	for _, dx in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -1, 1 }) do
			block(parent, "PergolaPost", Vector3.new(0.7, high, 0.7),
				frame * CFrame.new(x + dx * wide / 2, high / 2, z + dz * long / 2), wood, Enum.Material.WoodPlanks, true)
		end
		-- The beam along this side, carried by the two posts under it.
		block(parent, "PergolaBeam", Vector3.new(0.5, 0.8, long + 1.4),
			frame * CFrame.new(x + dx * wide / 2, high + 0.4, z), wood, Enum.Material.WoodPlanks, false)
	end
	local slats = math.max(4, math.floor(long / 1.6))
	for index = 0, slats do
		block(parent, "PergolaSlat", Vector3.new(wide + 1.6, 0.3, 0.4),
			frame * CFrame.new(x, high + 1, z - long / 2 + index * (long / slats)), wood, Enum.Material.WoodPlanks, false)
	end
	-- A climber up one post and along the beam, because a pergola without one is a frame.
	for index = 0, 6 do
		ellipsoid(parent, "PergolaLeaves", Vector3.new(1.6, 1.2, 1.6),
			frame * CFrame.new(x - wide / 2, 2 + index * 1.2, z - long / 2 + index * 0.3),
			Color3.fromRGB(150, 190, 150):Lerp(colour, 0.15))
	end
end

-- ===== A PLANTER =====
--
-- A stone box of soil with a small tree in it, stood on the deck edge. Heavy, low, and the one
-- green thing up here.
local function planter(parent: Instance, frame: CFrame, x: number, z: number)
	local stone = Color3.fromRGB(226, 226, 220)
	block(parent, "Planter", Vector3.new(3.4, 2, 3.4), frame * CFrame.new(x, 1, z), stone, Enum.Material.Concrete, true)
	block(parent, "PlanterSoil", Vector3.new(2.8, 0.3, 2.8), frame * CFrame.new(x, 2.05, z), Color3.fromRGB(96, 80, 66),
		Enum.Material.Ground, false)
	local foot = (frame * CFrame.new(x, 2, z)).Position
	column(parent, "PlanterTrunk", 0.5, foot, foot.Y, foot.Y + 3.4, Color3.fromRGB(150, 124, 96), Enum.Material.Wood, false)
	for _, leaf in ipairs({ { 0, 4.4, 0, 4.2, 2.4 }, { 0.9, 3.7, 0.6, 3, 1.8 }, { -0.8, 3.9, -0.7, 2.6, 1.6 } }) do
		ellipsoid(parent, "PlanterLeaves", Vector3.new(leaf[4], leaf[5], leaf[4]),
			frame * CFrame.new(x + leaf[1], leaf[2], z + leaf[3]), Color3.fromRGB(148, 192, 154))
	end
end

-- ===== A POOL TERRACE =====
--
-- Built in `frame`: its origin is the terrace's inner edge at deck height, +X runs outward away from
-- the route, +Z along it.
--
-- THE OUTLINE IS NOT A SQUARE. A narrow walk off the checkpoint, shoulders where it flares, a wide
-- middle holding the pool with a sun deck either side, and a rounded prow past the pool that the
-- water spills off. The deck slabs ARE the pool's walls, so the pool is the gap between them.
--
-- WHAT HOLDS IT UP: columns to the sea under the pool's four corners, under both sun decks and
-- under the prow. The walk in needs none, because it is a short span between the neck, which is
-- part of the chunk, and the pool block, which is on columns. Nothing stands under the pump room.
--
-- The sun side is +Z and the shade side -Z, and everything that stands on the deck has its own
-- place on one of them; blender/check_skypools.py holds that no two of them meet.
local function terrace(parent: Instance, frame: CFrame, x0: number, wide: number, long: number,
	groundY: number, dressing: { string })
	local x1 = x0 + wide
	local lz = long / 2
	local entryHalf = math.max(6, long * ENTRY_SHARE)
	local poolW = math.min(POOL_W, wide * 0.5)
	local px0 = x0 + wide * POOL_FROM
	local px1 = px0 + poolW
	local pz = math.min(POOL_L, long * 0.42) / 2
	local poolX = (px0 + px1) / 2
	local noseR = math.min(lz - 4, wide * 0.22, x1 - px1 - 0.8)
	local shoulder = math.min(6, (px0 - x0) * 0.6)
	local function has(what: string): boolean
		return table.find(dressing, what) ~= nil
	end

	local function strip(ax: number, bx: number, az: number, bz: number)
		block(parent, "Deck", Vector3.new(bx - ax, DECK_THICK, bz - az),
			frame * CFrame.new((ax + bx) / 2, -DECK_THICK / 2, (az + bz) / 2), DECK, Enum.Material.SmoothPlastic, true)
	end
	-- THE WALK IN, with the pump room's hatch cut out of it where this terrace has one.
	if has("pumproom") then
		local hx0, hx1 = x0 + HATCH_FROM, x0 + HATCH_FROM + HATCH
		strip(x0, hx0, -entryHalf, entryHalf)
		strip(hx1, px0, -entryHalf, entryHalf)
		strip(hx0, hx1, -entryHalf, HATCH_Z)
		strip(hx0, hx1, HATCH_Z + HATCH, entryHalf)
	else
		strip(x0, px0, -entryHalf, entryHalf)
	end
	-- THE SHOULDERS, where the walk flares out to the width of the pool deck.
	strip(px0 - shoulder, px0, -(lz - 3), -entryHalf)
	strip(px0 - shoulder, px0, entryHalf, lz - 3)
	-- THE SUN DECKS either side of the pool, the widest part of the terrace.
	strip(px0, px1, -lz, -pz)
	strip(px0, px1, pz, lz)
	-- THE BAND past the pool, and THE PROW: a disc on the end of it, which is the edge the water
	-- goes over and the only round thing in the outline.
	strip(px1, x1, -(lz - 5), lz - 5)
	local prow = (frame * CFrame.new(x1, 0, 0)).Position
	column(parent, "Prow", noseR * 2, prow, prow.Y - DECK_THICK, prow.Y, DECK, Enum.Material.SmoothPlastic, true)

	-- ===== THE POOL =====
	--
	-- A floor at POOL_DEPTH, steps at the inner end to walk in down and back out, and terrain water
	-- filled between them. The water is filled a little way into the walls so its edge is hidden
	-- behind the tiling instead of stepping along the voxel grid in the open.
	local function tiled(part: Part): Part
		if tileMaterial then
			part.MaterialVariant = TILE_VARIANT
		end
		return part
	end
	tiled(block(parent, "PoolFloor", Vector3.new(poolW, 1, pz * 2), frame * CFrame.new(poolX, -POOL_DEPTH - 0.5, 0),
		TILE, tileMaterial or Enum.Material.SmoothPlastic, true))
	for index = 1, BEACH_STEPS do
		local deep = POOL_DEPTH * index / (BEACH_STEPS + 1)
		local ax = px0 + (index - 1) * STEP_RUN
		tiled(block(parent, "PoolStep", Vector3.new(STEP_RUN, POOL_DEPTH - deep + 1, pz * 2),
			frame * CFrame.new(ax + STEP_RUN / 2, -deep - (POOL_DEPTH - deep + 1) / 2, 0), TILE,
			tileMaterial or Enum.Material.SmoothPlastic, true))
	end
	local stepsEnd = px0 + BEACH_STEPS * STEP_RUN
	local deepWater = POOL_DEPTH - WATER_DROP
	fillWater(frame * CFrame.new(poolX, -WATER_DROP - deepWater / 2, 0), Vector3.new(poolW + 2, deepWater, pz * 2 + 2))
	-- The part left where the water is, invisible: the client reads it to know where the surface is,
	-- and so do the toys floating on it (SkyPoolsClient).
	local surface = block(parent, "PoolWater", Vector3.new(poolW, 0.2, pz * 2), frame * CFrame.new(poolX, -WATER_DROP, 0),
		WATER, Enum.Material.SmoothPlastic, false)
	surface.Transparency = 1
	surface.CanQuery = false
	surface.CastShadow = false
	surface:SetAttribute("Deep", POOL_DEPTH)
	CollectionService:AddTag(surface, "SkyPoolWater")

	-- THE WATERLINE, a band of darker tile set into the walls where the water meets them, and the
	-- two lights in the long walls under it, which are what makes a pool glow at dusk.
	local bandY = -WATER_DROP - 0.55
	for _, band in ipairs({ { (stepsEnd + px1) / 2, -pz + 0.1, px1 - stepsEnd, 0.2 },
		{ (stepsEnd + px1) / 2, pz - 0.1, px1 - stepsEnd, 0.2 }, { px1 - 0.1, 0, 0.2, pz * 2 } }) do
		block(parent, "Waterline", Vector3.new(band[3], 1.1, band[4]), frame * CFrame.new(band[1], bandY, band[2]),
			MOSAIC, Enum.Material.SmoothPlastic, false)
	end
	for _, side in ipairs({ -1, 1 }) do
		local fitting = block(parent, "PoolLight", Vector3.new(2.4, 1, 0.3),
			frame * CFrame.new(poolX + side * poolW * 0.2, -POOL_DEPTH * 0.45, side * (pz - 0.15)),
			Color3.fromRGB(232, 250, 254), Enum.Material.Glass, false)
		local glow = Instance.new("SurfaceLight")
		glow.Face = if side > 0 then Enum.NormalId.Front else Enum.NormalId.Back
		glow.Brightness = 1.4
		glow.Range = 20
		glow.Angle = 140
		glow.Color = Color3.fromRGB(196, 240, 250)
		glow.Shadows = false
		glow.Parent = fitting
	end

	-- THE COPING: a flat kerb round the opening with a rolled bullnose on its inner edge, which is
	-- the edge you actually hold on to from the water.
	for _, edge in ipairs({ { poolX, -pz - 1.1, poolW + 4.4, 2.2 }, { poolX, pz + 1.1, poolW + 4.4, 2.2 },
		{ px0 - 1.1, 0, 2.2, pz * 2 }, { px1 + 1.1, 0, 2.2, pz * 2 } }) do
		block(parent, "Coping", Vector3.new(edge[3], 0.2, edge[4]), frame * CFrame.new(edge[1], 0.1, edge[2]), COPING,
			Enum.Material.SmoothPlastic, true)
	end
	for _, edge in ipairs({ { Vector3.new(px0, 0.18, -pz), Vector3.new(px1, 0.18, -pz) },
		{ Vector3.new(px0, 0.18, pz), Vector3.new(px1, 0.18, pz) },
		{ Vector3.new(px0, 0.18, -pz), Vector3.new(px0, 0.18, pz) },
		{ Vector3.new(px1, 0.18, -pz), Vector3.new(px1, 0.18, pz) } }) do
		rod(parent, "Bullnose", frame * edge[1], frame * edge[2], 0.5, COPING)
	end
	-- THE INLAY, a line of the same tile set into the deck a stride back from the coping, which is
	-- what stops the deck reading as one flat slab.
	for _, side in ipairs({ -1, 1 }) do
		block(parent, "Inlay", Vector3.new(poolW + 9, 0.08, 0.5), frame * CFrame.new(poolX, 0.02, side * (pz + 4.2)),
			MOSAIC, Enum.Material.SmoothPlastic, false)
	end

	-- THE OVERFLOW: a channel from the pool's outer wall, across the band, over the prow's lip.
	local channel = math.min(10, pz * 1.4)
	local lipX = x1 + noseR - 0.5
	water(parent, "Spill", Vector3.new(lipX - px1, 0.25, channel), frame * CFrame.new((px1 + lipX) / 2, 0.06, 0))
	for _, side in ipairs({ -1, 1 }) do
		block(parent, "SpillKerb", Vector3.new(lipX - px1, 0.55, 0.6),
			frame * CFrame.new((px1 + lipX) / 2, 0.27, side * (channel / 2 + 0.3)), COPING, Enum.Material.SmoothPlastic, true)
	end
	waterfall(parent, frame * Vector3.new(lipX + 0.6, -0.25, 0), frame.RightVector, channel, groundY, 90)

	-- ===== COLUMNS to the sea =====
	--
	-- Every one of them stands wholly under deck, so none comes up beside anything: the inner pair
	-- pass either side of the pump room, the outer pair keep inside the band, and the four under the
	-- sun decks keep inside the strips. The prow stands on the ninth.
	local innerZ = math.min(8, lz - 6)
	local outerZ = math.min(8, lz - 8.2)
	for _, at in ipairs({ { px0 - 2.5, -innerZ }, { px0 - 2.5, innerZ }, { px1 + 2.5, -outerZ }, { px1 + 2.5, outerZ },
		{ px0 + 3.5, -(lz - 3) }, { px0 + 3.5, lz - 3 }, { px1 - 3.5, -(lz - 3) }, { px1 - 3.5, lz - 3 },
		{ x1, 0 } }) do
		local under = frame * Vector3.new(at[1], -DECK_THICK, at[2])
		column(parent, "Column", COLUMN_D, under, groundY, under.Y, STONE, Enum.Material.SmoothPlastic, true)
		column(parent, "Collar", COLUMN_D + 2, under, under.Y - 2.4, under.Y, BAND, Enum.Material.SmoothPlastic, false)
	end

	-- ===== WHAT STANDS ON THE DECK =====
	local colour = PASTELS[rng:NextInteger(1, #PASTELS)]
	-- The two rows things stand in, kept far enough off the coping to walk between and far enough
	-- inside the edge that nothing hangs over it on the smaller terraces out in the sky.
	local sunZ = math.min(pz + 4.6, lz - 4.3)
	local shadeZ = -math.min(pz + 5, lz - 3)
	local spread = math.max(3.4, poolW * 0.2)
	for _, what in ipairs(dressing) do
		if what == "loungers" then
			-- Either side of where the parasol goes, feet to the water.
			for _, dx in ipairs({ -spread, spread }) do
				lounger(parent, frame * CFrame.new(poolX + dx, 0, sunZ), colour)
			end
		elseif what == "parasol" then
			parasol(parent, frame, poolX, sunZ, colour)
		elseif what == "towel" then
			-- A TOWEL SOMEBODY LEFT on the deck, out past the loungers.
			local at = frame * CFrame.new(math.min(poolX + poolW * 0.38, px1 - 2.2), 0.12, sunZ - 1)
				* CFrame.Angles(0, math.rad(rng:NextNumber(-12, 12)), 0)
			block(parent, "Towel", Vector3.new(3.2, 0.12, 5.4), at, colour, Enum.Material.Fabric, false)
			block(parent, "TowelStripe", Vector3.new(3.22, 0.13, 0.8), at * CFrame.new(0, 0, 1.4), COPING,
				Enum.Material.Fabric, false)
		elseif what == "ladder" then
			-- In the deep end's sun-side wall, where the water is over your head. The shade side is
			-- where the diving board comes out over the pool, and its rails would meet the board.
			local z = pz - 0.7
			for _, side in ipairs({ -1, 1 }) do
				local rail = frame * Vector3.new(poolX + 4 + side * 1.2, 0, z)
				rod(parent, "LadderRail", rail + Vector3.new(0, -POOL_DEPTH + 1, 0), rail + Vector3.new(0, 2.8, 0), 0.35, RAIL)
			end
			for index = 1, 5 do
				local rung = frame * Vector3.new(poolX + 4, -POOL_DEPTH + 1 + index * 1.6, z)
				rod(parent, "LadderRung", rung - frame.RightVector * 1.2, rung + frame.RightVector * 1.2, 0.25, RAIL)
			end
		elseif what == "board" then
			-- A DIVING BOARD out over the deep end from the shade side. You can walk out on it and
			-- jump off it, which is all it is for.
			local foot = frame * CFrame.new(poolX + 4.5, 0, shadeZ - 1)
			block(parent, "BoardStand", Vector3.new(3, 1.4, 3), foot * CFrame.new(0, 0.7, 0), BAND,
				Enum.Material.SmoothPlastic, true)
			block(parent, "DivingBoard", Vector3.new(3, 0.5, 11), foot * CFrame.new(0, 1.65, 5), COPING,
				Enum.Material.SmoothPlastic, true)
			for _, side in ipairs({ -1, 1 }) do
				rod(parent, "BoardRail", (foot * CFrame.new(side * 1.6, 1.9, 1)).Position,
					(foot * CFrame.new(side * 1.6, 3.4, 4.6)).Position, 0.2, RAIL)
			end
		elseif what == "planters" then
			for _, side in ipairs({ -1, 1 }) do
				planter(parent, frame, px0 - shoulder - 2.4, side * (entryHalf - 2.2))
			end
		elseif what == "pergola" then
			pergola(parent, frame, poolX, shadeZ - 1.5, 11, 6, colour)
		elseif what == "duck" or what == "swimring" then
			poolToy(parent, frame * CFrame.new((stepsEnd + px1) / 2, -WATER_DROP, 0), (px1 - stepsEnd) / 2 - 3,
				pz - 3, what)
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

-- A terrace BESIDE a checkpoint chunk, flush with its top.
--
-- `outward` is which way it faces: away from the middle on a level laid as a ring, and alternating
-- sides of the route on one laid as a path or a meander, so two terraces never crowd each other and
-- no terrace's columns come up beside its neighbour's deck.
--
-- The neck meets the chunk's cap edge and is only as long as the chunk. The terrace proper starts
-- NECK studs further out, 16.4 from the route's centre line, because the widest chunk this level
-- can put next door reaches 13.4 (the straight chunk's own shelves) -- so the terrace, which is
-- longer than the chunk, overhangs its neighbours' ends with three studs to spare.
-- blender/check_skypools.py holds that true for the whole chunk pool.
local function terraceBeside(parent: Instance, chunk: Instance, outward: Vector3, groundY: number,
	dressing: { string }): boolean
	local cap = capOf(chunk)
	if not cap then
		return false
	end
	local flat = Vector3.new(outward.X, 0, outward.Z)
	if flat.Magnitude < 0.01 then
		return false
	end
	local out = flat.Unit
	local capCF = cap.CFrame
	local halfOut = math.abs(capCF.RightVector:Dot(out)) * cap.Size.X / 2
		+ math.abs(capCF.LookVector:Dot(out)) * cap.Size.Z / 2
	local along = Vector3.yAxis:Cross(out)
	local halfAlong = math.abs(capCF.RightVector:Dot(along)) * cap.Size.X / 2
		+ math.abs(capCF.LookVector:Dot(along)) * cap.Size.Z / 2
	local top = cap.Position.Y + cap.Size.Y / 2
	local edge = Vector3.new(cap.Position.X, top, cap.Position.Z) + out * halfOut
	local frame = CFrame.fromMatrix(edge, out, Vector3.yAxis)

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
				CLOUD_TOP:Lerp(CLOUD_UNDER, rng:NextNumber(0, 0.55)))
			puff.Transparency = rng:NextNumber(0.03, 0.12)
			-- No sky in them. A cloud with reflectance is a mirror the size of the horizon, and it
			-- was adding the last of the white that hid the chunks.
			puff.Reflectance = 0
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
	-- THE WATER, terrain again, filled between the floor and WATER_DROP under the rim. What is left
	-- is the invisible marker the client reads for the splash and the ripples, as on a terrace.
	fillWaterCylinder(CFrame.new(centre + Vector3.new(0, surfaceY - WATER_DROP - (FINAL_DEEP - WATER_DROP) / 2, 0)),
		FINAL_DEEP - WATER_DROP, FINAL_RADIUS - 1)
	local surface = column(parent, "FinalPoolWater", FINAL_RADIUS * 2 - 2, centre, surfaceY - WATER_DROP - 0.1,
		surfaceY - WATER_DROP + 0.1, WATER, Enum.Material.SmoothPlastic, false)
	if surface then
		surface.Transparency = 1
		surface.CanQuery = false
		surface.CastShadow = false
		surface:SetAttribute("Deep", FINAL_DEEP)
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
		poolToy(parent, CFrame.new(centre + Vector3.new(math.cos(a) * 50, surfaceY - WATER_DROP, math.sin(a) * 50)), 10, 10,
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
--
-- Where it goes is SkyPath's (ReplicatedStorage/Shared/SkyPath.lua). What is here is the trough
-- built along it: a floor with a film of water running down it, walls with a rolled lip you can see
-- over from inside, hoops over the top every so often with pennants on them, and the rods that hang
-- the whole thing off the tower. None of it collides, so a player who falls onto the slide drops
-- through into the clouds and is caught like any other fall.
local function buildSlide(parent: Instance, spec: any, towerTopY: number): number
	if not SkyPath then
		return 0
	end
	local folder = Instance.new("Folder")
	folder.Name = "Slide"
	folder.Parent = parent
	local distances = SkyPath.distances(spec)
	local long = SkyPath.length(distances)
	local count = math.max(8, math.ceil(long / SkyPath.STEP))
	local rodEvery = math.max(1, math.floor(count / 18))
	local hoopEvery = math.max(2, math.floor(count / 12))
	local wide = SkyPath.WIDE
	for index = 0, count - 1 do
		local a, b = SkyPath.point(spec, index / count), SkyPath.point(spec, (index + 1) / count)
		local run = (b - a).Magnitude * 1.08 + 0.6
		local frame = CFrame.lookAt((a + b) / 2, b, SkyPath.up(spec, (index + 0.5) / count))
		local floor = block(folder, "SlideFloor", Vector3.new(wide, 0.8, run), frame * CFrame.new(0, -0.4, 0), SLIDE,
			Enum.Material.SmoothPlastic, false)
		floor.Reflectance = 0.15
		-- The film of water running down it, which is what makes it a water slide.
		local film = block(folder, "SlideFilm", Vector3.new(wide - 0.8, 0.12, run), frame * CFrame.new(0, 0.06, 0), FALL,
			Enum.Material.Glass, false)
		film.Transparency = 0.55
		film.Reflectance = 0.2
		film.CastShadow = false
		for _, side in ipairs({ -1, 1 }) do
			block(folder, "SlideWall", Vector3.new(0.8, 2.6, run), frame * CFrame.new(side * (wide / 2 + 0.4), 0.9, 0),
				RAIL, Enum.Material.SmoothPlastic, false)
			-- The rolled lip along the top of the wall, which is the edge you watch go past.
			local lip = block(folder, "SlideLip", Vector3.new(1, 1, run), frame * CFrame.new(side * (wide / 2 + 0.4), 2.2, 0),
				SLIDE, Enum.Material.SmoothPlastic, false)
			lip.Shape = Enum.PartType.Cylinder
			lip.CFrame = frame * CFrame.new(side * (wide / 2 + 0.4), 2.2, 0) * CFrame.Angles(0, math.pi / 2, 0)
		end
		-- A HOOP over the trough, with a pennant hung off the top of it.
		if index % hoopEvery == 0 and index > 1 then
			for step = 0, 8 do
				local a2 = math.pi * (step / 8)
				block(folder, "SlideHoop", Vector3.new(0.55, 0.55, 0.55),
					frame * CFrame.new(math.cos(a2) * (wide / 2 + 0.9), math.sin(a2) * (wide / 2 + 0.6) + 1.4, 0),
					if (index // hoopEvery) % 2 == 0 then COPING else SLIDE, Enum.Material.SmoothPlastic, false)
			end
			local flag = block(folder, "SlidePennant", Vector3.new(0.12, 1.4, 1.8),
				frame * CFrame.new(0, wide / 2 + 3.4, 0), PASTELS[(index % #PASTELS) + 1], Enum.Material.Fabric, false)
			flag.CastShadow = false
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
	return long
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
	-- The terrace, sharing the walkway's outer edge; its own inner columns carry that side. It stops
	-- eight studs short of the mouth, because the last thing wanted at the top of a slide is
	-- somebody's parasol beside it.
	local terraceL = WALK_L - 8
	terrace(parent, finish * CFrame.new(halfW, 0, terraceL / 2), 0, 34, terraceL, groundY,
		{ "loungers", "parasol", "swimring" })

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

	-- AN ARCH OVER THE MOUTH, so the one way down reads as a way. It stands a stud BEHIND the mouth
	-- and wider than the trough, so you pass under it and nothing of it is over the slide itself.
	local mouth = finish * CFrame.new(0, 0, WALK_L)
	for _, side in ipairs({ -1, 1 }) do
		local foot = (mouth * CFrame.new(side * (SLIDE_WIDE / 2 + 2.6), 0, -1.4)).Position
		column(parent, "ArchPost", 1.8, foot, foot.Y, foot.Y + 12, COPING, Enum.Material.SmoothPlastic, true)
		-- The rinse over the queue: a head on the post, running, as showers at a pool do.
		local head = (mouth * CFrame.new(side * (SLIDE_WIDE / 2 + 2.6), 0, -4.4)).Position
		column(parent, "RinsePost", 0.4, head, head.Y, head.Y + 7, RAIL, Enum.Material.Metal, false)
		column(parent, "RinseHead", 1.2, head, head.Y + 6.6, head.Y + 7, RAIL, Enum.Material.Metal, false)
		waterfall(parent, head + Vector3.new(0, 6.5, 0), Vector3.new(0, 0, 1), 1, head.Y + 0.1)
	end
	local beam = block(parent, "ArchBeam", Vector3.new(SLIDE_WIDE + 9, 2, 2.2), mouth * CFrame.new(0, 12.8, -1.4), SLIDE,
		Enum.Material.SmoothPlastic, false)
	label(beam, Enum.NormalId.Front, "THE LONG WAY DOWN", Color3.fromRGB(255, 255, 255))
	-- The lane painted on the deck up to the mouth, so where to stand is obvious from the walkway.
	for index = 0, 5 do
		block(parent, "MouthLane", Vector3.new(SLIDE_WIDE - 2, 0.06, 1.2), mouth * CFrame.new(0, 0.03, -3 - index * 2.4),
			SLIDE, Enum.Material.SmoothPlastic, false)
	end
	return mouth
end

-- ===== THE SCENERY POOLS =====
--
-- Terraces out in the sky on their own columns, to be seen and not reached. `avoid` is the route
-- itself: on a level laid as a ring they were always well outside it, but a route that goes
-- somewhere wanders, so each pool is tried at a few angles until it finds one that keeps its
-- distance from every chunk. A pool standing in the middle of the level you are running is worse
-- than one fewer pool.
local SCENERY_CLEAR = 300
local function sceneryPools(parent: Instance, centre: Vector3, radius: number, lowY: number, highY: number,
	groundY: number, avoid: { Vector3 })
	for index = 1, 6 do
		for try = 0, 13 do
			local angle = (index / 6) * math.pi * 2 + rng:NextNumber(-0.25, 0.25) + try * 0.21
			local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local reach = radius + rng:NextNumber(320, 780)
			local at = centre + out * reach + Vector3.new(0, rng:NextNumber(lowY, highY), 0)
			local clear = true
			for _, keep in ipairs(avoid) do
				if (Vector3.new(keep.X - at.X, 0, keep.Z - at.Z)).Magnitude < SCENERY_CLEAR then
					clear = false
					break
				end
			end
			if clear then
				local frame = CFrame.fromMatrix(at, out, Vector3.yAxis)
				terrace(parent, frame, 0, rng:NextNumber(34, 46), rng:NextNumber(28, 38), groundY,
					if index % 2 == 0 then { "loungers", "parasol" } else { "parasol" })
				break
			end
		end
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
	-- TERRAIN IS NOT PART OF THE MODEL and does not go when the model does, so anything a previous
	-- run left is taken out before this one fills its own pools.
	SkyPoolsService.clearWater()
	poolWaterLook()

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
	-- WHAT IS ON EACH TERRACE. The sun side of a deck holds either the loungers and what goes with
	-- them or the cabana, never both; the shade side holds one of the pergola, the board and the
	-- lifeguard's chair. So no list below has two things that would stand in the same place, which
	-- blender/check_skypools.py holds to.
	local dressings = {
		{ "loungers", "parasol", "ladder", "swimring", "pergola" },
		{ "loungers", "towel", "ladder", "pumproom", "duck", "planters" },
		{ "cabana", "board", "duck", "planters" },
		{ "loungers", "parasol", "towel", "swimring", "lifeguard" },
		{ "loungers", "parasol", "ladder", "duck", "pergola", "planters" },
	}
	-- WHICH WAY A TERRACE FACES. On a level laid as a ring, away from the middle. On one laid as a
	-- path or a meander, alternating sides of the route: two terraces on the same side of a bend
	-- would crowd each other, and it is a neighbour's columns coming up past your deck that made the
	-- ring version look wrong.
	local ringLaid = (level.layout or "ring") == "ring" and level.radius ~= nil
	local terraces = 0
	for index, entry in ipairs(chosen) do
		local cap = capOf(entry.model)
		if cap then
			local outward: Vector3
			if ringLaid then
				outward = Vector3.new(cap.Position.X - centre.X, 0, cap.Position.Z - centre.Z)
			else
				outward = cap.CFrame.RightVector * (if index % 2 == 0 then -1 else 1)
			end
			if terraceBeside(model, entry.model, outward, h.seaY, dressings[(index - 1) % #dressings + 1]) then
				terraces += 1
			end
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
	-- WHERE THE TOWER STANDS. In the middle of a ring, which is what a ring goes round. On a route
	-- that goes somewhere, beside the mouth instead (see TOWER_ASIDE) -- on the opposite side from
	-- the terrace off the walkway, so the ride sets off forward and sweeps away from it.
	local forward = (mouth * CFrame.new(0, 0, 1)).Position - start
	forward = Vector3.new(forward.X, 0, forward.Z)
	forward = if forward.Magnitude > 0.01 then forward.Unit else Vector3.new(0, 0, 1)
	local aside = Vector3.new(finish.RightVector.X, 0, finish.RightVector.Z).Unit
	local towerCentre = if ringLaid then centre else Vector3.new(start.X, 0, start.Z) - aside * TOWER_ASIDE
	local flat = Vector3.new(start.X - towerCentre.X, 0, start.Z - towerCentre.Z)
	local spec = {
		centre = towerCentre,
		angle0 = math.atan2(flat.Z, flat.X),
		radius0 = flat.Magnitude,
		radius1 = SLIDE_END_RADIUS,
		y0 = start.Y,
		y1 = h.poolY + 0.4,
		turns = SLIDE_TURNS,
	}
	-- WHICH WAY IT SWEEPS: the way that sets off along the walkway rather than back across it. With
	-- the tower beside the mouth both ways run forward-ish, and this is the one that does. The first
	-- MOUTH_CLEAR studs either side of it are checked in blender/check_skypools.py.
	if SkyPath then
		local early = SkyPath.point(spec, 0.03) - start
		if early:Dot(forward) < 0 then
			spec.turns = -SLIDE_TURNS
		end
	end
	local slideLong = buildSlide(model, spec, h.topY)

	-- ===== The tower, the pool it stands in, the clouds, the sky round it =====
	finalPool(model, towerCentre, h.poolY, h.seaY)
	tower(model, towerCentre, h.seaY, h.poolY, h.topY)
	cloudSea(model, towerCentre, h.cloudTop)
	local radius: number = level.radius or flat.Magnitude
	-- The route, for the scenery to keep away from: every third chunk is close enough spacing, since
	-- nothing out there comes within three chunks of anything.
	local away: { Vector3 } = { start }
	for index = 1, #chunks, 3 do
		table.insert(away, chunks[index].model:GetPivot().Position)
	end
	sceneryPools(model, towerCentre, radius, h.cloudTop + 50, startY + 40, h.seaY, away)
	balloons(model, towerCentre, math.max(radius, 420), startY)

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
-- === Why a sled, and who moves it ===
--
-- The ride used to be the server writing the rider's root CFrame every frame. That is a whole
-- character assembly replicated sixty times a second, and it rode badly: it stuttered, because the
-- client was being corrected to where the server had just put it, and you stood bolt upright all
-- the way down, because nothing ever sat you in anything.
--
-- So you sit in a SLED now. It is a seat, so the character sits in it the way it sits in anything,
-- and it is one small part instead of a character. The server starts it, keeps the clock and decides
-- where the ride ends; the rider's own client is handed the sled and draws every frame of it from
-- SkyPath and the start time, which is smooth and costs no replication at all. If that client never
-- answers -- the file is not pasted in, or it is still loading -- the server drives the sled itself
-- and the ride still happens, exactly as long and ending in the same place.

local riding: { [Player]: boolean } = {}
local driving: { [Player]: boolean? } = {} -- whose client has taken the sled over
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

-- ===== THE SLED =====
--
-- What you ride in: a round float with a seat in it, a back to lean on, grab handles, and spray off
-- the front. The seat is the one part that is moved; everything else is welded to it, so the whole
-- thing is one assembly a client can be handed.
local function buildSled(at: CFrame): (Model, Seat)
	local sled = Instance.new("Model")
	sled.Name = "SkySled"
	local seat = Instance.new("Seat")
	seat.Name = "SledSeat"
	seat.Size = Vector3.new(4, 1, 5)
	seat.CFrame = at
	seat.Anchored = true
	seat.CanCollide = false
	seat.Color = PASTELS[1]
	seat.Material = Enum.Material.SmoothPlastic
	seat.TopSurface = Enum.SurfaceType.Smooth
	seat.Parent = sled
	sled.PrimaryPart = seat

	local function piece(name: string, size: Vector3, offset: CFrame, colour: Color3, round: boolean): BasePart
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = at * offset
		part.Color = colour
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if round then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
		part.Parent = sled
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = seat
		weld.Part1 = part
		weld.Parent = part
		return part
	end
	-- The float: eight fat segments round the seat, the way a ring float is made.
	for index = 0, 7 do
		local angle = index * math.pi / 4
		piece("SledFloat", Vector3.new(2.2, 1.8, 2.2), CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, 2.9),
			if index % 2 == 0 then PASTELS[2] else COPING, true)
	end
	piece("SledBack", Vector3.new(3.6, 2.2, 0.5), CFrame.new(0, 1.3, 2.2) * CFrame.Angles(math.rad(-12), 0, 0), PASTELS[2], false)
	for _, side in ipairs({ -1, 1 }) do
		piece("SledHandle", Vector3.new(0.4, 0.4, 1.8), CFrame.new(side * 2, 0.9, 0.4), RAIL, false)
	end
	-- The spray off the front, which is the ride telling you how fast you are going.
	local nose = piece("SledNose", Vector3.new(2.4, 0.8, 1.2), CFrame.new(0, 0.2, -3), COPING, false)
	nose.Transparency = 1
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(236, 250, 255))
	spray.LightEmission = 0.5
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0.2) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.5, 1.1)
	spray.Speed = NumberRange.new(6, 14)
	spray.SpreadAngle = Vector2.new(35, 20)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.EmissionDirection = Enum.NormalId.Front
	spray.Rate = 40
	spray.Parent = nose
	return sled, seat
end

-- The event the rider's client answers on to say it is drawing the ride. Looked up when the level
-- is built rather than at startup, because Bootstrap makes the folder after it requires this.
local rideEvent: RemoteEvent? = nil
local sledOf: { [Player]: Seat } = {}
local function rideRemote(): RemoteEvent?
	if rideEvent then
		return rideEvent
	end
	local folder = ReplicatedStorage:FindFirstChild("RemoteEvents") or ReplicatedStorage:WaitForChild("RemoteEvents", 5)
	local event = folder and (folder:FindFirstChild("SkyRide") or folder:WaitForChild("SkyRide", 5))
	if event and event:IsA("RemoteEvent") then
		rideEvent = event
		event.OnServerEvent:Connect(function(player: Player)
			-- The one thing a client may say: "I have the sled on screen." It is taken only from
			-- someone who is actually on the slide, and it moves nobody: the server still owns the
			-- clock and still decides where the ride ends.
			local seat = sledOf[player]
			if not (riding[player] and seat and not driving[player]) then
				return
			end
			driving[player] = true
			seat.Anchored = false
			pcall(function()
				seat:SetNetworkOwner(player)
			end)
		end)
	end
	return rideEvent
end

function SkyPoolsService.attachSlide(model: Model, onArrive: ((Player) -> ())?): () -> ()
	local mouthValue = model:GetAttribute("SlideMouth")
	if typeof(mouthValue) ~= "CFrame" or not SkyPath then
		return function() end
	end
	local mouth: CFrame = mouthValue
	local spec = SkyPath.read(model)
	if not spec then
		return function() end
	end
	local distances = SkyPath.distances(spec)
	local seconds = SkyPath.seconds(distances)
	local remote = rideRemote()

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
		if not (root and root:IsA("BasePart") and humanoid and humanoid:IsA("Humanoid")) then
			return
		end
		riding[player] = true
		driving[player] = nil
		arrivedAt[player] = nil

		task.spawn(function()
			local startedAt = workspace:GetServerTimeNow()
			local sled, seat = buildSled(SkyPath.rideFrame(spec, distances, 0))
			sled:SetAttribute("Rider", player.UserId)
			sled:SetAttribute("RideStart", startedAt)
			sled:SetAttribute("RideSeconds", seconds)
			-- The slide's shape, on the sled itself, so the client needs to find nothing else.
			for _, name in ipairs({ "SlideCentre", "SlideAngle0", "SlideRadius0", "SlideRadius1", "SlideY0", "SlideY1",
				"SlideTurns" }) do
				sled:SetAttribute(name, model:GetAttribute(name))
			end
			sled.Parent = workspace
			sledOf[player] = seat
			CollectionService:AddTag(sled, "SkySled")
			seat:Sit(humanoid)
			-- No jumping out halfway down; put it back when the ride is over.
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			local rush = waterSound(seat, "SlideRush", 0.8, 0.45, 10, 60)
			if remote then
				remote:FireClient(player, sled)
			end

			-- THE SERVER KEEPS THE CLOCK either way, and moves the sled itself until the rider's
			-- client says it has it.
			while true do
				local u = (workspace:GetServerTimeNow() - startedAt) / seconds
				if u >= 1 or not seat.Parent or not root.Parent then
					break
				end
				if not driving[player] then
					seat.CFrame = SkyPath.rideFrame(spec, distances, u)
				end
				RunService.Heartbeat:Wait()
			end

			local landing = SkyPath.point(spec, 1)
			sledOf[player] = nil
			driving[player] = nil
			rush:Destroy()
			sled:Destroy()
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			humanoid.Sit = false
			if root.Parent then
				splash(landing)
				-- Standing in the pool where the slide ran out, facing on the way it was going. The
				-- server puts them there whatever the client did with the sled.
				local onward = landing - SkyPath.point(spec, 0.99)
				onward = Vector3.new(onward.X, 0, onward.Z)
				local facing = if onward.Magnitude > 0.01 then onward.Unit else Vector3.new(0, 0, -1)
				local stand = landing + Vector3.new(0, 3, 0)
				task.wait()
				root.CFrame = CFrame.lookAt(stand, stand + facing)
			end
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
	driving[player] = nil
	arrivedAt[player] = nil
end)

return SkyPoolsService
