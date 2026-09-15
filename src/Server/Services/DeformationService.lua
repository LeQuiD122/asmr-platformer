--!strict
-- ServerScriptService/Services/DeformationService.lua
-- Heart of the shared deformation system. Maintains a dictionary of active
-- sub-region states per platform, runs decay timers, applies per-material
-- gameplay effects (speed/friction/launch/dissolve/pop), and replicates
-- state changes to clients via the DeformationUpdate RemoteEvent.
--
-- Occupancy is tracked as a SET of players per cell, not a counter. Touched
-- and TouchEnded both fire many times per second per limb while a character
-- simply stands still, so a counter oscillates through zero and produces a
-- replication storm. Exits are also held for EXIT_GRACE seconds and cancelled
-- if the player re-touches, which absorbs spurious TouchEnded events.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SubRegionGrid = require(Shared:WaitForChild("SubRegionGrid"))
local MaterialConfigModule = require(Shared:WaitForChild("MaterialConfig"))
local Materials = MaterialConfigModule.Materials
local Constants = MaterialConfigModule.Constants

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local DeformationUpdate = RemoteEvents:WaitForChild("DeformationUpdate")
local SlimeLaunch = RemoteEvents:WaitForChild("SlimeLaunch")

local EXIT_GRACE = 0.2 -- seconds a TouchEnded is held before it counts as a real exit

local DeformationService = {}

-- platformStates[platform] = {
--   material = string?,
--   grid = GridConfig,
--   cells = { [colRow: string] = Cell },
--   playerCellCount = { [Player] = number },  -- cells this player occupies here
-- }
-- Cell = {
--   state, part, col, row,
--   occupants = { [Player] = true },
--   count = number,
--   pendingExit = { [Player] = number },
--   decayTimer, popCount, stepCount, dissolveScheduled,
-- }
local platformStates: { [BasePart]: any } = {}
local exitTokenCounter = 0

local function getOrCreatePlatformState(platform: BasePart)
	local state = platformStates[platform]
	if state then
		return state
	end
	state = {
		material = platform:GetAttribute("Material") :: string?,
		grid = SubRegionGrid.compute(platform.Size.X, platform.Size.Z),
		cells = {},
		playerCellCount = {},
	}
	platformStates[platform] = state
	return state
end

local function getOrCreateCell(state, key: string, part: BasePart, col: number, row: number)
	local cell = state.cells[key]
	if not cell then
		cell = {
			state = "pristine",
			part = part,
			col = col,
			row = row,
			occupants = {},
			count = 0,
			pendingExit = {},
			decayTimer = 0,
			popCount = 0,
			stepCount = 0,
			dissolveScheduled = false,
		}
		state.cells[key] = cell
	end
	return cell
end

-- Sends the sub-region part itself rather than a name path. The client cannot
-- resolve a GetFullName() string back to an Instance, and Instance references
-- replicate over a RemoteEvent for free.
local function replicate(platform: BasePart, cell, who: Player?)
	DeformationUpdate:FireAllClients({
		part = cell.part,
		col = cell.col,
		row = cell.row,
		state = cell.state,
		material = platformStates[platform] and platformStates[platform].material or nil,
		-- Bubble wrap needs the running pop index so the client knows WHICH
		-- bubble to flatten, rather than replaying the same generic tween.
		popCount = cell.popCount,
		-- HOW MANY TIMES THIS CELL HAS BEEN STOOD ON, for materials that fail in visible
		-- stages rather than all at once. Ice is the only one so far: it takes three
		-- steps in the same spot, and the player has to be able to SEE that the second
		-- one opened the crack further than the first, or the warning it is supposed to
		-- give is not a warning at all -- just a floor that drops without notice.
		stepCount = cell.stepCount,
		-- ...and WHICH SHEET it is popping, on a stacked platform. The client picks its
		-- bone prefix from this; without it a cell that has burst through to the lower
		-- layer would go on driving the flattened pockets above it and look inert.
		layer = cell.layer,
		-- WHO CAUSED IT, so each client can tell its own footsteps from everyone else's.
		-- Your own sounds play flat and unattenuated -- you cannot walk away from your own
		-- feet -- while other players' are positioned in the world. See AudioService.
		who = who,
	})
