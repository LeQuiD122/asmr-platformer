--!strict
-- StarterPlayerScripts/Services/SkyPoolsClient.lua
-- Sky Pools, on each client: the pools answer when you walk into them, and the toys drift.
--
-- === The water ===
--
-- The pools are Roblox terrain water now, so the swimming, the waves and the view from under the
-- surface are the engine's. What is here is what the engine does not do: for your own character
-- only (everyone else's pool is their own business, and their client does the same for them),
--
--   STEP IN and it splashes: spray where you broke the surface and the project's water sound.
--   WADE and it ripples: a ring spreading out from you on the surface every few steps, with a
--   quieter slosh, only while you are actually moving.
--
-- === The falls ===
--
-- A waterfall is built as three sheets of glass, which is the right shape and none of the motion.
-- Light runs down them here: each sheet's transparency breathes on a wave travelling downward, out
-- of step with its neighbours, so the fall reads as water moving past rather than as a pane. Local,
-- like everything else in this file, because nobody can touch it and replicating it would cost a
-- stream of updates for a shimmer.
--
-- === The ride ===
--
-- The slide at the end is ridden in a sled, and the rider's own client draws it: the server sits you
-- in it, hands it over, and from then on every frame of the ride is worked out here from
-- ReplicatedStorage.Shared.SkyPath and the moment it started. That is why it is smooth. The server
-- still owns the clock and still says where the ride ends, so nothing here decides anything; if this
-- file is not in the place at all, the server drives the sled itself and the ride still happens.
--
-- The rings are twelve short slivers laid in a circle and grown outward, because Roblox has no ring
-- shape and a flat disc growing reads as a stain rather than a ripple.
--
-- === The toys ===
--
-- SkyPoolsService floats a duck or a swim ring in most pools and puts how far each may drift on it.
-- Here they bob, turn slowly, and wander round their pool on a slow figure that never repeats on a
-- count. Moved locally for the reason SeaService moves City Shore's sea: replicating it would cost
-- every player a stream of updates for something nobody can touch.
--
-- === The sky ===
--
-- The hot air balloons drift round the level on the orbit SkyPoolsService gives each, from the
-- server clock so every player sees them in the same place, and now and then a burner flares. Two
-- flocks of gulls, made here and nowhere else, wheel round the fountain tower: the level's only
-- other living thing, and a calm one.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- The slide's shape and timing, shared with the server. Looked for with a timeout: without it there
-- is no ride drawn here, which the server copes with, so it must not stop the rest of this.
local skyPathModule = ReplicatedStorage:WaitForChild("Shared", 10)
skyPathModule = if skyPathModule then skyPathModule:WaitForChild("SkyPath", 10) else nil
local SkyPath: any = if skyPathModule and skyPathModule:IsA("ModuleScript") then require(skyPathModule) else nil

local SkyPoolsClient = {}

local WATER_SOUND = "rbxasset://sounds/impact_water.mp3"
local RIPPLE_EVERY = 0.45 -- seconds between rings while wading
local RIPPLE_LIFE = 1.4
local RIPPLE_FROM, RIPPLE_TO = 0.8, 4.5
local SLIVERS = 12
local WADE_SPEED = 3 -- studs a second, below which you are standing, not wading

type Ripple = { parts: { BasePart }, centre: Vector3, born: number }

local BALLOON_SPIN = 0.006 -- radians a second round the level: a full turn in about eighteen minutes
local GULL_BODY = Color3.fromRGB(246, 246, 244)
local GULL_WING = Color3.fromRGB(214, 218, 222)

type Gull = { body: BasePart, left: BasePart, right: BasePart, offset: Vector3, flap: number }
type Flock = { gulls: { Gull }, radius: number, height: number, speed: number, holder: Folder }

local balloons: { [Model]: { centre: Vector3, orbit: number, height: number, phase: number, flame: PointLight?, flareAt: number } } = {}
local flocks: { [Instance]: { centre: Vector3, list: { Flock } } } = {}
local pools: { BasePart } = {}
local toys: { [Model]: { rest: CFrame, drift: Vector2, phase: number } } = {}
local ripples: { Ripple } = {}
local wasIn = false
local lastRipple = 0

-- Where a pool's water is, relative to a point: whether the point is over it, and its surface height.
local function over(pool: BasePart, point: Vector3): (boolean, number)
	if pool.Shape == Enum.PartType.Cylinder then
		-- The final pool: an upright cylinder, lying along X before its roll, so its height is Size.X.
		local flat = Vector3.new(point.X - pool.Position.X, 0, point.Z - pool.Position.Z).Magnitude
		return flat < pool.Size.Y / 2, pool.Position.Y + pool.Size.X / 2
	end
	local p = pool.CFrame:PointToObjectSpace(point)
	local half = pool.Size / 2
	return math.abs(p.X) <= half.X + 0.5 and math.abs(p.Z) <= half.Z + 0.5, pool.Position.Y + half.Y
end

-- How far under its surface a pool still counts as that pool. A terrace pool says so on itself; for
-- anything that does not, six studs is a wade rather than a fall past it.
local function depthOf(pool: BasePart): number
	local deep = pool:GetAttribute("Deep")
	return if typeof(deep) == "number" then deep + 2 else 6
end

local function sliver(parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = "Ripple"
	part.Size = Vector3.new(0.25, 0.06, 0.9)
	part.Color = Color3.fromRGB(236, 250, 255)
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local function play(speed: number, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = WATER_SOUND
	s.PlaybackSpeed = speed
	s.Volume = volume
	s.Parent = SoundService
	s:Play()
	task.delay(2, function()
		s:Destroy()
	end)
end

local function splash(at: Vector3)
	local host = Instance.new("Part")
	host.Name = "PoolSplash"
	host.Size = Vector3.new(1, 1, 1)
	host.CFrame = CFrame.new(at)
	host.Anchored = true
	host.CanCollide = false
	host.CanTouch = false
	host.CanQuery = false
	host.Transparency = 1
	host.Parent = workspace
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(236, 250, 255))
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.4, 0.8)
	spray.Speed = NumberRange.new(6, 12)
	spray.SpreadAngle = Vector2.new(35, 35)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Acceleration = Vector3.new(0, -50, 0)
	spray.Rate = 0
	spray.Parent = host
	spray:Emit(28)
	play(1.1 + math.random() * 0.2, 0.4)
	task.delay(1.5, function()
		host:Destroy()
	end)
end

local function ripple(at: Vector3)
	local holder = Instance.new("Folder")
	holder.Name = "RippleRing"
	holder.Parent = workspace
	local parts = {}
	for _ = 1, SLIVERS do
		table.insert(parts, sliver(holder))
	end
	table.insert(ripples, { parts = parts, centre = at, born = os.clock() })
	play(1.5 + math.random() * 0.3, 0.12)
end

local function gullPart(parent: Instance, name: string, size: Vector3, colour: Color3): Part
	local part = sliver(parent)
	part.Name = name
	part.Size = size
	part.Color = colour
	return part
end

-- Two flocks round the tower of a Sky Pools level that has just appeared: one lower and wider, one
-- higher and closer, going opposite ways.
local function flocksFor(level: Instance)
	local centre = level:GetAttribute("SlideCentre")
	local top = level:GetAttribute("TowerTop")
	local count = level:GetAttribute("Gulls")
	if typeof(centre) ~= "Vector3" or typeof(top) ~= "number" then
		return
	end
	local many = if typeof(count) == "number" then count else 7
	local list = {}
	for index, spec in ipairs({ { 110, top - 24, 0.11 }, { 60, top + 8, -0.15 } }) do
		local holder = Instance.new("Folder")
		holder.Name = "Gulls" .. index
		holder.Parent = workspace
		local gulls = {}
		for k = 1, many do
			local body = gullPart(holder, "Gull", Vector3.new(0.35, 0.3, 1.3), GULL_BODY)
			local left = gullPart(holder, "Wing", Vector3.new(1.8, 0.06, 0.6), GULL_WING)
			local right = gullPart(holder, "Wing", Vector3.new(1.8, 0.06, 0.6), GULL_WING)
			-- A loose V behind the leader, never quite in step.
			local row = math.ceil((k - 1) / 2)
			local side = if k % 2 == 0 then 1 else -1
			table.insert(gulls, { body = body, left = left, right = right, flap = math.random() * 6,
				offset = Vector3.new(side * row * 2.4 + math.random() * 0.8, math.random() * 1.5, row * 2.2) })
		end
		table.insert(list, { gulls = gulls, radius = spec[1], height = spec[2], speed = spec[3], holder = holder })
	end
	flocks[level] = { centre = centre, list = list }
end

local function moveSky(serverNow: number, clock: number)
	for model, balloon in pairs(balloons) do
		if model.Parent then
			local a = balloon.phase + serverNow * BALLOON_SPIN
			local bob = 2 * math.sin(serverNow * 0.2 + balloon.phase)
			local at = balloon.centre + Vector3.new(math.cos(a) * balloon.orbit, balloon.height + bob, math.sin(a) * balloon.orbit)
			model:PivotTo(CFrame.new(at) * CFrame.Angles(0, -a, 0))
			-- The burner, flaring for a second now and then, the way a pilot keeps height.
			local flame = balloon.flame
			if flame then
				if clock >= balloon.flareAt then
					balloon.flareAt = clock + 6 + math.random() * 10
					flame.Brightness = 1.6
					task.delay(1.1, function()
						flame.Brightness = 0.6
					end)
				end
			end
		end
	end
	for _, entry in pairs(flocks) do
		for _, flock in ipairs(entry.list) do
			local a = serverNow * flock.speed
			local lead = entry.centre + Vector3.new(math.cos(a) * flock.radius, flock.height + 3 * math.sin(serverNow * 0.3), math.sin(a) * flock.radius)
			local tangent = Vector3.new(-math.sin(a), 0, math.cos(a)) * (if flock.speed >= 0 then 1 else -1)
			local heading = CFrame.lookAt(lead, lead + tangent)
			for _, gull in ipairs(flock.gulls) do
				local frame = heading * CFrame.new(gull.offset)
				local beat = math.sin(clock * 5 + gull.flap) * 0.5
				gull.body.CFrame = frame
				gull.left.CFrame = frame * CFrame.new(-0.2, 0, 0) * CFrame.Angles(0, 0, beat) * CFrame.new(-0.9, 0, 0)
				gull.right.CFrame = frame * CFrame.new(0.2, 0, 0) * CFrame.Angles(0, 0, -beat) * CFrame.new(0.9, 0, 0)
			end
		end
	end
end

-- ===== THE FALLS =====

local FALL_WAVE = 1.9 -- how fast the shimmer travels down a fall, in waves a second
local falls: { [BasePart]: { phase: number, alpha: number } } = {}

local function fallAdded(item: Instance)
	local phase = item:GetAttribute("Veil")
	local alpha = item:GetAttribute("Alpha")
	if item:IsA("BasePart") and typeof(phase) == "number" and typeof(alpha) == "number" then
		falls[item] = { phase = phase, alpha = alpha }
	end
end

local function moveFalls(now: number)
	for part, fall in pairs(falls) do
		if part.Parent then
			-- Down the fall, not across it: the phase carries the piece's place in the sheet, so
			-- the bright band travels from the lip toward the bottom.
			local wave = math.sin((now * FALL_WAVE - fall.phase * 0.55) * math.pi * 2)
			part.Transparency = math.clamp(fall.alpha + wave * 0.07, 0, 1)
		else
			falls[part] = nil
		end
	end
end

-- ===== THE RIDE =====
--
-- One at a time, and only ever your own: the server fires this client with the sled it has just sat
-- you in, and from then until the ride's time is up, the sled's seat is written here every frame.
type Ride = { sled: Model, seat: BasePart, spec: any, distances: { number }, startAt: number, seconds: number }
local ride: Ride? = nil
local rideRemote: RemoteEvent? = nil

-- ===== WHAT THE RIDE LOOKS LIKE FROM INSIDE IT =====
--
-- The slide was eight to fifteen seconds with nothing on screen to say it was happening. This is
-- the smallest thing that fixes that and the most that belongs on a calm level: the edges of the
-- screen draw in a little, two soft bands blur past to give the speed somewhere to read, and one
-- line of text counts the drop down to the water. It arrives as you leave the deck and is gone
-- before the banner comes up, so the ending still belongs to the ending.
local rideGui: ScreenGui? = nil
local rideParts: { [string]: any } = {}

local function ensureRideGui()
	if rideGui and rideGui.Parent then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "SkyRideOverlay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 30
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- The two bands: top and bottom, the colour of the slide, fading toward the middle.
	local bands = {}
	for index, top in ipairs({ true, false }) do
		local band = Instance.new("Frame")
		band.Name = if top then "RushTop" else "RushBottom"
		band.BackgroundColor3 = Color3.fromRGB(186, 172, 240)
		band.BackgroundTransparency = 1
		band.BorderSizePixel = 0
		band.Size = UDim2.new(1, 0, 0.3, 0)
		band.Position = if top then UDim2.fromScale(0, 0) else UDim2.fromScale(0, 0.7)
		band.Parent = gui
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = if top
			then NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
			else NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.35) })
		fade.Parent = band
		bands[index] = band
	end

	local drop = Instance.new("TextLabel")
	drop.Name = "Drop"
	drop.BackgroundTransparency = 1
	drop.AnchorPoint = Vector2.new(0.5, 0)
	drop.Position = UDim2.new(0.5, 0, 0.1, 0)
	drop.Size = UDim2.new(0, 320, 0, 34)
	drop.Font = Enum.Font.GothamBold
	drop.TextSize = 26
	drop.TextColor3 = Color3.fromRGB(246, 248, 255)
	drop.TextTransparency = 1
	drop.TextStrokeTransparency = 0.7
	drop.Text = ""
	drop.Parent = gui

	local caption = Instance.new("TextLabel")
	caption.Name = "Caption"
	caption.BackgroundTransparency = 1
	caption.AnchorPoint = Vector2.new(0.5, 0)
	caption.Position = UDim2.new(0.5, 0, 0.1, 30)
	caption.Size = UDim2.new(0, 320, 0, 20)
	caption.Font = Enum.Font.Gotham
	caption.TextSize = 14
	caption.TextColor3 = Color3.fromRGB(206, 214, 236)
	caption.TextTransparency = 1
	caption.Text = "TO THE POOL"
	caption.Parent = gui

	-- The splash: one white frame that flashes as you hit the water and fades off it.
	local splashFlash = Instance.new("Frame")
	splashFlash.Name = "Splash"
	splashFlash.BackgroundColor3 = Color3.fromRGB(236, 250, 255)
	splashFlash.BackgroundTransparency = 1
	splashFlash.BorderSizePixel = 0
	splashFlash.Size = UDim2.fromScale(1, 1)
	splashFlash.Parent = gui

	rideGui = gui
	rideParts = { bands = bands, drop = drop, caption = caption, flash = splashFlash }
