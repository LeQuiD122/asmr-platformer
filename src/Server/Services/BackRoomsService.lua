--!strict
-- ServerScriptService/Services/BackRoomsService.lua
-- The back rooms of the Corporation Baths: where you go after falling too many times in one run.
--
-- === What it is ===
--
-- "Backrooms? It is the back rooms of the baths, dear. Staff only." (Mrs Venn, LORE.md.) Fall enough times in one
-- run (Bootstrap's BACKROOMS_FALLS) and the last fall goes through the floor instead of back to the route: you are
-- standing in yellow rooms under a low ceiling of humming tube lights, on damp carpet, and the only way out is a
-- door marked WAY OUT at the far end. Never announced anywhere; it has to be found. Once a run.
--
-- === How it is built ===
--
-- From MAP below, one character a tile (TILE studs): `#` wall, `.` floor, `S` where you arrive, `D` the way out (in
-- the outer wall), `L` a locked staff door (a wall with a door on its open side), `x` the floor of a room nobody can
-- get into. One carpet floor under all of it, one ceiling over all of it resting on the walls, the walls a slab per
-- run of `#` in a row from floor to ceiling. Lights: a tube panel set into the ceiling over every floor tile whose
-- x and y are both 2 more than a multiple of 3, each a real SurfaceLight shining down (no glowing parts): every
-- floor tile is within three tiles of one (blender/check_backrooms.py). One of them stutters now and then. The
-- hum is the baths' own (AmbienceService plays BathsHum while InLevel is "backRooms").
--
-- Built once, at server start, far from everything else, and never moved. Bootstrap sends players in (arrival)
-- and takes them out (the door's prompt calls the exit it was given).

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Style"))

local BackRoomsService = {}

local ORIGIN = Vector3.new(-9000, 600, -9000) -- the map's corner (x, z) and the carpet's top (y)
local TILE = 4
local HEIGHT = 10 -- carpet to ceiling
local DOOR_HEIGHT = 7.5

-- BIGGER (the two-hundred-and-twenty-fifth pass, "you could make the backrooms bigger"): the old rooms are the
-- top left now; east of them a hall of square pillars, south of them a wing of offices and long corridors, and the way
-- out moved to the far corner of that wing.
local MAP = {
	"######################################################",
	"#S......#............#...........#...................#",
	"#.......#............#...............................#",
	"#.......#....##......#....####...#..##....##....##...#",
	"#............##...........#..#......##....##....##...#",
	"#.......#............#....#..#...#...................#",
	"####.####............##.###..##.##...................#",
	"#...........######..................##....##....##...#",
	"#...........#....#..................##....##....##...#",
	"#...##......#....#....#######....#...................#",
	"#...##......#........##xxxxx##...#...................#",
	"#...........#....#...Lxxxxxxx#...#..##....##....##...#",
	"###.#####.#########..#xxxxxxx#..#######.######.#######",
	"#.......#............##xxxxx##...#.....#......#......#",
	"#.......#.............#######..........#......#......#",
	"#..##...#...##.........................#.............#",
	"#..##.......##...#######.###.#######.###......#......#",
	"#.......#........#.........#.....#.....#......####.###",
	"#.......#........#.........#...........#.............#",
	"####.######......#....##...#.....#...........#.......#",
	"#................#....##...............#.....#.......#",
	"####.#######.#######.#########.#####.#########.###.###",
	"#......#..........#.........#........#.......#.......#",
	"#......#..........#.........#........#.......#.......#",
	"#......####.#######....##...####.#####...##..#.......#",
	"#....................................................#",
	"#..##.......................##.............##........#",
	"#..##....#######.#####......##.....#######.....#####.#",
	"#........#...........#.............#.....#.........#.#",
	"####.#####...........#....#######..#.....#.........#.#",
	"#........#....##.....#....#.....#..#.....######.####.#",
	"#........#....##..........#.....#........#...........#",
	"#.................................#......#...........D",
	"#..##....#...........#....#.....#.....#..#....##.....#",
	"#..##....#...........#....#.....#.....#..#....##.....#",
	"######################################################",
}

-- The palette of the lobby's own back door (HubService.buildBackDoor), so the two are one place.
local WALL = Color3.fromRGB(206, 186, 96)
local CARPET = Color3.fromRGB(126, 112, 74)
local CEILING = Color3.fromRGB(222, 214, 178)
local PANEL = Color3.fromRGB(248, 244, 226)
local TUBE = Color3.fromRGB(255, 241, 196)
local DOOR = Color3.fromRGB(96, 84, 58)
local LIGHT_BRIGHTNESS = 0.9
local LIGHT_RANGE = 16

local folder: Folder? = nil
local arrivalAt: CFrame? = nil
local noticePlate: BasePart? = nil
local exitHandler: ((Player) -> ())? = nil
-- THE WAY BACK (the hundred-and-third pass): the door behind where you arrive, for someone who came in by the lobby's
-- corridor (their BackRoomsFrom is "lobby"; Bootstrap's handler takes them back to it).
local returnHandler: ((Player) -> ())? = nil
local GRID = Color3.fromRGB(232, 226, 200) -- the ceiling's T-bars
local SKIRTING = Color3.fromRGB(104, 84, 52)
local DAMP = Color3.fromRGB(150, 128, 62)

-- The world position of a tile's centre, at height `up` above the carpet.
local function tileAt(x: number, y: number, up: number): Vector3
	return ORIGIN + Vector3.new((x + 0.5) * TILE, up, (y + 0.5) * TILE)
end

local function charAt(x: number, y: number): string
	local row = MAP[y + 1]
	if not row or x < 0 or x >= #row then
		return "#"
	end
	return string.sub(row, x + 1, x + 1)
end

-- A WALL TILE, `#` or the locked door's `L` (which is wall behind its door).
local function solid(c: string): boolean
	return c == "#" or c == "L"
end

local function part(name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material, parent: Instance): Part
	local made = Instance.new("Part")
	made.Name = name
	made.Anchored = true
	made.Size = size
	made.CFrame = cf
	made.Color = colour
	made.Material = material
	made.TopSurface = Enum.SurfaceType.Smooth
	made.BottomSurface = Enum.SurfaceType.Smooth
	made.Parent = parent
	return made
end

-- A sign: a plate on a wall with words on it (SurfaceGui), facing `facing` (a flat unit vector out of the wall).
local function sign(name: string, at: Vector3, facing: Vector3, size: Vector2, words: string, colour: Color3,
	ink: Color3, parent: Instance): Part
	local plate = part(name, Vector3.new(size.X, size.Y, 0.2), CFrame.lookAt(at, at + facing), colour,
		Enum.Material.SmoothPlastic, parent)
	plate.CanCollide = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.Parent = plate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = ink
	label.TextScaled = true
	label.TextWrapped = true
	label.FontFace = Style.WORLD.plain
	label.Text = words
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	return plate
end

-- Where a player arrives: the S tile, facing along the room.
function BackRoomsService.arrival(): CFrame
	return arrivalAt or CFrame.new(ORIGIN + Vector3.new(TILE * 1.5, 3, TILE * 1.5))
end

-- THE SECRET'S SHOT (Interactables.reveal, the first time a save finds the back rooms): from a little way into the
-- room, the camera on Mrs Venn's notice.
function BackRoomsService.secretShot(): (CFrame?, Vector3?, BasePart?)
	local plate = noticePlate
	if not (plate and plate.Parent) then
		return nil, nil, nil
	end
	local focus = plate.Position
	local eye = CFrame.lookAt(focus + plate.CFrame.LookVector * 9 + Vector3.new(1.5, -0.6, 0), focus)
	return eye, focus, plate
end

-- FLUFF (pass 268, from your notes: "a secret pet that can be found somewhere in the back rooms"). In the far corner of
-- the bottom-left room, low in the west wall, a mouse hole in the skirting with a faint warm light inside it, and a dust
-- bunny peeking out of it, breathing. Hold to pick it up: the first time, it is yours (Bootstrap hands it to
-- EconomyService.foundDustBunny, through setDustHandler). Never pointed to anywhere; the shop only says it is hiding.
local DUST = { x = 1, y = 33 } -- the tile in front of the hole; the hole is in that tile's west wall
local dustHandler: ((Player) -> ())? = nil
function BackRoomsService.setDustHandler(fn: (Player) -> ())
	dustHandler = fn
end

local function buildDust(made: Instance)
	local floor = tileAt(DUST.x, DUST.y, 0)
	local face = floor - Vector3.new(TILE / 2, 0, 0) -- the wall's face, the room to its +X
	local out = Vector3.new(1, 0, 0)
	local function flat(name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material): Part
		local p = part(name, size, cf, colour, material, made)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		return p
	end
	-- The hole: an arch of dark, a lintel of skirting over it, and a crumb of plaster on the carpet.
	local holeAt = CFrame.lookAt(face + out * 0.02, face + out * 2)
	flat("MouseHole", Vector3.new(1.7, 1.0, 0.04), holeAt * CFrame.new(0, 0.5, 0), Color3.fromRGB(14, 10, 8),
		Enum.Material.SmoothPlastic)
	local arch = flat("MouseHoleArch", Vector3.new(0.04, 1.7, 1.7), holeAt * CFrame.new(0, 1.0, 0) * CFrame.Angles(0, math.pi / 2, 0),
		Color3.fromRGB(14, 10, 8), Enum.Material.SmoothPlastic)
	arch.Shape = Enum.PartType.Cylinder
	for k, at in ipairs({ Vector3.new(0.35, 0.03, 1.15), Vector3.new(0.6, 0.03, -1.05), Vector3.new(0.25, 0.03, 1.5) }) do
		flat("MouseHoleCrumb", Vector3.new(0.18 + 0.05 * k, 0.06, 0.14 + 0.04 * k), CFrame.new(face + at), WALL, Enum.Material.Plaster)
	end
	local glowHost = flat("MouseHoleGlow", Vector3.new(0.2, 0.2, 0.2), CFrame.new(face - out * 0.3 + Vector3.new(0, 0.5, 0)), WALL,
		Enum.Material.SmoothPlastic)
	glowHost.Transparency = 1
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 214, 160)
	glow.Brightness = 0.45
	glow.Range = 5
	glow.Shadows = false
	glow.Parent = glowHost
	-- The bunny, peeking out (Assets.Cosmetics.Pal_Dust, the pal itself, a little smaller), its face to the room.
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local cosmetics = assets and assets:FindFirstChild("Cosmetics")
	local found = cosmetics and cosmetics:FindFirstChild("Pal_Dust")
	local template = if found and found:IsA("BasePart") then found elseif found then found:FindFirstChildWhichIsA("BasePart", true) else nil
	local host: BasePart
	if template then
		local bunny = template:Clone() :: BasePart
		bunny.Name = "DustBunny"
		bunny.Size = template.Size * (1.15 / template.Size.Y)
		bunny.Anchored = true
		bunny.CanCollide = false
		bunny.CanTouch = false
		bunny.CanQuery = true
		bunny.Parent = made
		host = bunny
	else
		-- (Without the model: a grey fluff ball.)
		host = part("DustBunny", Vector3.new(0.9, 0.9, 0.9), CFrame.new(), Color3.fromRGB(196, 196, 206), Enum.Material.Fabric, made)
		host.Shape = Enum.PartType.Ball
		host.CanCollide = false
	end
	local rest = CFrame.lookAt(face + out * 0.75 + Vector3.new(0, host.Size.Y / 2, 0), face + out * 3 + Vector3.new(0, host.Size.Y / 2, 0))
	host.CFrame = rest
	local hush = game:GetService("SoundService"):FindFirstChild("MaterialSounds")
	local squeak = hush and hush:FindFirstChild("cloudHush_2")
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DustPrompt"
	prompt.ActionText = "Pick up"
	prompt.ObjectText = "A dust bunny"
	prompt.HoldDuration = 0.8
	prompt.MaxActivationDistance = 7
	prompt.RequiresLineOfSight = false
	prompt.Parent = host
	prompt.Triggered:Connect(function(player: Player)
		if squeak and squeak:IsA("Sound") then
			local s = squeak:Clone()
			s.Volume = 0.6
			s.PlaybackSpeed = 1.25
			s.Parent = host
			s:Play()
			game:GetService("Debris"):AddItem(s, 3)
		end
		local give = dustHandler
		if give then
			local ok, err = pcall(give, player)
			if not ok then
				warn("BackRoomsService: Fluff: " .. tostring(err))
			end
		end
	end)
	-- Breathing, and now and then a little twitch toward the room.
	task.spawn(function()
		while host.Parent do
			local t = os.clock()
			local breath = 1 + 0.035 * math.sin(t * 2.3)
			local peek = math.max(0, math.sin(t * 0.37)) ^ 8 * 0.18
			host.CFrame = rest * CFrame.new(0, (breath - 1) * host.Size.Y * 0.5, -peek) * CFrame.Angles(0, 0.15 * math.sin(t * 0.6), 0)
			task.wait(0.05)
		end
	end)
end

function BackRoomsService.isBuilt(): boolean
	return folder ~= nil and (folder :: Folder).Parent ~= nil
end

-- ===== THINGS THE HOLD HAS KEPT, IN THE WALLS =====
--
-- Things from up there (a lifebuoy, a deckchair, a pool ladder, a locker, a bench, a slab of honey, a parasol, a buoy,
-- the keepsakes), half sunk into the walls, the carpet and the ceiling as if the rooms had grown round them; and some of
-- them WRONG, the way things are in rooms like these: too tall and thin, too big, pressed flat into the wall, the same
-- thing three times in a row. In nobody's way (they do not collide), and every one held by what it is sunk into.
local SUNK_SEED = 1983
local SUNK_WALLS, SUNK_FLOORS, SUNK_CEILINGS = 24, 13, 9
local WALL_REACH = 2.2 -- studs a thing reaches out of a wall at most: a corridor is a tile (4) across

local function decor(model: Model, name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material?,
	shape: Enum.PartType?): Part
	local p = part(name, size, cf, colour, material or Enum.Material.SmoothPlastic, model)
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Each built standing on its base at the origin, up its +Y: the surface it is sunk into is the plane y = 0.
type Thing = { make: (Model) -> (), tall: number }
local THINGS: { [string]: Thing } = {
	lifebuoy = { tall = 3.4, make = function(m: Model)
		for k = 0, 11 do
			local a = k * math.pi / 6
			decor(m, "Lifebuoy", Vector3.new(0.55, 0.55, 1.0), CFrame.new(math.cos(a) * 1.4, 1.7 + math.sin(a) * 1.4, 0)
				* CFrame.Angles(0, 0, a), if k % 3 == 0 then Color3.fromRGB(200, 70, 60) else Color3.fromRGB(236, 232, 220))
		end
	end },
	deckchair = { tall = 3.0, make = function(m: Model)
		local wood = Color3.fromRGB(150, 116, 80)
		for _, x in ipairs({ -0.9, 0.9 }) do
			decor(m, "ChairRail", Vector3.new(0.15, 3, 0.15), CFrame.new(x, 1.5, 0) * CFrame.Angles(0.45, 0, 0), wood, Enum.Material.Wood)
		end
		for k = 0, 2 do
			decor(m, "ChairCloth", Vector3.new(1.7, 0.9, 0.06), CFrame.new(0, 0.6 + k * 0.9, 0.3 - k * 0.42) * CFrame.Angles(0.45, 0, 0),
				if k % 2 == 0 then Color3.fromRGB(70, 140, 200) else Color3.fromRGB(240, 238, 230), Enum.Material.Fabric)
		end
	end },
	ladder = { tall = 5.0, make = function(m: Model)
		local chrome = Color3.fromRGB(200, 204, 208)
		for _, x in ipairs({ -0.8, 0.8 }) do
			decor(m, "LadderRail", Vector3.new(0.2, 5, 0.2), CFrame.new(x, 2.5, 0), chrome, Enum.Material.Metal)
		end
		for k = 1, 4 do
			decor(m, "LadderRung", Vector3.new(1.6, 0.14, 0.3), CFrame.new(0, k * 1.1, 0), chrome, Enum.Material.Metal)
		end
	end },
	locker = { tall = 6.0, make = function(m: Model)
		local steel = Color3.fromRGB(88, 104, 110)
		decor(m, "SunkLocker", Vector3.new(1.5, 6, 1.4), CFrame.new(0, 3, 0), steel, Enum.Material.DiamondPlate)
		decor(m, "SunkLockerDoor", Vector3.new(1.4, 5.8, 0.1), CFrame.new(0, 3, -0.75), steel, Enum.Material.Metal)
		for k = 0, 3 do
			decor(m, "SunkLockerVent", Vector3.new(0.9, 0.08, 0.04), CFrame.new(0, 5.2 - k * 0.25, -0.82), Color3.fromRGB(30, 34, 36))
		end
	end },
	bench = { tall = 1.8, make = function(m: Model)
		local wood = Color3.fromRGB(124, 96, 70)
		decor(m, "BenchSeat", Vector3.new(5, 0.3, 1.4), CFrame.new(0, 1.6, 0), wood, Enum.Material.Wood)
		for _, x in ipairs({ -2.1, 2.1 }) do
			decor(m, "BenchLeg", Vector3.new(0.3, 1.5, 1.2), CFrame.new(x, 0.75, 0), Color3.fromRGB(60, 62, 66), Enum.Material.Metal)
		end
	end },
	slab = { tall = 1.4, make = function(m: Model)
		local honey = decor(m, "HoneySlab", Vector3.new(5, 1.4, 3.6), CFrame.new(0, 0.7, 0), Color3.fromRGB(226, 160, 40),
			Enum.Material.SmoothPlastic)
		honey.Reflectance = 0.12
		honey.Transparency = 0.12
	end },
	parasol = { tall = 7.0, make = function(m: Model)
		decor(m, "ParasolPole", Vector3.new(0.25, 7, 0.25), CFrame.new(0, 3.5, 0), Color3.fromRGB(236, 232, 220), Enum.Material.Metal)
		for k = 0, 7 do
			local a = k * math.pi / 4
			decor(m, "ParasolCloth", Vector3.new(0.1, 2.6, 1.4), CFrame.new(math.cos(a) * 1.15, 6.6, math.sin(a) * 1.15)
				* CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(-62)),
				if k % 2 == 0 then Color3.fromRGB(236, 120, 150) else Color3.fromRGB(246, 242, 236), Enum.Material.Fabric)
		end
	end },
	buoy = { tall = 3.2, make = function(m: Model)
		decor(m, "BuoyBody", Vector3.new(2.4, 1.8, 1.8), CFrame.new(0, 0.9, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(210, 60, 50), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		decor(m, "BuoyBand", Vector3.new(0.5, 1.84, 1.84), CFrame.new(0, 1.4, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color3.fromRGB(240, 236, 226), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		decor(m, "BuoyMast", Vector3.new(0.2, 1.4, 0.2), CFrame.new(0, 2.5, 0), Color3.fromRGB(60, 62, 66), Enum.Material.Metal)
	end },
}
local THING_NAMES = { "lifebuoy", "deckchair", "ladder", "locker", "bench", "slab", "parasol", "buoy" }

-- WRONG, by a scale in the thing's own axes about its base: stretched tall (sy > 1, thinner to match), giant, or pressed
-- flat. Each part's place scaled from the base, and its size along each of its own axes by how far that axis scales.
local function distort(model: Model, base: CFrame, scale: Vector3)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			local rel = base:ToObjectSpace(item.CFrame)
			local p = rel.Position * scale
			local rot = rel - rel.Position
			local function along(axis: Vector3): number
				return (axis * scale).Magnitude
			end
			item.Size = Vector3.new(item.Size.X * along(rot.RightVector), item.Size.Y * along(rot.UpVector),
				item.Size.Z * along(-rot.LookVector))
			item.CFrame = base * (CFrame.new(p) * rot)
		end
	end
end

-- One thing, at `surface` (its up out of whatever it is sunk into), `sink` of it under, and how it is wrong.
local function sink(made: Instance, name: string, surface: CFrame, sinkShare: number, wrong: string?, rng: Random)
	local thing = THINGS[name]
	local model = Instance.new("Model")
	model.Name = "Sunk_" .. name
	thing.make(model)
	local scale = Vector3.one
	if wrong == "tall" then
		scale = Vector3.new(0.62, 1.9, 0.62)
	elseif wrong == "giant" then
		scale = Vector3.new(2.3, 2.3, 2.3)
	elseif wrong == "flat" then
		scale = Vector3.new(1.4, 0.18, 1.4)
	end
	if scale ~= Vector3.one then
		distort(model, CFrame.identity, scale)
	end
	local tilt = CFrame.Angles(rng:NextNumber(-0.45, 0.45), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.45, 0.45))
	local down = thing.tall * scale.Y * sinkShare
	model:PivotTo(surface * CFrame.new(0, -down, 0) * tilt)
	-- Taken by the room: a little of its colour gone to the walls' yellow.
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Color = item.Color:Lerp(WALL, 0.22)
		end
	end
	model.Parent = made
	return model
end

local function sinkThings(made: Instance)
	local rng = Random.new(SUNK_SEED)
	local rows, cols = #MAP, #MAP[1]
	local walls, floors = {}, {}
	for y = 0, rows - 1 do
		for x = 0, cols - 1 do
			if charAt(x, y) == "." then
				-- Not by where you arrive (the notice's wall), and not in front of the doors.
				local nearDoor = false
				for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					local n = charAt(x + step[1], y + step[2])
					if n == "D" or n == "L" or n == "S" then
						nearDoor = true
					end
				end
				if not nearDoor and (x > 3 or y > 3) then
					table.insert(floors, { x = x, y = y })
					for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
						if charAt(x + step[1], y + step[2]) == "#" then
							table.insert(walls, { x = x, y = y, dx = step[1], dy = step[2] })
						end
					end
				end
			end
		end
	end
	local taken: { Vector3 } = {}
	local function free(at: Vector3, gap: number): boolean
		for _, other in ipairs(taken) do
			if (other - at).Magnitude < gap then
				return false
			end
		end
		return true
	end
	local wrongs = { "tall", "giant", "flat", "repeat" }
	local placed = 0
	-- INTO THE WALLS: up out of the wall face, half in or more.
	for _ = 1, 200 do
		if placed >= SUNK_WALLS or #walls == 0 then
			break
		end
		local w = walls[rng:NextInteger(1, #walls)]
		local out = Vector3.new(-w.dx, 0, -w.dy)
		local face = tileAt(w.x, w.y, rng:NextNumber(1.2, HEIGHT - 3)) + Vector3.new(w.dx, 0, w.dy) * (TILE / 2)
		if free(face, TILE * 3) then
			table.insert(taken, face)
			placed += 1
			local name = THING_NAMES[rng:NextInteger(1, #THING_NAMES)]
			local wrong = if rng:NextNumber() < 0.55 then wrongs[rng:NextInteger(1, #wrongs)] else nil
			-- Out of a wall a thing reaches ACROSS the corridor: never stretched, and giant only if it is small, so
			-- nothing comes out through the wall opposite.
			if wrong == "tall" or (wrong == "giant" and THINGS[name].tall > 2) then
				wrong = "flat"
			end
			local across = Vector3.new(out.Z, 0, -out.X)
			local surface = CFrame.fromMatrix(face, across, out, across:Cross(out))
			if wrong == "repeat" then
				-- THE SAME THING THREE TIMES, in a row along the wall, each sunk exactly as deep.
				for k = -1, 1 do
					sink(made, name, surface + across * (k * 2.6), math.max(0.55, 1 - WALL_REACH / THINGS[name].tall), nil,
						Random.new(SUNK_SEED + placed))
				end
			else
				-- Deep enough that it reaches no more than WALL_REACH out of the wall, however long it is.
				local long = THINGS[name].tall * (if wrong == "giant" then 2.3 elseif wrong == "flat" then 0.18 else 1)
				sink(made, name, surface, math.max(rng:NextNumber(0.4, 0.62), 1 - WALL_REACH / long), wrong, rng)
			end
		end
	end
	-- INTO THE CARPET and OUT OF THE CEILING.
	for _, spec in ipairs({ { SUNK_FLOORS, false }, { SUNK_CEILINGS, true } }) do
		local count, ceiling = spec[1] :: number, spec[2] :: boolean
		local done = 0
		for _ = 1, 200 do
			if done >= count or #floors == 0 then
				break
			end
			local f = floors[rng:NextInteger(1, #floors)]
			local at = tileAt(f.x, f.y, if ceiling then HEIGHT else 0)
			if free(at, TILE * 3) then
				table.insert(taken, at)
				done += 1
				local name = THING_NAMES[rng:NextInteger(1, #THING_NAMES)]
				local wrong = if rng:NextNumber() < 0.45 then wrongs[rng:NextInteger(1, 3)] else nil
				local surface = if ceiling then CFrame.new(at) * CFrame.Angles(math.pi, 0, 0) else CFrame.new(at)
				sink(made, name, surface, rng:NextNumber(0.45, 0.65), wrong, rng)
			end
		end
	end
end

-- ===== WHAT WALKS DOWN HERE =====
--
-- E. MARSH, the faceless one who watches from the Deco tower (LORE.md: the key holder before you, who waited too long
-- for somebody to come and help). Down here he walks. Not at once: now and then soon after you arrive (HUNT_CHANCE, at
-- HUNT_EARLY seconds), and always once you have been lost HUNT_AFTER seconds. Out of the locked STAFF door, toward you
-- by the shortest way through the rooms, a little slower than you walk, stopping now and then to tilt his head; the
-- lights near him stutter. If he reaches you, Bootstrap's `onCaught` has you: the scare, and the lobby. Find the WAY
-- OUT first. One for each player down here, and gone when they leave.
local HUNT_AFTER, HUNT_CHANCE, HUNT_EARLY = 30, 0.35, NumberRange.new(12, 18)
local WALK, WALK_LATE, CATCH = 11.5, 13.5, 3.2
-- IN HIS HANDS (the hundred-and-sixty-seventh pass, from your note of 2026-11-03: "it incorrectly positions the characters
-- in the hands of the monster"): his hands close round whoever stands GRIP studs in front of him (StalkerClient's HOLD is
-- fitted to it), so at the catch he is squared up to you that far off. Written on him for your screen (Grip).
local GRIP = 4.6
type Hunt = { token: number, model: Model?, onCaught: (Player, Vector3) -> () }
local hunts: { [Player]: Hunt } = {}
local tubes: { SurfaceLight } = {}
local staffDoor: BasePart? = nil
local staffDoorRest: CFrame? = nil
local staffTile: { x: number, y: number }? = nil

local function storyRemote(): RemoteEvent?
	local folderOf = game:GetService("ReplicatedStorage"):FindFirstChild("RemoteEvents")
	local event = folderOf and folderOf:FindFirstChild("StoryMoment")
	return if event and event:IsA("RemoteEvent") then event else nil
end

local function tileOf(position: Vector3): (number, number)
	local rel = position - ORIGIN
	return math.floor(rel.X / TILE), math.floor(rel.Z / TILE)
end

local function walkable(x: number, y: number): boolean
	local c = charAt(x, y)
	return c == "." or c == "S"
end

-- The way from one tile to another through the rooms (breadth first), as tile centres; nil if there is none.
local function wayTo(fx: number, fy: number, tx: number, ty: number): { Vector3 }?
	if not (walkable(fx, fy) and walkable(tx, ty)) then
		return nil
	end
	local key = function(x: number, y: number): number
		return y * 1000 + x
	end
	local came: { [number]: number } = { [key(fx, fy)] = -1 }
	local queue = { { fx, fy } }
	local head = 1
	while head <= #queue do
		local cx, cy = queue[head][1], queue[head][2]
		head += 1
		if cx == tx and cy == ty then
			break
		end
		for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			local nx, ny = cx + step[1], cy + step[2]
			if walkable(nx, ny) and came[key(nx, ny)] == nil then
				came[key(nx, ny)] = key(cx, cy)
				table.insert(queue, { nx, ny })
			end
		end
	end
	if came[key(tx, ty)] == nil then
		return nil
	end
	local path = {}
	local at = key(tx, ty)
	while at ~= -1 do
		table.insert(path, 1, tileAt(at % 1000, at // 1000, 0))
		at = came[at]
	end
	return path
end

-- HIM (made worse to look at in the hundred-and-third pass, from your notes: "make the backrooms guy way scarier"):
-- too tall for the rooms, so he goes stooped, his head bowed under the ceiling; too thin, legs like poles; arms that
-- hang past his knees and end in long fingers; a pale head a size too big with no face on it at all, only a seam
-- down the middle of where a face would be (it is not a seam: StoryClient's screamer opens it).
--
-- JOINTED (the hundred-and-twenty-first pass, from your test: "the animation for the monster in the backrooms is
-- messed up and should be scarier"). He was one stiff block of parts, jumped along a few times a second, and the seam
-- was left behind when his head twitched: it read as broken, not frightening. Now every limb hangs on a joint off his
-- hips, thighs and shins, upper arms and forearms, a neck and the head, each with its rest (stooped, bowed) in the
-- joint, and the seam is welded to the head. This only carries him (an anchored, invisible root, moved smoothly each
-- frame); every screen draws him walking (StalkerClient: the stride with the knees the wrong way, the arms dragging,
-- the head that turns to look at you).
local function rigPart(model: Model, name: string, size: Vector3, colour: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.Massless = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end

-- `child` hung off `parent` on a joint named `name`: `c0` where the joint is in the parent's frame (and its rest turn),
-- `c1` where it is in the child's.
local function joint(name: string, parent: BasePart, child: BasePart, c0: CFrame, c1: CFrame)
	local motor = Instance.new("Motor6D")
	motor.Name = name
	motor.Part0 = parent
	motor.Part1 = child
	motor.C0 = c0
	motor.C1 = c1
	motor.Parent = parent
	child.CFrame = parent.CFrame * c0 * c1:Inverse()
end

local function welded(parent: BasePart, child: BasePart, at: CFrame)
	local weld = Instance.new("Weld")
	weld.Part0 = parent
	weld.Part1 = child
	weld.C0 = at
	weld.Parent = parent
	child.CFrame = parent.CFrame * at
end

-- ROUNDED (the two-hundred-and-twenty-third pass, from "make the backrooms character even better": filmed, he was a
-- pale head on flat black sticks with gaps at every joint). Each limb's own block stays as the joint carries it (his
-- hold is summed from it, blender/check_backrooms.py) but is not drawn: a round limb is welded along it in its place.
local function rounded(model: Model, limb: Part): Part
	limb.Transparency = 1
	local round = rigPart(model, limb.Name .. "Round", Vector3.new(limb.Size.Y, limb.Size.X, limb.Size.Z), limb.Color,
		limb.Material)
	round.Shape = Enum.PartType.Cylinder
	welded(limb, round, CFrame.Angles(0, 0, math.rad(90)))
	return round
end

-- A knob of a joint: a ball where two of his limbs meet, a little thicker than either, so it reads as bone under the
-- cloth and not a gap.
local function knob(model: Model, on: BasePart, offset: CFrame, across: number, colour: Color3, material: Enum.Material?)
	local ball = rigPart(model, "Knob", Vector3.new(across, across, across), colour, material)
	ball.Shape = Enum.PartType.Ball
	welded(on, ball, offset)
	return ball
end

local function marsh(at: Vector3): (Model, BasePart, CFrame)
	local model = Instance.new("Model")
	model.Name = "Marsh"
	-- (A faded charcoal since the two-hundred-and-twenty-fourth pass: near black, he was a black cut-out against the
	-- yellow walls and nothing of his shape read.)
	local suit, skin = Color3.fromRGB(46, 43, 44), Color3.fromRGB(214, 208, 200)
	local base = CFrame.new(at)
	local root = decor(model, "Root", Vector3.new(1, 1, 1), base, suit)
	root.Transparency = 1
	model.PrimaryPart = root
	local hips = rigPart(model, "Hips", Vector3.new(1.0, 0.5, 0.45), suit, Enum.Material.Fabric)
	joint("Hip", root, hips, CFrame.new(0, 5.3, 0), CFrame.identity)
	-- LEGS LIKE POLES: a thigh and a shin each, the foot welded on.
	for _, side in ipairs({ -1, 1 }) do
		local tag = if side < 0 then "L" else "R"
		local thigh = rigPart(model, "Thigh" .. tag, Vector3.new(0.34, 2.6, 0.34), suit, Enum.Material.Fabric)
		joint("Hip" .. tag, hips, thigh, CFrame.new(side * 0.34, -0.1, 0), CFrame.new(0, 1.3, 0))
		local shin = rigPart(model, "Shin" .. tag, Vector3.new(0.32, 2.5, 0.32), suit, Enum.Material.Fabric)
		joint("Knee" .. tag, thigh, shin, CFrame.new(0, -1.3, 0), CFrame.new(0, 1.25, 0))
		welded(shin, rigPart(model, "Foot", Vector3.new(0.42, 0.24, 0.9), suit, Enum.Material.Fabric), CFrame.new(0, -1.3, -0.22))
		-- Round, with a knob of a knee, and trousers too short for him: a band of grey sock over each ankle.
		rounded(model, thigh)
		rounded(model, shin)
		knob(model, thigh, CFrame.new(0, -1.3, 0), 0.44, suit, Enum.Material.Fabric)
		local sock = rigPart(model, "Sock", Vector3.new(0.34, 0.335, 0.335), Color3.fromRGB(92, 90, 88), Enum.Material.Fabric)
		sock.Shape = Enum.PartType.Cylinder
		welded(shin, sock, CFrame.new(0, -1.05, 0) * CFrame.Angles(0, 0, math.rad(90)))
		-- IN HIS SOCKS (the two-hundred-and-twenty-fourth pass): no shoes, the soft thud of his step; long grey feet in
		-- place of the black block (kept, not drawn: his hold is summed from where it is).
		for _, weld in ipairs(shin:GetChildren()) do
			if weld:IsA("Weld") and weld.Part1 and weld.Part1.Name == "Foot" then
				weld.Part1.Transparency = 1
			end
		end
		local sole = rigPart(model, "Sole", Vector3.new(0.4, 0.26, 1.2), Color3.fromRGB(92, 90, 88), Enum.Material.Fabric)
		local soleMesh = Instance.new("SpecialMesh")
		soleMesh.MeshType = Enum.MeshType.Sphere
		soleMesh.Parent = sole
		welded(shin, sole, CFrame.new(0, -1.3, -0.3))
	end
	-- STOOPED: the torso pitched forward over his hips (the rest of the waist's joint).
	local torso = rigPart(model, "Torso", Vector3.new(1.15, 2.3, 0.55), suit, Enum.Material.Fabric)
	joint("Spine", hips, torso, CFrame.new(0, 0.2, 0) * CFrame.Angles(math.rad(-16), 0, 0), CFrame.new(0, -1.15, 0))
	-- AN OFFICE MAN, of a kind (the same pass): a white shirt's collar at his throat, a dark red tie hanging off his
	-- stooped chest, his jacket's lapels, and the jacket's hem a little wider than him over his hips. His shoulders
	-- hunched up round his neck.
	local shirt, tieRed = Color3.fromRGB(206, 202, 192), Color3.fromRGB(88, 18, 22)
	welded(torso, rigPart(model, "Collar", Vector3.new(0.5, 0.22, 0.12), shirt, Enum.Material.Fabric),
		CFrame.new(0, 1.02, -0.26))
	welded(torso, rigPart(model, "Shirt", Vector3.new(0.34, 1.3, 0.04), shirt, Enum.Material.Fabric),
		CFrame.new(0, 0.38, -0.27))
	welded(torso, rigPart(model, "Tie", Vector3.new(0.14, 1.25, 0.05), tieRed, Enum.Material.Fabric),
		CFrame.new(0, 0.32, -0.3))
	for _, side in ipairs({ -1, 1 }) do
		welded(torso, rigPart(model, "Lapel", Vector3.new(0.16, 1.1, 0.05), Color3.fromRGB(58, 55, 58), Enum.Material.Fabric),
			CFrame.new(side * 0.24, 0.45, -0.29) * CFrame.Angles(0, 0, side * 0.22))
		knob(model, torso, CFrame.new(side * 0.6, 1.08, 0.02), 0.5, suit, Enum.Material.Fabric)
	end
	welded(torso, rigPart(model, "Hem", Vector3.new(1.25, 0.5, 0.62), suit, Enum.Material.Fabric), CFrame.new(0, -1.0, 0))
	-- A HUMP over his shoulder blades, the jacket strained across it: the stoop of something folded too long under
	-- ceilings too low for it.
	local hump = rigPart(model, "Hump", Vector3.new(1.05, 1.25, 0.62), suit, Enum.Material.Fabric)
	local humpMesh = Instance.new("SpecialMesh")
	humpMesh.MeshType = Enum.MeshType.Sphere
	humpMesh.Parent = hump
	welded(torso, hump, CFrame.new(0, 0.55, 0.2))
	-- DONE UP, AND BADGED (the two-hundred-and-twenty-fifth pass, "refine him"): two dull buttons doing his jacket up
	-- under the end of his tie, a breast pocket's flap, and clipped to it the staff badge of the baths, his name on it
	-- faded. Only close up, at the catch, can it be read.
	for _, high in ipairs({ -0.42, -0.66 }) do
		local button = rigPart(model, "Button", Vector3.new(0.12, 0.12, 0.12), Color3.fromRGB(28, 26, 26))
		button.Shape = Enum.PartType.Ball
		welded(torso, button, CFrame.new(0, high, -0.27))
	end
	welded(torso, rigPart(model, "Pocket", Vector3.new(0.34, 0.07, 0.05), Color3.fromRGB(58, 55, 58), Enum.Material.Fabric),
		CFrame.new(0.36, 0.3, -0.29))
	local badge = rigPart(model, "Badge", Vector3.new(0.34, 0.2, 0.03), Color3.fromRGB(226, 220, 200))
	welded(torso, badge, CFrame.new(0.36, 0.42, -0.31))
	local badgeGui = Instance.new("SurfaceGui")
	badgeGui.Face = Enum.NormalId.Front
	badgeGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	badgeGui.PixelsPerStud = 300
	badgeGui.Parent = badge
	local badgeWords = Instance.new("TextLabel")
	badgeWords.Size = UDim2.fromScale(1, 1)
	badgeWords.BackgroundTransparency = 1
	badgeWords.TextColor3 = Color3.fromRGB(52, 40, 22)
	badgeWords.TextTransparency = 0.25
	badgeWords.TextScaled = true
	badgeWords.FontFace = Style.WORLD.plain
	badgeWords.Text = "E. MARSH\nSTAFF"
	badgeWords.Parent = badgeGui
	-- His trouser hems dark with the carpet's damp, a band above each sock.
	for _, shinName in ipairs({ "ShinL", "ShinR" }) do
		local shinPart = model:FindFirstChild(shinName)
		if shinPart and shinPart:IsA("BasePart") then
			local hem = rigPart(model, "DampHem", Vector3.new(0.22, 0.345, 0.345), Color3.fromRGB(32, 30, 31), Enum.Material.Fabric)
			hem.Shape = Enum.PartType.Cylinder
			welded(shinPart, hem, CFrame.new(0, -0.78, 0) * CFrame.Angles(0, 0, math.rad(90)))
		end
	end
	-- ARMS PAST HIS KNEES: upper arm and forearm, hanging straight down whatever his stoop, long fingers off the hand.
	for _, side in ipairs({ -1, 1 }) do
		local tag = if side < 0 then "L" else "R"
		local upper = rigPart(model, "ArmUpper" .. tag, Vector3.new(0.28, 2.3, 0.28), suit, Enum.Material.Fabric)
		joint("Shoulder" .. tag, torso, upper, CFrame.new(side * 0.72, 1.05, 0) * CFrame.Angles(math.rad(16), 0, 0),
			CFrame.new(0, 1.15, 0))
		local lower = rigPart(model, "ArmLower" .. tag, Vector3.new(0.26, 2.3, 0.26), suit, Enum.Material.Fabric)
		joint("Elbow" .. tag, upper, lower, CFrame.new(0, -1.15, 0), CFrame.new(0, 1.15, 0))
		local hand = rigPart(model, "Hand", Vector3.new(0.26, 0.55, 0.18), skin)
		welded(lower, hand, CFrame.new(0, -1.4, -0.02))
		rounded(model, upper)
		rounded(model, lower)
		knob(model, upper, CFrame.new(0, -1.15, 0), 0.38, suit, Enum.Material.Fabric)
		-- A shirt cuff out of his sleeve, too short for his arms.
		local cuff = rigPart(model, "Cuff", Vector3.new(0.22, 0.3, 0.3), shirt, Enum.Material.Fabric)
		cuff.Shape = Enum.PartType.Cylinder
		welded(lower, cuff, CFrame.new(0, -1.08, 0) * CFrame.Angles(0, 0, math.rad(90)))
		-- FIVE LONG FINGERS (they were three pegs), each in two joints curling forward, with a dark nail: the middle
		-- ones longest, reaching as far as the three did.
		for k = 1, 5 do
			local long = ({ 0.62, 0.86, 0.95, 0.88, 0.66 })[k]
			local first = rigPart(model, "Finger", Vector3.new(0.065, long * 0.55, 0.065), skin)
			welded(hand, first, CFrame.new((k - 3) * 0.052, -0.27, 0) * CFrame.Angles(0.1, 0, (k - 3) * 0.07)
				* CFrame.new(0, -long * 0.275, 0))
			local second = rigPart(model, "Finger", Vector3.new(0.055, long * 0.5, 0.055), skin)
			welded(first, second, CFrame.new(0, -long * 0.275, 0) * CFrame.Angles(0.4, 0, 0) * CFrame.new(0, -long * 0.25, 0))
			welded(second, rigPart(model, "Nail", Vector3.new(0.058, 0.13, 0.03), Color3.fromRGB(120, 112, 96)),
				CFrame.new(0, -long * 0.2, -0.025))
		end
	end
	-- THE NECK further forward, the head bowed furthest.
	local neck = rigPart(model, "Neck", Vector3.new(0.3, 0.9, 0.3), skin)
	joint("NeckJ", torso, neck, CFrame.new(0, 1.15, 0) * CFrame.Angles(math.rad(-22), 0, 0), CFrame.new(0, -0.42, 0))
	rounded(model, neck)
	local head = rigPart(model, "Head", Vector3.new(1.15, 1.45, 1.1), skin)
	joint("HeadJ", neck, head, CFrame.new(0, 0.45, 0) * CFrame.Angles(math.rad(-18), 0, 0), CFrame.new(0, -0.72, 0))
	-- The seam, down the middle of where his face is not: a hair of dark on the front of the head, welded to it.
	local seam = rigPart(model, "Seam", Vector3.new(0.05, 1.0, 0.02), Color3.fromRGB(70, 40, 40))
	welded(head, seam, CFrame.new(0, -0.08, -0.56))
	-- A MADE HEAD (the two-hundred-and-eleventh pass, from your note of 2026-11-07: "make the back rooms monster
	-- scarier"). Where Assets/Props has Marsh_Head (Studio's generator: a pale, long, faceless head, its skin like wax), it
	-- is worn over the plain one, a little larger and longer than a head should be, and the plain one and its seam go.
	-- Its front is its own -Z, unless it says otherwise (FrontYaw, radians about Y).
	local props = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	props = props and props:FindFirstChild("Props")
	local made = props and props:FindFirstChild("Marsh_Head")
	local madePart = made and (if made:IsA("BasePart") then made else made:FindFirstChildWhichIsA("BasePart", true))
	if madePart then
		local face = madePart:Clone()
		face.Name = "MadeHead"
		face.Size = madePart.Size * (head.Size.Y * 1.35 / madePart.Size.Y)
		face.Anchored = false
		face.Massless = true
		face.CanCollide, face.CanQuery, face.CanTouch = false, false, false
		face.Parent = model
		local yaw = madePart:GetAttribute("FrontYaw")
		welded(head, face, CFrame.new(0, 0.12, 0) * CFrame.Angles(0, if typeof(yaw) == "number" then yaw else 0, 0))
		head.Transparency = 1
		seam.Transparency = 1
	end
	local headAt = head.CFrame
	-- His breath, heard before he is seen: the growl from the bottom of the flume, slowed, round him.
	local stories = game:GetService("SoundService"):FindFirstChild("StorySounds")
	local growl = stories and (stories:FindFirstChild("MawGrowl") or stories:FindFirstChild("MawRumble"))
	if growl and growl:IsA("Sound") then
		local breath = growl:Clone()
		breath.Name = "Breath"
		breath.Looped = true
		breath.Volume = 0.7
		breath.PlaybackSpeed = 0.62
		breath.RollOffMode = Enum.RollOffMode.InverseTapered
		breath.RollOffMinDistance = 6
		breath.RollOffMaxDistance = 60
		breath.Parent = head
		breath:Play()
	end
	return model, head, base:ToObjectSpace(headAt)
end

local function lightsNear(at: Vector3?)
	for _, light in ipairs(tubes) do
		local panel = light.Parent
		if panel and panel:IsA("BasePart") then
			local gap = if at then (panel.Position - (at :: Vector3)).Magnitude else math.huge
			-- DYING ROUND HIM (the hundred-and-third pass): the nearest nearly out and stuttering, the next ones low,
			-- the rest of the rooms as they were. Never quite dark: an eighth at the least, so you always see him.
			if gap < 10 then
				light.Brightness = LIGHT_BRIGHTNESS * (if math.random() < 0.6 then 0.12 else 0.4)
			elseif gap < 20 then
				light.Brightness = LIGHT_BRIGHTNESS * (if math.random() < 0.35 then 0.25 else 0.7)
			else
				light.Brightness = LIGHT_BRIGHTNESS
			end
		end
	end
end

-- Open floor all the way from one point to another (every tile under the line walkable), as the rooms are laid out.
local function openLine(from: Vector3, to: Vector3): boolean
	local gap = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local steps = math.max(1, math.ceil(gap.Magnitude / (TILE / 4)))
	for k = 0, steps do
		local x, y = tileOf(from + gap * (k / steps))
		if not walkable(x, y) then
			return false
		end
	end
	return true
end

-- WHERE HE STANDS TO HOLD YOU: GRIP studs from you on open floor, back the way he came if it is open, else whichever of
-- the four ways out of your tile is open and nearest to where he is (in the black at the catch, so the step is never
-- seen). Nil if none is.
local function squaredUp(you: Vector3, him: Vector3): Vector3?
	local feet = Vector3.new(you.X, him.Y, you.Z)
	local back = Vector3.new(him.X - you.X, 0, him.Z - you.Z)
	if back.Magnitude > 0.05 and openLine(feet, feet + back.Unit * GRIP) then
		return feet + back.Unit * GRIP
	end
	local best, nearest = nil, math.huge
	for _, way in ipairs({ Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }) do
		local spot = feet + way * GRIP
		if openLine(feet, spot) and (spot - him).Magnitude < nearest then
			best, nearest = spot, (spot - him).Magnitude
		end
	end
	return best
end

local function chase(player: Player, hunt: Hunt)
	local token = hunt.token
	local start = staffTile
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) or not folder then
		return
	end
	local sx, sy
	if start then
		sx, sy = start.x, start.y
	else
		-- No staff door: the reachable tile furthest from you.
		local px, py = tileOf(root.Position)
		local far, best = -1, nil
		for y = 0, #MAP - 1 do
			for x = 0, #MAP[1] - 1 do
				local way = walkable(x, y) and wayTo(px, py, x, y)
				if way and #way > far then
					far, best = #way, { x, y }
				end
			end
		end
		if not best then
			return
		end
		sx, sy = best[1], best[2]
	end
	-- OUT OF THE STAFF DOOR: it swings open, and he is there.
	local door, rest = staffDoor, staffDoorRest
	if door and rest then
		door.CFrame = rest * CFrame.new(-door.Size.X / 2, 0, 0) * CFrame.Angles(0, math.rad(80), 0) * CFrame.new(door.Size.X / 2, 0, 0)
		task.delay(4, function()
			if door.Parent then
				door.CFrame = rest
			end
		end)
	end
	local model, head = marsh(tileAt(sx, sy, 0))
	model.Parent = folder
	hunt.model = model
	local remote = storyRemote()
	if remote then
		-- The door bangs open (the client hears it there), and the lights go out from it toward you and come back.
		remote:FireClient(player, "stalk", { at = head.Position, door = if door then door.Position else head.Position })
	end
	local began = os.clock()
	local here = tileAt(sx, sy, 0)
	local path: { Vector3 }? = nil
	local nextPath, pauseUntil, flicker = 0, 0, 0
	local facing = Vector3.new(0, 0, 1)
	-- MOVED SMOOTHLY (since the hundred-and-twenty-first pass; he was shown in jerks, and it read as broken): his root
	-- each frame. When he stops to tilt his head, and when a long way off down a straight he rushes, is written on him
	-- (Paused, Rushing) for every screen to draw (StalkerClient).
	local rushUntil = 0
	local spotted = false
	while hunts[player] == hunt and hunt.token == token and player.Parent and player:GetAttribute("InLevel") == "backRooms" do
		local dt = RunService.Heartbeat:Wait()
		local character = player.Character
		local target = character and character:FindFirstChild("HumanoidRootPart")
		if not (target and target:IsA("BasePart")) then
			break
		end
		local now = os.clock()
		if now >= nextPath then
			nextPath = now + 0.4
			local hx, hy = tileOf(here)
			local tx, ty = tileOf(target.Position)
			path = wayTo(hx, hy, tx, ty)
			if path and #path > 1 then
				table.remove(path, 1)
			end
		end
		-- Now and then he stops, and his head tilts; then on, a little faster.
		if now >= pauseUntil and math.random() < dt * 0.12 then
			pauseUntil = now + 0.3 + math.random() * 0.4
		end
		local walking = now >= pauseUntil
		local speed = if now - began > 20 then WALK_LATE else WALK
		local far = Vector3.new(target.Position.X - here.X, 0, target.Position.Z - here.Z).Magnitude
		-- HE SEES YOU (the two-hundred-and-twenty-sixth pass, "improve the backrooms monster even more"): the first time
		-- there is open floor between you, he stops dead, a long moment, staring; then comes at you all at once.
		if not spotted and far < 44 and openLine(here, target.Position) then
			spotted = true
			pauseUntil = now + 0.9
			rushUntil = now + 2.1
			model:SetAttribute("Spotted", now)
		end
		if now >= rushUntil and far > 14 and math.random() < dt * 0.18 then
			rushUntil = now + 0.6
		end
		if now < rushUntil then
			speed *= 1.7
		end
		local goal = if path and path[1] then path[1] else Vector3.new(target.Position.X, here.Y, target.Position.Z)
		local flat = Vector3.new(goal.X - here.X, 0, goal.Z - here.Z)
		if walking and flat.Magnitude > 0.05 then
			local step = math.min(flat.Magnitude, speed * dt)
			here += flat.Unit * step
			facing = facing:Lerp(flat.Unit, math.min(1, dt * 8))
			if path and path[1] and (Vector3.new(path[1].X - here.X, 0, path[1].Z - here.Z)).Magnitude < 0.3 then
				table.remove(path, 1)
			end
		end
		model:PivotTo(CFrame.lookAt(here, here + Vector3.new(facing.X, 0, facing.Z)))
		model:SetAttribute("Paused", not walking)
		model:SetAttribute("Rushing", now < rushUntil)
		if now >= flicker then
			flicker = now + 0.15
			lightsNear(here)
		end
		-- CAUGHT.
		local gap = Vector3.new(target.Position.X - here.X, 0, target.Position.Z - here.Z).Magnitude
		if gap < CATCH and math.abs(target.Position.Y - here.Y - 3) < 6 then
			hunts[player] = nil
			lightsNear(nil)
			-- HE HAS YOU: every screen draws him bent over you, his arms round you (StalkerClient), while yours plays the
			-- rest (the hundred-and-twenty-fifth pass). Squared up to you first, GRIP studs off and facing you, so his
			-- hands close round you (your own screen sets you exactly there: StoryClient's caught).
			local spot = squaredUp(target.Position, here)
			if spot then
				here = spot
				model:PivotTo(CFrame.lookAt(here, Vector3.new(target.Position.X, here.Y, target.Position.Z)))
				model:SetAttribute("Grip", GRIP)
			end
			model:SetAttribute("Paused", true)
			model:SetAttribute("Caught", true)
			pcall(hunt.onCaught, player, head.Position)
			-- (Kept through the whole of the catch on their screen, the hundred-and-thirty-third pass: to the black.)
			task.delay(4.5, function()
				model:Destroy()
			end)
			return
		end
	end
	lightsNear(nil)
	model:Destroy()
end

-- Called as `player` arrives (Bootstrap's enterBackRooms): the hunt, soon or later.
function BackRoomsService.hunt(player: Player, onCaught: (Player, Vector3) -> ())
	local old = hunts[player]
	local hunt: Hunt = { token = (if old then old.token else 0) + 1, model = nil, onCaught = onCaught }
	hunts[player] = hunt
	local wait = if math.random() < HUNT_CHANCE then HUNT_EARLY.Min + math.random() * (HUNT_EARLY.Max - HUNT_EARLY.Min) else HUNT_AFTER
	task.delay(wait, function()
		if hunts[player] == hunt and player.Parent and player:GetAttribute("InLevel") == "backRooms" then
			chase(player, hunt)
		end
	end)
end

-- Called as `player` goes (the way out, the lobby, leaving the game): he is gone.
function BackRoomsService.callOff(player: Player)
	local hunt = hunts[player]
	hunts[player] = nil
	if hunt and hunt.model then
		hunt.model:Destroy()
	end
	if next(hunts) == nil then
		lightsNear(nil)
	end
end

game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
	BackRoomsService.callOff(player)
end)

-- The way back through the door you came in by (Bootstrap's: up the lobby's corridor).
function BackRoomsService.setReturn(fn: (Player) -> ())
	returnHandler = fn
end

function BackRoomsService.build(onExit: (Player) -> ())
	exitHandler = onExit
	if BackRoomsService.isBuilt() then
		return
	end
	local made = Instance.new("Folder")
	made.Name = "BackRooms"
	local rows, cols = #MAP, #MAP[1]

	-- THE CARPET, under everything, and THE CEILING, over everything, resting on the walls.
	-- (Carpet that is carpet, and walls and a ceiling of plaster, since the hundred-and-third pass: felt and plastic
	-- read as a model of the place, not the place.)
	part("Carpet", Vector3.new(cols * TILE, 1, rows * TILE),
		CFrame.new(ORIGIN + Vector3.new(cols * TILE / 2, -0.5, rows * TILE / 2)), CARPET, Enum.Material.Carpet, made)
	local ceiling = part("Ceiling", Vector3.new(cols * TILE, 1, rows * TILE),
		CFrame.new(ORIGIN + Vector3.new(cols * TILE / 2, HEIGHT + 0.5, rows * TILE / 2)), CEILING,
		Enum.Material.Plaster, made)
	ceiling.CastShadow = false

	-- THE WALLS: one slab per run of wall tiles along a row, carpet to ceiling.
	for y = 0, rows - 1 do
		local x = 0
		while x < cols do
			if solid(charAt(x, y)) then
				local from = x
				while x + 1 < cols and solid(charAt(x + 1, y)) do
					x += 1
				end
				local span = x - from + 1
				local centre = ORIGIN + Vector3.new((from + span / 2) * TILE, HEIGHT / 2, (y + 0.5) * TILE)
				part("Wall", Vector3.new(span * TILE, HEIGHT, TILE), CFrame.new(centre), WALL, Enum.Material.Plaster, made)
			end
			x += 1
		end
	end

	-- THINGS THE HOLD HAS KEPT, sunk into the walls, the carpet and the ceiling.
	sinkThings(made)
	-- FLUFF, in its mouse hole (pass 268).
	local dustOk, dustErr = pcall(buildDust, made)
	if not dustOk then
		warn("BackRoomsService: Fluff's hole: " .. tostring(dustErr))
	end

	-- THE PLACE LOOKED AT CLOSELY (the hundred-and-third pass, from your notes: "improve the looks of backrooms
	-- greatly"): the ceiling's T-bar grid, every tile's edge, held up against the ceiling; a skirting board along the
	-- foot of every wall; and the damp, darker patches rising up the walls from the carpet and brown rings on the
	-- ceiling tiles where something has come through. Nothing collides, nothing is in anyone's way, everything is on
	-- the surface it belongs to.
	local function flat(name: string, size: Vector3, cf: CFrame, colour: Color3, material: Enum.Material): Part
		local p = part(name, size, cf, colour, material, made)
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		return p
	end
	for gx = 0, cols do
		flat("CeilingGrid", Vector3.new(0.22, 0.12, rows * TILE),
			CFrame.new(ORIGIN + Vector3.new(gx * TILE, HEIGHT - 0.06, rows * TILE / 2)), GRID, Enum.Material.Metal)
	end
	for gy = 0, rows do
		flat("CeilingGrid", Vector3.new(cols * TILE, 0.12, 0.22),
			CFrame.new(ORIGIN + Vector3.new(cols * TILE / 2, HEIGHT - 0.06, gy * TILE)), GRID, Enum.Material.Metal)
	end
	local faces: { { at: Vector3, out: Vector3 } } = {}
	for y = 0, rows - 1 do
		for x = 0, cols - 1 do
			if charAt(x, y) == "." or charAt(x, y) == "S" then
				for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					-- (Not across the door you came in by, behind where you arrive.)
					-- (Nor across Fluff's mouse hole, pass 268: the skirting is cut for it.)
					local hole = x == DUST.x and y == DUST.y and step[1] == -1
					if charAt(x + step[1], y + step[2]) == "#" and not (charAt(x, y) == "S" and step[2] == -1) and not hole then
						local out = Vector3.new(-step[1], 0, -step[2])
						local face = tileAt(x, y, 0) + Vector3.new(step[1], 0, step[2]) * (TILE / 2)
						local across = Vector3.new(out.Z, 0, -out.X)
						flat("Skirting", Vector3.new(TILE, 0.55, 0.12),
							CFrame.fromMatrix(face + out * 0.06 + Vector3.new(0, 0.275, 0), across, Vector3.yAxis, -out),
							SKIRTING, Enum.Material.Wood)
						table.insert(faces, { at = face, out = out })
					end
				end
			end
		end
	end
	local damp = Random.new(1983)
	for _ = 1, 34 do
		if #faces == 0 then
			break
		end
		local f = faces[damp:NextInteger(1, #faces)]
		local across = Vector3.new(f.out.Z, 0, -f.out.X)
		local high = damp:NextNumber(0.9, 2.6)
		local patch = flat("Damp", Vector3.new(damp:NextNumber(1.2, 3.4), high, 0.03),
			CFrame.fromMatrix(f.at + f.out * 0.015 + across * damp:NextNumber(-0.8, 0.8) + Vector3.new(0, 0.55 + high / 2, 0),
				across, Vector3.yAxis, -f.out), DAMP, Enum.Material.Plaster)
		patch.Transparency = 0.35
	end
	for _ = 1, 18 do
		local x, y = damp:NextInteger(1, cols - 2), damp:NextInteger(1, rows - 2)
		if charAt(x, y) == "." then
			local across = damp:NextNumber(1.4, 3.2)
			local ring = flat("CeilingStain", Vector3.new(0.02, across, across),
				CFrame.new(tileAt(x, y, HEIGHT - 0.01)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(160, 132, 80),
				Enum.Material.Plaster)
			ring.Shape = Enum.PartType.Cylinder
			ring.Transparency = 0.45
		end
	end

	-- THE LIGHTS: a tube panel set into the ceiling, and the light it gives, every third tile.
	local lights: { SurfaceLight } = {}
	local middle, nearest = tileAt(cols / 2, rows / 2, 0), math.huge
	local stutter: SurfaceLight? = nil
	for y = 0, rows - 1 do
		for x = 0, cols - 1 do
			local c = charAt(x, y)
			if (c == "." or c == "S") and x % 3 == 2 and y % 3 == 2 then
				local panel = part("TubePanel", Vector3.new(TILE * 0.8, 0.2, TILE * 0.8),
					CFrame.new(tileAt(x, y, HEIGHT - 0.1)), PANEL, Enum.Material.SmoothPlastic, made)
				panel.CanCollide = false
				panel.CastShadow = false
				local light = Instance.new("SurfaceLight")
				light.Face = Enum.NormalId.Bottom
				light.Color = TUBE
				light.Brightness = LIGHT_BRIGHTNESS
				light.Range = LIGHT_RANGE
				light.Angle = 120
				light.Shadows = false
				light.Parent = panel
				table.insert(lights, light)
				local gap = (panel.Position - middle).Magnitude
				if gap < nearest then
					nearest, stutter = gap, light
				end
			end
		end
	end

	-- THE WAY OUT (D, in the outer wall): a door with a lintel over it, a sign and its own small light, and the
	-- prompt that takes you back (Bootstrap's exit).
	for y = 0, rows - 1 do
		for x = 0, cols - 1 do
			local c = charAt(x, y)
			if c == "D" then
				-- Which way is in: the open neighbour.
				local inward = Vector3.new(-1, 0, 0)
				for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					local n = charAt(x + step[1], y + step[2])
					if n == "." or n == "S" then
						inward = Vector3.new(step[1], 0, step[2])
					end
				end
				local base = tileAt(x, y, 0)
				local across = Vector3.new(inward.Z, 0, -inward.X)
				local frame = CFrame.fromMatrix(base, across, Vector3.yAxis, -inward)
				part("Lintel", Vector3.new(TILE, HEIGHT - DOOR_HEIGHT, TILE),
					frame * CFrame.new(0, DOOR_HEIGHT + (HEIGHT - DOOR_HEIGHT) / 2, 0), WALL, Enum.Material.SmoothPlastic, made)
				local door = part("WayOut", Vector3.new(TILE, DOOR_HEIGHT, 0.6),
					frame * CFrame.new(0, DOOR_HEIGHT / 2, 0), DOOR, Enum.Material.Wood, made)
				CollectionService:AddTag(door, "BackRoomsExit")
				local prompt = Instance.new("ProximityPrompt")
				prompt.ActionText = "Go back"
				prompt.ObjectText = "Way out"
				prompt.MaxActivationDistance = 8
				prompt.RequiresLineOfSight = false
				prompt.Parent = door
				prompt.Triggered:Connect(function(player: Player)
					local leave = exitHandler
					if leave then
						local ok, err = pcall(leave, player)
						if not ok then
							warn("BackRoomsService: the way out failed: " .. tostring(err))
						end
					end
				end)
				local plateAt = base + inward * (TILE / 2 + 0.11) + Vector3.new(0, DOOR_HEIGHT + 1.1, 0)
				local plate = sign("WayOutSign", plateAt, inward, Vector2.new(3.2, 1.2), "WAY OUT",
					Color3.fromRGB(46, 120, 74), Color3.fromRGB(240, 248, 240), made)
				local glow = Instance.new("PointLight")
				glow.Color = Color3.fromRGB(150, 230, 170)
				glow.Brightness = 0.6
				glow.Range = 9
				glow.Shadows = false
				glow.Parent = plate
			elseif c == "L" then
				-- THE LOCKED STAFF DOOR: a door on the wall's open side, and nothing behind it you can reach.
				for _, step in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
					local n = charAt(x + step[1], y + step[2])
					if n == "." then
						local outward = Vector3.new(step[1], 0, step[2])
						local face = tileAt(x, y, 0) + outward * (TILE / 2 + 0.15)
						local across = Vector3.new(outward.Z, 0, -outward.X)
						local staff = part("StaffDoor", Vector3.new(TILE * 0.8, DOOR_HEIGHT - 0.5, 0.3),
							CFrame.fromMatrix(face + Vector3.new(0, (DOOR_HEIGHT - 0.5) / 2, 0), across, Vector3.yAxis, -outward),
							DOOR, Enum.Material.Wood, made)
						-- Where he comes out (WHAT WALKS DOWN HERE).
						staffDoor, staffDoorRest = staff, staff.CFrame
						staffTile = { x = x + step[1], y = y + step[2] }
						sign("StaffSign", tileAt(x, y, 0) + outward * (TILE / 2 + 0.11) + Vector3.new(0, DOOR_HEIGHT + 0.6, 0), outward,
							Vector2.new(2.6, 0.9), "STAFF ONLY", Color3.fromRGB(60, 52, 40), Color3.fromRGB(232, 220, 180), made)
					end
				end
			elseif c == "S" then
				-- WHERE YOU ARRIVE, facing the way the room goes; and Mrs Venn's notice on the wall behind you, beside the
				-- door you came in by.
				local base = tileAt(x, y, 0)
				arrivalAt = CFrame.lookAt(base + Vector3.new(0, 3, 0), base + Vector3.new(TILE, 3, TILE))
				-- THE WAY BACK (the hundred-and-third pass, from your notes: "when I enter the backrooms room, and only in
				-- the lobby, I want to be able to go back through the door I came, just like in the movie"): a door frame
				-- in the wall behind you, the one you came through. For someone who came down the lobby's corridor it is
				-- open, its yellow light spilling out (StoryClient lights it on their screen alone), and walking back into
				-- it takes them back up the corridor (Bootstrap). For someone who fell in, it is a frame round bare wall.
				local face = tileAt(x, y - 1, 0) + Vector3.new(0, 0, TILE / 2)
				local doorAt = CFrame.lookAt(face, face + Vector3.new(0, 0, 1))
				for _, jamb in ipairs({ -1.81, 1.81 }) do
					part("ReturnFrame", Vector3.new(0.42, 6.4, 0.5), doorAt * CFrame.new(jamb, 3.2, -0.25), DOOR,
						Enum.Material.Wood, made).CanCollide = false
				end
				part("ReturnFrame", Vector3.new(4.04, 0.46, 0.56), doorAt * CFrame.new(0, 6.17, -0.25), DOOR, Enum.Material.Wood,
					made).CanCollide = false
				local doorway = part("ReturnDoorway", Vector3.new(3.2, 6.4, 0.1), doorAt * CFrame.new(0, 3.2, -0.05), WALL,
					Enum.Material.Plaster, made)
				doorway.CanCollide = false
				doorway.CanQuery = false
				local spill = Instance.new("SurfaceLight")
				spill.Name = "Spill"
				spill.Face = Enum.NormalId.Front
				spill.Color = Color3.fromRGB(255, 232, 160)
				spill.Brightness = 1.4
				spill.Range = 14
				spill.Angle = 110
				spill.Shadows = false
				spill.Enabled = false
				spill.Parent = doorway
				local threshold = part("ReturnThreshold", Vector3.new(3.0, 6, 0.6), doorAt * CFrame.new(0, 3, -0.3), WALL,
					Enum.Material.Plaster, made)
				threshold.Transparency = 1
				threshold.CanCollide = false
				threshold.CanQuery = false
				threshold.Touched:Connect(function(hit: BasePart)
					local character = hit.Parent
					local walker = character and game:GetService("Players"):GetPlayerFromCharacter(character)
					local back = returnHandler
					if walker and back and walker:GetAttribute("BackRoomsFrom") == "lobby" then
						local ok, err = pcall(back, walker)
						if not ok then
							warn("BackRoomsService: the way back failed: " .. tostring(err))
						end
					end
				end)
				noticePlate = sign("Notice", tileAt(x + 2, y - 1, 0) + Vector3.new(0, 5.2, TILE / 2 + 0.11), Vector3.new(0, 0, 1),
					Vector2.new(3.6, 2.6), "CORPORATION BATHS. BACK ROOMS. STAFF ONLY.\nIf you have come down too many "
						.. "times, the way out is the door marked WAY OUT. Mind the carpet, it is damp.\nMrs Venn",
					Color3.fromRGB(184, 152, 84), Color3.fromRGB(52, 40, 22), made)
			end
		end
	end

	-- PERSISTENT: far from everything, and a player can be sent here at any moment.
	made.Parent = workspace
	folder = made
	tubes = lights

	-- ONE TUBE ON ITS WAY OUT, near the middle: lit, then a stutter every few seconds. Never dark: it drops to a
	-- third, not to nothing, and only for a moment.
	local failing = stutter
	if failing then
		task.spawn(function()
			while made.Parent do
				task.wait(4 + math.random() * 4)
				for _ = 1, 3 do
					failing.Brightness = LIGHT_BRIGHTNESS * 0.33
					task.wait(0.06 + math.random() * 0.08)
					failing.Brightness = LIGHT_BRIGHTNESS
					task.wait(0.05 + math.random() * 0.1)
				end
			end
		end)
	end
	print(("BackRoomsService: built, %d lights, %d parts."):format(#lights, #made:GetDescendants()))
end

BackRoomsService.STAMP = "5e2bfadd"
return BackRoomsService
