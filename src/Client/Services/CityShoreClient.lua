--!strict
-- StarterPlayerScripts/Services/CityShoreClient.lua
-- City Shore's ending, played as a scene: the high dive off the board at the top of the spiral into
-- the sea seven hundred studs below (DiveFinaleService decides everything; this only shows it).
--
-- === The scene, on the diver's own screen (Cinema) ===
--
--   THE LEAP        from low beside the board, looking up: they go up and out against the sky and seem to
--                   hang there for a moment (the fall is held back for the first second), the sun
--                   behind them.
--   MAREN           a cut back up to the deck: over the lifeguard's shoulder, looking down past her at
--                   you dropping away. She saw you go.
--   THE TURN        close, going round them as they turn over, head down, the spiral they climbed
--                   standing behind them.
--   THE DROP        over them and a little behind, falling with them, looking down past them at the sea
--                   coming up: where they are going (it looked up at the sky, away from it).
--   THEIR FACE      close, from under it, head first at the water, the wind in it: what they tell themselves.
--   THE DROP        again, the sea near now.
--   THE WATER       from the surface, low, as they come down at it: only in the last second or so, when
--                   they are near enough to see.
--
-- AND THEY THINK ON THE WAY (Cinema.think, over their head): "Okay. Don't look down." off the board, "I looked
-- down." as they turn over and see it, and "Arms together. Arms together!" with the water coming.
--   THE SPLASH      spray thrown up, a white flash, the camera knocked.
--   UNDER           the water closes over them and the camera follows them down into the dark, shafts of
--                   light slanting down round them and a few fish going by, and far below a street lamp
--                   is still on, on a street that is under the sea (Harrow Bay's other end: the Sunken
--                   City). Held until the lobby takes them.
--
-- AND THINGS HAPPEN ON THE WAY DOWN: the sun flares as you leave the board, you drop through a flock of
-- gulls that bursts apart round you, and the air rushes past. HIT LIKE AN ACTION GAME (the eighty-first pass):
-- an impact frame as you leave the board, as you burst through the gulls and as you hit the water (Cinema.impact);
-- speed lines streaming in from the edges and wind streaking past you all the way down, air trails off your hands
-- and feet; the camera leaning into the fall (a Dutch tilt, buffeted); and you are never still in the air: rolling
-- and swaying in the wind, arms and legs working against it (Poses.dive). SCORED (Cinema.sound; audio/endings): the
-- board letting you go, the wind rising all the way down, the splash, the hum under the harbour, and the
-- last chord as the lamp comes into view.
--
-- THE LAST OF THE FALL IS SMOOTH. The server takes the diver over four hundred studs above the water
-- (it has to: see DiveFinaleService) and carries them down, and a character carried by the server
-- arrives on this screen in steps. So while it has them, this screen draws them where the carry puts
-- them, every frame, from the moment and the place it took them.
--
-- Head first all the way in: their own client turns the body over as it falls (PlatformStand, so
-- the humanoid does not stand it back up) until the server takes the last of the fall, which keeps
-- the angle (DiveFinaleService.commit).
--
-- === The pose, on everyone's ===
--
-- A swan off the board -- arms spread wide, back arched -- closing to arms together over the head to
-- go in clean (Poses.dive), for anyone diving, on every client: joints turned on one client are seen
-- on that client only.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Poses: any = (function()
	local found = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Poses", 15)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()
local Cinema: any = (function()
	local found = script.Parent and script.Parent:WaitForChild("Cinema", 15)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()

local CityShoreClient = {}
CityShoreClient.VERSION = "the two-hundred-and-eighth pass, 2026-11-12"

type Gull = { body: BasePart, left: BasePart, right: BasePart, home: Vector3, out: Vector3, flap: number, fled: number? }
type Scene = { began: number, water: number, tip: Vector3, from: Vector3, facing: Vector3, splash: Vector3?,
	splashAt: number?, lamp: Vector3?, held: { Instance }, carryFrom: Vector3?, carryAt: number?, told: boolean,
	shot: string?, maren: BasePart?, gulls: { Gull }, rush: BasePart?, wind: Sound?, sunWas: number?,
	shafts: { { part: BasePart, rest: CFrame, phase: number, beams: { { beam: Beam, clear: number } }? } }, fish: { { part: BasePart, from: Vector3, to: Vector3, speed: number } },
	hit: { [string]: boolean }, streaks: ParticleEmitter?, dropTop: number?, marenFigure: Model?,
	marenJoints: { [string]: any }?, underFx: { PostEffect }, hidden: { BasePart }, ceiling: BasePart? }
local scene: Scene? = nil
-- The fastest the diver falls and drifts while the scene is on (studs a second).
local FALL_SPEED = 110
local DRIFT = 10
-- THE HANG off the board: for this long the fall is held to HANG_SPEED, so the leap reads.
local HANG_SECONDS, HANG_SPEED = 1.1, 22
-- The speed the server carries the last of the fall at (DiveFinaleService's CARRY_SPEED), and how far
-- under the surface the diver ends up (its SPLASH_SINK).
local CARRY_SPEED = 120
local SPLASH_SINK = 1.5
-- When the camera goes down to the water to watch them come in: this high over it.
local WATER_SHOT = 120
-- THE HIT, held: seconds the camera stays at the surface on the splash before it goes under after them.
local SPLASH_HOLD = 0.6
-- THE DROWNED STREET (the two-hundred-and-eighth pass): how far under the splash it lies (it was 120: too far for its lamp
-- to be found, or for its light to be drawn on every machine), and how far round the splash the sea is taken off this
-- screen while the camera is under it (drown).
local DEEP_DOWN = 70
local DROWN_REACH = 320
local divers: { [Player]: { began: number, ends: number, model: Instance?, joints: { [string]: any }? } } = {}
local stepped: RBXScriptConnection? = nil

-- THE POSE, for everyone diving, after the animations every frame.
local function poseDivers()
	local now = os.clock()
	for player, d in pairs(divers) do
		local character = player.Character
		if not character or not player.Parent or now > d.ends then
			if d.joints then
				for _, joint in pairs(d.joints) do
					Poses.drive(joint, CFrame.identity)
				end
			end
			divers[player] = nil
		else
			if d.model ~= character then
				d.model = character
				d.joints = Poses.joints(character)
			end
			local joints = d.joints
			if joints then
				local t = now - d.began
				local r6 = Poses.isR6(joints)
				for name, joint in pairs(joints) do
					local turn = Poses.dive(name, t, math.clamp(t / 0.25, 0, 1), r6)
					if turn then
						Poses.drive(joint, turn)
					end
				end
			end
		end
	end
	local hook = stepped
	if hook and next(divers) == nil then
		hook:Disconnect()
		stepped = nil
	end
end

local function endScene(now: boolean?)
	local current = scene
	if not current then
		return
	end
	scene = nil
	for _, thing in ipairs(current.held) do
		thing:Destroy()
	end
	-- The sea, back on this screen (drown hid it for the last shot).
	for _, part in ipairs(current.hidden) do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
	if Poses and current.marenJoints then
		for _, joint in pairs(current.marenJoints) do
			Poses.drive(joint, CFrame.identity)
		end
	end
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays and current.sunWas then
		rays.Intensity = current.sunWas
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end
	if Cinema then
		Cinema.finish(now)
	end
end

local function beginScene(water: number, tip: Vector3)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid) then
		return
	end
	local look = Vector3.new(root.Position.X - tip.X, 0, root.Position.Z - tip.Z)
	local facing = if look.Magnitude > 0.1 then look.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	-- MAREN, on the deck, for the cut back up to her.
	local maren: BasePart? = nil
	local deck = workspace:FindFirstChild("DiveFinale", true)
	local figure = deck and deck:FindFirstChild("Maren", true)
	local head = figure and figure:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		maren = head
	end
	local current: Scene = { began = os.clock(), water = water, tip = tip, from = root.Position, facing = facing,
		held = {}, carryFrom = nil, carryAt = nil, told = false, shot = nil, maren = maren, gulls = {}, rush = nil,
		wind = nil, sunWas = nil, shafts = {}, fish = {}, hit = {}, streaks = nil, dropTop = nil,
		marenFigure = if figure and figure:IsA("Model") then figure else nil, marenJoints = nil, underFx = {},
		hidden = {}, ceiling = nil }
	scene = current
	humanoid.PlatformStand = true
	-- THE GULLS, circling halfway down the fall out from the board, which you drop straight through.
	local flockY = math.min(water + (root.Position.Y - water) * 0.5, root.Position.Y - 60)
	local flockAt = Vector3.new(tip.X, flockY, tip.Z) + facing * 14
	for k = 1, 11 do
		local a = k / 11 * math.pi * 2
		local home = flockAt + Vector3.new(math.cos(a) * (6 + (k % 3) * 4), (k % 4) * 3 - 4, math.sin(a) * (6 + (k % 3) * 4))
		local function bit(name: string, size: Vector3, colour: Color3): BasePart
			local part = Instance.new("Part")
			part.Name = name
			part.Size = size
			part.Color = colour
			part.Material = Enum.Material.SmoothPlastic
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
			part.CFrame = CFrame.new(home)
			part.Parent = workspace
			table.insert(current.held, part)
			return part
		end
		table.insert(current.gulls, { body = bit("Gull", Vector3.new(0.45, 0.4, 1.6), Color3.fromRGB(246, 246, 244)),
			left = bit("GullWing", Vector3.new(2.2, 0.08, 0.7), Color3.fromRGB(214, 218, 222)),
			right = bit("GullWing", Vector3.new(2.2, 0.08, 0.7), Color3.fromRGB(214, 218, 222)),
			home = home, out = Vector3.new(math.cos(a), 0.35, math.sin(a)).Unit, flap = math.random() * 6, fled = nil })
	end
	-- THE AIR RUSHING PAST: wisps left behind in the air as you fall through it, so they stream up past you.
	local rush = Instance.new("Part")
	rush.Name = "DiveRush"
	rush.Size = Vector3.new(26, 6, 26)
	rush.Transparency = 1
	rush.Anchored = true
	rush.CanCollide = false
	rush.CanTouch = false
	rush.CanQuery = false
	rush.CFrame = CFrame.new(root.Position - Vector3.new(0, 14, 0))
	rush.Parent = workspace
	table.insert(current.held, rush)
	local wisps = Instance.new("ParticleEmitter")
	wisps.Texture = "rbxasset://textures/particles/smoke_main.dds"
	wisps.Color = ColorSequence.new(Color3.fromRGB(246, 250, 255))
	wisps.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1.6) })
	wisps.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
	wisps.Lifetime = NumberRange.new(0.5, 0.9)
	wisps.Speed = NumberRange.new(0, 1)
	wisps.Shape = Enum.ParticleEmitterShape.Box
	wisps.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	wisps.Rate = 0
	wisps.Parent = rush
	current.rush = rush
	-- WIND STREAKS: long thin lines of air left behind in the sky as you fall, so they whip up past you.
	local streaks = Instance.new("ParticleEmitter")
	streaks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	streaks.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	streaks.LightEmission = 0.4
	streaks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0.05) })
	streaks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	streaks.Lifetime = NumberRange.new(0.25, 0.45)
	streaks.Speed = NumberRange.new(0, 0.5)
	streaks.Shape = Enum.ParticleEmitterShape.Box
	streaks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	streaks.Rate = 0
	-- Stretched along the fall where this Roblox can (Squash), round motes where it cannot.
	pcall(function()
		(streaks :: any).Squash = NumberSequence.new(-2.6)
	end)
	streaks.Parent = rush
	current.streaks = streaks
	-- AIR TRAILS off your hands and feet, the way a skydiver's hands draw lines in the sky.
	for _, limb in ipairs({ "RightHand", "LeftHand", "RightFoot", "LeftFoot", "Right Arm", "Left Arm" }) do
		local part = character and character:FindFirstChild(limb)
		if part and part:IsA("BasePart") then
			local a0 = Instance.new("Attachment")
			a0.Name = "DiveTrailA"
			a0.Position = Vector3.new(0, 0.18, 0)
			a0.Parent = part
			local a1 = Instance.new("Attachment")
			a1.Name = "DiveTrailB"
			a1.Position = Vector3.new(0, -0.18, 0)
			a1.Parent = part
			local trail = Instance.new("Trail")
			trail.Name = "DiveAirTrail"
			trail.Attachment0, trail.Attachment1 = a0, a1
			trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
			trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
			trail.Lifetime = 0.35
			trail.LightEmission = 0.3
			trail.FaceCamera = true
			trail.Parent = part
			for _, made in ipairs({ a0, a1, trail }) do
				table.insert(current.held, made)
			end
		end
	end
	-- THE SUN, flaring as you go out into it.
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		current.sunWas = rays.Intensity
		game:GetService("TweenService"):Create(rays, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Intensity = 0.32 }):Play()
		task.delay(1.8, function()
			if scene == current and current.sunWas then
				game:GetService("TweenService"):Create(rays, TweenInfo.new(1.2), { Intensity = current.sunWas }):Play()
			end
		end)
	end
	if Cinema then
		Cinema.begin()
		Cinema.caption("The High Dive", "Maren said it was the quickest way down. She said it was the only way.", 7)
		-- SCORED: the board letting you go, and the wind rising all the way down. The wind is seven seconds
		-- that grow to their loudest at the end, so it is started to end as they reach the water (the hang
		-- off the board, then the rest of the height at FALL_SPEED), and never before they are off the board.
		Cinema.sound("DiveBoard", 0.9, { fallback = "rbxasset://sounds/button.wav", speed = 0.4, keep = true })
		-- THE SCORE (the two-hundred-and-eleventh pass): wistful, growing as they go up and out over the drop.
		Cinema.score("Shore")
		local fall = HANG_SECONDS + math.max(0, root.Position.Y - water - HANG_SPEED * HANG_SECONDS) / FALL_SPEED
		task.delay(math.max(0.5, fall - 7), function()
			if scene == current then
				current.wind = Cinema.sound("DiveWind", 0.8, { fallback = "rbxasset://sounds/action_falling.mp3", speed = 0.6,
					fadeIn = 0.8 })
			end
		end)
	end
