"""Checks the flooded halls without running Roblox.

    python check_halls.py

=== Why this exists, and why it has been rewritten twice ===

The first version checked a MAZE: every cell reachable, no wall across an opening. Every check
passed and the level was still broken, because the route is a line and a maze is a grid and no
arrangement of a grid leaves a lane through its middle. It was rigorous about the wrong thing.

The second version checked that the level asked for a straight LINE and that the lane guard was
wired in. Those checks also passed, and the level was still broken, in two new ways:

  THE ROUTE STILL CLIMBED. Only the chunk's own internal rise was suppressed on a line layout.
  The per-chunk elevation STEP was not, and it is the larger of the two: forty-four chunks at
  an average of two and a half studs is a hundred and ten studs of climb inside a building
  with an eighty-eight stud ceiling.

  THE ROUTE AND THE ROOM AGREED ABOUT ONE THING ONLY. Both ran straight down +Z, and that was
  the whole of the agreement. Nothing said they had to keep agreeing, and nothing could have,
  because neither of them wrote the shape down.

Both are now impossible rather than checked: the shape lives in Shared/HallRoute and both sides
read it. What is left for this file is to check that the arrangement STILL HOLDS -- that the
level asks for a path, that both sides still read the module, that the climb is still
suppressed, and that the handful of numbers duplicated between Lua and Blender still match.

=== The division of labour ===

Whether a particular column lands on the lane depends on arithmetic at run time, so
FloodedHallsService checks that itself: guardLane samples every solid it places and names
anything that reaches the route.

What this file checks is that the AGREEMENT still exists. A runtime guard nobody calls is worth
nothing, and that is exactly the failure a static check can catch and a runtime one cannot.
"""

import math
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE.parent / "src"
SERVICE = SRC / "Server" / "Services" / "FloodedHallsService.lua"
LEVEL_SERVICE = SRC / "Server" / "Services" / "LevelService.lua"
LEVELS = SRC / "Shared" / "LevelDefinitions.lua"
ROUTE = SRC / "Shared" / "HallRoute.lua"
GENERATOR = HERE / "gen_flooded_halls.py"

problems = []


def fail(message):
    problems.append("  " + message)


def number(text, pattern, what):
    """One number out of a source file, or a complaint that it has gone.

    DOTALL and MULTILINE together: several of these patterns span lines to pin a number to the
    block it lives in ("the half-width inside the basin branch", not any half-width), and
    several others anchor with ^ to catch a module-level constant rather than a local with the
    same name further down.
    """
    found = re.search(pattern, text, re.S | re.M)
    if not found:
        fail("%s is not declared any more, so nothing states it." % what)
        return None
    return float(found.group(1))


