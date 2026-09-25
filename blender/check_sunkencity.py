"""The Sunken City (Level 3): holds the level's shape to what SunkenCityService assumes.

Run with plain Python from the project root:  python blender/check_sunkencity.py

The city is built along a route LevelService lays from random draws, so this lays the route the way
LevelService does (ring_layout.py) for short, medium and long runs over many seeds, and checks:

  THE ROUTE IS A STREET AND IT GOES SOMEWHERE: laid as a meander, bending no harder than the ring it
  replaces, never coming back on itself, flat but for the swell, and out of the water the whole way.
  A FALL IS SEEN AND CAUGHT: the kill plane is well under the surface, so you go into the water
  before you are reset; the aquarium's floor is above it; the drain's shaft ends well above the line
  where Roblox deletes a falling character.
  THE BLOCKS KEEP OFF THE STREET: every lot's frontage is on the kerb and no further in, nothing
  that may break the surface stands within EMERGE_CLEAR of the route's reach, and ROUTE_REACH really
  is the widest chunk in the pool.
  THE THING NEVER TOUCHES ANYTHING: its body and its wander stay inside the street, clear of the
  gantry legs and the lamp posts, under the road signs, clear of the aquarium's tower and the dry
  flat, and it turns back long before the whirlpool.
  THE AQUARIUM AND THE PIER FIT: the tower clears the neighbouring chunks, no pier pile stands in
  the whirlpool, and the whirlpool's pull cannot reach the start of the route.
  THE WIRING IS THERE: Bootstrap builds it, attaches the drain, stands the finish line down and
  exempts a rider from the kill plane; the ride's remote and shared path exist and both sides use
  them; the glass can be tapped; the palette and the banner exist; the client starts, reads every
  attribute the server writes and follows every tag it sets; no Ball parts, no Neon.
  THE MESHES FIT WHERE THE PARTS DID: every clearance the animals, the fish, the gulls and the kelp
  are held to is held for the meshes too, measured off blender/sealife_extents.json (what
  gen_sealife.py and gen_ferris.py actually built) and the bends the client gives them; SeaRig
  expects the sizes the generators build; the kelp's canopy stays in the street and under the
  surface; the Ferris wheel's frame stands on the floor and it has somewhere to stand on every run.

Exits non-zero on any failure.
"""
import json
import math
import re
import sys

import chunk_layout
from ring_layout import C as CHUNK_C
from ring_layout import CAP_HALF, CONTRACTS, DESTROY_Y, GAP, LAYOUTS, SRC, chunk_rects, rect_distance, xmax
from sunkencity_layout import (CITY_SOURCE, CLIENT_SOURCE, K, LEVEL, M, MIRRORED, P, PATH_SOURCE, along_of,
                               harbour_along,
                               along_route, aquarium, aquarium_checkpoint, city_lots, finale, flat,
                               flat_checkpoint, heights, monster_from_route, monster_reach, monster_span,
                               near_route, route_of)

BOOT = (SRC / "Server" / "Bootstrap.server.lua").read_text(encoding="utf-8")
LIGHT = (SRC / "Server" / "Services" / "LightingService.lua").read_text(encoding="utf-8")
UI = (SRC / "Client" / "Services" / "UIService.lua").read_text(encoding="utf-8")
CLIENT_BOOT = (SRC / "Client" / "Bootstrap.client.lua").read_text(encoding="utf-8")

problems = []
SKINNED = chunk_layout.load_skinned()


def fail(message):
    problems.append(message)


# THE MESHES as built: each one's real geometry box in Blender axes (x across, y forward, z up).
BLENDER = SRC.parent / "blender"
try:
    EXT = json.loads((BLENDER / "sealife_extents.json").read_text(encoding="utf-8"))
except (OSError, ValueError):
    EXT = {}
    fail("blender/sealife_extents.json is missing or unreadable: run gen_sealife.py and then gen_ferris.py")
RIG_SOURCE = (SRC / "Shared" / "SeaRig.lua").read_text(encoding="utf-8")
SEALIFE = (BLENDER / "gen_sealife.py").read_text(encoding="utf-8")
FERRIS_GEN = (BLENDER / "gen_ferris.py").read_text(encoding="utf-8")


def ext(name, key, axis):
    return EXT.get(name, {}).get(key, [0.0, 0.0, 0.0])[axis]


def reach_of(name):
    """The farthest the mesh reaches from its pivot in plan, whichever way it faces."""
    return math.hypot(max(abs(ext(name, "lo", 0)), abs(ext(name, "hi", 0))),
                      max(abs(ext(name, "lo", 1)), abs(ext(name, "hi", 1))))


def client_table(name):
    body = re.search(r"local %s = \{(.*?)\n\}" % name, CLIENT_SOURCE, re.S)
    return body.group(1) if body else ""


SWIM_T = client_table("SWIM")
KELP_T = client_table("KELP")


def swim_list(key):
    found = re.search(r"\b%s = \{ ([\d., ]+) \}" % key, SWIM_T)
    return [float(v) for v in found.group(1).split(",")] if found else []


def table_number(body, key, default=None):
    found = re.search(r"\b%s = ([\d.]+)" % key, body)
    return float(found.group(1)) if found else default


# ===================================================================== the definition and its pool

if not LEVEL.is_meander:
    print("FAIL: Level3 is not laid as a meander; the Sunken City runs down a street now, not round a ring")
    sys.exit(1)
for field, want in (("backdrop", "sunkenCity"), ("finale", "drain")):
    if LEVEL.field_text(field) != want:
        fail("Level3 has no %s = \"%s\"" % (field, want))
if LEVEL.step_scale != 0:
    fail("the Sunken City's route takes steps (stepScale %.1f); it should stay near the water" % LEVEL.step_scale)
if not LEVEL.wave:
    fail("the Sunken City's route has no swell")
else:
    height, every = LEVEL.wave
    if height * 2 * math.pi / every > 3:
        fail("the swell can lift the route %.1f studs from one chunk to the next, more than a comfortable jump"
             % (height * 2 * math.pi / every))

# HOW FAR THE STREET MAY BEND, measured against the ring this level used to be laid as.
longest = max(CONTRACTS[c][0] for c in LEVEL.pool_ids)
short_count = LEVEL.runs[0][1]
ring_turn = (longest + GAP) / LEVEL.ring_radius([LEVEL.slots[i % len(LEVEL.slots)] for i in range(short_count)])
bend = LEVEL.amplitude * 2 * math.pi / LEVEL.wavelength * (longest + GAP)
if bend > ring_turn:
    fail("the street turns %.1f degrees at the longest chunk, past the %.1f the ring it replaces turned"
         % (math.degrees(bend), math.degrees(ring_turn)))

for cid in LEVEL.pool_ids:
    if cid not in LAYOUTS:
        fail("%s is in the pool and has no layout" % cid)
    elif abs(CONTRACTS[cid][1]) > 0:
        fail("%s climbs or drops inside itself, so the route would leave the swell" % cid)
if LEVEL.by_category.get("stable") != ["S1_Straight"]:
    fail("the Sunken City's only stable chunk must be S1_Straight (the aquarium and the pier are laid along "
         "its straight side); the pool has %s" % LEVEL.by_category.get("stable"))
for cat in ("pace", "risk"):
    if not LEVEL.by_category.get(cat):
        fail("the pool has no %s chunk" % cat)
# HOW FAR ANYTHING THAT BREAKS THE SURFACE KEEPS FROM THE ROUTE, as a number rather than as its own
# rule: the per-lot check below compares a lot against EMERGE_CLEAR, so EMERGE_CLEAR being wrong
# would agree with itself. A roof coming up through the water within this of the route is close
# enough to be jumped onto.
if K["EMERGE_CLEAR"] < 25:
    fail("EMERGE_CLEAR is %.0f studs; a building may break the surface that close to the route"
         % K["EMERGE_CLEAR"])
widest = max(LEVEL.pool_ids, key=xmax)
if xmax(widest) > K["ROUTE_REACH"] + 0.01:
    fail("%s reaches %.1f from the centre line, past ROUTE_REACH %.1f" % (widest, xmax(widest), K["ROUTE_REACH"]))
for text, (name, _) in MIRRORED.items():
    if text not in CITY_SOURCE:
        fail("sunkencity_layout.py restates %s from the Luau text `%s`, which is no longer there" % (name, text))
if "PartType.Ball" in "\n".join(line.split("--", 1)[0]
                               for line in CITY_SOURCE.splitlines() + CLIENT_SOURCE.splitlines()):
    fail("the Sunken City uses Ball parts; a ball cannot be flattened, so use a sphere mesh")
for name, source in (("SunkenCityService", CITY_SOURCE), ("SunkenCityClient", CLIENT_SOURCE)):
    if "Enum.Material.Neon" in source:
        fail("%s uses Neon; this project lights nothing with fake light" % name)

# ===================================================================== the thing, against the street

reach = monster_reach()
g_side, g_up, g_down = reach["side"], reach["up"], reach["down"]
body = monster_from_route()
top_of_thing = -(K["MONSTER_DEPTH"] - K["MONSTER_BOB"]) + g_up  # relative to the surface, at its highest
if body > K["BOULEVARD_HALF"] - 5:
    fail("the thing's body reaches %.1f from the route's line, past the street's own edge at %.1f"
         % (body, K["BOULEVARD_HALF"]))
if M["GANTRY_LEG"] - body < 3:
    fail("the thing passes within %.1f of a gantry leg" % (M["GANTRY_LEG"] - body))
lamp_at = K["BOULEVARD_HALF"] - M["LAMP_IN"]
if lamp_at - body < 3:
    fail("the thing passes within %.1f of a lamp post" % (lamp_at - body))
panel_w, panel_h, panel_x, panel_y = M["GANTRY_PANEL"]
panel_bottom = -M["GANTRY_BEAM_DEPTH"] + panel_y - panel_h / 2
if top_of_thing > panel_bottom - 1:
    fail("the thing's back reaches %.1f under the surface and the road signs hang to %.1f"
         % (top_of_thing, panel_bottom))
if -(K["MONSTER_DEPTH"] + K["MONSTER_BOB"]) - g_down < -K["FLOOR_DEPTH"] + 5:
    fail("the thing swims into the sea floor")
# The two things you can walk into stand beside the street: its body must clear both.
tower_face = CAP_HALF + K["AQ_NECK"] - K["ROT_WALL"]
if tower_face - body < 1:
    fail("the thing's body reaches %.1f from the route and the aquarium's tower stands at %.1f"
         % (body, tower_face))
