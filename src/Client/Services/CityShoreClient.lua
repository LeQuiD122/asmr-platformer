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
--   THE DROP        falling with them, from just under them looking up: the tower and the sky going
--                   away above, the wind in the picture.
--   THE WATER       from the surface, low, as they come down at it: only in the last second or so, when
--                   they are near enough to see.
--   THE SPLASH      spray thrown up, a white flash, the camera knocked.
--   UNDER           the water closes over them and the camera follows them down into the dark, shafts of
--                   light slanting down round them and a few fish going by, and far below a street lamp
--                   is still on, on a street that is under the sea (Harrow Bay's other end: the Sunken
--                   City). Held until the lobby takes them.
--
-- AND THINGS HAPPEN ON THE WAY DOWN: the sun flares as you leave the board, you drop through a flock of
-- gulls that bursts apart round you, and the air rushes past. SCORED (Cinema.sound; audio/endings): the
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
CityShoreClient.VERSION = "twenty-first pass, 2026-09-30"

type Gull = { body: BasePart, left: BasePart, right: BasePart, home: Vector3, out: Vector3, flap: number, fled: number? }
type Scene = { began: number, water: number, tip: Vector3, from: Vector3, facing: Vector3, splash: Vector3?,
	splashAt: number?, lamp: Vector3?, held: { Instance }, carryFrom: Vector3?, carryAt: number?, told: boolean,
	shot: string?, maren: BasePart?, gulls: { Gull }, rush: BasePart?, wind: Sound?, sunWas: number?,
	shafts: { { part: BasePart, rest: CFrame, phase: number } }, fish: { { part: BasePart, from: Vector3, to: Vector3, speed: number } } }
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
		wind = nil, sunWas = nil, shafts = {}, fish = {} }
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

