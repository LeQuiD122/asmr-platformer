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
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

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
-- THE MENUS' COLOURS (Shared/Style, the ninety-ninth pass): the run's panels were a purple of their own.
local COLOUR = {
	surface = Style.COLOUR.panel,
	surfaceRaised = Style.COLOUR.panelRaised,
	stroke = Style.COLOUR.edge,

	textPrimary = Style.COLOUR.ink, -- ~16:1 on surface
	textSecondary = Style.COLOUR.inkSoft, -- ~7.5:1 on surface
	textMuted = Style.COLOUR.inkMuted,

	-- Chill is cool and quiet, hardcore is warm and awake. Deliberately a HUE shift rather
	-- than only a brightness one, so it survives being seen in peripheral vision.
	chill = Style.COLOUR.chill,
	hardcore = Style.COLOUR.hardcore,
	gold = Style.COLOUR.accent,
}

-- 4/8 rhythm. Every gap, pad and offset below is one of these.
local SPACE = { xs = 4, sm = 8, md = 12, lg = 16, xl = 24 }

-- 12 / 14 / 16 / 18 / 22 / 32. Six steps, and nothing between them.
local TEXT = { caption = 12, body = 14, label = 16, control = 18, mono = 22, display = 32 }

local RADIUS = Style.RADIUS.button

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
	stroke.Thickness = Style.STROKE.hair
	stroke.Transparency = 0.45
	stroke.Parent = frame

	return frame
end

local function newLabel(parent: Instance, size: number, colour: Color3, font: Font): TextLabel
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.FontFace = font
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
modeStroke.Thickness = Style.STROKE.hair
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

local modeText = newLabel(modeButton, TEXT.control, COLOUR.textPrimary, Style.FONT.heading)
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
	-- NEVER A CLOCK IN CHILL (the hundred-and-thirtieth pass, from your test): it was put up by a hardcore run and left
	-- up when the lobby voted Chill, still showing that run's time.
	if not hardcore then
		UIService.setTimerVisible(false)
	end
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

local timerText = newLabel(timerPanel, TEXT.mono, COLOUR.textPrimary, Style.FONT.number)
timerText.Size = UDim2.new(1, 0, 1, 0)
timerText.Text = "0:00.00"

