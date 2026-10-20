"""Sky Pools (Level 2): holds the level's shape to what SkyPoolsService assumes.

Run with plain Python from the project root:  python blender/check_skypools.py

SkyPoolsService builds terraces, a slide, a tower and a cloud sea round a route LevelService lays
from random draws, so nothing about it can be looked at in one fixed layout. This lays the route the
way LevelService does (skypools_layout.py) -- the same template, pool, meander and steps, DOWN --
for short, medium and long runs over many seeds, and checks every one:

  THE MEANDER IS GENTLE ENOUGH TO RUN. A chunk's entry face may only turn so far from the last
  chunk's exit and still be landed on; the ring's turn rate was the figure, and the meander's worst
  bend stays under it.
  THE ROUTE NEVER COMES BACK ON ITSELF, and no terrace overhangs another part of it.
  THE TERRACES CLEAR THEIR NEIGHBOURS. A terrace starts NECK studs out from the checkpoint chunk's
  cap edge and is longer than that chunk, so it overhangs the chunks either side; none of them may
  reach out that far. They take alternating sides, so no two of them meet.
  A TERRACE HOLDS ITSELF UP AND HOLDS TOGETHER. Every column stands under deck or under the pool it
  carries; everything that stands on the deck stands ON it, clear of the water, the overflow and
  each other; the pool is deep enough to swim in and its steps are shallow enough to walk out of.
  THE SLIDE HITS NOTHING. Its trough and its rods keep clear of every chunk, terrace and column, in
  plan or by height; the first stretch out of the mouth is clear of everything; it clears the final
  pool's rim; it lands inside the pool and outside the tower's water curtain; it is never steeper
  than a slide should be, nor too fast to be calm.
  THE HEIGHTS ARE IN ORDER: walkway, clouds, the cloud sea's underside, the final pool, the sea.
  AND THE WIRING IS THERE: Bootstrap builds it, stands the old finish line down, exempts a rider
  from the kill plane and clears the terrain water; the ride's remote and shared path exist and both
  sides use them; the palette and the finale banner exist; clouds are not Ball parts.

Exits non-zero on any failure.
"""
import math
import re
import sys

from skypools_layout import (AMPLITUDE, BASE_SURFACE_Y, BY_CATEGORY, C, CAP_HALF, CAP_TOP, CONTRACTS, DESCENDS,
                             DESTROY_Y, GAP, IS_MEANDER, LAYOUTS, LEVEL2, P, POOL_IDS, ROOT, RUNS, S, SKY,
                             SKYPATH, SLOTS, WAVELENGTH, boxes_overlap, chosen_terraces, chunk_frame,
                             declared_category, finish_frame, heights, kill_y, lay, on_deck, ring_radius,
                             slide_point, slide_spec, terrace_frame, terrace_plan, under_terrace, xmax)

SRC = ROOT / "src"
BOOT = (SRC / "Server" / "Bootstrap.server.lua").read_text(encoding="utf-8")
LIGHT = (SRC / "Server" / "Services" / "LightingService.lua").read_text(encoding="utf-8")
UI = (SRC / "Client" / "Services" / "UIService.lua").read_text(encoding="utf-8")
CLIENT = (SRC / "Client" / "Services" / "SkyPoolsClient.lua").read_text(encoding="utf-8")
CLIENT_BOOT = (SRC / "Client" / "Bootstrap.client.lua").read_text(encoding="utf-8")

problems = []


def fail(message):
    problems.append(message)


# ===================================================================== the definition

if not IS_MEANDER:
    print("FAIL: Level2 is not laid as a meander; Sky Pools follows a path down, not a ring")
    sys.exit(1)
if not DESCENDS:
    fail("Level2's route does not descend; Sky Pools goes DOWN toward its clouds")
for field, want in (("backdrop", "skyPools"), ("finale", "slide")):
    if '%s = "%s"' % (field, want) not in LEVEL2:
        fail("Level2 has no %s = \"%s\"" % (field, want))
for cid in POOL_IDS:
    if declared_category(cid) is None:
        fail("%s has no category this check can read in ChunkDefinitions" % cid)

# HOW FAR THE ROUTE MAY BEND, measured against the ring this level used to be laid as -- which ran
# for months, so its turn rate is the known-good figure. The ring turned (length + gap) over its
# radius at every chunk; the meander's worst is amplitude * 2pi / wavelength over the same chunk.
longest = max(CONTRACTS[c][0] for c in POOL_IDS)
short_count = RUNS[0][1]
ring_turn = (longest + GAP) / ring_radius([SLOTS[i % len(SLOTS)] for i in range(short_count)])
bend = AMPLITUDE * 2 * math.pi / WAVELENGTH * (longest + GAP)
if bend > ring_turn:
    fail("the meander turns %.1f degrees at the longest chunk, past the %.1f the ring it replaces turned"
         % (math.degrees(bend), math.degrees(ring_turn)))

# ===================================================================== the pool itself

if BY_CATEGORY.get("stable") != ["S1_Straight"]:
    fail("Sky Pools' only stable chunk must be S1_Straight (terraces are laid along its straight side); "
         "the pool has %s" % BY_CATEGORY.get("stable"))
for cid in POOL_IDS:
    if CONTRACTS[cid][1] > 0:
        fail("%s climbs %.1f inside itself, in the one level that only goes down" % (cid, CONTRACTS[cid][1]))

TERRACE_INNER = CAP_HALF + S["NECK"]
widest = max(POOL_IDS, key=xmax)
if xmax(widest) + 2 > TERRACE_INNER:
    fail("%s reaches %.1f from the route's centre line, inside the 2-stud margin of a terrace starting at %.1f"
         % (widest, xmax(widest), TERRACE_INNER))
S1_LEN = CONTRACTS["S1_Straight"][0]
if S["TERRACE_L"] / 2 > S1_LEN / 2 + GAP + min(CONTRACTS[c][0] for c in POOL_IDS):
    fail("a terrace is longer than its chunk and both neighbours together")

# The neck has to swallow the straight chunk's shelves, which hang below its top.
shelf_bottom = min(b.y - b.sy / 2 for b in LAYOUTS["S1_Straight"])
if S["NECK_THICK"] + 0.01 < CAP_TOP - shelf_bottom:
    fail("the neck is %.1f deep and the straight chunk's shelves hang %.1f under its cap top"
         % (S["NECK_THICK"], CAP_TOP - shelf_bottom))

# ===================================================================== one terrace, on its own

# The sizes terraces are actually built at: the checkpoint ones, the one off the finale walkway, and
# the smallest and largest the scenery pools are drawn at.
EVERYTHING = ("loungers", "parasol", "towel", "pergola", "planters", "cabana", "lifeguard", "board")
POOLSIDE = ("loungers", "parasol")
TERRACE_SIZES = [
    ("terrace", S["NECK"], S["TERRACE_W"], S["TERRACE_L"], EVERYTHING),
    ("finale terrace", 0, 34, S["WALK_L"] - 8, POOLSIDE),
    ("small scenery pool", 0, 34, 28, POOLSIDE),
    ("large scenery pool", 0, 46, 38, POOLSIDE),
]

