--!strict
-- StarterPlayerScripts/Services/EmoteService.lua
-- THE EMOTES: the shop's four (Wave, Sit and squish, Stretch, Spin), played by anyone who owns them and
-- seen by everyone.
--
-- A player asks the server to play one ("Emote"); the server checks they own it and tells every client,
-- and every client poses that character itself, through the same joints the endings use (Poses: the
-- characters here are jointed with AnimationConstraints, and a joint turned on one client is seen on
-- that client only). Moving ends an emote, on every screen at once, because every screen can see the
-- character move. Sit and squish also puts a little squishy toy in the hands, squeezed on the beat.
--
-- THE PICKER: G on a keyboard, D-pad right on a controller, or Emotes in the pause menu (a phone). A small
-- card at the bottom with an emote button for each you own and a way to the shop; nothing on the screen
-- otherwise. It closes on B or Escape, or by playing one.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Poses = require(Shared:WaitForChild("Poses")) :: any
local ShopCatalog = require(Shared:WaitForChild("ShopCatalog")) :: any

local EmoteService = {}

-- AN ERROR ONCE, NOT EVERY FRAME: the step below runs every frame (or several times a second), and the same
-- failure said every frame buries everything else in Output, the paste check included.
local warnedOnce: { [string]: boolean } = {}
local function warnOnce(text: string)
	if not warnedOnce[text] then
		warnedOnce[text] = true
		warn(text .. " (shown once)")
	end
end
EmoteService.VERSION = "emotes, 2026-10-05"

-- Each emote: its pose in Poses, how long it lasts, and whether moving ends it (a spin is too quick to).
local EMOTES: { [string]: { pose: string, seconds: number, keep: boolean?, toy: boolean? } } = {
	Wave = { pose = "wave", seconds = 2.4 },
	Stretch = { pose = "stretch", seconds = 3.4 },
	Spin = { pose = "spin", seconds = 1.5, keep = true },
	SitSquish = { pose = "sitSquish", seconds = 20, toy = true },
}
local ORDER = { "Wave", "SitSquish", "Stretch", "Spin" }
local PICKER_ACTION = "EmotePicker"
local CLOSE_ACTION = "EmotePickerClose"
local MOVING = 3 -- studs a second of walking that ends an emote

type Playing = { id: string, began: number, seconds: number, model: Instance?, joints: { [string]: any }?, toy: BasePart? }
local playing: { [Player]: Playing } = {}
local stepped: RBXScriptConnection? = nil
local kit: any = nil
local ui: { [string]: any } = {}
local state = { owned = {} :: { [string]: boolean }, open = false, remote = nil :: RemoteEvent?, cinema = nil :: any }

-- ===== POSING, on every client =====

local function rest(entry: Playing)
	if entry.joints then
		for _, joint in pairs(entry.joints) do
			Poses.drive(joint, CFrame.identity)
		end
	end
	if entry.toy then
		entry.toy:Destroy()
		entry.toy = nil
	end
end

local function stopFor(player: Player)
	local entry = playing[player]
	if entry then
		rest(entry)
		playing[player] = nil
	end
end

-- THE TOY, held between the hands and squeezed on the same beat as the pose.
local function holdToy(entry: Playing, character: Model, root: BasePart, t: number)
	local right = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	local left = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	if not (right and left and right:IsA("BasePart") and left:IsA("BasePart")) then
		return
	end
	local toy = entry.toy
	if not toy then
		local made = Instance.new("Part")
		made.Name = "EmoteToy"
		made.Shape = Enum.PartType.Ball
		made.Color = Color3.fromRGB(244, 192, 209)
		made.Material = Enum.Material.SmoothPlastic
		made.Anchored = true
		made.CanCollide = false
		made.CanTouch = false
		made.CanQuery = false
		made.CastShadow = false
		made.Parent = workspace
		entry.toy = made
		toy = made
	end
	local squeeze = math.max(0, math.sin(t * 3.2)) ^ 2
	local between = (right.Position + left.Position) / 2 + root.CFrame.LookVector * 0.25
	local part = toy :: BasePart
	part.Size = Vector3.new(0.9 + 0.25 * squeeze, 0.9 - 0.35 * squeeze, 0.9 + 0.25 * squeeze)
	part.CFrame = CFrame.new(between) * (root.CFrame - root.CFrame.Position)
end

