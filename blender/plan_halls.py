"""Draws the flooded halls in plan at every run length, from the real constants.

    python plan_halls.py

=== Why ===

Every structural bug this level has had was a PLAN bug: a spiral inside a maze, a climb through
a ceiling, a chamber landing on top of a junction, chunks inside walls. Not one of them is
visible in a screenshot taken from inside the level, because from inside a corridor every
corridor looks the same. All of them are obvious from above in about a second.

=== Why three of them ===

Because the lobby lets people vote Short, Medium or Long, and on this level that is not a
cosmetic setting. The chunk count decides how far the route runs, which decides how many
corners the corridor turns, where the last chamber lands and therefore where the flume is
built. A level that is correct at 44 chunks and broken at 22 is a level that is broken.

The worst case is not the extreme, it is the awkward middle: a route that stops a few studs
after a corner leaves a junction sitting inside the last chamber. Drawing all three is how that
gets noticed before somebody votes for it.

check_halls.py is the gate -- it fails a build. This is the drawing, and the two are different
jobs: a check tells you a rule was broken, a plan tells you what the level looks like, which is
the question you actually have when deciding whether the shape is any good.

Everything here is READ FROM THE SOURCES rather than restated. A diagram with its own copy of
the numbers is a drawing of a level that does not exist, which is worse than no drawing.
"""

import pathlib
import re
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.patches as patches
import matplotlib.pyplot as plt

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE.parent / "src"
SERVICE = SRC / "Server" / "Services" / "FloodedHallsService.lua"
LEVEL_SERVICE = SRC / "Server" / "Services" / "LevelService.lua"
ROUTE = SRC / "Shared" / "HallRoute.lua"
LEVELS = SRC / "Shared" / "LevelDefinitions.lua"
HUB = SRC / "Server" / "Services" / "HubService.lua"
BUILDER = SRC / "Server" / "ChunkBuilder.server.lua"
OUT = HERE / "halls_plan.png"

# What LevelService puts between chunks, and how wide a chunk is.
CHUNK_GAP = 5.0
CHUNK_WIDE = 20.0


def constant(text, pattern, fallback=None):
    found = re.search(pattern, text, re.S)
    if not found:
        if fallback is None:
            sys.exit("plan_halls: could not find %s -- the sources have moved." % pattern)
        return fallback
    return float(found.group(1))


