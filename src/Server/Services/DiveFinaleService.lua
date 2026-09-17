--!strict
-- ServerScriptService/Services/DiveFinaleService.lua
-- The end of City Shore: a high-dive platform at the top of the spiral, a springboard out over
-- the open sea, and a landing circle on the water that finishes the run.
--
-- === What it is ===
--
-- The run climbs a spiral high over the sea, and the sea is the one thing you can see the whole
-- way up and never reach. So that is how it ends. The last chunk runs onto a tiled deck with a
-- springboard out past its edge; you walk to the end of the board and jump. Fall inside the
-- landing circle and the water closes over you, the screen goes black, and the level is complete.
-- Steer out of the circle and it was not a dive: the kill plane has you, as it would anywhere.
--
-- === Two checks ===
--
-- A diver is someone who has LEFT THE BOARD -- passed through the air just under it -- AND is
-- over the LANDING CIRCLE. Neither is enough alone. The air under the board alone would count a
-- fall that drifts back in over the spiral. The circle alone would count anyone who fell off a
-- lower turn and drifted out over the same patch of sea, which is a way to finish the level
-- without climbing it.
--
-- === Why nothing here touches FallenPartsDestroyHeight ===
--
-- Roblox deletes a falling part below Workspace.FallenPartsDestroyHeight: -500 by default, with
-- the sea at -700. The first fix moved it from this module, and THAT LINE IS WHAT BROKE THE DIVE.
-- The property is PluginSecurity -- a script can read it, and only plugins, the command bar and
-- the Properties window can set it -- so the write threw. start() died after the platform was
-- built and before the watch was connected: a board you could jump off, nothing watching for
-- divers, and a kill plane with nobody to ask. Every dive was caught and sent back. check_hub
-- refuses any script that assigns it.
--
-- So a diver never reaches -500 on their own. COMMIT_ABOVE over the water, the server takes them
-- over: the character is anchored -- the engine does not delete anchored parts, which is how the
-- backdrop's sea can sit at -700 at all -- and carried the rest of the way down at the speed they
-- were already falling. The splash, the blackout and the completion land when they reach the
-- surface.
--
-- === Coordinates ===
--
-- Everything is laid out in the FINISH FRAME LevelService hands over: origin at the far end of the
-- last chunk on its walking surface, +Z the way the route was going, and +X pointing AWAY from the
-- spiral's centre, which is the way out over the sea. No chunk on any turn of the spiral reaches
-- further than about twenty-three studs out in this frame, so everything past that is open air.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local DiveFinaleService = {}

-- ===== THE PLATFORM =====
--
-- WIDE ENOUGH THAT ITS EDGE CLEARS ANY CHUNK, which is what decides this rather than taste. A
-- shaped chunk with a shelf on it reaches about sixteen studs from the route's centreline, so
-- thirty-six puts the deck's edge two studs clear of anything the generator can build.
local DECK_WIDE = 36
local DECK_DEEP = 30
local DECK_THICK = 3
-- The springboard, from its clamp on the deck to its tip out over the sea. Twenty studs of it are
-- past the deck's edge, which is the cantilever a real springboard has.
local BOARD_FROM = 4
local BOARD_TO = 38
local BOARD_WIDE = 5
local BOARD_TOP = 1.5
local RAIL_HEIGHT = 3.6
local FLAG_HEIGHT = 26

