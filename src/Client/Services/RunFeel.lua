--!strict
-- StarterPlayerScripts/Services/RunFeel.lua
-- THE RUN, FELT (the hundred-and-thirty-eighth pass, from your notes of 2026-10-30: "these next passes work on polishing
-- the game"): what a run says back to you, on your own screen, between its big moments.
--
--   A CHECKPOINT REACHED. Nothing said so: a Chill fall put you back "at your last checkpoint", and there was no telling
--   where that was. The server marks how far you have got (your Checkpoint attribute: the furthest stable chunk you have
--   stood on in this run, Bootstrap), and the first time you reach one further on than any before it, a ring of light
--   spreads out across the slab from its middle to its edges, and another after it, a warm glow comes up off the slab
--   and dies, and two low marimba bars sound (audio/gen_checkpoint_sfx.py: CheckpointChime_x3 in StorySounds, a
--   different take each time). Nothing on the screen itself and nothing to press.
--
-- Not while a scene has the camera (that is an ending's moment, not a checkpoint's), not in the back rooms, never in the
-- lobby. Without the chime imported, the ring comes alone: no built-in sound stands in for it (never a ping).
--
--   YOUR FOOTING (the hundred-and-fifty-second pass, from your test of 2026-10-31: "the blocks that don't break should
--   have some other effect, honey slows you down, and the clouds could make your feet wet and slippery"). Two things,
--   both felt in your legs:
--     SLIPPERY GROUND. Ice, soap, waxed butter and warm chocolate said they were slippery and were not: the server
--     lowered the friction of your character's parts, and Roblox's walking pays friction no mind. Now your walking
--     catches up with your keys or stick only so fast on them (FOOTING.grip): you slide on, turn wide, take a moment
--     to stop.
--     WHAT YOUR SOLES CARRY off a material, for a few seconds after: WET off a cloud or a jellyfish (a little
--     slippery anywhere, dark wet prints and drips), GREASY off butter (slippery, pale smears), STICKY off honey
--     (slower, golden prints and strings, and sticky soles do not slide at all, even on ice), GRITTY off sculpting
--     sand, salt or a cookie (grit grips: slippery ground is half as slippery). Lamb's ear wipes them clean.
--   Everyone's prints and drips are drawn for everyone near; the sliding is your own, on your own screen, where your
--   character is moved. Never in a scene, a seat or the water.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunFeel = {}
RunFeel.VERSION = "footing, the hundred-and-fifty-second pass, 2026-10-31"

-- THE RING: how far across the slab it spreads (a share of its shorter side), how long it takes, how thick it is drawn,
-- its colour, the gap before the second, and the glow off the slab (a real light, warm, never a lit block).
local RING = { reach = 0.92, seconds = 1.1, thick = 7, colour = Color3.fromRGB(255, 240, 212), second = 0.18,
	glow = Color3.fromRGB(255, 222, 172), light = 1.4, range = 14 }
-- THE CHIME: the sheet's takes and their slots (gen_checkpoint_sfx.py's SLOT), and how loud.
local CHIME = { takes = 3, slot = 1.5, volume = 0.45 }

-- A module beside this one (Cinema), found when first wanted: this needs nothing of it to run.
local function beside(name: string): any
	local found = script.Parent and script.Parent:FindFirstChild(name)
	if found and found:IsA("ModuleScript") then
		local ok, loaded = pcall(require, found)
		if ok and type(loaded) == "table" then
			return loaded
		end
	end
	return nil
end

-- AN ERROR ONCE, NOT EVERY TIME.
local warned: { [string]: boolean } = {}
local function warnOnce(text: string)
	if not warned[text] then
		warned[text] = true
		warn(text .. " (shown once)")
	end
end

-- ===== THE CHIME =====

local lastTake = 0
local function chime()
	local folder = SoundService:FindFirstChild("StorySounds")
	local sheet = folder and folder:FindFirstChild("CheckpointChime_x3")
	if not (sheet and sheet:IsA("Sound")) then
		return
	end
	-- A different take each time, never the one before.
	local take = math.random(1, CHIME.takes)
	if take == lastTake then
		take = take % CHIME.takes + 1
	end
	lastTake = take
	local s = sheet:Clone()
	s.Volume = CHIME.volume
	s.PlaybackSpeed = 0.98 + math.random() * 0.04
	local from = (take - 1) * CHIME.slot
	local regioned = pcall(function()
		(s :: any).PlaybackRegionsEnabled = true;
		(s :: any).PlaybackRegion = NumberRange.new(from, from + CHIME.slot - 0.05)
	end)
	s.TimePosition = from
	s.Parent = SoundService
	s:Play()
	if not regioned then
		task.delay(CHIME.slot - 0.07, function()
			if s.Parent then
				s:Stop()
			end
		end)
	end
	game:GetService("Debris"):AddItem(s, CHIME.slot + 0.6)
end

-- ===== THE RING =====

-- The slab under you, if you are standing on one: what the ray down from you meets, flat side up.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function slabUnder(root: BasePart, character: Model): BasePart?
	rayParams.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -10, 0), rayParams)
	if not hit or hit.Normal.Y < 0.9 then
		return nil
	end
	local part = hit.Instance
	return if part:IsA("BasePart") and part.CFrame.UpVector.Y > 0.9 then part else nil
