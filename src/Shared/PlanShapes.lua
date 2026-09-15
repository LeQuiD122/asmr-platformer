--!strict
-- ReplicatedStorage/Shared/PlanShapes.lua
-- Outlines a platform can be cut to, as pure functions of a normalised position.
--
-- === Why this can exist at all ===
--
-- A granular platform is a field of small cubes placed by a loop, and the loop already
-- tests each cube against a rounded-rectangle boundary and skips the ones outside it. That
-- test is the only thing deciding the platform's shape, so replacing it replaces the shape
-- -- with no new mesh, no import, and nothing size-locked, because there is no asset to
-- lock. Soap can be a heart today and a star tomorrow for the cost of one function.
--
-- THREE MATERIALS CAN DO IT, AT THREE DIFFERENT RESOLUTIONS, and the difference is just
-- how many parts a cell holds:
--
--   Soap      a field of cubes per cell, so the outline is cut ~18 steps across a platform,
--             and finer still on the shaved grain. Curves read as curves.
--   Lego      ONE brick per cell: six steps. A heart at six steps is a blob, so lego gets
--             the shapes that survive being pixelated -- a cross, a hole -- which is also
--             what real plates look like, since they step in whole bricks.
--   Buttons   one cap per cell, over a plate that stays whole. The shape decides which
--             BUTTONS exist rather than where the floor is, so it is the one place an
--             outline is purely cosmetic and cannot strand anybody.
--
-- Rigged materials cannot do it at all. Honey, sand and bubble wrap are skinned meshes whose
-- bones are matched to sub-region cells by position, so their outline is baked into an FBX
-- and changing it means a new asset and a re-import. `form` on one of those names a MESH
-- variant instead -- sand's turtle, bubble wrap's giant -- which is the same word doing a
-- different job, and worth knowing before reading a warning about it.
--
-- === Shapes are gameplay, and there is a checker ===
--
-- On a granular or bricked platform the parts ARE the floor and the slab underneath does not
-- collide, so anywhere the outline is empty is open air down to the sea. `check_plan_shapes.py`
-- loads this file into a real Lua interpreter, calls these functions at the exact cube grid
-- each chunk will build, and fails on a shape that cannot be entered, cannot be left, is
-- split in two, strands floor you cannot reach, or narrows below what a character can walk.
-- Three shapes in this file were retuned because it measured them.
--
-- === The contract ===
--
-- Every shape takes (u, v) in [-1, 1] -- the position within the platform's own footprint,
-- where (0, 0) is the centre and (1, 1) the far corner -- and returns whether that point is
-- inside. Aspect is deliberately NOT corrected: a heart on a 20 x 14 slab is a wide heart,
-- which is what you want, because the alternative is a heart with empty slab beside it.

local PlanShapes = {}

export type Shape = (u: number, v: number) -> boolean

-- A rounded rectangle, matching what the granular builder did before shapes existed.
-- `radius` is in normalised units, so 0.35 is a little over a third of the half-width.
local function roundedRect(u: number, v: number): boolean
	local radius = 0.35
	local qu = math.max(math.abs(u) - (1 - radius), 0)
	local qv = math.max(math.abs(v) - (1 - radius), 0)
	return math.sqrt(qu * qu + qv * qv) <= radius
end

-- A heart, built from two overlapping circles above a tapered V rather than from the
-- implicit curve, because every part of it has to be tunable against gameplay.
--
-- POINT TOWARD THE ENTRY, so you arrive at the tip and leave between the lobes.
--
-- === Three numbers that are gameplay, not styling ===
--
-- The slab under a granular platform has CanCollide off -- the cubes ARE the floor -- so
-- anywhere the shape is empty is a hole you fall through. That turns two aesthetic choices
-- into hard constraints:
--
--   * The TIP is the landing target. A mathematically sharp point gives a 1-stud strip to
--     land on. `taper` at 0.40 rather than 1.0 makes the V bulge outward instead of running
--     straight, which widens the tip to about 7.7 studs while still reading as a point.
--   * The CLEFT sits at the exit edge, so it is a hole in the face you jump from. Circles
--     at 0.40 with radius 0.60 overlap deeply, filling the centre line up to y = 0.707
--     against lobe tops at 0.86 -- so the cleft is a 1.2-stud notch you step around rather
--     than a slot that splits the exit in two.
--
-- The scale and offset then place the heart so the slab clips it at both ends: the tip is
-- blunted by the entry edge and the lobes are cut by the exit edge. Without that clipping
-- the shape floats in the middle of the slab with no material at either face, and the chunk
-- becomes unenterable and unleavable -- which is what the first version did.
local HEART_CX, HEART_CY, HEART_R = 0.40, 0.26, 0.60
local HEART_TAPER = 0.40
local HEART_SCALE, HEART_OFFSET = 0.80, -0.04

