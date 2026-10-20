--!strict
-- StarterPlayerScripts/Services/ShopLook.lua
-- THE SHOP'S LOOK AND FEEL (the hundred-and-fifth pass, from your notes: "stylistically connect the shop UI and its
-- vibe with the rest of the level ... the colors need variety ... incorporate the mouse icon to look like an item or a
-- chunk, have it crumble like a cookie ... effects splashing or splattering ... different sounds when you switch ...
-- the tabs ... when you press on the background of the shop ui it would crack if it's ice, or sparkle if it's lava, or
-- crumble if it's soap ... a random background of set defaults ... when you close the ui it would have a unique little
-- animation and a unique sound as well and same when you open it").
--
-- A THEME is one of the game's materials, drawn behind the shop with no images at all (frames, gradients, corners),
-- with its own colours for the shop's edge and title, things that move in it (chocolate chips, soap bubbles rising,
-- frost, honey dripping, lava's cracks glowing and embers, the back rooms' wallpaper under a failing tube), what a
-- press on its background does (crumbs, flakes, cracks, a drip, a splat, a pop, sparks, the light failing, a ripple),
-- and the sound that press makes (the material's own). The shop opens on a different one of the DEFAULTS each time,
-- or on the one you have chosen from your backgrounds (ShopCatalog; the crates come in the next pass).
--
-- THE CURSOR, with a mouse: a cookie, drawn the same way, that loses a bite and a shower of crumbs every click and
-- grows back after five. Opening: the shop squashes up out of nothing with the lid's pop and a burst of its theme;
-- closing: it squeezes and drops away with the lid going back on. Each tab has its own small sound.
--
-- THE BACKGROUNDS YOU OWN (the hundred-and-sixth pass): the one you have on is the one it opens on, and changes to at
-- once if you put another on with it open; a tile tried shows its background behind the shop until it closes. A CRATE
-- opened shakes over the shop while the server rolls it, throws its lid off with the sound of its rarity, and shows
-- what came out, in its own material, behind the shop and on a card.
--
-- ShopService calls this; without it the shop is as it was. Only ever on this screen.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
-- One look for the whole game (the ninety-ninth pass): every face, colour, corner and outline.
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))
-- The backgrounds' rarities and names (the crate's card).
local ShopCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopCatalog")) :: any

local ShopLook = {}

-- The game's own sound takes for a material (AudioService: your own recordings first, a sheet's take by its slot).
local AudioService: any = (function(): any
	local found = script.Parent and script.Parent:FindFirstChild("AudioService")
	if found and found:IsA("ModuleScript") then
		local ok, loaded = pcall(require, found)
		if ok and type(loaded) == "table" then
			return loaded
		end
	end
	return nil
end)()

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

export type Theme = { id: string, name: string, rarity: string, top: Color3, bottom: Color3, edge: Color3,
	title: Color3, titleInk: Color3, decor: string, effect: string, sound: string, fx: Color3, fx2: Color3 }

