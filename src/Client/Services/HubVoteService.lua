--!strict
-- StarterPlayerScripts/Services/HubVoteService.lua
-- The lobby's ballot banner: what the room is voting for, and how long is left.
--
-- === Why this is a screen GUI and not more signs in the room ===
--
-- The pads already show the tally, because a vote count is the one fact about a ballot that
-- is identical for everybody and can therefore honestly live on a shared object in the world.
-- YOUR three picks are not that. They are yours, they differ from the person standing next to
-- you, and a part in the workspace has one appearance for all viewers.
--
-- So the split is: counts on the pads, your own ballot and the countdown on your own screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local HubVoteService = {}

local ACCENT = Style.COLOUR.accent
local HARDCORE = Style.COLOUR.hardcore
local CHILL = Style.COLOUR.chill

local TITLE = Style.FONT.heading
local BODY = Style.FONT.body

local gui: ScreenGui? = nil
local card: Frame? = nil
local clock: TextLabel? = nil
local headline: TextLabel? = nil
local detail: TextLabel? = nil
local ring: Frame? = nil
-- When the result card should slide back out, as an os.clock stamp. Zero means "not pending",
-- which is also what a new tick or idle update sets it to.
local dismissAt = 0
-- A LOCKED PAD (onLocked) holds the card for LOCKED_FOR seconds; the tally that arrives meanwhile is kept in
-- lastState and shown after.
local LOCKED_FOR = 4
local lockedUntil = 0
local lastState: any = nil
local lastKind = "idle"

-- THE COUNTDOWN, KEPT HERE. The server says when it ends, on the clock every client shares; this
-- counts down to it every frame and, when the whole second changes, shows the new numeral and plays
-- the tick at the same moment. The server used to play each tick itself, and a sound made on the
-- server arrives when it replicates -- in pairs, 0.8 and 1.2 of a second apart.
local endsAt: number? = nil
local shownSeconds: number? = nil
-- THE TICK: a soft wooden tock each second, a little brighter for the last three, and a warm two-note chime as it
-- runs out (audio/gen_countdown_sfx.py: three takes in one upload, SoundService.StorySounds.CountdownTock_x3, each in
-- its own one-second slot). It was the engine's electronic ping, which was the wrong kind of sound for this game.
-- The same chime greets a level the run you are back from has opened. Until it is imported, a soft click stands in.
local TICK_SLOT = 1.0
local TICK = Instance.new("Sound")
TICK.Name = "CountdownTick"
TICK.SoundId = "rbxasset://sounds/clickfast.wav"
TICK.Volume = 0.35
TICK.Parent = SoundService
local function tock(which: number)
	local folder = SoundService:FindFirstChild("StorySounds")
	local sheet = folder and folder:FindFirstChild("CountdownTock_x3")
	if not (sheet and sheet:IsA("Sound")) then
		TICK.PlaybackSpeed = if which == 0 then 0.75 else 0.95
		TICK.TimePosition = 0
		TICK:Play()
		if which == 2 then
			task.delay(0.16, function()
				TICK.PlaybackSpeed = 1.15
				TICK.TimePosition = 0
				TICK:Play()
			end)
		end
		return
	end
	local s = sheet:Clone()
	s.Volume = 0.5
	local from = which * TICK_SLOT
	local regioned = pcall(function()
		(s :: any).PlaybackRegionsEnabled = true;
		(s :: any).PlaybackRegion = NumberRange.new(from, from + TICK_SLOT - 0.05)
	end)
	s.TimePosition = from
	s.Parent = SoundService
	s:Play()
	if not regioned then
		task.delay(TICK_SLOT - 0.07, function()
			if s.Parent then
				s:Stop()
			end
		end)
	end
	game:GetService("Debris"):AddItem(s, TICK_SLOT + 0.5)
end