end

local function ring(gui: SurfaceGui, delay: number, thick: number)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0.04, 0.04)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = frame
	local edge = Instance.new("UIStroke")
	edge.Color = RING.colour
	edge.Thickness = thick
	edge.Transparency = 1
	edge.Parent = frame
	task.delay(delay, function()
		if not frame.Parent then
			return
		end
		edge.Transparency = 0.12
		local spread = TweenInfo.new(RING.seconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		TweenService:Create(frame, spread, { Size = UDim2.fromScale(1, 1) }):Play()
		TweenService:Create(edge, TweenInfo.new(RING.seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Transparency = 1, Thickness = thick * 0.4 }):Play()
	end)
end

local function ripple(slab: BasePart)
	local reach = math.min(slab.Size.X, slab.Size.Z) * RING.reach
	-- A plate of nothing lying on the slab's top, its middle on the slab's middle: the rings are drawn on it.
	local plate = Instance.new("Part")
	plate.Name = "CheckpointRipple"
	plate.Anchored = true
	plate.CanCollide = false
	plate.CanQuery = false
	plate.CanTouch = false
	plate.CastShadow = false
	plate.Transparency = 1
	plate.Size = Vector3.new(reach, 0.05, reach)
	plate.CFrame = slab.CFrame * CFrame.new(0, slab.Size.Y / 2 + 0.04, 0)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(512, 512)
	gui.LightInfluence = 0
	gui.Adornee = plate
	gui.Parent = plate
	ring(gui, 0, RING.thick)
	ring(gui, RING.second, RING.thick * 0.6)
	-- The glow off the slab, coming up with the first ring and dying with the second.
	local glow = Instance.new("PointLight")
	glow.Color = RING.glow
	glow.Range = math.clamp(reach, 8, RING.range)
	glow.Brightness = 0
	glow.Shadows = false
	glow.Parent = plate
	TweenService:Create(glow, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = RING.light }):Play()
	task.delay(0.2, function()
		if glow.Parent then
			TweenService:Create(glow, TweenInfo.new(RING.seconds + RING.second, Enum.EasingStyle.Quad), { Brightness = 0 }):Play()
		end
	end)
	plate.Parent = workspace
	game:GetService("Debris"):AddItem(plate, RING.seconds + RING.second + 0.6)
end

-- ===== A CHECKPOINT FURTHER ON =====

local cinema: any = nil
local function inScene(): boolean
	cinema = cinema or beside("Cinema")
	return cinema ~= nil and cinema.active()
end

local function reached()
	local me = Players.LocalPlayer
	local level = me:GetAttribute("InLevel")
	if level == nil or level == "backRooms" or inScene() then
		return
	end
	chime()
	-- And felt, two soft beats with the two notes (the hundred-and-sixty-fourth pass).
	local haptics = beside("Haptics")
	if haptics then
		pcall(haptics.checkpoint)
	end
	local character = me.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if character and root and root:IsA("BasePart") then
		local slab = slabUnder(root, character)
		if slab then
			ripple(slab)
		end
	end
end

-- ===== YOUR FOOTING (the hundred-and-fifty-second pass) =====

