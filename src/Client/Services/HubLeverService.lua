--!strict
-- The lobby's mode lever, built on the client so it can move for one player only.
--
-- === Why this exists at all ===
--
-- The leaderboard shows chill times or hardcore times, and which one is a per-player choice:
-- two people at the same board should be able to read different columns. The board itself was
-- straightforward -- a SurfaceGui in each PlayerGui, adorned to the one board part.
--
-- The lever was not. A switch is only a switch because it TRAVELS: colour alone is a status
-- light, and the movement is what tells you that you operated something. But a Part has one
-- CFrame, so a shared lever cannot be thrown two ways at once, and an indicator floating in
-- front of a static head is exactly the status light we were trying not to build.
--
-- Parts parented to workspace.CurrentCamera are never replicated and never serialised: they
-- render in the world at their own CFrame and exist only on this client. That is the whole
-- trick. The server owns the base, the socket and the ClickDetector (it has to -- only the
-- server knows who clicked); this file owns the arm that swings.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local HubLeverService = {}

local CHILL = Color3.fromRGB(120, 196, 236)
local HARDCORE = Color3.fromRGB(232, 74, 68)

-- Degrees off vertical. Hardcore leans forward and chill sits back, so the two states differ
-- in silhouette and survive being glanced at from across the room.
local CHILL_LEAN = math.rad(-16)
local HARDCORE_LEAN = math.rad(30)

-- The handle is a mesh, and it degrades to primitives rather than to nothing.
--
-- Hub_LeverHandle is a knurled grip on a tapered shaft: the flats are what keep the swing
-- legible when the lever is small on screen, because a smooth cylinder rotating about its own
-- axis looks static. But this file runs on the client and the client cannot import an asset,
-- so if the mesh is missing it falls back to the stem-and-ball it replaced. A lever that is
-- plain is a great deal better than a lever that is absent.
local HANDLE_MESH = "Hub_LeverHandle"

local mode = "chill"
local stem: Part? = nil
local head: Part? = nil
local glow: PointLight? = nil
local caption: TextLabel? = nil
local pivotCFrame: CFrame? = nil
-- Where the knob sits along the arm, when the mesh set it. nil means the fallback geometry.
local headOffset: number? = nil

-- Rebuilt from the pivot every time rather than accumulated, for the same reason the statue
-- poses are: multiplying into the live CFrame compounds, and four throws would put the head
-- somewhere over the pool.
local function armCFrames(lean: number): (CFrame, CFrame)
	local base = pivotCFrame or CFrame.new()
	local hinge = base * CFrame.Angles(lean, 0, 0)
	-- The mesh is modelled with its base at the hinge and its knob 3.16 studs up, so it is
	-- centred 1.58 along the arm. The fallback ball keeps the old 3.8, which is where a ball
	-- on a stick has to sit to look like a lever.
	return hinge * CFrame.new(0, 1.58, 0), hinge * CFrame.new(0, 3.8, 0)
end

local function paint(instant: boolean)
	local stemPart, headPart = stem, head
	if not (stemPart and headPart) then
		return
	end
	local hardcore = mode == "hardcore"
	local colour = if hardcore then HARDCORE else CHILL
	local lean = if hardcore then HARDCORE_LEAN else CHILL_LEAN
	local stemAt, headAt = armCFrames(lean)
	if headOffset then
		headAt = CFrame.new((pivotCFrame or CFrame.new()).Position)
			* CFrame.Angles(lean, 0, 0)
			* CFrame.new(0, headOffset, 0)
	end

	headPart.Color = colour
	if glow then
		glow.Color = colour
		glow.Brightness = if hardcore then 5 else 1.8
	end
	if caption then
		caption.Text = if hardcore then "HARDCORE times" else "CHILL times"
		caption.TextColor3 = colour
	end

	if instant then
		stemPart.CFrame, headPart.CFrame = stemAt, headAt
		return
	end
	-- Back-eased, so the head overshoots slightly and settles. A linear slide reads as an
	-- object being moved; the overshoot reads as a switch being thrown.
	local info = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(stemPart, info, { CFrame = stemAt }):Play()
	TweenService:Create(headPart, info, { CFrame = headAt }):Play()
end

function HubLeverService.setMode(next: string)
	if next ~= "chill" and next ~= "hardcore" then
		return
	end
	local changed = next ~= mode
	mode = next
	paint(not changed)