-- ===== THE DIVE =====
--
-- CHECK ONE: THE AIR JUST UNDER THE BOARD, out past the deck's edge and no further along the route
-- than ZONE_SIDE either side of the deck. From three studs below the board's top, so standing on
-- it does not count and leaving it does, down to seventy. The kill plane is at least forty under
-- the deck, so a diver is recognised long before they reach it.
local ZONE_TOP = 3
local ZONE_DOWN = 70
local ZONE_SIDE = 20
-- CHECK TWO: THE LANDING CIRCLE, on the water in front of the tower. Its nearest edge is
-- twenty-four studs out from the route's centreline: clear of the deck at eighteen and of the far
-- corner of the longest chunk on any turn of the spiral (R1_SlimeLaunch, thirty-eight long, at
-- about twenty-three). And it is big, six hundred studs across, because the only fall it exists to
-- refuse is one that steers back in towards the tower. Simulated: every dive off the board that
-- does not head back in lands inside it, and no fall from further back down the route counts.
local CIRCLE_OUT = 324
local CIRCLE_RADIUS = 300
-- HOW HIGH OVER THE WATER THE SERVER TAKES OVER. At the sea's -700 that is -300: two hundred studs
-- above the -500 where the engine deletes a falling character. That margin is for the server
-- seeing the diver a little late, and the diver's own screen hearing about the anchor a little
-- later still. check_hub keeps it at least a hundred clear.
local COMMIT_ABOVE = 400
-- The slowest the carry goes, for a diver who stepped off a low deck rather than jumping.
local CARRY_SPEED = 350
-- Where the diver ends up: through the surface, then sinking under it while the screen goes black.
local SPLASH_SINK = 1.5
local SINK_DEPTH = 7
local SINK_TIME = 0.7
-- The sea's level if the backdrop cannot say. BackdropService's BASE_Y.
local FALLBACK_WATER = -700
-- A HELD DIVER IS LET GO once something has moved them this far from where they came to rest --
-- the lobby taking them back -- and never before: a character let go under the sea is below the
-- delete line and gone. If nothing has come for them after RELEASE_AFTER, nothing is coming, and
-- they are put back on the deck rather than left in the water.
local RELEASE_AWAY = 300
local RELEASE_AFTER = 12
-- A built-in water impact, present in every place with no upload. Slowed, because this is a body
-- hitting the sea from a great height rather than a drip.
local SPLASH_SOUND = "rbxasset://sounds/impact_water.mp3"
-- How often the watch checks the platform is still there and the old finish line is still
-- disarmed. Twice a second: a repair, not a control loop.
local GUARD_EVERY = 0.5
-- What LevelService calls the trigger at the end of the route.
local FINISH_NAME = "FinishLine"

local TILE = Color3.fromRGB(236, 240, 238)
local TRIM = Color3.fromRGB(72, 150, 170)
local BOARD = Color3.fromRGB(244, 244, 240)
local GRIP = Color3.fromRGB(96, 172, 184)
local STEEL = Color3.fromRGB(200, 204, 206)
local PENNANT = Color3.fromRGB(222, 98, 86)
local SPRAY = Color3.fromRGB(240, 250, 255)

type Finale = {
	frame: CFrame,
	model: Model,
	-- Kept so the platform can be put back if the level is rebuilt under it.
	parent: Instance,
	-- The landing circle's centre, on the water.
	circle: Vector3,
	waterAt: (number, number) -> number,
	onSplash: (Player) -> (),
}

-- A diver the server has taken over: the root, where it comes to rest, and when it gets there.
type Hold = { root: BasePart, rest: Vector3, settled: number }

local current: Finale? = nil
local diving: { [Player]: boolean } = {}
local committed: { [Player]: boolean } = {}
local held: { [Player]: Hold } = {}
local connection: RBXScriptConnection? = nil
local guardAt = 0
local saidRebuilt = false
local saidDisarmed = false
local saidStranded = false

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3,
	material: Enum.Material, shape: Enum.PartType?): Part
	local made = Instance.new("Part")
	made.Name = name
	if shape then
		made.Shape = shape
	end
	made.Size = size
	made.CFrame = cf
	made.Anchored = true
	made.Color = colour
	made.Material = material
	made.TopSurface = Enum.SurfaceType.Smooth
	made.BottomSurface = Enum.SurfaceType.Smooth
	made.Parent = parent
	return made
end

