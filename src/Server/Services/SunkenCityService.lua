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
--
-- LOOKED FOR WITH A TIMEOUT. A bare WaitForChild here yields forever when SunkenPath has not been
-- pasted in, and Bootstrap requires this module at startup -- so one missing file would stop the
-- whole server before the lobby was built. Without it the city still builds and the drain still
-- works; only the surfacing is off, and this says so.
local pathModule = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("SunkenPath", 10)
local SunkenPath: any = if pathModule and pathModule:IsA("ModuleScript") then require(pathModule) else nil
if not SunkenPath then
	warn("SunkenCityService: no ReplicatedStorage.Shared.SunkenPath, so the thing will not surface. Paste "
		.. "src/Shared/SunkenPath.lua in as a ModuleScript named exactly SunkenPath.")
end
-- The meshes (the Ferris wheel's, here), looked for the same way: without SeaRig the wheel is
-- built from parts in the same place.
local rigModule = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("SeaRig", 10)
local SeaRig: any = if rigModule and rigModule:IsA("ModuleScript") then require(rigModule) else nil
-- And the people still here (Townsfolk): without the module the level simply has nobody in it.
local npcModule = script.Parent:FindFirstChild("Townsfolk") or script.Parent:WaitForChild("Townsfolk", 5)
local Townsfolk: any = if npcModule and npcModule:IsA("ModuleScript") then require(npcModule) else nil
-- And the poses (Poses): a rider whose own client is not running is flailed by them from here.
local Poses: any = (function()
	local found = game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Poses", 10)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SunkenCityService = {}

-- ===== The water =====
local WATER_UNDER_ROUTE = 9 -- the surface, this far under the lowest chunk's origin
local FLOOR_DEPTH = 100 -- the sea floor, this far under the surface
-- HOW DEEP THE DETAIL GOES. There used to be a flat dark sheet at this depth and it read as a lid:
-- from the route the city under you was one black plane. It is gone; this is now only the depth
-- past which a window band is not worth building, because nothing can make it out from up there.
local MURK_DEPTH = 35
-- ===== What lives in it =====
-- A SHOAL of fish this often along the street, in the open water under the route: within SHOAL_OUT
-- of the centre line. They were ninety studs off it, which is inside the drowned blocks, so every
-- fish in the city was swimming inside a wall and nobody had ever seen one.
local SHOAL_EVERY = 45
local SHOAL_OUT = 19 -- the far side of a shoal's lane; its near side is 15, clear of the chunks overhead
local HORRORS = 4 -- and, far out where the haze takes over, four things that are not fish
local HORROR_OUT = 780
-- THE SWIMMERS: single animals with somewhere to be, rather than a shoal going round in a ring. A ray,
-- a turtle, a jellyfish, an eel, a big old grouper -- one every so often along the street, each with a
-- home it wanders round. The client makes and moves them; this only says where and what.
local SWIMMER_EVERY = 30
local SWIMMER_KINDS = { "ray", "turtle", "dolphins", "jelly", "shark", "grouper", "turtle", "dolphins", "ray", "jelly",
	"eel", "turtle" }
-- THEY SWIM BESIDE THE ROUTE, NOT UNDER IT. In play nobody saw one: they wandered up to SWIM_REACH
-- either side of the centre line, so half the time they were under the chunks, and the chunks are
-- what you are looking at. Now each has a lane on one side, its home SWIM_LANE from the centre line,
-- and wanders across no further than keeps it past the route's edge on one side and inside
-- SWIM_REACH on the other -- which is inside the road signs' legs and far inside the lamp posts.
local SWIM_LANE = { 15, 19 }
-- GULLS over the street: one every GULL.every studs, circling a point within GULL.out of the centre
-- line at up to GULL.radius, never lower than GULL.low over the water.
local GULL = { every = 70, out = 16, radius = 28, low = 32 }
local SWIM_REACH = 24
-- THE THING ON THE HORIZON. Far out past the city, on a schedule every client shares, something so
-- large that its back comes up out of the sea like a range of low hills, lies there, and goes down
-- again. It never comes near. It does not need to.
-- Measured across from the street's first point the way the blocks are laid, so it is always past
-- the city's edge whatever the street does. On its side the lone towers stop at FAR_OPEN past the
-- edge, which leaves it open sea to come up in (check_sunkencity.py holds the gap).
local LEVIATHAN_OUT = 1300
local LEVIATHAN_LONG = 760
local SCHEDULE = { leviathanFirst = 95, leviathanEvery = 260, rainFirst = 70, rainEvery = 230, rainLength = 75 }
-- THE WEATHER. A shower every few minutes, the same showers for everyone.
-- (its times are in SCHEDULE, above, with the thing's)
-- AND THE WINDOWS. A handful, near the street, with a light in them that goes on and off. Somebody is
-- still in there, or something is.
local LIT_WINDOWS = 7
local SEA_HALF = 3072 -- how far the water reaches from the middle, each way
local LONGEST = 2000 -- a part stops at 2048 studs; anything longer is built in pieces

-- ===== The city, laid along the route rather than round it =====
--
-- THE ROUTE IS THE BOULEVARD. The level used to be a ring with the city outside it, so the whole
-- run was spent looking at the place from its edge. The route is a line through the middle of it
-- now: blocks either side, their frontages on the street, the street running ahead into the haze.
-- The blocks are a grid laid in the route's own direction, and any lot the street would run through
-- is pushed back and shortened until its frontage is on the kerb -- which is how a real street
-- makes a wall of buildings rather than a corridor of gaps.
local PLAZA_RADIUS = 60
local BOULEVARD_HALF = 56 -- the open water either side of the route's centre line
local BLOCK = 118 -- a city block, each way
local STREET = 26 -- between one block and the next
local CITY_SIDE = 940 -- how far the blocks reach either side of the route
local CITY_BEYOND = 460 -- and past each end of it
local LOT_MIN = 30 -- a lot shorter than this after the street has taken its bite is not built
-- THE ROUTE'S REACH, the widest any chunk in this level's pool extends from its centre line (the
-- straight chunk's shelves). check_sunkencity.py holds it against the pool.
local ROUTE_REACH = 13.4
-- ANYTHING THAT BREAKS THE SURFACE stays this far beyond the route's reach, in plan.
local EMERGE_CLEAR = 40
local FAR_TOWERS = 16 -- lone towers out past the last block, for the skyline in the haze
local FAR_OPEN = 160 -- and on the side the thing on the horizon comes up, they stop this far past the edge

-- ===== The thing (drawn and moved by SunkenCityClient; these numbers are its whole brief) =====
local MONSTER_SPEED = 12 -- studs a second, up the street and back down it
local MONSTER_DEPTH = 29 -- its centre line, this far under the surface on average: fins clear of the road signs
local MONSTER_BOB = 5 -- and up and down by this much
local MONSTER_BOB_PERIOD = 47
local MONSTER_GIRTH = 8 -- its widest radius; the client draws nothing thicker
-- IT PATROLS THE BOULEVARD, up the route and back down it, and turns back this far short of the
-- far end, because the far end is the harbour and the drain.
local MONSTER_KEEP = 200
-- HOW FAR OFF THE LINE IT WANDERS, and it is small on purpose. On the ring it swam a few studs
-- inside the route with the whole city outside; on a street the aquarium's tower and the dry flat
-- stand right beside the water it is in, so the room it has is the gap between them.
-- blender/check_sunkencity.py holds its whole body inside that gap.
local MONSTER_SWING = 5
local MONSTER_SWING_WAVE = 340
-- The harbour: the open water at the end of the route, which has no city blocks in it. REACH is how
-- far it spreads either side of the route, ALONG is how much of the route's end belongs to it --
-- and they are separate numbers because a short run's whole street is shorter than the harbour is
-- wide, and measuring one with the other left a short run with nowhere to put the dry flat.
local HARBOUR_REACH = 520
-- A QUARTER OF THE STREET AT MOST. A short run's whole street is only about five hundred studs, and
-- a fixed two hundred of harbour at the end of that leaves nowhere to put the dry flat.
local HARBOUR_ALONG = 200
local HARBOUR_ALONG_SHARE = 0.25

-- ===== The aquarium =====
-- THE LANDING from the checkpoint's cap edge to the tower's inner wall. Longer than it was: the
-- thing patrols the street now rather than a ring inside it, and the tower has to stand back far
-- enough that it never touches the thing's body.
local AQ_NECK = 14
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
-- THE STAIR IS LAID FROM BOTH ENDS. Its head leaves the top landing just past the door (STAIR.top,
-- the door facing pi) and its foot comes down at STAIR.foot, fifty degrees short of the tunnel's
-- mouth (which faces 0) -- so you step off the last step and walk forward into the tunnel under the
-- turn above. It used to be laid from the head only, at a fixed eighteen degrees a step, and its
-- last turn ran straight across the tunnel's mouth four studs off the floor: the entrance to the
-- aquarium was a stair. stairPlan finds the step count and angle that join the two ends.
local STAIR = {
	top = math.pi + 0.6, -- where the first step leaves the top landing
	foot = math.rad(-50), -- where the last one comes down
	riseMin = 0.6, -- the shallowest rise, which keeps the turn above off your head
	riseBest = 0.85,
	angleMin = math.rad(14),
	angleMax = math.rad(20),
}
-- The aquarium's tank: everything in it keeps within TANK_HALF of the tunnel's line, which is where
-- the city is kept out (the city's `blocked`), and the open water past the gallery's window runs
-- WINDOW_DEEP further, for what comes up out of the dark to look in.
local TANK_HALF = 20
local WINDOW_DEEP = 60
local KELP_TUNNEL = 13 -- a strand in the tank stands at least this far off the tunnel's line
-- THE GLASS, tapped: it cracks at TAP.crack, cracks further at TAP.crack2 and goes at TAP.breaks.
-- Every tap adds one; one drains away every TAP.ease seconds, so it takes a player meaning it.
-- Then the aquarium floods with water you can swim in: the sea pours in and the gallery is full
-- after TAP.rise, slow enough to watch; it stays until TAP.hold, then goes down over TAP.drain, and
-- the glass is back. Nobody is washed out: the flood is somewhere to be.
local TAP = {
	crack = 3, -- taps of strain on one pane before it cracks
	crack2 = 5, -- before the crack spreads and weeps
	breaks = 7, -- before it goes
	ease = 4, -- seconds for one tap's strain to drain away
	rise = 8, -- seconds for the gallery to fill
	hold = 40, -- seconds from the glass going to the water starting to go down
	drain = 6, -- seconds for it to go down, before the glass is whole
}
-- KELP, as markers the client grows and sways (SunkenCityClient): in the tank, and in beds along the
-- street's kerbs, KELP_KERB off the centre line, halfway between one lamp post and the next.
local KELP_KERB = 49
-- THE STREET'S THINGS: the widest a vehicle's lane goes from the centre line (inside the road signs'
-- legs, clear of the kerb's kelp), and the pavement edge the furniture stands on.
local ROADSIDE = { vehicleLane = 30, furnitureAt = 52 }

-- ===== The last dry flat =====
local FLAT_SHARE = 0.7 -- off the checkpoint nearest this share of the way round
local FLAT_GANG = 10 -- the gangway, from the checkpoint's cap edge to the doorstep; see AQ_NECK
local FLAT_D, FLAT_W, FLAT_H = 24, 26, 9 -- outward, along the route, and the top floor's height
local FLAT_REACH = 26 -- the lots keep this far from its middle
local FLOODED_DEPTH = 13 -- the flooded floor under the flat, this far under the surface
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
local DRAIN_SECONDS = 13

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
-- How many windows in this build still have a light in them; see LIT_WINDOWS.
local litLeft = 0

-- ===== WHY THE TANK IS NOT TERRAIN WATER =====
--
-- The obvious way to make the aquarium's water look like water is to fill the tank with Roblox
-- terrain water, which refracts and caustics on its own. It cannot be done here, and the reason is
-- worth writing down: terrain water does not know about parts. Filling the tank would fill the
-- TUNNEL as well -- the glass tube is inside the tank, that is what a tunnel aquarium is -- and the
-- player would swim down a corridor they are supposed to walk through. Leaving a dry channel wide
-- enough to be safe from the four-stud voxel grid would leave a visible gap of clear nothing
-- between the glass and the water, which is worse than the problem.
--
-- So the tank is built the way the rest of this level is: layers of tinted glass at increasing
-- distance, so the view out has depth to it; caustics the client moves across the tunnel; specks
-- hanging in the light; and fish. What follows from that is that anything else in this level which
-- wants real water has the same answer.

-- ===== Parts =====-- ===== Parts =====

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
-- AN ELLIPSOID, which a Ball part cannot be: Roblox forces a ball's three sizes equal. A block with
-- a sphere mesh takes the block's size on all three axes, which is what a clump of weed or a tree's
-- canopy needs. Sky Pools' clouds are built the same way and for the same reason.
local function ellipsoid(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3): Part
	local part = block(parent, name, size, cf, colour, Enum.Material.Grass, false)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

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
	-- And ambience of the game's kind: faded out when the ending's scene starts (Cinema).
	CollectionService:AddTag(s, "Ambience")
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
				-- THE WATER HAS TO MOVE. A flat sheet of glass is the right colour and the wrong
				-- thing: what the eye actually reads as liquid is a pattern of light sliding across
				-- it, which is what the lobby's pool does with the engine's own water texture. Two of
				-- them at different scales, which the client slides in different directions, so
				-- they interfere the way real ripples do instead of scrolling like wallpaper.
				if name == "Water" then
					for index, scale in ipairs({ 14, 37 }) do
						local ripple = Instance.new("Texture")
						ripple.Name = "Ripple" .. index
						ripple.Face = Enum.NormalId.Top
						ripple.Texture = "rbxasset://textures/water/normal_1.dds"
						ripple.StudsPerTileU = scale
						ripple.StudsPerTileV = scale
						ripple.Transparency = if index == 1 then 0.72 else 0.82
						ripple.Color3 = Color3.fromRGB(214, 236, 232)
						ripple.Parent = plate
					end
					CollectionService:AddTag(plate, "SunkenSurface")
				end
			end
		end
	end
end

-- ===== THE ROUTE, AS A LINE ON THE PLAN =====
--
-- Everything in this level is placed from the route: the blocks are laid either side of it, the
-- signs hang over it, the thing patrols it and the harbour is at the end of it. So it is read once,
-- here, as a polyline through the chunks with the finish on the end, and every question the build
-- asks -- how far along, how far off, which way does it run here -- is answered from that.
export type Route = {
	points: { Vector3 },
	steps: { number },
	total: number,
	forward: Vector3,
	side: Vector3,
	middle: Vector3,
}

local function routeOf(chunks: { any }, finish: CFrame, y: number): Route
	local points: { Vector3 } = {}
	for _, entry in ipairs(chunks) do
		local at = entry.model:GetPivot().Position
		table.insert(points, Vector3.new(at.X, y, at.Z))
	end
	table.insert(points, Vector3.new(finish.Position.X, y, finish.Position.Z))
	local steps = { 0 }
	for index = 2, #points do
		steps[index] = steps[index - 1] + (points[index] - points[index - 1]).Magnitude
	end
	local run = points[#points] - points[1]
	local forward = if run.Magnitude > 1 then Vector3.new(run.X, 0, run.Z).Unit else Vector3.new(0, 0, 1)
	local sum = Vector3.zero
	for _, at in ipairs(points) do
		sum += at
	end
	return {
		points = points,
		steps = steps,
		total = steps[#steps],
		forward = forward,
		side = Vector3.yAxis:Cross(forward),
		middle = sum / #points,
	}
end

-- The point `s` studs along the route, and the way it runs there.
local function alongRoute(route: Route, s: number): (Vector3, Vector3)
	local at = math.clamp(s, 0, route.total)
	local low, high = 1, #route.steps
	while high - low > 1 do
		local mid = (low + high) // 2
		if route.steps[mid] <= at then
			low = mid
		else
			high = mid
		end
	end
	local span = route.steps[high] - route.steps[low]
	local within = if span > 0 then (at - route.steps[low]) / span else 0
	local from, to = route.points[low], route.points[high]
	local run = to - from
	local dir = if run.Magnitude > 0.001 then run.Unit else route.forward
	return from + run * within, dir
end

-- How far a point is from the route in plan, and which way is away from it. Walked segment by
-- segment: the route bends, and the distance to a bent line is not the distance to its ends.
local function nearRoute(route: Route, point: Vector3): (number, Vector3)
	local best, away = math.huge, route.side
	local p = Vector3.new(point.X, 0, point.Z)
	for index = 1, #route.points - 1 do
		local from = Vector3.new(route.points[index].X, 0, route.points[index].Z)
		local to = Vector3.new(route.points[index + 1].X, 0, route.points[index + 1].Z)
		local run = to - from
		local length = run.Magnitude
		if length > 0.001 then
			local along = math.clamp((p - from):Dot(run / length), 0, length)
			local foot = from + (run / length) * along
			local gap = (p - foot).Magnitude
			if gap < best then
				best = gap
				away = if gap > 0.01 then (p - foot).Unit else route.side
			end
		end
	end
	return best, away
end

-- How far along the route a point is, which is what the road signs and the harbour are measured in.
local function alongOf(route: Route, point: Vector3): number
	local best, at = math.huge, 0
	local p = Vector3.new(point.X, 0, point.Z)
	for index = 1, #route.points - 1 do
		local from = Vector3.new(route.points[index].X, 0, route.points[index].Z)
		local to = Vector3.new(route.points[index + 1].X, 0, route.points[index + 1].Z)
		local run = to - from
		local length = run.Magnitude
		if length > 0.001 then
			local along = math.clamp((p - from):Dot(run / length), 0, length)
			local gap = (p - (from + (run / length) * along)).Magnitude
			if gap < best then
				best, at = gap, route.steps[index] + along
			end
		end
	end
	return at
end

-- ===== BUILDINGS =====
--
-- Each is built in its lot's frame: origin on the sea floor at the lot's middle, +X outward from
-- the city's centre, +Z round the ring. `w` runs along Z (the frontage), `d` along X (the depth).

-- ===== A LANTERN =====
--
-- A street lantern as a street lantern is made: a glass box between four corner posts, a tray under
-- it, a stepped cap over it with a finial on top, hung from its arm by a short rod. The glass is lit
-- from inside by a real light when `lit` says so -- and a lantern that is lit is tagged, so the
-- client can make it gutter now and then, the way a light still running on something is not quite
-- steady. Built centred on `at`.
local function lantern(parent: Instance, at: CFrame, lit: boolean, warm: Color3)
	local iron = Color3.fromRGB(46, 50, 52)
	local glass = block(parent, "LanternGlass", Vector3.new(1.5, 2, 1.5), at, warm, Enum.Material.Glass, false)
	glass.Transparency = if lit then 0.2 else 0.45
	for _, corner in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		block(parent, "LanternFrame", Vector3.new(0.18, 2.2, 0.18), at * CFrame.new(corner[1] * 0.78, 0, corner[2] * 0.78),
			iron, Enum.Material.Metal, false)
	end
	block(parent, "LanternTray", Vector3.new(1.9, 0.25, 1.9), at * CFrame.new(0, -1.15, 0), iron, Enum.Material.Metal, false)
	block(parent, "LanternCap", Vector3.new(2.1, 0.35, 2.1), at * CFrame.new(0, 1.2, 0), iron, Enum.Material.Metal, false)
	block(parent, "LanternCap", Vector3.new(1.3, 0.35, 1.3), at * CFrame.new(0, 1.5, 0), iron, Enum.Material.Metal, false)
	block(parent, "LanternCap", Vector3.new(0.6, 0.35, 0.6), at * CFrame.new(0, 1.8, 0), iron, Enum.Material.Metal, false)
	ellipsoid(parent, "LanternFinial", Vector3.new(0.4, 0.5, 0.4), at * CFrame.new(0, 2.15, 0), iron)
	if lit then
		local glow = Instance.new("PointLight")
		glow.Brightness = 1
		glow.Range = 24
		glow.Color = warm
		glow.Shadows = false
		glow.Parent = glass
		CollectionService:AddTag(glass, "SunkenLantern")
	end
	return glass
end

-- ===== A SHIPPING CONTAINER =====
--
-- Corrugated sides, a door end with its locking bars, and a casting at each top corner. `size` is
-- length, height, width. The plain version -- ribs only -- is for the ones in a warehouse yard, which
-- are seen from further off and there are more of.
local function container(parent: Instance, cf: CFrame, size: Vector3, colour: Color3, rich: boolean)
	-- Plain Metal: Roblox has no corrugated material, and the ribs below are what make it read as one.
	local body = cityBlock(parent, "Container", size, cf, colour, Enum.Material.Metal)
	local dark = colour:Lerp(Color3.new(0, 0, 0), 0.25)
	local ribs = if rich then 6 else 3
	for index = 1, ribs do
		local x = -size.X / 2 + index * size.X / (ribs + 1)
		for _, side in ipairs({ -1, 1 }) do
			cityBlock(parent, "ContainerRib", Vector3.new(0.35, size.Y - 0.4, 0.25),
				cf * CFrame.new(x, 0, side * (size.Z / 2 + 0.1)), dark, Enum.Material.Metal)
		end
	end
	if rich then
		-- The door end: two leaves, and the locking bars running up them.
		cityBlock(parent, "ContainerDoor", Vector3.new(0.3, size.Y - 0.5, size.Z - 0.5),
			cf * CFrame.new(size.X / 2 + 0.1, 0, 0), dark, Enum.Material.Metal)
		for _, z in ipairs({ -size.Z * 0.3, -size.Z * 0.1, size.Z * 0.1, size.Z * 0.3 }) do
			cityBlock(parent, "LockBar", Vector3.new(0.25, size.Y - 0.6, 0.18),
				cf * CFrame.new(size.X / 2 + 0.3, 0, z), Color3.fromRGB(140, 136, 128), Enum.Material.Metal)
		end
		for _, x in ipairs({ -1, 1 }) do
			for _, z in ipairs({ -1, 1 }) do
				cityBlock(parent, "Casting", Vector3.new(0.7, 0.6, 0.7),
					cf * CFrame.new(x * (size.X / 2 - 0.25), size.Y / 2 - 0.2, z * (size.Z / 2 - 0.25)),
					Color3.fromRGB(70, 70, 68), Enum.Material.Metal)
			end
		end
	end
	return body
end

-- ===== WHAT A BUILDING IS MADE OF =====
--
-- The city was read back as "ugly platforms in the sky", and the criticism was exact: a box with a
-- band of window colour round it is a massing study, not a building. What makes a building read is
-- not more boxes, it is the four things below, and every kind of building here now gets all four.
--
--   A FACADE. Storeys, not one flat face: a sill line at every floor, pilasters standing the full
--   height between them, a cornice on top, and window panes set INTO the wall rather than painted
--   on the outside of it. Some panes are dark, some are broken, some are boarded.
--   WEAR. Nothing here has been maintained since the water came: rust running from every fixing,
--   render fallen off in patches, cracks, a corner gone, rubble at the foot of it.
--   GROWTH. The waterline is where the sea starts: weed and algae in a band along it, ivy up the
--   face that gets light, a tree that has taken a roof.
--   HOLDING OUT. And the other half of the story, which is the half that makes it a CITY rather
--   than a ruin: sandbags along a frontage, boards over the low windows, a pump with its hose over
--   the parapet, scaffolding on a wall somebody was shoring up, a floodlight still burning, a gauge
--   painted on the wall with the dates the water reached. Somebody was fighting this.
--
-- Each of these is a function taking the building's own frame and size, so a new kind of building
-- gets the whole language for four calls.

-- How weathered a surface is, from 0 (new) to 1 (nothing left of it): everything near the waterline
-- and everything old is greener and greyer.
local function weathered(colour: Color3, y: number, rng: Random): Color3
	local wet = math.clamp(1 - math.abs(y - waterLevel) / 26, 0, 1)
	return colour:Lerp(Color3.fromRGB(96, 110, 92), wet * 0.35 + rng:NextNumber(0, 0.12))
end

-- HOW MUCH OF THIS A BUILDING GETS, by how near the street it is. A facade is worth about thirty
-- parts and a city is three hundred buildings, so detail is spent where it is read: full on the
-- frontages you run past, sills and ribs in the middle distance, and nothing at all out in the haze
-- where a silhouette is the whole of what you can see anyway. `detail` is 2, 1 or 0.
local DETAIL_NEAR, DETAIL_MID = 300, 620
-- The most storeys a near facade is drawn with, top to bottom; the dial if the parts are too many.
local FACADE_FLOORS = 14
-- And nothing is drawn far under the water, where the depth has taken it: this is how far down the
-- eye still reaches from the route.
local SEEN_DEEP = 26
-- NO ROOF WITHIN SURFACE_CLEAR OF THE WATER, above or below. Two flat faces at nearly the same
-- height fight over which one the screen draws, and a roof a stud under the surface flickers green
-- and blue as the camera moves -- the "green roofs" that looked glitchy. A building stands clear of
-- the water or is plainly under it.
local SURFACE_CLEAR = 2.5

-- A FACADE between two heights: sills, pilasters, a cornice, and windows set into the wall.
--
-- `from` AND `to` ARE HEIGHTS ABOVE THE BUILDING'S OWN FLOOR, like every other height inside a
-- building's frame. They used to be world heights, and the tower passed a height above its floor
-- instead -- with the sea floor a hundred studs down, every tower's sills and pilasters ran about
-- ninety studs over its own roof. That is what the empty frames standing in the sky were: a facade
-- with no building in it. Relative is the convention everything else in a frame already uses, so it
-- is the one that cannot be got wrong by writing the obvious number.
local function facadeOf(parent: Instance, frame: CFrame, w: number, d: number, from: number, to: number,
	colour: Color3, rng: Random, storey: number, detail: number)
	local floorY = frame.Position.Y
	if detail <= 0 then
		return
	end
	-- ALL THE WAY DOWN on the frontages near the street, which is where you see them from under the
	-- water (falling, swimming, from the aquarium); only the part the eye reaches from above further
	-- out. Deep storeys get one window band a side rather than panes: the eye reads the band and the
	-- ribs as windows at that depth, and it costs a third of the parts.
	local start = if detail >= 2 then from else math.max(from, waterLevel - SEEN_DEEP - floorY)
	if to - start < 4 then
		return
	end
	local floors = math.clamp(math.floor((to - start) / storey), 1, if detail >= 2 then FACADE_FLOORS else 4)
	local each = (to - start) / floors
	local dark = Color3.fromRGB(28, 36, 40)
	local boarded = Color3.fromRGB(122, 96, 68)
	for index = 0, floors - 1 do
		local y = start + (index + 0.5) * each
		local sillY = start + index * each
		if math.abs(sillY + floorY - waterLevel) < 0.8 then
			sillY -= 1.2 -- never a sill lying in the surface (SURFACE_CLEAR)
		end
		-- The sill line at every floor: a thin course standing a little proud, which is the shadow
		-- that tells you how many storeys there are from a hundred studs away.
		cityBlock(parent, "Sill", Vector3.new(d + 0.7, 0.5, w + 0.7), frame * CFrame.new(0, sillY, 0),
			weathered(colour, sillY + floorY, rng))
		-- WINDOWS, set into the wall, on the two long faces only -- the ones a street sees. Some are
		-- dark, some are boarded, and the rest have glass still in them.
		if detail >= 2 and y + floorY < waterLevel - SEEN_DEEP then
			for _, side in ipairs({ -1, 1 }) do
				cityBlock(parent, "WindowBand", Vector3.new(0.5, each * 0.45, w - 2.4),
					frame * CFrame.new(side * (d / 2 - 0.05), y, 0), Color3.fromRGB(30, 40, 46))
			end
		elseif detail >= 2 then
			for _, side in ipairs({ -1, 1 }) do
				local panes = math.clamp(math.floor(w / 7), 1, 3)
				for pane = 0, panes - 1 do
					local along = -w / 2 + (pane + 0.5) * (w / panes)
					local pick = rng:NextNumber()
					local glassColour = if pick < 0.18 then dark elseif pick < 0.28 then boarded else GLASS
					local piece = cityBlock(parent, if pick < 0.28 then "Boarded" else "Window",
						Vector3.new(0.5, each * 0.5, w / panes - 2.2),
						frame * CFrame.new(side * (d / 2 - 0.1), y, along), glassColour,
						if pick < 0.28 then Enum.Material.WoodPlanks else Enum.Material.Glass)
					if pick >= 0.28 then
						piece.Reflectance = 0.06
					end
					-- A LIGHT IN A WINDOW above the water, in a handful of them. It is a real light,
					-- and it is not on all the time: the client switches it on and off at odd
					-- intervals, which is the thing about a drowned city that should not be
					-- happening.
					if pick >= 0.28 and litLeft > 0 and y + floorY > waterLevel + 2 and rng:NextNumber() < 0.06 then
						litLeft -= 1
						piece.Color = Color3.fromRGB(255, 214, 150)
						local glow = Instance.new("PointLight")
						glow.Brightness = 0
						glow.Range = 14
						glow.Color = Color3.fromRGB(255, 206, 140)
						glow.Shadows = false
						glow.Parent = piece
						CollectionService:AddTag(piece, "SunkenLitWindow")
					end
				end
			end
		end
	end
	-- PILASTERS: the vertical ribs between the window bays, which are what stop a facade reading as
	-- a striped box.
	local ribs = math.clamp(math.floor(w / 11), 1, 3)
	for index = 0, ribs do
		local z = -w / 2 + index * (w / ribs)
		for _, side in ipairs({ -1, 1 }) do
			cityBlock(parent, "Pilaster", Vector3.new(0.7, to - start, 1.4),
				frame * CFrame.new(side * (d / 2 + 0.25), (start + to) / 2, z),
				weathered(colour, (start + to) / 2 + floorY, rng))
		end
	end
	-- And a cornice on top of the run.
	cityBlock(parent, "Cornice", Vector3.new(d + 1.6, 1.1, w + 1.6), frame * CFrame.new(0, to, 0),
		weathered(colour, to + floorY, rng))
end

-- WEAR: rust, lost render, cracks, a corner gone and the rubble it left.
local function wearOn(parent: Instance, frame: CFrame, w: number, d: number, top: number, colour: Color3,
	rng: Random, detail: number)
	local floorY = frame.Position.Y
	local rust = Color3.fromRGB(122, 78, 52)
	if detail <= 0 then
		return
	end
	-- Rust running down from fixings. Thin, long, and always downward, which is the only direction
	-- a stain goes.
	for _ = 1, rng:NextInteger(2, if detail >= 2 then 5 else 3) do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local high = rng:NextNumber(floorY + 4, math.max(floorY + 5, top))
		local run = rng:NextNumber(4, 14)
		cityBlock(parent, "Stain", Vector3.new(0.25, run, rng:NextNumber(0.6, 1.6)),
			frame * CFrame.new(side * (d / 2 + 0.3), high - run / 2 - floorY, rng:NextNumber(-w / 2, w / 2)),
			rust:Lerp(colour, rng:NextNumber(0.2, 0.6)))
	end
	-- Render fallen off in patches, showing the block underneath.
	for _ = 1, if detail >= 2 then rng:NextInteger(1, 4) else 0 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local patchW = rng:NextNumber(3, 9)
		local patchH = rng:NextNumber(2, 6)
		cityBlock(parent, "Bare", Vector3.new(0.3, patchH, patchW),
			frame * CFrame.new(side * (d / 2 + 0.2), rng:NextNumber(2, math.max(3, top - floorY - 2)),
				rng:NextNumber(-w / 2 + patchW / 2, w / 2 - patchW / 2)), Color3.fromRGB(128, 120, 110))
	end
	-- A CORNER GONE, with what came off it on the ground. Parts cannot be subtracted, so the corner
	-- is not cut out -- it is rebuilt shorter, and the missing piece is lying at the foot of the wall.
	if detail >= 2 and rng:NextNumber() < 0.4 and top - floorY > 12 then
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local lost = rng:NextNumber(4, 9)
		cityBlock(parent, "Broken", Vector3.new(d * 0.32, lost, w * 0.3),
			frame * CFrame.new(side * d * 0.34, top - floorY - lost / 2, w * 0.35) * CFrame.Angles(0, 0, math.rad(4)),
			colour:Lerp(DEEP, 0.3))
		for piece = 1, rng:NextInteger(3, 6) do
			local size = rng:NextNumber(1.4, 3.4)
			cityBlock(parent, "Rubble", Vector3.new(size, size * 0.7, size * rng:NextNumber(0.7, 1.3)),
				frame * CFrame.new(side * (d / 2 + rng:NextNumber(1, 5)), size * 0.35,
					rng:NextNumber(-w / 2, w / 2)) * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6),
					rng:NextNumber(0, 1)), Color3.fromRGB(120, 116, 108))
		end
	end
end

-- GROWTH: the waterline band, ivy where the light is, and a tree that has taken a roof.
local function growthOn(parent: Instance, frame: CFrame, w: number, d: number, top: number, rng: Random,
	detail: number)
	local floorY = frame.Position.Y
	local weed = Color3.fromRGB(74, 104, 62)
	local algae = Color3.fromRGB(88, 118, 86)
	-- THE WATERLINE. Everything that has stood in a tide line wears one, and on a drowned city it is
	-- the one mark every building shares.
	--
	-- A RING ON THE WALLS, ENDING UNDER THE SURFACE. It was a solid slab the size of the building
	-- with its top exactly at the water's surface: on a building that stood, most of it was inside
	-- the walls, but on one that did not it was a green roof lying ON the water, fighting the water
	-- for the same pixels. Now it is four strips hugging the walls, from three studs down to a
	-- third of a stud under, and only on a building that actually reaches the surface.
	if top > waterLevel + 1 then
		for _, strip in ipairs({ { d / 2 + 0.25, 0, 0.5, w + 1 }, { -d / 2 - 0.25, 0, 0.5, w + 1 },
			{ 0, w / 2 + 0.25, d + 1, 0.5 }, { 0, -w / 2 - 0.25, d + 1, 0.5 } }) do
			cityBlock(parent, "Weedline", Vector3.new(strip[3], 2.7, strip[4]),
				frame * CFrame.new(strip[1], waterLevel - 1.65 - floorY, strip[2]), algae)
		end
	elseif top > waterLevel - 12 then
		-- A drowned roof near enough the light grows a mat of weed ON it, well under the surface.
		cityBlock(parent, "RoofWeed", Vector3.new(d * 0.7, 0.3, w * 0.6),
			frame * CFrame.new(rng:NextNumber(-d * 0.1, d * 0.1), top - floorY + 0.15, rng:NextNumber(-w * 0.15, w * 0.15)), algae)
	end
	-- FOAM where it comes out of the water: a ring a stud out from the wall, lying on the surface --
	-- high enough off it (SURFACE_CLEAR's reason) that the two never meet.
	if top > waterLevel + 1 then
		for _, strip in ipairs({ { d / 2 + 0.9, 0, 1.4, w + 3 }, { -d / 2 - 0.9, 0, 1.4, w + 3 },
			{ 0, w / 2 + 0.9, d + 3, 1.4 }, { 0, -w / 2 - 0.9, d + 3, 1.4 } }) do
			local foam = block(parent, "Foam", Vector3.new(strip[3], 0.25, strip[4]),
				frame * CFrame.new(strip[1], waterLevel + 0.35 - floorY, strip[2]), Color3.fromRGB(226, 238, 234),
				Enum.Material.SmoothPlastic, false)
			foam.Transparency = 0.45
			foam.CastShadow = false
		end
	end
	-- Algae up the underwater faces, in patches.
	for _ = 1, if detail >= 2 then rng:NextInteger(2, 5) else 0 do
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local patch = rng:NextNumber(3, 10)
		cityBlock(parent, "Algae", Vector3.new(0.35, patch, rng:NextNumber(3, 9)),
			frame * CFrame.new(side * (d / 2 + 0.35), rng:NextNumber(1, math.max(2, math.min(top, waterLevel) - floorY)),
				rng:NextNumber(-w / 2, w / 2)), algae:Lerp(DEEP, rng:NextNumber(0, 0.4)))
	end
	-- IVY up one face, above the water, and weed hanging off the sills under it.
	if detail >= 1 and top > waterLevel + 2 and rng:NextNumber() < 0.55 then
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local from = waterLevel - 2
		local runs = math.max(2, math.floor((top - from) / 3))
		for index = 0, runs do
			local y = from + index * ((top - from) / runs)
			ellipsoid(parent, "Ivy", Vector3.new(1.4, 2.6, rng:NextNumber(3, 7)),
				frame * CFrame.new(side * (d / 2 + 0.4), y - floorY,
					rng:NextNumber(-w / 3, w / 3) + math.sin(index) * 2), weed:Lerp(Color3.fromRGB(58, 84, 52),
					rng:NextNumber(0, 0.5)))
		end
	end
	-- AND A TREE OUT OF THE ROOF, sometimes: the thing that says nobody is coming back to this one.
	if detail >= 1 and top > waterLevel + 6 and rng:NextNumber() < 0.3 then
		local at = frame * Vector3.new(rng:NextNumber(-d / 4, d / 4), top - floorY, rng:NextNumber(-w / 4, w / 4))
		column(parent, "Trunk", 1, at, at.Y, at.Y + rng:NextNumber(4, 8), Color3.fromRGB(96, 82, 66), false, true)
		for leaf = 1, 3 do
			ellipsoid(parent, "Canopy", Vector3.new(rng:NextNumber(5, 9), rng:NextNumber(3, 5), rng:NextNumber(5, 9)),
				CFrame.new(at + Vector3.new(rng:NextNumber(-2, 2), rng:NextNumber(5, 9), rng:NextNumber(-2, 2))),
				weed:Lerp(Color3.fromRGB(110, 140, 84), rng:NextNumber(0, 0.6)))
		end
	end
end

-- HOLDING OUT: what somebody did about it, and in places is still doing.
local function holdingOut(parent: Instance, frame: CFrame, w: number, d: number, top: number, rng: Random)
	local floorY = frame.Position.Y
	local sand = Color3.fromRGB(168, 156, 128)
	local kind = rng:NextInteger(1, 5)
	if kind == 1 and top > waterLevel then
		-- SANDBAGS along the frontage, two courses, the top one short of the ends.
		for course = 0, 1 do
			local runs = math.max(2, math.floor(w / 3)) - course
			for index = 0, runs - 1 do
				local z = -w / 2 + (index + 0.5) * (w / runs)
				cityBlock(parent, "Sandbag", Vector3.new(2.4, 1, 2.8),
					frame * CFrame.new(d / 2 + 1.4, waterLevel - floorY + 0.5 + course * 1, z)
						* CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0), sand:Lerp(DEEP, rng:NextNumber(0, 0.25)))
			end
		end
	elseif kind == 2 then
		-- SCAFFOLDING on one wall: somebody was shoring this up when the water won.
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local high = math.min(top, waterLevel + 12)
		local pipe = Color3.fromRGB(150, 146, 134)
		for lift = 0, math.max(1, math.floor((high - floorY) / 7)) do
			local y = floorY + lift * 7
			if math.abs(y - waterLevel) < 0.8 then
				y -= 1.2 -- a board lying in the surface fights it for the same pixels
			end
			cityBlock(parent, "Boards", Vector3.new(2.6, 0.4, w * 0.8),
				frame * CFrame.new(side * (d / 2 + 1.6), y - floorY, 0), Color3.fromRGB(150, 124, 88))
			for _, z in ipairs({ -w * 0.35, w * 0.35 }) do
				local at = frame * Vector3.new(side * (d / 2 + 1.6), 0, z)
				column(parent, "ScaffoldLeg", 0.4, at, floorY, high, pipe, false, true)
			end
		end
	elseif kind == 3 and top > waterLevel then
		-- A PUMP on the parapet with its hose over the side, still pointing at the water.
		local at = frame * CFrame.new(rng:NextNumber(-d / 4, d / 4), top - floorY, rng:NextNumber(-w / 4, w / 4))
		cityBlock(parent, "PumpSkid", Vector3.new(4, 1, 3), at * CFrame.new(0, 0.5, 0), Color3.fromRGB(96, 100, 104))
		cityBlock(parent, "Pump", Vector3.new(3, 2.4, 2.2), at * CFrame.new(0, 2.2, 0), Color3.fromRGB(150, 92, 60))
		local hoseTop = (at * CFrame.new(1.4, 2.2, 0)).Position
		rod(parent, "Hose", hoseTop, Vector3.new(hoseTop.X + d / 2, waterLevel + 1, hoseTop.Z), 0.6,
			Color3.fromRGB(60, 66, 62))
		rod(parent, "Hose", Vector3.new(hoseTop.X + d / 2, waterLevel + 1, hoseTop.Z),
			Vector3.new(hoseTop.X + d / 2 + 3, waterLevel - 3, hoseTop.Z), 0.6, Color3.fromRGB(60, 66, 62))
	elseif kind == 4 and top > waterLevel + 3 then
		-- A FLOODLIGHT still burning on a corner, and it is a real light.
		local at = frame * CFrame.new(d / 2 - 1, top - floorY + 1.5, w / 2 - 1)
		column(parent, "LightMast", 0.5, at.Position, at.Position.Y - 1.5, at.Position.Y + 4,
			Color3.fromRGB(80, 84, 88), false, true)
		local head = cityBlock(parent, "Floodlight", Vector3.new(2, 1.4, 1.4), at * CFrame.new(0, 4, 0),
			Color3.fromRGB(226, 216, 190), Enum.Material.Glass)
		local glow = Instance.new("SpotLight")
		glow.Face = Enum.NormalId.Front
		glow.Angle = 70
		glow.Brightness = 1.4
		glow.Range = 50
		glow.Color = Color3.fromRGB(255, 232, 190)
		glow.Shadows = false
		glow.Parent = head
	else
		-- THE GAUGE painted on the wall, with the water's own marks on it. The plainest thing in the
		-- city and the one that says the most: somebody stood here and wrote down how far it came.
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local board = cityBlock(parent, "Gauge", Vector3.new(0.25, 10, 2.4),
			frame * CFrame.new(side * (d / 2 + 0.3), waterLevel - 3 - floorY, w / 3),
			Color3.fromRGB(226, 220, 204))
		for mark = 0, 4 do
			cityBlock(parent, "GaugeMark", Vector3.new(0.3, 0.3, if mark % 2 == 0 then 2.4 else 1.4),
				board.CFrame * CFrame.new(0.06, -4 + mark * 2, 0), Color3.fromRGB(60, 62, 66))
		end
		if top > waterLevel then
			label(board, if side > 0 then Enum.NormalId.Right else Enum.NormalId.Left, "HIGH WATER",
				Color3.fromRGB(70, 74, 78))
		end
	end
end

-- Everything a building gets once its own shape is up.
local function dress(parent: Instance, frame: CFrame, w: number, d: number, top: number, colour: Color3,
	rng: Random, detail: number)
	wearOn(parent, frame, w, d, top, colour, rng, detail)
	growthOn(parent, frame, w, d, top, rng, detail)
	-- Somebody was fighting the water at about one building in two on the street, and nowhere out in
	-- the haze, where a pump on a roof is four parts nobody will ever resolve.
	if detail >= 2 and rng:NextNumber() < 0.55 then
		holdingOut(parent, frame, w, d, top, rng)
	end
end

-- A BLOCK OF FLATS WITH THE WATER IN IT. Its lower storeys are drowned and its top one is open to
-- the weather, so you can look down into the rooms from the route.
--
-- IT NO LONGER STOPS AT THE WATERLINE. Every one of these used to top out two or three studs under
-- the surface, so a street of them was a field of flat tops at one height -- which is exactly what
-- "platforms in the sky" meant. They range from one storey under to four above now, and what is
-- above the water gets a roof rather than an open edge.
local function floodedFlats(parent: Instance, frame: CFrame, w: number, d: number, rng: Random, detail: number,
	mayStand: boolean)
	local floorY = frame.Position.Y
	-- IT ONLY STANDS UP OUT OF THE WATER WHERE THE LOT MAY. Anything that breaks the surface has to
	-- keep EMERGE_CLEAR beyond the route's reach, or it is a roof beside the walkway to jump onto;
	-- the city works out which lots those are and tells the building. Everywhere else it drowns,
	-- which is the same rule this level has always had -- it is only that a block of flats can now
	-- be the thing that stands.
	local stands = mayStand and rng:NextNumber() < 0.6
	-- A drowned one's parapet stands 2.6 over its top, so its top keeps 5.2 under the surface: the
	-- parapet then stays SURFACE_CLEAR under it, plainly drowned rather than a lip at the waterline.
	local top = if stands then waterLevel + rng:NextNumber(6, 30) else waterLevel - rng:NextNumber(5.2, 12)
	local storey = top - 8
	local facade = FACADES[rng:NextInteger(1, #FACADES)]
	cityBlock(parent, "Flats", Vector3.new(d, storey - floorY, w), frame * CFrame.new(0, (storey - floorY) / 2, 0),
		facade)
	facadeOf(parent, frame, w, d, 2, storey - floorY - 1, facade, rng, 7, detail)
	local rel = storey - floorY
	for _, wall in ipairs({ { d / 2 - 0.4, 0, 0.8, w }, { -d / 2 + 0.4, 0, 0.8, w }, { 0, w / 2 - 0.4, d, 0.8 },
		{ 0, -w / 2 + 0.4, d, 0.8 } }) do
		cityBlock(parent, "FlatWall", Vector3.new(wall[3], 8, wall[4]), frame * CFrame.new(wall[1], rel + 4, wall[2]),
			facade)
	end
	-- EVERY BLOCK HAS A ROOF. The top storey used to be open to the sky so you could look down into
	-- the rooms, and from any distance that is a hollow box -- which is what it was read back as.
	-- One in four has lost part of its roof instead: that is wear rather than hollowness, and it is
	-- the only way in for the eye, so it is the only one that gets the rooms furnished.
	local collapsed = rng:NextNumber() < 0.25
	local roofColour = weathered(facade, top, rng)
	if collapsed then
		cityBlock(parent, "FlatRoof", Vector3.new(d + 0.8, 0.7, w * 0.55 + 0.4),
			frame * CFrame.new(0, rel + 8.4, -w * 0.225), roofColour)
		cityBlock(parent, "FallenRoof", Vector3.new(d * 0.7, 0.6, w * 0.5),
			frame * CFrame.new(0, rel + 4, w * 0.2) * CFrame.Angles(math.rad(34), 0, 0), roofColour)
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
	else
		cityBlock(parent, "FlatRoof", Vector3.new(d + 0.8, 0.7, w + 0.8), frame * CFrame.new(0, rel + 8.4, 0), roofColour)
	end
	-- A parapet round the roof, so the building has an edge rather than stopping.
	for _, edge in ipairs({ { d / 2, 0, 0.6, w + 1.6 }, { -d / 2, 0, 0.6, w + 1.6 }, { 0, w / 2, d + 1.6, 0.6 },
		{ 0, -w / 2, d + 1.6, 0.6 } }) do
		cityBlock(parent, "Parapet", Vector3.new(edge[3], 1.8, edge[4]), frame * CFrame.new(edge[1], rel + 9.7, edge[2]),
			roofColour)
	end
	-- A tank and a stair head on the roofs that stand out of the water, which is what is actually on
	-- a roof; the drowned ones keep only the parapet, because nothing up there survived.
	if stands then
		local at = frame * Vector3.new(rng:NextNumber(-d / 5, d / 5), rel + 8.8, rng:NextNumber(-w / 5, w / 5))
		column(parent, "TankLegs", 2.4, at, at.Y, at.Y + 2.2, Color3.fromRGB(90, 80, 70), false, true)
		column(parent, "WaterTank", 4, at, at.Y + 2.2, at.Y + 6, Color3.fromRGB(128, 100, 80), false, true)
		cityBlock(parent, "StairHead", Vector3.new(4.5, 4, 4), frame * CFrame.new(-d / 4, rel + 10.5, w / 4), roofColour)
	end
	dress(parent, frame, w, d, math.max(top, storey + 8), facade, rng, detail)
end

-- A HOUSE OR A SHOP, low, entirely under the water, with a pitched roof made of two tilted slabs
-- (which look the same whichever way a wedge part happens to face).
local function house(parent: Instance, frame: CFrame, w: number, d: number, rng: Random, detail: number)
	local floorY = frame.Position.Y
	-- The roof's ridge and the chimney over it stand up to rise + 2 over the eaves, so the eaves go at
	-- least that and SURFACE_CLEAR under: a wide house with the old ten studs put its ridge out of the
	-- water.
	local rise = math.min(d, w) * 0.28
	local eaves = math.min(waterLevel - rng:NextNumber(10, 32), waterLevel - rise - 2 - SURFACE_CLEAR)
	local facade = FACADES[rng:NextInteger(1, #FACADES)]
	local roof = Color3.fromRGB(120, 76, 66):Lerp(Color3.fromRGB(80, 88, 96), rng:NextNumber())
	local body = eaves - floorY
	cityBlock(parent, "House", Vector3.new(d, body, w), frame * CFrame.new(0, body / 2, 0), facade)
	facadeOf(parent, frame, w, d, 1.5, body - 1.5, facade, rng, 6, detail)
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
	dress(parent, frame, w, d, eaves + rise, facade, rng, detail)
end

-- AN APARTMENT BLOCK OR AN OFFICE, standing up out of the water. `broken` takes a storey off one half.
local function tower(parent: Instance, frame: CFrame, w: number, d: number, top: number, office: boolean,
	rng: Random, detail: number)
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
	facadeOf(parent, frame, w, d, 2, main - 2, facade, rng, if office then 5 else 7, detail)
	if office then
		-- A SKYSCRAPER has a top, not an end. A setback storey narrower than the shaft, a crown of
		-- fins round it, plant on the roof and a mast with a red light that still blinks -- the
		-- aviation light is the one thing in this city still doing its job, which is the point of it.
		local upper = math.min(10, height * 0.12)
		cityBlock(parent, "Setback", Vector3.new(d * 0.72, upper, w * 0.72), frame * CFrame.new(0, height + upper / 2, 0),
			weathered(facade, top, rng))
		for index = 0, 5 do
			local a = index * math.pi / 3
			cityBlock(parent, "CrownFin", Vector3.new(0.6, upper + 4, 2.2),
				frame * CFrame.new(math.cos(a) * d * 0.38, height + (upper + 4) / 2, math.sin(a) * w * 0.38)
					* CFrame.Angles(0, -a, 0), weathered(facade, top, rng))
		end
		cityBlock(parent, "Crown", Vector3.new(d + 1, 1.4, w + 1), frame * CFrame.new(0, height - 0.7, 0), facade)
		cityBlock(parent, "PlantRoom", Vector3.new(d * 0.3, 3, w * 0.3), frame * CFrame.new(-d * 0.1, height + upper + 1.5, 0),
			Color3.fromRGB(118, 122, 124))
		local mastAt = frame * Vector3.new(d * 0.12, height + upper, w * 0.12)
		local mastTop = mastAt.Y + rng:NextNumber(12, 20)
		column(parent, "Antenna", 0.5, mastAt, mastAt.Y, mastTop, Color3.fromRGB(90, 94, 100), false, true)
		local beacon = block(parent, "AviationLight", Vector3.new(0.8, 0.8, 0.8), CFrame.new(mastAt.X, mastTop + 0.4, mastAt.Z),
			Color3.fromRGB(220, 60, 50), Enum.Material.Glass, false)
		local red = Instance.new("PointLight")
		red.Brightness = 1.2
		red.Range = 18
		red.Color = Color3.fromRGB(255, 70, 50)
		red.Shadows = false
		red.Parent = beacon
		CollectionService:AddTag(beacon, "SunkenBlink")
	else
		cityBlock(parent, "RoofHouse", Vector3.new(d * 0.3, 3, w * 0.25), frame * CFrame.new(-d / 5, main + 1.5, -w / 5), facade)
		-- A SIGN ON THE ROOF, now and then, lettered on a board on two legs and turned to the street:
		-- what the building was, which is the most city thing a skyline can say.
		if top > waterLevel + 8 and rng:NextNumber() < 0.2 then
			local words = ({ "HOTEL", "BANK", "CINEMA", "RADIO", "GRAND HOTEL", "TELEGRAPH", "OFFICES", "DAIRY" })[rng:NextInteger(1, 8)]
			local long = math.min(w * 0.7, 6 + #words * 1.6)
			for _, z in ipairs({ -long * 0.35, long * 0.35 }) do
				cityBlock(parent, "SignLeg", Vector3.new(0.5, 3, 0.5), frame * CFrame.new(-d / 2 + 2, main + 1.5, z),
					Color3.fromRGB(80, 84, 88), Enum.Material.Metal)
			end
			local board = cityBlock(parent, "RoofSign", Vector3.new(0.4, 3.4, long), frame * CFrame.new(-d / 2 + 2, main + 4.7, 0),
				FADED[rng:NextInteger(1, #FADED)]:Lerp(Color3.new(1, 1, 1), 0.2))
			label(board, Enum.NormalId.Left, words, Color3.fromRGB(246, 242, 232))
			label(board, Enum.NormalId.Right, words, Color3.fromRGB(246, 242, 232))
		end
		if rng:NextNumber() < 0.4 then
			local at = frame * Vector3.new(d / 5, main, w / 6)
			column(parent, "TankLegs", 2.6, at, at.Y, at.Y + 2.5, Color3.fromRGB(90, 80, 70), false, true)
			column(parent, "WaterTank", 4.2, at, at.Y + 2.5, at.Y + 7, Color3.fromRGB(128, 100, 80), false, true)
		end
	end
	-- A PARAPET round whatever the top turned out to be, so the building has an edge rather than
	-- stopping; and then everything time and the sea have done to it.
	for _, edge in ipairs({ { d / 2, 0, 0.6, w + 1.4 }, { -d / 2, 0, 0.6, w + 1.4 }, { 0, w / 2, d + 1.4, 0.6 },
		{ 0, -w / 2, d + 1.4, 0.6 } }) do
		cityBlock(parent, "Parapet", Vector3.new(edge[3], 1.6, edge[4]),
			frame * CFrame.new(edge[1], main + 0.8, edge[2]), weathered(facade, top, rng))
	end
	dress(parent, frame, w, d, top, facade, rng, detail)
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

-- A WAREHOUSE: one long shed with a sawtooth roof and a door big enough for a lorry, which is what
-- the far side of a dock street is made of. Low, so it reads as the back of the city rather than
-- competing with the towers.
local function warehouse(parent: Instance, frame: CFrame, w: number, d: number, rng: Random, detail: number,
	mayStand: boolean)
	local floorY = frame.Position.Y
	-- Its roof only comes up out of the water where the lot may break the surface; see floodedFlats.
	-- Standing clear of the water or plainly under it: a sawtooth roof within a stud of the surface
	-- was one of the flickering green roofs (SURFACE_CLEAR).
	local top = if mayStand then waterLevel + rng:NextNumber(3.5, 9) else waterLevel - rng:NextNumber(6, 11)
	local colour = drowned(Color3.fromRGB(150, 148, 138), (floorY + top) / 2)
	cityBlock(parent, "Warehouse", Vector3.new(d, top - floorY, w), frame * CFrame.new(0, (top - floorY) / 2, 0), colour)
	-- The sawtooth: short pitched ridges along its length, the glazed face of each one landward.
	local teeth = math.max(2, math.floor(w / 14))
	for index = 0, teeth - 1 do
		local z = -w / 2 + (index + 0.5) * (w / teeth)
		cityBlock(parent, "SawRidge", Vector3.new(d * 0.9, 3, w / teeth * 0.55),
			frame * CFrame.new(0, top - floorY + 1.5, z) * CFrame.Angles(math.rad(18), 0, 0), colour)
		local pane = cityBlock(parent, "SawGlass", Vector3.new(d * 0.88, 2.6, 0.4),
			frame * CFrame.new(0, top - floorY + 2.2, z + w / teeth * 0.3), GLASS)
		pane.Transparency = 0.45
	end
	-- The door, and the loading bank in front of it.
	cityBlock(parent, "WarehouseDoor", Vector3.new(0.6, math.min(10, top - floorY - 2), w * 0.34),
		frame * CFrame.new(-d / 2 - 0.2, math.min(10, top - floorY - 2) / 2, 0), Color3.fromRGB(96, 104, 104))
	cityBlock(parent, "LoadingBank", Vector3.new(6, 2.2, w * 0.5), frame * CFrame.new(-d / 2 - 3, 1.1, 0),
		drowned(STONE, floorY + 1))
	facadeOf(parent, frame, w, d, 2, top - floorY - 4, colour, rng, 9, detail)
	dress(parent, frame, w, d, top, colour, rng, detail)
	if rng:NextNumber() < 0.6 then
		for index = 1, rng:NextInteger(2, 5) do
			local crate = rng:NextNumber(3.5, 6)
			container(parent, frame * CFrame.new(-d / 2 - 8 - rng:NextNumber(0, 10), crate / 2,
				rng:NextNumber(-w / 2, w / 2)) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
				Vector3.new(crate * 2.2, crate, crate), FADED[rng:NextInteger(1, #FADED)], false)
		end
	end
end

-- A CHURCH, because every drowned city has one thing older than the rest of it, and because a
-- spire is the one silhouette that reads at any distance. The nave is under the water and the
-- tower comes up out of it.
local function church(parent: Instance, frame: CFrame, w: number, d: number)
	local floorY = frame.Position.Y
	local stone = drowned(Color3.fromRGB(184, 178, 162), floorY + 10)
	local naveTop = waterLevel - 6 -- its roof, 3 over this, keeps SURFACE_CLEAR under the water
	cityBlock(parent, "Nave", Vector3.new(d, naveTop - floorY, w * 0.6), frame * CFrame.new(0, (naveTop - floorY) / 2, 0), stone)
	cityBlock(parent, "NaveRoof", Vector3.new(d * 1.04, 3, w * 0.62), frame * CFrame.new(0, naveTop - floorY + 1.5, 0),
		drowned(Color3.fromRGB(120, 116, 112), naveTop))
	-- Buttresses down both sides, which is what says church rather than shed.
	for index = -2, 2 do
		for _, side in ipairs({ -1, 1 }) do
			cityBlock(parent, "Buttress", Vector3.new(5, naveTop - floorY - 6, 3),
				frame * CFrame.new(side * (d / 2 + 1.5), (naveTop - floorY - 6) / 2, index * w * 0.11), stone)
		end
	end
	local towerTop = waterLevel + 34
	local side = math.min(d * 0.7, 16)
	cityBlock(parent, "ChurchTower", Vector3.new(side, towerTop - floorY, side),
		frame * CFrame.new(0, (towerTop - floorY) / 2, -w * 0.36), stone)
	-- The belfry openings, and the spire over them.
	for _, face in ipairs({ Vector3.new(side / 2 + 0.2, 0, 0), Vector3.new(-side / 2 - 0.2, 0, 0),
		Vector3.new(0, 0, side / 2 + 0.2), Vector3.new(0, 0, -side / 2 - 0.2) }) do
		local opening = cityBlock(parent, "Belfry", Vector3.new(1, 7, 5),
			frame * CFrame.new(face.X, towerTop - floorY - 8, -w * 0.36 + face.Z), Color3.fromRGB(30, 34, 36))
		opening.Size = if math.abs(face.X) > 0 then Vector3.new(1, 7, 5) else Vector3.new(5, 7, 1)
	end
	for index = 0, 5 do
		local shrink = 1 - index / 6
		cityBlock(parent, "Spire", Vector3.new(side * 0.8 * shrink, 4, side * 0.8 * shrink),
			frame * CFrame.new(0, towerTop - floorY + 2 + index * 4, -w * 0.36), stone)
	end
	column(parent, "Cross", 0.5, (frame * CFrame.new(0, 0, -w * 0.36)).Position, towerTop + 26, towerTop + 32, BRASS, false)
end

-- A BILLBOARD on a roof or on its own legs: a hoarding whose paint has gone, and the one flat
-- surface in the level that faces the street.
local function billboard(parent: Instance, at: CFrame, wide: number, high: number, rng: Random)
	local frame = drowned(Color3.fromRGB(88, 88, 92), at.Position.Y)
	for _, side in ipairs({ -1, 1 }) do
		column(parent, "BoardLeg", 1, (at * CFrame.new(side * wide * 0.38, 0, 0)).Position, at.Position.Y - 12,
			at.Position.Y, frame, false)
	end
	local face = cityBlock(parent, "Billboard", Vector3.new(0.6, high, wide), at * CFrame.new(0, high / 2, 0),
		drowned(FADED[rng:NextInteger(1, #FADED)], at.Position.Y))
	label(face, Enum.NormalId.Front, if rng:NextNumber() < 0.5 then "SEA\nVIEW" else "OPEN\nDAILY",
		Color3.fromRGB(230, 226, 214))
	cityBlock(parent, "BoardRail", Vector3.new(0.8, 0.8, wide + 1.4), at * CFrame.new(0, high, 0), frame)
end

-- A VEHICLE, drowned where it stopped: a car, a van or a bus, at its own size. They were drawn at
-- two thirds of a car next to a person, and beside hundred-stud buildings in a hundred-and-twelve-
-- stud street they read as toys. `big` allows the bus, which only goes where there is room for one.
local streetKit = {}
function streetKit.wheel(parent: Instance, at: CFrame, size: number)
	local tyre = cityBlock(parent, "Wheel", Vector3.new(size * 0.35, size, size), at, Color3.fromRGB(34, 34, 36))
	tyre.Shape = Enum.PartType.Cylinder
end

function streetKit.car(parent: Instance, at: CFrame, rng: Random, big: boolean)
	local colour = FADED[rng:NextInteger(1, #FADED)]
	local glass = Color3.fromRGB(40, 54, 62)
	local kind = rng:NextNumber()
	if big and kind > 0.82 then
		-- A BUS: long, tall, a band of windows down both sides and a destination board nobody reads.
		cityBlock(parent, "Bus", Vector3.new(8.4, 8.6, 34), at * CFrame.new(0, 5.6, 0), colour:Lerp(Color3.fromRGB(200, 170, 80), 0.4))
		cityBlock(parent, "BusWindows", Vector3.new(8.6, 2.6, 30), at * CFrame.new(0, 7, 0.6), glass)
		cityBlock(parent, "BusScreen", Vector3.new(7.4, 3, 0.3), at * CFrame.new(0, 6.4, -17.05), glass)
		local board = cityBlock(parent, "BusBoard", Vector3.new(6, 1.2, 0.3), at * CFrame.new(0, 9.2, -17.1), Color3.fromRGB(30, 30, 32))
		label(board, Enum.NormalId.Front, "42  HARBOUR", Color3.fromRGB(230, 170, 70))
		for _, z in ipairs({ -11, 11 }) do
			for _, x in ipairs({ -4.2, 4.2 }) do
				streetKit.wheel(parent, at * CFrame.new(x, 1.6, z), 3.2)
			end
		end
	elseif kind > 0.66 then
		-- A VAN: a box behind a cab.
		cityBlock(parent, "Van", Vector3.new(6, 6.4, 11), at * CFrame.new(0, 4.4, 2), colour)
		cityBlock(parent, "VanCab", Vector3.new(6, 4.6, 5), at * CFrame.new(0, 3.5, -5.8), colour)
		cityBlock(parent, "VanScreen", Vector3.new(5.4, 1.8, 0.3), at * CFrame.new(0, 4.6, -8.3), glass)
		for _, z in ipairs({ -5.6, 4.6 }) do
			for _, x in ipairs({ -2.9, 2.9 }) do
				streetKit.wheel(parent, at * CFrame.new(x, 1.3, z), 2.6)
			end
		end
	else
		-- A CAR: body, cabin with its glass, bumpers, headlamps.
		cityBlock(parent, "CarBody", Vector3.new(5.4, 2.4, 13), at * CFrame.new(0, 1.9, 0), colour)
		cityBlock(parent, "CarCabin", Vector3.new(5, 2.2, 6.6), at * CFrame.new(0, 4.2, 0.4), colour)
		cityBlock(parent, "CarGlass", Vector3.new(5.1, 1.4, 5.6), at * CFrame.new(0, 4.3, 0.4), glass)
		cityBlock(parent, "CarGlass", Vector3.new(4.6, 1.4, 6.8), at * CFrame.new(0, 4.3, 0.4), glass)
		for _, z in ipairs({ -6.6, 6.6 }) do
			cityBlock(parent, "Bumper", Vector3.new(5.6, 0.7, 0.5), at * CFrame.new(0, 1.2, z), Color3.fromRGB(120, 122, 124))
		end
		for _, x in ipairs({ -1.8, 1.8 }) do
			cityBlock(parent, "Headlamp", Vector3.new(0.9, 0.6, 0.2), at * CFrame.new(x, 2.3, -6.55), Color3.fromRGB(210, 214, 200))
		end
		for _, z in ipairs({ -4.2, 4.2 }) do
			for _, x in ipairs({ -2.7, 2.7 }) do
				streetKit.wheel(parent, at * CFrame.new(x, 1.3, z), 2.6)
			end
		end
	end
end

-- A TRAM on its rails, where the last one stopped: one along the whole street, and the only thing
-- down there longer than a bus.
function streetKit.tram(parent: Instance, at: CFrame)
	local cream, green = Color3.fromRGB(222, 212, 184), Color3.fromRGB(74, 120, 98)
	cityBlock(parent, "Tram", Vector3.new(8.2, 9.4, 32), at * CFrame.new(0, 6.2, 0), cream)
	cityBlock(parent, "TramSkirt", Vector3.new(8.4, 2.6, 32.2), at * CFrame.new(0, 2.8, 0), green)
	cityBlock(parent, "TramWindows", Vector3.new(8.4, 3, 28), at * CFrame.new(0, 7.4, 0), Color3.fromRGB(40, 54, 62))
	cityBlock(parent, "TramRoof", Vector3.new(7.2, 0.8, 30), at * CFrame.new(0, 11.3, 0), green)
	rod(parent, "Pantograph", (at * CFrame.new(0, 11.7, 2)).Position, (at * CFrame.new(0, 15.5, -1)).Position, 0.3,
		Color3.fromRGB(60, 62, 64))
	rod(parent, "Pantograph", (at * CFrame.new(0, 15.5, -1)).Position, (at * CFrame.new(0, 15.5, -4)).Position, 0.3,
		Color3.fromRGB(60, 62, 64))
	for _, z in ipairs({ -11, 11 }) do
		cityBlock(parent, "Bogie", Vector3.new(7, 1.6, 6), at * CFrame.new(0, 1.2, z), Color3.fromRGB(46, 48, 50))
	end
end

-- STREET FURNITURE on the pavement edge: a bus shelter, a phone box, a bench, a bin, a dead tree, or
-- a traffic light still changing for nobody -- its amber is a real light, and it blinks
-- (SunkenBlink, SunkenCityClient).
function streetKit.furniture(parent: Instance, at: CFrame, rng: Random)
	local iron = Color3.fromRGB(62, 66, 68)
	local pick = rng:NextNumber()
	if pick < 0.2 then
		for _, z in ipairs({ -3.6, 3.6 }) do
			column(parent, "ShelterPost", 0.4, (at * CFrame.new(-1.2, 0, z)).Position, at.Position.Y, at.Position.Y + 7.4, iron, false)
		end
		cityBlock(parent, "ShelterRoof", Vector3.new(3.2, 0.3, 8.4), at * CFrame.new(-0.4, 7.5, 0), iron)
		local back = cityBlock(parent, "ShelterBack", Vector3.new(0.2, 5, 7.6), at * CFrame.new(-1.6, 3.6, 0), Color3.fromRGB(150, 180, 184))
		back.Transparency = 0.4
		cityBlock(parent, "ShelterSeat", Vector3.new(1, 0.3, 5), at * CFrame.new(-1, 1.6, 0), iron)
	elseif pick < 0.36 then
		local red = Color3.fromRGB(168, 56, 48)
		cityBlock(parent, "PhoneBox", Vector3.new(2.6, 7.6, 2.6), at * CFrame.new(0, 3.8, 0), red)
		cityBlock(parent, "PhoneGlass", Vector3.new(2.7, 4.6, 2.2), at * CFrame.new(0, 4.4, 0), Color3.fromRGB(40, 54, 62))
		cityBlock(parent, "PhoneRoof", Vector3.new(2.9, 0.6, 2.9), at * CFrame.new(0, 7.9, 0), red)
	elseif pick < 0.54 then
		local wood = Color3.fromRGB(110, 90, 66)
		cityBlock(parent, "BenchSeat", Vector3.new(1.6, 0.3, 6), at * CFrame.new(0, 1.8, 0), wood)
		cityBlock(parent, "BenchBack", Vector3.new(0.3, 1.6, 6), at * CFrame.new(-0.8, 2.9, 0), wood)
		for _, z in ipairs({ -2.4, 2.4 }) do
			cityBlock(parent, "BenchLeg", Vector3.new(1.4, 1.7, 0.3), at * CFrame.new(0, 0.85, z), iron)
		end
		column(parent, "Bin", 1.4, (at * CFrame.new(0, 0, 4.6)).Position, at.Position.Y, at.Position.Y + 2.6, Color3.fromRGB(58, 84, 70), false)
	elseif pick < 0.8 then
		-- A DEAD TREE, the street's plane trees drowned in their planters, weed hanging off them.
		local base = at.Position
		column(parent, "Planter", 3.6, base, base.Y, base.Y + 1.2, Color3.fromRGB(120, 116, 106), false)
		local tall = rng:NextNumber(14, 22)
		local crown = base + Vector3.new(0, tall, 0)
		rod(parent, "Trunk", base, crown, 1.1, Color3.fromRGB(70, 64, 56))
		for branch = 1, 4 do
			local a = branch * 1.6 + rng:NextNumber(-0.4, 0.4)
			local from = base + Vector3.new(0, tall * rng:NextNumber(0.55, 0.9), 0)
			local tip = from + Vector3.new(math.cos(a) * rng:NextNumber(3, 6), rng:NextNumber(2, 5), math.sin(a) * rng:NextNumber(3, 6))
			rod(parent, "Branch", from, tip, 0.45, Color3.fromRGB(70, 64, 56))
			if branch % 2 == 0 then
				ellipsoid(parent, "Weed", Vector3.new(1.4, 2.6, 1.4), CFrame.new(tip - Vector3.new(0, 1.2, 0)), Color3.fromRGB(70, 100, 60))
			end
		end
	else
		-- A TRAFFIC LIGHT, amber, blinking.
		local base = at.Position
		column(parent, "SignalPole", 0.5, base, base.Y, base.Y + 10, iron, false)
		cityBlock(parent, "SignalHead", Vector3.new(1.2, 3.6, 1.2), CFrame.new(base + Vector3.new(0, 11.6, 0)), Color3.fromRGB(40, 42, 44))
		for index, colour in ipairs({ Color3.fromRGB(90, 30, 26), Color3.fromRGB(230, 160, 50), Color3.fromRGB(30, 70, 40) }) do
			local lens = cityBlock(parent, "SignalLens", Vector3.new(0.3, 0.8, 0.8), CFrame.new(base + Vector3.new(0.65, 12.8 - index * 1.1, 0)), colour)
			if index == 2 then
				local amber = Instance.new("PointLight")
				amber.Brightness = 1.2
				amber.Range = 14
				amber.Color = Color3.fromRGB(255, 170, 60)
				amber.Shadows = false
				amber.Parent = lens
				CollectionService:AddTag(lens, "SunkenBlink")
			end
		end
	end
end

-- LIFE ON THE SEA FLOOR: a coral head, anemones on their stalks, urchins, a starfish. The street has
-- been a sea floor for long enough to be colonised.
function streetKit.reef(parent: Instance, at: Vector3, rng: Random)
	local ANEMONE = { Color3.fromRGB(220, 120, 140), Color3.fromRGB(240, 180, 90), Color3.fromRGB(160, 130, 210),
		Color3.fromRGB(120, 200, 170) }
	local head = ellipsoid(parent, "CoralHead", Vector3.new(rng:NextNumber(2.5, 4.5), rng:NextNumber(1.6, 2.6), rng:NextNumber(2.5, 4.5)),
		CFrame.new(at + Vector3.new(0, 0.8, 0)), Color3.fromRGB(190, 176, 150):Lerp(ANEMONE[rng:NextInteger(1, #ANEMONE)], 0.3))
	head.Material = Enum.Material.Slate
	for _ = 1, rng:NextInteger(2, 3) do
		local foot = at + Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
		local stalk = rng:NextNumber(0.8, 1.8)
		column(parent, "AnemoneStalk", 0.6, foot, foot.Y, foot.Y + stalk, Color3.fromRGB(200, 180, 160), false, true)
		ellipsoid(parent, "Anemone", Vector3.new(1.4, 0.9, 1.4), CFrame.new(foot + Vector3.new(0, stalk + 0.3, 0)),
			ANEMONE[rng:NextInteger(1, #ANEMONE)])
	end
	if rng:NextNumber() < 0.6 then
		local urchin = ellipsoid(parent, "Urchin", Vector3.new(0.9, 0.7, 0.9), CFrame.new(at + Vector3.new(rng:NextNumber(-2, 2), 0.35,
			rng:NextNumber(-2, 2))), Color3.fromRGB(40, 30, 50))
		urchin.Material = Enum.Material.Slate
	end
end


-- ===== THE CITY =====
--
-- A grid of blocks laid in the route's own direction, either side of it, out to CITY_SIDE and a
-- little past each end. The grid is STRAIGHT and the route MEANDERS through it, which is what a
-- real city looks like where a boulevard sweeps through one: every lot the street would run into
-- is pushed back and shortened until its frontage is on the kerb, and the street's edge follows
-- the bend while the blocks behind it stay square.
--
-- Each block holds two or three buildings along its frontage rather than one, because a block that
-- is one building is a warehouse and a street of warehouses is not a city.
-- How much of the route's end belongs to the harbour, on a route of this length.
local function harbourAlong(route: Route): number
	return math.min(HARBOUR_ALONG, route.total * HARBOUR_ALONG_SHARE)
end

local function city(parent: Instance, route: Route, floorY: number, blocked: (Vector3, number) -> boolean,
	rng: Random): number
	local built = 0
	local pitch = BLOCK + STREET
	local from, to = -CITY_BEYOND, route.total + CITY_BEYOND
	local rows = math.max(1, math.floor((to - from) / pitch))
	local cols = math.max(1, math.floor(CITY_SIDE * 2 / pitch))
	local churchDone = false
	for row = 0, rows do
		for col = 0, cols do
			local s = from + (row + 0.5) * pitch
			local across = -CITY_SIDE + (col + 0.5) * pitch
			local spot = route.points[1] + route.forward * s + route.side * across
			local at = Vector3.new(spot.X, floorY, spot.Z)
			local near, away = nearRoute(route, at)
			local half = BLOCK / 2
			-- In the street itself, or in the harbour's open water at the end of it.
			local along = alongOf(route, at)
			local harbourish = along > route.total - harbourAlong(route) and near < HARBOUR_REACH
			if near >= BOULEVARD_HALF + 14 and not harbourish then
				-- What the street takes out of this block, and what is left of it.
				local bite = math.max(0, (BOULEVARD_HALF + 6) - (near - half))
				local depth = BLOCK - bite
				if depth >= LOT_MIN then
					local centre = at + away * (bite / 2)
					local reach = math.sqrt(depth * depth + BLOCK * BLOCK) / 2
					if not blocked(centre, reach) then
						-- WHICH WAY THE BLOCK FACES. On the kerb it faces the street, because a
						-- frontage follows the road it is on. Further back it faces the way the
						-- GRID does, or the whole city would fan out round the bend like spokes
						-- instead of standing in streets of its own.
						local gridWay = if across >= 0 then route.side else -route.side
						local facing = if near < 320 then away else gridWay
						local frame = CFrame.fromMatrix(Vector3.new(centre.X, floorY, centre.Z), facing, Vector3.yAxis)
						-- HOW MUCH BUILDING THIS LOT GETS. A frontage on the street is read at walking
						-- distance and gets everything; the middle distance gets its storeys and its
						-- ribs; the haze gets a silhouette, which is all it could show anyway.
						local detail = if near < DETAIL_NEAR then 2 elseif near < DETAIL_MID then 1 else 0
						local frontage = BLOCK - 8
						local lots = if near < 320 then rng:NextInteger(2, 3) else rng:NextInteger(1, 2)
						local lotW = frontage / lots
						-- ANYTHING THAT BREAKS THE SURFACE keeps clear of the route.
						--
						-- Judged by where the lot's frontage ACTUALLY is once the street has taken its
						-- bite, not by where the block started: the block's own half made every lot on the
						-- kerb count as too near, so the whole first row drowned just under the surface.
						-- The frontage is 62 from the route's line at the nearest, which is far past any
						-- jump from a chunk.
						local nearCentre = nearRoute(route, centre)
						local clearOfRoute = nearCentre - depth / 2 >= EMERGE_CLEAR + ROUTE_REACH
						for index = 1, lots do
							local offset = -frontage / 2 + (index - 0.5) * lotW
							local lot = frame * CFrame.new(0, 0, offset)
							local w, d = lotW - 6, depth - 10
							local pick = rng:NextNumber()
							if near < 320 then
								if not churchDone and near > 150 and pick > 0.94 and clearOfRoute then
									church(parent, lot, w, d)
									dress(parent, lot, w, d, waterLevel + 34, Color3.fromRGB(184, 178, 162), rng, 2)
									churchDone = true
								elseif pick < 0.42 then
									floodedFlats(parent, lot, w, d, rng, detail, clearOfRoute)
								elseif pick < 0.72 then
									house(parent, lot, w, d, rng, detail)
								elseif pick < 0.88 and clearOfRoute then
									tower(parent, lot, w, d * 0.8, waterLevel + rng:NextNumber(6, 22), false, rng, detail)
								else
									warehouse(parent, lot, w, d, rng, detail, clearOfRoute)
								end
							elseif near < 620 then
								if pick < 0.35 and clearOfRoute then
									tower(parent, lot, w, d * 0.7, waterLevel + rng:NextNumber(10, 38), false, rng, detail)
								elseif pick < 0.62 then
									floodedFlats(parent, lot, w, d * 0.8, rng, detail, clearOfRoute)
								elseif pick < 0.84 then
									warehouse(parent, lot, w, d * 0.8, rng, detail, clearOfRoute)
								else
									house(parent, lot, w, d * 0.8, rng, detail)
								end
							elseif pick < 0.62 then
								tower(parent, lot, w * 0.85, d * 0.6, waterLevel + rng:NextNumber(20, 64),
									pick < 0.3, rng, detail)
							end
							built += 1
							-- A hoarding on a roof, where it would face the street.
							if near < 420 and clearOfRoute and rng:NextNumber() < 0.07 then
								billboard(parent, lot * CFrame.new(-d / 2 + 2, waterLevel - floorY + 4, 0), 18, 9, rng)
							end
						end
					end
				end
			end
		end
	end
	-- LONE TOWERS out past the last block, for a skyline that fades into the haze.
	for index = 1, FAR_TOWERS do
		local s = rng:NextNumber(-CITY_BEYOND, route.total + CITY_BEYOND)
		local sign = if index % 2 == 0 then 1 else -1
		local across = sign * rng:NextNumber(CITY_SIDE, CITY_SIDE + (if sign > 0 then FAR_OPEN else 700))
		local spot = route.points[1] + route.forward * s + route.side * across
		local at = Vector3.new(spot.X, floorY, spot.Z)
		local _, away = nearRoute(route, at)
		local frame = CFrame.fromMatrix(at, away, Vector3.yAxis)
		tower(parent, frame, rng:NextNumber(26, 40), rng:NextNumber(26, 40), waterLevel + rng:NextNumber(40, 96),
			true, rng, 0)
		built += 1
	end
	return built
end

-- ===== THE FERRIS WHEEL =====
--
-- A fairground's, drowned: standing in its own square of open water off the street, on the side
-- away from the plaza and the thing on the horizon, its lowest cabins under the surface and the
-- rest still going round, very slowly, for nobody. Every city has towers and a clock; a drowned one
-- reads as drowned by what should not be in water, and this is the one circle in a city of
-- rectangles, which is why it is seen from everywhere.
--
-- The meshes are gen_ferris.py's (Ferris_Frame, Ferris_Wheel, Ferris_Gondola, found and checked by
-- SeaRig); with none imported it is built plainer from parts in the same place. The frame reaches
-- the floor from `hub` over the water -- gen_ferris.py's FRAME_DOWN is FLOOR_DEPTH + hub, and the
-- checker holds the two together -- so it stands on the sea floor, not a stud off it. The client
-- turns the wheel and hangs the cabins (SunkenFerris), on the server's clock. One cabin's light is
-- still on.
local FERRIS = {
	out = 250, -- off the route's line
	hub = 26, -- the axle, over the water
	radius = 36, -- to the cabins' pins
	hang = 3, -- a cabin's middle, under its pin
	cabins = 16,
	spin = 0.02, -- radians a second: once round in five minutes
	reach = 40, -- the most it covers from its middle, frame and all
	clear = 48, -- and the square the city leaves it
	window = 190, -- and how far it keeps from the open water past the aquarium's window
	-- Where along the street it may stand, first choice first. Many, because the aquarium's view,
	-- the flat, the plaza and the harbour each rule some out, and five left it nowhere on some runs.
	shares = { 0.55, 0.62, 0.48, 0.7, 0.3, 0.4, 0.66, 0.35, 0.52, 0.25, 0.44, 0.75, 0.58, 0.2, 0.8, 0.15 },
	colours = { Color3.fromRGB(214, 170, 170), Color3.fromRGB(170, 204, 186), Color3.fromRGB(222, 206, 150),
		Color3.fromRGB(160, 186, 214) },
}

local function ferrisWheel(parent: Instance, at: Vector3, toward: Vector3, floorY: number, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = "FerrisWheel"
	model.Parent = parent
	local axle = CFrame.fromMatrix(Vector3.new(at.X, floorY + FLOOR_DEPTH + FERRIS.hub, at.Z), toward, Vector3.yAxis)
	local epoch = workspace:GetServerTimeNow()
	local paint = Color3.fromRGB(206, 202, 192)
	local function turning(item: Instance, index: number?)
		item:SetAttribute("Axle", axle)
		item:SetAttribute("Spin", FERRIS.spin)
		item:SetAttribute("Epoch", epoch)
		item:SetAttribute("Radius", FERRIS.radius)
		item:SetAttribute("Hang", FERRIS.hang)
		item:SetAttribute("Count", FERRIS.cabins)
		if index then
			item:SetAttribute("Index", index)
		end
		CollectionService:AddTag(item, "SunkenFerris")
	end
	local function mesh(name: string): BasePart?
		local rig = if SeaRig then SeaRig.place(model, name) else nil
		return rig and rig.part
	end
	-- A straight member from a to b, for the part-built wheel.
	local function strut(name: string, a: Vector3, b: Vector3, thick: number, into: Instance): Part
		return block(into, name, Vector3.new(thick, thick, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), paint,
			Enum.Material.Metal, false)
	end
	-- THE FRAME: an A-frame either side, braced, from the axle's bearings down to the floor.
	local frame = mesh("Ferris_Frame")
	if frame then
		frame.CFrame = axle
		frame.Color = paint
		frame.Material = Enum.Material.Metal
	else
		for _, side in ipairs({ -1, 1 }) do
			local top = axle * Vector3.new(side * 7.2, 0, 0)
			for _, spread in ipairs({ -30, 30 }) do
				strut("FerrisLeg", top, axle * Vector3.new(side * 9, -(FLOOR_DEPTH + FERRIS.hub), spread), 1.9, model)
			end
		end
		strut("FerrisAxle", axle * Vector3.new(-7.6, 0, 0), axle * Vector3.new(7.6, 0, 0), 2.2, model)
	end
	-- THE WHEEL, which the client turns about its part's X.
	local wheel = mesh("Ferris_Wheel")
	if wheel then
		wheel.CFrame = axle
		wheel.Color = paint
		wheel.Material = Enum.Material.Metal
		turning(wheel)
	else
		local rim = Instance.new("Model")
		rim.Name = "FerrisRim"
		local function onRim(side: number, a: number): Vector3
			return axle * Vector3.new(side * 3, math.sin(a) * FERRIS.radius, -math.cos(a) * FERRIS.radius)
		end
		for _, side in ipairs({ -1, 1 }) do
			for index = 0, 23 do
				strut("FerrisRim", onRim(side, 2 * math.pi * index / 24), onRim(side, 2 * math.pi * (index + 1) / 24), 0.9, rim)
			end
			for index = 0, 7 do
				strut("FerrisSpoke", axle * Vector3.new(side * 5, 0, 0), onRim(side, 2 * math.pi * (index + 0.5) / 8), 0.5, rim)
			end
		end
		rim.WorldPivot = axle
		rim.Parent = model
		turning(rim)
	end
	-- THE CABINS, one on every pin, hanging level. Put at rest here; the client moves them.
	local lit = rng:NextInteger(0, FERRIS.cabins - 1)
	for index = 0, FERRIS.cabins - 1 do
		local pin = (axle * CFrame.Angles(2 * math.pi * index / FERRIS.cabins, 0, 0)) * Vector3.new(0, 0, -FERRIS.radius)
		local rest = CFrame.new(pin) * axle.Rotation * CFrame.new(0, -FERRIS.hang, 0)
		local colour = FERRIS.colours[index % #FERRIS.colours + 1]
		-- Part-built, a box whose top is at the pin, so it hangs from something.
		local cabin: BasePart = mesh("Ferris_Gondola")
			or block(model, "FerrisCabin", Vector3.new(3.4, FERRIS.hang * 2, 3), rest, colour, Enum.Material.SmoothPlastic, false)
		cabin.CFrame = rest
		cabin.Color = colour
		turning(cabin, index)
		if index == lit then
			-- Still lit, after everything. A warm lamp in one cabin, going round with it.
			local glow = Instance.new("PointLight")
			glow.Color = Color3.fromRGB(255, 206, 140)
			glow.Brightness = 1.1
			glow.Range = 14
			glow.Shadows = false
			glow.Parent = cabin
			CollectionService:AddTag(cabin, "SunkenLantern")
		end
	end
	return model
end

-- ===== THE LANDMARKS (blender/gen_landmarks.py) =====
--
-- Four tall buildings the skyline is read by: the city was blocks, and blocks from any distance are a
-- field of flat tops. The Deco tower with its brass crown, the Needle with its pod, the Twin towers
-- and their skybridge, and a glass block that has started to go over. Each stands on the sea floor in
-- its own square of open water (`blocked` keeps the city off it), far enough off the route for
-- something that breaks the surface and short of where the things at the back swim (HORROR_OUT):
-- the check holds both. Its meshes share one box and go at one CFrame, front to the street; the
-- leaning one leans away from it. With the meshes not imported, tiers of parts stand in the same
-- place, and the spires' aviation lights are real lights either way.
--
-- Each: `height` is the mesh's (floor to tip), `reach` how far it covers from its middle in plan,
-- `out` how far off the route it stands and `side` which way, `share` where along the street it
-- would like to be, `lean` degrees, `sink` how far its base goes into the sand.
local LANDMARKS = {
	{ name = "Deco", height = 282, reach = 38, share = 0.22, out = 330, side = 1, lean = 0, sink = 0,
		meshes = { { "Landmark_DecoStone", Color3.fromRGB(210, 198, 172), Enum.Material.Concrete, 0 },
			{ "Landmark_DecoGlass", Color3.fromRGB(40, 48, 58), Enum.Material.SmoothPlastic, 0.18 },
			{ "Landmark_DecoCrown", Color3.fromRGB(190, 156, 88), Enum.Material.Metal, 0.1 } },
		plain = { { 44, 0, 160, 0 }, { 36, 160, 196, 0 }, { 28, 196, 220, 0 }, { 20, 220, 252, 0 } },
		tips = { Vector3.new(0, 282.5, 0) } },
	{ name = "Needle", height = 300, reach = 28, share = 0.47, out = 330, side = -1, lean = 0, sink = 0,
		meshes = { { "Landmark_NeedleShaft", Color3.fromRGB(206, 204, 196), Enum.Material.Concrete, 0 },
			{ "Landmark_NeedlePod", Color3.fromRGB(228, 226, 218), Enum.Material.SmoothPlastic, 0.05 },
			{ "Landmark_NeedleGlass", Color3.fromRGB(46, 62, 76), Enum.Material.SmoothPlastic, 0.2 } },
		plain = { { 12, 0, 232, 0 }, { 34, 232, 252, 0 }, { 2.4, 252, 298, 0 } },
		tips = { Vector3.new(0, 300.5, 0) } },
	{ name = "Twin", height = 300, reach = 38, share = 0.68, out = 320, side = 1, lean = 0, sink = 0,
		meshes = { { "Landmark_TwinBody", Color3.fromRGB(178, 184, 190), Enum.Material.Metal, 0.08 },
			{ "Landmark_TwinGlass", Color3.fromRGB(54, 70, 86), Enum.Material.SmoothPlastic, 0.2 } },
		plain = { { 20, 0, 250, -22 }, { 20, 0, 250, 22 } },
		tips = { Vector3.new(-22, 300.5, 0), Vector3.new(22, 300.5, 0) } },
	{ name = "Lean", height = 209, reach = 44, share = 0.86, out = 300, side = -1, lean = 5, sink = 1.5,
		meshes = { { "Landmark_LeanFrame", Color3.fromRGB(188, 188, 182), Enum.Material.Concrete, 0 },
			{ "Landmark_LeanGlass", Color3.fromRGB(78, 106, 126), Enum.Material.SmoothPlastic, 0.25 } },
		plain = { { 32, 0, 205, 0 } },
		tips = {} },
}

-- Stands one. `toward` is the way to the street. Returns its base, on the floor, for anything that
-- goes on it (the one who watches from the Deco tower's ledge).
local function landmark(parent: Instance, spec: any, at: Vector3, toward: Vector3, floorY: number): CFrame
	local model = Instance.new("Model")
	model.Name = "Landmark" .. spec.name
	model.Parent = parent
	local foot = Vector3.new(at.X, floorY, at.Z)
	local base = CFrame.lookAt(foot, foot + Vector3.new(toward.X, 0, toward.Z)) * CFrame.Angles(math.rad(spec.lean), 0, 0)
		* CFrame.new(0, -spec.sink, 0)
	local placed: { Instance } = {}
	local whole = SeaRig ~= nil
	for _, m in ipairs(spec.meshes) do
		local rig = if SeaRig then SeaRig.place(model, m[1]) else nil
		if rig then
			rig.part.CFrame = base * CFrame.new(0, spec.height / 2, 0)
			rig.part.Color = m[2]
			rig.part.Material = m[3]
			rig.part.Reflectance = m[4]
			rig.part.CastShadow = true
			table.insert(placed, rig.model)
		else
			whole = false
		end
	end
	if not whole then
		for _, item in ipairs(placed) do
			item:Destroy()
		end
		for _, tier in ipairs(spec.plain) do
			block(model, "Landmark", Vector3.new(tier[1], tier[3] - tier[2], tier[1]),
				base * CFrame.new(tier[4], (tier[2] + tier[3]) / 2, 0), spec.meshes[1][2], Enum.Material.Concrete, false)
		end
	end
	for _, tip in ipairs(spec.tips) do
		local beacon = block(model, "AviationLight", Vector3.new(1, 1, 1), base * CFrame.new(tip),
			Color3.fromRGB(220, 60, 50), Enum.Material.Glass, false)
		local red = Instance.new("PointLight")
		red.Brightness = 1.4
		red.Range = 24
		red.Color = Color3.fromRGB(255, 70, 50)
		red.Shadows = false
		red.Parent = beacon
		CollectionService:AddTag(beacon, "SunkenBlink")
	end
	return base
end

-- A STRAND OF KELP: a holdfast gripping the floor, and a marker saying how tall the strand is and
-- which way the current leans it. The client grows the stipe, the blades and the floats from it and
-- sways the whole thing, top most, a wave running up it (SunkenCityClient).
--
-- `current` is the way the water runs where it stands (down the street, or along the tank), which
-- a mesh strand leans and streams its canopy along; `canopy` says it may have one. The street's
-- strands do; the tank's do not, because a canopy there would lie over the tunnel's roof.
local function kelp(parent: Instance, foot: Vector3, height: number, rng: Random, current: Vector3?, canopy: boolean?)
	local hold = ellipsoid(parent, "Holdfast", Vector3.new(2.8, 1.4, 2.8), CFrame.new(foot + Vector3.new(0, 0.4, 0))
		* CFrame.Angles(0, rng:NextNumber(0, 6), 0), drowned(Color3.fromRGB(84, 72, 44), foot.Y))
	hold.Material = Enum.Material.SmoothPlastic
	local marker = block(parent, "Kelp", Vector3.new(1, 1, 1), CFrame.new(foot), SURFACE, Enum.Material.SmoothPlastic, false)
	marker.Transparency = 1
	marker:SetAttribute("Height", height)
	marker:SetAttribute("Phase", rng:NextNumber(0, 100))
	-- One current through the whole city, a strand a little either side of it: a bed of kelp all
	-- leaning its own way is a bed of kelp with no water in it.
	marker:SetAttribute("Lean", 0.7 + rng:NextNumber(-0.4, 0.4))
	if current then
		marker:SetAttribute("Along", current)
	end
	marker:SetAttribute("Canopy", canopy == true)
	CollectionService:AddTag(marker, "SunkenKelp")
end

-- ===== THE SIDE STREETS =====
--
-- The cross streets between the blocks, which were water with nothing in them. Now: utility poles
-- down one side of every other one, their wires sagging between them over the water; boats in the
-- others, moored along the kerb, a few turned over (gen_boats.py; SunkenBuoy, so they bob); and at
-- every corner on the boulevard a street sign, the street's name on one blade and the boulevard's on
-- the other. Everything here that stands out of the water is past EMERGE_CLEAR of the route's reach.
local STREET_NAMES = { "HARBOUR ST", "ALBERT RD", "MARKET ST", "QUAY LANE", "BRIDGE ST", "CHAPEL ROW", "MILL LANE",
	"NORTH PARADE", "ELM ST", "WATER LANE", "STATION RD", "KING ST", "ROPEWALK", "TIDE ST" }

-- A boat at `at`, which is on the water's surface, heading along its Z. Its model is a buoy.
function streetKit.boat(parent: Instance, at: CFrame, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = "Boat"
	local pick = rng:NextNumber()
	local kind = if pick < 0.5 then "row" elseif pick < 0.82 then "launch" else "capsized"
	local frame = if kind == "capsized" then at * CFrame.Angles(0, 0, math.pi) else at
	local specs = if kind == "row" then { { "Boat_Row", Color3.fromRGB(150, 112, 74), Enum.Material.WoodPlanks } }
		else { { "Boat_LaunchHull", FADED[rng:NextInteger(1, #FADED)]:Lerp(Color3.new(1, 1, 1), 0.55), Enum.Material.SmoothPlastic },
			{ "Boat_LaunchTop", Color3.fromRGB(46, 64, 98), Enum.Material.SmoothPlastic } }
	local whole = SeaRig ~= nil
	local placed: { Instance } = {}
	for _, spec in ipairs(specs) do
		local rig = if SeaRig then SeaRig.place(model, spec[1]) else nil
		if rig then
			rig.part.CFrame = frame
			rig.part.Color = spec[2]
			rig.part.Material = spec[3]
			table.insert(placed, rig.model)
		else
			whole = false
		end
	end
	if not whole then
		for _, item in ipairs(placed) do
			item:Destroy()
		end
		local long = if kind == "row" then 8 else 16
		local hullColour = if kind == "row" then Color3.fromRGB(150, 112, 74) else Color3.fromRGB(220, 220, 212)
		block(model, "Hull", Vector3.new(if kind == "row" then 3 else 5.2, 1.8, long), frame * CFrame.new(0, 0.2, 0), hullColour,
			Enum.Material.SmoothPlastic, false)
		if kind ~= "row" then
			block(model, "Cabin", Vector3.new(4, 2.2, 6), frame * CFrame.new(0, 2.2, 2.2), Color3.fromRGB(46, 64, 98),
				Enum.Material.SmoothPlastic, false)
		end
	end
	model.WorldPivot = at
	model.Parent = parent
	CollectionService:AddTag(model, "SunkenBuoy")
	return model
end

function streetKit.sideStreets(parent: Instance, route: Route, floorY: number, rng: Random,
	blocked: (Vector3, number) -> boolean): number
	local pitch = BLOCK + STREET
	local from = -CITY_BEYOND
	local rows = math.max(1, math.floor((route.total + 2 * CITY_BEYOND) / pitch))
	local reachable = route.total - harbourAlong(route)
	local wood, wire, metal = Color3.fromRGB(104, 84, 64), Color3.fromRGB(30, 32, 34), Color3.fromRGB(90, 96, 100)
	local things = 0
	for row = 1, rows do
		local s = from + row * pitch
		local line = route.points[1] + route.forward * s
		local named = STREET_NAMES[(row - 1) % #STREET_NAMES + 1]
		for _, sign in ipairs({ -1, 1 }) do
			local poles: { Vector3 } = {}
			local cornered = false
			local boats = 0
			for step = 0, 110 do
				local across = sign * step * 3
				local spot = line + route.side * across
				local near = nearRoute(route, spot)
				if alongOf(route, spot) > reachable then
					continue
				end
				-- THE CORNER, where the street meets the boulevard's pavement: the sign.
				if not cornered and near >= BOULEVARD_HALF + 2 and near <= BOULEVARD_HALF + 6 then
					cornered = true
					local post = spot + route.forward * (STREET / 2 + 1.2)
					if not blocked(post, 3) then
						column(parent, "SignPost", 0.5, post, floorY, waterLevel + 7, metal, false)
						for index, words in ipairs({ named, "SEA BOULEVARD" }) do
							local blade = block(parent, "StreetSign", Vector3.new(0.2, 1, 5),
								CFrame.fromMatrix(post + Vector3.new(0, waterLevel + 6.2 - index * 1.2 - post.Y, 0),
									if index == 1 then route.forward else route.side, Vector3.yAxis)
									* CFrame.new(0, 0, 0), Color3.fromRGB(38, 92, 62), Enum.Material.SmoothPlastic, false)
							label(blade, Enum.NormalId.Right, words, Color3.fromRGB(236, 240, 232))
							label(blade, Enum.NormalId.Left, words, Color3.fromRGB(236, 240, 232))
						end
						things += 1
					end
				end
				-- Poles every 36 studs down one side, from past the pavement to 250 out.
				if row % 2 == 0 and near >= 70 and near <= 250 and step % 12 == 0 then
					local foot = spot + route.forward * (STREET / 2 - 2)
					if not blocked(foot, 4) then
						table.insert(poles, foot)
					end
				end
				-- Boats in the other streets, moored along a kerb.
				if row % 2 == 1 and near >= 80 and near <= 300 and boats < 2 and step % 9 == 0 and rng:NextNumber() < 0.35 then
					local where = spot + route.forward * (rng:NextNumber(-7, 7))
					if not blocked(where, 10) then
						local heading = CFrame.lookAt(Vector3.new(where.X, waterLevel, where.Z),
							Vector3.new(where.X, waterLevel, where.Z) + route.side * sign)
						streetKit.boat(parent, heading * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), rng)
						boats += 1
						things += 1
					end
				end
			end
			-- The poles, and the wires between each pair that stand next to each other.
			local top = waterLevel + 12
			for index, foot in ipairs(poles) do
				column(parent, "UtilityPole", 0.9, foot, floorY, top, wood, false, true)
				local arm = CFrame.fromMatrix(Vector3.new(foot.X, top - 1, foot.Z), route.forward, Vector3.yAxis)
				block(parent, "Crossarm", Vector3.new(5.4, 0.4, 0.4), arm, wood, Enum.Material.Wood, false)
				if index % 3 == 0 then
					column(parent, "Transformer", 1.6, foot + route.forward * 0.9, top - 5, top - 2.6, metal, false)
				end
				local after = poles[index + 1]
				if after and (after - foot).Magnitude < 40 then
					for _, off in ipairs({ -2.2, 2.2 }) do
						local a = Vector3.new(foot.X, top - 0.7, foot.Z) + route.forward * off
						local b = Vector3.new(after.X, top - 0.7, after.Z) + route.forward * off
						local points = { a }
						for k = 1, 2 do
							local t = k / 3
							table.insert(points, a:Lerp(b, t) - Vector3.new(0, 1.4 * 4 * t * (1 - t), 0))
						end
						table.insert(points, b)
						for k = 1, #points - 1 do
							rod(parent, "Wire", points[k], points[k + 1], 0.12, wire)
						end
					end
				end
				things += 1
			end
		end
	end
	return things
end

-- THE METRO: a totem on the boulevard's pavement with the M on it, which is how you know the street
-- had a station under it. The entrance is a hundred studs down with the street; the totem is what
-- stands up out of the water.
function streetKit.metro(parent: Instance, route: Route, floorY: number, rng: Random, blocked: (Vector3, number) -> boolean,
	alongs: { number }): number
	local made = 0
	for index, share in ipairs({ 0.3, 0.64 }) do
		local s = route.total * share
		local clear = true
		for _, g in ipairs(alongs) do
			if math.abs(g - s) < 30 then
				clear = false
			end
		end
		local at, dir = alongRoute(route, s)
		local side = Vector3.yAxis:Cross(dir)
		local foot = at + side * ((if index % 2 == 0 then 1 else -1) * (BOULEVARD_HALF + 3))
		if clear and not blocked(foot, 6) and nearRoute(route, foot) - 1 >= EMERGE_CLEAR + ROUTE_REACH then
			column(parent, "MetroTotem", 0.9, foot, floorY, waterLevel + 9, Color3.fromRGB(70, 74, 80), false)
			local face = CFrame.fromMatrix(Vector3.new(foot.X, waterLevel + 9.8, foot.Z), dir, Vector3.yAxis)
			local disc = block(parent, "MetroSign", Vector3.new(0.5, 3.2, 3.2), face, Color3.fromRGB(196, 44, 40),
				Enum.Material.SmoothPlastic, false)
			disc.Shape = Enum.PartType.Cylinder
			local board = block(parent, "MetroBoard", Vector3.new(4.4, 1.1, 0.3),
				CFrame.fromMatrix(Vector3.new(foot.X, waterLevel + 7.6, foot.Z), dir, Vector3.yAxis),
				Color3.fromRGB(28, 44, 96), Enum.Material.SmoothPlastic, false)
			label(board, Enum.NormalId.Front, "METRO", Color3.fromRGB(236, 238, 242))
			label(board, Enum.NormalId.Back, "METRO", Color3.fromRGB(236, 238, 242))
			label(disc, Enum.NormalId.Right, "M", Color3.fromRGB(246, 244, 238))
			label(disc, Enum.NormalId.Left, "M", Color3.fromRGB(246, 244, 238))
			made += 1
		end
	end
	return made
end

-- ===== THE BOULEVARD ITSELF =====
--
-- The street the route runs down, which is the one part of the city you are actually in. Kerbs
-- either side under the water, tram rails down the middle of it, lamp posts whose heads come up
-- through the surface, and the cars that never got out. All of it under you and read through the
-- water, which is why the lamps are the only things here that break it.
local function boulevard(parent: Instance, route: Route, floorY: number, rng: Random, blocked: (Vector3, number) -> boolean,
	alongs: { number })
	local reachable = route.total - harbourAlong(route)
	-- Nothing wide stands where a road sign's legs come down.
	local function byGantry(s: number): boolean
		for _, g in ipairs(alongs) do
			if math.abs(g - s) < 24 then
				return true
			end
		end
		return false
	end
	local tramAt = route.total * 0.46
	while byGantry(tramAt) and tramAt < reachable do
		tramAt += 10
	end
	local step = 30
	local count = math.floor(route.total / step)
	local roadY = floorY + 0.8
	for index = 0, count do
		local s = index * step
		local at, dir = alongRoute(route, s)
		local side = Vector3.yAxis:Cross(dir)
		local mid = Vector3.new(at.X, roadY, at.Z)
		local facing = CFrame.lookAt(mid, mid + dir)
		-- The road surface, and a kerb either side of it.
		block(parent, "Road", Vector3.new(BOULEVARD_HALF * 2, 1.4, step + 1), facing, drowned(Color3.fromRGB(82, 86, 84), roadY),
			Enum.Material.Concrete, false)
		for _, sign in ipairs({ -1, 1 }) do
			block(parent, "Kerb", Vector3.new(3, 2, step + 1), facing * CFrame.new(sign * BOULEVARD_HALF, 0.8, 0),
				drowned(Color3.fromRGB(150, 148, 140), roadY), Enum.Material.Concrete, false)
		end
		-- Tram rails down the middle, a pair of thin bright lines in all that silt.
		for _, rail in ipairs({ -3.2, 3.2 }) do
			block(parent, "TramRail", Vector3.new(0.5, 0.4, step + 1), facing * CFrame.new(rail, 1.1, 0),
				Color3.fromRGB(120, 116, 104), Enum.Material.Metal, false)
		end
		-- LAMP POSTS, alternating sides, their lanterns out of the water. The one thing down here
		-- with a light still in it, and only every eighth one: a street of lit lamps would be a
		-- party, and a street where one in eight still burns is something else.
		-- NOTHING STANDS THROUGH THE AQUARIUM OR THE FLAT. A lamp post, like a building, is kept out of
		-- what they claim; before this, one in a dozen runs put a post through the tunnel.
		local lampSign = if index % 4 == 0 then 1 else -1
		if index % 2 == 0 and not blocked(at + side * (lampSign * (BOULEVARD_HALF - 2)), 4) then
			local sign = lampSign
			local foot = at + side * (sign * (BOULEVARD_HALF - 2))
			local top = waterLevel + 7
			local iron = drowned(Color3.fromRGB(64, 70, 72), waterLevel)
			column(parent, "LampPost", 1.1, Vector3.new(foot.X, floorY, foot.Z), floorY, top, iron, false)
			-- A collar where it comes out of the water, and a ring of weed on it.
			column(parent, "LampCollar", 1.6, Vector3.new(foot.X, 0, foot.Z), waterLevel - 0.6, waterLevel + 0.6,
				iron, false)
			column(parent, "LampWeed", 2.2, Vector3.new(foot.X, 0, foot.Z), waterLevel - 0.3, waterLevel + 0.2,
				Color3.fromRGB(74, 104, 62), false)
			-- The arm: up and out over the street, with a scroll where it leaves the post.
			local root = Vector3.new(foot.X, top - 0.4, foot.Z)
			local tip = root - side * (sign * 3.2) + Vector3.new(0, 0.6, 0)
			rod(parent, "LampArm", root, tip, 0.35, Color3.fromRGB(64, 70, 72))
			rod(parent, "LampBrace", root - Vector3.new(0, 1.4, 0), root - side * (sign * 1.6), 0.25,
				Color3.fromRGB(64, 70, 72))
			ellipsoid(parent, "LampScroll", Vector3.new(0.6, 0.6, 0.6), CFrame.new(root - side * (sign * 0.9)
				- Vector3.new(0, 0.6, 0)), Color3.fromRGB(64, 70, 72))
			rod(parent, "LampHanger", tip, tip - Vector3.new(0, 0.6, 0), 0.15, Color3.fromRGB(46, 50, 52))
			local lit = index % 8 == 0
			local glass = lantern(parent, CFrame.new(tip - Vector3.new(0, 1.8, 0)), lit, Color3.fromRGB(255, 226, 170))
			if lit then
				sound(glass, "LampBuzz", THUD_SOUND, 0.12, 0.05, 30, true)
			end
		end
		-- A CAR now and then, stopped where the water caught it.
		-- VEHICLES, where they stopped: in the lanes either side of the rails, the big ones nearer the
		-- middle where there is room for them, none where a road sign's legs come down.
		if not byGantry(s) then
			for _ = 1, if rng:NextNumber() < 0.25 then 2 else 1 do
				if rng:NextNumber() < 0.5 then
					local laneSide = if rng:NextNumber() < 0.5 then -1 else 1
					local big = rng:NextNumber() < 0.35
					local lane = laneSide * (if big then rng:NextNumber(10, 22) else rng:NextNumber(10, ROADSIDE.vehicleLane))
					if not blocked(at + side * lane, 18) then
						streetKit.car(parent, facing * CFrame.new(lane, 1.4, rng:NextNumber(-step / 3, step / 3))
							* CFrame.Angles(0, rng:NextNumber(-0.25, 0.25), 0), rng, big)
					end
				end
			end
		end
		if math.abs(s - tramAt) < step / 2 then
			streetKit.tram(parent, facing * CFrame.new(0, 1.4, s - tramAt) * CFrame.Angles(0, 0.06, 0))
		end
		-- FURNITURE on the pavement edge, on the side the lamp is not.
		if index % 2 == 0 and rng:NextNumber() < 0.7 and not byGantry(s) then
			local sign = if index % 4 == 0 then -1 else 1
			local spot = at + side * (sign * ROADSIDE.furnitureAt) + dir * rng:NextNumber(-6, 6)
			if not blocked(spot, 6) then
				streetKit.furniture(parent, CFrame.lookAt(Vector3.new(spot.X, roadY + 0.7, spot.Z), Vector3.new(spot.X, roadY + 0.7, spot.Z) - side * sign), rng)
			end
		end
		-- THE REEF the street has become, in patches either side of the rails.
		for _ = 1, 2 do
			local spot = at + side * ((if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(7, 46)) + dir * rng:NextNumber(-step / 2, step / 2)
			if not blocked(spot, 4) then
				streetKit.reef(parent, Vector3.new(spot.X, roadY + 0.7, spot.Z), rng)
			end
		end
		if s < reachable then
			-- KELP BEDS along the kerbs, halfway between one lamp post and the next, on alternating
			-- sides: two or three strands from the road to just under the surface, which is what
			-- you see from the route -- fronds moving at the top of the water.
			if index % 2 == 1 then
				local sign = if index % 4 == 1 then 1 else -1
				local bed = at + side * (sign * KELP_KERB)
				if not blocked(bed, 10) then
					for strand = 1, if rng:NextNumber() < 0.4 then 3 else 2 do
						local foot = bed + dir * ((strand - 2) * 3 + rng:NextNumber(-0.8, 0.8)) + side * rng:NextNumber(-1, 1)
						kelp(parent, Vector3.new(foot.X, floorY + 0.5, foot.Z), waterLevel - rng:NextNumber(1.5, 4) - floorY - 0.5, rng,
							dir, true)
					end
					-- BUBBLES out of the bed, all the way up: the one sign from the route that the floor
					-- a hundred studs down is alive.
					if rng:NextNumber() < 0.6 then
						local vent = block(parent, "BubbleVent", Vector3.new(1, 1, 1), CFrame.new(bed.X, floorY + 1, bed.Z), SURFACE,
							Enum.Material.SmoothPlastic, false)
						vent.Transparency = 1
						local rise = Instance.new("ParticleEmitter")
						rise.Name = "Bubbles"
						rise.Texture = "rbxasset://textures/particles/sparkles_main.dds"
						rise.Color = ColorSequence.new(Color3.fromRGB(226, 242, 240))
						rise.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.7) })
						rise.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.9, 0.5),
							NumberSequenceKeypoint.new(1, 1) })
						rise.Lifetime = NumberRange.new(16, 19)
						rise.Speed = NumberRange.new(5.5, 6.5)
						rise.EmissionDirection = Enum.NormalId.Top
						rise.SpreadAngle = Vector2.new(4, 4)
						rise.Rate = 1.6
						rise.Parent = vent
					end
				end
			end
			-- FLOTSAM, afloat in the open water under the route and bobbing (the client bobs anything
			-- tagged SunkenBuoy): planks, a crate, a barrel, a ball, and now and then a child's rubber
			-- duck, which is the one that stops people.
			if rng:NextNumber() < 0.34 then
				local spot = at + side * ((if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(12, 32))
					+ dir * rng:NextNumber(-10, 10)
				if not blocked(spot, 4) then
					local float = Instance.new("Model")
					float.Name = "Flotsam"
					local turn = CFrame.new(spot.X, waterLevel, spot.Z) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
					local pick = rng:NextNumber()
					if pick < 0.06 then
						local yellow = Color3.fromRGB(244, 204, 70)
						ellipsoid(float, "DuckBody", Vector3.new(1.6, 1.1, 2), turn * CFrame.new(0, 0.2, 0), yellow)
						ellipsoid(float, "DuckHead", Vector3.new(1, 1, 1), turn * CFrame.new(0, 0.95, -0.6), yellow)
						ellipsoid(float, "DuckBeak", Vector3.new(0.5, 0.25, 0.6), turn * CFrame.new(0, 0.85, -1.15),
							Color3.fromRGB(236, 124, 50))
					elseif pick < 0.4 then
						for plank = 0, rng:NextInteger(1, 2) do
							block(float, "Plank", Vector3.new(0.9, 0.3, rng:NextNumber(4, 7)), turn * CFrame.new(plank * 1.1, 0.05, plank * 0.8)
								* CFrame.Angles(0, plank * 0.4, 0), Color3.fromRGB(120, 96, 70), Enum.Material.WoodPlanks, false)
						end
					elseif pick < 0.62 then
						block(float, "Crate", Vector3.new(2.4, 2.4, 2.4), turn * CFrame.new(0, 0.3, 0) * CFrame.Angles(0.2, 0, 0.15),
							Color3.fromRGB(146, 116, 78), Enum.Material.WoodPlanks, false)
					elseif pick < 0.84 then
						local barrel = block(float, "Barrel", Vector3.new(3.2, 2, 2), turn * CFrame.new(0, 0.2, 0),
							FADED[rng:NextInteger(1, #FADED)], Enum.Material.Metal, false)
						barrel.Shape = Enum.PartType.Cylinder
					else
						local ball = ellipsoid(float, "Ball", Vector3.new(1.4, 1.4, 1.4), turn * CFrame.new(0, 0.3, 0),
							Color3.fromRGB(210, 80, 70))
						ball.Material = Enum.Material.SmoothPlastic
					end
					float.Parent = parent
					CollectionService:AddTag(float, "SunkenBuoy")
				end
			end
			-- WEED MATS on the surface along the kerbs, where the drift gathers.
			if rng:NextNumber() < 0.3 then
				local mat = at + side * ((if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(40, 52))
				if not blocked(mat, 6) then
					local across = rng:NextNumber(3, 8)
					local weed = block(parent, "WeedMat", Vector3.new(0.12, across, across * rng:NextNumber(0.7, 1)),
						CFrame.new(mat.X, waterLevel + 0.25, mat.Z) * CFrame.Angles(0, rng:NextNumber(0, 6), math.pi / 2),
						Color3.fromRGB(88, 112, 60), Enum.Material.Grass, false)
					weed.Shape = Enum.PartType.Cylinder
					weed.Transparency = 0.15
					weed.CastShadow = false
				end
			end
		end
	end
end

-- ===== THE PLAZA AND THE CLOCK TOWER =====
--
-- Stopped at twelve minutes past four, which is when the water came. The minute hands are tagged so
-- SunkenCityClient can make them try, now and then, to move on.
local function clockTower(parent: Instance, centre: Vector3, floorY: number)
	-- Placed beside the route rather than at the middle of a ring: the city has no middle now, it
	-- has a street, and this is the landmark off it.
	--
	-- BUILT IN STAGES, the way a clock tower is: a shaft of dressed stone with quoins at the corners
	-- and tall arched windows, a wider clock stage with a face on every side, an open belfry with the
	-- bell still hanging in it, pinnacles, and a copper spire gone green with a weathervane on top.
	-- The bell is tagged: every so often it tolls, once, and nobody is up there (SunkenCityClient).
	local rng = Random.new(412)
	column(parent, "Plaza", PLAZA_RADIUS * 2, centre, floorY, floorY + 0.6, Color3.fromRGB(120, 116, 106), false)
	local side = 22
	local shaftTop = waterLevel + 26
	local clockTop = waterLevel + 40
	local belfryTop = waterLevel + 52
	local stone = STONE
	local light = Color3.fromRGB(204, 198, 182)
	local copper = Color3.fromRGB(96, 150, 128)
	local at = function(y: number): CFrame
		return CFrame.new(centre.X, y, centre.Z)
	end
	-- THE SHAFT.
	cityBlock(parent, "ClockTower", Vector3.new(side, shaftTop - floorY, side), at((floorY + shaftTop) / 2), stone)
	for _, corner in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		cityBlock(parent, "Quoin", Vector3.new(1.6, shaftTop - (waterLevel - 20), 1.6),
			at((shaftTop + waterLevel - 20) / 2) * CFrame.new(corner[1] * side / 2, 0, corner[2] * side / 2), light)
	end
	for y = waterLevel - 16, shaftTop - 2, 8 do
		cityBlock(parent, "StringCourse", Vector3.new(side + 0.8, 0.7, side + 0.8), at(y), light)
	end
	-- Tall arched windows on every face, above the water: a dark recess with a round head.
	for index = 0, 3 do
		local normal = Vector3.new(math.cos(index * math.pi / 2), 0, math.sin(index * math.pi / 2))
		local mid = Vector3.new(centre.X, waterLevel + 11, centre.Z) + normal * (side / 2 + 0.05)
		local facing = CFrame.lookAt(mid, mid + normal)
		cityBlock(parent, "ArchWindow", Vector3.new(4, 10, 0.4), facing, Color3.fromRGB(26, 32, 36), Enum.Material.Glass)
		local head = block(parent, "ArchHead", Vector3.new(0.4, 4, 4), facing * CFrame.new(0, 5, 0)
			* CFrame.Angles(0, math.pi / 2, 0), drowned(Color3.fromRGB(26, 32, 36), waterLevel + 16), Enum.Material.Glass,
			false)
		head.Shape = Enum.PartType.Cylinder
		cityBlock(parent, "ArchSurround", Vector3.new(5.4, 0.8, 0.5), facing * CFrame.new(0, -5.2, 0.05), light)
	end

	-- THE CLOCK STAGE, a little wider than the shaft, with a cornice under and over it.
	cityBlock(parent, "ClockStage", Vector3.new(side + 2, clockTop - shaftTop, side + 2), at((shaftTop + clockTop) / 2), stone)
	cityBlock(parent, "Cornice", Vector3.new(side + 3.4, 1.2, side + 3.4), at(shaftTop), light)
	cityBlock(parent, "Cornice", Vector3.new(side + 3.4, 1.4, side + 3.4), at(clockTop), light)
	local faceY = (shaftTop + clockTop) / 2
	for index = 0, 3 do
		local normal = Vector3.new(math.cos(index * math.pi / 2), 0, math.sin(index * math.pi / 2))
		local faceAt = Vector3.new(centre.X, faceY, centre.Z) + normal * (side / 2 + 1.3)
		-- The bezel, the face, and twelve marks round its rim.
		local bezel = block(parent, "ClockBezel", Vector3.new(0.5, 12.4, 12.4),
			CFrame.lookAt(faceAt, faceAt + normal) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(58, 62, 64),
			Enum.Material.Metal, false)
		bezel.Shape = Enum.PartType.Cylinder
		local faceCentre = faceAt + normal * 0.2
		local face = block(parent, "ClockFace", Vector3.new(0.4, 11, 11),
			CFrame.lookAt(faceCentre, faceCentre + normal) * CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(232, 228, 214),
			Enum.Material.SmoothPlastic, false)
		face.Shape = Enum.PartType.Cylinder
		local pivot = CFrame.lookAt(faceCentre, faceCentre - normal)
		for hour = 0, 11 do
			local a = hour * math.pi / 6
			block(parent, "ClockMark", Vector3.new(if hour % 3 == 0 then 0.5 else 0.3, if hour % 3 == 0 then 1.4 else 0.9, 0.15),
				pivot * CFrame.Angles(0, 0, -a) * CFrame.new(0, 4.4, 0.3), Color3.fromRGB(40, 40, 44), Enum.Material.Metal,
				false)
		end
		-- 4:12. Clockwise, seen from in front, is a negative turn about the face's outward normal.
		local hourHand = block(parent, "HourHand", Vector3.new(0.7, 3.2, 0.2),
			pivot * CFrame.Angles(0, 0, -math.rad(126)) * CFrame.new(0, 1.6, 0.45), Color3.fromRGB(30, 30, 34),
			Enum.Material.Metal, false)
		hourHand:SetAttribute("Pivot", pivot)
		local minute = block(parent, "MinuteHand", Vector3.new(0.5, 4.6, 0.2),
			pivot * CFrame.Angles(0, 0, -math.rad(72)) * CFrame.new(0, 2.3, 0.55), Color3.fromRGB(30, 30, 34),
			Enum.Material.Metal, false)
		minute:SetAttribute("Pivot", pivot)
		CollectionService:AddTag(minute, "SunkenClockHand")
		ellipsoid(parent, "ClockBoss", Vector3.new(0.9, 0.9, 0.9), pivot * CFrame.new(0, 0, 0.6), Color3.fromRGB(30, 30, 34))
	end

	-- THE BELFRY: four piers and the arches between them, open to the air, with the bell in it.
	local belfryMid = (clockTop + belfryTop) / 2
	for _, corner in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		cityBlock(parent, "BelfryPier", Vector3.new(4, belfryTop - clockTop, 4),
			at(belfryMid) * CFrame.new(corner[1] * (side / 2 - 2), 0, corner[2] * (side / 2 - 2)), stone)
	end
	for index = 0, 3 do
		local normal = Vector3.new(math.cos(index * math.pi / 2), 0, math.sin(index * math.pi / 2))
		local lintelAt = Vector3.new(centre.X, belfryTop - 1.5, centre.Z) + normal * (side / 2 - 2)
		cityBlock(parent, "BelfryLintel", Vector3.new(side, 3, 4), CFrame.lookAt(lintelAt, lintelAt + normal)
			* CFrame.Angles(0, math.pi / 2, 0), stone)
		-- The louvres in the lower half of each opening, which is how the sound gets out.
		for louvre = 0, 3 do
			local y = clockTop + 1.5 + louvre * 1.4
			local louvreAt = Vector3.new(centre.X, y, centre.Z) + normal * (side / 2 - 2)
			cityBlock(parent, "Louvre", Vector3.new(side - 8, 0.3, 1.8), CFrame.lookAt(louvreAt, louvreAt + normal)
				* CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.rad(-25)), Color3.fromRGB(88, 76, 62),
				Enum.Material.WoodPlanks)
		end
	end
	cityBlock(parent, "BelfryFloor", Vector3.new(side, 1, side), at(clockTop + 0.5), stone)
	cityBlock(parent, "BelfryRoof", Vector3.new(side + 2, 1.2, side + 2), at(belfryTop + 0.6), light)
	-- THE BELL, on its headstock, still hanging. Tagged so the client can toll it.
	local bellBeam = cityBlock(parent, "Headstock", Vector3.new(side - 6, 1.2, 1.2), at(belfryTop - 3.5),
		Color3.fromRGB(96, 76, 58), Enum.Material.Wood)
	local bell = ellipsoid(parent, "Bell", Vector3.new(6, 6.5, 6), at(belfryTop - 7.6), Color3.fromRGB(146, 116, 66))
	bell.Material = Enum.Material.Metal
	bell:SetAttribute("Hang", bellBeam.CFrame)
	CollectionService:AddTag(bell, "SunkenBell")
	column(parent, "BellLip", 7, bell.Position - Vector3.new(0, 3.2, 0), bell.Position.Y - 3.6, bell.Position.Y - 2.8,
		Color3.fromRGB(130, 104, 60), false)

	-- PINNACLES at the four corners, and the SPIRE: copper gone green, in shrinking courses.
	for _, corner in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		local base = at(belfryTop + 1.2) * CFrame.new(corner[1] * (side / 2 - 1.4), 0, corner[2] * (side / 2 - 1.4))
		for step = 0, 3 do
			cityBlock(parent, "Pinnacle", Vector3.new(2.6 - step * 0.6, 1.6, 2.6 - step * 0.6), base * CFrame.new(0, 0.8 + step * 1.6, 0),
				light)
		end
	end
	local courses = 8
	for step = 0, courses - 1 do
		local size = (side - 2) * (1 - step / courses)
		cityBlock(parent, "Spire", Vector3.new(size, 3, size), at(belfryTop + 2.7 + step * 3), copper:Lerp(Color3.fromRGB(70, 110, 96),
			step / courses))
	end
	local vaneFoot = Vector3.new(centre.X, belfryTop + 1.2 + courses * 3, centre.Z)
	column(parent, "VaneRod", 0.3, vaneFoot, vaneFoot.Y, vaneFoot.Y + 7, Color3.fromRGB(58, 62, 64), false, true)
	cityBlock(parent, "VaneArrow", Vector3.new(4.2, 0.25, 0.25), CFrame.new(vaneFoot + Vector3.new(0, 6, 0))
		* CFrame.Angles(0, math.rad(35), 0), Color3.fromRGB(58, 62, 64), Enum.Material.Metal)
	for _, a in ipairs({ 0, math.pi / 2 }) do
		cityBlock(parent, "VaneCross", Vector3.new(2.4, 0.18, 0.18), CFrame.new(vaneFoot + Vector3.new(0, 4.8, 0))
			* CFrame.Angles(0, a, 0), Color3.fromRGB(58, 62, 64), Enum.Material.Metal)
	end

	-- And what the water and the weather have done to it, the same as everything else.
	dress(parent, CFrame.new(centre.X, floorY, centre.Z), side, side, belfryTop, stone, rng, 2)
end

-- ===== THE BOULEVARD'S ROAD SIGNS =====
--
-- Gantries across the street under the route, their signs a few studs down: the one thing on the
-- boulevard you can read from the route, and the last thing you read before the harbour. The thing
-- swims under them and never surfaces there. Placed at shares ALONG the route, which is the only
-- measurement a street has.
local function gantries(parent: Instance, route: Route, floorY: number, alongs: { number })
	local names = { "CITY CENTRE", "HARBOUR", "AQUARIUM", "CLOCK TOWER", "ALL ROUTES" }
	for index, s in ipairs(alongs) do
		local at, dir = alongRoute(route, s)
		local side = Vector3.yAxis:Cross(dir)
		local beamY = waterLevel - 4.5
		for _, sign in ipairs({ -1, 1 }) do
			local foot = at + side * (sign * 38)
			column(parent, "GantryLeg", 1.4, Vector3.new(foot.X, floorY, foot.Z), floorY, beamY,
				Color3.fromRGB(110, 116, 120), false)
		end
		local mid = Vector3.new(at.X, beamY, at.Z)
		local frame = CFrame.fromMatrix(mid, side, Vector3.yAxis)
		cityBlock(parent, "GantryBeam", Vector3.new(78, 1.4, 1.4), frame, Color3.fromRGB(110, 116, 120), Enum.Material.Metal)
		local panel = cityBlock(parent, "RoadSign", Vector3.new(22, 6, 0.4), frame * CFrame.new(-8, -3.7, 0),
			Color3.fromRGB(30, 96, 70))
		label(panel, Enum.NormalId.Front, names[(index - 1) % #names + 1], Color3.fromRGB(226, 232, 226))
		label(panel, Enum.NormalId.Back, names[index % #names + 1], Color3.fromRGB(226, 232, 226))
		-- A hanging traffic signal beside the sign, dead.
		local signal = cityBlock(parent, "Signal", Vector3.new(1.6, 4.4, 1.6), frame * CFrame.new(16, -3.4, 0),
			Color3.fromRGB(46, 50, 52))
		-- The loop's counter is not called `lamp`: this file declares a lamp() further down and the
		-- Luau check reads a local of that name here as shadowing it before it exists.
		for bulb = 0, 2 do
			local tone = if bulb == 0 then Color3.fromRGB(120, 40, 36) elseif bulb == 1 then Color3.fromRGB(120, 100, 40)
				else Color3.fromRGB(40, 110, 60)
			cityBlock(parent, "SignalLamp", Vector3.new(0.5, 1, 1), signal.CFrame * CFrame.new(0.9, 1.4 - bulb * 1.4, 0),
				drowned(tone, signal.Position.Y))
		end
	end
end

-- ===== THE HARBOUR =====
--
-- The end of the street: the water opens out, the blocks stop, and what is left is the working
-- edge of a port with nothing working in it. Built in the frame of the route's last stretch, so
-- the quays run away either side of the pier and everything faces the water you are about to be
-- pulled into.
local function harbour(parent: Instance, route: Route, vortex: Vector3, floorY: number, rng: Random)
	local at, dir = alongRoute(route, route.total)
	local side = Vector3.yAxis:Cross(dir)
	local frame = CFrame.fromMatrix(Vector3.new(at.X, floorY, at.Z), dir, Vector3.yAxis)
	local quayTop = waterLevel + 3

	-- QUAY WALLS either side of the basin, running back along the street's last stretch.
	for _, sign in ipairs({ -1, 1 }) do
		local wall = frame * CFrame.new(-190, (quayTop - floorY) / 2, sign * HARBOUR_REACH * 0.62)
		block(parent, "Quay", Vector3.new(420, quayTop - floorY, 10), wall, drowned(STONE, floorY + 10),
			Enum.Material.Concrete, false)
		-- Bollards along its edge, and a ladder down into the water.
		for index = -6, 6 do
			local bollard = wall * CFrame.new(index * 30, (quayTop - floorY) / 2 + 1, -sign * 6)
			column(parent, "Bollard", 2.2, bollard.Position, quayTop, quayTop + 2.4, Color3.fromRGB(58, 60, 62), false)
		end
	end

	-- A GANTRY CRANE over one quay, the landmark you see the whole way down the street.
	local craneAt = frame * CFrame.new(-120, 0, HARBOUR_REACH * 0.62)
	local craneTop = waterLevel + 46
	local paint = Color3.fromRGB(186, 104, 64)
	for _, leg in ipairs({ { -12, -12 }, { 12, -12 }, { -12, 12 }, { 12, 12 } }) do
		column(parent, "CraneLeg", 2.6, (craneAt * CFrame.new(leg[1], 0, leg[2])).Position, floorY, craneTop, paint, false)
	end
	cityBlock(parent, "CraneBeam", Vector3.new(30, 3.4, 30), craneAt * CFrame.new(0, craneTop - floorY + 1.7, 0), paint)
	cityBlock(parent, "CraneBoom", Vector3.new(96, 2.6, 3.4), craneAt * CFrame.new(-34, craneTop - floorY + 5, 0), paint)
	cityBlock(parent, "CraneCounter", Vector3.new(16, 5, 6), craneAt * CFrame.new(26, craneTop - floorY + 5, 0),
		Color3.fromRGB(70, 72, 74))
	cityBlock(parent, "CraneCab", Vector3.new(6, 5, 6), craneAt * CFrame.new(6, craneTop - floorY + 6.4, 4),
		Color3.fromRGB(210, 200, 180))
	-- Its hook, down on a cable, swinging over nothing.
	local hookTop = (craneAt * CFrame.new(-28, craneTop - floorY + 3.6, 0)).Position
	rod(parent, "CraneCable", hookTop, hookTop - Vector3.new(0, 26, 0), 0.4, Color3.fromRGB(80, 78, 74))
	cityBlock(parent, "CraneHook", Vector3.new(3, 3, 3), CFrame.new(hookTop - Vector3.new(0, 27, 0)),
		Color3.fromRGB(70, 72, 74))

	-- CONTAINERS stacked on the other quay, the colour gone out of them.
	local yard = frame * CFrame.new(-150, 0, -HARBOUR_REACH * 0.62)
	for index = 1, 16 do
		local tier = rng:NextInteger(0, 2)
		local box = yard * CFrame.new(rng:NextNumber(-90, 90), quayTop - floorY + 3 + tier * 6,
			rng:NextNumber(-14, 14)) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0)
		container(parent, box, Vector3.new(24, 6, 8), FADED[rng:NextInteger(1, #FADED)], true)
	end

	-- A LIGHTHOUSE on the basin's far side: the one light still burning out here, and it is what
	-- you steer by while the water takes you.
	local lightAt = frame * CFrame.new(150, 0, HARBOUR_REACH * 0.5)
	local lightTop = waterLevel + 40
	column(parent, "LighthouseBase", 22, lightAt.Position, floorY, waterLevel + 4, drowned(STONE, floorY + 8), false)
	for index = 0, 5 do
		local shrink = 1 - index * 0.1
		column(parent, "LighthouseShaft", 15 * shrink, lightAt.Position, waterLevel + 4 + index * 5.6,
			waterLevel + 9.6 + index * 5.6, if index % 2 == 0 then Color3.fromRGB(226, 222, 212) else Color3.fromRGB(190, 78, 66),
			false)
	end
	column(parent, "LighthouseGallery", 16, lightAt.Position, lightTop - 4, lightTop - 3, Color3.fromRGB(70, 72, 74), false)
	local lantern = column(parent, "LighthouseLantern", 10, lightAt.Position, lightTop - 3, lightTop + 4,
		Color3.fromRGB(238, 230, 200), false)
	if lantern then
		lantern.Material = Enum.Material.Glass
		lantern.Transparency = 0.25
		local beam = Instance.new("PointLight")
		beam.Brightness = 2.2
		beam.Range = 90
		beam.Color = Color3.fromRGB(255, 232, 190)
		beam.Shadows = false
		beam.Parent = lantern
		CollectionService:AddTag(lantern, "SunkenBeacon")
	end
	column(parent, "LighthouseCap", 11, lightAt.Position, lightTop + 4, lightTop + 6, Color3.fromRGB(70, 72, 74), false)

	-- A FISHING BOAT that went down by the quay, its bow still out of the water.
	local boat = frame * CFrame.new(-60, waterLevel - 6 - floorY, -HARBOUR_REACH * 0.34)
		* CFrame.Angles(math.rad(-32), 0, math.rad(8))
	cityBlock(parent, "Hull", Vector3.new(22, 4, 7), boat, Color3.fromRGB(60, 80, 110))
	cityBlock(parent, "HullBand", Vector3.new(22.2, 1, 7.2), boat * CFrame.new(0, 1.6, 0), Color3.fromRGB(200, 196, 186))
	cityBlock(parent, "Wheelhouse", Vector3.new(6, 4, 5), boat * CFrame.new(3, 4, 0), Color3.fromRGB(214, 210, 200))
	column(parent, "BoatMast", 0.6, (boat * CFrame.new(-4, 2, 0)).Position, waterLevel - 4, waterLevel + 9,
		Color3.fromRGB(150, 140, 120), false)

	-- A BARGE, half sunk, and the wreck of something older out on the silt.
	local barge = frame * CFrame.new(40, waterLevel - 3 - floorY, -HARBOUR_REACH * 0.5) * CFrame.Angles(0, 0, math.rad(-12))
	cityBlock(parent, "Barge", Vector3.new(46, 6, 14), barge, drowned(Color3.fromRGB(96, 92, 86), waterLevel - 3))
	cityBlock(parent, "BargeHold", Vector3.new(30, 1, 10), barge * CFrame.new(0, 3.2, 0), Color3.fromRGB(40, 44, 44))
	local wreck = frame * CFrame.new(230, 5, -HARBOUR_REACH * 0.2) * CFrame.Angles(math.rad(6), 0.4, math.rad(28))
	cityBlock(parent, "WreckHull", Vector3.new(58, 12, 16), wreck, drowned(Color3.fromRGB(70, 74, 72), floorY + 6))
	for index = -2, 2 do
		cityBlock(parent, "WreckRib", Vector3.new(1.2, 14, 17), wreck * CFrame.new(index * 11, 2, 0),
			drowned(Color3.fromRGB(58, 60, 58), floorY + 8))
	end

	-- BUOYS, floating on the water and chained to the floor. Tagged so the client can bob them.
	for index = 1, 6 do
		local spotAt = frame * CFrame.new(rng:NextNumber(-40, 260), waterLevel - floorY,
			rng:NextNumber(-HARBOUR_REACH * 0.7, HARBOUR_REACH * 0.7))
		local spot = spotAt.Position
		if (Vector3.new(spot.X - vortex.X, 0, spot.Z - vortex.Z)).Magnitude > VORTEX_R + 40 then
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
end

-- ===== WHAT LIVES IN THE WATER =====
--
-- Nothing here is built: each of these is a MARKER the client reads, because a shoal of fish is
-- thirty parts moving every frame and replicating that from the server would cost every player a
-- stream of updates for something nobody can touch. The server decides where they are and how big;
-- SunkenCityClient makes them and swims them. The same trade as City Shore's sea and Sky Pools'
-- gulls.
local function shoals(parent: Instance, route: Route, floorY: number, rng: Random,
	blocked: (Vector3, number) -> boolean)
	-- Each shoal circles a long loop laid ALONG the street (`Along`), so it stays in the street
	-- however the street bends: out to its radius along it, a third of that across -- and, like the
	-- swimmers, in a lane beside the route rather than under it.
	local reachable = route.total - harbourAlong(route)
	local count = math.max(3, math.floor(reachable / SHOAL_EVERY))
	for index = 1, count do
		local s = (index - 0.5) * (reachable / count)
		local at, dir = alongRoute(route, s)
		local side = Vector3.yAxis:Cross(dir)
		local spot = at + side * ((if index % 2 == 0 then 1 else -1) * rng:NextNumber(15, SHOAL_OUT))
		local radius = rng:NextNumber(12, 20)
		if not blocked(spot, radius + 4) then
			local marker = block(parent, "Shoal", Vector3.new(1, 1, 1),
				CFrame.new(spot.X, waterLevel - rng:NextNumber(3.5, 10), spot.Z), SURFACE,
				Enum.Material.SmoothPlastic, false)
			marker.Transparency = 1
			marker:SetAttribute("Count", rng:NextInteger(14, 22))
			marker:SetAttribute("Radius", radius)
			marker:SetAttribute("Speed", rng:NextNumber(0.25, 0.45))
			marker:SetAttribute("Length", rng:NextNumber(2.2, 3.2))
			marker:SetAttribute("Phase", rng:NextNumber(0, 100))
			marker:SetAttribute("Along", dir)
			CollectionService:AddTag(marker, "SunkenFishShoal")
		end
	end
	-- AND THE ONES AT THE BACK. Far enough out that the haze has them, big enough that you can see
	-- them anyway, slow enough that you are never sure. They keep to the deep water well off the
	-- street, and they are the reason not to look too long at the edge of the view.
	for index = 1, HORRORS do
		local s = route.total * (index - 0.5) / HORRORS
		local at, dir = alongRoute(route, s)
		local side = Vector3.yAxis:Cross(dir)
		local sign = if index % 2 == 0 then 1 else -1
		local spot = at + side * (sign * rng:NextNumber(HORROR_OUT * 0.8, HORROR_OUT * 1.3))
		local marker = block(parent, "Horror", Vector3.new(1, 1, 1),
			CFrame.new(spot.X, waterLevel - rng:NextNumber(26, 46), spot.Z), DEEP,
			Enum.Material.SmoothPlastic, false)
		marker.Transparency = 1
		marker:SetAttribute("Length", rng:NextNumber(34, 58))
		marker:SetAttribute("Radius", rng:NextNumber(120, 240))
		marker:SetAttribute("Speed", rng:NextNumber(0.03, 0.06))
		marker:SetAttribute("Phase", rng:NextNumber(0, 100))
		CollectionService:AddTag(marker, "SunkenHorror")
	end
end

-- ===== THE SWIMMERS =====
--
-- Markers, like the shoals: each is an animal's home, and the client builds the animal and moves it
-- round that home on a wandering path of its own -- turning to face where it is going, speeding up
-- and drifting, now and then darting. Nothing about them is shared between clients, because nothing
-- about them matters to the game: a ray nobody else saw is still a ray you saw.
local function swimmers(parent: Instance, route: Route, floorY: number, rng: Random,
	blocked: (Vector3, number) -> boolean)
	-- IN THE OPEN WATER UNDER THE ROUTE, where you look down and see them. Each one wanders along the
	-- street far more than across it and never further across than SWIM_REACH, which keeps it clear
	-- of the road signs' legs and the lamp posts without having to know where they are; none is given
	-- a home where its wander would reach the aquarium, the dry flat, or the harbour's whirlpool.
	-- NEAR THE TOP, mostly. The street's floor is a hundred studs down and what is down there is a
	-- shape in the dark; the animals are six to twenty-four studs under the surface, where the light
	-- still gets to them.
	local reachable = route.total - harbourAlong(route)
	local count = math.max(6, math.floor(reachable / SWIMMER_EVERY))
	for index = 1, count do
		local s = math.clamp((index - 0.5) * (reachable / count) + rng:NextNumber(-12, 12), 0, reachable)
		local at, dir = alongRoute(route, s)
		local side = Vector3.yAxis:Cross(dir)
		local kind = SWIMMER_KINDS[(index - 1) % #SWIMMER_KINDS + 1]
		-- NEAR THE TOP, where you see them from the route: jellyfish just under the surface, a pod of
		-- dolphins that leaps out of it now and then, turtles that come up to breathe, rays and sharks
		-- a little deeper and the grouper and the eels deeper still. How far each rises and sinks
		-- (`Bob`) is what keeps the top of it under the surface; the dolphins' leap and the turtles'
		-- breath are the two things that are meant to break it, and they do it on the client.
		-- A LITTLE NEARER THE TOP than they were: twenty studs of this water hides anything.
		local depth = if kind == "jelly" then rng:NextNumber(3.5, 7)
			elseif kind == "dolphins" then rng:NextNumber(4, 6)
			elseif kind == "turtle" then rng:NextNumber(5, 10)
			elseif kind == "ray" then rng:NextNumber(5.5, 11)
			elseif kind == "shark" then rng:NextNumber(7, 12)
			else rng:NextNumber(7, 14)
		local bob = if kind == "jelly" then 1.2 elseif kind == "dolphins" then 1 elseif kind == "turtle" then 2 else 3
		local range = if kind == "jelly" then 10 else rng:NextNumber(22, 40)
		local out = (if index % 2 == 0 then 1 else -1) * rng:NextNumber(SWIM_LANE[1], SWIM_LANE[2])
		local across = math.min(SWIM_REACH - math.abs(out), math.abs(out) - ROUTE_REACH + 2)
		local home = at + side * out
		if not blocked(home, math.max(range, across) + 6) and s + range < reachable then
			local marker = block(parent, "Swimmer", Vector3.new(1, 1, 1), CFrame.new(home.X, waterLevel - depth, home.Z),
				SURFACE, Enum.Material.SmoothPlastic, false)
			marker.Transparency = 1
			marker:SetAttribute("Kind", kind)
			marker:SetAttribute("Range", range)
			marker:SetAttribute("Across", if kind == "jelly" then math.min(across, 10) else across)
			marker:SetAttribute("Speed", rng:NextNumber(0.6, 1.2))
			marker:SetAttribute("Phase", rng:NextNumber(0, 100))
			marker:SetAttribute("Along", dir)
			marker:SetAttribute("Bob", bob)
			CollectionService:AddTag(marker, "SunkenSwimmer")
		end
	end
end

-- ===== GULLS =====
--
-- Over the street, circling: the one kind of life you see without looking into the water. Markers
-- the client builds and flies (SunkenCityClient). Each circles its own point over the street, high
-- enough to clear every chunk, the aquarium's tower and the dry flat's roof, and near enough the
-- street's middle that no circle reaches the buildings either side.
local function gulls(parent: Instance, route: Route, rng: Random, blocked: (Vector3, number) -> boolean)
	local count = math.max(4, math.floor(route.total / GULL.every))
	for index = 1, count do
		local s = (index - 0.5) * (route.total / count)
		local at, dir = alongRoute(route, s)
		local side = Vector3.yAxis:Cross(dir)
		local centre = at + side * rng:NextNumber(-GULL.out, GULL.out)
		local radius = rng:NextNumber(12, GULL.radius)
		if not blocked(centre, radius + 6) then
			local marker = block(parent, "Gull", Vector3.new(1, 1, 1), CFrame.new(centre.X, waterLevel + rng:NextNumber(GULL.low, 46),
				centre.Z), FOAM, Enum.Material.SmoothPlastic, false)
			marker.Transparency = 1
			marker:SetAttribute("Radius", radius)
			marker:SetAttribute("Speed", rng:NextNumber(0.25, 0.45) * (if index % 2 == 0 then 1 else -1))
			marker:SetAttribute("Phase", rng:NextNumber(0, 100))
			CollectionService:AddTag(marker, "SunkenGull")
		end
	end
end

-- ===== LIGHT IN THE WATER =====
--
-- What makes water read as water from above is not the surface, it is what the light does under it.
-- Two things, both cheap: shafts leaning down from the surface where it is broken, and the specks
-- drifting in them.
local function shafts(parent: Instance, route: Route, floorY: number, rng: Random)
	local count = math.max(4, math.floor(route.total / 110))
	for index = 1, count do
		local s = (index - 0.5) * (route.total / count) + rng:NextNumber(-30, 30)
		local at, dir = alongRoute(route, s)
		local side = Vector3.yAxis:Cross(dir)
		local spot = at + side * rng:NextNumber(-BOULEVARD_HALF * 1.6, BOULEVARD_HALF * 1.6)
		local depth = rng:NextNumber(24, 44)
		local wide = rng:NextNumber(7, 16)
		local shaft = block(parent, "LightShaft", Vector3.new(wide, depth, wide * 0.5),
			CFrame.new(spot.X, waterLevel - depth / 2, spot.Z) * CFrame.Angles(rng:NextNumber(-0.16, 0.16), rng:NextNumber(0, 6.2), 0),
			Color3.fromRGB(196, 226, 220), Enum.Material.Glass, false)
		shaft.Transparency = 0.93
		shaft.CastShadow = false
		shaft:SetAttribute("Phase", rng:NextNumber(0, 100))
		CollectionService:AddTag(shaft, "SunkenShaft")
		-- The specks, hanging in it.
		local motes = Instance.new("ParticleEmitter")
		motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		motes.Color = ColorSequence.new(Color3.fromRGB(226, 240, 232))
		motes.LightEmission = 0.4
		motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.15) })
		motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.5, 0.75), NumberSequenceKeypoint.new(1, 1) })
		motes.Lifetime = NumberRange.new(6, 12)
		motes.Speed = NumberRange.new(0.3, 1)
		motes.SpreadAngle = Vector2.new(60, 60)
		motes.Acceleration = Vector3.new(0, -0.4, 0)
		motes.Rate = 6
		motes.Parent = shaft
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

-- The frame beside a checkpoint: origin on its cap's outer edge at the cap's top, +X facing away
-- from the route on the side asked for, +Z along it. Sky Pools' terraces use the same frame.
--
-- IT TAKES A SIDE NOW, not a centre to face away from. On a ring there was an outside and that was
-- always the answer; on a street there is a left and a right, and what goes on one has to be able
-- to be told to go on the other.
local function besideFrame(cap: BasePart, side: number): CFrame?
	local right = Vector3.new(cap.CFrame.RightVector.X, 0, cap.CFrame.RightVector.Z)
	if right.Magnitude < 0.01 then
		return nil
	end
	local outward = right.Unit * side
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

type Aquarium = { tower: Vector3, far: Vector3, window: BasePart, light: PointLight, hum: Sound, keeper: CFrame,
	escape: { Vector3 } }

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
	-- THE STAIR: how many rises, how high each is and how far round each step turns, so that it runs
	-- from STAIR.top to STAIR.foot in whole turns with steps no steeper than STEP_RISE_MAX and none so
	-- shallow the turn above comes down on your head. Of the plans that fit, the one nearest
	-- STAIR.riseBest. check_sunkencity.py lays the same stair and walks it.
	local function stairPlan(drop: number): (number, number, number)
		local bestCount, bestRise, bestAngle, bestMiss = 0, 0, 0, math.huge
		for turns = 1, 5 do
			local sweep = STAIR.foot + turns * 2 * math.pi - STAIR.top
			if sweep > 0 then
				local fewest = math.max(2, math.ceil(sweep / STAIR.angleMax + 0.5))
				local most = math.floor(sweep / STAIR.angleMin + 0.5)
				for steps = fewest, most do
					local rise = drop / (steps + 1)
					local angle = sweep / (steps - 0.5)
					if rise >= STAIR.riseMin and rise <= STEP_RISE_MAX and angle >= STAIR.angleMin and angle <= STAIR.angleMax then
						local miss = math.abs(rise - STAIR.riseBest)
						if miss < bestMiss then
							bestCount, bestRise, bestAngle, bestMiss = steps + 1, rise, angle, miss
						end
					end
				end
			end
		end
		if bestCount == 0 then
			local count = math.ceil(drop / STEP_RISE_MAX)
			return count, drop / count, STEP_ANGLE
		end
		return bestCount, bestRise, bestAngle
	end

	-- A STACK OF ROCK from the sea floor to `topY`, boulders narrowing as they go up, and on the top --
	-- which is at the tunnel's eye level, the only part anyone sees -- what grows there: branching coral,
	-- a fan, a brain coral, a starfish. The colours are muted on purpose: this is a drowned aquarium,
	-- not a reef poster.
	local CORAL = { Color3.fromRGB(226, 146, 136), Color3.fromRGB(186, 160, 214), Color3.fromRGB(232, 196, 120),
		Color3.fromRGB(150, 200, 180) }
	local function rockStack(parent: Instance, base: Vector3, floorY: number, topY: number, rng: Random, dressed: boolean)
		local y = floorY
		local width = rng:NextNumber(9, 12)
		while y < topY - 1 do
			local h = math.min(topY - y, rng:NextNumber(10, 16))
			local rock = ellipsoid(parent, "Rock", Vector3.new(width, h * 1.35, width * rng:NextNumber(0.8, 1.1)),
				CFrame.new(base.X + rng:NextNumber(-1, 1), y + h * 0.325, base.Z + rng:NextNumber(-1, 1))
					* CFrame.Angles(0, rng:NextNumber(0, 6), 0), drowned(Color3.fromRGB(110, 108, 98), y + h / 2))
			rock.Material = Enum.Material.Rock
			y += h * 0.85
			width = math.max(4.5, width * 0.86)
		end
		if not dressed then
			return
		end
		local top = Vector3.new(base.X, topY, base.Z)
		-- Branching coral: a trunk and three arms, each with a rounded tip.
		local colour = CORAL[rng:NextInteger(1, #CORAL)]
		local trunkTop = top + Vector3.new(0, 2.4, 0)
		rod(parent, "Coral", top, trunkTop, 0.6, colour)
		for arm = 1, 3 do
			local a = arm * 2.1 + rng:NextNumber(-0.4, 0.4)
			local tip = trunkTop + Vector3.new(math.cos(a) * 1.4, rng:NextNumber(1.2, 2.2), math.sin(a) * 1.4)
			rod(parent, "Coral", trunkTop, tip, 0.45, colour)
			ellipsoid(parent, "CoralTip", Vector3.new(0.7, 0.7, 0.7), CFrame.new(tip), colour:Lerp(Color3.new(1, 1, 1), 0.25))
		end
		-- A sea fan, standing across the current: a cylinder's axis is its X, so a thin one stands as a disc.
		local fanAt = top + Vector3.new(rng:NextNumber(-2, 2), 2, rng:NextNumber(-2, 2))
		local fan = block(parent, "SeaFan", Vector3.new(0.2, 4, 4.6), CFrame.new(fanAt) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			Color3.fromRGB(150, 70, 90), Enum.Material.Fabric, false)
		fan.Shape = Enum.PartType.Cylinder
		-- A brain coral, and a starfish on the rock.
		local brain = ellipsoid(parent, "BrainCoral", Vector3.new(2.6, 1.5, 2.4), CFrame.new(top + Vector3.new(rng:NextNumber(-2, 2),
			0.5, rng:NextNumber(-2, 2))), Color3.fromRGB(196, 206, 150))
		brain.Material = Enum.Material.Slate
		local star = CFrame.new(top + Vector3.new(rng:NextNumber(-2.5, 2.5), 0.1, rng:NextNumber(-2.5, 2.5)))
			* CFrame.Angles(0, rng:NextNumber(0, 6), 0)
		for arm = 0, 4 do
			block(parent, "Starfish", Vector3.new(0.5, 0.25, 1.3), star * CFrame.Angles(0, arm * 2 * math.pi / 5, 0)
				* CFrame.new(0, 0, -0.6), Color3.fromRGB(214, 120, 70), Enum.Material.SmoothPlastic, false)
		end
	end

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

	-- THE STAIR, turning down from the top landing to its foot beside the tunnel's mouth (stairPlan),
	-- the last step one rise above the floor.
	local drop = landingY - tunnelY
	local count, rise, angle = stairPlan(drop)
	for step = 1, count - 1 do
		local psi = STAIR.top + (step - 0.5) * angle
		local cf = towerAt * CFrame.Angles(0, -psi, 0) * CFrame.new(6.15, -step * rise - 0.5, 0)
		block(parent, "Step", Vector3.new(7.1, 1, 3.2), cf, drowned(STONE, landingY - step * rise), Enum.Material.Concrete, true)
	end
	-- Three lamps down the stairwell, on the wall six and a half studs over the step beside them, so
	-- nobody walks into one.
	for _, share in ipairs({ 0.25, 0.5, 0.75 }) do
		local step = math.max(1, math.floor((count - 1) * share))
		local psi = STAIR.top + (step - 0.5) * angle
		lamp(parent, towerAt * CFrame.Angles(0, -psi, 0) * CFrame.new(ROT_R - ROT_WALL - 0.4, -step * rise + 6.5, 0),
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
	-- THE AQUARIUM'S GLASS IS NOT THE GLASS MATERIAL. Roblox's Glass draws only what is opaque
	-- behind it and leaves out everything transparent -- so from inside the tunnel, the four layers
	-- of tinted water outside, the bubbles, the specks and the sea's own surface overhead were
	-- simply not there, and the view out was of a clear, dry-looking dark. That is the "the water
	-- does not look watery" of an earlier round. A plain translucent pane shows all of it. The same
	-- goes for the tint layers themselves: glass in front of glass shows only the nearest.
	local glassColour = Color3.fromRGB(150, 200, 205)
	local PANE = Enum.Material.SmoothPlastic
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
					glassColour, PANE, true)
				pane.Transparency = 0.64
				pane.Reflectance = 0.06
				local roofPane = block(parent, "TunnelGlass", Vector3.new(TUNNEL_BAY, 0.4, roofSpan + 0.3),
					frame * CFrame.new(mid, ty + 6 + ridge / 2, side * half / 2) * CFrame.Angles(side * slope, 0, 0),
					glassColour, PANE, true)
				roofPane.Transparency = 0.64
				roofPane.Reflectance = 0.06
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
	-- THE LIGHT IN THE TUNNEL. Two lamps in a sixty-four stud tube left most of it dark and the
	-- glass reading as slate. A strip along the ridge every bay instead -- a real fitting, set into
	-- the roof, with a small light in every third one -- lights the whole run and, more to the
	-- point, lights the WATER outside it, which is the thing you came down here to look at.
	for bay = 0, bays - 1 do
		local x = tunnelFrom + (bay + 0.5) * TUNNEL_BAY
		local strip = block(parent, "TunnelLight", Vector3.new(TUNNEL_BAY - 3, 0.5, 1.2),
			frame * CFrame.new(x, ty + TUNNEL_H - 1.1, 0), Color3.fromRGB(226, 240, 240), Enum.Material.Glass, false)
		strip.Transparency = 0.2
		if bay % 2 == 0 then
			local glow = Instance.new("PointLight")
			glow.Brightness = 0.85
			glow.Range = 26
			glow.Color = Color3.fromRGB(198, 228, 236)
			glow.Shadows = false
			glow.Parent = strip
		end
	end
	-- And two uplights in the tunnel floor, throwing light UP through the water, which is what an
	-- aquarium tunnel actually feels like.
	for _, share in ipairs({ 0.3, 0.7 }) do
		local up = block(parent, "TunnelUplight", Vector3.new(3, 0.3, TUNNEL_W - 1),
			frame * CFrame.new(tunnelFrom + TUNNEL_L * share, ty + 0.2, 0), Color3.fromRGB(180, 226, 226),
			Enum.Material.Glass, false)
		up.Transparency = 0.25
		local glow = Instance.new("SurfaceLight")
		glow.Face = Enum.NormalId.Top
		glow.Angle = 150
		glow.Brightness = 1.2
		glow.Range = 34
		glow.Color = Color3.fromRGB(150, 220, 220)
		glow.Shadows = false
		glow.Parent = up
	end

	-- THE WATER OUTSIDE THE GLASS, in layers. One pane of tint reads as a green window; four at
	-- increasing distance read as water, because each one dims what is behind it a little more and
	-- that is what depth in water actually does to a view. They stand off the tunnel and the
	-- gallery, never across them, so the tube stays dry and walkable.
	--
	-- THEY STOP UNDER THE SURFACE, and nothing lies flat. They used to rise thirteen studs out of
	-- the water, and there were four more laid flat over the tunnel, three of them above the
	-- surface -- so from the route there was a rectangle over the aquarium where the water was a
	-- different water. Upright panes that end under the surface are edge-on from above, which is
	-- to say invisible from everywhere except inside the tunnel, which is the only place they are
	-- for.
	local tankLong = TUNNEL_L + ROOM_L + 40
	local tankMidX = tunnelFrom + tankLong / 2 - 20
	local tankTop = waterLevel - 3
	local tankBottom = floorY + 1
	for index, layer in ipairs({ { 22, 0.9 }, { 40, 0.93 }, { 64, 0.95 }, { 92, 0.96 } }) do
		for _, sign in ipairs({ -1, 1 }) do
			local pane = block(parent, "TankWater", Vector3.new(tankLong, tankTop - tankBottom, 0.6),
				frame * CFrame.new(tankMidX, (tankTop + tankBottom) / 2 - landingY, sign * layer[1]),
				SURFACE:Lerp(DEEP, index / 5), PANE, false)
			pane.Transparency = layer[2]
			pane.CastShadow = false
			pane:SetAttribute("Phase", index * 0.7 + (if sign > 0 then 0.4 else 0))
			CollectionService:AddTag(pane, "SunkenTank")
		end
	end

	-- CAUSTICS: the moving bright patches the surface throws onto everything under it. The client
	-- slides and fades them (SunkenCityClient); without them a tunnel under water is a tunnel in a
	-- dark room.
	for index = 1, 10 do
		local caustic = block(parent, "Caustic", Vector3.new(rng:NextNumber(5, 11), 0.2, rng:NextNumber(5, 11)),
			frame * CFrame.new(tunnelFrom + rng:NextNumber(0, TUNNEL_L + ROOM_L), ty + 0.35,
				rng:NextNumber(-TUNNEL_W / 2 + 0.6, TUNNEL_W / 2 - 0.6)),
			Color3.fromRGB(214, 240, 236), Enum.Material.SmoothPlastic, false)
		-- NOT NEON. A caustic is light the water throws onto the floor, and the light in this
		-- tunnel is the fittings in its roof and the two uplights in its floor -- so this is a pale
		-- patch for them to catch, not a part pretending to glow.
		caustic.Transparency = 0.82
		caustic.CastShadow = false
		caustic:SetAttribute("Phase", rng:NextNumber(0, 100))
		caustic:SetAttribute("Drift", rng:NextNumber(2.5, 5))
		CollectionService:AddTag(caustic, "SunkenCaustic")
	end

	-- Specks in the water, so it has something in it to see.
	local motesHost = block(parent, "TankMotes", Vector3.new(TUNNEL_L, 20, 60),
		frame * CFrame.new(tunnelFrom + TUNNEL_L / 2, ty + 6, 0), SURFACE, Enum.Material.SmoothPlastic, false)
	motesHost.Transparency = 1
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = ColorSequence.new(Color3.fromRGB(214, 232, 226))
	motes.LightEmission = 0.3
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.2) })
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.5, 0.8), NumberSequenceKeypoint.new(1, 1) })
	motes.Lifetime = NumberRange.new(8, 16)
	motes.Speed = NumberRange.new(0.2, 0.8)
	motes.SpreadAngle = Vector2.new(70, 70)
	motes.Acceleration = Vector3.new(0.1, -0.2, 0)
	motes.Rate = 14
	motes.Parent = motesHost


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
		glassColour, PANE, true)
	window.Transparency = 0.6
	window.Reflectance = 0.06
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

	-- ROCK STACKS beside the tunnel, their tops at eye level with the coral on them: the tank had
	-- nothing in it to look AT, only through. Placed first, so the kelp can keep out of them.
	local rocks: { Vector3 } = {}
	for index, spot in ipairs({ { 0.18, 13 }, { 0.42, -14 }, { 0.66, 12 }, { 0.88, -13 } }) do
		local at = frame * Vector3.new(tunnelFrom + TUNNEL_L * spot[1], 0, spot[2])
		table.insert(rocks, Vector3.new(at.X, 0, at.Z))
		rockStack(parent, Vector3.new(at.X, 0, at.Z), floorY, tunnelY + rng:NextNumber(0, 5) + (if index % 2 == 0 then 1 else 0), rng, true)
	end

	-- THE KELP FOREST: strands from the sea floor to just under the surface, a hundred studs of plant,
	-- in the tank either side of the tunnel and in a band past the gallery's window. Grown and swayed
	-- by the client, which lets the top of a strand and its blades reach KELP_REACH across: so a
	-- strand beside the tunnel stands KELP_TUNNEL off its line, keeps clear of the tower at one end
	-- and the gallery at the other, and is never rooted in a rock stack; and the ones past the window
	-- stand between the helmet and chest and what comes up out of the dark (check_sunkencity.py).
	local roomFar = roomX + ROOM_L / 2
	local planted = 0
	for _ = 1, 60 do
		if planted >= 16 then
			break
		end
		local along, off
		if planted < 12 then
			along = rng:NextNumber(tunnelFrom + 8, tunnelTo - 10)
			off = (if planted % 2 == 0 then 1 else -1) * rng:NextNumber(KELP_TUNNEL, TANK_HALF - 3)
		else
			along = rng:NextNumber(roomFar + 35, roomFar + 38)
			off = rng:NextNumber(-TANK_HALF + 3, TANK_HALF - 3)
		end
		local at = frame * Vector3.new(along, 0, off)
		local clear = true
		for _, rock in ipairs(rocks) do
			if Vector3.new(at.X - rock.X, 0, at.Z - rock.Z).Magnitude < 9 then
				clear = false
			end
		end
		if clear then
			planted += 1
			kelp(parent, Vector3.new(at.X, floorY, at.Z), waterLevel - rng:NextNumber(3, 9) - floorY, rng,
				Vector3.new(frame.RightVector.X, 0, frame.RightVector.Z).Unit, false)
		end
	end

	-- AND WHAT EVERY AQUARIUM HAS: a diver's helmet and a treasure chest, out past the gallery's
	-- window on their own rocks, breathing bubbles. Built at the size of the thing, so they read as
	-- ornaments made for a tank of giants.
	local helmetRock = frame * Vector3.new(roomFar + 16, 0, -6)
	rockStack(parent, Vector3.new(helmetRock.X, 0, helmetRock.Z), floorY, tunnelY - 2, rng, false)
	-- Seated on the rock: the collar's foot at the rock's top.
	local helmetAt = CFrame.lookAt(Vector3.new(helmetRock.X, tunnelY + 0.1, helmetRock.Z),
		(frame * Vector3.new(roomFar, 0, 0)) * Vector3.new(1, 0, 1) + Vector3.new(0, tunnelY + 0.1, 0))
	local copper = Color3.fromRGB(176, 124, 70)
	local helmet = ellipsoid(parent, "DiverHelmet", Vector3.new(5.4, 5.4, 5.4), helmetAt * CFrame.new(0, 1.4, 0), copper)
	helmet.Material = Enum.Material.Metal
	local collar = block(parent, "HelmetCollar", Vector3.new(1.4, 6.4, 6.4), helmetAt * CFrame.new(0, -1.4, 0)
		* CFrame.Angles(0, 0, math.pi / 2), copper:Lerp(Color3.fromRGB(90, 140, 110), 0.35), Enum.Material.Metal, false)
	collar.Shape = Enum.PartType.Cylinder
	for _, port in ipairs({ { 0, 0, 1 }, { -1, 0, 0.5 }, { 1, 0, 0.5 } }) do
		local dir = (helmetAt.LookVector * port[3] + helmetAt.RightVector * port[1]).Unit
		local at = helmetAt.Position + Vector3.new(0, 1.4, 0) + dir * 2.55
		local rim = block(parent, "PortRim", Vector3.new(0.5, 2.6, 2.6), CFrame.lookAt(at, at + dir) * CFrame.Angles(0, math.pi / 2, 0),
			BRASS, Enum.Material.Metal, false)
		rim.Shape = Enum.PartType.Cylinder
		local pane = block(parent, "PortGlass", Vector3.new(0.52, 1.9, 1.9), CFrame.lookAt(at, at + dir) * CFrame.Angles(0, math.pi / 2, 0),
			Color3.fromRGB(20, 30, 34), Enum.Material.Glass, false)
		pane.Shape = Enum.PartType.Cylinder
	end
	local valve = block(parent, "HelmetValve", Vector3.new(0.9, 0.9, 0.9), helmetAt * CFrame.new(0, 4.3, 0.4), BRASS,
		Enum.Material.Metal, false)
	local chestRock = frame * Vector3.new(roomFar + 20, 0, 7)
	rockStack(parent, Vector3.new(chestRock.X, 0, chestRock.Z), floorY, tunnelY - 3, rng, false)
	local chestAt = CFrame.lookAt(Vector3.new(chestRock.X, tunnelY - 3 + 1.6, chestRock.Z),
		(frame * Vector3.new(roomFar, 0, 0)) * Vector3.new(1, 0, 1) + Vector3.new(0, tunnelY - 1.4, 0))
	-- THE CHEST (gen_treasure.py): a planked sea chest with its barrel lid thrown open, iron bands,
	-- brackets and a torn hasp, a heap of coins with a crown and a goblet on it, rubies, a string of
	-- pearls over the edge and coins spilled on the rock. Five meshes, one box, its base on the rock.
	-- A faint warm light on the gold, which is the one thing down here that should catch the eye.
	-- With the meshes not imported, the old chest of parts.
	local TREASURE = {
		{ "Treasure_Wood", Color3.fromRGB(116, 80, 52), Enum.Material.WoodPlanks, 0 },
		{ "Treasure_Iron", Color3.fromRGB(58, 60, 64), Enum.Material.Metal, 0.05 },
		{ "Treasure_Gold", Color3.fromRGB(238, 190, 86), Enum.Material.Metal, 0.35 },
		{ "Treasure_Gems", Color3.fromRGB(200, 26, 44), Enum.Material.SmoothPlastic, 0.3 },
		{ "Treasure_Pearls", Color3.fromRGB(242, 238, 228), Enum.Material.SmoothPlastic, 0.2 },
	}
	local whole = SeaRig ~= nil
	for _, spec in ipairs(TREASURE) do
		if whole and not SeaRig.template(spec[1]) then
			whole = false
		end
	end
	local lid: BasePart
	if whole then
		for _, spec in ipairs(TREASURE) do
			local rig = SeaRig.place(parent, spec[1])
			if rig then
				-- Turned round: its front, with the hasp, to the window, and the open lid behind the gold.
				rig.part.CFrame = chestAt * CFrame.new(0, -1.55, 0) * CFrame.Angles(0, math.pi, 0)
				rig.part.Color = spec[2]
				rig.part.Material = spec[3]
				rig.part.Reflectance = spec[4]
			end
		end
		lid = block(parent, "ChestBubbles", Vector3.new(1, 1, 1), chestAt * CFrame.new(0, 3.4, 2.6), FOAM,
			Enum.Material.SmoothPlastic, false)
		lid.Transparency = 1
		local shine = Instance.new("PointLight")
		shine.Name = "GoldShine"
		shine.Color = Color3.fromRGB(255, 206, 120)
		shine.Brightness = 0.7
		shine.Range = 10
		shine.Shadows = false
		shine.Parent = lid
	else
		block(parent, "Chest", Vector3.new(5, 3, 3.4), chestAt, Color3.fromRGB(112, 78, 50), Enum.Material.WoodPlanks, false)
		for _, x in ipairs({ -1.8, 1.8 }) do
			block(parent, "ChestBand", Vector3.new(0.35, 3.1, 3.5), chestAt * CFrame.new(x, 0, 0), BRASS, Enum.Material.Metal, false)
		end
		local gold = ellipsoid(parent, "Gold", Vector3.new(4.2, 1.2, 2.8), chestAt * CFrame.new(0, 1.5, 0), Color3.fromRGB(230, 190, 90))
		gold.Material = Enum.Material.Metal
		lid = block(parent, "ChestLid", Vector3.new(5, 0.6, 3.4), chestAt * CFrame.new(0, 1.5, 1.7) * CFrame.Angles(math.rad(38), 0, 0)
			* CFrame.new(0, 0, -1.7), Color3.fromRGB(112, 78, 50), Enum.Material.WoodPlanks, false)
	end
	for _, host in ipairs({ valve, lid }) do
		local stream = Instance.new("ParticleEmitter")
		stream.Name = "Bubbles"
		stream.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		stream.Color = ColorSequence.new(Color3.fromRGB(226, 242, 240))
		stream.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.5) })
		stream.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.8) })
		stream.Lifetime = NumberRange.new(4, 6)
		stream.Speed = NumberRange.new(3, 5)
		stream.EmissionDirection = Enum.NormalId.Top
		stream.SpreadAngle = Vector2.new(8, 8)
		stream.Acceleration = Vector3.new(0, 1.5, 0)
		stream.Rate = if host == valve then 5 else 2.5
		stream.Parent = host
	end

	-- A BRASS RAIL down both sides of the tunnel, on posts at every rib, with a plaque here and there
	-- -- which is what makes it an aquarium and not a pipe. It stands off the glass by less than an
	-- arm, so the glass is still there to tap.
	for bay = 0, bays do
		local x = tunnelFrom + bay * TUNNEL_BAY
		for _, side in ipairs({ -1, 1 }) do
			block(parent, "RailPost", Vector3.new(0.3, 3.2, 0.3), frame * CFrame.new(x + (if bay == 0 then 1.2 else 0), ty + 1.6,
				side * (half - 0.9)), BRASS, Enum.Material.Metal, false)
		end
	end
	for _, side in ipairs({ -1, 1 }) do
		block(parent, "Handrail", Vector3.new(TUNNEL_L - 1.2, 0.3, 0.3), frame * CFrame.new(tunnelFrom + TUNNEL_L / 2 + 0.6, ty + 3.2,
			side * (half - 0.9)), BRASS, Enum.Material.Metal, false)
	end
	for index, words in ipairs({ "THE KELP FOREST", "OPEN WATER", "THE DEEP" }) do
		local side = if index % 2 == 0 then 1 else -1
		-- In the middle of a bay, where there is no post.
		local bayAt = ({ 0, 2, 3 })[index]
		local plaque = block(parent, "Plaque", Vector3.new(3.2, 1.1, 0.1), frame * CFrame.new(tunnelFrom + TUNNEL_BAY * (bayAt + 0.5),
			ty + 2.6, side * (half - 0.95)) * CFrame.Angles(math.rad(side * 25), 0, 0), Color3.fromRGB(40, 58, 60),
			Enum.Material.SmoothPlastic, false)
		label(plaque, if side > 0 then Enum.NormalId.Front else Enum.NormalId.Back, words, Color3.fromRGB(222, 214, 180))
	end

	-- BUBBLE VENTS along the tunnel's foot, outside the glass: columns of bubbles going up past you.
	for index, share in ipairs({ 0.12, 0.38, 0.62, 0.88 }) do
		local side = if index % 2 == 0 then 1 else -1
		do
			do
				local vent = block(parent, "BubbleVent", Vector3.new(1, 0.4, 1), frame * CFrame.new(tunnelFrom + TUNNEL_L * share, ty - 0.6,
					side * (half + 1.4)), Color3.fromRGB(60, 64, 66), Enum.Material.Metal, false)
				local bubbles = Instance.new("ParticleEmitter")
				bubbles.Name = "Bubbles"
				bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				bubbles.Color = ColorSequence.new(Color3.fromRGB(226, 242, 240))
				bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.45) })
				bubbles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.9) })
				bubbles.Lifetime = NumberRange.new(3.5, 5)
				bubbles.Speed = NumberRange.new(4, 6)
				bubbles.EmissionDirection = Enum.NormalId.Top
				bubbles.SpreadAngle = Vector2.new(6, 6)
				bubbles.Acceleration = Vector3.new(0, 1, 0)
				bubbles.Rate = 9
				bubbles.Parent = vent
			end
		end
	end

	-- ANIMALS IN THE TANK, the same swimmers the street has: over the tunnel, where you look up at
	-- them through the roof, high enough that no wing beat or bob reaches the glass and low enough
	-- that nothing breaks the surface; and jellyfish past the gallery's window.
	local tankAlong = Vector3.new(frame.RightVector.X, 0, frame.RightVector.Z).Unit
	for index, kind in ipairs({ "ray", "turtle", "shark", "ray", "grouper", "jelly", "jelly", "jelly" }) do
		local at, across, bob
		if kind == "jelly" then
			at = frame * Vector3.new(roomFar + rng:NextNumber(10, 26), 0, rng:NextNumber(-8, 8))
			at = Vector3.new(at.X, tunnelY + rng:NextNumber(8, 11), at.Z)
			across, bob = 6, 1.5
		else
			at = frame * Vector3.new(tunnelFrom + rng:NextNumber(22, TUNNEL_L - 22), 0, rng:NextNumber(-4, 4))
			at = Vector3.new(at.X, tunnelY + rng:NextNumber(13.5, 16), at.Z)
			across, bob = 9, 1
		end
		local marker = block(parent, "Swimmer", Vector3.new(1, 1, 1), CFrame.new(at), SURFACE, Enum.Material.SmoothPlastic, false)
		marker.Transparency = 1
		marker:SetAttribute("Kind", kind)
		marker:SetAttribute("Range", if kind == "jelly" then 5 else 16)
		marker:SetAttribute("Across", across)
		marker:SetAttribute("Bob", bob)
		marker:SetAttribute("Speed", rng:NextNumber(0.6, 1))
		marker:SetAttribute("Phase", rng:NextNumber(0, 100) + index)
		marker:SetAttribute("Along", tankAlong)
		-- Seen through the gallery's window rather than through the sea's Glass surface, so a
		-- jellyfish here can be clear (SunkenCityClient).
		marker:SetAttribute("Clear", kind == "jelly")
		CollectionService:AddTag(marker, "SunkenSwimmer")
	end
	-- THE WINDOW ONTO THE DEEP is tagged, so the client knows where to bring up what looks in.
	CollectionService:AddTag(window, "SunkenDeepWindow")

	-- Three shoals of fish (the client makes and moves the fish from these markers).
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
	-- THE SPACES THAT FLOOD when the glass goes, cut to fit: the tower under the surface, the tunnel and
	-- the gallery. The client fills them with rising water (SunkenCityClient); who is washed out is
	-- decided by the zones above, which are a little larger.
	local floodTower = block(parent, "FloodVolume", Vector3.new(waterLevel - tunnelY, (ROT_R - ROT_WALL) * 2 - 0.3,
		(ROT_R - ROT_WALL) * 2 - 0.3), CFrame.new(towerAt.Position.X, (tunnelY + waterLevel) / 2, towerAt.Position.Z)
		* CFrame.Angles(0, 0, math.pi / 2), FOAM, Enum.Material.SmoothPlastic, false)
	floodTower.Shape = Enum.PartType.Cylinder
	local floodTunnel = block(parent, "FloodVolume", Vector3.new(TUNNEL_L, 9, TUNNEL_W), frame * CFrame.new((tunnelFrom + tunnelTo) / 2,
		ty + 4.5, 0), FOAM, Enum.Material.SmoothPlastic, false)
	local floodGallery = block(parent, "FloodVolume", Vector3.new(ROOM_L, ROOM_H, ROOM_W), room * CFrame.new(0, ty + ROOM_H / 2, 0),
		FOAM, Enum.Material.SmoothPlastic, false)
	for _, volume in ipairs({ floodTower, floodTunnel, floodGallery }) do
		volume.Transparency = 1
		CollectionService:AddTag(volume, "SunkenFloodVolume")
	end
	-- And the whole tower, door to floor, as a shelter from the surge: nothing outside reaches in.
	local towerShelter = block(parent, "Shelter", Vector3.new((ROT_R - ROT_WALL) * 2, roofY - tunnelY, (ROT_R - ROT_WALL) * 2),
		frame * CFrame.new(xc, (roofY + tunnelY) / 2 - landingY, 0), FOAM, Enum.Material.SmoothPlastic, false)
	towerShelter.Transparency = 1
	CollectionService:AddTag(towerShelter, "SunkenShelter")
	-- A STORY SPOT against the gallery's side wall, well away from the attendant's way out: a staff
	-- locker goes there (StoryService). Its front faces into the room.
	local lockerSpot = block(parent, "StorySpot", Vector3.new(1, 1, 1), room * CFrame.new(-5, ty, -ROOM_W / 2 + 0.7)
		* CFrame.Angles(0, math.pi, 0), FOAM, Enum.Material.SmoothPlastic, false)
	lockerSpot.Transparency = 1
	lockerSpot.CanQuery = false
	lockerSpot:SetAttribute("Kind", "AquariumLocker")
	CollectionService:AddTag(lockerSpot, "StorySpot")

	return {
		tower = towerAt.Position,
		far = (frame * CFrame.new(roomX + ROOM_L / 2 + WINDOW_DEEP, 0, 0)).Position,
		window = window,
		-- Where the attendant stands: by the notice, facing the way in from the tunnel.
		keeper = CFrame.lookAt((room * CFrame.new(ROOM_L / 2 - 2.6, ty, 9.6)).Position,
			(room * CFrame.new(ROOM_L / 2 - 3.6, ty, 9.3)).Position),
		-- And their way out when the glass goes (Townsfolk.panic), on the floor: past the end of the
		-- bench, through the tunnel's doorway, down the middle of the tunnel and into the tower, clear
		-- of its stair's newel.
		escape = {
			(room * CFrame.new(1.5, ty, 6.5)).Position,
			(room * CFrame.new(-ROOM_L / 2 + 1.5, ty, 0)).Position,
			(frame * CFrame.new(tunnelFrom + TUNNEL_L * 0.5, ty, 0)).Position,
			(frame * CFrame.new(tunnelFrom + 2, ty, 0)).Position,
			(frame * CFrame.new(xc + (ROT_R - ROT_WALL) * 0.55, ty, 0)).Position,
		},
		light = light,
		hum = hum,
	}
end

-- ===== WATER YOU CAN SWIM IN =====
--
-- The sea is parts, so it can be seen through and cannot be swum in. The one place meant to be swum
-- is the flooded floor under the dry flat, and that is Roblox terrain water, which is GLOBAL and not
-- built per run: every fill is remembered here and cleared when the level goes, as Sky Pools does
-- with its pools, and the water's look is put back as it was found.
local swimWater = { fills = {} :: { { cf: CFrame, size: Vector3 } }, was = {} :: { [string]: any } }

-- Dark and green, the colour of a flooded room, not of a pool; the look is remembered as found.
function swimWater.look()
	for name, value in pairs({ WaterColor = Color3.fromRGB(40, 84, 80), WaterTransparency = 0.35,
		WaterReflectance = 0.1, WaterWaveSize = 0.02, WaterWaveSpeed = 4 }) do
		pcall(function()
			if swimWater.was[name] == nil then
				swimWater.was[name] = (workspace.Terrain :: any)[name]
			end
			(workspace.Terrain :: any)[name] = value
		end)
	end
end

local function fillSwimWater(cf: CFrame, size: Vector3)
	workspace.Terrain:FillBlock(cf, size, Enum.Material.Water)
	table.insert(swimWater.fills, { cf = cf, size = size })
	swimWater.look()
end

function SunkenCityService.clearWater()
	for _, region in ipairs(swimWater.fills) do
		pcall(function()
			workspace.Terrain:FillBlock(region.cf, region.size + Vector3.new(6, 6, 6), Enum.Material.Air)
		end)
	end
	table.clear(swimWater.fills)
	for name, value in pairs(swimWater.was) do
		pcall(function()
			(workspace.Terrain :: any)[name] = value
		end)
	end
	table.clear(swimWater.was)
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
	-- stairwell's shaft and THE FLOODED FLOOR: an L of two rooms a storey under the water, reached
	-- through a doorway at the foot of the shaft. Each piece drowned by its depth. Its top is the
	-- flat's floor.
	local shaft = { x0 = b0 + 10, x1 = b0 + 22, z0 = -hz + 0.8, z1 = -hz + 12.8 }
	local footprint = { x0 = b0, x1 = b1, z0 = -hz, z1 = hz }
	local roomA = { x0 = b0 + 1.2, x1 = b0 + 8.8, z0 = -hz + 1.2, z1 = hz - 1.2 }
	local roomB = { x0 = b0 + 8.8, x1 = b1 - 1.2, z0 = shaft.z1 + 1, z1 = hz - 1.2 }
	local door = { x0 = b0 + 13, x1 = b0 + 17, z0 = shaft.z1, z1 = shaft.z1 + 1 }
	local roomFloor = waterLevel - FLOODED_DEPTH
	local roomCeil = waterLevel - 0.8
	for _, band in ipairs({
		{ floorY, roomFloor, { shaft } },
		{ roomFloor, roomFloor + 7, { shaft, roomA, roomB, door } },
		{ roomFloor + 7, roomCeil, { shaft, roomA, roomB } },
		{ roomCeil, waterLevel, { shaft } },
		{ waterLevel, landingY, { shaft } },
	}) do
		local y0, y1 = band[1], band[2]
		if y1 - y0 > 0.05 then
			for _, r in ipairs(subtract(footprint, band[3])) do
				block(parent, "FlatBody", Vector3.new(r.x1 - r.x0, y1 - y0, r.z1 - r.z0), put((r.x0 + r.x1) / 2, (y0 + y1) / 2, (r.z0 + r.z1) / 2),
					drowned(wallColour, (y0 + y1) / 2), Enum.Material.Concrete, true)
			end
		end
	end
	for _, r in ipairs(subtract(footprint, { shaft })) do
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

	-- THE STAIRWELL: a railing round the hole and a spiral down to where the water starts. Then the
	-- water, which is real water now: swim down the shaft, through the doorway at its foot and into
	-- the flooded floor.
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
	column(parent, "StairColumn", 2.4, sc.Position, roomFloor, landingY + h, wallColour, true, true)
	block(parent, "ShaftFloor", Vector3.new(shaft.x1 - shaft.x0, 1, shaft.z1 - shaft.z0), put((shaft.x0 + shaft.x1) / 2, roomFloor - 0.5,
		(shaft.z0 + shaft.z1) / 2), drowned(wallColour, roomFloor), Enum.Material.Concrete, true)
	-- THE WATER: the shaft from its floor to just under the surface, and the flooded floor, as one
	-- block through the walls between them (the walls are solid; the water in them is never seen).
	fillSwimWater(put((roomA.x0 + roomB.x1) / 2, (roomFloor + roomCeil) / 2, (shaft.z0 + roomA.z1) / 2),
		Vector3.new(roomB.x1 - roomA.x0, roomCeil - roomFloor, roomA.z1 - shaft.z0))
	fillSwimWater(put((shaft.x0 + shaft.x1) / 2, (roomCeil + waterLevel - 0.3) / 2, (shaft.z0 + shaft.z1) / 2),
		Vector3.new(shaft.x1 - shaft.x0 - 0.4, waterLevel - 0.3 - roomCeil, shaft.z1 - shaft.z0 - 0.4))

	-- THE FLOODED FLOOR. Somebody's flat, a storey down, the way the water left it: the furniture
	-- lifted and turned over, a lamp that is somehow still on, a few fish that have moved in, and a
	-- note on the wall.
	local planks = Color3.fromRGB(96, 78, 60)
	for _, room in ipairs({ roomA, roomB }) do
		block(parent, "FloodedFloor", Vector3.new(room.x1 - room.x0, 0.2, room.z1 - room.z0),
			put((room.x0 + room.x1) / 2, roomFloor + 0.1, (room.z0 + room.z1) / 2), drowned(planks, roomFloor), Enum.Material.WoodPlanks, false)
	end
	local drift = Color3.fromRGB(120, 92, 70)
	cityBlock(parent, "Wardrobe", Vector3.new(1.4, 3.2, 6.5), put(roomB.x0 + 5, roomFloor + 0.9, roomB.z1 - 2.5)
		* CFrame.Angles(0, math.rad(20), math.rad(84)), Color3.fromRGB(110, 86, 64), Enum.Material.Wood)
	cityBlock(parent, "FloatingTable", Vector3.new(4, 0.4, 2.6), put(roomB.x1 - 5, roomCeil - 1.4, roomB.z0 + 4)
		* CFrame.Angles(math.rad(14), math.rad(30), math.rad(-9)), drift, Enum.Material.Wood)
	for index = 1, 2 do
		cityBlock(parent, "FloatingChair", Vector3.new(1.6, 1.6, 1.6), put(roomB.x1 - 6 - index * 2.4, roomCeil - 2.4 - index, roomB.z0 + 2 + index)
			* CFrame.Angles(math.rad(40 * index), math.rad(70 * index), math.rad(25)), drift, Enum.Material.Wood)
	end
	cityBlock(parent, "Bookcase", Vector3.new(5, 1.2, 2.4), put(roomA.x0 + 3.5, roomFloor + 0.6, roomA.z0 + 4)
		* CFrame.Angles(0, math.rad(12), 0), drift, Enum.Material.Wood)
	for index = 1, 6 do
		cityBlock(parent, "Book", Vector3.new(0.3, 1.1, 0.8), put(roomA.x0 + 1.5 + index * 0.9, roomFloor + 3 + (index % 3) * 2.2,
			roomA.z0 + 3 + index * 1.4) * CFrame.Angles(math.rad(index * 37), math.rad(index * 53), math.rad(index * 21)),
			({ Color3.fromRGB(150, 60, 50), Color3.fromRGB(60, 90, 130), Color3.fromRGB(190, 160, 90) })[index % 3 + 1])
	end
	ellipsoid(parent, "Bear", Vector3.new(1.1, 1.3, 0.9), put(roomA.x0 + 4, roomCeil - 1, roomA.z1 - 4) * CFrame.Angles(0.4, 0.9, 0.3),
		Color3.fromRGB(150, 110, 80)).Material = Enum.Material.Fabric
	block(parent, "Picture", Vector3.new(0.1, 2.2, 3), put(roomA.x0 + 0.05, roomFloor + 5, 0),
		Color3.fromRGB(60, 50, 40), Enum.Material.Wood, false)
	local note = block(parent, "Note", Vector3.new(0.1, 1.6, 2.4), put(roomB.x1 - 0.05, roomFloor + 4.6, (roomB.z0 + roomB.z1) / 2),
		Color3.fromRGB(226, 220, 200), Enum.Material.SmoothPlastic, false)
	label(note, Enum.NormalId.Left, "WE WENT UP.\nIT DID NOT STOP.", Color3.fromRGB(50, 40, 34))
	-- The lamp that is still on, down here, and gutters (SunkenLantern, SunkenCityClient).
	local bulb = block(parent, "FloodedLamp", Vector3.new(1, 0.6, 1), put((roomB.x0 + roomB.x1) / 2, roomCeil - 0.4, (roomB.z0 + roomB.z1) / 2),
		Color3.fromRGB(255, 226, 180), Enum.Material.SmoothPlastic, false)
	local glow = Instance.new("PointLight")
	glow.Brightness = 0.9
	glow.Range = 18
	glow.Color = Color3.fromRGB(255, 214, 160)
	glow.Shadows = false
	glow.Parent = bulb
	CollectionService:AddTag(bulb, "SunkenLantern")
	-- And the fish that live here now (SunkenFishShoal, drawn and swum by the client).
	local fishAt = put((roomA.x0 + roomA.x1) / 2, roomFloor + 5, -3)
	local fish = block(parent, "Shoal", Vector3.new(1, 1, 1), fishAt, SURFACE, Enum.Material.SmoothPlastic, false)
	fish.Transparency = 1
	fish:SetAttribute("Count", 7)
	fish:SetAttribute("Radius", 2.6)
	fish:SetAttribute("Speed", 0.5)
	fish:SetAttribute("Length", 1)
	fish:SetAttribute("Phase", 3)
	CollectionService:AddTag(fish, "SunkenFishShoal")
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
	local lap = block(parent, "StairwellSound", Vector3.new(1, 1, 1), put((shaft.x0 + shaft.x1) / 2, waterLevel - 0.5, entryZ), wallColour,
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
local function finale(parent: Instance, finish: CFrame, floorY: number, rng: Random): Vector3
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
	lantern(parent, finish * CFrame.new(-PIER_W / 2 + 2.6, 4.6, PIER_L - 3), true, Color3.fromRGB(255, 200, 140))
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
			-- NOT GLASS, which drew only what was opaque behind it: each ring showed none of the others
			-- and the funnel was a stack of flat panes. And every segment carries the engine's water
			-- texture, which the client slides round and in (`SunkenWhirlFlow`), faster the further
			-- in -- the surface pouring down the funnel rather than a cone standing in the sea.
			local piece = block(model, "Whirl", Vector3.new(span + 0.4, 0.5, 2 * math.pi * outerR / 16 + 0.4),
				CFrame.new(vortex) * CFrame.Angles(0, -beta, 0) * CFrame.new((outerR + innerR) / 2, -(topD + bottomD) / 2, 0)
					* CFrame.Angles(0, 0, slope),
				tone, Enum.Material.SmoothPlastic, false)
			-- SEE-THROUGH, and more so further in: a solid cone of panels read as a model standing in the
			-- sea. The water's skin, darkening into the hole, with the swirl drawn over it doing the moving.
			piece.Transparency = 0.3 + ring * 0.07
			piece.Reflectance = 0.1
			local flow = Instance.new("Texture")
			flow.Name = "Flow"
			flow.Face = Enum.NormalId.Top
			flow.Texture = "rbxasset://textures/water/normal_1.dds"
			flow.StudsPerTileU = 9
			flow.StudsPerTileV = 9
			flow.Transparency = 0.55
			flow.Color3 = Color3.fromRGB(226, 242, 238)
			flow.Parent = piece
			piece:SetAttribute("Ring", ring)
			CollectionService:AddTag(piece, "SunkenWhirlFlow")
		end
		-- STREAKS of foam on the ring, a few and uneven: sixteen identical segments turning look like
		-- nothing turning at all, and these are what the eye follows round.
		for streak = 1, 4 do
			local beta = streak * 2 * math.pi / 4 + rng:NextNumber(-0.5, 0.5)
			local r = (outerR + innerR) / 2 + rng:NextNumber(-1, 1)
			local drop = (topD + bottomD) / 2
			local mark = block(model, "Streak", Vector3.new(0.6, 0.12, rng:NextNumber(4, 9)),
				CFrame.new(vortex) * CFrame.Angles(0, -beta, 0) * CFrame.new(r, -drop + 0.35, 0) * CFrame.Angles(0, 0, slope)
					* CFrame.Angles(0, rng:NextNumber(0.25, 0.5), 0), FOAM, Enum.Material.SmoothPlastic, false)
			mark.Transparency = 0.25 + ring * 0.08
			mark.CastShadow = false
		end
		model:SetAttribute("Centre", vortex)
		-- Radians a second, the way the rider goes round.
		model:SetAttribute("Spin", 0.35 + 0.35 * ring)
		model.Parent = parent
		CollectionService:AddTag(model, "SunkenWhirlRing")
	end
	-- THE SPIRAL ARMS: three lines of foam wound into the middle, which is the thing that says a
	-- whirlpool is TURNING rather than that a hole has been cut in the water. Tagged with the rings,
	-- so the client turns them together.
	local arms = Instance.new("Model")
	arms.Name = "WhirlArms"
	-- THIN, and in more pieces: they were planks a stud thick that the ride went straight through.
	-- A line of foam is a skin on the water, tapering and fading as it is drawn in.
	for arm = 0, 2 do
		for step = 0, 27 do
			local share = step / 27
			local r = VORTEX_R * (1 - share * 0.86) + 2
			local beta = arm * 2 * math.pi / 3 + share * 2.6
			local drop = FUNNEL_DEPTH * share ^ 1.6
			local piece = block(arms, "WhirlArm", Vector3.new(r * 0.28, 0.12, 1.5 - share * 0.9),
				CFrame.new(vortex) * CFrame.Angles(0, -beta, 0) * CFrame.new(r, -drop + 0.35, 0) * CFrame.Angles(0, 0.35, 0),
				FOAM:Lerp(Color3.fromRGB(180, 214, 212), share), Enum.Material.SmoothPlastic, false)
			piece.Transparency = 0.3 + share * 0.45
			piece.CastShadow = false
		end
	end
	arms:SetAttribute("Centre", vortex)
	arms:SetAttribute("Spin", 0.5)
	arms.Parent = parent
	CollectionService:AddTag(arms, "SunkenWhirlRing")

	-- WHAT THE WATER IS CARRYING ROUND: a plank, a barrel, a lifebuoy, a crate. Nothing gets out.
	local debris = Instance.new("Model")
	debris.Name = "WhirlDebris"
	for index = 0, 5 do
		local beta = index * math.pi / 3
		local r = VORTEX_R * rng:NextNumber(0.55, 0.92)
		local at = CFrame.new(vortex) * CFrame.Angles(0, -beta, 0) * CFrame.new(r, -FUNNEL_DEPTH * (r / VORTEX_R) ^ 1.6 * 0.4, 0)
		if index % 3 == 0 then
			cityBlock(debris, "Plank", Vector3.new(7, 0.5, 1.4), at * CFrame.Angles(0, rng:NextNumber(0, 3), math.rad(12)),
				Color3.fromRGB(120, 100, 76))
		elseif index % 3 == 1 then
			local barrel = column(debris, "Barrel", 3, at.Position, at.Position.Y - 1.6, at.Position.Y + 1.6,
				Color3.fromRGB(150, 90, 60), false)
			if barrel then
				barrel.CanCollide = false
			end
		else
			for k = 0, 7 do
				local a = k * math.pi / 4
				block(debris, "Lifebuoy", Vector3.new(0.8, 0.5, 0.8),
					at * CFrame.new(math.cos(a) * 1.6, 0, math.sin(a) * 1.6),
					if k % 2 == 0 then Color3.fromRGB(200, 80, 66) else Color3.fromRGB(232, 228, 216),
					Enum.Material.SmoothPlastic, false)
			end
		end
	end
	debris:SetAttribute("Centre", vortex)
	debris:SetAttribute("Spin", 0.62)
	debris.Parent = parent
	CollectionService:AddTag(debris, "SunkenWhirlRing")

	-- ===== THE SWIRL =====
	--
	-- WATER, NOT A MODEL. The funnel's rings are only the water's skin; what makes it read as a real
	-- whirlpool is water MOVING over it, the way the sea came through the aquarium's glass: streaks of
	-- spray and foam drawn out along the way the water goes. Carriers ride round the funnel at every
	-- depth (tagged with the rings, so each client turns them with the rings, faster further in), and
	-- each throws spray gently IN, toward the middle and down: a carrier going round while its spray
	-- drifts in draws a spiral, so the whole surface is spiral arms of foam winding into the hole, never
	-- the same twice. Streaks laid along their own speed, as the torrent at the aquarium's window is.
	do
		local swirl = Instance.new("Model")
		swirl.Name = "WhirlSwirl"
		local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
		local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
		for index = 0, 17 do
			local share = (index % 6) / 6 + 0.08
			local r = VORTEX_R * (1 - share * 0.85)
			local beta = index * 2 * math.pi / 18 * 7
			local drop = FUNNEL_DEPTH * share ^ 1.6
			local at = CFrame.new(vortex) * CFrame.Angles(0, -beta, 0) * CFrame.new(r, -drop + 0.4, 0)
			-- The carrier's -X looks in at the middle; its front is the way round the water goes.
			local carrier = block(swirl, "SwirlCarrier", Vector3.new(1, 1, 1), at * CFrame.Angles(0, math.pi / 2, 0), FOAM,
				Enum.Material.SmoothPlastic, false)
			carrier.Transparency = 1
			local inward = Instance.new("Attachment")
			inward.Name = "In"
			-- Emitting toward the middle, and a little down the funnel's slope.
			inward.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(0, -0.35, 1))
			inward.Parent = carrier
			local streak = Instance.new("ParticleEmitter")
			streak.Texture = SMOKE
			streak.Color = ColorSequence.new(FOAM:Lerp(Color3.fromRGB(150, 196, 196), share))
			streak.LightEmission = 0.15
			streak.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1 - share * 0.5), NumberSequenceKeypoint.new(1, 2.4 - share)})
			streak.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.6, 0.72),
				NumberSequenceKeypoint.new(1, 1) })
			streak.Lifetime = NumberRange.new(1.4, 2.4)
			streak.Speed = NumberRange.new(2.5, 5)
			streak.SpreadAngle = Vector2.new(10, 10)
			streak.Acceleration = Vector3.new(0, -3, 0)
			streak.Drag = 0.6
			streak.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
			streak.EmissionDirection = Enum.NormalId.Front
			streak.Rate = 14
			streak.Parent = inward
			-- Glints on it, the light catching the water as it goes round.
			local glint = Instance.new("ParticleEmitter")
			glint.Texture = SPARK
			glint.Color = ColorSequence.new(Color3.fromRGB(230, 246, 242))
			glint.LightEmission = 0.5
			glint.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.05) })
			glint.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
			glint.Lifetime = NumberRange.new(0.6, 1.1)
			glint.Speed = NumberRange.new(1, 3)
			glint.SpreadAngle = Vector2.new(30, 30)
			glint.EmissionDirection = Enum.NormalId.Front
			glint.Rate = 6
			glint.Parent = inward
		end
		swirl:SetAttribute("Centre", vortex)
		-- Faster than the outer rings: the water speeds up as it goes in, and the arms trail behind it.
		swirl:SetAttribute("Spin", 1.1)
		swirl.Parent = parent
		CollectionService:AddTag(swirl, "SunkenWhirlRing")
		-- THE HOLE POURS: at the bottom of the funnel, streaks of water going down into the drain, fast.
		local pour = block(parent, "WhirlPour", Vector3.new(4, 1, 4), CFrame.new(vortex - Vector3.new(0, FUNNEL_DEPTH - 0.5, 0)),
			FOAM, Enum.Material.SmoothPlastic, false)
		pour.Transparency = 1
		local down = Instance.new("ParticleEmitter")
		down.Texture = SMOKE
		down.Color = ColorSequence.new(Color3.fromRGB(170, 212, 206))
		down.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0.8) })
		down.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		down.Lifetime = NumberRange.new(0.6, 1)
		down.Speed = NumberRange.new(14, 22)
		down.SpreadAngle = Vector2.new(12, 12)
		down.Acceleration = Vector3.new(0, -30, 0)
		down.Orientation = Enum.ParticleOrientation.VelocityParallel
		down.Squash = NumberSequence.new(1.4)
		down.EmissionDirection = Enum.NormalId.Bottom
		down.Rate = 40
		down.Parent = pour
	end

	-- THE THROAT BREATHES: a column of bubbles rising out of the drain up the middle of the funnel, and
	-- spray thrown up where it meets the surface -- moving whatever the client is doing.
	local breath = block(parent, "WhirlThroat", Vector3.new(3, 1, 3), CFrame.new(vortex - Vector3.new(0, FUNNEL_DEPTH, 0)),
		FOAM, Enum.Material.SmoothPlastic, false)
	breath.Transparency = 1
	local rising = Instance.new("ParticleEmitter")
	rising.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	rising.Color = ColorSequence.new(Color3.fromRGB(226, 244, 240))
	rising.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.8) })
	rising.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	rising.Lifetime = NumberRange.new(1.4, 2.2)
	rising.Speed = NumberRange.new(6, 10)
	rising.EmissionDirection = Enum.NormalId.Top
	rising.SpreadAngle = Vector2.new(18, 18)
	rising.RotSpeed = NumberRange.new(-180, 180)
	rising.Rate = 28
	rising.Parent = breath

	-- SPRAY blown off the rim, all the way round, and THE ROAR of it, which you hear from along the
	-- route before the pier.
	for index = 0, 7 do
		local beta = index * math.pi / 4
		local host = block(parent, "RimSpray", Vector3.new(1, 1, 1), CFrame.new(vortex) * CFrame.Angles(0, -beta, 0)
			* CFrame.new(VORTEX_R + 1, 0.4, 0), FOAM, Enum.Material.SmoothPlastic, false)
		host.Transparency = 1
		local spray = Instance.new("ParticleEmitter")
		spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
		spray.Color = ColorSequence.new(Color3.fromRGB(236, 246, 242))
		spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3.5) })
		spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		spray.Lifetime = NumberRange.new(0.8, 1.4)
		spray.Speed = NumberRange.new(2, 4)
		spray.EmissionDirection = Enum.NormalId.Top
		spray.SpreadAngle = Vector2.new(25, 25)
		spray.Acceleration = Vector3.new(0, -3, 0)
		spray.Rate = 6
		spray.Parent = host
	end
	local roarHost = block(parent, "WhirlRoar", Vector3.new(1, 1, 1), CFrame.new(vortex), FOAM, Enum.Material.SmoothPlastic, false)
	roarHost.Transparency = 1
	sound(roarHost, "Roar", WATER_SOUND, 0.32, 0.7, 170, true):Play()

	-- THE MIST over it, which is what you see from along the route before you see anything else.
	local mistHost = block(parent, "WhirlMist", Vector3.new(VORTEX_R * 2, 2, VORTEX_R * 2),
		CFrame.new(vortex + Vector3.new(0, 1, 0)), FOAM, Enum.Material.SmoothPlastic, false)
	mistHost.Transparency = 1
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.fromRGB(236, 246, 242))
	mist.LightEmission = 0.4
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10), NumberSequenceKeypoint.new(1, 30) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.82),
		NumberSequenceKeypoint.new(0.4, 0.9), NumberSequenceKeypoint.new(1, 1) })
	mist.Lifetime = NumberRange.new(3, 6)
	mist.Speed = NumberRange.new(1, 4)
	mist.SpreadAngle = Vector2.new(60, 60)
	mist.Acceleration = Vector3.new(0, 2, 0)
	mist.Rate = 5
	mist.Parent = mistHost

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

	-- THE DRAIN: a concrete collar on the harbour floor, bars across it, and the SHAFT under it with a
	-- floor at the bottom where the rider ends up. The shaft was sixteen flat black panels, and falling
	-- down it looked like falling past cardboard. It is a lined drain now: old wet brick in courses, an
	-- iron flange every ten studs where its sections were bolted, a rusted service ladder down one side,
	-- a caged lamp every twenty studs that still works (just: they flicker, SunkenCityClient), and the
	-- harbour pouring down its walls in streaks, the way the sea poured through the aquarium's glass.
	local collarR = 12
	local brickWet = Color3.fromRGB(46, 42, 40)
	for index = 0, 19 do
		local beta = index * 2 * math.pi / 20
		if index < 16 then
			local b16 = index * 2 * math.pi / 16
			cityBlock(parent, "DrainCollar", Vector3.new(collarR - DRAIN_R, 1.6, 2 * math.pi * collarR / 16 + 0.3),
				CFrame.new(vortex.X, floorY + 0.8, vortex.Z) * CFrame.Angles(0, -b16, 0) * CFrame.new((collarR + DRAIN_R) / 2, 0, 0), STONE)
		end
		local wall = block(parent, "ShaftWall", Vector3.new(1, SHAFT_DEPTH, 2 * math.pi * (DRAIN_R + 0.5) / 20 + 0.3),
			CFrame.new(vortex.X, floorY - SHAFT_DEPTH / 2, vortex.Z) * CFrame.Angles(0, -beta, 0) * CFrame.new(DRAIN_R + 0.5, 0, 0),
			brickWet:Lerp(SHAFT, (index % 3) * 0.2), Enum.Material.Brick, false)
		wall.Reflectance = 0.06
	end
	do
		-- THE FLANGES, every ten studs down.
		for depth = 6, SHAFT_DEPTH - 4, 10 do
			for index = 0, 15 do
				local beta = index * 2 * math.pi / 16
				block(parent, "ShaftFlange", Vector3.new(0.7, 0.7, 2 * math.pi * DRAIN_R / 16 + 0.2),
					CFrame.new(vortex.X, floorY - depth, vortex.Z) * CFrame.Angles(0, -beta, 0) * CFrame.new(DRAIN_R - 0.15, 0, 0),
					Color3.fromRGB(78, 60, 50), Enum.Material.CorrodedMetal, false)
			end
		end
		-- THE LADDER, rails and rungs, down the side away from the outfall.
		local side = CFrame.new(vortex.X, floorY, vortex.Z) * CFrame.new(DRAIN_R - 0.9, 0, 0)
		for _, dz in ipairs({ -0.8, 0.8 }) do
			block(parent, "ShaftLadder", Vector3.new(0.2, SHAFT_DEPTH, 0.2), side * CFrame.new(0, -SHAFT_DEPTH / 2, dz),
				Color3.fromRGB(96, 70, 54), Enum.Material.CorrodedMetal, false)
		end
		for depth = 1.5, SHAFT_DEPTH - 1, 1.6 do
			block(parent, "ShaftRung", Vector3.new(0.18, 0.18, 1.6), side * CFrame.new(0, -depth, 0),
				Color3.fromRGB(96, 70, 54), Enum.Material.CorrodedMetal, false)
		end
		-- THE LAMPS, caged, on alternating sides, and a real light in each.
		for k, depth in ipairs({ 14, 34, 52 }) do
			local beta = k * 2.1
			local at = CFrame.new(vortex.X, floorY - depth, vortex.Z) * CFrame.Angles(0, -beta, 0) * CFrame.new(DRAIN_R - 0.5, 0, 0)
			local fitting = block(parent, "SluiceLamp", Vector3.new(0.6, 1.2, 1), at, Color3.fromRGB(240, 222, 180),
				Enum.Material.SmoothPlastic, false)
			local bulb = Instance.new("PointLight")
			bulb.Brightness = 1
			bulb.Range = 16
			bulb.Color = Color3.fromRGB(255, 214, 160)
			bulb.Parent = fitting
			CollectionService:AddTag(fitting, "SunkenSluiceLamp")
			for bar = -1, 1 do
				block(parent, "LampCage", Vector3.new(0.12, 1.4, 0.12), at * CFrame.new(-0.4, 0, bar * 0.4),
					Color3.fromRGB(46, 44, 42), Enum.Material.Metal, false)
			end
		end
		-- THE HARBOUR POURING DOWN THE WALLS: four streams of streaks from the collar to the sluice.
		for k = 0, 3 do
			local beta = k * math.pi / 2 + 0.4
			local top = block(parent, "ShaftPour", Vector3.new(0.4, 0.4, 3),
				CFrame.new(vortex.X, floorY - 0.5, vortex.Z) * CFrame.Angles(0, -beta, 0) * CFrame.new(DRAIN_R - 0.6, 0, 0),
				FOAM, Enum.Material.SmoothPlastic, false)
			top.Transparency = 1
			local sheet = Instance.new("ParticleEmitter")
			sheet.Texture = "rbxasset://textures/particles/smoke_main.dds"
			sheet.Color = ColorSequence.new(Color3.fromRGB(170, 206, 200))
			sheet.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 2) })
			sheet.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
			sheet.Lifetime = NumberRange.new(1.6, 2.2)
			sheet.Speed = NumberRange.new(10, 16)
			sheet.SpreadAngle = Vector2.new(4, 20)
			sheet.Acceleration = Vector3.new(0, -24, 0)
			sheet.Orientation = Enum.ParticleOrientation.VelocityParallel
			sheet.Squash = NumberSequence.new(1.3)
			sheet.EmissionDirection = Enum.NormalId.Bottom
			sheet.Rate = 16
			sheet.Parent = top
		end
	end
	for index = 0, 2 do
		cityBlock(parent, "Grate", Vector3.new(0.5, 0.5, DRAIN_R * 2), CFrame.new(vortex.X, floorY + 1.2, vortex.Z)
			* CFrame.Angles(0, index * math.pi / 3, 0), Color3.fromRGB(60, 58, 54), Enum.Material.Metal)
	end
	-- Thick, its top where it always was: a thin floor is one a fast body can pass through in a step.
	block(parent, "ShaftFloor", Vector3.new(DRAIN_R * 2 + 2, 6, DRAIN_R * 2 + 2),
		CFrame.new(vortex.X, floorY - SHAFT_DEPTH - 3, vortex.Z), SHAFT, Enum.Material.SmoothPlastic, true)

	-- ===== AND SOMEWHERE TO ARRIVE =====
	--
	-- The ride used to end in a black cylinder with a floor, which is an ending only in the sense
	-- that it stops. At the bottom of a harbour drain there is a SLUICE: a brick chamber with the
	-- water still coming down one wall, a grating underfoot, a bulkhead lamp that still works, a
	-- ladder nobody is coming down, and a door to somewhere this level does not go. You are in it
	-- for the few seconds before the banner, and it is the last thing the level says.
	local bottom = floorY - SHAFT_DEPTH
	local brick = Color3.fromRGB(58, 54, 50)
	-- OUTFALL 3 leaves the sluice on its -X side (where its door always was): the three lengths of
	-- wall facing that way are left out, and a lintel spans the gap over the culvert's roof.
	local OUT_L, OUT_HALF, OUT_H = 140, 5, 9
	for index = 0, 15 do
		local beta = index * 2 * math.pi / 16
		if index < 7 or index > 9 then
			block(parent, "SluiceWall", Vector3.new(2, 16, 2 * math.pi * (DRAIN_R + 1) / 16 + 0.4),
				CFrame.new(vortex.X, bottom + 8, vortex.Z) * CFrame.Angles(0, -beta, 0) * CFrame.new(DRAIN_R + 1, 0, 0),
				brick, Enum.Material.Brick, true)
		end
	end
	block(parent, "SluiceLintel", Vector3.new(2, 16 - OUT_H, OUT_HALF * 2 + 4),
		CFrame.new(vortex.X - DRAIN_R - 1, bottom + OUT_H + (16 - OUT_H) / 2, vortex.Z), brick, Enum.Material.Brick, true)
	-- The grating you land on, and the sump under it.
	for index = -3, 3 do
		block(parent, "SluiceGrate", Vector3.new(DRAIN_R * 2 - 1, 0.3, 0.6),
			CFrame.new(vortex.X, bottom + 0.4, vortex.Z + index * 1.8), Color3.fromRGB(70, 68, 62),
			Enum.Material.Metal, true)
	end
	-- The water still coming in, down one wall and into the sump.
	local inflow = block(parent, "SluiceInflow", Vector3.new(0.8, 15, 5),
		CFrame.new(vortex.X + DRAIN_R - 1, bottom + 8, vortex.Z), SURFACE, Enum.Material.Glass, false)
	inflow.Transparency = 0.45
	inflow.CastShadow = false
	local splashHost = block(parent, "SluiceSplash", Vector3.new(4, 1, 4),
		CFrame.new(vortex.X + DRAIN_R - 2, bottom + 1, vortex.Z), FOAM, Enum.Material.SmoothPlastic, false)
	splashHost.Transparency = 1
	local spatter = Instance.new("ParticleEmitter")
	spatter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spatter.Color = ColorSequence.new(Color3.fromRGB(226, 240, 236))
	spatter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1) })
	spatter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	spatter.Lifetime = NumberRange.new(0.5, 1.1)
	spatter.Speed = NumberRange.new(2, 6)
	spatter.SpreadAngle = Vector2.new(50, 50)
	spatter.Acceleration = Vector3.new(0, -30, 0)
	spatter.Rate = 26
	spatter.Parent = splashHost
	ambience(splashHost, "SluiceFall", 0.55, 0.4, 10, 60)
	-- The bulkhead lamp, in its cage, on the wall across from the ladder (the wall it was on opposite
	-- the inflow is the way out now).
	local lampAt = CFrame.new(vortex.X, bottom + 9, vortex.Z + DRAIN_R - 1.2) * CFrame.Angles(0, math.pi / 2, 0)
	local fitting = block(parent, "SluiceLamp", Vector3.new(1.2, 2.2, 2.2), lampAt, Color3.fromRGB(240, 226, 190),
		Enum.Material.Glass, false)
	fitting.Transparency = 0.2
	local bulb = Instance.new("PointLight")
	bulb.Brightness = 1.6
	bulb.Range = 26
	bulb.Color = Color3.fromRGB(255, 226, 172)
	bulb.Shadows = true
	bulb.Parent = fitting
	CollectionService:AddTag(fitting, "SunkenSluiceLamp")
	for index = -1, 1 do
		block(parent, "LampCage", Vector3.new(0.3, 2.6, 0.2), lampAt * CFrame.new(0.7, 0, index * 0.8),
			Color3.fromRGB(46, 44, 42), Enum.Material.Metal, false)
	end
	-- A ladder up the wall, a door that does not open, and a sign by it.
	local ladder = Instance.new("TrussPart")
	ladder.Name = "SluiceLadder"
	ladder.Size = Vector3.new(2, 14, 2)
	ladder.CFrame = CFrame.new(vortex.X, bottom + 7, vortex.Z - DRAIN_R + 1.4)
	ladder.Anchored = true
	ladder.Color = Color3.fromRGB(70, 68, 62)
	ladder.Material = Enum.Material.Metal
	ladder.Parent = parent
	-- The door to OUTFALL 3, burst open by the water and flat back against the culvert's wall.
	local door = block(parent, "SluiceDoor", Vector3.new(0.5, 8, 5),
		CFrame.new(vortex.X - DRAIN_R - 4, bottom + 4, vortex.Z + OUT_HALF - 0.9) * CFrame.Angles(0, math.rad(78), 0),
		Color3.fromRGB(80, 90, 86), Enum.Material.Metal, false)
	label(door, Enum.NormalId.Right, "OUTFALL 3", Color3.fromRGB(216, 222, 214))

	-- ===== OUTFALL 3, AND THE PUMPING STATION AT ITS END =====
	--
	-- The water at the bottom of the drain goes somewhere, and so does the rider (SunkenPath.outfall):
	-- a brick culvert OUT_L long running out under the harbour, a concrete rib every twelve studs, two
	-- rusted pipes along its roof, a caged lamp every twenty-four studs on alternating walls, and the
	-- stream down the middle of its floor that carries you. Things written on its walls. At its end
	-- the HARBOUR PUMPING STATION: three dead pumps with their gauges at nothing, the desk with the
	-- gate lever down and a note on it, the key board with one hook empty, and by the door the time
	-- clock, stopped at eight minutes to midnight, and a card sticking out of the rack with the
	-- rider's own name on it: key holder, not clocked in (written when a ride starts). One door further
	-- on, shut: the lower gallery. All of it far under the sea floor, where nothing else is.
	local HALL_L, HALL_W, HALL_H = 32, 36, 16
	local concrete = Color3.fromRGB(84, 86, 84)
	local iron = Color3.fromRGB(66, 70, 74)
	local rust = Color3.fromRGB(112, 72, 50)
	local x0 = vortex.X - DRAIN_R - 0.5 -- where the culvert leaves the sluice
	local x1 = x0 - OUT_L -- where it opens into the station
	local oz = vortex.Z
	local waterY = bottom + 0.7
	local function site(x: number, y: number, dz: number): CFrame
		return CFrame.new(x, bottom + y, oz + dz)
	end
	local midX = (x0 + x1) / 2
	block(parent, "OutfallFloor", Vector3.new(OUT_L + 2, 1, OUT_HALF * 2 + 4), site(midX, -0.5, 0), concrete, Enum.Material.Concrete, true)
	block(parent, "OutfallRoof", Vector3.new(OUT_L + 2, 1.5, OUT_HALF * 2 + 4), site(midX, OUT_H + 0.75, 0), concrete, Enum.Material.Concrete, true)
	for _, side in ipairs({ -1, 1 }) do
		block(parent, "OutfallWall", Vector3.new(OUT_L + 2, OUT_H, 2), site(midX, OUT_H / 2, side * (OUT_HALF + 1)), brick,
			Enum.Material.Brick, true)
		local pipe = block(parent, "OutfallPipe", Vector3.new(OUT_L, 1, 1), site(midX, OUT_H - 1.6, side * (OUT_HALF - 1.4)), rust,
			Enum.Material.CorrodedMetal, false)
		pipe.Shape = Enum.PartType.Cylinder
	end
	-- The stream, its water sliding down the culvert (SunkenCityClient moves the texture, as the
	-- whirlpool's).
	local stream = block(parent, "OutfallStream", Vector3.new(OUT_L + 1, 0.7, OUT_HALF * 2 - 2.4), site(midX, 0.35, 0), SURFACE,
		Enum.Material.SmoothPlastic, false)
	stream.Transparency = 0.3
	stream.Reflectance = 0.08
	local streamFlow = Instance.new("Texture")
	streamFlow.Name = "Flow"
	streamFlow.Face = Enum.NormalId.Top
	streamFlow.Texture = "rbxasset://textures/water/normal_1.dds"
	streamFlow.StudsPerTileU, streamFlow.StudsPerTileV = 9, 9
	streamFlow.Transparency = 0.5
	streamFlow.Color3 = Color3.fromRGB(226, 242, 238)
	streamFlow.Parent = stream
	stream:SetAttribute("Ring", 3)
	CollectionService:AddTag(stream, "SunkenWhirlFlow")
	for x = x0 - 6, x1 + 4, -12 do
		for _, side in ipairs({ -1, 1 }) do
			block(parent, "OutfallRib", Vector3.new(1.4, OUT_H, 0.8), site(x, OUT_H / 2, side * (OUT_HALF - 0.3)), concrete,
				Enum.Material.Concrete, true)
		end
		block(parent, "OutfallRib", Vector3.new(1.4, 0.9, OUT_HALF * 2), site(x, OUT_H - 0.45, 0), concrete, Enum.Material.Concrete, false)
	end
	local lampCount = 0
	for x = x0 - 12, x1 + 8, -24 do
		lampCount += 1
		local side = if lampCount % 2 == 0 then 1 else -1
		local fitting = block(parent, "SluiceLamp", Vector3.new(1.4, 0.8, 0.8), site(x, OUT_H - 2.2, side * (OUT_HALF - 0.4)),
			Color3.fromRGB(240, 226, 190), Enum.Material.SmoothPlastic, false)
		fitting.Transparency = 0.2
		local glow = Instance.new("PointLight")
		glow.Brightness = 1.3
		glow.Range = 20
		glow.Color = Color3.fromRGB(255, 214, 160)
		glow.Parent = fitting
		CollectionService:AddTag(fitting, "SunkenSluiceLamp")
		block(parent, "LampCage", Vector3.new(1.6, 0.15, 1), site(x, OUT_H - 1.75, side * (OUT_HALF - 0.4)), iron, Enum.Material.Metal, false)
	end
	-- THINGS WRITTEN ON ITS WALLS, faint.
	for _, writing in ipairs({ { 8, 1, "OUTFALL 3" }, { 46, -1, "WHERE IS THE KEY MAN" }, { 84, 1, "IIII IIII IIII IIII II" },
		{ 118, -1, "KEY HOLDER ONLY BEYOND THIS POINT" } }) do
		local side = writing[2] :: number
		local plate = block(parent, "OutfallWriting", Vector3.new(10, 2.2, 0.1), site(x0 - (writing[1] :: number), 4.6, side * (OUT_HALF - 0.05)),
			brick, Enum.Material.Brick, false)
		plate.Transparency = 1
		label(plate, if side > 0 then Enum.NormalId.Front else Enum.NormalId.Back, writing[3] :: string, Color3.fromRGB(196, 190, 172))
	end

	-- THE STATION.
	local hallX = x1 - HALL_L / 2
	local far = x1 - HALL_L
	block(parent, "StationFloor", Vector3.new(HALL_L + 4, 1, HALL_W + 4), site(hallX, -0.5, 0), concrete, Enum.Material.Concrete, true)
	block(parent, "StationRoof", Vector3.new(HALL_L + 4, 1.5, HALL_W + 4), site(hallX, HALL_H + 0.75, 0), concrete, Enum.Material.Concrete, true)
	for _, side in ipairs({ -1, 1 }) do
		block(parent, "StationWall", Vector3.new(HALL_L + 4, HALL_H, 2), site(hallX, HALL_H / 2, side * (HALL_W / 2 + 1)), concrete,
			Enum.Material.Concrete, true)
	end
	block(parent, "StationWall", Vector3.new(2, HALL_H, HALL_W + 4), site(far - 1, HALL_H / 2, 0), concrete, Enum.Material.Concrete, true)
	local sideW = (HALL_W - OUT_HALF * 2) / 2
	for _, side in ipairs({ -1, 1 }) do
		block(parent, "StationWall", Vector3.new(2, HALL_H, sideW + 2), site(x1 + 1, HALL_H / 2, side * (OUT_HALF + (sideW + 2) / 2)),
			concrete, Enum.Material.Concrete, true)
	end
	block(parent, "StationWall", Vector3.new(2, HALL_H - OUT_H, OUT_HALF * 2), site(x1 + 1, OUT_H + (HALL_H - OUT_H) / 2, 0), concrete,
		Enum.Material.Concrete, true)
	local stationSign = block(parent, "StationSign", Vector3.new(0.2, 2, 12), site(x1 - 0.1, OUT_H + 2.6, 0), Color3.fromRGB(214, 190, 60),
		Enum.Material.SmoothPlastic, false)
	label(stationSign, Enum.NormalId.Left, "HARBOUR PUMPING STATION. OUTFALL 3", Color3.fromRGB(30, 30, 30))
	-- Where the stream goes: through a grate into the sump, churning.
	for bar = -4, 4 do
		block(parent, "SumpGrate", Vector3.new(4, 0.2, 0.35), site(x1 - 2.5, 0.1, bar * 0.9), iron, Enum.Material.Metal, false)
	end
	local sump = block(parent, "SumpChurn", Vector3.new(4, 0.4, 7), site(x1 - 2.5, 0.3, 0), FOAM, Enum.Material.SmoothPlastic, false)
	sump.Transparency = 1
	local churn = Instance.new("ParticleEmitter")
	churn.Texture = "rbxasset://textures/particles/smoke_main.dds"
	churn.Color = ColorSequence.new(Color3.fromRGB(214, 232, 228))
	churn.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2) })
	churn.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	churn.Lifetime = NumberRange.new(0.5, 1)
	churn.Speed = NumberRange.new(1, 3)
	churn.SpreadAngle = Vector2.new(40, 40)
	churn.EmissionDirection = Enum.NormalId.Top
	churn.Rate = 14
	churn.Parent = sump
	ambience(sump, "SumpSound", 0.5, 0.35, 10, 60)
	-- The pumps, dead, their gauges at nothing.
	for index, dz in ipairs({ -11, 0, 11 }) do
		local base = site(far + 6, 0, dz)
		block(parent, "PumpPlinth", Vector3.new(8, 1, 8), base * CFrame.new(0, 0.5, 0), concrete, Enum.Material.Concrete, true)
		local casing = block(parent, "PumpCasing", Vector3.new(9, 6, 6), base * CFrame.new(0, 5.5, 0) * CFrame.Angles(0, 0, math.pi / 2),
			iron, Enum.Material.Metal, true)
		casing.Shape = Enum.PartType.Cylinder
		for _, y in ipairs({ 1.6, 5.5, 9.4 }) do
			local flange = block(parent, "PumpFlange", Vector3.new(0.5, 7, 7), base * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2),
				rust, Enum.Material.CorrodedMetal, false)
			flange.Shape = Enum.PartType.Cylinder
		end
		local riser = block(parent, "PumpRiser", Vector3.new(HALL_H - 10, 2.2, 2.2),
			base * CFrame.new(0, 10 + (HALL_H - 10) / 2, 0) * CFrame.Angles(0, 0, math.pi / 2), rust, Enum.Material.CorrodedMetal, false)
		riser.Shape = Enum.PartType.Cylinder
		local gauge = block(parent, "PumpGauge", Vector3.new(0.3, 1.4, 1.4), base * CFrame.new(3.1, 6.5, 0), Color3.fromRGB(226, 222, 204),
			Enum.Material.SmoothPlastic, false)
		gauge.Shape = Enum.PartType.Cylinder
		label(gauge, Enum.NormalId.Right, "0", Color3.fromRGB(40, 40, 40))
		local plate = block(parent, "PumpPlate", Vector3.new(0.1, 0.7, 2.4), base * CFrame.new(4.05, 0.5, 0), BRASS, Enum.Material.Metal, false)
		label(plate, Enum.NormalId.Right, "PUMP " .. index, Color3.fromRGB(30, 30, 30))
	end
	-- The desk: the gate lever down, and the note.
	local desk = site(x1 - 14, 0, 10)
	block(parent, "ControlDesk", Vector3.new(6, 3, 2.4), desk * CFrame.new(0, 1.5, 0), iron, Enum.Material.Metal, true)
	block(parent, "GateLeverBase", Vector3.new(1, 0.6, 1), desk * CFrame.new(1.6, 3.3, 0), iron, Enum.Material.Metal, false)
	block(parent, "GateLever", Vector3.new(0.3, 2.4, 0.3), desk * CFrame.new(1.6, 3.3, 0) * CFrame.Angles(0, 0, math.rad(-55))
		* CFrame.new(0, 1.2, 0), rust, Enum.Material.CorrodedMetal, false)
	local gatePlate = block(parent, "GatePlate", Vector3.new(3, 0.8, 0.1), desk * CFrame.new(0, 2, -1.25), Color3.fromRGB(214, 190, 60),
		Enum.Material.SmoothPlastic, false)
	label(gatePlate, Enum.NormalId.Front, "GATES: CLOSED", Color3.fromRGB(30, 30, 30))
	local note = block(parent, "GateNote", Vector3.new(1.4, 0.05, 1.9), desk * CFrame.new(-1.4, 3.03, 0) * CFrame.Angles(0, math.rad(8), 0),
		Color3.fromRGB(236, 230, 210), Enum.Material.SmoothPlastic, false)
	label(note, Enum.NormalId.Top, "IF THE WATER COMES, OPEN THE GATES. THE KEY IS WITH THE KEY HOLDER.", Color3.fromRGB(50, 44, 40))
	-- The key board, one hook empty.
	local wallZ = HALL_W / 2 - 0.1
	block(parent, "KeyBoard", Vector3.new(4.2, 3, 0.2), site(x1 - 20, 5, wallZ), Color3.fromRGB(120, 96, 70), Enum.Material.Wood, false)
	for hook = 0, 5 do
		local hx = x1 - 21.75 + hook * 0.7
		block(parent, "KeyHook", Vector3.new(0.15, 0.15, 0.4), site(hx, 5.9, wallZ - 0.3), iron, Enum.Material.Metal, false)
		if hook ~= 3 then
			block(parent, "Key", Vector3.new(0.18, 0.8, 0.06), site(hx, 5.35, wallZ - 0.45), BRASS, Enum.Material.Metal, false)
		else
			local tag = block(parent, "KeyTag", Vector3.new(0.6, 0.35, 0.05), site(hx, 4.3, wallZ - 0.2), Color3.fromRGB(236, 230, 210),
				Enum.Material.SmoothPlastic, false)
			label(tag, Enum.NormalId.Front, "OUTFALL 3", Color3.fromRGB(150, 30, 30))
		end
	end
	-- The time clock, stopped, and the cards; the one sticking out is the rider's.
	local clockBox = block(parent, "TimeClock", Vector3.new(1.6, 2, 1), site(x1 - 5, 5, HALL_W / 2 - 0.5), Color3.fromRGB(150, 150, 140),
		Enum.Material.Metal, false)
	label(clockBox, Enum.NormalId.Front, "11:52", Color3.fromRGB(30, 30, 30))
	block(parent, "CardRack", Vector3.new(3, 3.6, 0.3), site(x1 - 8, 4.6, HALL_W / 2 - 0.15), iron, Enum.Material.Metal, false)
	for row = 0, 3 do
		for column = 0, 2 do
			if not (row == 1 and column == 1) then
				block(parent, "Card", Vector3.new(0.7, 0.7, 0.05), site(x1 - 8.9 + column * 0.9, 3.5 + row * 0.8, HALL_W / 2 - 0.33),
					Color3.fromRGB(230, 224, 206), Enum.Material.SmoothPlastic, false)
			end
		end
	end
	local card = block(parent, "TimeCard", Vector3.new(0.9, 1.3, 0.05), site(x1 - 8, 4.9, HALL_W / 2 - 0.5), Color3.fromRGB(242, 236, 216),
		Enum.Material.SmoothPlastic, false)
	local cardGui = Instance.new("SurfaceGui")
	cardGui.Face = Enum.NormalId.Front
	cardGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	cardGui.PixelsPerStud = 120
	cardGui.LightInfluence = 1
	cardGui.Parent = card
	local cardWords = Instance.new("TextLabel")
	cardWords.Name = "Words"
	cardWords.Size = UDim2.fromScale(1, 1)
	cardWords.BackgroundTransparency = 1
	cardWords.TextScaled = true
	cardWords.Font = Enum.Font.Code
	cardWords.TextColor3 = Color3.fromRGB(40, 36, 34)
	cardWords.Text = "KEY HOLDER\n\n14 AUG\nNOT CLOCKED IN"
	cardWords.Parent = cardGui
	-- The lamp over the desk, hung on its cable; a green one over the far door.
	block(parent, "LampCable", Vector3.new(0.15, 2.4, 0.15), site(x1 - 14, HALL_H - 1.2, 4), iron, Enum.Material.Metal, false)
	local hanging = block(parent, "SluiceLamp", Vector3.new(1.2, 0.8, 1.2), site(x1 - 14, HALL_H - 2.8, 4), Color3.fromRGB(226, 236, 240),
		Enum.Material.SmoothPlastic, false)
	hanging.Transparency = 0.2
	local cold = Instance.new("PointLight")
	cold.Brightness = 1.8
	cold.Range = 36
	cold.Color = Color3.fromRGB(214, 230, 240)
	cold.Shadows = true
	cold.Parent = hanging
	CollectionService:AddTag(hanging, "SunkenSluiceLamp")
	local farDoor = block(parent, "LowerGalleryDoor", Vector3.new(0.5, 8, 5), site(far + 0.3, 4, 0), iron, Enum.Material.Metal, true)
	label(farDoor, Enum.NormalId.Right, "LOWER GALLERY. NO ENTRY.", Color3.fromRGB(216, 222, 214))
	local exitLamp = block(parent, "EmergencyLamp", Vector3.new(0.4, 0.6, 1.4), site(far + 0.2, 9, 0), Color3.fromRGB(120, 210, 150),
		Enum.Material.SmoothPlastic, false)
	local green = Instance.new("PointLight")
	green.Brightness = 0.6
	green.Range = 12
	green.Color = Color3.fromRGB(110, 220, 140)
	green.Parent = exitLamp
	for _, puddle in ipairs({ { x1 - 12, -6, 5 }, { x1 - 22, 8, 7 }, { far + 12, -14, 4 } }) do
		local wet = block(parent, "Puddle", Vector3.new(puddle[3], 0.05, puddle[3] * 0.7), site(puddle[1], 0.03, puddle[2]),
			Color3.fromRGB(30, 40, 42), Enum.Material.SmoothPlastic, false)
		wet.Reflectance = 0.35
		wet.Transparency = 0.2
	end
	-- WHERE THE RIDE GOES, for SunkenPath.outfallFrame on the server and every client; and what the
	-- reveal looks at.
	parent:SetAttribute("OutfallFrom", Vector3.new(vortex.X, bottom + 3, vortex.Z))
	parent:SetAttribute("OutfallMouth", Vector3.new(x0 - 1, bottom + 3, oz))
	parent:SetAttribute("OutfallTo", Vector3.new(x1 - 9, bottom + 3, oz))
	parent:SetAttribute("OutfallWater", waterY)
	parent:SetAttribute("RevealEye", site(far + 3, HALL_H - 2.5, -HALL_W / 2 + 3).Position)
	parent:SetAttribute("RevealCard", card.Position)
	parent:SetAttribute("RevealCardEye", card.Position + Vector3.new(0, 0.1, -2.4))
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
	local chunks = level.placedChunks
	local minOrigin = math.huge
	for _, entry in ipairs(chunks) do
		minOrigin = math.min(minOrigin, base.Y + entry.surfaceY)
	end
	local h = SunkenCityService.heights(minOrigin)
	-- Any water a run that was stopped mid-way left behind goes first.
	SunkenCityService.clearWater()
	waterLevel = h.water
	litLeft = LIT_WINDOWS
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

	-- ===== The route, which everything else is placed from =====
	local finish: CFrame = level.finishFrame
	local lastCap = capOf(chunks[#chunks].model)
	if lastCap then
		finish = finish + Vector3.new(0, lastCap.Position.Y + lastCap.Size.Y / 2 - finish.Position.Y, 0)
	end
	local route = routeOf(chunks, finish, h.water)
	local centre = Vector3.new(route.middle.X, 0, route.middle.Z)

	-- ===== The finale first: the harbour is laid out round where it is =====
	local vortex = finale(model, finish, h.floor, rng)

	-- ===== The aquarium, off the checkpoint nearest two fifths of the way along =====
	--
	-- On the LEFT of the street, and the dry flat on the right, so the two things you can go inside
	-- are never on the same side of you.
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
	if best then
		local cap = capOf(best.model)
		local frame = if cap then besideFrame(cap, -1) else nil
		if frame then
			aq = aquarium(model, frame, h.floor, rng)
		end
	end

	-- ===== The last dry flat, off the checkpoint nearest seven tenths of the way along =====
	--
	-- Never the aquarium's checkpoint, and never so near the end that it stands in the harbour.
	local flat: Flat? = nil
	local flatPick: any, flatGap = nil, math.huge
	for index, entry in ipairs(chunks) do
		if entry.chunkId == "S1_Straight" and index > 1 and index < #chunks - 3 and entry ~= best then
			local miss = math.abs(index - FLAT_SHARE * #chunks)
			if miss < flatGap then
				flatPick, flatGap = entry, miss
			end
		end
	end
	if flatPick then
		local cap = capOf(flatPick.model)
		local frame = if cap then besideFrame(cap, 1) else nil
		if frame and alongOf(route, frame.Position) < route.total - harbourAlong(route) then
			flat = dryFlat(model, frame, h.floor)
		end
	end

	-- ===== The water: the surface with its two holes, and the floor with the drain's =====
	--
	-- NO MURK LID. There used to be a flat dark sheet thirty-five studs down, and it did exactly
	-- what a lid does: from the route the city under you was one black plane with a few roofs
	-- poking through it. The depth is drawn by the water's own colour on the buildings (see
	-- drowned) and by the haze, which describe distance instead of ending it.
	local holes: { Hole } = { { centre = vortex, outer = VORTEX_R + 3, inner = VORTEX_R - 1 } }
	if aq then
		table.insert(holes, { centre = aq.tower, outer = ROT_R, inner = ROT_R - ROT_WALL })
	end
	sheet(sea, "Water", centre, h.water, 0.4, SURFACE, Enum.Material.Glass, 0.4, holes)
	sheet(sea, "SeaFloor", centre, h.floor, 4, SILT, Enum.Material.Sand, 0,
		{ { centre = vortex, outer = 12, inner = DRAIN_R } })

	-- ===== The plaza and the clock tower, off the street about a third of the way along =====
	local plazaAt, plazaDir = alongRoute(route, route.total * 0.34)
	local plazaSide = Vector3.yAxis:Cross(plazaDir)
	local plaza = plazaAt + plazaSide * 230
	clockTower(sea, Vector3.new(plaza.X, 0, plaza.Z), h.floor)

	-- ===== The city, round everything that has already claimed its space =====
	local ferrisAt: Vector3? = nil
	local ferrisWhy = ""
	local standing: { { at: Vector3, reach: number } } = {}
	local function blocked(point: Vector3, reach: number): boolean
		for _, other in ipairs(standing) do
			if Vector3.new(point.X - other.at.X, 0, point.Z - other.at.Z).Magnitude < reach + other.reach + 12 then
				return true
			end
		end
		if ferrisAt and Vector3.new(point.X - ferrisAt.X, 0, point.Z - ferrisAt.Z).Magnitude < reach + FERRIS.clear then
			return true
		end
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
		if Vector3.new(point.X - plaza.X, 0, point.Z - plaza.Z).Magnitude < reach + PLAZA_RADIUS + 14 then
			return true
		end
		return false
	end
	-- The Ferris wheel's square, before the city is laid round it: the first place along the street,
	-- on the side away from the plaza and the horizon, that is clear of the aquarium and the flat,
	-- out of the harbour, and far enough off the route for something that breaks the surface.
	-- The side away from the plaza first, at FERRIS.out, then further out, then the other side: five
	-- places on one side left it nowhere in play, and the report says why when nothing fits at all.
	local refused: { [string]: number } = {}
	for _, side in ipairs({ 1, -1 }) do
		for _, out in ipairs({ FERRIS.out, FERRIS.out + 40, FERRIS.out + 80 }) do
			for _, share in ipairs(FERRIS.shares) do
				if ferrisAt then
					break
				end
				local s = route.total * share
				local at, dir = alongRoute(route, s)
				local spot = at - Vector3.yAxis:Cross(dir) * (out * side)
				local near, away = nearRoute(route, spot)
				-- And out of what the gallery's window looks at: its legs stood just past the tank, in the
				-- view that belongs to what comes up out of the dark.
				local outOfWindow = not aq or Vector3.new(spot.X - aq.far.X, 0, spot.Z - aq.far.Z).Magnitude > FERRIS.window
				if s < route.total - harbourAlong(route) - FERRIS.clear and near - FERRIS.reach >= EMERGE_CLEAR + ROUTE_REACH
					and near + FERRIS.reach <= HORROR_OUT * 0.8 - 250
					and outOfWindow and not blocked(spot, FERRIS.clear) then
					ferrisWheel(cityFolder, spot, away, h.floor, rng)
					ferrisAt = spot
				else
					local why = "on the aquarium, the flat or the plaza"
					if s >= route.total - harbourAlong(route) - FERRIS.clear then
						why = "in the harbour"
					elseif near - FERRIS.reach < EMERGE_CLEAR + ROUTE_REACH then
						why = "too near the route"
					elseif near + FERRIS.reach > HORROR_OUT * 0.8 - 250 then
						why = "out where the things swim"
					elseif not outOfWindow then
						why = "in the window's view"
					end
					refused[why] = (refused[why] or 0) + 1
				end
			end
		end
	end
	local refusals = {}
	for why, count in pairs(refused) do
		table.insert(refusals, ("%d %s"):format(count, why))
	end
	table.sort(refusals)
	ferrisWhy = table.concat(refusals, ", ")
	-- The landmarks, before the city too: the first place near where each would like to be that is
	-- clear, off the route, short of the things at the back and out of the harbour.
	local landmarkBase: { [string]: CFrame } = {}
	for _, spec in ipairs(LANDMARKS) do
		for step = 0, 8 do
			if landmarkBase[spec.name] then
				break
			end
			for _, turn in ipairs({ 1, -1 }) do
				local share = spec.share + turn * step * 0.03
				local s = route.total * share
				if not landmarkBase[spec.name] and share > 0.04 and s < route.total - harbourAlong(route) - spec.reach then
					local at, dir = alongRoute(route, s)
					local spot = at + Vector3.yAxis:Cross(dir) * (spec.side * spec.out)
					local near, away = nearRoute(route, spot)
					if near - spec.reach >= EMERGE_CLEAR + ROUTE_REACH and near + spec.reach <= HORROR_OUT * 0.8 - 250
						and not blocked(spot, spec.reach + 12) then
						landmarkBase[spec.name] = landmark(cityFolder, spec, spot, -away, h.floor)
						table.insert(standing, { at = spot, reach = spec.reach })
					end
				end
			end
		end
	end
	local lots = city(cityFolder, route, h.floor, blocked, rng)
	-- Where the road signs will stand, worked out first so the street keeps its vehicles out from
	-- under their legs.
	local alongs: { number } = {}
	for _, share in ipairs({ 0.16, 0.36, 0.58, 0.78 }) do
		local s = route.total * share
		local spot = alongRoute(route, s)
		local clearOfAq = not aq or (Vector3.new(spot.X - aq.tower.X, 0, spot.Z - aq.tower.Z)).Magnitude > 60
		local clearOfFlat = not flat or (Vector3.new(spot.X - flat.centre.X, 0, spot.Z - flat.centre.Z)).Magnitude > 60
		if clearOfAq and clearOfFlat and s < route.total - harbourAlong(route) then
			table.insert(alongs, s)
		end
	end
	boulevard(cityFolder, route, h.floor, rng, blocked, alongs)
	local streetThings = streetKit.sideStreets(cityFolder, route, h.floor, rng, blocked)
		+ streetKit.metro(cityFolder, route, h.floor, rng, blocked, alongs)
	shafts(sea, route, h.floor, rng)
	shoals(sea, route, h.floor, rng, blocked)

	-- ===== The road signs over the street, and the harbour at the end of it =====
	gantries(cityFolder, route, h.floor, alongs)
	swimmers(sea, route, h.floor, rng, blocked)
	gulls(sea, route, rng, blocked)
	harbour(sea, route, vortex, h.floor, rng)

	-- ===== The ambience, which the client lets fall away when the thing is under you =====
	local host = block(model, "AmbienceHost", Vector3.new(1, 1, 1), CFrame.new(centre.X, h.water, centre.Z), FOAM,
		Enum.Material.SmoothPlastic, false)
	host.Transparency = 1
	ambience(host, "Lapping", 0.5, 0.16, route.total / 2 + 300, route.total / 2 + 800)
	ambience(host, "Wind", 0.3, 0.08, route.total / 2 + 300, route.total / 2 + 800)

	-- ===== The thing's brief, for SunkenCityClient =====
	--
	-- The route's line itself, as studs on a plan: it patrols the boulevard now rather than
	-- swimming a ring, so what it needs is the street, not a radius.
	local line = {}
	for _, at in ipairs(route.points) do
		table.insert(line, string.format("%.1f,%.1f", at.X, at.Z))
	end
	sea:SetAttribute("MonsterLine", table.concat(line, ";"))
	sea:SetAttribute("MonsterSpeed", MONSTER_SPEED)
	sea:SetAttribute("MonsterDepth", MONSTER_DEPTH)
	sea:SetAttribute("MonsterBob", MONSTER_BOB)
	sea:SetAttribute("MonsterBobPeriod", MONSTER_BOB_PERIOD)
	sea:SetAttribute("MonsterGirth", MONSTER_GIRTH)
	sea:SetAttribute("MonsterSwing", MONSTER_SWING)
	sea:SetAttribute("MonsterSwingWave", MONSTER_SWING_WAVE)
	sea:SetAttribute("MonsterKeep", MONSTER_KEEP)
	sea:SetAttribute("WaterY", h.water)
	-- Where the road signs hang, which it never surfaces under (SunkenPath.surfacing).
	local quiet = {}
	for _, s in ipairs(alongs) do
		table.insert(quiet, string.format("%.1f", s))
	end
	sea:SetAttribute("QuietAlong", table.concat(quiet, ","))
	sea:SetAttribute("Epoch", workspace:GetServerTimeNow())
	-- THE THING ON THE HORIZON: where it comes up, far out on one side of the street and running
	-- the way the street runs, and when. Every client works the schedule out from the same epoch,
	-- so everyone looks up at the same moment.
	local farMiddle = route.points[1] + route.forward * (route.total / 2) + route.side * LEVIATHAN_OUT
	sea:SetAttribute("LeviathanFrom", Vector3.new(farMiddle.X, h.water, farMiddle.Z) - route.forward * (LEVIATHAN_LONG / 2))
	sea:SetAttribute("LeviathanTo", Vector3.new(farMiddle.X, h.water, farMiddle.Z) + route.forward * (LEVIATHAN_LONG / 2))
	sea:SetAttribute("LeviathanFirst", SCHEDULE.leviathanFirst)
	sea:SetAttribute("LeviathanEvery", SCHEDULE.leviathanEvery)
	-- The rain, on its own shared schedule.
	sea:SetAttribute("RainFirst", SCHEDULE.rainFirst)
	sea:SetAttribute("RainEvery", SCHEDULE.rainEvery)
	sea:SetAttribute("RainLength", SCHEDULE.rainLength)
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
	-- THE PEOPLE STILL HERE (Townsfolk): the attendant by the notice in the gallery, a fisherman on
	-- the pier, and whoever that is on the Deco tower's ledge. Spawned, because building a character
	-- waits on the avatar service, and the level should not.
	if Townsfolk then
		local deco = landmarkBase.Deco
		task.spawn(function()
			local skin = Color3.fromRGB(226, 192, 158)
			if aq then
				local keeper = Townsfolk.spawn(model, "Attendant", aq.keeper, "stand",
					{ skin, Color3.fromRGB(40, 56, 92), Color3.fromRGB(46, 48, 54) })
				if keeper then
					Townsfolk.wear(keeper, "Cap", Vector3.new(0.5, 1.35, 1.35), Color3.fromRGB(34, 46, 80), "Head",
						CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
					Townsfolk.wear(keeper, "Visor", Vector3.new(1.1, 0.1, 0.55), Color3.fromRGB(24, 26, 30), "Head",
						CFrame.new(0, 0.42, -0.72))
					Townsfolk.wear(keeper, "Badge", Vector3.new(0.5, 0.3, 0.06), Color3.fromRGB(214, 190, 110), "UpperTorso",
						CFrame.new(0.45, 0.35, -0.52))
					if Townsfolk.route then
						Townsfolk.route("Attendant", aq.escape)
					end
				end
			end
			-- On a crate by the rail, a little way before the drain, rod out over the water.
			local seat = finish * CFrame.new(-PIER_W / 2 + 2.6, 0, 7)
			local crate = block(model, "Crate", Vector3.new(1.8, 1.7, 1.8), seat * CFrame.new(0.5, 0.85, 0),
				Color3.fromRGB(128, 100, 70), Enum.Material.WoodPlanks, false)
			crate.CanCollide = false
			local facing = CFrame.lookAt((seat * CFrame.new(0, 1.7, 0)).Position, (seat * CFrame.new(-1, 1.7, 0)).Position)
			local fisher = Townsfolk.spawn(model, "Fisherman", facing, "sit",
				{ skin, Color3.fromRGB(226, 186, 44), Color3.fromRGB(52, 58, 66) })
			if fisher then
				Townsfolk.wear(fisher, "HatBrim", Vector3.new(0.12, 2.2, 2.2), Color3.fromRGB(226, 186, 44), "Head",
					CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
				Townsfolk.wear(fisher, "HatCrown", Vector3.new(0.7, 1.3, 1.3), Color3.fromRGB(226, 186, 44), "Head",
					CFrame.new(0, 0.85, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
				-- The rod and its line, placed in the world first and welded where they are.
				local root = fisher.model:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local hand = (facing * CFrame.new(0.6, 0.3, -1.2)).Position
					local tip = hand + facing.LookVector * 7 + Vector3.new(0, 3.2, 0)
					local lineEnd = Vector3.new(tip.X, h.water - 0.5, tip.Z)
					Townsfolk.wear(fisher, "Rod", Vector3.new(0.14, 0.14, (tip - hand).Magnitude), Color3.fromRGB(70, 56, 40),
						"HumanoidRootPart", root.CFrame:ToObjectSpace(CFrame.lookAt((hand + tip) / 2, tip)))
					Townsfolk.wear(fisher, "Line", Vector3.new(0.05, 0.05, (tip - lineEnd).Magnitude), Color3.fromRGB(220, 220, 214),
						"HumanoidRootPart", root.CFrame:ToObjectSpace(CFrame.lookAt((tip + lineEnd) / 2, lineEnd)))
				end
			end
			-- Nobody. On the Deco tower's first ledge, facing the street.
			if deco then
				-- Faceless, and its head follows you from three hundred studs off.
				Townsfolk.spawn(model, "Watcher", deco * CFrame.new(0, 160, -20), "stand",
					{ Color3.fromRGB(34, 36, 40), Color3.fromRGB(34, 36, 40), Color3.fromRGB(30, 32, 36) }, true, 320)
			end
		end)
	end
	-- And what lives in it, counted off the tags the client draws them from: if these are not zero and
	-- SunkenCityClient's own report says it drew none, the fault is on the client.
	local living = { SunkenSwimmer = 0, SunkenFishShoal = 0, SunkenKelp = 0, SunkenGull = 0 }
	local everything = model:GetDescendants()
	for _, item in ipairs(everything) do
		for tag, n in pairs(living) do
			if CollectionService:HasTag(item, tag) then
				living[tag] = n + 1
			end
		end
	end
	print(("SunkenCityService: water at %d, a %d-stud street, %d lots, %s, %s, the drain at the end, "
		.. "%d parts; %d swimmers, %d shoals, %d strands of kelp, %d gulls%s."):format(math.floor(h.water), math.floor(route.total), lots,
		if aq then "the aquarium off a checkpoint" else "NO aquarium (no checkpoint to put it on)",
		(if flat then "the dry flat off another, with the flooded floor under it" else "no dry flat")
			.. (if ferrisAt then ", the Ferris wheel" else ", NO Ferris wheel (nowhere clear: " .. ferrisWhy .. ")")
			.. (", %d of %d landmarks, %d things in the side streets"):format(#standing, #LANDMARKS, streetThings), #everything,
		living.SunkenSwimmer, living.SunkenFishShoal, living.SunkenKelp, living.SunkenGull,
		-- Which of the wheel's meshes it stood with, and why any were refused (SeaRig).
		if SeaRig then "; the wheel's " .. SeaRig.summary() else ""))
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
-- it ends far below the kill plane. A minute: the lobby now waits for the ending to be watched (its
-- captions read) and then six seconds more, and a rider caught by the plane in between is put back on
-- the route in the middle of the last scene.
function SunkenCityService.ownsFall(player: Player): boolean
	if riding[player] then
		return true
	end
	local landed = arrivedAt[player]
	return landed ~= nil and os.clock() - landed < 60
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

-- The event the rider's client answers on to say it is drawing the ride, as Sky Pools' does.
local drainEvent: RemoteEvent? = nil
local drawing: { [Player]: boolean } = {}
-- IN STUDIO, WHETHER EACH CLIENT IS RUNNING SunkenCityClient: `heard` is filled by the hello each
-- one sends as it starts (see IS THE CLIENT RUNNING, below).
local studio = { heard = {} :: { [Player]: string }, loads = false }
local function drainRemote(): RemoteEvent?
	if drainEvent then
		return drainEvent
	end
	local folder = ReplicatedStorage:FindFirstChild("RemoteEvents") or ReplicatedStorage:WaitForChild("RemoteEvents", 5)
	local event = folder and (folder:FindFirstChild("SunkenRide") or folder:WaitForChild("SunkenRide", 5))
	if event and event:IsA("RemoteEvent") then
		drainEvent = event
		event.OnServerEvent:Connect(function(player: Player, what: any, version: any)
			-- HELLO, from a client's SunkenCityClient as it starts: it is running, and which version.
			if what == "hello" then
				studio.heard[player] = tostring(version)
				print(("SunkenCityService: SunkenCityClient is running for %s (%s)"):format(player.Name, tostring(version)))
				return
			end
			-- Only from someone the drain actually has, and it decides nothing: the server keeps
			-- the clock and puts them at the bottom itself.
			if riding[player] then
				drawing[player] = true
			end
		end)
	end
	return drainEvent
end
-- Listening from the start, so the hello a client sends as it joins is heard.
task.spawn(drainRemote)

local function ride(player: Player, root: BasePart, humanoid: Humanoid, vortex: Vector3, shaftBottom: number,
	onArrive: ((Player) -> ())?, outfall: any?)
	riding[player] = true
	arrivedAt[player] = nil
	drawing[player] = nil
	humanoid.PlatformStand = true
	splash(Vector3.new(root.Position.X, waterLevel, root.Position.Z))
	local rush = sound(root, "DrainRush", WATER_SOUND, 0.65, 0.6, 60, true)
	rush:Play()
	local seconds = if SunkenPath then SunkenPath.DRAIN_SECONDS else DRAIN_SECONDS
	local spec = {
		vortex = vortex,
		from = root.Position,
		funnelY = vortex.Y - FUNNEL_DEPTH,
		bottomY = shaftBottom + 3,
	}
	-- AND ON DOWN THE OUTFALL, where the level has one (SunkenPath.outfallFrame), then the reveal.
	local outSeconds = if outfall and SunkenPath and SunkenPath.OUTFALL_SECONDS then SunkenPath.OUTFALL_SECONDS else 0
	local total = seconds + outSeconds
	local began = workspace:GetServerTimeNow()
	local remote = drainRemote()
	if remote then
		remote:FireClient(player, spec.vortex, spec.from, spec.funnelY, spec.bottomY, began, seconds,
			if outfall then outfall.path else nil, if outfall then outfall.reveal else nil)
		-- AND EVERY CLIENT flails them: arms thrown up and waving, legs kicking, head back -- weaker
		-- once the current has them. Played on each client from the same clock, because joints turned
		-- on one client are seen on that client only (SunkenCityClient).
		remote:FireAllClients("flail", player, began, total, seconds)
	end
	-- THEIR NAME ON THE CARD at the station, before the camera gets there.
	local card = if outfall then outfall.card else nil
	local cardWords = card and card:FindFirstChild("Words", true)
	if cardWords and cardWords:IsA("TextLabel") then
		cardWords.Text = ("KEY HOLDER\n%s\n14 AUG\nNOT CLOCKED IN"):format(string.upper(player.DisplayName))
	end
	-- IF THEIR OWN CLIENT NEVER TAKES THE RIDE, say why it looks the way it does: that is
	-- SunkenCityClient not running for them (and in Studio the check below says what is wrong). The
	-- server draws the ride then, flailing and all, but without the camera.
	task.delay(2, function()
		if riding[player] and not drawing[player] then
			warn(("SunkenCityService: %s's client did not take the ride down the drain, so SunkenCityClient is "
				.. "not running for them; the server is drawing the ride instead, without its camera"):format(player.Name))
		end
	end)
	-- THEY CRY OUT, over their head, for everyone to see: help, and the rest of it.
	--
	-- LETTERED LIKE A VOICE, NOT A WARNING SIGN. It was heavy capitals in a hard red outline, changing
	-- every 0.85 seconds, too fast to read and loud in the wrong way. Now the screams are scrawled
	-- (Permanent Marker), warm white on a soft shadow, and each one lands with a small jolt and stays long
	-- enough to read; once the current has them down the culvert the words go quiet and handwritten
	-- (Kalam), lower case and paler, each one hanging there a while, the way you talk to yourself in the
	-- dark.
	local head = player.Character and player.Character:FindFirstChild("Head")
	local cry: BillboardGui? = nil
	if head and head:IsA("BasePart") then
		local gui = Instance.new("BillboardGui")
		gui.Name = "DrainCry"
		gui.Size = UDim2.fromOffset(280, 76)
		gui.StudsOffset = Vector3.new(0, 3.6, 0)
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = 140
		local holder = Instance.new("Frame")
		holder.Size = UDim2.fromScale(1, 1)
		holder.BackgroundTransparency = 1
		holder.Parent = gui
		local pop = Instance.new("UIScale")
		pop.Parent = holder
		local function label(name: string, offset: number): TextLabel
			local text = Instance.new("TextLabel")
			text.Name = name
			text.AnchorPoint = Vector2.new(0.5, 0.5)
			text.Position = UDim2.new(0.5, offset, 0.5, offset)
			text.Size = UDim2.fromScale(1, 1)
			text.BackgroundTransparency = 1
			text.TextScaled = true
			text.Text = ""
			text.Parent = holder
			return text
		end
		-- The shadow, a little down and right of the words: softer than an outline, and it reads on water,
		-- brick and sky alike.
		local shadow = label("Shadow", 3)
		shadow.TextColor3 = Color3.fromRGB(8, 14, 18)
		local words = label("Words", 0)
		words.TextStrokeColor3 = Color3.fromRGB(24, 18, 22)
		gui.Adornee = head
		gui.Parent = head
		cry = gui
		local function speak(text: string, quiet: boolean)
			for _, piece in ipairs({ shadow, words }) do
				piece.Font = if quiet then Enum.Font.Kalam else Enum.Font.PermanentMarker
				piece.Text = text
				piece.TextTransparency = 1
			end
			words.TextColor3 = if quiet then Color3.fromRGB(206, 222, 218) else Color3.fromRGB(252, 244, 230)
			words.TextStrokeTransparency = 1
			holder.Size = if quiet then UDim2.fromScale(0.72, 0.62) else UDim2.fromScale(1, 1)
			holder.Position = if quiet then UDim2.fromScale(0.14, 0.19) else UDim2.fromScale(0, 0)
			holder.Rotation = if quiet then math.random(-2, 2) else math.random(-6, 6)
			pop.Scale = if quiet then 1 else 1.2
			-- (Looked up here: this file is near Luau's limit of top-level locals.)
			local TweenService = game:GetService("TweenService")
			local land = TweenInfo.new(if quiet then 0.6 else 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(pop, land, { Scale = 1 }):Play()
			TweenService:Create(words, land, { TextTransparency = 0, TextStrokeTransparency = if quiet then 1 else 0.6 }):Play()
			TweenService:Create(shadow, land, { TextTransparency = if quiet then 0.65 else 0.45 }):Play()
		end
		speak("HELP!", false)
		task.spawn(function()
			local cries = { "HELP!", "AAAAH!", "HELP ME!", "NOOOO!", "SOMEBODY!", "AAAAAAH!" }
			-- And quieter, once the current has them down the culvert.
			local carried = { "...help...", "where is this", "the gates...", "somebody...", "what keys?" }
			local index = 1
			while gui.Parent do
				local quiet = workspace:GetServerTimeNow() - began > seconds
				-- Long enough to read, and the quiet ones longer still.
				task.wait(if quiet then 2.8 else 1.7)
				if not gui.Parent then
					break
				end
				quiet = workspace:GetServerTimeNow() - began > seconds
				local list = if quiet then carried else cries
				index = index % #list + 1
				speak(list[index], quiet)
			end
		end)
	end
	-- THE RIDE IS SEEN, by everyone: bubbles and spray streaming off the rider all the way down.
	local trail = Instance.new("Attachment")
	trail.Name = "DrainTrail"
	trail.Parent = root
	for _, spec2 in ipairs({
		{ "rbxasset://textures/particles/sparkles_main.dds", Color3.fromRGB(224, 244, 240), 0.25, 0.6, 50, 6 },
		{ "rbxasset://textures/particles/smoke_main.dds", Color3.fromRGB(232, 244, 242), 1, 2.6, 22, -4 },
	}) do
		local e = Instance.new("ParticleEmitter")
		e.Texture = spec2[1]
		e.Color = ColorSequence.new(spec2[2])
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec2[3]), NumberSequenceKeypoint.new(1, spec2[4]) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.6, 1.4)
		e.Speed = NumberRange.new(2, 6)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, spec2[6], 0)
		e.Rate = spec2[5]
		e.Parent = trail
	end
	-- THE SERVER'S OWN RIDE IS NOT THE STIFF ONE: the rider is grabbed, spun round the funnel and sent
	-- head over heels down the shaft (SunkenPath.tumble) and, after a moment with no answer from their
	-- client, flails, the server turning their joints by the same numbers the client would
	-- (SunkenPath.flail) -- a Motor6D's C0 or, for the newer avatar joints, the parent-side attachment
	-- (SunkenPath.joints / SunkenPath.turn), which every client is sent. A player's character here has
	-- AnimationConstraints and no Motor6D, so turning only Motor6Ds turned nothing. The joints are given
	-- back the moment their client takes the ride, and at the bottom.
	--
	-- AND THE SERVER HOLDS THEM while it draws them: it takes their physics (their own client would
	-- otherwise keep adding gravity to their speed under every position it is handed, and at the bottom
	-- all of that speed at once put them straight through the sluice's floor), and clears their speed
	-- every step.
	local turned: { [string]: any } = {}
	local held = false
	local splashed = false
	-- THE LANDING: a burst of spray and a thud -- in the sluice, and where they are set down.
	local function thud(at: Vector3, count: number)
		local burst = Instance.new("Part")
		burst.Name = "SluiceLanding"
		burst.Size = Vector3.new(4, 0.4, 4)
		burst.CFrame = CFrame.new(at)
		burst.Anchored = true
		burst.CanCollide = false
		burst.CanQuery = false
		burst.CanTouch = false
		burst.Transparency = 1
		burst.Parent = workspace
		local splashes = Instance.new("ParticleEmitter")
		splashes.Texture = "rbxasset://textures/particles/smoke_main.dds"
		splashes.Color = ColorSequence.new(Color3.fromRGB(226, 240, 238))
		splashes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.6) })
		splashes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		splashes.Lifetime = NumberRange.new(0.5, 1)
		splashes.Speed = NumberRange.new(8, 16)
		splashes.SpreadAngle = Vector2.new(60, 60)
		splashes.EmissionDirection = Enum.NormalId.Top
		splashes.Acceleration = Vector3.new(0, -30, 0)
		splashes.Rate = 0
		splashes.Parent = burst
		splashes:Emit(count)
		sound(burst, "Landing", THUD_SOUND, 0.6, 1.2, 60, false):Play()
		Debris:AddItem(burst, 3)
	end
	local r6 = player.Character ~= nil and player.Character:FindFirstChild("UpperTorso") == nil
	local function giveBack()
		for _, joint in pairs(turned) do
			if Poses then
				pcall(Poses.turn, joint, CFrame.identity)
			end
		end
		table.clear(turned)
	end
	while root.Parent do
		local t = workspace:GetServerTimeNow() - began
		local u = t / seconds
		if t >= total then
			break
		end
		if not splashed and t >= seconds - 0.1 then
			splashed = true
			thud(Vector3.new(vortex.X, spec.bottomY - 2.6, vortex.Z), 45)
		end
		-- THE SERVER MOVES NOBODY once the rider's own client has the ride. Until it answers -- or
		-- if it never does -- this is the ride.
		if not drawing[player] and SunkenPath then
			if not held and t > 0.3 then
				held = pcall(function()
					root:SetNetworkOwner(nil)
				end)
			end
			local frame: CFrame
			if t < seconds then
				frame = SunkenPath.drainFrame(spec, u)
				if SunkenPath.tumble then
					frame *= SunkenPath.tumble(u, os.clock())
				end
			else
				frame = SunkenPath.outfallFrame(outfall.path, (t - seconds) / outSeconds, os.clock())
			end
			root.CFrame = frame
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			local character = player.Character
			if t > 0.6 and Poses and character then
				if next(turned) == nil then
					turned = Poses.joints(character)
				end
				local w = Poses.weight(t, total) * (if t > seconds then 0.4 else 1)
				for name, joint in pairs(turned) do
					local turn = Poses.flail(name, t, w, r6)
					if turn then
						Poses.turn(joint, turn)
					end
				end
			end
		elseif next(turned) ~= nil then
			giveBack()
		end
		task.wait()
	end
	giveBack()
	trail:Destroy()
	if root.Parent then
		-- Set down: on the station's landing on their feet, or (with no outfall) in the sluice.
		root.CFrame = if outfall and SunkenPath then SunkenPath.outfallFrame(outfall.path, 1, os.clock())
			else CFrame.new(vortex.X, spec.bottomY, vortex.Z)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		if outfall then
			thud(outfall.path.to - Vector3.new(0, 2.6, 0), 20)
		elseif not splashed then
			thud(Vector3.new(vortex.X, spec.bottomY - 2.6, vortex.Z), 45)
		end
	end
	if held then
		pcall(function()
			root:SetNetworkOwner(player)
		end)
	end
	rush:Destroy()
	if cry then
		cry:Destroy()
	end
	humanoid.PlatformStand = false
	riding[player] = nil
	drawing[player] = nil
	arrivedAt[player] = os.clock()
	-- THE REVEAL: the station held on screen (SunkenCityClient plays it), and then the level is over --
	-- the card, and a few seconds to look round before the lobby.
	if outfall and SunkenPath and SunkenPath.REVEAL_SECONDS then
		task.wait(SunkenPath.REVEAL_SECONDS)
	end
	if onArrive then
		onArrive(player)
	end
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

-- ===== THE GLASS =====
--
-- THE GALLERY'S WINDOW can be tapped -- the one with the notice beside it asking you not to -- and
-- nothing else: the tunnel's panes answered too once, and a tunnel you could crack with a nudge made
-- the notice pointless. It answers. A tap thuds and the fish bolt (SunkenCityClient reads `Tapped` off the model). Keep
-- tapping one pane and it takes the strain: at TAP.crack a crack stars out from where you hit it,
-- at TAP.crack2 it spreads and starts to weep, and at TAP.breaks it goes. The sea comes in. Every
-- client sees the pane burst and the water rise (`Flood`), and everyone still inside once it has
-- risen is washed out: back to their checkpoint in Chill -- the chunk the aquarium hangs off -- and
-- back to the start in Hardcore. After TAP.hold the water is gone and the glass is whole again,
-- because nothing in this game stays broken.
--
-- In Hardcore the old answer still comes first: three taps in five seconds, once a run, and
-- something outside knocks back.

local function glass(model: Model, onTaken: ((Player) -> ())?): { RBXScriptConnection }
	local CRACK_SOUND = "rbxassetid://135061782882830"
	local FLOOD_SETTLE = 4 -- seconds after the water is gone before the attendant says anything
	local CRACK_MENDS = 25
	local function crackLines(pane: BasePart, stage: number, rng: Random, inside: Vector3)
		local size = pane.Size
		local thin = if size.X <= size.Y and size.X <= size.Z then 1 elseif size.Y <= size.Z then 2 else 3
		local axes = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
		local extents = { size.X, size.Y, size.Z }
		local normal = axes[thin]
		local u = axes[if thin == 1 then 2 else 1]
		local v = axes[if thin == 3 then 2 else 3]
		local uHalf = extents[if thin == 1 then 2 else 1] / 2
		local vHalf = extents[if thin == 3 then 2 else 3] / 2
		local origin = u * rng:NextNumber(-uHalf, uHalf) * 0.5 + v * rng:NextNumber(-vHalf, vHalf) * 0.5
		local count = if stage == 1 then 7 else 12
		for _ = 1, count do
			local a = rng:NextNumber(0, 2 * math.pi)
			local dir = u * math.cos(a) + v * math.sin(a)
			local long = if stage == 1 then rng:NextNumber(0.8, 2.2) else rng:NextNumber(1.6, 3.8)
			local mid = origin + dir * (long / 2)
			local line = block(pane, "Crack", Vector3.new(long, extents[thin] + 0.06, 0.07),
				pane.CFrame * CFrame.fromMatrix(mid, dir, normal), Color3.fromRGB(236, 246, 246), Enum.Material.SmoothPlastic, false)
			line.Transparency = 0.2
			line.CastShadow = false
		end
		if stage >= 2 then
			local leakAt = Instance.new("Attachment")
			leakAt.Name = "Crack"
			-- Spraying INTO the aquarium: the attachment's up is the pane's normal, turned to face inside.
			local toward = pane.CFrame:VectorToObjectSpace(inside - pane.Position)
			leakAt.CFrame = CFrame.fromMatrix(origin, u, if toward:Dot(normal) >= 0 then normal else -normal)
			leakAt.Parent = pane
			local leak = Instance.new("ParticleEmitter")
			leak.Texture = "rbxasset://textures/particles/smoke_main.dds"
			leak.Color = ColorSequence.new(Color3.fromRGB(190, 226, 226))
			leak.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.1) })
			leak.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
			leak.Lifetime = NumberRange.new(0.6, 1)
			leak.Speed = NumberRange.new(2, 4)
			leak.SpreadAngle = Vector2.new(15, 15)
			leak.Acceleration = Vector3.new(0, -12, 0)
			leak.Rate = 22
			leak.Parent = leakAt
		end
	end

	local connections: { RBXScriptConnection } = {}
	local panes: { BasePart } = {}
	-- The notice asking you not to tap, which the flood tears off its wall (THE SEA COMING IN).
	local notices: { BasePart } = {}
	for _, item in ipairs(model:GetDescendants()) do
		-- The window with the notice by it, and only that.
		if item:IsA("BasePart") and item.Name == "ViewingWindow" then
			table.insert(panes, item)
		elseif item:IsA("BasePart") and item.Name == "Notice" then
			table.insert(notices, item)
		end
	end
	if #panes == 0 then
		return connections
	end
	local zones = tagged(model, "SunkenAquariumZone")
	-- Which way is inside, from a pane: toward the middle of the nearest zone.
	local function insideOf(pane: BasePart): Vector3
		local best, gap = pane.Position, math.huge
		for _, zone in ipairs(zones) do
			local d = (zone.Position - pane.Position).Magnitude
			if d < gap then
				best, gap = zone.Position, d
			end
		end
		return best
	end
	-- The gallery's own lamp: the light above the window and within a room's width of it.
	local window = model:FindFirstChild("ViewingWindow", true)
	local roomLight: PointLight? = nil
	if window and window:IsA("BasePart") then
		for _, item in ipairs(model:GetDescendants()) do
			local holder = item.Parent
			if item:IsA("PointLight") and holder and holder:IsA("BasePart") and holder.Position.Y > window.Position.Y
				and (holder.Position - window.Position).Magnitude < 16 then
				roomLight = item
			end
		end
	end

	local rng = Random.new(1847)

	-- ===== THE SEA COMING IN =====
	--
	-- AS REAL WATER YOU CAN SWIM IN, drawn here for every player. The pane bursts into shards that are
	-- thrown in and land on the floor, and jagged teeth of it stay in the frame. The sea comes through
	-- the hole in a torrent, falling water and spray with foam churning where it lands, and ONE LEVEL of
	-- TERRAIN WATER rises through the gallery, the tunnel and the tower at one rate: the gallery is full
	-- after TAP.rise and the tower goes on filling to the sea outside. It is the same water as the
	-- flooded floor under the flat, so you swim in it; bubbles come up through it, the aquarium's
	-- leaflets float up on it, and once the hole is under, the sea still comes through it in a rush of
	-- bubbles. Under it the view goes murky and the sound dull (SunkenCityClient). It stays until
	-- TAP.hold, goes down over TAP.drain, and the glass is whole. Nobody is washed out.
	--
	-- It replaces boxes of see-through parts that filled up, which looked like exactly that.
	local terrain = workspace.Terrain
	local SEA_IN = Color3.fromRGB(56, 116, 118)
	local FLOOD_STEP = 0.1 -- seconds between one level of the water and the next
	local INSET = 1 -- studs the water keeps in from a space's sides, so none of it shows through a wall
	local SPRAY = "rbxasset://textures/particles/sparkles_main.dds"
	local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
	local volumes = tagged(model, "SunkenFloodVolume")
	local flood = {
		bits = {} :: { Instance }, -- the teeth, gone when the glass is whole
		registered = false, -- its spaces are on the list of swimmable water cleared with the level
		level = -math.huge, -- where the water is now (the attendant swims by it)
	}

	-- Which of a part's own axes is nearest world up, and which way it points: a volume can be a box
	-- standing up or a cylinder lying on its side stood on end.
	local function upAxis(part: BasePart): (number, number)
		local best, sign, most = 2, 1, -1
		for axis, v in ipairs({ part.CFrame.RightVector, part.CFrame.UpVector, -part.CFrame.LookVector }) do
			local d = v:Dot(Vector3.yAxis)
			if math.abs(d) > most then
				best, sign, most = axis, if d >= 0 then 1 else -1, math.abs(d)
			end
		end
		return best, sign
	end
	local function heightOf(volume: BasePart, axis: number): number
		local size = volume.Size
		return if axis == 1 then size.X elseif axis == 2 then size.Y else size.Z
	end
	-- Each space that floods: how high it goes, and whether it is the tower's cylinder.
	local spaces: { { volume: BasePart, axis: number, bottom: number, top: number, cylinder: boolean } } = {}
	for _, volume in ipairs(volumes) do
		local axis = upAxis(volume)
		local full = heightOf(volume, axis)
		table.insert(spaces, { volume = volume, axis = axis, bottom = volume.Position.Y - full / 2,
			top = volume.Position.Y + full / 2,
			cylinder = volume:IsA("Part") and volume.Shape == Enum.PartType.Cylinder })
	end

	-- THE WATER IN A SPACE, as terrain: `material` from `y0`, `h` high, across the whole space.
	local function slab(space: { volume: BasePart, axis: number, bottom: number, top: number, cylinder: boolean },
		y0: number, h: number, material: Enum.Material)
		local v = space.volume
		local p = v.Position
		if space.cylinder then
			terrain:FillCylinder(CFrame.new(p.X, y0 + h / 2, p.Z), h, math.min(v.Size.Y, v.Size.Z) / 2 - INSET, material)
			return
		end
		local axes = { v.CFrame.RightVector, v.CFrame.UpVector, -v.CFrame.LookVector }
		local sizes = { v.Size.X, v.Size.Y, v.Size.Z }
		local i, k = space.axis % 3 + 1, (space.axis + 1) % 3 + 1
		local across = Vector3.new(axes[i].X, 0, axes[i].Z).Unit
		terrain:FillBlock(CFrame.fromMatrix(Vector3.new(p.X, y0 + h / 2, p.Z), across, Vector3.yAxis),
			Vector3.new(sizes[i] - 2 * INSET, h, sizes[k] - 2 * INSET), material)
	end
	-- Every space's water up to `level` and none over it: all the clearing first, then all the filling,
	-- so where two spaces meet, the water wins.
	local function waterTo(level: number)
		for _, space in ipairs(spaces) do
			local depth = math.clamp(level - space.bottom, 0, space.top - space.bottom)
			local over = space.top - space.bottom - depth
			if over > 0.01 then
				slab(space, space.top - over, over + 1, Enum.Material.Air)
			end
		end
		for _, space in ipairs(spaces) do
			local depth = math.clamp(level - space.bottom, 0, space.top - space.bottom)
			if depth > 0.01 then
				slab(space, space.bottom, depth, Enum.Material.Water)
			end
		end
	end

	-- A part of the flood that is not in the world yet (so everything on it arrives with it).
	local function loose(name: string, size: Vector3, cf: CFrame, colour: Color3, transparency: number): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = cf
		part.Color = colour
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = transparency
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		return part
	end
	local function emitter(parent: Instance, texture: string, colour: Color3, size: { number }, speed: { number },
		life: { number }, direction: Enum.NormalId, spread: number, fall: number): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.Texture = texture
		e.Color = ColorSequence.new(colour)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size[1]), NumberSequenceKeypoint.new(1, size[2]) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.7, 0.55),
			NumberSequenceKeypoint.new(1, 1) })
		e.Speed = NumberRange.new(speed[1], speed[2])
		e.Lifetime = NumberRange.new(life[1], life[2])
		e.EmissionDirection = direction
		e.SpreadAngle = Vector2.new(spread, spread)
		e.Acceleration = Vector3.new(0, fall, 0)
		e.Rate = 0
		e.Parent = parent
		return e
	end
	-- A pane's own axes, and how big it is along each: which is thin (its face), which of the other
	-- two is nearer up, and the one across.
	local function paneAxes(pane: BasePart): ({ Vector3 }, { number }, number, number, number)
		local size = pane.Size
		local axes = { pane.CFrame.RightVector, pane.CFrame.UpVector, -pane.CFrame.LookVector }
		local extents = { size.X, size.Y, size.Z }
		local thin = if size.X <= size.Y and size.X <= size.Z then 1 elseif size.Y <= size.Z then 2 else 3
		local up, most = 0, -1
		for index = 1, 3 do
			if index ~= thin and math.abs(axes[index].Y) > most then
				up, most = index, math.abs(axes[index].Y)
			end
		end
		return axes, extents, thin, up, 6 - thin - up
	end

	-- THE PANE BURSTS: shards thrown in with the sea, falling, tumbling and lying on the floor a while;
	-- and jagged teeth of it left all round the frame until it mends.
	local function shatter(pane: BasePart, inward: Vector3, was: number)
		local axes, extents, thin, up, across = paneAxes(pane)
		for _ = 1, 22 do
			local at = pane.Position + inward * (extents[thin] / 2 + 0.5)
				+ axes[up] * rng:NextNumber(-0.42, 0.42) * extents[up] + axes[across] * rng:NextNumber(-0.42, 0.42) * extents[across]
			local shard = loose("Shard", Vector3.new(0.14, rng:NextNumber(0.4, 1.5), rng:NextNumber(0.3, 1.1)),
				CFrame.new(at) * CFrame.Angles(rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3)),
				pane.Color:Lerp(Color3.new(1, 1, 1), 0.4), 0.3)
			shard.Reflectance = 0.15
			shard.Anchored = false
			shard.CanCollide = true
			shard.Parent = model
			shard.AssemblyLinearVelocity = inward * rng:NextNumber(10, 22) + axes[across] * rng:NextNumber(-5, 5)
				+ Vector3.new(0, rng:NextNumber(-2, 5), 0)
			shard.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9))
			Debris:AddItem(shard, 12)
		end
		for _, edge in ipairs({ { up, across }, { across, up } }) do
			local out, along = edge[1], edge[2]
			for _, side in ipairs({ -1, 1 }) do
				for _ = 1, 3 do
					-- A wedge's long flat face against the frame, its point toward the middle of the hole.
					local h = rng:NextNumber(0.6, 2.2)
					local at = pane.Position + axes[out] * side * (extents[out] / 2 - h / 2)
						+ axes[along] * rng:NextNumber(-0.42, 0.42) * extents[along]
					local tooth = Instance.new("WedgePart")
					tooth.Name = "GlassTooth"
					tooth.Size = Vector3.new(extents[thin] * 0.9, h, rng:NextNumber(0.7, 1.9))
					tooth.CFrame = CFrame.fromMatrix(at, axes[thin] * (if rng:NextNumber() < 0.5 then 1 else -1), -axes[out] * side)
					tooth.Color = pane.Color
					tooth.Material = pane.Material
					tooth.Transparency = math.clamp(was - 0.1, 0.15, 0.7)
					tooth.Anchored = true
					tooth.CanCollide = false
					tooth.CanTouch = false
					tooth.CanQuery = false
					tooth.CastShadow = false
					tooth.Parent = model
					table.insert(flood.bits, tooth)
				end
			end
		end
		-- The sea bursting through, the first seconds, across the whole hole.
		local burst = loose("SeaBursting", Vector3.new(extents[across] * 0.8, extents[up] * 0.7, 0.2),
			CFrame.lookAt(pane.Position + inward * (extents[thin] / 2 + 0.3), pane.Position + inward * 2), SEA_IN, 1)
		local spray = emitter(burst, SMOKE, Color3.fromRGB(206, 234, 232), { 1.2, 4.5 }, { 24, 36 }, { 0.5, 0.9 },
			Enum.NormalId.Front, 14, -24)
		spray.Rate = 160
		burst.Parent = model
		task.delay(2.5, function()
			spray.Rate = 0
		end)
		Debris:AddItem(burst, 4)
	end

	-- THE FLOOD, from the moment the pane goes to the moment the water is gone again.
	local function runFlood(pane: BasePart, inward: Vector3)
		-- The room with the hole in it, whose floor the water rises from at the rate that fills it in
		-- TAP.rise; and the highest any of it goes.
		local room = nil
		local gap = math.huge
		for _, space in ipairs(spaces) do
			local d = (space.volume.Position - pane.Position).Magnitude
			if space.volume.Parent and d < gap then
				room, gap = space, d
			end
		end
		if not room then
			return
		end
		local floor = room.bottom
		local rate = (room.top - room.bottom) / TAP.rise
		local top = floor
		for _, space in ipairs(spaces) do
			top = math.max(top, space.top)
		end
		swimWater.look()
		if not flood.registered then
			-- On the list the level clears when it goes, in case it goes with the water still up.
			flood.registered = true
			for _, space in ipairs(spaces) do
				table.insert(swimWater.fills, { cf = space.volume.CFrame, size = space.volume.Size })
			end
		end

		-- The hole: how wide, where its top and bottom are.
		local axes, extents, thin, up, across = paneAxes(pane)
		local holeTop = pane.Position.Y + math.abs(axes[up].Y) * extents[up] / 2
		local holeBottom = pane.Position.Y - math.abs(axes[up].Y) * extents[up] / 2
		local width = extents[across] * 0.85
		local mouth = pane.Position + inward * (extents[thin] / 2 + 0.6)
		local made: { Instance } = {}

		-- The torrent: falling water and spray through the hole, and, once the hole is under, a rush of
		-- bubbles instead.
		local torrent = loose("SeaPouringIn", Vector3.new(width, extents[up] * 0.8, 0.3), CFrame.lookAt(mouth, mouth + inward),
			SEA_IN, 1)
		local falls = emitter(torrent, SMOKE, Color3.fromRGB(196, 232, 232), { 1.6, 3.4 }, { 8, 14 }, { 0.6, 0.9 },
			Enum.NormalId.Front, 8, -45)
		falls.Orientation = Enum.ParticleOrientation.VelocityParallel
		falls.Squash = NumberSequence.new(1.2)
		local mist = emitter(torrent, SPRAY, Color3.fromRGB(226, 244, 242), { 0.6, 0.15 }, { 18, 28 }, { 0.4, 0.8 },
			Enum.NormalId.Front, 25, -20)
		local inrush = emitter(torrent, SPRAY, Color3.fromRGB(214, 240, 236), { 0.3, 0.6 }, { 10, 16 }, { 1.2, 2 },
			Enum.NormalId.Front, 18, 8)
		local roar = sound(torrent, "Roar", WATER_SOUND, 0.55, 1.1, 140, true)
		torrent.Parent = model
		roar:Play()
		table.insert(made, torrent)

		-- Foam churning where it lands, on the water wherever the water has got to.
		local landing = loose("SeaLanding", Vector3.new(width, 0.4, 4), CFrame.new(mouth), SEA_IN, 1)
		local foam = emitter(landing, SMOKE, Color3.fromRGB(236, 246, 244), { 1.6, 4 }, { 4, 9 }, { 0.6, 1.1 },
			Enum.NormalId.Top, 70, -12)
		local churn = emitter(landing, SPRAY, Color3.fromRGB(230, 246, 242), { 0.4, 0.1 }, { 2, 6 }, { 0.5, 1 },
			Enum.NormalId.Top, 60, -18)
		landing.Parent = model
		table.insert(made, landing)

		-- JETS THROUGH THE CRACKS round the frame, where the teeth of glass still hold: hard and high while
		-- they are above the water, streams of bubbles once they are under it. They fan out toward the
		-- sides, so the attendant, who stands beside the window, is in the spray.
		local jets: { { at: Vector3, water: ParticleEmitter, bubbles: ParticleEmitter } } = {}
		for _, spot in ipairs({ { -0.46, 0.42 }, { 0.46, 0.42 }, { -0.47, 0 }, { 0.47, 0 }, { -0.44, -0.38 }, { 0.44, -0.38 },
			{ 0, 0.47 } }) do
			local at = mouth + axes[across] * spot[1] * extents[across] + axes[up] * spot[2] * extents[up]
			local aim = (inward + axes[across] * spot[1] * 1.1 + Vector3.new(0, -0.12, 0)).Unit
			local host = loose("CrackJet", Vector3.new(0.2, 0.2, 0.2), CFrame.lookAt(at, at + aim), SEA_IN, 1)
			local water = emitter(host, SMOKE, Color3.fromRGB(206, 236, 236), { 0.5, 1.6 }, { 26, 34 }, { 0.35, 0.6 },
				Enum.NormalId.Front, 5, -40)
			water.Orientation = Enum.ParticleOrientation.VelocityParallel
			water.Squash = NumberSequence.new(1.5)
			local stream = emitter(host, SPRAY, Color3.fromRGB(226, 244, 240), { 0.2, 0.45 }, { 8, 12 }, { 0.8, 1.4 },
				Enum.NormalId.Front, 10, 6)
			host.Parent = model
			table.insert(made, host)
			table.insert(jets, { at = at, water = water, bubbles = stream })
		end
		-- THE SEA OVER THE SILL, sheeting down the wall under the window to the floor.
		local sill = Vector3.new(mouth.X, holeBottom + 0.1, mouth.Z) + inward * 0.3
		local curtainHost = loose("SillCurtain", Vector3.new(width, 0.2, 0.3), CFrame.lookAt(sill, sill + inward), SEA_IN, 1)
		local curtain = emitter(curtainHost, SMOKE, Color3.fromRGB(200, 232, 232), { 0.8, 1.8 }, { 3, 7 }, { 0.4, 0.8 },
			Enum.NormalId.Bottom, 6, -30)
		curtain.Orientation = Enum.ParticleOrientation.VelocityParallel
		curtain.Squash = NumberSequence.new(1.4)
		curtainHost.Parent = model
		table.insert(made, curtainHost)
		-- THE SURGE: a foaming front racing across the floor from the window to the far wall.
		local surgeFrom = Vector3.new(mouth.X, floor + 0.3, mouth.Z) + inward * 1.5
		local surgeTo = surgeFrom + inward * math.max(4, (room.volume.Position - pane.Position):Dot(inward) * 2 - 4)
		local surge = loose("Surge", Vector3.new(width + 8, 0.4, 1.5), CFrame.lookAt(surgeFrom, surgeFrom + inward), SEA_IN, 1)
		local surf = emitter(surge, SMOKE, Color3.fromRGB(238, 248, 246), { 1.4, 3.6 }, { 3, 7 }, { 0.5, 0.9 },
			Enum.NormalId.Top, 50, -14)
		surf.Rate = 160
		surge.Parent = model
		table.insert(made, surge)
		-- THE NOTICE asking you not to tap the glass, torn off its wall and floated away.
		local torn: { part: BasePart, rest: CFrame }? = nil
		for _, notice in ipairs(notices) do
			if notice.Parent and (notice.Position - pane.Position).Magnitude < 12 then
				torn = { part = notice, rest = notice.CFrame }
				notice.Anchored = false
				notice.CanCollide = true
				notice.AssemblyLinearVelocity = inward * 7 + Vector3.new(0, 5, 0)
				notice.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-3, 3), rng:NextNumber(-3, 3))
				break
			end
		end
		-- AND THE ATTENDANT RUNS (Townsfolk.panic), swimming by where the water is.
		flood.level = floor
		if Townsfolk and Townsfolk.panic then
			Townsfolk.panic(function(): number
				return flood.level
			end, TAP.hold + TAP.drain)
		end

		-- Bubbles coming up through the water in each space that is not the tower.
		local bubbling: { { host: Part, space: { volume: BasePart, axis: number, bottom: number, top: number, cylinder: boolean },
			bubbles: ParticleEmitter } } = {}
		for _, space in ipairs(spaces) do
			if not space.cylinder then
				local host = loose("Bubbling", Vector3.new(1, 1, 1), space.volume.CFrame, SEA_IN, 1)
				local bubbles = emitter(host, SPRAY, Color3.fromRGB(220, 244, 240), { 0.18, 0.4 }, { 2, 4 }, { 1, 3 },
					Enum.NormalId.Top, 12, 1)
				host.Parent = model
				table.insert(made, host)
				table.insert(bubbling, { host = host, space = space, bubbles = bubbles })
			end
		end
		local gurgle = sound(bubbling[1] and bubbling[1].host or torrent, "Gurgle", WATER_SOUND, 0.3, 0.5, 60, true)
		gurgle:Play()

		-- The aquarium's leaflets, lifted off the floor and floating up on the water, drifting.
		local roomAxes = { room.volume.CFrame.RightVector, room.volume.CFrame.UpVector, -room.volume.CFrame.LookVector }
		local roomSizes = { room.volume.Size.X, room.volume.Size.Y, room.volume.Size.Z }
		local ri, rk = room.axis % 3 + 1, (room.axis + 1) % 3 + 1
		local leaflets: { { part: Part, at: Vector3, drift: Vector3, spin: number, phase: number } } = {}
		for index = 1, 7 do
			local at = room.volume.Position + roomAxes[ri] * rng:NextNumber(-0.4, 0.4) * roomSizes[ri]
				+ roomAxes[rk] * rng:NextNumber(-0.4, 0.4) * roomSizes[rk]
			local tone = ({ Color3.fromRGB(238, 232, 214), Color3.fromRGB(150, 196, 214), Color3.fromRGB(232, 168, 146) })[index % 3 + 1]
			local leaflet = loose("Leaflet", Vector3.new(1.1, 0.05, 1.5), CFrame.new(at.X, floor + 0.1, at.Z), tone, 0)
			leaflet.Parent = model
			table.insert(made, leaflet)
			table.insert(leaflets, { part = leaflet, at = Vector3.new(at.X, 0, at.Z),
				drift = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * 0.25, spin = rng:NextNumber(-0.4, 0.4),
				phase = rng:NextNumber(0, 6) })
		end

		local began = os.clock()
		local full = math.min(top, floor + rate * TAP.hold)
		local written = -math.huge
		while model.Parent do
			local now = os.clock() - began
			local rising = now < TAP.hold
			local level = if rising then math.min(top, floor + rate * now)
				else full - (full - floor) * math.min(1, (now - TAP.hold) / TAP.drain)
			-- Terrain rewritten only while the level moves: once it is up, it is left alone.
			if math.abs(level - written) > 0.02 then
				waterTo(level)
				written = level
			end

			-- How much of the hole the sea still falls through, and how far it falls.
			local above = if rising then math.clamp((holeTop - level) / math.max(0.5, holeTop - holeBottom), 0, 1) else 0
			local drop = math.max(0.5, (holeTop + holeBottom) / 2 - level)
			local fallTime = math.sqrt(2 * drop / 45)
			falls.Rate = 220 * above
			falls.Lifetime = NumberRange.new(math.max(0.15, fallTime * 0.9), math.max(0.2, fallTime * 1.1))
			mist.Rate = 90 * above
			inrush.Rate = if rising and level > holeBottom then 70 * (1 - above) else 0
			roar.Volume = 1.1 * above
			local reach = math.clamp(11 * fallTime, 1.5, 8)
			landing.CFrame = CFrame.lookAt(Vector3.new(mouth.X, level + 0.2, mouth.Z) + inward * reach,
				Vector3.new(mouth.X, level + 0.2, mouth.Z) + inward * (reach + 1))
			foam.Rate = 90 * above
			churn.Rate = 40 * above + (if rising then 6 else 0)
			flood.level = level
			for _, jet in ipairs(jets) do
				local under = level > jet.at.Y
				jet.water.Rate = if rising and not under then 45 else 0
				jet.bubbles.Rate = if rising and under then 20 else 0
			end
			curtain.Rate = if rising and level < holeBottom then 120 else 0
			if surge.Parent then
				local share = math.min(1, now / 1.8)
				local front = surgeFrom:Lerp(surgeTo, share * (2 - share))
				surge.CFrame = CFrame.lookAt(Vector3.new(front.X, level + 0.3, front.Z), Vector3.new(front.X, level + 0.3, front.Z) + inward)
				surf.Rate = if share < 1 then 160 else 0
				if now > 2.8 then
					surge:Destroy()
				end
			end

			for _, b in ipairs(bubbling) do
				local depth = math.clamp(level - b.space.bottom, 0, b.space.top - b.space.bottom)
				local v = b.space.volume
				if depth > 0.5 then
					local sizes = { v.Size.X, v.Size.Y, v.Size.Z }
					local i, k = b.space.axis % 3 + 1, (b.space.axis + 1) % 3 + 1
					b.host.Size = Vector3.new(sizes[i] - 2, depth, sizes[k] - 2)
					b.host.CFrame = CFrame.fromMatrix(Vector3.new(v.Position.X, b.space.bottom + depth / 2, v.Position.Z),
						Vector3.new(({ v.CFrame.RightVector, v.CFrame.UpVector, -v.CFrame.LookVector })[i].X, 0,
							({ v.CFrame.RightVector, v.CFrame.UpVector, -v.CFrame.LookVector })[i].Z).Unit, Vector3.yAxis)
					b.bubbles.Lifetime = NumberRange.new(math.min(1, depth / 4), math.max(0.5, depth / 3))
					b.bubbles.Rate = if rising then 0.05 * (sizes[i] * sizes[k]) else 0.01 * (sizes[i] * sizes[k])
				else
					b.bubbles.Rate = 0
				end
			end
			gurgle.Volume = if level > floor + 1 then 0.5 else 0

			local surface = math.min(level, room.top - 0.3)
			for _, leaf in ipairs(leaflets) do
				local afloat = surface > floor + 0.15
				local y = if afloat then surface - 0.03 + math.sin(now * 1.3 + leaf.phase) * 0.06 else floor + 0.1
				local at = leaf.at + (if afloat then leaf.drift * math.min(now, TAP.hold) else Vector3.zero)
				leaf.part.CFrame = CFrame.new(at.X, y, at.Z) * CFrame.Angles(math.sin(now + leaf.phase) * 0.08,
					leaf.phase + leaf.spin * now, math.cos(now * 0.8 + leaf.phase) * 0.08)
			end

			if now >= TAP.hold + TAP.drain then
				break
			end
			task.wait(FLOOD_STEP)
		end
		-- All of it gone: the water, to the last voxel, and everything that went with it.
		for _, space in ipairs(spaces) do
			terrain:FillBlock(space.volume.CFrame, space.volume.Size + Vector3.new(4, 4, 4), Enum.Material.Air)
		end
		for _, thing in ipairs(made) do
			thing:Destroy()
		end
		flood.level = -math.huge
		-- The notice back on its wall.
		if torn and torn.part.Parent then
			torn.part.Anchored = true
			torn.part.CanCollide = false
			torn.part.CFrame = torn.rest
		end
	end

	local strain: { [BasePart]: { value: number, at: number } } = {}
	local cracked: { [BasePart]: number } = {}
	local taps: { [Player]: { number } } = {}
	local answered: { [Player]: boolean } = {}
	local prompts: { ProximityPrompt } = {}
	local flooding = false

	-- NOTHING STAYS BROKEN: a pane's cracks go when it mends.
	local function mend(pane: BasePart)
		for _, child in ipairs(pane:GetChildren()) do
			if child.Name == "Crack" then
				child:Destroy()
			end
		end
		strain[pane] = nil
		cracked[pane] = nil
	end

	local function breakPane(pane: BasePart)
		flooding = true
		for _, prompt in ipairs(prompts) do
			prompt.Enabled = false
		end
		local was = pane.Transparency
		-- IT GIVES FIRST: the crack runs right across it and it groans, and then it goes.
		crackLines(pane, 2, rng, insideOf(pane))
		local groan = sound(pane, "Groan", CRACK_SOUND, 0.55, 1.3, 60, false)
		groan:Play()
		Debris:AddItem(groan, 4)
		task.wait(0.45)
		mend(pane)
		-- The pane goes. It still stops anyone walking out through the hole into a hundred studs of
		-- water, which the flood is about to settle anyway.
		pane.Transparency = 1
		for _, spec in ipairs({ { CRACK_SOUND, 1.25, 1.4 }, { THUD_SOUND, 0.4, 1.6 }, { WATER_SOUND, 0.55, 1.4 } }) do
			local s = sound(pane, "Burst", spec[1], spec[2], spec[3], 140, false)
			s:Play()
			Debris:AddItem(s, 6)
		end
		-- Inward: the pane's face, turned toward the inside, level.
		local axes, _, thin = paneAxes(pane)
		local face = axes[thin]
		if face:Dot(insideOf(pane) - pane.Position) < 0 then
			face = -face
		end
		local inward = Vector3.new(face.X, 0, face.Z)
		inward = if inward.Magnitude > 0.01 then inward.Unit else Vector3.xAxis
		shatter(pane, inward, was)
		model:SetAttribute("FloodAt", pane.Position)
		model:SetAttribute("Flood", workspace:GetServerTimeNow())
		task.spawn(function()
			local ok, err = pcall(runFlood, pane, inward)
			if not ok then
				warn("SunkenCityService: the flood failed part-way, and the glass is mended anyway: " .. tostring(err))
				for _, space in ipairs(spaces) do
					pcall(function()
						terrain:FillBlock(space.volume.CFrame, space.volume.Size + Vector3.new(4, 4, 4), Enum.Material.Air)
					end)
				end
			end
			model:SetAttribute("Flood", 0)
			if pane.Parent then
				pane.Transparency = was
			end
			for _, bit in ipairs(flood.bits) do
				bit:Destroy()
			end
			flood.bits = {}
			for _, each in ipairs(panes) do
				mend(each)
			end
			flooding = false
			if Townsfolk then
				task.delay(FLOOD_SETTLE, function()
					Townsfolk.react("mended")
				end)
			end
			for _, prompt in ipairs(prompts) do
				prompt.Enabled = true
			end
		end)
	end

	local function tapped(player: Player, pane: BasePart)
		if flooding then
			return
		end
		local knock = sound(pane, "Tap", THUD_SOUND, 1.4, 0.5, 30, false)
		knock:Play()
		Debris:AddItem(knock, 2)
		-- The attendant has something to say about it (Townsfolk).
		local heard = "tap"
		-- WHAT EVERY TAP DOES, in both modes: the fish bolt. The client watches this.
		model:SetAttribute("Tapped", workspace:GetServerTimeNow())

		-- THE STRAIN on this pane, draining away between taps.
		local now = os.clock()
		local held = strain[pane]
		local value = if held then math.max(0, held.value - (now - held.at) / TAP.ease) else 0
		value += 1
		strain[pane] = { value = value, at = now }
		local stage = cracked[pane] or 0
		if value >= TAP.breaks then
			if Townsfolk then
				Townsfolk.react("burst")
			end
			breakPane(pane)
			return
		elseif value >= TAP.crack2 and stage < 2 then
			heard = "crack2"
			cracked[pane] = 2
			crackLines(pane, 2, rng, insideOf(pane))
			local creak = sound(pane, "Creak", CRACK_SOUND, 0.7, 1, 50, false)
			creak:Play()
			Debris:AddItem(creak, 4)
		elseif value >= TAP.crack and stage < 1 then
			heard = "crack"
			cracked[pane] = 1
			crackLines(pane, 1, rng, insideOf(pane))
			local creak = sound(pane, "Creak", CRACK_SOUND, 1.1, 0.8, 40, false)
			creak:Play()
			Debris:AddItem(creak, 3)
		end

		if Townsfolk then
			Townsfolk.react(heard)
		end

		-- THE OLD ANSWER, Hardcore only, once a run.
		local list = taps[player] or {}
		table.insert(list, now)
		while #list > 0 and now - list[1] > 5 do
			table.remove(list, 1)
		end
		taps[player] = list
		if #list >= 3 and not answered[player] and isHardcore(player) then
			answered[player] = true
			task.delay(1.8, function()
				if not pane.Parent then
					return
				end
				local thud = sound(pane, "Answer", THUD_SOUND, 0.45, 1.4, 60, false)
				thud:Play()
				Debris:AddItem(thud, 4)
				model:SetAttribute("Answered", workspace:GetServerTimeNow())
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
	end

	-- A PROMPT on the window, pressed not held: tapping glass is not a decision. And a click, for
	-- anyone who just clicks it.
	for _, pane in ipairs(panes) do
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Tap"
		prompt.ObjectText = "The glass"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = pane
		table.insert(prompts, prompt)
		table.insert(connections, prompt.Triggered:Connect(function(player)
			tapped(player, pane)
		end))
		local detector = Instance.new("ClickDetector")
		detector.MaxActivationDistance = 12
		detector.Parent = pane
		table.insert(connections, detector.MouseClick:Connect(function(player)
			tapped(player, pane)
		end))
	end

	-- THE CRACKS MEND, a while after anyone stopped tapping.
	local nextMend = 0
	table.insert(connections, RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now < nextMend then
			return
		end
		nextMend = now + 0.3
		-- A crack nobody has touched for CRACK_MENDS seconds after its strain drained away mends.
		if not flooding then
			for pane, held in pairs(strain) do
				if cracked[pane] and now - held.at > TAP.ease * held.value + CRACK_MENDS then
					mend(pane)
				end
			end
		end
	end))
	return connections
