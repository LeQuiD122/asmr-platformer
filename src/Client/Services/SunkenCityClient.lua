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
--
-- === Meshes, where they are imported ===
--
-- The animals, the fish, the gulls and the kelp are rigged meshes from blender/gen_sealife.py when
-- they are in ReplicatedStorage/Assets/TileMeshes (see ReplicatedStorage.Shared.SeaRig), moved by
-- their part and bent by their bones, and the part-built ones they have always been when they are
-- not. The report ten seconds in says which.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SunkenPath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SunkenPath"))
local SeaRig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SeaRig"))

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
-- THE SERPENT (blender/gen_serpent.py, Sea_Serpent), when it is imported: one body bent through the
-- same nineteen points the part-built one is laid on, its eyes still pale parts carried on its head.
type ThingMesh = { rig: SeaRig.Rig, chain: SeaRig.Chain, eyes: { BasePart }, eyeRest: { CFrame },
	headRest: CFrame, posed: { CFrame }, joints: { Vector3 } }
local thingMesh: ThingMesh? = nil
local thingPoints: { Vector3 } = {}
-- WHAT IS WORTH MOVING. Everything here moves on the clock, so anything far from the camera can be
-- left where it is: it is exactly where it should be the moment it comes near again. Under the water
-- past `water` nothing can be made out through the surface; the harbour's whirlpool and buoys, the
-- lights and the gulls carry further.
local SEEN = { water = 420, air = 700, harbour = 700, light = 500 }
local eyeAt = Vector3.zero -- the camera, this frame
local extras: { Extra } = {}
local nearness = 0 -- eased toward how near the thing is, 0 to 1
local inside = 0 -- eased toward whether you are inside the aquarium, 0 to 1
local rain = 0 -- eased toward whether it is raining, 0 to 1
local drowning = 0 -- eased toward whether the camera is inside the aquarium's flood, 0 to 1
local shade: ColorCorrectionEffect? = nil
local rumble: Sound? = nil
local waterBase: { [BasePart]: { colour: Color3, transparency: number } } = {}
local surfacing: Surfacing? = nil

local rings: { [Model]: { centre: Vector3, spin: number, rest: CFrame } } = {}
local buoys: { [Model]: { rest: CFrame, phase: number } } = {}
local hands: { [BasePart]: { rest: CFrame, pivot: CFrame } } = {}
local shoals: { [BasePart]: { fish: { Model }, rigs: { SeaRig.Rig }?, holder: Folder, radius: number, speed: number,
	phase: number, along: Vector3? } } = {}
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

-- EVERY PIECE GUARDED. This client does a dozen things a frame, and they used to run one after
-- another in a single function: one of them throwing stopped every one after it, every frame, with
-- nothing but a red line in Output to say so -- so the whirlpool stood still, the animals were never
-- moved and the kelp never grew, and it looked like none of them existed. Now each runs on its own,
-- and the first time one fails it says which and why, once, and the others carry on.
local failures: { [string]: boolean } = {}
local function guard(name: string, fn: (...any) -> ...any, ...: any)
	local ok, err = pcall(fn, ...)
	if not ok and not failures[name] then
		failures[name] = true
		warn(("SunkenCityClient: %s failed, and everything else carries on: %s"):format(name, tostring(err)))
	end
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
	thingMesh = nil
	local rig = SeaRig.place(holder, "Sea_Serpent", BODY)
	local chain = rig and SeaRig.chain(rig, SeaRig.BONES.Sea_Serpent)
	if rig and chain then
		rig.part.Reflectance = 0.04
		-- The eyes, where the part-built body has them: on the first segment, halfway between the
		-- first two joints, a little forward and up, looking the way the head looks.
		local head = girthAt(b, 0)
		local centre = (chain.heads[1] + chain.heads[2]) / 2
		local segment = CFrame.lookAt(centre, centre + (chain.heads[1] - chain.heads[2]))
		local eyes, eyeRest = {}, {}
		for _, side in ipairs({ -1, 1 }) do
			local eye = localPart(holder, "Eye", Vector3.new(1.4, 1.1, 1.8), EYE, true)
			eye.Transparency = 0.2
			table.insert(eyes, eye)
			table.insert(eyeRest, segment * CFrame.new(side * head * 0.72, head * 0.3, -SPACING * 0.45))
		end
		thingMesh = { rig = rig, chain = chain, eyes = eyes, eyeRest = eyeRest,
			headRest = rig.rest[chain.bones[1]], posed = {}, joints = {} }
		return
	elseif rig then
		rig.model:Destroy()
	end
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
	thingMesh = nil
end

-- Moves the body, and returns the horizontal distance from `from` to the nearest part of it. The
-- nineteen points come from SunkenPath.body, which works the surfacing out once for all of them.
local function moveThing(b: SunkenPath.Brief, t: number, from: Vector3?): number
	local nearest = math.huge
	local mesh = thingMesh
	if mesh then
		-- The serpent's joints sit half a spacing either side of the part-built body's segments.
		local points = SunkenPath.body(b, t, -0.5 * SPACING, SPACING, SEGMENTS + 1, thingPoints)
		-- The part rides the middle of the body, facing its head, so it is never far from what it
		-- draws and its bones turn only as far as the body bends.
		local middle = points[SEGMENTS // 2 + 1]
		local toward = Vector3.new(points[1].X - middle.X, 0, points[1].Z - middle.Z)
		local part = mesh.rig.part
		local frame = if toward.Magnitude > 0.1 then CFrame.lookAt(middle, middle + toward)
			else CFrame.new(middle) * part.CFrame.Rotation
		part.CFrame = frame
		local joints = mesh.joints
		for index, point in ipairs(points) do
			joints[index] = frame:PointToObjectSpace(point)
			if from and index % 3 == 1 then
				nearest = math.min(nearest, Vector3.new(point.X - from.X, 0, point.Z - from.Z).Magnitude)
			end
		end
		-- LEVEL: it doubles back at each end of its patrol, and the shortest turn there would roll
		-- it onto its back.
		SeaRig.follow(mesh.chain, mesh.rig.rest, joints, true, mesh.posed)
		local head = frame * mesh.posed[1] * mesh.headRest:Inverse()
		for index, eye in ipairs(mesh.eyes) do
			eye.CFrame = head * mesh.eyeRest[index]
		end
		return nearest
	end
	local points = SunkenPath.body(b, t, -SPACING, SPACING, SEGMENTS + 1, thingPoints)
	for index = 1, SEGMENTS do
		local here, ahead = points[index + 1], points[index]
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
-- WRITTEN ONLY WHEN IT HAS MOVED. The mood is eased every frame and then settles, and it used to be
-- written every frame regardless: the shade, the rumble, every plate of the sea (two kilometres of
-- Glass) and every ambient sound, found afresh with GetTagged -- a new table a frame, for nothing.
-- Now each of the four things it follows is taken to a two-hundredth, and nothing is written until
-- one of them changes by that.
local moodWritten = -1
-- The level's ambient sounds (SunkenAmbience) and the volume each was made at, kept by their tag.
local ambientSounds: { [Sound]: number } = {}
local function applyMood()
	local key = math.floor(nearness * 200) + 201 * (math.floor(inside * 200) + 201 * (math.floor(rain * 200)
		+ 201 * math.floor(drowning * 200)))
	if key == moodWritten and shade then
		return
	end
	moodWritten = key
	local cc = ensureShade()
	cc.Brightness = -0.05 * nearness - 0.02 * inside - 0.04 * rain - 0.06 * drowning
	cc.Saturation = -0.2 * nearness - 0.1 * inside - 0.1 * rain
	cc.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(200, 220, 225), nearness):Lerp(Color3.fromRGB(184, 226, 226), inside * 0.8)
		:Lerp(Color3.fromRGB(120, 196, 190), drowning * 0.7)
	ensureRumble().Volume = 0.55 * nearness
	for part, base in pairs(waterBase) do
		if part.Parent then
			part.Color = base.colour:Lerp(DARK_WATER, 0.6 * nearness)
			part.Transparency = base.transparency - 0.15 * nearness
		end
	end
	local quiet = (1 - 0.85 * nearness) * (1 - 0.6 * inside)
	for s, baseVolume in pairs(ambientSounds) do
		if s.Parent then
			s.Volume = baseVolume * quiet
		else
			ambientSounds[s] = nil
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
	moodWritten = -1
end

-- ===== THE SEA MODEL, ARRIVING AND LEAVING =====

local function seaArrived(model: Instance)
	local b = SunkenPath.read(model)
	if not b then
		warn("SunkenCityClient: the sea arrived without the thing's brief, so the thing is not drawn")
		return
	end
	clearThing()
	brief = b
	seaModel = model
	buildThing(b)
	waterBase = {}
	moodWritten = -1
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
			-- New plates to shade: the mood is written again whether it has moved or not.
			moodWritten = -1
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

-- A FISH: a body, a tail that beats, a pair of fins and an eye. Four parts more than it had, and
-- the difference between a shoal of grey lozenges and something alive.
-- A shoal's colours: silver with an orange one in four, gold, blue, or yellow and dark -- chosen per
-- shoal, so the street's shoals are not all one grey.
local FISH_COLOURS = {
	{ Color3.fromRGB(170, 190, 200), Color3.fromRGB(226, 150, 80) },
	{ Color3.fromRGB(230, 190, 90), Color3.fromRGB(240, 220, 150) },
	{ Color3.fromRGB(90, 150, 210), Color3.fromRGB(140, 200, 230) },
	{ Color3.fromRGB(236, 206, 70), Color3.fromRGB(60, 64, 70) },
}
local function makeFish(parent: Instance, index: number, long: number, palette: { Color3 }?): Model
	local fish = Instance.new("Model")
	fish.Name = "Fish"
	local colours = palette or FISH_COLOURS[1]
	local silver = if index % 4 == 0 then colours[2] else colours[1]
	local belly = silver:Lerp(Color3.new(1, 1, 1), 0.45)
	local body = localPart(fish, "FishBody", Vector3.new(0.5, 0.8, 1.8) * long, silver, true)
	local under = localPart(fish, "FishBelly", Vector3.new(0.42, 0.4, 1.5) * long, belly, true)
	under.CFrame = body.CFrame * CFrame.new(0, -0.22 * long, 0)
	local tail = localPart(fish, "FishTail", Vector3.new(0.15, 0.8, 0.7) * long, silver, false)
	tail.CFrame = body.CFrame * CFrame.new(0, 0, 1.1 * long)
	for _, side in ipairs({ -1, 1 }) do
		local fin = localPart(fish, "FishFin", Vector3.new(0.5, 0.12, 0.5) * long, silver, false)
		fin.CFrame = body.CFrame * CFrame.new(side * 0.3 * long, -0.1 * long, -0.1 * long)
			* CFrame.Angles(0, 0, side * 0.5)
	end
	local eye = localPart(fish, "FishEye", Vector3.new(0.18, 0.18, 0.18) * long, Color3.fromRGB(26, 28, 30), true)
	eye.CFrame = body.CFrame * CFrame.new(0.2 * long, 0.12 * long, -0.6 * long)
	fish.PrimaryPart = body
	fish.Parent = parent
	return fish
end

-- ===== THE THINGS AT THE BACK =====
--
-- Far out, where the haze has nearly everything, something long turns slowly. Never near the route,
-- never lit, never explained: they are the reason the edge of the view is worth not looking at.
-- Built from the same trick as the thing itself -- a line of ellipsoids, thickest in the middle --
-- but plainer, because at that distance a silhouette is all there is.
local HORROR_SEGMENTS = 9

local function makeHorror(parent: Instance, long: number): { BasePart }
	local dark = Color3.fromRGB(16, 30, 34)
	local body = {}
	for index = 1, HORROR_SEGMENTS do
		local share = (index - 1) / (HORROR_SEGMENTS - 1)
		local girth = long * 0.16 * math.sin(math.pi * (0.18 + 0.82 * share))
		local piece = localPart(parent, "Back", Vector3.new(girth, girth * 0.7, long / HORROR_SEGMENTS * 1.25), dark, true)
		table.insert(body, piece)
	end
	-- One fin on top, which is the only part of it that ever crosses the light.
	local fin = localPart(parent, "BackFin", Vector3.new(0.6, long * 0.12, long * 0.16), dark, false)
	table.insert(body, fin)
	return body
end

local function track(tag: string, added: (Instance) -> (), removed: (Instance) -> ())
	local function safeAdded(item: Instance)
		guard("setting up " .. tag, added, item)
	end
	local function safeRemoved(item: Instance)
		guard("taking down " .. tag, removed, item)
	end
	for _, item in ipairs(CollectionService:GetTagged(tag)) do
		safeAdded(item)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(safeAdded)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(safeRemoved)
end

-- What the tank and the sea do with the light, and what bolts when the glass is tapped.
local caustics: { [BasePart]: { phase: number, drift: number, rest: CFrame, base: number } } = {}
local shaftsSeen: { [BasePart]: { phase: number, rest: CFrame } } = {}
local tankPanes: { [BasePart]: { phase: number, base: number } } = {}
local horrors: { [BasePart]: { body: { BasePart }, long: number, radius: number, speed: number,
	phase: number, holder: Folder } } = {}
local scatterUntil = 0
-- The two lights in this level that are not steady: the lighthouse, sweeping, and the lamp at the
-- bottom of the drain, which has water coming down a wall beside it.
local beacons: { [BasePart]: { light: PointLight, base: number } } = {}
local sluiceLamps: { [BasePart]: { light: PointLight, base: number, nextFlicker: number } } = {}

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

