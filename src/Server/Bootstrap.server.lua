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
local sunkenModule = Services:WaitForChild("SunkenCityService", 5)
local SunkenCityService = if sunkenModule then require(sunkenModule :: ModuleScript) :: any else nil
-- Disconnects the drain's watch and the aquarium glass. The city itself goes with Workspace.Levels.
local sunkenTeardown: (() -> ())? = nil
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

local function startChosenLevel(level, players: { Player }, origin: Vector3)
	-- THE DIVE STANDS DOWN FIRST, before the old level is cleared out from under it. Its watch
	-- puts the platform back whenever it finds it destroyed, so a stop that came after the clear
	-- would have it rebuilding a platform for a level that no longer exists, in the frame the
	-- PREVIOUS run ended at.
	if DiveFinaleService then
		pcall(DiveFinaleService.stop)
	end
	levelInstance = LevelService.startLevel(level, players, origin)
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
						-- (UIService.showCompletion). `ScreenFade` stays wired for whatever wants
						-- it later; nothing fires it today.
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

	-- The chunks exist now, so their checkpoint triggers can be connected. Deferred by one
	-- frame so the models have finished parenting before anything looks for their parts.
	task.defer(function()
		wireCheckpointing(players)
	end)
	return levelInstance
end

HubService.setRunner(startChosenLevel)
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
	local standing = workspace:FindFirstChild("Backdrop")
	if standing then
		standing:Destroy()
	end
	local standing = workspace:FindFirstChild("Backdrop")
	if standing then
		standing:Destroy()
	end
	-- The dive platform is a child of Levels and goes with it, but the loop watching for divers
	-- is not: left running it would be watching a level that no longer exists.
	if DiveFinaleService then
		pcall(DiveFinaleService.stop)
	end
	LevelService.endLevel()
	levelInstance = nil
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

local function wirePlayer(player: Player)
	local function onCharacter(character: Model)
		local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart
		-- NO WAITING LOOP ANY MORE. This used to spin for up to ten seconds because the
		-- level was still generating when the first character spawned. The hub is built
		-- before any player is wired and never goes away, so there is always somewhere to
		-- put someone: the level if a run is in progress, the room otherwise.
		local target = if levelInstance then levelInstance.startPosition else hub.spawnPosition
		hrp.CFrame = CFrame.new(target)
		if not PlayerStateService.getState(player) then
			PlayerStateService.init(player, target)
			TimerService.init(player)
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

Players.PlayerRemoving:Connect(function(player: Player)
	PlayerStateService.cleanup(player)
	TimerService.cleanup(player)
	-- The GUI goes with the PlayerGui, but the mode and the label reference are held in a
	-- table keyed by Player, and a table keyed by a leaving Player is a leak.
	HubService.detachBoard(player)
	HubService.clearBallot(player)
	toggling[player] = nil
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
	if not HubService.isInRun(player) then
		return
	end
	TimerService.resetTimer(player)
	syncTimer(player)
end)

LeaveLevel.OnServerEvent:Connect(function(player: Player)
	if levelInstance then
		-- THE CLOCK STOPS WITH THE RUN. Leaving to the lobby left it ticking, so the hub showed a
	-- hardcore time counting up for a run that had ended -- and the next run inherited it.
	TimerService.resetTimer(player)
	syncTimer(player)
	HubService.returnToHub(player)
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

		-- RECORDED IN BOTH MODES, unlike the leaderboard. This is the player's own record
		-- rather than a ranking, so a chill run is worth keeping -- and the two modes are
		-- stored under separate keys rather than compared.
		-- Read BEFORE the hardcore branch stops the clock, so both modes record the same
		-- number for the same run.
		BestTimeService.submit(player, levelInstance.levelId, state.mode,
			TimerService.getElapsed(player))

		if state.mode == "hardcore" then
			local elapsed = TimerService.stopTimer(player)
			LeaderboardService.submitTime(player, levelInstance.levelId, state.mode, elapsed)
			syncTimer(player)
			LevelCompleted:FireClient(player, { levelId = levelInstance.levelId, time = elapsed })
		else
			LevelCompleted:FireClient(player, { levelId = levelInstance.levelId })
		end

		-- BACK TO THE ROOM, after the client has had the completion event.
		--
		-- The delay is the panel's own read time. Teleporting on the same frame would replace
		-- the result with a lobby before anyone had seen what they scored, which is the one
		-- moment the whole run was for.
		task.delay(4, function()
			HubService.returnToHub(player)
			-- AND THE ROOM GETS ITS AIR BACK, once nobody is left out on the level. Lighting is
			-- one setting for the whole server, so this waits for the LAST runner: re-lighting on
			-- the first would drop the lobby's sky over everyone still climbing.
			local running = false
			for _, other in ipairs(Players:GetPlayers()) do
				local otherState = if other ~= player then PlayerStateService.getState(other) else nil
				if otherState and not otherState.hasCompletedLevel then
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
	TimerService.resetTimer(player)
	syncTimer(player)
	PlayerFell:FireClient(player)
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
			if state.mode == "hardcore" then
				TimerService.resetTimer(player)
				syncTimer(player)
				-- Fired before the teleport, so the card is already fading up as the world
				-- changes underneath it rather than arriving after you have landed.
				PlayerFell:FireClient(player)
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
