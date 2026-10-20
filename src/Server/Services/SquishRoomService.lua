--!strict
-- ServerScriptService/Services/SquishRoomService.lua
-- THE SQUISH ROOM: a hall with a real slab of every material in the game, to walk on, press, pop and
-- sink into for as long as you like. Reached by a lift in the lobby, and left by the lift inside it.
--
-- === Why it is like this ===
--
--   * THE REAL MATERIALS. Each slab is cloned from the chunk templates ChunkBuilder makes, visuals and
--     all, and registered with DeformationService like a level's: honey dents, bubble wrap pops, soap
--     crumbles, the Needoh charges your jump. Every material in MaterialConfig gets one, so a material
--     added later is in the room without anyone remembering to put it there.
--   * SET INTO THE FLOOR. Each slab's walking surface is flush with the floor; below it is a pit the
--     shape of everything the slab hangs underneath it (rigs, butter blocks, wax skirts), so nothing
--     pokes through and anything that gives way drops you a few studs onto the pit's floor, from where you
--     can jump out. Nothing in the room is a fall.
--   * FAR AWAY AND CLOSED IN. It stands well beyond every level's horizon (the furthest backdrop reaches
--     6200 studs), walls and ceiling all round, so it is never seen from anywhere else.
--   * IT KEEPS YOU. It is not part of the lobby, so it is not put away when a run starts, and anyone in it
--     is left out of the lobby's vote (HubService.hubPlayers): a run never drags you out of it. The way
--     back is refused, with a word why, while the lobby is away for a run.
--
-- Every structure stands on something: the slabs in the floor, the signs on two legs, the lamps on the
-- ceiling, the ceiling on the walls; the lifts are cabins on a plinth.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Materials = (require(Shared:WaitForChild("MaterialConfig")) :: any).Materials
local DeformationService = require(script.Parent:WaitForChild("DeformationService")) :: any
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local SquishRoomService = {}

-- Where the room stands: beyond every level's horizon (6200 studs at most) and the lobby's.
local ROOM_ORIGIN = Vector3.new(9000, 600, 9000)
-- Where the lobby's lift stands, from the lobby's origin: in the garden, its door toward the garden's middle (+X)
-- (the hundredth pass: LobbyLayout, where every place in the lobby is).
local LobbyLayout = require(Shared:WaitForChild("LobbyLayout"))
local LOBBY_LIFT_AT = LobbyLayout.AT.lift
local ROW_WIDTH = 104 -- studs of slabs across the hall
local GAP = 6 -- studs of floor between two slabs
local SIGN_STRIP = 4 -- studs of floor in front of each slab, for its name
local MARGIN = 12 -- studs of floor between the slabs and the walls
local LIFT_ZONE = 22 -- studs of floor in front of the slabs, for the lift and arriving
local WALL_HEIGHT = 22
local PIT_MAX = 6.4 -- studs: deeper than this and a fall into it could not be jumped out of
local FADE_WAIT = 0.3 -- seconds the client's fade takes before the move

local PALETTE = {
	floor = Color3.fromRGB(244, 238, 246),
	wall = Color3.fromRGB(214, 206, 236),
	trim = Color3.fromRGB(150, 132, 196),
	pit = Color3.fromRGB(176, 166, 196),
	ceiling = Color3.fromRGB(236, 232, 244),
	sign = Color3.fromRGB(251, 234, 240),
	ink = Color3.fromRGB(72, 44, 92),
	cabin = Color3.fromRGB(244, 192, 209),
	cabinTrim = Color3.fromRGB(114, 36, 62),
	lamp = Color3.fromRGB(255, 236, 206),
	shelf = Color3.fromRGB(198, 162, 120),
}

