--!strict
-- StarterPlayerScripts/Services/ClimbClient.lua
-- THE CLIMB, on your screen (the two-hundred-and-sixtieth pass). The server says what is happening and this shows it:
--   * "going" covers the screen with a soft fade, "arrived" uncovers it once you are standing where you were going.
--   * YOUR HEIGHT, while you climb: a small pill at the top, how high you are standing and your best (the server keeps
--     both on you as attributes, ClimbHeight and ClimbBest). Nothing else on the screen.
--   * A NEW BEST: the first time you pass your best this climb, a word and a soft chime; every 25 m after that, the
--     height. Tokens paid for it are said with it.
--   * A FALL: the whoosh, the fade, and "Back to the bottom" with how high you were.
--   * THE AIR UP THERE: a clear sky's light while you climb (whatever a run elsewhere has set), and the wind, louder the
--     higher you are. All put back as you leave.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style")) :: any

local ClimbClient = {}

local ui: { [string]: any } = {}
local LONGEST = 8
local SETTLE = 0.8

-- The sky's light up the climb, as it is put on now (skyStage below sets it from your height).
local SKY: { [string]: any } = {
	ClockTime = 14.5,
	Brightness = 2.2,
	Ambient = Color3.fromRGB(120, 124, 136),
	OutdoorAmbient = Color3.fromRGB(150, 156, 170),
	EnvironmentDiffuseScale = 0.6,
	EnvironmentSpecularScale = 0.6,
	ExposureCompensation = 0,
}
local AIR = { Density = 0.28, Offset = 0.1, Color = Color3.fromRGB(206, 222, 240), Decay = Color3.fromRGB(150, 176, 210),
	Glare = 0.2, Haze = 1.2 }
local WIND = { low = 0.08, high = 0.45, at = 120 } -- its volume at the bottom and at `at` metres and over

-- ===== THE SKY AS YOU CLIMB (the two-hundred-and-sixty-second pass, "improve the background skies in the forever climb") =====
--
-- The higher you are, the later the day: a clear afternoon at the bottom, the gold of late afternoon by 60 m, sunset
-- (the haze rose and the clouds lit orange from the side) by 130 m, dusk and the first stars by 200 m, and from 300 m a
-- deep blue night full of stars and the moon, the climb's own lamps the warm light. Between two stages everything is
-- blended by your height. Each stage: from `at` metres, the time of day, the sun's brightness, the two ambients, the
-- air's colour and decay, its haze, glare and density, and how many stars.
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local STAGES = {
	{ at = 0, clock = 13.5, bright = 2.2, amb = rgb(120, 124, 136), out = rgb(150, 156, 170), air = rgb(206, 222, 240),
		decay = rgb(150, 176, 210), haze = 1.2, glare = 0.2, density = 0.28, stars = 0 },
	{ at = 60, clock = 16.4, bright = 2.0, amb = rgb(134, 120, 108), out = rgb(172, 150, 128), air = rgb(255, 220, 178),
		decay = rgb(236, 172, 122), haze = 1.6, glare = 0.6, density = 0.3, stars = 0 },
	{ at = 130, clock = 17.75, bright = 1.6, amb = rgb(132, 102, 112), out = rgb(164, 122, 130), air = rgb(255, 168, 140),
		decay = rgb(196, 112, 150), haze = 2.3, glare = 1.0, density = 0.32, stars = 0 },
	{ at = 200, clock = 18.7, bright = 1.0, amb = rgb(98, 92, 132), out = rgb(112, 102, 152), air = rgb(142, 122, 182),
		decay = rgb(72, 66, 132), haze = 1.6, glare = 0.3, density = 0.3, stars = 900 },
	{ at = 300, clock = 21.5, bright = 0.6, amb = rgb(86, 94, 132), out = rgb(92, 102, 152), air = rgb(44, 52, 96),
		decay = rgb(16, 20, 44), haze = 0.6, glare = 0, density = 0.24, stars = 3200 },
	{ at = 450, clock = 24, bright = 0.5, amb = rgb(82, 90, 132), out = rgb(82, 94, 142), air = rgb(22, 26, 56),
		decay = rgb(6, 8, 22), haze = 0.3, glare = 0, density = 0.2, stars = 5000 },
}
local starCount = 0

