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
--
-- === The storm by the slide ===
--
-- As you near the slide's mouth the cloud sea round the tower darkens, the light drops a little, and now
-- and then lightning lights the cloud tops below. Under the clouds, on the way down to the final pool, it
-- clears again. Only on your own screen, eased over seconds and written in small steps: a shade, never dark.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

-- The slide's shape and timing, shared with the server. Looked for with a timeout: without it there
-- is no ride drawn here, which the server copes with, so it must not stop the rest of this.
local skyPathModule = ReplicatedStorage:WaitForChild("Shared", 10)
skyPathModule = if skyPathModule then skyPathModule:WaitForChild("SkyPath", 10) else nil
local SkyPath: any = if skyPathModule and skyPathModule:IsA("ModuleScript") then require(skyPathModule) else nil

-- THE POSES (arms up in the sled) and THE CINEMA (the slide played as a scene), both looked for with
-- a timeout: without them the ride is drawn as it always was.
local Poses: any = (function()
	local found = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Poses", 15)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()
local Cinema: any = (function()
	local found = script.Parent and script.Parent:WaitForChild("Cinema", 15)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()

local SkyPoolsClient = {}
SkyPoolsClient.VERSION = "twenty-first pass, 2026-09-30"

local WATER_SOUND = "rbxasset://sounds/impact_water.mp3"
-- THE WATER'S OWN SOUNDS (WaterSounds, the ninety-eighth pass): if the module is not pasted yet, the old splash. ONE
-- local here, the rest inside: a main chunk has room for only so many (Luau's 200).
local WaterSounds: any = (function(): any
	local waterModule = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WaterSounds", 5)
	if waterModule and waterModule:IsA("ModuleScript") then
		return require(waterModule)
	end
	local function oldSplash(s: Sound, _kind: string): boolean
		s.SoundId = "rbxasset://sounds/impact_water.mp3"
		return false
	end
	local splashOnly: any = {}
	splashOnly.dress = oldSplash
	return splashOnly
end)()
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
-- RUDY'S RECORD, going round: each piece turned about the deck's spindle (SkyTurntable, its Axis and Spin).
local turntables: { [BasePart]: { rest: CFrame, axis: Vector3, spin: number } } = {}
local ripples: { Ripple } = {}
local wasIn = false
local lastRipple = 0

-- THE STORM BY THE SLIDE (moveStorm).
local STORM_FROM = 200 -- studs from the slide's mouth, flat, where it begins: the last stretch of any run
local STORM_FULL = 60 -- and where it is all there: the last chunk and the deck
local STORM_EASE = 0.35 -- the share of the way it moves in a second: over seconds, never at once
local STORM_GREY = Color3.fromRGB(122, 130, 150) -- what the nearest clouds are taken toward
local STORM_DARKEST = 0.5 -- the most any cloud is taken toward it
local STORM_NEAR, STORM_REACH = 300, 1400 -- clouds this near the tower darken fully, this far not at all
local STORM_TINT = Color3.fromRGB(226, 232, 246)
local LIGHTNING_EVERY = { 9, 16 } -- seconds between flashes, at the height of it
local LIGHTNING_BRIGHT = 1.3
local stormLevel: Instance? = nil
local storm = 0 -- eased toward how near the slide you are, 0 to 1
local stormAt = os.clock()
local stormWritten = -1
local cloudsWritten = -1
local stormShade: ColorCorrectionEffect? = nil
local cloudBase: { [Instance]: { colour: Color3, weight: number } } = {}
local nextFlash = 0

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

local function play(kind: string, speed: number, volume: number)
	local s = Instance.new("Sound")
	-- The pool's own water: a splash or a dip, one of several takes; the old splash at its old pitch without them.
	if not WaterSounds.dress(s, kind) then
		s.SoundId = WATER_SOUND
		s.PlaybackSpeed = speed
	end
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
	play("splash", 1.1 + math.random() * 0.2, 0.4)
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
	play("dip", 1.5 + math.random() * 0.3, 0.12)
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

-- ===== THE SLIDE, AS A SCENE =====
--
-- On the rider's own screen (Cinema), the long way down is shot like the end of a film:
--   THE PUSH OFF (to 0.1)    over their shoulder, down the slide ahead of them.
--   THE TRACK                above the clouds: alongside them and over them, looking a little ahead,
--                            so the slide is seen running on down into the cloud sea before they reach it.
--   THE PLUNGE               held over the cloud tops where they go in, looking down as the cloud
--                            closes over them, a whoosh and a few speed lines.
--   WHERE IT GOES            while they are in the cloud (five or six seconds, out of sight): under the
--                            cloud sea, wide, the slide coming down out of it and round into the pool it
--                            lands in, drifting slowly in. This is where you are going.
--   OUT OF THE CLOUD         cut a moment BEFORE they come out (the moment is worked out when the ride
--                            starts: scene.marks), under where the slide leaves the cloud, looking up at
--                            it; they burst through in a puff, an impact frame, and the camera turns
--                            after them. It used to wait there from the push off: nine seconds of the
--                            bottom of a slide with nobody on it, which said nothing about where the
--                            ride was going. The camera is never inside a cloud: twice the whole
--                            picture went white.
--   THE FACE                 from ahead of the sled, looking back at them, arms up: fourteen studs
--                            off, not seven, where they were too close to see.
--   THE POOL (from 0.86)     from the water, as they come down into it.
--   THE SKIM                 they do not stop at the water: the sled skips across the pool, three
--                            hops lower each time, spray at every touch, slews round and settles
--                            (SkyPath.skimFrame). Low over the water, alongside.
--   THE LANDING              held a moment on the pool after they tip out, then the camera is theirs.
-- And on everyone's, the rider sits with their arms up the whole way down (Poses.sled).
-- SCORED (Cinema.sound; audio/endings): the rush of the slide under them the whole way down, a whoosh as
-- they go into the cloud, a slap at every skip across the pool, the plunge as they tip out, and over all
-- of it THE PARTY'S SONG (PoolsSong), the one heard through the wall all the way up, in full at last and
-- started so far in that its last chord lands with them in the pool (the pool's chord only stands in
-- for it when it is not there).
local scene = { landedAt = nil :: number?, spec = nil :: any, landing = nil :: Vector3?,
	riders = {} :: { [Player]: { began: number, seconds: number, model: Instance?, joints: { [string]: any }? } },
	stepped = nil :: RBXScriptConnection?, shot = nil :: string?, burst = false, hops = 0, told = false,
	rush = nil :: Sound?, whooshed = false, shotAt = 0, eye = nil :: Vector3?,
	marks = nil :: { plunge: number, out: number, outAt: Vector3, outRun: Vector3 }?,
	song = nil :: Sound?, thinned = {} :: { [BasePart]: boolean }, mist = nil :: BasePart? }
local HOLD = 4.5 -- seconds the pool is held on screen after the splash (and longer if a caption is up)
local PLUNGE_HOLD = 1.1 -- seconds held over the cloud tops as they go in
local BURST_LEAD = 1.3 -- seconds before they come out of the cloud that the camera is waiting under it
local BURST_HOLD = 1.5 -- seconds the camera turns after them once they are out
local BELOW_HOLD = 1.8 -- seconds of the wide shot under the cloud sea (where it goes), after the ride in it
local MIST_LEAST = 1 -- the shortest the ride along in the cloud is held (with less, the wide shot comes straight on)
local MIST_REACH = 150 -- how far round the way through the cloud it is thinned on this screen
local MIST_THIN = 0.72 -- how thin (each cloud's local transparency) while the camera rides in it with them
local SONG_LANDS = 36 -- seconds into PoolsSong that its last chord falls

-- A new shot is a cut: the camera does not pan from one to the next. Out of the cloud the clouds are whole again.
function scene.cutTo(name: string)
	if scene.shot ~= name then
		if scene.shot == "mist" then
			scene.thin(nil)
			scene.drift(nil)
		end
		scene.shot = name
		scene.shotAt = os.clock()
		Cinema.cut()
	end
end

-- WHEN THEY GO INTO THE CLOUD AND WHEN THEY COME OUT, as shares of the ride, worked out once when it starts:
-- the first u where the sled is below each height, so a shot can be cut to a moment before it happens.
function scene.markClouds(current: Ride)
	scene.marks = nil
	local cloudTop = current.sled:GetAttribute("CloudTop")
	local cloudBottom = current.sled:GetAttribute("CloudBottom")
	if typeof(cloudTop) ~= "number" or typeof(cloudBottom) ~= "number" then
		return
	end
	local function below(y: number, from: number): number
		local u = from
		while u < 1 do
			if SkyPath.rideFrame(current.spec, current.distances, u).Position.Y < y then
				return u
			end
			u += 0.002
		end
		return 1
	end
	local plunge = below(cloudTop + 3, 0)
	local out = below(cloudBottom - 8, plunge)
	if out >= 1 then
		return
	end
	local outAt = SkyPath.rideFrame(current.spec, current.distances, out).Position
	local onward = SkyPath.rideFrame(current.spec, current.distances, math.min(1, out + 0.02)).Position
	local run = Vector3.new(onward.X - outAt.X, 0, onward.Z - outAt.Z)
	scene.marks = { plunge = plunge, out = out, outAt = outAt,
		outRun = if run.Magnitude > 0.01 then run.Unit else Vector3.new(0, 0, -1) }
end

-- IN THE CLOUD WITH THEM, on this screen only: the cloud round the way through it thinned, so they are seen in it
-- (white all round, the sky and the pool showing through), never lost in solid white; given back on the next cut.
function scene.thin(through: { Vector3 }?)
	for part in pairs(scene.thinned) do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
	scene.thinned = {}
	if not through then
		return
	end
	local level = stormLevel
	local sea = (level and level:FindFirstChild("CloudSea")) or workspace:FindFirstChild("CloudSea", true)
	if not sea then
		return
	end
	for _, item in ipairs(sea:GetChildren()) do
		if item:IsA("BasePart") and item.Name == "Cloud" then
			local reach = MIST_REACH + item.Size.Magnitude * 0.5
			for _, at in ipairs(through) do
				if (item.Position - at).Magnitude < reach then
					item.LocalTransparencyModifier = MIST_THIN
					scene.thinned[item] = true
					break
				end
			end
		end
	end
end

-- AND STREAMING PAST THEM: wisps let go just ahead, so they ride on through them (the wisps stay where they were
-- let go; the ride does not).
function scene.drift(at: Vector3?, run: Vector3?)
	local host = scene.mist
	if not at then
		if host then
			local wisps = host:FindFirstChildOfClass("ParticleEmitter")
			if wisps then
				wisps.Enabled = false
			end
			game:GetService("Debris"):AddItem(host, 2)
			scene.mist = nil
		end
		return
	end
	if not host then
		local made = Instance.new("Part")
		made.Name = "CloudWisps"
		made.Size = Vector3.new(26, 14, 26)
		made.Anchored = true
		made.CanCollide = false
		made.CanTouch = false
		made.CanQuery = false
		made.Transparency = 1
		local wisps = Instance.new("ParticleEmitter")
		wisps.Name = "Wisps"
		wisps.Texture = "rbxasset://textures/particles/smoke_main.dds"
		wisps.Color = ColorSequence.new(Color3.fromRGB(236, 241, 248))
		wisps.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 12) })
		wisps.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.66),
			NumberSequenceKeypoint.new(1, 1) })
		wisps.Lifetime = NumberRange.new(0.8, 1.4)
		wisps.Speed = NumberRange.new(0, 1.5)
		wisps.Rate = 45
		wisps.Shape = Enum.ParticleEmitterShape.Box
		wisps.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		wisps.LightInfluence = 0.6
		wisps.Parent = made
		made.Parent = workspace
		scene.mist = made
		host = made
	end
	if host then
		host.CFrame = CFrame.new(at + (run or Vector3.zero) * 14)
	end
