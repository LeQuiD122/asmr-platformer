--!strict
-- StarterPlayerScripts/Services/OnboardingService.lua
-- THE FIRST FIVE MINUTES: what a new player needs to know, each thing once, and nothing over the level.
--
--   THE WELCOME     on a first visit: one short card in the shop's look (three pages until the 237th pass). What the game is (every
--                   platform is something to squish), how to get to the end (with the controls for
--                   the device you are on: keyboard, touch or controller), and what tokens are for.
--                   It ends with a choice: "Show me how to start" or "I'll look around".
--   THE GUIDE       in the lobby: a marker bobbing over each thing to step on, one at a time, City
--                   Shore, Chill, Short, then Start, and one line at the bottom saying why.
--   THE HINTS       in a level: the first time you ever stand on a material, one quiet line at the
--                   bottom says what it does, and fades. It never takes a press, never covers the
--                   middle of the screen, and each one is shown once (kept in your save).
--   THE WAY TO THE SHOP   after your first finished run, back in the lobby: a marker over the kiosk
--                   and one line, until you open the shop.
--
-- The server keeps what has been shown (EconomyService, "Onboarding"): this only says "shown".

local AvatarEditorService = game:GetService("AvatarEditorService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local OnboardingService = {}

-- AN ERROR ONCE, NOT EVERY FRAME: the step below runs every frame (or several times a second), and the same
-- failure said every frame buries everything else in Output, the paste check included.
local warnedOnce: { [string]: boolean } = {}
local function warnOnce(text: string)
	if not warnedOnce[text] then
		warnedOnce[text] = true
		warn(text .. " (shown once)")
	end
end
OnboardingService.VERSION = "the first five minutes, 2026-10-04"

-- WHAT EACH MATERIAL DOES, in one line, for its first time underfoot. Every material in MaterialConfig
-- has one (check_shop.py holds that). In plain words, never a trade mark (the hundred-and-fiftieth pass): the bricks,
-- the stress ball, the sculpting sand and the jelly.
local HINTS: { [string]: string } = {
	Honey = "Honey slows you down and sticks to your shoes for a while. Sticky shoes grip, even on ice.",
	ButterWax = "Waxed butter: whole wax is slippery and fast. Cracked, it is soft and slow.",
	KineticSand = "Sculpting sand pours away a moment after you step on it. Keep moving.",
	Slime = "Slime is springy. It can launch you up.",
	Soap = "Soap is slippery and crumbles under your feet. Don't stand still.",
	Cookie = "A cookie cracks, then crumbles under you. Keep going, and mind the bite.",
	CreamyKeyboard = "A creamy keyboard. A key you stand on goes down, types its letter, and springs back.",
	Salt = "Salt crust. Stand still and the crust around you tilts and sinks.",
	Lava = "Lava under a crust. Hot, and it bursts if you stay. Keep going.",
	Oobleck = "Oobleck. Keep moving or you sink. A hard landing turns it solid.",
	Buttons = "Arcade buttons: cyan for speed, violet stores a charge, pink to jump higher.",
	Snow = "Fresh snow is slow. Follow a trodden trail, packed snow is quicker.",
	Foam = "Memory foam is soft and slow and never drops you. Jumps off it are soft.",
	LightSwitch = "Light switches. Step on the raised half of a rocker to flip it.",
	Lego = "Toy bricks. Firm underfoot, but each brick works loose a moment after you step on it.",
	Charcoal = "Charcoal lights when you step on it. Burnt coal turns to ash and drops.",
	Chocolate = "Melted chocolate holds your feet. It melts through if you stand still.",
	ChocolateSolid = "Solid chocolate snaps a moment after you step on it.",
	Clay = "Sticky clay squeezes out to the edges. Jumps off it are short. Stay central.",
	Cloud = "Cloud wets your shoes, and it's gone a moment after you step on it.",
	LambsEar = "Lamb's ear. Soft and fuzzy, safe to stand on, and it wipes your shoes clean.",
	Ice = "Ice is slippery and cracks under you. Don't wait around.",
	JelloSoda = "Jelly wobbles under you and slows you a little.",
	Jellyfish = "A jellyfish bell. Bounce across it, and your shoes come off it wet.",
	LavaKeys = "Keys on lava. Each sinks while you stand on it, and every step wears it down.",
	ButterStick = "Soft butter. You sink in a little, and your shoes come away greasy.",
	Needoh = "A stress ball: stand still to squeeze it, then jump for a much bigger jump.",
	BubbleWrap = "Bubble wrap. Steps pop it, a jump pops a ring, and the popped wrap tears behind you.",
}

-- The journal's page for each material found says what it does in these same words (JournalService).
OnboardingService.HINTS = HINTS

-- THE LOBBY GUIDE: what to step on, in order, and why.
local GUIDE = {
	-- STRAIGHT TO THE START (the two-hundred-and-thirty-seventh pass). City Shore is the only level open to someone new
	-- and Chill is already chosen, and the mode and length keys moved to the workshop in the garden, so the old four steps
	-- walked a new player down the whole garden and back before their first run.
	{ pad = "StartPad", tag = "Start", say = "Step on Start for your first run, City Shore. Finishing it opens the next." },
}

local HINT_SECONDS = 5
local CLOSE_ACTION = "WelcomeClose"

local kit: any = nil
local ui: { [string]: any } = {}
local state = {
	data = nil :: any,
	welcomeOpen = false,
	welcomeShown = false,
	page = 1,
	guiding = false,
	guideStep = 0,
	queue = {} :: { string },
	showingHint = false,
	seen = {} :: { [string]: boolean },
	shopPointer = false,
	-- The favourite ask (stepFavourite): a run finished this session, how long the lobby has been quiet,
	-- and whether it has been asked.
	finishedRun = false,
	favouriteSince = nil :: number?,
	favouriteAsked = false,
	remote = nil :: RemoteEvent?,
}

local function note(what: string, name: string?)
	local remote = state.remote
	if remote then
		remote:FireServer(what, name)
	end
end

-- In the lobby itself: not on a level, and not in the squish room (where the lobby still stands, far away).
local function inLobby(): boolean
	local me = Players.LocalPlayer
	return me:GetAttribute("InLevel") == nil and not me:GetAttribute("InSquishRoom") and not me:GetAttribute("InClimb")
		and workspace:FindFirstChild("Hub") ~= nil
end

local function hubPart(name: string): BasePart?
	local hub = workspace:FindFirstChild("Hub")
	local part = hub and hub:FindFirstChild(name, true)
	return if part and part:IsA("BasePart") then part else nil
end

-- ===== THE LINE AT THE BOTTOM (hints, the guide's words): never pressable, never in the middle =====

local function ensureLine()
	if ui.lineGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hints"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 15
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ui.lineGui = gui
	local pill = kit.label(gui, "Line", "", kit.BODY, 18, kit.LOOK.ink)
	pill.Active = false
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, 60)
	pill.AutomaticSize = Enum.AutomaticSize.XY
	pill.Size = UDim2.new(0, 0, 0, 0)
	pill.TextWrapped = true
	pill.BackgroundTransparency = 0.08
	pill.BackgroundColor3 = kit.LOOK.tile
	pill.Visible = false
	kit.corner(pill, UDim.new(0, 18))
	kit.stroke(pill, kit.LOOK.edge, 3)
	local most = Instance.new("UISizeConstraint")
	most.MaxSize = Vector2.new(560, 200)
	most.Parent = pill
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = pill
	ui.line = pill
end

-- One line for `seconds` (or until replaced, if nil).
local function line(text: string, seconds: number?)
	ensureLine()
	local pill = ui.line
	pill.Text = text
	pill.Visible = true
	-- CLEAR OF THE LEVEL'S OPENING WORDS (the two-hundred-and-forty-first pass: on the Flooded Halls the first
	-- material's line and "14 August. Four minutes to midnight..." were printed over each other). StoryService
	-- puts those words low in the middle for about fifteen seconds as a level starts; while they are up, the line
	-- stands above them.
	local opening = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	opening = opening and opening:FindFirstChild("StoryOpening")
	local rest = if opening then UDim2.new(0.5, 0, 0.86, -150) else UDim2.new(0.5, 0, 1, -96)
	TweenService:Create(pill, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = rest }):Play()
	local stamp = os.clock()
	ui.lineAt = stamp
	if seconds then
		task.delay(seconds, function()
			if ui.lineAt == stamp then
				local out = TweenService:Create(pill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 1, 60) })
				out:Play()
				out.Completed:Once(function()
					if ui.lineAt == stamp then
						pill.Visible = false
					end
				end)
			end
		end)
	end
