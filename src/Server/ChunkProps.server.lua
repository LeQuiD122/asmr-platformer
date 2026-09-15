--!strict
-- Dressing for chunk templates: tints and scattered props, applied after ChunkBuilder.
--
-- === Why this is a separate script and not part of ChunkBuilder ===
--
-- ChunkBuilder is 2900 lines that turn recipes into rigged, skinned, bone-weighted geometry,
-- and every one of the 56 templates depends on it being right. What the Needoh, keycap and
-- butter assets need is none of that: they are finished MeshParts that want placing on top of
-- a slab somebody else already built.
--
-- Bolting a prop system into the builder would mean touching the file every chunk in the game
-- comes out of, to add something no existing chunk uses. This runs afterwards, reads the
-- finished templates, and adds to them. If it fails, it fails alone.
--
-- === Why the props do not collide ===
--
-- The collision profile of a chunk is load-bearing: the plan checker measures entry and exit
-- faces, the deformation renderer finds bones by world position, and the fall recovery
-- raycasts onto the walking plane. A prop that collides changes all three. So these are
-- CanCollide false without exception -- they are things on the platform, not part of it.
--
-- === Idempotence ===
--
-- ChunkBuilder SKIPS templates that already exist, so on the second run of a session the
-- models arrive already decorated. Each one is tagged, and a tagged model is left alone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Straight from the free models, via the dump. One mesh id for every keycap and one for every
-- Needoh, which is why the palettes below are colour lists rather than asset lists.
local DRESSING: { [string]: any } = {
	-- ===== NEEDOH =====
	--
	-- On jello, because a Needoh IS a jello: a squishy translucent blob, and JelloSoda is the
	-- only material here that already reads that way underfoot. The props sit ON the slab and
	-- the slab is what deforms, so you get the look without a second deformation system.
	-- P20_NeedohField USED TO BE DRESSED HERE and deliberately is not any more. Scattering
	-- the free model's Needohs across a jello slab is what made the chunk read as "needoh
	-- stuff on top of soda" -- two materials in one platform, only one of which you could
	-- press into. The Needohs are the surface now, so there is nothing left to scatter.

	-- ===== KEYBOARD PALETTES =====
	--
	-- The same rigged Keyboard_Field mesh in three colourways. Nothing about the geometry
	-- changes -- one mesh, one rig, one recipe -- so a variant costs a Color3 and a line here.
	--
	-- Lava additionally carries the free model's own texture over a near-black base, which is
	-- exactly how the original does it: the heat is painted, not modelled.
	P21_KeyboardDusk = { tint = Color3.fromRGB(78, 46, 138) },
	P22_KeyboardMint = { tint = Color3.fromRGB(52, 190, 160) },
	-- NO TINT ANY MORE, only the texture. The dark grey was standing in for a material this
	-- chunk did not have; LavaKeys has a palette of its own and a heat effect that writes the
	-- key colour directly, so a tint here would be a third thing fighting the other two for
	-- the same property.
	P23_KeyboardLava = {
		texture = "rbxassetid://13076266447",
	},

	-- ===== BUTTER =====
	--
	-- The free model's seven `cubey` meshes are not squash frames, whatever they look like in
	-- a row: they are seven different SIZES, 2.6 to 6.0 wide and all about 4 tall. That is a
	-- stick that has been cut up, and cut butter is what goes on top of a butter platform.
	--
	-- The wrapped stick, cubey1, is 17.3 long -- longer than the slab is wide -- so it lies
	-- along the platform as its one large feature rather than being scattered.
	-- STRIPPED BACK TO NOTHING, and the entry is kept only to say so.
	--
	-- The cut pieces were flat-ish slabs standing at whatever angle the scatter gave them,
	-- and on a platform that already has a wax coating with a print on it they read as
	-- torn-off scraps of that coating rather than as butter -- "weird chunks of butter
	-- texture on top of the wax", exactly as reported.
	--
	-- The chunk does not need them. What makes it a butter chunk is the butter and the shell
	-- that cracks off it, both of which are the platform itself.
	-- The sticks take the wrapper print off the imported butter mesh. No props: the sticks
	-- ARE the chunk, and the wax coating over them is built by ChunkBuilder, not scattered
	-- here.
	P25_ButterStick = {
		textureFrom = "Butter_Stick",
	},

	P24_ButterBlocks = {
		props = {
			-- THE WRAPPED STICK USED TO LIE HERE and does not any more. P25 is a chunk made OF
			-- butter sticks now, so a stick lying on P24's slab of cut butter was the same
			-- object appearing twice in two different roles -- decoration on one platform and
			-- the platform itself on the next. The cuts stay; the whole stick belongs to the
			-- chunk that is about whole sticks.
		},
	},
}