-- A rail between two points in the finish frame: posts every eight studs and a round bar on top.
local function railRun(parent: Instance, frame: CFrame, from: Vector3, to: Vector3)
	local run = (to - from).Magnitude
	local posts = math.max(1, math.ceil(run / 8))
	for k = 0, posts do
		local at = from:Lerp(to, k / posts)
		part(parent, "DiveRailPost", Vector3.new(0.5, RAIL_HEIGHT, 0.5),
			frame * CFrame.new(at + Vector3.new(0, RAIL_HEIGHT / 2, 0)), STEEL, Enum.Material.Metal)
	end
	local lift = Vector3.new(0, RAIL_HEIGHT, 0)
	local bar = part(parent, "DiveRail", Vector3.new(run + 0.5, 0.55, 0.55),
		frame * CFrame.lookAt(from:Lerp(to, 0.5) + lift, to + lift) * CFrame.Angles(0, math.rad(90), 0),
		STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
	bar.Reflectance = 0.2
end

local function buildPlatform(frame: CFrame, circle: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "DiveFinale"
	local middle = DECK_DEEP / 2

	-- THE DECK, flush with the last chunk's walking surface, a teal border on the three sides that
	-- are not the way in, and a narrower block under it so it has some mass.
	part(model, "DiveDeck", Vector3.new(DECK_WIDE, DECK_THICK, DECK_DEEP),
		frame * CFrame.new(0, -DECK_THICK / 2, middle), TILE, Enum.Material.CeramicTiles)
	part(model, "DiveDeckBase", Vector3.new(DECK_WIDE - 8, 5, DECK_DEEP - 8),
		frame * CFrame.new(0, -DECK_THICK - 2.5, middle), TILE, Enum.Material.CeramicTiles)
	for _, spec in ipairs({
		{ Vector3.new(DECK_WIDE, 0.2, 1.6), Vector3.new(0, 0.1, DECK_DEEP - 0.8) },
		{ Vector3.new(1.6, 0.2, DECK_DEEP), Vector3.new(-DECK_WIDE / 2 + 0.8, 0.1, middle) },
		{ Vector3.new(1.6, 0.2, DECK_DEEP), Vector3.new(DECK_WIDE / 2 - 0.8, 0.1, middle) },
	}) do
		part(model, "DiveDeckTrim", spec[1] :: Vector3, frame * CFrame.new(spec[2] :: Vector3), TRIM,
			Enum.Material.CeramicTiles)
	end

	-- THE SPRINGBOARD. Clamped at its back end, resting on a roller a third of the way along, and
	-- cantilevered out past the deck's edge, which is how a real one is held. A gritted strip on
	-- top, the texture every diving board has.
	part(model, "DiveBoardClamp", Vector3.new(4, 0.9, BOARD_WIDE + 1),
		frame * CFrame.new(BOARD_FROM + 2, 0.45, middle), STEEL, Enum.Material.Metal)
	part(model, "DiveBoardRoller", Vector3.new(BOARD_WIDE + 1.4, 0.9, 0.9),
		frame * CFrame.new(13, 0.45, middle) * CFrame.Angles(0, math.rad(90), 0), STEEL,
		Enum.Material.Metal, Enum.PartType.Cylinder)
	for _, hand in ipairs({ 1, -1 }) do
		part(model, "DiveBoardStand", Vector3.new(1.4, 1.2, 0.6),
			frame * CFrame.new(13, 0.6, middle + hand * (BOARD_WIDE / 2 + 1)), STEEL, Enum.Material.Metal)
	end
	part(model, "DiveBoard", Vector3.new(BOARD_TO - BOARD_FROM, 0.9, BOARD_WIDE),
		frame * CFrame.new((BOARD_FROM + BOARD_TO) / 2, BOARD_TOP - 0.45, middle), BOARD,
		Enum.Material.SmoothPlastic)
	part(model, "DiveBoardGrip", Vector3.new(BOARD_TO - BOARD_FROM - 1.5, 0.12, BOARD_WIDE - 0.8),
		frame * CFrame.new((BOARD_FROM + BOARD_TO) / 2 + 0.5, BOARD_TOP + 0.06, middle), GRIP,
		Enum.Material.Sand)

	-- HANDRAILS either side of the board's back half, and a rail round the deck on every side but
	-- the way in and the gap the board goes out through.
	for _, hand in ipairs({ 1, -1 }) do
		local z = middle + hand * (BOARD_WIDE / 2 + 1.2)
		railRun(model, frame, Vector3.new(1, 0, z), Vector3.new(13, 0, z))
	end
	local inner, outer = -DECK_WIDE / 2 + 0.4, DECK_WIDE / 2 - 0.4
	local back = DECK_DEEP - 0.4
	local gap = BOARD_WIDE / 2 + 2
	railRun(model, frame, Vector3.new(inner, 0, 0.4), Vector3.new(inner, 0, back))
	railRun(model, frame, Vector3.new(inner, 0, back), Vector3.new(outer, 0, back))
	railRun(model, frame, Vector3.new(outer, 0, 0.4), Vector3.new(outer, 0, middle - gap))
	railRun(model, frame, Vector3.new(outer, 0, middle + gap), Vector3.new(outer, 0, back))

	-- A FLAG at the far inner corner: from the bottom of the spiral, the one thing on the skyline
	-- that says where the top is.
	part(model, "DiveFlagPole", Vector3.new(FLAG_HEIGHT, 0.5, 0.5),
		frame * CFrame.new(inner + 2, FLAG_HEIGHT / 2, back - 2) * CFrame.Angles(0, 0, math.pi / 2),
		STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(model, "DiveFlag", Vector3.new(0.12, 2.6, 4.4),
		frame * CFrame.new(inner + 2, FLAG_HEIGHT - 1.6, back - 4.4), PENNANT, Enum.Material.Fabric)

	-- THE LANDING CIRCLE, on the water. Invisible, the way the target of any real high dive is: it
	-- is a part at all so the circle the watch tests against can be selected in Studio's Explorer
	-- and seen, size and place, rather than taken on trust.
	local marker = part(model, "DiveLandingCircle", Vector3.new(2, CIRCLE_RADIUS * 2, CIRCLE_RADIUS * 2),
		CFrame.new(circle) * CFrame.Angles(0, 0, math.pi / 2), SPRAY, Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder)
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.CastShadow = false

	return model
end

-- CHECK ONE: in the air just under the board, out past the deck's edge.
local function underBoard(frame: CFrame, at: Vector3): boolean
	local p = frame:PointToObjectSpace(at)
	return p.X > DECK_WIDE / 2 and p.Z > -ZONE_SIDE and p.Z < DECK_DEEP + ZONE_SIDE
		and p.Y < BOARD_TOP - ZONE_TOP and p.Y > BOARD_TOP - ZONE_DOWN
end

-- CHECK TWO: over the landing circle, seen from above.
local function inCircle(finale: Finale, at: Vector3): boolean
	local dx, dz = at.X - finale.circle.X, at.Z - finale.circle.Z
	return dx * dx + dz * dz <= CIRCLE_RADIUS * CIRCLE_RADIUS
end

-- The splash: a column of spray, a ring spreading on the water, and the sound. Rate and Enabled
-- rather than Emit, because Emit called on the server does not reach anyone's screen.
local function splashEffects(finale: Finale, surface: Vector3)
	local host = part(finale.model, "Splash", Vector3.new(1, 1, 1), CFrame.new(surface + Vector3.new(0, 0.5, 0)),
		SPRAY, Enum.Material.SmoothPlastic)
	host.Transparency = 1
	host.CanCollide = false
	host.CanTouch = false
	host.CanQuery = false
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spray.Color = ColorSequence.new(SPRAY)
	spray.LightEmission = 0.25
	spray.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.5),
		NumberSequenceKeypoint.new(1, 8),
	})
	spray.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	spray.Lifetime = NumberRange.new(0.9, 1.7)
	spray.Speed = NumberRange.new(45, 95)
	spray.SpreadAngle = Vector2.new(22, 22)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Acceleration = Vector3.new(0, -110, 0)
	spray.Drag = 1.2
	spray.Rate = 420
	spray.Parent = host
	task.delay(0.18, function()
		if spray.Parent then
			spray.Enabled = false
		end
	end)

	local ring = part(finale.model, "SplashRing", Vector3.new(0.6, 8, 8),
		CFrame.new(surface + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2), SPRAY,
		Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.CastShadow = false
	ring.Transparency = 0.15
	TweenService:Create(ring, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, 70, 70),
		Transparency = 1,
	}):Play()

	local sound = Instance.new("Sound")
	sound.SoundId = SPLASH_SOUND
	sound.Volume = 1
	sound.PlaybackSpeed = 0.7
	sound.RollOffMaxDistance = 400
	sound.Parent = host
	sound:Play()

	Debris:AddItem(host, 5)
	Debris:AddItem(ring, 2)
