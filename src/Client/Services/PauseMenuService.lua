--!strict
-- StarterPlayerScripts/Services/PauseMenuService.lua
-- The in-run menu: what you chose, and the way out.
--
-- === Why this exists ===
--
-- Once a run starts there is no way back to the lobby short of dying enough times or closing
-- the game. LeaveLevel has existed on the server since the hub was built and nothing on the
-- client has ever fired it, so the exit was implemented at one end only.
--
-- === Why it is a tab and not a key ===
--
-- A menu bound solely to a key is a menu nobody on a touchscreen can open, and a run you
-- cannot leave on mobile is worse than one you cannot leave anywhere. So: a small tab in the
-- corner that is always pressable, with Escape and M as shortcuts for people who prefer them.
--
-- It also shows the run's settings, which is the other half of the same problem -- ten seconds
-- after a vote resolves nobody remembers whether the room picked medium or long.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SocialService = game:GetService("SocialService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local PauseMenuService = {}

local TITLE = Style.FONT.heading
local BODY = Style.FONT.body
local ACCENT = Style.COLOUR.accent

local open = false
local panel: Frame? = nil
local settingsLabel: TextLabel? = nil
local leaveRemote: RemoteEvent? = nil
-- The button a controller starts on when the menu opens (Keep running).
local firstButton: TextButton? = nil

-- WHAT THE INVITE SAYS on Roblox's own invite screen: why to come (ShopCatalog.REWARD.FRIEND, also told on the card
-- when a run starts with a friend in it). Nil where this Roblox has no such options, and the screen is the plain one.
local INVITE_WORDS = "Come and play Harrow Bay with me: a friend in your run pays 20% more tokens."
local function inviteOptions(): any
	local ok, options = pcall(function()
		local made = Instance.new("ExperienceInviteOptions")
		made.PromptMessage = INVITE_WORDS
		return made
	end)
	return if ok then options else nil
end

-- INVITE FRIENDS: Roblox's own invite screen, when this account may send one from here. When it may not
-- (in Studio, or an account that cannot invite), a word from Roblox's own corner says so.
local function invite()
	local me = Players.LocalPlayer
	local ok, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(me)
	end)
	if ok and can then
		pcall(function()
			SocialService:PromptGameInvite(me, inviteOptions())
		end)
		return
	end
	local text = "Invites are not available on this account right now."
	if RunService:IsStudio() then
		text = "Invites open in the live game, not in Studio."
	end
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Invite friends", Text = text, Duration = 4 })
	end)
end

local function usingPad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

local function slide()
	local frame = panel
	if not frame then
		return
	end
	if open then
		frame.Visible = true
	end
	local to = if open then UDim2.new(0.5, 0, 0.5, 0) else UDim2.new(0.5, 0, 1.6, 0)
	local move = TweenService:Create(frame,
		TweenInfo.new(0.28, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = to })
	move:Play()
	if not open then
		move.Completed:Once(function()
			frame.Visible = false
		end)
	end
	-- A CONTROLLER: the first button selected as it opens, and B to close it again.
	if open then
		if usingPad() and firstButton then
			GuiService.SelectedObject = firstButton
		end
		ContextActionService:BindActionAtPriority("PauseMenuBack", function(_, state: Enum.UserInputState)
			if state == Enum.UserInputState.Begin then
				open = false
				slide()
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 5, Enum.KeyCode.ButtonB)
	else
		ContextActionService:UnbindAction("PauseMenuBack")
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(frame) then
			GuiService.SelectedObject = nil
		end
	end
end