local function propTemplate(name: string): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("TileMeshes")
	local found = folder and folder:FindFirstChild(name)
	if found and not found:IsA("BasePart") then
		found = found:FindFirstChildWhichIsA("BasePart", true)
	end
	return if found and found:IsA("BasePart") then found else nil
end

-- The top of the walkable surface, which is not the top of the bounding box: several slabs
-- are authored with the walking plane below their own highest point (the butter body sits a
-- shell-thickness under it, for one). GetBoundingBox is still the right answer for placing
-- decoration -- it is where the eye says the surface is.
local function surfaceTop(model: Model): (CFrame, Vector3)
	local pivot, size = model:GetBoundingBox()
	return pivot, size
end

local missing: { [string]: boolean } = {}

local function dress(model: Model, recipe: any)
	if model:GetAttribute("Dressed") then
		return
	end
	model:SetAttribute("Dressed", true)

	-- BORROWED FROM ANOTHER MESH, rather than pasted in as an asset id.
	--
	-- The generated butter sticks have UVs but no texture, so next to the imported butter --
	-- which carries the free model's wrapper print -- they came out blank. The print lives on
	-- an uploaded image whose id is not written down anywhere in this repo, and guessing one
	-- is not a thing that can be done.
	--
	-- It does not have to be. The imported mesh is sitting in Assets/TileMeshes with the id
	-- already on it, so this reads it off that mesh at run time. Nothing to look up, nothing
	-- to keep in sync, and it keeps working if the asset is ever re-uploaded.
	if recipe.textureFrom then
		local source = propTemplate(recipe.textureFrom)
		if source and source:IsA("MeshPart") and source.TextureID ~= "" then
			-- ONLY THE SKINNED VISUAL. Every shard of the wax coating is a MeshPart too, and
			-- printing "BUTTER" across a hundred loose flakes of wrapper is not the effect.
			for _, item in ipairs(model:GetDescendants()) do
				if item:IsA("MeshPart") and item.Name == "SkinnedVisual" then
					item.TextureID = source.TextureID
				end
			end
		elseif not missing[recipe.textureFrom] then
			missing[recipe.textureFrom] = true
			warn(("ChunkProps: %s has no TextureID to borrow, so %s stays unprinted. Import "
				.. "the free model's butter mesh under that name into Assets/TileMeshes.")
				:format(recipe.textureFrom, model.Name))
		end
	end

	-- TINT AND TEXTURE first: they apply to the slab that is already there.
	if recipe.tint or recipe.texture then
		for _, item in ipairs(model:GetDescendants()) do
			if item:IsA("MeshPart") then
				if recipe.tint then
					item.Color = recipe.tint
				end
				if recipe.texture then
					item.TextureID = recipe.texture
				end
			end
		end
	end

	if not recipe.props then
		return
	end

	local centre, size = surfaceTop(model)
	local top = centre.Position.Y + size.Y / 2
	-- Seeded from the chunk's own name, so a given chunk scatters the same way every build.
	-- A platform that rearranges itself between sessions is one players cannot learn.
	local rng = Random.new(#model.Name * 7919)

	for _, group in ipairs(recipe.props) do
		for index = 1, group.count do
			local meshName = group.meshes[1 + (index - 1) % #group.meshes]
			local template = propTemplate(meshName)
			if not template then
				if not missing[meshName] then
					missing[meshName] = true
					warn(("ChunkProps: %s is not in Assets/TileMeshes, so %s goes without it. "
						.. "Run docs/build_asset_templates.lua and save the place.")
						:format(meshName, model.Name))
				end
				continue
			end

			local prop = template:Clone()
			prop.Name = meshName
			prop.Anchored = true
			prop.CanCollide = false
			prop.CanTouch = false
			prop.CanQuery = false
			prop.Size = template.Size * group.scale

			local offsetX = if group.spread.X > 0
				then rng:NextNumber(-group.spread.X / 2, group.spread.X / 2)
				else 0
			local offsetZ = if group.spread.Y > 0
				then rng:NextNumber(-group.spread.Y / 2, group.spread.Y / 2)
				else 0
			local turn = group.fixedTurn or rng:NextNumber(0, math.pi * 2)

			prop.CFrame = CFrame.new(
				centre.Position.X + offsetX,
				top + prop.Size.Y / 2 - group.sink,
				centre.Position.Z + offsetZ) * CFrame.Angles(0, turn, 0)
			prop.Parent = model
		end
	end
end

-- BOTH FOLDERS. ChunkBuilder writes the template to ServerStorage and mirrors a visual copy
-- into ReplicatedStorage; decorating only one would give the server and the client two
-- different ideas of what a chunk looks like.
-- WAITS FOR CHUNKBUILDER, because there is nothing to dress until it has run.
--
-- ChunkTemplates does not exist in Edit mode -- it is created at Play, by ChunkBuilder, from
-- recipes. Run before that (or pasted into the Command Bar, which is Edit mode by definition)
-- this finds an empty world and reports "dressed 0", which is exactly what happened.
--
-- Script execution order between two server Scripts is not defined either, so waiting for the
-- folder to exist AND stop growing is the only reliable signal that the builder is finished.
-- Polling rather than an event because ChunkBuilder does not raise one, and adding a signal to
-- it would mean editing the file this script exists to avoid editing.
local function waitForTemplates(): Folder?
	local deadline = os.clock() + 30
	local folder = ServerStorage:FindFirstChild("ChunkTemplates")
	while os.clock() < deadline do
		folder = ServerStorage:FindFirstChild("ChunkTemplates")
		if folder and folder:IsA("Folder") and #folder:GetChildren() > 0 then
			-- Settled: two consecutive checks with the same count means the builder has
			-- stopped adding to it.
			local count = #folder:GetChildren()
			task.wait(0.35)
			if #folder:GetChildren() == count then
				return folder
			end
		end
		task.wait(0.2)
	end
	return if folder and folder:IsA("Folder") then folder else nil
end

local templates = waitForTemplates()
if not templates then
	warn("ChunkProps: ChunkTemplates never appeared, so nothing was dressed. This script "
		.. "belongs in ServerScriptService and only does anything at Play -- pasting it into "
		.. "the Command Bar runs it in Edit mode, where the templates do not exist yet.")
	return
end

local dressed = 0
for _, folderName in ipairs({ "ChunkTemplates" }) do
	local folder = ServerStorage:FindFirstChild(folderName)
	if folder then
		for chunkId, recipe in pairs(DRESSING) do
			local model = folder:FindFirstChild(chunkId)
			if model and model:IsA("Model") then
				dress(model, recipe)
				dressed += 1
			end
		end
	end
end

local assets = ReplicatedStorage:FindFirstChild("Assets")
local chunks = assets and assets:FindFirstChild("Chunks")
if chunks then
	for chunkId, recipe in pairs(DRESSING) do
		local model = chunks:FindFirstChild(chunkId)
		if model and model:IsA("Model") then
			dress(model, recipe)
		end
	end
end

print(("ChunkProps: dressed %d chunk template(s)"):format(dressed))
