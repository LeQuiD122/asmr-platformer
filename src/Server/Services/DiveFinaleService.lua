--!strict
-- ServerScriptService/Services/DiveFinaleService.lua
-- The end of City Shore: a high-dive platform at the top of the spiral, a springboard out over
-- the open sea, and a finish that IS the sea.
--
-- === What it is ===
--
-- The run climbs a spiral seven hundred studs above the water for its whole length, and the
-- water is the one thing in the level you can see the entire time and never reach. So that is
-- how it ends. The last chunk runs onto a tiled deck with a springboard sticking out past its
-- edge; you walk to the end of the board, jump, fall through the cloud layers, and the level
-- completes the moment you hit the sea.
--
-- === Why the finish is not a trigger part ===
--
-- A diver reaches the water at over five hundred studs a second, which at sixty frames is nine
-- studs a frame. A Touched event on a thin part is simply skipped at that speed -- the character
-- is above it on one frame and below it on the next and never "touched" anything. So the splash
-- is a height test on Heartbeat against the sea's own surface, which cannot be skipped.
--
-- === Why the kill plane has to be told ===
--
-- Bootstrap's kill plane sits forty studs under the lowest chunk, which is nearly seven hundred
-- studs above the water. Every diver would be caught by it and sent back up a few frames into
-- the dive. So a player who has jumped off the board -- and a player standing in the sea after
-- the splash, still far below the plane -- belongs to this module, and Bootstrap asks ownsFall
-- before it catches anyone.
--
-- === Coordinates ===
--
-- Everything is laid out in the FINISH FRAME LevelService hands over: origin at the far end of
-- the last chunk on its walking surface, +Z the way the route was going, and +X pointing AWAY
-- from the spiral's centre, which is the way out over the sea. Every chunk of the spiral lies
-- at X of about 11 or less in this frame, so anything past the deck's outer edge is clear air.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local DiveFinaleService = {}

-- ===== THE PLATFORM =====
--
-- WIDE ENOUGH THAT ITS EDGE CLEARS ANY CHUNK, which is what decides this rather than taste.
-- The dive column starts at the deck's outer edge, and a shaped chunk with a shelf on it reaches
-- about sixteen studs from the route's centreline -- so at thirty wide the column began one stud
-- INSIDE the widest chunk on the turn below, and standing on that chunk's shelf counted as
-- falling. Thirty-six puts the edge two studs clear of anything the generator can build.
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
-- The column of air a jump off the board falls into. A player inside it is diving: out past the
-- deck's edge, three studs under the board's top and further down, so standing on the board
-- does not count and falling off it does.
local ZONE_OUT = 95
local ZONE_SIDE = 30
local ZONE_DOWN = 70
-- A diver who lands on something this far above the water did not reach it: they steered back
-- onto the spiral, and the kill plane is theirs again.
local LANDED_ABOVE = 40
-- How far under the surface the splash leaves you standing: in the sea to the chest.
local SPLASH_SINK = 1.5
-- The sea's level if the backdrop cannot say. BackdropService's BASE_Y.
local FALLBACK_WATER = -700
-- A built-in water impact, present in every place with no upload. Slowed down, because this is
-- a body hitting the sea from a great height rather than a drip.
local SPLASH_SOUND = "rbxasset://sounds/impact_water.mp3"

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
	waterAt: (number, number) -> number,
	onSplash: (Player) -> (),
}

local current: Finale? = nil
local diving: { [Player]: boolean } = {}
local splashed: { [Player]: boolean } = {}
local connection: RBXScriptConnection? = nil

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

