--!strict
-- StarterPlayerScripts/Services/TalkClient.lua
-- WHAT YOU SAY TO THEM, on your screen (the hundred-and-fourth pass, your idea: "I want to say the lines to them
-- myself, and I can choose not to talk to them by simply walking away from them far enough that the options of what
-- to say disappear by themselves").
--
-- When you talk to someone (F, or Y on a controller), Townsfolk sends what you could say to them; up to three things
-- come up low in the middle of the screen, in your own colours (the screen's dark panel, its warm accent), each with
-- its number. Choose one with the mouse, a tap, its number key, or the controller (the first is selected for you; B
-- puts them away) and the server has you say it and them answer; then what else you could say comes up. Walk further
-- from them than Conversations.REACH and the choices fade away by themselves. Nothing else on the screen changes.

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

type Offer = { person: string, title: string, head: BasePart, options: { { id: string, say: string } } }
local ui = {
	gui = nil :: ScreenGui?,
	holder = nil :: Frame?,
	list = nil :: Frame?,
	eyebrow = nil :: TextLabel?,
	offer = nil :: Offer?,
	remote = nil :: RemoteEvent?,
	watch = nil :: RBXScriptConnection?,
	buttons = {} :: { TextButton },
}
local KEYS = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }

local function usingPad(): boolean
	local last = UserInputService:GetLastInputType()
	return last == Enum.UserInputType.Gamepad1 or (UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled)
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
	-- Low in the middle, above where a thumb would be, as wide as a phone allows.
	local holder = Instance.new("Frame")
	holder.Name = "Choices"
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -150)
	holder.Size = UDim2.new(0.9, 0, 0, 0)
	holder.AutomaticSize = Enum.AutomaticSize.Y
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local most = Instance.new("UISizeConstraint")
	most.MaxSize = Vector2.new(460, math.huge)
	most.Parent = holder
	Style.fit(holder, Vector2.new(460, 230))
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = holder
	ui.holder = holder
	local eyebrow = Instance.new("TextLabel")
	eyebrow.Name = "Eyebrow"
	eyebrow.LayoutOrder = 0
	eyebrow.Size = UDim2.new(1, 0, 0, 22)
	eyebrow.BackgroundTransparency = 1
	eyebrow.FontFace = Style.FONT.heading
	eyebrow.TextSize = Style.SIZE.caption + 1
	eyebrow.TextColor3 = Style.COLOUR.inkSoft
	eyebrow.TextStrokeTransparency = 0.6
	eyebrow.Text = ""
	eyebrow.Parent = holder
	ui.eyebrow = eyebrow
	local list = Instance.new("Frame")
	list.Name = "List"
	list.LayoutOrder = 1
	list.Size = UDim2.new(1, 0, 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.Y
	list.BackgroundTransparency = 1
	list.Parent = holder
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
	ui.list = list
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
			TweenService:Create(holder, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 1, -130) }):Play()
		end
		for _, button in ipairs(ui.buttons) do
			TweenService:Create(button, TweenInfo.new(0.18), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
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

local function option(index: number, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = "Choice" .. index
	button.LayoutOrder = index
	button.AutoButtonColor = false
	button.Size = UDim2.new(1, 0, 0, 44)
	button.AutomaticSize = Enum.AutomaticSize.Y
	button.BackgroundColor3 = Style.COLOUR.panel
	button.BackgroundTransparency = 0.08
	button.FontFace = Style.FONT.body
	button.TextSize = Style.SIZE.label
	button.TextColor3 = Style.COLOUR.ink
	button.TextWrapped = true
	button.TextXAlignment = Enum.TextXAlignment.Left
	button.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Style.RADIUS.button
	corner.Parent = button
	local edge = Instance.new("UIStroke")
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Color = Style.COLOUR.edge
	edge.Thickness = Style.STROKE.button
	edge.Parent = button
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 46)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = button
	-- Its number, in the accent, at its left.
	local chip = Instance.new("TextLabel")
	chip.Name = "Number"
	chip.AnchorPoint = Vector2.new(0, 0.5)
	chip.Position = UDim2.new(0, -34, 0.5, 0)
	chip.Size = UDim2.fromOffset(24, 24)
	chip.BackgroundColor3 = Style.COLOUR.accent
	chip.FontFace = Style.FONT.heading
	chip.TextSize = Style.SIZE.body
	chip.TextColor3 = Style.COLOUR.panel
	chip.Text = tostring(index)
	chip.Parent = button
	local round = Instance.new("UICorner")
	round.CornerRadius = Style.RADIUS.pill
	round.Parent = chip
	local function lit(on: boolean)
		edge.Color = if on then Style.COLOUR.accent else Style.COLOUR.edge
		button.BackgroundColor3 = if on then Style.COLOUR.panelRaised else Style.COLOUR.panel
	end
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
		choose(index)
	end)
	return button
end

local function show(offer: Offer)
	build()
	local gui, list, holder, eyebrow = ui.gui, ui.list, ui.holder, ui.eyebrow
	if not (gui and list and holder and eyebrow) then
		return
	end
	ui.offer = offer
	for _, button in ipairs(ui.buttons) do
		button:Destroy()
	end
	table.clear(ui.buttons)
	eyebrow.Text = ("What do you say to %s?"):format(offer.title)
	for index, entry in ipairs(offer.options) do
		if index > #KEYS then
			break
		end
		local button = option(index, entry.say)
		button.BackgroundTransparency = 1
		button.TextTransparency = 1
		button.Parent = list
		table.insert(ui.buttons, button)
		TweenService:Create(button, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.08,
			TextTransparency = 0 }):Play()
	end
	holder.Position = UDim2.new(0.5, 0, 1, -130)
	gui.Enabled = true
	TweenService:Create(holder, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 1, -150) }):Play()
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

function TalkClient.isOpen(): boolean
	return ui.offer ~= nil
end

function TalkClient.start()
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

TalkClient.STAMP = "972bf443"
return TalkClient