local function heart(u: number, v: number): boolean
	local x = u
	local y = v * HEART_SCALE + HEART_OFFSET

	local dx = x - HEART_CX
	local dy = y - HEART_CY
	if dx * dx + dy * dy <= HEART_R * HEART_R then
		return true
	end
	dx = x + HEART_CX
	if dx * dx + dy * dy <= HEART_R * HEART_R then
		return true
	end

	if y >= -1 and y <= HEART_CY then
		local fraction = (y + 1) / (HEART_CY + 1)
		return math.abs(x) <= (HEART_CX + HEART_R) * fraction ^ HEART_TAPER
	end
	return false
end

local function circle(u: number, v: number): boolean
	return u * u + v * v <= 1
end

-- Five points. The radius oscillates with angle; the exponent sharpens the points, because
-- a plain cosine gives a flower and what separates a star from a flower is that its points
-- are narrower than its bays.
--
-- THE EXPONENT IS THE POINT'S WIDTH, and it is the heart's blunted tip all over again.
--
-- One of the five points sits on the exit centre line, so the last row of cubes on the
-- platform IS a tip -- and at 0.55 that tip came out two cubes, a 2-stud spike to leave a
-- chunk by. check_plan_shapes measured it before anyone walked it; it had been there since
-- the star was written.
--
-- 0.40 bulges the flanks outward instead of running them straight to the point, exactly as
-- HEART_TAPER does, and takes the tip to nearly four studs on the 22-wide platform R4 now
-- uses. Scaling the star up so the slab clipped its points was the other candidate and was
-- worse to look at: a five-pointed star cut by a square is not symmetrical about anything.
local function star(u: number, v: number): boolean
	local radius = math.sqrt(u * u + v * v)
	local angle = math.atan2(v, u)
	local lobe = math.abs(math.cos(2.5 * angle)) ^ 0.40
	return radius <= 0.42 + 0.58 * lobe
end

-- A turtle from above: shell, head, four flippers, tail. Each is an ellipse, and the shape
-- is their union -- which is both the cheapest way to build it and the reason it reads,
-- since a turtle IS a big oval with five small ovals stuck to it.
local function ellipse(u: number, v: number, cx: number, cy: number, rx: number, ry: number): boolean
	local du, dv = (u - cx) / rx, (v - cy) / ry
	return du * du + dv * dv <= 1
end

local function turtle(u: number, v: number): boolean
	if ellipse(u, v, 0, 0, 0.72, 0.62) then
		return true -- shell
	end
	if ellipse(u, v, 0, 0.82, 0.26, 0.26) then
		return true -- head
	end
	-- The tail OVERLAPS the shell. At its first position it started 0.04 short of the
	-- shell's edge, which left a hairline of missing floor across the platform -- invisible
	-- in a picture of the shape and a hole you fall through in play.
	if ellipse(u, v, 0, -0.78, 0.15, 0.26) then
		return true -- tail
	end
	for _, flipper in ipairs({ { 0.68, 0.44 }, { -0.68, 0.44 }, { 0.72, -0.40 }, { -0.72, -0.40 } }) do
		if ellipse(u, v, flipper[1], flipper[2], 0.30, 0.22) then
			return true
		end
	end
	return false
end

