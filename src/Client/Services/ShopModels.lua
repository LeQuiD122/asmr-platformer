--!strict
-- StarterPlayerScripts/Services/ShopModels.lua
-- THE SHOP'S ITEMS IN THE ROUND (the two-hundred-and-twelfth pass, from your note of 2026-11-07: the shop's items
-- wanted models and animations, not flat drawings). Each tile's disc shows a little model of what you are buying,
-- moving the way the thing does:
--
--   trail       a bead of the trail's colour going round, its ribbon of fading beads behind it (sprinkles in colours)
--   aura        a little figure on a plinth, the aura's motes circling and bobbing round it
--   steps       a soft slab, a foot coming down on it and the print it leaves, left and right in turn, fading
--   sound       a little speaker on its plinth, four bars in front of it bouncing to a beat
--   emote       a blocky figure doing the emote (a wave, a cheer, a bow, a spin, a flex, a groove, a stretch...)
--   tokens      a stack of the game's coins, more for a bigger pack, the top one spinning over it
--   crate       a wooden crate whose lid hops and rattles every few seconds
--
-- Passes keep their glyph and backgrounds their swatch (ShopService draws those). Everything is parts in a
-- ViewportFrame inside the disc; one loop moves them all, and lets go of a tile's model when the tile goes. With
-- Roblox's Reduce Motion on (Style.lessMotion), they are drawn and held still, turned a little to show their shape.
--
-- ShopService calls ShopModels.draw(icon, item); false means it has no model for that kind and the old drawing is used.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style"))

local ShopModels = {}

local WHITE = Color3.fromRGB(250, 248, 242)
local GOLD = Color3.fromRGB(244, 196, 70)
local GOLD_EDGE = Color3.fromRGB(186, 128, 30)
local WOOD = Color3.fromRGB(176, 122, 72)
local WOOD_DARK = Color3.fromRGB(122, 80, 44)
-- A warm skin, the same on every figure, so it shows on the pale discs as well as the dark ones.
local SKIN = Color3.fromRGB(236, 186, 146)
local SPRINKLES = { Color3.fromRGB(237, 147, 177), Color3.fromRGB(151, 196, 89), Color3.fromRGB(250, 199, 117),
	Color3.fromRGB(181, 212, 244), Color3.fromRGB(196, 168, 236) }

type Live = { view: ViewportFrame, step: (t: number) -> (), born: number }
local live: { Live } = {}
local loop: RBXScriptConnection? = nil

