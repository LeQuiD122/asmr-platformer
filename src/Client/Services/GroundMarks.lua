--!strict
-- StarterPlayerScripts/Services/GroundMarks.lua
-- WHAT YOU LEAVE BEHIND (the two-hundred-and-thirtieth pass, 2026-11-20, from "do other points from the 5 you mentioned":
-- the ground keeping your real footprints, and the hard materials cracking where you step). With the experience's mesh
-- and image setting on, a surface can be painted into while you play. Each slab you walk on is given an image laid on
-- its top (a Decal, which on a mesh follows the mesh's own surface), and every step paints into it:
--
--   PRESSED    kinetic sand, snow, clay, salt: a footprint pressed in, heel and ball and toes, the way you were going,
--              darker where it is deeper, each foot in turn either side of your path
--   CRACKED    chocolate, butter wax, ice, cookie: a split from under your foot, forking as it runs, the same few
--              cracks growing longer the more you stand on it
--
-- They stay. A slab keeps every mark made on it for as long as it is there (the run), so you can look back down a
-- stretch of sand and see the way you came. Only the most recent keep an image (MAX_PIXELS_KEPT; the oldest is wiped as
-- a new one is needed). On this screen alone, from your own steps: nothing here is seen by anyone
-- else or touches the game. (The older stamped prints and cracks, DeformationRenderer's, still come and go as before.)
--
-- Without the setting (AssetService refuses an EditableImage) it says so once and does nothing.

local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local GroundMarks = {}
GroundMarks.VERSION = "what you leave behind, the two-hundred-and-thirtieth pass, 2026-11-20"

local STRIDE = 2.3 -- studs walked between two steps
local PER_STUD = 26 -- pixels of image a stud of surface gets (14 drew a print as a blocky little box)
local MAX_PIXELS = 512 -- an image is never wider or longer than this
-- How much is kept at once, by pixels rather than by count: a pad is cut into small tiles, each with an image of its
-- own (tried as 36 images, three pads used them all and the sand lost its prints).
local MAX_SHEETS = 400
local MAX_PIXELS_KEPT = 8000000

type Kind = { style: string, ink: Color3, depth: number, lip: Color3? }
-- THE MATERIALS THAT KEEP A MARK, and how: the shade inside the mark, how strong, and for a print the colour of the
-- little ridge it pushes up ahead of the toe and behind the heel.
local KINDS: { [string]: Kind } = {
	KineticSand = { style = "press", ink = Color3.fromRGB(150, 112, 64), depth = 0.42, lip = Color3.fromRGB(236, 206, 150) },
	Snow = { style = "press", ink = Color3.fromRGB(112, 134, 172), depth = 0.56, lip = Color3.fromRGB(255, 255, 255) },
	Clay = { style = "press", ink = Color3.fromRGB(110, 62, 42), depth = 0.45, lip = Color3.fromRGB(196, 132, 104) },
	-- (The two-hundred-and-forty-fifth pass: memory foam's own, soft and grey in its pale foam.)
	Foam = { style = "press", ink = Color3.fromRGB(150, 140, 120), depth = 0.4, lip = Color3.fromRGB(250, 244, 230) },
	Salt = { style = "press", ink = Color3.fromRGB(160, 156, 150), depth = 0.32, lip = Color3.fromRGB(255, 255, 252) },
	Chocolate = { style = "crack", ink = Color3.fromRGB(40, 20, 12), depth = 0.25 },
	ChocolateSolid = { style = "crack", ink = Color3.fromRGB(40, 20, 12), depth = 0.25 },
	ButterWax = { style = "crack", ink = Color3.fromRGB(120, 96, 50), depth = 0.35 },
	Ice = { style = "crack", ink = Color3.fromRGB(235, 248, 255), depth = 0.3 },
	Cookie = { style = "crack", ink = Color3.fromRGB(70, 40, 20), depth = 0.3 },
}

type Sheet = { image: EditableImage, decal: Decal, part: BasePart, size: Vector2, used: number }
local sheets: { [BasePart]: Sheet } = {}
local count = 0
local pixelsKept = 0
local refused = false

local function kindOf(part: BasePart): (string?, BasePart?)
	local at: Instance? = part
	for _ = 1, 3 do
		if at and at:IsA("BasePart") then
			local material = at:GetAttribute("Material")
			if type(material) == "string" and KINDS[material] then
				return material, at
			end
		end
		at = at and at.Parent
	end
	return nil, nil
end

-- The surface a mark goes on: the drawn mesh you actually see, not the invisible tile you stand on. A slab's own
-- "Visual", the wax pads' "WaxShell", or a pad's "SkinnedVisual" (the sand's moving skin, kept on the platform two levels up from the tile:
-- marks painted on the tiles sat under the sand and were never seen). Else the slab.
local function surfaceOf(slab: BasePart, hit: BasePart): BasePart
	local at: Instance? = slab
	for _ = 1, 3 do
		if not at then
			break
		end
		for _, name in ipairs({ "Visual", "WaxShell", "SkinnedVisual" }) do
			local visual = at:FindFirstChild(name)
			if visual and visual:IsA("BasePart") and visual.Transparency < 1 then
				return visual
			end
		end
		at = at.Parent
	end
	return hit
end

local function oldest(): BasePart?
	local worst, when = nil, math.huge
	for part, sheet in pairs(sheets) do
		if sheet.used < when then
			worst, when = part, sheet.used
		end
	end
	return worst
end

local function drop(part: BasePart)
	local sheet = sheets[part]
	if sheet then
		sheets[part] = nil
		count -= 1
		pixelsKept -= sheet.size.X * sheet.size.Y
		sheet.decal:Destroy()
		sheet.image:Destroy()
	end
end

local function sheetOf(part: BasePart): Sheet?
	local sheet = sheets[part]
	if sheet then
		sheet.used = os.clock()
		return sheet
	end
	if refused then
		return nil
	end
	local size = Vector2.new(math.clamp(math.floor(part.Size.X * PER_STUD), 16, MAX_PIXELS),
		math.clamp(math.floor(part.Size.Z * PER_STUD), 16, MAX_PIXELS))
	while count > 0 and (count >= MAX_SHEETS or pixelsKept + size.X * size.Y > MAX_PIXELS_KEPT) do
		local old = oldest()
		if not old then
			break
		end
		drop(old)
	end
	local ok, image = pcall(function()
		return AssetService:CreateEditableImage({ Size = size })
	end)
	if not ok or not image then
		refused = true
		warn("GroundMarks: the ground cannot be painted on this screen (" .. tostring(image)
			.. "); turn on Game Settings > Security > Allow Mesh & Image APIs. No marks are kept.")
		return nil
	end
	local decal = Instance.new("Decal")
	decal.Name = "GroundMarks"
	decal.Face = Enum.NormalId.Top
	decal.TextureContent = Content.fromObject(image)
	decal.Parent = part
	sheet = { image = image, decal = decal, part = part, size = size, used = os.clock() }
	sheets[part] = sheet
	count += 1
	pixelsKept += size.X * size.Y
	part.Destroying:Connect(function()
		drop(part)
	end)
	return sheet
end

-- Where on a part's top face (in pixels of its sheet) a point in the world is, and a direction there (pixels).
-- A Decal on Top runs from the part's -X to +X across and from its -Z to +Z down (seen from above).
-- HALF A TURN ON A MESH (the two-hundred-and-forty-sixth pass, found matching the shop's prints to their marks: a print
-- pressed at a pad's +X +Z corner showed at its -X -Z corner). A Decal on a MeshPart's top lies turned half round from
-- one on a Part, so every mark on the materials' meshes was laid point-mirrored through the middle of the pad: under a
-- symmetrical sole, a crack or a popped bubble nobody could tell, under a paw beside the paw piece you could.
local function meshTurn(sheet: Sheet, v: Vector3): Vector3
	return if sheet.part:IsA("MeshPart") then Vector3.new(-v.X, v.Y, -v.Z) else v
end
local function toPixels(sheet: Sheet, world: Vector3): Vector2
	local here = meshTurn(sheet, sheet.part.CFrame:PointToObjectSpace(world))
	local s = sheet.part.Size
	return Vector2.new((here.X / s.X + 0.5) * sheet.size.X, (here.Z / s.Z + 0.5) * sheet.size.Y)
end
local function dirPixels(sheet: Sheet, dir: Vector3): Vector2
	-- (Turned as a point is: measured in play with a penguin and a slime print laid two ways.)
	local local3 = meshTurn(sheet, sheet.part.CFrame:VectorToObjectSpace(dir))
	local s = sheet.part.Size
	local v = Vector2.new(local3.X / s.X * sheet.size.X, local3.Z / s.Z * sheet.size.Y)
	return if v.Magnitude > 1e-4 then v.Unit else Vector2.new(0, 1)
end

local BLEND = Enum.ImageCombineType.BlendSourceOver

-- A FOOTPRINT: a shoe's sole pressed in along `forward` (pixels). First the ridge of pushed-up stuff in front of the
-- toe and behind the heel, light; then the dent over it, a soft shade, deepest at the heel and the ball; then a few
-- faint tread lines across the ball. Kept soft: it should read as pressed in, never as a stain.
local function press(sheet: Sheet, at: Vector2, forward: Vector2, kind: Kind, side: number)
	local scale = sheet.size.X / sheet.part.Size.X -- pixels a stud
	local across = Vector2.new(-forward.Y, forward.X)
	local function spot(along: number, aside: number): Vector2
		local p = at + forward * along * scale + across * aside * scale
		return Vector2.new(math.floor(p.X), math.floor(p.Y))
	end
	local function blot(along: number, aside: number, radius: number, colour: Color3, see: number)
		sheet.image:DrawCircle(spot(along, aside), math.max(1, math.floor(radius * scale)), colour,
			math.clamp(see, 0, 1), BLEND)
	end
	local lean = side * 0.03 -- the sole curves a little toward the other foot
	local L = 1.35 -- a foot is about a stud and a third long here (0.7 read as a peanut, not a step)
	if kind.lip then
		blot(0.42 * L, lean, 0.3 * L, kind.lip, 0.78) -- ridge pushed up ahead of the toe
		blot(-0.42 * L, 0, 0.24 * L, kind.lip, 0.86) -- smaller one behind the heel
	end
	local shade = 1 - kind.depth
	-- the sole, a run of overlapping soft discs heel to toe, each laid faint so the overlaps build the depth
	local sole = { { -0.3, 0, 0.2 }, { -0.17, 0.01, 0.19 }, { -0.04, 0.02, 0.19 }, { 0.09, 0.03, 0.22 },
		{ 0.21, 0.03, 0.21 }, { 0.31, 0.02, 0.17 } }
	for _, d in ipairs(sole) do
		blot(d[1] * L, (lean + side * d[2]) * L, d[3] * L, kind.ink, shade + 0.32)
	end
	blot(-0.3 * L, 0, 0.12 * L, kind.ink, shade + 0.22) -- the heel sinks deepest
	blot(0.13 * L, lean * L, 0.13 * L, kind.ink, shade + 0.24) -- then the ball
	for k = -1, 1 do -- tread
		local from = spot((0.12 + k * 0.1) * L, (lean - 0.15) * L)
		local to = spot((0.12 + k * 0.1) * L, (lean + 0.15) * L)
		sheet.image:DrawLine(from, to, kind.ink, math.clamp(shade + 0.3, 0, 1), BLEND)
	end
end

-- YOUR OWN PRINT, PRESSED IN (the two-hundred-and-forty-sixth pass, from your note of 2026-11-22: "make it so that the
-- pattern of the selected paw/footprint matches the one that is being put onto the chunk"). With a footprint from the
-- shop on, the mark pressed into sand, snow, clay, salt and foam is that print's own shape, the same one StepService
-- lays (drawPrint there): a paw's pad and toes, a heart, a star, a penguin's three toes. Drawn in the material's own
-- shade, as a dent, so it is the ground keeping your print. Shapes are given as drawPrint gives them, on a square from
-- 0 to 1 (x across, y from the toe down), with their sizes and turns.
type Shape = { x: number, y: number, w: number, h: number, round: boolean, turn: number? }
local PRINT_SHAPES: { [string]: { Shape } } = {
	HeartStep = { { x = 0.32, y = 0.36, w = 0.46, h = 0.46, round = true }, { x = 0.68, y = 0.36, w = 0.46, h = 0.46, round = true },
		{ x = 0.5, y = 0.56, w = 0.5, h = 0.42, round = false, turn = 45 } },
	StarStep = { { x = 0.5, y = 0.5, w = 0.56, h = 0.46, round = false, turn = 0 },
		{ x = 0.5, y = 0.5, w = 0.56, h = 0.46, round = false, turn = 45 } },
	HoneyPaw = { { x = 0.5, y = 0.66, w = 0.56, h = 0.4, round = false }, { x = 0.2, y = 0.36, w = 0.27, h = 0.27, round = true },
		{ x = 0.4, y = 0.24, w = 0.27, h = 0.27, round = true }, { x = 0.6, y = 0.24, w = 0.27, h = 0.27, round = true },
		{ x = 0.8, y = 0.36, w = 0.27, h = 0.27, round = true } },
	CatPaw = { { x = 0.5, y = 0.66, w = 0.5, h = 0.42, round = true }, { x = 0.22, y = 0.4, w = 0.25, h = 0.27, round = true },
		{ x = 0.4, y = 0.26, w = 0.25, h = 0.27, round = true }, { x = 0.6, y = 0.26, w = 0.25, h = 0.27, round = true },
		{ x = 0.78, y = 0.4, w = 0.25, h = 0.27, round = true } },
	-- (The toes a third bigger than drawPrint's flat ones: next to the modelled paw they were pin-pricks.)
	SlimeStep = { { x = 0.5, y = 0.4, w = 0.62, h = 0.5, round = true }, { x = 0.36, y = 0.72, w = 0.16, h = 0.3, round = false },
		{ x = 0.62, y = 0.68, w = 0.12, h = 0.22, round = false } },
	EmberStep = { { x = 0.5, y = 0.5, w = 0.56, h = 0.8, round = true } },
	PenguinSteps = { { x = 0.5, y = 0.72, w = 0.22, h = 0.3, round = true },
		{ x = 0.32, y = 0.38, w = 0.13, h = 0.46, round = false, turn = -28 },
		{ x = 0.5, y = 0.38, w = 0.13, h = 0.46, round = false, turn = 0 },
		{ x = 0.68, y = 0.38, w = 0.13, h = 0.46, round = false, turn = 28 } },
	GildedSteps = { { x = 0.5, y = 0.5, w = 0.56, h = 0.84, round = true } },
	BubbleSole = {}, -- a ring: drawn on its own below
}
-- Studs the 0-to-1 square of a print covers on the ground: the size of the piece StepService lays, so the dent under it
-- is the same print (measured against the honey paw in play).
local PRINT_SIZE = 1.5

local function stampPrint(sheet: Sheet, at: Vector2, forward: Vector2, kind: Kind, id: string)
	local scale = sheet.size.X / sheet.part.Size.X -- pixels a stud
	local across = Vector2.new(-forward.Y, forward.X)
	-- (At least as deep as a press: a crack's ink is laid faint, and a print in it at that depth could not be seen.)
	local shade = 1 - math.max(kind.depth, 0.5)
	-- A point on the print's square, in pixels on the sheet (y = 0 is the toe, ahead of you).
	local function onSheet(x: number, y: number): Vector2
		local p = at + across * (x - 0.5) * PRINT_SIZE * scale + forward * (0.5 - y) * PRINT_SIZE * scale
		return Vector2.new(math.floor(p.X), math.floor(p.Y))
	end
	local function blot(x: number, y: number, r: number, see: number)
		sheet.image:DrawCircle(onSheet(x, y), math.max(1, math.floor(r * PRINT_SIZE * scale)), kind.ink,
			math.clamp(see, 0, 1), BLEND)
	end
	-- (No ridge ahead of it, unlike a shoe's: under a paw or a heart it read as a third shape, not as the snow pushed up.)
	if id == "BubbleSole" then
		for k = 0, 15 do
			local a = k / 16 * math.pi * 2
			blot(0.5 + math.cos(a) * 0.34, 0.5 + math.sin(a) * 0.34, 0.07, shade + 0.2)
		end
		return
	end
	-- Each shape filled with soft discs along its long side (a round one an oval, a square one a bar), turned as drawPrint
	-- turns it; laid faint so overlaps build the depth.
	for _, s in ipairs(PRINT_SHAPES[id] or {}) do
		local long, short = math.max(s.w, s.h), math.min(s.w, s.h)
		local turn = math.rad(s.turn or 0)
		-- the long side's direction on the square (its h runs down, its w across), turned
		local dx, dy = if s.w >= s.h then 1 else 0, if s.w >= s.h then 0 else 1
		local c, sn = math.cos(turn), math.sin(turn)
		dx, dy = dx * c - dy * sn, dx * sn + dy * c
		local count = math.max(1, math.ceil(long / short * 2))
		local reach = (long - short) / 2
		for k = 0, count - 1 do
			local t = if count == 1 then 0 else (k / (count - 1)) * 2 - 1
			local r = short / 2 * (if s.round then math.sqrt(math.max(0.25, 1 - t * t * 0.6)) else 1)
			blot(s.x + dx * reach * t, s.y + dy * reach * t, r * 1.1, shade + 0.2)
		end
		if not s.round and s.turn and s.turn ~= 0 and s.w == s.h then
			-- a turned square: its corners too
			blot(s.x, s.y, short * 0.6, shade + 0.22)
		end
	end
end

-- A CRACK: a split from under your foot, wandering, forking once or twice, thinning as it goes.
local function crack(sheet: Sheet, at: Vector2, forward: Vector2, kind: Kind, dice: Random)
	local scale = sheet.size.X / sheet.part.Size.X
	local function line(from: Vector2, dir: Vector2, long: number, depth: number, strength: number)
		local here = from
		local steps = math.max(2, math.floor(long / 0.25))
		for _ = 1, steps do
			local turn = (dice:NextNumber() - 0.5) * 0.9
			local c, s = math.cos(turn), math.sin(turn)
			dir = Vector2.new(dir.X * c - dir.Y * s, dir.X * s + dir.Y * c)
			local nextAt = here + dir * 0.25 * scale
			sheet.image:DrawLine(Vector2.new(math.floor(here.X), math.floor(here.Y)),
				Vector2.new(math.floor(nextAt.X), math.floor(nextAt.Y)), kind.ink,
				math.clamp(1 - kind.depth * 2.6 * strength, 0, 1), BLEND)
			here = nextAt
			strength *= 0.93
			if depth < 2 and dice:NextNumber() < 0.16 then
				local fork = dice:NextNumber() < 0.5 and 0.7 or -0.7
				local fc, fs = math.cos(fork), math.sin(fork)
				line(here, Vector2.new(dir.X * fc - dir.Y * fs, dir.X * fs + dir.Y * fc), long * 0.45, depth + 1, strength * 0.8)
			end
		end
	end
	local spokes = dice:NextInteger(3, 5)
	for k = 1, spokes do
		local angle = (k / spokes) * math.pi * 2 + dice:NextNumber() * 0.8
		local dir = Vector2.new(math.cos(angle), math.sin(angle))
		line(at + dir * 0.1 * scale, dir, 0.7 + dice:NextNumber() * 0.9, 0, 1)
	end
end

-- ===== A BUBBLE POPPED (the two-hundred-and-thirty-sixth pass) =====
--
-- From your note of 2026-11-10, "work on the bubble wrap further", seen in play on 2026-11-21: a popped bubble and a whole
-- one looked the same, a pale dome a little lower than the next. Now DeformationRenderer, as each pocket bursts, asks
-- for its mark on the sheet: the flattened film where the dome was, a shade greyer, creased from the middle out in
-- four or five folds, with a bright fleck on a fold where the light catches it. When the sheet fills back up (its cell
-- pristine again), the marks over its pockets are lifted off.
local POP_SHADE = Color3.fromRGB(150, 164, 178)
local POP_CREASE = Color3.fromRGB(104, 118, 134)
local POP_GLINT = Color3.fromRGB(255, 255, 255)
local popDice = Random.new()

function GroundMarks.pop(part: BasePart, at: Vector3, radius: number)
	pcall(function()
		local sheet = sheetOf(part)
		if not sheet then
			return
		end
		local scale = sheet.size.X / part.Size.X
		local centre = toPixels(sheet, at)
		local r = math.max(2, math.floor(radius * scale))
		local c = Vector2.new(math.floor(centre.X), math.floor(centre.Y))
		sheet.image:DrawCircle(c, r, POP_SHADE, 0.74, BLEND)
		sheet.image:DrawCircle(c, math.max(1, math.floor(r * 0.55)), POP_SHADE, 0.8, BLEND)
		local folds = popDice:NextInteger(4, 6)
		for k = 1, folds do
			local angle = (k / folds) * math.pi * 2 + popDice:NextNumber() * 0.7
			local bend = angle + (popDice:NextNumber() - 0.5) * 0.6
			local mid = c + Vector2.new(math.cos(angle), math.sin(angle)) * r * (0.35 + popDice:NextNumber() * 0.2)
			local tip = mid + Vector2.new(math.cos(bend), math.sin(bend)) * r * (0.35 + popDice:NextNumber() * 0.25)
			local m = Vector2.new(math.floor(mid.X), math.floor(mid.Y))
			sheet.image:DrawLine(c, m, POP_CREASE, 0.45, BLEND)
			sheet.image:DrawLine(m, Vector2.new(math.floor(tip.X), math.floor(tip.Y)), POP_CREASE, 0.6, BLEND)
			if k == 1 then
				sheet.image:DrawCircle(m, math.max(1, math.floor(r * 0.08)), POP_GLINT, 0.25, BLEND)
			end
		end
		sheet.used = os.clock()
	end)
end

function GroundMarks.unpop(part: BasePart, at: Vector3, radius: number)
	pcall(function()
		local sheet = sheets[part]
		if not sheet then
			return
		end
		local scale = sheet.size.X / part.Size.X
		local centre = toPixels(sheet, at)
		sheet.image:DrawCircle(Vector2.new(math.floor(centre.X), math.floor(centre.Y)),
			math.max(2, math.floor(radius * scale * 1.15)), Color3.new(1, 1, 1), 1, Enum.ImageCombineType.Overwrite)
	end)
end

local walked = 0
local foot = 1
local last: Vector3? = nil
local rng = Random.new()
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function wornPrint(): string?
	local wearing = Players.LocalPlayer:GetAttribute("Footprint")
	if typeof(wearing) == "string" and (PRINT_SHAPES[wearing] or wearing == "BubbleSole") then
		return wearing
	end
	return nil
end

-- PRESSED WHERE YOUR PRINT IS LAID (same pass). With a print from the shop on, StepService lays it and asks for its
-- mark here, at the same spot and the same way, so the dent and the piece are one print; this file's own stride then
-- stands aside (step, below). `at` is the point the print was laid on, `ahead` the way you were going.
-- `id` and `walker` (the two-hundred-and-forty-seventh pass): anyone's print, not only yours. StepService lays every
-- nearby player's pieces, and now asks for each of their dents too, in their own print's shape.
function GroundMarks.stampAt(at: Vector3, ahead: Vector3, id: string?, walker: Model?)
	local print_ = id or wornPrint()
	if not print_ or not (PRINT_SHAPES[print_] or print_ == "BubbleSole") then
		return
	end
	local character = walker or Players.LocalPlayer.Character
	params.FilterDescendantsInstances = if character then { character } else {}
	local hit = workspace:Raycast(at + Vector3.new(0, 1.5, 0), Vector3.new(0, -4, 0), params)
	if not (hit and hit.Instance:IsA("BasePart")) then
		return
	end
	local material, slab = kindOf(hit.Instance)
	if not (material and slab) then
		return
	end
	local kind = KINDS[material]
	local sheet = sheetOf(surfaceOf(slab, hit.Instance))
	if not sheet then
		return
	end
	local flat = Vector3.new(ahead.X, 0, ahead.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local px, dir = toPixels(sheet, hit.Position), dirPixels(sheet, flat.Unit)
	-- On what cracks (ice, the chocolates, waxed butter, cookie) the print is pressed in AND it splits round it, so the
	-- shape is yours there too (the same pass; it was a crack and nothing else).
	stampPrint(sheet, px, dir, kind, print_)
	if kind.style ~= "press" then
		crack(sheet, px, dir, kind, rng)
	end
end

local function step(dt: number)
	if wornPrint() then
		last = nil
		return
	end
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid) or humanoid.FloorMaterial == Enum.Material.Air then
		last = nil
		return
	end
	local here = root.Position
	local flat = if last then Vector3.new(here.X - (last :: Vector3).X, 0, here.Z - (last :: Vector3).Z) else Vector3.zero
	last = here
	if flat.Magnitude > 4 then -- a teleport or a launch, not a step
		return
	end
	walked += flat.Magnitude
	if walked < STRIDE or flat.Magnitude < 1e-3 then
		return
	end
	walked = 0
	foot = -foot
	local forward = flat.Unit
	local across = Vector3.new(-forward.Z, 0, forward.X)
	local footAt = here + across * foot * 0.38
	params.FilterDescendantsInstances = { character }
	local hit = workspace:Raycast(footAt, Vector3.new(0, -6, 0), params)
	if not (hit and hit.Instance:IsA("BasePart")) then
		return
	end
	local material, slab = kindOf(hit.Instance)
	if not (material and slab) then
		return
	end
	local kind = KINDS[material]
	local sheet = sheetOf(surfaceOf(slab, hit.Instance))
	if not sheet then
		return
	end
	local at = toPixels(sheet, hit.Position)
	local dir = dirPixels(sheet, forward)
	if kind.style == "press" then
		press(sheet, at, dir, kind, foot)
	else
		crack(sheet, at, dir, kind, rng)
	end
end

function GroundMarks.start()
	local failed = false
	RunService.Heartbeat:Connect(function(dt: number)
		local ok, err = pcall(step, dt)
		if not ok and not failed then
			failed = true
			warn("GroundMarks: " .. tostring(err) .. " (shown once)")
		end
	end)
	print("GroundMarks: running, " .. GroundMarks.VERSION)
end

GroundMarks.STAMP = "d996c287"
return GroundMarks
