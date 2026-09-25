--!strict
-- StarterPlayerScripts/Services/ScreenEffects.lua
-- Small marks the material leaves on the lens as you cross it.
--
-- === Scale, and why it is the whole design ===
--
-- These are COSMETIC, and they are smaller than instinct says they should be. A mark runs
-- four to fourteen pixels on a 700-pixel screen -- the size of a real speck on a real lens
-- -- and it is meant to be noticed at the edge of vision rather than looked at.
--
-- Every version of this file has been too big, including the two that each cut it. The
-- first put marks a seventh of the screen wide with five or six shapes apiece, enough to
-- cover a corner; that is not a lens effect, it is a filter, and it makes the game harder to
-- play for decoration nobody asked for. The second halved them and they were still too big.
-- This is the third cut and the direction of the error has never once reversed, which is
-- worth remembering before anyone nudges these numbers back up.
--
-- The rule that keeps it honest: if you could not still read the platform underneath it,
-- it is too big.
--
-- === Not every material marks you ===
--
-- Six of the eighteen deliberately have NO entry here, and that is the most important
-- decision in the file. Lego, bubble wrap, the keyboard and the light switches are dry
-- moulded plastic; solid chocolate is cold and hard; soap is a bar. None of them throw
-- anything at your face, and inventing a splatter for them would say the effect is a
-- decoration applied to every chunk rather than something the material actually does.
--
-- Twelve materials mark the lens because twelve materials are wet, dusty or shedding. The
-- six that do not are the reason the twelve mean anything.
--
-- === Where they land ===
--
-- Sector-balanced, not random. Random placement clumps -- that is what random does -- and
-- the result was one side of the screen loaded while the other stayed empty. The screen is
-- divided into a ring of sectors around a protected centre, and each new mark goes to
-- whichever sector currently holds the fewest. Ties are broken randomly, so it spreads
-- without ever looking like it is filling a grid.

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ScreenEffects = {}

type Look = {
	colour: Color3,
	shape: string,   -- droplet | smear | smudge | grit | chip | crystal | fibre | bead
	size: number,    -- of the viewport's short side. Nothing here reaches 0.02.
	bits: number,    -- pieces in one mark, and it is small on purpose
	alpha: number,
	cap: number,
	life: number,
	slide: number,
	tint: Color3,
	saturation: number,
}

