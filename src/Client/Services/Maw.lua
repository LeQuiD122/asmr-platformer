--!strict
-- StarterPlayerScripts/Services/Maw.lua
-- The mouth at the bottom of the flume, on one player's screen only. Nothing else of it is ever seen:
-- what keeps the Hold is never shown whole (LORE.md). FloodedHallsClient opens it under the rider at
-- the end of the fall and shuts it on them; StoryClient lets it breathe, far down, for anyone who
-- prises up the loose board on the gangway.
--
-- Four meshes from blender/gen_maw.py, in ReplicatedStorage/Assets/TileMeshes: Maw_UpperJaw,
-- Maw_LowerJaw, Maw_UpperTeeth, Maw_LowerTeeth. Each one's box is centred on the jaw's hinge, so a jaw
-- is its hinge turned about its own X. Without them (or with an old import, which SIZE catches), a
-- rougher mouth of parts stands in, so the scene never waits on an import.
--
-- In the hinge's frame the mouth opens toward -Z; the upper jaw is on the +Y side of it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Maw = {}

-- What gen_maw.py builds (blender/maw_extents.json): an import that does not match is an old one.
Maw.SIZE = {
	Maw_UpperJaw = Vector3.new(55.0, 27.56, 105.0),
	Maw_LowerJaw = Vector3.new(51.22, 27.49, 97.72),
	Maw_UpperTeeth = Vector3.new(54.5, 40.76, 107.57),
	Maw_LowerTeeth = Vector3.new(49.94, 11.12, 95.81),
}
local LENGTH, HALF_W = 52, 27 -- gen_maw.py's jaw, for the stand-in
-- THE MESHES COME IN BACK TO FRONT (the two-hundred-and-fifty-second pass, from your look at the frame where it first
-- opens: "its teeth are out of place"). Measured in Studio by casting rays down onto each imported mesh: all four
-- run toward the hinge's +Z, back down the throat, not -Z as gen_maw.py's contract and everything here assume. So
-- every "open" swung each jaw the wrong way and the two passed through each other in an X: the fangs stuck out of
-- the other jaw's outside, the inner rows and the tongue stood in the air where the jaws should have been. Each mesh
-- is turned half round the hinge's Y as it is placed (they are the same either side of X, so nothing else moves).
local MESH_TURN = CFrame.Angles(0, math.pi, 0)
local FLESH = Color3.fromRGB(58, 16, 20)
local BONE = Color3.fromRGB(226, 218, 196)
-- The upper jaw's colour when the lower jaw wears its generated texture (that texture's own red).
local TEXTURED_FLESH = Color3.fromRGB(186, 60, 62)

export type Strand = { near: BasePart, far: BasePart, top: CFrame, bottom: CFrame, snaps: number }
export type Built = { model: Model, hinge: CFrame, upper: { { part: BasePart, offset: CFrame } },
	lower: { { part: BasePart, offset: CFrame } }, glow: PointLight, rim: SpotLight, meshes: boolean,
	gullet: PointLight, aura: { PointLight }, strands: { Strand }, breath: ParticleEmitter, upperAngle: number?,
	lowerAngle: number?, throat: { Ring }, tongue: { { part: BasePart, offset: CFrame, base: CFrame } }, drool: ParticleEmitter?,
	uvula: { { part: BasePart, offset: CFrame, base: CFrame, swing: number } }, grind: number, clockAt: number?,
	hungry: number, reaching: number }
-- One piece of a ring down the throat: a roll of gum (`long` 0) or a fang standing out of it, at `angle` round the ring.
export type Ring = { part: BasePart, ring: number, angle: number, long: number }