-- A stepping-stone cluster: three overlapping discs down the length of the platform. Reads
-- as a path rather than a slab, and unlike the others it has a NARROW WAIST, so the route
-- across it is not simply "walk in a straight line".
local function pebbles(u: number, v: number): boolean
	return ellipse(u, v, 0, 0.66, 0.52, 0.34)
		or ellipse(u, v, 0, 0, 0.62, 0.40)
		or ellipse(u, v, 0, -0.66, 0.52, 0.34)
end

-- A hexagon with its points along the travel axis.
--
-- Built as the intersection of three slabs rather than from a radius-and-angle test, which
-- is what keeps the sides DEAD STRAIGHT. Every other shape here is round, and the one thing
-- a cube field does better than a mesh is a straight edge -- cubes on a grid meeting a
-- straight boundary line up exactly, and the platform reads as cut rather than as eroded.
--
-- The two ends come out 0.42 wide, which is the same reasoning as the heart's blunted tip:
-- a point you have to land on cannot be a point.
local function hexagon(u: number, v: number): boolean
	if math.abs(v) > 1 then
		return false
	end
	-- cos30 and sin30. The two rotated slabs cut the corners off the vertical one.
	return math.abs(u * 0.866 + v * 0.5) <= 0.866 and math.abs(u * 0.866 - v * 0.5) <= 0.866
end

-- A PLUS, and the first shape here whose arms are a decision rather than a decoration.
--
-- The side arms go nowhere: they are a wide platform you can stand on that does not help you
-- cross. Only the middle lane does, and it is 0.34 of the half-width -- about 6 studs on an
-- 18-wide slab, wide enough to walk without being wide enough to wander.
local CROSS_ARM = 0.34

local function cross(u: number, v: number): boolean
	return roundedRect(u, v) and (math.abs(u) <= CROSS_ARM or math.abs(v) <= CROSS_ARM)
end

-- THE ONE WITH A HOLE IN IT, and it is a real hole -- the slab under a granular platform
-- does not collide, so the middle of this chunk is open air down to the sea.
--
-- Cut from the rounded rectangle rather than drawn as a ring of its own, deliberately. A
-- free-floating annulus has nothing at the entry and exit faces and would be unenterable;
-- taking a bite out of the default outline guarantees the platform still meets its
-- neighbours everywhere except where the bite is, so the shape can only ever remove floor
-- from the MIDDLE. That is also what makes it read as a hole rather than as a doughnut.
local function ring(u: number, v: number): boolean
	return roundedRect(u, v) and not ellipse(u, v, 0, 0, 0.44, 0.36)
end

-- A crescent: an oval with a bite out of one side, so the straight line across is blocked
-- and the way round is asymmetric -- you commit to the outside of the curve or you fall.
--
-- The bite is 0.70 tall against an outer height of 1.15, so it CANNOT reach either end. The
-- ends stay solid by construction rather than by tuning, which is the same guarantee the
-- ring gets from being a subtraction.
local function crescent(u: number, v: number): boolean
	return ellipse(u, v, 0, 0, 0.95, 1.15) and not ellipse(u, v, 0.62, 0, 0.62, 0.70)
end

-- A band that snakes from one end to the other. The only shape here that makes you turn.
--
-- The centre line is a half-period sine, so the band leaves the entry pointing straight,
-- swings a full 0.55 of the half-width to one side, crosses back through the middle and
-- swings the same distance the other way before straightening for the exit. Both faces are
-- centred by construction: sin(pi * v) is zero at v = -1 and v = 1, so the band arrives and
-- leaves on the middle of the edge no matter how far it wanders in between.
local WAVE_SWING = 0.55
local WAVE_HALF = 0.42

local function wave(u: number, v: number): boolean
	return math.abs(u - WAVE_SWING * math.sin(math.pi * v)) <= WAVE_HALF
end

-- A leaf: the intersection of two big offset circles, which is the classic lens and the
-- cheapest pointed shape there is.
--
-- `ry` is the whole tuning story, and the window is narrow. At 1.15 the two arcs meet before
-- they reach the ends and the platform is not crossable at all; at 1.35 the tips are blunt
-- enough that it reads as an ellipse. 1.28 leaves them 3.6 studs on the platform P13 uses --
-- over the 3.4 a character can walk, and pointed enough to be a leaf rather than an egg.
local LEAF_OFFSET, LEAF_RX, LEAF_RY = 0.75, 1.5, 1.28

