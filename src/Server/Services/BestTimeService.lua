--!strict
-- ServerScriptService/Services/BestTimeService.lua
-- One persistent best time per player, per level, per mode.
--
-- === Why this is not LeaderboardService ===
--
-- That one is an OrderedDataStore scoped to the ACTIVE SEASON and archived at rollover,
-- which is exactly right for a ranking and exactly wrong for a personal record: a best time
-- read from it disappears when the season turns. A statue that forgets your best time every
-- season is worse than no statue.
--
-- It also records CHILL times, which the leaderboard deliberately does not. This is your own
-- record rather than a ranking, so there is nothing to be unfair about -- and the two modes
-- are kept under separate keys rather than compared, because hardcore resets you to the
-- level start on every fall and the same route is a different task.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local store = DataStoreService:GetDataStore("PersonalBest_v1")

local BestTimeService = {}

-- KEPT FOR A MINUTE. The lobby board shows your best under the rankings and was reading it from the store
-- on every redraw, which is every step anyone takes onto a level pad, for everyone in the room. Each
-- player's bests are kept here for FRESH seconds (and set the moment a new one is written), and let go when
-- the player leaves.
local FRESH = 60
local known: { [Player]: { [string]: { at: number, value: number? } } } = {}

local function remember(player: Player, key: string, value: number?)
	local mine = known[player]
	if not mine then
		mine = {}
		known[player] = mine
	end
	mine[key] = { at = os.clock(), value = value }
end

Players.PlayerRemoving:Connect(function(player: Player)
	known[player] = nil
end)

local function keyFor(player: Player, levelId: number, mode: string): string
	return ("%d_%d_%s"):format(player.UserId, levelId, mode)
end

-- Writes only when the run is faster, so a slow run never overwrites a good one.
--
-- Every call is wrapped: DataStores fail for reasons that have nothing to do with this game
-- (throttling, an outage, Studio without API access) and none of them should be able to stop
-- a player finishing a level.
-- Returns true when this run is the player's new best (and was written).
function BestTimeService.submit(player: Player, levelId: number, mode: string, timeSeconds: number): boolean
	-- NO TIME IS NOT A TIME: a run with no clock (chill) has nothing to keep.
	if timeSeconds <= 0 then
		return false
	end
	local key = keyFor(player, levelId, mode)
	-- COMPARED AND WRITTEN IN ONE STEP (UpdateAsync). Reading first and writing after let a read that failed write
	-- a possibly slower time over a better one; now the store itself compares, so a best is never lost, and when the
	-- store does not answer at all nothing is written (the next run tries again). A stored 0 (a chill "best" from
	-- before chill had no clock) is no time, and no longer stands in the way of a real one.
	local improved = false
	local kept: number? = nil
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(existing: any): any
			improved = false
			kept = nil
			if typeof(existing) == "number" and existing > 0 and existing <= timeSeconds then
				kept = existing
				return nil -- not better: nothing is written
			end
			improved = true
			return timeSeconds
		end)
	end)
	if not ok then
		warn("BestTimeService.submit failed: " .. tostring(err))
		return false
	end
	if improved then
		remember(player, key, timeSeconds)
		return true
	end
	if kept then
		remember(player, key, kept)
	end
	return false
end

function BestTimeService.get(player: Player, levelId: number, mode: string): number?
	local key = keyFor(player, levelId, mode)
	local mine = known[player]
	local kept = mine and mine[key]
	if kept and os.clock() - kept.at < FRESH then
		return kept.value
	end
	local ok, value = pcall(function()
		return store:GetAsync(key)
	end)
	if not ok then
		-- The store did not answer: what was known last, rather than nothing.
		return if kept then kept.value else nil
	end
	-- A 0 saved before submit refused one (a chill "best") reads as no time, not as 00:00.
	local best = if typeof(value) == "number" and value > 0 then value else nil
	if player.Parent then
		remember(player, key, best)
	end
	return best
end

BestTimeService.STAMP = "71828c8e"
return BestTimeService
