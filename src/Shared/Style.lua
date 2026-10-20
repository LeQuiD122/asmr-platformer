--!strict
-- ReplicatedStorage/Shared/Style.lua
-- ONE LOOK FOR THE WHOLE GAME (the ninety-ninth pass, from your notes: "verify that the style of text, and their fonts
-- and the textures and the stylistic choices are similar throughout the game, so that we do not have an inconsistency
-- in one place vs another"). Every face, the colours every screen shares, its corners and its outlines are here, and
-- only here (blender/check_style.py holds every other file to that): change one and it changes everywhere.
--
-- ONE FAMILY FOR EVERY WORD IN THE GAME (the hundred-and-second pass, from your notes: "They should all be ONE
-- style!!!", and you chose Nunito): the menus, the shop, the story's captions and cries, the journal's pages, the
-- signs in the world, letters and notices alike, all Nunito, rounded, because this is a game about soft things. What
-- tells one kind of word from another is its weight and its slant, never another face:
--   Black       the few big words (a level finished, the shop's titles, the lobby's big signs), and a shout
--   ExtraBold   signs painted in the world
--   Bold        what is named and pressed: titles, buttons, names, labels, and the clocks
--   Medium      what is read: captions, thoughts, speech, descriptions
--   italic      a page in the journal, a letter, a note in someone's hand, a voice going quiet
-- (It was seven faces after the ninety-ninth pass: Fredoka for the big words, RobotoMono for the clocks, Garamond for
-- the journal, two hands for a shout and a murmur, and Gotham, Code and Arial on the world's signs.)
--
-- WORLD names the same family for words printed on the world (SurfaceGuis on parts), so a sign can be told from a menu
-- by what it says and where it is, and never by a face of its own.

local Style = {}

local NUNITO = "rbxasset://fonts/families/Nunito.json"

local function nunito(weight: Enum.FontWeight, italic: boolean?): Font
	return Font.new(NUNITO, weight, if italic then Enum.FontStyle.Italic else Enum.FontStyle.Normal)
end

Style.FONT = {
	display = nunito(Enum.FontWeight.Black), -- the few big words
	heading = nunito(Enum.FontWeight.Bold), -- titles, buttons, names, labels
	body = nunito(Enum.FontWeight.Medium), -- what is read: captions, thoughts, speech, descriptions
	number = nunito(Enum.FontWeight.Bold), -- clocks, times
	paper = nunito(Enum.FontWeight.Medium, true), -- the journal's pages
	shout = nunito(Enum.FontWeight.Black, true), -- a voice raised: a shout, a cry for help
	murmur = nunito(Enum.FontWeight.Regular, true), -- a voice lowered: the cry going quiet
}

Style.WORLD = {
	sign = nunito(Enum.FontWeight.ExtraBold), -- the town's signs and notices
	signHeavy = nunito(Enum.FontWeight.Black), -- stencilled, painted large
	letter = nunito(Enum.FontWeight.Medium, true), -- letters, notes, a page
	hand = nunito(Enum.FontWeight.SemiBold, true), -- written by hand
	marker = nunito(Enum.FontWeight.Black, true), -- scrawled
	typed = nunito(Enum.FontWeight.SemiBold), -- typed or stamped: a time card
	plain = nunito(Enum.FontWeight.Regular), -- the back rooms' notices, as plain as an office's
}

-- THE COLOURS EVERY SCREEN SHARES: one dark panel, one ink, one warm accent; the modes and the states.
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
Style.COLOUR = {
	panel = rgb(20, 19, 27), -- every card and panel
	panelRaised = rgb(40, 38, 52), -- a row, a well, a quiet button on a panel
	edge = rgb(64, 62, 84), -- a panel's outline
	ink = rgb(242, 244, 252), -- headings and what matters
	inkSoft = rgb(178, 184, 206), -- what is read under it
	inkMuted = rgb(126, 128, 150), -- what is there if you want it
	accent = rgb(246, 206, 148), -- the game's warm gold
	chill = rgb(124, 196, 236),
	hardcore = rgb(232, 96, 88),
	good = rgb(151, 196, 89),
	danger = rgb(236, 104, 96),
	paper = rgb(240, 234, 216), -- the journal's pages
	paperInk = rgb(44, 38, 32),
}

-- SIZES OF TEXT on a screen, in a step of a scale (never a size between two).
Style.SIZE = { caption = 13, body = 16, label = 18, title = 24, number = 22, display = 36 }

-- CORNERS AND OUTLINES: a panel's, a button's, a small chip's, and a pill (fully round ends).
Style.RADIUS = { panel = UDim.new(0, 18), button = UDim.new(0, 12), small = UDim.new(0, 8), pill = UDim.new(0.5, 0) }
Style.STROKE = { panel = 2, button = 1.5, hair = 1 }

-- FITTED TO THE SCREEN (the hundred-and-second pass, from your notes: "verify that every device can see everything and
-- that everything scales properly ... to the best of its ability"). A panel drawn at a fixed size for a 1280 by 720
-- screen is given a UIScale ("Fit") that follows the screen: never larger than the screen less a margin (a phone held
-- either way), not tiny on a phone (three quarters of its size at the least, where it fits), and a little larger on a
-- big screen (up to a third larger on a 1920 by 1080 monitor or a television). It scales about the panel's anchor, so
-- a centred card stays centred. On the client only.
Style.DESIGN = Vector2.new(1280, 720)
Style.MARGIN = 12
function Style.fit(panel: GuiObject, design: Vector2): UIScale
	local found = panel:FindFirstChild("Fit")
	local scale: UIScale
	if found and found:IsA("UIScale") then
		scale = found
	else
		scale = Instance.new("UIScale")
		scale.Name = "Fit"
		scale.Parent = panel
	end
	local watching: RBXScriptConnection? = nil
	local function update()
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		local view = camera.ViewportSize
		local room = Vector2.new(math.max(view.X - Style.MARGIN * 2, 1), math.max(view.Y - Style.MARGIN * 2, 1))
		local fits = math.min(room.X / design.X, room.Y / design.Y)
		local wanted = math.clamp(math.min(view.X / Style.DESIGN.X, view.Y / Style.DESIGN.Y), 0.75, 1.35)
		scale.Scale = math.max(0.4, math.min(fits, wanted))
	end
	local function watch()
		if watching then
			watching:Disconnect()
		end
		local camera = workspace.CurrentCamera
		if camera then
			watching = camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
		end
		update()
	end
	watch()
	local cameraChanged = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watch)
	panel.Destroying:Connect(function()
		cameraChanged:Disconnect()
		if watching then
			watching:Disconnect()
		end
	end)
	return scale
end

Style.STAMP = "16cb4e3a"
return Style
