"""Sky Pools (Level 2): holds the level's shape to what SkyPoolsService assumes.

Run with plain Python from the project root:  python blender/check_skypools.py

SkyPoolsService builds terraces, a slide, a tower and a cloud sea round a ring LevelService lays
from random draws, so nothing about it can be looked at in one fixed layout. This lays the ring the
way LevelService does (skypools_layout.py) -- the same template, pool, radius formula and steps,
DOWN -- for short, medium and long runs over many seeds, and checks every one:

  THE TERRACES CLEAR THEIR NEIGHBOURS. A terrace starts NECK studs out from the checkpoint chunk's
  cap edge and is longer than that chunk, so it overhangs the chunks either side; none of them may
  reach out that far.
  THE ROUTE NEVER COMES ROUND ONTO ITSELF, and the finale deck stops short of the start.
  THE SLIDE HITS NOTHING. Its trough and its rods keep clear of every chunk, terrace and column, in
  plan or by height; it clears the final pool's rim; it lands inside the pool and outside the
  tower's water curtain; it is never steeper than a slide should be, nor too fast to be calm.
  THE HEIGHTS ARE IN ORDER: walkway, clouds, the cloud sea's underside, the final pool, the sea.
  AND THE WIRING IS THERE: Bootstrap builds it, stands the old finish line down, exempts a rider
  from the kill plane; the palette and the finale banner exist; clouds are not Ball parts.

Exits non-zero on any failure.
"""
import math
import sys

from skypools_layout import (BASE_SURFACE_Y, BY_CATEGORY, C, CAP_HALF, CAP_TOP, CONTRACTS, DESCENDS, DESTROY_Y,
                             GAP, LAYOUTS, LEVEL2, POOL_IDS, RING, ROOT, RUNS, S, SKY, chosen_terraces,
                             chunk_frame, declared_category, finish_frame, heights, kill_y, lay,
                             slide_point, slide_spec, terrace_frame, xmax)

SRC = ROOT / "src"
BOOT = (SRC / "Server" / "Bootstrap.server.lua").read_text(encoding="utf-8")
LIGHT = (SRC / "Server" / "Services" / "LightingService.lua").read_text(encoding="utf-8")
UI = (SRC / "Client" / "Services" / "UIService.lua").read_text(encoding="utf-8")

problems = []


def fail(message):
    problems.append(message)


# ===================================================================== the definition

if not RING:
    print("FAIL: Level2 has no ring")
    sys.exit(1)
if not DESCENDS:
    fail("Level2's ring does not descend; Sky Pools goes DOWN toward its clouds")
for field, want in (("backdrop", "skyPools"), ("finale", "slide")):
    if '%s = "%s"' % (field, want) not in LEVEL2:
        fail("Level2 has no %s = \"%s\"" % (field, want))
for cid in POOL_IDS:
    if declared_category(cid) is None:
        fail("%s has no category this check can read in ChunkDefinitions" % cid)

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


# ===================================================================== laying the ring

def rect(origin, out, tan, x0, x1, z0, z1, y0, y1, name):
    """A box: a rectangle in plan in some frame, with a height range."""
    return {"o": origin, "out": out, "tan": tan, "x": (x0, x1), "z": (z0, z1), "y": (y0, y1), "name": name}


def inside(r, point, pad):
    dx, dz = point[0] - r["o"][0], point[1] - r["o"][1]
    x, z = dx * r["out"][0] + dz * r["out"][1], dx * r["tan"][0] + dz * r["tan"][1]
    return r["x"][0] - pad <= x <= r["x"][1] + pad and r["z"][0] - pad <= z <= r["z"][1] + pad