end

function scene.shoot(current: Ride, u: number)
	if not (Cinema and Cinema.active()) then
		return
	end
	local here = current.seat.Position
	local ahead = SkyPath.rideFrame(current.spec, current.distances, math.min(1, u + 0.02)).Position
	local run = ahead - here
	run = if run.Magnitude > 0.01 then run.Unit else Vector3.new(0, 0, -1)
	local flat = Vector3.new(run.X, 0, run.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local out = Vector3.new(here.X - current.spec.centre.X, 0, here.Z - current.spec.centre.Z)
	out = if out.Magnitude > 0.01 then out.Unit else Vector3.xAxis
	local character = Players.LocalPlayer.Character
	local ignore = if character then { character, current.sled } else { current.sled }
	local marks = scene.marks
	local cloudBottom = current.sled:GetAttribute("CloudBottom")
	-- Where the slide comes out of the cloud, and the eye under it that waits for them there.
	local function waitUnder()
		if scene.shot ~= "burst" and marks then
			scene.cutTo("burst")
			local away = Vector3.new(marks.outAt.X - current.spec.centre.X, 0, marks.outAt.Z - current.spec.centre.Z)
			away = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis
			scene.eye = Cinema.clear(marks.outAt + marks.outRun * 30 + away * 22 + Vector3.new(0, -24, 0), marks.outAt, ignore)
			Cinema.speedLines(0)
		end
	end
	if u < 0.1 then
		scene.cutTo("push")
		local eye = Cinema.clear(here - flat * 10 + Vector3.new(0, 5.5, 0), here, ignore)
		Cinema.point(CFrame.lookAt(eye, SkyPath.rideFrame(current.spec, current.distances, math.min(1, u + 0.12)).Position), 64)
	elseif marks and u < marks.plunge then
		-- THE TRACK: alongside and over them, looking a little ahead, so the slide is seen running on down
		-- into the cloud sea before they get there: where they are going, not only where they are.
		scene.cutTo("track")
		local far = SkyPath.rideFrame(current.spec, current.distances, math.min(1, marks.plunge + 0.03)).Position
		local eye = here + out * 22 + Vector3.new(0, 10, 0) - flat * 12
		Cinema.point(CFrame.lookAt(eye, here:Lerp(far, 0.3) + Vector3.new(0, 1, 0)), 56)
	elseif marks and u < marks.out then
		local left = (marks.out - u) * current.seconds
		local since = (u - marks.plunge) * current.seconds
		if since < PLUNGE_HOLD and left > BURST_LEAD then
			-- THE PLUNGE: held over the cloud tops where they go in, looking down as it closes over them.
			if scene.shot ~= "plunge" then
				scene.cutTo("plunge")
				scene.eye = Cinema.clear(here - flat * 14 + out * 9 + Vector3.new(0, 15, 0), here, ignore)
				Cinema.speedLines(0.45)
				if not scene.whooshed then
					scene.whooshed = true
					Cinema.sound("CloudWhoosh", 0.8)
				end
			end
			local held = os.clock() - scene.shotAt
			Cinema.point(CFrame.lookAt(scene.eye :: Vector3, here), 60 - math.min(held, PLUNGE_HOLD) * 6)
		elseif left > BURST_LEAD + BELOW_HOLD and (scene.shot == "mist" or left > BURST_LEAD + BELOW_HOLD + MIST_LEAST) then
			-- RIDING THROUGH IT WITH THEM: close behind and over them, the cloud thinned round the way through it and
			-- wisps streaming past, so the ride in the cloud is theirs (it was an empty sky for four seconds: your
			-- test of 2026-10-22, "I wanna see the player more often").
			if scene.shot ~= "mist" then
				scene.cutTo("mist")
				scene.thin({ here, here:Lerp(marks.outAt, 0.5), marks.outAt })
				Cinema.speedLines(0.6)
			end
			scene.drift(here, run)
			local eye = Cinema.clear(here - flat * 8 + out * 2.5 + Vector3.new(0, 3.5, 0), here, ignore)
			Cinema.point(CFrame.lookAt(eye, here + run * 4 + Vector3.new(0, 1.2, 0)), 66)
		elseif left > BURST_LEAD and (scene.shot == "below" or left > BURST_LEAD + 1) then
			-- WHERE IT GOES: they are in the cloud, out of sight, so this is the way down instead: under the cloud
			-- sea, wide, the slide coming down out of it and round into the pool it lands in, drifting slowly in.
			-- (Never for a moment only: with too little of the cloud left, the camera waits under it instead.)
			if scene.shot ~= "below" then
				scene.cutTo("below")
				Cinema.speedLines(0)
			end
			local held = os.clock() - scene.shotAt
			local landing = SkyPath.point(current.spec, 1)
			local mid = marks.outAt:Lerp(landing, 0.5)
			local away = Vector3.new(mid.X - current.spec.centre.X, 0, mid.Z - current.spec.centre.Z)
			away = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis
			local drift = math.clamp(held / 5, 0, 1)
			local eye = mid + away * (150 - 28 * drift) + Vector3.new(0, 6 + 6 * drift, 0)
			if typeof(cloudBottom) == "number" then
				eye = Vector3.new(eye.X, math.min(eye.Y, cloudBottom - 16), eye.Z)
			end
			Cinema.point(CFrame.lookAt(eye, mid:Lerp(marks.outAt, 0.38)), 66, true)
		else
			-- OUT OF THE CLOUD, a moment before: under where the slide leaves it, looking up at it.
			waitUnder()
			Cinema.point(CFrame.lookAt(scene.eye :: Vector3, marks.outAt + Vector3.new(0, 5, 0)), 60, true)
		end
	elseif marks and (u - marks.out) * current.seconds < BURST_HOLD then
		-- THROUGH: a puff where they came out, an impact frame, and the camera turning after them.
		waitUnder()
		if not scene.burst then
			scene.burst = true
			scene.puff(here)
			Cinema.impact(0.7)
			Cinema.speedLines(0.4)
		end
		Cinema.point(CFrame.lookAt(scene.eye :: Vector3, here + Vector3.new(0, 1, 0)), 60, true)
	elseif u < 0.86 then
		-- THE FACE: ahead of them looking back, far enough off to see all of them, the speed still on.
		if scene.shot ~= "face" then
			scene.cutTo("face")
			Cinema.speedLines(0.3)
		end
		local eye = Cinema.clear(here + run * 14 + Vector3.new(0, 4.5, 0), here, ignore)
		Cinema.point(CFrame.lookAt(eye, here + Vector3.new(0, 1.2, 0)), 58)
	else
		if scene.shot ~= "pool" then
			Cinema.speedLines(0)
		end
		scene.cutTo("pool")
		local landing = SkyPath.point(current.spec, 1)
		local last = SkyPath.point(current.spec, 0.97)
		local away = Vector3.new(landing.X - last.X, 0, landing.Z - last.Z)
		away = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis
		local side = Vector3.new(-away.Z, 0, away.X)
		Cinema.point(CFrame.lookAt(landing + away * 20 + side * 10 + Vector3.new(0, 2.5, 0), here), 58)
	end
end

-- THE SKIM, `s` seconds in: low over the water, alongside, the sled skipping past.
function scene.skimShot(current: Ride, s: number)
	if not (Cinema and Cinema.active()) then
		return
	end
	local at = current.seat.Position
	local landing = SkyPath.point(current.spec, 1)
	local last = SkyPath.point(current.spec, 0.97)
	local dir = Vector3.new(landing.X - last.X, 0, landing.Z - last.Z)
	dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.xAxis
	local side = Vector3.new(-dir.Z, 0, dir.X)
	scene.cutTo("skim")
	-- Keeping pace a little behind at first, and letting it go on past as it slows.
	local eye = Vector3.new(at.X, landing.Y + 2.2, at.Z) + side * 13 - dir * (4 - s * 2.2)
	Cinema.point(CFrame.lookAt(eye, at + Vector3.new(0, 0.5, 0)), 56)
end

-- A PUFF OF CLOUD where they came out of it, on this screen.
function scene.puff(at: Vector3)
	local host = Instance.new("Part")
	host.Name = "CloudPuff"
	host.Size = Vector3.new(1, 1, 1)
	host.CFrame = CFrame.new(at + Vector3.new(0, 4, 0))
	host.Anchored = true
	host.CanCollide = false
	host.CanTouch = false
	host.CanQuery = false
	host.Transparency = 1
	host.Parent = workspace
	local puff = Instance.new("ParticleEmitter")
	puff.Texture = "rbxasset://textures/particles/smoke_main.dds"
	puff.Color = ColorSequence.new(Color3.fromRGB(240, 244, 250))
	puff.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) })
	puff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	puff.Lifetime = NumberRange.new(1.2, 2.2)
	puff.Speed = NumberRange.new(6, 14)
	puff.SpreadAngle = Vector2.new(180, 180)
	puff.Drag = 2
	puff.Rate = 0
	puff.Parent = host
	puff:Emit(36)
	task.delay(3, function()
		host:Destroy()
	end)