end

-- ===== IS THE CLIENT RUNNING? (in Studio only) =====
--
-- Everything that moves in this level is drawn by SunkenCityClient, and for several passes it did not
-- run on the tester's client with nothing on screen to say so: no animals, no flood, a stiff ride. So
-- in Studio the server checks once, and says in Output exactly what is wrong: the module missing or in
-- the wrong place, a LocalScript where a ModuleScript should be, a module that never finishes loading,
-- or one that fails to load -- required here the way Bootstrap requires it, so its own error is
-- printed. And anyone whose client never says hello gets a notice on their screen.
function studio.check()
	local starter = game:GetService("StarterPlayer")
	local scripts = starter:FindFirstChild("StarterPlayerScripts")
	local services = scripts and scripts:FindFirstChild("Services")
	local found = services and services:FindFirstChild("SunkenCityClient")
	if not found then
		local elsewhere: Instance? = nil
		pcall(function()
			elsewhere = starter:FindFirstChild("SunkenCityClient", true) or ReplicatedStorage:FindFirstChild("SunkenCityClient", true)
				or game:GetService("ServerScriptService"):FindFirstChild("SunkenCityClient", true)
		end)
		warn(("SunkenCityService: there is no StarterPlayer.StarterPlayerScripts.Services.SunkenCityClient%s, so "
			.. "nothing of this level moves on anyone's screen. Paste src/Client/Services/SunkenCityClient.lua in "
			.. "there as a ModuleScript named exactly SunkenCityClient."):format(
			if elsewhere then " (there is one at " .. (elsewhere :: Instance):GetFullName() .. ")" else ""))
		return
	end
	if not found:IsA("ModuleScript") then
		warn(("SunkenCityService: StarterPlayerScripts.Services.SunkenCityClient is a %s. It must be a ModuleScript, "
			.. "or Bootstrap cannot start it."):format(found.ClassName))
		return
	end
	local done: boolean, ok: boolean, result: any = false, false, nil
	task.spawn(function()
		ok, result = pcall(require, found)
		done = true
	end)
	local waited = 0
	while not done and waited < 25 do
		task.wait(0.5)
		waited += 0.5
	end
	if not done then
		warn("SunkenCityService: SunkenCityClient did not finish loading in 25 seconds, so it waits forever for "
			.. "something; Output has an 'Infinite yield possible' line naming what.")
	elseif not ok then
		warn("SunkenCityService: SunkenCityClient FAILS TO LOAD, so it never runs on any client: " .. tostring(result))
	elseif type(result) ~= "table" or type(result.start) ~= "function" then
		warn("SunkenCityService: SunkenCityClient loads but has no start(), so it is not this project's file.")
	else
		studio.loads = true
		print(("SunkenCityService: SunkenCityClient loads (%s); each client says so in Output as it starts."):format(
			tostring(result.VERSION)))
	end
	local anyLocal = false
	for _, item in ipairs(if scripts then scripts:GetChildren() else {}) do
		if item:IsA("LocalScript") then
			anyLocal = true
		end
	end
	if not anyLocal then
		warn("SunkenCityService: StarterPlayerScripts has no LocalScript, so nothing starts SunkenCityClient. "
			.. "Paste src/Client/Bootstrap.client.lua in as a LocalScript named Bootstrap.")
	end
