--!strict
-- StarterPlayerScripts/Services/JournalService.lua
-- THE JOURNAL: everything you pick up in Harrow Bay, kept to read when you choose to.
--
-- === Why ===
--
-- Notes used to go straight onto the screen, over the level, and keepsakes came up as cards every time
-- you stepped on a new material. Both were reported as too much: this is a game about pressing things,
-- and the story kept stepping in front of it. So nothing is put in front of you any more. What you
-- take goes into the book you carry, a small line in the corner says so, and the book opens when you
-- want it: J, or the book at the top right of the screen (tap it on a phone, Y on a gamepad).
--
-- === What goes in it ===
--
--   NOTES       notice boards, letters on the ground, the siren log: what people left for somebody.
--   KEEPSAKES   the things the Hold kept and grew into the levels, picked up where somebody put them
--               down: "Keepsake 5 of 27", where it came from, and who was holding it.
--   SECRETS     what you found behind the bricks, in the tin, in the lockers: "Secret 2 of 5".
--
-- The server says what you took (Interactables.take, over StoryMoment: "journal"); this keeps it for the
-- session, shows the line in the corner (not while a scene has the screen: it waits), and stops drawing
-- the thing you picked up, on your screen only (the next player can still find it). Unread entries
-- carry a dot, and the book's badge counts them.
--
-- The book is paper on a dark cover, the house style of the rest of the interface (Nunito for the
-- furniture, Garamond for anything somebody wrote). It frees the mouse while it is open, so it works
-- in first person too.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local SoundService = game:GetService("SoundService")

local JournalService = {}
JournalService.VERSION = "eighteenth pass, 2026-09-29"

local TITLE = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)
local BODY = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Medium)
local COVER = Color3.fromRGB(20, 19, 27)
local PAPER = Color3.fromRGB(240, 234, 216)
local PAPER_DEEP = Color3.fromRGB(226, 218, 196)
local INK = Color3.fromRGB(44, 38, 32)
local INK_SOFT = Color3.fromRGB(110, 98, 80)
local ACCENT = Color3.fromRGB(246, 206, 148)
local UNREAD = Color3.fromRGB(214, 96, 84)
local TOAST_SECONDS = 4.5

export type Entry = { id: string, kind: string, title: string, body: string, from: string?, eyebrow: string,
	order: number, read: boolean }

local KINDS = {
	{ key = "note", name = "Notes", empty = "Nothing yet. Notice boards and letters you take are kept here." },
	{ key = "keepsake", name = "Keepsakes", empty = "Nothing yet. The things the Hold kept are lying about off the route: pick one up." },
	{ key = "secret", name = "Secrets", empty = "Nothing yet. Some things here only open to a pry bar." },
}

local keepsakeTotal = (function(): number
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local module = shared and shared:FindFirstChild("Keepsakes")
	if module and module:IsA("ModuleScript") then
		local ok, data = pcall(require, module)
		if ok and typeof(data) == "table" then
			local count = 0
			for _ in pairs(data) do
				count += 1
			end
			return count
		end
	end
	return 27
end)()

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

local entries: { Entry } = {}
local byId: { [string]: Entry } = {}
local counts: { [string]: number } = { note = 0, keepsake = 0, secret = 0 }
local ui: { [string]: any } = {}
local isOpen = false
local shownKind = "note"
local shownId: string? = nil
local toasts: { { title: string, eyebrow: string } } = {}
local toasting = false

-- ===== SMALL PIECES =====

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function pad(parent: Instance, x: number, y: number)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft, padding.PaddingRight = UDim.new(0, x), UDim.new(0, x)
	padding.PaddingTop, padding.PaddingBottom = UDim.new(0, y), UDim.new(0, y)
	padding.Parent = parent
end

