"""Static checks for the lobby hub.

    python check_hub.py

Separate from check_chunk_forms.py, which is about chunk geometry. Nothing here is
geometric: it is about whether the hub's data is complete, and whether the one constraint
sub-project C depends on still holds.
"""
import os
import math
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
LEVELS = os.path.join(ROOT, "src", "Shared", "LevelDefinitions.lua")
APPEARANCE = os.path.join(ROOT, "src", "Shared", "MaterialAppearance.lua")
LEVEL_SERVICE = os.path.join(ROOT, "src", "Server", "Services", "LevelService.lua")
HUB_SERVICE = os.path.join(ROOT, "src", "Server", "Services", "HubService.lua")
DIVE_SERVICE = os.path.join(ROOT, "src", "Server", "Services", "DiveFinaleService.lua")
BOOTSTRAP = os.path.join(ROOT, "src", "Server", "Bootstrap.server.lua")

failures = []


def fail(where, message):
    failures.append("%-22s %s" % (where, message))


def read(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


# A PAD IS MADE OF ITS LEVEL'S HEADLINE MATERIAL, and that cannot be derived.
#
# The obvious source is allowedMaterials[1], and it is wrong: Level1 and Level2 both start
# with Honey, so two of the three pads would come out identical and the room would say the
# two levels are the same thing. It is declared per level instead, and checked here for
# existence and for uniqueness, because a duplicate is exactly the failure that would ship
# looking fine.
def check_headline_materials():
    text = read(LEVELS)
    appearances = set(re.findall(r"^\t(\w+) = \{", read(APPEARANCE), re.M))

    seen = {}
    for level in re.finditer(r"^LevelDefinitions\.(\w+) = \{(.*?)^\}", text, re.S | re.M):
        name, body = level.group(1), level.group(2)
        if "levelId" not in body:
            continue
        found = re.search(r'headlineMaterial = "(\w+)"', body)
        if not found:
            fail(name, "has no headlineMaterial. The hub builds its pad out of it.")
            continue
        material = found.group(1)
        if material not in appearances:
            fail(name, "headlineMaterial '%s' is not in MaterialAppearance." % material)
        if material in seen:
            fail(name, "headlineMaterial '%s' is already used by %s. Two pads of the same "
                       "material read as two of the same level." % (material, seen[material]))
        seen[material] = name


# THE LEVEL ORIGIN HAS TO BE A PARAMETER, not a constant.
#
# It is the in-server half of sub-project C and the reason the hub and a run can exist at
# once. Checked rather than trusted because the three positions built from SPIRAL_RADIUS are
# easy to add a fourth to and forget: a chunk placed relative to the origin while the spawn
# is not puts players next to the level instead of on it.
def check_level_origin():
    text = read(LEVEL_SERVICE)

    signature = re.search(r"function LevelService\.startLevel\(([^)]*)\)", text)
    if not signature:
        fail("LevelService", "startLevel is missing entirely.")
        return
    if "origin" not in signature.group(1):
        fail("LevelService", "startLevel takes no origin parameter. The hub cannot place a "
                             "run beside itself without one.")

    for number, line in enumerate(text.splitlines(), 1):
        if "SPIRAL_RADIUS" not in line or line.strip().startswith("--"):
            continue
        if "local SPIRAL_RADIUS" in line or "angle +=" in line:
            continue
        if "base" not in line:
            fail("LevelService:%d" % number,
                 "positions from SPIRAL_RADIUS without the origin: %s" % line.strip())


# A RUN HAS TO BE DESTROYABLE, or the second one stacks on the first.
def check_end_level():
    text = read(LEVEL_SERVICE)
    if "function LevelService.endLevel(" not in text:
        fail("LevelService", "has no endLevel. Starting a second run would stack a second "
                             "spiral on the first, because startLevel clears only the "
                             "baseplate.")
    if "levelId = level.levelId" not in text:
        fail("LevelService", "startLevel does not return the level's own id. BestTimeService "
                             "and LeaderboardService both need it to file a time against the "
                             "right key.")


# THE SELECTION MUST BE PURE DATA, and this is the check sub-project C depends on.
#
# When multiple servers land, HubService.beginRun stops building locally and hands the
# RunRequest to TeleportService:TeleportToPrivateServer as teleport data. Teleport data is
# serialised, so an Instance in that table cannot cross, and C would mean rewriting the hub
# rather than extending it. The constraint is invisible until the day it is expensive, which
# is exactly the kind that gets checked.
INSTANCE_TYPES = ("BasePart", "Part", "Model", "Instance", "Folder", "Player",
                  "CFrame", "Vector3", "Color3")


def check_run_request_is_pure_data():
    if not os.path.exists(HUB_SERVICE):
        fail("HubService", "does not exist yet.")
        return
    text = read(HUB_SERVICE)
    block = re.search(r"type RunRequest = \{(.*?)\}", text, re.S)
    if not block:
        fail("HubService", "declares no RunRequest type.")
        return
    for line in block.group(1).splitlines():
        field = re.match(r"\s*(\w+)\s*:\s*([\w \"|?]+),?\s*$", line)
        if not field:
            continue
        for banned in INSTANCE_TYPES:
            if re.search(r"\b" + banned + r"\b", field.group(2)):
                fail("HubService", "RunRequest.%s is typed %s. It has to be plain data that "
                                   "survives a teleport."
                     % (field.group(1), field.group(2).strip()))


# EVERY LEVEL THE HUB OFFERS NEEDS A PAD, and every pad needs a level.
#
# The two lists are built from the same source, so this looks redundant. It is not: the
# failure it catches is a level added to LevelDefinitions.All and never noticed by the hub,
# which is the exact shape of the bug that cost this project a play session when five chunks
# were added to ChunkDefinitions and never reached AllIds.
def check_hub_builds_pads():
    if not os.path.exists(HUB_SERVICE):
        return  # already reported by the RunRequest check
    text = read(HUB_SERVICE)
    if "function HubService.build(" not in text:
        fail("HubService", "has no build(). The room is never created.")
        return
    if "padLevels()" not in text.split("function HubService.build(")[1]:
        fail("HubService", "build() does not iterate padLevels(), so a level added to "
                           "LevelDefinitions.All would silently get no pad.")



# ============================================================ pads you can actually stand on
#
# The poses silently did nothing for a whole round of testing. Not because setPose was broken
# -- it was correct the entire time -- but because the pose keys sat at z = 16 with the length
# keys at z = 14, and a 5-stud key overlaps an 8-stud pad at that spacing. Three of the five
# keys were physically inside another pad and could never be touched.
#
# That is not a bug reading the code finds, because every line of the code is right. It is a
# geometry mistake, so it takes a geometry check: pull every touchable pad's centre and radius
# out of HubService and assert that no two of them swallow each other.
def check_pads_are_reachable():
    if not os.path.exists(HUB_SERVICE):
        return  # already reported by the RunRequest check
    text = read(HUB_SERVICE)
    pads = []

    # EVERY NUMBER HERE IS READ OUT OF THE SOURCE, not copied into it.
    #
    # The first version of this check hard-coded the layout, so the round that moved the pool,
    # the benches, the statue and all three pad rows left the checker verifying a room that no
    # longer existed -- and it passed, cheerfully, against coordinates nothing used any more.
    # A layout check that does not track the layout is worse than none: it reports safety.
    spacing = re.search(r"local PAD_SPACING = ([\d.]+)", text)
    row_z = re.search(r"Vector3\.new\(offset, [\d.]+, (-?[\d.]+)\)", text)
    if spacing and row_z:
        step, z = float(spacing.group(1)), float(row_z.group(1))
        # COUNTED, NOT ASSUMED. This said three, with a comment claiming a fourth could not
        # collide with anything. padLevels appends the Sandbox to LevelDefinitions.All, so
        # there have always been four -- and the fourth, at x = 36, is precisely where the
        # backrooms corridor was built. The check passed because it did not know the pad
        # existed, which is the worst way for a check to pass.
        # padLevels is LevelDefinitions.All plus the Sandbox, so counting the levelId lines in
        # the definitions file gives the real row width, whatever it grows to.
        count = len(re.findall(r"levelId = \d+", read(LEVELS)))
        # MIRRORS THE CAP THE CODE APPLIES. PAD_SPACING is the spacing the row WANTS, not the
        # spacing it gets: HubService narrows it when the row would otherwise overhang the
        # inlay, so reading the constant alone reports a row that is wider than the one built
        # and fails a layout that is actually fine.
        #
        # Duplicating the rule here is not ideal and is the price of checking source rather
        # than running it -- so the two are written to look alike, and this comment is the
        # pointer to the other half.
        pad_size = re.search(r"local PAD_SIZE = Vector3\.new\(([\d.]+),", text)
        floor_x = re.search(r"local FLOOR_SIZE = Vector3\.new\(([\d.]+),", text)
        if pad_size and floor_x and count > 1:
            room = float(floor_x.group(1)) / 2 - 5 - float(pad_size.group(1)) / 2
            step = min(step, room * 2 / (count - 1))
        for i in range(count):
            pads.append(("level %d" % (i + 1), (i - (count - 1) / 2) * step, z, 4.0))

    row_size = re.search(r"pad\.Size = Vector3\.new\([\d.]+, ([\d.]+),", text)
    row_r = float(row_size.group(1)) / 2 if row_size else 4.0
    for z in (float(v) for v in re.findall(r"^\t\tz = (-?[\d.]+),", text, re.M)):
        for i in range(3):
            pads.append(("option z=%g #%d" % (z, i + 1), i * 12.0 - 12.0, z, row_r))

    key_size = re.search(r"key\.Size = Vector3\.new\([\d.]+, ([\d.]+),", text)
    key_r = float(key_size.group(1)) / 2 if key_size else 2.5
    poses = re.search(r"local POSE_ORDER = (\{[^}]*\})", text)
    layout = re.search(
        r"Vector3\.new\((-?[\d.]+) \+ \(index - 1\) \* ([\d.]+), [\d.]+, (-?[\d.]+)\)", text)
    if poses and layout:
        start, step, z = (float(v) for v in layout.groups())
        for i in range(len(re.findall(r'"\w+"', poses.group(1)))):
            pads.append(("pose %d" % (i + 1), start + i * step, z, key_r))

    start_pad = re.search(r"startPad\.Position = HUB_ORIGIN \+ Vector3\.new\((-?[\d.]+), [\d.]+, (-?[\d.]+)\)", text)
    if start_pad:
        pads.append(("start pad", float(start_pad.group(1)), float(start_pad.group(2)), 7.0))

    statue = re.search(r"stand\.Position = HUB_ORIGIN \+ Vector3\.new\((-?[\d.]+), [\d.]+, (-?[\d.]+)\)", text)
    if statue:
        pads.append(("statue plinth", float(statue.group(1)), float(statue.group(2)), 4.3))

    # Planters and benches, from the two lists that place them. Radii are generous on purpose:
    # these are rectangles being treated as circles, so the check errs toward complaining.
    planters = re.search(r"for _, offset in ipairs\(\{\n(.*?)\n\t\}\) do", text, re.S)
    if planters:
        for x, z in re.findall(r"Vector3\.new\((-?[\d.]+), 0, (-?[\d.]+)\)", planters.group(1)):
            pads.append(("planter", float(x), float(z), 3.8))

    # THE BACKROOMS CORRIDOR, which is fourteen studs long plus a nine-stud turn and is the
    # largest single object in the room. It was never in this list, so every placement of it
    # was checked by eye -- and it ended up growing out of a level pad.
    door = re.search(r"buildBackDoor\(HUB_ORIGIN \+ Vector3\.new\((-?[\d.]+), [\d.]+, (-?[\d.]+)\)", text)
    if door:
        dx, dz = float(door.group(1)), float(door.group(2))
        # SAMPLED ALONG ITS LENGTH, not bounded by one big circle. A corridor is 4.6 wide and
        # 14 long, and a circle that covers its length also covers seven studs of empty floor
        # either side of it -- which reported a clash with a pad that is nowhere near it, and
        # reported the corridor as clashing with its own turn.
        #
        # A row of small circles follows the shape instead. The two runs share a name so the
        # comparison below can skip pairs within the same object.
        for step in range(6):
            pads.append(("backrooms", dx + 2.0 + step * 2.4, dz, 2.5))
        for step in range(4):
            pads.append(("backrooms", dx + 11.0, dz - 3.0 - step * 2.4, 2.5))

    benches = re.search(r"for _, seat in ipairs\(\{\n(.*?)\n\t\}\) do", text, re.S)
    if benches:
        for x, z in re.findall(r"Vector3\.new\((-?[\d.]+), 0, (-?[\d.]+)\)", benches.group(1)):
            pads.append(("bench", float(x), float(z), 4.8))

    for a in range(len(pads)):
        for b in range(a + 1, len(pads)):
            na, xa, za, ra = pads[a]
            nb, xb, zb, rb = pads[b]
            # Two samples of the same object are not a clash with each other.
            if na == nb and na == "backrooms":
                continue
            gap = math.hypot(xa - xb, za - zb) - (ra + rb)
            # A pad you have to aim at gets reported as broken, so this wants real clearance
            # rather than merely not intersecting.
            if gap < 1.0:
                fail("HubService", "%s at (%g, %g) and %s at (%g, %g) leave %.2f studs "
                                   "between them, so at least one cannot be stepped on."
                                   % (na, xa, za, nb, xb, zb, gap))

    # NOTHING MAY OVERHANG THE DECK'S INLAY, which is the line the floor draws around itself.
    # A pad crossing it was reported as looking like a mistake, and it is: the inlay is what
    # tells you where the room ends.
    floor = re.search(r"local FLOOR_SIZE = Vector3\.new\(([\d.]+), [\d.]+, ([\d.]+)\)", text)
    if floor:
        half_x = float(floor.group(1)) / 2 - 5
        half_z = float(floor.group(2)) / 2 - 5
        for name, x, z, r in pads:
            if abs(x) + r > half_x or abs(z) + r > half_z:
                fail("HubService", "%s at (%g, %g) reaches past the deck inlay at %g x %g."
                                   % (name, x, z, half_x, half_z))


def check_level_fields():
    """Every level declares every field the other levels do.

    A LEVEL IS A DUCK-TYPED TABLE and nothing enforces its shape. Level4 shipped without
    `baseSeed`, and LevelService does `level.baseSeed + jobIdHash` -- so it generated
    perfectly in every offline check here and threw "attempt to perform arithmetic on nil"
    the instant somebody voted for it. `allowedMaterials`, `templates` and `parTime` were
    missing too, and would each have thrown in turn, one run at a time.

    There is no schema to check against, so the levels are checked against EACH OTHER: a
    field that every other level declares and this one does not is a field that was
    forgotten. That is weaker than a real schema and it is the right rule here -- it needs
    no list to maintain, and it gets stronger every time a level is added.

    The threshold is "all but one" rather than "all", so a field genuinely unique to one
    level -- Sandbox's fixedSequence -- does not make every other level look broken.
    """
    text = read(LEVELS)
    blocks = {}
    for match in re.finditer(r"LevelDefinitions\.(\w+) = \{(.*?)\n\}", text, re.S):
        name, body = match.group(1), match.group(2)
        if name in ("All", "ById"):
            continue
        blocks[name] = set(re.findall(r"^\t(\w+) =", body, re.M))

    if len(blocks) < 3:
        return
    common = set()
    for field in set().union(*blocks.values()):
        held = sum(1 for fields in blocks.values() if field in fields)
        if held >= len(blocks) - 1:
            common.add(field)

    for name, fields in sorted(blocks.items()):
        for field in sorted(common - fields):
            fail("LevelDefinitions", "%s has no `%s`, which every other level declares. "
                 "Whatever reads it gets nil the first time this level is played."
                 % (name, field))


# ---- THE DIVE FINALE, for any level that declares one.
#
# City Shore ends by jumping off a springboard at the top of the spiral into the sea seven
# hundred studs below. Three things make that work and each fails silently on its own: the
# platform has to be built somewhere, the kill plane has to leave the diver alone (it sits 680
# studs above the water), and the old finish line has to stand down or the run completes at the
# end of the route while the dive is still scenery.
def check_dive_finale():
    levels = read(LEVELS)
    if 'finale = "dive"' not in levels:
        return
    if not os.path.exists(DIVE_SERVICE):
        fail("DiveFinaleService", "a level declares `finale = \"dive\"` and the module is not "
                                  "there, so that level has no ending at all.")
        return
    # CODE ONLY, for both. The module's own comment explains at length why a Touched event
    # cannot work at dive speed, and the first version of the gate below fired on that comment.
    # A gate that fails on its own documentation is one somebody learns to ignore -- and the
    # presence checks are worth stripping too, since a line that survives only in a comment is
    # not a line that runs.
    def code_of(source):
        return "\n".join(line.split("--", 1)[0] for line in source.splitlines())

    dive, boot = code_of(read(DIVE_SERVICE)), code_of(read(BOOTSTRAP))

    if "finishFrame =" not in read(LEVEL_SERVICE):
        fail("LevelService", "no longer hands back finishFrame, so the dive platform has no "
                             "frame to be built in.")
    for needed, why in (
        ("DiveFinaleService.start(", "nothing builds the platform"),
        ("DiveFinaleService.ownsFall(player)",
         "the kill plane catches every diver 680 studs above the water"),
        ("DiveFinaleService.stop", "the diver watch keeps running after the level is gone"),
        ("finishPart.CanTouch = false",
         "the old finish line still completes the run at the end of the route"),
        # BOTH WARNINGS, because the fallback when the dive cannot be built is the old finish
        # line -- so a level that asks for a dive and silently does not get one is
        # indistinguishable from a level that was never changed. That was reported once: no
        # diving board, the run completed at the end of the route, and nothing in the Output.
        ("if not DiveFinaleService then",
         "it says nothing when it cannot build: with the module missing, the level quietly "
         "finishes at the end of its route instead"),
        ("elseif not levelInstance.finishFrame then",
         "it says nothing when it cannot build: with an older LevelService there is no "
         "finishFrame, and the level quietly finishes at the end of its route instead"),
    ):
        if needed not in boot:
            fail("Bootstrap", "%s (`%s` is gone)." % (why, needed))

    # THE SPLASH IS A HEIGHT TEST. A diver crosses about nine studs a frame, so a trigger part
    # is skipped outright: the character is above it on one frame and under it on the next.
    if "Touched" in dive:
        fail("DiveFinaleService", "the splash is back on a Touched event. At dive speed a "
                                  "trigger part is simply never touched.")
    if "at.Y <= water" not in dive:
        fail("DiveFinaleService", "the splash is no longer a height test against the sea's "
                                  "own surface.")

    # AND THE DIVE COLUMN STARTS OUTSIDE THE SPIRAL. The column begins at the deck's outer edge,
    # and the widest thing the generator can put on the turn below is a 22-wide shaped chunk with
    # a shelf beside it: about sixteen studs from the route's centreline. A deck narrower than
    # thirty-four counts standing on that shelf as falling into the sea.
    found = re.search(r"^local DECK_WIDE = ([\d.]+)", dive, re.M)
    if found and float(found.group(1)) / 2 < 17:
        fail("DiveFinaleService", "the deck is %g wide, so the dive column starts %.1f studs "
             "from the route's centreline -- inside the spiral."
             % (float(found.group(1)), float(found.group(1)) / 2))


def main():
    check_dive_finale()
    check_level_fields()
    check_headline_materials()
    check_level_origin()
    check_end_level()
    check_run_request_is_pure_data()
    check_hub_builds_pads()
    check_pads_are_reachable()

    if failures:
        print("HUB PROBLEMS (%d):" % len(failures))
        for line in failures:
            print("  " + line)
        return 1
    print("hub data is complete.")
    return 0


sys.exit(main())