for name, x0, wide, long, dressed in TERRACE_SIZES:
    plan = terrace_plan(x0, wide, long)
    # The outline is not a square: a narrow walk, a wider middle, a rounded prow past the pool.
    if plan["entry_half"] >= plan["lz"] - 2:
        fail("%s: the walk in is as wide as the terrace, so the outline is a rectangle" % name)
    if plan["nose_r"] < 3:
        fail("%s: the prow is only %.1f across, which reads as a corner rather than a nose"
             % (name, plan["nose_r"] * 2))
    # The prow is a disc centred on the terrace's outer edge, so the pool has to stop short of it.
    if plan["px1"] > plan["x1"] - plan["nose_r"] - 0.5:
        fail("%s: the prow's disc reaches back into the pool" % name)
    # Every column stands under something it could be carrying.
    half = S["COLUMN_D"] / 2
    for cx, cz in plan["columns"]:
        for step in range(16):
            angle = step * math.pi / 8
            at = (cx + math.cos(angle) * half, cz + math.sin(angle) * half)
            if not under_terrace(plan, at, 0.01):
                fail("%s: the column at (%.1f, %.1f) is not under the deck or the pool it carries"
                     % (name, cx, cz))
                break
    # Everything that stands on the deck stands ON it, out of the water and out of the overflow.
    for item, boxes in plan["stands"].items():
        if item not in dressed:
            continue
        for box in boxes:
            for at in ((box[0], box[2]), (box[1], box[2]), (box[0], box[3]), (box[1], box[3])):
                if not on_deck(plan, at, 0.01):
                    fail("%s: the %s hangs off the deck at (%.1f, %.1f)" % (name, item, at[0], at[1]))
                    break
            if boxes_overlap(box, plan["spill"], 0.2):
                fail("%s: the %s stands in the overflow channel" % (name, item))
    # The pool: deep enough to swim in, with steps shallow enough to walk back out of.
    rise = S["POOL_DEPTH"] / (S["BEACH_STEPS"] + 1)
    if rise > 2:
        fail("the pool's steps rise %.1f each, past the two studs a character steps up" % rise)
    if plan["steps_end"] > plan["px1"] - 4:
        fail("%s: the steps fill the pool, leaving nothing to swim in" % name)
# ===================================================================== what you can use and leave

# THE HATCH IS A WAY OUT, not only a way in. The deck it is cut through is as deep as the pool, and
# at four studs square that was a shaft the width of a character with a ladder in it.
if S["HATCH"] < 6:
    fail("the pump room's hatch is %.0f studs across and the deck is %.0f deep: that is a hole you "
         "get stuck in" % (S["HATCH"], S["DECK_THICK"]))
if "ladderHigh = math.ceil((ladderTop - (floorTop - 1)) / 2) * 2" not in SKY:
    fail("the hatch ladder no longer runs past the deck, so there is nothing to hold climbing out")
if "HatchRail" not in SKY:
    fail("the hatch has no grab rail at the top")
# FURNITURE YOU CAN USE. A lounger you cannot lie on is a lounger-shaped object.
if 'local function seat(' not in SKY:
    fail("SkyPoolsService has no seat(), so nothing on a terrace can be sat on")
for needle, why in (
    ('seat(parent, "LoungerCushion"', "the loungers are blocks again, so you cannot lie on them"),
    ('seat(parent, "ChairSeat"', "the lifeguard's chair is a block again, so you cannot sit in it"),
):
    if needle not in SKY:
        fail(why)
# THE CLOUDS ARE NOT PAPER WHITE. White cloud under a translucent chunk is what made the chunks
# vanish when you looked down at them; see the note by CLOUD_TOP.
cloud = re.search(r"local CLOUD_TOP = Color3\.fromRGB\((\d+), (\d+), (\d+)\)", SKY)
if not cloud:
    fail("this check can no longer read the cloud's colour")
elif min(int(cloud.group(index)) for index in (1, 2, 3)) > 244:
    fail("the cloud sea is back to near-white, which is what hid the translucent chunks from above")
if "specular = 0.5" not in LIGHT:
    fail("the skyPools palette no longer turns the environment specular down, so glossy chunk tops "
         "mirror the white sky again")

if S["POOL_DEPTH"] < 8:
    fail("the pool is %.1f deep, too shallow to swim in" % S["POOL_DEPTH"])
if S["WATER_DROP"] <= 0 or S["WATER_DROP"] > 1:
    fail("the water's surface is %.2f under the deck, which is either over it or a step down into it"
         % S["WATER_DROP"])

# WHAT skypools_layout.terrace_plan RESTATES. It is a copy of the terrace's geometry in Python, and
# a copy is only worth anything while it matches: every line below has to be in SkyPoolsService as
# written, or the picture and this check are of a terrace that is not being built.
for line in (
    "local entryHalf = math.max(6, long * ENTRY_SHARE)",
    "local poolW = math.min(POOL_W, wide * 0.5)",
    "local px0 = x0 + wide * POOL_FROM",
    "local pz = math.min(POOL_L, long * 0.42) / 2",
    "local noseR = math.min(lz - 4, wide * 0.22, x1 - px1 - 0.8)",
    "local shoulder = math.min(6, (px0 - x0) * 0.6)",
    "local innerZ = math.min(8, lz - 6)",
    "local outerZ = math.min(8, lz - 8.2)",
    "local sunZ = math.min(pz + 4.6, lz - 4.3)",
    "local shadeZ = -math.min(pz + 5, lz - 3)",
    "local spread = math.max(3.4, poolW * 0.2)",
    "local stepsEnd = px0 + BEACH_STEPS * STEP_RUN",
    "{ px0 - 2.5, -innerZ }, { px0 - 2.5, innerZ }, { px1 + 2.5, -outerZ }, { px1 + 2.5, outerZ },",
    "{ px0 + 3.5, -(lz - 3) }, { px0 + 3.5, lz - 3 }, { px1 - 3.5, -(lz - 3) }, { px1 - 3.5, lz - 3 },",
    "strip(px0 - shoulder, px0, -(lz - 3), -entryHalf)",
    "strip(px0, px1, -lz, -pz)",
    "strip(px1, x1, -(lz - 5), lz - 5)",
    "lounger(parent, frame * CFrame.new(poolX + dx, 0, sunZ), colour)",
    "pergola(parent, frame, poolX, shadeZ - 1.5, 11, 6, colour)",
):
    if line not in SKY:
        fail("SkyPoolsService no longer has `%s`, which skypools_layout.terrace_plan restates" % line)

# ===================================================================== what is on each terrace

plan = terrace_plan(S["NECK"], S["TERRACE_W"], S["TERRACE_L"])
dressing_block = SKY[SKY.index("local dressings = {"):]
dressing_block = dressing_block[:dressing_block.index("\n\t}")]
dressing_lines = [line for line in dressing_block.splitlines() if line.strip().startswith("{")]
if len(dressing_lines) < 3:
    fail("this check can no longer read the terraces' dressing lists")
for line in dressing_lines:
    items = re.findall(r'"(\w+)"', line)
    boxes = [(item, box) for item in items for box in plan["stands"].get(item, [])]
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            if boxes[i][0] != boxes[j][0] and boxes_overlap(boxes[i][1], boxes[j][1], 0.3):
                fail("the %s stands on the %s on the terrace dressed %s" % (boxes[i][0], boxes[j][0], items))
    # The board's plank and the ladder share the pool; they must not share a place in it.
    if "board" in items and "ladder" in items:
        for a in plan["over_water"]["board"]:
            for b in plan["over_water"]["ladder"]:
                if boxes_overlap(a, b, 0.3):
                    fail("the diving board comes down on the pool ladder")

# ===================================================================== the pump room

x0, px0, px1, pz, lz = S["NECK"], plan["px0"], plan["px1"], plan["pz"], plan["lz"]
hatch = (x0 + S["HATCH_FROM"], x0 + S["HATCH_FROM"] + S["HATCH"], S["HATCH_Z"], S["HATCH_Z"] + S["HATCH"])
room = (x0 + 0.5, min(px1 - 2, x0 + S["ROOM_LONG"]), S["ROOM_Z0"], S["ROOM_Z1"])
inner_z = plan["inner_z"]
if room[2] < -inner_z + S["COLUMN_D"] / 2 + 0.4 or room[3] > inner_z - S["COLUMN_D"] / 2 - 0.4:
    fail("the pump room's walls reach the columns carrying the pool's inner corners at z +-%.1f" % inner_z)