-- FOLDED AWAY ON A PRESS (the hundred-and-thirtieth pass, from your test: "I want to be able to minimise it when I'm in
-- hardcore"): pressing the clock folds it down to a small round stopwatch in its corner, and pressing that opens it
-- again; it stays as you left it for the rest of the session. A small mark at its right says it folds.
local timerShown, timerFolded = false, false
local timerFold = Instance.new("TextButton")
timerFold.Name = "Fold"
timerFold.Size = UDim2.new(1, 0, 1, 0)
timerFold.BackgroundTransparency = 1
timerFold.Text = ""
timerFold.AutoButtonColor = false
timerFold.Parent = timerPanel
local foldMark = Instance.new("Frame")
foldMark.Name = "FoldMark"
foldMark.AnchorPoint = Vector2.new(1, 0.5)
foldMark.Position = UDim2.new(1, -12, 0.5, 0)
foldMark.Size = UDim2.new(0, 10, 0, 2)
foldMark.BackgroundColor3 = COLOUR.textMuted
foldMark.BorderSizePixel = 0
foldMark.Parent = timerPanel
local timerPill = Instance.new("TextButton")
timerPill.Name = "HardcoreTimerFolded"
timerPill.Size = UDim2.new(0, 44, 0, 44)
timerPill.AnchorPoint = Vector2.new(1, 1)
timerPill.Position = timerPanel.Position
timerPill.BackgroundColor3 = COLOUR.surface
timerPill.BackgroundTransparency = 0.08
timerPill.BorderSizePixel = 0
timerPill.Text = ""
timerPill.AutoButtonColor = false
timerPill.Visible = false
timerPill.Parent = screenGui
local pillRound = Instance.new("UICorner")
pillRound.CornerRadius = UDim.new(1, 0)
pillRound.Parent = timerPill
local pillRim = Instance.new("UIStroke")
pillRim.Color = COLOUR.hardcore
pillRim.Thickness = Style.STROKE.hair
pillRim.Transparency = 0.35
pillRim.Parent = timerPill
-- The stopwatch: its ring, the button on its crown, and a hand.
local watchRing = Instance.new("Frame")
watchRing.AnchorPoint = Vector2.new(0.5, 0.5)
watchRing.Position = UDim2.new(0.5, 0, 0.5, 2)
watchRing.Size = UDim2.new(0, 20, 0, 20)
watchRing.BackgroundTransparency = 1
watchRing.Parent = timerPill
local watchRound = Instance.new("UICorner")
watchRound.CornerRadius = UDim.new(1, 0)
watchRound.Parent = watchRing
local watchRim = Instance.new("UIStroke")
watchRim.Color = COLOUR.textPrimary
watchRim.Thickness = 2
watchRim.Parent = watchRing
local watchCrown = Instance.new("Frame")
watchCrown.AnchorPoint = Vector2.new(0.5, 1)
watchCrown.Position = UDim2.new(0.5, 0, 0, -1)
watchCrown.Size = UDim2.new(0, 6, 0, 3)
watchCrown.BackgroundColor3 = COLOUR.textPrimary
watchCrown.BorderSizePixel = 0
watchCrown.Parent = watchRing
local watchHand = Instance.new("Frame")
watchHand.AnchorPoint = Vector2.new(0.5, 1)
watchHand.Position = UDim2.new(0.5, 0, 0.5, 0)
watchHand.Size = UDim2.new(0, 2, 0, 7)
watchHand.Rotation = 40
watchHand.BackgroundColor3 = COLOUR.hardcore
watchHand.BorderSizePixel = 0
watchHand.Parent = watchRing

local function showTimer()
	timerPanel.Visible = timerShown and not timerFolded
	timerPill.Visible = timerShown and timerFolded
end
timerFold.Activated:Connect(function()
	timerFolded = true
	showTimer()
end)
timerPill.Activated:Connect(function()
	timerFolded = false
	showTimer()
end)

function UIService.setTimerVisible(visible: boolean)
	timerShown = visible
	showTimer()
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

local tooltipText = newLabel(tooltip, TEXT.body, COLOUR.textSecondary, Style.FONT.body)
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

-- THE END OF A RUN IS THE ONE MOMENT THIS GAME GETS TO SAY SOMETHING, and it used to say "Level 1
-- Complete" in a grey box over a screen that had just cut to black. Both halves were wrong: the
-- blackout threw away the dive at the moment it was worth watching, and the banner said nothing
-- about the run it was ending.
--
-- So the blackout is gone (see the dive callback in Bootstrap) and the banner belongs to the level
-- it ends: that level's name, its own colour, a line about what you actually just did, and the
-- run's numbers under a rule that draws itself in. A LOOK PER LEVEL, with a fallback, so a new
-- level gets a sensible banner before anybody writes it one.
-- EACH LEVEL ENDS IN ITS OWN LANGUAGE.
--
-- The banner used to differ between levels by two colours, which is the difference between four
-- levels and one level with four skins. Every look below now also carries the SHAPE of its level:
-- the panel's own gradient, a vignette in its colour, and a MOTIF -- a few frames drawn inside the
-- panel that say where you have just been, with one of them moving.
--
--   CITY SHORE: a sun going down behind a horizon line. The last thing you did was dive at it.
--   SKY POOLS: cloud along the bottom edge and a ripple under the headline, in the slide's lavender
--   over a morning blue.
--   THE SUNKEN CITY: caustics drifting across a panel that is nearly black, because the banner comes
--   up at the bottom of the shaft with water somewhere overhead.
--   FLOODED HALLS: tile. A grid and a dado line, which is the whole building in two marks.
--
-- Every motif is frames and gradients -- no images, nothing to import -- and every one has exactly
-- one thing in motion, for the reason the rest of this banner does: one considered announcement
-- rather than five things switched on.
local COMPLETION_LOOKS: { [number]: any } = {
	[1] = { name = "City Shore", line = "You made the dive",
		accent = Color3.fromRGB(255, 206, 128), tint = Color3.fromRGB(31, 45, 72),
		top = Color3.fromRGB(46, 62, 96), bottom = Color3.fromRGB(122, 74, 74),
		vignette = Color3.fromRGB(26, 16, 22), motif = "shore" },
	[2] = { name = "Sky Pools", line = "Down through the clouds",
		accent = Color3.fromRGB(200, 190, 255), tint = Color3.fromRGB(30, 46, 76),
		top = Color3.fromRGB(52, 78, 122), bottom = Color3.fromRGB(150, 176, 216),
		vignette = Color3.fromRGB(14, 22, 40), motif = "clouds" },
	[3] = { name = "The Sunken City", line = "Pulled down into the dark",
		accent = Color3.fromRGB(150, 226, 210), tint = Color3.fromRGB(8, 20, 24),
		top = Color3.fromRGB(10, 26, 30), bottom = Color3.fromRGB(18, 48, 52),
		vignette = Color3.fromRGB(2, 8, 10), motif = "caustics" },
	[4] = { name = "Flooded Halls", line = "The tide is going out",
		accent = Color3.fromRGB(142, 214, 200), tint = Color3.fromRGB(22, 41, 45),
		top = Color3.fromRGB(30, 52, 54), bottom = Color3.fromRGB(58, 84, 82),
		vignette = Color3.fromRGB(8, 18, 18), motif = "tiles" },
	-- HILL HOUSE (the hundred-and-eleventh pass): the morning, and his door.
	[5] = { name = "Hill House", line = "You stood at his door",
		accent = Color3.fromRGB(255, 214, 150), tint = Color3.fromRGB(36, 44, 38),
		top = Color3.fromRGB(64, 84, 70), bottom = Color3.fromRGB(176, 150, 120),
		vignette = Color3.fromRGB(18, 16, 12), motif = "door" },
}
local COMPLETION_FALLBACK: any = { line = "Route cleared", accent = COLOUR.gold,
	tint = COLOUR.surfaceRaised }

-- A VIGNETTE INSTEAD OF A BLACKOUT. The top and bottom of the screen darken a little while the
-- banner is up, so it reads against the sea instead of competing with it, and the level is still
-- there behind it. Two bands rather than four: Roblox has no radial gradient, and the sides would
-- be twice the parts for a difference nobody would name.
local VIGNETTE_DEPTH = 0.26 -- of the screen, top and bottom
local VIGNETTE_DARK = 0.55 -- transparency at the very edge

local function vignetteBand(name: string, top: boolean): Frame
	local band = Instance.new("Frame")
	band.Name = name
	band.BackgroundColor3 = Color3.fromRGB(8, 6, 12)
	band.BackgroundTransparency = 1
	band.BorderSizePixel = 0
	band.Size = UDim2.new(1, 0, VIGNETTE_DEPTH, 0)
	band.Position = if top then UDim2.new(0, 0, 0, 0) else UDim2.new(0, 0, 1 - VIGNETTE_DEPTH, 0)
	band.ZIndex = BLACKOUT_ZINDEX
	band.Visible = false
	band.Parent = screenGui

	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	-- Solid at the screen edge, gone by the inner edge of the band.
	fade.Transparency = if top
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		else NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	fade.Parent = band
	return band
end

local vignetteTop = vignetteBand("VignetteTop", true)
local vignetteBottom = vignetteBand("VignetteBottom", false)

local function showVignette(on: boolean, seconds: number, colour: Color3?)
	for _, band in ipairs({ vignetteTop, vignetteBottom }) do
		if on then
			band.Visible = true
			band.BackgroundColor3 = colour or Color3.fromRGB(8, 6, 12)
		end
		TweenService:Create(band, TweenInfo.new(seconds, MOTION.style, Enum.EasingDirection.Out),
			{ BackgroundTransparency = if on then VIGNETTE_DARK else 1 }):Play()
	end
end

local completion = panel("CompletionBanner", screenGui)
completion.ZIndex = BLACKOUT_ZINDEX + 1
-- NO WIDER THAN THE SCREEN on a phone held upright: 520 wherever it fits.
completion.Size = UDim2.new(0.92, 0, 0, 172)
local completionMost = Instance.new("UISizeConstraint")
completionMost.MaxSize = Vector2.new(520, 172)
completionMost.Parent = completion
Style.fit(completion, Vector2.new(520, 172))
completion.AnchorPoint = Vector2.new(0.5, 0.5)
completion.Position = UDim2.new(0.5, 0, 0.36, 0)
completion.BackgroundTransparency = 1
completion.Visible = false
-- For the sweep of light below, which is a child sliding across the panel.
completion.ClipsDescendants = true

local completionStroke = completion:FindFirstChildOfClass("UIStroke") :: UIStroke
completionStroke.Transparency = 1
completionStroke.Thickness = Style.STROKE.button

-- The panel's own colour is the level's, and this only shades it downward, so the banner reads as
-- one lit object rather than a flat rectangle.
local completionDepth = Instance.new("UIGradient")
completionDepth.Rotation = 90
completionDepth.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 150, 150)),
})
completionDepth.Parent = completion

