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
for label, count in RUNS:
    worst = {"steep": 0.0, "slide": (1e9, 0.0), "apart": 1e9, "drop": 0.0, "long": 0.0, "mouth": 1e9}
    for seed in range(300):
        radius, chunks, finish_y = lay(count, seed)
        tops = [ch["y"] + (CAP_TOP if ch["id"] == "S1_Straight" else 2) for ch in chunks]
        cloud_top, pool_y, sea_y, top_y = heights(BASE_SURFACE_Y, kill_y(chunks))

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
if P["MIN_SECONDS"] < 5 or P["MAX_SECONDS"] > 25 or P["MIN_SECONDS"] > P["MAX_SECONDS"]:
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

for tag in set(re.findall(r'AddTag\([^,]+,\s*"(\w+)"\)', SKY)):
    if tag == "SkySled":
        continue  # the sled is found by the remote that hands it over, not by its tag
    if '"%s"' % tag not in CLIENT:
        fail("SkyPoolsService tags %s and SkyPoolsClient never looks for it" % tag)
if '"SkyPoolsClient"' not in CLIENT_BOOT:
    fail("the client Bootstrap never starts SkyPoolsClient, so the pools never splash")

# ===================================================================== report

for label, worst in report.items():
    nearest = "nothing ahead of it" if worst["mouth"] > 1e8 else "%.0f studs clear" % worst["mouth"]
    print("%-6s route keeps %4.0f studs from itself, slide %5.0f studs, drop %4.0f, %.1f-%.1f s, steepest %2.0f deg, "
          "mouth %s"
          % (label, worst["apart"], worst["long"], worst["drop"], worst["slide"][0], worst["slide"][1],
             worst["steep"], nearest))
if problems:
    print("\nPROBLEMS:")
    for p in dict.fromkeys(problems):
        print("  " + p)
    sys.exit(1)
print("sky pools: the meander is gentle and never meets itself, terraces stand up and hold together, the slide "
      "hits nothing and lands in the pool, the ride is the rider's, heights in order, wiring present.")