if not (room[0] + 0.8 <= hatch[0] and hatch[1] <= room[1] - 0.8 and room[2] + 0.8 <= hatch[2]
        and hatch[3] <= room[3] - 0.8):
    fail("the pump room's hatch is not over the room")
if not (x0 <= hatch[0] and hatch[1] <= px0):
    fail("the pump room's hatch is not in the terrace's walk in")
if abs(S["HATCH_Z"]) > plan["entry_half"] - S["HATCH"]:
    fail("the pump room's hatch is not under the walk in, which is only %.1f wide" % (plan["entry_half"] * 2))
with_room = [re.findall(r'"(\w+)"', line) for line in dressing_lines if '"pumproom"' in line]
if not with_room:
    fail("no terrace has the pump room")
for items in with_room:
    for item in items:
        for box in plan["stands"].get(item, []):
            if boxes_overlap(box, hatch, 0.3):
                fail("the pump room's hatch is under the %s on its terrace" % item)
pump_terrace = next((i for i, line in enumerate(dressing_lines) if '"pumproom"' in line), None)

# A toy drifts no further than the water it floats on.
drift_x = (px1 - plan["steps_end"]) / 2 - 3
if drift_x + 2.25 > (px1 - plan["steps_end"]) / 2 - 0.3 or (pz - 3) + 2.25 > pz - 0.3:
    fail("a pool toy can drift into the pool's wall")

# ===================================================================== laying the route


def rect(origin, out, tan, x0v, x1v, z0v, z1v, y0, y1, name):
    """A box: a rectangle in plan in some frame, with a height range."""
    return {"o": origin, "out": out, "tan": tan, "x": (x0v, x1v), "z": (z0v, z1v), "y": (y0, y1), "name": name}


def inside(r, point, pad):
    dx, dz = point[0] - r["o"][0], point[1] - r["o"][1]
    x, z = dx * r["out"][0] + dz * r["out"][1], dx * r["tan"][0] + dz * r["tan"][1]
    return r["x"][0] - pad <= x <= r["x"][1] + pad and r["z"][0] - pad <= z <= r["z"][1] + pad


def world(origin, out, tan, x, z):
    return (origin[0] + out[0] * x + tan[0] * z, origin[1] + out[1] * x + tan[1] * z)


MOUTH_CLEAR = S["MOUTH_CLEAR"]
# READ, NOT RESTATED: how far short of the mouth the walkway's own terrace stops.
short_by = re.search(r"local terraceL = WALK_L - ([\d.]+)", SKY)
if not short_by:
    fail("this check can no longer read how far short of the mouth the finale terrace stops")
terrace_l = S["WALK_L"] - (float(short_by.group(1)) if short_by else 8)
report = {}
# THE STORM BY THE SLIDE builds over the last stretch of a run, never from its first half, and every run reaches
# it: STORM_FROM (SkyPoolsClient) against each laid route's distance from the slide's mouth.
storm_from_found_ = re.search(r"^local STORM_FROM = ([0-9.]+)", CLIENT, re.M)
storm_from_ = float(storm_from_found_.group(1)) if storm_from_found_ else None
if storm_from_ is None:
    fail("this check can no longer read STORM_FROM from SkyPoolsClient")
