"""The Sunken City (Level 3): holds the level's shape to what SunkenCityService assumes.

Run with plain Python from the project root:  python blender/check_sunkencity.py

The city is built round a ring LevelService lays from random draws, so this lays the ring the way
LevelService does (ring_layout.py) for short, medium and long runs over many seeds, and checks:

  THE ROUTE STAYS OUT OF THE WATER: flat but for the swell, nothing in the pool climbs or drops, and
  every chunk's underside clears the surface.
  A FALL IS SEEN AND CAUGHT: the kill plane is well under the surface, so you go into the water before
  you are reset; the murk is under the kill plane; the aquarium's floor is above it; the drain's
  shaft ends well above the line where Roblox deletes a falling character.
  NOTHING BREAKS THE SURFACE NEAR THE ROUTE: the bands of lots start beyond the route's reach plus
  EMERGE_CLEAR, and ROUTE_REACH really is the widest chunk in the pool.
  THE THING NEVER TOUCHES ANYTHING: its body and sway stay inside the boulevard, clear of the gantry
  legs, under the road signs, clear of the aquarium's tower, away from the whirlpool's axis, and its
  harbour swerve stays inside the harbour sector and short of the buoys, quays, boat and crane.
  THE AQUARIUM AND THE PIER FIT: the tower clears the neighbouring chunks, no pier pile stands in the
  whirlpool, and the whirlpool's pull cannot reach the start of the route.
  THE WIRING IS THERE: Bootstrap builds it, attaches the drain, stands the finish line down and
  exempts a rider from the kill plane; the palette and the banner exist; the client starts, reads
  every attribute the server writes and follows every tag it sets; no Ball parts, no Neon.

Exits non-zero on any failure.
"""
import math
import re
import sys

from ring_layout import CONTRACTS, DESTROY_Y, LAYOUTS, SRC, chunk_rects, rect_distance, xmax
from sunkencity_layout import (CITY_SOURCE, CLIENT_SOURCE, K, LEVEL, M, MIRRORED, P, PATH_SOURCE, aquarium,
                               aquarium_checkpoint, bands, finale, flat, flat_checkpoint, heights, monster_radius,
                               monster_reach, wrap)

BOOT = (SRC / "Server" / "Bootstrap.server.lua").read_text(encoding="utf-8")
LIGHT = (SRC / "Server" / "Services" / "LightingService.lua").read_text(encoding="utf-8")
UI = (SRC / "Client" / "Services" / "UIService.lua").read_text(encoding="utf-8")
CLIENT_BOOT = (SRC / "Client" / "Bootstrap.client.lua").read_text(encoding="utf-8")

problems = []


def fail(message):
    problems.append(message)


# ===================================================================== the definition and its pool

if not LEVEL.has_ring:
    print("FAIL: Level3 has no ring")
    sys.exit(1)
for field, want in (("backdrop", "sunkenCity"), ("finale", "drain")):
    if LEVEL.field_text(field) != want:
        fail("Level3 has no %s = \"%s\"" % (field, want))
if LEVEL.step_scale != 0:
    fail("the Sunken City's ring takes steps (stepScale %.1f); it should stay near the water" % LEVEL.step_scale)
if not LEVEL.wave:
    fail("the Sunken City's ring has no swell")
else:
    height, every = LEVEL.wave
    if height * 2 * math.pi / every > 3:
        fail("the swell can lift the route %.1f studs from one chunk to the next, more than a comfortable jump"
             % (height * 2 * math.pi / every))
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
widest = max(LEVEL.pool_ids, key=xmax)
if xmax(widest) > K["ROUTE_REACH"] + 0.01:
    fail("%s reaches %.1f from the centre line, past ROUTE_REACH %.1f" % (widest, xmax(widest), K["ROUTE_REACH"]))
for text, (name, _) in MIRRORED.items():
    if text not in CITY_SOURCE:
        fail("sunkencity_layout.py restates %s from the Luau text `%s`, which is no longer there" % (name, text))
if "PartType.Ball" in "\n".join(l.split("--", 1)[0] for l in CITY_SOURCE.splitlines() + CLIENT_SOURCE.splitlines()):
    fail("the Sunken City uses Ball parts; a ball cannot be flattened, so use a sphere mesh")
for name, source in (("SunkenCityService", CITY_SOURCE), ("SunkenCityClient", CLIENT_SOURCE)):
    if "Enum.Material.Neon" in source:
        fail("%s uses Neon; this project lights nothing with fake light" % name)

# ===================================================================== the thing, against the fixed things