end

-- THE SERVER TAKES THE LAST OF THE FALL. Anchored, which the engine never deletes and the diver's
-- own client cannot overrule, and carried down at the speed they were already falling, so the
-- hand-over does not read as a stall. The splash, the blackout and the completion all land when
-- the diver reaches the surface.
local function commit(finale: Finale, player: Player, root: BasePart)
	local at = root.Position
	local water = finale.waterAt(at.X, at.Z)
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local facing = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	local speed = math.max(-root.AssemblyLinearVelocity.Y, CARRY_SPEED)
	local surface = Vector3.new(at.X, water - SPLASH_SINK, at.Z)
	local rest = surface - Vector3.new(0, SINK_DEPTH, 0)
	local carry = math.max(0.05, (at.Y - surface.Y) / speed)

	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	held[player] = { root = root, rest = rest, settled = os.clock() + carry + SINK_TIME }
	TweenService:Create(root, TweenInfo.new(carry, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(surface, surface + facing),
	}):Play()

	task.delay(carry, function()
		-- Still this run's diver: a level torn down mid-carry has nobody left to finish.
		local hold = held[player]
		if current ~= finale or not hold or hold.root ~= root then
			return
		end
		TweenService:Create(root, TweenInfo.new(SINK_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			CFrame = CFrame.lookAt(rest, rest + facing),
		}):Play()
		splashEffects(finale, Vector3.new(at.X, water, at.Z))
		finale.onSplash(player)
	end)
