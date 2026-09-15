--!strict
-- Shared/HallRoute.lua
-- THE ONE PLACE THAT KNOWS WHERE THE FLOODED HALLS GO.
--
-- === Why this file exists ===
--
-- Twice now the chunks have ended up inside the walls, and both times the cause was the same:
-- the ROUTE and the ROOM were laid out by two pieces of code that had never heard of each
-- other. First it was a spiral inside a maze. Then it was a straight line inside a straight
-- corridor, which agreed about direction and disagreed about everything else.
--
-- Agreement by coincidence does not survive an edit. So the shape of the level is written down
-- ONCE, here, and both sides ask this module rather than each other:
--
--   LevelService         asks where chunk N goes, and which way it faces.
--   FloodedHallsService  asks where the walls, the columns and the junctions go.
--
-- Neither can drift, because there is nothing to drift from.
--
-- === What the shape is ===
--
-- A corridor that turns. Not a spiral and not a straight run: a building has corridors, and a
-- corridor that goes left means the route goes left too. That is the whole point of laying the
-- two out together -- the chunks stop being a road that happens to be indoors and become the
-- walkway this building was built around.
--
-- === Coordinates ===
--
-- Everything here is LOCAL to the level's origin and FLAT (y = 0). Height belongs to whatever
-- is being placed -- the walkway sits well above the flooded floor and the two want different
-- numbers -- so this module deals only in the plan.

local HallRoute = {}

-- One bay, in studs. This is FloodedHallsService's BAY (24 * SCALE) and the two must match:
-- legs are whole numbers of bays so that walls, columns and arches land on the bay grid all the
-- way to a corner instead of being cut off mid-bay.
HallRoute.BAY = 96

export type Leg = {
	-- Distance along the whole route at which this leg begins.
	startAt: number,
	length: number,
	-- Unit vector, flat. The direction of travel along this leg.
	dir: Vector3,
	from: Vector3,
	to: Vector3,
}

export type Corner = {
	-- Distance along the route at which the turn happens.
	at: number,
	point: Vector3,
	inDir: Vector3,
	outDir: Vector3,
	-- +1 for a left turn, -1 for a right one. Only used for naming things in logs.
	hand: number,
}

export type Route = {
	legs: { Leg },
	length: number,
}

-- ===== THE PLAN =====
--
-- Leg lengths in bays, and which way the corridor turns at the end of each one. It repeats, so
-- a longer level simply gets more of it.
--
-- LEFT, RIGHT, RIGHT, LEFT is a zig-zag rather than a spiral, and that is deliberate: two
-- turns the same way in a row start wrapping the level around a centre, which is the spiral
-- shape this level exists to not be. Alternating pairs keep the route pointed broadly one way
-- while still taking real corners, so the building stays a building you are crossing rather
-- than a coil you are climbing.
--
-- No leg is shorter than three bays. A corner every other bay is a hedge maze; the references
-- are long halls with something at the end of them, and the length of the leg is what gives
-- you the receding arches to look down.
-- NO LEG SHORTER THAN FOUR BAYS, and that is set by the junctions rather than by taste. A
-- junction is a square as wide as the corridor, so it eats a full corridor width off each end
-- of the legs either side of it -- 211 studs at the hall's width. A three-bay leg is 288, which
-- would leave seventy-seven studs of actual corridor between two junctions: a level made of
-- crossroads. Four and five bays leave one and a half to two and a half bays of hall, which is
-- enough to see arches recede down.
-- FOUR, FIVE, FOUR, FIVE rather than four, four, five, four, and the reason is where the tall
-- hall ends up. A junction eats a corridor width off each end of the leg it sits between, so
-- only a five-bay leg has room for the double-height stretch in the middle of it. With the
-- five in third place it was never reached on a medium run, the stretch fell back onto the
-- opening leg, and the level's one surprise was thirty studs from the spawn.
local PATTERN: { { bays: number, turn: number } } = {
	{ bays = 4, turn = 1 },
	{ bays = 5, turn = -1 },
	{ bays = 4, turn = -1 },
	{ bays = 5, turn = 1 },
}

