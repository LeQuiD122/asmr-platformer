--!strict
-- StarterPlayerScripts/Services/HillHouseClient.lua
-- HILL HOUSE'S HALL (the hundred-and-twelfth pass): taking his key, as a scene, on your own screen.
--
-- HillHouseService stands you in front of the hook and says "key". Three shots, and then the level's banner (the
-- return to the lobby waits for the scene, as every ending's does):
--
--   TAKING IT (close)     in front of you and to one side, between you and the wall: your face, your hand on the
--                         key, the key coming off its hook on its green ribbon: "His key, where you left it last
--                         night."
--   HIS CLOCK (over you)  you turn to his longcase clock with the key in your hand, and the camera is over your
--                         shoulder on all of it, face to foot, its hands at four minutes to midnight since 1979; a
--                         beat, and its pendulum moves, and it ticks, and you start: it is going again.
--   THE WAY OUT (medium)  from the back of the hall, you by the open door with the morning bright behind you.
--
-- (The hundred-and-twenty-eighth pass, from your test of 2026-10-22: the first shot was behind your head, all hair and
-- shoulder; the clock was cut off at its face with nobody there to see it; your arm stuck straight out to the door.)
--
-- The key is gone from its hook on your screen from the first shot, and the pendulum swings on (on every screen that
-- has seen it start) while the house stands.
--
-- AND YOU ACT IT (the hundred-and-twentieth pass, from your test: "the player should have animations, not just stand
-- still"): you reach up to the hook and the key comes away in your hand on its ribbon, held up to look at; in the last
-- shot you go to the open door with it and look out at the morning.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cinema: any = (function()
	local found = script.Parent and script.Parent:WaitForChild("Cinema", 15)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()
local Poses: any = (function()
	local found = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Poses", 15)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()

local HillHouseClient = {}
HillHouseClient.VERSION = "the hundred-and-twenty-eighth pass, 2026-10-22"

-- How long each shot is held, and how far into the clock's shot it starts again.
local KEY_SHOT, CLOCK_SHOT, WAY_SHOT = 2.6, 3.4, 3.8
local CLOCK_STARTS = 0.9
-- The pendulum: how far it swings each way (radians) and how long a swing there and back takes (a longcase's two
-- seconds: one tick, one tock).
local SWING, PERIOD = 0.12, 2
-- YOU: when your hand reaches the hook and the key comes away, and how fast you go to the door with it.
local KEY_TAKEN = 0.8
local WAY_WALK = 4

type Scene = { model: Model, began: number, from: Vector3, clockCut: boolean, wayCut: boolean, started: boolean,
	done: boolean, keyed: boolean, handKey: Model?, speed: number?, walking: boolean, joints: { [string]: any }? }
local scene: Scene? = nil
local swinging: { [Model]: number } = {}
local failed = false

local function endScene(now: boolean?)
	local current = scene
	if not current then
		return
	end
	scene = nil
	-- You given back: your walk, your arms, and the key put away.
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and current.speed then
		humanoid.WalkSpeed = current.speed
	end
	if Poses and current.joints then
		for _, joint in pairs(current.joints) do
			Poses.drive(joint, CFrame.identity)
		end
	end
	if current.handKey then
		current.handKey:Destroy()
	end
	if Cinema then
		Cinema.finish(now)
	end
end

-- The key's prompt put away on this screen at once (it would hang over the hook all through the scene); with `parts`,
-- the key itself gone from its hook too.
local function hideKey(model: Model, parts: boolean)
	local key = model:FindFirstChild("HallKey", true)
	if key then
		for _, piece in ipairs(key:GetDescendants()) do
			if piece:IsA("BasePart") and parts then
				piece.Transparency = 1
			elseif piece:IsA("ProximityPrompt") then
				piece.Enabled = false
			end
		end
	end
end

-- HIS KEY IN YOUR HAND, on this screen: brass, its bow and its bit, and a loop of the green ribbon over your fingers.
local function keyInHand(character: Model): Model?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not (hand and hand:IsA("BasePart")) then
		return nil
	end
	local held = Instance.new("Model")
	held.Name = "HandKey"
	local brass, ribbon = Color3.fromRGB(196, 158, 76), Color3.fromRGB(58, 150, 88)
	local function bit(name: string, size: Vector3, offset: CFrame, colour: Color3, material: Enum.Material, shape: Enum.PartType?)
		local p = Instance.new("Part")
		p.Name = name
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.Color = colour
		p.Material = material
		p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, true
		p.CastShadow = false
		p.CFrame = hand.CFrame * offset
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = hand, p
		weld.Parent = p
		p.Parent = held
	end
	bit("KeyBow", Vector3.new(0.08, 0.42, 0.42), CFrame.new(0, -0.3, -0.25) * CFrame.Angles(0, math.pi / 2, 0), brass,
		Enum.Material.Metal, Enum.PartType.Cylinder)
	bit("KeyShank", Vector3.new(0.1, 0.1, 0.7), CFrame.new(0, -0.3, -0.75), brass, Enum.Material.Metal)
	bit("KeyBit", Vector3.new(0.08, 0.22, 0.2), CFrame.new(0, -0.38, -1.02), brass, Enum.Material.Metal)
	bit("KeyRibbon", Vector3.new(0.3, 0.6, 0.04), CFrame.new(0, -0.05, -0.12) * CFrame.Angles(0.4, 0, 0), ribbon,
		Enum.Material.Fabric)
	held.Parent = character
	return held
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- YOU, TAKING IT, `t` seconds in: the right arm up to the hook and the head tipped up to it; the key brought down in
-- front of you, the head bowed to look at it; then the arm lowered to your side as you go to the door. R15's axes (a
-- shoulder's +X swings the arm forward and up, the neck's +X tips the head back); nil for a joint left to your
-- animations (your legs walk you to the door).
local function heldPose(name: string, t: number): CFrame?
	-- Out to the key (it hangs at your chest, not up at the hook), then brought in to your chest, the forearm up and
	-- the head bowed over it; looking up to the clock as you turn to it, and starting back a little when it ticks;
	-- then carried low in front of you to the door.
	local reach = smooth(t / KEY_TAKEN)
	local bring = smooth((t - KEY_TAKEN) / 0.7)
	local look = smooth((t - KEY_SHOT) / 0.6)
	local lower = smooth((t - KEY_SHOT - CLOCK_SHOT) / 0.8)
	local since = t - KEY_SHOT - CLOCK_STARTS
	local start = if since > 0 then math.sin(math.min(since / 0.9, 1) * math.pi) else 0
	if name == "RightShoulder" then
		return CFrame.Angles(1.7 * reach * (1 - bring) + 0.85 * bring * (1 - lower) + 0.3 * lower, 0,
			-0.12 * math.max(reach, bring) * (1 - lower))
	elseif name == "RightElbow" then
		return CFrame.Angles(0.2 * reach * (1 - bring) + 1.35 * bring * (1 - lower) + 0.55 * lower, 0, 0)
	elseif name == "RightWrist" then
		return CFrame.Angles(0, 0, -0.35 * bring * (1 - lower))
	elseif name == "Neck" then
		return CFrame.Angles(-0.08 * reach * (1 - bring) - 0.38 * bring * (1 - look) + 0.22 * start, 0, 0)
	end
	return nil
end

-- After the animations each frame: you, as heldPose has you.
local function poseScene()
	local current = scene
	if not (current and Poses) then
		return
	end
	local character = Players.LocalPlayer.Character
	if not character then
		return
	end
	if not current.joints then
		current.joints = Poses.joints(character)
	end
	local t = os.clock() - current.began
	for name, joint in pairs(current.joints :: { [string]: any }) do
		local by = heldPose(name, t)
		if by then
			Poses.drive(joint, by)
		end
	end
	-- The moment your hand is at the hook: the key leaves it, and is in your hand.
	if not current.keyed and t >= KEY_TAKEN then
		current.keyed = true
		hideKey(current.model, true)
		current.handKey = keyInHand(character)
	end
end

-- The pendulums of every house this screen has seen start, swinging about their pivots.
local function swingPendulums(now: number)
	for model, since in pairs(swinging) do
		if not model.Parent then
			swinging[model] = nil
			continue
		end
		local pivot = model:GetAttribute("PendulumPivot")
		local rod = model:FindFirstChild("PendulumRod", true)
		local bob = model:FindFirstChild("PendulumBob", true)
		if typeof(pivot) == "CFrame" and rod and rod:IsA("BasePart") and bob and bob:IsA("BasePart") then
			-- Easing in over its first swing, as a pendulum given a push does.
			local amount = SWING * math.min(1, (now - since) / PERIOD)
			local swung = pivot * CFrame.Angles(0, 0, math.sin((now - since) / PERIOD * math.pi * 2) * amount)
			rod.CFrame = swung * CFrame.new(0, -1.5, 0)
			bob.CFrame = swung * CFrame.new(0, -3.1, 0) * CFrame.Angles(0, math.pi / 2, 0)
		end
	end
end

-- YOUR CAMERA KEPT IN THE HALL (the hundred-and-twenty-eighth pass, from your test: "I should not be able to go
-- through the floor, my camera I mean"): Roblox's camera stops only at what it can hit, and the window glass is not
-- that (nothing you can see through is), so it went out through the windows and, before the upstairs floor was made
-- solid, up into the empty upstairs. While your head is in the hall, after the camera has moved each frame, it is pulled
-- in toward you along its own line to the first wall, the ceiling or the floor it would have passed.
local HALL_MARGIN = 0.6
local hallModel: Instance? = nil
local hallLooked = 0

local function within(f: number, r: number, h: number, t: number): number
	if r > 1e-4 then
		return math.min(t, (h - f) / r)
	elseif r < -1e-4 then
		return math.min(t, (-h - f) / r)
	end
	return t
end

local function keepInHall()
	if scene or (Cinema and Cinema.active()) or Players.LocalPlayer:GetAttribute("InLevel") == nil then
		return
	end
	local now = os.clock()
	if not (hallModel and hallModel.Parent) and now - hallLooked > 2 then
		hallLooked = now
		hallModel = workspace:FindFirstChild("HillHouse", true)
	end
	local model = hallModel
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	if not (model and model.Parent and camera and head and head:IsA("BasePart")) then
		return
	end
	local box, size = model:GetAttribute("HallBox"), model:GetAttribute("HallSize")
	if typeof(box) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return
	end
	local half = size / 2 - Vector3.new(HALL_MARGIN, HALL_MARGIN, HALL_MARGIN)
	local focus = box:PointToObjectSpace(head.Position)
	if math.abs(focus.X) > half.X or math.abs(focus.Y) > half.Y or math.abs(focus.Z) > half.Z then
		return
	end
	local run = box:PointToObjectSpace(camera.CFrame.Position) - focus
	local t = within(focus.X, run.X, half.X, within(focus.Y, run.Y, half.Y, within(focus.Z, run.Z, half.Z, 1)))
	if t < 1 then
		camera.CFrame = CFrame.new(box:PointToWorldSpace(focus + run * math.max(t, 0))) * camera.CFrame.Rotation
	end
end

local function beginScene(model: Model)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (Cinema and root and root:IsA("BasePart")) or scene then
		return
	end
	scene = { model = model, began = os.clock(), from = root.Position, clockCut = false, wayCut = false, started = false,
		done = false, keyed = false, handKey = nil, speed = nil, walking = false, joints = nil }
	hideKey(model, false)
	Cinema.begin()
	Cinema.sound("KeyLift", 0.5, { keep = true })
	Cinema.caption("Hill House", "His key, on its green ribbon. Where you left it last night.", 6)
end

local function stepScene()
	local current = scene
	if not current then
		return
	end
	local model = current.model
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local t = os.clock() - current.began
	-- OVER when the lobby (or the next level) has them, when the house has gone, or at the latest long after.
	if not (root and root:IsA("BasePart")) or not model.Parent or (root.Position - current.from).Magnitude > 60 or t > 40 then
		endScene(true)
		return
	end
	local spot = model:GetAttribute("HallSpot")
	local keyAt = model:GetAttribute("HallKey")
	local face = model:GetAttribute("ClockFace")
	local out = model:GetAttribute("ClockFacing")
	local back = model:GetAttribute("HallBack")
	local door = model:GetAttribute("HallDoor")
	if not (typeof(spot) == "CFrame" and typeof(keyAt) == "Vector3" and typeof(face) == "Vector3" and typeof(out) == "Vector3"
		and typeof(back) == "Vector3" and typeof(door) == "Vector3") then
		endScene(true)
		return
	end
	local head = spot.Position + Vector3.new(0, 1.6, 0)
	local facing = spot.LookVector
	local side = spot.RightVector
	if t < KEY_SHOT then
		-- TAKING IT: in front of you and to one side, between you and the wall, a little under your eyes: your face,
		-- your hand on it, and the key coming away.
		local eye = head + side * 3 + facing * 1.5 + Vector3.new(0, -0.5, 0)
		Cinema.point(CFrame.lookAt(eye, keyAt:Lerp(head, 0.5)), 56)
	elseif t < KEY_SHOT + CLOCK_SHOT then
		-- HIS CLOCK, over your shoulder: you turn to it with the key in your hand, and all of it is in the picture, face
		-- to foot, the camera easing in; a beat, and it is going again, and you start.
		if not current.clockCut then
			current.clockCut = true
			Cinema.cut()
		end
		local toClock = Vector3.new(face.X - spot.Position.X, 0, face.Z - spot.Position.Z).Unit
		local right = toClock:Cross(Vector3.yAxis)
		local here = (root :: BasePart).Position
		;(root :: BasePart).CFrame = (root :: BasePart).CFrame:Lerp(CFrame.lookAt(here, here + toClock), 0.12)
		local k = math.clamp((t - KEY_SHOT) / CLOCK_SHOT, 0, 1)
		local eye = head - toClock * (3 - 0.6 * k) + right * 1 + Vector3.new(0, 0.5, 0)
		Cinema.point(CFrame.lookAt(eye, face + Vector3.new(0, -1.6, 0)), 50)
		if not current.started and t >= KEY_SHOT + CLOCK_STARTS then
			current.started = true
			swinging[model] = os.clock()
			Cinema.sound("ClockStart", 0.6, { keep = true })
			Cinema.caption("His clock", "Four minutes to midnight since 1979. It is going again.", 5)
		end
	else
		-- THE WAY OUT: from the back of the hall, you going to the open door with his key and looking out at the morning.
		if not current.wayCut then
			current.wayCut = true
			Cinema.cut()
		end
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and not current.walking then
			current.walking = true
			current.speed = humanoid.WalkSpeed
			humanoid.WalkSpeed = WAY_WALK
			humanoid:MoveTo(door)
		end
		local here = (root :: BasePart).Position
		if humanoid and (Vector3.new(here.X, 0, here.Z) - Vector3.new(door.X, 0, door.Z)).Magnitude < 0.7 then
			-- There: turned to face out of the door, slowly.
			local outside = CFrame.lookAt(here, here + facing)
			;(root :: BasePart).CFrame = (root :: BasePart).CFrame:Lerp(outside, 0.08)
		end
		Cinema.point(CFrame.lookAt(back, here + Vector3.new(0, 0.4, 0)), 50)
		if not current.done and t >= KEY_SHOT + CLOCK_SHOT + WAY_SHOT then
			current.done = true
			Cinema.done()
		end
	end
end

function HillHouseClient.start()
	if Cinema and Cinema.onLeave then
		Cinema.onLeave(function()
			endScene(true)
		end)
	end
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	local event = remotes and remotes:WaitForChild("HillScene", 20)
	if not (event and event:IsA("RemoteEvent")) then
		warn("HillHouseClient: no RemoteEvents.HillScene, so taking the key is not played as a scene. The server "
			.. "Bootstrap makes it; paste src/Server/Bootstrap.server.lua.")
		return
	end
	event.OnClientEvent:Connect(function(kind: any, model: any)
		if kind == "key" and typeof(model) == "Instance" and model:IsA("Model") then
			beginScene(model)
		end
	end)
	-- You, after the animations (as every pose in this game is).
	RunService.Stepped:Connect(function()
		local ok, err = pcall(poseScene)
		if not ok and not failed then
			failed = true
			warn("HillHouseClient: you could not be posed in the scene: " .. tostring(err))
		end
	end)
	-- Just after the camera has moved for the frame.
	RunService:BindToRenderStep("HillHallCamera", Enum.RenderPriority.Camera.Value + 1, function()
		local ok, err = pcall(keepInHall)
		if not ok and not failed then
			failed = true
			warn("HillHouseClient: the camera could not be kept in the hall: " .. tostring(err))
		end
	end)
	RunService.RenderStepped:Connect(function()
		swingPendulums(os.clock())
		local ok, err = pcall(stepScene)
		if not ok then
			if not failed then
				failed = true
				warn("HillHouseClient: the key's scene failed, and the camera is given back: " .. tostring(err))
			end
			pcall(endScene, true)
		end
	end)
	print("HillHouseClient: running, " .. HillHouseClient.VERSION)
end

HillHouseClient.STAMP = "899d813c"
return HillHouseClient
