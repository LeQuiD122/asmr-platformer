--!strict
-- ServerScriptService/Services/HillHouseService.lua
-- HILL HOUSE (the hundred-and-eleventh pass; you chose it, LORE.md level 5): your father's house on the hill over
-- Harrow Bay, at eight in the morning on 14 August, before any of it.
--
-- The route climbs out of the morning mist on the usual spiral. Where it ends, a stone landing and a footbridge cross
-- to the top of a crag, a hill of real ground standing out of the mist beside the spiral, and on it his garden and
-- his house: a picket fence round the edge, a stone path through lamb's ear to the front door, an apple tree, a bench
-- looking out to sea, the milk on the step. "Go in" opens his front door; inside is the hall (the hundred-and-twelfth
-- pass): his clock, his coat, and the key on its green ribbon, and "Take the key" is the end of the level.
--
-- EVERYTHING STANDS ON SOMETHING. The crag is terrain from the mist up (cleared again when the level goes, the way
-- Sky Pools clears its water); the landing is held by the last chunk at one side and the footbridge at the other; the
-- footbridge rests on the landing and is braced off the crag; the house, the fence and the tree stand on the top. Out in the mist, the far things
-- rise out of it on their own ground: St Brigid's on its hill, and the Deco tower over the town.
--
-- CLEAR OF THE ROUTE. The spiral circles its centre at one radius all the way up, so the crag is put out beyond it,
-- its nearest edge CLEAR studs outside the route's circle at every height: no chunk below can be inside the hill.
-- blender/check_hillhouse.py holds the numbers.
--
-- WHO IS UP HERE AT EIGHT (the hundred-and-thirteenth pass): Mr Gale the milkman at the top of the climb, and Mrs Dunn
-- the postwoman inside the gate (Townsfolk has what they say; Shared/Conversations what you can ask them).

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- One look for the whole game: the house's name on its gatepost in the world's print.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))
-- The people (Townsfolk), looked for with a timeout as every level's are: without it the hill is empty and still plays.
local townsModule = script.Parent:FindFirstChild("Townsfolk") or script.Parent:WaitForChild("Townsfolk", 5)
local Townsfolk: any = if townsModule and townsModule:IsA("ModuleScript") then require(townsModule) else nil

local HillHouseService = {}
HillHouseService.VERSION = "the hundred-and-thirteenth pass, 2026-10-21"

-- THE CRAG: its top's radius, how far its nearest edge stays outside the route's circle, how far ahead of the route's
-- end it stands, and how far below the top it goes (into the mist and past the kill plane).
local CRAG_R = 44
local CLEAR = 26
local AHEAD = 16
local CRAG_DEEP = 40 -- studs past the kill plane, so its foot is never seen
-- THE LANDING at the route's end, and the footbridge from it to the top.
local LANDING = Vector3.new(14, 1.2, 10)
local BRIDGE_WIDE = 6
local RISE = 1 -- the top of the crag is this much above the route's end
-- THE HOUSE: across, deep, a storey, and its roof.
local HOUSE_W, HOUSE_D, STOREY, ROOF_H = 26, 18, 11, 8
-- THE HALL (the hundred-and-twelfth pass): where his clock stopped (the hour he went down, 1979: the bay went out on
-- time), how long after the key is taken the level is finished (the scene's clock shot is on by then), and the key's
-- hook from the door's middle (across) and up from the floor.
local CLOCK_STOPPED_HOUR, CLOCK_STOPPED_MINUTE = 11, 56
local KEY_ARRIVE = 6.5
local KEY_HOOK = Vector3.new(3.6, 5.8, 0)
-- Where you stand to take it: in front of the hook, this far into the hall.
local KEY_STAND = 2.4
-- THE MIST: its top this far above the kill plane, so a fall goes into it and ends inside it.
local MIST_OVER_KILL = 6

local PALETTE = {
	render = Color3.fromRGB(236, 228, 214), -- the house's painted render
	plinth = Color3.fromRGB(150, 98, 78),
	slate = Color3.fromRGB(74, 80, 96),
	frame = Color3.fromRGB(246, 244, 238),
	glass = Color3.fromRGB(70, 84, 96),
	dark = Color3.fromRGB(24, 22, 26),
	door = Color3.fromRGB(38, 86, 64), -- his green, the ribbon's green
	brass = Color3.fromRGB(196, 158, 76),
	stone = Color3.fromRGB(184, 176, 160),
	timber = Color3.fromRGB(122, 92, 66),
	picket = Color3.fromRGB(240, 238, 230),
	leaf = Color3.fromRGB(176, 190, 170), -- lamb's ear
	tree = Color3.fromRGB(96, 70, 52),
	canopy = Color3.fromRGB(92, 140, 80),
	apple = Color3.fromRGB(196, 54, 46),
	mist = Color3.fromRGB(244, 234, 222),
	church = Color3.fromRGB(196, 190, 176),
	tower = Color3.fromRGB(232, 222, 200),
}

type Fill = { cf: CFrame, size: Vector3 }
local filled: { Fill } = {}
local built: Model? = nil
local prompt: ProximityPrompt? = nil
local takePrompt: ProximityPrompt? = nil
local arrived: { [Player]: boolean } = {}

-- ===== TERRAIN, put back when the level goes =====

local function fillCylinder(cf: CFrame, height: number, radius: number, material: Enum.Material)
	workspace.Terrain:FillCylinder(cf, height, radius, material)
	table.insert(filled, { cf = cf, size = Vector3.new(radius * 2 + 4, height + 4, radius * 2 + 4) })
end

local function fillBall(at: Vector3, radius: number, material: Enum.Material)
	workspace.Terrain:FillBall(at, radius, material)
	table.insert(filled, { cf = CFrame.new(at), size = Vector3.new(radius * 2 + 4, radius * 2 + 4, radius * 2 + 4) })
end

local function fillBlock(cf: CFrame, size: Vector3, material: Enum.Material)
	workspace.Terrain:FillBlock(cf, size, material)
	table.insert(filled, { cf = cf, size = size + Vector3.new(4, 4, 4) })
end

-- BARE GROUND under a rectangle of the top (its middle, the way it runs, its width across that and its length along
-- it): every terrain cell under it turned from grass to ground, a cell at a time. Filling ground over the grass (the
-- hundred-and-eighteenth pass) left the top cells grass, and the grass grew up through the hall's floor all the same
-- (your test of 2026-10-22): a fill only takes a cell from what is there when it fills more of it, and the grass and
-- the ground were filled to the same height. A cell's material changed outright has no such rule. (These cells are in
-- the crag, cleared with it.)
local function bareGround(mid: Vector3, along: Vector3, across: number, long: number)
	local side = Vector3.yAxis:Cross(along)
	local reach = math.sqrt(across * across + long * long) / 2 + 4
	local y0 = math.floor((mid.Y - 8) / 4) * 4
	for x = math.floor((mid.X - reach) / 4) * 4, mid.X + reach, 4 do
		for z = math.floor((mid.Z - reach) / 4) * 4, mid.Z + reach, 4 do
			-- Any cell reaching under the rectangle: its middle within half a cell of it.
			local off = Vector3.new(x + 2 - mid.X, 0, z + 2 - mid.Z)
			if math.abs(off:Dot(side)) <= across / 2 + 2 and math.abs(off:Dot(along)) <= long / 2 + 2 then
				workspace.Terrain:ReplaceMaterial(Region3.new(Vector3.new(x, y0, z), Vector3.new(x + 4, y0 + 16, z + 4)), 4,
					Enum.Material.Grass, Enum.Material.Ground)
			end
		end
	end
end

local function clearTerrain()
	for _, region in ipairs(filled) do
		pcall(function()
			workspace.Terrain:FillBlock(region.cf, region.size, Enum.Material.Air)
		end)
	end
	table.clear(filled)
end

-- ===== PARTS =====

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material,
	solid: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanTouch = false
	p.CanQuery = solid == true
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function wedge(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.CanCollide = false
	w.CanTouch = false
	w.CanQuery = false
	w.Size = size
	w.CFrame = cf
	w.Color = colour
	w.Material = material
	w.Parent = parent
	return w
end

local function cylinder(parent: Instance, name: string, length: number, diameter: number, cf: CFrame, colour: Color3,
	material: Enum.Material, solid: boolean?): Part
	-- A cylinder STANDING UP along `cf`'s Y: Roblox's cylinders lie along X, so it is turned a quarter about Z.
	local c = part(parent, name, Vector3.new(length, diameter, diameter), cf * CFrame.Angles(0, 0, math.pi / 2), colour,
		material, solid)
	c.Shape = Enum.PartType.Cylinder
	return c
end

local function ball(parent: Instance, name: string, diameter: number, at: Vector3, colour: Color3, material: Enum.Material): Part
	local b = part(parent, name, Vector3.new(diameter, diameter, diameter), CFrame.new(at), colour, material)
	b.Shape = Enum.PartType.Ball
	return b
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-4 then f.Unit else Vector3.zAxis
end

-- A WALL with rectangular holes in it (windows, a door), built as the strips between them. `holes` are { x0, x1, y0, y1 }
-- in the wall's own frame: x across it from -width/2, y up it from its foot. `cf` is the wall's foot, in its middle.
local function wallWithHoles(parent: Instance, name: string, cf: CFrame, width: number, height: number, thick: number,
	holes: { { number } }, colour: Color3, material: Enum.Material)
	local cuts = { -width / 2, width / 2 }
	for _, h in ipairs(holes) do
		table.insert(cuts, h[1])
		table.insert(cuts, h[2])
	end
	table.sort(cuts)
	for k = 1, #cuts - 1 do
		local x0, x1 = cuts[k], cuts[k + 1]
		if x1 - x0 > 0.01 then
			-- The holes this strip passes through, bottom to top.
			local spans = {}
			for _, h in ipairs(holes) do
				if h[1] <= x0 + 0.001 and h[2] >= x1 - 0.001 then
					table.insert(spans, { h[3], h[4] })
				end
			end
			table.sort(spans, function(a, b)
				return a[1] < b[1]
			end)
			local y = 0
			local function strip(y0: number, y1: number)
				if y1 - y0 > 0.01 then
					part(parent, name, Vector3.new(x1 - x0, y1 - y0, thick),
						cf * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, 0), colour, material, true)
				end
			end
			for _, span in ipairs(spans) do
				strip(y, span[1])
				y = span[2]
			end
			strip(y, height)
		end
	end
end

-- A window in a hole: a white frame round it, a sill under it, its glass, and (upstairs, where nothing is furnished)
-- the dark of the room behind.
local function window(parent: Instance, cf: CFrame, wide: number, high: number, dark: boolean)
	local frameT = 0.35
	part(parent, "WindowFrame", Vector3.new(wide, frameT, 0.5), cf * CFrame.new(0, high / 2 - frameT / 2, 0), PALETTE.frame,
		Enum.Material.SmoothPlastic)
	part(parent, "WindowFrame", Vector3.new(wide, frameT, 0.5), cf * CFrame.new(0, -high / 2 + frameT / 2, 0), PALETTE.frame,
		Enum.Material.SmoothPlastic)
	part(parent, "WindowFrame", Vector3.new(frameT, high, 0.5), cf * CFrame.new(-wide / 2 + frameT / 2, 0, 0), PALETTE.frame,
		Enum.Material.SmoothPlastic)
	part(parent, "WindowFrame", Vector3.new(frameT, high, 0.5), cf * CFrame.new(wide / 2 - frameT / 2, 0, 0), PALETTE.frame,
		Enum.Material.SmoothPlastic)
	-- The glazing bars: a sash window's cross.
	part(parent, "WindowBar", Vector3.new(wide, 0.18, 0.3), cf, PALETTE.frame, Enum.Material.SmoothPlastic)
	part(parent, "WindowBar", Vector3.new(0.18, high, 0.3), cf, PALETTE.frame, Enum.Material.SmoothPlastic)
	local glass = part(parent, "WindowGlass", Vector3.new(wide - frameT * 2, high - frameT * 2, 0.1), cf, PALETTE.glass,
		Enum.Material.SmoothPlastic)
	glass.Reflectance = 0.25
	glass.Transparency = 0.35
	if dark then
		part(parent, "WindowDark", Vector3.new(wide, high, 0.2), cf * CFrame.new(0, 0, 0.6), PALETTE.dark,
			Enum.Material.SmoothPlastic)
	end
	part(parent, "WindowSill", Vector3.new(wide + 0.8, 0.35, 0.9), cf * CFrame.new(0, -high / 2 - 0.15, -0.3), PALETTE.stone,
		Enum.Material.Concrete)
end