local function skyStage(metres: number)
	local a, b = STAGES[1], STAGES[1]
	for k = 1, #STAGES do
		if metres >= STAGES[k].at then
			a = STAGES[k]
			b = STAGES[math.min(k + 1, #STAGES)]
		end
	end
	local t = if b.at > a.at then math.clamp((metres - a.at) / (b.at - a.at), 0, 1) else 0
	t = t * t * (3 - 2 * t)
	local function mix(x: number, y: number): number
		return x + (y - x) * t
	end
	SKY.ClockTime = mix(a.clock, b.clock) % 24
	SKY.Brightness = mix(a.bright, b.bright)
	SKY.Ambient = a.amb:Lerp(b.amb, t)
	SKY.OutdoorAmbient = a.out:Lerp(b.out, t)
	AIR.Color = a.air:Lerp(b.air, t)
	AIR.Decay = a.decay:Lerp(b.decay, t)
	AIR.Haze = mix(a.haze, b.haze)
	AIR.Glare = mix(a.glare, b.glare)
	AIR.Density = mix(a.density, b.density)
	starCount = math.floor(mix(a.stars, b.stars))
end

local function build()
	if ui.fade then
		return
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local cover = Instance.new("ScreenGui")
	cover.Name = "ClimbFade"
	cover.ResetOnSpawn = false
	cover.DisplayOrder = 50
	cover.IgnoreGuiInset = true
	cover.Parent = playerGui
	local fade = Instance.new("Frame")
	fade.Active = false
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.fromRGB(232, 240, 250)
	fade.BackgroundTransparency = 1
	fade.BorderSizePixel = 0
	fade.Parent = cover
	ui.fade = fade

	local hud = Instance.new("ScreenGui")
	hud.Name = "ClimbHud"
	hud.ResetOnSpawn = false
	hud.DisplayOrder = 12
	hud.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	hud.Enabled = false
	hud.Parent = playerGui
	ui.hud = hud
	local pill = Instance.new("Frame")
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 14)
	pill.Size = UDim2.new(0, 248, 0, 52)
	pill.BackgroundColor3 = Style.COLOUR.panel
	pill.BackgroundTransparency = 0.12
	pill.Parent = hud
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = pill
	local edge = Instance.new("UIStroke")
	edge.Color = Style.COLOUR.accent
	edge.Thickness = 2
	edge.Transparency = 0.3
	edge.Parent = pill
	local height = Instance.new("TextLabel")
	height.BackgroundTransparency = 1
	height.Position = UDim2.new(0, 18, 0, 0)
	height.Size = UDim2.new(0.55, -18, 1, 0)
	height.FontFace = Style.FONT.heading
	height.TextSize = 26
	height.TextXAlignment = Enum.TextXAlignment.Left
	height.TextColor3 = Style.COLOUR.ink
	height.Text = "0 m"
	height.Parent = pill
	ui.height = height
	local best = Instance.new("TextLabel")
	best.BackgroundTransparency = 1
	best.Position = UDim2.new(0.55, 0, 0, 0)
	best.Size = UDim2.new(0.45, -18, 1, 0)
	best.FontFace = Style.FONT.body
	best.TextSize = 16
	best.TextXAlignment = Enum.TextXAlignment.Right
	best.TextColor3 = Style.COLOUR.accent
	best.Text = "BEST 0 m"
	best.Parent = pill
	ui.best = best

	-- The word, under the pill.
	local word = Instance.new("TextLabel")
	word.AnchorPoint = Vector2.new(0.5, 0)
	word.Position = UDim2.new(0.5, 0, 0, 76)
	word.AutomaticSize = Enum.AutomaticSize.X
	word.Size = UDim2.new(0, 0, 0, 40)
	word.BackgroundColor3 = Color3.fromRGB(251, 238, 214)
	word.FontFace = Style.FONT.heading
	word.TextSize = 20
	word.TextColor3 = Color3.fromRGB(72, 44, 40)
	word.Visible = false
	word.Parent = hud
	local wordCorner = Instance.new("UICorner")
	wordCorner.CornerRadius = UDim.new(0.5, 0)
	wordCorner.Parent = word
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 18)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = word
	ui.word = word
	-- A word for when you are not climbing (the lift will not go yet), at the bottom.
	local note = word:Clone()
	note.Parent = playerGui:FindFirstChild("ClimbFade")
	note.AnchorPoint = Vector2.new(0.5, 1)
	note.Position = UDim2.new(0.5, 0, 1, -96)
	ui.note = note
end