end

local function build(pivot: BasePart, toggle: RemoteEvent)
	-- CurrentCamera, not Workspace. This is the only parent whose children stay on this
	-- client; putting these in Workspace would replicate them straight back to everyone and
	-- undo the entire point.
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	pivotCFrame = CFrame.new(pivot.Position)

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local meshes = assets and assets:FindFirstChild("TileMeshes")
	local template = meshes and meshes:FindFirstChild(HANDLE_MESH)
	local source = if template and template:IsA("BasePart")
		then template
		else (if template then template:FindFirstChildWhichIsA("BasePart", true) else nil)

	local made: Part
	if source then
		made = source:Clone() :: any
		made.Name = "BoardSwitchStem"
		made.Material = Enum.Material.Metal
		made.Color = Color3.fromRGB(96, 92, 108)
	else
		made = Instance.new("Part")
		made.Name = "BoardSwitchStem"
		made.Size = Vector3.new(0.5, 3.2, 0.5)
		made.Material = Enum.Material.Metal
		made.Color = Color3.fromRGB(120, 118, 132)
	end
	made.Anchored = true
	made.CanCollide = false
	made.CanQuery = true
	made.Parent = camera
	stem = made

	-- The head is the lit knob at the top of the handle. With the mesh it is a small glowing
	-- cap sitting inside the modelled knob; without it, it is the whole switch.
	local ball = Instance.new("Part")
	ball.Name = "BoardSwitchHead"
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = true
	ball.Shape = Enum.PartType.Ball
	ball.Size = if source then Vector3.new(1.0, 1.0, 1.0) else Vector3.new(2.1, 2.1, 2.1)
	ball.Material = Enum.Material.Neon
	ball.Parent = camera
	head = ball
	headOffset = if source then 2.9 else nil

	local light = Instance.new("PointLight")
	light.Range = 14
	light.Shadows = false
	light.Parent = ball
	glow = light

	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.new(7, 0, 1.6, 0)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	sign.MaxDistance = 60
	sign.AlwaysOnTop = true
	sign.Parent = ball

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.FontFace = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.4
	label.Parent = sign
	caption = label

	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 18
	cap.Parent = label

	-- A ClickDetector on a camera-parented part fires on this client only, which is fine:
	-- it asks the server to flip the mode, and the server is what decides. The base in the
	-- room stays clickable too, so the control works whether you aim at the head or the socket.
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 40
	click.Parent = ball
	click.MouseClick:Connect(function()
		toggle:FireServer()
	end)

	paint(true)
end

-- WAITS FOR THE ROOM, and gives up rather than yielding forever.
--
-- WaitForChild with no timeout is how a client script becomes a client script that never
-- finishes starting. If the hub failed to build, the lever simply does not appear and every
-- other client service still runs.
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	if not remotes then
		return
	end
	local toggle = remotes:WaitForChild("HubBoardToggle", 20)
	local changed = remotes:WaitForChild("HubBoardMode", 20)
	if not (toggle and toggle:IsA("RemoteEvent") and changed and changed:IsA("RemoteEvent")) then
		return
	end

	changed.OnClientEvent:Connect(function(next: string)
		HubLeverService.setMode(next)
	end)

	-- THE ROOM COMES AND GOES NOW. It is reparented out of the workspace for the duration of
	-- every run, so a one-shot WaitForChild is only correct for a player who happens to join
	-- between runs -- anyone arriving mid-run would wait thirty seconds, find nothing, and
	-- never get a lever for the rest of the session.
	--
	-- Watching ChildAdded costs one connection and covers every case: joining mid-run, and
	-- the room returning at the end of one.
	local function attach()
		local hub = Workspace:FindFirstChild("Hub")
		local pivot = hub and hub:FindFirstChild("BoardSwitchPivot")
		if pivot and pivot:IsA("BasePart") and (not stem or stem.Parent == nil) then
			build(pivot, toggle :: RemoteEvent)
			paint(true)
		end
	end

	attach()
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Hub" then
			-- One frame for the room's own children to replicate before looking inside it.
			task.wait(0.2)
			attach()
		end
	end)

	-- The camera is rebuilt on respawn and takes the arm with it, so it is rebuilt too. This
	-- is the cost of using CurrentCamera as a private parent and it is a small one.
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		attach()
	end)
end)

return HubLeverService