end

-- THE GULLS: circling where they were until you come through, then scattering outward and up, beating hard.
local function moveGulls(current: Scene, here: Vector3, now: number)
	for _, gull in ipairs(current.gulls) do
		if not gull.fled and here.Y - gull.home.Y < 24 then
			gull.fled = now
			-- THROUGH THE FLOCK: an impact frame the first time, as they burst apart round you.
			if not current.hit.gulls and Cinema then
				current.hit.gulls = true
				Cinema.impact(0.8)
			end
		end
		local at, heading
		if gull.fled then
			local since = now - gull.fled
			at = gull.home + gull.out * (since * 34 + since * since * 6)
			heading = gull.out
		else
			local a = now * 0.6 + gull.flap
			at = gull.home + Vector3.new(math.cos(a) * 3, math.sin(a * 1.3) * 0.6, math.sin(a) * 3)
			heading = Vector3.new(-math.sin(a), 0, math.cos(a))
		end
		local frame = CFrame.lookAt(at, at + heading)
		local beat = math.sin(now * (if gull.fled then 16 else 6) + gull.flap) * 0.6
		gull.body.CFrame = frame
		gull.left.CFrame = frame * CFrame.new(-0.2, 0, 0) * CFrame.Angles(0, 0, beat) * CFrame.new(-1.1, 0, 0)
		gull.right.CFrame = frame * CFrame.new(0.2, 0, 0) * CFrame.Angles(0, 0, -beat) * CFrame.new(1.1, 0, 0)
	end
