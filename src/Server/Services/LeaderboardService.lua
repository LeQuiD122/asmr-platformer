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

-- WHICH BOARD: its store's name, season and all (so a season turning is a new board, not a stale one).
local function boardName(levelId: number, mode: string): string
	return ("Leaderboard_Level%d_%s_%s"):format(levelId, mode, currentSeasonId())
end

local function orderedStoreFor(levelId: number, mode: string)
	-- ONE STORE PER MODE, not one store with both in it.
	--
	-- A chill time and a hardcore time are not comparable: hardcore resets you to the level
	-- start on every fall, so the same route is a different task. Ranked together, every top
	-- entry would be a chill run and the board would tell a hardcore player nothing.
	return DataStoreService:GetOrderedDataStore(boardName(levelId, mode))
end

-- READ ONCE, SHOWN TO MANY. Every step on a level pad redrew every player's board, every flip of the board's
-- lever and every client's RequestLeaderboardData asked Roblox for it again, and an ordered store lets a
-- server read only about 5 + 2 per player of those a minute: a busy lobby ran out, and the board said
-- nothing for everyone (and a client asking over and over could run it out on purpose). Each board is kept
-- for FRESH seconds, read again only after that or after a time is submitted to it, and a second ask while
-- one is on its way waits for that one rather than asking again. A failed read shows the last good board.
local FRESH = 30
-- A READ THAT FAILED is not tried again for RETRY seconds (in Studio without API access every read fails, and a
-- warning on every redraw buried the Output), and said once a minute at most.
local RETRY = 10
local failedAt: { [string]: number } = {}
local saidAt: { [string]: number } = {}
local cache: { [string]: { at: number, rows: { any } } } = {}
local fetching: { [string]: boolean } = {}

local function forget(levelId: number, mode: string)
	local prefix = boardName(levelId, mode) .. "#"
	for key in pairs(cache) do
		if string.sub(key, 1, #prefix) == prefix then
			cache[key] = nil
		end
	end
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

-- LOWER IS BETTER, AND ONLY A BETTER TIME IS WRITTEN, in one step (UpdateAsync): the store compares and writes
-- together, so a read that failed (a busy server, a throttle) can no longer let a slower time over a better one, as
-- reading first and writing after did, and two servers finishing the same player at once cannot cross. A stored 0
-- (never a real time) is no time.
function LeaderboardService.submitTime(player: Player, levelId: number, mode: string, timeSeconds: number)
	local store = orderedStoreFor(levelId, mode)
	local key = tostring(player.UserId)
	local stored = toStored(timeSeconds)
	local improved = false
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(existing: any): any
			improved = false
			if typeof(existing) == "number" and existing > 0 and existing <= stored then
				return nil -- not better: nothing is written
			end
			improved = true
			return stored
		end)
	end)
	if not ok then
		warn("LeaderboardService.submitTime failed: " .. tostring(err))
		return
	end
	-- A NEW TIME ON IT: the next look reads the board again, so the time is there.
	if improved then
		forget(levelId, mode)
	end
end

function LeaderboardService.getTop(levelId: number, mode: string, count: number)
	local key = boardName(levelId, mode) .. "#" .. tostring(count)
	local kept = cache[key]
	if kept and os.clock() - kept.at < FRESH then
		return table.clone(kept.rows)
	end
	local failed = failedAt[key]
	if failed and os.clock() - failed < RETRY then
		return if kept then table.clone(kept.rows) else {}
	end
	-- ALREADY ON ITS WAY for someone else: wait for that read (a few seconds at most).
	if fetching[key] then
		local waited = 0
		while fetching[key] and waited < 10 do
			task.wait(0.1)
			waited += 0.1
		end
		local fresh = cache[key] or kept
		return if fresh then table.clone(fresh.rows) else {}
	end
	fetching[key] = true
	local store = orderedStoreFor(levelId, mode)
	local ok, pages = pcall(function()
		return store:GetSortedAsync(true, count) -- ascending: lowest time first
	end)
	if not ok then
		fetching[key] = nil
		failedAt[key] = os.clock()
		if not saidAt[key] or os.clock() - saidAt[key] > 60 then
			saidAt[key] = os.clock()
			warn("LeaderboardService.getTop failed: " .. tostring(pages))
		end
		return if kept then table.clone(kept.rows) else {}
	end
	local results = {}
	local readOk = pcall(function()
		for _, entry in ipairs(pages:GetCurrentPage()) do
			table.insert(results, { userId = tonumber(entry.key), time = fromStored(entry.value) })
		end
	end)
	fetching[key] = nil
	if not readOk then
		return if kept then table.clone(kept.rows) else {}
	end
	cache[key] = { at = os.clock(), rows = results }
	failedAt[key] = nil
	return table.clone(results)
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

LeaderboardService.STAMP = "5cb1004e"
return LeaderboardService
