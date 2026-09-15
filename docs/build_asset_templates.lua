--[[
	BUILD TILE TEMPLATES FROM THE FREE-MODEL ASSET IDS.

	Paste into the Studio Command Bar, press Enter, then SAVE THE PLACE.

	=== What the dump told us ===

	Every keycap in BOTH keyboard models is the same mesh, 8837613273, at 3 x 1.368 x 3. The
	lava version is that mesh with texture 13076266447 over a near-black base; the keycap pack
	is the same mesh with no texture and a colour per key. So "a lava keyboard" and "a purple
	keyboard" are not two models -- they are one mesh, one texture id, and a colour list. That
	is worth knowing because it means the variants cost nothing to add.

	Every Needoh is one mesh, 514528545, at 5 x 5 x 5, Material Glass, in two colours. A Needoh
	chunk is therefore a grid of that mesh, not a rig.

	The butter model looked at first like squash frames -- seven `cubey` parts at similar sizes,
	the way an animation strip looks. Reading the dump properly says otherwise: the seven differ
	in WIDTH, from 2.6 to 6.0, while all standing about 4 tall. Those are not stages of one block
	being squashed, they are pieces of one stick that has been cut up. So they go in, as cut
	butter on a butter platform, and the wrapped stick goes in with them.

	=== Why a script rather than doing it by hand ===

	MeshId cannot be assigned at runtime, so these have to exist as saved templates -- and
	building fourteen of them by hand through the Properties panel is fourteen chances to typo
	an asset id. This writes them once, correctly, and is safe to re-run: it replaces what it made
	before rather than stacking duplicates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")

local KEYCAP_MESH = "rbxassetid://8837613273"
local LAVA_TEXTURE = "rbxassetid://13076266447"
local NEEDOH_MESH = "rbxassetid://514528545"

-- Straight from the dump. Named for what they are rather than for their hex, because a palette
-- entry called "Ice" survives being read six months from now and one called "34,211,238" does not.
local KEYCAP_SETS = {
	Dusk = { Color3.fromRGB(61, 21, 133), Color3.fromRGB(170, 0, 170),
		Color3.fromRGB(0, 16, 176), Color3.fromRGB(13, 105, 172) },
	Mint = { Color3.fromRGB(52, 211, 153), Color3.fromRGB(34, 211, 238) },
	Lava = { Color3.fromRGB(59, 67, 70) },
}

-- The butter model's seven `cubey` meshes. They look like squash frames laid out in a row and
-- they are not: the dump gives seven different SIZES, 2.6 to 6.0 wide and all about 4 tall.
-- That is a stick that has been cut up, so they are named for what they are -- cut pieces --
-- and only the four most distinct are kept. Seven near-identical blocks on one platform reads
-- as repetition; four reads as a chopping board.
local BUTTER_CUTS = {
	Butter_Cut_1 = { "rbxassetid://99156354394532", Vector3.new(5.99, 4.27, 5.85) },
	Butter_Cut_2 = { "rbxassetid://103496837250070", Vector3.new(3.77, 4.12, 6.75) },
	Butter_Cut_3 = { "rbxassetid://106401239061901", Vector3.new(2.62, 4.36, 5.88) },
	Butter_Cut_4 = { "rbxassetid://84960551046688", Vector3.new(6.01, 3.96, 4.73) },
}

-- The wrapped stick, which is the only one of the eight that is not butter-coloured glass:
-- it has a printed wrapper texture and a Fabric surface, because a wrapper is paper.
local BUTTER_STICK = "rbxassetid://91283904228198"
local BUTTER_WRAP = "rbxassetid://129079834115239"

local NEEDOH_COLOURS = {
	Blossom = Color3.fromRGB(255, 152, 220),
	Deep = Color3.fromRGB(6, 114, 255),
}

local assets = ReplicatedStorage:FindFirstChild("Assets")
if not assets then
	warn("No ReplicatedStorage.Assets -- run this in the place that has the chunk meshes.")
	return
end
local folder = assets:FindFirstChild("TileMeshes")
if not folder then
	warn("No Assets.TileMeshes -- run this in the place that has the chunk meshes.")
	return
end

-- MeshId is read-only at runtime, so the template has to be CREATED with the mesh already on
-- it. InsertService:CreateMeshPartAsync is the only way to do that from a script; it yields,
-- and it throws on a bad id rather than returning nil, hence the pcall on each one.
local function template(name: string, meshId: string, size: Vector3, colour: Color3,
	material: Enum.Material, textureId: string?)
	local existing = folder:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local ok, part = pcall(function()
		return InsertService:CreateMeshPartAsync(meshId,
			Enum.CollisionFidelity.Box, Enum.RenderFidelity.Automatic)
	end)
	if not ok or not part then
		warn(("could not build %s from %s: %s"):format(name, meshId, tostring(part)))
		return
	end

	part.Name = name
	part.Size = size
	part.Color = colour
	part.Material = material
	part.Anchored = true
	part.CanCollide = true
	if textureId then
		part.TextureID = textureId
	end
	part.Parent = folder
	print(("  built %-26s %s"):format(name, meshId))
end

print("Keycaps -- one mesh, many colours:")
for setName, colours in pairs(KEYCAP_SETS) do
	for index, colour in ipairs(colours) do
		template(("Keycap_%s_%d"):format(setName, index), KEYCAP_MESH,
			Vector3.new(3, 1.368, 3), colour, Enum.Material.SmoothPlastic,
			if setName == "Lava" then LAVA_TEXTURE else nil)
	end
end

print("Needohs -- Glass, because that is what makes them read as squishy rather than solid:")
for name, colour in pairs(NEEDOH_COLOURS) do
	template("Needoh_" .. name, NEEDOH_MESH, Vector3.new(5, 5, 5), colour, Enum.Material.Glass)
end

print("Butter -- cut pieces in glass, and the wrapped stick in fabric:")
for name, spec in pairs(BUTTER_CUTS) do
	template(name, spec[1] :: string, spec[2] :: Vector3,
		Color3.fromRGB(248, 217, 109), Enum.Material.Glass)
end
template("Butter_Stick", BUTTER_STICK, Vector3.new(5.35, 4.16, 17.32),
	Color3.fromRGB(255, 176, 0), Enum.Material.Fabric, BUTTER_WRAP)

print("Done. Save the place, then Play: ChunkProps dresses the five new chunks.")
print("")
print("NOTE: the free models' own scripts are NOT copied here, on purpose. ButterWaxSquish is")
print("already running in your place -- twice -- and every keycap in the lava model carries two")
print("more. That is 80-plus scripts for one platform, and none of them have been read.")
