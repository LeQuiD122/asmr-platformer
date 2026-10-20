--!strict
-- ServerScriptService/Services/EconomyService.lua
-- TOKENS, WHAT YOU OWN, AND EVERY PURCHASE: the one place any of it changes.
--
-- === The rules this file keeps (nothing is dupable) ===
--
--   * ONE PROFILE PER PLAYER, LOCKED. ProfileStore (by loleris, MadStudioRoblox/ProfileStore, a
--     ModuleScript named exactly ProfileStore in ServerScriptService) holds each player's save with a
--     session lock: two servers can never both hold and save the same player, which is how most
--     Roblox dupes happen (join a second server before the first has saved). Without ProfileStore the
--     game still runs, on an unsaved profile, says so in Output, and refuses Robux purchases outside
--     Studio, because a purchase that cannot be saved would be money lost.
--   * THE CLIENT ASKS, IT NEVER TELLS. ShopRequest takes an action ("buy", "equip", "unequip") and an
--     item id, and nothing else. The price comes from ShopCatalog, the balance from the profile. No
--     request can add tokens, name an amount, or name another player.
--   * TOKENS ARE ADDED IN TWO PLACES ONLY: a run the server watched start and finish (runFinished),
--     and a Robux token pack (ProcessReceipt).
--   * A ROBUX PURCHASE IS GRANTED ONCE. Its PurchaseId is kept in the profile, and Roblox is told
--     PurchaseGranted only once a save containing that id has gone through. A retry, a crash or a
--     second server finds the id and does not grant again.
--   * ONE REQUEST AT A TIME PER PLAYER, and not faster than REQUEST_GAP: a spammed buy cannot race
--     itself.
--
-- The cosmetics you WEAR (trails, auras, footprints, step sounds) are decided HERE, on the server:
-- trails and auras are put on the character, and footprints and step sounds are written on the player
-- (Footprint, StepSound) for every client's StepService to draw and play. The client only ever
-- previews on its own screen.

local AnalyticsService = game:GetService("AnalyticsService")
local BadgeService = game:GetService("BadgeService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ShopCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopCatalog")) :: any
local LevelDefinitions = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LevelDefinitions")) :: any
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local EconomyService = {}

local REQUEST_GAP = 0.25 -- seconds between one player's requests
local PURCHASE_ID_CACHE = 100 -- receipts remembered per profile
local STUDIO_TOKENS = 1000 -- what a fresh profile gets in Studio only, to try the shop
local CURRENCY = "Tokens"
-- What can be worn, one of each at a time (Equipped is kind -> item id); a background is the shop's own (ShopLook).
local WEARABLE = { trail = true, aura = true, steps = true, sound = true, background = true }

-- What a new save looks like. ProfileStore fills in any field an older save is missing (Reconcile).
local TEMPLATE = {
	Tokens = 0,
	Owned = {} :: { [string]: boolean },
	Equipped = {} :: { [string]: string }, -- kind -> item id
	Welcomed = false,
	Guided = false, -- the lobby guide finished or skipped
	Hinted = {} :: { [string]: boolean }, -- materials whose one-time hint has been shown
	ShopIntro = false, -- shown the way to the kiosk after a first finished run
	AskedFavourite = false, -- asked once to favourite the game, after the way to the kiosk (OnboardingService)
	Journal = {} :: { any }, -- what you picked up in Harrow Bay, in order, kept between sessions (keepEntry)
	Finished = {} :: { [string]: boolean }, -- levels finished (level id as text); each opens the next (HubService.isOpen)
	SecondChances = 0, -- hardcore second chances bought and not yet used
	Earned = 0, -- every token ever earned by playing (for the welcome and for the dashboard)
	PurchaseIdCache = {} :: { string },
	StudioGift = false,
	AdminOpen = false, -- an admin's /levels: every level open for them (EconomyService.isAdmin); real progress kept
	StoryAt = 1, -- the story's level to go on from (1, City Shore, is the start): Bootstrap's story
	FoundBackRooms = false, -- fell into the back rooms once: the lobby's back corridor leads there from then on
	DailyDay = 0, -- the day (UTC, days since 1970) the daily chest was last opened (claimDaily)
	DailyStreak = 0, -- days in a row it has been opened
	Caches = {} :: { [string]: boolean }, -- the hidden caches found (level id as text), each paid once (foundCache)
	Challenges = {} :: { [string]: any }, -- today's challenges (challengesToday): the day, their ids, done, runs
	StarterGranted = false, -- the starter pack's tokens and trail given (grantStarter), once a save
	Materials = {} :: { [string]: boolean }, -- the materials stood on in a level (foundMaterial), each paid once
	Codes = {} :: { [string]: boolean }, -- the codes posted in the lobby's post box (handle "code"), each once a save
	-- What you have said to Harrow Bay's people and what they have told you (Townsfolk, Conversations): topic ids, and
	-- "clue:" ids for what you have learned about your father (the hundred-and-fourth pass).
	Heard = {} :: { [string]: boolean },
}

type Profile = {
	Data: any,
	LastSavedData: any,
	IsActive: (any) -> boolean,
	Save: (any) -> (),
	EndSession: (any) -> (),
	OnAfterSave: any,
}

local profiles: { [Player]: Profile } = {}
local passes: { [Player]: { [string]: boolean } } = {}
local busy: { [Player]: boolean } = {}
local lastAsk: { [Player]: number } = {}
local lastNote: { [Player]: { at: number, count: number } } = {}
local lastEmote: { [Player]: number } = {}
local emoteRemote: RemoteEvent? = nil
local runs: { [Player]: { startedAt: number, length: string } } = {}
-- FRIENDS IN THE RUN (withFriend, for ShopCatalog.REWARD.FRIEND): everyone who has been in the server's current run
-- (crew; a new run starts it again, a late joiner is added); who is a Roblox friend of whom, asked once a pair
-- (Player:IsFriendsWith is a web call); who has been told on their card (once while they are here); and the test
-- panel's pretend friend (Studio).
local crew: { [Player]: boolean } = {}
local friendOf: { [Player]: { [number]: boolean } } = {}
local toldFriend: { [Player]: boolean } = {}
local devFriend: { [Player]: boolean } = {}
-- THE MATERIALS FOUND SINCE THIS PLAYER'S RUN BEGAN (foundMaterial), told on its pill: how many, their tokens, and the
-- swatch trail if the last of them was among them.
local foundRun: { [Player]: { count: number, tokens: number, gift: string? } } = {}
-- PAID RANDOM ITEMS (the background crates, opened with tokens that Robux can buy): offered only where Roblox's policy
-- for the player allows them (asked on joining, in load); a crate is rolled with the server's own dice.
local randomOk: { [Player]: boolean } = {}
local crateDice = Random.new()
local saving = false -- true when profiles are really saved (ProfileStore found, API reachable)
local store: any = nil
local updateRemote: RemoteEvent? = nil
local earnedRemote: RemoteEvent? = nil
local levelsChanged: (() -> ())? = nil -- the lobby looks at its locked levels again (Bootstrap wires HubService)
local openReader: ((number) -> boolean)? = nil -- whether the lobby has a level open (HubService.isOpen), for the self-test

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = deepCopy(v)
	end
	return out
end

-- ===== THE SAVE =====

-- A profile that lives only as long as the server: the fallback without ProfileStore. Everything
-- works on it and none of it is kept.
local function memoryProfile(): Profile
	local data = deepCopy(TEMPLATE)
	local profile = {
		Data = data,
		LastSavedData = data,
		OnAfterSave = nil,
	}
	function profile.IsActive(_self: any): boolean
		return true
	end
	function profile.Save(_self: any) end
	function profile.EndSession(_self: any) end
	return profile :: any
end

local function openStore()
	local module = ServerScriptService:FindFirstChild("ProfileStore")
		or ServerScriptService:FindFirstChild("ProfileStore", true)
	if not (module and module:IsA("ModuleScript")) then
		warn("EconomyService: no ProfileStore in ServerScriptService, so tokens and purchases are NOT SAVED this "
			.. "session. Get ProfileStore (by loleris) from the Creator Store or github.com/MadStudioRoblox/ProfileStore, "
			.. "put the ModuleScript in ServerScriptService named exactly ProfileStore, and turn on Studio Access to "
			.. "API Services (Game Settings, Security) to save while testing.")
		return
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn("EconomyService: ProfileStore failed to load, so nothing is saved this session: " .. tostring(result))
		return
	end
	-- NOT LOLERIS'S PROFILESTORE: something else named ProfileStore (his older ProfileService has GetProfileStore, not
	-- New). Said plainly, with where it is, rather than as "attempt to call a nil value".
	if type(result) ~= "table" or type((result :: any).New) ~= "function" then
		local older = type(result) == "table" and type((result :: any).GetProfileStore) == "function"
		warn(("EconomyService: %s is not loleris's ProfileStore (it has no ProfileStore.New%s), so nothing is saved this "
			.. "session. Put ProfileStore from github.com/MadStudioRoblox/ProfileStore in ServerScriptService, named "
			.. "exactly ProfileStore, in its place."):format(module:GetFullName(),
			if older then "; it is ProfileService, the older library" else ""))
		return
	end
	-- STUDIO HAS ITS OWN SAVES, so testing the shop never touches what players have in the live game.
	local name = if RunService:IsStudio() then "PlayerData_Studio" else "PlayerData"
	local made, opened = pcall(function()
		return (result :: any).New(name, TEMPLATE)
	end)
	if made then
		store = opened
		saving = true
	else
		warn("EconomyService: ProfileStore.New failed, so nothing is saved this session: " .. tostring(opened))
	end
end

-- ===== WHAT THE CLIENT IS TOLD =====

local function owns(player: Player, id: string): boolean
	local profile = profiles[player]
	if not profile then
		return false
	end
	if profile.Data.Owned[id] then
		return true
	end
	-- A PASS is owned while Roblox says so (passes, from checkPasses), so the shop shows it Owned.
	if passes[player] and passes[player][id] then
		return true
	end
	-- VIP comes with the gold sparkle.
	if id == "Sparkle" and passes[player] and passes[player].VIP then
		return true
	end
	return false
end

local function stateFor(player: Player): any
	local profile = profiles[player]
	if not profile then
		return { ready = false, saving = saving }
	end
	local owned = {}
	for _, item in ipairs(ShopCatalog.all()) do
		if owns(player, item.id) then
			owned[item.id] = true
		end
	end
	return {
		ready = true,
		saving = saving,
		tokens = profile.Data.Tokens,
		owned = owned,
		equipped = deepCopy(profile.Data.Equipped),
		passes = deepCopy(passes[player] or {}),
		welcomed = profile.Data.Welcomed,
		guided = profile.Data.Guided,
		hinted = deepCopy(profile.Data.Hinted),
		shopIntro = profile.Data.ShopIntro,
		askedFavourite = profile.Data.AskedFavourite,
		earned = profile.Data.Earned,
		chances = profile.Data.SecondChances,
		crates = randomOk[player] == true, -- the background crates offered (Roblox's policy for paid random items)
	}
end

local function push(player: Player)
	local profile = profiles[player]
	if profile then
		player:SetAttribute("Tokens", profile.Data.Tokens)
	end
	if updateRemote then
		updateRemote:FireClient(player, stateFor(player))
	end
end

-- THE COLLECTION, SHOWN TO EVERYONE: how many keepsakes you have found, as a Keepsakes column in Roblox's own
-- player list (leaderstats), so the people in your server can see it. Counted from the journal kept between
-- sessions, so it is the whole collection, not this session's.
local function showCollection(player: Player)
	local profile = profiles[player]
	if not profile or player.Parent ~= Players then
		return
	end
	local count = 0
	for _, kept in ipairs(profile.Data.Journal or {}) do
		if kept.kind == "keepsake" then
			count += 1
		end
	end
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		stats.Parent = player
	end
	local value = (stats :: Instance):FindFirstChild("Keepsakes")
	if not (value and value:IsA("IntValue")) then
		value = Instance.new("IntValue")
		value.Name = "Keepsakes"
		value.Parent = stats
	end
	local counter = value :: IntValue
	counter.Value = count
end

local function logEconomy(player: Player, source: boolean, amount: number, kind: string, sku: string?)
	local profile = profiles[player]
	if not profile then
		return
	end
	pcall(function()
		AnalyticsService:LogEconomyEvent(player,
			if source then Enum.AnalyticsEconomyFlowType.Source else Enum.AnalyticsEconomyFlowType.Sink,
			CURRENCY, amount, profile.Data.Tokens, kind, sku)
	end)
end

-- THE FIRST FIVE MINUTES, step by step, for the Creator Dashboard's onboarding funnel: where new
-- players stop.
local function funnel(player: Player, step: number, name: string)
	pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name)
	end)
