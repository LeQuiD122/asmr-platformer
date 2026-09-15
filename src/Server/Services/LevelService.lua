--!strict
-- ServerScriptService/Services/LevelService.lua
-- Orchestrates level generation on server start. Template-based assembly:
-- pick a pre-verified template, fill each slot with a random chunk whose
-- category matches and whose materials are all whitelisted.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ChunkDefinitions = require(Shared:WaitForChild("ChunkDefinitions"))
-- THE SHAPE OF A LEVEL THAT IS INSIDE A BUILDING. Required unconditionally rather than behind
-- the layout check: a require inside the placement loop is a yield inside the placement loop,
-- and a module that only loads for one level is a module nobody notices is broken.
local HallRoute = require(Shared:WaitForChild("HallRoute"))

local ChunkService = require(script.Parent:WaitForChild("ChunkService"))
local DeformationService = require(script.Parent:WaitForChild("DeformationService"))
local PlayerStateService = require(script.Parent:WaitForChild("PlayerStateService"))

local LevelService = {}

-- Walkable height of the first chunk's surface. Lifts the whole level clear of
-- the world origin so falls read as falls.
--
-- This used to claim it also made the kill plane reachable. It did not. The kill
-- plane is minSurfaceY - 40, which is about -16 -- BELOW a default baseplate at
-- y = 0 -- so anyone who fell off landed on the baseplate and stood there: no
-- death, no respawn, no checkpoint, no way back onto the level. See
-- clearBaseplate below, which is what actually makes the claim true.
local BASE_SURFACE_Y = 24

-- Roblox's default place ships an opaque 2048-stud slab at y = 0, and it breaks
-- two separate things here.
--
-- It catches every fall, as above. And because it is opaque and sits 700 studs
-- ABOVE the backdrop's sea, it hides the entire ocean: the grey grid people took
-- for the water was this, seen from on top of the level.
--
-- Destroyed at RUNTIME, so nothing is written back to the saved place -- stop the
-- session and the baseplate is still in the file. The default SpawnLocation goes
-- with it, because this service builds its own (`LevelStart`, under
-- workspace.Levels) and a leftover would drop players at the origin instead.
local function clearBaseplate()
	for _, name in ipairs({ "Baseplate", "SpawnLocation" }) do
		local item = workspace:FindFirstChild(name)
		if item and item:IsA("BasePart") then
			item:Destroy()
			print("LevelService: removed workspace." .. name
				.. " -- it caught falls before the kill plane and hid the backdrop")
		end
	end
end

-- === The level CLIMBS now ===
--
-- These used to average about -0.9 studs a step, deliberately: the note said a downward
-- bias stops a long level climbing away forever. That solved a problem the level did not
-- have and created one it did -- twelve chunks of gentle descent is a ramp, and a ramp is
-- the one shape that reads as neither flat ground nor a climb.
--
-- Biased UP now, averaging about +2.7. The ceiling is jump height, not taste: a default
-- jump clears roughly 6.4 studs of rise while covering 8.2 of distance, and it has to clear
-- CHUNK_GAP as well, so past +4 it stops being reliably jumpable. A zero is left in so the
-- climb has landings rather than being an unbroken staircase.
local STEP_CHOICES = { 3, 4, 3, 0, 4, 3, 2 }

-- EVERY chunk gains height, not just the stable landings.
--
-- Only stable chunks stepped before, which is roughly one slot in three -- so a twenty-chunk
-- level climbed on six of them and the other fourteen were level. Pace and risk chunks take
-- a smaller step now, which is what turns a series of flat runs joined by steps into a route
-- that is going somewhere.
local PACE_STEP_CHOICES = { 2, 3, 0, 2, 3, 1, 2 }

