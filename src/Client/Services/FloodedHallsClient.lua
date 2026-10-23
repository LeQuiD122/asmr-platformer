--!strict
-- StarterPlayerScripts/Services/FloodedHallsClient.lua
-- The Flooded Halls' ending, played as a scene: the flume, the fall, and the gates at the bottom of it
-- all. FloodedHallsService decides everything (when the ride starts, where the rider is, when the run
-- is over); this only shows it. The last scene of the story (Townsfolk has the whole of it).
--
-- === On the rider's own screen (Cinema) ===
--
--   THE FLUME      drawn by this client, from the path the server wrote down (FlumePath), on a smooth
--                  curve through it and on this client's own clock, so it does not judder. You lie back
--                  in the water running down the trough, feet first, spray thrown up behind you, and
--                  what you think comes up over your head (THOUGHTS). Over your shoulder into the tube;
--                  chasing you down it; from the shaft's wall as you come round towards it; from just
--                  ahead, looking back at you; from below as you shoot out of the end of it (hit); and
--                  from above as you fall into the dark. A growl, from far below, before anything shows.
--   THE MOUTH      at the bottom of the fall there is something in the dark, and it is not lit until it
--                  has you. Falling on into nothing; then the light comes up in it all at once and it
--                  OPENS, a roar and an impact frame, and time all but stops: from over you, a speck over
--                  a mouth that fills the shaft; from beyond its teeth, you hanging over it; then you
--                  drop, and from inside it you are seen coming down into it; from its side, in profile,
--                  the jaws shut like a trap. Black. A heartbeat. "The Hold. It keeps what it is given."
--                  (Maw.lua; on your screen only, and nothing but its mouth is ever seen.)
--   THE DARK       the server moves you while it is black, and you come up in the GATE CHAMBER, the
--                  lowest room of the waterworks, as if you had been spat out into its sump.
--   THE SUMP       you come up out of the water and climb the ladder.
--   THE ROOM       one minute to midnight: Outfalls 1 and 2 already open, Outfall 3 shut.
--   THE WHEEL      you walk to it. The key is in your pocket; it was all along. It turns.
--   THE GATE       you turn the wheel and Outfall 3 grinds up; the bay starts to go out through it,
--                  daylight comes up at the end of the outfall, the lamps come on one by one and the
--                  sump drains.
--   MIDNIGHT       the clock on the wall reaches twelve.
--   THE LAST LINE  "14 August. 9:14 in the morning." And then LEVEL COMPLETE, and the room is yours
--                  for a few seconds before the lobby takes you.
--   OR, CLOCKED IN (the true ending, the hundred-and-fifteenth pass; below, at TRUE): someone walks up Outfall 3
--                  out of the daylight. Edwin Marsh, with his face. He stops at the gate and waves, as he waved
--                  the night he went down, and you wave back; then he goes back out into the morning, and it is
--                  15 August.
--
-- Everything the scene changes in the room (the gate, the wheel, the lamps, the clock, the water) is
-- changed on this screen only: each rider opens their own gates.
--
-- === Clocking in (the hundred-and-fourteenth pass) ===
--
-- The time clock by Mr Barlow on the gangway (StoryService): once you know what it cost the one before you, "Clock in"
-- stands you at it and a short scene plays on your screen. YOUR CARD, over your shoulder: it comes out of the rack and
-- into the slot, a soft heavy punch, and it says CLOCKED IN. ON SHIFT, from along the deck: you at the clock and Mr
-- Barlow beside it as he says his piece. Then the camera is yours again, the card stays punched on your screen, and the
-- clock's prompt is gone from it.
--
-- === On everyone's ===
--
-- The rider lies back on the way down the flume and rides it the way a person would: balancing, then
-- grabbing at the walls and scrabbling, then flailing as they shoot out of the end (Poses.flume).
--
-- === The lamps behind you ===
--
-- The halls are failing as you go through them: the roof lights two bays and more behind you stutter and
-- sink to a low glow, with a faint click, and if you are sent back past them (a checkpoint behind) they
-- come up again. On your own screen only, and only the roof lights: the bay you are in and everything
-- ahead stay lit, and the windows are never touched, so nothing is ever dark. The one fitting that fails
-- on everyone's screen (FloodedHallsService's Failing light) is left to the server.
--
-- === Sounds ===
--
-- Built-in sounds that every place has, unless SoundService has a folder StorySounds with Sounds
-- named GateGroan, WaterRush and Siren in it (audio/gen_story_sfx.py makes all three; import them and
-- put them there, and they are used instead). The siren is only heard if you have given it one.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")