reach = monster_reach()
g_side, g_up, g_down = reach["side"], reach["up"], reach["down"]
top_of_thing = -(K["MONSTER_DEPTH"] - K["MONSTER_BOB"]) + g_up  # relative to the surface, at its highest
if K["MONSTER_INSET"] + g_side > K["BOULEVARD_HALF"] - 5:
    fail("the thing's body reaches %.1f inside the ring's centre line, past the boulevard" % (K["MONSTER_INSET"] + g_side))
leg = M["GANTRY_LEG"]
if leg - (K["MONSTER_INSET"] + g_side) < 3:
    fail("the thing passes within %.1f of a gantry leg" % (leg - (K["MONSTER_INSET"] + g_side)))
panel_w, panel_h, panel_x, panel_y = M["GANTRY_PANEL"]
panel_bottom = -M["GANTRY_BEAM_DEPTH"] + panel_y - panel_h / 2
if top_of_thing > panel_bottom - 1:
    fail("the thing's back reaches %.1f under the surface and the road signs hang to %.1f" % (top_of_thing, panel_bottom))
if -(K["MONSTER_DEPTH"] + K["MONSTER_BOB"]) - g_down < -K["FLOOR_DEPTH"] + 5:
    fail("the thing swims into the sea floor")
if K["HARBOUR_SWERVE_HALF"] + 0.05 > K["HARBOUR_SECTOR_HALF"]:
    fail("the harbour swerve is wider than the harbour, so the thing swims through buildings")
outer_most = -K["MONSTER_INSET"] + K["HARBOUR_SWERVE"] + g_side
buoy_from = K["BOULEVARD_HALF"] + K["EMERGE_CLEAR"] + M["BUOY_FROM"]
if buoy_from - outer_most < 8:
    fail("at the top of its swerve the thing comes within %.1f of a buoy's chain" % (buoy_from - outer_most))
quay_from = K["BOULEVARD_HALF"] + K["EMERGE_CLEAR"]
if -K["MONSTER_INSET"] + g_side > quay_from - 10:
    fail("the thing reaches the quays where they meet the boulevard")
# The boat and the crane: the swerve at their angles.
for name, share, out in (("boat", M["BOAT_ANGLE"], M["BOAT_OUT"]), ("crane", 0.05, M["CRANE_OUT"] - 16)):
    offset = share * 2 * math.pi
    half = K["HARBOUR_SWERVE_HALF"]
    swerve = 0 if abs(offset) >= half else K["HARBOUR_SWERVE"] * 0.5 * (1 + math.cos(math.pi * offset / half))
    if out - (-K["MONSTER_INSET"] + swerve + g_side) < 10:
        fail("the thing's swerve comes within 10 of the harbour's %s" % name)

# ===================================================================== the surfacing and the mirror

for name in ("SURFACE_EVERY", "WARN", "BREACH", "WASH_AT", "WASH_RADIUS", "CREST", "CREST_REACH", "QUIET_MARGIN", "SWAY"):
    if name not in P:
        fail("SunkenPath has no %s this check can read" % name)
if P["WARN"] + P["BREACH"] >= P["SURFACE_EVERY"]:
    fail("one surfacing runs into the next")
if P["WASH_AT"] >= P["BREACH"]:
    fail("the surge comes after the thing has gone back down")
if P["WARN"] < 4:
    fail("the surfacing gives only %.1f seconds of warning" % P["WARN"])
# The surge has to cover the route's full width over the spot, which is MONSTER_INSET inside it.
if P["WASH_RADIUS"] < K["MONSTER_INSET"] + K["ROUTE_REACH"] + 2:
    fail("the surge does not reach the far edge of the route over the spot")