local function text(parent: Instance, name: string, value: string, font: Font | Enum.Font, size: number, colour: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	if typeof(font) == "Font" then
		label.FontFace = font
	else
		label.Font = font
	end
	label.TextSize = size
	label.TextColor3 = colour
	label.Text = value
	label.Parent = parent
	return label
end

local function unread(): number
	local count = 0
	for _, entry in ipairs(entries) do
		if not entry.read then
			count += 1
		end
	end
	return count
end

local function chime()
	local folder = SoundService:FindFirstChild("StorySounds")
	local own = folder and folder:FindFirstChild("JournalAdd")
	local s: Sound
	if own and own:IsA("Sound") then
		s = own:Clone()
	else
		s = Instance.new("Sound")
		s.SoundId = "rbxasset://sounds/clickfast.wav"
		s.PlaybackSpeed = 0.55
		s.Volume = 0.25
	end
	s.Parent = SoundService
	s:Play()
	game:GetService("Debris"):AddItem(s, 3)
end

-- ===== THE THINGS YOU PICKED UP, GONE FROM YOUR SCREEN =====

local function hide(object: Instance?)
	if not object then
		return
	end
	local function one(item: Instance)
		if item:IsA("BasePart") then
			-- Faded out over a moment, not blinked out: you picked it up, it did not vanish.
			local fade = Instance.new("NumberValue")
			fade.Value = item.LocalTransparencyModifier
			fade.Changed:Connect(function(value: number)
				if item.Parent then
					item.LocalTransparencyModifier = value
				end
			end)
			local tween = TweenService:Create(fade, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Value = 1 })
			tween.Completed:Once(function()
				fade:Destroy()
			end)
			tween:Play()
			item.CanQuery = false
		elseif item:IsA("ProximityPrompt") then
			item.Enabled = false
		elseif item:IsA("ParticleEmitter") or item:IsA("Light") or item:IsA("SurfaceGui") then
			(item :: any).Enabled = false
		elseif item:IsA("Decal") then
			-- (A Texture is a kind of Decal.)
			item.Transparency = 1
		end
	end
	one(object)
	for _, item in ipairs(object:GetDescendants()) do
		one(item)
	end
end

-- ===== THE BADGE AND THE BOOK'S TAB =====

local function refreshBadge()
	local badge = ui.badge
	if not badge then
		return
	end
	local count = unread()
	badge.Visible = count > 0
	badge.Text = if count > 9 then "9+" else tostring(count)
end

-- ===== THE BOOK =====

local refreshList: () -> ()

