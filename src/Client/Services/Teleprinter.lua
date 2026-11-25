--!strict
-- StarterPlayerScripts/Services/Teleprinter.lua
-- THE TELEPRINTER (the hundred-and-sixty-fifth pass, 2026-11-02, "keep polishing, do the next passes"). Every creamy
-- keyboard is the waterworks teleprinter grown into a stepping stone (Keepsakes: "The last thing it typed was KEY HOLDER
-- PLEASE CONFIRM. Nobody did."), and every key on it has a letter printed on it that nothing ever read.
--
-- Now a strip of paper tape comes up at the foot of your screen when you step onto one, and the teleprinter types its
-- last message onto it by itself, a soft tap a letter: KEY HOLDER PLEASE CONFIRM. Then every key you stand on types its
-- letter after it (DeformationService decides which: the key under your middle, with your weight on it, so walking types
-- each key you pass over and jumping does not). Type YES and it answers CONFIRMED: the first time, once a save, with its
-- tokens on the tokens' pill (EconomyService.answeredTeleprinter); after that, as often as you like, without. Once you have
-- answered it, it does not print its message for you again, only your letters. The tape scrolls left as it fills, and
-- goes a few seconds after the last letter.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local Teleprinter = {}
Teleprinter.VERSION = "the teleprinter, the two-hundred-and-eighth pass, 2026-11-12"

-- WHAT IT SAYS: its last message, and its answer to YES.
local SAYS = { asked = "KEY HOLDER PLEASE CONFIRM", answered = "CONFIRMED" }
-- HOW IT PRINTS: seconds a character as it types by itself, how many characters the tape keeps (more than any screen is
-- wide), seconds it stays after its last letter (and after its answer), its fade, and how loud its own tap is.
local PRINT = { pace = 0.06, shown = 160, stays = 4, answeredStays = 6, fade = 0.6, tap = 0.12 }
-- WHERE: the foot of the screen, over the tokens' pill, ACROSS THE WHOLE OF IT (the two-hundred-and-third pass, from your
-- note of 2026-11-06: the text "is hidden behind a beige overlay in the middle of the square with rounded edges instead
-- of going to the very end and disappearing afterwards"). It was a rounded box 520 wide in the middle of the screen, and
-- the letters were cut off at its left edge after thirty. Now it is a strip of paper from one side of the screen to the
-- other, as a teleprinter's tape is: each letter typed at the print head, `head` of the width in from the right, the
-- older ones running on to the left end of the screen and fading out over the last `fade` of the way, and the whole
-- strip gone a few seconds after the last letter.
-- A THIN TAPE (the two-hundred-and-fifth pass, from your note of 2026-11-07: "the line is too big"). It was a beige band
-- 46 high across the whole screen with title-sized letters on it, a bar laid over the game. A teleprinter's tape is a
-- narrow paper ribbon: `height` high now, small type (`type`), and the paper a little see-through, so the strip is a
-- line of print running past rather than a band in the way.
-- A SLIP, NOT A LINE (the two-hundred-and-eighth pass, from your note of 2026-11-12: "this KEY HOLDER PLEASE CONFIRM is
-- too wide and takes a whole line of space on the screen, which is not good and not aesthetic"). Three shapes it has
-- been, and each wrong its own way: a box 520 wide whose letters stopped dead at its left edge; a band from one side of
-- the screen to the other; a thin line from one side to the other. Now it is a short slip of paper over the tokens'
-- pill, no wider than its print needs (it grows from its middle as the letters come) and never wider than `wide`, or
-- `share` of a narrow screen. Past that the older letters run out through its left end, fading over the last `fade` of
-- it, so nothing is cut off dead and nothing lies across the game. Rounded a little (`round`), as a torn-off slip is.
local STRIP = { height = 26, lift = 128, wide = 340, share = 0.6, pad = 12, fade = 0.3, type = 15, paper = 0.12, round = 7 }

local me = Players.LocalPlayer
local ui: { gui: ScreenGui?, strip: Frame?, words: TextLabel?, rim: UIStroke?, fading: UIGradient? } = {}
-- What is on the tape, what is still to print (each piece with whether the teleprinter taps it out itself), and which
-- hiding is the latest.
local tape = ""
local queue: { { text: string, tap: boolean } } = {}
local printing = false
local blinking = false
local hideTurn = 0
local quietAnswer = false

-- A module beside this one (AudioService), found when first wanted: nothing here needs it to print.
local function beside(name: string): any
	local found = script.Parent and script.Parent:FindFirstChild(name)
	if found and found:IsA("ModuleScript") then
		local ok, loaded = pcall(require, found)
		if ok and type(loaded) == "table" then
			return loaded
		end
	end
	return nil
end

local function press(kind: string, volume: number?)
	local audio = beside("AudioService")
	if audio and type(audio.press) == "function" then
		pcall(audio.press, kind, volume)
	end
end

local function build()
	if ui.gui and ui.gui.Parent then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "Teleprinter"
	gui.ResetOnSpawn = false
	-- Under the pause card (20) and all that is over it: the shop, the cards, a scene, the dips, the arrival's black.
	gui.DisplayOrder = 19
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.Parent = me:WaitForChild("PlayerGui")
	local strip = Instance.new("Frame")
	strip.Name = "Tape"
	strip.AnchorPoint = Vector2.new(0.5, 1)
	strip.Position = UDim2.new(0.5, 0, 1, -STRIP.lift)
	-- A slip in the middle, as wide as its print (render sizes it): empty, it is only its two margins.
	strip.Size = UDim2.new(0, STRIP.pad * 2, 0, STRIP.height)
	strip.BackgroundColor3 = Style.COLOUR.paper
	-- What has run out past its left end is not drawn (and has faded to nothing by then: `fading` below).
	strip.ClipsDescendants = true
	strip.Visible = false
	strip.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, STRIP.round)
	corner.Parent = strip
	local rim = Instance.new("UIStroke")
	rim.Color = Style.COLOUR.paperInk
	rim.Thickness = 1
	rim.Transparency = 0.7
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = strip
	local words = Instance.new("TextLabel")
	words.Name = "Words"
	words.BackgroundTransparency = 1
	-- Between the slip's two margins: the newest letter at its right one, the rest running out to the left.
	words.Position = UDim2.new(0, STRIP.pad, 0, 0)
	words.Size = UDim2.new(1, -STRIP.pad * 2, 1, 0)
	-- FADING OUT as they reach the slip's left end, over the last STRIP.fade of it (only once it is full: a slip still
	-- growing has room for every letter, and render turns the fade on when it has stopped).
	local fading = Instance.new("UIGradient")
	fading.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(STRIP.fade, 0),
		NumberSequenceKeypoint.new(1, 0),
	})
	fading.Parent = words
	words.FontFace = Style.FONT.heading
	words.TextColor3 = Style.COLOUR.paperInk
	-- One size, whatever the screen: on a narrow one the tape runs off to the left sooner, and no letter shrinks as
	-- another is typed. Small, a tape's print.
	words.TextSize = STRIP.type
	words.TextScaled = false
	-- The newest letter at the right edge, the tape running out to the left.
	words.TextXAlignment = Enum.TextXAlignment.Right
	words.TextTruncate = Enum.TextTruncate.None
	words.Text = ""
	words.Parent = strip
	ui.gui, ui.strip, ui.words, ui.rim, ui.fading = gui, strip, words, rim, fading