local completionShine = Instance.new("Frame")
completionShine.Name = "Shine"
completionShine.BackgroundColor3 = Color3.new(1, 1, 1)
completionShine.BackgroundTransparency = 0.88
completionShine.BorderSizePixel = 0
completionShine.Size = UDim2.new(0.22, 0, 1, 0)
completionShine.Position = UDim2.fromScale(-0.3, 0)
completionShine.ZIndex = BLACKOUT_ZINDEX + 2
completionShine.Parent = completion

local completionShineFade = Instance.new("UIGradient")
completionShineFade.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(1, 1),
})
completionShineFade.Parent = completionShine

-- ===== THE MOTIF =====
--
-- A few frames drawn inside the panel, behind the text, rebuilt for whichever level just ended.
-- Everything here sits at a ZIndex under the labels and over the panel, and nothing in it is ever
-- read -- it is the difference between a banner that says which level you finished and a banner
-- that LOOKS like the level you finished.
local completionMotif = Instance.new("Frame")
completionMotif.Name = "Motif"
completionMotif.BackgroundTransparency = 1
completionMotif.Size = UDim2.fromScale(1, 1)
completionMotif.ZIndex = BLACKOUT_ZINDEX + 2
completionMotif.Parent = completion

local function motifFrame(name: string, colour: Color3, size: UDim2, position: UDim2, transparency: number): Frame
	local piece = Instance.new("Frame")
	piece.Name = name
	piece.BackgroundColor3 = colour
	piece.BackgroundTransparency = transparency
	piece.BorderSizePixel = 0
	piece.Size = size
	piece.Position = position
	piece.ZIndex = BLACKOUT_ZINDEX + 2
	piece.Parent = completionMotif
	return piece