end

-- Applies the gameplay-side effect of standing on a material (speed,
-- friction, launch). Called once per genuine cell entry.
local function applyMaterialEffectOnEnter(player: Player, materialName: string?)
	if not materialName then
		return
	end
	local matDef = Materials[materialName]
	if not matDef then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if matDef.speedMultiplier then
		humanoid.WalkSpeed = Constants.DEFAULT_WALKSPEED * matDef.speedMultiplier
	end

	if matDef.frictionOverride then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CustomPhysicalProperties = PhysicalProperties.new(
					part.CustomPhysicalProperties and part.CustomPhysicalProperties.Density or 1,
					matDef.frictionOverride,
					0.5
				)
			end
		end
	end

end

-- Slime launch. Deliberately NOT part of applyMaterialEffectOnEnter: that runs
-- only on a genuine first occupancy of a cell, so standing on slime and jumping
-- never re-triggered it. This runs on every contact instead, rate-limited per
-- player.
--
-- The GDD's "only when falling (Vy < 0)" rule exists to stop chain-launching
-- while already ascending. Read literally it makes the mechanic unreachable:
-- walking onto slime gives Vy of about 0, so R1_SlimeLaunch (walk on, get
-- thrown across the gap) could never fire. The gate is therefore "not already
-- moving upward", which preserves the anti-chain intent and makes it work.
local LAUNCH_COOLDOWN = 0.35
local UPWARD_TOLERANCE = 0.5
local lastLaunchAt: { [Player]: number } = {}

-- HOW HIGH, TURNED INTO HOW FAST. `microBounceHeight` is a HEIGHT in studs -- the apex
-- you want the player to reach -- and the thing that has to be handed to the client is a
-- velocity. Ballistics, not taste: v = sqrt(2 g h).
--
-- Expressing it as a height is the right way round for a designer. "Bubble wrap should lob
-- you four studs" is a statement anyone can check by looking; "bubble wrap should give you
-- 39.6 studs per second" is only meaningful once you have done this arithmetic in your
-- head, and it silently becomes wrong the moment gravity changes.
local function bounceVelocity(height: number): number
	return math.sqrt(2 * Constants.GRAVITY * height)
end

local function tryLaunch(player: Player, materialName: string?)
	-- WHAT THIS MATERIAL DOES TO YOU VERTICALLY, if anything.
	--
	-- This was Slime-only and hardcoded to it, which is why `microBounceHeight` sat in
	-- MaterialConfig being read by nothing at all: bubble wrap declared a bounce and there
	-- was no code path that could ever have applied it. Both materials want the same thing
	-- -- an upward impulse on contact, once, not stacked -- and differ only in how big it
	-- is and whether it is described as a speed or a height.
	local matDef = materialName and Materials[materialName]
	if not matDef then
		return
	end
	local speed = matDef.launchVelocity
	if not speed and matDef.microBounceHeight then
		speed = bounceVelocity(matDef.microBounceHeight)
	end
	if not speed then
		return
	end

	-- PER MATERIAL, falling back to the shared floor. One cooldown for everything meant
	-- tuning how often a Needoh throws you also retuned bubble wrap, and those two want
	-- opposite things: bubble wrap should fire on every step it can, a dough bed should
	-- barely fire at all.
	local now = os.clock()
	local cooldown = matDef.bounceCooldown or LAUNCH_COOLDOWN
	if now - (lastLaunchAt[player] or 0) < cooldown then
		return
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not rootPart:IsA("BasePart") or not humanoid then
		return
	end

	local velocity = rootPart.AssemblyLinearVelocity
	if velocity.Y > UPWARD_TOLERANCE then
		return -- already ascending; do not stack launches
	end

	lastLaunchAt[player] = now

	-- Hand the impulse to the owning client instead of writing velocity here.
	-- The character assembly is network-owned by the player, so a server-side
	-- AssemblyLinearVelocity write is overwritten by the client's next physics
	-- update. The server still decides WHETHER to launch (authority over the
	-- trigger, the cooldown and the ascent check); the client only applies it.
	-- STILL THE `SlimeLaunch` REMOTE, and the name is now a lie worth explaining rather
	-- than a rename worth three more files to paste. The client handler is already
	-- material-agnostic -- it takes a number and writes it to the character's upward
	-- velocity -- so bubble wrap rides the same wire. If this ever gets a third caller,
	-- rename it to LaunchImpulse across Bootstrap, this file and the client bootstrap.
	SlimeLaunch:FireClient(player, speed)
