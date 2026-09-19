--!strict
-- StarterPlayerScripts/Services/SunkenCityClient.lua
-- The Sunken City's moving parts, on each client: the thing under the route and its surfacing, the
-- whirlpool, the buoys, the fish, the stopped clock, the face in the mirror, and what the water and
-- the sound do when the thing is near.
--
-- === Why the client ===
--
-- SunkenCityService builds the city once on the server and puts the thing's whole brief on the sea
-- model as attributes. Where it is and when it surfaces are worked out from that brief and the
-- server clock by ReplicatedStorage.Shared.SunkenPath, the same module the server uses to decide
-- who it takes, so everyone sees it in the same place and it takes nobody it was not seen to reach.
-- Nothing of it is replicated: moving thirty parts every frame from the server would be a stream of
-- updates to every player, forever, for something nobody can touch.
--
-- The whirlpool's rings, the buoys and the clock are the server's parts, moved locally, which is the
-- arrangement SeaService already uses for City Shore's sea.
--
-- === The thing, and the rules it follows (ROADMAP section 6) ===
--
-- It never chases. It circles the boulevard under the route the other way to the runners and swings
-- out round the harbour. When it comes near, the sound goes first: the lapping and the wind drop away
-- and a low rumble comes up, and then the water darkens.
--
-- Every so often it SURFACES (see SunkenPath): bubbles and a dark patch on the water over the spot
-- for five seconds, then its back heaves up under the surface, its fins cut through it, and a surge
-- of spray goes up over the route. A Hardcore player standing there is taken back to the start by
-- the server, and gets one deep thud and a darker moment here; in Chill it only watches.
--
-- === The face in the mirror (ROADMAP section 6: rare, once a server or less, never in Chill) ===
--
-- The server decides, and says so by stamping MirrorFace on your player. The face is built here, on
-- the mirror, invisible, and only this client ever shows it: the bathroom light stutters, the face is
-- there for half a second with a drone under it, the light goes out, and when it comes back the
-- mirror is empty.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SunkenPath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SunkenPath"))

local SunkenCityClient = {}

local SEGMENTS = SunkenPath.SEGMENTS
local SPACING = SunkenPath.SPACING
local NEAR, FAR = 35, 95 -- fully "under you" within NEAR, not at all past FAR (horizontal studs)
local BODY = Color3.fromRGB(28, 40, 48)
local EYE = Color3.fromRGB(190, 206, 170)
local DARK_WATER = Color3.fromRGB(16, 34, 38)
local WATER_SOUND = "rbxasset://sounds/impact_water.mp3"
local THUD_SOUND = "rbxasset://sounds/action_jump_land.mp3"

type Extra = { part: BasePart, segment: number, offset: CFrame }
type Surfacing = { index: number, spot: Vector3, holder: Folder, patch: BasePart, bubbles: ParticleEmitter,
	surged: boolean, broke: boolean }

local brief: SunkenPath.Brief? = nil
local seaModel: Instance? = nil
local folder: Folder? = nil
local segments: { BasePart } = {}
local extras: { Extra } = {}
local nearness = 0 -- eased toward how near the thing is, 0 to 1
local inside = 0 -- eased toward whether you are inside the aquarium, 0 to 1
local shade: ColorCorrectionEffect? = nil
local rumble: Sound? = nil
local waterBase: { [BasePart]: { colour: Color3, transparency: number } } = {}
local surfacing: Surfacing? = nil

local rings: { [Model]: { centre: Vector3, spin: number, rest: CFrame } } = {}
local buoys: { [Model]: { rest: CFrame, phase: number } } = {}
local hands: { [BasePart]: { rest: CFrame, pivot: CFrame } } = {}
local shoals: { [BasePart]: { fish: { Model }, radius: number, speed: number } } = {}
local zones: { BasePart } = {}
local mirrors: { [BasePart]: { face: { BasePart } } } = {}
local mirrorLamps: { BasePart } = {}
local nextTwitch = 0

local function localPart(parent: Instance, name: string, size: Vector3, colour: Color3, round: boolean): Part
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
	if round then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	part.Parent = parent
	return part
