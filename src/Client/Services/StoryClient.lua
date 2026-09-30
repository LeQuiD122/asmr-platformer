--!strict
-- StarterPlayerScripts/Services/StoryClient.lua
-- The story's small moments, on this player's screen (Interactables tells it when, over the
-- StoryMoment remote):
--
--   whisper   one line low on the screen for a few seconds: "It is rusted shut."
--   moment    a SECRET found: a short scene (Cinema, the level's sound left alone). The camera drifts in
--             along a curve on what you have found, sharp on it and soft round it, a low sting under
--             it, its name and a line; then a card, "Secret 2 of 5", which says its words are in your
--             journal (the server has put them there: JournalService). Nothing else comes up.
--   peek      the loose board on the gangway: the camera looks straight down through the gap into the
--             shaft, and a long way down, in the dark, something opens its mouth a little and
--             breathes (Maw). Then it is only the dark again.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Cinema: any = (function()
	local found = script.Parent and script.Parent:WaitForChild("Cinema", 15)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()
local Maw: any = (function()
	local found = script.Parent and script.Parent:FindFirstChild("Maw")
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()

local StoryClient = {}
StoryClient.VERSION = "eighteenth pass, 2026-09-29"

local busy = false

local function sound(name: string, fallback: string?, volume: number, speed: number): Sound?
	local folder = SoundService:FindFirstChild("StorySounds")
	local own = folder and folder:FindFirstChild(name)
	local made: Sound
	if own and own:IsA("Sound") then
		made = own:Clone()
	elseif fallback then
		made = Instance.new("Sound")
		made.SoundId = fallback
		made.PlaybackSpeed = speed
	else
		return nil
	end
	made.Volume = volume
	made.Parent = SoundService
	made:Play()
	game:GetService("Debris"):AddItem(made, 12)
	return made
end

local function gui(name: string, order: number): ScreenGui?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local old = playerGui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local made = Instance.new("ScreenGui")
	made.Name = name
	made.ResetOnSpawn = false
	made.DisplayOrder = order
	made.Parent = playerGui
	return made
end

-- One line, low on the screen, for a few seconds.
local function whisper(text: string)
	local screen = gui("StoryWhisper", 26)
	if not screen then
		return
	end
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	-- Above the level's opening words (which sit low, at 0.86), so the two never print over each other.
	label.Position = UDim2.new(0.5, 0, 0.7, 0)
	label.Size = UDim2.new(0.8, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.TextWrapped = true
	label.Font = Enum.Font.Garamond
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(236, 232, 218)
	label.TextStrokeTransparency = 0.4
	label.TextTransparency = 1
	label.Text = text
	label.Parent = screen
	TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	task.delay(5, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(1.1, function()
				screen:Destroy()
			end)
		end
	end)
end

-- "Secret 2 of 5": the card after a moment, as the keepsakes have.
local function card(title: string, found: number, total: number)
	local screen = gui("SecretCard", 23)
	if not screen then
		return
	end
	local paper = Instance.new("Frame")
	paper.AnchorPoint = Vector2.new(0.5, 0)
	paper.Position = UDim2.new(0.5, 0, 0, -120)
	paper.Size = UDim2.new(0.9, 0, 0, 0)
	paper.AutomaticSize = Enum.AutomaticSize.Y
	paper.BackgroundColor3 = Color3.fromRGB(24, 26, 28)
	paper.BackgroundTransparency = 0.1
	paper.BorderSizePixel = 0
	paper.Parent = screen
	local widest = Instance.new("UISizeConstraint")
	widest.MaxSize = Vector2.new(380, math.huge)
	widest.Parent = paper
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(150, 140, 110)
	edge.Thickness = 1
	edge.Parent = paper
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = paper
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 3)
	list.Parent = paper
	for index, row in ipairs({ { ("SECRET %d OF %d"):format(found, total), 12, Color3.fromRGB(180, 170, 140) },
		{ title, 18, Color3.fromRGB(236, 232, 218) },
		{ "Kept in your journal. Press J to read it.", 14, Color3.fromRGB(200, 192, 170) } }) do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Font = if index == 1 then Enum.Font.GothamBold else Enum.Font.Garamond
		label.TextSize = row[2] :: number
		label.TextColor3 = row[3] :: Color3
		label.Text = row[1] :: string
		label.LayoutOrder = index
		label.Parent = paper
	end
	TweenService:Create(paper, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 0, 64) }):Play()
	task.delay(6, function()
		if paper.Parent then
			local away = TweenService:Create(paper, TweenInfo.new(0.7), { Position = UDim2.new(0.5, 0, 0, -140) })
			away:Play()
			away.Completed:Wait()
			screen:Destroy()
		end
	end)
end

-- A SECRET FOUND: the camera in on it, its name, a sting, then the card.
local function moment(data: { [string]: any })
	if busy or not Cinema then
		card(tostring(data.title), tonumber(data.found) or 1, tonumber(data.total) or 5)
		return
	end
	local eye, focus = data.eye, data.focus
	if typeof(eye) ~= "CFrame" or typeof(focus) ~= "Vector3" then
		return
	end
	busy = true
	Cinema.begin({ hush = false })
	sound("SecretSting", nil, 0.7, 1)
	local start = eye.Position
	local toward = (focus - start)
	local path = { start - toward.Unit * 3 + Vector3.new(0, 1.2, 0), start, start + toward * 0.22 + Vector3.new(0, -0.3, 0) }
	Cinema.caption(tostring(data.title), tostring(data.line), 6)
	local began = os.clock()
	local hook
	hook = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		local u = math.clamp(t / 6.5, 0, 1)
		u = u * u * (3 - 2 * u)
		local at = Cinema.spline(path, u)
		Cinema.point(CFrame.lookAt(at, focus), 50 - 8 * u)
		Cinema.focus((focus - at).Magnitude, 0.55)
		if t > 7.2 then
			hook:Disconnect()
			Cinema.finish()
			busy = false
			card(tostring(data.title), tonumber(data.found) or 1, tonumber(data.total) or 5)
		end
	end)