end

-- MAREN, ON YOUR SCREEN, as you go off the board: turned to it, and startled (Poses.startle), her hands coming up.
local function marenReacts(current: Scene, toward: Vector3, since: number)
	local figure = current.marenFigure
	if not (figure and figure.Parent and Poses) then
		return
	end
	if not current.marenJoints then
		current.marenJoints = Poses.joints(figure)
		local pivot = figure:GetPivot()
		figure:PivotTo(CFrame.lookAt(pivot.Position, pivot.Position + toward))
	end
	local joints = current.marenJoints :: { [string]: any }
	local r6 = Poses.isR6(joints)
	local w = math.clamp(since / 0.2, 0, 1)
	for name, joint in pairs(joints) do
		local turn = Poses.startle(name, since, w, r6)
		if turn then
			Poses.drive(joint, turn)
		end
	end
end

-- A part of the scene under the water, this client's alone.
-- THE LIGHT SHAFTS under the water (the two-hundred-and-thirteenth pass): how clear each of a shaft's three beams is
-- at its brightest, and how wide against the shaft; and the fade along it, clear at both ends.
local SHAFT_LAYERS = { { wide = 1, clear = 0.84 }, { wide = 1.7, clear = 0.91 }, { wide = 2.6, clear = 0.955 } }
local function shaftFade(clear: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, clear),
		NumberSequenceKeypoint.new(0.75, clear + (1 - clear) * 0.35), NumberSequenceKeypoint.new(1, 1) })
end