if P["QUIET_MARGIN"] < 5:
    fail("a surfacing can come up within %.0f of a road sign's reach" % P["QUIET_MARGIN"])

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
steps = ("TimerService.resetTimer(player)", "syncTimer(player)", "PlayerFell:FireClient(player)", "restartRunFor(player)",
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
for label, count in LEVEL.runs:
    worst = {"radius": 0.0, "water_gap": math.inf, "fall": math.inf, "vortex": math.inf, "tower": math.inf,
             "start": math.inf, "aq_kill": math.inf, "shaft": math.inf, "span": 0.0}
    for seed in range(300):
        radius, chunks, finish_y = LEVEL.lay(count, seed)
        worst["radius"] = radius
        h = heights(chunks)
        kill = min(ch["y"] for ch in chunks) - 40

        # ----- the route out of the water, the fall seen and caught
        underside = min(ch["y"] + min(b.y - b.sy / 2 for b in LAYOUTS[ch["id"]]) for ch in chunks)
        worst["water_gap"] = min(worst["water_gap"], underside - h["water"])
        if underside - h["water"] < 1.5:
            fail("%s seed %d: a chunk's underside is %.1f above the water" % (label, seed, underside - h["water"]))
        worst["fall"] = min(worst["fall"], h["water"] - kill)
        if h["water"] - kill < 20:
            fail("%s seed %d: the kill plane is only %.1f under the surface" % (label, seed, h["water"] - kill))
        if h["murk"] > kill:
            fail("%s seed %d: the murk is above the kill plane, so a fall is reset inside it" % (label, seed))
        worst["aq_kill"] = min(worst["aq_kill"], h["tunnel"] + 3 - kill)
        if h["tunnel"] + 3 < kill + 6:
            fail("%s seed %d: the aquarium's floor is within reach of the kill plane" % (label, seed))
        worst["shaft"] = min(worst["shaft"], h["shaft"] - DESTROY_Y)
        if h["shaft"] < DESTROY_Y + 60:
            fail("%s seed %d: the drain's shaft ends at %.0f, too near the %d delete line" % (label, seed, h["shaft"], DESTROY_Y))

        # ----- the surfacing: its fins come through the surface and stay under the route
        fins = h["water"] - P["CREST"] + g_up
        if fins > underside - 1:
            fail("%s seed %d: surfacing, the thing's fins reach %.1f, within a stud of a chunk's underside at %.1f"
                 % (label, seed, fins - h["water"], underside - h["water"]))

        # ----- the bands of lots: anything that may break the surface is EMERGE_CLEAR beyond the reach
        for start, end, kind in bands(radius):
            near = start - (radius + K["ROUTE_REACH"]) if start > radius else (radius - K["ROUTE_REACH"]) - end
            if near < 5:
                fail("%s seed %d: a band of lots (%s) starts %.1f from the route's reach" % (label, seed, kind, near))
        if radius - K["ROUTE_REACH"] - K["EMERGE_CLEAR"] < M["CLOCK_SIDE"] / math.sqrt(2) + 2:
            fail("%s: the clock tower is within EMERGE_CLEAR of the route on a ring of %.0f" % (label, radius))

        # ----- the pier and the whirlpool
        fin = finale(radius, chunks, finish_y)
        vortex = fin["vortex"]
        rects = chunk_rects(radius, chunks)
        start_gap = min(rect_distance(r, vortex) for r in rects[: max(1, len(rects) // 2)])
        worst["start"] = min(worst["start"], start_gap - K["CAPTURE_R"])
        if start_gap < K["CAPTURE_R"] + 15:
            fail("%s seed %d: the whirlpool's pull reaches within %.0f of the route's start" % (label, seed,
                                                                                               start_gap - K["CAPTURE_R"]))
        for pile in fin["piles"]:
            if math.dist(pile, vortex) < K["VORTEX_R"] + 3 + 1.5:
                fail("%s seed %d: a pier pile stands in the whirlpool" % (label, seed))
        if K["VORTEX_GAP"] < K["CAPTURE_R"] - 0.01:
            fail("the whirlpool's pull reaches back over the pier")
        harbour = math.atan2(vortex[1], vortex[0])
        for step in range(720):
            theta = step / 720 * 2 * math.pi
            r = monster_radius(radius, theta, harbour)
            point = (math.cos(theta) * r, math.sin(theta) * r)
            gap = math.dist(point, vortex) - g_side
            worst["vortex"] = min(worst["vortex"], gap)
            if gap < 25:
                fail("%s seed %d: the thing passes within %.0f of the whirlpool's axis" % (label, seed, gap))
                break

        # ----- the aquarium
        ch = aquarium_checkpoint(chunks)
        if ch is None:
            fail("%s seed %d: no checkpoint for the aquarium" % (label, seed))
        else:
            aq = aquarium(radius, ch)
            theta = math.atan2(aq["tower"][1], aq["tower"][0])
            if abs(wrap(theta - harbour)) < K["HARBOUR_SECTOR_HALF"] + 0.1:
                fail("%s seed %d: the aquarium is in the harbour" % (label, seed))
            tower_r = math.hypot(*aq["tower"])
            clear = (tower_r - K["ROT_R"]) - (monster_radius(radius, theta, harbour) + g_side)
            worst["tower"] = min(worst["tower"], clear)
            if clear < 6:
                fail("%s seed %d: the thing passes within %.1f of the aquarium's tower" % (label, seed, clear))
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
        # ----- the dry flat
        fch = flat_checkpoint(chunks, ch)
        if fch is None:
            fail("%s seed %d: no checkpoint for the dry flat" % (label, seed))
        else:
            fl = flat(radius, fch)
            theta = math.atan2(fl["centre"][1], fl["centre"][0])
            if abs(wrap(theta - harbour)) <= K["HARBOUR_SECTOR_HALF"]:
                fail("%s seed %d: the dry flat's checkpoint is in the harbour, so there is no flat" % (label, seed))
            for r in rects:
                if r["name"] == "chunk %d" % fch["index"]:
                    continue
                for x in (fl["x"][0], fl["x"][1]):
                    for z in (fl["z"][0], fl["z"][1], 0):
                        corner = (fl["edge"][0] + fl["out"][0] * x + fl["along"][0] * z,
                                  fl["edge"][1] + fl["out"][1] * x + fl["along"][1] * z)
                        if rect_distance(r, corner) < 1.5:
                            fail("%s seed %d: the dry flat touches %s" % (label, seed, r["name"]))
            inner_face = math.hypot(*fl["edge"]) + K["FLAT_GANG"]
            if inner_face - (monster_radius(radius, theta, harbour) + g_side) < 5:
                fail("%s seed %d: the thing passes within 5 of the dry flat" % (label, seed))
            drop = fl["landing_y"] - (h["water"] - 1.5)
            if not (8 <= drop <= 30):
                fail("%s seed %d: the dry flat's stair goes down %.0f to the water" % (label, seed, drop))
            if ch is not None and math.dist(fl["centre"], aquarium(radius, ch)["tower"]) < 60:
                fail("%s seed %d: the dry flat and the aquarium stand within 60 of each other" % (label, seed))
        last = chunks[-1]
        worst["span"] = max(worst["span"], (last["angle"] + (last["length"] + K["PIER_L"] + K["VORTEX_GAP"]) / radius)
                            / (2 * math.pi))
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
if "sunkenCity = {" not in LIGHT:
    fail("LightingService has no sunkenCity palette")
if '[3] = { name = "The Sunken City"' not in UI:
    fail("UIService's finale banner for level 3 is not the Sunken City's")
if '"SunkenCityClient"' not in CLIENT_BOOT:
    fail("the client Bootstrap never starts SunkenCityClient, so the thing never swims")
written = set(re.findall(r'sea:SetAttribute\("(\w+)"', CITY_SOURCE))
readers = CLIENT_SOURCE + PATH_SOURCE
read = set(re.findall(r'num\("(\w+)"\)', readers)) | set(re.findall(r'GetAttribute\("(\w+)"\)', readers))
for name in sorted(written - read):
    fail("SunkenCityService writes %s for the thing and SunkenCityClient never reads it" % name)
for name in sorted((read - written) - {"Centre", "Spin", "Pivot", "Count", "Radius", "Speed", "BaseVolume"}):
    fail("SunkenCityClient reads %s and SunkenCityService never writes it" % name)
tags = set(re.findall(r'AddTag\([^,]+,\s*"(\w+)"\)', CITY_SOURCE))
server_reads = set(re.findall(r'tagged\(model, "(\w+)"\)', CITY_SOURCE))
for tag in sorted(tags):
    if '"%s"' % tag not in CLIENT_SOURCE and tag not in server_reads:
        fail("SunkenCityService tags %s and nothing ever looks for it" % tag)
if 'require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SunkenPath"))' not in CLIENT_SOURCE \
        or 'WaitForChild("SunkenPath")' not in CITY_SOURCE:
    fail("the server and the client do not both use the shared SunkenPath, so they can disagree about the thing")
sky_attach = block[block.find("SunkenCityService.attach("):] if block else ""
if "sendBackToStart(player)" not in sky_attach:
    fail("Bootstrap does not hand the city sendBackToStart, so the surge takes nobody")

# ===================================================================== report

for label, worst in report.items():
    print("%-6s ring %4.0f, route + pier to %.2f of a turn; underside %.1f over the water, fall %.0f to the kill "
          "plane; the thing %.0f from the whirlpool and %.1f from the tower; pull %.0f short of the start"
          % (label, worst["radius"], worst["span"], worst["water_gap"], worst["fall"], worst["vortex"], worst["tower"],
             worst["start"]))
if problems:
    print("\nPROBLEMS:")
    for p in dict.fromkeys(problems):
        print("  " + p)
    sys.exit(1)
print("sunken city: route out of the water, falls seen and caught, nothing breaks the surface near the route, "
      "the thing touches nothing, the aquarium and the pier fit, wiring present.")