end

local function showRide(on: boolean)
	ensureRideGui()
	local gui = rideGui
	if not gui then
		return
	end
	gui.Enabled = true
	local seconds = if on then 0.5 else 0.7
	local tween = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, band in ipairs(rideParts.bands) do
		TweenService:Create(band, tween, { BackgroundTransparency = if on then 0.55 else 1 }):Play()
	end
	TweenService:Create(rideParts.drop, tween, { TextTransparency = if on then 0 else 1 }):Play()
	TweenService:Create(rideParts.caption, tween, { TextTransparency = if on then 0.25 else 1 }):Play()
	if not on then
		task.delay(seconds + 0.1, function()
			if gui.Parent and not ride then
				gui.Enabled = false
			end
		end)
	end
end

-- The splash, at the moment the ride runs out: a flash that clears in half a second.
local function splashFlash()
	ensureRideGui()
	local flash = rideParts.flash
	if not flash then
		return
	end
	flash.BackgroundTransparency = 0.45
	TweenService:Create(flash, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }):Play()
end

local function rideStarted(sled: Instance)
	if not (SkyPath and sled:IsA("Model")) then
		return
	end
	local spec = SkyPath.read(sled)
	local startAt, seconds = sled:GetAttribute("RideStart"), sled:GetAttribute("RideSeconds")
	-- The model arrives before its PrimaryPart is necessarily set, so the seat is waited for.
	local seat = sled.PrimaryPart or sled:FindFirstChild("SledSeat") or sled:WaitForChild("SledSeat", 5)
	if not (spec and typeof(startAt) == "number" and typeof(seconds) == "number" and seat and seat:IsA("BasePart")) then
		return
	end
	ride = { sled = sled, seat = seat, spec = spec, distances = SkyPath.distances(spec), startAt = startAt,
		seconds = seconds }
	showRide(true)
	-- The one thing this says back: the sled is on screen, so the server may hand it over.
	if rideRemote then
		rideRemote:FireServer()
	end