-- A part of the scene under the water, this client's alone.
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
	local floor = at.Y - 120
	for _, wall in ipairs({ { Vector3.new(160, 120, 1), Vector3.new(0, -60, 80) }, { Vector3.new(160, 120, 1), Vector3.new(0, -60, -80) },
		{ Vector3.new(1, 120, 160), Vector3.new(80, -60, 0) }, { Vector3.new(1, 120, 160), Vector3.new(-80, -60, 0) },
		{ Vector3.new(160, 1, 160), Vector3.new(0, -120, 0) } }) do
		under(current, "Deep", wall[1], CFrame.new(at + wall[2]), deep)
	end
	-- The street down there: roofs, and the lamp on its post.
	local street = at + current.facing * 22
	for index, roof in ipairs({ { -18, 6, 14, 10 }, { 20, -8, 16, 18 }, { -6, -26, 12, 8 }, { 28, 22, 10, 14 } }) do
		under(current, "DrownedRoof", Vector3.new(roof[3], roof[4], roof[3]),
			CFrame.new(street.X + roof[1], floor + roof[4] / 2, street.Z + roof[2]) * CFrame.Angles(0, index * 0.4, 0),
			Color3.fromRGB(26, 44, 50))
	end
	local post = Vector3.new(street.X, floor, street.Z)
	under(current, "LampPost", Vector3.new(0.6, 14, 0.6), CFrame.new(post + Vector3.new(0, 7, 0)), Color3.fromRGB(40, 46, 50))
	local head = under(current, "LampHead", Vector3.new(1.4, 1.2, 1.4), CFrame.new(post + Vector3.new(0, 14.4, 0)),
		Color3.fromRGB(250, 226, 170))
	head.Transparency = 0.2
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 206, 140)
	light.Brightness = 3
	light.Range = 40
	light.Parent = head
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
	tint.Parent = Lighting
	table.insert(current.held, tint)
	local blur = Instance.new("BlurEffect")
	blur.Name = "UnderCityShore"
	blur.Size = 5
	blur.Parent = Lighting
	table.insert(current.held, blur)
	-- UNDER THE WATER: shafts of light slanting down round them from the surface, swaying, and a few fish
	-- going by at the edge of the light.
	for k = 1, 7 do
		local a = k / 7 * math.pi * 2 + math.random()
		local r = 8 + math.random() * 22
		local top = at + Vector3.new(math.cos(a) * r, -1, math.sin(a) * r)
		local shaft = under(current, "LightShaft", Vector3.new(2 + math.random() * 3, 70, 0.2),
			CFrame.new(top - Vector3.new(0, 35, 0)) * CFrame.Angles(0, a, 0.18), Color3.fromRGB(200, 236, 230))
		shaft.Transparency = 0.9
		shaft.Material = Enum.Material.SmoothPlastic
		table.insert(current.shafts, { part = shaft, rest = shaft.CFrame, phase = math.random() * 6 })
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
		Cinema.sound("UnderwaterHum", 0.55, { looped = true, fadeIn = 1.5 })
		task.delay(2.6, function()
			if scene == current then
				Cinema.sound("ShoreChord", 0.7, { keep = true, fadeIn = 1 })
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
	local flash = Instance.new("ColorCorrectionEffect")
	flash.Name = "SplashFlash"
	flash.Brightness = 0.55
	flash.Parent = Lighting
	table.insert(current.held, flash)
	game:GetService("TweenService"):Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }):Play()
	if Cinema then
		Cinema.cut()
		Cinema.shake(2.4)
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
		root.CFrame = CFrame.lookAt(here, here + current.facing) * CFrame.Angles(-math.pi * 0.95 * over, 0, 0)
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
			wisps.Rate = if not splash and t > 1.3 then 45 else 0
		end
	end
	for _, shaft in ipairs(current.shafts) do
		shaft.part.CFrame = shaft.rest * CFrame.Angles(0.04 * math.sin(now * 0.5 + shaft.phase), 0, 0.03 * math.sin(now * 0.4 + shaft.phase))
		shaft.part.Transparency = 0.86 + 0.06 * math.sin(now * 0.8 + shaft.phase)
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
			current.shot = name
			Cinema.cut()
		end
	end
	if not splash then
		local height = here.Y - current.water
		if t < 1.6 then
			-- THE LEAP: low beside the board, looking up at them going out against the sky.
			shot("leap")
			local eye = current.tip + side * 7 - current.facing * 3 + Vector3.new(0, -2.5, 0)
			Cinema.point(CFrame.lookAt(eye, here + Vector3.new(0, 1, 0)), 56 - 4 * math.min(1, t / 1.6))
		elseif t < 2.7 and current.maren and current.maren.Parent then
			-- MAREN: over her shoulder on the deck, looking down past her at them dropping away.
			shot("maren")
			local head = (current.maren :: BasePart).Position
			local toward = Vector3.new(here.X - head.X, 0, here.Z - head.Z)
			toward = if toward.Magnitude > 0.1 then toward.Unit else current.facing
			local eye = head - toward * 3.2 + Vector3.new(0, 1.3, 0) + Vector3.new(-toward.Z, 0, toward.X) * 1.4
			Cinema.point(CFrame.lookAt(eye, here), 44)
		elseif t < 4.2 then
			-- THE TURN: close, going round them as they turn head down.
			shot("turn")
			local a = (t - 2.7) * 0.9
			local round = side * math.cos(a) + current.facing * math.sin(a)
			Cinema.point(CFrame.lookAt(here + round * 12 + Vector3.new(0, -3, 0), here), 60)
		elseif height > WATER_SHOT then
			-- THE DROP: just under them, falling with them, looking up past them at the sky.
			shot("drop")
			Cinema.shake(0.35)
			local eye = here + Vector3.new(0, -16, 0) + current.facing * 5 + side * 2
			Cinema.point(CFrame.lookAt(eye, here + Vector3.new(0, 6, 0), current.facing), 72)
		else
			-- THE WATER: from the surface, low, as they come down at it.
			shot("water")
			local below = Vector3.new(here.X, current.water, here.Z)
			Cinema.point(CFrame.lookAt(below + current.facing * 22 + side * 6 + Vector3.new(0, 2.5, 0), here), 50)
		end
	else
		local since = os.clock() - (current.splashAt :: number)
		local eye = here + Vector3.new(0, -3 - math.min(since, 10) * 0.8, 0) + current.facing * 7
		local lamp = current.lamp or (here - Vector3.new(0, 100, 0))
		Cinema.point(CFrame.lookAt(eye, here:Lerp(lamp, math.clamp(since / 5, 0, 0.7))), 64)
	end
end

function CityShoreClient.start()
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

return CityShoreClient