end

local function rounded(piece: Frame, scale: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(scale, 0)
	corner.Parent = piece
end

-- Builds the motif for a look and returns the one part of it that moves, with where it is going.
local function buildMotif(look: any): (Instance?, { [string]: any }?)
	for _, child in ipairs(completionMotif:GetChildren()) do
		child:Destroy()
	end
	local accent: Color3 = look.accent
	if look.motif == "shore" then
		-- A sun setting behind a horizon: the sea is a band across the lower third, the sun is a
		-- disc that rises out of it as the banner arrives, and the light on the water is a gradient.
		local sun = motifFrame("Sun", accent, UDim2.fromOffset(74, 74), UDim2.new(0.72, 0, 1, -34), 0.25)
		rounded(sun, 0.5)
		local sea = motifFrame("Sea", look.bottom or accent, UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 1, -44), 0.25)
		local shimmer = Instance.new("UIGradient")
		shimmer.Rotation = 90
		shimmer.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 0.85) })
		shimmer.Parent = sea
		sun.ZIndex = BLACKOUT_ZINDEX + 1
		return sun, { Position = UDim2.new(0.72, 0, 1, -74) }
	elseif look.motif == "clouds" then
		-- Cloud along the bottom edge, five humps of different sizes, and a ripple under the
		-- headline. The humps drift sideways, slowly, which is all a cloud ever does.
		local bank = motifFrame("Bank", Color3.fromRGB(246, 249, 255), UDim2.new(1.3, 0, 0, 40),
			UDim2.new(-0.15, 0, 1, -26), 0.35)
		for index = 0, 4 do
			local wide = 44 + (index % 3) * 26
			local hump = motifFrame("Hump", Color3.fromRGB(246, 249, 255), UDim2.fromOffset(wide, wide * 0.7),
				UDim2.new(-0.15, 24 + index * 108, 1, -34 - (index % 2) * 10), 0.35)
			rounded(hump, 0.5)
			hump.Parent = bank
			hump.ZIndex = bank.ZIndex
		end
		local ripple = motifFrame("Ripple", accent, UDim2.new(0, 190, 0, 2), UDim2.new(0, 28, 0, 96), 0.55)
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1) })
		fade.Parent = ripple
		return bank, { Position = UDim2.new(-0.1, 0, 1, -26) }
	elseif look.motif == "caustics" then
		-- Caustics: three pale bands leaning across a panel that is nearly black, drifting the way
		-- light does on the floor of somewhere flooded.
		local holder = motifFrame("Caustics", Color3.new(0, 0, 0), UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), 1)
		for index = 0, 2 do
			local band = Instance.new("Frame")
			band.Name = "Caustic"
			band.BackgroundColor3 = accent
			band.BackgroundTransparency = 0.86
			band.BorderSizePixel = 0
			band.Size = UDim2.new(0, 120 + index * 40, 1.6, 0)
			band.Position = UDim2.new(0, -160 + index * 150, -0.3, 0)
			band.Rotation = 18
			band.ZIndex = BLACKOUT_ZINDEX + 2
			band.Parent = holder
			local soft = Instance.new("UIGradient")
			soft.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) })
			soft.Parent = band
		end
		return holder, { Position = UDim2.fromScale(0.12, 0) }
	elseif look.motif == "door" then
		-- A door opening onto the morning: its frame, and a warm slit of light in it that widens as the banner arrives.
		motifFrame("Doorway", look.top or accent, UDim2.fromOffset(64, 100), UDim2.new(0.78, 0, 1, -100), 0.2)
		local light = motifFrame("Light", accent, UDim2.fromOffset(4, 92), UDim2.new(0.78, 4, 1, -96), 0.1)
		light.ZIndex = BLACKOUT_ZINDEX + 1
		return light, { Size = UDim2.fromOffset(56, 92) }
	elseif look.motif == "tiles" then
		-- Tile: a grid of hairlines and the dado stripe that runs round every wall in the building.
		for index = 1, 7 do
			motifFrame("Grout", Color3.fromRGB(226, 240, 236), UDim2.new(0, 1, 1, 0),
				UDim2.new(index / 8, 0, 0, 0), 0.92)
		end
		for index = 1, 3 do
			motifFrame("Grout", Color3.fromRGB(226, 240, 236), UDim2.new(1, 0, 0, 1),
				UDim2.new(0, 0, index / 4, 0), 0.92)
		end
		local dado = motifFrame("Dado", accent, UDim2.new(0, 0, 0, 6), UDim2.new(0, 0, 1, -44), 0.45)
		return dado, { Size = UDim2.new(1, 0, 0, 6) }
	end
	return nil, nil