local function build(): Frame
	local existing = card
	if existing then
		return existing
	end

	local player = Players.LocalPlayer
	local screen = Instance.new("ScreenGui")
	screen.Name = "HubVote"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 8
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen

	-- TOP CENTRE, not a corner. A countdown that decides what everyone is about to play is
	-- the most important thing on screen while it runs, and it should sit where the eye
	-- already is rather than where notifications go to be ignored.
	local panel = Instance.new("Frame")
	panel.Name = "Card"
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, -140)
	-- NO WIDER THAN THE SCREEN on a phone held upright.
	panel.Size = UDim2.new(0.92, 0, 0, 116)
	local most = Instance.new("UISizeConstraint")
	most.MaxSize = Vector2.new(440, 116)
	most.Parent = panel
	panel.BackgroundColor3 = Style.COLOUR.panel
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen
	card = panel

	local round = Instance.new("UICorner")
	round.CornerRadius = Style.RADIUS.panel
	round.Parent = panel

	local edge = Instance.new("UIStroke")
	edge.Thickness = 2
	edge.Color = ACCENT
	edge.Transparency = 0.4
	edge.Parent = panel

	-- The seconds as one big numeral in its own disc. A countdown reads as a countdown when
	-- the number is the largest thing in the frame.
	local disc = Instance.new("Frame")
	disc.Name = "Ring"
	disc.AnchorPoint = Vector2.new(0, 0.5)
	disc.Position = UDim2.new(0, 16, 0.5, 0)
	disc.Size = UDim2.new(0, 76, 0, 76)
	disc.BackgroundColor3 = ACCENT
	disc.BackgroundTransparency = 0.82
	disc.BorderSizePixel = 0
	disc.Parent = panel
	ring = disc

	local discRound = Instance.new("UICorner")
	discRound.CornerRadius = UDim.new(0.5, 0)
	discRound.Parent = disc

	local seconds = Instance.new("TextLabel")
	seconds.Name = "Clock"
	seconds.Size = UDim2.new(1, 0, 1, 0)
	seconds.BackgroundTransparency = 1
	seconds.FontFace = TITLE
	seconds.TextSize = 40
	seconds.TextColor3 = ACCENT
	seconds.Text = "10"
	seconds.Parent = disc
	clock = seconds

	local title = Instance.new("TextLabel")
	title.Name = "Headline"
	title.Position = UDim2.new(0, 108, 0, 22)
	title.Size = UDim2.new(1, -124, 0, 32)
	title.BackgroundTransparency = 1
	title.FontFace = TITLE
	title.TextSize = 26
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextColor3 = Style.COLOUR.ink
	title.Text = "Vote in progress"
	title.Parent = panel
	headline = title

	local sub = Instance.new("TextLabel")
	sub.Name = "Detail"
	sub.Position = UDim2.new(0, 108, 0, 56)
	sub.Size = UDim2.new(1, -124, 0, 40)
	sub.BackgroundTransparency = 1
	sub.FontFace = BODY
	sub.TextSize = 18
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextYAlignment = Enum.TextYAlignment.Top
	sub.TextWrapped = true
	sub.TextColor3 = Style.COLOUR.inkSoft
	sub.Text = ""
	sub.Parent = panel
	detail = sub

	return panel
end

-- Slides in from above rather than appearing. A card that pops into existence gets read as a
-- glitch; a card that arrives gets read as an announcement.
local function show(visible: boolean)
	local panel = build()
	local to = if visible then UDim2.new(0.5, 0, 0, 24) else UDim2.new(0.5, 0, 0, -140)
	if visible then
		panel.Visible = true
	end
	local slide = TweenService:Create(panel,
		TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Position = to })
	slide:Play()
	if not visible then
		slide.Completed:Once(function()
			panel.Visible = false
		end)
	end
end

local function describe(state): string
	local leading = state.leading
	if not leading then
		return ""
	end
	local name = "?"
	for _, level in ipairs(state.levels or {}) do
		if level.levelId == leading.levelId then
			name = level.name
		end
	end
	-- READ STRAIGHT OFF THE PAYLOAD, not looked up by level id.
	--
	-- The old line indexed a table keyed by level id, and a sparse numeric table does not
	-- survive the trip: "Open Sky (0)" while Open Sky was winning. City Shore is id 1, so its
	-- table serialised as a one-element array and it alone read correctly, which is exactly
	-- the pattern that got reported.
	local votes = state.leadingVotes or {}
	return ("%s (%d)   %s (%d)   %s (%d)"):format(
		name, votes.level or 0, leading.mode, votes.mode or 0,
		leading.length, votes.length or 0)
end

-- THE RESULT CARD LEAVES ON ITS OWN.
--
-- It slid in to announce the vote and then stayed there for the whole run, over the top of the
-- level. An announcement that does not end is a HUD element, and this was never meant to be
-- one -- the pause menu carries the run's settings for anyone who wants them later.
--
-- Long enough to read twice, and it leaves by the same slide it arrived on.
local function dismissSoon(after: number)
	dismissAt = os.clock() + after
	local mine = dismissAt
	task.delay(after, function()
		-- Only if nothing has happened since. A new ballot opening during the wait must not be
		-- closed by a timer belonging to the last one.
		if dismissAt == mine then
			show(false)
		end
	end)
