--!strict
-- StarterPlayerScripts/Services/FloodedHallsClient.lua
-- The Flooded Halls' ending, played as a scene: the flume, the fall, and the gates at the bottom of it
-- all. FloodedHallsService decides everything (when the ride starts, where the rider is, when the run
-- is over); this only shows it. The last scene of the story (Townsfolk has the whole of it).
--
-- === On the rider's own screen (Cinema) ===
--
--   THE FLUME      drawn by this client, from the path the server wrote down (FlumePath), so it is
--                  smooth: the server writing the rider sixty times a second was the lag. Over your
--                  shoulder into the tube; chasing you down it; from the shaft's wall as you come
--                  round towards it; from just ahead, looking back at you; from below as you shoot out
--                  of the end of it; and from above as you fall into the dark.
--   THE MOUTH      at the bottom of the fall there is something in the dark. From above, falling with
--                  you, its jaws open under you and a light comes up inside it, the teeth catching it;
--                  from inside it, between the jaws, looking up at you coming down; from the side, level
--                  with the teeth, the jaws shut. Black. A heartbeat. "The Hold. It keeps what it is
--                  given." (Maw.lua; on your screen only, and nothing but its mouth is ever seen.)
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
--
-- Everything the scene changes in the room (the gate, the wheel, the lamps, the clock, the water) is
-- changed on this screen only: each rider opens their own gates.
--
-- === On everyone's ===
--
-- The rider lies back with their arms crossed on the way down the flume (Poses.flume).
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

local FloodedHallsClient = {}
FloodedHallsClient.VERSION = "twenty-first pass, 2026-09-30"

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
	rumble: Sound?, lastFall: Vector3?, path: { CFrame }? }
local scene: Scene? = nil
local hallsEvent: RemoteEvent? = nil

local function once(current: Scene, key: string): boolean
	if current.done[key] then
		return false
	end
	current.done[key] = true
	return true
end

local function endScene()
	local current = scene
	if not current then
		return
	end
	scene = nil
	holdMine(nil)
	if Maw and current.mouth then
		Maw.destroy(current.mouth)
		current.mouth = nil
	end
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

-- WHERE THE RIDER IS, f of the way down, from the path the server wrote down: between two of its steps.
local function pathAt(path: { CFrame }, f: number): CFrame
	local last = #path - 1
	local x = math.clamp(f, 0, 1) * last
	local i = math.min(math.floor(x), last - 1)
	return path[i + 1]:Lerp(path[i + 2], x - i)
end

