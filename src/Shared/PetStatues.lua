--!strict
-- ReplicatedStorage/Shared/PetStatues.lua
-- THE PALS, MADE MONUMENTS (the two-hundred-and-sixty-fourth pass, from your note: "bring these little pets as shapes
-- in the sky that kind of resemble them, floating like the clouds are in the air, and maybe as some sort of marble
-- structure somewhere on the levels, on all of them, marble where there's pools").
--
-- The six pals (Assets.Cosmetics.Pal_*, the shop's Pals tab) made big, in whatever each place is made of:
--   * "marble"  white veined marble (SkyMarble), on a stepped pedestal: where there is a pool, and spouting into it.
--   * "sand"    a sand sculpture on City Shore's beach, on a heap of sand.
--   * "topiary" clipped hedge in Hill House's garden, on a hedge plinth.
--   * "stone"   mossy drowned stone in the Sunken City, rising out of the water on a tall pedestal.
--   * "cloud"   white and soft, a cloud in the climb's sky, puffs round its feet.
-- Every statue stands on its pedestal and the pedestal on the ground it is given; a cloud is a cloud.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PetStatues = {}

PetStatues.PALS = { "Pal_Needoh", "Pal_Slime", "Pal_Jelly", "Pal_Bee", "Pal_Cloud", "Pal_Lava" }
PetStatues.NAMES = { Pal_Needoh = "SQUISH", Pal_Slime = "GLOOP", Pal_Jelly = "WIBBLE", Pal_Bee = "BUMBLE",
	Pal_Cloud = "NIMBUS", Pal_Lava = "CINDER" }

local FINISH: { [string]: { material: Enum.Material, colour: Color3, variant: string? } } = {
	marble = { material = Enum.Material.Marble, colour = Color3.fromRGB(242, 240, 236), variant = "SkyMarble" },
	sand = { material = Enum.Material.Sand, colour = Color3.fromRGB(230, 208, 162) },
	topiary = { material = Enum.Material.LeafyGrass, colour = Color3.fromRGB(86, 138, 72) },
	-- Limestone, not Rock: Rock is dressed in the coursed sea-wall stone (MaterialAppearance.SURFACES) and the pal came out a brick igloo.
	stone = { material = Enum.Material.Limestone, colour = Color3.fromRGB(128, 142, 128) },
	cloud = { material = Enum.Material.SmoothPlastic, colour = Color3.fromRGB(250, 251, 255) },
}
local PEDESTAL: { [string]: { material: Enum.Material, colour: Color3, trim: Color3, variant: string? } } = {
	marble = { material = Enum.Material.Marble, colour = Color3.fromRGB(232, 228, 222), trim = Color3.fromRGB(206, 168, 88),
		variant = "SkyMarble" },
	sand = { material = Enum.Material.Sand, colour = Color3.fromRGB(220, 196, 150), trim = Color3.fromRGB(200, 176, 132) },
	topiary = { material = Enum.Material.LeafyGrass, colour = Color3.fromRGB(70, 118, 60), trim = Color3.fromRGB(140, 112, 80) },
	stone = { material = Enum.Material.Rock, colour = Color3.fromRGB(98, 108, 102), trim = Color3.fromRGB(70, 104, 84) },
}

local function finish(part: BasePart, look: { material: Enum.Material, colour: Color3, variant: string? })
	part.Material = look.material
	part.Color = look.colour
	if look.variant then
		pcall(function()
			if game:GetService("MaterialService"):FindFirstChild(look.variant :: string, true) then
				part.MaterialVariant = look.variant :: string
			end
		end)
	end
end

local function block(parent: Instance, name: string, size: Vector3, cf: CFrame, solid: boolean): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = solid
	p.CanQuery = solid
	p.CanTouch = false
	p.Size = size
	p.CFrame = cf
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A pal's mesh, its own colours taken off (the statue is all one stuff), `height` tall, its base at `base` (its front, -Z,
-- the way `base` looks). Nil where the pal is not imported.
function PetStatues.pet(parent: Instance, name: string, base: CFrame, height: number, kind: string): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Cosmetics")
	local found = folder and folder:FindFirstChild(name)
	local template = if found and found:IsA("BasePart") then found elseif found then found:FindFirstChildWhichIsA("BasePart", true)
		else nil
	if not template then
		return nil
	end
	local pet = template:Clone() :: BasePart
	pet.Name = "PetStatue_" .. name
	for _, child in ipairs(pet:GetChildren()) do
		if child:IsA("SurfaceAppearance") or child:IsA("Decal") or child:IsA("Texture") or child:IsA("Light")
			or child:IsA("ParticleEmitter") then
			child:Destroy()
		end
	end
	if pet:IsA("MeshPart") then
		(pet :: MeshPart).TextureID = ""
	end
	pet.Size = template.Size * (height / template.Size.Y)
	pet.CFrame = base * CFrame.new(0, height / 2, 0)
	pet.Anchored = true
	pet.CanCollide = kind ~= "cloud"
	pet.CanQuery = kind ~= "cloud"
	pet.CanTouch = false
	pet.CastShadow = kind ~= "cloud"
	finish(pet, FINISH[kind] or FINISH.marble)
	pet.Parent = parent
	return pet
end

-- A stepped pedestal at `base` (its foot), `width` across and `height` tall: a plinth, a die with a trim band and a name
-- plate, a cornice. Returns where its top is.
function PetStatues.pedestal(parent: Instance, base: CFrame, width: number, height: number, kind: string, label: string?): CFrame
	local look = PEDESTAL[kind] or PEDESTAL.marble
	local foot = height * 0.16
	local cap = height * 0.14
	local die = height - foot - cap
	local plinth = block(parent, "PedestalFoot", Vector3.new(width * 1.25, foot, width * 1.25), base * CFrame.new(0, foot / 2, 0), true)
	finish(plinth, look)
	local body = block(parent, "PedestalDie", Vector3.new(width, die, width), base * CFrame.new(0, foot + die / 2, 0), true)
	finish(body, look)
	local band = block(parent, "PedestalBand", Vector3.new(width + 0.1, math.min(0.5, die * 0.08), width + 0.1),
		base * CFrame.new(0, foot + die * 0.82, 0), false)
	band.Material = if kind == "marble" then Enum.Material.Metal else look.material
	band.Color = look.trim
	local top = block(parent, "PedestalCap", Vector3.new(width * 1.15, cap, width * 1.15), base * CFrame.new(0, height - cap / 2, 0), true)
	finish(top, look)
	if label and kind ~= "topiary" and kind ~= "sand" then
		local plate = block(parent, "PedestalPlate", Vector3.new(width * 0.6, die * 0.22, 0.12),
			base * CFrame.new(0, foot + die * 0.45, -width / 2 - 0.06), false)
		plate.Material = Enum.Material.Metal
		plate.Color = look.trim
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = plate
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.TextScaled = true
		text.Text = label
		text.TextColor3 = Color3.fromRGB(58, 44, 30)
		pcall(function()
			local Style = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Style")) :: any
			text.FontFace = Style.FONT.heading
		end)
		text.Parent = gui
	end
	return base * CFrame.new(0, height, 0)
end

-- A whole statue: pedestal and pal, and, for a fountain, water arcing from the pal's front. Returns the model.
function PetStatues.statue(parent: Instance, name: string, base: CFrame, petHeight: number, pedestalHeight: number,
	kind: string, fountain: boolean?, water: Color3?): Model
	local model = Instance.new("Model")
	model.Name = "PetStatue"
	model.Parent = parent
	local width = petHeight * 0.75
	local top = PetStatues.pedestal(model, base, width, pedestalHeight, kind, PetStatues.NAMES[name])
	local pet = PetStatues.pet(model, name, top, petHeight, kind)
	if fountain and pet then
		-- THE JET (seen in play: as particles it was a faint glitter, whatever their size). A rope of water, a Beam curving
		-- from the pal's front up and over and down into the pool a pal's length out, the pool being three studs under the
		-- pedestal's top wherever a fountain stands; and a soft splash where it lands.
		local spout = block(model, "PetSpout", Vector3.new(0.3, 0.3, 0.3),
			top * CFrame.new(0, petHeight * 0.45, -pet.Size.Z * 0.45), false)
		spout.Transparency = 1
		local front = top.LookVector
		local landing = top.Position + front * (pet.Size.Z * 0.5 + petHeight * 1.1) - Vector3.new(0, 3, 0)
		local reach = (landing - spout.Position).Magnitude
		local from = Instance.new("Attachment")
		from.Name = "PetJetFrom"
		from.Parent = spout
		from.WorldCFrame = CFrame.fromMatrix(spout.Position, (front + Vector3.new(0, 0.75, 0)).Unit,
			Vector3.new(0, 1, 0):Cross(front).Unit:Cross((front + Vector3.new(0, 0.75, 0)).Unit))
		local into = Instance.new("Attachment")
		into.Name = "PetJetInto"
		into.Parent = spout
		into.WorldCFrame = CFrame.fromMatrix(landing, Vector3.new(0, -1, 0), front)
		local jet = Instance.new("Beam")
		jet.Name = "PetJet"
		jet.Attachment0 = from
		jet.Attachment1 = into
		jet.CurveSize0 = reach * 0.55
		jet.CurveSize1 = reach * 0.3
		jet.FaceCamera = true
		jet.Segments = 24
		jet.Width0 = petHeight * 0.05
		jet.Width1 = petHeight * 0.08
		jet.Color = ColorSequence.new(water or Color3.fromRGB(226, 246, 250))
		jet.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.85, 0.3),
			NumberSequenceKeypoint.new(1, 0.6) })
		jet.LightEmission = 0.2
		jet.LightInfluence = 0.8
		jet.Parent = spout
		local splashAt = Instance.new("Attachment")
		splashAt.Name = "PetSplash"
		splashAt.Parent = spout
		splashAt.WorldCFrame = CFrame.new(landing)
		local splash = Instance.new("ParticleEmitter")
		splash.Name = "PetStream"
		splash.Texture = "rbxasset://textures/particles/smoke_main.dds"
		splash.Color = ColorSequence.new(Color3.fromRGB(236, 248, 252))
		splash.LightEmission = 0.15
		splash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, petHeight * 0.05),
			NumberSequenceKeypoint.new(1, petHeight * 0.14) })
		splash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		splash.Lifetime = NumberRange.new(0.5, 0.8)
		splash.Rate = 24
		splash.Speed = NumberRange.new(2, 4)
		splash.SpreadAngle = Vector2.new(55, 55)
		splash.Acceleration = Vector3.new(0, -6, 0)
		splash.EmissionDirection = Enum.NormalId.Top
		splash.Parent = splashAt
	end
	return model
