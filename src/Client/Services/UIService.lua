--!strict
-- StarterPlayerScripts/Services/UIService.lua
-- Mode indicator, hardcore clock, leaderboard, completion banner, settings menu.
--
-- EVERYTHING VISUAL IN HERE COMES OUT OF THE TOKEN BLOCK BELOW. Individual frames do not
-- pick their own colours, corner radii, paddings or tween timings. That is the single
-- change that separates a HUD that looks designed from one that looks assembled: before
-- this, four panels had four background colours, three corner radii, two type scales and
-- tween durations chosen one at a time between 0.3 and 0.8 -- and the result reads as
-- unrelated pieces sharing a screen even when each piece is fine on its own.

-- HOISTED for the reason spelled out at the top of HubService: a local declared below the
-- code that reads it is not that local, it is a global, and a global is nil.
--
--   chillBoardEnabled  the settings toggle did `chillBoardEnabled = not chillBoardEnabled`,
--                      which created a GLOBAL and left the real local false forever, so the
--                      switch flipped its own label and changed nothing else.
--   currentMode        passed straight into applyLeaderboardMode as nil.
local chillBoardEnabled = false
local currentMode = "chill"
-- Forward-declared rather than moved: it is an Instance built further down with the rest
-- of the board, and building it up here would put a label in the file before the frame it
-- belongs to. The collapse routine compares against it to spare it from being hidden, and
-- against a global nil it spared nothing -- so collapsing the board hid the very tag that
-- says what the collapsed thing is.
local tabTag: TextLabel

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UIService = {}

-- ===================================================================== tokens

-- A DARK, DESATURATED PLUM -- not black, and not an inverted light theme.
--
-- Pure black sits at a harsher contrast against light text than anything else on screen
-- and reads as a debug overlay dropped on the game. Tinting the neutrals toward the
-- level's own palette -- the sea, the pastel backdrop -- makes the HUD belong to the
-- world it floats over, and every pairing below still clears 4.5:1.
local COLOUR = {
	surface = Color3.fromRGB(22, 19, 28),
	surfaceRaised = Color3.fromRGB(33, 28, 42),
	stroke = Color3.fromRGB(78, 68, 96),

	textPrimary = Color3.fromRGB(243, 239, 249), -- ~16:1 on surface
	textSecondary = Color3.fromRGB(178, 168, 196), -- ~7.5:1 on surface
	textMuted = Color3.fromRGB(126, 116, 145),

	-- Chill is cool and quiet, hardcore is warm and awake. Deliberately a HUE shift rather
	-- than only a brightness one, so it survives being seen in peripheral vision.
	chill = Color3.fromRGB(150, 196, 236),
	hardcore = Color3.fromRGB(255, 138, 160),
	gold = Color3.fromRGB(255, 214, 140),
}

-- 4/8 rhythm. Every gap, pad and offset below is one of these.
local SPACE = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 }

-- 12 / 14 / 16 / 18 / 22 / 32. Six steps, and nothing between them.
local TEXT = { caption = 12, body = 14, label = 16, control = 18, mono = 22, display = 32 }

local RADIUS = UDim.new(0, 12)

-- One rhythm for the whole HUD. Exits run at 65% of entrances: an exit that takes as long
-- as its entrance feels like the interface is reluctant to get out of the way.
local MOTION = {
	fast = 0.14,
	base = 0.22,
	slow = 0.34,
	style = Enum.EasingStyle.Quad,
}

local function tweenIn(seconds: number?): TweenInfo
	return TweenInfo.new(seconds or MOTION.base, MOTION.style, Enum.EasingDirection.Out)
end

local function tweenOut(seconds: number?): TweenInfo
	return TweenInfo.new((seconds or MOTION.base) * 0.65, MOTION.style, Enum.EasingDirection.In)
end