end

local function oneShot(speed: number, volume: number, id: string?)
	local s = Instance.new("Sound")
	s.SoundId = id or WATER_SOUND
	s.PlaybackSpeed = speed
	s.Volume = volume
	s.Parent = SoundService
	s:Play()
	task.delay(4, function()
		s:Destroy()
	end)
end

-- ===== THE THING =====

-- How thick it is along its length: a blunt head, widest a little behind it, a long taper to the tail.
local function girthAt(b: SunkenPath.Brief, index: number): number
	local x = index / (SEGMENTS - 1)
	if x < 0.15 then
		return b.girth * (0.75 + x / 0.15 * 0.25)
	end
	return b.girth * (1 - 0.75 * ((x - 0.15) / 0.85) ^ 1.3)
end

local function buildThing(b: SunkenPath.Brief)
	local holder = Instance.new("Folder")
	holder.Name = "SunkenThing"
	holder.Parent = workspace
	folder = holder
	segments = {}
	extras = {}
	for index = 0, SEGMENTS - 1 do
		local g = girthAt(b, index)
		table.insert(segments, localPart(holder, "Body", Vector3.new(g * 1.8, g * 1.5, SPACING * 1.6), BODY, true))
	end
	-- Eyes, pale and a little forward on the head; a ridge of fins down the back; a fluke at the tail.
	local head = girthAt(b, 0)
	for _, side in ipairs({ -1, 1 }) do
		local eye = localPart(holder, "Eye", Vector3.new(1.4, 1.1, 1.8), EYE, true)
		eye.Transparency = 0.2
		table.insert(extras, { part = eye, segment = 1, offset = CFrame.new(side * head * 0.72, head * 0.3, -SPACING * 0.45) })
	end
	for index = 2, 12, 2 do
		local g = girthAt(b, index)
		local fin = localPart(holder, "Fin", Vector3.new(0.5, g * 0.9, 4), BODY, false)
		table.insert(extras, { part = fin, segment = index + 1, offset = CFrame.new(0, g * 0.85, 0) * CFrame.Angles(math.rad(-30), 0, 0) })
	end
	local fluke = localPart(holder, "Fluke", Vector3.new(12, 0.6, 5), BODY, true)
	table.insert(extras, { part = fluke, segment = SEGMENTS, offset = CFrame.new(0, 0, SPACING * 0.8) })
end

local function clearThing()
	if folder then
		folder:Destroy()
	end
	folder = nil
	segments = {}
	extras = {}
end

-- Moves the body, and returns the horizontal distance from `from` to the nearest part of it.
local function moveThing(b: SunkenPath.Brief, t: number, from: Vector3?): number
	local points = {}
	for index = 0, SEGMENTS do
		points[index] = SunkenPath.point(b, t, (index - 1) * SPACING)
	end
	local nearest = math.huge
	for index = 1, SEGMENTS do
		local here, ahead = points[index], points[index - 1]
		segments[index].CFrame = CFrame.lookAt(here, ahead)
		if from and index % 3 == 1 then
			nearest = math.min(nearest, Vector3.new(here.X - from.X, 0, here.Z - from.Z).Magnitude)
		end
	end
	for _, extra in ipairs(extras) do
		extra.part.CFrame = segments[extra.segment].CFrame * extra.offset
	end
	return nearest
end

-- ===== THE SURFACING, SEEN =====

local function endSurfacing()
	local s = surfacing
	if s then
		s.holder:Destroy()
	end
	surfacing = nil
end

-- A ring of spray and a column of it, spreading from the spot: the surge over the route.
local function surge(at: Vector3)
	local host = localPart(workspace, "Surge", Vector3.new(1, 1, 1), BODY, false)
	host.Transparency = 1
	host.CFrame = CFrame.new(at)
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(214, 232, 226))
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0.6) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(1.2, 2.2)
	spray.Speed = NumberRange.new(18, 32)
	spray.SpreadAngle = Vector2.new(55, 55)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Acceleration = Vector3.new(0, -26, 0)
	spray.Rate = 0
	spray.Parent = host
	spray:Emit(160)
	oneShot(0.55, 1.2)
	oneShot(0.3, 0.9)
	task.delay(3, function()
		host:Destroy()
	end)