report = {}
for label, count in RUNS:
    worst = {"span": 0.0, "steep": 0.0, "slide": (1e9, 0.0), "clear": 1e9, "radius": None, "drop": 0.0}
    for seed in range(300):
        radius, chunks, finish_y = lay(count, seed)
        worst["radius"] = radius
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

        # ----- things the slide must miss
        obstacles = []
        for ch in chunks:
            origin, out, tan = chunk_frame(radius, ch)
            reach = xmax(ch["id"])
            obstacles.append(rect(origin, out, tan, -reach, reach, 0, ch["length"], ch["y"] - 6,
                                  ch["y"] + max(0.0, ch["rise"]) + 4, "chunk %d" % ch["index"]))

        def columns(frame_origin, out, along, points, top, name):
            """Columns under a deck, from the deck's underside to the sea."""
            half_d = S["COLUMN_D"] / 2
            for x, z in points:
                px = frame_origin[0] + out[0] * x + along[0] * z
                pz = frame_origin[1] + out[1] * x + along[1] * z
                obstacles.append(rect((px, pz), out, along, -half_d, half_d, -half_d, half_d, sea_y, top,
                                      name + " column"))

        def terrace_obstacles(frame_origin, out, along, x0, wide, long, top, name, neck=0.0):
            """A terrace as SkyPoolsService.terrace lays it: the deck, what stands on it, its columns."""
            lz = long / 2
            obstacles.append(rect(frame_origin, out, along, x0 - neck, x0 + wide, -lz, lz,
                                  top - max(S["DECK_THICK"], S["NECK_THICK"] if neck else 0), top + 12, name))
            x1 = x0 + wide
            columns(frame_origin, out, along, [(x0 + 5, -lz + 5), (x0 + 5, lz - 5), (x1 - 5, -lz + 5),
                                               (x1 - 5, lz - 5)], top - S["DECK_THICK"], name)

        for ch in chosen_terraces(chunks):
            edge, out, along = terrace_frame(radius, ch)
            terrace_obstacles(edge, out, along, S["NECK"], S["TERRACE_W"], S["TERRACE_L"], ch["y"] + CAP_TOP,
                              "terrace at chunk %d" % ch["index"], neck=S["NECK"])
        # The finale deck and its terrace, straight on from the last chunk, as finaleDeck lays them.
        finish, out, tan = finish_frame(radius, chunks)
        walk_w, walk_l = S["WALK_W"], S["WALK_L"]
        deck_top = finish_y + CAP_TOP
        obstacles.append(rect(finish, out, tan, -walk_w / 2, walk_w / 2, 0, walk_l - 0.5,
                              deck_top - S["DECK_THICK"], deck_top + 14, "finale walkway"))
        columns(finish, out, tan, [(-walk_w / 2 + 4, 4), (-walk_w / 2 + 4, walk_l - 4)], deck_top - S["DECK_THICK"],
                "finale walkway")
        side = (finish[0] + out[0] * walk_w / 2 + tan[0] * walk_l / 2,
                finish[1] + out[1] * walk_w / 2 + tan[1] * walk_l / 2)
        terrace_obstacles(side, out, tan, 0, 34, walk_l, deck_top, "finale terrace")

        # ----- the route does not come round onto itself
        last = chunks[-1]
        span = (last["angle"] + (last["length"] + walk_l) / radius) / (2 * math.pi)
        worst["span"] = max(worst["span"], span)
        clear_studs = (1 - span) * 2 * math.pi * radius
        worst["clear"] = min(worst["clear"], clear_studs)
        if clear_studs < 40 + S["TERRACE_L"] / 2:
            fail("%s seed %d: the finale deck ends %.0f studs short of the start going round" % (label, seed, clear_studs))

        # ----- the slide
        spec = slide_spec(radius, chunks, finish_y)
        samples = 600
        length = 0.0
        prev = None
        half = S["SLIDE_WIDE"] / 2 + 0.8
        for i in range(samples + 1):
            f = i / samples
            plan, y, r = slide_point(spec, f)
            if prev:
                run = math.hypot(plan[0] - prev[0][0], plan[1] - prev[0][1])
                length += math.hypot(run, y - prev[1])
                if run > 0:
                    worst["steep"] = max(worst["steep"], math.degrees(math.atan2(prev[1] - y, run)))
            prev = (plan, y)
            if f < 0.02:
                continue  # the mouth, which is meant to meet the finale deck
            for ob in obstacles:
                if inside(ob, plan, half) and ob["y"][0] - 3 < y + 2.2 and y - 1.2 < ob["y"][1]:
                    fail("%s seed %d: the slide at %.2f runs into the %s" % (label, seed, f, ob["name"]))
                    break
            # Its rods climb inward from here to the tower: they must pass under anything above.
            reach = r - S["TOWER_D"] / 2
            if reach > 2:
                rod_top = min(y + 2.2 + reach * 0.45, top_y - 20)
                for ob in obstacles:
                    if ob["name"].startswith("chunk") and inside(ob, plan, 2) and rod_top > ob["y"][0] - 3:
                        fail("%s seed %d: a slide rod at %.2f climbs into %s" % (label, seed, f, ob["name"]))
                        break
            # Over the final pool's rim, clear of it.
            if abs(r - (S["FINAL_RADIUS"] + 1.5)) < half + 1.5:
                rim_top = pool_y - S["FINAL_DEEP"] / 2 - 0.2 + (S["FINAL_DEEP"] + 3.6) / 2
                if y - 1.2 < rim_top + 2:
                    fail("%s seed %d: the slide meets the final pool's rim" % (label, seed))
        worst["drop"] = max(worst["drop"], spec["y0"] - spec["y1"])
        seconds = min(max(length / S["SLIDE_SPEED"], S["SLIDE_MIN_SECONDS"]), S["SLIDE_MAX_SECONDS"])
        lo, hi = worst["slide"]
        worst["slide"] = (min(lo, seconds), max(hi, seconds))
        if length / seconds > 95:
            fail("%s seed %d: the slide is %.0f studs in %.1f s, too fast to be calm" % (label, seed, length, seconds))
    if worst["steep"] > 42:
        fail("%s: the slide gets as steep as %.0f degrees" % (label, worst["steep"]))
    report[label] = worst