local function uncover()
	build()
	ui.coveredAt = nil
	TweenService:Create(ui.fade, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
end

local function cover()
	build()
	local stamp = os.clock()
	ui.coveredAt = stamp
	TweenService:Create(ui.fade, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { BackgroundTransparency = 0 }):Play()
	task.delay(LONGEST, function()
		if ui.coveredAt == stamp then
			uncover()
		end
	end)
end

-- The camera behind you as the fade lifts, so it is never left inside the lift.
local function behind()
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (camera and root and root:IsA("BasePart")) then
		return
	end
	local flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if flat.Magnitude < 0.05 then
		return
	end
	local at = root.Position + Vector3.new(0, 1.5, 0)
	camera.CFrame = CFrame.lookAt(at - flat.Unit * 9 + Vector3.new(0, 4, 0), at)
end

local function say(text: string, seconds: number?, atBottom: boolean?)
	build()
	local label = if atBottom then ui.note else ui.word
	label.Text = text
	label.Visible = true
	local stamp = os.clock()
	label:SetAttribute("At", stamp)
	task.delay(seconds or 3, function()
		if label:GetAttribute("At") == stamp then
			label.Visible = false
		end
	end)
end

local function play(folder: string, name: string, volume: number, pitch: number?)
	local found = SoundService:FindFirstChild(folder)
	local sound = found and found:FindFirstChild(name)
	if not (sound and sound:IsA("Sound")) then
		return
	end
	local s = sound:Clone()
	s.Volume = volume
	s.PlaybackSpeed = pitch or 1
	s.Looped = false
	s.Parent = SoundService
	s:Play()
	game:GetService("Debris"):AddItem(s, 8)
end

-- ===== THE AIR =====

local saved: { [string]: any } = {}
local savedAir: { [string]: any } = {}
local dimmed: { [PostEffect]: boolean } = {}
local up = false

local function same(a: any, b: any): boolean
	if type(a) == "number" and type(b) == "number" then
		return math.abs(a - b) < 1e-3
	end
	return a == b
end

local function skyOn()
	local L = Lighting :: any
	if not up then
		for key in pairs(SKY) do
			saved[key] = L[key]
		end
		saved.StarCount = nil
		local air = Lighting:FindFirstChildOfClass("Atmosphere") :: any
		if air then
			for key in pairs(AIR) do
				savedAir[key] = air[key]
			end
		end
		-- A level's own blur and grade (the halls' depth of field, the Sunken City's tint) are not the sky's.
		for _, effect in ipairs(Lighting:GetChildren()) do
			if (effect:IsA("DepthOfFieldEffect") or effect:IsA("ColorCorrectionEffect")) and effect.Enabled then
				dimmed[effect] = true
				effect.Enabled = false
			end
		end
	end
	up = true
	for key, value in pairs(SKY) do
		L[key] = value
	end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		if saved.StarCount == nil then
			saved.StarCount = sky.StarCount
		end
		sky.StarCount = starCount
	end
	local air = Lighting:FindFirstChildOfClass("Atmosphere") :: any
	if air then
		for key, value in pairs(AIR) do
			air[key] = value
		end
	end
end

local function skyOff()
	if not up then
		return
	end
	up = false
	local L = Lighting :: any
	-- Put back, unless something else (a run's light) has set it since.
	for key, value in pairs(SKY) do
		if same(L[key], value) and saved[key] ~= nil then
			L[key] = saved[key]
		end
	end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky and saved.StarCount ~= nil and sky.StarCount == starCount then
		sky.StarCount = saved.StarCount
	end
	local air = Lighting:FindFirstChildOfClass("Atmosphere") :: any
	if air then
		for key, value in pairs(AIR) do
			if same(air[key], value) and savedAir[key] ~= nil then
				air[key] = savedAir[key]
			end
		end
	end
	for effect in pairs(dimmed) do
		if effect.Parent then
			effect.Enabled = true
		end
	end
	table.clear(dimmed)
	table.clear(saved)
	table.clear(savedAir)
end

local wind: Sound? = nil
local function windOn(on: boolean)
	if on and not wind then
		local folder = SoundService:FindFirstChild("AmbienceSounds")
		local source = folder and folder:FindFirstChild("RoofWind")
		if source and source:IsA("Sound") then
			local s = source:Clone()
			s.Looped = true
			s.Volume = WIND.low
			s.Parent = SoundService
			s:Play()
			wind = s
		end
	elseif not on and wind then
		local s = wind
		wind = nil
		TweenService:Create(s, TweenInfo.new(1.2), { Volume = 0 }):Play()
		game:GetService("Debris"):AddItem(s, 1.4)
	end
end

-- ===== ONLY THE STEPS AHEAD (pass 261) =====
--
-- From your note: "the chunks below me should disappear, and only the next 1-2 chunks in front of me should remain". On
-- your screen, the step you last stood on (ClimbStep, the server's) and the SHOW_AHEAD after it are there; every other
-- step is taken away for you alone: not drawn, its lights and signs out, and in the server's hidden collision group,
-- which your character passes through. Others climbing have their own. Everything is put back as it was the moment a
-- step is yours again, or you leave.
local hiddenSteps: { [Instance]: { [Instance]: { any } } } = {}

-- `fading`: the step is being unbuilt (BUILD below), which fades its parts itself; they still stop being solid at once.
local function conceal(model: Instance, group: string, fading: boolean?)
	local saved = hiddenSteps[model]
	if not saved then
		saved = {}
		hiddenSteps[model] = saved
	end
	for _, item in ipairs(model:GetDescendants()) do
		if saved[item] == nil then
			if item:IsA("BasePart") then
				saved[item] = { item.LocalTransparencyModifier, item.CollisionGroup }
				if not fading then
					item.LocalTransparencyModifier = 1
				end
				item.CollisionGroup = group
			elseif item:IsA("Decal") then
				saved[item] = { item.LocalTransparencyModifier }
				item.LocalTransparencyModifier = 1
			elseif item:IsA("SurfaceGui") or item:IsA("Light") or item:IsA("ParticleEmitter") or item:IsA("Beam") then
				saved[item] = { (item :: any).Enabled }
				;(item :: any).Enabled = false
			end
		end
	end
end

local function reveal(model: Instance)
	local saved = hiddenSteps[model]
	hiddenSteps[model] = nil
	if not saved then
		return
	end
	for item, was in pairs(saved) do
		if item.Parent then
			if item:IsA("BasePart") then
				item.LocalTransparencyModifier = was[1]
				item.CollisionGroup = was[2]
			elseif item:IsA("Decal") then
				item.LocalTransparencyModifier = was[1]
			else
				(item :: any).Enabled = was[1]
			end
		end
	end
end

-- ===== BUILT AND UNBUILT (passes 263 and 264) =====
--
-- From your notes: "make a building animation" and then "improve the animation of building the chunks as I go even more,
-- be creative with it". A step that comes to you is GATHERED OUT OF THE AIR: its pieces start scattered round where it
-- will be, tumbled and see-through, and each flies home along an arc, the middle of the step first and its edges after,
-- turning as it comes and snapping square with a little overshoot. When the last piece lands the step CLICKS: a soft
-- brick click, a ring of light running out across its top and a puff of sparkles. A step left behind is BLOWN AWAY: top
-- first, its pieces lift on one gust, tumble off sideways, fall and fade, with a soft hush. It stops being solid the
-- moment it starts to go, so a fall is still a fall. All of it on your screen only, every piece put back exactly where
-- the server has it when its motion ends. Under Roblox's Reduce Motion the pieces only fade, without flying or spinning.
local BUILD = {
	inTime = 0.62, -- seconds for one piece to fly home
	inStagger = 0.34, -- the middle first, the edges this much later
	outTime = 0.75,
	outStagger = 0.2, -- the top first
	scatter = { 7, 12 }, -- how far out a piece starts, studs
	lift = { 2.5, 5.5 }, -- how high its arc rises over the straight line home
	spin = 2.4, -- the most a piece is turned when it starts, radians a side
	gravity = 46,
	ring = Color3.fromRGB(255, 240, 206),
}
type Piece = { cf: CFrame, ltm: number, delay: number, from: Vector3, lift: number, spin: Vector3, fly: Vector3 }
type Motion = { kind: string, t0: number, parts: { [BasePart]: Piece }, top: CFrame?, wide: number, demo: boolean? }
local moving: { [Instance]: Motion } = {}
local seen: { [Instance]: boolean } = {}
local buildRng = Random.new()

local function settle(model: Instance)
	local motion = moving[model]
	if not motion then
		return
	end
	moving[model] = nil
	for part, info in pairs(motion.parts) do
		if part.Parent then
			part.CFrame = info.cf
			part.LocalTransparencyModifier = if motion.kind == "in" then info.ltm else 1
		end
	end
end

-- The click: a ring of warm light running out over the step's top, and a puff of sparkles off it.
local function landed(motion: Motion)
	local top = motion.top
	if not top then
		return
	end
	if not motion.demo then
		play("MaterialSounds", "legoClick_" .. buildRng:NextInteger(1, 4), 0.32, buildRng:NextNumber(0.92, 1.08))
	end
	if Style.lessMotion() then
		return
	end
	local ring = Instance.new("Part")
	ring.Name = "ClimbBuildRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.SmoothPlastic
	ring.Color = BUILD.ring
	ring.Transparency = 0.45
	ring.Size = Vector3.new(0.08, motion.wide * 0.6, motion.wide * 0.6)
	ring.CFrame = top * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.pi / 2)
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, motion.wide * 1.7, motion.wide * 1.7),
		Transparency = 1,
	}):Play()
	game:GetService("Debris"):AddItem(ring, 0.6)
	local spark = Instance.new("Attachment")
	spark.Parent = workspace.Terrain
	spark.WorldPosition = top.Position + Vector3.new(0, 0.4, 0)
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Color = ColorSequence.new(BUILD.ring)
	burst.LightEmission = 0.6
	burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	burst.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	burst.Lifetime = NumberRange.new(0.5, 0.9)
	burst.Speed = NumberRange.new(4, 9)
	burst.SpreadAngle = Vector2.new(80, 80)
	burst.Acceleration = Vector3.new(0, -10, 0)
	burst.Rate = 0
	burst.Parent = spark
	burst:Emit(if motion.demo then 6 else 18)
	-- (Pass 265) A soft puff of dust knocked off its underside as it locks, drifting down and away.
	if not motion.demo then
		local dust = Instance.new("ParticleEmitter")
		dust.Texture = "rbxasset://textures/particles/smoke_main.dds"
		dust.Color = ColorSequence.new(Color3.fromRGB(246, 240, 230))
		dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.2) })
		dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
		dust.Lifetime = NumberRange.new(0.8, 1.3)
		dust.Speed = NumberRange.new(1.5, 3)
		dust.SpreadAngle = Vector2.new(70, 70)
		dust.EmissionDirection = Enum.NormalId.Bottom
		dust.Acceleration = Vector3.new(0, -2, 0)
		dust.Rate = 0
		dust.Parent = spark
		dust:Emit(6)
	end
	game:GetService("Debris"):AddItem(spark, 1.6)