end

local function stepSurfacing(b: SunkenPath.Brief, t: number)
	local into, spot, index = SunkenPath.surfacing(b, t)
	local current = surfacing
	if not (into and spot and index) then
		if current then
			endSurfacing()
		end
		return
	end
	if not current or current.index ~= index then
		endSurfacing()
		local holder = Instance.new("Folder")
		holder.Name = "Surfacing"
		holder.Parent = workspace
		-- THE WARNING: a patch of dark water over the spot, growing, and bubbles coming up through it.
		local patch = localPart(holder, "DarkWater", Vector3.new(0.3, 16, 16), DARK_WATER, false)
		patch.Shape = Enum.PartType.Cylinder
		patch.Transparency = 0.7
		patch.CFrame = CFrame.new(spot + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		local host = localPart(holder, "Bubbles", Vector3.new(14, 1, 14), BODY, false)
		host.Transparency = 1
		host.CFrame = CFrame.new(spot - Vector3.new(0, 1, 0))
		local bubbles = Instance.new("ParticleEmitter")
		bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		bubbles.Color = ColorSequence.new(Color3.fromRGB(220, 236, 232))
		bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.1) })
		bubbles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		bubbles.Lifetime = NumberRange.new(0.5, 1)
		bubbles.Speed = NumberRange.new(2, 5)
		bubbles.EmissionDirection = Enum.NormalId.Top
		bubbles.Rate = 0
		bubbles.Parent = host
		current = { index = index, spot = spot, holder = holder, patch = patch, bubbles = bubbles, surged = false, broke = false }
		surfacing = current
	end
	local s = current :: Surfacing
	local warned = math.clamp((into + SunkenPath.WARN) / SunkenPath.WARN, 0, 1)
	local size = 16 + 24 * warned
	s.patch.Size = Vector3.new(0.3, size, size)
	s.patch.Transparency = 0.7 - 0.35 * warned
	s.bubbles.Rate = if into < 0 then 10 + 50 * warned else 70
	if into >= 0 and not s.broke then
		s.broke = true
		oneShot(0.12, 1.1)
	end
	if into >= SunkenPath.WASH_AT and not s.surged then
		s.surged = true
		surge(s.spot)
	end
end

-- ===== WHAT THE WATER AND THE SOUND DO =====

local function ensureShade(): ColorCorrectionEffect
	local existing = shade
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("ColorCorrectionEffect")
	made.Name = "SunkenShade"
	made.Parent = Lighting
	shade = made
	return made
end

local function ensureRumble(): Sound
	local existing = rumble
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Sound")
	made.Name = "SunkenRumble"
	made.SoundId = WATER_SOUND
	made.PlaybackSpeed = 0.12
	made.Looped = true
	made.Volume = 0
	made.Parent = SoundService
	made:Play()
	rumble = made
	return made
end

-- Small steps on purpose, as with every light change in this project: a shade, not a blackout.
local function applyMood()
	local cc = ensureShade()
	cc.Brightness = -0.05 * nearness - 0.02 * inside
	cc.Saturation = -0.2 * nearness - 0.1 * inside
	cc.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(200, 220, 225), nearness):Lerp(Color3.fromRGB(184, 226, 226), inside * 0.8)
	ensureRumble().Volume = 0.55 * nearness
	for part, base in pairs(waterBase) do
		if part.Parent then
			part.Color = base.colour:Lerp(DARK_WATER, 0.6 * nearness)
			part.Transparency = base.transparency - 0.15 * nearness
		end
	end
	local quiet = (1 - 0.85 * nearness) * (1 - 0.6 * inside)
	for _, s in ipairs(CollectionService:GetTagged("SunkenAmbience")) do
		if s:IsA("Sound") then
			local baseVolume = s:GetAttribute("BaseVolume")
			if typeof(baseVolume) == "number" then
				s.Volume = baseVolume * quiet
			end
		end
	end