for label, count in RUNS:
    worst = {"steep": 0.0, "slide": (1e9, 0.0), "apart": 1e9, "drop": 0.0, "long": 0.0, "mouth": 1e9}
    for seed in range(300):
        radius, chunks, finish_y = lay(count, seed)
        tops = [ch["y"] + (CAP_TOP if ch["id"] == "S1_Straight" else 2) for ch in chunks]
        cloud_top, pool_y, sea_y, top_y = heights(BASE_SURFACE_Y, kill_y(chunks))
        if storm_from_ is not None:
            mouth_ = slide_spec(radius, chunks, finish_y)["mouth"]
            near_ = [math.hypot(ch["pos"][0] - mouth_[0], ch["pos"][1] - mouth_[1]) < storm_from_ for ch in chunks]
            if not near_[-1]:
                fail("%s seed %d: the storm by the slide never reaches the end of the route" % (label, seed))
            elif near_.index(True) < len(chunks) * 0.5:
                fail("%s seed %d: the storm by the slide begins in the first half of the run (chunk %d of %d)"
                     % (label, seed, near_.index(True) + 1, len(chunks)))

        # ----- heights in order
        if min(tops) - cloud_top < 20:
            fail("%s seed %d: the lowest walkway is only %.1f above the clouds" % (label, seed, min(tops) - cloud_top))
        if not (sea_y < pool_y < cloud_top - S["CLOUD_THICK"] - 60):
            fail("%s seed %d: the final pool is not in clear air between the clouds' underside and the sea"
                 % (label, seed))
        # A character that ends up below Workspace.FallenPartsDestroyHeight is deleted by the engine.
        if pool_y - S["FINAL_DEEP"] < DESTROY_Y + 30:
            fail("%s seed %d: the final pool's floor is at %.0f, within 30 studs of the %d line where Roblox "
                 "deletes a falling character" % (label, seed, pool_y - S["FINAL_DEEP"], DESTROY_Y))

        # ----- the route never comes back on itself
        for i in range(len(chunks)):
            for j in range(i + 5, len(chunks)):
                gap_studs = math.hypot(chunks[i]["pos"][0] - chunks[j]["pos"][0],
                                       chunks[i]["pos"][1] - chunks[j]["pos"][1])
                if gap_studs < worst["apart"]:
                    worst["apart"] = gap_studs
                if gap_studs < 90:
                    fail("%s seed %d: chunks %d and %d come within %.0f studs of each other"
                         % (label, seed, i + 1, j + 1, gap_studs))

        # ----- what the slide must miss, and where the terraces are
        obstacles = []
        for ch in chunks:
            origin, out, tan = chunk_frame(radius, ch)
            reach = xmax(ch["id"])
            obstacles.append(rect(origin, out, tan, -reach, reach, 0, ch["length"], ch["y"] - 6,
                                  ch["y"] + max(0.0, ch["rise"]) + 4, "chunk %d" % ch["index"]))

        def columns(origin, out, tan, points, top, name):
            half_d = S["COLUMN_D"] / 2
            for x, z in points:
                at = world(origin, out, tan, x, z)
                obstacles.append(rect(at, out, tan, -half_d, half_d, -half_d, half_d, sea_y, top,
                                      name + " column"))

        def terrace_obstacles(origin, out, tan, x0v, wide, long, top, name, neck=0.0):
            """A terrace as SkyPoolsService.terrace lays it, as one box round its whole outline."""
            shape = terrace_plan(x0v, wide, long)
            lz_here = long / 2
            obstacles.append(rect(origin, out, tan, x0v - neck, shape["x1"] + shape["nose_r"], -lz_here, lz_here,
                                  top - max(S["DECK_THICK"], S["NECK_THICK"] if neck else 0), top + 12, name))
            columns(origin, out, tan, shape["columns"], top - S["DECK_THICK"], name)

        chosen = chosen_terraces(chunks)
        terrace_frames = []
        for index, ch in enumerate(chosen, 1):
            edge, out, along = terrace_frame(radius, ch, index)
            terrace_frames.append((ch, edge, out, along))
            terrace_obstacles(edge, out, along, S["NECK"], S["TERRACE_W"], S["TERRACE_L"], ch["y"] + CAP_TOP,
                              "terrace at chunk %d" % ch["index"], neck=S["NECK"])

        # ----- a terrace overhangs its own chunk's neighbours and nothing else
        shape = terrace_plan(S["NECK"], S["TERRACE_W"], S["TERRACE_L"])
        for ch, edge, out, along in terrace_frames:
            corners = [world(edge, out, along, x, z)
                       for x in (S["NECK"], shape["x1"] + shape["nose_r"])
                       for z in (-shape["lz"], shape["lz"])]
            for other in obstacles:
                if not other["name"].startswith("chunk"):
                    continue
                index = int(other["name"].split()[1])
                if abs(index - ch["index"]) <= 1:
                    continue
                for at in corners:
                    if inside(other, at, 2):
                        fail("%s seed %d: the terrace at chunk %d reaches over %s"
                             % (label, seed, ch["index"], other["name"]))
                        break
        # ----- and no two terraces meet
        for a in range(len(terrace_frames)):
            for b in range(a + 1, len(terrace_frames)):
                ca = world(terrace_frames[a][1], terrace_frames[a][2], terrace_frames[a][3],
                           (S["NECK"] + shape["x1"]) / 2, 0)
                cb = world(terrace_frames[b][1], terrace_frames[b][2], terrace_frames[b][3],
                           (S["NECK"] + shape["x1"]) / 2, 0)
                if math.hypot(ca[0] - cb[0], ca[1] - cb[1]) < S["TERRACE_W"] + S["TERRACE_L"]:
                    fail("%s seed %d: two terraces stand within a terrace's own size of each other"
                         % (label, seed))

        # The finale deck and its terrace, straight on from the last chunk, as finaleDeck lays them.
        finish, out, tan = finish_frame(radius, chunks)
        walk_w, walk_l = S["WALK_W"], S["WALK_L"]
        deck_top = finish_y + CAP_TOP
        obstacles.append(rect(finish, out, tan, -walk_w / 2, walk_w / 2, 0, walk_l - 0.5,
                              deck_top - S["DECK_THICK"], deck_top + 14, "finale walkway"))
        columns(finish, out, tan, [(-walk_w / 2 + 4, 4), (-walk_w / 2 + 4, walk_l - 4)],
                deck_top - S["DECK_THICK"], "finale walkway")
        side = world(finish, out, tan, walk_w / 2, terrace_l / 2)
        terrace_obstacles(side, out, tan, 0, 34, terrace_l, deck_top, "finale terrace")

        # ----- the slide
        spec = slide_spec(radius, chunks, finish_y)
        mouth = spec["mouth"]
        # WHAT IS BEHIND THE MOUTH is not in the slide's way: you leave the deck going forward, and
        # the walkway and its terrace are both behind that line.
        behind = set()
        for ob in obstacles:
            ahead = -1e9
            for x in ob["x"]:
                for z in ob["z"]:
                    at_corner = world(ob["o"], ob["out"], ob["tan"], x, z)
                    ahead = max(ahead, (at_corner[0] - mouth[0]) * tan[0] + (at_corner[1] - mouth[1]) * tan[1])
            if ahead <= 0.5:
                behind.add(ob["name"])
        samples = 600
        length = 0.0
        prev = None
        half = P["WIDE"] / 2 + 0.8
        for i in range(samples + 1):
            f = i / samples
            at, y, r = slide_point(spec, f)
            if prev:
                run = math.hypot(at[0] - prev[0][0], at[1] - prev[0][1])
                length += math.hypot(run, y - prev[1])
                if run > 0:
                    worst["steep"] = max(worst["steep"], math.degrees(math.atan2(prev[1] - y, run)))
            prev = (at, y)
            # THE MOUTH IS KEPT CLEAR: nothing stands within MOUTH_CLEAR of the first stretch out of
            # it, so the one thing you came here to do has room.
            gone = math.hypot(at[0] - mouth[0], at[1] - mouth[1])
            if 0 < gone < 60:
                for ob in obstacles:
                    if ob["name"] == "finale walkway" or ob["name"] in behind:
                        continue
                    dx, dz = at[0] - ob["o"][0], at[1] - ob["o"][1]
                    x = dx * ob["out"][0] + dz * ob["out"][1]
                    z = dx * ob["tan"][0] + dz * ob["tan"][1]
                    near = math.hypot(max(ob["x"][0] - x, 0, x - ob["x"][1]), max(ob["z"][0] - z, 0, z - ob["z"][1]))
                    if near < worst["mouth"] and ob["y"][1] > y - 4:
                        worst["mouth"] = near
                    if near < MOUTH_CLEAR and ob["y"][1] > y - 4 and ob["y"][0] < y + 14:
                        fail("%s seed %d: the %s stands %.0f studs from the slide's mouth, inside the %d it is "
                             "given" % (label, seed, ob["name"], near, MOUTH_CLEAR))
                        break
            if f < 0.02:
                continue  # the mouth itself, which is meant to meet the finale deck
            for ob in obstacles:
                if inside(ob, at, half) and ob["y"][0] - 3 < y + 2.2 and y - 1.2 < ob["y"][1]:
                    fail("%s seed %d: the slide at %.2f runs into the %s" % (label, seed, f, ob["name"]))
                    break
            # Its rods climb inward from here to the tower: they must pass under anything above.
            reach = r - S["TOWER_D"] / 2
            if reach > 2:
                rod_top = min(y + 2.2 + reach * 0.45, top_y - 20)
                for ob in obstacles:
                    if ob["name"].startswith("chunk") and inside(ob, at, 2) and rod_top > ob["y"][0] - 3:
                        fail("%s seed %d: a slide rod at %.2f climbs into %s" % (label, seed, f, ob["name"]))
                        break
            # Over the final pool's rim, clear of it.
            if abs(r - (S["FINAL_RADIUS"] + 1.5)) < half + 1.5:
                rim_top = pool_y - S["FINAL_DEEP"] / 2 - 0.2 + (S["FINAL_DEEP"] + 3.6) / 2
                if y - 1.2 < rim_top + 2:
                    fail("%s seed %d: the slide meets the final pool's rim" % (label, seed))
        worst["drop"] = max(worst["drop"], spec["y0"] - spec["y1"])
        worst["long"] = max(worst["long"], length)
        seconds = min(max(length / P["SPEED"], P["MIN_SECONDS"]), P["MAX_SECONDS"])
        lo, hi = worst["slide"]
        worst["slide"] = (min(lo, seconds), max(hi, seconds))
        if length / seconds > 95:
            fail("%s seed %d: the slide is %.0f studs in %.1f s, too fast to be calm" % (label, seed, length, seconds))

        # The pump room hangs under its terrace: its floor must stay out of the clouds.
        if pump_terrace is not None and pump_terrace < len(chosen):
            ch = chosen[pump_terrace]
            floor = ch["y"] + CAP_TOP - S["DECK_THICK"] - S["ROOM_DOWN"] - 1
            if floor < cloud_top + 5:
                fail("%s seed %d: the pump room's floor is at %.0f, in the clouds at %.0f"
                     % (label, seed, floor, cloud_top))
    if worst["steep"] > 42:
        fail("%s: the slide gets as steep as %.0f degrees" % (label, worst["steep"]))
    report[label] = worst

# ----- the landing, whatever the route
curtain = S["BASIN_D"] / 2 + 0.8
land_in, land_out = S["SLIDE_END_RADIUS"] - P["WIDE"] / 2, S["SLIDE_END_RADIUS"] + P["WIDE"] / 2
if land_out > S["FINAL_RADIUS"] - 10:
    fail("the slide ends %.0f from the middle, too near the final pool's rim at %.0f" % (land_out, S["FINAL_RADIUS"]))
if land_in < curtain + 10:
    fail("the slide ends %.0f from the middle, too near the tower's curtain at %.0f" % (land_in, curtain))
if S["SLIDE_TURNS"] >= 1:
    fail("the slide goes a full turn or more, so it passes under itself")
# THE SKIM (eighteenth pass): the sled carries on across the pool from where the trough runs out, along
# the way it was going. Tangent to the ring at worst, so it ends no further out than this, and it must
# still be in the water, clear of the rim.
skim = P.get("SKIM_SECONDS")
if skim is None:
    fail("SkyPath has no SKIM_SECONDS: the slide stops dead at the water instead of skimming across it")