-- TWELVE ENTRIES, NOT EIGHTEEN. See the note above: dry moulded plastic, cold solid
-- chocolate and a bar of soap do not throw anything at a lens, so they are absent rather
-- than given a token mark.
local LOOKS: { [string]: Look } = {
	-- Runs, and is the only thing here that travels any real distance down the glass.
	Honey = { colour = Color3.fromRGB(228, 158, 40), shape = "droplet", size = 0.012, bits = 2,
		alpha = 0.22, cap = 7, life = 5.0, slide = 18, tint = Color3.fromRGB(255, 186, 74),
		saturation = 0.10 },
	-- Thinner, so it beads instead of running, and it throws one extra fleck.
	Slime = { colour = Color3.fromRGB(120, 216, 86), shape = "droplet", size = 0.011, bits = 3,
		alpha = 0.20, cap = 8, life = 4.5, slide = 7, tint = Color3.fromRGB(138, 255, 118),
		saturation = 0.14 },
	-- Grease does not bead, it SMEARS -- a wiped streak with no defined edge.
	ButterWax = { colour = Color3.fromRGB(246, 226, 152), shape = "smear", size = 0.016, bits = 2,
		alpha = 0.42, cap = 6, life = 4.4, slide = 8, tint = Color3.fromRGB(255, 226, 140),
		saturation = 0.05 },
	-- Dry grit: several tiny angular specks, no single one of them a mark on its own.
	KineticSand = { colour = Color3.fromRGB(198, 172, 124), shape = "grit", size = 0.006, bits = 6,
		alpha = 0.26, cap = 10, life = 4.0, slide = 10, tint = Color3.fromRGB(228, 204, 158),
		saturation = -0.08 },
	-- Frost: fine crossing slivers, which is what a crystal is at this size.
	Ice = { colour = Color3.fromRGB(228, 244, 255), shape = "crystal", size = 0.013, bits = 3,
		alpha = 0.34, cap = 9, life = 5.5, slide = 1, tint = Color3.fromRGB(178, 220, 255),
		saturation = -0.20 },
	JelloSoda = { colour = Color3.fromRGB(246, 158, 92), shape = "droplet", size = 0.011, bits = 2,
		alpha = 0.22, cap = 7, life = 4.0, slide = 8, tint = Color3.fromRGB(255, 166, 96),
		saturation = 0.14 },
	-- Sea water off a bell: clear drops that run off fast, and hardly any colour.
	Jellyfish = { colour = Color3.fromRGB(226, 214, 244), shape = "droplet", size = 0.010, bits = 2,
		alpha = 0.18, cap = 6, life = 3.0, slide = 10, tint = Color3.fromRGB(214, 196, 240),
		saturation = 0.04 },
	-- BARELY ANYTHING, and deliberately the quietest entry in this table. A Needoh is
	-- sealed: nothing comes off it, so the only honest reason to put something on the
	-- camera at all is the faint smear a hand leaves on a satin toy. Two bits, low alpha,
	-- and it slides off fast.
	-- Embers, and very few. The keys are molten but they are not liquid -- what comes off is
	-- the odd spark carried up on the heat, not a spatter, so this is the shortest-lived
	-- entry in the table and the fastest to slide clear.
	LavaKeys = { colour = Color3.fromRGB(255, 148, 58), shape = "droplet", size = 0.006, bits = 2,
		alpha = 0.20, cap = 4, life = 1.8, slide = 14, tint = Color3.fromRGB(255, 176, 96),
		saturation = 0.24 },
	-- A smear, not a spatter. Butter transfers rather than flies, so this is wide, slow and
	-- barely there -- and it stays put, which is what the very low slide says.
	ButterStick = { colour = Color3.fromRGB(248, 236, 186), shape = "droplet", size = 0.016, bits = 2,
		alpha = 0.16, cap = 5, life = 6.5, slide = 1, tint = Color3.fromRGB(252, 242, 198),
		saturation = 0.06 },
	Needoh = { colour = Color3.fromRGB(96, 214, 210), shape = "droplet", size = 0.008, bits = 2,
		alpha = 0.12, cap = 4, life = 2.6, slide = 10, tint = Color3.fromRGB(110, 222, 218),
		saturation = 0.10 },
	-- Hairs and pollen, not liquid: single thin fibres lying at odd angles.
	LambsEar = { colour = Color3.fromRGB(196, 212, 168), shape = "fibre", size = 0.015, bits = 3,
		alpha = 0.44, cap = 8, life = 4.2, slide = 3, tint = Color3.fromRGB(210, 228, 184),
		saturation = -0.05 },
	-- Foam beads: little clustered bubbles that pop off the block, pale and light.
	Foam = { colour = Color3.fromRGB(250, 248, 240), shape = "bead", size = 0.008, bits = 5,
		alpha = 0.34, cap = 9, life = 4.6, slide = 6, tint = Color3.fromRGB(248, 242, 226),
		saturation = -0.06 },
	-- SOOT SMUDGES. Charcoal does not stick as a drop, it scrapes -- soft-edged dark
	-- patches with a scratch through them.
	Charcoal = { colour = Color3.fromRGB(42, 39, 38), shape = "smudge", size = 0.018, bits = 3,
		alpha = 0.30, cap = 9, life = 5.0, slide = 4, tint = Color3.fromRGB(58, 54, 52),
		saturation = -0.20 },
	-- Warm chocolate runs like honey but darker and slightly thicker.
	Chocolate = { colour = Color3.fromRGB(88, 52, 28), shape = "droplet", size = 0.012, bits = 2,
		alpha = 0.22, cap = 7, life = 4.8, slide = 15, tint = Color3.fromRGB(152, 88, 44),
		saturation = 0.10 },
	-- Wet earth flicks off in CHIPS: angular, matte, and they stay where they land.
	Clay = { colour = Color3.fromRGB(160, 100, 70), shape = "chip", size = 0.009, bits = 4,
		alpha = 0.24, cap = 8, life = 6.0, slide = 2, tint = Color3.fromRGB(208, 144, 108),
		saturation = -0.04 },
	-- Crystal grit, thrown up by your own feet like sand -- but white, and it catches light
	-- where sand does not, so it sits brighter and lasts longer.
	Salt = { colour = Color3.fromRGB(246, 247, 248), shape = "grit", size = 0.007, bits = 6,
		alpha = 0.34, cap = 9, life = 4.2, slide = 8, tint = Color3.fromRGB(250, 250, 252),
		saturation = -0.06 },
	-- EMBERS. Not splatter -- nothing molten reaches your face and survives -- but sparks
	-- carried up on the heat do, and they are the brightest thing on the lens by a distance.
	-- Short-lived on purpose: an ember that lingers is a scorch mark.
	Lava = { colour = Color3.fromRGB(255, 168, 62), shape = "grit", size = 0.006, bits = 5,
		alpha = 0.16, cap = 7, life = 1.6, slide = -12, tint = Color3.fromRGB(255, 146, 60),
		saturation = 0.20 },
	-- Thick and pale, and it does NOT run: a shear-thickening fluid that has landed on
	-- something has already stiffened, so the slide is nearly nothing.
	Oobleck = { colour = Color3.fromRGB(238, 236, 226), shape = "droplet", size = 0.013, bits = 2,
		alpha = 0.24, cap = 7, life = 4.4, slide = 3, tint = Color3.fromRGB(240, 238, 230),
		saturation = -0.04 },
	-- Flakes that land and then melt: a crystal, like ice, but smaller and whiter, and the
	-- shortest life of the crystalline three because it is going as soon as it arrives.
	Snow = { colour = Color3.fromRGB(248, 251, 255), shape = "crystal", size = 0.010, bits = 3,
		alpha = 0.30, cap = 10, life = 2.8, slide = 5, tint = Color3.fromRGB(226, 240, 255),
		saturation = -0.16 },
	-- Condensation: tiny round beads, the most transparent thing here.
	Cloud = { colour = Color3.fromRGB(252, 253, 255), shape = "bead", size = 0.007, bits = 6,
		alpha = 0.40, cap = 10, life = 3.2, slide = 4, tint = Color3.fromRGB(255, 255, 255),
		saturation = -0.12 },
}

