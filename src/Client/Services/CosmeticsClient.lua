--!strict
-- StarterPlayerScripts/Services/CosmeticsClient.lua
-- THE SHOP'S TRAILS AND AURAS AS THINGS (the ninety-seventh pass, from "way better quality items in my shop ... blender
-- meshes and animations ... make all of the cosmetics in the shop look better").
--
-- They were particles only: flat sprites in Roblox's four stock textures, the same few on everything. On top of them
-- now (the particles stay, as their haze and glints), every trail and aura is made of small modelled things, seen by
-- everyone near: blender/gen_cosmetics.py's meshes (ReplicatedStorage.Assets.Cosmetics), coloured and moved here.
--
--   A TRAIL lets one go behind you every few studs you cover, and it does what that thing would: sprinkles are tossed
--   and tumble and bounce and lie there; honey drips, falls and spreads where it lands; soap bubbles float up wobbling
--   and pop; slime lands with a splat that wobbles; cloud puffs swell and thin; jelly beads bounce; sea glass and the
--   swatch's chips tumble; embers fall glowing and cool to ash; the green ribbon's glints flutter down.
--   AN AURA carries a few round you, always: stars and gold circling and twinkling, snowflakes falling and turning,
--   bubbles and embers rising, fireflies wandering with their wings beating (two of them lit), mist drifting at your
--   feet.
--
-- WHAT EACH IS, in ShopCatalog (PIECES): its meshes, sizes, colours, material and motion, so the shop and this cannot
-- disagree. WHAT YOU WEAR is read off your character, where ShopCatalog.wear tags it (PieceTrail, PieceAura) for the
-- server's look and for the shop's try-on alike: so the preview is the real thing, as the particles are.
--
-- CHEAP BY DESIGN: on this screen only (nothing is sent), anchored and touching nothing, players within NEAR only, at
-- most TRAIL_MAX of a trail's and AURA_MAX of an aura's, and PIECES_MAX in all; a piece is put back in a pool, not
-- destroyed. Without the meshes imported, nothing here is drawn and the particles carry it alone (said once).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ShopCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ShopCatalog")) :: any

local CosmeticsClient = {}
CosmeticsClient.VERSION = "ninety-seventh pass, 2026-10-18"

local NEAR = 120 -- studs: further off, nothing is drawn
local TRAIL_MAX = 22 -- a trail's pieces alive at once, per player
local AURA_MAX = 8 -- an aura's, per player
local PIECES_MAX = 260 -- in all, on this screen
local GRAVITY = 34
local FLAP = 22 -- a firefly's wingbeats, a second

type Live = { part: BasePart, wings: BasePart?, born: number, life: number, motion: string, from: Vector3, vel: Vector3,
	spin: Vector3, angle: Vector3, ground: number, landed: boolean, bounces: number, size: Vector3, colour: Color3,
	cool: Color3?, alpha: number, phase: number, owner: Player, aura: boolean, slot: number, seed: number, landedAt: number }
type Wearer = { trail: string?, aura: string?, last: Vector3?, travelled: number, auraSet: { Live } }

