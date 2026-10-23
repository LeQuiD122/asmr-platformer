--!strict
-- StarterPlayerScripts/Services/ShopService.lua
-- THE SHOP: bold, bright and TACTILE. Its buttons press down and spring back like the materials do,
-- and a purchase pops like bubble wrap. It opens from the kiosk in the lobby (Roblox's own prompt) and
-- from the pause menu, and from nowhere else: nothing about it sits on the screen while you play.
--
-- EVERY DEVICE. The layout is worked out from the screen it is on, every time it opens and whenever
-- the screen changes: four columns on a wide screen, three on a tablet or a phone on its side, two on
-- a narrow one; the tabs scroll sideways when they do not fit; every button is at least 44 pixels
-- high (a thumb); the whole of it is kept inside the device's safe area (notches, rounded corners).
-- A controller: the first tile is selected when it opens, the bumpers change tab, B closes. A
-- keyboard: Escape closes. Your character, and a phone's thumbstick, are paused while it is open.
--
-- IT ASKS, IT NEVER TELLS. Every buy and equip goes to the server (EconomyService) as an action and an
-- item id; what comes back is the truth about your tokens and what you own, and the shop redraws from
-- that. Robux goes through Roblox's own purchase window.
--
-- MADE OVER (the hundred-and-twenty-second pass, from your test: "resize the UI appropriately so that the edges of the
-- categories are not cut off, and work on the colours a bit more, and improve those animations ... and the layout, and
-- make it fancier"). The tabs have room all round inside their strip, so no outline is cut off; each is a chunky key in
-- its own colour with its own little drawing, on a lip it presses into, the chosen one deeper, lifted and bounced. A
-- tab's colour runs through everything in it: its tiles washed pale in it, outlined and lettered in deeper shades of it
-- (its hue kept, never greyed). The tiles sit on a tray over the background, each a card on a lip that lifts under the
-- pointer and sinks under a press, and they pop in one after another when a tab opens; the rare ones and what is sold
-- for Robux have a gleam running round their outline; the best value of the token packs says so. Your tokens count up
-- and down, the difference rising off the wallet; beside them, on a wide screen, how many of a tab are yours. A tab
-- chosen or a thing bought puffs a little of the background's material (ShopLook.puff).

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ShopCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopCatalog")) :: any
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

-- ITS LOOK AND FEEL (the hundred-and-fifth pass, ShopLook): a material of the game behind it, a cookie for a cursor, a
-- press on its background answered in its material, its own sounds opening, closing and changing tab. Without it the
-- shop is as it was.
local ShopLook: any = (function(): any
	local found = script.Parent and script.Parent:FindFirstChild("ShopLook")
	if found and found:IsA("ModuleScript") then
		local ok, loaded = pcall(require, found)
		if ok and type(loaded) == "table" then
			return loaded
		end
		warn("ShopService: ShopLook failed to load, so the shop is plain: " .. tostring(loaded))
	end
	return nil
end)()

local ShopService = {}
ShopService.VERSION = "the shop, 2026-10-22"

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- THE LOOK (option A, "tactile chunky"): mint panel, deep teal edges, pink and amber pills.
local LOOK = {
	panel = rgb(159, 225, 203),
	edge = rgb(8, 80, 65),
	tile = rgb(225, 245, 238),
	ink = rgb(4, 52, 44),
	soft = rgb(15, 110, 86),
	pink = rgb(251, 234, 240),
	pinkInk = rgb(114, 36, 62),
	amber = rgb(250, 238, 218),
	amberInk = rgb(99, 56, 6),
	token = rgb(239, 159, 39),
	tokenEdge = rgb(99, 56, 6),
	tokenInk = rgb(65, 36, 2),
	robux = rgb(151, 196, 89),
	robuxEdge = rgb(39, 80, 10),
	robuxInk = rgb(23, 52, 4),
	soon = rgb(211, 209, 199),
	soonEdge = rgb(95, 94, 90),
	soonInk = rgb(68, 68, 65),
	white = rgb(255, 255, 255),
}
-- A TAB'S COLOURS (family, below): its own, a pale wash of it, and two deeper shades of it for outlines and words.
type Family = { fill: Color3, pale: Color3, edge: Color3, ink: Color3 }
local CHUNKY = Style.FONT.display
local BODY = Style.FONT.heading
local MIN_TOUCH = 44 -- pixels: nothing you press is smaller than a thumb
-- ROOM (the hundred-and-twenty-second pass): inside the tabs' strip and round the grid's tiles, so an outline, a lip or a
-- lift is never cut off at an edge; and the lips the tabs and the tiles stand on.
local TAB_ROOM, TAB_LIP = 10, 5
local TILE_ROOM, TILE_LIP = 9, 6
local CLOSE_ACTION = "ShopClose"
local TAB_ACTION = "ShopTabs"

-- Is a controller what is being used right now (not merely plugged in)?
local function usingPad(): boolean
	return UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
end

-- Everything built, kept in one table.
local ui: { [string]: any } = {}
-- What the shop is showing, and what the server last said.
local shop = {
	open = false,
	tab = "Featured",
	data = nil :: any,
	preview = nil :: string?,
	asking = false,
	cols = 4,
	text = 1, -- text scale for this screen
	cell = Vector2.new(180, 220),
	requestRemote = nil :: RemoteFunction?,
	stateRemote = nil :: RemoteFunction?,
	controls = nil :: any,
	seenOwned = nil :: { [string]: boolean }?, -- what the server said you owned last time (a Robux background unboxed)
	palette = nil :: Family?, -- this tab's colours, for everything drawn now
	fresh = false, -- a tab has just opened: its tiles pop in
	wide = false, -- room in the header for how many of a tab are yours
	drawn = nil :: string?, -- what the grid was last drawn from
	gleams = {} :: { UIGradient }, -- the lights running round the rare tiles' outlines
	-- LIVELIER (the hundred-and-thirty-fifth pass, from your test: "improve the shop looks even more"): turned, swept and
	-- breathed by the same frame loop as the gleams.
	rays = {} :: { Frame }, -- the sunbursts behind the icons
	sheens = {} :: { { grad: UIGradient, phase: number } }, -- the sheen across each card
	breathe = {} :: { UIScale }, -- the prices you can pay
}

-- ===== SMALL THINGS =====

local function corner(parent: Instance, radius: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = radius
	c.Parent = parent
end

local function stroke(parent: Instance, colour: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = colour
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

local function label(parent: Instance, name: string, text: string, font: Font, size: number, colour: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.FontFace = font
	l.TextSize = size
	l.TextColor3 = colour
	l.Text = text
	l.Parent = parent
	return l
end

-- A sound from the game's own takes (SoundService.MaterialSounds: a keypad click for a tap, bubble wrap
-- for a purchase), or a built-in one where those are not imported.
local function uiSound(event: string, volume: number)
	local folder = SoundService:FindFirstChild("MaterialSounds")
	local takes = {}
	if folder then
		for _, s in ipairs(folder:GetChildren()) do
			if s:IsA("Sound") and s.Name:sub(1, #event + 1) == event .. "_" then
				table.insert(takes, s)
			end
		end
	end
	local made: Sound
	if #takes > 0 then
		made = (takes[math.random(1, #takes)] :: Sound):Clone()
	else
		made = Instance.new("Sound")
		made.SoundId = "rbxasset://sounds/electronicpingshort.wav"
		made.PlaybackSpeed = if event == "bubblePop" then 1.4 else 2
	end
	made.Volume = volume
	made.Parent = SoundService
	made:Play()
	game:GetService("Debris"):AddItem(made, 3)
end

-- A TACTILE BUTTON: a coloured face on a darker lip. Pressed, the face sinks onto the lip; let go, it
-- springs back past where it was and settles. `face` is the TextButton (it gets the selection and the
-- Activated), `content` the row inside it for a coin and the words.
local function squishy(parent: Instance, name: string, fill: Color3, edge: Color3): (Frame, TextButton, Frame)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.Parent = parent
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.BackgroundColor3 = edge
	lip.BorderSizePixel = 0
	lip.Position = UDim2.new(0, 0, 0, 5)
	lip.Size = UDim2.new(1, 0, 1, -5)
	lip.Parent = holder
	corner(lip, UDim.new(0.5, 0))
	local face = Instance.new("TextButton")
	face.Name = "Face"
	face.AutoButtonColor = false
	face.BackgroundColor3 = fill
	face.BorderSizePixel = 0
	face.Size = UDim2.new(1, 0, 1, -5)
	face.Text = ""
	face.Selectable = true
	face.Parent = holder
	corner(face, UDim.new(0.5, 0))
	stroke(face, edge, 3)
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.fromScale(1, 1)
	content.Parent = face
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 6)
	row.Parent = content
	local down = UDim2.new(0, 0, 0, 4)
	local up = UDim2.new(0, 0, 0, 0)
	local function press()
		TweenService:Create(face, TweenInfo.new(0.06, Enum.EasingStyle.Quad), { Position = down }):Play()
	end
	local function release()
		TweenService:Create(face, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = up }):Play()
	end
	face.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			press()
		end
	end)
	face.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			release()
		end
	end)
	-- A controller's A has no InputBegan on the button, so it gets the whole press at once.
	face.Activated:Connect(function(_input: InputObject?)
		if usingPad() then
			press()
			task.delay(0.07, release)
		end
	end)
	return holder, face, content
end

local function coin(parent: Instance, size: number): Frame
	local c = Instance.new("Frame")
	c.Name = "Coin"
	c.Size = UDim2.fromOffset(size, size)
	c.BackgroundColor3 = rgb(250, 199, 117)
	c.BorderSizePixel = 0
	c.LayoutOrder = 0
	c.Parent = parent
	corner(c, UDim.new(0.5, 0))
	stroke(c, LOOK.tokenEdge, 2)
	local shine = Instance.new("Frame")
	shine.BackgroundColor3 = rgb(255, 238, 200)
	shine.BorderSizePixel = 0
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(0.5, 0.5)
	shine.Size = UDim2.fromScale(0.42, 0.42)
	shine.Parent = c
	corner(shine, UDim.new(0.5, 0))
	return c
end

-- The words on a button, as the second thing in its row.
local function buttonWords(content: Frame, text: string, colour: Color3, size: number): TextLabel
	local words = label(content, "Words", text, CHUNKY, size, colour)
	words.AutomaticSize = Enum.AutomaticSize.X
	words.Size = UDim2.new(0, 0, 1, 0)
	words.LayoutOrder = 1
	return words
end

-- ===== A TOAST: one line, for a moment =====

local function toast(text: string)
	local holder = ui.toast
	if not holder then
		return
	end
	holder.Text = text
	holder.Visible = true
	-- In the colours of the tab it is said over.
	local fam = shop.palette
	if fam then
		holder.BackgroundColor3 = fam.pale
		holder.TextColor3 = fam.ink
		if ui.toastEdge then
			ui.toastEdge.Color = fam.edge
		end
	end
	holder.Position = UDim2.new(0.5, 0, 1, 20)
	TweenService:Create(holder, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 1, -24) }):Play()
	local stamp = os.clock()
	ui.toastAt = stamp
	task.delay(2.6, function()
		if ui.toastAt == stamp then
			holder.Visible = false
		end
	end)
end

-- ===== THE ICON ON A TILE: a drawing of what it is, made of shapes =====

local function blob(parent: Instance, size: UDim2, position: UDim2, colour: Color3, round: boolean): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = colour
	f.BorderSizePixel = 0
	f.Parent = parent
	corner(f, if round then UDim.new(0.5, 0) else UDim.new(0.25, 0))
	return f
end

local function drawIcon(icon: Frame, item: any)
	local ink = item.accent
	local kind = item.kind
	if kind == "trail" then
		blob(icon, UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.68, 0.5), ink, true)
		blob(icon, UDim2.fromScale(0.2, 0.2), UDim2.fromScale(0.42, 0.5), ink, true).BackgroundTransparency = 0.3
		blob(icon, UDim2.fromScale(0.12, 0.12), UDim2.fromScale(0.24, 0.5), ink, true).BackgroundTransparency = 0.55
	elseif kind == "aura" then
		local ring = blob(icon, UDim2.fromScale(0.62, 0.62), UDim2.fromScale(0.5, 0.5), ink, true)
		ring.BackgroundTransparency = 1
		stroke(ring, ink, 3)
		blob(icon, UDim2.fromScale(0.22, 0.22), UDim2.fromScale(0.5, 0.5), ink, true)
	elseif kind == "steps" then
		local left = blob(icon, UDim2.fromScale(0.2, 0.34), UDim2.fromScale(0.38, 0.58), ink, true)
		left.Rotation = -12
		local right = blob(icon, UDim2.fromScale(0.2, 0.34), UDim2.fromScale(0.62, 0.4), ink, true)
		right.Rotation = 12
	elseif kind == "sound" then
		for k, h in ipairs({ 0.3, 0.56, 0.4 }) do
			blob(icon, UDim2.fromScale(0.13, h), UDim2.fromScale(0.3 + (k - 1) * 0.2, 0.5), ink, false)
		end
	elseif kind == "emote" then
		blob(icon, UDim2.fromScale(0.26, 0.26), UDim2.fromScale(0.5, 0.32), ink, true)
		blob(icon, UDim2.fromScale(0.36, 0.3), UDim2.fromScale(0.5, 0.68), ink, false)
	elseif kind == "background" then
		-- A SWATCH of the background: its own two colours, top to bottom, and a few of its pieces.
		local theme = if ShopLook and item.theme then ShopLook.THEMES[item.theme] else nil
		local wash = Instance.new("UIGradient")
		wash.Rotation = 90
		wash.Color = if theme then ColorSequence.new(theme.top, theme.bottom) else ColorSequence.new(item.colour, item.accent)
		wash.Parent = icon
		for k, spot in ipairs({ { 0.32, 0.36, 0.2 }, { 0.66, 0.3, 0.14 }, { 0.52, 0.66, 0.24 } }) do
			local bit = blob(icon, UDim2.fromScale(spot[3], spot[3]), UDim2.fromScale(spot[1], spot[2]),
				if theme then theme.fx2 else ink, true)
			bit.BackgroundTransparency = 0.15 + k * 0.1
		end
	elseif kind == "crate" then
		-- A CRATE: a wooden box under its lid, with a question on it.
		local box = blob(icon, UDim2.fromScale(0.6, 0.42), UDim2.fromScale(0.5, 0.6), item.colour:Lerp(ink, 0.15), false)
		stroke(box, ink, 2)
		local lid = blob(icon, UDim2.fromScale(0.68, 0.14), UDim2.fromScale(0.5, 0.35), item.colour:Lerp(ink, 0.35), false)
		stroke(lid, ink, 2)
		local mark = label(box, "Mark", "?", CHUNKY, 18, LOOK.white)
		mark.Size = UDim2.fromScale(1, 1)
		mark.TextScaled = true
	elseif kind == "tokens" then
		for k = 1, 3 do
			local c = blob(icon, UDim2.fromScale(0.42, 0.16), UDim2.fromScale(0.5, 0.66 - (k - 1) * 0.14), LOOK.token, true)
			stroke(c, LOOK.tokenEdge, 2)
		end
	else
		local words = label(icon, "Glyph", if item.id == "DoubleTokens" then "2x" elseif item.id == "VIP" then "VIP" else "+1",
			CHUNKY, 18, ink)
		words.Size = UDim2.fromScale(1, 1)
		words.TextScaled = true
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0.18, 0)
		pad.PaddingRight = UDim.new(0.18, 0)
		pad.PaddingTop = UDim.new(0.22, 0)
		pad.PaddingBottom = UDim.new(0.22, 0)
		pad.Parent = words
	end