local function leaf(u: number, v: number): boolean
	return ellipse(u, v, -LEAF_OFFSET, 0, LEAF_RX, LEAF_RY)
		and ellipse(u, v, LEAF_OFFSET, 0, LEAF_RX, LEAF_RY)
end

-- A cog. The teeth are a STEP function of the angle, not a smooth one, and that is the
-- whole difference between a cog and the flower a cosine gives you: real teeth have flat
-- tops, parallel flanks and square roots, and a radius that eases in and out has none of
-- those. The star above wants the smooth version, so the two do not converge.
--
-- WIDE TEETH, NARROW SLOTS, and the cut-off is the whole tuning story.
--
-- A tooth is an angular wedge, so its narrowest point in the plane is at its BASE, where it
-- leaves the body -- and one of the eight sits exactly on the exit centre line. At the
-- obvious cut of 0.2 that base measured 2.6 studs on an 18-wide platform, which is a spike
-- to leave the chunk by rather than a step, and check_plan_shapes found it before anyone
-- walked it.
--
-- -0.6 opens each tooth to about 32 degrees against a 13-degree slot, which takes the base
-- to 6 studs. It also stops being a compromise once you look at it: a rim with wide teeth
-- and narrow slots cut into it is a sprocket, and a sprocket is a better fit for a cube
-- field than a fine gear ever was.
local COG_TEETH = 8
local COG_CUT = -0.6
local COG_BODY, COG_TOOTH = 0.74, 0.26

local function cog(u: number, v: number): boolean
	local radius = math.sqrt(u * u + v * v)
	local angle = math.atan2(v, u)
	local tooth = if math.cos(COG_TEETH * angle) > COG_CUT then COG_TOOTH else 0
	return radius <= COG_BODY + tooth
end

-- Two discs joined by a bar, and the tightest waist in the file at 0.20 of the half-width --
-- around 3.6 studs, which is a beam rather than a path.
--
-- Distinct from `pebbles` on purpose: that one is three lobes with a gentle pinch and reads
-- as stepping stones you stroll between, this is two landings with a genuine crossing in the
-- middle. Same idea, opposite amount of it.
local function bone(u: number, v: number): boolean
	return ellipse(u, v, 0, 0.62, 0.78, 0.45)
		or ellipse(u, v, 0, -0.62, 0.78, 0.45)
		or (math.abs(u) <= 0.20 and math.abs(v) <= 0.70)
end

-- Declared as a LOCAL and then assigned, not annotated in place.
--
-- `PlanShapes.shapes: {...} = {...}` is a syntax error in Luau: a type annotation is only
-- legal on a `local`, so the parser reads `PlanShapes.shapes:` as the beginning of a method
-- definition and fails on the brace. It is a compile error, not a type warning -- the whole
-- module fails to load and takes ChunkBuilder down with it.
local shapes: { [string]: Shape } = {
	rounded = roundedRect,
	heart = heart,
	circle = circle,
	star = star,
	turtle = turtle,
	pebbles = pebbles,
	hexagon = hexagon,
	cross = cross,
	ring = ring,
	crescent = crescent,
	wave = wave,
	leaf = leaf,
	cog = cog,
	bone = bone,
}
PlanShapes.shapes = shapes

-- Looks a shape up by name, falling back to the rounded rectangle.
--
-- An unknown name is NOT an error: a chunk asking for a shape that does not exist should
-- build as an ordinary platform rather than fail to build, because the alternative is a
-- typo in a chunk definition taking out level generation. It warns once so the typo is
-- still findable.
local warned: { [string]: boolean } = {}

function PlanShapes.get(name: string?): Shape
	if not name then
		return roundedRect
	end
	local shape = shapes[name]
	if shape then
		return shape
	end
	if not warned[name] then
		warned[name] = true
		warn(("PlanShapes: no shape named '%s'; using the default outline."):format(name))
	end
	return roundedRect
end

return PlanShapes
