-- HARROW BAY'S SURFACES, MADE IN ONE GO (the hundred-and-sixty-ninth and seventieth passes).
--
-- Every MaterialVariant the game asks for, under MaterialService: named, on the right material, at the right size. A
-- script in the game cannot make these (their maps are Studio's to set), but Studio's own Command Bar can. Paste the whole
-- of this file into the Command Bar (View, Command Bar) and press Enter, once. A variant already there is left as it is.
--
-- The maps: paste an image's number (the digits of its rbxassetid://) into MAPS below before you run it and it is set
-- too; a 0 leaves that map for you to set by hand (select the variant under MaterialService, then its ColorMap, NormalMap
-- and RoughnessMap in Properties). The files are in textures/, three to a surface (HANDOFF, Make the surfaces). A variant
-- already there keeps everything, and takes only the maps you give numbers to here.
local MAPS = {
	HarrowBoards = { Color = 0, Normal = 0, Roughness = 0 },
	HarrowTimber = { Color = 0, Normal = 0, Roughness = 0 },
	HarrowFlags = { Color = 0, Normal = 0, Roughness = 0 },
	HarrowStone = { Color = 0, Normal = 0, Roughness = 0 },
	HarrowMarble = { Color = 0, Normal = 0, Roughness = 0 },
	HarrowRender = { Color = 0, Normal = 0, Roughness = 0 },
	HarrowCast = { Color = 0, Normal = 0, Roughness = 0 },
	HarrowCanvas = { Color = 0, Normal = 0, Roughness = 0 },
	HarrowPaint = { Color = 0, Normal = 0, Roughness = 0 },
	Slab = { Color = 0, Normal = 0, Roughness = 0 },
	Concrete = { Color = 0, Normal = 0, Roughness = 0 },
	PoolTile = { Color = 0, Normal = 0, Roughness = 0 },
}

-- name, the material it shows on, studs a tile, and whose maps it wears.
local VARIANTS = {
	{ "HarrowBoards", Enum.Material.WoodPlanks, 8, "HarrowBoards" },
	{ "HarrowTimber", Enum.Material.Wood, 6, "HarrowTimber" },
	{ "HarrowFlags", Enum.Material.Slate, 12, "HarrowFlags" },
	{ "HarrowStone", Enum.Material.Rock, 10, "HarrowStone" },
	{ "HarrowMarble", Enum.Material.Marble, 16, "HarrowMarble" },
	{ "HarrowRender", Enum.Material.Plaster, 12, "HarrowRender" },
	{ "HarrowCast", Enum.Material.Concrete, 10, "HarrowCast" },
	{ "HarrowCanvas", Enum.Material.Fabric, 4, "HarrowCanvas" },
	{ "HarrowPaint", Enum.Material.Metal, 8, "HarrowPaint" },
	-- The stone under every chunk: one set of maps on the three materials the slabs are made of, under the names you
	-- gave them in Studio (MaterialAppearance's SlabVariants). Yours are kept; numbers in MAPS.Slab put the sharper maps on.
	{ "ConcreteMeshTile", Enum.Material.Concrete, 4, "Slab" },
	{ "PlasterMeshTile", Enum.Material.Plaster, 4, "Slab" },
	{ "SlateMeshTile", Enum.Material.Slate, 4, "Slab" },
	{ "ConcreteBackdrop", Enum.Material.Concrete, 16, "Concrete" },
	{ "PoolTileBackdrop", Enum.Material.Concrete, 6, "PoolTile" },
}

local MaterialService = game:GetService("MaterialService")
local made, kept, mapped = 0, 0, 0
for _, spec in ipairs(VARIANTS) do
	local name, base, studs, wears = spec[1], spec[2], spec[3], spec[4]
	local variant = MaterialService:FindFirstChild(name, true)
	if not (variant and variant:IsA("MaterialVariant")) then
		variant = Instance.new("MaterialVariant")
		variant.Name = name
		variant.BaseMaterial = base
		variant.StudsPerTile = studs
		variant.Parent = MaterialService
		made += 1
	else
		kept += 1
	end
	local ids = MAPS[wears]
	if ids then
		for kind, id in pairs(ids) do
			if id ~= 0 then
				(variant :: any)[kind .. "Map"] = "rbxassetid://" .. tostring(id)
				mapped += 1
			end
		end
	end
end
print(("Harrow Bay's surfaces: %d MaterialVariants made, %d already there, %d maps set. The rest of the maps by hand "
	.. "(HANDOFF, Make the surfaces)."):format(made, kept, mapped))
