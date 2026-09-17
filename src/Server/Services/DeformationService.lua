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
local function replicate(platform: BasePart, cell, who: Player?, cause: string?)
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
		-- CLAY AND SALT, which move material between cells rather than failing where they are
		-- stood on. How far this cell has gone down, how much its neighbours have pushed into
		-- it, which way it leans, and what this update IS: a foot landing on it ("step"), a
		-- foot standing on it ("creep"), or a neighbour's weight arriving ("push"). A cell
		-- nobody touched still has to be redrawn, and the renderer must not stamp a footprint
		-- or play a footstep for it. See DISPLACEMENT below.
		depth = cell.depth,
		push = cell.push,
		lean = cell.lean,
		cause = cause,
		-- A KEYPAD COMBO landing on this press, so the pad lights up from it. See KEYPADS.
		combo = cell.combo,
		-- HOW FAR A NEEDOH IS SQUEEZED under whoever is standing still on it, 0 to 1. See NEEDOH.
		charge = cell.charge,
		-- CHARCOAL: "smoulder", "burning", "ash", or nothing for cold coal. See CHARCOAL.
		fire = cell.fire,
		-- OOBLECK: how deep the player on this cell is wading, 0 to 1, and for a hardening shock the
		-- cell it spread from, as (col, row). See OOBLECK.
		wade = cell.wade,
		origin = cell.origin,
	})
end

-- ===== KEYPADS: switches, surges, charges and springs =====
--
-- A keypad cell carries one of three switches. ChunkBuilder writes which on the tile as `Switch`, and
-- every one of them does something:
--
--   CLICKY (cyan) throws you forward, and the SURGE carries off the pad for `surgeLinger`. Clicky
--   presses in a row, each within `streakWindow` of the last, build a streak: at `comboAt` the surge
--   becomes a combo, and a clicky press in every row of the pad is a circuit.
--
--   LINEAR (violet) is a CAPACITOR. Every violet press stores a charge, up to `capacitorMax`, held
--   for `capacitorHold` from the last one, and the next clicky press spends the lot: `dischargeSpeed`
--   more surge and `dischargeLinger` longer for each charge, never past `surgeCap`. The violet columns
--   either side of the lane are worth stepping out onto.
--
--   TACTILE (pink) is a SPRING. With a pink button under you your jump is `springJump[1]` times its
--   height; jump off pink, land back on pink within `springChain`, and the next jump is a level
--   higher. Walking off, or landing on anything else, puts your jump back. See SPRINGS below.
--
-- A surge you already have carries across violet and pink alike, and pressing more buttons never
-- takes any of it away: a press keeps whichever surge is bigger and lasts longer.
--
-- `effectTokens` changes on every material effect, so a surge carried off a pad is ended by its own
-- timer only when nothing else has taken over the player's speed in the meantime.
local surges: { [Player]: { multiplier: number, expires: number } } = {}
-- count, last press time, the rows covered on `slab`, and which light-up has been shown.
local streaks: { [Player]: any } = {}
local effectTokens: { [Player]: number } = {}
-- The charges a player's violet presses have stored, and until when.
local capacitors: { [Player]: { count: number, expires: number } } = {}
-- A player's armed spring: its level, how many pink cells they are standing on, when they last left
-- one, and their jump as it was before any spring touched it. See SPRINGS.
local springs: { [Player]: { level: number, on: number, left: number, jumpPower: number, jumpHeight: number } } = {}

-- A clicky press. Returns "combo" on the press that makes a combo and "circuit" on the press that
-- completes the lane -- a clicky press in EVERY row of this pad inside one streak -- which is when the
-- pad lights up or overloads; the presses after it keep the surge without lighting it again.
--
-- It also DISCHARGES the capacitor: every stored charge goes into this press's surge, and how many went
-- is left on the cell as `charge`, for the renderer to arc them out of the player into the button.
local function pressClicky(matDef, cell, player: Player): string?
	local now = os.clock()
	local slab = cell.part.Parent
	local streak = streaks[player]
	if streak and now - streak.last <= (matDef.streakWindow or 0.8) and streak.slab == slab then
		streak.count += 1
		streak.last = now
	else
		streak = { count = 1, last = now, rows = {}, slab = slab, shown = nil }
		streaks[player] = streak
	end
	streak.rows[cell.row] = true
	local covered = 0
	for _ in pairs(streak.rows) do
		covered += 1
	end
	local rows = if slab then slab:GetAttribute("GridRows") else nil
	local circuit = typeof(rows) == "number" and covered >= rows
	local combo = streak.count >= (matDef.comboAt or 3)
	local speeds = matDef.switchSpeeds
	local stored = capacitors[player]
	local spent = if stored and stored.expires > now then stored.count else 0
	capacitors[player] = nil
	cell.charge = if spent > 0 then spent else nil
	local multiplier = math.min((if circuit then matDef.circuitSpeed or 1.4
		elseif combo then matDef.comboSpeed or 1.3
		else (speeds and speeds.clicky) or 1.2) + spent * (matDef.dischargeSpeed or 0), matDef.surgeCap or 1.6)
	local expires = now + (if circuit then matDef.circuitLinger or 3
		elseif combo then matDef.comboLinger or 2
		else matDef.surgeLinger or 1) + spent * (matDef.dischargeLinger or 0)
	-- NEVER LESS THAN THE SURGE ALREADY RUNNING. Without this the plain press straight after a
	-- discharge would throw the discharge away, and it is the one that always comes next on a lane.
	local running = surges[player]
	if running and running.expires > now then
		multiplier = math.max(multiplier, running.multiplier)
		expires = math.max(expires, running.expires)
	end
	surges[player] = { multiplier = multiplier, expires = expires }
	if circuit and streak.shown ~= "circuit" then
		streak.shown = "circuit"
		return "circuit"
	elseif combo and not circuit and streak.shown == nil then
		streak.shown = "combo"
		return "combo"
	end
	return nil
