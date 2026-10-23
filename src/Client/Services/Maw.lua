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
local FLESH = Color3.fromRGB(58, 16, 20)
local BONE = Color3.fromRGB(226, 218, 196)

export type Strand = { near: BasePart, far: BasePart, top: CFrame, bottom: CFrame, snaps: number }
export type Built = { model: Model, hinge: CFrame, upper: { { part: BasePart, offset: CFrame } },
	lower: { { part: BasePart, offset: CFrame } }, glow: PointLight, rim: SpotLight, meshes: boolean,
	gullet: PointLight, aura: { PointLight }, strands: { Strand }, breath: ParticleEmitter, upperAngle: number?,
	lowerAngle: number? }

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
		for _, spec in ipairs(parts) do
			local part = (template(spec[1] :: string) :: MeshPart):Clone()
			dress(part, spec[2] :: Color3, spec[3] :: number)
			part.Parent = model
			table.insert(spec[4] :: { any }, { part = part, offset = CFrame.identity })
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
	local tongue = Instance.new("Part")
	tongue.Name = "Tongue"
	tongue.Size = Vector3.new(HALF_W * 0.9, 5, LENGTH * 0.62)
	local tongueShape = Instance.new("SpecialMesh")
	tongueShape.MeshType = Enum.MeshType.Sphere
	tongueShape.Parent = tongue
	dress(tongue, Color3.fromRGB(70, 22, 28), 0.1)
	tongue.CastShadow = false
	tongue.Parent = model
	-- On the lower jaw's inner side (the lower jaw is the -Y one), running out from the hinge.
	table.insert(lower, { part = tongue, offset = CFrame.new(0, -1.5, -LENGTH * 0.34) })
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
	-- SALIVA between the jaws: strands from the roof of the mouth to its floor, sagging, which stretch as it
	-- opens and the longest snap. Nothing says a living thing as quickly. Each is two pieces, to its sag.
	local strands: { Strand } = {}
	for k, spec in ipairs({ { -0.55, 0.36 }, { 0.32, 0.46 }, { -0.18, 0.55 }, { 0.6, 0.62 }, { -0.42, 0.7 }, { 0.12, 0.78 } }) do
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
		gullet = gullet, aura = aura, strands = strands, breath = breath }
	Maw.set(built, 0.05, 0.05)
	return built
end

-- The jaws open by `upperAngle` and `lowerAngle` (radians; 0 is shut).
function Maw.set(built: Built, upperAngle: number, lowerAngle: number)
	built.upperAngle, built.lowerAngle = upperAngle, lowerAngle
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

Maw.STAMP = "17049ea6"
return Maw