local FOOTING = {
	-- How fast, per second, your walking catches up with where your keys or stick point on each slippery thing: the
	-- lower, the further you slide. Ordinary ground is not here: on it you walk where you point.
	grip = { Ice = 1.6, Soap = 2.6, ButterWax = 3.2, Chocolate = 4.2 } :: { [string]: number },
	-- What each material leaves on your soles, and what wipes them.
	leaves = { Cloud = "wet", Jellyfish = "wet", ButterStick = "greasy", ButterWax = "greasy", Honey = "sticky",
		KineticSand = "gritty", Salt = "gritty", Cookie = "gritty" } :: { [string]: string },
	wipes = { LambsEar = true } :: { [string]: boolean },
	-- Each: how long it lasts once you are off what left it; its own grip on any ground (none: it does not slide you);
	-- how much of your speed it leaves you; whether it holds you even on slippery ground (sticky); how much better it
	-- makes slippery ground hold (gritty); its prints; its drips; the sound under it now and then.
	soles = {
		wet = { seconds = 5, grip = 7, colour = Color3.fromRGB(52, 78, 104), alpha = 0.5, drip = Color3.fromRGB(196, 226, 250),
			sound = "dip" },
		greasy = { seconds = 5, grip = 4.5, colour = Color3.fromRGB(250, 234, 168), alpha = 0.3, sound = "ButterStick" },
		sticky = { seconds = 4, speed = 0.82, holds = true, colour = Color3.fromRGB(226, 150, 34), alpha = 0.25,
			drip = Color3.fromRGB(236, 164, 40), sound = "Honey" },
		gritty = { seconds = 4, boost = 2, colour = Color3.fromRGB(196, 168, 122), alpha = 0.5 },
	} :: { [string]: any },
	stride = 2.4, -- studs walked between two prints
	look = 6, -- studs below your root the ground is looked for
	kept = 48, -- prints at most, the oldest going first
	near = 120, -- studs: anyone further off has no prints drawn
	every = 0.1, -- seconds between two looks at everyone else's feet (yours: every frame)
	life = 2.6, -- seconds a print lasts
	sounded = 3, -- a print in this many makes its sound
}

