--!strict
-- ReplicatedStorage/Shared/Types.lua
-- Central Luau type declarations shared across server and client.

export type ChunkCategory = "stable" | "pace" | "risk"

export type ChunkDefinition = {
	id: string,
	name: string,
	category: ChunkCategory,
	materials: { [string]: boolean },
	sizeX: number,
	sizeZ: number,
	connections: { string },
	tags: { string },
	containsSlime: boolean,
	containsRisk: boolean,
}

export type LevelDefinition = {
	levelId: number,
	name: string,
	description: string,
	minChunks: number,
	maxChunks: number,
	allowedChunkIds: { string },
	allowedMaterials: { string },
	parTime: number,
	baseSeed: number,
	templates: { { string } }, -- array of slot-token sequences, e.g. {"S","M1","M1","S",...}
}

export type Mode = "chill" | "hardcore"

export type PlayerSessionData = {
	mode: Mode,
	checkpointChunkIndex: number,
	checkpointPosition: Vector3,
	failStatePosition: Vector3,
	hardcoreTimer: number,
	checkpointBackward: Vector3,
	isAtStart: boolean,
	hasCompletedLevel: boolean,
}

export type SubRegionCellState = "pristine" | "deformed" | "decaying" | "exhausted"

export type SubRegionState = {
	state: SubRegionCellState,
	occupantCount: number,
	decayTimer: number,
	popCount: number,
}

export type DeformationState = {
	platform: BasePart,
	material: string?,
	subRegionStates: { [string]: SubRegionState }, -- key = "col,row"
}

-- Wire format of the DeformationUpdate RemoteEvent. Carries the sub-region
-- part itself; a GetFullName() path string cannot be resolved back to an
-- Instance on the client.
export type DeformationUpdatePayload = {
	part: BasePart,
	col: number,
	row: number,
	state: SubRegionCellState,
	material: string?,
}

export type GridConfig = {
	platformSizeX: number,
	platformSizeZ: number,
	cols: number,
	rows: number,
	cellSizeX: number,
	cellSizeZ: number,
}

return {}