-- ===== THE WAY DOWN THE DRAIN =====
--
-- The server sits you in the whirlpool, keeps the clock and decides where you land; from the moment
-- it hands the ride over, this draws every frame of it from the same numbers. Your own character is
-- already yours to move -- the client owns it -- so this costs nothing and is smooth, which the
-- server writing it sixty times a second was not.
type Drain = { spec: any, startAt: number, seconds: number }
local drain: Drain? = nil
local drainRemote: RemoteEvent? = nil

local function drainStarted(vortex: Vector3, from: Vector3, funnelY: number, bottomY: number,
	startAt: number, seconds: number)
	if typeof(vortex) ~= "Vector3" or typeof(from) ~= "Vector3" or typeof(startAt) ~= "number"
		or typeof(seconds) ~= "number" then
		return
	end
	drain = { spec = { vortex = vortex, from = from, funnelY = funnelY, bottomY = bottomY },
		startAt = startAt, seconds = seconds }
	if drainRemote then
		drainRemote:FireServer()
	end
end

local function moveRider(serverNow: number)
	local current = drain
	if not current then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local u = (serverNow - current.startAt) / current.seconds
	if u >= 1 or not (root and root:IsA("BasePart")) then
		drain = nil
		return
	end
	(root :: BasePart).CFrame = SunkenPath.drainFrame(current.spec, math.max(0, u))
end

-- ===== WHAT LIVES HERE, AND WHAT THE CITY DOES ON ITS OWN =====
--
-- Everything below is on this client alone, for the reason the shoals are: none of it can be touched
-- and all of it moves every frame. What has to be SHARED -- the rain, the bell, the thing on the
-- horizon, so that two players look up at the same moment -- is worked out from the level's epoch
-- and the schedules SunkenCityService writes on the sea, the same way the surfacing is.

-- The sounds this project has to be eerie with: the water sample and the landing thud, pitched a
-- long way down, the lobby's ping pitched down until it rings like a bell, and two of the material
-- takes, which a long way down are masonry letting go and something large breathing out.
local PING_SOUND = "rbxasset://sounds/electronicpingshort.wav"
-- The engine's own falling-wind loop, a little faster, is a wash of noise: close enough to rain on
-- water that the ear takes it as rain once the streaks are falling.
local RAIN_SOUND = "rbxasset://sounds/action_falling.mp3"
local CRUMBLE_SOUND = "rbxassetid://135061782882830"
local BUBBLES_SOUND = "rbxassetid://132175495859275"

local surfacePlates: { [BasePart]: { Texture } } = {}
local litWindows: { [BasePart]: { light: PointLight, lit: Color3, onAt: number, offAt: number, state: number } } = {}
local blinks: { [BasePart]: PointLight } = {}
local lanterns: { [BasePart]: { light: PointLight, base: number, dipAt: number } } = {}
local bells: { [BasePart]: { rest: CFrame, hang: CFrame } } = {}
local tolled: number? = nil
local nextStrange = 0
local DARK_PANE = Color3.fromRGB(36, 44, 48)

-- A sound somewhere, kept for as long as it actually plays at the speed it is played at. `oneShot`
-- cuts everything at four seconds, which is right for a splash and wrong for a moan an octave and a
-- half down.
local function longSound(parent: Instance, id: string, speed: number, volume: number, reach: number?): Sound
	local s = Instance.new("Sound")
	s.SoundId = id
	s.PlaybackSpeed = speed
	s.Volume = volume
	if reach then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = reach * 0.1
		s.RollOffMaxDistance = reach
	end
	s.Parent = parent
	s:Play()
	task.delay(20, function()
		s:Destroy()
	end)
	return s
end

-- ===== THE SWIMMERS =====
--
-- BIG ENOUGH TO SEE. They were drawn at life size for a person, which from a platform fifteen
-- studs over the water and through twenty studs of it is a grey fleck. Each kind has a scale; the
-- shapes and every offset in them are multiplied by it. The shark is drawn at its own size.
local SWIMMER_SCALE = { ray = 1.6, turtle = 1.4, jelly = 1.3, eel = 1.3, grouper = 1.4, shark = 1, dolphins = 1 }
-- THE TWO THAT BREAK THE SURFACE, on purpose and on the client: a pod of dolphins leaps clear of it
-- now and then, one after another, and a turtle comes up to breathe. Everything else stays under.
local LEAP_EVERY, LEAP_LONG, LEAP_HIGH = 13, 1.6, 3
local BREATH_EVERY, BREATH_LONG = 38, 7
local POD = { Vector3.new(0, 0, 0), Vector3.new(-2.6, -0.4, 3.2), Vector3.new(2.4, -0.2, 4.4) }

type Swimmer = { kind: string, parts: { BasePart }, marker: BasePart, range: number, across: number,
	speed: number, phase: number, along: Vector3, scale: number, bob: number, holder: Folder,
	rigs: { SeaRig.Rig }?, shell: BasePart? }
local swimmers: { [BasePart]: Swimmer } = {}

local function makeSwimmer(holder: Folder, kind: string, k: number, clear: boolean): { BasePart }
	local parts: { BasePart } = {}
	local function add(name: string, size: Vector3, colour: Color3, round: boolean): BasePart
		local part = localPart(holder, name, size * k, colour, round)
		table.insert(parts, part)
		return part
	end
	if kind == "ray" then
		-- A flat round body, two wings that beat slowly from where they join it, and a whip of a tail.
		add("RayBody", Vector3.new(3, 0.8, 4.2), Color3.fromRGB(58, 70, 74), true)
		add("RayWing", Vector3.new(3.4, 0.3, 3), Color3.fromRGB(64, 78, 82), true)
		add("RayWing", Vector3.new(3.4, 0.3, 3), Color3.fromRGB(64, 78, 82), true)
		add("RayTail", Vector3.new(0.2, 0.2, 4.5), Color3.fromRGB(48, 56, 60), false)
	elseif kind == "turtle" then
		add("Shell", Vector3.new(3.6, 1.5, 4.6), Color3.fromRGB(86, 96, 62), true)
		add("Head", Vector3.new(1.1, 0.9, 1.4), Color3.fromRGB(120, 124, 92), true)
		for _ = 1, 4 do
			add("Flipper", Vector3.new(2, 0.25, 0.9), Color3.fromRGB(110, 116, 84), true)
		end
	elseif kind == "jelly" then
		-- SEE-THROUGH ONLY WHERE IT CAN BE SEEN THROUGH. The sea's surface is Glass, and Glass leaves
		-- out anything transparent behind it: a clear jellyfish under it is no jellyfish at all from
		-- the route. So the street's are pale and solid, and only the tank's (`Clear`, seen through
		-- the gallery's window) are clear.
		local bell = add("JellyBell", Vector3.new(2.4, 1.8, 2.4), Color3.fromRGB(226, 196, 232), true)
		bell.Transparency = if clear then 0.4 else 0
		for _ = 1, 4 do
			local tendril = add("Tendril", Vector3.new(0.12, 3.6, 0.12), Color3.fromRGB(236, 212, 240), false)
			tendril.Transparency = if clear then 0.45 else 0
		end
	elseif kind == "eel" then
		for index = 1, 9 do
			local thick = 1.1 * (1 - (index - 1) / 11)
			add("Eel", Vector3.new(thick, thick, 2.4), Color3.fromRGB(48, 58, 50), true)
		end
	elseif kind == "dolphins" then
		-- THREE, each a body, a pale belly, a beak, a fin, two flippers and flukes.
		for _ = 1, #POD do
			local blue = Color3.fromRGB(112, 130, 146)
			add("DolphinBody", Vector3.new(1.5, 1.4, 6.5), blue, true)
			add("DolphinBelly", Vector3.new(1.2, 0.7, 5), Color3.fromRGB(214, 220, 222), true)
			add("DolphinBeak", Vector3.new(0.45, 0.45, 1.5), blue, true)
			add("DolphinFin", Vector3.new(0.25, 1.3, 1.4), blue, false)
			add("DolphinFlipper", Vector3.new(1.6, 0.15, 0.7), blue, false)
			add("DolphinFlipper", Vector3.new(1.6, 0.15, 0.7), blue, false)
			add("DolphinFlukes", Vector3.new(2.4, 0.15, 0.9), blue, false)
		end
	elseif kind == "shark" then
		-- Grey over white, a dorsal fin that breaks the line of it, a tail that sweeps. It cruises.
		local grey = Color3.fromRGB(92, 104, 112)
		add("SharkBody", Vector3.new(2.2, 2.3, 10), grey, true)
		add("SharkBelly", Vector3.new(1.8, 1.1, 8.4), Color3.fromRGB(196, 202, 204), true)
		add("SharkDorsal", Vector3.new(0.3, 2.4, 2), grey, false)
		add("SharkTail", Vector3.new(0.3, 3.2, 1.3), grey, false)
		add("SharkTail", Vector3.new(0.3, 1.6, 1), grey, false)
		add("SharkFin", Vector3.new(2.6, 0.2, 1.3), grey, false)
		add("SharkFin", Vector3.new(2.6, 0.2, 1.3), grey, false)
		add("SharkEye", Vector3.new(0.3, 0.3, 0.3), Color3.fromRGB(16, 16, 18), true)
		add("SharkEye", Vector3.new(0.3, 0.3, 0.3), Color3.fromRGB(16, 16, 18), true)
	else
		-- The grouper: a big slow fish that has been down here longer than anyone.
		add("Grouper", Vector3.new(2.2, 2.6, 6), Color3.fromRGB(96, 92, 80), true)
		add("GrouperTail", Vector3.new(0.3, 2.4, 1.6), Color3.fromRGB(86, 82, 70), false)
		add("GrouperFin", Vector3.new(0.3, 1.4, 2.4), Color3.fromRGB(86, 82, 70), false)
		add("GrouperEye", Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(20, 22, 24), true)
		add("GrouperEye", Vector3.new(0.4, 0.4, 0.4), Color3.fromRGB(20, 22, 24), true)
	end
	return parts
end

-- THE SAME ANIMALS AS MESHES, when they are imported: which mesh each kind is, and its colour (a
-- mesh takes one, so a ray is the grey of its back and a dolphin its own blue all over).
local SWIMMER_MESH: { [string]: { name: string, colour: Color3 } } = {
	ray = { name = "Sea_Ray", colour = Color3.fromRGB(64, 78, 82) },
	turtle = { name = "Sea_Turtle", colour = Color3.fromRGB(120, 124, 92) },
	jelly = { name = "Sea_Jelly", colour = Color3.fromRGB(226, 196, 232) },
	eel = { name = "Sea_Eel", colour = Color3.fromRGB(48, 58, 50) },
	dolphins = { name = "Sea_Dolphin", colour = Color3.fromRGB(112, 130, 146) },
	shark = { name = "Sea_Shark", colour = Color3.fromRGB(92, 104, 112) },
	grouper = { name = "Sea_Grouper", colour = Color3.fromRGB(96, 92, 80) },
}
-- HOW HARD EACH SWIMS, in radians a bone. check_sunkencity.py restates the ones that decide how near
-- something a fin or a wing tip can come: the ray's wings over the tunnel's roof above all, and how
-- steeply a leaping dolphin can point.
local SWIM = {
	sharkWag = { 0.1, 0.18, 0.3 },
	grouperWag = { 0.1, 0.28 },
	eelWave = 0.28,
	rayBeat = { 0.22, 0.18 },
	dolphinBeat = { 0.05, 0.15, 0.3 },
	-- A leaping dolphin points along its arc, but never steeper than this; the arc's steepness is
	-- judged over the fifth of a second ahead, as if it went at least pitchRun along in it. At the
	-- turn of its wander it barely moves along, and judged by that alone it would stand on its tail.
	pitch = 0.7,
	pitchRun = 1.2,
	spine = SeaRig.numbered("Spine_", 7),
	rims = SeaRig.numbered("Rim_", 4),
	arms = SeaRig.numbered("Arm_", 4),
	armTips = SeaRig.numbered("ArmTip_", 4),
}

-- The meshes for one swimmer (three for the pod, and the turtle's shell as well as its body), or
-- nil if any of them is not imported, in which case it is drawn the old way whole.
local function makeSwimmerMesh(holder: Folder, kind: string, clear: boolean): ({ SeaRig.Rig }?, BasePart?)
	local spec = SWIMMER_MESH[kind]
	if not spec or not SeaRig.template(spec.name) or (kind == "turtle" and not SeaRig.template("Sea_TurtleShell")) then
		return nil, nil
	end
	local shell: BasePart? = nil
	if kind == "turtle" then
		local rig = SeaRig.place(holder, "Sea_TurtleShell", Color3.fromRGB(86, 96, 62))
		shell = rig and rig.part
	end
	local rigs = {}
	for _ = 1, if kind == "dolphins" then #POD else 1 do
		local rig = SeaRig.place(holder, spec.name, spec.colour)
		if rig then
			-- Clear only where it is seen through the gallery's window, as the part-built one is.
			if kind == "jelly" and clear then
				rig.part.Transparency = 0.4
			end
			table.insert(rigs, rig)
		end
	end
	return rigs, shell
end

-- Where a swimmer is at `clock`, in the street's own frame (or the tank's): up to `range` along it
-- and `across` over it, and never more across than that, because past it is something solid. Most
-- wander on slow sines that never line up, so they go somewhere rather than round a circle, rising
-- and sinking by `bob`. An eel goes round a long loop with a wriggle across it; its body is its head
-- a moment ago, so the wriggle runs down it the way it does down a real one.
-- How far above its wander a leaping dolphin or a breathing turtle is at `clock`: from where it
-- swims up through the surface and back, as an arc for the leap and a slow rise and hold for the
-- breath. `lag` staggers the pod so they go one after another. A dolphin's leap is judged from where
-- it actually is (`fromY`, its bob and its place in the pod and all), so the top of every arc is
-- LEAP_HIGH over the water whatever the bob is doing at the time.
local function lift(s: Swimmer, clock: number, lag: number, fromY: number?): number
	local b = brief
	if not b then
		return 0
	end
	local under = b.waterY - (fromY or s.marker.Position.Y)
	if s.kind == "dolphins" then
		local into = (clock + s.phase - lag) % LEAP_EVERY
		if into < LEAP_LONG then
			return (under + LEAP_HIGH) * math.sin(math.pi * into / LEAP_LONG)
		end
	elseif s.kind == "turtle" then
		local into = (clock + s.phase * 3) % BREATH_EVERY
		if into < BREATH_LONG then
			local ease = math.clamp(math.min(into, BREATH_LONG - into) / 2, 0, 1)
			return (under - 0.55 * s.scale) * ease * ease * (3 - 2 * ease)
		end
	end
	return 0
end

-- `calm` leaves the eel's wriggle out: a mesh eel wriggles by its bones, along its own line.
local function swimmerAt(s: Swimmer, clock: number, calm: boolean?): Vector3
	local k = clock * 0.18 * s.speed * (if s.kind == "dolphins" then 2 else 1) + s.phase
	local home = s.marker.Position
	local side = Vector3.new(-s.along.Z, 0, s.along.X)
	if s.kind == "eel" then
		local a = clock * 0.1 * s.speed + s.phase
		local wriggle = if calm then 0 else math.sin(clock * 3.2 + s.phase) * 1.1
		return home + s.along * (math.cos(a) * s.range * 0.7)
			+ side * (math.sin(a) * math.min(s.across - 1.2, s.range * 0.45) + wriggle)
			+ Vector3.new(0, math.sin(a * 2.3) * math.min(1.2, s.bob), 0)
	elseif s.kind == "jelly" then
		return home + s.along * (math.sin(k * 0.3) * s.range) + side * (math.cos(k * 0.23) * s.across)
			+ Vector3.new(0, math.sin(k * 0.8) * s.bob, 0)
	end
	return home + s.along * (math.sin(k * 0.61) * s.range) + side * (math.sin(k * 0.43 + 1.7) * s.across)
		+ Vector3.new(0, math.sin(k * 0.29) * s.bob + (if s.kind == "turtle" then lift(s, clock, 0) else 0), 0)
end

-- A splash where something breaks the surface, and the sound of it if you are near.
local function splash(at: Vector3, size: number)
	local host = localPart(workspace, "Splash", Vector3.new(1, 1, 1), BODY, false)
	host.Transparency = 1
	host.Position = at
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/smoke_main.dds"
	burst.Color = ColorSequence.new(Color3.fromRGB(232, 244, 242))
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6 * size), NumberSequenceKeypoint.new(1, 1.8 * size) })
	burst.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	burst.Lifetime = NumberRange.new(0.5, 0.9)
	burst.Speed = NumberRange.new(4, 8)
	burst.SpreadAngle = Vector2.new(35, 35)
	burst.EmissionDirection = Enum.NormalId.Top
	burst.Acceleration = Vector3.new(0, -24, 0)
	burst.Rate = 0
	burst.Parent = host
	burst:Emit(math.floor(14 * size))
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - at).Magnitude < 120 then
		longSound(host, WATER_SOUND, 1.1 + math.random() * 0.2, 0.35, 90)
	end
	task.delay(2, function()
		host:Destroy()
	end)