-- THE FLUME, f of the way down it.
local function flumeShot(current: Scene, root: BasePart, f: number)
	local here = root.Position
	local up = Vector3.yAxis
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
	local slideFrame = current.halls:GetAttribute("SlideFrame")
	local axis = if typeof(slideFrame) == "CFrame" then slideFrame.Position else here
	local out = Vector3.new(here.X - axis.X, 0, here.Z - axis.Z)
	out = if out.Magnitude > 0.05 then out.Unit else Vector3.xAxis
	local path = current.path
	local character = Players.LocalPlayer.Character
	local ignore = if character then { character } else {}
	if f < 0.09 then
		-- OVER THE SHOULDER, into the tube.
		local eye = Cinema.clear(here - flat * 10 + up * 5, here, ignore)
		Cinema.point(CFrame.lookAt(eye, here + flat * 10 - up * 3), 62)
	elseif f < 0.34 and path then
		-- CHASING: behind the rider along the trough and a little over it, the tube ahead of them.
		local behind = pathAt(path, f - 0.045)
		local eye = behind.Position + behind.UpVector * 4.2 + Vector3.new(0, 1.5, 0)
		Cinema.point(CFrame.lookAt(eye, here + look * 6 + up * 0.8), 70)
	elseif f < 0.5 then
		-- FROM THE SHAFT'S WALL, as they come round towards it: never across the mast from them.
		if once(current, "wall") then
			local ahead = CFrame.Angles(0, 0.9, 0) * out
			current.fallEye = Vector3.new(axis.X, here.Y - 10, axis.Z) + ahead * 55
			Cinema.cut()
		end
		Cinema.point(CFrame.lookAt(current.fallEye :: Vector3, here + Vector3.new(0, 1, 0)), 46)
	elseif f < 0.68 and path then
		-- FROM JUST AHEAD, looking back at them: lying back, arms crossed, the helix going up behind.
		local ahead = pathAt(path, math.min(1, f + 0.04))
		local eye = ahead.Position + ahead.UpVector * 3 + Vector3.new(0, 1, 0)
		Cinema.point(CFrame.lookAt(eye, here + Vector3.new(0, 1, 0)), 64)
	elseif f < 0.8 then
		-- FROM BELOW, as they shoot out of the end of the tube and past: the water's rush left behind in
		-- the tube, and only the air now.
		if once(current, "below") then
			current.fallEye = here - up * 34 + Vector3.new(flat.Z, 0, -flat.X) * 16 + flat * 10
			Cinema.cut()
		end
		if once(current, "wind") then
			local rush = current.rush
			if rush and rush.Parent then
				TweenService:Create(rush, TweenInfo.new(0.6), { Volume = 0 }):Play()
			end
			keep(current, sound("PlungeWind", WIND, 0.5, 0.8, false))
		end
		Cinema.point(CFrame.lookAt(current.fallEye :: Vector3, here), 58)
	else
		-- FROM ABOVE, as they fall into the dark, and far below something starts to show.
		Cinema.point(CFrame.lookAt(here + up * 15 + flat * 3, here - up * 12), 74)
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
		end
		if b > BEAT.key + 2.4 and once(current, "click") then
			keep(current, sound(nil, CLICK, 0.9, 0.55, false))
		end
		Cinema.point(CFrame.lookAt(at(-2.8, 4.2, -20.4), at(-8, 2.8, -22.6)), 48)
	elseif b < BEAT.midnight then
		-- THE WHEEL, AND THE GATE GOING UP.
		if once(current, "wheel") then
			holdMine("wheel")
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
		local push = ease((b - BEAT.wheel) / (BEAT.midnight - BEAT.wheel))
		local eye = at(-12, 6, -8):Lerp(at(-6, 8, -15), push)
		Cinema.point(CFrame.lookAt(eye, at(0, 13, -40)), 66)
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
	elseif b < current.gates + 0.8 then
		-- THE LAST LINE, pushing in from behind the rider toward the open gate and the light.
		if once(current, "last") then
			Cinema.caption("Harrow Bay", "14 August. 9:14 in the morning.", 7)
			-- The only chord of the four endings that resolves, left to ring out after the scene.
			local chord = sound("HallsChord", nil, 0.7, 1, false)
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