end

-- ===== A TAB'S COLOURS (the hundred-and-twenty-second pass, from your test: "work on the colours a bit more") =====
--
-- Every tab's own colour (ShopLook.TAB_COLOURS) runs through everything in it: its tiles washed pale in it, outlined
-- and lettered in deeper shades of the same colour (its hue kept and its colour strengthened as it darkens, so a deep
-- shade is never a grey), the tray's scroll bar, the "i" card, the confirm card and the toast. A tab and what is in it
-- are one family; the next tab is another.
local function family(tab: string): Family
	local own = if ShopLook and ShopLook.TAB_COLOURS then ShopLook.TAB_COLOURS[tab] else nil
	if typeof(own) ~= "Color3" then
		return { fill = LOOK.panel, pale = LOOK.tile, edge = LOOK.edge, ink = LOOK.ink }
	end
	local h, s, v = own:ToHSV()
	return {
		fill = own,
		pale = own:Lerp(LOOK.white, 0.72),
		edge = Color3.fromHSV(h, math.min(1, s * 1.25 + 0.15), v * 0.42),
		ink = Color3.fromHSV(h, math.min(1, s + 0.2), v * 0.26),
	}
end

-- A TAB'S OWN LITTLE DRAWING, on a white disc at the start of its key: what is in it, made of shapes like the tiles'.
local function tabGlyph(disc: Frame, tab: string, ink: Color3)
	if tab == "Featured" then
		-- A star: two squares, one turned.
		for _, turn in ipairs({ 0, 45 }) do
			blob(disc, UDim2.fromScale(0.46, 0.46), UDim2.fromScale(0.5, 0.5), ink, false).Rotation = turn
		end
	elseif tab == "Steps" then
		blob(disc, UDim2.fromScale(0.2, 0.34), UDim2.fromScale(0.38, 0.58), ink, true).Rotation = -12
		blob(disc, UDim2.fromScale(0.2, 0.34), UDim2.fromScale(0.62, 0.42), ink, true).Rotation = 12
	elseif tab == "Trails" then
		blob(disc, UDim2.fromScale(0.3, 0.3), UDim2.fromScale(0.66, 0.5), ink, true)
		blob(disc, UDim2.fromScale(0.2, 0.2), UDim2.fromScale(0.4, 0.5), ink, true).BackgroundTransparency = 0.35
		blob(disc, UDim2.fromScale(0.12, 0.12), UDim2.fromScale(0.22, 0.5), ink, true).BackgroundTransparency = 0.6
	elseif tab == "Sounds" then
		for k, tall in ipairs({ 0.3, 0.56, 0.4 }) do
			blob(disc, UDim2.fromScale(0.14, tall), UDim2.fromScale(0.3 + (k - 1) * 0.2, 0.5), ink, false)
		end
	elseif tab == "Auras" then
		local ring = blob(disc, UDim2.fromScale(0.62, 0.62), UDim2.fromScale(0.5, 0.5), ink, true)
		ring.BackgroundTransparency = 1
		stroke(ring, ink, 2)
		blob(disc, UDim2.fromScale(0.22, 0.22), UDim2.fromScale(0.5, 0.5), ink, true)
	elseif tab == "Emotes" then
		blob(disc, UDim2.fromScale(0.28, 0.28), UDim2.fromScale(0.5, 0.3), ink, true)
		blob(disc, UDim2.fromScale(0.42, 0.3), UDim2.fromScale(0.5, 0.68), ink, false)
	elseif tab == "Passes" then
		-- A ticket, with a notch at each end.
		blob(disc, UDim2.fromScale(0.64, 0.4), UDim2.fromScale(0.5, 0.5), ink, false)
		for _, x in ipairs({ 0.18, 0.82 }) do
			blob(disc, UDim2.fromScale(0.16, 0.16), UDim2.fromScale(x, 0.5), LOOK.white, true)
		end
	elseif tab == "Tokens" then
		local c = blob(disc, UDim2.fromScale(0.6, 0.6), UDim2.fromScale(0.5, 0.5), LOOK.token, true)
		stroke(c, LOOK.tokenEdge, 2)
		blob(c, UDim2.fromScale(0.42, 0.42), UDim2.fromScale(0.5, 0.5), rgb(255, 238, 200), true)
	elseif tab == "Backgrounds" then
		-- A swatch, shading from one colour into another.
		local swatch = blob(disc, UDim2.fromScale(0.58, 0.58), UDim2.fromScale(0.5, 0.5), LOOK.white, false)
		local wash = Instance.new("UIGradient")
		wash.Rotation = 45
		wash.Color = ColorSequence.new(ink, ink:Lerp(LOOK.white, 0.6))
		wash.Parent = swatch
	end
end

-- THE BEST VALUE of the token packs: the most tokens for each Robux, from the catalogue's own numbers.
local function bestPack(): string?
	local best, most = nil, 0
	for _, item in ipairs(ShopCatalog.inTab("Tokens")) do
		if item.kind == "tokens" and type(item.tokens) == "number" and type(item.robux) == "number" and item.robux > 0 then
			local each = item.tokens / item.robux
			if each > most then
				best, most = item.id, each
			end
		end
	end
	return best
end

-- ===== WHAT THE SERVER SAYS =====

local function owned(id: string): boolean
	local data = shop.data
	return data ~= nil and data.owned ~= nil and data.owned[id] == true
end

local function equipped(item: any): boolean
	local data = shop.data
	return data ~= nil and data.equipped ~= nil and data.equipped[item.kind] == item.id
end

local function tokens(): number
	local data = shop.data
	return if data and typeof(data.tokens) == "number" then data.tokens else 0
end

local render: () -> () -- the grid, drawn again (declared here, made below)
local wearBackground: (string) -> () -- a background put on (made below, once ask is)

-- THE TITLE in the colours of the background behind it (ShopLook calls this whenever the background changes).
local function paintTitle()
	if ShopLook and ui.title then
		local theme = ShopLook.theme()
		ui.title.BackgroundColor3 = theme.title
		ui.title.TextColor3 = theme.titleInk
		if ui.titleEdge then
			ui.titleEdge.Color = theme.edge
		end
		-- (And the tray the tiles sit on in a pale wash of it, outlined in its edge.)
		if ui.tray then
			ui.tray.BackgroundColor3 = theme.top:Lerp(LOOK.white, 0.8)
			ui.trayEdge.Color = theme.edge
		end
	end
end

-- YOUR TOKENS (the hundred-and-twenty-second pass): counted up or down to what the server says rather than jumped,
-- the difference rising off the wallet (gained) or sinking from it (spent), and the wallet swelling or squeezing.
-- With the shop shut, just written.
local function showTokens(value: number)
	local words = ui.tokenWords
	local from = ui.shownTokens
	ui.shownTokens = value
	if not words then
		return
	end
	if not (shop.open and typeof(from) == "number" and from ~= value) then
		words.Text = tostring(value)
		return
	end
	local counter = Instance.new("NumberValue")
	counter.Value = from
	counter.Changed:Connect(function(now: number)
		if ui.shownTokens == value then
			words.Text = tostring(math.floor(now + 0.5))
		end
	end)
	local count = TweenService:Create(counter, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = value })
	count.Completed:Once(function()
		if ui.shownTokens == value then
			words.Text = tostring(value)
		end
		counter:Destroy()
	end)
	count:Play()
	local wallet, panel = ui.wallet, ui.panel
	if not (wallet and panel) then
		return
	end
	local gained = value > from
	local swell = wallet:FindFirstChildOfClass("UIScale")
	if swell then
		swell.Scale = if gained then 1.14 else 0.9
		TweenService:Create(swell, TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	local s = math.max(ui.bounce.Scale, 0.01)
	local at = (wallet.AbsolutePosition - panel.AbsolutePosition) / s
	local size = wallet.AbsoluteSize / s
	local delta = label(panel, "Delta", (if gained then "+" else "") .. tostring(value - from), CHUNKY, 24,
		if gained then LOOK.robuxEdge else LOOK.pinkInk)
	delta.ZIndex = 25
	delta.Size = UDim2.fromOffset(size.X, 30)
	delta.Position = UDim2.fromOffset(at.X, at.Y + size.Y + 2)
	local rim = Instance.new("UIStroke")
	rim.Color = LOOK.white
	rim.Thickness = 2
	rim.Parent = delta
	local drift = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(delta, drift, { Position = UDim2.fromOffset(at.X, at.Y + size.Y + (if gained then -16 else 24)),
		TextTransparency = 1 }):Play()
	TweenService:Create(rim, drift, { Transparency = 1 }):Play()
	game:GetService("Debris"):AddItem(delta, 1)
end

-- What the grid is drawn from, in one line: an answer from the server that changes none of it does not draw the grid
-- again (which would cut short its tiles popping in).
local function drawnFrom(data: any): string
	local bits = { tostring(data.ready), tostring(data.crates), tostring(data.chances) }
	for _, set in ipairs({ data.owned, data.equipped }) do
		if type(set) == "table" then
			local keys = {}
			for key, value in pairs(set) do
				table.insert(keys, tostring(key) .. "=" .. tostring(value))
			end
			table.sort(keys)
			table.insert(bits, table.concat(keys, ","))
		end
	end
	return table.concat(bits, "|")
end

local function accept(data: any)
	if type(data) ~= "table" then
		return
	end
	shop.data = data
	if ui.tokenWords then
		if data.ready and typeof(data.tokens) == "number" then
			showTokens(data.tokens)
		else
			ui.tokenWords.Text = "..."
		end
	end
	-- THE BACKGROUND YOU HAVE ON (the hundred-and-sixth pass): the shop opens on it, and turns to it at once if it is
	-- open; and a background bought with Robux is unboxed the moment Roblox says it is yours.
	if ShopLook and data.ready then
		local worn = if type(data.equipped) == "table" then ShopCatalog.get(data.equipped.background) else nil
		ShopLook.choose(if worn then worn.theme else nil)
		local before = shop.seenOwned
		local now = if type(data.owned) == "table" then data.owned else {}
		if before and shop.open then
			for _, item in ipairs(ShopCatalog.inTab("Backgrounds")) do
				if item.kind == "background" and item.robux and now[item.id] and not before[item.id] then
					ShopLook.crate(function(): any
						return { ok = true, won = item.id }
					end, wearBackground, function() end)
				end
			end
		end
		shop.seenOwned = table.clone(now)
	end
	-- (Drawn again only when it changes what is drawn: an answer about your tokens alone leaves the tiles as they are.)
	if shop.open and drawnFrom(data) ~= shop.drawn then
		render()
	end
end

local function ask(action: string, id: string): any
	local remote = shop.requestRemote
	if not remote or shop.asking then
		return nil
	end
	shop.asking = true
	local ok, result = pcall(function()
		return remote:InvokeServer(action, id)
	end)
	shop.asking = false
	if not ok or type(result) ~= "table" then
		toast("The shop did not answer. Try again in a moment.")
		return nil
	end
	accept(result.state)
	return result
end

wearBackground = function(id: string)
	local item = ShopCatalog.get(id)
	local result = ask("equip", id)
	if item and result and result.ok then
		toast(item.name .. " is behind the shop now.")
	end
end

-- ===== TRYING THINGS ON (your own screen only) =====

local function wearPreview(item: any?)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return
	end
	if item and (item.kind == "trail" or item.kind == "aura") then
		ShopCatalog.wear(root, if item.kind == "trail" then item else nil, if item.kind == "aura" then item else nil, "ShopPreview")
		shop.preview = item.id
	else
		ShopCatalog.wear(root, nil, nil, "ShopPreview")
		shop.preview = nil
	end
end

-- ===== THE POP when something is bought =====

local function pop(at: GuiObject)
	uiSound("bubblePop", 0.7)
	-- (And a little of the background's material out of it.)
	if ShopLook and ShopLook.puff then
		ShopLook.puff(at, 1.2)
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 1.12
	scale.Parent = at
	TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	game:GetService("Debris"):AddItem(scale, 0.5)
	-- Bubbles burst out of it and fade.
	for k = 1, 9 do
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.fromScale(0.5, 0.5)
		b.Size = UDim2.fromOffset(12, 12)
		b.BackgroundColor3 = LOOK.white
		b.BackgroundTransparency = 0.2
		b.BorderSizePixel = 0
		b.ZIndex = 20
		b.Parent = at
		corner(b, UDim.new(0.5, 0))
		stroke(b, LOOK.edge, 2)
		local a = k / 9 * math.pi * 2
		TweenService:Create(b, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, math.cos(a) * 70, 0.5, math.sin(a) * 70),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(4, 4),
		}):Play()
		game:GetService("Debris"):AddItem(b, 0.6)
	end