-- ===== THE HALL (the hundred-and-twelfth pass) =====
--
-- Inside his front door, one long room: the floorboards on the plinth and a rug down the middle, a dado rail round
-- the walls, the lamp lit on the hall table with a photograph by it, and a slant of morning sun through the side window
-- with the dust turning in it. His longcase clock against the wall, stopped at four minutes to midnight since 1979,
-- its pendulum still; his coat and his cap on the hooks by the door as he left them; and on its own hook on the other
-- side of the door, the key on its green ribbon. In the house's frame (`centre`, -Z the front). Returns where things
-- are, for the scene.
local function buildHall(parent: Instance, centre: CFrame): { [string]: any }
	local W, D = HOUSE_W, HOUSE_D
	local floorY = 1.2
	local inner = -D / 2 + 1 -- the front wall's inside face
	local mahogany = Color3.fromRGB(86, 44, 30)
	local brass = PALETTE.brass
	part(parent, "HallFloor", Vector3.new(W - 2, 0.1, D - 2), centre * CFrame.new(0, floorY + 0.05, 0), PALETTE.timber,
		Enum.Material.WoodPlanks, true)
	part(parent, "HallRug", Vector3.new(5, 0.06, 9), centre * CFrame.new(0, floorY + 0.13, -2.5), Color3.fromRGB(128, 44, 48),
		Enum.Material.Fabric)
	-- THE DADO RAIL, round the walls at a hand's height (a gap for the door).
	for _, run in ipairs({
		-- (Proud of the panelling, which is 0.12 thick: the two-hundred-and-twelfth pass.)
		{ Vector3.new(0.2, 0.3, D - 2), Vector3.new(-(W / 2 - 1.22), floorY + 3.2, 0) },
		{ Vector3.new(0.2, 0.3, D - 2), Vector3.new(W / 2 - 1.22, floorY + 3.2, 0) },
		{ Vector3.new(W - 2, 0.3, 0.2), Vector3.new(0, floorY + 3.2, D / 2 - 1.22) },
		{ Vector3.new(W / 2 - 3.6, 0.3, 0.2), Vector3.new(-(W / 4 + 0.8), floorY + 3.2, inner + 0.22) },
		{ Vector3.new(W / 2 - 3.6, 0.3, 0.2), Vector3.new(W / 4 + 0.8, floorY + 3.2, inner + 0.22) },
	}) do
		part(parent, "DadoRail", run[1], centre * CFrame.new(run[2]), mahogany, Enum.Material.Wood)
	end

	-- HIS CLOCK, against the right-hand wall, facing into the hall.
	local clock = centre * CFrame.new(W / 2 - 1 - 0.75, floorY, -1.5) * CFrame.Angles(0, math.pi / 2, 0)
	part(parent, "ClockBase", Vector3.new(2.4, 0.6, 1.4), clock * CFrame.new(0, 0.3, 0), mahogany, Enum.Material.Wood, true)
	part(parent, "ClockTrunk", Vector3.new(2, 4.6, 1.2), clock * CFrame.new(0, 2.9, 0), mahogany, Enum.Material.Wood, true)
	local trunkGlass = part(parent, "ClockTrunkGlass", Vector3.new(1.2, 3.4, 0.08), clock * CFrame.new(0, 2.8, -0.63),
		Color3.fromRGB(200, 214, 220), Enum.Material.SmoothPlastic)
	trunkGlass.Transparency = 0.7
	part(parent, "ClockHood", Vector3.new(2.6, 2.4, 1.4), clock * CFrame.new(0, 6.4, 0), mahogany, Enum.Material.Wood, true)
	for _, half in ipairs({ -1, 1 }) do
		wedge(parent, "ClockPediment", Vector3.new(1.4, 0.7, 1.3),
			clock * CFrame.new(half * 0.65, 7.95, 0) * CFrame.Angles(0, half * math.pi / 2, 0), mahogany, Enum.Material.Wood)
	end
	-- Its face, and its hands where they stopped.
	local face = clock * CFrame.new(0, 6.4, -0.74)
	local dial = cylinder(parent, "ClockFace", 0.08, 1.9, face * CFrame.Angles(math.pi / 2, 0, 0), Color3.fromRGB(244, 238, 222),
		Enum.Material.SmoothPlastic)
	dial.CastShadow = false
	local minuteTurn = CLOCK_STOPPED_MINUTE / 60 * math.pi * 2
	local hourTurn = (CLOCK_STOPPED_HOUR + CLOCK_STOPPED_MINUTE / 60) / 12 * math.pi * 2
	part(parent, "ClockMinuteHand", Vector3.new(0.08, 0.8, 0.04), face * CFrame.new(0, 0, -0.06) * CFrame.Angles(0, 0, minuteTurn)
		* CFrame.new(0, 0.4, 0), PALETTE.dark, Enum.Material.Metal)
	part(parent, "ClockHourHand", Vector3.new(0.12, 0.55, 0.04), face * CFrame.new(0, 0, -0.07) * CFrame.Angles(0, 0, hourTurn)
		* CFrame.new(0, 0.275, 0), PALETTE.dark, Enum.Material.Metal)
	-- The pendulum, still behind the trunk's glass: a rod and a brass bob, hung from a pivot the scene swings it about.
	local pivot = clock * CFrame.new(0, 4.9, -0.3)
	part(parent, "PendulumRod", Vector3.new(0.08, 3, 0.08), pivot * CFrame.new(0, -1.5, 0), brass, Enum.Material.Metal)
	local bob = part(parent, "PendulumBob", Vector3.new(0.12, 0.8, 0.8), pivot * CFrame.new(0, -3.1, 0) * CFrame.Angles(0, math.pi / 2, 0),
		brass, Enum.Material.Metal)
	bob.Shape = Enum.PartType.Cylinder

	-- HIS COAT AND HIS CAP on the hooks to the left of the door, as he left them.
	local rail = centre * CFrame.new(-4.4, floorY + 6.6, inner + 0.15)
	part(parent, "CoatRail", Vector3.new(3.2, 0.4, 0.2), rail, mahogany, Enum.Material.Wood)
	for _, x in ipairs({ -1.1, 0, 1.1 }) do
		part(parent, "CoatHook", Vector3.new(0.18, 0.18, 0.45), rail * CFrame.new(x, -0.1, 0.3), brass, Enum.Material.Metal)
	end
	local coatColour = Color3.fromRGB(42, 48, 64)
	part(parent, "Coat", Vector3.new(1.7, 4.2, 0.55), rail * CFrame.new(-1.1, -2.4, 0.5), coatColour, Enum.Material.Fabric)
	for _, x in ipairs({ -1, 1 }) do
		part(parent, "CoatSleeve", Vector3.new(0.45, 3, 0.45), rail * CFrame.new(-1.1 + x * 0.95, -2.1, 0.55) * CFrame.Angles(0, 0, x * 0.05),
			coatColour, Enum.Material.Fabric)
	end
	cylinder(parent, "Cap", 0.35, 1.1, rail * CFrame.new(1.1, -0.45, 0.5), Color3.fromRGB(112, 98, 82), Enum.Material.Fabric)
	part(parent, "CapBrim", Vector3.new(0.9, 0.1, 0.5), rail * CFrame.new(1.1, -0.6, 0.85), Color3.fromRGB(100, 86, 72),
		Enum.Material.Fabric)

	-- THE KEY on its green ribbon, on its own hook to the right of the door.
	local hook = centre * CFrame.new(KEY_HOOK.X, floorY + KEY_HOOK.Y, inner + 0.15)
	part(parent, "KeyHook", Vector3.new(0.2, 0.2, 0.5), hook * CFrame.new(0, 0, 0.25), brass, Enum.Material.Metal)
	local key = Instance.new("Model")
	key.Name = "HallKey"
	key.Parent = parent
	local ribbon = Color3.fromRGB(58, 150, 88)
	for _, lean in ipairs({ -0.18, 0.18 }) do
		part(key, "KeyRibbon", Vector3.new(0.14, 1.4, 0.04), hook * CFrame.new(lean * 1.6, -0.75, 0.45) * CFrame.Angles(0, 0, lean),
			ribbon, Enum.Material.Fabric)
	end
	local bow = cylinder(key, "KeyBow", 0.08, 0.5, hook * CFrame.new(0, -1.65, 0.45) * CFrame.Angles(math.pi / 2, 0, 0), brass,
		Enum.Material.Metal)
	bow.CastShadow = false
	local shank = part(key, "KeyShank", Vector3.new(0.12, 0.9, 0.08), hook * CFrame.new(0, -2.3, 0.45), brass, Enum.Material.Metal)
	part(key, "KeyBit", Vector3.new(0.32, 0.25, 0.08), hook * CFrame.new(0.15, -2.62, 0.45), brass, Enum.Material.Metal)

	-- THE HALL TABLE against the left-hand wall: the lamp lit, and a photograph.
	local tableAt = centre * CFrame.new(-(W / 2 - 1 - 0.9), floorY, -3) * CFrame.Angles(0, -math.pi / 2, 0)
	part(parent, "HallTable", Vector3.new(3.2, 0.15, 1.6), tableAt * CFrame.new(0, 3, 0), mahogany, Enum.Material.Wood, true)
	for _, x in ipairs({ -1.4, 1.4 }) do
		for _, z in ipairs({ -0.65, 0.65 }) do
			part(parent, "HallTableLeg", Vector3.new(0.15, 2.9, 0.15), tableAt * CFrame.new(x, 1.45, z), mahogany, Enum.Material.Wood)
		end
	end
	cylinder(parent, "LampStem", 1.2, 0.25, tableAt * CFrame.new(-0.8, 3.7, 0), brass, Enum.Material.Metal)
	local shade = cylinder(parent, "LampShade", 0.9, 1.2, tableAt * CFrame.new(-0.8, 4.6, 0), Color3.fromRGB(240, 222, 184),
		Enum.Material.Fabric)
	local lamp = Instance.new("PointLight")
	lamp.Color = Color3.fromRGB(255, 214, 160)
	lamp.Brightness = 0.5
	lamp.Range = 16
	lamp.Shadows = false
	lamp.Parent = shade
	part(parent, "Photograph", Vector3.new(0.9, 1.1, 0.08), tableAt * CFrame.new(0.7, 3.65, 0.2) * CFrame.Angles(-0.15, 0, 0),
		mahogany, Enum.Material.Wood)
	part(parent, "PhotographPrint", Vector3.new(0.7, 0.9, 0.04), tableAt * CFrame.new(0.7, 3.65, 0.15) * CFrame.Angles(-0.15, 0, 0),
		Color3.fromRGB(176, 158, 128), Enum.Material.SmoothPlastic)

	-- THE MORNING SUN through the left-hand window, slanting down across the hall, and the dust turning in it.
	local sill = centre * CFrame.new(-(W / 2 - 1.4), 7.4, 0)
	local floorSpot = (centre * CFrame.new(-2, floorY, -2.5)).Position
	local beam = part(parent, "Sunbeam", Vector3.new(0.4, 0.4, 0.4), CFrame.lookAt(sill.Position, floorSpot), PALETTE.dark,
		Enum.Material.SmoothPlastic)
	beam.Transparency = 1
	local sun = Instance.new("SpotLight")
	sun.Color = Color3.fromRGB(255, 228, 190)
	sun.Brightness = 1.2
	sun.Range = 28
	sun.Angle = 38
	sun.Face = Enum.NormalId.Front
	sun.Shadows = true
	sun.Parent = beam
	local motes = part(parent, "SunbeamDust", Vector3.new(3, 4, 8),
		CFrame.lookAt((sill.Position + floorSpot) / 2, floorSpot), PALETTE.dark, Enum.Material.SmoothPlastic)
	motes.Transparency = 1
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "Dust"
	dust.Shape = Enum.ParticleEmitterShape.Box
	dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	dust.Rate = 5
	dust.Lifetime = NumberRange.new(6, 9)
	dust.Speed = NumberRange.new(0.02, 0.08)
	dust.SpreadAngle = Vector2.new(180, 180)
	dust.Size = NumberSequence.new(0.07)
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(0.8, 0.35), NumberSequenceKeypoint.new(1, 1) })
	dust.Color = ColorSequence.new(Color3.fromRGB(255, 240, 214))
	dust.LightEmission = 0.4
	dust.LightInfluence = 1
	dust.Drag = 1
	dust.Parent = motes

	-- ===== THE HALL, LIVED IN (the two-hundred-and-twelfth pass, from your note of 2026-11-07: Hill House's models
	-- inside and out). Its walls were the outside's render, and its back half was bare boards. Now the walls are
	-- panelled to the rail and papered above it, with a skirting at the foot and a cornice under the ceiling, the
	-- holes left for the door and the windows; a lamp hangs in the middle; and at the back, by the window, his chair
	-- with its footstool and the table with his pipe and his mug, the bookcase with his ship on top, the painting of
	-- the bay, the barometer by the clock and the umbrella stand by the door. All of it on the floor or on a wall.
	local panelColour = Color3.fromRGB(140, 100, 70)
	local paper = Color3.fromRGB(176, 190, 166)
	local inX, inZ = W / 2 - 1, D / 2 - 1
	local ceilingY = STOREY - 0.3
	local winLow, winHigh = 3.5 - floorY, 3.5 + 5 - floorY -- the ground-floor windows, from the boards
	local linings = {
		-- { the lining's foot (its middle, facing into the hall), its width, the holes in it }
		{ centre * CFrame.new(-inX + 0.06, floorY, 0) * CFrame.Angles(0, math.pi / 2, 0), D - 2, { { -2, 2 } } },
		{ centre * CFrame.new(inX - 0.06, floorY, 0) * CFrame.Angles(0, -math.pi / 2, 0), D - 2, { { -2, 2 } } },
		-- (Turned to face the hall, so its window, at 2 to 6 across the house, is at -6 to -2 across it.)
		{ centre * CFrame.new(0, floorY, inZ - 0.06) * CFrame.Angles(0, math.pi, 0), W - 2, { { -6, -2 } } },
		{ centre * CFrame.new(0, floorY, -inZ + 0.06), W - 2, { { -9.5, -5.5 }, { 5.5, 9.5 } }, true },
	}
	local panelTop = 3.2
	for _, lining in ipairs(linings) do
		local foot, wide, windows, isFront = lining[1], lining[2], lining[3], lining[4]
		local low, high, skirt = {}, {}, {}
		for _, w in ipairs(windows) do
			table.insert(low, { w[1], w[2], winLow, winHigh })
			table.insert(high, { w[1], w[2], winLow - panelTop, winHigh - panelTop })
		end
		if isFront then
			-- The door's hole, the door 8 high from the boards.
			table.insert(low, { -2.1, 2.1, -1, 8 })
			table.insert(high, { -2.1, 2.1, -1, 8 - panelTop })
			table.insert(skirt, { -2.1, 2.1, -1, 8 })
		end
		wallWithHoles(parent, "Panelling", foot, wide, panelTop, 0.12, low, panelColour, Enum.Material.Wood)
		wallWithHoles(parent, "Wallpaper", foot * CFrame.new(0, panelTop, 0), wide, ceilingY - floorY - panelTop, 0.12, high, paper,
			Enum.Material.Fabric)
		wallWithHoles(parent, "Skirting", foot * CFrame.new(0, 0, 0.04), wide, 0.5, 0.2, skirt, mahogany, Enum.Material.Wood)
		part(parent, "Cornice", Vector3.new(wide, 0.5, 0.35), foot * CFrame.new(0, ceilingY - floorY - 0.25, 0.1), PALETTE.render,
			Enum.Material.SmoothPlastic)
	end
	-- A painted ceiling under the upstairs boards (whose underside was their swirling timber).
	part(parent, "HallCeiling", Vector3.new(W - 2, 0.1, D - 2), centre * CFrame.new(0, ceilingY - 0.05, 0), PALETTE.render,
		Enum.Material.SmoothPlastic)
	-- The lamp hanging in the middle on its chain.
	cylinder(parent, "PendantChain", 1.5, 0.08, centre * CFrame.new(0, ceilingY - 0.75, 0.5), brass, Enum.Material.Metal)
	local pendant = cylinder(parent, "PendantShade", 0.7, 1.6, centre * CFrame.new(0, ceilingY - 1.85, 0.5),
		Color3.fromRGB(240, 222, 184), Enum.Material.Fabric)
	local hanging = Instance.new("PointLight")
	hanging.Color = Color3.fromRGB(255, 214, 160)
	hanging.Brightness = 0.6
	hanging.Range = 18
	hanging.Shadows = false
	hanging.Parent = pendant

	-- HIS CHAIR by the back window, facing into the hall (its -Z), with its footstool.
	local plush = Color3.fromRGB(176, 138, 64)
	local chair = centre * CFrame.new(4, floorY, 5.6)
	for _, x in ipairs({ -1.1, 1.1 }) do
		for _, z in ipairs({ -0.9, 0.9 }) do
			part(parent, "ChairLeg", Vector3.new(0.3, 0.5, 0.3), chair * CFrame.new(x, 0.25, z), mahogany, Enum.Material.Wood)
		end
	end
	part(parent, "ChairSeat", Vector3.new(2.8, 0.8, 2.4), chair * CFrame.new(0, 0.9, 0), plush, Enum.Material.Fabric, true)
	part(parent, "ChairCushion", Vector3.new(2.1, 0.35, 1.9), chair * CFrame.new(0, 1.47, -0.15), plush, Enum.Material.Fabric)
	part(parent, "ChairBack", Vector3.new(2.8, 2.6, 0.6), chair * CFrame.new(0, 2.6, 0.9), plush, Enum.Material.Fabric, true)
	for _, x in ipairs({ -1.15, 1.15 }) do
		part(parent, "ChairArm", Vector3.new(0.5, 0.9, 2.4), chair * CFrame.new(x, 1.75, 0), plush, Enum.Material.Fabric)
	end
	part(parent, "Footstool", Vector3.new(1.6, 0.8, 1.2), centre * CFrame.new(4, floorY + 0.4, 3.2), plush, Enum.Material.Fabric)
	-- The table at his elbow: his pipe and his mug.
	local side = centre * CFrame.new(6.9, floorY, 5.6)
	cylinder(parent, "SideTableLeg", 2.1, 0.25, side * CFrame.new(0, 1.05, 0), mahogany, Enum.Material.Wood)
	cylinder(parent, "SideTableFoot", 0.15, 1, side * CFrame.new(0, 0.075, 0), mahogany, Enum.Material.Wood)
	cylinder(parent, "SideTableTop", 0.15, 1.5, side * CFrame.new(0, 2.17, 0), mahogany, Enum.Material.Wood, true)
	cylinder(parent, "Mug", 0.5, 0.42, side * CFrame.new(0.3, 2.5, 0.2), Color3.fromRGB(230, 226, 214), Enum.Material.SmoothPlastic)
	part(parent, "PipeStem", Vector3.new(0.6, 0.08, 0.08), side * CFrame.new(-0.25, 2.29, -0.25) * CFrame.Angles(0, 0.5, 0),
		PALETTE.dark, Enum.Material.SmoothPlastic)
	cylinder(parent, "PipeBowl", 0.3, 0.24, side * CFrame.new(-0.55, 2.39, -0.1), Color3.fromRGB(96, 56, 36), Enum.Material.Wood)

	-- THE BOOKCASE against the back wall, left of the window, his books on its shelves and his ship on top.
	local case = centre * CFrame.new(-8, floorY, inZ - 0.72)
	part(parent, "BookcaseBack", Vector3.new(4, 7, 0.2), case * CFrame.new(0, 3.5, 0.5), mahogany, Enum.Material.Wood, true)
	for _, x in ipairs({ -1.875, 1.875 }) do
		part(parent, "BookcaseSide", Vector3.new(0.25, 7, 1.2), case * CFrame.new(x, 3.5, 0), mahogany, Enum.Material.Wood, true)
	end
	part(parent, "BookcaseTop", Vector3.new(4.2, 0.2, 1.3), case * CFrame.new(0, 7.1, 0), mahogany, Enum.Material.Wood, true)
	local spines = { Color3.fromRGB(128, 44, 48), Color3.fromRGB(38, 86, 64), Color3.fromRGB(46, 58, 96),
		Color3.fromRGB(176, 138, 64), Color3.fromRGB(96, 70, 52), Color3.fromRGB(206, 196, 176) }
	local books = Random.new(1979)
	for shelf = 0, 4 do
		local y = 0.1 + shelf * 1.5
		part(parent, "BookcaseShelf", Vector3.new(3.5, 0.15, 1.1), case * CFrame.new(0, y, 0), mahogany, Enum.Material.Wood, true)
		if shelf < 4 then
			local x = -1.65
			while x < 1.4 do
				local thick = books:NextNumber(0.18, 0.32)
				local tall = books:NextNumber(0.85, 1.2)
				part(parent, "Book", Vector3.new(thick, tall, 0.8), case * CFrame.new(x + thick / 2, y + 0.075 + tall / 2, 0.05),
					spines[books:NextInteger(1, #spines)], Enum.Material.Fabric)
				x += thick + 0.02
			end
		end
	end
	-- His ship, on its stand on top.
	local ship = case * CFrame.new(0, 7.2, 0)
	part(parent, "ShipStand", Vector3.new(0.9, 0.2, 0.3), ship * CFrame.new(0, 0.1, 0), mahogany, Enum.Material.Wood)
	part(parent, "ShipHull", Vector3.new(2, 0.5, 0.5), ship * CFrame.new(0, 0.45, 0), Color3.fromRGB(46, 58, 96), Enum.Material.Wood)
	part(parent, "ShipDeck", Vector3.new(1.9, 0.08, 0.42), ship * CFrame.new(0, 0.72, 0), PALETTE.timber, Enum.Material.Wood)
	for _, x in ipairs({ -0.45, 0.45 }) do
		cylinder(parent, "ShipMast", 1.5, 0.07, ship * CFrame.new(x, 1.5, 0), PALETTE.timber, Enum.Material.Wood)
		part(parent, "ShipSail", Vector3.new(0.6, 0.8, 0.03), ship * CFrame.new(x, 1.55, 0), Color3.fromRGB(244, 238, 222),
			Enum.Material.Fabric)
	end

	-- THE PAINTING of the bay on the left-hand wall, behind the table: sky, sea, and a boat going out.
	local picture = centre * CFrame.new(-inX + 0.2, floorY + 6.2, 5) * CFrame.Angles(0, -math.pi / 2, 0)
	part(parent, "PaintingFrame", Vector3.new(3.2, 2.4, 0.16), picture, brass, Enum.Material.Wood)
	part(parent, "PaintingSky", Vector3.new(2.8, 1.1, 0.04), picture * CFrame.new(0, 0.45, -0.09), Color3.fromRGB(206, 214, 222),
		Enum.Material.SmoothPlastic)
	part(parent, "PaintingSea", Vector3.new(2.8, 0.9, 0.04), picture * CFrame.new(0, -0.55, -0.09), Color3.fromRGB(64, 96, 120),
		Enum.Material.SmoothPlastic)
	part(parent, "PaintingBoat", Vector3.new(0.5, 0.14, 0.03), picture * CFrame.new(0.6, -0.1, -0.12), PALETTE.dark,
		Enum.Material.SmoothPlastic)
	part(parent, "PaintingSail", Vector3.new(0.05, 0.4, 0.03), picture * CFrame.new(0.6, 0.15, -0.12), Color3.fromRGB(244, 238, 222),
		Enum.Material.SmoothPlastic)

	-- THE BAROMETER on the right-hand wall, past the clock, its needle on Change.
	local glass = centre * CFrame.new(inX - 0.2, floorY + 5.5, 3.2) * CFrame.Angles(0, math.pi / 2, 0)
	part(parent, "BarometerCase", Vector3.new(0.7, 2.6, 0.16), glass, mahogany, Enum.Material.Wood)
	local barometer = part(parent, "BarometerDial", Vector3.new(0.06, 1, 1), glass * CFrame.new(0, -0.6, -0.1)
		* CFrame.Angles(0, math.pi / 2, 0), Color3.fromRGB(244, 238, 222), Enum.Material.SmoothPlastic)
	barometer.Shape = Enum.PartType.Cylinder
	part(parent, "BarometerNeedle", Vector3.new(0.05, 0.4, 0.02), glass * CFrame.new(0, -0.45, -0.15), PALETTE.dark,
		Enum.Material.Metal)

	-- THE UMBRELLA STAND by the door, his umbrella in it.
	local stand = centre * CFrame.new(-2.9, floorY, -inZ + 0.7)
	cylinder(parent, "UmbrellaStand", 1.6, 0.8, stand * CFrame.new(0, 0.8, 0), Color3.fromRGB(46, 58, 96), Enum.Material.SmoothPlastic)
	cylinder(parent, "Umbrella", 2.8, 0.22, stand * CFrame.new(0, 1.55, 0), PALETTE.dark, Enum.Material.Fabric)
	part(parent, "UmbrellaHandle", Vector3.new(0.12, 0.12, 0.45), stand * CFrame.new(0, 3.0, 0.15), mahogany, Enum.Material.Wood)

	return {
		-- THE HALL'S ROOM, floor to ceiling and wall to wall, that your camera is kept in while you are in it.
		box = centre * CFrame.new(0, (floorY + STOREY - 0.3) / 2, 0),
		boxSize = Vector3.new(W - 2, STOREY - 0.3 - floorY, D - 2),
		spot = centre * CFrame.new(KEY_HOOK.X, floorY + 3, inner + KEY_STAND),
		key = shank,
		keyAt = shank.Position,
		clockFace = face.Position,
		clockFacing = clock.LookVector,
		pivot = pivot,
		back = (centre * CFrame.new(-3.5, floorY + 6.2, D / 2 - 2.6)).Position,
		-- Just inside the open door, on its unhinged side: where you go with the key, to look out (HillHouseClient).
		door = (centre * CFrame.new(0.6, floorY + 3, inner + 1.6)).Position,
	}
end

-- ===== THE HOUSE =====
--
-- Two storeys of white render on a brick plinth under a slate roof, a chimney at one end, sash windows, and the front
-- door in his green under a little porch, a brass knocker and the house's name. `front` is the middle of the front
-- wall's foot, facing out (its LookVector the way the front faces).
local function buildHouse(parent: Instance, front: CFrame): (BasePart, { [string]: any })
	local W, D = HOUSE_W, HOUSE_D
	local height = STOREY * 2
	-- The house's own frame: its middle, on the ground; -Z is the front.
	local centre = front * CFrame.new(0, 0, D / 2)
	local wallT = 1
	-- THE PLINTH, a course of brick round the foot.
	part(parent, "Plinth", Vector3.new(W + 0.6, 1.2, D + 0.6), centre * CFrame.new(0, 0.6, 0), PALETTE.plinth,
		Enum.Material.Brick, true)
	-- THE FRONT, with its door and four windows.
	local doorW, doorH = 4.2, 8
	local winW, winH = 4, 5
	local frontHoles = {
		{ -doorW / 2, doorW / 2, 1.2, 1.2 + doorH },
		{ -W / 2 + 3.5, -W / 2 + 3.5 + winW, 3.5, 3.5 + winH }, { W / 2 - 3.5 - winW, W / 2 - 3.5, 3.5, 3.5 + winH },
		{ -W / 2 + 3.5, -W / 2 + 3.5 + winW, STOREY + 3, STOREY + 3 + winH },
		{ W / 2 - 3.5 - winW, W / 2 - 3.5, STOREY + 3, STOREY + 3 + winH },
		{ -winW / 2, winW / 2, STOREY + 3, STOREY + 3 + winH },
	}
	local frontWall = centre * CFrame.new(0, 0, -D / 2 + wallT / 2)
	wallWithHoles(parent, "FrontWall", frontWall, W, height, wallT, frontHoles, PALETTE.render, Enum.Material.Plaster)
	for k = 2, #frontHoles do
		local h = frontHoles[k]
		window(parent, frontWall * CFrame.new((h[1] + h[2]) / 2, (h[3] + h[4]) / 2, 0), h[2] - h[1], h[4] - h[3],
			h[3] >= STOREY)
	end
	-- THE BACK and THE SIDES, a window a storey each side and two at the back.
	local backWall = centre * CFrame.new(0, 0, D / 2 - wallT / 2) * CFrame.Angles(0, math.pi, 0)
	local backHoles = { { -6, -2, 3.5, 3.5 + winH }, { 2, 6, STOREY + 3, STOREY + 3 + winH } }
	wallWithHoles(parent, "BackWall", backWall, W, height, wallT, backHoles, PALETTE.render, Enum.Material.Plaster)
	for _, h in ipairs(backHoles) do
		window(parent, backWall * CFrame.new((h[1] + h[2]) / 2, (h[3] + h[4]) / 2, 0), h[2] - h[1], h[4] - h[3],
			h[3] >= STOREY)
	end
	for _, side in ipairs({ -1, 1 }) do
		local sideWall = centre * CFrame.new(side * (W / 2 - wallT / 2), 0, 0) * CFrame.Angles(0, -side * math.pi / 2, 0)
		local sideHoles = { { -2, 2, 3.5, 3.5 + winH }, { -2, 2, STOREY + 3, STOREY + 3 + winH } }
		wallWithHoles(parent, "SideWall", sideWall, D - wallT * 2, height, wallT, sideHoles, PALETTE.render,
			Enum.Material.Plaster)
		for _, h in ipairs(sideHoles) do
			window(parent, sideWall * CFrame.new(0, (h[3] + h[4]) / 2, 0), h[2] - h[1], h[4] - h[3], h[3] >= STOREY)
		end
		-- THE GABLE, a triangle of render up to the ridge, in two halves under the two slopes.
		for _, half in ipairs({ -1, 1 }) do
			wedge(parent, "Gable", Vector3.new(wallT, ROOF_H, D / 2),
				centre * CFrame.new(side * (W / 2 - wallT / 2), height + ROOF_H / 2, half * D / 4)
					* CFrame.Angles(0, if half < 0 then 0 else math.pi, 0), PALETTE.render, Enum.Material.Plaster)
		end
	end
	-- THE FIRST FLOOR, so the upstairs windows have a floor behind them; solid, the hall's ceiling, so a camera stops at
	-- it (it went up through it into the empty upstairs: your test of 2026-10-22).
	part(parent, "Floor", Vector3.new(W - wallT * 2, 0.6, D - wallT * 2), centre * CFrame.new(0, STOREY, 0), PALETTE.timber,
		Enum.Material.WoodPlanks, true)
	-- (The ground floor is the hall's own boards, on the plinth: buildHall.)
	-- THE ROOF: two slate slopes meeting at the ridge, a little over the walls all round, and the ridge tiles.
	for _, half in ipairs({ -1, 1 }) do
		wedge(parent, "Roof", Vector3.new(W + 2, ROOF_H, D / 2 + 1),
			centre * CFrame.new(0, height + ROOF_H / 2, half * (D / 4 + 0.5)) * CFrame.Angles(0, if half < 0 then 0 else math.pi, 0),
			PALETTE.slate, Enum.Material.Slate)
	end
	cylinder(parent, "Ridge", W + 2, 0.8, centre * CFrame.new(0, height + ROOF_H, 0) * CFrame.Angles(0, 0, -math.pi / 2),
		PALETTE.plinth, Enum.Material.Brick)
	-- THE CHIMNEY at one end, on the ridge, with two pots.
	local stack = centre * CFrame.new(W / 2 - 3, height + ROOF_H + 1.5, 0)
	part(parent, "Chimney", Vector3.new(3, 7, 3.2), stack, PALETTE.plinth, Enum.Material.Brick)
	for _, x in ipairs({ -0.7, 0.7 }) do
		cylinder(parent, "ChimneyPot", 1.4, 0.9, stack * CFrame.new(x, 4.2, 0), Color3.fromRGB(170, 104, 74),
			Enum.Material.Concrete)
	end
	-- THE FRONT DOOR, his green, hung on its left: a hinge part it turns about.
	local doorFoot = frontWall * CFrame.new(-doorW / 2, 1.2, -0.2)
	local hinge = part(parent, "DoorHinge", Vector3.new(0.2, 0.2, 0.2), doorFoot, PALETTE.dark, Enum.Material.SmoothPlastic)
	hinge.Transparency = 1
	local door = part(parent, "FrontDoor", Vector3.new(doorW, doorH, 0.35), doorFoot * CFrame.new(doorW / 2, doorH / 2, 0),
		PALETTE.door, Enum.Material.SmoothPlastic, true)
	door.Reflectance = 0.08
	door:SetAttribute("Closed", door.CFrame)
	part(parent, "Knocker", Vector3.new(0.7, 0.9, 0.2), door.CFrame * CFrame.new(0, 0.8, -0.25), PALETTE.brass,
		Enum.Material.Metal)
	part(parent, "Letterbox", Vector3.new(1.6, 0.35, 0.15), door.CFrame * CFrame.new(0, -0.8, -0.22), PALETTE.brass,
		Enum.Material.Metal)
	part(parent, "DoorKnob", Vector3.new(0.35, 0.35, 0.35), door.CFrame * CFrame.new(doorW / 2 - 0.5, -0.4, -0.3), PALETTE.brass,
		Enum.Material.Metal)
	-- The step, and the porch over it on two brackets.
	part(parent, "DoorStep", Vector3.new(doorW + 2, 1.2, 2.4), frontWall * CFrame.new(0, 0.6, -1.6), PALETTE.stone,
		Enum.Material.Concrete, true)
	for _, x in ipairs({ -1, 1 }) do
		part(parent, "PorchBracket", Vector3.new(0.4, 1.6, 2), frontWall * CFrame.new(x * (doorW / 2 + 0.6), 9.8, -1),
			PALETTE.frame, Enum.Material.SmoothPlastic)
	end
	-- THE PORCH HOOD (the two-hundred-and-twelfth pass: its two wedges read as a pair of black wings): two slate
	-- slopes meeting at a ridge over the door, each with a white board along its foot, lying on the brackets.
	for _, half in ipairs({ -1, 1 }) do
		local slope = frontWall * CFrame.new(half * 1.55, 11.25, -1.3) * CFrame.Angles(0, 0, -half * 0.42)
		part(parent, "PorchRoof", Vector3.new(3.5, 0.3, 2.9), slope, PALETTE.slate, Enum.Material.Slate)
		part(parent, "PorchFascia", Vector3.new(3.5, 0.35, 0.14), slope * CFrame.new(0, -0.2, -1.45), PALETTE.frame,
			Enum.Material.SmoothPlastic)
	end
	part(parent, "PorchRidge", Vector3.new(0.35, 0.3, 2.9), frontWall * CFrame.new(0, 11.95, -1.3), PALETTE.plinth,
		Enum.Material.Brick)
	-- THE DOOR'S SURROUND: a white pilaster each side and a head over it, standing on the step.
	for _, x in ipairs({ -1, 1 }) do
		part(parent, "DoorPilaster", Vector3.new(0.5, 8.2, 0.3), frontWall * CFrame.new(x * (doorW / 2 + 0.25), 5.3, -0.62),
			PALETTE.frame, Enum.Material.SmoothPlastic)
	end
	part(parent, "DoorHead", Vector3.new(doorW + 1.4, 0.5, 0.45), frontWall * CFrame.new(0, 9.65, -0.7), PALETTE.frame,
		Enum.Material.SmoothPlastic)

	-- ===== THE HOUSE, FINISHED (the two-hundred-and-twelfth pass, from your note of 2026-11-07: Hill House's models,
	-- inside and out). It was a plain box of render. Now: dressed stone at its corners, a band of stone between the
	-- storeys, a gutter under each eave and a downpipe from the front one to the ground, his green shutters at the
	-- front windows and a box of flowers under each one downstairs. All of it on the walls or the roof it belongs to.
	local quoin = Color3.fromRGB(206, 198, 182)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local row = 0
			for y = 1.2, height - 0.9, 1 do
				local long = if row % 2 == 0 then 1.8 else 1.1
				local other = if row % 2 == 0 then 1.1 else 1.8
				part(parent, "Quoin", Vector3.new(long, 0.85, 0.3),
					centre * CFrame.new(sx * (W / 2 - long / 2 + 0.15), y + 0.45, sz * (D / 2 + 0.15)), quoin, Enum.Material.Limestone)
				part(parent, "Quoin", Vector3.new(0.3, 0.85, other),
					centre * CFrame.new(sx * (W / 2 + 0.15), y + 0.45, sz * (D / 2 - other / 2 + 0.15)), quoin, Enum.Material.Limestone)
				row += 1
			end
		end
	end
	-- The band between the storeys, under the upstairs windows.
	for _, sz in ipairs({ -1, 1 }) do
		part(parent, "StringCourse", Vector3.new(W + 0.3, 0.4, 0.3), centre * CFrame.new(0, STOREY + 0.2, sz * (D / 2 + 0.15)),
			quoin, Enum.Material.Limestone)
	end
	for _, sx in ipairs({ -1, 1 }) do
		part(parent, "StringCourse", Vector3.new(0.3, 0.4, D + 0.3), centre * CFrame.new(sx * (W / 2 + 0.15), STOREY + 0.2, 0),
			quoin, Enum.Material.Limestone)
	end
	-- The gutters under the eaves, and the downpipe from the front one, down the right-hand side wall on its clips.
	local iron = Color3.fromRGB(46, 50, 56)
	for _, sz in ipairs({ -1, 1 }) do
		local gutter = part(parent, "Gutter", Vector3.new(W + 2, 0.5, 0.5), centre * CFrame.new(0, height - 0.15, sz * (D / 2 + 1.05)),
			iron, Enum.Material.Metal)
		gutter.Shape = Enum.PartType.Cylinder
	end
	-- (Behind the corner's stones, which reach 1.8 along the side wall.)
	local pipeX, pipeZ = W / 2 + 0.45, -D / 2 + 2.4
	cylinder(parent, "Downpipe", height - 0.6, 0.4, centre * CFrame.new(pipeX, (height - 0.6) / 2, pipeZ), iron, Enum.Material.Metal)
	local reach = (D / 2 + 1.05) + pipeZ
	part(parent, "DownpipeElbow", Vector3.new(0.4, 0.4, reach), centre * CFrame.new(pipeX, height - 0.4, pipeZ - reach / 2), iron,
		Enum.Material.Metal)
	for y = 3, height - 3, 6 do
		part(parent, "DownpipeClip", Vector3.new(0.3, 0.2, 0.55), centre * CFrame.new(W / 2 + 0.2, y, pipeZ), iron, Enum.Material.Metal)
	end
	-- His green shutters, open against the wall either side of each front window, and the flower boxes downstairs.
	local petals = { Color3.fromRGB(226, 120, 150), Color3.fromRGB(248, 244, 236), Color3.fromRGB(206, 64, 72),
		Color3.fromRGB(240, 196, 80) }
	for k = 2, #frontHoles do
		local h = frontHoles[k]
		local mid = (h[1] + h[2]) / 2
		local cy = (h[3] + h[4]) / 2
		local half = (h[2] - h[1]) / 2
		for _, side in ipairs({ -1, 1 }) do
			-- (1.6 wide: the upstairs windows are 3.5 apart, room for two shutters back to back.)
			local shutter = frontWall * CFrame.new(mid + side * (half + 0.85), cy, -0.62)
			part(parent, "Shutter", Vector3.new(1.6, h[4] - h[3], 0.2), shutter, PALETTE.door, Enum.Material.Wood)
			for slat = -2, 2 do
				part(parent, "ShutterSlat", Vector3.new(1.25, 0.12, 0.08), shutter * CFrame.new(0, slat * 0.9, -0.12), PALETTE.door,
					Enum.Material.Wood)
			end
		end
		if h[3] < STOREY then
			local box = frontWall * CFrame.new(mid, h[3] - 0.75, -0.9)
			part(parent, "FlowerBox", Vector3.new(h[2] - h[1], 0.8, 0.8), box, PALETTE.timber, Enum.Material.Wood)
			part(parent, "FlowerLeaves", Vector3.new(h[2] - h[1] - 0.3, 0.3, 0.6), box * CFrame.new(0, 0.5, 0), PALETTE.canopy,
				Enum.Material.Grass)
			for f = 0, 6 do
				ball(parent, "Flower", 0.45, (box * CFrame.new(-1.5 + f * 0.5, 0.75, (f % 2) * 0.24 - 0.12)).Position,
					petals[f % #petals + 1], Enum.Material.SmoothPlastic)
			end
		end
	end
	-- THE MILK on the step, two bottles with their foil caps, and the morning's paper on the mat.
	for k = 0, 1 do
		local at = frontWall * CFrame.new(doorW / 2 + 0.2 - k * 0.6, 1.9, -1.6)
		cylinder(parent, "MilkBottle", 1.1, 0.5, at, Color3.fromRGB(248, 248, 244), Enum.Material.Glass)
		cylinder(parent, "MilkCap", 0.08, 0.5, at * CFrame.new(0, 0.58, 0), Color3.fromRGB(196, 196, 204), Enum.Material.Foil)
	end
	part(parent, "Newspaper", Vector3.new(1.8, 0.15, 1.2), frontWall * CFrame.new(-0.6, 1.28, -1.4) * CFrame.Angles(0, 0.3, 0),
		Color3.fromRGB(226, 220, 204), Enum.Material.Fabric)
	return door, buildHall(parent, centre)
end

-- ===== THE GARDEN =====

local function picketFence(parent: Instance, centre: Vector3, radius: number, topY: number, gate: Vector3)
	local count = math.floor(2 * math.pi * radius / 1.4)
	local gateDir = flat(gate - centre)
	for k = 0, count - 1 do
		local a = k / count * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		-- A GAP for the gate where the footbridge comes in.
		if dir:Dot(gateDir) < math.cos(math.rad(5.5)) then
			local at = centre + dir * radius
			local picket = part(parent, "Picket", Vector3.new(0.3, 3.4, 0.6), CFrame.lookAt(Vector3.new(at.X, topY + 1.7, at.Z),
				Vector3.new(centre.X, topY + 1.7, centre.Z)), PALETTE.picket, Enum.Material.WoodPlanks, true)
			picket.CanQuery = false
		end
	end
	-- Two rails round it, on the pickets.
	local segs = 48
	for k = 0, segs - 1 do
		local a0, a1 = k / segs * math.pi * 2, (k + 1) / segs * math.pi * 2
		local p0 = centre + Vector3.new(math.cos(a0), 0, math.sin(a0)) * radius
		local p1 = centre + Vector3.new(math.cos(a1), 0, math.sin(a1)) * radius
		local mid = (p0 + p1) / 2
		if flat(mid - centre):Dot(gateDir) < math.cos(math.rad(5.5)) then
			for _, y in ipairs({ 1.1, 2.6 }) do
				part(parent, "FenceRail", Vector3.new(0.25, 0.3, (p1 - p0).Magnitude + 0.1),
					CFrame.lookAt(Vector3.new(mid.X, topY + y, mid.Z), Vector3.new(p1.X, topY + y, p1.Z)), PALETTE.picket,
					Enum.Material.WoodPlanks)
			end
		end
	end
	-- The gate's two posts, and the gate itself, standing open.
	local side = Vector3.yAxis:Cross(gateDir)
	for _, s in ipairs({ -1, 1 }) do
		local at = centre + gateDir * radius + side * s * 3.2
		part(parent, "GatePost", Vector3.new(0.7, 4.4, 0.7), CFrame.new(at.X, topY + 2.2, at.Z), PALETTE.picket,
			Enum.Material.WoodPlanks, true)
		part(parent, "GatePostCap", Vector3.new(1, 0.3, 1), CFrame.new(at.X, topY + 4.55, at.Z), PALETTE.picket,
			Enum.Material.WoodPlanks)
	end
	local hingeAt = centre + gateDir * radius + side * 3.2
	part(parent, "Gate", Vector3.new(0.3, 3.2, 5.6),
		CFrame.lookAt(Vector3.new(hingeAt.X, topY + 1.9, hingeAt.Z), Vector3.new(hingeAt.X, topY + 1.9, hingeAt.Z) + gateDir)
			* CFrame.new(0, 0, -2.8), PALETTE.picket, Enum.Material.WoodPlanks)
end

local function nameplate(parent: Instance, at: CFrame)
	local plate = part(parent, "NamePlate", Vector3.new(3.2, 0.9, 0.12), at, PALETTE.dark, Enum.Material.Slate)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 1
	gui.Parent = plate
	local words = Instance.new("TextLabel")
	words.BackgroundTransparency = 1
	words.Size = UDim2.fromScale(1, 1)
	words.FontFace = Style.WORLD.sign
	words.TextScaled = true
	words.TextColor3 = Color3.fromRGB(236, 228, 210)
	words.Text = "HILL HOUSE"
	words.Parent = gui
end

local function appleTree(parent: Instance, at: Vector3)
	cylinder(parent, "TreeTrunk", 7, 1.4, CFrame.new(at + Vector3.new(0, 3.5, 0)), PALETTE.tree, Enum.Material.Wood, true)
	for k, off in ipairs({ Vector3.new(0, 8.5, 0), Vector3.new(2.2, 7.6, 1), Vector3.new(-2, 7.8, -1.2), Vector3.new(0.6, 9.6, -1.6) }) do
		ball(parent, "TreeCanopy", 6 - (k % 2), at + off, PALETTE.canopy, Enum.Material.LeafyGrass)
	end
	for k = 1, 7 do
		local a = k * 2.4
		ball(parent, "Apple", 0.55, at + Vector3.new(math.cos(a) * 2.6, 7 + (k % 3) * 0.8, math.sin(a) * 2.6), PALETTE.apple,
			Enum.Material.SmoothPlastic)
	end
end

local function bench(parent: Instance, at: Vector3, facing: Vector3)
	local cf = CFrame.lookAt(at, at + facing)
	part(parent, "BenchSeat", Vector3.new(6, 0.4, 1.8), cf * CFrame.new(0, 1.8, 0), PALETTE.timber, Enum.Material.WoodPlanks, true)
	part(parent, "BenchBack", Vector3.new(6, 1.6, 0.3), cf * CFrame.new(0, 2.9, 0.85), PALETTE.timber, Enum.Material.WoodPlanks)
	for _, x in ipairs({ -2.6, 2.6 }) do
		part(parent, "BenchLeg", Vector3.new(0.4, 1.6, 1.6), cf * CFrame.new(x, 0.8, 0), Color3.fromRGB(60, 58, 62),
			Enum.Material.Metal, true)
	end
end

-- ===== THE GARDEN, LIVED IN (the hundred-and-eighty-eighth pass) =====
--
-- From your note of 2026-11-04: "then we need to make level 5 less barren". The top of the crag was a lawn eighty-five
-- studs across with one apple tree and one bench on it. Now it is a cottage garden: roses along the front of the house
-- and by the gate, a well, a wheelbarrow of flowers by the path, three beehives under the trees, a birdbath, and three
-- more apple trees. The made ones come from Studio's mesh generator (Assets/Props, Hill_*); whichever is not there is
-- left out. Each stands on the grass, placed in the garden's own frame (studs across, studs in from the middle toward
-- the house), clear of the house (in 4 to 22, across 13 either way), the path (across 2.6 either way of the middle),
-- the old tree, the bench, and Mrs Dunn inside the gate; its height, and its turn. The well and the hives are solid.
local GARDEN = {
	{ "Hill_Well", -24, -18, 7, 0.4 },
	{ "Hill_Wheelbarrow", 7, -29, 2.6, 1.2 },
	{ "Hill_Birdbath", 16, -20, 2.6, 0 },
	{ "Hill_Beehive", -33, 9, 3, 1.57 },
	{ "Hill_Beehive", -33, 13.5, 3, 1.57 },
	{ "Hill_Beehive", -33, 18, 3, 1.57 },
	{ "Hill_Roses", -7, 1.6, 3, 0 },
	{ "Hill_Roses", 7, 1.6, 3, 1 },
	{ "Hill_Roses", -11, 1.6, 2.6, 2 },
	{ "Hill_Roses", 11, 1.6, 2.6, 3 },
	{ "Hill_Roses", -6.5, -39, 2.8, 0.5 },
	{ "Hill_Roses", -11, -37, 2.6, 2.5 },
	{ "Hill_Roses", 22, -12, 3, 1.5 },
	{ "Hill_Roses", -15, -30, 2.6, 4 },
}
local GARDEN_TREES = { { 28, 18 }, { -12, 30 }, { 28, -24 } }
local GARDEN_SOLID = { Hill_Well = true, Hill_Beehive = true }
local function dressGarden(garden: Instance, top: Vector3, inward: Vector3, across: Vector3)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Props")
	for _, spot in ipairs(GARDEN) do
		local name = spot[1] :: string
		local model = folder and folder:FindFirstChild(name)
		local template = model and model:FindFirstChildWhichIsA("BasePart")
		if template then
			local piece = template:Clone()
			piece.Name = name
			piece.Size = template.Size * ((spot[4] :: number) / template.Size.Y)
			local at = top + across * (spot[2] :: number) + inward * (spot[3] :: number)
			piece.CFrame = CFrame.lookAt(at, at + inward) * CFrame.Angles(0, spot[5] :: number, 0)
				* CFrame.new(0, piece.Size.Y / 2, 0)
			piece.Anchored = true
			piece.CanCollide = GARDEN_SOLID[name] == true
			piece.CanTouch = false
			piece.Parent = garden
		end
	end
	for _, spot in ipairs(GARDEN_TREES) do
		appleTree(garden, top + across * spot[1] + inward * spot[2])
	end
	-- A PAL CLIPPED IN HEDGE (pass 264: the pals as a structure on every level): Bumble, as topiary on a low hedge plinth,
	-- on the lawn by the well, turned to the path, the way a cottage garden has a peacock in box. (Seen in play: at -22, -2
	-- it stood under the old apple tree, whose trunk is at -20, 2.)
	local PetStatues = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PetStatues")) :: any
	local hedgeAt = top + across * -26 + inward * -8
	PetStatues.statue(garden, "Pal_Bee", CFrame.lookAt(hedgeAt, hedgeAt + across), 6.5, 1.6, "topiary")
end

-- ===== WHO IS UP HERE AT EIGHT (the hundred-and-thirteenth pass) =====
--
-- MR GALE, the milkman, at the top of the climb: on the landing, on the far side from the way over to the bridge and
-- toward its far end (never between you and the bridge), his crate of milk at his feet and an empty in his hand, facing
-- whoever comes up. MRS DUNN, the postwoman, inside the gate beside the path, her bag on her shoulder and the morning's
-- letters in her hand, facing the gate. Everything of theirs is the people's own (CanCollide off), but the crate, which
-- stands on the landing.
local function people(model: Instance, garden: Instance, landing: CFrame, out: Vector3, gate: Vector3, inward: Vector3,
	across: Vector3, topY: number)
	if not Townsfolk then
		return
	end
	local away = if landing.RightVector:Dot(out) > 0 then -1 else 1
	local spot = landing * CFrame.new(away * (LANDING.X / 2 - 2.5), LANDING.Y / 2, -(LANDING.Z / 2 - 2.5))
	local arrive = (landing * CFrame.new(0, LANDING.Y / 2, LANDING.Z / 2)).Position
	local feet = CFrame.lookAt(spot.Position, Vector3.new(arrive.X, spot.Y, arrive.Z))
	-- His crate, on the landing at his side: a wire crate and the tops of six bottles.
	local crate = feet * CFrame.new(-away * 1.6, 0, 0.6)
	part(model, "MilkCrate", Vector3.new(1.8, 1, 1.3), crate * CFrame.new(0, 0.5, 0), Color3.fromRGB(70, 96, 120),
		Enum.Material.Metal, true)
	for k = 0, 5 do
		local x, z = (k % 3 - 1) * 0.55, (math.floor(k / 3) - 0.5) * 0.55
		cylinder(model, "MilkBottle", 0.5, 0.36, crate * CFrame.new(x, 1.2, z) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(246, 246, 240), Enum.Material.Glass)
	end
	local gale = Townsfolk.spawn(model, "Gale", feet, "stand",
		{ Color3.fromRGB(222, 182, 150), Color3.fromRGB(242, 240, 234), Color3.fromRGB(46, 52, 70) })
	if gale then
		Townsfolk.wear(gale, "Cap", Vector3.new(0.35, 1.32, 1.32), Color3.fromRGB(242, 240, 234), "Head",
			CFrame.new(0, 0.55, 0.02) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
		Townsfolk.wear(gale, "CapPeak", Vector3.new(1.05, 0.08, 0.5), Color3.fromRGB(46, 52, 70), "Head", CFrame.new(0, 0.42, -0.72))
		Townsfolk.wear(gale, "EmptyBottle", Vector3.new(0.9, 0.34, 0.34), Color3.fromRGB(236, 240, 238), "LeftHand",
			CFrame.new(0, -0.45, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
	end
	local stand = gate + inward * 5 + across * 4.8
	stand = Vector3.new(stand.X, topY, stand.Z)
	local dunn = Townsfolk.spawn(garden, "Dunn", CFrame.lookAt(stand, Vector3.new(gate.X, topY, gate.Z)), "stand",
		{ Color3.fromRGB(176, 128, 96), Color3.fromRGB(40, 54, 92), Color3.fromRGB(40, 54, 92) })
	if dunn then
		local red = Color3.fromRGB(176, 40, 40)
		Townsfolk.wear(dunn, "PostBag", Vector3.new(0.5, 1.3, 1.3), red, "UpperTorso", CFrame.new(1.05, -1.1, 0))
		Townsfolk.wear(dunn, "BagStrap", Vector3.new(0.14, 2.7, 0.12), Color3.fromRGB(120, 30, 30), "UpperTorso",
			CFrame.new(0.1, -0.1, -0.55) * CFrame.Angles(0, 0, 0.62))
		Townsfolk.wear(dunn, "Letters", Vector3.new(0.7, 0.12, 0.5), Color3.fromRGB(240, 234, 220), "RightHand",
			CFrame.new(0, -0.3, -0.3))
	end
end

-- ===== THE MIST, and what stands out of it =====

local function mistSheets(parent: Instance, centre: Vector3, topY: number)
	-- ONE SOLID SHEET (the hundred-and-eighteenth pass, from your test: the honey, slime and soda "stay invisible most of
	-- the time"). It was three see-through sheets nineteen hundred studs across, and Roblox draws see-through parts one
	-- after another by how far each one's middle is from the camera: the mist's middle was nearer than every chunk
	-- across the spiral, so it was drawn after them and painted over them. Opaque, it is drawn with the solid things and
	-- hides nothing in front of it; the morning's haze (LightingService) softens its far edge, and banks of mist roll
	-- across its top so it is not a painted floor.
	local sheet = cylinder(parent, "Mist", 3, 1900, CFrame.new(centre.X, topY - 6, centre.Z), PALETTE.mist,
		Enum.Material.SmoothPlastic)
	sheet.CastShadow = false
	-- OUT TO THE HORIZON (the two-hundred-and-forty-first pass, from "polish the game more"). The sheet ended nineteen
	-- hundred studs across, and from the middle of the walk you saw its rim and a band of bare pink sky beyond it, a white
	-- disc hanging in nothing. Square sheets of the same mist (a part is at most 2048 studs a side) go on past it, a hair
	-- lower so the two never fight, seven by seven, out past where the haze takes everything.
	local TILE = 1900
	for gx = -3, 3 do
		for gz = -3, 3 do
			local tile = part(parent, "MistFar", Vector3.new(TILE + 4, 3, TILE + 4),
				CFrame.new(centre.X + gx * TILE, topY - 6.3, centre.Z + gz * TILE), PALETTE.mist, Enum.Material.SmoothPlastic)
			tile.CastShadow = false
		end
	end
	local wind = Vector3.new(1, 0, 0.4).Unit
	-- (A third ring since the same pass, out where the walk climbs, so the mist is seen moving under the route too.)
	for ring = 0, 2 do
		local reach = 130 + ring * 170
		local count = 6 + ring * 4
		for index = 1, count do
			local a = (index + ring * 0.5) / count * math.pi * 2
			local host = part(parent, "MistBank", Vector3.new(140, 2, 140),
				CFrame.new(centre.X + math.cos(a) * reach, topY - 4, centre.Z + math.sin(a) * reach), PALETTE.mist,
				Enum.Material.SmoothPlastic)
			host.Transparency = 1
			local rolling = Instance.new("ParticleEmitter")
			rolling.Name = "Mist"
			rolling.Texture = "rbxasset://textures/particles/smoke_main.dds"
			rolling.Color = ColorSequence.new(PALETTE.mist)
			rolling.LightInfluence = 0.9
			rolling.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 24), NumberSequenceKeypoint.new(1, 52) })
			rolling.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.74),
				NumberSequenceKeypoint.new(0.75, 0.82), NumberSequenceKeypoint.new(1, 1) })
			rolling.Lifetime = NumberRange.new(14, 22)
			rolling.Speed = NumberRange.new(0.4, 1.2)
			rolling.Acceleration = wind * 0.3
			rolling.Rotation = NumberRange.new(0, 360)
			rolling.RotSpeed = NumberRange.new(-4, 4)
			rolling.Shape = Enum.ParticleEmitterShape.Box
			rolling.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			rolling.EmissionDirection = Enum.NormalId.Top
			rolling.Rate = 0.5
			rolling.Parent = host
		end
	end
end

-- ===== THE COUNTRY OUT OF THE MIST, IN TERRAIN (pass 270) =====
--
-- From your note: "improve the background hills". They were squashed balls of grass, every one the same smooth egg,
-- and a squashed ball is not a hill. Now each is smooth voxel terrain written from a height field (WriteVoxels): a
-- long rolling ridge on a warped outline, lumps and a second crest along it, a saddle between; grass on its gentle
-- slopes, patches of meadow, bare earth where it steepens and rock where it falls away. Only its shell above the mist
-- is made (the mist hides its feet), in slices a frame apart, and every slice is put down in `filled` so the level
-- takes it all away with the rest of its terrain.
type Hill = { cx: number, cz: number, base: number, radius: number, rise: number, seed: number, along: Vector3,
	stretch: number, flat: number?, far: boolean? }

-- THE LAND ON A HILL (pass 271, from your note: "improve the hills"): the gentle slopes laid out in FIELDS, a patchwork
-- on a grid turned with the hill and bent by noise, about FIELD studs a side, mostly grass and some ploughed earth, with
-- HEDGEROWS of leafy green along their edges; moorland over the high ground; bare earth where it steepens; rock where it
-- falls away. The far ranges are all moor and rock (fields too small to see).
local FIELD = 64
local function landAt(h: Hill, x: number, z: number, height: number, slope: number): Enum.Material
	-- (Seen in play: rock on anything but the steepest drops reads as crushed glass at this distance, and the moor took
	-- most slopes so the fields hardly showed; both held back.)
	if slope > 1.35 then
		return Enum.Material.Rock
	elseif slope > 0.8 then
		return Enum.Material.Ground
	end
	if h.far or height > h.rise * 0.82 or slope > 0.6 then
		return if math.noise(x / 50, z / 50, h.seed + 3) > 0.42 then Enum.Material.Ground else Enum.Material.LeafyGrass
	end
	local dx, dz = x - h.cx, z - h.cz
	local u = (dx * h.along.X + dz * h.along.Z) + 18 * math.noise(x / 90, z / 90, h.seed)
	local v = (-dx * h.along.Z + dz * h.along.X) + 18 * math.noise(z / 90, x / 90, h.seed + 1)
	local fu, fv = u / FIELD, v / (FIELD * 0.8)
	local eu, ev = math.abs(fu - math.floor(fu + 0.5)) * FIELD, math.abs(fv - math.floor(fv + 0.5)) * FIELD * 0.8
	if eu < 4 or ev < 4 then
		return Enum.Material.LeafyGrass -- a hedgerow
	end
	local pick = math.noise(math.floor(fu) * 1.7 + h.seed, math.floor(fv) * 1.3, 0.5)
	return if pick > 0.3 then Enum.Material.Ground elseif pick < -0.3 then Enum.Material.LeafyGrass else Enum.Material.Grass
end

-- Its height above `base` at (x, z): 0 outside it.
local function hillHeight(h: Hill, x: number, z: number): number
	local dx, dz = x - h.cx, z - h.cz
	local a = (dx * h.along.X + dz * h.along.Z) / h.radius
	local b = (-dx * h.along.Z + dz * h.along.X) / (h.radius * h.stretch)
	-- A warped outline, so no hill is an ellipse.
	local warp = 0.22 * math.noise(a * 1.1 + h.seed, b * 1.1 - h.seed, 0.37)
	local d = math.sqrt(a * a + b * b) + warp
	if d >= 1 then
		return 0
	end
	local dome = (1 - d * d) ^ 1.35
	-- A second crest off along the ridge, and a saddle between, and lumps all over it.
	local crest = math.exp(-((a - 0.45) ^ 2 + (b * 1.4) ^ 2) * 6) * 0.35
	local lumps = 0.16 * math.noise(a * 2.6 + h.seed * 3, b * 2.6, 1.7) + 0.07 * math.noise(a * 6, b * 6 + h.seed, 4.1)
	local height = h.rise * math.max(0, dome * (1 + lumps) + crest * dome)
	if h.flat then
		-- A level crown (St Brigid's, for its church): flattened to `flat`, eased into the slope round it.
		local top = h.flat :: number
		if height > top then
			height = top + (height - top) * 0.08
		end
	end
	return height
end

local function writeHill(h: Hill, alive: () -> boolean)
	local terrain = workspace.Terrain
	-- Its box, fitted to its turned outline (a long ridge on a slant is not a square).
	local ex = (math.abs(h.along.X) + math.abs(h.along.Z) * h.stretch) * h.radius * 1.3
	local ez = (math.abs(h.along.Z) + math.abs(h.along.X) * h.stretch) * h.radius * 1.3
	local x0 = math.floor((h.cx - ex) / 4) * 4
	local z0 = math.floor((h.cz - ez) / 4) * 4
	local nx = math.ceil(ex * 2 / 4) + 1
	local nz = math.ceil(ez * 2 / 4) + 1
	local y0 = math.floor((h.base - 8) / 4) * 4
	local ny = math.ceil((h.rise * 1.45 + 16) / 4)
	-- Each column's surface height, once.
	local tops = table.create(nx)
	for i = 1, nx do
		local row = table.create(nz)
		for k = 1, nz do
			local height = hillHeight(h, x0 + (i - 0.5) * 4, z0 + (k - 0.5) * 4)
			row[k] = if height > 0 then h.base + height else -math.huge
		end
		tops[i] = row
	end
	local SLICE = 24
	for i0 = 1, nx, SLICE do
		-- (The level gone meanwhile: no more of it, so nothing is left behind after its terrain is cleared.)
		if not alive() then
			return
		end
		local i1 = math.min(nx, i0 + SLICE - 1)
		local w = i1 - i0 + 1
		local low = Vector3.new(x0 + (i0 - 1) * 4, y0, z0)
		local high = low + Vector3.new(w * 4, ny * 4, nz * 4)
		local region = Region3.new(low, high)
		-- What is there already (a neighbouring hill's slope): only ever added to, never written over with air.
		local materials, occupancy = terrain:ReadVoxels(region, 4)
		for i = i0, i1 do
			local mRow, oRow = materials[i - i0 + 1], occupancy[i - i0 + 1]
			for k = 1, nz do
				local top = tops[i][k]
				if top > y0 then
					-- Its slope, from its neighbours: grass, earth, rock by how steep it is; meadow in patches.
					local function at(ii: number, kk: number): number
						local row = tops[math.clamp(ii, 1, nx)]
						local v = row[math.clamp(kk, 1, nz)]
						return if v == -math.huge then h.base else v
					end
					local slope = math.max(math.abs(at(i + 1, k) - at(i - 1, k)), math.abs(at(i, k + 1) - at(i, k - 1))) / 8
					local x, z = x0 + (i - 0.5) * 4, z0 + (k - 0.5) * 4
					local surface = landAt(h, x, z, top - h.base, slope)
					for j = 1, ny do
						local bottom = y0 + (j - 1) * 4
						local fill = math.clamp((top - bottom) / 4, 0, 1)
						if fill > oRow[j][k] then
							oRow[j][k] = fill
							mRow[j][k] = if top - bottom > 10 then Enum.Material.Ground else surface
						end
					end
				end
			end
		end
		terrain:WriteVoxels(region, 4, materials, occupancy)
		table.insert(filled, { cf = CFrame.new((low + high) / 2), size = high - low + Vector3.new(4, 4, 4) })
		task.wait()
	end
end

local function stBrigids(parent: Instance, ground: Vector3, facing: Vector3)
	-- The church on its hill: a nave, a tower and a spire, the colour of old stone.
	local cf = CFrame.lookAt(ground, ground + facing)
	part(parent, "ChurchNave", Vector3.new(10, 9, 22), cf * CFrame.new(0, 4.5, 0), PALETTE.church, Enum.Material.Slate)
	for _, half in ipairs({ -1, 1 }) do
		wedge(parent, "ChurchRoof", Vector3.new(22, 5, 5.5),
			cf * CFrame.new(half * 2.75, 11.5, 0) * CFrame.Angles(0, half * math.pi / 2, 0), PALETTE.slate, Enum.Material.Slate)
	end
	part(parent, "ChurchTower", Vector3.new(7, 18, 7), cf * CFrame.new(0, 9, -13), PALETTE.church, Enum.Material.Slate)
	-- The spire: four slopes meeting at its point.
	for _, a in ipairs({ 0, math.pi / 2, math.pi, -math.pi / 2 }) do
		wedge(parent, "ChurchSpire", Vector3.new(7, 14, 3.5),
			cf * CFrame.new(0, 25, -13) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -1.75), PALETTE.slate, Enum.Material.Slate)
	end
end

local function decoTower(parent: Instance, ground: Vector3)
	-- The Deco tower over the town, its top out of the mist: stepped, cream, a lantern at the top.
	for k, size in ipairs({ Vector3.new(16, 30, 16), Vector3.new(12, 22, 12), Vector3.new(8, 14, 8) }) do
		local below = 0
		if k == 2 then
			below = 30
		elseif k == 3 then
			below = 52
		end
		part(parent, "DecoTower", size, CFrame.new(ground + Vector3.new(0, below + size.Y / 2, 0)), PALETTE.tower,
			Enum.Material.Concrete)
	end
	part(parent, "DecoLantern", Vector3.new(4, 4, 4), CFrame.new(ground + Vector3.new(0, 68, 0)), PALETTE.brass,
		Enum.Material.Metal)
end

-- ===== WHAT BOOTSTRAP CALLS =====

-- Builds it all at the route's end (`finish`, its walkable top at the end of the last chunk, facing on), round the
-- route's centre (`centre`), above the kill plane (`killY`), under `parent`; `onArrive` is called once a player for the
-- first one to open the front door.
function HillHouseService.start(finish: CFrame, parent: Instance, centre: Vector3, killY: number, onArrive: (Player) -> ())
	HillHouseService.stop()
	local model = Instance.new("Model")
	model.Name = "HillHouse"
	model.Parent = parent
	built = model

	local P = finish.Position
	local T = flat(finish.LookVector)
	local out = flat(P - centre)
	local routeR = Vector3.new(P.X - centre.X, 0, P.Z - centre.Z).Magnitude
	local topY = P.Y + RISE

	-- THE CRAG'S PLACE: out from the route and a little ahead, then pushed further out until its nearest edge is CLEAR
	-- outside the route's circle.
	local C = P + out * (CLEAR + CRAG_R + 8) + T * AHEAD
	for _ = 1, 40 do
		local fromCentre = Vector3.new(C.X - centre.X, 0, C.Z - centre.Z).Magnitude
		if fromCentre - CRAG_R >= routeR + CLEAR then
			break
		end
		C += out * 2
	end
	C = Vector3.new(C.X, topY, C.Z)
	model:SetAttribute("CragCentre", C)
	model:SetAttribute("CragRadius", CRAG_R)

	-- THE CRAG, terrain: its body of rock from deep in the mist to just under the top, a skin of ground, and the grass
	-- on the top; rocks standing out of its sides on the far side from the route only.
	local bottom = killY - CRAG_DEEP
	local body = topY - 6 - bottom
	fillCylinder(CFrame.new(C.X, bottom + body / 2, C.Z), body, CRAG_R - 2, Enum.Material.Rock)
	fillCylinder(CFrame.new(C.X, topY - 4.5, C.Z), 3, CRAG_R, Enum.Material.Ground)
	fillCylinder(CFrame.new(C.X, topY - 1.5, C.Z), 3, CRAG_R, Enum.Material.Grass)
	local rng = Random.new(math.floor(P.X * 7 + P.Z * 13) % 100000)
	for _ = 1, 12 do
		local a = rng:NextNumber(-1.2, 1.2)
		local dir = (out * math.cos(a) + Vector3.yAxis:Cross(out) * math.sin(a)).Unit
		local y = rng:NextNumber(bottom + 30, topY - 14)
		fillBall(Vector3.new(C.X, y, C.Z) + dir * (CRAG_R - 6), rng:NextNumber(8, 14),
			if rng:NextNumber() < 0.6 then Enum.Material.Rock else Enum.Material.Slate)
	end

	-- THE LANDING at the route's end, flush with the last chunk, as every level's end is. NO LEGS DOWN TO THE MIST: the
	-- spiral passes under this spot once a turn, and a leg would go through the chunks below. It is held by the last
	-- chunk at one side and the footbridge, braced off the crag, at the other.
	local landing = CFrame.lookAt(P, P + T) * CFrame.new(0, -LANDING.Y / 2, -LANDING.Z / 2)
	part(model, "Landing", LANDING, landing, PALETTE.stone, Enum.Material.Concrete, true)

	-- THE FOOTBRIDGE, from the landing to the top: planks between two rails on posts.
	local landingMid = landing.Position
	local toward = flat(C - landingMid)
	local startAt = landingMid + toward * (math.min(LANDING.X, LANDING.Z) / 2 - 0.5)
	startAt = Vector3.new(startAt.X, P.Y, startAt.Z)
	local endAt = Vector3.new(C.X, topY, C.Z) - toward * (CRAG_R - 3)
	local span = (endAt - startAt)
	local spanCF = CFrame.lookAt((startAt + endAt) / 2, endAt)
	part(model, "Footbridge", Vector3.new(BRIDGE_WIDE, 0.6, span.Magnitude), spanCF * CFrame.new(0, -0.3, 0), PALETTE.timber,
		Enum.Material.WoodPlanks, true)
	model:SetAttribute("BridgeFrom", startAt)
	model:SetAttribute("BridgeTo", endAt)
	local posts = math.max(2, math.floor(span.Magnitude / 4))
	for _, s in ipairs({ -1, 1 }) do
		for k = 0, posts do
			local along = -span.Magnitude / 2 + k * span.Magnitude / posts
			part(model, "BridgePost", Vector3.new(0.4, 3.4, 0.4), spanCF * CFrame.new(s * (BRIDGE_WIDE / 2 - 0.2), 1.7, along),
				PALETTE.timber, Enum.Material.Wood)
		end
		-- The handrail, and an unseen wall under it the height of the rail so nobody steps off the side.
		part(model, "BridgeRail", Vector3.new(0.3, 0.3, span.Magnitude), spanCF * CFrame.new(s * (BRIDGE_WIDE / 2 - 0.2), 3.3, 0),
			PALETTE.timber, Enum.Material.Wood)
		local guard = part(model, "BridgeGuard", Vector3.new(0.4, 3.4, span.Magnitude),
			spanCF * CFrame.new(s * (BRIDGE_WIDE / 2 - 0.2), 1.7, 0), PALETTE.timber, Enum.Material.Wood, true)
		guard.Transparency = 1
	end
	-- TWO BRACES under it, from the rock of the crag's face up to its middle: what carries it, on the crag's side of the
	-- route (never down through the spiral).
	for _, s in ipairs({ -1, 1 }) do
		local foot = endAt + toward * 1 + spanCF.RightVector * s * (BRIDGE_WIDE / 2 - 0.6) - Vector3.new(0, 9, 0)
		local head = spanCF.Position + spanCF.RightVector * s * (BRIDGE_WIDE / 2 - 0.6) - Vector3.new(0, 0.7, 0)
		part(model, "BridgeBrace", Vector3.new(0.8, 0.8, (head - foot).Magnitude), CFrame.lookAt((foot + head) / 2, head),
			PALETTE.timber, Enum.Material.Wood)
	end

	-- THE GARDEN on the top: the fence and its gate where the bridge comes in, the house facing the bridge, the path to
	-- the door through lamb's ear, an apple tree, and a bench looking out to sea.
	local garden = Instance.new("Folder")
	garden.Name = "Garden"
	garden.Parent = model
	local top = Vector3.new(C.X, topY, C.Z)
	picketFence(garden, top, CRAG_R - 1.5, topY, endAt)
	local inward = flat(top - endAt) -- from the gate toward the middle
	local across = Vector3.yAxis:Cross(inward)
	-- THE HOUSE, its front wall's foot four studs past the middle, facing the gate; it goes back from there.
	local frontMid = top + inward * 4
	local door, hall = buildHouse(model, CFrame.lookAt(frontMid, frontMid - inward))
	-- NO GRASS IN THE HOUSE (the hundred-and-eighteenth pass, from your test): Roblox grows its terrain grass blades up
	-- through anything standing on the grass, the hall's floor included. Under the house and the path to its door the
	-- top of the crag is bare ground, which grows nothing.
	local houseMid = frontMid + inward * (HOUSE_D / 2)
	fillBlock(CFrame.lookAt(houseMid - Vector3.new(0, 1.5, 0), houseMid - Vector3.new(0, 1.5, 0) + inward),
		Vector3.new(HOUSE_W + 4, 3, HOUSE_D + 4), Enum.Material.Ground)
	bareGround(houseMid, inward, HOUSE_W + 2, HOUSE_D + 2)
	-- NO GROUND IN THE HALL EITHER (the two-hundred-and-twelfth pass): the crag's top is lumpy, and its ground stood up
	-- through the hall's boards (to 0.7 over them), so the hall's floor looked like earth. Inside the walls, from two
	-- studs under the house's foot (a full cell of ground just under the boards still rendered up through them) to its
	-- ceiling, there is no terrain at all. The plinth hides the hollow under the boards.
	local hollow = houseMid + Vector3.new(0, (STOREY - 2) / 2, 0)
	workspace.Terrain:FillBlock(CFrame.lookAt(hollow, hollow + inward), Vector3.new(HOUSE_W - 2, STOREY + 2, HOUSE_D - 2),
		Enum.Material.Air)
	-- WHERE THINGS ARE IN THE HALL, for the scene (HillHouseClient) and for check_shots.
	model:SetAttribute("HallSpot", hall.spot)
	model:SetAttribute("HallKey", hall.keyAt)
	model:SetAttribute("ClockFace", hall.clockFace)
	model:SetAttribute("ClockFacing", hall.clockFacing)
	model:SetAttribute("PendulumPivot", hall.pivot)
	model:SetAttribute("HallBack", hall.back)
	model:SetAttribute("HallDoor", hall.door)
	model:SetAttribute("HallBox", hall.box)
	model:SetAttribute("HallSize", hall.boxSize)
	-- Its name on the gatepost, facing whoever comes over the bridge.
	local post = top - inward * (CRAG_R - 1.5) + across * 3.2 + Vector3.new(0, 3.4, 0)
	local plateAt = post - inward * 0.45
	nameplate(garden, CFrame.lookAt(plateAt, plateAt - inward))
	-- THE PATH: stepping stones from the gate to the step, with the lamb's ear either side, on bare ground (the grass
	-- came up through the stones).
	local pathLong = ((frontMid - inward * 2.6) - endAt).Magnitude
	local pathMid = endAt + inward * (pathLong / 2)
	fillBlock(CFrame.lookAt(pathMid - Vector3.new(0, 1.5, 0), pathMid - Vector3.new(0, 1.5, 0) + inward),
		Vector3.new(4.5, 3, pathLong + 3), Enum.Material.Ground)
	bareGround(pathMid, inward, 4.5, pathLong + 3)
	local stones = math.floor(pathLong / 2.6)
	for k = 0, stones do
		local at = endAt + inward * (k * pathLong / math.max(1, stones))
		part(garden, "PathStone", Vector3.new(3, 0.2, 2), CFrame.lookAt(at + Vector3.new(0, 0.1, 0), at + Vector3.new(0, 0.1, 0) + inward)
			* CFrame.Angles(0, (k % 2) * 0.08 - 0.04, 0), PALETTE.stone, Enum.Material.Slate, true)
		for _, s in ipairs({ -1, 1 }) do
			ball(garden, "LambsEar", 1.6, at + across * s * 2.6 + Vector3.new(0, 0.4, 0), PALETTE.leaf, Enum.Material.Fabric)
		end
	end
	appleTree(garden, top - across * 20 + inward * 2)
	bench(garden, top + across * 22 - inward * 4, out)
	dressGarden(garden, top, inward, across)
	people(model, garden, landing, out, endAt, inward, across, topY)

	-- THE FAR THINGS, out of the mist: St Brigid's on its hill, and the Deco tower over the town, toward the sea.
	local seaward = out
	mistSheets(model, Vector3.new(centre.X, 0, centre.Z), killY + MIST_OVER_KILL)
	local churchAt = top + seaward * 520 + Vector3.yAxis:Cross(seaward) * 260
	churchAt = Vector3.new(churchAt.X, killY + MIST_OVER_KILL + 18, churchAt.Z)
	local towerAt = top + seaward * 640 - Vector3.yAxis:Cross(seaward) * 180
	decoTower(model, Vector3.new(towerAt.X, killY + MIST_OVER_KILL - 40, towerAt.Z))
	-- THE COUNTRY ROUND IT (passes 241 and 270): St Brigid's hill and hills all the way round, far off and the haze
	-- taking the further ones, out of the mist so the mist is over a country and not a floor; each with a wood on it.
	-- Laid by a fixed seed, the same every run, kept clear of the route (inside 700 studs of its middle) and of the
	-- church and the tower; made of terrain (THE COUNTRY OUT OF THE MIST, above) in the background, the woods set on
	-- the ground it makes. The church's hill first, and the church on its level crown.
	local mistY = killY + MIST_OVER_KILL
	local hills: { Hill } = {}
	local churchGround = churchAt.Y + 18
	-- (Seen in play: the feet of the hills showed a thin lip at the mist's top, so they stand 16 down in it; and the
	-- church's crown was 3 studs over its floor.)
	local foot = mistY - 16
	table.insert(hills, { cx = churchAt.X, cz = churchAt.Z, base = foot, radius = 96, rise = churchGround - foot + 6,
		seed = 7.3, along = seaward, stretch = 0.8, flat = churchGround - foot - 3 })
	stBrigids(model, Vector3.new(churchAt.X, churchGround, churchAt.Z), -seaward)
	do
		local rng = Random.new(1979)
		local count = 14
		for index = 1, count do
			local a = (index + rng:NextNumber(-0.3, 0.3)) / count * math.pi * 2
			local reach = rng:NextNumber(760, 1500)
			local at = Vector3.new(centre.X + math.cos(a) * reach, 0, centre.Z + math.sin(a) * reach)
			local clear = (Vector3.new(at.X, 0, at.Z) - Vector3.new(churchAt.X, 0, churchAt.Z)).Magnitude > 260
				and (Vector3.new(at.X, 0, at.Z) - Vector3.new(towerAt.X, 0, towerAt.Z)).Magnitude > 220
			if clear then
				local radius = rng:NextNumber(110, 240) * reach / 1100
				local turn = rng:NextNumber(0, math.pi)
				table.insert(hills, { cx = at.X, cz = at.Z, base = foot, radius = radius * 1.25,
					rise = radius * rng:NextNumber(0.32, 0.55) + 10, seed = index * 1.37 + 0.5,
					along = Vector3.new(math.cos(turn), 0, math.sin(turn)), stretch = rng:NextNumber(0.45, 0.75) })
			end
		end
	end
	-- THE FAR RANGES (pass 271): long blue ridges much further out, lost in the haze, so the country goes on past the
	-- hills to the edge of seeing. Moor and rock, no woods, no fields.
	do
		local rng = Random.new(1981)
		for index = 1, 5 do
			local a = (index + rng:NextNumber(-0.25, 0.25)) / 5 * math.pi * 2 + 0.4
			local reach = rng:NextNumber(2100, 2600)
			local turn = a + math.pi / 2 + rng:NextNumber(-0.3, 0.3)
			table.insert(hills, { cx = centre.X + math.cos(a) * reach, cz = centre.Z + math.sin(a) * reach, base = foot,
				radius = rng:NextNumber(380, 480), rise = rng:NextNumber(100, 150), seed = 40 + index * 2.3,
				along = Vector3.new(math.cos(turn), 0, math.sin(turn)), stretch = rng:NextNumber(0.28, 0.4), far = true })
		end
	end
	-- A TOR: a heap of rounded rock on a hill's crest, sunk into it. A FARMHOUSE: white walls, a slate roof and a
	-- chimney, on a gentle shoulder, its long side to the slope.
	local function tor(hill: Hill, rng: Random)
		local best, bx, bz = -1, hill.cx, hill.cz
		for _ = 1, 24 do
			local r = hill.radius * rng:NextNumber(0, 0.5)
			local t = rng:NextNumber(0, math.pi * 2)
			local x, z = hill.cx + math.cos(t) * r, hill.cz + math.sin(t) * r
			local height = hillHeight(hill, x, z)
			if height > best then
				best, bx, bz = height, x, z
			end
		end
		if best < 20 then
			return
		end
		local size = hill.radius / 12
		for _ = 1, rng:NextInteger(3, 5) do
			local off = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * size
			local radius = size * rng:NextNumber(0.45, 0.8)
			fillBall(Vector3.new(bx, hill.base + best - radius * 0.35, bz) + off, radius,
				if rng:NextNumber() < 0.5 then Enum.Material.Rock else Enum.Material.Slate)
		end
	end
	local function farmhouse(hill: Hill, rng: Random)
		for _ = 1, 20 do
			local r = hill.radius * rng:NextNumber(0.35, 0.7)
			local t = rng:NextNumber(0, math.pi * 2)
			local x, z = hill.cx + math.cos(t) * r, hill.cz + math.sin(t) * r
			local height = hillHeight(hill, x, z)
			local ahead = hillHeight(hill, x + 6, z)
			local side = hillHeight(hill, x, z + 6)
			if height > 10 and math.abs(ahead - height) < 3 and math.abs(side - height) < 3 then
				local scale = hill.radius / 110
				local ground = hill.base + height - 1
				local cf = CFrame.new(x, ground, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
				local w, d, tall = 16 * scale, 7 * scale, 6 * scale
				part(model, "FarHouse", Vector3.new(w, tall, d), cf * CFrame.new(0, tall / 2, 0), Color3.fromRGB(236, 232, 222),
					Enum.Material.Plaster).CastShadow = false
				for _, half in ipairs({ -1, 1 }) do
					wedge(model, "FarHouseRoof", Vector3.new(w + 0.6 * scale, 3.2 * scale, d / 2 + 0.3 * scale),
						cf * CFrame.new(0, tall + 1.6 * scale, half * (d / 4 + 0.15 * scale)) * CFrame.Angles(0, if half > 0 then math.pi else 0, 0),
						PALETTE.slate, Enum.Material.Slate).CastShadow = false
				end
				part(model, "FarHouseChimney", Vector3.new(1.4 * scale, 3 * scale, 1.4 * scale),
					cf * CFrame.new(w * 0.38, tall + 3 * scale, 0), Color3.fromRGB(150, 120, 104), Enum.Material.Brick).CastShadow = false
				return
			end
		end
	end
	task.spawn(function()
		local rng = Random.new(1980)
		for index, hill in ipairs(hills) do
			if not (model.Parent and built == model) then
				return
			end
			local ok, err = pcall(writeHill, hill, function(): boolean
				return model.Parent ~= nil and built == model
			end)
			if not ok then
				warn("HillHouseService: a far hill: " .. tostring(err))
			end
			if index > 1 and not hill.far and model.Parent and built == model then
				if index % 2 == 0 then
					pcall(tor, hill, rng)
				end
				if index % 3 ~= 1 then
					pcall(farmhouse, hill, rng)
				end
			end
			-- A wood on it (not on the church's crown): canopy clumps on its upper slopes, set into the ground they stand
			-- on, so none floats; darker and lighter greens.
			if index > 1 and not hill.far and model.Parent then
				for _ = 1, rng:NextInteger(5, 9) do
					local r = hill.radius * rng:NextNumber(0.05, 0.5)
					local t = rng:NextNumber(0, math.pi * 2)
					local x, z = hill.cx + math.cos(t) * r, hill.cz + math.sin(t) * r * hill.stretch
					local height = hillHeight(hill, x, z)
					if height > 8 then
						local size = rng:NextNumber(18, 34) * hill.radius / 220
						for _ = 1, 3 do
							local off = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * size * 0.5
							local s = size * rng:NextNumber(0.6, 1)
							local tree = ball(model, "FarWood", s, Vector3.new(x, hill.base + height + s * 0.22, z) + off,
								PALETTE.canopy:Lerp(Color3.fromRGB(56, 90, 54), rng:NextNumber(0, 0.8)), Enum.Material.LeafyGrass)
							tree.CastShadow = false
						end
					end
				end
			end
		end
	end)

	-- THE DOOR: "Go in". The first time anyone opens it, it swings in, and stays open.
	local hinge = model:FindFirstChild("DoorHinge", true)
	local open = Instance.new("ProximityPrompt")
	open.Name = "HouseDoorPrompt"
	open.ActionText = "Go in"
	open.ObjectText = "Hill House"
	open.HoldDuration = 0.4
	open.MaxActivationDistance = 9
	open.RequiresLineOfSight = false
	open.Parent = door
	prompt = open
	open.Triggered:Connect(function(_player: Player)
		if hinge and hinge:IsA("BasePart") and door:GetAttribute("Swung") == nil then
			door:SetAttribute("Swung", true)
			-- INWARD: a negative turn takes the door's free edge from across the opening toward the hall (+Z).
			local turn = hinge.CFrame * CFrame.Angles(0, math.rad(-100), 0)
			local offset = hinge.CFrame:Inverse() * door.CFrame
			local value = Instance.new("CFrameValue")
			value.Value = hinge.CFrame
			value.Changed:Connect(function(cf: CFrame)
				door.CFrame = cf * offset
			end)
			TweenService:Create(value, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = turn }):Play()
			task.delay(1.4, function()
				value:Destroy()
			end)
			open.Enabled = false
		end
	end)

	-- THE KEY: "Take the key", the end of the level. Stood in front of its hook (the scene is shot from there), the
	-- scene played on your screen, and the level finished once its clock shot is on (the return waits for the scene).
	local take = Instance.new("ProximityPrompt")
	take.Name = "HallKeyPrompt"
	take.ActionText = "Take the key"
	take.ObjectText = "His key"
	take.HoldDuration = 0.6
	take.MaxActivationDistance = 6
	take.RequiresLineOfSight = false
	take.Parent = hall.key
	takePrompt = take
	take.Triggered:Connect(function(player: Player)
		if arrived[player] then
			return
		end
		arrived[player] = true
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.CFrame = hall.spot
			root.AssemblyLinearVelocity = Vector3.zero
		end
		local folder = ReplicatedStorage:FindFirstChild("RemoteEvents")
		local scene = folder and folder:FindFirstChild("HillScene")
		if scene and scene:IsA("RemoteEvent") then
			scene:FireClient(player, "key", model)
		end
		task.delay(KEY_ARRIVE, function()
			if player.Parent then
				onArrive(player)
			end
		end)
	end)
end

function HillHouseService.stop()
	if prompt then
		prompt:Destroy()
		prompt = nil
	end
	if takePrompt then
		takePrompt:Destroy()
		takePrompt = nil
	end
	if built then
		built:Destroy()
		built = nil
	end
	table.clear(arrived)
	clearTerrain()
end

HillHouseService.STAMP = "2358394c"
return HillHouseService