end

-- THE GATHERING (pass 265, from your note: "improve the animation of the chunks and the climb itself"): as a step's
-- pieces start to fly home, motes are drawn in to where it will be from all round, a swirl of the air being gathered,
-- for about as long as the pieces take.
local function gathering(at: Vector3, wide: number)
	if Style.lessMotion() then
		return
	end
	local well = Instance.new("Part")
	well.Name = "ClimbGathering"
	well.Anchored = true
	well.CanCollide = false
	well.CanQuery = false
	well.CanTouch = false
	well.Transparency = 1
	well.Size = Vector3.new(wide * 2.4, wide * 1.2, wide * 2.4)
	well.CFrame = CFrame.new(at)
	well.Parent = workspace
	local pull = Instance.new("ParticleEmitter")
	pull.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pull.Color = ColorSequence.new(Color3.fromRGB(255, 244, 214), Color3.fromRGB(206, 226, 255))
	pull.LightEmission = 0.5
	pull.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.28),
		NumberSequenceKeypoint.new(1, 0) })
	pull.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.2),
		NumberSequenceKeypoint.new(1, 0.6) })
	pull.Lifetime = NumberRange.new(0.55, 0.7)
	pull.Speed = NumberRange.new(wide * 1.7, wide * 2)
	pull.RotSpeed = NumberRange.new(-200, 200)
	pull.Shape = Enum.ParticleEmitterShape.Sphere
	pull.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	pull.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	pull.Rate = 70
	pull.Parent = well
	task.delay(0.55, function()
		pull.Enabled = false
	end)
	game:GetService("Debris"):AddItem(well, 1.4)