-- DECLARED, not merely absent.
--
-- These six leave nothing on a lens and that is a decision, so it is written down as one.
-- The difference matters to check_lua: a material missing from BOTH tables is an omission
-- worth reporting, and a material listed here is finished. Left implicit, the checker could
-- only tell "no marks" from "forgot to add marks" by guessing.
local NO_MARK: { [string]: boolean } = {
	Lego = true,            -- moulded ABS. Dry, hard, and it throws bricks rather than dust.
	BubbleWrap = true,      -- plastic film.
	CreamyKeyboard = true,  -- plastic caps.
	LightSwitch = true,     -- plastic plates.
	ChocolateSolid = true,  -- cold and tempered; it snaps, it does not spatter.
	Soap = true,            -- a bar. It is the wet version people picture, and it is not.
	Buttons = true,         -- moulded caps. Same reasoning as the keyboard beside them.
}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local gui = Instance.new("ScreenGui")
gui.Name = "MaterialLensMarks"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = -10
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local correction = Instance.new("ColorCorrectionEffect")
correction.Name = "MaterialTint"
correction.Parent = Lighting

-- A RING OF SECTORS AROUND A PROTECTED CENTRE, in fractions of the viewport.
--
-- Twelve cells of a four-by-three grid with the two middle ones left out. The gap in the
-- middle is the centre guard and the platformer's business end: nothing is ever placed
-- where the next jump is going to be.
local SECTORS = {
	{ 0.00, 0.25, 0.00, 0.33 }, { 0.25, 0.50, 0.00, 0.33 },
	{ 0.50, 0.75, 0.00, 0.33 }, { 0.75, 1.00, 0.00, 0.33 },
	{ 0.00, 0.25, 0.33, 0.66 }, --[[ centre left out ]]
	{ 0.75, 1.00, 0.33, 0.66 },
	{ 0.00, 0.25, 0.66, 1.00 }, { 0.25, 0.50, 0.66, 1.00 },
	{ 0.50, 0.75, 0.66, 1.00 }, { 0.75, 1.00, 0.66, 1.00 },
}