local function poseAll()
	local now = os.clock()
	for player, entry in pairs(playing) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local emote = EMOTES[entry.id]
		local t = now - entry.began
		if not (character and root and root:IsA("BasePart") and emote) or not player.Parent or t >= entry.seconds then
			stopFor(player)
			continue
		end
		-- MOVING ENDS IT, seen the same on every screen.
		local v = root.AssemblyLinearVelocity
		if not emote.keep and t > 0.4 and Vector3.new(v.X, 0, v.Z).Magnitude > MOVING then
			stopFor(player)
			continue
		end
		if entry.model ~= character then
			if entry.joints then
				rest(entry)
			end
			entry.model = character
			entry.joints = Poses.joints(character)
		end
		local joints = entry.joints
		local shape = Poses[emote.pose]
		if joints and shape then
			local r6 = Poses.isR6(joints)
			local w = Poses.weight(t, entry.seconds)
			for name, joint in pairs(joints) do
				local turn = shape(name, t, w, r6)
				if turn then
					Poses.drive(joint, turn)
				end
			end
		end
		if emote.toy then
			holdToy(entry, character :: Model, root :: BasePart, t)
		end
	end
	local hook = stepped
	if hook and next(playing) == nil then
		hook:Disconnect()
		stepped = nil
	end
end

local function begin(player: Player, id: string, lateBy: number)
	local emote = EMOTES[id]
	if not emote then
		return
	end
	stopFor(player)
	playing[player] = { id = id, began = os.clock() - math.clamp(lateBy, 0, 0.5), seconds = emote.seconds }
	if not stepped then
		stepped = RunService.Stepped:Connect(function()
			local ok, err = pcall(poseAll)
			if not ok then
				warnOnce("EmoteService: " .. tostring(err))
			end
		end)
	end
end

-- ===== PLAYING ONE =====

local function canPlay(): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid) or root.Anchored then
		return false
	end
	if humanoid.FloorMaterial == Enum.Material.Air then
		return false
	end
	local cinema = state.cinema
	return not (cinema and cinema.active and cinema.active())
end

-- Asked of the server, which tells everyone (and refuses one you do not own).
function EmoteService.play(id: string)
	EmoteService.close()
	if not EMOTES[id] or not canPlay() then
		return
	end
	local remote = state.remote
	if remote then
		remote:FireServer(id)
	end
end

-- THE SHOP'S TRY-ON: the emote on your own character, on your own screen only.
function EmoteService.preview(id: string)
	if EMOTES[id] and canPlay() then
		begin(Players.LocalPlayer, id, 0)
	end
end

-- ===== THE PICKER =====

local function build()
	if ui.screen then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Emotes"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 28
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	ui.screen = gui
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Active = true
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -100)
	panel.Size = UDim2.new(0.94, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = kit.LOOK.panel
	panel.Visible = false
	panel.Parent = gui
	kit.corner(panel, UDim.new(0, 22))
	kit.stroke(panel, kit.LOOK.edge, 4)
	local most = Instance.new("UISizeConstraint")
	most.MaxSize = Vector2.new(640, 400)
	most.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 14)
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.Parent = panel
	local column = Instance.new("UIListLayout")
	column.Padding = UDim.new(0, 10)
	column.SortOrder = Enum.SortOrder.LayoutOrder
	column.Parent = panel
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	ui.panel = panel
	ui.scale = scale

	local head = Instance.new("Frame")
	head.Name = "Head"
	head.BackgroundTransparency = 1
	head.Size = UDim2.new(1, 0, 0, kit.MIN_TOUCH)
	head.LayoutOrder = 1
	head.Parent = panel
	local title = kit.label(head, "Title", "Emotes", kit.CHUNKY, 24, kit.LOOK.pinkInk)
	title.Size = UDim2.new(1, -(kit.MIN_TOUCH + 8), 1, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, 0, 0, 0)
	close.Size = UDim2.fromOffset(kit.MIN_TOUCH, kit.MIN_TOUCH)
	close.BackgroundColor3 = kit.LOOK.pink
	close.FontFace = kit.CHUNKY
	close.TextSize = 22
	close.TextColor3 = kit.LOOK.pinkInk
	close.Text = "X"
	close.Parent = head
	kit.corner(close, UDim.new(0.5, 0))
	kit.stroke(close, kit.LOOK.pinkInk, 3)
	close.Activated:Connect(function()
		EmoteService.close()
	end)

	local grid = Instance.new("Frame")
	grid.Name = "Buttons"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 2
	grid.Parent = panel
	local cells = Instance.new("UIGridLayout")
	cells.CellSize = UDim2.fromOffset(132, kit.MIN_TOUCH + 9)
	cells.CellPadding = UDim2.fromOffset(10, 10)
	cells.HorizontalAlignment = Enum.HorizontalAlignment.Center
	cells.SortOrder = Enum.SortOrder.LayoutOrder
	cells.Parent = grid
	ui.grid = grid
end