else:
    reach = P["SPEED"] * skim / 2
    furthest = (S["SLIDE_END_RADIUS"] ** 2 + reach ** 2) ** 0.5 + P["WIDE"] / 2
    if furthest > S["FINAL_RADIUS"] - 8:
        fail("the skim runs %.0f studs on from the slide's end, out to %.0f from the middle: over the final "
             "pool's rim at %.0f" % (reach, furthest, S["FINAL_RADIUS"]))
for needle, why in (
    ("function SkyPath.skimFrame", "SkyPath cannot say where the sled is on the skim"),
    ("function SkyPath.skimEnd", "SkyPath cannot say where the skim stops"),
):
    if needle not in SKYPATH:
        fail(why)
if "local landing = SkyPath.skimEnd(spec)" not in SKY:
    fail("the server stands the rider where the slide ended, not where the skim did")
if "SkyPath.skimFrame(current.spec, s)" not in CLIENT:
    fail("the rider's client never draws the skim")
# THE CAMERA IS NEVER IN A CLOUD (the picture went white twice) and never on top of the rider.
for needle, why in (
    ('model:SetAttribute("CloudTop"', "the slide's camera is never told where the clouds are"),
):
    if needle not in SKY:
        fail(why)
# NOTHING ON THE SLIDE PASSES THROUGH THE RIDER (twentieth pass). The rods that hang it off the tower
# used to leave from the trough's centre line two studs up, which is where the rider sits; they leave
# from the wall's lip on the tower's side now. And the hoops' crowns clear a seated head.
if "local inner = frame * Vector3.new(side * (wide / 2 + 0.4), 2.2, 0)" not in SKY \
        or "local inner = frame * Vector3.new(0, 2.2, 0)" in SKY:
    fail("the slide's rods leave from the middle of the trough again, through anyone riding it")
hoop = re.search(r"math\.sin\(a2\) \* \(wide / 2 \+ ([\d.]+)\) \+ ([\d.]+), 0\)", SKY)
if not hoop or P["WIDE"] / 2 + float(hoop.group(1)) + float(hoop.group(2)) - 0.3 < P.get("SIT_HEIGHT", 1.6) + 5.5:
    fail("the slide's hoops come down on a seated rider's head")
# THE LIGHT IS NOT MILK (twentieth pass): no haze in the air, and the white cloud under everything does not
# fill every shadow.
sky_palette = LIGHT[LIGHT.find("skyPools = {"):]
sky_palette = sky_palette[:sky_palette.find("\n\t},")]
haze = re.search(r"\bhaze = ([\d.]+)", sky_palette)
diffuse = re.search(r"\bdiffuse = ([\d.]+)", sky_palette)
if not haze or float(haze.group(1)) > 0.1:
    fail("the skyPools palette has haze in the air again, a white film over the whole level")
if not diffuse or float(diffuse.group(1)) > 0.5:
    fail("the skyPools palette lights every surface from the white cloud again, and nothing has a shaded side")
# RUDY'S RECORD GOES ROUND.
if 'CollectionService:AddTag(spinning, "SkyTurntable")' not in SKY         or 'CollectionService:GetTagged("SkyTurntable")' not in CLIENT         or 'GetInstanceAddedSignal("SkyTurntable")' not in CLIENT:
    fail("Rudy's record does not go round")
# THE CLOUD SEA MOVES (nineteenth pass): mist banks rolling one way over the tops, wisps lifting.
for needle, why in (
    ('block(folder, "MistBank"', "the cloud sea is still again: no mist rolls over it"),
    ("mist.Acceleration = wind", "the mist does not drift with the wind"),
    ('wisp.Name = "Wisp"', "no wisps lift off the cloud tops"),
):
    if needle not in SKY:
        fail(why)
face = re.search(r"here \+ run \* ([\d.]+) \+ Vector3\.new\(0, ([\d.]+), 0\)", CLIENT)
if not face or float(face.group(1)) < 12:
    fail("the slide's face shot is back too close to the rider to see them")
if S["TOWER_ASIDE"] <= S["FINAL_RADIUS"] + S["WALK_W"]:
    fail("the tower stands %.0f to the side of the mouth, near enough that its final pool reaches the walkway"
         % S["TOWER_ASIDE"])

# ===================================================================== the ride

for needle, why in (
    ("SkyPath.rideFrame", "SkyPoolsService no longer puts the sled where the shared path says"),
    ("seat:Sit(humanoid)", "the rider is never sat in the sled, which is what the ride was missing"),
    ("SetNetworkOwner", "the sled is never handed to the rider's client, so the ride is replicated a frame "
                        "at a time from the server, which is what made it stutter"),
    ("if not driving[player] then", "the server does not stand back once the client is drawing the ride"),
    ("riding[player] and seat and not driving[player]", "the ride's remote takes a client's word without "
                                                        "checking it is that client's ride"),
):
    if needle not in SKY:
        fail(why)
for needle, why in (
    ("SkyPath.rideFrame", "SkyPoolsClient never draws the ride"),
    ("rideRemote:FireServer()", "the client never tells the server it has the sled"),
    ("AssemblyLinearVelocity = Vector3.zero", "the client lets gravity pull at the sled between frames"),
):
    if needle not in CLIENT:
        fail(why)
if 'ensureRemoteEvent(remoteEventsFolder, "SkyRide")' not in BOOT:
    fail("Bootstrap never makes the SkyRide remote, so no client can ever draw the ride")
for needle in ("function SkyPath.point", "function SkyPath.rideFrame", "function SkyPath.seconds"):
    if needle not in SKYPATH:
        fail("ReplicatedStorage/Shared/SkyPath.lua has no %s" % needle.split()[-1])
if P.get("SIT_HEIGHT", 0) <= 0:
    fail("the sled sits at or under the trough's floor")
if P["SPEED"] > 95:
    fail("the ride is set to %.0f studs a second, which is not a calm slide" % P["SPEED"])
# Up to half a minute since the slide became a scene to watch (the fifteenth pass slowed every ending
# to half speed); longer than that is a sit-down.
if P["MIN_SECONDS"] < 5 or P["MAX_SECONDS"] > 32 or P["MIN_SECONDS"] > P["MAX_SECONDS"]:
    fail("the ride is clamped to %.0f-%.0f seconds, which is either a drop or a sit-down"
         % (P["MIN_SECONDS"], P["MAX_SECONDS"]))

# ===================================================================== the wiring

marker = "if level.backdrop == \"skyPools\" then"
if marker not in BOOT:
    fail("Bootstrap never checks for the skyPools backdrop, so nothing builds the pools")
    sky_block = ""
else:
    # ONLY THE SKY POOLS BLOCK: up to the next section header, not the end of the level's setup. The
    # Sunken City's block after it stands the finish line down and finishes runs too, and read as one
    # it hid Sky Pools losing both.
    sky_block = BOOT[BOOT.index(marker):]
    ends = [at for at in (sky_block.find("\n\t-- ===== "), sky_block.find("-- THE MODE COMES FROM THE PADS")) if at > 0]
    sky_block = sky_block[:min(ends)]
for needle, why in (
    ("SkyPoolsService.build(levelInstance", "Bootstrap never builds the pools"),
    ("SkyPoolsService.attachSlide(", "Bootstrap never attaches the slide"),
    ("finishRunFor(player)", "the slide's arrival does not finish the run"),
    ("finishPart.CanTouch = false", "the old finish line is not stood down, so the finale deck ends the run"),
    ("if SkyPoolsService.clearWater then", "the terrain water is never cleared, so the next level starts "
                                          "with pools of water standing in its sky"),
    ("pcall(SkyPoolsService.clearWater)", "the teardown looks for clearWater without calling it"),
):
    if needle not in sky_block:
        fail(why)
