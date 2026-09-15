--!strict
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

local HubVoteService = {}

local ACCENT = Color3.fromRGB(246, 206, 148)
local HARDCORE = Color3.fromRGB(232, 96, 88)
local CHILL = Color3.fromRGB(124, 196, 236)

local TITLE = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Bold)
local BODY = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Medium)

local gui: ScreenGui? = nil
local card: Frame? = nil
local clock: TextLabel? = nil
local headline: TextLabel? = nil
local detail: TextLabel? = nil
local ring: Frame? = nil
-- When the result card should slide back out, as an os.clock stamp. Zero means "not pending",
-- which is also what a new tick or idle update sets it to.
local dismissAt = 0

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
	panel.Size = UDim2.new(0, 440, 0, 116)
	panel.BackgroundColor3 = Color3.fromRGB(20, 19, 27)
	panel.BackgroundTransparency = 0.12
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screen
	card = panel

	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 16)
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
	title.TextColor3 = Color3.fromRGB(242, 244, 252)
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
	sub.TextColor3 = Color3.fromRGB(178, 184, 206)
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

function HubVoteService.onTick(state)
	build()
	dismissAt = 0
	local seconds = tonumber(state.secondsLeft) or 0
	if clock then
		clock.Text = tostring(seconds)
		clock.TextSize = 40
		clock.TextColor3 = ACCENT
	end
	if headline then
		headline.Text = "Starting in"
	end
	if detail then
		detail.Text = describe(state)
	end
	if ring then
		-- Warms toward the accent as it runs out, so the last three seconds LOOK like the
		-- last three seconds without anything having to say so.
		local urgency = math.clamp((10 - seconds) / 10, 0, 1)
		ring.BackgroundTransparency = 0.82 - urgency * 0.45
	end
	show(true)
end

-- BETWEEN BALLOTS, which is most of the time. The card still shows the tally, so a vote you
-- cast is visible the instant you cast it, and it says where the start pad is instead of
-- leaving the room to work out what happens next.
function HubVoteService.onIdle(state)
	build()
	dismissAt = 0
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

function HubVoteService.onCancelled()
	if clock then
		clock.TextSize = 40
		clock.TextColor3 = ACCENT
	end
	if ring then
		ring.BackgroundColor3 = ACCENT
	end
	show(false)
end

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
		elseif kind == "clear" then
			dismissAt = 0
			show(false)
		end
	end)
end)

return HubVoteService