-- === The route is a HELIX ===
--
-- It ran dead straight, then along a gentle serpentine, and both were the same shape from
-- above: a line going away from you. A spiral is different in kind -- the level wraps around
-- a centre, so the part you are on and the part you climbed ten chunks ago are in view at
-- once, and the whole thing reads as one object rather than as a road.
--
-- THE RADIUS IS BOUNDED FROM BELOW, and by geometry rather than by taste. A chunk on the
-- inside of a curve travels less arc than its centre line does, so at a tight enough radius
-- consecutive chunks overlap at their inner edges. With chunks about 24 long, 20 wide and a
-- 5-stud gap, the inner edge gets (29 * (R - 10) / R) studs of arc to fit 24 studs of chunk
-- into -- which fails below R = 58. 90 leaves real margin and still wraps a 20-chunk level
-- almost exactly once round.
--
-- More turns means a longer level, not a tighter one: at this radius a full circuit is 565
-- studs, so Level 3 at 812 makes about one and a half.
local SPIRAL_RADIUS = 90

-- Chunks are islands, not a continuous walkway. Every chunk boundary is a jump.
-- 5 studs against an 8.2-stud reach leaves margin for a mistimed or slowed
-- takeoff, which matters because honey halves WalkSpeed and butter-wax
-- overshoots.
local CHUNK_GAP = 5

-- ===== TURNING A CORNER ON THE JUNCTION CHUNK =====
--
-- Where S2_Junction's arm is, read off its builder in ChunkBuilder: the arm is centred
-- JUNCTION_ARM_Z along the main run and its outer face is JUNCTION_ARM_REACH to the side.
-- Every corner in LevelService is these two numbers plus CHUNK_GAP, and check_halls compares
-- them against the builder so they cannot drift from the chunk they describe.
local JUNCTION_ARM_Z = 12
local JUNCTION_ARM_REACH = 24
local junctionWarned = false

-- ===== AND IF THERE IS NO JUNCTION: HOW FAR PAST THE PREVIOUS CHUNK TO TURN =====
--
-- The fallback only. The next chunk is laid ACROSS the path, reaching this far back along the
-- new direction so it sits in front of the player. Two sums decide whether that works, and
-- check_halls tests both against the ENTRY geometry ChunkBuilder actually produces:
--
--   CHUNK_GAP + CORNER_BAR must clear the widest reach at any chunk's entry, shelves
--   included, or the chunk laid across reaches back into the one before it.
--   CHUNK_GAP + CORNER_BAR minus half the narrowest entry must be under a jump.
--
-- At 9 that is 14 against a reach of 13.4 and an 8-stud jump onto the narrowest entry. It
-- works, narrowly, and that is why it is only the fallback: landing on a shaped chunk's SIDE
-- is not something any of the shapes were ever checked for.
local CORNER_BAR = 9

