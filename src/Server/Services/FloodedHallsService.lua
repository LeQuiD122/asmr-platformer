--!strict
-- The flooded halls: a tiled bathhouse standing in still green water.
--
-- === What this is ===
--
-- A place to run through: a liminal bathhouse, tiled floor to ceiling, with the route carried
-- on a walkway high above a drowned lower floor. Arches recede into other arches, columns
-- stand in the water, and every so often something is floating that should not be.
--
-- === The route IS the building ===
--
-- This is the third attempt at making the chunks and the architecture coexist, and the first
-- two failed the same way.
--
--   A MAZE with a spiral route through it. A spiral climbs eighty studs while turning through
--   five hundred degrees; a maze is a grid with walls in the middle of it. Nothing had told
--   either about the other, and the chunks came out inside the walls.
--
--   A STRAIGHT CORRIDOR with a straight route. Better, and still wrong: the route stayed
--   straight and the room stayed straight, and they agreed about nothing else. The per-chunk
--   elevation step was never suppressed, so forty-four chunks climbed a hundred and ten studs
--   through an eighty-eight stud ceiling -- which is why it still looked like a spiral going
--   up even after it had been told to be a line.
--
-- Both failures are the same failure: two pieces of code guessing at each other. So the shape
-- is written down once, in Shared/HallRoute, and BOTH sides read it. The corridor turns
-- because the route turns, and the route turns because the corridor does. They are one thing.
--
-- === Why the walkway is high above the water ===
--
-- Two reasons, and the second is not cosmetic.
--
-- It is the image: every reference is a vast hall seen ACROSS, with the eye carried down a
-- colonnade to something far away. Standing at floor level in a corridor you see one bay. From
-- a walkway two thirds of the way up you see the whole length of it, the water below, and the
-- light coming across from the far side.
--
-- And it makes falling mean something. With the route at floor level a fall landed you in
-- ankle-deep water on a solid tiled floor, well ABOVE the kill plane -- no death, no respawn,
-- no way back up, just a player standing in a puddle with nothing to do. The flooded floor is
-- fifty-six studs down now, so the kill plane is passed on the way and a fall is a fall.
--
-- === Why the tile grid is not in the meshes ===
--
-- The tiles are the whole look and none of them are modelled. One wall at the tile size in the
-- references is over a thousand tiles, each needing a recessed grout line; as geometry that is
-- tens of thousands of triangles per surface and there are hundreds of surfaces here.
--
-- Roblox's built-in CeramicTiles carries a real PBR set -- albedo, normal, roughness -- tiling
-- at a fixed world scale, which is exactly this surface for the cost of one property. So the
-- meshes carry the forms the material cannot give and the material carries the surface the
-- forms cannot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HallRoute = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("HallRoute"))

local FloodedHallsService = {}

-- ===== SCALE, and it is the one number worth understanding here =====
--
-- The kit is modelled at human size: a 24-stud bay and a 22-stud ceiling, which is a room you
-- could stand in. That is the right size for a bathroom and the wrong size for this.
--
-- It also fixes the thing I could not otherwise fix. CeramicTiles tiles at a FIXED world size,
-- so the only way to change how big a tile looks relative to a wall is to change how big the
-- wall is. At human scale a 22-stud wall is a handful of tiles high and reads as a domestic
-- bathroom; at four times that it is dozens, which is the fine grid over a vast surface that
-- every one of the references actually shows.
--
-- If the tiles look wrong in game, THIS is the number to move, and it is the only one.
local SCALE = 4.0

-- One bay at model size. Matches BAY and HEIGHT in blender/gen_flooded_halls.py, and matches
-- HallRoute.BAY -- legs are whole bays so that walls, columns and arches land on the grid all
-- the way to a corner instead of being cut off mid-bay.
local BAY = 24 * SCALE
local HEIGHT = 22 * SCALE
local WALL_THICK = 2 * SCALE

-- Half the width of the lane the route runs down. Nothing solid is ever built inside it, and
-- guardLane below enforces that rather than trusting it.
--
-- THE ARCH PICKED THIS NUMBER, not taste. The transverse arch is the one piece the route runs
-- THROUGH rather than beside, so the lane has to be narrower than its opening at the height a
-- player occupies or the arch is a wall across the level. See buildArchway: ARCH_SPAN and
-- ARCH_SPRING are set against this, and check_halls measures the two against each other at
-- both foot and head height.
local LANE_HALF = 30

-- Half the width of the corridor itself.
--
-- WIDE, AND NOT BY PREFERENCE. Everything that stands beside the route has to fit between the
-- lane and the wall, and at BAY * 0.8 that gap is 43 studs -- which is less than a dry ledge is
-- wide and a third of what the sunken bay needs. Both would have been built straddling the
-- walkway, and the lane guard would have said so on every single run.
--
-- It is also what the references actually show: a narrow walkway crossing a very large hall,
-- not a corridor with a path down it. The walkway is 20 studs in a room of 211.
local HALL_HALF_WIDTH = BAY * 1.1

-- HOW FAR THE FLOODED FLOOR LIES BELOW THE WALKWAY. See the header: this is what makes a fall
-- a fall. LevelService puts the kill plane 40 studs under the lowest walkable surface, so
-- anything past 40 works and 56 leaves real margin without burying the colonnade.
local FLOOR_DROP = 56

-- How deep the water lies on that floor. Ankle-to-shin, so the tile pattern still reads
-- through it, which is what makes the floor legible from above.
local WATER_DEPTH = 1.9 * SCALE

-- How far a dry ledge stands above the water.
local LEDGE_RISE = 2.4 * SCALE

local TILE_COLOUR = Color3.fromRGB(232, 226, 198)
-- ===== NOT GLASS. =====
--
-- Roblox's Glass material is not a colour, it is a screen-space refraction: it samples the
-- frame buffer behind itself and bends it. Transparent surfaces are not in that buffer, so
-- glass and other translucent objects interact badly and view-dependently -- which is the
-- reported bug exactly: slime, honey and jello soda platforms vanishing from some angles and
-- reappearing from others.
--
-- Tiling the water helped its sort order and did not fix this, because the sort order was not
-- the whole of it. This level had glass in two places, both of them large and both of them
-- near the things that were disappearing: the water under the entire route, and a diffuser
-- hanging under every ceiling light directly over it.
--
-- SmoothPlastic with the same transparency and reflectance loses the true refraction and keeps
-- the sheen, the colour and the depth. That is a real loss and it is worth it: a reflection
-- nobody can see because the platform in front of it has disappeared is worth nothing. Flip
-- this back to Glass to see the difference, one line, if the platforms ever behave.
local WATER_MATERIAL = Enum.Material.SmoothPlastic

-- LIGHTER AND GREENER than it was. The water reads almost black in an unlit room, and this
-- room is deliberately unlit; a darker pigment on top of that gave a pool of tar. Most of what
-- makes water look like water is what you can see THROUGH it, so the colour has to be light
-- enough for the tile grid to survive the trip.
local WATER_COLOUR = Color3.fromRGB(96, 198, 172)

-- ===== VARIATION, and how much of it =====
--
-- A liminal space is not an empty one. What makes the references unsettling is that they are
-- FULL of purpose-built fittings -- steps, basins, rails, cubicle stubs, plinths -- with
-- nobody using any of them. A bare tiled corridor is not liminal, it is unfinished.
--
-- But every one of these is placed beside the walkway you have to keep looking past, so the
-- probabilities are low on purpose. The aim is that no two bays are the same, not that every
-- bay has something in it.
local DOORWAY_CHANCE = 0.3
local BASIN_CHANCE = 0.26
local PARTITION_CHANCE = 0.22
local PLINTH_CHANCE = 0.20
-- How deep a sunken basin goes, picked per basin. Three depths rather than a range, because
-- water you can measure needs things to measure it AGAINST -- two basins at 41 and 43 studs
-- read as one depth badly built, where 28 and 60 read as shallow and deep.
local BASIN_DEPTHS = { 11 * SCALE, 16 * SCALE, 22 * SCALE }
-- The void is not painted black, it is painted ALMOST black. A pure zero reads as a hole in
-- the render rather than as a surface, and the eye stops believing there is a space there.
-- Darker again, and SmoothPlastic rather than Slate below: Slate carries a real texture, and a
-- texture is something for the little light that reaches down there to catch on.
local VOID_COLOUR = Color3.fromRGB(3, 4, 5)

-- THE COLOUR THE LIGHT ARRIVES IN. Warm, and much warmer than the tiles: every reference is
-- lit by daylight coming through something, and daylight that has passed through frosted glass
-- or a deep reveal always arrives warmer and softer than it left.
local GLOW_COLOUR = Color3.fromRGB(255, 246, 214)
-- AND THE COLOUR OF THE SKY OVER THE GLAZED ROOF, which is not the same as the lamps. Daylight
-- through overcast is cool and almost colourless; the warmth in this level comes from what it
-- lands on. Making the sky warm as well would leave nothing for the tile to do.
local SKY_COLOUR = Color3.fromRGB(238, 246, 250)
-- AND WHAT THE GLASS ITSELF GLOWS AT, a little under the sky's own colour. Neon's brightness IS
-- its colour, so a whole ceiling of it at near-white outshone everything in the hall and bloomed
-- into a white-out. Brought down just enough that the glazing bars read against it again.
local ROOF_GLOW = Color3.fromRGB(206, 214, 218)
-- AND THE COLOUR IT ARRIVES IN DOWN AT THE WATER, which is not the same. Light that has been
-- through a few studs of green water and back out comes back green, and that is most of why a
-- lit pool reads as a lit POOL rather than as a floor with a lamp on it.
local POOL_GLOW = Color3.fromRGB(150, 240, 216)

-- ===== THE TILE PALETTE =====
--
-- ONE CREAM WAS NOT A PALETTE. Every wall, floor and ceiling in the level was TILE_COLOUR, so the
-- whole building was a single value with the lighting as the only thing describing it -- and in
-- a dim room the lighting describes very little. A real bath hall is tiled in at least three:
--
--   A WAINSCOT, the lower third of every wall in a cooler, greener tile that hides the wear and
--   the water marks. It is also what makes the walkway read as high: you look DOWN at the
--   change of colour, and the upper wall carries on past you.
--   A TRIM, a lighter glazed bullnose on every edge -- dado, cornice, coping, niche frames.
--   An ACCENT, one dark teal, used sparingly: a single stripe under the dado, the frame round
--   the dome, the pool's depth band. Sparingly is the point; a second stripe is a pattern.
local WAINSCOT_COLOUR = Color3.fromRGB(190, 214, 204)
local TRIM_COLOUR = Color3.fromRGB(242, 238, 218)
local ACCENT_TILE = Color3.fromRGB(70, 112, 116)
-- The inside of a blind niche: the wainscot tile a shade down, which is what reads as a recess.
local NICHE_COLOUR = Color3.fromRGB(176, 198, 188)

-- ===== THE FLUME, AND THE VOID UNDER IT =====
--
-- The route ends by RIDING something, not by touching a pad. Every other level finishes
-- administratively: you step on the last chunk and a Touched fires. That is fine for a spiral
-- in open sky and wrong here -- this level is a swimming baths, and a swimming baths ends the
-- way one does.
--
-- And it does not end in the water. The last chamber is the one room where the water has gone:
-- the floor has given way, and everything that was in here drained into whatever is underneath.
-- The flume runs down into that. You ride a bright plastic tube out of a lit room, it ends in
-- mid-air, and you fall the rest of the way in the dark.
--
-- These numbers mirror build_slide() in gen_flooded_halls.py. They have to: the ride is a path
-- through the middle of a mesh, and a rider following a different curve from the one the tube
-- was swept along goes through its wall.
local SLIDE_RADIUS = 9.0 * SCALE
local SLIDE_TURNS = 1.25
local SLIDE_DROP = 26.0 * SCALE
-- The inside radius of the trough, which is not decoration: it is the difference between the
-- tube's CENTRE LINE, which is what the mesh is swept along, and the surface a rider is
-- actually on. Ignore it and the rider floats thirteen studs above the trough with their feet
-- through the open side, and the mouth of the tube stands a full bore above the apron that is
-- supposed to lead into it.
local SLIDE_BORE = 1.8 * SCALE
-- How thick the flume's shell is, mirrored from SLIDE_WALL in gen_flooded_halls.py with the rest.
-- The brackets are measured against it: a saddle has to meet the OUTSIDE of the shell, which is a
-- bore and a wall below the centre line.
local SLIDE_WALL = 0.5 * SCALE
-- HOW MUCH THE MOUTH OPENS OUT, mirrored from SLIDE_FLARE in gen_flooded_halls.py.
--
-- It was 0.45, which is a flare you could park a bus in: the mouth stood eighteen studs above
-- the apron it is supposed to lead off, so the entrance read as a pipe hanging in the air
-- beside the platform rather than as something you step into. It also has to be known HERE,
-- because the mouth's trough floor is a flared bore below the tube's centre line and that is
-- the height the whole flume has to be lifted by.
local SLIDE_FLARE = 0.15
local SLIDE_MOUTH_LIFT = SLIDE_BORE * (1 + SLIDE_FLARE)
-- How far below the centre line the rider sits. Their root is roughly three studs above their
-- feet, so this puts the feet on the trough and their head inside the tube.
-- In the open trough that puts the feet a stud off its floor and the head under its lip, and
-- check_halls works that through at every stage of the ride with the bank included.
local RIDE_SINK = SLIDE_BORE - 3.6
-- How much of the ride is spent inside the tube. The rest is the fall.
local SLIDE_HELIX = 0.68
local SLIDE_PLUNGE = 108
local SLIDE_SECONDS = 4.6
-- ===== HOW FAR OUT THE MOUTH SITS =====
--
-- Pushed out from 60 to 100, and the reason is the pit rather than the walk. The pit is centred
-- on the flume's own axis, and the axis is a radius away from the mouth -- so the further in
-- the mouth is, the further the hole reaches back across the route. At 60 the pit came within
-- a couple of studs of the walkway's centreline; at 100 it clears it by nearly thirty.
local MOUTH_OFFSET = 100
-- How far past the end of the route the mouth sits, so the gangway to it starts where the
-- walkway stops rather than running back underneath it. The gangway is twice this wide with its
-- near edge on the line where the last chunk ends: twenty-four studs, which is a walkway, where
-- the thirty-two stud apron it replaces read as a second platform.
local MOUTH_ALONG = 12
-- How far the gangway's deck reaches back past the route's centreline, so the whole width of the
-- last chunk steps onto planks rather than half of it.
local GANGWAY_TAIL = 12

-- How wide the opening in the ceiling under the dome is. Hall_Dome is 156 studs in radius at
-- this scale, so this has to be under that or the cap does not reach the plate it caps.
-- NARROWER THAN THE DOME'S OWN FOOTPRINT ALL THE WAY ROUND. The hole is square and the dome is
-- round, so at 150 the hole's corners reached 212 studs from the centre against a 156-stud
-- dome: four patches of ceiling open to nothing at the corners of the room. At 108 the square's
-- diagonal is inside the dome's rim.
local DOME_HALF = 108

-- ===== THE TALL HALL =====
--
-- One stretch of the route where the ceiling goes up to twice the height and the walls carry
-- a second order above the cornice, lit from clerestory windows nobody could reach.
--
-- THE POINT IS THE CHANGE, not the height. A level that is uniformly grand is a level with one
-- room in it, however big that room is. Walking out of an eighty-eight stud corridor into a
-- hundred and seventy-six stud hall and back into the corridor is three rooms, and it is the
-- only moment in the level where the building surprises you.
-- TWO BAYS, NOT THREE, and the short run is what set it. A junction eats a full corridor
-- width off each end of the leg it sits between, so a four-bay leg has 173 studs of actual
-- hall in it. At three bays the tall stretch did not fit anywhere on a 22-chunk route and the
-- short run silently lost the one room in the level that is not a corridor.
local TALL_BAYS = 2
local TALL_MULTIPLIER = 2.0

-- ===== THE POOL =====
--
-- The hall had water in it but no POOL: one flat sheet eight studs deep from wall to wall, with
-- stripes painted on the floor under it. Every reference is the other thing -- a basin with an
-- edge, a coping, a depth you can see go dark, steps going down into it.
--
-- So there is one now, down the middle of every leg, directly under the walkway: forty studs
-- deeper than the shallows either side of it, tiled, lit from inside its walls, with lane ropes
-- floating along its edges and the lane stripes on its floor where they belong. The colonnade
-- stands in the shallows beside it, which is exactly where a colonnade in a bath hall stands.
--
-- POOL_HALF is set by the columns, not by taste: its coping and gutter have to stop short of the
-- column bases at LANE_HALF + BAY * 0.3 less a column's radius. check_halls measures it.
local POOL_HALF = 32
local POOL_DEPTH = 10 * SCALE
-- Deeper than the shallows and bluer, for the reason the basins are: water is a depth of colour.
local POOL_WATER_COLOUR = Color3.fromRGB(70, 170, 168)
local POOL_LINING = Color3.fromRGB(198, 226, 222)
-- If this MaterialVariant exists under MaterialService -- it is the glazed mosaic the backdrop's
-- colonnade uses -- the pool is lined with it. If not, the pool is ceramic tile like the rest.
local POOL_TILE_VARIANT = "PoolTileBackdrop"

-- ===== BEHIND THE START =====
--
-- How far the hall runs back past the spawn before it ends, and the passage through its end wall.
-- See buildEntrance.
--
-- A BAY AND A HALF, so the first thing behind you is a room rather than a wall. The first leg's
-- bays still begin half a bay back; the extra bay puts the end wall far enough away to hold a
-- deck, a chair and a doorway without any of them crowding the spawn.
local ENTRANCE_DEPTH = BAY * 1.5
-- The doorway, and the passage behind it: narrower and lower than anything on the route, which
-- is what makes it read as a way out of the hall rather than more of it.
local DOOR_HALF = 20
-- Four studs lower than it was, so the stopped clock over it hangs clear of both the architrave
-- below and the cornice every wall now carries along its top.
local DOOR_HEIGHT = 56
local PASSAGE_HALF = 34
-- Short of the floor, water and ceiling plates, which reach HALL_HALF_WIDTH + BAY * 2.6 past the
-- start. check_halls holds the passage to that, because past it the passage opens onto the sky.
local PASSAGE_LENGTH = BAY * 1.8

-- The hole in the chamber floor, and the black room under it.
local PIT_HALF = 62
-- ===== WHY YOU COULD STILL SEE THE BOTTOM, AND IT WAS NOT THE DEPTH =====
--
-- The shaft used to drop a hundred and twenty studs and then OPEN OUT into a wider black room.
-- That was the mistake. Widening puts a horizontal ledge all the way round at the join, and a
-- ledge is a floor: from the rim you looked down a shaft and saw a lit ring of shelf stopping
-- it. The thing that read as "the bottom" was not the bottom at all.
--
-- What hides a bottom is not darkness and not distance -- it is the ABSENCE OF A CUE. Parallel
-- walls receding with nothing crossing them give the eye nothing to fix on, and the floor, when
-- it finally arrives, is fogged to within a shade of the walls beside it and cannot be picked
-- out. So: one shaft, one width, all the way down, and four hundred studs of it.
--
-- (Distance alone makes it WORSE, which is worth writing down because it is the obvious move.
-- Fog blends everything toward its colour by distance, so a floor sunk far enough renders as a
-- clearly visible pale plate. Uniformity is what works, not depth.)
local PIT_WALL_DEPTH = 400

-- ===== IS THIS THE MESH THE GENERATOR CURRENTLY BUILDS? =====
--
-- Nothing syncs in this project: every mesh is exported by hand and imported by hand, so the
-- copy in Studio is whatever was imported LAST. That has now cost two separate rounds of
-- debugging -- a flume that was not there because Hall_Slide had never been imported, and an
-- arch whose opening was still in the old place because Hall_ArchWall had not been re-imported
-- after the geometry moved. In both cases the code was right, the level was wrong, and there
-- was nothing in the Output to say which.
--
-- A mesh cannot carry a version number through an FBX import, but it carries its SIZE, and
-- every one of those edits changed one. So the sizes the generator currently produces are
-- written down here and checked on the way in. It does not fix anything; it turns "the bug is
-- still there" into a line naming the file to re-import.
--
-- REGENERATE THIS TABLE rather than editing it: gen_flooded_halls.py prints it, ready to
-- paste, every time it runs.
local EXPECTED_SIZE: { [string]: Vector3 } = {
	Hall_ArchWall = Vector3.new(24.000, 22.000, 2.300),
	Hall_Column = Vector3.new(10.336, 22.000, 10.336),
	Hall_Vault = Vector3.new(26.000, 9.200, 24.000),
	Hall_CurveWall = Vector3.new(18.800, 22.000, 18.800),
	Hall_Steps = Vector3.new(11.400, 9.598, 11.420),
	Hall_Dome = Vector3.new(78.120, 17.624, 78.120),
	Hall_Hand = Vector3.new(4.259, 10.000, 1.675),
	Hall_Cove = Vector3.new(24.000, 1.600, 1.600),
	Hall_Rail = Vector3.new(0.520, 10.689, 9.919),
	Hall_Slide = Vector3.new(23.560, 31.540, 23.560),
	Hall_Ripple = Vector3.new(2.200, 0.100, 2.188),
}

local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("FloodedHallsService: " .. message)
end

-- EITHER FOLDER, because either is a reasonable guess.
--
-- Assets holds two mesh folders and the split is historical rather than principled:
-- TileMeshes started as chunk platforms and became the place everything goes, while Backdrop
-- is a private namespace of Backdrop_* props that only BackdropService reads.
--
-- The halls are genuinely both. LevelDefinitions calls them a backdrop, because that field is
-- what distinguishes one level from another -- but they are the room the player is standing
-- in, which is nothing like a horizon. Checking both costs one lookup and removes the
-- question; the warning names both, so a piece that really is missing is obvious.
local function kitMesh(name: string): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local found: Instance? = nil
	for _, folderName in ipairs({ "TileMeshes", "Backdrop" }) do
		local folder = assets and assets:FindFirstChild(folderName)
		found = folder and folder:FindFirstChild(name)
		if found then
			break
		end
	end
	-- The importer often leaves a Model wrapping the MeshPart. Reach through it rather than
	-- making everyone unwrap by hand.
	if found and not found:IsA("BasePart") then
		found = found:FindFirstChildWhichIsA("BasePart", true)
	end
	if not (found and found:IsA("BasePart")) then
		warnOnce("nokit_" .. name, name .. " is in neither Assets/TileMeshes nor "
			.. "Assets/Backdrop, so the halls are missing it. Run "
			.. "blender/gen_flooded_halls.py and import the kit.")
		return nil
	end

	-- SEE EXPECTED_SIZE. A tenth is a wide tolerance on purpose: it has to ignore whatever the
	-- importer rounds off and still catch a piece whose geometry has actually moved, and every
	-- edit that has caused trouble changed a dimension by a good deal more than that.
	local want = EXPECTED_SIZE[name]
	if want then
		local got = found.Size
		local drifted = math.abs(got.X - want.X) > want.X * 0.1
			or math.abs(got.Y - want.Y) > want.Y * 0.1
			or math.abs(got.Z - want.Z) > want.Z * 0.1
		if drifted then
			warnOnce("stale_" .. name, ("the %s in Assets measures %.1f x %.1f x %.1f, and the "
				.. "generator currently builds it %.1f x %.1f x %.1f. This is an OLD IMPORT: "
				.. "re-run blender/gen_flooded_halls.py and re-import this one piece. Whatever "
				.. "you were expecting to have changed about it has not.")
				:format(name, got.X, got.Y, got.Z, want.X, want.Y, want.Z))
		end
	end
	return found
end

-- TILED, ALWAYS. Every surface in this level is the same ceramic, so this is the one place
-- that decides what that means.
local function dressTile(part: BasePart)
	part.Material = Enum.Material.CeramicTiles
	part.Color = TILE_COLOUR
	part.Anchored = true
	part.CastShadow = true
end

-- ===== WHERE THE ROUTE IS, AND WHAT MAY STAND NEAR IT =====
--
-- Module-level because every placement helper needs them and threading them through twenty
-- call sites is how one of them ends up with a stale copy.
local hallOrigin = Vector3.zero
local hallRoute: HallRoute.Route = HallRoute.build(1)
-- World Y of the flooded floor's top surface.
local hallFloorY = 0
-- The walkway's own height, which the lane guard needs: see WALK_BAND below.
local hallSurfaceY = 0
local laneWarned = false