end

local function moveSled(serverNow: number)
	local current = ride
	if not current then
		return
	end
	if not current.sled.Parent or not current.seat.Parent then
		ride = nil
		showRide(false)
		return
	end
	local u = (serverNow - current.startAt) / current.seconds
	if u >= 1 then
		ride = nil
		splashFlash()
		showRide(false)
		return
	end
	-- How far there is left to fall, which is the one number worth showing on a slide.
	local left = math.max(0, current.seat.Position.Y - current.spec.y1)
	rideParts.drop.Text = ("%d studs"):format(left)
	current.seat.CFrame = SkyPath.rideFrame(current.spec, current.distances, u)
	-- It is unanchored while this client has it, so gravity would pull at it between frames.
	current.seat.AssemblyLinearVelocity = Vector3.zero
	current.seat.AssemblyAngularVelocity = Vector3.zero
end

local function step()
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	moveSky(serverNow, now)
	moveSled(serverNow)
	moveFalls(now)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local feet = root.Position - Vector3.new(0, 3, 0)
		local inWater, surface = false, 0
		for _, pool in ipairs(pools) do
			if pool.Parent then
				local isOver, top = over(pool, root.Position)
				-- In the water when you are over it with your feet below its top, and not far below it
				-- (falling past a pool is not wading in it).
				if isOver and feet.Y < top and feet.Y > top - depthOf(pool) then
					inWater, surface = true, top
					break
				end
			end
		end
		if inWater and not wasIn then
			splash(Vector3.new(root.Position.X, surface, root.Position.Z))
			lastRipple = now
		elseif inWater then
			local v = root.AssemblyLinearVelocity
			if Vector3.new(v.X, 0, v.Z).Magnitude > WADE_SPEED and now - lastRipple > RIPPLE_EVERY then
				lastRipple = now
				ripple(Vector3.new(root.Position.X, surface + 0.05, root.Position.Z))
			end
		end
		wasIn = inWater
	end

	for index = #ripples, 1, -1 do
		local r = ripples[index]
		local u = (now - r.born) / RIPPLE_LIFE
		if u >= 1 then
			if r.parts[1] and r.parts[1].Parent then
				(r.parts[1].Parent :: Instance):Destroy()
			end
			table.remove(ripples, index)
		else
			local radius = RIPPLE_FROM + (RIPPLE_TO - RIPPLE_FROM) * (1 - (1 - u) * (1 - u))
			for k, part in ipairs(r.parts) do
				local a = k * 2 * math.pi / SLIVERS
				part.CFrame = CFrame.new(r.centre) * CFrame.Angles(0, -a, 0) * CFrame.new(radius, 0, 0)
				part.Size = Vector3.new(0.25, 0.06, 2 * math.pi * radius / SLIVERS * 0.8)
				part.Transparency = 0.3 + 0.7 * u
			end
		end
	end

	for model, toy in pairs(toys) do
		if model.Parent then
			local t = now + toy.phase
			local x = toy.drift.X * math.sin(t * 0.07) * math.cos(t * 0.031)
			local z = toy.drift.Y * math.sin(t * 0.053 + 1.3)
			local bob = 0.12 * math.sin(t * 1.4)
			model:PivotTo(toy.rest * CFrame.new(x, bob, z) * CFrame.Angles(0.04 * math.sin(t * 1.1), t * 0.12, 0.04 * math.sin(t * 0.9)))
		end
	end
