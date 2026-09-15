--!strict
-- ServerScriptService/Services/ChunkService.lua
-- Maintains the chunk template pool (ServerStorage/ChunkTemplates) and
-- spawns/destroys chunk instances into Workspace.Levels.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local ChunkService = {}

local templatesFolder = ServerStorage:WaitForChild("ChunkTemplates")

local function ensureLevelsFolder(): Folder
	local existing = Workspace:FindFirstChild("Levels")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Levels"
	folder.Parent = Workspace
	return folder
end

-- Clones a chunk template and places it so its ENTRY EDGE meets the given
-- world position: entry Z at targetZ, walkable entry surface at targetY.
--
-- Aligning on the template's published EntryZ/EntrySurfaceY attributes rather
-- than on a bounding box is what keeps sloped and stepped chunks flush against
-- flat ones. A bounding box's min-Y is the lowest corner of the geometry, which
-- for a pitched ramp is not the height you walk on at its entry.
-- Places a chunk so its ENTRY POINT lands on `at`, with the chunk turned to face along
-- that CFrame.
--
-- This used to take a bare (z, y) pair and move the clone by a Vector3 delta, which meant
-- every chunk in the game was axis-aligned and the route could only ever run dead ahead
-- along +Z. A spiral is not a layout problem on top of that -- it is impossible, because
-- nothing here could turn a chunk.
--
-- Chunks are authored running along +Z with their entry at (0, EntrySurfaceY, EntryZ), and
-- their pivot is wherever the bounding box happens to be. So the placement is: put the
-- entry at `at`, adopt `at`'s rotation, and carry the pivot along by the offset between
-- the two -- which one CFrame multiply does, including rotating that offset.
function ChunkService.spawnChunk(chunkId: string, at: CFrame): Model?
	local template = templatesFolder:FindFirstChild(chunkId)
	if not template then
		warn("ChunkService: no template found for " .. chunkId .. " -- run ChunkBuilder first")
		return nil
	end

	local clone = template:Clone()
	local entryZ = (clone:GetAttribute("EntryZ") :: number?) or 0
	local entrySurfaceY = (clone:GetAttribute("EntrySurfaceY") :: number?) or 0

	local pivot = clone:GetPivot()
	local entry = Vector3.new(0, entrySurfaceY, entryZ)
	clone:PivotTo(at * CFrame.new(pivot.Position - entry))

	clone.Parent = ensureLevelsFolder()
	return clone
end

function ChunkService.destroyChunk(model: Model)
	if model and model.Parent then
		model:Destroy()
	end
end

function ChunkService.clearLevel()
	local levelsFolder = Workspace:FindFirstChild("Levels")
	if levelsFolder then
		for _, child in ipairs(levelsFolder:GetChildren()) do
			child:Destroy()
		end
	end
end

-- Total Z length and entry-to-exit rise of a chunk, used by LevelService to
-- advance its placement cursor.
--
-- This used to read PrimaryPart.Size.Z, which is only the FIRST platform of a
-- chunk. Every composite chunk (gaps, landings, stairs, flanks) is longer than
-- its primary slab, so the cursor under-advanced and each composite was buried
-- inside the chunk placed after it.
function ChunkService.getChunkMetrics(chunkId: string): (number, number)
	local template = templatesFolder:FindFirstChild(chunkId)
	if not template then
		return 12, 0
	end
	local length = (template:GetAttribute("Length") :: number?) or template:GetExtentsSize().Z
	local rise = (template:GetAttribute("Rise") :: number?) or 0
	return length, rise
end

return ChunkService