local function showEntry(entry: Entry?)
	local page = ui.page
	if not page then
		return
	end
	for _, child in ipairs(page:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	page.CanvasPosition = Vector2.zero
	if not entry then
		local kind = KINDS[1]
		for _, k in ipairs(KINDS) do
			if k.key == shownKind then
				kind = k
			end
		end
		local hint = text(page, "Empty", kind.empty, Enum.Font.Garamond, 20, INK_SOFT)
		hint.LayoutOrder = 1
		return
	end
	shownId = entry.id
	if not entry.read then
		entry.read = true
		refreshBadge()
	end
	local eyebrow = text(page, "Eyebrow", string.upper(entry.eyebrow), TITLE, 13, INK_SOFT)
	eyebrow.LayoutOrder = 1
	local title = text(page, "Title", entry.title, TITLE, 24, INK)
	title.LayoutOrder = 2
	if entry.from then
		local from = text(page, "From", entry.from, Enum.Font.Garamond, 18, INK_SOFT)
		from.LayoutOrder = 3
	end
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	rule.BackgroundColor3 = INK_SOFT
	rule.BackgroundTransparency = 0.6
	rule.BorderSizePixel = 0
	rule.Size = UDim2.new(0, 120, 0, 1)
	rule.LayoutOrder = 4
	rule.Parent = page
	local body = text(page, "Body", entry.body, Enum.Font.Garamond, 22, INK)
	body.LineHeight = 1.12
	body.LayoutOrder = 5
	refreshList()
end

refreshList = function()
	local list = ui.list
	if not list then
		return
	end
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for _, kind in ipairs(KINDS) do
		local tab = ui.tabs and ui.tabs[kind.key]
		if tab then
			local mine = 0
			for _, entry in ipairs(entries) do
				if entry.kind == kind.key then
					mine += 1
				end
			end
			tab.Text = ("%s  %d"):format(kind.name, mine)
			local on = kind.key == shownKind
			tab.BackgroundColor3 = if on then COVER else PAPER_DEEP
			tab.TextColor3 = if on then ACCENT else INK
		end
	end
	local index = 0
	for i = #entries, 1, -1 do
		local entry = entries[i]
		if entry.kind == shownKind then
			index += 1
			local row = Instance.new("TextButton")
			row.Name = "Row"
			row.AutoButtonColor = false
			row.Text = ""
			row.Size = UDim2.new(1, 0, 0, 58)
			row.BackgroundColor3 = if entry.id == shownId then PAPER_DEEP else PAPER
			row.BackgroundTransparency = if entry.id == shownId then 0 else 1
			row.BorderSizePixel = 0
			row.LayoutOrder = index
			row.Parent = list
			round(row, 8)
			local dot = Instance.new("Frame")
			dot.Name = "Unread"
			dot.AnchorPoint = Vector2.new(0, 0.5)
			dot.Position = UDim2.new(0, 8, 0.5, 0)
			dot.Size = UDim2.fromOffset(8, 8)
			dot.BackgroundColor3 = UNREAD
			dot.BorderSizePixel = 0
			dot.Visible = not entry.read
			dot.Parent = row
			round(dot, 4)
			local name = text(row, "Name", entry.title, Enum.Font.Garamond, 20, INK)
			name.Position = UDim2.fromOffset(24, 8)
			name.Size = UDim2.new(1, -30, 0, 22)
			name.AutomaticSize = Enum.AutomaticSize.None
			name.TextTruncate = Enum.TextTruncate.AtEnd
			name.TextWrapped = false
			local sub = text(row, "Sub", entry.eyebrow, BODY, 13, INK_SOFT)
			sub.Position = UDim2.fromOffset(24, 32)
			sub.Size = UDim2.new(1, -30, 0, 18)
			sub.AutomaticSize = Enum.AutomaticSize.None
			sub.TextTruncate = Enum.TextTruncate.AtEnd
			sub.TextWrapped = false
			row.Activated:Connect(function()
				showEntry(entry)
			end)
		end
	end
	if index == 0 and shownId == nil then
		showEntry(nil)
	end
end

local function pickKind(key: string)
	shownKind = key
	shownId = nil
	-- The newest of that kind, if there is one.
	local newest: Entry? = nil
	for i = #entries, 1, -1 do
		if entries[i].kind == key then
			newest = entries[i]
			break
		end
	end
	if newest then
		showEntry(newest)
	else
		refreshList()
		showEntry(nil)
	end
end

local function setOpen(on: boolean)
	if on == isOpen or not ui.book then
		return
	end
	isOpen = on
	local book: Frame = ui.book
	local dim: Frame = ui.dim
	if on then
		-- The newest unread thing, wherever it is; else the last kind looked at.
		for i = #entries, 1, -1 do
			if not entries[i].read then
				shownKind = entries[i].kind
				break
			end
		end
		pickKind(shownKind)
		dim.Visible = true
		book.Visible = true
		book.Position = UDim2.new(0.5, 0, 0.54, 0)
		ui.scale.Scale = 0.96
		TweenService:Create(book, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(0.5, 0.5) }):Play()
		TweenService:Create(ui.scale, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		TweenService:Create(dim, TweenInfo.new(0.25), { BackgroundTransparency = 0.45 }):Play()
		-- Escape closes the book (not the pause menu) while it is open.
		ContextActionService:BindActionAtPriority("JournalClose", function(_, state)
			if state == Enum.UserInputState.Begin then
				setOpen(false)
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
		chime()
	else
		ContextActionService:UnbindAction("JournalClose")
		local away = TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 1 })
		away:Play()
		TweenService:Create(ui.scale, TweenInfo.new(0.2), { Scale = 0.96 }):Play()
		away.Completed:Once(function()
			if not isOpen then
				dim.Visible = false
				book.Visible = false
			end
		end)
	end
end

function JournalService.toggle()
	setOpen(not isOpen)
end

function JournalService.isOpen(): boolean
	return isOpen
end