end

-- THE POSE, for everyone riding, after the animations every frame.
function scene.poseRiders()
	local now = workspace:GetServerTimeNow()
	for player, r in pairs(scene.riders) do
		local character = player.Character
		local t = now - r.began
		if not character or not player.Parent or t >= r.seconds then
			if r.joints then
				for _, joint in pairs(r.joints) do
					Poses.drive(joint, CFrame.identity)
				end
			end
			scene.riders[player] = nil
		elseif t >= 0 then
			if r.model ~= character then
				r.model = character
				r.joints = Poses.joints(character)
			end
			local joints = r.joints
			if joints then
				local r6 = Poses.isR6(joints)
				local w = Poses.weight(t, r.seconds)
				for name, joint in pairs(joints) do
					local turn = Poses.sled(name, t, w, r6)
					if turn then
						Poses.drive(joint, turn)
					end
				end
			end
		end
	end
	local hook = scene.stepped
	if hook and next(scene.riders) == nil then
		hook:Disconnect()
		scene.stepped = nil
	end
end

function scene.posed(player: any, began: any, seconds: any)
	if not Poses or typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(began) ~= "number"
		or typeof(seconds) ~= "number" then
		return
	end
	scene.riders[player] = { began = began, seconds = seconds }
	if not scene.stepped then
		scene.stepped = RunService.Stepped:Connect(function()
			pcall(scene.poseRiders)
		end)
	end