end

-- A pal as a cloud: white and soft, `height` tall, its middle at `at`, with a few puffs round its feet and flanks so it
-- reads as a cloud shaped like it rather than as a white statue in the sky.
function PetStatues.cloud(parent: Instance, name: string, at: CFrame, height: number, seed: number): Model
	local model = Instance.new("Model")
	model.Name = "PetCloud"
	model.Parent = parent
	local pet = PetStatues.pet(model, name, at * CFrame.new(0, -height / 2, 0), height, "cloud")
	local rng = Random.new(seed)
	local wide = if pet then math.max(pet.Size.X, pet.Size.Z) else height
	-- A flat bank of wide puffs under it, overlapping, that it sits in. (Pass 265, seen in play: "Ball" parts are always
	-- round whatever their size, so the bank was a string of loose balls. Now each puff is a sphere MESH, which takes the
	-- part's own size: flat, wide, lying on one level and overlapping all round under the pal.)
	local count = 11
	for k = 1, count do
		local a = (k / count) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local reach = wide * rng:NextNumber(0.28, 0.46)
		local s = wide * rng:NextNumber(0.42, 0.6)
		local puff = block(model, "PetCloudPuff", Vector3.new(s * 1.5, s * 0.42, s),
			at * CFrame.new(math.cos(a) * reach, -height * rng:NextNumber(0.4, 0.47), math.sin(a) * reach * 0.75)
				* CFrame.Angles(0, -a + rng:NextNumber(-0.3, 0.3), 0),
			false)
		local round = Instance.new("SpecialMesh")
		round.MeshType = Enum.MeshType.Sphere
		round.Parent = puff
		puff.Material = Enum.Material.SmoothPlastic
		puff.Color = if k % 3 == 0 then Color3.fromRGB(226, 232, 246) else Color3.fromRGB(240, 244, 252)
		puff.CastShadow = false
	end
	-- And its middle, one broad low puff under the whole of it.
	local base = block(model, "PetCloudPuff", Vector3.new(wide * 1.1, height * 0.2, wide * 0.8), at * CFrame.new(0, -height * 0.46, 0),
		false)
	local baseRound = Instance.new("SpecialMesh")
	baseRound.MeshType = Enum.MeshType.Sphere
	baseRound.Parent = base
	base.Material = Enum.Material.SmoothPlastic
	base.Color = Color3.fromRGB(236, 240, 250)
	base.CastShadow = false
	-- Wisps off its edges, so its outline is soft.
	local wisps = Instance.new("ParticleEmitter")
	wisps.Name = "PetCloudWisps"
	wisps.Texture = "rbxasset://textures/particles/smoke_main.dds"
	wisps.Color = ColorSequence.new(Color3.fromRGB(246, 248, 255))
	wisps.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, wide * 0.18), NumberSequenceKeypoint.new(1, wide * 0.32) })
	wisps.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.72),
		NumberSequenceKeypoint.new(1, 1) })
	wisps.Lifetime = NumberRange.new(6, 9)
	wisps.Rate = 1.2
	wisps.Speed = NumberRange.new(0.5, 1.5)
	wisps.SpreadAngle = Vector2.new(180, 30)
	wisps.LightInfluence = 0.6
	wisps.Shape = Enum.ParticleEmitterShape.Box
	wisps.Parent = base
	return model
end

PetStatues.STAMP = "d221dcfe"
return PetStatues
