--!strict
-- StarterPlayerScripts/Services/TalkClient.lua
-- WHAT YOU SAY TO THEM, on your screen (the hundred-and-fourth pass, your idea: "I want to say the lines to them
-- myself, and I can choose not to talk to them by simply walking away from them far enough that the options of what
-- to say disappear by themselves").
--
-- When you talk to someone (F, or Y on a controller), Townsfolk sends what you could say to them; up to three things
-- come up low in the middle of the screen, each in the one speech bubble everyone speaks in (Style.BUBBLE: cream, dark
-- ink, the bold face, a dark rim; since the hundred-and-nineteenth pass, from your test: "you see the stylistic
-- difference between the script and my options of what to say? They should have the same style"), each with its
-- number in a dark coin that turns gold on the one you are on; they pop up one after another. Choose one with the
-- mouse, a tap, its number key, or the controller (the first is selected for you; B puts them away) and the server has
-- you say it and them answer; then what else you could say comes up. Walk further from them than Conversations.REACH
-- and the choices fade away by themselves. Nothing else on the screen changes.
--
-- STYLED FURTHER (the hundred-and-twenty-third pass, from your test: "the text between character and the player could
-- be styled better"). Over the choices, who you are talking to: their initial on a disc in their own colour, and the
-- question. Each choice a card lit from above on a soft shadow; the one you are on lifts off its shadow and leans
-- toward you, its rim and number gold and an arrow at its end; something you have never said to anyone, in any run, is
-- marked New (what you have said before comes back each time you start a level). And every speech bubble over a head,
-- theirs and yours, is written out a letter at a time as it comes up, its name tag and shadow there at once.
--
-- UNDER YOU, AND WHO THEY ARE (the two-hundredth pass, from your note of 2026-11-05: "the UI of the characters talking,
-- the speech boxes and interactions"). Seen in play, the choices stood a hundred and fifty pixels up the screen, three
-- cards and a heading tall, which put them across your own character's middle; now they sit DOCK.low from the bottom
-- (DOCK.touch on a touch screen, over the thumbs) and you stay in sight above them. Over them, who you are talking to:
-- their own face, a likeness of their head as they stand there, in the disc in their colour (their initial if no likeness
-- can be made), then their name and "What do you say?". And while they think what to answer, three dots over their head
-- come up one by one (Townsfolk.think): the bubble tagged ThinkingBubble.

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local TalkClient = {}

local Conversations: any = (function(): any
	local found = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Conversations", 10)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()

type Option = { id: string, say: string, fresh: boolean? }
type Offer = { person: string, title: string, head: BasePart, tint: Color3?, options: { Option } }
local ui = {
	gui = nil :: ScreenGui?,
	holder = nil :: Frame?,
	list = nil :: Frame?,
	eyebrow = nil :: TextLabel?,
	portrait = nil :: Frame?,
	initial = nil :: TextLabel?,
	offer = nil :: Offer?,
	remote = nil :: RemoteEvent?,
	watch = nil :: RBXScriptConnection?,
	buttons = {} :: { TextButton },
	slots = {} :: { Frame },
	low = 0,
}
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
-- Letters a second a speech bubble is written out at: quicker than reading, so it is never waited on.
local WRITE_RATE = 48
-- WHERE THE CHOICES SIT (the two-hundredth pass): `low` pixels up from the bottom of the screen with a keyboard or a
-- controller, `touch` on a touch screen (over the thumbstick and the jump button), and `away` further down as they come
-- and go.
local DOCK = { low = 26, touch = 104, away = 20 }
-- THE LIKENESS (the same pass): how far in front of their face the little camera stands (studs), how high over its
-- middle, and how wide it sees (degrees), so the head fills the disc.
local LIKENESS = { back = 3.4, up = 0.25, fov = 26 }
-- THE THREE DOTS (the same pass): how long each dot takes to come up while they think.
local DOT_EVERY = 0.28

-- A PRESS, HEARD (the hundred-and-forty-fourth pass): AudioService.press, the one soft sound every menu in the game makes
-- (a felt tap, two notes up as a card opens and down as it goes). The words you choose made none.
local function pressSound(kind: string)
	local found = script.Parent and script.Parent:FindFirstChild("AudioService")
	if found and found:IsA("ModuleScript") then
		local ok, audio = pcall(require, found)
		if ok and type(audio) == "table" and type(audio.press) == "function" then
			audio.press(kind)
		end
	end
end

local function usingPad(): boolean
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.Gamepad1 or (UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled)
end

local function rounded(f: GuiObject, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = f
end

local function build()
	if ui.gui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Talk"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.DisplayOrder = 6
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ui.gui = gui
	-- Low in the middle, under your character (DOCK, the two-hundredth pass; over the thumbs on a touch screen), as wide
	-- as a phone allows.
	local holder = Instance.new("Frame")
	holder.Name = "Choices"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -DOCK.low)
	holder.Size = UDim2.new(0.9, 0, 0, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local most = Instance.new("UISizeConstraint")
	most.MaxSize = Vector2.new(480, math.huge)
	most.Parent = holder
	Style.fit(holder, Vector2.new(480, 250))
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	ui.holder = holder
	local eyebrow = Instance.new("TextLabel")
	eyebrow.Name = "Eyebrow"
	eyebrow.LayoutOrder = 0
	-- WHO YOU ARE TALKING TO, in a bubble of its own over the choices: at its start their face on a disc in their own
	-- colour (what they wear), a little bigger than the bubble so it stands out of it like a medal; then their name, and
	-- the question in a lighter ink (RichText, show).
	eyebrow.Size = UDim2.fromOffset(0, 40)
	eyebrow.AutomaticSize = Enum.AutomaticSize.X
	eyebrow.BackgroundColor3 = Style.BUBBLE.fill
	eyebrow.FontFace = Style.BUBBLE.font
	eyebrow.TextSize = Style.SIZE.body
	eyebrow.TextColor3 = Style.BUBBLE.ink
	eyebrow.RichText = true
	eyebrow.Text = ""
	rounded(eyebrow, Style.RADIUS.pill)
	local eyebrowRim = Instance.new("UIStroke")
	eyebrowRim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	eyebrowRim.Color = Style.BUBBLE.rim
	eyebrowRim.Thickness = Style.BUBBLE.stroke
	eyebrowRim.Parent = eyebrow
	local eyebrowPad = Instance.new("UIPadding")
	eyebrowPad.PaddingLeft, eyebrowPad.PaddingRight = UDim.new(0, 56), UDim.new(0, 18)
	eyebrowPad.Parent = eyebrow
	local portrait = Instance.new("Frame")
	portrait.Name = "Portrait"
	portrait.AnchorPoint = Vector2.new(0, 0.5)
	portrait.Position = UDim2.new(0, -54, 0.5, 0)
	portrait.Size = UDim2.fromOffset(46, 46)
	portrait.BackgroundColor3 = Style.COLOUR.accent
	portrait.BorderSizePixel = 0
	portrait.Parent = eyebrow
	rounded(portrait, Style.RADIUS.pill)
	local portraitRim = Instance.new("UIStroke")
	portraitRim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	portraitRim.Color = Style.BUBBLE.rim
	portraitRim.Thickness = Style.BUBBLE.stroke
	portraitRim.Parent = portrait
	local initial = Instance.new("TextLabel")
	initial.Name = "Initial"
	initial.BackgroundTransparency = 1
	initial.Size = UDim2.fromScale(1, 1)
	initial.FontFace = Style.FONT.display
	initial.TextSize = Style.SIZE.title
	initial.TextColor3 = Style.BUBBLE.ink
	initial.Text = ""
	initial.Parent = portrait
	eyebrow.Parent = holder
	ui.eyebrow = eyebrow
	ui.portrait = portrait
	ui.initial = initial
	local list = Instance.new("Frame")
	list.Name = "List"
	list.LayoutOrder = 1
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.Parent = holder
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 10)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
	ui.list = list
end

-- A CHOICE SEEN OR GONE: the card, its rim, its shadow, its number, its New and its words together, `to` 0 seen and 1
-- gone, and a little smaller as it goes. (Its arrow only ever shows on the one you are on.)
local function fade(button: TextButton, to: number, seconds: number)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad)
	TweenService:Create(button, info, { BackgroundTransparency = to, TextTransparency = to }):Play()
	local rim = button:FindFirstChildOfClass("UIStroke")
	if rim then
		TweenService:Create(rim, info, { Transparency = to }):Play()
	end
	for _, name in ipairs({ "Number", "New" }) do
		local chip = button:FindFirstChild(name)
		if chip and chip:IsA("TextLabel") then
			TweenService:Create(chip, info, { BackgroundTransparency = to, TextTransparency = to }):Play()
			local chipRim = chip:FindFirstChildOfClass("UIStroke")
			if chipRim then
				TweenService:Create(chipRim, info, { Transparency = to }):Play()
			end
		end
	end
	local arrow = button:FindFirstChild("Arrow")
	if arrow and arrow:IsA("TextLabel") and to == 1 then
		TweenService:Create(arrow, info, { TextTransparency = 1 }):Play()
	end
	local slot = button.Parent
	local shade = slot and slot:FindFirstChild("Shade")
	if shade and shade:IsA("Frame") then
		TweenService:Create(shade, info, { BackgroundTransparency = if to == 1 then 1 else Style.BUBBLE.shade }):Play()
	end
	local grow = button:FindFirstChildOfClass("UIScale")
	if grow and to == 1 then
		TweenService:Create(grow, info, { Scale = 0.9 }):Play()
	end
end

local function hide()
	local gui = ui.gui
	ui.offer = nil
	if ui.watch then
		ui.watch:Disconnect()
		ui.watch = nil
	end
	ContextActionService:UnbindAction("TalkChoose")
	local selected = GuiService.SelectedObject
	if selected and gui and selected:IsDescendantOf(gui) then
		GuiService.SelectedObject = nil
	end
	if gui and gui.Enabled then
		local holder = ui.holder
		if holder then
			TweenService:Create(holder, TweenInfo.new(0.18, Enum.EasingStyle.Quad),
				{ Position = UDim2.new(0.5, 0, 1, -ui.low + DOCK.away) }):Play()
		end
		for _, button in ipairs(ui.buttons) do
			fade(button, 1, 0.16)
		end
		task.delay(0.2, function()
			if not ui.offer then
				gui.Enabled = false
			end
		end)
	end
end

local function choose(index: number)
	local offer = ui.offer
	local remote = ui.remote
	if not (offer and remote) then
		return
	end
	local option = offer.options[index]
	if not option then
		return
	end
	remote:FireServer("say", offer.person, option.id)
	hide()
end

-- ONE CHOICE: a slot holding the card and the soft shadow it stands on, so the card can lift off it.
local function option(index: number, entry: Option): (Frame, TextButton)
	local bubble = Style.BUBBLE
	local slot = Instance.new("Frame")
	slot.Name = "Choice" .. index
	slot.LayoutOrder = index
	slot.BackgroundTransparency = 1
	slot.Size = UDim2.new(1, 0, 0, 0)
	slot.AutomaticSize = Enum.AutomaticSize.Y
	local shade = Instance.new("Frame")
	shade.Name = "Shade"
	shade.Position = UDim2.fromOffset(0, 4)
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = bubble.ink
	shade.BackgroundTransparency = bubble.shade
	shade.BorderSizePixel = 0
	shade.Parent = slot
	rounded(shade, bubble.radius)
	local button = Instance.new("TextButton")
	button.Name = "Card"
	button.AutoButtonColor = false
	button.Size = UDim2.new(1, 0, 0, 46)
	button.AutomaticSize = Enum.AutomaticSize.Y
	button.BackgroundColor3 = bubble.fill
	button.FontFace = bubble.font
	button.TextSize = bubble.text
	button.TextColor3 = bubble.ink
	button.TextWrapped = true
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Text = entry.say
	button.ZIndex = 2
	-- LIT FROM ABOVE, like the bubbles over their heads.
	local light = Instance.new("UIGradient")
	light.Rotation = 90
	light.Color = ColorSequence.new(bubble.top, bubble.fill)
	light.Parent = button
	rounded(button, bubble.radius)
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = bubble.rim
	edge.Thickness = bubble.stroke
	edge.Parent = button
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 52)
	pad.PaddingRight = UDim.new(0, 36)
	pad.PaddingTop = UDim.new(0, 11)
	pad.PaddingBottom = UDim.new(0, 11)
	pad.Parent = button
	local grow = Instance.new("UIScale")
	grow.Parent = button
	-- Its number, in a dark coin at its left (the bubble's ink, the number in its cream); gold when it is the one you
	-- are on.
	local chip = Instance.new("TextLabel")
	chip.Name = "Number"
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.Position = UDim2.new(0, -40, 0.5, 0)
	chip.Size = UDim2.fromOffset(28, 28)
	chip.BackgroundColor3 = bubble.ink
	chip.FontFace = bubble.font
	chip.TextSize = Style.SIZE.body
	chip.TextColor3 = bubble.fill
	chip.Text = tostring(index)
	chip.ZIndex = 3
	chip.Parent = button
	rounded(chip, Style.RADIUS.pill)
	-- THE ARROW at its end, on the one you are on: you are about to say it.
	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(1, 0.5)
	arrow.Position = UDim2.new(1, 26, 0.5, 0)
	arrow.Size = UDim2.fromOffset(20, 28)
	arrow.BackgroundTransparency = 1
	arrow.FontFace = Style.FONT.display
	arrow.TextSize = 28
	arrow.TextColor3 = bubble.ink
	arrow.Text = "\u{203A}"
	arrow.TextTransparency = 1
	arrow.ZIndex = 3
	arrow.Parent = button
	-- NEW: never said to anyone, in any run.
	if entry.fresh then
		local new = Instance.new("TextLabel")
		new.Name = "New"
		new.AnchorPoint = Vector2.new(1, 0.5)
		new.Position = UDim2.new(1, 26, 0, -11)
		new.Size = UDim2.fromOffset(0, 20)
		new.AutomaticSize = Enum.AutomaticSize.X
		new.BackgroundColor3 = Style.COLOUR.accent
		new.FontFace = Style.FONT.display
		new.TextSize = Style.SIZE.caption
		new.TextColor3 = bubble.ink
		new.Text = "New"
		new.ZIndex = 4
		new.Parent = button
		rounded(new, Style.RADIUS.pill)
		local newRim = Instance.new("UIStroke")
		newRim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		newRim.Color = bubble.rim
		newRim.Thickness = bubble.stroke
		newRim.Parent = new
		local newPad = Instance.new("UIPadding")
		newPad.PaddingLeft, newPad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
		newPad.Parent = new
	end
	button.Parent = slot
	local swell = TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function lit(on: boolean)
		edge.Color = if on then Style.COLOUR.accent else bubble.rim
		edge.Thickness = if on then bubble.stroke + 1 else bubble.stroke
		chip.BackgroundColor3 = if on then Style.COLOUR.accent else bubble.ink
		chip.TextColor3 = if on then bubble.ink else bubble.fill
		-- Up off its shadow and leaning in, with its arrow.
		TweenService:Create(button, swell, { Position = if on then UDim2.fromOffset(6, -2) else UDim2.fromOffset(0, 0) }):Play()
		TweenService:Create(arrow, swell, { TextTransparency = if on then 0 else 1 }):Play()
		TweenService:Create(grow, swell, { Scale = if on then 1.02 else 1 }):Play()
	end
	button.MouseButton1Down:Connect(function()
		TweenService:Create(button, swell, { Position = UDim2.fromOffset(6, 2) }):Play()
		TweenService:Create(grow, swell, { Scale = 0.98 }):Play()
	end)
	button.MouseEnter:Connect(function()
		lit(true)
	end)
	button.MouseLeave:Connect(function()
		lit(false)
	end)
	button.SelectionGained:Connect(function()
		lit(true)
	end)
	button.SelectionLost:Connect(function()
		lit(false)
	end)
	button.Activated:Connect(function()
		pressSound("tap")
		choose(index)
	end)
	return slot, button
end

-- THEIR FACE IN THE DISC (the two-hundredth pass): a copy of whoever `head` belongs to, as they stand, in a little
-- viewport of its own, its camera LIKENESS.back in front of their face. Only what draws is kept (no scripts, sounds,
-- prompts, bubbles, lights or effects). False, and the disc keeps their initial, when there is no one to copy.
local function likeness(disc: Frame, head: BasePart): boolean
	local old = disc:FindFirstChild("Likeness")
	if old then
		old:Destroy()
	end
	local model = head.Parent
	if not (model and model:IsA("Model")) then
		return false
	end
	local made, copy = pcall(function()
		return model:Clone()
	end)
	if not made or not copy then
		return false
	end
	for _, item in ipairs(copy:GetDescendants()) do
		if item:IsA("LuaSourceContainer") or item:IsA("Sound") or item:IsA("ProximityPrompt") or item:IsA("LayerCollector")
			or item:IsA("Light") or item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail") then
			item:Destroy()
		end
	end
	local view = Instance.new("ViewportFrame")
	view.Name = "Likeness"
	view.Size = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(160, 158, 170)
	view.LightColor = Color3.fromRGB(255, 244, 228)
	view.LightDirection = Vector3.new(-0.3, -1, -0.5)
	view.ZIndex = 2
	rounded(view, Style.RADIUS.pill)
	copy.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = LIKENESS.fov
	local face = head.CFrame
	camera.CFrame = CFrame.lookAt(face.Position + face.LookVector * LIKENESS.back + face.UpVector * LIKENESS.up,
		face.Position + face.UpVector * (LIKENESS.up * 0.2))
	camera.Parent = view
	view.CurrentCamera = camera
	view.Parent = disc
	return true
end

-- Their name for RichText: the three characters it treats as markup, written as text.
local function plain(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function show(offer: Offer)
	build()
	local gui, list, holder, eyebrow = ui.gui, ui.list, ui.holder, ui.eyebrow
	if not (gui and list and holder and eyebrow) then
		return
	end
	ui.offer = offer
	for _, slot in ipairs(ui.slots) do
		slot:Destroy()
	end
	table.clear(ui.slots)
	table.clear(ui.buttons)
	-- Their name, and the question after it in a lighter ink.
	eyebrow.Text = ('<font weight="heavy">%s</font><font transparency="0.4">   What do you say?</font>'):format(plain(offer.title))
	-- Their face on their own colour; their initial (the last word of what they are called: Mrs Venn's V) without one.
	local words = string.split(offer.title, " ")
	local tint = if typeof(offer.tint) == "Color3" then offer.tint else Style.COLOUR.accent
	if ui.portrait and ui.initial then
		ui.portrait.BackgroundColor3 = tint
		ui.initial.Text = string.upper(string.sub(words[#words] or "", 1, 1))
		ui.initial.TextColor3 = if 0.299 * tint.R + 0.587 * tint.G + 0.114 * tint.B > 0.6 then Style.BUBBLE.ink
			else Color3.new(1, 1, 1)
		local drawn, seen = pcall(likeness, ui.portrait, offer.head)
		ui.initial.Visible = not (drawn and seen)
	end
	for index, entry in ipairs(offer.options) do
		if index > #KEYS then
			break
		end
		local slot, button = option(index, entry)
		button.BackgroundTransparency = 1
		button.TextTransparency = 1
		local rim = button:FindFirstChildOfClass("UIStroke")
		if rim then
			rim.Transparency = 1
		end
		for _, name in ipairs({ "Number", "New" }) do
			local chip = button:FindFirstChild(name)
			if chip and chip:IsA("TextLabel") then
				chip.BackgroundTransparency, chip.TextTransparency = 1, 1
				local chipRim = chip:FindFirstChildOfClass("UIStroke")
				if chipRim then
					chipRim.Transparency = 1
				end
			end
		end
		local shade = slot:FindFirstChild("Shade")
		if shade and shade:IsA("Frame") then
			shade.BackgroundTransparency = 1
		end
		local grow = button:FindFirstChildOfClass("UIScale")
		if grow then
			grow.Scale = 0.85
		end
		slot.Parent = list
		table.insert(ui.slots, slot)
		table.insert(ui.buttons, button)
		-- ONE AFTER ANOTHER, each popping up into its place as a bubble does.
		task.delay((index - 1) * 0.07, function()
			if button.Parent then
				fade(button, 0, 0.2)
				if grow then
					TweenService:Create(grow, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				end
			end
		end)
	end
	-- Under you (DOCK): over the thumbs on a touch screen with no keyboard.
	ui.low = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then DOCK.touch else DOCK.low
	holder.Position = UDim2.new(0.5, 0, 1, -ui.low + DOCK.away)
	gui.Enabled = true
	TweenService:Create(holder, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 1, -ui.low) }):Play()
	-- Number keys choose; B (or Escape) puts them away. The controller's A presses the selected one, as on any menu.
	local binds: { Enum.KeyCode } = { Enum.KeyCode.Escape, Enum.KeyCode.ButtonB }
	for index = 1, #ui.buttons do
		table.insert(binds, KEYS[index])
	end
	ContextActionService:BindActionAtPriority("TalkChoose", function(_, state, input)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Pass
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			hide()
			return Enum.ContextActionResult.Sink
		end
		local index = table.find(KEYS, input.KeyCode)
		if index then
			choose(index)
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value, table.unpack(binds))
	if usingPad() and ui.buttons[1] then
		GuiService.SelectedObject = ui.buttons[1]
	end
	-- WALK AWAY AND THEY GO: further than Conversations.REACH from whoever you were talking to.
	local reach = if Conversations then Conversations.REACH else 16
	if ui.watch then
		ui.watch:Disconnect()
	end
	ui.watch = RunService.Heartbeat:Connect(function()
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local head = offer.head
		if not (root and root:IsA("BasePart") and head and head.Parent) or (root.Position - head.Position).Magnitude > reach then
			hide()
		end
	end)
end

-- A SPEECH BUBBLE WRITTEN OUT a letter at a time as it comes up, on this screen (its size is the whole line's from the
-- start, so it never grows as it fills).
local function writeOut(gui: Instance)
	local words = gui:FindFirstChild("Words")
	if not (words and words:IsA("TextLabel")) then
		return
	end
	local total = utf8.len(words.Text) or #words.Text
	words.MaxVisibleGraphemes = 0
	local started = os.clock()
	local writing: RBXScriptConnection? = nil
	writing = RunService.Heartbeat:Connect(function()
		local shown = math.floor((os.clock() - started) * WRITE_RATE) + 1
		if not words.Parent or shown >= total then
			words.MaxVisibleGraphemes = -1
			if writing then
				writing:Disconnect()
			end
		else
			words.MaxVisibleGraphemes = shown
		end
	end)
end

-- THREE DOTS COMING UP ONE BY ONE while they think what to say (the two-hundredth pass; Townsfolk.think makes the
-- bubble and tags it ThinkingBubble): one, two, three, a beat with none, and round again, until they speak.
local function thinkOut(gui: Instance)
	local words = gui:FindFirstChild("Words")
	if not (words and words:IsA("TextLabel")) then
		return
	end
	local dots = { 1, 3, 5, 0 } -- graphemes of the three dots: one, two (with the space between), all three, none
	local started = os.clock()
	local thinking: RBXScriptConnection? = nil
	thinking = RunService.Heartbeat:Connect(function()
		if not words.Parent then
			if thinking then
				thinking:Disconnect()
			end
			return
		end
		words.MaxVisibleGraphemes = dots[math.floor((os.clock() - started) / DOT_EVERY) % #dots + 1]
	end)
end

function TalkClient.isOpen(): boolean
	return ui.offer ~= nil
end

-- PUT AWAY FROM OUTSIDE (Cinema, as a scene starts: the hundred-and-fortieth pass), as walking away puts them away.
function TalkClient.dismiss()
	hide()
end

function TalkClient.start()
	CollectionService:GetInstanceAddedSignal("SpeechBubble"):Connect(writeOut)
	CollectionService:GetInstanceAddedSignal("ThinkingBubble"):Connect(thinkOut)
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	local remote = remotes and remotes:WaitForChild("Talk", 20)
	if not (remote and remote:IsA("RemoteEvent")) then
		warn("TalkClient: no RemoteEvents.Talk, so you cannot choose what to say. The server Bootstrap makes it; paste "
			.. "src/Server/Bootstrap.server.lua.")
		return
	end
	ui.remote = remote
	remote.OnClientEvent:Connect(function(kind: any, data: any)
		if kind == "offer" and typeof(data) == "table" and typeof(data.person) == "string" and typeof(data.options) == "table"
			and typeof(data.head) == "Instance" and data.head:IsA("BasePart") then
			local ok, err = pcall(show, data :: Offer)
			if not ok then
				warn("TalkClient: the choices failed to show: " .. tostring(err))
			end
		end
	end)
	print("TalkClient: running")
end

TalkClient.STAMP = "4cf69365"
return TalkClient