local Poses: any = (function()
	local found = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Poses", 15)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()
local Cinema: any = (function()
	local found = script.Parent and script.Parent:WaitForChild("Cinema", 15)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()
local Maw: any = (function()
	local found = script.Parent and script.Parent:WaitForChild("Maw", 15)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()
local HallRoute: any = (function()
	local found = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HallRoute", 15)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()

local FloodedHallsClient = {}
FloodedHallsClient.VERSION = "the hundred-and-fifteenth pass, 2026-10-21"

local GROAN = "rbxasset://sounds/bass.mp3"
local RUSH = "rbxasset://sounds/impact_water.mp3"
local SPLASH = "rbxasset://sounds/impact_water.mp3"
local CLICK = "rbxasset://sounds/switch3.wav"
local WIND = "rbxasset://sounds/action_falling.mp3"
local BASS = "rbxasset://sounds/bass.mp3"

-- A sound for the scene: the place's own recording of it if there is one, else a built-in slowed down.
local function sound(name: string?, fallback: string?, volume: number, speed: number, looped: boolean): Sound?
	local folder = SoundService:FindFirstChild("StorySounds")
	local own = name and folder and folder:FindFirstChild(name)
	local made: Sound
	if own and own:IsA("Sound") then
		made = own:Clone()
	elseif fallback then
		made = Instance.new("Sound")
		made.SoundId = fallback
		made.PlaybackSpeed = speed
	else
		return nil
	end
	made.Volume = volume
	made.Looped = looped
	made.Parent = SoundService
	made:Play()
	return made
end

local function ease(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- ===== THE POSES =====
--
-- Riders on the flume, for everyone; and this player's own body in the chamber (climbing, the key,
-- the wheel), set after the animations every frame.
type Posed = { began: number, ends: number, model: Instance?, joints: { [string]: any }? }
local riders: { [Player]: Posed } = {}
local mine: { shape: string, began: number }? = nil
local mineJoints: { model: Instance?, joints: { [string]: any }? } = { model = nil, joints = nil }
local stepped: RBXScriptConnection? = nil

local function applyShape(joints: { [string]: any }, shape: string, t: number, w: number)
	local r6 = Poses.isR6(joints)
	local fn = Poses[shape]
	if not fn then
		return
	end
	for name, joint in pairs(joints) do
		local turn = fn(name, t, w, r6)
		if turn then
			Poses.drive(joint, turn)
		end
	end
end

local function release(joints: { [string]: any }?)
	if joints then
		for _, joint in pairs(joints) do
			Poses.drive(joint, CFrame.identity)
		end
	end
end

local function poseEveryone()
	local now = workspace:GetServerTimeNow()
	for player, r in pairs(riders) do
		local character = player.Character
		if not character or not player.Parent or now > r.ends then
			release(r.joints)
			riders[player] = nil
		elseif now >= r.began then
			if r.model ~= character then
				r.model = character
				r.joints = Poses.joints(character)
			end
			local joints = r.joints
			if joints then
				applyShape(joints, "flume", now - r.began, Poses.weight(now - r.began, r.ends - r.began))
			end
		end
	end
	local own = mine
	local character = Players.LocalPlayer.Character
	if own and character then
		if mineJoints.model ~= character then
			mineJoints.model = character
			mineJoints.joints = Poses.joints(character)
		end
		local joints = mineJoints.joints
		if joints then
			local t = os.clock() - own.began
			applyShape(joints, own.shape, t, math.clamp(t / 0.4, 0, 1))
		end
	end
	local hook = stepped
	if hook and next(riders) == nil and not mine then
		hook:Disconnect()
		stepped = nil
	end
end

local function posing()
	if Poses and not stepped then
		stepped = RunService.Stepped:Connect(function()
			pcall(poseEveryone)
		end)
	end
end

local function holdMine(shape: string?)
	if not Poses then
		return
	end
	if shape then
		mine = { shape = shape, began = os.clock() }
		posing()
	else
		mine = nil
		release(mineJoints.joints)
	end
end

-- ===== THE SCENE =====
type Scene = { began: number, slide: number, gates: number, halls: Instance, chamber: Instance?, frame: CFrame?,
	done: { [string]: boolean }, sounds: { Sound }, speed: number?, arrived: boolean, fallEye: Vector3?,
	gateRest: CFrame?, wheelRest: CFrame?, maw: number, mouth: any, fallFrom: Vector3?, heart: Sound?,
	rumble: Sound?, lastFall: Vector3?, path: { CFrame }?, rush: Sound?, clockAt: number, exitFrame: CFrame?,
	thought: number, wake: Instance?, growl: Sound?, exitSpeed: number?, fallM: number?, fallD: number?,
	tumble: number?, lit: any?, mawRest: CFrame?, lungeAt: number?, trueEnd: boolean, marsh: Model?, marshRest: CFrame?,
	marshJoints: { [string]: any }?, marshParts: { Instance }, throat: any?, swallowed: boolean?, crunched: number? }
local scene: Scene? = nil
local hallsEvent: RemoteEvent? = nil

local function once(current: Scene, key: string): boolean
	if current.done[key] then
		return false
	end
	current.done[key] = true
	return true
end

-- THE DARK. Out of the end of the tube the shaft goes black on this screen: no light from the sky or the air (ambient,
-- the environment's light), the shaft's own lamps all but out, a cold grade over everything, and only a faint light on
-- you (as if from the tube's mouth above), so you are seen falling and nothing under you is, until the mouth lights
-- itself. NOT FOG. The first dark thickened the air to 0.82, more than twice the thickest of any level's (the halls'
-- own notes say 0.42 already erased the water), and the black air hid the mouth even when it was lit: it was reported
-- as gone. The air is made black here at the level's own thickness or less. Put back as the chamber starts, or
-- whenever the scene ends, with anything still fading stopped first.
-- DARK, NOT BLACK (2026-10-18, from your fourth test: "too dark, I can't see anything other than the glowing light; I
-- need to see the player, but not so bright that I can see the surroundings"). The light from the air was taken to
-- 5, 5, 7 under an exposure turned down, a sixth of the halls' own: only the mouth's lamps showed, and you were not a
-- figure but nothing. Now the air keeps two thirds of the halls' light, cold, and the exposure is left nearly as it
-- was; what hides the halls is the black air (no thicker than the level's), which swallows anything a few tens of
-- studs off. And a lamp hangs a little over you as you fall, as if from the tube's mouth above, so you are always seen.
type Lit = { ambient: Color3, outdoor: Color3, brightness: number, exposure: number, diffuse: number, specular: number,
	density: number?, colour: Color3?, decay: Color3?, haze: number?, glare: number?, grade: ColorCorrectionEffect,
	glimmer: PointLight?, lamp: Attachment?, pour: ParticleEmitter?, dimmed: { [Light]: number }, off: { Light },
	tweens: { Tween } }
local DARK = { ambient = Color3.fromRGB(24, 26, 34), exposure = -0.1, colour = Color3.fromRGB(5, 5, 7), airAtMost = 0.36,
	dim = 0.08, reach = 90, over = 7 }
local function darken(current: Scene, root: BasePart)
	if current.lit then
		return
	end
	local Lighting = game:GetService("Lighting")
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "HoldDark"
	grade.Brightness = 0
	grade.Parent = Lighting
	local lit: Lit = { ambient = Lighting.Ambient, outdoor = Lighting.OutdoorAmbient, brightness = Lighting.Brightness,
		exposure = Lighting.ExposureCompensation, diffuse = Lighting.EnvironmentDiffuseScale,
		specular = Lighting.EnvironmentSpecularScale, density = if atmosphere then atmosphere.Density else nil,
		colour = if atmosphere then atmosphere.Color else nil, decay = if atmosphere then atmosphere.Decay else nil,
		haze = if atmosphere then atmosphere.Haze else nil, glare = if atmosphere then atmosphere.Glare else nil,
		grade = grade, glimmer = nil, pour = nil, dimmed = {}, off = {}, tweens = {} }
	current.lit = lit
	local fade = TweenInfo.new(1.2, Enum.EasingStyle.Sine)
	local function tween(target: Instance, goal: { [string]: any })
		local made = TweenService:Create(target, fade, goal)
		table.insert(lit.tweens, made)
		made:Play()
	end
	tween(Lighting, { Ambient = DARK.ambient, OutdoorAmbient = DARK.ambient, Brightness = 0,
		ExposureCompensation = DARK.exposure, EnvironmentDiffuseScale = 0, EnvironmentSpecularScale = 0 })
	if atmosphere then
		tween(atmosphere, { Density = math.min(atmosphere.Density, DARK.airAtMost), Color = DARK.colour, Decay = DARK.colour,
			Haze = 0, Glare = 0 })
	end
	tween(grade, { Brightness = 0, Contrast = 0.14, Saturation = -0.25, TintColor = Color3.fromRGB(212, 218, 236) })
	-- THE SHAFT'S OWN LAMPS, all but out on this screen: every light of the halls within DARK.reach of the shaft's
	-- middle (the mast). Not the mouth's, which it has with it, nor the one on you.
	local slideFrame = current.halls:GetAttribute("SlideFrame")
	local middle = if typeof(slideFrame) == "CFrame" then slideFrame.Position else root.Position
	for _, item in ipairs(current.halls:GetDescendants()) do
		if item:IsA("Light") and item.Enabled and item.Brightness > 0 then
			local holder = item.Parent
			local at = if holder and holder:IsA("BasePart") then holder.Position
				elseif holder and holder:IsA("Attachment") then holder.WorldPosition
				else nil
			if at and Vector3.new(at.X - middle.X, 0, at.Z - middle.Z).Magnitude < DARK.reach then
				if holder and holder:GetAttribute("Failing") then
					-- The failing fitting: the server sets its brightness many times a second (its stutter), so it is
					-- switched off here for the scene instead.
					item.Enabled = false
					table.insert(lit.off, item)
				else
					lit.dimmed[item] = item.Brightness
					tween(item, { Brightness = item.Brightness * DARK.dim })
				end
			end
		end
	end
	-- A cold light on you, so you are a figure in the dark and not nothing.
	local head = root.Parent and root.Parent:FindFirstChild("Head")
	local glimmer = Instance.new("PointLight")
	glimmer.Name = "FallGlimmer"
	glimmer.Color = Color3.fromRGB(170, 190, 230)
	glimmer.Brightness = 1.2
	glimmer.Range = 14
	glimmer.Shadows = false
	glimmer.Parent = if head and head:IsA("BasePart") then head else root
	lit.glimmer = glimmer
	-- AND A LAMP OVER YOU, falling with you (the fall moves it, DARK.over studs above): a light from inside the head
	-- lights the shoulders and not the face, and this lights you from above as the tube's mouth would, all the way
	-- down. Its reach is short, so it finds you and not the walls.
	local lamp = Instance.new("Attachment")
	lamp.Name = "FallLamp"
	lamp.WorldPosition = root.Position + Vector3.new(0, DARK.over, 0)
	lamp.Parent = workspace.Terrain
	local over = Instance.new("PointLight")
	over.Color = Color3.fromRGB(176, 196, 232)
	over.Brightness = 1.4
	over.Range = 18
	over.Shadows = false
	over.Parent = lamp
	lit.lamp = lamp
	-- The water pouring off the flume's lip, on this screen, off: in the dark it was a lit column down to the mouth.
	local spout = current.halls:FindFirstChild("FlumePour", true)
	local pour = spout and spout:FindFirstChildOfClass("ParticleEmitter")
	if pour then
		pour.Enabled = false
		lit.pour = pour
	end
end

-- The light put back: everything darken changed, as it was (anything still fading toward the dark stopped first, or
-- it would carry on into the light put back).
local function relight(current: Scene)
	local lit: Lit? = current.lit
	if not lit then
		return
	end
	current.lit = nil
	for _, made in ipairs(lit.tweens) do
		made:Cancel()
	end
	local Lighting = game:GetService("Lighting")
	Lighting.Ambient, Lighting.OutdoorAmbient = lit.ambient, lit.outdoor
	Lighting.Brightness, Lighting.ExposureCompensation = lit.brightness, lit.exposure
	Lighting.EnvironmentDiffuseScale, Lighting.EnvironmentSpecularScale = lit.diffuse, lit.specular
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and lit.density then
		atmosphere.Density = lit.density
		atmosphere.Color = lit.colour :: Color3
		atmosphere.Decay = lit.decay :: Color3
		atmosphere.Haze = lit.haze :: number
		atmosphere.Glare = lit.glare :: number
	end
	for light, brightness in pairs(lit.dimmed) do
		if light.Parent then
			light.Brightness = brightness
		end
	end
	for _, light in ipairs(lit.off) do
		light.Enabled = true
	end
	lit.grade:Destroy()
	if lit.glimmer then
		lit.glimmer:Destroy()
	end
	if lit.lamp then
		lit.lamp:Destroy()
	end
	if lit.pour then
		lit.pour.Enabled = true
	end
end

-- The throat put away, its red with it, and the picture steady again.
local function dropThroat(current: Scene)
	local throat = current.throat
	if throat then
		throat.model:Destroy()
		throat.tint:Destroy()
		current.throat = nil
	end
	if Cinema then
		Cinema.waver(0)
	end
end

local function endScene()
	local current = scene
	if not current then
		return
	end
	scene = nil
	holdMine(nil)
	relight(current)
	if current.wake then
		current.wake:Destroy()
		current.wake = nil
	end
	if Maw and current.mouth then
		Maw.destroy(current.mouth)
		current.mouth = nil
	end
	dropThroat(current)
	for _, s in ipairs(current.sounds) do
		if s.Parent then
			TweenService:Create(s, TweenInfo.new(2.5), { Volume = 0 }):Play()
			game:GetService("Debris"):AddItem(s, 3)
		end
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
		if current.speed then
			humanoid.WalkSpeed = current.speed
		end
	end
	if Cinema then
		Cinema.finish()
	end
end

local function keep(current: Scene, s: Sound?)
	if s then
		table.insert(current.sounds, s)
	end
end

-- WHERE THE RIDER IS, f of the way down, from the path the server wrote down: on a smooth curve through its
-- steps (Catmull-Rom), facing along the curve. It was straight lines from step to step, and the rider's speed and
-- heading changed with a jolt at every one of the 220: the judder in the ride was that.
local function pathAt(path: { CFrame }, f: number): CFrame
	local last = #path - 1
	local x = math.clamp(f, 0, 1) * last
	local i = math.min(math.floor(x), last - 1)
	local u = x - i
	local p0 = path[math.max(1, i)].Position
	local p1, p2 = path[i + 1].Position, path[i + 2].Position
	local p3 = path[math.min(#path, i + 3)].Position
	local at = 0.5 * (2 * p1 + (p2 - p0) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u * u
		+ (3 * p1 - p0 - 3 * p2 + p3) * u * u * u)
	local run = 0.5 * ((p2 - p0) + (2 * p0 - 5 * p1 + 4 * p2 - p3) * 2 * u + (3 * p1 - p0 - 3 * p2 + p3) * 3 * u * u)
	local turn = path[i + 1]:Lerp(path[i + 2], u)
	local up = turn.UpVector
	if run.Magnitude < 0.01 or math.abs(run.Unit:Dot(up)) > 0.98 then
		return turn - turn.Position + at
	end
	return CFrame.lookAt(at, at + run, up)
end

-- THE RIDER LIES BACK IN THE TROUGH, feet first. The path is a standing rider's (the server's, which check_halls
-- keeps inside the trough), and stood up in it they rode the flume like a statue on a moving walkway, which is how
-- it was reported. So the root is laid back by Poses.FLUME_RECLINE over Poses.FLUME_LIE seconds, let down LIE_DROP
-- onto the trough's floor, and Poses.flume bends the hips so the legs lie along it. Out of the end of the tube it
-- is held the way it came out and turned over onto its back, face up, which is how the mouth finds it.
local LIE_DROP = 2.4
local HELIX = 0.68 -- FloodedHallsService's SLIDE_HELIX: the share of the ride in the tube; the rest is the fall
local function lying(current: Scene, path: { CFrame }, frame: CFrame, f: number, t: number): CFrame
	local recline = if Poses then Poses.FLUME_RECLINE else math.rad(62)
	local w = ease(t / (if Poses then Poses.FLUME_LIE else 0.6))
	if f <= HELIX then
		return frame * CFrame.new(0, -LIE_DROP * w, 0) * CFrame.Angles(recline * w, 0, 0)
	end
	local exit = current.exitFrame or pathAt(path, HELIX)
	current.exitFrame = exit
	local out = (exit - exit.Position + frame.Position) * CFrame.new(0, -LIE_DROP, 0) * CFrame.Angles(recline, 0, 0)
	local flat = CFrame.new(frame.Position) * CFrame.Angles(math.pi / 2, 0, 0)
	return out:Lerp(flat, ease((f - HELIX) / (1 - HELIX) / 0.6))
end

-- WHAT GOES THROUGH THEIR HEAD on the way down, over it (Cinema.think): seconds in, the words, how long.
local THOUGHTS = {
	{ 1.0, "Staff only... and here I am.", 2.4 },
	{ 3.4, "It just keeps going down.", 2.2 },
	{ 5.6, "Too fast. Way too fast!", 1.9 },
	{ 7.7, "Where is the bottom?!", 1.6 },
	{ 9.7, "...what was that?", 1.3 },
}
local GROWL_AT = 0.84 -- f: the growl, from far below, before anything can be seen

-- THE WAKE: spray thrown up off the water in the trough as they go, on this screen. Gone when they leave the tube.
local function startWake(root: BasePart): Instance
	local at = Instance.new("Attachment")
	at.Name = "FlumeWake"
	at.CFrame = CFrame.new(0, -0.6, 0.6)
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(226, 244, 246))
	spray.LightEmission = 0.2
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.8) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	spray.Lifetime = NumberRange.new(0.35, 0.7)
	spray.Speed = NumberRange.new(5, 11)
	spray.SpreadAngle = Vector2.new(35, 35)
	spray.Acceleration = Vector3.new(0, -30, 0)
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Rate = 45
	spray.Parent = at
	local drops = Instance.new("ParticleEmitter")
	drops.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	drops.Color = ColorSequence.new(Color3.fromRGB(236, 250, 252))
	drops.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0.08) })
	drops.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	drops.Lifetime = NumberRange.new(0.3, 0.6)
	drops.Speed = NumberRange.new(8, 14)
	drops.SpreadAngle = Vector2.new(50, 50)
	drops.Acceleration = Vector3.new(0, -50, 0)
	drops.EmissionDirection = Enum.NormalId.Top
	drops.Rate = 30
	drops.Parent = at
	at.Parent = root
	return at
end

-- THE FLUME, f of the way down it.
local function flumeShot(current: Scene, root: BasePart, f: number)
	local here = root.Position
	local up = Vector3.yAxis
	-- The way the ride goes, from the path, not the root: the root lies back, so its front faces the roof. Past
	-- the end of the tube, the way it was going as it came out (straight down has no way along).
	local path = current.path
	local look = if path then pathAt(path, math.min(f, HELIX - 0.005)).LookVector else root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
	local slideFrame = current.halls:GetAttribute("SlideFrame")
	local axis = if typeof(slideFrame) == "CFrame" then slideFrame.Position else here
	local out = Vector3.new(here.X - axis.X, 0, here.Z - axis.Z)
	out = if out.Magnitude > 0.05 then out.Unit else Vector3.xAxis
	local character = Players.LocalPlayer.Character
	local ignore = if character then { character } else {}
	if f < 0.09 then
		-- OVER THE SHOULDER, into the tube.
		local eye = Cinema.clear(here - flat * 10 + up * 5, here, ignore)
		Cinema.point(CFrame.lookAt(eye, here + flat * 10 - up * 3), 62)
		Cinema.speedLines(0.12)
	elseif f < 0.34 and path then
		-- CHASING: behind the rider along the trough and a little over it, the tube ahead of them.
		local behind = pathAt(path, f - 0.045)
		local eye = behind.Position + behind.UpVector * 4.2 + Vector3.new(0, 1.5, 0)
		Cinema.point(CFrame.lookAt(eye, here + look * 6 + up * 0.8), 70)
		Cinema.speedLines(0.3)
	elseif f < 0.5 then
		-- FROM THE SHAFT'S WALL, as they come round towards it: never across the mast from them.
		if once(current, "wall") then
			local ahead = CFrame.Angles(0, 0.9, 0) * out
			current.fallEye = Vector3.new(axis.X, here.Y - 10, axis.Z) + ahead * 55
			Cinema.cut()
		end
		Cinema.point(CFrame.lookAt(current.fallEye :: Vector3, here + Vector3.new(0, 1, 0)), 46)
		Cinema.speedLines(0.2)
	elseif f < 0.64 and path then
		-- FROM JUST AHEAD, looking back at them: lying back, holding on, the helix going up behind. Always a point IN
		-- the tube: with the end of it near, the point ahead was out past it in the air, and the camera hung over the
		-- end of the tube while they went through it (check_shots.py found it).
		local ahead = pathAt(path, math.min(HELIX - 0.005, f + 0.04))
		local eye = ahead.Position + ahead.UpVector * 3 + Vector3.new(0, 1, 0)
		Cinema.point(CFrame.lookAt(eye, here + Vector3.new(0, 1, 0)), 64)
		Cinema.speedLines(0.45)
	elseif f < 0.8 then
		-- FROM BELOW THE END OF THE TUBE, waiting there a moment before they reach it (where they are going), then as
		-- they shoot out of it and past: the water's rush left behind in the tube, and only the air now.
		if once(current, "below") then
			local exit = if path then pathAt(path, HELIX - 0.005) else nil
			local endAt = if exit then exit.Position else here
			local endRun = if exit then Vector3.new(exit.LookVector.X, 0, exit.LookVector.Z) else flat
			endRun = if endRun.Magnitude > 0.05 then endRun.Unit else flat
			current.fallEye = endAt - up * 34 + Vector3.new(endRun.Z, 0, -endRun.X) * 16 + endRun * 10
			Cinema.cut()
		end
		if f >= HELIX and once(current, "wind") then
			local rush = current.rush
			if rush and rush.Parent then
				TweenService:Create(rush, TweenInfo.new(0.6), { Volume = 0 }):Play()
			end
			keep(current, sound("PlungeWind", WIND, 0.5, 0.8, false))
		end
		Cinema.point(CFrame.lookAt(current.fallEye :: Vector3, here), 58)
		Cinema.speedLines(0.55)
	else
		-- FROM ABOVE, as they fall into the dark. Nothing below shows yet: whatever is down there is not lit.
		Cinema.point(CFrame.lookAt(here + up * 15 + flat * 3, here - up * 12), 74)
		Cinema.speedLines(0.65)
	end
end

-- THE BEATS OF THE GATE CHAMBER, in seconds after the server put the rider in it: long enough for every
-- caption to be read twice (FloodedHallsService's GATES.SECONDS is the whole, and the key comes out at
-- its KEY_AT, which is BEAT.key).
local BEAT = {
	climb = 3.6,
	room = 9.5,
	walk = 14,
	key = 14,
	wheel = 20,
	gate = 21,
	rush = 22,
	midnight = 30,
	last = 35,
}

-- ===== THE TRUE ENDING (the hundred-and-fifteenth pass; you chose it) =====
--
-- For a rider who clocked in at the time clock on the gangway (StoryService), the gates end differently. After
-- midnight, someone walks up Outfall 3 out of the daylight: EDWIN MARSH, the key holder before you, the one on the Deco
-- tower, in the dark clothes he wears there, the green ribbon at his neck, and his face. He stops at the gate. He waves,
-- as he waved to you from the dive board the night he went down, and you wave back. Then he goes back out into the
-- morning, and it is 15 August. On this screen only; every other screen and every other ending never shows him. The
-- beats, in seconds after the rider came up in the chamber (BEAT.last is the first), and FloodedHallsService's
-- GATES.TRUE makes the run that much longer:
local TRUE = { light = 35, face = 41.6, wave = 46.2, morning = 51.2, done = 57.2 }
-- Along Outfall 3, in the chamber's frame (its gate's line is at -41): where he stops, how fast he walks (studs a
-- second), and how far back into the light he goes.
local MARSH = { stop = -45, walk = 3.6, back = -78 }

-- A WALK, on his joints: the legs swinging from the hips, a knee giving as its leg comes through, the arms against them.
local function walkPose(name: string, t: number): CFrame?
	local s = math.sin(t * 5.4)
	if name == "RightHip" then
		return CFrame.Angles(s * 0.42, 0, 0)
	elseif name == "LeftHip" then
		return CFrame.Angles(-s * 0.42, 0, 0)
	elseif name == "RightKnee" then
		return CFrame.Angles(-math.max(0, s) * 0.5, 0, 0)
	elseif name == "LeftKnee" then
		return CFrame.Angles(-math.max(0, -s) * 0.5, 0, 0)
	elseif name == "RightShoulder" then
		return CFrame.Angles(-s * 0.3, 0, 0)
	elseif name == "LeftShoulder" then
		return CFrame.Angles(s * 0.3, 0, 0)
	end
	return nil
end

local function trueStep(current: Scene, b: number)
	local frame = current.frame :: CFrame
	local function at(x: number, y: number, z: number): Vector3
		return frame * Vector3.new(x, y, z)
	end
	local ahead = frame.LookVector
	-- HIM: walking up out of the light, stopping at the gate, waving, turning and going back into it.
	local model = current.marsh
	if model and model.Parent and current.marshRest then
		local from = frame:PointToObjectSpace((current.marshRest :: CFrame).Position)
		local span = MARSH.stop - from.Z
		local z, yaw, seen, walking = MARSH.stop, 0, 1, false
		if b < TRUE.face then
			local u = math.clamp((b - TRUE.light - 0.6) * MARSH.walk / math.max(1, span), 0, 1)
			z = from.Z + span * u
			walking = u > 0 and u < 1
			seen = math.clamp((b - TRUE.light) / 0.8, 0, 1)
		elseif b >= TRUE.morning then
			yaw = math.pi * ease((b - TRUE.morning) / 0.8)
			local going = math.max(0, b - TRUE.morning - 0.8)
			z = math.max(MARSH.back, MARSH.stop - going * MARSH.walk)
			walking = going > 0 and z > MARSH.back
			seen = 1 - math.clamp((b - (TRUE.done - 2.6)) / 2.2, 0, 1)
		end
		local p = at(from.X, from.Y, z)
		model:PivotTo(CFrame.lookAt(p, p - ahead) * CFrame.Angles(0, yaw, 0))
		for _, item in ipairs(current.marshParts) do
			(item :: any).LocalTransparencyModifier = 1 - seen
		end
		local joints = current.marshJoints
		if Poses and joints then
			local r6 = Poses.isR6(joints)
			local raised = math.clamp((b - TRUE.wave) / 0.5, 0, 1) * math.clamp((TRUE.morning - b) / 0.5, 0, 1)
			for name, joint in pairs(joints) do
				local by: CFrame? = nil
				if walking then
					by = walkPose(name, b)
				elseif raised > 0 then
					by = Poses.wave(name, b - TRUE.wave, raised, r6)
				end
				Poses.drive(joint, by or CFrame.identity)
			end
		end
	end
	if b < TRUE.face then
		-- SOMEONE IN THE LIGHT: from behind you at the wheel, down Outfall 3 into the morning.
		if once(current, "true light") then
			Cinema.cut()
			Cinema.caption("Outfall 3", "Someone is walking up out of the morning.", 5)
		end
		Cinema.point(CFrame.lookAt(at(-6, 7, -12), at(0, 4, -60)), 50)
	elseif b < TRUE.wave then
		-- HIS FACE: at the gate, square on, close; the chord carried home.
		if once(current, "true face") then
			Cinema.cut()
			Cinema.caption("Edwin Marsh", "Key holder, 1979. He has his face back.", 5)
			local chord = sound("MorningChord", nil, 0.7, 1, false) or sound("EndChord", nil, 0.7, 1, false)
			if chord then
				game:GetService("Debris"):AddItem(chord, 14)
			end
		end
		Cinema.point(CFrame.lookAt(at(0, 5.2, MARSH.stop + 7), at(0, 4.7, MARSH.stop)), 38)
	elseif b < TRUE.morning then
		-- THE WAVE: from the side, you at the wheel and him at the gate, both waving.
		if once(current, "true wave") then
			Cinema.cut()
			holdMine("wave")
			Cinema.caption("The wave", "He waved to you from the dive board, the night he went down. You wave back.", 5)
		end
		Cinema.point(CFrame.lookAt(at(17, 6, -27), at(-4, 3.5, -33)), 52)
	elseif b < TRUE.done then
		-- INTO THE MORNING: over your shoulder, him going back out into the light.
		if once(current, "true morning") then
			Cinema.cut()
			holdMine(nil)
			Cinema.caption("Harrow Bay", "15 August. The tide went out, and the day ended.", 6)
		end
		Cinema.point(CFrame.lookAt(at(-6.8, 5.3, -17), at(0, 5, -70)), 52)
	else
		endScene()
	end
end

-- THE GATE CHAMBER, `b` seconds after the server put the rider in it.
local function chamberStep(current: Scene, root: BasePart, humanoid: Humanoid, b: number)
	local chamber = current.chamber :: Instance
	local frame = current.frame :: CFrame
	local function at(x: number, y: number, z: number): Vector3
		return frame * Vector3.new(x, y, z)
	end
	local arrive = chamber:GetAttribute("Arrive")
	local ladder = chamber:GetAttribute("Ladder")
	local stand = chamber:GetAttribute("Stand")
	local waterY = chamber:GetAttribute("WaterY")
	if typeof(arrive) ~= "CFrame" or typeof(ladder) ~= "Vector3" or typeof(stand) ~= "CFrame" or typeof(waterY) ~= "number" then
		return
	end
	local ahead = frame.LookVector
	-- Wait for the server's move to arrive here (it happens in the dark).
	if not current.arrived then
		if (root.Position - arrive.Position).Magnitude < 14 or b > 1.2 then
			current.arrived = true
			Cinema.cut()
			-- Out of the dark: the mouth gone, the heartbeat going, the picture coming up.
			if Maw and current.mouth then
				Maw.destroy(current.mouth)
				current.mouth = nil
			end
			dropThroat(current)
			local heart = current.heart
			if heart and heart.Parent then
				TweenService:Create(heart, TweenInfo.new(2), { Volume = 0 }):Play()
			end
			Cinema.black(false, 2.2)
		else
			return
		end
	end

	if b < BEAT.climb then
		-- UP OUT OF THE SUMP AND UP THE LADDER.
		if once(current, "surface") then
			humanoid.PlatformStand = true
			holdMine("climb")
			keep(current, sound(nil, SPLASH, 0.8, 0.7, false))
			-- (Said, so it is plain what happened: it swallowed you, and it gave you back.)
			Cinema.think(Players.LocalPlayer.Character, "It... spat me out?", 2.6)
		end
		-- In the chamber's own axes: its +Z is back into the sump, away from the gates.
		local lad = frame:PointToObjectSpace(ladder)
		local surfaceAt = at(lad.X, waterY - frame.Y - 1.2, lad.Z + 1.3)
		local topAt = at(lad.X, lad.Y + 3, lad.Z + 0.6)
		local standAt = at(lad.X, lad.Y + 3, lad.Z - 2.4)
		local pos
		if b < 1.4 then
			pos = arrive.Position:Lerp(surfaceAt, ease(b / 1.4))
		elseif b < 3 then
			pos = surfaceAt:Lerp(topAt, ease((b - 1.4) / 1.6))
		else
			pos = topAt:Lerp(standAt, ease((b - 3) / 0.6))
		end
		root.CFrame = CFrame.lookAt(pos, pos + ahead)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		-- High enough over the floor to see down into the sump past its edge.
		Cinema.point(CFrame.lookAt(at(9, 8, 11), root.Position + Vector3.new(0, 1, 0)), 58)
		return
	end
	if once(current, "standing") then
		humanoid.PlatformStand = false
		holdMine(nil)
	end

	if b < BEAT.room then
		-- THE ROOM, from high by the gates: one minute to midnight.
		if once(current, "room") then
			Cinema.caption("Outfall Gates", "Harrow Bay Corporation Waterworks. One minute to midnight.", 7)
		end
		-- A slow push across the room while its caption is read.
		local u = ease((b - BEAT.climb) / (BEAT.room - BEAT.climb))
		Cinema.point(CFrame.lookAt(at(14, 17, -30):Lerp(at(9, 14, -24), u), at(-2, 3, 8)), 62)
	elseif b < BEAT.walk then
		-- THE WALK TO THE WHEEL.
		if once(current, "walk") then
			current.speed = humanoid.WalkSpeed
			humanoid.WalkSpeed = 9
			Cinema.cut()
		end
		if once(current, "walk" .. math.floor(b)) then
			humanoid:MoveTo(stand.Position)
		end
		if b > BEAT.walk - 0.3 and (root.Position - stand.Position).Magnitude > 1.5 then
			root.CFrame = CFrame.lookAt(stand.Position + Vector3.new(0, 3, 0), stand.Position + Vector3.new(0, 3, 0) + ahead)
		end
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		flat = if flat.Magnitude > 0.05 then flat.Unit else ahead
		local left = Vector3.new(-flat.Z, 0, flat.X)
		Cinema.point(CFrame.lookAt(root.Position - flat * 10 + Vector3.new(0, 4.5, 0) + left * 5, root.Position + flat * 8), 62)
	elseif b < BEAT.wheel then
		-- THE KEY.
		if once(current, "key") then
			humanoid:MoveTo(root.Position)
			local p = stand.Position + Vector3.new(0, 3, 0)
			root.CFrame = CFrame.lookAt(p, p + ahead)
			holdMine("key")
			Cinema.caption("The key", "It was in your pocket the whole time.", 7)
			Cinema.cut()
		end
		if b > BEAT.key + 2.4 and once(current, "click") then
			keep(current, sound(nil, CLICK, 0.9, 0.55, false))
		end
		-- Low, ahead of you and to your right, looking up: your face over the lock as the key goes in, the wheel beside
		-- you. (It looked at the lock from your side, with you half out of the picture: check_shots.py.)
		Cinema.point(CFrame.lookAt(at(-2, 3.6, -25.5), at(-8, 3.8, -21.1)), 46)
	elseif b < BEAT.midnight then
		-- THE WHEEL, AND THE GATE GOING UP.
		if once(current, "wheel") then
			holdMine("wheel")
			Cinema.cut()
		end
		local axis = chamber:GetAttribute("WheelAxis")
		local wheel = chamber:FindFirstChild("Wheel")
		if typeof(axis) == "CFrame" and wheel and wheel:IsA("Model") then
			current.wheelRest = current.wheelRest or wheel:GetPivot()
			local turn = (b - BEAT.wheel) * 1.7
			wheel:PivotTo(axis * CFrame.Angles(0, 0, -turn) * axis:ToObjectSpace(current.wheelRest :: CFrame))
		end
		local gate = chamber:FindFirstChild("Gate3")
		if b > BEAT.gate and gate and gate:IsA("Model") then
			current.gateRest = current.gateRest or gate:GetPivot()
			if once(current, "groan") then
				local groan = sound("GateGroan", GROAN, 0.9, 0.35, true)
				keep(current, groan)
				if groan then
					task.delay(7.8, function()
						if groan.Parent then
							TweenService:Create(groan, TweenInfo.new(1.2), { Volume = 0 }):Play()
						end
					end)
				end
			end
			gate:PivotTo((current.gateRest :: CFrame) + frame.UpVector * 27 * ease((b - BEAT.gate) / 7.5))
		end
		if b > BEAT.rush and once(current, "rush") then
			Cinema.caption("Outfall 3", "For the first time in three days, the tide is going out.", 7)
			keep(current, sound("WaterRush", RUSH, 0.9, 0.4, true))
			-- The bay going out under the gate: spray off the foot of it, along the outfall.
			local foot = Instance.new("Part")
			foot.Name = "OutfallSpray"
			foot.Anchored = true
			foot.CanCollide = false
			foot.CanQuery = false
			foot.CanTouch = false
			foot.Transparency = 1
			foot.Size = Vector3.new(20, 1, 1)
			foot.CFrame = frame * CFrame.new(0, 0.5, -40)
			foot.Parent = chamber
			local spray = Instance.new("ParticleEmitter")
			spray.Texture = "rbxasset://textures/particles/smoke_main.dds"
			spray.Color = ColorSequence.new(Color3.fromRGB(214, 236, 232))
			spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4) })
			spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
			spray.Lifetime = NumberRange.new(0.8, 1.6)
			spray.Speed = NumberRange.new(18, 30)
			spray.SpreadAngle = Vector2.new(25, 12)
			spray.EmissionDirection = Enum.NormalId.Front
			spray.Acceleration = Vector3.new(0, -12, 0)
			spray.Rate = 90
			spray.Parent = foot
			local daylight = chamber:FindFirstChild("Daylight", true)
			local light = daylight and daylight:FindFirstChildOfClass("SurfaceLight")
			if light then
				TweenService:Create(light, TweenInfo.new(6, Enum.EasingStyle.Sine), { Brightness = 1.8 }):Play()
			end
		end
		-- The lamps, one after another, and the sump going down.
		for _, lamp in ipairs(chamber:GetChildren()) do
			if lamp.Name == "GateLamp" then
				local order = lamp:GetAttribute("Order")
				if typeof(order) == "number" and b > BEAT.rush + 1.1 + order * 0.8 and once(current, "lamp" .. order) then
					local light = lamp:FindFirstChildOfClass("PointLight")
					if light then
						TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 1.1 }):Play()
					end
				end
			end
		end
		local centre, size = chamber:GetAttribute("SumpCentre"), chamber:GetAttribute("SumpSize")
		if typeof(centre) == "Vector3" and typeof(size) == "Vector3" then
			for step = 1, 3 do
				if b > BEAT.rush + 1 + step * 1.8 and once(current, "drain" .. step) then
					local top = centre.Y + size.Y / 2 - (step - 1) * size.Y / 3
					pcall(function()
						workspace.Terrain:FillBlock(CFrame.new(centre.X, top - size.Y / 6, centre.Z) * (frame - frame.Position),
							Vector3.new(size.X + 4, size.Y / 3 + 1, size.Z + 4), Enum.Material.Air)
					end)
				end
			end
		end
		-- Behind you and to your left, easing in: you at the wheel in the lower half of the picture, from the waist up,
		-- and the gate going up behind you. (It looked up at the gate and left you under the bottom bar.)
		local push = ease((b - BEAT.wheel) / (BEAT.midnight - BEAT.wheel))
		local eye = at(-13, 6, -8):Lerp(at(-12, 6, -12), push)
		Cinema.point(CFrame.lookAt(eye, at(-4, 9, -34)), 70)
	elseif b < BEAT.last then
		-- MIDNIGHT.
		local face = chamber:GetAttribute("ClockFace")
		if once(current, "midnight") then
			holdMine(nil)
			Cinema.caption("Midnight", "Somewhere far above, the siren. It is not a test.", 7)
			keep(current, sound("Siren", nil, 0.7, 1, false))
		end
		if typeof(face) == "CFrame" then
			local tick = ease((b - BEAT.midnight - 0.8) / 0.5)
			for _, hand in ipairs({ { "GateClockHour", (11 + 59 / 60) * 30, 360, 1.3 }, { "GateClockMinute", 59 * 6, 360, 2 } }) do
				local part = chamber:FindFirstChild(hand[1] :: string)
				if part and part:IsA("BasePart") then
					local from, to, long = hand[2] :: number, hand[3] :: number, hand[4] :: number
					local angle = math.rad(from + (to - from) * tick)
					part.CFrame = face * CFrame.Angles(0, 0, -angle) * CFrame.new(0, long / 2, 0)
				end
			end
			-- Square on to the face, from seven studs out into the room.
			Cinema.point(CFrame.lookAt(face * Vector3.new(0, 0, 7), face.Position), 42, true)
		end
	elseif current.trueEnd then
		trueStep(current, b)
	elseif b < current.gates + 0.8 then
		-- THE LAST LINE, pushing in from behind the rider toward the open gate and the light.
		if once(current, "last") then
			Cinema.caption("Harrow Bay", "14 August. 9:14 in the morning.", 7)
			-- The only chord of the four endings that resolves, left to ring out after the scene.
			local chord = sound("HallsChord", nil, 0.7, 1, false) or sound("EndChord", nil, 0.7, 1, false)
			if chord then
				game:GetService("Debris"):AddItem(chord, 12)
			end
		end
		local u = ease((b - BEAT.last) / math.max(1, current.gates - BEAT.last))
		local eye = at(-8, 5.5, -12):Lerp(at(-3, 8, -30), u)
		Cinema.point(CFrame.lookAt(eye, at(0, 12, -95)), 60 - 5 * u)
	else
		endScene()
	end