-- ===================================================================== scaffolding

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GameUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Roblox has no drop shadow, so ELEVATION IS A RIM: a one-pixel stroke slightly lighter
-- than the surface. At one width everywhere it does the job a consistent shadow scale
-- does on the web -- it says these panels are the same kind of object. Same corner radius
-- and same inner padding on all of them is most of why a set of boxes reads as a family.
local function panel(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = COLOUR.surface
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = RADIUS
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOUR.stroke
	stroke.Thickness = 1
	stroke.Transparency = 0.45
	stroke.Parent = frame

	return frame
end

local function newLabel(parent: Instance, size: number, colour: Color3, font: Enum.Font): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Font = font
	text.TextSize = size
	text.TextColor3 = colour
	text.RichText = true
	text.Parent = parent
	return text
end

-- ===================================================================== mode button

-- 44 TALL, NOT 40. The platform minimum for a touch target is 44, and this is the only
-- control in the game -- being a few pixels short of comfortably hittable is not a
-- rounding error on the one button there is.
local modeButton = Instance.new("TextButton")
modeButton.Name = "ModeButton"
-- A QUARTER OF THE SIZE IT WAS. 208 by 44 is a button, and this stopped being a button when
-- mode became a vote -- a readout that large is claiming an importance it no longer has, and
-- it sat in the corner cluttering the view for the whole of every run.
--
-- 96 by 26 still reads at a glance and takes a sixth of the area.
modeButton.Size = UDim2.new(0, 96, 0, 26)
modeButton.AnchorPoint = Vector2.new(1, 1)
modeButton.Position = UDim2.new(1, -SPACE.xl, 1, -SPACE.xl)
modeButton.BackgroundColor3 = COLOUR.surface
modeButton.BackgroundTransparency = 0.08
modeButton.BorderSizePixel = 0
modeButton.Text = ""

-- NOT A BUTTON ANY MORE, and the reason is that mode stopped being a personal setting.
--
-- The lobby votes on it. The server refuses every toggle during a run, and outside a run you
-- are in the lobby standing on a pad that does the same job properly -- so this could only
-- ever be pressed in situations where pressing it did nothing. A control whose entire
-- behaviour is to refuse is worse than no control: it invites the press and then explains why
-- the press was wrong.
--
-- Kept as a READOUT rather than deleted. What mode this run is remains worth knowing at a
-- glance, and the panel is already built, positioned and styled to say it. Active is false, so
-- it no longer takes the click or shows a press state, and InputService no longer binds it.
modeButton.Active = false
modeButton.AutoButtonColor = false
modeButton.Parent = screenGui

local modeCorner = Instance.new("UICorner")
modeCorner.CornerRadius = RADIUS
modeCorner.Parent = modeButton

local modeStroke = Instance.new("UIStroke")
modeStroke.Color = COLOUR.chill
modeStroke.Thickness = 1
modeStroke.Transparency = 0.35
modeStroke.Parent = modeButton

-- A dot carries the mode as fast as the word does, and the word is still there for anyone
-- the colour does not reach.
local modeDot = Instance.new("Frame")
modeDot.Name = "Dot"
modeDot.Size = UDim2.new(0, 6, 0, 6)
modeDot.AnchorPoint = Vector2.new(0, 0.5)
modeDot.Position = UDim2.new(0, SPACE.md, 0.5, 0)
modeDot.BackgroundColor3 = COLOUR.chill
modeDot.BorderSizePixel = 0
modeDot.Parent = modeButton

local modeDotCorner = Instance.new("UICorner")
modeDotCorner.CornerRadius = UDim.new(1, 0)
modeDotCorner.Parent = modeDot

local modeText = newLabel(modeButton, TEXT.control, COLOUR.textPrimary, Enum.Font.GothamMedium)
modeText.Size = UDim2.new(1, -(SPACE.md * 2 + SPACE.sm), 1, 0)
modeText.Position = UDim2.new(0, SPACE.md + SPACE.sm + SPACE.xs, 0, 0)
modeText.TextSize = 13
modeText.TextXAlignment = Enum.TextXAlignment.Left
modeText.Text = "Chill"

UIService.modeButton = modeButton

-- Forward-declared here rather than beside the leaderboard, because setMode is defined
-- above it and check_lua reads declaration order as text.
function UIService.applyLeaderboardMode(mode: string) end

function UIService.setMode(mode: string)
	local hardcore = mode == "hardcore"
	local accent = if hardcore then COLOUR.hardcore else COLOUR.chill
	modeText.Text = if hardcore then "Hardcore" else "Chill"
	TweenService:Create(modeStroke, tweenIn(), { Color = accent }):Play()
	TweenService:Create(modeDot, tweenIn(), { BackgroundColor3 = accent }):Play()
	UIService.applyLeaderboardMode(mode)
end

-- Press feedback that does NOT move the button's bounds: only the fill and rim change. A
-- scale-down on a corner-anchored element visibly slides it away from the corner, which
-- reads as the layout twitching rather than as a press.
modeButton.MouseButton1Down:Connect(function()
	TweenService:Create(modeButton, tweenIn(MOTION.fast), { BackgroundTransparency = 0 }):Play()
	TweenService:Create(modeStroke, tweenIn(MOTION.fast), { Transparency = 0 }):Play()
end)

local function releaseMode()
	TweenService:Create(modeButton, tweenOut(MOTION.fast), { BackgroundTransparency = 0.08 }):Play()
	TweenService:Create(modeStroke, tweenOut(MOTION.fast), { Transparency = 0.35 }):Play()
end

modeButton.MouseButton1Up:Connect(releaseMode)
modeButton.MouseLeave:Connect(releaseMode)

-- ===================================================================== hardcore clock

local timerPanel = panel("HardcoreTimer", screenGui)
timerPanel.Size = UDim2.new(0, 208, 0, 46)
timerPanel.AnchorPoint = Vector2.new(1, 1)
timerPanel.Position = UDim2.new(1, -SPACE.xl, 1, -(SPACE.xl + 44 + SPACE.sm))
timerPanel.Visible = false

local timerText = newLabel(timerPanel, TEXT.mono, COLOUR.textPrimary, Enum.Font.RobotoMono)
timerText.Size = UDim2.new(1, 0, 1, 0)
timerText.Text = "0:00.00"

function UIService.setTimerVisible(visible: boolean)
	timerPanel.Visible = visible
end

-- MONOSPACED, AND THAT IS FUNCTIONAL. A running clock in a proportional face re-flows on
-- nearly every frame as digit widths change, so the whole readout jitters. Tabular figures
-- are the standard answer for timers and data columns.
function UIService.setTimer(elapsed: number)
	local minutes = math.floor(elapsed / 60)
	timerText.Text = ("%d:%05.2f"):format(minutes, elapsed - minutes * 60)
end

-- ===================================================================== tooltip

local tooltip = panel("Tooltip", screenGui)
tooltip.Size = UDim2.new(0, 320, 0, 40)
tooltip.AnchorPoint = Vector2.new(1, 1)
tooltip.Position = UDim2.new(1, -SPACE.xl, 1, -(SPACE.xl + 44 + SPACE.sm + 46 + SPACE.sm))
tooltip.BackgroundTransparency = 1
tooltip.Visible = false

local tooltipStroke = tooltip:FindFirstChildOfClass("UIStroke") :: UIStroke
tooltipStroke.Transparency = 1

local tooltipText = newLabel(tooltip, TEXT.body, COLOUR.textSecondary, Enum.Font.Gotham)
tooltipText.Size = UDim2.new(1, -SPACE.lg * 2, 1, 0)
tooltipText.Position = UDim2.new(0, SPACE.lg, 0, 0)
tooltipText.TextWrapped = true
tooltipText.TextTransparency = 1

local tooltipToken = 0

function UIService.showTooltip(text: string)
	tooltipToken += 1
	local token = tooltipToken
	tooltipText.Text = text
	tooltip.Visible = true
	TweenService:Create(tooltip, tweenIn(), { BackgroundTransparency = 0.08 }):Play()
	TweenService:Create(tooltipStroke, tweenIn(), { Transparency = 0.45 }):Play()
	TweenService:Create(tooltipText, tweenIn(), { TextTransparency = 0 }):Play()

	task.delay(2.6, function()
		if tooltipToken ~= token then
			return
		end
		TweenService:Create(tooltip, tweenOut(), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(tooltipStroke, tweenOut(), { Transparency = 1 }):Play()
		TweenService:Create(tooltipText, tweenOut(), { TextTransparency = 1 }):Play()
		task.delay(MOTION.base, function()
			if tooltipToken == token then
				tooltip.Visible = false
			end
		end)
	end)
end

-- ===================================================================== the blackout
--
-- A full-screen black sheet the completion banner sits ON TOP of, for the one ending that needs
-- the picture to go away: the dive at the end of City Shore, where the water closes over you.
--
-- ZIndex rather than creation order, because this ScreenGui is in Sibling mode: the sheet is
-- above every HUD panel and the banner and its two labels are above the sheet. A blackout that
-- covered the banner it exists to frame would be a blank screen with nothing on it.
local BLACKOUT_ZINDEX = 5

local blackout = Instance.new("Frame")
blackout.Name = "Blackout"
blackout.BackgroundColor3 = Color3.new(0, 0, 0)
blackout.BackgroundTransparency = 1
blackout.BorderSizePixel = 0
blackout.Size = UDim2.new(1, 0, 1, 0)
blackout.Visible = false
blackout.ZIndex = BLACKOUT_ZINDEX
blackout.Parent = screenGui

local blackoutToken = 0

function UIService.fadeToBlack(seconds: number?)
	blackoutToken += 1
	blackout.Visible = true
	TweenService:Create(blackout, TweenInfo.new(seconds or 0.45, MOTION.style,
		Enum.EasingDirection.Out), { BackgroundTransparency = 0 }):Play()
end

function UIService.fadeFromBlack(seconds: number?)
	blackoutToken += 1
	local token = blackoutToken
	local over = seconds or 0.7
	TweenService:Create(blackout, TweenInfo.new(over, MOTION.style, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }):Play()
	-- Hidden once it is clear, so a transparent sheet is not sitting over the HUD swallowing
	-- nothing in particular for the rest of the session.
	task.delay(over + 0.05, function()
		if blackoutToken == token then
			blackout.Visible = false
		end
	end)
end

-- ===================================================================== completion

local completion = panel("CompletionBanner", screenGui)
completion.ZIndex = BLACKOUT_ZINDEX + 1
completion.Size = UDim2.new(0, 440, 0, 132)
completion.AnchorPoint = Vector2.new(0.5, 0.5)
completion.Position = UDim2.new(0.5, 0, 0.36, 0)
completion.BackgroundTransparency = 1
completion.Visible = false

local completionStroke = completion:FindFirstChildOfClass("UIStroke") :: UIStroke
completionStroke.Transparency = 1

local completionTitle = newLabel(completion, TEXT.display, COLOUR.textPrimary, Enum.Font.GothamBold)
completionTitle.ZIndex = BLACKOUT_ZINDEX + 2
completionTitle.Size = UDim2.new(1, 0, 0, 44)
completionTitle.Position = UDim2.new(0, 0, 0, SPACE.xl)
completionTitle.TextTransparency = 1

local completionSubtitle = newLabel(completion, TEXT.label, COLOUR.textSecondary, Enum.Font.Gotham)
completionSubtitle.ZIndex = BLACKOUT_ZINDEX + 2
completionSubtitle.Size = UDim2.new(1, 0, 0, 26)
completionSubtitle.Position = UDim2.new(0, 0, 0, SPACE.xl + 46)
completionSubtitle.TextTransparency = 1

local completionToken = 0

function UIService.showCompletion(levelId: number?, time: number?)
	completionToken += 1
	local token = completionToken

	completionTitle.Text = if levelId then ("Level %d Complete"):format(levelId) else "Level Complete"
	if time then
		local minutes = math.floor(time / 60)
		completionSubtitle.Text = ("Hardcore  ·  %d:%05.2f"):format(minutes, time - minutes * 60)
		completionStroke.Color = COLOUR.hardcore
	else
		completionSubtitle.Text = "Chill run"
		completionStroke.Color = COLOUR.chill
	end

	completion.Visible = true
	completion.Size = UDim2.new(0, 408, 0, 122)
	completion.BackgroundTransparency = 1
	completionStroke.Transparency = 1
	completionTitle.TextTransparency = 1
	completionSubtitle.TextTransparency = 1

	local info = tweenIn(MOTION.slow)
	TweenService:Create(completion, info, {
		Size = UDim2.new(0, 440, 0, 132),
		BackgroundTransparency = 0.06,
	}):Play()
	TweenService:Create(completionStroke, info, { Transparency = 0.25 }):Play()
	TweenService:Create(completionTitle, info, { TextTransparency = 0 }):Play()
	-- STAGGERED BY 90ms. The subtitle arriving a beat after the headline is what makes the
	-- banner read as one considered announcement instead of two labels switched on
	-- together -- the same reason list rows stagger below.
	task.delay(0.09, function()
		if completionToken == token then
			TweenService:Create(completionSubtitle, info, { TextTransparency = 0 }):Play()
		end
	end)

	task.delay(3.4, function()
		if completionToken ~= token then
			return
		end
		local out = tweenOut(MOTION.slow)
		TweenService:Create(completion, out, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(completionStroke, out, { Transparency = 1 }):Play()
		TweenService:Create(completionTitle, out, { TextTransparency = 1 }):Play()
		TweenService:Create(completionSubtitle, out, { TextTransparency = 1 }):Play()
		task.delay(MOTION.slow, function()
			if completionToken == token then
				completion.Visible = false
			end
		end)
	end)
end

-- ===================================================================== settings

local settingsFrame = panel("SettingsMenu", screenGui)
settingsFrame.Size = UDim2.new(0, 300, 0, 320)
settingsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
settingsFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
settingsFrame.Visible = false

-- LEAVING A RUN, and the only way back to the lobby that is not finishing or dying.
--
-- The button only asks. The server decides whether there is a run to leave, because a client
-- that could fire this from the hub would be teleporting itself to the hub spawn from
-- wherever it liked -- a free teleport anywhere in the room.
local leaveButton = Instance.new("TextButton")
leaveButton.Name = "LeaveLevel"
leaveButton.Size = UDim2.new(1, -32, 0, 34)
leaveButton.Position = UDim2.new(0, 16, 1, -50)
leaveButton.BackgroundColor3 = Color3.fromRGB(92, 46, 52)
leaveButton.AutoButtonColor = true
leaveButton.Font = Enum.Font.GothamMedium
leaveButton.TextSize = 14
leaveButton.TextColor3 = Color3.fromRGB(244, 226, 228)
leaveButton.Text = "Leave level"
leaveButton.Parent = settingsFrame

local leaveCorner = Instance.new("UICorner")
leaveCorner.CornerRadius = UDim.new(0, 6)
leaveCorner.Parent = leaveButton

leaveButton.Activated:Connect(function()
	-- Looked up on each press rather than cached at load. Bootstrap creates the remotes at
	-- server start, and this module can be required before that has replicated.
	local remotes = ReplicatedStorage:FindFirstChild("RemoteEvents")
	local leave = remotes and remotes:FindFirstChild("LeaveLevel")
	if leave and leave:IsA("RemoteEvent") then
		leave:FireServer()
		settingsFrame.Visible = false
	end
end)

-- The chill half of the rule, as a button. Hardcore ignores it by design.
local boardToggle = Instance.new("TextButton")
boardToggle.Name = "ChillLeaderboardToggle"
boardToggle.Size = UDim2.new(1, -32, 0, 34)
boardToggle.Position = UDim2.new(0, 16, 1, -92)
boardToggle.BackgroundColor3 = Color3.fromRGB(48, 44, 60)
boardToggle.AutoButtonColor = true
boardToggle.Font = Enum.Font.GothamMedium
boardToggle.TextSize = 14
boardToggle.TextColor3 = Color3.fromRGB(226, 228, 240)
boardToggle.Text = "Chill leaderboard: off"
boardToggle.Parent = settingsFrame

local boardToggleCorner = Instance.new("UICorner")
boardToggleCorner.CornerRadius = UDim.new(0, 6)
boardToggleCorner.Parent = boardToggle

boardToggle.Activated:Connect(function()
	chillBoardEnabled = not chillBoardEnabled
	-- Written as a statement rather than a multi-line if-expression: check_lua counts blocks
	-- by keyword, and an `if` spread over three lines with no `end` reads to it as a block
	-- left open. The Lua is valid either way; the checker is the one that has to parse it.
	if chillBoardEnabled then
		boardToggle.Text = "Chill leaderboard: on"
	else
		boardToggle.Text = "Chill leaderboard: off"
	end
	UIService.applyLeaderboardMode(currentMode)
end)

function UIService.toggleSettingsMenu()
	settingsFrame.Visible = not settingsFrame.Visible
end

-- ===================================================================== leaderboard

local leaderboard = panel("LeaderboardDisplay", screenGui)
-- SMALLER. 288 by 300 is a quarter of a phone screen given over to times nobody has set
-- yet, parked over the corner of the level you are trying to look at.
leaderboard.Size = UDim2.new(0, 218, 0, 208)
leaderboard.AnchorPoint = Vector2.new(0, 1)
leaderboard.Position = UDim2.new(0, SPACE.xl, 1, -SPACE.xl)
leaderboard.Visible = false

-- THE ROWS GO IN A FRAME OF THEIR OWN, and this is what stopped the panel folding.
--
-- The list layout lived on the panel itself, and the three collapse controls -- the glyph,
-- the full-size hit area and the tab label -- were parented straight into it alongside the
-- rows. A UIListLayout lays out EVERY child, so all three became list items: the hit area is
-- sized to the whole panel, so as a list entry it reserved the panel's entire height and
-- pushed the rows out from under it. That is the tall empty box in the screenshot, and it is
-- also why aiming at the panel did not reliably land on anything.
--
-- Splitting them apart fixes the layout and the folding at once: the layout owns Content and
-- nothing else, and the controls float above it where a control belongs.
local leaderboardContent = Instance.new("Frame")
leaderboardContent.Name = "Content"
leaderboardContent.Size = UDim2.new(1, 0, 1, 0)
leaderboardContent.BackgroundTransparency = 1
leaderboardContent.ZIndex = 3
leaderboardContent.Parent = leaderboard

local leaderboardPad = Instance.new("UIPadding")
leaderboardPad.PaddingTop = UDim.new(0, SPACE.lg)
leaderboardPad.PaddingBottom = UDim.new(0, SPACE.lg)
leaderboardPad.PaddingLeft = UDim.new(0, SPACE.lg)
leaderboardPad.PaddingRight = UDim.new(0, SPACE.lg)
leaderboardPad.Parent = leaderboardContent

local leaderboardList = Instance.new("UIListLayout")
leaderboardList.SortOrder = Enum.SortOrder.LayoutOrder
leaderboardList.Padding = UDim.new(0, SPACE.xs)
leaderboardList.Parent = leaderboardContent

-- Small, muted, and spaced out by hand. A panel heading competing with its own contents is
-- the commonest way a data panel ends up looking cluttered: the rows are the content, and
-- the title only has to say which table this is.
local leaderboardTitle = newLabel(leaderboardContent, TEXT.caption, COLOUR.textMuted, Enum.Font.GothamBold)
leaderboardTitle.Name = "Title"
leaderboardTitle.Size = UDim2.new(1, 0, 0, 18)
leaderboardTitle.TextXAlignment = Enum.TextXAlignment.Left
leaderboardTitle.Text = "HARDCORE · BEST TIMES"
leaderboardTitle.LayoutOrder = 0

local titleSpacer = Instance.new("Frame")
titleSpacer.Name = "TitleSpacer"
titleSpacer.Size = UDim2.new(1, 0, 0, SPACE.sm)
titleSpacer.BackgroundTransparency = 1
titleSpacer.LayoutOrder = 1
titleSpacer.Parent = leaderboardContent

-- OFF BY DEFAULT IN CHILL, always on in Hardcore.
--
-- Chill is the mode you play to feel the materials, and a ranking in the corner of the
-- screen is the opposite of that. Hardcore is the mode that exists to be ranked, so there it
-- is not optional -- which is why the toggle below only reaches the chill half.

-- The caller still gets to hide it outright: `visible` is whether anything wants it shown at
-- all, and the mode rule decides whether chill is allowed to.
local function leaderboardShouldShow(visible: boolean): boolean
	return visible and (currentMode == "hardcore" or chillBoardEnabled)
end

local leaderboardWanted = false

-- COLLAPSIBLE, because a 300-pixel panel pinned to the bottom-left corner is in the way of
-- the one thing you are actually doing: looking at the platform in front of you.
--
-- Collapsed it becomes a tab you can still see and still press -- not hidden, which would mean
-- rediscovering a control that has no other entry point. The panel is the same instance either
-- way; only its height and its contents' visibility change, so nothing has to be rebuilt and
-- the rows keep refreshing behind it.
local leaderboardOpen = true
local TAB_HEIGHT = 32
local OPEN_HEIGHT = 208

local collapse = Instance.new("TextButton")
collapse.Name = "Collapse"
collapse.AnchorPoint = Vector2.new(1, 0)
collapse.Position = UDim2.new(1, 0, 0, 0)
collapse.Size = UDim2.new(0, 30, 0, 26)
collapse.BackgroundTransparency = 1
collapse.Font = Enum.Font.GothamBold
collapse.TextSize = 18
collapse.TextColor3 = Color3.fromRGB(190, 196, 214)
collapse.Text = "-"
collapse.ZIndex = 6
collapse.Parent = leaderboard

-- THE WHOLE PANEL IS THE BUTTON, not a 30-pixel glyph in its corner.
--
-- A toggle you have to aim at is a toggle most people never find, and this one is a corner
-- panel on a screen where the player is usually mid-jump. The glyph stays as an affordance --
-- something has to LOOK pressable -- but the hit area is the panel.
local hit = Instance.new("TextButton")
hit.Name = "HitArea"
hit.Size = UDim2.new(1, 0, 1, 0)
hit.BackgroundTransparency = 1
hit.Text = ""
hit.AutoButtonColor = false
-- ABOVE the content, not behind it. Nothing inside the panel is interactive -- the rows are
-- TextLabels and labels do not take input -- so there is no click here to protect from being
-- eaten, and sitting under them only made the press miss.
hit.ZIndex = 5
hit.Parent = leaderboard

-- ANIMATED, because a panel that jumps between two sizes reads as a glitch and one that
-- travels reads as a thing folding away. Quart out: fast at first, so it feels responsive,
-- then easing into place.
local resizeTween: Tween? = nil

local function applyCollapse()
	collapse.Text = if leaderboardOpen then "-" else "+"
	local tag = leaderboard:FindFirstChild("TabTag")
	if tag and tag:IsA("TextLabel") then
		tag.Visible = not leaderboardOpen
	end
	-- COLLAPSES IN BOTH AXES. Shrinking only the height left a 288-pixel bar lying along the
	-- bottom of the screen, which is not much less in the way than the panel was. A tab is
	-- small in both directions or it is not a tab.
	local wanted = if leaderboardOpen
		then UDim2.new(0, 218, 0, OPEN_HEIGHT)
		else UDim2.new(0, 96, 0, TAB_HEIGHT)
	if resizeTween then
		resizeTween:Cancel()
	end
	resizeTween = TweenService:Create(leaderboard,
		TweenInfo.new(0.26, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = wanted })
	;(resizeTween :: Tween):Play()
	-- ONE FRAME, not a walk over every descendant testing it against three controls. Now that
	-- the rows live in Content and the controls do not, hiding the content IS hiding the rows,
	-- and the controls are excluded by where they are rather than by being named here.
	--
	-- Hidden immediately on the way down so nothing spills outside the shrinking frame, and
	-- revealed only once it has finished growing on the way up. The opposite order in each
	-- direction is the whole reason this reads as folding rather than snapping.
	if leaderboardOpen then
		task.delay(0.18, function()
			if leaderboardOpen then
				leaderboardContent.Visible = true
			end
		end)
	else
		leaderboardContent.Visible = false
	end
end

-- What the tab says when it is shut. Without it a collapsed panel is an anonymous box with
-- a plus sign, and nobody presses a box to find out what is in it.
tabTag = Instance.new("TextLabel")
tabTag.Name = "TabTag"
tabTag.Size = UDim2.new(1, -34, 1, 0)
tabTag.Position = UDim2.new(0, 10, 0, 0)
tabTag.BackgroundTransparency = 1
tabTag.Font = Enum.Font.GothamMedium
tabTag.TextSize = 12
tabTag.TextXAlignment = Enum.TextXAlignment.Left
tabTag.TextColor3 = Color3.fromRGB(178, 184, 206)
tabTag.Text = "Best times"
tabTag.Visible = false
tabTag.ZIndex = 6
tabTag.Parent = leaderboard

local function toggleLeaderboard()
	leaderboardOpen = not leaderboardOpen
	applyCollapse()
end

collapse.Activated:Connect(toggleLeaderboard)
hit.Activated:Connect(toggleLeaderboard)

function UIService.applyLeaderboardMode(mode: string)
	currentMode = mode
	leaderboard.Visible = leaderboardShouldShow(leaderboardWanted)
	applyCollapse()
end

function UIService.setLeaderboardVisible(visible: boolean)
	leaderboardWanted = visible
	leaderboard.Visible = leaderboardShouldShow(visible)
	applyCollapse()
end

-- Names are resolved once each and remembered. GetNameFromUserIdAsync is a web call: it
-- yields, it can fail, and it is called for every row of every refresh -- so an unguarded
-- one turns a refresh into ten round trips and an error if any of them is rate-limited.
local nameCache: { [number]: string } = {}

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, resolved = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok and resolved then resolved else ("Player %d"):format(userId)
	nameCache[userId] = name
	return name
end

local function clearRows()
	for _, child in ipairs(leaderboard:GetChildren()) do
		if child.Name == "Row" or child.Name == "Empty" then
			child:Destroy()
		end
	end
end

-- Called after every refresh, because rows are created as the data arrives and a row created
-- while the panel is shut would otherwise appear on top of the tab.
function UIService.reapplyCollapse()
	applyCollapse()
end

function UIService.refreshLeaderboard(data: { { userId: number, time: number } })
	clearRows()

	if #data == 0 then
		local empty = newLabel(leaderboardContent, TEXT.body, COLOUR.textMuted, Enum.Font.Gotham)
		empty.Name = "Empty"
		empty.Size = UDim2.new(1, 0, 0, 44)
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.TextYAlignment = Enum.TextYAlignment.Top
		empty.TextWrapped = true
		empty.Text = "No times yet. Finish a hardcore run to open the board."
		empty.LayoutOrder = 2
		return
	end

	for i, entry in ipairs(data) do
		local mine = entry.userId == player.UserId

		local row = Instance.new("Frame")
		row.Name = "Row"
		row.Size = UDim2.new(1, 0, 0, 28)
		row.BackgroundColor3 = COLOUR.surfaceRaised
		-- The local player's row is tinted AND still carries its rank and name, so the
		-- highlight is an aid to finding yourself rather than the only way to do it.
		row.BackgroundTransparency = if mine then 0.35 else 1
		row.BorderSizePixel = 0
		row.LayoutOrder = i + 1
		row.Parent = leaderboardContent

		local rowCorner = Instance.new("UICorner")
		rowCorner.CornerRadius = UDim.new(0, 6)
		rowCorner.Parent = row

		local rank = newLabel(row, TEXT.body, if i == 1 then COLOUR.gold else COLOUR.textMuted, Enum.Font.GothamBold)
		rank.Size = UDim2.new(0, 22, 1, 0)
		rank.Position = UDim2.new(0, SPACE.sm, 0, 0)
		rank.TextXAlignment = Enum.TextXAlignment.Left
		rank.Text = tostring(i)

		local who = newLabel(row, TEXT.body, if mine then COLOUR.textPrimary else COLOUR.textSecondary, Enum.Font.Gotham)
		who.Size = UDim2.new(1, -(SPACE.sm + 22 + 84), 1, 0)
		who.Position = UDim2.new(0, SPACE.sm + 22, 0, 0)
		who.TextXAlignment = Enum.TextXAlignment.Left
		who.TextTruncate = Enum.TextTruncate.AtEnd
		who.Text = nameFor(entry.userId)

		-- Times right-aligned and monospaced, so the digits form a column you can compare
		-- straight down instead of a ragged edge you have to read row by row.
		local minutes = math.floor(entry.time / 60)
		local when = newLabel(row, TEXT.body, COLOUR.textPrimary, Enum.Font.RobotoMono)
		when.Size = UDim2.new(0, 76, 1, 0)
		when.Position = UDim2.new(1, -(76 + SPACE.sm), 0, 0)
		when.TextXAlignment = Enum.TextXAlignment.Right
		when.Text = ("%d:%05.2f"):format(minutes, entry.time - minutes * 60)

		-- Staggered by 35ms per row. All-at-once reads as a screen redraw; a short cascade
		-- reads as the board filling in, and it costs nothing.
		local parts = { rank, who, when }
		for _, item in ipairs(parts) do
			item.TextTransparency = 1
		end
		task.delay(0.035 * (i - 1), function()
			if not row.Parent then
				return
			end
			for _, item in ipairs(parts) do
				TweenService:Create(item, tweenIn(), { TextTransparency = 0 }):Play()
			end
		end)
	end
	UIService.reapplyCollapse()
end

return UIService
