--!strict
-- StarterPlayerScripts/Services/ViewModeService.lua
-- THE VIEW AND THE CURSOR: third person, first person if you ask for it, and Ctrl.
--
-- === Third person, always, unless you go and look through the viewer ===
--
-- This is a game about seeing your feet land on things, so it is played in third person, and in a run
-- the camera is held behind you at one distance (THIRD_DISTANCE): no zooming in until you lose sight of
-- yourself. In the lobby it zooms between LOBBY_NEAR and LOBBY_FAR: never so near that a scroll slips
-- you into first person by accident.
--
-- COMING BACK FROM FIRST PERSON LANDS YOU IN A PROPER THIRD PERSON VIEW. Letting go of the lock left the
-- camera where first person had it, inside your head, until you scrolled out by hand. Now it is put
-- behind you and over your shoulder at THIRD_DISTANCE, at once, and the lobby's range given back after.
--
-- First person was asked for as an option and then asked to be kept out of the interface: nothing on
-- the screen for it, nothing in anybody's way. So it lives in the room. The SEASIDE VIEWER on the
-- lobby's terrace (HubService builds it) has a prompt, "Look through": use it and your view is first
-- person at once, in the lobby and in every run after, until you use it again. The choice is kept on
-- the player as ViewMode ("third" or "first") for anything else that wants it.
--
-- === Ctrl: the cursor locked or free ===
--
-- As in most Roblox games that have it (Squid Game's among them), Ctrl toggles the cursor:
--
--   THIRD PERSON   locked: the cursor is held in the middle, the camera turns as the mouse moves, and
--                  you face where you look, the camera a little over your right shoulder. Free: the
--                  ordinary cursor, and right-drag turns the camera. Free to begin with.
--   FIRST PERSON   the cursor is locked in first person anyway; Ctrl frees it, to click the journal or
--                  the pause tab, and Ctrl locks it again.
--
-- A word at the bottom of the screen says which, for a moment, and goes. Nothing is done to the camera
-- while a scene has it (Cinema), and you are never turned while you ride, sit or are carried.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local ViewModeService = {}
ViewModeService.VERSION = "nineteenth pass, 2026-09-30"

-- How far behind you the camera is held in a run, and how far over your shoulder when the cursor is
-- locked in third person.
local THIRD_DISTANCE = 14
local LOBBY_NEAR, LOBBY_FAR = 6, 36
local SHOULDER = Vector3.new(1.75, 0.2, 0)
local STEP = "ViewModeCursor"

local Cinema: any = (function()
	local found = script.Parent and script.Parent:FindFirstChild("Cinema")
	if found and found:IsA("ModuleScript") then
		local ok, module = pcall(require, found)
		if ok then
			return module
		end
	end
	return nil
end)()

local state = {
	view = "third",
	locked = false, -- third person: the cursor held in the middle
	free = false, -- first person: the cursor let go
	turned = false, -- whether AutoRotate is ours to give back
	offset = Vector3.zero,
}
local ui: { [string]: any } = {}

local function inRun(): boolean
	return Players.LocalPlayer:GetAttribute("InLevel") ~= nil
end

-- The camera as the view and the place say it should be.
local function apply()
	local player = Players.LocalPlayer
	player:SetAttribute("ViewMode", state.view)
	if state.view == "first" then
		-- The near end first: a far end set under the near one would be clamped back up to it.
		player.CameraMinZoomDistance = 0.5
		player.CameraMaxZoomDistance = 0.5
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	elseif inRun() then
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = THIRD_DISTANCE
		player.CameraMinZoomDistance = THIRD_DISTANCE
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMaxZoomDistance = LOBBY_FAR
		player.CameraMinZoomDistance = LOBBY_NEAR
	end
	-- The viewer says what it will do next, on this screen.
	local prompt = ui.prompt
	if prompt and prompt.Parent then
		prompt.ActionText = if state.view == "first" then "Step back" else "Look through"
		prompt.ObjectText = if state.view == "first" then "Third person" else "First person"
	end
end

-- A word at the bottom of the screen for a moment: which way the cursor is now.
local function say(text: string)
	local label: TextLabel? = ui.word
	if not label then
		return
	end
	label.Text = text
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.5
	ui.said = (ui.said or 0) + 1
	local mine = ui.said
	task.delay(1.4, function()
		if ui.said == mine then
			TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

-- Straight into a good third person view: the zoom held at THIRD_DISTANCE for a moment (the camera
-- goes there), the camera put behind you and a little above, and then the place's own range given back
-- (the camera stays where it was put).
local function settleThird()
	local player = Players.LocalPlayer
	player.CameraMode = Enum.CameraMode.Classic
	player.CameraMaxZoomDistance = THIRD_DISTANCE
	player.CameraMinZoomDistance = THIRD_DISTANCE
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if camera and root and root:IsA("BasePart") then
		local flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		flat = if flat.Magnitude > 0.05 then flat.Unit else Vector3.new(0, 0, -1)
		local at = root.Position + Vector3.new(0, 1.5, 0)
		camera.CFrame = CFrame.lookAt(at - flat * THIRD_DISTANCE + Vector3.new(0, THIRD_DISTANCE * 0.35, 0), at)
	end
	task.delay(0.15, function()
		if state.view == "third" then
			apply()
		end
	end)
end

function ViewModeService.setView(view: string)
	if view ~= "first" and view ~= "third" then
		return
	end
	local was = state.view
	state.view = view
	state.free = false
	if view == "third" and was == "first" then
		settleThird()
	else
		apply()
	end
	say(if view == "first" then "First person. Ctrl frees the cursor." else "Third person.")
end

function ViewModeService.view(): string
	return state.view
end

local function toggleCursor()
	if state.view == "first" then
		state.free = not state.free
		say(if state.free then "Cursor free (Ctrl)" else "Cursor locked (Ctrl)")
	else
		state.locked = not state.locked
		say(if state.locked then "Cursor locked (Ctrl)" else "Cursor free (Ctrl)")
	end
end

-- Is a menu open that wants the cursor (the journal, the pause menu)? Then it is free, whatever Ctrl
-- says, and locked again when the menu shuts.
local function menuOpen(): boolean
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return false
	end
	local journal = playerGui:FindFirstChild("Journal")
	local book = journal and journal:FindFirstChild("Book")
	local pause = playerGui:FindFirstChild("PauseMenu")
	local card = pause and pause:FindFirstChild("Card")
	return (book ~= nil and book:IsA("GuiObject") and book.Visible) or (card ~= nil and card:IsA("GuiObject") and card.Visible)
end

-- Every frame, after the camera: the cursor, the shoulder, and which way you face.
local function step(dt: number)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local scene = Cinema and Cinema.active()
	local menu = menuOpen()
	-- First person: the modal button frees the cursor while it is shown (and always while a menu is up).
	local modal: TextButton? = ui.modal
	if modal then
		modal.Visible = state.view == "first" and (state.free or menu) and not scene
	end
	local lockedNow = state.view == "third" and state.locked and not scene and not menu
	if lockedNow then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	elseif state.view == "third" and ui.wasLocked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	ui.wasLocked = lockedNow
	if not (humanoid and root and root:IsA("BasePart")) then
		return
	end
	-- Over the shoulder while locked, eased in and out.
	local want = if lockedNow then SHOULDER else Vector3.zero
	state.offset = state.offset:Lerp(want, 1 - math.exp(-10 * dt))
	humanoid.CameraOffset = state.offset
	-- Facing where you look: never while you ride, sit, are carried, or are down.
	local free = not humanoid.Sit and not humanoid.PlatformStand and not root.Anchored and humanoid.Health > 0
	if lockedNow and free then
		local look = workspace.CurrentCamera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.05 then
			humanoid.AutoRotate = false
			state.turned = true
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		end
	elseif state.turned then
		state.turned = false
		humanoid.AutoRotate = true
	end
end

local function build()
	local screen = Instance.new("ScreenGui")
	screen.Name = "ViewMode"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 18
	screen.IgnoreGuiInset = true
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local word = Instance.new("TextLabel")
	word.Name = "Word"
	word.AnchorPoint = Vector2.new(0.5, 1)
	word.Position = UDim2.new(0.5, 0, 1, -64)
	word.Size = UDim2.fromOffset(360, 22)
	word.BackgroundTransparency = 1
	word.FontFace = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)
	word.TextSize = 16
	word.TextColor3 = Color3.fromRGB(246, 240, 226)
	word.TextStrokeColor3 = Color3.fromRGB(12, 12, 16)
	word.TextTransparency = 1
	word.TextStrokeTransparency = 1
	word.Text = ""
	word.Parent = screen
	ui.word = word
	-- Nothing to see: a button the size of a pixel, whose only job is to free the cursor in first
	-- person while it is shown (Modal).
	local modal = Instance.new("TextButton")
	modal.Name = "FreeCursor"
	modal.Size = UDim2.fromOffset(1, 1)
	modal.BackgroundTransparency = 1
	modal.Text = ""
	modal.Modal = true
	modal.Visible = false
	modal.Parent = screen
	ui.modal = modal
end

-- The viewer in the lobby: found when it streams in, and its prompt heard on this client.
local function findViewer()
	for _, item in ipairs(workspace:GetDescendants()) do
		if item:IsA("ProximityPrompt") and item.Name == "ViewScopePrompt" then
			ui.prompt = item
			apply()
			return
		end
	end
end

function ViewModeService.start()
	build()
	apply()
	findViewer()
	workspace.DescendantAdded:Connect(function(item: Instance)
		if item:IsA("ProximityPrompt") and item.Name == "ViewScopePrompt" then
			ui.prompt = item
			task.defer(apply)
		end
	end)
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if prompt.Name == "ViewScopePrompt" and who == Players.LocalPlayer then
			ViewModeService.setView(if state.view == "first" then "third" else "first")
		end
	end)
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("InLevel"):Connect(apply)
	-- A new character comes with the camera's defaults on some setups: the view is put back on it.
	player.CharacterAdded:Connect(function()
		state.turned = false
		task.defer(apply)
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
			toggleCursor()
		end
	end)
	RunService:BindToRenderStep(STEP, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("ViewModeService: " .. tostring(err))
		end
	end)
	print("ViewModeService: running, " .. ViewModeService.VERSION)
end

return ViewModeService