-- Slot token -> required chunk category. W1/O1-style tokens (specific-material
-- risk slots used in the GDD's per-template tables for readability) collapse
-- to "risk" here, same as R1/R2.
local function categoryForSlot(token: string): string
	if token == "S" then
		return "stable"
	elseif token:sub(1, 1) == "M" then
		return "pace"
	else
		return "risk" -- R1, R2, W1, O1, etc.
	end
end

local function chunkMaterialsAreWhitelisted(chunkDef, allowedMaterials: { string }): boolean
	local allowedSet = {}
	for _, m in ipairs(allowedMaterials) do
		allowedSet[m] = true
	end
	for matName in pairs(chunkDef.materials) do
		if not allowedSet[matName] then
			return false
		end
	end
	return true
end

local function pickChunkForSlot(token: string, level, rng: Random): string?
	local category = categoryForSlot(token)
	local candidates = {}
	for _, chunkId in ipairs(level.allowedChunkIds) do
		local def = ChunkDefinitions[chunkId]
		if def and def.category == category and chunkMaterialsAreWhitelisted(def, level.allowedMaterials) then
			table.insert(candidates, chunkId)
		end
	end
	if #candidates == 0 then
		warn(("LevelService: no eligible chunk for slot '%s' (category '%s') in level %d"):format(token, category, level.levelId))
		return nil
	end
	return candidates[rng:NextInteger(1, #candidates)]
end

-- Sequentially places chunks south-to-north along +Z, using each chunk's
-- Z footprint so adjacent chunks butt up cleanly.
-- `origin` is where this level's spiral is centred, and it defaults to the world origin so
-- every existing caller is unchanged.
--
-- It exists because the hub is a permanent room that has to coexist with a run, and later
-- because sub-project C needs more than one level to be placeable at once. Adding it now is
-- three lines; adding it after a hub has been built around a fixed position is not.
function LevelService.startLevel(level, players: { Player }, origin: Vector3?)
	local base = origin or Vector3.zero
	clearBaseplate()
	ChunkService.clearLevel()

	local jobIdHash = 0
	for i = 1, #game.JobId do
		jobIdHash += string.byte(game.JobId, i)
	end
	local rng = Random.new(level.baseSeed + jobIdHash)

	-- A level may declare an explicit chunk order instead of a slot template.
	-- Used by the dev sandbox so every material is guaranteed to appear.
	local fixedSequence = level.fixedSequence
	local authored = if fixedSequence then fixedSequence else level.templates[rng:NextInteger(1, #level.templates)]

	-- ===== HOW LONG THE RUN IS =====
	--
	-- THE SHORT / MEDIUM / LONG PADS HAVE NEVER DONE ANYTHING, on any level, since the lobby
	-- was built. HubService does its half correctly: it takes a scaled COPY of the level and
	-- writes minChunks and maxChunks onto it, 0.5x for short and 1.5x for long. This service
	-- then picked a template and walked it, and never read either field. Every run was the
	-- template's own length, and a vote for a short run produced the identical level.
	--
	-- It is invisible from the inside, which is why it survived: the run that arrives IS a
	-- plausible run, it is just not the one that was asked for.
	--
	-- The template is a rhythm of slot categories rather than a fixed list, so a different
	-- length is the same rhythm continued or cut short. Cycling keeps the pattern the author
	-- wrote -- stable landings where they put them -- at any count.
	--
	-- The sandbox is exempt. Its fixedSequence exists so that every material appears exactly
	-- once, and trimming it would silently drop materials from the one place they are all
	-- meant to be checked.
	local template = authored
	if not fixedSequence then
		local low = level.minChunks or #authored
		local high = math.max(low, level.maxChunks or low)
		local wanted = math.max(1, if high > low then rng:NextInteger(low, high) else low)
		if wanted ~= #authored then
			template = {}
			for index = 1, wanted do
				table.insert(template, authored[(index - 1) % #authored + 1])
			end
		end
	end

	-- Arc travelled so far, in radians about the centre. Chunks advance by their own
	-- length, so a long chunk turns further than a short one and the spacing stays even.
	-- Which shape this level's route is. Read once rather than per chunk: a level cannot
	-- change its mind halfway along, and reading it in the loop invites exactly that.
	--
	-- "line" is kept as an alias for "path" rather than deleted. Nothing in the project uses
	-- it any more, but a level definition carrying it would otherwise silently fall back to a
	-- spiral, which is the exact failure this field was added to prevent.
	local pathLayout = level.layout == "path" or level.layout == "line"
	-- FLAT, and this is a SEPARATE decision from the shape.
	--
	-- The straight-line layout still climbed. Only the chunk's own internal rise was being
	-- suppressed; the per-chunk STEP was not, and that is the larger of the two -- forty-four
	-- chunks at an average of two and a half studs is a hundred and ten studs of climb, in a
	-- building with an eighty-eight stud ceiling. The route went through the roof, which is
	-- why it still looked like a spiral going up even after it had been told to be a line.
	local flatLayout = pathLayout

	-- ===== THE PATH, AS IT IS ACTUALLY LAID =====
	--
	-- Where the current leg starts, which way it runs, how far along it the next chunk goes, and
	-- the length every finished leg turned out to be. The corridor is built from routeLegs
	-- afterwards, so these are not an estimate of the building: they ARE its plan.
	local legIndex = 1
	local legOrigin = Vector3.zero
	local legDir = Vector3.new(0, 0, 1)
	local legBase = 0
	local along = 0
	local routeLegs: { number } = {}
	local angle = 0
	local cursorY = BASE_SURFACE_Y
	local placed = CFrame.new()
	local placedChunks = {}

	for slotIndex, token in ipairs(template) do
		-- With a fixed sequence the entries ARE chunk ids, not slot tokens.
		local chunkId = if fixedSequence then token else pickChunkForSlot(token, level, rng)
		if not chunkId then
			continue
		end

		-- Elevation profile. Chunks that rise internally (ramp, stairs) declare it; on top
		-- of that every chunk takes a step, with the stable landings taking the bigger ones
		-- so the climb still has a rhythm rather than being one constant grade.
		--
		-- Capped by jump height, not by taste: past about +4 a gap stops being reliably
		-- clearable once CHUNK_GAP is spent as well.
		-- NOT ON A FLAT LAYOUT. See flatLayout above: this step is what put the indoor route
		-- through the ceiling, and suppressing the chunk's internal rise alone did not touch
		-- it.
		if slotIndex > 1 and not flatLayout then
			local isStable = ChunkDefinitions[chunkId] and ChunkDefinitions[chunkId].category == "stable"
			local steps = if isStable then STEP_CHOICES else PACE_STEP_CHOICES
			cursorY += steps[rng:NextInteger(1, #steps)]
		end

		local length, rise = ChunkService.getChunkMetrics(chunkId)

		-- ===== SPIRAL, OR A STRAIGHT LINE =====
		--
		-- A SPIRAL IS NOT THE ONLY SHAPE A RUN CAN BE, and assuming it was is what put the
		-- flooded halls' chunks inside their own walls: the halls are a building, the spiral
		-- climbs eighty studs through the middle of it, and nothing had told either of them
		-- about the other.
		--
		-- A line is the right shape for a level that is INSIDE something. It stays level, it
		-- goes one way, and the architecture round it can be a corridor of known width -- so
		-- the route and the room can be built to agree instead of hoping they miss.
		--
		-- The spiral remains the default and is untouched. `layout = "line"` is opt-in per
		-- level, and only the new one asks for it.
		local out, tangent
		if pathLayout then
			-- ===== FOLLOWING THE BUILDING, AND TURNING WHERE THE CHUNKS ARE =====
			--
			-- `angle` is distance travelled along the route here rather than an arc, so
			-- everything downstream that reads it still means "how far along".
			--
			-- THE CORNER USED TO BE AT A FIXED PLACE, and that one decision was behind two
			-- separate complaints. A leg was planned as four or five bays; chunks come in
			-- whatever lengths the template picks; so the last chunk before a corner ended a
			-- random distance short of it, and the shortfall had to go somewhere:
			--
			--   A SMALL ONE: the chunk after the corner started AT it, reaching back across the
			--   path, and the two chunks intersected. Honey through soap.
			--   A LARGE ONE: a gap up to thirty-nine studs, too far to jump, with a tiled
			--   landing laid in it that read as a stray platform in the middle of the run.
			--
			-- So the corner is not fixed any more: when this chunk would run past the leg's
			-- planned length, the corridor turns HERE -- and it turns on S2_Junction, the
			-- L-shaped stable chunk the kit already has for exactly this: a sixteen-by-twenty run
			-- with a sixteen-stud arm off its left side and a wedge in the inside corner.
			--
			-- WHY A JUNCTION RATHER THAN LAYING THE NEXT CHUNK ACROSS THE PATH. That was the
			-- first version of this fix and it has a flaw worth writing down. A chunk laid across
			-- the path is landed on from its SIDE, and nineteen chunks in this level's pool are
			-- shaped forms -- stars, rings, pebbles, hearts -- that are only guaranteed walkable
			-- from their entry face. The junction is entered and left through faces it was built
			-- with connections on, so every chunk either side of a corner is met face-first,
			-- across the same five-stud gap as everywhere else.
			--
			-- It turns either way, because it has three connections rather than two:
			--   LEFT:  in through the main run's south face, out through the arm.
			--   RIGHT: in through the arm, out through the main run's south face.
			-- Either way the corridor's corner lands inside the junction, at its local
			-- (0, 0, JUNCTION_ARM_Z). And being a stable chunk, it is a checkpoint -- which is
			-- exactly where one belongs.
			local plannedBays, plannedTurn = HallRoute.legPlan(legIndex)
			if along + length > plannedBays * HallRoute.BAY then
				local up = Vector3.new(0, 1, 0)
				local outDir = HallRoute.turn(legDir, plannedTurn)
				local turnsLeft = plannedTurn > 0
				local cornerAt = along + (if turnsLeft then JUNCTION_ARM_Z else JUNCTION_ARM_REACH)
				local corner = legOrigin + legDir * cornerAt
				-- A right turn is the same chunk ROTATED, never reflected: its arm faces back at
				-- the player and its main run's south face points the new way.
				local junctionAt = if turnsLeft
					then CFrame.fromMatrix(base + legOrigin + legDir * along
						+ Vector3.new(0, cursorY, 0), up:Cross(legDir), up, legDir)
					else CFrame.fromMatrix(base + corner + outDir * JUNCTION_ARM_Z
						+ Vector3.new(0, cursorY, 0), -legDir, up, -outDir)
				local junction = ChunkService.spawnChunk("S2_Junction", junctionAt)
				local nextAlong = 0
				if junction then
					for _, part in ipairs(junction:GetDescendants()) do
						if part:IsA("BasePart") and part:GetAttribute("Material") then
							DeformationService.registerPlatform(part)
						end
					end
					table.insert(placedChunks, {
						model = junction,
						index = slotIndex,
						chunkId = "S2_Junction",
						surfaceY = cursorY,
						startAngle = legBase + along,
						-- Facing the way the route LEAVES it, so a fall just after the corner
						-- recovers back onto the junction rather than back down the old leg.
						tangent = outDir,
					})
					nextAlong = (if turnsLeft then JUNCTION_ARM_REACH else JUNCTION_ARM_Z)
						+ CHUNK_GAP
				else
					-- NO JUNCTION TEMPLATE. Rather than leave a twenty-nine stud hole in the
					-- route, lay this chunk across the path; see CORNER_BAR for what that costs.
					if not junctionWarned then
						junctionWarned = true
						warn("LevelService: S2_Junction has no template, so corners are laying the "
							.. "next chunk across the path instead, and a shaped chunk landed on "
							.. "from its side may not be walkable. Re-run ChunkBuilder.")
					end
					cornerAt = along + CORNER_BAR
					nextAlong = -CORNER_BAR
				end
				table.insert(routeLegs, cornerAt)
				legOrigin += legDir * cornerAt
				legBase += cornerAt
				legDir = outDir
				legIndex += 1
				along = nextAlong
			end

			tangent = legDir
			out = Vector3.new(0, 0, 0)
			angle = legBase + along
			placed = CFrame.fromMatrix(
				base + legOrigin + legDir * along + Vector3.new(0, cursorY, 0),
				Vector3.new(0, 1, 0):Cross(legDir),
				Vector3.new(0, 1, 0),
				legDir
			)
		else
			-- Position on the circle, and the tangent to face along.
			--
			-- The chunk's +Z has to follow the tangent, which is why this is built from an
			-- explicit matrix rather than CFrame.lookAt: lookAt aims the LOOK vector, and a
			-- CFrame's look vector is its NEGATIVE z. Using it here would place every chunk
			-- backwards -- entry at the far end, exit at the near one.
			out = Vector3.new(math.cos(angle), 0, math.sin(angle))
			tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			placed = CFrame.fromMatrix(
				base + out * SPIRAL_RADIUS + Vector3.new(0, cursorY, 0),
				Vector3.new(0, 1, 0):Cross(tangent),
				Vector3.new(0, 1, 0),
				tangent
			)
		end

		local model = ChunkService.spawnChunk(chunkId, placed)
		if model then
			-- Every material-bearing slab in the chunk, not just the one named
			-- "Platform". Composite chunks carry their material on named
			-- sections (SandSection, HoneyLanding, SoapSection, Step2/Step3),
			-- and matching on the name alone left those inert.
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") and part:GetAttribute("Material") then
					DeformationService.registerPlatform(part)
				end
			end
			table.insert(placedChunks, {
				model = model,
				index = slotIndex,
				chunkId = chunkId,
				surfaceY = cursorY,
				-- The arc this chunk starts at, in radians. Was a Z coordinate, which no
				-- longer identifies a position on a route that wraps.
				startAngle = angle,
				-- WHICH WAY THIS CHUNK POINTS, stored rather than recomputed.
				--
				-- Bootstrap used to rebuild it from startAngle with sin and cos, which is only
				-- correct on the spiral -- on a route where `angle` is studs travelled,
				-- sin(1200) is a number with no meaning, and the fall-recovery direction it
				-- produced sent players sideways off the walkway. One field ends that: every
				-- layout records the direction it actually used.
				tangent = tangent,
			})
		end

		-- On a path the next chunk goes further along the current leg; on the spiral `angle` is
		-- arc, converted to radians.
		if pathLayout then
			along += length + CHUNK_GAP
			angle = legBase + along
		else
			angle += (length + CHUNK_GAP) / SPIRAL_RADIUS
		end
		-- A PATH STAYS LEVEL. The rise is what makes a spiral a climb, and a climb through a
		-- building with a ceiling puts the last chunk through the roof.
		cursorY += if flatLayout then 0 else rise
	end

	-- A LEVEL AUDIT, for the same reason ChunkBuilder has a rig audit.
	--
	-- Neither this service nor ChunkService prints anything on success, so a level that
	-- placed all thirteen chunks and a level that placed NONE produced identical logs --
	-- both silent. The warnings that exist ("no eligible chunk", "no template found") only
	-- fire on specific failures, so their absence proved nothing either way, and working
	-- out which had happened meant guessing from the geometry. One line ends that.
	if #placedChunks == 0 then
		warn(("LevelService: level %d placed NO chunks from %d slots. Check that ChunkBuilder ran "
			.. "and that ReplicatedStorage.Assets.Chunks is populated."):format(level.levelId, #template))
	elseif pathLayout then
		-- A DIFFERENT LINE FOR A PATH, because "degrees round" means nothing on one and the
		-- numbers that do mean something -- how far it went, how many corners it took -- are
		-- the ones the halls are then built to.
		print(("LevelService: level %d placed %d/%d chunks along %d studs of route, turning %d "
			.. "time(s) where the chunks turned, surface y %d")
			:format(level.levelId, #placedChunks, #template, math.floor(angle), legIndex - 1,
				cursorY))
	else
		print(("LevelService: level %d placed %d/%d chunks, %d degrees round, surface y %d to %d")
			:format(level.levelId, #placedChunks, #template,
				math.floor(math.deg(angle)), BASE_SURFACE_Y, cursorY))
	end

	local levelsFolder = game.Workspace.Levels

	-- Finish trigger spanning the end of the final chunk, at that chunk's
	-- height rather than a hardcoded Y.
	local finishPart = Instance.new("Part")
	finishPart.Name = "FinishLine"
	finishPart.Anchored = true
	finishPart.CanCollide = false
	finishPart.CanTouch = true
	finishPart.Transparency = 1
	finishPart.Size = Vector3.new(20, 10, 2)
	-- On the spiral, at the end of the last chunk placed, and turned to match it. `placed`
	-- still holds that chunk's entry CFrame, so walking forward along its own +Z by its
	-- length is where the route runs out.
	local finishLength = 0
	if #placedChunks > 0 then
		finishLength = select(1, ChunkService.getChunkMetrics(placedChunks[#placedChunks].chunkId))
	end
	finishPart.CFrame = placed * CFrame.new(0, 5, finishLength - 1)
	finishPart.Parent = levelsFolder

	-- The first chunk sits at angle 0, which is (SPIRAL_RADIUS, y, 0) rather than the
	-- origin -- the route wraps around a centre now and the centre is empty.
	--
	-- On a path every route starts at the origin heading +Z -- both HallRoute.build and
	-- fromLegs begin that way -- so eight studs along it IS eight studs up +Z.
	local startPosition = if pathLayout
		then base + Vector3.new(0, BASE_SURFACE_Y + 4, 8)
		else base + Vector3.new(SPIRAL_RADIUS, BASE_SURFACE_Y + 4, 8)

	-- Spawn on the level, not on the baseplate. Bootstrap also teleports on
	-- CharacterAdded, but a real SpawnLocation makes respawns land correctly
	-- without depending on that hook firing in time.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LevelStart"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(if pathLayout
		then base + Vector3.new(0, BASE_SURFACE_Y + 0.5, 8)
		else base + Vector3.new(SPIRAL_RADIUS, BASE_SURFACE_Y + 0.5, 8))
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = levelsFolder

	for _, player in ipairs(players) do
		PlayerStateService.init(player, startPosition)
	end

	-- Lowest walkable surface in the level, so the kill plane can sit a fixed
	-- distance below the actual geometry instead of at a hardcoded Y that the
	-- descending elevation profile could sink past.
	local minSurfaceY = BASE_SURFACE_Y
	for _, entry in ipairs(placedChunks) do
		if entry.surfaceY < minSurfaceY then
			minSurfaceY = entry.surfaceY
		end
	end

	-- THE LAST LEG ends at the last chunk's exit, not at the gap after it.
	if pathLayout then
		table.insert(routeLegs, math.max(1, along - CHUNK_GAP))
	end

	return {
		levelId = level.levelId,
		placedChunks = placedChunks,
		startPosition = startPosition,
		finishPart = finishPart,
		spawn = spawn,
		minSurfaceY = minSurfaceY,
		killY = minSurfaceY - 40,
		-- ===== WHAT THE BUILDING NEEDS TO KNOW =====
		--
		-- Only meaningful on a path layout, and nil everywhere else so a caller that forgets
		-- to check gets an obvious failure rather than a plausible wrong number.
		--
		-- The length is the one that matters. The halls are built to the distance the chunks
		-- ACTUALLY used, corners and all, so the far chamber lands where the route ends
		-- instead of somewhere an estimate put it.
		routeLength = if pathLayout then legBase + along - CHUNK_GAP else nil,
		routeSurfaceY = if pathLayout then cursorY else nil,
		-- How long each leg of the corridor actually came out, in order. FloodedHallsService
		-- builds from exactly this, which is why a corner cannot be anywhere but where the
		-- chunks turned.
		routeLegs = if pathLayout then routeLegs else nil,
		-- Where the route runs out, facing the way it was going. The flume mouth goes here.
		routeEnd = if pathLayout then placed * CFrame.new(0, 0, finishLength) else nil,
	}
end

-- TEARS A RUN DOWN so another can be built.
--
-- Thin on purpose: ChunkService.clearLevel already destroys every child of Workspace.Levels,
-- and the finish trigger and the level's SpawnLocation are both children of it, so they go
-- with the chunks. Anything that has to survive a run must not be parented there -- which is
-- why the hub is its own folder rather than a corner of this one.
--
-- Safe to call when no level exists and safe to call twice: clearLevel looks the folder up
-- with FindFirstChild and does nothing when it is absent. That matters because the return
-- path can fire from a finish and from a manual leave, and both can land in the same frame
-- when the last player finishes by walking out.
function LevelService.endLevel()
	ChunkService.clearLevel()
end

return LevelService
