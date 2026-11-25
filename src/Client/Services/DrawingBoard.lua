--!strict
-- StarterPlayerScripts/Services/DrawingBoard.lua
-- THE EASEL IN THE SQUISH ROOM (the two-hundred-and-thirty-second pass, from your note of 2026-11-20: "do the free
-- drawing in the squish room"). SquishRoomService stands it against the front wall, right of the lift: paper on two
-- posts, a tray of seven paint pots, a rubber and a sponge. Roblox's own prompt "Draw" brings your view square onto the
-- paper and frees the cursor; then:
--
--   * press and drag on the paper (mouse or finger) to paint;
--   * touch a pot to take its colour (it lifts a little, so you can see which you hold), the rubber to rub out, the
--     sponge to wipe your drawing off;
--   * a controller: the left stick moves a brush ring over the paper, the right trigger paints, the right bumper takes
--     the next pot along, down on the pad wipes, B steps back (A, X and Y are left alone: the prompts and jumping use
--     them);
--   * walk, jump, or press Done to step back from it.
--
-- SHARED (the two-hundred-and-thirty-third pass, from your note of 2026-11-20: "make the drawings visible to other
-- players too"). Everyone's drawing is a see-through layer of its own on the same paper, so you see all of them at
-- once, yours on top. Your strokes go to the server in small batches (SquishRoomService checks them: you are in the
-- room, at the easel, not too fast, inside the sheet) and on to everyone else; it keeps them, so whoever comes in later
-- or has the room stream back in asks for the paper as it is ("sync"). The rubber and the sponge only ever touch your
-- own layer: nobody can rub out anyone else's picture. A player's drawing goes when they leave the server, and the
-- drawings of anyone you have blocked are never shown to you.

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local DrawingBoard = {}
DrawingBoard.VERSION = "the easel, shared, 2026-11-20"

-- Pixels of picture on the 12 by 7 stud paper, 64 a stud. SquishRoomService keeps the same size (EASEL_SHEET).
local SIZE = Vector2.new(768, 448)
local BRUSH = 5 -- pixels: the paint's radius, about a twelfth of a stud
local RUBBER = 16 -- pixels: the rubber's
local RUBBER_CODE = 8 -- a stroke is sent as a number: a paint's place on the tray (1 to 7), or this for the rubber
local SEND_EVERY = 0.1 -- seconds between batches of your strokes
local SEGMENT_POINTS = 150 -- points in one piece of a stroke before a new piece starts
local PAD_SPEED = 0.45 -- of the sheet a second, a controller's stick pushed all the way
local EASE = 0.45 -- seconds the view takes to come square onto the paper
local VIEW_STEP = "DrawingBoardView"
local PAD_ACTION = "DrawingBoardPad"
local OVER = Enum.ImageCombineType.BlendSourceOver
local CLEAR = Enum.ImageCombineType.Overwrite
-- The tray's paints in the order SquishRoomService sets them out (each pot's PaintIndex): Plum, Rose, Honey, Mint, Sky,
-- Soot, Chalk.
local PAINTS = {
	Color3.fromRGB(72, 44, 92),
	Color3.fromRGB(236, 128, 166),
	Color3.fromRGB(242, 168, 52),
	Color3.fromRGB(104, 192, 140),
	Color3.fromRGB(104, 158, 226),
	Color3.fromRGB(44, 40, 48),
	Color3.fromRGB(252, 250, 246),
}

type Sheet = { image: EditableImage }
type Segment = { any } -- { code, { x1, y1, x2, y2, ... } }
-- Every easel's layers, by where it stands (a part streamed away and back is a new part; the pictures are the same),
-- then by whose (a user id).
local layers: { [string]: { [number]: Sheet } } = {}
local papers: { [string]: BasePart } = {}

local state = {
	on = false,
	paper = nil :: BasePart?,
	key = "",
	sheet = nil :: Sheet?,
	from = CFrame.new(),
	started = 0,
	down = false,
	touch = nil :: InputObject?,
	last = nil :: Vector2?,
	code = 1,
	chosen = nil :: BasePart?,
	rests = {} :: { [BasePart]: Vector3 },
	cursor = Vector2.new(0.5, 0.5), -- a controller's brush, on the sheet (0 to 1 across and down)
	stick = Vector2.zero,
	padDown = false,
	pad = false, -- a controller was the last thing used
	warned = false,
	pending = {} :: { Segment }, -- your strokes not yet sent
	current = nil :: Segment?, -- the piece of stroke being drawn now
	dirty = false,
	sentAt = 0,
	blocked = {} :: { [number]: boolean },
	hideOthers = false, -- the easel's sign turned to ONLY MINE (on your screen only)
	remote = nil :: RemoteEvent?,
}
local ui: { [string]: any } = {}

local function me(): number
	return Players.LocalPlayer.UserId
end

local function keyOf(paper: BasePart): string
	local p = paper.Position
	return string.format("%d,%d,%d", math.round(p.X), math.round(p.Y), math.round(p.Z))
end

-- A layer's picture on its paper's face (put back whenever the paper streams in again). Yours drawn over the others.
local function attach(key: string, author: number, sheet: Sheet)
	local paper = papers[key]
	if not (paper and paper.Parent) then
		return
	end
	local name = "Drawing_" .. tostring(author)
	if paper:FindFirstChild(name) then
		return
	end
	local decal = Instance.new("Decal")
	decal.Name = name
	decal.Face = Enum.NormalId.Front
	decal.ZIndex = if author == me() then 2 else 1
	decal.Transparency = if author ~= me() and state.hideOthers then 1 else 0
	decal.TextureContent = Content.fromObject(sheet.image)
	decal.Parent = paper
end

local function layerFor(key: string, author: number, make: boolean): Sheet?
	if state.blocked[author] then
		return nil
	end
	local byAuthor = layers[key]
	if not byAuthor then
		byAuthor = {}
		layers[key] = byAuthor
	end
	local all = byAuthor :: { [number]: Sheet }
	local sheet = all[author]
	if not sheet and make then
		local ok, image = pcall(function()
			return AssetService:CreateEditableImage({ Size = SIZE })
		end)
		if not ok or not image then
			if not state.warned then
				state.warned = true
				warn("DrawingBoard: no picture to draw on (" .. tostring(image) .. ")")
			end
			return nil
		end
		local made: Sheet = { image = image :: EditableImage }
		all[author] = made
		sheet = made
	end
	if sheet then
		attach(key, author, sheet)
	end
	return sheet
end

local function clearSheet(sheet: Sheet)
	sheet.image:DrawRectangle(Vector2.zero, SIZE, Color3.new(1, 1, 1), 1, CLEAR)
end

local function dropLayer(key: string, author: number)
	local byAuthor = layers[key]
	local sheet = byAuthor and byAuthor[author]
	if byAuthor and sheet then
		byAuthor[author] = nil
		pcall(function()
			sheet.image:Destroy()
		end)
	end
	local paper = papers[key]
	local decal = paper and paper:FindFirstChild("Drawing_" .. tostring(author))
	if decal then
		decal:Destroy()
	end
end

-- Where on the sheet (0 to 1, across from the left as you face it, and down) a point on the paper is, and back.
local function uvOf(paper: BasePart, world: Vector3): Vector2
	local here = paper.CFrame:PointToObjectSpace(world)
	return Vector2.new(0.5 - here.X / paper.Size.X, 0.5 - here.Y / paper.Size.Y)
end

local function worldOf(paper: BasePart, uv: Vector2): Vector3
	return paper.CFrame:PointToWorldSpace(Vector3.new((0.5 - uv.X) * paper.Size.X, (0.5 - uv.Y) * paper.Size.Y,
		-paper.Size.Z / 2))
end

-- ===== PAINT =====

-- A line through `points` (x1, y1, x2, y2, ... in pixels) in paint `code`, carried on from `from` if given, in dabs
-- close enough to read as one line. Yours as you draw, and everyone's as it arrives.
local function paint(sheet: Sheet, code: number, points: { number }, from: Vector2?): Vector2?
	local rubber = code == RUBBER_CODE
	local colour = PAINTS[code] or PAINTS[1]
	local radius = if rubber then RUBBER else BRUSH
	local last = from
	for i = 1, #points - 1, 2 do
		local at = Vector2.new(points[i], points[i + 1])
		local start = last or at
		local steps = math.max(1, math.ceil((at - start).Magnitude / math.max(1, radius * 0.45)))
		for k = 1, steps do
			local p = start:Lerp(at, k / steps)
			local spot = Vector2.new(math.floor(p.X), math.floor(p.Y))
			if rubber then
				sheet.image:DrawCircle(spot, RUBBER, Color3.new(1, 1, 1), 1, CLEAR)
			else
				sheet.image:DrawCircle(spot, BRUSH, colour, 0, OVER)
			end
		end
		last = at
	end
	return last
end

local function paintAll(sheet: Sheet, segments: any)
	if type(segments) ~= "table" then
		return
	end
	for _, segment in ipairs(segments) do
		if type(segment) == "table" and type(segment[1]) == "number" and type(segment[2]) == "table" then
			paint(sheet, segment[1], segment[2], nil)
		end
	end
end

-- YOUR STROKES, SENT: in batches every SEND_EVERY, each piece of a stroke carrying on from the last point sent.
local function send(force: boolean?)
	local remote = state.remote
	if not (remote and state.dirty and state.key ~= "") then
		return
	end
	if not force and os.clock() - state.sentAt < SEND_EVERY then
		return
	end
	state.sentAt = os.clock()
	remote:FireServer("draw", state.key, state.pending)
	state.dirty = false
	local current = state.current
	local last = state.last
	if current and last then
		local carry: Segment = { current[1], { last.X, last.Y } }
		state.pending = { carry }
		state.current = carry
	else
		state.pending = {}
		state.current = nil
	end
end

local function endStroke()
	state.last = nil
	state.current = nil
	send(true)
	state.pending = {}
end

local function stroke(uv: Vector2)
	local sheet = state.sheet
	if not sheet then
		return
	end
	if uv.X < 0 or uv.X > 1 or uv.Y < 0 or uv.Y > 1 then
		state.last = nil
		state.current = nil
		return
	end
	local at = Vector2.new(math.floor(uv.X * SIZE.X), math.floor(uv.Y * SIZE.Y))
	paint(sheet, state.code, { at.X, at.Y }, state.last)
	local current = state.current
	if not current or current[1] ~= state.code or #current[2] >= SEGMENT_POINTS * 2 then
		local points = {}
		local last = state.last
		if last then
			table.insert(points, last.X)
			table.insert(points, last.Y)
		end
		local made: Segment = { state.code, points }
		table.insert(state.pending, made)
		state.current = made
		current = made
	end
	local points = (current :: Segment)[2]
	table.insert(points, at.X)
	table.insert(points, at.Y)
	state.last = at
	state.dirty = true
	send(false)
end

-- The sponge: your own layer off the paper, for everyone.
local function wipe()
	local sheet = state.sheet
	if sheet then
		clearSheet(sheet)
	end
	state.pending = {}
	state.current = nil
	state.last = nil
	state.dirty = false
	local remote = state.remote
	if remote and state.key ~= "" then
		remote:FireServer("wipe", state.key)
	end
end

-- A PRESS, HEARD: AudioService.press, the one soft felt tap every menu in the game makes (the two-hundred-and-thirty-
-- fourth pass): a pot taken, the sponge, the sign turned, the view coming onto the paper and leaving it.
local function pressSound(kind: string)
	local found = script.Parent and script.Parent:FindFirstChild("AudioService")
	if found and found:IsA("ModuleScript") then
		local ok, audio = pcall(require, found)
		if ok and type(audio) == "table" and type(audio.press) == "function" then
			pcall(audio.press, kind)
		end
	end
end

-- ===== THE TRAY =====

-- A pot (or the rubber, or the sponge) lifted `height` above where it stands, its paint with it.
local function raise(thing: BasePart, height: number)
	local rest = state.rests[thing]
	if not rest then
		rest = thing.Position
		state.rests[thing] = rest
	end
	local delta = (rest :: Vector3) + Vector3.new(0, height, 0) - thing.Position
	if delta.Magnitude < 1e-4 then
		return
	end
	thing.CFrame += delta
	for _, child in ipairs(thing:GetChildren()) do
		if child:IsA("BasePart") then
			child.CFrame += delta
		end
	end
end

local function trayNear(paper: BasePart): { BasePart }
	local list = {}
	for _, thing in ipairs(CollectionService:GetTagged("PaintPot")) do
		if thing:IsA("BasePart") and (thing.Position - paper.Position).Magnitude < 12 then
			table.insert(list, thing)
		end
	end
	table.sort(list, function(a, b)
		return uvOf(paper, a.Position).X < uvOf(paper, b.Position).X
	end)
	return list
end

local function choose(thing: BasePart)
	if thing:GetAttribute("Tool") == "wipe" then
		pressSound("close")
		wipe()
		raise(thing, 0.3)
		task.delay(0.22, function()
			raise(thing, 0)
		end)
		return
	end
	local previous = state.chosen
	if previous and previous ~= thing then
		raise(previous, 0)
	end
	if previous ~= thing then
		pressSound("tap")
	end
	state.chosen = thing
	raise(thing, 0.28)
	local index = thing:GetAttribute("PaintIndex")
	if thing:GetAttribute("Tool") == "rubber" then
		state.code = RUBBER_CODE
	elseif type(index) == "number" and PAINTS[index] then
		state.code = index
	end
	endStroke()
end

-- The right bumper: the next pot along (the rubber after the last paint, then round again; the sponge is down on the pad).
local function chooseNext()
	local paper = state.paper
	if not paper then
		return
	end
	local list = {}
	for _, thing in ipairs(trayNear(paper)) do
		if thing:GetAttribute("Tool") ~= "wipe" then
			table.insert(list, thing)
		end
	end
	if #list == 0 then
		return
	end
	local index = (table.find(list, state.chosen :: any) or 0) % #list + 1
	choose(list[index])
end

-- ===== WHERE YOU POINT =====

local function aim(screen: Vector2): (string?, any)
	local camera = workspace.CurrentCamera
	local paper = state.paper
	if not (camera and paper) then
		return nil, nil
	end
	local ray = camera:ScreenPointToRay(screen.X, screen.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local list: { Instance } = { paper }
	for _, thing in ipairs(trayNear(paper)) do
		table.insert(list, thing)
	end
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 80, params)
	if not hit then
		return nil, nil
	end
	if hit.Instance == paper then
		return "paper", uvOf(paper, hit.Position)
	end
	local thing: Instance = hit.Instance
	if not CollectionService:HasTag(thing, "PaintPot") and thing.Parent and thing.Parent:IsA("BasePart") then
		thing = thing.Parent
	end
	return "pot", thing
end

-- ===== THE VIEW =====

-- Square onto the paper, the whole sheet on screen whatever its shape: the tray in sight below it and a fifth of the
-- screen clear above it, where the lobby's vote card sits (first framed tight, the card covered the top of the sheet).
local function framing(paper: BasePart): CFrame
	local camera = workspace.CurrentCamera
	local up = paper.CFrame.UpVector
	local out = paper.CFrame.LookVector -- the paper's Front face looks this way
	local centre = paper.Position + up * 0.3
	local halfH = paper.Size.Y / 2 + 2.3
	local halfW = paper.Size.X / 2 + 0.8
	local tanV = math.tan(math.rad(camera.FieldOfView) / 2)
	local aspect = camera.ViewportSize.X / math.max(1, camera.ViewportSize.Y)
	local distance = math.max(halfH / tanV, halfW / (tanV * aspect))
	return CFrame.lookAt(centre + out * distance, centre, up)
end

local leave: () -> ()

-- YOU, OUT OF YOUR OWN WAY: the view stands where you do, so your head was between it and the paper, and with it your
-- name tags (their boards on your head), your crown and your pal (CosmeticsClient's, in workspace.CosmeticPieces, the
-- ones within a few studs of your head). Hidden on your screen only while you draw (everyone else still sees you at the
-- easel), and all back when you step away.
local hiddenTags: { [BillboardGui]: boolean } = {}
local hiddenPieces: { [BasePart]: boolean } = {}

local function hideSelf(hidden: boolean)
	local character = Players.LocalPlayer.Character
	if not hidden then
		for tag in pairs(hiddenTags) do
			if tag.Parent then
				tag.Enabled = true
			end
		end
		for piece in pairs(hiddenPieces) do
			if piece.Parent then
				piece.LocalTransparencyModifier = 0
			end
		end
		table.clear(hiddenTags)
		table.clear(hiddenPieces)
	end
	if not character then
		return
	end
	for _, piece in ipairs(character:GetDescendants()) do
		if piece:IsA("BasePart") or piece:IsA("Decal") then
			piece.LocalTransparencyModifier = if hidden then 1 else 0
		elseif hidden and piece:IsA("BillboardGui") and piece.Enabled then
			piece.Enabled = false
			hiddenTags[piece] = true
		end
	end
	local head = character:FindFirstChild("Head")
	local worn = workspace:FindFirstChild("CosmeticPieces")
	if hidden and worn and head and head:IsA("BasePart") then
		for _, piece in ipairs(worn:GetChildren()) do
			if piece:IsA("BasePart") and (piece.Position - head.Position).Magnitude < 6 then
				piece.LocalTransparencyModifier = 1
				hiddenPieces[piece] = true
			end
		end
	end
end

local function viewStep(dt: number)
	local camera = workspace.CurrentCamera
	local paper = state.paper
	if not (camera and paper and paper.Parent) then
		leave()
		return
	end
	local a = math.clamp((os.clock() - state.started) / EASE, 0, 1)
	a = a * a * (3 - 2 * a)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = state.from:Lerp(framing(paper), a)
	hideSelf(true)
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	-- A controller's brush ring, moved by the stick, painting while the right trigger is held.
	if state.stick.Magnitude > 0.15 then
		local push = Vector2.new(state.stick.X, -state.stick.Y)
		state.cursor = Vector2.new(math.clamp(state.cursor.X + push.X * PAD_SPEED * dt, 0, 1),
			math.clamp(state.cursor.Y + push.Y * PAD_SPEED * dt, 0, 1))
		if state.padDown then
			stroke(state.cursor)
		end
	end
	local ring = ui.ring
	if ring then
		ring.Visible = state.pad
		if state.pad then
			local spot = camera:WorldToViewportPoint(worldOf(paper, state.cursor))
			ring.Position = UDim2.fromOffset(spot.X, spot.Y)
		end
	end
	-- Walking or jumping away steps you back from it.
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and os.clock() - state.started > 0.4 and (humanoid.MoveDirection.Magnitude > 0.2 or humanoid.Jump) then
		leave()
	end
end

local function padAction(_: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	state.pad = true
	local key = input.KeyCode
	local began = inputState == Enum.UserInputState.Begin
	if key == Enum.KeyCode.Thumbstick1 then
		state.stick = if inputState == Enum.UserInputState.End then Vector2.zero
			else Vector2.new(input.Position.X, input.Position.Y)
	elseif key == Enum.KeyCode.ButtonR2 then
		state.padDown = began or inputState == Enum.UserInputState.Change
		if began then
			state.last = nil
			state.current = nil
			stroke(state.cursor)
		elseif not state.padDown then
			endStroke()
		end
	elseif key == Enum.KeyCode.ButtonR1 and began then
		chooseNext()
	elseif key == Enum.KeyCode.DPadDown and began then
		wipe()
	elseif key == Enum.KeyCode.ButtonB and began then
		leave()
	end
	return Enum.ContextActionResult.Sink
end

local function enter(paper: BasePart)
	if state.on then
		return
	end
	local key = keyOf(paper)
	papers[key] = paper
	local sheet = layerFor(key, me(), true)
	local camera = workspace.CurrentCamera
	if not (sheet and camera) then
		return
	end
	state.on = true
	state.paper = paper
	state.key = key
	state.sheet = sheet
	state.from = camera.CFrame
	state.started = os.clock()
	state.down = false
	state.padDown = false
	state.last = nil
	state.stick = Vector2.zero
	state.pad = UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1
	local prompt = paper:FindFirstChild("DrawPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end
	-- What you hold: the colour you last held here, or the first pot.
	local held = state.chosen
	if not (held and held.Parent) then
		local first = trayNear(paper)[1]
		if first then
			choose(first)
		end
	else
		raise(held :: BasePart, 0.28)
	end
	ui.gui.Enabled = true
	pressSound("open")
	RunService:BindToRenderStep(VIEW_STEP, Enum.RenderPriority.Camera.Value + 3, function(dt: number)
		local ok, err = pcall(viewStep, dt)
		if not ok then
			warn("DrawingBoard: " .. tostring(err))
			leave()
		end
	end)
	ContextActionService:BindActionAtPriority(PAD_ACTION, padAction, false, 3000, Enum.KeyCode.Thumbstick1,
		Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonR1, Enum.KeyCode.DPadDown, Enum.KeyCode.ButtonB)
end

leave = function()
	if not state.on then
		return
	end
	state.on = false
	state.down = false
	state.padDown = false
	endStroke()
	pcall(function()
		RunService:UnbindFromRenderStep(VIEW_STEP)
	end)
	ContextActionService:UnbindAction(PAD_ACTION)
	ui.gui.Enabled = false
	pressSound("close")
	local paper = state.paper
	if paper then
		local prompt = paper:FindFirstChild("DrawPrompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = true
		end
	end
	hideSelf(false)
	for thing in pairs(state.rests) do
		if thing.Parent then
			raise(thing, 0)
		end
	end
	-- The camera back over your shoulder, and Roblox's own again.
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if camera then
		if root and root:IsA("BasePart") then
			local flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
			local at = root.Position + Vector3.new(0, 1.5, 0)
			camera.CFrame = CFrame.lookAt(at - flat * 11 + Vector3.new(0, 3.5, 0), at)
		end
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end
end

-- ===== ON SCREEN WHILE YOU DRAW: a Done button, and a controller's brush ring =====

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- Named "Easel": ViewModeService frees the cursor while it is up, as for any card.
	local gui = Instance.new("ScreenGui")
	gui.Name = "Easel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 14
	gui.Enabled = false
	gui.Parent = playerGui
	ui.gui = gui
	local done = Instance.new("TextButton")
	done.Name = "Done"
	done.AnchorPoint = Vector2.new(0.5, 1)
	done.Position = UDim2.new(0.5, 0, 1, -28)
	done.Size = UDim2.fromOffset(132, 46)
	done.BackgroundColor3 = Color3.fromRGB(251, 234, 240)
	done.AutoButtonColor = true
	done.FontFace = Style.FONT.heading
	done.TextSize = 20
	done.TextColor3 = Color3.fromRGB(72, 44, 92)
	done.Text = "Done"
	done.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = done
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(114, 36, 62)
	edge.Thickness = 3
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = done
	done.Activated:Connect(function()
		leave()
	end)
	local ring = Instance.new("Frame")
	ring.Name = "BrushRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Size = UDim2.fromOffset(22, 22)
	ring.BackgroundTransparency = 1
	ring.Visible = false
	ring.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = ring
	local line = Instance.new("UIStroke")
	line.Color = Color3.fromRGB(72, 44, 92)
	line.Thickness = 2
	line.Parent = ring
	ui.ring = ring
end

-- ===== START =====

-- ===== EVERYONE ELSE'S =====

local function blockedNow()
	local ok, ids = pcall(function()
		return StarterGui:GetCore("GetBlockedUserIds")
	end)
	if ok and type(ids) == "table" then
		for _, id in ipairs(ids) do
			if type(id) == "number" then
				state.blocked[id] = true
			end
		end
	end
end

local function heard(kind: any, key: any, author: any, data: any)
	if type(key) ~= "string" then
		return
	end
	if kind == "all" then
		-- The paper as the server has it: every layer cleared and drawn again, yours too (the server's is the one).
		local byAuthor = layers[key]
		if byAuthor then
			for _, sheet in pairs(byAuthor) do
				clearSheet(sheet)
			end
		end
		if type(data) == "table" then
			for id, segments in pairs(data) do
				local who = tonumber(id)
				if who then
					local sheet = layerFor(key, who, true)
					if sheet then
						paintAll(sheet, segments)
					end
				end
			end
		end
		return
	end
	if type(author) ~= "number" then
		return
	end
	if kind == "draw" then
		if author ~= me() then
			local sheet = layerFor(key, author, true)
			if sheet then
				paintAll(sheet, data)
			end
		end
	elseif kind == "wipe" then
		local sheet = layerFor(key, author, false)
		if sheet then
			clearSheet(sheet)
		end
	elseif kind == "gone" then
		dropLayer(key, author)
	end
end

-- ===== EVERYONE'S OR ONLY MINE (the two-hundred-and-thirty-fourth pass) =====
--
-- The sign on the easel's arm. Turned to ONLY MINE, every other player's layer is hidden on your screen (still drawn
-- into as it arrives, so turning it back shows them as they are now); the sign's words and its prompt say which way it
-- is turned. Yours alone: nobody else's easel changes. It stays as you left it while you are in the server.
local function showToggle(sign: Instance)
	local gui = sign:FindFirstChildOfClass("SurfaceGui")
	local label = gui and gui:FindFirstChildOfClass("TextLabel")
	if label then
		label.Text = if state.hideOthers then "ONLY MINE" else "EVERYONE'S"
	end
	local prompt = sign:FindFirstChild("TogglePrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.ActionText = if state.hideOthers then "Show others' drawings" else "Hide others' drawings"
	end
end

local function setHideOthers(on: boolean)
	state.hideOthers = on
	local mine = "Drawing_" .. tostring(me())
	for _, paper in pairs(papers) do
		if paper.Parent then
			for _, decal in ipairs(paper:GetChildren()) do
				if decal:IsA("Decal") and decal.Name:sub(1, 8) == "Drawing_" and decal.Name ~= mine then
					decal.Transparency = if on then 1 else 0
				end
			end
		end
	end
	for _, sign in ipairs(CollectionService:GetTagged("EaselToggle")) do
		showToggle(sign)
	end
end

local function hookToggle(sign: Instance)
	showToggle(sign)
	local prompt = sign:WaitForChild("TogglePrompt", 10)
	if prompt and prompt:IsA("ProximityPrompt") then
		showToggle(sign)
		prompt.Triggered:Connect(function(player: Player)
			if player == Players.LocalPlayer then
				setHideOthers(not state.hideOthers)
				pressSound("tap")
			end
		end)
	end
end

function DrawingBoard.start()
	build()
	blockedNow()
	pcall(function()
		local blockedEvent = StarterGui:GetCore("PlayerBlockedEvent")
		blockedEvent.Event:Connect(function(player: Player)
			state.blocked[player.UserId] = true
			for key in pairs(layers) do
				dropLayer(key, player.UserId)
			end
		end)
	end)
	local remote = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("Easel", 20)
	if remote and remote:IsA("RemoteEvent") then
		state.remote = remote
		remote.OnClientEvent:Connect(function(kind: any, key: any, author: any, data: any)
			local ok, err = pcall(heard, kind, key, author, data)
			if not ok then
				warn("DrawingBoard: " .. tostring(err))
			end
		end)
	else
		warn("DrawingBoard: no RemoteEvents.Easel; paste the current server Bootstrap. Drawing stays your own.")
	end
	local function hook(paper: Instance)
		if not paper:IsA("BasePart") then
			return
		end
		-- Streamed in (or back in): the pictures on it, and the paper as it is now asked for.
		local key = keyOf(paper)
		papers[key] = paper
		for author, sheet in pairs(layers[key] or {}) do
			attach(key, author, sheet)
		end
		local remote = state.remote
		if remote then
			remote:FireServer("sync", key)
		end
		local prompt = paper:WaitForChild("DrawPrompt", 10)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Triggered:Connect(function(player: Player)
				if player == Players.LocalPlayer then
					enter(paper)
				end
			end)
		end
	end
	for _, paper in ipairs(CollectionService:GetTagged("DrawingPaper")) do
		task.spawn(hook, paper)
	end
	for _, sign in ipairs(CollectionService:GetTagged("EaselToggle")) do
		task.spawn(hookToggle, sign)
	end
	CollectionService:GetInstanceAddedSignal("EaselToggle"):Connect(function(sign: Instance)
		task.spawn(hookToggle, sign)
	end)
	CollectionService:GetInstanceAddedSignal("DrawingPaper"):Connect(function(paper: Instance)
		task.spawn(hook, paper)
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not state.on or processed then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			state.pad = false
			local what, value = aim(Vector2.new(input.Position.X, input.Position.Y))
			if what == "pot" then
				choose(value)
			elseif what == "paper" then
				state.down = true
				state.touch = if kind == Enum.UserInputType.Touch then input else nil
				state.last = nil
				state.current = nil
				stroke(value)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if not (state.on and state.down) then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseMovement or (kind == Enum.UserInputType.Touch and input == state.touch) then
			local what, value = aim(Vector2.new(input.Position.X, input.Position.Y))
			if what == "paper" then
				stroke(value)
			else
				state.last = nil
				state.current = nil
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or (kind == Enum.UserInputType.Touch and input == state.touch) then
			state.down = false
			state.touch = nil
			endStroke()
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		leave()
	end)
	print("DrawingBoard: running, " .. DrawingBoard.VERSION)
end

DrawingBoard.STAMP = "2584d982"
return DrawingBoard