end

local function resetMaterialEffect(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Constants.DEFAULT_WALKSPEED
	end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CustomPhysicalProperties = nil :: any
		end
	end
end

-- === Genuine enter / exit transitions ===

local function onPlayerEnterCell(platform: BasePart, state, cell, player: Player)
	cell.occupants[player] = true
	cell.count += 1
	state.playerCellCount[player] = (state.playerCellCount[player] or 0) + 1

	local matDef = Materials[state.material]

	-- COUNTED FIRST, BEFORE ANYTHING IS ANNOUNCED. The threshold test still lives further
	-- down with the collapse it triggers, but the counter itself has to run up here,
	-- because the replicate immediately below carries cell.stepCount to the client and it
	-- has to describe THIS footfall rather than the one before it.
	--
	-- Left where it was, the client saw 0 on the first step and 1 on the second, so ice
	-- drew its stage-one hairline twice and never showed the crack widening -- the exact
	-- warning the material exists to give. Every other field in that payload (state,
	-- popCount, layer) is already the post-entry value; this one was the odd one out.
	local steps = matDef and matDef.stepsToCollapse
	if steps and cell.state ~= "exhausted" then
		cell.stepCount = (cell.stepCount or 0) + 1
	end

	local announced = false
	if cell.state == "pristine" or cell.state == "decaying" then
		cell.state = "deformed"
		cell.decayTimer = 0
		replicate(platform, cell, player)
		announced = true
	end

	applyMaterialEffectOnEnter(player, state.material)

	-- GIVES WAY after a fixed duration of continuous contact. One timer per cell, not
	-- one per Touched event.
	--
	-- Keyed on the material HAVING a dissolveTime rather than on it being soap, which is
	-- what it used to test. Two materials collapse now and they collapse for different
	-- reasons -- soap dissolves, sand loses cohesion and crumbles -- but the mechanic is
	-- identical: stand here too long and the floor stops being floor.
	local dissolveTime = matDef and matDef.dissolveTime

	-- The one place a cell actually gives way, called from both triggers below.
	local function collapse()
		if cell.state == "exhausted" then
			return
		end
		-- SNAPSHOT BEFORE BREAKING IT. A hardcore restart has to put the platform back,
		-- and the pristine values differ per material -- a skinned platform's tile is a
		-- non-colliding sensor with a Floor child that does collide, a granular one is the
		-- other way round, and an overlay's slab is visible where everything else's is
		-- hidden. Recomputing all that on the way back is guesswork; recording it on the
		-- way out is exact.
		local floorPart = cell.part:FindFirstChild("Floor")
		local slabPart = cell.part.Parent
		cell.pristine = {
			tileCollide = cell.part.CanCollide,
			tileTouch = cell.part.CanTouch,
			floorCollide = (floorPart and floorPart:IsA("BasePart")) and floorPart.CanCollide or nil,
			slabCollide = (slabPart and slabPart:IsA("BasePart")) and slabPart.CanCollide or nil,
			slabTransparency = (slabPart and slabPart:IsA("BasePart")) and slabPart.Transparency or nil,
		}
		cell.state = "exhausted"
		-- A collapsed cell stops being floor: CanCollide off drops anyone standing on
		-- it. Previously only CanTouch was cleared, so the tile "dissolved" visually but
		-- still held your weight.
		cell.part.CanTouch = false
		cell.part.CanCollide = false
		-- On a SKINNED platform the tile is a pure sensor whose CanCollide is already
		-- false, and a separate Floor child carries the collision (see buildSubRegions in
		-- ChunkBuilder). Clearing the tile alone changes nothing there, so a collapsed
		-- cell would go on holding your weight on exactly the platforms that have a rig
		-- -- the hole would be visual only. This matters more now: sand is ALWAYS rigged.
		local floor = cell.part:FindFirstChild("Floor")
		if floor and floor:IsA("BasePart") then
			floor.CanCollide = false
		end
		-- AND THE SLAB, here rather than only at build time.
		--
		-- ChunkBuilder already leaves the slab non-colliding for any material that can
		-- dissolve, but that only takes effect on templates built SINCE that change --
		-- and a stale ChunkTemplates folder is the most common state this project is
		-- ever in, because the fix silently does nothing until both chunk folders are
		-- cleared. While the slab holds you, a "hole" is a 0.9-stud step down onto
		-- concrete and nothing more, which is exactly what standing on nothing looks
		-- like. Doing it again at collapse costs nothing and cannot be skipped.
		local slab = cell.part.Parent
		if slab and slab:IsA("BasePart") then
			slab.CanCollide = false
			-- AND IT STOPS BEING DRAWN, which matters for exactly one material.
			--
			-- For soap and sand the slab is already invisible, so this is a no-op and a
			-- collapsed cell reads as the hole it is. Bubble wrap is the exception: it is
			-- an OVERLAY, so its slab stays visible as the thing being wrapped -- and
			-- that made its collapse unreadable. The floor gave way exactly as intended
			-- and the player dropped through a solid-looking grey block, which does not
			-- read as "the platform failed", it reads as the game breaking.
			--
			-- Whole-platform rather than per-cell, because per-cell is not available: a
			-- rig cannot open a hole in itself (MeshId is fixed at import and a Bone
			-- carries only a CFrame), which is the same limit that keeps soap granular.
			-- By the time any cell here has been popped through, the sheet above it is
			-- comprehensively burst, so losing the body underneath reads as the platform
			-- going rather than as something arbitrary.
			slab.Transparency = 1
			for _, child in ipairs(slab:GetChildren()) do
				if child:IsA("BasePart") and child.Name:match("^CornerBevel") then
					child.CanCollide = false
				end
			end
		end
		replicate(platform, cell, player)
	end

	-- TWO TRIGGERS, because a clock alone made this nearly unreachable. The timer wants
	-- CONTINUOUS occupancy of one cell, and walking leaves a cell long before it fires,
	-- so in practice only standing still ever collapsed anything.
	--
	-- Kinetic sand does not fail because you stood on it, it fails because it has been
	-- WORKED. Counting footfalls is that: cross the same cell a few times and it goes,
	-- however briefly you were on it each time.
	if steps and cell.state ~= "exhausted" and (cell.stepCount or 0) >= steps then
		collapse()
	end

	-- The clock, for standing still. One timer per cell, not one per Touched event.
	if dissolveTime and not cell.dissolveScheduled and cell.state ~= "exhausted" then
		cell.dissolveScheduled = true
		task.delay(dissolveTime, function()
			cell.dissolveScheduled = false
			if cell.count > 0 then
				collapse()
			end
		end)
	end

	-- Bubble wrap: pops N times, then goes flat/neutral.
	--
	-- REPLICATES ON EVERY GENUINE ENTRY, which it did not used to. It announced only the
	-- two state transitions -- the first entry and the fourth -- and sent nothing for
	-- the two in between, so a cell popped twice and was then silent however often you
	-- crossed it.
	--
	-- That was survivable while the client flattened a fixed FRACTION of the cell's
	-- bubbles per event, because the two events between them covered the whole cell. It
	-- stopped being survivable when popping became geometric: the client now bursts
	-- whatever is under your FOOT, so a pocket you did not step near on entry one and
	-- entry four could never burst at all, while the cell spent its four counts anyway.
	-- The client needs to be told where you are, not merely that a threshold was passed.
	if state.material == "BubbleWrap" and cell.state ~= "exhausted" then
		-- HOW MANY SHEETS DEEP THIS PLATFORM IS. Read off the slab rather than off the
		-- material, because it is a property of the MESH: an ordinary sheet has one layer
		-- of pockets and a giant one has two, and they are the same material. Defaulting
		-- to 1 is what keeps every existing bubble wrap chunk behaving exactly as before.
		cell.layer = cell.layer or 1
		local layers = platform:GetAttribute("PopLayers") or 1

		if cell.popCount < Materials.BubbleWrap.popCount then
			cell.popCount += 1
		end
		if cell.popCount >= Materials.BubbleWrap.popCount then
			if cell.layer < layers then
				-- THROUGH THE TOP SHEET, NOT THROUGH THE FLOOR. The upper pockets under
				-- this cell are all burst, so the cell drops to the layer below and its
				-- budget starts again. The player is standing on the lower sheet now and
				-- can see it, which is the warning that the next pass is the last one.
				cell.layer += 1
				cell.popCount = 0
				replicate(platform, cell, player)
			else
				-- The last sheet has gone, so there is nothing left to stand on.
				-- `collapse` is what soap and sand already use: it clears the tile, the
				-- Floor child and the slab, so this is a real hole rather than a visual
				-- one.
				collapse()
			end
		elseif not announced then
			-- `announced` guards the double send: on a first entry the pristine ->
			-- deformed transition above has already gone out, and firing again here
			-- would burst the same pockets twice and double the tile's jolt.
			replicate(platform, cell, player)
		end
	end
end

local function onPlayerExitCell(platform: BasePart, state, cell, player: Player)
	cell.occupants[player] = nil
	cell.count = math.max(0, cell.count - 1)

	local remaining = (state.playerCellCount[player] or 1) - 1
	state.playerCellCount[player] = remaining > 0 and remaining or nil

	-- Only clear the movement effect once the player is off this platform
	-- entirely. Limbs routinely span two cells; clearing per-cell would make
	-- honey's slowdown flicker.
	if not state.playerCellCount[player] then
		resetMaterialEffect(player)
	end

	if cell.count == 0 and cell.state == "deformed" then
		cell.state = "decaying"
		local matDef = state.material and Materials[state.material]
		cell.decayTimer = matDef and matDef.decayDuration or Constants.DECAY_DURATION
		replicate(platform, cell, player)
	end
end

-- Registers Touched/TouchEnded on every SubRegion child part of a platform.
-- Stable platforms carry no Material attribute and nothing to deform, so they
-- are skipped entirely rather than replicating no-op state changes for the
-- ~40% of a level that is stable chunks -- including the opening chunk every
-- player spawns and idles on.
-- Puts every platform back to how it was built, WITHOUT rebuilding anything.
--
-- This is what a hardcore restart runs instead of tearing the level down and generating it
-- again. The rebuild worked, but it destroyed the geometry every OTHER player in the
-- server was standing on, so one person failing dropped everyone into the sea -- and then
-- their own kill planes fired, and in hardcore that restarted the level again.
--
-- Restoring in place harms nobody: another player mid-run gets their floor back, which is
-- the one side effect that cannot be a complaint. It is still not per-player -- the level
-- is one set of parts and there is no way to show two versions of it without building two
-- -- but the disruption drops from "everyone is teleported into the void" to "some bubbles
-- you had already popped are round again".
function DeformationService.restoreAll()
	for platform, state in pairs(platformStates) do
		for _, cell in pairs(state.cells) do
			local saved = cell.pristine
			if saved then
				cell.part.CanCollide = saved.tileCollide
				cell.part.CanTouch = saved.tileTouch
				local floorPart = cell.part:FindFirstChild("Floor")
				if floorPart and floorPart:IsA("BasePart") and saved.floorCollide ~= nil then
					floorPart.CanCollide = saved.floorCollide
				end
				local slabPart = cell.part.Parent
				if slabPart and slabPart:IsA("BasePart") then
					if saved.slabCollide ~= nil then
						slabPart.CanCollide = saved.slabCollide
					end
					if saved.slabTransparency ~= nil then
						slabPart.Transparency = saved.slabTransparency
					end
					for _, child in ipairs(slabPart:GetChildren()) do
						if child:IsA("BasePart") and child.Name:match("^CornerBevel") then
							child.CanCollide = saved.slabCollide ~= false
						end
					end
				end
				cell.pristine = nil
			end

			cell.state = "pristine"
			cell.popCount = 0
			cell.stepCount = 0
			cell.layer = 1
			cell.dissolveScheduled = false
			-- Announced, so the client springs the surface back: bubbles re-inflate, soap
			-- and sand come out of their collapsed pose. Without this the state is right on
			-- the server and the platform still LOOKS destroyed.
			--
			-- No `who`: a repair is not anybody's footstep.
			replicate(platform, cell)
		end
	end
end

function DeformationService.registerPlatform(platform: BasePart)
	if not platform:GetAttribute("Material") then
		return
	end

	local state = getOrCreatePlatformState(platform)

	for _, child in ipairs(platform:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^SubRegion_") then
			local col = child:GetAttribute("Col") :: number
			local row = child:GetAttribute("Row") :: number
			local key = SubRegionGrid.key(col, row)
			local cell = getOrCreateCell(state, key, child, col, row)

			child.Touched:Connect(function(hit: BasePart)
				local character = hit:FindFirstAncestorOfClass("Model")
				local player = character and Players:GetPlayerFromCharacter(character)
				if not player then
					return
				end

				-- Cancel any exit being held for this player.
				cell.pendingExit[player] = nil

				if not cell.occupants[player] then
					onPlayerEnterCell(platform, state, cell, player)
				end

				-- Runs on every contact, not just first occupancy.
				tryLaunch(player, state.material)
			end)

			child.TouchEnded:Connect(function(hit: BasePart)
				local character = hit:FindFirstAncestorOfClass("Model")
				local player = character and Players:GetPlayerFromCharacter(character)
				if not player or not cell.occupants[player] then
					return
				end

				exitTokenCounter += 1
				local token = exitTokenCounter
				cell.pendingExit[player] = token

				task.delay(EXIT_GRACE, function()
					if cell.pendingExit[player] ~= token then
						return -- re-touched, or superseded by a newer exit
					end
					cell.pendingExit[player] = nil
					if cell.occupants[player] then
						onPlayerExitCell(platform, state, cell, player)
					end
				end)
			end)
		end
	end
end

-- Clean up occupancy when a player leaves so cells cannot be held forever.
Players.PlayerRemoving:Connect(function(player: Player)
	lastLaunchAt[player] = nil
	for platform, state in pairs(platformStates) do
		for _, cell in pairs(state.cells) do
			cell.pendingExit[player] = nil
			if cell.occupants[player] then
				onPlayerExitCell(platform, state, cell, player)
			end
		end
		state.playerCellCount[player] = nil
	end
end)

-- Decay tick: independent per sub-region. Reverting to "pristine" also
-- re-inflates bubble wrap (popCount resets) per the GDD.
RunService.Heartbeat:Connect(function(dt: number)
	for platform, state in pairs(platformStates) do
		for _, cell in pairs(state.cells) do
			if cell.state == "decaying" then
				cell.decayTimer -= dt
				if cell.decayTimer <= 0 then
					cell.state = "pristine"
					cell.decayTimer = 0
					if state.material == "BubbleWrap" then
						cell.popCount = 0
					end
					-- AND THE FOOTFALL COUNT, which nothing reset. A cell that has decayed
					-- is pristine by every other measure -- it looks repaired and it reports
					-- itself repaired -- but it kept the steps already spent on it, so a
					-- three-step material was one step from collapsing forever after. Ice
					-- that has visibly refrozen has to be as strong as ice that was never
					-- stood on, or the warning it gives is a lie the second time round.
					cell.stepCount = 0
					-- Soap that dissolved does not come back in current scope;
					-- only pre-dissolve "deformed" visuals decay. Exhausted soap
					-- is permanent for that server's level instance.
					--
					-- NO `who`: this runs in the decay sweep, which has no player at all --
					-- passing one here would have been a nil global. A surface relaxing is
					-- nobody's footstep, and it must not be attributed to one.
					replicate(platform, cell)
				end
			elseif cell.state == "exhausted" and state.material == "BubbleWrap" then
				-- Bubble wrap re-inflates via its own decay path once no
				-- occupants remain; reuse the decaying branch by seeding a timer.
				if cell.count == 0 and cell.decayTimer == 0 then
					cell.decayTimer = Materials.BubbleWrap.decayDuration
					cell.state = "decaying"
				end
			end
		end
	end
end)

-- Fail-state teleports never reset any platform's deformation state --
-- enforced simply by not touching platformStates from teleport logic
-- (see PlayerStateService / LevelService).

return DeformationService