end

-- ===== THE ARCHES ON THE WAY DOWN (the hundred-and-eighth pass) =====
--
-- From your notes: the arches "glowing or making these cool sparkling effects and kind of like shake my camera a
-- little" as you slide. On the rider's own screen only: each hoop over the slide (SlideArch, tagged by the server)
-- begins to glow as you come down toward it, a small real light in its crown; passing under it, it flares and fades
-- to an afterglow, its hoop flashes pale, sparkles in its own colours burst off it, the air of it goes past
-- (ArchPass) and the picture gives a small shake. All of it fades away at the bottom.
local ARCH_LIGHT_FROM = 45 -- studs off, an arch begins to glow
local ARCH_PASS = 7 -- studs from its middle: as good as under it
local ARCH_GLOW = 0.9 -- its light as you reach it
local ARCH_FLARE = 1.6 -- and the moment you pass under it (small steps: never brighter than this)
local ARCH_AFTER = 0.35 -- what it keeps, behind you
type Arch = { centre: Vector3, light: PointLight, parts: { BasePart }, colours: { Color3 }, sparks: { ParticleEmitter },
	passed: boolean }
local arches: { Arch } = {}

-- Everything the arches had on this screen, taken off and their colours given back.
local function archesOff()
	for _, a in ipairs(arches) do
		a.light:Destroy()
		for _, emitter in ipairs(a.sparks) do
			emitter:Destroy()
		end
		for k, part in ipairs(a.parts) do
			if part.Parent then
				part.Color = a.colours[k]
			end
		end
	end
	table.clear(arches)