-- THE THEMES. `sound` is "Folder/Name" in SoundService (a sheet's take is picked by slot). Rarity is the crates' (the
-- next pass); "default" ones are everyone's.
ShopLook.THEMES = {
	cookie = { id = "cookie", name = "Cookie", rarity = "default", top = rgb(222, 172, 112), bottom = rgb(182, 124, 72),
		edge = rgb(92, 54, 26), title = rgb(110, 64, 30), titleInk = rgb(255, 240, 220), decor = "chips",
		effect = "crumbs", sound = "ShopSounds/CookieCrunch_x4", fx = rgb(196, 138, 80), fx2 = rgb(70, 40, 24) },
	soap = { id = "soap", name = "Soap", rarity = "default", top = rgb(240, 236, 252), bottom = rgb(206, 214, 242),
		edge = rgb(108, 98, 160), title = rgb(150, 120, 220), titleInk = rgb(255, 255, 255), decor = "bubbles",
		effect = "flakes", sound = "MaterialSounds/soapCrumble", fx = rgb(250, 248, 255), fx2 = rgb(200, 190, 240) },
	ice = { id = "ice", name = "Ice", rarity = "default", top = rgb(222, 244, 254), bottom = rgb(150, 204, 236),
		edge = rgb(40, 96, 140), title = rgb(70, 150, 210), titleInk = rgb(255, 255, 255), decor = "frost",
		effect = "cracks", sound = "MaterialSounds/iceCrack", fx = rgb(255, 255, 255), fx2 = rgb(170, 220, 250) },
	honey = { id = "honey", name = "Honey", rarity = "common", top = rgb(250, 206, 96), bottom = rgb(214, 140, 30),
		edge = rgb(120, 66, 8), title = rgb(170, 96, 10), titleInk = rgb(255, 246, 220), decor = "drips",
		effect = "drip", sound = "MaterialSounds/honeySquish", fx = rgb(246, 176, 40), fx2 = rgb(255, 222, 130) },
	slime = { id = "slime", name = "Slime", rarity = "common", top = rgb(176, 244, 140), bottom = rgb(88, 196, 96),
		edge = rgb(30, 100, 40), title = rgb(46, 150, 60), titleInk = rgb(240, 255, 236), decor = "blobs",
		effect = "splat", sound = "MaterialSounds/slimeBoing", fx = rgb(120, 220, 110), fx2 = rgb(200, 255, 180) },
	sand = { id = "sand", name = "Kinetic sand", rarity = "common", top = rgb(240, 214, 160), bottom = rgb(206, 170, 112),
		edge = rgb(120, 86, 40), title = rgb(170, 120, 60), titleInk = rgb(255, 248, 230), decor = "grains",
		effect = "crumbs", sound = "MaterialSounds/kineticSandImprint", fx = rgb(226, 190, 130), fx2 = rgb(180, 140, 84) },
	jello = { id = "jello", name = "Jelly", rarity = "rare", top = rgb(255, 150, 170), bottom = rgb(210, 60, 100),
		edge = rgb(120, 20, 50), title = rgb(190, 40, 80), titleInk = rgb(255, 236, 240), decor = "blobs",
		effect = "splat", sound = "MaterialSounds/jelloWobble", fx = rgb(255, 120, 150), fx2 = rgb(255, 200, 210) },
	cloud = { id = "cloud", name = "Cloud", rarity = "epic", top = rgb(176, 214, 244), bottom = rgb(236, 244, 252),
		edge = rgb(80, 120, 170), title = rgb(110, 160, 220), titleInk = rgb(255, 255, 255), decor = "puffs",
		effect = "puff", sound = "MaterialSounds/cloudHush", fx = rgb(255, 255, 255), fx2 = rgb(220, 232, 248) },
	bubbleWrap = { id = "bubbleWrap", name = "Bubble wrap", rarity = "rare", top = rgb(230, 244, 255),
		bottom = rgb(196, 222, 246), edge = rgb(70, 110, 160), title = rgb(90, 140, 210), titleInk = rgb(255, 255, 255),
		decor = "pockets", effect = "pop", sound = "MaterialSounds/bubblePop", fx = rgb(255, 255, 255),
		fx2 = rgb(160, 200, 240) },
	lava = { id = "lava", name = "Lava", rarity = "epic", top = rgb(64, 22, 16), bottom = rgb(26, 10, 8),
		edge = rgb(255, 120, 40), title = rgb(230, 90, 30), titleInk = rgb(255, 236, 200), decor = "glow",
		effect = "sparks", sound = "MaterialSounds/lavaCrust", fx = rgb(255, 150, 50), fx2 = rgb(255, 230, 120) },
	backRooms = { id = "backRooms", name = "The back rooms", rarity = "legendary", top = rgb(222, 204, 116),
		bottom = rgb(190, 168, 84), edge = rgb(96, 84, 40), title = rgb(126, 110, 52), titleInk = rgb(255, 248, 210),
		decor = "wallpaper", effect = "flicker", sound = "StorySounds/TubeDie", fx = rgb(255, 246, 200),
		fx2 = rgb(80, 70, 30) },
	hold = { id = "hold", name = "The Hold", rarity = "mythic", top = rgb(20, 44, 52), bottom = rgb(4, 10, 14),
		edge = rgb(120, 220, 210), title = rgb(30, 110, 110), titleInk = rgb(220, 255, 250), decor = "deep",
		effect = "ripple", sound = "WaterSounds/Drip_x8", fx = rgb(150, 240, 230), fx2 = rgb(255, 90, 70) },
}
ShopLook.DEFAULTS = { "cookie", "soap", "ice" }
-- EVERY TAB ITS OWN COLOUR (from your notes: "the colors need variety"), its chosen one deeper.
ShopLook.TAB_COLOURS = {
	Featured = rgb(255, 214, 120), Steps = rgb(176, 222, 160), Trails = rgb(160, 204, 255), Sounds = rgb(250, 182, 212),
	Auras = rgb(212, 184, 255), Emotes = rgb(255, 198, 150), Passes = rgb(150, 230, 212), Tokens = rgb(255, 232, 140),
	Backgrounds = rgb(206, 204, 236),
}
-- The tabs' sounds, in the order ShopTab_x9 holds them: ShopCatalog.TABS, then Backgrounds.
ShopLook.TAB_ORDER = { "Featured", "Steps", "Trails", "Sounds", "Auras", "Emotes", "Passes", "Tokens", "Backgrounds" }
local SLOT = { ShopTab = 1.2, CookieCrunch = 0.9, CrateReveal = 3.0, material = 1.0, Drip = 1.0 }

local look = {
	panel = nil :: Frame?,
	screen = nil :: ScreenGui?,
	backdrop = nil :: Frame?,
	fxGui = nil :: ScreenGui?,
	cursor = nil :: Frame?,
	bites = 0,
	theme = ShopLook.THEMES.cookie :: Theme,
	open = false,
	pieces = {} :: { { frame: GuiObject, kind: string, seed: number, base: UDim2 } },
	stepping = nil :: RBXScriptConnection?,
	pressing = nil :: RBXScriptConnection?,
	chosen = nil :: string?,
	base = nil :: string?, -- the background this opening is in (the one you have on, or the default it opened on)
	repainted = nil :: (() -> ())?, -- ShopService's: the title in the new background's colours
	crating = nil :: string?, -- a crate over the shop: "shaking", then "shown"
	crate = nil :: { [string]: any }?,
}

-- ===== SOUND =====

local function playSound(path: string, volume: number, slotIndex: number?)
	local folderName, name = string.match(path, "^(%w+)/(%w+)$")
	if not (folderName and name) then
		return
	end
	-- A MATERIAL'S SOUND, as the chunks make it: one of its takes from AudioService (so the soap is your own crumble).
	if folderName == "MaterialSounds" and AudioService and AudioService.takesFor and AudioService.applyTake then
		local takes = AudioService.takesFor(name)
		if #takes > 0 then
			local s = Instance.new("Sound")
			s.Volume = volume
			s.PlaybackSpeed = 0.96 + math.random() * 0.08
			AudioService.applyTake(s, takes[math.random(1, #takes)])
			s.Parent = SoundService
			s:Play()
			game:GetService("Debris"):AddItem(s, 4)
			return
		end
	end
	local folder = SoundService:FindFirstChild(folderName)
	if not folder then
		return
	end
	local source = folder:FindFirstChild(name)
	local sheetCount = tonumber(string.match(name, "_x(%d+)$"))
	if not source then
		-- A material's takes, singles or a sheet: the first that is there.
		for _, item in ipairs(folder:GetChildren()) do
			if item:IsA("Sound") and string.sub(item.Name, 1, #name + 1) == name .. "_" then
				source = item
				sheetCount = tonumber(string.match(item.Name, "_x(%d+)$"))
				break
			end
		end
	end
	if not (source and source:IsA("Sound")) then
		return
	end
	local s = source:Clone()
	s.Volume = volume
	s.PlaybackSpeed = 0.96 + math.random() * 0.08
	if sheetCount then
		local slot = SLOT[string.match(name, "^(%w+)_x") or ""] or SLOT.material
		local index = slotIndex or math.random(1, sheetCount)
		local from = (index - 1) * slot
		pcall(function()
			(s :: any).PlaybackRegionsEnabled = true;
			(s :: any).PlaybackRegion = NumberRange.new(from, from + slot - 0.05)
		end)
		s.TimePosition = from
	end
	s.Parent = SoundService
	s:Play()
	game:GetService("Debris"):AddItem(s, 4)
end

-- ===== THE PIECES: small frames that make the themes and the effects =====

local function dot(parent: Instance, size: number, colour: Color3, round: boolean): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundColor3 = colour
	f.BorderSizePixel = 0
	f.Active = false
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

-- A burst of a theme's effect (the shop's own, or `as`) at `at` (screen pixels, as the mouse reports them), on the
-- effects layer.
local function burst(effect: string, at: Vector2, strength: number, as: Theme?)
	local layer = look.fxGui
	if not layer then
		return
	end
	local theme = as or look.theme
	local function fling(size: number, colour: Color3, round: boolean, reach: Vector2, fall: number, life: number,
		spin: number?)
		local f = dot(layer, size, colour, round)
		f.Position = UDim2.fromOffset(at.X, at.Y)
		f.Rotation = math.random(0, 90)
		local goal = UDim2.fromOffset(at.X + reach.X, at.Y + reach.Y + fall)
		TweenService:Create(f, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = goal,
			BackgroundTransparency = 1, Rotation = f.Rotation + (spin or 180) }):Play()
		game:GetService("Debris"):AddItem(f, life + 0.1)
		return f
	end
	local count = math.floor(10 * strength)
	if effect == "crumbs" then
		for _ = 1, count do
			fling(math.random(4, 9), if math.random() < 0.7 then theme.fx else theme.fx2, false,
				Vector2.new(math.random(-50, 50), math.random(-30, 10)), math.random(60, 140), 0.7)
		end
	elseif effect == "flakes" then
		for _ = 1, count do
			fling(math.random(5, 10), if math.random() < 0.6 then theme.fx else theme.fx2, false,
				Vector2.new(math.random(-40, 40), math.random(-20, 10)), math.random(50, 110), 1.1, 360)
		end
	elseif effect == "cracks" then
		-- Lines out from the point, growing fast and staying a moment, a few shards dropping off.
		for _ = 1, math.max(4, math.floor(6 * strength)) do
			local line = dot(layer, 2, theme.fx, false)
			local angle = math.random() * 360
			local long = math.random(24, 80) * strength
			line.AnchorPoint = Vector2.new(0, 0.5)
			line.Position = UDim2.fromOffset(at.X, at.Y)
			line.Size = UDim2.fromOffset(0, 2)
			line.Rotation = angle
			TweenService:Create(line, TweenInfo.new(0.09, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(long, 2) }):Play()
			task.delay(0.9, function()
				TweenService:Create(line, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
			end)
			game:GetService("Debris"):AddItem(line, 1.5)
		end
		for _ = 1, math.floor(4 * strength) do
			fling(math.random(4, 8), theme.fx2, false, Vector2.new(math.random(-20, 20), 0), math.random(50, 90), 0.8)
		end
	elseif effect == "drip" then
		local blob = dot(layer, 14, theme.fx, true)
		blob.Position = UDim2.fromOffset(at.X, at.Y)
		blob.AnchorPoint = Vector2.new(0.5, 0)
		TweenService:Create(blob, TweenInfo.new(0.5, Enum.EasingStyle.Sine), { Size = UDim2.fromOffset(12, 40) }):Play()
		task.delay(0.5, function()
			TweenService:Create(blob, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.fromOffset(at.X, at.Y + 120), BackgroundTransparency = 1 }):Play()
		end)
		game:GetService("Debris"):AddItem(blob, 1.1)
	elseif effect == "splat" then
		local blob = dot(layer, 10, theme.fx, true)
		blob.Position = UDim2.fromOffset(at.X, at.Y)
		TweenService:Create(blob, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(34, 26) }):Play()
		task.delay(0.6, function()
			TweenService:Create(blob, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		end)
		game:GetService("Debris"):AddItem(blob, 1.1)
		for _ = 1, count do
			fling(math.random(5, 9), theme.fx2, true, Vector2.new(math.random(-60, 60), math.random(-50, 0)), 70, 0.6)
		end
	elseif effect == "pop" then
		local ring = dot(layer, 10, theme.fx, true)
		ring.BackgroundTransparency = 1
		ring.Position = UDim2.fromOffset(at.X, at.Y)
		local edge = Instance.new("UIStroke")
		edge.Color = theme.fx2
		edge.Thickness = 3
		edge.Parent = ring
		TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(60, 60) }):Play()
		TweenService:Create(edge, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		game:GetService("Debris"):AddItem(ring, 0.4)
		for _ = 1, 5 do
			fling(4, theme.fx2, true, Vector2.new(math.random(-36, 36), math.random(-36, 36)), 0, 0.3)
		end
	elseif effect == "sparks" then
		for _ = 1, math.floor(14 * strength) do
			local spark = fling(math.random(3, 6), if math.random() < 0.5 then theme.fx else theme.fx2, false,
				Vector2.new(math.random(-40, 40), math.random(-110, -40)), 0, math.random(5, 9) / 10, 90)
			spark.BackgroundTransparency = 0
		end
		local flash = dot(layer, 20, theme.fx2, true)
		flash.Position = UDim2.fromOffset(at.X, at.Y)
		flash.BackgroundTransparency = 0.3
		TweenService:Create(flash, TweenInfo.new(0.25), { Size = UDim2.fromOffset(70, 70), BackgroundTransparency = 1 }):Play()
		game:GetService("Debris"):AddItem(flash, 0.3)
	elseif effect == "flicker" then
		local backdrop = look.backdrop
		if backdrop then
			task.spawn(function()
				for _ = 1, 3 do
					backdrop.BackgroundTransparency = 0.6
					task.wait(0.05 + math.random() * 0.05)
					backdrop.BackgroundTransparency = 0
					task.wait(0.04 + math.random() * 0.08)
				end
			end)
		end
	elseif effect == "puff" then
		for _ = 1, math.max(4, math.floor(7 * strength)) do
			local cloud = dot(layer, math.random(14, 26), theme.fx, true)
			cloud.Position = UDim2.fromOffset(at.X + math.random(-14, 14), at.Y + math.random(-8, 8))
			cloud.BackgroundTransparency = 0.2
			local goal = UDim2.fromOffset(at.X + math.random(-60, 60), at.Y + math.random(-40, 10))
			TweenService:Create(cloud, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { Position = goal,
				Size = UDim2.fromOffset(60, 40), BackgroundTransparency = 1 }):Play()
			game:GetService("Debris"):AddItem(cloud, 1)
		end
	elseif effect == "ripple" then
		for k = 0, 2 do
			task.delay(k * 0.14, function()
				local ring = dot(layer, 8, theme.fx, true)
				ring.BackgroundTransparency = 1
				ring.Position = UDim2.fromOffset(at.X, at.Y)
				local edge = Instance.new("UIStroke")
				edge.Color = theme.fx
				edge.Thickness = 2
				edge.Parent = ring
				TweenService:Create(ring, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(110, 70) }):Play()
				TweenService:Create(edge, TweenInfo.new(0.8), { Transparency = 1 }):Play()
				game:GetService("Debris"):AddItem(ring, 0.9)
			end)
		end
	end
end

-- ===== THE BACKDROP: the theme's material, behind the shop =====

local function clearPieces()
	for _, item in ipairs(look.pieces) do
		item.frame:Destroy()
	end
	table.clear(look.pieces)
end

local function piece(frame: GuiObject, kind: string, base: UDim2)
	frame.Position = base
	table.insert(look.pieces, { frame = frame, kind = kind, seed = math.random() * 100, base = base })
end

local function paint(theme: Theme)
	local backdrop = look.backdrop
	if not backdrop then
		return
	end
	clearPieces()
	backdrop.BackgroundColor3 = Color3.new(1, 1, 1)
	local gradient = backdrop:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(theme.top, theme.bottom)
	gradient.Rotation = 90
	gradient.Parent = backdrop
	local rng = Random.new(#theme.id * 97)
	local function at(): UDim2
		return UDim2.fromScale(rng:NextNumber(0.03, 0.97), rng:NextNumber(0.05, 0.95))
	end
	if theme.decor == "chips" then
		for _ = 1, 16 do
			local chip = dot(backdrop, rng:NextInteger(10, 22), theme.fx2, true)
			chip.Rotation = rng:NextInteger(0, 90)
			chip.BackgroundTransparency = 0.15
			piece(chip, "drift", at())
		end
	elseif theme.decor == "bubbles" then
		for _ = 1, 12 do
			local bubble = dot(backdrop, rng:NextInteger(16, 46), theme.fx, true)
			bubble.BackgroundTransparency = 0.8
			local edge = Instance.new("UIStroke")
			edge.Color = Color3.new(1, 1, 1)
			edge.Transparency = 0.3
			edge.Thickness = 2
			edge.Parent = bubble
			piece(bubble, "rise", at())
		end
	elseif theme.decor == "frost" then
		for _ = 1, 9 do
			local shard = dot(backdrop, 1, theme.fx, false)
			shard.Size = UDim2.fromOffset(rng:NextInteger(60, 160), rng:NextInteger(16, 40))
			shard.Rotation = rng:NextInteger(-50, 50)
			shard.BackgroundTransparency = 0.72
			piece(shard, "still", at())
		end
		for _ = 1, 8 do
			piece(dot(backdrop, 4, theme.fx, false), "twinkle", at())
		end
	elseif theme.decor == "drips" then
		for k = 1, 8 do
			local drip = dot(backdrop, 1, theme.fx2, true)
			drip.AnchorPoint = Vector2.new(0.5, 0)
			drip.Size = UDim2.fromOffset(rng:NextInteger(12, 22), 30)
			drip.BackgroundTransparency = 0.2
			piece(drip, "drip", UDim2.fromScale(k / 9, 0))
		end
	elseif theme.decor == "grains" then
		for _ = 1, 40 do
			local grain = dot(backdrop, rng:NextInteger(3, 6), if rng:NextNumber() < 0.5 then theme.fx else theme.fx2, true)
			grain.BackgroundTransparency = 0.2
			piece(grain, "still", at())
		end
		for _ = 1, 4 do
			local print_ = dot(backdrop, 1, theme.fx2, true)
			print_.Size = UDim2.fromOffset(rng:NextInteger(26, 34), rng:NextInteger(50, 62))
			print_.Rotation = rng:NextInteger(-30, 30)
			print_.BackgroundTransparency = 0.7
			piece(print_, "still", at())
		end
	elseif theme.decor == "puffs" then
		for _ = 1, 9 do
			local puff = dot(backdrop, rng:NextInteger(60, 130), theme.fx, true)
			puff.BackgroundTransparency = 0.35
			puff.Size = UDim2.fromOffset(puff.Size.X.Offset, math.floor(puff.Size.X.Offset * 0.55))
			piece(puff, "drift", at())
		end
	elseif theme.decor == "blobs" then
		for _ = 1, 7 do
			local blob = dot(backdrop, rng:NextInteger(40, 90), theme.fx2, true)
			blob.BackgroundTransparency = 0.55
			piece(blob, "wobble", at())
		end
	elseif theme.decor == "pockets" then
		for row = 0, 5 do
			for col = 0, 8 do
				local pocket = dot(backdrop, 34, theme.fx, true)
				pocket.BackgroundTransparency = 0.45
				local edge = Instance.new("UIStroke")
				edge.Color = theme.fx2
				edge.Transparency = 0.4
				edge.Parent = pocket
				piece(pocket, "still", UDim2.fromScale((col + 0.5 + (row % 2) * 0.5) / 9.5, (row + 0.5) / 6))
			end
		end
	elseif theme.decor == "glow" then
		for _ = 1, 10 do
			local crack = dot(backdrop, 1, theme.fx, false)
			crack.Size = UDim2.fromOffset(rng:NextInteger(50, 140), 3)
			crack.Rotation = rng:NextInteger(-60, 60)
			piece(crack, "pulse", at())
		end
		for _ = 1, 10 do
			piece(dot(backdrop, 4, theme.fx2, false), "rise", at())
		end
	elseif theme.decor == "wallpaper" then
		for k = 0, 14 do
			local stripe = dot(backdrop, 1, theme.fx2, false)
			stripe.AnchorPoint = Vector2.new(0.5, 0)
			stripe.Size = UDim2.new(0, 6, 1, 0)
			stripe.BackgroundTransparency = 0.85
			piece(stripe, "still", UDim2.fromScale(k / 14, 0))
		end
		local tube = dot(backdrop, 1, theme.fx, false)
		tube.AnchorPoint = Vector2.new(0.5, 0)
		tube.Size = UDim2.new(0.5, 0, 0, 8)
		piece(tube, "tube", UDim2.fromScale(0.5, 0.02))
		-- And now and then, far back, something tall and thin crossing behind the shop.
		local figure = dot(backdrop, 1, rgb(30, 26, 18), false)
		figure.AnchorPoint = Vector2.new(0.5, 1)
		figure.Size = UDim2.fromOffset(16, 120)
		figure.BackgroundTransparency = 1
		local head = dot(figure, 18, rgb(30, 26, 18), true)
		head.Position = UDim2.new(0.5, 0, 0, -8)
		piece(figure, "walker", UDim2.fromScale(-0.1, 1))
	elseif theme.decor == "deep" then
		for _ = 1, 6 do
			local band = dot(backdrop, 1, theme.fx, false)
			band.Size = UDim2.new(0.7, 0, 0, rng:NextInteger(10, 24))
			band.BackgroundTransparency = 0.9
			band.Rotation = rng:NextInteger(-8, 8)
			piece(band, "drift", at())
		end
		for k = 0, 11 do
			local tooth = dot(backdrop, 1, rgb(232, 226, 206), false)
			tooth.AnchorPoint = Vector2.new(0.5, 1)
			tooth.Size = UDim2.fromOffset(6, 26)
			tooth.Rotation = (k % 2) * 6 - 3
			tooth.BackgroundTransparency = 1
			piece(tooth, "teeth", UDim2.fromScale((k + 0.5) / 12, 1.02))
		end
	end
end

local function step()
	local now = os.clock()
	for _, p in ipairs(look.pieces) do
		local f, b, s = p.frame, p.base, p.seed
		if p.kind == "drift" then
			f.Position = b + UDim2.fromOffset(math.sin(now * 0.3 + s) * 8, math.cos(now * 0.25 + s) * 6)
		elseif p.kind == "rise" then
			local y = (b.Y.Scale - ((now * 0.03 + s) % 1.2))
			if y < -0.1 then
				y += 1.2
			end
			f.Position = UDim2.fromScale(b.X.Scale + math.sin(now + s) * 0.01, y)
		elseif p.kind == "twinkle" then
			f.BackgroundTransparency = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(now * 2 + s * 3))
		elseif p.kind == "drip" then
			local grow = (now * 0.25 + s) % 1
			f.Size = UDim2.fromOffset(f.Size.X.Offset, 20 + 120 * grow ^ 2)
		elseif p.kind == "wobble" then
			local k = 1 + 0.08 * math.sin(now * 1.6 + s)
			f.Rotation = math.sin(now * 0.7 + s) * 8
			f.Size = UDim2.fromOffset(f.Size.X.Offset, f.Size.X.Offset * k)
		elseif p.kind == "pulse" then
			f.BackgroundTransparency = 0.15 + 0.5 * (0.5 + 0.5 * math.sin(now * 1.4 + s))
		elseif p.kind == "tube" then
			f.BackgroundTransparency = if math.random() < 0.02 then 0.8 else 0
		elseif p.kind == "walker" then
			-- Crosses behind once in a long while, slowly, and is gone.
			local cycle = (now + s * 3) % 40
			if cycle < 9 then
				f.BackgroundTransparency = 0.55
				f.Position = UDim2.fromScale(-0.1 + 1.2 * cycle / 9, 1)
				for _, child in ipairs(f:GetChildren()) do
					if child:IsA("Frame") then
						child.BackgroundTransparency = 0.55
					end
				end
			else
				f.BackgroundTransparency = 1
				for _, child in ipairs(f:GetChildren()) do
					if child:IsA("Frame") then
						child.BackgroundTransparency = 1
					end
				end
			end
		elseif p.kind == "teeth" then
			local show = 0.5 + 0.5 * math.sin(now * 0.4 + s * 0.2)
			f.BackgroundTransparency = 1 - 0.6 * show ^ 3
		end
	end
	-- A crate's light, turning slowly behind it.
	local crate = look.crate
	if crate and crate.rays.Visible then
		crate.rays.Rotation = (now * 24) % 360
	end
end

-- A THEME PUT BEHIND THE SHOP: painted, the shop's edge in its colour, and the title told (ShopService).
local function applyTheme(theme: Theme)
	look.theme = theme
	paint(theme)
	local panel = look.panel
	local edge = if panel then panel:FindFirstChildOfClass("UIStroke") else nil
	if edge then
		edge.Color = theme.edge
	end
	if look.repainted then
		task.spawn(look.repainted)
	end
end

-- ...and, when it changes with the shop open, a burst of it from the middle and its material's sound.
local function freshen(theme: Theme)
	local panel = look.panel
	if panel then
		local centre = panel.AbsolutePosition + panel.AbsoluteSize / 2 + GuiService:GetGuiInset()
		burst(theme.effect, centre, 1.4)
	end
	playSound(theme.sound, 0.5)
end

-- ===== THE CURSOR: a cookie, with a mouse =====

local function makeCookie(): Frame
	local layer = look.fxGui :: ScreenGui
	local body = dot(layer, 30, rgb(214, 160, 96), true)
	body.Name = "Cookie"
	body.ZIndex = 50
	local rim = Instance.new("UIStroke")
	rim.Color = rgb(150, 100, 52)
	rim.Thickness = 2
	rim.Parent = body
	for _, spot in ipairs({ { 0.3, 0.32, 6 }, { 0.66, 0.28, 5 }, { 0.5, 0.6, 7 }, { 0.25, 0.68, 4 }, { 0.74, 0.66, 5 } }) do
		local chip = dot(body, spot[3], rgb(70, 40, 24), true)
		chip.Position = UDim2.fromScale(spot[1], spot[2])
		chip.ZIndex = 51
	end
	local scale = Instance.new("UIScale")
	scale.Parent = body
	return body
end

local function cursorOn(on: boolean)
	local usingMouse = UserInputService.MouseEnabled and not UserInputService.TouchEnabled
	if on and usingMouse then
		if not look.cursor then
			look.cursor = makeCookie()
		end
		UserInputService.MouseIconEnabled = false
		look.bites = 0
	else
		if look.cursor then
			look.cursor:Destroy()
			look.cursor = nil
		end
		UserInputService.MouseIconEnabled = true
	end
end

local function bite()
	local body = look.cursor
	if not body then
		return
	end
	local scale = body:FindFirstChildOfClass("UIScale")
	look.bites += 1
	local at = UserInputService:GetMouseLocation()
	burst("crumbs", at, 0.6, ShopLook.THEMES.cookie)
	if scale then
		if look.bites >= 5 then
			look.bites = 0
			scale.Scale = 0.2
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		else
			TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 1 - look.bites * 0.12 }):Play()
		end
	end