end

local function clearLine()
	ui.lineAt = os.clock()
	if ui.line then
		ui.line.Visible = false
		ui.line.Position = UDim2.new(0.5, 0, 1, 60)
	end
end

-- ===== A MARKER OVER SOMETHING IN THE LOBBY: "step here", bobbing =====

local function clearMarker()
	if ui.marker then
		ui.marker:Destroy()
		ui.marker = nil
	end
end

local function marker(part: BasePart, text: string)
	clearMarker()
	local board = Instance.new("BillboardGui")
	board.Name = "GuideMarker"
	board.Adornee = part
	board.AlwaysOnTop = true
	board.Size = UDim2.fromOffset(170, 96)
	board.StudsOffset = Vector3.new(0, 6, 0)
	board.MaxDistance = 400
	board.ResetOnSpawn = false
	board.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ui.marker = board
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = board
	local pill = kit.label(holder, "Tag", text, kit.CHUNKY, 22, kit.LOOK.amberInk)
	pill.BackgroundTransparency = 0
	pill.BackgroundColor3 = kit.LOOK.amber
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.fromScale(0.5, 0)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.new(0, 0, 0, 42)
	kit.corner(pill, UDim.new(0.5, 0))
	kit.stroke(pill, kit.LOOK.amberInk, 3)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = pill
	-- The arrow: a turned square under the pill, pointing down at the thing.
	local arrow = Instance.new("Frame")
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.new(0.5, 0, 0, 62)
	arrow.Size = UDim2.fromOffset(26, 26)
	arrow.Rotation = 45
	arrow.BackgroundColor3 = kit.LOOK.token
	arrow.Parent = holder
	kit.stroke(arrow, kit.LOOK.amberInk, 3)
	-- Bobbing, so it reads as "here" from across the room.
	local bob = TweenService:Create(holder, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.fromOffset(0, -10) })
	bob:Play()
