--!strict
-- StarterPlayerScripts/Services/Haptics.lua
-- FELT IN YOUR HANDS (the hundred-and-sixty-fourth pass, 2026-11-02, "keep polishing, do the next passes"). A game
-- whose every surface wants to be pressed was seen and heard and never felt: nothing in it touched a controller's
-- motors or a phone's. Now what is under your own feet is felt as well as heard, each kind of surface in its own way:
--
--   SQUISH  honey, slime, clay, the stress ball, the mud, the jelly and the bare butter: a soft swell and a slow let go
--   POP     bubble wrap: one sharp tick a bubble
--   CLICK   the keypads, the toy bricks and the light switches: a crisp snap
--   THOCK   a keyboard's keys, and the keys over lava: a short deep knock
--   GRAIN   sculpting sand, soap, salt, snow and the cookie: a fine grit, two grains to a step
--   CRACK   ice, the candle wax, both chocolates and the coal: a snap with a smaller one after it
--   HUSH    foam, cloud and lamb's ear: barely there
--   BOUNCE  a jellyfish: a swell up under you
--   CRUST   lava: a low, slow roll
--
-- And the moments: a checkpoint reached (two soft beats with its two notes), the slime's fling, a hard landing, a
-- scene's jolts and impacts, and every press in the menus (Roblox's own click, a softer brush as a card opens and goes,
-- two soft beats for something good, two knocks for a no).
--
-- HOW. Roblox's HapticEffect, a waveform played on whatever the player holds: a PlayStation or Xbox controller, most
-- iPhones, Pixels and Galaxies, a Quest's controllers. Where a client has no HapticEffect, a controller's two motors
-- instead (HapticService), the heavy shapes on the large one and the sharp ones on the small. However strong a shape is
-- written here, Roblox scales it by the player's own haptics setting, so the player keeps the last word; and a phone,
-- held in both hands for a whole run, feels its steps a little lighter than a controller does (PHONE).
--
-- Only YOUR feet, never anyone else's: AudioService feels a step only when it is yours (its `mine`), and only once its
-- sound is certain to play, so a step felt is a step heard, one to a footfall. Nothing on a server (HapticService is the
-- client's alone), and nothing at all if the player's device has nothing to feel with.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HapticService = game:GetService("HapticService")
local UserInputService = game:GetService("UserInputService")

local Haptics = {}
Haptics.VERSION = "felt in your hands, the hundred-and-sixty-fourth pass, 2026-11-02"

-- A SHAPE: its waveform as keys (milliseconds from the start, then how strong, 0 to 1, drawn straight from key to key),
-- and whether it is a heavy thing (the large motor, where there is no HapticEffect) or a sharp one (the small).
type Shape = { keys: { { number } }, heavy: boolean }
local SHAPES: { [string]: Shape } = {
	-- Underfoot, a shape to a kind of surface (UNDERFOOT below).
	squish = { keys = { { 0, 0 }, { 45, 0.24 }, { 130, 0.3 }, { 280, 0 } }, heavy = true },
	pop = { keys = { { 0, 0.9 }, { 28, 0 } }, heavy = false },
	click = { keys = { { 0, 0.7 }, { 20, 0 } }, heavy = false },
	thock = { keys = { { 0, 0.55 }, { 20, 0.32 }, { 75, 0 } }, heavy = false },
	grain = { keys = { { 0, 0.16 }, { 25, 0.3 }, { 50, 0.1 }, { 80, 0.26 }, { 140, 0 } }, heavy = false },
	crack = { keys = { { 0, 0.75 }, { 25, 0.15 }, { 55, 0.42 }, { 125, 0 } }, heavy = false },
	hush = { keys = { { 0, 0 }, { 70, 0.1 }, { 190, 0 } }, heavy = true },
	bounce = { keys = { { 0, 0.22 }, { 90, 0.5 }, { 230, 0 } }, heavy = true },
	crust = { keys = { { 0, 0.3 }, { 90, 0.46 }, { 320, 0 } }, heavy = true },
	-- The moments.
	checkpoint = { keys = { { 0, 0.34 }, { 60, 0 }, { 230, 0 }, { 240, 0.28 }, { 310, 0 } }, heavy = false },
	launch = { keys = { { 0, 0.2 }, { 80, 0.75 }, { 280, 0 } }, heavy = true },
	thump = { keys = { { 0, 1 }, { 60, 0.55 }, { 240, 0 } }, heavy = true },
	rumble = { keys = { { 0, 0.5 }, { 120, 0.35 }, { 420, 0 } }, heavy = true },
	brush = { keys = { { 0, 0 }, { 40, 0.12 }, { 110, 0 } }, heavy = false },
	good = { keys = { { 0, 0.3 }, { 40, 0 }, { 110, 0 }, { 120, 0.4 }, { 170, 0 } }, heavy = false },
	no = { keys = { { 0, 0.45 }, { 30, 0 }, { 120, 0 }, { 130, 0.45 }, { 160, 0 } }, heavy = false },
}

-- EVERY MATERIAL'S SHAPE, by MaterialConfig's names (check_touch.py holds every material to having one). A material
-- missing here is felt as a squish rather than not at all.
local UNDERFOOT: { [string]: string } = {
	Honey = "squish", Slime = "squish", Clay = "squish", Needoh = "squish", Oobleck = "squish", JelloSoda = "squish",
	ButterStick = "squish",
	BubbleWrap = "pop",
	Buttons = "click", Lego = "click", LightSwitch = "click",
	CreamyKeyboard = "thock", LavaKeys = "thock",
	KineticSand = "grain", Soap = "grain", Salt = "grain", Snow = "grain", Cookie = "grain",
	Ice = "crack", ButterWax = "crack", Chocolate = "crack", ChocolateSolid = "crack", Charcoal = "crack",
	Foam = "hush", Cloud = "hush", LambsEar = "hush",
	Jellyfish = "bounce",
	Lava = "crust",
}
-- A keypad's release is the spring coming back, not a press: half as strong. Its combo or circuit, the zap of a charge
-- going out, a little more than the click.
local EVENTS: { [string]: number } = { buttonRelease = 0.5, buttonCombo = 1.3, buttonCircuit = 1.3 }

-- THE GAPS, so nothing chatters: one feel underfoot every so often whatever the materials (two under you at once are one
-- step), one press, one jolt.
local GAP = { underfoot = 0.07, press = 0.05, jolt = 0.12 }
-- A PHONE: its steps this much of a controller's (a phone's motor is right under the thumbs, for the whole run).
local PHONE = { underfoot = 0.7 }
-- A HARD LANDING: from how fast you were falling (studs a second) it is felt at all, and at how fast at full. An
-- ordinary jump lands at about 53, so only a real drop is felt; the step's own shape comes with every landing anyway.
local LANDING = { from = 70, full = 150 }
-- A scene's jolt (Cinema.shake: about 1 for a door giving way, 3 for something enormous) under this is not felt.
local JOLT_LEAST = 0.3