end

local completionEyebrow = newLabel(completion, TEXT.caption, COLOUR.gold, Style.FONT.heading)
completionEyebrow.ZIndex = BLACKOUT_ZINDEX + 3
completionEyebrow.Size = UDim2.new(1, -SPACE.xl * 2, 0, 16)
completionEyebrow.Position = UDim2.new(0, SPACE.xl, 0, SPACE.xl)
completionEyebrow.TextXAlignment = Enum.TextXAlignment.Left
completionEyebrow.TextTransparency = 1

local completionTitle = newLabel(completion, TEXT.display, COLOUR.textPrimary, Style.FONT.display)
completionTitle.ZIndex = BLACKOUT_ZINDEX + 3
completionTitle.Size = UDim2.new(1, -SPACE.xl * 2, 0, 40)
completionTitle.Position = UDim2.new(0, SPACE.xl, 0, SPACE.xl + 20)
completionTitle.TextXAlignment = Enum.TextXAlignment.Left
completionTitle.TextTransparency = 1

-- IT DRAWS ITSELF IN, left to right, under the headline. One moving element is what makes the
-- banner read as an announcement arriving rather than a box switched on.
local completionRule = Instance.new("Frame")
completionRule.Name = "Rule"
completionRule.BackgroundColor3 = COLOUR.gold
completionRule.BorderSizePixel = 0
completionRule.Size = UDim2.fromOffset(0, 2)
completionRule.Position = UDim2.new(0, SPACE.xl, 0, SPACE.xl + 68)
completionRule.ZIndex = BLACKOUT_ZINDEX + 3
completionRule.BackgroundTransparency = 1
completionRule.Parent = completion