end

-- Builds the platform at `finishFrame` under `parent` and starts watching for divers. `waterAt`
-- gives the sea's surface height at a world X and Z; `onSplash` is the level's finish.
function DiveFinaleService.start(finishFrame: CFrame, parent: Instance,
	waterAt: ((number, number) -> number?)?, onSplash: (Player) -> ())
	DiveFinaleService.stop()
	saidRebuilt, saidDisarmed, saidStranded, guardAt = false, false, false, 0

	local function sea(x: number, z: number): number
		local level = if waterAt then waterAt(x, z) else nil
		return level or FALLBACK_WATER
	end
	local over = finishFrame * Vector3.new(CIRCLE_OUT, 0, DECK_DEEP / 2)
	local circle = Vector3.new(over.X, sea(over.X, over.Z), over.Z)

	local model = buildPlatform(finishFrame, circle)
	model.Parent = parent
	local finale: Finale = {
		frame = finishFrame,
		model = model,
		parent = parent,
		circle = circle,
		waterAt = sea,
		onSplash = onSplash,
	}
	current = finale

	connection = RunService.Heartbeat:Connect(function()
		-- ===== THE PLATFORM AND THE OLD FINISH LINE, BOTH HELD =====
		--
		-- A level rebuilt with the dive armed came back with no board and its finish line live,
		-- so the dive holds its ground: it puts the platform back if it is destroyed, and keeps
		-- the finish line disarmed for as long as it owns the ending. Each repair says so once.
		local now = os.clock()
		if now - guardAt > GUARD_EVERY then
			guardAt = now
			if not finale.model.Parent then
				finale.model = buildPlatform(finale.frame, finale.circle)
				finale.model.Parent = finale.parent
				if not saidRebuilt then
					saidRebuilt = true
					warn("DiveFinaleService: the level was rebuilt underneath the dive, so the "
						.. "platform went with it. Put back. If this repeats, something is "
						.. "building levels without arming the finale.")
				end
			end
			local finish = finale.parent:FindFirstChild(FINISH_NAME)
			if finish and finish:IsA("BasePart") and finish.CanTouch then
				finish.CanTouch = false
				if not saidDisarmed then
					saidDisarmed = true
					warn("DiveFinaleService: the old finish line at the end of the route was live "
						.. "while the dive owned the ending, so the run would have completed on "
						.. "reaching the deck. Disarmed.")
				end
			end
		end

		-- ===== HELD DIVERS =====
		--
		-- Let go once the lobby has moved them. returnToHub teleports before it tears the run
		-- down, so by the time stop() lets everyone go they are already standing in the room.
		for player, hold in pairs(held) do
			if not hold.root.Parent then
				held[player] = nil
			elseif now > hold.settled then
				if (hold.root.Position - hold.rest).Magnitude > RELEASE_AWAY then
					hold.root.Anchored = false
					held[player] = nil
				elseif now - hold.settled > RELEASE_AFTER then
					hold.root.CFrame = finale.frame * CFrame.new(0, 3.5, DECK_DEEP / 2)
					hold.root.Anchored = false
					held[player] = nil
					committed[player] = nil
					if not saidStranded then
						saidStranded = true
						warn(("DiveFinaleService: %s reached the water and nothing took them to "
							.. "the lobby within %d seconds, so they are back on the deck rather "
							.. "than held under the sea. The run's completion did not send them "
							.. "home: look for a completion that returned early."):format(
							player.Name, RELEASE_AFTER))
					end
				end
			end
		end

		-- ===== DIVERS =====
		for _, player in ipairs(Players:GetPlayers()) do
			if committed[player] then
				continue
			end
			local character = player.Character
			local found = character and character:FindFirstChild("HumanoidRootPart")
			if not (found and found:IsA("BasePart")) then
				diving[player] = nil
				continue
			end
			local root: BasePart = found
			local at = root.Position
			if not inCircle(finale, at) then
				-- OUTSIDE THE CIRCLE, whatever came before: not a dive, and the kill plane has them.
				diving[player] = nil
			elseif not diving[player] then
				if underBoard(finale.frame, at) then
					diving[player] = true
				end
			elseif at.Y <= finale.circle.Y + COMMIT_ABOVE then
				diving[player] = nil
				committed[player] = true
				commit(finale, player, root)
			end
		end
	end)

	-- ONE LINE OF PROOF, after the watch is connected. If this is not in the Output, the dive is
	-- not armed, whatever the level looks like.
	local top = finishFrame.Position
	print(("DiveFinaleService: high dive armed at (%d, %d, %d), %d parts. Landing circle %d studs "
		.. "across on the water %d studs below; the server takes divers over %d studs above it."):format(
		math.floor(top.X), math.floor(top.Y), math.floor(top.Z), #model:GetDescendants(),
		CIRCLE_RADIUS * 2, math.floor(top.Y - circle.Y), COMMIT_ABOVE))
end

-- True while a dive owns this level's ending. Bootstrap's finish-line handler asks before it
-- completes anyone, so the end of the route can never finish a run the dive is meant to finish.
function DiveFinaleService.isArmed(): boolean
	return current ~= nil
end

-- True while this module is responsible for where the player is: falling inside the circle, or
-- taken over by the server after it. The kill plane leaves both alone.
function DiveFinaleService.ownsFall(player: Player): boolean
	return diving[player] == true or committed[player] == true
end

-- Safe to call when nothing is running, and twice.
function DiveFinaleService.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	-- AN ANCHORED CHARACTER STAYS ANCHORED wherever it goes, so every held diver is let go here.
	for _, hold in pairs(held) do
		if hold.root.Parent then
			hold.root.Anchored = false
		end
	end
	table.clear(held)
	local finale = current
	if finale and finale.model.Parent then
		finale.model:Destroy()
	end
	current = nil
	table.clear(diving)
	table.clear(committed)
end

return DiveFinaleService