end

-- THE MOUTH, `m` seconds after the fall out of the tube ends. The one moment in the game meant to frighten, so it
-- does not show itself until it has you. You fall on into the black with the growl still in your ears; then the light
-- comes up in it all at once and it LUNGES up out of the dark at you, jaws springing open, a roar and an impact frame;
-- time all but stops with you hanging over a mouth that fills the shaft, seen past you from above at an angle, so its
-- teeth ring the gullet and it can only be a mouth, and you twist over in the air to look down at it; then YOUR FACE,
-- close, from under it, lit green from below, as you see what it is; then you drop in, seen from inside it (your face
-- coming at it, not your back); then from above, wide, it shuts on you. Its beats, in seconds:
-- Every shot in it at least eight tenths of a second, so it can be seen (check_shots.py): they were half that, and the
-- whole of it was over in three and a half seconds of cuts. Only the bite itself is a slam.
local JAWS = {
	dark = 0.45, -- falling on, fast, into nothing
	reveal = 0.8, -- the light comes up in it and it lunges up at you, opening
	face = 1.8, -- past you from above at an angle: a speck over a mouth that fills the shaft, turning over to look
	into = 3.1, -- your face, close, from under it, lit from below by the mouth: "No. No no no no."; then you drop
	bite = 4.1, -- from inside it, looking up at you coming down into it
	snap = 5.0, -- from above, wide: it creaks shut, and SLAMS on you
	crunch = 6.2, -- and crunches down twice more (CRUNCHES) before the dark
	caption = 6.4, -- in the dark: the one line
}
-- THE JAWS, LONGER AND HARDER (the hundred-and-thirty-second pass, from your test: "the jaws need to snap longer, and
-- create lots of impact"): CREAK seconds before the slam they start to close, slowly, then slam; after it, at each of
-- CRUNCHES (seconds after the slam), they give a little and bite down again.
local CREAK = 0.9
local CRUNCHES = { 0.45, 0.9 }
-- Where it waits, and how far it lunges: MAW_DEEP under the end of the tube's fall in the dark, then MAW_RISE up at you.
-- HANG: how fast you fall while time all but stops over it (studs a second).
local MAW_DEEP, MAW_RISE, LUNGE = 116, 34, 0.55
local HANG = 2
-- TURNING OVER to look: from lying on your back (as you came out of the tube) to face down into it, TURN seconds from
-- a moment after it lights.
local TURN_AT, TURN = 0.1, 0.55

-- HOW FAST THEY FALL, `m` seconds into the mouth: as fast as they came out of the tube (`v0`), slowing as it comes
-- for them until they all but hang over it, then dropping in fast.
local function fallSpeed(m: number, v0: number): number
	if m < JAWS.dark then
		return v0 - 30 * m
	elseif m < JAWS.reveal then
		local from = v0 - 30 * JAWS.dark
		return from + (HANG - from) * ease((m - JAWS.dark) / (JAWS.reveal - JAWS.dark))
	elseif m < JAWS.into then
		return HANG
	elseif m < JAWS.into + 0.25 then
		return HANG + (45 - HANG) * ease((m - JAWS.into) / 0.25)
	end
	return 45 + 35 * (m - JAWS.into - 0.25)
end

-- SWALLOWED (the hundred-and-twenty-fourth pass, from your test: "the moment where there is the monster scene, like I
-- don't understand what is going on still"). After the jaws shut it was black for five seconds and then you were in
-- water. Now, down its throat: ribbed, wet, dark red, lit by its own slow pulse, you turning over and over as it swallows
-- you down (its rings going up past you), its heartbeat and the line; then it heaves, a rush of water and white, and it
-- spits you out into the sump of the Gate Chamber, where you come up thinking just that. THROAT's beats are from the
-- jaws' snap; it heaves SPIT seconds before the server moves you (GATES.MAW).
local THROAT = { from = 0.6, radius = 11, slats = 16, ribs = 7, gap = 9, speed = 7, spit = 0.9 }
-- AND WITH DRAMA (the hundred-and-thirty-second pass, from your test: "when I'm inside its throat it should be more
-- dramatic"): its heart beats every BEAT seconds, and on each beat its walls squeeze in SQUEEZE studs and its light flares,
-- the picture knocked; wet streaks rush up past you, the picture rolls and the speed is on.
local THROAT_BEAT, THROAT_SQUEEZE = 0.8, 1.6
type Throat = { model: Model, ribs: { Model }, base: Vector3, pulse: PointLight, made: number,
	walls: { { part: BasePart, rest: CFrame, out: Vector3 } }, tint: ColorCorrectionEffect, beats: number }

local function buildThroat(at: Vector3): Throat
	local model = Instance.new("Model")
	model.Name = "HoldThroat"
	local function part(parent: Instance, size: Vector3, cf: CFrame, colour: Color3): Part
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.14
		p.Size = size
		p.CFrame = cf
		p.Color = colour
		p.Parent = parent
		return p
	end
	-- The walls: slats round a tube, from over you on down.
	local walls = {}
	for k = 1, THROAT.slats do
		local a = k / THROAT.slats * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local mid = at + out * THROAT.radius - Vector3.new(0, 24, 0)
		local slat = part(model, Vector3.new(4.8, 90, 1.4), CFrame.lookAt(mid, mid - out), Color3.fromRGB(122, 34, 42))
		table.insert(walls, { part = slat, rest = slat.CFrame, out = out })
	end
	-- WET STREAKS rushing up past you as it swallows.
	local streaks = part(model, Vector3.new(THROAT.radius * 1.6, 1, THROAT.radius * 1.6), CFrame.new(at - Vector3.new(0, 30, 0)),
		Color3.new(0, 0, 0))
	streaks.Transparency = 1
	local wet = Instance.new("ParticleEmitter")
	wet.Name = "Wet"
	wet.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	wet.Color = ColorSequence.new(Color3.fromRGB(255, 196, 196))
	wet.LightEmission = 0.3
	wet.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.15) })
	wet.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	wet.Lifetime = NumberRange.new(0.6, 1)
	wet.Speed = NumberRange.new(40, 60)
	wet.EmissionDirection = Enum.NormalId.Top
	wet.Shape = Enum.ParticleEmitterShape.Box
	wet.Rate = 90
	wet.Parent = streaks
	-- The ribs: rings a little inside the wall, which the swallowing carries up past you.
	local ribs = {}
	for r = 1, THROAT.ribs do
		local rib = Instance.new("Model")
		rib.Name = "Rib"
		for k = 1, THROAT.slats do
			local a = (k + 0.5) / THROAT.slats * math.pi * 2
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local p = at + out * (THROAT.radius - 1.1)
			part(rib, Vector3.new(4.6, 1.6, 1.8), CFrame.lookAt(p, p - out), Color3.fromRGB(86, 20, 28))
		end
		rib.Parent = model
		table.insert(ribs, rib)
	end
	-- Its own slow pulse of red, on you.
	local glow = part(model, Vector3.new(1, 1, 1), CFrame.new(at + Vector3.new(0, 4, 0)), Color3.new(0, 0, 0))
	glow.Transparency = 1
	local pulse = Instance.new("PointLight")
	pulse.Color = Color3.fromRGB(255, 80, 70)
	pulse.Brightness = 1.4
	pulse.Range = 26
	pulse.Shadows = false
	pulse.Parent = glow
	model.Parent = workspace
	-- Its red over everything, while you are in it.
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "ThroatTint"
	tint.TintColor = Color3.fromRGB(255, 206, 204)
	tint.Contrast = 0.14
	tint.Saturation = 0.12
	tint.Parent = game:GetService("Lighting")
	return { model = model, ribs = ribs, base = at, pulse = pulse, made = os.clock(), walls = walls, tint = tint, beats = 0 }