local function build()
	if panel then
		return
	end
	local player = Players.LocalPlayer
	local screen = Instance.new("ScreenGui")
	screen.Name = "PauseMenu"
	screen.ResetOnSpawn = false
	-- INSIDE THE SAFE AREA (clear of a phone's notch and rounded corners); the tab sits below Roblox's bar.
	screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	-- Above the run HUD, below nothing. When this is open it is the thing being used.
	screen.DisplayOrder = 20
	screen.Parent = player:WaitForChild("PlayerGui")

	-- THE TAB. Small, always there, top-right where a settings control is looked for.
	local tab = Instance.new("TextButton")
	tab.Name = "Tab"
	tab.AnchorPoint = Vector2.new(1, 0)
	tab.Position = UDim2.new(1, -14, 0, 76)
	tab.Size = UDim2.new(0, 44, 0, 44)
	tab.BackgroundColor3 = Style.COLOUR.panel
	tab.BackgroundTransparency = 0.15
	tab.BorderSizePixel = 0
	tab.FontFace = TITLE
	tab.TextSize = 22
	tab.TextColor3 = ACCENT
	tab.Text = "II"
	tab.Parent = screen

	local tabRound = Instance.new("UICorner")
	tabRound.CornerRadius = Style.RADIUS.button
	tabRound.Parent = tab

	local tabEdge = Instance.new("UIStroke")
	tabEdge.Color = ACCENT
	tabEdge.Transparency = 0.55
	tabEdge.Thickness = Style.STROKE.button
	tabEdge.Parent = tab

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 1.6, 0)
	-- NO WIDER THAN THE SCREEN: 380 on anything wide enough, the screen's width less a margin on a
	-- phone held upright.
	card.Size = UDim2.new(0.92, 0, 0, 304)
	local cardMost = Instance.new("UISizeConstraint")
	cardMost.MaxSize = Vector2.new(380, 304)
	cardMost.Parent = card
	-- And no taller than the screen, larger on a large one (Style.fit).
	Style.fit(card, Vector2.new(380, 304))
	card.BackgroundColor3 = Style.COLOUR.panel
	card.BackgroundTransparency = 0.06
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = screen
	panel = card

	local round = Instance.new("UICorner")
	round.CornerRadius = Style.RADIUS.panel
	round.Parent = card

	local edge = Instance.new("UIStroke")
	edge.Color = ACCENT
	edge.Transparency = 0.5
	edge.Thickness = Style.STROKE.panel
	edge.Parent = card

	local heading = Instance.new("TextLabel")
	heading.Position = UDim2.new(0, 26, 0, 22)
	heading.Size = UDim2.new(1, -52, 0, 34)
	heading.BackgroundTransparency = 1
	heading.FontFace = TITLE
	heading.TextSize = 27
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.TextColor3 = Style.COLOUR.ink
	heading.Text = "This run"
	heading.Parent = card

	-- THE LEVEL NAME, given the size it deserves. It was the first line of a wrapped paragraph
	-- in the same 19pt grey as the settings, so "where am I" and "how is it being played" read
	-- as one undifferentiated block.
	local place = Instance.new("TextLabel")
	place.Name = "Place"
	place.Position = UDim2.new(0, 26, 0, 54)
	place.Size = UDim2.new(1, -52, 0, 30)
	place.BackgroundTransparency = 1
	place.FontFace = TITLE
	place.TextSize = 23
	place.TextXAlignment = Enum.TextXAlignment.Left
	place.TextTruncate = Enum.TextTruncate.AtEnd
	place.TextColor3 = Style.COLOUR.ink
	place.Text = "-"
	place.Parent = card

	-- The settings as CHIPS. They are two independent facts and a dash between them does not
	-- say so -- and a chip lets hardcore be red without recolouring a whole sentence.
	local chips = Instance.new("Frame")
	chips.Name = "Chips"
	chips.Position = UDim2.new(0, 26, 0, 88)
	chips.Size = UDim2.new(1, -52, 0, 26)
	chips.BackgroundTransparency = 1
	chips.Parent = card

	local chipRow = Instance.new("UIListLayout")
	chipRow.FillDirection = Enum.FillDirection.Horizontal
	chipRow.Padding = UDim.new(0, 8)
	chipRow.Parent = chips

	local function chip(name: string, order: number)
		local holder = Instance.new("Frame")
		holder.Name = name .. "Chip"
		holder.LayoutOrder = order
		holder.Size = UDim2.new(0, 118, 1, 0)
		holder.BackgroundColor3 = Style.COLOUR.panelRaised
		holder.BorderSizePixel = 0
		holder.Parent = chips
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = holder
		local text = Instance.new("TextLabel")
		text.Name = name
		text.Size = UDim2.new(1, 0, 1, 0)
		text.BackgroundTransparency = 1
		text.FontFace = BODY
		text.TextSize = 15
		text.TextColor3 = Style.COLOUR.inkSoft
		text.Text = "-"
		text.Parent = holder
	end

	chip("Mode", 1)
	chip("Length", 2)

	-- Kept, hidden, so the old setRunSummary entry point still has something to write to
	-- rather than erroring if anything still calls it.
	local settings = Instance.new("TextLabel")
	settings.Name = "Settings"
	settings.Size = UDim2.new(0, 0, 0, 0)
	settings.BackgroundTransparency = 1
	settings.Visible = false
	settings.Parent = card
	settingsLabel = settings

	local function button(text: string, y: number, colour: Color3, dark: boolean): TextButton
		local made = Instance.new("TextButton")
		made.Position = UDim2.new(0, 26, 0, y)
		made.Size = UDim2.new(1, -52, 0, 44)
		made.BackgroundColor3 = colour
		made.BorderSizePixel = 0
		made.FontFace = TITLE
		made.TextSize = 19
		made.TextColor3 = if dark then Style.COLOUR.panel else Style.COLOUR.ink
		made.Text = text
		made.Parent = card
		local corner = Instance.new("UICorner")
		corner.CornerRadius = Style.RADIUS.button
		corner.Parent = made
		return made
	end

	local resume = button("Keep running", 128, Style.COLOUR.panelRaised, false)
	firstButton = resume
	local leave = button("Leave to the lobby", 182, ACCENT, true)
	-- THE SHOP, THE EMOTES AND AN INVITE, side by side, from anywhere: on a phone this is the way to all three
	-- (a keyboard has the kiosk and G, a controller the kiosk and D-pad right). Three to a row rather than a
	-- fourth row, which would not fit a phone held sideways.
	local shopButton = button("Shop", 236, Color3.fromRGB(159, 225, 203), true)
	shopButton.Size = UDim2.new(1 / 3, -23, 0, 44)
	local emotesButton = button("Emotes", 236, Color3.fromRGB(244, 192, 209), true)
	emotesButton.Position = UDim2.new(1 / 3, 11, 0, 236)
	emotesButton.Size = UDim2.new(1 / 3, -23, 0, 44)
	local inviteButton = button("Invite", 236, Color3.fromRGB(252, 214, 146), true)
	inviteButton.Position = UDim2.new(2 / 3, -4, 0, 236)
	inviteButton.Size = UDim2.new(1 / 3, -23, 0, 44)

	resume.Activated:Connect(function()
		open = false
		slide()
	end)

	leave.Activated:Connect(function()
		open = false
		slide()
		-- THE CLIENT ASKS. The server decides whether there is a run to leave, which is why
		-- this carries no arguments: a request that cannot say anything cannot say anything
		-- wrong, and the one on the other end already refuses when you are in the lobby.
		if leaveRemote then
			leaveRemote:FireServer()
		end
	end)

	shopButton.Activated:Connect(function()
		open = false
		slide()
		local module = script.Parent and script.Parent:FindFirstChild("ShopService")
		if module and module:IsA("ModuleScript") then
			local ok, err = pcall(function()
				(require(module) :: any).open()
			end)
			if not ok then
				warn("PauseMenuService: the shop did not open: " .. tostring(err))
			end
		end
	end)

	emotesButton.Activated:Connect(function()
		open = false
		slide()
		local module = script.Parent and script.Parent:FindFirstChild("EmoteService")
		if module and module:IsA("ModuleScript") then
			local ok, err = pcall(function()
				(require(module) :: any).open()
			end)
			if not ok then
				warn("PauseMenuService: the emotes did not open: " .. tostring(err))
			end
		end
	end)

	inviteButton.Activated:Connect(function()
		open = false
		slide()
		task.spawn(invite)
	end)

	tab.Activated:Connect(function()
		open = not open
		slide()
	end)
