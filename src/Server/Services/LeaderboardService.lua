--!strict
-- ServerScriptService/Services/LeaderboardService.lua
-- Hardcore-mode only. Active season via OrderedDataStore (clean top-N reads).
-- At season end, archive snapshot batched into a regular DataStore key
-- (not per-player writes, to stay well under DataStore request limits).

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local LeaderboardService = {}

local SEASON_LENGTH_DAYS = 90 -- 3 months

local function currentSeasonId(): string
	local seasonIndex = math.floor(os.time() / (SEASON_LENGTH_DAYS * 24 * 60 * 60))
	return "Season" .. tostring(seasonIndex)
end

local function orderedStoreFor(levelId: number, mode: string)
	-- ONE STORE PER MODE, not one store with both in it.
	--
	-- A chill time and a hardcore time are not comparable: hardcore resets you to the level
	-- start on every fall, so the same route is a different task. Ranked together, every top
	-- entry would be a chill run and the board would tell a hardcore player nothing.
	return DataStoreService:GetOrderedDataStore(
		("Leaderboard_Level%d_%s_%s"):format(levelId, mode, currentSeasonId()))
end

local archiveStore = DataStoreService:GetDataStore("LeaderboardArchive")

-- TIMES ARE STORED AS WHOLE MILLISECONDS, and this is a correctness requirement rather
-- than a precision choice.
--
-- An OrderedDataStore only accepts INTEGER values -- that is what makes it sortable --
-- and this stored `timeSeconds` straight, a float. Every SetAsync therefore threw, and it
-- threw inside a pcall, so a finished hardcore run warned once into the output and
-- silently saved nothing. The board could never have had a row in it.
--
-- Milliseconds rather than rounded seconds because the timer resolves far finer than a
-- second and two runs of a 300-second level should not tie.
local function toStored(timeSeconds: number): number
	return math.floor(timeSeconds * 1000 + 0.5)
end

local function fromStored(value: number): number
	return value / 1000
end

function LeaderboardService.submitTime(player: Player, levelId: number, mode: string, timeSeconds: number)
	local store = orderedStoreFor(levelId, mode)
	local key = tostring(player.UserId)
	local stored = toStored(timeSeconds)
	local success, existing = pcall(function()
		return store:GetAsync(key)
	end)
	-- Lower time is better; only overwrite if this run is faster (or first run).
	if success and existing and existing <= stored then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync(key, stored)
	end)
	if not ok then
		warn("LeaderboardService.submitTime failed: " .. tostring(err))
	end
end

function LeaderboardService.getTop(levelId: number, mode: string, count: number)
	local store = orderedStoreFor(levelId, mode)
	local ok, pages = pcall(function()
		return store:GetSortedAsync(true, count) -- ascending: lowest time first
	end)
	if not ok then
		warn("LeaderboardService.getTop failed: " .. tostring(pages))
		return {}
	end
	local page = pages:GetCurrentPage()
	local results = {}
	for _, entry in ipairs(page) do
		table.insert(results, { userId = tonumber(entry.key), time = fromStored(entry.value) })
	end
	return results
end

-- Called on season rollover: reads the outgoing season's OrderedDataStore
-- top entries and writes them as ONE batched record to the archive store,
-- avoiding per-player DataStore writes.
function LeaderboardService.archiveSeason(seasonId: string, levelId: number)
	local store = DataStoreService:GetOrderedDataStore("Leaderboard_Level" .. levelId .. "_" .. seasonId)
	local ok, pages = pcall(function()
		return store:GetSortedAsync(true, 100)
	end)
	if not ok then
		warn("LeaderboardService.archiveSeason failed to read: " .. tostring(pages))
		return
	end
	local page = pages:GetCurrentPage()
	local snapshot = {}
	for _, entry in ipairs(page) do
		table.insert(snapshot, { userId = tonumber(entry.key), time = fromStored(entry.value) })
	end
	local archiveKey = ("%s_Level%d"):format(seasonId, levelId)
	local encoded = HttpService:JSONEncode(snapshot)
	local ok2, err2 = pcall(function()
		archiveStore:SetAsync(archiveKey, encoded)
	end)
	if not ok2 then
		warn("LeaderboardService.archiveSeason failed to write: " .. tostring(err2))
	end
end

function LeaderboardService.getSeasonArchive(seasonId: string, levelId: number)
	local archiveKey = ("%s_Level%d"):format(seasonId, levelId)
	local ok, encoded = pcall(function()
		return archiveStore:GetAsync(archiveKey)
	end)
	if not ok or not encoded then
		return {}
	end
	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(encoded)
	end)
	if not decodeOk then
		return {}
	end
	return decoded
end

return LeaderboardService