-- ===== HOW FAR ABOVE AND BELOW THE WALKWAY COUNTS AS "IN THE WAY" =====
--
-- The lane rule used to be about PLAN alone: nothing solid within thirty studs of the
-- centreline, at any height whatsoever. That is the right rule for a wall and far too strong
-- for a building, because it also forbids everything a walkway over water actually needs --
-- the piers holding it up, the beams over it, the lane markings on the floor beneath it.
--
-- The thing being protected is not a column of space, it is a person. A character is five
-- studs tall and clears about six and a half, so fourteen above the deck is their head, their
-- jump and a margin; four below catches anything that could stand proud of the walking surface.
--
-- MEASURED RATHER THAN GENEROUS, and that distinction matters. The first version used
-- thirty-four, which sounds safely conservative and is not: it swallows the ceiling beams, so
-- every beam had to be waved through with `free` -- and a piece marked `free` is a piece
-- nothing checks, forever, including after somebody lowers the ceiling. A band that is honest
-- about what a person occupies is the one that leaves the most things genuinely checked.
local WALK_BAND_BELOW = 4
local WALK_BAND_ABOVE = 14
-- ===== WHERE THE LAST ROOM IS =====
--
-- Known BEFORE the corridor is built, because the corridor has to get out of its way.
--
-- The route does not end at a tidy place. It ends wherever forty-four chunks happen to run
-- out, and simulating that showed the common case is the awkward one: the route turns a corner
-- and stops seventy studs later, so the last chamber lands ON TOP of that junction. Built in
-- ignorance, the junction puts two full-height walls across the middle of the room and the
-- corridor's own walls run out into open floor inside it.
--
-- So the chamber is a fact the rest of the builder can test against rather than a thing that
-- happens at the end. Anything whose position falls inside it is left to the chamber.
local chamberAt = Vector3.zero
local chamberHalf = 0

-- ===== THE SUNKEN BASINS =====
--
-- Chosen while the bays are being built, because that is the only place that knows which bays
-- already have something in them -- and built afterwards, because each one is a hole in three
-- different surfaces that are laid down in one piece each.
export type Basin = {
	at: Vector3,
	half: number,
	depth: number,
	-- Which way is the walkway, so the steps face it and the rail stands on the right side.
	inward: Vector3,
	along: Vector3,
}
local hallBasins: { Basin } = {}

-- ===== THE POOL, PER LEG =====
--
-- One box per leg, chosen before anything is built because the piers stand in it and the floor
-- and the water are cut round it. Laid out so neighbouring boxes TOUCH and never overlap: a leg's
-- box runs on past its corner by the pool's half-width, and the next leg's starts that far along,
-- so the two meet on a line and the corner square belongs to exactly one of them. Overlapping
-- boxes would put two floors and two columns of water in the same place.
export type Pool = {
	leg: HallRoute.Leg,
	from: number,
	to: number,
	first: boolean,
	last: boolean,
	box: { minX: number, maxX: number, minZ: number, maxZ: number },
}
local hallPools: { Pool } = {}

local function poolUnder(where: Vector3): boolean
	for _, pool in ipairs(hallPools) do
		local box = pool.box
		if where.X > box.minX and where.X < box.maxX and where.Z > box.minZ and where.Z < box.maxZ then
			return true
		end
	end
	return false
end

-- Where the ceiling opens up, if anywhere. Recorded as a flat rectangle because that is what
-- the ceiling plate needs, plus the leg it sits on so the walls can be placed in its frame.
local hallTall: {
	leg: HallRoute.Leg,
	from: number,
	to: number,
	box: { minX: number, maxX: number, minZ: number, maxZ: number },
}? = nil

local function insideChamber(where: Vector3): boolean
	if chamberHalf <= 0 then
		return false
	end
	return math.abs(where.X - chamberAt.X) < chamberHalf
		and math.abs(where.Z - chamberAt.Z) < chamberHalf
end

-- ===== NOTHING IN THE LANE =====
--
-- The rule the whole level exists to keep, enforced rather than remembered.
--
-- The previous guard measured |x| from the origin, which is the distance to the route only
-- while the route runs along one axis. The moment it turned a corner that guard was measuring
-- nothing and passing everything -- a check that cannot fail is worse than no check, because
-- it is also a claim.
--
-- This one measures to the actual polyline, and it SAMPLES the part's footprint rather than
-- using its centre or its bounding radius. A centre test misses a long wall that crosses the
-- lane end-on; a bounding-radius test flags every long wall that runs safely alongside it. A
-- grid of points a good deal finer than the lane is half the width catches both.
local function guardLane(cf: CFrame, size: Vector3, name: string)
	if laneWarned then
		return
	end
	-- ONLY THINGS THAT COULD BE IN THE WAY. Every rotation in this level is about Y, so size.Y
	-- is always the true vertical extent and this test is exact rather than conservative.
	local top = cf.Position.Y + size.Y / 2
	local bottom = cf.Position.Y - size.Y / 2
	if top < hallSurfaceY - WALK_BAND_BELOW or bottom > hallSurfaceY + WALK_BAND_ABOVE then
		return
	end
	local acrossX = math.max(1, math.ceil(size.X / 24))
	local acrossZ = math.max(1, math.ceil(size.Z / 24))
	local closest = math.huge
	for ix = 0, acrossX do
		for iz = 0, acrossZ do
			local spot = cf * CFrame.new(
				-size.X / 2 + (ix / acrossX) * size.X, 0,
				-size.Z / 2 + (iz / acrossZ) * size.Z)
			local flat = Vector3.new(spot.Position.X - hallOrigin.X, 0,
				spot.Position.Z - hallOrigin.Z)
			local gap = HallRoute.distanceTo(hallRoute, flat)
			if gap < closest then
				closest = gap
			end
		end
	end
	if closest < LANE_HALF then
		laneWarned = true
		warn(("FloodedHallsService: %s comes within %.0f studs of the route, inside the "
			.. "%d-stud lane the chunks run down -- it will be inside the walkway. Move it "
			.. "outward or narrow the lane."):format(name, closest, LANE_HALF))
	end
end

export type Options = {
	-- Allowed in the lane on purpose: the gangway, the flume, the pit.
	free: boolean?,
	-- Painted as the void rather than as tile.
	dark: boolean?,
	-- Positioned by its own centre rather than stood on the given height. For the few pieces
	-- that float -- the hand under the water, the flume hanging in its shaft.
	centred: boolean?,
	-- Hung from the given height instead of stood on it: the mesh's TOP lands there. For the
	-- pieces modelled going downward, of which the steps are the only one.
	hang: boolean?,
}

local function slab(parent: Instance, cf: CFrame, size: Vector3, name: string,
	options: Options?): Part
	local opts: Options = options or {}
	if not opts.free then
		guardLane(cf, size, name)
	end
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	dressTile(part)
	if opts.dark then
		part.Material = Enum.Material.SmoothPlastic
		part.Color = VOID_COLOUR
		part.Reflectance = 0
	end
	part.Parent = parent
	return part
end