end

-- ===== THE COSMETICS EVERYONE SEES =====

-- Worn on the server so everyone sees them; built by ShopCatalog.wear, the same builder the shop's
-- try-on uses on your own screen.
-- WHAT ANYONE HAS FINISHED CHANGED (a save loaded or gone, a level finished): the lobby opens or locks its levels.
-- ===== THE DAILY CHEST =====
--
-- The lobby's chest (HubService), opened once a day: days are UTC (Roblox's servers keep that clock), so the next
-- one opens at midnight UTC. Opened the day after the last time, the streak goes on; a day missed starts it again.
-- What it pays is ShopCatalog.dailyReward(streak), day seven's from then on while the streak lasts.
local DAY = 86400

local function today(): number
	return math.floor(os.time() / DAY)
end

-- What each player's own screen is told: when the next chest opens (0 when it is ready now, on the server's clock,
-- which is what workspace:GetServerTimeNow reads), and the streak so far.
local function dailyAttributes(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local day = tonumber(profile.Data.DailyDay) or 0
	player:SetAttribute("DailyNext", if day == today() then (day + 1) * DAY else 0)
	player:SetAttribute("DailyStreak", tonumber(profile.Data.DailyStreak) or 0)
end

local function tellLevels()
	local changed = levelsChanged
	if changed then
		local ok, err = pcall(changed :: any)
		if not ok then
			warn("EconomyService: the lobby could not look at its levels again: " .. tostring(err))
		end
	end
end

-- ===== BADGES =====
--
-- Roblox's own badges (ShopCatalog.BADGES), awarded by the server for what was really played. An id of 0 is a badge
-- not made yet, and nothing is asked. Each is asked for once per player a session (Roblox limits badge calls); one
-- already owned is Roblox's to ignore, so an older save that finished a level before its badge existed gets it the
-- next time it finishes that level.
local badgeAsked: { [Player]: { [number]: boolean } } = {}

function EconomyService.awardBadge(player: Player, badgeId: any)
	if type(badgeId) ~= "number" or badgeId == 0 then
		return
	end
	local asked = badgeAsked[player] or {}
	badgeAsked[player] = asked
	if asked[badgeId] then
		return
	end
	asked[badgeId] = true
	task.spawn(function()
		local ok, err = pcall(function()
			BadgeService:AwardBadge(player.UserId, badgeId)
		end)
		if not ok then
			warn(("EconomyService: badge %d for %s was not awarded: %s"):format(badgeId, player.Name, tostring(err)))
		end
	end)
end

-- THE STORY'S BADGES (Bootstrap, after its last level): played to the end, and a whole story in Hardcore.
function EconomyService.awardStoryBadges(player: Player, wholeHardcore: boolean)
	local badges = ShopCatalog.BADGES
	if type(badges) ~= "table" then
		return
	end
	EconomyService.awardBadge(player, badges.story)
	if wholeHardcore then
		EconomyService.awardBadge(player, badges.storyHardcore)
	end
end

-- ===== ADMINS =====
--
-- WHO MAY OPEN EVERY LEVEL FOR THEMSELVES, with /levels in chat: the game's owner (for a group game, the group's
-- owner), anyone whose user id is in ADMIN_IDS, and anyone in Studio. Their own save's progress is not touched: with
-- it on (AdminOpen, kept in the save) the lobby counts them as having finished every level, so every level is open
-- while they are in a server. A run is the whole room's, so the room they are in can play those levels with them;
-- nobody else's progress changes unless they finish a level themselves. The same command turns it off.
local ADMIN_IDS: { [number]: boolean } = {
	-- [123456789] = true, -- a user id per line, for anyone else who should have it
}
local groupOwner: { [Player]: boolean } = {}
local adminNotifier: ((Player, boolean) -> ())? = nil

function EconomyService.isAdmin(player: Player): boolean
	if RunService:IsStudio() or ADMIN_IDS[player.UserId] == true then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return game.CreatorId ~= 0 and player.UserId == game.CreatorId
	end
	return groupOwner[player] == true
end

function EconomyService.setAdminNotifier(fn)
	adminNotifier = fn
end

-- /levels: every level open for this admin, or back to their own progress. Anyone else is ignored.
local function toggleAdminOpen(player: Player)
	local profile = profiles[player]
	if not (profile and profile:IsActive()) or not EconomyService.isAdmin(player) then
		return
	end
	local on = profile.Data.AdminOpen ~= true
	profile.Data.AdminOpen = on
	print(("EconomyService: %s (admin) has every level %s."):format(player.Name,
		if on then "open for them" else "back to their own progress"))
	tellLevels()
	local notify = adminNotifier
	if notify then
		local ok, err = pcall(notify :: any, player, on)
		if not ok then
			warn("EconomyService: telling an admin about /levels failed: " .. tostring(err))
		end
	end
end

-- The save's finished levels, made if an older save has none.
local function finishedOf(data: any): { [string]: boolean }
	if type(data.Finished) ~= "table" then
		data.Finished = {}
	end
	return data.Finished
end

-- ===== DAILY CHALLENGES =====
--
-- Three a day for each player (ShopCatalog.pickChallenges), picked the first time their save sees the day, from what
-- they can do: a level's only once that level is open to them in their own save (the level before it, or any later
-- one, finished, as the lobby opens them). Done by finishing runs (challengeRun, from runFinished), each paid once
-- that day. Their own screen is told by attributes, for the lobby's board and the card: Challenges (today's ids),
-- ChallengesDone, ChallengeRuns, and ChallengeNext (when new ones come, on the server's clock).
local function canChallenge(data: any, challenge: any): boolean
	local level = challenge.level
	if level == nil then
		return true
	end
	local at = nil
	for index, each in ipairs(LevelDefinitions.All) do
		if each.levelId == level then
			at = index
		end
	end
	if at == nil then
		return false
	end
	if at == 1 then
		return true
	end
	local finished = finishedOf(data)
	for index = at - 1, #LevelDefinitions.All do
		if finished[tostring(LevelDefinitions.All[index].levelId)] == true then
			return true
		end
	end
	return false
end

local function challengesToday(data: any): any
	local now = today()
	local state = data.Challenges
	if type(state) ~= "table" or state.day ~= now or type(state.ids) ~= "table" or type(state.done) ~= "table" then
		state = {
			day = now,
			ids = ShopCatalog.pickChallenges(now, function(challenge)
				return canChallenge(data, challenge)
			end),
			done = {},
			runs = 0,
		}
		data.Challenges = state
	end
	return state
end

local function challengeAttributes(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local state = challengesToday(profile.Data)
	local done = {}
	for _, id in ipairs(state.ids) do
		if state.done[id] then
			table.insert(done, id)
		end
	end
	player:SetAttribute("Challenges", table.concat(state.ids, ","))
	player:SetAttribute("ChallengesDone", table.concat(done, ","))
	player:SetAttribute("ChallengeRuns", tonumber(state.runs) or 0)
	player:SetAttribute("ChallengeNext", (state.day + 1) * DAY)
end

-- THE MATERIALS FOUND, for the player's own screen (the journal's pages, the lobby's board, the chime): Materials, the
-- keys found in the catalogue's order, and MaterialsFound, how many.
local function materialsAttribute(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local found = if type(profile.Data.Materials) == "table" then profile.Data.Materials else {}
	local keys = {}
	for _, material in ipairs(ShopCatalog.MATERIALS) do
		if found[material.key] then
			table.insert(keys, material.key)
		end
	end
	player:SetAttribute("Materials", table.concat(keys, ","))
	player:SetAttribute("MaterialsFound", #keys)
end

-- THE VIP TAG, over a VIP player's head in the lobby and the squish room, for everyone in the server to see: a
-- BillboardGui on their Head, the server's, so every client draws it. Put away on a level (InLevel set), where a
-- run is played with nothing over anyone. In the VIP pass's own colours, rounded like the shop's tiles.
local VIP_TAG = "VipTag"
local VIP_FILL = Color3.fromRGB(206, 203, 246)
local VIP_INK = Color3.fromRGB(38, 33, 92)

local function vipTag(player: Player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then
		return
	end
	local existing = head:FindFirstChild(VIP_TAG)
	local isVip = passes[player] ~= nil and passes[player].VIP == true
	if not isVip then
		if existing then
			existing:Destroy()
		end
		return
	end
	local tag = existing
	if not (tag and tag:IsA("BillboardGui")) then
		-- THE BADGE: a rounded plaque in the VIP pass's colours, gold into lilac into pink, with a white rim; VIP in the
		-- shop's own chunky letters, white with a dark outline; a little gold crown of three points sitting on it; and
		-- a shine that sweeps across it now and then (ShopService plays the shine on each screen). It was a plain
		-- lilac pill with VIP in it.
		local gui = Instance.new("BillboardGui")
		gui.Name = VIP_TAG
		gui.Size = UDim2.new(2.7, 0, 1.25, 0) -- studs, so it shrinks with distance like the head it is on
		gui.StudsOffsetWorldSpace = Vector3.new(0, 3.35, 0) -- over the name Roblox shows
		gui.MaxDistance = 80
		gui.LightInfluence = 0
		gui.AlwaysOnTop = false
		local pill = Instance.new("Frame")
		pill.Name = "Pill"
		pill.AnchorPoint = Vector2.new(0.5, 1)
		pill.Position = UDim2.fromScale(0.5, 1)
		pill.Size = UDim2.fromScale(1, 0.72)
		pill.BackgroundColor3 = Color3.new(1, 1, 1)
		pill.ClipsDescendants = true
		pill.Parent = gui
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = pill
		local fill = Instance.new("UIGradient")
		fill.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 214, 120)),
			ColorSequenceKeypoint.new(0.5, VIP_FILL), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 160, 210)) })
		fill.Rotation = 15
		fill.Parent = pill
		local rim = Instance.new("UIStroke")
		rim.Color = Color3.fromRGB(255, 255, 255)
		rim.Thickness = 2
		rim.Transparency = 0.1
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rim.Parent = pill
		local word = Instance.new("TextLabel")
		word.Name = "Word"
		word.BackgroundTransparency = 1
		word.AnchorPoint = Vector2.new(0.5, 0.5)
		word.Position = UDim2.fromScale(0.5, 0.52)
		word.Size = UDim2.fromScale(0.8, 0.78)
		word.FontFace = Style.FONT.display
		word.TextScaled = true
		word.Text = "VIP"
		word.TextColor3 = Color3.fromRGB(255, 255, 255)
		word.TextStrokeColor3 = VIP_INK
		word.TextStrokeTransparency = 0
		word.ZIndex = 3
		word.Parent = pill
		-- THE SHINE: the plaque's own shape over it, white, seen only along a slanting band of its gradient; ShopService
		-- slides the band across (the gradient's Offset). A bar clipped by the plaque would have shown past its round
		-- ends: a frame clips its children square, whatever its corners.
		local shine = Instance.new("Frame")
		shine.Name = "Shine"
		shine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		shine.BorderSizePixel = 0
		shine.Size = UDim2.fromScale(1, 1)
		shine.ZIndex = 2
		shine.Parent = pill
		local shineCorner = Instance.new("UICorner")
		shineCorner.CornerRadius = UDim.new(0.5, 0)
		shineCorner.Parent = shine
		local sweep = Instance.new("UIGradient")
		sweep.Name = "Sweep"
		sweep.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1),
			NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1) })
		sweep.Rotation = 20
		sweep.Offset = Vector2.new(-1, 0)
		sweep.Parent = shine
		-- THE CROWN: three gold points on a band, sitting on the plaque's top edge.
		local crown = Instance.new("Frame")
		crown.Name = "Crown"
		crown.BackgroundTransparency = 1
		crown.AnchorPoint = Vector2.new(0.5, 1)
		crown.Position = UDim2.fromScale(0.5, 0.34)
		crown.Size = UDim2.fromScale(0.36, 0.34)
		crown.ZIndex = 4 -- over the plaque's top edge, which it sits on
		crown.Parent = gui
		local gold, goldEdge = Color3.fromRGB(255, 208, 84), Color3.fromRGB(150, 96, 20)
		for k = 0, 2 do
			local point = Instance.new("Frame")
			point.Name = "Point"
			point.AnchorPoint = Vector2.new(0.5, 0.5)
			-- The middle one tallest; each one's lower corner inside the band, so none stands off it.
			point.Position = UDim2.fromScale(0.18 + 0.32 * k, if k == 1 then 0.4 else 0.5)
			point.Size = UDim2.fromScale(0.26, 0.5)
			point.SizeConstraint = Enum.SizeConstraint.RelativeYY
			point.Rotation = 45
			point.BackgroundColor3 = gold
			point.ZIndex = 4
			point.Parent = crown
			local pointEdge = Instance.new("UIStroke")
			pointEdge.Color = goldEdge
			pointEdge.Thickness = 1
			pointEdge.Parent = point
		end
		local band = Instance.new("Frame")
		band.Name = "Band"
		band.AnchorPoint = Vector2.new(0.5, 1)
		band.Position = UDim2.fromScale(0.5, 1)
		band.Size = UDim2.fromScale(1, 0.36)
		band.BackgroundColor3 = gold
		band.ZIndex = 5
		band.Parent = crown
		local bandCorner = Instance.new("UICorner")
		bandCorner.CornerRadius = UDim.new(0.3, 0)
		bandCorner.Parent = band
		local bandEdge = Instance.new("UIStroke")
		bandEdge.Color = goldEdge
		bandEdge.Thickness = 1
		bandEdge.Parent = band
		gui.Parent = head
		tag = gui
	end
	local shown = tag :: BillboardGui
	shown.Enabled = player:GetAttribute("InLevel") == nil