local function build()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local screen = Instance.new("ScreenGui")
	screen.Name = "Journal"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 45
	screen.Parent = playerGui
	ui.screen = screen

	-- THE TAB: a small book beside the pause tab, with a badge counting what is unread.
	local tab = Instance.new("TextButton")
	tab.Name = "JournalTab"
	tab.AnchorPoint = Vector2.new(1, 0)
	tab.Position = UDim2.new(1, -66, 0, 76)
	tab.Size = UDim2.new(0, 44, 0, 44)
	tab.BackgroundColor3 = COVER
	tab.BackgroundTransparency = 0.15
	tab.BorderSizePixel = 0
	tab.AutoButtonColor = true
	tab.Text = ""
	tab.Parent = screen
	round(tab, 12)
	local tabEdge = Instance.new("UIStroke")
	tabEdge.Color = ACCENT
	tabEdge.Transparency = 0.55
	tabEdge.Thickness = 1.5
	tabEdge.Parent = tab
	-- The book, drawn: two pages and a spine.
	for _, side in ipairs({ -1, 1 }) do
		local leaf = Instance.new("Frame")
		leaf.AnchorPoint = Vector2.new(0.5, 0.5)
		leaf.Position = UDim2.new(0.5, side * 6, 0.5, 0)
		leaf.Size = UDim2.fromOffset(11, 18)
		leaf.BackgroundColor3 = PAPER
		leaf.BorderSizePixel = 0
		leaf.Rotation = side * 6
		leaf.Parent = tab
		round(leaf, 2)
		for line = 0, 2 do
			local ink = Instance.new("Frame")
			ink.Position = UDim2.fromOffset(2, 4 + line * 4)
			ink.Size = UDim2.fromOffset(7, 1)
			ink.BackgroundColor3 = INK_SOFT
			ink.BorderSizePixel = 0
			ink.Parent = leaf
		end
	end
	local badge = Instance.new("TextLabel")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.new(1, -4, 0, 4)
	badge.Size = UDim2.fromOffset(20, 20)
	badge.BackgroundColor3 = UNREAD
	badge.BorderSizePixel = 0
	badge.FontFace = TITLE
	badge.TextSize = 12
	badge.TextColor3 = Color3.new(1, 1, 1)
	badge.Visible = false
	badge.Parent = tab
	round(badge, 10)
	ui.badge = badge
	ui.tab = tab
	tab.Activated:Connect(function()
		JournalService.toggle()
	end)

	-- THE LINE IN THE CORNER: under the tabs, sliding in from the right.
	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.AnchorPoint = Vector2.new(1, 0)
	toast.Position = UDim2.new(1, 340, 0, 132)
	toast.Size = UDim2.fromOffset(300, 0)
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.BackgroundColor3 = COVER
	toast.BackgroundTransparency = 0.08
	toast.BorderSizePixel = 0
	toast.Visible = false
	toast.Parent = screen
	round(toast, 12)
	pad(toast, 14, 10)
	local toastEdge = Instance.new("UIStroke")
	toastEdge.Color = ACCENT
	toastEdge.Transparency = 0.6
	toastEdge.Parent = toast
	local toastList = Instance.new("UIListLayout")
	toastList.Padding = UDim.new(0, 2)
	toastList.SortOrder = Enum.SortOrder.LayoutOrder
	toastList.Parent = toast
	ui.toastEyebrow = text(toast, "Eyebrow", "", TITLE, 12, ACCENT)
	ui.toastEyebrow.LayoutOrder = 1
	ui.toastTitle = text(toast, "Title", "", Enum.Font.Garamond, 20, PAPER)
	ui.toastTitle.LayoutOrder = 2
	ui.toastHint = text(toast, "Hint", "", BODY, 13, Color3.fromRGB(190, 184, 170))
	ui.toastHint.LayoutOrder = 3
	ui.toast = toast

	-- THE BOOK ITSELF.
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	-- Modal: frees the mouse while the book is open, even in first person.
	dim.Modal = true
	dim.Visible = false
	dim.Parent = screen
	dim.Activated:Connect(function()
		setOpen(false)
	end)
	ui.dim = dim

	local book = Instance.new("Frame")
	book.Name = "Book"
	book.AnchorPoint = Vector2.new(0.5, 0.5)
	book.Position = UDim2.fromScale(0.5, 0.5)
	book.Size = UDim2.fromScale(0.92, 0.82)
	book.BackgroundColor3 = COVER
	book.BorderSizePixel = 0
	book.Visible = false
	book.Parent = screen
	round(book, 18)
	pad(book, 14, 14)
	local biggest = Instance.new("UISizeConstraint")
	biggest.MaxSize = Vector2.new(900, 560)
	biggest.Parent = book
	local scale = Instance.new("UIScale")
	scale.Parent = book
	ui.scale = scale
	local bookEdge = Instance.new("UIStroke")
	bookEdge.Color = ACCENT
	bookEdge.Transparency = 0.5
	bookEdge.Thickness = 2
	bookEdge.Parent = book
	ui.book = book

	-- The left page: which kind, and the list.
	local left = Instance.new("Frame")
	left.Name = "LeftPage"
	left.Size = UDim2.new(0.38, -6, 1, 0)
	left.BackgroundColor3 = PAPER
	left.BorderSizePixel = 0
	left.Parent = book
	round(left, 10)
	pad(left, 14, 14)
	local heading = text(left, "Heading", "JOURNAL", TITLE, 14, INK_SOFT)
	heading.Size = UDim2.new(1, 0, 0, 18)
	heading.AutomaticSize = Enum.AutomaticSize.None
	local tabsRow = Instance.new("Frame")
	tabsRow.Name = "Kinds"
	tabsRow.BackgroundTransparency = 1
	tabsRow.Position = UDim2.fromOffset(0, 26)
	tabsRow.Size = UDim2.new(1, 0, 0, 30)
	tabsRow.Parent = left
	local tabsLayout = Instance.new("UIListLayout")
	tabsLayout.FillDirection = Enum.FillDirection.Horizontal
	tabsLayout.Padding = UDim.new(0, 6)
	tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabsLayout.Parent = tabsRow
	ui.tabs = {}
	for index, kind in ipairs(KINDS) do
		local button = Instance.new("TextButton")
		button.Name = kind.name
		button.Size = UDim2.new(1 / 3, -4, 1, 0)
		button.BackgroundColor3 = PAPER_DEEP
		button.BorderSizePixel = 0
		button.FontFace = TITLE
		button.TextSize = 13
		button.TextColor3 = INK
		button.Text = kind.name
		button.LayoutOrder = index
		button.Parent = tabsRow
		round(button, 8)
		button.Activated:Connect(function()
			pickKind(kind.key)
		end)
		ui.tabs[kind.key] = button
	end
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(0, 66)
	list.Size = UDim2.new(1, 0, 1, -66)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = INK_SOFT
	list.Parent = left
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
	ui.list = list

	-- The right page: what it says.
	local right = Instance.new("Frame")
	right.Name = "RightPage"
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position = UDim2.fromScale(1, 0)
	right.Size = UDim2.new(0.62, -6, 1, 0)
	right.BackgroundColor3 = PAPER
	right.BorderSizePixel = 0
	right.Parent = book
	round(right, 10)
	local page = Instance.new("ScrollingFrame")
	page.Name = "Page"
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.Size = UDim2.new(1, 0, 1, -34)
	page.CanvasSize = UDim2.new()
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.ScrollBarThickness = 4
	page.ScrollBarImageColor3 = INK_SOFT
	page.Parent = right
	pad(page, 26, 22)
	local pageLayout = Instance.new("UIListLayout")
	pageLayout.Padding = UDim.new(0, 8)
	pageLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pageLayout.Parent = page
	ui.page = page
	local foot = text(right, "Foot", "J or Esc to close", BODY, 13, INK_SOFT)
	foot.AnchorPoint = Vector2.new(1, 1)
	foot.Position = UDim2.new(1, -18, 1, -10)
	foot.Size = UDim2.new(1, -36, 0, 16)
	foot.AutomaticSize = Enum.AutomaticSize.None
	foot.TextXAlignment = Enum.TextXAlignment.Right
	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.Size = UDim2.fromOffset(30, 30)
	close.BackgroundColor3 = PAPER_DEEP
	close.BorderSizePixel = 0
	close.FontFace = TITLE
	close.TextSize = 16
	close.TextColor3 = INK
	close.Text = "X"
	close.Parent = right
	round(close, 15)
	close.Activated:Connect(function()
		setOpen(false)
	end)