type Mark = { frame: Frame, sector: number }

local marks: { Mark } = {}
local activeLook: Look? = nil
local activeName: string? = nil
local washTarget, wash, lastStep = 0, 0, 0
local announced = false
local HOLD = 0.6

local function rand(lo: number, hi: number): number
	return lo + math.random() * (hi - lo)
end

-- The emptiest sector, ties broken at random.
--
-- This is what stopped one side of the screen filling while the other stayed bare. Random
-- placement CLUMPS -- that is what random is -- and with a cap of eight or nine the clumping
-- is the only thing you notice. Choosing the least-occupied cell spreads them without ever
-- looking like it is filling a grid in order, because ties are common and broken randomly.
local function pickSector(): number
	local counts = table.create(#SECTORS, 0)
	for _, mark in ipairs(marks) do
		counts[mark.sector] += 1
	end
	local best, tied = math.huge, {}
	for index, count in ipairs(counts) do
		if count < best then
			best, tied = count, { index }
		elseif count == best then
			table.insert(tied, index)
		end
	end
	return tied[math.random(1, #tied)]
end

local function sectorPoint(sector: number, view: Vector2): Vector2
	local box = SECTORS[sector]
	-- Inset from the sector's own edges, so two marks in neighbouring cells cannot end up
	-- touching across the boundary and reading as one clump again.
	return Vector2.new(
		rand(box[1] + 0.04, box[2] - 0.04) * view.X,
		rand(box[3] + 0.05, box[4] - 0.05) * view.Y
	)
end

-- One piece. Corner radius carries most of the shape difference: fully rounded is a drop,
-- barely rounded is a chip, and a long thin fully-rounded one is a fibre.
local function piece(parent: Frame, look: Look, w: number, h: number, at: Vector2, rot: number, alpha: number)
	local part = Instance.new("Frame")
	part.AnchorPoint = Vector2.new(0.5, 0.5)
	part.Position = UDim2.fromOffset(at.X, at.Y)
	part.Size = UDim2.fromOffset(math.max(1, w), math.max(1, h))
	part.Rotation = rot
	part.BackgroundColor3 = look.colour
	part.BackgroundTransparency = alpha
	part.BorderSizePixel = 0
	part.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = if look.shape == "chip" then UDim.new(0.18, 0) else UDim.new(0.5, 0)
	corner.Parent = part
	return part
end

-- Softens a piece to nothing at its own edges. What separates a smudge from a dot.
local function soften(part: Frame, strength: number)
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, strength),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, strength),
	})
	gradient.Rotation = rand(0, 180)
	gradient.Parent = part
end