end

local function throatStep(current: Scene, root: BasePart, m: number, side: Vector3)
	local held = current.lastFall
	if not held then
		return
	end
	local s = m - JAWS.snap - THROAT.from
	if not current.throat then
		current.throat = buildThroat(held)
		Cinema.cut()
		Cinema.black(false, 0.6)
		local lit: Lit? = current.lit
		if lit and lit.glimmer then
			lit.glimmer.Brightness = 0.9
		end
	end
	local throat: Throat = current.throat
	-- The rings, going up past you as it swallows: a rib every THROAT.gap studs, wrapping round.
	local shift = (s * THROAT.speed) % THROAT.gap
	for r, rib in ipairs(throat.ribs) do
		local y = -32 + (r - 1) * THROAT.gap + shift
		rib:PivotTo(CFrame.new(throat.base + Vector3.new(0, y, 0)))
	end
	-- ITS HEART: on every beat the walls squeeze in and spring back, its light flares, the picture is knocked.
	local beat = math.max(0, s) % THROAT_BEAT / THROAT_BEAT
	local squeeze = THROAT_SQUEEZE * math.exp(-beat * 5)
	for _, wall in ipairs(throat.walls) do
		wall.part.CFrame = wall.rest - wall.out * squeeze
	end
	throat.pulse.Brightness = 1 + 2.4 * math.exp(-beat * 6)
	local beats = math.floor(math.max(0, s) / THROAT_BEAT)
	if beats > throat.beats then
		throat.beats = beats
		Cinema.impact(0.3)
		Cinema.shake(1.1)
	end
	Cinema.shake(0.45)
	Cinema.speedLines(0.7)
	Cinema.waver(0.9)
	-- YOU, turning over and over, slowly, held in the middle of it.
	local spin = s * 0.9
	root.CFrame = CFrame.new(held) * CFrame.Angles(0, spin, 0) * CFrame.Angles(math.pi / 2, 0, 0.3)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	if s > 0.6 and once(current, "swallowed") then
		Cinema.think(Players.LocalPlayer.Character, "It swallowed me...", 2.4)
	end
	if s > 3.2 and once(current, "let me out") then
		Cinema.think(Players.LocalPlayer.Character, "Let me OUT!", 1.8)
	end
	-- FROM OVER YOU, down its throat: you turning in it, the rings coming up at us.
	Cinema.point(CFrame.lookAt(held + Vector3.new(0, 9, 0) + side * 2.5, held - Vector3.new(0, 6, 0), side), 72)