end

-- ===== THE WELCOME =====

local function controlsText(): string
	if kit.usingPad() or (UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled) then
		return "Left stick to move, A to jump, right stick to look round. D-pad up opens your journal, D-pad down the menu."
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "The stick on the left to move, the button on the right to jump, drag to look round. The button top right is the menu."
	end
	return "WASD to move, Space to jump, Ctrl to lock the camera to your mouse. J opens your journal, Esc the menu."
end

-- ONE CARD, NOT THREE (the two-hundred-and-thirty-seventh pass, from your note of 2026-11-21 with the reel on how Roblox
-- recommends games: a player who leaves in the first minute or three counts against the game, so the fun has to start
-- in the first seconds). Three pages to read stood between joining and playing; now one says what the game is and how
-- to move, and "Let's go" sends you to the start.
local PAGES = {
	{ title = "Welcome to Harrow Bay",
		body = "Every platform here is something soft, squishy or crunchy to run across: honey, soap, bubble wrap, lava. Each level is a route of materials to its end, and finishing one opens the next. Every finish earns tokens for the shop, more with a friend running with you.",
		art = "controls" },
}

local function freeze(on: boolean)
	-- Counted with the shop's (ShopService.kit.hold), so neither frees you while the other is open.
	if kit.hold then
		kit.hold(on)
		return
	end
	local controls = kit.controls()
	if controls then
		pcall(function()
			if on then
				controls:Disable()
			else
				controls:Enable()
			end
		end)
	end
end

local function drawArt(frame: Frame, art: string)
	for _, old in ipairs(frame:GetChildren()) do
		if old:IsA("GuiObject") or old:IsA("UIListLayout") then
			old:Destroy()
		end
	end
	if art == "controls" then
		local words = kit.label(frame, "Controls", controlsText(), kit.BODY, 16, kit.LOOK.edge)
		words.Size = UDim2.fromScale(1, 1)
		words.TextWrapped = true
		words.BackgroundTransparency = 0
		words.BackgroundColor3 = kit.LOOK.panel
		kit.corner(words, UDim.new(0, 14))
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 12)
		pad.PaddingRight = UDim.new(0, 12)
		pad.Parent = words
		return
	end
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 14)
	row.Parent = frame
	if art == "tokens" then
		for _ = 1, 3 do
			kit.coin(frame, 48)
		end
		return
	end
	-- Three materials: honey, soap, bubble wrap.
	for k, colours in ipairs({
		{ Color3.fromRGB(239, 159, 39), Color3.fromRGB(99, 56, 6) },
		{ Color3.fromRGB(214, 236, 246), Color3.fromRGB(12, 68, 124) },
		{ Color3.fromRGB(244, 192, 209), Color3.fromRGB(114, 36, 62) },
	}) do
		local blob = Instance.new("Frame")
		blob.LayoutOrder = k
		blob.Size = UDim2.fromOffset(54, 54)
		blob.BackgroundColor3 = colours[1]
		blob.Parent = frame
		kit.corner(blob, UDim.new(0.5, 0))
		kit.stroke(blob, colours[2], 3)
	end