local function build(mark: Frame, look: Look, px: number)
	local shape = look.shape

	if shape == "droplet" then
		-- A drop is not a circle: it is round at the bottom and drawn out at the top, where
		-- it is still attached to where it came from. One body plus a short tail.
		local body = piece(mark, look, px, px * rand(0.9, 1.1), Vector2.zero, 0, look.alpha)
		local tail = rand(0, 360)
		piece(mark, look, px * 0.34, px * rand(0.8, 1.5),
			Vector2.new(math.cos(math.rad(tail)) * px * 0.5, math.sin(math.rad(tail)) * px * 0.5),
			tail + 90, look.alpha + 0.06)
		-- A highlight, tiny and offset. Liquid on glass catches light on one side, and this
		-- single pale speck is most of what makes a droplet look wet rather than painted.
		local shine = piece(mark, look, px * 0.26, px * 0.2, Vector2.new(-px * 0.2, -px * 0.22), 0,
			math.max(0, look.alpha - 0.22))
		shine.BackgroundColor3 = look.colour:Lerp(Color3.new(1, 1, 1), 0.7)
		for _ = 2, look.bits do
			local angle, distance = rand(0, math.pi * 2), px * rand(1.2, 2.4)
			piece(mark, look, px * 0.3, px * 0.3,
				Vector2.new(math.cos(angle) * distance, math.sin(angle) * distance), 0,
				look.alpha + 0.14)
		end

	elseif shape == "smear" then
		-- A wipe: long, thin, soft at both ends, all lying the same way.
		local lie = rand(0, 360)
		for index = 1, look.bits do
			local part = piece(mark, look, px * rand(1.6, 2.8), px * rand(0.22, 0.42),
				Vector2.new(rand(-px, px) * 0.5, rand(-px, px) * 0.4), lie + rand(-12, 12),
				look.alpha + index * 0.07)
			soften(part, 0.85)
		end

	elseif shape == "smudge" then
		-- Soot: a soft dark patch with one hard scratch through it.
		for index = 1, look.bits do
			local part = piece(mark, look, px * rand(0.8, 1.4), px * rand(0.5, 0.9),
				Vector2.new(rand(-px, px) * 0.45, rand(-px, px) * 0.35), rand(0, 360),
				look.alpha + index * 0.08)
			soften(part, 0.9)
		end
		local scratch = rand(0, 360)
		piece(mark, look, px * rand(1.5, 2.4), math.max(1, px * 0.06), Vector2.zero, scratch,
			math.max(0, look.alpha - 0.08))

	elseif shape == "grit" then
		-- Specks. Tiny, angular, unevenly spread, and no one of them is a mark by itself.
		for _ = 1, look.bits do
			local angle, distance = rand(0, math.pi * 2), px * rand(0, 3.4)
			piece(mark, look, px * rand(0.7, 1.5), px * rand(0.6, 1.3),
				Vector2.new(math.cos(angle) * distance, math.sin(angle) * distance),
				rand(0, 360), look.alpha + rand(0, 0.2))
		end

	elseif shape == "chip" then
		-- Angular flakes, close together, sitting where they landed.
		for _ = 1, look.bits do
			local angle, distance = rand(0, math.pi * 2), px * rand(0, 1.6)
			piece(mark, look, px * rand(0.6, 1.2), px * rand(0.5, 1.0),
				Vector2.new(math.cos(angle) * distance, math.sin(angle) * distance),
				rand(0, 360), look.alpha + rand(0, 0.14))
		end

	elseif shape == "crystal" then
		-- Frost: slivers crossing through one point, six-ish fold like the real thing.
		local base = rand(0, 60)
		for index = 1, look.bits do
			piece(mark, look, px * rand(1.2, 2.0), math.max(1, px * 0.09), Vector2.zero,
				base + index * (180 / look.bits), look.alpha + rand(0, 0.12))
		end
		piece(mark, look, px * 0.3, px * 0.3, Vector2.zero, 0, look.alpha)

	elseif shape == "fibre" then
		-- A hair: very long, one pixel or two wide, bent by being drawn as two segments at
		-- a slight angle to each other. A perfectly straight fibre reads as a scratch.
		for _ = 1, look.bits do
			local lie = rand(0, 360)
			local at = Vector2.new(rand(-px, px) * 0.6, rand(-px, px) * 0.6)
			piece(mark, look, px * rand(1.4, 2.2), math.max(1, px * 0.05), at, lie, look.alpha)
			piece(mark, look, px * rand(0.8, 1.4), math.max(1, px * 0.05),
				Vector2.new(at.X + math.cos(math.rad(lie)) * px, at.Y + math.sin(math.rad(lie)) * px),
				lie + rand(10, 30), look.alpha + 0.08)
		end

	else -- bead
		-- Condensation: small circles of varying size, each with a highlight, clustered.
		for index = 1, look.bits do
			local angle, distance = rand(0, math.pi * 2), (if index == 1 then 0 else px * rand(0.8, 3.0))
			local size = px * rand(0.55, 1.25)
			local at = Vector2.new(math.cos(angle) * distance, math.sin(angle) * distance)
			piece(mark, look, size, size, at, 0, look.alpha)
			local shine = piece(mark, look, size * 0.32, size * 0.32,
				Vector2.new(at.X - size * 0.22, at.Y - size * 0.24), 0, math.max(0, look.alpha - 0.2))
			shine.BackgroundColor3 = look.colour:Lerp(Color3.new(1, 1, 1), 0.75)
		end
	end