end

-- At the bottom: their lights faded out over a couple of seconds, and then all of it off.
local function archesFade()
	for _, a in ipairs(arches) do
		TweenService:Create(a.light, TweenInfo.new(2, Enum.EasingStyle.Sine), { Brightness = 0 }):Play()
	end
	task.delay(2.2, function()
		if not ride then
			archesOff()
		end
	end)
end

-- As a ride starts: a light (dark) in every arch's crown, and a burst of sparkles ready in every piece of its hoop.
local function archesOn()
	archesOff()
	for _, model in ipairs(CollectionService:GetTagged("SlideArch")) do
		local centre = model:GetAttribute("Centre")
		if model:IsA("Model") and typeof(centre) == "Vector3" then
			local parts, colours, sparks = {}, {}, {}
			local crown: BasePart? = nil
			for _, part in ipairs(model:GetChildren()) do
				if part:IsA("BasePart") then
					table.insert(parts, part)
					table.insert(colours, part.Color)
					if not crown or part.Position.Y > (crown :: BasePart).Position.Y then
						crown = part
					end
					local emitter = Instance.new("ParticleEmitter")
					emitter.Name = "ArchSparkle"
					emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
					emitter.Rate = 0
					emitter.Lifetime = NumberRange.new(0.5, 1.1)
					emitter.Speed = NumberRange.new(4, 10)
					emitter.SpreadAngle = Vector2.new(180, 180)
					emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
					emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0),
						NumberSequenceKeypoint.new(0.7, 0.3), NumberSequenceKeypoint.new(1, 1) })
					emitter.Color = ColorSequence.new(Color3.new(1, 1, 1), part.Color)
					emitter.LightEmission = 1
					emitter.Drag = 3
					emitter.Acceleration = Vector3.new(0, -5, 0)
					emitter.Parent = part
					table.insert(sparks, emitter)
				end
			end
			if crown then
				local light = Instance.new("PointLight")
				light.Name = "ArchGlow"
				light.Brightness = 0
				light.Range = 12
				light.Color = colours[1]:Lerp(Color3.new(1, 1, 1), 0.45)
				light.Shadows = false
				light.Parent = crown
				table.insert(arches, { centre = centre, light = light, parts = parts, colours = colours, sparks = sparks,
					passed = false })
			end
		end
	end