end

local function showSeconds(seconds: number)
	if clock then
		clock.Text = tostring(seconds)
		clock.TextSize = 40
		clock.TextColor3 = ACCENT
	end
	if ring then
		-- Warms toward the accent as it runs out, so the last three seconds LOOK like the
		-- last three seconds without anything having to say so.
		local urgency = math.clamp((10 - seconds) / 10, 0, 1)
		ring.BackgroundTransparency = 0.82 - urgency * 0.45
	end
end

RunService.RenderStepped:Connect(function()
	local deadline = endsAt
	if not deadline then
		return
	end
	local left = math.ceil(deadline - workspace:GetServerTimeNow() - 0.001)
	if left >= 1 and left ~= shownSeconds then
		shownSeconds = left
		showSeconds(left)
		-- The last three a little brighter: a countdown you can hear closing.
		tock(if left <= 3 then 1 else 0)
	elseif left <= 0 and shownSeconds and shownSeconds >= 1 then
		-- And as it runs out, the chime.
		shownSeconds = 0
		tock(2)
	end
end)

function HubVoteService.onTick(state)
	build()
	dismissAt = 0
	lastState, lastKind = state, "tick"
	local seconds = tonumber(state.secondsLeft) or 0
	local deadline = tonumber(state.endsAt)
	if deadline then
		-- The numeral and the tick are the frame loop's; a vote cast mid-countdown only
		-- refreshes the tally below.
		endsAt = deadline
	else
		showSeconds(seconds)
	end
	if os.clock() < lockedUntil then
		return
	end
	if headline then
		headline.Text = "Starting in"
	end
	if detail then
		detail.Text = describe(state)
	end
	show(true)
end

-- BETWEEN BALLOTS, which is most of the time. The card still shows the tally, so a vote you
-- cast is visible the instant you cast it, and it says where the start pad is instead of
-- leaving the room to work out what happens next.
function HubVoteService.onIdle(state)
	build()
	dismissAt = 0
	endsAt, shownSeconds = nil, nil
	lastState, lastKind = state, "idle"
	if os.clock() < lockedUntil then
		return
	end
	if clock then
		clock.Text = "VOTE"
		clock.TextSize = 24
		clock.TextColor3 = ACCENT
	end
	if ring then
		ring.BackgroundColor3 = ACCENT
		ring.BackgroundTransparency = 0.82
	end
	if headline then
		headline.Text = "Step on START to begin"
	end
	if detail then
		detail.Text = describe(state)
	end
	show(true)
end

function HubVoteService.onResult(result)
	build()
	lockedUntil = 0
	-- The ballot is over: nothing from it is shown again after a held message (a stale countdown would be).
	lastState, lastKind = nil, "idle"
	endsAt, shownSeconds = nil, nil
	local hardcore = result.mode == "hardcore"
	if clock then
		clock.Text = "GO"
		clock.TextSize = 30
		clock.TextColor3 = if hardcore then HARDCORE else CHILL
	end
	if ring then
		ring.BackgroundColor3 = if hardcore then HARDCORE else CHILL
		ring.BackgroundTransparency = 0.55
	end
	if headline then
		headline.Text = tostring(result.levelName)
	end
	if detail then
		detail.Text = ("%s  -  %s run  -  %d %s voting"):format(
			tostring(result.mode), tostring(result.length),
			tonumber(result.voters) or 0,
			if (tonumber(result.voters) or 0) == 1 then "player" else "players")
	end
	show(true)
	dismissSoon(4.5)
end

-- A LOCKED PAD STEPPED ON (HubService.tellLocked, to you alone): which level, and what opens it. Then back to
-- the tally.
function HubVoteService.onLocked(payload)
	if type(payload) ~= "table" then
		return
	end
	build()
	dismissAt = 0
	lockedUntil = os.clock() + LOCKED_FOR
	local mine = lockedUntil
	if clock and endsAt == nil then
		clock.Text = "LOCKED"
		clock.TextSize = 17
		clock.TextColor3 = ACCENT
	end
	if headline then
		headline.Text = tostring(payload.name)
	end
	if detail then
		detail.Text = ("Locked. Finish %s to open it, or play with someone who has."):format(tostring(payload.before))
	end
	show(true)
	task.delay(LOCKED_FOR, function()
		if lockedUntil ~= mine then
			return
		end
		lockedUntil = 0
		local state = lastState
		if state and lastKind == "tick" then
			HubVoteService.onTick(state)
		elseif state then
			HubVoteService.onIdle(state)
		end
	end)