if CAP_HALF + K["FLAT_GANG"] - body < 1:
    fail("the thing's body reaches %.1f from the route and the dry flat starts at %.1f"
         % (body, CAP_HALF + K["FLAT_GANG"]))
# And it turns back before the pier, so it is never in the harbour with the drain.
if K["MONSTER_KEEP"] < K["PIER_L"] + K["VORTEX_GAP"] + K["VORTEX_R"] + 60:
    fail("the thing turns back only %.0f short of the end, which is inside the whirlpool" % K["MONSTER_KEEP"])

# ===================================================================== the surfacing and the mirror

for name in ("SURFACE_EVERY", "WARN", "BREACH", "WASH_AT", "WASH_RADIUS", "CREST", "CREST_REACH",
             "QUIET_MARGIN", "SWAY"):
    if name not in P:
        fail("SunkenPath has no %s this check can read" % name)
if P["WARN"] + P["BREACH"] >= P["SURFACE_EVERY"]:
    fail("one surfacing runs into the next")
if P["WASH_AT"] >= P["BREACH"]:
    fail("the surge comes after the thing has gone back down")
if P["WARN"] < 4:
    fail("the surfacing gives only %.1f seconds of warning" % P["WARN"])
# The surge has to cover the route's full width over the spot, which is under the street.
if P["WASH_RADIUS"] < K["MONSTER_SWING"] + K["ROUTE_REACH"] + 2:
    fail("the surge does not reach the far edge of the route over the spot")
if P["QUIET_MARGIN"] < 5:
    fail("a surfacing can come up within %.0f of a road sign's reach" % P["QUIET_MARGIN"])
for needle, why in (
    ("function SunkenPath.walk", "SunkenPath cannot read a line, so the thing has no street to patrol"),
    ("function SunkenPath.along", "SunkenPath has no patrol along the route"),
    ('model:GetAttribute("MonsterLine")', "SunkenPath never reads the route's line"),
    ("function SunkenPath.drainFrame", "the drain's ride is not shared, so the client cannot draw it"),
):
    if needle not in PATH_SOURCE:
        fail(why)

# The server takes only Hardcore players, only above the water, only outside the shelters; the
# mirror only a Hardcore player, once a server.
surge = CITY_SOURCE[CITY_SOURCE.find("-- THE SURGE"):CITY_SOURCE.find("-- THE MIRROR:")]
for needle, why in (("isHardcore(player)", "the surge takes Chill players too"),
                    ("inAny(shelters, p)", "the surge reaches players indoors"),
                    ("p.Y > spot.Y", "the surge takes players under the water, in the aquarium"),
                    ("onTaken(player)", "the surge takes nobody")):
    if needle not in surge:
        fail(why)
mirror = CITY_SOURCE[CITY_SOURCE.find("-- THE MIRROR:"):]
for needle, why in (("not mirrorShown", "the mirror can happen more than once a server"),
                    ("isHardcore(player)", "the face in the mirror shows in Chill"),
                    ("mirrorShown = true", "the mirror never marks itself as done"),
                    ('SetAttribute("MirrorFace"', "the server never tells the client to show the face")):
    if needle not in mirror:
        fail(why)
if "local mirrorShown = false" not in CITY_SOURCE:
    fail("mirrorShown is not a module-level flag, so it resets every run")
if 'GetAttributeChangedSignal("MirrorFace")' not in CLIENT_SOURCE:
    fail("SunkenCityClient never listens for MirrorFace")
# The reset the surge uses is the kill plane's own.
steps = ("TimerService.resetTimer(player)", "syncTimer(player)", "PlayerFell:FireClient(player)",
         "restartRunFor(player)",
         "hrp.CFrame = CFrame.new(levelInstance.startPosition + Vector3.new(0, 3, 0))")
send = BOOT[BOOT.find("sendBackToStart = function"):]
send = send[:send.find("\nend\n")]
branch = BOOT[BOOT.find('if state.mode == "hardcore" then', BOOT.find("if hrp.Position.Y < killY")):]
branch = branch[:branch.find("else")]
for step in steps:
    if step not in send:
        fail("sendBackToStart is missing `%s`, which the kill plane's Hardcore reset has" % step)
    if step not in branch:
        fail("the kill plane's Hardcore reset no longer has `%s`, so sendBackToStart has drifted from it" % step)

# ===================================================================== every run

report = {}

# ===================================================================== the aquarium's stair

# stairPlan, restated: the table of numbers, then the search. Each line below is the Luau as written,
# so a change to the stair that this does not know about fails here rather than passing quietly.
_stair_table = re.search(r"local STAIR = \{(.*?)\n\}", CITY_SOURCE, re.S)
STAIR = {}
if _stair_table:
    for _name, _expr in re.findall(r"^\t(\w+) = ([^,\n]+),", _stair_table.group(1), re.M):
        STAIR[_name] = eval(_expr.replace("math.rad(", "math.radians(").replace("math.pi", "math.pi"), {"math": math})
for _needle in (
    "for turns = 1, 5 do",
    "local sweep = STAIR.foot + turns * 2 * math.pi - STAIR.top",
    "local fewest = math.max(2, math.ceil(sweep / STAIR.angleMax + 0.5))",
    "local most = math.floor(sweep / STAIR.angleMin + 0.5)",
    "local rise = drop / (steps + 1)",
    "local angle = sweep / (steps - 0.5)",
    "local psi = STAIR.top + (step - 0.5) * angle\n\t\tlocal cf = towerAt * CFrame.Angles(0, -psi, 0) * CFrame.new(6.15, -step * rise - 0.5, 0)",
    'block(parent, "Step", Vector3.new(7.1, 1, 3.2), cf,',
    "if index >= 11 and index <= 13 then",
    "if index == 23 or index == 0 or index == 1 then",
):
    if _needle not in CITY_SOURCE:
        fail("the aquarium's stair or its tower has changed from what this check lays: `%s`" % _needle)


# THE BOUNDS THEMSELVES, not just today's drops: the shallowest, most turned stair stairPlan is
# allowed to choose must still leave room under the turn above it.
if STAIR and STAIR["riseMin"] * 2 * math.pi / STAIR["angleMax"] - 1 < 7:
    fail("stairPlan may choose steps so shallow that the turn above is %.1f over the one below"
         % (STAIR["riseMin"] * 2 * math.pi / STAIR["angleMax"] - 1))
if not STAIR:
    fail("cannot find the STAIR table in SunkenCityService")


def stair_plan(drop):
    best, miss_best = None, math.inf
    for turns in range(1, 6):
        sweep = STAIR["foot"] + turns * 2 * math.pi - STAIR["top"]
        if sweep <= 0:
            continue
        fewest = max(2, math.ceil(sweep / STAIR["angleMax"] + 0.5))
        most = math.floor(sweep / STAIR["angleMin"] + 0.5)
        for steps in range(fewest, most + 1):
            rise = drop / (steps + 1)
            angle = sweep / (steps - 0.5)
            if STAIR["riseMin"] <= rise <= K["STEP_RISE_MAX"] and STAIR["angleMin"] <= angle <= STAIR["angleMax"]:
                miss = abs(rise - STAIR["riseBest"])
                if miss < miss_best:
                    best, miss_best = (steps + 1, rise, angle), miss
    return best


def _overlaps(centre, half, lo, hi):
    """Whether an arc centre +/- half overlaps the arc lo..hi, all in degrees, any number of turns."""
    width = hi - lo
    mid = (lo + hi) / 2
    gap = (centre - mid + 180) % 360 - 180
    return abs(gap) < half + width / 2


def walk_stair(drop):
    """What is wrong with the stair for this drop, or None. The tread's arc is taken at r = 8, where
    you walk; the mouth is the three wall segments round 0, the door the three round 180."""
    plan = stair_plan(drop)
    if plan is None:
        return "no stair fits a drop of %.1f" % drop
    count, rise, angle = plan
    turn = rise * 2 * math.pi / angle
    if turn - 1 < 7:
        return "the turn above is only %.1f over the step below it" % (turn - 1)
    half = math.degrees(1.6 / 8)
    foot = math.degrees(STAIR["foot"])
    for j in range(1, count):
        psi = math.degrees(STAIR["top"] + (j - 0.5) * angle)
        top = drop - j * rise
        bottom = top - 1
        if _overlaps(psi, half, -22.5, 22.5) and bottom < 7.5:
            return "step %d crosses the tunnel's mouth %.1f off the floor" % (j, bottom)
        if _overlaps(psi, half, foot + half, 22.5) and bottom < 6.5:
            return "step %d is %.1f over the way from the stair's foot to the tunnel" % (j, bottom)
        if _overlaps(psi, half, 157.5, 202.5) and j * rise < 6.5:
            return "step %d is in the doorway, %.1f under the landing" % (j, j * rise)
    return None