end

local function showPage(index: number)
	state.page = index
	local page = PAGES[index]
	ui.welcomeTitle.Text = page.title
	ui.welcomeBody.Text = page.body
	drawArt(ui.welcomeArt, page.art)
	for k, dot in ipairs(ui.dots) do
		dot.BackgroundColor3 = if k == index then kit.LOOK.edge else kit.LOOK.panel
	end
	local last = index == #PAGES
	ui.primaryWords.Text = if last then "Let's go" else "Next"
	ui.secondaryWords.Text = if last then "I'll look around" else "Skip"
	ui.secondary.Parent.Visible = not (last and not inLobby())
	if kit.usingPad() then
		GuiService.SelectedObject = ui.primary
	end
end

local function startGuide()
	if state.guiding or not inLobby() then
		return
	end
	state.guiding = true
	state.guideStep = 1
end

local function finishWelcome(guide: boolean)
	if not state.welcomeOpen then
		return
	end
	state.welcomeOpen = false
	ContextActionService:UnbindAction(CLOSE_ACTION)
	if GuiService.SelectedObject and ui.welcome and GuiService.SelectedObject:IsDescendantOf(ui.welcome) then
		GuiService.SelectedObject = nil
	end
	local scale = ui.welcomeScale
	local out = TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Scale = 0.85 })
	out:Play()
	out.Completed:Once(function()
		ui.welcome.Enabled = false
	end)
	freeze(false)
	note("welcomed")
	if guide and inLobby() then
		startGuide()
	else
		note("guided")
	end
end