end

-- ===== THE LINE IN THE CORNER =====

local function pumpToasts()
	if toasting then
		return
	end
	toasting = true
	task.spawn(function()
		while #toasts > 0 do
			-- Not over a scene: it waits for the camera to be given back.
			while (Cinema and Cinema.active()) or isOpen do
				task.wait(0.5)
				if isOpen then
					table.clear(toasts)
					break
				end
			end
			local item = table.remove(toasts, 1)
			if not item then
				break
			end
			local toast: Frame = ui.toast
			ui.toastEyebrow.Text = item.eyebrow
			ui.toastTitle.Text = item.title
			ui.toastHint.Text = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
				then "Tap the book to read it." else "Press J to read it."
			toast.Visible = true
			toast.Position = UDim2.new(1, 340, 0, 132)
			chime()
			TweenService:Create(toast, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Position = UDim2.new(1, -14, 0, 132) }):Play()
			local shownFor = 0
			while shownFor < TOAST_SECONDS and not isOpen do
				task.wait(0.1)
				shownFor += 0.1
			end
			local away = TweenService:Create(toast, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
				{ Position = UDim2.new(1, 340, 0, 132) })
			away:Play()
			away.Completed:Wait()
			toast.Visible = false
			task.wait(0.2)
		end
		toasting = false
	end)