local function under(current: Scene, name: string, size: Vector3, cf: CFrame, colour: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Color = colour
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = workspace
	table.insert(current.held, part)
	return part
end

-- THE CAMERA GOES UNDER: the sea taken off this screen (every part of the backdrop near the splash that lies at the
-- water's level: its wave, its foam, what floats on it), so nothing of it is between the eye and the street; and the
-- surface drawn from underneath instead, a pale ceiling over the dark. Put back when the scene ends (endScene).
local function drown(current: Scene, at: Vector3)
	local backdrop = workspace:FindFirstChild("Backdrop")
	if backdrop then
		for _, item in ipairs(backdrop:GetDescendants()) do
			if item:IsA("BasePart") and item.LocalTransparencyModifier < 1 then
				local half = item.Size / 2
				local reach = math.max(half.X, half.Z)
				local away = Vector2.new(item.Position.X - at.X, item.Position.Z - at.Z).Magnitude - reach
				if away < DROWN_REACH and item.Position.Y - half.Y < current.water + 50 and item.Position.Y + half.Y > current.water - 90 then
					item.LocalTransparencyModifier = 1
					table.insert(current.hidden, item)
				end
			end
		end
	end
	local ceiling = current.ceiling
	if ceiling then
		ceiling.Transparency = 0.15
	end
end

-- THE WATER CLOSES OVER THEM: the dark under the surface round their way down, the drowned street
-- far below with its one lamp still on, bubbles going up, and the view going green and soft.
local function splashed(at: Vector3)
	local current = scene
	if not current or current.splash then
		return
	end
	current.splash = at
	current.splashAt = os.clock()
	local deep = Color3.fromRGB(10, 34, 42)
	local floor = at.Y - DEEP_DOWN
	for _, wall in ipairs({ { Vector3.new(160, DEEP_DOWN + 6, 1), Vector3.new(0, -DEEP_DOWN / 2 + 3, 80) },
		{ Vector3.new(160, DEEP_DOWN + 6, 1), Vector3.new(0, -DEEP_DOWN / 2 + 3, -80) },
		{ Vector3.new(1, DEEP_DOWN + 6, 160), Vector3.new(80, -DEEP_DOWN / 2 + 3, 0) },
		{ Vector3.new(1, DEEP_DOWN + 6, 160), Vector3.new(-80, -DEEP_DOWN / 2 + 3, 0) },
		{ Vector3.new(160, 1, 160), Vector3.new(0, -DEEP_DOWN, 0) } }) do
		under(current, "Deep", wall[1], CFrame.new(at + wall[2]), deep)
	end
	-- THE SURFACE FROM UNDERNEATH, over the whole of it: pale, the light coming down through it. Unseen until the camera
	-- is under (drown): from above it would be a pale square lying on the sea.
	local ceiling = under(current, "SurfaceUnder", Vector3.new(160, 1, 160), CFrame.new(at + Vector3.new(0, 6, 0)), Color3.fromRGB(150, 206, 200))
	ceiling.Transparency = 1
	current.ceiling = ceiling
	-- The street down there: roofs, and the lamp on its post. (Forty studs ahead of where you went in, the two-hundred-and-
	-- thirty-fifth pass: at twenty-two the camera looked at it from almost straight above, and a lamp from above is a
	-- dot on a disc.)
	local street = at + current.facing * 40
	local side = Vector3.new(-current.facing.Z, 0, current.facing.X)
	for index, roof in ipairs({ { -18, 6, 14, 10 }, { 20, -8, 16, 18 }, { -6, -26, 12, 8 }, { 28, 22, 10, 14 } }) do
		under(current, "DrownedRoof", Vector3.new(roof[3], roof[4], roof[3]),
			CFrame.new(street.X + roof[1], floor + roof[4] / 2, street.Z + roof[2]) * CFrame.Angles(0, index * 0.4, 0),
			Color3.fromRGB(26, 44, 50))
	end
	-- THE LAMP, SEEN AS A LAMP (the two-hundred-and-thirty-fifth pass, from your note of 2026-11-10, "the lamp at the
	-- bottom is no longer visible", seen in play on 2026-11-21: the street under it was a pale disc thirty-four studs
	-- across, lit, with a pale ball of halo fifteen across on top, and from above that was all there was, a pale blob,
	-- no post, no lantern). Now: a cobbled street, dark, that only the lamp's own light makes a pool on; a post painted
	-- a lighter iron so that light catches it, twenty studs tall with a crossbar; a lantern of four warm panes in a dark
	-- frame under a pointed cap and a finial; and only a small amber glow round it, as light in murky water has.
	local post = Vector3.new(street.X, floor, street.Z)
	local iron = Color3.fromRGB(70, 86, 84)
	local frameIron = Color3.fromRGB(30, 34, 36)
	local cobbles = under(current, "LampStreet", Vector3.new(30, 0.6, 30), CFrame.new(post + Vector3.new(0, 0.3, 0)),
		Color3.fromRGB(58, 62, 58))
	cobbles.Material = Enum.Material.Cobblestone
	local kerb = under(current, "LampKerb", Vector3.new(30, 0.8, 1.4), CFrame.new(post + side * 4 + Vector3.new(0, 0.4, 0)),
		Color3.fromRGB(84, 86, 80))
	kerb.CFrame = CFrame.lookAt(kerb.Position, kerb.Position + current.facing) * CFrame.Angles(0, math.pi / 2, 0)
	under(current, "LampFoot", Vector3.new(1.8, 1.2, 1.8), CFrame.new(post + Vector3.new(0, 1.2, 0)), iron)
	under(current, "LampPost", Vector3.new(0.8, 20, 0.8), CFrame.new(post + Vector3.new(0, 10.6, 0)), iron)
	under(current, "LampCrossbar", Vector3.new(2.4, 0.3, 0.3), CFrame.new(post + Vector3.new(0, 18, 0)), iron)
	local headAt = post + Vector3.new(0, 21.8, 0)
	local head = under(current, "LampHead", Vector3.new(2.6, 3.2, 2.6), CFrame.new(headAt), Color3.fromRGB(255, 196, 112))
	head.Material = Enum.Material.SmoothPlastic
	-- The frame round the panes: four corner bars, a sill under and a band over.
	for _, corner in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
		under(current, "LampFrame", Vector3.new(0.25, 3.4, 0.25), CFrame.new(headAt + Vector3.new(corner[1] * 1.35, 0, corner[2] * 1.35)),
			frameIron)
	end
	under(current, "LampFrame", Vector3.new(3, 0.3, 3), CFrame.new(headAt - Vector3.new(0, 1.75, 0)), frameIron)
	under(current, "LampFrame", Vector3.new(3.1, 0.3, 3.1), CFrame.new(headAt + Vector3.new(0, 1.75, 0)), frameIron)
	-- The cap stepped to a point: a wide course, a narrower one, and the finial.
	under(current, "LampCap", Vector3.new(2.6, 0.5, 2.6), CFrame.new(headAt + Vector3.new(0, 2.15, 0)), frameIron)
	under(current, "LampCap", Vector3.new(1.6, 0.6, 1.6), CFrame.new(headAt + Vector3.new(0, 2.7, 0)), frameIron)
	under(current, "LampCap", Vector3.new(0.8, 0.5, 0.8), CFrame.new(headAt + Vector3.new(0, 3.25, 0)), frameIron)
	under(current, "LampFinial", Vector3.new(0.35, 0.8, 0.35), CFrame.new(headAt + Vector3.new(0, 3.9, 0)), frameIron)
	-- The lantern is lit by lights that are not inside it (a light inside a part does not light that part): one under
	-- it, which throws the pool on the cobbles and lights the post; one to the side, which is its own panes.
	local glowAt = under(current, "LampGlow", Vector3.new(0.2, 0.2, 0.2), CFrame.new(headAt - Vector3.new(0, 3, 0)),
		Color3.fromRGB(255, 236, 190))
	glowAt.Transparency = 1
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 110)
	light.Brightness = 7
	light.Range = 30
	light.Shadows = false
	light.Parent = glowAt
	local lensAt = under(current, "LampLens", Vector3.new(0.2, 0.2, 0.2), CFrame.new(headAt + side * 2.4 + current.facing * -2.4),
		Color3.fromRGB(255, 236, 190))
	lensAt.Transparency = 1
	local lens = Instance.new("PointLight")
	lens.Color = Color3.fromRGB(255, 214, 150)
	lens.Brightness = 4
	lens.Range = 8
	lens.Shadows = false
	lens.Parent = lensAt
	-- The glow: what a light does to water with silt in it. Two small amber shells, lit by nothing but their own
	-- colour, so they are there on a machine that draws no far lights. (The fifteen-stud pale one was the blob.)
	for index, wide in ipairs({ 4.6, 7.4 }) do
		local halo = under(current, "LampHalo", Vector3.new(wide, wide, wide), CFrame.new(headAt), Color3.fromRGB(255, 186, 104))
		halo.Shape = Enum.PartType.Ball
		halo.Transparency = 0.8 + 0.09 * index
	end
	current.lamp = head.Position
	local column = under(current, "Bubbles", Vector3.new(8, 60, 8), CFrame.new(at - Vector3.new(0, 34, 0)), deep)
	column.Transparency = 1
	local bubbles = Instance.new("ParticleEmitter")
	bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	bubbles.Color = ColorSequence.new(Color3.fromRGB(214, 240, 236))
	bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.6) })
	bubbles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	bubbles.Lifetime = NumberRange.new(2, 4)
	bubbles.Speed = NumberRange.new(3, 7)
	bubbles.EmissionDirection = Enum.NormalId.Top
	bubbles.SpreadAngle = Vector2.new(20, 20)
	bubbles.Rate = 40
	bubbles.Parent = column
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "UnderCityShore"
	tint.TintColor = Color3.fromRGB(150, 206, 204)
	tint.Brightness = -0.08
	tint.Saturation = -0.2
	tint.Enabled = false
	tint.Parent = Lighting
	table.insert(current.held, tint)
	local blur = Instance.new("BlurEffect")
	blur.Name = "UnderCityShore"
	blur.Size = 5
	blur.Enabled = false
	blur.Parent = Lighting
	table.insert(current.held, blur)
	-- (On when the camera goes under after them, not over the moment of the hit, which is seen from the surface.)
	current.underFx = { tint, blur }
	-- UNDER THE WATER: shafts of light slanting down round them from the surface, swaying, and a few fish
	-- going by at the edge of the light.
	for k = 1, 7 do
		local a = k / 7 * math.pi * 2 + math.random()
		local r = 8 + math.random() * 22
		local top = at + Vector3.new(math.cos(a) * r, -1, math.sin(a) * r)
		-- SOFT SHAFTS (the two-hundred-and-thirteenth pass, from your screenshot of 2026-11-13: the light "glitched"):
		-- each was a flat see-through slab 70 studs long, and from under the water they read as hard panes of glass
		-- across the shot. Now each is a beam of light, always turned to the eye, soft at its edges and fading out at
		-- both ends, hung from an unseen holder that sways as the slab did.
		local wide = 2 + math.random() * 3
		local shaft = under(current, "LightShaft", Vector3.new(0.2, 0.2, 0.2),
			CFrame.new(top - Vector3.new(0, 35, 0)) * CFrame.Angles(0, a, 0.18), Color3.fromRGB(200, 236, 230))
		shaft.Transparency = 1
		local high = Instance.new("Attachment")
		high.Position = Vector3.new(0, 35, 0)
		high.Parent = shaft
		local low = Instance.new("Attachment")
		low.Position = Vector3.new(0, -35, 0)
		low.Parent = shaft
		-- Three beams to a shaft, a faint core inside two wider and fainter, so its edges fall away softly (a beam
		-- has no soft edge of its own, and the soft texture tried first does not load); twelve segments, because
		-- a beam of one samples its fade only at its two ends, which are clear, and it vanished.
		local beams: { { beam: Beam, clear: number } } = {}
		for layer, spec in ipairs(SHAFT_LAYERS) do
			local beam = Instance.new("Beam")
			beam.Name = "ShaftLayer" .. layer
			beam.Attachment0 = high
			beam.Attachment1 = low
			beam.FaceCamera = true
			beam.Width0 = wide * spec.wide * 0.7
			beam.Width1 = wide * spec.wide * 1.3
			beam.Segments = 12
			beam.Color = ColorSequence.new(Color3.fromRGB(200, 236, 230))
			beam.LightEmission = 0.2
			beam.LightInfluence = 0.3
			beam.Transparency = shaftFade(spec.clear)
			beam.Parent = shaft
			table.insert(beams, { beam = beam, clear = spec.clear })
		end
		table.insert(current.shafts, { part = shaft, rest = shaft.CFrame, phase = math.random() * 6, beams = beams })
	end
	for k = 1, 5 do
		local depth = 10 + k * 7
		local side = Vector3.new(-current.facing.Z, 0, current.facing.X)
		local from = at - Vector3.new(0, depth, 0) + side * 40 + current.facing * (k * 4 - 10)
		local fish = under(current, "Fish", Vector3.new(0.5, 0.9, 2.2), CFrame.new(from), Color3.fromRGB(34, 60, 66))
		table.insert(current.fish, { part = fish, from = from, to = from - side * 80, speed = 3 + math.random() * 3 })
	end
	-- SCORED: the splash, the wind gone, the hum under the harbour, and after a moment the last chord.
	if Cinema then
		Cinema.fade(current.wind, 0.3)
		Cinema.sound("DiveSplash", 1, { fallback = "rbxasset://sounds/impact_water.mp3", speed = 0.6, keep = true })
		Cinema.climax(1)
		Cinema.sound("UnderwaterHum", 0.55, { looped = true, fadeIn = 1.5 })
		task.delay(2.6, function()
			if scene == current then
				Cinema.sound("ShoreChord", 0.7, { keep = true, fadeIn = 1, alt = "EndChord", altPitch = 0.89 })
			end
		end)
	end
	-- THE SPLASH, on this screen: a crown of spray, a white flash and the camera knocked.
	local crown = under(current, "SplashCrown", Vector3.new(1, 1, 1), CFrame.new(at + Vector3.new(0, 0.5, 0)), Color3.new(1, 1, 1))
	crown.Transparency = 1
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(240, 250, 255))
	spray.LightEmission = 0.3
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.8, 1.6)
	spray.Speed = NumberRange.new(30, 70)
	spray.SpreadAngle = Vector2.new(28, 28)
	spray.Acceleration = Vector3.new(0, -80, 0)
	spray.Drag = 1
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Rate = 0
	spray.Parent = crown
	spray:Emit(160)
	-- FOAM racing out over the water from where they went in.
	local foam = under(current, "SplashFoam", Vector3.new(0.2, 2, 2), CFrame.new(Vector3.new(at.X, current.water + 0.15, at.Z))
		* CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(240, 250, 255))
	foam.Shape = Enum.PartType.Cylinder
	foam.Transparency = 0.2
	game:GetService("TweenService"):Create(foam, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, 30, 30), Transparency = 1 }):Play()
	-- AND UNDER, the air they took in with them: a burst of bubbles round them, going up.
	local gulp = under(current, "EntryBubbles", Vector3.new(3, 3, 3), CFrame.new(at - Vector3.new(0, 4, 0)), Color3.new(1, 1, 1))
	gulp.Transparency = 1
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Color = ColorSequence.new(Color3.fromRGB(226, 246, 244))
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.7) })
	burst.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	burst.Lifetime = NumberRange.new(1, 2.2)
	burst.Speed = NumberRange.new(4, 11)
	burst.SpreadAngle = Vector2.new(70, 70)
	burst.Acceleration = Vector3.new(0, 6, 0)
	burst.Drag = 1.5
	burst.Rate = 0
	burst.Parent = gulp
	burst:Emit(140)
	local flash = Instance.new("ColorCorrectionEffect")
	flash.Name = "SplashFlash"
	flash.Brightness = 0.55
	flash.Parent = Lighting
	table.insert(current.held, flash)
	game:GetService("TweenService"):Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }):Play()
	if Cinema then
		-- THE HIT, held at the surface a moment (SPLASH_HOLD) before the camera goes under: it cut straight under, and
		-- the hit itself was never seen (your test of 2026-10-22: "the final dive in should have more impact on hit").
		Cinema.impact(1.6)
		Cinema.speedLines(0)
		Cinema.shake(2.8)
		Cinema.caption("Harrow Bay", "Somewhere under the water, a street lamp is still on.", 9)
		-- THE STORY IS TOLD once that has been read: the banner may come up, the lobby may take them. The
		-- shot under the water holds until it does.
		Cinema.done()
	end