local function block(parent: Instance, size: Vector3, colour: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = colour
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function bead(parent: Instance, d: number, colour: Color3): Part
	local p = block(parent, Vector3.new(d, d, d), colour)
	p.Shape = Enum.PartType.Ball
	return p
end

-- A cylinder standing up (a Part's cylinder lies along its X): the CFrame it should stand at, turned.
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)
local function drum(parent: Instance, height: number, d: number, colour: Color3, material: Enum.Material?): Part
	local p = block(parent, Vector3.new(height, d, d), colour, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function plinth(parent: Instance, colour: Color3): Part
	-- (A shade darker than its disc, so it shows on the palest of them.)
	local p = drum(parent, 0.3, 2.6, colour:Lerp(Color3.fromRGB(120, 110, 100), 0.35))
	p.CFrame = CFrame.new(0, -1.15, 0) * UPRIGHT
	return p
end

-- A blocky figure: its parts by name, each with the CFrame it hangs from (a shoulder, a hip) so a pose turns it there.
type Figure = { root: CFrame, parts: { [string]: { part: Part, joint: CFrame, hang: CFrame } } }
local function figure(parent: Instance, body: Color3, skin: Color3): Figure
	local f: Figure = { root = CFrame.new(0, -0.95, 0), parts = {} }
	local function limb(name: string, size: Vector3, joint: CFrame, hang: CFrame, colour: Color3)
		f.parts[name] = { part = block(parent, size, colour), joint = joint, hang = hang }
	end
	limb("Torso", Vector3.new(0.9, 0.95, 0.5), CFrame.new(0, 1.55, 0), CFrame.identity, body)
	limb("Head", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, 2.05, 0), CFrame.new(0, 0.3, 0), skin)
	limb("LeftArm", Vector3.new(0.38, 0.95, 0.42), CFrame.new(-0.65, 1.95, 0), CFrame.new(0, -0.4, 0), skin)
	limb("RightArm", Vector3.new(0.38, 0.95, 0.42), CFrame.new(0.65, 1.95, 0), CFrame.new(0, -0.4, 0), skin)
	limb("LeftLeg", Vector3.new(0.42, 1, 0.45), CFrame.new(-0.22, 1.05, 0), CFrame.new(0, -0.5, 0), body:Lerp(Color3.new(), 0.35))
	limb("RightLeg", Vector3.new(0.42, 1, 0.45), CFrame.new(0.22, 1.05, 0), CFrame.new(0, -0.5, 0), body:Lerp(Color3.new(), 0.35))
	return f
end

-- Places the figure: `whole` moves all of it (a bounce, a turn, a bow), and each named joint turns by its own angles.
local function pose(f: Figure, whole: CFrame, turns: { [string]: CFrame })
	local base = f.root * whole
	for name, bit in pairs(f.parts) do
		bit.part.CFrame = base * bit.joint * (turns[name] or CFrame.identity) * bit.hang
	end
end

local A = CFrame.Angles
local function rad(d: number): number
	return math.rad(d)
end

-- How each emote moves, from the seconds since it began.
local EMOTES: { [string]: (t: number) -> (CFrame, { [string]: CFrame }) } = {
	Wave = function(t)
		return CFrame.identity, { RightArm = A(0, 0, rad(150 + 20 * math.sin(t * 7))) }
	end,
	Cheer = function(t)
		local up = math.abs(math.sin(t * 4))
		return CFrame.new(0, up * 0.25, 0), { LeftArm = A(0, 0, rad(-160)), RightArm = A(0, 0, rad(160)) }
	end,
	Bow = function(t)
		local d = (math.sin(t * 1.6) + 1) / 2
		return CFrame.new(0, 1.05, 0) * A(rad(-40 * d), 0, 0) * CFrame.new(0, -1.05, 0), { RightArm = A(rad(-50), 0, rad(30)) }
	end,
	Spin = function(t)
		return A(0, t * 5, 0), { LeftArm = A(0, 0, rad(-80)), RightArm = A(0, 0, rad(80)) }
	end,
	Shrug = function(t)
		local up = math.max(0, math.sin(t * 2.4))
		return CFrame.identity, { LeftArm = A(rad(-30), 0, rad(-50 * up)), RightArm = A(rad(-30), 0, rad(50 * up)),
			Head = A(0, 0, rad(10 * up)) }
	end,
	Flex = function(t)
		-- Arms out and up at the elbow's angle, pumping, the whole of him leaning into it.
		local pump = 10 * math.sin(t * 6)
		return A(0, 0, rad(3 * math.sin(t * 6))), { LeftArm = A(0, 0, rad(-110 - pump)), RightArm = A(0, 0, rad(110 + pump)) }
	end,
	Groove = function(t)
		return CFrame.new(0.12 * math.sin(t * 4), 0.08 * math.abs(math.sin(t * 8)), 0) * A(0, 0, rad(6 * math.sin(t * 4))),
			{ LeftArm = A(0, 0, rad(-30 - 25 * math.sin(t * 4))), RightArm = A(0, 0, rad(30 - 25 * math.sin(t * 4))) }
	end,
	Stretch = function(t)
		local d = (math.sin(t * 1.4) + 1) / 2
		return CFrame.new(0, 0.2 * d, 0), { LeftArm = A(0, 0, rad(-170 * d)), RightArm = A(0, 0, rad(170 * d)) }
	end,
	SitSquish = function(t)
		local squeeze = 0.5 + 0.5 * math.sin(t * 5)
		return CFrame.new(0, -0.45, 0), { LeftLeg = A(rad(90), 0, 0), RightLeg = A(rad(90), 0, 0),
			LeftArm = A(rad(-60), 0, rad(-12 * squeeze)), RightArm = A(rad(-60), 0, rad(12 * squeeze)) }
	end,
	RoyalWave = function(t)
		-- One hand behind, the other up and turning at the wrist, the head slowly crossing the crowd.
		return A(0, 0.25 * math.sin(t * 0.8), 0), { LeftArm = A(rad(40), 0, rad(-20)), RightArm = A(0, 0, rad(120)) * A(0, rad(35 * math.sin(t * 3)), 0),
			Head = A(rad(-8), 0, 0) }
	end,
	Aura = function(t)
		return CFrame.new(0, 0.18 + 0.12 * math.sin(t * 1.5), 0), { LeftArm = A(0, 0, rad(-25)), RightArm = A(0, 0, rad(25)) }
	end,
}

-- ===== EACH KIND: builds into the viewport's world, and returns how it moves =====

local BUILD: { [string]: (world: Instance, item: any) -> (t: number) -> () } = {}

BUILD.trail = function(world, item)
	plinth(world, item.colour)
	local head = item.colour:Lerp(item.accent, 0.25)
	local beads: { BasePart } = {}
	local count = 9
	-- AUTUMN LEAVES (limited): its own leaves (Cos_Leaf) trailing and turning, where the others have beads.
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local cosmetics = assets and assets:FindFirstChild("Cosmetics")
	local leafModel = if item.id == "AutumnLeaves" and cosmetics then cosmetics:FindFirstChild("Cos_Leaf") else nil
	local leafTemplate = if leafModel then leafModel:FindFirstChildWhichIsA("MeshPart", true) else nil
	for k = 1, count do
		local colour = if item.id == "Sprinkles" then SPRINKLES[(k - 1) % #SPRINKLES + 1] else head
		local across = 0.8 * (1 - (k - 1) / (count + 2))
		local b: BasePart
		if leafTemplate then
			local leaf = (leafTemplate :: MeshPart):Clone()
			leaf.Anchored = true
			leaf.CanCollide = false
			leaf.CastShadow = false
			leaf.Size = leaf.Size * (across * 1.9 / math.max(leaf.Size.X, leaf.Size.Y, leaf.Size.Z))
			leaf.Parent = world
			b = leaf
		else
			b = bead(world, across, colour)
			b.Transparency = (k - 1) / (count + 1)
		end
		table.insert(beads, b)
	end
	return function(t)
		for k, b in ipairs(beads) do
			local a = t * 2.2 - (k - 1) * 0.28
			local at = Vector3.new(math.cos(a) * 1.45, 0.35 + math.sin(a * 2) * 0.45, math.sin(a) * 0.8)
			-- (A leaf sways and turns but mostly shows you its face: edge on, it was a red sliver.)
			b.CFrame = if leafTemplate then CFrame.new(at) * CFrame.Angles(0.5 * math.sin(a * 2 + k), 0.6 * math.sin(a + k), 0.4 * math.sin(a * 1.5) + k)
				else CFrame.new(at)
		end
	end
end

BUILD.aura = function(world, item)
	plinth(world, item.colour)
	local pale = item.accent:Lerp(WHITE, 0.45)
	local body = drum(world, 1.3, 0.8, pale)
	body.CFrame = CFrame.new(0, -0.35, 0) * UPRIGHT
	bead(world, 0.62, pale).Position = Vector3.new(0, 0.62, 0)
	local motes: { Part } = {}
	for k = 1, 6 do
		local m = bead(world, if k % 2 == 0 then 0.22 else 0.3, item.accent:Lerp(item.colour, 0.3))
		table.insert(motes, m)
	end
	return function(t)
		for k, m in ipairs(motes) do
			local a = t * 1.3 + k * math.pi / 3
			m.Position = Vector3.new(math.cos(a) * 1.05, -0.3 + ((t * 0.5 + k / 6) % 1) * 1.4, math.sin(a) * 1.05)
			m.Transparency = math.clamp(((t * 0.5 + k / 6) % 1 - 0.7) / 0.3, 0, 1)
		end
	end
end

BUILD.steps = function(world, item)
	local slab = block(world, Vector3.new(3.6, 0.5, 2.6), item.colour:Lerp(WHITE, 0.6))
	slab.CFrame = CFrame.new(0, -0.5, 0)
	local prints: { Part } = {}
	for k = 1, 2 do
		local p = drum(world, 0.06, 0.7, item.accent)
		table.insert(prints, p)
	end
	local foot = block(world, Vector3.new(0.8, 0.5, 1.3), item.colour:Lerp(item.accent, 0.35))
	return function(t)
		local phase = t * 0.9
		local which = math.floor(phase) % 2
		local f = phase % 1
		for k, p in ipairs(prints) do
			local x = if k == 1 then -0.75 else 0.75
			local z = if k == 1 then 0.35 else -0.35
			local mine = (k - 1) == which
			-- The print under the foot appears as it lands, and fades the step after.
			local age = if mine then math.max(0, f - 0.35) / 0.65 else 1 + f
			p.CFrame = CFrame.new(x, -0.22, z) * UPRIGHT
			p.Size = Vector3.new(0.06, 0.75, 1.05)
			p.Transparency = if mine and f < 0.35 then 1 else math.clamp((age - 0.6) / 1.2, 0, 1)
		end
		local x = if which == 0 then -0.75 else 0.75
		local z = if which == 0 then 0.35 else -0.35
		local lift = math.max(0, math.cos(f * math.pi * 2)) * 1.1
		foot.CFrame = CFrame.new(x, 0 + lift, z)
	end
end

BUILD.sound = function(world, item)
	plinth(world, item.colour)
	local box = block(world, Vector3.new(1.5, 1.7, 0.9), item.accent)
	box.CFrame = CFrame.new(0, -0.15, 0.35)
	local cone = drum(world, 0.12, 0.95, item.colour:Lerp(WHITE, 0.5))
	cone.CFrame = CFrame.new(0, -0.3, -0.12) * CFrame.Angles(0, math.pi / 2, 0)
	local dot = drum(world, 0.14, 0.35, item.accent:Lerp(Color3.new(), 0.3))
	dot.CFrame = CFrame.new(0, -0.3, -0.16) * CFrame.Angles(0, math.pi / 2, 0)
	local bars: { Part } = {}
	for k = 1, 4 do
		table.insert(bars, block(world, Vector3.new(0.22, 0.4, 0.22), item.colour:Lerp(item.accent, 0.2)))
	end
	return function(t)
		for k, b in ipairs(bars) do
			local h = 0.25 + 0.75 * math.abs(math.sin(t * (3 + k * 0.7) + k))
			b.Size = Vector3.new(0.22, h, 0.22)
			b.CFrame = CFrame.new(-0.6 + (k - 1) * 0.4, -1 + h / 2, -0.75)
		end
		cone.Size = Vector3.new(0.12, 0.95 + 0.06 * math.sin(t * 12), 0.95 + 0.06 * math.sin(t * 12))
	end
end

BUILD.emote = function(world, item)
	plinth(world, item.colour)
	local f = figure(world, item.accent, SKIN)
	local move = EMOTES[item.id] or EMOTES.Groove
	return function(t)
		local whole, turns = move(t)
		pose(f, whole, turns)
	end
end

BUILD.tokens = function(world, item)
	local amount = tonumber((tostring(item.id):match("%d+"))) or 100
	local stack = math.clamp(math.floor(math.log(amount / 50, 2)) + 1, 2, 7)
	local coins: { Part } = {}
	for k = 1, stack do
		local c = drum(world, 0.22, 1.3, if k % 2 == 0 then GOLD else GOLD:Lerp(GOLD_EDGE, 0.25), Enum.Material.Metal)
		c.CFrame = CFrame.new(0.05 * math.sin(k * 2.1), -1.15 + (k - 1) * 0.23, 0.05 * math.cos(k * 1.7)) * UPRIGHT
		table.insert(coins, c)
	end
	local top = drum(world, 0.2, 1.1, GOLD, Enum.Material.Metal)
	local rim = drum(world, 0.22, 0.6, GOLD_EDGE, Enum.Material.Metal)
	local topY = -1.15 + stack * 0.23 + 0.55
	return function(t)
		-- Lying tilted toward you and turning, so its face is always seen (on its edge it read as a stick).
		local at = CFrame.new(0, topY + 0.12 * math.sin(t * 2), 0) * CFrame.Angles(0, t * 2.5, 0) * CFrame.Angles(math.rad(-35), 0, 0)
		top.CFrame = at * UPRIGHT
		rim.CFrame = at * CFrame.new(0, 0.005, 0) * UPRIGHT
	end
end

-- A PRODUCT (the run boost): its coins, and a green arrow rising beside them and settling.
BUILD.product = function(world, item)
	if item.id ~= "RunBoost" then
		error("no model")
	end
	plinth(world, item.colour)
	for k = 1, 3 do
		local c = drum(world, 0.22, 1.1, if k % 2 == 0 then GOLD else GOLD:Lerp(GOLD_EDGE, 0.25), Enum.Material.Metal)
		c.CFrame = CFrame.new(-0.6, -0.9 + (k - 1) * 0.23, 0) * UPRIGHT
	end
	local green = Color3.fromRGB(110, 220, 140)
	local shaft = block(world, Vector3.new(0.45, 1.1, 0.3), green)
	local head = Instance.new("WedgePart")
	head.Anchored = true
	head.CanCollide = false
	head.CastShadow = false
	head.Size = Vector3.new(0.3, 0.6, 1.1)
	head.Color = green
	head.Parent = world
	local head2 = head:Clone()
	head2.Parent = world
	return function(t)
		local rise = 0.3 * math.abs(math.sin(t * 2))
		local at = CFrame.new(0.65, -0.25 + rise, 0)
		shaft.CFrame = at
		-- Two wedges back to back, the arrow's point.
		-- (Their tall faces meet in the middle, so the two make a point: ^.)
		head.CFrame = at * CFrame.new(0, 0.85, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.new(0, 0, -0.275)
		head2.CFrame = at * CFrame.new(0, 0.85, 0) * CFrame.Angles(0, -math.pi / 2, 0) * CFrame.new(0, 0, -0.275)
	end
end

BUILD.crate = function(world, item)
	local box = block(world, Vector3.new(1.8, 1.3, 1.5), WOOD, Enum.Material.Wood)
	box.CFrame = CFrame.new(0, -0.6, 0)
	for _, y in ipairs({ -0.95, -0.25 }) do
		local band = block(world, Vector3.new(1.84, 0.16, 1.54), WOOD_DARK, Enum.Material.Wood)
		band.CFrame = CFrame.new(0, y, 0)
	end
	local lid = block(world, Vector3.new(2, 0.3, 1.7), WOOD_DARK, Enum.Material.Wood)
	local glow = bead(world, 0.5, item.accent:Lerp(WHITE, 0.4))
	return function(t)
		local beat = t % 3
		local hop = if beat < 0.6 then math.abs(math.sin(beat / 0.6 * math.pi * 2)) * 0.35 else 0
		local rattle = if beat < 0.6 then math.sin(beat * 50) * 0.08 else 0
		box.CFrame = CFrame.new(rattle * 0.5, -0.6, 0) * CFrame.Angles(0, 0, rattle * 0.5)
		lid.CFrame = CFrame.new(rattle, 0.2 + hop, 0) * CFrame.Angles(0, 0, rattle * 1.5)
		glow.Position = Vector3.new(0, 0.15 + hop * 0.6, 0)
		glow.Transparency = if hop > 0.05 then 0.2 else 1
	end
end

-- A PAL (the two-hundred-and-sixteenth pass): the pal itself (its model from Assets.Cosmetics), doing what it does at
-- your side: hopping and squashing on its plinth, or bobbing over it.
BUILD.pal = function(world, item)
	local ShopCatalog = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("ShopCatalog")) :: any
	local spec = ShopCatalog.pal(item.id)
	local assets = game:GetService("ReplicatedStorage"):FindFirstChild("Assets")
	local cosmetics = assets and assets:FindFirstChild("Cosmetics")
	local found = spec and cosmetics and cosmetics:FindFirstChild(spec.mesh)
	local template = if found and found:IsA("MeshPart") then found elseif found then found:FindFirstChildWhichIsA("MeshPart", true) else nil
	if not template then
		error("no model")
	end
	plinth(world, item.colour)
	local part = (template :: MeshPart):Clone()
	part.Anchored = true
	part.CanCollide = false
	local largest = math.max(part.Size.X, part.Size.Y, part.Size.Z)
	local base = part.Size * (2.1 / largest)
	part.Size = base
	part.Parent = world
	local hopper = spec.motion == "hop"
	local yaw = math.rad(spec.yaw or 0)
	return function(t)
		local size, y, roll = base, 0, 0
		if hopper then
			local u = (t * 0.9) % 1
			local height = 0.55 * math.sin(u * math.pi)
			local land = if u < 0.12 then 1 - u / 0.12 elseif u > 0.88 then (u - 0.88) / 0.12 else 0
			local s = (spec.squash or 0.3) * land - 0.1 * math.sin(u * math.pi)
			size = Vector3.new(base.X * (1 + s * 0.6), base.Y * (1 - s), base.Z * (1 + s * 0.6))
			y = -1.0 + size.Y / 2 + height -- on the plinth's top
		else
			y = -0.2 + 0.18 * math.sin(t * 2.2)
			roll = 0.08 * math.sin(t * 1.6)
		end
		part.Size = size
		-- Facing the camera (-Z), turning a little to show its shape.
		part.CFrame = CFrame.new(0, y, 0) * CFrame.Angles(0, yaw + 0.35 * math.sin(t * 0.7), roll)
	end
end

-- ===== THE LOOP =====

local function ensureLoop()
	if loop then
		return
	end
	loop = RunService.RenderStepped:Connect(function()
		if #live == 0 then
			if loop then
				loop:Disconnect()
				loop = nil
			end
			return
		end
		local now = os.clock()
		for k = #live, 1, -1 do
			local entry = live[k]
			if not entry.view.Parent then
				table.remove(live, k)
			elseif entry.view.Visible and entry.view.AbsoluteSize.X > 0 then
				entry.step(now - entry.born)
			end
		end
	end)
end

-- Draws `item` into `icon` (its disc) as a model in the round. False when there is no model for its kind.
function ShopModels.draw(icon: GuiObject, item: any): boolean
	local build = BUILD[item.kind]
	if not build then
		return false
	end
	local view = Instance.new("ViewportFrame")
	view.Name = "Model"
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.Position = UDim2.fromScale(0.5, 0.5)
	view.Size = UDim2.fromScale(0.94, 0.94)
	view.BackgroundTransparency = 1
	view.Ambient = item.colour:Lerp(Color3.fromRGB(150, 146, 140), 0.6)
	view.LightColor = Color3.fromRGB(255, 250, 240)
	view.LightDirection = Vector3.new(-0.6, -1, -0.8)
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = view
	local world = Instance.new("WorldModel")
	world.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = 36
	-- Framed on the models' middle (they stand from the plinth at -1.3 to a head at 1.7), far enough back that the
	-- round of the disc never cuts a head or a lid.
	camera.CFrame = CFrame.lookAt(Vector3.new(0, 1.35, -6.5), Vector3.new(0, 0.2, 0))
	camera.Parent = view
	view.CurrentCamera = camera
	local ok, step = pcall(build, world, item)
	if not ok or type(step) ~= "function" then
		view:Destroy()
		return false
	end
	view.Parent = icon
	-- Its first frame now, so it is never empty; held still on that frame under Reduce Motion.
	local born = os.clock() - (#live % 7) * 0.4
	pcall(step, 1.3)
	if not Style.lessMotion() then
		table.insert(live, { view = view, step = step, born = born })
		ensureLoop()
	end
	return true
end

ShopModels.STAMP = "9f46b345"
return ShopModels
