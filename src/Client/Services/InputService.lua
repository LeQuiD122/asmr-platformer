--!strict
-- StarterPlayerScripts/Services/InputService.lua
-- Detects click on the mode icon, checks CanToggleMode via RemoteFunction,
-- then sends the toggle request or shows the "switch at start only" tooltip.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local RemoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions")

local PlayerModeChanged = RemoteEvents:WaitForChild("PlayerModeChanged")
local ModeToggleBlocked = RemoteEvents:WaitForChild("ModeToggleBlocked")
local CanToggleMode = RemoteFunctions:WaitForChild("CanToggleMode")
-- The pull half of the run HUD. WaitForChild rather than FindFirstChild: this module is
-- required at client boot and the server may not have created it yet.
local RequestRunState = RemoteFunctions:WaitForChild("RequestRunState")

local UIService = require(script.Parent:WaitForChild("UIService"))

local InputService = {}

local currentMode = "chill"

function InputService.onModeIconClicked()
	local canToggle = CanToggleMode:InvokeServer()
	if not canToggle then
		UIService.showTooltip("You can switch modes only at the start of a level.")
		return
	end
	-- ASKS, AND WAITS TO BE TOLD. The display is not touched here on purpose.
	--
	-- This used to flip currentMode and update the HUD on the spot, before the server had seen
	-- the request at all. So a refusal produced a warning next to a HUD that had already
	-- changed, and from then on the client believed a mode the server had never agreed to --
	-- which is how a hardcore run ended up labelled Chill.
	PlayerModeChanged:FireServer(currentMode == "chill" and "hardcore" or "chill")
end

-- The server's answer, and the only thing that moves the display.
PlayerModeChanged.OnClientEvent:Connect(function(mode: string)
	currentMode = mode
	UIService.setMode(mode)
end)

ModeToggleBlocked.OnClientEvent:Connect(function()
	UIService.showTooltip("You can switch modes only at the start of a level.")
end)

-- THE CONNECTION THAT WAS NEVER MADE.
--
-- This file has always exported `onModeIconClicked`, and a comment here used to say it
-- was "wired to the actual mode-icon GuiButton at runtime". Nothing wired it. The button
-- was a TextLabel besides, so there was nothing to wire it to -- which is why the mode
-- switch looked implemented from every angle except pressing it.
-- NOT BOUND ANY MORE. The mode is a lobby vote now: the server refuses every toggle during a
-- run, and outside a run the mode pad in the hub does the job properly. Wiring a button whose
-- only possible outcome is a refusal message is worse than leaving it unwired.
--
-- onModeIconClicked stays below, unbound, because it is still the correct implementation if
-- the mode ever becomes a personal setting again -- and deleting it would mean writing it
-- back from scratch to find that out.

-- ===== Hardcore clock and board =====

local RunService = game:GetService("RunService")
local HardcoreTimerSync = RemoteEvents:WaitForChild("HardcoreTimerSync")
local RequestLeaderboardData = RemoteFunctions:WaitForChild("RequestLeaderboardData")

-- The server sends state CHANGES; the seconds in between are counted here. `baseElapsed`
-- is the authoritative reading at the moment of the last packet and `startedAt` is when
-- that packet arrived, so the display is always server time plus local drift since --
-- never a local clock that has been free-running long enough to disagree.
local running = false
local baseElapsed = 0
local startedAt = 0

local function refreshBoard()
	task.spawn(function()
		local ok, data = pcall(function()
			return RequestLeaderboardData:InvokeServer()
		end)
		if ok and type(data) == "table" then
			UIService.refreshLeaderboard(data)
		end
	end)
end

-- Named, so the pull below can hand the pushed payload and the requested one to exactly the
-- same code. Two routes into one function; no second copy of the HUD rules to keep in step.
local function applyRunState(payload)
	if type(payload) ~= "table" or payload.mode == nil then
		return
	end
	local hardcore = payload.mode == "hardcore"
	currentMode = payload.mode
	UIService.setMode(payload.mode)
	UIService.setTimerVisible(hardcore)
	UIService.setLeaderboardVisible(hardcore)

	running = hardcore and payload.running or false
	baseElapsed = payload.elapsed or 0
	startedAt = os.clock()
	UIService.setTimer(baseElapsed)

	if hardcore then
		refreshBoard()
	end
end

HardcoreTimerSync.OnClientEvent:Connect(applyRunState)

-- THE PULL. Asked once at startup and again on every spawn, because a spawn is the one moment
-- the client is guaranteed to be in whatever state the server just put it in -- run start,
-- respawn after a fall, or returning to the lobby.
--
-- pcall'd and spawned: an InvokeServer yields and can throw if the server is mid-teardown, and
-- neither is a reason to take the rest of this module down with it.
local function askForRunState()
	task.spawn(function()
		local ok, payload = pcall(function()
			return RequestRunState:InvokeServer()
		end)
		if ok then
			applyRunState(payload)
		end
	end)
end

askForRunState()
Players.LocalPlayer.CharacterAdded:Connect(askForRunState)

RunService.RenderStepped:Connect(function()
	if running then
		UIService.setTimer(baseElapsed + (os.clock() - startedAt))
	end
end)

return InputService