end

-- Passing under one: the flare, the flash of its hoop, its sparkles, its air, and a small shake.
local function archPassed(a: Arch)
	a.passed = true
	a.light.Brightness = ARCH_FLARE
	TweenService:Create(a.light, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = ARCH_AFTER }):Play()
	for k, part in ipairs(a.parts) do
		part.Color = a.colours[k]:Lerp(Color3.new(1, 1, 1), 0.6)
		TweenService:Create(part, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Color = a.colours[k] }):Play()
	end
	for _, emitter in ipairs(a.sparks) do
		emitter:Emit(4)
	end
	if Cinema and Cinema.active() then
		Cinema.sound("ArchPass", 0.45, { pitch = 0.97 + math.random() * 0.06, keep = true })
		Cinema.shake(0.2)
	end
end

-- Each frame of a ride: the arches ahead glowing up as you come, the one you are under passed.
local function moveArches(at: Vector3)
	for _, a in ipairs(arches) do
		if not a.passed then
			local d = (a.centre - at).Magnitude
			if d < ARCH_PASS then
				archPassed(a)
			else
				local near = math.clamp(1 - (d - ARCH_PASS) / (ARCH_LIGHT_FROM - ARCH_PASS), 0, 1)
				a.light.Brightness = ARCH_GLOW * near * near
			end
		end
	end
end

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
	drop.FontFace = Style.FONT.heading
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
	caption.FontFace = Style.FONT.body
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
	-- THE SCENE'S BARS instead, where there is a scene: no bands, no counter on a film.
	if Cinema then
		return
	end
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
	local gui = rideGui
	if not (flash and gui) then
		return
	end
	-- Shown on its own when there is a scene (the bands and the counter stay off then).
	gui.Enabled = true
	if Cinema then
		task.delay(0.7, function()
			if gui.Parent and not ride then
				gui.Enabled = false
			end
		end)
	end
	flash.BackgroundTransparency = 0.45
	TweenService:Create(flash, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }):Play()
end

local function rideStarted(sled: Instance)
	if not (SkyPath and typeof(sled) == "Instance" and sled:IsA("Model")) then
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
	pcall(archesOn)
	scene.landedAt = nil
	scene.shot = nil
	scene.burst = false
	scene.hops = 0
	scene.told = false
	scene.whooshed = false
	scene.eye = nil
	pcall(scene.markClouds, ride :: Ride)
	if Cinema then
		Cinema.begin()
		Cinema.caption("The Long Way Down", "Everyone takes it in the end.", 7)
		scene.rush = Cinema.sound("SlideRush", 0.55, { looped = true, fadeIn = 1.2 })
		-- THE PARTY'S SONG, in full at last: started so far in that its last chord falls as they land in the pool.
		scene.song = Cinema.sound("PoolsSong", 0.5, { keep = true, fadeIn = 1.5 })
		local song = scene.song
		if song then
			local landsIn = seconds + SkyPath.SKIM_SECONDS - (workspace:GetServerTimeNow() - startAt)
			song.TimePosition = math.max(0, SONG_LANDS - landsIn)
		end
	end
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
		archesOff()
		showRide(false)
		scene.thin(nil)
		scene.drift(nil)
		if Cinema then
			Cinema.fade(scene.song, 1.5)
		end
		scene.song = nil
		if Cinema and Cinema.active() then
			Cinema.finish()
		end
		return
	end
	local elapsed = serverNow - current.startAt
	local u = elapsed / current.seconds
	if u >= 1 then
		local s = elapsed - current.seconds
		if s < SkyPath.SKIM_SECONDS then
			-- THE SKIM: across the pool, spray at every touch.
			current.seat.CFrame = SkyPath.skimFrame(current.spec, s)
			current.seat.AssemblyLinearVelocity = Vector3.zero
			current.seat.AssemblyAngularVelocity = Vector3.zero
			local touched = 0
			for _, h in ipairs(SkyPath.HOPS) do
				if s >= h[1] then
					touched += 1
				end
			end
			if touched > scene.hops then
				scene.hops = touched
				splash(Vector3.new(current.seat.Position.X, SkyPath.point(current.spec, 1).Y, current.seat.Position.Z))
				if Cinema and Cinema.active() then
					Cinema.shake(0.6)
					-- Each skip smaller than the last, and a little higher.
					Cinema.sound("SkimSlap", 0.95 - touched * 0.18, { pitch = 1 + touched * 0.07, keep = true })
					if touched == 1 then
						Cinema.fade(scene.rush, 0.5)
					end
				end
			end
			pcall(scene.skimShot, current, s)
			return
		end
		ride = nil
		splashFlash()
		archesFade()
		showRide(false)
		if Cinema and Cinema.active() then
			Cinema.sound("PoolPlunge", 0.9, { keep = true })
		end
		-- THE POOL, held a moment after the splash, then the camera is theirs.
		scene.landedAt = os.clock()
		scene.spec = current.spec
		scene.landing = SkyPath.skimEnd(current.spec)
		return
	end
	-- How far there is left to fall, which is the one number worth showing on a slide.
	local left = math.max(0, current.seat.Position.Y - current.spec.y1)
	if rideParts.drop then
		rideParts.drop.Text = ("%d studs"):format(left)
	end
	current.seat.CFrame = SkyPath.rideFrame(current.spec, current.distances, u)
	-- It is unanchored while this client has it, so gravity would pull at it between frames.
	current.seat.AssemblyLinearVelocity = Vector3.zero
	current.seat.AssemblyAngularVelocity = Vector3.zero
	moveArches(current.seat.Position)
	pcall(scene.shoot, current, u)