-- `soft`: what they stand on has given (waxed butter whose wax is broken, DeformationRenderer's Soft): it holds a foot.
type Feet = { soles: string?, till: number, on: string?, last: Vector3?, travelled: number, foot: number, count: number,
	drips: ParticleEmitter?, dripKind: string?, soft: boolean? }
local feet: { [Player]: Feet } = {}
local slide = { carried = Vector3.zero, controls = nil :: any, lookedAt = 0, prints = {} :: { BasePart }, folder = nil :: Folder? }

local footRay = RaycastParams.new()
footRay.FilterType = Enum.RaycastFilterType.Exclude
footRay.IgnoreWater = true

local function printFolder(): Folder
	local existing = slide.folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "SolePrints"
	made.Parent = workspace
	slide.folder = made
	return made
end

-- What `character` stands on: the game's own material (the Material its platform carries), "ground" for anything else
-- solid, or nil in the air. And where.
local function groundUnder(character: Model, root: BasePart, humanoid: Humanoid): (string?, RaycastResult?)
	footRay.FilterDescendantsInstances = { character, printFolder() }
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -FOOTING.look, 0), footRay)
	if not hit then
		return nil, nil
	end
	-- Feet on it: no further below the root than the legs reach (others' FloorMaterial is not kept on this screen). The
	-- legs are HipHeight on R15, and on R6 (whose HipHeight is 0) its 2-stud legs.
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
	if root.Position.Y - hit.Position.Y > legs + root.Size.Y / 2 + 0.7 then
		return nil, nil
	end
	local item: Instance? = hit.Instance
	for _ = 1, 4 do
		if not item then
			break
		end
		local name = item:GetAttribute("Material")
		if typeof(name) == "string" then
			return name, hit
		end
		item = item.Parent
	end
	return "ground", hit
end

-- How fast your walking catches up where you point (nil: at once), and how much of your speed you keep.
local function gripFor(f: Feet?): (number?, number)
	-- (Butter with its wax broken is not slippery ground: the two-hundred-and-seventh pass.)
	local rate = if f and f.on and not f.soft then FOOTING.grip[f.on] else nil
	local residue = if f and f.soles then FOOTING.soles[f.soles] else nil
	-- On the honey itself its own slowness is the server's (DeformationService), not this on top of it.
	local onSource = f ~= nil and f.on ~= nil and FOOTING.leaves[f.on] == f.soles
	if residue then
		if residue.holds then
			return nil, if onSource then 1 else residue.speed or 1
		end
		if residue.boost and rate then
			rate *= residue.boost
		end
		if residue.grip then
			rate = if rate then math.min(rate, residue.grip) else residue.grip
		end
	end
	return rate, if residue and not onSource then residue.speed or 1 else 1
end

-- The controls Roblox's own PlayerModule drives your character with: where your keys or stick point, before anything
-- is done with it.
local function controlsOf(): any
	if slide.controls == nil then
		local scripts = Players.LocalPlayer:FindFirstChild("PlayerScripts")
		local module = scripts and scripts:FindFirstChild("PlayerModule")
		local ok, controls = false, nil
		if module and module:IsA("ModuleScript") then
			ok, controls = pcall(function()
				return (require(module) :: any):GetControls()
			end)
		end
		slide.controls = if ok and controls then controls else false
	end
	return slide.controls or nil
end

-- YOUR SLIDE, every frame, just after Roblox has read your keys or stick: where you point, eased toward at your footing's
-- grip, and given to your character as its walk (Humanoid:Move, whose length is a share of your walking speed).
local function slideStep(dt: number)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local state = humanoid and humanoid:GetState()
	if not (humanoid and root and root:IsA("BasePart")) or root.Anchored or humanoid.Sit or humanoid.PlatformStand
		or state == Enum.HumanoidStateType.Swimming or state == Enum.HumanoidStateType.Climbing
		or state == Enum.HumanoidStateType.Seated or inScene() then
		slide.carried = Vector3.zero
		return
	end
	local controls = controlsOf()
	local camera = workspace.CurrentCamera
	if not (controls and camera) then
		return
	end
	local move = controls:GetMoveVector()
	local wanted = Vector3.zero
	if move.Magnitude > 0.01 then
		local look = camera.CFrame.LookVector
		local ahead = Vector3.new(look.X, 0, look.Z)
		if ahead.Magnitude < 0.01 then
			ahead = Vector3.new(camera.CFrame.UpVector.X, 0, camera.CFrame.UpVector.Z)
		end
		ahead = ahead.Unit
		local right = Vector3.new(-ahead.Z, 0, ahead.X)
		wanted = right * move.X - ahead * move.Z
		if wanted.Magnitude > 1 then
			wanted = wanted.Unit
		end
	end
	local rate, speed = gripFor(feet[Players.LocalPlayer])
	if rate == nil then
		slide.carried = wanted
		if speed < 1 then
			humanoid:Move(wanted * speed, false)
		end
		return
	end
	slide.carried += (wanted - slide.carried) * (1 - math.exp(-rate * dt))
	if wanted.Magnitude < 0.01 and slide.carried.Magnitude < 0.04 then
		slide.carried = Vector3.zero
	end
	humanoid:Move(slide.carried * speed, false)
end

-- A PRINT of what your soles carry: a sole, toe and heel, flat on the ground, fading as it dries.
local function solePrint(kind: string, at: Vector3, up: Vector3, ahead: Vector3)
	local residue = FOOTING.soles[kind]
	local forward = ahead - up * ahead:Dot(up)
	if not residue or forward.Magnitude < 0.05 then
		return
	end
	forward = forward.Unit
	local part = Instance.new("Part")
	part.Name = "SolePrint"
	part.Size = Vector3.new(0.9, 0.05, 1.5)
	part.CFrame = CFrame.fromMatrix(at + up * 0.04, up:Cross(-forward), up)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = printFolder()
	local face = Instance.new("SurfaceGui")
	face.Face = Enum.NormalId.Top
	face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	face.PixelsPerStud = 40
	face.LightInfluence = 1
	face.Parent = part
	local fade = TweenInfo.new(FOOTING.life * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, FOOTING.life * 0.4)
	for _, piece in ipairs({ { 0.86, 0.5, 0.5, 0.3 }, { 0.62, 0.36, 0.5, 0.76 } }) do
		local oval = Instance.new("Frame")
		oval.AnchorPoint = Vector2.new(0.5, 0.5)
		oval.Size = UDim2.fromScale(piece[1], piece[2])
		oval.Position = UDim2.fromScale(piece[3], piece[4])
		oval.BackgroundColor3 = residue.colour
		oval.BackgroundTransparency = residue.alpha
		oval.BorderSizePixel = 0
		oval.Parent = face
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = oval
		TweenService:Create(oval, fade, { BackgroundTransparency = 1 }):Play()
	end
	game:GetService("Debris"):AddItem(part, FOOTING.life + 0.2)
	table.insert(slide.prints, part)
	while #slide.prints > FOOTING.kept do
		local oldest = table.remove(slide.prints, 1)
		if oldest then
			oldest:Destroy()
		end
	end
end

-- The sound of a step on what your soles carry, now and then: water underfoot, honey, butter. Soft.
local function soleSound(kind: string, root: BasePart, mine: boolean)
	local residue = FOOTING.soles[kind]
	if not (residue and residue.sound) then
		return
	end
	if residue.sound == "dip" then
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local module = shared and shared:FindFirstChild("WaterSounds")
		local s = Instance.new("Sound")
		local dressed = false
		if module and module:IsA("ModuleScript") then
			local ok, water = pcall(require, module)
			dressed = ok and type(water) == "table" and water.dress(s, "dip")
		end
		if not dressed then
			s:Destroy()
			return
		end
		s.Volume = if mine then 0.16 else 0.12
		s.RollOffMaxDistance = 40
		s.Parent = root
		s:Play()
		game:GetService("Debris"):AddItem(s, 2)
		return
	end
	local audio = beside("AudioService")
	if audio and audio.playSfx then
		audio.playSfx(residue.sound, root, mine, { gain = 0.3 })
	end
end

-- Drips off soles that carry something wet or sticky, at the feet, while they do.
local function setDrips(f: Feet, root: BasePart)
	local residue = if f.soles then FOOTING.soles[f.soles] else nil
	local kind = if residue and residue.drip then f.soles else nil
	if f.dripKind == kind and (f.drips == nil or f.drips.Parent) then
		return
	end
	if f.drips then
		local old = f.drips
		old.Enabled = false
		game:GetService("Debris"):AddItem(old.Parent or old, 1)
		f.drips = nil
	end
	f.dripKind = kind
	if not (kind and residue) then
		return
	end
	local at = Instance.new("Attachment")
	at.Name = "SoleDrips"
	at.Position = Vector3.new(0, -(root.Size.Y / 2 + 1.6), 0)
	at.Parent = root
	local drips = Instance.new("ParticleEmitter")
	drips.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	drips.Color = ColorSequence.new(residue.drip)
	drips.Size = NumberSequence.new(if kind == "sticky" then 0.16 else 0.1)
	drips.Transparency = NumberSequence.new(0.2, 1)
	drips.Lifetime = NumberRange.new(0.3, 0.6)
	drips.Speed = NumberRange.new(0.2, 0.8)
	drips.SpreadAngle = Vector2.new(25, 25)
	drips.Acceleration = Vector3.new(0, if kind == "sticky" then -14 else -34, 0)
	drips.Rate = if kind == "sticky" then 3 else 6
	drips.LightEmission = 0.1
	drips.Parent = at
	f.drips = drips
end

-- Everyone's feet: what they stand on, what their soles carry, their prints and drips. Yours every frame (your slide
-- reads it), everyone else's ten times a second.
local function feetStep(everyone: boolean)
	local now = os.clock()
	local me = Players.LocalPlayer
	local myRoot = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
	local here = if myRoot and myRoot:IsA("BasePart") then myRoot.Position else nil
	for _, player in ipairs(Players:GetPlayers()) do
		local mine = player == me
		if not mine and not everyone then
			continue
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (character and root and root:IsA("BasePart") and humanoid) then
			feet[player] = nil
			continue
		end
		if not mine and (here == nil or (root.Position - here).Magnitude > FOOTING.near) then
			continue
		end
		local f = feet[player]
		if not f then
			f = { soles = nil, till = 0, on = nil, last = nil, travelled = 0, foot = 1, count = 0 }
			feet[player] = f
		end
		local f2 = f :: Feet
		local on, hit = groundUnder(character, root, humanoid)
		f2.on = on
		-- Given already (Soft, on the cell or the floor under it)?
		local under: Instance? = if hit then hit.Instance else nil
		f2.soft = false
		for _ = 1, 3 do
			if not under then
				break
			end
			if under:GetAttribute("Soft") == true then
				f2.soft = true
				break
			end
			under = under.Parent
		end
		local before = f2.soles
		if on and FOOTING.wipes[on] then
			f2.soles = nil
		elseif on and FOOTING.leaves[on] then
			local kind = FOOTING.leaves[on]
			f2.soles = kind
			f2.till = now + FOOTING.soles[kind].seconds
		end
		if f2.soles and now > f2.till then
			f2.soles = nil
		end
		if before and f2.soles == nil and on and FOOTING.wipes[on] then
			-- Wiped: a little of what was on them, left in the leaves.
			local residue = FOOTING.soles[before]
			if residue and hit then
				local spot = Instance.new("Part")
				spot.Anchored, spot.CanCollide, spot.CanTouch, spot.CanQuery = true, false, false, false
				spot.Transparency = 1
				spot.Size = Vector3.new(0.2, 0.2, 0.2)
				spot.CFrame = CFrame.new(hit.Position)
				spot.Parent = printFolder()
				local fluff = Instance.new("ParticleEmitter")
				fluff.Texture = "rbxasset://textures/particles/smoke_main.dds"
				fluff.Color = ColorSequence.new(residue.colour)
				fluff.Size = NumberSequence.new(0.5)
				fluff.Transparency = NumberSequence.new(0.6, 1)
				fluff.Lifetime = NumberRange.new(0.4, 0.8)
				fluff.Speed = NumberRange.new(1, 3)
				fluff.SpreadAngle = Vector2.new(60, 60)
				fluff.Rate = 0
				fluff.Parent = spot
				fluff:Emit(8)
				game:GetService("Debris"):AddItem(spot, 1.2)
			end
		end
		setDrips(f2, root)
		-- A STRIDE on something solid, with something on your soles: a print, and now and then its sound.
		local last = f2.last
		f2.last = root.Position
		if not (last and hit and f2.soles) or FOOTING.leaves[on or ""] == f2.soles then
			continue
		end
		local moved = Vector3.new(root.Position.X - last.X, 0, root.Position.Z - last.Z).Magnitude
		if moved > 8 then
			continue
		end
		f2.travelled += moved
		if f2.travelled < FOOTING.stride then
			continue
		end
		f2.travelled = 0
		f2.foot = -f2.foot
		local v = root.AssemblyLinearVelocity
		local ahead = Vector3.new(v.X, 0, v.Z)
		if ahead.Magnitude < 1 then
			ahead = root.CFrame.LookVector
		end
		local side = hit.Normal:Cross(-Vector3.new(ahead.X, 0, ahead.Z).Unit)
		solePrint(f2.soles :: string, hit.Position + side * (0.42 * f2.foot), hit.Normal, ahead)
		f2.count += 1
		if f2.count % FOOTING.sounded == 0 then
			soleSound(f2.soles :: string, root, mine)
		end
	end
	for player, f in pairs(feet) do
		if player.Parent ~= Players then
			if f.drips then
				f.drips:Destroy()
			end
			feet[player] = nil
		end
	end