end

-- Where one of the pod is at `clock`, and which way it points: the way it is going, pitched with
-- the arc of a leap but never steeper than SWIM.pitch.
local function dolphinFrame(s: Swimmer, clock: number, index: number): CFrame
	local offset = POD[index]
	local lag = (index - 1) * 0.35
	local side = Vector3.new(-s.along.Z, 0, s.along.X)
	local function at(c: number): Vector3
		local spot = swimmerAt(s, c) + side * offset.X + s.along * offset.Z + Vector3.new(0, offset.Y, 0)
		return spot + Vector3.new(0, lift(s, c, lag, spot.Y), 0)
	end
	local here, ahead = at(clock), at(clock + 0.2)
	local flat = Vector3.new(ahead.X - here.X, 0, ahead.Z - here.Z)
	local way = if flat.Magnitude > 0.02 then flat.Unit else s.along
	local pitch = math.clamp(math.atan2(ahead.Y - here.Y, math.max(flat.Magnitude, SWIM.pitchRun)), -SWIM.pitch, SWIM.pitch)
	return CFrame.lookAt(here, here + way) * CFrame.Angles(pitch, 0, 0)
end

-- The pod, one dolphin at a time: each follows the pod's line from its own place in it, leaps on
-- its own beat, and splashes going out and coming back.
local splashed: { [BasePart]: { [number]: number } } = {}
local function moveDolphins(s: Swimmer, clock: number)
	local p = s.parts
	local b = brief
	for index = 1, #POD do
		local lag = (index - 1) * 0.35
		local heading = dolphinFrame(s, clock, index)
		local here = heading.Position
		local rig = s.rigs and s.rigs[index]
		if rig then
			-- Dolphins beat up and down, a wave from the middle of the back to the flukes.
			rig.part.CFrame = heading
			for bone, name in ipairs({ "Spine_1", "Spine_2", "Flukes" }) do
				SeaRig.bend(rig, name, SeaRig.ACROSS, math.sin(clock * 5 + index - 0.6 * bone) * SWIM.dolphinBeat[bone])
			end
		elseif #p >= index * 7 then
			local beat = math.sin(clock * 5 + index) * 0.25
			local first = (index - 1) * 7
			p[first + 1].CFrame = heading
			p[first + 2].CFrame = heading * CFrame.new(0, -0.35, 0.2)
			p[first + 3].CFrame = heading * CFrame.new(0, -0.15, -3.6)
			p[first + 4].CFrame = heading * CFrame.new(0, 0.9, 0.4) * CFrame.Angles(0.5, 0, 0)
			p[first + 5].CFrame = heading * CFrame.new(-0.9, -0.45, -1.2) * CFrame.Angles(0, 0.3, 0.4)
			p[first + 6].CFrame = heading * CFrame.new(0.9, -0.45, -1.2) * CFrame.Angles(0, -0.3, -0.4)
			p[first + 7].CFrame = heading * CFrame.new(0, 0, 3.5) * CFrame.Angles(beat, 0, 0)
		end
		-- The splash, once going out and once coming back.
		if b then
			local into = (clock + s.phase - lag) % LEAP_EVERY
			local marks = splashed[s.marker] or {}
			splashed[s.marker] = marks
			local leap = math.floor((clock + s.phase - lag) / LEAP_EVERY)
			for edge, when in ipairs({ LEAP_LONG * 0.12, LEAP_LONG * 0.88 }) do
				local key = index * 10 + edge
				if into >= when and into < LEAP_LONG and marks[key] ~= leap then
					marks[key] = leap
					splash(Vector3.new(here.X, b.waterY + 0.3, here.Z), 1)
				end
			end
		end
	end
end

-- THE MESHES SWIM BY BENDING: a wave down a fish's body, a ray's wings from the root out, a turtle's
-- flippers rowing and flapping, a jellyfish's bell pulling in and letting go.
local function moveSwimmerMesh(s: Swimmer, clock: number)
	local rig = (s.rigs :: { SeaRig.Rig })[1]
	if not rig then
		return
	end
	local UP, ACROSS, FORWARD = SeaRig.UP, SeaRig.ACROSS, SeaRig.FORWARD
	local calm = s.kind == "eel"
	local here = swimmerAt(s, clock, calm)
	local ahead = swimmerAt(s, clock + 0.25, calm)
	local heading = if (ahead - here).Magnitude > 0.01 then CFrame.lookAt(here, ahead) else CFrame.new(here)
	local t = clock + s.phase
	if s.kind == "ray" then
		-- The wing tips a beat behind the roots, which is the ripple a ray's wing actually makes.
		local root, tip = math.sin(t * 2.2), math.sin(t * 2.2 - 0.6)
		rig.part.CFrame = heading
		SeaRig.bend(rig, "Wing_L1", FORWARD, root * SWIM.rayBeat[1])
		SeaRig.bend(rig, "Wing_R1", FORWARD, -root * SWIM.rayBeat[1])
		SeaRig.bend(rig, "Wing_L2", FORWARD, tip * SWIM.rayBeat[2])
		SeaRig.bend(rig, "Wing_R2", FORWARD, -tip * SWIM.rayBeat[2])
		SeaRig.bend(rig, "Tail", UP, math.sin(t * 3) * 0.3)
	elseif s.kind == "turtle" then
		local stroke = t * 1.6
		if s.shell then
			s.shell.CFrame = heading
		end
		rig.part.CFrame = heading
		SeaRig.bend2(rig, "Flipper_FL", FORWARD, math.sin(stroke) * 0.4, UP, math.cos(stroke) * 0.3)
		SeaRig.bend2(rig, "Flipper_FR", FORWARD, -math.sin(stroke) * 0.4, UP, -math.cos(stroke) * 0.3)
		SeaRig.bend(rig, "Flipper_BL", UP, math.sin(stroke + 1) * 0.25)
		SeaRig.bend(rig, "Flipper_BR", UP, -math.sin(stroke + 1) * 0.25)
		-- Coming up to breathe it lifts its head out; the rest of the time it looks about.
		local up = math.clamp(lift(s, clock, 0) / 3, 0, 1)
		SeaRig.bend2(rig, "Head", UP, math.sin(t * 0.4) * 0.25 * (1 - up), ACROSS, 0.35 * up)
	elseif s.kind == "jelly" then
		-- The bell pulls in quickly and lets go slowly, and each pull lifts it a little.
		local beat = (t * 0.55) % 1
		local pull = if beat < 0.3 then math.sin(math.pi * beat / 0.3) else 0
		rig.part.CFrame = CFrame.new(here + Vector3.new(0, 0.25 * pull, 0))
			* CFrame.Angles(0.08 * math.sin(t * 0.3), s.phase, 0.08 * math.cos(t * 0.37))
		for q = 1, 4 do
			local bone = rig.bones[SWIM.rims[q]]
			local at = if bone then rig.rest[bone].Position else Vector3.zero
			local out = Vector3.new(at.X, 0, at.Z)
			if out.Magnitude > 0.01 then
				-- About UP x out, which turns the rim in and down.
				SeaRig.bend(rig, SWIM.rims[q], UP:Cross(out.Unit), 0.35 * pull)
			end
			SeaRig.bend(rig, SWIM.arms[q], ACROSS, 0.12 * math.sin(t * 0.9 + q))
			SeaRig.bend(rig, SWIM.armTips[q], FORWARD, 0.22 * math.sin(t * 1.1 + q * 1.7))
		end
	elseif s.kind == "eel" then
		rig.part.CFrame = heading
		for index = 1, 7 do
			SeaRig.bend(rig, SWIM.spine[index], UP, SWIM.eelWave * math.sin(t * 3.2 - 0.9 * index))
		end
	elseif s.kind == "shark" then
		local wag = math.sin(t * 1.8)
		rig.part.CFrame = heading * CFrame.Angles(0, -wag * 0.05, 0)
		for index = 1, 3 do
			SeaRig.bend(rig, SWIM.spine[index], UP, SWIM.sharkWag[index] * math.sin(t * 1.8 - 0.7 * index))
		end
	else
		rig.part.CFrame = heading
		SeaRig.bend(rig, "Spine_1", UP, SWIM.grouperWag[1] * math.sin(t * 2.4 - 0.7))
		SeaRig.bend(rig, "Tail", UP, SWIM.grouperWag[2] * math.sin(t * 2.4 - 1.4))
	end
end