end

-- AFTER THE BITE, `m` seconds into the mouth: its line in the dark and its heartbeat; down its throat; then it heaves.
local function afterBite(current: Scene, root: BasePart, m: number, side: Vector3)
	if m > JAWS.caption and once(current, "keeps") then
		Cinema.caption("The Hold", "It keeps what it is given.", 7)
	end
	if m > JAWS.caption + 0.2 and once(current, "heart") then
		current.heart = sound("Heartbeat", BASS, 0.6, 0.45, true)
		keep(current, current.heart)
	end
	local spitAt = current.maw - THROAT.spit
	if m >= JAWS.crunch + THROAT.from and m < spitAt then
		throatStep(current, root, m, side)
	elseif m >= spitAt and once(current, "spat") then
		-- IT HEAVES: the walls clamp, a rush of water and white, and out.
		local throat = current.throat
		if throat then
			for _, wall in ipairs(throat.walls) do
				wall.part.CFrame = wall.rest - wall.out * (THROAT_SQUEEZE * 2.5)
			end
			throat.pulse.Brightness = 4
		end
		keep(current, sound(nil, SPLASH, 1, 0.55, false))
		keep(current, sound("MawRoar", BASS, 0.6, 0.3, false))
		Cinema.impact(1.6)
		Cinema.shake(2.8)
		Cinema.speedLines(0)
		Cinema.waver(0)
		Cinema.black(true, 0.3)
	end