end

local function clearMood()
	if shade then
		shade:Destroy()
		shade = nil
	end
	if rumble then
		rumble:Destroy()
		rumble = nil
	end
	nearness, inside = 0, 0
	waterBase = {}
end

-- ===== THE SEA MODEL, ARRIVING AND LEAVING =====

local function seaArrived(model: Instance)
	local b = SunkenPath.read(model)
	if not b then
		return
	end
	clearThing()
	brief = b
	seaModel = model
	buildThing(b)
	waterBase = {}
end

-- The surface plates, remembered as they were built so the darkening always eases back to them.
-- Looked for until found rather than once, because the plates can arrive a moment after the model.
local function findWater()
	local model = seaModel
	if not model or next(waterBase) ~= nil then
		return
	end
	for _, item in ipairs(model:GetChildren()) do
		if item:IsA("BasePart") and item.Name == "Water" then
			waterBase[item] = { colour = item.Color, transparency = item.Transparency }
		end
	end
end

local function seaLeft(model: Instance)
	if model ~= seaModel then
		return
	end
	brief = nil
	seaModel = nil
	clearThing()
	clearMood()
	endSurfacing()
end

-- ===== THE FACE IN THE MIRROR =====

-- Built on the mirror's face, a hair in front of it, invisible until it is wanted. Pale, eyes and a
-- mouth that are only dark hollows, and a little too low: it is looking at you from behind you.
local function buildFace(mirror: BasePart): { BasePart }
	local holder = Instance.new("Folder")
	holder.Name = "MirrorFace"
	holder.Parent = workspace
	local front = mirror.CFrame * CFrame.new(0, -0.3, -mirror.Size.Z / 2 - 0.06)
	local parts = {
		localPart(holder, "Face", Vector3.new(2.1, 2.8, 0.05), Color3.fromRGB(196, 194, 188), true),
		localPart(holder, "Hollow", Vector3.new(0.55, 0.36, 0.05), Color3.fromRGB(8, 8, 10), true),
		localPart(holder, "Hollow", Vector3.new(0.55, 0.36, 0.05), Color3.fromRGB(8, 8, 10), true),
		localPart(holder, "Hollow", Vector3.new(0.8, 0.3, 0.05), Color3.fromRGB(8, 8, 10), true),
	}
	parts[1].CFrame = front
	parts[2].CFrame = front * CFrame.new(-0.45, 0.35, -0.02)
	parts[3].CFrame = front * CFrame.new(0.45, 0.35, -0.02)
	parts[4].CFrame = front * CFrame.new(0, -0.7, -0.02)
	for _, part in ipairs(parts) do
		part.Transparency = 1
	end
	return parts
end

local function lampNear(at: Vector3): PointLight?
	for _, part in ipairs(mirrorLamps) do
		if part.Parent and (part.Position - at).Magnitude < 14 then
			local light = part:FindFirstChildOfClass("PointLight")
			if light then
				return light
			end
		end
	end
	return nil
end

local function showFace()
	for mirror, entry in pairs(mirrors) do
		if mirror.Parent then
			local light = lampNear(mirror.Position)
			task.spawn(function()
				-- The light stutters first: the warning every threat gets.
				for _ = 1, 5 do
					if light then
						light.Enabled = not light.Enabled
					end
					task.wait(0.09)
				end
				if light then
					light.Enabled = true
				end
				local drone = Instance.new("Sound")
				drone.SoundId = WATER_SOUND
				drone.PlaybackSpeed = 0.08
				drone.Volume = 0.9
				drone.Parent = SoundService
				drone:Play()
				oneShot(2.4, 0.35)
				for _, part in ipairs(entry.face) do
					part.Transparency = if part.Name == "Face" then 0.08 else 0
				end
				task.wait(0.5)
				if light then
					light.Enabled = false
				end
				for _, part in ipairs(entry.face) do
					part.Transparency = 1
				end
				task.wait(0.8)
				if light then
					light.Enabled = true
				end
				task.wait(2)
				drone:Destroy()
			end)
		end
	end
end