end

local function dress(player: Player)
	local profile = profiles[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (profile and root and root:IsA("BasePart")) then
		return
	end
	local trail = ShopCatalog.get(profile.Data.Equipped.trail)
	local aura = ShopCatalog.get(profile.Data.Equipped.aura)
	ShopCatalog.wear(root,
		if trail and owns(player, trail.id) then trail else nil,
		if aura and owns(player, aura.id) then aura else nil,
		"Cosmetic")
	vipTag(player)
end

-- FOOTPRINTS AND STEP SOUNDS, on the player for every client to see and hear (StepService). Written
-- whether or not there is a character, so they are there the moment one spawns.
local function stepGear(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local steps = ShopCatalog.get(profile.Data.Equipped.steps)
	local sound = ShopCatalog.get(profile.Data.Equipped.sound)
	player:SetAttribute("Footprint", if steps and steps.kind == "steps" and owns(player, steps.id) then steps.id else nil)
	player:SetAttribute("StepSound", if sound and sound.kind == "sound" and owns(player, sound.id) then sound.id else nil)
end

-- ===== LOADING AND LEAVING =====

-- Whether `player` owns the pass `item`: true, false, or nil when Roblox did not answer.
local function ownsPass(player: Player, item: any): boolean?
	local ok, has = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, item.passId :: number)
	end)
	if not ok then
		return nil
	end
	return has == true
end

-- THE STARTER PACK (a pass, so Roblox sells it once): its tokens and its trail, given once a save the first time the
-- pass is found (on joining, or the moment it is bought), and told with the usual pill. Not saved yet when the server
-- stops, it is given again next time, never twice once saved.
local function grantStarter(player: Player)
	local profile = profiles[player]
	local owned = passes[player]
	local starter = ShopCatalog.get("StarterPack")
	if not (profile and profile:IsActive() and owned and owned.StarterPack and starter) then
		return
	end
	local data = profile.Data
	if data.StarterGranted then
		return
	end
	data.StarterGranted = true
	local starterTokens = starter.tokens or 0
	data.Tokens += starterTokens
	local gift = if starter.gives then ShopCatalog.get(starter.gives) else nil
	if gift then
		data.Owned[gift.id] = true
	end
	logEconomy(player, true, starterTokens, Enum.AnalyticsEconomyTransactionType.IAP.Name, starter.id)
	push(player)
	if earnedRemote then
		earnedRemote:FireClient(player, starterTokens, { starter = true, gift = if gift then gift.name else nil })
	end
end

