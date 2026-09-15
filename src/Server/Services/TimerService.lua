--!strict
-- ServerScriptService/Services/TimerService.lua
-- Per-player hardcore elapsed timer. No dependencies (pure per-player tick).
--
-- Start condition: player first crosses from the opening stable chunk (index 0)
-- into chunk index >= 1. Reset to 0 on fail-triggered teleport (clean-run
-- semantics). Does NOT auto-restart on teleport -- waits for the player to
-- cross into chunk 2 again, same trigger condition as initial start.
-- Stops on level completion. Discarded entirely on mode switch.

local RunService = game:GetService("RunService")

local TimerService = {}

local timers: { [Player]: { elapsed: number, running: boolean } } = {}

function TimerService.init(player: Player)
	timers[player] = { elapsed = 0, running = false }
end

function TimerService.startTimer(player: Player)
	local t = timers[player]
	if not t then
		return
	end
	t.elapsed = 0
	t.running = true
end

function TimerService.stopTimer(player: Player): number
	local t = timers[player]
	if not t then
		return 0
	end
	t.running = false
	return t.elapsed
end

function TimerService.resetTimer(player: Player)
	local t = timers[player]
	if not t then
		return
	end
	t.elapsed = 0
	t.running = false -- waits for the chunk-2 crossing trigger to restart
end

function TimerService.isRunning(player: Player): boolean
	local t = timers[player]
	return t ~= nil and t.running == true
end

function TimerService.getElapsed(player: Player): number
	local t = timers[player]
	return t and t.elapsed or 0
end

function TimerService.cleanup(player: Player)
	timers[player] = nil
end

RunService.Heartbeat:Connect(function(dt: number)
	for _, t in pairs(timers) do
		if t.running then
			t.elapsed += dt
		end
	end
end)

return TimerService