end

-- ===== WHAT THE SERVER SAYS YOU TOOK =====

function JournalService.add(data: { [string]: any })
	local id = tostring(data.id or data.title)
	hide(if typeof(data.object) == "Instance" then data.object else nil)
	if byId[id] then
		-- Taken twice (it is still there for everyone else): nothing new, but a word to say so.
		if not data.quiet then
			table.insert(toasts, { eyebrow = "ALREADY IN YOUR JOURNAL", title = byId[id].title })
			pumpToasts()
		end
		return
	end
	local kind = tostring(data.kind or "note")
	counts[kind] = (counts[kind] or 0) + 1
	local eyebrow = "A note"
	local from: string? = nil
	if kind == "keepsake" then
		eyebrow = ("Keepsake %d of %d"):format(counts[kind], keepsakeTotal)
		if typeof(data.from) == "string" then
			from = "From " .. data.from .. "."
		end
	elseif kind == "secret" then
		eyebrow = ("Secret %d of %d"):format(counts[kind], tonumber(data.total) or 5)
		if typeof(data.secret) == "string" and data.secret ~= data.title then
			from = data.secret .. "."
		end
	elseif typeof(data.from) == "string" then
		from = data.from
	end
	local entry: Entry = { id = id, kind = kind, title = tostring(data.title), body = tostring(data.body or ""), from = from,
		eyebrow = eyebrow, order = #entries + 1, read = false }
	table.insert(entries, entry)
	byId[id] = entry
	refreshBadge()
	if isOpen then
		refreshList()
	end
	if not data.quiet then
		table.insert(toasts, { eyebrow = if kind == "keepsake" then "KEEPSAKE KEPT" else "ADDED TO YOUR JOURNAL",
			title = entry.title })
		pumpToasts()
	end
end

function JournalService.entries(): { Entry }
	return table.clone(entries)
end

function JournalService.start()
	build()
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.J or input.KeyCode == Enum.KeyCode.ButtonY then
			JournalService.toggle()
		end
	end)
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	local event = remotes and remotes:WaitForChild("StoryMoment", 20)
	if not (event and event:IsA("RemoteEvent")) then
		warn("JournalService: no RemoteEvents.StoryMoment, so nothing you pick up reaches the journal. The server "
			.. "Bootstrap makes it; paste src/Server/Bootstrap.server.lua.")
		return
	end
	event.OnClientEvent:Connect(function(kind: any, data: any)
		if kind == "journal" and typeof(data) == "table" then
			local ok, err = pcall(JournalService.add, data)
			if not ok then
				warn("JournalService: could not keep an entry: " .. tostring(err))
			end
		elseif kind == "hide" and typeof(data) == "Instance" then
			hide(data)
		end
	end)
	print("JournalService: running, " .. JournalService.VERSION)
end

return JournalService