end

function SkyPoolsClient.start()
	local function added(item: Instance)
		if item:IsA("BasePart") and not table.find(pools, item) then
			table.insert(pools, item)
		end
	end
	for _, item in ipairs(CollectionService:GetTagged("SkyPoolWater")) do
		added(item)
	end
	for _, item in ipairs(CollectionService:GetTagged("SkyFall")) do
		fallAdded(item)
	end
	CollectionService:GetInstanceAddedSignal("SkyFall"):Connect(fallAdded)
	CollectionService:GetInstanceRemovedSignal("SkyFall"):Connect(function(item)
		falls[item :: any] = nil
	end)
	CollectionService:GetInstanceAddedSignal("SkyPoolWater"):Connect(added)
	CollectionService:GetInstanceRemovedSignal("SkyPoolWater"):Connect(function(item)
		local index = table.find(pools, item :: any)
		if index then
			table.remove(pools, index)
		end
	end)

	local function toyAdded(item: Instance)
		local drift = item:GetAttribute("Drift")
		if item:IsA("Model") and typeof(drift) == "Vector2" then
			toys[item] = { rest = item:GetPivot(), drift = drift, phase = math.random() * 100 }
		end
	end
	for _, item in ipairs(CollectionService:GetTagged("SkyPoolToy")) do
		toyAdded(item)
	end
	CollectionService:GetInstanceAddedSignal("SkyPoolToy"):Connect(toyAdded)
	CollectionService:GetInstanceRemovedSignal("SkyPoolToy"):Connect(function(item)
		if item:IsA("Model") then
			toys[item] = nil
		end
	end)

	local function balloonAdded(item: Instance)
		local centre, orbit = item:GetAttribute("Centre"), item:GetAttribute("Orbit")
		local height, phase = item:GetAttribute("Height"), item:GetAttribute("Phase")
		if item:IsA("Model") and typeof(centre) == "Vector3" and typeof(orbit) == "number" and typeof(height) == "number"
			and typeof(phase) == "number" then
			local flame = item:FindFirstChild("Flame", true)
			balloons[item] = { centre = centre, orbit = orbit, height = height, phase = phase,
				flame = if flame and flame:IsA("PointLight") then flame else nil, flareAt = os.clock() + math.random() * 8 }
		end
	end
	for _, item in ipairs(CollectionService:GetTagged("SkyBalloon")) do
		balloonAdded(item)
	end
	CollectionService:GetInstanceAddedSignal("SkyBalloon"):Connect(balloonAdded)
	CollectionService:GetInstanceRemovedSignal("SkyBalloon"):Connect(function(item)
		if item:IsA("Model") then
			balloons[item] = nil
		end
	end)

	for _, item in ipairs(CollectionService:GetTagged("SkyPoolsLevel")) do
		flocksFor(item)
	end
	CollectionService:GetInstanceAddedSignal("SkyPoolsLevel"):Connect(flocksFor)
	CollectionService:GetInstanceRemovedSignal("SkyPoolsLevel"):Connect(function(item)
		local entry = flocks[item]
		if entry then
			for _, flock in ipairs(entry.list) do
				flock.holder:Destroy()
			end
		end
		flocks[item] = nil
	end)

	-- The ride, if the place has the remote: made by Bootstrap with every other one.
	local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents") or ReplicatedStorage:WaitForChild("RemoteEvents", 10)
	local event = remotes and remotes:FindFirstChild("SkyRide")
	if event and event:IsA("RemoteEvent") then
		rideRemote = event
		event.OnClientEvent:Connect(rideStarted)
	end

	RunService.RenderStepped:Connect(step)
end

return SkyPoolsClient
