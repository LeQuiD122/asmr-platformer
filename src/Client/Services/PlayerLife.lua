--!strict
-- StarterPlayerScripts/Services/PlayerLife.lua
-- YOUR CHARACTER, ALIVE (the hundred-and-twentieth pass, from your test: "the player should have animations, not just
-- stand still": in the scenes, when talking, and all the time). On top of Roblox's own walk and idle, after them each
-- frame, on this screen:
--
--   YOUR HEAD FOLLOWS WHERE YOU LOOK: your own character's head turns after the camera, as far as a neck turns, and
--   standing still the body turns a little with it; look back over your shoulder and it turns ahead again. Yours only:
--   it is your camera.
--   STANDING ABOUT: anyone stood still a while (you, and everyone you can see) now and then looks round, shifts their
--   weight, or puts a hand to their chin, each in their own time, and stops the moment they move.
--
-- Never while something else has them: a scene (Cinema, on your own screen), an emote, a line being told (a Teller's
-- gesture, StoryClient), a seat, the water, a ride.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Poses: any = (function()
	local found = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Poses", 15)
	return if found and found:IsA("ModuleScript") then require(found) else nil
end)()

-- A module beside this one (Cinema, EmoteService), found when first wanted: this needs nothing of theirs to run.
local function sibling(name: string): any
	local found = script.Parent and script.Parent:FindFirstChild(name)
	if found and found:IsA("ModuleScript") then
		local ok, loaded = pcall(require, found)
		if ok and type(loaded) == "table" then
			return loaded
		end
	end
	return nil
end

local PlayerLife = {}
PlayerLife.VERSION = "the hundred-and-twentieth pass, 2026-10-22"

-- YOUR HEAD AFTER YOUR VIEW: how far the head turns and tips, how quickly it follows, past what angle behind you it
-- looks ahead again, how much of the turn the body takes standing still, and how much the camera's usual look down at
-- you is not counted (you are not looking at your feet).
local HEAD = { yaw = math.rad(70), pitch = math.rad(26), behind = math.rad(115), follow = 7, waist = 0.3, down = 0.3 }
-- STANDING ABOUT: slower than this is standing still; stood still this long, a fidget, then another every so often.
local STILL_SPEED = 0.8
local STILL_FOR = 4
local EVERY_LOW, EVERY_HIGH = 7, 14
type Fidget = { pose: string, seconds: number }
local FIDGETS: { Fidget } = {
	{ pose = "lookAround", seconds = 4 },
	{ pose = "weightShift", seconds = 3 },
	{ pose = "ponder", seconds = 3.2 },
}

type Life = { model: Model, joints: { [string]: any }, still: number, nextAt: number, fidget: Fidget?, began: number,
	rng: Random, yaw: number, pitch: number, headed: boolean }
local lives: { [Player]: Life } = {}
local others = { cinema = nil :: any, emotes = nil :: any, failed = false }

local function lifeOf(player: Player): Life?
	local model = player.Character
	if not (model and model.Parent and Poses) then
		lives[player] = nil
		return nil
	end
	local life = lives[player]
	if not life or life.model ~= model then
		life = { model = model, joints = Poses.joints(model), still = 0, nextAt = 0, fidget = nil, began = 0,
			rng = Random.new(player.UserId), yaw = 0, pitch = 0, headed = false }
		lives[player] = life
	end
	return life
end

-- Busy with something else that moves them: a line being told, an emote, a seat, the water, a ride.
local function busy(player: Player, model: Model, humanoid: Humanoid): boolean
	local at, span = model:GetAttribute("GestureAt"), model:GetAttribute("GestureFor")
	if typeof(at) == "number" and typeof(span) == "number" and workspace:GetServerTimeNow() - at < span then
		return true
	end
	local emotes = others.emotes
	if emotes and emotes.isPlaying and emotes.isPlaying(player) then
		return true
	end
	local state = humanoid:GetState()
	return humanoid.Sit or humanoid.PlatformStand or state == Enum.HumanoidStateType.Swimming
		or state == Enum.HumanoidStateType.Seated
end

-- The joints a pose (or the head) was turning, given back to the animations.
local function letGo(life: Life, pose: string?)
	local fn = if pose then Poses[pose] else nil
	local r6 = Poses.isR6(life.joints)
	for name, joint in pairs(life.joints) do
		if (fn and fn(name, 0, 1, r6)) or ((name == "Neck" or name == "Waist") and life.headed) then
			Poses.drive(joint, CFrame.identity)
		end
	end
end

-- YOUR HEAD, after the camera.
local function head(life: Life, root: BasePart, dt: number, standing: boolean)
	local camera = workspace.CurrentCamera
	local neck = life.joints.Neck
	if not (camera and neck) or Poses.isR6(life.joints) then
		return
	end
	local look = root.CFrame:VectorToObjectSpace(camera.CFrame.LookVector)
	local yaw = math.atan2(-look.X, -look.Z)
	local pitch = (math.asin(math.clamp(look.Y, -1, 1)) + HEAD.down) * 0.6
	if math.abs(yaw) > HEAD.behind then
		yaw, pitch = 0, 0
	end
	yaw = math.clamp(yaw, -HEAD.yaw, HEAD.yaw)
	pitch = math.clamp(pitch, -HEAD.pitch, HEAD.pitch)
	local k = 1 - math.exp(-dt * HEAD.follow)
	life.yaw += (yaw - life.yaw) * k
	life.pitch += (pitch - life.pitch) * k
	local share = if standing then HEAD.waist else 0
	Poses.drive(neck, CFrame.Angles(life.pitch, life.yaw * (1 - share), 0))
	local waist = life.joints.Waist
	if waist and standing then
		Poses.drive(waist, CFrame.Angles(0, life.yaw * share, 0))
	end
	life.headed = true
end

local function step(dt: number)
	if not Poses then
		return
	end
	local now = os.clock()
	local me = Players.LocalPlayer
	local cinema = others.cinema
	local inScene = cinema ~= nil and cinema.active and cinema.active()
	for _, player in ipairs(Players:GetPlayers()) do
		local life = lifeOf(player)
		if not life then
			continue
		end
		local model = life.model
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if not (humanoid and root and root:IsA("BasePart")) then
			continue
		end
		local mine = player == me
		if (mine and inScene) or busy(player, model, humanoid) then
			-- Something else has them: a fidget let go of, the head let be.
			if life.fidget or life.headed then
				letGo(life, if life.fidget then life.fidget.pose else nil)
			end
			life.fidget, life.still, life.headed = nil, 0, false
			continue
		end
		local standing = root.AssemblyLinearVelocity.Magnitude < STILL_SPEED
		life.still = if standing then life.still + dt else 0
		local fidget = life.fidget
		if fidget then
			local t = now - life.began
			if not standing or t >= fidget.seconds then
				letGo(life, fidget.pose)
				life.fidget = nil
				life.nextAt = now + life.rng:NextNumber(EVERY_LOW, EVERY_HIGH)
			else
				local fn = Poses[fidget.pose]
				local w = Poses.weight(t, fidget.seconds)
				local r6 = Poses.isR6(life.joints)
				for name, joint in pairs(life.joints) do
					local by = fn(name, t, w, r6)
					if by then
						Poses.drive(joint, by)
					end
				end
			end
		elseif life.still >= STILL_FOR and now >= life.nextAt then
			life.fidget = FIDGETS[life.rng:NextInteger(1, #FIDGETS)]
			life.began = now
		end
		if mine and not life.fidget then
			head(life, root, dt, standing)
		end
	end
	for player in pairs(lives) do
		if player.Parent ~= Players then
			lives[player] = nil
		end
	end
end

function PlayerLife.start()
	others.cinema = sibling("Cinema")
	others.emotes = sibling("EmoteService")
	-- After the animations, as every pose in this game is.
	RunService.Stepped:Connect(function(_, dt: number)
		local ok, err = pcall(step, dt)
		if not ok and not others.failed then
			others.failed = true
			warn("PlayerLife: " .. tostring(err) .. " (shown once)")
		end
	end)
	print("PlayerLife: running, " .. PlayerLife.VERSION)
end

PlayerLife.STAMP = "32becc65"
return PlayerLife