end

-- ===== A CRATE OPENED (the hundred-and-sixth pass) =====
--
-- Over the shop: the screen dimmed, a wooden crate dropped in and shaking harder and harder while the server rolls it;
-- then its lid thrown off with the sound of what came out (CrateReveal_x5, a take for each rarity), the background
-- bursting out of it in its own material and painted behind the shop, light turning behind the crate for an epic one
-- and up, a flash for a legendary or a mythic; and a card in the rarity's colour naming it, to put on now or later.
-- Drawn at one size and fitted to the screen (Style.fit). Escape or B, once it is open, is "Later".

local RARITY_TAKE = { common = 1, rare = 2, epic = 3, legendary = 4, mythic = 5 }
type Ask = () -> any
type Wear = (string) -> ()
type Told = (any) -> ()
local WOOD, WOOD_DARK, WOOD_EDGE = rgb(196, 138, 80), rgb(160, 106, 58), rgb(92, 54, 26)
local DIM = rgb(12, 10, 16)
local BOX_AT, LID_AT = UDim2.fromOffset(170, 150), UDim2.fromOffset(170, 98)

local function rounded(f: GuiObject, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = f
end

local function outline(f: GuiObject, colour: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = colour
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	return s
end

local function caption(parent: Instance, name: string, words: string, font: Font, size: number, colour: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.FontFace = font
	l.TextSize = size
	l.TextColor3 = colour
	l.Text = words
	l.Parent = parent
	return l
end

-- Put away: the card, the light and the dimming; and the background back to the one this opening is in, unless it was
-- just put on.
local function hideCrate(restore: boolean)
	local c = look.crate
	look.crating = nil
	if not c then
		return
	end
	c.won = nil
	local fx = look.fxGui
	if fx and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(fx) then
		GuiService.SelectedObject = nil
	end
	c.card.Visible = false
	c.rays.Visible = false
	TweenService:Create(c.shade, TweenInfo.new(0.2), { BackgroundTransparency = 1, BackgroundColor3 = DIM }):Play()
	TweenService:Create(c.boxScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 }):Play()
	task.delay(0.22, function()
		if not look.crating then
			c.shade.Visible = false
		end
	end)
	if restore and look.open then
		ShopLook.restore()
	end
end

local function crateCard(): { [string]: any }?
	if look.crate then
		return look.crate
	end
	local layer = look.fxGui
	if not layer then
		return nil
	end
	local c: { [string]: any } = {}
	-- THE DIMMING, which also keeps a press off the shop under it.
	local shade = Instance.new("TextButton")
	shade.Name = "CrateShade"
	shade.AutoButtonColor = false
	shade.Text = ""
	shade.Selectable = false
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = DIM
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.ZIndex = 10
	shade.Visible = false
	shade.Parent = layer
	c.shade = shade
	local stage = Instance.new("Frame")
	stage.Name = "CrateStage"
	stage.AnchorPoint = Vector2.new(0.5, 0.5)
	stage.Position = UDim2.fromScale(0.5, 0.5)
	stage.Size = UDim2.fromOffset(340, 430)
	stage.BackgroundTransparency = 1
	stage.ZIndex = 11
	stage.Parent = shade
	Style.fit(stage, Vector2.new(340, 430))
	-- THE LIGHT behind it (an epic one and up): long soft rays, turning (step).
	local rays = Instance.new("Frame")
	rays.Name = "Rays"
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = BOX_AT
	rays.Size = UDim2.fromOffset(10, 10)
	rays.BackgroundTransparency = 1
	rays.ZIndex = 11
	rays.Visible = false
	rays.Parent = stage
	for k = 0, 5 do
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0.5, 0.5)
		ray.Position = UDim2.fromScale(0.5, 0.5)
		ray.Size = UDim2.fromOffset(320, 22)
		ray.Rotation = k * 30
		ray.BorderSizePixel = 0
		ray.BackgroundTransparency = 0.5
		ray.ZIndex = 11
		local fade = Instance.new("UIGradient")
		fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1) })
		fade.Parent = ray
		ray.Parent = rays
	end
	c.rays = rays
	-- THE CRATE: planks, a lid, and a question on its front.
	local box = Instance.new("Frame")
	box.Name = "Crate"
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = BOX_AT
	box.Size = UDim2.fromOffset(150, 112)
	box.BackgroundColor3 = WOOD
	box.BorderSizePixel = 0
	box.ZIndex = 13
	box.Parent = stage
	rounded(box, 14)
	outline(box, WOOD_EDGE, 4)
	for k = 1, 2 do
		local plank = Instance.new("Frame")
		plank.AnchorPoint = Vector2.new(0.5, 0.5)
		plank.Position = UDim2.fromScale(0.5, k / 3)
		plank.Size = UDim2.new(1, -10, 0, 4)
		plank.BackgroundColor3 = WOOD_DARK
		plank.BorderSizePixel = 0
		plank.ZIndex = 14
		plank.Parent = box
	end
	local mark = caption(box, "Mark", "?", Style.FONT.display, 52, rgb(255, 240, 214))
	mark.Size = UDim2.fromScale(1, 1)
	mark.ZIndex = 15
	local boxScale = Instance.new("UIScale")
	boxScale.Parent = box
	c.box, c.boxScale, c.mark = box, boxScale, mark
	local lid = Instance.new("Frame")
	lid.Name = "Lid"
	lid.AnchorPoint = Vector2.new(0.5, 1)
	lid.Position = LID_AT
	lid.Size = UDim2.fromOffset(168, 28)
	lid.BackgroundColor3 = WOOD_DARK
	lid.BorderSizePixel = 0
	lid.ZIndex = 16
	lid.Parent = stage
	rounded(lid, 10)
	c.lid, c.lidEdge = lid, outline(lid, WOOD_EDGE, 4)
	-- THE CARD, under it: what came out, and what to do with it.
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Position = UDim2.new(0.5, 0, 1, -6)
	card.Size = UDim2.fromOffset(320, 176)
	card.BackgroundColor3 = rgb(255, 250, 242)
	card.BorderSizePixel = 0
	card.ZIndex = 17
	card.Visible = false
	card.Parent = stage
	rounded(card, 22)
	c.cardEdge = outline(card, WOOD_EDGE, 4)
	local cardScale = Instance.new("UIScale")
	cardScale.Parent = card
	local pill = caption(card, "Rarity", "", Style.FONT.heading, 16, rgb(255, 255, 255))
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 14)
	pill.Size = UDim2.fromOffset(0, 26)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundTransparency = 0
	pill.ZIndex = 18
	rounded(pill, 13)
	local pillPad = Instance.new("UIPadding")
	pillPad.PaddingLeft = UDim.new(0, 12)
	pillPad.PaddingRight = UDim.new(0, 12)
	pillPad.Parent = pill
	local name = caption(card, "Name", "", Style.FONT.display, 26, rgb(44, 30, 18))
	name.Position = UDim2.new(0, 12, 0, 46)
	name.Size = UDim2.new(1, -24, 0, 32)
	name.TextScaled = true
	name.ZIndex = 18
	local nameFit = Instance.new("UITextSizeConstraint")
	nameFit.MaxTextSize = 26
	nameFit.Parent = name
	local line = caption(card, "Line", "A new background for the shop", Style.FONT.body, 15, rgb(110, 84, 60))
	line.Position = UDim2.new(0, 12, 0, 80)
	line.Size = UDim2.new(1, -24, 0, 20)
	line.ZIndex = 18
	local function cardButton(buttonName: string, words: string, x: number): TextButton
		local b = Instance.new("TextButton")
		b.Name = buttonName
		b.AutoButtonColor = true
		b.AnchorPoint = Vector2.new(0, 1)
		b.Position = UDim2.new(x, 0, 1, -14)
		b.Size = UDim2.new(0.44, 0, 0, 48)
		b.FontFace = Style.FONT.heading
		b.TextSize = 18
		b.Text = words
		b.BorderSizePixel = 0
		b.ZIndex = 18
		b.Parent = card
		rounded(b, 14)
		return b
	end
	local wear = cardButton("Wear", "Put it on", 0.52)
	wear.TextColor3 = rgb(255, 255, 255)
	local later = cardButton("Later", "Later", 0.04)
	later.BackgroundColor3 = rgb(240, 230, 214)
	later.TextColor3 = WOOD_EDGE
	outline(later, WOOD_EDGE, 2)
	c.card, c.cardScale, c.pill, c.name, c.wear = card, cardScale, pill, name, wear
	wear.Activated:Connect(function()
		local won = c.won
		local onWear = c.onWear
		hideCrate(false)
		if won and onWear then
			onWear(won)
		end
	end)
	later.Activated:Connect(function()
		hideCrate(true)
	end)
	look.crate = c
	return c
