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
local SETTLE = 1.0 -- seconds the fade stays up after you arrive, so you step out into the room as it is
-- THE ROOM'S SKY LIGHT, WARM (the two-hundred-and-thirty-fourth pass). For its first seconds after a jump of 9000 studs
-- the renderer has not yet worked out that the hall is closed in, and the sky's cool outdoor light filled it: you
-- stepped out into a cold blue hall that turned warm as you watched (several seconds, so no fade could cover it). While
-- you are in the room your screen gives that outdoor light the lamps' warmth instead, so the hall looks the same from
-- the first moment; once the renderer has it, the outdoor light no longer reaches in and nothing else changes. Put
-- back as you leave, unless something else (a run's light) has set it since.
local ROOM_OUTDOOR = Color3.fromRGB(196, 180, 164)

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

-- THE CAMERA BEHIND YOU as the doors open (the two-hundred-and-thirty-fourth pass): it kept the angle it had before the
-- move, which could leave it inside the lift you had just stepped out of, looking at the room through its bars.
local function behind()
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (camera and root and root:IsA("BasePart")) then
		return
	end
	local flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if flat.Magnitude < 0.05 then
		return
	end
	local at = root.Position + Vector3.new(0, 1.5, 0)
	camera.CFrame = CFrame.lookAt(at - flat.Unit * 6 + Vector3.new(0, 2.5, 0), at)
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

-- What the room changes, and what it found there, to put back.
local ROOM_LIGHT: { [string]: any } = {
	OutdoorAmbient = ROOM_OUTDOOR,
	-- The sky's picture lit the hall too (and the marble floor mirrored it), indoors where no sky reaches.
	EnvironmentDiffuseScale = 0.1,
	EnvironmentSpecularScale = 0.25,
}
local found: { [string]: any } = {}
local warmedNow = false

local function roomLight(inRoom: boolean)
	local Lighting = game:GetService("Lighting") :: any
	if inRoom then
		for key, value in pairs(ROOM_LIGHT) do
			if not warmedNow then
				found[key] = Lighting[key]
			end
			Lighting[key] = value
		end
		warmedNow = true
	elseif warmedNow then
		for key, value in pairs(ROOM_LIGHT) do
			-- Put back, unless something else (a run's light) has set it since.
			local now = Lighting[key]
			local same = if type(now) == "number" then math.abs(now - value) < 1e-3 else now == value
			if same and found[key] ~= nil then
				Lighting[key] = found[key]
			end
		end
		table.clear(found)
		warmedNow = false
	end
end

function SquishRoomClient.start()
	build()
	local me = Players.LocalPlayer
	roomLight(me:GetAttribute("InSquishRoom") == true)
	me:GetAttributeChangedSignal("InSquishRoom"):Connect(function()
		roomLight(me:GetAttribute("InSquishRoom") == true)
	end)
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
	local remote = remotes:WaitForChild("SquishRoom", 20)
	if remote and remote:IsA("RemoteEvent") then
		remote.OnClientEvent:Connect(function(kind: any)
			if kind == "going" then
				cover()
			elseif kind == "arrived" then
				-- HELD A MOMENT LONGER (the two-hundred-and-thirty-fourth pass): after a jump of 9000 studs the room's
				-- lamps take a second or two to light it, and you stepped out into a cold blue hall that warmed up as you
				-- watched. The fade stays up through that, so the doors open on the room as it is.
				local stamp = ui.coveredAt
				behind()
				task.delay(SETTLE, function()
					if ui.coveredAt == stamp then
						behind()
						uncover()
					end
				end)
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

SquishRoomClient.STAMP = "94acbe7c"
return SquishRoomClient