local completionMode = newLabel(completion, TEXT.label, COLOUR.textSecondary, Style.FONT.body)
completionMode.ZIndex = BLACKOUT_ZINDEX + 3
completionMode.Size = UDim2.new(0.5, -SPACE.xl, 0, 26)
completionMode.Position = UDim2.new(0, SPACE.xl, 0, SPACE.xl + 84)
completionMode.TextXAlignment = Enum.TextXAlignment.Left
completionMode.TextTransparency = 1
-- A STORY'S LINE ("Story 2 of 4. Next: The Sunken City") is longer than "Hardcore run": shrunk to fit, never bigger.
local completionModeCap = Instance.new("UITextSizeConstraint")
completionModeCap.MaxTextSize = TEXT.label
completionModeCap.Parent = completionMode

local completionTime = newLabel(completion, TEXT.mono, COLOUR.textPrimary, Style.FONT.number)
completionTime.ZIndex = BLACKOUT_ZINDEX + 3
completionTime.AnchorPoint = Vector2.new(1, 0)
completionTime.Size = UDim2.new(0.5, -SPACE.xl, 0, 30)
completionTime.Position = UDim2.new(1, -SPACE.xl, 0, SPACE.xl + 82)
completionTime.TextXAlignment = Enum.TextXAlignment.Right
completionTime.TextTransparency = 1

local completionToken = 0
local COMPLETION_HOLD = 3.6

