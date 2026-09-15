--!strict
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
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local PauseMenuService = {}

local TITLE = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)
local BODY = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Medium)
local ACCENT = Color3.fromRGB(246, 206, 148)

local open = false
local panel: Frame? = nil
local settingsLabel: TextLabel? = nil
local leaveRemote: RemoteEvent? = nil

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
end

local function build()
	if panel then
		return
	end
	local player = Players.LocalPlayer
	local screen = Instance.new("ScreenGui")
	screen.Name = "PauseMenu"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	-- Above the run HUD, below nothing. When this is open it is the thing being used.
	screen.DisplayOrder = 20
	screen.Parent = player:WaitForChild("PlayerGui")

	-- THE TAB. Small, always there, top-right where a settings control is looked for.
	local tab = Instance.new("TextButton")
	tab.Name = "Tab"
	tab.AnchorPoint = Vector2.new(1, 0)
	tab.Position = UDim2.new(1, -14, 0, 76)
	tab.Size = UDim2.new(0, 44, 0, 44)
	tab.BackgroundColor3 = Color3.fromRGB(20, 19, 27)
	tab.BackgroundTransparency = 0.15
	tab.BorderSizePixel = 0
	tab.FontFace = TITLE
	tab.TextSize = 22
	tab.TextColor3 = ACCENT
	tab.Text = "II"
	tab.Parent = screen

	local tabRound = Instance.new("UICorner")
	tabRound.CornerRadius = UDim.new(0, 12)
	tabRound.Parent = tab

	local tabEdge = Instance.new("UIStroke")
	tabEdge.Color = ACCENT
	tabEdge.Transparency = 0.55
	tabEdge.Thickness = 1.5
	tabEdge.Parent = tab

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 1.6, 0)
	card.Size = UDim2.new(0, 380, 0, 250)
	card.BackgroundColor3 = Color3.fromRGB(18, 17, 25)
	card.BackgroundTransparency = 0.06
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = screen
	panel = card

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 18)
	round.Parent = card

	local edge = Instance.new("UIStroke")
	edge.Color = ACCENT
	edge.Transparency = 0.5
	edge.Thickness = 2
	edge.Parent = card

	local heading = Instance.new("TextLabel")
	heading.Position = UDim2.new(0, 26, 0, 22)
	heading.Size = UDim2.new(1, -52, 0, 34)
	heading.BackgroundTransparency = 1
	heading.FontFace = TITLE
	heading.TextSize = 27
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.TextColor3 = Color3.fromRGB(242, 244, 252)
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
	place.TextColor3 = Color3.fromRGB(238, 240, 250)
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
		holder.BackgroundColor3 = Color3.fromRGB(40, 38, 52)
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
		text.TextColor3 = Color3.fromRGB(196, 202, 222)
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
		made.TextColor3 = if dark then Color3.fromRGB(24, 22, 30) else Color3.fromRGB(238, 240, 250)
		made.Text = text
		made.Parent = card
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 11)
		corner.Parent = made
		return made
	end

	local resume = button("Keep running", 128, Color3.fromRGB(38, 36, 50), false)
	local leave = button("Leave to the lobby", 182, ACCENT, true)

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

	tab.Activated:Connect(function()
		open = not open
		slide()
	end)
end

-- THREE FACTS, SEPARATELY. The caller used to pre-join them into one string, which left this
-- no way to style the halves differently -- and styling them differently is the whole point:
-- the level is where you are, the mode and length are how it is being played.
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
	-- press. M is there for anyone who expects it and costs nothing.
	ContextActionService:BindAction("HubPauseMenu", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			open = not open
			slide()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.M, Enum.KeyCode.Escape)
end)

return PauseMenuService
