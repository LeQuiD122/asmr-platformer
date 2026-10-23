--!strict
-- StarterPlayerScripts/Services/StalkerClient.lua
-- HIM, IN THE BACK ROOMS, ALIVE AND WRONG (the hundred-and-twenty-first pass, from your test: "the animation for the
-- monster in the backrooms is messed up and should be scarier"). BackRoomsService carries him (an invisible root moved
-- each frame, and Paused and Rushing written on him); this draws him on your screen, walking:
--
--   THE STRIDE   long slow steps on legs like poles, the knees bending the wrong way as each leg comes through, his
--                hips dropping and swaying under each step, and a heavy soft thud as each foot comes down.
--   THE ARMS     hanging past his knees, swinging late and loose; rushing, they come up and reach out at you.
--   THE HEAD     bowed and lolling, and now and then snapping to another angle for a moment; when you can see him, it
--                turns to look at you in stiff jerks, further round than a neck should go.
--   STOPPED      when he stops, his head tips slowly over, too far.
--
-- His own body (the server's) is hidden on this screen and a copy of it drawn in its place, eased after where he really
-- is, so he never jumps; the copy goes when he does.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local StalkerClient = {}
StalkerClient.VERSION = "the hundred-and-twenty-first pass, 2026-10-22"

-- THE WALK: studs of ground in a stride (a step of each leg), how quickly the copy catches up with where he is, and his
-- walking pace (BackRoomsService's WALK) that the swing is measured against.
local STRIDE, FOLLOW, PACE = 6.2, 12, 11.5
-- THE HEAD: how far round it turns to look at you (further than a neck goes), how far it tips, and how near you are
-- for it to.
local LOOK_TURN, LOOK_PITCH, LOOK_NEAR = math.rad(150), math.rad(50), 48
-- His footfall: a soft step of Roblox's own, slowed right down. Low and heavy, never a crack.
local THUD = "rbxasset://sounds/action_footsteps_plastic.mp3"

type Seen = { real: Model, copy: Model, root: BasePart, motors: { [string]: Motor6D }, at: CFrame, phase: number,
	speed: number, snapUntil: number, snap: CFrame, nextLook: number, look: Vector2, tilt: number, grab: number }
local seen: { [Model]: Seen } = {}
local failed = false

local function hide(model: Model)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") or item:IsA("Decal") then
			item.LocalTransparencyModifier = 1
		end
	end
end

-- HIS COPY ON THIS SCREEN, his own hidden: the copy without his breath (his own still breathes where he is).
local function copyOf(real: Model): Seen?
	local root = real.PrimaryPart
	if not root then
		return nil
	end
	local copy = real:Clone()
	local copyRoot = copy.PrimaryPart
	if not copyRoot then
		copy:Destroy()
		return nil
	end
	local motors: { [string]: Motor6D } = {}
	for _, item in ipairs(copy:GetDescendants()) do
		if item:IsA("Sound") then
			item:Destroy()
		elseif item:IsA("Motor6D") then
			motors[item.Name] = item
		end
	end
	copy.Name = "MarshSeen"
	copy.Parent = workspace
	hide(real)
	real.DescendantAdded:Connect(function(item: Instance)
		if item:IsA("BasePart") then
			item.LocalTransparencyModifier = 1
		end
	end)
	return { real = real, copy = copy, root = copyRoot, motors = motors, at = root.CFrame, phase = 0, speed = 0,
		snapUntil = 0, snap = CFrame.identity, nextLook = 0, look = Vector2.zero, tilt = 0, grab = 0 }
end

local function thud(at: Vector3, loud: number)
	local spot = Instance.new("Attachment")
	spot.WorldPosition = at
	spot.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = THUD
	s.PlaybackSpeed = 0.42 + math.random() * 0.06
	s.Volume = 0.5 * loud
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 6
	s.RollOffMaxDistance = 70
	s.Parent = spot
	s:Play()
	game:GetService("Debris"):AddItem(spot, 2)
end

local function drive(one: Seen, name: string, by: CFrame)
	local motor = one.motors[name]
	if motor then
		motor.Transform = by
	end
end

local function animate(one: Seen, dt: number, now: number, camera: Camera?)
	local real = one.real
	local root = real.PrimaryPart :: BasePart
	-- WHERE HE IS, eased after: he never jumps.
	local before = one.at.Position
	one.at = one.at:Lerp(root.CFrame, 1 - math.exp(-dt * FOLLOW))
	one.root.CFrame = one.at
	-- HE HAS YOU (the hundred-and-twenty-fifth pass, from your test: "the animation of the backrooms monster kill is
	-- weird"): caught, he folds right down over you, his knees giving the wrong way under him, his arms coming round you
	-- from both sides, his head down at yours and tipping, twitching.
	if real:GetAttribute("Caught") == true then
		one.grab = math.min(1, one.grab + dt / 0.35)
		local g = one.grab
		drive(one, "Hip", CFrame.new(0, -0.7 * g, 0))
		drive(one, "Spine", CFrame.Angles(-0.7 * g, 0, 0))
		for side, sign in pairs({ L = 1, R = -1 }) do
			drive(one, "Hip" .. side, CFrame.Angles(-0.3 * g, 0, 0))
			drive(one, "Knee" .. side, CFrame.Angles(0.7 * g, 0, 0))
			drive(one, "Shoulder" .. side, CFrame.Angles(1.65 * g, 0, -0.32 * sign * g))
			drive(one, "Elbow" .. side, CFrame.Angles(0.95 * g, 0, 0))
		end
		drive(one, "NeckJ", CFrame.Angles(-0.3 * g, 0, 0))
		drive(one, "HeadJ", CFrame.Angles(-0.45 * g, 0, (0.45 + 0.1 * math.sin(now * 11)) * g))
		return
	end
	local moved = Vector3.new(one.at.Position.X - before.X, 0, one.at.Position.Z - before.Z).Magnitude
	one.speed += (moved / math.max(dt, 1e-3) - one.speed) * math.min(1, dt * 6)
	local rushing = real:GetAttribute("Rushing") == true
	local paused = real:GetAttribute("Paused") == true or one.speed < 0.5
	local pace = math.clamp(one.speed / PACE, 0, 1.8)
	local was = one.phase
	one.phase += moved / STRIDE
	-- A FOOT DOWN at every half stride.
	if math.floor(one.phase * 2) ~= math.floor(was * 2) then
		thud(one.at.Position, math.clamp(pace, 0.4, 1.2))
	end
	local s = math.sin(one.phase * math.pi * 2)
	local swing = 0.55 * math.min(pace, 1.2)
	-- THE HIPS, dropping as each leg takes his weight and swaying across.
	drive(one, "Hip", CFrame.new(0, -0.32 * math.abs(s) * pace, 0) * CFrame.Angles(0, 0.14 * s * pace, 0.07 * s * pace))
	-- THE LEGS: a thigh's +X swings it forward; a knee's +X bends it FORWARD, the wrong way, as its leg is behind him.
	for side, sign in pairs({ L = 1, R = -1 }) do
		local leg = s * sign
		drive(one, "Hip" .. side, CFrame.Angles(leg * swing, 0, 0))
		drive(one, "Knee" .. side, CFrame.Angles(0.75 * math.max(0, -leg) * math.min(pace, 1.2), 0, 0))
	end
	-- THE BODY, stooping further when he rushes (a spine's -X pitches it forward).
	drive(one, "Spine", CFrame.Angles((if rushing then -0.35 else 0) - 0.05 * math.abs(s) * pace, 0.1 * s * pace, 0))
	-- THE ARMS: late and loose against the legs; rushing, up and out at you (a shoulder's +X swings the arm forward).
	for side, sign in pairs({ L = 1, R = -1 }) do
		local late = -math.sin(one.phase * math.pi * 2 - 0.9) * sign
		if rushing then
			drive(one, "Shoulder" .. side, CFrame.Angles(1.4 + 0.12 * late, 0, -0.15 * sign))
			drive(one, "Elbow" .. side, CFrame.Angles(0.25, 0, 0))
		else
			drive(one, "Shoulder" .. side, CFrame.Angles(0.35 * late * math.min(pace, 1.2), 0, 0.05 * sign))
			drive(one, "Elbow" .. side, CFrame.Angles(0.15 + 0.1 * math.abs(late), 0, 0))
		end
	end
	-- THE HEAD: toward you when you can see him (in stiff jerks, further round than a neck goes); else bowed and lolling,
	-- and tipping over when he stops; and now and then a snap to another angle for a moment.
	local want = Vector2.zero
	local head = one.copy:FindFirstChild("Head")
	local torso = one.copy:FindFirstChild("Torso")
	if camera and head and head:IsA("BasePart") and torso and torso:IsA("BasePart") then
		local to = camera.CFrame.Position - head.Position
		if to.Magnitude < LOOK_NEAR and camera.CFrame.LookVector:Dot(-to.Unit) > 0.55 then
			local rel = torso.CFrame:VectorToObjectSpace(to.Unit)
			want = Vector2.new(math.clamp(math.atan2(-rel.X, -rel.Z), -LOOK_TURN, LOOK_TURN),
				math.clamp(math.asin(math.clamp(rel.Y, -1, 1)) + 0.6, -LOOK_PITCH, LOOK_PITCH))
		end
	end
	if now >= one.nextLook then
		one.nextLook = now + 0.08 + math.random() * 0.22
		one.look = one.look:Lerp(want, 0.55)
	end
	one.tilt += ((if paused then 0.7 else 0) - one.tilt) * math.min(1, dt * 1.5)
	if now >= one.snapUntil and math.random() < dt * 0.9 then
		one.snapUntil = now + 0.12 + math.random() * 0.2
		one.snap = CFrame.Angles((math.random() - 0.5) * 0.6, (math.random() - 0.5) * 0.9, (math.random() - 0.5) * 1.2)
	end
	local loll = CFrame.Angles(0.06 * math.sin(now * 1.3), 0, 0.18 * math.sin(now * 0.8) + one.tilt)
	drive(one, "HeadJ", CFrame.Angles(one.look.Y, one.look.X, 0) * loll * (if now < one.snapUntil then one.snap else CFrame.identity))
	drive(one, "NeckJ", CFrame.Angles(0.04 * s * pace, 0, 0))
end

local function step(dt: number)
	local rooms = workspace:FindFirstChild("BackRooms")
	if rooms then
		for _, child in ipairs(rooms:GetChildren()) do
			if child.Name == "Marsh" and child:IsA("Model") and not seen[child] then
				local made = copyOf(child)
				if made then
					seen[child] = made
				end
			end
		end
	end
	local camera = workspace.CurrentCamera
	local now = os.clock()
	for real, one in pairs(seen) do
		if not (real.Parent and real.PrimaryPart and one.copy.Parent) then
			one.copy:Destroy()
			seen[real] = nil
			continue
		end
		animate(one, dt, now, camera)
	end
end

function StalkerClient.start()
	RunService.RenderStepped:Connect(function(dt: number)
		local ok, err = pcall(step, dt)
		if not ok and not failed then
			failed = true
			warn("StalkerClient: " .. tostring(err) .. " (shown once)")
		end
	end)
	print("StalkerClient: running, " .. StalkerClient.VERSION .. " for " .. Players.LocalPlayer.Name)
end

StalkerClient.STAMP = "54373819"
return StalkerClient