-- THE MOUTH, `m` seconds after the fall out of the tube ends. Its beats, in seconds:
local JAWS = {
	fall = 1.7, -- from above, falling in, the mouth opening under you
	inside = 2.9, -- from inside it, looking up at you coming down
	snap = 3.45, -- from the side, level with the teeth, as it shuts
	caption = 3.9, -- in the dark: the one line
}

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
	local hinge: CFrame = mouth.hinge
	local opens = -hinge.LookVector
	local side = hinge.UpVector
	local slideFrame = current.halls:GetAttribute("SlideFrame")
	local axis = if typeof(slideFrame) == "CFrame" then slideFrame.Position else hinge.Position
	local inward = Vector3.new(axis.X - hinge.Position.X, 0, axis.Z - hinge.Position.Z)
	inward = if inward.Magnitude > 0.1 then inward.Unit else Vector3.xAxis
	if once(current, "fall") then
		humanoid.PlatformStand = true
		holdMine("flail")
		current.rumble = sound("MawRumble", BASS, 0.9, 0.2, false)
		keep(current, current.rumble)
		Cinema.cut()
	end
	-- THE RIDER falls on into it, turning over, and is held where the jaws close.
	local floor = hinge.Position.Y + 8
	local drop = 22 * m + 7 * m * m
	local pos = from - Vector3.new(0, drop, 0)
	if pos.Y < floor then
		pos = Vector3.new(pos.X, floor, pos.Z)
	end
	if m >= JAWS.snap then
		pos = current.lastFall or pos
	end
	current.lastFall = pos
	root.CFrame = CFrame.new(pos) * CFrame.Angles(math.pi / 2 + m * 0.9, 0, m * 0.35)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	-- THE JAWS: opening wide under you, breathing, then shut.
	local upper, lower
	if m < JAWS.fall then
		local u = ease(m / JAWS.fall)
		upper, lower = 0.28 + (0.8 - 0.28) * u, 0.24 + (0.66 - 0.24) * u
	elseif m < JAWS.inside then
		local breath = 0.03 * math.sin((m - JAWS.fall) * 6)
		upper, lower = 0.8 + breath, 0.66 + breath
	else
		local u = math.clamp((m - JAWS.inside) / (JAWS.snap - JAWS.inside - 0.1), 0, 1)
		u = u * u * u
		upper, lower = 0.8 + (0.02 - 0.8) * u, 0.66 + (0.02 - 0.66) * u
	end
	Maw.set(mouth, upper, lower)
	Maw.light(mouth, if m < JAWS.fall then 0.3 + 0.7 * ease(m / JAWS.fall) else 1)
	if m < JAWS.fall then
		-- FROM ABOVE, falling with you: the mouth opening in the dark under you, the light coming up in
		-- it, pushing in as it rushes up (wider, then narrower: a dolly zoom).
		local u = ease(m / JAWS.fall)
		local back = 9 + 14 * u
		local fov = math.deg(2 * math.atan(6.2 / back))
		Cinema.point(CFrame.lookAt(pos + Vector3.new(0, back, 0) + inward * 2.5, pos - Vector3.new(0, 40, 0), side), fov)
		Cinema.focus(back + 30, 0.25)
	elseif m < JAWS.inside then
		-- FROM INSIDE IT, between the jaws a little up from the hinge, looking up at you coming down,
		-- the teeth either side of the picture.
		if once(current, "inside") then
			Cinema.cut()
		end
		local eye = hinge.Position + opens * 10 + inward * 4
		Cinema.point(CFrame.lookAt(eye, pos, side), 76)
		Cinema.focus((pos - eye).Magnitude, 0.35)
	elseif m < JAWS.snap then
		-- FROM THE SIDE, level with the teeth, as it shuts: kept inside the shaft's walls.
		if once(current, "bite") then
			Cinema.cut()
			Cinema.focus(nil)
		end
		if m > JAWS.snap - 0.2 and once(current, "snap") then
			keep(current, sound("JawsShut", BASS, 1, 0.3, false))
			Cinema.shake(3)
		end
		local eye = hinge.Position + opens * 30 + side * 24 + inward * 8
		Cinema.point(CFrame.lookAt(eye, hinge.Position + opens * 26), 58)
	else
		-- BLACK. Then only a heartbeat, from inside something.
		if once(current, "dark") then
			Cinema.black(true)
			local rumble = current.rumble
			if rumble and rumble.Parent then
				TweenService:Create(rumble, TweenInfo.new(0.4), { Volume = 0 }):Play()
			end
		end
		if m > JAWS.caption and once(current, "keeps") then
			Cinema.caption("The Hold", "It keeps what it is given.", 7)
		end
		if m > JAWS.caption + 0.2 and once(current, "heart") then
			current.heart = sound("Heartbeat", BASS, 0.6, 0.45, true)
			keep(current, current.heart)
		end
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
	local t = workspace:GetServerTimeNow() - current.began
	local f = t / current.slide
	if f < 1 then
		-- THE RIDE, drawn here: the rider's root on the path, every frame, lying back in the trough.
		local path = current.path
		if path and f >= 0 then
			humanoid.PlatformStand = true
			root.CFrame = pathAt(path, f)
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end
		if f >= 0.02 and once(current, "title") then
			Cinema.caption("The Corporation Baths", "Staff only beyond the flume.", 7)
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
				-- Ninety studs down: far enough that the fall into it can be watched, near enough that the
				-- lit teeth show from the end of the tube.
				current.mouth = Maw.build(Maw.facing(from - Vector3.new(0, 90, 0), Vector3.yAxis, Vector3.yAxis:Cross(radial)),
					workspace)
				Maw.set(current.mouth, 0.28, 0.24)
				Maw.light(current.mouth, 0)
			end
		end
		if current.mouth and f >= 0.8 then
			Maw.light(current.mouth, 0.3 * (f - 0.8) / 0.2)
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
		heart = nil, rumble = nil, lastFall = nil, path = path }
	if path and hallsEvent then
		hallsEvent:FireServer("riding")
	end
	if not (scene :: Scene).frame then
		(scene :: Scene).chamber = nil
	end
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

function FloodedHallsClient.start()
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	local event = remotes and remotes:WaitForChild("HallsCinema", 20)
	if not (event and event:IsA("RemoteEvent")) then
		warn("FloodedHallsClient: no RemoteEvents.HallsCinema, so the flume and the gates are not played as a scene. "
			.. "The server Bootstrap makes it; paste src/Server/Bootstrap.server.lua.")
		return
	end
	hallsEvent = event
	event.OnClientEvent:Connect(function(kind: any, player: any, began: any, slide: any, gates: any, maw: any)
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

return FloodedHallsClient
