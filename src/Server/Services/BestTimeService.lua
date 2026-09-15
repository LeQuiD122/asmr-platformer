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

local store = DataStoreService:GetDataStore("PersonalBest_v1")

local BestTimeService = {}

local function keyFor(player: Player, levelId: number, mode: string): string
	return ("%d_%d_%s"):format(player.UserId, levelId, mode)
end

-- Writes only when the run is faster, so a slow run never overwrites a good one.
--
-- Every call is wrapped: DataStores fail for reasons that have nothing to do with this game
-- (throttling, an outage, Studio without API access) and none of them should be able to stop
-- a player finishing a level.
function BestTimeService.submit(player: Player, levelId: number, mode: string, timeSeconds: number)
	local key = keyFor(player, levelId, mode)
	local readOk, existing = pcall(function()
		return store:GetAsync(key)
	end)
	-- A FAILED READ DOES NOT BLOCK THE WRITE. If the read threw we do not know the old time,
	-- and refusing to write would mean a player whose first ever run happened during an
	-- outage never gets a record at all. Writing a possibly-slower time is the cheaper
	-- mistake: the next faster run corrects it.
	if readOk and typeof(existing) == "number" and existing <= timeSeconds then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(key, timeSeconds)
	end)
	if not ok then
		warn("BestTimeService.submit failed: " .. tostring(err))
	end
end

function BestTimeService.get(player: Player, levelId: number, mode: string): number?
	local ok, value = pcall(function()
		return store:GetAsync(keyFor(player, levelId, mode))
	end)
	if ok and typeof(value) == "number" then
		return value
	end
	return nil
end

return BestTimeService