local function moveSwimmers(clock: number)
	for marker, s in pairs(swimmers) do
		if not marker.Parent then
			swimmers[marker] = nil
			continue
		end
		if (marker.Position - eyeAt).Magnitude > SEEN.water + s.range then
			continue
		end
		local p = s.parts
		local k = s.scale
		if s.kind == "dolphins" then
			moveDolphins(s, clock)
			continue
		end
		if s.rigs then
			moveSwimmerMesh(s, clock)
			continue
		end
		if s.kind == "eel" then
			-- Each segment is where the head was a moment before, facing the one ahead of it.
			local lag = 2.2 * k / math.max(0.5, 0.1 * s.speed * s.range * 0.6)
			local ahead = swimmerAt(s, clock + lag)
			for index, part in ipairs(p) do
				local at = swimmerAt(s, clock - (index - 1) * lag)
				part.CFrame = if (ahead - at).Magnitude > 0.01 then CFrame.lookAt(at, ahead) else CFrame.new(at)
				ahead = at
			end
			continue
		end
		local here = swimmerAt(s, clock)
		local ahead = swimmerAt(s, clock + 0.25)
		local heading = if (ahead - here).Magnitude > 0.01 then CFrame.lookAt(here, ahead) else CFrame.new(here)
		if s.kind == "ray" then
			-- Wings hinge at the body's edge, not at their own middle.
			local beat = math.sin(clock * 2.2 + s.phase) * 0.45
			p[1].CFrame = heading
			p[2].CFrame = heading * CFrame.new(-1.3 * k, 0, 0.3 * k) * CFrame.Angles(0, 0, beat) * CFrame.new(-1.5 * k, 0, 0)
			p[3].CFrame = heading * CFrame.new(1.3 * k, 0, 0.3 * k) * CFrame.Angles(0, 0, -beat) * CFrame.new(1.5 * k, 0, 0)
			p[4].CFrame = heading * CFrame.new(0, 0, 4 * k) * CFrame.Angles(0, math.sin(clock * 3 + s.phase) * 0.3, 0)
		elseif s.kind == "turtle" then
			local paddle = math.sin(clock * 1.6 + s.phase) * 0.5
			p[1].CFrame = heading
			p[2].CFrame = heading * CFrame.new(0, 0.1 * k, -2.8 * k)
			p[3].CFrame = heading * CFrame.new(-2 * k, 0, -1.2 * k) * CFrame.Angles(0, paddle, -0.3)
			p[4].CFrame = heading * CFrame.new(2 * k, 0, -1.2 * k) * CFrame.Angles(0, -paddle, 0.3)
			p[5].CFrame = heading * CFrame.new(-1.6 * k, 0, 1.8 * k) * CFrame.Angles(0, -paddle * 0.5, -0.3)
			p[6].CFrame = heading * CFrame.new(1.6 * k, 0, 1.8 * k) * CFrame.Angles(0, paddle * 0.5, 0.3)
		elseif s.kind == "jelly" then
			-- The bell pulses and the tendrils trail and sway under it.
			local pulse = 1 + 0.12 * math.sin(clock * 2 + s.phase)
			p[1].Size = Vector3.new(2.4 * pulse, 1.8 / pulse, 2.4 * pulse) * k
			p[1].CFrame = CFrame.new(here)
			for index = 2, 5 do
				local a = index * math.pi / 2
				p[index].CFrame = CFrame.new(here + Vector3.new(math.cos(a) * 0.6, -2.4, math.sin(a) * 0.6) * k)
					* CFrame.Angles(math.sin(clock * 1.3 + index) * 0.25, 0, math.cos(clock * 1.1 + index) * 0.25)
			end
		elseif s.kind == "shark" then
			local wag = math.sin(clock * 1.8 + s.phase)
			local body = heading * CFrame.Angles(0, wag * 0.06, 0)
			p[1].CFrame = body
			p[2].CFrame = body * CFrame.new(0, -0.55 * k, 0.3 * k)
			p[3].CFrame = body * CFrame.new(0, 1.9 * k, 0.2 * k) * CFrame.Angles(0.45, 0, 0)
			local root = body * CFrame.new(0, 0, 5 * k) * CFrame.Angles(0, wag * 0.45, 0)
			p[4].CFrame = root * CFrame.new(0, 1.1 * k, 0.4 * k) * CFrame.Angles(0.6, 0, 0)
			p[5].CFrame = root * CFrame.new(0, -0.6 * k, 0.2 * k) * CFrame.Angles(-0.5, 0, 0)
			p[6].CFrame = body * CFrame.new(-1.5 * k, -0.6 * k, -1.2 * k) * CFrame.Angles(0, 0, 0.35)
			p[7].CFrame = body * CFrame.new(1.5 * k, -0.6 * k, -1.2 * k) * CFrame.Angles(0, 0, -0.35)
			p[8].CFrame = body * CFrame.new(-0.85 * k, 0.35 * k, -4.1 * k)
			p[9].CFrame = body * CFrame.new(0.85 * k, 0.35 * k, -4.1 * k)
		else
			local wag = math.sin(clock * 2.4 + s.phase) * 0.35
			p[1].CFrame = heading
			p[2].CFrame = heading * CFrame.new(0, 0, 3.4 * k) * CFrame.Angles(0, wag, 0)
			p[3].CFrame = heading * CFrame.new(0, 1.6 * k, 0.4 * k)
			p[4].CFrame = heading * CFrame.new(0.9 * k, 0.4 * k, -2.2 * k)
			p[5].CFrame = heading * CFrame.new(-0.9 * k, 0.4 * k, -2.2 * k)
		end
	end
end

-- ===== THE GULLS =====
--
-- White over grey, black-tipped, circling their points over the street: flapping for a while, then
-- gliding with the wings held, banked into the turn.
type Gull = { marker: BasePart, parts: { BasePart }, radius: number, speed: number, phase: number, holder: Folder,
	body: BasePart?, wings: SeaRig.Rig? }
local gulls: { [BasePart]: Gull } = {}
local GULL_SIZE = 1.4

local function makeGull(holder: Folder): { BasePart }
	local parts: { BasePart } = {}
	local white, grey, black = Color3.fromRGB(240, 240, 236), Color3.fromRGB(176, 182, 188), Color3.fromRGB(34, 34, 36)
	for _, spec in ipairs({
		{ "GullBody", Vector3.new(1.1, 1, 2.6), white, true },
		{ "GullHead", Vector3.new(0.9, 0.85, 1), white, true },
		{ "GullBeak", Vector3.new(0.22, 0.22, 0.7), Color3.fromRGB(236, 196, 70), false },
		{ "GullWing", Vector3.new(3.4, 0.15, 1.2), grey, false },
		{ "GullWing", Vector3.new(3.4, 0.15, 1.2), grey, false },
		{ "GullTip", Vector3.new(1, 0.16, 0.9), black, false },
		{ "GullTip", Vector3.new(1, 0.16, 0.9), black, false },
		{ "GullTail", Vector3.new(0.8, 0.12, 0.9), white, false },
	}) do
		table.insert(parts, localPart(holder, spec[1], spec[2] * GULL_SIZE, spec[3], spec[4]))
	end
	return parts
end

local function moveGulls(clock: number)
	local g = GULL_SIZE
	for marker, gull in pairs(gulls) do
		if not marker.Parent then
			gulls[marker] = nil
			continue
		end
		local centre = marker.Position
		if (centre - eyeAt).Magnitude > SEEN.air + gull.radius then
			continue
		end
		local a = clock * gull.speed + gull.phase
		local function at(angle: number): Vector3
			return centre + Vector3.new(math.cos(angle) * gull.radius, 1.5 * math.sin(angle * 2 + gull.phase), math.sin(angle) * gull.radius)
		end
		local here = at(a)
		local ahead = at(a + 0.05 * math.sign(gull.speed))
		local bank = if gull.speed > 0 then 0.35 else -0.35
		local body = CFrame.lookAt(here, ahead) * CFrame.Angles(0, 0, bank)
		local cycle = (clock + gull.phase) % 3.7
		local wing = if cycle < 1.2 then math.sin(clock * 9) * 0.6 else 0.12
		local wings = gull.wings
		if wings and gull.body then
			-- The mesh: body and wings in one frame, the tips a beat behind the roots.
			local tip = if cycle < 1.2 then math.sin(clock * 9 - 0.7) * 0.4 else 0.05
			gull.body.CFrame = body
			wings.part.CFrame = body
			SeaRig.bend(wings, "Wing_L1", SeaRig.FORWARD, wing)
			SeaRig.bend(wings, "Wing_R1", SeaRig.FORWARD, -wing)
			SeaRig.bend(wings, "Wing_L2", SeaRig.FORWARD, tip)
			SeaRig.bend(wings, "Wing_R2", SeaRig.FORWARD, -tip)
			continue
		end
		local p = gull.parts
		p[1].CFrame = body
		p[2].CFrame = body * CFrame.new(0, 0.35 * g, -1.4 * g)
		p[3].CFrame = body * CFrame.new(0, 0.25 * g, -2.1 * g)
		for index, side in ipairs({ -1, 1 }) do
			local hinge = body * CFrame.new(side * 0.5 * g, 0.25 * g, 0) * CFrame.Angles(0, 0, side * wing)
			p[3 + index].CFrame = hinge * CFrame.new(side * 1.7 * g, 0, 0)
			p[5 + index].CFrame = hinge * CFrame.new(side * 3.6 * g, 0, 0.1 * g)
		end
		p[8].CFrame = body * CFrame.new(0, 0.1 * g, 1.6 * g)
	end
end

-- THE WHIRLPOOL'S WATER: the texture on every segment of the funnel slides round and in, faster the
-- further in the ring is, so the surface pours down it.
local whirlFlow: { [BasePart]: { texture: Texture, ring: number } } = {}
local function moveWhirlFlow(clock: number)
	for part, flow in pairs(whirlFlow) do
		if not part.Parent then
			whirlFlow[part] = nil
			continue
		end
		if (part.Position - eyeAt).Magnitude > SEEN.harbour then
			continue
		end
		flow.texture.OffsetStudsU = clock * (1.5 + flow.ring * 1.2)
		flow.texture.OffsetStudsV = clock * (2 + flow.ring * 1.6)
	end
end

-- ===== THE FERRIS WHEEL =====
--
-- SunkenCityService stands it and says, on each turning piece, where its axle is and how fast it
-- goes. The wheel turns about the axle; every cabin hangs level from its pin, swinging a little.
-- On the server's clock, so everyone sees it at the same place in its very slow turn.
type FerrisPiece = { axle: CFrame, spin: number, epoch: number, index: number?, count: number, radius: number, hang: number }
local ferris: { [Instance]: FerrisPiece } = {}
local function moveFerris()
	local now = workspace:GetServerTimeNow()
	for item, piece in pairs(ferris) do
		if not item.Parent then
			ferris[item] = nil
			continue
		end
		local turn = ((now - piece.epoch) * piece.spin) % (2 * math.pi)
		local frame: CFrame
		local index = piece.index
		if index then
			local pin = (piece.axle * CFrame.Angles(turn + 2 * math.pi * index / piece.count, 0, 0))
				* Vector3.new(0, 0, -piece.radius)
			frame = CFrame.new(pin) * piece.axle.Rotation * CFrame.Angles(0.05 * math.sin(now * 0.7 + index), 0, 0)
				* CFrame.new(0, -piece.hang, 0)
		else
			frame = piece.axle * CFrame.Angles(turn, 0, 0)
		end
		if item:IsA("BasePart") then
			item.CFrame = frame
		elseif item:IsA("Model") then
			item:PivotTo(frame)
		end
	end
end

-- ===== THE KELP =====
--
-- A strand is a stipe of short segments from its holdfast to just under the surface, with blades
-- off it on alternating sides and a float at the root of every other blade, darker and greener low
-- down and gold at the top where the light is. It sways as a strand does: hardly at all at the
-- foot and most at the top, leaning with the current, with a wave running up it so the top lags the
-- middle. Only strands near the camera move; the rest hold still where nobody can tell.
type Kelp = { marker: BasePart, height: number, phase: number, lean: Vector3, across: Vector3, joints: number,
	parts: { BasePart }, blades: { { part: BasePart, joint: number, side: number, long: number } },
	floats: { { part: BasePart, joint: number, side: number } }, holder: Folder,
	rig: SeaRig.Rig?, chain: SeaRig.Chain?, canopy: SeaRig.Rig?, frame: CFrame?, jointBuf: { Vector3 } }
local kelps: { [BasePart]: Kelp } = {}
local KELP_NEAR = 300
local KELP_STIPE = Color3.fromRGB(96, 88, 48)
local KELP_LOW, KELP_HIGH = Color3.fromRGB(70, 92, 44), Color3.fromRGB(156, 150, 70)

-- Where joint `i` of `joints` is at `clock`. Its lateral reach is at most 0.9 * (2 + 0.03 * height)
-- at the top, which is what the server allows for (check_sunkencity.py restates it).
local function kelpJoint(k: Kelp, i: number, clock: number): Vector3
	local f = i / k.joints
	local bend = f ^ 1.6
	local amp = 2 + k.height * 0.03
	local sway = math.sin(clock * 0.55 + k.phase - f * 2.4)
	local drift = math.cos(clock * 0.37 + k.phase * 1.3 - f * 1.9)
	return k.marker.Position + Vector3.new(0, f * k.height, 0) + k.lean * (bend * amp * (0.5 + 0.35 * sway))
		+ k.across * (bend * amp * 0.3 * drift)
end

local function poseKelp(k: Kelp, clock: number, moved: { BasePart }, frames: { CFrame })
	local joints = {}
	for i = 0, k.joints do
		joints[i] = kelpJoint(k, i, clock)
	end
	for i = 1, k.joints do
		local from, to = joints[i - 1], joints[i]
		table.insert(moved, k.parts[i])
		table.insert(frames, CFrame.lookAt((from + to) / 2, to))
	end
	for _, blade in ipairs(k.blades) do
		local at = joints[blade.joint]
		local flutter = math.sin(clock * 1.7 + blade.joint + k.phase)
		local dir = (k.lean * 0.9 + k.across * (blade.side * 0.7 + 0.25 * flutter) + Vector3.yAxis * 0.35).Unit
		table.insert(moved, blade.part)
		table.insert(frames, CFrame.lookAt(at + dir * (blade.long / 2), at + dir * blade.long)
			* CFrame.Angles(0, 0, math.sin(clock * 0.9 + blade.joint) * 0.6))
	end
	for _, float in ipairs(k.floats) do
		local at = joints[float.joint]
		table.insert(moved, float.part)
		table.insert(frames, CFrame.new(at + (k.lean * 0.3 + k.across * (float.side * 0.45)) * 1))
	end