-- How each material is named on its sign.
local NAMES: { [string]: string } = {
	ButterWax = "Butter Wax", KineticSand = "Kinetic Sand", CreamyKeyboard = "Creamy Keyboard",
	Buttons = "Arcade Buttons", Foam = "Memory Foam", LightSwitch = "Light Switches",
	ChocolateSolid = "Solid Chocolate", LambsEar = "Lamb's Ear", JelloSoda = "Jello Soda",
	LavaKeys = "Lava Keys", ButterStick = "Butter Stick", BubbleWrap = "Bubble Wrap",
}

local room = {
	folder = nil :: Folder?,
	arrive = nil :: Vector3?, -- where you step out of the room's lift
	lobbyArrive = nil :: Vector3?, -- where you step out of the lobby's lift
	remote = nil :: RemoteEvent?,
	built = false,
}

-- ===== SMALL THINGS =====

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3,
	solid: boolean, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = solid
	p.CanTouch = solid
	p.CanQuery = solid
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A flat rectangle of floor from (x0, z0) to (x1, z1), its top at `y`.
local function floorPiece(parent: Instance, x0: number, z0: number, x1: number, z1: number, y: number)
	if x1 - x0 < 0.05 or z1 - z0 < 0.05 then
		return
	end
	part(parent, "Floor", Vector3.new(x1 - x0, 1, z1 - z0),
		CFrame.new((x0 + x1) / 2, y - 0.5, (z0 + z1) / 2), PALETTE.floor, true)
end

