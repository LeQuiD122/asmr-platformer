--!strict
-- StarterPlayerScripts/Services/DeathService.lua
-- The hardcore death card: a pulse of "You died", then a choice.
--
-- === Why a pause before the buttons ===
--
-- Falling in hardcore already sends you back to the start, and until now that happened
-- instantly and silently: one frame you were mid-air, the next you were on chunk one with a
-- reset clock and no idea whether the game had noticed. The run ended and nothing said so.
--
-- The three seconds are not decoration. They are the gap between "that went wrong" and "what
-- do I want to do about it", and offering the buttons inside that gap gets one of them pressed
-- by accident -- your hands are still on the keys from the jump you just missed.
--
-- === Why it fades rather than flashes ===
--
-- A hard flash on a death is a punishment, and this is a game about soft materials and quiet
-- sounds. A slow fade in and out says the same thing without raising its voice, and it reads
-- at a glance because it is the only thing on screen that moves.
--
-- === The second chance ===
--
-- A fall after the first stretch can be undone: back to the checkpoint you fell from, the clock where it
-- was. The card offers it when the server says there is somewhere to go back to: "Second chance (2)"
-- with some bought, or its Robux price, which buys one and uses it at once. A run carried on that way
-- does not go on the leaderboard or count as a best (Bootstrap), so a place there can never be bought.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local DeathService = {}

-- The price list, for the second chance's product id and price (optional: without it, no button).
local ShopCatalog: any = (function()
	local shared = ReplicatedStorage:WaitForChild("Shared", 10)
	local module = shared and shared:WaitForChild("ShopCatalog", 10)
	if module and module:IsA("ModuleScript") then
		local ok, loaded = pcall(require, module)
		if ok then
			return loaded
		end
	end
	return nil
end)()

local TITLE = Style.FONT.heading
local BODY = Style.FONT.body
local FALLEN = Style.COLOUR.danger
local WAIT_SECONDS = 3

local screen: ScreenGui? = nil
local wash: Frame? = nil
local headline: TextLabel? = nil
local note: TextLabel? = nil
local choices: Frame? = nil
-- "Try again", which a controller starts on when the choice appears.
local firstChoice: TextButton? = nil
-- The second chance: its button, whether this fall has one to offer, how many are owned, and the remote.
local chance = { button = nil :: TextButton?, offered = false, owned = 0, remote = nil :: RemoteEvent?,
	state = nil :: RemoteFunction?, buying = false }
local pulsing = false
local leaveRemote: RemoteEvent? = nil
local retryRemote: RemoteEvent? = nil

