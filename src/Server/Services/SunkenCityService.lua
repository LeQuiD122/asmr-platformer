--!strict
-- ServerScriptService/Services/SunkenCityService.lua
-- Level 3, The Sunken City: the drowned city round the route, the aquarium, and the drain.
--
-- === What the level is ===
--
-- LevelService lays the route as a flat ring just above the sea, rising and dipping a few studs on
-- a slow swell (see `ring` on LevelDefinitions.Level3). Under it and round it, this builds a city
-- that went under the water and stayed there:
--
--   THE CITY, in rings round a plaza: blocks of lots between ring streets and eight avenues. Next
--   to the route the flats are flooded and roofless, so you look down into rooms with the furniture
--   still in them, a few studs under the surface. Further out the apartment blocks and offices
--   break the surface, and a multi-storey car park stands with its top deck of cars just under it.
--   THE CLOCK TOWER in the plaza, stopped at twelve minutes past four, and the harbour cranes are
--   the landmarks you steer by.
--   THE BOULEVARD runs round under the route, clear of buildings, with road signs on gantries a
--   few studs down. It is where the thing swims.
--   THE THING. Something enormous circles the boulevard, the other way to you, and never chases
--   anyone. SunkenCityClient draws and moves it on each client from the numbers this file puts on
--   the model; when it passes under you the water darkens and the sound drops away.
--   THE AQUARIUM, off one checkpoint: a door in a round tower standing in the water, a spiral stair
--   down inside it, a glass tunnel through the water on pillars, and a gallery at the far end with
--   a window onto the deep and a sign asking you not to tap on the glass.
--   THE DRAIN. The route runs out onto a pier over the harbour. Past its end is a whirlpool, and
--   under the whirlpool a drain in the harbour floor. Step off the pier and it pulls you round and
--   down into the dark, and that is the end of the level.
--
-- === Rules this follows ===
--
--   NOTHING FLOATS. Every building, the car park, the gantries, the tunnel, the pier and the crane
--   stand on the sea floor; the buoys float on the water and are chained to the floor.
--   NOTHING IN THE WATER CATCHES A FALL. Every part of the city is non-collidable, so a player who
--   falls goes through into the water and is caught by the kill plane as on every level, never
--   stranded on a roof a few studs under the surface. Only what you are meant to walk on collides:
--   the aquarium, the pier.
--   NOTHING BREAKS THE SURFACE NEAR THE ROUTE. Anything whose top is above the water stands at
--   least EMERGE_CLEAR studs from the route's reach, so no building ever stands in the way of the
--   run or within a jump of it.
--   DEPTH IS PAINTED IN. A part under the water is coloured darker and bluer the deeper it is
--   (drowned), with a murk layer under the kill plane, because a sheet of glass does not dim what
--   is behind it the way real water does.
--   THE WATER GOES SOMEWHERE, and that is the ending: down the drain.
--   SCARES FOLLOW ROADMAP SECTION 6. The thing is telegraphed (the sound goes first) and never
--   touches anyone. The one thing that answers back, in the aquarium, only answers a Hardcore
--   player, and only once.

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))
-- Where the thing is and when it surfaces, shared with every client so both agree on who it reaches.
local SunkenPath = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("SunkenPath"))

local SunkenCityService = {}

-- ===== The water =====
local WATER_UNDER_ROUTE = 9 -- the surface, this far under the lowest chunk's origin
local FLOOR_DEPTH = 100 -- the sea floor, this far under the surface
local MURK_DEPTH = 35 -- a darker layer this far down: under the kill plane, over most of the city
local SEA_HALF = 3072 -- how far the water reaches from the middle, each way
local LONGEST = 2000 -- a part stops at 2048 studs; anything longer is built in pieces

-- ===== The city =====
local PLAZA_RADIUS = 60
local BOULEVARD_HALF = 45 -- the street under the route: no lot comes within this of the ring
local STREET = 20 -- between one band of lots and the next
local INNER_BAND = 80
local OUTER_BAND = 110
local OUTER_BANDS = 3
local AVENUES = 8
local AVENUE_WIDE = 26
local LOT_ARC_MIN, LOT_ARC_MAX = 40, 62
-- THE ROUTE'S REACH, the widest any chunk in this level's pool extends from its centre line (the
-- straight chunk's shelves). check_sunkencity.py holds it against the pool.
local ROUTE_REACH = 13.4
-- ANYTHING THAT BREAKS THE SURFACE stays this far beyond the route's reach, in plan.
local EMERGE_CLEAR = 40
local FAR_TOWERS = 10 -- lone towers out past the last band, for the skyline in the haze

-- ===== The thing (drawn and moved by SunkenCityClient; these numbers are its whole brief) =====
local MONSTER_INSET = 6 -- it swims this far inside the route's centre line
local MONSTER_SPEED = 12 -- studs a second, round the ring the other way to the route
local MONSTER_DEPTH = 29 -- its centre line, this far under the surface on average: fins clear of the road signs
local MONSTER_BOB = 5 -- and up and down by this much
local MONSTER_BOB_PERIOD = 47
local MONSTER_GIRTH = 8 -- its widest radius; the client draws nothing thicker
-- THE HARBOUR SWERVE. Round the harbour it swings out into the open water rather than pass over
-- the drain, and the harbour has no buildings for the width of the swerve.
local HARBOUR_SWERVE = 85
local HARBOUR_SWERVE_HALF = 0.1 * 2 * math.pi
local HARBOUR_SECTOR_HALF = 0.14 * 2 * math.pi

-- ===== The aquarium =====
local AQ_NECK = 9 -- the landing from the checkpoint's cap edge to the tower's inner wall
local AQ_NECK_WIDE = 7
local NECK_THICK = 7.4 -- deep enough to swallow the straight chunk's side shelves (Sky Pools' reason)
local ROT_R = 11 -- the round tower's outer radius
local ROT_WALL = 1.2
local ROT_ROOF = 12 -- the roof, this far above the door's floor
local ROT_SEGMENTS = 24
local DOOR_H = 9
local TUNNEL_BELOW = 22 -- the tunnel's floor, this far under the surface
local TUNNEL_L = 64
local TUNNEL_W = 7
local TUNNEL_H = 10
local TUNNEL_BAY = 16
local ROOM_L, ROOM_W, ROOM_H = 22, 24, 11
local STEP_ANGLE = math.rad(18)
local STEP_RISE_MAX = 1.05

-- ===== The last dry flat =====
local FLAT_SHARE = 0.7 -- off the checkpoint nearest this share of the way round
local FLAT_GANG = 6 -- the gangway, from the checkpoint's cap edge to the doorstep
local FLAT_D, FLAT_W, FLAT_H = 24, 26, 9 -- outward, along the route, and the top floor's height
local FLAT_REACH = 26 -- the lots keep this far from its middle
-- THE FACE IN THE MIRROR (ROADMAP section 6): rare, once a server or less, never in Chill.
local MIRROR_LINGER = 1.6 -- seconds a Hardcore player stands before the mirror before it may happen
local MIRROR_CHANCE = 0.5 -- the chance, once per player per run, while it has not happened on this server

-- ===== The drain =====
local PIER_L, PIER_W = 26, 14
local VORTEX_GAP = 20 -- from the pier's end to the whirlpool's middle
local VORTEX_R = 22
local FUNNEL_DEPTH = 16
local CAPTURE_R = 20
local DRAIN_R = 7
local SHAFT_DEPTH = 60 -- under the sea floor; the rider ends at the bottom, in the dark
local DRAIN_SECONDS = 6.5

-- ===== Colours =====
local DEEP = Color3.fromRGB(24, 50, 56)
local SURFACE = Color3.fromRGB(58, 116, 116)
local MURK = Color3.fromRGB(18, 42, 46)
local SILT = Color3.fromRGB(64, 78, 70)
local STONE = Color3.fromRGB(170, 168, 156)
local GLASS = Color3.fromRGB(40, 54, 62)
local BRASS = Color3.fromRGB(150, 128, 80)
local FOAM = Color3.fromRGB(214, 232, 226)
local SHAFT = Color3.fromRGB(8, 10, 12)
local FACADES = {
	Color3.fromRGB(176, 170, 158),
	Color3.fromRGB(158, 170, 172),
	Color3.fromRGB(190, 176, 160),
	Color3.fromRGB(150, 162, 150),
	Color3.fromRGB(172, 152, 146),
	Color3.fromRGB(200, 196, 184),
}
local FADED = {
	Color3.fromRGB(196, 120, 110),
	Color3.fromRGB(110, 140, 176),
	Color3.fromRGB(214, 206, 180),
	Color3.fromRGB(120, 160, 120),
	Color3.fromRGB(210, 180, 110),
}

-- The sounds. impact_water is the project's water sound everywhere else; action_jump_land is the
-- character's own landing thud, which ships with the engine for exactly that reason.
local WATER_SOUND = "rbxasset://sounds/impact_water.mp3"
local THUD_SOUND = "rbxasset://sounds/action_jump_land.mp3"

-- The surface height for this build. Set once by build() before anything is made; every drowned
-- colour reads it.
local waterLevel = 0

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

-- DEPTH, PAINTED ON: darker and bluer the further under the surface the part's middle is.
local function drowned(colour: Color3, y: number): Color3
	return colour:Lerp(DEEP, math.clamp((waterLevel - y) / 70, 0, 0.82))
end

-- A piece of the city: drowned by its own depth, and never solid (see NOTHING IN THE WATER CATCHES
-- A FALL in the header).
local function cityBlock(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3,
	material: Enum.Material?): Part
	return block(parent, name, size, cf, drowned(colour, cf.Position.Y), material or Enum.Material.SmoothPlastic, false)
end

-- An upright cylinder from `bottom` to `top` at `at`'s X and Z, in pieces when it is longer than a
-- part can be, each piece drowned by its own depth unless `natural` is set.
local function column(parent: Instance, name: string, diameter: number, at: Vector3, bottom: number, top: number,
	colour: Color3, solid: boolean, natural: boolean?): Part?
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
			CFrame.new(at.X, y, at.Z) * CFrame.Angles(0, 0, math.pi / 2),
			if natural then colour else drowned(colour, y), Enum.Material.SmoothPlastic, solid)
		part.Shape = Enum.PartType.Cylinder
		last = part
	end
	return last
end

-- A cylinder from one point to another.
local function rod(parent: Instance, name: string, from: Vector3, to: Vector3, diameter: number, colour: Color3)
	local length = (to - from).Magnitude
	if length < 0.05 then
		return
	end
	local mid = (from + to) / 2
	local part = block(parent, name, Vector3.new(length, diameter, diameter),
		CFrame.lookAt(mid, to) * CFrame.Angles(0, math.pi / 2, 0), drowned(colour, mid.Y), Enum.Material.Metal, false)
	part.Shape = Enum.PartType.Cylinder
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

local function sound(parent: Instance, name: string, id: string, speed: number, volume: number, reach: number,
	looped: boolean): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	s.PlaybackSpeed = speed
	s.Volume = volume
	s.Looped = looped
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = reach
	s.Parent = parent
	return s
end

-- THE AMBIENCE, tagged so the client can let it drop away when the thing passes under. BaseVolume is
-- what the client scales from, so it never compounds its own changes.
--
-- ALWAYS ON A PART, never loose in the model: a sound parented to a model plays everywhere, and the
-- lobby would hear the harbour. On a part it is positional, at full volume out to `near` and gone by
-- `far`.
local function ambience(parent: BasePart, name: string, speed: number, volume: number, near: number, far: number): Sound
	local s = sound(parent, name, WATER_SOUND, speed, volume, far, true)
	s.RollOffMode = Enum.RollOffMode.Linear
	s.RollOffMinDistance = near
	s:SetAttribute("BaseVolume", volume)
	CollectionService:AddTag(s, "SunkenAmbience")
	s:Play()
	return s
end

