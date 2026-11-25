--!strict
-- StarterPlayerScripts/Services/StoryClient.lua
-- The story's small moments, on this player's screen (Interactables tells it when, over the
-- StoryMoment remote):
--
--   whisper   one line low on the screen for a few seconds: "It is rusted shut."
--   pry       THE BAR AT WORK, the first time it opens something: over your shoulder you turn to it, set the
--             bar, three hard tugs with dust coming out of it, what you think of it over your head; on the
--             last tug it gives (the server opens it then): an impact frame, and you jump back.
--   moment    a SECRET found: a short scene (Cinema, the level's sound left alone), with YOU in it: over your
--             shoulder, hand at your chin and head tilting, working out what this is, what you make of it over
--             your head; then the camera drifts in along a curve on what you have found, sharp on it and soft
--             round it, a low sting under it, its name and a line; then a card, "Secret 2 of 6", which says its
--             words are in your journal (the server has put them there: JournalService).
--   peek      the loose board on the gangway: you lean over the gap; the camera looks straight down into the
--             shaft, and a long way down, in the dark, something opens its mouth a little and breathes (Maw),
--             and you jolt; then back up to you, backing off it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local Cinema: any = (function()
	local found = script.Parent and script.Parent:WaitForChild("Cinema", 15)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()
-- His own mouth, cut from his made head (the two-hundred-and-twenty-seventh pass): MarshMouth beside this.
local MarshMouth: any = (function()
	local found = script.Parent and script.Parent:FindFirstChild("MarshMouth")
	local ok, loaded = pcall(function()
		return if found and found:IsA("ModuleScript") then require(found) else nil
	end)
	return if ok then loaded else nil
end)()
local Maw: any = (function()
	local found = script.Parent and script.Parent:FindFirstChild("Maw")
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()
local Poses: any = (function()
	local shared = ReplicatedStorage:WaitForChild("Shared", 15)
	local found = shared and shared:FindFirstChild("Poses")
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()

local StoryClient = {}
StoryClient.VERSION = "eighteenth pass, 2026-09-29"

local busy = false

local function sound(name: string, fallback: string?, volume: number, speed: number): Sound?
	local folder = SoundService:FindFirstChild("StorySounds")
	local own = folder and folder:FindFirstChild(name)
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
	made.Parent = SoundService
	made:Play()
	game:GetService("Debris"):AddItem(made, 12)
	return made
end

local function gui(name: string, order: number): ScreenGui?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end
	local old = playerGui:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local made = Instance.new("ScreenGui")
	made.Name = name
	made.ResetOnSpawn = false
	made.DisplayOrder = order
	made.Parent = playerGui
	return made
end

-- One line, low on the screen, for a few seconds.
local function whisper(text: string)
	local screen = gui("StoryWhisper", 26)
	if not screen then
		return
	end
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	-- Above the level's opening words (which sit low, at 0.86), so the two never print over each other.
	label.Position = UDim2.new(0.5, 0, 0.7, 0)
	label.Size = UDim2.new(0.8, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.TextWrapped = true
	label.FontFace = Style.FONT.body
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(236, 232, 218)
	label.TextStrokeTransparency = 0.4
	label.TextTransparency = 1
	label.Text = text
	label.Parent = screen
	TweenService:Create(label, TweenInfo.new(0.5), { TextTransparency = 0 }):Play()
	task.delay(5, function()
		if label.Parent then
			TweenService:Create(label, TweenInfo.new(1), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.delay(1.1, function()
				screen:Destroy()
			end)
		end
	end)
end

-- HOW TO READ IT, ON THE DEVICE IN HAND (the hundred-and-forty-seventh pass): the card said "Press J" to a controller and
-- a phone too. The journal's own words for it (JournalService's line in the corner).
local function readHint(): string
	local input = game:GetService("UserInputService")
	if input:GetLastInputType().Name:sub(1, 7) == "Gamepad" then
		return "Kept in your journal. Press D-pad up to read it."
	elseif input.TouchEnabled and not input.KeyboardEnabled then
		return "Kept in your journal. Tap the book to read it."
	end
	return "Kept in your journal. Press J to read it."
end

-- "Secret 2 of 5": the card after a moment, as the keepsakes have.
local function card(title: string, found: number, total: number)
	local screen = gui("SecretCard", 23)
	if not screen then
		return
	end
	local paper = Instance.new("Frame")
	paper.AnchorPoint = Vector2.new(0.5, 0)
	paper.Position = UDim2.new(0.5, 0, 0, -120)
	paper.Size = UDim2.new(0.9, 0, 0, 0)
	paper.AutomaticSize = Enum.AutomaticSize.Y
	paper.BackgroundColor3 = Color3.fromRGB(24, 26, 28)
	paper.BackgroundTransparency = 0.1
	paper.BorderSizePixel = 0
	paper.Parent = screen
	local widest = Instance.new("UISizeConstraint")
	widest.MaxSize = Vector2.new(380, math.huge)
	widest.Parent = paper
	local edge = Instance.new("UIStroke")
	edge.Color = Color3.fromRGB(150, 140, 110)
	edge.Thickness = 1
	edge.Parent = paper
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = paper
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 3)
	list.Parent = paper
	for index, row in ipairs({ { ("SECRET %d OF %d"):format(found, total), 12, Color3.fromRGB(180, 170, 140) },
		{ title, 18, Color3.fromRGB(236, 232, 218) },
		{ readHint(), 14, Color3.fromRGB(200, 192, 170) } }) do
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.TextWrapped = true
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.FontFace = if index == 1 then Style.FONT.heading else Style.FONT.body
		label.TextSize = row[2] :: number
		label.TextColor3 = row[3] :: Color3
		label.Text = row[1] :: string
		label.LayoutOrder = index
		label.Parent = paper
	end
	TweenService:Create(paper, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 0, 64) }):Play()
	task.delay(6, function()
		if paper.Parent then
			local away = TweenService:Create(paper, TweenInfo.new(0.7), { Position = UDim2.new(0.5, 0, 0, -140) })
			away:Play()
			away.Completed:Wait()
			screen:Destroy()
		end
	end)
end

-- ===== YOU, IN THE SCENE =====
--
-- The secret scenes used to be the camera alone, drifting onto what had been found, which left you wondering what had
-- happened. Now you act it out: you turn to the thing, work the bar into it (three hard tugs), jump back when it
-- gives, then stand there working it out, hand at your chin and head tilting, while what you make of it shows over
-- your head (Cinema.think). Your own character, posed on this screen only (Poses, through the animations' own way in).
type Act = { pose: string, began: number }
local acting: { now: Act?, before: Act?, switched: number, joints: { [string]: any }?, model: Instance?,
	hook: RBXScriptConnection? } = { now = nil, before = nil, switched = 0, joints = nil, model = nil, hook = nil }
local BLEND = 0.3 -- seconds from one pose into the next

local function poseOf(entry: Act?, name: string, r6: boolean, now: number): CFrame
	if not (entry and Poses) then
		return CFrame.identity
	end
	local make = Poses[entry.pose]
	if type(make) ~= "function" then
		return CFrame.identity
	end
	return make(name, now - entry.began, 1, r6) or CFrame.identity
end

local function driveActing()
	local character = Players.LocalPlayer.Character
	if not (character and Poses) then
		return
	end
	if acting.model ~= character then
		acting.model = character
		acting.joints = Poses.joints(character)
	end
	local joints = acting.joints
	if not joints then
		return
	end
	local now = os.clock()
	local r6 = Poses.isR6(joints)
	local blend = math.clamp((now - acting.switched) / BLEND, 0, 1)
	blend = blend * blend * (3 - 2 * blend)
	for name, joint in pairs(joints) do
		local from = poseOf(acting.before, name, r6, now)
		local to = poseOf(acting.now, name, r6, now)
		Poses.drive(joint, from:Lerp(to, blend))
	end
	-- Back to the animations once the last pose has blended out.
	if not acting.now and blend >= 1 then
		for _, joint in pairs(joints) do
			Poses.drive(joint, CFrame.identity)
		end
		local hook = acting.hook
		if hook then
			hook:Disconnect()
			acting.hook = nil
		end
	end
end

-- Into `pose` (one of Poses': "pry", "ponder", "startle", "peer"), or out of any with nil.
local function act(pose: string?)
	local now = os.clock()
	acting.before = acting.now
	acting.now = if pose then { pose = pose, began = now } else nil
	acting.switched = now
	if not acting.hook then
		acting.hook = RunService.Stepped:Connect(function()
			pcall(driveActing)
		end)
	end
end

-- The thing in front of you: turned to face it (your own character, on your own screen first; the server follows).
local function faceToward(at: Vector3)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local flat = Vector3.new(at.X - root.Position.X, 0, at.Z - root.Position.Z)
		if flat.Magnitude > 0.2 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		end
	end
end

-- THE TWO-SHOT: you and the thing, SIDE ON, so your face and what you are doing are both in it. It was over your
-- shoulder, and your back filled the picture; on the baths' narrow gangway the wall behind you pulled the camera in
-- until it was your head and nothing else. Now from the side with the more room (Cinema.clear tells), a little above
-- and a little back, the side kept for the whole scene so it never swaps; from above only if neither side has room.
local twoShotSide: number? = nil
local function twoShot(at: Vector3, push: number): CFrame?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return nil
	end
	local forward = Vector3.new(at.X - root.Position.X, 0, at.Z - root.Position.Z)
	forward = if forward.Magnitude > 0.2 then forward.Unit else Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local right = forward:Cross(Vector3.yAxis)
	local head = root.Position + Vector3.new(0, 1.5, 0)
	local mid = head:Lerp(Vector3.new(at.X, math.max(at.Y, head.Y - 1.2), at.Z), 0.5)
	local reach = 7.5 - 2 * math.clamp(push, 0, 1)
	local ignore = { character }
	local function from(side: number): Vector3
		return Cinema.clear(mid + right * side * reach - forward * reach * 0.35 + Vector3.new(0, 1.4, 0), mid, ignore)
	end
	if not twoShotSide then
		local rightRoom, leftRoom = (from(1) - mid).Magnitude, (from(-1) - mid).Magnitude
		twoShotSide = if math.max(rightRoom, leftRoom) < 3.2 then 0 elseif leftRoom > rightRoom + 0.5 then -1 else 1
	end
	local eye = if twoShotSide == 0 then Cinema.clear(mid - forward * 4 + Vector3.new(0, 7, 0), mid, ignore)
		else from(twoShotSide :: number)
	return CFrame.lookAt(eye, mid)
end

-- THE BAR IN YOUR HANDS for the scene: the one on your back hidden on this screen, one in your right hand instead.
local barHeld: { hand: BasePart?, hidden: { BasePart } } = { hand = nil, hidden = {} }
local function barInHands(on: boolean)
	local character = Players.LocalPlayer.Character
	if on then
		if barHeld.hand or not character then
			return
		end
		for _, name in ipairs({ "PryBarCarried", "PryBarClaw" }) do
			local part = character:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				part:SetAttribute("SceneWas", part.Transparency)
				part.Transparency = 1
				table.insert(barHeld.hidden, part)
			end
		end
		local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		if hand and hand:IsA("BasePart") then
			local bar = Instance.new("Part")
			bar.Name = "SceneBar"
			bar.Size = Vector3.new(0.2, 3.2, 0.2)
			bar.Color = Color3.fromRGB(46, 44, 48)
			bar.Material = Enum.Material.Metal
			bar.CanCollide = false
			bar.CanTouch = false
			bar.CanQuery = false
			bar.Massless = true
			bar.CFrame = hand.CFrame * CFrame.new(0, -0.3, -0.6) * CFrame.Angles(math.rad(-70), 0, 0)
			local weld = Instance.new("WeldConstraint")
			weld.Part0, weld.Part1 = hand, bar
			weld.Parent = bar
			bar.Parent = character
			barHeld.hand = bar
		end
	else
		if barHeld.hand then
			barHeld.hand:Destroy()
			barHeld.hand = nil
		end
		for _, part in ipairs(barHeld.hidden) do
			local was = part:GetAttribute("SceneWas")
			part.Transparency = if typeof(was) == "number" then was else 0
		end
		table.clear(barHeld.hidden)
	end
end

-- A puff of dust out of the thing as the bar bites.
local function dust(at: Vector3)
	local puff = Instance.new("Part")
	puff.Name = "PryDust"
	puff.Size = Vector3.new(1, 1, 1)
	puff.Transparency = 1
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanTouch = false
	puff.CanQuery = false
	puff.CFrame = CFrame.new(at)
	puff.Parent = workspace
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxasset://textures/particles/smoke_main.dds"
	motes.Color = ColorSequence.new(Color3.fromRGB(196, 184, 166))
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.2) })
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	motes.Lifetime = NumberRange.new(0.6, 1.1)
	motes.Speed = NumberRange.new(1.5, 4)
	motes.SpreadAngle = Vector2.new(60, 60)
	motes.Acceleration = Vector3.new(0, -2, 0)
	motes.Rate = 0
	motes.Parent = puff
	motes:Emit(14)
	game:GetService("Debris"):AddItem(puff, 2)
end

-- THE SCENE'S END, whichever way it ends: the pose let go, the bar back on your back, the camera given back.
local scene: { prying: boolean, token: number, held: BasePart? } = { prying = false, token = 0, held = nil }
local function endScene()
	act(nil)
	barInHands(false)
	twoShotSide = nil
	scene.prying = false
	-- LET GO OF (the lever's scene holds you at the box, leverBox).
	local held = scene.held
	scene.held = nil
	if held and held.Parent then
		held.Anchored = false
	end
	busy = false
	if Cinema then
		Cinema.finish()
	end
end

-- How long the bar works before the thing gives (Interactables waits as long before it opens it).
local PRY_SECONDS = 1.75

-- CHIPS OF BRICK knocked out of the wall: little pieces of it, flying out and tumbling to the floor, on this screen.
local function chips(at: Vector3, out: Vector3, count: number, power: number)
	for _ = 1, count do
		local chip = Instance.new("Part")
		chip.Name = "BrickChip"
		chip.Size = Vector3.new(0.12 + math.random() * 0.2, 0.1 + math.random() * 0.12, 0.12 + math.random() * 0.2)
		chip.Color = Color3.fromRGB(140 + math.random(0, 30), 78 + math.random(0, 14), 62 + math.random(0, 10))
		chip.Material = Enum.Material.Brick
		chip.CanCollide = true
		chip.CanTouch = false
		chip.CanQuery = false
		chip.CastShadow = false
		chip.CFrame = CFrame.new(at + out * 0.35 + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.8)
			* CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chip.AssemblyLinearVelocity = out * (5 + math.random() * 6) * power
			+ Vector3.new((math.random() - 0.5) * 6, 2 + math.random() * 4, (math.random() - 0.5) * 6)
		chip.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 30
		chip.Parent = workspace
		game:GetService("Debris"):AddItem(chip, 3)
	end
end

-- THE BAR SWUNG INTO BRICKS (the hundred-and-twenty-ninth pass, from your test: "when I break the bricks with the
-- crowbar, I should actually hit the bricks and there should be some pieces flying out"): you step up to the wall,
-- and three blows go into it (Poses.strike), the bar drawn each frame from your hand, back over your shoulder as you
-- draw it and onto the bricks as it lands, chips and dust flying out of each, the wall shaking; on the last the patch
-- bursts out (the server lets the bricks go then, PRY_SECONDS in, as it does for the bar's other work).
local BAR_LONG = 3.2
local STRIKE_STAND = 4.2 -- studs out from the wall you strike it from: the bar's tip just reaches it
local function strikeBricks(data: { [string]: any })
	local at, out = data.at :: Vector3, data.out :: Vector3
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hand = character and (character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm"))
	if not (root and root:IsA("BasePart") and hand and hand:IsA("BasePart")) then
		return
	end
	local flatOut = Vector3.new(out.X, 0, out.Z)
	flatOut = if flatOut.Magnitude > 0.05 then flatOut.Unit else Vector3.zAxis
	busy = true
	scene.prying = true
	scene.token += 1
	twoShotSide = nil
	local token = scene.token
	local from = root.CFrame
	local stand = Vector3.new(at.X, root.Position.Y, at.Z) + flatOut * STRIKE_STAND
	local goal = CFrame.lookAt(stand, stand - flatOut)
	Cinema.begin({ hush = false })
	-- The bar off your back and in your hand, held as a blow holds it: drawn by this scene each frame, not welded.
	barInHands(true)
	local bar = barHeld.hand
	if bar then
		local weld = bar:FindFirstChildOfClass("WeldConstraint")
		if weld then
			weld:Destroy()
		end
		bar.Anchored = true
		bar.Size = Vector3.new(0.2, 0.2, BAR_LONG)
	end
	act("strike")
	Cinema.think(character, tostring(data.think or "Let's see what's in here."), 2.2)
	local began = os.clock()
	local blows = table.clone(Poses.STRIKES)
	local hook
	hook = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		if scene.token ~= token or not scene.prying then
			hook:Disconnect()
			return
		end
		-- Up to the wall, in the first moment.
		if t < 0.3 and root.Parent then
			local u = math.clamp(t / 0.3, 0, 1)
			root.CFrame = from:Lerp(goal, u * u * (3 - 2 * u))
		end
		-- The bar from your hand: up and back over your shoulder as you draw it, onto the bricks as the blow lands.
		if bar and bar.Parent and hand.Parent and acting.now and acting.now.pose == "strike" then
			local grip = hand.Position
			local drawn = (Vector3.yAxis * 0.75 + flatOut * 0.65).Unit
			local onto = at - grip
			onto = if onto.Magnitude > 0.05 then onto.Unit else -flatOut
			local back = Poses.strikeBack(t)
			local dir = onto:Lerp(drawn, back)
			dir = if dir.Magnitude > 0.05 then dir.Unit else onto
			bar.CFrame = CFrame.lookAt(grip, grip + dir) * CFrame.new(0, 0, -(BAR_LONG / 2 - 0.25))
		end
		-- EACH BLOW LANDS: the wall shakes, chips and dust fly out of it, and the bar's knock, a little lower each time.
		while blows[1] and t >= blows[1] do
			table.remove(blows, 1)
			Cinema.shake(0.5)
			Cinema.impact(0.3)
			Cinema.sound("BarStrike", 0.7, { pitch = 0.92 + 0.04 * #blows, keep = true })
			chips(at, flatOut, 6, 1)
			dust(at)
		end
		local shot = twoShot(at, math.clamp(t / PRY_SECONDS, 0, 1))
		if shot then
			Cinema.point(shot, 50 - 4 * math.clamp(t / PRY_SECONDS, 0, 1))
		end
		if t >= PRY_SECONDS and acting.now and acting.now.pose == "strike" then
			-- IT GIVES: the patch bursts out in a spray of chips and dust.
			Cinema.impact(0.9)
			Cinema.shake(0.9)
			Cinema.sound("BrickBurst", 0.75, { keep = true })
			chips(at, flatOut, 16, 1.5)
			dust(at)
			act("startle")
			barInHands(false)
			task.delay(0.6, function()
				if scene.token == token and acting.now and acting.now.pose == "startle" then
					act("ponder")
				end
			end)
		end
		if t > PRY_SECONDS + 4 then
			hook:Disconnect()
			if scene.token == token and scene.prying then
				endScene()
			end
		end
	end)
end

-- THE BAR AS A LEVER (the two-hundred-and-seventh pass, from your note of 2026-11-10: "improve the animation drastically
-- for the level 2 chest that should be prised up with a bar"). The tin box was opened as a locker is: standing, three
-- tugs at the air in front of it, the lid still, and then it flew open. Now you get down to it: set in front of the
-- box on the floor it stands on and held there (it is under water, and you drifted up off it), down on your haunches
-- (Poses.lever), the bar's claw kept under the lid's front edge wherever the lid is and its handle in your hands, and
-- your weight borne down on it three times (Poses.LEVER's clock, which the server lifts the lid by, so the lid comes up
-- under the claw as you heave): silt out of the seam and the bar's knock on each, the picture shaking harder through
-- the long last one. Seen side on and low, the lid and your hands in the middle of the picture, closing in as it builds;
-- then it gives: the knock of the clasp, an impact frame, and you thrown back off it as the lid goes over.
-- (`stand` and `bar` are the two numbers Poses.lever's arms were fitted to: change them and the hands leave the bar.
-- `eye` is how far to the side the camera stands, where there is room: far enough that you and the box are both whole.)
local LEVER = { stand = 3.75, claw = 0.22, eye = 7.4, bar = 2.8 }
local function leverBox(data: { [string]: any })
	local at, out = data.at :: Vector3, data.out :: Vector3
	local lid = data.lid
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (character and root and root:IsA("BasePart") and humanoid) then
		return
	end
	local flatOut = Vector3.new(out.X, 0, out.Z)
	flatOut = if flatOut.Magnitude > 0.05 then flatOut.Unit else Vector3.zAxis
	local right = (-flatOut):Cross(Vector3.yAxis)
	local timing = Poses.LEVER
	busy = true
	scene.prying = true
	scene.token += 1
	twoShotSide = nil
	local token = scene.token
	local half = if typeof(data.half) == "number" then data.half else 0.6
	local legs = if humanoid.RigType == Enum.HumanoidRigType.R6 then 2 else humanoid.HipHeight
	local stand = Vector3.new(at.X, at.Y - half + legs + root.Size.Y / 2, at.Z) + flatOut * LEVER.stand
	local goal = CFrame.lookAt(stand, stand - flatOut)
	local from = root.CFrame
	root.AssemblyLinearVelocity = Vector3.zero
	root.Anchored = true
	scene.held = root
	Cinema.begin({ hush = false })
	-- The bar off your back and in your hands: drawn by this scene each frame, from the lid's edge to your grip.
	barInHands(true)
	local bar = barHeld.hand
	if bar then
		local weld = bar:FindFirstChildOfClass("WeldConstraint")
		if weld then
			weld:Destroy()
		end
		bar.Anchored = true
		bar.Size = Vector3.new(0.2, 0.2, LEVER.bar)
	end
	-- WHICH SIDE TO WATCH FROM: the one with more room at the box's own height, measured here and kept. (twoShot would
	-- have measured from where you were when you pressed the key: afloat over the pool, with room on every side, and
	-- then the wall beside the box pulled the camera in until neither you nor the box was whole.)
	-- (Aimed a stud higher and a little nearer you than the lid, the two-hundred-and-thirty-fifth pass: at the lid's own
	-- height your head was above the top of the picture, seen in play on 2026-11-21.)
	local chest = Vector3.new(at.X, at.Y + half + 1.5, at.Z) + flatOut * 1.9
	local function room(side: number): number
		return (Cinema.clear(chest + right * side * LEVER.eye + flatOut * 1.2 + Vector3.new(0, 0.9, 0), chest, { character }) - chest).Magnitude
	end
	local rightRoom, leftRoom = room(1), room(-1)
	local side = if math.max(rightRoom, leftRoom) < 3.2 then 0 elseif leftRoom > rightRoom + 0.5 then -1 else 1
	act("lever")
	Cinema.think(character, tostring(data.think or "Let's see what's in here."), 2.8)
	local rightHand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local leftHand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	local seamRest = at + Vector3.new(0, half, 0) + flatOut * 0.78
	local began = os.clock()
	local heaves = table.clone(timing.heaves)
	local gave = false
	local hook
	hook = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		if scene.token ~= token or not scene.prying then
			hook:Disconnect()
			return
		end
		-- Down to it, in the first moment, and kept there.
		if root.Parent then
			local u = math.clamp(t / 0.45, 0, 1)
			root.CFrame = from:Lerp(goal, u * u * (3 - 2 * u))
		end
		-- WHERE THE CLAW BITES: under the front edge of the lid, wherever the lid is now (the server lifts it).
		local seam = seamRest
		if not gave and typeof(lid) == "Instance" and lid:IsA("BasePart") and lid.Parent then
			seam = lid.CFrame * Vector3.new(0, -lid.Size.Y / 2, -lid.Size.Z / 2)
		end
		local pull = Poses.leverPull(t)
		-- THE BAR, from the claw to your grip: square to the box, never flatter than its rim lets it lie nor steeper than a
		-- bar could be worked. (With no hands to find, it drops as you bear on it.)
		if bar and bar.Parent and not gave then
			local rise = 0.9 - 0.55 * pull
			local tip = seam - flatOut * LEVER.claw
			local grip: Vector3? = nil
			if rightHand and rightHand:IsA("BasePart") and leftHand and leftHand:IsA("BasePart") then
				grip = (rightHand.Position + leftHand.Position) / 2
			elseif rightHand and rightHand:IsA("BasePart") then
				grip = rightHand.Position
			end
			if grip then
				local toGrip = grip - tip
				rise = math.clamp(math.atan2(toGrip.Y, math.max(0.3, toGrip:Dot(flatOut))), 0.12, 1.25)
			end
			local along = flatOut * math.cos(rise) + Vector3.yAxis * math.sin(rise)
			bar.CFrame = CFrame.lookAt(tip, tip + along) * CFrame.new(0, 0, -LEVER.bar / 2)
		end
		-- EACH HEAVE: the bar's knock, lower and harder each time, silt out of the seam, and the picture jolted.
		while heaves[1] and t >= heaves[1] do
			local index = #timing.heaves - #heaves + 1
			table.remove(heaves, 1)
			Cinema.shake(0.25 + 0.12 * index)
			Cinema.sound("BarStrike", 0.35 + 0.1 * index, { pitch = 0.62 + 0.05 * index, keep = true })
			dust(seam)
		end
		-- THE LAST ONE HELD: the picture shaking harder the longer it is.
		local last = timing.heaves[#timing.heaves]
		if t > last + 0.35 and not gave then
			Cinema.shake(0.15 + 0.45 * math.clamp((t - last - 0.35) / math.max(0.05, timing.gives - last - 0.35), 0, 1))
		end
		-- THE SHOT: side on and a little over the box, you and it both whole in the picture with the bar between,
		-- closing in as the heaves build; from above only if neither side has room.
		local build = math.clamp(t / timing.gives, 0, 1)
		local mid = if gave then at + Vector3.new(0, half + 0.7, 0) + flatOut * 0.9 else chest
		local eye
		if side == 0 then
			eye = Cinema.clear(mid + flatOut * 3.5 + Vector3.new(0, 6, 0), mid, { character })
		else
			eye = Cinema.clear(mid + right * side * (LEVER.eye - 1.3 * build) + flatOut * 1.2
				+ Vector3.new(0, 0.9 + 0.4 * build, 0), mid, { character })
		end
		Cinema.point(CFrame.lookAt(eye, mid), 56 - 5 * build)
		if t >= timing.gives and not gave then
			-- IT GIVES: the clasp's knock, the jolt, and you thrown back off it as the lid goes over.
			gave = true
			Cinema.impact(0.9)
			Cinema.shake(0.8)
			Cinema.sound("ClockPunch", 0.8, { pitch = 0.78, keep = true })
			dust(seam)
			act("startle")
			barInHands(false)
			task.delay(0.6, function()
				if scene.token == token and acting.now and acting.now.pose == "startle" then
					act("ponder")
				end
			end)
		end
		-- Nothing came of it: the scene ends by itself.
		if t > timing.gives + 4 then
			hook:Disconnect()
			if scene.token == token and scene.prying then
				endScene()
			end
		end
	end)
end

-- THE BAR AT WORK (Interactables' "pry"): you turn to it, set the bar, three hard tugs with the dust coming out, and
-- on the last it gives (the server opens it then): an impact frame and a jump back. Then the scene of what was in it
-- (moment, or peek for the board) takes over; with nothing in it (an empty locker) it ends by itself.
local function pry(data: { [string]: any })
	local at = data.at
	if busy or not Cinema or typeof(at) ~= "Vector3" then
		return
	end
	if data.strike == true and typeof(data.out) == "Vector3" and Poses and Poses.STRIKES then
		strikeBricks(data)
		return
	end
	if data.lever == true and typeof(data.out) == "Vector3" and Poses and Poses.LEVER and Poses.lever then
		leverBox(data)
		return
	end
	busy = true
	scene.prying = true
	scene.token += 1
	twoShotSide = nil
	local token = scene.token
	local character = Players.LocalPlayer.Character
	faceToward(at)
	Cinema.begin({ hush = false })
	barInHands(true)
	act("pry")
	Cinema.think(character, tostring(data.think or "Let's see what's in here."), 2.6)
	local began = os.clock()
	local tugs = { 0.4, 0.95, 1.5 }
	local hook
	hook = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		if scene.token ~= token or not scene.prying then
			hook:Disconnect()
			return
		end
		while tugs[1] and t >= tugs[1] do
			table.remove(tugs, 1)
			Cinema.shake(0.35)
			dust(at)
		end
		local shot = twoShot(at, math.clamp(t / PRY_SECONDS, 0, 1))
		if shot then
			Cinema.point(shot, 50 - 4 * math.clamp(t / PRY_SECONDS, 0, 1))
		end
		if t >= PRY_SECONDS and acting.now and acting.now.pose == "pry" then
			-- IT GIVES.
			Cinema.impact(0.9)
			act("startle")
			barInHands(false)
			task.delay(0.6, function()
				if scene.token == token and acting.now and acting.now.pose == "startle" then
					act("ponder")
				end
			end)
		end
		-- Nothing came of it (an empty locker): the scene ends by itself.
		if t > PRY_SECONDS + 4 then
			hook:Disconnect()
			if scene.token == token and scene.prying then
				endScene()
			end
		end
	end)
end

-- A SECRET FOUND: you, side on, working out what you have found (hand at your chin, what you make of it over your
-- head); then close in on it, INSIDE the thing (the coat in the locker, the letter in the box), its name and a sting;
-- then the card. Takes over from the bar's scene. It used to drift for five and a half seconds along a curve that ended
-- against the outside of whatever it was. LOOKED AT AGAIN (`again`), it is only the close look, three seconds, with
-- its name: no sting, no card, no scene over again.
local MOMENT = { ponder = 2.4, close = 4.2 } -- seconds: you working it out; then close in on it
local function moment(data: { [string]: any })
	local takingOver = scene.prying
	if (busy and not takingOver) or not Cinema then
		if data.again ~= true then
			card(tostring(data.title), tonumber(data.found) or 1, tonumber(data.total) or 5)
		end
		return
	end
	local eye, focus = data.eye, data.focus
	if typeof(eye) ~= "CFrame" or typeof(focus) ~= "Vector3" then
		if takingOver then
			endScene()
		end
		return
	end
	local again = data.again == true
	busy = true
	scene.prying = false
	scene.token += 1
	twoShotSide = nil
	local token = scene.token
	local character = Players.LocalPlayer.Character
	Cinema.begin({ hush = false })
	if not again then
		sound("SecretSting", nil, 0.7, 1)
	end
	faceToward(focus)
	if not again and not (acting.now and acting.now.pose == "ponder") then
		act("ponder")
	end
	-- Close in on it from the side it opens to (the way the server's eye for it looks in from), never from behind it.
	local out = Vector3.new(eye.Position.X - focus.X, 0, eye.Position.Z - focus.Z)
	out = if out.Magnitude > 0.1 then out.Unit else Vector3.zAxis
	local reach = math.clamp((eye.Position - focus).Magnitude * 0.5, 1.9, 3.4)
	-- A THING WITH A SIZE TO IT (a locker's inside) is framed whole: stood back far enough for all of it and coming in a
	-- little (the hundred-and-twenty-fourth pass, from your test: "the animation inside looks weird": it closed in till
	-- the coat filled the picture, a dark cloth with a gold line down it).
	local span = if typeof(data.span) == "number" then data.span else nil
	-- A THING IN A WALL (the bricks' hole: the hundred-and-thirtieth pass, from your test, "fix the camera"): looked into
	-- from above, `rise` studs over it; at its own height the camera was down on the sill, and the bricks were all it saw.
	local rise = if typeof(data.rise) == "number" then data.rise else nil
	local ponder = if again then 0 else MOMENT.ponder
	local closing = if again then 3 else MOMENT.close
	local began = os.clock()
	local said, captioned = false, false
	local hook
	hook = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		if scene.token ~= token then
			hook:Disconnect()
			return
		end
		if t < ponder then
			-- YOU, working it out: side on, a little closer as you lean in.
			if not said and t > 0.3 and typeof(data.think) == "string" then
				said = true
				Cinema.think(character, data.think, 3.4)
			end
			local shot = twoShot(focus, 0.5 * math.clamp(t / ponder, 0, 1))
			if shot then
				Cinema.point(shot, 48)
			end
		else
			-- WHAT IT IS: close in on it, from in front of it and a little above, easing in; sharp on it, its name.
			if not captioned then
				captioned = true
				Cinema.cut()
				Cinema.caption(tostring(data.title), tostring(data.line), if again then 3 else 5)
				-- And you out of its way, if you are standing in front of it.
				Cinema.stepAside(focus + out * ((span or reach) + 1.4), focus, 2.4)
			end
			local u = math.clamp((t - ponder) / MOMENT.close, 0, 1)
			u = u * u * (3 - 2 * u)
			local back = if span then span + 1.4 - 1.2 * u else reach - 0.7 * u
			local want = focus + out * back + Vector3.new(0, 0.45 - 0.15 * u, 0)
			if rise then
				want = focus + out * (back + 0.4) + Vector3.new(0, rise * (1 - 0.25 * u) + 0.3, 0)
			end
			local at = Cinema.clear(want, focus, { character })
			Cinema.point(CFrame.lookAt(at, focus - Vector3.new(0, 0.1, 0)), 52 - 6 * u)
			Cinema.focus((focus - at).Magnitude, 0.55)
		end
		if t > ponder + closing then
			hook:Disconnect()
			endScene()
			if not again then
				card(tostring(data.title), tonumber(data.found) or 1, tonumber(data.total) or 5)
			end
		end
	end)
end

-- UNDER THE BOARDS: you leaning over the gap; then straight down into the shaft, where far below the mouth opens a
-- little and breathes (and you jolt at it); then back to you, backing off, what you make of it over your head.
local function peek(data: { [string]: any })
	local hole = data.eye
	local takingOver = scene.prying
	if (busy and not takingOver) or not Cinema or typeof(hole) ~= "CFrame" then
		if takingOver then
			endScene()
		end
		return
	end
	busy = true
	scene.prying = false
	scene.token += 1
	twoShotSide = nil
	local token = scene.token
	local character = Players.LocalPlayer.Character
	Cinema.begin({ hush = false })
	faceToward(hole.Position)
	act("peer")
	local over = hole.Position + Vector3.new(0, 1.5, 0)
	local mouth = if Maw then Maw.build(Maw.facing(over - Vector3.new(0, 240, 0), Vector3.yAxis, Vector3.xAxis), workspace) else nil
	if mouth then
		Maw.set(mouth, 0.06, 0.05)
		Maw.light(mouth, 0)
	end
	sound("MawRumble", "rbxasset://sounds/bass.mp3", 0.5, 0.2)
	local began = os.clock()
	local captioned, jolted, back = false, false, false
	local hook
	hook = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		if scene.token ~= token then
			hook:Disconnect()
			if Maw and mouth then
				Maw.destroy(mouth)
			end
			return
		end
		local breath = math.clamp(math.sin(math.clamp((t - 1.8) / 5, 0, 1) * math.pi), 0, 1)
		if mouth then
			Maw.set(mouth, 0.06 + 0.3 * breath, 0.05 + 0.25 * breath)
			Maw.light(mouth, 0.45 * breath)
		end
		if t < 1.8 then
			-- YOU, leaning over the gap to look.
			local shot = twoShot(hole.Position, 0.35)
			if shot then
				Cinema.point(shot, 48)
			end
		elseif t < 7.6 then
			if not captioned then
				captioned = true
				Cinema.cut()
				Cinema.caption(tostring(data.title), tostring(data.line), 6)
			end
			-- AT ITS WIDEST, it gets you: a jolt.
			if not jolted and breath > 0.9 then
				jolted = true
				Cinema.impact(0.7)
			end
			-- Straight down: told which way is up on the screen, since looking along the world's up has no answer.
			Cinema.point(CFrame.lookAt(over + Vector3.new(0, -2, 0), over - Vector3.new(0, 100, 0), Vector3.zAxis),
				40 - 6 * math.min(1, (t - 1.8) / 6))
		else
			-- BACK UP, backing off it: what you make of it.
			if not back then
				back = true
				Cinema.cut()
				act("startle")
				Cinema.think(character, tostring(data.think or "Is that... breathing?"), 2.4)
			end
			local shot = twoShot(hole.Position, 0)
			if shot then
				Cinema.point(shot, 50)
			end
		end
		if t > 10 then
			hook:Disconnect()
			if Maw and mouth then
				Maw.destroy(mouth)
			end
			endScene()
			card(tostring(data.title), tonumber(data.found) or 1, tonumber(data.total) or 5)
		end
	end)
end

-- ===== WHAT WALKS IN THE BACK ROOMS =====
--
-- ===== THE BACK ROOMS ON THIS SCREEN (the hundred-and-third pass) =====
--
-- THEIR OWN LIGHT while you are down there: a little yellow, a little flat, the air thick with it (the room's haze),
-- given back as you leave. THE DOOR YOU CAME IN BY, lit for you alone if you came down the lobby's corridor (the
-- server takes you back through it); a frame round bare wall if you fell in. THE DREAD as he comes: the door banging
-- open, the lights going out from it toward you and coming back, then your heart, louder and faster and the picture
-- draining of colour the nearer he is. And THE SCREAMER: the lights gone, then him, an arm's length away, and his
-- blank face splitting open down its seam into the Hold's mouth.
local Lighting = game:GetService("Lighting")
local backRooms = { grade = nil :: ColorCorrectionEffect?, haze = nil :: { [string]: any }?, dread = nil :: RBXScriptConnection?,
	heart = nil :: Sound?, dreadFx = nil :: ColorCorrectionEffect? }

local function backRoomsFolder(): Instance?
	return workspace:FindFirstChild("BackRooms")
end

local function tubes(): { SurfaceLight }
	local out = {}
	local folder = backRoomsFolder()
	for _, item in ipairs(if folder then folder:GetDescendants() else {}) do
		if item:IsA("SurfaceLight") and item.Parent and item.Parent.Name == "TubePanel" then
			table.insert(out, item)
		end
	end
	return out
end

local function lightTheDoor()
	local folder = backRoomsFolder()
	local doorway = folder and folder:FindFirstChild("ReturnDoorway")
	if not (doorway and doorway:IsA("BasePart")) then
		return
	end
	local open = Players.LocalPlayer:GetAttribute("BackRoomsFrom") == "lobby"
	doorway.Color = if open then Color3.fromRGB(255, 226, 140) else Color3.fromRGB(206, 186, 96)
	doorway.Material = if open then Enum.Material.SmoothPlastic else Enum.Material.Plaster
	local spill = doorway:FindFirstChild("Spill")
	if spill and spill:IsA("SurfaceLight") then
		spill.Enabled = open
	end
end

local function backRoomsLight(on: boolean)
	if on then
		if not backRooms.grade then
			local grade = Instance.new("ColorCorrectionEffect")
			grade.Name = "BackRoomsGrade"
			grade.TintColor = Color3.fromRGB(255, 244, 210)
			grade.Saturation = -0.14
			grade.Contrast = 0.1
			grade.Parent = Lighting
			backRooms.grade = grade
		end
		local air = Lighting:FindFirstChildOfClass("Atmosphere")
		if air and not backRooms.haze then
			backRooms.haze = { Density = air.Density, Offset = air.Offset, Color = air.Color, Decay = air.Decay, Haze = air.Haze,
				Glare = air.Glare }
			air.Density, air.Offset, air.Glare, air.Haze = 0.42, 0, 0, 1.4
			air.Color, air.Decay = Color3.fromRGB(226, 212, 156), Color3.fromRGB(150, 130, 76)
		end
		lightTheDoor()
	else
		if backRooms.grade then
			backRooms.grade:Destroy()
			backRooms.grade = nil
		end
		local air = Lighting:FindFirstChildOfClass("Atmosphere")
		local was = backRooms.haze
		if air and was then
			for key, value in pairs(was) do
				(air :: any)[key] = value
			end
		end
		backRooms.haze = nil
	end
end

local function stopDread()
	if backRooms.dread then
		backRooms.dread:Disconnect()
		backRooms.dread = nil
	end
	if backRooms.heart then
		backRooms.heart:Destroy()
		backRooms.heart = nil
	end
	if backRooms.dreadFx then
		backRooms.dreadFx:Destroy()
		backRooms.dreadFx = nil
	end
end

-- The lights out from `from` toward you, one after another, and back on in the same order.
local function lightsWave(from: Vector3)
	local list = tubes()
	table.sort(list, function(a, b)
		local pa, pb = a.Parent :: BasePart, b.Parent :: BasePart
		return (pa.Position - from).Magnitude < (pb.Position - from).Magnitude
	end)
	for index, light in ipairs(list) do
		if index > 24 then
			break
		end
		task.delay(index * 0.04, function()
			local was = light.Brightness
			light.Brightness = was * 0.08
			task.delay(0.9, function()
				light.Brightness = was
			end)
		end)
	end
end

-- STALKED: the staff door bangs open where he is (heard from there), the lights go out from it toward you and come
-- back, you wonder aloud; and from then until he is gone, your heart and the colour draining the nearer he is.
local function stalked(data: { [string]: any }?)
	local door = if data and typeof(data.door) == "Vector3" then data.door else nil
	local folder = SoundService:FindFirstChild("StorySounds")
	local slam = folder and folder:FindFirstChild("DoorSlam")
	if door and slam and slam:IsA("Sound") then
		local spot = Instance.new("Attachment")
		spot.WorldPosition = door
		spot.Parent = workspace.Terrain
		local s = slam:Clone()
		s.Volume = 1
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = 10
		s.RollOffMaxDistance = 140
		s.Parent = spot
		s:Play()
		game:GetService("Debris"):AddItem(spot, 3)
	end
	if door then
		lightsWave(door)
	end
	task.delay(0.8, function()
		if Cinema then
			Cinema.think(Players.LocalPlayer.Character, "...is someone there?", 2.4)
		end
	end)
	sound("MawGrowl", "rbxasset://sounds/bass.mp3", 0.45, 0.7)
	stopDread()
	local beat = folder and folder:FindFirstChild("Heartbeat")
	if beat and beat:IsA("Sound") then
		local heart = beat:Clone()
		heart.Looped = true
		heart.Volume = 0
		heart.Parent = SoundService
		heart:Play()
		backRooms.heart = heart
	end
	local fx = Instance.new("ColorCorrectionEffect")
	fx.Name = "Dread"
	fx.Parent = Lighting
	backRooms.dreadFx = fx
	backRooms.dread = RunService.RenderStepped:Connect(function()
		local rooms = backRoomsFolder()
		local him = rooms and rooms:FindFirstChild("Marsh")
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (him and him:IsA("Model") and root and root:IsA("BasePart"))
			or Players.LocalPlayer:GetAttribute("InLevel") ~= "backRooms" then
			stopDread()
			return
		end
		local gap = (him:GetPivot().Position - root.Position).Magnitude
		local near = math.clamp(1 - (gap - 4) / 36, 0, 1)
		local heart = backRooms.heart
		if heart then
			heart.Volume = 0.12 + 0.75 * near
			heart.PlaybackSpeed = 0.85 + 0.6 * near
		end
		fx.Saturation = -0.5 * near
		fx.Contrast = 0.28 * near
		fx.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 226, 220), near)
	end)
end

-- HIS FACE, OPENING: built on this screen only (under the camera), two halves of the pale head hinged at the back,
-- which swing apart down the seam onto rows of long teeth and a dark red throat with a light in it. Bigger since the
-- hundred-and-twenty-fifth pass (by SCREAM), its teeth fangs a hand long, and a pale light on its skin: from your test,
-- "the animation of the backrooms monster kill is weird", it was two flat red slabs filling the picture, too near
-- and too small to be a face.
local SCREAM = 1.6
-- A fang carries its base length and which way it points (+1 up, -1 down): it grows out of the gum as the mouth opens.
type Piece = { part: BasePart, offset: CFrame, len: number?, dir: number?, eyelid: number? }
-- A strand of spit from under the lid to the jaw, stretching as it opens and snapping at `snap` (how far open).
type Strand = { top: BasePart, bottom: BasePart, from: CFrame, to: CFrame, snap: number, broken: boolean? }
type Screamer = { model: Model, left: { Piece }, right: { Piece }, gullet: PointLight,
	lid: { Piece }?, jaw: { Piece }?, hinge: CFrame?, jawHinge: CFrame?, strands: { Strand }?,
	lidTurn: number?, jawTurn: number?, throatAt: CFrame?, own: boolean?, scale: Vector3?, eyeOpen: number? }

-- HIS MADE HEAD (the two-hundred-and-twenty-first pass, from your note: "it still has the old head-opening animation even
-- though there is a new head model"). BackRoomsService has worn Assets/Props.Marsh_Head over the plain head since the
-- two-hundred-and-eleventh pass, but the screamer still built the old head (two pale halves on a seam) and opened that
-- in front of him, while his new head stayed on behind it. Now, where the made head is there, it is the head that
-- opens: the whole of it hinges up and back from the top of the skull like a lid, fangs hanging from under it, onto a
-- red jaw with a row of fangs and the throat's light where his face was. The halves stay for a place without the model.
local function madeHeadTemplate(): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local props = assets and assets:FindFirstChild("Props")
	local made = props and props:FindFirstChild("Marsh_Head")
	if not made then
		return nil
	end
	local part = if made:IsA("BasePart") then made else made:FindFirstChildWhichIsA("BasePart", true)
	return part
end
-- His made head's height on him (BackRoomsService: 1.35 of the plain head's 1.45), a little bigger here so it reads.
local MADE_HEIGHT = 1.45 * 1.35 * 1.15
local function screamerFace(): Screamer
	local model = Instance.new("Model")
	model.Name = "Screamer"
	local skin, flesh, bone = Color3.fromRGB(214, 208, 200), Color3.fromRGB(70, 12, 16), Color3.fromRGB(232, 226, 206)
	local function piece(name: string, size: Vector3, colour: Color3, material: Enum.Material?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = size
		p.Color = colour
		p.Material = material or Enum.Material.SmoothPlastic
		p.Parent = model
		return p
	end
	-- Fangs a little darker than bone, so the light in the throat does not blow them out to white.
	local fang = Color3.fromRGB(196, 184, 160)
	local template = madeHeadTemplate()
	local lid: { Piece }?, jaw: { Piece }?, hinge: CFrame? = nil, nil, nil
	local jawHinge: CFrame?, strands: { Strand }? = nil, nil
	local lidTurn, jawTurn, throatAt, own = math.rad(40), math.rad(22), nil, false
	local screamerScale: Vector3? = nil
	local mouth = if template and MarshMouth then MarshMouth.pieces() else nil
	if template and mouth then
		-- HIS OWN MOUTH (the two-hundred-and-twenty-seventh pass, from your question: "do you think having his mouth
		-- actually open instead of just having another fake one underneath would be better?"). His head cut at his lips
		-- (MarshMouth): his skull tips back a little on the hinge under his ears and his own jaw drops wide, his chin and
		-- his lower lip going with it, onto a dark palate and the floor of his mouth, a tongue, and teeth rooted on both
		-- his lips. One head, opening; no lid, nothing underneath.
		own = true
		local scale = template.Size * (MADE_HEIGHT / template.Size.Y) / mouth.meshSize
		local function cloned(part: MeshPart): BasePart
			local copy = part:Clone()
			copy.Anchored = true
			copy.Size = part.Size * scale
			copy.Parent = model
			return copy
		end
		lid = { { part = cloned(mouth.skull), offset = CFrame.identity } }
		if mouth.palate then
			table.insert(lid, { part = cloned(mouth.palate), offset = CFrame.identity })
		end
		-- HIS EYES (the two-hundred-and-twenty-eighth pass): his lids, cut from his skull, and what is behind them.
		for i, lidPart in ipairs(mouth.lids) do
			table.insert(lid, { part = cloned(lidPart), offset = CFrame.identity, eyelid = i })
		end
		for _, eyePart in ipairs(MarshMouth.eyeParts(scale)) do
			eyePart.part.Anchored = true
			eyePart.part.Parent = model
			table.insert(lid, { part = eyePart.part, offset = eyePart.offset })
		end
		jaw = { { part = cloned(mouth.jaw), offset = CFrame.identity } }
		if mouth.floor then
			table.insert(jaw, { part = cloned(mouth.floor), offset = CFrame.identity })
		end
		hinge = CFrame.new(MarshMouth.HINGE * scale)
		jawHinge = hinge
		lidTurn, jawTurn = math.rad(13), math.rad(38)
		-- A tongue lying in his jaw, thick and wet.
		local tongue = piece("Tongue", Vector3.new(0.62, 0.15, 0.85) * scale.Y, Color3.fromRGB(110, 30, 38))
		tongue.Reflectance = 0.08
		local tongueMesh = Instance.new("SpecialMesh")
		tongueMesh.MeshType = Enum.MeshType.Sphere
		tongueMesh.Parent = tongue
		table.insert(jaw, { part = tongue, offset = CFrame.new((mouth.middle + MarshMouth.NORMAL * 0.04
			+ Vector3.new(0, 0, -0.1)) * scale) * CFrame.Angles(-math.atan(MarshMouth.SLOPE), 0, 0) })
		-- His teeth, on his lips: growing out of the gums as he opens.
		for _, tooth in ipairs(MarshMouth.teeth()) do
			local long = tooth.len * scale.Y
			local part = piece("Fang", Vector3.new(0.05 * scale.Y, long, 0.05 * scale.Y), fang)
			local spindle = Instance.new("SpecialMesh")
			spindle.MeshType = Enum.MeshType.Sphere
			spindle.Parent = part
			table.insert(if tooth.upper then lid else jaw, { part = part, offset = MarshMouth.toothFrame(tooth, scale),
				len = long, dir = 1 })
		end
		-- Spit between his lips, snapping as he opens.
		strands = {}
		local spit = Color3.fromRGB(112, 38, 42)
		for i, x in ipairs({ -0.28, -0.12, 0.03, 0.15, 0.3 }) do
			local lip = MarshMouth.lipAt(x)
			if lip then
				-- Thin and round, tapering at the ends (filmed square and thick, they were red bars across his mouth).
				local function thread(): BasePart
					local p = piece("Spit", Vector3.new(0.03, 0.03, 0.1) * (MADE_HEIGHT / 2.2), spit)
					p.Reflectance = 0.18
					p.Transparency = 1
					local round = Instance.new("SpecialMesh")
					round.MeshType = Enum.MeshType.Sphere
					round.Parent = p
					return p
				end
				local at = CFrame.new((lip + Vector3.new(0, 0, 0.05)) * scale)
				table.insert(strands, { top = thread(), bottom = thread(), from = at, to = at,
					snap = ({ 1.04, 1.14, 1.22, 1.08, 1.18 })[i] })
			end
		end
		throatAt = CFrame.new((mouth.middle + Vector3.new(0, -0.04, 0.32)) * scale)
		screamerScale = scale
	end
	if template and not own then
		-- THE LID: his made head itself, its face (-Z, or FrontYaw) toward you.
		local head = template:Clone()
		head.Name = "Lid"
		head.Anchored = true
		head.CanCollide, head.CanQuery, head.CanTouch = false, false, false
		head.CastShadow = false
		head.Size = template.Size * (MADE_HEIGHT / template.Size.Y)
		head.Parent = model
		local yaw = template:GetAttribute("FrontYaw")
		local turn = CFrame.Angles(0, if typeof(yaw) == "number" then yaw else 0, 0)
		local hs = head.Size
		local hh, hd, hw = hs.Y, hs.Z, hs.X
		-- Hinged at the top of the back of the skull, so it tips up and back off his face.
		-- (Pass 222's play test: hinged at the top and tipped 58 degrees he looked up at the sky over a gap. Hinged at
		-- the ears now, and tipped less, it is a mouth.)
		hinge = CFrame.new(0, hh * 0.1, hd * 0.32)
		lid = { { part = head, offset = turn } }
		-- Fangs under the lid's front edge, pointing down: they come up with it, and grow out of the gum as it opens.
		-- The third and seventh are the long ones, a pair of real fangs among the rest.
		local scale = MADE_HEIGHT / 2.2
		-- On the underside of his head, at the chin (pass 222's play test: rooted near its middle they were inside it,
		-- and never seen).
		local lidRoot = -hh * 0.4
		for k = 1, 9 do
			local x = (k - 5) * hw * 0.085
			local len = 0.5 * scale * (if k == 3 or k == 7 then 1.4 else 1 - 0.25 * math.abs(k - 5) / 4)
			local tooth = piece("Fang", Vector3.new(0.07 * scale, len, 0.07 * scale), fang)
			local spindle = Instance.new("SpecialMesh")
			spindle.MeshType = Enum.MeshType.Sphere
			spindle.Parent = tooth
			local z = -hd * (0.3 - 0.06 * math.abs(k - 5) / 4)
			-- Each leaning its own way, raked toward you, not a row of pegs.
			local lean = ({ 0.1, -0.15, 0.05, 0.2, -0.05, 0.15, -0.1, 0.08, -0.2 })[k]
			table.insert(lid, { part = tooth, offset = CFrame.new(x, lidRoot, z) * CFrame.Angles(-0.3, 0, lean + (k - 5) * 0.06),
				len = len, dir = -1 })
		end
		-- THE JAW left behind where his face was: the red of the mouth, and a row of fangs standing up out of it. It
		-- drops a little on its own hinge, low at the back, as the lid goes up: a mouth opening both ways.
		jaw = {}
		jawHinge = CFrame.new(0, -hh * 0.32, hd * 0.3)
		-- A deep, dark mouth, sunk into where his face was (not a ball standing out of it).
		local mouth = piece("Mouth", Vector3.new(hw * 0.7, hh * 0.38, hd * 0.6), Color3.fromRGB(42, 6, 9))
		local bowl = Instance.new("SpecialMesh")
		bowl.MeshType = Enum.MeshType.Sphere
		bowl.Parent = mouth
		table.insert(jaw, { part = mouth, offset = CFrame.new(0, -hh * 0.16, hd * 0.06) })
		local jawRoot = -hh * 0.02 - 0.225 * scale
		-- THE LOWER JAW ITSELF (from the same test: the fangs stood on nothing): a pale chin under them, and red gum
		-- along its top that the fangs stand in.
		local chin = piece("Chin", Vector3.new(hw * 0.78, hh * 0.26, hd * 0.74), Color3.fromRGB(226, 212, 196))
		local chinMesh = Instance.new("SpecialMesh")
		chinMesh.MeshType = Enum.MeshType.Sphere
		chinMesh.Parent = chin
		table.insert(jaw, { part = chin, offset = CFrame.new(0, jawRoot - hh * 0.1, -hd * 0.02) })
		local gum = piece("Gum", Vector3.new(hw * 0.68, hh * 0.08, hd * 0.6), flesh)
		local gumMesh = Instance.new("SpecialMesh")
		gumMesh.MeshType = Enum.MeshType.Sphere
		gumMesh.Parent = gum
		table.insert(jaw, { part = gum, offset = CFrame.new(0, jawRoot + 0.01, -hd * 0.05) })
		for k = 1, 8 do
			local a = (k - 4.5) / 3.5
			-- Uneven, as teeth are: no two the same height (a level row was a cake's candles in the play test).
			local len = 0.45 * scale * ({ 0.8, 1.35, 0.7, 1.0, 0.85, 1.1, 1.4, 0.75 })[k]
			local tooth = piece("Fang", Vector3.new(0.07 * scale, len, 0.07 * scale), fang)
			local spindle = Instance.new("SpecialMesh")
			spindle.MeshType = Enum.MeshType.Sphere
			spindle.Parent = tooth
			-- round the front of the jaw, an arc
			local lean = ({ -0.2, 0.1, -0.05, 0.18, -0.15, 0.06, -0.1, 0.2 })[k]
			table.insert(jaw, { part = tooth, offset = CFrame.new(a * hw * 0.3, jawRoot, -hd * (0.26 - 0.1 * a * a))
				* CFrame.Angles(-0.35, 0, lean - a * 0.3), len = len, dir = 1 })
		end
		-- SPIT, strung between the lid and the jaw: it stretches as he opens and snaps a strand at a time, each leaving a
		-- drip hanging from the lid. Wet and dark, not bright.
		strands = {}
		local spit = Color3.fromRGB(112, 38, 42)
		for i, x in ipairs({ -0.28, -0.12, 0.03, 0.15, 0.3 }) do
			local function thread(name: string): BasePart
				-- (0.035 was too fine to see from over your shoulder.)
				local p = piece(name, Vector3.new(0.065, 0.065, 0.1) * scale, spit)
				p.Reflectance = 0.18
				p.Transparency = 1
				return p
			end
			local u = x / 0.3
			table.insert(strands, {
				top = thread("Spit"),
				bottom = thread("Spit"),
				from = CFrame.new(x * hw, lidRoot + 0.04, -hd * 0.27),
				to = CFrame.new(x * hw * 0.9, jawRoot, -hd * (0.24 - 0.1 * u * u)),
				-- Two go on the throw open (its overshoot reaches about 1.1), the rest on the lunge.
				snap = ({ 1.04, 1.14, 1.22, 1.08, 1.18 })[i],
			})
		end
	end
	-- Each half's pieces, by where they sit from its hinge (the back edge of the face on its side).
	local halves = { [-1] = {}, [1] = {} }
	for _, side in ipairs(if template then {} else { -1, 1 }) do
		local list = {}
		-- ROUND, a head's half (the hundred-and-thirty-third pass): blocks, they read as two slabs.
		local half = piece("Half", Vector3.new(0.62, 1.8, 1.3) * SCREAM, skin)
		local round = Instance.new("SpecialMesh")
		round.MeshType = Enum.MeshType.Sphere
		round.Parent = half
		table.insert(list, { part = half, offset = CFrame.new(side * -0.3 * SCREAM, 0, -0.62 * SCREAM) })
		-- The cut face, red, on the side that opens toward the other half; the teeth standing off it into the gap.
		table.insert(list, { part = piece("Gum", Vector3.new(0.06, 1.55, 1.15) * SCREAM, flesh),
			offset = CFrame.new(side * 0.02 * SCREAM, 0, -0.62 * SCREAM) })
		for k = 1, 9 do
			-- A fang: a long pale spindle, standing off the gum into the gap.
			local tooth = piece("Tooth", Vector3.new(0.13, 0.13, 0.62) * SCREAM, bone)
			local spindle = Instance.new("SpecialMesh")
			spindle.MeshType = Enum.MeshType.Sphere
			spindle.Parent = tooth
			table.insert(list, { part = tooth, offset = CFrame.new(side * 0.16 * SCREAM, (-0.8 + k * 0.16) * SCREAM,
				(-0.95 + (k % 2) * 0.14) * SCREAM) * CFrame.Angles(0, side * 0.7, 0) })
		end
		halves[side] = list
	end
	local throat = piece("Throat", if template then Vector3.new(0.6, 0.5, 0.2) else Vector3.new(1.0, 1.4, 0.2) * SCREAM, flesh)
	throat.Name = "Throat"
	if template then
		-- Round and deep in the mouth, not a flat red square at the lens on the lunge.
		local deep = Instance.new("SpecialMesh")
		deep.MeshType = Enum.MeshType.Sphere
		deep.Parent = throat
	end
	local gullet = Instance.new("PointLight")
	gullet.Color = Color3.fromRGB(255, 70, 50)
	gullet.Brightness = 0
	gullet.Range = if template then 4 else 9 * SCREAM
	gullet.Shadows = false
	gullet.Parent = throat
	-- A pale light on his skin, from over the face, so the halves read as a head and not as slabs.
	local pale = Instance.new("PointLight")
	pale.Color = Color3.fromRGB(236, 230, 214)
	pale.Brightness = if template then 0.35 else 1.3
	pale.Range = 7 * SCREAM
	pale.Shadows = false
	pale.Parent = throat
	model.Parent = workspace.CurrentCamera
	return { model = model, left = halves[-1], right = halves[1], gullet = gullet, lid = lid, jaw = jaw, hinge = hinge,
		jawHinge = jawHinge, strands = strands, lidTurn = lidTurn, jawTurn = jawTurn, throatAt = throatAt, own = own,
		scale = screamerScale, eyeOpen = 0 }
end

-- A fang where its gum is in `frame`, grown to `grow` of its length out of it.
local function setFang(entry: Piece, frame: CFrame, grow: number)
	local len, dir = entry.len, entry.dir
	if not (len and dir) then
		entry.part.CFrame = frame * entry.offset
		return
	end
	local long = len * grow
	local size = entry.part.Size
	entry.part.Size = Vector3.new(size.X, long, size.Z)
	entry.part.CFrame = frame * entry.offset * CFrame.new(0, dir * long / 2, 0)
end

-- A thread between two points, or hidden if there is nothing to draw.
local function stretch(part: BasePart, a: Vector3, b: Vector3)
	local d = (b - a).Magnitude
	if d < 0.02 then
		part.Transparency = 1
		return
	end
	local size = part.Size
	part.Size = Vector3.new(size.X, size.Y, d)
	part.CFrame = CFrame.lookAt((a + b) / 2, b)
	part.Transparency = 0
end

-- Where the face is (its centre's frame, facing you) and how far open (0 shut, 1 wide).
local function placeScreamer(face: Screamer, at: CFrame, open: number)
	local lid, jaw, hinge = face.lid, face.jaw, face.hinge
	if lid and jaw and hinge then
		-- The made head: up and back off his face on its hinge, the jaw where it was.
		local tipped = at * hinge * CFrame.Angles((face.lidTurn or math.rad(40)) * open, 0, 0) * hinge:Inverse()
		local jawHinge = face.jawHinge or CFrame.new()
		local dropped = at * jawHinge * CFrame.Angles(-(face.jawTurn or math.rad(22)) * open, 0, 0) * jawHinge:Inverse()
		-- The fangs come out of the gums as he opens, short at first, then their whole length and more.
		local grow = 0.3 + 0.8 * math.clamp(open, 0, 1.3)
		for _, entry in ipairs(lid) do
			if entry.eyelid and face.scale and MarshMouth then
				-- His lids, up and back into his head as his eyes open.
				entry.part.CFrame = tipped * MarshMouth.lidTurn(entry.eyelid, face.scale, face.eyeOpen or 1)
				continue
			end
			setFang(entry, tipped, grow)
			-- Its fangs are inside his head until it lifts: not to be seen through his face.
			if entry.part.Name == "Fang" then
				entry.part.Transparency = if open > 0.05 then 0 else 1
			end
		end
		for _, entry in ipairs(jaw) do
			setFang(entry, dropped, grow)
			-- Shut, the jaw is inside his head and not to be seen through it (his own jaw, MouthJaw, is his chin: always).
			entry.part.Transparency = if open > 0.02 or entry.part.Name == "MouthJaw" then 0 else 1
		end
		-- The spit: sagging between the two while it holds, then a drip left hanging from the lid.
		for _, strand in ipairs(face.strands or {}) do
			local a = (tipped * strand.from).Position
			local b = (dropped * strand.to).Position
			-- Once snapped it stays snapped, though the mouth eases back a little after its first throw.
			if open >= strand.snap then
				strand.broken = true
			end
			if open <= 0.08 then
				strand.top.Transparency, strand.bottom.Transparency = 1, 1
			elseif not strand.broken then
				local sag = (a + b) / 2 - Vector3.new(0, 0.12 * (b - a).Magnitude, 0)
				stretch(strand.top, a, sag)
				stretch(strand.bottom, sag, b)
			else
				stretch(strand.top, a, a - Vector3.new(0, 0.2, 0))
				strand.bottom.Transparency = 1
			end
		end
		local throat = face.model:FindFirstChild("Throat")
		if throat and throat:IsA("BasePart") then
			throat.CFrame = at * (face.throatAt or CFrame.new(0, -0.15, 0.35))
			throat.Transparency = if open > 0.02 then 0 else 1
		end
		return
	end
	local swing = math.rad(78) * open
	local h = 0.62 * SCREAM
	for _, entry in ipairs(face.left) do
		entry.part.CFrame = at * CFrame.new(h, 0, h) * CFrame.Angles(0, -swing, 0) * CFrame.new(-h, 0, -h) * entry.offset
	end
	for _, entry in ipairs(face.right) do
		entry.part.CFrame = at * CFrame.new(-h, 0, h) * CFrame.Angles(0, swing, 0) * CFrame.new(h, 0, -h) * entry.offset
	end
	local throat = face.model:FindFirstChild("Throat")
	if throat and throat:IsA("BasePart") then
		throat.CFrame = at * CFrame.new(0, 0, 0.35 * SCREAM)
	end
end

-- CAUGHT (the screamer, made far worse in the hundred-and-third pass: "make the screamer way more dramatic"; acted out
-- in the hundred-and-twenty-fifth; and made something you can follow in the hundred-and-thirty-third, from your test:
-- "it's so weird, I don't understand what's going on, it should be longer and I should understand what I'm looking
-- at"): every light near you goes out and the hum with it, a beat of black; then a red flicker back, low, and SIDE ON,
-- far enough off to see all of it, you and HIM, folded down over you with his arms coming round you (StalkerClient
-- draws it), his growl, you starting back; then OVER YOUR SHOULDER, his blank head, at a size you can read, splits down
-- its seam and swings open onto the fangs and the red throat, the stab and his roar at once, the lights flaring; it
-- LUNGES at you; black. The server takes you to the lobby in the black (Bootstrap waits for it).
local CAUGHT = { loom = 0.35, face = 1.9, black = 3.5 }
local LUNGE_AT = 1.15 -- seconds into his face that it lunges at you

-- IN HIS HANDS (the hundred-and-sixty-seventh pass, from your note of 2026-11-03: "it incorrectly positions the
-- characters in the hands of the monster"): BackRoomsService squared him up to you, Grip studs off; here, in the black
-- before the lights come back, you are set exactly there, facing him, so his hands (StalkerClient's HOLD) close round
-- you and not the air beside you. Your screen's own place for you is a step ahead of the server's, which is the gap this
-- closes. Nothing is done if he was not squared up (no Grip on him).
local function holdMe(character: Model?)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rooms = workspace:FindFirstChild("BackRooms")
	if not (root and root:IsA("BasePart") and rooms) then
		return
	end
	local holder: Model? = nil
	local nearest = math.huge
	for _, item in ipairs(rooms:GetChildren()) do
		if item.Name == "Marsh" and item:IsA("Model") and item:GetAttribute("Caught") == true and item.PrimaryPart then
			local gap = ((item.PrimaryPart :: BasePart).Position - root.Position).Magnitude
			if gap < nearest then
				holder, nearest = item, gap
			end
		end
	end
	local grip = holder and holder:GetAttribute("Grip")
	if not (holder and holder.PrimaryPart and typeof(grip) == "number") then
		return
	end
	local his = (holder.PrimaryPart :: BasePart).CFrame
	local ahead = Vector3.new(his.LookVector.X, 0, his.LookVector.Z)
	if ahead.Magnitude < 0.05 then
		return
	end
	local spot = Vector3.new(his.Position.X, root.Position.Y, his.Position.Z) + ahead.Unit * grip
	root.AssemblyLinearVelocity = Vector3.zero
	root.CFrame = CFrame.lookAt(spot, Vector3.new(his.Position.X, spot.Y, his.Position.Z))
end

-- THE CAMERA KEPT IN THE ROOM (the same pass): the rooms are four studs across in places, and a shot from eight studs to
-- one side was in the wall. How far there is to look from, from `mid` along `way`, up to `most`.
local function roomAlong(mid: Vector3, way: Vector3, most: number, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(mid, way * most, params)
	return if hit then hit.Distance else most
end

local function caught(data: { [string]: any })
	local at = data.at
	if not Cinema or typeof(at) ~= "Vector3" then
		return
	end
	stopDread()
	scene.token += 1
	busy = true
	local token = scene.token
	-- (Not hushed: the hum goes with the lights, below, and you are in the lobby before it could matter.)
	Cinema.begin({ hush = false })
	act("startle")
	faceToward(at)
	local lights = tubes()
	local was: { [SurfaceLight]: number } = {}
	for _, light in ipairs(lights) do
		was[light] = light.Brightness
		light.Brightness = 0
	end
	sound("TubeDie", nil, 0.9, 1)
	Cinema.black(true, 0.06)
	local camera = workspace.CurrentCamera
	local eye = camera.CFrame
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	holdMe(character)
	local face: Screamer? = nil
	local current = { thought = false, opened = false, lunged = false, hidden = {} :: { BasePart },
		mine = {} :: { [BasePart]: boolean },
		side = nil :: Vector3?, ignore = (if character then { character } else {}) :: { Instance } }
	local began = os.clock()
	local loomed = false
	local struck = false
	local blacked = false
	local hook
	hook = RunService.RenderStepped:Connect(function()
		local t = os.clock() - began
		if scene.token ~= token then
			hook:Disconnect()
			if face then
				face.model:Destroy()
			end
			for item in pairs(current.mine) do
				item.LocalTransparencyModifier = 0
			end
			return
		end
		-- HIS HEAD: his walking copy's on this screen (StalkerClient), else where the server said it was; and you.
		local seen = workspace:FindFirstChild("MarshSeen")
		local headPart = seen and seen:FindFirstChild("Head")
		local his = if headPart and headPart:IsA("BasePart") then headPart.Position else at
		local me = if root and root:IsA("BasePart") then root.Position else at
		local toward = Vector3.new(his.X - me.X, 0, his.Z - me.Z)
		toward = if toward.Magnitude > 0.1 then toward.Unit else Vector3.zAxis
		local across = Vector3.new(-toward.Z, 0, toward.X)
		if t >= CAUGHT.loom and not loomed then
			-- A RED FLICKER BACK, low: him, over you.
			loomed = true
			for light, brightness in pairs(was) do
				light.Brightness = brightness * 0.3
			end
			Cinema.black(false, 0.08)
			Cinema.cut()
			sound("MawGrowl", "rbxasset://sounds/bass.mp3", 0.8, 0.7)
			Cinema.shake(1.4)
			Cinema.impact(0.6, true)
		end
		if t >= CAUGHT.loom + 0.45 and not current.thought then
			current.thought = true
			Cinema.think(character, "What IS that?!", 1.2)
		end
		if t >= CAUGHT.face and not struck then
			struck = true
			face = screamerFace()
			Cinema.cut()
			-- Your thought gone with the cut (the two-hundred-and-twenty-fifth pass: "What IS that?!" hung on into his face).
			local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
			local thought = gui and gui:FindFirstChild("CinemaThought")
			if thought then
				thought:Destroy()
			end
			-- His own head put out of the way on this screen: the face that opens is in its place.
			if headPart and headPart:IsA("BasePart") then
				for _, item in ipairs(headPart.Parent and headPart.Parent:GetDescendants() or {}) do
					if item:IsA("BasePart") and (item == headPart or item:IsDescendantOf(headPart)
						or item.Name == "Seam" or item.Name == "Face" or item.Name == "MadeHead"
						or string.sub(item.Name, 1, 5) == "Mouth") then
						item.LocalTransparencyModifier = 1
						table.insert(current.hidden, item)
					end
				end
			end
			-- OVER YOUR SHOULDER, back far enough to see all of his head (and never past a wall behind you).
			-- Aimed a little over his head, so the lid going up stays in the picture and does not fill the top of it.
			local aim = his + Vector3.new(0, 0.45, 0)
			-- FROM WHERE THERE IS ROOM (pass 223's play test: from behind you in a four-stud room the wall stopped the lens
			-- two studs off his face). Over your shoulder if that way has the room, else along whichever way out of the
			-- room has most, never more than 5.9 off.
			local back = (-toward * 5.9 + across * 1.7).Unit
			local best, room = back, roomAlong(aim, back, 6.5, current.ignore)
			for _, way in ipairs({ (-toward + across).Unit, (-toward - across).Unit, across, -across }) do
				local here = roomAlong(aim, way, 6.5, current.ignore) * 0.85
				if room < 5 and here > room then
					best, room = way, here
				end
			end
			local off = math.clamp(room - 0.5, 1.5, 5.9)
			eye = CFrame.lookAt(Cinema.clear(aim + best * off + Vector3.new(0, 0.05, 0), aim, current.ignore), aim)
		end
		if face then
			local s = t - CAUGHT.face
			-- THE THROW OPEN: a beat shut, shuddering harder; then flung open past wide and easing back (an overshoot),
			-- quivering as he roars; wider again as he comes at you.
			local p = math.clamp((s - 0.35) / 0.26, 0, 1)
			local q = p - 1
			local open = if p <= 0 then 0 else 1 + 2.70158 * q * q * q + 1.70158 * q * q
			local lunge = math.clamp((s - LUNGE_AT) / 0.35, 0, 1) ^ 2
			if p >= 1 then
				open += 0.035 * math.sin(s * 26) + 0.25 * lunge
			end
			local quake = if p <= 0 then 0.07 * math.clamp(s / 0.35, 0, 1) else 0.018
			local shudder = CFrame.Angles(math.noise(s * 31, 0.5) * quake, math.noise(s * 29, 7.5) * quake,
				math.noise(s * 33, 13.5) * quake)
			if p > 0 and not current.opened then
				current.opened = true
				for light, brightness in pairs(was) do
					light.Brightness = brightness * 1.25
				end
				sound("ScreamerStab", "rbxasset://sounds/bass.mp3", 1, 1)
				sound("MawRoar", "rbxasset://sounds/bass.mp3", 1, 0.8)
				Cinema.impact(1.6, true)
				Cinema.shake(3)
			end
			if lunge > 0 and not current.lunged then
				current.lunged = true
				Cinema.impact(2, true)
				Cinema.shake(4)
			end
			-- His face where his head is, facing you, and on the lunge flying at the lens, his head cocking as it comes.
			local from = his:Lerp(eye.Position + eye.LookVector * 1.4, lunge)
			-- HIS EYES FLY OPEN (the two-hundred-and-twenty-eighth pass): half open as the shot comes, then wide, a beat
			-- before his mouth.
			face.eyeOpen = 0.45 + 0.55 * math.clamp((s - 0.1) / 0.08, 0, 1)
			placeScreamer(face, CFrame.lookAt(from, eye.Position) * CFrame.Angles(0, 0, 0.22 * lunge) * shudder, open)
			-- NOTHING OF YOURS IN THE WAY (pass 222's play test: a big hair took half the picture): your head and what you
			-- wear on it, where it lies across the line from the lens to his face, kept out of this shot. Your shoulder
			-- and body stay, so you are still seen there.
			if character then
				local lens = eye.Position
				local line = from - lens
				for _, item in ipairs(character:GetDescendants()) do
					if item:IsA("BasePart") and (item.Name == "Head" or item:FindFirstAncestorWhichIsA("Accessory")) then
						local k = math.clamp((item.Position - lens):Dot(line) / line:Dot(line), 0, 1)
						local off = (lens + line * k - item.Position).Magnitude
						if off < item.Size.Magnitude * 0.5 + 0.5 then
							item.LocalTransparencyModifier = 1
							current.mine[item] = true
						end
					end
				end
			end
			face.gullet.Brightness = 2 + 3 * math.min(open, 1) + 1.2 * math.sin(s * 19) ^ 2 + math.random() * 0.6
			-- WIDER WHERE THE WALLS PUSH THE LENS IN (pass 223's play test: in the four-stud rooms the camera came to two
			-- studs off and his face filled the screen, nostrils and all, before it opened). Wide enough to hold about four
			-- studs of him, his head and the lid going up.
			local near = (eye.Position - his).Magnitude
			local fits = math.deg(2 * math.atan(2.1 / math.max(near, 0.5)))
			Cinema.point(eye, math.clamp(math.max(52 + 5 * math.min(open, 1), fits), 40, 88) + 10 * lunge)
		elseif loomed then
			-- HE HAS YOU: side on, far enough off to see all of it, you and him folded down over you, easing in. From the
			-- side with the more room, chosen once; where neither side has room for it (a corridor), from behind you and
			-- a little to one side, along it; and never past a wall.
			local k = math.clamp((t - CAUGHT.loom) / (CAUGHT.face - CAUGHT.loom), 0, 1)
			local mid = me:Lerp(his, 0.5) + Vector3.new(0, 0.6, 0)
			if not current.side then
				local left, right = roomAlong(mid, across, 8, current.ignore), roomAlong(mid, -across, 8, current.ignore)
				current.side = if math.max(left, right) >= 5 then (if left >= right then across else -across)
					else (across * 0.45 - toward).Unit
			end
			local side = current.side :: Vector3
			local want = mid + side * (8 - 1.5 * k) - toward * 1 + Vector3.new(0, 1.8, 0)
			Cinema.point(CFrame.lookAt(Cinema.clear(want, mid, current.ignore), mid), 60 - 4 * k)
		else
			Cinema.point(eye, 70)
		end
		if t > CAUGHT.black and not blacked then
			blacked = true
			Cinema.black(true, 0.04)
			if face then
				face.model:Destroy()
				face = nil
			end
			for _, item in ipairs(current.hidden) do
				item.LocalTransparencyModifier = 0
			end
			for item in pairs(current.mine) do
				item.LocalTransparencyModifier = 0
			end
			for light, brightness in pairs(was) do
				light.Brightness = brightness
			end
		end
		if t > CAUGHT.black + 0.6 then
			hook:Disconnect()
			endScene()
		end
	end)
end

-- ===== THE PEOPLE TELL IT WITH THEIR BODIES =====
--
-- Everyone in Harrow Bay who says a line says it with a gesture (Townsfolk sets Gesture, GestureAt and
-- GestureFor on them, and which hand is free in Hands); here it is played on their joints every frame, on top
-- of how they stand and the head the server turns to you: smooth, which turning them from the server is not.
-- Only near the camera, and let go of when the line is done. Their own client's clock, set against the
-- server's once per line.
type Teller = { joints: { [string]: any }?, at: number?, clock: number, playing: boolean }
local tellers: { [Instance]: Teller } = {}
local TELL_SEEN = 90 -- studs: further than this from the camera, nobody's hands are worth turning

-- THEIR VOICES: no words, the sound of somebody talking as they say a line, the one for its gesture (a hello, a
-- mumbled explaining, a questioning hum, a worried one, a sigh: audio/gen_voice_sfx.py, nine takes in one upload,
-- SoundService.StorySounds.TownsfolkVoice_x9, in the order of Poses.GESTURES), from their head, at their own pitch
-- (Townsfolk's VOICES). Only as a line starts, never for one already being said. Silent until it is imported.
local VOICE_SLOT = 2.0
local function speak(model: Instance, gesture: string)
	local folder = SoundService:FindFirstChild("StorySounds")
	local sheet = folder and folder:FindFirstChild("TownsfolkVoice_x9")
	local head = model:FindFirstChild("Head")
	local index = if Poses and Poses.GESTURES then table.find(Poses.GESTURES, gesture) else nil
	if not (sheet and sheet:IsA("Sound") and head and head:IsA("BasePart") and index) then
		return
	end
	local voice = sheet:Clone()
	voice.Name = "Voice"
	local from = (index - 1) * VOICE_SLOT
	local pitch = model:GetAttribute("Voice")
	voice.PlaybackSpeed = (if typeof(pitch) == "number" then pitch else 1) * (0.97 + math.random() * 0.06)
	voice.Volume = 0.55
	voice.Looped = false
	voice.RollOffMode = Enum.RollOffMode.InverseTapered
	voice.RollOffMinDistance = 8
	voice.RollOffMaxDistance = 50
	local regioned = pcall(function()
		(voice :: any).PlaybackRegionsEnabled = true;
		(voice :: any).PlaybackRegion = NumberRange.new(from, from + VOICE_SLOT - 0.05)
	end)
	voice.TimePosition = from
	voice.Parent = head
	voice:Play()
	if not regioned then
		task.delay((VOICE_SLOT - 0.07) / voice.PlaybackSpeed, function()
			if voice.Parent then
				voice:Stop()
			end
		end)
	end
	-- Gone once its slot has played, at its own speed (the lowest voices take nearly three seconds over two).
	game:GetService("Debris"):AddItem(voice, VOICE_SLOT / voice.PlaybackSpeed + 0.5)
end

local function stepTellers()
	if not Poses then
		return
	end
	local camera = workspace.CurrentCamera
	local now = os.clock()
	for model, teller in pairs(tellers) do
		if not model.Parent then
			tellers[model] = nil
			continue
		end
		local gesture = model:GetAttribute("Gesture")
		local at, span = model:GetAttribute("GestureAt"), model:GetAttribute("GestureFor")
		if typeof(at) == "number" and at ~= teller.at then
			teller.at = at
			teller.clock = now - (workspace:GetServerTimeNow() - at)
			-- A line just begun: said aloud.
			if typeof(gesture) == "string" and workspace:GetServerTimeNow() - at < 0.5 then
				speak(model, gesture)
			end
		end
		local t = now - teller.clock
		local root = (model :: Model).PrimaryPart
		local active = typeof(gesture) == "string" and typeof(span) == "number" and teller.at ~= nil and t >= 0
			and t < span and root ~= nil and camera ~= nil and (root.Position - camera.CFrame.Position).Magnitude < TELL_SEEN
		if active then
			if not teller.joints then
				teller.joints = Poses.joints(model)
			end
			local joints = teller.joints :: { [string]: any }
			local r6 = Poses.isR6(joints)
			local w = Poses.weight(t, span :: number)
			local hands = model:GetAttribute("Hands")
			-- A PLAYER'S BODY is being walked and breathed by their animations: only the joints the gesture moves are
			-- set, and the rest are left to them (a townsperson has no animations, so every joint is set).
			local own = Players:GetPlayerFromCharacter(model) ~= nil
			for name, joint in pairs(joints) do
				local by = Poses.tell(gesture :: string, name, t, w, if typeof(hands) == "string" then hands else "both", r6)
				if by or not own then
					Poses.drive(joint, by or CFrame.identity)
				end
			end
			teller.playing = true
		elseif teller.playing then
			teller.playing = false
			for _, joint in pairs(teller.joints or {}) do
				Poses.drive(joint, CFrame.identity)
			end
		end
	end
end

-- THE WATCHER, GONE (the hundred-and-sixteenth pass): once you have clocked in, opened the gates and seen his face (the
-- true ending), his ledge on the Deco tower is empty on your screen. He has stopped waiting.
local function stoppedWaiting(model: Instance)
	if model.Name ~= "Watcher" then
		return
	end
	local function hide(item: Instance)
		if (item:IsA("BasePart") or item:IsA("Decal")) and Players.LocalPlayer:GetAttribute("TrueEnding") == true then
			item.LocalTransparencyModifier = 1
		end
	end
	for _, item in ipairs(model:GetDescendants()) do
		hide(item)
	end
	model.DescendantAdded:Connect(hide)
end

-- HE COMES NEARER (the hundred-and-seventy-second pass): the Watcher on the way ahead of you (StoryService's
-- watcherAhead) is gone before you reach him. Within AHEAD.near studs he fades in AHEAD.fade seconds, with a breath
-- under everything, and is not seen again where he stood.
local AHEAD = { near = 34, fade = 0.7 }
local function aheadGone(model: Instance)
	if model.Name ~= "Watcher" then
		return
	end
	local function watch()
		local hook
		hook = RunService.Heartbeat:Connect(function()
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local his = model:FindFirstChild("HumanoidRootPart")
			if not model.Parent then
				hook:Disconnect()
				return
			end
			if not (root and root:IsA("BasePart") and his and his:IsA("BasePart"))
				or (root.Position - his.Position).Magnitude > AHEAD.near then
				return
			end
			hook:Disconnect()
			sound("MawGrowl", "rbxasset://sounds/bass.mp3", 0.22, 0.55)
			local began = os.clock()
			local fade
			fade = RunService.Heartbeat:Connect(function()
				local k = math.clamp((os.clock() - began) / AHEAD.fade, 0, 1)
				for _, item in ipairs(model:GetDescendants()) do
					if item:IsA("BasePart") or item:IsA("Decal") then
						item.LocalTransparencyModifier = math.max(item.LocalTransparencyModifier, k)
					end
				end
				if k >= 1 or not model.Parent then
					fade:Disconnect()
					-- GONE IS GONE (the hundred-and-seventy-ninth pass): nothing of him left on this screen to walk into or
					-- to catch the camera, in the group that meets nothing (StoryService's apparitions), whatever the
					-- server has him in.
					for _, item in ipairs(model:GetDescendants()) do
						if item:IsA("BasePart") then
							item.CanQuery = false
							pcall(function()
								item.CollisionGroup = "Apparitions"
							end)
						end
					end
				end
			end)
		end)
	end
	-- (Written on him by the server just after he is made, so it may arrive a moment after he does.)
	if model:GetAttribute("Ahead") == true then
		watch()
	else
		local waiting
		waiting = model:GetAttributeChangedSignal("Ahead"):Connect(function()
			if model:GetAttribute("Ahead") == true then
				waiting:Disconnect()
				watch()
			end
		end)
	end
end

local function startTellers()
	local function add(model: Instance)
		if model:IsA("Model") and not tellers[model] then
			tellers[model] = { joints = nil, at = nil, clock = 0, playing = false }
			stoppedWaiting(model)
			aheadGone(model)
		end
	end
	-- The people, and (the hundred-and-nineteenth pass) any player saying a line of their own (Townsfolk.speakAs tags
	-- them Teller): told the same way.
	for _, tag in ipairs({ "Townsperson", "Teller" }) do
		for _, model in ipairs(CollectionService:GetTagged(tag)) do
			add(model)
		end
		CollectionService:GetInstanceAddedSignal(tag):Connect(add)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(function(model: Instance)
			tellers[model] = nil
		end)
	end
	-- After the animations, as every pose in this game is.
	RunService.Stepped:Connect(function()
		pcall(stepTellers)
	end)
end

-- ONE OF A ROW AT A TIME (the hundred-and-twenty-fourth pass, from your test: "locker 3 is hard to open"): of prompts
-- tagged OneOfARow (the halls' staff lockers, side by side), only the one nearest you along the floor shows on this
-- screen, measured from where it stands shut (RowAt), so the one in front of you is the one you open.
local function oneOfARow()
	local last = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - last < 0.15 then
			return
		end
		last = now
		local tagged = CollectionService:GetTagged("OneOfARow")
		if #tagged == 0 then
			return
		end
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			return
		end
		local best, bestGap = nil, math.huge
		for _, item in ipairs(tagged) do
			local at = item:GetAttribute("RowAt")
			if item:IsA("ProximityPrompt") and typeof(at) == "Vector3" then
				local gap = Vector3.new(at.X - root.Position.X, 0, at.Z - root.Position.Z).Magnitude
				if gap < bestGap then
					best, bestGap = item, gap
				end
			end
		end
		for _, item in ipairs(tagged) do
			if item:IsA("ProximityPrompt") then
				item.Enabled = item == best
			end
		end
	end)
end

function StoryClient.start()
	-- Taken to the lobby mid-scene: the scene is over, its loops end on the token, you are yourself again.
	if Cinema and Cinema.onLeave then
		Cinema.onLeave(function()
			scene.token += 1
			endScene()
		end)
	end
	-- His head cut at the lips, in the background, ready for when he opens it (MarshMouth).
	if MarshMouth then
		task.spawn(MarshMouth.prepare)
		-- And the lobby leviathan's jaw (the two-hundred-and-twenty-ninth pass).
		if MarshMouth.leviathan then
			task.spawn(MarshMouth.leviathan)
		end
	end
	-- The people's gestures first: they need nothing but the people.
	startTellers()
	oneOfARow()
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	local event = remotes and remotes:WaitForChild("StoryMoment", 20)
	if not (event and event:IsA("RemoteEvent")) then
		warn("StoryClient: no RemoteEvents.StoryMoment, so secrets have no scene and nothing whispers. The server "
			.. "Bootstrap makes it; paste src/Server/Bootstrap.server.lua.")
		return
	end
	event.OnClientEvent:Connect(function(kind: any, data: any)
		local ok, err = pcall(function()
			if kind == "whisper" and typeof(data) == "string" then
				whisper(data)
			elseif kind == "pry" and typeof(data) == "table" then
				pry(data)
			elseif kind == "moment" and typeof(data) == "table" then
				moment(data)
			elseif kind == "peek" and typeof(data) == "table" then
				peek(data)
			elseif kind == "stalk" and typeof(data) == "table" then
				stalked(data)
			elseif kind == "caught" and typeof(data) == "table" then
				caught(data)
			end
		end)
		if not ok then
			warn("StoryClient: a moment failed, and the camera is given back: " .. tostring(err))
			pcall(endScene)
			busy = false
		end
	end)
	-- THE BACK ROOMS' OWN LIGHT, and the door you came in by, as you go in and out of them.
	local me = Players.LocalPlayer
	local function placeChanged()
		local down = me:GetAttribute("InLevel") == "backRooms"
		backRoomsLight(down)
		if not down then
			stopDread()
		end
	end
	me:GetAttributeChangedSignal("InLevel"):Connect(placeChanged)
	me:GetAttributeChangedSignal("BackRoomsFrom"):Connect(lightTheDoor)
	placeChanged()
	print("StoryClient: running, " .. StoryClient.VERSION)
end

StoryClient.STAMP = "3da889d8"
return StoryClient