end

local function mawStep(current: Scene, root: BasePart, humanoid: Humanoid, m: number)
	local mouth = current.mouth
	local from = current.fallFrom
	if not (mouth and from) then
		-- No mouth (no Maw module, or no attributes): the old way, a dip to black.
		if once(current, "dip") then
			Cinema.black(true, 0.8)
		end
		return
	end
	-- SWALLOWED: the mouth is gone from the picture, and the rest happens down its throat.
	if current.swallowed then
		afterBite(current, root, m, mouth.hinge.UpVector)
		return
	end
	local slideFrame = current.halls:GetAttribute("SlideFrame")
	local character = Players.LocalPlayer.Character
	local ignore = if character then { character, mouth.model } else { mouth.model }
	if once(current, "fall") then
		humanoid.PlatformStand = true
		holdMine("flail")
		current.rumble = sound("MawRumble", BASS, 0.9, 0.2, false)
		keep(current, current.rumble)
		Cinema.cut()
		darken(current, root)
		-- As fast as the end of the tube's fall: no jolt as one becomes the other.
		local path = current.path
		local n = if path then #path else 0
		current.exitSpeed = if path and n > 2 then (path[n].Position - path[n - 1].Position).Magnitude * (n - 1) / current.slide
			else 40
		current.fallM, current.fallD, current.tumble = 0, 0, 0
		-- HIT LIKE THE DIVE (the hundred-and-thirty-second pass, from your test: "I want as much impact when falling down
		-- in level 3 and 4 as in level 1"): out of the tube with a jolt.
		Cinema.impact(1)
		Cinema.shake(1.2)
	end
	-- THE LUNGE: up out of the dark at you, fast and then slowing, as it opens.
	local rest: CFrame = current.mawRest or mouth.hinge
	current.mawRest = rest
	local lunge = if m < JAWS.reveal then 0 else 1 - (1 - math.clamp((m - JAWS.reveal) / LUNGE, 0, 1)) ^ 3
	-- (Only while it rises: carrying every part of it each frame once it has stopped would be work for nothing.)
	if lunge ~= current.lungeAt then
		current.lungeAt = lunge
		Maw.place(mouth, rest + Vector3.new(0, MAW_RISE * lunge, 0))
	end
	local hinge: CFrame = mouth.hinge
	local opens = -hinge.LookVector
	local side = hinge.UpVector
	local axis = if typeof(slideFrame) == "CFrame" then slideFrame.Position else hinge.Position
	local inward = Vector3.new(axis.X - hinge.Position.X, 0, axis.Z - hinge.Position.Z)
	inward = if inward.Magnitude > 0.1 then inward.Unit else Vector3.xAxis
	-- THE RIDER falls on into it, turning over (slowly while time all but stops), and is held where the jaws close.
	local v0 = current.exitSpeed or 40
	local lastM = current.fallM or 0
	if m < lastM then
		lastM, current.fallD = 0, 0
	end
	local d = current.fallD or 0
	local s = lastM
	while s < m do
		local h = math.min(0.01, m - s)
		d += fallSpeed(s + h / 2, v0) * h
		s += h
	end
	-- Turned over to face it, the tumble all but stops: you go in face first, looking at it.
	local over = ease(math.clamp((m - JAWS.reveal - TURN_AT) / TURN, 0, 1))
	current.tumble = (current.tumble or 0) + (m - lastM) * 0.9 * math.clamp(fallSpeed(m, v0) / 45, 0.12, 1.2) * (1 - 0.75 * over)
	current.fallM, current.fallD = m, d
	local floor = hinge.Position.Y + 8
	local pos = from - Vector3.new(0, d, 0)
	if pos.Y < floor then
		pos = Vector3.new(pos.X, floor, pos.Z)
	end
	if m >= JAWS.snap then
		pos = current.lastFall or pos
	end
	current.lastFall = pos
	local tumble = current.tumble or 0
	root.CFrame = CFrame.new(pos) * CFrame.Angles(math.pi / 2 + tumble - math.pi * over, 0, tumble * 0.4)
	local lit: Lit? = current.lit
	if lit and lit.lamp then
		lit.lamp.WorldPosition = pos + Vector3.new(0, DARK.over, 0) + inward * 2
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	-- THE JAWS: shut in the dark; SPRUNG open as it lunges; breathing, slow, while you hang; then shut on you.
	local upper, lower = 0.04, 0.03
	if m >= JAWS.reveal and m < JAWS.snap - CREAK then
		local u = 1 - (1 - math.clamp((m - JAWS.reveal) / 0.35, 0, 1)) ^ 3
		local breath = 0.03 * math.sin((m - JAWS.reveal) * 2.2)
		upper, lower = 0.04 + (0.86 - 0.04) * u + breath, 0.03 + (0.72 - 0.03) * u + breath
	elseif m < JAWS.snap then
		-- CREAKING SHUT, slowly, a third of the way; then the slam.
		local creak = ease((m - (JAWS.snap - CREAK)) / (CREAK - 0.25))
		local slam = math.clamp((m - (JAWS.snap - 0.25)) / 0.25, 0, 1) ^ 3
		local up, lo = 0.86 - 0.3 * creak, 0.72 - 0.25 * creak
		upper, lower = up + (0.02 - up) * slam, lo + (0.02 - lo) * slam
	elseif m >= JAWS.snap then
		-- SHUT, and crunching: giving a little and biting down again, twice.
		local gape = 0
		for _, at in ipairs(CRUNCHES) do
			local w = (m - JAWS.snap - (at - 0.25)) / 0.25
			if w > 0 and w < 1 then
				gape = 0.14 * math.sin(math.pi * w ^ 0.6)
			end
		end
		upper, lower = 0.02 + gape, 0.02 + gape * 0.8
	end
	Maw.set(mouth, upper, lower)
	-- ITS LIGHT: nothing until it comes for you, then all at once (one stutter as it catches), then never steady.
	if m < JAWS.reveal then
		Maw.light(mouth, 0)
	elseif m < JAWS.reveal + 0.12 then
		Maw.light(mouth, 0.3)
	else
		Maw.light(mouth, 1, os.clock())
	end
	if m >= JAWS.reveal and once(current, "reveal") then
		-- IT COMES: a roar, an impact frame, the shaft shaking, its breath coming up out of it.
		keep(current, sound("MawRoar", BASS, 1, 0.32, false))
		local growl = current.growl
		if growl and growl.Parent then
			TweenService:Create(growl, TweenInfo.new(0.3), { Volume = 0 }):Play()
		end
		Cinema.impact(1.4)
		Cinema.shake(2.4)
		Cinema.speedLines(0)
		Maw.breathe(mouth, 10)
		Cinema.cut()
	end
	-- WHAT YOU SEE, said as you see it (the hundred-and-twenty-fourth pass: the test could not tell what it was).
	if m >= JAWS.reveal + 0.15 and once(current, "a mouth") then
		Cinema.think(character, "Is that... a MOUTH?!", 1.3)
	end
	if m >= JAWS.face + 0.05 and once(current, "no") then
		Cinema.think(character, "No. No no no no.", 1.6)
		-- (The light on you down to a glimmer for the close look at your face: with the mouth's own light coming up under
		-- you, it was washed out white.)
		local lit: Lit? = current.lit
		if lit and lit.glimmer then
			lit.glimmer.Brightness = 0.35
		end
	end
	if m < JAWS.reveal then
		-- FROM ABOVE, falling with you, into nothing: black under you, and the growl.
		Cinema.speedLines(0.65)
		Cinema.shake(0.45)
		Cinema.point(CFrame.lookAt(pos + Vector3.new(0, 9, 0) + inward * 3 + side * 1.5, pos - Vector3.new(0, 30, 0), side), 66)
	elseif m < JAWS.face then
		-- PAST YOU, FROM ABOVE AT AN ANGLE, into it: you in the top third of the picture, small, and under you a mouth
		-- that fills the shaft, its teeth ringing a gullet lit from inside; you twisting over to look. Easing in. (It
		-- looked further down, and you were above the picture, under the top bar, the whole shot: check_shots.py.)
		local k = ease((m - JAWS.reveal) / (JAWS.face - JAWS.reveal))
		local eye = pos + Vector3.new(0, 18 - 1 * k, 0) + inward * (20 - 2 * k) + side * 8
		local target = (hinge.Position + opens * 16):Lerp(pos, 0.62)
		Cinema.point(CFrame.lookAt(eye, target, Vector3.yAxis), 74 - 4 * k)
		Cinema.focus(nil)
	elseif m < JAWS.into then
		-- YOUR FACE, close, from under it (between you and the mouth): lit green from below, the dark above you, as you
		-- see what it is. The picture's up is your head's, so the face is the right way up in it.
		if once(current, "face") then
			Cinema.cut()
		end
		local headPart = character and character:FindFirstChild("Head")
		local face = if headPart and headPart:IsA("BasePart") then headPart.Position else pos
		local k = ease((m - JAWS.face) / (JAWS.into - JAWS.face))
		-- Under your face and out past the crown of your head (lying as you are, your chest and arms would be
		-- in the way straight under it).
		local crown = Vector3.new(root.CFrame.UpVector.X, 0, root.CFrame.UpVector.Z)
		crown = if crown.Magnitude > 0.1 then crown.Unit else inward
		local eye = face - Vector3.new(0, 4.4 - 0.8 * k, 0) + crown * 1.8 + side * 0.8
		Cinema.point(CFrame.lookAt(eye, face, root.CFrame.UpVector), 54 - 6 * k)
		Cinema.focus((face - eye).Magnitude, 0.6)
		Cinema.shake(0.4)
	elseif m < JAWS.bite then
		-- FROM INSIDE IT, low between the jaws, looking up at you coming down into it, the teeth either side.
		if once(current, "inside") then
			Cinema.cut()
		end
		local eye = hinge.Position + opens * 9 + inward * 5
		Cinema.point(CFrame.lookAt(eye, pos, side), 82)
		Cinema.focus((pos - eye).Magnitude, 0.35)
	elseif m < JAWS.crunch then
		-- FROM ABOVE, WIDE: the jaws creaking, then slamming shut on you, teeth through teeth, and crunching down.
		if once(current, "bite") then
			Cinema.cut()
			Cinema.focus(nil)
			-- The creak as they start to close.
			keep(current, sound("MawRumble", BASS, 0.7, 0.32, false))
		end
		if m > JAWS.snap - 0.05 and once(current, "snap") then
			-- THE SLAM: everything at once.
			keep(current, sound("JawsShut", BASS, 1, 0.3, false))
			keep(current, sound("MawRoar", BASS, 0.8, 0.26, false))
			Cinema.impact(2)
			Cinema.shake(3.8)
			Maw.breathe(mouth, 0)
		end
		for index, at in ipairs(CRUNCHES) do
			if m > JAWS.snap + at - 0.03 and (current.crunched or 0) < index then
				current.crunched = index
				keep(current, sound("JawsShut", BASS, 0.85 - 0.15 * index, 0.26 - 0.03 * index, false))
				Cinema.impact(1.1 - 0.25 * index)
				Cinema.shake(2.2 - 0.5 * index)
			end
		end
		if m > JAWS.snap then
			Cinema.shake(0.6)
		end
		Cinema.point(CFrame.lookAt(hinge.Position + opens * 55 + inward * 24 + side * 14, hinge.Position + opens * 22,
			Vector3.yAxis), 70)
	else
		-- BLACK as it shuts. Then DOWN ITS THROAT (throatStep), its heartbeat, the line; then it heaves and spits you out.
		if once(current, "dark") then
			Cinema.black(true)
			local rumble = current.rumble
			if rumble and rumble.Parent then
				TweenService:Create(rumble, TweenInfo.new(0.4), { Volume = 0 }):Play()
			end
			if Maw then
				Maw.destroy(mouth)
			end
			current.swallowed = true
		end
		afterBite(current, root, m, side)
	end
end

local function stepScene()
	local current = scene
	if not current then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid) or not current.halls.Parent then
		endScene()
		return
	end
	-- ON THIS CLIENT'S OWN CLOCK, set against the server's once when the ride began: the server's time read
	-- fresh every frame is corrected now and then as the clocks agree, and every correction was a hitch.
	local t = os.clock() - current.clockAt
	local f = t / current.slide
	if f < 1 then
		-- THE RIDE, drawn here: the rider's root on the path, every frame, lying back in the trough.
		local path = current.path
		if path and f >= 0 then
			humanoid.PlatformStand = true
			root.CFrame = lying(current, path, pathAt(path, f), f, t)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			if f < HELIX and not current.wake and once(current, "wake") then
				current.wake = startWake(root)
			end
		end
		if f >= HELIX then
			if current.wake then
				current.wake:Destroy()
				current.wake = nil
			end
			-- SHOT OUT OF THE END OF IT, into the air: hit, and the shaft goes black (THE DARK).
			if once(current, "shot out") then
				Cinema.impact(0.8)
				darken(current, root)
			end
		end
		if f >= 0.02 and once(current, "title") then
			Cinema.caption("The Corporation Baths", "Staff only beyond the flume.", 7)
		end
		-- WHAT THEY THINK, over their head as they go: where this goes, then that it does not stop.
		for index, thought in ipairs(THOUGHTS) do
			if index > current.thought and t >= thought[1] then
				current.thought = index
				Cinema.think(Players.LocalPlayer.Character, thought[2] :: string, thought[3] :: number)
			end
		end
		-- THE GROWL, from a long way down, before anything can be seen: low, felt more than heard.
		if current.mouth and f >= GROWL_AT and once(current, "growl") then
			current.growl = sound("MawGrowl", BASS, 0.6, 0.18, false)
			keep(current, current.growl)
			Cinema.shake(0.35)
		end
		-- THE MOUTH, in the dark under the end of the fall, before anyone could see it.
		if current.chamber and Maw and current.maw > 0 and f >= 0.6 and once(current, "mouth") then
			local plunge = current.halls:GetAttribute("PlungeEnd")
			local slideFrame = current.halls:GetAttribute("SlideFrame")
			if typeof(plunge) == "CFrame" and typeof(slideFrame) == "CFrame" then
				local from = plunge.Position
				local radial = Vector3.new(from.X - slideFrame.Position.X, 0, from.Z - slideFrame.Position.Z)
				radial = if radial.Magnitude > 0.1 then radial.Unit else Vector3.xAxis
				current.fallFrom = from
				-- MAW_DEEP down, in the dark, where nothing of it can be seen from the fall; it lunges up MAW_RISE at you
				-- (mawStep).
				current.mouth = Maw.build(Maw.facing(from - Vector3.new(0, MAW_DEEP, 0), Vector3.yAxis, Vector3.yAxis:Cross(radial)),
					workspace)
				-- Shut, and DARK: nothing of it shows until it opens (mawStep). It used to light up as you fell,
				-- so by the time it opened you had been looking at it for two seconds.
				Maw.set(current.mouth, 0.06, 0.05)
				Maw.light(current.mouth, 0)
			end
		end
		flumeShot(current, root, f)
		return
	end
	if not current.chamber or current.gates <= 0 then
		if t > current.slide + 1.5 then
			endScene()
		end
		return
	end
	if t < current.slide + current.maw then
		mawStep(current, root, humanoid, t - current.slide)
		return
	end
	-- The light back, in the black before the chamber.
	relight(current)
	chamberStep(current, root, humanoid, t - current.slide - current.maw)