local function checkPasses(player: Player)
	local owned = passes[player] or {}
	passes[player] = owned
	local unsure = {}
	for _, item in ipairs(ShopCatalog.all()) do
		if (item.kind == "pass" or item.kind == "background") and item.passId and item.passId ~= 0 and not owned[item.id] then
			local has = ownsPass(player, item)
			if has then
				owned[item.id] = true
			elseif has == nil then
				table.insert(unsure, item)
			end
		end
	end
	player:SetAttribute("VIP", owned.VIP == true)
	player:SetAttribute("DoubleTokens", owned.DoubleTokens == true)
	grantStarter(player)
	-- A CHECK THAT FAILED IS ASKED AGAIN: Roblox's ownership check can fail for a moment, and someone who paid for
	-- VIP or 2x tokens would have gone without it for the whole session. Five more times, further apart each
	-- time (2, 4, 8, 16 and 32 seconds), and the pass is theirs the moment one answers.
	if #unsure > 0 then
		task.spawn(function()
			local gap = 2
			for _ = 1, 5 do
				task.wait(gap)
				gap *= 2
				if player.Parent ~= Players then
					return
				end
				local still = {}
				local found = false
				for _, item in ipairs(unsure) do
					local has = ownsPass(player, item)
					if has then
						owned[item.id] = true
						found = true
					elseif has == nil then
						table.insert(still, item)
					end
				end
				unsure = still
				if found then
					player:SetAttribute("VIP", owned.VIP == true)
					player:SetAttribute("DoubleTokens", owned.DoubleTokens == true)
					grantStarter(player)
					push(player)
					dress(player)
				end
				if #unsure == 0 then
					return
				end
			end
			warn(("EconomyService: could not tell whether %s owns %d pass(es); they will be checked again on rejoining.")
				:format(player.Name, #unsure))
		end)
	end
end

local function load(player: Player)
	local profile: Profile? = nil
	if store then
		local ok, result = pcall(function()
			return store:StartSessionAsync(tostring(player.UserId), {
				Cancel = function()
					return player.Parent ~= Players
				end,
			})
		end)
		if ok and result then
			local p = result :: any
			pcall(function()
				p:AddUserId(player.UserId)
				p:Reconcile()
			end)
			-- THE SESSION WAS TAKEN by another server (the player joined somewhere else): this server
			-- lets go of the player rather than keep playing on a save it no longer holds.
			p.OnSessionEnd:Connect(function()
				profiles[player] = nil
				player:Kick("Your save was opened on another server. Please rejoin.")
			end)
			profile = p
		elseif not ok then
			warn("EconomyService: loading " .. player.Name .. "'s save failed: " .. tostring(result))
		end
		if not profile then
			-- IN STUDIO, carry on unsaved (API access is often off there); LIVE, a player is never let
			-- play on a save that did not load, or what they earn and buy would be lost.
			if RunService:IsStudio() then
				warn("EconomyService: no save session in Studio, so this test is unsaved. Turn on Studio Access to "
					.. "API Services (Game Settings, Security) to test saving.")
				profile = memoryProfile()
			else
				if player.Parent == Players then
					player:Kick("Your save could not be loaded. Please rejoin in a moment.")
				end
				return
			end
		end
	else
		profile = memoryProfile()
	end
	local ready = profile :: Profile
	if player.Parent ~= Players then
		ready:EndSession()
		return
	end
	-- IN STUDIO ONLY, a pocketful of tokens on a fresh save, to try the shop with. Studio's saves are
	-- their own store (see openStore), so this never reaches the live game.
	if RunService:IsStudio() and not ready.Data.StudioGift then
		ready.Data.StudioGift = true
		ready.Data.Tokens += STUDIO_TOKENS
	end
	-- A GROUP GAME'S OWNER is an admin (isAdmin); asked once, here, because the answer waits on Roblox.
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(game.CreatorId)
		end)
		groupOwner[player] = ok and rank == 255
	end
	-- PAID RANDOM ITEMS (the background crates): only where Roblox's policy for this player allows them, asked once,
	-- here; not offered when the answer does not come. In Studio they are offered whatever it says, to test them.
	local okPolicy, policy = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	randomOk[player] = okPolicy and type(policy) == "table" and policy.ArePaidRandomItemsRestricted == false
	if RunService:IsStudio() and not randomOk[player] then
		randomOk[player] = true
		warn("EconomyService: Roblox's policy for you does not allow paid random items, or did not answer; the "
			.. "background crates are offered anyway in Studio, to test them. The live game would not offer them to you.")
	end
	profiles[player] = ready
	dailyAttributes(player)
	challengeAttributes(player)
	materialsAttribute(player)
	stepGear(player)
	showCollection(player)
	if not ready.Data.Welcomed then
		funnel(player, 1, "Welcome shown")
	end
	checkPasses(player)
	push(player)
	dress(player)
	-- Whatever they have finished opens in the lobby for everyone here.
	tellLevels()
end

local function unload(player: Player)
	local profile = profiles[player]
	profiles[player] = nil
	passes[player] = nil
	groupOwner[player] = nil
	badgeAsked[player] = nil
	busy[player] = nil
	lastAsk[player] = nil
	lastNote[player] = nil
	lastEmote[player] = nil
	runs[player] = nil
	crew[player] = nil
	friendOf[player] = nil
	toldFriend[player] = nil
	devFriend[player] = nil
	foundRun[player] = nil
	randomOk[player] = nil
	if profile then
		profile:EndSession()
	end
	-- What they had opened closes again unless someone still here has finished it too.
	tellLevels()
end

-- ===== WHAT THE CLIENT CAN ASK =====

local ACTIONS = { buy = true, equip = true, unequip = true, code = true, crate = true }

local function answer(player: Player, ok: boolean, reason: string?): any
	return { ok = ok, reason = reason, state = stateFor(player) }
end

local function handle(player: Player, action: any, id: any): any
	if typeof(action) ~= "string" or not ACTIONS[action] then
		return answer(player, false, "unknown")
	end
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return answer(player, false, "loading")
	end
	-- A CODE POSTED in the lobby's post box (ShopCatalog.CODES): its tokens once a save, while it lasts; otherwise why
	-- not (unknown, ended, used), for the box to say. Told with the usual pill.
	if action == "code" then
		local key = ShopCatalog.codeKey(id)
		local entry = if key then ShopCatalog.code(key) else nil
		if not (key and entry) then
			return answer(player, false, "unknown")
		end
		local ends = ShopCatalog.codeEnds(entry)
		if not ends or os.time() >= ends then
			return answer(player, false, "ended")
		end
		local data = profile.Data
		if type(data.Codes) ~= "table" then
			data.Codes = {}
		end
		if data.Codes[key] then
			return answer(player, false, "used")
		end
		data.Codes[key] = true
		local codeTokens = entry.tokens
		data.Tokens += codeTokens
		logEconomy(player, true, codeTokens, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Code")
		-- THE DASHBOARD: which code (CustomField01), so you can see which of your posts brought players back.
		pcall(function()
			AnalyticsService:LogCustomEvent(player, "CodeRedeemed", codeTokens,
				{ [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = key })
		end)
		if earnedRemote then
			earnedRemote:FireClient(player, codeTokens, { code = key })
		end
		return answer(player, true)
	end
	-- UNEQUIP names a kind of thing ("trail", "aura", "steps", "sound"), not an item.
	if action == "unequip" then
		if typeof(id) ~= "string" or not WEARABLE[id] then
			return answer(player, false, "unknown")
		end
		profile.Data.Equipped[id] = nil
		dress(player)
		stepGear(player)
		return answer(player, true)
	end
	local item = ShopCatalog.get(id)
	if not item then
		return answer(player, false, "unknown")
	end
	if item.soon then
		return answer(player, false, "soon")
	end
	-- A BACKGROUND CRATE (ShopCatalog.CRATE, the hundred-and-sixth pass): rolled here, never on the client, and always
	-- one you do not have yet (ShopCatalog.rollCrate); nothing once you have them all. Never where Roblox's policy for
	-- the player keeps paid random items out (randomOk). A crate is opened, never bought as a thing; nothing else is.
	if action == "crate" or item.kind == "crate" then
		if action ~= "crate" or item.kind ~= "crate" or not item.price then
			return answer(player, false, "unknown")
		end
		if randomOk[player] ~= true then
			return answer(player, false, "restricted")
		end
		local data = profile.Data
		local won = ShopCatalog.rollCrate(function(other: string): boolean
			return owns(player, other)
		end, crateDice:NextNumber(), crateDice:NextNumber())
		if not won then
			return answer(player, false, "owned")
		end
		if data.Tokens < item.price then
			return answer(player, false, "short")
		end
		data.Tokens -= item.price
		data.Owned[won.id] = true
		logEconomy(player, false, item.price, Enum.AnalyticsEconomyTransactionType.Shop.Name, item.id)
		pcall(function()
			AnalyticsService:LogCustomEvent(player, "CrateOpened", 1,
				{ [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = won.rarity or "" })
		end)
		local opened = answer(player, true)
		opened.won = won.id
		return opened
	end
	-- EARNED, NEVER SOLD (the green ribbon: finishStory gives it).
	if action == "buy" and item.earn then
		return answer(player, false, "earned")
	end
	if action == "buy" then
		local price = item.price
		if not price or price <= 0 then
			return answer(player, false, "robux") -- a Robux item is bought through Roblox, never here
		end
		if owns(player, item.id) then
			return answer(player, false, "owned")
		end
		if profile.Data.Tokens < price then
			return answer(player, false, "short")
		end
		profile.Data.Tokens -= price
		profile.Data.Owned[item.id] = true
		logEconomy(player, false, price, Enum.AnalyticsEconomyTransactionType.Shop.Name, item.id)
		-- A NEW THING IS WORN AT ONCE, which is what anyone who just bought it wants.
		if WEARABLE[item.kind] then
			profile.Data.Equipped[item.kind] = item.id
			dress(player)
			stepGear(player)
		end
		return answer(player, true)
	end
	-- EQUIP: only what you own, only what can be worn.
	if not WEARABLE[item.kind] then
		return answer(player, false, "unknown")
	end
	if not owns(player, item.id) then
		return answer(player, false, "not owned")
	end
	profile.Data.Equipped[item.kind] = item.id
	dress(player)
	stepGear(player)
	return answer(player, true)
end

local function onRequest(player: Player, action: any, id: any): any
	local now = os.clock()
	if busy[player] or now - (lastAsk[player] or 0) < REQUEST_GAP then
		return answer(player, false, "busy")
	end
	busy[player] = true
	lastAsk[player] = now
	local ok, result = pcall(handle, player, action, id)
	busy[player] = nil
	if not ok then
		warn("EconomyService: a shop request failed: " .. tostring(result))
		return answer(player, false, "error")
	end
	push(player)
	return result
end

-- ===== THE FIRST FIVE MINUTES (OnboardingService on the client) =====
--
-- What a new player has seen, kept so it is seen once: the welcome, the lobby guide, each material's
-- hint, the way to the kiosk. The client NOTES that it has shown something; it can set these flags and
-- nothing else (no tokens, nothing owned), and only for itself.
local NOTES = { welcomed = true, guided = true, hinted = true, shopIntro = true, favourite = true }
local MAX_HINTS = 64

local function onNote(player: Player, what: any, name: any)
	if typeof(what) ~= "string" or not NOTES[what] then
		return
	end
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return
	end
	-- A FEW AT A TIME: a welcome finished and skipped arrives as two notes together, which is fine;
	-- a stream of them is not.
	local now = os.clock()
	local window = lastNote[player]
	if not window or now - window.at > 2 then
		window = { at = now, count = 0 }
		lastNote[player] = window
	end
	window.count += 1
	if window.count > 8 then
		return
	end
	local data = profile.Data
	if what == "welcomed" then
		if data.Welcomed then
			return
		end
		data.Welcomed = true
		funnel(player, 2, "Welcome finished")
	elseif what == "guided" then
		if data.Guided then
			return
		end
		data.Guided = true
		funnel(player, 3, "Lobby guide finished")
	elseif what == "hinted" then
		if typeof(name) ~= "string" or #name > 24 or not name:match("^%a+$") or data.Hinted[name] then
			return
		end
		local count = 0
		for _ in pairs(data.Hinted) do
			count += 1
		end
		if count >= MAX_HINTS then
			return
		end
		if count == 0 then
			funnel(player, 5, "First material hint")
		end
		data.Hinted[name] = true
	elseif what == "shopIntro" then
		if data.ShopIntro then
			return
		end
		data.ShopIntro = true
		funnel(player, 7, "Shop after first run")
	elseif what == "favourite" then
		if data.AskedFavourite then
			return
		end
		data.AskedFavourite = true
	end
	push(player)
end

-- ===== THE JOURNAL, KEPT BETWEEN SESSIONS =====
--
-- What you picked up in Harrow Bay, in the order you picked it up: notes, keepsakes and secrets, so a
-- collection carries on where it left off. Only the server writes it (Interactables.take, from a prompt Roblox
-- has already checked), and only what the story itself says: there is nothing in it for a client to forge.
-- Capped, so a save cannot grow without end. Read back by JournalService through JournalState, with the
-- reader's name put into the letters that use it.
local JOURNAL_MOST = 200
local JOURNAL_FIELDS = { "kind", "title", "body", "from", "secret", "total", "material" }
local lastJournal: { [Player]: number } = {}

function EconomyService.keepEntry(player: Player, record: { [string]: any })
	local profile = profiles[player]
	if not (profile and profile:IsActive()) then
		return
	end
	local id = record.id
	if typeof(id) ~= "string" or #id > 160 then
		return
	end
	local journal = profile.Data.Journal
	if #journal >= JOURNAL_MOST then
		return
	end
	for _, kept in ipairs(journal) do
		if kept.id == id then
			return
		end
	end
	local kept: { [string]: any } = { id = id }
	for _, field in ipairs(JOURNAL_FIELDS) do
		local value = record[field]
		if typeof(value) == "string" then
			kept[field] = string.sub(value, 1, 4000)
		elseif typeof(value) == "number" then
			kept[field] = value
		end
	end
	table.insert(journal, kept)
	if kept.kind == "keepsake" then
		showCollection(player)
	end
end

-- The ids already kept, as a set (Interactables counts the secrets found in earlier sessions with it).
function EconomyService.keptIds(player: Player): { [string]: boolean }?
	local profile = profiles[player]
	if not profile then
		return nil
	end
	local ids = {}
	for _, kept in ipairs(profile.Data.Journal) do
		ids[kept.id] = true
	end
	return ids
end

-- JOURNALSTATE: the journal as it was saved, once the save has loaded (ready = false until then, and for
-- a client asking more than twice a second).
local function onJournal(player: Player): any
	local now = os.clock()
	local last = lastJournal[player]
	if last and now - last < 0.5 then
		return { ready = false }
	end
	lastJournal[player] = now
	local profile = profiles[player]
	if not profile then
		return { ready = false }
	end
	local name = string.upper(player.DisplayName)
	local out = {}
	for _, kept in ipairs(profile.Data.Journal) do
		local entry = table.clone(kept)
		if typeof(entry.body) == "string" then
			entry.body = (entry.body:gsub("%%s", name))
		end
		table.insert(out, entry)
	end
	return { ready = true, entries = out }
end

-- ===== THE EMOTES =====
--
-- The client asks to play an emote it owns (or "stop"); the server checks it owns it and tells every
-- client, which poses that player's character (EmoteService). Not faster than EMOTE_GAP.
local EMOTE_GAP = 0.6
-- WHO HAS AN EMOTE PLAYING: a "stop" is passed on to everyone only for one of them, once, so a client sending stop
-- after stop cannot make the server shout at every other player (and a real stop, moving, is never held back).
local emoting: { [Player]: boolean } = {}

local function onEmote(player: Player, id: any)
	local remote = emoteRemote
	if not remote then
		return
	end
	local now = os.clock()
	if now - (lastEmote[player] or 0) < EMOTE_GAP and id ~= "stop" then
		return
	end
	if id == "stop" then
		if not emoting[player] then
			return
		end
		emoting[player] = nil
		remote:FireAllClients(player, "stop", workspace:GetServerTimeNow())
		return
	end
	local item = ShopCatalog.get(id)
	if not item or item.kind ~= "emote" or item.soon or not owns(player, item.id) then
		return
	end
	lastEmote[player] = now
	emoting[player] = true
	remote:FireAllClients(player, item.id, workspace:GetServerTimeNow())
end

-- ===== STUDIO ONLY: THE TEST PANEL (DevPanelClient) =====
--
-- What is awkward to reach by playing, for testing: tokens, a second chance, a clean slate, the first visit
-- again, the way to the shop. NEVER IN THE LIVE GAME: the handler is only connected in Studio (start), and
-- checks again here.
local DEV_TOKENS = 500

-- STUDIO ONLY (the test panel): every keepsake into the journal, as if each had been picked up, so the shelf in
-- the squish room can be seen full without playing every level for it. Interactables.take keeps each one and
-- tells the client, quietly.
local function giveAllKeepsakes(player: Player)
	local module = script.Parent:FindFirstChild("Interactables")
	if not (module and module:IsA("ModuleScript")) then
		return
	end
	local ok, story = pcall(require, module)
	if not (ok and type(story) == "table" and story.keepsakeList and story.take) then
		return
	end
	for _, item in ipairs(story.keepsakeList()) do
		pcall(story.take, player, { title = item.thing, body = item.line or "" }, nil, "keepsake",
			{ material = item.material, from = item.from }, true)
	end
end

-- ===== THE SELF-TEST (Studio only: the test panel's "Self-test") =====
--
-- The shop's own paths, run for real on this save in the engine, each step said PASS or FAIL: the cheapest thing
-- not owned bought (its price taken, worn at once), bought again (refused, nothing taken), taken off and put back
-- on; something too dear refused; a Robux item refused here; a run finished the moment it started paying nothing;
-- a journal entry kept with the reader's name left out. Nothing yields while it runs, and then the save is put
-- back exactly as it was (and any run this player was really in), so it can be pressed any time.
local function selfTest(player: Player)
	local profile = profiles[player]
	if not (profile and profile:IsActive()) then
		warn("SELF-TEST: no save is loaded yet; press it again in a moment.")
		return
	end
	local data = profile.Data
	local before = deepCopy(data)
	local realRun = runs[player]
	local realCrew = table.clone(crew)
	local realFound = foundRun[player]
	local realDevFriend = devFriend[player]
	local realNote = lastNote[player]
	local results: { { label: string, ok: boolean, detail: string? } } = {}
	local function check(label: string, ok: boolean, detail: string?)
		table.insert(results, { label = label, ok = ok, detail = detail })
	end
	local ran, err = pcall(function()
		local pick, dear, robux = nil, nil, nil
		for _, item in ipairs(ShopCatalog.all()) do
			if item.price and item.price > 0 and not item.soon and not owns(player, item.id) then
				if WEARABLE[item.kind] and (not pick or item.price < pick.price) then
					pick = item
				end
				if not dear or item.price > dear.price then
					dear = item
				end
			end
			if item.robux and not robux then
				robux = item
			end
		end
		if not pick then
			check("something to buy", false, "everything wearable is owned: press Clear purchases first")
			return
		end
		data.Tokens = pick.price * 2 + 10
		local tokens = data.Tokens
		local result = handle(player, "buy", pick.id)
		check("buy " .. pick.id, result.ok == true and data.Owned[pick.id] == true and data.Tokens == tokens - pick.price,
			("ok %s, tokens %d, expected %d"):format(tostring(result.ok), data.Tokens, tokens - pick.price))
		check("worn the moment it is bought", data.Equipped[pick.kind] == pick.id)
		result = handle(player, "buy", pick.id)
		check("a second buy refused, nothing taken", result.ok == false and data.Tokens == tokens - pick.price,
			("reason %s, tokens %d"):format(tostring(result.reason), data.Tokens))
		result = handle(player, "unequip", pick.kind)
		check("taken off", result.ok == true and data.Equipped[pick.kind] == nil)
		result = handle(player, "equip", pick.id)
		check("put back on", result.ok == true and data.Equipped[pick.kind] == pick.id)
		if dear and dear.id ~= pick.id then
			data.Tokens = 0
			result = handle(player, "buy", dear.id)
			check("too dear refused", result.ok == false and result.reason == "short" and not data.Owned[dear.id],
				("reason %s"):format(tostring(result.reason)))
		end
		if robux then
			result = handle(player, "buy", robux.id)
			check("a Robux item not sold for tokens", result.ok == false, ("reason %s"):format(tostring(result.reason)))
		end
		-- A BACKGROUND CRATE (the hundred-and-sixth pass): its price taken and a background you lacked given; refused
		-- when short; never bought as a thing.
		local crate = ShopCatalog.get(ShopCatalog.CRATE.id)
		if crate and crate.price and randomOk[player] and not ShopCatalog.crateDone(function(other: string): boolean
			return owns(player, other)
		end) then
			data.Tokens = crate.price
			result = handle(player, "crate", crate.id)
			local won = if result.won then ShopCatalog.get(result.won) else nil
			check("a crate gives a background you lacked", result.ok == true and won ~= nil and won.kind == "background"
				and before.Owned[won.id] ~= true and data.Owned[won.id] == true and data.Tokens == 0,
				("ok %s, won %s, tokens %d"):format(tostring(result.ok), tostring(result.won), data.Tokens))
			result = handle(player, "crate", crate.id)
			check("a crate refused when short", result.ok == false and result.reason == "short",
				("reason %s"):format(tostring(result.reason)))
			result = handle(player, "buy", crate.id)
			check("a crate is never bought as a thing", result.ok == false and not data.Owned[crate.id],
				("reason %s"):format(tostring(result.reason)))
		end
		data.Tokens = 100
		local wasFinished = finishedOf(data)["1"]
		EconomyService.runStarted({ player }, "short")
		EconomyService.runFinished(player, false, false, 1)
		check("a run finished at once pays nothing (the warning above is this)", data.Tokens == 100,
			("tokens %d"):format(data.Tokens))
		check("a run finished at once opens no level", finishedOf(data)["1"] == wasFinished)
		-- TODAY'S CHALLENGES (challengesToday, challengeRun): three, none on a level not yet open; one done pays once
		-- that day, and the third run of the day counts as three.
		local wasFinishedAll = table.clone(finishedOf(data))
		table.clear(finishedOf(data))
		data.Challenges = {}
		local picked = challengesToday(data)
		local locked = {}
		for _, id in ipairs(picked.ids) do
			local challenge = ShopCatalog.challenge(id)
			if challenge and challenge.level and challenge.level ~= LevelDefinitions.All[1].levelId then
				table.insert(locked, id)
			end
		end
		check("three challenges a day, none on a level not yet open", #picked.ids == ShopCatalog.CHALLENGES_A_DAY
			and #locked == 0, table.concat(picked.ids, ","))
		for key, value in pairs(wasFinishedAll) do
			finishedOf(data)[key] = value
		end
		data.Challenges = { day = today(), ids = { "long", "three" }, done = {}, runs = 0 }
		local beforeChallenge = data.Tokens
		local paidLong = EconomyService.challengeRun(player, { length = "long" })
		local paidAgain = EconomyService.challengeRun(player, { length = "long" })
		local paidThird = EconomyService.challengeRun(player, { length = "short" })
		local long, three = ShopCatalog.challenge("long"), ShopCatalog.challenge("three")
		check("a challenge pays once a day, and the third run counts", paidLong == long.reward and paidAgain == 0
			and paidThird == three.reward and data.Tokens == beforeChallenge + long.reward + three.reward,
			("%d %d %d"):format(paidLong, paidAgain, paidThird))
		-- THE STARTER PACK (grantStarter): its tokens and its trail once a save, the pass Owned in the shop; the trail
		-- never sold on its own.
		local starterPasses = passes[player] or {}
		passes[player] = starterPasses
		local realStarter = starterPasses.StarterPack
		starterPasses.StarterPack = true
		data.StarterGranted = false
		data.Owned.SeaGlass = nil
		local beforeStarter = data.Tokens
		grantStarter(player)
		grantStarter(player)
		local pack = ShopCatalog.get("StarterPack")
		check("the starter pack gives its tokens and its trail once", pack ~= nil
			and data.Tokens == beforeStarter + (pack.tokens or 0) and data.Owned.SeaGlass == true and data.StarterGranted == true,
			("tokens %d"):format(data.Tokens - beforeStarter))
		check("a pass you own shows as owned", owns(player, "StarterPack"))
		starterPasses.StarterPack = realStarter
		data.Owned.SeaGlass = nil
		-- A CODE (handle "code"): a real one pays once, as typed in any case and with spaces; a used one, an unknown one
		-- and an ended one say so. Two codes of the self-test's own, taken out again at once.
		table.insert(ShopCatalog.CODES, { code = "SELFTESTCODE", tokens = 7, ends = "2999-12-31" })
		table.insert(ShopCatalog.CODES, { code = "SELFTESTOLD", tokens = 7, ends = "2000-01-01" })
		data.Codes = {}
		local beforeCode = data.Tokens
		local codeFirst = handle(player, "code", " selftest code ")
		local codeAgain = handle(player, "code", "SELFTESTCODE")
		local codeUnknown = handle(player, "code", "NOSUCHCODE")
		local codeOld = handle(player, "code", "selftestold")
		for index = #ShopCatalog.CODES, 1, -1 do
			if string.sub(ShopCatalog.CODES[index].code, 1, 8) == "SELFTEST" then
				table.remove(ShopCatalog.CODES, index)
			end
		end
		check("a code pays once, and an unknown or ended one says so", codeFirst.ok == true and codeAgain.reason == "used"
			and codeUnknown.reason == "unknown" and codeOld.reason == "ended" and data.Tokens == beforeCode + 7,
			("%s %s %s"):format(tostring(codeAgain.reason), tostring(codeUnknown.reason), tostring(codeOld.reason)))
		-- THE MATERIALS (foundMaterial): one found pays once, and only a real one; the last of them gives the swatch
		-- trail and the bonus.
		data.Materials = {}
		data.Owned.Swatch = nil
		local beforeMaterial = data.Tokens
		local firstFind = EconomyService.foundMaterial(player, "Honey")
		local againFind = EconomyService.foundMaterial(player, "Honey")
		local madeUp = EconomyService.foundMaterial(player, "Marble")
		check("a material found pays once, and only a real one", firstFind == true and againFind == false
			and madeUp == false and data.Tokens == beforeMaterial + ShopCatalog.REWARD.MATERIAL,
			("tokens %d"):format(data.Tokens - beforeMaterial))
		for _, material in ipairs(ShopCatalog.MATERIALS) do
			if material.key ~= "Soap" then
				data.Materials[material.key] = true
			end
		end
		local beforeLast = data.Tokens
		EconomyService.foundMaterial(player, "Soap")
		check("the last material gives the swatch trail and the bonus", data.Owned.Swatch == true
			and data.Tokens == beforeLast + ShopCatalog.REWARD.MATERIAL + ShopCatalog.REWARD.MATERIALS_ALL,
			("tokens %d"):format(data.Tokens - beforeLast))
		local glass = handle(player, "buy", "SeaGlass")
		check("the sea glass trail is never sold", glass.ok == false and glass.reason == "earned",
			("reason %s"):format(tostring(glass.reason)))
		-- A FRIEND IN THE RUN (withFriend): alone in one, none; the test panel's pretend friend counts; a fifth more.
		devFriend[player] = nil
		check("alone in a run, no friend's bonus", EconomyService.withFriend(player) == false)
		devFriend[player] = true
		check("the test panel's friend counts as one", EconomyService.withFriend(player) == true)
		devFriend[player] = realDevFriend
		local plain = ShopCatalog.reward("medium", false, false, false)
		local together = ShopCatalog.reward("medium", false, false, false, true)
		check("a friend in the run pays a fifth more", together == math.floor(plain * ShopCatalog.REWARD.FRIEND + 0.5)
			and together > plain, ("%d, %d"):format(plain, together))
		EconomyService.keepEntry(player, { id = "note:SELF-TEST", kind = "note", title = "SELF-TEST", body = "for %s" })
		local kept = nil
		for _, entry in ipairs(data.Journal) do
			if entry.id == "note:SELF-TEST" then
				kept = entry
			end
		end
		check("a journal entry kept, the name left out", kept ~= nil and kept.body == "for %s")
		-- THE SECOND CHANCE: one owned is spent once, and only once.
		data.SecondChances = 1
		local first = EconomyService.spendChance(player)
		local second = EconomyService.spendChance(player)
		check("a second chance spent once, and only once", first == true and second == false and data.SecondChances == 0)
		-- THE NOTES: a client sets only the flags it may, and nothing else.
		local tokensNow = data.Tokens
		onNote(player, "Tokens", 999)
		onNote(player, "welcomedAgain")
		check("a note the server does not know changes nothing", data.Tokens == tokensNow)
		data.AskedFavourite = false
		onNote(player, "favourite")
		check("a note it knows sets its flag", data.AskedFavourite == true)
		-- WHAT THE SHOP IS TOLD is what the save says.
		local told = stateFor(player)
		check("the shop is told the save's tokens", type(told) == "table" and told.tokens == data.Tokens)
		-- LEVELS OPEN IN ORDER, through the lobby itself (Bootstrap wires HubService.isOpen here): City Shore open; City
		-- Shore finished in this save opens Sky Pools; taken back, Sky Pools is as the others here leave it.
		local isOpen = openReader
		local opener, opened = LevelDefinitions.All[1], LevelDefinitions.All[2]
		if isOpen and opener and opened then
			local finished = finishedOf(data)
			local key = tostring(opener.levelId)
			local had = finished[key]
			check("City Shore is open", isOpen(opener.levelId) == true)
			finished[key] = true
			tellLevels()
			check("City Shore finished opens Sky Pools", isOpen(opened.levelId) == true)
			finished[key] = nil
			tellLevels()
			-- Still open if anyone here (you included) has finished any level at all: getting further keeps it open.
			local others = false
			for _, other in ipairs(Players:GetPlayers()) do
				local theirs = EconomyService.finishedLevels(other)
				for _, level in ipairs(LevelDefinitions.All) do
					if theirs and theirs[tostring(level.levelId)] == true then
						others = true
					end
				end
			end
			check("not finished, Sky Pools is locked (unless anyone here has finished a level)",
				isOpen(opened.levelId) == others)
			finished[key] = had
		else
			check("the lobby reads the saves", false, "no lobby wired to the save: paste the current server Bootstrap")
		end
		-- A HIDDEN CACHE (foundCache): its tokens the first time, nothing the second.
		data.Caches = {}
		local beforeCache = data.Tokens
		local cacheFirst = EconomyService.foundCache(player, 1)
		local cacheAgain = EconomyService.foundCache(player, 1)
		check("a hidden cache pays once a save", cacheFirst == true and cacheAgain == false
			and data.Tokens == beforeCache + ShopCatalog.REWARD.CACHE, ("tokens %d"):format(data.Tokens - beforeCache))
		-- THE DAILY CHEST (claimDaily): once a day; the next day its streak goes on; after a day missed it starts again.
		data.DailyDay, data.DailyStreak = 0, 0
		local dailyFirst = EconomyService.claimDaily(player)
		local dailyAgain = EconomyService.claimDaily(player)
		data.DailyDay -= 1
		local dailyNext = EconomyService.claimDaily(player)
		data.DailyDay -= 2
		local dailyMissed = EconomyService.claimDaily(player)
		check("the daily chest: once a day, its streak the next day, and again from day one after a day missed",
			dailyFirst.opened == true and dailyFirst.streak == 1 and dailyAgain.opened == false and dailyNext.opened == true
				and dailyNext.streak == 2 and dailyMissed.opened == true and dailyMissed.streak == 1,
			("%s %s %s %s"):format(tostring(dailyFirst.streak), tostring(dailyAgain.opened), tostring(dailyNext.streak),
				tostring(dailyMissed.streak)))
		-- THE STORY'S REWARD (finishStory): its bonus paid and the green ribbon owned; never for sale.
		local beforeReward = data.Tokens
		EconomyService.finishStory(player, false)
		local ribbonOwned = false
		for _, item in ipairs(ShopCatalog.all()) do
			if item.earn == "story" then
				ribbonOwned = data.Owned[item.id] == true
			end
		end
		check("finishing the story pays its bonus and gives the green ribbon",
			data.Tokens == beforeReward + ShopCatalog.storyReward(false, passes[player] ~= nil and passes[player].DoubleTokens == true)
				and ribbonOwned, ("tokens %d, ribbon %s"):format(data.Tokens - beforeReward, tostring(ribbonOwned)))
		data.Owned.GreenRibbon = nil
		result = handle(player, "buy", "GreenRibbon")
		check("the green ribbon is never sold", result.ok == false and result.reason == "earned",
			("reason %s"):format(tostring(result.reason)))
		-- THE STORY'S PLACE, kept in the save and read back (Bootstrap goes on from it), and never out of range.
		EconomyService.setStoryAt(player, 3)
		local storyKept = EconomyService.storyAt(player)
		EconomyService.setStoryAt(player, 99)
		local storyCapped = EconomyService.storyAt(player)
		check("the story's place kept, and kept in range", storyKept == 3 and storyCapped == #LevelDefinitions.All,
			("%s, then %s"):format(tostring(storyKept), tostring(storyCapped)))
	end)
	if not ran then
		check("the self-test ran to the end", false, tostring(err))
	end
	-- THE SAVE PUT BACK, in the same table (ProfileStore holds this one), and any real run with it.
	for key in pairs(data) do
		data[key] = nil
	end
	for key, value in pairs(before) do
		data[key] = value
	end
	runs[player] = realRun
	table.clear(crew)
	for member, on in pairs(realCrew) do
		crew[member] = on
	end
	devFriend[player] = realDevFriend
	foundRun[player] = realFound
	lastNote[player] = realNote
	showCollection(player)
	push(player)
	dress(player)
	stepGear(player)
	tellLevels()
	dailyAttributes(player)
	challengeAttributes(player)
	materialsAttribute(player)
	-- THE STORES, which wait on Roblox, so after the save is put back: the leaderboard read, then read again at once
	-- from what LeaderboardService kept (no second wait); and a personal best read. With the data stores off in
	-- Studio the board answers empty, which is still an answer.
	local function serviceNamed(name: string): any
		local module = script.Parent:FindFirstChild(name)
		if not (module and module:IsA("ModuleScript")) then
			return nil
		end
		local ok, loaded = pcall(require, module)
		return if ok and type(loaded) == "table" then loaded else nil
	end
	local board = serviceNamed("LeaderboardService")
	if board and board.getTop then
		local readOk, rows = pcall(board.getTop, 1, "hardcore", 10)
		check("the leaderboard answers", readOk and type(rows) == "table", if readOk then nil else tostring(rows))
		local started = os.clock()
		local againOk = pcall(board.getTop, 1, "hardcore", 10)
		local took = os.clock() - started
		check("read again at once, from what was kept", againOk and took < 0.05, ("%.2f s"):format(took))
	end
	local bests = serviceNamed("BestTimeService")
	if bests and bests.get then
		local bestOk, bestErr = pcall(bests.get, player, 1, "hardcore")
		check("a personal best read", bestOk, if bestOk then nil else tostring(bestErr))
	end
	-- WHAT WAS BUILT AT THE START, as it stands: the keepsake shelf in the squish room (a toy and a card for every
	-- keepsake, and the board on top), and this player's statue in the lobby, marked as theirs.
	local CollectionService = game:GetService("CollectionService")
	local story = serviceNamed("Interactables")
	local keepsakes = if story and story.keepsakeList then #story.keepsakeList() else 0
	local toys = #CollectionService:GetTagged("ShelfToy")
	local cards = #CollectionService:GetTagged("ShelfEmpty")
	check("the keepsake shelf built, a toy and a card for each", keepsakes > 0 and toys == keepsakes and cards == keepsakes
		and #CollectionService:GetTagged("ShelfCount") == 1, ("%d keepsakes, %d toys, %d cards"):format(keepsakes, toys, cards))
	-- THE BACK ROOMS (BackRoomsService), built at the start, with their one way out.
	local wayOut = #CollectionService:GetTagged("BackRoomsExit")
	check("the back rooms built, with one way out", wayOut == 1, ("%d ways out"):format(wayOut))
	local statue = false
	for _, stand in ipairs(CollectionService:GetTagged("LobbyStatue")) do
		if stand:GetAttribute("Owner") == player.UserId then
			statue = true
		end
	end
	check("your statue in the lobby, marked as yours", statue)
	-- WHAT OTHERS AND YOUR SCREEN ARE SHOWN matches the save, now it is put back: the Keepsakes count in the player
	-- list (the journal's keepsakes), and the tokens your screen reads (the Tokens attribute).
	local saved = 0
	for _, kept in ipairs(data.Journal or {}) do
		if kept.kind == "keepsake" then
			saved += 1
		end
	end
	local stats = player:FindFirstChild("leaderstats")
	local shown = stats and stats:FindFirstChild("Keepsakes")
	check("the player list shows your keepsakes", shown ~= nil and shown:IsA("IntValue") and shown.Value == saved,
		("%s shown, %d saved"):format(if shown and shown:IsA("IntValue") then tostring(shown.Value) else "none", saved))
	check("your screen is told your tokens", player:GetAttribute("Tokens") == data.Tokens,
		("%s told, %d saved"):format(tostring(player:GetAttribute("Tokens")), data.Tokens))
	local failed, lines = 0, {}
	for _, step in ipairs(results) do
		if not step.ok then
			failed += 1
		end
		table.insert(lines, ("  %s  %s%s"):format(if step.ok then "pass" else "FAIL", step.label,
			if step.ok or not step.detail then "" else " (" .. step.detail .. ")"))
	end
	local summary = ("SELF-TEST: %d of %d passed, and the save is as it was.\n%s"):format(#results - failed, #results,
		table.concat(lines, "\n"))
	if failed == 0 then
		print(summary)
	else
		warn(summary)
	end
end

local function onDev(player: Player, action: any)
	if not RunService:IsStudio() then
		return
	end
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return
	end
	local data = profile.Data
	if action == "tokens" then
		data.Tokens += DEV_TOKENS
	elseif action == "chance" then
		data.SecondChances = (data.SecondChances or 0) + 1
	elseif action == "clear" then
		data.Owned = {}
		data.Equipped = {}
		data.SecondChances = 0
		dress(player)
		stepGear(player)
	elseif action == "firstVisit" then
		data.Welcomed = false
		data.Guided = false
		data.Hinted = {}
		data.ShopIntro = false
		data.AskedFavourite = false
		data.Earned = 0
	elseif action == "shopIntro" then
		data.Earned = math.max(data.Earned, 1)
		data.ShopIntro = false
	elseif action == "keepsakes" then
		task.spawn(giveAllKeepsakes, player)
	elseif action == "selftest" then
		task.spawn(selfTest, player)
		return
	elseif action == "journal" then
		-- The saved journal emptied (and what you have said to everyone, so the conversations start over); the
		-- journal on screen keeps what it has until you rejoin.
		data.Heard = {}
		data.Journal = {}
		showCollection(player)
	elseif action == "levels" then
		-- Every level finished, or none again: to see the lobby's pads open and boarded up.
		local finished = finishedOf(data)
		local every = true
		for _, level in ipairs(LevelDefinitions.All) do
			if finished[tostring(level.levelId)] ~= true then
				every = false
			end
		end
		table.clear(finished)
		if not every then
			for _, level in ipairs(LevelDefinitions.All) do
				finished[tostring(level.levelId)] = true
			end
		end
		tellLevels()
	elseif action == "dailyNext" then
		-- As if the chest was last opened yesterday: open it now and the streak goes on a day.
		data.DailyDay = today() - 1
		dailyAttributes(player)
	elseif action == "storyStart" then
		-- The story from City Shore again next time (its place in the save put back to the start).
		data.StoryAt = 1
	elseif action == "vip" then
		-- VIP on and off, to see the tag (a pass cannot be owned in Studio).
		local owned = passes[player] or {}
		passes[player] = owned
		owned.VIP = not owned.VIP
		player:SetAttribute("VIP", owned.VIP == true)
		dress(player)
	elseif action == "codesForget" then
		-- Every code as if never posted, to post them again.
		data.Codes = {}
	elseif action == "materials" then
		-- Every material found but one (Soap, on City Shore), to finish the collection on the next run; pressed again,
		-- none found and the swatch trail taken back.
		local any = false
		for _ in pairs(data.Materials) do
			any = true
		end
		data.Materials = {}
		if any then
			data.Owned.Swatch = nil
			if data.Equipped.trail == "Swatch" then
				data.Equipped.trail = nil
			end
			dress(player)
		else
			for _, material in ipairs(ShopCatalog.MATERIALS) do
				if material.key ~= "Soap" then
					data.Materials[material.key] = true
				end
			end
		end
		materialsAttribute(player)
	elseif action == "starter" then
		-- The starter pack as if bought (a pass cannot be owned in Studio): its tokens and trail given once; pressed again,
		-- the pass, the trail and the once-a-save mark taken back, to try it again.
		local owned = passes[player] or {}
		passes[player] = owned
		local starter = ShopCatalog.get("StarterPack")
		if owned.StarterPack then
			owned.StarterPack = nil
			data.StarterGranted = false
			if starter and starter.gives then
				data.Owned[starter.gives] = nil
				if data.Equipped.trail == starter.gives then
					data.Equipped.trail = nil
				end
			end
			dress(player)
		else
			owned.StarterPack = true
			grantStarter(player)
		end
	elseif action == "challengesNew" then
		-- A fresh three with nothing done (picked as if on another day), to see the board and the card change.
		data.Challenges = {
			day = today(),
			ids = ShopCatalog.pickChallenges(today() + math.random(1, 9999), function(challenge)
				return canChallenge(data, challenge)
			end),
			done = {},
			runs = 0,
		}
		challengeAttributes(player)
	elseif action == "friend" then
		-- A pretend friend in your runs, on and off (the players in a Studio test are nobody's friends): the card at the
		-- next run's start, and "With a friend" on its tokens.
		devFriend[player] = if devFriend[player] then nil else true
		toldFriend[player] = nil
		print(("EconomyService: a friend in %s's runs is %s (Studio)."):format(player.Name,
			if devFriend[player] then "on" else "off"))
	elseif action == "favourite" then
		-- Asked, then not: OnboardingService sees the flip and asks again.
		data.Earned = math.max(data.Earned, 1)
		data.ShopIntro = true
		data.AskedFavourite = true
		push(player)
		data.AskedFavourite = false
	else
		return
	end
	push(player)
end

-- ===== THE SECOND CHANCE =====

-- One used, if there is one: true when it was there to spend.
function EconomyService.spendChance(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() or (profile.Data.SecondChances or 0) < 1 then
		return false
	end
	profile.Data.SecondChances -= 1
	push(player)
	return true
end

-- ===== ROBUX =====

-- GRANTED ONCE, SAVED BEFORE ROBLOX IS TOLD. The pattern from ProfileStore's own documentation.
local function receipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	local profile = player and profiles[player]
	if not (player and profile and profile:IsActive()) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	-- NOT SAVING, NOT SELLING: outside Studio a purchase on an unsaved profile would be lost on leaving.
	if not saving and not RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local item = ShopCatalog.byProduct(info.ProductId)
	if not item then
		warn("EconomyService: a purchase of product " .. tostring(info.ProductId) .. " that ShopCatalog does not know")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local purchaseId = tostring(info.PurchaseId)
	local cache = profile.Data.PurchaseIdCache
	if not table.find(cache, purchaseId) then
		if item.kind == "tokens" and item.tokens then
			profile.Data.Tokens += item.tokens
			logEconomy(player, true, item.tokens, Enum.AnalyticsEconomyTransactionType.IAP.Name, item.id)
		elseif item.id == "SecondChance" then
			-- KEPT until used: one hardcore fall undone (Bootstrap spends it through spendChance).
			profile.Data.SecondChances += 1
		else
			return Enum.ProductPurchaseDecision.NotProcessedYet -- nothing else is sold as a product yet
		end
		while #cache >= PURCHASE_ID_CACHE do
			table.remove(cache, 1)
		end
		table.insert(cache, purchaseId)
		push(player)
	end
	local function saved(): boolean
		local last = profile.LastSavedData
		local savedCache = last and last.PurchaseIdCache
		return savedCache ~= nil and table.find(savedCache, purchaseId) ~= nil
	end
	if saved() then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	while profile:IsActive() and profile.OnAfterSave do
		profile:Save()
		profile.OnAfterSave:Wait()
		if saved() then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

-- ===== RUNS =====

-- WHETHER TWO PLAYERS ARE ROBLOX FRIENDS, asked once a pair (both ways at once). A failed ask is not kept, and counts
-- as no.
local function remember(player: Player, userId: number, yes: boolean)
	local known = friendOf[player]
	if not known then
		known = {}
		friendOf[player] = known
	end
	known[userId] = yes
end

local function isFriend(player: Player, other: Player): boolean
	local known = friendOf[player]
	if known and known[other.UserId] ~= nil then
		return known[other.UserId]
	end
	local ok, yes = pcall(player.IsFriendsWith, player, other.UserId)
	if not ok then
		return false
	end
	remember(player, other.UserId, yes == true)
	if other.Parent ~= nil then
		remember(other, player.UserId, yes == true)
	end
	return yes == true
end

-- A FRIEND IN THIS PLAYER'S RUN: someone else who has been in the run and is still in the server, and a Roblox friend
-- of theirs (or, in Studio, the test panel's pretend friend). Can take a moment the first time (it asks Roblox).
function EconomyService.withFriend(player: Player): boolean
	if devFriend[player] and RunService:IsStudio() then
		return true
	end
	local others = {}
	for other in pairs(crew) do
		if other ~= player then
			table.insert(others, other)
		end
	end
	for _, other in ipairs(others) do
		if other.Parent == Players and player.Parent == Players and isFriend(player, other) then
			return true
		end
	end
	return false
end

-- WHAT A FRIEND ADDS, as a whole percent (20 for a FRIEND of 1.2), for the words on the card.
function EconomyService.friendPercent(): number
	return math.floor(((tonumber(ShopCatalog.REWARD.FRIEND) or 1) - 1) * 100 + 0.5)
end

-- WHO IS NEWLY RUNNING WITH A FRIEND (Bootstrap tells them on their card): each player once while they are here.
function EconomyService.newlyWithFriends(): { Player }
	local members = {}
	for player in pairs(crew) do
		table.insert(members, player)
	end
	local news = {}
	for _, player in ipairs(members) do
		if not toldFriend[player] and crew[player] and EconomyService.withFriend(player) then
			toldFriend[player] = true
			table.insert(news, player)
		end
	end
	return news
end

-- A RUN BEGINS: the server notes who is in it and how long it is, so a finish can be checked. A new run starts its
-- crew again; a late joiner (joining) is added to the run already on.
function EconomyService.runStarted(players: { Player }, length: string, joining: boolean?)
	if not joining then
		table.clear(crew)
	end
	for _, player in ipairs(players) do
		runs[player] = { startedAt = os.clock(), length = length }
		crew[player] = true
		foundRun[player] = nil
		local profile = profiles[player]
		if profile and profile.Data.Earned == 0 then
			funnel(player, 4, "First run started")
		end
	end
end

-- A RUN ENDS, as the server saw it (Bootstrap's completeRun). Pays once, and only for a run this
-- server watched start, that took at least MIN_SECONDS. The level it was (levelId) is kept as finished.
function EconomyService.runFinished(player: Player, hardcore: boolean, best: boolean, levelId: number?)
	local run = runs[player]
	runs[player] = nil
	local profile = profiles[player]
	if not (run and profile and profile:IsActive()) then
		return
	end
	local least = ShopCatalog.REWARD.MIN_SECONDS[run.length] or ShopCatalog.REWARD.MIN_SECONDS.medium
	if os.clock() - run.startedAt < least then
		warn(("EconomyService: %s finished a %s run in %.0f s, faster than it can be played; no tokens.")
			:format(player.Name, run.length, os.clock() - run.startedAt))
		return
	end
	-- THE LEVEL'S BADGE (ShopCatalog.BADGES), for a run really played.
	local badges = ShopCatalog.BADGES
	if levelId ~= nil and type(badges) == "table" and type(badges.level) == "table" then
		EconomyService.awardBadge(player, badges.level[levelId])
	end
	-- THE LEVEL IS FINISHED, kept in the save: the next one opens in the lobby (HubService.isOpen), for everyone
	-- in the server while this player is in it.
	local finished = finishedOf(profile.Data)
	if levelId ~= nil and finished[tostring(levelId)] ~= true then
		finished[tostring(levelId)] = true
		tellLevels()
		-- THE DASHBOARD: each level's first finish in a save (FirstFinish_<level id>), the climb through the levels.
		pcall(function()
			AnalyticsService:LogCustomEvent(player, ("FirstFinish_%d"):format(levelId))
		end)
	end
	-- A FRIEND IN THE RUN (withFriend): a fifth more. Asked before the tokens are added, and the save looked at again
	-- after, as asking Roblox can take a moment.
	local friend = EconomyService.withFriend(player)
	if not profile:IsActive() then
		return
	end
	local double = passes[player] ~= nil and passes[player].DoubleTokens == true
	local amount = ShopCatalog.reward(run.length, hardcore, best, double, friend)
	if profile.Data.Earned == 0 then
		funnel(player, 6, "First run finished")
	end
	profile.Data.Tokens += amount
	profile.Data.Earned += amount
	logEconomy(player, true, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Run_" .. run.length)
	-- THE DASHBOARD: runs finished with a friend (RunWithFriend, the level), to see whether bringing one catches on.
	if friend then
		pcall(function()
			AnalyticsService:LogCustomEvent(player, "RunWithFriend", levelId or 0)
		end)
	end
	-- TODAY'S CHALLENGES this run did (challengeRun): paid with it, on the same pill.
	local prize, done = EconomyService.challengeRun(player, { levelId = levelId, hardcore = hardcore, best = best,
		friend = friend, length = run.length })
	-- THE MATERIALS FOUND ON THIS RUN (foundMaterial, paid as each was found): told on the same pill.
	local found = foundRun[player]
	foundRun[player] = nil
	local foundTokens = if found then found.tokens else 0
	local foundCount = if found then found.count else 0
	local foundGift = if found then found.gift else nil
	push(player)
	if earnedRemote then
		earnedRemote:FireClient(player, amount + prize + foundTokens, { length = run.length, hardcore = hardcore, best = best,
			double = double, friend = friend, challenges = #done, materials = foundCount, gift = foundGift })
	end
end

-- WHAT THIS PLAYER HAS FINISHED (level id as text), read by the lobby to open levels in order. Nil until their
-- save is loaded.
function EconomyService.finishedLevels(player: Player): { [string]: boolean }?
	local profile = profiles[player]
	if not (profile and profile:IsActive()) then
		return nil
	end
	-- AN ADMIN WITH EVERY LEVEL OPEN (/levels) counts as having finished them all; the save itself is left as it is.
	if profile.Data.AdminOpen == true and EconomyService.isAdmin(player) then
		local all: { [string]: boolean } = {}
		for _, level in ipairs(LevelDefinitions.All) do
			all[tostring(level.levelId)] = true
		end
		return all
	end
	return finishedOf(profile.Data)
end

-- THE STORY'S PLACE IN THIS SAVE (Bootstrap): the level to go on from, 1 being City Shore, the start.
function EconomyService.storyAt(player: Player): number
	local profile = profiles[player]
	local at = if profile and profile:IsActive() then tonumber(profile.Data.StoryAt) else nil
	return math.clamp(math.floor(at or 1), 1, #LevelDefinitions.All)
end

function EconomyService.setStoryAt(player: Player, index: number)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile.Data.StoryAt = math.clamp(math.floor(index), 1, #LevelDefinitions.All)
	end
end

-- THE BACK ROOMS, ONCE FOUND (by falling into them): kept in the save, so the lobby's back corridor leads there.
-- WHAT YOU HAVE SAID AND LEARNED (Townsfolk): a copy, so nothing outside can change the save by it.
function EconomyService.heard(player: Player): { [string]: boolean }
	local profile = profiles[player]
	local out = {}
	if profile and profile:IsActive() and type(profile.Data.Heard) == "table" then
		for key, value in pairs(profile.Data.Heard) do
			if value == true then
				out[key] = true
			end
		end
	end
	return out
end

-- One topic said or one clue learned, kept. Ids are short words of the game's own (Conversations), never a player's.
function EconomyService.markHeard(player: Player, key: string)
	local profile = profiles[player]
	if not (profile and profile:IsActive()) or typeof(key) ~= "string" or #key > 40 then
		return
	end
	if type(profile.Data.Heard) ~= "table" then
		profile.Data.Heard = {}
	end
	profile.Data.Heard[key] = true
end

function EconomyService.foundBackRooms(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile:IsActive() and profile.Data.FoundBackRooms == true
end

function EconomyService.markFoundBackRooms(player: Player)
	local profile = profiles[player]
	if profile and profile:IsActive() then
		profile.Data.FoundBackRooms = true
	end
end

function EconomyService.setLevelsChanged(fn)
	levelsChanged = fn
end

function EconomyService.setOpenReader(fn)
	openReader = fn
end

-- A HIDDEN CACHE FOUND (Interactables.cache, one a level): its tokens, once a save. True when it paid.
function EconomyService.foundCache(player: Player, levelId: number): boolean
	local profile = profiles[player]
	if not (profile and profile:IsActive()) then
		return false
	end
	local data = profile.Data
	if type(data.Caches) ~= "table" then
		data.Caches = {}
	end
	local key = tostring(levelId)
	if data.Caches[key] then
		return false
	end
	data.Caches[key] = true
	local amount = ShopCatalog.REWARD.CACHE
	data.Tokens += amount
	data.Earned += amount
	logEconomy(player, true, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Cache")
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "CacheFound", levelId)
	end)
	push(player)
	if earnedRemote then
		earnedRemote:FireClient(player, amount, { cache = true })
	end
	return true
end

-- A MATERIAL FOUND ON A LEVEL (lookUnder, the server seeing a runner stand on it): its tokens, once a save; and with the
-- last of them all, the swatch trail, the bonus and the badge. True when it counted. Told on the run's pill
-- (foundRun) and by the player's Materials attribute (the journal's pages, the lobby's board, a chime).
function EconomyService.foundMaterial(player: Player, name: string): boolean
	local profile = profiles[player]
	if not (profile and profile:IsActive()) or ShopCatalog.material(name) == nil then
		return false
	end
	local data = profile.Data
	if type(data.Materials) ~= "table" then
		data.Materials = {}
	end
	if data.Materials[name] then
		return false
	end
	data.Materials[name] = true
	local count = 0
	for _, material in ipairs(ShopCatalog.MATERIALS) do
		if data.Materials[material.key] then
			count += 1
		end
	end
	local amount = ShopCatalog.REWARD.MATERIAL
	local gift: string? = nil
	if count == #ShopCatalog.MATERIALS then
		amount += ShopCatalog.REWARD.MATERIALS_ALL
		for _, item in ipairs(ShopCatalog.all()) do
			if item.earn == "materials" and not data.Owned[item.id] then
				data.Owned[item.id] = true
				gift = item.name
			end
		end
		task.spawn(EconomyService.awardBadge, player, ShopCatalog.BADGES.materials)
		pcall(function()
			AnalyticsService:LogCustomEvent(player, "AllMaterials")
		end)
	end
	data.Tokens += amount
	data.Earned += amount
	logEconomy(player, true, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Material")
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "MaterialFound", count)
	end)
	local run = foundRun[player] or { count = 0, tokens = 0, gift = nil }
	run.count += 1
	run.tokens += amount
	run.gift = gift or run.gift
	foundRun[player] = run
	materialsAttribute(player)
	push(player)
	return true
end

-- WHAT IS UNDER A RUNNER'S FEET, as the server sees it: a level's platform carries its Material (on the slab, or a
-- model a few parents up). Only on a level (InLevel set, and not the back rooms), never in the squish room, where every
-- material stands side by side; and nothing a client says counts.
local underParams = RaycastParams.new()
underParams.FilterType = Enum.RaycastFilterType.Exclude
local function lookUnder(player: Player)
	local level = player:GetAttribute("InLevel")
	if typeof(level) ~= "string" or level == "backRooms" or player:GetAttribute("InSquishRoom") then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	underParams.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -8, 0), underParams)
	local part: Instance? = hit and hit.Instance
	for _ = 1, 4 do
		if not part then
			return
		end
		local name = part:GetAttribute("Material")
		if typeof(name) == "string" then
			local profile = profiles[player]
			local found = profile and profile.Data.Materials
			if type(found) == "table" and not found[name] then
				EconomyService.foundMaterial(player, name)
			end
			return
		end
		part = part.Parent
	end
end

-- A FINISHED RUN AGAINST TODAY'S CHALLENGES (runFinished, and the self-test): counted among today's runs, and each
-- challenge it does paid once that day. Returns what it paid, and the ids of the challenges it did.
function EconomyService.challengeRun(player: Player, run: { [string]: any }): (number, { string })
	local profile = profiles[player]
	if not (profile and profile:IsActive()) then
		return 0, {}
	end
	local data = profile.Data
	local state = challengesToday(data)
	state.runs = (tonumber(state.runs) or 0) + 1
	local prize = 0
	local done = {}
	for _, id in ipairs(state.ids) do
		local challenge = ShopCatalog.challenge(id)
		if challenge and not state.done[id] and ShopCatalog.challengeMet(challenge, run, state.runs) then
			state.done[id] = true
			prize += challenge.reward
			table.insert(done, id)
			pcall(function()
				AnalyticsService:LogCustomEvent(player, "ChallengeDone", challenge.reward,
					{ [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = id })
			end)
		end
	end
	if prize > 0 then
		data.Tokens += prize
		data.Earned += prize
		logEconomy(player, true, prize, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Challenge")
	end
	challengeAttributes(player)
	return prize, done
end

-- THE DAILY CHEST OPENED (HubService's, through Bootstrap): its tokens if it is a new day, with the streak; or how long
-- until the next one. Told to the player by the caller (the vote card) and by the "+N tokens" pill.
function EconomyService.claimDaily(player: Player): { [string]: any }
	local profile = profiles[player]
	if not (profile and profile:IsActive()) then
		return { opened = false, loading = true }
	end
	local data = profile.Data
	local now = today()
	local nextIn = DAY - (os.time() % DAY)
	local last = tonumber(data.DailyDay) or 0
	if last == now then
		return { opened = false, streak = tonumber(data.DailyStreak) or 0, nextIn = nextIn }
	end
	local streak = if last == now - 1 then (tonumber(data.DailyStreak) or 0) + 1 else 1
	local amount = ShopCatalog.dailyReward(streak)
	data.DailyDay = now
	data.DailyStreak = streak
	data.Tokens += amount
	data.Earned += amount
	logEconomy(player, true, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Daily")
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "DailyChest", streak)
	end)
	push(player)
	dailyAttributes(player)
	if earnedRemote then
		earnedRemote:FireClient(player, amount, { daily = true, streak = streak })
	end
	return { opened = true, amount = amount, streak = streak, nextIn = nextIn }
end

-- THE STORY FINISHED (Bootstrap, after its last level, for someone whose own walking got there): its bonus
-- (ShopCatalog.storyReward) and whatever is earned by the story (the green ribbon), once each time a story ends.
function EconomyService.finishStory(player: Player, hardcore: boolean)
	local profile = profiles[player]
	if not (profile and profile:IsActive()) then
		return
	end
	local double = passes[player] ~= nil and passes[player].DoubleTokens == true
	local amount = ShopCatalog.storyReward(hardcore, double)
	profile.Data.Tokens += amount
	profile.Data.Earned += amount
	logEconomy(player, true, amount, Enum.AnalyticsEconomyTransactionType.Gameplay.Name, "Story")
	local fresh = false
	for _, item in ipairs(ShopCatalog.all()) do
		if item.earn == "story" and not profile.Data.Owned[item.id] then
			profile.Data.Owned[item.id] = true
			fresh = true
		end
	end
	push(player)
	if earnedRemote then
		earnedRemote:FireClient(player, amount, { story = true, hardcore = hardcore, double = double, ribbon = fresh })
	end
end

function EconomyService.isWelcomed(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile.Data.Welcomed == true
end

function EconomyService.start()
	openStore()
	local events = ReplicatedStorage:WaitForChild("RemoteEvents")
	local functions = ReplicatedStorage:WaitForChild("RemoteFunctions")
	local request = functions:WaitForChild("ShopRequest") :: RemoteFunction
	local state = functions:WaitForChild("ShopState") :: RemoteFunction
	updateRemote = events:WaitForChild("ShopUpdate") :: RemoteEvent
	earnedRemote = events:WaitForChild("TokensEarned") :: RemoteEvent
	;(events:WaitForChild("Onboarding") :: RemoteEvent).OnServerEvent:Connect(onNote)
	emoteRemote = events:WaitForChild("Emote") :: RemoteEvent
	if RunService:IsStudio() then
		local dev = events:WaitForChild("DevPanel", 10)
		if dev and dev:IsA("RemoteEvent") then
			dev.OnServerEvent:Connect(onDev)
		end
	end
	;(emoteRemote :: RemoteEvent).OnServerEvent:Connect(onEmote)

	request.OnServerInvoke = onRequest
	state.OnServerInvoke = function(player: Player)
		return stateFor(player)
	end
	local journalState = functions:WaitForChild("JournalState", 10)
	if journalState and journalState:IsA("RemoteFunction") then
		journalState.OnServerInvoke = onJournal
	else
		warn("EconomyService: no RemoteFunctions.JournalState, so the journal is not read back next time. Paste "
			.. "src/Server/Bootstrap.server.lua.")
	end
	MarketplaceService.ProcessReceipt = receipt
	-- THE DASHBOARD SEES EVERY ROBUX PROMPT CLOSE (custom events PassPrompt and ProductPrompt, 1 bought, 0 not, the
	-- item in CustomField01): how many who are shown a price pay it, item by item. What is granted is the receipt's
	-- business, not this.
	local function promptClosed(player: Player?, event: string, item: any, bought: boolean)
		if not (player and item) then
			return
		end
		pcall(function()
			AnalyticsService:LogCustomEvent(player, event, if bought then 1 else 0,
				{ [Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = tostring(item.id) })
		end)
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, bought: boolean)
		promptClosed(Players:GetPlayerByUserId(userId), "ProductPrompt", ShopCatalog.byProduct(productId), bought)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, bought: boolean)
		local item = ShopCatalog.byPass(passId)
		promptClosed(player, "PassPrompt", item, bought)
		if bought and item then
			local owned = passes[player] or {}
			passes[player] = owned
			owned[item.id] = true
			player:SetAttribute("VIP", owned.VIP == true)
			player:SetAttribute("DoubleTokens", owned.DoubleTokens == true)
			grantStarter(player)
			push(player)
			dress(player)
		end
	end)

	local function joined(player: Player)
		-- THE VIP TAG comes off on a level and back on in the lobby.
		player:GetAttributeChangedSignal("InLevel"):Connect(function()
			vipTag(player)
		end)
		-- A NEW CHARACTER is dressed once its root is there (it may not be the moment it is added).
		player.CharacterAdded:Connect(function(character: Model)
			if character:WaitForChild("HumanoidRootPart", 10) then
				dress(player)
			end
		end)
		task.spawn(load, player)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		joined(player)
	end
	Players.PlayerAdded:Connect(joined)
	Players.PlayerRemoving:Connect(unload)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastJournal[player] = nil
		emoting[player] = nil
	end)
	-- THE MATERIALS UNDER EVERY RUNNER'S FEET (lookUnder), looked at twice a second.
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player in pairs(profiles) do
				pcall(lookUnder, player)
			end
		end
	end)
	-- NEW CHALLENGES AT MIDNIGHT UTC for everyone here (challengeAttributes picks them the first time a save sees the
	-- day), looked at every half minute.
	task.spawn(function()
		local shown = today()
		while true do
			task.wait(30)
			if today() ~= shown then
				shown = today()
				for player in pairs(profiles) do
					pcall(challengeAttributes, player)
				end
			end
		end
	end)
	-- /levels FOR AN ADMIN (toggleAdminOpen): a chat command where the place uses the new chat, so the line is never
	-- shown to anyone; a plain chat line read on the server otherwise.
	local TextChatService = game:GetService("TextChatService")
	local commandMade = false
	pcall(function()
		if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
			local command = Instance.new("TextChatCommand")
			command.Name = "AdminLevels"
			command.PrimaryAlias = "/levels"
			command.Triggered:Connect(function(source: TextSource)
				local who = Players:GetPlayerByUserId(source.UserId)
				if who then
					toggleAdminOpen(who)
				end
			end)
			command.Parent = TextChatService:FindFirstChild("TextChatCommands") or TextChatService
			commandMade = true
		end
	end)
	if not commandMade then
		local function listen(player: Player)
			player.Chatted:Connect(function(message: string)
				if string.lower(message) == "/levels" then
					toggleAdminOpen(player)
				end
			end)
		end
		for _, player in ipairs(Players:GetPlayers()) do
			listen(player)
		end
		Players.PlayerAdded:Connect(listen)
	end
	print(("EconomyService: running, %s."):format(if saving then "saving with ProfileStore" else "NOT SAVING (no ProfileStore)"))
end

EconomyService.STAMP = "0b849edf"
return EconomyService
