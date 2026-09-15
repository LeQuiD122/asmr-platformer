--[[
	DUMP AN IMPORTED MODEL'S STRUCTURE, so it can be written against.

	Paste into the Studio Command Bar with the model SELECTED, press Enter, then copy the whole
	Output block back to me.

	=== Why this is needed ===

	A marketplace listing tells me a name, a creator and a type. It does not tell me what is
	inside, and everything I would write depends on what is inside: whether the Needohs are one
	MeshPart each or twenty welded parts decides whether a Needoh chunk is a mesh swap or a rig;
	whether the keycaps are separate parts with readable names decides whether the keyboard
	variants can reuse the existing Keyboard_Field builder or need a new one; whether the butter
	is a solid block or a shell with an interior decides what a butter mechanic can even do.

	So this prints the tree, the part sizes, the mesh and texture ids, and the material and
	colour of each distinct surface -- enough to write against without guessing.

	=== What it deliberately does NOT print ===

	Script SOURCE. Reading a free model's scripts is worth doing and it is worth doing by eye,
	in Studio, where you can see the whole file -- not pasted through a chat window where a long
	one gets truncated in the middle and the interesting part is the bit that got cut. This
	names them and their line counts; vet_free_model.lua is the one that flags them.
]]

local selection = game:GetService("Selection"):Get()
if #selection == 0 then
	warn("Select the imported model first, then run this again.")
	return
end

-- Deep trees from the toolbox are often deep for no reason -- a model wrapped in a model
-- wrapped in a folder -- and printing all of it buries the part that matters.
local MAX_DEPTH = 5
local MAX_LINES = 220
local lines = 0

local function describe(item: Instance): string
	if item:IsA("MeshPart") then
		return ("MeshPart size=%s mesh=%s texture=%s material=%s colour=%d,%d,%d"):format(
			tostring(item.Size), item.MeshId, item.TextureID, item.Material.Name,
			math.floor(item.Color.R * 255), math.floor(item.Color.G * 255),
			math.floor(item.Color.B * 255))
	elseif item:IsA("BasePart") then
		local shape = if item:IsA("Part") then item.Shape.Name else item.ClassName
		return ("%s %s size=%s material=%s colour=%d,%d,%d%s"):format(
			item.ClassName, shape, tostring(item.Size), item.Material.Name,
			math.floor(item.Color.R * 255), math.floor(item.Color.G * 255),
			math.floor(item.Color.B * 255),
			if item.Transparency > 0 then (" transparency=" .. item.Transparency) else "")
	elseif item:IsA("LuaSourceContainer") then
		local ok, source = pcall(function()
			return (item :: any).Source
		end)
		local count = 0
		if ok and typeof(source) == "string" then
			for _ in source:gmatch("\n") do
				count += 1
			end
		end
		return ("%s  << SCRIPT, %d lines -- read this in Studio before keeping it"):format(
			item.ClassName, count + 1)
	elseif item:IsA("Decal") or item:IsA("Texture") then
		return ("%s face=%s id=%s"):format(item.ClassName, item.Face.Name, item.Texture)
	elseif item:IsA("SurfaceAppearance") then
		return ("SurfaceAppearance colour=%s normal=%s rough=%s metal=%s"):format(
			item.ColorMap, item.NormalMap, item.RoughnessMap, item.MetalnessMap)
	elseif item:IsA("Weld") or item:IsA("Motor6D") then
		return ("%s %s -> %s"):format(item.ClassName,
			if item.Part0 then item.Part0.Name else "nil",
			if item.Part1 then item.Part1.Name else "nil")
	end
	return item.ClassName
end

local function walk(item: Instance, depth: number)
	if lines >= MAX_LINES then
		return
	end
	lines += 1
	print(("%s%s : %s"):format(string.rep("  ", depth), item.Name, describe(item)))
	if depth >= MAX_DEPTH then
		local kids = #item:GetChildren()
		if kids > 0 then
			print(("%s  ... %d more below, not shown"):format(string.rep("  ", depth), kids))
		end
		return
	end
	for _, child in ipairs(item:GetChildren()) do
		walk(child, depth + 1)
	end
end

for _, root in ipairs(selection) do
	print("=====================================================")
	local size = root:IsA("Model") and root:GetExtentsSize() or Vector3.zero
	print(("ROOT %s (%s)  extents=%s"):format(root.Name, root.ClassName, tostring(size)))
	walk(root, 0)
end

if lines >= MAX_LINES then
	warn(("truncated at %d lines. If the interesting part is missing, select a single child "
		.. "and run this on that instead."):format(MAX_LINES))
end