end

function RunFeel.start()
	-- YOUR FOOTING: your slide just after Roblox reads your keys (its own step is at Input), and everyone's feet.
	RunService:BindToRenderStep("RunFeelFooting", Enum.RenderPriority.Input.Value + 1, function(dt: number)
		local ok, err = pcall(function()
			local everyone = os.clock() - slide.lookedAt >= FOOTING.every
			if everyone then
				slide.lookedAt = os.clock()
			end
			feetStep(everyone)
			slideStep(dt)
		end)
		if not ok then
			warnOnce("RunFeel: the footing could not be worked out: " .. tostring(err))
		end
	end)
	local me = Players.LocalPlayer
	local furthest = tonumber(me:GetAttribute("Checkpoint")) or 0
	me:GetAttributeChangedSignal("Checkpoint"):Connect(function()
		local now = tonumber(me:GetAttribute("Checkpoint")) or 0
		-- Further on than before (back to 0 as a run starts, or starts again: nothing to say), and past the slab you
		-- start on.
		local further = now > furthest and now > 1
		furthest = now
		if further then
			local ok, err = pcall(reached)
			if not ok then
				warnOnce("RunFeel: a checkpoint could not be shown: " .. tostring(err))
			end
		end
	end)
	print("RunFeel: running, " .. RunFeel.VERSION)
end

RunFeel.STAMP = "2bc3fccd"
return RunFeel