local function words(host: BasePart, face: Enum.NormalId, text: string, colour: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	gui.Parent = host
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.FontFace = Style.FONT.display
	label.TextColor3 = colour
	label.Text = text
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.Parent = label
end

local function spaced(name: string): string
	return NAMES[name] or (name:gsub("(%l)(%u)", "%1 %2"))
end

-- ===== THE SLABS =====

-- Waits for ChunkBuilder to have made the templates (it runs beside Bootstrap at start), then picks
-- one slab for each material: the one with the most cells that is not too big for the hall.
local function pickSlabs(): { { name: string, slab: BasePart } }
	local templates = ServerStorage:WaitForChild("ChunkTemplates", 60)
	if not templates then
		warn("SquishRoomService: no ServerStorage.ChunkTemplates (ChunkBuilder has not run), so the room is empty.")
		return {}
	end
	-- Until the count stops growing (ChunkBuilder adds them one by one).
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
	local best: { [string]: { slab: BasePart, cells: number, area: number } } = {}
	for _, item in ipairs(templates:GetDescendants()) do
		local name = item:IsA("BasePart") and item:GetAttribute("Material")
		if typeof(name) == "string" and Materials[name] then
			local slab = item :: BasePart
			local cells = 0
			for _, child in ipairs(slab:GetChildren()) do
				if child:IsA("BasePart") and child.Name:match("^SubRegion_") then
					cells += 1
				end
			end
			if cells > 0 then
				local area = slab.Size.X * slab.Size.Z
				local fits = slab.Size.X <= 18 and slab.Size.Z <= 18
				local held = best[name]
				local heldFits = held and held.slab.Size.X <= 18 and held.slab.Size.Z <= 18
				if not held or (fits and not heldFits) or (fits == heldFits and cells > held.cells) then
					best[name] = { slab = slab, cells = cells, area = area }
				end
			end
		end
	end
	local list = {}
	for name in pairs(Materials) do
		local found = best[name]
		if found then
			table.insert(list, { name = name, slab = found.slab })
		else
			warn("SquishRoomService: no template slab of " .. name .. ", so it is not in the room.")
		end
	end
	table.sort(list, function(a, b)
		return spaced(a.name) < spaced(b.name)
	end)
	return list
end

-- A slab, cloned with everything it carries, and measured: its walking surface (the top of its cells),
-- its own footprint (the hole in the floor) and the footprint and depth of all it hangs below (the pit).
type Pad = { name: string, model: Model, slab: BasePart, top: number, hole: Vector2, pit: Vector2, depth: number,
	centreOffset: Vector3 }

local function measure(name: string, source: BasePart): Pad
	local model = Instance.new("Model")
	model.Name = "Pad_" .. name
	local slab = source:Clone()
	slab.Parent = model
	model.PrimaryPart = slab
	local top = -math.huge
	for _, child in ipairs(slab:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^SubRegion_") then
			top = math.max(top, child.Position.Y + child.Size.Y / 2)
		end
	end
	local extent = slab.CFrame:VectorToWorldSpace(slab.Size)
	local hole = Vector2.new(math.abs(extent.X), math.abs(extent.Z))
	local box, size = model:GetBoundingBox()
	local bottom = box.Position.Y - size.Y / 2
	return {
		name = name,
		model = model,
		slab = slab,
		top = top,
		hole = hole,
		pit = Vector2.new(math.max(hole.X, size.X) + 1, math.max(hole.Y, size.Z) + 1),
		depth = math.clamp(top - bottom + 1, 3, PIT_MAX),
		-- From the slab's centre to the centre of its walking surface, kept through the move.
		centreOffset = Vector3.new(0, top - slab.Position.Y, 0),
	}
end

-- ===== THE LIFTS =====

-- A lift cabin on its plinth at `base` (its floor), its door facing `base.LookVector`; a call panel with
-- Roblox's own prompt; a sign over the door.
local function buildLift(parent: Instance, base: CFrame, sign: string, toward: string): ProximityPrompt
	local cabin = Instance.new("Model")
	cabin.Name = "Lift_" .. toward
	cabin.Parent = parent
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x, y, z)
	end
	part(cabin, "LiftPlinth", Vector3.new(7.4, 0.4, 7.4), at(0, 0.2, 0), PALETTE.cabinTrim, true)
	part(cabin, "LiftBack", Vector3.new(7, 10, 0.4), at(0, 5.4, 3.3), PALETTE.cabin, true)
	part(cabin, "LiftSide", Vector3.new(0.4, 10, 7), at(-3.3, 5.4, 0), PALETTE.cabin, true)
	part(cabin, "LiftSide", Vector3.new(0.4, 10, 7), at(3.3, 5.4, 0), PALETTE.cabin, true)
	part(cabin, "LiftJamb", Vector3.new(1.2, 10, 0.4), at(-2.9, 5.4, -3.3), PALETTE.cabin, true)
	part(cabin, "LiftJamb", Vector3.new(1.2, 10, 0.4), at(2.9, 5.4, -3.3), PALETTE.cabin, true)
	local lintel = part(cabin, "LiftLintel", Vector3.new(7, 1.8, 0.4), at(0, 9.5, -3.3), PALETTE.cabinTrim, true)
	words(lintel, Enum.NormalId.Front, sign, PALETTE.sign)
	part(cabin, "LiftRoof", Vector3.new(7.6, 0.5, 7.6), at(0, 10.65, 0), PALETTE.cabinTrim, true)
	-- A lamp in the roof, and the call panel on the right-hand wall inside.
	local lamp = part(cabin, "LiftLamp", Vector3.new(1.6, 0.25, 1.6), at(0, 10.27, 0), PALETTE.lamp, false)
	local light = Instance.new("PointLight")
	light.Color = PALETTE.lamp
	light.Brightness = 0.9
	light.Range = 10
	light.Parent = lamp
	local panel = part(cabin, "LiftPanel", Vector3.new(0.2, 1.6, 1), at(3.0, 4.2, -1.2), PALETTE.cabinTrim, false)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SquishLiftPrompt"
	prompt.ActionText = "Ride"
	prompt.ObjectText = toward
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = panel
	return prompt
end

-- ===== THE KEEPSAKE SHELF =====
--
-- Against the front wall, left of the lift home: a cubby for every keepsake in Harrow Bay (nine across, three
-- high), in the order of their materials' names, each with its toy and a card. The shelf is the same for
-- everyone; what is ON it is each player's own: JournalService shows the toys you have found (tag ShelfToy)
-- and a card for the ones you have not (ShelfEmpty), by journal id, and counts them on the board on top
-- (ShelfCount). Its prompt opens your journal at the keepsakes. Everything stands on something: the plinth
-- on the floor, the frame on the plinth, the toys and cards on its boards, the board on its top.
local SHELF_COLUMNS, SHELF_ROWS = 9, 3
local CUBBY = Vector3.new(3.2, 3, 2.2) -- inside each: wide, tall, deep
local SHELF_BOARD = 0.3
local SHELF_PLINTH = 0.8
local SHELF_LEFT = 26 -- studs left of the hall's middle to the shelf's: clear of the lift home

-- The toys are Interactables' (the same as out in the levels), looked for rather than waited on.
local Interactables: any = nil
do
	local module = script.Parent:FindFirstChild("Interactables")
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			Interactables = result
		end
	end
end

-- A toy sized to its cubby (never larger than it was made) and set down on the board, in the middle.
local function seat(toy: Model, x: number, floorY: number, z: number)
	local box, size = toy:GetBoundingBox()
	-- Scaled about its own middle, not about wherever its pivot happens to be.
	toy.WorldPivot = box
	local fit = math.min(1, (CUBBY.X - 0.6) / size.X, (CUBBY.Y - 0.5) / size.Y, (CUBBY.Z - 0.9) / size.Z)
	if fit < 1 then
		pcall(function()
			toy:ScaleTo(fit)
		end)
	end
	box, size = toy:GetBoundingBox()
	toy:PivotTo(toy:GetPivot() + Vector3.new(x - box.Position.X, floorY + size.Y / 2 - box.Position.Y, z - box.Position.Z))
end

local function buildShelf(folder: Folder, middleX: number, wallZ: number, y: number)
	local list = if Interactables and Interactables.toy and Interactables.keepsakeList then Interactables.keepsakeList() else {}
	if #list == 0 then
		warn("SquishRoomService: no keepsakes to put on the shelf (Interactables or Keepsakes missing).")
		return
	end
	local model = Instance.new("Model")
	model.Name = "KeepsakeShelf"
	model.Parent = folder
	local width = SHELF_COLUMNS * CUBBY.X + (SHELF_COLUMNS + 1) * SHELF_BOARD
	local height = SHELF_ROWS * CUBBY.Y + (SHELF_ROWS + 1) * SHELF_BOARD
	local depth = CUBBY.Z + SHELF_BOARD
	local base = y + SHELF_PLINTH
	local zMid = wallZ + depth / 2
	local plinth = part(model, "ShelfPlinth", Vector3.new(width, SHELF_PLINTH, depth), CFrame.new(middleX, y + SHELF_PLINTH / 2, zMid),
		PALETTE.trim, true)
	part(model, "ShelfBack", Vector3.new(width, height, SHELF_BOARD), CFrame.new(middleX, base + height / 2, wallZ + SHELF_BOARD / 2),
		PALETTE.shelf, true, Enum.Material.Wood)
	for row = 0, SHELF_ROWS do
		part(model, "ShelfBoard", Vector3.new(width, SHELF_BOARD, depth),
			CFrame.new(middleX, base + row * (CUBBY.Y + SHELF_BOARD) + SHELF_BOARD / 2, zMid), PALETTE.shelf, true, Enum.Material.Wood)
	end
	for column = 0, SHELF_COLUMNS do
		part(model, "ShelfUpright", Vector3.new(SHELF_BOARD, height, depth),
			CFrame.new(middleX - width / 2 + column * (CUBBY.X + SHELF_BOARD) + SHELF_BOARD / 2, base + height / 2, zMid),
			PALETTE.shelf, true, Enum.Material.Wood)
	end
	-- The board on top, standing on it, facing the hall; its words are each player's own count.
	local sign = part(model, "ShelfSign", Vector3.new(14, 1.8, 0.3), CFrame.new(middleX, base + height + 0.9, wallZ + 0.45),
		PALETTE.sign, false)
	words(sign, Enum.NormalId.Back, "KEEPSAKES", PALETTE.ink)
	CollectionService:AddTag(sign, "ShelfCount")
	for index, item in ipairs(list) do
		if index > SHELF_COLUMNS * SHELF_ROWS then
			break
		end
		local row = (index - 1) // SHELF_COLUMNS -- 0 is the top row
		local column = (index - 1) % SHELF_COLUMNS
		local x = middleX - width / 2 + SHELF_BOARD + column * (CUBBY.X + SHELF_BOARD) + CUBBY.X / 2
		local floorY = base + (SHELF_ROWS - 1 - row) * (CUBBY.Y + SHELF_BOARD) + SHELF_BOARD
		local z = wallZ + SHELF_BOARD + CUBBY.Z / 2
		local id = "keepsake:" .. item.thing
		-- Its toy, made as it is out in the levels, sized to the cubby and set down on the board.
		local toy = Interactables.toy(model, CFrame.new(x, floorY, z) * CFrame.Angles(0, math.pi, 0), item.material)
		if toy then
			toy.Name = "ShelfToy_" .. item.material
			seat(toy, x, floorY, z)
			toy:SetAttribute("JournalId", id)
			CollectionService:AddTag(toy, "ShelfToy")
		end
		-- And its card, standing on the board and leaning on the back: what shows until it is found.
		local card = part(model, "ShelfCard", Vector3.new(1.4, 1.4, 0.1),
			CFrame.new(x, floorY + 0.7, wallZ + SHELF_BOARD + 0.14) * CFrame.Angles(-0.12, 0, 0), PALETTE.sign, false)
		words(card, Enum.NormalId.Back, "?", PALETTE.ink)
		card:SetAttribute("JournalId", id)
		CollectionService:AddTag(card, "ShelfEmpty")
	end
	-- Roblox's own prompt, on the plinth: the journal, at the keepsakes (JournalService opens it).
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "KeepsakeShelfPrompt"
	prompt.ActionText = "Look"
	prompt.ObjectText = "Keepsakes"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = plinth
end

-- ===== THE HALL =====

local function buildHall(folder: Folder, pads: { Pad })
	local y = ROOM_ORIGIN.Y
	-- SHELF PACKING: left to right in rows of ROW_WIDTH, each cell a pit's width and a gap, each row as
	-- deep as its deepest pit, its sign strip and a gap.
	local x0 = ROOM_ORIGIN.X - ROW_WIDTH / 2
	local rows: { { pads: { Pad }, depth: number, width: number } } = {}
	local current = { pads = {}, depth = 0, width = 0 }
	for _, pad in ipairs(pads) do
		local cellWidth = pad.pit.X + GAP
		if current.width + cellWidth > ROW_WIDTH and #current.pads > 0 then
			table.insert(rows, current)
			current = { pads = {}, depth = 0, width = 0 }
		end
		table.insert(current.pads, pad)
		current.width += cellWidth
		current.depth = math.max(current.depth, SIGN_STRIP + pad.pit.Y + GAP)
	end
	if #current.pads > 0 then
		table.insert(rows, current)
	end
	local zStart = ROOM_ORIGIN.Z + LIFT_ZONE
	local z = zStart
	for _, row in ipairs(rows) do
		local rowZ0, rowZ1 = z, z + row.depth
		-- Centre the row across the hall.
		local x = x0 + (ROW_WIDTH - row.width) / 2
		floorPiece(folder, x0 - MARGIN, rowZ0, x, rowZ1, y)
		for _, pad in ipairs(row.pads) do
			local cellX0, cellX1 = x, x + pad.pit.X + GAP
			local cx = (cellX0 + cellX1) / 2
			local pitZ0 = rowZ0 + SIGN_STRIP + GAP / 2
			local cz = pitZ0 + pad.pit.Y / 2
			local hx0, hx1 = cx - pad.hole.X / 2, cx + pad.hole.X / 2
			local hz0, hz1 = cz - pad.hole.Y / 2, cz + pad.hole.Y / 2
			-- The floor round the hole.
			floorPiece(folder, cellX0, rowZ0, hx0, rowZ1, y)
			floorPiece(folder, hx1, rowZ0, cellX1, rowZ1, y)
			floorPiece(folder, hx0, rowZ0, hx1, hz0, y)
			floorPiece(folder, hx0, hz1, hx1, rowZ1, y)
			-- The pit under it: a floor to land on, and four walls up to the hall's floor.
			local px, pz = pad.pit.X, pad.pit.Y
			local bottom = y - pad.depth
			part(folder, "PitFloor", Vector3.new(px, 1, pz), CFrame.new(cx, bottom - 0.5, cz), PALETTE.pit, true)
			local wallH = pad.depth - 1
			for _, w in ipairs({
				{ Vector3.new(px, wallH, 0.6), Vector3.new(cx, bottom + wallH / 2, cz - pz / 2) },
				{ Vector3.new(px, wallH, 0.6), Vector3.new(cx, bottom + wallH / 2, cz + pz / 2) },
				{ Vector3.new(0.6, wallH, pz), Vector3.new(cx - px / 2, bottom + wallH / 2, cz) },
				{ Vector3.new(0.6, wallH, pz), Vector3.new(cx + px / 2, bottom + wallH / 2, cz) },
			}) do
				part(folder, "PitWall", w[1], CFrame.new(w[2]), PALETTE.pit, true)
			end
			-- The slab, its walking surface flush with the floor.
			local rotation = pad.slab.CFrame - pad.slab.CFrame.Position
			pad.model:PivotTo(CFrame.new(Vector3.new(cx, y, cz) - pad.centreOffset) * rotation)
			pad.model.Parent = folder
			for _, piece in ipairs(pad.model:GetDescendants()) do
				if piece:IsA("BasePart") and piece:GetAttribute("Material") then
					DeformationService.registerPlatform(piece)
				end
			end
			-- Its name, on a sign on two legs in the strip in front of it.
			local signZ = rowZ0 + SIGN_STRIP / 2
			for _, side in ipairs({ -1.9, 1.9 }) do
				part(folder, "SignLeg", Vector3.new(0.25, 1.6, 0.25), CFrame.new(cx + side, y + 0.8, signZ), PALETTE.trim, false)
			end
			local board = part(folder, "SignBoard", Vector3.new(5, 1.3, 0.25), CFrame.new(cx, y + 2.2, signZ), PALETTE.sign, false)
			words(board, Enum.NormalId.Front, spaced(pad.name), PALETTE.ink)
			x = cellX1
		end
		floorPiece(folder, x, rowZ0, x0 + ROW_WIDTH + MARGIN, rowZ1, y)
		z = rowZ1
	end
	local zEnd = z + MARGIN
	local xA, xB = x0 - MARGIN, x0 + ROW_WIDTH + MARGIN
	local zA = ROOM_ORIGIN.Z
	-- The floor in front of the slabs (the lift and arriving) and behind them.
	floorPiece(folder, xA, zA, xB, zStart, y)
	floorPiece(folder, xA, z, xB, zEnd, y)
	-- The walls, the ceiling resting on them, and a trim along the foot of the walls.
	local cx, cz = (xA + xB) / 2, (zA + zEnd) / 2
	local width, depth = xB - xA, zEnd - zA
	for _, w in ipairs({
		{ Vector3.new(width + 4, WALL_HEIGHT, 2), Vector3.new(cx, y + WALL_HEIGHT / 2, zA - 1) },
		{ Vector3.new(width + 4, WALL_HEIGHT, 2), Vector3.new(cx, y + WALL_HEIGHT / 2, zEnd + 1) },
		{ Vector3.new(2, WALL_HEIGHT, depth), Vector3.new(xA - 1, y + WALL_HEIGHT / 2, cz) },
		{ Vector3.new(2, WALL_HEIGHT, depth), Vector3.new(xB + 1, y + WALL_HEIGHT / 2, cz) },
	}) do
		part(folder, "Wall", w[1], CFrame.new(w[2]), PALETTE.wall, true)
	end
	for _, t in ipairs({
		{ Vector3.new(width, 1, 0.3), Vector3.new(cx, y + 0.5, zA + 0.15) },
		{ Vector3.new(width, 1, 0.3), Vector3.new(cx, y + 0.5, zEnd - 0.15) },
		{ Vector3.new(0.3, 1, depth), Vector3.new(xA + 0.15, y + 0.5, cz) },
		{ Vector3.new(0.3, 1, depth), Vector3.new(xB - 0.15, y + 0.5, cz) },
	}) do
		part(folder, "Skirting", t[1], CFrame.new(t[2]), PALETTE.trim, false)
	end
	part(folder, "Ceiling", Vector3.new(width + 4, 1.4, depth + 4), CFrame.new(cx, y + WALL_HEIGHT + 0.7, cz), PALETTE.ceiling, true)
	-- LAMPS on the ceiling, every 30 studs: real lights, warm and modest, and not too many.
	for lx = xA + 15, xB - 8, 30 do
		for lz = zA + 15, zEnd - 8, 30 do
			local lamp = part(folder, "CeilingLamp", Vector3.new(2.4, 0.4, 2.4), CFrame.new(lx, y + WALL_HEIGHT - 0.2, lz),
				PALETTE.lamp, false)
			local light = Instance.new("PointLight")
			light.Color = PALETTE.lamp
			light.Brightness = 1.1
			light.Range = 28
			light.Shadows = false
			light.Parent = lamp
		end
	end
	-- THE LIFT HOME, at the front, its door facing into the hall.
	local liftBase = CFrame.lookAt(Vector3.new(cx, y, zA + 8), Vector3.new(cx, y, zA + 20))
	local prompt = buildLift(folder, liftBase, "LOBBY", "Lobby")
	room.arrive = Vector3.new(cx, y + 3.5, zA + 15)
	prompt.Triggered:Connect(function(player: Player)
		SquishRoomService.leave(player)
	end)
	-- THE KEEPSAKE SHELF against the front wall (in front of its skirting), left of the lift.
	local shelfOk, shelfErr = pcall(buildShelf, folder, cx - SHELF_LEFT, zA + 0.3, y)
	if not shelfOk then
		warn("SquishRoomService: the keepsake shelf failed to build: " .. tostring(shelfErr))
	end
end

-- ===== IN AND OUT =====

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function tell(player: Player, kind: string)
	local remote = room.remote
	if remote then
		remote:FireClient(player, kind)
	end
end

-- THE MOVE, under the client's fade: "going" covers the screen, the place is streamed in around where you
-- are going (StreamingEnabled is on by default, and a floor 9000 studs away is not on your screen until
-- asked for), you are set down there, and "arrived" uncovers the screen. Never a fall into a half-loaded
-- room.
local function move(player: Player, to: Vector3, after: (() -> ())?)
	tell(player, "going")
	task.spawn(function()
		task.wait(FADE_WAIT)
		pcall(function()
			player:RequestStreamAroundAsync(to, 6)
		end)
		local root = rootOf(player)
		if root then
			root.CFrame = CFrame.new(to)
			root.AssemblyLinearVelocity = Vector3.zero
		end
		if after then
			after()
		end
		tell(player, "arrived")
	end)
end

function SquishRoomService.enter(player: Player)
	if player:GetAttribute("InSquishRoom") then
		return
	end
	-- NOT FROM A RUN (InLevel is set on a runner until the hub has them back): the run would wait for them.
	if player:GetAttribute("InLevel") then
		tell(player, "running")
		return
	end
	local arrive = room.arrive
	-- STILL BEING BUILT (it waits for ChunkBuilder's templates at start): say so, and stay.
	if not arrive then
		tell(player, "building")
		return
	end
	-- Out of the lobby's vote from this moment.
	player:SetAttribute("InSquishRoom", true)
	move(player, arrive)
end

function SquishRoomService.leave(player: Player)
	local back = room.lobbyArrive
	-- THE LOBBY IS AWAY while a run is on (HubService puts it in ServerStorage): stay, and be told why.
	if not back or not workspace:FindFirstChild("Hub") then
		tell(player, "closed")
		return
	end
	move(player, back, function()
		player:SetAttribute("InSquishRoom", nil)
	end)
end

function SquishRoomService.isInRoom(player: Player): boolean
	return player:GetAttribute("InSquishRoom") == true
end

-- Builds the hall (once the chunk templates exist) and the lobby's lift (into the lobby's own folder, so
-- it is put away with the lobby during a run). `hubOrigin` is HubService's.
function SquishRoomService.build(hubOrigin: Vector3)
	if room.built then
		return
	end
	room.built = true
	room.remote = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("SquishRoom") :: RemoteEvent

	-- THE LOBBY'S LIFT, in the garden, its door towards the garden's middle (+X).
	local hub = workspace:FindFirstChild("Hub")
	if hub then
		local base = hubOrigin + LOBBY_LIFT_AT
		local liftBase = CFrame.lookAt(base, base + Vector3.new(1, 0, 0))
		local prompt = buildLift(hub, liftBase, "SQUISH ROOM", "Squish Room")
		room.lobbyArrive = base + Vector3.new(7, 3.5, 0)
		prompt.Triggered:Connect(function(player: Player)
			SquishRoomService.enter(player)
		end)
	else
		warn("SquishRoomService: no lobby (workspace.Hub) to put the lift in.")
	end

	-- STUDIO ONLY: the test panel's "squish room" button takes you there, or back.
	if game:GetService("RunService"):IsStudio() then
		local dev = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("DevPanel", 10)
		if dev and dev:IsA("RemoteEvent") then
			dev.OnServerEvent:Connect(function(player: Player, action: any)
				if action ~= "squish" then
					return
				end
				if SquishRoomService.isInRoom(player) then
					SquishRoomService.leave(player)
				else
					SquishRoomService.enter(player)
				end
			end)
		end
	end

	-- A RESPAWN in the room keeps you there (Bootstrap puts a new character in the lobby or the run).
	local function joined(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			if not player:GetAttribute("InSquishRoom") then
				return
			end
			local root = character:WaitForChild("HumanoidRootPart", 10)
			task.wait(0.2)
			local arrive = room.arrive
			if root and root:IsA("BasePart") and arrive and player:GetAttribute("InSquishRoom") then
				move(player, arrive)
			end
		end)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		joined(player)
	end
	Players.PlayerAdded:Connect(joined)

	-- THE HALL, once ChunkBuilder's templates are there.
	local folder = Instance.new("Folder")
	folder.Name = "SquishRoom"
	folder.Parent = workspace
	room.folder = folder
	local pads = {}
	for _, picked in ipairs(pickSlabs()) do
		local ok, pad = pcall(measure, picked.name, picked.slab)
		if ok then
			table.insert(pads, pad)
		else
			warn("SquishRoomService: could not lay out " .. picked.name .. ": " .. tostring(pad))
		end
	end
	buildHall(folder, pads)
	print(("SquishRoomService: the squish room is open, %d materials."):format(#pads))
end

SquishRoomService.STAMP = "560d0f12"
return SquishRoomService