# ----- the landing, whatever the ring
curtain = S["BASIN_D"] / 2 + 0.8
land_in, land_out = S["SLIDE_END_RADIUS"] - S["SLIDE_WIDE"] / 2, S["SLIDE_END_RADIUS"] + S["SLIDE_WIDE"] / 2
if land_out > S["FINAL_RADIUS"] - 10:
    fail("the slide ends %.0f from the middle, too near the final pool's rim at %.0f" % (land_out, S["FINAL_RADIUS"]))
if land_in < curtain + 10:
    fail("the slide ends %.0f from the middle, too near the tower's curtain at %.0f" % (land_in, curtain))
if S["SLIDE_TURNS"] >= 1:
    fail("the slide goes a full turn or more, so it passes under itself")

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
code = "\n".join(line.split("--", 1)[0] for line in SKY.splitlines())
if "PartType.Ball" in code:
    fail("SkyPoolsService uses Ball parts; a ball cannot be flat, and round clouds were City Shore's eggs")
if "Enum.Material.Neon" in code:
    fail("SkyPoolsService uses Neon; this project lights nothing with fake light")
if ("function SkyPoolsService.heights" not in SKY or "cloudTop - CLOUD_THICK - FINAL_BELOW" not in SKY
        or "destroyY + POOL_ABOVE_DESTROY" not in SKY):
    fail("SkyPoolsService.heights no longer matches the formula skypools_layout.py restates")

# ===================================================================== the pump room and the toys

import re  # noqa: E402

lz = S["TERRACE_L"] / 2
x0 = S["NECK"]
px0 = x0 + S["TERRACE_W"] * 0.55 - S["POOL_W"] / 2
px1 = px0 + S["POOL_W"]
pz = S["POOL_L"] / 2
inner_x = (x0 + px0) / 2
hatch = (x0 + S["HATCH_FROM"], x0 + S["HATCH_FROM"] + S["HATCH"], S["HATCH_Z"], S["HATCH_Z"] + S["HATCH"])
room = (x0 + 0.5, min(px1 - 2, x0 + S["ROOM_LONG"]), S["ROOM_Z0"], S["ROOM_Z1"])
column_z = lz - 5
if room[2] < -column_z + S["COLUMN_D"] / 2 + 0.5 or room[3] > column_z - S["COLUMN_D"] / 2 - 0.5:
    fail("the pump room's walls reach the terrace's columns at z +-%.0f" % column_z)