end

-- The notice: on the screen of someone whose client never said hello, for half a minute.
function studio.notice(player: Player)
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui or gui:FindFirstChild("SunkenClientNotice") then
		return
	end
	local card = Instance.new("ScreenGui")
	card.Name = "SunkenClientNotice"
	card.ResetOnSpawn = false
	card.DisplayOrder = 70
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 70)
	-- Most of the screen's width and never more than 640: it was cut off at both sides of a narrow one.
	label.Size = UDim2.new(0.9, 0, 0, 0)
	local widest = Instance.new("UISizeConstraint")
	widest.MaxSize = Vector2.new(640, math.huge)
	widest.Parent = label
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundColor3 = Color3.fromRGB(70, 22, 26)
	label.BackgroundTransparency = 0.1
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromRGB(255, 236, 230)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 16
	label.TextWrapped = true
	-- The module loads, so what never ran is the thing that starts it: an older client Bootstrap, which
	-- is what this was in play (its "Bootstrap ready" came from line 255, and the lines that start
	-- SunkenCityClient are the seventeen it was missing).
	label.Text = "STUDIO ONLY: SunkenCityClient is not running for you, so this level's animals, the ride's camera and "
		.. "the underwater sound are missing. Open Output and search for SunkenCity: the server has written what is wrong."
	if studio.loads then
		label.Text = "STUDIO ONLY: SunkenCityClient loads but nothing starts it: your client Bootstrap (the LocalScript in "
			.. "StarterPlayerScripts) is an older copy. Paste src/Client/Bootstrap.client.lua over it. Until then this "
			.. "level has no animals, no ride camera and no underwater sound."
	end
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = label
	label.Parent = card
	card.Parent = gui
	Debris:AddItem(card, 30)