-- THE THROAT (the two-hundred-and-fiftieth pass, "improve the monster on level 4"): behind the hinge, rings of gum,
-- each set with fangs leaning in and down, one inside the next to the dark. They grind round, each against the one
-- before it, and squeeze in a wave that runs down the throat, so the mouth is alive past its jaws and anything that
-- falls in is taken down. Kept inside the skull's own outline (narrow in Y, the way the jaws open), so nothing of
-- it shows from outside; and no tube or end to it, only rings, so there is no disc lying in the mouth.
-- { depth past the hinge, half width (X), half height (Y), fangs, fang length }
local RINGS = { { 2, 19, 8.5, 16, 5 }, { 8, 15.8, 7.3, 14, 4.3 }, { 14, 12.6, 6.1, 12, 3.6 }, { 20, 9.4, 4.9, 10, 2.9 } }
local GRIND, SQUEEZE, FANG_LEAN = 0.22, 0.07, 0.55
-- HUNGRY (Maw.hunger, 0 to 1): as it comes for you the rings grind this many times faster and squeeze this much harder.
local HUNGRY_GRIND, HUNGRY_SQUEEZE = 4, 2.2
-- REACHING (Maw.reach, 0 to 1): the tongue lifts off the floor of the mouth toward what falls into it, by this much.
local REACH_LIFT = 0.55
-- THE INNER ROWS (the two-hundred-and-fifty-first pass, "improve the maw model even more"): a second row of fangs inside
-- each jaw's rim, shorter and raked back toward the throat, the way a shark's are, so nothing that goes in comes out.
-- { jaw scale, how far in from the rim (share of the jaw), fangs, length }
local INNER_ROWS = { upper = { 1, 0.78, 16, 5.2 }, lower = { 0.93, 0.76, 14, 4.2 } }
local VAULT, GUM_BAND = 6, 2.6 -- gen_maw.py's VAULT and GUM, to find the roof of the mouth
local GUM_RED = Color3.fromRGB(138, 40, 48)

local function template(name: string): MeshPart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("TileMeshes")
	local found = folder and folder:FindFirstChild(name)
	local part = if found and found:IsA("MeshPart") then found elseif found then found:FindFirstChildWhichIsA("MeshPart", true) else nil
	local want = Maw.SIZE[name]
	if not (part and want) then
		return nil
	end
	local got = part.Size
	if math.abs(got.X - want.X) > want.X * 0.15 or math.abs(got.Y - want.Y) > want.Y * 0.15
		or math.abs(got.Z - want.Z) > want.Z * 0.15 then
		warn(("Maw: %s is imported at %.1f x %.1f x %.1f, built %.1f x %.1f x %.1f: an old import; the stand-in is used.")
			:format(name, got.X, got.Y, got.Z, want.X, want.Y, want.Z))
		return nil
	end
	return part :: MeshPart
end

local function dress(part: BasePart, colour: Color3, wet: number)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = true
	part.Color = colour
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = wet
end

-- The stand-in: a jaw plate and a row of fangs, as parts, with their offsets from the hinge.
local function standIn(model: Model, upper: boolean): { { part: BasePart, offset: CFrame } }
	local out = {}
	local sign = if upper then 1 else -1
	local scale = if upper then 1 else 0.93
	local plate = Instance.new("Part")
	plate.Name = if upper then "UpperJaw" else "LowerJaw"
	plate.Size = Vector3.new(HALF_W * 2 * scale, 8, LENGTH * scale)
	local shape = Instance.new("SpecialMesh")
	shape.MeshType = Enum.MeshType.Sphere
	shape.Parent = plate
	dress(plate, FLESH, 0.06)
	plate.Parent = model
	table.insert(out, { part = plate, offset = CFrame.new(0, sign * 3, -LENGTH * scale / 2) })
	local count = if upper then 22 else 18
	for k = 1, count do
		local th = -math.pi / 2 * 0.92 + math.pi * 0.92 * (k - 0.5) / count
		local x, z = HALF_W * scale * 0.95 * math.sin(th), -LENGTH * scale * 0.95 * math.cos(th)
		local long = (if upper then 5 + 11 * math.cos(th) ^ 2 else 2 + 3 * math.cos(th) ^ 2)
		local fang = Instance.new("Part")
		fang.Name = "Fang"
		fang.Size = Vector3.new(0.9, long, 0.9)
		local spindle = Instance.new("SpecialMesh")
		spindle.MeshType = Enum.MeshType.Sphere
		spindle.Parent = fang
		dress(fang, BONE, 0.12)
		fang.Parent = model
		local lean = CFrame.Angles(-0.25 * math.cos(th) * sign, 0, 0.25 * math.sin(th) * sign)
		table.insert(out, { part = fang, offset = CFrame.new(x, -sign * long / 2, z) * lean })
	end
	return out
