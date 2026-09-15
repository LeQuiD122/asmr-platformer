--[[
	VETTING A FREE MODEL BEFORE IT GOES IN THE GAME.

	Paste into the Studio Command Bar with the imported model SELECTED, then press Enter.

	Free toolbox models are uploaded by anyone and reviewed by no one. The overwhelming
	majority are fine. The ones that are not fall into three groups, and only one of them is
	obvious once it is in your place:

	  1. SCRIPTS. A Script or LocalScript inside a decorative model has no legitimate reason to
	     be there, and this is how backdoored models work -- the script sits quiet, fetches code
	     from elsewhere later, and by then it is in your published game. This check treats ANY
	     script in a prop as a stop sign, because a prop does not need one.

	  2. WEIGHT. A "butter" model can be four hundred parts with eight 1024px textures. That
	     costs you nothing in Studio and costs every player on a phone quite a lot.

	  3. PROVENANCE. Nothing here can tell you whether the uploader made it. A model that is
	     visibly someone else's IP, or that is a re-upload of a paid asset, is a problem you
	     inherit the moment you publish.

	This reports 1 and 2. For 3, look at the thing and judge.
]]

local selection = game:GetService("Selection"):Get()
if #selection == 0 then
	warn("Select the imported model first, then run this again.")
	return
end

local scripts, parts, meshes, decals, unions = {}, 0, 0, 0, 0
local textures: { [string]: boolean } = {}
local tris = 0

for _, root in ipairs(selection) do
	local everything = root:GetDescendants()
	table.insert(everything, root)
	for _, item in ipairs(everything) do
		if item:IsA("LuaSourceContainer") then
			table.insert(scripts, item:GetFullName() .. "  (" .. item.ClassName .. ")")
		elseif item:IsA("MeshPart") then
			parts += 1
			meshes += 1
			if item.TextureID ~= "" then
				textures[item.TextureID] = true
			end
			-- No triangle count is exposed to Luau, so size is the only proxy available.
			tris += 1
		elseif item:IsA("UnionOperation") then
			parts += 1
			unions += 1
		elseif item:IsA("BasePart") then
			parts += 1
		elseif item:IsA("Decal") or item:IsA("Texture") then
			decals += 1
			textures[item.Texture] = true
		elseif item:IsA("SurfaceAppearance") then
			for _, map in ipairs({ item.ColorMap, item.NormalMap, item.RoughnessMap,
				item.MetalnessMap }) do
				if map ~= "" then
					textures[map] = true
				end
			end
		end
	end
end

local textureCount = 0
for _ in pairs(textures) do
	textureCount += 1
end

print(("--- %d selected: %d parts (%d mesh, %d union), %d decals, %d distinct textures"):format(
	#selection, parts, meshes, unions, decals, textureCount))

if #scripts > 0 then
	warn(("!!! %d SCRIPT(S) INSIDE. A decorative model has no reason to contain one. Read every "
		.. "line before you keep any of them, and if in doubt delete them -- a prop does not "
		.. "stop being a prop without its scripts."):format(#scripts))
	for _, where in ipairs(scripts) do
		warn("      " .. where)
	end
else
	print("    no scripts: clean on the only count that can hurt you later")
end

-- Thresholds are judgement, not law. They are set where a single decorative prop starts
-- costing more than the thing it is decorating.
if parts > 150 then
	warn(("    %d parts is heavy for one prop. Worth deleting the parts you cannot see before "
		.. "this goes anywhere near the lobby."):format(parts))
end
if unions > 0 then
	warn(("    %d union(s). Unions carry their own collision mesh and are the usual reason a "
		.. "free model tanks a frame rate; consider replacing them with MeshParts."):format(unions))
end
if textureCount > 6 then
	warn(("    %d distinct textures. Each is a separate download for every player who "
		.. "loads it."):format(textureCount))
end
