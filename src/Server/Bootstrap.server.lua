--!strict
-- ServerScriptService/Bootstrap.server.lua
-- Creates RemoteEvents/RemoteFunctions, starts the level, and wires the
-- top-level game loop: checkpointing, fail teleports, mode switching,
-- timer start/stop, and level completion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LevelDefinitions = require(Shared:WaitForChild("LevelDefinitions"))

-- WHICH LEVELS THIS PLACE HAS, said once at startup. The lobby builds a pad for each, named from
-- this list, so when the lobby shows the wrong levels the question is always whether
-- LevelDefinitions was pasted in. Levels 2 and 3 were Open Sky and Far Water before they became
-- Sky Pools and the Sunken City: either old name still here means the copy in
-- ReplicatedStorage.Shared is out of date.
do
	local names = {}
	local stale = false
	for _, level in ipairs(LevelDefinitions.All) do
		table.insert(names, ("%d %s"):format(level.levelId, tostring(level.name)))
		if level.name == "Open Sky" or level.name == "Far Water" then
			stale = true
		end
	end
	print("Bootstrap: the lobby's levels are " .. table.concat(names, ", ") .. ".")
	if stale then
		warn("Bootstrap: ReplicatedStorage.Shared.LevelDefinitions is an older copy (level 2 or 3 is still Open "
			.. "Sky or Far Water), so the lobby shows the old levels. Paste src/Shared/LevelDefinitions.lua over it.")
	end
end

-- ===== RemoteEvents / RemoteFunctions =====
--
-- ORDER MATTERS: these are created BEFORE any service is required.
-- DeformationService blocks at module scope on WaitForChild("RemoteEvents"),
-- and it is pulled in transitively by LevelService. If the requires ran first,
-- this script would deadlock inside require() waiting for a folder that only
-- this script creates, and nothing downstream (level, remotes, spawn) would
-- ever initialise. Do not move the service requires above this block.

local function ensureFolder(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function ensureRemoteEvent(parent: Instance, name: string): RemoteEvent
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local re = Instance.new("RemoteEvent")
	re.Name = name
	re.Parent = parent
	return re
end

local function ensureRemoteFunction(parent: Instance, name: string): RemoteFunction
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	local rf = Instance.new("RemoteFunction")
	rf.Name = name
	rf.Parent = parent
	return rf
end

local remoteEventsFolder = ensureFolder(ReplicatedStorage, "RemoteEvents")
local remoteFunctionsFolder = ensureFolder(ReplicatedStorage, "RemoteFunctions")

local DeformationUpdate = ensureRemoteEvent(remoteEventsFolder, "DeformationUpdate")
local PlayerModeChanged = ensureRemoteEvent(remoteEventsFolder, "PlayerModeChanged")
local ModeToggleBlocked = ensureRemoteEvent(remoteEventsFolder, "ModeToggleBlocked")
local LevelCompleted = ensureRemoteEvent(remoteEventsFolder, "LevelCompleted")
local LeaveLevel = ensureRemoteEvent(remoteEventsFolder, "LeaveLevel")
-- The lever's two halves talk over these. HubBoardToggle is the client's copy of the switch
-- asking to be thrown; HubBoardMode is the server telling one client which way its lever now
-- points. Both are per player -- nothing here is ever broadcast.
local HubBoardToggle = ensureRemoteEvent(remoteEventsFolder, "HubBoardToggle")
local HubBoardMode = ensureRemoteEvent(remoteEventsFolder, "HubBoardMode")
-- The ballot, broadcast to everyone: ticks while the countdown runs, then the result. It is
-- the same payload for all of them, because a vote count is public by definition.
local HubVoteState = ensureRemoteEvent(remoteEventsFolder, "HubVoteState")
-- Slime launches must be applied by the client that owns the character. Writing
-- velocity from the server onto a client-owned assembly gets discarded on the
-- next physics replication, which is why the launch felt weak and inconsistent.
local SlimeLaunch = ensureRemoteEvent(remoteEventsFolder, "SlimeLaunch")
-- THE SCREEN GOING BLACK, for the one ending that asks for it. City Shore finishes by hitting
-- the sea seven hundred studs down; the screen fades out as the water closes over you, the
-- completion banner reads on the black, and it fades back once the lobby has you. Per player,
-- both ways.
local ScreenFade = ensureRemoteEvent(remoteEventsFolder, "ScreenFade")

local RequestLeaderboardData = ensureRemoteFunction(remoteFunctionsFolder, "RequestLeaderboardData")
local CanToggleMode = ensureRemoteFunction(remoteFunctionsFolder, "CanToggleMode")
-- THE HUD ASKS, instead of only being told.
--
-- Every part of the run HUD -- the clock, the best-times panel and the mode readout --
-- hangs off a single HardcoreTimerSync push, fired once as the run starts. A single
-- fire-and-forget at the exact moment the character is being moved to a new level is a
-- race by construction: miss it and the HUD stays hidden until something else happens to
-- fire it, and the only other caller is the kill plane. That is precisely the reported
-- "I have to jump off before the menus and the timer appear".
--
-- A push cannot be made reliable by firing it harder. So the client now also PULLS: it
-- asks on startup and on every spawn, and the answer is the same payload the push sends.
-- Whichever arrives first wins and the other is a harmless repeat.
local RequestRunState = ensureRemoteFunction(remoteFunctionsFolder, "RequestRunState")
-- The hardcore clock lives on the server (TimerService), but a label that only updated
-- when the server sent a packet would tick once a checkpoint. This carries the state
-- changes -- started, reset, stopped -- and the client runs the seconds itself between
-- them, so the display is smooth and still cannot drift from the authoritative time.
local HardcoreTimerSync = ensureRemoteEvent(remoteEventsFolder, "HardcoreTimerSync")
-- Falling in hardcore used to happen in silence: one frame mid-air, the next back on chunk
-- one with a reset clock and nothing saying the run had ended. PlayerFell is the server
-- telling you it noticed; HardcoreRetry is you saying you want another go.
local PlayerFell = ensureRemoteEvent(remoteEventsFolder, "PlayerFell")
local HardcoreRetry = ensureRemoteEvent(remoteEventsFolder, "HardcoreRetry")
-- SKY POOLS' SLIDE. The rider's own client answers on this to say it is drawing the ride, and the
-- server hands it the sled to drive; see SkyPoolsService.attachSlide for why. Made here with every
-- other remote so it exists before any level is built.
ensureRemoteEvent(remoteEventsFolder, "SkyRide")
-- THE SUNKEN CITY'S DRAIN, for the same reason: the rider's own client draws the ride down the
-- whirlpool and answers on this to say it has it.
ensureRemoteEvent(remoteEventsFolder, "SunkenRide")
-- CITY SHORE'S DIVE, played as a scene on the diver's screen and posed on everyone's (DiveFinaleService
-- tells, CityShoreClient draws).
ensureRemoteEvent(remoteEventsFolder, "DiveCinema")
-- THE FLOODED HALLS' FLUME AND THE GATES UNDER IT, played as a scene (FloodedHallsService tells,
-- FloodedHallsClient draws).
ensureRemoteEvent(remoteEventsFolder, "HallsCinema")
-- THE STORY'S SMALL MOMENTS: a secret found, a line whispered (Interactables tells, StoryClient shows),
-- and what you pick up going into your journal (JournalService).
ensureRemoteEvent(remoteEventsFolder, "StoryMoment")
-- WHAT YOU SAY TO THE TOWNSFOLK (Townsfolk offers your choices, TalkClient shows them and sends back the one chosen).
ensureRemoteEvent(remoteEventsFolder, "Talk")
-- HILL HOUSE'S HALL (the hundred-and-twelfth pass): the server says "key" as you take his key off its hook, and
-- HillHouseClient plays it as a scene on your screen.
ensureRemoteEvent(remoteEventsFolder, "HillScene")
-- THE SHOP (EconomyService on the server, ShopService on the client): the client asks to buy or wear
-- something (ShopRequest) and reads its tokens and what it owns (ShopState); the server says when that
-- changes (ShopUpdate) and what a finished run paid (TokensEarned).
ensureRemoteFunction(remoteFunctionsFolder, "ShopRequest")
ensureRemoteFunction(remoteFunctionsFolder, "ShopState")
-- THE JOURNAL KEPT BETWEEN SESSIONS (EconomyService): what you had, asked for once your save is loaded.
ensureRemoteFunction(remoteFunctionsFolder, "JournalState")
ensureRemoteEvent(remoteEventsFolder, "ShopUpdate")
ensureRemoteEvent(remoteEventsFolder, "TokensEarned")
-- THE FIRST FIVE MINUTES: the client notes what a new player has been shown (the welcome, the lobby
-- guide, a material's hint), so it is shown once. It can set those flags and nothing else.
ensureRemoteEvent(remoteEventsFolder, "Onboarding")
-- THE EMOTES (a player asks, the server checks they own it and tells everyone) and THE SECOND CHANCE (a
-- hardcore runner asks to go back to where they fell from; one bought is spent).
ensureRemoteEvent(remoteEventsFolder, "Emote")
ensureRemoteEvent(remoteEventsFolder, "SecondChance")
-- THE SQUISH ROOM: the server tells a player in it that the lobby is away for a run ("closed").
ensureRemoteEvent(remoteEventsFolder, "SquishRoom")
-- STUDIO ONLY: the test panel (DevPanelClient). Not made in the live game, and nothing listens there.
if game:GetService("RunService"):IsStudio() then
	ensureRemoteEvent(remoteEventsFolder, "DevPanel")
end
-- AN ENDING'S WORD, from the player's own screen (Cinema): "began" as the scene starts, "done" once it
-- has been watched, its captions read. The return to the lobby waits for "done" (see completeRun), so a
-- scene is never cut off in the middle of a sentence.
local SceneState = ensureRemoteEvent(remoteEventsFolder, "SceneState")
local sceneState: { [Player]: string } = {}
SceneState.OnServerEvent:Connect(function(player: Player, state: any)
	if state == "began" or state == "done" then
		sceneState[player] = state
	end
end)
game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
	sceneState[player] = nil
end)
-- The longest an ending is waited for, whatever its screen says: a client that never answers must not
-- keep anyone out of the lobby.
local SCENE_WAIT = 50

-- ===== Services =====
-- Safe to require now that the remotes above exist.

local Services = script.Parent:WaitForChild("Services")
local LevelService = require(Services:WaitForChild("LevelService"))
local PlayerStateService = require(Services:WaitForChild("PlayerStateService"))
local TimerService = require(Services:WaitForChild("TimerService"))
local LeaderboardService = require(Services:WaitForChild("LeaderboardService"))
local LightingService = require(Services:WaitForChild("LightingService"))
-- For the hardcore restart, which repairs the level's damage in place. ChunkService was
-- required here too while that restart rebuilt the level; it no longer does, and a require
-- kept "in case" is a claim about what this file uses that stops being true immediately.
local DeformationService = require(Services:WaitForChild("DeformationService"))
-- REQUIRED WITH A TIMEOUT, because a bare WaitForChild yields FOREVER.
--
-- The pcall around BackdropService.build below guards a build ERROR and does nothing
-- whatsoever about the module being ABSENT -- that failure lands here, at the require, and
-- takes down every line beneath it including level generation. Which is exactly the
-- failure the LightingService pcall was written to prevent, reintroduced eight lines
-- higher up. A missing scenery module is a horizon that does not appear, not a server that
-- never starts.
local backdropModule = Services:WaitForChild("BackdropService", 5)
local BackdropService = if backdropModule then require(backdropModule :: ModuleScript) :: any else nil
-- The flooded halls, for the level whose backdrop is a building rather than a horizon.
-- Optional in exactly the way BackdropService is, and for the same reason: a place that
-- has not imported these meshes should still run every other level.
local hallsModule = Services:WaitForChild("FloodedHallsService", 5)
local FloodedHallsService = if hallsModule then require(hallsModule :: ModuleScript) :: any else nil
-- The high dive that finishes City Shore. Optional in exactly the way the two above are: a place
-- without it still runs every level, that one finishing at the end of its route instead.
local diveModule = Services:WaitForChild("DiveFinaleService", 5)
local DiveFinaleService = if diveModule then require(diveModule :: ModuleScript) :: any else nil
-- Sky Pools' terraces, tower, clouds and slide. Optional in exactly the way the three above are: a
-- place without it still runs Level 2, as a bare ring finishing at the end of its route.
local skyModule = Services:WaitForChild("SkyPoolsService", 5)
local SkyPoolsService = if skyModule then require(skyModule :: ModuleScript) :: any else nil
-- Disconnects the slide's prompt. The pools themselves are parented under Workspace.Levels, so the
-- level's own teardown takes them; this is for the one connection that would outlive them.
local skyTeardown: (() -> ())? = nil
-- The Sunken City's drowned city, aquarium and drain. Optional in the same way: a place without it
-- still runs Level 3, as a bare flat ring finishing at the end of its route.
-- HILL HOUSE (the hundred-and-eleventh pass): the crag, the garden and the house at the end of level 5. Optional in the
-- same way: a place without it still runs Hill House, as a spiral finishing at the end of its route.
local hillModule = Services:WaitForChild("HillHouseService", 5)
local HillHouseService = if hillModule then require(hillModule :: ModuleScript) :: any else nil
local sunkenModule = Services:WaitForChild("SunkenCityService", 5)
local SunkenCityService = if sunkenModule then require(sunkenModule :: ModuleScript) :: any else nil
-- Disconnects the drain's watch and the aquarium glass. The city itself goes with Workspace.Levels.
local sunkenTeardown: (() -> ())? = nil
-- THE STORY (Harrow Bay, 14 August): each level's opening words, and City Shore's people. Optional: a
-- place without it plays the same levels with nobody in them and nothing said.
local storyModule = Services:WaitForChild("StoryService", 5)
local StoryService = if storyModule then require(storyModule :: ModuleScript) :: any else nil
-- THE SHOP'S SERVER SIDE: tokens, what each player owns and wears, Robux purchases. Optional, and
-- required in a pcall: a place without it (or without ShopCatalog) plays every level and pays nothing.
local EconomyService: any = nil
do
	local economyModule = Services:WaitForChild("EconomyService", 5)
	if economyModule then
		local ok, loaded = pcall(require, economyModule :: ModuleScript)
		if ok then
			EconomyService = loaded
			task.spawn(function()
				local started, err = pcall(EconomyService.start)
				if not started then
					warn("Bootstrap: EconomyService failed to start, so the shop is closed: " .. tostring(err))
				end
			end)
		else
			warn("Bootstrap: EconomyService failed to load (is ReplicatedStorage.Shared.ShopCatalog pasted?): " .. tostring(loaded))
		end
	end
end
-- Undoes the halls' GLOBAL changes -- lighting, reverb, the caustic loop -- when a run
-- ends. Left set, every other level would inherit a bathhouse.
local hallsTeardown: (() -> ())? = nil

-- ===== WHAT A LEVEL LEAVES BEHIND, TAKEN AWAY =====
--
-- Most of a level goes when Workspace.Levels is cleared, because that is where it is parented.
-- Three things are not in there and do not:
--
--   THE FLOODED HALLS are their own model in the workspace, several hundred parts of the room you
--   were standing in, with a caustic loop and a water loop still running.
--   THEIR LOOK -- a bloom, a depth of field and a grade hung on Lighting.
--   SKY POOLS' WATER, which is terrain, and terrain belongs to the place rather than to a model.
--
-- This used to run only when the NEXT level was built, so finishing a run and going back to the
-- lobby left the lobby standing in the last level's weather with its rooms still in the world.
-- It runs on the way home as well now.
local function tearDownLevelWorld()
	if hallsTeardown then
		pcall(hallsTeardown)
		hallsTeardown = nil
	end
	local oldHalls = workspace:FindFirstChild("FloodedHalls")
	if oldHalls then
		oldHalls:Destroy()
	end
	if SkyPoolsService and SkyPoolsService.clearWater then
		pcall(SkyPoolsService.clearWater)
	end
end
if not BackdropService then
	warn(
		"Bootstrap: no ServerScriptService.Services.BackdropService; running without a horizon. "
			.. "Paste src/Server/Services/BackdropService.lua in as a ModuleScript to get one."
	)
end