end

local function addMark(look: Look)
	local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local px = math.min(view.X, view.Y) * look.size
	local sector = pickSector()
	local at = sectorPoint(sector, view)

	local mark = Instance.new("Frame")
	mark.Name = "Mark"
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromOffset(at.X, at.Y)
	mark.Size = UDim2.fromOffset(0, 0)
	mark.BackgroundTransparency = 1
	mark.BorderSizePixel = 0
	mark.Rotation = rand(0, 360)
	mark.Parent = gui

	build(mark, look, px)
	table.insert(marks, { frame = mark, sector = sector })

	if look.slide > 1 then
		TweenService:Create(mark, TweenInfo.new(look.life, Enum.EasingStyle.Linear),
			{ Position = UDim2.fromOffset(at.X, at.Y + look.slide) }):Play()
	end

	task.delay(look.life * 0.55, function()
		if not mark.Parent then
			return
		end
		local out = TweenInfo.new(look.life * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		for _, part in ipairs(mark:GetDescendants()) do
			if part:IsA("Frame") then
				TweenService:Create(part, out, { BackgroundTransparency = 1 }):Play()
			end
		end
		task.delay(look.life * 0.45, function()
			for index, existing in ipairs(marks) do
				if existing.frame == mark then
					table.remove(marks, index)
					break
				end
			end
			mark:Destroy()
		end)
	end)
end

local function clearMarks()
	for _, mark in ipairs(marks) do
		mark.frame:Destroy()
	end
	table.clear(marks)
end

function ScreenEffects.onStep(materialName: string?, mine: boolean)
	-- Same rule as the audio: your screen answers your feet and nobody else's.
	if not (mine and materialName) then
		return
	end
	local look = LOOKS[materialName]
	if not look then
		-- NO_MARK materials end here, which is the intended path for six of the eighteen.
		-- Anything reaching this line that is NOT in NO_MARK is an omission, and check_lua
		-- reports it rather than leaving it to be noticed in play.
		return
	end

	if not announced then
		announced = true
		print(("[ScreenEffects] first material step: %s -- lens marks are live"):format(materialName))
	end

	if activeName ~= materialName then
		clearMarks()
		activeName = materialName
	end

	activeLook = look
	washTarget = 1
	lastStep = os.clock()

	if #marks < look.cap then
		addMark(look)
	end
end

RunService.RenderStepped:Connect(function(dt: number)
	local look = activeLook
	if not look then
		return
	end
	if washTarget > 0 and os.clock() - lastStep > HOLD then
		washTarget = 0
	end

	local rate = if GuiService.ReducedMotionEnabled then 0.05
		elseif washTarget > wash then 0.25
		else 1.1
	wash += (washTarget - wash) * math.clamp(dt / rate, 0, 1)

	if wash < 0.02 then
		wash = 0
		activeLook = nil
		correction.TintColor = Color3.new(1, 1, 1)
		correction.Saturation = 0
		return
	end

	-- Very faint, and lerped FROM WHITE: ColorCorrection multiplies, so a material's colour
	-- written straight in would drop every other channel and charcoal would black the game
	-- out. No blur any more -- at this scale the marks carry it and blur only cost clarity.
	correction.TintColor = Color3.new(1, 1, 1):Lerp(look.tint, 0.05 * wash)
	correction.Saturation = look.saturation * wash
end)

-- Materials with no entry are not reported: six of them are absent on purpose. This only
-- catches the reverse -- a look left behind for a material that no longer exists.
function ScreenEffects.audit(materialNames: { string })
	local missing = {}
	for _, name in ipairs(materialNames) do
		if not (LOOKS[name] or NO_MARK[name]) then
			table.insert(missing, name)
		end
	end
	if #missing > 0 then
		warn(("[ScreenEffects] %s is in neither LOOKS nor NO_MARK -- decide whether it marks "
			.. "the lens and say so."):format(table.concat(missing, ", ")))
	end
end

print("[ScreenEffects] loaded, 16 material lens looks (7 materials leave no mark)")

return ScreenEffects