end

local function startMotion(model: Instance, kind: string, demo: boolean?)
	settle(model)
	local parts: { BasePart } = {}
	local low, high = math.huge, -math.huge
	local middle = Vector3.zero
	local biggest: BasePart? = nil
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			table.insert(parts, item)
			low = math.min(low, item.Position.Y)
			high = math.max(high, item.Position.Y)
			middle += item.Position
			if not biggest or item.Size.X * item.Size.Z > biggest.Size.X * biggest.Size.Z then
				biggest = item
			end
		end
	end
	if #parts == 0 then
		return
	end
	middle /= #parts
	local span = math.max(1, high - low)
	local far = 0.01
	for _, part in ipairs(parts) do
		far = math.max(far, (part.Position - middle).Magnitude)
	end
	local still = Style.lessMotion()
	local gust = CFrame.Angles(0, buildRng:NextNumber(0, math.pi * 2), 0).LookVector
	local motion: Motion = { kind = kind, t0 = os.clock(), parts = {}, wide = 6, demo = demo }
	local reach = if demo then 0.35 else 1
	if biggest then
		local slab = biggest :: BasePart
		motion.top = slab.CFrame * CFrame.new(0, slab.Size.Y / 2, 0)
		motion.wide = math.max(slab.Size.X, slab.Size.Z)
	end
	for _, part in ipairs(parts) do
		local away = part.Position - middle
		local flat = Vector3.new(away.X, 0, away.Z)
		local out = if flat.Magnitude > 0.2 then flat.Unit
			else CFrame.Angles(0, buildRng:NextNumber(0, math.pi * 2), 0).LookVector
		-- Turned off the straight line out a little, so pieces come from all round and not in a star.
		out = CFrame.Angles(0, buildRng:NextNumber(-0.7, 0.7), 0):VectorToWorldSpace(out)
		local rise = (part.Position.Y - low) / span
		local piece: Piece = {
			cf = part.CFrame,
			ltm = part.LocalTransparencyModifier,
			delay = if kind == "in"
				then BUILD.inStagger * ((part.Position - middle).Magnitude / far) + buildRng:NextNumber(0, 0.07)
				else BUILD.outStagger * (1 - rise) + buildRng:NextNumber(0, 0.06),
			from = if still then Vector3.zero
				else (out * buildRng:NextNumber(BUILD.scatter[1], BUILD.scatter[2]) + Vector3.new(0, buildRng:NextNumber(-5, 3), 0))
					* reach,
			lift = buildRng:NextNumber(BUILD.lift[1], BUILD.lift[2]) * reach,
			spin = if still then Vector3.zero
				else Vector3.new(buildRng:NextNumber(-1, 1), buildRng:NextNumber(-1, 1), buildRng:NextNumber(-1, 1)) * BUILD.spin,
			fly = if still then Vector3.zero
				else ((gust * 0.6 + out * 0.4) * buildRng:NextNumber(5, 10) + Vector3.new(0, buildRng:NextNumber(5, 9), 0)) * reach,
		}
		motion.parts[part] = piece
		if kind == "in" then
			part.LocalTransparencyModifier = 1
			part.CFrame = CFrame.new(piece.cf.Position + piece.from) * piece.cf.Rotation
				* CFrame.Angles(piece.spin.X, piece.spin.Y, piece.spin.Z)
		end
	end
	if kind == "out" and not demo then
		play("StorySounds", "CloudWhoosh", 0.08, buildRng:NextNumber(1.25, 1.45))
	end
	if kind == "in" and not demo and not still then
		gathering(middle, motion.wide)
	end
	moving[model] = motion
