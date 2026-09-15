--!strict
-- The hardcore death card: a pulse of "You died", then a choice.
--
-- === Why a pause before the buttons ===
--
-- Falling in hardcore already sends you back to the start, and until now that happened
-- instantly and silently: one frame you were mid-air, the next you were on chunk one with a
-- reset clock and no idea whether the game had noticed. The run ended and nothing said so.
--
-- The three seconds are not decoration. They are the gap between "that went wrong" and "what
-- do I want to do about it", and offering the buttons inside that gap gets one of them pressed
-- by accident -- your hands are still on the keys from the jump you just missed.
--
-- === Why it fades rather than flashes ===
--
-- A hard flash on a death is a punishment, and this is a game about soft materials and quiet
-- sounds. A slow fade in and out says the same thing without raising its voice, and it reads
-- at a glance because it is the only thing on screen that moves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local DeathService = {}

local TITLE = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)
local BODY = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Medium)
local FALLEN = Color3.fromRGB(236, 104, 96)
local WAIT_SECONDS = 3

local screen: ScreenGui? = nil
local wash: Frame? = nil
local headline: TextLabel? = nil
local note: TextLabel? = nil
local choices: Frame? = nil
local pulsing = false
local leaveRemote: RemoteEvent? = nil
local retryRemote: RemoteEvent? = nil

local function build()
	if screen then
		return
	end
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "DeathCard"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Above the pause menu: when this is up it is the only thing that matters.
	gui.DisplayOrder = 40
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	screen = gui

	-- A wash rather than a full blackout. You should still be able to see where you fell from.
	local tint = Instance.new("Frame")
	tint.Name = "Wash"
	tint.Size = UDim2.new(1, 0, 1, 0)
	tint.BackgroundColor3 = Color3.fromRGB(28, 10, 12)
	tint.BackgroundTransparency = 1
	tint.BorderSizePixel = 0
	tint.Parent = gui
	wash = tint

	local title = Instance.new("TextLabel")
	title.Name = "Headline"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.new(0.5, 0, 0.38, 0)
	title.Size = UDim2.new(1, 0, 0, 74)
	title.BackgroundTransparency = 1
	title.FontFace = TITLE
	title.TextSize = 58
	title.TextColor3 = FALLEN
	title.TextTransparency = 1
	title.Text = "You died"
	title.Parent = gui
	headline = title

	local sub = Instance.new("TextLabel")
	sub.Name = "Note"
	sub.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.Position = UDim2.new(0.5, 0, 0.46, 0)
	sub.Size = UDim2.new(1, 0, 0, 28)
	sub.BackgroundTransparency = 1
	sub.FontFace = BODY
	sub.TextSize = 19
	sub.TextColor3 = Color3.fromRGB(214, 190, 192)
	sub.TextTransparency = 1
	sub.Text = "Hardcore: back to the start."
	sub.Parent = gui
	note = sub

	local row = Instance.new("Frame")
	row.Name = "Choices"
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.new(0.5, 0, 0.60, 0)
	row.Size = UDim2.new(0, 420, 0, 48)
	row.BackgroundTransparency = 1
	row.Visible = false
	row.Parent = gui
	choices = row

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = row

	local function button(text: string, order: number, colour: Color3, dark: boolean): TextButton
		local made = Instance.new("TextButton")
		made.LayoutOrder = order
		made.Size = UDim2.new(0, 200, 1, 0)
		made.BackgroundColor3 = colour
		made.BorderSizePixel = 0
		made.FontFace = TITLE
		made.TextSize = 19
		made.TextColor3 = if dark then Color3.fromRGB(24, 22, 30) else Color3.fromRGB(238, 240, 250)
		made.Text = text
		made.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 11)
		corner.Parent = made
		return made
	end

	local again = button("Try again", 1, Color3.fromRGB(246, 206, 148), true)
	local out = button("Leave to the lobby", 2, Color3.fromRGB(44, 42, 58), false)

	again.Activated:Connect(function()
		DeathService.hide()
		if retryRemote then
			retryRemote:FireServer()
		end
	end)
	out.Activated:Connect(function()
		DeathService.hide()
		if leaveRemote then
			leaveRemote:FireServer()
		end
	end)
end

function DeathService.hide()
	pulsing = false
	local gui = screen
	if gui then
		gui.Enabled = false
	end
	if choices then
		choices.Visible = false
	end
end

function DeathService.show()
	build()
	local gui, tint, title, sub, row = screen, wash, headline, note, choices
	if not (gui and tint and title and sub and row) then
		return
	end
	gui.Enabled = true
	row.Visible = false
	pulsing = true

	-- THE PULSE. Two and a half seconds of breathing in and out, driven off the clock rather
	-- than a chain of tweens: a tween chain that outlives its own card keeps animating a
	-- hidden frame, and this one can be dismissed at any moment by the button below it.
	task.spawn(function()
		local started = os.clock()
		while pulsing and gui.Enabled do
			local phase = (os.clock() - started) * 1.6
			local breath = (math.sin(phase) + 1) / 2
			title.TextTransparency = 0.15 + breath * 0.45
			sub.TextTransparency = 0.35 + breath * 0.35
			tint.BackgroundTransparency = 0.72 + breath * 0.14
			RunService.Heartbeat:Wait()
		end
	end)

	task.delay(WAIT_SECONDS, function()
		if not pulsing then
			return
		end
		-- The pulse stops when the choice appears: a decision should be made against something
		-- still, not something breathing at you.
		pulsing = false
		title.TextTransparency = 0.1
		sub.TextTransparency = 0.3
		tint.BackgroundTransparency = 0.7
		row.Visible = true
		row.Position = UDim2.new(0.5, 0, 0.66, 0)
		TweenService:Create(row,
			TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0.60, 0) }):Play()
	end)
end

task.spawn(function()
	build()
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	if not remotes then
		return
	end
	local leave = remotes:WaitForChild("LeaveLevel", 20)
	if leave and leave:IsA("RemoteEvent") then
		leaveRemote = leave
	end
	local retry = remotes:FindFirstChild("HardcoreRetry")
	if retry and retry:IsA("RemoteEvent") then
		retryRemote = retry
	end

	local fell = remotes:WaitForChild("PlayerFell", 20)
	if fell and fell:IsA("RemoteEvent") then
		fell.OnClientEvent:Connect(function()
			DeathService.show()
		end)
	end
end)

return DeathService