-- TURNING, and the handedness is worth stating because getting it backwards is invisible in
-- code and obvious in game.
--
-- Roblox is right-handed with +Y up. Stand at the origin facing +Z and your RIGHT hand points
-- at -X, so a LEFT turn from +Z heads toward +X. Written out: left maps (x, z) to (z, -x).
local function turned(dir: Vector3, hand: number): Vector3
	if hand > 0 then
		return Vector3.new(dir.Z, 0, -dir.X)
	end
	return Vector3.new(-dir.Z, 0, dir.X)
end

-- Walks the pattern until `total` studs have been covered, cutting the last leg short so the
-- route ends exactly where it was asked to.
--
-- PREFIX-CONSISTENT ON PURPOSE: build(1000) and build(2000) agree about everything in the
-- first thousand studs, corners included. That is what lets LevelService lay out chunks
-- against a generous estimate and the halls then be built to the length the chunks actually
-- used, with no possibility of the two disagreeing about where corner three was.
function HallRoute.build(total: number): Route
	local legs: { Leg } = {}
	local at = 0
	local here = Vector3.zero
	local dir = Vector3.new(0, 0, 1)
	local index = 0

	while at < total do
		index += 1
		local spec = PATTERN[(index - 1) % #PATTERN + 1]
		local span = spec.bays * HallRoute.BAY
		local last = false
		-- The last leg is trimmed rather than dropped, so a route of any length still ends
		-- facing along a leg instead of stopping in the middle of a junction.
		if at + span >= total then
			span = total - at
			last = true
		end
		table.insert(legs, {
			startAt = at,
			length = span,
			dir = dir,
			from = here,
			to = here + dir * span,
		})
		at += span
		here = here + dir * span
		if last then
			break
		end
		dir = turned(dir, spec.turn)
	end

	-- A degenerate ask still gets a usable route rather than an empty table nobody checks for.
	if #legs == 0 then
		table.insert(legs, {
			startAt = 0,
			length = math.max(total, 1),
			dir = dir,
			from = here,
			to = here + dir * math.max(total, 1),
		})
	end

	return { legs = legs, length = total }
end

-- ===== A ROUTE WHOSE LEGS ARE THE LENGTHS THE CHUNKS ACTUALLY TOOK =====
--
-- build() lays the plan out at its planned lengths, and for a long time that was the only way a
-- route got made. It put every corner at a FIXED distance, while the chunks leading up to it
-- come in whatever lengths the template picks -- so the last chunk before a corner ended a
-- random distance short of it, and that shortfall became either two chunks intersecting or a
-- tiled landing filling a gap nobody could jump.
--
-- LevelService now turns where its chunks are and records how long each leg came out. These
-- three are what it needs to do that, and fromLegs is what the halls build from afterwards --
-- so the corridor turns exactly where the walkway does, by construction.

-- The plan for the Nth leg: how many bays it is meant to be, and which way it turns at its end.
function HallRoute.legPlan(index: number): (number, number)
	local spec = PATTERN[(index - 1) % #PATTERN + 1]
	return spec.bays, spec.turn
end

-- Turning, exposed, so the thing laying chunks and the thing laying walls share one definition
-- of which way is left.
function HallRoute.turn(dir: Vector3, hand: number): Vector3
	return turned(dir, hand)
end

function HallRoute.fromLegs(lengths: { number }): Route
	local legs: { Leg } = {}
	local at = 0
	local here = Vector3.zero
	local dir = Vector3.new(0, 0, 1)
	for index, span in ipairs(lengths) do
		local length = math.max(span, 1)
		table.insert(legs, {
			startAt = at,
			length = length,
			dir = dir,
			from = here,
			to = here + dir * length,
		})
		at += length
		here = here + dir * length
		local _, hand = HallRoute.legPlan(index)
		dir = turned(dir, hand)
	end
	if #legs == 0 then
		return HallRoute.build(1)
	end
	return { legs = legs, length = at }
end

-- Where the route is at `at` studs along it, and which way it is heading there.
--
-- AT A CORNER THE ANSWER IS THE NEW DIRECTION. The comparison is strict, so a distance that
-- lands exactly on a leg boundary belongs to the leg AFTER the turn. That is the answer the
-- caller wants every time: something placed at the corner is something about to travel the
-- new way, not something that has just finished travelling the old way.
--
-- Past the end it extrapolates along the final leg rather than clamping, because the finish
-- line and the flume mouth both sit slightly beyond the last chunk.
function HallRoute.pointAt(route: Route, at: number): (Vector3, Vector3)
	for index, leg in ipairs(route.legs) do
		local isLast = index == #route.legs
		if at < leg.startAt + leg.length or isLast then
			local along = at - leg.startAt
			if not isLast then
				along = math.clamp(along, 0, leg.length)
			end
			return leg.from + leg.dir * along, leg.dir
		end
	end
	return Vector3.zero, Vector3.new(0, 0, 1)
end

-- The next turn strictly after `at`, or nil if the rest of the route is straight.
function HallRoute.nextCorner(route: Route, at: number): number?
	for index, leg in ipairs(route.legs) do
		if index == #route.legs then
			break
		end
		local ends = leg.startAt + leg.length
		if ends > at then
			return ends
		end
	end
	return nil
end

-- Every turn, with both directions, for whoever has to build the junction rooms.
function HallRoute.corners(route: Route): { Corner }
	local found: { Corner } = {}
	for index = 1, #route.legs - 1 do
		local leg = route.legs[index]
		local next_ = route.legs[index + 1]
		-- The hand is recovered from the two directions rather than stored, so it cannot
		-- disagree with the geometry it is supposed to describe.
		local left = turned(leg.dir, 1)
		table.insert(found, {
			at = leg.startAt + leg.length,
			point = leg.to,
			inDir = leg.dir,
			outDir = next_.dir,
			hand = if left:Dot(next_.dir) > 0 then 1 else -1,
		})
	end
	return found
end

-- HOW FAR A POINT IS FROM THE WALKWAY, flat, measured to the nearest leg.
--
-- This is what makes the lane rule enforceable now that the route bends. The old guard
-- measured |x| from the origin, which is only the distance to the route while the route runs
-- along one axis -- the moment it turned a corner the guard was measuring nothing and passing
-- everything.
function HallRoute.distanceTo(route: Route, point: Vector3): number
	local best = math.huge
	for _, leg in ipairs(route.legs) do
		local rel = point - leg.from
		local along = math.clamp(rel.X * leg.dir.X + rel.Z * leg.dir.Z, 0, leg.length)
		local near = leg.from + leg.dir * along
		local dx = point.X - near.X
		local dz = point.Z - near.Z
		local gap = math.sqrt(dx * dx + dz * dz)
		if gap < best then
			best = gap
		end
	end
	return best
end

-- A CFrame whose local +Z runs along the route at `at`.
--
-- Chunks are modelled with their entry at local z = 0 and their exit at z = +length, so the Z
-- COLUMN has to be the direction of travel. Built from an explicit matrix for that reason:
-- CFrame.lookAt aims the look vector, and a CFrame's look vector is its NEGATIVE z, so using
-- it here would face everything backwards.
function HallRoute.frameAt(route: Route, at: number, height: number): CFrame
	local point, dir = HallRoute.pointAt(route, at)
	local up = Vector3.new(0, 1, 0)
	return CFrame.fromMatrix(point + Vector3.new(0, height, 0), up:Cross(dir), up, dir)
end

return HallRoute