for label, count in LEVEL.runs:
    worst = {"water_gap": math.inf, "fall": math.inf, "vortex": math.inf, "start": math.inf,
             "aq_kill": math.inf, "shaft": math.inf, "apart": math.inf, "street": math.inf, "lots": 0}
    for seed in range(120):
        radius, chunks, finish_y = LEVEL.lay(count, seed)
        h = heights(chunks)
        kill = min(ch["y"] for ch in chunks) - 40
        route = route_of(radius, chunks, finish_y)

        # ----- the route out of the water, the fall seen and caught
        underside = min(ch["y"] + min(b.y - b.sy / 2 for b in LAYOUTS[ch["id"]]) for ch in chunks)
        # ----- what hangs under a rigged platform stays out of the water: a jellyfish's tentacles
        # hang nearly eight studs under the bell, a slime's strands six. A mesh hangs its
        # surfaceOffset plus half its height under the plane you walk on, which is the slab's
        # top plus its tiles.
        for ch in chunks:
            for b in LAYOUTS[ch["id"]]:
                for spec in SKINNED.get(b.material) or []:
                    if spec.get("form") == b.form and abs(spec["sizeX"] - b.sx) <= 0.1 and abs(spec["sizeZ"] - b.sz) <= 0.1:
                        tip = (ch["y"] + b.y + b.sy / 2 + CHUNK_C["TILE_THICKNESS"]
                               - (spec["surfaceOffset"] + spec["meshHeight"] / 2))
                        worst["hang"] = min(worst.get("hang", 99.0), tip - h["water"])
                        if tip - h["water"] < 1.5:
                            fail("%s seed %d: %s hangs to %.1f over the water under %s"
                                 % (label, seed, spec["mesh"], tip - h["water"], ch["id"]))
        worst["water_gap"] = min(worst["water_gap"], underside - h["water"])
        if underside - h["water"] < 1.5:
            fail("%s seed %d: a chunk's underside is %.1f above the water" % (label, seed, underside - h["water"]))
        worst["fall"] = min(worst["fall"], h["water"] - kill)
        if h["water"] - kill < 20:
            fail("%s seed %d: the kill plane is only %.1f under the surface" % (label, seed, h["water"] - kill))
        worst["aq_kill"] = min(worst["aq_kill"], h["tunnel"] + 3 - kill)
        if h["tunnel"] + 3 < kill + 6:
            fail("%s seed %d: the aquarium's floor is within reach of the kill plane" % (label, seed))
        worst["shaft"] = min(worst["shaft"], h["shaft"] - DESTROY_Y)
        if h["shaft"] < DESTROY_Y + 60:
            fail("%s seed %d: the drain's shaft ends at %.0f, too near the %d delete line"
                 % (label, seed, h["shaft"], DESTROY_Y))

        # ----- the surfacing: its fins come through the surface and stay under the route
        fins = h["water"] - P["CREST"] + g_up
        if fins > underside - 1:
            fail("%s seed %d: surfacing, the thing's fins reach %.1f, within a stud of a chunk's underside at %.1f"
                 % (label, seed, fins - h["water"], underside - h["water"]))

        # ----- the street never comes back on itself
        for i in range(len(chunks)):
            for j in range(i + 5, len(chunks)):
                gap_studs = math.dist(chunks[i]["pos"], chunks[j]["pos"])
                worst["apart"] = min(worst["apart"], gap_studs)
                if gap_studs < 90:
                    fail("%s seed %d: chunks %d and %d come within %.0f studs of each other"
                         % (label, seed, i + 1, j + 1, gap_studs))

        # ----- the blocks: on the kerb, never in the street, and nothing near the route may emerge
        lots = city_lots(route)
        worst["lots"] = max(worst["lots"], len(lots))
        if not lots:
            fail("%s seed %d: the city has no lots at all" % (label, seed))
        for lot in lots:
            worst["street"] = min(worst["street"], lot["inner"])
            if lot["inner"] < K["BOULEVARD_HALF"] - 0.01:
                fail("%s seed %d: a block's frontage stands %.1f from the route, inside the street's %.0f"
                     % (label, seed, lot["inner"], K["BOULEVARD_HALF"]))
            if lot["emerges"] and lot["inner"] < K["EMERGE_CLEAR"] + K["ROUTE_REACH"]:
                fail("%s seed %d: a block that may break the surface stands %.1f from the route"
                     % (label, seed, lot["inner"]))
        # The clock tower stands off the street on its plaza.
        plaza_at, plaza_dir = along_route(route, route["total"] * 0.34)
        plaza_side = (-plaza_dir[1], plaza_dir[0])
        plaza = (plaza_at[0] + plaza_side[0] * M["PLAZA_OUT"], plaza_at[1] + plaza_side[1] * M["PLAZA_OUT"])
        plaza_near, _ = near_route(route, plaza)
        if plaza_near - M["CLOCK_SIDE"] / math.sqrt(2) < K["EMERGE_CLEAR"] + K["ROUTE_REACH"]:
            fail("%s seed %d: the clock tower stands %.0f from the route, inside what may break the surface"
                 % (label, seed, plaza_near))

        # ----- the pier and the whirlpool
        fin = finale(radius, chunks, finish_y)
        vortex = fin["vortex"]
        rects = chunk_rects(radius, chunks)
        start_gap = min(rect_distance(r, vortex) for r in rects[: max(1, len(rects) // 2)])
        worst["start"] = min(worst["start"], start_gap - K["CAPTURE_R"])
        if start_gap < K["CAPTURE_R"] + 15:
            fail("%s seed %d: the whirlpool's pull reaches within %.0f of the route's start"
                 % (label, seed, start_gap - K["CAPTURE_R"]))
        for pile in fin["piles"]:
            if math.dist(pile, vortex) < K["VORTEX_R"] + 3 + 1.5:
                fail("%s seed %d: a pier pile stands in the whirlpool" % (label, seed))
        if K["VORTEX_GAP"] < K["CAPTURE_R"] - 0.01:
            fail("the whirlpool's pull reaches back over the pier")
        # The thing patrols the street and turns back: how near it ever gets to the whirlpool.
        turn_at = monster_span(route)
        stop, _ = along_route(route, turn_at)
        worst["vortex"] = min(worst["vortex"], math.dist(stop, vortex) - body)
        if math.dist(stop, vortex) - body < 60:
            fail("%s seed %d: the thing turns back %.0f from the whirlpool"
                 % (label, seed, math.dist(stop, vortex) - body))

        # ----- the aquarium
        ch = aquarium_checkpoint(chunks)
        if ch is None:
            fail("%s seed %d: no checkpoint for the aquarium" % (label, seed))
        else:
            aq = aquarium(radius, ch)
            if along_of(route, aq["tower"]) > route["total"] - harbour_along(route):
                fail("%s seed %d: the aquarium stands in the harbour" % (label, seed))
            for r in rects:
                if r["name"] == "chunk %d" % ch["index"]:
                    continue
                if rect_distance(r, aq["tower"]) < K["ROT_R"] + 1.5:
                    fail("%s seed %d: the aquarium's tower touches %s" % (label, seed, r["name"]))
                for end in aq["tunnel"] + (aq["room"],):
                    if rect_distance(r, end) < 14:
                        fail("%s seed %d: the aquarium's tunnel reaches %s" % (label, seed, r["name"]))
            landing = aq["landing_y"]
            if landing - h["tunnel"] < 12:
                fail("%s seed %d: the aquarium's stair has only %.0f to go down" % (label, seed, landing - h["tunnel"]))
            wrong = walk_stair(landing - h["tunnel"])
            if wrong:
                fail("%s seed %d: the aquarium's stair: %s" % (label, seed, wrong))
        # ----- the dry flat
        fch = flat_checkpoint(chunks, ch)
        if fch is None:
            fail("%s seed %d: no checkpoint for the dry flat" % (label, seed))
        else:
            fl = flat(radius, fch)
            if along_of(route, fl["centre"]) > route["total"] - harbour_along(route):
                fail("%s seed %d: the dry flat stands in the harbour" % (label, seed))
            for r in rects:
                if r["name"] == "chunk %d" % fch["index"]:
                    continue
                for x in (fl["x"][0], fl["x"][1]):
                    for z in (fl["z"][0], fl["z"][1], 0):
                        corner = (fl["edge"][0] + fl["out"][0] * x + fl["along"][0] * z,
                                  fl["edge"][1] + fl["out"][1] * x + fl["along"][1] * z)
                        if rect_distance(r, corner) < 1.5:
                            fail("%s seed %d: the dry flat touches %s" % (label, seed, r["name"]))
            drop = fl["landing_y"] - (h["water"] - 1.5)
            if not (8 <= drop <= 30):
                fail("%s seed %d: the dry flat's stair goes down %.0f to the water" % (label, seed, drop))
            if ch is not None and math.dist(fl["centre"], aquarium(radius, ch)["tower"]) < 60:
                fail("%s seed %d: the dry flat and the aquarium stand within 60 of each other" % (label, seed))
    report[label] = worst

# ===================================================================== the wiring

marker = 'if level.backdrop == "sunkenCity" then'
block = BOOT[BOOT.index(marker):] if marker in BOOT else ""
# Only the Sunken City's own block, up to the next section header, for check_skypools.py's reason.
if block:
    ends = [at for at in (block.find("\n\t-- ===== "), block.find("-- THE MODE COMES FROM THE PADS")) if at > 0]
    block = block[:min(ends)]
if not block:
    fail("Bootstrap never checks for the sunkenCity backdrop, so nothing builds the city")
for needle, why in (
    ("SunkenCityService.build(levelInstance", "Bootstrap never builds the city"),
    ("SunkenCityService.attach(", "Bootstrap never attaches the drain"),
    ("finishRunFor(player)", "the drain does not finish the run"),
    ("finishPart.CanTouch = false", "the old finish line is not stood down, so the pier ends the run"),
):
    if block and needle not in block:
        fail(why)
kill_line = BOOT[BOOT.index("if hrp.Position.Y < killY"):]
kill_line = kill_line[:kill_line.index(" then")]
if "SunkenCityService.ownsFall(player)" not in kill_line:
    fail("the kill plane does not exempt a drain rider, so the ride ends at the kill plane")
if 'ensureRemoteEvent(remoteEventsFolder, "SunkenRide")' not in BOOT:
    fail("Bootstrap never makes the SunkenRide remote, so no client can draw the way down the drain")
for needle, why in (
    ("SunkenPath.drainFrame", "the server no longer puts the rider where the shared path says"),
    ("if not drawing[player] and SunkenPath then", "the server does not stand back once the client is drawing "
                                                   "the ride"),
    ("if riding[player] then", "the ride's remote takes a client's word without checking it is riding"),
):
    if needle not in CITY_SOURCE:
        fail(why)
for needle, why in (
    ("SunkenPath.drainFrame", "SunkenCityClient never draws the ride down the drain"),
    ("drainRemote:FireServer()", "the client never tells the server it has the ride"),
    ('GetAttributeChangedSignal("Tapped")', "the client never answers a tap on the glass"),
):
    if needle not in CLIENT_SOURCE:
        fail(why)
# The glass says it can be tapped, and every tap does something in both modes.
glass = CITY_SOURCE[CITY_SOURCE.find("-- ===== THE GLASS ====="):CITY_SOURCE.find("-- ONCE A SERVER, EVER")]
for needle, why in (
    ("ProximityPrompt", "the window has no prompt, so a player has no way to know it can be tapped"),
    ("prompt.Triggered:Connect(function(player)\n\t\t\ttapped(player, pane)",
     "the panes' prompts are not wired to anything, so using them does nothing"),
    ('model:SetAttribute("Tapped"', "a tap tells nobody, so nothing answers it"),
    ("ClickDetector", "clicking the glass no longer works"),
):
    if needle not in glass:
        fail(why)
# ===================================================================== the buildings

# A BUILDING IS NOT A BOX WITH A STRIPE ROUND IT. The city was read back as "platforms in the sky",
# and these five are what it takes to answer that: storeys you can count, what time has done to
# them, what has grown on them, what somebody did about the water -- and detail spent where it can
# be read rather than evenly over three hundred buildings.
for needle, why in (
    ("local function facadeOf", "the buildings have no facade: sills, ribs and windows set into the wall"),
    ("local function wearOn", "nothing wears: no rust, no fallen render, no broken corner"),
    ("local function growthOn", "nothing has grown on the city since the water came"),
    ("local function holdingOut", "nothing shows the city fighting the water, which is half the story"),
    ("local function dress", "the buildings are never dressed"),
    ("local DETAIL_NEAR, DETAIL_MID", "detail is no longer spent by distance, so either the street is "
                                      "bare or the haze is full of parts nobody can resolve"),
    ("local detail = if near < DETAIL_NEAR then 2 elseif near < DETAIL_MID then 1 else 0",
     "the city no longer decides how much building a lot gets from how near the street it is"),
):
    if needle not in CITY_SOURCE:
        fail(why)
# Every kind of building gets dressed, or the ones that do not stand out as the clean ones.
for kind in ("floodedFlats", "house", "tower", "warehouse"):
    body = CITY_SOURCE[CITY_SOURCE.index("local function %s(" % kind):]
    body = body[:body.index("\nend\n")]
    if "dress(parent" not in body:
        fail("%s is never dressed, so it is a clean box in a drowned city" % kind)
    if "facadeOf(parent" not in body:
        fail("%s has no facade, so it reads as a platform rather than a building" % kind)
# AND THE FACADE IS BOUNDED. A city is three hundred buildings; an unbounded facade is a part count.
for needle, why in (
    ("math.clamp(math.floor((to - start) / storey), 1, if detail >= 2 then FACADE_FLOORS else 4)",
     "the facade's storeys are unbounded"),
    ("math.clamp(math.floor(w / 7), 1, 3)", "the facade's window panes are unbounded"),
    ("local SEEN_DEEP", "the facade is drawn all the way down into water nobody can see through"),
):
    if needle not in CITY_SOURCE:
        fail(why)
# The flats no longer all stop at the waterline, which is what made a street of them read as a field
# of platforms -- but a building may only stand up out of the water where the lot is allowed to
# break the surface, which is the rule this level has always had.
if "local stands = mayStand and rng:NextNumber() < 0.6" not in CITY_SOURCE:
    fail("every block of flats tops out under the water again, so the city is one flat height -- or "
         "worse, it stands wherever it likes and a roof comes up beside the route")
for call in ('floodedFlats(parent, lot, w, d, rng, detail, clearOfRoute)',
             'warehouse(parent, lot, w, d, rng, detail, clearOfRoute)'):
    if call not in CITY_SOURCE:
        fail("the city does not tell `%s` whether its lot may break the surface" % call.split("(")[0])
if "local top = if mayStand then waterLevel + rng:NextNumber(3.5, 9)" not in CITY_SOURCE:
    fail("a warehouse roof comes up out of the water wherever it is built")

if "sunkenCity = {" not in LIGHT:
    fail("LightingService has no sunkenCity palette")
if '[3] = { name = "The Sunken City"' not in UI:
    fail("UIService's finale banner for level 3 is not the Sunken City's")
if '"SunkenCityClient"' not in CLIENT_BOOT:
    fail("the client Bootstrap never starts SunkenCityClient, so the thing never swims")
written = set(re.findall(r'sea:SetAttribute\("(\w+)"', CITY_SOURCE))
written_anywhere = set(re.findall(r':SetAttribute\("(\w+)"', CITY_SOURCE))
readers = CLIENT_SOURCE + PATH_SOURCE
read = set(re.findall(r'num\("(\w+)"\)', readers)) | set(re.findall(r'GetAttribute\("(\w+)"\)', readers)) \
    | set(re.findall(r'numbers\("(\w+)"\)', readers))
for name in sorted(written - read):
    fail("SunkenCityService writes %s on the sea and SunkenCityClient never reads it" % name)
# Every marker's brief -- a shoal's, a horror's, a swimmer's -- is read by the client that draws it.
for name in sorted(set(re.findall(r'marker:SetAttribute\("(\w+)"', CITY_SOURCE)) - read):
    fail("SunkenCityService gives its markers %s and SunkenCityClient never reads it" % name)
for name in sorted(read - written_anywhere):
    fail("SunkenCityClient reads %s and SunkenCityService never writes it" % name)
tags = set(re.findall(r'AddTag\([^,]+,\s*"(\w+)"\)', CITY_SOURCE))
server_reads = set(re.findall(r'tagged\(model, "(\w+)"\)', CITY_SOURCE))
for tag in sorted(tags):
    if '"%s"' % tag not in CLIENT_SOURCE and tag not in server_reads:
        fail("SunkenCityService tags %s and nothing ever looks for it" % tag)
if 'require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SunkenPath"))' not in CLIENT_SOURCE \
        or 'WaitForChild("SunkenPath"' not in CITY_SOURCE:
    fail("the server and the client do not both use the shared SunkenPath, so they can disagree about the thing")
sky_attach = block[block.find("SunkenCityService.attach("):] if block else ""
if "sendBackToStart(player)" not in sky_attach:
    fail("Bootstrap does not hand the city sendBackToStart, so the surge takes nobody")

# ===================================================================== this pass

# THE FACADE IS IN THE BUILDING'S OWN FRAME. The empty frames in the sky were a tower passing a height
# above its floor to a facade that expected a world height. Every call's `from` is a small number
# over the floor, and its `to` comes, however indirectly, from something minus floorY.
fac = CITY_SOURCE[CITY_SOURCE.index("local function facadeOf("):]
fac = fac[:fac.index("\nend\n")]
for needle, why in (
    ("local floorY = frame.Position.Y", "facadeOf no longer knows its own floor"),
    ("local start = if detail >= 2 then from else math.max(from, waterLevel - SEEN_DEEP - floorY)",
     "facadeOf's start is not a height over the floor any more"),
    ('Vector3.new(d + 1.6, 1.1, w + 1.6), frame * CFrame.new(0, to, 0)', "the cornice is not at `to` in the frame"),
):
    if needle not in fac:
        fail(why)


def relative(expr, body, depth=0):
    """Whether `expr`, followed through the locals it names, is a height over floorY."""
    if "floorY" in expr:
        return True
    if depth > 3:
        return False
    for name in re.findall(r"[A-Za-z_]\w*", expr):
        found = re.search(r"local %s = (.+)" % name, body)
        if found and relative(found.group(1), body, depth + 1):
            return True
    return False


calls = 0
for kind in ("floodedFlats", "house", "tower", "warehouse"):
    body = CITY_SOURCE[CITY_SOURCE.index("local function %s(" % kind):]
    body = body[:body.index("\nend\n")]
    for start_arg, to_arg in re.findall(r"facadeOf\(parent, frame, w, d, ([^,]+), ([^,]+),", body):
        calls += 1
        try:
            low = float(start_arg)
        except ValueError:
            low = None
        if low is None or not 0 <= low <= 3:
            fail("%s's facade starts at `%s`, which is not a small height over its own floor" % (kind, start_arg))
        if not relative(to_arg, body):
            fail("%s's facade ends at `%s`, which is not a height over its own floor -- the frames in "
                 "the sky again" % (kind, to_arg))
if calls < 4:
    fail("only %d facadeOf calls found in the four buildings" % calls)

# EVERY BLOCK OF FLATS HAS A ROOF. Open to the sky read as hollow from any distance; one in four has
# lost part of it, which is wear, and those are the ones with rooms to see into.
for needle, why in (
    ('cityBlock(parent, "FlatRoof", Vector3.new(d + 0.8, 0.7, w + 0.8), frame * CFrame.new(0, rel + 8.4, 0), roofColour)',
     "a block of flats can be left without a roof, which is the hollow box again"),
    ("local collapsed = rng:NextNumber() < 0.25", "more than one in four roofs has fallen in, or none can"),
    ('cityBlock(parent, "FallenRoof"', "a fallen-in roof leaves no roof lying in the room"),
):
    if needle not in CITY_SOURCE:
        fail(why)

# THE TANK STOPS UNDER THE SURFACE and nothing in it lies flat. Panes above the water, or laid over the
# tunnel, made a rectangle by the aquarium where the water looked like different water.
if "local tankTop = waterLevel - 3" not in CITY_SOURCE:
    fail("the aquarium's tank panes are not held under the surface")
if CITY_SOURCE.count('"TankWater"') != 1:
    fail("there is more than one kind of tank pane; the flat ones over the tunnel are back")

# A HANDFUL OF LIT WINDOWS, not a lit city.
if "litLeft = LIT_WINDOWS" not in CITY_SOURCE or "litLeft -= 1" not in CITY_SOURCE:
    fail("lit windows are no longer counted, so any number of them can be lit")
if K.get("LIT_WINDOWS", 99) > 12:
    fail("LIT_WINDOWS is %d; a city with that many lights on is not abandoned" % K.get("LIT_WINDOWS", 99))

# THE SWIMMERS KEEP TO THE OPEN WATER UNDER THE ROUTE. Never further across than SWIM_REACH, and a
# ray -- the widest, at its scale -- reaches its wing tip past that; the street bends a couple of
# studs over the length an animal wanders along it. All of that stays inside the road signs' legs,
# which are the nearest thing standing in the street.
scale = {name: float(value) for name, value in
         re.findall(r"(\w+) = ([\d.]+)", (re.search(r"local SWIMMER_SCALE = \{(.*?)\}", CLIENT_SOURCE) or [None, ""])[1])}
RAY = scale.get("ray", 0)
RAY_HALF_SPAN, BEND = (1.3 + 1.5 + 3.4 / 2) * RAY, 2.5
if not RAY:
    fail("cannot find the swimmers' scale in SunkenCityClient")
for needle, why in (
    ("CFrame.new(-1.3 * k, 0, 0.3 * k) * CFrame.Angles(0, 0, beat) * CFrame.new(-1.5 * k, 0, 0)",
     "the ray's wing is not where this check thinks it is"),
    ("side * (math.sin(k * 0.43 + 1.7) * s.across)", "a swimmer's wander across the street is not held to Across"),
    ("local startle = if along then 0 else bolt", "the street's shoals bolt when the aquarium's glass is tapped"),
    ("run * (math.cos(a) * radius * wobble) + side * (math.sin(a) * radius * 0.6)",
     "a shoal no longer circles a loop laid along the street"),
):
    if needle not in CLIENT_SOURCE:
        fail(why)
for needle, why in (
    ("local across = SWIM_REACH - math.abs(out)", "a swimmer's Across is not measured from SWIM_REACH"),
    ("blocked(home, math.max(range, across) + 6)",
     "a swimmer can be given a home whose wander takes it through the aquarium or the dry flat"),
    ("swimmers(sea, route, h.floor, rng, blocked)", "the swimmers are placed without knowing what is blocked"),
    ("shoals(sea, route, h.floor, rng, blocked)", "the shoals are placed without knowing what is blocked"),
    ("local reachable = route.total - harbourAlong(route)", "a swimmer can be put in the harbour's whirlpool"),
    ("local spot = at + side * rng:NextNumber(-SHOAL_OUT, SHOAL_OUT)", "a shoal is not held to SHOAL_OUT"),
    ("local radius = rng:NextNumber(12, 20)", "a shoal's size is not what this check allows for"),
    ('marker:SetAttribute("Along", dir)', "the street's markers do not say which way the street runs"),
):
    if needle not in CITY_SOURCE:
        fail(why)
leg_face = M["GANTRY_LEG"] - 0.7
# A mesh reaches its box's corner from its pivot at most, whichever way it faces; the eel's wave
# throws its tail about two studs more, and the pod swims 2.6 either side of its line.
MESH_REACH = max([reach_of(n) for n in ("Sea_Ray", "Sea_Shark", "Sea_Grouper", "Sea_Turtle", "Sea_TurtleShell", "Sea_Jelly")]
                 + [reach_of("Sea_Eel") + 2.0, reach_of("Sea_Dolphin") + 2.6])
widest = K["SWIM_REACH"] + max(RAY_HALF_SPAN, MESH_REACH) + BEND
if widest > leg_face - 0.5:
    fail("a ray's wing reaches %.1f across the street and the road signs' legs stand at %.1f" % (widest, leg_face))
shoal_widest = K["SHOAL_OUT"] + 20 * 0.6 + max(3.2 / 2, reach_of("Sea_FishLarge")) + BEND
if shoal_widest > leg_face - 0.5:
    fail("a shoal reaches %.1f across the street and the road signs' legs stand at %.1f" % (shoal_widest, leg_face))
# THE TANK'S: over the tunnel's roof and under the surface, and inside the tank.
for needle in ("at = Vector3.new(at.X, tunnelY + rng:NextNumber(13.5, 16), at.Z)", "across, bob = 9, 1",
               "at = frame * Vector3.new(tunnelFrom + rng:NextNumber(22, TUNNEL_L - 22), 0, rng:NextNumber(-4, 4))"):
    if needle not in CITY_SOURCE:
        fail("the tank's animals have moved from where this check puts them: `%s`" % needle)
roof_apex = K["TUNNEL_H"] + 0.4
# The mesh ray's wing: Wing_?1 from 1.4 to 3.6 across, Wing_?2 from 3.6 to the tip, each bent by
# SWIM.rayBeat, so its tip rises and falls by this much over the body's middle.
RAY_BEAT = swim_list("rayBeat")
ray_bones = re.search(r'\("Wing_L1", \(-([\d.]+), 0, 0\), \(-([\d.]+), 0, 0\), "Root"\),\s*'
                      r'\("Wing_L2", \(-[\d.]+, 0, 0\), \(-([\d.]+), 0, 0\)', SEALIFE)
if len(RAY_BEAT) != 2 or not ray_bones:
    fail("cannot find how the mesh ray's wings are rigged or how hard they beat")
    ray_tip = 99.0
else:
    w0, w1, w2 = (float(v) for v in ray_bones.groups())
    ray_tip = 0.1 + (w1 - w0) * math.sin(RAY_BEAT[0]) + (w2 - w1) * math.sin(RAY_BEAT[0] + RAY_BEAT[1]) + 0.05
ray_down = max(max(0.4, 0.15 + 1.5 * math.sin(0.45)) * RAY, -ext("Sea_Ray", "lo", 2), ray_tip)
if 13.5 - 1 - ray_down < roof_apex + 0.3:
    fail("a ray over the tunnel can touch its roof (a wing tip %.2f down)" % ray_down)
# The grouper over the tunnel, the deepest-bellied of them; it clears the glass by a quarter stud.
grouper_down = max(2.6 * scale.get("grouper", 0) / 2, -ext("Sea_Grouper", "lo", 2))
if 13.5 - 1 - grouper_down < roof_apex + 0.25:
    fail("a grouper over the tunnel can touch its roof")
# The turtle: its front flippers flap 0.4 down from 0.45 under its middle, 2.95 long.
if "SeaRig.bend2(rig, \"Flipper_FL\", FORWARD, math.sin(stroke) * 0.4" not in CLIENT_SOURCE:
    fail("the turtle's flippers flap differently from what this check allows for")
if 13.5 - 1 - max(0.75 * scale.get("turtle", 0), 0.45 + 2.95 * math.sin(0.4) + 0.1) < roof_apex + 0.3:
    fail("a turtle's flipper over the tunnel can touch its roof")
if 16 + 1 + max((1.9 + 1.2) * scale.get("shark", 0), ext("Sea_Shark", "hi", 2)) > K["TUNNEL_BELOW"] - 1:
    fail("a shark over the tunnel can break the surface")
if 4 + 9 + RAY_HALF_SPAN > K["TANK_HALF"] + 1:
    fail("a ray over the tunnel reaches out of the tank, where the city is allowed to build")

# THE KELP'S REACH. A strand's top sways up to 0.9 of (2 + 0.03 of its height) off its foot, and a
# blade reaches 4.2 further; it sways less lower down, as the bend (f ^ 1.6) says.
for needle in ("local amp = 2 + k.height * 0.03", "local bend = f ^ 1.6",
               "k.lean * (bend * amp * (0.5 + 0.35 * sway))", "k.across * (bend * amp * 0.3 * drift)",
               "local long = 3 + f * 1.2", "if f > 0.3 then"):
    if needle not in CLIENT_SOURCE:
        fail("the kelp sways differently from what this check allows for: `%s`" % needle)
REACH_FACTOR = math.hypot(0.85, 0.3)


def kelp_reach(height, f):
    return f ** 1.6 * REACH_FACTOR * (2 + 0.03 * height) + (4.2 if f > 0.3 else 0)


for needle in ("if index % 2 == 1 then", "local bed = at + side * (sign * KELP_KERB)",
               "local foot = bed + dir * ((strand - 2) * 3 + rng:NextNumber(-0.8, 0.8)) + side * rng:NextNumber(-1, 1)",
               "if index % 2 == 0 and not blocked(at + side * (lampSign * (BOULEVARD_HALF - 2)), 4) then",
               "off = (if planted % 2 == 0 then 1 else -1) * rng:NextNumber(KELP_TUNNEL, TANK_HALF - 3)",
               "along = rng:NextNumber(tunnelFrom + 8, tunnelTo - 10)",
               "along = rng:NextNumber(roomFar + 35, roomFar + 38)"):
    if needle not in CITY_SOURCE:
        fail("the kelp is planted differently from what this check allows for: `%s`" % needle)
street_reach = kelp_reach(K["FLOOR_DEPTH"] - 2, 1)
if K["KELP_KERB"] - 1 - street_reach < leg_face + 0.3:
    fail("a kerb's kelp reaches %.1f in, where the road signs' legs stand at %.1f"
         % (K["KELP_KERB"] - 1 - street_reach, leg_face))
if K["KELP_KERB"] + 1 + street_reach > K["BOULEVARD_HALF"] + M["LOT_BITE"]:
    fail("a kerb's kelp reaches into the blocks")
if K["KELP_KERB"] - 1 - street_reach < K["SWIM_REACH"] + max(RAY_HALF_SPAN, MESH_REACH) + BEND:
    fail("the street's animals swim into the kerb's kelp")
# THE MESH STRAND bends through the same joints (kelpJoint), so its sway is the part-built one's; its
# small blades must reach no further than the 4.2 allowed for above.
if "joints[i + 1] = frame:PointToObjectSpace(kelpJoint(k, i, clock))" not in CLIENT_SOURCE:
    fail("the mesh kelp does not bend through kelpJoint, so the reach checked here is not its reach")
blade = re.search(r"KELP_BLADE = ([\d.]+)", SEALIFE)
if not blade or "base = Vector((0, 0, z0)) + out * (long * t * 0.7)" not in SEALIFE:
    fail("cannot find how long the mesh kelp's blades are")
else:
    long_ = float(blade.group(1))
    blade_reach = max(math.hypot(long_ * 0.7 * t, 0.75 * math.sin(math.pi * min(1, 1.1 * t)) + 0.05 + 0.1 * abs(math.sin(20 * t)))
                      for t in [i / 200 for i in range(201)]) + 0.12 + 0.05
    if blade_reach > 4.2:
        fail("the mesh kelp's blades reach %.2f from the stipe, past the 4.2 allowed for" % blade_reach)
# THE CANOPY, on the street's strands only: across the street no further than the road signs' legs
# and the blocks allow, and under the surface however it ripples.
for needle, why in (
    ("rng,\n\t\t\t\t\t\t\tdir, true)", "the street's kelp is not given the street's current and a canopy"),
    ("Vector3.new(frame.RightVector.X, 0, frame.RightVector.Z).Unit, false)", "the tank's kelp can be given a canopy"),
    ("local canopy = if marker:GetAttribute(\"Canopy\") == true then", "the client gives a canopy to strands not meant to have one"),
):
    if needle not in (CITY_SOURCE + CLIENT_SOURCE):
        fail(why)
canopy_down, ripple = table_number(KELP_T, "canopyDown"), table_number(KELP_T, "ripple")
fan = re.search(r"CANOPY_FAN = ([\d.]+)", SEALIFE)
if canopy_down is None or ripple is None or not fan or "Sea_KelpCanopy" not in EXT:
    fail("cannot find how the kelp's canopy is set on its stipe")
else:
    across = max(abs(ext("Sea_KelpCanopy", "lo", 1)), abs(ext("Sea_KelpCanopy", "hi", 1)))
    canopy_reach = 0.3 * (2 + 0.03 * K["FLOOR_DEPTH"]) + across + 0.3
    if K["KELP_KERB"] - 1 - canopy_reach < leg_face + 0.3:
        fail("the kelp's canopy reaches %.1f in, where the road signs' legs stand at %.1f"
             % (K["KELP_KERB"] - 1 - canopy_reach, leg_face))
    if K["KELP_KERB"] + 1 + canopy_reach > K["BOULEVARD_HALF"] + M["LOT_BITE"]:
        fail("the kelp's canopy reaches into the blocks")
    # The fronds ripple on four bones along them, each by `ripple` a beat behind the last.
    edges = [0.0, 3.0, 6.0, 9.0, ext("Sea_KelpCanopy", "hi", 0)]
    rise = 0.0
    for step_ in range(360):
        phi = 2 * math.pi * step_ / 360
        bent, height_ = 0.0, 0.0
        for index in range(4):
            bent += ripple * math.sin(phi - 1.2 * (index + 1))
            height_ += (edges[index + 1] - edges[index]) * math.sin(bent)
            rise = max(rise, height_)
    # The street's strands top out 1.5 to 4 under the surface; the stipe's top stands canopyDown
    # under that, a sixth of a stud over it at worst for a chain stretched to its strand.
    under = 1.5 + canopy_down - 0.17 - ext("Sea_KelpCanopy", "hi", 2) - rise
    if under < 1.0:
        fail("the kelp's canopy comes up to %.2f under the surface as it ripples" % under)
# The worst of it is at the top of the tunnel's roof, over the sea floor where the strand stands, for
# the shortest strand (whose top is nearest) and the tallest (whose sway is widest).
roof_over_floor = K["FLOOR_DEPTH"] - K["TUNNEL_BELOW"] + K["TUNNEL_H"] + 0.4
tank_reach = max(kelp_reach(tall, min(1, roof_over_floor / tall)) for tall in (K["FLOOR_DEPTH"] - 9, K["FLOOR_DEPTH"] - 3))
if K["KELP_TUNNEL"] - tank_reach < K["TUNNEL_W"] / 2 + 0.4 + 0.3:
    fail("the tank's kelp sways into the tunnel's glass (%.1f of %.1f)" % (tank_reach, K["KELP_TUNNEL"]))
if K["KELP_TUNNEL"] > K["TANK_HALF"] - 3:
    fail("there is no room in the tank for kelp at KELP_TUNNEL")
deep = re.search(r"local DEEP_OUT, DEEP_DOWN = ([\d.]+), ([\d.]+)", CLIENT_SOURCE)
if not deep or "local head = localPart(holder, \"DeepHead\", Vector3.new(22, 16, 26), BODY, true)" not in CLIENT_SOURCE:
    fail("cannot find how far out what looks in at the window comes up")
elif 38 + kelp_reach(K["FLOOR_DEPTH"] - 3, 1) > float(deep.group(1)) - 13 - 0.5:
    fail("the kelp past the window reaches into what comes up to look in")
if 35 - kelp_reach(K["FLOOR_DEPTH"] - 9, (K["FLOOR_DEPTH"] - K["TUNNEL_BELOW"] + 5) / (K["FLOOR_DEPTH"] - 9)) < 20 + 7:
    fail("the kelp past the window reaches into the chest's rock")
if float(deep.group(1)) + 13 > K["WINDOW_DEEP"] + 22 if deep else False:
    fail("what looks in at the window comes up where the city may build")

# THE GLASS: tap it and it cracks, keep on and it breaks; the water comes up and everyone inside is
# washed out -- to the checkpoint in Chill, the start in Hardcore -- and then it is whole again.
tap = {name: float(value) for name, value in re.findall(r"^\t(\w+) = ([\d.]+),", (re.search(r"local TAP = \{(.*?)\n\}", CITY_SOURCE, re.S) or [None, ""])[1], re.M)}
if not (0 < tap.get("crack", 0) < tap.get("crack2", 0) < tap.get("breaks", 0)):
    fail("the glass does not crack, crack further and then break, in that order")
if tap.get("hold", 0) <= tap.get("rise", 0) + 3:
    fail("the flood drains before anyone inside could have been washed out")
for needle, why in (
    ("for _, connection in ipairs(glass(model, onTaken)) do", "attach does not hand the glass the way to send someone to the start"),
    ('(item.Name == "TunnelGlass" and item.Size.Y > 1)', "the tunnel's own panes cannot be tapped"),
    ("prompt.Parent = pane", "the panes have no prompt"),
    ("if isHardcore(player) then\n\t\t\tif onTaken then\n\t\t\t\tonTaken(player)", "a Hardcore player is not sent to the start by the flood"),
    ("root.CFrame = CFrame.new(state.checkpointPosition + Vector3.new(0, 4, 0))", "a Chill player is not sent back to the checkpoint by the flood"),
    ("inAny(zones, root.Position)", "the flood washes out people who are not inside"),
    ('model:SetAttribute("Flood", 0)', "the water never goes down"),
    ("pane.Transparency = was", "the broken pane never comes back"),
):
    if needle not in CITY_SOURCE:
        fail(why)
for needle, why in (
    ('GetAttributeChangedSignal("Flood")', "the client never sees the glass break"),
    ("local function startFlood", "nothing fills with water"),
    ("drowning", "being inside the flood looks like nothing"),
):
    if needle not in CLIENT_SOURCE:
        fail(why)

# THE AQUARIUM'S GLASS IS NOT GLASS: Roblox's Glass leaves out everything transparent behind it.
if "local PANE = Enum.Material.SmoothPlastic" not in CITY_SOURCE:
    fail("the aquarium's panes have no material of their own")
for name in ("TunnelGlass", "TankWater", "ViewingWindow"):
    for found in re.finditer(r'"%s"[^\n]*\n?[^\n]*' % name, CITY_SOURCE):
        if "Enum.Material.Glass" in found.group(0):
            fail("%s is Glass, which hides the tank's water, bubbles and specks behind it" % name)
# AND ICE IS NOT GLASS either, or it vanishes against the sea from above (MaterialAppearance).
APPEAR = (SRC / "Shared" / "MaterialAppearance.lua").read_text(encoding="utf-8")
ice = re.search(r"\tIce = \{(.*?)\n\t\}", APPEAR, re.S)
if not ice or "Enum.Material.Glass" in ice.group(1):
    fail("Ice is Glass again, so a sheet of it disappears over the water when you look down on it")

# THE RAIN'S STREAKS: Squash runs -3 to 3.
for value in re.findall(r"Squash = NumberSequence\.new\(([\d.]+)\)", CLIENT_SOURCE):
    if float(value) > 3:
        fail("a Squash of %s is outside what Roblox allows" % value)


# THE THING ON THE HORIZON COMES UP IN OPEN SEA: past the city's edge and past the lone towers on its
# side, which stop at FAR_OPEN, however wide it is at its widest.
if "route.points[1] + route.forward * (route.total / 2) + route.side * LEVIATHAN_OUT" not in CITY_SOURCE:
    fail("the thing on the horizon is not laid in the city's own frame, so the city's edge says nothing about it")
if "CITY_SIDE + (if sign > 0 then FAR_OPEN else 700)" not in CITY_SOURCE:
    fail("the lone towers no longer stop short on the thing's side")
girth = re.search(r"local girth = ([\d.]+) \+ ([\d.]+) \* math\.sin", CLIENT_SOURCE)
if not girth:
    fail("cannot find how wide the thing on the horizon is")
else:
    half_width = (float(girth.group(1)) + float(girth.group(2))) / 2
    TOWER_HALF = 40 / math.sqrt(2)
    gap = K["LEVIATHAN_OUT"] - half_width - (K["CITY_SIDE"] + K["FAR_OPEN"] + TOWER_HALF)
    if gap < 40:
        fail("the thing on the horizon comes up %.0f from the nearest lone tower" % gap)

# THE CLIENT: the rain is eased before the mood reads it, and leaving the level takes the weather.
if CLIENT_SOURCE.find("local rain = 0") < 0 or CLIENT_SOURCE.find("local rain = 0") > CLIENT_SOURCE.find(
        "local function applyMood"):
    fail("applyMood reads `rain` before it is declared, which in Luau is a nil global")
if "clearWeather()" not in CLIENT_SOURCE:
    fail("the rain and the thing on the horizon outlive the level")

# ===================================================================== this pass, the seventh

# NOTHING FLAT NEAR THE WATER'S OWN FACE. Every building either stands SURFACE_CLEAR out of the water
# or is plainly under it, with whatever it carries on top: a drowned block's parapet, a drowned
# warehouse's sawtooth, a church's nave roof, a house's ridge and chimney. Two flat faces at nearly
# one height flicker, and that was the green roofs.
CLEAR = K.get("SURFACE_CLEAR", 0)
if CLEAR < 2:
    fail("SURFACE_CLEAR is %.1f; a roof that near the surface flickers against it" % CLEAR)
tops = (
    ("local top = if stands then waterLevel + rng:NextNumber(6, 30) else waterLevel - rng:NextNumber(5.2, 12)", 6, -5.2, 2.6,
     "a block of flats"),
    ("local top = if mayStand then waterLevel + rng:NextNumber(3.5, 9) else waterLevel - rng:NextNumber(6, 11)", 3.5, -6, 3.1,
     "a warehouse"),
)
for needle, stands_low, drowned_high, over, what in tops:
    if needle not in CITY_SOURCE:
        fail("%s's height has changed from what this check allows for: `%s`" % (what, needle))
    if stands_low < CLEAR or drowned_high + over > -CLEAR:
        fail("%s can stand within SURFACE_CLEAR of the surface" % what)
for needle, why in (
    ("local naveTop = waterLevel - 6", "the church's nave roof comes up near the surface"),
    ("local eaves = math.min(waterLevel - rng:NextNumber(10, 32), waterLevel - rise - 2 - SURFACE_CLEAR)",
     "a house's ridge or chimney can come up out of the water"),
    ("if top > waterLevel + 1 then\n\t\tfor _, strip in ipairs({ { d / 2 + 0.25, 0, 0.5, w + 1 }",
     "the weed band is a slab across the building again, which lies ON the water"),
    ("frame * CFrame.new(strip[1], waterLevel - 1.65 - floorY, strip[2]), algae)", "the weed band reaches the surface"),
    ("frame * CFrame.new(strip[1], waterLevel + 0.35 - floorY, strip[2]), Color3.fromRGB(226, 238, 234)",
     "the foam lies in the water's own face"),
    ("CFrame.new(mat.X, waterLevel + 0.25, mat.Z)", "the weed mats lie in the water's own face"),
    ("local clearOfRoute = nearCentre - depth / 2 >= EMERGE_CLEAR + ROUTE_REACH",
     "which lots may stand is judged from where the block started, so the street's front row drowns again"),
):
    if needle not in CITY_SOURCE:
        fail(why)
# (The weed band: from 3 studs down to a third of one under: 1.65 +/- 2.7 / 2.)
if -1.65 + 2.7 / 2 > -0.25:
    fail("the weed band comes within a quarter of a stud of the surface")

# FACADES ALL THE WAY DOWN near the street, bounded.
facade_floors = K.get("FACADE_FLOORS", 99)
if facade_floors > 16:
    fail("FACADE_FLOORS is %d; a facade of that many storeys on every near building is a part count" % facade_floors)

# THE STREET'S THINGS stay inside the road signs' legs (vehicles) and on the pavement edge
# (furniture); none stands where a leg comes down.
street = dict(re.findall(r"(\w+) = ([\d.]+)", (re.search(r"local ROADSIDE = \{(.*?)\}", CITY_SOURCE) or [None, ""])[1]))
lane = float(street.get("vehicleLane", 99))
car_reach = 6.5 * math.sin(0.25) + 2.8 * math.cos(0.25)
bus_reach = 17 * math.sin(0.25) + 4.2 * math.cos(0.25)
if lane + car_reach > leg_face - 0.5 or 22 + bus_reach > leg_face - 0.5:
    fail("a vehicle reaches the road signs' legs")
if lane + car_reach > K["KELP_KERB"] - 1 - street_reach:
    fail("a vehicle stands in the kerb's kelp")
for needle in ('if big then rng:NextNumber(10, 22) else rng:NextNumber(10, ROADSIDE.vehicleLane)',
               "* CFrame.Angles(0, rng:NextNumber(-0.25, 0.25), 0), rng, big)", "if not byGantry(s) then",
               "if index % 2 == 0 and rng:NextNumber() < 0.7 and not byGantry(s) then"):
    if needle not in CITY_SOURCE:
        fail("the street's vehicles or furniture are placed differently from what this check allows for: `%s`" % needle)
furniture_at = float(street.get("furnitureAt", 0))
lamp_face = K["BOULEVARD_HALF"] - M["LAMP_IN"] - M["LAMP_D"] / 2
if not (lamp_face + 1 > furniture_at - 2 and furniture_at + 6 < K["BOULEVARD_HALF"] + M["LOT_BITE"]):
    fail("the street's furniture is not on the pavement edge")

# THE ANIMALS, near the top: nothing but the dolphins' leap and a turtle's breath breaks the surface,
# and the dolphins' leap stays under every chunk.
for needle in ('local depth = if kind == "jelly" then rng:NextNumber(3.5, 7)',
               'elseif kind == "dolphins" then rng:NextNumber(4, 6)',
               'elseif kind == "turtle" then rng:NextNumber(5, 10)',
               'elseif kind == "ray" or kind == "shark" then rng:NextNumber(7, 16)',
               'local bob = if kind == "jelly" then 1.2 elseif kind == "dolphins" then 1 elseif kind == "turtle" then 2 else 3',
               'marker:SetAttribute("Bob", bob)'):
    if needle not in CITY_SOURCE:
        fail("the animals' depths have changed from what this check allows for: `%s`" % needle)
# Each one's top over its middle, part-built or mesh, whichever is higher: the mesh jellyfish's
# bell lifts a quarter stud as it pulls, and the mesh dolphin's fin sways with the first bone of
# its back, measured here from the far corner of its box to be sure.
DOLPHIN_BEAT = swim_list("dolphinBeat")
fin_sway = (math.hypot(ext("Sea_Dolphin", "hi", 1) - ext("Sea_Dolphin", "lo", 1), ext("Sea_Dolphin", "hi", 2))
            * math.sin(DOLPHIN_BEAT[0] if DOLPHIN_BEAT else 1.0))
for kind, shallowest, bob, over in (("jelly", 3.5, 1.2, max(0.9 * 1.12 * scale.get("jelly", 0), ext("Sea_Jelly", "hi", 2) + 0.25)),
                                    ("turtle", 5, 2, max(0.75 * scale.get("turtle", 0), ext("Sea_TurtleShell", "hi", 2))),
                                    ("dolphins", 4, 1, max(0.9 + 0.65, ext("Sea_Dolphin", "hi", 2) + fin_sway)),
                                    ("ray", 7, 3, max((0.15 + 1.5 * math.sin(0.45)) * RAY, ext("Sea_Ray", "hi", 2), ray_tip)),
                                    ("shark", 7, 3, max((1.9 + 1.2) * scale.get("shark", 0), ext("Sea_Shark", "hi", 2)))):
    if shallowest - bob - over < 0.5:
        fail("a %s can come up to %.1f under the surface when it is not meant to" % (kind, shallowest - bob - over))
leap = re.search(r"local LEAP_EVERY, LEAP_LONG, LEAP_HIGH = ([\d.]+), ([\d.]+), ([\d.]+)", CLIENT_SOURCE)
if not leap:
    fail("cannot find how high the dolphins leap")
else:
    # THE LEAP, drawn as the client draws it: the arc tops out LEAP_HIGH over the water from wherever
    # the dolphin is (its bob and its place in the pod included), and it points along the arc,
    # judged over the fifth of a second ahead as if it went at least pitchRun along in it, never
    # steeper than SWIM.pitch. What reaches highest is the fin, or the beak or the flukes when it
    # points up or down; part-built and mesh both.
    high, long_leap = float(leap.group(3)), float(leap.group(2))
    pitch_max, pitch_run = table_number(SWIM_T, "pitch"), table_number(SWIM_T, "pitchRun")
    if pitch_max is None or pitch_run is None:
        fail("cannot find how steeply a leaping dolphin points")
    else:
        # The points that can be highest, (forward of the middle, up): the fin's top, the beak's tip
        # and the flukes' tips -- the part-built pod's from its pieces, the mesh's from what was built.
        if "(0, -0.95, 2.0)" not in SEALIFE:
            fail("the mesh dolphin's fin is not where this check puts it")
        points = [(-0.4, 1.55), (4.35, 0.075), (-3.95, 0.075),
                  (-0.95, ext("Sea_Dolphin", "hi", 2) + fin_sway), (ext("Sea_Dolphin", "hi", 1), 0.02),
                  (ext("Sea_Dolphin", "lo", 1), 0.05)]
        worst_leap = 0.0
        for depth_x10 in range(int((4 - 1 - 0.4) * 10), int((6 + 1) * 10) + 1):
            under_ = depth_x10 / 10
            for step_ in range(401):
                u = step_ / 400
                y = (under_ + high) * math.sin(math.pi * u) - under_
                u2 = u + 0.2 / long_leap
                y2 = (under_ + high) * math.sin(math.pi * u2) - under_ if u2 < 1 else -under_
                pitch = max(-pitch_max, min(pitch_max, math.atan((y2 - y) / pitch_run)))
                for along_, up in points:
                    worst_leap = max(worst_leap, y + up * math.cos(pitch) + along_ * math.sin(pitch))
        if worst_leap > 7.0 - 1:
            fail("a leaping dolphin reaches %.1f over the water, and the chunks' undersides are at 7" % worst_leap)

# GULLS: over the street's middle, above every chunk, short of the buildings either side.
gull = dict(re.findall(r"(\w+) = ([\d.]+)", (re.search(r"local GULL = \{(.*?)\}", CITY_SOURCE) or [None, ""])[1]))
gull_low, gull_out, gull_radius = float(gull.get("low", 0)), float(gull.get("out", 99)), float(gull.get("radius", 99))
GULL_SPAN = max((0.5 + 1.7 + 1.9) * 1.4, max(abs(ext("Sea_GullWings", "lo", 0)), ext("Sea_GullWings", "hi", 0)))
if gull_out + gull_radius + GULL_SPAN > K["BOULEVARD_HALF"] + M["LOT_BITE"] - 2:
    fail("a gull's circle reaches the buildings either side of the street")
if "blocked(centre, radius + 6)" not in CITY_SOURCE or "local GULL_SIZE = 1.4" not in CLIENT_SOURCE:
    fail("the gulls are placed or drawn differently from what this check allows for")
route_top = 0.0
for label_, count_ in LEVEL.runs:
    for seed_ in range(0, 120, 7):
        radius_, chunks_, finish_y_ = LEVEL.lay(count_, seed_)
        water_ = heights(chunks_)["water"]
        for ch_ in chunks_:
            route_top = max(route_top, ch_["y"] + max(b.y + b.sy / 2 for b in LAYOUTS[ch_["id"]]) - water_)
if gull_low - 1.5 - GULL_SPAN * 0.4 < route_top + 3:
    fail("a gull flies as low as %.0f over the water and the chunks reach %.0f" % (gull_low - 1.5, route_top))

# THE FLOODED FLOOR you can swim down to: above the kill plane, its water cleared with the level.
worst_fall = min(r["fall"] for r in report.values())
if K.get("FLOODED_DEPTH", 99) > worst_fall - 8:
    fail("the flooded floor under the flat is %.0f down and the kill plane %.0f" % (K.get("FLOODED_DEPTH", 99), worst_fall))
for needle, why in (
    ("SunkenCityService.clearWater()\n\twaterLevel = h.water", "a new build does not clear the last one's water first"),
    ("table.clear(arrivedAt)\n\t\tSunkenCityService.clearWater()", "the level's undo leaves its water in the world"),
    ("workspace.Terrain:FillBlock(region.cf, region.size + Vector3.new(6, 6, 6), Enum.Material.Air)",
     "clearing the water does not take it all"),
):
    if needle not in CITY_SOURCE:
        fail(why)
if "FloodedDoor" in CITY_SOURCE:
    fail("the flooded floor's doorway is shut again")

# THE WHIRLPOOL is not Glass, its water flows, and the client moves it.
if re.search(r'"Whirl", Vector3[^\n]*\n[^\n]*\n[^\n]*\n\s*tone, Enum\.Material\.Glass', CITY_SOURCE):
    fail("the whirlpool's rings are Glass again, so each one hides the others")
if "CollectionService:AddTag(piece, \"SunkenWhirlFlow\")" not in CITY_SOURCE:
    fail("the whirlpool's water does not flow")

# THE CLIENT: every piece of a frame guarded, and a report of what it drew.
step_body = CLIENT_SOURCE[CLIENT_SOURCE.find("local function step(dt: number)"):]
step_body = step_body[:step_body.find("\nend\n")]
for piece in ("moveRider", "thingFrame", "moveSmallThings", "moveSwimmers", "moveKelp", "moveGulls", "moveWhirlFlow", "moveFerris",
              "moveSurface", "moveLights", "stepFlood", "stepBell", "stepRain", "stepLeviathan", "stepStrange", "stepDeep"):
    if ", %s" % piece not in step_body:
        fail("the frame calls %s unguarded, so if it throws everything after it stops" % piece)
if "guard(\"setting up \" .. tag, added, item)" not in CLIENT_SOURCE or "local function reportLater" not in CLIENT_SOURCE:
    fail("the client no longer guards its tags or reports what it drew")
# NOTHING A FRAME SEARCHES THE GAME. Every function the frame runs, and the mood it writes, works from
# the tables the tags filled: a GetTagged or a GetDescendants in one of them is a new table and a walk
# of the game sixty times a second (applyMood did exactly that with the ambient sounds).
per_frame = set(re.findall(r'guard\("[^"]*", (\w+)', step_body)) | {"applyMood", "moveThing"}
for name in sorted(per_frame):
    found = re.search(r"\nlocal function %s\(.*?\n(.*?)\nend\n" % name, CLIENT_SOURCE, re.S)
    if found and re.search(r"GetTagged\(|GetDescendants\(", found.group(1)):
        fail("%s runs every frame and searches the game (GetTagged or GetDescendants) each time" % name)
if "if key == moodWritten and shade then" not in CLIENT_SOURCE:
    fail("the mood is written every frame whether it has changed or not")

# THE SIZES SeaRig expects are the sizes the generators build (Blender x, y, z arrive as x, z, y).
for name, x, y, z in re.findall(r"(\w+) = Vector3\.new\(([\d.]+), ([\d.]+), ([\d.]+)\)",
                                (re.search(r"SeaRig\.SIZE = \{(.*?)\n\}", RIG_SOURCE, re.S) or [None, ""])[1]):
    if name not in EXT:
        fail("SeaRig expects %s, which neither generator reports building" % name)
        continue
    lo, hi = EXT[name]["box_lo"], EXT[name]["box_hi"]
    built = (hi[0] - lo[0], hi[2] - lo[2], hi[1] - lo[1])
    if any(abs(a - float(b)) > 0.05 for a, b in zip(built, (x, y, z))):
        fail("SeaRig expects %s at %s x %s x %s and it is built %.1f x %.1f x %.1f" % ((name, x, y, z) + built))
for name in ("Sea_Kelp", "Sea_KelpCanopy", "Sea_FishLarge", "Ferris_Wheel", "Ferris_Frame", "Ferris_Gondola"):
    if name not in EXT:
        fail("%s is not in blender/sealife_extents.json: run gen_sealife.py and gen_ferris.py" % name)

# THE FERRIS WHEEL: the generator and the service agree on it, its frame stands on the floor, and
# on every run there is somewhere along the street for its square.
ferris_t = re.search(r"local FERRIS = \{(.*?)\n\}", CITY_SOURCE, re.S)
F = {k_: float(v_) for k_, v_ in re.findall(r"\b(\w+) = ([\d.]+)", ferris_t.group(1))} if ferris_t else {}
F_SHARES = [float(v_) for v_ in re.search(r"shares = \{ ([\d., ]+) \}", ferris_t.group(1)).group(1).split(",")] if ferris_t else []
G_ = {k_: float(v_) for k_, v_ in re.findall(r"^(RADIUS|INNER|HALF_WIDTH|CABINS|FRAME_DOWN|HANG) = ([\d.]+)", FERRIS_GEN, re.M)}
if not F or not F_SHARES or len(G_) < 6:
    fail("cannot find the Ferris wheel's numbers in SunkenCityService or gen_ferris.py")
else:
    if G_["FRAME_DOWN"] != K["FLOOR_DEPTH"] + F["hub"]:
        fail("the Ferris wheel's frame reaches %.0f down and its axle stands %.0f over a floor %.0f under the water: "
             "it would not stand on the floor" % (G_["FRAME_DOWN"], F["hub"], K["FLOOR_DEPTH"]))
    for gen_name, lua_name in (("RADIUS", "radius"), ("HANG", "hang"), ("CABINS", "cabins")):
        if G_[gen_name] != F[lua_name]:
            fail("gen_ferris.py's %s is %s and SunkenCityService's FERRIS.%s is %s"
                 % (gen_name, G_[gen_name], lua_name, F[lua_name]))
    cabin_half = max(ext("Ferris_Gondola", "hi", 0), ext("Ferris_Gondola", "hi", 1))
    ferris_reach = max(reach_of("Ferris_Frame"), reach_of("Ferris_Wheel"), math.hypot(cabin_half, G_["RADIUS"] + cabin_half))
    if ferris_reach > F["reach"]:
        fail("the Ferris wheel reaches %.1f from its middle and FERRIS.reach allows %.0f" % (ferris_reach, F["reach"]))
    if F["reach"] > F["clear"]:
        fail("the Ferris wheel's square is smaller than the wheel")
    if F["hub"] - G_["RADIUS"] - G_["HANG"] - ext("Ferris_Gondola", "hi", 2) < -(K["FLOOR_DEPTH"] - 2):
        fail("the Ferris wheel's lowest cabin reaches the floor")
    if "local near, away = nearRoute(route, spot)" not in CITY_SOURCE or \
            "near - FERRIS.reach >= EMERGE_CLEAR + ROUTE_REACH" not in CITY_SOURCE or \
            "if ferrisAt and Vector3.new(point.X - ferrisAt.X, 0, point.Z - ferrisAt.Z).Magnitude < reach + FERRIS.clear then" not in CITY_SOURCE:
        fail("the Ferris wheel is placed without keeping off the route, or the city is not kept off it")
    for label_, count_ in LEVEL.runs:
        for seed_ in range(0, 120, 7):
            radius_, chunks_, finish_y_ = LEVEL.lay(count_, seed_)
            route_ = route_of(radius_, chunks_, finish_y_)
            ch_ = aquarium_checkpoint(chunks_)
            aq_ = aquarium(radius_, ch_) if ch_ is not None else None
            fch_ = flat_checkpoint(chunks_, ch_)
            fl_ = flat(radius_, fch_) if fch_ is not None else None
            pa_, pd_ = along_route(route_, route_["total"] * 0.34)

            def claimed(point, reach, plaza_side):
                # As `blocked` does.
                if aq_ is not None:
                    a_, b_ = aq_["tower"], aq_["far"]
                    run_ = (b_[0] - a_[0], b_[1] - a_[1])
                    l_ = math.hypot(*run_) or 1.0
                    t_ = min(max(((point[0] - a_[0]) * run_[0] + (point[1] - a_[1]) * run_[1]) / l_, 0), l_)
                    if math.dist(point, (a_[0] + run_[0] / l_ * t_, a_[1] + run_[1] / l_ * t_)) < reach + K["ROOM_W"] / 2 + 10:
                        return True
                if fl_ is not None and math.dist(point, fl_["centre"]) < reach + K["FLAT_REACH"]:
                    return True
                plaza_at = (pa_[0] - plaza_side * pd_[1] * M["PLAZA_OUT"], pa_[1] + plaza_side * pd_[0] * M["PLAZA_OUT"])
                return math.dist(point, plaza_at) < reach + K["PLAZA_RADIUS"] + 14

            # The wheel stands on the side AWAY from the plaza. This model's plan may be the service's
            # mirrored, so both ways round are tried, and each must find a clear spot.
            for side_ in (1, -1):
                found_ = False
                for share_ in F_SHARES:
                    s_ = route_["total"] * share_
                    at_, dir_ = along_route(route_, s_)
                    spot_ = (at_[0] - side_ * dir_[1] * F["out"], at_[1] + side_ * dir_[0] * F["out"])
                    near_, _ = near_route(route_, spot_)
                    if (s_ < route_["total"] - harbour_along(route_) - F["clear"]
                            and near_ - F["reach"] >= K["EMERGE_CLEAR"] + K["ROUTE_REACH"]
                            and not claimed(spot_, F["clear"], -side_)):
                        found_ = True
                        break
                if not found_:
                    fail("%s seed %d: nowhere along the street is clear for the Ferris wheel" % (label_, seed_))

# THE SERPENT: its body is the path's (SEGMENTS joints SPACING apart) and the service's girth, its
# reach is folded into monster_reach above, it turns off the path no further than the sway and the
# wander can turn it, and the client lays it on SunkenPath.body, level, whenever it is drawn.
SERPENT_GEN = (BLENDER / "gen_serpent.py").read_text(encoding="utf-8")
S_ = {k_: float(v_) for k_, v_ in re.findall(r"^(SEGMENTS|SPACING|GIRTH|SWAY_TURN) = ([\d.]+)", SERPENT_GEN, re.M)}
if len(S_) < 4 or "Sea_Serpent" not in EXT:
    fail("cannot find the serpent's numbers in gen_serpent.py, or it is not in sealife_extents.json")
else:
    if S_["SEGMENTS"] != P["SEGMENTS"] or S_["SPACING"] != P["SPACING"]:
        fail("gen_serpent.py builds %d joints %.0f apart and SunkenPath lays %d, %.0f apart"
             % (S_["SEGMENTS"], S_["SPACING"], P["SEGMENTS"], P["SPACING"]))
    if S_["GIRTH"] != K["MONSTER_GIRTH"]:
        fail("gen_serpent.py builds a girth of %.0f and the service's MONSTER_GIRTH is %.0f"
             % (S_["GIRTH"], K["MONSTER_GIRTH"]))
    turn = (2 * math.pi * P["SWAY"] / P["SWAY_WAVE"]) + (2 * math.pi * K["MONSTER_SWING"] / K["MONSTER_SWING_WAVE"])
    if math.atan(turn) > S_["SWAY_TURN"] + 0.005:
        fail("the thing turns up to %.2f off the path and gen_serpent.py measures its fluke at %.2f"
             % (math.atan(turn), S_["SWAY_TURN"]))
for needle, why in (
    ("SunkenPath.body(b, t, -0.5 * SPACING, SPACING, SEGMENTS + 1, thingPoints)",
     "the serpent is not laid on the path's own points"),
    ("SeaRig.follow(mesh.chain, mesh.rig.rest, joints, true, mesh.posed)",
     "the serpent is not kept level, so it rolls over where it turns back"),
    ("if b and (#segments > 0 or thingMesh) then", "the thing is only moved when it is built from parts"),
    ("function SunkenPath.body", "SunkenPath cannot give the whole body at once"),
):
    if needle not in CLIENT_SOURCE + PATH_SOURCE:
        fail(why)

# ===================================================================== report

for label, worst in report.items():
    print("%-6s street keeps %4.0f studs from itself, %d lots, frontages from %.0f; underside %.1f over the water, "
          "fall %.0f to the kill plane; the thing turns %.0f short of the whirlpool; pull %.0f short of the start; "
          "what hangs under a platform %.1f over the water"
          % (label, worst["apart"], worst["lots"], worst["street"], worst["water_gap"], worst["fall"],
             worst["vortex"], worst["start"], worst.get("hang", float("nan"))))
if problems:
    print("\nPROBLEMS:")
    for p in dict.fromkeys(problems):
        print("  " + p)
    sys.exit(1)
print("sunken city: the street goes somewhere and never meets itself, the blocks keep off it, falls seen and "
      "caught, the thing touches nothing, the aquarium and the pier fit, wiring present.")
