--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

print("[client] Bootstrap starting")

local Services = script.Parent:WaitForChild("Services")
local UIService = require(Services:WaitForChild("UIService"))
local InputService = require(Services:WaitForChild("InputService"))
require(Services:WaitForChild("AudioService"))
require(Services:WaitForChild("ScreenEffects"))
require(Services:WaitForChild("DeformationRenderer"))
-- The lobby lever, which is client-built because it has to move differently for each
-- player. See the header in HubLeverService for why that is not something the server can do.
require(Services:WaitForChild("HubLeverService"))
-- The ballot banner. Counts live on the pads in the room; your own picks and the countdown
-- live here, because a part in the workspace has one appearance for every viewer.
require(Services:WaitForChild("HubVoteService"))
-- The in-run menu. LeaveLevel has existed on the server since the hub was built and nothing
-- on the client ever fired it, so the exit was implemented at one end only.
require(Services:WaitForChild("PauseMenuService"))
-- The hardcore death card. Falling used to be silent; this is the part that says so.
require(Services:WaitForChild("DeathService"))
-- BackdropService IS NO LONGER A CLIENT SERVICE. It used to be required here and hooked
-- RenderStepped to keep the horizon locked to the player. It is static geometry built
-- once on the server now, so there is nothing left for the client to do.
-- DELETE StarterPlayerScripts/Services/BackdropService from the place file; if it is left
-- behind it will build a second horizon on top of the real one.
--
-- SeaService is the one piece of the backdrop that is still a client concern: it animates
-- the swell on parts the server already built, locally, so the motion costs no
-- replication. Started in a task.spawn because it waits for the backdrop to exist and
-- must not hold up anything below it.
local SeaService = require(Services:WaitForChild("SeaService"))
task.spawn(SeaService.start)

-- Same arrangement, and separate from SeaService for the same reason it is a separate
-- file: the swell loop sways parts about a fixed origin, and a cloud has to travel and
-- wrap. Spawned rather than called, because it waits on the backdrop existing.
local CloudService = require(Services:WaitForChild("CloudService"))
task.spawn(CloudService.start)

-- THE TWO LEVELS WITH MOVING PARTS OF THEIR OWN: Sky Pools' splashing pools and drifting toys, and
-- the Sunken City's thing, whirlpool, buoys, fish and clock. Each is looked for WITH A TIMEOUT inside
-- its own task, so a place that has not had one pasted in loses that level's moving water and
-- nothing else -- a bare WaitForChild here would hold up every line below it forever.
for _, name in ipairs({ "SkyPoolsClient", "SunkenCityClient" }) do
	task.spawn(function()
		local module = Services:WaitForChild(name, 30)
		if module and module:IsA("ModuleScript") then
			local service: any = require(module)
			service.start()
		else
			warn(("[client] no StarterPlayerScripts.Services.%s; that level's water will not move. Paste "
				.. "src/Client/Services/%s.lua in as a ModuleScript."):format(name, name))
		end
	end)
end

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local LevelCompleted = RemoteEvents:WaitForChild("LevelCompleted")
local SlimeLaunch = RemoteEvents:WaitForChild("SlimeLaunch")
-- THE DIVE'S BLACKOUT. WaitForChild WITH A TIMEOUT and a nil guard, because a place whose server
-- Bootstrap predates this remote would otherwise yield here forever -- and every line below this
-- one would never run, which is the failure this file has already had once.
local ScreenFade = RemoteEvents:WaitForChild("ScreenFade", 10) :: RemoteEvent?
if ScreenFade then
	ScreenFade.OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.black then
			UIService.fadeToBlack(payload.time)
		else
			UIService.fadeFromBlack(payload.time)
		end
	end)
end

-- Applied here, on the client, because this client owns the character assembly.
-- The server decides when a launch happens; if it wrote the velocity itself the
-- value would be discarded on the next physics replication.
SlimeLaunch.OnClientEvent:Connect(function(launchVelocity: number)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then
		return
	end
	-- Leave Running first: that state actively damps vertical velocity, so
	-- assigning without it eats most of the launch.
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	local current = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(current.X, launchVelocity, current.Z)
end)

-- THE MODE HITBOX USED TO BE BUILT HERE, and it is gone on purpose.
--
-- It was a transparent TextButton laid over UIService's mode label, because that label
-- was a TextLabel and could not be clicked. UIService's indicator is a real TextButton
-- now and InputService connects to it directly, so this overlay would be a SECOND
-- connection to the same toggle -- one click, two flips, mode unchanged and apparently
-- broken.
--
-- It also found the label with `screenGui:WaitForChild("ModeIndicator")`, which is worth
-- remembering: WaitForChild without a timeout yields FOREVER. Renaming the instance in
-- UIService stalled this script permanently at that line, and everything below it --
-- including the completion handler -- simply never ran. No error, no output, just a
-- client that stopped halfway through starting up.

-- ===== Level completion =====

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Soft, slow and pastel rather than a firework. The whole game is built around calm
-- tactile feedback, and a burst of hard confetti at the end of it would be the one moment
-- that belongs to a different game.
--
-- The palette is the HUD's accent set -- the pink it uses for hardcore, the gold it uses
-- for first place, the blue it uses for chill. Effects and interface drawn from one set of
-- colours read as one product; picked separately they read as two.
local CELEBRATION_COLOURS = ColorSequence.new({
	ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255, 214, 140)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 190, 205)),
	ColorSequenceKeypoint.new(1.0, Color3.fromRGB(180, 210, 245)),
})