end

-- THE MESH STRAND (Sea_Kelp, and Sea_KelpCanopy on the street's): its joints are exactly where the
-- part-built strand's would be (kelpJoint, which is what the checker holds), its stipe's bones laid
-- through them, and the canopy set on the stipe's top, streaming down the current and rippling.
local KELP = {
	bones = SeaRig.numbered("Kelp_", 12),
	fronds = SeaRig.numbered("Frond_", 4),
	-- The stipe's top stands this far under the strand's Height when it carries a canopy, whose
	-- fronds rise to about that Height as they ripple, and this far when it does not (the float's
	-- top is at about the Height then).
	canopyDown = 3.5,
	bareDown = 1.5,
	ripple = 0.1, -- radians a frond bone
	stipe = Color3.fromRGB(92, 100, 52),
}

local function poseKelpMesh(k: Kelp, clock: number)
	local rig, chain, frame = k.rig, k.chain, k.frame
	if not (rig and chain and frame) then
		return
	end
	local joints = k.jointBuf
	for i = 0, k.joints do
		joints[i + 1] = frame:PointToObjectSpace(kelpJoint(k, i, clock))
	end
	local top = SeaRig.follow(chain, rig.rest, joints)
	local canopy = k.canopy
	if canopy then
		canopy.part.CFrame = frame * top * CFrame.new(chain.tails[#chain.tails])
		for index, name in ipairs(KELP.fronds) do
			SeaRig.bend(canopy, name, Vector3.zAxis, KELP.ripple * math.sin(clock * 1.3 + k.phase - 1.2 * index))
		end
	end
end

local function growKelp(marker: BasePart): Kelp
	local height = marker:GetAttribute("Height")
	local phase = marker:GetAttribute("Phase")
	local leanAngle = marker:GetAttribute("Lean")
	local tall = if typeof(height) == "number" then height else 40
	local a = if typeof(leanAngle) == "number" then leanAngle else 0
	local lean = Vector3.new(math.cos(a), 0, math.sin(a))
	local holder = Instance.new("Folder")
	holder.Name = "Kelp"
	holder.Parent = workspace
	local joints = math.clamp(math.floor(tall / 8), 4, 14)
	local k: Kelp = { marker = marker, height = tall, phase = if typeof(phase) == "number" then phase else 0, lean = lean,
		across = Vector3.new(-lean.Z, 0, lean.X), joints = joints, parts = {}, blades = {}, floats = {}, holder = holder,
		jointBuf = {} }
	local rig = SeaRig.place(holder, "Sea_Kelp", KELP.stipe)
	local chain = rig and SeaRig.chain(rig, KELP.bones)
	if rig and chain then
		-- The mesh leans down the current along the street (the canopy streams that way), where the
		-- part-built strand leans the city's one way.
		local along = marker:GetAttribute("Along")
		local flat = if typeof(along) == "Vector3" then Vector3.new(along.X, 0, along.Z) else Vector3.zero
		local current = if flat.Magnitude > 0.01 then flat.Unit else lean
		local canopy = if marker:GetAttribute("Canopy") == true then SeaRig.place(holder, "Sea_KelpCanopy", KELP_HIGH) else nil
		k.lean, k.across = current, Vector3.new(-current.Z, 0, current.X)
		k.height = tall - (if canopy then KELP.canopyDown else KELP.bareDown)
		k.joints = #chain.bones
		k.rig, k.chain, k.canopy = rig, chain, canopy
		local frame = CFrame.fromMatrix(marker.Position, current, Vector3.yAxis) * CFrame.new(-chain.heads[1])
		k.frame = frame
		rig.part.CFrame = frame
		poseKelpMesh(k, os.clock())
		return k
	elseif rig then
		rig.model:Destroy()
	end
	for _ = 1, joints do
		table.insert(k.parts, localPart(holder, "Stipe", Vector3.new(0.45, 0.45, tall / joints + 0.4), KELP_STIPE, false))
	end
	for j = 1, joints do
		local f = j / joints
		if f > 0.3 then
			local sides = if j == joints then { -1, 1 } else { if j % 2 == 0 then 1 else -1 }
			for _, side in ipairs(sides) do
				local long = 3 + f * 1.2
				local blade = localPart(holder, "Blade", Vector3.new(0.08, 1.1 + f * 0.6, long), KELP_LOW:Lerp(KELP_HIGH, f), false)
				table.insert(k.blades, { part = blade, joint = j, side = side, long = long })
				if j % 2 == 0 then
					table.insert(k.floats, { part = localPart(holder, "Float", Vector3.new(0.55, 0.55, 0.55),
						Color3.fromRGB(150, 138, 62), true), joint = j, side = side })
				end
			end
		end
	end
	local moved, frames = {}, {}
	poseKelp(k, os.clock(), moved, frames)
	workspace:BulkMoveTo(moved, frames, Enum.BulkMoveMode.FireCFrameChanged)
	return k
end

local function moveKelp(clock: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local moved, frames = {}, {}
	for marker, k in pairs(kelps) do
		if not marker.Parent then
			kelps[marker] = nil
			continue
		end
		local base = marker.Position
		if (Vector3.new(base.X - eye.X, 0, base.Z - eye.Z)).Magnitude < KELP_NEAR then
			if k.rig then
				poseKelpMesh(k, clock)
			else
				poseKelp(k, clock, moved, frames)
			end
		end
	end
	if #moved > 0 then
		workspace:BulkMoveTo(moved, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- ===== THE WATER, THE LIGHTS AND THE BELL =====

local function moveSurface(clock: number)
	for plate, ripples in pairs(surfacePlates) do
		if not plate.Parent then
			surfacePlates[plate] = nil
			continue
		end
		-- Two patterns, sliding different ways at different speeds: they interfere, which is what
		-- makes it read as ripples rather than as a texture scrolling past. Faster in the rain.
		local pace = 1 + 1.5 * rain
		local first, second = ripples[1], ripples[2]
		if first then
			first.OffsetStudsU = clock * 1.1 * pace
			first.OffsetStudsV = clock * 0.7 * pace
		end
		if second then
			second.OffsetStudsU = -clock * 0.45 * pace
			second.OffsetStudsV = clock * 0.9 * pace
		end
	end
end

local function moveLights(clock: number)
	-- WINDOWS THAT SHOULD NOT BE LIT. On for a while, off for longer, and now and then a stutter.
	-- Each window is off (0), stuttering (1) or lit (2), and its light and pane are written only when
	-- that changes: they were written every frame, lit or not, which is a property change a frame on
	-- every lit window in the city for nothing.
	for part, lit in pairs(litWindows) do
		if not part.Parent then
			litWindows[part] = nil
			continue
		end
		local want = 0
		if clock >= lit.offAt then
			lit.onAt = clock + 12 + math.random() * 40
			lit.offAt = lit.onAt + 5 + math.random() * 18
		elseif clock >= lit.onAt then
			want = if math.random() < 0.004 then 1 else 2
		end
		if want ~= lit.state then
			lit.state = want
			lit.light.Brightness = if want == 2 then 1.1 elseif want == 1 then 0.11 else 0
			part.Color = if want == 2 then lit.lit else DARK_PANE
		end
	end
	-- THE AVIATION LIGHTS, blinking as they were set to, for nobody.
	local on = (clock % 1.6) < 0.35
	for part, light in pairs(blinks) do
		if part.Parent then
			if light.Enabled ~= on then
				light.Enabled = on
			end
		else
			blinks[part] = nil
		end
	end
	-- THE LANTERNS, which gutter.
	for part, lamp in pairs(lanterns) do
		if not part.Parent then
			lanterns[part] = nil
			continue
		end
		if (part.Position - eyeAt).Magnitude > SEEN.light then
			continue
		end
		local dip = if clock >= lamp.dipAt then 0.25 else 1
		if clock >= lamp.dipAt + 0.25 then
			lamp.dipAt = clock + 18 + math.random() * 40
		end
		lamp.light.Brightness = lamp.base * dip * (0.9 + 0.1 * math.sin(clock * 7 + part.Position.X))
	end
end

-- THE BELL tolls once, on a schedule everyone shares, and swings on its headstock after it. Nobody
-- is up there. Somebody arriving between tolls hears the next one, not a toll on arrival.
local BELL_FIRST, BELL_EVERY = 40, 137
local function stepBell(t: number)
	if t < BELL_FIRST then
		return
	end
	local count = math.floor((t - BELL_FIRST) / BELL_EVERY)
	local since = (t - BELL_FIRST) - count * BELL_EVERY
	local toll = tolled ~= nil and count ~= tolled
	tolled = count
	for part, bell in pairs(bells) do
		if not part.Parent then
			bells[part] = nil
			continue
		end
		if toll then
			-- The strike, and the note after it, ringing on across the water.
			longSound(part, THUD_SOUND, 0.3, 1, 700)
			local note = longSound(part, PING_SOUND, 0.26, 1.1, 900)
			local echo = Instance.new("ReverbSoundEffect")
			echo.DecayTime = 8
			echo.Parent = note
		end
		local swing = if since < 9 then math.sin(since * 2.4) * 0.35 * (1 - since / 9) else 0
		part.CFrame = bell.hang * CFrame.Angles(swing, 0, 0) * bell.hang:Inverse() * bell.rest
	end
end

-- STRANGE SOUNDS, now and then, from somewhere out in the city: a long moan under the water, metal
-- giving, masonry letting go, something large breathing out. Each one from a real place a few hundred
-- studs off, so it comes FROM somewhere.
local function stepStrange(clock: number, at: Vector3?)
	if nextStrange == 0 then
		nextStrange = clock + 15
	end
	if clock < nextStrange or not at then
		return
	end
	nextStrange = clock + 22 + math.random() * 35
	local a = math.random() * math.pi * 2
	local reach = 150 + math.random() * 250
	local host = localPart(workspace, "Strange", Vector3.new(1, 1, 1), BODY, false)
	host.Transparency = 1
	host.Position = at + Vector3.new(math.cos(a) * reach, -10, math.sin(a) * reach)
	local pick = math.random(1, 4)
	local id = if pick == 1 then WATER_SOUND elseif pick == 2 then THUD_SOUND elseif pick == 3 then CRUMBLE_SOUND
		else BUBBLES_SOUND
	local speed = if pick == 1 then 0.08 + math.random() * 0.04 elseif pick == 2 then 0.2
		elseif pick == 3 then 0.32 else 0.42
	longSound(host, id, speed, 1, 900)
	task.delay(20, function()
		host:Destroy()
	end)
end

-- ===== THE RAIN =====
--
-- On the level's own schedule, the same for everyone: it comes in over five seconds, falls for a
-- minute and a bit, and goes. Streaks round the camera, a hiss, rings on the water round you, the
-- ripples running faster, and the light a step lower -- the step is taken in applyMood with the rest.
local rainHost: Part? = nil
local rainSound: Sound? = nil
local rainRings: { { part: BasePart, born: number } } = {}
local nextRing = 0

local function raining(t: number): boolean
	local model = seaModel
	if not model then
		return false
	end
	local first, every, length = model:GetAttribute("RainFirst"), model:GetAttribute("RainEvery"),
		model:GetAttribute("RainLength")
	if typeof(first) ~= "number" or typeof(every) ~= "number" or typeof(length) ~= "number" or t < first then
		return false
	end
	return ((t - first) % every) < length
end

local function stepRain(t: number, dt: number, clock: number, at: Vector3?)
	rain = ease(rain, if raining(t) then 1 else 0, 0.2, dt)
	for index = #rainRings, 1, -1 do
		local r = rainRings[index]
		local u = (clock - r.born) / 0.9
		if u >= 1 then
			r.part:Destroy()
			table.remove(rainRings, index)
		else
			r.part.Size = Vector3.new(0.1, 0.6 + u * 3.4, 0.6 + u * 3.4)
			r.part.Transparency = 0.6 + 0.4 * u
		end
	end
	if rain <= 0.001 then
		if rainHost then
			rainHost:Destroy()
			rainHost = nil
		end
		if rainSound then
			rainSound:Destroy()
			rainSound = nil
		end
		return
	end
	if not rainHost then
		local host = localPart(workspace, "Rain", Vector3.new(160, 1, 160), BODY, false)
		host.Transparency = 1
		local drops = Instance.new("ParticleEmitter")
		drops.Name = "Drops"
		drops.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		drops.Color = ColorSequence.new(Color3.fromRGB(206, 222, 224))
		drops.Size = NumberSequence.new(0.18)
		drops.Squash = NumberSequence.new(2.5)
		drops.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.6) })
		drops.Lifetime = NumberRange.new(0.8, 1.1)
		drops.Speed = NumberRange.new(70, 90)
		drops.EmissionDirection = Enum.NormalId.Bottom
		drops.SpreadAngle = Vector2.new(4, 4)
		drops.Rate = 0
		drops.Parent = host
		rainHost = host
		local hiss = Instance.new("Sound")
		hiss.SoundId = RAIN_SOUND
		hiss.Looped = true
		hiss.PlaybackSpeed = 1.4
		hiss.Volume = 0
		hiss.Parent = SoundService
		hiss:Play()
		rainSound = hiss
	end
	local host = rainHost :: Part
	local camera = workspace.CurrentCamera
	if camera then
		host.CFrame = CFrame.new(camera.CFrame.Position + Vector3.new(0, 40, 0))
	end
	local drops = host:FindFirstChild("Drops")
	if drops and drops:IsA("ParticleEmitter") then
		drops.Rate = 700 * rain
	end
	if rainSound then
		rainSound.Volume = 0.22 * rain
	end
	-- Rings on the water round you, a few at a time.
	local b = brief
	if at and b and clock >= nextRing and rain > 0.5 then
		nextRing = clock + 0.12
		local spot = Vector3.new(at.X + (math.random() - 0.5) * 60, b.waterY + 0.15, at.Z + (math.random() - 0.5) * 60)
		local ring = localPart(workspace, "RainRing", Vector3.new(0.1, 0.6, 0.6), Color3.fromRGB(226, 238, 236), false)
		ring.Shape = Enum.PartType.Cylinder
		ring.CFrame = CFrame.new(spot) * CFrame.Angles(0, 0, math.pi / 2)
		ring.Transparency = 0.6
		table.insert(rainRings, { part = ring, born = clock })
	end
end

-- ===== THE THING ON THE HORIZON =====
--
-- Once every few minutes, far out past the city, something comes up. Its back breaks the surface as a
-- line of dark hills three quarters of a kilometre long, water sheets off it, it breathes out, it
-- lies there, and it goes down again. You hear it first. It does not come near, and nothing about it
-- is explained, and that is the whole of it.
local LEVIATHAN_SEGMENTS = 16
local RISE, HOLD, SINK = 9, 12, 10
local leviathan: { holder: Folder, parts: { BasePart }, fins: { BasePart }, spray: ParticleEmitter, index: number }? = nil

local function clearLeviathan()
	local current = leviathan
	if current then
		current.holder:Destroy()
	end
	leviathan = nil
end

local function stepLeviathan(t: number)
	local model = seaModel
	local b = brief
	if not (model and b) then
		clearLeviathan()
		return
	end
	local from, to = model:GetAttribute("LeviathanFrom"), model:GetAttribute("LeviathanTo")
	local first, every = model:GetAttribute("LeviathanFirst"), model:GetAttribute("LeviathanEvery")
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" or typeof(first) ~= "number" or typeof(every) ~= "number"
		or t < first then
		clearLeviathan()
		return
	end
	local index = math.floor((t - first) / every)
	local into = (t - first) - index * every
	if into > RISE + HOLD + SINK then
		clearLeviathan()
		return
	end
	local current = leviathan
	if not current or current.index ~= index then
		clearLeviathan()
		local holder = Instance.new("Folder")
		holder.Name = "FarThing"
		holder.Parent = workspace
		local parts, fins = {}, {}
		for segment = 1, LEVIATHAN_SEGMENTS do
			local share = (segment - 1) / (LEVIATHAN_SEGMENTS - 1)
			local girth = 40 + 100 * math.sin(math.pi * (0.1 + 0.8 * share))
			table.insert(parts, localPart(holder, "FarBack", Vector3.new(girth, girth * 0.55, 80), BODY, true))
			if segment % 4 == 2 then
				table.insert(fins, localPart(holder, "FarFin", Vector3.new(4, girth * 0.45, girth * 0.6), BODY, false))
			end
		end
		local spray = Instance.new("ParticleEmitter")
		spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
		spray.Color = ColorSequence.new(Color3.fromRGB(226, 236, 234))
		spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(1, 46) })
		spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		spray.Lifetime = NumberRange.new(3, 5)
		spray.Speed = NumberRange.new(40, 60)
		spray.EmissionDirection = Enum.NormalId.Top
		spray.SpreadAngle = Vector2.new(12, 12)
		spray.Rate = 0
		spray.Parent = parts[math.floor(LEVIATHAN_SEGMENTS / 2)]
		current = { holder = holder, parts = parts, fins = fins, spray = spray, index = index }
		leviathan = current
		-- YOU HEAR IT FIRST: a moan the whole city hears at once, pitched down to where it is felt more
		-- than heard, and a second, lower, after it. Only when it is starting -- arriving halfway
		-- through, you see it without the call.
		if into < 2 then
			longSound(SoundService, WATER_SOUND, 0.07, 1.2)
			task.delay(1.5, function()
				longSound(SoundService, WATER_SOUND, 0.05, 0.9)
			end)
		end
	end
	local live = current :: any
	-- Every segment faces the way the whole back runs. Facing `to` itself would leave the last one
	-- looking at its own position, which is no direction at all.
	local run = Vector3.new((to :: Vector3).X - (from :: Vector3).X, 0, (to :: Vector3).Z - (from :: Vector3).Z).Unit
	local lift = if into < RISE then into / RISE elseif into < RISE + HOLD then 1 else 1 - (into - RISE - HOLD) / SINK
	lift = lift * lift * (3 - 2 * lift)
	for segment, part in ipairs(live.parts) do
		local share = (segment - 1) / (LEVIATHAN_SEGMENTS - 1)
		local along = (from :: Vector3):Lerp(to :: Vector3, share)
		local arch = math.sin(math.pi * share)
		-- Wholly under by twenty studs at rest; at the top, a third of its height out at the middle
		-- of the back and less toward the ends, like the line of a range of hills.
		local top = b.waterY - part.Size.Y * 0.5 - 20 + (20 + part.Size.Y * 0.35) * lift * (0.35 + 0.65 * arch)
		local at = Vector3.new(along.X, top, along.Z)
		part.CFrame = CFrame.lookAt(at, at + run)
	end
	for fin, part in ipairs(live.fins) do
		local host = live.parts[fin * 4 - 2]
		if host then
			part.CFrame = host.CFrame * CFrame.new(0, host.Size.Y * 0.45 + part.Size.Y * 0.35, 0)
		end
	end
	-- IT BREATHES OUT, once, at the top.
	live.spray.Rate = if into > RISE and into < RISE + 2.5 then 30 else 0