-- ===== THE SMALLER MOVING THINGS =====

local function makeFish(parent: Instance, index: number): Model
	local fish = Instance.new("Model")
	fish.Name = "Fish"
	local silver = if index % 4 == 0 then Color3.fromRGB(226, 150, 80) else Color3.fromRGB(170, 190, 200)
	local body = localPart(fish, "FishBody", Vector3.new(0.5, 0.8, 1.8), silver, true)
	local tail = localPart(fish, "FishTail", Vector3.new(0.15, 0.8, 0.7), silver, false)
	tail.CFrame = body.CFrame * CFrame.new(0, 0, 1.1)
	fish.PrimaryPart = body
	fish.Parent = parent
	return fish
end

local function track(tag: string, added: (Instance) -> (), removed: (Instance) -> ())
	for _, item in ipairs(CollectionService:GetTagged(tag)) do
		added(item)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(added)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(removed)
end

local function inZone(point: Vector3): boolean
	for _, zone in ipairs(zones) do
		if zone.Parent then
			local p = zone.CFrame:PointToObjectSpace(point)
			local half = zone.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
				return true
			end
		end
	end
	return false
end

local function ease(current: number, target: number, rate: number, dt: number): number
	local step = rate * dt
	if current < target then
		return math.min(target, current + step)
	end
	return math.max(target, current - step)
end

-- ===== EVERY FRAME =====

local function moveSmallThings(clock: number)
	for model, ring in pairs(rings) do
		if model.Parent then
			local turn = CFrame.new(ring.centre) * CFrame.Angles(0, -ring.spin * clock, 0) * CFrame.new(ring.centre):Inverse()
			model:PivotTo(turn * ring.rest)
		end
	end
	for model, buoy in pairs(buoys) do
		if model.Parent then
			local bob = 0.35 * math.sin(clock * 1.3 + buoy.phase)
			local tilt = 0.06 * math.sin(clock * 0.9 + buoy.phase)
			model:PivotTo(buoy.rest * CFrame.new(0, bob, 0) * CFrame.Angles(tilt, 0, tilt * 0.7))
		end
	end
	-- THE CLOCK TRIES TO MOVE ON, every half a minute or so: all four minute hands a minute forward
	-- together, a moment's hold, and back to twelve past.
	if clock >= nextTwitch then
		nextTwitch = clock + 30 + math.random() * 25
		for part, hand in pairs(hands) do
			if part.Parent then
				part.CFrame = hand.pivot * CFrame.Angles(0, 0, -math.rad(6)) * hand.pivot:Inverse() * hand.rest
			end
		end
		task.delay(0.35, function()
			for part, hand in pairs(hands) do
				if part.Parent then
					part.CFrame = hand.rest
				end
			end
		end)
	end
	for marker, shoal in pairs(shoals) do
		if marker.Parent then
			local count = #shoal.fish
			for index, fish in ipairs(shoal.fish) do
				local a = clock * shoal.speed + index * 2 * math.pi / count
				local wobble = 1 + 0.15 * math.sin(a * 3 + index)
				local rise = 1.2 * math.sin(clock * 0.8 + index)
				local here = marker.Position + Vector3.new(math.cos(a) * shoal.radius * wobble, rise, math.sin(a) * shoal.radius * 0.6)
				local ahead = marker.Position + Vector3.new(math.cos(a + 0.1) * shoal.radius * wobble, rise, math.sin(a + 0.1) * shoal.radius * 0.6)
				fish:PivotTo(CFrame.lookAt(here, ahead))
			end
		end
	end
end

local function step(dt: number)
	local now = workspace:GetServerTimeNow()
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local at: Vector3? = if root and root:IsA("BasePart") then root.Position else nil

	local b = brief
	if b and #segments > 0 then
		findWater()
		local t = now - b.epoch
		local nearest = moveThing(b, t, at)
		stepSurfacing(b, t)
		local target = math.clamp((FAR - nearest) / (FAR - NEAR), 0, 1)
		nearness = ease(nearness, target, 0.8, dt)
		inside = ease(inside, if at and inZone(at) then 1 else 0, 1.5, dt)
		applyMood()
	end
	moveSmallThings(os.clock())