def chunk_lengths(count):
    """Representative chunk lengths, taken from the builder's own recipes."""
    lengths = []
    if BUILDER.exists():
        body = BUILDER.read_text(encoding="utf-8")
        start = body.find("LinearChunks")
        for match in re.finditer(r"\n\t(\w+) = \{\n(.*?)\n\t\},\n", body[start:], re.S):
            spans = [float(x) for x in re.findall(r"length = ([\d.]+)", match.group(2))]
            if spans:
                lengths.append(sum(spans))
    if not lengths:
        lengths = [20.0]
    lengths.sort()
    return [lengths[len(lengths) // 2]] * count


def build_route(pattern, bay, total):
    """HallRoute.build, in Python. Left turn maps (x, z) to (z, -x)."""
    legs, at, here, direction, index = [], 0.0, (0.0, 0.0), (0.0, 1.0), 0
    while at < total:
        bays, turn = pattern[index % len(pattern)]
        span, last = bays * bay, False
        if at + span >= total:
            span, last = total - at, True
        legs.append({"at": at, "len": span, "dir": direction, "from": here})
        at += span
        here = (here[0] + direction[0] * span, here[1] + direction[1] * span)
        if last:
            break
        direction = (direction[1], -direction[0]) if turn > 0 else (-direction[1], direction[0])
        index += 1
    return legs


def legs_from(pattern, lengths):
    """HallRoute.fromLegs, in Python: explicit leg lengths, the pattern's turns."""
    legs, at, here, direction = [], 0.0, (0.0, 0.0), (0.0, 1.0)
    for index, span in enumerate(lengths):
        span = max(span, 1.0)
        legs.append({"at": at, "len": span, "dir": direction, "from": here})
        at += span
        here = (here[0] + direction[0] * span, here[1] + direction[1] * span)
        turn = pattern[index % len(pattern)][1]
        direction = (direction[1], -direction[0]) if turn > 0 else (-direction[1], direction[0])
    return legs


def point_at(legs, at):
    for index, leg in enumerate(legs):
        last = index == len(legs) - 1
        if at < leg["at"] + leg["len"] or last:
            along = at - leg["at"]
            if not last:
                along = max(0.0, min(leg["len"], along))
            return ((leg["from"][0] + leg["dir"][0] * along,
                     leg["from"][1] + leg["dir"][1] * along), leg["dir"])
    return ((0.0, 0.0), (0.0, 1.0))


class Halls:
    """Everything plan_halls needs to know, worked out once from the sources."""

    def __init__(self):
        self.text = SERVICE.read_text(encoding="utf-8")
        route_src = ROUTE.read_text(encoding="utf-8")
        self.scale = constant(self.text, r"local SCALE = ([\d.]+)")
        self.bay = 24 * self.scale
        self.lane = constant(self.text, r"local LANE_HALF = ([\d.]+)")
        self.hall = constant(self.text, r"local HALL_HALF_WIDTH = BAY \* ([\d.]+)") * self.bay
        self.drop = constant(self.text, r"local FLOOR_DROP = ([\d.]+)")
        self.mouth_off = constant(self.text, r"local MOUTH_OFFSET = ([\d.]+)")
        self.pit = constant(self.text, r"local PIT_HALF = ([\d.]+)")
        self.slide_r = constant(self.text, r"local SLIDE_RADIUS = ([\d.]+) \* SCALE") * self.scale
        self.wall = constant(self.text, r"local WALL_THICK = ([\d.]+) \* SCALE") * self.scale
        self.basin = constant(self.text, r"BASIN_CHANCE then.*?local half = BAY \* ([\d.]+)") * self.bay
        self.tall_bays = constant(self.text, r"local TALL_BAYS = ([\d.]+)")
        self.mouth_along = constant(self.text, r"local MOUTH_ALONG = ([\d.]+)")
        self.gangway_tail = constant(self.text, r"local GANGWAY_TAIL = ([\d.]+)")
        self.pool_half = constant(self.text, r"local POOL_HALF = ([\d.]+)")
        self.pool_depth = constant(self.text, r"local POOL_DEPTH = ([\d.]+) \* SCALE") * self.scale
        self.column_half = constant(self.text, r"Hall_Column = Vector3\.new\(([\d.]+),") * self.scale / 2
        self.entrance = constant(self.text, r"local ENTRANCE_DEPTH = BAY \* ([\d.]+)") * self.bay
        self.passage_half = constant(self.text, r"local PASSAGE_HALF = ([\d.]+)")
        self.passage_len = constant(self.text, r"local PASSAGE_LENGTH = BAY \* ([\d.]+)") * self.bay
        level_text = LEVEL_SERVICE.read_text(encoding="utf-8")
        self.arm_z = constant(level_text, r"local JUNCTION_ARM_Z = ([\d.]+)")
        self.arm_reach = constant(level_text, r"local JUNCTION_ARM_REACH = ([\d.]+)")
        self.chamber = constant(self.text, r"hallFloorY, room.Position.Z\), BAY \* ([\d.]+)") * self.bay
        self.pattern = [(int(b), int(t))
                        for b, t in re.findall(r"\{ bays = (\d+), turn = (-?\d+) \}", route_src)]

    def lay_out(self, count):
        """LevelService's placement loop: turning where the chunks are, not at a fixed place."""
        lengths, index, along, junctions = [], 0, 0.0, []
        origin, direction = (0.0, 0.0), (0.0, 1.0)
        chunks = []
        for span in chunk_lengths(count):
            bays, turn = self.pattern[index % len(self.pattern)]
            if along + span > bays * self.bay:
                # LevelService's corner, mirrored: an S2_Junction, entered by its main run and
                # left by its arm for a left turn, entered by its arm and left by its main run's
                # south face for a right. The corner is inside it either way.
                left = turn > 0
                corner = along + (self.arm_z if left else self.arm_reach)
                lengths.append(corner)
                origin = (origin[0] + direction[0] * corner, origin[1] + direction[1] * corner)
                leaving = ((direction[1], -direction[0]) if left
                           else (-direction[1], direction[0]))
                junctions.append((origin, direction, leaving, left))
                direction = leaving
                index += 1
                along = (self.arm_reach if left else self.arm_z) + CHUNK_GAP
            where = (origin[0] + direction[0] * along, origin[1] + direction[1] * along)
            chunks.append((where, direction, span))
            along += span + CHUNK_GAP
        lengths.append(max(1.0, along - CHUNK_GAP))
        used = legs_from(self.pattern, lengths)
        return {
            "legs": used,
            "corners": [leg["at"] + leg["len"] for leg in used[:-1]],
            "chunks": chunks,
            "junctions": junctions,
            "length": sum(lengths),
        }

def draw_plan(axis, halls, run, title):
    axis.set_facecolor("#11161a")
    end_at, end_dir = point_at(run["legs"], run["length"])
    left = (end_dir[1], -end_dir[0])
    chamber_at = (end_at[0] + left[0] * halls.mouth_off * 0.55,
                  end_at[1] + left[1] * halls.mouth_off * 0.55)

    def in_chamber(where):
        return (abs(where[0] - chamber_at[0]) < halls.chamber
                and abs(where[1] - chamber_at[1]) < halls.chamber)

    def block(centre, along, across, direction, colour, alpha=1.0, edge=None, z=2, lw=0.8):
        side = (direction[1], -direction[0])
        pts = []
        for da, dc in ((-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)):
            pts.append((centre[0] + direction[0] * along * da + side[0] * across * dc,
                        centre[1] + direction[1] * along * da + side[1] * across * dc))
        axis.add_patch(patches.Polygon(pts, closed=True, facecolor=colour, alpha=alpha,
                                       edgecolor=edge or "none", linewidth=lw, zorder=z))

    # ---- the corridor, and where a basin is allowed to sit in it
    # chooseTall, mirrored. A junction eats a corridor width off the END IT SITS AT, and the
    # first leg has none behind it while the last runs into the chamber instead -- so charging
    # every leg for two of them, which the first version of this drawing did, undercounts the
    # opening leg by a hundred studs and reports no tall hall on the short run when there is
    # one. A plan that disagrees with the level is worse than no plan.
    want = halls.tall_bays * halls.bay
    count = len(run["legs"])
    longest, tall = None, None
    for index, leg in enumerate(run["legs"]):
        usable = leg["len"]
        if index > 0:
            usable -= halls.hall
        if index < count - 1:
            usable -= halls.hall
        if (usable > want + halls.bay * 0.5
                and (longest is None or leg["len"] > longest[0]["len"])
                and (index < count - 1 or count == 1)):
            longest = (leg, index)
    if longest:
        leg, index = longest
        low = -halls.bay * 0.5 if index == 0 else halls.hall
        high = leg["len"] - (0 if index == count - 1 else halls.hall)
        a0 = max(low, (low + high) / 2 - want / 2)
        a1 = min(high, a0 + want)
        if a1 - a0 >= want * 0.75:
            tall = (leg, a0, a1, leg["at"] + a0)

    for index, leg in enumerate(run["legs"]):
        direction, origin_ = leg["dir"], leg["from"]
        first, last = index == 0, index == len(run["legs"]) - 1
        # The first leg's walls run back to the entrance's end wall now, past the start.
        start = -halls.entrance if first else halls.hall
        stop = leg["len"] if last else leg["len"] - halls.hall
        while stop > start and in_chamber((origin_[0] + direction[0] * stop,
                                           origin_[1] + direction[1] * stop)):
            stop -= 4
        if stop <= start:
            continue
        middle = (origin_[0] + direction[0] * (start + stop) / 2,
                  origin_[1] + direction[1] * (start + stop) / 2)
        side = (direction[1], -direction[0])
        block(middle, stop - start, halls.hall * 2, direction, "#1d2a31", 1.0, z=1)
        # THE BAND A BASIN CAN OCCUPY, on both sides. Its lateral position is fixed -- hard
        # against the wall -- so drawing the band rather than a random sample shows the real
        # clearance to the lane instead of one roll of the dice.
        for hand in (1, -1):
            centre = (middle[0] + side[0] * hand * (halls.hall - halls.wall / 2 - halls.basin),
                      middle[1] + side[1] * hand * (halls.hall - halls.wall / 2 - halls.basin))
            block(centre, stop - start, halls.basin * 2, direction, "#1c4f63", 0.85, z=2)
            wall = (middle[0] + side[0] * hand * halls.hall,
                    middle[1] + side[1] * hand * halls.hall)
            block(wall, stop - start, halls.wall, direction, "#7d8a92", z=3)

    # ---- the pool: choosePools, mirrored. One box per leg, touching and never overlapping.
    pools = []
    problems = run.setdefault("problems", [])
    pool_half = halls.pool_half
    for index, leg in enumerate(run["legs"]):
        pdir, porigin = leg["dir"], leg["from"]
        pside = (pdir[1], -pdir[0])

        def on_leg(a, lateral, pdir=pdir, porigin=porigin, pside=pside):
            return (porigin[0] + pdir[0] * a + pside[0] * lateral,
                    porigin[1] + pdir[1] * a + pside[1] * lateral)

        first, last = index == 0, index == len(run["legs"]) - 1
        a0 = -halls.entrance + halls.bay * 0.22 + 12 if first else pool_half
        a1 = leg["len"] if last else leg["len"] + pool_half

        def in_room(a, on_leg=on_leg):
            return any(in_chamber(on_leg(a, lateral))
                       for lateral in (-pool_half - 4, 0, pool_half + 4))

        while a1 > a0 and in_room(a1):
            a1 -= 4
        if a1 - a0 > halls.bay * 0.5 and not in_room(a0):
            corners = [on_leg(a, lateral) for a in (a0, a1) for lateral in (pool_half, -pool_half)]
            pools.append((min(c[0] for c in corners), max(c[0] for c in corners),
                          min(c[1] for c in corners), max(c[1] for c in corners)))
            block(on_leg((a0 + a1) / 2, 0), a1 - a0, pool_half * 2, pdir, "#1d6f7e", 1.0,
                  edge="#d8e4dc", z=3, lw=0.7)
    for i, a in enumerate(pools):
        for b in pools[i + 1:]:
            dx = min(a[1], b[1]) - max(a[0], b[0])
            dz = min(a[3], b[3]) - max(a[2], b[2])
            if dx > 0.5 and dz > 0.5:
                problems.append("two legs' pools overlap by %.0f x %.0f studs" % (dx, dz))
    # The junction's inside-corner column stands in the shallows, clear of every pool's gutter.
    for turn in run["corners"]:
        where, into = point_at(run["legs"], turn - 1)
        out_dir = point_at(run["legs"], turn + 1)[1]
        if in_chamber(where):
            continue
        reach = halls.hall - halls.bay * 0.3
        column = (where[0] + (-into[0] + out_dir[0]) * reach, where[1] + (-into[1] + out_dir[1]) * reach)
        for box in pools:
            gap_x = max(box[0] - column[0], 0, column[0] - box[1])
            gap_z = max(box[2] - column[1], 0, column[1] - box[3])
            if (gap_x * gap_x + gap_z * gap_z) ** 0.5 < halls.column_half + 3.6:
                problems.append("a junction column stands in the pool's edge")
    run["pools"] = pools

    # ---- behind the start: the passage through the end wall, and the lit side room off it
    first_leg = run["legs"][0]
    fdir, forigin = first_leg["dir"], first_leg["from"]
    fside = (fdir[1], -fdir[0])

    def behind(back, lateral):
        return (forigin[0] - fdir[0] * back + fside[0] * lateral,
                forigin[1] - fdir[1] * back + fside[1] * lateral)

    near = halls.entrance + halls.wall
    far = near + halls.passage_len
    block(behind((near + far) / 2, 0), halls.passage_len, halls.passage_half * 2, fdir,
          "#141c21", 1.0, edge="#3d525d", z=1)
    side_out = halls.passage_half + halls.bay * 0.62
    block(behind(far - halls.bay * 0.25, (halls.passage_half + side_out) / 2), halls.bay * 0.5,
          side_out - halls.passage_half, fdir, "#3a3524", 1.0, edge="#e8c46a", z=1)

    if tall:
        leg, a0, a1, _ = tall
        where = (leg["from"][0] + leg["dir"][0] * (a0 + a1) / 2,
                 leg["from"][1] + leg["dir"][1] * (a0 + a1) / 2)
        block(where, a1 - a0, halls.hall * 2, leg["dir"], "none", 1.0,
              edge="#e8c46a", z=9, lw=2.0)
        run["tall_at"] = tall[3]

    # ---- junctions, minus any the last chamber swallows
    for turn in run["corners"]:
        where, _ = point_at(run["legs"], turn - 1)
        inside = in_chamber(where)
        axis.add_patch(patches.Rectangle(
            (where[0] - halls.hall, where[1] - halls.hall), halls.hall * 2, halls.hall * 2,
            facecolor="none" if inside else "#1d2a31",
            edgecolor="#ff8c5a" if inside else "#3d525d",
            linestyle="--" if inside else "-", linewidth=1.2, zorder=1))

    # ---- the last chamber, the pit, the flume, the apron
    axis.add_patch(patches.Rectangle(
        (chamber_at[0] - halls.chamber, chamber_at[1] - halls.chamber),
        halls.chamber * 2, halls.chamber * 2,
        facecolor="#20303a", edgecolor="#9fb3bd", linewidth=1.2, zorder=1))
    # The mouth is out along the bridge and past the end of the route; the helix axis -- and so
    # the pit -- is one radius FORWARD of it, because the tube leaves along the bridge and the
    # rider starts a radius from the centre. Mirrored from buildEnd rather than guessed: this
    # drawing said the pit was somewhere else while the flume was ninety degrees out.
    mouth = (end_at[0] + left[0] * halls.mouth_off + end_dir[0] * halls.mouth_along,
             end_at[1] + left[1] * halls.mouth_off + end_dir[1] * halls.mouth_along)
    # BACK along the route from the mouth, not forward. buildEnd puts the helix axis at
    # `mouthAt - xLocal * SLIDE_RADIUS` and xLocal works out as the route's own heading, so the
    # pit sits behind the mouth. Drawing it on the wrong side is how a plan ends up agreeing
    # with itself and not with the level.
    pit = (mouth[0] - end_dir[0] * halls.slide_r, mouth[1] - end_dir[1] * halls.slide_r)
    axis.add_patch(patches.Rectangle(
        (pit[0] - halls.pit, pit[1] - halls.pit), halls.pit * 2, halls.pit * 2,
        facecolor="#05070a", edgecolor="#60727c", linewidth=1.0, zorder=4))
    axis.add_patch(patches.Circle(pit, halls.slide_r, fill=False, edgecolor="#3fd0e0",
                                  linewidth=2.0, zorder=5))

    # ---- the lane nothing may be built in, then the chunks in it
    for index in range(0, int(run["length"]), 24):
        where, direction = point_at(run["legs"], float(index))
        block(where, 26, halls.lane * 2, direction, "#2f4a3a", 0.5, z=2)
    for where, direction, span in run["chunks"]:
        middle = (where[0] + direction[0] * span / 2, where[1] + direction[1] * span / 2)
        block(middle, span, CHUNK_WIDE, direction, "#8ee6a8", 1.0, edge="#2c5a3a", z=7)
    # THE JUNCTION CHUNKS, drawn as the L they are, so a corner that overlaps or gaps shows up
    # here before it shows up in game.
    # `turns_left`, not `left`: the bridge below reads `left` as the end direction's left-hand
    # VECTOR, and reusing the name for this loop's boolean handed it True to index.
    for corner, inward, outward, turns_left in run["junctions"]:
        def at(offset_in, offset_out):
            return (corner[0] + inward[0] * offset_in + outward[0] * offset_out,
                    corner[1] + inward[1] * offset_in + outward[1] * offset_out)
        if turns_left:
            block(at(-2, 0), 20, 16, inward, "#cfe3f2", 1.0, edge="#5b7f96", z=7)
            block(at(0, 16), 16, 16, outward, "#cfe3f2", 1.0, edge="#5b7f96", z=7)
        else:
            block(at(0, 2), 20, 16, outward, "#cfe3f2", 1.0, edge="#5b7f96", z=7)
            block(at(-16, 0), 16, 16, inward, "#cfe3f2", 1.0, edge="#5b7f96", z=7)

    # THE GANGWAY, timber, from just past the route's centreline out to the mouth; and the mast
    # the flume and the gangway's far end both hang off, on the helix's axis.
    deck_mid = (halls.mouth_off - halls.gangway_tail) / 2
    bridge = (end_at[0] + left[0] * deck_mid + end_dir[0] * halls.mouth_along,
              end_at[1] + left[1] * deck_mid + end_dir[1] * halls.mouth_along)
    block(bridge, halls.mouth_along * 2, halls.mouth_off + halls.gangway_tail, end_dir,
          "#a4825c", 1.0, edge="#5e4630", z=6)
    axis.plot([pit[0]], [pit[1]], marker="o", markersize=4, color="#9aa6a8", zorder=8)
    axis.plot([mouth[0]], [mouth[1]], marker="o", markersize=6, color="#3fd0e0", zorder=8)
    axis.plot([0], [0], marker="s", markersize=7, color="#f5f5f5", zorder=8)

    swallowed = sum(1 for turn in run["corners"]
                    if in_chamber(point_at(run["legs"], turn - 1)[0]))
    axis.set_aspect("equal")
    axis.autoscale_view()
    axis.margins(0.05)
    axis.set_title("%s\n%d chunks, %.0f studs, %d corners%s"
                   % (title, len(run["chunks"]), run["length"], len(run["corners"]),
                      ", %d junction in the chamber" % swallowed if swallowed else ""),
                   color="#dfe7ea", fontsize=9)
    axis.tick_params(colors="#6f7d85", labelsize=7)
    for spine in axis.spines.values():
        spine.set_color("#2a353c")
    return swallowed


def draw_section(lift, halls, run):
    """The half a plan cannot show: heights, the fall, and where the flume ends up."""
    lift.set_facecolor("#11161a")
    text = halls.text
    height = 22 * halls.scale
    water = 1.9 * halls.scale
    slide_drop = constant(text, r"local SLIDE_DROP = ([\d.]+) \* SCALE") * halls.scale
    slide_bore = constant(text, r"local SLIDE_BORE = ([\d.]+) \* SCALE") * halls.scale
    plunge = constant(text, r"local SLIDE_PLUNGE = ([\d.]+)")
    pit_deep = constant(text, r"local PIT_WALL_DEPTH = ([\d.]+)")
    void_deep = 0.0
    tall_mult = constant(text, r"local TALL_MULTIPLIER = ([\d.]+)")
    listed = re.search(r"local BASIN_DEPTHS = \{(.*?)\}", text, re.S)
    depths = sorted(float(x) * halls.scale
                    for x in re.findall(r"([\d.]+) \* SCALE", listed.group(1) if listed else ""))
    if not depths:
        sys.exit("plan_halls: BASIN_DEPTHS has gone from FloodedHallsService.")
    floor_y = -halls.drop
    at = run["length"]
    wide = at + halls.chamber * 2 + halls.bay

    lift.add_patch(patches.Rectangle((-halls.bay, floor_y), wide, height,
                                     facecolor="#1d2a31", zorder=1))
    # The tall stretch, drawn where it actually falls along the route.
    # WHERE IT ACTUALLY IS along the route, not a fraction of the way in. The section's whole
    # job is to say how high things are AT a distance; putting one of them at a made-up
    # distance defeats it.
    tall_at = run.get("tall_at")
    if tall_at is not None:
        lift.add_patch(patches.Rectangle((tall_at, floor_y), halls.tall_bays * halls.bay,
                                         height * tall_mult, facecolor="#243541",
                                         edgecolor="#e8c46a", linewidth=1.2, zorder=2))
        lift.text(tall_at + 10, floor_y + height * tall_mult - 22, "the tall hall",
                  color="#e8c46a", fontsize=8, zorder=7)

    # The basins, one of each depth, so the three read against each other.
    for index, deep in enumerate(depths):
        where = at * (0.44 + index * 0.13)
        lift.add_patch(patches.Rectangle((where, floor_y - deep), halls.basin * 2, deep,
                                         facecolor="#123243", edgecolor="#3fd0e0",
                                         linewidth=0.9, zorder=4))
        lift.text(where + 4, floor_y - deep + 6, "%.0f" % deep, color="#6fd8e8",
                  fontsize=7, zorder=7)

    lift.add_patch(patches.Rectangle((-halls.bay, floor_y - max(depths)), wide,
                                     water + max(depths), facecolor="#2f7f6c", alpha=0.45,
                                     zorder=3))
    lift.axhline(0, color="#8ee6a8", linewidth=2.2, zorder=6)
    lift.axhline(-40, color="#ff6b6b", linewidth=1.1, linestyle="--", zorder=7)
    lift.text(4, -36, "kill plane", color="#ff9b9b", fontsize=8, zorder=8)
    lift.text(4, floor_y + water + 5, "flooded floor", color="#7fd6c0", fontsize=8, zorder=8)
    lift.text(4, -14, "the walkway", color="#8ee6a8", fontsize=8, zorder=8)

    # The pool under the walkway, all the way to the last room.
    lift.add_patch(patches.Rectangle((-halls.bay, floor_y - halls.pool_depth), at, halls.pool_depth,
                                     facecolor="#1d6f7e", edgecolor="#d8e4dc", linewidth=0.8,
                                     alpha=0.9, zorder=4))
    lift.text(8, floor_y - halls.pool_depth + 8, "the pool", color="#bfe8e4", fontsize=8, zorder=8)
    pit_left = at + halls.chamber - halls.pit
    lift.add_patch(patches.Rectangle((pit_left, floor_y - pit_deep), halls.pit * 2, pit_deep,
                                     facecolor="#05070a", edgecolor="#60727c", zorder=5))
    lift.text(pit_left + halls.pit * 0.2, floor_y - pit_deep + 40, "the shaft", color="#55656d",
              fontsize=9, zorder=8)
    lift.plot([pit_left + halls.pit, pit_left + halls.pit * 1.2],
              [slide_bore, slide_bore - slide_drop], color="#3fd0e0", linewidth=3.0, zorder=9)
    lift.plot([pit_left + halls.pit * 1.2, pit_left + halls.pit * 1.2],
              [slide_bore - slide_drop, slide_bore - slide_drop - plunge],
              color="#3fd0e0", linewidth=1.3, linestyle=":", zorder=9)
    lift.plot([pit_left + halls.pit * 1.2], [slide_bore - slide_drop - plunge],
              marker="v", markersize=8, color="#3fd0e0", zorder=10)

    lift.add_patch(patches.Rectangle((0, -3), at, 3, facecolor="#8ee6a8", zorder=6))
    lift.set_xlim(-halls.bay, wide)
    lift.set_ylim(floor_y - pit_deep - void_deep - 30, height * tall_mult + floor_y + 30)
    lift.set_title("the medium run in section   distance along the route, height above the "
                   "walkway", color="#dfe7ea", fontsize=9)
    lift.tick_params(colors="#6f7d85", labelsize=7)
    for spine in lift.spines.values():
        spine.set_color("#2a353c")


def main():
    halls = Halls()
    levels = LEVELS.read_text(encoding="utf-8")
    hub = HUB.read_text(encoding="utf-8") if HUB.exists() else ""
    authored = 44
    for match in re.finditer(r"LevelDefinitions\.(\w+) = \{(.*?)\n\}", levels, re.S):
        if 'backdrop = "floodedHalls"' in match.group(2):
            found = re.search(r"minChunks = (\d+)", match.group(2))
            if found:
                authored = int(found.group(1))
    short = constant(hub, r'length == "short" then\s*\n\s*return ([\d.]+)', 0.5) if hub else 0.5
    long_ = constant(hub, r'length == "long" then\s*\n\s*return ([\d.]+)', 1.5) if hub else 1.5

    figure = plt.figure(figsize=(16, 12))
    grid = figure.add_gridspec(2, 3, height_ratios=[2.1, 1.0])
    medium = None
    runs = []
    swallowed_any = 0
    for column, (name, scale) in enumerate(
            (("Short", short), ("Medium", 1.0), ("Long", long_))):
        count = max(4, int(authored * scale))
        run = halls.lay_out(count)
        runs.append(run)
        swallowed_any += draw_plan(figure.add_subplot(grid[0, column]), halls, run,
                                   "%s (x%.2g)" % (name, scale))
        if name == "Medium":
            medium = run

    draw_section(figure.add_subplot(grid[1, :]), halls, medium)
    problems = []
    for column, (name, scale) in enumerate((("Short", short), ("Medium", 1.0), ("Long", long_))):
        pass
    problems = [p for run in runs for p in run.get("problems", [])]
    figure.patch.set_facecolor("#0b0f12")
    figure.tight_layout()
    figure.savefig(OUT, dpi=100, facecolor=figure.get_facecolor())
    print("wrote %s" % OUT.name)
    print("  white square = the start, green = chunks, pale blue L = the junction chunk at each corner,")
    print("  dark green band = the lane nothing may be built in, blue band = where a basin")
    print("  may sit, gold outline = the tall hall, cyan = the flume, black = the pit,")
    print("  brown = the timber gangway, grey dot = the flume's mast, dark strip behind the start")
    print("  = the passage through the end wall, with its lit side room outlined in gold,")
    print("  teal with a pale edge = the pool down the middle of each leg.")
    for run in runs:
        print("  %d chunks: %d pool boxes" % (len(run["chunks"]), len(run.get("pools", []))))
    if problems:
        print("POOL PROBLEMS:")
        for problem in problems:
            print("  " + problem)
        sys.exit(1)
    print("  a dashed orange junction is one the last chamber swallowed, which is handled.")
    if swallowed_any:
        print("  %d junction(s) fell inside a chamber across the three lengths; the corridor"
              % swallowed_any)
        print("  skips those and the chamber's own walls close the space.")


if __name__ == "__main__":
    main()
