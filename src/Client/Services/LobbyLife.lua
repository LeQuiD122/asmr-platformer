--!strict
-- StarterPlayerScripts/Services/LobbyLife.lua
-- THE LOBBY, ALIVE (the hundred-and-ninth pass, from your notes: "greatly improve the vibe and aesthetics of the
-- lobby"). On your own screen only, while you are in the lobby, and nothing of it is sent anywhere:
--
--   SOAP BUBBLES drifting up off the fountain on the breeze, wobbling, catching the light, each a different size;
--   tap one and it pops, with the bubble wrap's own soft pop and a few flecks of film. Walk into one and it pops
--   silently, flecks and no sound; left alone, one goes by itself after a while, without a sound (the hundred-and-
--   eighteenth pass, from your test: they were the random sounds as you walked about the lobby).
--   GULLS wheeling slowly round the promenade, gliding, now and then a few beats of their wings, banking into the turn.
--   FIREFLIES over the garden's lawn, blinking on and off.
--
-- Cheap by design: at most BUBBLES_MAX bubbles, three gulls of four parts each, and one emitter; nothing at all
-- while a level is on (the lobby is put away then) or when you are far from the plaza.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LobbyLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LobbyLayout"))

-- The game's own sound takes (AudioService): the bubble wrap's pops, for a bubble's.
local AudioService: any = (function(): any
	local found = script.Parent and script.Parent:FindFirstChild("AudioService")
	if found and found:IsA("ModuleScript") then
		local ok, loaded = pcall(require, found)
		if ok and type(loaded) == "table" then
			return loaded
		end
	end
	return nil
end)()

local LobbyLife = {}
LobbyLife.VERSION = "hundred-and-ninth pass, 2026-10-21"

local BUBBLES_MAX = 14
local BUBBLE_EVERY = 0.7 -- seconds between one bubble and the next
local BUBBLE_NEAR = 160 -- studs from the fountain: further off, none are blown
local WIND = Vector3.new(1.1, 0, 0.7) -- studs a second, the breeze off the sea
local GULLS = 3
local POP_REACH = 1.6 -- studs past a bubble's own size that your head or body pops it

type Bubble = { part: BasePart, glint: BasePart, born: number, life: number, from: Vector3, rise: number, size: number,
	seed: number }
type Gull = { body: BasePart, head: BasePart, wings: { BasePart }, radius: number, height: number, speed: number,
	phase: number, seed: number }

local folder: Folder? = nil
local anchor: BasePart? = nil -- an invisible part to hang the pops' sounds and flecks on
local fireflies: ParticleEmitter? = nil
local bubbles: { Bubble } = {}
local gulls: { Gull } = {}
local nextBubble = 0
local on = false
local failed = false
local rng = Random.new()

local function hubOrigin(): Vector3
	return LobbyLayout.ORIGIN
end

local function holder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "LobbyLife"
	made.Parent = workspace
	folder = made
	return made
end

local function piece(name: string, size: Vector3, colour: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = size
	p.Color = colour
	p.Material = material
	return p
end

local function anchorPart(): BasePart
	local existing = anchor
	if existing and existing.Parent then
		return existing
	end
	local made = piece("LifeAnchor", Vector3.new(1, 1, 1), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	made.Transparency = 1
	made.Position = hubOrigin() + Vector3.new(0, -20, 0)
	made.Parent = holder()
	anchor = made
	return made
end

-- ===== BUBBLES =====

local function popSound(at: Vector3)
	local takes = if AudioService and AudioService.takesFor then AudioService.takesFor("bubblePop") else {}
	if #takes == 0 or not AudioService.applyTake then
		return
	end
	local spot = Instance.new("Attachment")
	spot.Parent = anchorPart()
	spot.WorldPosition = at
	local s = Instance.new("Sound")
	s.Volume = 0.35
	s.PlaybackSpeed = 0.95 + rng:NextNumber() * 0.12
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 4
	s.RollOffMaxDistance = 40
	AudioService.applyTake(s, takes[rng:NextInteger(1, #takes)])
	s.Parent = spot
	s:Play()
	game:GetService("Debris"):AddItem(spot, 3)
end

local function flecks(at: Vector3, size: number)
	local spot = Instance.new("Attachment")
	spot.Parent = anchorPart()
	spot.WorldPosition = at
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Rate = 0
	burst.Lifetime = NumberRange.new(0.25, 0.5)
	burst.Speed = NumberRange.new(2, 5)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25 * size), NumberSequenceKeypoint.new(1, 0) })
	burst.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	burst.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(214, 226, 255))
	burst.LightEmission = 0.6
	burst.Drag = 4
	burst.Parent = spot
	burst:Emit(7)
	game:GetService("Debris"):AddItem(spot, 1)
end

-- HEARD ONLY WHEN YOU POPPED IT ON PURPOSE (a tap): walked into or gone by itself, it is seen and not heard.
local function pop(index: number, heard: boolean, seen: boolean)
	local b = bubbles[index]
	if heard then
		popSound(b.part.Position)
	end
	if seen then
		flecks(b.part.Position, b.size)
	end
	b.part:Destroy()
	table.remove(bubbles, index)
end

local function blow(fountain: Vector3, now: number)
	if #bubbles >= BUBBLES_MAX then
		return
	end
	-- A SOAP FILM, NOT A GLASS BALL (the hundred-and-twenty-third pass, from your test: "bubbles look weird in the
	-- fountain": as Glass against the sky they were dull grey-blue balls up by the canopy): a thin pale skin you can
	-- almost see through, its colour sliding through the film's pinks, blues, greens and golds, a bright glint of the
	-- sun on its upper side; smaller, and drifting up slowly from just over the water.
	local size = rng:NextNumber(0.45, 1.15)
	local ball = piece("LobbyBubble", Vector3.new(size, size, size), Color3.fromHSV(rng:NextNumber(0, 1), 0.22, 1),
		Enum.Material.SmoothPlastic)
	ball.Shape = Enum.PartType.Ball
	ball.Transparency = 0.78
	ball.Reflectance = 0.3
	local glint = piece("Glint", Vector3.new(size, size, size) * 0.2, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	glint.Shape = Enum.PartType.Ball
	glint.Transparency = 0.2
	local a = rng:NextNumber(0, math.pi * 2)
	local from = fountain + Vector3.new(math.cos(a) * rng:NextNumber(0.5, 2.5), rng:NextNumber(3.2, 4.4), math.sin(a) * rng:NextNumber(0.5, 2.5))
	ball.Position = from
	glint.Position = from
	ball.Parent = holder()
	glint.Parent = ball
	table.insert(bubbles, { part = ball, glint = glint, born = now, life = rng:NextNumber(5, 9), from = from,
		rise = rng:NextNumber(0.45, 0.9), size = size, seed = rng:NextNumber(0, 100) })
end

local function moveBubbles(now: number, body: { Vector3 })
	for index = #bubbles, 1, -1 do
		local b = bubbles[index]
		local age = now - b.born
		if age >= b.life or not b.part.Parent then
			pop(index, false, b.part.Parent ~= nil)
		else
			-- Up, and away on the breeze, wandering; wobbling as it goes, a little bigger as it rises.
			local wander = Vector3.new(math.noise(age * 0.4, b.seed, 0), math.noise(b.seed, age * 0.3, 0) * 0.4,
				math.noise(0, b.seed, age * 0.4)) * 2
			local at = b.from + WIND * age + Vector3.new(0, b.rise * age, 0) + wander
			local wobble = 1 + 0.06 * math.sin(age * 7 + b.seed)
			local swell = (1 + 0.15 * math.min(1, age / b.life)) * math.min(1, age / 0.4)
			local size = b.size * swell
			b.part.Size = Vector3.new(size * wobble, size / wobble, size * wobble)
			b.part.Position = at
			b.part.Color = Color3.fromHSV((b.seed * 0.01 + age * 0.08) % 1, 0.22, 1)
			-- Its glint, up and toward the sun on its skin.
			b.glint.Size = Vector3.new(size, size, size) * 0.2
			b.glint.Position = at + Vector3.new(-0.2, 0.28, -0.16) * size
			-- WALKED INTO: popped.
			for _, point in ipairs(body) do
				if (point - at).Magnitude < size / 2 + POP_REACH then
					pop(index, false, true)
					break
				end
			end
		end
	end
end

-- A TAP OR A CLICK on a bubble pops it.
local function tapped(input: InputObject, processed: boolean)
	if processed or not on then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	-- THE NEAREST BUBBLE ALONG THE TAP, worked out here: a bubble takes no part in the game's rays (the camera's, the
	-- trails' ground), so it is never in anything's way.
	local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
	local best, bestAlong = nil, math.huge
	for index, b in ipairs(bubbles) do
		local to = b.part.Position - ray.Origin
		local along = to:Dot(ray.Direction)
		local off = (to - ray.Direction * along).Magnitude
		if along > 0 and along < 200 and off < b.part.Size.X / 2 + 0.4 and along < bestAlong then
			best, bestAlong = index, along
		end
	end
	if best then
		pop(best, true, true)
	end
end

-- ===== GULLS =====

local function makeGull(k: number): Gull
	local white, grey = Color3.fromRGB(244, 244, 240), Color3.fromRGB(176, 180, 190)
	local body = piece("GullBody", Vector3.new(0.8, 0.7, 2.3), white, Enum.Material.SmoothPlastic)
	local shape = Instance.new("SpecialMesh")
	shape.MeshType = Enum.MeshType.Sphere
	shape.Parent = body
	local head = piece("GullHead", Vector3.new(0.6, 0.6, 0.6), white, Enum.Material.SmoothPlastic)
	head.Shape = Enum.PartType.Ball
	local wings = {}
	for _ = 1, 2 do
		table.insert(wings, piece("GullWing", Vector3.new(2.6, 0.1, 0.9), grey, Enum.Material.SmoothPlastic))
	end
	for _, p in ipairs({ body, head, wings[1], wings[2] }) do
		p.Parent = holder()
	end
	return { body = body, head = head, wings = wings, radius = 175 + k * 22, height = 26 + k * 9,
		speed = 0.07 + k * 0.012, phase = k * 2.1, seed = rng:NextNumber(0, 100) }
end

local function moveGulls(now: number)
	local centre = hubOrigin()
	for _, g in ipairs(gulls) do
		local a = now * g.speed + g.phase
		-- A loose loop, not a circle: wider one way than the other, rising and falling a little.
		local at = centre + Vector3.new(math.cos(a) * g.radius, g.height + math.sin(a * 2 + g.seed) * 4,
			math.sin(a) * g.radius * 0.8)
		local ahead = centre + Vector3.new(math.cos(a + 0.02) * g.radius, g.height + math.sin((a + 0.02) * 2 + g.seed) * 4,
			math.sin(a + 0.02) * g.radius * 0.8)
		local frame = CFrame.lookAt(at, ahead) * CFrame.Angles(0, 0, math.rad(18)) -- banked into the turn
		g.body.CFrame = frame
		g.head.CFrame = frame * CFrame.new(0, 0.25, -1.3)
		-- GLIDING mostly; a few beats of the wings now and then.
		local beating = math.noise(now * 0.25, g.seed) > 0.15
		local flap = if beating then math.sin(now * 9 + g.seed) * 0.6 else math.sin(now * 1.2 + g.seed) * 0.08
		for side, wing in ipairs(g.wings) do
			local sign = if side == 1 then -1 else 1
			wing.CFrame = frame * CFrame.new(sign * 0.35, 0.1, 0) * CFrame.Angles(0, 0, sign * flap)
				* CFrame.new(sign * 1.3, 0, 0)
		end
	end
end

-- ===== FIREFLIES =====

local function makeFireflies(): ParticleEmitter
	local garden = LobbyLayout.DECKS.garden
	local field = piece("FireflyField", Vector3.new(garden.w - 14, 5, garden.d - 14), Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic)
	field.Transparency = 1
	field.Position = hubOrigin() + Vector3.new(garden.x, 4, garden.z)
	field.Parent = holder()
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "Fireflies"
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Rate = 3
	motes.Lifetime = NumberRange.new(4, 7)
	motes.Speed = NumberRange.new(0.2, 0.6)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Size = NumberSequence.new(0.22)
	-- Blinking: on, off, on again, gone.
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.1),
		NumberSequenceKeypoint.new(0.35, 0.9), NumberSequenceKeypoint.new(0.55, 0.15), NumberSequenceKeypoint.new(0.8, 0.85),
		NumberSequenceKeypoint.new(1, 1) })
	motes.Color = ColorSequence.new(Color3.fromRGB(226, 255, 150))
	motes.LightEmission = 1
	motes.Drag = 1
	motes.Acceleration = Vector3.new(0, 0.15, 0)
	motes.Parent = field
	return motes
end

-- ===== ON AND OFF =====

local function setOn(want: boolean)
	if want == on then
		return
	end
	on = want
	if want then
		for k = 1, GULLS do
			table.insert(gulls, makeGull(k))
		end
		fireflies = makeFireflies()
	else
		for index = #bubbles, 1, -1 do
			pop(index, false, false)
		end
		for _, g in ipairs(gulls) do
			g.body:Destroy()
			g.head:Destroy()
			for _, wing in ipairs(g.wings) do
				wing:Destroy()
			end
		end
		table.clear(gulls)
		local emitter = fireflies
		if emitter and emitter.Parent then
			(emitter.Parent :: Instance):Destroy()
		end
		fireflies = nil
	end
end

local function step()
	local player = Players.LocalPlayer
	local inLobby = workspace:FindFirstChild("Hub") ~= nil and player:GetAttribute("InLevel") == nil
	setOn(inLobby)
	if not on then
		return
	end
	local now = os.clock()
	local fountain = hubOrigin() + LobbyLayout.AT.pool
	local camera = workspace.CurrentCamera
	local near = camera ~= nil and (camera.CFrame.Position - fountain).Magnitude < BUBBLE_NEAR
	if near and now >= nextBubble then
		nextBubble = now + BUBBLE_EVERY * rng:NextNumber(0.6, 1.4)
		blow(fountain, now)
	end
	local body: { Vector3 } = {}
	local character = player.Character
	if character then
		for _, name in ipairs({ "Head", "HumanoidRootPart" }) do
			local part = character:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				table.insert(body, part.Position)
			end
		end
	end
	moveBubbles(now, body)
	moveGulls(now)
end

function LobbyLife.start()
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(step)
		if not ok and not failed then
			failed = true
			warn("[client] LobbyLife: " .. tostring(err) .. " (shown once)")
		end
	end)
	UserInputService.InputBegan:Connect(tapped)
	print("LobbyLife: running, " .. LobbyLife.VERSION)
end

LobbyLife.STAMP = "19fe7174"
return LobbyLife
