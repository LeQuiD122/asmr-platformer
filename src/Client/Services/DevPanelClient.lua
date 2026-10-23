--!strict
-- StarterPlayerScripts/Services/DevPanelClient.lua
-- STUDIO ONLY: THE TEST PANEL. A few buttons for what is awkward to reach by playing: tokens to spend, a
-- second chance to use, a clean slate, the first visit again, the way to the shop, the squish room. F8 opens
-- it, or the small DEV tab (for the Device Emulator's touch screens). In the live game none of it is built,
-- and the server neither makes its remote nor listens.

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DevPanelClient = {}
DevPanelClient.VERSION = "the test panel, 2026-10-06"

local BUTTONS = {
	{ action = "tokens", text = "+500 tokens" },
	{ action = "chance", text = "+1 second chance" },
	{ action = "clear", text = "Clear purchases" },
	{ action = "firstVisit", text = "First visit again" },
	{ action = "shopIntro", text = "Way to the shop" },
	{ action = "favourite", text = "Favourite ask again" },
	{ action = "keepsakes", text = "All keepsakes" },
	{ action = "journal", text = "Clear journal (rejoin)" },
	{ action = "selftest", text = "Self-test" },
	{ action = "vip", text = "VIP on/off" },
	{ action = "levels", text = "Levels open/locked" },
	{ action = "nearEnd", text = "Near the end" },
	{ action = "storyStart", text = "Story from the start" },
	{ action = "backRooms", text = "Back rooms" },
	{ action = "dailyNext", text = "Daily: next day" },
	{ action = "friend", text = "Friend in runs on/off" },
	{ action = "challengesNew", text = "Challenges: new three" },
	{ action = "starter", text = "Starter pack on/off" },
	{ action = "materials", text = "Materials: 26 / none" },
	{ action = "codesForget", text = "Codes: post again" },
	{ action = "squish", text = "Squish room / lobby" },
	{ action = "storyKnown", text = "Know the whole story" },
	{ action = "trueEnding", text = "True ending on/off" },
}

local ui: { [string]: any } = {}
local kit: any = nil
local remote: RemoteEvent? = nil

local function close()
	if ui.panel then
		ui.panel.Visible = false
		ContextActionService:UnbindAction("DevPanelClose")
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(ui.panel) then
			GuiService.SelectedObject = nil
		end
	end
end

local function open()
	ui.panel.Visible = true
	ContextActionService:BindActionAtPriority("DevPanelClose", function(_, state)
		if state == Enum.UserInputState.Begin then
			close()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 30, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	if kit.usingPad() and ui.first then
		GuiService.SelectedObject = ui.first
	end
end

local function toggle()
	if ui.panel.Visible then
		close()
	else
		open()
	end
end

-- ===== THE SELF-TEST'S CLIENT HALF (the same button as the server's) =====
--
-- The screens a player opens, opened and closed for real on this screen, each step said pass or FAIL in Output:
-- the shop, the journal (at the keepsakes) and the emote picker. A screen that throws, or does not show, or will
-- not go away, would otherwise be found only by pressing it.
local function clientSelfTest()
	local results: { { label: string, ok: boolean, detail: string? } } = {}
	local function check(label: string, ok: boolean, detail: string?)
		table.insert(results, { label = label, ok = ok, detail = detail })
	end
	local function service(name: string): any
		local module = script.Parent and script.Parent:FindFirstChild(name)
		if not (module and module:IsA("ModuleScript")) then
			return nil
		end
		local ok, loaded = pcall(require, module)
		return if ok and type(loaded) == "table" then loaded else nil
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- THE CURSOR, free while a screen is up (ViewModeService.menuOpen; the death card was missed once). Only to be
	-- seen if it is locked to start with, which is read with this panel closed (it frees the cursor itself).
	local UserInputService = game:GetService("UserInputService")
	close()
	task.wait(0.3)
	local locked = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
	local function cursorFree(label: string)
		if not locked then
			check(label .. ": the cursor (free already: Ctrl, or first person)", true)
			return
		end
		task.wait(0.2)
		check(label .. ": the cursor free to press it", UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter)
	end
	-- EVERY SCREEN, MEASURED ON THIS DEVICE (the hundred-and-second pass: "verify that every device can see everything
	-- and that everything scales properly"). With each screen up, every element of it that shows is looked at as
	-- Roblox laid it out here: one hanging off an edge of the screen (an element wholly off it is parked there on
	-- purpose, and passed over, as is anything in a scrolling list), words that do not fit their box (TextFits), and on
	-- a touch screen a button under a thumb (the stick's corner and the jump button's). Run it in Studio's Device
	-- Emulator on a phone, a tablet and a television as well as here, and each says how this screen does there.
	local camera = workspace.CurrentCamera
	local function visibleNow(item: GuiObject): boolean
		local at: Instance? = item
		while at and not at:IsA("ScreenGui") do
			if at:IsA("GuiObject") and not at.Visible then
				return false
			end
			if at ~= item and (at:IsA("ScrollingFrame") or (at:IsA("GuiObject") and at.ClipsDescendants)) then
				return false
			end
			at = at.Parent
		end
		return true
	end
	local function onScreen(label: string)
		local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
		local touch = UserInputService.TouchEnabled
		local off, cramped, thumbs, measured = {}, {}, {}, 0
		for _, gui in ipairs(playerGui:GetChildren()) do
			if gui:IsA("ScreenGui") and gui.Enabled and gui.Name ~= "DevPanel" then
				local inset = if gui.IgnoreGuiInset then Vector2.zero else GuiService:GetGuiInset()
				for _, item in ipairs(gui:GetDescendants()) do
					if item:IsA("GuiObject") and visibleNow(item) and item.AbsoluteSize.X > 1 and item.AbsoluteSize.Y > 1 then
						local at, size = item.AbsolutePosition + inset, item.AbsoluteSize
						local right, bottom = at.X + size.X, at.Y + size.Y
						local outside = right <= 0 or bottom <= 0 or at.X >= view.X or at.Y >= view.Y
						if not outside then
							measured += 1
							if at.X < -2 or at.Y < -2 or right > view.X + 2 or bottom > view.Y + 2 then
								table.insert(off, item:GetFullName())
							end
							if (item:IsA("TextLabel") or item:IsA("TextButton")) and item.Text ~= ""
								and item.TextTransparency < 1 and not item.TextFits then
								table.insert(cramped, item:GetFullName())
							end
							if touch and item:IsA("GuiButton") and item.BackgroundTransparency < 1 then
								local stick = at.X < 280 and bottom > view.Y - 230
								local jump = right > view.X - 230 and bottom > view.Y - 230
								if stick or jump then
									table.insert(thumbs, item:GetFullName())
								end
							end
						end
					end
				end
			end
		end
		local function some(list: { string }): string
			local shownList = {}
			for k = 1, math.min(3, #list) do
				table.insert(shownList, list[k])
			end
			return table.concat(shownList, ", ") .. (if #list > 3 then (" and %d more"):format(#list - 3) else "")
		end
		local where = ("%d by %d"):format(math.floor(view.X), math.floor(view.Y))
		check(("%s: all on the screen (%s, %d things)"):format(label, where, measured), #off == 0,
			if #off > 0 then "off an edge: " .. some(off) else nil)
		check(("%s: every word fits its box"):format(label), #cramped == 0,
			if #cramped > 0 then "does not fit: " .. some(cramped) else nil)
		if touch then
			check(("%s: no button under a thumb"):format(label), #thumbs == 0,
				if #thumbs > 0 then "under the stick or the jump button: " .. some(thumbs) else nil)
		end
	end
	onScreen("the screen as it is")
	local shop = service("ShopService")
	if shop and shop.open and shop.close and shop.isOpen then
		local opened, err = pcall(shop.open)
		task.wait(0.5)
		check("the shop opens", opened and shop.isOpen() == true, if opened then nil else tostring(err))
		onScreen("the shop")
		cursorFree("the shop")
		local closed, closeErr = pcall(shop.close)
		task.wait(0.5)
		check("the shop closes", closed and shop.isOpen() == false, if closed then nil else tostring(closeErr))
	else
		check("the shop is there", false, "no ShopService with open, close and isOpen")
	end
	local journal = service("JournalService")
	if journal and journal.open and journal.isOpen and journal.toggle then
		local opened, err = pcall(journal.open, "keepsake")
		task.wait(0.5)
		check("the journal opens at the keepsakes", opened and journal.isOpen() == true, if opened then nil else tostring(err))
		onScreen("the journal")
		cursorFree("the journal")
		local closed, closeErr = pcall(journal.toggle)
		task.wait(0.5)
		check("the journal closes", closed and journal.isOpen() == false, if closed then nil else tostring(closeErr))
	else
		check("the journal is there", false, "no JournalService with open, isOpen and toggle")
	end
	local emotes = service("EmoteService")
	if emotes and emotes.open and emotes.close then
		local opened, err = pcall(emotes.open)
		task.wait(0.5)
		local screen = playerGui:FindFirstChild("Emotes")
		local panel = screen and screen:FindFirstChild("Panel")
		check("the emote picker opens", opened and panel ~= nil and panel:IsA("GuiObject") and panel.Visible,
			if opened then nil else tostring(err))
		onScreen("the emote picker")
		cursorFree("the emote picker")
		local closed, closeErr = pcall(emotes.close)
		task.wait(0.3)
		check("the emote picker closes", closed and panel ~= nil and panel:IsA("GuiObject") and not panel.Visible,
			if closed then nil else tostring(closeErr))
	else
		check("the emote picker is there", false, "no EmoteService with open and close")
	end
	local pause = service("PauseMenuService")
	if pause and pause.setOpen and pause.isOpen then
		local opened, err = pcall(pause.setOpen, true)
		task.wait(0.5)
		local pauseGui = playerGui:FindFirstChild("PauseMenu")
		local card = pauseGui and pauseGui:FindFirstChild("Card")
		check("the pause menu opens", opened and pause.isOpen() == true and card ~= nil and card:IsA("GuiObject") and card.Visible,
			if opened then nil else tostring(err))
		onScreen("the pause menu")
		cursorFree("the pause menu")
		local closed, closeErr = pcall(pause.setOpen, false)
		task.wait(0.5)
		check("the pause menu closes", closed and pause.isOpen() == false and card ~= nil and card:IsA("GuiObject")
			and not card.Visible, if closed then nil else tostring(closeErr))
	else
		check("the pause menu is there", false, "no PauseMenuService with setOpen and isOpen")
	end
	-- THE SERVER ANSWERS THIS SCREEN through the remotes the game uses: the save, the journal and the leaderboard.
	local functions = ReplicatedStorage:FindFirstChild("RemoteFunctions")
	for _, ask in ipairs({
		{ name = "ShopState", label = "the save answers", ready = true },
		{ name = "JournalState", label = "the journal answers", ready = true },
		{ name = "RequestLeaderboardData", label = "the leaderboard answers", ready = false },
	}) do
		local remote = functions and functions:FindFirstChild(ask.name)
		if remote and remote:IsA("RemoteFunction") then
			local asked, answer = pcall(function()
				return remote:InvokeServer()
			end)
			local good = asked and type(answer) == "table" and (not ask.ready or answer.ready == true)
			check(ask.label, good, if asked then nil else tostring(answer))
		else
			check(ask.label, false, "no RemoteFunctions." .. ask.name)
		end
	end
	-- THE DEATH CARD: shown (without a second chance), its choices after their three seconds, then put away.
	local death = service("DeathService")
	if death and death.show and death.hide then
		local shown, err = pcall(death.show, false)
		task.wait(3.6)
		local cardGui = playerGui:FindFirstChild("DeathCard")
		local row = cardGui and cardGui:FindFirstChild("Choices", true)
		check("the death card shows its choices", shown and cardGui ~= nil and cardGui:IsA("ScreenGui") and cardGui.Enabled
			and row ~= nil and row:IsA("GuiObject") and row.Visible, if shown then nil else tostring(err))
		onScreen("the death card")
		cursorFree("the death card")
		local hidden, hideErr = pcall(death.hide)
		task.wait(0.3)
		check("the death card goes", hidden and cardGui ~= nil and cardGui:IsA("ScreenGui") and not cardGui.Enabled,
			if hidden then nil else tostring(hideErr))
	else
		check("the death card is there", false, "no DeathService with show and hide")
	end
	-- THE LOBBY'S LEVEL PADS as this screen sees them (levels open in order): City Shore open; a locked pad boarded up
	-- and saying so, an open one with no boards. Only from the lobby (the room is away during a run).
	local hub = workspace:FindFirstChild("Hub")
	local pads = 0
	for _, pad in ipairs(if hub then hub:GetChildren() else {}) do
		if pad:IsA("BasePart") and pad.Name:sub(1, 9) == "LevelPad_" then
			pads += 1
			local locked = pad:GetAttribute("Locked") == true
			local boards, up = 0, 0
			for _, board in ipairs(pad:GetChildren()) do
				if board.Name == "LockBoard" and board:IsA("BasePart") then
					boards += 1
					if board.Transparency < 0.5 then
						up += 1
					end
				end
			end
			local sign = pad:FindFirstChild("Detail", true)
			local says = sign ~= nil and sign:IsA("TextLabel") and sign.Text:sub(1, 6) == "Locked"
			local wanted = if locked then 2 else 0
			check(("%s %s"):format(pad.Name, if locked then "locked: boarded up, saying so" else "open: no boards"),
				boards == 2 and up == wanted and says == locked, ("%d boards, %d up"):format(boards, up))
			if pad.Name == "LevelPad_1" then
				check("City Shore is open", not locked)
			end
		end
	end
	check("the lobby's level pads", hub == nil or pads > 0, if hub then nil else "not in the lobby, so not looked at")
	-- THE STORY PAD (HubService.STORY_ID, 100), always open.
	local storyPad = hub and hub:FindFirstChild("LevelPad_100")
	check("the Story pad, open", hub == nil or (storyPad ~= nil and storyPad:GetAttribute("Locked") ~= true),
		if hub then nil else "not in the lobby, so not looked at")
	-- THE VIP TAG over your own head: there with VIP (the panel's VIP on/off), not without; put away on a level.
	local me = Players.LocalPlayer
	local head = me.Character and me.Character:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("VipTag")
	local vip = me:GetAttribute("VIP") == true
	local shownRight = tag == nil or (tag:IsA("BillboardGui") and tag.Enabled == (me:GetAttribute("InLevel") == nil))
	check(if vip then "the VIP tag over your head" else "no VIP tag without VIP (VIP on/off shows it)",
		(tag ~= nil) == vip and shownRight)
	local failed, lines = 0, {}
	for _, step in ipairs(results) do
		if not step.ok then
			failed += 1
		end
		table.insert(lines, ("  %s  %s%s"):format(if step.ok then "pass" else "FAIL", step.label,
			if step.ok or not step.detail then "" else " (" .. step.detail .. ")"))
	end
	local summary = ("SELF-TEST (client): %d of %d passed.\n%s"):format(#results - failed, #results,
		table.concat(lines, "\n"))
	if failed == 0 then
		print(summary)
	else
		warn(summary)
	end
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevPanel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	-- THE TAB, top left under Roblox's own buttons: for a touch screen in the Device Emulator.
	local tab = Instance.new("TextButton")
	tab.Name = "DevTab"
	tab.Position = UDim2.fromOffset(12, 64)
	tab.Size = UDim2.fromOffset(kit.MIN_TOUCH + 12, kit.MIN_TOUCH)
	tab.BackgroundColor3 = kit.LOOK.pinkInk
	tab.FontFace = kit.CHUNKY
	tab.TextSize = 16
	tab.TextColor3 = kit.LOOK.pink
	tab.Text = "DEV"
	tab.Parent = gui
	kit.corner(tab, UDim.new(0.3, 0))
	tab.Activated:Connect(toggle)
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Active = true
	panel.Visible = false
	panel.Position = UDim2.fromOffset(12, 64 + kit.MIN_TOUCH + 10)
	panel.Size = UDim2.fromOffset(330, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = kit.LOOK.tile
	panel.Parent = gui
	kit.corner(panel, UDim.new(0, 18))
	kit.stroke(panel, kit.LOOK.pinkInk, 3)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = panel
	local column = Instance.new("UIListLayout")
	column.Padding = UDim.new(0, 8)
	column.SortOrder = Enum.SortOrder.LayoutOrder
	column.Parent = panel
	local title = kit.label(panel, "Title", "Studio test panel (F8)", kit.CHUNKY, 17, kit.LOOK.pinkInk)
	title.Size = UDim2.new(1, 0, 0, 24)
	title.LayoutOrder = 0
	-- TWO TO A ROW, so the panel stays on a phone's screen in the Device Emulator as the buttons grow.
	local grid = Instance.new("Frame")
	grid.Name = "Buttons"
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.new(1, 0, 0, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.LayoutOrder = 1
	grid.Parent = panel
	local cells = Instance.new("UIGridLayout")
	cells.CellSize = UDim2.new(0.5, -4, 0, kit.MIN_TOUCH + 5)
	cells.CellPadding = UDim2.fromOffset(8, 8)
	cells.SortOrder = Enum.SortOrder.LayoutOrder
	cells.Parent = grid
	for order, button in ipairs(BUTTONS) do
		local holder, face, content = kit.squishy(grid, button.action, kit.LOOK.pink, kit.LOOK.pinkInk)
		holder.LayoutOrder = order
		kit.buttonWords(content, button.text, kit.LOOK.pinkInk, 15)
		face.Activated:Connect(function()
			kit.sound("buttonClick", 0.5)
			if remote then
				remote:FireServer(button.action)
			end
			if button.action == "selftest" then
				task.spawn(clientSelfTest)
			end
		end)
		ui.first = ui.first or face
	end
	ui.panel = panel
end

function DevPanelClient.start()
	if not RunService:IsStudio() then
		return
	end
	local services = script.Parent
	local shopModule = services and services:WaitForChild("ShopService", 20)
	if shopModule and shopModule:IsA("ModuleScript") then
		kit = (require(shopModule) :: any).kit
	end
	local found = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("DevPanel", 20)
	if not (kit and found and found:IsA("RemoteEvent")) then
		warn("DevPanelClient: no DevPanel remote or no ShopService kit; paste the current server Bootstrap and ShopService.")
		return
	end
	remote = found
	build()
	ContextActionService:BindAction("DevPanelToggle", function(_, state)
		if state == Enum.UserInputState.Begin then
			toggle()
			return Enum.ContextActionResult.Sink
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.KeyCode.F8)
	print("DevPanelClient: running (Studio only), " .. DevPanelClient.VERSION)
end

DevPanelClient.STAMP = "61fc5413"
return DevPanelClient