end

-- A LEVEL OPENED by the run you have just come back from (HubService.tellOpened, to you alone): its name and the
-- countdown's two-note marimba chime, held for OPENED_FOR seconds, then the tally (or nothing, if no ballot has been
-- shown since).
local OPENED_FOR = 5

function HubVoteService.onOpened(payload)
	if type(payload) ~= "table" or type(payload.names) ~= "table" or #payload.names == 0 then
		return
	end
	local names = {}
	for _, name in ipairs(payload.names) do
		table.insert(names, tostring(name))
	end
	local many = #names > 1
	local title = table.concat(names, " and ") .. (if many then " are open" else " is open")
	local body = if many then "New levels. Step on their pads to vote for them." else "A new level. Step on its pad to vote for it."
	HubVoteService.say("NEW", title, body)
	tock(2)
end

-- A HELD MESSAGE on the card, to you alone: a short badge in the disc, a headline and a line under it, for
-- OPENED_FOR seconds, then the tally (or nothing, if no ballot has been shown since).
function HubVoteService.say(badge: string, title: string, body: string)
	build()
	dismissAt = 0
	lockedUntil = os.clock() + OPENED_FOR
	local mine = lockedUntil
	if clock and endsAt == nil then
		clock.Text = badge
		clock.TextSize = if #badge > 4 then 18 else 26
		clock.TextColor3 = ACCENT
	end
	if headline then
		headline.Text = title
	end
	if detail then
		detail.Text = body
	end
	show(true)
	task.delay(OPENED_FOR, function()
		if lockedUntil ~= mine then
			return
		end
		lockedUntil = 0
		local state = lastState
		if state and lastKind == "tick" then
			HubVoteService.onTick(state)
		elseif state then
			HubVoteService.onIdle(state)
		else
			show(false)
		end
	end)
end