kill = BOOT[BOOT.index("if hrp.Position.Y < killY"):]
kill = kill[:kill.index(" then")]
if "SkyPoolsService.ownsFall(player)" not in kill:
    fail("the kill plane does not exempt a slide rider, so the ride ends in the clouds")
if "skyPools = {" not in LIGHT:
    fail("LightingService has no skyPools palette")
if '[2] = { name = "Sky Pools"' not in UI:
    fail("UIService's finale banner for level 2 is not Sky Pools'")
# EVERY LEVEL ENDS IN ITS OWN LANGUAGE, and this is the one check that holds all four: the banner
# carries a motif per level and builds it.
for level, motif in ((1, "shore"), (2, "clouds"), (3, "caustics"), (4, "tiles")):
    if 'motif = "%s"' % motif not in UI:
        fail("UIService's completion banner has no %s motif for level %d" % (motif, level))
if "local function buildMotif" not in UI or "buildMotif(look)" not in UI:
    fail("UIService never builds the completion banner's motif, so every level ends the same way")
code = "\n".join(line.split("--", 1)[0] for line in SKY.splitlines())
if "PartType.Ball" in code:
    fail("SkyPoolsService uses Ball parts; a ball cannot be flat, and round clouds were City Shore's eggs")
if "Enum.Material.Neon" in code:
    fail("SkyPoolsService uses Neon; this project lights nothing with fake light")
if ("function SkyPoolsService.heights" not in SKY or "cloudTop - CLOUD_THICK - FINAL_BELOW" not in SKY
        or "destroyY + POOL_ABOVE_DESTROY" not in SKY):
    fail("SkyPoolsService.heights no longer matches the formula skypools_layout.py restates")
# The water is filled and taken away again, and its look is put back with it.
for needle, why in (
    ("Enum.Material.Water", "nothing fills the pools with water any more"),
    ("Enum.Material.Air", "clearWater does not take the water out again"),
    ("terrainWas[name]", "the terrain's own look is changed without being remembered"),
):
    if needle not in SKY:
        fail(why)

# ===================================================================== the sky

balloon = re.search(r"local height = startY \+ rng:NextNumber\((\d+), (\d+)\)", SKY)
scenery = re.search(r"sceneryPools\(model, towerCentre, radius, h\.cloudTop \+ \d+, startY \+ (\d+), h\.seaY", SKY)
if not balloon or not scenery:
    fail("this check can no longer read the balloons' heights or the scenery pools'")
else:
    basket_bottom = float(balloon.group(1)) - 26 - 1.7
    scenery_top = float(scenery.group(1)) + 9.5
    if basket_bottom < scenery_top + 5:
        fail("a balloon's basket can pass through a scenery pool's parasol")
flock_specs = re.findall(r"\{ (\d+), top ([+-]) (\d+), (-?[\d.]+) \}", CLIENT)
if len(flock_specs) != 2:
    fail("this check can no longer read the gull flocks")
else:
    for radius_text, sign, offset, _ in flock_specs:
        flock_r = float(radius_text)
        flock_low = (float(offset) if sign == "+" else -float(offset)) - 3 - 1.5
        if flock_r < S["BASIN_D"] / 2 + 5:
            fail("a flock of gulls flies through the fountain's basin")
        for label, count in RUNS:
            for seed in range(60):
                radius, chunks, finish_y = lay(count, seed)
                top_y = heights(BASE_SURFACE_Y, kill_y(chunks))[3]
                spec = slide_spec(radius, chunks, finish_y)
                for i in range(1, 101):
                    at, y, r = slide_point(spec, i / 100)
                    reach = r - S["TOWER_D"] / 2
                    if reach > 2 and r > flock_r > S["TOWER_D"] / 2:
                        rod_top = min(y + 2.2 + reach * 0.45, top_y - 20)
                        high = (y + 2.2) + (rod_top - (y + 2.2)) * (r - flock_r) / (r - S["TOWER_D"] / 2)
                        if high > top_y + flock_low - 3:
                            fail("%s seed %d: a slide rod reaches the gulls at radius %.0f" % (label, seed, flock_r))
                            break

# A tag is read if ANY other file looks for it: the pools' client, or since the seventeenth pass the
# camera (Ambience, faded out by Cinema) and the story (StorySpot, built on by StoryService).
OTHERS = "\n".join(path.read_text(encoding="utf-8") for path in (ROOT / "src").rglob("*.lua")
                   if path.name != "SkyPoolsService.lua")
for tag in set(re.findall(r'AddTag\([^,]+,\s*"(\w+)"\)', SKY)):
    if tag == "SkySled":
        continue  # the sled is found by the remote that hands it over, not by its tag
    if '"%s"' % tag not in OTHERS:
        fail("SkyPoolsService tags %s and nothing ever looks for it" % tag)
if '"SkyPoolsClient"' not in CLIENT_BOOT:
    fail("the client Bootstrap never starts SkyPoolsClient, so the pools never splash")

# NO SEE-THROUGH GLASS. A transparent Glass part leaves out everything transparent behind it, so the
# pools and the falls hid the clouds and the jelly and soda chunks behind them ("the soda chunk
# disappears from a certain angle"). The pool lights (opaque) and the invisible markers may stay Glass.
SKY_SOURCE = (SRC / "Server" / "Services" / "SkyPoolsService.lua").read_text(encoding="utf-8").split("\n")
for index_, line_ in enumerate(SKY_SOURCE):
    if "Enum.Material.Glass" in line_:
        context_ = "\n".join(SKY_SOURCE[max(0, index_ - 3):index_ + 1])
        if not any(name_ in context_ for name_ in ("PoolLight", "FallMist", "FallBoil")):
            fail("SkyPoolsService line %d makes see-through water of Glass, which hides the chunks behind it" % (index_ + 1))
# AND THE SODA IS NOT GLASS, or it mirrors the open sky at a low angle and washes out to nothing.
APPEAR = (SRC / "Shared" / "MaterialAppearance.lua").read_text(encoding="utf-8")
soda_ = re.search(r"\tJelloSoda = \{(.*?)\n\t\}", APPEAR, re.S)
if not soda_ or "Enum.Material.Glass" in soda_.group(1):
    fail("JelloSoda is Glass again, so against Sky Pools' sky it vanishes from a low angle")

# THE STORM BY THE SLIDE (SkyPoolsClient): near the mouth the clouds round the tower darken and the light drops a
# little, eased over seconds and written in small steps, never dark; it clears under the clouds and is gone at
# once off the level; lightning is a real light, soft and brief, only at the height of it.
storm_ = CLIENT[CLIENT.find("-- ===== THE STORM BY THE SLIDE ====="):CLIENT.find("local function step()")]
def storm_number_(name_):
    found_ = re.search(r"^local %s = (-?[0-9.]+)" % name_, CLIENT, re.M)
    return float(found_.group(1)) if found_ else None
from_, full_ = storm_number_("STORM_FROM"), storm_number_("STORM_FULL")
if from_ is None or full_ is None or not (from_ > full_ > 0):
    fail("the storm does not build between two distances from the slide (STORM_FROM > STORM_FULL > 0)")
ease_ = storm_number_("STORM_EASE")
if ease_ is None or not (0 < ease_ <= 1):
    fail("the storm does not ease in over seconds (STORM_EASE between 0 and 1)")
darkest_ = storm_number_("STORM_DARKEST")
if darkest_ is None or darkest_ > 0.6:
    fail("the storm takes the clouds too far toward grey (STORM_DARKEST over 0.6)")
grey_ = re.search(r"local STORM_GREY = Color3\.fromRGB\((\d+), (\d+), (\d+)\)", CLIENT)
if not grey_ or min(int(v_) for v_ in grey_.groups()) < 100:
    fail("the storm grey is too dark for clouds in daylight")