end

-- The mouth, shut, at `hinge`, under `parent`. Dark: its lights start at nothing.
function Maw.build(hinge: CFrame, parent: Instance): Built
	local model = Instance.new("Model")
	model.Name = "TheMaw"
	local upper, lower = {}, {}
	local parts = {
		{ "Maw_UpperJaw", FLESH, 0.07, upper },
		{ "Maw_UpperTeeth", BONE, 0.14, upper },
		{ "Maw_LowerJaw", FLESH, 0.07, lower },
		{ "Maw_LowerTeeth", BONE, 0.14, lower },
	}
	local meshes = true
	for _, spec in ipairs(parts) do
		if not template(spec[1] :: string) then
			meshes = false
		end
	end
	if meshes then
		-- MATCHED GUMS (the two-hundred-and-twelfth pass): the lower jaw and the fangs carry generated textures,
		-- but the upper jaw's mesh had no UVs to take one. Its plain colour is set to the lower jaw's red so the
		-- two halves of the mouth read as one flesh. (Since the two-hundred-and-fiftieth pass gen_maw.py unwraps the
		-- upper jaw and its import wears the lower jaw's flesh texture too; the colour stays for an older import.)
		local lowerJaw = template("Maw_LowerJaw")
		if lowerJaw and lowerJaw.TextureID ~= "" then
			parts[1][2] = TEXTURED_FLESH
		end
		for _, spec in ipairs(parts) do
			local part = (template(spec[1] :: string) :: MeshPart):Clone()
			dress(part, spec[2] :: Color3, spec[3] :: number)
			part.Parent = model
			table.insert(spec[4] :: { any }, { part = part, offset = MESH_TURN })
		end
	else
		for _, entry in ipairs(standIn(model, true)) do
			table.insert(upper, entry)
		end
		for _, entry in ipairs(standIn(model, false)) do
			table.insert(lower, entry)
		end
	end
	-- NO THROAT PART. It used to be a black cylinder back past the hinge, and its end was a black disc
	-- forty studs across lying right in the mouth: from above, falling in, the one thing you saw was that
	-- circle, with the jaws round it in the dark. It was reported, rightly, as a circle that should not
	-- be there. The dark of the pit is throat enough.
	--
	-- A TONGUE along the lower jaw, wet, so there is something inside the mouth for the light to find.
	-- (The two-hundred-and-fiftieth pass: it was one ellipsoid 24 by 32 lying a stud OVER the hollow of the jaw's
	-- floor, and from above, falling in, it was a flat dark disc across the mouth, an egg from the side. Now two long
	-- lobes either side of a groove and a narrower tip, sunk into the hollow, in the gums' own red.)
	local tongues = {}
	-- (Both of those were made worse by the meshes lying back to front, MESH_TURN: the tongue stood in the air with no
	-- jaw under it.) { across, along (toward the tip is -), width, length share, thickness }.
	-- (One broad flat blade and a tip since the two-hundred-and-fifty-second pass: seen end-on from above, the two
	-- lobes with a lump at their root read as something else entirely.)
	for _, spec in ipairs({ { 0, 0, 14, 1.05, 2.4 }, { 0, -LENGTH * 0.2, 10, 0.55, 2.2 } }) do
		local lobe = Instance.new("Part")
		lobe.Name = "Tongue"
		lobe.Size = Vector3.new(spec[3], spec[5], LENGTH * 0.46 * spec[4])
		local lobeShape = Instance.new("SpecialMesh")
		lobeShape.MeshType = Enum.MeshType.Sphere
		lobeShape.Parent = lobe
		dress(lobe, Color3.fromRGB(150, 50, 58), 0.12)
		lobe.CastShadow = false
		lobe.Parent = model
		-- On the lower jaw's inner side (the lower jaw is the -Y one), in the hollow of its floor. It moves (Maw.set).
		local entry = { part = lobe, offset = CFrame.identity, base = CFrame.new(spec[1], -4.2, -LENGTH * 0.3 + spec[2]) }
		table.insert(lower, entry)
		table.insert(tongues, entry)
	end
	-- THE INNER ROWS (see INNER_ROWS), on the made jaws only: each fang's root sunk a stud into the roof (or floor) of the
	-- mouth where gen_maw.py's vault puts it, standing toward the other jaw and raked back down the throat. A few are
	-- missing, as in the outer rows.
	if meshes then
		for _, jaw in ipairs({ { INNER_ROWS.upper, 1, upper }, { INNER_ROWS.lower, -1, lower } }) do
			local spec, sign, list = jaw[1], jaw[2] :: number, jaw[3] :: { any }
			local s, r, count, length = spec[1], spec[2], spec[3], spec[4]
			for n = 1, count do
				if (n * 5 + count) % 7 ~= 0 then
					local th = -math.pi / 2 * 0.86 + math.pi * 0.86 * (n - 0.5) / count
					local cap = math.sqrt(1 - r * r)
					local back = 1 - r * math.cos(th)
					local roof = GUM_BAND * 0.2 + VAULT * cap * (0.5 + 0.5 * back)
					local root = Vector3.new(HALF_W * s * r * math.sin(th), sign * (roof + 1), -LENGTH * s * r * math.cos(th))
					local dir = Vector3.new(-0.15 * math.sin(th), -sign * math.cos(0.5), math.sin(0.5)).Unit
					local long = length * (0.75 + 0.5 * ((n * 3 + count) % 5) / 4)
					local fang = Instance.new("Part")
					fang.Name = "InnerFang"
					fang.Size = Vector3.new(0.7, long, 0.7)
					local spindle = Instance.new("SpecialMesh")
					spindle.MeshType = Enum.MeshType.Sphere
					spindle.Parent = fang
					dress(fang, BONE, 0.14)
					fang.CastShadow = false
					fang.Parent = model
					local across = (Vector3.xAxis - dir * dir.X).Unit
					table.insert(list, { part = fang, offset = CFrame.fromMatrix(root + dir * long / 2, across, dir) })
				end
			end
		end
	end
	-- THE UVULA, at the back of the roof of the mouth over the throat: a stalk and a heavy drop of flesh, hanging down
	-- into the gullet and swinging (Maw.set). It catches the red from below.
	local uvula = {}
	-- (Back over the throat, not the mouth: the shot from inside the mouth looking up at you is taken just in front
	-- of the hinge, and hung there it filled a third of that picture as a red ball on a stick.)
	local hang = CFrame.fromMatrix(Vector3.new(0, VAULT, 1.5), Vector3.xAxis, Vector3.new(0, 0.35, -0.94).Unit)
	for _, spec in ipairs({ { Vector3.new(0.8, 4, 0.8), 1.9 }, { Vector3.new(1.8, 2.4, 1.8), 4.5 } }) do
		local flesh = Instance.new("Part")
		flesh.Name = "Uvula"
		flesh.Size = spec[1] :: Vector3
		local blob = Instance.new("SpecialMesh")
		blob.MeshType = Enum.MeshType.Sphere
		blob.Parent = flesh
		dress(flesh, GUM_RED, 0.12)
		flesh.CastShadow = false
		flesh.Parent = model
		local entry = { part = flesh, offset = hang * CFrame.new(0, -(spec[2] :: number), 0), base = hang, swing = spec[2] :: number }
		table.insert(upper, entry)
		table.insert(uvula, entry)
	end
	-- THE RINGS DOWN ITS THROAT (see RINGS): a roll of gum per fang slot, long enough round to meet the next, deep
	-- enough to meet the ring behind, and a fang standing out of each. No shadows from them, so the red down the
	-- throat still comes up through them.
	local throat: { Ring } = {}
	for k, spec in ipairs(RINGS) do
		local rx, ry, count = spec[2], spec[3], spec[4]
		local round = math.pi * (3 * (rx + ry) - math.sqrt((3 * rx + ry) * (rx + 3 * ry)))
		for n = 1, count do
			local angle = (n - 0.5 + 0.5 * (k % 2)) / count * math.pi * 2
			local gum = Instance.new("Part")
			gum.Name = "ThroatGum"
			gum.Size = Vector3.new(round / count * 1.7, 2.8, 7.2)
			local roll = Instance.new("SpecialMesh")
			roll.MeshType = Enum.MeshType.Sphere
			roll.Parent = gum
			dress(gum, GUM_RED, 0.1)
			gum.CastShadow = false
			gum.Parent = model
			table.insert(throat, { part = gum, ring = k, angle = angle, long = 0 })
			local long = spec[5] * (0.8 + 0.4 * ((n * 7 + k * 3) % 5) / 4)
			local fang = Instance.new("Part")
			fang.Name = "ThroatFang"
			fang.Size = Vector3.new(0.8, long, 0.8)
			local spindle = Instance.new("SpecialMesh")
			spindle.MeshType = Enum.MeshType.Sphere
			spindle.Parent = fang
			dress(fang, BONE, 0.14)
			fang.CastShadow = false
			fang.Parent = model
			table.insert(throat, { part = fang, ring = k, angle = angle, long = long })
		end
	end
	local function lamp(name: string, at: CFrame): Part
		local host = Instance.new("Part")
		host.Name = name
		host.Size = Vector3.new(1, 1, 1)
		dress(host, FLESH, 0)
		host.Transparency = 1
		host.CastShadow = false
		host.CFrame = at
		host.Parent = model
		return host
	end
	-- THE GLOW INSIDE IT, between the jaws above the hinge: the colour of something that lives without
	-- the sun, a sick acid green, never steady (Maw.light). It lights the teeth from within, which is what
	-- makes them read as teeth in the dark, and it reaches the whole length of the jaws.
	-- LIT FROM INSIDE ONLY. The lights threw no shadows, so they shone straight through the jaws onto their OUTSIDE,
	-- and from above the mouth was a glowing orange ball (it was reported as a pumpkin). With shadows, the outside
	-- stays dark and only the inside of the mouth, the gums and the teeth, catch the light.
	local deep = lamp("Deep", hinge * CFrame.new(0, 0, -8))
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(190, 255, 110)
	glow.Brightness = 0
	-- (Reaching the teeth's tips and not the one hanging over them: at 60 it washed your face out white, as the test of
	-- the hundred-and-twenty-fourth pass showed.)
	glow.Range = 46
	glow.Shadows = true
	glow.Parent = deep
	-- AND RED DOWN ITS THROAT, past the hinge: the gullet is lit from inside like a lamp through meat.
	local gullet = Instance.new("PointLight")
	gullet.Color = Color3.fromRGB(255, 56, 40)
	gullet.Brightness = 0
	gullet.Range = 40
	gullet.Shadows = true
	gullet.Parent = lamp("Gullet", hinge * CFrame.new(0, 0, 6))
	-- ITS BREATH, coming up out of the throat when it opens: warm, wet, slow (Maw.breathe).
	local breath = Instance.new("ParticleEmitter")
	breath.Texture = "rbxasset://textures/particles/smoke_main.dds"
	breath.Color = ColorSequence.new(Color3.fromRGB(120, 132, 108), Color3.fromRGB(70, 76, 66))
	breath.LightEmission = 0
	breath.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 22) })
	breath.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.88), NumberSequenceKeypoint.new(0.5, 0.92),
		NumberSequenceKeypoint.new(1, 1) })
	breath.Lifetime = NumberRange.new(2.2, 3.6)
	breath.Speed = NumberRange.new(9, 16)
	breath.SpreadAngle = Vector2.new(22, 22)
	breath.Drag = 0.8
	breath.RotSpeed = NumberRange.new(-20, 20)
	-- The lamp's front (-Z) is the way the mouth opens.
	breath.EmissionDirection = Enum.NormalId.Front
	breath.Rate = 0
	breath.Parent = deep
	-- DROOL off the roof of the mouth while it breathes: thick drops that fall, lit only by its own light.
	local palate = Instance.new("Part")
	palate.Name = "Palate"
	palate.Size = Vector3.new(HALF_W * 1.1, 0.5, LENGTH * 0.6)
	dress(palate, FLESH, 0)
	palate.Transparency = 1
	palate.CastShadow = false
	palate.Parent = model
	table.insert(upper, { part = palate, offset = CFrame.new(0, 1.5, -LENGTH * 0.42) })
	local drool = Instance.new("ParticleEmitter")
	drool.Texture = "rbxasset://textures/particles/smoke_main.dds"
	drool.Color = ColorSequence.new(Color3.fromRGB(172, 178, 150))
	drool.LightInfluence = 1
	drool.LightEmission = 0
	drool.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.3) })
	drool.Squash = NumberSequence.new(1.6)
	drool.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.6) })
	drool.Lifetime = NumberRange.new(1.0, 1.6)
	drool.Speed = NumberRange.new(0.5, 2)
	drool.Acceleration = Vector3.new(0, -40, 0)
	drool.EmissionDirection = Enum.NormalId.Bottom
	drool.Rate = 0
	drool.Parent = palate
	-- SALIVA between the jaws: strands from the roof of the mouth to its floor, sagging, which stretch as it
	-- opens and the longest snap. Nothing says a living thing as quickly. Each is two pieces, to its sag.
	local strands: { Strand } = {}
	-- (Ten since the two-hundred-and-fifty-first pass, from the hinge out to the lips; six read as a few threads.)
	for k, spec in ipairs({ { -0.55, 0.36 }, { 0.32, 0.46 }, { -0.18, 0.55 }, { 0.6, 0.62 }, { -0.42, 0.7 }, { 0.12, 0.78 },
		{ 0.45, 0.24 }, { -0.7, 0.5 }, { 0.75, 0.84 }, { -0.25, 0.9 } }) do
		local function piece(): BasePart
			local part = Instance.new("Part")
			part.Name = "Saliva"
			part.Size = Vector3.new(0.4, 0.4, 1)
			dress(part, Color3.fromRGB(150, 160, 132), 0.12)
			part.Transparency = 0.35
			part.CastShadow = false
			part.Parent = model
			return part
		end
		local x, z = spec[1] * HALF_W, spec[2] * LENGTH
		table.insert(strands, { near = piece(), far = piece(), top = CFrame.new(x, 1.2, -z),
			bottom = CFrame.new(x * 0.92, -1.2, -z * (0.96 + 0.02 * k)), snaps = 14 + 3 * (k % 3) })
	end
	-- AND A COLD LIGHT FROM ABOVE THE MOUTH, pointed down into it, so the tips of the teeth catch it
	-- against the dark as you fall past them.
	-- (The hinge's +Z is back down into the throat, so the lamp's Back face points down into the mouth.)
	local over = lamp("Above", hinge * CFrame.new(0, 0, -LENGTH * 2.2))
	local rim = Instance.new("SpotLight")
	rim.Color = Color3.fromRGB(214, 226, 236)
	rim.Brightness = 0
	rim.Range = 140
	rim.Angle = 45
	rim.Face = Enum.NormalId.Back
	rim.Shadows = true
	rim.Parent = over
	-- A SLIGHT GLOW OF ITS OWN (2026-10-18, from your fourth test: "maybe you could make the monster have a slight glow
	-- as well"). Lit only from inside, its outside was nothing in the dark and the mouth read as a light, not a thing.
	-- Three faint lamps of its own colour, cold and sickly, over the upper jaw, under the lower and out past its lips,
	-- with no shadows so they reach its outside: the shape of it, wet, just there. Never the warm light through the jaws
	-- that once made it a pumpkin, and out with the rest of its light until it comes (Maw.light).
	local aura: { PointLight } = {}
	for _, at in ipairs({ CFrame.new(0, 20, -LENGTH * 0.55), CFrame.new(0, -18, -LENGTH * 0.5), CFrame.new(0, 2, -LENGTH * 1.25) }) do
		local faint = Instance.new("PointLight")
		faint.Color = Color3.fromRGB(120, 210, 180)
		faint.Brightness = 0
		faint.Range = 46
		faint.Shadows = false
		faint.Parent = lamp("Aura", hinge * at)
		table.insert(aura, faint)
	end
	model.Parent = parent
	local built: Built = { model = model, hinge = hinge, upper = upper, lower = lower, glow = glow, rim = rim, meshes = meshes,
		gullet = gullet, aura = aura, strands = strands, breath = breath, throat = throat, tongue = tongues,
		drool = drool, uvula = uvula, grind = 0, hungry = 0, reaching = 0 }
	Maw.set(built, 0.05, 0.05)
	return built
end

-- The jaws open by `upperAngle` and `lowerAngle` (radians; 0 is shut).
function Maw.set(built: Built, upperAngle: number, lowerAngle: number)
	built.upperAngle, built.lowerAngle = upperAngle, lowerAngle
	local clock = os.clock()
	local dt = math.clamp(clock - (built.clockAt or clock), 0, 0.1)
	built.clockAt = clock
	local hungry, reaching = built.hungry, built.reaching
	-- The tongue never lies still: it rolls and shifts along the floor of the mouth, faster the hungrier it is; and
	-- reaching, it lifts off the floor from its root toward what is coming down into it, its tip searching.
	local fast = 1 + 1.5 * hungry
	local roll = CFrame.new(0.8 * math.sin(clock * 1.1 * fast), 0.4 * math.sin(clock * 1.7 * fast), 0)
		* CFrame.Angles(0.05 * math.sin(clock * 1.3 * fast), 0.1 * math.sin(clock * 0.8 * fast), 0.08 * math.sin(clock * 0.9 * fast))
	local root = CFrame.new(0, -4.2, -2)
	local lift = root * CFrame.Angles(REACH_LIFT * reaching + 0.08 * reaching * math.sin(clock * 6), 0.12 * reaching
		* math.sin(clock * 3.3), 0) * root:Inverse()
	for _, lobe in ipairs(built.tongue) do
		lobe.offset = lift * roll * lobe.base
	end
	-- The uvula swings, a slow heavy pendulum, harder when it is hungry.
	for _, piece in ipairs(built.uvula) do
		local a = (0.12 + 0.2 * hungry) * math.sin(clock * (1.6 + hungry))
		local b = (0.08 + 0.15 * hungry) * math.sin(clock * 1.1 + 0.7)
		piece.offset = piece.base * CFrame.Angles(a, 0, b) * CFrame.new(0, -piece.swing, 0)
	end
	-- The rings down its throat grind, each against the next, and squeeze in a wave that runs down it: harder and
	-- faster as it comes for you (Maw.hunger). The grind is added up frame by frame, so speeding it never jumps.
	built.grind += dt * GRIND * (1 + (HUNGRY_GRIND - 1) * hungry)
	local squeezeBy = SQUEEZE * (1 + (HUNGRY_SQUEEZE - 1) * hungry)
	for _, piece in ipairs(built.throat) do
		local spec = RINGS[piece.ring]
		local squeeze = 1 - squeezeBy * (0.5 + 0.5 * math.sin(clock * (2.2 + 3 * hungry) - piece.ring * 0.9))
		local rx, ry = spec[2] * squeeze, spec[3] * squeeze
		local th = piece.angle + built.grind * (if piece.ring % 2 == 0 then 1 else -1)
		local outward = Vector3.new(math.sin(th) / rx, math.cos(th) / ry, 0).Unit
		local round = Vector3.new(outward.Y, -outward.X, 0)
		local at = Vector3.new(rx * math.sin(th), ry * math.cos(th), spec[1])
		if piece.long == 0 then
			piece.part.CFrame = built.hinge * CFrame.fromMatrix(at, round, outward)
		else
			-- Leaning in toward the middle and down the throat, from just inside the gum.
			local lean = -outward * math.cos(FANG_LEAN) + Vector3.zAxis * math.sin(FANG_LEAN)
			piece.part.CFrame = built.hinge * CFrame.fromMatrix(at - outward * 1.2 + lean * piece.long / 2, round, lean)
		end
	end
	local up = built.hinge * CFrame.Angles(upperAngle, 0, 0)
	for _, entry in ipairs(built.upper) do
		entry.part.CFrame = up * entry.offset
	end
	local down = built.hinge * CFrame.Angles(-lowerAngle, 0, 0)
	for _, entry in ipairs(built.lower) do
		entry.part.CFrame = down * entry.offset
	end
	-- The saliva, stretched between them: thinner the further it is pulled, sagging toward the throat, and
	-- gone once it is pulled past what it holds.
	for _, strand in ipairs(built.strands) do
		local a = (up * strand.top).Position
		local b = (down * strand.bottom).Position
		local span = (b - a).Magnitude
		local snapped = span > strand.snaps
		-- (The hinge's +Z is back down into the throat.)
		local sag = a:Lerp(b, 0.5) + built.hinge:VectorToWorldSpace(Vector3.zAxis) * math.clamp(span * 0.18, 0.5, 4)
		local thick = math.clamp(0.7 - span / 60, 0.14, 0.7)
		for _, pair in ipairs({ { strand.near, a, sag }, { strand.far, sag, b } }) do
			local part, from, to = pair[1] :: BasePart, pair[2] :: Vector3, pair[3] :: Vector3
			part.Transparency = if snapped then 1 else 0.35
			part.Size = Vector3.new(thick, thick, math.max(0.2, (to - from).Magnitude + thick * 0.5))
			part.CFrame = CFrame.lookAt(from:Lerp(to, 0.5), to)
		end
	end
end

-- How lit it is: 0 is the dark, 1 is as much as it ever shows. With `clock` (seconds), the light inside it is
-- never steady: it swells and sinks like breath, and every so often it catches and dips, as if something moved
-- across it. Uncanny rather than bright: an acid glow, red down the throat, one cold light from above.
function Maw.light(built: Built, amount: number, clock: number?)
	local pulse, dip, throb = 1, 1, 1
	if clock then
		pulse = 0.8 + 0.2 * math.sin(clock * 1.9) * math.sin(clock * 0.7 + 1)
		dip = if math.noise(clock * 3.1, 0.5) > 0.38 then 0.4 else 1
		throb = 0.65 + 0.35 * math.abs(math.sin(clock * 2.6))
	end
	-- (Brighter since the hundred-and-twenty-fourth pass, from your test, "I don't understand what is going on still": it
	-- was a dark shape with a red smear under it. Now its gums are red and its teeth white in its own light.)
	built.glow.Brightness = 3.4 * amount * pulse * dip
	built.gullet.Brightness = 3.2 * amount * throb
	built.rim.Brightness = 2.2 * amount
	for _, faint in ipairs(built.aura) do
		faint.Brightness = 0.7 * amount * pulse
	end
end

-- The whole mouth moved to a new `hinge` (the lunge up out of the dark): every part of it carried there, and the
-- jaws set again at the angles they were at.
function Maw.place(built: Built, hinge: CFrame)
	local move = hinge * built.hinge:Inverse()
	for _, item in ipairs(built.model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.CFrame = move * item.CFrame
		end
	end
	built.hinge = hinge
	Maw.set(built, built.upperAngle or 0.05, built.lowerAngle or 0.05)
end

-- Its breath coming up out of the throat: `rate` puffs a second, 0 for none.
function Maw.breathe(built: Built, rate: number)
	built.breath.Rate = rate
	if built.drool then
		built.drool.Rate = rate * 1.2
	end
end

-- How hungry it is, 0 to 1: the rings down its throat churn, the tongue and the uvula move faster (Maw.set).
function Maw.hunger(built: Built, amount: number)
	built.hungry = math.clamp(amount, 0, 1)
end

-- How far the tongue reaches up off the floor of the mouth toward what is falling into it, 0 to 1 (Maw.set).
function Maw.reach(built: Built, amount: number)
	built.reaching = math.clamp(amount, 0, 1)
end

-- A frame for the hinge that puts the mouth's opening toward `opens`, the jaws parting along `side`.
function Maw.facing(at: Vector3, opens: Vector3, side: Vector3): CFrame
	local back = -opens.Unit
	local y = (side - back * side:Dot(back)).Unit
	return CFrame.fromMatrix(at, y:Cross(back), y, back)
end

function Maw.destroy(built: Built?)
	if built and built.model.Parent then
		built.model:Destroy()
	end
end

Maw.STAMP = "31b25c99"
return Maw