-- AN ADMIN'S /levels (EconomyService), to them alone: every level open for them, or back to their own progress.
function HubVoteService.onAdmin(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.on then
		HubVoteService.say("ADMIN", "Every level open for you", "Your save is unchanged. Type /levels again to turn it off.")
	else
		HubVoteService.say("ADMIN", "Levels back to your progress", "Type /levels to open every level for yourself again.")
	end
end

-- THE DAILY CHEST (HubService; EconomyService.claimDaily), on your own screen: its prompt says whether it opens today
-- (your DailyNext, on the server's clock), its lid lifts for you when it pays, and opened too soon, this card says
-- how long until the next one.
local function dailyChest(): Model?
	local hub = workspace:FindFirstChild("Hub")
	local chest = hub and hub:FindFirstChild("DailyChest")
	return if chest and chest:IsA("Model") then chest else nil
end

task.spawn(function()
	while true do
		local chest = dailyChest()
		local prompt = chest and chest:FindFirstChild("DailyPrompt", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			local nextAt = Players.LocalPlayer:GetAttribute("DailyNext")
			local ready = typeof(nextAt) ~= "number" or nextAt == 0 or workspace:GetServerTimeNow() >= nextAt
			prompt.ActionText = if ready then "Open" else "Opened today"
		end
		task.wait(2)
	end
end)

-- The lid, lifted on its back edge and let down again, on this screen only.
local function liftLid()
	local chest = dailyChest()
	local lid = chest and chest:FindFirstChild("Lid")
	if not (lid and lid:IsA("BasePart")) then
		return
	end
	local rest = lid.CFrame
	local hinge = rest * CFrame.new(0, -lid.Size.Y / 2, lid.Size.Z / 2)
	local open = hinge * CFrame.Angles(math.rad(70), 0, 0) * hinge:Inverse() * rest
	TweenService:Create(lid, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = open }):Play()
	task.delay(3.5, function()
		TweenService:Create(lid, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = rest }):Play()
	end)
end

function HubVoteService.onDaily(payload)
	if type(payload) ~= "table" then
		return
	end
	local streak = tonumber(payload.streak) or 1
	if payload.opened then
		liftLid()
		HubVoteService.say("DAY " .. streak, "Daily chest", ("+%d tokens. Come back tomorrow for day %d; miss a day and it starts again.")
			:format(tonumber(payload.amount) or 0, streak + 1))
	elseif payload.loading then
		HubVoteService.say("DAILY", "Daily chest", "Your save is still loading. Try again in a moment.")
	else
		local left = math.max(0, tonumber(payload.nextIn) or 0)
		HubVoteService.say("DAILY", "Opened today", ("The next one opens in %dh %02dm. You are on day %d."):format(
			math.floor(left / 3600), math.floor(left % 3600 / 60), streak))
	end
end

-- ===== TODAY'S CHALLENGES (EconomyService.challengeRun), on your own screen =====
--
-- The lobby's board (HubService) is the same wood for everyone; what is written on it is yours, drawn here on a
-- SurfaceGui of your own over its panel: today's three, ticked as you do them, and when new ones come. One done, this
-- card says so as it pays. Read from your attributes: Challenges, ChallengesDone, ChallengeRuns, ChallengeNext.
local PAPER = Color3.fromRGB(250, 243, 226)
local INK = Color3.fromRGB(64, 46, 34)
local DONE = Color3.fromRGB(15, 110, 86)

local challengeCatalog: any = nil
local function catalog(): any
	if challengeCatalog == nil then
		local shared = ReplicatedStorage:FindFirstChild("Shared")
		local module = shared and shared:FindFirstChild("ShopCatalog")
		if module and module:IsA("ModuleScript") then
			local ok, loaded = pcall(require, module)
			if ok then
				challengeCatalog = loaded
			end
		end
	end
	return challengeCatalog
end

local function split(value: any): { string }
	local list = {}
	if type(value) == "string" then
		for id in string.gmatch(value, "[^,]+") do
			table.insert(list, id)
		end
	end
	return list
end

local function boardPanel(): BasePart?
	local hub = workspace:FindFirstChild("Hub")
	local board = hub and hub:FindFirstChild("ChallengeBoard")
	local panel = board and board:FindFirstChild("Panel")
	return if panel and panel:IsA("BasePart") then panel else nil
end

local function boardLabel(parent: Instance, font: Font, size: number): TextLabel
	local made = Instance.new("TextLabel")
	made.BackgroundTransparency = 1
	made.FontFace = font
	made.TextSize = size
	made.TextColor3 = INK
	made.TextWrapped = true
	made.TextXAlignment = Enum.TextXAlignment.Left
	made.Text = ""
	made.Parent = parent
	return made
end

type BoardRow = { box: Frame, words: TextLabel, prize: TextLabel }
local boardGui: SurfaceGui? = nil
local boardRows: { BoardRow } = {}
local boardFoot: TextLabel? = nil

-- The panel's face, 7 by 4.6 studs at 64 pixels a stud: a title, three rows (a box, the words, the tokens), and when
-- new ones come at the foot.
local function buildBoard(): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ChallengeBoardFace"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 64
	gui.LightInfluence = 0.3
	gui.MaxDistance = 140
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local paper = Instance.new("Frame")
	paper.Size = UDim2.fromScale(1, 1)
	paper.BackgroundColor3 = PAPER
	paper.BorderSizePixel = 0
	paper.Parent = gui
	local title = boardLabel(paper, TITLE, 30)
	title.Text = "Today's challenges"
	title.Position = UDim2.new(0, 18, 0, 10)
	title.Size = UDim2.new(1, -36, 0, 40)
	table.clear(boardRows)
	for index = 1, 3 do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Position = UDim2.new(0, 18, 0, 58 + (index - 1) * 64)
		row.Size = UDim2.new(1, -36, 0, 56)
		row.Parent = paper
		local box = Instance.new("Frame")
		box.Size = UDim2.fromOffset(32, 32)
		box.Position = UDim2.new(0, 0, 0.5, -16)
		box.BackgroundColor3 = PAPER
		box.Parent = row
		local round = Instance.new("UICorner")
		round.CornerRadius = Style.RADIUS.small
		round.Parent = box
		local edge = Instance.new("UIStroke")
		edge.Color = INK
		edge.Thickness = 3
		edge.Parent = box
		local words = boardLabel(row, BODY, 22)
		words.Position = UDim2.new(0, 46, 0, 0)
		words.Size = UDim2.new(1, -126, 1, 0)
		local prize = boardLabel(row, TITLE, 24)
		prize.Position = UDim2.new(1, -80, 0, 0)
		prize.Size = UDim2.new(0, 80, 1, 0)
		prize.TextXAlignment = Enum.TextXAlignment.Right
		table.insert(boardRows, { box = box, words = words, prize = prize })
	end
	local foot = boardLabel(paper, BODY, 19)
	foot.Position = UDim2.new(0, 18, 1, -40)
	foot.Size = UDim2.new(1, -36, 0, 30)
	foot.TextTransparency = 0.25
	boardFoot = foot
	boardGui = gui
	return gui
end

local function drawBoard()
	local panel = boardPanel()
	if not panel then
		return
	end
	local gui = boardGui
	if not (gui and gui.Parent) then
		gui = buildBoard()
	end
	if gui then
		gui.Adornee = panel
	end
	local me = Players.LocalPlayer
	local ids = split(me:GetAttribute("Challenges"))
	local done = {}
	for _, id in ipairs(split(me:GetAttribute("ChallengesDone"))) do
		done[id] = true
	end
	local runs = tonumber(me:GetAttribute("ChallengeRuns")) or 0
	local shop = catalog()
	for index, row in ipairs(boardRows) do
		local challenge = if shop and ids[index] then shop.challenge(ids[index]) else nil
		if challenge then
			local finished = done[challenge.id] == true
			local words = challenge.text
			if challenge.count and not finished then
				words = ("%s (%d of %d)"):format(words, math.min(runs, challenge.count), challenge.count)
			end
			row.words.Text = words
			row.words.TextTransparency = if finished then 0.45 else 0
			row.prize.Text = if finished then "Done" else "+" .. challenge.reward
			row.prize.TextColor3 = if finished then DONE else INK
			row.box.BackgroundColor3 = if finished then DONE else PAPER
		else
			row.words.Text = if index == 1 then "Your challenges are on their way." else ""
			row.words.TextTransparency = 0
			row.prize.Text = ""
			row.box.BackgroundColor3 = PAPER
		end
		row.box.Visible = challenge ~= nil
	end
	local foot = boardFoot
	local nextAt = me:GetAttribute("ChallengeNext")
	if foot then
		if typeof(nextAt) == "number" then
			local left = math.max(0, nextAt - workspace:GetServerTimeNow())
			foot.Text = ("New ones in %dh %02dm"):format(math.floor(left / 3600), math.floor(left % 3600 / 60))
		else
			foot.Text = ""
		end
	end
end

-- ONE DONE: this card says which, what it paid and how many are done today. Only for ones done while you watch, so
-- a save loading or a new day (a different three) says nothing. SEEN FIRST: a save's three and what is done of them
-- can reach this screen one after the other, in either order; until what is done has been seen once for these
-- three (seenDone), nothing is new, or a challenge done earlier today was told again on joining.
local knownIds: string? = nil
local knownDone: { [string]: boolean } = {}
local seenDone = false
local function noticeDone()
	local me = Players.LocalPlayer
	local ids = me:GetAttribute("Challenges")
	local doneValue = me:GetAttribute("ChallengesDone")
	local doneList = split(doneValue)
	local fresh = {}
	if type(ids) == "string" and ids == knownIds and seenDone then
		for _, id in ipairs(doneList) do
			if not knownDone[id] then
				table.insert(fresh, id)
			end
		end
	end
	knownIds = if type(ids) == "string" then ids else nil
	seenDone = type(doneValue) == "string"
	table.clear(knownDone)
	for _, id in ipairs(doneList) do
		knownDone[id] = true
	end
	local shop = catalog()
	if #fresh == 0 or not shop then
		return
	end
	local reward = 0
	local words = {}
	for _, id in ipairs(fresh) do
		local challenge = shop.challenge(id)
		if challenge then
			reward += challenge.reward
			table.insert(words, challenge.text)
		end
	end
	local title = "Challenge done"
	if #fresh > 1 then
		title = #fresh .. " challenges done"
	end
	HubVoteService.say("+" .. reward, title, ("%s. %d of %d done today."):format(table.concat(words, ", "), #doneList,
		#split(ids)))
end

task.spawn(function()
	local me = Players.LocalPlayer
	for _, name in ipairs({ "Challenges", "ChallengesDone", "ChallengeRuns", "ChallengeNext" }) do
		me:GetAttributeChangedSignal(name):Connect(function()
			if name == "Challenges" or name == "ChallengesDone" then
				noticeDone()
			end
			drawBoard()
		end)
	end
	noticeDone()
	while true do
		drawBoard()
		task.wait(30)
	end
end)

-- ===== THE MATERIALS FOUND (EconomyService.foundMaterial), on your own screen =====
--
-- The board beside the challenges (HubService's MaterialsBoard) carries your collection: how many you have found, and
-- each by name beside its colour, or a "?" for one still to find. Drawn here from your Materials attribute.
type MaterialCell = { dot: Frame, name: TextLabel }
local materialsGui: SurfaceGui? = nil
local materialCells: { MaterialCell } = {}
local materialsTitle: TextLabel? = nil

local function materialsPanel(): BasePart?
	local hub = workspace:FindFirstChild("Hub")
	local board = hub and hub:FindFirstChild("MaterialsBoard")
	local panel = board and board:FindFirstChild("Panel")
	return if panel and panel:IsA("BasePart") then panel else nil
end

-- The panel's face, 7 by 4.6 studs at 64 pixels a stud: the count at the top, then three columns of names.
local function buildMaterialsFace(count: number): SurfaceGui
	local face = Instance.new("SurfaceGui")
	face.Name = "MaterialsBoardFace"
	face.Face = Enum.NormalId.Front
	face.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	face.PixelsPerStud = 64
	face.LightInfluence = 0.3
	face.MaxDistance = 140
	face.ResetOnSpawn = false
	face.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local paper = Instance.new("Frame")
	paper.Size = UDim2.fromScale(1, 1)
	paper.BackgroundColor3 = PAPER
	paper.BorderSizePixel = 0
	paper.Parent = face
	local title = boardLabel(paper, TITLE, 26)
	title.Position = UDim2.new(0, 18, 0, 10)
	title.Size = UDim2.new(1, -36, 0, 34)
	materialsTitle = title
	table.clear(materialCells)
	local rows = math.max(1, math.ceil(count / 3))
	local rowHeight = math.floor(236 / rows)
	for index = 1, count do
		local cell = Instance.new("Frame")
		cell.BackgroundTransparency = 1
		cell.Position = UDim2.new(0, 18 + ((index - 1) % 3) * 140, 0, 50 + math.floor((index - 1) / 3) * rowHeight)
		cell.Size = UDim2.new(0, 136, 0, rowHeight)
		cell.Parent = paper
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(14, 14)
		dot.Position = UDim2.new(0, 0, 0.5, -7)
		dot.BackgroundColor3 = PAPER
		dot.Parent = cell
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = dot
		local edge = Instance.new("UIStroke")
		edge.Color = INK
		edge.Thickness = 2
		edge.Parent = dot
		local name = boardLabel(cell, BODY, 15)
		name.Position = UDim2.new(0, 22, 0, 0)
		name.Size = UDim2.new(1, -22, 1, 0)
		name.TextScaled = true
		local most = Instance.new("UITextSizeConstraint")
		most.MaxTextSize = 15
		most.Parent = name
		table.insert(materialCells, { dot = dot, name = name })
	end
	materialsGui = face
	return face
end

local function drawMaterials()
	local panel = materialsPanel()
	local shop = catalog()
	if not (panel and shop and type(shop.MATERIALS) == "table") then
		return
	end
	local face = materialsGui
	if not (face and face.Parent) then
		face = buildMaterialsFace(#shop.MATERIALS)
	end
	if face then
		face.Adornee = panel
	end
	local have = {}
	for _, key in ipairs(split(Players.LocalPlayer:GetAttribute("Materials"))) do
		have[key] = true
	end
	local found = 0
	for index, material in ipairs(shop.MATERIALS) do
		local cell = materialCells[index]
		local got = have[material.key] == true
		if got then
			found += 1
		end
		if cell then
			cell.dot.BackgroundColor3 = if got then material.colour else PAPER
			cell.name.Text = if got then material.name else "?"
			cell.name.TextTransparency = if got then 0 else 0.55
		end
	end
	local title = materialsTitle
	if title then
		title.Text = ("Materials found  %d of %d"):format(found, #shop.MATERIALS)
	end
end

task.spawn(function()
	Players.LocalPlayer:GetAttributeChangedSignal("Materials"):Connect(drawMaterials)
	while true do
		drawMaterials()
		task.wait(10)
	end
end)

-- THE STORY, to you alone (Bootstrap): waiting in the lobby for the rest to finish a level, or gone on without you.
function HubVoteService.onStory(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.what == "waiting" then
		local extra = if type(payload.extra) == "table" then payload.extra else {}
		local playing = tonumber(extra.playing) or 1
		local who = if playing == 1 then "1 player is" else playing .. " players are"
		HubVoteService.say("STORY", "Waiting for the others",
			("%s still on %s. The story goes on when they finish."):format(who, tostring(extra.level or "the level")))
	elseif payload.what == "behind" then
		HubVoteService.say("STORY", "The story went on without you", "Step on the Story pad to go on from where your save is.")
	end
end

-- A FRIEND IN YOUR RUN (Bootstrap, from EconomyService.newlyWithFriends), to you alone, once while you are here: what
-- reaching the end together pays.
function HubVoteService.onFriend(payload)
	local percent = if type(payload) == "table" then tonumber(payload.percent) or 20 else 20
	HubVoteService.say("+" .. percent .. "%", "Running with a friend",
		("A friend of yours is on this run. Reach the end and it pays %d%% more tokens."):format(percent))
end

-- START STEPPED ON WHILE A RUN IS ON (HubService.tellBusy), to you alone: how many are still playing.
function HubVoteService.onBusy(payload)
	local playing = if type(payload) == "table" then tonumber(payload.playing) or 0 else 0
	local who = if playing == 1 then "1 player is" else playing .. " players are"
	HubVoteService.say("WAIT", "A run is still on", who .. " still playing. Start works again once everyone is back.")
end

function HubVoteService.onCancelled()
	lockedUntil = 0
	endsAt, shownSeconds = nil, nil
	if clock then
		clock.TextSize = 40
		clock.TextColor3 = ACCENT
	end
	if ring then
		ring.BackgroundColor3 = ACCENT
	end
	show(false)
end

-- YOUR OWN STATUE. Everyone's statue stands on the same plinth (HubService.buildStatue, tag LobbyStatue, its
-- Owner the player's id); this screen shows only its own, hidden from here rather than taken down, so the
-- others' screens still have theirs. A figure that loads later, or a pose that swaps it, is hidden as it
-- arrives.
local function hideOthers(stand: Instance)
	if stand:GetAttribute("Owner") == Players.LocalPlayer.UserId then
		return
	end
	local function hide(item: Instance)
		if item:IsA("BasePart") or item:IsA("Decal") then
			(item :: any).LocalTransparencyModifier = 1
		elseif item:IsA("LayerCollector") or item:IsA("ParticleEmitter") or item:IsA("Light") then
			(item :: any).Enabled = false
		elseif item:IsA("Humanoid") then
			item.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end
	hide(stand)
	for _, item in ipairs(stand:GetDescendants()) do
		hide(item)
	end
	stand.DescendantAdded:Connect(hide)
end

task.spawn(function()
	local CollectionService = game:GetService("CollectionService")
	for _, stand in ipairs(CollectionService:GetTagged("LobbyStatue")) do
		hideOthers(stand)
	end
	CollectionService:GetInstanceAddedSignal("LobbyStatue"):Connect(hideOthers)
end)

-- WAITS WITH A TIMEOUT, always. WaitForChild with no timeout is how a client service becomes
-- one that never finishes starting, and every other service in this folder would be waiting
-- behind it.
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	local state = remotes and remotes:WaitForChild("HubVoteState", 20)
	if not (state and state:IsA("RemoteEvent")) then
		return
	end
	state.OnClientEvent:Connect(function(kind: string, payload: any)
		if kind == "tick" then
			HubVoteService.onTick(payload)
		elseif kind == "idle" then
			HubVoteService.onIdle(payload)
		elseif kind == "result" then
			HubVoteService.onResult(payload)
		elseif kind == "cancelled" then
			HubVoteService.onCancelled()
		elseif kind == "locked" then
			HubVoteService.onLocked(payload)
		elseif kind == "opened" then
			HubVoteService.onOpened(payload)
		elseif kind == "admin" then
			HubVoteService.onAdmin(payload)
		elseif kind == "busy" then
			HubVoteService.onBusy(payload)
		elseif kind == "story" then
			HubVoteService.onStory(payload)
		elseif kind == "daily" then
			HubVoteService.onDaily(payload)
		elseif kind == "friend" then
			HubVoteService.onFriend(payload)
		elseif kind == "clear" then
			dismissAt = 0
			lockedUntil = 0
			lastState, lastKind = nil, "idle"
			show(false)
		end
	end)
end)

HubVoteService.STAMP = "39a9ce1b"
return HubVoteService
