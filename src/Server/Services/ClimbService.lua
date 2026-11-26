--!strict
-- ServerScriptService/Services/ClimbService.lua
-- THE CLIMB (the two-hundred-and-sixtieth pass, from your note of 2026-11-25: "a new feature called infinite climb up
-- where it goes forever and there's a leaderboard of the max height players have reached"; a fall sends you back to the
-- bottom, your best height is kept, the board is global).
--
-- === What it is ===
--
--   * A ROCK IN THE SKY, far out where nothing else is (9000, 300, -9000; the squish room and the back rooms stand at the
--     other corners): a flagged courtyard on its top, a low wall round it, and in its middle a stone column that goes up
--     for ever. Round the column, one after another and always climbing, steps of the game's own materials, cloned
--     with everything they carry from ChunkBuilder's templates (as the squish room's slabs are) and registered with
--     DeformationService, so honey dents, bubble wrap pops, soap crumbles under you and grows back, a Needoh charges your
--     jump. Each step is carried on an iron arm from the column with a strut under it: nothing hangs in the air.
--   * FOR EVER, BUT ONLY WHERE SOMEONE IS. The path is worked out step by step from one seed (spotFor), so any step can
--     be built again exactly where it was. The first KEEP_BOTTOM are always there; above them a step is built only
--     while a climber is within BEHIND below or AHEAD above it, and taken away again when nobody is. The column grows as
--     the steps do. Harder as it goes: wider gaps and taller steps, up to what a running jump can always make.
--   * A LANDING every LANDING_EVERY steps: a stone floor to stand on, a post with how high it is, a lamp. A rest, not a
--     checkpoint.
--   * A FALL IS THE BOTTOM. Dropping FALL_DROP below the step you last stood on (or off the rock) is a fall: under a fade,
--     back to the courtyard. Your height is where your feet were on the last step you stood on; your best is kept in your
--     save (EconomyService.climbed, which pays a few tokens each new 25 m) and on the board.
--   * THE BOARD, GLOBAL: an ordered store of everyone's best (whole decimetres, as an ordered store wants integers),
--     written only when a best is better (UpdateAsync), read every BOARD_FRESH seconds at most, shown in the lobby by the
--     tower and at the bottom of the climb. Where the store cannot be reached (Studio without API access) it shows the
--     bests of the people here.
--   * IN AND OUT: the lobby's climbing tower at the garden's east end (its door's prompt), and back by the lift at the
--     bottom or the pause menu's Leave; anyone climbing is out of the lobby's vote (HubService.hubPlayers), as in the
--     squish room. A reset puts you back at the bottom.

local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Materials = (require(Shared:WaitForChild("MaterialConfig")) :: any).Materials
local MaterialAppearance = require(Shared:WaitForChild("MaterialAppearance")) :: any
local DeformationService = require(script.Parent:WaitForChild("DeformationService")) :: any
-- One look for the whole game: the heading face for every sign here.
local Style = require(Shared:WaitForChild("Style")) :: any
local PetStatues = require(Shared:WaitForChild("PetStatues")) :: any

local ClimbService = {}

-- ===== WHERE, AND HOW IT GOES UP =====
local ORIGIN = Vector3.new(9000, 300, -9000) -- the courtyard's floor (its top), at the column's middle
local COURT_RADIUS = 64
local TERRACE = { distance = 92, radius = 32 } -- the arrival terrace, out on the lift's side
local COLUMN_RADIUS = 9
local START_ANGLE = 0 -- where the first step goes up from (+X of the column)
local PATH = { near = 30, far = 38 } -- how far out from the column's middle the steps go
-- HEADROOM: a step is never less than this over the step a turn below it (with what hangs under it, and a jump), so the
-- spiral is never a stack you hit your head in.
local TURN_CLEAR = 22
local KEEP_BOTTOM = 6 -- steps always built
local AHEAD = 6 -- steps built above each climber
local BEHIND = 2 -- and kept below each climber
local BUILD_PER_TICK = 6 -- steps built at most each tick, so a fast climb never stutters the server
-- ONLY UP (pass 261, from your note: "how am I ever going to fall down if the chunk below me is there to catch me?").
-- Each climber's own screen shows only the step they are on and the next SHOW_AHEAD (ClimbClient; the rest are in
-- HIDDEN_GROUP for them, which their character passes through), and the server only ever counts them as climbing: a
-- step lower than the last one stood on is not stood on. So a miss is a fall, all the way: FALL_DROP under the last step,
-- or onto the courtyard from FLOOR_FALL_FROM steps up.
local SHOW_AHEAD = 2
local HIDDEN_GROUP = "ClimbHidden"
local FALL_DROP = 12 -- studs under the step you stood on last that make a fall
local FLOOR_FALL_FROM = 3
local LANDING_EVERY = 25
local SEED = 260
local METRE = 0.28 -- a stud, in metres (Roblox's own scale), for the height you are shown
-- THE STEPS' DIFFICULTY, from the bottom (0) to HARDEST_AT steps (1): the gap between one step and the next and how much
-- higher it is. A running jump here is 7.2 studs up and about eight across on the level, so the hardest step is a gap
-- of 5.4 with a rise of 3.8, which always makes it.
local HARDEST_AT = 280
local GAP = { easy = 1.6, hard = 5.0, jitter = 0.5 }
local RISE = { easy = 2.0, hard = 3.5, jitter = 0.3, most = 4.0 }

-- ===== THE BOARD =====
local BOARD_STORE = "ClimbHeight_v1"
local BOARD_ROWS = 10
local BOARD_FRESH = 60
local SUBMIT_EVERY = 90 -- seconds between writes of a climber's best while they climb (and always on a fall or leaving)

-- ===== THE LOBBY'S TOWER =====
-- (Pass 265, from your note: "positioning the climb entrance somewhere closer to the levels themselves since this is
-- where the main focus will be". It stood at the garden's east end; now it has a deck of its own beside the level gates,
-- one short walk from them (LobbyLayout: climbTower, climbBoard, climbGate). Its door faces -X, toward the gates.)
local LobbyLayout = require(Shared:WaitForChild("LobbyLayout")) :: any
local TOWER_AT = LobbyLayout.AT.climbTower
local LOBBY_BOARD_AT = LobbyLayout.AT.climbBoard
-- The board is turned to where you come onto the deck: the walk's mouth, on the deck's west edge.
local LOBBY_BOARD_FACES = LobbyLayout.AT.climbBoardFaces
	or Vector3.new(LobbyLayout.DECKS.climb.x - LobbyLayout.DECKS.climb.w / 2, 1, LobbyLayout.DECKS.climb.z)
local GATE_AT = LobbyLayout.AT.climbGate
local FADE_WAIT = 0.3

local PALETTE = {
	stone = Color3.fromRGB(226, 216, 196),
	stoneDark = Color3.fromRGB(160, 150, 138),
	flags = Color3.fromRGB(176, 168, 158),
	rock = Color3.fromRGB(118, 112, 108),
	iron = Color3.fromRGB(52, 56, 66),
	brass = Color3.fromRGB(196, 160, 82),
	lamp = Color3.fromRGB(255, 226, 170),
	sea = Color3.fromRGB(70, 128, 160),
	cloud = Color3.fromRGB(250, 251, 255),
	sign = Color3.fromRGB(250, 243, 226),
	ink = Color3.fromRGB(58, 44, 72),
	tower = Color3.fromRGB(64, 70, 92),
	pennant = Color3.fromRGB(240, 120, 132),
}

-- ===== STATE =====
type Spot = {
	index: number,
	at: Vector3, -- the middle of its walking surface
	angle: number,
	radius: number,
	tangent: Vector3,
	half: number, -- half its length along the path
	long: number,
	short: number,
	material: string?, -- nil on a landing
	landing: boolean,
}
type Pad = { name: string, slab: BasePart, top: number, long: number, short: number, alongX: boolean }
type Climber = { standY: number, standIndex: number, best: number, startBest: number, submitted: number,
	lastSubmit: number, falling: boolean }

local world: { [string]: any } = { built = false }
local pads: { Pad } = {}
local padByName: { [string]: Pad } = {}
local spots: { Spot } = {}
local steps: { [number]: Model } = {}
local columnTop = 0 -- how high the column is built (y)
local cloudBand = 0 -- how many bands of clouds are up
local climbers: { [Player]: Climber } = {}
local boardRows: { { name: string, metres: number } } = {}
local boardReadAt = -math.huge
local boardSurfaces: { SurfaceGui } = {}
local names: { [number]: string } = {}

-- ===== SMALL PIECES =====

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3, solid: boolean,
	material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = solid
	p.CanTouch = false
	p.CanQuery = solid
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A cylinder standing up (a Part's cylinder runs along its own X).
local function upright(parent: Instance, name: string, height: number, radius: number, at: Vector3, colour: Color3,
	solid: boolean, material: Enum.Material?): Part
	local p = part(parent, name, Vector3.new(height, radius * 2, radius * 2), CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2),
		colour, solid, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A member between two points (a girder, a strut).
local function beam(parent: Instance, name: string, from: Vector3, to: Vector3, thick: number, colour: Color3,
	material: Enum.Material?): Part
	local length = (to - from).Magnitude
	return part(parent, name, Vector3.new(thick, thick, length), CFrame.lookAt((from + to) / 2, to), colour, false,
		material or Enum.Material.Metal)
end

local function words(host: BasePart, face: Enum.NormalId, text: string, colour: Color3, scale: number?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.Parent = host
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = colour
	label.TextScaled = true
	label.FontFace = Style.FONT.heading
	label.Parent = gui
	local size = Instance.new("UITextSizeConstraint")
	size.MaxTextSize = math.floor(60 * (scale or 1))
	size.Parent = label
	return label
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function tell(player: Player, kind: string, extra: any?)
	local remote = world.remote
	if remote then
		remote:FireClient(player, kind, extra)
	end
end

local function metresAt(y: number): number
	return math.max(0, (y - ORIGIN.Y) * METRE)
end

-- ===== THE STEPS' MATERIALS =====

-- One slab of each material from ChunkBuilder's templates (it runs beside Bootstrap at start): the one with the most
-- cells that is between 6 and 18 studs each way, measured for its walking surface. As SquishRoomService.pickSlabs.
local function pickPads()
	local templates = ServerStorage:WaitForChild("ChunkTemplates", 60)
	if not templates then
		warn("ClimbService: no ServerStorage.ChunkTemplates (ChunkBuilder has not run), so the climb has only landings.")
		return
	end
	local last, steady = -1, 0
	for _ = 1, 120 do
		local count = #templates:GetChildren()
		if count == last and count > 0 then
			steady += 1
			if steady >= 4 then
				break
			end
		else
			steady = 0
		end
		last = count
		task.wait(0.5)
	end
	local best: { [string]: { slab: BasePart, cells: number } } = {}
	for _, item in ipairs(templates:GetDescendants()) do
		local name = item:IsA("BasePart") and item:GetAttribute("Material")
		if typeof(name) == "string" and Materials[name] then
			local slab = item :: BasePart
			local fits = slab.Size.X >= 6 and slab.Size.Z >= 5 and slab.Size.X <= 18 and slab.Size.Z <= 18
			if fits then
				local cells = 0
				for _, child in ipairs(slab:GetChildren()) do
					if child:IsA("BasePart") and child.Name:match("^SubRegion_") then
						cells += 1
					end
				end
				local held = best[name]
				if cells > 0 and (not held or cells > held.cells) then
					best[name] = { slab = slab, cells = cells }
				end
			end
		end
	end
	local list = {}
	for name, found in pairs(best) do
		local slab = found.slab
		local top = -math.huge
		for _, child in ipairs(slab:GetChildren()) do
			if child:IsA("BasePart") and child.Name:match("^SubRegion_") then
				local here = slab.CFrame:PointToObjectSpace(child.Position)
				top = math.max(top, here.Y + child.Size.Y / 2)
			end
		end
		local alongX = slab.Size.X >= slab.Size.Z
		table.insert(list, {
			name = name,
			slab = slab,
			top = top,
			long = math.max(slab.Size.X, slab.Size.Z),
			short = math.min(slab.Size.X, slab.Size.Z),
			alongX = alongX,
		})
	end
	-- In a fixed order, so the seed picks the same material for the same step on every server.
	table.sort(list, function(a, b)
		return a.name < b.name
	end)
	pads = list
	for _, pad in ipairs(list) do
		padByName[pad.name] = pad
	end
end

-- ===== THE PATH =====

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- The next step's place, worked out from the one before it and its own index alone.
local function extend()
	local index = #spots + 1
	local before = spots[index - 1]
	local prevAngle = if before then before.angle else START_ANGLE
	local prevRadius = if before then before.radius else (PATH.near + PATH.far) / 2
	local prevY = if before then before.at.Y else ORIGIN.Y + 1
	local prevHalf = if before then before.half else 4
	local prevMaterial = if before then before.material else nil
	local rng = Random.new(SEED * 7919 + index * 104729)
	local hard = math.clamp(index / HARDEST_AT, 0, 1)
	local landing = index % LANDING_EVERY == 0
	local material: string? = nil
	local long, short = 16, 12
	if not landing and #pads > 0 then
		local pick = pads[rng:NextInteger(1, #pads)]
		if pick.name == prevMaterial and #pads > 1 then
			pick = pads[(table.find(pads, pick) :: number) % #pads + 1]
		end
		material = pick.name
		long, short = pick.long, pick.short
	elseif not landing then
		landing = true
	end
	local gap = lerp(GAP.easy, GAP.hard, hard) + rng:NextNumber(-GAP.jitter, GAP.jitter)
	if landing or (before and before.landing) then
		gap = math.min(gap, 3)
	end
	local rise = math.clamp(lerp(RISE.easy, RISE.hard, hard) + rng:NextNumber(-RISE.jitter, RISE.jitter), 0.8, RISE.most)
	local radius = math.clamp(prevRadius + rng:NextNumber(-3, 3), PATH.near, PATH.far)
	-- The angle on round that puts this step's middle `reach` from the last one's.
	local reach = prevHalf + math.max(0.5, gap) + long / 2
	local cosine = math.clamp((prevRadius * prevRadius + radius * radius - reach * reach) / (2 * prevRadius * radius), -1, 1)
	local angle = prevAngle + math.acos(cosine)
	-- THE HEADROOM: over the highest step a turn below, by TURN_CLEAR, with the rise taken up to what a jump makes.
	local under = -math.huge
	for k = #spots, math.max(1, #spots - 40), -1 do
		local other = spots[k]
		local apart = angle - other.angle
		if math.abs(apart - math.pi * 2) < 0.55 then
			under = math.max(under, other.at.Y)
		end
	end
	if prevY + rise < under + TURN_CLEAR then
		rise = math.clamp(under + TURN_CLEAR - prevY, rise, RISE.most)
	end
	local y = prevY + rise
	local spot: Spot = {
		index = index,
		at = Vector3.new(ORIGIN.X + math.cos(angle) * radius, y, ORIGIN.Z + math.sin(angle) * radius),
		angle = angle,
		radius = radius,
		tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle)),
		half = long / 2,
		long = long,
		short = short,
		material = material,
		landing = landing,
	}
	table.insert(spots, spot)
end

local function spotFor(index: number): Spot
	while #spots < index do
		extend()
	end
	return spots[index]
end

-- ===== BUILDING A STEP =====

-- What carries a step: an iron arm from the column's face out under its middle, and a strut from lower on the column up
-- to the arm's end.
local function carry(model: Model, spot: Spot, underY: number)
	local out = Vector3.new(math.cos(spot.angle), 0, math.sin(spot.angle))
	local base = Vector3.new(ORIGIN.X, underY, ORIGIN.Z) + out * (COLUMN_RADIUS - 0.4)
	local tip = Vector3.new(ORIGIN.X, underY, ORIGIN.Z) + out * spot.radius
	beam(model, "ClimbArm", base, tip, 1.3, PALETTE.iron)
	local foot = base + Vector3.new(0, -math.min(9, (spot.radius - COLUMN_RADIUS) * 0.7), 0)
	beam(model, "ClimbStrut", foot, base:Lerp(tip, 0.8), 0.8, PALETTE.iron)
	-- A collar where the arm meets the column.
	part(model, "ClimbCollar", Vector3.new(1.2, 2.6, 2.6), CFrame.lookAt(base, base + out), PALETTE.iron, false, Enum.Material.Metal)
end

local function heightSign(parent: Instance, at: CFrame, metres: number)
	part(parent, "LandingPost", Vector3.new(0.4, 4.2, 0.4), at * CFrame.new(0, 2.1, 0), PALETTE.iron, false, Enum.Material.Metal)
	local board = part(parent, "LandingSign", Vector3.new(4.4, 1.8, 0.3), at * CFrame.new(0, 4.6, 0), PALETTE.sign, false)
	words(board, Enum.NormalId.Front, ("%d m"):format(math.floor(metres + 0.5)), PALETTE.ink)
	words(board, Enum.NormalId.Back, ("%d m"):format(math.floor(metres + 0.5)), PALETTE.ink)
end

local function buildStep(index: number)
	if steps[index] then
		return
	end
	local spot = spotFor(index)
	local model = Instance.new("Model")
	model.Name = "ClimbStep_" .. index
	model:SetAttribute("ClimbStep", index)
	local up = Vector3.new(0, 1, 0)
	local underY = spot.at.Y - 2.6
	local pad = spot.material and padByName[spot.material]
	if pad then
		local slab = pad.slab:Clone()
		slab.Parent = model
		model.PrimaryPart = slab
		-- Its long side along the path, level whatever it was in its chunk, its walking surface's middle at the spot.
		local turn = if pad.alongX then CFrame.fromMatrix(Vector3.zero, spot.tangent, up)
			else CFrame.fromMatrix(Vector3.zero, up:Cross(spot.tangent), up)
		model:PivotTo(CFrame.new(spot.at) * turn * CFrame.new(0, -pad.top, 0))
		slab:SetAttribute("ClimbStep", index)
		underY = spot.at.Y - pad.top - slab.Size.Y / 2 - 0.65
		if typeof(MaterialAppearance.paintKeys) == "function" then
			pcall(MaterialAppearance.paintKeys, model, nil)
		end
	else
		-- A LANDING: a stone floor with a lip, a post with the height on it, a lamp on the column over it.
		local floor = part(model, "LandingFloor", Vector3.new(spot.long, 1.6, spot.short),
			CFrame.fromMatrix(spot.at - up * 0.8, spot.tangent, up), PALETTE.stone, true, Enum.Material.Slate)
		floor:SetAttribute("ClimbStep", index)
		model.PrimaryPart = floor
		part(model, "LandingEdge", Vector3.new(spot.long + 0.6, 0.6, spot.short + 0.6),
			CFrame.fromMatrix(spot.at - up * 1.9, spot.tangent, up), PALETTE.stoneDark, false, Enum.Material.Slate)
		local out = Vector3.new(math.cos(spot.angle), 0, math.sin(spot.angle))
		heightSign(model, CFrame.lookAt(spot.at + out * (spot.short / 2 - 1), spot.at + out * (spot.short / 2 - 1) + spot.tangent),
			metresAt(spot.at.Y))
		local lampAt = Vector3.new(ORIGIN.X, spot.at.Y + 9, ORIGIN.Z) + out * (COLUMN_RADIUS + 1.2)
		part(model, "LandingLampArm", Vector3.new(0.4, 0.4, 1.6), CFrame.lookAt(lampAt - out * 0.8, lampAt), PALETTE.iron, false,
			Enum.Material.Metal)
		local lamp = part(model, "LandingLamp", Vector3.new(1.2, 1.2, 1.2), CFrame.new(lampAt + out * 0.2 - up * 0.6),
			PALETTE.lamp, false)
		lamp.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Color = PALETTE.lamp
		light.Brightness = 1.1
		light.Range = 22
		light.Parent = lamp
		underY = spot.at.Y - 2.4
	end
	carry(model, spot, underY)
	model.Parent = world.stepsFolder
	if pad then
		for _, piece in ipairs(model:GetDescendants()) do
			if piece:IsA("BasePart") and piece:GetAttribute("Material") then
				piece:SetAttribute("ClimbStep", index)
				DeformationService.registerPlatform(piece)
			end
		end
	end
	steps[index] = model
end

-- ===== THE COLUMN AND THE SKY ROUND IT =====

local SEGMENT = 64
local function growColumn(to: number)
	local folder = world.columnFolder
	while columnTop < to do
		local from = columnTop
		local seg = upright(folder, "ClimbColumn", SEGMENT, COLUMN_RADIUS, Vector3.new(ORIGIN.X, from + SEGMENT / 2, ORIGIN.Z),
			PALETTE.stone, true, Enum.Material.Concrete)
		seg.CastShadow = true
		-- A band at each join, and the height on four plaques every other one.
		upright(folder, "ClimbBand", 1.6, COLUMN_RADIUS + 0.5, Vector3.new(ORIGIN.X, from + SEGMENT, ORIGIN.Z), PALETTE.stoneDark,
			false, Enum.Material.Concrete)
		local metres = metresAt(from + SEGMENT)
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local at = Vector3.new(ORIGIN.X, from + SEGMENT - 3.2, ORIGIN.Z) + out * (COLUMN_RADIUS + 0.15)
			local plaque = part(folder, "ClimbPlaque", Vector3.new(3.6, 1.6, 0.25), CFrame.lookAt(at, at + out), PALETTE.sign, false)
			words(plaque, Enum.NormalId.Front, ("%d m"):format(math.floor(metres + 0.5)), PALETTE.ink, 0.8)
		end
		columnTop = from + SEGMENT
	end
end

-- A CLOUD: a heap of flattened puffs, wide and flat-bottomed, never one ball (which read as an egg).
-- (Pass 262: a cloud is a flat grey-blue base of wide puffs, a body of white ones heaped on it, and a few small crowning
-- ones; at sunset the climb's light catches them orange from the side, at night they go blue-grey.)
local CLOUD_BASE = Color3.fromRGB(214, 222, 238)
local function cloudHeap(folder: Instance, middle: Vector3, size: number, rng: Random)
	local function puff(at: Vector3, s: number, flat: number, colour: Color3)
		local p = part(folder, "ClimbCloud", Vector3.new(s * 1.6, s * flat, s * 1.25),
			CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), colour, false, Enum.Material.SmoothPlastic)
		p.Shape = Enum.PartType.Ball
		p.CastShadow = false
	end
	for _ = 1, rng:NextInteger(4, 6) do
		puff(middle + Vector3.new(rng:NextNumber(-size, size) * 0.9, -size * 0.12, rng:NextNumber(-size, size) * 0.6),
			size * rng:NextNumber(0.6, 1), 0.32, CLOUD_BASE)
	end
	for _ = 1, rng:NextInteger(5, 8) do
		puff(middle + Vector3.new(rng:NextNumber(-size, size) * 0.65, rng:NextNumber(0, size * 0.18),
			rng:NextNumber(-size, size) * 0.4), size * rng:NextNumber(0.45, 0.85), 0.55, PALETTE.cloud)
	end
	for _ = 1, rng:NextInteger(2, 3) do
		puff(middle + Vector3.new(rng:NextNumber(-size, size) * 0.3, size * rng:NextNumber(0.22, 0.34),
			rng:NextNumber(-size, size) * 0.2), size * rng:NextNumber(0.3, 0.45), 0.7, PALETTE.cloud)
	end
end

-- Clouds in bands as the column grows: a few soft heaps at a distance in each, never in the way.
local CLOUD_BAND = 110
local function growClouds(to: number)
	local folder = world.cloudFolder
	while ORIGIN.Y + cloudBand * CLOUD_BAND < to do
		cloudBand += 1
		local rng = Random.new(SEED + cloudBand * 31)
		local y = ORIGIN.Y + cloudBand * CLOUD_BAND
		for _ = 1, 6 do
			local a = rng:NextNumber(0, math.pi * 2)
			local far = rng:NextNumber(130, 420)
			local middle = Vector3.new(ORIGIN.X + math.cos(a) * far, y + rng:NextNumber(-30, 30), ORIGIN.Z + math.sin(a) * far)
			cloudHeap(folder, middle, rng:NextNumber(26, 44), rng)
		end
		-- AND ONE PAL IN EACH BAND (pass 264: "the little pets as shapes in the sky ... floating like the clouds"): a cloud the
		-- shape of one of your pals, the six in turn going up, well out and turned to face the column.
		local pal = PetStatues.PALS[(cloudBand - 1) % #PetStatues.PALS + 1]
		local a = rng:NextNumber(0, math.pi * 2)
		local far = rng:NextNumber(230, 340)
		local middle = Vector3.new(ORIGIN.X + math.cos(a) * far, y + rng:NextNumber(-20, 25), ORIGIN.Z + math.sin(a) * far)
		PetStatues.cloud(folder, pal, CFrame.lookAt(middle, Vector3.new(ORIGIN.X, middle.Y, ORIGIN.Z)), rng:NextNumber(40, 56),
			SEED + cloudBand)
	end
end

-- ===== THE BOTTOM =====

-- THE BOARD (pass 261: "improve the leaderboard"): a dark enamelled panel in an iron frame with brass edges and a brass
-- peak over it, on two posts with brass finials; on it a gold header and the top ten, each with a medal for the first
-- three. Twelve studs by eleven, so it reads from the path.
local BOARD_INK = Color3.fromRGB(26, 26, 42)
local function buildBoard(parent: Instance, base: CFrame, title: string): SurfaceGui
	for _, x in ipairs({ -6, 6 }) do
		part(parent, "BoardPost", Vector3.new(0.7, 13, 0.7), base * CFrame.new(x, 6.5, 0.2), PALETTE.iron, true, Enum.Material.Metal)
		local finial = part(parent, "BoardFinial", Vector3.new(1, 1, 1), base * CFrame.new(x, 13.4, 0.2), PALETTE.brass, false,
			Enum.Material.Metal)
		finial.Shape = Enum.PartType.Ball
		part(parent, "BoardFoot", Vector3.new(1.6, 0.4, 1.6), base * CFrame.new(x, 0.2, 0.2), PALETTE.iron, true, Enum.Material.Metal)
	end
	part(parent, "BoardFrame", Vector3.new(12.8, 11.8, 0.6), base * CFrame.new(0, 7.2, 0.05), PALETTE.iron, true, Enum.Material.Metal)
	local face = part(parent, "BoardFace", Vector3.new(12, 11, 0.2), base * CFrame.new(0, 7.2, -0.3), BOARD_INK, false)
	for _, y in ipairs({ 1.25, 13.15 }) do
		part(parent, "BoardTrim", Vector3.new(13.2, 0.35, 0.8), base * CFrame.new(0, y, -0.05), PALETTE.brass, false, Enum.Material.Metal)
	end
	-- The peak: two brass wedges meeting over the middle, and a little climber's star on it.
	for _, sign in ipairs({ -1, 1 }) do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "BoardPeak"
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.CanQuery = false
		wedge.Size = Vector3.new(0.5, 1.6, 3.2)
		wedge.CFrame = base * CFrame.new(sign * 1.6, 14.1, -0.05) * CFrame.Angles(0, sign * math.pi / 2, 0)
		wedge.Color = PALETTE.brass
		wedge.Material = Enum.Material.Metal
		wedge.Parent = parent
	end
	local star = part(parent, "BoardStar", Vector3.new(0.9, 0.9, 0.9), base * CFrame.new(0, 15.2, -0.05), Color3.fromRGB(255, 214, 120),
		false, Enum.Material.Metal)
	star.Shape = Enum.PartType.Ball
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ClimbBoard"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui:SetAttribute("Title", title)
	gui.Parent = face
	table.insert(boardSurfaces, gui)
	return gui
end

local MEDALS = { Color3.fromRGB(255, 204, 84), Color3.fromRGB(206, 212, 226), Color3.fromRGB(222, 152, 102) }

local function label(parent: Instance, text: string, size: number, colour: Color3, at: UDim2, extent: UDim2,
	align: Enum.TextXAlignment?, heavy: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = at
	l.Size = extent
	l.Text = text
	l.TextSize = size
	l.TextColor3 = colour
	l.TextXAlignment = align or Enum.TextXAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.FontFace = if heavy == false then Style.FONT.body else Style.FONT.heading
	l.Parent = parent
	return l
end

-- The board's rows, drawn on every board.
local function drawBoards()
	for _, gui in ipairs(boardSurfaces) do
		gui:ClearAllChildren()
		local header = Instance.new("Frame")
		header.Size = UDim2.new(1, 0, 0, 104)
		header.BackgroundColor3 = Color3.new(1, 1, 1)
		header.BorderSizePixel = 0
		header.Parent = gui
		local gradient = Instance.new("UIGradient")
		gradient.Color = ColorSequence.new(Color3.fromRGB(255, 220, 132), Color3.fromRGB(238, 168, 76))
		gradient.Rotation = 90
		gradient.Parent = header
		label(header, tostring(gui:GetAttribute("Title") or "HIGHEST CLIMBERS"), 46, BOARD_INK, UDim2.new(0, 0, 0, 10),
			UDim2.new(1, 0, 0, 54))
		label(header, "BEST HEIGHT  ·  EVERY SERVER", 20, Color3.fromRGB(110, 62, 30), UDim2.new(0, 0, 0, 66), UDim2.new(1, 0, 0, 26),
			nil, false)
		local list = Instance.new("Frame")
		list.BackgroundTransparency = 1
		list.Position = UDim2.new(0, 22, 0, 118)
		list.Size = UDim2.new(1, -44, 1, -130)
		list.Parent = gui
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = list
		if #boardRows == 0 then
			label(list, "Nobody yet. Be the first to climb!", 28, Color3.fromRGB(236, 232, 248), UDim2.new(), UDim2.new(1, 0, 0, 60))
		end
		for rank, row in ipairs(boardRows) do
			local strip = Instance.new("Frame")
			strip.LayoutOrder = rank
			strip.Size = UDim2.new(1, 0, 0, 38)
			strip.BackgroundColor3 = if rank % 2 == 1 then Color3.fromRGB(44, 44, 68) else Color3.fromRGB(36, 36, 56)
			strip.BorderSizePixel = 0
			strip.Parent = list
			local round = Instance.new("UICorner")
			round.CornerRadius = UDim.new(0, 10)
			round.Parent = strip
			local medal = Instance.new("Frame")
			medal.Size = UDim2.new(0, 32, 0, 32)
			medal.Position = UDim2.new(0, 4, 0, 3)
			medal.BackgroundColor3 = MEDALS[rank] or Color3.fromRGB(66, 66, 96)
			medal.Parent = strip
			local medalRound = Instance.new("UICorner")
			medalRound.CornerRadius = UDim.new(0.5, 0)
			medalRound.Parent = medal
			label(medal, tostring(rank), 20, if MEDALS[rank] then BOARD_INK else Color3.fromRGB(230, 230, 246), UDim2.new(),
				UDim2.fromScale(1, 1))
			label(strip, row.name, 29, Color3.fromRGB(242, 240, 252), UDim2.new(0, 46, 0, 0), UDim2.new(0.66, -46, 1, 0),
				Enum.TextXAlignment.Left)
			label(strip, ("%d m"):format(math.floor(row.metres)), 29, MEDALS[1], UDim2.new(0.66, 0, 0, 0), UDim2.new(0.34, -12, 1, 0),
				Enum.TextXAlignment.Right)
		end
	end
end

local function nameOf(userId: number): string
	local known = names[userId]
	if known then
		return known
	end
	local here = Players:GetPlayerByUserId(userId)
	if here then
		names[userId] = here.DisplayName
		return here.DisplayName
	end
	local ok, found = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and typeof(found) == "string" then found else ("Climber %d"):format(userId % 10000)
	names[userId] = name
	return name
end

local boardStore: OrderedDataStore? = nil
local function readBoard(force: boolean?)
	if not force and os.clock() - boardReadAt < BOARD_FRESH then
		return
	end
	boardReadAt = os.clock()
	local rows: { { name: string, metres: number } } = {}
	local ok = false
	if boardStore then
		ok = pcall(function()
			local page = (boardStore :: OrderedDataStore):GetSortedAsync(false, BOARD_ROWS):GetCurrentPage()
			for _, entry in ipairs(page) do
				local id = tonumber(entry.key)
				if id then
					table.insert(rows, { name = nameOf(id), metres = (tonumber(entry.value) or 0) / 10 })
				end
			end
		end)
	end
	if not ok then
		-- WHERE THE STORE CANNOT BE REACHED (Studio without API access): the bests of the people here.
		rows = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local best = tonumber(player:GetAttribute("ClimbBest")) or 0
			if best > 0 then
				table.insert(rows, { name = player.DisplayName, metres = best })
			end
		end
		table.sort(rows, function(a, b)
			return a.metres > b.metres
		end)
		while #rows > BOARD_ROWS do
			table.remove(rows)
		end
	end
	boardRows = rows
	drawBoards()
end

local function economy(): any
	local module = script.Parent:FindFirstChild("EconomyService")
	if not module then
		return nil
	end
	local ok, found = pcall(require, module)
	return if ok then found else nil
end

-- A climber's best written to the board (only if it is better than what the board has) and to their save.
local function submit(player: Player, climber: Climber)
	climber.lastSubmit = os.clock()
	if climber.best <= climber.submitted + 0.05 then
		return
	end
	local value = math.floor(climber.best * 10)
	climber.submitted = climber.best
	task.spawn(function()
		if boardStore then
			pcall(function()
				(boardStore :: OrderedDataStore):UpdateAsync(tostring(player.UserId), function(old: number?)
					if old and old >= value then
						return nil
					end
					return value
				end)
			end)
		end
		readBoard(true)
	end)
end

-- THE LIFT HOME: an old seaside lift standing on a stone base with a step up: marble columns at its corners on bases and
-- under capitals, iron lattice sides between them, a cream back wall with the brass lift doors in it and a lit floor dial
-- over them, a cornice and a green dome with a brass finial on top, a brass-framed sign over the way in, lanterns at the
-- front corners, and the call panel by the door. `base` is its floor's middle, its front (-Z) toward the column. Returns
-- the panel, for the prompt.
local function buildLift(folder: Instance, base: CFrame): BasePart
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	local cream = Color3.fromRGB(246, 238, 222)
	local green = Color3.fromRGB(92, 152, 140)
	part(folder, "LiftBase", Vector3.new(11, 0.6, 10), at(0, 0.3, 0), PALETTE.stoneDark, true, Enum.Material.Concrete)
	part(folder, "LiftStep", Vector3.new(7, 0.3, 1), at(0, 0.15, -5.5), PALETTE.stone, true, Enum.Material.Concrete)
	-- The corner columns.
	for _, x in ipairs({ -4.6, 4.6 }) do
		for _, z in ipairs({ -4, 4 }) do
			part(folder, "LiftColumnBase", Vector3.new(1.4, 0.5, 1.4), at(x, 0.85, z), PALETTE.stoneDark, true, Enum.Material.Marble)
			upright(folder, "LiftColumn", 9, 0.5, (at(x, 5.6, z)).Position, PALETTE.stone, true, Enum.Material.Marble)
			part(folder, "LiftCapital", Vector3.new(1.4, 0.5, 1.4), at(x, 10.35, z), PALETTE.stoneDark, false, Enum.Material.Marble)
		end
	end
	-- The back wall, the brass doors in it, and the dial over them.
	part(folder, "LiftBack", Vector3.new(8.6, 9.6, 0.5), at(0, 5.6, 4.1), cream, true, Enum.Material.Plaster)
	for _, x in ipairs({ -1.05, 1.05 }) do
		part(folder, "LiftDoor", Vector3.new(2.05, 6.4, 0.2), at(x, 4, 3.8), PALETTE.brass, false, Enum.Material.Metal)
	end
	part(folder, "LiftDoorFrame", Vector3.new(4.8, 0.4, 0.3), at(0, 7.4, 3.75), PALETTE.iron, false, Enum.Material.Metal)
	local dialRim = part(folder, "LiftDialRim", Vector3.new(0.2, 1.8, 1.8), at(0, 8.6, 3.75) * CFrame.Angles(0, math.pi / 2, 0),
		PALETTE.brass, false, Enum.Material.Metal)
	dialRim.Shape = Enum.PartType.Cylinder
	local dial = part(folder, "LiftDial", Vector3.new(0.12, 1.4, 1.4), at(0, 8.6, 3.65) * CFrame.Angles(0, math.pi / 2, 0),
		PALETTE.lamp, false)
	dial.Shape = Enum.PartType.Cylinder
	local dialLight = Instance.new("PointLight")
	dialLight.Color = PALETTE.lamp
	dialLight.Brightness = 0.6
	dialLight.Range = 8
	dialLight.Parent = dial
	part(folder, "LiftNeedle", Vector3.new(0.1, 0.6, 0.06), at(0, 8.75, 3.55) * CFrame.Angles(0, 0, math.rad(30)), PALETTE.iron,
		false, Enum.Material.Metal)
	-- The lattice sides: a rail at waist height and bars above and below it, crossed.
	for _, x in ipairs({ -4.6, 4.6 }) do
		part(folder, "LiftRail", Vector3.new(0.25, 0.25, 7.4), at(x, 3.6, 0), PALETTE.brass, false, Enum.Material.Metal)
		for k = -3, 3 do
			part(folder, "LiftBar", Vector3.new(0.12, 8.8, 0.12), at(x, 5.4, k * 1.05), PALETTE.iron, true, Enum.Material.Metal)
		end
		for _, tilt in ipairs({ -1, 1 }) do
			part(folder, "LiftBrace", Vector3.new(0.1, 0.1, 8.4), at(x, 7.3, 0) * CFrame.Angles(tilt * 0.33, 0, 0), PALETTE.iron, false,
				Enum.Material.Metal)
		end
	end
	-- The cornice, the drum and the dome, the finial.
	part(folder, "LiftCeiling", Vector3.new(10.6, 0.5, 9.6), at(0, 10.85, 0), cream, true, Enum.Material.Plaster)
	part(folder, "LiftCornice", Vector3.new(11.6, 0.5, 10.6), at(0, 11.35, 0), PALETTE.stoneDark, true, Enum.Material.Concrete)
	upright(folder, "LiftDrum", 1.1, 3.6, (at(0, 12.15, 0)).Position, cream, true, Enum.Material.Plaster)
	local dome = part(folder, "LiftDome", Vector3.new(7.2, 4.4, 7.2), at(0, 12.7, 0), green, true, Enum.Material.Metal)
	dome.Shape = Enum.PartType.Ball
	upright(folder, "LiftFinialStem", 1.4, 0.18, (at(0, 15.4, 0)).Position, PALETTE.brass, false, Enum.Material.Metal)
	local finial = part(folder, "LiftFinial", Vector3.new(0.8, 0.8, 0.8), at(0, 16.3, 0), PALETTE.brass, false, Enum.Material.Metal)
	finial.Shape = Enum.PartType.Ball
	-- The sign over the way in, in a brass frame, on the cornice's front.
	part(folder, "LiftSignFrame", Vector3.new(8.4, 1.9, 0.3), at(0, 11.35, -5.45), PALETTE.brass, false, Enum.Material.Metal)
	local sign = part(folder, "LiftSign", Vector3.new(8, 1.5, 0.2), at(0, 11.35, -5.6), PALETTE.sign, false)
	words(sign, Enum.NormalId.Front, "LIFT TO HARROW BAY", PALETTE.ink)
	-- Lanterns at the front corners.
	for _, x in ipairs({ -4.6, 4.6 }) do
		part(folder, "LanternArm", Vector3.new(0.2, 0.2, 1), at(x, 8.6, -4.9), PALETTE.iron, false, Enum.Material.Metal)
		local globe = part(folder, "LanternGlobe", Vector3.new(0.8, 0.95, 0.8), at(x, 8.1, -5.4), PALETTE.lamp, false)
		globe.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Color = PALETTE.lamp
		light.Brightness = 0.7
		light.Range = 10
		light.Parent = globe
	end
	-- The call panel on the right-hand column, its button lit.
	local panel = part(folder, "LiftPanel", Vector3.new(1, 1.6, 0.25), at(3.6, 3.6, -4.1), PALETTE.brass, false, Enum.Material.Metal)
	local button = part(folder, "LiftButton", Vector3.new(0.35, 0.35, 0.2), at(3.6, 3.6, -4.25), PALETTE.lamp, false)
	button.Shape = Enum.PartType.Ball
	return panel
end

local function buildBottom(folder: Folder)
	local up = Vector3.new(0, 1, 0)
	local y = ORIGIN.Y
	-- THE ROCK, from the courtyard down to the sea, and the sea.
	upright(folder, "ClimbRock", 300, COURT_RADIUS + 6, Vector3.new(ORIGIN.X, y - 4 - 150, ORIGIN.Z), PALETTE.rock, true,
		Enum.Material.Rock)
	local rng = Random.new(SEED)
	for k = 1, 14 do
		local a = k / 14 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local size = rng:NextNumber(22, 40)
		local boulder = part(folder, "ClimbBoulder", Vector3.new(size, size * 1.3, size),
			CFrame.new(Vector3.new(ORIGIN.X, y - 14 - rng:NextNumber(0, 70), ORIGIN.Z) + out * (COURT_RADIUS + 2)),
			PALETTE.rock, true, Enum.Material.Rock)
		boulder.Shape = Enum.PartType.Ball
	end
	part(folder, "ClimbSea", Vector3.new(6000, 2, 6000), CFrame.new(ORIGIN.X, y - 300, ORIGIN.Z), PALETTE.sea, true,
		Enum.Material.SmoothPlastic)
	-- A layer of cloud round the rock below the courtyard.
	for _ = 1, 30 do
		local a = rng:NextNumber(0, math.pi * 2)
		local far = rng:NextNumber(COURT_RADIUS + 60, 520)
		cloudHeap(folder, Vector3.new(ORIGIN.X + math.cos(a) * far, y - rng:NextNumber(60, 120), ORIGIN.Z + math.sin(a) * far),
			rng:NextNumber(34, 60), rng)
	end
	-- THE COURTYARD: a disc of flags, a kerb and a low wall round it, open where the lift is.
	upright(folder, "ClimbCourtyard", 4, COURT_RADIUS, Vector3.new(ORIGIN.X, y - 2, ORIGIN.Z), PALETTE.flags, true,
		Enum.Material.Slate)
	local liftAngle = math.pi
	local liftOut = Vector3.new(math.cos(liftAngle), 0, math.sin(liftAngle))
	-- THE ARRIVAL TERRACE (pass 261: "there's too little space for all of it"): a round terrace of its own, joined to the
	-- courtyard on the lift's side and well clear of the steps, for the lift home, the board and the sign.
	local terraceAt = Vector3.new(ORIGIN.X, y, ORIGIN.Z) + liftOut * TERRACE.distance
	local count = 48
	for k = 0, count - 1 do
		local a = (k + 0.5) / count * math.pi * 2
		local onTerrace = ((Vector3.new(ORIGIN.X, y, ORIGIN.Z) + Vector3.new(math.cos(a), 0, math.sin(a)) * COURT_RADIUS)
			- terraceAt).Magnitude < TERRACE.radius - 0.5
		if not onTerrace then
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local at = Vector3.new(ORIGIN.X, y + 1.6, ORIGIN.Z) + out * (COURT_RADIUS - 1)
			local length = 2 * math.pi * (COURT_RADIUS - 1) / count + 0.4
			part(folder, "ClimbWall", Vector3.new(1.6, 3.2, length), CFrame.lookAt(at, at + out:Cross(up)), PALETTE.stone, true,
				Enum.Material.Concrete)
			part(folder, "ClimbWallCap", Vector3.new(2, 0.4, length), CFrame.lookAt(at + up * 1.8, at + up * 1.8 + out:Cross(up)),
				PALETTE.stoneDark, false, Enum.Material.Concrete)
		end
	end
	-- The column's plinth, and a ring of lamps on posts round it.
	part(folder, "ClimbPlinth", Vector3.new(26, 3, 26), CFrame.new(ORIGIN.X, y + 1.5, ORIGIN.Z), PALETTE.stoneDark, true,
		Enum.Material.Concrete)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2 + math.pi / 6
		local at = Vector3.new(ORIGIN.X + math.cos(a) * 44, y, ORIGIN.Z + math.sin(a) * 44)
		upright(folder, "ClimbLampPost", 8, 0.25, at + up * 4, PALETTE.iron, true, Enum.Material.Metal)
		local globe = part(folder, "ClimbLampGlobe", Vector3.new(1.4, 1.4, 1.4), CFrame.new(at + up * 8.6), PALETTE.lamp, false)
		globe.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Color = PALETTE.lamp
		light.Brightness = 0.8
		light.Range = 20
		light.Parent = globe
	end
	-- THE FIRST STEP UP: a stone pad where the path begins, with a word on it.
	local startOut = Vector3.new(math.cos(START_ANGLE), 0, math.sin(START_ANGLE))
	local startAt = Vector3.new(ORIGIN.X, y, ORIGIN.Z) + startOut * ((PATH.near + PATH.far) / 2)
	local startPad = part(folder, "ClimbStart", Vector3.new(8, 1, 8), CFrame.new(startAt + up * 0.5), PALETTE.stone, true,
		Enum.Material.Marble)
	words(startPad, Enum.NormalId.Top, "CLIMB!", PALETTE.ink)
	-- The terrace's floor and rock, and its own wall, open where it meets the courtyard.
	upright(folder, "ClimbTerrace", 4, TERRACE.radius, terraceAt - up * 2, PALETTE.flags, true, Enum.Material.Slate)
	upright(folder, "ClimbTerraceRock", 300, TERRACE.radius + 3, terraceAt - up * 154, PALETTE.rock, true, Enum.Material.Rock)
	local ring = 28
	for k = 0, ring - 1 do
		local a = (k + 0.5) / ring * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local at = terraceAt + out * (TERRACE.radius - 1) + up * 1.6
		if (at - Vector3.new(ORIGIN.X, at.Y, ORIGIN.Z)).Magnitude > COURT_RADIUS + 0.5 then
			local length = 2 * math.pi * (TERRACE.radius - 1) / ring + 0.4
			part(folder, "ClimbWall", Vector3.new(1.6, 3.2, length), CFrame.lookAt(at, at + out:Cross(up)), PALETTE.stone, true,
				Enum.Material.Concrete)
			part(folder, "ClimbWallCap", Vector3.new(2, 0.4, length), CFrame.lookAt(at + up * 1.8, at + up * 1.8 + out:Cross(up)),
				PALETTE.stoneDark, false, Enum.Material.Concrete)
		end
	end
	local side = liftOut:Cross(up)
	for _, s in ipairs({ -1, 1 }) do
		local at = terraceAt + side * (s * 20) + liftOut * 6
		upright(folder, "ClimbLampPost", 8, 0.25, at + up * 4, PALETTE.iron, true, Enum.Material.Metal)
		local globe = part(folder, "ClimbLampGlobe", Vector3.new(1.4, 1.4, 1.4), CFrame.new(at + up * 8.6), PALETTE.lamp, false)
		globe.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Color = PALETTE.lamp
		light.Brightness = 0.8
		light.Range = 20
		light.Parent = globe
	end
	-- THE LIFT HOME (pass 263: "the exit to Harrow Bay is misplaced, also improve its model design"). It stood on the
	-- terrace's very edge, its back against the wall. Now it stands well in, facing the column across the terrace, and is
	-- a lift: buildLift.
	local liftAt = terraceAt + liftOut * (TERRACE.radius - 13)
	local panel = buildLift(folder, CFrame.lookAt(liftAt, liftAt - liftOut))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClimbHomePrompt"
	prompt.ActionText = "Ride home"
	prompt.ObjectText = "Lift to Harrow Bay"
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = panel
	prompt.Triggered:Connect(function(player: Player)
		ClimbService.leave(player)
	end)
	world.arrive = liftAt - liftOut * 10 + up * 3.5
	world.arriveFace = -liftOut
	-- THE BOARD on the terrace's left and the sign on its right as you arrive, each turned to you.
	local arriveFlat = Vector3.new(world.arrive.X, y, world.arrive.Z)
	local boardAt = terraceAt + side * 15 - liftOut * 4
	buildBoard(folder, CFrame.lookAt(boardAt, arriveFlat), "HIGHEST CLIMBERS")
	local signAt = terraceAt - side * 15 - liftOut * 4
	local signFrame = CFrame.lookAt(signAt, arriveFlat)
	-- A MADE SIGNBOARD (pass 269, from your note: "improve this sign"). It was a white plate on two sticks, and in the
	-- sun up here it glared. Now Assets/Props.Climb_Signboard (Studio's mesh generator): a dark-green planked board in a
	-- gold scrolled border under a little peaked copper roof, between cast-iron posts with finials, standing on the
	-- terrace; and the words in cream, set on the board's own face (its FaceZ, TextY, TextW, TextH: where the board is, in
	-- the model's own studs). The old plate on posts stands in without it.
	local props = ReplicatedStorage:FindFirstChild("Assets")
	props = props and props:FindFirstChild("Props")
	local madeSign = props and props:FindFirstChild("Climb_Signboard")
	if madeSign and madeSign:IsA("Model") then
		local scale = 1.45
		local board = madeSign:Clone()
		board.Name = "ClimbSignboard"
		for _, item in ipairs(board:GetDescendants()) do
			if item:IsA("BasePart") then
				item.Anchored = true
				item.CanCollide = item.Name == "posts_geom"
				item.CanTouch = false
			end
		end
		board:ScaleTo(scale)
		local foot = (tonumber(madeSign:GetAttribute("FootY")) or -3.47) * scale
		local at = signFrame * CFrame.new(0, -foot, 0)
		board:PivotTo(at)
		board.Parent = folder
		local faceZ = (tonumber(madeSign:GetAttribute("FaceZ")) or -0.8) * scale
		local textW = (tonumber(madeSign:GetAttribute("TextW")) or 4.3) * scale
		-- Two lines of their own (seen in play: as one block the question wrapped, "How high can you / go?"): the name large,
		-- up in the board's middle arch, and the question on one line across the board under it.
		local cream = Color3.fromRGB(250, 236, 196)
		for _, line in ipairs({ { "ClimbSign", "THE CLIMB", 0.5, 2.9, 0.95, 1.5 }, { "ClimbSignLine", "How high can you go?", -0.85, 4.3, 0.62, 1 } }) do
			local face = part(folder, line[1] :: string, Vector3.new(math.min((line[4] :: number) * scale, textW),
				(line[5] :: number) * scale, 0.05), at * CFrame.new(0, (line[3] :: number) * scale, faceZ - 0.04), PALETTE.sign, false)
			face.Transparency = 1
			face.CanQuery = false
			words(face, Enum.NormalId.Front, line[2] :: string, cream, line[6] :: number)
		end
	else
		for _, x in ipairs({ -3, 3 }) do
			part(folder, "SignPost", Vector3.new(0.4, 6, 0.4), signFrame * CFrame.new(x, 3, 0.3), PALETTE.iron, true,
				Enum.Material.Metal)
		end
		local sign = part(folder, "ClimbSign", Vector3.new(8, 3, 0.3), signFrame * CFrame.new(0, 5.4, 0), PALETTE.sign, false)
		words(sign, Enum.NormalId.Front, "THE CLIMB\nHow high can you go?", PALETTE.ink)
	end
end

-- ===== THE LOBBY'S TOWER =====

-- THE TOWER'S ENTRANCE (pass 261: "improve the entrance itself"): a little station at its foot on a stone base with two
-- steps up: cream walls between iron corner posts, a green gabled roof, stone pilasters either side of an arched doorway
-- full of warm light with a keystone over it, a lantern on each side, and the sign in a brass frame on the gable.
local VERDIGRIS = Color3.fromRGB(92, 152, 140)
local function buildEntrance(model: Model, cabin: CFrame)
	local function at(x: number, y: number, z: number): CFrame
		return cabin * CFrame.new(x, y, z)
	end
	-- The base and its steps.
	-- (Pass 263: the two steps overlapped the base and each other with their tops at the same heights, and flickered.
	-- Now each is its own piece of floor, side by side, a third of the base's height apart, none inside another.)
	part(model, "EntranceBase", Vector3.new(11, 0.8, 11), at(0, 0.4, 0), PALETTE.stoneDark, true, Enum.Material.Concrete)
	part(model, "EntranceStep", Vector3.new(7, 0.27, 0.9), at(0, 0.135, -6.95), PALETTE.stone, true, Enum.Material.Concrete)
	part(model, "EntranceStep", Vector3.new(7, 0.54, 0.9), at(0, 0.27, -6.05), PALETTE.stone, true, Enum.Material.Concrete)
	-- Walls: cream panels between iron corner posts, the front's either side of the door.
	part(model, "EntranceBack", Vector3.new(8.4, 8, 0.5), at(0, 4.8, 4.1), PALETTE.stone, true, Enum.Material.Plaster)
	for _, x in ipairs({ -4.1, 4.1 }) do
		part(model, "EntranceSide", Vector3.new(0.5, 8, 8.4), at(x, 4.8, 0), PALETTE.stone, true, Enum.Material.Plaster)
	end
	for _, x in ipairs({ -3.25, 3.25 }) do
		part(model, "EntranceFront", Vector3.new(2.2, 8, 0.5), at(x, 4.8, -4.1), PALETTE.stone, true, Enum.Material.Plaster)
	end
	for _, x in ipairs({ -4.3, 4.3 }) do
		for _, z in ipairs({ -4.3, 4.3 }) do
			part(model, "EntrancePost", Vector3.new(0.7, 8.4, 0.7), at(x, 5, z), PALETTE.iron, true, Enum.Material.Metal)
		end
	end
	-- A dado band round it.
	-- (Round the sides and back, and the front either side of the door: never across the doorway.)
	part(model, "EntranceDado", Vector3.new(9.2, 0.4, 0.3), at(0, 3, 4.4), PALETTE.tower, false, Enum.Material.Metal)
	for _, x in ipairs({ -4.4, 4.4 }) do
		part(model, "EntranceDado", Vector3.new(0.3, 0.4, 9.2), at(x, 3, 0), PALETTE.tower, false, Enum.Material.Metal)
	end
	for _, x in ipairs({ -3.4, 3.4 }) do
		part(model, "EntranceDado", Vector3.new(1.9, 0.4, 0.3), at(x, 3, -4.4), PALETTE.tower, false, Enum.Material.Metal)
	end
	-- The doorway: pilasters with a base and a capital, the arch of light, its rim and keystone.
	for _, x in ipairs({ -2.35, 2.35 }) do
		part(model, "EntrancePilasterBase", Vector3.new(1.3, 0.6, 0.9), at(x, 1.1, -4.45), PALETTE.stoneDark, true, Enum.Material.Marble)
		part(model, "EntrancePilaster", Vector3.new(1, 5.4, 0.7), at(x, 4.1, -4.45), PALETTE.stone, true, Enum.Material.Marble)
		part(model, "EntranceCapital", Vector3.new(1.4, 0.5, 1), at(x, 7, -4.45), PALETTE.stoneDark, false, Enum.Material.Marble)
	end
	local glow = Color3.fromRGB(255, 222, 160)
	local door = part(model, "TowerDoor", Vector3.new(3.7, 5.6, 0.3), at(0, 3.6, -4.05), glow, false, Enum.Material.SmoothPlastic)
	local arch = part(model, "EntranceArch", Vector3.new(0.3, 3.7, 3.7), at(0, 6.4, -4.05) * CFrame.Angles(0, math.pi / 2, 0), glow,
		false, Enum.Material.SmoothPlastic)
	arch.Shape = Enum.PartType.Cylinder
	local rim = part(model, "EntranceArchRim", Vector3.new(0.4, 4.6, 4.6), at(0, 6.4, -3.95) * CFrame.Angles(0, math.pi / 2, 0),
		PALETTE.stoneDark, false, Enum.Material.Marble)
	rim.Shape = Enum.PartType.Cylinder
	part(model, "EntranceSpandrel", Vector3.new(4.4, 0.6, 0.5), at(0, 9, -4.1), PALETTE.stone, true, Enum.Material.Plaster)
	part(model, "EntranceKeystone", Vector3.new(0.8, 1.1, 0.7), at(0, 8.5, -4.4), PALETTE.brass, false, Enum.Material.Metal)
	local light = Instance.new("PointLight")
	light.Color = glow
	light.Brightness = 0.9
	light.Range = 12
	light.Parent = door
	-- A lantern either side: an iron bracket, a brass cap, a warm globe.
	for _, x in ipairs({ -3.4, 3.4 }) do
		part(model, "LanternBracket", Vector3.new(0.2, 0.2, 1), at(x, 5.6, -4.8), PALETTE.iron, false, Enum.Material.Metal)
		part(model, "LanternCap", Vector3.new(0.9, 0.3, 0.9), at(x, 5.65, -5.3), PALETTE.brass, false, Enum.Material.Metal)
		local globe = part(model, "LanternGlobe", Vector3.new(0.75, 0.9, 0.75), at(x, 5.1, -5.3), glow, false, Enum.Material.SmoothPlastic)
		globe.Shape = Enum.PartType.Ball
		local lamp = Instance.new("PointLight")
		lamp.Color = glow
		lamp.Brightness = 0.6
		lamp.Range = 9
		lamp.Parent = globe
	end
	-- The roof: a cornice, two green slopes meeting at a ridge, and the gable's front where the sign hangs.
	part(model, "EntranceCornice", Vector3.new(9.8, 0.5, 9.8), at(0, 9.05, 0), PALETTE.stoneDark, true, Enum.Material.Concrete)
	for _, s in ipairs({ -1, 1 }) do
		local slope = Instance.new("WedgePart")
		slope.Name = "EntranceRoof"
		slope.Anchored = true
		slope.Size = Vector3.new(10.2, 2.6, 5.1)
		slope.CFrame = at(s * 2.55, 10.6, 0) * CFrame.Angles(0, s * math.pi / 2, 0)
		slope.Color = VERDIGRIS
		slope.Material = Enum.Material.Metal
		slope.Parent = model
	end
	part(model, "EntranceRidge", Vector3.new(0.5, 0.4, 10.4), at(0, 12, 0), PALETTE.brass, false, Enum.Material.Metal)
	-- The gable's front: two wedges turned as the slopes are, so they make the triangle under them.
	for _, s in ipairs({ -1, 1 }) do
		local g = Instance.new("WedgePart")
		g.Name = "EntranceGable"
		g.Anchored = true
		g.Size = Vector3.new(0.3, 2.6, 5.1)
		g.CFrame = at(s * 2.55, 10.6, -4.95) * CFrame.Angles(0, s * math.pi / 2, 0)
		g.Color = PALETTE.stone
		g.Material = Enum.Material.Plaster
		g.Parent = model
	end
	-- The sign, in a brass frame, on the front over the door.
	part(model, "SignFrame", Vector3.new(7.4, 2.2, 0.3), at(0, 9.9, -5.15), PALETTE.brass, false, Enum.Material.Metal)
	local sign = part(model, "TowerSign", Vector3.new(7, 1.8, 0.2), at(0, 9.9, -5.3), PALETTE.sign, false)
	words(sign, Enum.NormalId.Front, "THE CLIMB", PALETTE.ink)
	return door
end

local function buildTower(hub: Instance, hubOrigin: Vector3)
	local model = Instance.new("Model")
	model.Name = "ClimbTower"
	model.Parent = hub
	world.tower = model
	local base = hubOrigin + TOWER_AT
	local front = Vector3.new(-1, 0, 0)
	local up = Vector3.new(0, 1, 0)
	local side = front:Cross(up)
	local HEIGHT = 58
	world.towerFrame = { base = base, front = front, side = side, height = HEIGHT }
	-- Four legs leaning in, from the deck to the lantern deck; rings and crossed braces between them.
	local function corner(h: number, sx: number, sz: number): Vector3
		local half = lerp(6, 3.2, h / HEIGHT)
		return base + up * h + front * (sx * half) + side * (sz * half)
	end
	for _, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		beam(model, "TowerLeg", corner(0, c[1], c[2]), corner(HEIGHT, c[1], c[2]), 1, PALETTE.tower)
		part(model, "TowerFoot", Vector3.new(2.2, 0.6, 2.2), CFrame.new(corner(0.3, c[1], c[2])), PALETTE.stoneDark, true,
			Enum.Material.Concrete)
	end
	local levels = { 0.5, 12, 24, 36, 48, HEIGHT }
	for i, h in ipairs(levels) do
		local ring = { corner(h, 1, 1), corner(h, 1, -1), corner(h, -1, -1), corner(h, -1, 1) }
		for k = 1, 4 do
			beam(model, "TowerRing", ring[k], ring[k % 4 + 1], 0.6, PALETTE.tower)
		end
		local nextH = levels[i + 1]
		if nextH and h > 1 then
			local above = { corner(nextH, 1, 1), corner(nextH, 1, -1), corner(nextH, -1, -1), corner(nextH, -1, 1) }
			for k = 1, 4 do
				beam(model, "TowerBrace", ring[k], above[k % 4 + 1], 0.35, PALETTE.tower)
				beam(model, "TowerBrace", ring[k % 4 + 1], above[k], 0.35, PALETTE.tower)
			end
		end
	end
	-- THE LANTERN DECK and its beacon, and a pennant on a mast.
	part(model, "TowerDeck", Vector3.new(8.6, 0.6, 8.6), CFrame.new(base + up * (HEIGHT + 0.3)), PALETTE.tower, false,
		Enum.Material.Metal)
	upright(model, "TowerLantern", 3.4, 1.8, base + up * (HEIGHT + 2.3), PALETTE.brass, false, Enum.Material.Metal)
	local beacon = part(model, "TowerBeacon", Vector3.new(2.6, 2.6, 2.6), CFrame.new(base + up * (HEIGHT + 2.4)), PALETTE.lamp, false)
	beacon.Shape = Enum.PartType.Ball
	local glow = Instance.new("PointLight")
	glow.Color = PALETTE.lamp
	glow.Brightness = 1.2
	glow.Range = 24
	glow.Parent = beacon
	upright(model, "TowerMast", 7, 0.15, base + up * (HEIGHT + 7.5), PALETTE.tower, false, Enum.Material.Metal)
	local pennant = part(model, "TowerPennant", Vector3.new(0.1, 1.6, 3.4), CFrame.new(base + up * (HEIGHT + 10) + side * 1.7),
		PALETTE.pennant, false, Enum.Material.Fabric)
	pennant.CastShadow = false
	-- THE DAIS (pass 265): a round marble floor under the tower, edged in brass, that it stands in the middle of.
	upright(model, "TowerDaisRing", 0.14, 10.8, base + up * 0.07, PALETTE.brass, false, Enum.Material.Metal)
	upright(model, "TowerDais", 0.2, 10.4, base + up * 0.1, PALETTE.stone, true, Enum.Material.Marble)
	for k = 0, 7 do
		-- Eight brass studs round its edge, like a compass's.
		local a = k / 8 * math.pi * 2
		upright(model, "TowerDaisStud", 0.24, 0.35, base + Vector3.new(math.cos(a) * 9.4, 0.12, math.sin(a) * 9.4), PALETTE.brass,
			false, Enum.Material.Metal)
	end
	-- THE UPDRAFT (pass 265): warm motes drifting slowly up round the tower from its dais, the way dust rises in a sunbeam,
	-- so it reads as the way up from across the lobby.
	local draft = part(model, "TowerUpdraft", Vector3.new(14, 1, 14), CFrame.new(base + up * 1), PALETTE.lamp, false)
	draft.Transparency = 1
	draft.CanQuery = false
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "TowerMotes"
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = ColorSequence.new(Color3.fromRGB(255, 236, 196), Color3.fromRGB(214, 226, 255))
	motes.LightEmission = 0.4
	motes.LightInfluence = 0.3
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.15, 0.22),
		NumberSequenceKeypoint.new(0.8, 0.16), NumberSequenceKeypoint.new(1, 0) })
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.9) })
	motes.Lifetime = NumberRange.new(7, 10)
	motes.Rate = 6
	motes.Speed = NumberRange.new(3.5, 5.5)
	motes.SpreadAngle = Vector2.new(8, 8)
	motes.RotSpeed = NumberRange.new(-40, 40)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.Parent = draft
	-- THE ENTRANCE at its foot, its door toward the gates, and the prompt on the door.
	local door = buildEntrance(model, CFrame.lookAt(base, base + front))
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ClimbPrompt"
	prompt.ActionText = "Climb"
	prompt.ObjectText = "The Climb"
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = door
	prompt.Triggered:Connect(function(player: Player)
		ClimbService.enter(player)
	end)
	world.lobbyArrive = base + front * 10 + up * 3.5
	-- THE BOARD beside it, turned to the garden.
	local boardBase = hubOrigin + LOBBY_BOARD_AT
	local facesFlat = hubOrigin + LOBBY_BOARD_FACES
	buildBoard(model, CFrame.lookAt(boardBase, Vector3.new(facesFlat.X, boardBase.Y, facesFlat.Z)), "HIGHEST CLIMBERS")
	-- THE GATEWAY (pass 265): where the walk from the level gates comes onto the climb's deck, two stone piers either side of
	-- it and an iron arch between them, rising in the middle, with the name on a plate hung in it and a lantern on each
	-- pier; so the way to the climb is a way in, seen from the gates.
	local gate = hubOrigin + GATE_AT
	local gateFace = Vector3.new(-1, 0, 0)
	local span = 12.4
	for _, side in ipairs({ -1, 1 }) do
		local foot = gate + Vector3.new(0, 0, side * span)
		part(model, "GatePierBase", Vector3.new(2.6, 0.8, 2.6), CFrame.new(foot + up * 0.4), PALETTE.stoneDark, true,
			Enum.Material.Concrete)
		part(model, "GatePier", Vector3.new(2, 9, 2), CFrame.new(foot + up * 5.3), PALETTE.stone, true, Enum.Material.Marble)
		part(model, "GatePierCap", Vector3.new(2.6, 0.6, 2.6), CFrame.new(foot + up * 10.1), PALETTE.stoneDark, true,
			Enum.Material.Concrete)
		local finial = part(model, "GatePierFinial", Vector3.new(1, 1, 1), CFrame.new(foot + up * 10.9), PALETTE.brass, false,
			Enum.Material.Metal)
		finial.Shape = Enum.PartType.Ball
		-- A lantern hung off the pier's inner face.
		local lanternAt = foot + up * 7.3 - Vector3.new(0, 0, side * 1.7)
		part(model, "GateLanternArm", Vector3.new(0.2, 0.2, 1.4), CFrame.new(foot + up * 7.95 - Vector3.new(0, 0, side * 1.3)),
			PALETTE.iron, false, Enum.Material.Metal)
		part(model, "GateLanternCap", Vector3.new(0.8, 0.3, 0.8), CFrame.new(lanternAt + up * 0.55), PALETTE.brass, false,
			Enum.Material.Metal)
		local globe = part(model, "GateLanternGlobe", Vector3.new(0.7, 0.85, 0.7), CFrame.new(lanternAt), PALETTE.lamp, false,
			Enum.Material.SmoothPlastic)
		globe.Shape = Enum.PartType.Ball
		local lamp = Instance.new("PointLight")
		lamp.Color = PALETTE.lamp
		lamp.Brightness = 0.6
		lamp.Range = 10
		lamp.Parent = globe
	end
	-- The arch: iron, in short straight pieces on a curve from one cap to the other, rising 3.4 in the middle, a lighter
	-- bar under it and brass rings between the two.
	local pieces = 14
	local prev: Vector3? = nil
	for k = 0, pieces do
		local t = k / pieces
		local at = gate + Vector3.new(0, 10.4 + 3.4 * math.sin(t * math.pi), -span + 2 * span * t)
		if prev then
			beam(model, "GateArch", prev, at, 0.45, PALETTE.tower, Enum.Material.Metal)
			beam(model, "GateArchLower", prev - up * 0.9, at - up * 0.9, 0.22, PALETTE.tower, Enum.Material.Metal)
		end
		prev = at
	end
	for k = 1, pieces - 1, 2 do
		local t = k / pieces
		local at = gate + Vector3.new(0, 10.4 + 3.4 * math.sin(t * math.pi) - 0.45, -span + 2 * span * t)
		local ring = upright(model, "GateArchRing", 0.12, 0.38, at, PALETTE.brass, false, Enum.Material.Metal)
		ring.CFrame = CFrame.new(at) * CFrame.Angles(0, math.pi / 2, 0)
	end
	-- The name, on a plate hung from the arch's crown by two short chains, its face to the gates.
	local plateAt = gate + up * 11.2
	for _, z in ipairs({ -2.6, 2.6 }) do
		beam(model, "GatePlateChain", gate + Vector3.new(0, 12.95, z), plateAt + Vector3.new(0, 0.85, z), 0.1, PALETTE.iron,
			Enum.Material.Metal)
	end
	part(model, "GatePlateFrame", Vector3.new(7.6, 1.8, 0.2), CFrame.lookAt(plateAt, plateAt + gateFace), PALETTE.brass, false,
		Enum.Material.Metal)
	local plate = part(model, "GatePlate", Vector3.new(7.2, 1.4, 0.2), CFrame.lookAt(plateAt + gateFace * 0.12,
		plateAt + gateFace * 2), PALETTE.sign, false)
	words(plate, Enum.NormalId.Front, "THE CLIMB", PALETTE.ink)
	CollectionService:AddTag(model, "ClimbTower")
end

-- A slab, made a toy: cloned with all it carries, scaled down, and made nothing but a look (no material attribute for
-- the deformation or the step sounds, no tags, nothing to touch or stand on).
local function miniature(pad: Pad, long: number): Model
	local model = Instance.new("Model")
	model.Name = "Mini_" .. pad.name
	local slab = pad.slab:Clone()
	slab.Parent = model
	model.PrimaryPart = slab
	for _, item in ipairs(model:GetDescendants()) do
		for _, tag in ipairs(item:GetTags()) do
			item:RemoveTag(tag)
		end
		for name in pairs(item:GetAttributes()) do
			item:SetAttribute(name, nil)
		end
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanQuery = false
			item.CanTouch = false
		elseif item:IsA("BaseScript") or item:IsA("ProximityPrompt") or item:IsA("ClickDetector") then
			item:Destroy()
		end
	end
	for _, tag in ipairs(model:GetTags()) do
		model:RemoveTag(tag)
	end
	model:ScaleTo(long / pad.long)
	return model
end

-- THE STEPS UP THE TOWER'S OUTSIDE (pass 261: "improve how detailed those little square chunks are"): each a real slab of
-- one of the climb's materials made small (honey, bubble wrap, chocolate, keys...), on an iron bracket with a strut,
-- winding up the tower. Put on once the materials are measured; plain coloured blocks where there are none.
local function decorateTower()
	local tower = world.tower :: Model?
	local frame = world.towerFrame
	if not (tower and frame) then
		return
	end
	local up = Vector3.new(0, 1, 0)
	local colours = { Color3.fromRGB(255, 196, 120), Color3.fromRGB(150, 220, 200), Color3.fromRGB(246, 170, 196),
		Color3.fromRGB(190, 176, 246), Color3.fromRGB(250, 230, 150), Color3.fromRGB(170, 210, 250) }
	for k = 0, 11 do
		local h = 17 + k * 3.3
		local a = k * 0.95
		local half = lerp(6, 3.2, h / frame.height)
		local out = frame.front * math.cos(a) + frame.side * math.sin(a)
		local along = out:Cross(up)
		local at = frame.base + up * h + out * (half + 2.6)
		local pad = if #pads > 0 then pads[(k * 5) % #pads + 1] else nil
		if pad then
			local mini = miniature(pad, 4.2)
			local scale = 4.2 / pad.long
			local turn = if pad.alongX then CFrame.fromMatrix(Vector3.zero, along, up) else CFrame.fromMatrix(Vector3.zero, up:Cross(along), up)
			mini:PivotTo(CFrame.new(at) * turn * CFrame.new(0, -pad.top * scale, 0))
			mini.Parent = tower
			-- (Pass 265: built and blown away again and again on everyone's screen, bottom to top, a little show of how the
			-- climb's steps come to you: ClimbClient's DEMO.)
			mini:SetAttribute("DemoIndex", k + 1)
			CollectionService:AddTag(mini, "ClimbDemoStep")
		else
			local step = part(tower, "TowerStep", Vector3.new(3.4, 0.8, 2.6), CFrame.lookAt(at, at + along), colours[k % #colours + 1], false)
			step.CanQuery = false
		end
		-- The bracket: an arm from the leg's ring out under it, and a strut up to it.
		local root = frame.base + up * (h - 0.9) + out * (half - 0.2)
		beam(tower, "TowerStepArm", root, at - up * 0.9 + out * 0.6, 0.3, PALETTE.tower)
		beam(tower, "TowerStepStrut", root - up * 1.6, at - up * 0.9, 0.22, PALETTE.tower)
	end
end

-- ===== MOVING PEOPLE =====

-- Under the client's fade: covered, the place streamed in, set down, uncovered (as the squish room's lifts).
local function move(player: Player, to: Vector3, face: Vector3?, after: (() -> ())?)
	tell(player, "going")
	task.spawn(function()
		task.wait(FADE_WAIT)
		pcall(function()
			player:RequestStreamAroundAsync(to, 6)
		end)
		local root = rootOf(player)
		if root then
			root.CFrame = if face then CFrame.lookAt(to, to + face) else CFrame.new(to)
			root.AssemblyLinearVelocity = Vector3.zero
		end
		if after then
			after()
		end
		tell(player, "arrived")
	end)
end

local function toBottom(player: Player)
	local climber = climbers[player]
	if climber then
		climber.standIndex = 0
		climber.standY = ORIGIN.Y
		climber.falling = true
		player:SetAttribute("ClimbHeight", 0)
		player:SetAttribute("ClimbStep", 0)
	end
	move(player, world.arrive, world.arriveFace, function()
		local c = climbers[player]
		if c then
			c.falling = false
		end
	end)
end

function ClimbService.enter(player: Player)
	if player:GetAttribute("InClimb") then
		return
	end
	if player:GetAttribute("InLevel") or player:GetAttribute("InSquishRoom") then
		tell(player, "running")
		return
	end
	if not world.arrive then
		tell(player, "building")
		return
	end
	local Economy = economy()
	local saved = if Economy and Economy.climbBest then Economy.climbBest(player) else 0
	local best = math.max(saved, tonumber(player:GetAttribute("ClimbBest")) or 0)
	climbers[player] = { standY = ORIGIN.Y, standIndex = 0, best = best, startBest = best, submitted = best,
		lastSubmit = os.clock(), falling = true }
	player:SetAttribute("ClimbBest", math.floor(best))
	player:SetAttribute("ClimbHeight", 0)
	player:SetAttribute("ClimbStep", 0)
	player:SetAttribute("InClimb", true)
	move(player, world.arrive, world.arriveFace, function()
		local c = climbers[player]
		if c then
			c.falling = false
		end
	end)
end

-- OUT OF THE CLIMB WITHOUT GOING ANYWHERE (pass 266): your best kept, the climb's attributes off you. For someone put
-- into a level while still marked as climbing (the test panel's level, say): a fall there was a fall in the climb, and
-- put them back at its bottom.
function ClimbService.drop(player: Player)
	local climber = climbers[player]
	if climber then
		submit(player, climber)
	end
	climbers[player] = nil
	player:SetAttribute("InClimb", nil)
	player:SetAttribute("ClimbHeight", nil)
	player:SetAttribute("ClimbStep", nil)
end

function ClimbService.leave(player: Player)
	local back = world.lobbyArrive
	if not back or not workspace:FindFirstChild("Hub") then
		-- THE LOBBY IS AWAY FOR A RUN (pass 266, from your note: "I can't exit to the lobby from the climb ... it says when
		-- the run is on I can't exit"). Leave was refused and you were stuck up here. Now you go where everyone outside a
		-- run goes while the lobby is away: under the fade, a new character, which the server puts into the run.
		tell(player, "going")
		task.delay(FADE_WAIT, function()
			ClimbService.drop(player)
			if player.Parent == Players then
				player:LoadCharacter()
				task.wait(0.6)
				tell(player, "arrived")
			end
		end)
		return
	end
	local climber = climbers[player]
	if climber then
		submit(player, climber)
		climber.falling = true
	end
	move(player, back, Vector3.new(-1, 0, 0), function()
		climbers[player] = nil
		player:SetAttribute("InClimb", nil)
		player:SetAttribute("ClimbHeight", nil)
		player:SetAttribute("ClimbStep", nil)
	end)
end

function ClimbService.isClimbing(player: Player): boolean
	return player:GetAttribute("InClimb") == true
end

-- ===== EVERY TICK: where everyone is, what is built =====

local standParams = RaycastParams.new()
standParams.FilterType = Enum.RaycastFilterType.Exclude

local function stepIndexOf(hit: Instance?): number?
	local at = hit
	while at and at ~= workspace do
		local index = at:GetAttribute("ClimbStep")
		if typeof(index) == "number" then
			return index
		end
		at = at.Parent
	end
	return nil
end

local function track(player: Player, climber: Climber)
	local root = rootOf(player)
	if not root or climber.falling then
		return
	end
	local character = player.Character :: Model
	standParams.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -6, 0), standParams)
	if hit then
		local index = stepIndexOf(hit.Instance)
		if index then
			-- ONLY UP: a lower step is one your screen has taken away (ClimbClient), passed through on the way down.
			if index >= climber.standIndex then
				climber.standIndex = index
				climber.standY = hit.Position.Y
			end
		elseif hit.Instance:IsDescendantOf(world.bottomFolder) then
			if climber.standIndex >= FLOOR_FALL_FROM then
				submit(player, climber)
				tell(player, "fell", math.floor(metresAt(climber.standY)))
				toBottom(player)
				return
			end
			climber.standIndex = 0
			climber.standY = hit.Position.Y
		end
		player:SetAttribute("ClimbStep", climber.standIndex)
		local metres = metresAt(climber.standY)
		player:SetAttribute("ClimbHeight", math.floor(metres))
		if metres > climber.best + 0.5 then
			local before = climber.best
			climber.best = metres
			player:SetAttribute("ClimbBest", math.floor(metres))
			local Economy = economy()
			if Economy and Economy.climbed then
				local ok, paid = pcall(Economy.climbed, player, metres)
				if ok and typeof(paid) == "number" and paid > 0 then
					tell(player, "paid", paid)
				end
			end
			if math.floor(before / 25) < math.floor(metres / 25) then
				tell(player, "milestone", math.floor(metres / 25) * 25)
			end
		end
	end
	-- A FALL: well under the step you last stood on, or off the rock altogether.
	if (climber.standIndex > 0 and root.Position.Y < climber.standY - FALL_DROP) or root.Position.Y < ORIGIN.Y - 30 then
		submit(player, climber)
		tell(player, "fell", math.floor(metresAt(climber.standY)))
		toBottom(player)
	elseif os.clock() - climber.lastSubmit > SUBMIT_EVERY then
		submit(player, climber)
	end
end

local function keep()
	local wanted: { [number]: boolean } = {}
	local highest = KEEP_BOTTOM
	for index = 1, KEEP_BOTTOM do
		wanted[index] = true
	end
	for _, climber in pairs(climbers) do
		local from = math.max(1, climber.standIndex - BEHIND)
		local to = climber.standIndex + AHEAD
		highest = math.max(highest, to)
		for index = from, to do
			wanted[index] = true
		end
	end
	local built = 0
	for index = 1, highest do
		if wanted[index] and not steps[index] then
			buildStep(index)
			built += 1
			if built >= BUILD_PER_TICK then
				break
			end
		end
	end
	for index, model in pairs(steps) do
		if not wanted[index] then
			steps[index] = nil
			model:Destroy()
		end
	end
	local top = spotFor(highest).at.Y + 40
	growColumn(top)
	growClouds(top + 200)
end

-- ===== BUILT ONCE =====

function ClimbService.build(hubOrigin: Vector3)
	if world.built then
		return
	end
	world.built = true
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
	local remote = remotes:FindFirstChild("Climb")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "Climb"
		remote.Parent = remotes
	end
	world.remote = remote
	;(remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player, kind: any)
		if kind == "leave" and ClimbService.isClimbing(player) then
			ClimbService.leave(player)
		end
	end)
	-- THE STEPS YOUR SCREEN HAS TAKEN AWAY (ClimbClient) are in this group, which no character collides with.
	pcall(function()
		local physics = game:GetService("PhysicsService")
		for _, name in ipairs({ HIDDEN_GROUP, "VipGuests" }) do
			if not physics:IsCollisionGroupRegistered(name) then
				physics:RegisterCollisionGroup(name)
			end
		end
		physics:CollisionGroupSetCollidable(HIDDEN_GROUP, "Default", false)
		physics:CollisionGroupSetCollidable(HIDDEN_GROUP, "VipGuests", false)
		physics:CollisionGroupSetCollidable(HIDDEN_GROUP, HIDDEN_GROUP, false)
	end)
	ReplicatedStorage:SetAttribute("ClimbShowAhead", SHOW_AHEAD)
	ReplicatedStorage:SetAttribute("ClimbOriginY", ORIGIN.Y)
	ReplicatedStorage:SetAttribute("ClimbMetre", METRE)
	ReplicatedStorage:SetAttribute("ClimbHiddenGroup", HIDDEN_GROUP)
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(BOARD_STORE)
	end)
	boardStore = if ok then store else nil

	-- THE LOBBY'S TOWER and its board.
	local hub = workspace:FindFirstChild("Hub")
	if hub then
		buildTower(hub, hubOrigin)
	else
		warn("ClimbService: no lobby (workspace.Hub) to put the tower in.")
	end

	-- STUDIO ONLY: the test panel's "climb" takes you there, or back.
	if RunService:IsStudio() then
		local dev = remotes:WaitForChild("DevPanel", 10)
		if dev and dev:IsA("RemoteEvent") then
			dev.OnServerEvent:Connect(function(player: Player, action: any)
				if action ~= "climb" then
					return
				end
				if ClimbService.isClimbing(player) then
					ClimbService.leave(player)
				else
					ClimbService.enter(player)
				end
			end)
		end
	end

	-- A RESPAWN in the climb is the bottom.
	local function joined(player: Player)
		-- Put into a level (InLevel), you are out of the climb (pass 266).
		player:GetAttributeChangedSignal("InLevel"):Connect(function()
			if player:GetAttribute("InLevel") ~= nil and player:GetAttribute("InClimb") then
				ClimbService.drop(player)
			end
		end)
		player.CharacterAdded:Connect(function(character: Model)
			if not player:GetAttribute("InClimb") then
				return
			end
			character:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.25)
			if player:GetAttribute("InClimb") and world.arrive then
				toBottom(player)
			end
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		joined(player)
	end
	Players.PlayerAdded:Connect(joined)
	Players.PlayerRemoving:Connect(function(player: Player)
		local climber = climbers[player]
		if climber then
			submit(player, climber)
		end
		climbers[player] = nil
	end)

	-- THE PLACE.
	local folder = Instance.new("Folder")
	folder.Name = "Climb"
	folder.Parent = workspace
	local bottom = Instance.new("Folder")
	bottom.Name = "Bottom"
	bottom.Parent = folder
	world.bottomFolder = bottom
	local column = Instance.new("Folder")
	column.Name = "Column"
	column.Parent = folder
	world.columnFolder = column
	local clouds = Instance.new("Folder")
	clouds.Name = "Clouds"
	clouds.Parent = folder
	world.cloudFolder = clouds
	local stepsFolder = Instance.new("Folder")
	stepsFolder.Name = "Steps"
	stepsFolder.Parent = folder
	world.stepsFolder = stepsFolder
	columnTop = ORIGIN.Y
	buildBottom(bottom)
	pcall(MaterialAppearance.dress, folder)
	drawBoards()
	pickPads()
	local decorated, decorateErr = pcall(decorateTower)
	if not decorated then
		warn("ClimbService: the tower's little steps: " .. tostring(decorateErr))
	end
	keep()

	-- The board, read now and every so often.
	task.spawn(function()
		while true do
			readBoard(false)
			task.wait(BOARD_FRESH)
		end
	end)

	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since < 0.15 then
			return
		end
		since = 0
		for player, climber in pairs(climbers) do
			if player.Parent ~= Players or not player:GetAttribute("InClimb") then
				climbers[player] = nil
			else
				local okTrack, err = pcall(track, player, climber)
				if not okTrack then
					warn("ClimbService: " .. tostring(err))
				end
			end
		end
		local okKeep, keepErr = pcall(keep)
		if not okKeep then
			warn("ClimbService: building the steps: " .. tostring(keepErr))
		end
	end)
	print(("ClimbService: the climb is open, %d materials for its steps."):format(#pads))
end

ClimbService.STAMP = "a82c0090"
return ClimbService