-- Respected if the platform exposes it. A celebration is exactly the kind of thing that
-- should get quieter, not disappear, when someone has asked for less motion.
local function reducedMotion(): boolean
	local ok, value = pcall(function()
		return UserSettings():GetService("UserGameSettings").ReducedMotion
	end)
	return ok and value == true
end

-- A flat disc that expands and fades: the shockwave.
--
-- THIS IS THE PIECE THAT GIVES THE BURST A CAUSE. Particles alone spray outward from
-- nothing in particular; a ring travelling out along the ground says the energy came from
-- a point, at an instant, and everything else is a consequence of it. A Cylinder part
-- extrudes along its X axis, so it needs a 90-degree roll to lie flat -- a detail this
-- project has been caught by before.
local function shockwave(origin: Vector3, parent: Instance)
	local ring = Instance.new("Part")
	ring.Name = "CompletionRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.25, 3, 3)
	ring.CFrame = CFrame.new(origin) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 226, 236)
	ring.Transparency = 0.35
	ring.Parent = parent

	TweenService:Create(ring, TweenInfo.new(0.85, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.25, 46, 46),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, 1.2)
end

local function celebrateAt(root: BasePart)
	local quiet = reducedMotion()

	local attachment = Instance.new("Attachment")
	attachment.Parent = root

	-- The motes: many, slow, and long-lived, so the moment lingers instead of snapping.
	local motes = Instance.new("ParticleEmitter")
	motes.Color = CELEBRATION_COLOURS
	motes.LightEmission = 0.65
	motes.LightInfluence = 0
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0.0, 0.0),
		NumberSequenceKeypoint.new(0.15, 0.55),
		NumberSequenceKeypoint.new(1.0, 0.0),
	})
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.0, 1.0),
		NumberSequenceKeypoint.new(0.1, 0.15),
		NumberSequenceKeypoint.new(1.0, 1.0),
	})
	motes.Lifetime = NumberRange.new(2.2, 3.4)
	motes.Speed = NumberRange.new(7, 15)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Drag = 2.5 -- they slow and hang rather than flying off
	motes.Acceleration = Vector3.new(0, -6, 0)
	motes.Rate = 0
	motes.Rotation = NumberRange.new(0, 360)
	motes.RotSpeed = NumberRange.new(-40, 40)
	motes.Parent = attachment

	-- A second, much slower set that drifts UPWARD, which is what stops the whole thing
	-- reading as an explosion: something is still gently happening a beat after the burst
	-- is over.
	local drift = Instance.new("ParticleEmitter")
	drift.Color = CELEBRATION_COLOURS
	drift.LightEmission = 0.8
	drift.LightInfluence = 0
	drift.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0.0, 0.0),
		NumberSequenceKeypoint.new(0.3, 0.25),
		NumberSequenceKeypoint.new(1.0, 0.0),
	})
	drift.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.0, 1.0),
		NumberSequenceKeypoint.new(0.2, 0.35),
		NumberSequenceKeypoint.new(1.0, 1.0),
	})
	drift.Lifetime = NumberRange.new(3.5, 5.0)
	drift.Speed = NumberRange.new(1.5, 3.5)
	drift.SpreadAngle = Vector2.new(140, 140)
	drift.Acceleration = Vector3.new(0, 2.2, 0)
	drift.Rate = 0
	drift.Parent = attachment

	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 236, 246)
	glow.Range = 28
	glow.Brightness = 3.4
	glow.Parent = attachment

	-- STAGGERED, NOT SIMULTANEOUS. Firing every emitter on one frame is a single flat
	-- thud; spreading them over about a third of a second gives the moment a shape -- an
	-- impact, then a bloom, then a slow drift. It is the same reason list rows cascade
	-- rather than appearing together, applied to a physical effect instead of a panel.
	if not quiet then
		-- Parented to workspace, not to the character. An anchored Part inside a character
		-- model is an extra limb as far as the Humanoid is concerned, and it is a local
		-- effect anyway -- nothing about it belongs to the rig.
		shockwave(root.Position, workspace)
	end
	motes:Emit(if quiet then 40 else 140)
	TweenService:Create(glow, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = 0,
	}):Play()

	task.delay(0.12, function()
		if attachment.Parent then
			drift:Emit(if quiet then 20 else 60)
		end
	end)
	-- A smaller second pop, off-beat, so the effect does not decay in a straight line.
	task.delay(0.3, function()
		if attachment.Parent and not quiet then
			motes:Emit(45)
		end
	end)

	-- Debris rather than task.delay: if the character is destroyed first (respawn, reset)
	-- the attachment goes with it, and a pending delay would be writing to a destroyed
	-- instance.
	Debris:AddItem(attachment, 7)
end

LevelCompleted.OnClientEvent:Connect(function(payload)
	UIService.showCompletion(payload.levelId, payload.time)

	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		celebrateAt(root)
	end
end)

print("[client] Bootstrap ready")