function UIService.showCompletion(levelId: number?, time: number?, story: any?)
	completionToken += 1
	local token = completionToken
	local look: any = (levelId and COMPLETION_LOOKS[levelId]) or COMPLETION_FALLBACK

	completionEyebrow.Text = if levelId and look.name
		then ("LEVEL %d   %s"):format(levelId, string.upper(look.name))
		elseif levelId then ("LEVEL %d"):format(levelId)
		else "RUN COMPLETE"
	completionTitle.Text = look.line
	completionMode.Text = if time then "Hardcore run" else "Chill run"
	if time then
		local minutes = math.floor(time / 60)
		completionTime.Text = ("%d:%05.2f"):format(minutes, time - minutes * 60)
	else
		completionTime.Text = ""
	end
	-- THE STORY (Bootstrap): which of the four this was and what comes next; after the last, the story's own time.
	completionMode.TextScaled = false
	if type(story) == "table" and type(story.step) == "number" then
		completionMode.TextScaled = true
		if story.next then
			completionMode.Text = ("Story %d of %d. Next: %s"):format(story.step, tonumber(story.of) or 4, tostring(story.next))
		else
			completionMode.Text = "Story complete"
			if type(story.total) == "number" then
				local minutes = math.floor(story.total / 60)
				completionTime.Text = ("%d:%05.2f"):format(minutes, story.total - minutes * 60)
			end
		end
	end

	completion.BackgroundColor3 = look.tint
	-- THE PANEL'S OWN LIGHT is the level's now: its sky at the top falling to its ground at the
	-- bottom, rather than one tint shaded downward for every level alike.
	completionDepth.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, look.top or Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, look.bottom or Color3.fromRGB(150, 150, 150)),
	})
	local mover, goal = buildMotif(look)
	completionStroke.Color = look.accent
	completionEyebrow.TextColor3 = look.accent
	completionRule.BackgroundColor3 = look.accent
	completionMode.TextColor3 = if time then COLOUR.hardcore else COLOUR.chill

	-- Set low and blank, then brought up: the panel rises the last 24 pixels as it fades in.
	completion.Visible = true
	completion.Position = UDim2.new(0.5, 0, 0.36, 24)
	completion.BackgroundTransparency = 1
	completionStroke.Transparency = 1
	completionRule.Size = UDim2.fromOffset(0, 2)
	completionRule.BackgroundTransparency = 1
	completionShine.Position = UDim2.fromScale(-0.3, 0)
	for _, label in ipairs({ completionEyebrow, completionTitle, completionMode, completionTime }) do
		label.TextTransparency = 1
	end
	showVignette(true, MOTION.slow, look.vignette)

	local rise = tweenIn(MOTION.slow)
	TweenService:Create(completion, rise, {
		Position = UDim2.new(0.5, 0, 0.36, 0),
		BackgroundTransparency = 0.05,
	}):Play()
	TweenService:Create(completionStroke, rise, { Transparency = 0.3 }):Play()

	-- STAGGERED, through each tween's own delay rather than a chain of task.delay: the eyebrow,
	-- then the headline, then the rule drawing itself, then the numbers. Four beats inside half a
	-- second, which reads as one considered announcement instead of five things switched on.
	local function arrive(target: Instance, goal: { [string]: any }, delay: number, seconds: number?)
		TweenService:Create(target, TweenInfo.new(seconds or MOTION.slow, MOTION.style,
			Enum.EasingDirection.Out, 0, false, delay), goal):Play()
	end
	arrive(completionEyebrow, { TextTransparency = 0 }, 0.02)
	arrive(completionTitle, { TextTransparency = 0 }, 0.1)
	arrive(completionRule, { Size = UDim2.fromOffset(152, 2), BackgroundTransparency = 0.15 }, 0.18, 0.45)
	arrive(completionMode, { TextTransparency = 0 }, 0.26)
	arrive(completionTime, { TextTransparency = 0 }, 0.3)
	-- And one sweep of light across the panel, once, behind the text.
	arrive(completionShine, { Position = UDim2.fromScale(1.1, 0) }, 0.16, 0.8)
	-- THE MOTIF'S ONE MOVING PART: the sun rising out of the sea, the cloud drifting, the caustics
	-- sliding, the dado drawing itself along the wall. Slow, and it finishes while the banner is
	-- still up.
	if mover and goal then
		TweenService:Create(mover, TweenInfo.new(2.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out,
			0, false, 0.1), goal):Play()
	end

	task.delay(COMPLETION_HOLD, function()
		if completionToken ~= token then
			return
		end
		local out = tweenOut(MOTION.slow)
		TweenService:Create(completion, out, {
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 0.36, -16),
		}):Play()
		TweenService:Create(completionStroke, out, { Transparency = 1 }):Play()
		TweenService:Create(completionRule, out, { BackgroundTransparency = 1 }):Play()
		for _, label in ipairs({ completionEyebrow, completionTitle, completionMode, completionTime }) do
			TweenService:Create(label, out, { TextTransparency = 1 }):Play()
		end
		showVignette(false, MOTION.slow)
		task.delay(MOTION.slow, function()
			if completionToken == token then
				completion.Visible = false
				vignetteTop.Visible = false
				vignetteBottom.Visible = false
			end
		end)
	end)