end

-- THE LID OFF and what came out.
local function reveal(c: { [string]: any }, won: any)
	look.crating = "shown"
	c.won = won.id
	local rarity = ShopCatalog.RARITY[won.rarity or ""] or ShopCatalog.RARITY.common
	local theme: Theme = (ShopLook.THEMES :: any)[won.theme or ""] or look.theme
	local level = RARITY_TAKE[won.rarity] or 1
	TweenService:Create(c.lid, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = LID_AT + UDim2.fromOffset(math.random(60, 110) * (if math.random() < 0.5 then -1 else 1), -150),
		Rotation = math.random(-60, 60),
		BackgroundTransparency = 1,
	}):Play()
	TweenService:Create(c.lidEdge, TweenInfo.new(0.55), { Transparency = 1 }):Play()
	c.mark.Visible = false
	c.boxScale.Scale = 1.18
	TweenService:Create(c.boxScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	playSound("ShopSounds/CrateReveal_x5", 0.7, level)
	-- Out of the crate in its own material, and behind the shop.
	local at = c.box.AbsolutePosition + c.box.AbsoluteSize / 2 + GuiService:GetGuiInset()
	burst(theme.effect, at, 1.2 + level * 0.3, theme)
	if look.theme.id ~= theme.id then
		applyTheme(theme)
	end
	-- The light for an epic one and up; a flash for a legendary or a mythic.
	if level >= 3 then
		for _, ray in ipairs(c.rays:GetChildren()) do
			if ray:IsA("Frame") then
				ray.BackgroundColor3 = rarity.colour
			end
		end
		c.rays.Visible = true
	end
	if level >= 4 then
		c.shade.BackgroundColor3 = rgb(255, 250, 236)
		c.shade.BackgroundTransparency = 0.1
		TweenService:Create(c.shade, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.35,
			BackgroundColor3 = DIM }):Play()
	end
	-- Its card, in the rarity's colour.
	c.pill.Text = string.upper(rarity.name)
	c.pill.BackgroundColor3 = rarity.colour
	c.name.Text = won.name
	c.wear.BackgroundColor3 = rarity.colour
	c.cardEdge.Color = rarity.colour:Lerp(Color3.new(0, 0, 0), 0.35)
	task.delay(0.3, function()
		if look.crating ~= "shown" then
			return
		end
		c.card.Visible = true
		c.cardScale.Scale = 0.6
		TweenService:Create(c.cardScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad" then
			GuiService.SelectedObject = c.wear
		end
	end)
end

-- A CRATE, opened: `ask` is the server's answer (it yields; { ok, won } or why not), `wear` puts what came out on,
-- `refused` is told why nothing did.
function ShopLook.crate(ask: Ask, wear: Wear, refused: Told)
	if look.crating or not look.open then
		return
	end
	local c = crateCard()
	if not c then
		return
	end
	look.crating = "shaking"
	c.onWear = wear
	c.won = nil
	c.card.Visible = false
	c.rays.Visible = false
	c.mark.Visible = true
	c.box.Rotation = 0
	c.box.Position = BOX_AT
	c.lid.Position = LID_AT
	c.lid.Rotation = 0
	c.lid.BackgroundTransparency = 0
	c.lidEdge.Transparency = 0
	c.shade.Visible = true
	c.shade.BackgroundColor3 = DIM
	c.shade.BackgroundTransparency = 1
	TweenService:Create(c.shade, TweenInfo.new(0.2), { BackgroundTransparency = 0.35 }):Play()
	c.boxScale.Scale = 0.2
	TweenService:Create(c.boxScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	playSound("ShopSounds/CrateShake", 0.6)
	local answered, result = false, nil
	task.spawn(function()
		local ok, got = pcall(ask)
		result = if ok then got else nil
		answered = true
	end)
	task.spawn(function()
		-- SHAKING harder the longer it goes, for a moment at least, and until the server has said.
		local started = os.clock()
		while look.crating == "shaking" and (not answered or os.clock() - started < 1.2) and os.clock() - started < 15 do
			local t = os.clock() - started
			local k = math.min(1, t / 1.2)
			c.box.Rotation = math.sin(t * 34) * (2 + 7 * k)
			c.box.Position = BOX_AT + UDim2.fromOffset(math.random(-2, 2) * k, math.random(-3, 1) * k)
			c.lid.Position = LID_AT + UDim2.fromOffset(0, -math.abs(math.sin(t * 17)) * 6 * k)
			c.lid.Rotation = math.sin(t * 29) * 4 * k
			task.wait()
		end
		if look.crating ~= "shaking" then
			return
		end
		c.box.Rotation = 0
		c.box.Position = BOX_AT
		local won = if type(result) == "table" and result.ok and result.won then ShopCatalog.get(result.won) else nil
		if not won then
			hideCrate(false)
			refused(result)
			return
		end
		reveal(c, won)
	end)
end

-- Is a crate over the shop? (Escape and B put an open one away, and wait while one is shaking.)
function ShopLook.crating(): boolean
	return look.crating ~= nil
end

function ShopLook.dismiss()
	if look.crating == "shown" then
		hideCrate(true)
	end
end

-- ===== WHAT SHOPSERVICE CALLS =====

-- Built once, inside the shop's panel (behind everything in it) and over the shop (the effects and the cursor).
function ShopLook.attach(panel: Frame, screen: ScreenGui)
	if look.panel then
		return
	end
	look.panel, look.screen = panel, screen
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, -8, 1, -8)
	backdrop.Position = UDim2.fromScale(0.5, 0.5)
	backdrop.AnchorPoint = Vector2.new(0.5, 0.5)
	backdrop.ZIndex = 0
	backdrop.ClipsDescendants = true
	backdrop.Active = false
	backdrop.Parent = panel
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 22)
	round.Parent = backdrop
	look.backdrop = backdrop
	local fx = Instance.new("ScreenGui")
	fx.Name = "ShopFx"
	fx.ResetOnSpawn = false
	fx.IgnoreGuiInset = true
	fx.DisplayOrder = (screen.DisplayOrder or 30) + 1
	fx.Enabled = false
	fx.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	look.fxGui = fx