end

-- A Hardcore fall, or being taken by the surfacing, while the thing is under you: one deep thud and a
-- darker moment. The event only fires in Hardcore, which is what keeps this out of Chill.
local function fell()
	if nearness < 0.35 then
		return
	end
	oneShot(0.4, 1, THUD_SOUND)
	local cc = ensureShade()
	local was = cc.Brightness
	cc.Brightness = was - 0.2
	task.delay(0.6, function()
		if cc.Parent then
			cc.Brightness = was
		end
	end)
end

function SunkenCityClient.start()
	track("SunkenSea", seaArrived, seaLeft)
	track("SunkenWhirlRing", function(item)
		if item:IsA("Model") then
			local centre = item:GetAttribute("Centre")
			local spin = item:GetAttribute("Spin")
			if typeof(centre) == "Vector3" and typeof(spin) == "number" then
				rings[item] = { centre = centre, spin = spin, rest = item:GetPivot() }
			end
		end
	end, function(item)
		if item:IsA("Model") then
			rings[item] = nil
		end
	end)
	track("SunkenBuoy", function(item)
		if item:IsA("Model") then
			buoys[item] = { rest = item:GetPivot(), phase = math.random() * 6 }
		end
	end, function(item)
		if item:IsA("Model") then
			buoys[item] = nil
		end
	end)
	track("SunkenClockHand", function(item)
		local pivot = item:GetAttribute("Pivot")
		if item:IsA("BasePart") and typeof(pivot) == "CFrame" then
			hands[item] = { rest = item.CFrame, pivot = pivot }
		end
	end, function(item)
		if item:IsA("BasePart") then
			hands[item] = nil
		end
	end)
	track("SunkenFishShoal", function(item)
		if not item:IsA("BasePart") then
			return
		end
		local count = item:GetAttribute("Count")
		local radius = item:GetAttribute("Radius")
		local speed = item:GetAttribute("Speed")
		local holder = Instance.new("Folder")
		holder.Name = "Shoal"
		holder.Parent = workspace
		local fish = {}
		local many = if typeof(count) == "number" then count else 8
		for index = 1, many do
			table.insert(fish, makeFish(holder, index))
		end
		shoals[item] = { fish = fish, radius = if typeof(radius) == "number" then radius else 10,
			speed = if typeof(speed) == "number" then speed else 0.4 }
		item.Destroying:Connect(function()
			holder:Destroy()
		end)
	end, function(item)
		if item:IsA("BasePart") then
			local shoal = shoals[item]
			local first = shoal and shoal.fish[1]
			local holder = first and first.Parent
			if holder then
				holder:Destroy()
			end
			shoals[item] = nil
		end
	end)
	track("SunkenAquariumZone", function(item)
		if item:IsA("BasePart") then
			table.insert(zones, item)
		end
	end, function(item)
		local index = table.find(zones, item :: any)
		if index then
			table.remove(zones, index)
		end
	end)
	track("SunkenMirror", function(item)
		if item:IsA("BasePart") and not mirrors[item] then
			mirrors[item] = { face = buildFace(item) }
		end
	end, function(item)
		if item:IsA("BasePart") then
			local entry = mirrors[item]
			local holder = entry and entry.face[1] and entry.face[1].Parent
			if holder then
				holder:Destroy()
			end
			mirrors[item] = nil
		end
	end)
	track("SunkenMirrorLamp", function(item)
		if item:IsA("BasePart") then
			table.insert(mirrorLamps, item)
		end
	end, function(item)
		local index = table.find(mirrorLamps, item :: any)
		if index then
			table.remove(mirrorLamps, index)
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("MirrorFace"):Connect(showFace)

	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	local fellEvent = remotes and remotes:WaitForChild("PlayerFell", 20)
	if fellEvent and fellEvent:IsA("RemoteEvent") then
		fellEvent.OnClientEvent:Connect(fell)
	end
	RunService.RenderStepped:Connect(step)
end

return SunkenCityClient
