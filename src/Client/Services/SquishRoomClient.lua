--!strict
-- StarterPlayerScripts/Services/SquishRoomClient.lua
-- THE SQUISH ROOM'S LIFTS, on your screen. The server says what is happening and this shows it: "going"
-- covers the screen with a soft fade, "arrived" uncovers it once you are standing where you were going
-- (the server streams the place in first), "building" and "closed" are a word at the bottom when the lift
-- will not go yet. Nothing here takes a press; the lifts use Roblox's own prompt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local SquishRoomClient = {}
SquishRoomClient.VERSION = "the squish room, 2026-10-05"

local ui: { [string]: any } = {}

local function build()
	if ui.fade then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- The fade covers everything, notch and all.
	local cover = Instance.new("ScreenGui")
	cover.Name = "LiftFade"
	cover.ResetOnSpawn = false
	cover.DisplayOrder = 50
	cover.IgnoreGuiInset = true
	cover.Parent = playerGui
	local fade = Instance.new("Frame")
	fade.Active = false
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.fromRGB(236, 230, 246)
	fade.BackgroundTransparency = 1
	fade.BorderSizePixel = 0
	fade.Parent = cover
	ui.fade = fade
	-- The word, inside the safe area at the bottom.
	local words = Instance.new("ScreenGui")
	words.Name = "LiftWord"
	words.ResetOnSpawn = false
	words.DisplayOrder = 16
	words.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	words.Parent = playerGui
	local pill = Instance.new("TextLabel")
	pill.Active = false
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, -96)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.new(0, 0, 0, 40)
	pill.BackgroundColor3 = Color3.fromRGB(251, 234, 240)
	pill.FontFace = Style.FONT.heading
	pill.TextSize = 18
	pill.TextColor3 = Color3.fromRGB(72, 44, 92)
	pill.Visible = false
	pill.Parent = words
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(114, 36, 62)
	edge.Thickness = 3
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = pill
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = pill
	ui.pill = pill
end

-- Covered while the server moves you; uncovered when it says you have arrived (or after LONGEST, so a
-- lost word can never leave the screen covered).
local LONGEST = 8

local function uncover()
	build()
	ui.coveredAt = nil
	TweenService:Create(ui.fade, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

local function cover()
	build()
	local stamp = os.clock()
	ui.coveredAt = stamp
	TweenService:Create(ui.fade, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { BackgroundTransparency = 0 }):Play()
	task.delay(LONGEST, function()
		if ui.coveredAt == stamp then
			uncover()
		end
	end)
end

local function say(text: string)
	build()
	local pill = ui.pill
	pill.Text = text
	pill.Visible = true
	local stamp = os.clock()
	ui.sayAt = stamp
	task.delay(4, function()
		if ui.sayAt == stamp then
			pill.Visible = false
		end
	end)
end

function SquishRoomClient.start()
	build()
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
	local remote = remotes:WaitForChild("SquishRoom", 20)
	if remote and remote:IsA("RemoteEvent") then
		remote.OnClientEvent:Connect(function(kind: any)
			if kind == "going" then
				cover()
			elseif kind == "arrived" then
				uncover()
			elseif kind == "closed" then
				say("The lobby is away while a run is on. It opens again when the run ends.")
			elseif kind == "building" then
				say("The squish room is still being set up. Try again in a moment.")
			elseif kind == "running" then
				say("Finish or leave your run first.")
			end
		end)
	else
		warn("SquishRoomClient: no RemoteEvents.SquishRoom; paste the current server Bootstrap.")
	end
	print("SquishRoomClient: running, " .. SquishRoomClient.VERSION)
end

SquishRoomClient.STAMP = "d8a5bf07"
return SquishRoomClient
