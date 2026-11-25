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

-- His own mouth (the two-hundred-and-twenty-seventh pass): his made head cut at the lips, beside this.
local MarshMouth: any = (function()
	local found = script.Parent and script.Parent:FindFirstChild("MarshMouth")
	local ok, loaded = pcall(function()
		return if found and found:IsA("ModuleScript") then require(found) else nil
	end)
	return if ok then loaded else nil
end)()

local StalkerClient = {}
StalkerClient.VERSION = "the hundred-and-sixty-seventh pass, 2026-11-03"

-- THE WALK: studs of ground in a stride (a step of each leg), how quickly the copy catches up with where he is, and his
-- walking pace (BackRoomsService's WALK) that the swing is measured against.
local STRIDE, FOLLOW, PACE = 6.2, 12, 11.5
-- THE HEAD: how far round it turns to look at you (further than a neck goes), how far it tips, and how near you are
-- for it to.
local LOOK_TURN, LOOK_PITCH, LOOK_NEAR = math.rad(150), math.rad(50), 48
-- His footfall: a soft step of Roblox's own, slowed right down. Low and heavy, never a crack.
local THUD = "rbxasset://sounds/action_footsteps_plastic.mp3"
-- HE HAS YOU, IN HIS HANDS (the hundred-and-sixty-seventh pass, from your note of 2026-11-03: "fix the issue with the
-- backrooms animation where it incorrectly positions the characters in the hands of the monster"). His hands used to
-- close six studs out from him and above your head, round nothing, wherever you were. Now he is squared up to you
-- BackRoomsService's GRIP studs off, and this is the hold fitted to that (the sums are his rig's own, done again by
-- blender/check_backrooms.py): hunched right down on his knees bent the wrong way, the upper arms hanging, the long
-- forearms come forward along your sides and close at your middle, his fingers round behind your back, his face a stud
-- over yours, looking down. Each a joint's turn at the full hold (radians; `hips` studs down).
local HOLD = { hips = 1.2, spine = 0.97, thigh = 0.69, knee = 1.35, shoulder = 0.43, shoulderYaw = 0.9, shoulderRoll = 0.76,
	elbow = 1.9, elbowTwist = 0.87, neck = 0.6, head = 0.6 }

-- HIS FINGERS (the two-hundred-and-twenty-fourth pass): each joint of each finger (BackRoomsService welds two to a
-- finger), its rest, and the pivot at its knuckle, so they can flex on this screen.
type Knuckle = { weld: Weld, rest: CFrame, pivot: CFrame, tip: boolean, k: number }
type Seen = { real: Model, copy: Model, root: BasePart, motors: { [string]: Motor6D }, at: CFrame, phase: number,
	speed: number, snapUntil: number, snap: CFrame, nextLook: number, look: Vector2, tilt: number, grab: number,
	knuckles: { Knuckle }, tie: { weld: Weld, rest: CFrame, pivot: CFrame }?, spotted: number?,
	mouth: { skull: { Weld }, jaw: { Weld }, base: CFrame, hinge: CFrame, lids: { { weld: Weld, i: number } },
		scale: Vector3, teeth: { { part: BasePart, weld: Weld, frame: CFrame, len: number } } }?, open: number, eyes: number }
local seen: { [Model]: Seen } = {}
local failed = false

local function hide(model: Model)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") or item:IsA("Decal") then
			item.LocalTransparencyModifier = 1
		elseif item:IsA("SurfaceGui") then
			-- (His badge's words, the two-hundred-and-twenty-fifth pass: a part hidden still shows its SurfaceGui.)
			item.Enabled = false
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
	local knuckles: { Knuckle } = {}
	local tie = nil
	for _, item in ipairs(copy:GetDescendants()) do
		if item:IsA("Sound") then
			item:Destroy()
		elseif item:IsA("Motor6D") then
			motors[item.Name] = item
		elseif item:IsA("Weld") and item.Part1 and item.Part1.Name == "Tie" then
			tie = { weld = item, rest = item.C0, pivot = CFrame.new(0, -item.Part1.Size.Y / 2, 0) }
		elseif item:IsA("Weld") and item.Part1 and item.Part1.Name == "Finger" and item.Part0 then
			table.insert(knuckles, { weld = item, rest = item.C0, pivot = CFrame.new(0, -item.Part1.Size.Y / 2, 0),
				tip = item.Part0.Name == "Finger", k = #knuckles })
		end
	end
	copy.Name = "MarshSeen"
	-- HIS OWN JAW ON HIM (the two-hundred-and-twenty-seventh pass): where his head has been cut at the lips (MarshMouth),
	-- his made head is drawn in its two pieces on this copy, his teeth on his lips, so his own mouth can hang open as
	-- he walks, work when he stops, gape when he comes at you and open over you when he has you.
	local mouth = nil
	local cut = if MarshMouth then MarshMouth.pieces() else nil
	local made = copy:FindFirstChild("MadeHead")
	local headPart = copy:FindFirstChild("Head")
	if cut and made and made:IsA("BasePart") and headPart and headPart:IsA("BasePart") then
		local worn: Weld? = nil
		for _, item in ipairs(headPart:GetChildren()) do
			if item:IsA("Weld") and item.Part1 == made then
				worn = item
			end
		end
		if worn then
			local scale = made.Size / cut.meshSize
			local base = worn.C0
			made.Transparency = 1
			local function on(part: BasePart, list: { Weld }): BasePart
				local piece = part:Clone()
				piece.Size = part.Size * scale
				piece.Parent = copy
				local weld = Instance.new("Weld")
				weld.Part0 = headPart
				weld.Part1 = piece
				weld.C0 = base
				weld.Parent = headPart
				table.insert(list, weld)
				return piece
			end
			local skullWelds, jawWelds = {}, {}
			local teeth = {}
			local skull = on(cut.skull, skullWelds)
			if cut.palate then
				on(cut.palate, skullWelds)
			end
			-- HIS EYES (the two-hundred-and-twenty-eighth pass): his lids on his skull, shut, and his eyes behind them.
			local lidWelds = {}
			for i, lidPart in ipairs(cut.lids) do
				local lidPiece = lidPart:Clone()
				lidPiece.Size = lidPart.Size * scale
				lidPiece.Parent = copy
				local weld = Instance.new("Weld")
				weld.Part0 = skull
				weld.Part1 = lidPiece
				weld.C0 = CFrame.identity
				weld.Parent = lidPiece
				table.insert(lidWelds, { weld = weld, i = i })
			end
			for _, eyePart in ipairs(MarshMouth.eyeParts(scale)) do
				eyePart.part.Parent = copy
				local weld = Instance.new("Weld")
				weld.Part0 = skull
				weld.Part1 = eyePart.part
				weld.C0 = eyePart.offset
				weld.Parent = eyePart.part
			end
			local jaw = on(cut.jaw, jawWelds)
			if cut.floor then
				on(cut.floor, jawWelds)
			end
			for _, tooth in ipairs(MarshMouth.teeth()) do
				local long = tooth.len * scale.Y
				local part = Instance.new("Part")
				part.Name = "MouthTooth"
				part.Size = Vector3.new(0.05 * scale.Y, long, 0.05 * scale.Y)
				part.Color = Color3.fromRGB(196, 184, 160)
				part.Material = Enum.Material.SmoothPlastic
				part.Massless = true
				part.CanCollide, part.CanQuery, part.CanTouch = false, false, false
				part.CastShadow = false
				local spindle = Instance.new("SpecialMesh")
				spindle.MeshType = Enum.MeshType.Sphere
				spindle.Parent = part
				part.Parent = copy
				local weld = Instance.new("Weld")
				weld.Part0 = if tooth.upper then skull else jaw
				weld.Part1 = part
				weld.C0 = MarshMouth.toothFrame(tooth, scale) * CFrame.new(0, long / 2, 0)
				weld.Parent = part
				table.insert(teeth, { part = part, weld = weld, frame = MarshMouth.toothFrame(tooth, scale), len = long })
			end
			mouth = { skull = skullWelds, jaw = jawWelds, base = base, hinge = CFrame.new(MarshMouth.HINGE * scale),
				lids = lidWelds, scale = scale, teeth = teeth }
		end
	end
	copy.Parent = workspace
	hide(real)
	real.DescendantAdded:Connect(function(item: Instance)
		if item:IsA("BasePart") then
			item.LocalTransparencyModifier = 1
		end
	end)
	return { real = real, copy = copy, root = copyRoot, motors = motors, at = root.CFrame, phase = 0, speed = 0,
		snapUntil = 0, snap = CFrame.identity, nextLook = 0, look = Vector2.zero, tilt = 0, grab = 0, knuckles = knuckles, tie = tie,
		mouth = mouth, open = 0, eyes = 0 }
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

-- A CRACK OF HIS NECK (the two-hundred-and-twenty-sixth pass): soft and low, close to him, as his head snaps round.
-- (One of the chocolate snaps, uploaded for the materials, slowed right down: dull, close, a joint going.)
local CRACK = "rbxassetid://118391851257636"
local function crack(at: Vector3, loud: number)
	local spot = Instance.new("Attachment")
	spot.WorldPosition = at
	spot.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = CRACK
	s.PlaybackSpeed = 0.5 + math.random() * 0.08
	s.Volume = 0.35 * loud
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 4
	s.RollOffMaxDistance = 40
	s.Parent = spot
	s:Play()
	game:GetService("Debris"):AddItem(spot, 2)
end

-- His mouth `want` open (0 shut, 1 wide), eased there: the jaw dropping on its hinge under his ears, his skull tipping
-- back a little with it.
local function gape(one: Seen, want: number, dt: number)
	local mouth = one.mouth
	if not mouth then
		return
	end
	one.open += (want - one.open) * math.min(1, dt * 7)
	local h = mouth.hinge
	for _, weld in ipairs(mouth.jaw) do
		weld.C0 = mouth.base * h * CFrame.Angles(-math.rad(38) * one.open, 0, 0) * h:Inverse()
	end
	for _, weld in ipairs(mouth.skull) do
		weld.C0 = mouth.base * h * CFrame.Angles(math.rad(10) * one.open, 0, 0) * h:Inverse()
	end
	-- His teeth out of his gums only as far as his mouth is open (filmed at their whole length, they came out through his
	-- face with his mouth all but shut).
	local grow = math.clamp(one.open / 0.6, 0.05, 1)
	for _, tooth in ipairs(mouth.teeth) do
		local long = tooth.len * grow
		local size = tooth.part.Size
		tooth.part.Size = Vector3.new(size.X, long, size.Z)
		tooth.weld.C0 = tooth.frame * CFrame.new(0, long / 2, 0)
		tooth.part.Transparency = if one.open < 0.04 then 1 else 0
	end
end

-- His eyes `want` open (0 shut, 1 wide): his lids swinging up into his head, quickly.
local function stare(one: Seen, want: number, dt: number)
	local mouth = one.mouth
	if not mouth then
		return
	end
	one.eyes += (want - one.eyes) * math.min(1, dt * 14)
	for _, lid in ipairs(mouth.lids) do
		lid.weld.C0 = MarshMouth.lidTurn(lid.i, mouth.scale, one.eyes)
	end
end

local function drive(one: Seen, name: string, by: CFrame)
	local motor = one.motors[name]
	if motor then
		motor.Transform = by
	end
end

-- His fingers curled by `curl` (radians at the tip joint, half at the first; less than nought splays them), each a
-- little out of step with the others.
local function flex(one: Seen, curl: number, now: number, restless: number)
	for _, knuckle in ipairs(one.knuckles) do
		local own = curl + restless * math.sin(now * 2.6 + knuckle.k * 1.7)
		local bend = if knuckle.tip then own else own * 0.5
		knuckle.weld.C0 = knuckle.rest * knuckle.pivot:Inverse() * CFrame.Angles(bend, 0, 0) * knuckle.pivot
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
	-- from both sides, his head down at yours and tipping, twitching. Where the server squared him up to you, at once
	-- (not eased after: the hold is fitted to exactly that), and in HOLD's shape (see HOLD).
	if real:GetAttribute("Caught") == true then
		if one.grab == 0 then
			one.at = root.CFrame
			one.root.CFrame = one.at
		end
		one.grab = math.min(1, one.grab + dt / 0.35)
		local g = one.grab
		-- SEEN IN THE HOLD (the two-hundred-and-twenty-fifth pass: filmed, the lights round him low and red and he was a
		-- black shape over you). A faint cold light between you and him, on this screen alone: his face, his hands, his
		-- badge, just enough.
		local torsoPart = one.copy:FindFirstChild("Torso")
		if torsoPart and torsoPart:IsA("BasePart") and not torsoPart:FindFirstChild("HoldLight") then
			local spot = Instance.new("Attachment")
			spot.Name = "HoldLight"
			spot.Position = Vector3.new(0, 0.6, -2.4)
			spot.Parent = torsoPart
			local cold = Instance.new("PointLight")
			cold.Color = Color3.fromRGB(214, 222, 236)
			cold.Brightness = 0.55
			cold.Range = 7
			cold.Shadows = false
			cold.Parent = spot
		end
		drive(one, "Hip", CFrame.new(0, -HOLD.hips * g, 0))
		drive(one, "Spine", CFrame.Angles(-HOLD.spine * g, 0, 0))
		for side, sign in pairs({ L = 1, R = -1 }) do
			drive(one, "Hip" .. side, CFrame.Angles(-HOLD.thigh * g, 0, 0))
			drive(one, "Knee" .. side, CFrame.Angles(HOLD.knee * g, 0, 0))
			drive(one, "Shoulder" .. side, CFrame.Angles(HOLD.shoulder * g, -HOLD.shoulderYaw * sign * g,
				-HOLD.shoulderRoll * sign * g))
			drive(one, "Elbow" .. side, CFrame.Angles(HOLD.elbow * g, 0, -HOLD.elbowTwist * sign * g))
		end
		drive(one, "NeckJ", CFrame.Angles(HOLD.neck * g, 0, 0))
		drive(one, "HeadJ", CFrame.Angles(HOLD.head * g, 0, (0.45 + 0.1 * math.sin(now * 11)) * g))
		-- His fingers closing on you, and trembling there.
		flex(one, 0.75 * g, now, 0.06)
		-- His mouth open over you, quivering.
		gape(one, 0.85 * g + 0.06 * math.sin(now * 13), dt)
		stare(one, 1, dt)
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
	-- THE HIPS, dropping as each leg takes his weight and swaying across; dropping further and lurching over onto his
	-- right (A LIMP, the two-hundred-and-twenty-fifth pass: something wrong with that leg, and he goes on anyway).
	local limp = 0.2 * math.max(0, -s) * math.min(pace, 1.2)
	drive(one, "Hip", CFrame.new(0, -0.32 * math.abs(s) * pace - limp, 0)
		* CFrame.Angles(0, 0.14 * s * pace, 0.07 * s * pace - 0.5 * limp))
	-- THE LEGS: a thigh's +X swings it forward; a knee's +X bends it FORWARD, the wrong way, as its leg is behind him.
	-- The right one shorter in its swing, dragged.
	for side, sign in pairs({ L = 1, R = -1 }) do
		local leg = s * sign
		drive(one, "Hip" .. side, CFrame.Angles(leg * swing * (if side == "R" then 0.7 else 1), 0, 0))
		drive(one, "Knee" .. side, CFrame.Angles(0.75 * math.max(0, -leg) * math.min(pace, 1.2), 0, 0))
	end
	-- THE BODY, stooping further when he rushes (a spine's -X pitches it forward).
	-- And his breathing: slow, deep heaves of his back, deepest when he has stopped (the two-hundred-and-twenty-fourth
	-- pass).
	local breath = math.sin(now * 2.2) * (if paused then 0.07 else 0.025)
	drive(one, "Spine", CFrame.Angles((if rushing then -0.35 else 0) - 0.05 * math.abs(s) * pace + breath, 0.1 * s * pace, 0))
	-- His fingers: flexing as he walks, working slowly when he stops, splayed open reaching when he rushes.
	flex(one, if rushing then -0.3 else 0.12, now, if paused then 0.3 else 0.15)
	-- HIS TIE (the same pass): swinging off his stooped chest as he walks, and flying out ahead of him when he comes
	-- at you.
	local tie = one.tie
	if tie then
		local hang = (if rushing then 0.6 else 0.12) + 0.14 * s * pace + 0.05 * math.sin(now * 1.7)
		tie.weld.C0 = tie.rest * tie.pivot:Inverse() * CFrame.Angles(hang, 0, 0) * tie.pivot
	end
	-- THE ARMS: late and loose against the legs; rushing, up and out at you (a shoulder's +X swings the arm forward).
	for side, sign in pairs({ L = 1, R = -1 }) do
		local late = -math.sin(one.phase * math.pi * 2 - 0.9) * sign
		if rushing then
			drive(one, "Shoulder" .. side, CFrame.Angles(1.4 + 0.12 * late, 0, -0.15 * sign))
			drive(one, "Elbow" .. side, CFrame.Angles(0.25, 0, 0))
		else
			-- (His left shoulder hitched up higher than the right, and held there.)
			drive(one, "Shoulder" .. side, CFrame.new(0, if side == "L" then 0.12 else 0, 0)
				* CFrame.Angles(0.35 * late * math.min(pace, 1.2), 0, 0.05 * sign))
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
	-- HE HAS SEEN YOU (BackRoomsService writes Spotted as he stops dead): his head snaps straight round to you with a
	-- crack, and holds there, staring, until he comes.
	if real:GetAttribute("Spotted") ~= nil and not one.spotted then
		one.spotted = now
		if head and head:IsA("BasePart") then
			crack(head.Position, 1)
		end
	end
	local staring = one.spotted ~= nil and now - (one.spotted :: number) < 1.0
	-- HIS EYES: shut, as they always were, until he has seen you; then open, on you, and they stay open.
	stare(one, if one.spotted ~= nil then 1 else 0, dt)
	-- HIS MOUTH: slack as he walks, working slowly when he stops, shut tight as he stares, and wide as he comes at you.
	gape(one, if staring then 0 elseif rushing then 0.8 + 0.08 * math.sin(now * 9)
		elseif paused then 0.16 + 0.12 * math.sin(now * 2.1) else 0.07 + 0.03 * math.sin(now * 1.3), dt)
	if staring then
		one.look = want
		one.nextLook = now + 0.2
	elseif now >= one.nextLook then
		one.nextLook = now + 0.08 + math.random() * 0.22
		one.look = one.look:Lerp(want, 0.55)
	end
	one.tilt += ((if paused and not staring then 0.7 else 0) - one.tilt) * math.min(1, dt * 1.5)
	if not staring and now >= one.snapUntil and math.random() < dt * 0.9 then
		one.snapUntil = now + 0.12 + math.random() * 0.2
		if head and head:IsA("BasePart") and math.random() < 0.5 then
			crack(head.Position, 0.6)
		end
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

StalkerClient.STAMP = "a6823855"
return StalkerClient