end


-- ===== THE FLOOD =====
--
-- When the glass goes (SunkenCityService writes `Flood` and `FloodAt` on the model), every client
-- sees the same thing: the pane bursts inward in shards, a jet of water comes through the hole, and
-- the tower, the tunnel and the gallery fill to the top over the time the server gives it. Inside
-- the water the view goes green and soft. The server washes everyone out once it is up; when it
-- writes `Flood` back to 0 the water goes down again.
local floodVolumes: { BasePart } = {}
type FloodWater = { part: Part, volume: BasePart, axis: number, sign: number }
local floodWater: { FloodWater } = {}
local floodBegan = 0
local floodDrainFrom = 0
local floodBlur: BlurEffect? = nil
local shards: { { part: BasePart, velocity: Vector3, spin: Vector3, born: number } } = {}
local FLOOD_RISE, FLOOD_DRAIN = 3.5, 4

-- Which of a part's own axes is nearest to world up, and whether it points up or down: a volume
-- can be a box standing up or a cylinder lying on its side stood on end.
local function upAxis(part: BasePart): (number, number)
	local best, sign, most = 2, 1, -1
	for axis, v in ipairs({ part.CFrame.RightVector, part.CFrame.UpVector, -part.CFrame.LookVector }) do
		local d = v:Dot(Vector3.yAxis)
		if math.abs(d) > most then
			best, sign, most = axis, if d >= 0 then 1 else -1, math.abs(d)
		end
	end
	return best, sign
end

local function setWater(w: FloodWater, share: number)
	local size = w.volume.Size
	local full = if w.axis == 1 then size.X elseif w.axis == 2 then size.Y else size.Z
	local h = math.max(0.05, full * share)
	local offset = (-full / 2 + h / 2) * w.sign
	if w.axis == 1 then
		w.part.Size = Vector3.new(h, size.Y, size.Z)
		w.part.CFrame = w.volume.CFrame * CFrame.new(offset, 0, 0)
	elseif w.axis == 2 then
		w.part.Size = Vector3.new(size.X, h, size.Z)
		w.part.CFrame = w.volume.CFrame * CFrame.new(0, offset, 0)
	else
		w.part.Size = Vector3.new(size.X, size.Y, h)
		w.part.CFrame = w.volume.CFrame * CFrame.new(0, 0, offset)
	end
end

local function clearFlood()
	for _, w in ipairs(floodWater) do
		w.part:Destroy()
	end
	floodWater = {}
	floodDrainFrom = 0
	for _, shard in ipairs(shards) do
		shard.part:Destroy()
	end
	shards = {}
	if floodBlur then
		floodBlur:Destroy()
		floodBlur = nil
	end
	drowning = 0
end

local function startFlood(model: Instance)
	clearFlood()
	for _, volume in ipairs(floodVolumes) do
		if volume.Parent and volume:IsDescendantOf(model) and volume:IsA("Part") then
			local axis, sign = upAxis(volume)
			local water = localPart(workspace, "FloodWater", Vector3.new(1, 1, 1), Color3.fromRGB(56, 116, 118), false)
			water.Shape = volume.Shape
			water.Transparency = 0.4
			local w: FloodWater = { part = water, volume = volume, axis = axis, sign = sign }
			setWater(w, 0)
			table.insert(floodWater, w)
		end
	end
	floodBegan = os.clock()
	local at = model:GetAttribute("FloodAt")
	if typeof(at) ~= "Vector3" then
		return
	end
	-- Inward: toward the middle of the nearest of the spaces that flood.
	local inward = Vector3.xAxis
	local gap = math.huge
	for _, w in ipairs(floodWater) do
		local d = (w.volume.Position - at).Magnitude
		if d < gap then
			gap = d
			local flat = Vector3.new(w.volume.Position.X - at.X, 0, w.volume.Position.Z - at.Z)
			inward = if flat.Magnitude > 0.1 then flat.Unit else Vector3.xAxis
		end
	end
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - at).Magnitude < 160 then
		longSound(SoundService, CRUMBLE_SOUND, 1.3, 1.1)
		longSound(SoundService, WATER_SOUND, 0.45, 1.3)
		longSound(SoundService, THUD_SOUND, 0.35, 1)
	end
	for _ = 1, 16 do
		local shard = localPart(workspace, "Shard", Vector3.new(0.1 + math.random() * 0.1, 0.5 + math.random() * 0.9,
			0.4 + math.random() * 0.7), Color3.fromRGB(200, 230, 232), false)
		shard.Transparency = 0.35
		shard.CFrame = CFrame.new(at + Vector3.new((math.random() - 0.5) * 3, (math.random() - 0.5) * 3, (math.random() - 0.5) * 3))
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		table.insert(shards, { part = shard, velocity = inward * (14 + math.random() * 12)
			+ Vector3.new((math.random() - 0.5) * 8, math.random() * 6, (math.random() - 0.5) * 8),
			spin = Vector3.new(math.random() * 8, math.random() * 8, math.random() * 8), born = os.clock() })
	end
	-- The jet, through the hole, for as long as the water is coming up.
	local jet = localPart(workspace, "Jet", Vector3.new(1, 1, 1), BODY, false)
	jet.Transparency = 1
	jet.CFrame = CFrame.lookAt(at, at + inward)
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(206, 234, 232))
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4.5) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.5, 0.8)
	spray.Speed = NumberRange.new(28, 40)
	spray.EmissionDirection = Enum.NormalId.Front
	spray.SpreadAngle = Vector2.new(12, 12)
	spray.Acceleration = Vector3.new(0, -20, 0)
	spray.Rate = 140
	spray.Parent = jet
	task.delay(FLOOD_RISE + 1.5, function()
		jet:Destroy()
	end)
end

local function stepFlood(clock: number, dt: number)
	if #floodWater > 0 then
		local share
		if floodDrainFrom > 0 then
			share = 1 - (clock - floodDrainFrom) / FLOOD_DRAIN
			if share <= 0 then
				clearFlood()
				return
			end
		else
			share = math.min(1, (clock - floodBegan) / FLOOD_RISE)
		end
		share = share * share * (3 - 2 * share)
		for _, w in ipairs(floodWater) do
			setWater(w, share)
		end
	end
	for index = #shards, 1, -1 do
		local shard = shards[index]
		if clock - shard.born > 2 then
			shard.part:Destroy()
			table.remove(shards, index)
		else
			-- Sinking through water, not falling through air: heavy drag, light gravity.
			shard.velocity = (shard.velocity + Vector3.new(0, -14 * dt, 0)) * (1 - math.min(0.9, 2.2 * dt))
			shard.part.CFrame = (shard.part.CFrame + shard.velocity * dt)
				* CFrame.Angles(shard.spin.X * dt, shard.spin.Y * dt, shard.spin.Z * dt)
		end
	end
	-- INSIDE THE WATER: the view goes green and soft.
	local under = false
	local camera = workspace.CurrentCamera
	if camera then
		local eye = camera.CFrame.Position
		for _, w in ipairs(floodWater) do
			local p = w.part.CFrame:PointToObjectSpace(eye)
			local half = w.part.Size / 2
			if math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z then
				under = true
			end
		end
	end
	drowning = ease(drowning, if under then 1 else 0, 2.5, dt)
	if drowning > 0.01 then
		local blur = floodBlur
		if not blur then
			local made = Instance.new("BlurEffect")
			made.Name = "SunkenFloodBlur"
			made.Parent = Lighting
			floodBlur = made
			blur = made
		end
		if blur then
			blur.Size = 12 * drowning
		end
	elseif floodBlur then
		floodBlur:Destroy()
		floodBlur = nil
	end
end

