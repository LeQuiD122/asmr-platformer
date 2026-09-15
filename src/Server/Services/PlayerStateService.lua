--!strict
-- ServerScriptService/Services/PlayerStateService.lua
-- Tracks per-player session data. No dependencies. Not persisted across
-- sessions (disconnect/rejoin defaults to Chill per the GDD).

local PlayerStateService = {}

local states: { [Player]: any } = {}

local function createInitialState(startPosition: Vector3)
	return {
		mode = "chill",
		checkpointChunkIndex = 0,
		checkpointPosition = startPosition,
		-- Which way is BACKWARDS along the route at that checkpoint. World -Z at the
		-- start, and re-derived per chunk from the helix angle after that.
		checkpointBackward = Vector3.new(0, 0, -1),
		failStatePosition = startPosition,
		hardcoreTimer = 0,
		isAtStart = true,
		hasCompletedLevel = false,
	}
end

function PlayerStateService.init(player: Player, startPosition: Vector3)
	states[player] = createInitialState(startPosition)
end

function PlayerStateService.getState(player: Player)
	return states[player]
end

function PlayerStateService.setCheckpoint(player: Player, position: Vector3, chunkIndex: number, backward: Vector3?)
	local state = states[player]
	if not state then
		return
	end
	state.checkpointPosition = position
	if backward then
		state.checkpointBackward = backward
	end
	state.checkpointChunkIndex = chunkIndex
	state.failStatePosition = position
	-- LEAVING THE FIRST CHUNK ends "the start" -- not reaching a checkpoint at all.
	--
	-- This tested `chunkIndex >= 1`, and chunk 1 is the chunk you SPAWN ON: its
	-- checkpoint trigger fires the moment the character lands on it. So every player was
	-- flagged as having left the start before they had taken a step, and the mode switch
	-- then refused every click for the rest of the session -- including, absurdly, at the
	-- start of the level, which is the one place its own error message points you to.
	--
	-- Bootstrap starts the hardcore clock on the same threshold, and deliberately so:
	-- "the run has begun" should be one fact, not two that can disagree.
	if chunkIndex >= 2 then
		state.isAtStart = false
	end
end

-- Back to the start of the level with progress cleared, and THE MODE KEPT.
--
-- Deliberately not `init`, which is for a player joining and resets mode to "chill". A
-- hardcore fall calls this, so reusing init would drop the runner into chill mode by way
-- of the very mechanic that makes hardcore hardcore -- and silently, since the HUD would
-- simply start saying Chill and they would assume they had pressed something.
--
-- `isAtStart` comes back true, which is intended: you are at the start again, so the mode
-- switch unlocks again. Being sent back to the beginning and then being told you may not
-- change mode there would be the wrong answer to a reasonable request.
function PlayerStateService.restartRun(player: Player, startPosition: Vector3)
	local state = states[player]
	if not state then
		return
	end
	local mode = state.mode
	states[player] = createInitialState(startPosition)
	states[player].mode = mode
end

-- Chill mode: teleport 3 tiles behind the checkpoint (not the checkpoint itself).
function PlayerStateService.resetToFailState(player: Player, mode: "chill" | "hardcore", levelStartPosition: Vector3)
	local state = states[player]
	if not state then
		return nil
	end
	if mode == "hardcore" then
		return levelStartPosition
	end
	-- "3 tiles behind" is resolved by LevelService using chunk geometry;
	-- this just returns the checkpoint as the anchor point to offset from.
	return state.checkpointPosition
end

function PlayerStateService.setMode(player: Player, mode: "chill" | "hardcore")
	local state = states[player]
	if not state then
		return false
	end
	if not state.isAtStart then
		return false -- toggle only allowed at level start
	end
	state.mode = mode
	state.hardcoreTimer = 0 -- switching discards any in-progress timer
	return true
end

-- THE MODE THE LOBBY CHOSE, applied when the run actually starts.
--
-- setMode above refuses unless isAtStart, which is right for the in-run toggle and wrong for
-- this: the hub is the authority on what mode a run is, and it says so BEFORE the run exists.
-- Without this the pad you stood on in the lobby changed nothing at all -- the run used
-- whatever mode the state happened to be carrying, so a chill player got the hardcore
-- send-back-to-start on their first fall and had no idea why.
--
-- isAtStart goes false in the same breath. The run has begun and the choice is made; the mode
-- is not up for renegotiation until you are back in the lobby.
function PlayerStateService.beginRun(player: Player, mode: "chill" | "hardcore")
	local state = states[player]
	if not state then
		return false
	end
	state.mode = mode
	state.hardcoreTimer = 0
	state.isAtStart = false
	return true
end

function PlayerStateService.canToggleMode(player: Player): boolean
	local state = states[player]
	return state ~= nil and state.isAtStart == true
end

function PlayerStateService.markCompleted(player: Player)
	local state = states[player]
	if state then
		state.hasCompletedLevel = true
	end
end

function PlayerStateService.cleanup(player: Player)
	states[player] = nil
end

return PlayerStateService