end

-- After the splash: the pool from its far side, the tower going up out of it, then back to the player.
local function holdLanding()
	local landedAt = scene.landedAt
	if not landedAt or not (Cinema and Cinema.active()) then
		return
	end
	if os.clock() - landedAt > HOLD then
		scene.landedAt = nil
		Cinema.finish()
		return
	end
	local spec = scene.spec
	local landing = scene.landing or SkyPath.point(spec, 1)
	local last = SkyPath.point(spec, 0.97)
	local away = Vector3.new(landing.X - SkyPath.point(spec, 1).X, 0, landing.Z - SkyPath.point(spec, 1).Z)
	if away.Magnitude < 0.01 then
		away = Vector3.new(landing.X - last.X, 0, landing.Z - last.Z)
	end
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis
	if not scene.told then
		scene.told = true
		Cinema.caption("The Sky Pools", "Everybody who came up for the party is still up there. You are the only one who came down.", 8)
		-- The song's own last chord is ringing already; the pool's chord only when there is no song.
		if not (scene.song and scene.song.Parent) then
			Cinema.sound("PoolsChord", 0.7, { keep = true, fadeIn = 1, alt = "EndChord", altPitch = 1.19 })
		end
		scene.song = nil
		Cinema.done()
	end
	-- CLOSE, low over the water and a little to one side, easing in: you in the pool, big enough to see (it was
	-- thirty-two studs off and you were a speck in it: your test of 2026-10-22), the tower going up behind you.
	local side = Vector3.new(-away.Z, 0, away.X)
	local k = math.clamp((os.clock() - landedAt) / HOLD, 0, 1)
	Cinema.point(CFrame.lookAt(landing + away * (14 - 4 * k) + side * 4 + Vector3.new(0, 2.4, 0),
		landing + Vector3.new(0, 0.6, 0)), 60)
end

-- ===== THE STORM BY THE SLIDE =====

local function ensureStormShade(): ColorCorrectionEffect
	local existing = stormShade
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("ColorCorrectionEffect")
	made.Name = "SkyStorm"
	made.Parent = Lighting
	stormShade = made
	return made
end

-- The cloud sea, taken toward storm grey by u (0 to 1): the clouds round the tower most, the far ones not at
-- all. Each cloud's own colour is kept the first time it is seen, so it always eases back to it.
local function paintClouds(u: number)
	local level = stormLevel
	local sea = level and level:FindFirstChild("CloudSea")
	local centre = level and level:GetAttribute("SlideCentre")
	if not sea or typeof(centre) ~= "Vector3" then
		return
	end
	for _, item in ipairs(sea:GetDescendants()) do
		local base = cloudBase[item]
		if not base then
			local at: Vector3? = nil
			local colour: Color3? = nil
			if item:IsA("BasePart") and item.Name == "Cloud" then
				at, colour = item.Position, item.Color
			elseif item:IsA("ParticleEmitter") and item.Parent and item.Parent:IsA("BasePart") then
				at, colour = (item.Parent :: BasePart).Position, item.Color.Keypoints[1].Value
			end
			if at and colour then
				local away = Vector3.new(at.X - centre.X, 0, at.Z - centre.Z).Magnitude
				base = { colour = colour, weight = math.clamp((STORM_REACH - away) / (STORM_REACH - STORM_NEAR), 0, 1) }
				cloudBase[item] = base
			end
		end
		if base and base.weight > 0 then
			local shade = base.colour:Lerp(STORM_GREY, STORM_DARKEST * base.weight * u)
			if item:IsA("BasePart") then
				item.Color = shade
			elseif item:IsA("ParticleEmitter") then
				item.Color = ColorSequence.new(shade)
			end
		end
	end
end

-- Written only when it has moved: the shade to a hundredth, the clouds (hundreds of them) to a twentieth.
local function applyStorm()
	local key = math.floor(storm * 100 + 0.5)
	if key == stormWritten then
		return
	end
	stormWritten = key
	local s = key / 100
	local cc = ensureStormShade()
	cc.Brightness = -0.06 * s
	cc.Saturation = -0.12 * s
	cc.Contrast = 0.03 * s
	cc.TintColor = Color3.new(1, 1, 1):Lerp(STORM_TINT, s)
	local cloudKey = math.floor(s * 20 + 0.5)
	if cloudKey ~= cloudsWritten then
		cloudsWritten = cloudKey
		paintClouds(cloudKey / 20)
	end
end