end

local function animateSteps()
	local now = os.clock()
	for model, motion in pairs(moving) do
		local length = if motion.kind == "in" then BUILD.inTime else BUILD.outTime
		local done = true
		for part, info in pairs(motion.parts) do
			if part.Parent then
				local t = math.clamp((now - motion.t0 - info.delay) / length, 0, 1)
				if t < 1 then
					done = false
				end
				local home = info.cf.Position
				if motion.kind == "in" then
					-- Home along an arc (a curve through a point lifted over the halfway), quick then slowing.
					local u = 1 - (1 - t) ^ 3
					local start = home + info.from
					local over = (start + home) / 2 + Vector3.new(0, info.lift, 0)
					local at = start:Lerp(over, u):Lerp(over:Lerp(home, u), u)
					-- Turning square, past it a touch, and back (ease out, back).
					local v = t - 1
					local turned = 1 + 2.4 * v * v * v + 1.4 * v * v
					local left = info.spin * (1 - turned)
					part.CFrame = CFrame.new(at) * info.cf.Rotation * CFrame.Angles(left.X, left.Y, left.Z)
					part.LocalTransparencyModifier = info.ltm + (1 - info.ltm) * (1 - math.min(1, t * 2.2))
				else
					-- Up on the gust, over and down, tumbling.
					local tau = t * length
					local at = home + info.fly * tau - Vector3.new(0, 0.5 * BUILD.gravity * tau * tau, 0)
					local turn = info.spin * (t * 1.6)
					part.CFrame = CFrame.new(at) * info.cf.Rotation * CFrame.Angles(turn.X, turn.Y, turn.Z)
					part.LocalTransparencyModifier = info.ltm + (1 - info.ltm) * math.clamp((t - 0.25) / 0.75, 0, 1)
				end
			end
		end
		if done or model.Parent == nil then
			local wasIn = motion.kind == "in" and model.Parent ~= nil
			settle(model)
			if wasIn then
				landed(motion)
			end
		end
	end
end

local function sortSteps()
	local climb = workspace:FindFirstChild("Climb")
	local folder = climb and climb:FindFirstChild("Steps")
	if not folder then
		return
	end
	local me = Players.LocalPlayer
	local on = me:GetAttribute("InClimb") == true
	local at = tonumber(me:GetAttribute("ClimbStep")) or 0
	local ahead = tonumber(ReplicatedStorage:GetAttribute("ClimbShowAhead")) or 2
	local group = ReplicatedStorage:GetAttribute("ClimbHiddenGroup")
	if typeof(group) ~= "string" then
		return
	end
	for _, model in ipairs(folder:GetChildren()) do
		local index = model:GetAttribute("ClimbStep")
		if typeof(index) == "number" then
			local shown = not on or (index >= math.max(1, at) and index <= at + ahead)
			if shown then
				if hiddenSteps[model] then
					settle(model)
					reveal(model)
					if on then
						startMotion(model, "in")
					end
				elseif not seen[model] and on then
					startMotion(model, "in")
				end
				seen[model] = true
			else
				local wasShown = seen[model] == true and hiddenSteps[model] == nil
				conceal(model, group, wasShown or moving[model] ~= nil)
				if wasShown and on then
					startMotion(model, "out")
				end
				seen[model] = false
			end
		end
	end
	for model in pairs(hiddenSteps) do
		if model.Parent == nil then
			hiddenSteps[model] = nil
		end
	end
	for model in pairs(seen) do
		if model.Parent == nil then
			seen[model] = nil
		end
	end
end

-- ===== THE TOWER'S LITTLE SHOW (pass 265) =====
--
-- The small steps winding up the lobby's climbing tower (ClimbService tags them ClimbDemoStep, each its DemoIndex) are
-- built out of the air one after another from the bottom, held a moment, and blown away from the top, over and over:
-- what the climb's own steps do, shown before you go in. Only while you are near the tower and not climbing; quietly
-- (no clicks); and under Reduce Motion they stay as they are.
local DEMO = { near = 260, gap = 0.22, hold = 2.6, rest = 1.4 }

local function demoSteps(): { Instance }
	local list = game:GetService("CollectionService"):GetTagged("ClimbDemoStep")
	table.sort(list, function(a, b)
		return (tonumber(a:GetAttribute("DemoIndex")) or 0) < (tonumber(b:GetAttribute("DemoIndex")) or 0)
	end)
	return list