end

-- THREE FACTS, SEPARATELY. The caller used to pre-join them into one string, which left this
-- no way to style the halves differently -- and styling them differently is the whole point:
-- the level is where you are, the mode and length are how it is being played.
-- OPENED AND CLOSED FROM OUTSIDE (the test panel's Self-test), the same way the tab and the keys do it.
function PauseMenuService.setOpen(on: boolean)
	build()
	if open ~= on then
		open = on
		slide()
	end
end

function PauseMenuService.isOpen(): boolean
	return open
end

function PauseMenuService.setRun(levelName: string, mode: string, length: string)
	build()
	local root = panel
	if not root then
		return
	end

	local place = root:FindFirstChild("Place")
	if place and place:IsA("TextLabel") then
		place.Text = levelName
	end

	local hardcore = mode:lower() == "hardcore"
	local modeChip = root:FindFirstChild("ModeChip")
	local modeText = modeChip and modeChip:FindFirstChild("Mode")
	if modeChip and modeChip:IsA("Frame") and modeText and modeText:IsA("TextLabel") then
		modeChip.BackgroundColor3 = if hardcore
			then Color3.fromRGB(88, 34, 34)
			else Color3.fromRGB(32, 54, 68)
		modeText.TextColor3 = if hardcore
			then Color3.fromRGB(248, 176, 172)
			else Color3.fromRGB(168, 214, 238)
		-- Capitalised here, not at the source: the server's value is an identifier and should
		-- stay lowercase everywhere except the one place a person reads it.
		modeText.Text = mode:sub(1, 1):upper() .. mode:sub(2)
	end

	local lengthChip = root:FindFirstChild("LengthChip")
	local lengthText = lengthChip and lengthChip:FindFirstChild("Length")
	if lengthText and lengthText:IsA("TextLabel") then
		lengthText.Text = length:sub(1, 1):upper() .. length:sub(2) .. " run"
	end
end

-- The old shape, kept so anything still calling it does not break. It cannot style anything,
-- which is why setRun exists.
function PauseMenuService.setRunSummary(text: string)
	build()
	if settingsLabel then
		settingsLabel.Text = text
	end
end

task.spawn(function()
	build()

	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	local leave = remotes and remotes:WaitForChild("LeaveLevel", 20)
	if leave and leave:IsA("RemoteEvent") then
		leaveRemote = leave
	end

	-- The result of the vote is what this run IS, so the banner's announcement is also the
	-- menu's summary. One source, two places it is shown.
	local voteState = remotes and remotes:FindFirstChild("HubVoteState")
	if voteState and voteState:IsA("RemoteEvent") then
		voteState.OnClientEvent:Connect(function(kind: string, payload: any)
			if kind == "result" and typeof(payload) == "table" then
				PauseMenuService.setRun(tostring(payload.levelName),
					tostring(payload.mode), tostring(payload.length))
			end
		end)
	end

	-- Escape is bound with a sink so it does not also open Roblox's own menu on the same
	-- press. M is there for anyone who expects it and costs nothing. A CONTROLLER opens it with
	-- D-pad down (Start is Roblox's own menu, and nothing else in the game uses the D-pad).
	ContextActionService:BindAction("HubPauseMenu", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			open = not open
			slide()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.M, Enum.KeyCode.Escape, Enum.KeyCode.DPadDown)
end)

PauseMenuService.STAMP = "466ea02d"
return PauseMenuService