-- LIGHTNING in the cloud tops near the tower: a real light just over them, twice, briefly, soft. Nothing to see
-- but the clouds it lights.
local function flashLightning(now: number)
	local level = stormLevel
	if storm < 0.6 or now < nextFlash or not level then
		return
	end
	nextFlash = now + math.random(LIGHTNING_EVERY[1], LIGHTNING_EVERY[2])
	local centre = level:GetAttribute("SlideCentre")
	local top = level:GetAttribute("CloudTop")
	if typeof(centre) ~= "Vector3" or typeof(top) ~= "number" then
		return
	end
	local angle = math.random() * math.pi * 2
	local reach = 120 + math.random() * 200
	local spot = Instance.new("Attachment")
	spot.Name = "Lightning"
	spot.Position = Vector3.new(centre.X + math.cos(angle) * reach, top + 4, centre.Z + math.sin(angle) * reach)
	spot.Parent = workspace.Terrain
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(220, 228, 255)
	light.Range = 90
	light.Shadows = false
	light.Brightness = 0
	light.Parent = spot
	local strength = storm
	task.spawn(function()
		light.Brightness = LIGHTNING_BRIGHT * strength
		task.wait(0.07)
		light.Brightness = 0
		task.wait(0.12)
		light.Brightness = LIGHTNING_BRIGHT * 0.6 * strength
		task.wait(0.1)
		spot:Destroy()
	end)
end

-- Out of the level, or the level gone: no storm at all, at once (the lobby is never left shaded), and the clouds
-- given back their own colours while they are still known (a late join would otherwise keep them grey for good).
local function stormGone()
	if next(cloudBase) ~= nil then
		paintClouds(0)
	end
	storm = 0
	stormWritten, cloudsWritten = -1, -1
	cloudBase = {}
	if stormShade then
		stormShade:Destroy()
		stormShade = nil
	end
end

local function moveStorm(now: number)
	local dt = math.min(now - stormAt, 0.25)
	stormAt = now
	local level = stormLevel
	if not (level and level.Parent and Players.LocalPlayer:GetAttribute("InLevel") == "skyPools") then
		if stormShade then
			stormGone()
		end
		return
	end
	local target = 0
	local mouth = level:GetAttribute("SlideMouth")
	local bottom = level:GetAttribute("CloudBottom")
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if typeof(mouth) == "CFrame" and root and root:IsA("BasePart") then
		local flat = Vector3.new(root.Position.X - mouth.Position.X, 0, root.Position.Z - mouth.Position.Z).Magnitude
		target = math.clamp((STORM_FROM - flat) / (STORM_FROM - STORM_FULL), 0, 1)
		-- UNDER THE CLOUDS it clears: the end of the ride comes out into calm air over the pool.
		if typeof(bottom) == "number" then
			target *= math.clamp((root.Position.Y - (bottom - 30)) / 30, 0, 1)
		end
	end
	storm += (target - storm) * math.min(1, STORM_EASE * dt)
	applyStorm()
	flashLightning(now)
end

local function stormFor(level: Instance)
	stormGone()
	stormLevel = level
end

local function step()
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	moveSky(serverNow, now)
	moveSled(serverNow)
	holdLanding()
	moveFalls(now)
	moveStorm(now)
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

	for part, deck in pairs(turntables) do
		if part.Parent then
			local about = CFrame.new(deck.axis)
			part.CFrame = about * CFrame.Angles(0, -now * deck.spin, 0) * about:Inverse() * deck.rest
		else
			turntables[part] = nil
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
	-- Taken to the lobby mid-slide: the slide is over here, its arches, its cloud and its song put away.
	if Cinema and Cinema.onLeave then
		Cinema.onLeave(function()
			ride = nil
			scene.landedAt = nil
			scene.thin(nil)
			scene.drift(nil)
			archesOff()
			showRide(false)
			Cinema.fade(scene.song, 1)
			scene.song = nil
		end)
	end
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
	local function deckAdded(item: Instance)
		local axis, spin = item:GetAttribute("Axis"), item:GetAttribute("Spin")
		if item:IsA("BasePart") and typeof(axis) == "Vector3" and typeof(spin) == "number" then
			turntables[item] = { rest = item.CFrame, axis = axis, spin = spin }
		end
	end
	for _, item in ipairs(CollectionService:GetTagged("SkyTurntable")) do
		deckAdded(item)
	end
	CollectionService:GetInstanceAddedSignal("SkyTurntable"):Connect(deckAdded)
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
		stormFor(item)
	end
	CollectionService:GetInstanceAddedSignal("SkyPoolsLevel"):Connect(flocksFor)
	CollectionService:GetInstanceAddedSignal("SkyPoolsLevel"):Connect(stormFor)
	CollectionService:GetInstanceRemovedSignal("SkyPoolsLevel"):Connect(function(item)
		if stormLevel == item then
			stormGone()
			stormLevel = nil
		end
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
		-- The ride is the rider's alone; the arms-up pose is anyone's.
		event.OnClientEvent:Connect(function(first: any, a: any, b: any, c: any)
			if first == "pose" then
				scene.posed(a, b, c)
			else
				rideStarted(first)
			end
		end)
	end

	RunService.RenderStepped:Connect(step)
end

SkyPoolsClient.STAMP = "6361e442"
return SkyPoolsClient