end

-- THE BACKGROUND YOU HAVE ON (a theme id, or nil for one of the defaults at random): opened on from now on, and turned
-- to at once if the shop is open. True when it changed what is behind the shop.
function ShopLook.choose(id: string?): boolean
	look.chosen = id
	local theme = if id then (ShopLook.THEMES :: any)[id] else nil
	if not theme then
		return false
	end
	look.base = id
	if look.open and not look.crating and look.theme.id ~= id then
		applyTheme(theme)
		freshen(theme)
		return true
	end
	return false
end

-- A BACKGROUND TRIED: shown behind the shop until it closes (or another is tried). True when there is one to show.
function ShopLook.show(id: string): boolean
	local theme = (ShopLook.THEMES :: any)[id]
	if not (theme and look.open) or look.crating then
		return false
	end
	if look.theme.id ~= id then
		applyTheme(theme)
		freshen(theme)
	end
	return true
end

-- Back to the background this opening is in.
function ShopLook.restore(): boolean
	local theme = if look.base then (ShopLook.THEMES :: any)[look.base] else nil
	if look.open and theme and look.theme.id ~= theme.id then
		applyTheme(theme)
		return true
	end
	return false
end

-- ShopService's: told whenever the background changes (the title in its colours).
function ShopLook.onRepaint(fn: () -> ())
	look.repainted = fn