-- The buttons, for what is owned now: one per emote, and the way to the shop.
local function fill()
	local grid = ui.grid
	for _, old in ipairs(grid:GetChildren()) do
		if old:IsA("GuiObject") then
			old:Destroy()
		end
	end
	local first: GuiObject? = nil
	for order, id in ipairs(ORDER) do
		if state.owned[id] then
			local item = ShopCatalog.get(id)
			local holder, face, content = kit.squishy(grid, id, item and item.colour or kit.LOOK.tile, item and item.accent or kit.LOOK.edge)
			holder.LayoutOrder = order
			local words = kit.buttonWords(content, item and item.name or id, item and item.accent or kit.LOOK.ink, 18)
			words.TextScaled = true
			words.AutomaticSize = Enum.AutomaticSize.None
			words.Size = UDim2.new(1, -14, 1, -12)
			face.Activated:Connect(function()
				kit.sound("buttonClick", 0.5)
				EmoteService.play(id)
			end)
			first = first or face
		end
	end
	local holder, face, content = kit.squishy(grid, "GetMore", kit.LOOK.token, kit.LOOK.tokenEdge)
	holder.LayoutOrder = 99
	local words = kit.buttonWords(content, if first then "More" else "Get emotes", kit.LOOK.tokenInk, 18)
	words.TextScaled = true
	words.AutomaticSize = Enum.AutomaticSize.None
	words.Size = UDim2.new(1, -14, 1, -12)
	face.Activated:Connect(function()
		EmoteService.close()
		local module = script.Parent and script.Parent:FindFirstChild("ShopService")
		if module and module:IsA("ModuleScript") then
			pcall(function()
				(require(module) :: any).open("Emotes")
			end)
		end
	end)
	ui.first = first or face
end

function EmoteService.open()
	if not kit then
		return
	end
	build()
	fill()
	state.open = true
	ui.screen.Enabled = true
	ui.panel.Visible = true
	ui.scale.Scale = 0.85
	TweenService:Create(ui.scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	kit.sound("buttonClick", 0.5)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			EmoteService.close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 15, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	if kit.usingPad() and ui.first then
		GuiService.SelectedObject = ui.first
	end
end

function EmoteService.close()
	if not state.open then
		return
	end
	state.open = false
	ContextActionService:UnbindAction(CLOSE_ACTION)
	if ui.panel then
		ui.panel.Visible = false
		ui.screen.Enabled = false
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(ui.panel) then
			GuiService.SelectedObject = nil
		end
	end
end

function EmoteService.toggle()
	if state.open then
		EmoteService.close()
	else
		EmoteService.open()
	end
end

-- ===== STARTING =====

local function accept(data: any)
	if type(data) == "table" and type(data.owned) == "table" then
		state.owned = data.owned
		if state.open then
			fill()
		end
	end
end

function EmoteService.start()
	local services = script.Parent
	local shopModule = services and services:WaitForChild("ShopService", 20)
	if shopModule and shopModule:IsA("ModuleScript") then
		kit = (require(shopModule) :: any).kit
	end
	local cinemaModule = services and services:FindFirstChild("Cinema")
	if cinemaModule and cinemaModule:IsA("ModuleScript") then
		local ok, loaded = pcall(require, cinemaModule)
		if ok then
			state.cinema = loaded
		end
	end
	local events = ReplicatedStorage:WaitForChild("RemoteEvents")
	local functions = ReplicatedStorage:WaitForChild("RemoteFunctions")
	local remote = events:WaitForChild("Emote", 20)
	local update = events:WaitForChild("ShopUpdate", 20)
	local ask = functions:WaitForChild("ShopState", 20)
	if not (remote and remote:IsA("RemoteEvent") and kit) then
		warn("EmoteService: the Emote remote or ShopService's kit is missing. Paste src/Server/Bootstrap.server.lua "
			.. "and src/Client/Services/ShopService.lua.")
		return
	end
	state.remote = remote
	remote.OnClientEvent:Connect(function(player: any, id: any, at: any)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or typeof(id) ~= "string" then
			return
		end
		if id == "stop" then
			stopFor(player)
		else
			local late = if typeof(at) == "number" then workspace:GetServerTimeNow() - at else 0
			begin(player, id, late)
		end
	end)
	if update and update:IsA("RemoteEvent") then
		update.OnClientEvent:Connect(accept)
	end
	if ask and ask:IsA("RemoteFunction") then
		task.spawn(function()
			local ok, data = pcall(function()
				return ask:InvokeServer()
			end)
			if ok then
				accept(data)
			end
		end)
	end
	-- G, or D-pad right on a controller: the picker. Not while typing (ContextActionService sees to it).
	ContextActionService:BindAction(PICKER_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			EmoteService.toggle()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.G, Enum.KeyCode.DPadRight)
	-- YOUR OWN EMOTE ends the moment you move, and says so, so every screen stops it together.
	RunService.Heartbeat:Connect(function()
		local mine = playing[Players.LocalPlayer]
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local emote = mine and EMOTES[mine.id]
		if mine and emote and not emote.keep and humanoid and humanoid.MoveDirection.Magnitude > 0.1
			and os.clock() - mine.began > 0.2 then
			stopFor(Players.LocalPlayer)
			if state.remote then
				state.remote:FireServer("stop")
			end
		end
	end)
	print("EmoteService: running, " .. EmoteService.VERSION)
end

EmoteService.STAMP = "148273ad"
return EmoteService