end

-- ===== THE CONFIRM CARD =====

local function confirm(text: string, yesText: string, onYes: () -> ())
	local modal = ui.modal
	if not modal then
		return
	end
	modal.Card.Message.Text = text
	ui.yesWords.Text = yesText
	ui.onYes = onYes
	-- In the tab's colours; the dark coming up behind it, and the card swinging in.
	local fam: Family = shop.palette or family(shop.tab)
	modal.Card.BackgroundColor3 = fam.pale
	modal.Card.Message.TextColor3 = fam.ink
	if ui.cardEdge then
		ui.cardEdge.Color = fam.edge
	end
	modal.Visible = true
	modal.BackgroundTransparency = 1
	TweenService:Create(modal, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.4 }):Play()
	modal.Card.Rotation = -4
	TweenService:Create(modal.Card, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	local scale = modal.Card:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 0.85
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	if usingPad() then
		GuiService.SelectedObject = ui.yes
	end
end

local function closeConfirm()
	if ui.modal then
		ui.modal.Visible = false
	end
	ui.onYes = nil
end

-- ===== A BACKGROUND CRATE (the hundred-and-sixth pass) =====
--
-- Opened from its tile, or from a background still in it: never where Roblox's policy for you keeps paid random items
-- out (the server says so, `crates`); nothing to open once you have them all; your odds said before you pay (on the
-- confirm card, for what you have). ShopLook shakes it while the server rolls it, and shows what came out.
local CRATE_WORDS: { [string]: string } = {
	short = "Not enough tokens.",
	restricted = "Background crates are not offered where you are.",
	owned = "You have every background from the crates.",
	busy = "One moment, then try again.",
	loading = "Your save is still loading. Try again in a moment.",
}

local function crateRefused(result: any)
	if type(result) ~= "table" then
		return -- (ask has said the shop did not answer)
	end
	toast(CRATE_WORDS[result.reason] or "The crate would not open. Try again in a moment.")
end

local function openCrate(crate: any)
	if shop.data and shop.data.crates == false then
		toast(CRATE_WORDS.restricted)
		return
	end
	if ShopCatalog.crateDone(owned) then
		toast(CRATE_WORDS.owned)
		return
	end
	local price = crate.price :: number
	if tokens() < price then
		confirm(("You need %d more tokens for a crate."):format(price - tokens()), "Get tokens", function()
			ShopService.showTab("Tokens")
		end)
		return
	end
	confirm(("Open a crate for %d tokens? Always one you do not have. %s."):format(price, ShopCatalog.crateOdds(owned)),
		"Open it", function()
			if ShopLook then
				ShopLook.crate(function(): any
					return ask("crate", crate.id)
				end, wearBackground, crateRefused)
				return
			end
			local result = ask("crate", crate.id)
			local won = if result and result.ok then ShopCatalog.get(result.won) else nil
			if won then
				toast(won.name .. " came out of the crate.")
			else
				crateRefused(result)
			end
		end)
end

-- ===== PRESSING A PRICE =====

local function pressPrice(item: any, tile: GuiObject)
	uiSound("buttonClick", 0.5)
	if item.soon then
		toast(item.name .. " is coming soon.")
		return
	end
	local player = Players.LocalPlayer
	-- IN THE STARTER PACK ONLY: where to get it, and the way there.
	if item.earn == "starter" and not owned(item.id) then
		local pack = ShopCatalog.get("StarterPack")
		local more = if pack and pack.tokens then (" with %d tokens"):format(pack.tokens) else ""
		confirm(("%s comes in the starter pack%s, once only."):format(item.name, more), "See it", function()
			ShopService.showTab("Passes")
		end)
		return
	end
	-- FOR EVERY MATERIAL FOUND: said what it takes.
	if item.earn == "materials" and not owned(item.id) then
		toast(("Stand on every material in the levels (%d) to get %s."):format(#ShopCatalog.MATERIALS, item.name))
		return
	end
	-- A BACKGROUND CRATE: opened (above), your odds said first.
	if item.kind == "crate" then
		openCrate(item)
		return
	end
	-- A BACKGROUND STILL IN THE CRATES: how often it comes, and the crate to open.
	if item.earn == "crate" and not owned(item.id) then
		local crate = ShopCatalog.get(ShopCatalog.CRATE.id)
		local rarity = ShopCatalog.RARITY[item.rarity or ""]
		toast(("%s comes out of the background crates, %s."):format(item.name, if rarity then rarity.word else "now and then"))
		if crate then
			openCrate(crate)
		end
		return
	end
	-- EARNED, NOT SOLD: said what it takes.
	if item.earn and not owned(item.id) then
		toast("Finish the story to get " .. item.name .. ".")
		return
	end
	-- ROBUX: a pass (bought once; the mythic background is one) or a product, in Roblox's own window. A background
	-- bought so, once yours, is put on and taken off like the rest (below).
	if item.robux and not (item.kind == "background" and owned(item.id)) then
		local passId = item.passId or 0
		local productId = item.productId or 0
		local isPass = item.passId ~= nil
		if isPass and owned(item.id) then
			toast("You have " .. item.name .. ".")
			return
		end
		if (isPass and passId == 0) or (not isPass and productId == 0) then
			toast(item.name .. " is not on sale yet.")
			return
		end
		if isPass then
			MarketplaceService:PromptGamePassPurchase(player, passId)
		else
			MarketplaceService:PromptProductPurchase(player, productId)
		end
		return
	end
	-- AN OWNED EMOTE: played, with the shop out of the way.
	if owned(item.id) and item.kind == "emote" then
		local module = script.Parent and script.Parent:FindFirstChild("EmoteService")
		ShopService.close()
		if module and module:IsA("ModuleScript") then
			pcall(function()
				(require(module) :: any).play(item.id)
			end)
		end
		return
	end
	-- TOKENS. Owned and wearable: put it on, or take it off.
	if owned(item.id) then
		if equipped(item) then
			ask("unequip", item.kind)
			toast(item.name .. " taken off.")
		else
			local result = ask("equip", item.id)
			if result and result.ok then
				toast(item.name .. " on.")
			end
		end
		return
	end
	local price = item.price :: number
	if tokens() < price then
		local short = price - tokens()
		confirm(("You need %d more tokens for %s."):format(short, item.name), "Get tokens", function()
			ShopService.showTab("Tokens")
		end)
		return
	end
	confirm(("Buy %s for %d tokens?"):format(item.name, price), "Buy", function()
		local result = ask("buy", item.id)
		if result and result.ok then
			-- (The grid has been drawn again from the server's answer, so the tile is a new one.)
			local fresh = ui.grid and ui.grid:FindFirstChild(item.id)
			pop(if fresh and fresh:IsA("GuiObject") then fresh else tile)
			toast(item.name .. " is yours.")
		elseif result and result.reason == "short" then
			toast("Not enough tokens.")
		end
	end)
end

-- ===== ONE TILE =====

-- ===== WHAT AN ITEM IS: the "i" on its tile =====
--
-- Hovered (a mouse) or pressed (a thumb, a controller): a small card by the tile with the item's name, its whole
-- description, and what a thing of its kind does. Pressed again, or anywhere else touched, it goes.
local KIND_WORDS: { [string]: string } = {
	trail = "A ribbon that follows you, for everyone to see. Wear one at a time.",
	aura = "A glow all around you, for everyone to see. Wear one at a time.",
	steps = "Prints where you walk, for everyone to see. Each fades after a moment.",
	sound = "A soft sound now and then as you walk in the lobby and the squish room. Never on a level, where the chunks speak.",
	emote = "Play it from the emote picker (G, or right on the D-pad), and anyone near you sees it.",
	pass = "A Roblox pass: bought once with Robux, and yours for good.",
	product = "Bought with Robux, and kept until you use it.",
	tokens = "Tokens to spend here, bought with Robux.",
	background = "A background for this shop, behind everything in it. Only you see it. Tap it to try it.",
	crate = "Opens to a background you do not have yet. Once you have all of one rarity, the rest share its chance.",
}
local EARN_WORDS: { [string]: string } = {
	story = "Not sold: finish the story to get it.",
	starter = "Not sold on its own: it comes with the starter pack.",
	materials = "Not sold: stand on every material in the levels to get it.",
	crate = "Not sold on its own: it comes out of the background crates.",
}

local function hideInfo()
	local info = ui.info
	if info then
		info.Visible = false
	end
	shop.infoFor = nil
	shop.infoHover = false
end

local function showInfo(item: any, anchor: GuiObject, hover: boolean)
	local info = ui.info
	local panel = ui.panel
	if not (info and panel) then
		return
	end
	shop.infoFor = item.id
	shop.infoHover = hover
	-- In the tab's colours.
	local fam: Family = shop.palette or family(shop.tab)
	if ui.infoEdge then
		ui.infoEdge.Color = fam.edge
	end
	ui.infoTitle.TextColor3 = fam.ink
	ui.infoKind.TextColor3 = fam.edge
	ui.infoTitle.Text = item.name
	local kind = if item.earn then EARN_WORDS[item.earn] else nil
	ui.infoKind.Text = kind or KIND_WORDS[item.kind] or ""
	ui.infoWords.Text = item.blurb .. "." .. (if item.kind == "crate" then " " .. ShopCatalog.crateOdds(owned) .. "." else "")
	info.Visible = true
	-- Beside the "i", inside the panel, once its height is known.
	task.defer(function()
		if not info.Visible or shop.infoFor ~= item.id then
			return
		end
		local rel = anchor.AbsolutePosition - panel.AbsolutePosition
		local size = info.AbsoluteSize
		local room = panel.AbsoluteSize
		local x = math.clamp(rel.X, 10, math.max(10, room.X - size.X - 10))
		local y = rel.Y + anchor.AbsoluteSize.Y + 4
		if y + size.Y > room.Y - 10 then
			y = math.max(10, rel.Y - size.Y - 4)
		end
		info.Position = UDim2.fromOffset(x, y)
	end)
end

local function makeTile(item: any, order: number): TextButton
	local t = shop.text
	local fam: Family = shop.palette or family(shop.tab)
	-- THE TILE is the button (a controller selects it; pressed, it tries the thing on). What you see is a card in the
	-- tab's colours on a lip of its deeper shade (the hundred-and-twenty-second pass): under the pointer the card lifts
	-- off its lip and its icon swells; pressed, it sinks onto the lip and springs back.
	local tile = Instance.new("TextButton")
	tile.Name = item.id
	tile.LayoutOrder = order
	tile.AutoButtonColor = false
	tile.Text = ""
	tile.BackgroundTransparency = 1
	tile.BorderSizePixel = 0
	tile.Selectable = true
	corner(tile, UDim.new(0, 18))
	local lip = Instance.new("Frame")
	lip.Name = "Lip"
	lip.BackgroundColor3 = fam.edge
	lip.BorderSizePixel = 0
	lip.Position = UDim2.new(0, 0, 0, TILE_LIP)
	lip.Size = UDim2.new(1, 0, 1, -TILE_LIP)
	lip.Parent = tile
	corner(lip, UDim.new(0, 18))
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.BackgroundColor3 = LOOK.white
	card.BorderSizePixel = 0
	card.Size = UDim2.new(1, 0, 1, -TILE_LIP)
	card.Parent = tile
	corner(card, UDim.new(0, 18))
	local outline = stroke(card, fam.edge, 3)
	-- LIT FROM ABOVE: white at the top of the card, fading into the tab's own pale colour.
	local light = Instance.new("UIGradient")
	light.Rotation = 90
	light.Color = ColorSequence.new(LOOK.white, fam.pale)
	light.Parent = card
	local lift = Instance.new("UIScale")
	lift.Parent = tile
	local swell: UIScale? = nil -- the icon's, made with it below
	local rest, raised, sunk = UDim2.new(0, 0, 0, 0), UDim2.new(0, 0, 0, -2), UDim2.new(0, 0, 0, TILE_LIP - 1)
	local quick = TweenInfo.new(0.14, Enum.EasingStyle.Quad)
	local spring = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	tile.MouseEnter:Connect(function()
		TweenService:Create(lift, quick, { Scale = 1.03 }):Play()
		TweenService:Create(card, quick, { Position = raised }):Play()
		if swell then
			TweenService:Create(swell, spring, { Scale = 1.08 }):Play()
		end
	end)
	tile.MouseLeave:Connect(function()
		TweenService:Create(lift, quick, { Scale = 1 }):Play()
		TweenService:Create(card, quick, { Position = rest }):Play()
		if swell then
			TweenService:Create(swell, quick, { Scale = 1 }):Play()
		end
	end)
	tile.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(card, TweenInfo.new(0.06, Enum.EasingStyle.Quad), { Position = sunk }):Play()
		end
	end)
	tile.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			TweenService:Create(card, spring, { Position = rest }):Play()
		end
	end)

	-- (cellH is the card's, over its lip.)
	local cellW, cellH = shop.cell.X, shop.cell.Y - TILE_LIP
	local priceH = math.max(MIN_TOUCH + 5, math.floor(cellH * 0.2))
	-- (A little smaller than it was, for bigger words under it; the hundred-and-twenty-third pass, from your test: "when I
	-- hover over the icons in the shop, they get bigger which is cool but the text gets covered, work on sizing a bit".)
	local iconD = math.floor(math.min(cellW * 0.46, cellH * 0.34))
	local top = math.floor(10 * t)
	-- ITS STAGE: a soft wash of the item's own colour behind the icon, so each tile has its colour.
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.AnchorPoint = Vector2.new(0.5, 0)
	stage.Position = UDim2.new(0.5, 0, 0, top - 4)
	stage.Size = UDim2.new(1, -16, 0, iconD + 8)
	stage.BackgroundColor3 = item.colour
	stage.BackgroundTransparency = 0.72
	stage.BorderSizePixel = 0
	stage.ClipsDescendants = true
	stage.Parent = card
	corner(stage, UDim.new(0, 14))
	-- A SUNBURST behind it, turning slowly: rays of the item's colour gone pale, fading out toward their ends.
	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.new(0.5, 0, 0, 4 + iconD / 2)
	rays.Size = UDim2.fromOffset(iconD * 2.4, iconD * 2.4)
	rays.BackgroundTransparency = 1
	rays.Parent = stage
	for k = 0, 5 do
		local ray = Instance.new("Frame")
		ray.Name = "Ray"
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.new(0, math.floor(iconD * 0.24), 1, 0)
		ray.Rotation = k * 30
		ray.BackgroundColor3 = item.colour:Lerp(LOOK.white, 0.55)
		ray.BorderSizePixel = 0
		ray.Parent = rays
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.45),
			NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(0.7, 0.45), NumberSequenceKeypoint.new(1, 1) })
		fade.Parent = ray
	end
	table.insert(shop.rays, rays)

	local icon = Instance.new("Frame")
	icon.Name = "Icon"
	-- Held by its middle, so swelling under the pointer it grows evenly all round, into the gap under it and never over
	-- the name (it grew downward from its top before).
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.new(0.5, 0, 0, top + iconD / 2)
	icon.Size = UDim2.fromOffset(iconD, iconD)
	icon.BackgroundColor3 = item.colour
	icon.BorderSizePixel = 0
	icon.Parent = card
	corner(icon, UDim.new(0.5, 0))
	stroke(icon, item.accent, 3)
	drawIcon(icon, item)
	local iconSwell = Instance.new("UIScale")
	iconSwell.Parent = icon
	swell = iconSwell

	-- THE WORDS, right under the icon, in the shop's own rounded letters: the name, and under it the description
	-- shrinking to fit its room (never cut off in the middle of a word). The whole of it is on the "i".
	local nameY = top + iconD + math.floor(8 * t)
	local nameH = math.floor(26 * t)
	local name = label(card, "ItemName", item.name, CHUNKY, math.floor(20 * t), fam.ink)
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 0, nameY)
	name.Size = UDim2.new(1, -16, 0, nameH)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local blurbY = nameY + nameH + 2
	local blurb = label(card, "Blurb", item.blurb, CHUNKY, math.floor(15 * t), fam.edge)
	blurb.AnchorPoint = Vector2.new(0.5, 0)
	blurb.Position = UDim2.new(0.5, 0, 0, blurbY)
	blurb.Size = UDim2.new(1, -18, 0, math.max(14, cellH - priceH - 14 - blurbY))
	blurb.TextWrapped = true
	blurb.TextScaled = true
	blurb.TextYAlignment = Enum.TextYAlignment.Top
	local fit = Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = math.floor(16 * t)
	fit.MinTextSize = 10
	fit.Parent = blurb

	-- THE "i": what this is, in full. Its press area is a thumb's; the circle in it is small.
	local more = Instance.new("TextButton")
	more.Name = "Info"
	more.AutoButtonColor = false
	more.Text = ""
	more.BackgroundTransparency = 1
	more.Position = UDim2.fromOffset(2, 2)
	more.Size = UDim2.fromOffset(MIN_TOUCH, MIN_TOUCH)
	more.Parent = card
	local dot = label(more, "Dot", "i", CHUNKY, math.floor(17 * t), LOOK.white)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(math.floor(26 * t), math.floor(26 * t))
	dot.BackgroundTransparency = 0
	dot.BackgroundColor3 = fam.edge
	corner(dot, UDim.new(0.5, 0))
	more.MouseEnter:Connect(function()
		showInfo(item, more, true)
	end)
	more.MouseLeave:Connect(function()
		if shop.infoHover and shop.infoFor == item.id then
			hideInfo()
		end
	end)
	more.Activated:Connect(function()
		uiSound("buttonClick", 0.35)
		if shop.infoFor == item.id and not shop.infoHover then
			hideInfo()
		else
			showInfo(item, more, false)
		end
	end)

	-- The badge, top right: Soon, Owned, or On.
	local chances = if item.id == "SecondChance" and shop.data and typeof(shop.data.chances) == "number" then shop.data.chances else 0
	local badgeText = if item.soon then "Soon" elseif chances > 0 then ("%d left"):format(chances)
		elseif equipped(item) then "On" elseif owned(item.id) then "Owned" elseif item.once then "Once only"
		elseif item.kind == "tokens" and item.id == bestPack() then "Best value" else nil
	if badgeText then
		local badge = label(card, "Badge", badgeText, CHUNKY, math.max(12, math.floor(13 * t)),
			if item.soon then LOOK.soonInk else LOOK.white)
		badge.BackgroundTransparency = 0
		badge.BackgroundColor3 = if item.soon then LOOK.soon elseif badgeText == "Best value" then LOOK.robuxEdge else fam.edge
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, -8, 0, 8)
		badge.AutomaticSize = Enum.AutomaticSize.X
		badge.Size = UDim2.new(0, 0, 0, math.floor(22 * t))
		corner(badge, UDim.new(0.5, 0))
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = badge
	end
	-- ITS RARITY (a background): a pill in the rarity's colour, on the foot of its icon.
	local rarity = if item.rarity then ShopCatalog.RARITY[item.rarity] else nil
	if rarity then
		local pill = label(card, "Rarity", rarity.name, CHUNKY, math.max(12, math.floor(13 * t)), LOOK.white)
		pill.BackgroundTransparency = 0
		pill.BackgroundColor3 = rarity.colour
		pill.AnchorPoint = Vector2.new(0.5, 0.5)
		pill.Position = UDim2.new(0.5, 0, 0, top + iconD - 4)
		pill.AutomaticSize = Enum.AutomaticSize.X
		pill.Size = UDim2.new(0, 0, 0, math.floor(20 * t))
		pill.ZIndex = 3
		corner(pill, UDim.new(0.5, 0))
		stroke(pill, LOOK.white, 2)
		local pillPad = Instance.new("UIPadding")
		pillPad.PaddingLeft = UDim.new(0, 8)
		pillPad.PaddingRight = UDim.new(0, 8)
		pillPad.Parent = pill
	end
	-- A GLEAM RUNNING ROUND THE OUTLINE of the rare ones (an epic background or better) and of what is sold for Robux
	-- (but the token packs, a whole tab of them): the outline in its colour, with a white light turning round it.
	local rare = item.rarity == "epic" or item.rarity == "legendary" or item.rarity == "mythic"
	local gleam = if rare and rarity then rarity.colour elseif item.robux and item.kind ~= "tokens" then LOOK.token else nil
	if gleam then
		outline.Color = LOOK.white
		outline.Thickness = 4
		local run = Instance.new("UIGradient")
		run.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, gleam),
			ColorSequenceKeypoint.new(0.4, gleam),
			ColorSequenceKeypoint.new(0.5, LOOK.white),
			ColorSequenceKeypoint.new(0.6, gleam),
			ColorSequenceKeypoint.new(1, gleam),
		})
		run.Parent = outline
		table.insert(shop.gleams, run)
	end

	-- THE PRICE: amber for tokens, green for Robux, grey for soon, the tab's own colours once it is yours.
	local fill, edge, ink, words
	if item.soon then
		fill, edge, ink = LOOK.soon, LOOK.soonEdge, LOOK.soonInk
		words = if item.price then tostring(item.price) else ("R$ " .. tostring(item.robux))
	elseif item.robux and not (item.kind == "background" and owned(item.id)) then
		if item.passId ~= nil and owned(item.id) then
			fill, edge, ink, words = fam.pale, fam.edge, fam.ink, "Owned"
		else
			fill, edge, ink, words = LOOK.robux, LOOK.robuxEdge, LOOK.robuxInk, "R$ " .. tostring(item.robux)
		end
	elseif item.kind == "crate" and shop.data and shop.data.crates == false then
		-- Not offered where you are (Roblox's policy for paid random items).
		fill, edge, ink, words = LOOK.soon, LOOK.soonEdge, LOOK.soonInk, "Not here"
	elseif item.kind == "crate" and ShopCatalog.crateDone(owned) then
		fill, edge, ink, words = LOOK.soon, LOOK.soonEdge, LOOK.soonInk, "All yours"
	elseif item.earn == "crate" and not owned(item.id) then
		-- In the crates: where it comes from, where a price would be.
		fill, edge, ink, words = LOOK.soon, LOOK.soonEdge, LOOK.soonInk, "In crates"
	elseif item.earn == "starter" and not owned(item.id) then
		-- In the starter pack only: where it comes from, where a price would be.
		fill, edge, ink, words = LOOK.robux, LOOK.robuxEdge, LOOK.robuxInk, "Starter pack"
	elseif item.earn == "materials" and not owned(item.id) then
		-- For every material found: what it takes, where a price would be.
		fill, edge, ink, words = LOOK.soon, LOOK.soonEdge, LOOK.soonInk, ("Find all %d"):format(#ShopCatalog.MATERIALS)
	elseif item.earn and not owned(item.id) then
		-- Earned, never sold: what it takes, where a price would be.
		fill, edge, ink, words = LOOK.soon, LOOK.soonEdge, LOOK.soonInk, "Finish the story"
	elseif owned(item.id) and item.kind == "emote" then
		fill, edge, ink, words = fam.fill, fam.edge, fam.ink, "Play"
	elseif owned(item.id) then
		-- A sound pack is used, not worn.
		local sound = item.kind == "sound"
		if equipped(item) then
			fill, edge, ink, words = fam.edge, fam.ink, LOOK.white, if sound then "Stop" else "Take off"
		else
			fill, edge, ink, words = fam.fill, fam.edge, fam.ink, if sound then "Use" else "Put on"
		end
	else
		fill, edge, ink, words = LOOK.token, LOOK.tokenEdge, LOOK.tokenInk, tostring(item.price)
	end
	local holder, face, content = squishy(card, "Price", fill, edge)
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0.5, 0, 1, -8)
	holder.Size = UDim2.new(1, -20, 0, priceH)
	if item.price and not owned(item.id) and fill == LOOK.token then
		coin(content, math.floor(18 * t))
		-- ONE YOU CAN PAY breathes, gently: what you can have says so.
		if not item.soon and tokens() >= item.price then
			local breath = Instance.new("UIScale")
			breath.Parent = content
			table.insert(shop.breathe, breath)
		end
	end
	-- A SHEEN sweeping across the card now and then, each tile a beat after the one before it.
	local sheen = Instance.new("Frame")
	sheen.Name = "Sheen"
	sheen.Size = UDim2.fromScale(1, 1)
	sheen.BackgroundColor3 = LOOK.white
	sheen.BorderSizePixel = 0
	sheen.ZIndex = 4
	sheen.Parent = card
	corner(sheen, UDim.new(0, 18))
	local sweep = Instance.new("UIGradient")
	sweep.Rotation = 20
	sweep.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1),
		NumberSequenceKeypoint.new(0.5, 0.62), NumberSequenceKeypoint.new(0.58, 1), NumberSequenceKeypoint.new(1, 1) })
	sweep.Offset = Vector2.new(-2, 0)
	sweep.Parent = sheen
	table.insert(shop.sheens, { grad = sweep, phase = (order % 12) * 0.38 })
	buttonWords(content, words, ink, math.floor(19 * t))
	face.Activated:Connect(function()
		pressPrice(item, tile)
	end)
	-- THE TILE ITSELF: try it on (a trail or an aura on you, prints at your feet, three steps to hear).
	tile.Activated:Connect(function()
		uiSound("buttonClick", 0.35)
		if item.kind == "emote" then
			local module = script.Parent and script.Parent:FindFirstChild("EmoteService")
			if module and module:IsA("ModuleScript") then
				pcall(function()
					(require(module) :: any).preview(item.id)
				end)
			end
			toast(item.name .. ": watch yourself behind the shop.")
		elseif item.kind == "steps" or item.kind == "sound" then
			local module = script.Parent and script.Parent:FindFirstChild("StepService")
			if module and module:IsA("ModuleScript") then
				pcall(function()
					(require(module) :: any).preview(item)
				end)
			end
			toast(if item.kind == "steps" then item.name .. ": look at your feet." else "Listen: " .. item.name .. ".")
		elseif item.kind == "trail" or item.kind == "aura" then
			if shop.preview == item.id then
				wearPreview(nil)
				toast("Preview off.")
			else
				wearPreview(item)
				toast("Trying on " .. item.name .. ". Close the shop to see it from behind.")
			end
		elseif item.kind == "background" then
			-- TRIED BEHIND THE SHOP until it closes, yours or not.
			if ShopLook and item.theme and ShopLook.show(item.theme) then
				toast("Trying " .. item.name .. " behind the shop.")
			end
		elseif item.kind == "crate" then
			toast(ShopCatalog.crateOdds(owned) .. ".")
		else
			toast(item.blurb .. ".")
		end
	end)
	-- POPPED IN, one after another, when a tab has just opened (not when the server's answer draws it again).
	if shop.fresh then
		lift.Scale = 0
		task.delay(math.min(order - 1, 12) * 0.035, function()
			if lift.Parent then
				TweenService:Create(lift, TweenInfo.new(0.34, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		end)
	end
	return tile
end

-- ===== THE GRID AND THE TABS =====

-- THE TABS, painted for the one chosen (the hundred-and-twenty-second pass): every tab in its own colour on a lip of its
-- deeper shade; the chosen one deep with white words, lifted a little over the rest and bounced as it is chosen; one
-- under the pointer lifted a little too.
local function settleTab(part: any)
	local want = if part.button.Name == shop.tab then 1.06 elseif part.hovered then 1.03 else 1
	TweenService:Create(part.scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad), { Scale = want }):Play()
end

local function paintTabs()
	for _, part in ipairs(ui.tabParts or {}) do
		local button = part.button
		local chosen = button.Name == shop.tab
		local fam = family(button.Name)
		button.BackgroundColor3 = if chosen then fam.ink else fam.edge
		part.top.BackgroundColor3 = if chosen then fam.edge else fam.fill
		part.edge.Color = if chosen then fam.ink else fam.edge
		part.words.TextColor3 = if chosen then LOOK.white else fam.ink
		if chosen and not part.chosen then
			part.scale.Scale = 0.86
			TweenService:Create(part.scale, TweenInfo.new(0.38, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1.06 }):Play()
		elseif part.chosen and not chosen then
			settleTab(part)
		end
		part.chosen = chosen
	end
end

-- The chosen tab scrolled into the strip when it is off either end of it (a controller's bumpers, a narrow screen).
local function tabIntoView(button: GuiObject)
	local strip = ui.tabs
	if not strip then
		return
	end
	local s = math.max(ui.bounce.Scale, 0.01)
	local at = strip.CanvasPosition.X
	local left = (button.AbsolutePosition.X - strip.AbsolutePosition.X) / s + at
	local right = left + button.AbsoluteSize.X / s
	local view = strip.AbsoluteSize.X / s
	local want = at
	if left - TAB_ROOM < at then
		want = left - TAB_ROOM
	elseif right + TAB_ROOM > at + view then
		want = right + TAB_ROOM - view
	end
	if want ~= at then
		TweenService:Create(strip, TweenInfo.new(0.25, Enum.EasingStyle.Quad),
			{ CanvasPosition = Vector2.new(math.max(0, want), 0) }):Play()
	end
end

render = function()
	local grid = ui.grid
	if not grid then
		return
	end
	hideInfo()
	for _, old in ipairs(grid:GetChildren()) do
		if old:IsA("GuiObject") then
			old:Destroy()
		end
	end
	local data = shop.data
	if ui.loading then
		ui.loading.Visible = not (data and data.ready)
	end
	-- THIS TAB'S COLOURS for everything drawn now; the rare tiles' gleams made afresh with them.
	local fam = family(shop.tab)
	shop.palette = fam
	table.clear(shop.gleams)
	table.clear(shop.rays)
	table.clear(shop.sheens)
	table.clear(shop.breathe)
	grid.ScrollBarImageColor3 = fam.edge
	local first: GuiObject? = nil
	for order, item in ipairs(ShopCatalog.inTab(shop.tab)) do
		-- BOUGHT ONCE (the starter pack): off Featured once it is yours, and still in its own tab, Owned.
		if not (shop.tab == "Featured" and item.once and owned(item.id)) then
			local tile = makeTile(item, order)
			tile.Parent = grid
			first = first or tile
		end
	end
	ui.firstTile = first
	shop.fresh = false
	shop.drawn = if data then drawnFrom(data) else nil
	-- EVERY TAB ITS OWN COLOUR (ShopLook.TAB_COLOURS, through family), the chosen one deeper with white words.
	paintTabs()
	-- HOW MANY OF THIS TAB ARE YOURS (of what can be had for good: not the token packs, a second chance or the crate).
	local progress = ui.progress
	if progress then
		local have, of = 0, 0
		for _, item in ipairs(ShopCatalog.inTab(shop.tab)) do
			if item.kind ~= "tokens" and item.kind ~= "product" and item.kind ~= "crate" and not item.soon then
				of += 1
				if owned(item.id) then
					have += 1
				end
			end
		end
		progress.Visible = of > 0 and shop.wide
		progress.BackgroundColor3 = fam.pale
		ui.progressEdge.Color = fam.edge
		ui.progressWords.Text = ("%d of %d yours"):format(have, of)
		ui.progressWords.TextColor3 = fam.ink
		ui.progressBar.BackgroundColor3 = fam.edge
		ui.progressFill.BackgroundColor3 = fam.edge
		TweenService:Create(ui.progressFill, TweenInfo.new(0.45, Enum.EasingStyle.Quad),
			{ Size = UDim2.fromScale(if of > 0 then have / of else 0, 1) }):Play()
	end
end

function ShopService.showTab(tab: string)
	if not table.find(ShopCatalog.TABS, tab) then
		return
	end
	-- (Its tiles pop in when it is another tab; the same one pressed again is only drawn again.)
	shop.fresh = shop.tab ~= tab
	shop.tab = tab
	closeConfirm()
	render()
	local grid = ui.grid
	if grid then
		grid.CanvasPosition = Vector2.zero
	end
	local index = table.find(ShopCatalog.TABS, tab)
	local part = if index and ui.tabParts then ui.tabParts[index] else nil
	if part and shop.open then
		tabIntoView(part.button)
	end
	if usingPad() and shop.open and ui.firstTile then
		GuiService.SelectedObject = ui.firstTile
	end
end

-- ===== THE LAYOUT, FOR THIS SCREEN =====

local function layout()
	local panel = ui.panel
	local camera = workspace.CurrentCamera
	if not (panel and camera) then
		return
	end
	-- THE SAFE AREA'S SIZE (the ScreenGui's own, inside the notches), or the whole screen until it has one.
	local safe = ui.screen.AbsoluteSize
	local view = if safe.X > 0 and safe.Y > 0 then safe else camera.ViewportSize
	local w = math.clamp(view.X - 24, 300, 960)
	local h = math.clamp(view.Y - 24, 260, 680)
	local t = math.clamp(math.min(view.X, view.Y) / 720, 0.8, 1.12)
	shop.text = t
	shop.cols = if w >= 840 then 4 elseif w >= 540 then 3 else 2
	panel.Size = UDim2.fromOffset(w, h)

	local headH = math.max(MIN_TOUCH + 8, math.floor(60 * t))
	local tabsH = math.max(MIN_TOUCH, math.floor(46 * t))
	shop.wide = w >= 640
	ui.header.Size = UDim2.new(1, -(28 + MIN_TOUCH + 16), 0, headH)
	ui.title.TextSize = math.floor(26 * t)
	ui.tokenWords.TextSize = math.floor(20 * t)
	ui.progressWords.TextSize = math.floor(16 * t)
	-- THE TABS' STRIP, TAB_ROOM bigger than its tabs all round (they sit inside it TAB_ROOM from every edge): a tab's
	-- outline, its lip and its lift are never cut off where the strip ends.
	local stripTop = headH + 12 - TAB_ROOM
	ui.tabs.Position = UDim2.new(0, 14 - TAB_ROOM, 0, stripTop)
	ui.tabs.Size = UDim2.new(1, -(28 - 2 * TAB_ROOM), 0, tabsH + 2 * TAB_ROOM)
	local discD = math.floor((tabsH - TAB_LIP) * 0.62)
	for _, part in ipairs(ui.tabParts) do
		part.words.TextSize = math.floor(17 * t)
		part.button.Size = UDim2.new(0, 0, 0, tabsH)
		part.disc.Size = UDim2.fromOffset(discD, discD)
		part.pad.PaddingLeft = UDim.new(0, 10 + discD + 8)
	end
	-- THE TRAY under the tabs, and the grid inside it with TILE_ROOM round its tiles.
	local trayTop = stripTop + tabsH + 2 * TAB_ROOM + 2
	ui.tray.Position = UDim2.new(0, 12, 0, trayTop)
	ui.tray.Size = UDim2.new(1, -24, 1, -(trayTop + 12))
	local gridTop = trayTop + 4
	ui.grid.Position = UDim2.new(0, 16, 0, gridTop)
	ui.grid.Size = UDim2.new(1, -36, 1, -(gridTop + 18))
	local gap = math.floor(12 * t)
	local inner = (w - 36) - 16 - 2 * TILE_ROOM -- the scroll bar's room, and the room round the tiles
	local cellW = math.floor((inner - gap * (shop.cols - 1)) / shop.cols)
	local cellH = math.floor(math.clamp(cellW * 1.2, 170, 300)) + TILE_LIP
	shop.cell = Vector2.new(cellW, cellH)
	ui.gridLayout.CellSize = UDim2.fromOffset(cellW, cellH)
	ui.gridLayout.CellPadding = UDim2.fromOffset(gap, gap)
	render()
end

-- ===== BUILDING IT =====

local function build()
	if ui.screen then
		return
	end
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "Shop"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 30
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- INSIDE THE SAFE AREA on every device: clear of notches, rounded corners and Roblox's own top bar.
	screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	screen.Enabled = false
	screen.Parent = playerGui
	ui.screen = screen

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.AutoButtonColor = false
	dim.Text = ""
	dim.Selectable = false
	dim.BackgroundColor3 = rgb(4, 30, 26)
	dim.BackgroundTransparency = 0.45
	dim.Size = UDim2.new(1, 0, 1, 0)
	dim.Parent = screen
	ui.dim = dim
	dim.Activated:Connect(function()
		ShopService.close()
	end)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundColor3 = LOOK.panel
	panel.BorderSizePixel = 0
	-- ACTIVE, so a press on the panel's own space stops here and does not fall through to the dim behind
	-- it (which closes the shop).
	panel.Active = true
	panel.Visible = false
	panel.Parent = screen
	corner(panel, UDim.new(0, 26))
	stroke(panel, LOOK.edge, 4)
	local bounce = Instance.new("UIScale")
	bounce.Parent = panel
	ui.panel = panel
	ui.bounce = bounce
	if ShopLook then
		ShopLook.attach(panel, screen)
	end
	-- (And the title in the background's colours whenever it changes.)
	if ShopLook then
		ShopLook.onRepaint(paintTitle)
	end

	-- THE HEADER: "Shop", your tokens (with + for more), and a big close button.
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Position = UDim2.new(0, 14, 0, 10)
	header.Parent = panel
	ui.header = header
	local headRow = Instance.new("UIListLayout")
	headRow.FillDirection = Enum.FillDirection.Horizontal
	headRow.VerticalAlignment = Enum.VerticalAlignment.Center
	headRow.Padding = UDim.new(0, 10)
	headRow.Parent = header

	local title = label(header, "Title", "Shop", CHUNKY, 26, LOOK.pinkInk)
	title.BackgroundTransparency = 0
	title.BackgroundColor3 = LOOK.pink
	title.AutomaticSize = Enum.AutomaticSize.X
	title.Size = UDim2.new(0, 0, 1, -6)
	title.LayoutOrder = 1
	corner(title, UDim.new(0.5, 0))
	ui.titleEdge = stroke(title, LOOK.pinkInk, 3)
	local titlePad = Instance.new("UIPadding")
	titlePad.PaddingLeft = UDim.new(0, 18)
	titlePad.PaddingRight = UDim.new(0, 18)
	titlePad.Parent = title
	ui.title = title

	local wallet = Instance.new("Frame")
	wallet.Name = "Wallet"
	wallet.BackgroundColor3 = LOOK.amber
	wallet.AutomaticSize = Enum.AutomaticSize.X
	wallet.Size = UDim2.new(0, 0, 1, -6)
	wallet.LayoutOrder = 2
	wallet.Parent = header
	corner(wallet, UDim.new(0.5, 0))
	stroke(wallet, LOOK.amberInk, 3)
	-- (Swelling as tokens come in, squeezing as they go: showTokens.)
	Instance.new("UIScale").Parent = wallet
	ui.wallet = wallet
	local walletRow = Instance.new("UIListLayout")
	walletRow.FillDirection = Enum.FillDirection.Horizontal
	walletRow.VerticalAlignment = Enum.VerticalAlignment.Center
	walletRow.Padding = UDim.new(0, 8)
	walletRow.Parent = wallet
	local walletPad = Instance.new("UIPadding")
	walletPad.PaddingLeft = UDim.new(0, 12)
	walletPad.PaddingRight = UDim.new(0, 6)
	walletPad.Parent = wallet
	coin(wallet, 22)
	local tokenWords = label(wallet, "Tokens", "...", CHUNKY, 20, LOOK.amberInk)
	tokenWords.AutomaticSize = Enum.AutomaticSize.X
	tokenWords.Size = UDim2.new(0, 0, 1, 0)
	tokenWords.LayoutOrder = 1
	ui.tokenWords = tokenWords
	local more = Instance.new("TextButton")
	more.Name = "More"
	more.LayoutOrder = 2
	more.AutoButtonColor = true
	more.Size = UDim2.fromOffset(MIN_TOUCH, MIN_TOUCH)
	more.BackgroundColor3 = LOOK.robux
	more.FontFace = CHUNKY
	more.TextSize = 24
	more.TextColor3 = LOOK.robuxInk
	more.Text = "+"
	more.Parent = wallet
	corner(more, UDim.new(0.5, 0))
	stroke(more, LOOK.robuxEdge, 3)
	more.Activated:Connect(function()
		uiSound("buttonClick", 0.5)
		ShopService.showTab("Tokens")
	end)

	-- HOW MANY OF THIS TAB ARE YOURS, beside your tokens on a wide screen: words and a bar, in the tab's colours.
	local progress = Instance.new("Frame")
	progress.Name = "Progress"
	progress.BackgroundColor3 = LOOK.tile
	progress.AutomaticSize = Enum.AutomaticSize.X
	progress.Size = UDim2.new(0, 0, 1, -10)
	progress.LayoutOrder = 3
	progress.Visible = false
	progress.Parent = header
	corner(progress, UDim.new(0.5, 0))
	ui.progressEdge = stroke(progress, LOOK.edge, 3)
	local progressRow = Instance.new("UIListLayout")
	progressRow.FillDirection = Enum.FillDirection.Horizontal
	progressRow.VerticalAlignment = Enum.VerticalAlignment.Center
	progressRow.Padding = UDim.new(0, 10)
	progressRow.SortOrder = Enum.SortOrder.LayoutOrder
	progressRow.Parent = progress
	local progressPad = Instance.new("UIPadding")
	progressPad.PaddingLeft = UDim.new(0, 14)
	progressPad.PaddingRight = UDim.new(0, 14)
	progressPad.Parent = progress
	local progressWords = label(progress, "Words", "", CHUNKY, 16, LOOK.ink)
	progressWords.AutomaticSize = Enum.AutomaticSize.X
	progressWords.Size = UDim2.new(0, 0, 1, 0)
	progressWords.LayoutOrder = 1
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromOffset(72, 10)
	bar.BackgroundColor3 = LOOK.edge
	bar.BackgroundTransparency = 0.75
	bar.BorderSizePixel = 0
	bar.LayoutOrder = 2
	bar.Parent = progress
	corner(bar, UDim.new(0.5, 0))
	local barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = LOOK.edge
	barFill.BorderSizePixel = 0
	barFill.Parent = bar
	corner(barFill, UDim.new(0.5, 0))
	ui.progress = progress
	ui.progressWords = progressWords
	ui.progressBar = bar
	ui.progressFill = barFill

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -12, 0, 12)
	close.Size = UDim2.fromOffset(MIN_TOUCH + 4, MIN_TOUCH + 4)
	close.BackgroundColor3 = LOOK.pink
	close.FontFace = CHUNKY
	close.TextSize = 24
	close.TextColor3 = LOOK.pinkInk
	close.Text = "X"
	close.Parent = panel
	corner(close, UDim.new(0.5, 0))
	stroke(close, LOOK.pinkInk, 3)
	close.Activated:Connect(function()
		ShopService.close()
	end)
	-- (Turning under the pointer.)
	close.MouseEnter:Connect(function()
		TweenService:Create(close, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 90 }):Play()
	end)
	close.MouseLeave:Connect(function()
		TweenService:Create(close, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Rotation = 0 }):Play()
	end)

	-- THE TABS: a strip that scrolls sideways when it does not fit, with TAB_ROOM inside it all round (the hundred-and-
	-- twenty-second pass, from your test: "resize the UI appropriately so that the edges of the categories are not cut
	-- off": their outlines were cut along the top and on the left). Each tab is a chunky key: the button is its lip, in
	-- its colour's deeper shade; on it the face, outlined, with a white disc and the tab's own little drawing; and the
	-- words. Pressed, the face sinks onto the lip and springs back.
	local tabs = Instance.new("ScrollingFrame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.BorderSizePixel = 0
	tabs.ScrollingDirection = Enum.ScrollingDirection.X
	tabs.ScrollBarThickness = 0
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabs.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabs.Selectable = false
	tabs.Parent = panel
	ui.tabs = tabs
	local tabRoom = Instance.new("UIPadding")
	tabRoom.PaddingLeft = UDim.new(0, TAB_ROOM)
	tabRoom.PaddingRight = UDim.new(0, TAB_ROOM)
	tabRoom.PaddingTop = UDim.new(0, TAB_ROOM)
	tabRoom.PaddingBottom = UDim.new(0, TAB_ROOM)
	tabRoom.Parent = tabs
	local tabRow = Instance.new("UIListLayout")
	tabRow.FillDirection = Enum.FillDirection.Horizontal
	tabRow.Padding = UDim.new(0, 12)
	tabRow.SortOrder = Enum.SortOrder.LayoutOrder
	tabRow.Parent = tabs
	-- (Room after the last one too, whether or not the canvas counts the padding on its right.)
	local tail = Instance.new("Frame")
	tail.Name = "Tail"
	tail.BackgroundTransparency = 1
	tail.LayoutOrder = #ShopCatalog.TABS + 1
	tail.Size = UDim2.fromOffset(TAB_ROOM, 1)
	tail.Parent = tabs
	ui.tabButtons = {}
	ui.tabParts = {}
	for order, tab in ipairs(ShopCatalog.TABS) do
		local fam = family(tab)
		local button = Instance.new("TextButton")
		button.Name = tab
		button.LayoutOrder = order
		button.AutoButtonColor = false
		button.AutomaticSize = Enum.AutomaticSize.X
		button.Text = ""
		button.BorderSizePixel = 0
		button.BackgroundColor3 = fam.edge
		button.Parent = tabs
		corner(button, UDim.new(0.5, 0))
		local top = Instance.new("Frame")
		top.Name = "Face"
		top.BackgroundColor3 = fam.fill
		top.BorderSizePixel = 0
		top.Size = UDim2.new(1, 0, 1, -TAB_LIP)
		top.Parent = button
		corner(top, UDim.new(0.5, 0))
		local edge = stroke(top, fam.edge, 2.5)
		local disc = Instance.new("Frame")
		disc.Name = "Disc"
		disc.AnchorPoint = Vector2.new(0, 0.5)
		disc.Position = UDim2.new(0, 10, 0.5, 0)
		disc.BackgroundColor3 = LOOK.white
		disc.BorderSizePixel = 0
		disc.Parent = top
		corner(disc, UDim.new(0.5, 0))
		tabGlyph(disc, tab, fam.edge)
		local words = label(button, "Words", tab, CHUNKY, 17, fam.ink)
		words.AutomaticSize = Enum.AutomaticSize.X
		words.Size = UDim2.new(0, 0, 1, -TAB_LIP)
		words.ZIndex = 2
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 44)
		pad.PaddingRight = UDim.new(0, 18)
		pad.Parent = words
		local scale = Instance.new("UIScale")
		scale.Parent = button
		local part = { button = button, top = top, edge = edge, disc = disc, words = words, pad = pad, scale = scale,
			hovered = false, chosen = false }
		local function sink(down: boolean)
			local to = if down then UDim2.new(0, 0, 0, TAB_LIP - 1) else UDim2.new(0, 0, 0, 0)
			local how = if down then TweenInfo.new(0.06, Enum.EasingStyle.Quad)
				else TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			TweenService:Create(top, how, { Position = to }):Play()
			TweenService:Create(words, how, { Position = to }):Play()
		end
		button.MouseEnter:Connect(function()
			part.hovered = true
			settleTab(part)
		end)
		button.MouseLeave:Connect(function()
			part.hovered = false
			settleTab(part)
			sink(false)
		end)
		button.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				sink(true)
			end
		end)
		button.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				sink(false)
			end
		end)
		button.Activated:Connect(function()
			if usingPad() then
				sink(true)
				task.delay(0.07, sink, false)
			end
			if ShopLook then
				ShopLook.tab(tab)
				if ShopLook.puff then
					ShopLook.puff(button, 0.5)
				end
			else
				uiSound("buttonClick", 0.4)
			end
			ShopService.showTab(tab)
		end)
		table.insert(ui.tabButtons, button)
		table.insert(ui.tabParts, part)
	end

	-- THE TRAY the tiles sit on (the hundred-and-twenty-second pass): a pale sheet over the background, in a wash of its
	-- colours, so what moves in it is behind the tiles and never under their words.
	local tray = Instance.new("Frame")
	tray.Name = "Tray"
	tray.BackgroundColor3 = LOOK.white
	tray.BackgroundTransparency = 0.25
	tray.BorderSizePixel = 0
	tray.ZIndex = 2
	tray.Parent = panel
	corner(tray, UDim.new(0, 20))
	local trayEdge = stroke(tray, LOOK.edge, 3)
	trayEdge.Transparency = 0.35
	ui.tray = tray
	ui.trayEdge = trayEdge

	-- THE GRID.
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.ScrollBarThickness = 8
	grid.ScrollBarImageColor3 = LOOK.edge
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new(0, 0, 0, 0)
	grid.Selectable = false
	grid.ZIndex = 3
	grid.Parent = panel
	ui.grid = grid
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	ui.gridLayout = gridLayout
	local gridPad = Instance.new("UIPadding")
	-- (TILE_ROOM round the tiles: a little more above, for a lifted one's outline, and below, for the lips.)
	gridPad.PaddingTop = UDim.new(0, TILE_ROOM + 3)
	gridPad.PaddingBottom = UDim.new(0, TILE_ROOM + 8)
	gridPad.PaddingLeft = UDim.new(0, TILE_ROOM)
	gridPad.PaddingRight = UDim.new(0, TILE_ROOM)
	gridPad.Parent = grid
	local loading = label(panel, "Loading", "Opening your shop...", CHUNKY, 20, LOOK.edge)
	loading.Name = "Loading"
	loading.AnchorPoint = Vector2.new(0.5, 0.5)
	loading.Position = UDim2.fromScale(0.5, 0.6)
	loading.Size = UDim2.new(1, 0, 0, 30)
	loading.Visible = false
	loading.ZIndex = 4
	ui.loading = loading

	-- THE "i" CARD: an item's whole description and what a thing of its kind does, by its tile.
	local info = Instance.new("Frame")
	info.Name = "Info"
	info.Active = true
	info.Visible = false
	info.ZIndex = 20
	info.BackgroundColor3 = LOOK.white
	info.Size = UDim2.new(0.6, 0, 0, 0)
	info.AutomaticSize = Enum.AutomaticSize.Y
	info.Parent = panel
	corner(info, UDim.new(0, 16))
	ui.infoEdge = stroke(info, LOOK.edge, 3)
	local infoMost = Instance.new("UISizeConstraint")
	infoMost.MaxSize = Vector2.new(300, 400)
	infoMost.Parent = info
	local infoList = Instance.new("UIListLayout")
	infoList.Padding = UDim.new(0, 4)
	infoList.SortOrder = Enum.SortOrder.LayoutOrder
	infoList.Parent = info
	local infoPad = Instance.new("UIPadding")
	infoPad.PaddingTop = UDim.new(0, 12)
	infoPad.PaddingBottom = UDim.new(0, 14)
	infoPad.PaddingLeft = UDim.new(0, 14)
	infoPad.PaddingRight = UDim.new(0, 14)
	infoPad.Parent = info
	local function infoLine(name: string, size: number, colour: Color3, order: number): TextLabel
		local line = label(info, name, "", CHUNKY, size, colour)
		line.ZIndex = 21
		line.LayoutOrder = order
		line.Size = UDim2.new(1, 0, 0, 0)
		line.AutomaticSize = Enum.AutomaticSize.Y
		line.TextWrapped = true
		line.TextXAlignment = Enum.TextXAlignment.Left
		return line
	end
	ui.infoTitle = infoLine("Title", 20, LOOK.ink, 1)
	ui.infoWords = infoLine("Words", 16, LOOK.ink, 2)
	ui.infoKind = infoLine("Kind", 14, LOOK.soft, 3)
	-- A tap or a click on the card puts it away.
	info.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			hideInfo()
		end
	end)
	ui.info = info
	grid:GetPropertyChangedSignal("CanvasPosition"):Connect(hideInfo)

	-- THE CONFIRM CARD, over the grid.
	local modal = Instance.new("TextButton")
	modal.Name = "Modal"
	modal.AutoButtonColor = false
	modal.Text = ""
	modal.Selectable = false
	modal.BackgroundColor3 = rgb(4, 30, 26)
	modal.BackgroundTransparency = 0.4
	modal.Size = UDim2.fromScale(1, 1)
	modal.Visible = false
	modal.ZIndex = 10
	modal.Parent = panel
	corner(modal, UDim.new(0, 26))
	modal.Activated:Connect(closeConfirm)
	ui.modal = modal
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.new(0.86, 0, 0, 210)
	card.BackgroundColor3 = LOOK.tile
	card.Active = true
	card.Parent = modal
	corner(card, UDim.new(0, 22))
	ui.cardEdge = stroke(card, LOOK.edge, 4)
	local cardMax = Instance.new("UISizeConstraint")
	cardMax.MaxSize = Vector2.new(440, 260)
	cardMax.Parent = card
	Instance.new("UIScale").Parent = card
	local message = label(card, "Message", "", CHUNKY, 22, LOOK.ink)
	message.Position = UDim2.new(0, 18, 0, 16)
	message.Size = UDim2.new(1, -36, 0, 96)
	message.TextWrapped = true
	-- (A long one, the crate's odds on a phone, shrinks to fit rather than running under the buttons.)
	message.TextScaled = true
	local messageFit = Instance.new("UITextSizeConstraint")
	messageFit.MaxTextSize = 22
	messageFit.MinTextSize = 13
	messageFit.Parent = message
	local yesHolder, yes, yesContent = squishy(card, "Yes", LOOK.token, LOOK.tokenEdge)
	yesHolder.AnchorPoint = Vector2.new(0, 1)
	yesHolder.Position = UDim2.new(0.52, 0, 1, -16)
	yesHolder.Size = UDim2.new(0.44, 0, 0, MIN_TOUCH + 9)
	ui.yes = yes
	ui.yesWords = buttonWords(yesContent, "Buy", LOOK.tokenInk, 21)
	yes.Activated:Connect(function()
		local action = ui.onYes
		closeConfirm()
		if action then
			action()
		end
	end)
	local noHolder, no, noContent = squishy(card, "No", LOOK.white, LOOK.edge)
	noHolder.AnchorPoint = Vector2.new(0, 1)
	noHolder.Position = UDim2.new(0.04, 0, 1, -16)
	noHolder.Size = UDim2.new(0.44, 0, 0, MIN_TOUCH + 9)
	buttonWords(noContent, "Not now", LOOK.ink, 21)
	no.Activated:Connect(function()
		uiSound("buttonClick", 0.4)
		closeConfirm()
	end)

	-- THE TOAST, at the bottom of the screen.
	local toastFrame = label(screen, "Toast", "", BODY, 17, LOOK.ink)
	toastFrame.Name = "Toast"
	toastFrame.Visible = false
	toastFrame.AnchorPoint = Vector2.new(0.5, 1)
	toastFrame.BackgroundTransparency = 0
	toastFrame.BackgroundColor3 = LOOK.tile
	toastFrame.AutomaticSize = Enum.AutomaticSize.X
	toastFrame.Size = UDim2.new(0, 0, 0, 40)
	toastFrame.ZIndex = 30
	corner(toastFrame, UDim.new(0.5, 0))
	ui.toastEdge = stroke(toastFrame, LOOK.edge, 3)
	local toastPad = Instance.new("UIPadding")
	toastPad.PaddingLeft = UDim.new(0, 18)
	toastPad.PaddingRight = UDim.new(0, 18)
	toastPad.Parent = toastFrame
	ui.toast = toastFrame
end

-- ===== OPEN AND CLOSE =====

local function playerControls(): any
	if shop.controls == nil then
		local ok, module = pcall(function()
			local playerModule = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
			return playerModule and (require(playerModule :: ModuleScript) :: any):GetControls()
		end)
		shop.controls = if ok and module then module else false
	end
	return if shop.controls then shop.controls else nil
end

-- STANDING STILL while a screen wants you to (the shop, the welcome): counted, so one of them closing does
-- not free you while another is still open.
local holds = 0
local function hold(on: boolean)
	local c = playerControls()
	if on then
		holds += 1
		if holds == 1 and c then
			pcall(function()
				c:Disable()
			end)
		end
	else
		holds = math.max(0, holds - 1)
		if holds == 0 and c then
			pcall(function()
				c:Enable()
			end)
		end
	end
end

function ShopService.open(tab: string?)
	build()
	if shop.open then
		if tab then
			ShopService.showTab(tab)
		end
		return
	end
	shop.open = true
	ui.screen.Enabled = true
	ui.panel.Visible = true
	shop.tab = tab or shop.tab
	-- (Its tiles pop in, and its tabs pop up one after another: the one it opens on counts as chosen already, so it
	-- pops up with the rest rather than bouncing first.)
	shop.fresh = true
	for _, part in ipairs(ui.tabParts) do
		part.chosen = part.button.Name == shop.tab
		part.hovered = false
	end
	layout()
	for k, part in ipairs(ui.tabParts) do
		part.scale.Scale = 0
		task.delay(0.08 + k * 0.03, function()
			if shop.open then
				TweenService:Create(part.scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Scale = if part.button.Name == shop.tab then 1.06 else 1 }):Play()
			end
		end)
	end
	-- The dark coming up behind it, and the gleams set turning round the rare tiles while it is open.
	ui.dim.BackgroundTransparency = 1
	TweenService:Create(ui.dim, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.45 }):Play()
	if ui.spin then
		ui.spin:Disconnect()
	end
	ui.spin = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local turn = (now * 80) % 360
		for _, run in ipairs(shop.gleams) do
			run.Rotation = turn
		end
		local slow = (now * 14) % 360
		for _, rays in ipairs(shop.rays) do
			rays.Rotation = slow
		end
		-- Each sheen crosses its card in 0.8 seconds, once every five.
		for _, sheen in ipairs(shop.sheens) do
			local p = ((now + sheen.phase) % 5) / 0.8
			sheen.grad.Offset = Vector2.new(if p < 1 then -1 + 2 * p else -2, 0)
		end
		local breath = 1 + 0.045 * math.sin(now * 3.2)
		for _, scale in ipairs(shop.breathe) do
			scale.Scale = breath
		end
	end)
	-- OPENING: squashed up out of almost nothing, a little past full size and a little turned, and settled; its theme
	-- painted behind it, the lid's pop, and a burst of its material (ShopLook).
	ui.bounce.Scale = 0.35
	ui.panel.Rotation = -4
	local swell = TweenService:Create(ui.bounce, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.04 })
	swell:Play()
	TweenService:Create(ui.panel, TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
	swell.Completed:Once(function()
		if shop.open then
			TweenService:Create(ui.bounce, TweenInfo.new(0.12, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
		end
	end)
	if ShopLook then
		ShopLook.opened()
	else
		uiSound("buttonClick", 0.6)
	end
	-- What the server says now, in case an update was missed.
	task.spawn(function()
		local remote = shop.stateRemote
		if remote then
			local ok, data = pcall(function()
				return remote:InvokeServer()
			end)
			if ok then
				accept(data)
			end
		end
	end)
	-- Standing still while you shop, on every device.
	hold(true)
	ContextActionService:BindActionAtPriority(CLOSE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			if ShopLook and ShopLook.crating() then
				ShopLook.dismiss()
			elseif ui.modal and ui.modal.Visible then
				closeConfirm()
			else
				ShopService.close()
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 20, Enum.KeyCode.Escape, Enum.KeyCode.ButtonB)
	ContextActionService:BindActionAtPriority(TAB_ACTION, function(_, inputState, input)
		if inputState == Enum.UserInputState.Begin then
			local at = table.find(ShopCatalog.TABS, shop.tab) or 1
			-- (And the arrow keys on a keyboard: the hundred-and-twenty-third pass, from your test: "I wanna be able to
			-- switch tabs by using arrow keys on my keyboard in the shop".)
			local back = input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.Left
			local step = if back then -1 else 1
			local nextTab = ShopCatalog.TABS[((at - 1 + step) % #ShopCatalog.TABS) + 1]
			if ShopLook then
				ShopLook.tab(nextTab)
			end
			ShopService.showTab(nextTab)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 20, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1, Enum.KeyCode.Left,
		Enum.KeyCode.Right)
	if usingPad() and ui.firstTile then
		GuiService.SelectedObject = ui.firstTile
	end
end

function ShopService.close()
	if not shop.open then
		return
	end
	shop.open = false
	closeConfirm()
	hideInfo()
	-- CLOSING: a squeeze, then away, turning as it goes, with the lid going back on and a last burst of its material.
	if ShopLook then
		ShopLook.closed()
	else
		uiSound("buttonClick", 0.4)
	end
	TweenService:Create(ui.dim, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
	if ui.spin then
		ui.spin:Disconnect()
		ui.spin = nil
	end
	local squeeze = TweenService:Create(ui.bounce, TweenInfo.new(0.06, Enum.EasingStyle.Quad), { Scale = 1.05 })
	squeeze:Play()
	local tween = TweenService:Create(ui.bounce, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{ Scale = 0.2 })
	squeeze.Completed:Once(function()
		if not shop.open then
			tween:Play()
			TweenService:Create(ui.panel, TweenInfo.new(0.2, Enum.EasingStyle.Quad), { Rotation = 5 }):Play()
		end
	end)
	tween.Completed:Once(function()
		if not shop.open then
			ui.panel.Visible = false
			ui.screen.Enabled = false
		end
	end)
	-- The try-on comes off unless you own and wear it (the server's copy stays either way).
	wearPreview(nil)
	ContextActionService:UnbindAction(CLOSE_ACTION)
	ContextActionService:UnbindAction(TAB_ACTION)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.screen) then
		GuiService.SelectedObject = nil
	end
	hold(false)
end

function ShopService.isOpen(): boolean
	return shop.open
end

-- ===== THE POST BOX: A CODE TO TYPE (the lobby's post box, ShopCatalog.CODES) =====
--
-- Its prompt opens a small card of your own: a box to type the code in, "Post it", and a line saying what came of
-- it. The server decides (ShopRequest "code"); a code that pays is told by the usual pill. Closes on B, Escape or
-- "Close", and lets go of a controller's selection.
local CODE_CLOSE_ACTION = "CodeBoxClose"
local CODE_WORDS: { [string]: string } = {
	unknown = "That code isn't one we know. Check the spelling.",
	used = "You've posted that code already.",
	ended = "That code has ended.",
	loading = "Your save is still loading. Try again in a moment.",
	busy = "One moment, then try again.",
}
local codes: { [string]: any } = {}

local function closeCodes()
	local screen = codes.screen
	if not (screen and screen.Enabled) then
		return
	end
	screen.Enabled = false
	ContextActionService:UnbindAction(CODE_CLOSE_ACTION)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(screen) then
		GuiService.SelectedObject = nil
	end
	hold(false)
end

local function buildCodes()
	if codes.screen then
		return
	end
	local codeScreen = Instance.new("ScreenGui")
	codeScreen.Name = "CodeBox"
	codeScreen.ResetOnSpawn = false
	codeScreen.DisplayOrder = 31
	-- INSIDE THE SAFE AREA, like the shop.
	codeScreen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	codeScreen.Enabled = false
	codeScreen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	codes.screen = codeScreen
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.new(0.86, 0, 0, 236)
	card.BackgroundColor3 = LOOK.tile
	card.Active = true
	card.Parent = codeScreen
	corner(card, UDim.new(0, 22))
	stroke(card, LOOK.edge, 4)
	local codeMost = Instance.new("UISizeConstraint")
	codeMost.MaxSize = Vector2.new(400, 236)
	codeMost.Parent = card
	local title = label(card, "Title", "Post a code", CHUNKY, 24, LOOK.ink)
	title.Position = UDim2.new(0, 18, 0, 14)
	title.Size = UDim2.new(1, -36, 0, 30)
	local box = Instance.new("TextBox")
	box.Name = "Code"
	box.Position = UDim2.new(0, 18, 0, 52)
	box.Size = UDim2.new(1, -36, 0, MIN_TOUCH + 6)
	box.BackgroundColor3 = LOOK.white
	box.FontFace = CHUNKY
	box.TextSize = 22
	box.TextColor3 = LOOK.ink
	box.PlaceholderText = "Type a code"
	box.PlaceholderColor3 = LOOK.soonInk
	box.ClearTextOnFocus = false
	box.Text = ""
	box.Parent = card
	corner(box, UDim.new(0, 12))
	stroke(box, LOOK.edge, 3)
	codes.box = box
	local said = label(card, "Said", "", BODY, 17, LOOK.ink)
	said.Position = UDim2.new(0, 18, 0, 108)
	said.Size = UDim2.new(1, -36, 0, 44)
	said.TextWrapped = true
	codes.said = said
	local postHolder, post, postContent = squishy(card, "Post", LOOK.token, LOOK.tokenEdge)
	postHolder.AnchorPoint = Vector2.new(0, 1)
	postHolder.Position = UDim2.new(0.52, 0, 1, -16)
	postHolder.Size = UDim2.new(0.44, 0, 0, MIN_TOUCH + 9)
	buttonWords(postContent, "Post it", LOOK.tokenInk, 21)
	local shutHolder, shut, shutContent = squishy(card, "Close", LOOK.white, LOOK.edge)
	shutHolder.AnchorPoint = Vector2.new(0, 1)
	shutHolder.Position = UDim2.new(0.04, 0, 1, -16)
	shutHolder.Size = UDim2.new(0.44, 0, 0, MIN_TOUCH + 9)
	buttonWords(shutContent, "Close", LOOK.ink, 21)
	shut.Activated:Connect(function()
		uiSound("buttonClick", 0.4)
		closeCodes()
	end)
	local function send()
		if box.Text == "" then
			said.Text = "Type the code first."
			return
		end
		uiSound("buttonClick", 0.5)
		said.Text = "Posting..."
		local result = ask("code", box.Text)
		if result and result.ok then
			box.Text = ""
			said.Text = "Posted. The tokens are yours."
		elseif result then
			said.Text = CODE_WORDS[tostring(result.reason)] or "That did not work. Try again in a moment."
		else
			said.Text = "The post box did not answer. Try again in a moment."
		end
	end
	post.Activated:Connect(send)
	box.FocusLost:Connect(function(enter: boolean)
		if enter then
			send()
		end
	end)
end

function ShopService.openCodes()
	buildCodes()
	local screen = codes.screen
	if not screen or screen.Enabled then
		return
	end
	screen.Enabled = true
	codes.said.Text = "Codes come from our posts. Each one works once."
	uiSound("buttonClick", 0.6)
	hold(true)
	ContextActionService:BindActionAtPriority(CODE_CLOSE_ACTION, function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			closeCodes()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 20, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)
	if usingPad() then
		GuiService.SelectedObject = codes.box
	end
end

function ShopService.codesOpen(): boolean
	return codes.screen ~= nil and codes.screen.Enabled == true
end

-- ===== TOKENS EARNED, said at the end of a run =====

local function earned(amount: any, info: any)
	if typeof(amount) ~= "number" then
		return
	end
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui"):FindFirstChild("TokenPop")
	if not gui then
		local made = Instance.new("ScreenGui")
		made.Name = "TokenPop"
		made.ResetOnSpawn = false
		made.DisplayOrder = 24
		made.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
		made.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		gui = made
	end
	local pill = Instance.new("Frame")
	pill.Name = "Earned"
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, 80)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.Size = UDim2.new(0, 0, 0, 52)
	pill.BackgroundColor3 = LOOK.amber
	pill.Parent = gui
	corner(pill, UDim.new(0.5, 0))
	stroke(pill, LOOK.amberInk, 3)
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 10)
	row.Parent = pill
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 18)
	pad.Parent = pill
	coin(pill, 26)
	local reasons = {}
	local story = type(info) == "table" and info.story == true
	if story then
		table.insert(reasons, "Story complete")
	end
	if type(info) == "table" and info.trueEnding == true then
		table.insert(reasons, "The true ending")
	end
	if type(info) == "table" then
		if info.hardcore then
			table.insert(reasons, "Hardcore")
		end
		if info.best then
			table.insert(reasons, "New best")
		end
		if info.friend then
			table.insert(reasons, "With a friend")
		end
		if info.starter then
			table.insert(reasons, "Starter pack")
		end
		if typeof(info.code) == "string" then
			table.insert(reasons, "Code " .. info.code)
		end
		local materials = tonumber(info.materials) or 0
		if materials == 1 then
			table.insert(reasons, "New material")
		elseif materials > 1 then
			table.insert(reasons, ("%d new materials"):format(materials))
		end
		local challenges = tonumber(info.challenges) or 0
		if challenges == 1 then
			table.insert(reasons, "Challenge done")
		elseif challenges > 1 then
			table.insert(reasons, ("%d challenges done"):format(challenges))
		end
		if info.double then
			table.insert(reasons, "2x")
		end
		if info.daily then
			table.insert(reasons, ("Daily chest, day %d"):format(tonumber(info.streak) or 1))
		end
		if info.cache then
			table.insert(reasons, "Hidden cache")
		end
	end
	local ribbon = if type(info) == "table" and info.ribbon then "  and the green ribbon (Trails)" else ""
	if type(info) == "table" and info.trueEnding == true then
		ribbon = "  and the key holder's plaque"
	end
	if type(info) == "table" and type(info.gift) == "string" then
		ribbon = ("  and the %s trail"):format(string.lower(info.gift))
	end
	local words = label(pill, "Words", ("+%d tokens"):format(amount) .. (if #reasons > 0 then "  (" .. table.concat(reasons, ", ") .. ")" else "")
		.. ribbon, CHUNKY, 22, LOOK.amberInk)
	words.AutomaticSize = Enum.AutomaticSize.X
	words.Size = UDim2.new(0, 0, 1, 0)
	words.LayoutOrder = 1
	task.delay(1.2, function()
		uiSound("bubblePop", 0.6)
		-- The story's bonus comes with its last level's own: it stands above that one rather than on it.
		TweenService:Create(pill, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 1, if story then -92 else -28) }):Play()
		task.delay(4.5, function()
			local out = TweenService:Create(pill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 1, 80) })
			out:Play()
			out.Completed:Once(function()
				pill:Destroy()
			end)
		end)
	end)
end

-- ===== STARTING =====

-- THE VIP BADGES' SHINE (EconomyService makes the badge, over a VIP player's head): every few seconds a light sweeps
-- across each one, on this screen. Their own part of the game: nothing to do with the shop being open.
local function shineVipBadges()
	task.spawn(function()
		while true do
			task.wait(3.2)
			for _, player in ipairs(Players:GetPlayers()) do
				local head = player.Character and player.Character:FindFirstChild("Head")
				local badge = head and head:FindFirstChild("VipTag")
				local pill = badge and badge:FindFirstChild("Pill")
				local shine = pill and pill:FindFirstChild("Shine")
				local sweep = shine and shine:FindFirstChild("Sweep")
				if sweep and sweep:IsA("UIGradient") and badge:IsA("BillboardGui") and badge.Enabled then
					sweep.Offset = Vector2.new(-1, 0)
					TweenService:Create(sweep, TweenInfo.new(0.75, Enum.EasingStyle.Sine), { Offset = Vector2.new(1, 0) }):Play()
				end
			end
		end
	end)
end

function ShopService.start()
	shineVipBadges()
	local events = ReplicatedStorage:WaitForChild("RemoteEvents")
	local functions = ReplicatedStorage:WaitForChild("RemoteFunctions")
	shop.requestRemote = functions:WaitForChild("ShopRequest", 20) :: RemoteFunction?
	shop.stateRemote = functions:WaitForChild("ShopState", 20) :: RemoteFunction?
	local update = events:WaitForChild("ShopUpdate", 20)
	local earnedEvent = events:WaitForChild("TokensEarned", 20)
	if not (shop.requestRemote and shop.stateRemote and update and earnedEvent) then
		warn("ShopService: the shop's remotes are missing (ShopRequest, ShopState, ShopUpdate, TokensEarned). The "
			.. "server Bootstrap makes them: paste src/Server/Bootstrap.server.lua.")
		return
	end
	build()
	;(update :: RemoteEvent).OnClientEvent:Connect(accept)
	;(earnedEvent :: RemoteEvent).OnClientEvent:Connect(earned)
	-- THE KIOSK'S PROMPT (Roblox's own): heard here, so the server does nothing to open a shop.
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if prompt.Name == "ShopPrompt" and who == Players.LocalPlayer then
			ShopService.open()
		elseif prompt.Name == "CodePrompt" and who == Players.LocalPlayer then
			ShopService.openCodes()
		end
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if shop.open then
				layout()
			end
		end)
	end
	-- VIP IN CHAT: a tag before the name of anyone with the pass.
	local chat = game:GetService("TextChatService")
	pcall(function()
		chat.OnIncomingMessage = function(message: TextChatMessage)
			local props = Instance.new("TextChatMessageProperties")
			local source = message.TextSource
			local who = source and Players:GetPlayerByUserId(source.UserId)
			if who and who:GetAttribute("VIP") then
				props.PrefixText = "<font color=\"#AFA9EC\">[VIP]</font> " .. message.PrefixText
			end
			return props
		end
	end)
	task.spawn(function()
		local ok, data = pcall(function()
			return (shop.stateRemote :: RemoteFunction):InvokeServer()
		end)
		if ok then
			accept(data)
		end
	end)
	print("ShopService: running, " .. ShopService.VERSION)
end

-- THE KIT, for the other screens in this style (OnboardingService's welcome): one look, one button.
ShopService.kit = {
	LOOK = LOOK,
	CHUNKY = CHUNKY,
	BODY = BODY,
	MIN_TOUCH = MIN_TOUCH,
	corner = corner,
	stroke = stroke,
	label = label,
	squishy = squishy,
	buttonWords = buttonWords,
	coin = coin,
	sound = uiSound,
	usingPad = usingPad,
	controls = playerControls,
	hold = hold,
}

ShopService.STAMP = "9fa2efc2"
return ShopService