end

local function showAll(list: { Instance })
	for _, model in ipairs(list) do
		settle(model)
		for _, item in ipairs(model:GetDescendants()) do
			if item:IsA("BasePart") then
				item.LocalTransparencyModifier = 0
			end
		end
	end
end

local function demoNear(list: { Instance }): boolean
	local camera = workspace.CurrentCamera
	local first = list[1]
	if not (camera and first and first:IsA("Model")) then
		return false
	end
	return (camera.CFrame.Position - first:GetPivot().Position).Magnitude < DEMO.near
end

local function runDemo()
	while true do
		local list = demoSteps()
		local me = Players.LocalPlayer
		if #list == 0 or me:GetAttribute("InClimb") or Style.lessMotion() or not demoNear(list) then
			showAll(list)
			task.wait(1)
		else
			-- Away, top first; then built again, bottom first; then held.
			for k = #list, 1, -1 do
				startMotion(list[k], "out", true)
				task.wait(DEMO.gap * 0.6)
			end
			task.wait(BUILD.outTime + DEMO.rest)
			for _, model in ipairs(list) do
				settle(model)
				for _, item in ipairs(model:GetDescendants()) do
					if item:IsA("BasePart") then
						item.LocalTransparencyModifier = 0
					end
				end
				startMotion(model, "in", true)
				task.wait(DEMO.gap)
			end
			task.wait(BUILD.inTime + BUILD.inStagger + DEMO.hold)
		end
	end
end

-- THE PALS IN THE CLIMB'S SKY, by your height (pass 265, from your note: "like the chunks in the sky in the climb, I want
-- the cloud pets to appear and disappear ... a range of visibility, or better make them fade out of the player's view").
-- A pal cloud near your height is all there; one far above or below you fades, and is gone once it is FADE.far over or
-- under you, so you climb up past them one by one. Outside the climb they are all as made.
local FADE = { near = 55, far = 150 }
local cloudShown: { [BasePart]: number } = {}

local function fadeClouds()
	local climb = workspace:FindFirstChild("Climb")
	local clouds = climb and climb:FindFirstChild("Clouds")
	if not clouds then
		return
	end
	local on = Players.LocalPlayer:GetAttribute("InClimb") == true
	local camera = workspace.CurrentCamera
	local y = if camera then camera.CFrame.Position.Y else 0
	for _, model in ipairs(clouds:GetChildren()) do
		if model.Name == "PetCloud" and model:IsA("Model") then
			local h = if on then math.abs(model:GetPivot().Position.Y - y) else 0
			local fade = math.clamp((h - FADE.near) / (FADE.far - FADE.near), 0, 1)
			fade = fade * fade * (3 - 2 * fade)
			for _, item in ipairs(model:GetDescendants()) do
				if item:IsA("BasePart") then
					if cloudShown[item] ~= fade then
						cloudShown[item] = fade
						item.LocalTransparencyModifier = fade
					end
				elseif item:IsA("ParticleEmitter") then
					item.Enabled = fade < 0.6
				end
			end
		end
	end
	for item in pairs(cloudShown) do
		if item.Parent == nil then
			cloudShown[item] = nil
		end
	end
end

-- A RING OF LIGHT AT EVERY 25 M (pass 265): sparkles thrown out flat all round you from your feet, as the height is said.
local function heightRing()
	if Style.lessMotion() then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	local spot = Instance.new("Attachment")
	spot.Parent = workspace.Terrain
	local ring = Instance.new("ParticleEmitter")
	ring.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	ring.Color = ColorSequence.new(Color3.fromRGB(255, 232, 170), Color3.fromRGB(255, 200, 220))
	ring.LightEmission = 0.7
	ring.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	ring.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.8) })
	ring.Lifetime = NumberRange.new(0.9, 1.1)
	ring.Speed = NumberRange.new(16, 18)
	ring.Drag = 3
	ring.SpreadAngle = Vector2.new(0, 0)
	ring.EmissionDirection = Enum.NormalId.Front
	ring.Rate = 0
	ring.Parent = spot
	local feet = root.Position - Vector3.new(0, 2.6, 0)
	for k = 0, 35 do
		spot.WorldCFrame = CFrame.new(feet) * CFrame.Angles(0, k / 36 * math.pi * 2, 0)
		ring:Emit(1)
	end
	game:GetService("Debris"):AddItem(spot, 1.6)
end

-- ===== WHILE YOU CLIMB =====

local startBest = 0
local passed = false

local function refresh()
	build()
	local me = Players.LocalPlayer
	local height = tonumber(me:GetAttribute("ClimbHeight")) or 0
	local best = tonumber(me:GetAttribute("ClimbBest")) or 0
	ui.height.Text = ("%d m"):format(height)
	ui.best.Text = ("BEST %d m"):format(best)
	if wind then
		local t = math.clamp(height / WIND.at, 0, 1)
		wind.Volume = WIND.low + (WIND.high - WIND.low) * t
	end
	if not passed and best > startBest and startBest > 0 then
		passed = true
		say("New best!", 2.5)
		play("StorySounds", "JournalAdd", 0.5)
	end