bright_ = re.search(r"cc\.Brightness = -([0-9.]+) \* s", storm_)
if not bright_ or float(bright_.group(1)) > 0.08:
    fail("the storm drops the light more than a little (Brightness under -0.08)")
lightning_ = storm_number_("LIGHTNING_BRIGHT")
if lightning_ is None or lightning_ > 1.5:
    fail("the lightning is brighter than a soft flash in the clouds (LIGHTNING_BRIGHT over 1.5)")
for needle_, why_ in (
    ("storm += (target - storm) * math.min(1, STORM_EASE * dt)", "the storm jumps instead of easing"),
    ("if key == stormWritten then\n\t\treturn", "the storm is written every frame, not only when it moves"),
    ("target *= math.clamp((root.Position.Y - (bottom - 30)) / 30, 0, 1)", "the storm does not clear under the clouds"),
    ('Players.LocalPlayer:GetAttribute("InLevel") == "skyPools"', "the storm is not only on Sky Pools"),
    ("if stormShade then\n\t\t\tstormGone()", "leaving the level leaves the screen shaded"),
    ("\t\tpaintClouds(0)\n", "the clouds are not given back their colours when the storm goes"),
    ("cloudBase[item] = base", "each cloud's own colour is not kept, so it cannot ease back"),
    ('Instance.new("PointLight")', "the lightning is not a real light"),
    ("light.Shadows = false", "the lightning casts shadows (costly, and harsh)"),
    ("if storm < 0.6 or now < nextFlash", "the lightning is not kept to the height of the storm"),
    ("spot:Destroy()", "a lightning light is left behind"),
):
    if needle_ not in storm_:
        fail("SkyPoolsClient: " + why_)
if "Neon" in storm_:
    fail("SkyPoolsClient: the storm fakes light with Neon")
if "\tmoveFalls(now)\n\tmoveStorm(now)\n" not in CLIENT:
    fail("SkyPoolsClient: the storm is never moved")
if 'CollectionService:GetInstanceAddedSignal("SkyPoolsLevel"):Connect(stormFor)' not in CLIENT:
    fail("SkyPoolsClient: the storm never finds the level")

# ===================================================================== the slide's shots
#
# WHERE THE RIDE IS GOING (2026-10-16): the deck is only about twenty studs over the cloud tops, so the old "under
# the clouds" shot held from the push off until they came out: nine seconds of the bottom of a slide with nobody on
# it. Restated here from SkyPoolsClient's own numbers and replayed on laid runs: the track sees the slide on ahead,
# the plunge holds over the cloud tops, the wide shot under the cloud sea frames where the slide comes out AND the
# pool it lands in, and the camera waits under the exit only a moment before they burst through. No shot is a flash,
# no eye is ever inside the cloud (twice the whole picture went white).
def lua_num(text, pattern, label):
    found = re.search(pattern, text, re.M)
    if not found:
        fail("this check can no longer read %s" % label)
        return None
    return [float(g) for g in found.groups()]


shot_nums = {
    "holds": lua_num(CLIENT, r"^local PLUNGE_HOLD = ([\d.]+).*\n^local BURST_LEAD = ([\d.]+).*\n^local BURST_HOLD = ([\d.]+)",
                     "how long the plunge, the wait under the cloud and the burst are held"),
    "marks": lua_num(CLIENT, r"local plunge = below\(cloudTop \+ ([\d.]+), 0\)\n\tlocal out = below\(cloudBottom - ([\d.]+), plunge\)",
                     "where the ride goes into the cloud and comes out"),
    "track": lua_num(CLIENT, r"local eye = here \+ out \* ([\d.]+) \+ Vector3\.new\(0, ([\d.]+), 0\) - flat \* ([\d.]+)\n",
                     "the track's eye"),
    "plunge": lua_num(CLIENT, r"Cinema\.clear\(here - flat \* ([\d.]+) \+ out \* ([\d.]+) \+ Vector3\.new\(0, ([\d.]+), 0\), here, ignore\)",
                      "the plunge's eye"),
    "below": lua_num(CLIENT, r"local eye = mid \+ away \* \(([\d.]+) - ([\d.]+) \* drift\) \+ Vector3\.new\(0, ([\d.]+) \+ ([\d.]+) \* drift, 0\)",
                     "the wide shot's eye"),
    "aim": lua_num(CLIENT, r"Cinema\.point\(CFrame\.lookAt\(eye, mid:Lerp\(marks\.outAt, ([\d.]+)\)\), ([\d.]+), true\)",
                   "where the wide shot looks"),
    "burst": lua_num(CLIENT, r"marks\.outAt \+ marks\.outRun \* ([\d.]+) \+ away \* ([\d.]+) \+ Vector3\.new\(0, -([\d.]+), 0\)",
                     "the eye that waits under the cloud"),
    "path": lua_num(SKYPATH, r"^SkyPath\.SPEED = ([\d.]+)\n^SkyPath\.MIN_SECONDS, SkyPath\.MAX_SECONDS = ([\d.]+), ([\d.]+)\n"
                             r"^SkyPath\.RAMP = ([\d.]+)", "the ride's speed and bounds"),
}
for needle, why in (
    ("pcall(scene.markClouds, ride :: Ride)", "when the ride goes into the cloud and comes out is never worked out"),
    ("\telseif marks and u < marks.plunge then\n", "the track does not run until they reach the cloud"),
    ("\t\tif since < PLUNGE_HOLD and left > BURST_LEAD then\n", "the plunge is not held over the cloud tops"),
    ('\t\telseif left > BURST_LEAD and (scene.shot == "below" or left > BURST_LEAD + 1) then\n',
     "the way down is not shown while they are in the cloud"),
    ("\telseif marks and (u - marks.out) * current.seconds < BURST_HOLD then\n", "the camera does not turn after them"),
    ("\t\tCinema.point(CFrame.lookAt(scene.eye :: Vector3, here + Vector3.new(0, 1, 0)), 60, true)\n",
     "the camera does not turn after them once they are out of the cloud"),
    ("\t\t\tCinema.impact(0.7)\n", "bursting out of the cloud is not hit"),
    ("\t\t\tscene.puff(here)\n", "no puff where they come out of the cloud"),
    ("CFrame.lookAt(eye, here:Lerp(far, 0.3)", "the track looks only at the rider, never at where they are going"),
):
    if needle not in CLIENT:
        fail("SkyPoolsClient: " + why)
if 'scene.cutTo("under")' in CLIENT:
    fail("SkyPoolsClient: the old shot of the bottom of the slide, waiting from the push off, is back")