-- ===== THE WATER, WITH ROUND HOLES =====
--
-- The surface is a sheet of glass plates, and two things stand in it that must stay dry inside: the
-- aquarium's tower and the whirlpool. A plate cannot have a round hole, so each hole is cut square
-- (the hole's outer radius, each way) and its four corners filled back with strips that stop inside
-- a band of the hole's own wall, where the wall hides their stepped edge. The strips never overlap
-- each other or the plates, because two panes of glass over each other read as a darker patch.
type Rect = { x0: number, x1: number, z0: number, z1: number }
type Hole = { centre: Vector3, outer: number, inner: number }

-- Everything in `area` that is not in `cuts`, as rectangles: slabs along X at every cut's edges, and
-- in each slab the runs of Z no cut covers.
local function subtract(area: Rect, cuts: { Rect }): { Rect }
	local xs = { area.x0, area.x1 }
	for _, cut in ipairs(cuts) do
		table.insert(xs, math.clamp(cut.x0, area.x0, area.x1))
		table.insert(xs, math.clamp(cut.x1, area.x0, area.x1))
	end
	table.sort(xs)
	local out: { Rect } = {}
	for index = 1, #xs - 1 do
		local a, b = xs[index], xs[index + 1]
		if b - a > 0.01 then
			local mid = (a + b) / 2
			local spans = {}
			for _, cut in ipairs(cuts) do
				if cut.x0 < mid and mid < cut.x1 then
					table.insert(spans, { cut.z0, cut.z1 })
				end
			end
			table.sort(spans, function(p, q)
				return p[1] < q[1]
			end)
			local z = area.z0
			for _, span in ipairs(spans) do
				if span[1] > z + 0.01 then
					table.insert(out, { x0 = a, x1 = b, z0 = z, z1 = math.min(span[1], area.z1) })
				end
				z = math.max(z, span[2])
			end
			if area.z1 > z + 0.01 then
				table.insert(out, { x0 = a, x1 = b, z0 = z, z1 = area.z1 })
			end
		end
	end
	return out
end

-- The strips that fill a round hole's square corners back in. Each covers one step of X, from just
-- outside the hole's inner radius to the square's edge; the steps are even in X squared, which is
-- what keeps every uncovered notch inside the band between the two radii.
local function fillers(hole: Hole): { Rect }
	local outer, inner = hole.outer, hole.inner
	local step = outer * outer - inner * inner
	local xs = { 0 }
	local k = 1
	while xs[#xs] < outer - 0.001 do
		table.insert(xs, math.min(outer, math.sqrt(k * step)))
		k += 1
	end
	local out: { Rect } = {}
	for index = 1, #xs - 1 do
		local a, b = xs[index], xs[index + 1]
		local z = math.sqrt(math.max(0, inner * inner - a * a))
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local x0, x1 = a, b
				if sx < 0 then
					x0, x1 = -b, -a
				end
				local z0, z1 = z, outer
				if sz < 0 then
					z0, z1 = -outer, -z
				end
				table.insert(out, { x0 = hole.centre.X + x0, x1 = hole.centre.X + x1, z0 = hole.centre.Z + z0,
					z1 = hole.centre.Z + z1 })
			end
		end
	end
	return out
end

-- A sheet of plates over the whole sea at height `y` (its top), minus the holes.
local function sheet(parent: Instance, name: string, centre: Vector3, y: number, thick: number, colour: Color3,
	material: Enum.Material, transparency: number, holes: { Hole })
	local cuts: { Rect } = {}
	for _, hole in ipairs(holes) do
		table.insert(cuts, { x0 = hole.centre.X - hole.outer, x1 = hole.centre.X + hole.outer,
			z0 = hole.centre.Z - hole.outer, z1 = hole.centre.Z + hole.outer })
	end
	local rects = subtract({ x0 = centre.X - SEA_HALF, x1 = centre.X + SEA_HALF, z0 = centre.Z - SEA_HALF,
		z1 = centre.Z + SEA_HALF }, cuts)
	for _, hole in ipairs(holes) do
		for _, rect in ipairs(fillers(hole)) do
			table.insert(rects, rect)
		end
	end
	for _, rect in ipairs(rects) do
		local nx = math.ceil((rect.x1 - rect.x0) / 2048)
		local nz = math.ceil((rect.z1 - rect.z0) / 2048)
		local w, d = (rect.x1 - rect.x0) / nx, (rect.z1 - rect.z0) / nz
		for i = 0, nx - 1 do
			for j = 0, nz - 1 do
				local plate = block(parent, name, Vector3.new(w, thick, d),
					CFrame.new(rect.x0 + (i + 0.5) * w, y - thick / 2, rect.z0 + (j + 0.5) * d), colour, material, false)
				plate.Transparency = transparency
				if material == Enum.Material.Glass then
					plate.Reflectance = 0.08
				end
			end
		end
	end
end

-- ===== BUILDINGS =====
--
-- Each is built in its lot's frame: origin on the sea floor at the lot's middle, +X outward from
-- the city's centre, +Z round the ring. `w` runs along Z (the frontage), `d` along X (the depth).

-- A WINDOW BAND: one dark ribbon round all four faces, a little proud of the wall. Only above the
-- murk, where anyone can see it.
local function ribbons(parent: Instance, frame: CFrame, w: number, d: number, from: number, to: number, every: number)
	local floorY = frame.Position.Y
	local start = math.max(from, waterLevel - MURK_DEPTH)
	if to - start < 2 then
		return
	end
	local count = math.min(10, math.floor((to - start) / every))
	for index = 1, count do
		local y = to - index * (to - start) / (count + 0.5)
		cityBlock(parent, "Windows", Vector3.new(d + 0.4, 1.6, w + 0.4), frame * CFrame.new(0, y - floorY, 0), GLASS,
			Enum.Material.Glass)
	end
end

-- FLOODED FLATS, roofless, their top storey a few studs under the surface with the rooms still
-- furnished. What you look down into from the route.
local function floodedFlats(parent: Instance, frame: CFrame, w: number, d: number, rng: Random)
	local floorY = frame.Position.Y
	local top = waterLevel - rng:NextNumber(2, 3.2)
	local storey = top - 8
	local facade = FACADES[rng:NextInteger(1, #FACADES)]
	cityBlock(parent, "Flats", Vector3.new(d, storey - floorY, w), frame * CFrame.new(0, (storey - floorY) / 2, 0), facade)
	ribbons(parent, frame, w, d, floorY, storey - 2, 6)
	local rel = storey - floorY
	for _, wall in ipairs({ { d / 2 - 0.4, 0, 0.8, w }, { -d / 2 + 0.4, 0, 0.8, w }, { 0, w / 2 - 0.4, d, 0.8 },
		{ 0, -w / 2 + 0.4, d, 0.8 } }) do
		cityBlock(parent, "FlatWall", Vector3.new(wall[3], 8, wall[4]), frame * CFrame.new(wall[1], rel + 4, wall[2]), facade)
	end
	-- A partition, and what was left in the rooms either side of it.
	local split = rng:NextNumber(-w / 5, w / 5)
	cityBlock(parent, "Partition", Vector3.new(d - 1.6, 6.5, 0.5), frame * CFrame.new(0, rel + 3.25, split), facade)
	local tone = FADED[rng:NextInteger(1, #FADED)]
	local a = frame * CFrame.new(rng:NextNumber(-d / 4, d / 4), rel, (split + w / 2) / 2)
	cityBlock(parent, "Bed", Vector3.new(4.2, 1.1, 2.4), a * CFrame.new(0, 0.55, 0), Color3.fromRGB(214, 210, 200))
	cityBlock(parent, "Blanket", Vector3.new(3, 0.3, 2.5), a * CFrame.new(0.5, 1.2, 0), tone)
	local b = frame * CFrame.new(rng:NextNumber(-d / 4, d / 4), rel, (split - w / 2) / 2)
	cityBlock(parent, "Sofa", Vector3.new(4, 1, 1.8), b * CFrame.new(0, 0.5, 0), tone, Enum.Material.Fabric)
	cityBlock(parent, "SofaBack", Vector3.new(4, 1.6, 0.5), b * CFrame.new(0, 1.3, -0.9), tone, Enum.Material.Fabric)
	cityBlock(parent, "Table", Vector3.new(2.4, 1.2, 1.6), b * CFrame.new(0.4, 0.6, 2.4), Color3.fromRGB(150, 120, 90))
	cityBlock(parent, "Fridge", Vector3.new(1.6, 3.4, 1.6), frame * CFrame.new(d / 2 - 1.6, rel + 1.7, split + 1.4),
		Color3.fromRGB(226, 226, 220))
	-- Sometimes a piece of the roof, fallen in and leaning on the partition.
	if rng:NextNumber() < 0.35 then
		cityBlock(parent, "FallenRoof", Vector3.new(d * 0.6, 0.6, w * 0.4),
			frame * CFrame.new(0, rel + 3, split + w / 5) * CFrame.Angles(math.rad(28), 0, 0), facade)
	end
end

-- A HOUSE OR A SHOP, low, entirely under the water, with a pitched roof made of two tilted slabs
-- (which look the same whichever way a wedge part happens to face).
local function house(parent: Instance, frame: CFrame, w: number, d: number, rng: Random)
	local floorY = frame.Position.Y
	local eaves = waterLevel - rng:NextNumber(10, 32)
	local facade = FACADES[rng:NextInteger(1, #FACADES)]
	local roof = Color3.fromRGB(120, 76, 66):Lerp(Color3.fromRGB(80, 88, 96), rng:NextNumber())
	local body = eaves - floorY
	cityBlock(parent, "House", Vector3.new(d, body, w), frame * CFrame.new(0, body / 2, 0), facade)
	ribbons(parent, frame, w, d, floorY, eaves - 2, 5)
	local rise = math.min(d, w) * 0.28
	local slope = math.atan2(rise, d / 2)
	local slab = math.sqrt(rise * rise + d * d / 4) + 0.6
	for _, side in ipairs({ -1, 1 }) do
		cityBlock(parent, "Roof", Vector3.new(slab, 0.6, w + 0.8),
			frame * CFrame.new(side * d / 4, body + rise / 2, 0) * CFrame.Angles(0, 0, -side * slope), roof)
	end
	if rng:NextNumber() < 0.5 then
		cityBlock(parent, "Chimney", Vector3.new(1.6, rise + 2, 1.6), frame * CFrame.new(d / 5, body + rise / 2 + 1, w / 4),
			facade)
	end
end

-- AN APARTMENT BLOCK OR AN OFFICE, standing up out of the water. `broken` takes a storey off one half.
local function tower(parent: Instance, frame: CFrame, w: number, d: number, top: number, office: boolean, rng: Random)
	local floorY = frame.Position.Y
	local facade = FACADES[rng:NextInteger(1, #FACADES)]
	local height = top - floorY
	local broken = not office and rng:NextNumber() < 0.4
	local main = if broken then height - 6 else height
	cityBlock(parent, if office then "Office" else "Apartments", Vector3.new(d, main, w),
		frame * CFrame.new(0, main / 2, 0), facade)
	if broken then
		-- The half that is still standing.
		cityBlock(parent, "Apartments", Vector3.new(d, 6, w / 2), frame * CFrame.new(0, main + 3, w / 4), facade)
	end
	ribbons(parent, frame, w, d, floorY, main - 2, if office then 4 else 6)
	if office then
		cityBlock(parent, "Crown", Vector3.new(d + 1, 1.4, w + 1), frame * CFrame.new(0, height - 0.7, 0), facade)
		if rng:NextNumber() < 0.5 then
			local at = frame * Vector3.new(d / 5, height, -w / 5)
			column(parent, "Antenna", 0.4, at, at.Y, at.Y + 10, Color3.fromRGB(90, 94, 100), false, true)
		end
	else
		cityBlock(parent, "RoofHouse", Vector3.new(d * 0.3, 3, w * 0.25), frame * CFrame.new(-d / 5, main + 1.5, -w / 5), facade)
		if rng:NextNumber() < 0.4 then
			local at = frame * Vector3.new(d / 5, main, w / 6)
			column(parent, "TankLegs", 2.6, at, at.Y, at.Y + 2.5, Color3.fromRGB(90, 80, 70), false, true)
			column(parent, "WaterTank", 4.2, at, at.Y + 2.5, at.Y + 7, Color3.fromRGB(128, 100, 80), false, true)
		end
	end
end

-- THE MULTI-STOREY CAR PARK: open decks on columns, cars still parked, the top deck a few studs
-- under the surface, where the cars are the plainest thing in the city to see from the route.
local function carPark(parent: Instance, frame: CFrame, w: number, d: number, rng: Random)
	local floorY = frame.Position.Y
	local deckTop = waterLevel - 4
	for _, cx in ipairs({ -d / 2 + 2, 0, d / 2 - 2 }) do
		for _, cz in ipairs({ -w / 2 + 2, 0, w / 2 - 2 }) do
			local at = frame * Vector3.new(cx, 0, cz)
			column(parent, "CarParkColumn", 2.2, at, floorY, deckTop - 1.2, STONE, false)
		end
	end
	for level = 0, 3 do
		local y = deckTop - level * 10
		cityBlock(parent, "Deck", Vector3.new(d, 1.2, w), frame * CFrame.new(0, y - 0.6 - floorY, 0), STONE,
			Enum.Material.Concrete)
		local cars = if level == 0 then 6 else 3
		for _ = 1, cars do
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local along = rng:NextNumber(-w / 2 + 4, w / 2 - 4)
			local car = frame * CFrame.new(side * (d / 2 - 6), y - floorY, along) * CFrame.Angles(0, rng:NextNumber(-0.08, 0.08), 0)
			local paint = FADED[rng:NextInteger(1, #FADED)]
			cityBlock(parent, "CarBody", Vector3.new(4.6, 1.3, 2.2), car * CFrame.new(0, 0.95, 0), paint)
			cityBlock(parent, "CarCabin", Vector3.new(2.4, 1, 2), car * CFrame.new(side * 0.3, 2.1, 0), paint:Lerp(GLASS, 0.5))
			cityBlock(parent, "CarWheels", Vector3.new(4.2, 0.6, 2), car * CFrame.new(0, 0.3, 0), Color3.fromRGB(30, 30, 32))
		end
	end
	for _, wall in ipairs({ { d / 2, 0, 0.5, w }, { -d / 2, 0, 0.5, w }, { 0, w / 2, d, 0.5 }, { 0, -w / 2, d, 0.5 } }) do
		cityBlock(parent, "Parapet", Vector3.new(wall[3], 1, wall[4]), frame * CFrame.new(wall[1], deckTop + 0.5 - floorY, wall[2]),
			STONE)
	end
	local post = frame * Vector3.new(-d / 2 + 1.5, deckTop - floorY, -w / 2 + 1.5)
	column(parent, "SignPost", 0.4, post, post.Y, post.Y + 1.6, Color3.fromRGB(80, 84, 90), false)
	local sign = cityBlock(parent, "ParkingSign", Vector3.new(2.2, 2.2, 0.3), CFrame.new(post + Vector3.new(0, 2.6, 0))
		* (frame - frame.Position), Color3.fromRGB(40, 70, 150))
	label(sign, Enum.NormalId.Front, "P", Color3.fromRGB(220, 230, 240))
	label(sign, Enum.NormalId.Back, "P", Color3.fromRGB(220, 230, 240))
end

-- ===== THE CITY =====
--
-- Bands of lots in rings round the plaza, inside and outside the boulevard, cut by eight avenues;
-- the harbour sector has none outside the ring. `blocked(point, reach)` says whether a lot there
-- would stand in something that has already claimed the space (the aquarium, the car park).

type Band = { from: number, to: number, kind: string }

local function bands(radius: number): { Band }
	local out: { Band } = {}
	local innerFrom, innerTo = PLAZA_RADIUS + STREET / 2, radius - BOULEVARD_HALF - STREET / 2
	local depth = innerTo - innerFrom
	if depth >= 30 then
		local count = math.max(1, math.floor((depth + STREET) / (INNER_BAND + STREET)))
		local each = (depth - (count - 1) * STREET) / count
		for index = 1, count do
			local from = innerFrom + (index - 1) * (each + STREET)
			table.insert(out, { from = from, to = from + each, kind = if index == count then "nearInner" else "inner" })
		end
	end
	local outerFrom = radius + BOULEVARD_HALF + STREET / 2
	for index = 1, OUTER_BANDS do
		local from = outerFrom + (index - 1) * (OUTER_BAND + STREET)
		table.insert(out, { from = from, to = from + OUTER_BAND, kind = if index == 1 then "nearOuter" else "outer" .. index })
	end
	return out
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function city(parent: Instance, centre: Vector3, radius: number, floorY: number, harbourAngle: number,
	carParkAngle: number, blocked: (Vector3, number) -> boolean, rng: Random): number
	local built = 0
	local carParkDone = false
	local avenueOffset = rng:NextNumber(0, 2 * math.pi / AVENUES)
	for _, band in ipairs(bands(radius)) do
		local mid = (band.from + band.to) / 2
		local theta = 0
		while theta < 2 * math.pi do
			local arc = rng:NextNumber(LOT_ARC_MIN, LOT_ARC_MAX)
			local span = arc / mid
			local at = theta + span / 2
			theta += span
			-- Not across an avenue.
			local onAvenue = false
			for k = 0, AVENUES - 1 do
				local avenue = avenueOffset + k * 2 * math.pi / AVENUES
				if math.abs(wrapAngle(at - avenue)) < span / 2 + (AVENUE_WIDE / 2) / mid then
					onAvenue = true
					break
				end
			end
			local outside = band.from > radius
			local inHarbour = outside and math.abs(wrapAngle(at - harbourAngle)) < HARBOUR_SECTOR_HALF
			local where = Vector3.new(centre.X + math.cos(at) * mid, floorY, centre.Z + math.sin(at) * mid)
			-- As wide as the lot is at its NARROW end, so neighbours never overlap at the inner corners.
			local w, d = span * band.from - 6, band.to - band.from
			local reach = math.sqrt(w * w + d * d) / 2
			if not onAvenue and not inHarbour and not blocked(where, reach) then
				local out = Vector3.new(math.cos(at), 0, math.sin(at))
				local frame = CFrame.fromMatrix(where, out, Vector3.yAxis)
				-- May it break the surface? Only where the whole lot is EMERGE_CLEAR beyond the reach.
				local clearOfRoute = band.from - (radius + ROUTE_REACH) >= EMERGE_CLEAR
					or (radius - ROUTE_REACH) - band.to >= EMERGE_CLEAR
				local pick = rng:NextNumber()
				if band.kind == "nearOuter" and not carParkDone and math.abs(wrapAngle(at - carParkAngle)) < span then
					carPark(parent, frame, w, d, rng)
					carParkDone = true
				elseif band.kind == "nearOuter" or band.kind == "nearInner" then
					if pick < 0.55 then
						floodedFlats(parent, frame, w, d, rng)
					elseif pick < 0.8 or not clearOfRoute then
						house(parent, frame, w, d, rng)
					else
						tower(parent, frame, w, d * 0.8, waterLevel + rng:NextNumber(6, 18), false, rng)
					end
				elseif band.kind == "inner" then
					if pick < 0.7 or not clearOfRoute then
						house(parent, frame, w, d * 0.8, rng)
					else
						floodedFlats(parent, frame, w, d * 0.7, rng)
					end
				elseif band.kind == "outer2" then
					if pick < 0.5 and clearOfRoute then
						tower(parent, frame, w, d * 0.6, waterLevel + rng:NextNumber(8, 28), false, rng)
					elseif pick < 0.75 then
						floodedFlats(parent, frame, w, d * 0.6, rng)
					else
						house(parent, frame, w, d * 0.6, rng)
					end
				else
					if pick < 0.6 and clearOfRoute then
						tower(parent, frame, w * 0.8, d * 0.5, waterLevel + rng:NextNumber(24, 58), true, rng)
					elseif pick < 0.9 and clearOfRoute then
						tower(parent, frame, w, d * 0.6, waterLevel + rng:NextNumber(8, 26), false, rng)
					end
				end
				built += 1
			end
		end
	end
	-- LONE TOWERS out past the last band, for a skyline that fades into the haze.
	local last = radius + BOULEVARD_HALF + STREET / 2 + OUTER_BANDS * (OUTER_BAND + STREET)
	for index = 1, FAR_TOWERS do
		local at = (index / FAR_TOWERS) * 2 * math.pi + rng:NextNumber(-0.2, 0.2)
		if math.abs(wrapAngle(at - harbourAngle)) > HARBOUR_SECTOR_HALF then
			local r = last + rng:NextNumber(80, 420)
			local where = Vector3.new(centre.X + math.cos(at) * r, floorY, centre.Z + math.sin(at) * r)
			local frame = CFrame.fromMatrix(where, Vector3.new(math.cos(at), 0, math.sin(at)), Vector3.yAxis)
			tower(parent, frame, rng:NextNumber(26, 40), rng:NextNumber(26, 40), waterLevel + rng:NextNumber(40, 90), true, rng)
			built += 1
		end
	end
	return built
end

-- ===== THE PLAZA AND THE CLOCK TOWER =====
--
-- Stopped at twelve minutes past four, which is when the water came. The minute hands are tagged so
-- SunkenCityClient can make them try, now and then, to move on.
local function clockTower(parent: Instance, centre: Vector3, floorY: number)
	column(parent, "Plaza", PLAZA_RADIUS * 2, centre, floorY, floorY + 0.6, Color3.fromRGB(120, 116, 106), false)
	local top = waterLevel + 44
	local side = 22
	cityBlock(parent, "ClockTower", Vector3.new(side, top - floorY, side), CFrame.new(centre.X, (floorY + top) / 2, centre.Z), STONE)
	ribbons(parent, CFrame.new(centre.X, floorY, centre.Z), side, side, floorY, waterLevel + 20, 8)
	cityBlock(parent, "Cornice", Vector3.new(side + 2, 1.6, side + 2), CFrame.new(centre.X, top - 6, centre.Z), STONE)
	-- The belfry, and a stepped roof with a spire.
	for index, size in ipairs({ side - 2, side - 8, side - 14 }) do
		cityBlock(parent, "Roof", Vector3.new(size, 3, size), CFrame.new(centre.X, top + 1.5 + (index - 1) * 3, centre.Z),
			Color3.fromRGB(96, 110, 108))
	end
	column(parent, "Spire", 1.2, centre, top + 9, top + 22, Color3.fromRGB(110, 104, 90), false, true)
	local faceY = waterLevel + 30
	for index = 0, 3 do
		local normal = Vector3.new(math.cos(index * math.pi / 2), 0, math.sin(index * math.pi / 2))
		local faceAt = Vector3.new(centre.X, faceY, centre.Z) + normal * (side / 2 + 0.3)
		local face = block(parent, "ClockFace", Vector3.new(0.6, 14, 14),
			CFrame.lookAt(faceAt, faceAt + normal) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(232, 228, 214),
			Enum.Material.SmoothPlastic, false)
		face.Shape = Enum.PartType.Cylinder
		local pivot = CFrame.lookAt(faceAt, faceAt - normal)
		-- 4:12. Clockwise, seen from in front, is a negative turn about the face's outward normal.
		local hour = block(parent, "HourHand", Vector3.new(0.8, 4.2, 0.2),
			pivot * CFrame.Angles(0, 0, -math.rad(126)) * CFrame.new(0, 2.1, 0.4), Color3.fromRGB(30, 30, 34),
			Enum.Material.Metal, false)
		hour:SetAttribute("Pivot", pivot)
		local minute = block(parent, "MinuteHand", Vector3.new(0.6, 6, 0.2),
			pivot * CFrame.Angles(0, 0, -math.rad(72)) * CFrame.new(0, 3, 0.5), Color3.fromRGB(30, 30, 34),
			Enum.Material.Metal, false)
		minute:SetAttribute("Pivot", pivot)
		CollectionService:AddTag(minute, "SunkenClockHand")
	end
end

-- ===== THE BOULEVARD'S ROAD SIGNS =====
--
-- Gantries across the street under the route, their signs a few studs down: the one thing on the
-- boulevard you can read from the route. The thing swims under them.
local function gantries(parent: Instance, centre: Vector3, radius: number, floorY: number, angles: { number })
	local names = { "CITY CENTRE", "HARBOUR", "AQUARIUM", "CLOCK TOWER" }
	for index, at in ipairs(angles) do
		local out = Vector3.new(math.cos(at), 0, math.sin(at))
		local beamY = waterLevel - 4.5
		for _, side in ipairs({ -1, 1 }) do
			local foot = centre + out * (radius + side * 38)
			column(parent, "GantryLeg", 1.4, foot, floorY, beamY, Color3.fromRGB(110, 116, 120), false)
		end
		local mid = centre + out * radius + Vector3.new(0, beamY, 0)
		local frame = CFrame.fromMatrix(mid, out, Vector3.yAxis)
		cityBlock(parent, "GantryBeam", Vector3.new(78, 1.4, 1.4), frame, Color3.fromRGB(110, 116, 120), Enum.Material.Metal)
		local panel = cityBlock(parent, "RoadSign", Vector3.new(22, 6, 0.4), frame * CFrame.new(-8, -3.7, 0),
			Color3.fromRGB(30, 96, 70))
		label(panel, Enum.NormalId.Front, names[(index - 1) % #names + 1], Color3.fromRGB(226, 232, 226))
		label(panel, Enum.NormalId.Back, names[index % #names + 1], Color3.fromRGB(226, 232, 226))
	end
end

-- ===== THE HARBOUR =====
local function harbour(parent: Instance, centre: Vector3, radius: number, floorY: number, harbourAngle: number,
	rng: Random)
	-- Quay walls along the sector's edges, their tops a few studs out of the water.
	for _, side in ipairs({ -1, 1 }) do
		local at = harbourAngle + side * HARBOUR_SECTOR_HALF
		local out = Vector3.new(math.cos(at), 0, math.sin(at))
		local from, to = radius + BOULEVARD_HALF + EMERGE_CLEAR, radius + 520
		local mid = centre + out * ((from + to) / 2) + Vector3.new(0, (floorY + waterLevel + 3) / 2, 0)
		block(parent, "Quay", Vector3.new(to - from, waterLevel + 3 - floorY, 8), CFrame.fromMatrix(mid, out, Vector3.yAxis),
			STONE, Enum.Material.Concrete, false)
	end
	-- A gantry crane standing out in the basin: the landmark on the harbour side.
	local craneAt = harbourAngle + 0.05 * 2 * math.pi
	local out = Vector3.new(math.cos(craneAt), 0, math.sin(craneAt))
	local base = centre + out * (radius + 230)
	local frame = CFrame.fromMatrix(Vector3.new(base.X, floorY, base.Z), out, Vector3.yAxis)
	local craneTop = waterLevel + 42
	local paint = Color3.fromRGB(186, 104, 64)
	for _, leg in ipairs({ { -10, -12 }, { 10, -12 }, { -10, 12 }, { 10, 12 } }) do
		local at = frame * Vector3.new(leg[1], 0, leg[2])
		column(parent, "CraneLeg", 2.4, at, floorY, craneTop, paint, false)
	end
	block(parent, "CraneBeam", Vector3.new(24, 3, 28), frame * CFrame.new(0, craneTop - floorY + 1.5, 0), paint,
		Enum.Material.Metal, false)
	block(parent, "CraneBoom", Vector3.new(70, 2.4, 3), frame * CFrame.new(-30, craneTop - floorY + 4.2, 0), paint,
		Enum.Material.Metal, false)
	block(parent, "CraneCab", Vector3.new(6, 5, 6), frame * CFrame.new(4, craneTop - floorY + 5.5, 0),
		Color3.fromRGB(210, 200, 180), Enum.Material.SmoothPlastic, false)
	-- A fishing boat that went down by the quay, its bow still out of the water.
	local boatAt = harbourAngle - 0.08 * 2 * math.pi
	local boatOut = Vector3.new(math.cos(boatAt), 0, math.sin(boatAt))
	local boat = CFrame.fromMatrix(centre + boatOut * (radius + 150) + Vector3.new(0, waterLevel - 6, 0), boatOut, Vector3.yAxis)
		* CFrame.Angles(math.rad(-32), 0, math.rad(8))
	cityBlock(parent, "Hull", Vector3.new(7, 4, 22), boat, Color3.fromRGB(60, 80, 110))
	cityBlock(parent, "HullBand", Vector3.new(7.2, 1, 22.2), boat * CFrame.new(0, 1.6, 0), Color3.fromRGB(200, 196, 186))
	cityBlock(parent, "Wheelhouse", Vector3.new(5, 4, 6), boat * CFrame.new(0, 4, 3), Color3.fromRGB(214, 210, 200))
	-- BUOYS, floating on the water and chained to the floor. Tagged so the client can bob them.
	for index = 1, 5 do
		local at = harbourAngle + rng:NextNumber(-0.9, 0.9) * HARBOUR_SECTOR_HALF
		local r = radius + BOULEVARD_HALF + EMERGE_CLEAR + rng:NextNumber(20, 300)
		local spot = centre + Vector3.new(math.cos(at) * r, waterLevel, math.sin(at) * r)
		local buoy = Instance.new("Model")
		buoy.Name = "Buoy"
		local red = index % 2 == 0
		column(buoy, "BuoyBody", 3, spot, waterLevel - 1.2, waterLevel + 1.8,
			if red then Color3.fromRGB(190, 70, 60) else Color3.fromRGB(230, 226, 214), false, true)
		column(buoy, "BuoyMast", 0.4, spot, waterLevel + 1.8, waterLevel + 5, Color3.fromRGB(60, 60, 64), false, true)
		block(buoy, "BuoyTop", Vector3.new(1.4, 1.4, 1.4), CFrame.new(spot + Vector3.new(0, 5.4, 0)),
			if red then Color3.fromRGB(190, 70, 60) else Color3.fromRGB(60, 120, 80), Enum.Material.SmoothPlastic, false)
		buoy.Parent = parent
		CollectionService:AddTag(buoy, "SunkenBuoy")
		rod(parent, "BuoyChain", spot + Vector3.new(0, -1.2, 0), Vector3.new(spot.X, floorY, spot.Z), 0.3,
			Color3.fromRGB(70, 66, 60))
	end
end

-- ===== THE CAP of a stable chunk =====
local function capOf(model: Instance): BasePart?
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") and item.Name == "SurfaceCap" then
			return item
		end
	end
	return nil
end

-- The frame beside a checkpoint: origin on its cap's outer edge at the cap's top, +X outward from
-- the city's centre, +Z along the route. Sky Pools' terraces use the same frame.
local function besideFrame(cap: BasePart, centre: Vector3): CFrame?
	local flat = Vector3.new(cap.Position.X - centre.X, 0, cap.Position.Z - centre.Z)
	if flat.Magnitude < 1 then
		return nil
	end
	local outward = flat.Unit
	local capCF = cap.CFrame
	local halfOut = math.abs(capCF.RightVector:Dot(outward)) * cap.Size.X / 2
		+ math.abs(capCF.LookVector:Dot(outward)) * cap.Size.Z / 2
	local top = cap.Position.Y + cap.Size.Y / 2
	return CFrame.fromMatrix(Vector3.new(cap.Position.X, top, cap.Position.Z) + outward * halfOut, outward, Vector3.yAxis)
end

-- ===== THE AQUARIUM =====
--
-- Built in the frame beside its checkpoint. Returns the round tower's centre (for the water's hole)
-- and the far end of the gallery (for keeping lots out of the way), plus the gallery's window.

type Aquarium = { tower: Vector3, far: Vector3, window: BasePart, light: PointLight, hum: Sound }

-- The solid height ranges of one wall segment, from `bottom` to `top`, minus the openings it
-- crosses, each cut at the murk and at the surface so the drowned colour follows the depth.
local function wallRuns(bottom: number, top: number, openings: { { number } }): { { number } }
	local runs = { { bottom, top } }
	for _, gap in ipairs(openings) do
		local next = {}
		for _, run in ipairs(runs) do
			if gap[2] <= run[1] or gap[1] >= run[2] then
				table.insert(next, run)
			else
				if gap[1] > run[1] then
					table.insert(next, { run[1], gap[1] })
				end
				if gap[2] < run[2] then
					table.insert(next, { gap[2], run[2] })
				end
			end
		end
		runs = next
	end
	local cut = {}
	for _, run in ipairs(runs) do
		local marks = { run[1] }
		for _, y in ipairs({ waterLevel - MURK_DEPTH, waterLevel }) do
			if y > run[1] and y < run[2] then
				table.insert(marks, y)
			end
		end
		table.insert(marks, run[2])
		for index = 1, #marks - 1 do
			table.insert(cut, { marks[index], marks[index + 1] })
		end
	end
	return cut
end

local function lamp(parent: Instance, at: CFrame, brightness: number, range: number, colour: Color3): PointLight
	local fixture = block(parent, "Lamp", Vector3.new(1, 0.8, 1), at, Color3.fromRGB(230, 220, 190),
		Enum.Material.SmoothPlastic, false)
	local light = Instance.new("PointLight")
	light.Brightness = brightness
	light.Range = range
	light.Color = colour
	light.Shadows = true
	light.Parent = fixture
	return light
end

local function aquarium(parent: Instance, frame: CFrame, floorY: number, rng: Random): Aquarium
	local landingY = frame.Position.Y
	local tunnelY = waterLevel - TUNNEL_BELOW
	local xc = AQ_NECK + ROT_R - ROT_WALL
	local towerAt = frame * CFrame.new(xc, 0, 0)
	local warm = Color3.fromRGB(255, 214, 170)

	-- The landing, from the checkpoint to the door.
	block(parent, "Landing", Vector3.new(AQ_NECK + 0.4, NECK_THICK, AQ_NECK_WIDE),
		frame * CFrame.new(AQ_NECK / 2, -NECK_THICK / 2, 0), STONE, Enum.Material.Concrete, true)

	-- THE TOWER'S WALL: segments at every fifteen degrees, with the door facing the route and the
	-- tunnel's mouth facing out, and every run drowned by its own depth.
	local roofY = landingY + ROT_ROOF
	for index = 0, ROT_SEGMENTS - 1 do
		local psi = index * 2 * math.pi / ROT_SEGMENTS
		local openings = {}
		if index >= 11 and index <= 13 then
			table.insert(openings, { landingY - 0.5, landingY + DOOR_H })
		end
		if index == 23 or index == 0 or index == 1 then
			table.insert(openings, { tunnelY - 0.5, tunnelY + TUNNEL_H + 0.6 })
		end
		local chord = 2 * ROT_R * math.sin(math.pi / ROT_SEGMENTS) + 0.1
		for _, run in ipairs(wallRuns(floorY, roofY, openings)) do
			local height = run[2] - run[1]
			local mid = (run[1] + run[2]) / 2
			local cf = towerAt * CFrame.Angles(0, -psi, 0) * CFrame.new(ROT_R - ROT_WALL / 2, mid - landingY, 0)
			block(parent, "TowerWall", Vector3.new(ROT_WALL, height, chord), cf, drowned(STONE, mid), Enum.Material.Concrete, true)
		end
	end
	local roof = block(parent, "TowerRoof", Vector3.new(1.2, ROT_R * 2 + 1.2, ROT_R * 2 + 1.2),
		towerAt * CFrame.new(0, ROT_ROOF + 0.6, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(96, 124, 118),
		Enum.Material.SmoothPlastic, true)
	roof.Shape = Enum.PartType.Cylinder
	local sign = block(parent, "AquariumSign", Vector3.new(0.3, 1.8, 8), towerAt * CFrame.new(-ROT_R - 0.2, DOOR_H + 1.4, 0),
		Color3.fromRGB(34, 70, 80), Enum.Material.SmoothPlastic, false)
	label(sign, Enum.NormalId.Left, "AQUARIUM", Color3.fromRGB(210, 226, 220))

	-- The column the stair turns round, the floor at the top of the stair, and the one at the bottom.
	column(parent, "StairColumn", 5, towerAt.Position, tunnelY, roofY, STONE, true, true)
	block(parent, "TopLanding", Vector3.new(ROT_R - ROT_WALL - 2.6, 1, 8),
		towerAt * CFrame.new(-(2.6 + ROT_R - ROT_WALL) / 2, -0.5, 0), STONE, Enum.Material.Concrete, true)
	local bottomFloor = block(parent, "TowerFloor", Vector3.new(1, (ROT_R - ROT_WALL) * 2, (ROT_R - ROT_WALL) * 2),
		CFrame.new(towerAt.Position.X, tunnelY - 0.5, towerAt.Position.Z) * CFrame.Angles(0, 0, math.pi / 2), STONE,
		Enum.Material.Concrete, true)
	bottomFloor.Shape = Enum.PartType.Cylinder

	-- THE STAIR, turning down from the top landing: a step every eighteen degrees, as many as the
	-- drop needs at no more than STEP_RISE_MAX each, the last one landing on the floor.
	local drop = landingY - tunnelY
	local count = math.ceil(drop / STEP_RISE_MAX)
	local rise = drop / count
	local firstAngle = math.pi + 0.6
	for step = 1, count - 1 do
		local psi = firstAngle + (step - 0.5) * STEP_ANGLE
		local cf = towerAt * CFrame.Angles(0, -psi, 0) * CFrame.new(6.15, -step * rise - 0.5, 0)
		block(parent, "Step", Vector3.new(7.1, 1, 3.2), cf, drowned(STONE, landingY - step * rise), Enum.Material.Concrete, true)
	end
	-- Three lamps down the stairwell, at depths under the door.
	for index, depth in ipairs({ 6, 18, drop - 6 }) do
		local psi = math.pi / 2 + index * 2.1
		lamp(parent, towerAt * CFrame.Angles(0, -psi, 0) * CFrame.new(ROT_R - ROT_WALL - 0.6, -math.min(depth, drop - 4), 0),
			0.8, 16, warm)
	end
	-- DRIPS in the stairwell, irregular, so no two settle into a rhythm.
	for index = 1, 3 do
		local drip = sound(parent, "Drip", WATER_SOUND, 1, 0.3, 50, false)
		local host = block(parent, "DripSource", Vector3.new(0.4, 0.4, 0.4),
			towerAt * CFrame.new(rng:NextNumber(-6, 6), -index * drop / 4, rng:NextNumber(-6, 6)), STONE,
			Enum.Material.SmoothPlastic, false)
		host.Transparency = 1
		drip.Parent = host
		task.spawn(function()
			local timing = Random.new(90 + index)
			while drip.Parent do
				task.wait(timing:NextNumber(4, 13))
				drip.PlaybackSpeed = timing:NextNumber(0.95, 1.2)
				drip:Play()
			end
		end)
	end

	-- THE TUNNEL: a walkway through the water on pillars, glass sides and a pointed glass roof,
	-- framed at every bay.
	local tunnelFrom = xc + ROT_R - 0.3
	local tunnelTo = tunnelFrom + TUNNEL_L
	local ty = tunnelY - landingY
	block(parent, "TunnelFloor", Vector3.new(TUNNEL_L + 0.6, 1, TUNNEL_W), frame * CFrame.new((tunnelFrom + tunnelTo) / 2, ty - 0.5, 0),
		drowned(STONE, tunnelY), Enum.Material.Concrete, true)
	local glassColour = Color3.fromRGB(150, 200, 205)
	local metal = drowned(Color3.fromRGB(70, 80, 84), tunnelY)
	local bays = math.floor(TUNNEL_L / TUNNEL_BAY)
	local half = TUNNEL_W / 2 + 0.2
	local ridge = TUNNEL_H - 6
	local slope = math.atan2(ridge, half)
	local roofSpan = math.sqrt(ridge * ridge + half * half)
	for bay = 0, bays do
		local x = tunnelFrom + bay * TUNNEL_BAY
		if bay < bays then
			local mid = x + TUNNEL_BAY / 2
			for _, side in ipairs({ -1, 1 }) do
				local pane = block(parent, "TunnelGlass", Vector3.new(TUNNEL_BAY, 6, 0.4), frame * CFrame.new(mid, ty + 3, side * half),
					glassColour, Enum.Material.Glass, true)
				pane.Transparency = 0.6
				local roofPane = block(parent, "TunnelGlass", Vector3.new(TUNNEL_BAY, 0.4, roofSpan + 0.3),
					frame * CFrame.new(mid, ty + 6 + ridge / 2, side * half / 2) * CFrame.Angles(side * slope, 0, 0),
					glassColour, Enum.Material.Glass, true)
				roofPane.Transparency = 0.6
			end
		end
		local post = if bay == 0 then 1.6 else 0.6
		for _, side in ipairs({ -1, 1 }) do
			block(parent, "TunnelRib", Vector3.new(0.6, 6, post), frame * CFrame.new(x, ty + 3, side * (half + post / 2 - 0.3)),
				metal, Enum.Material.Metal, true)
			block(parent, "TunnelRib", Vector3.new(0.6, 0.6, roofSpan + 0.6),
				frame * CFrame.new(x, ty + 6 + ridge / 2, side * half / 2) * CFrame.Angles(side * slope, 0, 0), metal,
				Enum.Material.Metal, false)
			-- Pillars to the floor, a pair at every rib.
			local at = frame * Vector3.new(x, 0, side * 2.6)
			column(parent, "TunnelPillar", 1.6, at, floorY, tunnelY - 1, STONE, true)
		end
	end
	lamp(parent, frame * CFrame.new(tunnelFrom + TUNNEL_L * 0.35, ty + TUNNEL_H - 1.2, 0), 0.5, 14, Color3.fromRGB(190, 220, 230))
	lamp(parent, frame * CFrame.new(tunnelFrom + TUNNEL_L * 0.75, ty + TUNNEL_H - 1.2, 0), 0.5, 14, Color3.fromRGB(190, 220, 230))

	-- THE GALLERY at the tunnel's end: the top floor of a building standing on the sea floor.
	local roomX = tunnelTo + ROOM_L / 2 - 0.3
	local room = frame * CFrame.new(roomX, 0, 0)
	block(parent, "GalleryBase", Vector3.new(ROOM_L + 2, tunnelY - floorY, ROOM_W + 2),
		room * CFrame.new(0, (floorY + tunnelY) / 2 - landingY, 0), drowned(STONE, (floorY + tunnelY) / 2), Enum.Material.Concrete, true)
	local wallY = ty + ROOM_H / 2
	local wallColour = drowned(STONE, tunnelY + ROOM_H / 2)
	-- Side walls whole; the back wall round the tunnel's doorway; the front wall round the window.
	for _, side in ipairs({ -1, 1 }) do
		block(parent, "GalleryWall", Vector3.new(ROOM_L + 2, ROOM_H, 1), room * CFrame.new(0, wallY, side * (ROOM_W / 2 + 0.5)),
			wallColour, Enum.Material.Concrete, true)
		local sideWidth = (ROOM_W - TUNNEL_W - 1.2) / 2
		block(parent, "GalleryWall", Vector3.new(1, ROOM_H, sideWidth),
			room * CFrame.new(-ROOM_L / 2 - 0.5, wallY, side * (TUNNEL_W / 2 + 0.6 + sideWidth / 2)), wallColour,
			Enum.Material.Concrete, true)
		local windowSide = (ROOM_W - 10) / 2
		block(parent, "GalleryWall", Vector3.new(1, ROOM_H, windowSide),
			room * CFrame.new(ROOM_L / 2 + 0.5, wallY, side * (5 + windowSide / 2)), wallColour, Enum.Material.Concrete, true)
	end
	block(parent, "GalleryLintel", Vector3.new(1, ROOM_H - TUNNEL_H, TUNNEL_W + 1.2),
		room * CFrame.new(-ROOM_L / 2 - 0.5, ty + TUNNEL_H + (ROOM_H - TUNNEL_H) / 2, 0), wallColour, Enum.Material.Concrete, true)
	block(parent, "GallerySill", Vector3.new(1, 2.5, 10), room * CFrame.new(ROOM_L / 2 + 0.5, ty + 1.25, 0), wallColour,
		Enum.Material.Concrete, true)
	block(parent, "GalleryLintel", Vector3.new(1, ROOM_H - 8.5, 10), room * CFrame.new(ROOM_L / 2 + 0.5, ty + 8.5 + (ROOM_H - 8.5) / 2, 0),
		wallColour, Enum.Material.Concrete, true)
	block(parent, "GalleryCeiling", Vector3.new(ROOM_L + 2, 1, ROOM_W + 2), room * CFrame.new(0, ty + ROOM_H + 0.5, 0), wallColour,
		Enum.Material.Concrete, true)
	-- The building's upper floors, above the gallery and still under the water.
	local upperFrom = tunnelY + ROOM_H + 1
	local upperTo = waterLevel - 8
	if upperTo - upperFrom > 1 then
		block(parent, "GalleryUpper", Vector3.new(ROOM_L + 2, upperTo - upperFrom, ROOM_W + 2),
			room * CFrame.new(0, (upperFrom + upperTo) / 2 - landingY, 0), drowned(STONE, (upperFrom + upperTo) / 2),
			Enum.Material.Concrete, false)
	end
	-- The window onto the deep, in a brass frame.
	local window = block(parent, "ViewingWindow", Vector3.new(0.3, 6, 10), room * CFrame.new(ROOM_L / 2 + 0.5, ty + 5.5, 0),
		glassColour, Enum.Material.Glass, true)
	window.Transparency = 0.55
	window.CanQuery = true
	for _, edge in ipairs({ { 0, 2.5, 0.5, 10.6 }, { 0, 8.5, 0.5, 10.6 }, { -5.1, 5.5, 6.4, 0.5 }, { 5.1, 5.5, 6.4, 0.5 } }) do
		block(parent, "WindowFrame", Vector3.new(0.6, edge[3], edge[4]), room * CFrame.new(ROOM_L / 2 - 0.1, ty + edge[2], edge[1]),
			BRASS, Enum.Material.Metal, false)
	end
	local notice = block(parent, "Notice", Vector3.new(0.1, 1.6, 4.6), room * CFrame.new(ROOM_L / 2 - 0.1, ty + 6, 8.3),
		Color3.fromRGB(226, 220, 200), Enum.Material.SmoothPlastic, false)
	label(notice, Enum.NormalId.Left, "PLEASE DO NOT TAP ON THE GLASS", Color3.fromRGB(60, 40, 30))
	-- A bench facing it.
	block(parent, "Bench", Vector3.new(1.8, 0.5, 7), room * CFrame.new(ROOM_L / 2 - 6, ty + 1.6, 0), Color3.fromRGB(120, 90, 64),
		Enum.Material.Wood, true)
	for _, z in ipairs({ -2.8, 2.8 }) do
		block(parent, "BenchLeg", Vector3.new(1.4, 1.35, 0.4), room * CFrame.new(ROOM_L / 2 - 6, ty + 0.68, z), Color3.fromRGB(60, 60, 64),
			Enum.Material.Metal, false)
	end
	local light = lamp(parent, room * CFrame.new(0, ty + ROOM_H - 0.5, 0), 0.7, 20, Color3.fromRGB(200, 225, 230))
	local hum = sound(window, "Hum", WATER_SOUND, 0.18, 0.2, 40, true)
	hum:Play()

	-- KELP, in strands from the floor, and three shoals of fish (the client makes and moves the fish
	-- from these markers).
	for _ = 1, 10 do
		local along = rng:NextNumber(tunnelFrom, tunnelTo + ROOM_L)
		local off = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(10, 28)
		local at = frame * Vector3.new(along, 0, off)
		local topY = math.min(waterLevel - 4, tunnelY + rng:NextNumber(-6, 10))
		local y0 = floorY
		local lean = rng:NextNumber(-0.25, 0.25)
		for piece = 1, 3 do
			local y1 = floorY + (topY - floorY) * piece / 3
			local from = Vector3.new(at.X + lean * (piece - 1) * 3, y0, at.Z)
			local to = Vector3.new(at.X + lean * piece * 3, y1, at.Z)
			rod(parent, "Kelp", from, to, 1.2, Color3.fromRGB(70, 104, 56))
			y0 = y1
		end
	end
	for index, spot in ipairs({ { tunnelFrom + TUNNEL_L * 0.3, 12 }, { tunnelFrom + TUNNEL_L * 0.7, -12 }, { roomX + ROOM_L / 2 + 18, 0 } }) do
		local marker = block(parent, "FishShoal", Vector3.new(1, 1, 1), frame * CFrame.new(spot[1], ty + 5, spot[2]), FOAM,
			Enum.Material.SmoothPlastic, false)
		marker.Transparency = 1
		marker:SetAttribute("Radius", if index == 3 then 16 else 11)
		marker:SetAttribute("Count", 9)
		marker:SetAttribute("Speed", 0.35 + index * 0.08)
		CollectionService:AddTag(marker, "SunkenFishShoal")
	end

	-- WHERE THE CLIENT TINTS THE VIEW: under the water inside the tower, and the tunnel and gallery.
	for _, zone in ipairs({
		{ xc, (tunnelY + waterLevel) / 2 - landingY, 0, (ROT_R - ROT_WALL) * 2, waterLevel - tunnelY + 2, (ROT_R - ROT_WALL) * 2 },
		{ (tunnelFrom + roomX + ROOM_L / 2) / 2, ty + ROOM_H / 2, 0, roomX + ROOM_L / 2 - tunnelFrom, ROOM_H + 2, ROOM_W },
	}) do
		local box = block(parent, "AquariumZone", Vector3.new(zone[4], zone[5], zone[6]), frame * CFrame.new(zone[1], zone[2], zone[3]),
			FOAM, Enum.Material.SmoothPlastic, false)
		box.Transparency = 1
		CollectionService:AddTag(box, "SunkenAquariumZone")
		CollectionService:AddTag(box, "SunkenShelter")
	end
	-- And the whole tower, door to floor, as a shelter from the surge: nothing outside reaches in.
	local towerShelter = block(parent, "Shelter", Vector3.new((ROT_R - ROT_WALL) * 2, roofY - tunnelY, (ROT_R - ROT_WALL) * 2),
		frame * CFrame.new(xc, (roofY + tunnelY) / 2 - landingY, 0), FOAM, Enum.Material.SmoothPlastic, false)
	towerShelter.Transparency = 1
	CollectionService:AddTag(towerShelter, "SunkenShelter")

	return {
		tower = towerAt.Position,
		far = (frame * CFrame.new(roomX + ROOM_L / 2, 0, 0)).Position,
		window = window,
		light = light,
		hum = hum,
	}
end

-- ===== THE LAST DRY FLAT =====
--
-- A block of flats standing in the water beside a checkpoint, its top floor still above the surface
-- and still dry, reached over a plank gangway: the second place off the route to step into (ROADMAP
-- section 6), and the quiet one. A lamp is still on inside, so the doorway shows from the route. The
-- flat is small and nearly bare: a sofa facing the window over the drowned city, a kitchen counter,
-- the calendar, a stairwell going down into the flooded floor below where the stairs end in the
-- water, and the bathroom, with the mirror.
--
-- It stands up out of the water this near the route as the aquarium's tower does: the exception
-- EMERGE_CLEAR makes for the places you are meant to walk into. Built in the frame beside its
-- checkpoint (besideFrame): +X outward, +Z along the route, origin on the cap's edge at its top.
type Flat = { centre: Vector3 }

local function railing(parent: Instance, from: Vector3, to: Vector3, colour: Color3)
	rod(parent, "Rail", from + Vector3.new(0, 3, 0), to + Vector3.new(0, 3, 0), 0.25, colour)
	local posts = math.max(1, math.floor((to - from).Magnitude / 3))
	for index = 0, posts do
		local at = from:Lerp(to, index / posts)
		column(parent, "RailPost", 0.25, at, at.Y, at.Y + 3, colour, false, true)
	end
	local mid = (from + to) / 2 + Vector3.new(0, 1.5, 0)
	local guard = block(parent, "RailGuard", Vector3.new(0.4, 3, (to - from).Magnitude), CFrame.lookAt(mid, to + Vector3.new(0, 1.5, 0)),
		colour, Enum.Material.SmoothPlastic, true)
	guard.Transparency = 1
end

local function dryFlat(parent: Instance, frame: CFrame, floorY: number): Flat
	local landingY = frame.Position.Y
	local b0, b1 = FLAT_GANG, FLAT_GANG + FLAT_D
	local hz = FLAT_W / 2
	local h = FLAT_H
	local wallColour = Color3.fromRGB(196, 186, 170)
	local wood = Color3.fromRGB(120, 94, 70)
	local metal = Color3.fromRGB(80, 84, 90)
	local function put(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, y - landingY, z)
	end

	-- THE GANGWAY: planks from the checkpoint's edge to the doorstep, posts and a rope each side.
	block(parent, "Gangway", Vector3.new(b0 + 0.6, 0.5, 4), put(b0 / 2, landingY - 0.25, 0), wood, Enum.Material.Wood, true)
	for _, side in ipairs({ -1, 1 }) do
		for _, x in ipairs({ 0.3, b0 - 0.3 }) do
			column(parent, "GangwayPost", 0.3, put(x, landingY, side * 1.8).Position, landingY, landingY + 3, wood, false, true)
		end
		rod(parent, "GangwayRope", put(0.3, landingY + 2.8, side * 1.8).Position, put(b0 - 0.3, landingY + 2.8, side * 1.8).Position,
			0.15, Color3.fromRGB(170, 150, 110))
		local guard = block(parent, "GangwayGuard", Vector3.new(b0, 3, 0.4), put(b0 / 2, landingY + 1.5, side * 2), wood,
			Enum.Material.SmoothPlastic, true)
		guard.Transparency = 1
	end

	-- THE BUILDING UNDER THE FLAT, from the sea floor to the flat's floor, solid but for the
	-- stairwell's shaft, each piece drowned by its depth. Its top is the flat's floor.
	local shaft = { x0 = b0 + 10, x1 = b0 + 22, z0 = -hz + 0.8, z1 = -hz + 12.8 }
	local footprint = { x0 = b0, x1 = b1, z0 = -hz, z1 = hz }
	for _, r in ipairs(subtract(footprint, { shaft })) do
		for _, band in ipairs({ { floorY, waterLevel - MURK_DEPTH }, { waterLevel - MURK_DEPTH, waterLevel }, { waterLevel, landingY } }) do
			local y0, y1 = band[1], band[2]
			if y1 - y0 > 0.05 then
				block(parent, "FlatBody", Vector3.new(r.x1 - r.x0, y1 - y0, r.z1 - r.z0), put((r.x0 + r.x1) / 2, (y0 + y1) / 2, (r.z0 + r.z1) / 2),
					drowned(wallColour, (y0 + y1) / 2), Enum.Material.Concrete, true)
			end
		end
		block(parent, "FlatFloor", Vector3.new(r.x1 - r.x0, 0.1, r.z1 - r.z0), put((r.x0 + r.x1) / 2, landingY + 0.05, (r.z0 + r.z1) / 2),
			Color3.fromRGB(150, 120, 90), Enum.Material.WoodPlanks, false)
	end
	if landingY - waterLevel > 4 then
		cityBlock(parent, "FlatWindows", Vector3.new(FLAT_D + 0.4, 1.4, FLAT_W + 0.4), put((b0 + b1) / 2, (waterLevel + landingY) / 2, 0),
			GLASS, Enum.Material.Glass)
	end

	-- THE WALLS of the top floor: the doorway facing the route, a window facing out over the city.
	local wy = landingY + h / 2
	for _, side in ipairs({ -1, 1 }) do
		block(parent, "FlatWall", Vector3.new(0.8, h, hz - 2), put(b0 + 0.4, wy, side * (2 + (hz - 2) / 2)), wallColour, Enum.Material.Concrete, true)
		block(parent, "FlatWall", Vector3.new(FLAT_D, h, 0.8), put((b0 + b1) / 2, wy, side * (hz - 0.4)), wallColour, Enum.Material.Concrete, true)
	end
	block(parent, "FlatLintel", Vector3.new(0.8, h - 7, 4), put(b0 + 0.4, landingY + 7 + (h - 7) / 2, 0), wallColour, Enum.Material.Concrete, true)
	local wz0, wz1 = 0.5, 5
	block(parent, "FlatWall", Vector3.new(0.8, h, wz0 + hz), put(b1 - 0.4, wy, (-hz + wz0) / 2), wallColour, Enum.Material.Concrete, true)
	block(parent, "FlatWall", Vector3.new(0.8, h, hz - wz1), put(b1 - 0.4, wy, (wz1 + hz) / 2), wallColour, Enum.Material.Concrete, true)
	block(parent, "FlatSill", Vector3.new(0.8, 3, wz1 - wz0), put(b1 - 0.4, landingY + 1.5, (wz0 + wz1) / 2), wallColour, Enum.Material.Concrete, true)
	block(parent, "FlatLintel", Vector3.new(0.8, h - 6.5, wz1 - wz0), put(b1 - 0.4, landingY + 6.5 + (h - 6.5) / 2, (wz0 + wz1) / 2), wallColour,
		Enum.Material.Concrete, true)
	local pane = block(parent, "FlatWindow", Vector3.new(0.2, 3.5, wz1 - wz0), put(b1 - 0.4, landingY + 4.75, (wz0 + wz1) / 2), GLASS,
		Enum.Material.Glass, true)
	pane.Transparency = 0.5
	-- The roof, a parapet, and the water tank every block here carries.
	block(parent, "FlatRoof", Vector3.new(FLAT_D, 1, FLAT_W), put((b0 + b1) / 2, landingY + h + 0.5, 0), wallColour, Enum.Material.Concrete, true)
	for _, edge in ipairs({ { (b0 + b1) / 2, hz - 0.3, FLAT_D, 0.6 }, { (b0 + b1) / 2, -hz + 0.3, FLAT_D, 0.6 }, { b0 + 0.3, 0, 0.6, FLAT_W },
		{ b1 - 0.3, 0, 0.6, FLAT_W } }) do
		block(parent, "Parapet", Vector3.new(edge[3], 1.2, edge[4]), put(edge[1], landingY + h + 1.6, edge[2]), wallColour, Enum.Material.Concrete, false)
	end
	local tankAt = put(b1 - 6, landingY + h + 1, hz - 6).Position
	column(parent, "TankLegs", 2.6, tankAt, tankAt.Y, tankAt.Y + 2.5, Color3.fromRGB(90, 80, 70), false, true)
	column(parent, "WaterTank", 4.2, tankAt, tankAt.Y + 2.5, tankAt.Y + 7, Color3.fromRGB(128, 100, 80), false, true)

	-- THE LAMP still on by the door, so the doorway glows from the route.
	lamp(parent, put(b0 + 5, landingY + h - 0.4, 0), 0.55, 20, Color3.fromRGB(255, 206, 150))

	-- The living room: a sofa facing the window, a side table and a radio. The kitchen by the door.
	local sofa = put(b1 - 9, landingY, 2.2)
	block(parent, "Sofa", Vector3.new(1.8, 1, 3.6), sofa * CFrame.new(0, 0.5, 0), Color3.fromRGB(120, 96, 110), Enum.Material.Fabric, true)
	block(parent, "SofaBack", Vector3.new(0.5, 1.7, 3.6), sofa * CFrame.new(-0.9, 1.35, 0), Color3.fromRGB(120, 96, 110), Enum.Material.Fabric, true)
	block(parent, "SideTable", Vector3.new(1.4, 1.4, 1.4), put(b1 - 9, landingY + 0.7, 4.7), wood, Enum.Material.Wood, true)
	block(parent, "Radio", Vector3.new(0.9, 0.6, 0.5), put(b1 - 9, landingY + 1.7, 4.7), Color3.fromRGB(60, 52, 46), Enum.Material.SmoothPlastic, false)
	block(parent, "Counter", Vector3.new(7, 2.8, 1.6), put(b0 + 5, landingY + 1.4, -hz + 1.6), Color3.fromRGB(210, 206, 196), Enum.Material.SmoothPlastic, true)
	column(parent, "Kettle", 0.8, put(b0 + 3, landingY + 2.8, -hz + 1.6).Position, landingY + 2.8, landingY + 3.6, metal, false, true)
	block(parent, "Fridge", Vector3.new(1.6, 4.2, 1.6), put(b0 + 2, landingY + 2.1, hz - 1.6), Color3.fromRGB(226, 226, 220), Enum.Material.SmoothPlastic, true)
	local calendar = block(parent, "Calendar", Vector3.new(0.1, 2.6, 2), put(b0 + 0.85, landingY + 4.8, -6), Color3.fromRGB(236, 232, 218),
		Enum.Material.SmoothPlastic, false)
	label(calendar, Enum.NormalId.Right, "THURSDAY 16\n\nThe water will not come up this far.\nManagement", Color3.fromRGB(60, 50, 40))

	-- THE STAIRWELL: a railing round the hole, a spiral down to a landing just under the water, and at
	-- the bottom a doorway into the flooded floor, blocked by a wardrobe that fell across it.
	local sc = put((shaft.x0 + shaft.x1) / 2, landingY, (shaft.z0 + shaft.z1) / 2)
	local bottom = waterLevel - 1.5
	local drop = landingY - bottom
	local count = math.max(2, math.ceil(drop / STEP_RISE_MAX))
	local rise = drop / count
	for step = 1, count - 1 do
		local psi = math.pi + (step - 0.5) * STEP_ANGLE
		block(parent, "Step", Vector3.new(4.2, 1, 2.2), sc * CFrame.Angles(0, -psi, 0) * CFrame.new(3.5, -step * rise - 0.5, 0),
			drowned(wallColour, landingY - step * rise), Enum.Material.Concrete, true)
	end
	column(parent, "StairColumn", 2.4, sc.Position, bottom, landingY + h, wallColour, true, true)
	block(parent, "StairLanding", Vector3.new(shaft.x1 - shaft.x0, 1, shaft.z1 - shaft.z0), put((shaft.x0 + shaft.x1) / 2, bottom - 0.5,
		(shaft.z0 + shaft.z1) / 2), drowned(wallColour, bottom), Enum.Material.Concrete, true)
	cityBlock(parent, "FloodedDoor", Vector3.new(0.3, 7, 4), put(shaft.x1 - 0.1, bottom + 2, (shaft.z0 + shaft.z1) / 2 + 2), Color3.fromRGB(12, 16, 18))
	cityBlock(parent, "Wardrobe", Vector3.new(1.4, 6.5, 3.2), put(shaft.x1 - 1.4, bottom + 1.4, (shaft.z0 + shaft.z1) / 2 + 2)
		* CFrame.Angles(0, 0, math.rad(-58)), Color3.fromRGB(110, 86, 64), Enum.Material.Wood)
	local rail = Color3.fromRGB(70, 74, 78)
	local entryZ = (shaft.z0 + shaft.z1) / 2
	railing(parent, put(shaft.x1, landingY, shaft.z1).Position, put(shaft.x0, landingY, shaft.z1).Position, rail)
	railing(parent, put(shaft.x1, landingY, shaft.z0 + 0.8).Position, put(shaft.x1, landingY, shaft.z1).Position, rail)
	railing(parent, put(shaft.x0, landingY, shaft.z1).Position, put(shaft.x0, landingY, entryZ + 1.8).Position, rail)
	railing(parent, put(shaft.x0, landingY, entryZ - 1.8).Position, put(shaft.x0, landingY, shaft.z0 + 0.8).Position, rail)
	local notice = block(parent, "Notice", Vector3.new(2.4, 1.2, 0.1), put((shaft.x0 + shaft.x1) / 2, landingY + 2.4, shaft.z1 + 0.1),
		Color3.fromRGB(214, 190, 60), Enum.Material.SmoothPlastic, false)
	label(notice, Enum.NormalId.Back, "FLOODED. NO ACCESS.", Color3.fromRGB(30, 30, 30))
	-- The water, heard from the top of the stairs, and dripping on the way down.
	local lap = block(parent, "StairwellSound", Vector3.new(1, 1, 1), put((shaft.x0 + shaft.x1) / 2, bottom + 1, entryZ), wallColour,
		Enum.Material.SmoothPlastic, false)
	lap.Transparency = 1
	sound(lap, "Lapping", WATER_SOUND, 0.5, 0.25, 30, true):Play()
	task.spawn(function()
		local drip = sound(lap, "Drip", WATER_SOUND, 1, 0.3, 40, false)
		local timing = Random.new(4412)
		while drip.Parent do
			task.wait(timing:NextNumber(3, 11))
			drip.PlaybackSpeed = timing:NextNumber(0.95, 1.25)
			drip:Play()
		end
	end)

	-- THE BATHROOM, in the far corner: a partition with a doorway, the sink, the mirror over it, a
	-- bathtub full of dark water, and a cold light that does not always stay on.
	local bx0, bx1, bz0, bz1 = b1 - 8, b1 - 0.8, 5.5, hz - 0.8
	block(parent, "BathroomWall", Vector3.new(bx1 - bx0, h, 0.5), put((bx0 + bx1) / 2, wy, bz0 - 0.25), wallColour, Enum.Material.Concrete, true)
	block(parent, "BathroomWall", Vector3.new(0.5, h, 7.3 - bz0), put(bx0 - 0.25, wy, (bz0 + 7.3) / 2), wallColour, Enum.Material.Concrete, true)
	block(parent, "BathroomWall", Vector3.new(0.5, h, bz1 - 9.8), put(bx0 - 0.25, wy, (9.8 + bz1) / 2), wallColour, Enum.Material.Concrete, true)
	block(parent, "BathroomLintel", Vector3.new(0.5, h - 7, 2.5), put(bx0 - 0.25, landingY + 7 + (h - 7) / 2, 8.55), wallColour,
		Enum.Material.Concrete, true)
	local tile = Color3.fromRGB(206, 216, 214)
	block(parent, "SinkStand", Vector3.new(0.8, 2.6, 0.8), put(bx1 - 0.8, landingY + 1.3, 9), tile, Enum.Material.SmoothPlastic, true)
	block(parent, "Sink", Vector3.new(1.6, 0.5, 2), put(bx1 - 0.9, landingY + 2.85, 9), tile, Enum.Material.SmoothPlastic, true)
	local mirrorAt = put(bx1 - 0.05, landingY + 5.2, 9).Position
	local mirror = block(parent, "Mirror", Vector3.new(2.4, 3.2, 0.15), CFrame.lookAt(mirrorAt, mirrorAt - frame.RightVector),
		Color3.fromRGB(200, 206, 210), Enum.Material.SmoothPlastic, false)
	mirror.Reflectance = 0.6
	CollectionService:AddTag(mirror, "SunkenMirror")
	for _, wall in ipairs({ { bx0 + 0.3, 11, 0.4, 2.4 }, { bx0 + 4.4, 11, 0.4, 2.4 }, { bx0 + 2.35, 9.9, 4.5, 0.4 } }) do
		block(parent, "Bathtub", Vector3.new(wall[3], 1.8, wall[4]), put(wall[1], landingY + 0.9, wall[2]), Color3.fromRGB(236, 236, 230),
			Enum.Material.SmoothPlastic, true)
	end
	local tub = block(parent, "TubWater", Vector3.new(3.7, 0.2, 1.8), put(bx0 + 2.35, landingY + 1.4, 11.1), Color3.fromRGB(20, 30, 34),
		Enum.Material.Glass, false)
	tub.Transparency = 0.15
	local fixture = block(parent, "BathroomLamp", Vector3.new(1, 0.4, 1), put((bx0 + bx1) / 2, landingY + h - 0.3, 9), Color3.fromRGB(230, 236, 236),
		Enum.Material.SmoothPlastic, false)
	local cold = Instance.new("PointLight")
	cold.Brightness = 0.45
	cold.Range = 11
	cold.Color = Color3.fromRGB(200, 220, 230)
	cold.Parent = fixture
	CollectionService:AddTag(fixture, "SunkenMirrorLamp")
	-- It stutters now and then on its own, for everyone: the room was like this before anything happened in it.
	task.spawn(function()
		local timing = Random.new(1612)
		while cold.Parent do
			task.wait(timing:NextNumber(12, 30))
			for _ = 1, timing:NextInteger(2, 4) do
				cold.Enabled = false
				task.wait(0.06)
				cold.Enabled = true
				task.wait(timing:NextNumber(0.05, 0.2))
			end
		end
	end)

	-- WHERE THINGS HAPPEN: in front of the mirror, and the whole flat as a shelter from the surge.
	local zone = block(parent, "MirrorZone", Vector3.new(bx1 - bx0 - 1.5, 7, bz1 - bz0), put(bx1 - (bx1 - bx0 - 1.5) / 2, landingY + 3.5,
		(bz0 + bz1) / 2), tile, Enum.Material.SmoothPlastic, false)
	zone.Transparency = 1
	CollectionService:AddTag(zone, "SunkenMirrorZone")
	local shelter = block(parent, "Shelter", Vector3.new(FLAT_D, landingY + h - (waterLevel - 3), FLAT_W),
		put((b0 + b1) / 2, (landingY + h + waterLevel - 3) / 2, 0), tile, Enum.Material.SmoothPlastic, false)
	shelter.Transparency = 1
	CollectionService:AddTag(shelter, "SunkenShelter")

	return { centre = put((b0 + b1) / 2, landingY, 0).Position }
end

-- ===== THE PIER, THE WHIRLPOOL AND THE DRAIN =====
--
-- In the finish frame: +X away from the middle, +Z on along the route. The pier runs on from the
-- last chunk; the whirlpool is VORTEX_GAP past its end; the drain is on the harbour floor under it.
local function finale(parent: Instance, finish: CFrame, floorY: number): Vector3
	local pierTop = finish.Position.Y
	local stone = Color3.fromRGB(150, 150, 140)
	block(parent, "Pier", Vector3.new(PIER_W, 2.5, PIER_L), finish * CFrame.new(0, -1.25, PIER_L / 2), stone,
		Enum.Material.Concrete, true)
	-- The last pair well short of the end, so no pile stands in the whirlpool's rim.
	for _, z in ipairs({ 3, PIER_L / 2 - 2, PIER_L - 8 }) do
		for _, x in ipairs({ -PIER_W / 2 + 2, PIER_W / 2 - 2 }) do
			local at = finish * Vector3.new(x, 0, z)
			column(parent, "Pile", 2, at, floorY, pierTop - 2.5, stone, true)
		end
	end
	-- Bollards and a chain along each side, and a guard you cannot see along them: the pier's end is
	-- the one way off it.
	for _, x in ipairs({ -PIER_W / 2 + 0.8, PIER_W / 2 - 0.8 }) do
		local previous: Vector3? = nil
		for _, z in ipairs({ 2, PIER_L / 2, PIER_L - 0.8 }) do
			local at = finish * Vector3.new(x, 0, z)
			column(parent, "Bollard", 1.2, at, pierTop, pierTop + 2.2, Color3.fromRGB(60, 62, 66), true, true)
			if previous then
				rod(parent, "Chain", previous + Vector3.new(0, 1.8, 0), at + Vector3.new(0, 1.8, 0), 0.25, Color3.fromRGB(80, 76, 70))
			end
			previous = at
		end
		local guard = block(parent, "PierGuard", Vector3.new(0.6, 3.4, PIER_L - 1), finish * CFrame.new(x, 1.7, PIER_L / 2 + 0.5),
			stone, Enum.Material.SmoothPlastic, true)
		guard.Transparency = 1
	end
	-- THE LANTERN at the far end, the one warm light in the harbour: you see it from along the route
	-- before you see the pier, and it hangs from its own post and arm.
	local lanternPost = finish * Vector3.new(-PIER_W / 2 + 1.2, 0, PIER_L - 3)
	column(parent, "LanternPost", 0.45, lanternPost, pierTop, pierTop + 6, Color3.fromRGB(60, 62, 66), true, true)
	rod(parent, "LanternArm", lanternPost + Vector3.new(0, 5.8, 0), (finish * CFrame.new(-PIER_W / 2 + 2.6, 5.8, PIER_L - 3)).Position, 0.25,
		Color3.fromRGB(60, 62, 66))
	lamp(parent, finish * CFrame.new(-PIER_W / 2 + 2.6, 5.1, PIER_L - 3), 0.8, 24, Color3.fromRGB(255, 200, 140))
	local post = finish * Vector3.new(PIER_W / 2 - 1.2, 0, PIER_L - 3)
	column(parent, "SignPost", 0.4, post, pierTop, pierTop + 4, Color3.fromRGB(80, 84, 90), false, true)
	local sign = block(parent, "DrainSign", Vector3.new(0.2, 1.8, 3.6), finish * CFrame.new(PIER_W / 2 - 1.2, 4.6, PIER_L - 3),
		Color3.fromRGB(214, 190, 60), Enum.Material.SmoothPlastic, false)
	label(sign, Enum.NormalId.Left, "HARBOUR DRAIN. KEEP CLEAR.", Color3.fromRGB(30, 30, 30))
	label(sign, Enum.NormalId.Right, "HARBOUR DRAIN. KEEP CLEAR.", Color3.fromRGB(30, 30, 30))

	-- THE WHIRLPOOL: a foam rim, and five rings of water turning faster the further in they are,
	-- stepping down into a funnel. The client turns them (SunkenCityClient); here they only stand.
	local vortex = (finish * CFrame.new(0, 0, PIER_L + VORTEX_GAP)).Position
	vortex = Vector3.new(vortex.X, waterLevel, vortex.Z)
	for index = 0, 23 do
		local beta = index * 2 * math.pi / 24
		local rim = block(parent, "WhirlRim", Vector3.new(4.2, 0.3, 2 * math.pi * (VORTEX_R + 3) / 24 + 0.4),
			CFrame.new(vortex) * CFrame.Angles(0, -beta, 0) * CFrame.new(VORTEX_R + 1, -0.2, 0), FOAM,
			Enum.Material.SmoothPlastic, false)
		rim.Transparency = 0.1
	end
	local radii = { VORTEX_R, VORTEX_R * 0.8, VORTEX_R * 0.6, VORTEX_R * 0.4, VORTEX_R * 0.2, 1.5 }
	for ring = 0, 4 do
		local outerR, innerR = radii[ring + 1], radii[ring + 2]
		local topD, bottomD = FUNNEL_DEPTH * (ring / 5) ^ 1.6, FUNNEL_DEPTH * ((ring + 1) / 5) ^ 1.6
		local span = math.sqrt((outerR - innerR) ^ 2 + (bottomD - topD) ^ 2)
		local slope = math.atan2(bottomD - topD, outerR - innerR)
		local model = Instance.new("Model")
		model.Name = "WhirlRing"
		local tone = FOAM:Lerp(Color3.fromRGB(26, 58, 64), ring / 4)
		for index = 0, 15 do
			local beta = index * 2 * math.pi / 16 + ring * 0.12
			local piece = block(model, "Whirl", Vector3.new(span + 0.4, 0.5, 2 * math.pi * outerR / 16 + 0.4),
				CFrame.new(vortex) * CFrame.Angles(0, -beta, 0) * CFrame.new((outerR + innerR) / 2, -(topD + bottomD) / 2, 0)
					* CFrame.Angles(0, 0, slope),
				tone, Enum.Material.Glass, false)
			piece.Transparency = 0.25 - ring * 0.03
		end
		model:SetAttribute("Centre", vortex)
		-- Radians a second, the way the rider goes round.
		model:SetAttribute("Spin", 0.35 + 0.35 * ring)
		model.Parent = parent
		CollectionService:AddTag(model, "SunkenWhirlRing")
	end
	-- The current going down: a dark column from the funnel to the drain, with bubbles in it.
	local throat = column(parent, "Throat", 5, vortex, floorY, waterLevel - FUNNEL_DEPTH, Color3.fromRGB(20, 44, 50), false, true)
	if throat then
		throat.Transparency = 0.45
	end
	for index = 0, 5 do
		local beta = index * math.pi / 3
		local host = block(parent, "Spray", Vector3.new(1, 1, 1),
			CFrame.new(vortex + Vector3.new(math.cos(beta) * VORTEX_R, 0.2, math.sin(beta) * VORTEX_R)), FOAM,
			Enum.Material.SmoothPlastic, false)
		host.Transparency = 1
		local spray = Instance.new("ParticleEmitter")
		spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		spray.Color = ColorSequence.new(Color3.fromRGB(230, 244, 240))
		spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.1) })
		spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		spray.Lifetime = NumberRange.new(0.8, 1.6)
		spray.Speed = NumberRange.new(3, 7)
		spray.SpreadAngle = Vector2.new(30, 30)
		spray.Acceleration = Vector3.new(0, -20, 0)
		spray.EmissionDirection = Enum.NormalId.Top
		spray.Rate = 8
		spray.Parent = host
	end
	local rushHost = block(parent, "WhirlpoolSound", Vector3.new(1, 1, 1), CFrame.new(vortex), FOAM, Enum.Material.SmoothPlastic, false)
	rushHost.Transparency = 1
	ambience(rushHost, "WhirlpoolRush", 0.7, 0.55, 20, 140)

	-- THE DRAIN: a concrete collar on the harbour floor, bars across it, and a black shaft under it
	-- with a floor at the bottom where the rider ends up.
	local collarR = 12
	for index = 0, 15 do
		local beta = index * 2 * math.pi / 16
		cityBlock(parent, "DrainCollar", Vector3.new(collarR - DRAIN_R, 1.6, 2 * math.pi * collarR / 16 + 0.3),
			CFrame.new(vortex.X, floorY + 0.8, vortex.Z) * CFrame.Angles(0, -beta, 0) * CFrame.new((collarR + DRAIN_R) / 2, 0, 0), STONE)
		block(parent, "ShaftWall", Vector3.new(1, SHAFT_DEPTH, 2 * math.pi * (DRAIN_R + 0.5) / 16 + 0.3),
			CFrame.new(vortex.X, floorY - SHAFT_DEPTH / 2, vortex.Z) * CFrame.Angles(0, -beta, 0) * CFrame.new(DRAIN_R + 0.5, 0, 0),
			SHAFT, Enum.Material.SmoothPlastic, false)
	end
	for index = 0, 2 do
		cityBlock(parent, "Grate", Vector3.new(0.5, 0.5, DRAIN_R * 2), CFrame.new(vortex.X, floorY + 1.2, vortex.Z)
			* CFrame.Angles(0, index * math.pi / 3, 0), Color3.fromRGB(60, 58, 54), Enum.Material.Metal)
	end
	block(parent, "ShaftFloor", Vector3.new(DRAIN_R * 2 + 2, 1, DRAIN_R * 2 + 2),
		CFrame.new(vortex.X, floorY - SHAFT_DEPTH - 0.5, vortex.Z), SHAFT, Enum.Material.SmoothPlastic, true)
	return vortex
end

-- ===== WHERE IT ALL GOES =====
--
-- The heights the level is built to, from its chunks. Restated by blender/sunkencity_layout.py.
function SunkenCityService.heights(minOrigin: number)
	local water = minOrigin - WATER_UNDER_ROUTE
	return {
		water = water,
		floor = water - FLOOR_DEPTH,
		murk = water - MURK_DEPTH,
		tunnel = water - TUNNEL_BELOW,
		shaftBottom = water - FLOOR_DEPTH - SHAFT_DEPTH,
	}
end

-- ===== BUILDING IT =====
function SunkenCityService.build(level: any, parent: Instance): Model?
	if not level or not level.placedChunks or #level.placedChunks == 0 or not level.finishFrame then
		warn("SunkenCityService: the level has no chunks or no finish, so there is nothing to build round.")
		return nil
	end
	local base: Vector3 = level.centre or Vector3.zero
	local centre = Vector3.new(base.X, 0, base.Z)
	local chunks = level.placedChunks
	local minOrigin = math.huge
	for _, entry in ipairs(chunks) do
		minOrigin = math.min(minOrigin, base.Y + entry.surfaceY)
	end
	local h = SunkenCityService.heights(minOrigin)
	waterLevel = h.water
	local radius: number = level.radius or 200
	local rng = Random.new(7919 * (level.levelId or 3))

	local model = Instance.new("Model")
	model.Name = "SunkenCity"
	-- THE SEA stands apart from the city so it can be kept loaded: the plates are 2 km across and
	-- streaming judges a part by its middle, so a plate whose middle is far off would vanish and leave
	-- a hole in the sea.
	local sea = Instance.new("Model")
	sea.Name = "Sea"
	sea.Parent = model
	local cityFolder = Instance.new("Model")
	cityFolder.Name = "City"
	cityFolder.Parent = model

	-- ===== The finale first: the harbour is laid out round where it is =====
	local finish: CFrame = level.finishFrame
	local lastCap = capOf(chunks[#chunks].model)
	if lastCap then
		finish = finish + Vector3.new(0, lastCap.Position.Y + lastCap.Size.Y / 2 - finish.Position.Y, 0)
	end
	local vortex = finale(model, finish, h.floor)
	local harbourAngle = math.atan2(vortex.Z - centre.Z, vortex.X - centre.X)

	-- ===== The aquarium, off the checkpoint nearest two fifths of the way round =====
	local best: any, gap = nil, math.huge
	for index, entry in ipairs(chunks) do
		if entry.chunkId == "S1_Straight" and index > 1 and index < #chunks then
			local miss = math.abs(index - 0.4 * #chunks)
			if miss < gap then
				best, gap = entry, miss
			end
		end
	end
	local aq: Aquarium? = nil
	local aqAngle = 0
	if best then
		local cap = capOf(best.model)
		local frame = if cap then besideFrame(cap, centre) else nil
		if frame then
			aq = aquarium(model, frame, h.floor, rng)
			aqAngle = math.atan2(frame.Position.Z - centre.Z, frame.Position.X - centre.X)
		end
	end

	-- ===== The last dry flat, off the checkpoint nearest seven tenths of the way round =====
	--
	-- Never the aquarium's checkpoint, and never in the harbour, where the thing swings wide.
	local flat: Flat? = nil
	local flatAngle: number? = nil
	local flatPick: any, flatGap = nil, math.huge
	for index, entry in ipairs(chunks) do
		if entry.chunkId == "S1_Straight" and index > 1 and index < #chunks and entry ~= best then
			local miss = math.abs(index - FLAT_SHARE * #chunks)
			if miss < flatGap then
				flatPick, flatGap = entry, miss
			end
		end
	end
	if flatPick then
		local cap = capOf(flatPick.model)
		local frame = if cap then besideFrame(cap, centre) else nil
		if frame then
			local at = math.atan2(frame.Position.Z - centre.Z, frame.Position.X - centre.X)
			if math.abs(wrapAngle(at - harbourAngle)) > HARBOUR_SECTOR_HALF then
				flat = dryFlat(model, frame, h.floor)
				flatAngle = at
			end
		end
	end

	-- ===== The water: the surface with its two holes, the murk, the floor with the drain's =====
	local holes: { Hole } = { { centre = vortex, outer = VORTEX_R + 3, inner = VORTEX_R - 1 } }
	if aq then
		table.insert(holes, { centre = aq.tower, outer = ROT_R, inner = ROT_R - ROT_WALL })
	end
	sheet(sea, "Water", centre, h.water, 0.4, SURFACE, Enum.Material.Glass, 0.4, holes)
	sheet(sea, "Murk", centre, h.murk, 0.4, MURK, Enum.Material.SmoothPlastic, 0.6, {})
	sheet(sea, "SeaFloor", centre, h.floor, 4, SILT, Enum.Material.Sand, 0,
		{ { centre = vortex, outer = 12, inner = DRAIN_R } })
	clockTower(sea, centre, h.floor)

	-- ===== The city, round everything that has already claimed its space =====
	local function blocked(point: Vector3, reach: number): boolean
		if aq then
			local from, to = Vector3.new(aq.tower.X, 0, aq.tower.Z), Vector3.new(aq.far.X, 0, aq.far.Z)
			local p = Vector3.new(point.X, 0, point.Z)
			local along = math.clamp((p - from):Dot((to - from).Unit), 0, (to - from).Magnitude)
			if (p - (from + (to - from).Unit * along)).Magnitude < reach + ROOM_W / 2 + 10 then
				return true
			end
		end
		if flat and Vector3.new(point.X - flat.centre.X, 0, point.Z - flat.centre.Z).Magnitude < reach + FLAT_REACH then
			return true
		end
		return false
	end
	local carParkAngle = wrapAngle(aqAngle - 0.18 * 2 * math.pi)
	local lots = city(cityFolder, centre, radius, h.floor, harbourAngle, carParkAngle, blocked, rng)
	local gantryAngles = {}
	for _, share in ipairs({ 0.1, 0.27, 0.55, 0.68 }) do
		local at = share * 2 * math.pi
		local clearOfFlat = not flatAngle or math.abs(wrapAngle(at - (flatAngle :: number))) > 0.25
		if math.abs(wrapAngle(at - aqAngle)) > 0.25 and clearOfFlat and math.abs(wrapAngle(at - harbourAngle)) > HARBOUR_SECTOR_HALF then
			table.insert(gantryAngles, at)
		end
	end
	gantries(cityFolder, centre, radius, h.floor, gantryAngles)
	harbour(sea, centre, radius, h.floor, harbourAngle, rng)

	-- ===== The ambience, which the client lets fall away when the thing is under you =====
	-- On a part at the city's middle, full volume anywhere near the route and silent long before the
	-- lobby (see ambience).
	local host = block(model, "AmbienceHost", Vector3.new(1, 1, 1), CFrame.new(centre.X, h.water, centre.Z), FOAM,
		Enum.Material.SmoothPlastic, false)
	host.Transparency = 1
	ambience(host, "Lapping", 0.5, 0.16, radius + 300, radius + 700)
	ambience(host, "Wind", 0.3, 0.08, radius + 300, radius + 700)

	-- ===== The thing's brief, for SunkenCityClient =====
	sea:SetAttribute("MonsterCentre", centre)
	sea:SetAttribute("MonsterRadius", radius - MONSTER_INSET)
	sea:SetAttribute("MonsterSpeed", MONSTER_SPEED)
	sea:SetAttribute("MonsterDepth", MONSTER_DEPTH)
	sea:SetAttribute("MonsterBob", MONSTER_BOB)
	sea:SetAttribute("MonsterBobPeriod", MONSTER_BOB_PERIOD)
	sea:SetAttribute("MonsterGirth", MONSTER_GIRTH)
	sea:SetAttribute("HarbourAngle", harbourAngle)
	sea:SetAttribute("HarbourSwerve", HARBOUR_SWERVE)
	sea:SetAttribute("HarbourSwerveHalf", HARBOUR_SWERVE_HALF)
	sea:SetAttribute("WaterY", h.water)
	-- Where the road signs hang, which it never surfaces under (SunkenPath.surfacing).
	local quiet = {}
	for _, at in ipairs(gantryAngles) do
		table.insert(quiet, string.format("%.4f", at))
	end
	sea:SetAttribute("QuietAngles", table.concat(quiet, ","))
	sea:SetAttribute("Epoch", workspace:GetServerTimeNow())
	CollectionService:AddTag(sea, "SunkenSea")

	-- The drain's shape, for attach.
	model:SetAttribute("Vortex", vortex)
	model:SetAttribute("PierTop", finish.Position.Y)
	model:SetAttribute("ShaftBottom", h.shaftBottom)
	if aq then
		model:SetAttribute("HasAquarium", true)
	end

	pcall(function()
		sea.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	end)
	model.Parent = parent
	print(("SunkenCityService: water at %d, %d lots, %s, %s, the drain at the end, %d parts."):format(math.floor(h.water), lots,
		if aq then "the aquarium off a checkpoint" else "NO aquarium (no checkpoint to put it on)",
		if flat then "the dry flat off another" else "no dry flat", #model:GetDescendants()))
	return model
end

-- ===== THE DRAIN, RIDDEN =====
--
-- Step off the pier's end and the whirlpool takes you: round and in, down the funnel, then straight
-- down the current into the drain and the shaft under it. The rider is moved by writing the root's
-- CFrame, as on the flume and Sky Pools' slide. Nobody chooses to be pulled down a drain, so there is
-- no prompt: being inside the whirlpool, below the pier, is enough.

local riding: { [Player]: boolean } = {}
local arrivedAt: { [Player]: number } = {}

-- THE DRAIN OWNS ITS RIDER'S FALL, from the moment the whirlpool takes them until the lobby does:
-- it ends far below the kill plane. Fifteen seconds is well past the four the return waits.
function SunkenCityService.ownsFall(player: Player): boolean
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
	spray.Color = ColorSequence.new(Color3.fromRGB(226, 240, 236))
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0.2) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.6, 1.2)
	spray.Speed = NumberRange.new(12, 24)
	spray.SpreadAngle = Vector2.new(40, 40)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Acceleration = Vector3.new(0, -60, 0)
	spray.Rate = 0
	spray.Parent = host
	spray:Emit(60)
	local s = sound(host, "Splash", WATER_SOUND, 0.9, 0.9, 120, false)
	s:Play()
	Debris:AddItem(host, 3)
end

local function ride(player: Player, root: BasePart, humanoid: Humanoid, vortex: Vector3, shaftBottom: number,
	onArrive: ((Player) -> ())?)
	riding[player] = true
	arrivedAt[player] = nil
	humanoid.PlatformStand = true
	splash(Vector3.new(root.Position.X, waterLevel, root.Position.Z))
	local rush = sound(root, "DrainRush", WATER_SOUND, 0.65, 0.6, 60, true)
	rush:Play()
	local start = root.Position
	local flat = Vector3.new(start.X - vortex.X, 0, start.Z - vortex.Z)
	local r0 = math.max(2, flat.Magnitude)
	local a0 = math.atan2(flat.Z, flat.X)
	local funnelY = vortex.Y - FUNNEL_DEPTH
	local bottomY = shaftBottom + 3
	local began = os.clock()
	while root.Parent do
		local u = (os.clock() - began) / DRAIN_SECONDS
		if u >= 1 then
			break
		end
		local here: Vector3
		local facing: Vector3
		if u < 0.5 then
			-- Round and in, down the funnel.
			local s = u / 0.5
			local r = r0 + (1.5 - r0) * s
			local a = a0 + s * 2.2 * 2 * math.pi
			here = Vector3.new(vortex.X + math.cos(a) * r, start.Y + (funnelY - start.Y) * s * s, vortex.Z + math.sin(a) * r)
			facing = Vector3.new(-math.sin(a), 0, math.cos(a))
		else
			-- Straight down the current, faster and faster, still turning.
			local s = (u - 0.5) / 0.5
			local a = a0 + 2.2 * 2 * math.pi + s * 3 * 2 * math.pi
			here = Vector3.new(vortex.X + math.cos(a) * 1.2, funnelY + (bottomY - funnelY) * s * s, vortex.Z + math.sin(a) * 1.2)
			facing = Vector3.new(math.cos(a), 0, math.sin(a))
		end
		root.CFrame = CFrame.lookAt(here, here + facing)
		task.wait()
	end
	if root.Parent then
		root.CFrame = CFrame.new(vortex.X, bottomY, vortex.Z)
	end
	rush:Destroy()
	humanoid.PlatformStand = false
	riding[player] = nil
	arrivedAt[player] = os.clock()
	if onArrive then
		onArrive(player)
	end
end

-- ===== THE GLASS =====
--
-- Tap on the gallery's window and it thuds. Tap three times in a few seconds and, for a Hardcore
-- player, once a run, something outside taps back: a heavy thud, the glass shivers, the lamp stutters.
-- In Chill nothing answers (ROADMAP section 6: no scares in Chill).
local function glass(model: Model): RBXScriptConnection?
	local window = model:FindFirstChild("ViewingWindow", true)
	if not (window and window:IsA("BasePart")) then
		return nil
	end
	local pane: BasePart = window
	-- The gallery's own lamp: the light above the window and within a room's width of it.
	local roomLight: PointLight? = nil
	for _, item in ipairs(model:GetDescendants()) do
		local holder = item.Parent
		if item:IsA("PointLight") and holder and holder:IsA("BasePart") and holder.Position.Y > pane.Position.Y
			and (holder.Position - pane.Position).Magnitude < 16 then
			roomLight = item
		end
	end
	local detector = Instance.new("ClickDetector")
	detector.MaxActivationDistance = 12
	detector.Parent = pane
	local taps: { [Player]: { number } } = {}
	local answered: { [Player]: boolean } = {}
	return detector.MouseClick:Connect(function(player: Player)
		local knock = sound(pane, "Tap", THUD_SOUND, 1.4, 0.5, 30, false)
		knock:Play()
		Debris:AddItem(knock, 2)
		local list = taps[player] or {}
		table.insert(list, os.clock())
		while #list > 0 and os.clock() - list[1] > 5 do
			table.remove(list, 1)
		end
		taps[player] = list
		local state = PlayerStateService.getState(player)
		if #list >= 3 and not answered[player] and state and state.mode == "hardcore" then
			answered[player] = true
			task.delay(1.8, function()
				if not pane.Parent then
					return
				end
				local thud = sound(pane, "Answer", THUD_SOUND, 0.45, 1.4, 60, false)
				thud:Play()
				Debris:AddItem(thud, 4)
				local rest = pane.CFrame
				local light = roomLight
				for _ = 1, 6 do
					pane.CFrame = rest * CFrame.new(0, 0, (math.random() - 0.5) * 0.3)
					if light then
						light.Enabled = not light.Enabled
					end
					task.wait(0.07)
				end
				pane.CFrame = rest
				if light then
					light.Enabled = true
				end
			end)
		end
	end)
end

-- ===== THE SURGE AND THE MIRROR =====

local function inAny(boxes: { BasePart }, point: Vector3): boolean
	for _, box in ipairs(boxes) do
		if box.Parent then
			local p = box.CFrame:PointToObjectSpace(point)
			local half = box.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

local function tagged(model: Instance, tag: string): { BasePart }
	local out = {}
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") and CollectionService:HasTag(item, tag) then
			table.insert(out, item)
		end
	end
	return out
end

local function isHardcore(player: Player): boolean
	local state = PlayerStateService.getState(player)
	return state ~= nil and state.mode == "hardcore"
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- ONCE A SERVER, EVER: the face in the mirror is rare by design (ROADMAP section 6), and a scare
-- that happens every time stops being one.
local mirrorShown = false

-- Hooks the drain, the surge, the mirror and the glass to a built city. `onArrive` finishes the
-- rider's run; `onTaken` sends a Hardcore player back to the start (Bootstrap's sendBackToStart,
-- the same reset a Hardcore fall gets). Returns the undo, which Bootstrap calls before the next run.
type PlayerCallback = (Player) -> ()

function SunkenCityService.attach(model: Model, onArrive: PlayerCallback?, onTaken: PlayerCallback?): () -> ()
	local vortexValue = model:GetAttribute("Vortex")
	local pierTop = model:GetAttribute("PierTop")
	local shaftBottom = model:GetAttribute("ShaftBottom")
	if typeof(vortexValue) ~= "Vector3" or typeof(pierTop) ~= "number" or typeof(shaftBottom) ~= "number" then
		return function() end
	end
	local vortex: Vector3 = vortexValue
	local sea = model:FindFirstChild("Sea")
	local path = if sea then SunkenPath.read(sea) else nil
	local shelters = tagged(model, "SunkenShelter")
	local mirrorZones = tagged(model, "SunkenMirrorZone")
	local washed = -1
	local lingering: { [Player]: number } = {}
	local rolled: { [Player]: boolean } = {}
	local nextMirrorCheck = 0
	local connections: { RBXScriptConnection } = {}
	table.insert(connections, RunService.Heartbeat:Connect(function()
		-- THE DRAIN: step off the pier into the whirlpool and it takes you.
		for _, player in ipairs(Players:GetPlayers()) do
			if not riding[player] and not arrivedAt[player] then
				local root = rootOf(player)
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if root and humanoid then
					local p = root.Position
					local flat = Vector3.new(p.X - vortex.X, 0, p.Z - vortex.Z).Magnitude
					if flat < CAPTURE_R and p.Y < (pierTop :: number) - 2 and p.Y > vortex.Y - 30 then
						task.spawn(ride, player, root, humanoid, vortex, shaftBottom :: number, onArrive)
					end
				end
			end
		end

		-- THE SURGE: once per surfacing, at the moment the spray goes over the route, every Hardcore
		-- player within reach of the spot, above the water and not indoors, is taken back to the start.
		-- The clients showed it coming for five seconds from the same schedule (SunkenPath).
		if path then
			local into, spot, index = SunkenPath.surfacing(path, workspace:GetServerTimeNow() - path.epoch)
			if into and spot and index and into >= SunkenPath.WASH_AT and index ~= washed then
				washed = index
				for _, player in ipairs(Players:GetPlayers()) do
					local root = rootOf(player)
					if root and not riding[player] and not arrivedAt[player] and isHardcore(player) then
						local p = root.Position
						local near = Vector3.new(p.X - spot.X, 0, p.Z - spot.Z).Magnitude
						if near < SunkenPath.WASH_RADIUS and p.Y > spot.Y and p.Y < spot.Y + 30 and not inAny(shelters, p)
							and onTaken then
							onTaken(player)
						end
					end
				end
			end
		end

		-- THE MIRROR: a Hardcore player standing before it for a moment gets one roll a run, while it
		-- has never happened on this server. The client does the rest (SunkenCityClient).
		local now = os.clock()
		if not mirrorShown and #mirrorZones > 0 and now >= nextMirrorCheck then
			nextMirrorCheck = now + 0.25
			for _, player in ipairs(Players:GetPlayers()) do
				local root = rootOf(player)
				if root and isHardcore(player) and inAny(mirrorZones, root.Position) then
					local since = lingering[player] or now
					lingering[player] = since
					if now - since >= MIRROR_LINGER and not rolled[player] then
						rolled[player] = true
						if math.random() < MIRROR_CHANCE then
							mirrorShown = true
							player:SetAttribute("MirrorFace", os.clock())
						end
					end
				else
					lingering[player] = nil
				end
			end
		end
	end))
	local tapping = glass(model)
	if tapping then
		table.insert(connections, tapping)
	end
	return function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(arrivedAt)
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	riding[player] = nil
	arrivedAt[player] = nil
end)

return SunkenCityService