end

-- A violet press: one more charge in the capacitor, and its hold starts again. Returns how many it holds.
local function pressLinear(matDef, player: Player): number
	local now = os.clock()
	local stored = capacitors[player]
	local count = if stored and stored.expires > now then stored.count else 0
	count = math.min(count + 1, matDef.capacitorMax or 3)
	capacitors[player] = { count = count, expires = now + (matDef.capacitorHold or 4) }
	return count
end

-- ===== NEEDOH: the squeeze you choose =====
--
-- The mini jumps are gone. A Needoh does not throw you; it GIVES, for as long as you squeeze it. Stand
-- still on the bed and after `chargeAfter` the dough starts sinking under you, fully squeezed after
-- `chargeTime` more; jump out of the hollow and the jump is up to `chargeJump` times its normal
-- height. Walk and nothing builds.
--
-- The jump itself is the player's own, on their own client. This only raises JumpHeight and JumpPower
-- -- whichever the humanoid is using -- in CHARGE_STEPS steps rather than every frame, and puts both
-- back the moment the player leaves the bed. The steps are also what everyone else sees: each one is
-- announced on the cells the player is standing on, as `charge`.
local STILL_SPEED = 3
local CHARGE_STEPS = 4
local charges: { [Player]: { still: number, shown: number, frame: number, jumpPower: number, jumpHeight: number } } = {}
-- Counts heartbeats, so a player standing across two Needoh beds charges once a frame, not twice.
local heartbeatFrame = 0

local function restoreJump(player: Player)
	local charge = charges[player]
	if not charge then
		return
	end
	charges[player] = nil
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.JumpPower = charge.jumpPower
		humanoid.JumpHeight = charge.jumpHeight
	end
end

local function chargeNeedoh(platform: BasePart, state, def, dt: number)
	for player in pairs(state.playerCellCount) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and root:IsA("BasePart") and humanoid) then
			continue
		end
		local charge = charges[player]
		if not charge then
			-- The jump as it was before the bed touched it, so it goes back exactly -- from under a keypad
			-- spring, if one is still armed.
			local sprung = springs[player]
			charge = {
				still = 0,
				shown = 0,
				frame = 0,
				jumpPower = if sprung then sprung.jumpPower else humanoid.JumpPower,
				jumpHeight = if sprung then sprung.jumpHeight else humanoid.JumpHeight,
			}
			charges[player] = charge
		end
		if charge.frame == heartbeatFrame then
			continue
		end
		charge.frame = heartbeatFrame

		local velocity = root.AssemblyLinearVelocity
		if Vector3.new(velocity.X, 0, velocity.Z).Magnitude < STILL_SPEED and math.abs(velocity.Y) < STILL_SPEED then
			charge.still += dt
		else
			charge.still = 0
		end
		local level = math.clamp((charge.still - (def.chargeAfter or 0.25)) / (def.chargeTime or 1), 0, 1)
		local shown = math.floor(level * (CHARGE_STEPS - 1) + 0.5) / (CHARGE_STEPS - 1)
		if shown ~= charge.shown then
			charge.shown = shown
			local height = 1 + ((def.chargeJump or 2) - 1) * shown
			humanoid.JumpHeight = charge.jumpHeight * height
			-- Jump height goes with the square of launch speed, so power takes the root.
			humanoid.JumpPower = charge.jumpPower * math.sqrt(height)
			for _, cell in pairs(state.cells) do
				if cell.occupants[player] and cell.state ~= "exhausted" then
					cell.charge = shown
					replicate(platform, cell, player, "charge")
				end
			end
		end
	end
end

-- ===== SPRINGS: the pink switches =====
--
-- A pink button under you raises your jump to `springJump[level]` times its height, through JumpHeight and
-- JumpPower the way a Needoh's squeeze does. Jump off pink and the spring stays armed in the air; land on
-- pink again within `springChain` of leaving it and that is a BOUNCE, one level up, to the top of
-- `springJump`. Walking off pink, landing on anything else, or `springChain` passing with no landing at all
-- puts the jump back exactly as it was.
--
-- The jump is the player's own, on their own client, so a new level arrives a moment after the landing
-- that earned it. A bounce taken quicker than that still jumps at the level before, never below the first.
-- A player who left pink rising this fast, in studs a second, JUMPED off it: the exit is heard
-- EXIT_GRACE after the feet leave, when even an unboosted jump is still going up at about 11.
local SPRING_RISING = 6
-- Or with this much air between the root and the button, for an exit the occupancy audit noticed late,
-- near the top of the jump. A standing root is about 3 above; walking up onto the dome keypad's raised
-- violet cells puts it about 4.75 above the pink cell left behind, which must not count as a launch.
local SPRING_ABOVE = 6

local function releaseSpring(player: Player)
	local spring = springs[player]
	if not spring then
		return
	end
	springs[player] = nil
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.JumpPower = spring.jumpPower
		humanoid.JumpHeight = spring.jumpHeight
	end
end