end

local function climbing(on: boolean)
	build()
	ui.hud.Enabled = on
	if on then
		startBest = tonumber(Players.LocalPlayer:GetAttribute("ClimbBest")) or 0
		passed = false
		skyOn()
		windOn(true)
		refresh()
	else
		skyOff()
		windOn(false)
	end
end

function ClimbClient.start()
	build()
	local me = Players.LocalPlayer
	me:GetAttributeChangedSignal("InClimb"):Connect(function()
		climbing(me:GetAttribute("InClimb") == true)
	end)
	me:GetAttributeChangedSignal("ClimbHeight"):Connect(refresh)
	me:GetAttributeChangedSignal("ClimbBest"):Connect(refresh)
	if me:GetAttribute("InClimb") then
		climbing(true)
	end
	-- THE STEPS BUILDING AND UNBUILDING, every frame.
	game:GetService("RunService").RenderStepped:Connect(function()
		local ok, err = pcall(animateSteps)
		if not ok then
			warn("ClimbClient: building the steps: " .. tostring(err))
			table.clear(moving)
		end
	end)
	-- THE SKY BY YOUR HEIGHT, every frame while you climb.
	game:GetService("RunService").RenderStepped:Connect(function()
		if not (up and me:GetAttribute("InClimb")) then
			return
		end
		local character = me.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local originY = tonumber(ReplicatedStorage:GetAttribute("ClimbOriginY"))
		local metre = tonumber(ReplicatedStorage:GetAttribute("ClimbMetre")) or 0.28
		if root and root:IsA("BasePart") and originY then
			skyStage(math.max(0, (root.Position.Y - originY) * metre))
			skyOn()
		end
	end)
	-- THE TOWER'S LITTLE SHOW, and THE PALS IN THE SKY faded by your height (pass 265).
	task.spawn(function()
		local ok, err = pcall(runDemo)
		if not ok then
			warn("ClimbClient: the tower's steps: " .. tostring(err))
		end
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(fadeClouds)
			if not ok then
				warn("ClimbClient: the pal clouds: " .. tostring(err))
				task.wait(2)
			end
			task.wait(0.1)
		end
	end)
	-- THE STEPS: only yours, kept in step with where you stand.
	task.spawn(function()
		while true do
			local ok, err = pcall(sortSteps)
			if not ok then
				warn("ClimbClient: the steps: " .. tostring(err))
				task.wait(2)
			end
			task.wait(0.15)
		end
	end)
	me:GetAttributeChangedSignal("ClimbStep"):Connect(function()
		pcall(sortSteps)
	end)
	-- THE SKY, held: a run starting elsewhere sets the light for everyone, and up here it is still a clear day.
	task.spawn(function()
		while true do
			task.wait(2)
			if me:GetAttribute("InClimb") and up then
				skyOn()
			end
		end
	end)
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents")
	local remote = remotes:WaitForChild("Climb", 30)
	if not (remote and remote:IsA("RemoteEvent")) then
		warn("ClimbClient: no RemoteEvents.Climb; paste the current server Bootstrap.")
		return
	end
	ui.remote = remote
	remote.OnClientEvent:Connect(function(kind: any, extra: any)
		if kind == "going" then
			cover()
		elseif kind == "arrived" then
			local stamp = ui.coveredAt
			behind()
			task.delay(SETTLE, function()
				if ui.coveredAt == stamp then
					behind()
					uncover()
				end
			end)
		elseif kind == "fell" then
			play("StorySounds", "CloudWhoosh", 0.6)
			local height = tonumber(extra) or 0
			task.delay(0.6, function()
				say(if height > 0 then ("Back to the bottom. You made %d m."):format(height) else "Back to the bottom.", 3)
			end)
		elseif kind == "milestone" then
			play("StorySounds", "JournalAdd", 0.35, 1.08)
			heightRing()
			say(("%d m!"):format(tonumber(extra) or 0), 2)
		elseif kind == "paid" then
			say(("+%d tokens for a new height"):format(tonumber(extra) or 0), 2.5)
		elseif kind == "closed" then
			say("The lobby is away while a run is on. It opens again when the run ends.", 4, true)
		elseif kind == "building" then
			say("The climb is still being set up. Try again in a moment.", 4, true)
		elseif kind == "running" then
			say("Finish or leave your run first.", 4, true)
		end
	end)
	print("ClimbClient: running")
end

-- Asked by the pause menu's Leave while you climb.
function ClimbClient.leave()
	local remote = ui.remote
	if remote then
		remote:FireServer("leave")
	end
end

ClimbClient.STAMP = "70b75f94"
return ClimbClient