local live: { Live } = {}
local wearers: { [Player]: Wearer } = {}
local pool: { [string]: { BasePart } } = {}
local folder: Folder? = nil
local templates: Folder? = nil
local warned = false -- the meshes missing, said once
local failed = false -- a step that went wrong, said once
local rng = Random.new()
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function holder(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "CosmeticPieces"
	made.Parent = workspace
	folder = made
	return made
end

local function meshes(): Folder?
	local found = templates
	if found and found.Parent then
		return found
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local cosmetics = assets and assets:FindFirstChild("Cosmetics")
	if cosmetics and cosmetics:IsA("Folder") then
		templates = cosmetics
		return cosmetics
	end
	if not warned then
		warned = true
		warn("[client] CosmeticsClient: no ReplicatedStorage.Assets.Cosmetics, so the shop's trails and auras are particles "
			.. "only. Import meshes/cosmetics/*.fbx into it (see HANDOFF).")
	end
	return nil
end

-- A part of the right kind, from the pool or new: a mesh (its largest side `size` studs) or a ball.
local function take(mesh: string, size: number): BasePart?
	local list = pool[mesh]
	local part: BasePart? = if list and #list > 0 then table.remove(list) else nil
	if not part then
		if mesh == "Ball" then
			local ball = Instance.new("Part")
			ball.Shape = Enum.PartType.Ball
			part = ball
		else
			local source = meshes()
			local found = source and source:FindFirstChild(mesh)
			local template = if found and found:IsA("MeshPart") then found
				elseif found then found:FindFirstChildWhichIsA("MeshPart", true) else nil
			if not template then
				return nil
			end
			part = (template :: MeshPart):Clone()
		end
		local made = part :: BasePart
		made.Anchored = true
		made.CanCollide = false
		made.CanQuery = false
		made.CanTouch = false
		made.CastShadow = false
		made.Massless = true
		made:SetAttribute("Mesh", mesh)
		-- Its own proportions, kept: a piece back from the pool may have been squashed where it landed.
		made:SetAttribute("Base", made.Size)
	end
	local made = part :: BasePart
	local kept = made:GetAttribute("Base")
	local base = if typeof(kept) == "Vector3" then kept else made.Size
	local largest = math.max(base.X, base.Y, base.Z)
	if mesh == "Ball" then
		made.Size = Vector3.new(size, size, size)
	elseif largest > 0 then
		made.Size = base * (size / largest)
	end
	made.Parent = holder()
	return made
end

local function give(part: BasePart)
	local mesh = part:GetAttribute("Mesh")
	part.Parent = nil
	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("Light") then
			child:Destroy()
		end
	end
	if typeof(mesh) == "string" then
		pool[mesh] = pool[mesh] or {}
		if #pool[mesh] < 64 then
			table.insert(pool[mesh], part)
		else
			part:Destroy()
		end
	else
		part:Destroy()
	end
end

local function groundUnder(at: Vector3): number
	local ignore: { Instance } = { holder() }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	rayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(at, Vector3.new(0, -10, 0), rayParams)
	return if hit then hit.Position.Y else at.Y - 3.2
end

local function dress(part: BasePart, piece: any, colour: Color3)
	part.Color = colour
	part.Material = if piece.material == "Glass" then Enum.Material.Glass
		elseif piece.material == "Neon" then Enum.Material.SmoothPlastic -- never Neon (no fake light)
		else Enum.Material.SmoothPlastic
	part.Reflectance = piece.shine or 0.05
	part.Transparency = piece.alpha or 0
end

-- One piece of `look`, let go at `at` (a trail's) or placed in an aura's `slot`.
local function spawn(owner: Player, look: any, at: Vector3, heading: Vector3, aura: boolean, slot: number): Live?
	if #live >= PIECES_MAX then
		return nil
	end
	local piece = look.pieces[rng:NextInteger(1, #look.pieces)]
	local part = take(piece.mesh, piece.size * rng:NextNumber(0.85, 1.15))
	if not part then
		return nil
	end
	local colour = piece.colours[rng:NextInteger(1, #piece.colours)]
	dress(part, piece, colour)
	local wings: BasePart? = nil
	if piece.wings then
		wings = take(piece.wings, piece.size * 1.1)
		if wings then
			dress(wings, { material = "Glass", alpha = 0.55, shine = 0.2 }, Color3.fromRGB(230, 240, 255))
		end
	end
	if piece.light and slot <= (piece.lights or 2) then
		local glow = Instance.new("PointLight")
		glow.Color = piece.light
		glow.Brightness = 0.7
		glow.Range = 5
		glow.Shadows = false
		glow.Parent = part
	end
	local side = heading:Cross(Vector3.yAxis)
	local motion = look.motion
	local vel = Vector3.zero
	if motion == "toss" then
		vel = side * rng:NextNumber(-3, 3) + Vector3.new(0, rng:NextNumber(4, 7), 0) - heading * rng:NextNumber(0.5, 2)
	elseif motion == "flutter" then
		vel = Vector3.new(0, -1.2, 0)
	end
	local one: Live = { part = part, wings = wings, born = os.clock(), life = look.life * rng:NextNumber(0.85, 1.15),
		motion = motion, from = at, vel = vel, spin = Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-6, 6), rng:NextNumber(-6, 6)),
		angle = Vector3.new(rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28), rng:NextNumber(0, 6.28)),
		ground = if aura then 0 else groundUnder(at), landed = false, bounces = 0, size = part.Size, colour = colour,
		cool = piece.cool, alpha = piece.alpha or 0, phase = rng:NextNumber(0, 6.28), owner = owner, aura = aura, slot = slot,
		seed = rng:NextNumber(0, 100), landedAt = 0 }
	part.CFrame = CFrame.new(at)
	table.insert(live, one)
	return one
end

-- Where a thing of an aura is, `t` seconds into its round, about a root at `root`.
local function auraPlace(one: Live, look: any, root: Vector3, now: number): (Vector3, number)
	local count = math.max(1, look.count or 6)
	local radius = look.radius or 2.4
	local a = one.slot / count * math.pi * 2 + one.phase
	local motion = one.motion
	if motion == "orbit" then
		local turn = now * (look.spin or 0.5) + a
		local height = math.sin(now * 1.3 + one.phase) * 0.6 + 0.4
		return root + Vector3.new(math.cos(turn) * radius, height, math.sin(turn) * radius), 0
	elseif motion == "hover" then
		local wander = Vector3.new(math.noise(now * 0.4, one.seed, 0), math.noise(0, now * 0.4, one.seed) * 0.6,
			math.noise(one.seed, 0, now * 0.4))
		return root + Vector3.new(math.cos(a) * radius, 0.6, math.sin(a) * radius) + wander * 2.4, 0
	elseif motion == "drift" then
		local turn = now * 0.12 + a
		return root + Vector3.new(math.cos(turn) * radius, -2.4, math.sin(turn) * radius), 0
	end
	-- "rise" and "fall": round their life, each its own way round, from the bottom up or the top down.
	local life = one.life
	-- Each its own way through its round (its phase), so they do not rise or fall all together.
	local u = (((now - one.born) + one.phase / (2 * math.pi) * life) % life) / life
	local y = if motion == "fall" then 3.2 - 5.6 * u else -2.2 + 4.6 * u
	local sway = math.sin(now * 2 + one.phase) * 0.25
	return root + Vector3.new(math.cos(a) * (radius + sway), y, math.sin(a) * (radius + sway)), u
end

local function step(dt: number)
	local now = os.clock()
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	-- WHO WEARS WHAT, near enough to see.
	local seen: { [Player]: boolean } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - eye).Magnitude < NEAR then
			seen[player] = true
			local w = wearers[player] or { trail = nil, aura = nil, last = nil, travelled = 0, auraSet = {} }
			wearers[player] = w
			local trailTag = root:FindFirstChild("ShopPreviewTrailTop") or root:FindFirstChild("CosmeticTrailTop")
			local auraTag = root:FindFirstChild("ShopPreviewAura") or root:FindFirstChild("CosmeticAura")
			local trail = trailTag and trailTag:GetAttribute("PieceTrail")
			local aura = auraTag and auraTag:GetAttribute("PieceAura")
			w.trail = if typeof(trail) == "string" then trail else nil
			local wantAura = if typeof(aura) == "string" then aura else nil
			if wantAura ~= w.aura then
				for _, one in ipairs(w.auraSet) do
					one.life = 0
				end
				table.clear(w.auraSet)
				w.aura = wantAura
			end
			-- THE TRAIL: one let go every `every` studs covered, behind you, a little to one side or the other.
			local look = w.trail and ShopCatalog.pieces(w.trail)
			local here = root.Position
			if look and meshes() then
				local last = w.last or here
				local moved = Vector3.new(here.X - last.X, 0, here.Z - last.Z).Magnitude
				w.travelled += if moved < 8 then moved else 0
				local count = 0
				for _, one in ipairs(live) do
					if one.owner == player and not one.aura then
						count += 1
					end
				end
				local heading = root.CFrame.LookVector
				heading = Vector3.new(heading.X, 0, heading.Z)
				heading = if heading.Magnitude > 0.01 then heading.Unit else Vector3.zAxis
				while w.travelled >= look.every and count < TRAIL_MAX do
					w.travelled -= look.every
					local side = heading:Cross(Vector3.yAxis) * rng:NextNumber(-0.6, 0.6)
					spawn(player, look, here - heading * 0.9 + side + Vector3.new(0, rng:NextNumber(-0.6, 0.4), 0), heading, false, 0)
					count += 1
				end
				w.travelled = math.min(w.travelled, look.every)
			end
			w.last = here
			-- THE AURA: its set, kept full.
			local auraLook = w.aura and ShopCatalog.pieces(w.aura)
			if auraLook and meshes() then
				local want = math.min(AURA_MAX, auraLook.count or 6)
				for slot = #w.auraSet + 1, want do
					local one = spawn(player, auraLook, here, Vector3.zAxis, true, slot)
					if one then
						table.insert(w.auraSet, one)
					else
						break
					end
				end
			end
		end
	end
	for player, w in pairs(wearers) do
		if not seen[player] then
			for _, one in ipairs(w.auraSet) do
				one.life = 0
			end
			wearers[player] = nil
		end
	end
	-- EVERY PIECE MOVED, and the spent ones put away.
	local k = 1
	while k <= #live do
		local one = live[k]
		local age = now - one.born
		local done = not one.part.Parent or not one.owner.Parent
		local part = one.part
		one.angle += one.spin * dt
		if one.aura then
			local w = wearers[one.owner]
			local root = one.owner.Character and one.owner.Character:FindFirstChild("HumanoidRootPart")
			local look = w and w.aura and ShopCatalog.pieces(w.aura)
			if one.life <= 0 or not (w and look and root and root:IsA("BasePart")) then
				done = true
			else
				local at, u = auraPlace(one, look, (root :: BasePart).Position, now)
				local twinkle = if one.motion == "orbit" then 0.75 + 0.25 * math.sin(now * 5 + one.phase * 3) else 1
				part.Size = one.size * twinkle
				local fadeIn = math.clamp(age / 0.6, 0, 1)
				local edge = if one.motion == "rise" or one.motion == "fall" then math.clamp(math.min(u, 1 - u) / 0.15, 0, 1) else 1
				part.Transparency = 1 - (1 - one.alpha) * fadeIn * edge
				if one.cool then
					part.Color = one.colour:Lerp(one.cool, math.clamp(u * 1.2, 0, 1))
				end
				part.CFrame = CFrame.new(at) * CFrame.fromEulerAnglesXYZ(one.angle.X * 0.3, one.angle.Y, one.angle.Z * 0.3)
				if one.wings then
					local beat = math.sin(now * FLAP * math.pi * 2 + one.phase) * 0.7
					one.wings.CFrame = part.CFrame * CFrame.new(0, part.Size.Y * 0.3, 0) * CFrame.Angles(0, 0, beat)
					one.wings.Transparency = math.max(part.Transparency, 0.55)
				end
			end
		else
			local u = age / one.life
			if u >= 1 then
				done = true
			else
				local pos = part.Position
				local motion = one.motion
				local scale = 1
				local fade = math.clamp((u - 0.7) / 0.3, 0, 1)
				if motion == "rise" then
					-- A bubble: up, wobbling, growing a little; then it pops.
					pos = one.from + Vector3.new(math.sin(age * 3 + one.phase) * 0.25, age * 1.4, math.cos(age * 2.6 + one.phase) * 0.25)
					scale = 1 + 0.25 * u + 0.06 * math.sin(age * 9)
					if u > 0.88 then
						scale *= 1 + (u - 0.88) * 4
						fade = (u - 0.88) / 0.12
					else
						fade = 0
					end
				elseif motion == "puff" then
					-- A cloud puff: hangs where it was left, swelling and thinning, lifting a little.
					pos = one.from + Vector3.new(0, age * 0.35, 0)
					scale = 1 + 0.9 * u
					fade = u ^ 1.5
				elseif motion == "flutter" then
					-- A glint: drifting down, side to side, turning.
					pos = one.from + Vector3.new(math.sin(age * 4 + one.phase) * 0.5, -age * 1.1, math.cos(age * 3 + one.phase) * 0.3)
					fade = u ^ 2
				else
					-- "toss", "drip", "splat", "bounce": falling under gravity, to the ground, and what it does there.
					if not one.landed then
						one.vel -= Vector3.new(0, GRAVITY * dt, 0)
						pos += one.vel * dt
						local half = one.size.Y * 0.5
						if pos.Y - half <= one.ground then
							pos = Vector3.new(pos.X, one.ground + half, pos.Z)
							local bounce = if motion == "bounce" then 0.45 elseif motion == "toss" then 0.3 else 0
							local most = if motion == "bounce" then 2 else 1
							if bounce > 0 and one.bounces < most and math.abs(one.vel.Y) > 2 then
								one.vel = Vector3.new(one.vel.X * 0.6, -one.vel.Y * bounce, one.vel.Z * 0.6)
								one.bounces += 1
							else
								one.landed = true
								one.vel = Vector3.zero
								one.spin = Vector3.zero
								one.landedAt = age
							end
						end
					end
					if one.landed then
						local since = age - one.landedAt
						if motion == "drip" or motion == "splat" then
							-- It spreads where it lands: flattening, widening, a wobble going out of it.
							local spread = math.clamp(since / 0.25, 0, 1)
							local wobble = 1 + 0.15 * math.sin(since * 22) * math.exp(-since * 5)
							part.Size = Vector3.new(one.size.X * (1 + 0.5 * spread) * wobble, one.size.Y * (1 - 0.6 * spread),
								one.size.Z * (1 + 0.5 * spread) * wobble)
							one.angle = Vector3.new(0, one.angle.Y, 0)
						end
					end
				end
				if motion == "rise" or motion == "puff" or motion == "flutter" then
					part.Size = one.size * scale
				end
				if one.cool then
					part.Color = one.colour:Lerp(one.cool, math.clamp(u * 1.6, 0, 1))
				end
				part.Transparency = 1 - (1 - one.alpha) * (1 - fade)
				part.CFrame = CFrame.new(pos) * CFrame.fromEulerAnglesXYZ(one.angle.X, one.angle.Y, one.angle.Z)
			end
		end
		if done then
			give(part)
			if one.wings then
				give(one.wings)
			end
			live[k] = live[#live]
			live[#live] = nil
		else
			k += 1
		end
	end
end

function CosmeticsClient.start()
	RunService.RenderStepped:Connect(function(dt: number)
		local ok, err = pcall(step, math.min(dt, 0.1))
		if not ok and not failed then
			failed = true
			warn("[client] CosmeticsClient: " .. tostring(err) .. " (shown once)")
		end
	end)
	print("CosmeticsClient: running, " .. CosmeticsClient.VERSION)
end

CosmeticsClient.STAMP = "ec389bcc"
return CosmeticsClient