end

-- The tape's last letters, and a cursor that blinks after them while it is up; and the slip as wide as they need, up
-- to as wide as it gets (STRIP.wide, or STRIP.share of the screen), where the oldest start to fade out at its left end.
local function render()
	local words, strip, fading = ui.words, ui.strip, ui.fading
	if words and strip then
		local cursor = if math.floor(os.clock() * 2) % 2 == 0 then "_" else " "
		local shown = string.sub(tape, -PRINT.shown)
		words.Text = shown .. cursor
		-- (Measured with the cursor on, whichever half of its blink this is, so the slip does not breathe with it.)
		local camera = workspace.CurrentCamera
		local most = math.min(STRIP.wide, (if camera then camera.ViewportSize.X else 800) * STRIP.share)
		local inked = math.max(words.TextBounds.X, (#shown + 1) * STRIP.type * 0.66)
		local need = inked + STRIP.pad * 2
		strip.Size = UDim2.new(0, math.clamp(need, STRIP.pad * 2 + STRIP.type, most), 0, STRIP.height)
		if fading then
			fading.Enabled = need > most
		end
	end
end

local function show()
	build()
	local strip, words, rim = ui.strip, ui.words, ui.rim
	if not (strip and words and rim) then
		return
	end
	hideTurn += 1
	strip.BackgroundTransparency = STRIP.paper
	words.TextTransparency = 0
	rim.Transparency = 0.7
	strip.Visible = true
	if not blinking then
		blinking = true
		task.spawn(function()
			while ui.strip and ui.strip.Visible do
				render()
				task.wait(0.5)
			end
			blinking = false
		end)
	end
end

-- Gone `seconds` after the last letter, unless more come first.
local function hideAfter(seconds: number)
	hideTurn += 1
	local turn = hideTurn
	task.delay(seconds, function()
		local strip, words, rim = ui.strip, ui.words, ui.rim
		if hideTurn ~= turn or printing or not (strip and words and rim) then
			return
		end
		local fade = TweenInfo.new(PRINT.fade, Enum.EasingStyle.Quad)
		TweenService:Create(strip, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(words, fade, { TextTransparency = 1 }):Play()
		local out = TweenService:Create(rim, fade, { Transparency = 1 })
		out:Play()
		out.Completed:Once(function()
			if hideTurn == turn then
				strip.Visible = false
			end
		end)
	end)
end

-- Prints what is queued, a character at a time, its own pieces tapped out as it types them.
local function printOut()
	if printing then
		return
	end
	printing = true
	show()
	task.spawn(function()
		local confirmed = false
		while #queue > 0 do
			local piece = table.remove(queue, 1) :: { text: string, tap: boolean }
			if piece.text == SAYS.answered then
				confirmed = true
			end
			for at = 1, #piece.text do
				local character = string.sub(piece.text, at, at)
				tape ..= character
				render()
				if piece.tap and character ~= " " then
					press("tap", PRINT.tap)
				end
				if piece.tap then
					task.wait(PRINT.pace)
				end
			end
		end
		printing = false
		if confirmed and quietAnswer then
			-- Answered again (no tokens this time, so no tokens' pill to sound it): its own soft good note.
			press("good")
		end
		hideAfter(if confirmed then PRINT.answeredStays else PRINT.stays)
	end)
end

local function typed(letter: any, fresh: any)
	if typeof(letter) ~= "string" or #letter ~= 1 then
		return
	end
	if fresh == true then
		-- A new line: a fresh tape, and its message first, until you have answered it.
		tape = ""
		queue = {}
		if me:GetAttribute("Teleprinter") ~= true then
			table.insert(queue, { text = SAYS.asked, tap = true })
			table.insert(queue, { text = "   ", tap = true })
		end
	end
	table.insert(queue, { text = letter, tap = false })
	printOut()
end

local function confirm(paid: any)
	quietAnswer = not (type(paid) == "number" and paid > 0)
	table.insert(queue, { text = "   ", tap = true })
	table.insert(queue, { text = SAYS.answered, tap = true })
	printOut()
end

local started = false
function Teleprinter.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("RemoteEvents", 30)
		local remote = remotes and remotes:WaitForChild("Teleprinter", 30)
		if not (remote and remote:IsA("RemoteEvent")) then
			warn("Teleprinter: no RemoteEvents.Teleprinter, so the keyboards type nothing. Paste the server's Bootstrap "
				.. "(src/Server/Bootstrap.server.lua) over the one in ServerScriptService.")
			return
		end
		remote.OnClientEvent:Connect(function(kind: any, a: any, b: any)
			if kind == "typed" then
				typed(a, b)
			elseif kind == "answered" then
				confirm(a)
			end
		end)
	end)
end

Teleprinter.STAMP = "32391f7f"
return Teleprinter