if not (room[0] + 0.8 <= hatch[0] and hatch[1] <= room[1] - 0.8 and room[2] + 0.8 <= hatch[2] and hatch[3] <= room[3] - 0.8):
    fail("the pump room's hatch is not over the room")
if not (x0 <= hatch[0] and hatch[1] <= px0):
    fail("the pump room's hatch is not in the terrace's inner strip")


def overlaps(a, b, margin):
    return a[0] < b[1] + margin and b[0] < a[1] + margin and a[2] < b[3] + margin and b[2] < a[3] + margin


# What stands on the inner deck for each dressing, as (x0, x1, z0, z1) in the terrace's frame.
footprints = {
    "loungers": [(inner_x - 3.1, inner_x + 3.1, z - 1.3, z + 1.3) for z in (-lz * 0.45, lz * 0.45)],
    "parasol": [(inner_x - 1.1, inner_x + 1.1, -1.1, 1.1)],
    "board": [(px0 - 4.5, px0 + 9, -pz * 0.5 - 1.5, -pz * 0.5 + 1.5)],
    "ladder": [(px0 + 0.2, px0 + 1, -1.4, 1.4)],
    "towel": [(px0 - 1, px0 + 5, pz, pz + 5.3)],
}
dressing_block = SKY[SKY.index("local dressings = {"):]
dressing_block = dressing_block[:dressing_block.index("\n\t}")]
with_room = [re.findall(r'"(\w+)"', line) for line in dressing_block.splitlines() if '"pumproom"' in line]
if not with_room:
    fail("no terrace has the pump room")
for dressing in with_room:
    for item in dressing:
        for box in footprints.get(item, []):
            if overlaps(box, hatch, 0.3):
                fail("the pump room's hatch is under the %s on its terrace" % item)
pump_terrace = next((i for i, line in enumerate([l for l in dressing_block.splitlines() if l.strip().startswith("{")])
                     if '"pumproom"' in line), None)
for label, count in RUNS:
    for seed in range(100):
        radius, chunks, finish_y = lay(count, seed)
        cloud_top = heights(BASE_SURFACE_Y, kill_y(chunks))[0]
        chosen = chosen_terraces(chunks)
        if pump_terrace is not None and pump_terrace < len(chosen):
            ch = chosen[pump_terrace]
            floor = ch["y"] + CAP_TOP - S["DECK_THICK"] - S["ROOM_DOWN"] - 1
            if floor < cloud_top + 5:
                fail("%s seed %d: the pump room's floor is at %.0f, in the clouds at %.0f" % (label, seed, floor, cloud_top))
# A toy drifts no further than its pool: the swim ring reaches 2.25 from its middle.
if S["POOL_W"] / 2 - 3 + 2.25 > S["POOL_W"] / 2 - 0.3 or S["POOL_L"] / 2 - 3 + 2.25 > S["POOL_L"] / 2 - 0.3:
    fail("a pool toy can drift into the pool's wall")
# ===================================================================== the cabana, the chair and the sky