end

-- ===================================================================== settings

local settingsFrame = panel("SettingsMenu", screenGui)
settingsFrame.Size = UDim2.new(0, 300, 0, 320)
Style.fit(settingsFrame, Vector2.new(300, 320))
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
leaveButton.FontFace = Style.FONT.heading
leaveButton.TextSize = 14
leaveButton.TextColor3 = Color3.fromRGB(244, 226, 228)
leaveButton.Text = "Leave level"
leaveButton.Parent = settingsFrame

local leaveCorner = Instance.new("UICorner")
leaveCorner.CornerRadius = Style.RADIUS.small
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
boardToggle.FontFace = Style.FONT.heading
boardToggle.TextSize = 14
boardToggle.TextColor3 = Color3.fromRGB(226, 228, 240)
boardToggle.Text = "Chill leaderboard: off"
boardToggle.Parent = settingsFrame

local boardToggleCorner = Instance.new("UICorner")
boardToggleCorner.CornerRadius = Style.RADIUS.small
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
Style.fit(leaderboard, Vector2.new(218, 208))
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
local leaderboardTitle = newLabel(leaderboardContent, TEXT.caption, COLOUR.textMuted, Style.FONT.heading)
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
collapse.FontFace = Style.FONT.heading
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
tabTag.FontFace = Style.FONT.heading
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
		local empty = newLabel(leaderboardContent, TEXT.body, COLOUR.textMuted, Style.FONT.body)
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
		rowCorner.CornerRadius = Style.RADIUS.small
		rowCorner.Parent = row

		local rank = newLabel(row, TEXT.body, if i == 1 then COLOUR.gold else COLOUR.textMuted, Style.FONT.heading)
		rank.Size = UDim2.new(0, 22, 1, 0)
		rank.Position = UDim2.new(0, SPACE.sm, 0, 0)
		rank.TextXAlignment = Enum.TextXAlignment.Left
		rank.Text = tostring(i)

		local who = newLabel(row, TEXT.body, if mine then COLOUR.textPrimary else COLOUR.textSecondary, Style.FONT.body)
		who.Size = UDim2.new(1, -(SPACE.sm + 22 + 84), 1, 0)
		who.Position = UDim2.new(0, SPACE.sm + 22, 0, 0)
		who.TextXAlignment = Enum.TextXAlignment.Left
		who.TextTruncate = Enum.TextTruncate.AtEnd
		who.Text = nameFor(entry.userId)

		-- Times right-aligned and monospaced, so the digits form a column you can compare
		-- straight down instead of a ragged edge you have to read row by row.
		local minutes = math.floor(entry.time / 60)
		local when = newLabel(row, TEXT.body, COLOUR.textPrimary, Style.FONT.number)
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

-- ===================================================================== phones and tablets
--
-- ON A TOUCH SCREEN WITH NO KEYBOARD the bottom corners are Roblox's own: the thumbstick on the left,
-- jump on the right. The hardcore clock, the mode and the tooltip go to the top right, under the menu
-- and journal tabs, and the best times to the top left, so nothing sits under a thumb.
do
	local input = game:GetService("UserInputService")
	if input.TouchEnabled and not input.KeyboardEnabled then
		local top = 72
		modeButton.AnchorPoint = Vector2.new(1, 0)
		modeButton.Position = UDim2.new(1, -SPACE.xl, 0, top)
		timerPanel.AnchorPoint = Vector2.new(1, 0)
		timerPanel.Position = UDim2.new(1, -SPACE.xl, 0, top + 26 + SPACE.sm)
		tooltip.AnchorPoint = Vector2.new(1, 0)
		tooltip.Position = UDim2.new(1, -SPACE.xl, 0, top + 26 + SPACE.sm + 46 + SPACE.sm)
		leaderboard.AnchorPoint = Vector2.new(0, 0)
		leaderboard.Position = UDim2.new(0, SPACE.xl, 0, SPACE.xl)
	end
end

UIService.STAMP = "75a6c86e"
return UIService