if all(shot_nums.values()):
    plunge_hold, burst_lead, burst_hold = shot_nums["holds"]
    over_top, under_bottom = shot_nums["marks"]
    t_out, t_up, t_back = shot_nums["track"]
    p_back, p_out, p_up = shot_nums["plunge"]
    b_far, b_in, b_up, b_rise = shot_nums["below"]
    b_aim, b_fov = shot_nums["aim"]
    w_run, w_away, w_down = shot_nums["burst"]
    speed, min_s, max_s, ramp = shot_nums["path"]
    samples = 200

    def ride_share(u):
        norm = 1 - ramp / 2
        return (u * u / (2 * ramp)) / norm if u < ramp else (u - ramp / 2) / norm

    def flat_unit(x, z):
        m = math.hypot(x, z)
        return (x / m, z / m) if m > 0.01 else (1.0, 0.0)

    shot_worst = {"wait": 0.0, "short": (1e9, ""), "hidden": 0.0}
    for label, count in RUNS:
        for seed in range(0, 300, 25):
            radius, chunks, finish_y = lay(count, seed)
            cloud_top, pool_y, sea_y, top_y = heights(BASE_SURFACE_Y, kill_y(chunks))
            spec = slide_spec(radius, chunks, finish_y)
            ctop, cbot = cloud_top + 8, cloud_top - S["CLOUD_THICK"] * 1.3
            cx, cz = spec["centre"]

            def on_slide(f):
                (x, z), y, _ = slide_point(spec, f)
                return (x, y, z)
            dist = [0.0]
            for i in range(1, samples + 1):
                dist.append(dist[-1] + math.dist(on_slide(i / samples), on_slide((i - 1) / samples)))
            seconds = min(max_s, max(min_s, dist[-1] / speed))

            def ride_at(u):
                t = min(1, max(0, ride_share(min(1, max(0, u))))) * dist[-1]
                lo = 0
                while lo < samples - 1 and dist[lo + 1] < t:
                    lo += 1
                span = dist[lo + 1] - dist[lo]
                return on_slide((lo + ((t - dist[lo]) / span if span > 0 else 0)) / samples)

            def first_below(y, start):
                u = start
                while u < 1:
                    if ride_at(u)[1] < y:
                        return u
                    u += 0.002
                return 1
            u_in = first_below(ctop + over_top, 0)
            u_out = first_below(cbot - under_bottom, u_in)
            if u_out >= 1:
                fail("%s seed %d: the ride never comes out under the cloud" % (label, seed))
                continue
            shot, began, shots = None, 0.0, []
            step = 1 / 20
            t = 0.0
            while t < seconds:
                u = t / seconds
                here = ride_at(u)
                ox, oz = flat_unit(here[0] - cx, here[2] - cz)
                if u < 0.1:
                    name = "push"
                elif u < u_in:
                    name = "track"
                    if here[1] + t_up < ctop + 4:
                        fail("%s seed %d: the track's eye goes down into the cloud tops" % (label, seed))
                elif u < u_out:
                    left, since = (u_out - u) * seconds, (u - u_in) * seconds
                    if since < plunge_hold and left > burst_lead:
                        name = "plunge"
                        if shot != "plunge" and here[1] + p_up < ctop + 4:
                            fail("%s seed %d: the plunge is watched from inside the cloud" % (label, seed))
                    elif left > burst_lead and (shot == "below" or left > burst_lead + 1):
                        name = "below"
                    else:
                        name = "wait"
                elif (u - u_out) * seconds < burst_hold:
                    name = "burst"
                elif u < 0.86:
                    name = "face"
                else:
                    name = "pool"
                if name != shot:
                    if shot is not None:
                        shots.append((shot, t - began))
                    shot, began = name, t
                t += step
            shots.append((shot, seconds - began))
            for name, length in shots:
                if name == "wait":
                    shot_worst["wait"] = max(shot_worst["wait"], length)
                if name != "pool":
                    if length < 0.8:
                        fail("%s seed %d: the %s shot is a flash (%.2f s)" % (label, seed, name, length))
                    shot_worst["short"] = min(shot_worst["short"], (length, name))
            # The camera waiting on the empty bottom of the slide: a moment, never the ride.
            waited = sum(length for name, length in shots if name == "wait")
            if waited > burst_lead + 1.2:
                fail("%s seed %d: the camera waits %.1f s under the cloud on an empty slide" % (label, seed, waited))
            if [name for name, _ in shots][:2] != ["push", "track"] or "below" not in [name for name, _ in shots]:
                fail("%s seed %d: the shots run %s" % (label, seed, [name for name, _ in shots]))
            # The eyes under the cloud are under it.
            out_at = ride_at(u_out)
            onward = ride_at(min(1, u_out + 0.02))
            rx, rz = flat_unit(onward[0] - out_at[0], onward[2] - out_at[2])
            ax, az = flat_unit(out_at[0] - cx, out_at[2] - cz)
            if out_at[1] - w_down > cbot - 10:
                fail("%s seed %d: the eye waiting for them to come out is inside the cloud" % (label, seed))
            landing = on_slide(1)
            mid = tuple((a + b) / 2 for a, b in zip(out_at, landing))
            mx, mz = flat_unit(mid[0] - cx, mid[2] - cz)
            target = tuple(a + (b - a) * b_aim for a, b in zip(mid, out_at))
            tv = math.tan(math.radians(b_fov / 2))
            for drift in (0.0, 1.0):
                far = b_far - b_in * drift
                eye = (mid[0] + mx * far, min(mid[1] + b_up + b_rise * drift, cbot - 16), mid[2] + mz * far)
                if math.hypot(eye[0] - cx, eye[2] - cz) < S["FINAL_RADIUS"] + 15:
                    fail("%s seed %d: the wide shot's eye is over the pool, not out in the open" % (label, seed))
                fx, fy, fz = (target[0] - eye[0], target[1] - eye[1], target[2] - eye[2])
                m = math.sqrt(fx * fx + fy * fy + fz * fz)
                fx, fy, fz = fx / m, fy / m, fz / m
                rgx, rgz = flat_unit(-fz, fx)
                # up = right x forward, with right = (rgx, 0, rgz)
                upx, upy, upz = (-rgz * fy, rgz * fx - rgx * fz, rgx * fy)
                for what, p in (("where the slide comes out", out_at), ("the pool it lands in", landing),
                                ("the cloud over the exit", (out_at[0], cbot, out_at[2]))):
                    rel = (p[0] - eye[0], p[1] - eye[1], p[2] - eye[2])
                    z = rel[0] * fx + rel[1] * fy + rel[2] * fz
                    x = rel[0] * rgx + rel[2] * rgz
                    y = rel[0] * upx + rel[1] * upy + rel[2] * upz
                    if z <= 0 or abs(y / z) > tv * 0.97 or abs(x / z) > tv * 16 / 9 * 0.97:
                        fail("%s seed %d: the wide shot under the cloud does not frame %s" % (label, seed, what))
    print("slide shots: the camera waits under the cloud %.1f s at most, the shortest shot is the %s (%.1f s)"
          % (shot_worst["wait"], shot_worst["short"][1], shot_worst["short"][0]))

# ===================================================================== report

for label, worst in report.items():
    nearest = "nothing ahead of it" if worst["mouth"] > 1e8 else "%.0f studs clear" % worst["mouth"]
    print("%-6s route keeps %4.0f studs from itself, slide %5.0f studs, drop %4.0f, %.1f-%.1f s, steepest %2.0f deg, "
          "mouth %s"
          % (label, worst["apart"], worst["long"], worst["drop"], worst["slide"][0], worst["slide"][1],
             worst["steep"], nearest))
# THE FALLS BREAK UP (the hundred-and-first pass): a fall's sheet goes down VEIL_REACH studs at most, thinning as it
# goes, and its streaks and mist carry on; a sheet from a pool to the clouds is a thin white line through everything.
SKY_TEXT = "\n".join(SKY_SOURCE)
reach = re.search(r"^local VEIL_REACH = ([\d.]+)", SKY_TEXT, re.M)
if not reach or float(reach.group(1)) > 60:
    fail("SkyPoolsService: a fall's sheet reaches further than 60 studs (a white line to the clouds)")
for needle, why in (
    ("local reach = math.min(height, VEIL_REACH)", "a fall's sheet goes all the way down"),
    ("local alpha = veil.alpha + (1 - veil.alpha) * thin * 0.92", "a long fall's sheet does not thin as it falls"),
    ('sheet:SetAttribute("Alpha", alpha)', "the shimmer puts a long fall's sheet back to solid"),
):
    if needle not in SKY_TEXT:
        fail("SkyPoolsService: " + why)
if problems:
    print("\nPROBLEMS:")
    for p in dict.fromkeys(problems):
        print("  " + p)
    sys.exit(1)
print("sky pools: the meander is gentle and never meets itself, terraces stand up and hold together, the slide "
      "hits nothing and lands in the pool, the ride is the rider's, heights in order, wiring present.")