end

if RunService:IsStudio() then
	task.defer(studio.check)
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
	-- THE OUTFALL, where the level was built with one (finale): the path, what the reveal looks at, and
	-- the time card that gets the rider's name.
	local outfall: any = nil
	local oFrom, oMouth, oTo, oWater = model:GetAttribute("OutfallFrom"), model:GetAttribute("OutfallMouth"),
		model:GetAttribute("OutfallTo"), model:GetAttribute("OutfallWater")
	local rEye, rCard, rCardEye = model:GetAttribute("RevealEye"), model:GetAttribute("RevealCard"), model:GetAttribute("RevealCardEye")
	if typeof(oFrom) == "Vector3" and typeof(oMouth) == "Vector3" and typeof(oTo) == "Vector3" and typeof(oWater) == "number"
		and typeof(rEye) == "Vector3" and typeof(rCard) == "Vector3" and typeof(rCardEye) == "Vector3" then
		outfall = {
			path = { from = oFrom, mouth = oMouth, to = oTo, waterY = oWater },
			reveal = { eye = rEye, card = rCard, cardEye = rCardEye },
			card = model:FindFirstChild("TimeCard", true),
		}
	end
	local sea = model:FindFirstChild("Sea")
	local path = if sea and SunkenPath then SunkenPath.read(sea) else nil
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
						task.spawn(ride, player, root, humanoid, vortex, shaftBottom :: number, onArrive, outfall)
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
	for _, connection in ipairs(glass(model, onTaken)) do
		table.insert(connections, connection)
	end
	-- In Studio, a notice for anyone here whose SunkenCityClient has not said it is running.
	if RunService:IsStudio() then
		task.delay(25, function()
			if model.Parent then
				for _, player in ipairs(Players:GetPlayers()) do
					if not studio.heard[player] then
						studio.notice(player)
						if studio.loads then
							warn(("SunkenCityService: SunkenCityClient loads, but %s's client never started it: the client "
								.. "Bootstrap in StarterPlayerScripts is an older copy without the lines that start it. Paste "
								.. "src/Client/Bootstrap.client.lua over it."):format(player.Name))
						end
					end
				end
			end
		end)
	end
	return function()
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		table.clear(arrivedAt)
		SunkenCityService.clearWater()
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	studio.heard[player] = nil
	riding[player] = nil
	arrivedAt[player] = nil
end)

return SunkenCityService