local function buildWelcome()
	if ui.welcome then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Welcome"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 35
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ui.welcome = gui
	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.Active = true
	dim.BackgroundColor3 = Color3.fromRGB(4, 30, 26)
	dim.BackgroundTransparency = 0.4
	dim.Size = UDim2.fromScale(1, 1)
	dim.Parent = gui
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Active = true
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.new(0.92, 0, 0.9, 0)
	card.BackgroundColor3 = kit.LOOK.tile
	card.Parent = gui
	kit.corner(card, UDim.new(0, 26))
	kit.stroke(card, kit.LOOK.edge, 4)
	local most = Instance.new("UISizeConstraint")
	most.MaxSize = Vector2.new(560, 440)
	most.Parent = card
	local scale = Instance.new("UIScale")
	scale.Parent = card
	ui.welcomeScale = scale
	ui.card = card

	local title = kit.label(card, "Title", "", kit.CHUNKY, 30, kit.LOOK.pinkInk)
	title.Position = UDim2.new(0, 22, 0, 18)
	title.Size = UDim2.new(1, -44, 0, 40)
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	local titleMost = Instance.new("UITextSizeConstraint")
	titleMost.MaxTextSize = 30
	titleMost.Parent = title
	ui.welcomeTitle = title

	local art = Instance.new("Frame")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.Position = UDim2.new(0, 22, 0, 66)
	art.Size = UDim2.new(1, -44, 0.24, 0)
	art.Parent = card
	ui.welcomeArt = art

	local body = kit.label(card, "Body", "", kit.BODY, 18, kit.LOOK.ink)
	body.Position = UDim2.new(0, 22, 0.24, 76)
	body.Size = UDim2.new(1, -44, 0.76, -(76 + 104))
	body.TextWrapped = true
	body.TextScaled = true
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	local bodyMost = Instance.new("UITextSizeConstraint")
	bodyMost.MaxTextSize = 19
	bodyMost.MinTextSize = 12
	bodyMost.Parent = body
	ui.welcomeBody = body

	-- The dots: which page of three.
	local dots = Instance.new("Frame")
	dots.BackgroundTransparency = 1
	dots.AnchorPoint = Vector2.new(0.5, 1)
	dots.Position = UDim2.new(0.5, 0, 1, -84)
	dots.Size = UDim2.fromOffset(80, 12)
	dots.Parent = card
	local dotRow = Instance.new("UIListLayout")
	dotRow.FillDirection = Enum.FillDirection.Horizontal
	dotRow.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotRow.Padding = UDim.new(0, 8)
	dotRow.Parent = dots
	ui.dots = {}
	-- (No dots for a single card: one dot under it says nothing.)
	dots.Visible = #PAGES > 1
	for k = 1, #PAGES do
		local dot = Instance.new("Frame")
		dot.LayoutOrder = k
		dot.Size = UDim2.fromOffset(12, 12)
		dot.Parent = dots
		kit.corner(dot, UDim.new(0.5, 0))
		kit.stroke(dot, kit.LOOK.edge, 2)
		table.insert(ui.dots, dot)
	end

	-- The two buttons, thumb-sized.
	local height = kit.MIN_TOUCH + 9
	local primaryHolder, primary, primaryContent = kit.squishy(card, "Primary", kit.LOOK.token, kit.LOOK.tokenEdge)
	primaryHolder.AnchorPoint = Vector2.new(1, 1)
	primaryHolder.Position = UDim2.new(1, -18, 1, -16)
	primaryHolder.Size = UDim2.new(0.56, -24, 0, height)
	ui.primary = primary
	ui.primaryWords = kit.buttonWords(primaryContent, "Next", kit.LOOK.tokenInk, 20)
	ui.primaryWords.TextScaled = true
	local secondaryHolder, secondary, secondaryContent = kit.squishy(card, "Secondary", kit.LOOK.white, kit.LOOK.edge)
	secondaryHolder.AnchorPoint = Vector2.new(0, 1)
	secondaryHolder.Position = UDim2.new(0, 18, 1, -16)
	secondaryHolder.Size = UDim2.new(0.44, -12, 0, height)
	ui.secondary = secondary
	ui.secondaryWords = kit.buttonWords(secondaryContent, "Skip", kit.LOOK.ink, 20)
	for _, words in ipairs({ ui.primaryWords, ui.secondaryWords }) do
		words.TextScaled = true
		words.AutomaticSize = Enum.AutomaticSize.None
		words.Size = UDim2.new(1, -16, 1, -12)
		local most = Instance.new("UITextSizeConstraint")
		most.MaxTextSize = 20
		most.Parent = words
	end

	primary.Activated:Connect(function()
		kit.sound("buttonClick", 0.5)
		if state.page < #PAGES then
			showPage(state.page + 1)
		else
			finishWelcome(true)
		end
	end)
	secondary.Activated:Connect(function()
		kit.sound("buttonClick", 0.4)
		-- Skip from any page: the welcome is done and the guide is not wanted.
		finishWelcome(false)
	end)
end

