--!strict
-- ReplicatedFirst/Arrival.client.lua
-- THE ARRIVAL (the hundred-and-fifty-ninth pass): what you see from the moment you join until Harrow Bay is there to be
-- seen. It was Roblox's own loading screen, and then the lobby arriving round you as it streamed in: the boards under
-- you after you, the textures after the boards, the sea's sound after the sea. Now the screen is the game's own black
-- from the first frame, the card a dip puts on it (UIService.fadeCard) with the bay's name, and its gold rule drawing
-- itself as the place comes in: the game loaded, you in it, the ground under you streamed in, the first things you will
-- see and hear fetched. Then it fades as a dip does (Bootstrap's DIP.back), and the welcome waits for it
-- (OnboardingService). While it is up, `Arriving` is set on you, which is all the rest of the game needs to know.
--
-- IT BORROWS NOTHING. A script here runs before anything else has arrived, Style included, which is the point of it:
-- so its faces and colours are Style's written out (blender/check_style.py holds them to Style's own), and it waits on
-- nothing that may never come. However slow the rest is, it is gone ARRIVE.most seconds after the game has loaded (and
-- before the game has loaded there would only have been Roblox's own screen to look at).

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ARRIVE = {
	least = 1.2, -- seconds the card is up at the least, so it reads as a card and not a flicker
	most = if RunService:IsStudio() then 4 else 12, -- seconds after the game has loaded at the most, whatever is still coming
	ground = 8, -- seconds the ground under you is waited for
	fetch = 6, -- seconds the first things you will see and hear are waited for
	out = 0.9, -- the fade back up (a dip's)
}

-- Style's, written out (Style.FONT.display, .heading, .body; Style.COLOUR.ink, .inkSoft, .inkMuted, .accent).
local NUNITO = "rbxasset://fonts/families/Nunito.json"
local DISPLAY = Font.new(NUNITO, Enum.FontWeight.Heavy, Enum.FontStyle.Normal)
local HEADING = Font.new(NUNITO, Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local BODY = Font.new(NUNITO, Enum.FontWeight.Medium, Enum.FontStyle.Normal)
local INK = Color3.fromRGB(242, 244, 252)
local INK_SOFT = Color3.fromRGB(178, 184, 206)
local INK_MUTED = Color3.fromRGB(126, 128, 150)
local GOLD = Color3.fromRGB(246, 206, 148)
local RULE = 120 -- the rule's length when all is in (UIService's card's)

local me = Players.LocalPlayer
me:SetAttribute("Arriving", true)

-- ===== THE CARD =====

-- Over everything there is, the Studio test panel (60) too, for as long as it is up.
local gui = Instance.new("ScreenGui")
gui.Name = "Arrival"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 70

local sheet = Instance.new("Frame")
sheet.Name = "Black"
sheet.BackgroundColor3 = Color3.new(0, 0, 0)
sheet.BorderSizePixel = 0
sheet.Size = UDim2.fromScale(1, 1)
sheet.Parent = gui

local card = Instance.new("Frame")
card.Name = "Card"
card.BackgroundTransparency = 1
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.46)
card.Size = UDim2.new(0.9, 0, 0, 132)
card.Parent = sheet

local function words(text: string, face: Font, size: number, colour: Color3, y: number, height: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 0, 0, y)
	label.Size = UDim2.new(1, 0, 0, height)
	label.FontFace = face
	label.TextSize = size
	label.TextColor3 = colour
	label.TextTransparency = 1
	label.Text = text
	label.Parent = card
	return label
end

-- In spaced capitals over the name, as a level's is on a dip.
local eyebrow = words((string.upper("Welcome to"):gsub(".", "%0 ")):sub(1, -2), HEADING, 16, INK_SOFT, 0, 22)
local title = words("Harrow Bay", DISPLAY, 40, INK, 28, 48)
title.TextScaled = true
local titleMost = Instance.new("UITextSizeConstraint")
titleMost.MaxTextSize = 40
titleMost.Parent = title
local rule = Instance.new("Frame")
rule.Name = "Rule"
rule.AnchorPoint = Vector2.new(0.5, 0)
rule.Position = UDim2.new(0.5, 0, 0, 86)
rule.Size = UDim2.fromOffset(0, 2)
rule.BackgroundColor3 = GOLD
rule.BackgroundTransparency = 1
rule.BorderSizePixel = 0
rule.Parent = card
-- The game is its sounds: said once, quietly, under the rule.
local hint = words("Best with headphones", BODY, 14, INK_MUTED, 104, 20)

gui.Parent = me:WaitForChild("PlayerGui")
-- Only now, with the black already up, so nothing of a half-built world shows between the two.
pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local SOFT = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
TweenService:Create(eyebrow, SOFT, { TextTransparency = 0.15 }):Play()
TweenService:Create(title, SOFT, { TextTransparency = 0 }):Play()
TweenService:Create(hint, SOFT, { TextTransparency = 0.2 }):Play()
TweenService:Create(rule, SOFT, { BackgroundTransparency = 0.2 }):Play()

-- How far in the place is, 0 to 1: the rule drawn that far.
local shown = 0
local function reached(share: number)
	if share <= shown then
		return
	end
	shown = share
	TweenService:Create(rule, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(math.floor(RULE * share + 0.5), 2) }):Play()
end

-- ===== AWAY, ONCE =====

local upAt = os.clock() -- when the card went up
local gone = false
local function arrive()
	if gone then
		return
	end
	gone = true
	reached(1)
	local quick = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, label in ipairs({ eyebrow, title, hint }) do
		TweenService:Create(label, quick, { TextTransparency = 1 }):Play()
	end
	TweenService:Create(rule, quick, { BackgroundTransparency = 1 }):Play()
	task.delay(0.25, function()
		TweenService:Create(sheet, TweenInfo.new(ARRIVE.out, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }):Play()
		task.delay(ARRIVE.out, function()
			me:SetAttribute("Arriving", nil)
			gui:Destroy()
		end)
	end)
end

-- ===== WHAT IT WAITS FOR, each for so long at the most =====

task.spawn(function()
	if not game:IsLoaded() then
		game.Loaded:Wait()
	end
	reached(0.25)
	-- From here on, ARRIVE.most at the most, whatever is still on its way.
	local loadedAt = os.clock()
	task.delay(ARRIVE.most, arrive)
	local function left(): number
		return math.max(0.1, ARRIVE.most - (os.clock() - loadedAt))
	end

	-- You, in the bay.
	local character = me.Character or me.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", left())
	reached(0.5)

	-- The ground under you, streamed in: something solid below your feet.
	if root and root:IsA("BasePart") then
		local below = RaycastParams.new()
		below.FilterType = Enum.RaycastFilterType.Exclude
		below.FilterDescendantsInstances = { character }
		local untilAt = os.clock() + math.min(ARRIVE.ground, left())
		while not gone and os.clock() < untilAt do
			if root.Parent and workspace:Raycast(root.Position, Vector3.new(0, -24, 0), below) then
				break
			end
			task.wait(0.1)
		end
	end
	reached(0.75)

	-- The first things you will see and hear: Roblox's queue of what it is still fetching, emptied (or near enough).
	local untilAt = os.clock() + math.min(ARRIVE.fetch, left())
	while not gone and os.clock() < untilAt and ContentProvider.RequestQueueSize > 0 do
		task.wait(0.1)
	end
	reached(1)

	-- The card read, at the least.
	local up = os.clock() - upAt
	if up < ARRIVE.least then
		task.wait(ARRIVE.least - up)
	end
	arrive()
end)