-- A foot arriving on a pink cell. Returns the level the spring is at now.
local function stepOnSpring(matDef, player: Player): number?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local heights = matDef.springJump or { 1.5 }
	local spring = springs[player]
	if not spring then
		-- The jump as it was, so it goes back exactly -- from under a Needoh's squeeze, if one holds it.
		local held = charges[player]
		spring = {
			level = 0,
			on = 0,
			left = 0,
			jumpPower = if held then held.jumpPower else humanoid.JumpPower,
			jumpHeight = if held then held.jumpHeight else humanoid.JumpHeight,
		}
		springs[player] = spring
	end
	if spring.on == 0 then
		-- Arriving from the air on a spring still armed, inside the window: a bounce.
		local bounced = spring.level > 0 and os.clock() - spring.left <= (matDef.springChain or 1)
		spring.level = if bounced then math.min(spring.level + 1, #heights) else 1
		local height = heights[spring.level]
		humanoid.JumpHeight = spring.jumpHeight * height
		-- Jump height goes with the square of launch speed, so power takes the root.
		humanoid.JumpPower = spring.jumpPower * math.sqrt(height)
	end
	spring.on += 1
	return spring.level
end

-- A foot leaving a pink cell. Returns the level it launched at if the player jumped off it, so the pad
-- can throw them up; walking off puts the jump back.
local function leaveSpring(player: Player, cell): number?
	local spring = springs[player]
	if not spring then
		return nil
	end
	spring.on = math.max(0, spring.on - 1)
	if spring.on > 0 then
		return nil
	end
	spring.left = os.clock()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local above = cell.part.CFrame:PointToObjectSpace(root.Position).Y - cell.part.Size.Y / 2
		if root.AssemblyLinearVelocity.Y > SPRING_RISING or above > SPRING_ABOVE then
			return spring.level
		end
	end
	releaseSpring(player)
	return nil
end

-- A spring armed in the air that never came down on pink: the jump goes back when the window closes.
local function settleSprings(now: number)
	local def = Materials.Buttons
	local chain = def and def.springChain or 1
	for player, spring in pairs(springs) do
		if spring.on == 0 and now - spring.left > chain then
			releaseSpring(player)
		end
	end
end

-- ===== CHARCOAL: the grill that catches =====
--
-- A foot on cold charcoal lights it (`fire` = "smoulder"). After igniteAfter it is burning; spreadAfter
-- into that it tries to light each cold neighbour, with spreadChance each; burnFor after it caught it
-- is ash, and the cell gives way. A foot on burning coal stamps it down, taking stompBurn off what it
-- has left. regrowAfter after it gave way a fresh coal is back in the hole. All server time: the
-- clients only draw the state they are sent. The ticking is burnCharcoal, further down.

-- ===== OOBLECK: stamp it hard =====
--
-- Every player on an oobleck pool wades: `level` rises by wadeStill a second standing and wadeMoving
-- moving, drags their speed by up to wadeDrag, and at 1 the cells under them give way. A LANDING --
-- a fall faster than shockFrom, remembered for FALL_MEMORY because the landing itself is what zeroes
-- it -- hardens the whole pool for shockTime, and a hard pool drains everyone's wade. Announced in
-- WADE_STEPS steps rather than every frame. The ticking is wadeOobleck, further down.
local FALL_MEMORY = 0.35
local WADE_STEPS = 4
local lowestFall: { [Player]: { speed: number, at: number } } = {}
local wades: { [Player]: { level: number, shown: number, frame: number } } = {}

-- The whole pool, hard, spreading from the cell that was landed on.
local function shockOobleck(platform: BasePart, state, def, landed)
	state.hardUntil = os.clock() + (def.shockTime or 1.2)
	local origin = Vector2.new(landed.col, landed.row)
	for _, cell in pairs(state.cells) do
		if cell.state ~= "exhausted" then
			cell.origin = origin
			replicate(platform, cell, nil, "shock")
			cell.origin = nil
		end
	end
end

-- Applies the gameplay-side effect of standing on a material (speed,
-- friction, launch). Called once per genuine cell entry.
local function applyMaterialEffectOnEnter(player: Player, materialName: string?, cell: any?)
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

	-- ANY MATERIAL TAKES YOUR SPEED OVER, including from a surge carried off a keypad.
	effectTokens[player] = (effectTokens[player] or 0) + 1
	-- AND A SPRING ENDS ON ANYTHING BUT PINK. A pink press has already counted itself on by now, so this
	-- only lets go of a spring nobody is standing on. See SPRINGS.
	local spring = springs[player]
	if spring and spring.on == 0 then
		releaseSpring(player)
	end
	local speeds = matDef.switchSpeeds
	if not speeds and surges[player] then
		surges[player] = nil
		streaks[player] = nil
		if not matDef.speedMultiplier then
			humanoid.WalkSpeed = Constants.DEFAULT_WALKSPEED
		end
	end

	if matDef.speedMultiplier then
		local multiplier = matDef.speedMultiplier
		-- PACKED SALT IS FIRM FOOTING. Loose crystals roll under you and a cell trodden flat does
		-- not, so the speed comes back toward normal with every step that packed the cell you are
		-- on. The reward half of the material, and what makes your own trail worth keeping to.
		if matDef.displacement == "brine" and cell and matDef.displaceSteps then
			multiplier += (1 - multiplier) * math.clamp((cell.depth or 0) / matDef.displaceSteps, 0, 1)
		end
		-- CHARCOAL: burning coal is hot underfoot, so you hurry. See CHARCOAL.
		if matDef.hotSpeed and cell and cell.fire == "burning" then
			multiplier = matDef.hotSpeed
		end
		-- OOBLECK: the deeper you are wading, the more it holds your legs. See OOBLECK.
		if matDef.wadeDrag then
			local wade = wades[player]
			multiplier *= 1 - matDef.wadeDrag * (if wade then wade.shown else 0)
		end
		-- A KEYPAD SWITCH, cell by cell. See KEYPADS above.
		local switch = if speeds and cell then cell.part:GetAttribute("Switch") else nil
		if speeds and switch then
			local surge = surges[player]
			if switch == "clicky" then
				multiplier = if surge then surge.multiplier else speeds.clicky or multiplier
			elseif surge and surge.expires > os.clock() then
				-- Across violet and pink alike: neither costs you a surge.
				multiplier = surge.multiplier
			else
				multiplier = speeds[switch] or speeds.linear or multiplier
			end
		end
		humanoid.WalkSpeed = Constants.DEFAULT_WALKSPEED * multiplier
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
	restoreJump(player)
	wades[player] = nil
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local surge = surges[player]
		local now = os.clock()
		if surge and surge.expires > now then
			-- A SURGE CARRIES OFF THE PAD. It runs out on its own timer, unless another material
			-- has taken the player's speed first -- which changes the token and cancels this.
			humanoid.WalkSpeed = Constants.DEFAULT_WALKSPEED * surge.multiplier
			local token = (effectTokens[player] or 0) + 1
			effectTokens[player] = token
			task.delay(surge.expires - now, function()
				if effectTokens[player] ~= token then
					return
				end
				surges[player] = nil
				if humanoid.Parent then
					humanoid.WalkSpeed = Constants.DEFAULT_WALKSPEED
				end
			end)
		else
			surges[player] = nil
			humanoid.WalkSpeed = Constants.DEFAULT_WALKSPEED
		end
	end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CustomPhysicalProperties = nil :: any
		end
	end
end

-- === Collapse ===
--
-- The one place a cell gives way. Lifted out of onPlayerEnterCell, where it was a closure over
-- the player who stepped on the cell, because clay and salt break cells NOBODY is standing on:
-- a clay lip tears off beside you and a salt plate sinks next to your trail. `who` is whoever's
-- weight did it, for the sound, or nil.
local function collapseCell(platform: BasePart, cell, who: Player?)
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
	local reachFound = cell.part:FindFirstChild("Reach")
	local reachPart = if reachFound and reachFound:IsA("BasePart") then reachFound else nil
	local slabPart = cell.part.Parent
	cell.pristine = {
		tileCollide = cell.part.CanCollide,
		tileTouch = cell.part.CanTouch,
		reachTouch = if reachPart then reachPart.CanTouch else nil,
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
	if reachPart then
		reachPart.CanTouch = false
	end
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
	replicate(platform, cell, who)
end

-- ===== DISPLACEMENT: clay and salt =====
--
-- Every other material answers a footfall on the cell you stepped on, and only there: it sinks,
-- counts, cracks or gives way where you are. These two MOVE MATERIAL. What goes down under your
-- foot has to go somewhere, and where it goes is into the cells around it -- which is the whole
-- mechanic of both, and the whole risk.
--
-- CLAY SQUEEZES OUT. A step sinks the cell and pushes that clay toward the nearest free side of the
-- slab. A cell with a neighbour on both sides takes it as a ridge; a cell at the edge takes it as a
-- LIP, curling out over the side, and a lip that reaches displaceLimit tears off and drops away with
-- whoever is standing on it. The next cell in is then the edge. Stepping on a ridge flattens it and
-- sends its clay on outward, so trampling the middle of a slab builds ridges that eat its sides.
--
-- SALT SITS ON BRINE. A step packs the crust under you -- lower, firmer, faster -- and packing it
-- harder, from displaceFrom on, squeezes the brine from under it into the unpacked crust around it.
-- That crust heaves: one push cracks a plate, displaceTilt lift and tilt it, displaceLimit break it
-- and it sinks, and a plate left floating sinks anyway after sinkAfter. A tilted plate will not take
-- a foot. So your trail gets better with every pass while the crust beside it breaks up, and a
-- player who stands still packs themselves onto an island.
--
-- STANDING STILL COUNTS. Every creepEvery seconds an occupied cell is pressed again.
--
-- `depth`, `push` and `lean` are shared by the two and mean the same thing to the renderer: how far
-- the cell has gone down, how much has been pushed into it, and which way it leans.

-- Lip a step on a ridge carries on outward with it.
local CLAY_CARRY = 1
-- Seconds before the cell inside a torn lip checks whether it is overhanging now. A beat, so a side
-- goes in stages you can see rather than all at once.
local CLAY_CASCADE = 0.6

local ORTHOGONAL = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

-- The live cell at a grid position: nil off the slab, and nil where the cell has gone.
local function cellAt(state, col: number, row: number)
	if col < 1 or row < 1 or col > state.grid.cols or row > state.grid.rows then
		return nil
	end
	local other = state.cells[SubRegionGrid.key(col, row)]
	if not other or other.state == "exhausted" then
		return nil
	end
	return other
end

-- Cells from this one to open air across the slab, in one direction.
local function toFreeSide(state, cell, step: number): number
	local distance = 1
	while cellAt(state, cell.col + step * distance, cell.row) do
		distance += 1
	end
	return distance
end

-- The side a clay cell's lip hangs over: -1 or 1, or 0 while it has a neighbour on both sides.
local function overhang(state, cell): number
	if not cellAt(state, cell.col - 1, cell.row) then
		return -1
	elseif not cellAt(state, cell.col + 1, cell.row) then
		return 1
	end
	return 0
end

-- Which way a clay cell leans, in world space: out over its free side, or not at all.
local function clayLean(platform: BasePart, state, cell): Vector3?
	local side = overhang(state, cell)
	if side == 0 then
		return nil
	end
	return platform.CFrame.RightVector * side
end

local function tearClay(platform: BasePart, state, cell, who: Player?)
	local def = Materials[state.material]
	local limit = def and def.displaceLimit or 3
	if cell.state == "exhausted" or (cell.push or 0) < limit or overhang(state, cell) == 0 then
		return
	end
	collapseCell(platform, cell, who)
	-- THE NEXT CELL IN IS THE EDGE NOW, and a ridge pushed high by trampling tears in its turn.
	task.delay(CLAY_CASCADE, function()
		for _, step in ipairs({ -1, 1 }) do
			local inner = cellAt(state, cell.col + step, cell.row)
			if inner then
				inner.lean = clayLean(platform, state, inner)
				replicate(platform, inner, nil, "push")
				tearClay(platform, state, inner, nil)
			end
		end
	end)
end

local function squeezeClay(platform: BasePart, state, cell, who: Player?, cause: string)
	local def = Materials[state.material]
	cell.depth = math.min((cell.depth or 0) + 1, def.displaceSteps or 3)
	cell.push = cell.push or 0

	-- TOWARD THE NEAREST OPEN SIDE, and split both ways down the exact middle.
	local left, right = toFreeSide(state, cell, -1), toFreeSide(state, cell, 1)
	local sides = if left < right then { -1 } elseif right < left then { 1 } else { -1, 1 }
	local share = 1 / #sides

	-- A STEP ON A RIDGE FLATTENS IT, and its clay goes on outward with the rest. Not at an edge,
	-- where there is nowhere further for it to go than over.
	local carry = 0
	if overhang(state, cell) == 0 then
		carry = math.min(cell.push, CLAY_CARRY)
		cell.push -= carry
	end

	local pushed = {}
	for _, side in ipairs(sides) do
		local target = cellAt(state, cell.col + side, cell.row)
		if target then
			target.push = (target.push or 0) + (1 + carry) * share
			target.lean = clayLean(platform, state, target)
			table.insert(pushed, target)
		else
			-- Open air on this side: the clay goes out over this cell's own edge.
			cell.push += share
		end
	end
	cell.lean = clayLean(platform, state, cell)

	replicate(platform, cell, who, cause)
	for _, target in ipairs(pushed) do
		replicate(platform, target, who, "push")
	end
	tearClay(platform, state, cell, who)
	for _, target in ipairs(pushed) do
		tearClay(platform, state, target, who)
	end
end

local function packSalt(platform: BasePart, state, cell, who: Player?, cause: string)
	local def = Materials[state.material]
	cell.depth = cell.depth or 0
	cell.push = cell.push or 0

	-- A HEAVED PLATE IS FLOATING ON BRINE, and it will not take a foot.
	if cell.depth == 0 and cell.push >= (def.displaceTilt or 2) then
		collapseCell(platform, cell, who)
		return
	end
	if cell.depth >= (def.displaceSteps or 3) then
		-- Packed as hard as it goes. Still a step and still a crunch, with nothing left under it.
		replicate(platform, cell, who, cause)
		return
	end

	cell.depth += 1
	cell.push = 0
	cell.lean = nil
	cell.floating = 0
	replicate(platform, cell, who, cause)

	-- THE FIRST STEP ONLY CRUSHES THE CRYSTALS ON TOP. See displaceFrom in MaterialConfig.
	if cell.depth < (def.displaceFrom or 1) then
		return
	end
	for _, offset in ipairs(ORTHOGONAL) do
		local other = cellAt(state, cell.col + offset[1], cell.row + offset[2])
		-- PACKED CRUST HAS NO BRINE UNDER IT, so a trail, once made, stays made.
		if other and (other.depth or 0) == 0 then
			other.push = (other.push or 0) + 1
			local away = other.part.Position - cell.part.Position
			away = Vector3.new(away.X, 0, away.Z)
			if away.Magnitude > 0.01 then
				other.lean = (other.lean or Vector3.zero) + away.Unit
			end
			if other.push >= (def.displaceLimit or 3) then
				collapseCell(platform, other, who)
			else
				replicate(platform, other, who, "push")
			end
		end
	end
end

local function displace(platform: BasePart, state, cell, who: Player?, cause: string)
	if cell.state == "exhausted" then
		return
	end
	local def = state.material and Materials[state.material]
	local kind = def and def.displacement
	if kind == "squeeze" then
		squeezeClay(platform, state, cell, who, cause)
	elseif kind == "brine" then
		packSalt(platform, state, cell, who, cause)
	end
end

-- A TALLER SENSOR for the two materials whose floor moves UP as well as down.
--
-- Every other surface only ever sinks its collider, so a foot stays inside the thin tile that
-- senses it. A clay ridge or a heaved salt plate lifts the collider ABOVE that tile, and a player
-- standing on one would stop touching the sensor under them: no occupancy, no squeeze, and an exit
-- reported for someone who never left. This spans everything a clay or salt floor moves through.
local REACH_BELOW = 1.8
local REACH_ABOVE = 2.6

local function reachFor(tile: BasePart): BasePart
	local existing = tile:FindFirstChild("Reach")
	if existing and existing:IsA("BasePart") then
		return existing
	end
	local reach = Instance.new("Part")
	reach.Name = "Reach"
	reach.Size = Vector3.new(tile.Size.X, REACH_BELOW + REACH_ABOVE, tile.Size.Z)
	reach.CFrame = tile.CFrame * CFrame.new(0, tile.Size.Y / 2 + (REACH_ABOVE - REACH_BELOW) / 2, 0)
	reach.Anchored = true
	reach.CanCollide = false
	reach.CanQuery = false
	reach.CanTouch = true
	reach.CastShadow = false
	reach.Transparency = 1
	reach.Parent = tile
	return reach
end

-- === Genuine enter / exit transitions ===

local function onPlayerEnterCell(platform: BasePart, state, cell, player: Player)
	cell.occupants[player] = true
	cell.count += 1
	state.playerCellCount[player] = (state.playerCellCount[player] or 0) + 1

	local matDef = Materials[state.material]

	-- CLAY AND SALT MOVE MATERIAL rather than counting steps or running a clock, so they take their
	-- own path. See DISPLACEMENT above.
	if matDef and matDef.displacement then
		cell.creep = 0
		if cell.state == "pristine" or cell.state == "decaying" then
			cell.state = "deformed"
			cell.decayTimer = 0
		end
		displace(platform, state, cell, player, "step")
		applyMaterialEffectOnEnter(player, state.material, cell)
		return
	end

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

	-- A KEYPAD PRESS is counted before it is announced, so the announcement can carry what it did: a
	-- clicky press its combo and the charge it spent, a violet press the charge it stored, a pink press
	-- its spring's level. See KEYPADS.
	local switch = if matDef and matDef.switchSpeeds then cell.part:GetAttribute("Switch") else nil
	if switch == "clicky" then
		cell.combo = pressClicky(matDef, cell, player)
	elseif switch == "linear" then
		cell.charge = pressLinear(matDef, player)
	elseif switch == "tactile" then
		cell.charge = stepOnSpring(matDef, player)
	end

	-- CHARCOAL CATCHES under a foot, and a foot on burning coal stamps it down. See CHARCOAL.
	local fireBefore = cell.fire
	if matDef and matDef.igniteAfter and cell.state ~= "exhausted" then
		if not cell.fire then
			cell.fire = "smoulder"
			cell.fireAt = os.clock()
		elseif cell.fire == "burning" then
			cell.fireAt -= matDef.stompBurn or 0.5
		end
	end
	-- OOBLECK: a landing hardens the pool, and a foot arriving on a new cell arrives as deep as its
	-- player is wading. See OOBLECK.
	if matDef and matDef.shockFrom then
		local fall = lowestFall[player]
		if fall and fall.speed < -matDef.shockFrom and os.clock() - fall.at <= FALL_MEMORY then
			shockOobleck(platform, state, matDef, cell)
			-- Spent: a landing across two cells is one landing.
			fall.speed = 0
		end
		local wade = wades[player]
		cell.wade = if wade then wade.shown else 0
	end

	local announced = false
	if cell.state == "pristine" or cell.state == "decaying" then
		cell.state = "deformed"
		cell.decayTimer = 0
		replicate(platform, cell, player)
		announced = true
	end
	cell.combo = nil
	if switch then
		cell.charge = nil
	end
	-- A coal that caught under a cell already announced still has to be shown catching.
	if not announced and cell.fire ~= fireBefore then
		replicate(platform, cell, player)
	end

	applyMaterialEffectOnEnter(player, state.material, cell)

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
		collapseCell(platform, cell, player)
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

	-- OFF A PINK BUTTON, by jumping or by walking. See SPRINGS.
	local matDef = state.material and Materials[state.material]
	local sprang = if matDef and matDef.switchSpeeds and cell.part:GetAttribute("Switch") == "tactile"
		then leaveSpring(player, cell)
		else nil

	-- Only clear the movement effect once the player is off this platform
	-- entirely. Limbs routinely span two cells; clearing per-cell would make
	-- honey's slowdown flicker.
	if not state.playerCellCount[player] then
		resetMaterialEffect(player)
	end

	if cell.count == 0 then
		cell.creep = 0
		cell.charge = nil
	end
	if cell.count == 0 and cell.state == "deformed" then
		cell.state = "decaying"
		cell.decayTimer = matDef and matDef.decayDuration or Constants.DECAY_DURATION
		-- A LAUNCH off a spring goes out as one, with its level, so the pad throws the jumper up.
		cell.charge = sprang
		replicate(platform, cell, player, if sprang then "spring" else nil)
		cell.charge = nil
	end
end

-- ===== OCCUPANCY AUDIT =====
--
-- A cell keeps its occupants until TouchEnded says they have gone, and TouchEnded is not guaranteed:
-- a quick step, a jump, a teleport or a respawn can all leave without one. A cell holding a ghost
-- stays "deformed" for good -- a keypad's buttons held down with nobody on them, which is what the
-- middle of a keypad looked like in a screenshot; a clay cell squeezing itself; a Needoh charging for
-- nobody. So every AUDIT_EVERY seconds each occupied cell checks that its occupants are still near it.
local AUDIT_EVERY = 0.25
-- Studs past the cell's edge a root can be and still be on it: a player standing across two cells
-- has their root over the line between them.
local AUDIT_REACH = 2.5
local AUDIT_HEIGHT = 9
local auditAt = 0

local function auditOccupants(platform: BasePart, state)
	for _, cell in pairs(state.cells) do
		if cell.count > 0 then
			local half = cell.part.Size * 0.5
			for player in pairs(cell.occupants) do
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				local gone = true
				if root and root:IsA("BasePart") then
					local p = cell.part.CFrame:PointToObjectSpace(root.Position)
					gone = math.abs(p.X) > half.X + AUDIT_REACH or math.abs(p.Z) > half.Z + AUDIT_REACH
						or math.abs(p.Y) > AUDIT_HEIGHT
				end
				if gone then
					cell.pendingExit[player] = nil
					onPlayerExitCell(platform, state, cell, player)
				end
			end
		end
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
-- PUTS ONE CELL BACK the way it was built. `whole` is a restart putting back every cell, which also
-- gives the slab its collision back; one cell healing or regrowing leaves the slab alone, because
-- the other holes in the same platform still need it out of the way.
local function restoreCell(platform: BasePart, cell, whole: boolean)
	local saved = cell.pristine
	if saved then
		cell.part.CanCollide = saved.tileCollide
		cell.part.CanTouch = saved.tileTouch
		local reachPart = cell.part:FindFirstChild("Reach")
		if reachPart and reachPart:IsA("BasePart") and saved.reachTouch ~= nil then
			reachPart.CanTouch = saved.reachTouch
		end
		local floorPart = cell.part:FindFirstChild("Floor")
		if floorPart and floorPart:IsA("BasePart") and saved.floorCollide ~= nil then
			floorPart.CanCollide = saved.floorCollide
		end
		local slabPart = cell.part.Parent
		if whole and slabPart and slabPart:IsA("BasePart") then
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
	cell.depth = 0
	cell.push = 0
	cell.lean = nil
	cell.creep = 0
	cell.floating = 0
	cell.charge = nil
	cell.fire = nil
	cell.fireAt = nil
	cell.spread = nil
	cell.regrowAt = nil
	cell.healAt = nil
	cell.wade = nil
	-- Announced, so the client springs the surface back: bubbles re-inflate, soap and sand come out
	-- of their collapsed pose, a coal settles into its hole. Without this the state is right on the
	-- server and the platform still LOOKS destroyed.
	--
	-- No `who`: a repair is not anybody's footstep.
	replicate(platform, cell)
end

-- Puts every platform back to how it was built, WITHOUT rebuilding anything.
--
-- This is what a hardcore restart runs instead of tearing the level down and generating it
-- again. The rebuild worked, but it destroyed the geometry every OTHER player in the
-- server was standing on, so one person failing dropped everyone into the sea -- and then
-- their own kill planes fired, and in hardcore that restarted the level again.
--
-- Restoring in place harms nobody: another player mid-run gets their floor back, which is
-- the one side effect that cannot be a complaint.
function DeformationService.restoreAll()
	for platform, state in pairs(platformStates) do
		state.hardUntil = nil
		for _, cell in pairs(state.cells) do
			restoreCell(platform, cell, true)
		end
	end
end

-- ===== the grill and the pool, ticking =====

local function burnCharcoal(platform: BasePart, state, def, now: number)
	for _, cell in pairs(state.cells) do
		if cell.state == "exhausted" then
			-- A FRESH COAL in the ash hole, so the grill is never burned out for good.
			if cell.regrowAt and now >= cell.regrowAt then
				restoreCell(platform, cell, false)
			end
		elseif cell.fire == "smoulder" then
			if now - cell.fireAt >= (def.igniteAfter or 1) then
				cell.fire = "burning"
				cell.spread = nil
				replicate(platform, cell, nil, "fire")
			end
		elseif cell.fire == "burning" then
			local age = now - cell.fireAt
			local caught = def.igniteAfter or 1
			if not cell.spread and age >= caught + (def.spreadAfter or 1) then
				-- IT SPREADS, to each cold neighbour on a chance: a grill burns in patches, not as a
				-- tidy wave, and a chance under one is what lets a fire die out on its own.
				cell.spread = true
				for _, offset in ipairs(ORTHOGONAL) do
					local other = cellAt(state, cell.col + offset[1], cell.row + offset[2])
					if other and not other.fire and math.random() < (def.spreadChance or 0.35) then
						other.fire = "smoulder"
						other.fireAt = now
						replicate(platform, other, nil, "fire")
					end
				end
			end
			if age >= caught + (def.burnFor or 2.5) then
				-- ASH, and ash does not hold you.
				cell.fire = "ash"
				cell.regrowAt = now + (def.regrowAfter or 7)
				collapseCell(platform, cell, nil)
			end
		end
	end
end

-- Remembers each player's fastest recent fall. A landing zeroes the fall on the same frame it is
-- touched, so the speed a player ARRIVED at has to be remembered rather than read.
local function trackFalls(now: number)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local speed = root.AssemblyLinearVelocity.Y
			local record = lowestFall[player]
			if not record then
				lowestFall[player] = { speed = speed, at = now }
			elseif speed < record.speed or now - record.at > FALL_MEMORY then
				record.speed = speed
				record.at = now
			end
		end
	end
end

local function wadeOobleck(platform: BasePart, state, def, dt: number, now: number)
	local hard = (state.hardUntil or 0) > now
	for player in pairs(state.playerCellCount) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and root:IsA("BasePart") and humanoid) then
			continue
		end
		local wade = wades[player]
		if not wade then
			wade = { level = 0, shown = 0, frame = 0 }
			wades[player] = wade
		end
		-- Once a frame, however many pools a player is standing across.
		if wade.frame == heartbeatFrame then
			continue
		end
		wade.frame = heartbeatFrame

		if hard then
			wade.level = math.max(0, wade.level - dt * 4)
		else
			local velocity = root.AssemblyLinearVelocity
			local moving = Vector3.new(velocity.X, 0, velocity.Z).Magnitude >= (def.wadeSlow or 8)
			wade.level = math.min(1, wade.level + (if moving then def.wadeMoving or 0.3 else def.wadeStill or 1) * dt)
		end

		local shown = math.floor(wade.level * WADE_STEPS) / WADE_STEPS
		if shown ~= wade.shown then
			wade.shown = shown
			humanoid.WalkSpeed = Constants.DEFAULT_WALKSPEED * (def.speedMultiplier or 1) * (1 - (def.wadeDrag or 0.5) * shown)
			for _, cell in pairs(state.cells) do
				if cell.occupants[player] and cell.state ~= "exhausted" then
					cell.wade = shown
					replicate(platform, cell, player, "wade")
				end
			end
		end
		if wade.level >= 1 then
			-- UNDER. The cells holding this player give way, and fill back in later.
			wade.level, wade.shown = 0, 0
			for _, cell in pairs(state.cells) do
				if cell.occupants[player] and cell.state ~= "exhausted" then
					cell.healAt = now + (def.healAfter or 3.5)
					collapseCell(platform, cell, player)
				end
			end
		end
	end
	for _, cell in pairs(state.cells) do
		if cell.state == "exhausted" and cell.healAt and now >= cell.healAt then
			restoreCell(platform, cell, false)
		end
	end
end

function DeformationService.registerPlatform(platform: BasePart)
	if not platform:GetAttribute("Material") then
		return
	end

	local state = getOrCreatePlatformState(platform)
	-- The taller sensor for every material whose floor moves UP or sinks further than the thin tile
	-- reaches: clay and salt, and oobleck, which you wade into.
	local reachDef = Materials[state.material]
	local movesMaterial = reachDef ~= nil and (reachDef.displacement ~= nil or reachDef.wadeStill ~= nil)

	for _, child in ipairs(platform:GetChildren()) do
		if child:IsA("BasePart") and child.Name:match("^SubRegion_") then
			local col = child:GetAttribute("Col") :: number
			local row = child:GetAttribute("Row") :: number
			local key = SubRegionGrid.key(col, row)
			local cell = getOrCreateCell(state, key, child, col, row)

			local sensor: BasePart = if movesMaterial then reachFor(child) else child

			sensor.Touched:Connect(function(hit: BasePart)
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

			sensor.TouchEnded:Connect(function(hit: BasePart)
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
	surges[player] = nil
	streaks[player] = nil
	effectTokens[player] = nil
	charges[player] = nil
	capacitors[player] = nil
	springs[player] = nil
	lowestFall[player] = nil
	wades[player] = nil
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
	heartbeatFrame += 1
	local now = os.clock()
	local audit = now - auditAt >= AUDIT_EVERY
	if audit then
		auditAt = now
	end
	trackFalls(now)
	settleSprings(now)
	for platform, state in pairs(platformStates) do
		-- STANDING STILL PRESSES AGAIN, on the materials that move material. See DISPLACEMENT.
		local creepDef = state.material and Materials[state.material]
		local creepEvery = creepDef and creepDef.creepEvery
		if audit then
			auditOccupants(platform, state)
		end
		if creepDef and creepDef.chargeTime then
			chargeNeedoh(platform, state, creepDef, dt)
		end
		if creepDef and creepDef.igniteAfter then
			burnCharcoal(platform, state, creepDef, now)
		end
		if creepDef and creepDef.wadeStill then
			wadeOobleck(platform, state, creepDef, dt, now)
		end
		for _, cell in pairs(state.cells) do
			if creepEvery and cell.count > 0 and cell.state ~= "exhausted" then
				cell.creep = (cell.creep or 0) + dt
				if cell.creep >= creepEvery then
					cell.creep -= creepEvery
					displace(platform, state, cell, next(cell.occupants), "creep")
				end
			end
			-- AND A FLOATING SALT PLATE GOES UNDER on its own, whether or not anyone is near it.
			local sinkAfter = creepDef and creepDef.sinkAfter
			if sinkAfter and cell.state ~= "exhausted" and (cell.depth or 0) == 0
				and (cell.push or 0) >= (creepDef.displaceTilt or 2) then
				cell.floating = (cell.floating or 0) + dt
				if cell.floating >= sinkAfter then
					collapseCell(platform, cell, nil)
				end
			end
			if cell.state == "decaying" then
				cell.decayTimer -= dt
				if cell.decayTimer <= 0 and cell.pristine then
					-- A CELL THAT GAVE WAY AND IS COMING BACK -- only bubble wrap takes this road -- gets
					-- its floor back too. It used to re-inflate on screen with its collision still
					-- off: a whole-looking sheet you fell straight through.
					restoreCell(platform, cell, false)
				elseif cell.decayTimer <= 0 then
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
					cell.depth = 0
					cell.push = 0
					cell.lean = nil
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