end

local function started(player: Player, began: number, slide: number, gates: number, maw: number)
	if Poses then
		riders[player] = { began = began, ends = began + slide }
		posing()
	end
	-- (The mouth's time is part of the scene on the rider's own screen; everyone else just sees them
	-- keep falling into the dark.)
	if player ~= Players.LocalPlayer or not Cinema then
		return
	end
	local halls = workspace:FindFirstChild("FloodedHalls")
	if not halls then
		return
	end
	endScene()
	local chamber = halls:FindFirstChild("GateChamber")
	local frame = chamber and chamber:GetAttribute("Frame")
	-- THE PATH THE SERVER WROTE DOWN, read once: with it, this client draws the ride and says so.
	local path: { CFrame }? = nil
	local samples = halls:FindFirstChild("FlumePath")
	local count = samples and samples:GetAttribute("Samples")
	if samples and typeof(count) == "number" then
		local list: { CFrame }? = {}
		for k = 0, count do
			local value = samples:FindFirstChild(tostring(k))
			if not (value and value:IsA("CFrameValue")) then
				list = nil
				break
			end
			table.insert(list :: { CFrame }, value.Value)
		end
		path = list
	end
	scene = { began = began, slide = slide, gates = gates, halls = halls, chamber = chamber,
		frame = if typeof(frame) == "CFrame" then frame else nil, done = {}, sounds = {}, speed = nil,
		arrived = false, fallEye = nil, gateRest = nil, wheelRest = nil, maw = maw, mouth = nil, fallFrom = nil,
		heart = nil, rumble = nil, lastFall = nil, path = path, rush = nil,
		clockAt = os.clock() - (workspace:GetServerTimeNow() - began), exitFrame = nil, thought = 0, wake = nil,
		growl = nil, exitSpeed = nil, fallM = nil, fallD = nil, tumble = nil, lit = nil, mawRest = nil, lungeAt = nil,
		trueEnd = false, marsh = nil, marshRest = nil, marshJoints = nil, marshParts = {} }
	if path and hallsEvent then
		hallsEvent:FireServer("riding")
	end
	if not (scene :: Scene).frame then
		(scene :: Scene).chamber = nil
	end
	-- THE TRUE ENDING'S MAN, in the light behind the gate: hidden on this screen from the start, and shown only if this
	-- rider clocked in (and the server gave the gates the time for it).
	local opening = scene :: Scene
	local him = chamber and chamber:FindFirstChild("Marsh")
	if him and him:IsA("Model") then
		for _, item in ipairs(him:GetDescendants()) do
			if item:IsA("BasePart") or item:IsA("Decal") then
				item.LocalTransparencyModifier = 1
				table.insert(opening.marshParts, item)
			end
		end
		opening.marsh = him
		opening.marshRest = him:GetPivot()
		opening.marshJoints = if Poses then Poses.joints(him) else nil
	end
	opening.trueEnd = opening.marsh ~= nil and opening.chamber ~= nil and Players.LocalPlayer:GetAttribute("ClockedIn") == true
		and gates >= TRUE.done
	-- YOUR NAME ON THE ROTA, on this screen.
	local rota = chamber and chamber:FindFirstChild("RotaBoard")
	local words = rota and rota:FindFirstChild("Words", true)
	if words and words:IsA("TextLabel") then
		words.Text = "KEY HOLDER, OUTFALL 3: " .. string.upper(Players.LocalPlayer.DisplayName)
	end
	Cinema.begin()
	-- SCORED (audio/endings): the flume's water rushing under them all the way down the tube, the air
	-- as they shoot out of it, and at the very end the one chord that resolves.
	local current = scene :: Scene
	local rush = sound("FlumeRush", nil, 0, 1, true)
	if rush then
		TweenService:Create(rush, TweenInfo.new(1.2), { Volume = 0.55 }):Play()
		current.rush = rush
		keep(current, rush)
	end
end