-- WOOD, for the few things in this building that were fitted rather than built: the gangway out to
-- the flume and the lifeguard's chair. Not tile, and not run past the lane guard -- the gangway is
-- in the lane on purpose, because it is walked on.
local function timber(parent: Instance, cf: CFrame, size: Vector3, name: string,
	colour: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	part.Material = Enum.Material.Wood
	part.Color = colour
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A frame centred between two points, its Z axis running from one to the other and its Y axis as
-- close to `normal` as that allows. For anything that is a member between two points: a stave of
-- the flume, a brace, a chair leg, a rib. Right-handed by construction, since X is Y cross Z.
local function spanFrame(from: Vector3, to: Vector3, normal: Vector3): (CFrame, number)
	local run = to - from
	local length = run.Magnitude
	local along = run / length
	local lift = (normal - along * normal:Dot(along)).Unit
	return CFrame.fromMatrix(from:Lerp(to, 0.5), lift:Cross(along), lift, along), length
end

-- A fitting that is neither tile nor wood: a clock, a rail, a lamp. Not solid unless the caller
-- says so, because almost none of these is anything to stand on.
local function fitting(parent: Instance, name: string, size: Vector3, cf: CFrame, colour: Color3,
	material: Enum.Material, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cf
	part.Anchored = true
	part.CanCollide = false
	part.Material = material
	part.Color = colour
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- ===== A TILED WALL, DRESSED =====
--
-- Every full-height wall in the level goes through here -- the corridor's sides, the junctions,
-- the arch returns, the chamber, the entrance and its passage -- so they all carry the same
-- courses and meet each other at the same heights. Before this only the corridor walls had a
-- dado, and it stopped dead at every junction.
--
--   THE WAINSCOT, below the dado, in WAINSCOT_COLOUR.
--   THE DADO, a trim bullnose at the change of colour. Standing proud of BOTH faces, because an
--   arch return is seen from both sides and a perimeter wall's outside is never seen at all.
--   ONE ACCENT STRIPE a little under it.
--   A TWO-STEP CORNICE where the wall meets the ceiling, which was a bare right angle.
--
-- `bottom` is how high the wall starts, for the lintel pieces over doorways; a course that
-- falls outside the wall is skipped. The thin horizontal axis of `size` is taken as the
-- thickness, since every caller builds walls in a different frame.
local WAINSCOT = HEIGHT * 0.42

local function tiledWall(parent: Instance, cf: CFrame, size: Vector3, name: string,
	options: Options?, bottom: number?)
	local base = bottom or 0
	local top = base + size.Y
	local thickX = size.X < size.Z
	local function offset(height: number): number
		return height - base - size.Y / 2
	end
	local function course(height: number, tall: number, proud: number, courseName: string,
		colour: Color3)
		if height - tall / 2 < base or height + tall / 2 > top + 0.01 then
			return
		end
		local across = (if thickX then size.X else size.Z) + proud * 2
		local long = if thickX then size.Z else size.X
		local part = slab(parent, cf * CFrame.new(0, offset(height), 0),
			if thickX then Vector3.new(across, tall, long) else Vector3.new(long, tall, across),
			courseName, options)
		part.Color = colour
		part.CanCollide = false
	end

	if base < WAINSCOT and top > WAINSCOT then
		local lower = slab(parent, cf * CFrame.new(0, offset((base + WAINSCOT) / 2), 0),
			Vector3.new(size.X, WAINSCOT - base, size.Z), name, options)
		lower.Color = WAINSCOT_COLOUR
		slab(parent, cf * CFrame.new(0, offset((WAINSCOT + top) / 2), 0),
			Vector3.new(size.X, top - WAINSCOT, size.Z), name, options)
	else
		local whole = slab(parent, cf, size, name, options)
		if top <= WAINSCOT then
			whole.Color = WAINSCOT_COLOUR
		end
	end
	course(WAINSCOT, SCALE * 1.6, SCALE * 0.8, "Dado", TRIM_COLOUR)
	course(WAINSCOT - 4, 1.8, SCALE * 0.3, "TileStripe", ACCENT_TILE)
	course(HEIGHT - 1.6, 3.2, SCALE * 0.75, "Cornice", TRIM_COLOUR)
	course(HEIGHT - 4, 1.6, SCALE * 0.4, "Cornice", TRIM_COLOUR)
end

-- A kit mesh, grown to match and standing ON the given height rather than centred at it.
--
-- ROBLOX POSITIONS A MESHPART BY ITS BOUNDING-BOX CENTRE, and the kit is modelled standing on
-- z = 0, so passing the floor's CFrame straight through buries the bottom half of every column
-- in the floor. The size is only known after the clone, which is why the lift happens here
-- rather than at the call site -- every caller getting it right is not a plan.
local function piece(parent: Instance, meshName: string, cf: CFrame,
	options: Options?): BasePart?
	local opts: Options = options or {}
	local template = kitMesh(meshName)
	if not template then
		return nil
	end
	local made = template:Clone()
	made.Name = meshName
	-- GROWN TO MATCH. The meshes are modelled at scale 1 and every measurement above is
	-- multiplied by SCALE, so a mesh dropped in at import size would be a doll's-house arch in
	-- a cathedral-sized wall. Size scales about the part's own centre.
	made.Size = made.Size * SCALE
	-- THREE WAYS UP, and the right one is a property of the mesh rather than of the call site.
	--
	-- Roblox positions a MeshPart by its bounding-box CENTRE. The kit is modelled standing on
	-- z = 0, so most pieces want lifting by half their height to stand on a floor. The steps
	-- are modelled going DOWN from z = 0, so the same lift stands a flight of descending steps
	-- in the air above the bay it descends into. And a few pieces float and want neither.
	local lift = if opts.centred then 0 elseif opts.hang then -made.Size.Y / 2 else made.Size.Y / 2
	made.CFrame = cf * CFrame.new(0, lift, 0)
	if not opts.free then
		guardLane(made.CFrame, made.Size, meshName)
	end
	dressTile(made)
	made.Parent = parent
	return made
end

-- A LIT OPENING: the glowing panel, plus the light it actually casts.
--
-- Neon alone is a bright rectangle and lights nothing, and a bright rectangle in a flat room
-- reads as a screen rather than as a window. The PointLight is what turns it into a source: it
-- picks out the tile relief on the surrounding wall, and grout lines catching light at a
-- grazing angle is most of what says "tiled" from across a room.
local function lightPanel(parent: Instance, cf: CFrame, size: Vector3, brightness: number,
	overhead: boolean?)
	-- ===== THE REVEAL =====
	--
	-- A window in a two-stud wall is a TUNNEL, not a rectangle, and that tunnel is where the
	-- soft gradient in every reference comes from: light entering at an angle strikes the
	-- inside faces of the opening before it reaches the room, so the frame is lit from within
	-- and fades from blinding at the outer edge to nothing at the inner. A flat glowing panel
	-- flush with the wall has no inside faces and therefore no gradient.
	--
	-- === WHICH FACE IS LEFT OPEN ===
	--
	-- A reveal is four sides of an opening and the fifth has to be the way the light comes out.
	-- For a window in a wall that is the panel's own +/- Z, and the frame goes above, below and
	-- to each side. For an opening in a CEILING it is the underside, and the frame goes round
	-- it in plan.
	--
	-- THE SKYLIGHTS WERE BUILT WITH THE WALL FRAME, which put a tiled plate directly under each
	-- one, flush with its bottom face. They were sealed. Every skylight in the level has been
	-- lighting the inside of its own lid, and the only light source whose range could reach the
	-- middle of the hall was the one that was switched off.
	local jamb = 0.9
	local frame = if overhead then {
		{ Vector3.new(size.X + jamb * 2, jamb * 2, jamb), Vector3.new(0, 0, size.Z / 2 + jamb / 2) },
		{ Vector3.new(size.X + jamb * 2, jamb * 2, jamb), Vector3.new(0, 0, -size.Z / 2 - jamb / 2) },
		{ Vector3.new(jamb, jamb * 2, size.Z + jamb * 2), Vector3.new(size.X / 2 + jamb / 2, 0, 0) },
		{ Vector3.new(jamb, jamb * 2, size.Z + jamb * 2), Vector3.new(-size.X / 2 - jamb / 2, 0, 0) },
	} else {
		{ Vector3.new(size.X + jamb * 2, jamb, size.Z + 1.6), Vector3.new(0, size.Y / 2, 0) },
		{ Vector3.new(size.X + jamb * 2, jamb, size.Z + 1.6), Vector3.new(0, -size.Y / 2, 0) },
		{ Vector3.new(jamb, size.Y, size.Z + 1.6), Vector3.new(size.X / 2, 0, 0) },
		{ Vector3.new(jamb, size.Y, size.Z + 1.6), Vector3.new(-size.X / 2, 0, 0) },
	}
	for _, spec in ipairs(frame) do
		local reveal = Instance.new("Part")
		reveal.Name = "Reveal"
		reveal.Size = spec[1]
		reveal.CFrame = cf * CFrame.new(spec[2])
		reveal.Material = Enum.Material.CeramicTiles
		reveal.Color = TILE_COLOUR
		reveal.Anchored = true
		reveal.CastShadow = true
		reveal.Parent = parent
	end

	local panel = Instance.new("Part")
	panel.Name = "LightSlot"
	panel.Size = size
	panel.CFrame = cf
	panel.Anchored = true
	panel.CanCollide = false
	panel.CastShadow = false
	panel.Material = Enum.Material.Neon
	panel.Color = GLOW_COLOUR
	panel.Parent = parent

	if not overhead then
		local light = Instance.new("PointLight")
		light.Color = GLOW_COLOUR
		-- DIMMER AND SHORTER-RANGED than the first pass, and the range matters more than the
		-- brightness. A 160-stud range from a window in every other bay means every point in
		-- the hall is lit by four windows at once, which is not a row of windows, it is a
		-- ceiling panel.
		light.Brightness = brightness * 0.26
		light.Range = 22 * SCALE
		light.Shadows = true
		light.Parent = panel
		return panel
	end

	-- ===== A CEILING LIGHT IS NOT A GLOWING RECTANGLE =====
	--
	-- Neon renders at full brightness with a hard edge, and a PointLight radiates from a point.
	-- Put those together in a ceiling and you get exactly what it looked like: a white slab
	-- with a square of light projected on the floor underneath it, both of which announce that
	-- a rectangle was placed there.
	--
	-- A real ceiling fitting is three things, and it is worth having all three because this is
	-- now the key light in the level:
	--
	--   A DIFFUSER. The bright element is never what you see -- you see a milky panel WITH the
	--   element behind it. One near-transparent plate under the Neon does that, and it is the
	--   single biggest step away from "glowing rectangle": the edge stops being a step from
	--   full white to ceiling and becomes a gradient across the plate's thickness.
	--
	--   (THERE WAS A HALO HERE AND IT HAD TO GO. The idea was to soften the fitting's outline
	--   with two larger, fainter Neon plates below it. It does not work, and the reason is
	--   worth writing down because this is the SECOND time the same idea has failed in this
	--   level: Neon in Roblox is not a glow, it is a surface that ignores lighting. At any
	--   transparency where it contributes anything at all it reads as a solid white sheet, so
	--   the halo arrived as a large rectangular panel hanging under the ceiling -- the exact
	--   complaint, and exactly what the fake volumetric light shafts did before it.
	--
	--   LIGHT IN THIS ENGINE COMES FROM LIGHT OBJECTS. Geometry pretending to be light is
	--   geometry, and it will be seen as geometry from some angle. The SurfaceLight below is
	--   what softens the pool of light; the fitting's own outline is softened by the diffuser,
	--   which works because it is the size of the fitting rather than a plate around it.)
	--
	--   A DIRECTION. A SurfaceLight emits from one face within a cone, so it washes down onto
	--   the walkway instead of radiating a sphere that happens to be inside a ceiling. It is
	--   the difference between a projected square and a lit room, it costs the same as the
	--   PointLight it replaces, and it is why the pool of light has soft edges at all.
	panel.Transparency = 0.12

	local diffuser = Instance.new("Part")
	diffuser.Name = "Diffuser"
	diffuser.Size = Vector3.new(size.X + 1.2, size.Y * 0.5, size.Z + 1.2)
	diffuser.CFrame = cf * CFrame.new(0, -size.Y * 0.55, 0)
	diffuser.Anchored = true
	diffuser.CanCollide = false
	diffuser.CastShadow = false
	-- SEE WATER_MATERIAL. This one hangs directly over the walkway, so it was the worst-placed
	-- piece of glass in the level for exactly the platforms that were vanishing.
	diffuser.Material = Enum.Material.SmoothPlastic
	diffuser.Color = GLOW_COLOUR
	diffuser.Transparency = 0.45
	diffuser.Parent = parent

	local wash = Instance.new("SurfaceLight")
	wash.Face = Enum.NormalId.Bottom
	-- WIDE, but not a hemisphere. At 180 a SurfaceLight is a PointLight with extra steps; at
	-- 150 the pool of light still reaches the walls and still has a soft edge on the way.
	wash.Angle = 150
	wash.Color = GLOW_COLOUR
	wash.Brightness = brightness * 0.42
	wash.Range = 26 * SCALE
	wash.Shadows = true
	wash.Parent = panel
	return panel
end

-- ===== THE LIGHT SHAFTS ARE GONE, AND THAT IS THE FIX FOR SOMETHING ELSE =====
--
-- There used to be a lightShaft() here: a tall, very transparent Neon box under every skylight,
-- standing in for the volumetric beam Roblox cannot render. It never worked -- at any
-- transparency where you could see it at all, it read as a pale slab standing in the room,
-- which is the failure mode of every fake volumetric once it becomes legible as an object.
--
-- IT WAS ALSO COSTING SOMETHING MUCH WORSE THAN ITSELF.
--
-- Roblox sorts transparent surfaces per object and does not depth-write them, so overlapping
-- translucent things drop out of each other in ways that change with the viewing angle. This
-- level has a lot of them: the water, the ripples, the diffusers, the halos -- and the CHUNKS,
-- because slime, honey and jello soda are translucent and they are the things a player is
-- actually looking at. Stack four transparent layers between the camera and a slime platform
-- and the platform is the one that loses, which is exactly the reported bug: invisible from
-- above, fine from the side, with only the opaque parts of the chunk still drawn.
--
-- So the largest transparent objects that were nowhere near essential have gone, and the
-- ceiling halo is down from two plates to one. The SurfaceLight does the job the shaft was
-- pretending to do, and it does it with no surface at all.

-- ===== BUILDING IN A LEG'S OWN FRAME =====
--
-- Every leg of the corridor is the same corridor, so it would be absurd to write the bay loop
-- once per direction. `lateral` is studs to the left of the centreline, `along` is studs from
-- the leg's start, `height` is studs above the flooded floor -- and the returned CFrame is
-- already rotated to the leg, so a wall's Size can be stated as (thickness, height, length)
-- whichever way the corridor happens to be running.
local function legFrame(leg: HallRoute.Leg, along: number, lateral: number,
	height: number): CFrame
	local side = Vector3.new(leg.dir.Z, 0, -leg.dir.X)
	local flat = leg.from + leg.dir * along + side * lateral
	return CFrame.fromMatrix(
		hallOrigin + Vector3.new(flat.X, hallFloorY + height, flat.Z),
		side, Vector3.new(0, 1, 0), leg.dir)
end

-- ===== THE TRANSVERSE ARCH, BUILT HERE RATHER THAN IMPORTED =====
--
-- This used to be Hall_ArchWall, and it has been reported broken three times running.
--
-- The mesh was wrong the first time, I fixed it, and it stayed wrong -- because nothing in this
-- project syncs, so a corrected mesh only helps once somebody re-exports and re-imports it, and
-- there is no way to tell from inside the game which of those has happened. I added a size
-- check that names a stale import, and that is worth having, but it still leaves the one piece
-- the route runs THROUGH depending on a manual step to not be a wall across the level.
--
-- So it is not a mesh any more. An arched opening is a rectangle with the corners filled in;
-- filling them with a dozen boxes stepped along the curve is what a masonry arch actually is,
-- it costs twenty-seven parts in a level that has hundreds, and it cannot be out of date.
--
-- The clearances are stated here as studs rather than inherited from a model's proportions,
-- which is the other half of why this kept going wrong: the mesh was authored against its own
-- 22-unit wall height and had never been told where the walkway crossed it.
local ARCH_SPAN = 40          -- half the opening's width, at the springing
local ARCH_SPRING = 40        -- how high above the flooded floor the curve starts
local ARCH_RINGS = 12         -- voussoirs per side

local function buildArchway(halls: Model, leg: HallRoute.Leg, along: number)
	local head = ARCH_SPRING + ARCH_SPAN

	-- The piers, either side of the opening and full height.
	for _, side in ipairs({ 1, -1 }) do
		local from = ARCH_SPAN
		local to = HALL_HALF_WIDTH - WALL_THICK / 2
		if to - from > 1 then
			tiledWall(halls, legFrame(leg, along, side * (from + to) / 2, HEIGHT / 2),
				Vector3.new(to - from, HEIGHT, WALL_THICK), "ArchPier")
		end
	end

	-- The wall above the crown.
	if HEIGHT - head > 1 then
		slab(halls, legFrame(leg, along, 0, (head + HEIGHT) / 2),
			Vector3.new(ARCH_SPAN * 2, HEIGHT - head, WALL_THICK), "ArchHead",
			{ free = true })
	end

	-- THE CURVE, as voussoirs. Each course fills from the circle out to the pier on both sides,
	-- so the opening narrows the way an arch does. Stepped rather than smooth on purpose: a
	-- real arch is cut blocks, and at this scale the steps read as the joints between them.
	local course = ARCH_SPAN / ARCH_RINGS
	for index = 0, ARCH_RINGS - 1 do
		local rise = (index + 0.5) * course
		local open = math.sqrt(math.max(0, ARCH_SPAN * ARCH_SPAN - rise * rise))
		local fill = ARCH_SPAN - open
		if fill > 0.5 then
			for _, side in ipairs({ 1, -1 }) do
				slab(halls, legFrame(leg, along, side * (open + fill / 2),
					ARCH_SPRING + rise), Vector3.new(fill, course, WALL_THICK),
					"Voussoir", { free = true })
			end
		end
	end
end

-- ===== A BLIND DOORWAY, down at the water =====
--
-- An opening in the wall with nothing behind it: no room, no light, no sill, just a dark rectangle
-- at the far side of the water where a door plainly used to go somewhere.
--
-- It is the cheapest liminal thing in the level and possibly the most effective, and it works
-- BECAUSE it is out of reach -- fifty studs below the walkway, across water, with no way down to
-- it. Anything you could walk up to and find solid is a prop. Something you can only ever look at
-- stays a question.
--
-- LOW ENOUGH TO CLEAR THE WAINSCOT'S STRIPE. At half a bay tall the dado ran straight across the
-- top of every doorway, which reads as a shelf over a hole rather than as a door.
local function buildDoorway(halls: Model, leg: HallRoute.Leg, along: number, side: number)
	local tall = BAY * 0.28
	local wide = BAY * 0.26
	local into = legFrame(leg, along, side * (HALL_HALF_WIDTH - WALL_THICK * 0.25), tall / 2)
	local hole = slab(halls, into, Vector3.new(WALL_THICK, tall, wide), "Doorway")
	hole.Color = Color3.fromRGB(12, 14, 14)
	hole.Material = Enum.Material.SmoothPlastic
	hole.Reflectance = 0
	-- The architrave: a tiled surround standing proud of the wall, which is what makes the dark
	-- rectangle read as an opening rather than as a stain.
	for _, jamb in ipairs({
		{ Vector3.new(WALL_THICK * 0.5, tall + SCALE, SCALE), 0, wide / 2 + SCALE / 2 },
		{ Vector3.new(WALL_THICK * 0.5, tall + SCALE, SCALE), 0, -wide / 2 - SCALE / 2 },
		{ Vector3.new(WALL_THICK * 0.5, SCALE, wide + SCALE * 2), tall / 2 + SCALE / 2, 0 },
	}) do
		-- TOWARDS THE ROOM, whichever wall this is. legFrame's X axis is the leg's left vector
		-- and does not flip with `side`, so a fixed offset would stand the surround proud on one
		-- wall and bury it inside the other.
		local trim = slab(halls, into * CFrame.new(-side * WALL_THICK * 0.45, jamb[2] :: number,
			jamb[3] :: number), jamb[1] :: Vector3, "Architrave")
		trim.Color = TRIM_COLOUR
	end
end

-- ===== A BLIND NICHE =====
--
-- A round-headed recess in the upper wall, in the panels that have no window. The upper wall was
-- forty studs of blank tile between one window and the next; this is what every tiled hall of the
-- period puts there, and it costs four parts.
--
-- Built as two layers, each a slab with a cylinder for its head: a trim frame, and a darker panel
-- inside it standing a fraction further forward. Each face sits an eighth of a stud off the one
-- behind it, so nothing is ever coplanar enough to shimmer; the darker colour is what reads as
-- the recess.
local function buildNiche(halls: Model, leg: HallRoute.Leg, along: number, side: number)
	local face = HALL_HALF_WIDTH - WALL_THICK / 2
	local from = HEIGHT * 0.52
	local springing = HEIGHT * 0.8
	for _, layer in ipairs({
		{ BAY * 0.2 + SCALE * 1.5, 1.0, SCALE * 0.75, TRIM_COLOUR },
		{ BAY * 0.2, 1.24, 0, NICHE_COLOUR },
	}) do
		local wide = layer[1] :: number
		local proud = layer[2] :: number
		local bottom = from - (layer[3] :: number)
		local body = slab(halls, legFrame(leg, along, side * face, (bottom + springing) / 2),
			Vector3.new((proud + 0.12) * 2, springing - bottom, wide), "Niche")
		body.Color = layer[4] :: Color3
		body.CanCollide = false
		-- A Roblox cylinder lies along its X axis, and legFrame's X is across the hall -- which is
		-- the wall's normal, so the disc faces the room with no turn at all.
		local head = slab(halls, legFrame(leg, along, side * face, springing),
			Vector3.new(proud * 2, wide, wide), "Niche")
		head.Shape = Enum.PartType.Cylinder
		head.Color = layer[4] :: Color3
		head.CanCollide = false
	end
end

-- One leg: two walls, a window rhythm, a colonnade, and whatever else lands in its bays.
local function buildLeg(halls: Model, leg: HallRoute.Leg, legIndex: number, isLast: boolean,
	rng: Random)
	-- Where the walls start and stop. A junction is a square as wide as the corridor, so the
	-- side walls have to hold off by that much at any end that has one; the very first end is
	-- closed off instead, and the very last runs into the chamber.
	local from = if legIndex == 1 then -BAY * 0.5 else HALL_HALF_WIDTH
	local to = if isLast then leg.length else leg.length - HALL_HALF_WIDTH
	-- AND OUT OF THE LAST ROOM. Walked back rather than solved for: the leg is axis-aligned
	-- and so is the chamber, so stepping is exact to within its step and costs nothing at all
	-- next to being wrong.
	while to > from and insideChamber(legFrame(leg, to, 0, 0).Position) do
		to -= 4
	end
	local span = to - from
	if span <= 0 then
		return
	end
	-- THE FIRST LEG'S WALLS RUN BACK PAST THE START to the entrance's end wall. The bays still
	-- begin where they did, so every column, arch and light keeps its place; only the walls, the
	-- stain and the moulding along them reach back to meet buildEntrance.
	local wallFrom = if legIndex == 1 then -ENTRANCE_DEPTH else from
	local wallSpan = to - wallFrom

	for _, side in ipairs({ 1, -1 }) do
		-- ONE SLAB PER SIDE, not one per bay. A seam every ninety-six studs along the exact
		-- line the eye follows is the one place a seam is guaranteed to be seen.
		tiledWall(halls, legFrame(leg, wallFrom + wallSpan / 2, side * HALL_HALF_WIDTH, HEIGHT / 2),
			Vector3.new(WALL_THICK, HEIGHT, wallSpan), "Wall")

		-- ===== THE TIDE LINE =====
		--
		-- A band of darker, wetter tile at the waterline, running the whole length of the wall
		-- without a break.
		--
		-- This is the single most characteristic thing about a room that has been under water
		-- for years, and it does two jobs at once. It says the water has been at this exact
		-- height long enough to stain the tile, which is a fact about TIME rather than about
		-- depth. And because it is dead level over hundreds of studs while everything else
		-- recedes into haze, it is the one line in the level the eye can use to judge distance
		-- and to tell that the floor has not tilted.
		--
		-- Cheap: one part per wall per leg. It is also the reason the walls are single slabs --
		-- a per-bay wall would need a per-bay stain, and the joins between them would break the
		-- one property that makes it work.
		local tide = slab(halls, legFrame(leg, wallFrom + wallSpan / 2,
			side * (HALL_HALF_WIDTH - WALL_THICK / 2 - 0.6), WATER_DEPTH + 1.4),
			Vector3.new(1.2, WATER_DEPTH * 1.5, wallSpan), "TideLine")
		tide.Color = Color3.fromRGB(126, 138, 118)
		-- Glossier than dry tile, because it is wet. That is what makes the band catch the
		-- pool lighting below it and read as a stain rather than as a painted stripe.
		tide.Reflectance = 0.16
		tide.CanCollide = false
	end

	-- (THE DADO is laid by tiledWall now, with the rest of the courses, on every wall in the level
	-- rather than on the corridor's sides alone.)

	-- (THE LANE STRIPES are on the pool's floor now, where lane stripes go: see buildPools. On the
	-- shallows they ran under the column bases and across every basin.)

	-- ===== THE CEILING, COFFERED =====
	--
	-- The ceiling is the largest surface in the level and was the plainest: one flat plate with a
	-- beam every bay. Four ribs down the length of each leg -- two on the column lines, carrying
	-- the colonnade up into the roof, and two framing the rooflights over the walkway -- turn it
	-- into a grid of coffers with the beams. Every coffer is a pool of shadow and every rib a lit
	-- edge, which is a ceiling with depth for eight parts a leg.
	--
	-- NOT OVER THE TALL HALL, whose ceiling is open to the glazed roof: a rib crossing it would be
	-- a beam hanging in the air.
	local ceilingRuns: { { number } } = { { wallFrom, to } }
	local tall = hallTall
	if tall and tall.leg == leg then
		ceilingRuns = { { wallFrom, tall.from }, { tall.to, to } }
	end
	for _, run in ipairs(ceilingRuns) do
		local a, b = run[1], run[2]
		if b - a > 2 then
			for _, lateral in ipairs({ -(LANE_HALF + BAY * 0.3), -BAY * 0.21, BAY * 0.21,
				LANE_HALF + BAY * 0.3 }) do
				local rib = slab(halls, legFrame(leg, (a + b) / 2, lateral, HEIGHT - SCALE * 0.45),
					Vector3.new(SCALE * 0.9, SCALE * 0.9, b - a), "CeilingRib")
				rib.CanCollide = false
			end
		end
	end

	-- THE BAY RHYTHM. In the references the wall is never the subject -- what you see is the
	-- rhythm of openings along it receding into haze.
	local bays = math.max(1, math.floor(span / BAY))
	-- HOW FAR A LIGHT AT THE WALL IS FROM THE WALKWAY. Stated once so the rooflight below can
	-- say what it is for, and so the number is visible rather than buried in a range.
	local wallToLane = HALL_HALF_WIDTH - WALL_THICK * 0.4
	for bay = 1, bays do
		local along = from + (bay - 0.5) * (span / bays)
		if insideChamber(legFrame(leg, along, 0, 0).Position) then
			continue
		end
		-- ===== THE ROOFLIGHT, WHICH IS THE ONE THAT MATTERS =====
		--
		-- A slot in the ceiling directly over the route, and it exists because NOTHING WAS
		-- LIGHTING THE WALKWAY AT ALL.
		--
		-- The hall is 211 studs across, so a light on the wall is 102 studs from the
		-- centreline. The windows had a range of 88 and the pool slots 52, which means they
		-- stopped 14 and 50 studs short of the middle -- and the middle is the only part of
		-- this level anyone stands on. The walls looked superb and the platforms rendered as
		-- black silhouettes, which is exactly what a room lit entirely from its edges does.
		--
		-- Worse, the wall windows cast shadows, and the colonnade stands between them and the
		-- route. The little light that did carry that far arrived through two rows of columns.
		--
		-- So: overhead, over the lane, in every bay. This is the key light in the level and
		-- everything else is now atmosphere around it. It is 32 studs above the walkway, which
		-- is nothing for a point light, and it casts shadows -- the platforms throwing their
		-- own shadows down onto the water 56 studs below is worth the one light that does it.
		local roof = lightPanel(halls, legFrame(leg, along, 0, HEIGHT - SCALE * 0.5),
			Vector3.new(BAY * 0.2, SCALE, BAY * 0.66), 3.4, true)
		roof.Name = "RoofLight"

		-- ARCH BAYS GET NEITHER OF THE NEXT TWO. The transverse arch already spans the
		-- ceiling at the bay's centre and already runs piers down both walls, so a beam and a
		-- pilaster at the same station are a second copy of each occupying the same space --
		-- invisible, wasteful, and the sort of thing that shows up as z-fighting on somebody
		-- else's graphics card.
		local archBay = bay % 3 == 0

		-- ===== A BEAM ACROSS THE CEILING, AND PILASTERS UNDER IT =====
		--
		-- The ceiling was one flat plate for the whole level, which is the largest single
		-- surface in it and the one with least happening. A beam per bay costs one part and
		-- changes the room completely: it gives the ceiling a rhythm that matches the
		-- colonnade below it, it casts a band of shadow that moves as you walk, and it turns
		-- "a tall space" into "a sequence of bays", which is what the references actually are.
		--
		-- The pilasters are the same argument applied downward: a flat wall behind a free
		-- standing column looks like a column parked in front of a wall. A shallow pier rising
		-- behind each one ties the two together and makes the colonnade read as structure.
		if not archBay then
			-- NOT `free`. It spans the lane from wall to wall, and the only reason that is
			-- allowed is that it is twenty-five studs over anybody's head -- so let the guard
			-- be the thing that knows it, and say so if the ceiling ever comes down.
			slab(halls, legFrame(leg, along, 0, HEIGHT - SCALE * 0.9),
				Vector3.new(HALL_HALF_WIDTH * 2, SCALE * 1.8, BAY * 0.16), "Beam")
			for _, side in ipairs({ 1, -1 }) do
				slab(halls, legFrame(leg, along,
					side * (HALL_HALF_WIDTH - WALL_THICK / 2 - SCALE * 0.4), HEIGHT / 2),
					Vector3.new(SCALE * 0.9, HEIGHT, BAY * 0.3), "Pilaster")
				-- A capital under the cornice and a plinth at its foot, so it reads as a pier
				-- and not as a strip of wall standing forward.
				local cap = slab(halls, legFrame(leg, along,
					side * (HALL_HALF_WIDTH - WALL_THICK / 2 - SCALE * 0.7), HEIGHT - SCALE * 2),
					Vector3.new(SCALE * 1.4, SCALE * 1.2, BAY * 0.36), "PilasterCap")
				cap.Color = TRIM_COLOUR
				local plinth = slab(halls, legFrame(leg, along,
					side * (HALL_HALF_WIDTH - WALL_THICK / 2 - SCALE * 0.6), SCALE * 1.5),
					Vector3.new(SCALE * 1.2, SCALE * 3, BAY * 0.34), "PilasterBase")
				plinth.Color = WAINSCOT_COLOUR
			end
		end

		-- ===== THE PANEL OF WALL BETWEEN THIS BAY AND THE NEXT =====
		--
		-- EVERYTHING SET INTO THE WALL WAS BEHIND A PILASTER. The windows, the low light slots
		-- and the blind doorways were all placed at the bay's centre -- and so is the pilaster,
		-- twenty-nine studs wide and standing three and a half proud of the wall. In every bay
		-- that has one it covered the window completely and the doorway with it; the light still
		-- came out, and the thing it was coming out of could not be seen.
		--
		-- So the pilasters stay where the columns are, and everything set INTO the wall goes in
		-- the panel between two of them: a window in one panel, a blind niche in the next, and
		-- the doorways and water-level slots below them. That is the rhythm of a real arcaded
		-- wall -- pier, opening, pier -- and it is the first time the walls have had one.
		local panel = along + (span / bays) / 2
		if bay < bays and not insideChamber(legFrame(leg, panel, 0, 0).Position) then
			local doorSide = 0
			if rng:NextNumber() < DOORWAY_CHANCE then
				doorSide = if rng:NextNumber() < 0.5 then 1 else -1
				buildDoorway(halls, leg, panel, doorSide)
			end

			-- ===== LIGHT DOWN AT THE WATER =====
			--
			-- The windows are high, which is right for the room and useless for the pool, so
			-- there is a second, lower set of sources: slots just above the waterline that light
			-- the water and the first studs of wall above it and nothing else. ONE PER PANEL,
			-- ALTERNATING SIDES, and never on the side a doorway took. Above the tide line now,
			-- which was standing in front of the lower half of every one.
			local slotSide = if bay % 2 == 0 then 1 else -1
			if slotSide ~= doorSide then
				local slot = lightPanel(halls,
					legFrame(leg, panel, slotSide * wallToLane, WATER_DEPTH + 13)
						* CFrame.Angles(0, math.pi / 2, 0),
					Vector3.new(BAY * 0.3, 9, WALL_THICK * 0.3), 1.6)
				local lamp = slot:FindFirstChildOfClass("PointLight")
				if lamp then
					lamp.Color = POOL_GLOW
					lamp.Range = 15 * SCALE
					-- NO SHADOWS on these. They sit at the height of every column base in the
					-- room, so shadow-casting them means a dozen extra shadow volumes for light
					-- that is supposed to read as a diffuse glow off the water anyway.
					lamp.Shadows = false
				end
				slot.Color = POOL_GLOW
			end

			-- A window in every other panel and a niche in the rest. One window per panel is a
			-- corridor of strip lights; what makes these images is the DISTANCE between one lit
			-- opening and the next.
			if bay % 2 == 1 then
				for _, side in ipairs({ 1, -1 }) do
					-- HIGH IN THE WALL: nine tenths of it above the deck, with masonry over its
					-- head, which is the proportion every reference has.
					local window = lightPanel(halls,
						legFrame(leg, panel, side * wallToLane, HEIGHT * 0.74)
							* CFrame.Angles(0, math.pi / 2, 0),
						Vector3.new(BAY * 0.16, HEIGHT * 0.42, WALL_THICK * 0.3), 1.1)
					local lamp = window:FindFirstChildOfClass("PointLight")
					if lamp then
						-- FAR ENOUGH TO CROSS THE HALL: two rows of windows that only light
						-- their own walls meet in a dark stripe down the middle, over the route.
						lamp.Range = 32 * SCALE
						-- AND NO SHADOWS, which is the other half of it. The colonnade stands
						-- between every window and the walkway, so with shadows on, the only
						-- light that reached the route arrived through two rows of columns.
						lamp.Shadows = false
					end
				end
			else
				for _, side in ipairs({ 1, -1 }) do
					buildNiche(halls, leg, panel, side)
				end
			end
		end

		-- THE COLONNADE, both rows outside the lane. Every column is placed relative to the
		-- lane rather than on a grid, so there is no arrangement in which one lands on the
		-- route.
		for _, side in ipairs({ 1, -1 }) do
			piece(halls, "Hall_Column", legFrame(leg, along, side * (LANE_HALF + BAY * 0.3), 0))
		end

		-- ===== A TRANSVERSE ARCH every third bay =====
		--
		-- Arches receding one behind another is the single most repeated image in the
		-- references, and the length of a leg is the only place in the level they can be seen
		-- all at once.
		--
		-- THE ROUTE GOES THROUGH THIS ONE. It is the single piece in the level deliberately
		-- placed across the lane, because its opening IS the lane -- and that is why LANE_HALF
		-- is set from the opening's width rather than chosen. It is marked free for the same
		-- reason: the guard samples a bounding box and would flag the opening as solid, since
		-- a bounding box has no idea there is a hole in the middle of it. check_halls.py
		-- carries the static version of this check instead, comparing the two numbers at the
		-- source rather than at run time.
		--
		-- The panel is one bay wide and the hall is wider, so the gaps out to each wall are
		-- filled with plain returns. Without them the arch is a free-standing hoop with light
		-- coming round both sides of it, which is a folly, not a building.
		if archBay then
			buildArchway(halls, leg, along)
		end

		-- A skylight every fourth bay, dropping a shaft past the walkway into the water.
		if bay % 4 == 2 then
			local side = if bay % 8 == 2 then 1 else -1
			local above = legFrame(leg, along, side * (LANE_HALF + BAY * 0.55), HEIGHT - SCALE)
			-- OVERHEAD, so it is framed round its opening rather than capped underneath.
			-- Every skylight in this level was sealed by its own reveal until now.
			lightPanel(halls, above, Vector3.new(BAY * 0.3, SCALE, BAY * 0.3), 1.4, true)
		end

		-- Coving along the foot of both walls, which is what separates wall from floor when
		-- both are the same tile in the same colour.
		for _, side in ipairs({ 1, -1 }) do
			local cove = piece(halls, "Hall_Cove",
				legFrame(leg, along, side * (HALL_HALF_WIDTH - WALL_THICK / 2), 0)
					* CFrame.Angles(0, if side > 0 then math.pi / 2 else -math.pi / 2, 0))
			if cove then
				cove.CanCollide = false
			end
		end

		-- ===== THE PIERS THAT CARRY THE WALKWAY =====
		--
		-- The route has been floating fifty-six studs over open water since the day it was
		-- lifted there, held up by nothing, and it is the largest unanswered question in the
		-- level: a tiled building, carefully coved and dadoed, with a walkway hanging in the
		-- air down the middle of it.
		--
		-- This is what the height-aware lane guard was for. A pier is squarely in the lane in
		-- plan and nowhere near it in space -- it stops seven studs short of the deck, which is
		-- close enough to read as carrying it and far enough that nothing can catch on it.
		--
		-- One per bay rather than one per chunk: piers are structure and structure is on the
		-- building's module, not the route's. A chunk lands wherever it lands; the bays are
		-- what the arches, the beams and the colonnade are already counting in.
		local pierTop = FLOOR_DROP - 7
		local capital = SCALE * 1.6
		-- DOWN TO THE POOL'S FLOOR wherever the pool is under it, which is everywhere but the
		-- last room. A pier stopping at the shallows' level would be hanging in forty studs of
		-- water.
		local foot = if poolUnder(legFrame(leg, along, 0, 0).Position) then -POOL_DEPTH else 0
		slab(halls, legFrame(leg, along, 0, (foot + pierTop - capital) / 2),
			Vector3.new(11, pierTop - capital - foot, 11), "Pier")
		slab(halls, legFrame(leg, along, 0, pierTop - capital / 2),
			Vector3.new(16, capital, 16), "PierCap")

		-- ===== WHAT IS IN THIS BAY =====
		--
		-- One decision per side per bay, from a short list, and mostly nothing. The aim is that
		-- no two bays are alike -- not that every bay has a fitting in it. A corridor where
		-- every bay is furnished is as uniform as one where none is, and it is slower.
		--
		-- All of these are measured FROM THE WALL INWARD rather than from the centreline
		-- outward. Stated the other way round each is one arithmetic slip away from a fitting
		-- laid across the walkway, and the slip is invisible: a ledge in the lane looks exactly
		-- like a ledge.
		for _, side in ipairs({ 1, -1 }) do
			local roll = rng:NextNumber()
			local wallAt = HALL_HALF_WIDTH - WALL_THICK / 2

			if roll < BASIN_CHANCE then
				-- A SUNKEN BASIN. Recorded rather than built: it is a hole in the floor, a hole
				-- in the water and a room under both, and all three of those surfaces are laid
				-- down in one piece long after this loop has finished.
				--
				-- WATER YOU CANNOT MEASURE IS NOT WET. One depth everywhere reads as a green
				-- floor; a basin with steps going down into it, where the tile grid dims and
				-- then disappears, is what tells you the level is under water rather than
				-- painted with it.
				local half = BAY * 0.31
				local frame = legFrame(leg, along, side * (wallAt - half), 0)
				table.insert(hallBasins, {
					at = Vector3.new(frame.Position.X, hallFloorY, frame.Position.Z),
					half = half,
					depth = BASIN_DEPTHS[rng:NextInteger(1, #BASIN_DEPTHS)],
					-- The frame's X runs left, so the walkway is on the opposite side from the
					-- wall this basin is against.
					inward = frame.RightVector * -side,
					along = frame.LookVector,
				})
			elseif roll < BASIN_CHANCE + PARTITION_CHANCE then
				-- CUBICLE STUBS: three waist-high fins off the wall, the changing-room
				-- partitions of a bathhouse with the doors long gone. The single most
				-- bathhouse-looking thing in the kit and it costs three boxes.
				for fin = -1, 1 do
					slab(halls, legFrame(leg, along + fin * BAY * 0.3,
						side * (wallAt - BAY * 0.16), BAY * 0.13),
						Vector3.new(BAY * 0.32, BAY * 0.26, WALL_THICK * 0.6), "Partition")
				end
			elseif roll < BASIN_CHANCE + PARTITION_CHANCE + PLINTH_CHANCE then
				-- A dry ledge: the deck beside the pool.
				--
				-- WITHOUT DRY GROUND THERE IS NO WET GROUND. A level flooded uniformly to one
				-- depth is not a flooded building, it is a building with a green floor, because
				-- nothing in shot is dry enough to prove the rest is under water. It is that
				-- edge, with the waterline cutting across the tile grid, that makes the whole
				-- image read as flooded.
				local wide = BAY * 0.6
				slab(halls, legFrame(leg, along, side * (wallAt - wide / 2), LEDGE_RISE / 2),
					Vector3.new(wide, LEDGE_RISE, BAY * 0.9), "Ledge")
			end
		end
	end
end

-- ===== A JUNCTION =====
--
-- Where the corridor turns. The square is open on the two sides the corridor arrives and
-- leaves by, and walled on the other two -- which are, between them, the OUTSIDE of the elbow.
-- The inside of the elbow is the corner you can see round, and it gets a column rather than a
-- wall so the turn is visible from a bay away.
local function buildJunction(halls: Model, corner: HallRoute.Corner)
	local up = Vector3.new(0, 1, 0)
	local centre = hallOrigin + Vector3.new(corner.point.X, hallFloorY, corner.point.Z)
	local width = HALL_HALF_WIDTH * 2
	-- A JUNCTION INSIDE THE LAST ROOM IS NOT A JUNCTION. The chamber is four times the width
	-- of the corridor and has its own walls; building this one as well puts two of them across
	-- the middle of it. The common case for a 44-chunk route is exactly this.
	if insideChamber(centre) then
		return
	end

	-- The two outer walls. Passing only the right vector lets CFrame.fromMatrix work the third
	-- axis out, which keeps the basis right-handed without me having to reason about signs.
	for _, spec in ipairs({
		{ corner.inDir, 1 },
		{ corner.outDir, -1 },
	}) do
		local facing: Vector3 = spec[1] :: Vector3
		local sign: number = spec[2] :: number
		tiledWall(halls, CFrame.fromMatrix(
			centre + facing * (sign * HALL_HALF_WIDTH) + up * (HEIGHT / 2), facing, up),
			Vector3.new(WALL_THICK, HEIGHT, width), "Wall")
	end

	-- THE INSIDE CORNER: a column where two walls would otherwise meet.
	--
	-- The corridor arrives from the -inDir side and leaves by the +outDir side, so those two
	-- sides are the openings and the convex corner between them is the one you can see round.
	-- The column is stepped back IN from it along both axes -- towards the centre, which is
	-- +inDir and -outDir from that corner -- so it stands in the room rather than in the
	-- doorway.
	local inner = centre - corner.inDir * HALL_HALF_WIDTH + corner.outDir * HALL_HALF_WIDTH
	piece(halls, "Hall_Column", CFrame.new(inner + corner.inDir * BAY * 0.3
		- corner.outDir * BAY * 0.3))

	-- THE COLUMN-LINE RIBS, carried round the turn as a square, so the coffered ceiling of one leg
	-- runs into the next instead of stopping at the junction's edge.
	for _, direction in ipairs({ corner.inDir, corner.outDir }) do
		local across = Vector3.new(direction.Z, 0, -direction.X)
		for _, sign in ipairs({ 1, -1 }) do
			local rib = slab(halls, CFrame.fromMatrix(
				centre + across * (sign * (LANE_HALF + BAY * 0.3)) + up * (HEIGHT - SCALE * 0.45),
				across, up), Vector3.new(SCALE * 0.9, SCALE * 0.9, width), "CeilingRib")
			rib.CanCollide = false
		end
	end

	-- A LANTERN OVER THE TURN. A junction lit the same as the corridor is a widening; a
	-- junction with its own light is a place, and a place is what tells you that you turned.
	lightPanel(halls, CFrame.new(centre + up * (HEIGHT - SCALE)),
		Vector3.new(BAY * 0.5, SCALE, BAY * 0.5), 1.6, true)
end

-- ===== THERE ARE NO CORNER LANDINGS =====
--
-- There used to be a buildLanding here: a tiled slab laid in the gap a chunk left in front of a
-- corner. It was reported three times as a stray platform in the middle of the run, and it was
-- the visible half of a bug whose other half was chunks intersecting at the same corners.
--
-- Both came from the corner being at a fixed distance while the chunks are not. LevelService
-- now turns where its chunks are and reports the leg lengths that produced, and the corridor is
-- built from those -- so there is never a gap to fill, and nothing here to fill it with.

-- ===== A PLATE WITH HOLES IN IT =====
--
-- Roblox has no such thing as a slab with something cut out of it, and by now three surfaces
-- need one. The floor is open where the flume drops through it and where the basins sink below
-- it. The water is open in the same places, because a flat plane stretched across a pit is a
-- sheet of glass over a hole. The ceiling is open under the dome and over the tall hall.
--
-- The first version took ONE square hole and emitted the four boxes around it by hand, which
-- does not generalise: two holes cut out of the same plate by two passes of that would each
-- re-cover the other's opening.
--
-- So this is the real thing, and it is simpler than it sounds because every leg of this level
-- runs along a world axis and therefore so does every hole. Slice the plate into strips at
-- every hole edge in X; within each strip the holes that apply are the ones spanning it, and
-- they are just intervals in Z with gaps between them. Emit a box per gap.
export type Hole = { minX: number, maxX: number, minZ: number, maxZ: number }

-- ===== AND WHY THE WATER IS CUT UP FURTHER THAN THE HOLES REQUIRE =====
--
-- Roblox sorts transparent surfaces per OBJECT, by the distance to that object's centre, and
-- draws them back to front. That works while objects are roughly the size of the space between
-- them. It falls apart for one enormous transparent part, because its centre is nowhere near
-- most of it: a water plate 1400 studs long has its centre in the middle of the level, and from
-- a camera looking down at a platform near that middle the plate can sort as NEARER than the
-- platform it is fifty studs below. It is then drawn last, over the top, and a translucent
-- chunk -- slime, honey, jello soda -- is composited away behind half-opaque green glass.
--
-- That is the reported bug exactly: translucent platforms invisible from above with only their
-- opaque parts still drawn, and fine again from the side, because turning the camera changes
-- which centre is nearer.
--
-- The fix is not to make the water less transparent, it is to stop any one piece of it being
-- enormous. Tiled at 320 studs, every piece's centre is within 160 studs of all of it, so a
-- tile can never sort in front of something it is plainly behind. The tiles are coplanar, move
-- together and share every property, so there is no seam to see -- which would NOT be true if
-- they ever moved independently, and is why applyWater drives them all from one number.
local WATER_TILE = 320

local function plate(parent: Instance, atY: number, x0: number, x1: number, z0: number,
	z1: number, thickness: number, holes: { Hole }, name: string, options: Options?,
	tileTo: number?)
	local cuts: { number } = { x0, x1 }
	for _, hole in ipairs(holes) do
		if hole.maxX > x0 and hole.minX < x1 then
			table.insert(cuts, math.clamp(hole.minX, x0, x1))
			table.insert(cuts, math.clamp(hole.maxX, x0, x1))
		end
	end
	table.sort(cuts)

	for index = 1, #cuts - 1 do
		local ax, bx = cuts[index], cuts[index + 1]
		if bx - ax > 1 then
			-- WHICH HOLES APPLY TO THIS STRIP, tested at its middle. The strip boundaries are
			-- the hole edges, so no hole can start or stop partway across one -- a hole either
			-- covers the whole strip in X or none of it, and the midpoint settles which.
			local middleX = (ax + bx) / 2
			local bands: { { number } } = {}
			for _, hole in ipairs(holes) do
				if hole.minX <= middleX and hole.maxX >= middleX then
					table.insert(bands, { math.max(hole.minZ, z0), math.min(hole.maxZ, z1) })
				end
			end
			table.sort(bands, function(a, b)
				return a[1] < b[1]
			end)

			-- One box per gap, tiled down if a maximum was asked for.
			local function lay(az: number, bz: number)
				if bz - az <= 1 then
					return
				end
				local downX = if tileTo then math.max(1, math.ceil((bx - ax) / tileTo)) else 1
				local downZ = if tileTo then math.max(1, math.ceil((bz - az) / tileTo)) else 1
				local stepX = (bx - ax) / downX
				local stepZ = (bz - az) / downZ
				for ix = 0, downX - 1 do
					for iz = 0, downZ - 1 do
						slab(parent, CFrame.new(
							ax + (ix + 0.5) * stepX, atY, az + (iz + 0.5) * stepZ),
							Vector3.new(stepX, thickness, stepZ), name, options)
					end
				end
			end

			local at = z0
			for _, band in ipairs(bands) do
				lay(at, band[1])
				at = math.max(at, band[2])
			end
			lay(at, z1)
		end
	end
end

-- A hole centred on a point, which is what every caller here actually has.
local function holeAt(where: Vector3, half: number): Hole
	return { minX = where.X - half, maxX = where.X + half,
		minZ = where.Z - half, maxZ = where.Z + half }
end

-- Where the flume's tube centre is at t in 0..1 along it, in the flume's own frame.
--
-- THE HANDEDNESS IS NOT A DETAIL. Blender is z-up and the kit exports with axis_up = "Y", so a
-- Blender point (x, y, z) arrives in Roblox as (x, z, -y). The mesh sweeps its helix through
-- (cos, sin, height), which means anything following it has to be (cos, height, -sin). Get the
-- sign wrong and the path is the mirror image of the tube: a rider spirals out through its
-- wall on the first quarter turn, and a part-built copy of it is wound the wrong way round.
local function helixAt(t: number): Vector3
	local angle = t * SLIDE_TURNS * math.pi * 2
	return Vector3.new(
		math.cos(angle) * SLIDE_RADIUS,
		-SLIDE_DROP * t,
		-math.sin(angle) * SLIDE_RADIUS)
end

-- ===== THE FLUME, BUILT HERE RATHER THAN IMPORTED =====
--
-- This used to be Hall_Slide, an imported mesh, and it was reported misaligned four rounds in a
-- row while its frame measured correct every time. A helix has a handedness, and whether that
-- survives the FBX import cannot be checked in a kit where every other piece is symmetric. Built
-- from parts along helixAt -- the curve the rider follows, the mouth is placed from and the
-- gangway is measured against -- it cannot disagree with any of them, and its orientation has not
-- been reported since.
--
-- ===== AND BUILT AS A FLUME AGAIN, NOT A PIPE =====
--
-- The first part-built version was a closed tube, a cylinder per segment with a ball at every
-- joint, because that was the shape with no seams to get wrong. It fixed the orientation and lost
-- everything that made the mesh read as a water slide -- the open trough, the bright lip, the
-- mouth opening out -- and it came out looking like a hose. This is the mesh's shape again, and
-- more than the mesh ever had:
--
--   A U, NOT A RING. A half-round floor with straight sides leaning out, which is the section a
--   fibreglass flume actually has. You can see down into it from the gangway, and see a rider in
--   it all the way round.
--   BANKED INTO THE TURN, the outside wall standing higher than the inside, the way every curved
--   flume is laid. The rider leans with it: see slideUp.
--   A ROLLED LIP along both edges in a pale trim. From across the room it is the one line that
--   traces the whole helix.
--   FLANGES every eighth segment, where a real flume's sections bolt together. They put a rhythm
--   down its length, and they are where it is held up.
--   HELD UP. A steel mast on the helix's axis, down into the shaft, with a bracket out to a saddle
--   under every flange. The flume was the last thing in the level hanging in mid-air.
--
-- The shell is staves. Between two stations, each edge of the section is one thin part whose inner
-- face lies on the chord. Every stave is widened to its OUTER chord, so neighbours meet on the
-- outside and overlap, out of sight, on the inside; and each runs past both stations by more than
-- the wedge a bend opens at a joint.
local FLUME_SEGMENTS = 64
-- Staves round the half-round floor. The two straight sides are one stave each on top of these.
local FLUME_ARC = 8
local FLUME_BANK = math.rad(16)
-- How far the straight sides rise above the centre line, and lean out at the top, in bores.
local FLUME_SIDE_RISE = 0.6
local FLUME_SIDE_OUT = 0.14
local FLUME_LIP = SLIDE_WALL + 0.9
local FLUME_FLANGE_EVERY = 8
local FLUME_COLOUR = Color3.fromRGB(32, 122, 146)
local FLUME_TRIM = Color3.fromRGB(232, 229, 214)
local STEEL_COLOUR = Color3.fromRGB(58, 70, 72)
-- How far above the walkway the mast stands, with its lamp on top.
local MAST_TOP = 30
-- The gangway's wood and rails: weathered teak for the deck, darker for what holds it up.
local PLANK_TONES = {
	Color3.fromRGB(124, 100, 74),
	Color3.fromRGB(136, 110, 82),
	Color3.fromRGB(114, 92, 68),
	Color3.fromRGB(130, 106, 78),
}
local TIMBER_DARK = Color3.fromRGB(84, 70, 56)
local RAIL_COLOUR = Color3.fromRGB(198, 200, 196)

-- The flume's frame at t in 0..1: its centre line, the direction it runs, the axis across the
-- trough, the axis up out of it, and the bore there. SHARED BY THE SHELL, THE BRACKETS AND THE
-- RIDE, so none of the three can lean a different way from the others.
--
-- THE EXACT DERIVATIVE for the direction, not a difference between two points along the curve. A
-- difference is one-sided at the mouth and skews the cut end by nearly two degrees, which across
-- the gangway's width stands the bottom edge of the shell on its last plank.
--
-- EASED IN OVER THE FLARE. The helix falls at twenty degrees from its very first stud, and a
-- section square to that leans back over the gangway. So across the first tenth the section is
-- eased from level and unbanked to the full pitch and bank: the mouth is an upright, level U that
-- the deck runs straight into.
local function flumeBasis(t: number): (Vector3, Vector3, Vector3, Vector3, number)
	local centre = helixAt(t)
	local spin = SLIDE_TURNS * math.pi * 2
	local angle = t * spin
	local tangent = Vector3.new(-math.sin(angle) * SLIDE_RADIUS * spin, -SLIDE_DROP,
		-math.cos(angle) * SLIDE_RADIUS * spin).Unit
	local ease = math.clamp(t / 0.1, 0, 1)
	tangent = Vector3.new(tangent.X, 0, tangent.Z).Unit:Lerp(tangent, ease).Unit
	local square = tangent:Cross(Vector3.new(0, 1, 0)):Cross(tangent).Unit
	local inward = Vector3.new(-centre.X, 0, -centre.Z).Unit
	local bank = FLUME_BANK * ease
	local up = square * math.cos(bank) + inward * math.sin(bank)
	up = (up - tangent * up:Dot(tangent)).Unit
	local grow = if t < 0.1 then 1 + SLIDE_FLARE * (1 - t / 0.1) ^ 2 else 1
	return centre, tangent, tangent:Cross(up).Unit, up, SLIDE_BORE * grow
end

-- The section at a bore of `radius`, as (across, up) from one lip, round the floor, to the other.
local function flumeProfile(radius: number): { Vector2 }
	local rise = SLIDE_BORE * FLUME_SIDE_RISE
	local out = SLIDE_BORE * FLUME_SIDE_OUT
	local points = { Vector2.new(-(radius + out), rise) }
	for k = 0, FLUME_ARC do
		local phi = math.pi + k * math.pi / FLUME_ARC
		table.insert(points, Vector2.new(math.cos(phi) * radius, math.sin(phi) * radius))
	end
	table.insert(points, Vector2.new(radius + out, rise))
	return points
end

local function flumePart(halls: Model, name: string, size: Vector3, cf: CFrame, colour: Color3,
	shape: Enum.PartType?): Part
	-- NOT SOLID, and not queryable: the rider is carried along the inside of this, and a player
	-- who walks into the mouth should find the prompt rather than a wall.
	local part = fitting(halls, name, size, cf, colour, Enum.Material.SmoothPlastic, shape)
	part.CanQuery = false
	part.CanTouch = false
	part.Reflectance = 0.12
	return part
end

type Station = {
	centre: Vector3,
	tangent: Vector3,
	side: Vector3,
	up: Vector3,
	radius: number,
	points: { Vector3 },
}

local function buildFlume(halls: Model, slideFrame: CFrame)
	local stations: { Station } = {}
	for index = 0, FLUME_SEGMENTS do
		local centre, tangent, side, up, radius = flumeBasis(index / FLUME_SEGMENTS)
		local station: Station = {
			centre = slideFrame:PointToWorldSpace(centre),
			tangent = slideFrame:VectorToWorldSpace(tangent),
			side = slideFrame:VectorToWorldSpace(side),
			up = slideFrame:VectorToWorldSpace(up),
			radius = radius,
			points = {},
		}
		for _, p in ipairs(flumeProfile(radius)) do
			table.insert(station.points, station.centre + station.side * p.X + station.up * p.Y)
		end
		table.insert(stations, station)
	end

	-- THE SHELL.
	for index = 1, FLUME_SEGMENTS do
		local a, b = stations[index], stations[index + 1]
		local middle = (a.centre + b.centre) / 2
		for k = 1, #a.points - 1 do
			local from = (a.points[k] + a.points[k + 1]) / 2
			local to = (b.points[k] + b.points[k + 1]) / 2
			local across = (a.points[k + 1] - a.points[k]) + (b.points[k + 1] - b.points[k])
			local outward = across:Cross(to - from).Unit
			if outward:Dot((from + to) / 2 - middle) < 0 then
				outward = -outward
			end
			local cf, run = spanFrame(from, to, outward)
			local chord = across.Magnitude / 2
			flumePart(halls, "FlumeShell",
				Vector3.new(chord * (1 + SLIDE_WALL / a.radius) + 0.15, SLIDE_WALL, run + 0.7),
				cf * CFrame.new(0, SLIDE_WALL / 2, 0), FLUME_COLOUR)
		end
	end

	-- THE LIP, rolled over the top of both sides.
	local wall = Vector2.new(SLIDE_BORE * FLUME_SIDE_OUT, SLIDE_BORE * FLUME_SIDE_RISE).Unit
	local function lipAt(station: Station, hand: number): Vector3
		local top = station.points[if hand < 0 then 1 else #station.points]
		-- Out through the side by half its thickness, so the roll sits ON the edge rather than
		-- inside the trough, and a little way up it so it caps the end of the stave.
		local outAcross, outUp = hand * wall.Y, -wall.X
		local upAcross, upUp = hand * wall.X, wall.Y
		return top + station.side * (outAcross * SLIDE_WALL / 2 + upAcross * 0.3)
			+ station.up * (outUp * SLIDE_WALL / 2 + upUp * 0.3)
	end
	for _, hand in ipairs({ -1, 1 }) do
		for index = 1, FLUME_SEGMENTS do
			local from = lipAt(stations[index], hand)
			local to = lipAt(stations[index + 1], hand)
			local lip = flumePart(halls, "FlumeLip",
				Vector3.new((to - from).Magnitude + 0.35, FLUME_LIP, FLUME_LIP),
				CFrame.lookAt(from:Lerp(to, 0.5), to) * CFrame.Angles(0, math.rad(90), 0),
				FLUME_TRIM, Enum.PartType.Cylinder)
			-- Trim casts no shadow of its own: the shell it sits on already does, and there are
			-- more than a hundred of these.
			lip.CastShadow = false
		end
	end

	-- THE FLANGES, with a trim ring finishing both cut ends.
	for index = 1, FLUME_SEGMENTS + 1, FLUME_FLANGE_EVERY do
		local station = stations[index]
		-- One-sided at the two ends, so the ring finishes the cut rather than standing past it.
		local back = if index == 1 then 0 elseif index == FLUME_SEGMENTS + 1 then 1.3 else 0.65
		for k = 1, #station.points - 1 do
			local p0, p1 = station.points[k], station.points[k + 1]
			local middle = (p0 + p1) / 2
			local outward = (p1 - p0):Cross(station.tangent).Unit
			if outward:Dot(middle - station.centre) < 0 then
				outward = -outward
			end
			local cf = spanFrame(middle - station.tangent * back,
				middle + station.tangent * (1.3 - back), outward)
			local flange = flumePart(halls, "FlumeFlange",
				Vector3.new((p1 - p0).Magnitude * (1 + (SLIDE_WALL + 0.9) / station.radius) + 0.2,
					0.9, 1.3),
				cf * CFrame.new(0, SLIDE_WALL + 0.45, 0), FLUME_TRIM)
			flange.CastShadow = false
		end
	end

	-- ===== WHAT HOLDS IT UP =====
	local up = Vector3.new(0, 1, 0)
	local upright = CFrame.Angles(0, 0, math.pi / 2)
	local function steel(name: string, size: Vector3, cf: CFrame, shape: Enum.PartType?): Part
		local part = flumePart(halls, name, size, cf, STEEL_COLOUR, shape)
		part.Material = Enum.Material.Metal
		part.Reflectance = 0.04
		return part
	end

	-- THE MAST, on the helix's own axis, from the bottom of the shaft to a lamp over the mouth. The
	-- rider is a radius out from it the whole way down, so it is never in the way.
	local top = MAST_TOP - SLIDE_MOUTH_LIFT
	local bottom = -(SLIDE_MOUTH_LIFT + FLOOR_DROP + PIT_WALL_DEPTH)
	steel("FlumeMast", Vector3.new(top - bottom, 6, 6),
		slideFrame * CFrame.new(0, (top + bottom) / 2, 0) * upright, Enum.PartType.Cylinder)

	-- A BRACKET UNDER EVERY FLANGE: an arm out from the mast and a saddle up to the shell. The
	-- saddle stops a quarter of a wall short of the shell's outside, which seats it in the skin
	-- and keeps it well clear of the bore.
	for index = FLUME_FLANGE_EVERY, FLUME_SEGMENTS, FLUME_FLANGE_EVERY do
		-- The last one a station short of the end, so its saddle is under the shell rather than
		-- half past the cut.
		local centre, tangent, _, _, radius =
			flumeBasis(math.min(index, FLUME_SEGMENTS - 1) / FLUME_SEGMENTS)
		local outward = Vector3.new(centre.X, 0, centre.Z).Unit
		local armTop = centre.Y - (radius + SLIDE_WALL) - 1.2
		local arm, armRun = spanFrame(outward * 3 + up * (armTop - 1.1),
			outward * (SLIDE_RADIUS + 2) + up * (armTop - 1.1), up)
		steel("FlumeBracket", Vector3.new(1.8, 2.2, armRun), slideFrame * arm)
		steel("FlumeCollar", Vector3.new(3, 8.5, 8.5),
			slideFrame * CFrame.new(0, armTop - 1.1, 0) * upright, Enum.PartType.Cylinder)
		local saddleTop = centre.Y - (radius + SLIDE_WALL * 0.75)
		local saddleAt = outward * SLIDE_RADIUS + up * ((armTop + saddleTop) / 2)
		steel("FlumeSaddle", Vector3.new(3, saddleTop - armTop, 3),
			slideFrame * CFrame.lookAt(saddleAt, saddleAt + Vector3.new(tangent.X, 0, tangent.Z)))
	end

	-- AT THE MOUTH, a heavier bracket: a crosshead from the mast out along the route's heading to
	-- the gangway's far edge, under the end of the gangway and the mouth together, with a saddle
	-- up to the trough and a knee brace back down to the mast. The gangway's girders span to it
	-- from their last trestle.
	local deckUnder = -SLIDE_MOUTH_LIFT - 5
	local crossReach = SLIDE_RADIUS + MOUTH_ALONG
	steel("FlumeCrosshead", Vector3.new(crossReach, 3, 5),
		slideFrame * CFrame.new(crossReach / 2, deckUnder - 1.5, 0))
	steel("FlumeCollar", Vector3.new(3, 8.5, 8.5),
		slideFrame * CFrame.new(0, deckUnder - 1.5, 0) * upright, Enum.PartType.Cylinder)
	local mouthSaddleTop = -(SLIDE_MOUTH_LIFT + SLIDE_WALL / 2) - 0.7
	steel("FlumeSaddle", Vector3.new(6, mouthSaddleTop - deckUnder, 3),
		slideFrame * CFrame.new(SLIDE_RADIUS, (deckUnder + mouthSaddleTop) / 2, -2))
	local knee, kneeRun = spanFrame(Vector3.new(3, -SLIDE_MOUTH_LIFT - 40, 0),
		Vector3.new(SLIDE_RADIUS + 4, deckUnder - 3, 0), Vector3.new(0, 0, 1))
	steel("FlumeBrace", Vector3.new(2.4, 2.4, kneeRun), slideFrame * knee)

	-- THE LAMP. A warm point over the finish: the one light in the chamber whose source you can see
	-- from the door, and the first thing in the room that says which way to go.
	steel("FlumeMastCap", Vector3.new(1.2, 9, 9),
		slideFrame * CFrame.new(0, top + 0.6, 0) * upright, Enum.PartType.Cylinder)
	local globe = flumePart(halls, "FlumeLamp", Vector3.new(5, 5, 5),
		slideFrame * CFrame.new(0, top + 3.7, 0), GLOW_COLOUR, Enum.PartType.Ball)
	globe.Material = Enum.Material.Neon
	globe.Reflectance = 0
	globe.CastShadow = false
	local glow = Instance.new("PointLight")
	glow.Color = GLOW_COLOUR
	glow.Brightness = 0.9
	glow.Range = 15 * SCALE
	-- NO SHADOWS. The oculus overhead already throws the flume's shadow down the shaft, and a second
	-- shadow-casting light in among seven hundred staves is frame rate spent on nothing.
	glow.Shadows = false
	glow.Parent = globe
	steel("FlumeFinial", Vector3.new(2.4, 1.4, 1.4),
		slideFrame * CFrame.new(0, top + 7.2, 0) * upright, Enum.PartType.Cylinder)
end

-- ===== A SUNKEN BASIN =====
--
-- A square of floor that is not there, a room under it, and water standing in the hole to the
-- same level as everywhere else. The hole itself is cut by the floor and water plates; this is
-- everything that lines it.
--
-- The depth is the whole point. Looking down through eight studs of green water at a tile
-- floor, and then along two bays at a basin where the tile fades out before the bottom, is the
-- only way this level ever says how deep anything is.
local function buildBasin(halls: Model, basin: Basin)
	local half = basin.half

	-- The bottom, and the four sides holding the surrounding floor up.
	slab(halls, CFrame.new(basin.at - Vector3.new(0, basin.depth + SCALE, 0)),
		Vector3.new(half * 2 + WALL_THICK * 2, 2 * SCALE, half * 2 + WALL_THICK * 2),
		"BasinFloor", { free = true })
	for _, axis in ipairs({ Vector3.new(1, 0, 0), Vector3.new(0, 0, 1) }) do
		for _, sign in ipairs({ 1, -1 }) do
			local flat = axis * (half * sign)
			local sizeX = if axis.X ~= 0 then WALL_THICK else half * 2 + WALL_THICK * 2
			local sizeZ = if axis.X ~= 0 then half * 2 + WALL_THICK * 2 else WALL_THICK
			slab(halls, CFrame.new(basin.at
				+ Vector3.new(flat.X, -basin.depth / 2, flat.Z)),
				Vector3.new(sizeX, basin.depth, sizeZ), "BasinWall", { free = true })
		end
	end

	-- THE WATER IN IT, as its own column. The main plate has a hole here, because a flat slab
	-- of water stretched over a pit is a sheet of glass over a pit -- and because the depth is
	-- the point, and one plate cannot be two thicknesses.
	local deepWater = Instance.new("Part")
	deepWater.Name = "BasinWater"
	deepWater.Size = Vector3.new(half * 2, basin.depth + WATER_DEPTH, half * 2)
	deepWater.CFrame = CFrame.new(basin.at
		+ Vector3.new(0, WATER_DEPTH / 2 - basin.depth / 2, 0))
	deepWater.Anchored = true
	deepWater.CanCollide = false
	deepWater.CanTouch = false
	deepWater.CastShadow = false
	deepWater.Material = WATER_MATERIAL
	deepWater.Color = WATER_COLOUR
	-- LESS TRANSPARENT THAN THE SHALLOWS, and that is the whole trick. Real water is not a
	-- colour, it is a depth of colour: the same green over eight studs and over sixty cannot
	-- be the same value or the deep end reads as a painted square.
	deepWater.Transparency = 0.3
	deepWater.Reflectance = 0.24
	deepWater.Parent = halls

	-- A light on the bottom, which is the one thing that stops a deep basin being a black
	-- square. Pool lighting is always underwater and always aimed up, and it is what makes the
	-- surface glow from beneath rather than being lit from the room.
	local lamp = Instance.new("Part")
	lamp.Name = "BasinLamp"
	lamp.Size = Vector3.new(half * 0.7, 1.2, half * 0.7)
	lamp.CFrame = CFrame.new(basin.at - Vector3.new(0, basin.depth - 1.4, 0))
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.CastShadow = false
	lamp.Material = Enum.Material.Neon
	lamp.Color = POOL_GLOW
	lamp.Transparency = 0.45
	lamp.Parent = halls
	local glow = Instance.new("PointLight")
	glow.Color = POOL_GLOW
	glow.Brightness = 1.1
	glow.Range = math.min(34 * SCALE, basin.depth + 18 * SCALE)
	glow.Shadows = false
	glow.Parent = lamp

	-- ===== STEPS DOWN ON THE WALKWAY SIDE =====
	--
	-- WHICH WAY A FLIGHT OF STEPS FACES IS A FACT ABOUT THE MESH, and guessing it is how the
	-- first placement of this piece ended up with a staircase running across the basin rather
	-- than into it. Hall_Steps puts tread i further along +y and lower in z, and the kit
	-- exports z-up to y-up, so the part descends towards its own local -Z. Pointing +Z at the
	-- walkway therefore sends the flight away from it, which is down into the water.
	--
	-- The length matters too: the part is positioned by its bounding-box CENTRE, so the top of
	-- the flight is half a flight ahead of wherever the CFrame is put. Ignore that and the
	-- staircase starts in mid-basin with its top step floating.
	local up = Vector3.new(0, 1, 0)
	-- HOW LONG THE FLIGHT IS, mirroring STEP_FLIGHT in gen_flooded_halls.py (STEP_TREADS times
	-- STEP_RUN). check_halls compares the two, because a MeshPart is placed by its bounding-box
	-- centre and this is the number that turns that centre into "where the top tread is".
	local flight = 11.2 * SCALE
	local mouth = CFrame.fromMatrix(
		basin.at + basin.inward * (half - flight / 2),
		up:Cross(basin.inward), up, basin.inward)
	-- HUNG rather than stood, so the top tread is level with the floor it leaves and the rest
	-- of the flight is under it. It only descends 32 studs; in the two deeper basins it runs
	-- out partway down and disappears into the water, which is the image this piece exists for.
	piece(halls, "Hall_Steps", mouth, { hang = true, free = true })
	local rail = piece(halls, "Hall_Rail",
		mouth * CFrame.new(BAY * 0.22, 0, 0), { free = true })
	if rail then
		rail.Material = Enum.Material.Metal
		rail.Color = Color3.fromRGB(198, 200, 196)
		rail.Reflectance = 0.18
		rail.CanCollide = false
	end
end

-- WHERE THE POOL GOES, leg by leg. See the note at hallPools.
local function choosePools(route: HallRoute.Route)
	hallPools = {}
	for index, leg in ipairs(route.legs) do
		local first, last = index == 1, index == #route.legs
		-- The first leg's pool starts a little way out from the entrance deck; every other one
		-- starts where the previous box's corner square ends.
		local from = if first then -ENTRANCE_DEPTH + BAY * 0.22 + 12 else POOL_HALF
		local to = if last then leg.length else leg.length + POOL_HALF
		local function inRoom(at: number): boolean
			for _, lateral in ipairs({ -POOL_HALF - 4, 0, POOL_HALF + 4 }) do
				if insideChamber(legFrame(leg, at, lateral, 0).Position) then
					return true
				end
			end
			return false
		end
		-- Out of the last room, walked back the way the walls are.
		while to > from and inRoom(to) do
			to -= 4
		end
		if to - from > BAY * 0.5 and not inRoom(from) then
			local least = Vector3.new(math.huge, 0, math.huge)
			local most = Vector3.new(-math.huge, 0, -math.huge)
			for _, at in ipairs({ from, to }) do
				for _, lateral in ipairs({ POOL_HALF, -POOL_HALF }) do
					local where = legFrame(leg, at, lateral, 0).Position
					least = Vector3.new(math.min(least.X, where.X), 0, math.min(least.Z, where.Z))
					most = Vector3.new(math.max(most.X, where.X), 0, math.max(most.Z, where.Z))
				end
			end
			table.insert(hallPools, {
				leg = leg,
				from = from,
				to = to,
				first = first,
				last = last,
				box = { minX = least.X, maxX = most.X, minZ = least.Z, maxZ = most.Z },
			})
		end
	end
end

-- ===== THE POOL, BUILT =====
--
-- Everything round the edge of a box is built only along the stretches of its sides that no
-- neighbouring box touches. Where two legs' pools meet at a corner there is no wall, no coping
-- and no rope across the join -- it is one pool turning the corner, not two pools butted
-- together. That is the whole reason for exposedRuns.
--
-- The walls stand INSIDE the box rather than outside it, so the floor and water plates -- cut to
-- the box -- meet their outer faces exactly, and two walls meeting at an outside corner fill it
-- between them with no gap to see down.
local ROPE_COLOURS = {
	Color3.fromRGB(232, 228, 212),
	Color3.fromRGB(184, 72, 62),
	Color3.fromRGB(232, 228, 212),
	Color3.fromRGB(62, 112, 150),
}

type PoolSide = { axis: Vector3, sign: number, run: Vector3, at: number, lo: number, hi: number }

local function poolSides(box: Hole): { PoolSide }
	local x, z = Vector3.new(1, 0, 0), Vector3.new(0, 0, 1)
	return {
		{ axis = x, sign = 1, run = z, at = box.maxX, lo = box.minZ, hi = box.maxZ },
		{ axis = x, sign = -1, run = z, at = box.minX, lo = box.minZ, hi = box.maxZ },
		{ axis = z, sign = 1, run = x, at = box.maxZ, lo = box.minX, hi = box.maxX },
		{ axis = z, sign = -1, run = x, at = box.minZ, lo = box.minX, hi = box.maxX },
	}
end

-- The stretches of one side that open onto the shallows rather than onto another leg's pool.
local function exposedRuns(pool: Pool, side: PoolSide): { { number } }
	local cuts: { { number } } = {}
	for _, other in ipairs(hallPools) do
		if other ~= pool then
			for _, facing in ipairs(poolSides(other.box)) do
				if facing.axis == side.axis and facing.sign ~= side.sign
					and math.abs(facing.at - side.at) < 0.5 then
					local a, b = math.max(side.lo, facing.lo), math.min(side.hi, facing.hi)
					if b > a then
						table.insert(cuts, { a, b })
					end
				end
			end
		end
	end
	table.sort(cuts, function(p, q)
		return p[1] < q[1]
	end)
	local runs: { { number } } = {}
	local at = side.lo
	for _, cut in ipairs(cuts) do
		if cut[1] > at + 1 then
			table.insert(runs, { at, cut[1] })
		end
		at = math.max(at, cut[2])
	end
	if side.hi > at + 1 then
		table.insert(runs, { at, side.hi })
	end
	return runs
end

-- The pool's lining: POOL_LINING tile, and the glazed mosaic variant over it if Studio has one.
local poolVariant: boolean? = nil
local function poolTile(part: BasePart)
	part.Color = POOL_LINING
	if poolVariant == nil then
		poolVariant = game:GetService("MaterialService"):FindFirstChild(POOL_TILE_VARIANT) ~= nil
	end
	if poolVariant then
		local ok = pcall(function()
			part.Material = Enum.Material.Concrete
			part.MaterialVariant = POOL_TILE_VARIANT
		end)
		if not ok then
			poolVariant = false
		end
	end
end

local function buildPools(halls: Model)
	local up = Vector3.new(0, 1, 0)
	for poolIndex, pool in ipairs(hallPools) do
		local box = pool.box
		local wideX, wideZ = box.maxX - box.minX, box.maxZ - box.minZ

		-- THE FLOOR, and the water standing on it -- tiled at WATER_TILE like the rest of the
		-- water, for the transparency sort's sake.
		poolTile(slab(halls, CFrame.new((box.minX + box.maxX) / 2, hallFloorY - POOL_DEPTH - 4,
			(box.minZ + box.maxZ) / 2), Vector3.new(wideX, 8, wideZ), "PoolFloor", { free = true }))
		local downX = math.max(1, math.ceil(wideX / WATER_TILE))
		local downZ = math.max(1, math.ceil(wideZ / WATER_TILE))
		for ix = 0, downX - 1 do
			for iz = 0, downZ - 1 do
				local water = Instance.new("Part")
				water.Name = "PoolWater"
				water.Size = Vector3.new(wideX / downX, POOL_DEPTH + WATER_DEPTH, wideZ / downZ)
				water.CFrame = CFrame.new(box.minX + (ix + 0.5) * wideX / downX,
					hallFloorY + (WATER_DEPTH - POOL_DEPTH) / 2, box.minZ + (iz + 0.5) * wideZ / downZ)
				water.Anchored = true
				water.CanCollide = false
				water.CanTouch = false
				water.CanQuery = false
				water.CastShadow = false
				water.Material = WATER_MATERIAL
				water.Color = POOL_WATER_COLOUR
				water.Transparency = 0.34
				water.Reflectance = 0.24
				water.Parent = halls
			end
		end

		-- ===== ROUND THE EDGE =====
		for sideIndex, side in ipairs(poolSides(box)) do
			local normal = side.axis * side.sign
			-- A frame on this side: `along` studs down it, `out` studs outward from the box's
			-- edge (negative is into the pool), `height` above the shallows' floor. X is the
			-- side's outward normal, so a cylinder built on it faces into the pool.
			local function frame(along: number, out: number, height: number): CFrame
				return CFrame.fromMatrix(side.axis * (side.at + side.sign * out) + side.run * along
					+ up * (hallFloorY + height), normal, up)
			end
			-- Copings meeting at a corner would have coplanar tops; one direction sits a hair
			-- higher than the other.
			local lift = if side.axis.X ~= 0 then 0 else 0.06

			for _, span in ipairs(exposedRuns(pool, side)) do
				local lo, hi = span[1], span[2]
				local length = hi - lo
				local middle = (lo + hi) / 2

				-- The wall, from under the pool's floor up to the shallows.
				poolTile(slab(halls, frame(middle, -WALL_THICK / 2, -(POOL_DEPTH + 8) / 2),
					Vector3.new(WALL_THICK, POOL_DEPTH + 8, length), "PoolWall", { free = true }))
				-- A dark band just under the edge: the depth line every pool has.
				local band = slab(halls, frame(middle, -WALL_THICK, -4.5),
					Vector3.new(0.6, 3, length), "PoolBand", { free = true })
				band.Color = ACCENT_TILE
				band.CanCollide = false
				-- THE COPING, a raised bullnose over the wall's top, and the gutter grate behind it.
				-- Both under eight studs of water, and both still the clearest line in the level
				-- from the walkway.
				local coping = slab(halls, frame(middle, -3.5, 0.3 + lift),
					Vector3.new(WALL_THICK + 3, 1.2, length), "PoolCoping", { free = true })
				coping.Color = TRIM_COLOUR
				coping.CanCollide = false
				local grate = fitting(halls, "PoolGutter", Vector3.new(1.6, 0.6, length),
					frame(middle, 2.8, 0.1 + lift), Color3.fromRGB(38, 50, 52),
					Enum.Material.SmoothPlastic)
				grate.CastShadow = false

				-- LAMPS IN THE WALL, every other bay, which is what makes a pool glow from inside
				-- instead of being lit from the room. Short-ranged and unshadowed: light for the
				-- water, not for the hall.
				local count = math.max(1, math.floor(length / BAY))
				for k = 0, count - 1 do
					if (k + sideIndex + poolIndex) % 2 == 0 and length > BAY * 0.6 then
						local spot = frame(lo + (k + 0.5) * (length / count), -WALL_THICK,
							-POOL_DEPTH * 0.55)
						fitting(halls, "PoolLampRim", Vector3.new(0.9, 8, 8), spot,
							Color3.fromRGB(150, 156, 152), Enum.Material.Metal, Enum.PartType.Cylinder)
						local lens = fitting(halls, "PoolLamp", Vector3.new(1.2, 6, 6), spot, POOL_GLOW,
							Enum.Material.Neon, Enum.PartType.Cylinder)
						lens.CastShadow = false
						local glow = Instance.new("PointLight")
						glow.Color = POOL_GLOW
						glow.Brightness = 0.9
						glow.Range = 13 * SCALE
						glow.Shadows = false
						glow.Parent = lens
					end
				end

				-- A LANE ROPE floating along the edge, a few studs in. Floats in a repeating run of
				-- colours, and the one strong colour anywhere in the building.
				local floats = math.max(1, math.floor(length / 32 + 0.5))
				for k = 0, floats - 1 do
					local rope = fitting(halls, "LaneRope",
						Vector3.new(length / floats - 0.4, 1.8, 1.8),
						CFrame.fromMatrix(side.axis * (side.at - side.sign * (WALL_THICK + 3))
							+ side.run * (lo + (k + 0.5) * length / floats)
							+ up * (hallFloorY + WATER_DEPTH + 0.15), side.run, up),
						ROPE_COLOURS[(k + sideIndex) % #ROPE_COLOURS + 1], Enum.Material.SmoothPlastic,
						Enum.PartType.Cylinder)
					rope.CastShadow = false
				end
			end
		end

		-- ===== STEPS AND STRIPES, in the leg's own frame =====
		local leg = pool.leg
		local inner = POOL_HALF - WALL_THICK
		local startAt = pool.from + (if pool.first then WALL_THICK else 0)
		local stripeFrom = startAt + 10
		-- STEPS DOWN INTO THE DEEP END, at the entrance end of the first leg -- the first thing you
		-- see if you turn round at the spawn and look down.
		if pool.first then
			local rise = POOL_DEPTH / 6
			for k = 1, 5 do
				local top = -k * rise
				poolTile(slab(halls, legFrame(leg, startAt + (k - 0.5) * 6, 0, (top - POOL_DEPTH) / 2),
					Vector3.new(inner * 2, top + POOL_DEPTH, 6), "PoolStep", { free = true }))
				local nosing = slab(halls, legFrame(leg, startAt + k * 6 - 0.4, 0, top + 0.1),
					Vector3.new(inner * 2, 0.4, 0.8), "PoolStep", { free = true })
				nosing.Color = TRIM_COLOUR
			end
			stripeFrom = startAt + 30 + 10
		end
		local stripeTo = pool.to - WALL_THICK - 10
		if stripeTo - stripeFrom > 20 then
			for _, lateral in ipairs({ -12, 12 }) do
				local pieces = {
					{ (stripeFrom + stripeTo) / 2, Vector3.new(4, 0.5, stripeTo - stripeFrom) },
					-- The T where a stripe meets a wall.
					{ stripeTo, Vector3.new(14, 0.5, 4) },
				}
				if pool.first then
					table.insert(pieces, { stripeFrom, Vector3.new(14, 0.5, 4) })
				end
				for _, spec in ipairs(pieces) do
					local stripe = slab(halls, legFrame(leg, spec[1] :: number, lateral,
						-POOL_DEPTH + 0.25), spec[2] :: Vector3, "LaneLine", { free = true })
					stripe.Color = ACCENT_TILE
					stripe.CanCollide = false
				end
			end
		end
	end
end

-- ===== THE TALL HALL =====
--
-- One stretch where the ceiling goes, and it is the only place in the level the building does
-- anything you did not expect.
--
-- Built as a second storey rather than as a taller room: the lower order of columns and arches
-- runs through unchanged, a cornice marks where the old ceiling was, and above it a plain
-- upper wall carries clerestory windows. That is how a real hall of this kind is put together,
-- and it is also the only version that reads as tall -- a room with no line at the old ceiling
-- height has nothing to be twice as tall AS.
local function buildTall(halls: Model)
	local tall = hallTall
	if not tall then
		return
	end
	local leg = tall.leg
	local top = HEIGHT * TALL_MULTIPLIER
	local span = tall.to - tall.from
	local middle = tall.from + span / 2

	for _, side in ipairs({ 1, -1 }) do
		-- The upper wall, standing on the line of the lower one.
		slab(halls, legFrame(leg, middle, side * HALL_HALF_WIDTH, (HEIGHT + top) / 2),
			Vector3.new(WALL_THICK, top - HEIGHT, span), "Wall")

		-- THE CORNICE. A band projecting into the room at exactly the height the ceiling used
		-- to be. Without it the two storeys are one wall with windows at two heights; with it
		-- the eye reads a room stacked on a room, which is the whole effect.
		slab(halls, legFrame(leg, middle,
			side * (HALL_HALF_WIDTH - WALL_THICK / 2 - BAY * 0.07), HEIGHT + SCALE * 0.6),
			Vector3.new(BAY * 0.14, SCALE * 1.2, span), "Cornice")

		-- Clerestory windows, high in the upper wall. Out of reach and out of scale, which is
		-- most of why a tall room feels tall.
		for step = 1, TALL_BAYS do
			lightPanel(halls,
				legFrame(leg, tall.from + (step - 0.5) * (span / TALL_BAYS),
					side * (HALL_HALF_WIDTH - WALL_THICK * 0.4), HEIGHT * 1.52)
					* CFrame.Angles(0, math.pi / 2, 0),
				Vector3.new(BAY * 0.34, HEIGHT * 0.34, WALL_THICK * 0.3), 1.4)
		end
	end

	-- The two ends, closing the upper volume off so the lower ceiling has something to meet.
	for _, at in ipairs({ tall.from, tall.to }) do
		slab(halls, legFrame(leg, at, 0, (HEIGHT + top) / 2),
			Vector3.new(HALL_HALF_WIDTH * 2, top - HEIGHT, WALL_THICK),
			"TallEnd", { free = true })
	end

	-- ===== AND A GLAZED ROOF OVER IT =====
	--
	-- THE ONE THING FROM THE REFERENCES THAT WAS NEVER BUILT. Half of them are shot in a pool
	-- hall under a glass roof: the whole ceiling is sky, the light comes straight down, and the
	-- tile and the water are washed out by it. Everything in this level so far has been lit by
	-- windows in walls, which is why it has read as a basement.
	--
	-- This is the room that answers it. You walk two hundred studs of dim corridor, the ceiling
	-- goes to twice its height, and it is GLASS -- the brightest thing in the level by a wide
	-- margin, throwing hard shadows off the beams onto the water fifty studs below.
	--
	-- It is a lit surface rather than an actual sky, and that is deliberate as well as cheap: a
	-- real skybox is a blue day, and the references are all flat overcast. A pale panel behind
	-- glazing bars IS an overcast sky seen from the bottom of a deep room, and it is the one
	-- version of this that needs no uploaded asset.
	local glazing = Instance.new("Part")
	glazing.Name = "Rooflight"
	glazing.Size = Vector3.new(HALL_HALF_WIDTH * 2 - WALL_THICK, SCALE, span)
	glazing.CFrame = legFrame(leg, middle, 0, top + SCALE * 0.5)
	glazing.Anchored = true
	glazing.CanCollide = false
	glazing.CastShadow = false
	glazing.Material = Enum.Material.Neon
	glazing.Color = ROOF_GLOW
	glazing.Parent = halls

	-- THE GLAZING BARS. Without them it is a glowing rectangle, which is the mistake this level
	-- has made twice; with them it is a roof. They also do the real work: the shadows they
	-- throw are long, parallel, and move as you walk, and that is most of what says "daylight"
	-- rather than "a lamp".
	local bars = math.max(2, math.floor(span / (BAY * 0.5)))
	for index = 0, bars do
		slab(halls, legFrame(leg, middle - span / 2 + index * (span / bars), 0,
			top + SCALE * 0.9),
			Vector3.new(HALL_HALF_WIDTH * 2, SCALE * 0.7, SCALE * 0.9), "GlazingBar",
			{ free = true })
	end
	-- And one down the middle the long way, so the grid reads as a grid.
	slab(halls, legFrame(leg, middle, 0, top + SCALE * 0.9),
		Vector3.new(SCALE * 0.9, SCALE * 0.7, span), "GlazingBar", { free = true })

	-- The light itself. Wide, bright, shadowed: this is the sun as far as this level is
	-- concerned, and everything else in the room is fill against it.
	local daylight = Instance.new("SurfaceLight")
	daylight.Face = Enum.NormalId.Bottom
	daylight.Angle = 130
	daylight.Color = SKY_COLOUR
	daylight.Brightness = 2.1
	daylight.Range = 60 * SCALE
	daylight.Shadows = true
	daylight.Parent = glazing

	-- A tiled surround, so the glass sits in a roof rather than being one.
	for _, spec in ipairs({
		{ Vector3.new(WALL_THICK, 2 * SCALE, span), HALL_HALF_WIDTH, 0 },
		{ Vector3.new(WALL_THICK, 2 * SCALE, span), -HALL_HALF_WIDTH, 0 },
	}) do
		slab(halls, legFrame(leg, middle + (spec[3] :: number), spec[2] :: number,
			top + SCALE), spec[1] :: Vector3, "Ceiling", { free = true })
	end
end

-- WHERE THE TALL STRETCH GOES: the middle of the longest leg that has room for it.
--
-- The longest, because the stretch has to fit between the junctions at either end of its leg
-- and the shortest leg is mostly junction. The middle, because a tall room that begins at a
-- corner reads as part of the corner.
local function chooseTall(route: HallRoute.Route)
	hallTall = nil
	local want = TALL_BAYS * BAY
	local best: HallRoute.Leg? = nil
	for index, leg in ipairs(route.legs) do
		-- HOW MUCH OF THE LEG IS ACTUALLY HALL. A junction eats a corridor width off the end
		-- it sits at, and the first leg has no junction behind it while the last runs into the
		-- chamber instead of into one. Charging every leg for two junctions -- which the first
		-- version did -- undercounts the opening leg by a hundred studs, and on a short route
		-- that is the only leg there is.
		local usable = leg.length
		if index > 1 then
			usable -= HALL_HALF_WIDTH
		end
		if index < #route.legs then
			usable -= HALL_HALF_WIDTH
		end
		if usable > want + BAY * 0.5 and (not best or leg.length > best.length) then
			-- Never the leg the last chamber is on: the chamber is already the payoff at the
			-- end, and two payoffs in a row is neither.
			if index < #route.legs or #route.legs == 1 then
				best = leg
			end
		end
	end
	if not best then
		return
	end

	-- CENTRED IN THE HALL, not in the leg. On the first leg those are different places: the
	-- leg starts in open corridor and ends in a junction, so its midpoint is already a good way
	-- into the junction's half.
	local low = if best == route.legs[1] then -BAY * 0.5 else HALL_HALF_WIDTH
	local high = best.length - (if best == route.legs[#route.legs] then 0 else HALL_HALF_WIDTH)
	local from = math.max(low, (low + high) / 2 - want / 2)
	local to = math.min(high, from + want)
	if to - from < want * 0.75 then
		hallTall = nil
		return
	end
	local least = Vector3.new(math.huge, 0, math.huge)
	local most = Vector3.new(-math.huge, 0, -math.huge)
	for _, at in ipairs({ from, to }) do
		for _, lateral in ipairs({ HALL_HALF_WIDTH - WALL_THICK, -(HALL_HALF_WIDTH - WALL_THICK) }) do
			local where = legFrame(best, at, lateral, 0).Position
			least = Vector3.new(math.min(least.X, where.X), 0, math.min(least.Z, where.Z))
			most = Vector3.new(math.max(most.X, where.X), 0, math.max(most.Z, where.Z))
		end
	end
	hallTall = {
		leg = best,
		from = from,
		to = to,
		box = { minX = least.X, maxX = most.X, minZ = least.Z, maxZ = most.Z },
	}
end

-- ===== WHAT IS OVERHEAD IN THE LAST ROOM =====
--
-- The dome was a bare shell: a plain tiled saucer over the biggest room in the level, with the
-- square edge of the ceiling cut raw round it. Three things, all of them what a domed bath hall
-- actually has, and nothing else:
--
--   AN OCULUS at the crown: a round skylight ringed in tile. It is this room's daylight, falling
--   straight down past the flume into the shaft -- smaller and dimmer than the glazed roof, which
--   has already been turned down once for being too bright.
--   EIGHT RIBS from the oculus to the springing, following the dome's own curve.
--   A FRAME round the square opening in the ceiling, in the pool's dark teal, so the hole reads as
--   a coffer rather than as a cut.
local OCULUS_RADIUS = 18
local OCULUS_GLOW = Color3.fromRGB(178, 192, 198)
local OCULUS_BRIGHTNESS = 1.1
local DOME_RIBS = 8

-- MEASURED OFF THE DOME THAT IS THERE, not off constants: the dome is an import, and its size is the
-- one thing an import reliably carries. gen_flooded_halls sweeps the inner surface as a quarter
-- ellipse, a span across and a rise up, and wraps a shell outside it 1.05 times as wide and two
-- model units (eight studs) taller -- so both numbers fall out of the part.
local function buildDomeDetail(halls: Model, dome: BasePart)
	local up = Vector3.new(0, 1, 0)
	local base = dome.Position - up * (dome.Size.Y / 2)
	local span = dome.Size.X / 2 / 1.05
	local rise = dome.Size.Y - 2 * SCALE
	local function heightAt(d: number): number
		local f = math.clamp(d / span, 0, 1)
		return rise * math.sqrt(1 - f * f)
	end
	local apex = base + up * rise

	-- THE OCULUS: a lit disc just under the crown, the light it lets in, and a ring round it.
	local disc = fitting(halls, "Oculus", Vector3.new(1, OCULUS_RADIUS * 2, OCULUS_RADIUS * 2),
		CFrame.new(apex - up * 1.1) * CFrame.Angles(0, 0, math.pi / 2), OCULUS_GLOW,
		Enum.Material.Neon, Enum.PartType.Cylinder)
	disc.CastShadow = false
	local sky = Instance.new("SurfaceLight")
	-- Stood on end, the cylinder's -X face is the one looking down.
	sky.Face = Enum.NormalId.Left
	sky.Angle = 100
	sky.Color = SKY_COLOUR
	sky.Brightness = OCULUS_BRIGHTNESS
	sky.Range = 45 * SCALE
	sky.Shadows = true
	sky.Parent = disc

	local ringOut = OCULUS_RADIUS + 5
	local ringTop = heightAt(ringOut) - 0.25
	for k = 0, 23 do
		local angle = k / 24 * math.pi * 2
		local spot = base + Vector3.new(math.cos(angle) * (OCULUS_RADIUS + 2.5), ringTop - 1.2,
			math.sin(angle) * (OCULUS_RADIUS + 2.5))
		local block = slab(halls, CFrame.lookAt(spot, Vector3.new(apex.X, spot.Y, apex.Z)),
			Vector3.new(6.4, 2.4, 5), "OculusRing", { free = true })
		block.CanCollide = false
	end

	-- THE RIBS, as chords between points on the curve hung a little inside it. A chord of a surface
	-- curving away from you lies on your side of it, so no rib can come out through the shell.
	local samples = { ringOut, span * 0.4, span * 0.6, span * 0.77, span * 0.89, span * 0.97,
		span - 0.5 }
	for rib = 0, DOME_RIBS - 1 do
		local angle = rib / DOME_RIBS * math.pi * 2
		local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local function under(d: number): Vector3
			local h = heightAt(d)
			-- Off the surface along its own inward normal, so the rib stands square to the dome
			-- even where it turns down toward the springing.
			local normal = -(outward * (d / (span * span)) + up * (h / (rise * rise))).Unit
			return base + outward * d + up * h + normal * 1.55
		end
		for s = 1, #samples - 1 do
			local cf, run = spanFrame(under(samples[s]), under(samples[s + 1]), -up)
			local member = slab(halls, cf, Vector3.new(3.2, 2.4, run + 0.9), "DomeRib",
				{ free = true })
			member.CanCollide = false
		end
	end
end

-- The frame round the square opening, hung under the ceiling's cut edge.
local function buildDomeFrame(halls: Model, roomAt: Vector3)
	for _, spec in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local ax: number, az: number = spec[1], spec[2]
		local reach = DOME_HALF + 3
		local long = DOME_HALF * 2 + 12
		local band = slab(halls,
			CFrame.new(roomAt + Vector3.new(ax * reach, HEIGHT - 2, az * reach)),
			if ax ~= 0 then Vector3.new(6, 4, long) else Vector3.new(long, 4, 6),
			"DomeFrame", { free = true })
		band.Color = ACCENT_TILE
		band.CanCollide = false
	end
end

-- ===== THE LAST CHAMBER =====
--
-- The one room where the water has gone. The floor has given way, and the flume runs down
-- through the hole into whatever is underneath.
--
-- Everything here is placed in the frame of the route's final direction, so the chamber turns
-- with the corridor and the gangway always leads off the walkway to the left.
-- How big the last room is, and where. Called from build() before anything else is placed,
-- because the corridor is built around the answer.
local function chamberFor(endFrame: CFrame): (Vector3, number)
	-- Pushed sideways so it holds both the walkway and the pit, which sit either side of it.
	local room = endFrame * CFrame.new(MOUTH_OFFSET * 0.55, 0, 0)
	-- Wider than the corridor by enough to be a room rather than a widening, and wide enough
	-- to hold the pit, which sits a hundred and sixty studs off the route's centreline.
	return Vector3.new(room.Position.X, hallFloorY, room.Position.Z), BAY * 2.0
end

local function buildEnd(halls: Model, endFrame: CFrame, surfaceY: number): (CFrame, Vector3)
	local up = Vector3.new(0, 1, 0)
	local roomAt, half = chamberFor(endFrame)
	local roomCF = CFrame.fromMatrix(roomAt, endFrame.RightVector, up)
	-- The floor, the ceiling and the water under this room are the level's, not the chamber's.
	-- They are single plates over the whole footprint and the pit is cut out of them where it
	-- falls, which is the only arrangement with no seam running across open floor.

	-- THE MOUTH, out to the left of where the walkway runs out, and the timber gangway that
	-- reaches it. A prompt you have to walk to is a decision; a prompt on the last chunk is
	-- something you trigger by finishing.
	-- ===== THE BRIDGE, THE MOUTH, AND WHICH WAY YOU ARE FACING WHEN YOU REACH IT =====
	--
	-- The flume was ninety degrees out, and it was out by construction rather than by a sign
	-- error: the frame was built from the PIT and the mouth fell wherever the radius put it,
	-- while the direction the tube set off in was whatever the frame's axes happened to be.
	-- That came out as the route's own heading -- so the bridge carried you sideways to an
	-- opening that pointed straight ahead, and you arrived at it square-on.
	--
	-- Built from the walk now, in the order a person experiences it. The walkway runs out. A
	-- bridge goes left, over the hole. At the end of the bridge is the mouth, and the tube
	-- leaves in the direction you are already walking. Everything else -- the helix's centre,
	-- and therefore the pit -- is derived from that rather than the other way round.
	local enter = endFrame.RightVector
	local mouthAt = (endFrame * CFrame.new(MOUTH_OFFSET, 0, MOUTH_ALONG)).Position

	-- ===== THE GANGWAY =====
	--
	-- A timber deck from the end of the walkway out to the mouth, on two steel girders, with rails
	-- along the drop and trestles down into the water.
	--
	-- IT REPLACES TWO THINGS THAT MADE NO SENSE TOGETHER. There was a tiled apron a hundred studs
	-- long and thirty-two wide, which read as a second and bigger platform beside the route rather
	-- than a way to anywhere; and a wooden diving board over the shaft, a plank going nowhere next
	-- to a slab going somewhere. The wood is the way to the flume now, which is a use for it that
	-- nobody has to have explained.
	--
	-- Its far end bears on the flume's crosshead, which the mast carries, and its landward half on
	-- two trestles outside the pit's kerb. Nothing about it is hanging in the air.
	local deckFrom = -GANGWAY_TAIL
	local deckTo = MOUTH_OFFSET
	local deckWide = MOUTH_ALONG * 2
	local plankCount = math.max(1, math.floor((deckTo - deckFrom) / 2.5 + 0.5))
	local pitch = (deckTo - deckFrom) / plankCount
	for index = 0, plankCount - 1 do
		-- Four tones, stepped through out of order, so the deck is boards rather than stripes.
		local tone = PLANK_TONES[(index * 7 + math.floor(index / 3)) % #PLANK_TONES + 1]
		timber(halls, endFrame * CFrame.new(deckFrom + (index + 0.5) * pitch, -1.4, MOUTH_ALONG),
			Vector3.new(pitch - 0.22, 0.8, deckWide), "GangwayPlank", tone)
	end

	-- The girders under both edges, and a timber stringer down the middle. Half a stud short of
	-- the mouth, where the crosshead they bear on is.
	local girderTo = deckTo - 0.5
	for _, z in ipairs({ 1, deckWide - 1 }) do
		local girder = timber(halls, endFrame * CFrame.new((deckFrom + girderTo) / 2, -3.4, z),
			Vector3.new(girderTo - deckFrom, 3.2, 1.6), "GangwayGirder", STEEL_COLOUR)
		girder.Material = Enum.Material.Metal
	end
	timber(halls, endFrame * CFrame.new((deckFrom + girderTo) / 2, -3, MOUTH_ALONG),
		Vector3.new(girderTo - deckFrom, 2.4, 1.8), "GangwayStringer", TIMBER_DARK)

	-- RAILS along the drop: the far edge, the near edge from past the end of the walkway, and the
	-- tail. The route steps on through the gap left in the near edge, and the mouth is left open.
	local function railRun(from: Vector3, to: Vector3)
		local run = (to - from).Magnitude
		local posts = math.max(1, math.ceil(run / 12))
		for k = 0, posts do
			local post = fitting(halls, "GangwayRailPost", Vector3.new(0.6, 4.2, 0.6),
				endFrame * CFrame.new(from:Lerp(to, k / posts) + Vector3.new(0, 1.1, 0)),
				RAIL_COLOUR, Enum.Material.Metal)
			post.CanCollide = true
			post.Reflectance = 0.18
		end
		local lift = Vector3.new(0, 3.2, 0)
		local bar = fitting(halls, "GangwayRail", Vector3.new(run + 0.6, 0.7, 0.7),
			endFrame * CFrame.lookAt(from:Lerp(to, 0.5) + lift, to + lift)
				* CFrame.Angles(0, math.rad(90), 0),
			RAIL_COLOUR, Enum.Material.Metal, Enum.PartType.Cylinder)
		bar.CanCollide = true
		bar.Reflectance = 0.18
	end
	local railTo = deckTo - 4
	railRun(Vector3.new(16, 0, 0.3), Vector3.new(railTo, 0, 0.3))
	railRun(Vector3.new(deckFrom + 0.3, 0, deckWide - 0.3), Vector3.new(railTo, 0, deckWide - 0.3))
	railRun(Vector3.new(deckFrom + 0.3, 0, 0.3), Vector3.new(deckFrom + 0.3, 0, deckWide - 0.3))

	-- THE TRESTLES, on the flooded floor short of the kerb: two posts under the girders, a cap
	-- across them, and a cross of bracing.
	for _, x in ipairs({ 14, 30 }) do
		for _, z in ipairs({ 1.2, deckWide - 1.2 }) do
			timber(halls, endFrame * CFrame.new(x, -(FLOOR_DROP + 7) / 2, z),
				Vector3.new(2.4, FLOOR_DROP - 7, 2.4), "GangwayPost", TIMBER_DARK)
		end
		timber(halls, endFrame * CFrame.new(x, -6, MOUTH_ALONG), Vector3.new(2.6, 2, deckWide + 2),
			"GangwayCap", TIMBER_DARK)
		for _, flip in ipairs({ false, true }) do
			local low = if flip then deckWide - 1.2 else 1.2
			local high = if flip then 1.2 else deckWide - 1.2
			local brace, braceRun = spanFrame(
				(endFrame * CFrame.new(x, -FLOOR_DROP + 6, low)).Position,
				(endFrame * CFrame.new(x, -12, high)).Position, endFrame.RightVector)
			timber(halls, brace, Vector3.new(1.2, 1.2, braceRun), "GangwayBrace", TIMBER_DARK)
		end
	end

	-- WHERE THE HELIX'S CENTRE HAS TO BE for the mouth to be at the end of that bridge with the
	-- tube leaving along it. The rider starts at the helix's local +X and travels along local
	-- -Z, so -Z is the way in and the centre is one radius back along +X from the mouth.
	local zLocal = -enter
	local xLocal = up:Cross(zLocal)
	local axis = mouthAt - xLocal * SLIDE_RADIUS
	local pitAt = Vector3.new(axis.X, hallFloorY, axis.Z)

	-- A KERB ROUND THE HOLE. Two studs of tile standing proud of the floor, which is what
	-- stops the water plane meeting the pit's edge at exactly its own height -- a waterline
	-- that ends flush with a drop reads as a rendering error rather than as a drain.
	for _, spec in ipairs({
		{ Vector3.new(1, 0, 0), PIT_HALF }, { Vector3.new(1, 0, 0), -PIT_HALF },
		{ Vector3.new(0, 0, 1), PIT_HALF }, { Vector3.new(0, 0, 1), -PIT_HALF },
	}) do
		local axis: Vector3 = spec[1] :: Vector3
		local offset: number = spec[2] :: number
		local flat = axis * offset
		local sizeX = if axis.X ~= 0 then 6 else PIT_HALF * 2 + 12
		local sizeZ = if axis.X ~= 0 then PIT_HALF * 2 + 12 else 6
		slab(halls, CFrame.new(pitAt + Vector3.new(flat.X, WATER_DEPTH * 0.7, flat.Z)),
			Vector3.new(sizeX, WATER_DEPTH * 1.4, sizeZ), "Kerb", { free = true })
	end

	-- ===== THE CHAMBER'S OWN WALLS, WITH DOORWAYS WHERE THE CORRIDOR ARRIVES =====
	--
	-- Four sides, and a hole in whichever of them the route comes through.
	--
	-- Which one that is cannot be assumed. The obvious guess -- the corridor arrives from
	-- behind, along the route's final direction -- is right only while the route ends part-way
	-- down a leg. Let it end shortly after a corner, which is the common case, and the
	-- corridor arrives through a SIDE wall instead; a chamber built on the guess seals the
	-- level off a few studs from its end, with no error anywhere.
	--
	-- So the openings are derived. Every leg runs along a world axis and so does every face,
	-- so a leg pierces a face exactly when it runs along that face's normal and its centreline
	-- crosses the face within its width. That is two dot products, and it is right whatever
	-- the route does.
	for _, spec in ipairs({
		{ Vector3.new(1, 0, 0), 1 }, { Vector3.new(1, 0, 0), -1 },
		{ Vector3.new(0, 0, 1), 1 }, { Vector3.new(0, 0, 1), -1 },
	}) do
		local axis: Vector3 = spec[1] :: Vector3
		local sign: number = spec[2] :: number
		-- The face's own two directions in world terms: `axis` is its normal, `across` runs
		-- along it.
		local across = Vector3.new(axis.Z, 0, axis.X)
		local faceAt = roomAt + axis * (sign * half)

		-- Where the corridor comes through, as intervals along the face.
		local gaps: { { number } } = {}
		for _, leg in ipairs(hallRoute.legs) do
			if math.abs(leg.dir:Dot(axis)) < 0.5 then
				continue
			end
			local legAt = hallOrigin + Vector3.new(leg.from.X, hallFloorY, leg.from.Z)
			local reach = (legAt - roomAt):Dot(across)
			-- AND IT HAS TO ACTUALLY REACH THIS FACE. Crossing the face's line is not the same
			-- as crossing the face: on a zig-zag route a leg on the far side of the level runs
			-- along the same axis and can sit at the same lateral offset, and would otherwise
			-- punch a doorway in a wall it is four hundred studs away from.
			local entersAt = legAt:Dot(axis)
			local leavesAt = entersAt + leg.length * leg.dir:Dot(axis)
			local near = math.min(entersAt, leavesAt) - WALL_THICK
			local far = math.max(entersAt, leavesAt) + WALL_THICK
			local faceOn = faceAt:Dot(axis)
			if math.abs(reach) < half and faceOn >= near and faceOn <= far then
				table.insert(gaps, {
					reach - HALL_HALF_WIDTH - WALL_THICK,
					reach + HALL_HALF_WIDTH + WALL_THICK,
				})
			end
		end
		table.sort(gaps, function(a, b)
			return a[1] < b[1]
		end)

		-- The wall in the pieces between them.
		local at = -half
		local segments: { { number } } = {}
		for _, gap in ipairs(gaps) do
			if gap[1] > at then
				table.insert(segments, { at, math.min(gap[1], half) })
			end
			at = math.max(at, gap[2])
		end
		if at < half then
			table.insert(segments, { at, half })
		end

		for _, piece_ in ipairs(segments) do
			local low: number, high: number = piece_[1], piece_[2]
			if high - low > 2 then
				local middle = faceAt + across * ((low + high) / 2)
				tiledWall(halls, CFrame.fromMatrix(
					middle + Vector3.new(0, HEIGHT / 2, 0), axis, Vector3.new(0, 1, 0)),
					Vector3.new(WALL_THICK, HEIGHT, high - low), "Wall", { free = true })

				-- WINDOWS SET INTO THIS STRETCH OF WALL, which is where the chamber's light comes
				-- from now. Only on stretches long enough to hold one, so a short return beside a
				-- doorway does not get a window squeezed into it.
				if high - low > BAY * 0.7 then
					local runs = math.max(1, math.floor((high - low) / (BAY * 1.4)))
					for k = 1, runs do
						local at = low + (k - 0.5) * (high - low) / runs
						-- Just inside the wall's own plane, so the reveal reads round it.
						local spot = faceAt + across * at - axis * (sign * WALL_THICK * 0.4)
						-- fromMatrix(across, up) makes Z the wall's normal, which is the axis a
						-- wall window is left open along.
						local window = lightPanel(halls,
							CFrame.fromMatrix(spot + Vector3.new(0, HEIGHT * 0.7, 0), across,
								Vector3.new(0, 1, 0)),
							Vector3.new(BAY * 0.3, HEIGHT * 0.26, WALL_THICK * 0.3), 1.1)
						window.Name = "ChamberWindow"
						local lamp = window:FindFirstChildOfClass("PointLight")
						if lamp then
							lamp.Shadows = false
						end
					end
				end
			end
		end
	end
	-- THE DOME SITS ON THE CEILING, not under it.
	--
	-- It is 312 studs across and 70 tall, and the ceiling is at 88. Placed inside the room it
	-- is a saucer hanging in mid-air; placed at 0.82 of the height, as it was, it is a saucer
	-- hanging in mid-air with the ceiling slab cutting across it. Neither is a dome.
	--
	-- A dome is a hole in a ceiling with a cap over it, so that is what it is: the ceiling
	-- plate below is cut with an opening slightly narrower than this, and this covers it. From
	-- underneath the room simply opens upward, which is what every one of the references does
	-- with its light.
	local dome = piece(halls, "Hall_Dome", CFrame.new(roomAt + Vector3.new(0, HEIGHT, 0)),
		{ free = true })
	-- AND WHAT IS UNDER IT: an oculus, ribs, and a frame round the opening. See buildDomeDetail.
	if dome then
		buildDomeDetail(halls, dome)
	end
	buildDomeFrame(halls, roomAt)

	-- (THE DOME'S RING OF LIGHTS HAS MOVED ONTO THE WALLS. It was six panels placed on a circle
	-- 173 studs out -- written for a round room and set down in a square one, so every panel was
	-- between nineteen and forty-two studs from the nearest wall, glowing in mid-air. They are in
	-- the wall loop above now, set into the chamber's own walls.)

	-- ===== THE PIT =====
	--
	-- Four black walls, one width, all the way down. See PIT_WALL_DEPTH: any change of width
	-- puts a ledge round the join, and a lit ledge is what reads as the bottom.
	for _, spec in ipairs({
		{ Vector3.new(1, 0, 0), PIT_HALF }, { Vector3.new(1, 0, 0), -PIT_HALF },
		{ Vector3.new(0, 0, 1), PIT_HALF }, { Vector3.new(0, 0, 1), -PIT_HALF },
	}) do
		local axis: Vector3 = spec[1] :: Vector3
		local offset: number = spec[2] :: number
		local flat = axis * offset
		local sizeX = if axis.X ~= 0 then 4 else PIT_HALF * 2 + 8
		local sizeZ = if axis.X ~= 0 then PIT_HALF * 2 + 8 else 4
		slab(halls, CFrame.new(pitAt + Vector3.new(flat.X, -PIT_WALL_DEPTH / 2, flat.Z)),
			Vector3.new(sizeX, PIT_WALL_DEPTH, sizeZ), "PitWall",
			{ free = true, dark = true })
	end

	-- The floor, four hundred studs down and the same near-black as the walls that reach it.
	-- There is no ledge above it and nothing lighting it, so there is no line for the eye to
	-- catch: it is the same shade as the wall beside it at the same depth.
	slab(halls, CFrame.new(pitAt + Vector3.new(0, -PIT_WALL_DEPTH - 4, 0)),
		Vector3.new(PIT_HALF * 2 + 8, 8, PIT_HALF * 2 + 8), "VoidFloor",
		{ free = true, dark = true })

	-- (THE DIVING BOARD IS GONE. A springboard over the shaft was meant as a joke about a pool
	-- with no water left in it; in game it read as a second plank going nowhere, beside the
	-- gangway that goes somewhere, and it was reported as not making sense. The wood is the
	-- gangway now.)

	-- ===== A LADDER INTO IT =====
	--
	-- Hung rather than stood: Hall_Rail is modelled rising from its base, so hanging it puts
	-- its top at the rim and the rest of it inside the shaft. A pool ladder descending into
	-- four hundred studs of nothing is the one joke left in this room, and it does not need a
	-- second one beside it.
	for _, side in ipairs({ 1, -1 }) do
		local rung = piece(halls, "Hall_Rail",
			CFrame.fromMatrix(pitAt + xLocal * (PIT_HALF - 3)
				+ up:Cross(xLocal) * (side * 11), up:Cross(xLocal), up, xLocal),
			{ hang = true, free = true })
		if rung then
			rung.Material = Enum.Material.Metal
			rung.Color = Color3.fromRGB(198, 200, 196)
			rung.Reflectance = 0.18
			rung.CanCollide = false
		end
	end

	-- ===== THE FLUME =====
	--
	-- The one object in the level made of moulded plastic rather than tile, which is what makes
	-- it read as the only thing here that was ever meant to be enjoyed.
	-- LIFTED BY A BORE. The frame's origin is the tube's centre line, so putting it at walking
	-- height would sink the trough a bore below the bridge and stand its rim a bore above it --
	-- a slide you step DOWN into and cannot see over. Raised by exactly one flared bore, the
	-- trough at the mouth is level with the floor beside it.
	--
	-- fromMatrix works the third axis out as vX:Cross(vY), which for these two is exactly
	-- zLocal -- so the tube leaves along the bridge, which is the whole point of the block
	-- above.
	local slideFrame = CFrame.fromMatrix(
		Vector3.new(axis.X, surfaceY + SLIDE_MOUTH_LIFT, axis.Z), xLocal, up)
	-- BUILT FROM THE CURVE, as an open flume on its own mast. See buildFlume.
	buildFlume(halls, slideFrame)

	-- (THE ENTRANCE PIECES ARE GONE: a threshold tray, stepped cheeks and a lintel. The tray was
	-- a second platform laid on top of the bridge; the lintel hung eight studs above the cheeks
	-- it was meant to span; and all three were dressing a mouth that was somewhere else. With
	-- the tube built from the same curve the bridge is measured from, the bridge simply runs
	-- into its open end, which is the only entrance a tube needs.)
	return slideFrame, pitAt
end

-- ===== PIERS UNDER THE WALKWAY INSIDE THE LAST CHAMBER =====
--
-- buildLeg carries the walkway on a pier per bay, but it skips every bay inside the last
-- chamber -- the chamber builds its own walls -- so the final stretch of chunks crossed the
-- biggest room in the level held up by nothing at all. This walks the legs through the chamber
-- on the same spacing and fills that in, keeping clear of the pit and of the chamber's edge so
-- a pier never lands a stud from the corridor's last one.
local function buildChamberPiers(halls: Model, pitAt: Vector3)
	local pierTop = FLOOR_DROP - 7
	local capital = SCALE * 1.6
	for _, leg in ipairs(hallRoute.legs) do
		local along = BAY * 0.5
		while along < leg.length do
			local p = legFrame(leg, along, 0, 0).Position
			local deepInside = math.abs(p.X - chamberAt.X) < chamberHalf - 24
				and math.abs(p.Z - chamberAt.Z) < chamberHalf - 24
			local overPit = math.abs(p.X - pitAt.X) < PIT_HALF + 10
				and math.abs(p.Z - pitAt.Z) < PIT_HALF + 10
			if deepInside and not overPit then
				slab(halls, legFrame(leg, along, 0, (pierTop - capital) / 2),
					Vector3.new(11, pierTop - capital, 11), "Pier")
				slab(halls, legFrame(leg, along, 0, pierTop - capital / 2),
					Vector3.new(16, capital, 16), "PierCap")
			end
			along += BAY
		end
	end
end

-- ===== BEHIND THE START =====
--
-- Turn round at the spawn and there was nothing there. The first leg's walls began half a bay back
-- and nothing closed them: the floor, the water and the ceiling ran on for three hundred and fifty
-- studs to the edges of their plates, with daylight showing under the last of them.
--
-- A building has an end, and in this genre the end wall is the most useful wall there is, because
-- it is the first thing that can say there is more of the place than you are going to see. So:
-- another bay of hall behind the start, a dry tiled deck along its end wall, a lifeguard's chair
-- nobody is sitting in, a clock that has stopped -- and in the middle of the wall a tall doorway
-- into a flooded passage with no light of its own. Far down the passage, round a corner you cannot
-- see past, something is lit. You cannot reach any of it, and none of it explains itself.
local ENTRANCE_PAINT = Color3.fromRGB(222, 220, 208)

-- A lifeguard's chair, in `base`'s frame: standing on its origin, facing its +Z.
local function buildLifeguardChair(halls: Model, base: CFrame)
	local ahead = Vector3.new(0, 0, 1)
	local up = Vector3.new(0, 1, 0)
	local function member(from: Vector3, to: Vector3, thick: number, normal: Vector3)
		local cf, run = spanFrame(base:PointToWorldSpace(from), base:PointToWorldSpace(to),
			base:VectorToWorldSpace(normal))
		timber(halls, cf, Vector3.new(thick, thick, run + thick * 0.5), "LifeguardChair",
			ENTRANCE_PAINT)
	end
	for _, x in ipairs({ -7, 7 }) do
		-- Legs splayed front and back, the back pair carrying on up into the backrest.
		member(Vector3.new(x, 0, -8), Vector3.new(x, 30, -4), 1.6, ahead)
		member(Vector3.new(x, 0, 8), Vector3.new(x, 30, 4), 1.6, ahead)
		member(Vector3.new(x, 30, -4), Vector3.new(x, 42, -6), 1.4, ahead)
		-- A stretcher between each pair, an arm, and the post holding the arm up.
		member(Vector3.new(x, 10, -6.67), Vector3.new(x, 10, 6.67), 1, up)
		member(Vector3.new(x * 1.07, 34.5, -4), Vector3.new(x * 1.07, 34.5, 5), 1.2, up)
		member(Vector3.new(x * 1.07, 31, 4.5), Vector3.new(x * 1.07, 34.5, 4.5), 1, ahead)
	end
	-- Two rungs up the front, the foot rest, the seat, and two slats across the back.
	for _, y in ipairs({ 7, 12 }) do
		member(Vector3.new(-7, y, 8 - 4 * y / 30), Vector3.new(7, y, 8 - 4 * y / 30), 1, up)
	end
	timber(halls, base * CFrame.new(0, 17, 7.3), Vector3.new(15, 0.9, 3.2), "LifeguardChair",
		ENTRANCE_PAINT)
	timber(halls, base * CFrame.new(0, 30.6, 0), Vector3.new(16, 1.2, 10), "LifeguardChair",
		ENTRANCE_PAINT)
	for _, y in ipairs({ 35.5, 40 }) do
		local function onBack(h: number): Vector3
			return Vector3.new(0, h, -3.2 - (h - 30) / 6)
		end
		local cf = spanFrame(base:PointToWorldSpace(onBack(y - 1.8)),
			base:PointToWorldSpace(onBack(y + 1.8)), base:VectorToWorldSpace(ahead))
		timber(halls, cf, Vector3.new(15.4, 0.8, 3.6), "LifeguardChair", ENTRANCE_PAINT)
	end
end

-- A wall clock, stopped, in `face`'s frame: its +Z comes out of the wall toward whoever is looking.
local function buildClock(halls: Model, face: CFrame)
	local turn = CFrame.Angles(0, math.pi / 2, 0)
	local ink = Color3.fromRGB(34, 38, 40)
	fitting(halls, "ClockRim", Vector3.new(1.2, 20, 20), face * CFrame.new(0, 0, 0.1) * turn,
		Color3.fromRGB(52, 58, 58), Enum.Material.Metal, Enum.PartType.Cylinder)
	fitting(halls, "ClockFace", Vector3.new(0.6, 17.5, 17.5), face * CFrame.new(0, 0, 0.6) * turn,
		Color3.fromRGB(236, 232, 218), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	-- Something on the face at `clockwise` degrees from twelve, running `from` studs out from the
	-- centre along its own length. Seen from the hall the face's +X is the viewer's right, so a
	-- turn of minus that angle about Z carries twelve round the right way.
	local function mark(name: string, clockwise: number, size: Vector3, from: number, out: number)
		fitting(halls, name, size,
			face * CFrame.new(0, 0, out) * CFrame.Angles(0, 0, -math.rad(clockwise))
				* CFrame.new(0, from + size.Y / 2, 0), ink, Enum.Material.SmoothPlastic)
	end
	for k = 0, 11 do
		local major = k % 3 == 0
		mark("ClockTick", k * 30,
			Vector3.new(if major then 0.7 else 0.4, if major then 2.4 else 1.4, 0.2),
			if major then 5.9 else 6.9, 0.95)
	end
	-- STOPPED, at thirteen minutes to five. Not midnight and not a round number: a time that means
	-- nothing is the one that reads as the moment it actually stopped.
	mark("ClockHand", (4 + 47 / 60) * 30, Vector3.new(0.8, 5, 0.3), -1, 1.1)
	mark("ClockHand", 47 * 6, Vector3.new(0.55, 7.4, 0.3), -1, 1.3)
	fitting(halls, "ClockPin", Vector3.new(0.4, 1.3, 1.3), face * CFrame.new(0, 0, 1.5) * turn,
		ink, Enum.Material.Metal, Enum.PartType.Cylinder)
end

local function buildEntrance(halls: Model, leg: HallRoute.Leg)
	local back = -ENTRANCE_DEPTH
	if insideChamber(legFrame(leg, back, 0, 0).Position) then
		return
	end
	local inner = HALL_HALF_WIDTH - WALL_THICK / 2
	local outer = HALL_HALF_WIDTH + WALL_THICK / 2

	-- THE END WALL, in three pieces round the doorway, the dado carried round from the side walls
	-- and a tiled architrave standing proud of the opening.
	for _, hand in ipairs({ 1, -1 }) do
		tiledWall(halls, legFrame(leg, back - WALL_THICK / 2, hand * (DOOR_HALF + outer) / 2,
			HEIGHT / 2), Vector3.new(outer - DOOR_HALF, HEIGHT, WALL_THICK), "BackWall")
	end
	tiledWall(halls, legFrame(leg, back - WALL_THICK / 2, 0, (DOOR_HEIGHT + HEIGHT) / 2),
		Vector3.new(DOOR_HALF * 2, HEIGHT - DOOR_HEIGHT, WALL_THICK), "BackWall", nil, DOOR_HEIGHT)
	for _, jamb in ipairs({
		{ Vector3.new(SCALE, DOOR_HEIGHT + SCALE, WALL_THICK * 0.5), DOOR_HALF + SCALE / 2,
			(DOOR_HEIGHT + SCALE) / 2 },
		{ Vector3.new(SCALE, DOOR_HEIGHT + SCALE, WALL_THICK * 0.5), -(DOOR_HALF + SCALE / 2),
			(DOOR_HEIGHT + SCALE) / 2 },
		{ Vector3.new(DOOR_HALF * 2 + SCALE * 2, SCALE, WALL_THICK * 0.5), 0,
			DOOR_HEIGHT + SCALE / 2 },
	}) do
		slab(halls, legFrame(leg, back + WALL_THICK * 0.25, jamb[2] :: number, jamb[3] :: number),
			jamb[1] :: Vector3, "Architrave")
	end

	-- THE DECK: dry tile along the foot of the end wall, either side of the water running in
	-- through the doorway. Steps down into the water off one side; the chair on the other, turned
	-- a little toward the doorway as if somebody had been watching it.
	local deckDepth = BAY * 0.22
	for _, hand in ipairs({ 1, -1 }) do
		local from = DOOR_HALF + SCALE
		slab(halls, legFrame(leg, back + deckDepth / 2, hand * (from + inner) / 2, LEDGE_RISE / 2),
			Vector3.new(inner - from, LEDGE_RISE, deckDepth), "EntranceDeck")
	end
	for step = 1, 2 do
		local top = LEDGE_RISE * (1 - step / 3)
		slab(halls, legFrame(leg, back + deckDepth + (step - 0.5) * 4, -90, top / 2),
			Vector3.new(18, top, 4), "EntranceStep")
	end
	buildLifeguardChair(halls,
		legFrame(leg, back + 10, 84, LEDGE_RISE) * CFrame.Angles(0, math.rad(-12), 0))
	-- Two studs clear of the architrave's head, so it hangs on the wall rather than sitting on the
	-- door frame.
	buildClock(halls, legFrame(leg, back + 0.5, 0, DOOR_HEIGHT + 16))

	-- ONE MORE BAY OF THE HALL'S OWN RHYTHM: the colonnade, a beam, and a single window high on one
	-- side, dimmer than any on the route. Enough to see the end wall by; not enough to see into
	-- the doorway.
	local mid = back + BAY * 0.5
	for _, side in ipairs({ 1, -1 }) do
		piece(halls, "Hall_Column", legFrame(leg, mid, side * (LANE_HALF + BAY * 0.3), 0))
	end
	slab(halls, legFrame(leg, mid, 0, HEIGHT - SCALE * 0.9),
		Vector3.new(HALL_HALF_WIDTH * 2, SCALE * 1.8, BAY * 0.16), "Beam")
	local window = lightPanel(halls,
		legFrame(leg, mid, HALL_HALF_WIDTH - WALL_THICK * 0.4, HEIGHT * 0.74)
			* CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(BAY * 0.16, HEIGHT * 0.42, WALL_THICK * 0.3), 0.8)
	local lamp = window:FindFirstChildOfClass("PointLight")
	if lamp then
		lamp.Range = 26 * SCALE
		lamp.Shadows = false
	end

	-- ===== THE PASSAGE =====
	--
	-- Straight back from the doorway, full height and a third of the hall's width, ending in a
	-- blank wall. The last half-bay of its left side opens into a side room that cannot be seen
	-- into from anywhere on the route, and that room has a window. All you get from the spawn is
	-- its light, on the far end of the passage and on the water.
	local near = back - WALL_THICK
	local far = near - PASSAGE_LENGTH
	local alcove = far + BAY * 0.5
	local alcoveOut = PASSAGE_HALF + BAY * 0.62
	local wallOff = PASSAGE_HALF + WALL_THICK / 2
	tiledWall(halls, legFrame(leg, (near + far) / 2, -wallOff, HEIGHT / 2),
		Vector3.new(WALL_THICK, HEIGHT, near - far), "PassageWall")
	tiledWall(halls, legFrame(leg, (near + alcove) / 2, wallOff, HEIGHT / 2),
		Vector3.new(WALL_THICK, HEIGHT, near - alcove), "PassageWall")
	-- The end, across the passage and the side room both; the side room's far wall and its front.
	tiledWall(halls, legFrame(leg, far - WALL_THICK / 2, (alcoveOut - PASSAGE_HALF) / 2, HEIGHT / 2),
		Vector3.new(alcoveOut + PASSAGE_HALF + WALL_THICK * 2, HEIGHT, WALL_THICK), "PassageWall")
	tiledWall(halls, legFrame(leg, (far + alcove) / 2, alcoveOut + WALL_THICK / 2, HEIGHT / 2),
		Vector3.new(WALL_THICK, HEIGHT, alcove - far + WALL_THICK * 2), "PassageWall")
	tiledWall(halls, legFrame(leg, alcove + WALL_THICK / 2, (PASSAGE_HALF + alcoveOut + WALL_THICK) / 2,
		HEIGHT / 2), Vector3.new(alcoveOut + WALL_THICK - PASSAGE_HALF, HEIGHT, WALL_THICK),
		"PassageWall")
	local light = lightPanel(halls,
		legFrame(leg, (far + alcove) / 2, alcoveOut + WALL_THICK / 2 - WALL_THICK * 0.4,
			HEIGHT * 0.55) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(BAY * 0.22, HEIGHT * 0.4, WALL_THICK * 0.3), 3.4)
	light.Name = "PassageLight"
	local spill = light:FindFirstChildOfClass("PointLight")
	if spill then
		-- Far enough to reach round the corner onto the passage floor. It keeps its shadows, which
		-- is what stops it lighting the hall through the walls between.
		spill.Range = 30 * SCALE
	end
end

-- Where the RIDER is at f in 0..1 along the ride, in the flume's own frame.
--
-- SHARED BY THE MESH, THE PROMPT AND THE RIDE so none of the three can disagree about where
-- the flume is. The prompt sits at the mouth and the ride starts there; writing the top
-- position twice is how it ends up in mid-air beside the tube.
--
-- The rider rides RIDE_SINK below the tube's centre line, which is what helixAt returns: their
-- root is about three studs above their feet, so this puts the feet on the trough and the head
-- inside the tube rather than floating up the middle of it.
local function slidePoint(f: number): Vector3
	if f <= SLIDE_HELIX then
		return helixAt(f / SLIDE_HELIX) - Vector3.new(0, RIDE_SINK, 0)
	end
	-- PAST THE END OF THE TUBE. Squared, so it accelerates: this is a fall, and a fall that
	-- covers equal distance in equal time is a lift.
	local g = (f - SLIDE_HELIX) / (1 - SLIDE_HELIX)
	local out = helixAt(1) - Vector3.new(0, RIDE_SINK, 0)
	return Vector3.new(out.X, out.Y - SLIDE_PLUNGE * g * g, out.Z)
end

-- Which way is up for the rider at f: the trough's banked up through the helix, easing back to
-- straight up over the first moments of the fall rather than snapping to it.
local function slideUp(f: number): Vector3
	if f <= SLIDE_HELIX then
		local _, _, _, banked = flumeBasis(f / SLIDE_HELIX)
		return banked
	end
	local _, _, _, last = flumeBasis(1)
	return last:Lerp(Vector3.new(0, 1, 0), math.clamp((f - SLIDE_HELIX) / 0.06, 0, 1)).Unit
end

function FloodedHallsService.build(origin: Vector3, level: any?): Model
	local halls = Instance.new("Model")
	halls.Name = "FloodedHalls"
	local rng = Random.new(20260903)

	-- ===== THE ROUTE THE CHUNKS ACTUALLY TOOK =====
	--
	-- Not an estimate and not a copy: LevelService hands back the distance it used, corners
	-- and all, and HallRoute is prefix-consistent, so building to that length reproduces
	-- exactly the corridor those chunks were laid along.
	--
	-- The fallback is for a caller with no level -- a scratch build in Studio -- and is
	-- deliberately plain rather than clever.
	local surfaceY = origin.Y + ((level and level.routeSurfaceY) or 24)
	local routeLength = (level and level.routeLength) or (HallRoute.BAY * 11)
	hallOrigin = origin
	-- BUILT FROM THE LEGS THE CHUNKS ACTUALLY TOOK. LevelService turns wherever its chunks turn
	-- and records how long each leg came out. Building from the fixed plan instead is what used
	-- to leave a chunk-shaped mismatch at every corner.
	hallRoute = if level and level.routeLegs
		then HallRoute.fromLegs(level.routeLegs)
		else HallRoute.build(routeLength)
	hallFloorY = surfaceY - FLOOR_DROP
	hallSurfaceY = surfaceY
	laneWarned = false

	-- WHERE THE LEVEL ENDS, WORKED OUT FIRST. Everything below asks whether it is standing in
	-- the last room, and nothing can ask that until the room has a position.
	local endFrame = (level and level.routeEnd)
		or HallRoute.frameAt(hallRoute, routeLength, surfaceY - origin.Y) + origin
	chamberAt, chamberHalf = chamberFor(endFrame)

	local legs = hallRoute.legs
	-- Cleared per build, not per server. These are module state so that the bay loop can record
	-- a basin and the plate pass can cut it out; left over from a previous run they would be
	-- holes in the new level's floor at the old level's coordinates.
	hallBasins = {}
	chooseTall(hallRoute)
	choosePools(hallRoute)

	for index, leg in ipairs(legs) do
		buildLeg(halls, leg, index, index == #legs, rng)
	end
	for _, corner in ipairs(HallRoute.corners(hallRoute)) do
		buildJunction(halls, corner)
	end
	-- BEHIND THE START. See buildEntrance.
	buildEntrance(halls, legs[1])

	-- ===== THE END, and the way down out of it =====
	--
	-- BEFORE THE FLOOR, because the floor has a hole in it and this is what decides where.
	local slideFrame, pitAt = buildEnd(halls, endFrame, surfaceY)
	buildChamberPiers(halls, pitAt)

	-- ===== THE FLOODED FLOOR, THE CEILING AND THE WATER =====
	--
	-- One plate each over the whole footprint rather than one per leg. Everything outside the
	-- corridor is behind a wall and never seen, so three enormous surfaces are cheaper in every
	-- sense than forty accurate ones -- and they cannot develop a seam at a junction, which
	-- forty accurate ones certainly would.
	local low = Vector3.new(math.huge, 0, math.huge)
	local high = Vector3.new(-math.huge, 0, -math.huge)
	for _, leg in ipairs(legs) do
		for _, point in ipairs({ leg.from, leg.to }) do
			low = Vector3.new(math.min(low.X, point.X), 0, math.min(low.Z, point.Z))
			high = Vector3.new(math.max(high.X, point.X), 0, math.max(high.Z, point.Z))
		end
	end
	-- Generous enough to reach past the last chamber, which sits off to one side of the route
	-- end and is the furthest thing from any leg.
	local margin = HALL_HALF_WIDTH + BAY * 2.6
	local spanX = (high.X - low.X) + margin * 2
	local spanZ = (high.Z - low.Z) + margin * 2
	local middle = origin + Vector3.new((low.X + high.X) / 2, 0, (low.Z + high.Z) / 2)

	local x0, x1 = middle.X - spanX / 2, middle.X + spanX / 2
	local z0, z1 = middle.Z - spanZ / 2, middle.Z + spanZ / 2

	-- EVERY HOLE IN ONE LIST PER SURFACE, because they are cut in one pass. Two passes of a
	-- single-hole cutter over the same plate would each re-cover the other's opening, which is
	-- the bug the general version exists to make unavailable.
	local sunken: { Hole } = { holeAt(pitAt, PIT_HALF) }
	for _, pool in ipairs(hallPools) do
		table.insert(sunken, pool.box)
	end
	for _, basin in ipairs(hallBasins) do
		table.insert(sunken, holeAt(basin.at, basin.half))
	end
	plate(halls, hallFloorY - SCALE, x0, x1, z0, z1, 2 * SCALE, sunken, "Floor",
		{ free = true })

	-- THE CEILING opens in two places: under the dome, and over the tall hall.
	local open: { Hole } = { holeAt(chamberAt, DOME_HALF) }
	if hallTall then
		table.insert(open, hallTall.box)
	end
	plate(halls, hallFloorY + HEIGHT + SCALE, x0, x1, z0, z1, 2 * SCALE, open, "Ceiling",
		{ free = true })

	-- THE WATER.
	--
	-- Not Terrain water: this has to be perfectly flat and perfectly still, and Terrain water
	-- flows and foams. A transparent plate with a high reflectance is most of the effect -- the
	-- tiles read through it and the columns reflect in it. applyWater below gives it the rest:
	-- a swell, and rings spreading from where things drip into it.
	--
	-- With the same holes in it as the floor. The pit is where all of it went, and each basin
	-- carries its own deeper column of water instead.
	plate(halls, hallFloorY + WATER_DEPTH / 2, x0, x1, z0, z1, WATER_DEPTH, sunken, "Water",
		{ free = true }, WATER_TILE)
	for _, item in ipairs(halls:GetChildren()) do
		if item:IsA("BasePart") and item.Name == "Water" then
			item.CanCollide = false
			item.CanTouch = false
			item.Material = WATER_MATERIAL
			item.Color = WATER_COLOUR
			item.Transparency = 0.46
			item.Reflectance = 0.32
			item.CastShadow = false
		end
	end

	-- The basins, now the holes they sit in exist.
	for _, basin in ipairs(hallBasins) do
		buildBasin(halls, basin)
	end
	-- And the pool down the middle, now its holes are cut. See buildPools.
	buildPools(halls)
	buildTall(halls)

	-- THE ONE DEEP END USED TO BE PLACED BY HAND HERE, on the first leg, at a fixed depth,
	-- and covered over by the floor plate so that nobody ever saw it. It is now one of the
	-- basins above: chosen per bay, at one of three depths, with the floor and the water both
	-- cut open over it.
	--
	-- THE HAND, far down a leg and off to the side, floating just under the surface. Placed
	-- deliberately rather than scattered: something half-glimpsed across a flooded room is
	-- unsettling in a way the same object at arm's length never is, because at arm's length
	-- you can tell what it is.
	local handLeg = legs[math.min(2, #legs)]
	local hand = piece(halls, "Hall_Hand",
		legFrame(handLeg, handLeg.length * 0.6, LANE_HALF + BAY * 0.45, WATER_DEPTH - 2.6 * SCALE)
			* CFrame.Angles(0, math.rad(38), math.rad(-12)), { centred = true })
	if hand then
		hand.Material = Enum.Material.SmoothPlastic
		hand.Color = Color3.fromRGB(206, 198, 186)
		hand.CanCollide = false
	end

	-- Ordinary debris, which does the opposite job: it makes the hand plausible. A single
	-- anomaly in an empty room reads as placed by a designer; the same anomaly among floating
	-- junk reads as something that happened.
	for _ = 1, 8 do
		local leg = legs[rng:NextInteger(1, #legs)]
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		local junk = Instance.new("Part")
		junk.Name = "Debris"
		junk.Size = Vector3.new(rng:NextNumber(1.2, 3.2), rng:NextNumber(0.4, 1.0),
			rng:NextNumber(1.2, 3.2)) * SCALE
		junk.CFrame = legFrame(leg, rng:NextNumber(0, leg.length),
			side * rng:NextNumber(LANE_HALF + BAY * 0.2, HALL_HALF_WIDTH - BAY * 0.2),
			WATER_DEPTH - junk.Size.Y * 0.35)
			* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		junk.Anchored = true
		junk.CanCollide = false
		junk.CastShadow = false
		junk.Material = Enum.Material.Wood
		junk.Color = Color3.fromRGB(96, 86, 70)
		junk.Parent = halls
	end

	-- ===== ONE LIGHT IN THE LEVEL IS FAILING =====
	--
	-- Exactly one, chosen at random, and it is the single cheapest thing here that makes the
	-- building feel abandoned rather than merely empty.
	--
	-- An empty room that is in perfect working order is a room BEFORE opening time. A room with
	-- one fitting stuttering in it is a room nobody has come back to, and the difference
	-- between those two readings is the whole genre. It also does something no static detail
	-- can: it draws the eye to a bay you were not looking at, on a schedule you cannot predict,
	-- which is the only thing in this level that ever surprises you twice.
	--
	-- Marked here and driven by applyWater's loop, because this level has one animation loop
	-- and adding a second for one light would be a second thing to remember to shut down.
	local fittings = {}
	for _, item in ipairs(halls:GetChildren()) do
		if item:IsA("BasePart") and item.Name == "RoofLight" then
			table.insert(fittings, item)
		end
	end
	if #fittings > 2 then
		-- Never the first or the last: the first is where you arrive and the last is over the
		-- flume, and both are places a player needs to be able to see.
		fittings[rng:NextInteger(2, #fittings - 1)]:SetAttribute("Failing", true)
	end

	-- Recorded on the model so Bootstrap can move the finish here without this module having to
	-- know what a finish is.
	halls:SetAttribute("SlideFrame", slideFrame)
	halls:SetAttribute("SlideTop", slideFrame * CFrame.new(slidePoint(0)))
	halls:SetAttribute("SlideLanding", slideFrame * CFrame.new(slidePoint(1)))

	halls.Parent = workspace
	print(("FloodedHallsService: %d legs over %d studs, %d corners, walkway %d studs above "
		.. "the water."):format(#legs, math.floor(routeLength),
		#HallRoute.corners(hallRoute), FLOOR_DROP - WATER_DEPTH))
	return halls
end

-- ===== RIDING IT =====
--
-- Hold E at the mouth, and the flume carries you down and drops you.
--
-- HELD, NOT PRESSED, and for the same reason the benches are: a tap is something you can do by
-- accident while running past, and this one ends the level. A hold is a decision.
--
-- The rider is moved by writing the root CFrame each frame rather than by physics. A physical
-- slide needs a smooth collidable tube, tuned friction and a character that does not catch on
-- seams, and gets you a rider stuck halfway down about one run in five. Driving the position
-- directly is not a shortcut here, it is the only version that always works, and on a ride
-- nobody steers there is nothing physics would have added.
function FloodedHallsService.attachSlide(halls: Model, onArrive: ((Player) -> ())?): () -> ()
	local frame = halls:GetAttribute("SlideFrame")
	if typeof(frame) ~= "CFrame" then
		return function() end
	end
	local slideFrame: CFrame = frame

	-- THE PROMPT SITS ON THE GANGWAY, at the mouth's threshold, not on the ride's first frame.
	-- Those are a few studs apart -- the ride starts inside the trough -- and the difference is
	-- whether you can reach the prompt from the floor you are standing on.
	local mount = Instance.new("Part")
	mount.Name = "SlideMount"
	mount.Size = Vector3.new(12, 6, 12)
	mount.CFrame = slideFrame * CFrame.new(SLIDE_RADIUS, -SLIDE_MOUTH_LIFT + 3, 0)
	mount.Anchored = true
	mount.CanCollide = false
	mount.Transparency = 1
	mount.Parent = halls

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Ride"
	prompt.ObjectText = "Flume"
	prompt.HoldDuration = 0.8
	prompt.MaxActivationDistance = 22
	prompt.RequiresLineOfSight = false
	prompt.Parent = mount

	local riding: { [Player]: boolean } = {}

	local connection = prompt.Triggered:Connect(function(player: Player)
		if riding[player] then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (root and root:IsA("BasePart") and humanoid) then
			return
		end
		riding[player] = true

		task.spawn(function()
			-- PLATFORMSTAND, not Anchored. Anchoring the root freezes the whole assembly and
			-- the limbs stop moving with it, so the rider arrives as a statue. PlatformStand
			-- keeps the character simulated but takes control away, which is what a ride is.
			humanoid.PlatformStand = true
			local started = os.clock()
			while true do
				local f = (os.clock() - started) / SLIDE_SECONDS
				if f >= 1 or not root.Parent then
					break
				end
				local here = slideFrame * CFrame.new(slidePoint(f))
				-- Facing along the flume rather than fixed, so the rider turns through the
				-- bend instead of going down it sideways -- and looks straight down once the
				-- tube has run out, which is the point of the last third.
				local ahead = slideFrame * CFrame.new(slidePoint(math.min(1, f + 0.02)))
				-- BANKED WITH THE TROUGH through the helix, so the rider leans into the turn the
				-- way the flume does instead of riding bolt upright up its outer wall.
				root.CFrame = CFrame.lookAt(here.Position, ahead.Position,
					slideFrame:VectorToWorldSpace(slideUp(f)))
				task.wait()
			end
			if root.Parent then
				root.CFrame = slideFrame * CFrame.new(slidePoint(1))
			end
			humanoid.PlatformStand = false
			riding[player] = nil
			if onArrive then
				onArrive(player)
			end
		end)
	end)

	return function()
		connection:Disconnect()
	end
end

-- ===== THE WATER, MOVING =====
--
-- A flat plate is the right shape for still water and the wrong amount of nothing.
--
-- Every reference here is of water that is NOT moving in any useful sense -- no waves, no
-- current, nothing you could point at. And yet none of them is dead, because real standing
-- water is never quite still: the surface breathes, and every few seconds something drips into
-- it from a ceiling that has been leaking for years. Take both away and you have green glass.
--
-- Roblox cannot ripple a part and the usual trick, a scrolling normal map, needs an uploaded
-- texture this project does not have. But it CAN move a part and it CAN resize a MeshPart, and
-- those two are enough for the only two things the surface has to do.
--
--   THE SWELL. Every water surface in the level rises and falls together, four tenths of a
--   stud on a nine-second cycle with a slower term beating against it so it never repeats on a
--   count. Moving them TOGETHER is what makes this safe: the plates are coplanar, and any
--   scheme that moved them independently would open a seam along every join, fifty studs long
--   and lit from below.
--
--   THE RINGS. Drips, spreading. A ring mesh grown from ten studs across to fifty and faded
--   out as it goes, which is what a drop landing on still water looks like from above, and the
--   one piece of motion in the level with a cause you can name.
--
-- Both are slow enough to be deniable and that is deliberate. Water you NOTICE moving in a
-- room like this would be a current, and a current means a way out.
local RIPPLE_EVERY = 1.15
local RIPPLE_LIFE = 3.6
-- SMALLER. At fifty-six studs across, a ring is nearly three chunks wide: it stops reading as
-- a drip landing and starts reading as something surfacing. The whole point of these is to be
-- deniable.
local RIPPLE_FROM = 6
local RIPPLE_TO = 30
local SWELL_STUDS = 0.4
local SWELL_PERIOD = 9.0

function FloodedHallsService.applyWater(halls: Model): () -> ()
	local surfaces = {}
	for _, item in ipairs(halls:GetChildren()) do
		if item:IsA("BasePart")
			and (item.Name == "Water" or item.Name == "BasinWater" or item.Name == "PoolWater") then
			table.insert(surfaces, { part = item, home = item.Position })
		end
	end
	if #surfaces == 0 then
		return function() end
	end

	local template = kitMesh("Hall_Ripple")
	local rng = Random.new(77213)
	local running = true

	-- The failing fitting, and what it looked like before it started failing.
	-- Anything loose on the water. Given the same slow drift as the surface it is floating on,
	-- because debris that is perfectly still on water that is not is worse than either.
	local adrift = {}
	for _, item in ipairs(halls:GetChildren()) do
		if item:IsA("BasePart") and item.Name == "Debris" then
			table.insert(adrift, {
				part = item,
				home = item.CFrame,
				rate = 0.03 + (#adrift % 5) * 0.011,
				phase = (#adrift % 7) * 0.9,
				reach = 5 + (#adrift % 4) * 3,
			})
		end
	end

	local failing: BasePart? = nil
	local failingLamp: SurfaceLight? = nil
	local failingWas = 0
	for _, item in ipairs(halls:GetChildren()) do
		if item:IsA("BasePart") and item:GetAttribute("Failing") then
			failing = item
			failingLamp = item:FindFirstChildOfClass("SurfaceLight")
			failingWas = if failingLamp then failingLamp.Brightness else 0
			break
		end
	end
	local live: { { part: BasePart, born: number } } = {}
	local legs = hallRoute.legs

	task.spawn(function()
		local due = os.clock() + RIPPLE_EVERY
		while running do
			local now = os.clock()

			-- THE SWELL, applied to every surface from one number.
			local rise = math.sin(now * (math.pi * 2 / SWELL_PERIOD)) * SWELL_STUDS
				+ math.sin(now * 0.41) * SWELL_STUDS * 0.35
			for _, entry in ipairs(surfaces) do
				if entry.part.Parent then
					entry.part.Position = entry.home + Vector3.new(0, rise, 0)
				end
			end

			-- WHAT IS FLOATING ON IT. A slow circle and a slower turn, both far below the rate
			-- anything could be seen to be doing: the aim is that the junk is never in quite
			-- the place you left it, not that you catch it moving.
			for _, entry in ipairs(adrift) do
				if entry.part.Parent then
					entry.part.CFrame = entry.home
						* CFrame.new(
							math.sin(now * entry.rate + entry.phase) * entry.reach, 0,
							math.cos(now * entry.rate * 0.8 + entry.phase) * entry.reach)
						* CFrame.Angles(0, math.sin(now * entry.rate * 0.6) * 0.35, 0)
				end
			end

			-- THE FAILING FITTING.
			--
			-- Lit for about five seconds, then a second of stutter. NOT random noise every
			-- frame: a fluorescent on its way out sits there working, fails for a moment, and
			-- catches again. Continuous flicker reads as a broken effect; the long quiet
			-- stretch is what makes the stutter land, and it is the same reason the drips in
			-- this level are seconds apart rather than a rhythm.
			if failing and failing.Parent then
				local cycle = (now % 6.4) / 6.4
				local lit = 1.0
				if cycle > 0.84 then
					lit = if math.sin(now * 41) > -0.2 then 1.0 else 0.1
				end
				failing.Transparency = 0.12 + (1 - lit) * 0.8
				if failingLamp then
					failingLamp.Brightness = failingWas * lit
				end
			end

			-- THE RINGS.
			if template and now >= due and #live < 5 then
				due = now + rng:NextNumber(RIPPLE_EVERY * 0.6, RIPPLE_EVERY * 1.8)
				local leg = legs[rng:NextInteger(1, #legs)]
				local side = Vector3.new(leg.dir.Z, 0, -leg.dir.X)
				local flat = leg.from + leg.dir * rng:NextNumber(0, leg.length)
					+ side * rng:NextNumber(-HALL_HALF_WIDTH * 0.8, HALL_HALF_WIDTH * 0.8)
				local ring = template:Clone()
				ring.Name = "Ripple"
				ring.Anchored = true
				ring.CanCollide = false
				ring.CanTouch = false
				ring.CanQuery = false
				ring.CastShadow = false
				ring.Material = Enum.Material.Neon
				ring.Color = POOL_GLOW
				ring.Transparency = 0.55
				ring.Size = Vector3.new(RIPPLE_FROM, 2.2, RIPPLE_FROM)
				ring.CFrame = CFrame.new(hallOrigin
					+ Vector3.new(flat.X, hallFloorY + WATER_DEPTH + 0.5 + rise, flat.Z))
				ring.Parent = halls
				table.insert(live, { part = ring, born = now })
			end

			for index = #live, 1, -1 do
				local entry = live[index]
				local f = (now - entry.born) / RIPPLE_LIFE
				if f >= 1 or not entry.part.Parent then
					entry.part:Destroy()
					table.remove(live, index)
				else
					-- WIDENING FAST AND THEN SLOWING, like a real one: a square root rather
					-- than a straight ramp. A ring that expands at a constant rate reads as a
					-- growing circle; the deceleration is what makes it read as a wave losing
					-- energy.
					local eased = math.sqrt(f)
					local across = RIPPLE_FROM + (RIPPLE_TO - RIPPLE_FROM) * eased
					entry.part.Size = Vector3.new(across, 2.2, across)
					-- Faded on the square, so it is still clearly visible halfway out and
					-- gone by the edge rather than lingering as a faint hoop.
					entry.part.Transparency = 0.55 + 0.45 * (f * f)
				end
			end

			-- Fifteen hertz. The swell moves four tenths of a stud over nine seconds; nobody
			-- can tell the difference between that at 15 and at 60, and this is a loop running
			-- for the whole length of a run.
			task.wait(1 / 15)
		end
	end)

	return function()
		running = false
		for _, entry in ipairs(live) do
			if entry.part.Parent then
				entry.part:Destroy()
			end
		end
		for _, entry in ipairs(surfaces) do
			if entry.part.Parent then
				entry.part.Position = entry.home
			end
		end
	end
end

-- ===== CAUSTICS =====
--
-- THE SINGLE THING THAT MAKES WATER READ AS WATER. In half the references the water itself is
-- barely visible -- what tells you it is there is the rippling net of light thrown up onto the
-- walls and columns from it. Take that away and a green floor is a green floor.
--
-- Roblox has no caustics and no way to author them without an uploaded texture, so this is an
-- approximation and worth being honest about: a handful of dim, water-coloured PointLights
-- drifting slowly just above the surface. They pick out the tile relief on nearby walls and
-- move, and moving light low down that is the colour of the water is enough for the eye to
-- attribute it to the water. It will not survive close inspection of a single wall; it is
-- convincing in motion and at distance, which is when it is ever seen.
--
-- Dim on purpose. Caustics are a shimmer over the ambient, never a light source.
local CAUSTIC_LIGHTS = 10
local CAUSTIC_COLOUR = Color3.fromRGB(120, 226, 200)

function FloodedHallsService.applyCaustics(halls: Model, origin: Vector3): () -> ()
	-- ON THE ROUTE, not scattered over a square. The halls are an L now, so a bounding box is
	-- mostly solid rock -- half the lights would have been sealed inside a wall, lighting it
	-- from the inside, which is the one place a light does nothing at all.
	local rng = Random.new(90210)
	local running = true
	local lights = {}
	local legs = hallRoute.legs
	for index = 1, CAUSTIC_LIGHTS do
		local leg = legs[((index - 1) % #legs) + 1]
		local side = Vector3.new(leg.dir.Z, 0, -leg.dir.X)
		local flat = leg.from + leg.dir * rng:NextNumber(0, leg.length)
			+ side * rng:NextNumber(-HALL_HALF_WIDTH * 0.8, HALL_HALF_WIDTH * 0.8)

		local host = Instance.new("Part")
		host.Name = "Caustic"
		host.Size = Vector3.new(0.2, 0.2, 0.2)
		host.Transparency = 1
		host.Anchored = true
		host.CanCollide = false
		host.CanTouch = false
		host.CanQuery = false
		host.CastShadow = false
		host.Position = origin + Vector3.new(flat.X, hallFloorY + WATER_DEPTH + 1.2, flat.Z)
		host.Parent = halls

		local light = Instance.new("PointLight")
		light.Color = CAUSTIC_COLOUR
		-- UP FROM 0.32. Caustics are a shimmer over the ambient rather than a light source, and
		-- that is still true -- but with the room this dark the shimmer was the only thing
		-- reaching the water at all, and a shimmer nobody can see is not one.
		light.Brightness = 0.5
		light.Range = 22 * SCALE
		-- SHADOWS OFF. Ten shadow-casting lights drifting through a hall of hundreds of parts
		-- is a frame-rate problem for an effect nobody would notice the shadows of anyway.
		light.Shadows = false
		light.Parent = host
		table.insert(lights, {
			part = host,
			home = host.Position,
			-- Each drifts on its own two frequencies, so no two ever share a path and the
			-- whole set never repeats as a group.
			rateA = rng:NextNumber(0.10, 0.24),
			rateB = rng:NextNumber(0.07, 0.19),
			phase = rng:NextNumber(0, math.pi * 2),
			reach = rng:NextNumber(6, 14) * SCALE,
		})
	end

	task.spawn(function()
		while running do
			local now = os.clock()
			for _, entry in ipairs(lights) do
				if entry.part.Parent then
					entry.part.Position = entry.home + Vector3.new(
						math.sin(now * entry.rateA + entry.phase) * entry.reach,
						math.sin(now * entry.rateB * 2.1) * 0.6,
						math.cos(now * entry.rateB + entry.phase) * entry.reach)
				end
			end
			-- Ten hertz, not every frame. The movement is slow enough that nobody can tell,
			-- and it takes the cost from noticeable to nothing.
			task.wait(0.1)
		end
	end)

	return function()
		running = false
	end
end

-- ===== WHAT IT SOUNDS LIKE =====
--
-- Reverb does most of it and costs no asset. Bathroom is not a joke setting: it is the tuned
-- profile for a small hard-surfaced tiled room, and this level is nothing but tiled rooms. It
-- turns every footstep into the room answering, which is the whole point of a bathhouse.
--
-- The drips need an uploaded sound, so the id is left blank rather than guessed. A blank id is
-- silent and harmless; an invented one is a console error on every spawn.
-- ===== A SOUND THAT NEEDED NO UPLOAD =====
--
-- This was blank for the whole life of the level, with a note saying a guessed id would be a
-- console error on every spawn. That was right about invented ids and wrong about the options:
-- Roblox ships a handful of sounds at rbxasset:// paths that are present in every place with no
-- upload at all, and the lobby's tick already uses one, so the scheme is proven here.
--
-- A water impact is exactly the sound this level has been missing. THIS IS AN ASMR GAME and
-- the one level built entirely out of hard tile -- the most acoustically alive material there
-- is, already running Bathroom reverb -- has been completely silent.
--
-- Swap it for a proper recording when there is one. Until then the room has water in it.
local DRIP_SOUND_ID = "rbxasset://sounds/impact_water.mp3"
-- How many drip sources. Sparse and irregular: a drip you can predict is a metronome, and a
-- metronome is the opposite of unsettling.
local DRIP_SOURCES = 6

function FloodedHallsService.applySound(halls: Model): () -> ()
	local soundService = game:GetService("SoundService")
	local wasReverb = soundService.AmbientReverb
	soundService.AmbientReverb = Enum.ReverbType.Bathroom

	if DRIP_SOUND_ID ~= "" then
		local rng = Random.new(4172)
		local parts = {}
		for _, item in ipairs(halls:GetChildren()) do
			if item:IsA("BasePart") and item.Name == "Hall_Column" then
				table.insert(parts, item)
			end
		end
		for _ = 1, math.min(DRIP_SOURCES, #parts) do
			-- ON THE COLUMNS, because a drip has to come from somewhere the eye accepts water
			-- could be running down. A drip out of open air is a sound effect; a drip off a
			-- column is the building.
			local host = parts[rng:NextInteger(1, #parts)]
			local drip = Instance.new("Sound")
			drip.Name = "Drip"
			drip.SoundId = DRIP_SOUND_ID
			-- Quiet. A drip you can hear clearly is a sound effect; one you half-hear from two
			-- bays away is a building.
			drip.Volume = 0.28
			drip.RollOffMaxDistance = 70 * SCALE
			drip.RollOffMode = Enum.RollOffMode.InverseTapered
			drip.Parent = host
			task.spawn(function()
				while drip.Parent do
					-- Irregular by design. The wait is randomised every time rather than set
					-- once, so no two drips settle into a rhythm with each other.
					task.wait(rng:NextNumber(4, 14))
					drip.PlaybackSpeed = rng:NextNumber(0.92, 1.12)
					drip:Play()
				end
			end)
		end
	end

	return function()
		soundService.AmbientReverb = wasReverb
	end
end

-- ===== THE AIR, WHICH IS HALF OF IT =====
--
-- Every reference image is HAZY. Not fogged in the sense of being hard to see through -- fogged
-- in the sense that a room forty studs away is paler and warmer than the one you are standing
-- in, so distance is visible. Without it a tiled corridor is uniformly lit to its far end and
-- reads as flat, which is exactly the failure mode a repeating material has.
--
-- === On being told twice that it is too bright ===
--
-- The first pass reasoned that a room lit by bounce off a hundred white tiles wants a high
-- ambient. That is true of the BOUNCE and false of the setting: ambient in Roblox is a flat
-- floor under every surface at once, so raising it does not light the room, it deletes the
-- shadows. Everything went white.
--
-- The second pass cut ambient to a third and was still too bright, and the reason is that
-- ambient was never the largest term. There were four more, all additive, and each one looked
-- reasonable on its own:
--
--   A WINDOW IN EVERY BAY with a 160-stud range, so every point in the hall was lit by four of
--   them at once. That is not a row of windows, it is a lit ceiling.
--   HAZE, which is light. Atmosphere haze does not darken distance, it fills the volume with
--   a glow, and at 0.9 over this many sources it is a second ambient.
--   TEN CAUSTIC LIGHTS at 0.85 brightness and a 136-stud range, which is another 1360 stud-
--   lights of green fill nobody had counted as lighting because they were called an effect.
--   AND A BLOOM that then smeared all of it.
--
-- So this pass cuts every term rather than the obvious one: half as many windows at a third
-- the brightness and a seventh the volume, haze halved, caustics down to a third, exposure
-- down, contrast up. The references are a dim room with blinding windows -- almost all of
-- their range is dark, and the few bright things are bright BY COMPARISON. There is no setting
-- that produces that while every surface is independently lit.
--
-- Separate from build() because Lighting is global and a level has to be able to put it back.
function FloodedHallsService.applyAtmosphere(): () -> ()
	local lighting = game:GetService("Lighting")
	local was = {
		FogEnd = lighting.FogEnd,
		FogStart = lighting.FogStart,
		FogColor = lighting.FogColor,
		Ambient = lighting.Ambient,
		OutdoorAmbient = lighting.OutdoorAmbient,
		Brightness = lighting.Brightness,
		ExposureCompensation = lighting.ExposureCompensation,
	}

	-- AN ATMOSPHERE OBJECT, not just fog. FogStart/FogEnd is a linear fade to a flat colour and
	-- it looks like one: everything past FogEnd is the same shade of nothing. Atmosphere is
	-- scattering -- it tints by distance and hazes the light sources. Fog is kept as well
	-- because Atmosphere alone does not reach far enough indoors.
	local air = lighting:FindFirstChildOfClass("Atmosphere")
	local madeAir = false
	if not air then
		air = Instance.new("Atmosphere")
		air.Parent = lighting
		madeAir = true
	end
	local airWas = {
		Density = air.Density, Offset = air.Offset,
		Color = air.Color, Decay = air.Decay,
		Glare = air.Glare, Haze = air.Haze,
	}
	-- ===== THE AIR =====
	--
	-- The level was reading flat and monochrome: a single blue-grey wash over everything, near
	-- and far alike. Three things were doing that and only one of them is obvious.
	--
	--   TOO MUCH DENSITY, so the near field was already hazed. Haze that starts at your feet
	--   is not depth, it is a filter over the lens.
	--   A NEUTRAL DECAY, so distance went grey. Grey is the one colour that cannot describe
	--   anything, and it is what a room turns into when the far end has no hue of its own.
	--   FOG THE COLOUR OF THE TILES, so the far end of a corridor was the same value as the
	--   wall beside you and the space had no gradient at all.
	--
	-- Now the near air is clear and warm and the far air goes GREEN -- the colour of the water,
	-- because that is what is in this building. Distance recedes into the pools instead of into
	-- nothing, which ties the two halves of the palette together and is the whole reason the
	-- references look wet rather than merely pale.
	air.Density = 0.28
	air.Offset = 0.1
	air.Color = Color3.fromRGB(234, 228, 202)
	air.Decay = Color3.fromRGB(74, 104, 98)
	-- Glare is the bloom round the openings and Haze is how much of it fills the room. Haze is
	-- LIGHT, not darkness: see the note above. Halved again.
	air.Glare = 0.14
	-- Haze is LIGHT, not darkness. It was cut hard when the level was washing out and put back
	-- once the sources were where they belonged; pulled in again now, because with the density
	-- down its job is the far half of the room rather than all of it.
	air.Haze = 0.4

	-- Scaled with the building, or a room four times the size is uniformly clear to its far
	-- wall and the haze stops describing distance at all.
	-- STARTS FURTHER OUT AND ENDS SOONER. A short, late fog is a gradient; a long, early one is
	-- a tint. The near two hundred studs -- which is everything you are standing in -- are now
	-- clear, and the fall-off happens across the length of a leg, where it describes the
	-- receding colonnade instead of veiling the bay you are in.
	lighting.FogStart = 55 * 4
	lighting.FogEnd = 195 * 4
	-- AND IT IS THE COLOUR OF THE WATER. Fog the colour of the tiles makes the far end of a
	-- corridor the same value as the wall beside you, which is not depth, it is a veil. Green
	-- fog puts the pools at the end of every view, so the room recedes into the thing that is
	-- actually filling it.
	lighting.FogColor = Color3.fromRGB(104, 138, 130)
	-- ===== AND THEN IT WAS TOO DARK IN THE POOLS =====
	--
	-- Both corrections were right and they were corrections to different things.
	--
	-- The room was washing out because it had too many SOURCES: a window in every bay at a
	-- 160-stud range, haze at 0.9, ten caustic lights nobody had counted as lighting. Cutting
	-- those was correct and the hall is the right darkness now.
	--
	-- What went with them was the only light that ever reached the water, because every source
	-- in the level was up at two thirds of the wall and the water is fifty-six studs below the
	-- walkway. The answer is NOT to put the global levels back -- that returns the white-out
	-- and leaves the pools relatively as dark as before. It is the low slots along the
	-- waterline and the lamps in the basins, which are new, plus a modest lift here so the
	-- shadows are dark rather than black.
	lighting.Ambient = Color3.fromRGB(32, 34, 32)
	lighting.OutdoorAmbient = Color3.fromRGB(42, 44, 40)
	lighting.Brightness = 0.55
	-- UNDER-EXPOSED. Over-exposure was the single biggest contributor to the white-out: it
	-- lifts everything, and everything here is a pale tile.
	lighting.ExposureCompensation = -0.2

	-- ===== POST =====
	--
	-- The references are photographs, and photographs of bright interiors have three things a
	-- raw render never does: the highlights bleed, the far distance goes soft, and the colour
	-- is graded. All three are one instance each in Roblox.
	local bloom = Instance.new("BloomEffect")
	-- Only the windows should pass it. With the exposure down the tiles no longer come close,
	-- so the threshold can come down too -- which is what keeps the windows blooming while
	-- everything around them stays dark.
	-- TIGHTER. A wide bloom at a low threshold is what turned the light pools on the walls into
	-- flat white patches; a small one at a higher threshold keeps the bleed to the fittings
	-- themselves, which is where a camera would actually put it.
	bloom.Threshold = 2.2
	bloom.Intensity = 0.4
	bloom.Size = 18
	bloom.Parent = lighting

	local blur = Instance.new("DepthOfFieldEffect")
	-- FAR ONLY. Blurring anything near the player is a headache; the effect wanted is the far
	-- end of a corridor going soft, which is the FarIntensity alone.
	blur.NearIntensity = 0
	blur.FarIntensity = 0.6
	blur.FocusDistance = 42 * 4
	blur.InFocusRadius = 60 * 4
	blur.Parent = lighting

	local grade = Instance.new("ColorCorrectionEffect")
	-- Down and with the contrast up. Lowering contrast was meant to read as washed-out film;
	-- with everything already near-white it just removed the last of the separation.
	-- CONTRAST EASED. A positive contrast pushes the darks down as hard as it lifts the
	-- brights, and with every source in the room aimed at a wall the thing in the darks was
	-- the platforms. The rooflight is the real fix; this stops the grade undoing it.
	grade.Brightness = -0.02
	grade.Contrast = 0.11
	-- SATURATION UP, not down. The level has exactly two hues in it -- warm light and green
	-- water -- and desaturating was throwing away the only colour contrast it has. This is the
	-- difference between "pale and wet" and "grey".
	grade.Saturation = 0.06
	grade.TintColor = Color3.fromRGB(252, 248, 238)
	grade.Parent = lighting

	return function()
		for key, value in pairs(was) do
			(lighting :: any)[key] = value
		end
		if madeAir then
			air:Destroy()
		else
			for key, value in pairs(airWas) do
				(air :: any)[key] = value
			end
		end
		bloom:Destroy()
		blur:Destroy()
		grade:Destroy()
	end
end

return FloodedHallsService