end

-- UNDER THE BOARDS: straight down into the shaft, and far below, the mouth, breathing.
local function peek(data: { [string]: any })
	local hole = data.eye
	if busy or not Cinema or typeof(hole) ~= "CFrame" then
		return
	end
	busy = true
	Cinema.begin({ hush = false })
	local over = hole.Position + Vector3.new(0, 1.5, 0)
	local mouth = if Maw then Maw.build(Maw.facing(over - Vector3.new(0, 240, 0), Vector3.yAxis, Vector3.xAxis), workspace) else nil
	if mouth then
		Maw.set(mouth, 0.06, 0.05)
		Maw.light(mouth, 0)
	end
	sound("MawRumble", "rbxasset://sounds/bass.mp3", 0.5, 0.2)
	Cinema.caption(tostring(data.title), tostring(data.line), 6)
	local began = os.clock()
	local hook
	hook = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		local breath = math.clamp(math.sin(math.clamp((t - 1) / 5, 0, 1) * math.pi), 0, 1)
		if mouth then
			Maw.set(mouth, 0.06 + 0.3 * breath, 0.05 + 0.25 * breath)
			Maw.light(mouth, 0.45 * breath)
		end
		-- Straight down: told which way is up on the screen, since looking along the world's up has no answer.
		Cinema.point(CFrame.lookAt(over + Vector3.new(0, -2, 0), over - Vector3.new(0, 100, 0), Vector3.zAxis), 40 - 6 * math.min(1, t / 7))
		if t > 7.5 then
			hook:Disconnect()
			if Maw and mouth then
				Maw.destroy(mouth)
			end
			Cinema.finish()
			busy = false
			card(tostring(data.title), tonumber(data.found) or 1, tonumber(data.total) or 5)
		end
	end)
end

function StoryClient.start()
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	local event = remotes and remotes:WaitForChild("StoryMoment", 20)
	if not (event and event:IsA("RemoteEvent")) then
		warn("StoryClient: no RemoteEvents.StoryMoment, so secrets have no scene and nothing whispers. The server "
			.. "Bootstrap makes it; paste src/Server/Bootstrap.server.lua.")
		return
	end
	event.OnClientEvent:Connect(function(kind: any, data: any)
		local ok, err = pcall(function()
			if kind == "whisper" and typeof(data) == "string" then
				whisper(data)
			elseif kind == "moment" and typeof(data) == "table" then
				moment(data)
			elseif kind == "peek" and typeof(data) == "table" then
				peek(data)
			end
		end)
		if not ok then
			busy = false
			warn("StoryClient: a moment failed, and the camera is given back: " .. tostring(err))
			if Cinema then
				pcall(Cinema.finish)
			end
		end
	end)
	print("StoryClient: running, " .. StoryClient.VERSION)
end

return StoryClient