-- ===== THE WATER IN THE FLUME =====
--
-- FloodedHallsService lays a sheet of water down the trough; here it runs downhill: each piece's texture slid
-- along it, the way the piece was laid (its +Z is downstream), at FLUME_FLOW studs a second.
local FLUME_FLOW = 14
local flumeWater: { [Texture]: boolean } = {}
local function moveWater(clock: number)
	for flow in pairs(flumeWater) do
		if flow.Parent then
			flow.OffsetStudsV = (clock * FLUME_FLOW) % flow.StudsPerTileV
		else
			flumeWater[flow] = nil
		end
	end
end
local function waterAdded(part: Instance)
	local flow = part:FindFirstChild("Flow")
	if flow and flow:IsA("Texture") then
		flumeWater[flow] = true
	end
end

-- ===== THE LAMPS BEHIND YOU =====

local LAMPS_KEPT = 2 -- bays behind you whose roof lights stay lit
local LAMP_GLOW = 0.3 -- what a failed lamp keeps of its light: a low glow, never off
local LAMP_DIM = Color3.fromRGB(96, 88, 70) -- the panel's colour with nothing behind it
local LAMP_FADE = 1.2 -- seconds from the stutter down to the glow
local LAMP_BACK = 0.8 -- seconds back up, when you are sent back past it
-- The stutter as it fails: how much light, for how long. Never below a sixth, and over in half a second.
local STUTTER = { { 0.18, 0.06 }, { 1, 0.08 }, { 0.18, 0.1 }, { 0.85, 0.12 } }
local LAMP_BAY: number = if HallRoute and typeof(HallRoute.BAY) == "number" then HallRoute.BAY else 96

type Lamp = { light: Light?, bright: number, colour: Color3, along: number, failed: boolean, level: number,
	turn: number, fresh: boolean }
local lamps: { [BasePart]: Lamp } = {}
local lampsAt = 0
local lampsSeen = 0

local function setLamp(part: BasePart, lamp: Lamp, level: number)
	lamp.level = level
	local light = lamp.light
	if light and light.Parent then
		light.Brightness = lamp.bright * level
	end
	part.Color = LAMP_DIM:Lerp(lamp.colour, level)
end

-- From where it is now to `level` over `seconds`, unless something newer has been asked of it.
local function fadeLamp(part: BasePart, lamp: Lamp, level: number, seconds: number, turn: number)
	local from = lamp.level
	local began = os.clock()
	while lamp.turn == turn and part.Parent do
		local u = math.clamp((os.clock() - began) / seconds, 0, 1)
		setLamp(part, lamp, from + (level - from) * u)
		if u >= 1 then
			break
		end
		task.wait()
	end
end

local function failLamp(part: BasePart, lamp: Lamp)
	lamp.failed = true
	lamp.turn += 1
	local turn = lamp.turn
	task.spawn(function()
		local click = Instance.new("Sound")
		click.SoundId = CLICK
		click.Volume = 0.3
		click.PlaybackSpeed = 0.8
		click.RollOffMaxDistance = 300
		click.Parent = part
		click:Play()
		click.Ended:Once(function()
			click:Destroy()
		end)
		for _, beat in ipairs(STUTTER) do
			if lamp.turn ~= turn or not part.Parent then
				return
			end
			setLamp(part, lamp, beat[1])
			task.wait(beat[2])
		end
		fadeLamp(part, lamp, LAMP_GLOW, LAMP_FADE, turn)
	end)
end

local function relightLamp(part: BasePart, lamp: Lamp)
	lamp.failed = false
	lamp.turn += 1
	local turn = lamp.turn
	task.spawn(fadeLamp, part, lamp, 1, LAMP_BACK, turn)
end

local function stepLamps()
	local now = os.clock()
	if now - lampsAt < 0.2 then
		return
	end
	lampsAt = now
	local halls = workspace:FindFirstChild("FloodedHalls")
	if not halls then
		if next(lamps) ~= nil then
			lamps = {}
		end
		return
	end
	-- Only on a run through the halls, and not during the ending (the scene has the room's lamps to itself).
	if Players.LocalPlayer:GetAttribute("InLevel") ~= "floodedHalls" or scene ~= nil then
		return
	end
	-- THE ROOF LIGHTS, looked for now and then: with streaming on they arrive as you get near them, and one that
	-- comes back after streaming out is a new part, found again here.
	if now - lampsSeen > 1 then
		lampsSeen = now
		for _, item in ipairs(halls:GetChildren()) do
			-- (And the lamps hanging over the walkway since the hundred-and-thirty-fourth pass: they fail with them.)
			if item:IsA("BasePart") and (item.Name == "RoofLight" or item.Name == "PendantLight") and not lamps[item]
				and not item:GetAttribute("Failing") then
				local along = item:GetAttribute("Along")
				if typeof(along) == "number" then
					local light: Light? = item:FindFirstChildOfClass("SurfaceLight") or item:FindFirstChildOfClass("PointLight")
					lamps[item] = { light = light, bright = if light then light.Brightness else 0, colour = item.Color,
						along = along, failed = false, level = 1, turn = 0, fresh = true }
				end
			end
		end
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	-- WHERE YOU ARE: the bay of the nearest roof light.
	local nearest, here = math.huge, nil
	for part, lamp in pairs(lamps) do
		if part.Parent then
			local gap = Vector3.new(part.Position.X - root.Position.X, 0, part.Position.Z - root.Position.Z).Magnitude
			if gap < nearest then
				nearest, here = gap, lamp.along
			end
		else
			lamps[part] = nil
		end
	end
	if here == nil then
		return
	end
	local behind = here - (LAMPS_KEPT + 0.5) * LAMP_BAY
	for part, lamp in pairs(lamps) do
		local gone = lamp.along < behind
		if lamp.fresh then
			-- First seen already behind you (a late join, or streamed back in): low at once, no stutter.
			lamp.fresh = false
			if gone then
				lamp.failed = true
				setLamp(part, lamp, LAMP_GLOW)
			end
		elseif gone and not lamp.failed then
			failLamp(part, lamp)
		elseif not gone and lamp.failed and lamp.along > behind + LAMP_BAY * 0.5 then
			relightLamp(part, lamp)
		end
	end
end

-- ===== CLOCKING IN (the hundred-and-fourteenth pass) =====
--
-- How long each shot is held, when the card slides from the rack to the slot, and when it is punched.
local CLOCK = { card = 2.4, shift = 3.6, slideFrom = 0.5, slideTo = 1.4, punch = 1.6 }
local clocking = { token = 0 }

local function clockIn(model: Model)
	local frame = model:GetAttribute("Frame")
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local card = model:FindFirstChild("ClockCard")
	if scene or not (Cinema and typeof(frame) == "CFrame" and root and root:IsA("BasePart") and card and card:IsA("BasePart")) then
		return
	end
	local at: CFrame = frame
	local prompt = model:FindFirstChild("ClockInPrompt", true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end
	clocking.token += 1
	local token = clocking.token
	local rack = card.CFrame
	-- In the slot under the dial, its written side turned to the front.
	local slot = at * CFrame.new(0, 3.9, -0.6) * CFrame.Angles(0, -math.pi / 2, 0)
	local stamped = ("KEY HOLDER\n%s\n14 AUG  11:57 PM\nCLOCKED IN"):format(string.upper(Players.LocalPlayer.DisplayName))
	Cinema.begin({ hush = false })
	holdMine("key")
	local began = os.clock()
	local punched, cut = false, false
	local hook: RBXScriptConnection? = nil
	hook = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		if clocking.token ~= token or not model.Parent then
			if hook then
				hook:Disconnect()
			end
			holdMine(nil)
			Cinema.finish(true)
			return
		end
		if t < CLOCK.card then
			-- YOUR CARD: over your shoulder, on the slot.
			Cinema.point(CFrame.lookAt(at * Vector3.new(1.4, 5, -5), at * Vector3.new(0.3, 4, -1)), 48)
			card.CFrame = rack:Lerp(slot, ease((t - CLOCK.slideFrom) / (CLOCK.slideTo - CLOCK.slideFrom)))
			if t >= CLOCK.punch and not punched then
				punched = true
				local punch = sound("ClockPunch", CLICK, 0.75, 0.45, false)
				if punch then
					game:GetService("Debris"):AddItem(punch, 4)
				end
				Cinema.impact(0.2)
				local words = card:FindFirstChild("Words", true)
				if words and words:IsA("TextLabel") then
					words.Text = stamped
					words.TextColor3 = Color3.fromRGB(150, 30, 30)
				end
			end
		elseif t < CLOCK.card + CLOCK.shift then
			-- ON SHIFT: from along the deck, you at the clock and Mr Barlow beside it.
			if not cut then
				cut = true
				holdMine(nil)
				Cinema.cut()
				Cinema.caption("Clocked in", "14 August. Three minutes to midnight. On shift.", 5)
			end
			Cinema.point(CFrame.lookAt(at * Vector3.new(9, 5, -7), at * Vector3.new(1, 2.8, 0)), 55)
		else
			if hook then
				hook:Disconnect()
			end
			Cinema.finish()
		end
	end)
end

function FloodedHallsClient.start()
	if Cinema and Cinema.onLeave then
		Cinema.onLeave(endScene)
	end
	-- The lamps first: they need nothing from the server but the halls themselves.
	local lampsWarned = false
	for _, part in ipairs(CollectionService:GetTagged("FlumeWater")) do
		waterAdded(part)
	end
	CollectionService:GetInstanceAddedSignal("FlumeWater"):Connect(waterAdded)
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(stepLamps)
		pcall(moveWater, os.clock())
		if not ok and not lampsWarned then
			lampsWarned = true
			warn("FloodedHallsClient: the lamps behind you stopped: " .. tostring(err))
		end
	end)
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	local event = remotes and remotes:WaitForChild("HallsCinema", 20)
	if not (event and event:IsA("RemoteEvent")) then
		warn("FloodedHallsClient: no RemoteEvents.HallsCinema, so the flume and the gates are not played as a scene. "
			.. "The server Bootstrap makes it; paste src/Server/Bootstrap.server.lua.")
		return
	end
	hallsEvent = event
	event.OnClientEvent:Connect(function(kind: any, player: any, began: any, slide: any, gates: any, maw: any)
		-- CLOCKED IN (the time clock's word, to you alone): its second value is the clock, not a player.
		if kind == "clockin" and typeof(player) == "Instance" and player:IsA("Model") then
			clockIn(player)
			return
		end
		if kind ~= "flume" or typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(began) ~= "number"
			or typeof(slide) ~= "number" then
			return
		end
		started(player, began, slide, if typeof(gates) == "number" then gates else 0, if typeof(maw) == "number" then maw else 0)
	end)
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(stepScene)
		if not ok then
			warn("FloodedHallsClient: the scene failed, and the camera is given back: " .. tostring(err))
			pcall(endScene)
		end
	end)
	print("FloodedHallsClient: running, " .. FloodedHallsClient.VERSION)
end

FloodedHallsClient.STAMP = "bfede0cc"
return FloodedHallsClient