-- ===== WHAT LOOKS IN AT THE WINDOW =====
--
-- Past the gallery's window is open water and the dark under it. Every so often, on a schedule
-- every player shares, something comes up out of that dark: a head as wide as the gallery, with one
-- pale eye, rising slowly until the eye is level with the window, holding there, and sinking away.
-- It is drawn only for someone near enough to see it. It never comes closer than its own length.
local deepWindows: { BasePart } = {}
local deepThing: { holder: Folder, head: BasePart, eye: BasePart, pupil: BasePart, feelers: { BasePart }, index: number }? = nil
local DEEP_FIRST, DEEP_EVERY = 45, 110
local DEEP_RISE, DEEP_HOLD, DEEP_SINK = 7, 5, 7
local DEEP_OUT, DEEP_DOWN = 62, 50 -- its face stays behind the kelp past the window

local function clearDeep()
	local current = deepThing
	if current then
		current.holder:Destroy()
	end
	deepThing = nil
end

local function stepDeep(t: number, clock: number, at: Vector3?)
	local window = deepWindows[1]
	if not window or not window.Parent or not at or (at - window.Position).Magnitude > 90 or t < DEEP_FIRST then
		clearDeep()
		return
	end
	local index = math.floor((t - DEEP_FIRST) / DEEP_EVERY)
	local into = (t - DEEP_FIRST) - index * DEEP_EVERY
	if into > DEEP_RISE + DEEP_HOLD + DEEP_SINK then
		clearDeep()
		return
	end
	-- Out of the gallery: the window's thin axis, turned away from the nearest space that floods.
	local out = window.CFrame.RightVector
	local nearest, gap = nil, math.huge
	for _, volume in ipairs(floodVolumes) do
		local d = (volume.Position - window.Position).Magnitude
		if volume.Parent and d < gap then
			nearest, gap = volume, d
		end
	end
	if nearest and (window.Position - nearest.Position):Dot(out) < 0 then
		out = -out
	end
	local current = deepThing
	if not current or current.index ~= index then
		clearDeep()
		local holder = Instance.new("Folder")
		holder.Name = "DeepThing"
		holder.Parent = workspace
		local head = localPart(holder, "DeepHead", Vector3.new(22, 16, 26), BODY, true)
		local eye = localPart(holder, "DeepEye", Vector3.new(4.4, 4.4, 1.6), Color3.fromRGB(206, 212, 170), true)
		local pupil = localPart(holder, "DeepPupil", Vector3.new(0.7, 3.4, 0.3), Color3.fromRGB(10, 10, 12), false)
		local feelers = {}
		for _ = 1, 3 do
			table.insert(feelers, localPart(holder, "DeepFeeler", Vector3.new(0.8, 14, 0.8), BODY, true))
		end
		current = { holder = holder, head = head, eye = eye, pupil = pupil, feelers = feelers, index = index }
		deepThing = current
		if into < 2 then
			longSound(head, WATER_SOUND, 0.09, 1.1, 220)
		end
	end
	local live = current :: any
	local lift = if into < DEEP_RISE then into / DEEP_RISE elseif into < DEEP_RISE + DEEP_HOLD then 1
		else 1 - (into - DEEP_RISE - DEEP_HOLD) / DEEP_SINK
	lift = lift * lift * (3 - 2 * lift)
	local pos = window.Position + out * DEEP_OUT + Vector3.new(math.sin(clock * 0.3) * 1.5, -DEEP_DOWN * (1 - lift) + 1, 0)
	local head = CFrame.lookAt(pos, pos - out)
	live.head.CFrame = head
	live.eye.CFrame = head * CFrame.new(3, 2.5, -12.6)
	live.pupil.CFrame = live.eye.CFrame * CFrame.new(0, 0, -0.75)
	for index, feeler in ipairs(live.feelers) do
		feeler.CFrame = head * CFrame.new((index - 2) * 5, -7, -6) * CFrame.Angles(math.sin(clock * 0.8 + index) * 0.25, 0,
			math.cos(clock * 0.6 + index) * 0.2) * CFrame.new(0, -7, 0)
	end
end

-- Leaving the level takes the weather and the far thing with it.
local function clearWeather()
	clearLeviathan()
	clearFlood()
	clearDeep()
	rain = 0
	tolled = nil
	if rainHost then
		rainHost:Destroy()
		rainHost = nil
	end
	if rainSound then
		rainSound:Destroy()
		rainSound = nil
	end
	for _, r in ipairs(rainRings) do
		r.part:Destroy()
	end
	rainRings = {}
end

-- ===== EVERY FRAME =====