end

function ShopLook.theme(): Theme
	return look.theme
end

function ShopLook.opened()
	local panel, fx = look.panel, look.fxGui
	if not (panel and fx) then
		return
	end
	look.open = true
	local id = look.chosen
	if not (id and (ShopLook.THEMES :: any)[id]) then
		id = ShopLook.DEFAULTS[math.random(1, #ShopLook.DEFAULTS)]
	end
	look.base = id
	applyTheme((ShopLook.THEMES :: any)[id :: string])
	panel.BackgroundTransparency = 1
	fx.Enabled = true
	cursorOn(true)
	playSound("ShopSounds/ShopOpen", 0.6)
	local centre = panel.AbsolutePosition + panel.AbsoluteSize / 2 + GuiService:GetGuiInset()
	task.delay(0.12, function()
		burst(look.theme.effect, centre, 1.6)
	end)
	if look.stepping then
		look.stepping:Disconnect()
	end
	look.stepping = RunService.RenderStepped:Connect(function()
		step()
		local body = look.cursor
		if body then
			local at = UserInputService:GetMouseLocation()
			body.Position = UDim2.fromOffset(at.X, at.Y)
		end
	end)
	-- A PRESS ON THE SHOP'S OWN BACKGROUND (not on anything in it): the theme's effect and its material's sound; and
	-- the cookie's bite, wherever you click.
	if look.pressing then
		look.pressing:Disconnect()
	end
	look.pressing = UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		bite()
		-- (Not while a crate is open over it.)
		if look.crating then
			return
		end
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not (playerGui and look.panel) then
			return
		end
		local spot = input.Position
		local over = playerGui:GetGuiObjectsAtPosition(spot.X, spot.Y)
		local onPanel, onButton = false, false
		for _, item in ipairs(over) do
			if item == look.panel or item == look.backdrop or item:IsDescendantOf(look.backdrop :: Frame) then
				onPanel = true
			elseif item:IsA("GuiButton") and item:IsDescendantOf(look.panel :: Frame) then
				onButton = true
			end
		end
		if onPanel and not onButton then
			local screenAt = Vector2.new(spot.X, spot.Y) + GuiService:GetGuiInset()
			burst(look.theme.effect, screenAt, 1)
			playSound(look.theme.sound, 0.55)
		end
	end)
end

function ShopLook.closed()
	if not look.open then
		return
	end
	look.open = false
	if look.crating then
		hideCrate(false)
	end
	playSound("ShopSounds/ShopClose", 0.55)
	local panel = look.panel
	if panel then
		local centre = panel.AbsolutePosition + panel.AbsoluteSize / 2 + GuiService:GetGuiInset()
		burst(look.theme.effect, centre, 1.2)
	end
	cursorOn(false)
	if look.pressing then
		look.pressing:Disconnect()
		look.pressing = nil
	end
	task.delay(1.2, function()
		if not look.open then
			if look.stepping then
				look.stepping:Disconnect()
				look.stepping = nil
			end
			clearPieces()
			if look.fxGui then
				look.fxGui.Enabled = false
			end
		end
	end)
end

-- A tab chosen: its own small sound.
function ShopLook.tab(name: string)
	local index = table.find(ShopLook.TAB_ORDER, name)
	if index then
		playSound("ShopSounds/ShopTab_x9", 0.5, index)
	end
end

ShopLook.STAMP = "5dc54558"
return ShopLook