local lastAt: { [string]: number } = {}

local function soon(kind: string): boolean
	local now = os.clock()
	if now - (lastAt[kind] or -1) < (GAP :: any)[kind] then
		return true
	end
	lastAt[kind] = now
	return false
end

-- A phone with nothing else to feel with: touch, and no controller.
local function onPhone(): boolean
	return UserInputService.TouchEnabled and not UserInputService.GamepadEnabled
end

-- ===== HAPTICEFFECT =====

-- Whether this client can make a HapticEffect (nil until first tried), the folder they live in (made by this client, so
-- it and they are on this screen only), each shape's effect, and the scale its keys were last written at.
local effectsWork: boolean? = nil
local holder: Folder? = nil
local effects: { [string]: Instance } = {}
local writtenAt: { [string]: number } = {}

local function folder(): Folder
	local found = holder
	if found and found.Parent then
		return found
	end
	local made = Instance.new("Folder")
	made.Name = "YourHaptics"
	made.Parent = workspace
	holder = made
	return made
end

local function keysFor(shape: Shape, scale: number): { any }
	local keys = {}
	for _, key in ipairs(shape.keys) do
		table.insert(keys, FloatCurveKey.new(key[1], math.clamp(key[2] * scale, 0, 1), Enum.KeyInterpolationMode.Linear))
	end
	return keys