local function build()
	if screen then
		return
	end
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "DeathCard"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	-- Above the pause menu: when this is up it is the only thing that matters.
	gui.DisplayOrder = 40
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	screen = gui

	-- A wash rather than a full blackout. You should still be able to see where you fell from.
	local tint = Instance.new("Frame")
	tint.Name = "Wash"
	tint.Size = UDim2.new(1, 0, 1, 0)
	tint.BackgroundColor3 = Color3.fromRGB(28, 10, 12)
	tint.BackgroundTransparency = 1
	tint.BorderSizePixel = 0
	tint.Parent = gui
	wash = tint

	local title = Instance.new("TextLabel")
	title.Name = "Headline"
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.new(0.5, 0, 0.38, 0)
	title.Size = UDim2.new(1, 0, 0, 74)
	title.BackgroundTransparency = 1
	title.FontFace = TITLE
	title.TextSize = 58
	title.TextColor3 = FALLEN
	title.TextTransparency = 1
	title.Text = "You died"
	title.Parent = gui
	headline = title

	local sub = Instance.new("TextLabel")
	sub.Name = "Note"
	sub.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.Position = UDim2.new(0.5, 0, 0.46, 0)
	sub.Size = UDim2.new(1, 0, 0, 28)
	sub.BackgroundTransparency = 1
	sub.FontFace = BODY
	sub.TextSize = 19
	sub.TextColor3 = Color3.fromRGB(214, 190, 192)
	sub.TextTransparency = 1
	sub.Text = "Hardcore: back to the start."
	sub.Parent = gui
	note = sub

	local row = Instance.new("Frame")
	row.Name = "Choices"
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.new(0.5, 0, 0.60, 0)
	-- NO WIDER THAN THE SCREEN on a phone held upright.
	row.Size = UDim2.new(0.9, 0, 0, 48)
	local rowMost = Instance.new("UISizeConstraint")
	rowMost.MaxSize = Vector2.new(600, 48)
	rowMost.Parent = row
	row.BackgroundTransparency = 1
	row.Visible = false
	row.Parent = gui
	choices = row

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.Parent = row

	local function button(text: string, order: number, colour: Color3, dark: boolean): TextButton
		local made = Instance.new("TextButton")
		made.LayoutOrder = order
		made.Size = UDim2.new(1 / 3, -8, 1, 0)
		made.BackgroundColor3 = colour
		made.BorderSizePixel = 0
		made.FontFace = TITLE
		made.TextSize = 19
		made.TextColor3 = if dark then Style.COLOUR.panel else Style.COLOUR.ink
		made.Text = text
		made.TextScaled = true
		local most = Instance.new("UITextSizeConstraint")
		most.MaxTextSize = 19
		most.Parent = made
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = made
		made.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = Style.RADIUS.button
		corner.Parent = made
		return made
	end

	local again = button("Try again", 1, Style.COLOUR.accent, true)
	firstChoice = again
	local second = button("Second chance", 2, Style.COLOUR.good, true)
	second.Visible = false
	chance.button = second
	local out = button("Leave to the lobby", 3, Style.COLOUR.panelRaised, false)

	-- THE SECOND CHANCE: used if one is owned; else bought (Roblox's own window) and used once it lands.
	second.Activated:Connect(function()
		if chance.owned > 0 then
			DeathService.hide()
			if chance.remote then
				chance.remote:FireServer()
			end
			return
		end
		local item = ShopCatalog and ShopCatalog.get("SecondChance")
		local productId = item and item.productId or 0
		if productId ~= 0 and not chance.buying then
			chance.buying = true
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
		end
	end)

	again.Activated:Connect(function()
		DeathService.hide()
		if retryRemote then
			retryRemote:FireServer()
		end
	end)
	out.Activated:Connect(function()
		DeathService.hide()
		if leaveRemote then
			leaveRemote:FireServer()
		end
	end)
end

function DeathService.hide()
	pulsing = false
	local gui = screen
	if gui then
		gui.Enabled = false
	end
	if choices then
		choices.Visible = false
	end
	local GuiService = game:GetService("GuiService")
	if GuiService.SelectedObject and choices and GuiService.SelectedObject:IsDescendantOf(choices) then
		GuiService.SelectedObject = nil
	end
end

-- How many second chances are owned, from the server, and the button said accordingly.
local function readChances()
	local remote = chance.state
	local ok, data = false, nil
	if remote then
		ok, data = pcall(function()
			return remote:InvokeServer()
		end)
	end
	chance.owned = if ok and type(data) == "table" and typeof(data.chances) == "number" then data.chances else 0
	local item = ShopCatalog and ShopCatalog.get("SecondChance")
	local productId = item and item.productId or 0
	local b = chance.button
	if not b then
		return
	end
	if not chance.offered then
		b.Visible = false
	elseif chance.owned > 0 then
		b.Text = ("Second chance (%d)"):format(chance.owned)
		b.Visible = true
	elseif productId ~= 0 and item then
		b.Text = ("Second chance  R$ %d"):format(item.robux or 0)
		b.Visible = true
	else
		b.Visible = false -- not on sale yet, and none owned
	end
end

function DeathService.show(offer: boolean?)
	build()
	chance.offered = offer == true
	chance.buying = false
	task.spawn(readChances)
	local gui, tint, title, sub, row = screen, wash, headline, note, choices
	if not (gui and tint and title and sub and row) then
		return
	end
	gui.Enabled = true
	row.Visible = false
	pulsing = true

	-- THE PULSE. Two and a half seconds of breathing in and out, driven off the clock rather
	-- than a chain of tweens: a tween chain that outlives its own card keeps animating a
	-- hidden frame, and this one can be dismissed at any moment by the button below it.
	task.spawn(function()
		local started = os.clock()
		while pulsing and gui.Enabled do
			local phase = (os.clock() - started) * 1.6
			local breath = (math.sin(phase) + 1) / 2
			title.TextTransparency = 0.15 + breath * 0.45
			sub.TextTransparency = 0.35 + breath * 0.35
			tint.BackgroundTransparency = 0.72 + breath * 0.14
			RunService.Heartbeat:Wait()
		end
	end)

	task.delay(WAIT_SECONDS, function()
		if not pulsing then
			return
		end
		-- The pulse stops when the choice appears: a decision should be made against something
		-- still, not something breathing at you.
		pulsing = false
		title.TextTransparency = 0.1
		sub.TextTransparency = 0.3
		tint.BackgroundTransparency = 0.7
		row.Visible = true
		-- A CONTROLLER: "Try again" selected, so A is the answer.
		if game:GetService("UserInputService"):GetLastInputType().Name:sub(1, 7) == "Gamepad" and firstChoice then
			game:GetService("GuiService").SelectedObject = firstChoice
		end
		row.Position = UDim2.new(0.5, 0, 0.66, 0)
		TweenService:Create(row,
			TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0.60, 0) }):Play()
	end)
end

task.spawn(function()
	build()
	local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 20)
	if not remotes then
		return
	end
	local leave = remotes:WaitForChild("LeaveLevel", 20)
	if leave and leave:IsA("RemoteEvent") then
		leaveRemote = leave
	end
	local remote = remotes:WaitForChild("SecondChance", 10)
	if remote and remote:IsA("RemoteEvent") then
		chance.remote = remote
	end
	local functions = ReplicatedStorage:WaitForChild("RemoteFunctions", 10)
	local stateRemote = functions and functions:WaitForChild("ShopState", 10)
	if stateRemote and stateRemote:IsA("RemoteFunction") then
		chance.state = stateRemote
	end
	-- BOUGHT FROM THE CARD: the purchase lands on the server (EconomyService), and once it shows up here
	-- it is used at once, which is why it was bought.
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, bought: boolean)
		local item = ShopCatalog and ShopCatalog.get("SecondChance")
		if userId ~= Players.LocalPlayer.UserId or not item or productId ~= item.productId then
			return
		end
		chance.buying = false
		if not bought or not chance.offered then
			return
		end
		for _ = 1, 20 do
			readChances()
			if chance.owned > 0 then
				DeathService.hide()
				if chance.remote then
					chance.remote:FireServer()
				end
				return
			end
			task.wait(0.5)
		end
	end)
	local retry = remotes:FindFirstChild("HardcoreRetry")
	if retry and retry:IsA("RemoteEvent") then
		retryRemote = retry
	end

	local fell = remotes:WaitForChild("PlayerFell", 20)
	if fell and fell:IsA("RemoteEvent") then
		fell.OnClientEvent:Connect(function(offer: any)
			DeathService.show(offer == true)
		end)
	end
end)

DeathService.STAMP = "88f12ebc"
return DeathService
