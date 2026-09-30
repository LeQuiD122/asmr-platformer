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

export type Built = { model: Model, hinge: CFrame, upper: { { part: BasePart, offset: CFrame } },
	lower: { { part: BasePart, offset: CFrame } }, glow: PointLight, rim: SpotLight, meshes: boolean }

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
	dress(tongue, Color3.fromRGB(96, 30, 38), 0.18)
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
	-- the sun. It lights the teeth from within, which is what makes them read as teeth in the dark.
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(150, 255, 206)
	glow.Brightness = 0
	glow.Range = 70
	glow.Shadows = false
	glow.Parent = lamp("Deep", hinge * CFrame.new(0, 0, -16))
	-- AND A COLD LIGHT FROM ABOVE THE MOUTH, pointed down into it, so the tips of the teeth catch it
	-- against the dark as you fall past them.
	-- (The hinge's +Z is back down into the throat, so the lamp's Back face points down into the mouth.)
	local over = lamp("Above", hinge * CFrame.new(0, 0, -LENGTH * 2.2))
	local rim = Instance.new("SpotLight")
	rim.Color = Color3.fromRGB(214, 226, 236)
	rim.Brightness = 0
	rim.Range = 180
	rim.Angle = 70
	rim.Face = Enum.NormalId.Back
	rim.Shadows = true
	rim.Parent = over
	model.Parent = parent
	local built: Built = { model = model, hinge = hinge, upper = upper, lower = lower, glow = glow, rim = rim, meshes = meshes }
	Maw.set(built, 0.05, 0.05)
	return built
end

-- The jaws open by `upperAngle` and `lowerAngle` (radians; 0 is shut).
function Maw.set(built: Built, upperAngle: number, lowerAngle: number)
	local up = built.hinge * CFrame.Angles(upperAngle, 0, 0)
	for _, entry in ipairs(built.upper) do
		entry.part.CFrame = up * entry.offset
	end
	local down = built.hinge * CFrame.Angles(-lowerAngle, 0, 0)
	for _, entry in ipairs(built.lower) do
		entry.part.CFrame = down * entry.offset
	end
end

-- How lit it is: 0 is the dark, 1 is as much as it ever shows.
function Maw.light(built: Built, amount: number)
	built.glow.Brightness = 2.2 * amount
	built.rim.Brightness = 2.4 * amount
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

return Maw