def main():
    if not SERVICE.exists():
        print("FloodedHallsService.lua not found; nothing to check.")
        return 0
    text = SERVICE.read_text(encoding="utf-8")
    levels = LEVELS.read_text(encoding="utf-8")
    gen = GENERATOR.read_text(encoding="utf-8")
    route_src = ROUTE.read_text(encoding="utf-8") if ROUTE.exists() else ""
    level_text = LEVEL_SERVICE.read_text(encoding="utf-8") if LEVEL_SERVICE.exists() else ""

    # ---- ONE PLACE KNOWS THE SHAPE, AND BOTH SIDES READ IT.
    #
    # This is the whole design. A side that stops reading the module has not broken a rule, it
    # has gone back to guessing, and guessing is what put chunks inside walls twice.
    if not route_src:
        fail("Shared/HallRoute.lua is gone. The route and the room have nothing to agree on.")
    for who, body in (("FloodedHallsService", text), ("LevelService", level_text)):
        if body and "HallRoute" not in body:
            fail("%s no longer reads Shared/HallRoute, so it is working out the level's shape "
                 "on its own again. That is the bug this module exists to make impossible."
                 % who)

    # ---- THE LEVEL ASKS FOR A PATH.
    for match in re.finditer(r"LevelDefinitions\.(\w+) = \{(.*?)\n\}", levels, re.S):
        name, body = match.group(1), match.group(2)
        if 'backdrop = "floodedHalls"' not in body:
            continue
        if 'layout = "path"' not in body:
            fail("%s uses the flooded halls but does not declare `layout = \"path\"`. Its "
                 "chunks will spiral through the corridor walls." % name)

    # ---- AND LevelService STILL HONOURS IT, BOTH WAYS.
    #
    # Two checks, not one, because the level being the right SHAPE and the level being FLAT are
    # separate decisions and only the first was ever made.
    if level_text:
        if 'level.layout == "path"' not in level_text:
            fail("LevelService no longer reads `level.layout == \"path\"`, so a level asking "
                 "for a path silently gets a spiral.")
        if "cursorY += if flatLayout then 0" not in level_text:
            fail("LevelService still applies the chunk's internal rise on a flat layout, so "
                 "the route climbs through the corridor's ceiling.")
        if "slotIndex > 1 and not flatLayout" not in level_text:
            fail("LevelService still applies the per-chunk elevation STEP on a flat layout. "
                 "This is the larger of the two climbs and the one that was missed last time: "
                 "44 chunks at ~2.5 studs is 110 studs of rise under an 88-stud ceiling.")
        if "tangent = tangent" not in level_text:
            fail("LevelService no longer records each chunk's tangent, so Bootstrap is back to "
                 "rebuilding it from startAngle with sin/cos -- which is only meaningful on the "
                 "spiral, where that number is radians rather than studs.")

    # ---- THE LANE GUARD IS WIRED IN, at both placement paths.
    #
    # A guard on one of the two is a guard that misses half of everything and looks present.
    if "local function guardLane" not in text:
        fail("guardLane is gone, so nothing checks that solids stay clear of the route.")
    else:
        if text.count("guardLane(") < 3:
            fail("guardLane is called %d time(s) counting its own definition; it has to run in "
                 "both slab() and piece(), or half of everything placed goes unchecked."
                 % text.count("guardLane("))
        if "HallRoute.distanceTo" not in text:
            fail("guardLane no longer measures to the route polyline. Measuring |x| from the "
                 "origin only works while the route runs along one axis -- the moment it turns "
                 "a corner that guard passes everything.")

    # ---- THE NUMBERS.
    scale = number(text, r"local SCALE = ([\d.]+)", "SCALE")
    lane_half = number(text, r"local LANE_HALF = ([\d.]+)", "LANE_HALF")
    floor_drop = number(text, r"local FLOOR_DROP = ([\d.]+)", "FLOOR_DROP")
    hall_half = number(text, r"local HALL_HALF_WIDTH = BAY \* ([\d.]+)", "HALL_HALF_WIDTH")
    route_bay = number(route_src, r"HallRoute\.BAY = ([\d.]+)", "HallRoute.BAY")
    if None in (scale, lane_half, floor_drop, hall_half, route_bay):
        return report()
    bay = 24 * scale
    hall_half_studs = bay * hall_half

    # The two modules measure the same bay. HallRoute cuts legs into whole bays so that walls
    # and columns land on the grid all the way to a corner; a different bay there means every
    # leg ends mid-bay.
    if abs(route_bay - bay) > 0.001:
        fail("HallRoute.BAY is %g but FloodedHallsService's bay is %g (24 * SCALE). Legs would "
             "be cut into the wrong module and every corner would land mid-bay."
             % (route_bay, bay))

    # A chunk is 16 to 20 studs wide, so the lane has to clear half of that plus standing room.
    if lane_half < 24:
        fail("LANE_HALF is %g, which is narrower than a chunk plus standing room. Chunks will "
             "touch the architecture." % lane_half)

    # ---- THE ONE PIECE THE ROUTE RUNS THROUGH.
    #
    # The transverse arch. Nothing else in the level is walked THROUGH, so nothing else has a
    # clearance, and this one has been reported broken three times.
    #
    # It is not a mesh any more. It was Hall_ArchWall, which meant the clearance depended on a
    # model's own proportions AND on somebody having re-imported it -- and there is no way to
    # tell those two failures apart from inside the game. It is built from parts now, in studs,
    # in the service, so this check reads the numbers that are actually used.
    arch_span = number(text, r"local ARCH_SPAN = ([\d.]+)", "ARCH_SPAN")
    arch_spring = number(text, r"local ARCH_SPRING = ([\d.]+)", "ARCH_SPRING")
    if 'piece(halls, "Hall_ArchWall"' in text:
        fail("Hall_ArchWall is being placed again. The arch is the one piece the route passes "
             "through, and as a mesh its clearance depends on an import nobody can verify from "
             "in game. Build it from parts.")
    if None not in (arch_span, arch_spring):
        head = arch_spring + arch_span
        # Roblox characters are 5 studs tall; 8 leaves room for a jump and for a chunk that
        # rises internally under the arch.
        if head - floor_drop < 8:
            fail("The archway's head is %.1f studs above the walkway. A character is 5 studs "
                 "tall, so the route runs into it. Raise ARCH_SPRING."
                 % (head - floor_drop))
        if head > 22 * scale - 4:
            fail("The archway's head reaches %.1f studs against a %g-stud wall, leaving nothing "
                 "above the opening." % (head, 22 * scale))
        if arch_spring >= floor_drop:
            fail("The archway springs at %.1f, which is at or above the walkway at %g. The "
                 "opening has to be full width where a player stands, so the curve must start "
                 "below them." % (arch_spring, floor_drop))
        for at, where in ((0.0, "at the walking surface"), (5.0, "at head height")):
            rise = floor_drop + at - arch_spring
            half = math.sqrt(max(0.0, arch_span * arch_span - rise * rise))
            if half <= lane_half:
                fail("The archway's opening is only %.1f studs to each side %s, against a "
                     "%g-stud lane. The jambs are in the walkway." % (half, where, lane_half))
                break

    # ---- THE FLUME LEAVES ALONG THE BRIDGE YOU WALKED IN ON.
    #
    # It was ninety degrees out, and by construction rather than by a sign error: the frame was
    # built from the PIT, the mouth fell wherever the radius put it, and the direction the tube
    # set off in was whatever the frame's axes happened to be -- which came out as the route's
    # heading, while the bridge to it runs sideways.
    #
    # These four lines are the derivation that fixes it, checked as a set because any one of
    # them going missing puts the mouth and the walk back out of agreement.
    for needed, why in (
        ("local enter = endFrame.RightVector", "the direction the bridge runs"),
        ("local zLocal = -enter", "the tube leaves along the bridge, so -Z is the way in"),
        ("local xLocal = up:Cross(zLocal)", "and the mouth is one radius along +X from the axis"),
        ("Vector3.new(axis.X, surfaceY + SLIDE_MOUTH_LIFT, axis.Z), xLocal, up)",
         "the frame is built from those rather than from the pit"),
        ("local axis = mouthAt - xLocal * SLIDE_RADIUS",
         "and the pit is centred on the helix, not the other way round"),
    ):
        if needed not in text:
            fail("The flume's frame no longer derives from the bridge (%s). It will point "
                 "whichever way the pit happens to, which was ninety degrees out." % why)
            break

    # ---- A FALL HAS TO REACH THE KILL PLANE.
    #
    # LevelService puts it 40 studs under the lowest walkable surface. With the flooded floor
    # any closer than that, a player who falls lands on solid tile ABOVE the plane: no death,
    # no respawn, no way back up, and nothing in the logs. That was the state of this level
    # while the route ran at floor height.
    if floor_drop <= 40:
        fail("FLOOR_DROP is %g, so the flooded floor is inside the 40 studs LevelService "
             "leaves above the kill plane. A player who falls off the walkway lands on tile, "
             "alive and stuck." % floor_drop)

    # ---- THE CORRIDOR IS WIDER THAN THE LANE, AND A LEG IS LONGER THAN A JUNCTION.
    #
    # A junction is a square as wide as the corridor, so it eats HALL_HALF_WIDTH off each end
    # of the legs either side of it. A leg shorter than twice that has no wall left at all.
    legs = re.findall(r"\{ bays = (\d+), turn = (-?\d+) \}", route_src)
    if not legs:
        fail("HallRoute's PATTERN has no legs in it.")
    else:
        shortest = min(int(bays) for bays, _ in legs) * bay
        if shortest < hall_half_studs * 2 + bay:
            fail("HallRoute's shortest leg is %g studs and a junction eats %g of it, leaving "
                 "under a bay of actual corridor. Lengthen the leg or narrow the hall."
                 % (shortest, hall_half_studs * 2))
        turns = [int(turn) for _, turn in legs]
        if all(turn == turns[0] for turn in turns):
            fail("Every turn in HallRoute's PATTERN goes the same way, so the route coils "
                 "around a centre. That is a spiral with corners, which is the shape this "
                 "level exists to not be.")
    if hall_half_studs <= lane_half:
        fail("HALL_HALF_WIDTH is %g and LANE_HALF is %g: the walls are inside the lane."
             % (hall_half_studs, lane_half))

    # ---- THE FLUME, WHICH LIVES IN TWO FILES.
    #
    # The ride is a path through the middle of a mesh. A rider following a different curve from
    # the one the tube was swept along goes out through its wall, and there is no way to notice
    # that from either file alone.
    # MATCHED AGAINST THE GENERATOR'S MODULE CONSTANTS, which were hoisted out of build_slide
    # precisely so this comparison has a unique name to find. The first version of this check
    # searched the whole generator for `radius = ` and matched build_column's, which is a
    # different 3.4 entirely -- and then reported that the two files agreed.
    pairs = [
        ("SLIDE_RADIUS", r"local SLIDE_RADIUS = ([\d.]+) \* SCALE", r"\nSLIDE_RADIUS = ([\d.]+)"),
        ("SLIDE_DROP", r"local SLIDE_DROP = ([\d.]+) \* SCALE", r"\nSLIDE_DROP = ([\d.]+)"),
        ("SLIDE_BORE", r"local SLIDE_BORE = ([\d.]+) \* SCALE", r"\nSLIDE_BORE = ([\d.]+)"),
        ("SLIDE_TURNS", r"local SLIDE_TURNS = ([\d.]+)", r"\nSLIDE_TURNS = ([\d.]+)"),
        # THE WALL TOO, now that the brackets are measured against the outside of the shell.
        ("SLIDE_WALL", r"local SLIDE_WALL = ([\d.]+) \* SCALE", r"\nSLIDE_WALL = ([\d.]+)"),
    ]
    for name, lua_pattern, gen_pattern in pairs:
        mine = number(text, lua_pattern, name)
        theirs = number(gen, gen_pattern, name + "'s counterpart in gen_flooded_halls")
        if mine is not None and theirs is not None and abs(mine - theirs) > 0.001:
            fail("%s is %g in FloodedHallsService and %g in the generator. The ride and the tube "
                 "are different curves; the rider leaves through the wall." % (name, mine, theirs))

    # THE MOUTH IS AT WALKING HEIGHT. This is the question the last version of this level could
    # not answer: the flume top sat 76 studs up a wall with nothing climbing to it, and the
    # finish was at the bottom, so the ride was both unreachable and skippable.
    if "surfaceY + SLIDE_MOUTH_LIFT" not in text:
        fail("The flume's frame is no longer lifted to the walkway's own height. Its mouth's "
             "trough floor is a flared bore below the tube's centre line, so the frame has to "
             "be raised by exactly that or the entrance sits above or below the apron.")
    # The flare lives in both files, and it is what SLIDE_MOUTH_LIFT is derived from.
    lua_flare = number(text, r"local SLIDE_FLARE = ([\d.]+)", "SLIDE_FLARE in Lua")
    gen_flare = number(gen, r"^SLIDE_FLARE = ([\d.]+)", "SLIDE_FLARE in the generator")
    if None not in (lua_flare, gen_flare) and abs(lua_flare - gen_flare) > 0.001:
        fail("SLIDE_FLARE is %g in FloodedHallsService and %g in the generator. The mouth will "
             "not be the height the flume is lifted by." % (lua_flare, gen_flare))
    if "GangwayPlank" not in text:
        fail("The gangway is gone -- there is nothing between the end of the walkway and the "
             "flume mouth to stand on.")

    # ---- THE SHAFT IS ONE HOLE, AND THE RIDE ENDS INSIDE IT.
    #
    # The shaft used to drop a hundred and twenty studs and open out into a wider room, which
    # put a horizontal ledge right round the join -- and a ledge, lit from the shaft above it,
    # is what read as "the bottom". Uniformity is what hides a bottom, not depth: parallel walls
    # with nothing crossing them give the eye nothing to fix on.
    plunge = number(text, r"local SLIDE_PLUNGE = ([\d.]+)", "SLIDE_PLUNGE")
    pit_depth = number(text, r"local PIT_WALL_DEPTH = ([\d.]+)", "PIT_WALL_DEPTH")
    drop = number(text, r"local SLIDE_DROP = ([\d.]+) \* SCALE", "SLIDE_DROP")
    if "VOID_HALF" in text or "VoidLid" in text:
        fail("The shaft opens out again somewhere. Any change of width puts a horizontal ledge "
             "round the join, and that ledge is exactly what used to read as the bottom of it.")
    if None not in (plunge, pit_depth, drop, scale):
        lands_at = drop * scale - floor_drop + plunge
        if lands_at >= pit_depth - 40:
            fail("The ride ends %g studs under the flooded floor and the shaft is %g deep. The "
                 "rider needs to finish well clear of the floor, or the one thing they are "
                 "looking at on the way down is the bottom." % (lands_at, pit_depth))
        # And the bottom has to be far enough away that fog has flattened it into the walls.
        if pit_depth + floor_drop < 300:
            fail("The bottom of the shaft is only %g studs from the walkway. That is inside the "
                 "range where it still reads as a separate surface."
                 % (pit_depth + floor_drop))

    # ---- THE GANGWAY IS MEASURED FROM THE MOUTH, NOT BESIDE IT.
    #
    # The arithmetic -- deck from the route's end to MOUTH_OFFSET, is the mouth at its end -- can
    # never fail, because the deck is DEFINED from the same constant. What can go wrong is the
    # derivation being broken: somebody sizing the deck to a round number, or moving the mouth
    # without it. So that is what is checked, and the numbers are then true by construction.
    mouth_off = number(text, r"local MOUTH_OFFSET = ([\d.]+)", "MOUTH_OFFSET")
    mouth_along = number(text, r"local MOUTH_ALONG = ([\d.]+)", "MOUTH_ALONG")
    for needed, why in (
        ("local deckTo = MOUTH_OFFSET", "its deck no longer ends at the mouth"),
        ("local deckWide = MOUTH_ALONG * 2", "its width no longer runs from the route's end"),
        ("endFrame * CFrame.new(deckFrom + (index + 0.5) * pitch, -1.4, MOUTH_ALONG)",
         "its planks are no longer laid from endFrame and those two"),
    ):
        if needed not in text:
            fail("The gangway out to the flume is no longer derived from the mouth (%s). Move the "
                 "mouth and the deck stays where it was." % why)
            break
    if None not in (mouth_off, mouth_along) and mouth_off < 40:
        fail("MOUTH_OFFSET is %g. The pit is centred a radius past the mouth, so a small offset "
             "drags the hole back across the walkway." % mouth_off)

    # ---- THE LENGTH THE PLAYER ASKED FOR.
    #
    # HubService offers Short / Medium / Long and scales the level's minChunks and maxChunks by
    # 0.5, 1.0 and 1.5. LevelService then picked a template and walked it, and read neither
    # field -- so for the whole life of the lobby every run was the template's own length and
    # the pads did nothing at all. It is invisible from the inside, because the run that arrives
    # is a perfectly plausible run; it is just not the one that was voted for.
    #
    # It matters twice as much here as elsewhere: on this level the chunk count decides how far
    # the route goes, which decides how many corners the corridor turns and where the last
    # chamber and the flume are built.
    if level_text and "level.minChunks" not in level_text:
        fail("LevelService does not read level.minChunks, so the lobby's Short / Medium / Long "
             "vote changes nothing. HubService scales those fields and nothing consumes them.")

    # ---- THE PLATE CUTS EVERY HOLE IN ONE PASS.
    #
    # Three surfaces have holes in them now and two of them have several. A single-hole cutter
    # run twice over the same plate has each pass re-covering the other's opening, which looks
    # exactly like the hole never being cut.
    if "plateWithHole" in text:
        fail("plateWithHole is still here. It takes one hole, and the floor and the water now "
             "have the flume pit plus one per basin -- run twice, each pass floors over the "
             "other's opening.")
    if "local function plate(" not in text:
        fail("the general plate() cutter is gone, so nothing can open the floor for a basin.")

    # ---- THE WATER IS NOT A STILL PLATE.
    if "FloodedHallsService.applyWater" not in text:
        fail("applyWater is gone: the water is back to a flat plate that never moves.")
    boot = (SRC / "Server" / "Bootstrap.server.lua")
    if boot.exists() and "applyWater" not in boot.read_text(encoding="utf-8"):
        fail("Bootstrap never calls applyWater, so the surface is built and then left dead. "
             "Its undo also has to be collected, or the swell keeps running after the level "
             "is torn down.")

    # ---- A BASIN FITS BETWEEN THE LANE AND THE WALL.
    #
    # This is the one piece of furniture wide enough to reach the walkway, and it is a HOLE in
    # the floor, so getting it wrong is not a cosmetic clash -- it is an opening under the
    # route.
    basin_half = number(text, r"BASIN_CHANCE then.*?local half = BAY \* ([\d.]+)",
                        "the basin's half-width, where the basin is chosen")
    if basin_half is not None:
        inner = (hall_half_studs - 8) - bay * basin_half * 2
        if inner < lane_half:
            fail("A basin is %g studs across against a %g-stud gap between the lane and the "
                 "wall: its inner edge lands %g studs from the centreline, inside the %g-stud "
                 "lane. That is a hole in the floor under the walkway."
                 % (bay * basin_half * 2, hall_half_studs - 8 - lane_half, inner, lane_half))

    # ---- THE FLIGHT OF STEPS LIVES IN TWO FILES TOO.
    #
    # A MeshPart is positioned by its bounding-box CENTRE, so the Lua has to know how long the
    # flight is to work out where its top tread lands. That is a measurement of a mesh, held as
    # a number in a different file, which is the same trap the flume's radius was.
    lua_flight = number(text, r"local flight = ([\d.]+) \* SCALE", "the flight length in Lua")
    treads = number(gen, r"^STEP_TREADS = ([\d.]+)", "STEP_TREADS")
    run = number(gen, r"^STEP_RUN = ([\d.]+)", "STEP_RUN")
    rise = number(gen, r"^STEP_RISE = ([\d.]+)", "STEP_RISE")
    width = number(gen, r"^STEP_WIDTH = ([\d.]+)", "STEP_WIDTH")
    if None not in (lua_flight, treads, run, rise, width, basin_half):
        if abs(lua_flight - treads * run) > 0.01:
            fail("The flight is %g long in FloodedHallsService and %g in the generator "
                 "(STEP_TREADS x STEP_RUN). The top tread will not land at the basin's rim."
                 % (lua_flight, treads * run))
        # AND IT HAS TO FIT IN THE BASIN IT GOES INTO, both across and along. The first version
        # of this mesh was a bay and a half wide, which is wider than the basin.
        across = width * scale
        basin_across = bay * basin_half * 2
        if across > basin_across - 8:
            fail("The flight is %g studs wide and a basin is %g across. It will stick out "
                 "through the basin's own walls." % (across, basin_across))
        # AND IT MUST NOT REACH THE BOTTOM. It is a measuring stick, not a way down: the
        # treads fading into the water is the whole point of the piece.
        deep = treads * rise * scale
        listed = re.search(r"local BASIN_DEPTHS = \{(.*?)\}", text, re.S)
        depths = [float(x) * scale for x in
                  re.findall(r"([\d.]+) \* SCALE", listed.group(1) if listed else "")]
        if depths and deep >= min(depths):
            fail("The flight drops %g studs and the shallowest basin is %g deep, so it reaches "
                 "the bottom or goes through it. It is meant to run out in the water."
                 % (deep, min(depths)))

    # ---- SOMETHING HAS TO LIGHT THE WALKWAY.
    #
    # This is the one the level failed on hardest and the one that was least visible in the
    # source. The hall is 211 studs across, so a light on a wall is 102 studs from the
    # centreline; the windows had a range of 88 and the pool slots 52. Both numbers look
    # generous on their own, both were chosen to stop the hall washing out, and between them
    # they left a dark stripe down the exact middle of the level -- which is where the route
    # is. The walls looked superb and the platforms rendered as black silhouettes.
    #
    # Two ways to satisfy it: put a light over the lane, or give a wall light the range to
    # cross the hall. The first is what the level does.
    overhead = re.search(r"lightPanel\(halls,\s*legFrame\(leg, along, 0,", text)
    window_range = number(text, r"lamp\.Range = ([\d.]+) \* SCALE\s*\n\s*--[^\n]*\n\s*"
                                r"--[^\n]*shadows", "the wall window's range")
    reach_from_wall = hall_half_studs - (2 * scale) * 0.4
    if not overhead:
        if window_range is None or window_range * scale < reach_from_wall:
            fail("Nothing lights the route. There is no panel over the lane, and a wall light "
                 "is %.0f studs from the centreline with a range of %s. The walkway will be in "
                 "the dark with lit walls either side of it."
                 % (reach_from_wall,
                    "%.0f" % (window_range * scale) if window_range else "none stated"))

    # ---- AND A CEILING OPENING HAS TO BE OPEN.
    #
    # lightPanel frames its panel on four sides and leaves the fifth for the light to come out
    # of. For a window that fifth side is the panel's own Z; for an opening in a ceiling it is
    # the underside, which is a different four parts. Passing a ceiling slot through the window
    # frame puts a tiled plate flush against its bottom face and seals it -- and a sealed light
    # looks exactly like a light, right up until you notice the room under it is dark.
    #
    # Every skylight in this level was sealed this way, including the only source whose range
    # could reach the middle of the hall.
    def calls_to(name, body):
        """Every call to `name`, with balanced parentheses."""
        found = []
        at = 0
        while True:
            at = body.find(name + "(", at)
            if at < 0:
                return found
            depth, index = 0, at + len(name)
            while index < len(body):
                if body[index] == "(":
                    depth += 1
                elif body[index] == ")":
                    depth -= 1
                    if depth == 0:
                        found.append(body[at:index + 1])
                        break
                index += 1
            at = index + 1

    for call in calls_to("lightPanel", text):
        sizes = re.findall(r"Vector3\.new\(([^()]*(?:\([^()]*\)[^()]*)*)\)", call)
        if not sizes:
            continue
        parts = [piece.strip() for piece in sizes[-1].split(",")]
        # A slot exactly SCALE tall is a thin horizontal opening, which is a ceiling one. The
        # windows and the dome ring are all HEIGHT-proportioned and never match this.
        if len(parts) == 3 and parts[1] == "SCALE" and not re.search(r",\s*true\s*\)\s*$", call):
            fail("A ceiling slot (%s) is built with the wall reveal, which caps it underneath. "
                 "Pass `true` as lightPanel's last argument so it is framed in plan and left "
                 "open below." % sizes[-1])

    # ---- THE SIZE TABLE IS NOT STALE.
    #
    # FloodedHallsService keeps a copy of what every kit piece measures, and warns at run time
    # when what is in Assets does not match -- which is the only way this project can tell "the
    # code is wrong" apart from "you have not re-imported it yet". That has been the answer
    # twice: a flume that was never imported, and an arch still carrying its old opening.
    #
    # But a table of expected sizes is itself a thing that goes stale, and a stale one is worse
    # than none: it would warn about every correctly imported mesh and be ignored within a day.
    # The generator writes kit_sizes.txt every run, so this can compare the two without having
    # to start Blender.
    sizes_file = HERE / "kit_sizes.txt"
    if not sizes_file.exists():
        fail("blender/kit_sizes.txt is missing. Run gen_flooded_halls.py -- it writes the file "
             "that proves FloodedHallsService's EXPECTED_SIZE table is current.")
    else:
        built_sizes = {}
        for line in sizes_file.read_text(encoding="utf-8").splitlines():
            bits = line.split()
            if len(bits) == 4:
                built_sizes[bits[0]] = tuple(float(v) for v in bits[1:])
        listed = dict(
            (found.group(1), tuple(float(v) for v in found.group(2, 3, 4)))
            for found in re.finditer(
                r"(Hall_[A-Za-z]+) = Vector3\.new\(([\d.]+), ([\d.]+), ([\d.]+)\)", text))
        if not listed:
            fail("FloodedHallsService has no EXPECTED_SIZE table, so a mesh that was never "
                 "re-imported reports nothing and looks like a code bug instead.")
        for name, size in sorted(built_sizes.items()):
            mine = listed.get(name)
            if mine is None:
                fail("EXPECTED_SIZE has no entry for %s, so an old import of it goes unnoticed."
                     % name)
            elif any(abs(a - b) > 0.01 for a, b in zip(mine, size)):
                fail("EXPECTED_SIZE says %s is %.3f x %.3f x %.3f but the generator last built "
                     "it %.3f x %.3f x %.3f. The table is stale: re-paste the one "
                     "gen_flooded_halls.py prints, or every correct import will warn."
                     % ((name,) + mine + size))

    # ---- THE LANE GUARD KNOWS ABOUT HEIGHT, AND IS HONEST ABOUT IT.
    #
    # The rule used to be plan-only: nothing solid within the lane at any height. That is right
    # for a wall and far too strong for a building -- it also forbids the piers under the
    # walkway, the beams over it and the lane markings on the floor beneath it, which is why
    # none of those existed.
    #
    # The band replaces it, and the band's SIZE is the thing worth checking. Too small and the
    # guard misses something a player walks into; too generous and every overhead member has to
    # be waved through with `free`, and a piece marked `free` is a piece nothing checks again.
    band_below = number(text, r"local WALK_BAND_BELOW = ([\d.]+)", "WALK_BAND_BELOW")
    band_above = number(text, r"local WALK_BAND_ABOVE = ([\d.]+)", "WALK_BAND_ABOVE")
    if None not in (band_below, band_above):
        # 5 studs of character plus a 6.4-stud jump is 11.4; anything under that is a band that
        # would let something be built through a player's head.
        if band_above < 12:
            fail("WALK_BAND_ABOVE is %g. A character is 5 studs tall and clears 6.4, so the "
                 "guard would allow a beam through the top of a jump." % band_above)
        if band_above > 24:
            fail("WALK_BAND_ABOVE is %g, which is well above anything a player occupies. It "
                 "sweeps up the ceiling members, and every one of those then has to be marked "
                 "`free` -- which is how things stop being checked at all." % band_above)
        if band_below < 2:
            fail("WALK_BAND_BELOW is %g, so something standing proud of the walking surface "
                 "would not be noticed." % band_below)
    # And the guard has to actually apply it.
    if "hallSurfaceY - WALK_BAND_BELOW" not in text:
        fail("guardLane no longer tests height, so it is back to forbidding the whole column "
             "of space above and below the route.")

    # ---- THE THINGS ADDED LAST, WHICH NOTHING WAS WATCHING.
    #
    # Every one of these was put in to fix something reported, and every one of them would go
    # back to being broken silently. A fix without a gate is a fix that lasts until the next
    # edit -- which in this level has been about a day.

    # THE WINDOWS ARE ABOVE THE DECK. At 0.62 of the wall height their centres sat below the
    # walkway and half of every one was lighting the water for nobody.
    window_at = number(text, r"side \* wallToLane, HEIGHT \* ([\d.]+)\)\n\s*\* CFrame\.Angles",
                       "the window height")
    window_tall = number(text, r"Vector3\.new\(BAY \* 0\.16, HEIGHT \* ([\d.]+), WALL_THICK",
                         "the window's height as a fraction")
    if None not in (window_at, window_tall):
        height = 22 * scale
        centre = window_at * height
        top = centre + window_tall * height / 2
        if centre <= floor_drop:
            fail("The windows are centred %.1f studs above the floor and the walkway is at %g. "
                 "Half of each one is under the deck." % (centre, floor_drop))
        if top > height - 2:
            fail("The windows reach %.1f studs against a %g-stud wall, leaving no masonry over "
                 "their heads." % (top, height))

    # ONE THING PER PLACE. An arch bay already spans the ceiling and already runs piers down
    # both walls, so it must not also build a beam and a pilaster in the same spot.
    if "if not archBay then" not in text:
        fail("The ceiling beam is no longer skipped on arch bays, so every third bay builds a "
             "beam and an arch head in the same space.")

    # THE PIERS CLEAR THE WALKWAY. They are the reason the lane guard learned about height, and
    # they have to stop short of the band or they trip the very check that allows them.
    pier_top = number(text, r"local pierTop = FLOOR_DROP - ([\d.]+)", "the piers' headroom")
    if None not in (pier_top, band_below) and pier_top <= band_below:
        fail("The piers stop %g studs under the deck and the guard's band reaches %g down. "
             "They will be reported as being in the lane." % (pier_top, band_below))

    # THE GLAZED ROOF EXISTS. It is the only daylight in the level and the one thing from the
    # reference images that went unbuilt for the level's whole life.
    if "Rooflight" not in text or "daylight" not in text:
        fail("The tall hall's glazed roof is gone. It is the brightest thing in the level and "
             "the only source that reads as daylight rather than as a lamp.")

    # THE MOUTH'S LINTEL FRAMES THE OPENING rather than sitting inside it. The tube's rim is two
    # flared bores above the trough, and the first version put the lintel at 1.75 of one.
    if "MouthLintel" in text and "SLIDE_MOUTH_LIFT * 2" not in text:
        fail("The flume mouth's lintel is no longer set from SLIDE_MOUTH_LIFT * 2, so it is "
             "probably back inside the opening it is supposed to frame.")

    # THE DRIP SOUND IS A REAL PATH. Blank is fine and silent; an rbxasset path is a built-in
    # that ships with every place. A bare numeric id is a GUESS, and a guessed id is a console
    # error on every spawn -- which is the thing that kept this blank for so long.
    drip = re.search(r'local DRIP_SOUND_ID = "([^"]*)"', text)
    if drip and drip.group(1) and not drip.group(1).startswith("rbxasset://"):
        fail("DRIP_SOUND_ID is '%s'. Either blank, or an rbxasset:// built-in that is present "
             "in every place. Anything else is an id somebody guessed." % drip.group(1))

    # ---- CORNERS TURN WHERE THE CHUNKS ARE.
    #
    # The corner used to be at a fixed distance and the chunks leading up to it are not, so the
    # shortfall went either into two chunks intersecting (honey through soap) or into a gap too
    # wide to jump with a tiled landing laid in it. Both were reported, the landing three times.
    #
    # LevelService turns where its chunks are now, lays the next chunk across the path, and hands
    # the real leg lengths to the halls. These check that the arrangement is still in place and
    # that its two sums still hold against the widths the kit actually builds.
    # CODE ONLY. The note explaining why the landings were removed names them, and a gate
    # that fires on its own documentation is a gate somebody learns to ignore -- which is what
    # the first version of this one did, on the first run.
    def code_of(source):
        return "\n".join(line.split("--", 1)[0] for line in source.splitlines())
    if (re.search(r"\bbuildLanding\b", code_of(text))
            or re.search(r"\brouteLandings\b", code_of(level_text))):
        fail("Corner landings are back. They only exist to fill a gap that turning where the "
             "chunks are makes impossible, and they read as stray platforms in the run.")
    if "HallRoute.fromLegs" not in text:
        fail("FloodedHallsService no longer builds the corridor from the leg lengths the chunks "
             "took, so its corners are back at planned distances the walkway does not turn at.")
    if "routeLegs" not in level_text or "HallRoute.legPlan" not in level_text:
        fail("LevelService no longer records where its route actually turned.")
    gap = number(level_text, r"^local CHUNK_GAP = ([\d.]+)", "CHUNK_GAP")
    bar = number(level_text, r"^local CORNER_BAR = ([\d.]+)", "CORNER_BAR")
    arm_z = number(level_text, r"^local JUNCTION_ARM_Z = ([\d.]+)", "JUNCTION_ARM_Z")
    arm_reach = number(level_text, r"^local JUNCTION_ARM_REACH = ([\d.]+)",
                       "JUNCTION_ARM_REACH")
    builder_path = SRC / "Server" / "ChunkBuilder.server.lua"
    builder = builder_path.read_text(encoding="utf-8") if builder_path.exists() else ""
    path_w = re.search(r"^local PATH_WIDTH = ([\d.]+)", builder, re.M)
    path_width = float(path_w.group(1)) if path_w else 16.0

    # CORNERS TURN ON THE JUNCTION CHUNK. Laying the next chunk across the path lands the player
    # on its SIDE, and the shaped forms in the pool are only checked walkable from their entry
    # face; the junction is entered and left through faces with connections built on them.
    if '"S2_Junction", junctionAt' not in level_text:
        fail("Corners no longer turn on S2_Junction. Laying the next chunk across the path lands "
             "players on its side, which no shaped chunk was checked for.")

    # THE JUNCTION NUMBERS ARE THE JUNCTION'S. LevelService places every corner from two
    # measurements of a chunk that ChunkBuilder builds; move the arm there and every corner is
    # silently a gap or an overlap.
    arm = re.search(r'makePlatform\(model, "EastArm", ([\d.]+), ([\d.]+), nil, '
                    r'CFrame\.new\(([\w.]+), 0, ([\d.]+)\)\)', builder)
    if not arm:
        fail("S2_Junction's east arm is no longer built the way LevelService's corner "
             "arithmetic assumes (a platform named EastArm at a stated offset).")
    elif None not in (arm_z, arm_reach):
        arm_width = float(arm.group(1))
        centre_x = path_width if arm.group(3) == "PATH_WIDTH" else float(arm.group(3))
        built_z, built_reach = float(arm.group(4)), centre_x + arm_width / 2
        if abs(built_z - arm_z) > 0.01 or abs(built_reach - arm_reach) > 0.01:
            fail("LevelService turns corners assuming S2_Junction's arm is centred %g along it "
                 "and reaches %g out; ChunkBuilder builds it at %g and %g. Every corner is "
                 "off by the difference." % (arm_z, arm_reach, built_z, built_reach))

    # THE FALLBACK'S TWO SUMS, measured against ENTRY geometry.
    #
    # The first version of this read every `width = ` in ChunkBuilder, and so took SHELF widths
    # -- the four- and five-stud ledges beside a platform, which make it wider -- for the
    # narrowest chunk in the kit, and a soap star's bounding square for the widest. At a corner
    # what matters is the entry segment: how far it reaches to the side with its shelves, and
    # how wide the walkable slab is.
    entry_reach, entry_width = [], []
    if "local LinearChunks" in builder:
        body = builder[builder.index("local LinearChunks"):]
        body = body[:body.index("\n}\n")]

        def tables_in(chunk_text):
            found, depth, begin = [], 0, None
            for i, ch in enumerate(chunk_text):
                if ch == "{":
                    if depth == 0:
                        begin = i
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth == 0 and begin is not None:
                        found.append(chunk_text[begin:i + 1])
                        begin = None
            return found

        for chunk in re.finditer(r"\n\t(\w+) = \{", body):
            open_at = chunk.end() - 1
            depth, close_at = 0, open_at
            for close_at in range(open_at, len(body)):
                if body[close_at] == "{":
                    depth += 1
                elif body[close_at] == "}":
                    depth -= 1
                    if depth == 0:
                        break
            segments = [s for s in tables_in(body[open_at + 1:close_at])
                        if not re.search(r"\bgap\s*=", s)]
            if not segments:
                continue
            first = segments[0]
            bare = re.sub(r"shelf\s*=\s*\{[^}]*\}", "", first)
            width = re.search(r"\bwidth\s*=\s*([\d.]+)", bare)
            offset = re.search(r"\boffsetX\s*=\s*(-?[\d.]+)", bare)
            shelf = re.search(r"shelf\s*=\s*\{[^}]*\bwidth\s*=\s*([\d.]+)", first)
            walk = float(width.group(1)) if width else path_width
            reach = abs(float(offset.group(1)) if offset else 0.0) + walk / 2
            if shelf:
                reach += 0.4 + float(shelf.group(1))
            entry_width.append(walk)
            entry_reach.append(reach)
    if None not in (gap, bar) and entry_reach:
        if gap + bar <= max(entry_reach):
            fail("The corner fallback lays a chunk across the path %g studs past the last one, but "
                 "a chunk's entry reaches %.1f to the side with its shelves, so it reaches back "
                 "into the chunk before it." % (gap + bar, max(entry_reach)))
        # A character clears about 8.2 studs of distance, per the note at STEP_CHOICES.
        if gap + bar - min(entry_width) / 2 > 8.2:
            fail("The corner fallback leaves a %.1f-stud jump onto the narrowest entry (%g wide). A "
                 "character clears about 8.2." % (gap + bar - min(entry_width) / 2,
                                                  min(entry_width)))

    # ---- THE FLUME IS BUILT FROM THE CURVE, NOT IMPORTED.
    #
    # Reported misaligned four rounds running while its frame measured correct every time. A
    # helix has a handedness that cannot be verified through the FBX import, and every other
    # piece in the kit is symmetric so nothing else could reveal a mirrored axis. Built from
    # helixAt, the tube is the same curve the ride follows and cannot disagree with it.
    if 'piece(halls, "Hall_Slide"' in text:
        fail("Hall_Slide is being placed again. Its winding cannot be checked through the "
             "import, and it was misaligned for four rounds; build the tube from helixAt.")
    if "buildFlume(halls, slideFrame)" not in text:
        fail("The flume is not being built at all -- nothing calls buildFlume.")

    # ---- AND IT IS A FLUME: open, lipped, held up, and the rider leaning with it.
    #
    # Built as a closed tube it fixed the orientation and was reported as looking like a hose;
    # before it had a mast it was the last thing in the level hanging in mid-air.
    # QUOTED, because the names nest: FlumeMast is inside FlumeMastCap, and the first version of
    # this went on passing with the mast deleted.
    for needed, why in (
        ('"FlumeShell"', "the open trough"),
        ('"FlumeLip"', "the rolled lip that traces the helix"),
        ('"FlumeMast"', "the mast it is held up by"),
        ('"FlumeSaddle"', "the saddles it bears on"),
        ("slideUp(f)", "the rider banking with the trough"),
    ):
        if needed not in text:
            fail("The flume has lost %s: %s is gone." % (why, needed))

    # ---- THE RIDER IS IN THE TROUGH, all the way down, bank included.
    #
    # An open trough is only a ride while the rider is inside it. Bank it harder, sink the rider
    # less or narrow the bore, and they ride up over the outer lip -- which nothing at run time
    # would ever report. flumeBasis, mirrored: the section eased from level over the flare, banked
    # toward the axis, the rider RIDE_SINK straight down from the centre line and their feet three
    # studs further along the section's own up.
    bank = number(text, r"^local FLUME_BANK = math\.rad\(([\d.]+)\)", "FLUME_BANK")
    slide_r = number(text, r"^local SLIDE_RADIUS = ([\d.]+) \* SCALE", "SLIDE_RADIUS")
    turns = number(text, r"^local SLIDE_TURNS = ([\d.]+)", "SLIDE_TURNS")
    bore = number(text, r"^local SLIDE_BORE = ([\d.]+) \* SCALE", "SLIDE_BORE")
    flare = number(text, r"^local SLIDE_FLARE = ([\d.]+)", "SLIDE_FLARE")
    sink_less = number(text, r"^local RIDE_SINK = SLIDE_BORE - ([\d.]+)", "RIDE_SINK")
    side_rise = number(text, r"^local FLUME_SIDE_RISE = ([\d.]+)", "FLUME_SIDE_RISE")
    side_out = number(text, r"^local FLUME_SIDE_OUT = ([\d.]+)", "FLUME_SIDE_OUT")
    if None not in (bank, slide_r, turns, bore, flare, sink_less, side_rise, side_out, drop,
                    scale):
        def v_dot(a, b):
            return sum(x * y for x, y in zip(a, b))

        def v_scale(a, s):
            return tuple(x * s for x in a)

        def v_cross(a, b):
            return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2],
                    a[0] * b[1] - a[1] * b[0])

        def v_unit(a):
            return v_scale(a, 1.0 / math.sqrt(v_dot(a, a)))

        radius, fall, sink = slide_r * scale, drop * scale, bore * scale - sink_less
        spin = turns * math.tau
        tightest = None
        # "Inside the bore" is not enough on its own, and the first version of this gate proved it:
        # a rider RIDE_SINK straight down from the centre is inside the circle whatever the bank,
        # and inside it however little they are sunk. Two more things have to hold.
        highest = None
        lowest = None
        for step in range(201):
            at = step / 200.0
            angle = at * spin
            centre = (math.cos(angle) * radius, -fall * at, -math.sin(angle) * radius)
            tangent = v_unit((-math.sin(angle) * radius * spin, -fall,
                              -math.cos(angle) * radius * spin))
            ease = min(1.0, at / 0.1)
            flat = v_unit((tangent[0], 0.0, tangent[2]))
            tangent = v_unit(tuple(f * (1 - ease) + g * ease for f, g in zip(flat, tangent)))
            square = v_unit(v_cross(v_cross(tangent, (0.0, 1.0, 0.0)), tangent))
            inward = v_unit((-centre[0], 0.0, -centre[2]))
            lean = math.radians(bank) * ease
            up = tuple(s * math.cos(lean) + i * math.sin(lean) for s, i in zip(square, inward))
            up = v_unit(tuple(u - g * v_dot(up, tangent) for u, g in zip(up, tangent)))
            side = v_unit(v_cross(tangent, up))
            bore_here = bore * scale * ((1 + flare * (1 - at / 0.1) ** 2) if at < 0.1 else 1)
            down = (0.0, -sink, 0.0)
            w, v = v_dot(down, side), v_dot(down, up)
            root_room = bore_here - math.hypot(w, v)
            feet_room = bore_here - math.hypot(w, v - 3.0)
            room = min(root_room - 2.0, feet_room - 0.3)
            if tightest is None or room < tightest[0]:
                tightest = (room, at, root_room, feet_room)
            # ON THE FLOOR, not floating up the middle of the trough.
            if highest is None or feet_room > highest[0]:
                highest = (feet_room, at)
            # AND BELOW THE LOW SIDE. Bank a U far enough and its inner lip drops under the rider's
            # head: still inside the circle, and visibly sliding out over the edge.
            low_lip = (bore * scale * side_rise * up[1]
                       - (bore_here + bore * scale * side_out) * abs(side[1]))
            head = -sink + 2.0 * up[1]
            if lowest is None or low_lip - head < lowest[0]:
                lowest = (low_lip - head, at)
        if tightest[0] < 0:
            fail("The rider leaves the trough %.2f of the way down: their root has %.2f studs of "
                 "bore round it and their feet %.2f, against 2 and 0.3. Ease FLUME_BANK or "
                 "RIDE_SINK." % (tightest[1], tightest[2], tightest[3]))
        if highest[0] > 2.5:
            fail("The rider floats %.1f studs above the trough's floor %.2f of the way down. "
                 "RIDE_SINK is not sinking them onto it." % highest)
        if lowest[0] < 0.5:
            fail("The flume's lower lip is only %.1f studs above the rider's head %.2f of the way "
                 "down; banked that hard, the rider is sliding out over the edge. Ease FLUME_BANK."
                 % lowest)

    # ---- NO DIVING BOARD.
    if re.search(r'"DivingBoard"', code_of(text)):
        fail("The diving board is back. It read as a second plank over the shaft going nowhere, "
             "beside the gangway that goes somewhere, and it was reported as not making sense.")

    # ---- THE HALL ENDS BEHIND THE START.
    #
    # It did not: turn round at the spawn and the floor, the water and the ceiling ran out to the
    # edges of their plates with daylight showing under them.
    if "buildEntrance(halls, legs[1])" not in code_of(text) or '"BackWall"' not in text:
        fail("Nothing closes the hall behind the spawn. Turn round at the start and the level runs "
             "out to the edge of its plates, with daylight under the ceiling.")
    if "local wallFrom = if legIndex == 1 then -ENTRANCE_DEPTH else from" not in text:
        fail("The first leg's walls no longer run back to the entrance's end wall, so it stands "
             "free with a gap down either side of it.")
    entrance = number(text, r"^local ENTRANCE_DEPTH = BAY \* ([\d.]+)", "ENTRANCE_DEPTH")
    passage = number(text, r"^local PASSAGE_LENGTH = BAY \* ([\d.]+)", "PASSAGE_LENGTH")
    margin = number(text, r"local margin = HALL_HALF_WIDTH \+ BAY \* ([\d.]+)",
                    "the floor and ceiling plates' margin")
    wall_thick = number(text, r"^local WALL_THICK = ([\d.]+) \* SCALE", "WALL_THICK")
    if None not in (entrance, passage, margin, wall_thick):
        deepest = (entrance + passage) * bay + 2 * wall_thick * scale
        reach = hall_half_studs + margin * bay
        if deepest > reach - 4:
            fail("The passage behind the start ends %.0f studs back, and the floor, water and "
                 "ceiling plates only reach %.0f. Its far end opens onto the sky."
                 % (deepest, reach))


    # ---- NOTHING GLOWING IN MID-AIR.
    #
    # The end chamber's lights were placed on a circle written for a round room, in a square one,
    # so every panel floated nineteen to forty-two studs from any wall.
    if "half * 0.9" in text:
        fail("The chamber's ring of lights is back: panels on a circle inside a square room, "
             "none of them on a wall.")
    if "ChamberWindow" not in text:
        fail("The end chamber has no windows set into its walls, so it has no light of its own.")

    # ---- THE DOME COVERS ITS HOLE.
    dome_half = number(text, r"^local DOME_HALF = ([\d.]+)", "DOME_HALF")
    kit_file = HERE / "kit_sizes.txt"
    if dome_half is not None and kit_file.exists():
        for line in kit_file.read_text(encoding="utf-8").splitlines():
            bits = line.split()
            if len(bits) == 4 and bits[0] == "Hall_Dome":
                radius = float(bits[1]) * scale / 2
                if dome_half * math.sqrt(2) >= radius - 1:
                    fail("The ceiling's hole under the dome is square and %g to each side, so its "
                         "corners reach %.0f studs out against a %.0f-stud dome. They open onto "
                         "nothing." % (dome_half, dome_half * math.sqrt(2), radius))

    # ---- THE ROOF OVER THE FLUME IS DRESSED, FROM THE DOME THAT IS THERE.
    #
    # A bare saucer over the biggest room in the level, with the ceiling cut raw round it. The
    # detail is measured off the imported dome's own size, so it lands under the dome whatever
    # was imported; and the oculus stays dimmer than the glazed roof, which was turned down once
    # already for being too bright.
    if "buildDomeDetail(halls, dome)" not in code_of(text) or "dome.Size" not in text:
        fail("The dome over the flume is a bare shell again, or its detail is placed from "
             "constants instead of from the dome that was actually imported.")
    oculus = number(text, r"^local OCULUS_RADIUS = ([\d.]+)", "OCULUS_RADIUS")
    oculus_light = number(text, r"^local OCULUS_BRIGHTNESS = ([\d.]+)", "OCULUS_BRIGHTNESS")
    roof_light = number(text, r"daylight\.Brightness = ([\d.]+)", "the glazed roof's brightness")
    if None not in (oculus, dome_half) and oculus + 5 >= dome_half:
        fail("The oculus and its ring reach %g studs out and the opening under the dome is %g: "
             "the ceiling hides it." % (oculus + 5, dome_half))
    if None not in (oculus_light, roof_light) and oculus_light >= roof_light:
        fail("The oculus is %g bright against the glazed roof's %g. The glazed roof was turned "
             "down for being too bright; this must not be brighter." % (oculus_light, roof_light))

    # ---- THE WALLS ARE DRESSED, ALL OF THEM, AND NOTHING IN THEM IS BEHIND A PILASTER.
    #
    # The windows, the waterline slots and the blind doorways were all at the bay's centre, and so
    # is the pilaster -- twenty-nine studs wide, standing three and a half proud -- so in most
    # bays it covered them. And only the corridor's own walls had a dado; it stopped dead at every
    # junction and arch return.
    if re.search(r"legFrame\(leg, along, (side|slotSide) \* wallToLane", code_of(text)) \
            or "buildDoorway(halls, leg, along" in code_of(text):
        fail("Something set into the wall is back at the bay's centre, behind the pilaster that "
             "stands there. Windows, slots and doorways go in the panel between two pilasters.")
    if code_of(text).count("tiledWall(halls") < 11:
        fail("Only %d walls go through tiledWall. Every full-height wall has to, or the dado, "
             "stripe and cornice stop dead where one kind of wall meets another."
             % code_of(text).count("tiledWall(halls"))
    wainscot = number(text, r"^local WAINSCOT = HEIGHT \* ([\d.]+)", "WAINSCOT")
    stripe = re.search(r"course\(WAINSCOT - ([\d.]+), ([\d.]+),", text)
    door_tall = number(text, r"local function buildDoorway.*?local tall = BAY \* ([\d.]+)",
                       "the blind doorway's height")
    springing = number(text, r"local springing = HEIGHT \* ([\d.]+)", "the niche's springing")
    if None not in (wainscot, door_tall, springing) and stripe:
        height = 22 * scale
        stripe_bottom = wainscot * height - float(stripe.group(1)) - float(stripe.group(2)) / 2
        if door_tall * bay + scale >= stripe_bottom:
            fail("A blind doorway's architrave reaches %.1f and the wainscot stripe starts at %.1f: "
                 "the stripe runs across the top of every doorway."
                 % (door_tall * bay + scale, stripe_bottom))
        niche_top = springing * height + (bay * 0.2 + scale * 1.5) / 2
        if niche_top >= height - 4 - 0.8:
            fail("A niche's frame reaches %.1f, into the cornice that starts at %.1f."
                 % (niche_top, height - 4.8))

    # ---- THE POOL FITS BETWEEN THE COLUMNS, CLEARS THE BASINS, AND HOLDS ITS PIERS.
    pool_half = number(text, r"^local POOL_HALF = ([\d.]+)", "POOL_HALF")
    column = re.search(r"Hall_Column = Vector3\.new\(([\d.]+),", text)
    if None not in (pool_half,) and column:
        column_inner = lane_half + bay * 0.3 - float(column.group(1)) * scale / 2
        # The gutter grate is the outermost thing on the edge: 3.6 studs past the box.
        if pool_half + 3.6 >= column_inner:
            fail("The pool's gutter reaches %.1f studs out and the column bases start at %.1f. The "
                 "colonnade is standing in the pool's edge." % (pool_half + 3.6, column_inner))
        if basin_half is not None:
            basin_inner = hall_half_studs - 4 - bay * basin_half * 2
            if pool_half + 3.6 >= basin_inner:
                fail("The pool's edge at %.1f runs into the sunken basins, which start at %.1f."
                     % (pool_half + 3.6, basin_inner))
    for needed, why in (
        ("local foot = if poolUnder(", "the walkway's piers no longer reach down to the pool's floor"),
        ("math.ceil(wideX / WATER_TILE)", "the pool's water is one huge transparent part again, "
                                          "which is what made translucent chunks vanish"),
        ('item.Name == "PoolWater"', "the pool's water is not in the swell, so its surface and the "
                                     "shallows' part company"),
        ("exposedRuns(pool, side)", "the pool's edge is built on every side, including across the "
                                    "joins where one leg's pool runs into the next"),
    ):
        if needed not in code_of(text):
            fail("The pool is broken: %s." % why)

    # ---- SCALE REACHES THE MESHES.
    if "made.Size = made.Size * SCALE" not in text:
        fail("mesh clones are not multiplied by SCALE, so they will not match the parts.")

    # ---- EVERY MESH PLACED IS ONE THE GENERATOR BUILDS AND EXPORTS.
    wanted = set(re.findall(r'"(Hall_[A-Za-z]+)"', text))
    built = set(re.findall(r'finish\(bm, "(Hall_[A-Za-z]+)"\)', gen))
    exported = set()
    main_block = gen[gen.index("def main():"):] if "def main():" in gen else ""
    for builder in re.findall(r"build_(\w+)", main_block):
        for name in built:
            if name.lower().replace("hall_", "") == builder.replace("_", ""):
                exported.add(name)
    for name in sorted(wanted - built):
        fail("%s is placed by the service but no generator builds it." % name)
    for name in sorted(wanted & built - exported):
        fail("%s is built but main() does not export it, so importing the kit will not "
             "produce one." % name)

    print("flooded halls: scale %g, bay %g, lane +/-%g inside a %g-wide corridor, walkway %g "
          "studs above the water, %d mesh kinds placed."
          % (scale, bay, lane_half, hall_half_studs * 2, floor_drop, len(wanted)))
    if not problems:
        print("route and room agree: one shape module, path layout, flat route, lane guarded, "
              "flume reachable and landing in the void.")
    return report()


def report():
    if problems:
        print("")
        print("PROBLEMS:")
        for line in problems:
            print(line)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
