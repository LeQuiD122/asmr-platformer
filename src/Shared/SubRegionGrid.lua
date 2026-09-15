--!strict
-- ReplicatedStorage/Shared/SubRegionGrid.lua
-- Pure utility module. No dependencies. Used by server (DeformationService)
-- and client (DeformationRenderer). Grid math must stay identical on both
-- sides or client-predicted tween targets will drift from server truth.

-- DEVIATION FROM GDD v1.1: the doc pins cell target 2.5 studs and a 2-4 clamp,
-- sized for 6x4 platforms. Platforms are now roughly 4x that area, and a 2-4
-- clamp on a 16x20 slab yields 4x5 stud cells -- bigger than the character, so
-- they stop reading as "sub-regions" and start reading as four quadrants. Target
-- and clamp are raised to keep cells near character scale (~3 studs).
local CELL_SIZE_TARGET = 3.2 -- studs
local MIN_CELLS, MAX_CELLS = 2, 6

-- Visible seam between adjacent tiles. Wide enough to read as discrete cells
-- at play-camera distance, which is what sells the surface as constructed
-- rather than as one painted slab.
local TILE_GAP = 0.15

local SubRegionGrid = {}

function SubRegionGrid.compute(sizeX: number, sizeZ: number)
	local cols = math.clamp(math.floor(sizeX / CELL_SIZE_TARGET + 0.5), MIN_CELLS, MAX_CELLS)
	local rows = math.clamp(math.floor(sizeZ / CELL_SIZE_TARGET + 0.5), MIN_CELLS, MAX_CELLS)
	return {
		platformSizeX = sizeX,
		platformSizeZ = sizeZ,
		cols = cols,
		rows = rows,
		cellSizeX = sizeX / cols,
		cellSizeZ = sizeZ / rows,
	}
end

-- Root part XZ position -> active (col, row), or nil if off-platform.
-- Centroid-based, deterministic, no dead zones.
function SubRegionGrid.getActiveRegion(rootPos: Vector3, platformCFrame: CFrame, gridConfig)
	local localPos = platformCFrame:PointToObjectSpace(rootPos)
	local halfX = gridConfig.platformSizeX / 2
	local halfZ = gridConfig.platformSizeZ / 2
	if math.abs(localPos.X) > halfX or math.abs(localPos.Z) > halfZ then
		return nil
	end
	local col = math.floor((localPos.X + halfX) / gridConfig.cellSizeX) + 1
	local row = math.floor((localPos.Z + halfZ) / gridConfig.cellSizeZ) + 1
	col = math.clamp(col, 1, gridConfig.cols)
	row = math.clamp(row, 1, gridConfig.rows)
	return col, row
end

-- (col, row) -> world CFrame + size, for tween targeting and for placing
-- the actual sub-region trigger parts during chunk construction.
-- `gap` overrides the default seam width. Continuous materials (honey, slime) use
-- 0 so their edge-matched tile meshes can actually meet; granular and breakable
-- materials keep the default, where the seam is wanted.
function SubRegionGrid.getRegionCFrame(platformCFrame: CFrame, gridConfig, col: number, row: number, gap: number?)
	local halfX = gridConfig.platformSizeX / 2
	local halfZ = gridConfig.platformSizeZ / 2
	local centerX = -halfX + (col - 0.5) * gridConfig.cellSizeX
	local centerZ = -halfZ + (row - 0.5) * gridConfig.cellSizeZ
	local worldPos = platformCFrame:PointToWorldSpace(Vector3.new(centerX, 0, centerZ))
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = platformCFrame:GetComponents()
	local worldCF = CFrame.new(worldPos.X, worldPos.Y, worldPos.Z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	local seam = gap or TILE_GAP
	local cellSize = Vector3.new(gridConfig.cellSizeX - seam, 1, gridConfig.cellSizeZ - seam)
	return worldCF, cellSize
end

-- Builds a "col,row" lookup key. Used consistently by server + client
-- so DeformationState dictionaries agree on keys.
function SubRegionGrid.key(col: number, row: number): string
	return col .. "," .. row
end

return SubRegionGrid