end

local function stepScene()
	local current = scene
	if not current then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		endScene(true)
		return
	end
	local t = os.clock() - current.began
	local here = root.Position
	-- OVER when the lobby has them, when a dive that was not a dive has put them back up, or at the
	-- latest, long after the water.
	local splash = current.splash
	if splash and ((here - splash).Magnitude > 200 or os.clock() - (current.splashAt :: number) > 60)
		or not splash and ((t > 3.5 and here.Y > current.from.Y - 5 and not root.Anchored) or t > 40) then
		endScene(true)
		return
	end
	-- THE SERVER HAS THE LAST OF THE FALL: drawn here where its carry puts them, every frame, rather than
	-- in the steps it arrives in.
	if root.Anchored and not splash then
		if not current.carryFrom then
			current.carryFrom = here
			current.carryAt = os.clock()
		end
		local surface = current.water - SPLASH_SINK
		local from = current.carryFrom :: Vector3
		local y = math.max(surface, from.Y - CARRY_SPEED * (os.clock() - (current.carryAt :: number)))
		root.CFrame = CFrame.new(Vector3.new(from.X, y, from.Z)) * (root.CFrame - root.CFrame.Position)
		here = root.Position
	end
	-- HEAD FIRST, and SLOW ENOUGH TO WATCH, while their own client has them: held back for the hang off
	-- the board, then no faster than FALL_SPEED down and DRIFT across.
	if not root.Anchored and not splash then
		local v = root.AssemblyLinearVelocity
		local across = Vector3.new(v.X, 0, v.Z)
		if across.Magnitude > DRIFT then
			across = across.Unit * DRIFT
		end
		local limit = if t < HANG_SECONDS then HANG_SPEED else FALL_SPEED
		root.AssemblyLinearVelocity = Vector3.new(across.X, math.max(v.Y, -limit), across.Z)
		local over = math.clamp((t - 0.35) / 1.4, 0, 1)
		over = over * over * (3 - 2 * over)
		-- BUFFETED: once over, the wind rolls and yaws the body a little, never still.
		local wind = math.clamp((t - 1.6) / 0.8, 0, 1)
		local roll = 0.16 * math.noise(t * 1.3, 2.1) * wind
		local yaw = 0.12 * math.noise(t * 0.9, 5.7) * wind
		root.CFrame = CFrame.lookAt(here, here + current.facing) * CFrame.Angles(-math.pi * 0.95 * over, yaw, roll)
		root.AssemblyAngularVelocity = Vector3.zero
	end
	-- THE GULLS, THE AIR, and under the water THE LIGHT AND THE FISH, whatever the camera is doing.
	local now = os.clock()
	pcall(moveGulls, current, here, now)
	local rush = current.rush
	if rush and rush.Parent then
		rush.CFrame = CFrame.new(here - Vector3.new(0, 10, 0))
		local wisps = rush:FindFirstChildOfClass("ParticleEmitter")
		if wisps then
			wisps.Rate = if not splash and t > 1.3 then 60 else 0
		end
		local streaks = current.streaks
		if streaks then
			streaks.Rate = if not splash and t > 1.5 then 90 else 0
		end
	end
	for _, shaft in ipairs(current.shafts) do
		shaft.part.CFrame = shaft.rest * CFrame.Angles(0.04 * math.sin(now * 0.5 + shaft.phase), 0, 0.03 * math.sin(now * 0.4 + shaft.phase))
		-- (The shaft breathes, a little brighter and dimmer.)
		for _, layer in ipairs(shaft.beams or {}) do
			layer.beam.Transparency = shaftFade(math.clamp(layer.clear + 0.03 * math.sin(now * 0.8 + shaft.phase), 0, 1))
		end
	end
	for _, fish in ipairs(current.fish) do
		local since = splash and (now - (current.splashAt :: number)) or 0
		local along = math.clamp(since * fish.speed / (fish.to - fish.from).Magnitude, 0, 1)
		local at = fish.from:Lerp(fish.to, along) + Vector3.new(0, math.sin(since * 2 + fish.speed) * 0.4, 0)
		fish.part.CFrame = CFrame.lookAt(at, at + (fish.to - fish.from).Unit) * CFrame.Angles(0, math.sin(since * 7) * 0.2, 0)
	end
	if not (Cinema and Cinema.active()) then
		return
	end
	local side = Vector3.new(-current.facing.Z, 0, current.facing.X)
	local function shot(name: string)
		if current.shot ~= name then
			-- Maren let go once the camera has left her.
			if current.shot == "maren" and current.marenJoints and Poses then
				for _, joint in pairs(current.marenJoints) do
					Poses.drive(joint, CFrame.identity)
				end
			end
			current.shot = name
			Cinema.cut()
		end
	end
	-- WHAT THEY THINK, once each, over their head.
	local function think(key: string, words: string, seconds: number)
		if not current.hit[key] then
			current.hit[key] = true
			Cinema.think(character, words, seconds)
		end
	end
	if not splash then
		local height = here.Y - current.water
		if t < 1.6 then
			-- THE LEAP: low beside the board, looking up at them going out against the sky; hit as they leave it,
			-- then a slow push in on the hang, the frame tipping as they turn.
			shot("leap")
			if not current.hit.leap and t > 0.18 then
				current.hit.leap = true
				Cinema.impact(1)
			end
			if t > 0.55 then
				think("brave", "Okay. Don't look down.", 1.8)
			end
			-- (Lower and a little wider than it was, aimed under them: close to the lens and falling, their feet went
			-- under the bottom bar for the first moment of it. check_shots.py.)
			local eye = current.tip + side * 7 - current.facing * 3 + Vector3.new(0, -4, 0)
			local tip = 0.12 * math.clamp((t - 0.6) / 1.0, 0, 1)
			Cinema.point(CFrame.lookAt(eye, here + Vector3.new(0, -0.5, 0)) * CFrame.Angles(0, 0, tip), 60 - 10 * math.min(1, t / 1.6))
		elseif t < 2.7 and current.maren and current.maren.Parent then
			-- MAREN, as you go: she turns to the board and starts, her hands coming up, seen from the board's side. (It
			-- was over her shoulder looking down past her at you, and she stands thirty studs back from the tip: the
			-- deck's own floor filled the picture. Your test of 2026-10-22, "the camera is covered by a plane".)
			shot("maren")
			local head = (current.maren :: BasePart).Position
			local toward = Vector3.new(current.tip.X - head.X, 0, current.tip.Z - head.Z)
			toward = if toward.Magnitude > 0.1 then toward.Unit else current.facing
			pcall(marenReacts, current, toward, t - 1.6)
			local ignore: { Instance } = { character :: Instance }
			if current.marenFigure then
				table.insert(ignore, current.marenFigure :: Instance)
			end
			local eye = Cinema.clear(head + toward * 6 + Vector3.new(-toward.Z, 0, toward.X) * 1.5 - Vector3.new(0, 0.5, 0),
				head, ignore)
			Cinema.point(CFrame.lookAt(eye, head - Vector3.new(0, 1, 0)), 50)
		elseif t < 4.2 then
			-- THE TURN: close, going round them as they turn head down, the speed starting to show.
			shot("turn")
			if t > 3.1 then
				think("looked", "I looked down.", 1.6)
			end
			Cinema.speedLines(0.35 * math.clamp((t - 2.7) / 1.5, 0, 1))
			local a = (t - 2.7) * 0.9
			local round = side * math.cos(a) + current.facing * math.sin(a)
			Cinema.point(CFrame.lookAt(here + round * 12 + Vector3.new(0, -3, 0), here) * CFrame.Angles(0, 0, -0.1), 64)
		elseif height > WATER_SHOT then
			-- How far down the drop they are, from where it began to where the camera goes to the water.
			local top = current.dropTop or height
			current.dropTop = top
			local down = math.clamp((top - height) / math.max(1, top - WATER_SHOT), 0, 1)
			if down >= 0.5 then
				-- THEIR FACE, close, from under it, for the second half of the drop: head first at the water (their face
				-- is to the tower, upside down, after the turn), the wind in it and the sky behind, and what they tell
				-- themselves. (The drop is two seconds: split three ways, no shot of it lasted long enough to read.)
				shot("face")
				think("arms", "Arms together. Arms together!", 2)
				Cinema.shake(0.6)
				Cinema.speedLines(0.85)
				local headPart = character and character:FindFirstChild("Head")
				local face = if headPart and headPart:IsA("BasePart") then headPart.Position else here
				local eye = Cinema.clear(face - current.facing * 4.2 - Vector3.new(0, 2.2, 0) + side * 1.1, face, { character })
				Cinema.point(CFrame.lookAt(eye, face) * CFrame.Angles(0, 0, 0.07 * math.sin(t * 2.3)), 58)
			else
				-- THE DROP: over them and a little behind, falling with them, looking down past them at the sea
				-- coming up at them: where they are going, they in the top half of the picture and the sea filling the
				-- rest. Leaning into the fall, the frame rocking with the wind, wide, so the speed shows. (It looked a
				-- third of the way to the sea, and they were under the top bar the whole time: check_shots.py.)
				shot("drop")
				Cinema.shake(0.5)
				Cinema.speedLines(0.75)
				local lean = 0.14 + 0.06 * math.sin(t * 1.7)
				-- (Kept clear of anything of the tower's still beside them, near the top.)
				local eye = Cinema.clear(here + Vector3.new(0, 9, 0) - current.facing * 4 + side * 2.5, here, { character })
				Cinema.point(CFrame.lookAt(eye, here - Vector3.new(0, 22, 0), current.facing) * CFrame.Angles(0, 0, lean), 78)
			end
		else
			-- THE WATER: from the surface, low, as they come down at it. Aimed ahead of their fall, under them: aimed at
			-- them, the camera turned after them too slowly in the last moment and they fell out of the picture.
			shot("water")
			Cinema.speedLines(0.35)
			local below = Vector3.new(here.X, current.water, here.Z)
			Cinema.point(CFrame.lookAt(below + current.facing * 22 + side * 6 + Vector3.new(0, 2.5, 0), here - Vector3.new(0, 14, 0)), 50)
		end
	elseif os.clock() - (current.splashAt :: number) < SPLASH_HOLD then
		-- THE HIT, from the surface where the camera watched them come in, turning up to the spray going up out of
		-- the water, the foam racing out, the flash and the jolt. (No cut: the same eye, looking up at it.)
		current.shot = "splash"
		local below = Vector3.new(splash.X, current.water, splash.Z)
		Cinema.point(CFrame.lookAt(below + current.facing * 22 + side * 6 + Vector3.new(0, 2.5, 0), below + Vector3.new(0, 6, 0)), 52)
	else
		-- UNDER: behind them and a little over them (never above the surface), on them as they sink for two seconds,
		-- then tilting down past them to the lamp on the drowned street. It was in front of them and turned toward
		-- the lamp at once, and they were behind the camera within a second.
		if current.shot ~= "under" then
			shot("under")
			drown(current, splash)
			for _, fx in ipairs(current.underFx) do
				fx.Enabled = true
			end
		end
		local since = os.clock() - (current.splashAt :: number)
		local eye = here - current.facing * 7 + side * 1.5 + Vector3.new(0, 3 - math.min(since, 10) * 0.2, 0)
		eye = Vector3.new(eye.X, math.min(eye.Y, current.water - 1.5), eye.Z)
		local lamp = current.lamp or (here - Vector3.new(0, 100, 0))
		-- (Further onto the lamp than before, the two-hundred-and-thirty-fifth pass: it sits a little under the middle of the
		-- picture, below the card that comes up over the middle at the end.)
		Cinema.point(CFrame.lookAt(eye, here:Lerp(lamp, math.clamp((since - 2) / 3.5, 0, 0.92))), 62)
	end
end

function CityShoreClient.start()
	if Cinema and Cinema.onLeave then
		Cinema.onLeave(function()
			endScene(true)
		end)
	end
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	local event = remotes and remotes:WaitForChild("DiveCinema", 20)
	if not (event and event:IsA("RemoteEvent")) then
		warn("CityShoreClient: no RemoteEvents.DiveCinema, so the dive is not played as a scene. The server Bootstrap "
			.. "makes it; paste src/Server/Bootstrap.server.lua.")
		return
	end
	event.OnClientEvent:Connect(function(kind: any, player: any, a: any, b: any, c: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end
		if kind == "dive" then
			if Poses then
				divers[player] = { began = os.clock(), ends = os.clock() + 12 }
				if not stepped then
					stepped = RunService.Stepped:Connect(function()
						pcall(poseDivers)
					end)
				end
			end
			if player == Players.LocalPlayer and typeof(b) == "number" and typeof(c) == "Vector3" then
				beginScene(b, c)
			end
		elseif kind == "splash" then
			local d = divers[player]
			if d then
				d.ends = os.clock() + 1.5
			end
			if player == Players.LocalPlayer and typeof(a) == "Vector3" then
				splashed(a)
			end
		end
	end)
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(stepScene)
		if not ok then
			warn("CityShoreClient: the dive's scene failed, and the camera is given back: " .. tostring(err))
			pcall(endScene, true)
		end
	end)
	print("CityShoreClient: running, " .. CityShoreClient.VERSION)
end

CityShoreClient.STAMP = "b1d8bd87"
return CityShoreClient