local function moveSmallThings(clock: number)
	for model, ring in pairs(rings) do
		if model.Parent and (ring.centre - eyeAt).Magnitude < SEEN.harbour then
			local turn = CFrame.new(ring.centre) * CFrame.Angles(0, -ring.spin * clock, 0) * CFrame.new(ring.centre):Inverse()
			model:PivotTo(turn * ring.rest)
		end
	end
	for model, buoy in pairs(buoys) do
		if model.Parent and (buoy.rest.Position - eyeAt).Magnitude < SEEN.harbour then
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
	-- THE SHOALS. Round their marker, bobbing, each fish out of step with the next -- and, for a few
	-- seconds after somebody taps the glass, BOLTING: the ring opens out and the speed doubles, then
	-- it settles back. That is what the notice on the gallery wall is about.
	local startled = math.max(0, scatterUntil - clock)
	local bolt = if startled > 0 then startled / 2.5 else 0
	-- The mesh fish are moved together (BulkMoveTo), which is far cheaper than one CFrame at a time.
	local moved: { BasePart }, frames: { CFrame } = {}, {}
	for marker, shoal in pairs(shoals) do
		if marker.Parent and (marker.Position - eyeAt).Magnitude < SEEN.water + shoal.radius then
			-- A shoal in the street goes round a loop laid along it and is nowhere near the glass,
			-- so only the aquarium's shoals bolt when it is tapped.
			local along = shoal.along
			local startle = if along then 0 else bolt
			local rigs = shoal.rigs
			local count = if rigs then #rigs else #shoal.fish
			local radius = shoal.radius * (1 + startle * 0.8)
			local speed = shoal.speed * (1 + startle * 2.2)
			local side = if along then Vector3.new(-along.Z, 0, along.X) else Vector3.zAxis
			local run = along or Vector3.xAxis
			for index = 1, count do
				local a = clock * speed + index * 2 * math.pi / count + shoal.phase
				local wobble = 1 + 0.15 * math.sin(a * 3 + index)
				local rise = 1.2 * math.sin(clock * 0.8 + index) + startle * 3 * math.sin(index * 1.7)
				local here = marker.Position + run * (math.cos(a) * radius * wobble) + side * (math.sin(a) * radius * 0.6)
					+ Vector3.new(0, rise, 0)
				local ahead = marker.Position + run * (math.cos(a + 0.1) * radius * wobble) + side * (math.sin(a + 0.1) * radius * 0.6)
					+ Vector3.new(0, rise, 0)
				local rig = rigs and rigs[index]
				if rig then
					-- A mesh fish beats its tail, faster when it bolts.
					table.insert(moved, rig.part)
					table.insert(frames, CFrame.lookAt(here, ahead))
					SeaRig.bend(rig, "Tail", SeaRig.UP, 0.45 * math.sin(clock * (7 + startle * 6) + index))
				else
					shoal.fish[index]:PivotTo(CFrame.lookAt(here, ahead) * CFrame.Angles(0, 0, math.sin(clock * 6 + index) * 0.2))
				end
			end
		end
	end
	if #moved > 0 then
		workspace:BulkMoveTo(moved, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- THE THINGS AT THE BACK, turning on their own long circles out in the haze.
	for marker, horror in pairs(horrors) do
		if marker.Parent then
			local a = clock * horror.speed + horror.phase
			local centre = marker.Position
			for index, piece in ipairs(horror.body) do
				local isFin = index > HORROR_SEGMENTS
				local behind = (if isFin then 3 else index - 1) * (horror.long / HORROR_SEGMENTS)
				local back = a - behind / math.max(1, horror.radius)
				local here = centre + Vector3.new(math.cos(back) * horror.radius, 2 * math.sin(clock * 0.15 + index),
					math.sin(back) * horror.radius)
				local ahead = centre + Vector3.new(math.cos(back + 0.05) * horror.radius, 0, math.sin(back + 0.05) * horror.radius)
				local frame = CFrame.lookAt(here, Vector3.new(ahead.X, here.Y, ahead.Z))
				piece.CFrame = if isFin then frame * CFrame.new(0, horror.long * 0.07, 0) else frame
			end
		end
	end
	-- THE CAUSTICS, sliding and breathing: the light off a surface that is never still.
	for part, caustic in pairs(caustics) do
		if part.Parent and (caustic.rest.Position - eyeAt).Magnitude < SEEN.light then
			local drift = caustic.drift
			part.CFrame = caustic.rest * CFrame.new(math.sin(clock * 0.3 + caustic.phase) * drift, 0,
				math.cos(clock * 0.22 + caustic.phase * 1.3) * drift)
			part.Transparency = caustic.base + 0.1 * math.sin(clock * 0.9 + caustic.phase)
		end
	end
	-- THE SHAFTS of light, leaning as the surface above them moves.
	for part, shaft in pairs(shaftsSeen) do
		if part.Parent and (shaft.rest.Position - eyeAt).Magnitude < SEEN.light then
			part.CFrame = shaft.rest * CFrame.Angles(math.sin(clock * 0.16 + shaft.phase) * 0.05, 0,
				math.cos(clock * 0.13 + shaft.phase) * 0.05)
		end
	end
	-- THE LIGHTHOUSE, turning: its light comes round to you once every few seconds and goes again,
	-- which is the whole of what a lighthouse is.
	for part, beacon in pairs(beacons) do
		if part.Parent then
			local sweep = (math.sin(clock * 0.7) + 1) / 2
			beacon.light.Brightness = beacon.base * (0.25 + 1.5 * sweep ^ 3)
			part.Transparency = 0.45 - 0.3 * sweep ^ 3
		end
	end
	-- AND THE LAMP AT THE BOTTOM OF THE DRAIN, which stutters now and then and comes back.
	for part, fitting in pairs(sluiceLamps) do
		if part.Parent and clock >= fitting.nextFlicker then
			fitting.nextFlicker = clock + 4 + math.random() * 9
			task.spawn(function()
				for _ = 1, math.random(2, 4) do
					fitting.light.Brightness = fitting.base * 0.15
					task.wait(0.05 + math.random() * 0.06)
					fitting.light.Brightness = fitting.base
					task.wait(0.06 + math.random() * 0.1)
				end
			end)
		end
	end
	-- AND THE TANK'S LAYERS, which breathe so the water outside the glass is never a still pane --
	-- seen only from inside the aquarium, so only written while you are in it.
	for part, pane in pairs(tankPanes) do
		if part.Parent and inside > 0.01 then
			part.Transparency = math.clamp(pane.base + 0.012 * math.sin(clock * 0.5 + pane.phase), 0, 1)
		end
	end
end

-- The thing under the route and the mood it makes, which only exist once the sea's brief has come.
local function thingFrame(b: SunkenPath.Brief, now: number, at: Vector3?, dt: number)
	findWater()
	local t = now - b.epoch
	local nearest = moveThing(b, t, at)
	stepSurfacing(b, t)
	local target = math.clamp((FAR - nearest) / (FAR - NEAR), 0, 1)
	nearness = ease(nearness, target, 0.8, dt)
	inside = ease(inside, if at and inZone(at) then 1 else 0, 1.5, dt)
	applyMood()
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if camera then
		eyeAt = camera.CFrame.Position
	end
	local now = workspace:GetServerTimeNow()
	guard("the ride down the drain", moveRider, now)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local at: Vector3? = if root and root:IsA("BasePart") then root.Position else nil

	local b = brief
	if b and (#segments > 0 or thingMesh) then
		guard("the thing under the route", thingFrame, b, now, at, dt)
	end
	local clock = os.clock()
	guard("the whirlpool, buoys, clock, shoals and the things at the back", moveSmallThings, clock)
	guard("the swimmers", moveSwimmers, clock)
	guard("the kelp", moveKelp, clock)
	guard("the gulls", moveGulls, clock)
	guard("the whirlpool's water", moveWhirlFlow, clock)
	guard("the Ferris wheel", moveFerris)
	guard("the water's surface", moveSurface, clock)
	guard("the lights", moveLights, clock)
	guard("the flood", stepFlood, clock, dt)
	if b then
		local t = now - b.epoch
		guard("the bell", stepBell, t)
		guard("the rain", stepRain, t, dt, clock, at)
		guard("the thing on the horizon", stepLeviathan, t)
		guard("the strange sounds", stepStrange, clock, at)
		guard("what looks in at the window", stepDeep, t, clock, at)
	elseif leviathan or rainHost or tolled ~= nil or #floodWater > 0 or deepThing then
		guard("clearing up the level", clearWeather)
	end
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

-- A REPORT, ten seconds after the level is up, of what this client is actually drawing: the line to
-- look for in Output when something that should move does not.
local function reportLater(model: Instance)
	task.delay(10, function()
		if not model.Parent then
			return
		end
		local function count(set: { [any]: any }): number
			local n = 0
			for _ in pairs(set) do
				n += 1
			end
			return n
		end
		local broken = {}
		for name in pairs(failures) do
			table.insert(broken, name)
		end
		print(("SunkenCityClient: drawing the thing (%s), %d swimmers, %d shoals, %d strands of kelp, %d gulls, "
			.. "%d whirlpool rings, %d turning pieces of the Ferris wheel; %s; %s"):format(
			if thingMesh then "the serpent mesh" else #segments .. " pieces", count(swimmers),
			count(shoals), count(kelps), count(gulls), count(rings), count(ferris),
			if #broken == 0 then "nothing has failed" else "FAILED: " .. table.concat(broken, ", "), SeaRig.summary()))
	end)
end

function SunkenCityClient.start()
	track("SunkenSea", function(model: Instance)
		reportLater(model)
		seaArrived(model)
	end, seaLeft)
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
		local long = item:GetAttribute("Length")
		local phase = item:GetAttribute("Phase")
		local holder = Instance.new("Folder")
		holder.Name = "Shoal"
		holder.Parent = workspace
		local fish = {}
		local many = if typeof(count) == "number" then count else 8
		local size = if typeof(long) == "number" then long else 1
		local pick = if typeof(phase) == "number" then math.floor(phase) % #FISH_COLOURS + 1 else 1
		-- The street's shoals are drawn big, to be seen from the route through the water: the large
		-- fish mesh for them, the small one for the tank's and the flat's.
		local meshName = if size >= 1.8 then "Sea_FishLarge" else "Sea_Fish"
		local rigs: { SeaRig.Rig }? = nil
		if SeaRig.template(meshName) then
			local made = {}
			for index = 1, many do
				local rig = SeaRig.place(holder, meshName, FISH_COLOURS[pick][if index % 4 == 0 then 2 else 1])
				if rig then
					table.insert(made, rig)
				end
			end
			rigs = made
		else
			for index = 1, many do
				table.insert(fish, makeFish(holder, index, size, FISH_COLOURS[pick]))
			end
		end
		local along = item:GetAttribute("Along")
		shoals[item] = { fish = fish, rigs = rigs, holder = holder, radius = if typeof(radius) == "number" then radius else 10,
			speed = if typeof(speed) == "number" then speed else 0.4,
			phase = if typeof(phase) == "number" then phase else 0,
			along = if typeof(along) == "Vector3" then along else nil }
		item.Destroying:Connect(function()
			holder:Destroy()
		end)
	end, function(item)
		if item:IsA("BasePart") then
			local shoal = shoals[item]
			if shoal then
				shoal.holder:Destroy()
			end
			shoals[item] = nil
		end
	end)
	track("SunkenHorror", function(item)
		if not item:IsA("BasePart") then
			return
		end
		local long = item:GetAttribute("Length")
		local radius = item:GetAttribute("Radius")
		local speed = item:GetAttribute("Speed")
		local phase = item:GetAttribute("Phase")
		local holder = Instance.new("Folder")
		holder.Name = "Back"
		holder.Parent = workspace
		horrors[item] = {
			body = makeHorror(holder, if typeof(long) == "number" then long else 40),
			long = if typeof(long) == "number" then long else 40,
			radius = if typeof(radius) == "number" then radius else 160,
			speed = if typeof(speed) == "number" then speed else 0.04,
			phase = if typeof(phase) == "number" then phase else 0,
			holder = holder,
		}
	end, function(item)
		local entry = horrors[item :: any]
		if entry then
			entry.holder:Destroy()
			horrors[item :: any] = nil
		end
	end)
	track("SunkenBeacon", function(item)
		if item:IsA("BasePart") then
			local light = item:FindFirstChildOfClass("PointLight")
			if light then
				beacons[item] = { light = light, base = light.Brightness }
			end
		end
	end, function(item)
		beacons[item :: any] = nil
	end)
	track("SunkenSluiceLamp", function(item)
		if item:IsA("BasePart") then
			local light = item:FindFirstChildOfClass("PointLight")
			if light then
				sluiceLamps[item] = { light = light, base = light.Brightness, nextFlicker = os.clock() + 3 }
			end
		end
	end, function(item)
		sluiceLamps[item :: any] = nil
	end)
	track("SunkenSwimmer", function(item)
		if not item:IsA("BasePart") then
			return
		end
		local kind = item:GetAttribute("Kind")
		local range, speed = item:GetAttribute("Range"), item:GetAttribute("Speed")
		local across = item:GetAttribute("Across")
		local bob = item:GetAttribute("Bob")
		local clear = item:GetAttribute("Clear") == true
		local phase, along = item:GetAttribute("Phase"), item:GetAttribute("Along")
		local holder = Instance.new("Folder")
		holder.Name = "Swimmer"
		holder.Parent = workspace
		local name = if typeof(kind) == "string" then kind else "grouper"
		local rigs, shell = makeSwimmerMesh(holder, name, clear)
		swimmers[item] = {
			kind = name,
			holder = holder,
			rigs = rigs,
			shell = shell,
			parts = if rigs then {} else makeSwimmer(holder, name, SWIMMER_SCALE[name] or 1, clear),
			scale = SWIMMER_SCALE[name] or 1,
			bob = if typeof(bob) == "number" then bob else 3,
			marker = item,
			range = if typeof(range) == "number" then range else 20,
			across = if typeof(across) == "number" then across else 10,
			speed = if typeof(speed) == "number" then speed else 1,
			phase = if typeof(phase) == "number" then phase else 0,
			along = if typeof(along) == "Vector3" then along else Vector3.new(0, 0, 1),
		}
		item.Destroying:Connect(function()
			holder:Destroy()
		end)
	end, function(item)
		if item:IsA("BasePart") then
			local s = swimmers[item]
			if s then
				s.holder:Destroy()
			end
			swimmers[item] = nil
		end
	end)
	track("SunkenGull", function(item)
		if item:IsA("BasePart") and not gulls[item] then
			local holder = Instance.new("Folder")
			holder.Name = "Gull"
			holder.Parent = workspace
			local radius, speed, phase = item:GetAttribute("Radius"), item:GetAttribute("Speed"), item:GetAttribute("Phase")
			-- The mesh gull is two meshes, white body and grey wings; both or neither.
			local wings = if SeaRig.template("Sea_Gull") then SeaRig.place(holder, "Sea_GullWings", Color3.fromRGB(176, 182, 188)) else nil
			local body = if wings then SeaRig.place(holder, "Sea_Gull", Color3.fromRGB(240, 240, 236)) else nil
			gulls[item] = { marker = item, parts = if body then {} else makeGull(holder), holder = holder,
				body = body and body.part, wings = if body then wings else nil,
				radius = if typeof(radius) == "number" then radius else 20,
				speed = if typeof(speed) == "number" then speed else 0.3, phase = if typeof(phase) == "number" then phase else 0 }
			if wings and not body then
				wings.model:Destroy()
			end
		end
	end, function(item)
		if item:IsA("BasePart") then
			local gull = gulls[item]
			if gull then
				gull.holder:Destroy()
			end
			gulls[item] = nil
		end
	end)
	track("SunkenWhirlFlow", function(item)
		local texture = item:FindFirstChildOfClass("Texture")
		local ring = item:GetAttribute("Ring")
		if item:IsA("BasePart") and texture then
			whirlFlow[item] = { texture = texture, ring = if typeof(ring) == "number" then ring else 0 }
		end
	end, function(item)
		if item:IsA("BasePart") then
			whirlFlow[item] = nil
		end
	end)
	track("SunkenKelp", function(item)
		if item:IsA("BasePart") and not kelps[item] then
			kelps[item] = growKelp(item)
		end
	end, function(item)
		if item:IsA("BasePart") then
			local k = kelps[item]
			if k then
				k.holder:Destroy()
			end
			kelps[item] = nil
		end
	end)
	track("SunkenAmbience", function(item)
		local baseVolume = item:GetAttribute("BaseVolume")
		if item:IsA("Sound") and typeof(baseVolume) == "number" then
			ambientSounds[item] = baseVolume
			moodWritten = -1
		end
	end, function(item)
		if item:IsA("Sound") then
			ambientSounds[item] = nil
		end
	end)
	track("SunkenFerris", function(item)
		local axle, spin, epoch = item:GetAttribute("Axle"), item:GetAttribute("Spin"), item:GetAttribute("Epoch")
		local count, radius, hang = item:GetAttribute("Count"), item:GetAttribute("Radius"), item:GetAttribute("Hang")
		local index = item:GetAttribute("Index")
		if typeof(axle) == "CFrame" and typeof(spin) == "number" and typeof(epoch) == "number" then
			ferris[item] = { axle = axle, spin = spin, epoch = epoch,
				index = if typeof(index) == "number" then index else nil,
				count = if typeof(count) == "number" then count else 16,
				radius = if typeof(radius) == "number" then radius else 36,
				hang = if typeof(hang) == "number" then hang else 3 }
		end
	end, function(item)
		ferris[item] = nil
	end)
	track("SunkenFloodVolume", function(item)
		if item:IsA("BasePart") then
			table.insert(floodVolumes, item)
		end
	end, function(item)
		local index = table.find(floodVolumes, item :: any)
		if index then
			table.remove(floodVolumes, index)
		end
	end)
	track("SunkenDeepWindow", function(item)
		if item:IsA("BasePart") then
			table.insert(deepWindows, item)
		end
	end, function(item)
		local index = table.find(deepWindows, item :: any)
		if index then
			table.remove(deepWindows, index)
		end
	end)
	track("SunkenSurface", function(item)
		if item:IsA("BasePart") then
			local list = {}
			for _, child in ipairs(item:GetChildren()) do
				if child:IsA("Texture") then
					table.insert(list, child)
				end
			end
			surfacePlates[item] = list
		end
	end, function(item)
		if item:IsA("BasePart") then
			surfacePlates[item] = nil
		end
	end)
	track("SunkenLitWindow", function(item)
		local light = item:FindFirstChildOfClass("PointLight")
		if item:IsA("BasePart") and light then
			local start = os.clock() + math.random() * 30
			litWindows[item] = { light = light, lit = item.Color, onAt = start, offAt = start + 5 + math.random() * 15, state = 0 }
			item.Color = DARK_PANE
		end
	end, function(item)
		if item:IsA("BasePart") then
			litWindows[item] = nil
		end
	end)
	track("SunkenBlink", function(item)
		local light = item:FindFirstChildOfClass("PointLight")
		if item:IsA("BasePart") and light then
			blinks[item] = light
		end
	end, function(item)
		if item:IsA("BasePart") then
			blinks[item] = nil
		end
	end)
	track("SunkenLantern", function(item)
		local light = item:FindFirstChildOfClass("PointLight")
		if item:IsA("BasePart") and light then
			lanterns[item] = { light = light, base = light.Brightness, dipAt = os.clock() + math.random() * 30 }
		end
	end, function(item)
		if item:IsA("BasePart") then
			lanterns[item] = nil
		end
	end)
	track("SunkenBell", function(item)
		local hang = item:GetAttribute("Hang")
		if item:IsA("BasePart") and typeof(hang) == "CFrame" then
			bells[item] = { rest = item.CFrame, hang = hang }
		end
	end, function(item)
		if item:IsA("BasePart") then
			bells[item] = nil
		end
	end)
	track("SunkenCaustic", function(item)
		if item:IsA("BasePart") then
			local phase = item:GetAttribute("Phase")
			local drift = item:GetAttribute("Drift")
			caustics[item] = { phase = if typeof(phase) == "number" then phase else 0,
				drift = if typeof(drift) == "number" then drift else 3, rest = item.CFrame,
				base = item.Transparency }
		end
	end, function(item)
		caustics[item :: any] = nil
	end)
	track("SunkenShaft", function(item)
		if item:IsA("BasePart") then
			local phase = item:GetAttribute("Phase")
			shaftsSeen[item] = { phase = if typeof(phase) == "number" then phase else 0, rest = item.CFrame }
		end
	end, function(item)
		shaftsSeen[item :: any] = nil
	end)
	track("SunkenTank", function(item)
		if item:IsA("BasePart") then
			local phase = item:GetAttribute("Phase")
			tankPanes[item] = { phase = if typeof(phase) == "number" then phase else 0, base = item.Transparency }
		end
	end, function(item)
		tankPanes[item :: any] = nil
	end)
	-- WHEN SOMEBODY TAPS THE GLASS. The server writes the moment on the level's model; every client
	-- reads it, which is why the fish bolt for everyone in the gallery and not only for whoever
	-- tapped. Watched on the model itself rather than over a remote, because an attribute is
	-- already replicated and this is one number.
	local function watchTaps(model: Instance)
		model:GetAttributeChangedSignal("Tapped"):Connect(function()
			scatterUntil = os.clock() + 2.5
			oneShot(1.3, 0.35)
		end)
		model:GetAttributeChangedSignal("Flood"):Connect(function()
			local value = model:GetAttribute("Flood")
			if typeof(value) == "number" and value > 0 then
				startFlood(model)
			elseif #floodWater > 0 and floodDrainFrom == 0 then
				floodDrainFrom = os.clock()
			end
		end)
	end
	for _, item in ipairs(CollectionService:GetTagged("SunkenSea")) do
		local level = item.Parent
		if level then
			watchTaps(level)
		end
	end
	CollectionService:GetInstanceAddedSignal("SunkenSea"):Connect(function(item)
		local level = item.Parent
		if level then
			watchTaps(level)
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
	local rideEvent = remotes and remotes:WaitForChild("SunkenRide", 20)
	if rideEvent and rideEvent:IsA("RemoteEvent") then
		drainRemote = rideEvent
		rideEvent.OnClientEvent:Connect(drainStarted)
	end
	RunService.RenderStepped:Connect(step)
end

return SunkenCityClient