end

-- `name`'s effect with its keys at `scale`, made the first time it is wanted; nil if this client has no HapticEffect.
local function effectFor(name: string, shape: Shape, scale: number): Instance?
	if effectsWork == false then
		return nil
	end
	local effect = effects[name]
	if not (effect and effect.Parent) then
		local ok, made = pcall(function()
			local new = (Instance.new :: any)("HapticEffect")
			new.Name = name
			new.Type = Enum.HapticEffectType.Custom
			new.Looped = false
			new.Parent = folder()
			return new
		end)
		effectsWork = ok
		if not ok then
			return nil
		end
		effect = made
		effects[name] = made
		writtenAt[name] = nil
	end
	-- The keys again only when the scale has changed: a step on the same surface plays what is already written.
	if writtenAt[name] ~= scale then
		local ok = pcall(function()
			(effect :: any):SetWaveformKeys(keysFor(shape, scale))
		end)
		if not ok then
			return nil
		end
		writtenAt[name] = scale
	end
	return effect
end

-- ===== A CONTROLLER'S MOTORS, where there is no HapticEffect =====

local PAD = Enum.UserInputType.Gamepad1
local motorTurn: { [Enum.VibrationMotor]: number } = {}

local function motorFor(heavy: boolean): Enum.VibrationMotor?
	local first = if heavy then Enum.VibrationMotor.Large else Enum.VibrationMotor.Small
	local other = if heavy then Enum.VibrationMotor.Small else Enum.VibrationMotor.Large
	local ok, found = pcall(function(): Enum.VibrationMotor?
		if not HapticService:IsVibrationSupported(PAD) then
			return nil
		end
		-- A controller with only one of the two: the one it has.
		if HapticService:IsMotorSupported(PAD, first) then
			return first
		elseif HapticService:IsMotorSupported(PAD, other) then
			return other
		end
		return nil
	end)
	return if ok then found else nil
end

local function buzz(shape: Shape, scale: number)
	local motor = motorFor(shape.heavy)
	if not motor then
		return
	end
	local peak, length = 0, 0
	for _, key in ipairs(shape.keys) do
		peak = math.max(peak, key[2])
		length = math.max(length, key[1])
	end
	local turn = (motorTurn[motor] or 0) + 1
	motorTurn[motor] = turn
	pcall(function()
		HapticService:SetMotor(PAD, motor, math.clamp(peak * scale, 0, 1))
	end)
	-- Let go when the shape would have ended, unless a newer one has the motor by then.
	task.delay(math.max(length, 30) / 1000, function()
		if motorTurn[motor] == turn then
			pcall(function()
				HapticService:SetMotor(PAD, motor, 0)
			end)
		end
	end)
end

-- ===== PLAYING ONE =====

-- `name` a shape, `scale` how strong against how it is written (rounded to a twentieth, so a step's slightly different
-- gain does not rewrite the keys every time).
local function play(name: string, scale: number?)
	if not RunService:IsClient() then
		return
	end
	local shape = SHAPES[name]
	if not shape then
		return
	end
	local strength = math.floor(math.clamp(scale or 1, 0, 1.5) * 20 + 0.5) / 20
	if strength <= 0 then
		return
	end
	local effect = effectFor(name, shape, strength)
	if effect then
		pcall(function()
			(effect :: any):Play()
		end)
	else
		buzz(shape, strength)
	end
end

-- ===== WHAT THE GAME CALLS =====