local function buildPlatform(frame: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "DiveFinale"
	local middle = DECK_DEEP / 2

	-- THE DECK, flush with the last chunk's walking surface, with a teal border on the three
	-- sides that are not the way in, and a narrower block under it so it has some mass.
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

	-- THE SPRINGBOARD. Clamped at its back end, resting on a roller a third of the way along,
	-- and cantilevered out past the deck's edge -- which is how a real one is held, so nothing
	-- about it is hanging in the air. A gritted strip on top, the texture every diving board has.
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

	-- A FLAG at the far inner corner. From the bottom of the spiral this is the one thing on the
	-- skyline that says where the top is.
	part(model, "DiveFlagPole", Vector3.new(FLAG_HEIGHT, 0.5, 0.5),
		frame * CFrame.new(inner + 2, FLAG_HEIGHT / 2, back - 2) * CFrame.Angles(0, 0, math.pi / 2),
		STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
	part(model, "DiveFlag", Vector3.new(0.12, 2.6, 4.4),
		frame * CFrame.new(inner + 2, FLAG_HEIGHT - 1.6, back - 4.4), PENNANT, Enum.Material.Fabric)

	return model
end

-- Inside the column of air under and beyond the board.
local function inDive(frame: CFrame, at: Vector3): boolean
	local p = frame:PointToObjectSpace(at)
	return p.X > DECK_WIDE / 2 and p.X < DECK_WIDE / 2 + ZONE_OUT
		and p.Z > -ZONE_SIDE and p.Z < DECK_DEEP + ZONE_SIDE
		and p.Y < BOARD_TOP - 3 and p.Y > BOARD_TOP - ZONE_DOWN
end

local function splash(finale: Finale, root: BasePart, water: number)
	local at = root.Position

	-- STOPPED, AND STANDING IN THE SEA. A floor just under the surface so the diver stays where
	-- they landed for the few seconds before the lobby, instead of sinking out of the world.
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	local facing = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
	local standAt = Vector3.new(at.X, water - SPLASH_SINK, at.Z)
	local floor = part(finale.model, "SplashFloor", Vector3.new(40, 2, 40),
		CFrame.new(standAt - Vector3.new(0, 4, 0)), Color3.new(0, 0, 0), Enum.Material.SmoothPlastic)
	floor.Transparency = 1
	floor.CanTouch = false
	floor.CanQuery = false
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.lookAt(standAt, standAt + facing)

	-- THE SPLASH: a column of spray, a ring spreading on the water, and the sound. Rate and
	-- Enabled rather than Emit, because Emit called on the server does not reach anyone's screen.
	local host = part(finale.model, "Splash", Vector3.new(1, 1, 1), CFrame.new(at.X, water + 0.5, at.Z),
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
		CFrame.new(at.X, water + 0.3, at.Z) * CFrame.Angles(0, 0, math.pi / 2), SPRAY,
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

-- Builds the platform at `finishFrame` under `parent` and starts watching for divers. `waterAt`
-- gives the sea's surface height at a world X and Z; `onSplash` is the level's finish.
function DiveFinaleService.start(finishFrame: CFrame, parent: Instance,
	waterAt: ((number, number) -> number?)?, onSplash: (Player) -> ())
	DiveFinaleService.stop()

	local model = buildPlatform(finishFrame)
	model.Parent = parent
	local finale: Finale = {
		frame = finishFrame,
		model = model,
		waterAt = function(x: number, z: number): number
			local level = if waterAt then waterAt(x, z) else nil
			return level or FALLBACK_WATER
		end,
		onSplash = onSplash,
	}
	current = finale

	-- ONE LINE OF PROOF. Everything about this feature is invisible until someone walks to the
	-- end of a level, and its failure mode is the level ending the way it used to. If this line
	-- is not in the Output, the platform was not built, whatever else the log says.
	local at = finishFrame.Position
	print(("DiveFinaleService: high dive built at (%d, %d, %d), %d parts. The sea is %d studs "
		.. "below it, and the run finishes there rather than at the end of the route."):format(
		at.X, at.Y, at.Z, #model:GetDescendants(),
		math.floor(at.Y - finale.waterAt(at.X, at.Z))))

	connection = RunService.Heartbeat:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			if splashed[player] then
				continue
			end
			local character = player.Character
			local found = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not (found and found:IsA("BasePart") and humanoid) then
				diving[player] = nil
				continue
			end
			local root: BasePart = found
			local at = root.Position
			if not diving[player] then
				if inDive(finale.frame, at) then
					diving[player] = true
				end
				continue
			end
			local water = finale.waterAt(at.X, at.Z)
			if humanoid.FloorMaterial ~= Enum.Material.Air and at.Y > water + LANDED_ABOVE then
				diving[player] = nil
			elseif at.Y <= water + 2 then
				diving[player] = nil
				splashed[player] = true
				splash(finale, root, water)
				finale.onSplash(player)
			end
		end
	end)
end

-- True while this module is responsible for where the player is: falling from the board, or
-- standing in the sea after the splash. The kill plane leaves both alone.
function DiveFinaleService.ownsFall(player: Player): boolean
	return diving[player] == true or splashed[player] == true
end

-- Safe to call when nothing is running, and twice.
function DiveFinaleService.stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	local finale = current
	if finale and finale.model.Parent then
		finale.model:Destroy()
	end
	current = nil
	table.clear(diving)
	table.clear(splashed)
end

return DiveFinaleService