CLIENT = (SRC / "Client" / "Services" / "SkyPoolsClient.lua").read_text(encoding="utf-8")
pool_x = x0 + S["TERRACE_W"] * 0.55
x1 = x0 + S["TERRACE_W"]
footprints["cabana"] = [(px0 + S["CABANA_FROM"], px0 + S["CABANA_FROM"] + S["CABANA_W"], pz + 1.5, lz - 0.5)]
chair_z = -pz - S["LIFEGUARD_BACK"]
footprints["lifeguard"] = [(pool_x - 1.6, pool_x + 1.6, chair_z - 1.6, chair_z + 3.5), (pool_x + 3.6, pool_x + 4.4, chair_z - 1.4, chair_z + 1.4)]
pool_box = (px0 - 0.6, px1 + 0.6, -pz - 0.6, pz + 0.6)
spill = (px1, x1, -4.5, 4.5)
for item in ("cabana", "lifeguard"):
    for box in footprints[item]:
        if overlaps(box, pool_box, 0.2):
            fail("the %s stands in the pool" % item)
        if overlaps(box, spill, 0.2):
            fail("the %s stands in the overflow channel" % item)
        if box[0] < x0 or box[1] > x1 or box[2] < -lz or box[3] > lz:
            fail("the %s hangs off the edge of its terrace" % item)
for line in dressing_block.splitlines():
    items = re.findall(r'"(\w+)"', line)
    for item in ("cabana", "lifeguard"):
        if item in items:
            for other in items:
                if other == item:
                    continue
                for a in footprints.get(item, []):
                    for b in footprints.get(other, []):
                        if overlaps(a, b, 0.3):
                            fail("the %s stands on the %s on its terrace" % (item, other))

balloon = re.search(r"local height = startY \+ rng:NextNumber\((\d+), (\d+)\)", SKY)
scenery = re.search(r"sceneryPools\(model, centre, radius, h\.cloudTop \+ \d+, startY \+ (\d+), h\.seaY\)", SKY)
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
        flock_low = (float(offset) if sign == "+" else -float(offset)) - 3 - 1.5  # under the tower's top, at its lowest
        if flock_r < S["BASIN_D"] / 2 + 5:
            fail("a flock of gulls flies through the fountain's basin")
        # The slide's rods climb toward the tower: none may reach a flock where it flies.
        for label, count in RUNS:
            for seed in range(60):
                radius, chunks, finish_y = lay(count, seed)
                top_y = heights(BASE_SURFACE_Y, kill_y(chunks))[3]
                spec = slide_spec(radius, chunks, finish_y)
                for i in range(1, 101):
                    plan, y, r = slide_point(spec, i / 100)
                    reach = r - S["TOWER_D"] / 2
                    if reach > 2 and r > flock_r > S["TOWER_D"] / 2:
                        rod_top = min(y + 2.2 + reach * 0.45, top_y - 20)
                        at = (y + 2.2) + (rod_top - (y + 2.2)) * (r - flock_r) / (r - S["TOWER_D"] / 2)
                        if at > top_y + flock_low - 3:
                            fail("%s seed %d: a slide rod reaches the gulls at radius %.0f" % (label, seed, flock_r))
                            break

CLIENT_BOOT = (SRC / "Client" / "Bootstrap.client.lua").read_text(encoding="utf-8")
for tag in set(re.findall(r'AddTag\([^,]+,\s*"(\w+)"\)', SKY)) | set(re.findall(r'\),\s*"(SkyPool\w+)"\)', SKY)):
    if '"%s"' % tag not in CLIENT:
        fail("SkyPoolsService tags %s and SkyPoolsClient never looks for it" % tag)
if '"SkyPoolsClient"' not in CLIENT_BOOT:
    fail("the client Bootstrap never starts SkyPoolsClient, so the pools never splash")

# ===================================================================== report

for label, worst in report.items():
    print("%-6s ring radius %5.0f, route + finale up to %.2f of a turn (%.0f studs clear before the start), "
          "slide drop %.0f, %.1f-%.1f s, steepest %.0f deg"
          % (label, worst["radius"], worst["span"], worst["clear"], worst["drop"], worst["slide"][0],
             worst["slide"][1], worst["steep"]))
if problems:
    print("\nPROBLEMS:")
    for p in dict.fromkeys(problems):
        print("  " + p)
    sys.exit(1)
print("sky pools: terraces clear their neighbours, the ring never meets itself, the slide hits nothing and "
      "lands in the pool, heights in order, wiring present.")