-- YOUR OWN STEP on `material`, from AudioService.playSfx once its sound is certain to play: `event` the sound asked for
-- (a keypad's release or combo), `gain` the sound's own (a quieter crust, a louder launch off a spring).
function Haptics.step(material: string, event: string?, gain: number?)
	if soon("underfoot") then
		return
	end
	local scale = (gain or 1) * (if event then EVENTS[event] or 1 else 1)
	if onPhone() then
		scale *= PHONE.underfoot
	end
	play(UNDERFOOT[material] or "squish", math.min(scale, 1.3))
end

-- A PRESS in a menu, from AudioService.press, by the same kinds: "tap" (Roblox's own click), "open" and "close" (a soft
-- brush), "good" (two soft beats) and "no" (two knocks).
function Haptics.press(kind: string?)
	if not RunService:IsClient() or soon("press") then
		return
	end
	if kind == nil or kind == "tap" then
		-- Roblox's own click, which each device's makers tuned for its own motor; a controller's small motor where this
		-- client has no HapticEffect.
		local ok = effectsWork ~= false and pcall(function()
			local click = effects.tap
			if not (click and click.Parent) then
				local new = (Instance.new :: any)("HapticEffect")
				new.Name = "tap"
				new.Type = Enum.HapticEffectType.UIClick
				new.Parent = folder()
				effects.tap = new
				click = new
			end
			(click :: any):Play()
		end)
		if not ok then
			buzz(SHAPES.click, 0.6)
		end
	elseif kind == "open" or kind == "close" then
		play("brush")
	elseif kind == "good" then
		play("good")
	elseif kind == "no" then
		play("no")
	end
end

-- A CHECKPOINT REACHED (RunFeel, with its two notes).
function Haptics.checkpoint()
	play("checkpoint")
end

-- THE SLIME'S FLING, `velocity` the launch's (about 100 studs a second).
function Haptics.launch(velocity: number?)
	play("launch", math.clamp((velocity or 100) / 110, 0.4, 1))
end

-- A SCENE'S IMPACT FRAME (Cinema.impact, `strength` about 1; 1.5 for a crash).
function Haptics.impact(strength: number?)
	play("thump", math.clamp(0.6 * (strength or 1), 0.3, 1))
end

-- A SCENE'S JOLT (Cinema.shake). Small ones are seen and not felt.
function Haptics.jolt(amount: number)
	if amount < JOLT_LEAST or soon("jolt") then
		return
	end
	play("rumble", math.clamp(amount / 3, 0.15, 1))
end

-- ===== A HARD LANDING =====

-- How fast you were falling, kept every frame while you fall: by the time Roblox says you have landed, the speed is gone.
local function watch(character: Model)
	local foundHumanoid = character:WaitForChild("Humanoid", 10)
	local foundRoot = character:WaitForChild("HumanoidRootPart", 10)
	if not (foundHumanoid and foundHumanoid:IsA("Humanoid") and foundRoot and foundRoot:IsA("BasePart")) then
		return
	end
	local humanoid = foundHumanoid :: Humanoid
	local root = foundRoot :: BasePart
	local fastest = 0
	local falling: RBXScriptConnection? = nil
	local function stopFalling()
		local connection = falling
		if connection then
			connection:Disconnect()
			falling = nil
		end
	end
	humanoid.StateChanged:Connect(function(_, now: Enum.HumanoidStateType)
		if now == Enum.HumanoidStateType.Freefall then
			fastest = 0
			if not falling then
				falling = RunService.Heartbeat:Connect(function()
					fastest = math.max(fastest, -root.AssemblyLinearVelocity.Y)
				end)
			end
		elseif now == Enum.HumanoidStateType.Landed then
			stopFalling()
			if fastest >= LANDING.from then
				play("thump", math.clamp((fastest - LANDING.from) / (LANDING.full - LANDING.from), 0.2, 1))
			end
			fastest = 0
		elseif falling and now ~= Enum.HumanoidStateType.Jumping then
			-- Into the water, onto a seat, into a scene: not a landing.
			stopFalling()
			fastest = 0
		end
	end)
	humanoid.Destroying:Once(stopFalling)
end

local started = false
function Haptics.start()
	if started or not RunService:IsClient() then
		return
	end
	started = true
	local me = Players.LocalPlayer
	me.CharacterAdded:Connect(function(character: Model)
		task.spawn(watch, character)
	end)
	if me.Character then
		task.spawn(watch, me.Character)
	end
end

Haptics.STAMP = "326501ab"
return Haptics