local function showWelcome()
	if state.welcomeOpen or state.welcomeShown then
		return
	end
	state.welcomeShown = true
	buildWelcome()
	state.welcomeOpen = true
	ui.welcome.Enabled = true
	ui.welcomeScale.Scale = 0.8
	TweenService:Create(ui.welcomeScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	kit.sound("bubblePop", 0.5)
	showPage(1)
	freeze(true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			finishWelcome(false)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 25, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
end

-- ===== EVERY FEW FRAMES: the guide, the hints, the way to the shop =====

local function rootPart(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function stepGuide(root: BasePart)
	if not state.guiding then
		return
	end
	if not inLobby() then
		-- Gone into the run: the guide has done its job, and its words go with it.
		state.guiding = false
		clearMarker()
		clearLine()
		note("guided")
		return
	end
	local step = GUIDE[state.guideStep]
	if not step then
		state.guiding = false
		clearMarker()
		note("guided")
		line("Good luck. Your first level is on its way.", 4)
		return
	end
	local pad = hubPart(step.pad)
	if not pad then
		-- A lobby without that pad (an older HubService): skip the step rather than stall.
		state.guideStep += 1
		return
	end
	if not ui.marker or ui.marker.Adornee ~= pad then
		marker(pad, step.tag)
		line(step.say, nil)
	end
	local flat = Vector3.new(root.Position.X - pad.Position.X, 0, root.Position.Z - pad.Position.Z)
	local reach = math.max(pad.Size.X, pad.Size.Y, pad.Size.Z) / 2 + 1
	if flat.Magnitude <= reach and math.abs(root.Position.Y - pad.Position.Y) < 7 then
		kit.sound("buttonClick", 0.5)
		state.guideStep += 1
		clearMarker()
	end
end

-- The material under you: the slab (or a tile on it) carries a Material attribute.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function materialUnder(root: BasePart): string?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end
	rayParams.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -8, 0), rayParams)
	local part: Instance? = hit and hit.Instance
	for _ = 1, 4 do
		if not part then
			return nil
		end
		local name = part:GetAttribute("Material")
		if typeof(name) == "string" then
			return name
		end
		part = part.Parent
	end
	return nil
end

local function nextHint()
	if state.showingHint or #state.queue == 0 then
		return
	end
	local name = table.remove(state.queue, 1) :: string
	state.showingHint = true
	line(HINTS[name] :: string, HINT_SECONDS)
	note("hinted", name)
	task.delay(HINT_SECONDS + 0.6, function()
		state.showingHint = false
		nextHint()
	end)
end

local function stepHints(root: BasePart)
	if inLobby() or state.welcomeOpen then
		return
	end
	local name = materialUnder(root)
	if not name or not HINTS[name] or state.seen[name] then
		return
	end
	local data = state.data
	if data and data.hinted and data.hinted[name] then
		state.seen[name] = true
		return
	end
	-- NEVER A BACKLOG: three waiting at most (the squish room puts every material under your feet in a
	-- minute). One left out is not marked seen, so it comes the next time you stand on it.
	if #state.queue >= 3 then
		return
	end
	state.seen[name] = true
	table.insert(state.queue, name)
	nextHint()
end

local function shopOpen(): boolean
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local shop = playerGui and playerGui:FindFirstChild("Shop")
	local panel = shop and shop:FindFirstChild("Panel")
	return panel ~= nil and panel:IsA("GuiObject") and panel.Visible
end

local function stepShop()
	local data = state.data
	local due = data and data.ready and (data.earned or 0) > 0 and not data.shopIntro and inLobby() and not state.guiding
	if due and not state.shopPointer then
		local counter = hubPart("KioskCounter")
		if counter then
			state.shopPointer = true
			marker(counter, "Shop")
			line("You earned tokens. Spend them at the kiosk.", nil)
		end
	elseif state.shopPointer and (not due or shopOpen()) then
		state.shopPointer = false
		clearMarker()
		clearLine()
		if shopOpen() then
			note("shopIntro")
		end
	end
end

-- ===== THE FAVOURITE, asked once ever =====
--
-- After the way to the kiosk, back in the lobby from a finished run, with nothing else on the screen for a
-- few seconds: Roblox's own "favourite this game?" prompt, once, and not at all if it already is one. Noted
-- before it is asked, so it is never asked twice even if Roblox declines to show it.
local FAVOURITE_SETTLE = 6

local function stepFavourite()
	local data = state.data
	local due = data and data.ready and data.shopIntro and not data.askedFavourite and state.finishedRun
		and not state.favouriteAsked and inLobby() and not state.guiding and not state.welcomeOpen
		and not state.shopPointer and not shopOpen()
	if not due then
		state.favouriteSince = nil
		return
	end
	local now = os.clock()
	local since = state.favouriteSince
	if not since then
		state.favouriteSince = now
		return
	end
	if now - since < FAVOURITE_SETTLE then
		return
	end
	state.favouriteAsked = true
	note("favourite")
	task.spawn(function()
		local ok, already = pcall(function()
			return AvatarEditorService:GetFavoriteAsync(game.PlaceId, Enum.AvatarItemType.Asset)
		end)
		if ok and already == true then
			return
		end
		pcall(function()
			AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
		end)
	end)
end

-- ===== WHAT THE SERVER SAYS =====

-- AFTER THE ARRIVAL (the hundred-and-fifty-ninth pass): the join card (ReplicatedFirst's Arrival, `Arriving` on you
-- while it is up) gone first, for ARRIVAL_MOST seconds at the most, and then a moment to see the lobby.
local ARRIVAL_MOST = 25
local function afterArrival(fn: () -> ())
	task.spawn(function()
		local me = Players.LocalPlayer
		local untilAt = os.clock() + ARRIVAL_MOST
		while me:GetAttribute("Arriving") == true and os.clock() < untilAt do
			task.wait(0.2)
		end
		task.wait(1.5)
		fn()
	end)
end

local function accept(data: any)
	if type(data) ~= "table" or not data.ready then
		return
	end
	-- THE FIRST VISIT GIVEN BACK (the Studio test panel): everything shown is forgotten here too, so the
	-- welcome, the guide and the hints all come again.
	local before = state.data
	if before and before.welcomed and not data.welcomed then
		state.welcomeShown = false
		state.guiding = false
		state.guideStep = 0
		state.seen = {}
		state.queue = {}
		state.shopPointer = false
		clearMarker()
		clearLine()
	end
	-- A RUN FINISHED AFTER THE WAY TO THE KIOSK (more tokens earned than before, with the kiosk already shown),
	-- for the favourite ask: so it comes after the next run you chose to play, never straight after the
	-- kiosk. Or the test panel's "Favourite ask again" (asked, then not), which puts it due at once.
	if before and before.shopIntro and (data.earned or 0) > (before.earned or 0) then
		state.finishedRun = true
	end
	if before and before.askedFavourite and not data.askedFavourite and data.shopIntro then
		state.finishedRun = true
		state.favouriteAsked = false
	end
	state.data = data
	if not data.welcomed and not state.welcomeShown then
		-- A moment to see the lobby first, once it is there to be seen.
		afterArrival(showWelcome)
	elseif data.welcomed and not data.guided and not state.guiding and inLobby() then
		-- Left halfway through the guide last time: pick it up again.
		startGuide()
	end
end

function OnboardingService.start()
	local services = script.Parent
	local shopModule = services and services:WaitForChild("ShopService", 20)
	if not (shopModule and shopModule:IsA("ModuleScript")) then
		warn("OnboardingService: no ShopService beside it, so the welcome has no look to borrow. Paste "
			.. "src/Client/Services/ShopService.lua.")
		return
	end
	kit = (require(shopModule) :: any).kit
	if not kit then
		warn("OnboardingService: ShopService is an older copy without its kit. Paste src/Client/Services/ShopService.lua.")
		return
	end
	local events = ReplicatedStorage:WaitForChild("RemoteEvents")
	local functions = ReplicatedStorage:WaitForChild("RemoteFunctions")
	state.remote = events:WaitForChild("Onboarding", 20) :: RemoteEvent?
	local update = events:WaitForChild("ShopUpdate", 20)
	local ask = functions:WaitForChild("ShopState", 20)
	if not (state.remote and update and ask) then
		warn("OnboardingService: its remotes are missing (Onboarding, ShopUpdate, ShopState). Paste "
			.. "src/Server/Bootstrap.server.lua.")
		return
	end
	;(update :: RemoteEvent).OnClientEvent:Connect(accept)
	task.spawn(function()
		-- The save may still be loading: ask until it answers ready.
		for _ = 1, 20 do
			local ok, data = pcall(function()
				return (ask :: RemoteFunction):InvokeServer()
			end)
			if ok and type(data) == "table" and data.ready then
				accept(data)
				return
			end
			task.wait(1)
		end
	end)
	-- A MATERIAL FOUND (EconomyService.foundMaterial, your MaterialsFound going up): a soft chime, and nothing on the
	-- screen; the journal and the lobby's board keep it.
	local me = Players.LocalPlayer
	local shownFound = tonumber(me:GetAttribute("MaterialsFound"))
	me:GetAttributeChangedSignal("MaterialsFound"):Connect(function()
		local now = tonumber(me:GetAttribute("MaterialsFound")) or 0
		if shownFound ~= nil and now > shownFound and kit then
			kit.sound("bubblePop", 0.35)
		end
		shownFound = now
	end)
	local last = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - last < 0.25 then
			return
		end
		last = now
		local root = rootPart()
		if not root then
			return
		end
		local ok, err = pcall(function()
			stepGuide(root)
			stepHints(root)
			stepShop()
			stepFavourite()
		end)
		if not ok then
			warnOnce("OnboardingService: " .. tostring(err))
		end
	end)
	print("OnboardingService: running, " .. OnboardingService.VERSION)
end

OnboardingService.STAMP = "b1aed416"
return OnboardingService