-- Applied before the level is generated so the first frame anyone sees is already
-- correctly lit.
--
-- In a pcall because it is purely cosmetic and must never be able to stop the game
-- from starting. It already did once: reading Lighting.Technology throws without an
-- internal capability, and that error aborted everything below this line, so the level
-- was never generated and nobody was ever placed on it. A lighting tweak taking out
-- level generation is the wrong failure mode at any severity.
local lightingOk, lightingErr = pcall(LightingService.apply)
if not lightingOk then
	warn("Bootstrap: LightingService.apply failed, continuing without it: " .. tostring(lightingErr))
end

-- ===== Level start =====

-- THE HUB DECIDES WHICH LEVEL RUNS, and Bootstrap no longer does.
--
-- This used to be `local CURRENT_LEVEL = LevelDefinitions.Sandbox` with a level built at
-- server start. Nothing is built at boot any more: the room is, and a level only exists
-- while someone is running it.
local HubService = require(script.Parent.Services.HubService)
local BestTimeService = require(script.Parent.Services.BestTimeService)
local levelInstance = nil

-- FORWARD-DECLARED. Starting a level has to wire its checkpoints, and wiring checkpoints
-- needs the level -- so one of the two has to be named before it is written. This is the
-- shorter one to hoist.
-- FORWARD-DECLARED alongside wireCheckpointing, for the same reason: the leave handler
-- pushes the clock to the client and is written above the function that does it.
local syncTimer: (Player) -> ()
local wireCheckpointing: ({ Player }) -> ()
-- FINISHING A RUN, as a function rather than only as a Touched handler.
--
-- The flooded halls end by RIDING the flume, and the ride sets the rider's CFrame directly. A
-- part that is teleported onto a trigger does not reliably raise Touched -- there was no
-- movement into it to detect -- so hanging the only completion path off the trigger means the
-- one level that finishes by riding is the one level that can fail to finish at all.
--
-- Assigned by wireCheckpointing, called by both. Forward-declared because the ride is attached
-- while the level is being built and the handler is written a few hundred lines below: read at
-- call time, not at wiring time, so the order does not matter.
--
-- Re-entry is not a concern. The first thing it does is check hasCompletedLevel, so a rider who
-- also brushes the trigger completes once.
local finishRunFor: ((Player) -> ())? = nil
-- THE HARDCORE RESET, for things that are not falls: the Sunken City's thing taking a Hardcore player
-- off the route when it surfaces. Forward-declared for the reason finishRunFor is (the level is wired
-- above the code it needs), assigned beside restartRunFor, and the same five steps as the kill plane's
-- Hardcore branch, which blender/check_sunkencity.py holds the two to.
local sendBackToStart: ((Player) -> ())? = nil
-- THE SECOND CHANCE: where each hardcore runner was, and their clock, the moment before a fall sent them
-- back to the start. Used within WINDOW seconds (one bought, EconomyService), it puts them back there
-- with the clock where it was; that run then counts for neither the leaderboard nor a best.
-- THE RUN'S LENGTH as the lobby voted it, kept from the moment the run starts (the lobby's choice may
-- move on while the run is played).
local runLength = "medium"
-- And its backdrop (what a runner's client is told it is in, InLevel), for someone who joins it late.
local runBackdrop: string? = nil

-- THE FASTEST A RUN CAN BE PLAYED, by its length: ShopCatalog's MIN_SECONDS, the floor the tokens use.
-- Required in a pcall, so a place without ShopCatalog still runs (with no floor).
local fastest: { [string]: number }? = nil
do
	local ok, catalog = pcall(function()
		return require(ReplicatedStorage:WaitForChild("Shared"):FindFirstChild("ShopCatalog") :: ModuleScript)
	end)
	if ok and type(catalog) == "table" and type(catalog.REWARD) == "table" then
		fastest = catalog.REWARD.MIN_SECONDS
	end
end

-- THE ROUTE WALKED: the server saw the runner at the last checkpoint in the first three quarters of the
-- route, which no way to the finish skips (a teleport to it does). Asked for a time to count, and for a run
-- to pay its tokens at all.
local function walkedRoute(player: Player, state: any): boolean
	if not levelInstance then
		return false
	end
	-- SKIPPED with the test panel's Near the end (Studio): not a run walked, whatever the checkpoints say.
	if state.skipped then
		warn(("Bootstrap: %s's run was skipped with Near the end, so it counts for nothing."):format(player.Name))
		return false
	end
	local count = #levelInstance.placedChunks
	local needed = 0
	local definitions = require(ReplicatedStorage.Shared.ChunkDefinitions)
	for _, entry in ipairs(levelInstance.placedChunks) do
		local def = definitions[entry.chunkId]
		local index = entry.index
		if type(index) == "number" and def and def.category == "stable" and index <= count * 0.75
			and index > needed then
			needed = index
		end
	end
	if (state.checkpointChunkIndex or 0) < needed then
		warn(("Bootstrap: %s finished without reaching checkpoint %d (last seen at %d); not a run walked.")
			:format(player.Name, needed, state.checkpointChunkIndex or 0))
		return false
	end
	return true
end

-- A TIME THAT COUNTS, for a personal best and for the leaderboard. Three things the server saw for itself:
--   * the clock ran: hardcore, and more than nothing (chill has no clock, and its "best" used to be saved
--     as 0 and shown on the lobby board as 00:00);
--   * the runner reached the last checkpoint in the first three quarters of the route, which no way to the
--     finish skips (a teleport to the finish does);
--   * it is no faster than half the fastest a run of this length can be played (ShopCatalog's floor).
-- A time that does not count still finishes the run and, if the route was walked, still pays its tokens; it
-- is only not kept.
local function fairTime(player: Player, state: any): boolean
	if not levelInstance or state.mode ~= "hardcore" then
		return false
	end
	local elapsed = TimerService.getElapsed(player)
	if elapsed <= 0 then
		return false
	end
	if not walkedRoute(player, state) then
		return false
	end
	local floor = fastest and fastest[runLength]
	if floor and elapsed < floor * 0.5 then
		warn(("Bootstrap: %s finished a %s run in %.1f s, faster than it can be played; the time is not kept.")
			:format(player.Name, runLength, elapsed))
		return false
	end
	return true
end

-- ===== THE DASHBOARD'S VIEW OF THE LEVELS =====
--
-- Each run is a step on one progression path ("Levels", the level's id its step), so the Creator Dashboard shows
-- how many players start each level, how many finish it, and how many leave it partway (from the menu, or by
-- leaving the server); the mode and the length go along as custom fields. Kept here per player (not read back
-- from the hub, which lets go of a leaving runner before this hears of it). Guarded: it never gets in a run's way.
local AnalyticsService = game:GetService("AnalyticsService")
local PROGRESSION_PATH = "Levels"
local runningFor: { [Player]: { levelId: number, name: string, fields: { [string]: any } } } = {}

local function progression(player: Player, status: string)
	local run = runningFor[player]
	if status == "start" then
		local instance = levelInstance
		if not instance then
			return
		end
		local request = HubService.getRequest()
		local level = HubService.levelById(instance.levelId)
		run = {
			levelId = instance.levelId,
			name = tostring(level and level.name or ("Level " .. tostring(instance.levelId))),
			fields = {
				[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = tostring(request.mode),
				[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = tostring(runLength),
			},
		}
		runningFor[player] = run
	else
		runningFor[player] = nil
	end
	if not run then
		return
	end
	local logged = run
	pcall(function()
		if status == "start" then
			AnalyticsService:LogProgressionStartEvent(player, PROGRESSION_PATH, logged.levelId, logged.name, logged.fields)
		elseif status == "complete" then
			AnalyticsService:LogProgressionCompleteEvent(player, PROGRESSION_PATH, logged.levelId, logged.name, logged.fields)
		else
			AnalyticsService:LogProgressionFailEvent(player, PROGRESSION_PATH, logged.levelId, logged.name, logged.fields)
		end
	end)
end

local secondChance = {
	WINDOW = 45,
	falls = {} :: { [Player]: { at: number, position: Vector3, backward: Vector3, chunk: number, elapsed: number } },
}

-- FRIENDS IN THE RUN (EconomyService.newlyWithFriends): each told on their card, a moment after arriving and once while
-- they are here, that reaching the end pays more for it.
local FRIEND_TELL_AFTER = 4
local function tellRunFriends()
	if not (EconomyService and EconomyService.newlyWithFriends) then
		return
	end
	task.delay(FRIEND_TELL_AFTER, function()
		local ok, news = pcall(EconomyService.newlyWithFriends)
		if not ok then
			warn("Bootstrap: looking for friends in the run failed: " .. tostring(news))
			return
		end
		for _, player in ipairs(news) do
			if player.Parent ~= nil then
				HubVoteState:FireClient(player, "friend", { percent = EconomyService.friendPercent() })
			end
		end
	end)
end

local function startChosenLevel(level, players: { Player }, origin: Vector3)
	-- THE DIVE STANDS DOWN FIRST, before the old level is cleared out from under it. Its watch
	-- puts the platform back whenever it finds it destroyed, so a stop that came after the clear
	-- would have it rebuilding a platform for a level that no longer exists, in the frame the
	-- PREVIOUS run ended at.
	if DiveFinaleService then
		pcall(DiveFinaleService.stop)
	end
	-- Hill House's crag is terrain, so it goes first too (its parts go with the level; its ground would not).
	if HillHouseService then
		pcall(HillHouseService.stop)
	end
	levelInstance = LevelService.startLevel(level, players, origin)
	runLength = HubService.getRequest().length
	runBackdrop = level.backdrop
	-- THE RUN IS NOTED for its tokens: who is in it, how long it is, and when it began.
	if EconomyService then
		pcall(EconomyService.runStarted, players, HubService.getRequest().length)
		tellRunFriends()
	end
	-- A RING LEVEL ON AN OLD LEVELSERVICE lays the old tight spiral and hands back no centre, so
	-- the pools or the city would be built round the wrong point. Said here, where it happens.
	if level.ring and levelInstance and not levelInstance.centre then
		warn(("Bootstrap: %s is laid on a ring, and this place's LevelService is an older copy that "
			.. "cannot lay one -- re-paste src/Server/Services/LevelService.lua."):format(tostring(level.name)))
	end
	-- THE SAME, FOR A MEANDER. An older LevelService does not know the layout and quietly lays the
	-- old spiral instead, which puts the pools and the tower round a route that is not there.
	if level.layout == "meander" and levelInstance and levelInstance.layout ~= "meander" then
		warn(("Bootstrap: %s asks to be laid as a meander and this place's LevelService laid a %s "
			.. "instead -- re-paste src/Server/Services/LevelService.lua."):format(tostring(level.name),
			tostring(levelInstance.layout or "spiral")))
	end

	-- AFTER the level, because the backdrop measures the level's extent to find the middle
	-- to centre itself on. In a pcall for the same reason LightingService is: it is purely
	-- scenery and must never be able to stop players being placed on the level below.
	--
	-- Nil-checked BEFORE the pcall rather than inside it, because `pcall(x.build)` indexes x
	-- to find the argument and only then calls pcall -- so a missing module would throw
	-- outside the pcall it looks like it is protected by.
	-- THE BACKDROP IS WHAT MAKES A LEVEL A LEVEL. Levels share one chunk pool and differ only
	-- in what stands behind them, so this is the line that tells them apart.
	--
	-- An existing backdrop is REMOVED for a level that wants none, not just left unbuilt:
	-- BackdropService.build reuses whatever is already in the workspace, so coming from the
	-- city shore to an empty theme would otherwise keep the city.
	-- THE FLOODED HALLS, torn down first so a second run never builds inside the first.
	--
	-- Unlike the backdrop this is not scenery seen from a distance -- it is the room the player
	-- is standing in, several hundred parts of it, and two overlapping is not a cosmetic
	-- problem. Torn down unconditionally rather than only when leaving this level, because the
	-- level that follows might be any of them.
	tearDownLevelWorld()

	if level.backdrop == "floodedHalls" and FloodedHallsService then
		-- Each piece in a pcall, for the reason the backdrop is: this is atmosphere, and
		-- atmosphere must never be able to stop players being placed on the level below it.
		local built: Model? = nil
		local ok, err = pcall(function()
			-- THE ROUTE THE CHUNKS ACTUALLY TOOK, handed straight over. The halls are built
			-- around it rather than beside it, which is the only reason the two agree about
			-- where a corner is.
			built = FloodedHallsService.build(origin, levelInstance)
		end)
		if not ok then
			warn("Bootstrap: FloodedHallsService.build failed, running without it: "
				.. tostring(err))
		elseif built then
			-- Every one of these hands back its own undo, collected into a single function so
			-- the ender has one thing to call. Lighting, reverb and the caustic loop are all
			-- GLOBAL or ongoing: none of them clean themselves up.
			local undos = {}
			for _, apply in ipairs({
				function()
					return FloodedHallsService.applyAtmosphere()
				end,
				function()
					return FloodedHallsService.applySound(built :: Model)
				end,
				function()
					return FloodedHallsService.applyCaustics(built :: Model, origin)
				end,
				-- THE SURFACE ITSELF, which is a running loop rather than a property, and so
				-- hands back an undo like the rest of them. Without this the water is a plate
				-- of green glass: correct, still, and dead.
				function()
					return FloodedHallsService.applyWater(built :: Model)
				end,
			}) do
				local fine, undo = pcall(apply)
				if fine and typeof(undo) == "function" then
					table.insert(undos, undo)
				end
			end
			-- THE FINISH MOVES TO THE BOTTOM OF THE FLUME.
			--
			-- LevelService puts finishPart at the end of the chunk route, which on this level
			-- is the doorway of the far chamber -- so the run would end as you walked in,
			-- before the thing it was walking towards.
			--
			-- Moved rather than replaced: every rule about best times, hardcore clocks and
			-- returning to the hub already hangs off finishPart.Touched, and a second
			-- completion path would be a second place for those rules to drift.
			local landing = (built :: Model):GetAttribute("SlideLanding")
			if levelInstance and levelInstance.finishPart and typeof(landing) == "CFrame" then
				levelInstance.finishPart.CFrame = landing
			end
			local unride = FloodedHallsService.attachSlide(built :: Model, function(player)
				-- THE TRUE ENDING seen (the hundred-and-sixteenth pass): a rider who clocked in at the time clock by Mr
				-- Barlow came through the gates to his face; its reward, once a save, before the run's own.
				if player:GetAttribute("ClockedIn") == true and EconomyService and EconomyService.trueEnding then
					pcall(EconomyService.trueEnding, player)
				end
				if finishRunFor then
					finishRunFor(player)
				end
			end)
			if typeof(unride) == "function" then
				table.insert(undos, unride)
			end

			hallsTeardown = function()
				for _, undo in ipairs(undos) do
					pcall(undo)
				end
			end
		end
	end

	-- THE LEVEL'S OWN LIGHT, before anything of it is built, so the first frame is already lit
	-- the way the rest of the run will be. Each level names a palette through its `backdrop`
	-- (LightingService.palettes); a level with no palette of its own falls back to the default.
	--
	-- This has to happen HERE rather than once at boot, because the lobby sets the atmosphere for
	-- the whole game while it builds the room -- so a palette applied before that is overwritten
	-- by the lobby's, which is why City Shore has been running under the room's haze.
	local levelLightOk, levelLightErr = pcall(LightingService.apply, level.backdrop)
	if not levelLightOk then
		warn("Bootstrap: lighting for this level failed, continuing with whatever is set: "
			.. tostring(levelLightErr))
	end

	local existingBackdrop = workspace:FindFirstChild("Backdrop")
	if level.backdrop == "cityShore" then
		if BackdropService then
			local backdropOk, backdropErr = pcall(BackdropService.build)
			if not backdropOk then
				warn("Bootstrap: BackdropService.build failed, continuing without it: " .. tostring(backdropErr))
			end
		end
	elseif existingBackdrop then
		existingBackdrop:Destroy()
	end

	-- ===== THE HIGH DIVE =====
	--
	-- AFTER THE BACKDROP, because the platform's finish is the sea's surface and the sea is part
	-- of the backdrop. Torn down first for the reason the halls are: a second run must never
	-- build a second platform, and a level that does not want one must not inherit it.
	--
	-- The old finish line stands down when it builds. Both would otherwise fire: walking to the
	-- end of the last chunk would complete the run, and the dive it leads to would be scenery.
	-- ===== AND IF IT CANNOT BE BUILT, SAY SO =====
	--
	-- The fallback when any of this fails is the OLD FINISH LINE, which completes the run at the
	-- end of the route and sends everyone to the lobby -- which is precisely the ending the dive
	-- replaced. So a level that asks for a dive and does not get one looks exactly like a level
	-- that was never changed, and all three ways it could happen used to be silent:
	--
	--   the module is not in Studio          (nothing is pasted, so nothing warns)
	--   LevelService is an older copy        (no finishFrame, so there is nowhere to build)
	--   the build itself threw               (warned, but only in the pcall's own words)
	--
	-- Reported as "there was no diving board and it completed anyway". Each one names the file to
	-- paste now, and the success path prints where the platform went, so the Output always says
	-- which of the four happened.
	-- ONE LINE PER RUN saying which ending this level armed. The dive's own warnings cover every
	-- way it can fail once it is asked for; this covers the level never asking at all.
	local ending = "at the end of its route"
	if level.finale == "dive" then
		ending = "with the high dive"
	elseif level.finale == "slide" then
		ending = "with the slide into the clouds"
	elseif level.finale == "drain" then
		ending = "down the harbour drain"
	elseif level.finale == "house" then
		ending = "at his front door"
	end
	print(("Bootstrap: %s (level %s) ends %s."):format(tostring(level.name), tostring(level.levelId), ending))
	if level.finale == "dive" then
		if not DiveFinaleService then
			warn("Bootstrap: this level ends with a dive, and there is no "
				.. "ServerScriptService.Services.DiveFinaleService in this place -- so it is "
				.. "finishing at the end of its route instead, with no diving board. Paste "
				.. "src/Server/Services/DiveFinaleService.lua in as a ModuleScript named exactly "
				.. "DiveFinaleService.")
		elseif not levelInstance.finishFrame then
			warn("Bootstrap: this level ends with a dive, and LevelService handed back no "
				.. "finishFrame -- so there is nowhere to put the platform and the run is "
				.. "finishing at the end of its route instead. The LevelService in this place is "
				.. "an older copy: re-paste src/Server/Services/LevelService.lua.")
		else
			local frame: CFrame = levelInstance.finishFrame
			local diveOk, diveErr = pcall(function()
				DiveFinaleService.start(
					frame,
					workspace:WaitForChild("Levels"),
					if BackdropService then BackdropService.waterLevelAt else nil,
					function(player: Player)
						-- NO BLACKOUT, and that was the mistake worth naming. The dive is the best
						-- thing in this level, the water closing over you says "that was the end"
						-- on its own, and cutting to black threw the picture away at exactly that
						-- moment -- leaving a small grey banner alone on an empty screen. The
						-- banner carries the ending now, over the sea, in the level's own colours
						-- (UIService.showCompletion). `ScreenFade` is only the story's now, for
						-- the move between its levels (storyNext).
						if finishRunFor then
							finishRunFor(player)
						end
					end
				)
			end)
			if diveOk then
				-- THE OLD FINISH LINE STANDS DOWN. Both would otherwise fire, and the one at the
				-- end of the route fires first: you would complete the level by walking up to the
				-- board rather than by jumping off it.
				if levelInstance.finishPart then
					levelInstance.finishPart.CanTouch = false
				end
			else
				warn("Bootstrap: the high dive failed to build, so this level is finishing at the "
					.. "end of its route instead: " .. tostring(diveErr))
			end
		end
	end

	-- ===== HILL HOUSE (the hundred-and-eleventh pass) =====
	--
	-- The crag, the garden and the house, built beside the route's end (HillHouseService). Like the dive, the door IS
	-- the ending, so the old finish line stands down once it is built; and every way it can fail falls back to it and
	-- says so.
	if level.finale == "house" then
		if not HillHouseService then
			warn("Bootstrap: this level is Hill House, and there is no ServerScriptService.Services.HillHouseService in "
				.. "this place, so it is finishing at the end of its route instead, with no house. Paste "
				.. "src/Server/Services/HillHouseService.lua in as a ModuleScript named exactly HillHouseService.")
		elseif not (levelInstance.finishFrame and levelInstance.centre and levelInstance.killY) then
			warn("Bootstrap: this level is Hill House, and LevelService handed back no finish frame, centre or kill "
				.. "plane, so the house cannot be placed. Re-paste src/Server/Services/LevelService.lua.")
		else
			local houseOk, houseErr = pcall(function()
				HillHouseService.start(levelInstance.finishFrame, workspace:WaitForChild("Levels"), levelInstance.centre,
					levelInstance.killY, function(player: Player)
						if finishRunFor then
							finishRunFor(player)
						end
					end)
			end)
			if houseOk then
				if levelInstance.finishPart then
					levelInstance.finishPart.CanTouch = false
				end
			else
				warn("Bootstrap: Hill House failed to build, so this level is finishing at the end of its route "
					.. "instead: " .. tostring(houseErr))
			end
		end
	end

	-- ===== SKY POOLS =====
	--
	-- The terraces, the tower, the cloud sea and the slide, built round the ring LevelService just
	-- laid. The last run's slide prompt is disconnected first; its parts went with its level.
	--
	-- Like the dive, the slide IS the ending, so the old finish line stands down once it is built:
	-- otherwise stepping onto the finale deck would complete the run before the slide it leads to.
	-- And like the dive, every way this can fail falls back to that finish line and says so.
	if skyTeardown then
		skyTeardown()
		skyTeardown = nil
	end
	if level.backdrop == "skyPools" then
		if not SkyPoolsService then
			warn("Bootstrap: this level is Sky Pools, and there is no "
				.. "ServerScriptService.Services.SkyPoolsService in this place -- so it is a bare ring of "
				.. "chunks finishing at the end of its route, with no pools and no slide. Paste "
				.. "src/Server/Services/SkyPoolsService.lua in as a ModuleScript named exactly SkyPoolsService.")
		else
			local built: Model? = nil
			local skyOk, skyErr = pcall(function()
				built = SkyPoolsService.build(levelInstance, workspace:WaitForChild("Levels"))
			end)
			if not skyOk then
				warn("Bootstrap: SkyPoolsService.build failed, so this level is finishing at the end of its "
					.. "route instead: " .. tostring(skyErr))
			elseif built then
				local unride = SkyPoolsService.attachSlide(built :: Model, function(player: Player)
					if finishRunFor then
						finishRunFor(player)
					end
				end)
				if levelInstance.finishPart then
					levelInstance.finishPart.CanTouch = false
				end
				skyTeardown = function()
					if typeof(unride) == "function" then
						pcall(unride)
					end
					-- THE POOLS' WATER IS TERRAIN, and terrain is not part of the level's model, so
					-- it does not go when the model does. Taken out here, or the next level would
					-- start with pools of water standing in its sky.
					if SkyPoolsService.clearWater then
						pcall(SkyPoolsService.clearWater)
					end
				end
			end
		end
	end

	-- ===== THE SUNKEN CITY =====
	--
	-- The drowned city round the ring, the aquarium off a checkpoint, and the drain the route runs out
	-- to. Like the slide, the drain IS the ending, so the old finish line stands down once it is
	-- attached, and every way this can fail falls back to that finish line and says so.
	if sunkenTeardown then
		sunkenTeardown()
		sunkenTeardown = nil
	end
	if level.backdrop == "sunkenCity" then
		if not SunkenCityService then
			warn("Bootstrap: this level is The Sunken City, and there is no "
				.. "ServerScriptService.Services.SunkenCityService in this place -- so it is a bare ring of "
				.. "chunks finishing at the end of its route, with no city and no drain. Paste "
				.. "src/Server/Services/SunkenCityService.lua in as a ModuleScript named exactly SunkenCityService.")
		else
			local built: Model? = nil
			local cityOk, cityErr = pcall(function()
				built = SunkenCityService.build(levelInstance, workspace:WaitForChild("Levels"))
			end)
			if not cityOk then
				warn("Bootstrap: SunkenCityService.build failed, so this level is finishing at the end of its "
					.. "route instead: " .. tostring(cityErr))
			elseif built then
				local undo = SunkenCityService.attach(built :: Model, function(player: Player)
					if finishRunFor then
						finishRunFor(player)
					end
				end, function(player: Player)
					-- Taken by the surfacing: Hardcore only, which SunkenCityService checks before calling.
					if sendBackToStart then
						sendBackToStart(player)
					end
				end)
				if levelInstance.finishPart then
					levelInstance.finishPart.CanTouch = false
				end
				sunkenTeardown = function()
					if typeof(undo) == "function" then
						pcall(undo)
					end
				end
			end
		end
	end

	-- THE MODE COMES FROM THE PADS, and until now it did not come from anywhere.
	--
	-- The lobby has a chill pad and a hardcore pad and the player stands on one of them, but
	-- nothing carried that choice into PlayerStateService -- so the run used whatever mode the
	-- state was already holding. A player who picked Chill still got the hardcore
	-- back-to-the-start on their first fall, which is exactly how it was reported.
	local request = HubService.getRequest()
	for _, player in ipairs(players) do
		TimerService.init(player)
		if not PlayerStateService.getState(player) then
			PlayerStateService.init(player, levelInstance.startPosition)
		end
		PlayerStateService.beginRun(player, request.mode :: any)
		progression(player, "start")
		-- The mode the run ACTUALLY starts in, from the server, once per player. Two rounds
		-- were spent on "I am in chill and it sends me to the start" while the HUD was showing
		-- a mode the server had never agreed to; this line makes that unarguable next time.
		-- THE HUD IS TOLD THE RUN HAS STARTED. Nothing did this, so the timer and the best-times
		-- panel stayed hidden until something else happened to call syncTimer -- which in
		-- practice meant falling off, because the kill plane is the only other caller. Hence
		-- "I have to jump down to bring the menus out".
		syncTimer(player)
		print(("Bootstrap: %s starts %s in %s mode."):format(
			player.Name, tostring(request.levelId), tostring(request.mode)))
		-- THE READOUT ONLY EVER HEARD ABOUT MANUAL TOGGLES.
		--
		-- PlayerModeChanged is fired when someone presses the button, and mode stopped being
		-- set that way rounds ago -- it is a vote now. So a run that resolved to hardcore
		-- started, and the panel in the corner went on saying Chill because nothing had told
		-- it otherwise. The HUD was not wrong about a toggle; it had simply never been
		-- informed of the only thing that decides the mode.
		PlayerModeChanged:FireClient(player, request.mode)
		local character = player.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			hrp.CFrame = CFrame.new(levelInstance.startPosition)
		end
	end
	-- THE ROOM GOES AWAY. Without this the lobby, its parapet and its whole horizon stay in
	-- the workspace for the duration of the run, in the same coordinate space as the level.
	HubService.setVisible(false)
	HubService.markInRun(players)
	-- WHICH LEVEL EACH PLAYER IS IN, on the player, for their own client: its ambience
	-- (AmbienceService) and anything else that has to know. HubService.returnToHub clears it.
	for _, player in ipairs(players) do
		player:SetAttribute("InLevel", level.backdrop)
	end

	-- THE STORY'S PART, once the level and its people exist: the opening words on everyone's screen,
	-- and on City Shore, Sal's cart and Pip's sandcastle on the chunks.
	if StoryService then
		local built = levelInstance
		task.spawn(function()
			local ok, err = pcall(StoryService.stage, level, built, players)
			if not ok then
				warn("Bootstrap: StoryService.stage failed: " .. tostring(err))
			end
		end)
	end

	-- The chunks exist now, so their checkpoint triggers can be connected. Deferred by one
	-- frame so the models have finished parenting before anything looks for their parts.
	task.defer(function()
		wireCheckpointing(players)
	end)
	return levelInstance
end

-- ===== THE STORY =====
--
-- The four levels one after another (the lobby's Story pad, HubService.STORY_ID), each handing straight into the
-- next when its ending has been watched. In Hardcore one clock runs across them all: each level's own fair time,
-- added up, so a fall restarts only the level you are on. A story's time goes on its own leaderboard (STORY_ID) only
-- if it was played from City Shore in one go with every level's time counted. Where each player got to is kept in
-- their save (EconomyService.storyAt), so a story stopped partway goes on from there next time, from the level the
-- furthest-behind player in the room is on. A group plays it together: whoever finishes a level first waits in the
-- lobby until the rest are done, or for STORY_WAIT, after which the story goes on without whoever is still playing.
local STORY_WAIT = 150
local STORY_FADE = 0.6 -- seconds to black and back, either side of the move between a story's levels
local storyRun: any = nil
-- Story players being moved to the next level (storyNext): held, and passed over by the kill plane.
local storyMoving: { [Player]: boolean } = {}

-- THE LEVEL'S WORLD TAKEN DOWN, for the ender and for a story going on to its next level: the backdrop, the dive's
-- watch, the chunks and the rooms. Putting the lobby's own light back is the ender's, not this.
local function endLevelWorld()
	local standing = workspace:FindFirstChild("Backdrop")
	if standing then
		standing:Destroy()
	end
	-- The dive platform is a child of Levels and goes with it, but the loop watching for divers
	-- is not: left running it would be watching a level that no longer exists.
	if DiveFinaleService then
		pcall(DiveFinaleService.stop)
	end
	-- Hill House's ground is terrain, which the level's teardown would not take.
	if HillHouseService then
		pcall(HillHouseService.stop)
	end
	LevelService.endLevel()
	levelInstance = nil
	tearDownLevelWorld()
end

-- To one story player, on their vote card (HubVoteService.onStory).
local function tellStory(player: Player, what: string, extra: any?)
	HubVoteState:FireClient(player, "story", { what = what, extra = extra })
end

-- THE STORY'S LEVEL (run.index of LevelDefinitions.Story) for everyone still in it, at the length it was voted. Anyone
-- who wandered into the squish room meanwhile is left out of it; with nobody left, the story is over.
local function storyLevel(run: any, origin: Vector3?)
	local level = LevelDefinitions.Story[run.index]
	HubService.setLevel(level.levelId)
	local going = {}
	for player in pairs(run.players) do
		if player.Parent ~= Players then
			run.players[player] = nil
		elseif player:GetAttribute("InSquishRoom") then
			run.players[player] = nil
			tellStory(player, "behind")
		else
			table.insert(going, player)
		end
	end
	run.done = {}
	run.waiting = false
	if #going == 0 then
		storyRun = nil
		pcall(LightingService.apply, "lobby")
		return nil
	end
	print(("Bootstrap: the story goes on to %s (%d of %d) for %d player(s)."):format(
		tostring(level.name), run.index, #LevelDefinitions.Story, #going))
	return startChosenLevel(HubService.scaledLevel(level, run.length), going, origin or HubService.levelOrigin())
end

-- A STORY BEGUN FROM THE LOBBY, from the level the furthest-behind of its players got to (their saves), so nobody
-- misses one. Only one begun from City Shore can set a time.
local function startStory(players: { Player }, origin: Vector3)
	local from = #LevelDefinitions.Story
	for _, player in ipairs(players) do
		local at = 1
		if EconomyService and EconomyService.storyAt then
			local ok, saved = pcall(EconomyService.storyAt, player)
			if ok and type(saved) == "number" then
				at = saved
			end
		end
		from = math.min(from, at)
	end
	from = math.clamp(from, 1, #LevelDefinitions.Story)
	local run = { players = {}, done = {}, index = from, from = from, length = HubService.getRequest().length,
		total = {}, fair = {}, waiting = false }
	for _, player in ipairs(players) do
		run.players[player] = true
		run.total[player] = 0
		run.fair[player] = from == 1
		pcall(function()
			AnalyticsService:LogCustomEvent(player, "StoryStarted", from)
		end)
	end
	storyRun = run
	return storyLevel(run, origin)
end

-- ON TO THE NEXT LEVEL (the one just played taken down first), or, after the last, everyone home.
local function storyNext(run: any)
	-- Once at a time: someone leaving during the move must not start a second one.
	if storyRun ~= run or run.moving then
		return
	end
	if run.index >= #LevelDefinitions.Story then
		storyRun = nil
		for player in pairs(run.players) do
			if player.Parent == Players and HubService.isInRun(player) then
				HubService.returnToHub(player)
			end
		end
		return
	end
	run.index += 1
	-- THE MOVE BETWEEN LEVELS. The screen goes black and everyone in the story is held where they stand (anchored, and
	-- passed over by the kill plane: storyMoving) while the last level comes down and the next goes up; then they are at
	-- its start and the screen comes back. Without it they fell through the space the last level had left, and one who
	-- dropped past the new level's kill plane before being put on it took a Hardcore fall at its start.
	run.moving = true
	local held: { BasePart } = {}
	for player in pairs(run.players) do
		if player.Parent == Players then
			storyMoving[player] = true
			ScreenFade:FireClient(player, { black = true, time = STORY_FADE })
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				root.Anchored = true
				table.insert(held, root)
			end
		end
	end
	task.wait(STORY_FADE)
	endLevelWorld()
	local ok, err = pcall(storyLevel, run, nil)
	for _, root in ipairs(held) do
		root.Anchored = false
	end
	for player in pairs(storyMoving) do
		storyMoving[player] = nil
		if player.Parent == Players then
			ScreenFade:FireClient(player, { black = false, time = STORY_FADE })
		end
	end
	run.moving = false
	if not ok then
		warn("Bootstrap: the story's next level failed to start, so everyone goes back to the lobby: " .. tostring(err))
		storyRun = nil
		for player in pairs(run.players) do
			if player.Parent == Players and HubService.isInRun(player) then
				HubService.returnToHub(player)
			end
		end
		pcall(LightingService.apply, "lobby")
	end
end

-- STILL PLAYING the story's level: in the story, in the run, and not finished it.
local function storyPlaying(run: any, except: Player?): number
	local playing = 0
	for player in pairs(run.players) do
		if player ~= except and player.Parent == Players and not run.done[player] and HubService.isInRun(player) then
			playing += 1
		end
	end
	return playing
end

-- TIME UP (STORY_WAIT after the first finished this level): whoever is still playing it is taken out of the story and
-- back to the lobby, and the ones who finished go on.
local function storyTimeUp(run: any, index: number)
	if storyRun ~= run or run.index ~= index then
		return
	end
	for player in pairs(run.players) do
		if player.Parent == Players and not run.done[player] and HubService.isInRun(player) then
			run.players[player] = nil
			progression(player, "fail")
			TimerService.resetTimer(player)
			syncTimer(player)
			HubService.returnToHub(player)
			tellStory(player, "behind")
		end
	end
	if next(run.players) ~= nil then
		storyNext(run)
	else
		storyRun = nil
	end
end

-- A STORY PLAYER HAS WATCHED THEIR LEVEL'S ENDING (completeRun): the next level at once if nobody else is still
-- playing this one; otherwise the lobby, to wait for them.
local function storyStep(player: Player)
	local run = storyRun
	if not (run and run.players[player]) then
		HubService.returnToHub(player)
		return
	end
	run.done[player] = true
	local playing = storyPlaying(run, player)
	if playing == 0 then
		storyNext(run)
		return
	end
	HubService.returnToHub(player)
	tellStory(player, "waiting", { playing = playing, level = LevelDefinitions.Story[run.index].name })
	if not run.waiting then
		run.waiting = true
		local index = run.index
		task.delay(STORY_WAIT, function()
			storyTimeUp(run, index)
		end)
	end
end

-- OUT OF THE STORY (left it from the menu, or left the server): if that leaves nobody still playing its level, the
-- ones waiting in the lobby go on; if nobody at all, the story is over.
local function storyLeave(player: Player)
	local run = storyRun
	if not (run and run.players[player]) then
		return
	end
	run.players[player] = nil
	run.done[player] = nil
	if storyPlaying(run, player) > 0 then
		return
	end
	local waiting = false
	for other in pairs(run.players) do
		if other ~= player and other.Parent == Players and run.done[other] then
			waiting = true
		end
	end
	if waiting then
		storyNext(run)
	else
		storyRun = nil
	end
end

-- THE LOBBY'S RUNNER: the story, or one level.
local function startFromLobby(level, players: { Player }, origin: Vector3)
	if level.story then
		return startStory(players, origin)
	end
	storyRun = nil
	return startChosenLevel(level, players, origin)
end

HubService.setRunner(startFromLobby)
HubService.setBoardReader(LeaderboardService.getTop)
HubService.setBestReader(BestTimeService.get)
HubService.setBoardNotifier(function(player: Player, mode: string)
	HubBoardMode:FireClient(player, mode)
end)

HubService.setModeNotifier(function(player: Player, mode: string)
	PlayerModeChanged:FireClient(player, mode)
end)

HubService.setAnnouncer(function(kind: string, payload: any)
	-- NOT FireAllClients. The vote banner was reaching everyone including players mid-run,
	-- who cannot vote, cannot see the pads, and were being told about a ballot they are not
	-- in -- which is the "confusing intervention" it was reported as.
	for _, player in ipairs(HubService.hubPlayers()) do
		HubVoteState:FireClient(player, kind, payload)
	end
end)

-- LEVELS OPEN IN ORDER (HubService.isOpen), from what each player's save says they have finished
-- (EconomyService). Without the shop's server side nothing is locked.
if EconomyService and EconomyService.finishedLevels and EconomyService.setLevelsChanged then
	HubService.setFinishedReader(EconomyService.finishedLevels)
	EconomyService.setLevelsChanged(HubService.refreshLocks)
	-- And back the other way, for the Self-test to see the lobby open and lock a level.
	if EconomyService.setOpenReader then
		EconomyService.setOpenReader(HubService.isOpen)
	end
	-- An admin's /levels, said on their own vote card.
	if EconomyService.setAdminNotifier then
		EconomyService.setAdminNotifier(function(player: Player, on: boolean)
			HubVoteState:FireClient(player, "admin", { on = on })
		end)
	end
end
-- THE DAILY CHEST in the lobby (HubService.setDailyChest): EconomyService.claimDaily decides, and the player's own
-- vote card says what happened (HubVoteService.onDaily); its tokens come with the usual "+N tokens".
if HubService.setDailyChest and EconomyService and EconomyService.claimDaily then
	HubService.setDailyChest(function(player: Player)
		local result = EconomyService.claimDaily(player)
		HubVoteState:FireClient(player, "daily", result)
	end)
end
-- To one player alone, on the banner: a locked pad stepped on ("locked": which level and what opens it), and coming
-- back from a run that opened a level ("opened": which).
HubService.setLockNotifier(function(player: Player, kind: string, payload: any)
	HubVoteState:FireClient(player, kind, payload)
end)

-- THE CLIENT ASKS, THE SERVER DECIDES, and it decides only about the player who asked.
--
-- FireServer carries no argument on purpose. A client that could name the mode could name
-- anything; a client that can only say "flip mine" cannot say anything wrong. Debounced here
-- as well as in the room's own ClickDetector, because this is a remote and remotes are the
-- ones that get spammed -- every flip is a DataStore read.
local toggling: { [Player]: boolean } = {}
HubBoardToggle.OnServerEvent:Connect(function(player: Player)
	if toggling[player] then
		return
	end
	toggling[player] = true
	HubService.toggleBoardMode(player)
	task.delay(0.4, function()
		toggling[player] = nil
	end)
end)

-- Tearing down is the hub's to trigger and LevelService's to do, so the hub gets a function
-- rather than a dependency on LevelService. Clearing levelInstance here is what makes the
-- next spawn go to the room instead of to a level that no longer exists.
-- THE BACKDROP IS PART OF THE RUN, so it leaves with the run.
--
-- Leaving to the lobby cleared the chunks and left City Shore's horizon standing: towers, sea
-- and all, wrapped around a room that is nowhere near them. Moving the hub further away was
-- the obvious answer and the wrong one -- that backdrop reaches 6200 studs, so escaping it
-- means teleporting the lobby further than the whole world is wide.
--
-- Destroying it is both correct and cheaper. It is rebuilt from scratch on the next run that
-- wants one, which is already how it works.
-- THE BACKDROP IS PART OF THE RUN, so it leaves with the run.
--
-- Leaving to the lobby cleared the chunks and left City Shore's horizon standing: towers, sea
-- and all, wrapped around a room that is nowhere near them. Moving the hub further away was
-- the obvious answer and the wrong one -- that backdrop reaches 6200 studs, so escaping it
-- means teleporting the lobby further than the whole world is wide.
--
-- Destroying it is both correct and cheaper. It is rebuilt from scratch on the next run that
-- wants one, which is already how it works.
HubService.setEnder(function()
	endLevelWorld()
	-- AND THE ROOM GETS ITS AIR BACK, however the run ended. This used to happen only when the last
	-- runner FINISHED, so leaving from the pause menu, or the last runner leaving the server, left the
	-- level's sky over the lobby until the next run, and its world standing.
	pcall(LightingService.apply, "lobby")
end)

-- WRAPPED, AND THIS IS THE BUG THAT CAUSED THE INFINITE FALLING.
--
-- Bootstrap is one long Script. An error at any top-level line stops every line BELOW it
-- from ever running, and the kill plane is connected 280 lines further down -- so a throw in
-- here left a half-built room with no kill plane, no finish wiring and no leave handler. The
-- symptom was falling forever off a lobby pad, which looks nothing like "the room failed to
-- build", and that is exactly why it has to be guarded rather than trusted.
--
-- The fallback position is deliberately not nil: something has to be a valid place to stand
-- even when the room did not finish.
local buildOk, hubResult = pcall(HubService.build)
if not buildOk then
	warn("Bootstrap: the hub failed to build, so the lobby may be incomplete. Everything "
		.. "below still runs, including the kill plane: " .. tostring(hubResult))
end
local hub = if buildOk then hubResult else { spawnPosition = Vector3.new(0, 204, -588) }

-- THE SQUISH ROOM: a hall with a real slab of every material, reached by a lift in the lobby. Optional,
-- required in a pcall and built on its own thread (it waits for ChunkBuilder's templates): a place
-- without it plays exactly as before.
do
	local squishModule = Services:FindFirstChild("SquishRoomService")
	if squishModule and squishModule:IsA("ModuleScript") then
		task.spawn(function()
			local ok, err = pcall(function()
				(require(squishModule) :: any).build(HubService.origin())
			end)
			if not ok then
				warn("Bootstrap: the squish room failed to build: " .. tostring(err))
			end
		end)
	end
end

-- JOINING A RUN THAT IS ALREADY ON. While the lobby is away (from a run's start until its first runner is
-- back) there is nowhere to stand but the level, so someone joining the server then is put on it, and is
-- one of its runners: counted in (so it is not torn down under them), playing it in its mode, on its clock,
-- and paid for finishing it like everyone else.
local function joinRunLate(player: Player)
	local instance = levelInstance
	if not instance or HubService.isInRun(player) then
		return
	end
	local request = HubService.getRequest()
	TimerService.init(player)
	if not PlayerStateService.getState(player) then
		PlayerStateService.init(player, instance.startPosition)
	end
	PlayerStateService.beginRun(player, request.mode :: any)
	HubService.markInRun({ player })
	progression(player, "start")
	if runBackdrop then
		player:SetAttribute("InLevel", runBackdrop)
	end
	if EconomyService then
		pcall(EconomyService.runStarted, { player }, runLength, true)
		tellRunFriends()
	end
	syncTimer(player)
	PlayerModeChanged:FireClient(player, request.mode)
	-- IN A STORY, carried along with it from here (no story time: they did not start it).
	if storyRun then
		storyRun.players[player] = true
		storyRun.total[player] = 0
		storyRun.fair[player] = false
	end
	print(("Bootstrap: %s joins the run late, in %s mode."):format(player.Name, tostring(request.mode)))
end

local function wirePlayer(player: Player)
	local function onCharacter(character: Model)
		local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart
		-- NO WAITING LOOP ANY MORE. This used to spin for up to ten seconds because the
		-- level was still generating when the first character spawned. The hub is built
		-- before any player is wired and never goes away, so there is always somewhere to
		-- put someone.
		-- WHERE: the level for its runners, and for anyone at all while the lobby is away (the squish room
		-- takes its own back from there); the room for everyone else. It was the level for anyone at all
		-- while a run was on, so a player who had finished and was back in the lobby, and reset, was put
		-- back on a level they were no longer in.
		local inRunNow = levelInstance ~= nil and HubService.isInRun(player)
		-- A NEW CHARACTER is never in the back rooms (Reset there puts you on the level, or in the lobby).
		if player:GetAttribute("InLevel") == "backRooms" then
			player:SetAttribute("InLevel", if inRunNow then runBackdrop else nil)
		end
		local lobbyAway = workspace:FindFirstChild("Hub") == nil
		local target = if levelInstance and (inRunNow or lobbyAway) then levelInstance.startPosition else hub.spawnPosition
		hrp.CFrame = CFrame.new(target)
		if not PlayerStateService.getState(player) then
			PlayerStateService.init(player, target)
			TimerService.init(player)
		end
		if levelInstance and not inRunNow and lobbyAway and not player:GetAttribute("InSquishRoom") then
			joinRunLate(player)
		end
	end

	-- THE LEADERBOARD IS DRAWN INTO THIS PLAYER'S OWN PlayerGui, so it needs one to exist.
	-- PlayerGui is not there the instant PlayerAdded fires, and waiting for it here would
	-- block everything below, so it waits on its own thread.
	task.spawn(function()
		if player:WaitForChild("PlayerGui", 20) then
			local ok, err = pcall(HubService.attachBoard, player)
			if not ok then
				warn("Bootstrap: the leaderboard view failed to attach: " .. tostring(err))
			end
		end
	end)

	-- Cosmetic and DataStore-backed, so it must never be able to stop a player being wired.
	task.spawn(function()
		local ok, err = pcall(HubService.buildStatue, player, BestTimeService.get)
		if not ok then
			warn("Bootstrap: building the statue failed, continuing without it: " .. tostring(err))
		end
	end)

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
end

-- PlayerAdded does NOT fire for players who already exist when this script
-- runs, which in Studio Play Solo is always the local player. Without this
-- loop the CharacterAdded hook is never connected for them and they stay on
-- the baseplate instead of being placed on the level.
for _, player in ipairs(Players:GetPlayers()) do
	wirePlayer(player)
end
Players.PlayerAdded:Connect(wirePlayer)

-- ===== STUDIO ONLY: NEAR THE END =====
--
-- The test panel's "Near the end" puts you at a checkpoint about eight chunks before the finish of the run you are
-- in, to see a level's last stretch and its ending without playing all of it: the storm building by the Sky Pools
-- slide, the lamps failing behind you in the halls, every level's ending. A run skipped like this counts for
-- nothing (walkedRoute refuses it: no tokens, no time, no level opened), so a test cannot fake its way into a save.
if game:GetService("RunService"):IsStudio() then
	local dev = remoteEventsFolder:FindFirstChild("DevPanel")
	if dev and dev:IsA("RemoteEvent") then
		local definitions = require(ReplicatedStorage.Shared.ChunkDefinitions)
		dev.OnServerEvent:Connect(function(player: Player, action: any)
			if action ~= "nearEnd" then
				return
			end
			local state = PlayerStateService.getState(player)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not (levelInstance and HubService.isInRun(player) and state and not state.hasCompletedLevel
				and root and root:IsA("BasePart")) then
				warn("Bootstrap: Near the end is for a run you are in; start one first.")
				return
			end
			local chunks = levelInstance.placedChunks
			local last = math.max(#chunks - 8, 2)
			local target: any = nil
			for _, entry in ipairs(chunks) do
				local def = definitions[entry.chunkId]
				if def and def.category == "stable" and entry.index <= last and entry.model.PrimaryPart
					and (target == nil or entry.index > target.index) then
					target = entry
				end
			end
			if not target then
				warn("Bootstrap: this run has no checkpoint before its last stretch to put you at.")
				return
			end
			local primary = target.model.PrimaryPart :: BasePart
			local at = Vector3.new(primary.Position.X, target.surfaceY + 3, primary.Position.Z)
			local tangent = target.tangent
				or Vector3.new(-math.sin(target.startAngle), 0, math.cos(target.startAngle))
			state.skipped = true
			PlayerStateService.setCheckpoint(player, at, target.index, -tangent)
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = CFrame.lookAt(at + Vector3.new(0, 2, 0), at + Vector3.new(0, 2, 0) + tangent)
			print(("Bootstrap: %s put near the end (checkpoint %d of %d chunks); this run counts for nothing.")
				:format(player.Name, target.index, #chunks))
		end)
	end
end

Players.PlayerRemoving:Connect(function(player: Player)
	-- LEFT THE SERVER PARTWAY THROUGH A RUN: a run left, for the dashboard.
	if runningFor[player] then
		progression(player, "fail")
	end
	PlayerStateService.cleanup(player)
	TimerService.cleanup(player)
	-- The GUI goes with the PlayerGui, but the mode and the label reference are held in a
	-- table keyed by Player, and a table keyed by a leaving Player is a leak.
	HubService.detachBoard(player)
	HubService.clearBallot(player)
	-- Their statue goes with them (an older HubService has no removeStatue: nothing to do).
	if HubService.removeStatue then
		pcall(HubService.removeStatue, player)
	end
	toggling[player] = nil
	secondChance.falls[player] = nil
	-- OUT OF THE STORY too (storyLeave): the hub has already had them back, so the rest may go on.
	storyLeave(player)
	storyMoving[player] = nil
	-- A countdown started by someone who then left must not fire a run into an empty lobby.
	-- PlayerRemoving fires before the player is gone from GetPlayers, hence the 1.
	if #Players:GetPlayers() <= 1 and HubService.isVoting() then
		HubService.cancelVote()
	end
end)

-- LEAVING IS EXPLICIT AND SERVER-CHECKED. The client asks; the server decides. A client that
-- fired this while already in the hub would otherwise teleport itself to the hub spawn from
-- wherever it liked, which is a free teleport anywhere in the room.
-- ANOTHER GO, from the death card. The restart has already happened by the time this can be
-- pressed -- hardcore puts you back at the start immediately, which is the mode -- so all this
-- has to do is put the clock back to zero and let the start line arm again.
--
-- It carries no arguments for the same reason every other remote here does not: a client that
-- can only say "again" cannot say anything wrong.
HardcoreRetry.OnServerEvent:Connect(function(player: Player)
	-- ONLY FROM THE START, which is where a hardcore fall has just put you. Anywhere else this stopped the
	-- clock mid-run, and the next checkpoint started it again from nothing: fired just before the last
	-- one, a few seconds became a "best" and a place on the leaderboard.
	if not HubService.isInRun(player) or not PlayerStateService.canToggleMode(player) then
		return
	end
	TimerService.resetTimer(player)
	syncTimer(player)
end)

-- THE BACK ROOMS' WAY OUT, filled in once it is made (below): "Leave to the lobby" from down there, with no run to
-- leave (you came through the lobby's corridor), is that way out. It did nothing at all.
local backRoomsLeave: ((Player) -> ())? = nil
LeaveLevel.OnServerEvent:Connect(function(player: Player)
	if player:GetAttribute("InLevel") == "backRooms" and not (levelInstance and HubService.isInRun(player)) then
		local leave = backRoomsLeave
		if leave then
			pcall(leave, player)
		end
		return
	end
	-- ONLY A RUNNER LEAVES A RUN. It was anyone while any run was on: someone in the squish room pressing
	-- "Leave to the lobby" was put in the lobby still marked as in the squish room (and so left out of every
	-- vote after), and the lobby was brought back into the world in the middle of the run.
	if levelInstance and HubService.isInRun(player) then
		progression(player, "fail")
		-- THE CLOCK STOPS WITH THE RUN. Leaving to the lobby left it ticking, so the hub showed a
	-- hardcore time counting up for a run that had ended -- and the next run inherited it.
	TimerService.resetTimer(player)
	syncTimer(player)
	HubService.returnToHub(player)
	-- AND OUT OF THE STORY (storyLeave), so whoever is waiting in the lobby can go on.
	storyLeave(player)
	end
end)

-- ===== Mode switching =====

RequestLeaderboardData.OnServerInvoke = function(player: Player)
	-- THE LEVEL ID COMES FROM THE SERVER, not from the caller.
	--
	-- It used to be a client argument, which made the remote unusable by the only thing
	-- that wants it: the HUD has no idea which level id it is standing in, so it could
	-- only ever have passed nil. There is one current level, the server knows which, and
	-- taking it from the caller was also a free way to read any level's board.
	-- FALLS BACK TO LEVEL 1 WHEN NO RUN EXISTS. This is called from the hub too, where
	-- levelInstance is nil -- and a board showing nothing at all reads as broken, where a
	-- board showing Level 1 reads as the default it is.
	-- THE CALLER'S OWN MODE, read on the server. A client that could name the mode could
	-- read the hardcore board while playing chill, which is harmless, and could also be
	-- handed a mode this game does not have, which is a DataStore key it invented.
	local requesterState = PlayerStateService.getState(player)
	local requesterMode = if requesterState then requesterState.mode else "hardcore"
	return LeaderboardService.getTop(
		if levelInstance then levelInstance.levelId else 1, requesterMode, 100)
end

-- ONE PAYLOAD, TWO WAYS OUT. syncTimer pushes it, RequestRunState hands the same thing back
-- to a client that asks. Built in one place so the two can never drift apart -- a pull that
-- reports a different mode from the push would be worse than having no pull at all.
local function runState(player: Player)
	local state = PlayerStateService.getState(player)
	return {
		mode = state and state.mode or "chill",
		running = TimerService.isRunning(player),
		elapsed = TimerService.getElapsed(player),
	}
end

function syncTimer(player: Player)
	HardcoreTimerSync:FireClient(player, runState(player))
end

RequestRunState.OnServerInvoke = function(player: Player)
	return runState(player)
end

-- THE SAME RULE THE SETTER USES.
--
-- This asked PlayerStateService.canToggleMode, which tests isAtStart, while the actual setter
-- refuses whenever HubService says you are in a run. Two different questions with two
-- different answers: the client asked the permissive one, got a yes, changed its own display,
-- fired the request, and the server then refused it -- so the warning appeared AND the HUD
-- moved, which is exactly the contradiction that got reported.
--
-- Being in a run is the first and strongest test, asked here in the same words the setter uses.
CanToggleMode.OnServerInvoke = function(player: Player)
	if HubService.isInRun(player) then
		return false
	end
	return PlayerStateService.canToggleMode(player)
end

PlayerModeChanged.OnServerEvent:Connect(function(player: Player, mode: string)
	if mode ~= "chill" and mode ~= "hardcore" then
		return
	end
	-- NOT WHILE YOU ARE RUNNING. The mode is a lobby decision now -- there is a pad for it --
	-- and a run whose rules can change halfway through has no rules. This was reachable
	-- because isAtStart stays true for the whole of chunk 1, so the toggle was legal for as
	-- long as you stood on the first platform.
	if HubService.isInRun(player) then
		ModeToggleBlocked:FireClient(player)
		return
	end
	local ok = PlayerStateService.setMode(player, mode)
	if not ok then
		ModeToggleBlocked:FireClient(player)
		return
	end
	-- THE SERVER SAYS WHAT THE MODE IS, and the client waits to be told.
	--
	-- Nothing sent a confirmation before, so the client had no choice but to guess -- it set
	-- its own display the moment you pressed the button and hoped. When the server disagreed,
	-- the two silently diverged and the HUD said Chill through an entire hardcore run.
	PlayerModeChanged:FireClient(player, mode)
	TimerService.resetTimer(player)
	-- So the HUD switches its clock and leaderboard over at the moment the mode does,
	-- rather than at the next checkpoint.
	syncTimer(player)
end)

-- ===== Checkpoint crossing -> hardcore timer start =====
-- Chunk-index crossing is detected by watching each placed chunk's
-- finish-adjacent stable-chunk marker; simplified here via touch parts
-- placed at each stable chunk boundary (index in placedChunks).

function wireCheckpointing(players: { Player })
	if not levelInstance then
		return
	end
	-- THE START LINE IS CHUNK TWO, whatever chunk two happens to be.
	--
	-- The clock used to start on a CHECKPOINT trigger, and checkpoints only exist on chunks
	-- whose category is "stable" -- so on a spiral that opens with honey, the first stable slab
	-- is several platforms in and the opening stretch of every hardcore run went untimed. That
	-- was reported as "the timer only starts when I cross the honey", which is exactly what the
	-- code says if you read it for what it does rather than what it is called.
	--
	-- A run starts when you leave the platform you spawned on. That is chunk two, and it has
	-- nothing to do with what chunk two is made of.
	for _, entry in ipairs(levelInstance.placedChunks) do
		local model = entry.model
		local primary = model.PrimaryPart
		if not primary then
			continue
		end

		-- EVERY PART OF CHUNK TWO, not just its cap.
		--
		-- This wired Touched onto `SurfaceCap or primary`, and only STABLE chunks have a
		-- SurfaceCap. On every other chunk the thing you actually stand on is a SubRegion
		-- collider, several parts up from the slab -- so `primary` was never touched, the
		-- start line never fired, and the clock waited for the next stable chunk to start it
		-- through the checkpoint path below. That is exactly "it only starts on the 2nd safe
		-- chunk": the safe chunk was the only one whose trigger could be reached.
		--
		-- Connecting to all of them costs one extra connection per part on ONE chunk, and it
		-- stops caring what chunk two is made of -- which is the whole point of a start line
		-- that is defined by position in the run rather than by material.
		if entry.index == 2 then
			local function crossed(hit: BasePart)
				local character = hit:FindFirstAncestorOfClass("Model")
				local player = character and Players:GetPlayerFromCharacter(character)
				if not player or TimerService.isRunning(player) then
					return
				end
				local state = PlayerStateService.getState(player)
				if state and state.mode == "hardcore" then
					TimerService.startTimer(player)
					syncTimer(player)
				end
			end
			for _, item in ipairs(model:GetDescendants()) do
				if item:IsA("BasePart") then
					item.CanTouch = true
					item.Touched:Connect(crossed)
				end
			end
			-- The slab itself may have no descendants worth touching on some recipes, so the
			-- primary is wired regardless rather than only when the loop found nothing -- a
			-- duplicate is harmless here because the handler exits the moment the clock runs.
			primary.CanTouch = true
			primary.Touched:Connect(crossed)
		end
		-- Any BasePart within a stable chunk acts as a checkpoint trigger
		-- for players who cross onto it.
		local def = require(ReplicatedStorage.Shared.ChunkDefinitions)[entry.chunkId]
		if def and def.category == "stable" then
			-- Stable slabs are capped by a SurfaceCap plate, which is what the
			-- player actually stands on. Touching the slab itself no longer
			-- happens, so the checkpoint trigger has to live on the cap.
			local cap = primary:FindFirstChild("SurfaceCap")
			local trigger: BasePart = (cap and cap:IsA("BasePart")) and cap or primary
			trigger.CanTouch = true

			-- Checkpoint sits on the chunk's actual walkable surface, which the
			-- generator recorded per chunk. Deriving it from the slab centre
			-- would drift by the slab/cap thickness and by the elevation step.
			local checkpointPos = Vector3.new(primary.Position.X, entry.surfaceY + 3, primary.Position.Z)

			-- WHICH WAY IS BACKWARDS HERE. On a straight level this was world -Z and
			-- nobody had to think about it. The route is a HELIX now, so "back down the
			-- track" is a different direction at every chunk -- it is the reverse of the
			-- tangent to the circle at this chunk's own angle. Recovering along world -Z
			-- instead pushes you sideways off the route almost everywhere, which is not a
			-- cosmetic error: you land in open air, fall, get recovered to the same bad
			-- spot, and fall again until something else kills you.
			-- STORED BY THE PLACER NOW. Rebuilding it from startAngle is only correct on the
			-- spiral, where that number is radians; on the indoor route it is studs travelled
			-- and sin() of it is noise. The fallback keeps old level instances working.
			local tangent = entry.tangent
				or Vector3.new(-math.sin(entry.startAngle), 0, math.cos(entry.startAngle))
			local backward = -tangent

			trigger.Touched:Connect(function(hit: BasePart)
				local character = hit:FindFirstAncestorOfClass("Model")
				local player = character and Players:GetPlayerFromCharacter(character)
				if not player then
					return
				end
				PlayerStateService.setCheckpoint(player, checkpointPos, entry.index, backward)
				-- CHUNK 2, not chunk 1, and it matches PlayerStateService.setCheckpoint
				-- on purpose. Chunk 1 is the spawn chunk, so starting here began the
				-- clock before the player had moved -- and worse, switching to hardcore
				-- calls resetTimer, so a player who switched at the start stopped a clock
				-- that then had no trigger left to restart it until the NEXT stable
				-- chunk. The first stretch of every hardcore run went untimed.
				if entry.index >= 2 and not TimerService.isRunning(player) then
					local state = PlayerStateService.getState(player)
					if state and state.mode == "hardcore" and state.checkpointChunkIndex >= 2 then
						TimerService.startTimer(player)
						syncTimer(player)
					end
				end
			end)
		end
	end

	-- ===== FINISHING =====
	--
	-- One function, two ways in: walking over the trigger, which is every level, and stepping
	-- off the end of the flume, which is the flooded halls. A second copy of these rules for
	-- the second entry point would be a second place for best times, hardcore clocks and the
	-- return to the hub to drift apart.
	local function completeRun(player: Player)
		local state = PlayerStateService.getState(player)
		if not state or state.hasCompletedLevel then
			return
		end
		PlayerStateService.markCompleted(player)
		progression(player, "complete")

		-- RECORDED IN BOTH MODES, unlike the leaderboard. This is the player's own record
		-- rather than a ranking, so a chill run is worth keeping -- and the two modes are
		-- stored under separate keys rather than compared.
		-- Read BEFORE the hardcore branch stops the clock, so both modes record the same
		-- number for the same run.
		-- A RUN CONTINUED WITH A SECOND CHANCE (bought) is not a best and not on the leaderboard:
		-- a place on it can never be bought. It still pays its tokens.
		local usedChance = state.usedChance == true
		-- AND ONLY A FAIR TIME (fairTime): the clock ran, the route was walked, and not impossibly fast.
		local counted = not usedChance and fairTime(player, state)
		-- AND TOKENS ONLY FOR A ROUTE WALKED: waiting out the minimum and jumping to the finish pays nothing.
		local walked = walkedRoute(player, state)
		local newBest = if counted then BestTimeService.submit(player, levelInstance.levelId, state.mode,
			TimerService.getElapsed(player)) else false
		-- THE STORY (storyRun): this level's time added to the story's own (a fall restarts only this level, so it is
		-- each level's own fair time that counts), and where they got to kept in their save (a route walked).
		local story = storyRun
		local storyInfo: any = nil
		if story and story.players[player] then
			local of = #LevelDefinitions.Story
			local last = story.index >= of
			-- WHERE THEIR OWN WALKING HAD GOT TO before this level (their save): the story's reward is for someone who
			-- reached its last level themselves, not for someone who joined it there late.
			local reached = 0
			if EconomyService and EconomyService.storyAt then
				local ok, at = pcall(EconomyService.storyAt, player)
				reached = if ok and type(at) == "number" then at else 0
			end
			if state.mode == "hardcore" and counted then
				story.total[player] = (story.total[player] or 0) + TimerService.getElapsed(player)
			else
				story.fair[player] = false
			end
			if walked and EconomyService and EconomyService.setStoryAt then
				pcall(EconomyService.setStoryAt, player, if last then 1 else story.index + 1)
			end
			local fair = story.fair[player] == true and state.mode == "hardcore"
			storyInfo = {
				step = story.index,
				of = of,
				next = if last then nil else LevelDefinitions.Story[story.index + 1].name,
				total = if last and fair then story.total[player] else nil,
			}
			if last then
				pcall(function()
					AnalyticsService:LogCustomEvent(player, "StoryFinished", if fair then 1 else 0)
				end)
				-- THE STORY'S REWARD (EconomyService.finishStory): its bonus, and the green ribbon the first time.
				if walked and reached >= of and EconomyService and EconomyService.finishStory then
					local hardcoreStory = state.mode == "hardcore"
					task.spawn(function()
						pcall(EconomyService.finishStory, player, hardcoreStory)
					end)
				end
				-- THE STORY'S BADGES (EconomyService.awardStoryBadges): played to its end on foot, and a whole one in Hardcore.
				if walked and EconomyService and EconomyService.awardStoryBadges then
					pcall(EconomyService.awardStoryBadges, player, fair)
				end
				-- THE STORY'S OWN LEADERBOARD and best: a whole story, from City Shore, every level's time counted.
				if fair then
					local total = story.total[player]
					task.spawn(function()
						pcall(LeaderboardService.submitTime, player, HubService.STORY_ID, "hardcore", total)
						pcall(BestTimeService.submit, player, HubService.STORY_ID, "hardcore", total)
					end)
				end
			end
		end
		-- THE TOKENS for this run (EconomyService checks it saw the run start and that it took as long as
		-- a run takes). A new best counts only in hardcore, the one mode with a clock.
		if EconomyService and walked then
			local hardcore = state.mode == "hardcore"
			-- The level, so it is kept as finished and the next one opens in the lobby.
			local finishedId = levelInstance.levelId
			task.spawn(function()
				local ok, err = pcall(EconomyService.runFinished, player, hardcore, hardcore and newBest == true, finishedId)
				if not ok then
					warn("Bootstrap: paying tokens for a run failed: " .. tostring(err))
				end
			end)
		end

		if state.mode == "hardcore" then
			local elapsed = TimerService.stopTimer(player)
			if counted then
				LeaderboardService.submitTime(player, levelInstance.levelId, state.mode, elapsed)
			end
			syncTimer(player)
			LevelCompleted:FireClient(player, { levelId = levelInstance.levelId, time = elapsed, story = storyInfo })
		else
			LevelCompleted:FireClient(player, { levelId = levelInstance.levelId, story = storyInfo })
		end

		-- BACK TO THE ROOM, after the client has had the completion event.
		--
		-- The delay is the panel's own read time. Teleporting on the same frame would replace
		-- the result with a lobby before anyone had seen what they scored, which is the one
		-- moment the whole run was for. Six seconds: long enough to stand in the last room with
		-- LEVEL COMPLETE up and look round it before the lobby comes back.
		--
		-- AND NOT BEFORE THE ENDING HAS BEEN WATCHED. Every level ends in a scene, and the six seconds
		-- used to start the moment the run counted as finished, which on City Shore is the splash:
		-- the lobby took you away in the middle of the last caption. The six now start when the
		-- scene says it is done (SceneState), or after SCENE_WAIT whatever it says.
		task.spawn(function()
			local waited = 0
			while sceneState[player] == "began" and waited < SCENE_WAIT and player.Parent do
				task.wait(0.25)
				waited += 0.25
			end
			sceneState[player] = nil
			task.wait(6)
			-- A STORY GOES ON (storyStep): to its next level, to the lobby to wait for the rest, or home after the last.
			local going = storyRun
			if going and going.players[player] and player.Parent then
				storyStep(player)
				return
			end
			if player.Parent then
				HubService.returnToHub(player)
			end
			-- AND THE ROOM GETS ITS AIR BACK, once nobody is left out on the level. Lighting is
			-- one setting for the whole server, so this waits for the LAST runner: re-lighting on
			-- the first would drop the lobby's sky over everyone still climbing.
			-- STILL OUT ON THE LEVEL: a runner the hub has not had back (HubService.isInRun). It asked
			-- whether anyone at all had not finished, which counted everyone in the squish room, everyone
			-- who had left the run, and everyone who had joined the server and never run, so the lobby
			-- kept the level's sky.
			local running = false
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player and HubService.isInRun(other) then
					running = true
					break
				end
			end
			if not running then
				-- THE LEVEL'S WORLD GOES WITH ITS AIR. Same condition, same moment: the last
				-- runner is home, so the room gets its light back and the level stops existing.
				tearDownLevelWorld()
				pcall(LightingService.apply, "lobby")
			end
		end)
	end

	finishRunFor = completeRun

	if levelInstance.finishPart then
		levelInstance.finishPart.Touched:Connect(function(hit: BasePart)
			-- NOT WHILE THE DIVE OWNS THE ENDING. Disarming the trigger's CanTouch was the only
			-- thing stopping it, and a run was reported completing on arrival at the deck, before
			-- the board -- which is exactly this trigger firing. The dive's watch keeps CanTouch
			-- off as well; this is the guarantee that does not depend on it.
			if DiveFinaleService and DiveFinaleService.isArmed() then
				return
			end
			local character = hit:FindFirstAncestorOfClass("Model")
			local player = character and Players:GetPlayerFromCharacter(character)
			if player then
				completeRun(player)
			end
		end)
	end
end

-- WIRED WHEN A LEVEL EXISTS, not at server start.
--
-- This ran once, deferred, at boot -- and at boot there is no level, only the lobby. The first
-- line of wireCheckpointing is `if not levelInstance then return end`, so it returned
-- immediately and NOTHING was ever wired. Not once, for any run.
--
-- Two reported bugs fall out of that single line:
--
--   * the hardcore clock never started, because the trigger that starts it is one of the
--     checkpoint triggers that were never created;
--   * chill recovery always returned you to the start of the level, because a checkpoint is
--     only recorded when you cross one -- so checkpointPosition stayed at its initial value,
--     which IS the start position.
--
-- Neither is a bug in the timer or in the recovery. Both are the same missing call.
task.defer(function()
	wireCheckpointing(Players:GetPlayers())
end)

-- ===== Hardcore restart =====
--
-- RESTARTING IS ONE PLAYER'S EVENT, NOT THE SERVER'S. The first version rebuilt the level:
-- ChunkService.clearLevel followed by LevelService.startLevel, then every player reset and
-- teleported. It restored the run correctly and was wrong about everything else -- the
-- geometry other people were standing on was destroyed under them, they were flung to the
-- start of a level they had not failed, and their own kill planes then fired, which in
-- hardcore restarted the level again.
--
-- What actually has to be undone splits cleanly in two:
--
--   PER PLAYER -- the clock, the checkpoint, the position. Only the player who fell.
--
--   SHARED -- the damage. Soap that dissolved, sand that crumbled, bubble wrap that
--   collapsed. There is one set of parts and no way to show two versions of it without
--   building two levels, so this cannot be per-player. But it does not need to be
--   disruptive either: DeformationService.restoreAll puts the surfaces back IN PLACE,
--   without destroying anything, so a bystander gets their floor back rather than losing
--   the ground beneath them. That is the whole difference between the two approaches.
--
-- Rebuilding is still what a fresh level needs; it is just not what a failed run needs.
local restarting = false

-- A HARDCORE FALL, noted before it is undone: the checkpoint and the clock, if there was progress to
-- go back to (past the first stretch). Nothing for chill, which never sends you to the start.
local function noteFall(player: Player)
	local state = PlayerStateService.getState(player)
	if not state or state.mode ~= "hardcore" or state.checkpointChunkIndex < 2 then
		secondChance.falls[player] = nil
		return
	end
	secondChance.falls[player] = {
		at = os.clock(),
		position = state.checkpointPosition,
		backward = state.checkpointBackward,
		chunk = state.checkpointChunkIndex,
		elapsed = TimerService.getElapsed(player),
	}
end

local function restartRunFor(player: Player)
	if restarting then
		return
	end
	restarting = true

	-- The level's damage, repaired in place. Everyone sees it; nobody is moved by it.
	DeformationService.restoreAll()

	local state = PlayerStateService.getState(player)
	if state and levelInstance then
		PlayerStateService.restartRun(player, levelInstance.startPosition)
		-- Put the mode back. LevelService.startLevel used to wipe it via init; restartRun
		-- keeps it, and setMode is legal here because restartRun restores isAtStart.
		PlayerStateService.setMode(player, state.mode)
		syncTimer(player)
	end

	restarting = false
end

sendBackToStart = function(player: Player)
	local character = player.Character
	local found = character and character:FindFirstChild("HumanoidRootPart")
	if not levelInstance or not found or not found:IsA("BasePart") then
		return
	end
	local hrp: BasePart = found
	noteFall(player)
	TimerService.resetTimer(player)
	syncTimer(player)
	PlayerFell:FireClient(player, secondChance.falls[player] ~= nil)
	restartRunFor(player)
	hrp.CFrame = CFrame.new(levelInstance.startPosition + Vector3.new(0, 3, 0))
end

-- ===== Fail-state handling =====
-- A "fail" (missed jump / fell off) is detected by Y-position dropping below a kill-plane
-- threshold under the level.

-- Chill mode sets you back three tiles along the route from the last checkpoint. Tiles are
-- ~3.2 studs after the geometry rescale, so this is the stud equivalent.
--
-- LOST ONCE ALREADY, and the failure is worth recording. It sat between the hardcore
-- restart and this handler, and a rewrite of the restart replaced everything up to the
-- Heartbeat connect -- taking this line with it. Luau reads an undeclared name as a nil
-- GLOBAL rather than erroring at compile time, so the file loaded fine and then threw
-- `attempt to perform arithmetic (mul) on Vector3 and nil` on every frame a player was
-- below the kill plane. The throw happened BEFORE the teleport, so chill recovery never
-- ran: you fell past the plane, kept falling, and died to Roblox's own destroy height
-- instead of being set back. check_lua.py now looks for exactly this.
local CHILL_SETBACK_STUDS = 3 * 3.2

-- A RECOVERY POINT THAT IS ACTUALLY ON SOMETHING.
--
-- Chill recovery puts you three tiles BACK down the route from your checkpoint, and back is
-- the reverse of the spiral's tangent at that chunk. That is right most of the time and
-- wrong at a chunk boundary, on a taper, and anywhere the route steps -- and when it is
-- wrong you land in open air, fall, get recovered to the same bad spot, and fall again. The
-- loop only ends when something else kills you, which reads as falling forever.
--
-- The comment beside the tangent calculation describes this failure exactly, from the last
-- time it was fixed. It was fixed there by choosing a better direction; it is fixed here by
-- CHECKING, which is the part that holds regardless of what the direction gets wrong next.
--
-- Falls back to the checkpoint itself, which is a place the player demonstrably stood.
local RECOVERY_PROBE = 60

local function groundedRecovery(candidate: Vector3, fallback: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Hub") }
	-- Downward from above the candidate: a point three tiles back is only usable if there is
	-- floor under it, and the only way to know that is to look.
	local hit = workspace:Raycast(candidate + Vector3.new(0, 6, 0),
		Vector3.new(0, -RECOVERY_PROBE, 0), params)
	if hit then
		return hit.Position + Vector3.new(0, 3.5, 0)
	end
	return fallback + Vector3.new(0, 3.5, 0)
end

-- THE SECOND CHANCE, asked for from the death card: spent first (a chance that cannot be paid for is
-- not given), then the checkpoint and the clock put back, and the runner set down where they fell from.
do
	local remote = remoteEventsFolder:FindFirstChild("SecondChance")
	if remote and remote:IsA("RemoteEvent") then
		remote.OnServerEvent:Connect(function(player: Player)
			local fall = secondChance.falls[player]
			local state = PlayerStateService.getState(player)
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart")
			if not (fall and state and levelInstance and EconomyService and hrp and hrp:IsA("BasePart")) then
				return
			end
			if os.clock() - fall.at > secondChance.WINDOW or state.mode ~= "hardcore" or state.hasCompletedLevel then
				secondChance.falls[player] = nil
				return
			end
			if not EconomyService.spendChance(player) then
				return
			end
			secondChance.falls[player] = nil
			PlayerStateService.setCheckpoint(player, fall.position, fall.chunk, fall.backward)
			local now = PlayerStateService.getState(player)
			if now then
				now.usedChance = true
			end
			TimerService.resume(player, fall.elapsed)
			syncTimer(player)
			hrp.CFrame = CFrame.new(groundedRecovery(fall.position, fall.position))
		end)
	end
end

-- ===== THE BACK ROOMS =====
--
-- Too many falls in one run (BACKROOMS_FALLS, once a run) and the last one goes through the floor, into the back
-- rooms of the baths (BackRoomsService): never announced, found by falling. The door marked WAY OUT puts you back
-- where that fall would have: the start in Hardcore (clock and all), your checkpoint in Chill. While there you are
-- "in" the back rooms as far as your own client is concerned (InLevel "backRooms": its hum, and nothing of the level's
-- own), and out of the kill plane's reach. Optional and required in a pcall, like the squish room.
local BACKROOMS_FALLS = 7
local BackRoomsService: any = nil
-- The secrets (the back rooms are the sixth, told the first time a save finds them).
local Interactables: any = nil
do
	local interactablesModule = Services:FindFirstChild("Interactables")
	if interactablesModule and interactablesModule:IsA("ModuleScript") then
		local ok, loaded = pcall(require, interactablesModule)
		if ok then
			Interactables = loaded
		end
	end
end
do
	local backRoomsModule = Services:FindFirstChild("BackRoomsService")
	if backRoomsModule and backRoomsModule:IsA("ModuleScript") then
		local ok, loaded = pcall(require, backRoomsModule)
		if ok then
			BackRoomsService = loaded
		else
			warn("Bootstrap: BackRoomsService failed to load: " .. tostring(loaded))
		end
	end
end

-- CAUGHT DOWN THERE (BackRoomsService's hunt: E. Marsh reached you before you found the way out): the scare on your
-- screen, and then the lobby, run or no run (the run is lost, as a run left is).
local function caughtInBackRooms(player: Player, at: Vector3)
	if player:GetAttribute("InLevel") ~= "backRooms" then
		return
	end
	player:SetAttribute("BackRoomsFrom", nil)
	local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local story = remotes and remotes:FindFirstChild("StoryMoment")
	if story and story:IsA("RemoteEvent") then
		story:FireClient(player, "caught", { at = at })
	end
	-- (Long enough for the whole of it on their screen: him over you, his face, the lunge; StoryClient's CAUGHT.)
	task.wait(3.9)
	if not player.Parent or player:GetAttribute("InLevel") ~= "backRooms" then
		return
	end
	ScreenFade:FireClient(player, { black = true, time = 0.05 })
	if levelInstance and HubService.isInRun(player) then
		progression(player, "fail")
		TimerService.resetTimer(player)
		syncTimer(player)
		HubService.returnToHub(player)
		storyLeave(player)
	else
		HubService.returnToHub(player)
	end
	task.delay(0.5, function()
		ScreenFade:FireClient(player, { black = false, time = 0.9 })
	end)
end

-- INTO THE BACK ROOMS, however you came: a cut to black (at once, so the move is never seen: it reads as going
-- through the floor), and you are standing where you arrive as it fades back. And something down there starts to
-- walk (BackRoomsService.hunt).
local function enterBackRooms(player: Player, hrp: BasePart, how: string?)
	ScreenFade:FireClient(player, { black = true, time = 0.02 })
	-- How you came (the hundred-and-third pass): "lobby" down its corridor, which leaves the door behind you open to
	-- go back by; "fall" through the floor, which does not. Set before InLevel, so the client sees both together.
	player:SetAttribute("BackRoomsFrom", how or "fall")
	player:SetAttribute("InLevel", "backRooms")
	-- The lobby's vote card packed away, as a run's start does (HubService.hubPlayers leaves them out from here on).
	HubVoteState:FireClient(player, "clear", {})
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.CFrame = BackRoomsService.arrival()
	task.delay(0.35, function()
		ScreenFade:FireClient(player, { black = false, time = 0.9 })
	end)
	if BackRoomsService.hunt then
		BackRoomsService.hunt(player, caughtInBackRooms)
	end
end

-- FOUND BY FALLING (the kill plane, BACKROOMS_FALLS): in, and kept in the save, and counted.
local function sendToBackRooms(player: Player, hrp: BasePart)
	-- Found for the first time by this save (asked before it is marked found): told as a secret, below.
	local first = not (EconomyService and EconomyService.foundBackRooms and EconomyService.foundBackRooms(player))
	enterBackRooms(player, hrp, "fall")
	if EconomyService and EconomyService.markFoundBackRooms then
		pcall(EconomyService.markFoundBackRooms, player)
	end
	-- A Hardcore fall is still a fall: the clock goes back to nothing, as it would have.
	local state = PlayerStateService.getState(player)
	if state and state.mode == "hardcore" then
		TimerService.resetTimer(player)
		syncTimer(player)
	end
	print(("Bootstrap: %s fell through into the back rooms."):format(player.Name))
	pcall(function()
		AnalyticsService:LogCustomEvent(player, "BackRoomsFound")
	end)
	if EconomyService and EconomyService.awardBadge then
		local catalogOk, catalog = pcall(function()
			return require(ReplicatedStorage:WaitForChild("Shared"):FindFirstChild("ShopCatalog") :: ModuleScript)
		end)
		if catalogOk and type(catalog) == "table" and type(catalog.BADGES) == "table" then
			EconomyService.awardBadge(player, catalog.BADGES.backRooms)
		end
	end
	-- THE SIXTH SECRET (Interactables.SECRETS.backRooms), the first time: once the screen has come back, its scene on
	-- Mrs Venn's notice, its card ("Secret 6 of 6", or however many you have), and the notice in your journal.
	if first and Interactables and Interactables.reveal and BackRoomsService.secretShot then
		task.delay(1.2, function()
			local eye, focus, anchor = BackRoomsService.secretShot()
			if eye and focus and anchor and player.Parent and player:GetAttribute("InLevel") == "backRooms" then
				pcall(Interactables.reveal, player, "backRooms", eye, focus, anchor)
			end
		end)
	end
end

-- THE WAY OUT (the door's prompt): back where the fall that sent you would have put you; to the lobby if the run
-- you came from is over.
local function leaveBackRooms(player: Player)
	if player:GetAttribute("InLevel") ~= "backRooms" then
		return
	end
	if BackRoomsService.callOff then
		BackRoomsService.callOff(player)
	end
	player:SetAttribute("BackRoomsFrom", nil)
	local character = player.Character
	local found = character and character:FindFirstChild("HumanoidRootPart")
	if not (found and found:IsA("BasePart")) then
		return
	end
	local hrp: BasePart = found
	ScreenFade:FireClient(player, { black = true, time = 0.3 })
	task.wait(0.3)
	local state = PlayerStateService.getState(player)
	if levelInstance and HubService.isInRun(player) and state then
		player:SetAttribute("InLevel", runBackdrop)
		if state.mode == "hardcore" then
			restartRunFor(player)
			TimerService.resetTimer(player)
			syncTimer(player)
			hrp.CFrame = CFrame.new(levelInstance.startPosition + Vector3.new(0, 3, 0))
		else
			local back = state.checkpointBackward or Vector3.new(0, 0, -1)
			local behind = state.checkpointPosition + back * CHILL_SETBACK_STUDS
			hrp.CFrame = CFrame.new(groundedRecovery(behind, state.checkpointPosition))
		end
	else
		HubService.returnToHub(player)
	end
	ScreenFade:FireClient(player, { black = false, time = 0.7 })
end
backRoomsLeave = leaveBackRooms

-- BACK THROUGH THE DOOR YOU CAME IN BY (the hundred-and-third pass): for someone who came down the lobby's corridor
-- (BackRoomsFrom "lobby"), the door behind where they arrived takes them back up it, to the corridor's turn, facing
-- the way out, as if they had only stepped through and back. Once a moment, however many parts of them touch it.
local goingBack: { [Player]: boolean } = {}
local function backThroughTheDoor(player: Player)
	if goingBack[player] or player:GetAttribute("InLevel") ~= "backRooms" or player:GetAttribute("BackRoomsFrom") ~= "lobby" then
		return
	end
	goingBack[player] = true
	if BackRoomsService.callOff then
		BackRoomsService.callOff(player)
	end
	ScreenFade:FireClient(player, { black = true, time = 0.25 })
	task.wait(0.28)
	player:SetAttribute("BackRoomsFrom", nil)
	HubService.returnToHub(player, if HubService.backDoorReturn then HubService.backDoorReturn() else nil)
	ScreenFade:FireClient(player, { black = false, time = 0.8 })
	task.delay(1, function()
		goingBack[player] = nil
	end)
end
if BackRoomsService and BackRoomsService.setReturn then
	BackRoomsService.setReturn(backThroughTheDoor)
end

-- THE LOBBY'S BACK CORRIDOR (HubService.setBackRoomsDoor): its far end takes someone who has found the back rooms
-- (their save) straight in, from the lobby only; the way out brings them back to it. A dead end for anyone else.
if HubService.setBackRoomsDoor then
	HubService.setBackRoomsDoor(function(player: Player)
		if not (BackRoomsService and BackRoomsService.isBuilt()) then
			return
		end
		if HubService.isInRun(player) or player:GetAttribute("InLevel") ~= nil or player:GetAttribute("InSquishRoom") then
			return
		end
		if not (EconomyService and EconomyService.foundBackRooms and EconomyService.foundBackRooms(player)) then
			return
		end
		local character = player.Character
		local found = character and character:FindFirstChild("HumanoidRootPart")
		if found and found:IsA("BasePart") then
			enterBackRooms(player, found, "lobby")
		end
	end)
end

-- STUDIO ONLY: the test panel's "Back rooms" takes you there now (as a fall would, in a run; through the lobby's
-- corridor otherwise), and counts them as found, so the corridor can be tried too.
if game:GetService("RunService"):IsStudio() and BackRoomsService then
	local dev = remoteEventsFolder:FindFirstChild("DevPanel")
	if dev and dev:IsA("RemoteEvent") then
		dev.OnServerEvent:Connect(function(player: Player, action: any)
			if action ~= "backRooms" or not BackRoomsService.isBuilt() or player:GetAttribute("InLevel") == "backRooms" then
				return
			end
			local character = player.Character
			local found = character and character:FindFirstChild("HumanoidRootPart")
			if not (found and found:IsA("BasePart")) then
				return
			end
			local state = PlayerStateService.getState(player)
			if levelInstance and HubService.isInRun(player) and state then
				state.backRooms = true
				sendToBackRooms(player, found)
			else
				if EconomyService and EconomyService.markFoundBackRooms then
					pcall(EconomyService.markFoundBackRooms, player)
				end
				enterBackRooms(player, found)
			end
		end)
	end
end

if BackRoomsService then
	task.spawn(function()
		local ok, err = pcall(BackRoomsService.build, leaveBackRooms)
		if not ok then
			warn("Bootstrap: the back rooms failed to build: " .. tostring(err))
		end
	end)
end

game:GetService("RunService").Heartbeat:Connect(function()
	-- THE HUB CATCH RUNS ALWAYS, and gating it on `not levelInstance` was the bug.
	--
	-- The room sits 200 studs up and the spiral only ever CLIMBS -- every entry in
	-- STEP_CHOICES and PACE_STEP_CHOICES is zero or positive -- so the level tops out well
	-- below the lobby. killY is therefore around -16, which is a 216-stud drop from the hub
	-- floor: long enough to read as falling forever, and entirely unprotected whenever a run
	-- happened to be in progress, because this returned before reaching the check.
	--
	-- Written as a proximity test rather than a mode test. Where you are is the thing that
	-- decides where you belong, and it stays true whether or not a level exists.
	-- ONLY WHILE THE ROOM IS ACTUALLY THERE.
	--
	-- This is a proximity test -- below the deck, within 200 studs of it horizontally -- and
	-- during a run the level occupies that same column of space. So a runner 150 studs under
	-- the lobby was inside the catch's box and could be yanked up to a spawn pad that, since
	-- the room now stashes itself, was not even in the workspace.
	--
	-- Where you are decides where you belong, but only when there is something to belong to.
	local hubSpawn = HubService.spawnPosition()
	if not HubService.isHidden() then
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local found = character and character:FindFirstChild("HumanoidRootPart")
			if found and found:IsA("BasePart") then
				local at = found.Position
				local flat = Vector2.new(at.X - hubSpawn.X, at.Z - hubSpawn.Z).Magnitude
				if at.Y < hubSpawn.Y - 30 and at.Y > hubSpawn.Y - 400 and flat < 200 then
					local hrp: BasePart = found
					hrp.CFrame = CFrame.new(hubSpawn)
				end
			end
		end
	end

	if not levelInstance then
		return
	end
	-- Derived from the level's lowest surface rather than a fixed Y, because the
	-- elevation profile can descend well below the starting height.
	local killY = levelInstance.killY

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local found = character and character:FindFirstChild("HumanoidRootPart")
		if not found or not found:IsA("BasePart") then
			continue
		end
		-- Bound to a plain typed local on purpose. Writing `(hrp :: BasePart).CFrame = ...`
		-- as a statement directly after a function call or a `local x = f(...)` line is a
		-- Luau parse ambiguity: the parser reads the leading `(` as the argument list of a
		-- call to the previous expression, and the whole script fails to compile.
		local hrp: BasePart = found
		-- A STORY PLAYER BEING MOVED to its next level (storyNext) is held, and is no fall.
		if storyMoving[player] then
			continue
		end
		-- NOR IS ANYONE IN THE BACK ROOMS (they are far from the level, on a floor of their own).
		if player:GetAttribute("InLevel") == "backRooms" then
			continue
		end

		-- THE DIVE IS A FALL THIS DOES NOT OWN. City Shore finishes seven hundred studs below
		-- the kill plane, in the sea, so a diver is exempt from the moment they leave the board
		-- until the lobby takes them back. Sky Pools' slide is the same: it ends in a pool under the
		-- clouds, far below the plane that catches an ordinary fall into them. And the Sunken City's
		-- drain, which ends at the bottom of a shaft under the harbour floor.
		--
		-- AND THE FLOODED HALLS' FLUME, which was missing and is the whole of that bug: the ride
		-- drops into the void under the far chamber, the plane caught the rider part way down, and
		-- put them back on the last chunk they had touched. A ride that ends the level cannot be
		-- something the plane interrupts.
		if hrp.Position.Y < killY
			and not (DiveFinaleService and DiveFinaleService.ownsFall(player))
			and not (SkyPoolsService and SkyPoolsService.ownsFall(player))
			and not (SunkenCityService and SunkenCityService.ownsFall(player))
			and not (FloodedHallsService and FloodedHallsService.ownsFall
				and FloodedHallsService.ownsFall(player)) then
			local state = PlayerStateService.getState(player)
			if not state then
				continue
			end
			-- ONE FALL TOO MANY (BACKROOMS_FALLS in this run): through the floor, into the back rooms. Once a run.
			state.falls = (state.falls or 0) + 1
			if BackRoomsService and BackRoomsService.isBuilt() and state.falls >= BACKROOMS_FALLS and not state.backRooms then
				state.backRooms = true
				sendToBackRooms(player, hrp)
				continue
			end
			if state.mode == "hardcore" then
				noteFall(player)
				TimerService.resetTimer(player)
				syncTimer(player)
				-- Fired before the teleport, so the card is already fading up as the world
				-- changes underneath it rather than arriving after you have landed. It says whether
				-- there is a second chance to offer (somewhere to go back to).
				PlayerFell:FireClient(player, secondChance.falls[player] ~= nil)
				-- Only this player. `restarting` guards the storm: this runs on Heartbeat,
				-- and a character stays below the kill plane for several frames while the
				-- teleport and the repair are in flight.
				restartRunFor(player)
				hrp.CFrame = CFrame.new(levelInstance.startPosition + Vector3.new(0, 3, 0))
			else
				local back = state.checkpointBackward or Vector3.new(0, 0, -1)
				local behind = state.checkpointPosition + back * CHILL_SETBACK_STUDS
				hrp.CFrame = CFrame.new(groundedRecovery(behind, state.checkpointPosition))
			end
		end
	end
end)

-- ===== THE PASTE CHECK (Studio only) =====
--
-- Every file here is pasted by hand and every sound imported by hand, and a round can be forty files. So in
-- Studio the server says, a few seconds after it starts, whether everything the game expects is in place:
-- every module (server, shared and client) as the right kind of script, the scripts, the sounds, and
-- ProfileStore; and that the modules taken out of the game are gone. What is wrong is named, with where it
-- goes; when it is all there, it says so in one line. check_hub.py keeps these lists the same as src/ and
-- audio/, so a file added to the game is added here too.
-- PASTE STAMPS (written by tools/stamp.py, not by hand): what each module's STAMP says when it is current.
local PASTE_STAMPS: { [string]: { [string]: string } } = {
	shared = {
		ChunkDefinitions = "4210d3cc",
		Conversations = "3ea9ed08",
		Keepsakes = "2213dd3d",
		LevelDefinitions = "4fc9bd94",
		LobbyLayout = "d2908861",
		MaterialAppearance = "b1cbae82",
		MaterialConfig = "cb2d1920",
		PlanShapes = "c4c2dee5",
		Poses = "f120320d",
		ShopCatalog = "a893da9c",
		SkyPath = "ee880e00",
		Style = "34c3e714",
		SunkenPath = "938bcf38",
		WaterSounds = "f8d3e842",
	},
	server = {
		BackRoomsService = "ca6fa480",
		BestTimeService = "71828c8e",
		DiveFinaleService = "f9e1544f",
		EconomyService = "66b1627b",
		FloodedHallsService = "facf4cb4",
		HillHouseService = "2b03c327",
		HubService = "f3c4e0b7",
		Interactables = "3ee2e4f1",
		LeaderboardService = "5cb1004e",
		LightingService = "e8009ba0",
		SkyPoolsService = "d628dbf4",
		SquishRoomService = "87302c64",
		StoryService = "527b60fd",
		SunkenCityService = "1f4fbbe3",
		TimerService = "4c754864",
		Townsfolk = "0d6b3e76",
	},
	client = {
		AmbienceService = "93ae5f36",
		AudioService = "1096b908",
		Cinema = "87246380",
		CityShoreClient = "bf8a0666",
		CosmeticsClient = "2e4a024f",
		DeathService = "88f12ebc",
		DeformationRenderer = "2c44d45e",
		DevPanelClient = "61fc5413",
		EmoteService = "ef8c7244",
		FloodedHallsClient = "bfede0cc",
		HillHouseClient = "899d813c",
		HubLeverService = "cb5ad0b8",
		HubVoteService = "39a9ce1b",
		JournalService = "a9e90c21",
		LobbyLife = "19fe7174",
		Maw = "17049ea6",
		OnboardingService = "5de561e4",
		PauseMenuService = "466ea02d",
		PlayerLife = "32becc65",
		ScreenEffects = "1aab395f",
		SearchlightClient = "25ab1038",
		ShopLook = "b104ab03",
		ShopService = "9fa2efc2",
		SkyPoolsClient = "6361e442",
		SquishRoomClient = "d8a5bf07",
		StalkerClient = "54373819",
		StepService = "f8fc4255",
		StoryClient = "fb1f02a8",
		SunkenCityClient = "655616d7",
		TalkClient = "d2da2c3b",
		UIService = "75a6c86e",
		ViewModeService = "fa7b7c02",
	},
}
-- END PASTE STAMPS

-- THE CLIENT'S HALF needs the client modules' stamps, which only this script has: published for it, in Studio.
if game:GetService("RunService"):IsStudio() then
	pcall(function()
		ReplicatedStorage:SetAttribute("PasteStamps", game:GetService("HttpService"):JSONEncode(PASTE_STAMPS.client or {}))
	end)
end

local function pasteCheck()
	local ServerScriptService = game:GetService("ServerScriptService")
	local StarterPlayerScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local SoundService = game:GetService("SoundService")
	local SERVER_MODULES = { "BackRoomsService", "BackdropService", "BestTimeService", "ChunkService", "DeformationService",
		"DiveFinaleService", "EconomyService", "FloodedHallsService", "HillHouseService", "HubService", "Interactables",
		"LeaderboardService", "LevelService", "LightingService", "PlayerStateService", "SkyPoolsService",
		"SquishRoomService", "StoryService", "SunkenCityService", "TimerService", "Townsfolk" }
	local SHARED_MODULES = { "ChunkDefinitions", "Conversations", "HallRoute", "Keepsakes", "LevelDefinitions",
		"LobbyLayout", "MaterialAppearance", "MaterialConfig", "PlanShapes", "Poses", "SeaRig", "ShopCatalog", "SkyPath",
		"Style", "SubRegionGrid", "SunkenPath", "Types", "WaterSounds" }
	local CLIENT_MODULES = { "AmbienceService", "AudioService", "Cinema", "CityShoreClient", "CloudService", "CosmeticsClient",
		"DeathService", "DeformationRenderer", "DevPanelClient", "EmoteService", "FloodedHallsClient",
		"HillHouseClient", "HubLeverService", "HubVoteService", "InputService", "JournalService", "LobbyLife", "Maw", "OnboardingService",
		"PlayerLife",
		"PauseMenuService", "ScreenEffects", "SeaService", "SearchlightClient", "ShopService", "SkyPoolsClient",
		"ShopLook", "SquishRoomClient", "StalkerClient", "StepService", "StoryClient", "SunkenCityClient", "TalkClient", "UIService",
		"ViewModeService" }
	-- Taken out of the game: still there, they would run alongside what replaced them.
	local GONE = { "KeepsakeService", "PromptStyleService" }
	-- Sounds, by folder. Material sounds come four to a name (name_1 to name_4), or as ONE SHEET of takes (name_x4,
	-- audio/sheets/: the chunks' since the eighty-eighth pass, the keypad's and the last two materials' since the
	-- ninety-sixth). AudioService plays a sheet in place of any single files of its event, so those can go.
	local MATERIAL_FAMILIES = { "charcoalSnap", "claySquish", "cloudHush", "lavaCrust", "leafBrush", "legoClick", "needohSquish",
		"saltCrunch", "snowPack" }
	local SHEET_SOUNDS = { "bubblePop_x4", "button_clicky_x4", "button_linear_x3", "button_release_x3", "button_tactile_x3",
		"chocolateChunk_x4", "chocolateSnap_x4", "cookieCrunch_x4", "foamCompress_x4", "iceCrack_x4", "jelloWobble_x4",
		"jellyBounce_x4", "kineticSandImprint_x4", "slimeBoing_x4", "soapCrumble_x4", "switchClack_x4", "ooblSquelch_x4" }
	local BUTTON_SOUNDS = { "button_circuit_1", "button_circuit_2", "button_combo_1", "button_combo_2" }
	local STORY_SOUNDS = { "GateGroan", "Heartbeat", "JawsShut", "MawRumble", "SecretSting", "Siren", "WaterRush",
		"CloudWhoosh", "CulvertWash", "DiveBoard", "DiveSplash", "DiveWind", "DrainFall", "EndChord", "FlumeRush",
		"HallsChord", "PlungeWind", "PoolPlunge", "PoolsChord", "ShoreChord", "SkimSlap", "SlideRush", "SunkenChord",
		"UnderwaterHum", "WhirlRoar", "MawGrowl", "MawRoar", "TownsfolkVoice_x9", "CountdownTock_x3", "JournalAdd", "DoorSlam", "TubeDie",
		"ScreamerStab", "ArchPass", "KeyLift", "ClockStart", "ClockPunch",
		"MorningChord", "PoolsSong", "BarStrike", "BrickBurst" }
	-- Each of these has a stand-in (EndChord for the four chords, a built-in sound for the roars and the growl, the
	-- pool's chord for the Sky Pools' song).
	local OPTIONAL = { ShoreChord = true, PoolsChord = true, SunkenChord = true, HallsChord = true, WhirlRoar = true,
		MawGrowl = true, MawRoar = true, TownsfolkVoice_x9 = true, CountdownTock_x3 = true, JournalAdd = true,
		DoorSlam = true, TubeDie = true, ScreamerStab = true, ArchPass = true, KeyLift = true, ClockStart = true,
		ClockPunch = true, MorningChord = true, PoolsSong = true, BarStrike = true, BrickBurst = true }
	local AMBIENCE_SOUNDS = { "BathsHum", "HarbourNight", "HillMorning", "HoldDrone", "PartyFar", "RoofWind", "ShoreSea" }
	-- The lobby's own (the ninety-sixth pass): optional, as the lobby has the server's stand-ins without them.
	-- The levels' water (the ninety-eighth pass): optional, as the old splash stands in without them.
	local WATER_SOUNDS = { "Dip_x8", "Drip_x8", "Lap", "Pour", "Splash_x6", "Stream" }
	-- THE SHOP'S OWN (ShopLook, the hundred-and-fifth pass), optional: the shop is plain without them.
	local SHOP_SOUNDS = { "CookieCrunch_x4", "CrateReveal_x5", "CrateShake", "ShopClose", "ShopOpen", "ShopTab_x9" }
	local LOBBY_SOUNDS = { "BuoyBell_x2", "FountainBed", "FountainSplash_x10", "KeyPress_x4", "LeverChill_x2",
		"LeverHardcore_x2", "LockedPress_x2", "PadPress_x4", "PosePress_x4", "SeaBed_1", "SeaBed_2", "StartPress_x2", "Surf_x8",
		"WindGust_x5" }

	local problems: { string } = {}
	local optionalMissing: { string } = {}
	local counted = 0
	local function moduleAt(folder: Instance?, where: string, name: string)
		counted += 1
		local found = folder and folder:FindFirstChild(name)
		if not found then
			table.insert(problems, ("missing      %s/%s (ModuleScript)"):format(where, name))
		elseif not found:IsA("ModuleScript") then
			table.insert(problems, ("wrong kind   %s/%s is a %s; it should be a ModuleScript"):format(where, name,
				found.ClassName))
		end
	end
	local function scriptAt(parent: Instance?, where: string, name: string, kind: string)
		counted += 1
		local found = parent and (parent:FindFirstChild(name) or parent:FindFirstChild(name .. ".server")
			or parent:FindFirstChild(name .. ".client"))
		-- However its name is written ("BootStrap" is the same script as "Bootstrap").
		if parent and not found then
			local want = string.lower(name)
			for _, child in ipairs(parent:GetChildren()) do
				local named = string.lower(child.Name)
				if named == want or named == want .. ".server" or named == want .. ".client" then
					found = child
					break
				end
			end
		end
		if not found then
			table.insert(problems, ("missing      %s/%s (%s; if it is there under another name, ignore this)")
				:format(where, name, kind))
		elseif found.ClassName ~= kind then
			table.insert(problems, ("wrong kind   %s/%s is a %s; it should be a %s"):format(where, name, found.ClassName, kind))
		end
	end
	local serverServices = ServerScriptService:FindFirstChild("Services")
	for _, name in ipairs(SERVER_MODULES) do
		moduleAt(serverServices, "ServerScriptService/Services", name)
	end
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	for _, name in ipairs(SHARED_MODULES) do
		moduleAt(shared, "ReplicatedStorage/Shared", name)
	end
	local clientServices = StarterPlayerScripts and StarterPlayerScripts:FindFirstChild("Services")
	for _, name in ipairs(CLIENT_MODULES) do
		moduleAt(clientServices, "StarterPlayerScripts/Services", name)
	end
	scriptAt(ServerScriptService, "ServerScriptService", "Bootstrap", "Script")
	scriptAt(ServerScriptService, "ServerScriptService", "ChunkBuilder", "Script")
	scriptAt(ServerScriptService, "ServerScriptService", "ChunkProps", "Script")
	scriptAt(StarterPlayerScripts, "StarterPlayerScripts", "Bootstrap", "LocalScript")
	for _, name in ipairs(GONE) do
		for _, folder in ipairs({ clientServices, serverServices }) do
			if folder and folder:FindFirstChild(name) then
				table.insert(problems, ("delete       %s (no longer part of the game)"):format(folder:GetFullName() .. "." .. name))
			end
		end
	end
	-- ANOTHER MODULE'S CODE IN IT (pasted into the wrong script): a module whose STAMP is the one expected of a
	-- different module. BackRoomsService's code once went into BackdropService, which builds City Shore's terrain,
	-- so City Shore had none, and nothing here said so: BackdropService has no stamp of its own to be checked
	-- against. Every module is looked at for this, stamped or not. The client's are checked on the client.
	local owner: { [string]: string } = {}
	for _, kind in ipairs({ "server", "shared", "client" }) do
		for name, stamp in pairs(PASTE_STAMPS[kind] or {}) do
			owner[stamp] = name
		end
	end
	local misplaced: { [string]: boolean } = {}
	for _, side in ipairs({ { names = SERVER_MODULES, folder = serverServices, where = "ServerScriptService/Services",
		src = "src/Server/Services/" }, { names = SHARED_MODULES, folder = shared, where = "ReplicatedStorage/Shared",
		src = "src/Shared/" } }) do
		for _, name in ipairs(side.names) do
			local found = side.folder and side.folder:FindFirstChild(name)
			if found and found:IsA("ModuleScript") then
				local ok, loaded = pcall(require, found)
				local stamp = if ok and type(loaded) == "table" then loaded.STAMP else nil
				local whose = if type(stamp) == "string" then owner[stamp] else nil
				if whose and whose ~= name then
					misplaced[name] = true
					table.insert(problems, ("wrong code   %s/%s has %s's code in it: paste %s%s.lua into it (and check %s)")
						:format(side.where, name, whose, side.src, name, whose))
				end
			end
		end
	end
	-- AN OLD COPY: a server or shared module whose STAMP is not the one expected (tools/stamp.py) was pasted before
	-- its last change, and is named. The client's modules are checked on the client (Bootstrap.client).
	for _, side in ipairs({ { kind = "server", folder = serverServices, where = "ServerScriptService/Services" },
		{ kind = "shared", folder = shared, where = "ReplicatedStorage/Shared" } }) do
		local expected = PASTE_STAMPS[side.kind] or {}
		local names = {}
		for name in pairs(expected) do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in ipairs(names) do
			local found = side.folder and side.folder:FindFirstChild(name)
			if found and found:IsA("ModuleScript") then
				local ok, loaded = pcall(require, found)
				local stamp = if ok and type(loaded) == "table" then loaded.STAMP else nil
				if stamp ~= expected[name] and not misplaced[name] then
					table.insert(problems, ("out of date  %s/%s is an old copy: paste the current one"):format(side.where, name))
				end
			end
		end
	end
	local profileStore = ServerScriptService:FindFirstChild("ProfileStore")
	if not (profileStore and profileStore:IsA("ModuleScript")) then
		table.insert(problems, "missing      ServerScriptService/ProfileStore (ModuleScript, by loleris: saves do not keep without it)")
	else
		-- THE RIGHT ONE: loleris's ProfileStore has ProfileStore.New. Something else of that name (ProfileService, his
		-- older library, has GetProfileStore instead) loads and then saves nothing.
		local ok, loaded = pcall(require, profileStore)
		if not ok then
			table.insert(problems, "broken       ServerScriptService/ProfileStore does not load: " .. tostring(loaded))
		elseif type(loaded) ~= "table" or type((loaded :: any).New) ~= "function" then
			local older = type(loaded) == "table" and type((loaded :: any).GetProfileStore) == "function"
			table.insert(problems, "wrong module ServerScriptService/ProfileStore has no ProfileStore.New, so nothing is saved: "
				.. (if older then "it is ProfileService (the older library)" else "it is not loleris's ProfileStore")
				.. ". Put ProfileStore (github.com/MadStudioRoblox/ProfileStore) in its place, named ProfileStore.")
		end
	end

	local sounds = 0
	-- A sound in its folder: missing, or there twice (an old one not deleted, so old and new play at random).
	local function sound(folderName: string, name: string, optional: boolean?)
		sounds += 1
		local folder = SoundService:FindFirstChild(folderName)
		local copies = 0
		if folder then
			for _, child in ipairs(folder:GetChildren()) do
				if child.Name == name then
					copies += 1
				end
			end
		end
		if copies == 0 then
			if optional then
				table.insert(optionalMissing, name)
			else
				table.insert(problems, ("sound        SoundService.%s.%s is missing"):format(folderName, name))
			end
		elseif copies > 1 then
			table.insert(problems, ("sound twice  SoundService.%s.%s is there %d times: delete the old one"):format(
				folderName, name, copies))
		end
	end
	for _, family in ipairs(MATERIAL_FAMILIES) do
		for k = 1, 4 do
			sound("MaterialSounds", family .. "_" .. k)
		end
	end
	for _, name in ipairs(SHEET_SOUNDS) do
		sound("MaterialSounds", name)
	end
	for _, name in ipairs(BUTTON_SOUNDS) do
		sound("MaterialSounds", name)
	end
	for _, name in ipairs(STORY_SOUNDS) do
		sound("StorySounds", name, OPTIONAL[name])
	end
	for _, name in ipairs(AMBIENCE_SOUNDS) do
		sound("AmbienceSounds", name)
	end
	for _, name in ipairs(LOBBY_SOUNDS) do
		sound("LobbySounds", name, true)
	end
	for _, name in ipairs(SHOP_SOUNDS) do
		sound("ShopSounds", name, true)
	end
	for _, name in ipairs(WATER_SOUNDS) do
		sound("WaterSounds", name, true)
	end

	if #problems == 0 then
		print(("PASTE CHECK: everything is in place (%d modules and scripts, %d sounds, ProfileStore)."):format(
			counted, sounds - #optionalMissing))
	else
		warn(("PASTE CHECK: %d thing%s to fix before testing:\n  %s"):format(#problems,
			if #problems == 1 then "" else "s", table.concat(problems, "\n  ")))
	end
	if #optionalMissing > 0 then
		print("PASTE CHECK: not imported, with a stand-in playing instead (fine for now): "
			.. table.concat(optionalMissing, ", "))
	end

	-- THE DATA STORES: without them nothing is kept in a Studio test, which is worth knowing before judging
	-- whether saving works.
	local storesOk = pcall(function()
		game:GetService("DataStoreService"):GetDataStore("PasteCheck"):GetAsync("probe")
	end)
	if not storesOk then
		warn("PASTE CHECK: Studio cannot reach the data stores, so saves, the journal, best times and the leaderboard "
			.. "are not kept in this test. Publish the place, then Game Settings, Security, Enable Studio Access to "
			.. "API Services.")
	end

	-- ROBUX ITEMS WITH NO ID YET (ShopCatalog.lua): fine for testing (the shop says "not on sale yet"), needed
	-- before the game is published.
	local catalogModule = shared and shared:FindFirstChild("ShopCatalog")
	local notOnSale: { string } = {}
	if catalogModule and catalogModule:IsA("ModuleScript") then
		local ok, catalog = pcall(require, catalogModule)
		if ok and type(catalog) == "table" and type(catalog.all) == "function" then
			for _, item in ipairs(catalog.all()) do
				local unset = if item.passId ~= nil then item.passId == 0 else (item.productId or 0) == 0
				if item.robux and unset then
					table.insert(notOnSale, tostring(item.name))
				end
			end
		end
	end
	if #notOnSale > 0 then
		print("PASTE CHECK: not on sale yet, no id in ShopCatalog.lua (fine for testing, needed before publishing): "
			.. table.concat(notOnSale, ", "))
	end
	-- BADGES NOT MADE YET (ShopCatalog.BADGES): nothing is awarded for them until they are.
	if catalogModule and catalogModule:IsA("ModuleScript") then
		local ok, catalog = pcall(require, catalogModule)
		local badges = if ok and type(catalog) == "table" then catalog.BADGES else nil
		if type(badges) == "table" then
			local unmade: { string } = {}
			for _, level in ipairs(LevelDefinitions.All) do
				if type(badges.level) ~= "table" or (badges.level[level.levelId] or 0) == 0 then
					table.insert(unmade, tostring(level.name))
				end
			end
			if (badges.story or 0) == 0 then
				table.insert(unmade, "the story")
			end
			if (badges.storyHardcore or 0) == 0 then
				table.insert(unmade, "the story in Hardcore")
			end
			if (badges.backRooms or 0) == 0 then
				table.insert(unmade, "the back rooms (a secret)")
			end
			if #unmade > 0 then
				print("PASTE CHECK: badges not made yet, no id in ShopCatalog.BADGES (nothing is awarded for them until "
					.. "there is): " .. table.concat(unmade, ", "))
			end
		end
	end
end
if game:GetService("RunService"):IsStudio() then
	task.delay(4, function()
		local ok, err = pcall(pasteCheck)
		if not ok then
			warn("PASTE CHECK could not run: " .. tostring(err))
		end
	end)
end

-- THE LAST LINE OF BOOTSTRAP, and it exists to make one specific failure diagnosable.
--
-- This is a single Script, so a throw at any top-level line silently kills every line below
-- it -- and the kill plane is connected near the bottom. That is how a half-built lobby with
-- no kill plane happened, and from inside the game it looked like an infinite-fall bug rather
-- than like a startup error.
--
-- If this line is missing from the output, something above it threw and the game is running
-- with an unknown amount of itself not wired up. That is worth one print.
print("Bootstrap: ready. Kill plane active, hub wired.")
