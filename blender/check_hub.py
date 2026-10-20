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

    # POSITIONS, not every mention. Since Sky Pools the route's radius is a per-level `radius`
    # worked out from SPIRAL_RADIUS, so a line that only computes a radius is not a position and
    # is not checked -- but any line that BUILDS one from either name must add the origin.
    for number, line in enumerate(text.splitlines(), 1):
        code = line.split("--")[0]
        if not re.search(r"\b(SPIRAL_RADIUS|radius)\b", code):
            continue
        if "Vector3.new(" not in code and "out *" not in code:
            continue
        if "base" not in code:
            fail("LevelService:%d" % number,
                 "positions from the route radius without the origin: %s" % line.strip())


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



# ============================================================ the promenade, and everything on it
#
# The poses once did nothing for a whole round of testing, not because setPose was broken but because the pose keys
# sat inside the length keys and could never be stepped on. A geometry mistake takes a geometry check, and a layout
# check has to track the layout or it reports safety for a room that no longer exists.
#
# Since the hundredth pass every place in the lobby is in src/Shared/LobbyLayout.lua, and lobby_layout.py reads it
# (never copies it) and gives every thing its footprint in HubService's own sizes. So: HubService takes every place
# from the layout (none written into it); every thing stands wholly inside a deck's inlay (or, a lamp, on a walk);
# no two things come within a stud of each other; every walk's way onto each of its decks is clear, and so is the way
# from the spawn to the start; the decks stand apart, each walk spans the gap between two; the structure is not
# Neon; and every deck and walk stands on piers down into the sea.
def check_pads_are_reachable():
    if not os.path.exists(HUB_SERVICE):
        return  # already reported by the RunRequest check
    text = read(HUB_SERVICE)
    sys.path.insert(0, HERE)
    import lobby_layout
    try:
        layout = lobby_layout.read()
    except Exception as err:  # a layout this cannot read is a layout nothing here can vouch for
        fail("LobbyLayout", "cannot be read (%s)" % err)
        return
    for needle, why in (
        ('local LobbyLayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LobbyLayout"))',
         "does not read the lobby's layout"),
        ("local HUB_ORIGIN = LobbyLayout.ORIGIN", "has the lobby's origin written into it, not read from the layout"),
        ("pad.CFrame = CFrame.new(HUB_ORIGIN) * LobbyLayout.arc(count)[index]",
         "does not put the level pads on the arc round the start"),
        ("window.CFrame = pad.CFrame * CFrame.new(0, 6.2, PAD_SIZE.Z / 2)", "puts a level pad's window off its back edge"),
        ("local across = HUB_ORIGIN + (AT :: any)[row.at] + Vector3.new((index - (#row.values + 1) / 2) * 12, 0, 0)",
         "does not centre the mode and length keys across the way in"),
        ("return HUB_ORIGIN + AT.spawn + Vector3.new(0, 2.5, 0)", "says you arrive somewhere the layout does not"),
        ("spawn.CFrame = CFrame.new(HUB_ORIGIN + AT.spawn)", "has its spawn somewhere the layout does not"),
        ("startPad.Position = HUB_ORIGIN + AT.start", "has its start pad somewhere the layout does not"),
        ("board.Position = HUB_ORIGIN + AT.board", "has its leaderboard somewhere the layout does not"),
        ("stand.Position = HUB_ORIGIN + AT.statue", "has the statue somewhere the layout does not"),
        ("key.CFrame = CFrame.new(HUB_ORIGIN + AT.poseRow + Vector3.new((index - (#POSE_ORDER + 1) / 2) * 6, 0, 0))",
         "has the pose keys somewhere the layout does not"),
        ("local base = HUB_ORIGIN + AT.kiosk", "has the shop's kiosk somewhere the layout does not"),
        ("buildBackDoor(HUB_ORIGIN + AT.backDoor, folder)", "has the back house somewhere the layout does not"),
        ("buildDailyChest(HUB_ORIGIN + AT.chest, folder)", "has the daily chest somewhere the layout does not"),
        ("buildChallengeBoard(HUB_ORIGIN + AT.challenges, folder)", "has the challenges board somewhere the layout does not"),
        ('buildChallengeBoard(HUB_ORIGIN + AT.materials, folder, "MaterialsBoard")',
         "has the materials board somewhere the layout does not"),
        ("buildPostBox(HUB_ORIGIN + AT.postBox, folder)", "has the post box somewhere the layout does not"),
        ("local poolCentre = HUB_ORIGIN + AT.pool", "has the pool somewhere the layout does not"),
        ("local base = HUB_ORIGIN + AT.viewer", "has the viewer somewhere the layout does not"),
        ("for _, seat in ipairs(LobbyLayout.BENCHES) do", "does not take its benches from the layout"),
        ("for _, spot in ipairs(LobbyLayout.PLANTERS) do", "does not take its planters from the layout"),
        ("for _, spot in ipairs(LobbyLayout.LAMPS) do", "does not take its lamp posts from the layout"),
        ("buildPromenade(folder)", "never builds the decks and walks"),
        ("railDeck(folder, name)", "leaves a deck without its rail"),
        ("railWalk(folder, w.to)", "leaves a walk without its rails"),
        ("pierGrid(folder, deck.x, deck.z, deck.w, deck.d)", "leaves a deck standing on nothing"),
        ("LobbyLayout.over(offset, 6)", "still counts who is in the room by distance from its middle"),
        ("local ARCADE = HUB_ORIGIN + LobbyLayout.centre(\"arcade\")", "does not know where the arcade's middle is"),
    ):
        if needle not in text:
            fail("HubService", why)
    for builder in ("buildPostBox", "buildChallengeBoard", "buildDailyChest"):
        body = text[text.find("local function %s(" % builder):]
        body = body[:body.find("\nend\n")]
        if "CFrame.lookAt(at, Vector3.new(ARCADE.X, at.Y, ARCADE.Z))" not in body:
            fail("HubService", "%s does not face the arcade's middle" % builder)

    # NOT NEON: the structure's light is the lamps' (the rails' coping, the decks' bands, the pads' windows).
    rail = text[text.find("local function railRun("):text.find("local function railDeck(")]
    if not rail or "Enum.Material.Neon" in rail or "cap.Material = Enum.Material.Marble" not in rail:
        fail("HubService", "the rails' coping is not stone (Neon is a glow with no light in it)")
    if "trim.Material = Enum.Material.Marble" not in text or "trim.Material = Enum.Material.Neon" in text:
        fail("HubService", "the decks' bands are not stone")
    if "window.Material = Enum.Material.Glass" not in text or 'shine.Name = "WindowLight"' not in text:
        fail("HubService", "a level pad's window is not glass with a real light behind it")
    if "shine.Brightness = if not open then 0 elseif on then 1.1 else 0.45" not in text:
        fail("HubService", "a level pad's window light does not go out behind the boards, or brighten when chosen")

    # ON PIERS DOWN INTO THE SEA, the sea where the piers end.
    for needle, why in (
        ("local drop = LobbyLayout.SEA_DROP + 4", "the piers do not reach the sea"),
        ("post.Size = Vector3.new(3, drop - 1, 3)", "a pier does not run from the deck's underside to the sea"),
        ("post.Position = HUB_ORIGIN + Vector3.new(x, -1 - (drop - 1) / 2, z)", "a pier does not hang from under the deck"),
        ("local across = math.max(2, math.ceil((w - 6) / 30) + 1)", "a deck's piers are more than 30 studs apart"),
        ("pier(folder, centre.X, centre.Z + offset)", "a walk has no piers"),
    ):
        if needle not in text:
            fail("HubService", why)
    sea = re.search(r"local SEA_Y, SEA_SPAN, SEA_STEP = (-?[\d.]+),", text)
    if not sea or float(sea.group(1)) != -layout["sea_drop"]:
        fail("HubService", "the sea is not where the piers end (SEA_Y is not minus LobbyLayout.SEA_DROP)")

    # THE DECKS STAND APART, and each walk spans the gap between the plaza and its place, narrower than both sides.
    decks = layout["decks"]
    names = sorted(decks)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            da, db = decks[a], decks[b]
            if abs(da["x"] - db["x"]) < (da["w"] + db["w"]) / 2 and abs(da["z"] - db["z"]) < (da["d"] + db["d"]) / 2:
                fail("LobbyLayout", "the %s and %s decks overlap" % (a, b))
    if "plaza" not in decks or len(layout["walks"]) != len(decks) - 1:
        fail("LobbyLayout", "every place is not one walk from the plaza")
    for w in layout["walks"]:
        if w["to"] not in decks:
            fail("LobbyLayout", "a walk goes to %s, which is no deck" % w["to"])
            continue
        x, z, length, width, along_x = lobby_layout.walk(layout, w["to"])
        if length < 8:
            fail("LobbyLayout", "the walk to %s is %g long: the decks are not apart" % (w["to"], length))
        for deck in (decks["plaza"], decks[w["to"]]):
            side = deck["d"] if along_x else deck["w"]
            if width + 2 * layout["margin"] + 8 > side:
                fail("LobbyLayout", "the walk to %s is too wide for a deck's side" % w["to"])

    # EVERY THING ON A DECK, INSIDE ITS INLAY; NOTHING CROWDING ANYTHING; EVERY WAY IN CLEAR.
    shapes = lobby_layout.footprints(layout, text)
    for shape in shapes:
        if shape["role"] in ("thing", "step") and not lobby_layout.inside_inlay(layout, shape):
            fail("LobbyLayout", "%s at (%g, %g) reaches past its deck's inlay" % (shape["name"], shape["x"], shape["z"]))
        if shape["role"] == "walk" and not lobby_layout.on_walk(layout, shape):
            fail("LobbyLayout", "%s at (%g, %g) is on no deck and no walk" % (shape["name"], shape["x"], shape["z"]))
    for i, a in enumerate(shapes):
        for b in shapes[i + 1:]:
            if a["group"] == b["group"]:
                continue
            clearance = lobby_layout.gap(a, b)
            # A pad you have to aim at gets reported as broken, so this wants real clearance, not merely no overlap.
            if clearance < 1.0:
                fail("LobbyLayout", "%s at (%g, %g) and %s at (%g, %g) leave %.2f studs between them"
                     % (a["name"], a["x"], a["z"], b["name"], b["x"], b["z"], clearance))
    for lane, box in lobby_layout.lanes(layout):
        for shape in shapes:
            if shape["role"] in ("step", "clear"):
                continue
            if lobby_layout.in_lane(shape, box) > -0.5:
                fail("LobbyLayout", "%s at (%g, %g) stands in %s" % (shape["name"], shape["x"], shape["z"], lane))
    at = layout["at"]
    # EVERYTHING STANDS ON THE DECK (its top at 1): the stalls by their feet, the statue's plinth, the board and the
    # start pad by their middles, half their height up.
    def size_y(pattern, fallback):
        found = re.search(pattern, text)
        return float(found.group(1)) if found else fallback
    heights = {name: 1.0 for name in ("pool", "kiosk", "chest", "challenges", "materials", "postBox", "backDoor",
                                      "viewer", "lift")}
    # (The statue's plinth is the first stand.Size in the file; the board's stand, under the deck, comes later.)
    heights["statue"] = 1 + size_y(r"stand\.Size = Vector3\.new\([\d.]+, ([\d.]+), [\d.]+\)", 5) / 2
    heights["board"] = 1 + size_y(r'board\.Size = Vector3\.new\([\d.]+, ([\d.]+), [\d.]+\)', 14) / 2
    heights["start"] = 1 + size_y(r"startPad\.Size = Vector3\.new\([\d.]+, ([\d.]+), [\d.]+\)", 1.6) / 2
    for name, y in heights.items():
        if name not in at:
            fail("LobbyLayout", "has no place for the %s" % name)
        elif abs(at[name][1] - y) > 1e-6:
            fail("LobbyLayout", "the %s does not stand on the deck (y %g, not %g)" % (name, at[name][1], y))
    if lobby_layout.deck_of(layout, at["spawn"][0], at["spawn"][2]) != "plaza":
        fail("LobbyLayout", "you do not arrive on the plaza")
    if lobby_layout.deck_of(layout, at["start"][0], at["start"][2]) != "gates":
        fail("LobbyLayout", "the start is not at the level gates")
    # THE SQUISH ROOM'S LIFT lets you out 7 studs in front of its door (+X), on the floor and clear of everything.
    lx, _, lz = at["lift"]
    out = dict(kind="circle", name="the lift's way out", x=lx + 7, z=lz, r=1.5, role="clear", group="lift out")
    if not lobby_layout.inside_inlay(layout, out):
        fail("LobbyLayout", "the squish room's lift lets you out past the deck's inlay")
    for shape in shapes:
        if shape["name"] != "squish lift" and lobby_layout.gap(out, shape) < 0.5:
            fail("LobbyLayout", "the squish room's lift lets you out into %s" % shape["name"])


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
    # THE DIVE'S OWN BLOCK of Bootstrap, from where it starts the dive to where the next ending (Sky
    # Pools) or the run's modes begin. Sky Pools stands the old finish line down and finishes runs
    # too, so a gate searching past the dive's block passes on the slide's lines while the dive does
    # neither -- which it did, the day the slide went in.
    started = boot.find("DiveFinaleService.start(")
    ends = [at for at in (boot.find("if skyTeardown then", started), boot.find("HubService.getRequest()", started))
            if started >= 0 and at > started]
    dive_block = boot[started:min(ends)] if ends else boot[started:started + 1800] if started >= 0 else ""

    if "finishFrame =" not in read(LEVEL_SERVICE):
        fail("LevelService", "no longer hands back finishFrame, so the dive platform has no "
                             "frame to be built in.")
    for needed, why in (
        ("DiveFinaleService.start(", "nothing builds the platform"),
        ("DiveFinaleService.ownsFall(player)",
         "the kill plane catches every diver 680 studs above the water"),
        ("DiveFinaleService.stop", "the diver watch keeps running after the level is gone"),
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
    if "finishPart.CanTouch = false" not in dive_block:
        fail("Bootstrap", "the old finish line still completes the run at the end of the route "
                          "(`finishPart.CanTouch = false` is gone from the dive's block).")

    # NO SCRIPT SETS THE DESTROY HEIGHT. Workspace.FallenPartsDestroyHeight is PluginSecurity: a
    # script can read it, and only plugins, the command bar and the Properties window can set it.
    # The dive's first fix assigned it, the assignment threw, and start() died after building the
    # board and before connecting the watch -- so every diver was caught by the kill plane and
    # sent back. Checked across every script, because the same line anywhere does the same.
    for folder, _, names in os.walk(os.path.join(ROOT, "src")):
        for name in names:
            if name.endswith(".lua"):
                path = os.path.join(folder, name)
                if re.search(r"FallenPartsDestroyHeight\s*=(?!=)", code_of(read(path))):
                    fail(os.path.relpath(path, ROOT), "assigns Workspace.FallenPartsDestroyHeight, "
                         "which is PluginSecurity: the line throws, and nothing after it in that "
                         "function runs.")
    # SO THE SERVER HOLDS THE DIVER INSTEAD, above the -500 delete line, and carries them in.
    if "root.Anchored = true" not in dive:
        fail("DiveFinaleService", "nothing holds the diver when the server takes over: the "
                                  "character is owned by its own client, so a server that writes "
                                  "only a position is overruled on the next physics frame, and the "
                                  "diver falls on past -500 and is deleted.")
    # THE BLACKOUT IS GONE ON PURPOSE, and this gate is the reverse of the one it replaces. Fading
    # to black at the splash cut the picture at the one moment worth watching and left the banner
    # alone on an empty screen; the completion banner is the ending now. A fade re-added here is a
    # regression, and exactly the kind someone reintroduces by restoring an older Bootstrap.
    # (Looked for in the dive's own code: the story's move between levels fades to black on purpose.)
    dive_block = boot[boot.find("DiveFinaleService.start("):boot.find("if diveOk then")]
    if "{ black = true" in dive_block:
        fail("Bootstrap", "the dive fades the screen to black at the splash again, which throws "
                          "away the dive itself. The completion banner is the ending now: see "
                          "UIService.showCompletion.")
    # AND THE SPLASH STILL HAS TO FINISH THE RUN, blackout or no blackout. Scoped to the dive's own
    # callback: the route's ending calls finishRunFor too, so a file-wide search passes while the
    # dive finishes nothing, which is the shape of the bug this whole section exists for.
    if "finishRunFor(player)" not in dive_block:
        fail("Bootstrap", "the dive's splash no longer finishes the run, so hitting the water "
                          "does nothing at all.")

    # A RESTART AND AN EARLY FINISH, reported together and the same bug seen twice: a level that
    # came back with no board and with its finish line live, so the run completed on arriving at
    # the deck. Three things now hold the ending, and each is checked.
    if "finale.model = buildPlatform" not in dive:
        fail("DiveFinaleService", "the platform is not put back when the level is rebuilt under it, "
                                  "so a restart comes back with no board.")
    if "DiveFinaleService.isArmed()" not in boot:
        fail("Bootstrap", "the finish line is not guarded while the dive is armed, so the end of the "
                          "route can complete a run the dive is meant to finish.")
    stop_at = boot.find("pcall(DiveFinaleService.stop)")
    build_at = boot.find("LevelService.startLevel(")
    if stop_at < 0 or build_at < 0 or stop_at > build_at:
        fail("Bootstrap", "the dive does not stand down before the level is cleared, so its watch "
                          "rebuilds a platform for the previous run.")

    # THE SPLASH IS A HEIGHT TEST. A diver crosses about nine studs a frame, so a trigger part
    # is skipped outright: the character is above it on one frame and under it on the next.
    if "Touched" in dive:
        fail("DiveFinaleService", "the splash is back on a Touched event. At dive speed a "
                                  "trigger part is simply never touched.")
    if "at.Y <= finale.circle.Y + COMMIT_ABOVE" not in dive:
        fail("DiveFinaleService", "the dive no longer finishes on a height test over the landing "
                                  "circle.")

    # TWO CHECKS: off the board, and over the landing circle. The circle alone would finish the
    # level for anyone who fell off a lower turn and drifted out over the same patch of sea.
    if '"DiveLandingCircle"' not in dive or "inCircle(finale, at)" not in dive:
        fail("DiveFinaleService", "the landing circle is gone, so any fall past the board counts "
                                  "as a dive wherever it comes down.")
    if "underBoard(finale.frame, at)" not in dive or "p.Z > -ZONE_SIDE" not in dive:
        fail("DiveFinaleService", "a diver no longer has to have left the board, so falling off a "
                                  "lower turn into the circle finishes the level.")
    # NOT FloorMaterial: that is the diver's client's to report, and the server's copy lags it.
    if "FloorMaterial" in dive:
        fail("DiveFinaleService", "the dive reads Humanoid.FloorMaterial again. The server's copy "
                                  "lags the diver's client, so it can drop a diver mid-fall and "
                                  "hand them to the kill plane.")
    commit = re.search(r"^local COMMIT_ABOVE = ([\d.]+)", dive, re.M)
    water = re.search(r"^local FALLBACK_WATER = (-[\d.]+)", dive, re.M)
    if not commit or not water:
        fail("DiveFinaleService", "COMMIT_ABOVE or FALLBACK_WATER is gone, so nothing says where "
                                  "the server takes a diver over.")
    elif float(water.group(1)) + float(commit.group(1)) < -400:
        fail("DiveFinaleService", "the server takes divers over at %g, less than a hundred studs "
             "above the -500 where Roblox deletes a falling character, so a diver seen a little "
             "late is deleted first." % (float(water.group(1)) + float(commit.group(1))))
    out = re.search(r"^local CIRCLE_OUT = ([\d.]+)", dive, re.M)
    radius = re.search(r"^local CIRCLE_RADIUS = ([\d.]+)", dive, re.M)
    if not out or not radius:
        fail("DiveFinaleService", "CIRCLE_OUT or CIRCLE_RADIUS is gone.")
    elif float(out.group(1)) - float(radius.group(1)) < 23:
        fail("DiveFinaleService", "the landing circle's nearest edge is %g studs from the route's "
             "centreline, over the spiral: the far corner of R1_SlimeLaunch, the longest chunk, "
             "reaches about twenty-three."
             % (float(out.group(1)) - float(radius.group(1))))

    # AND THE DIVE COLUMN STARTS OUTSIDE THE SPIRAL. The column begins at the deck's outer edge,
    # and the widest thing the generator can put on the turn below is a 22-wide shaped chunk with
    # a shelf beside it: about sixteen studs from the route's centreline. A deck narrower than
    # thirty-four counts standing on that shelf as falling into the sea.
    found = re.search(r"^local DECK_WIDE = ([\d.]+)", dive, re.M)
    if found and float(found.group(1)) / 2 < 17:
        fail("DiveFinaleService", "the deck is %g wide, so the dive column starts %.1f studs "
             "from the route's centreline -- inside the spiral."
             % (float(found.group(1)), float(found.group(1)) / 2))


# EVERY LEVEL'S PAD LOOKS LIKE ITS PLACE. A backdrop with no entry in HubService's THEME_LOOKS falls
# back to the empty "no horizon yet" window, which is how Sky Pools and the Sunken City first sat in
# the lobby looking like levels that had not been built.
def check_pad_looks():
    levels = read(LEVELS)
    hub = read(HUB_SERVICE)
    table = hub[hub.find("local THEME_LOOKS = {"):]
    table = table[:table.find("\n}\n")]
    looks = set(re.findall(r"^\t(\w+) = \{", table, re.M))
    listed = re.search(r"LevelDefinitions\.All = \{(.*?)\}", levels, re.S)
    for name in re.findall(r"LevelDefinitions\.(\w+)", listed.group(1) if listed else ""):
        start = levels.find("LevelDefinitions.%s = {" % name)
        block = levels[start:levels.find("\n}\n", start)] if start >= 0 else ""
        backdrop = re.search(r'backdrop = "(\w+)"', block)
        if backdrop and backdrop.group(1) != "none" and backdrop.group(1) not in looks:
            fail("HubService", "has no THEME_LOOKS entry for %s's backdrop \"%s\", so its lobby pad "
                               "shows an empty sky and \"no horizon yet\"." % (name, backdrop.group(1)))


# THE COUNTDOWN TICKS ON THE SECOND. The server used to play each tick itself, and a sound made on
# the server reaches a client when it replicates, in batches: the ticks were heard 0.8 then 1.2 of a
# second apart. Each client plays its own now, from the end time on the shared clock.
VOTE_CLIENT = os.path.join(ROOT, "src", "Client", "Services", "HubVoteService.lua")


def check_countdown_ticks_evenly():
    hub = read(HUB_SERVICE)
    client = read(VOTE_CLIENT)
    if "TICK_SOUND" in hub:
        fail("HubService", "plays the countdown's tick on the server again, so it is heard when it replicates, not on the second")
    for needle in ("countdownEndsAt = workspace:GetServerTimeNow() + COUNTDOWN_SECONDS", "endsAt = countdownEndsAt,"):
        if needle not in hub:
            fail("HubService", "does not tell the clients when the countdown ends: `%s`" % needle)
    for needle in ("RunService.RenderStepped:Connect(function()", "workspace:GetServerTimeNow()", "TICK:Play()",
                   "endsAt = deadline"):
        if needle not in client:
            fail("HubVoteService", "does not keep the countdown itself on the shared clock: `%s`" % needle)


# ONE STATUE A SCREEN, AND NONE LEFT BEHIND. Every player's statue stands on the same plinth, so each is
# tagged with its owner and each screen hides everyone's but its own (HubVoteService), figure and all, as
# it loads and as it changes pose; and a statue goes with its player, so a server does not collect them.
def check_statues():
    hub = read(HUB_SERVICE)
    boot = read(BOOTSTRAP)
    vote = read(VOTE_CLIENT)
    build = hub[hub.find("function HubService.buildStatue("):]
    build = build[:build.find("\nend\n")]
    for needle, why in (
        ('stand:SetAttribute("Owner", player.UserId)', "a statue does not say whose it is"),
        ('CollectionService:AddTag(stand, "LobbyStatue")', "a statue is not tagged for the screens to sort out"),
    ):
        if needle not in build:
            fail("HubService", why)
    remove = hub[hub.find("function HubService.removeStatue("):]
    remove = remove[:remove.find("\nend\n")]
    if "stand:Destroy()" not in remove or "poseFor[player] = nil" not in remove:
        fail("HubService", "a leaving player's statue (or their pose) stays behind")
    leaving = boot[boot.find("Players.PlayerRemoving:Connect(function(player: Player)"):]
    if "pcall(HubService.removeStatue, player)" not in leaving[:2500]:
        fail("Bootstrap", "a statue is never taken down when its player leaves")
    for needle, why in (
        ('if stand:GetAttribute("Owner") == Players.LocalPlayer.UserId then\n\t\treturn',
         "every statue is hidden, your own as well"),
        ("(item :: any).LocalTransparencyModifier = 1", "the others' statues are not hidden"),
        ("item.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None", "a hidden figure still shows its name"),
        ("stand.DescendantAdded:Connect(hide)", "a figure that loads later, or a new pose, shows through"),
        ('CollectionService:GetInstanceAddedSignal("LobbyStatue"):Connect(hideOthers)',
         "a statue built after you joined is not hidden"),
    ):
        if needle not in vote:
            fail("HubVoteService", why)


# A RUN ENDS PROPERLY HOWEVER IT ENDS, AND A PLAYER IS PUT WHERE THEY BELONG. The last runner out (finished,
# left from the menu, or gone from the server) gives the lobby its sky back and takes the level's world
# away; "still running" means a runner the hub has not had back, not anyone who has not finished; a player
# respawns on the level only if they are in its run (or the lobby is away), and someone who joins while
# the lobby is away is counted into the run, in its mode, and paid for finishing it.
def check_runs_end():
    boot = read(BOOTSTRAP)
    ender = boot[boot.find("HubService.setEnder(function()"):]
    ender = ender[:ender.find("\nend)\n")]
    for needle, why in (
        ("\tendLevelWorld()\n", "a run that ends without a finish leaves the level's world standing"),
        ('pcall(LightingService.apply, "lobby")', "a run that ends without a finish leaves the level's sky over the "
         "lobby"),
    ):
        if needle not in ender:
            fail("Bootstrap", why)
    # THE SHARED TEARDOWN (the ender's, and a story's between levels): backdrop, dive watch, chunks, rooms.
    world = boot[boot.find("local function endLevelWorld()"):]
    world = world[:world.find("\nend\n")]
    for needle, why in (
        ("\tLevelService.endLevel()\n\tlevelInstance = nil\n\ttearDownLevelWorld()", "a level's chunks or rooms are left standing"),
        ("pcall(DiveFinaleService.stop)", "the dive's watch goes on after its level"),
        ('local standing = workspace:FindFirstChild("Backdrop")', "City Shore's horizon is left standing"),
    ):
        if needle not in world:
            fail("Bootstrap", why)
    if "if other ~= player and HubService.isInRun(other) then" not in boot or "otherState.hasCompletedLevel" in boot:
        fail("Bootstrap", "the finish counts anyone who has not finished as still running (the squish room, the "
             "lobby), so the lobby keeps the level's sky")
    wire = boot[boot.find("local function wirePlayer("):]
    wire = wire[:wire.find("\nend\n")]
    for needle, why in (
        ('local lobbyAway = workspace:FindFirstChild("Hub") == nil', "a respawn does not know whether the lobby is there"),
        ("local target = if levelInstance and (inRunNow or lobbyAway) then levelInstance.startPosition "
         "else hub.spawnPosition", "a player back in the lobby who resets is put on a level they are not in"),
        ('if levelInstance and not inRunNow and lobbyAway and not player:GetAttribute("InSquishRoom") then\n'
         "\t\t\tjoinRunLate(player)", "someone joining while a run is on is not counted into it (or the squish room "
         "is pulled in)"),
    ):
        if needle not in wire:
            fail("Bootstrap", why)
    late = boot[boot.find("local function joinRunLate("):boot.find("local function wirePlayer(")]
    for needle, why in (
        ("if not instance or HubService.isInRun(player) then\n\t\treturn", "a runner is joined into their own run again"),
        ("HubService.markInRun({ player })", "a late joiner is not one of the run's runners, so it ends under them"),
        ("PlayerStateService.beginRun(player, request.mode :: any)", "a late joiner does not play the run's mode"),
        ("pcall(EconomyService.runStarted, { player }, runLength, true)", "a late joiner is not paid for finishing"),
        ('player:SetAttribute("InLevel", runBackdrop)', "a late joiner's client is not told which level it is in"),
    ):
        if needle not in late:
            fail("Bootstrap", why)


# THE BOARD IS READ ONCE AND SHOWN TO MANY. Roblox lets a server read an ordered store about 5 + 2 per player
# times a minute, and the lobby redraws every player's board on every pad step: each board is kept for a
# while (its season in its name), a second ask waits for the first, a failed read shows the last good board,
# and a new time on it clears it. Personal bests are kept a minute, set when written, let go on leaving.
LEADER = os.path.join(ROOT, "src", "Server", "Services", "LeaderboardService.lua")
BEST = os.path.join(ROOT, "src", "Server", "Services", "BestTimeService.lua")


def check_board_reads():
    lead = read(LEADER)
    best = read(BEST)
    fresh = re.search(r"^local FRESH = (\d+)", lead, re.M)
    if not fresh or int(fresh.group(1)) < 10:
        fail("LeaderboardService", "the board is not kept long enough to save the store's few reads a minute")
    top = lead[lead.find("function LeaderboardService.getTop("):]
    top = top[:top.find("\nend\n")]
    for needle, why in (
        ('local key = boardName(levelId, mode) .. "#" .. tostring(count)', "a kept board does not know its season"),
        ("if kept and os.clock() - kept.at < FRESH then\n\t\treturn table.clone(kept.rows)", "every look reads the store"),
        ("\tif fetching[key] then\n", "two looks at once read the store twice"),
        ("\t\tend\n\t\treturn if kept then table.clone(kept.rows) else {}\n\tend\n\tlocal results = {}",
         "a failed read blanks the board instead of showing the last good one"),
        ("if failed and os.clock() - failed < RETRY then\n\t\treturn if kept then table.clone(kept.rows) else {}",
         "a failed read is tried again on every redraw"),
        ("if not saidAt[key] or os.clock() - saidAt[key] > 60 then", "a failed read is warned about on every redraw"),
    ):
        if needle not in top:
            fail("LeaderboardService", why)
    if top.count("fetching[key] = nil") < 2:
        fail("LeaderboardService", "a failed read leaves the board marked as being read, so every look after it waits")
    submit = lead[lead.find("function LeaderboardService.submitTime("):lead.find("function LeaderboardService.getTop(")]
    if "forget(levelId, mode)" not in submit:
        fail("LeaderboardService", "a new time does not show on the board until the kept one runs out")
    # A PLACE ON THE BOARD IS NEVER LOST: compared and written in one step, never read first and written after.
    if "store:UpdateAsync(key, function(existing: any): any" not in submit or "SetAsync" in submit or "GetAsync" in submit:
        fail("LeaderboardService", "a time is read and written in two steps, so a slower one can overwrite a better")
    if 'if typeof(existing) == "number" and existing > 0 and existing <= stored then' not in submit:
        fail("LeaderboardService", "a slower time is written over a better one")
    for needle, why in (
        ("if kept and os.clock() - kept.at < FRESH then\n\t\treturn kept.value", "every redraw reads your best from the store"),
        ("\tremember(player, key, timeSeconds)\n", "a new best shows late, from the kept old one"),
        ("\tknown[player] = nil\n", "a leaving player's bests are kept for the life of the server"),
    ):
        if needle not in best:
            fail("BestTimeService", why)


# ONLY A RUNNER LEAVES A RUN: "Leave to the lobby" from anyone else (the squish room, the lobby while a run is
# on) put them in the lobby still marked as elsewhere, and brought the lobby back in the middle of the run.
def check_leaving():
    boot = read(BOOTSTRAP)
    leave = boot[boot.find("LeaveLevel.OnServerEvent:Connect("):]
    leave = leave[:leave.find("\nend)\n")]
    if "if levelInstance and HubService.isInRun(player) then" not in leave:
        fail("Bootstrap", "anyone can leave a run they are not in")


# THE PASTE CHECK KNOWS THE WHOLE GAME. In Studio the server lists what is missing from the place; its lists
# are kept here the same as src/ and audio/, so a module or a sound added to the game is added to it too, and
# what was taken out of the game is named for deleting and is not in src/ any more.
def check_paste_check():
    import pathlib as _pathlib
    boot = read(BOOTSTRAP)
    block = boot[boot.find("local function pasteCheck()"):]
    block = block[:block.find("\nend\n")]
    if not block:
        fail("Bootstrap", "there is no paste check")
        return

    def names(table_name):
        found = re.search(r"local %s = \{(.*?)\}" % table_name, block, re.S)
        return sorted(re.findall(r'"(\w+)"', found.group(1))) if found else None

    root = _pathlib.Path(ROOT)

    def stems(folder, pattern="*.lua"):
        return sorted(p.name.split(".")[0] for p in (root / folder).glob(pattern))

    audio = root / "audio"
    families = sorted({p.stem.rsplit("_", 1)[0] for p in (audio / "materials").glob("*.wav")})
    for table_name, expected in (
        ("SERVER_MODULES", stems("src/Server/Services")),
        ("SHARED_MODULES", stems("src/Shared")),
        ("CLIENT_MODULES", stems("src/Client/Services")),
        ("MATERIAL_FAMILIES", families),
        ("BUTTON_SOUNDS", sorted(p.stem for p in (audio / "buttons").glob("*.wav"))),
        ("SHEET_SOUNDS", sorted(p.stem for p in (audio / "sheets").glob("*.wav"))),
        ("LOBBY_SOUNDS", sorted(p.stem for p in (audio / "lobby").glob("*.wav"))),
        ("WATER_SOUNDS", sorted(p.stem for p in (audio / "water").glob("*.wav"))),
        ("STORY_SOUNDS", sorted([p.stem for p in (audio / "story").glob("*.wav")]
                                + [p.stem for p in (audio / "endings").glob("*.wav")])),
        ("AMBIENCE_SOUNDS", sorted(p.stem for p in (audio / "ambience").glob("*.wav"))),
    ):
        listed = names(table_name)
        if listed != expected:
            missing = sorted(set(expected) - set(listed or []))
            extra = sorted(set(listed or []) - set(expected))
            fail("Bootstrap", "the paste check's %s is not what the game has (missing %s, extra %s)"
                 % (table_name, missing, extra))
    for family in families:
        count = len(list((audio / "materials").glob(family + "_*.wav")))
        if count != 4:
            fail("Bootstrap", "the paste check expects four of %s, and audio/materials has %d" % (family, count))
    gone = names("GONE") or []
    for name in ("KeepsakeService", "PromptStyleService"):
        if name not in gone:
            fail("Bootstrap", "the paste check does not tell anyone to delete %s" % name)
    present = set(stems("src/Server/Services")) | set(stems("src/Client/Services")) | set(stems("src/Shared"))
    for name in gone:
        if name in present:
            fail("Bootstrap", "the paste check says to delete %s, which is still part of the game" % name)
    # THE LOBBY'S OWN SOUNDS are looked for as optional (the lobby has the server's stand-ins without them), in their
    # own folder; the sheets in MaterialSounds, as the takes are.
    if 'sound("LobbySounds", name, true)' not in block:
        fail("Bootstrap", "the paste check does not look for the lobby's own sounds, or calls them required")
    if 'sound("WaterSounds", name, true)' not in block:
        fail("Bootstrap", "the paste check does not look for the water's sounds, or calls them required")
    if 'for _, name in ipairs(SHEET_SOUNDS) do\n\t\tsound("MaterialSounds", name)' not in block:
        fail("Bootstrap", "the paste check does not look for the sheets in MaterialSounds")
    optional = re.search(r"local OPTIONAL = \{(.*?)\}", block, re.S)
    for name in re.findall(r"(\w+) = true", optional.group(1) if optional else ""):
        if name not in (names("STORY_SOUNDS") or []):
            fail("Bootstrap", "the paste check calls %s optional and does not look for it" % name)
    scripts = sorted(p.name.replace(".server.lua", "") for p in (root / "src" / "Server").glob("*.server.lua"))
    for name in scripts:
        if 'scriptAt(ServerScriptService, "ServerScriptService", "%s", "Script")' % name not in block:
            fail("Bootstrap", "the paste check does not look for the %s Script" % name)
    if 'scriptAt(StarterPlayerScripts, "StarterPlayerScripts", "Bootstrap", "LocalScript")' not in block:
        fail("Bootstrap", "the paste check does not look for the client's Bootstrap")
    for needle, why in (
        ('local storesOk = pcall(function()\n\t\tgame:GetService("DataStoreService"):GetDataStore("PasteCheck")',
         "does not say whether Studio can reach the data stores (or asks unguarded)"),
        ('if not storesOk then\n\t\twarn("PASTE CHECK: Studio cannot reach the data stores',
         "does not say whether Studio can reach the data stores"),
        ('local unset = if item.passId ~= nil then item.passId == 0 else (item.productId or 0) == 0',
         "does not notice a Robux item with no id"),
        ("if item.robux and unset then", "lists items that are not sold for Robux as not on sale"),
        ('print("PASTE CHECK: not on sale yet', "does not list the Robux items with no id"),
        ('local profileStore = ServerScriptService:FindFirstChild("ProfileStore")', "does not look for ProfileStore"),
        ('elseif type(loaded) ~= "table" or type((loaded :: any).New) ~= "function" then',
         "takes anything named ProfileStore for loleris's (ProfileService loaded and saved nothing)"),
        ("if named == want or named == want .. \".server\" or named == want .. \".client\" then",
         "says a script is missing when its name is only written differently (BootStrap)"),
        ("elseif copies > 1 then", "does not notice a sound imported twice (an old one not deleted)"),
        ('elseif not found:IsA("ModuleScript") then', "does not notice a module pasted as the wrong kind of script"),
    ):
        if needle not in block:
            fail("Bootstrap", "the paste check " + why)
    tail = boot[boot.find("local function pasteCheck()"):]
    if 'if game:GetService("RunService"):IsStudio() then\n\ttask.delay(4, function()\n\t\tlocal ok, err = pcall(pasteCheck)' \
            not in tail:
        fail("Bootstrap", "the paste check is not run (in Studio, after the start, guarded)")


# THE DASHBOARD SEES THE LEVELS: a start for everyone who starts a run (late joiners too), a completion for
# every finish, a fail for leaving partway (the menu, or the server), each the right event, guarded; and the
# kiosk's visits counted, the top of the shop's funnel.
def check_dashboard():
    boot = read(BOOTSTRAP)
    hub = read(HUB_SERVICE)
    prog = boot[boot.find("local function progression("):boot.find("local secondChance = {")]
    for needle, why in (
        ('if status == "start" then\n\t\t\tAnalyticsService:LogProgressionStartEvent(', "a start is not logged as one"),
        ('elseif status == "complete" then\n\t\t\tAnalyticsService:LogProgressionCompleteEvent(', "a finish is not logged as one"),
        ("else\n\t\t\tAnalyticsService:LogProgressionFailEvent(", "leaving partway is not logged as a fail"),
        ('pcall(function()\n\t\tif status == "start" then', "the dashboard's logging is not guarded"),
    ):
        if needle not in prog:
            fail("Bootstrap", why)
    for needle, why in (
        ('\t\tPlayerStateService.beginRun(player, request.mode :: any)\n\t\tprogression(player, "start")',
         "a run's start is not logged"),
        ('\tHubService.markInRun({ player })\n\tprogression(player, "start")', "a late joiner's start is not logged"),
        ('\t\tPlayerStateService.markCompleted(player)\n\t\tprogression(player, "complete")', "a finish is not logged"),
        # (the menu's own one: being caught in the back rooms ends a run with the same two lines)
        ('in the middle of the run.\n\tif levelInstance and HubService.isInRun(player) then\n\t\tprogression(player, "fail")',
         "leaving a run from the menu is not logged"),
        ('\tif runningFor[player] then\n\t\tprogression(player, "fail")\n\tend\n\tPlayerStateService.cleanup(player)',
         "leaving the server partway through a run is not logged"),
    ):
        if needle not in boot:
            fail("Bootstrap", why)
    kiosk = hub[hub.find("function HubService.buildKiosk("):]
    if 'pcall(function()\n\t\t\tgame:GetService("AnalyticsService"):LogCustomEvent(player, "ShopKiosk")' not in kiosk:
        fail("HubService", "the kiosk's visits are not counted for the dashboard")
    # THE CLIMB THROUGH THE LEVELS: each level's first finish in a save (FirstFinish_<id>), and a locked level someone
    # wanted (LockedPad_<id>), counted once per player and level a session, not once per step on the pad.
    economy = read(os.path.join(ROOT, "src", "Server", "Services", "EconomyService.lua"))
    finish = economy[economy.find("function EconomyService.runFinished("):economy.find("function EconomyService.finishedLevels(")]
    first = finish.find('AnalyticsService:LogCustomEvent(player, ("FirstFinish_%d"):format(levelId))')
    marked = finish.find("finished[tostring(levelId)] = true")
    if first < 0 or marked < 0 or first < marked or "pcall(function()\n\t\t\tAnalyticsService:LogCustomEvent(player, (\"FirstFinish_" not in finish:
        fail("EconomyService", "a level's first finish is not counted for the dashboard (or not only the first, or unguarded)")
    told = hub[hub.find("function HubService.tellLocked("):]
    told = told[:told.find("\nend\n")]
    for needle, why in (
        ('game:GetService("AnalyticsService"):LogCustomEvent(player, ("LockedPad_%d"):format(levelId))',
         "a locked level someone wanted is not counted for the dashboard"),
        ("if not logged[levelId] then\n\t\tlogged[levelId] = true", "a locked pad is counted on every step, not once per player"),
    ):
        if needle not in told:
            fail("HubService", why)
    if "lockLogged[player] = nil" not in hub:
        fail("HubService", "who has stepped on a locked pad is kept after they leave")


# LEVELS OPEN IN ORDER. The first level and the sandbox always; each after it once anyone in the server has
# finished the one before (their save). A locked level takes no vote and cannot win one; its pad is boarded up and
# says what opens it; the player stepping on it is told, not every frame. A finish is kept only for a run that
# was really played, and the lobby looks again whenever what anyone has finished changes.
def check_levels_open_in_order():
    hub = read(HUB_SERVICE)
    boot = read(BOOTSTRAP)
    economy = read(os.path.join(ROOT, "src", "Server", "Services", "EconomyService.lua"))
    banner = read(os.path.join(ROOT, "src", "Client", "Services", "HubVoteService.lua"))
    dev = read(os.path.join(ROOT, "src", "Client", "Services", "DevPanelClient.lua"))

    def within(text, start, stop):
        at = text.find(start)
        return text[at:text.find(stop, at + 1)] if at >= 0 else ""

    is_open = within(hub, "function HubService.isOpen(", "\nend\n")
    for needle, why in (
        ("if before == nil or reader == nil then\n\t\treturn true", "the first level (or every level, with no save to read) is not always open"),
        ("for _, player in ipairs(Players:GetPlayers()) do", "a level is not opened by anyone in the server"),
        ("finished[key] == true", "a level opens without the one before it finished"),
        ("if level.levelId == before.levelId then\n\t\t\treached = true", "getting further does not count from the level before"),
        ("if reached then\n\t\t\ttable.insert(keys, tostring(level.levelId))",
         "someone who got further (carried into a level and finished it) finds the levels behind them locked"),
    ):
        if needle not in is_open:
            fail("HubService", why)
    if "return if index > 1 then LevelDefinitions.All[index - 1] else nil" not in hub:
        fail("HubService", "the level before is not the one before it in LevelDefinitions.All")
    vote = within(hub, "function HubService.vote(", "\nend\n")
    if "if not HubService.isOpen(value :: number) then\n\t\t\tHubService.tellLocked(player, value :: number)\n\t\t\treturn" not in vote:
        fail("HubService", "a locked level takes a vote")
    resolve = within(hub, "function HubService.resolveVote(", "\nend\n")
    if "if HubService.isOpen(level.levelId) then\n\t\t\ttable.insert(levelOrder, level.levelId)" not in resolve:
        fail("HubService", "a locked level can win the vote")
    pads = within(hub, "function HubService.refreshPads(", "\nend\n")
    for needle, why in (
        ("board.Transparency = if open then 1 else 0", "the boards are not across a locked level's window (or stay on an open one)"),
        ('text = ("Locked: finish %s first"):format(before.name)', "a locked pad does not say what opens it"),
        ("clear = 0.8", "a locked level's window is not dimmed"),
    ):
        if needle not in pads:
            fail("HubService", why)
    pad = within(hub, "local function makeLevelPad(", "\nend\n")
    for needle, why in (
        ('board.Name = "LockBoard"', "the level pads have no boards for when they are locked"),
        ("board.Transparency = 1\n", "the boards are not built hidden"),
        ("board.CanCollide = false", "the boards can be walked into"),
        ("window.Size.Z / 2 + 0.15", "the boards are not lying on the window (they would float)"),
    ):
        if needle not in pad:
            fail("HubService", why)
    told = within(hub, "function HubService.tellLocked(", "\nend\n")
    if "os.clock() - told.at < LOCK_TELL_GAP then\n\t\treturn" not in told:
        fail("HubService", "a locked pad tells the player every frame they stand on it")
    locks = within(hub, "function HubService.refreshLocks(", "\nend\n")
    for needle, why in (
        ("ballot.levelId = first.levelId", "a vote left on a level that locked again is not moved to the first level"),
        ("HubService.refreshPads()\n\ttellState()", "the pads and the banner are not shown what changed"),
    ):
        if needle not in locks:
            fail("HubService", why)
    if "lockTold[player] = nil" not in within(hub, "function HubService.clearBallot(", "\nend\n"):
        fail("HubService", "who was told about a locked pad is kept after they leave")

    for needle, why in (
        ("Finished = {} :: { [string]: boolean },", "the save does not keep the levels finished"),
        ("function EconomyService.finishedLevels(", "the lobby cannot read what a player has finished"),
    ):
        if needle not in economy:
            fail("EconomyService", why)
    finished = within(economy, "function EconomyService.runFinished(", "\nend\n")
    played = finished.find("faster than it can be played")
    kept = finished.find("finished[tostring(levelId)] = true\n\t\ttellLevels()")
    if kept < 0:
        fail("EconomyService", "a finished level is not kept (or the lobby is not told)")
    elif played < 0 or kept < played:
        fail("EconomyService", "a run finished faster than it can be played still opens the next level")
    load = within(economy, "local function load(", "\nend\n")
    if not load.rstrip().endswith("tellLevels()"):
        fail("EconomyService", "a save loading does not open what it has finished")
    unload = within(economy, "local function unload(", "\nend\n")
    if not unload.rstrip().endswith("tellLevels()"):
        fail("EconomyService", "a player leaving does not lock again what only they had opened")
    if 'elseif action == "levels" then' not in economy or '{ action = "levels", text = "Levels open/locked" }' not in dev:
        fail("EconomyService", "the test panel cannot open and lock the levels")
    if "check(\"a run finished at once opens no level\"" not in economy:
        fail("EconomyService", "the self-test does not check that a too-fast run opens no level")

    for needle, why in (
        ("pcall(EconomyService.runFinished, player, hardcore, hardcore and newBest == true, finishedId)",
         "a finish does not say which level it was"),
        ("HubService.setFinishedReader(EconomyService.finishedLevels)", "the lobby does not read the saves"),
        ("EconomyService.setLevelsChanged(HubService.refreshLocks)", "the lobby is not told when a level is finished"),
        ("HubService.setLockNotifier(function(player: Player, kind: string, payload: any)\n\tHubVoteState:FireClient(player, kind, payload)",
         "a player stepping on a locked pad (or back from a run that opened a level) is not told"),
    ):
        if needle not in boot:
            fail("Bootstrap", why)

    for needle, why in (
        ('elseif kind == "locked" then\n\t\t\tHubVoteService.onLocked(payload)', "the banner never says a level is locked"),
        ("HubVoteService.onIdle(state)", "the banner does not go back to the tally after saying a level is locked"),
    ):
        if needle not in banner:
            fail("HubVoteService", why)
    for name in ("onIdle", "onTick"):
        if "if os.clock() < lockedUntil then\n\t\treturn" not in within(banner, "function HubVoteService.%s(" % name, "\nend\n"):
            fail("HubVoteService", "a vote elsewhere wipes the locked message at once (%s)" % name)
    if "lockedUntil = 0" not in within(banner, "function HubVoteService.onResult(", "\nend\n"):
        fail("HubVoteService", "the locked message holds back the run's result")

    # A LEVEL THE RUN OPENED is told to each player coming back from it: what was shut when they left and is open
    # now (so nothing is said twice, and a level opened by someone joining is not announced), on the vote card with
    # a chime, then back to the tally or put away (never a countdown from before the run).
    if 'pcall(notify :: any, player, "locked", {' not in told:
        fail("HubService", "a locked pad's message is not sent as \"locked\"")
    if "openWhenLeft[player] = openWhenLeft[player] or HubService.openNow()" not in within(hub, "function HubService.markInRun(", "\nend\n"):
        fail("HubService", "what was open when a player went into a run is not kept")
    back = within(hub, "function HubService.returnToHub(", "\nend\n")
    if "openWhenLeft[player] = nil" not in back or "HubService.tellOpened(player, wasOpen)" not in back:
        fail("HubService", "a player coming back is not told what the run opened (or is told twice)")
    opened = within(hub, "function HubService.tellOpened(", "\nend\n")
    if "before[level.levelId] == false and HubService.isOpen(level.levelId)" not in opened:
        fail("HubService", "a level is announced as opened that was open already, or is not open")
    if 'pcall(notify :: any, player, "opened", { names = names })' not in opened:
        fail("HubService", "an opened level is never sent to the player")
    if 'elseif kind == "opened" then\n\t\t\tHubVoteService.onOpened(payload)' not in banner:
        fail("HubVoteService", "the banner never says a level opened")
    on_opened = within(banner, "function HubVoteService.onOpened(", "\nend\n")
    for needle, why in (
        ('HubVoteService.say("NEW", title, body)', "the opened message is not held on the card"),
        ("\tHubVoteService.say(\"NEW\", title, body)\n\ttock(2)", "a level opening makes no sound"),
    ):
        if needle not in on_opened:
            fail("HubVoteService", why)
    # THE HELD MESSAGE every one of these goes through (say): held for its time, then the tally or nothing.
    say = within(banner, "function HubVoteService.say(", "\nend\n")
    for needle, why in (
        ("lockedUntil = os.clock() + OPENED_FOR", "a held message is wiped by the next tally at once"),
        ("else\n\t\t\tshow(false)", "a held message stays up for good when there is no tally to go back to"),
    ):
        if needle not in say:
            fail("HubVoteService", why)
    if 'lastState, lastKind = nil, "idle"' not in within(banner, "function HubVoteService.onResult(", "\nend\n"):
        fail("HubVoteService", "after a run the card can go back to a countdown from before it")
    if 'elseif kind == "clear" then\n\t\t\tdismissAt = 0\n\t\t\tlockedUntil = 0\n\t\t\tlastState, lastKind = nil, "idle"' not in banner:
        fail("HubVoteService", "packing the banner away for a run leaves a held message to come back over it")


# ONE RUN AT A TIME. Nothing starts a run while anyone is still out on a level (one level per server): not the
# Start pad (which tells whoever stepped on it how many are still playing, once, not every frame), not a vote, and
# not a countdown that ends after a story's next level has started.
def check_one_run_at_a_time():
    hub = read(HUB_SERVICE)
    banner = read(os.path.join(ROOT, "src", "Client", "Services", "HubVoteService.lua"))

    def within(text, start, stop):
        at = text.find(start)
        return text[at:text.find(stop, at + 1)] if at >= 0 else ""

    if "function HubService.runOn(): boolean\n\treturn next(inRun) ~= nil" not in hub:
        fail("HubService", "nothing knows whether a run is on")
    if "if HubService.runOn() then\n\t\treturn" not in within(hub, "function HubService.callVote(", "\nend\n"):
        fail("HubService", "a vote can be called while a run is on")
    if "if HubService.runOn() then\n\t\twarn(" not in within(hub, "function HubService.beginRun(", "\nend\n"):
        fail("HubService", "a run can start while another is on")
    start = within(hub, "startPad.Touched:Connect(function(hit: BasePart)", "\n\tend)\n")
    if "if HubService.runOn() then" not in start or "HubService.tellBusy(stepped)" not in start:
        fail("HubService", "the Start pad starts a vote while a run is on (or does not say why it will not)")
    busy = within(hub, "function HubService.tellBusy(", "\nend\n")
    if "os.clock() - last < LOCK_TELL_GAP then\n\t\treturn" not in busy:
        fail("HubService", "standing on Start during a run says so every frame")
    if 'pcall(notify :: any, player, "busy", { playing = playing })' not in busy:
        fail("HubService", "whoever stepped on Start is never told a run is on")
    if "\tbusyTold[player] = nil\n" not in hub:
        fail("HubService", "when a player was told a run is on is kept after they leave")
    if 'elseif kind == "busy" then\n\t\t\tHubVoteService.onBusy(payload)' not in banner:
        fail("HubVoteService", "the vote card never says a run is still on")


# STORY MODE: the four levels one after another from a Story pad (always open, between the levels and the
# sandbox), each handing straight into the next once its ending is watched; a group waits in the lobby for the
# rest (STORY_WAIT at most); a fall restarts only the level you are on, and the story's Hardcore time (each level's
# own fair time added up, from City Shore in one go) goes on its own leaderboard; where you got to is kept in your
# save, and a story goes on from the furthest-behind player's place; leaving takes you out of it.
def check_story_mode():
    hub = read(HUB_SERVICE)
    boot = read(BOOTSTRAP)
    economy = read(os.path.join(ROOT, "src", "Server", "Services", "EconomyService.lua"))
    ui = read(os.path.join(ROOT, "src", "Client", "Services", "UIService.lua"))
    client_boot = read(os.path.join(ROOT, "src", "Client", "Bootstrap.client.lua"))
    banner = read(os.path.join(ROOT, "src", "Client", "Services", "HubVoteService.lua"))

    def within(text, start, stop):
        at = text.find(start)
        return text[at:text.find(stop, at + 1)] if at >= 0 else ""

    pads = within(hub, "function HubService.padLevels()", "\nend\n")
    if "table.insert(levels, STORY)\n\ttable.insert(levels, LevelDefinitions.Sandbox)" not in pads:
        fail("HubService", "there is no Story pad (between the levels and the sandbox)")
    if "\tstory = true,\n" not in hub or "HubService.STORY_ID = 100" not in hub:
        fail("HubService", "the story is not marked as one, or has no id of its own")
    if "local scaled = HubService.scaledLevel(level, current.length)" not in within(hub, "function HubService.beginRun(", "\nend\n"):
        fail("HubService", "a level from the lobby and a story's level are not scaled the same way")

    for needle, why in (
        ("HubService.setRunner(startFromLobby)", "the lobby cannot start a story"),
        ("if level.story then\n\t\treturn startStory(players, origin)\n\tend\n\tstoryRun = nil", "a story is started as a level (or a level leaves a story running)"),
    ):
        if needle not in boot:
            fail("Bootstrap", why)
    start = within(boot, "local function startStory(", "\nend\n")
    for needle, why in (
        ("from = math.min(from, at)", "a story does not go on from the furthest-behind player's place"),
        ("run.fair[player] = from == 1", "a story begun partway can set a time"),
    ):
        if needle not in start:
            fail("Bootstrap", why)
    level = within(boot, "local function storyLevel(", "\nend\n")
    for needle, why in (
        ("HubService.setLevel(level.levelId)", "a story's level is not the one the run says it is"),
        ("startChosenLevel(HubService.scaledLevel(level, run.length), going,", "a story's level is not built at its length for its players"),
        ('elseif player:GetAttribute("InSquishRoom") then', "a story pulls someone out of the squish room"),
        ("if #going == 0 then\n\t\tstoryRun = nil", "a story with nobody left builds a level for nobody"),
    ):
        if needle not in level:
            fail("Bootstrap", why)
    nxt = within(boot, "local function storyNext(", "\nend\n")
    if "\ttask.wait(STORY_FADE)\n\tendLevelWorld()\n\tlocal ok, err = pcall(storyLevel, run, nil)" not in nxt:
        fail("Bootstrap", "a story's next level is built over the last one")
    # THE MOVE BETWEEN A STORY'S LEVELS: once at a time; the screen to black and back; everyone held (anchored, and
    # passed over by the kill plane) while the last level comes down and the next goes up, and let go after.
    for needle, why in (
        ("if storyRun ~= run or run.moving then\n\t\treturn", "two moves to a story's next level can overlap"),
        ("run.moving = true\n", "a move to a story's next level is not marked as one"),
        ("\trun.moving = false\n", "a story can never move on again after one move"),
        ("storyMoving[player] = true", "a story player being moved can be taken for a fall"),
        ("ScreenFade:FireClient(player, { black = true, time = STORY_FADE })", "the move between a story's levels is not hidden"),
        ("ScreenFade:FireClient(player, { black = false, time = STORY_FADE })", "the screen stays black after a story's move"),
        ("\t\t\t\troot.Anchored = true\n", "story players fall through the space the last level left"),
        ("\tfor _, root in ipairs(held) do\n\t\troot.Anchored = false\n", "story players are left frozen at the next level's start"),
    ):
        if needle not in nxt:
            fail("Bootstrap", why)
    if "if storyMoving[player] then\n\t\t\tcontinue\n\t\tend" not in boot:
        fail("Bootstrap", "the kill plane takes a story player being moved for a fall")
    if "\tstoryLeave(player)\n\tstoryMoving[player] = nil\n" not in boot:
        fail("Bootstrap", "a story player who left during a move is kept")
    if ("if run.index >= #LevelDefinitions.All then\n\t\tstoryRun = nil\n\t\tfor player in pairs(run.players) do\n"
            "\t\t\tif player.Parent == Players and HubService.isInRun(player) then\n\t\t\t\tHubService.returnToHub(player)") not in nxt:
        fail("Bootstrap", "the end of a story does not send everyone home")
    step = within(boot, "local function storyStep(", "\nend\n")
    for needle, why in (
        ("if playing == 0 then\n\t\tstoryNext(run)", "the last to finish a story's level does not go straight on"),
        ('tellStory(player, "waiting",', "whoever finishes first is not told they are waiting"),
        ("if not run.waiting then", "a story's wait is started more than once a level"),
        ("task.delay(STORY_WAIT, function()", "a group waits for ever for someone who never finishes"),
    ):
        if needle not in step:
            fail("Bootstrap", why)
    if "HubService.returnToHub(player)\n\t\t\ttellStory(player, \"behind\")" not in within(boot, "local function storyTimeUp(", "\nend\n"):
        fail("Bootstrap", "whoever is left behind when time is up is not taken out of the story and home")
    for needle, why in (
        ("\tHubService.returnToHub(player)\n\t-- AND OUT OF THE STORY (storyLeave), so whoever is waiting in the lobby can go on.\n\tstoryLeave(player)",
         "leaving a story from the menu leaves the others waiting"),
        ("\tsecondChance.falls[player] = nil\n\t-- OUT OF THE STORY too (storyLeave): the hub has already had them back, so the rest may go on.\n\tstoryLeave(player)\n",
         "leaving the server leaves a story's others waiting"),
        ("local going = storyRun\n\t\t\tif going and going.players[player] and player.Parent then\n\t\t\t\tstoryStep(player)",
         "a story player is sent to the lobby after every level"),
        ("if state.mode == \"hardcore\" and counted then\n\t\t\t\tstory.total[player] =", "a story's time counts a level whose time did not"),
        ("if walked and EconomyService and EconomyService.setStoryAt then", "a story's place is saved for a level not walked"),
        ('pcall(LeaderboardService.submitTime, player, HubService.STORY_ID, "hardcore", total)', "a whole story's time is not on its leaderboard"),
        ("time = elapsed, story = storyInfo })", "the end of a Hardcore story level does not say where the story is"),
        ("{ levelId = levelInstance.levelId, story = storyInfo })", "the end of a Chill story level does not say where the story is"),
        ("storyRun.fair[player] = false", "someone who joins a story late can set its time"),
    ):
        if needle not in boot:
            fail("Bootstrap", why)
    if "if fair then\n\t\t\t\t\tlocal total = story.total[player]" not in boot:
        fail("Bootstrap", "a story's time goes on its leaderboard without being a fair whole story")

    for needle, why in (
        ("StoryAt = 1,", "a new save has no place in the story"),
        ("return math.clamp(math.floor(at or 1), 1, #LevelDefinitions.All)", "a story's saved place can be out of range"),
        ("profile.Data.StoryAt = math.clamp(math.floor(index), 1, #LevelDefinitions.All)", "a story's place is not saved (or out of range)"),
        ('elseif action == "storyStart" then\n\t\t-- The story from City Shore again', "the test panel cannot start the story again"),
    ):
        if needle not in economy:
            fail("EconomyService", why)
    if "function UIService.showCompletion(levelId: number?, time: number?, story: any?)" not in ui \
            or 'completionMode.Text = ("Story %d of %d. Next: %s")' not in ui or 'completionMode.Text = "Story complete"' not in ui:
        fail("UIService", "LEVEL COMPLETE does not say where the story is, or that it is complete")
    if "UIService.showCompletion(payload.levelId, payload.time, payload.story)" not in client_boot:
        fail("Bootstrap.client", "the story's place never reaches LEVEL COMPLETE")
    if 'elseif kind == "story" then\n\t\t\tHubVoteService.onStory(payload)' not in banner:
        fail("HubVoteService", "the vote card never says the story is waiting, or went on")


# THE DAILY CHEST: on the deck (its bottom on the floor, the lid resting on it), Roblox's own prompt, and opening it is
# Bootstrap's (EconomyService.claimDaily), the player told on their own card; the lid lifts on their screen only.
def check_daily_chest():
    hub = read(HUB_SERVICE)
    boot = read(BOOTSTRAP)
    banner = read(os.path.join(ROOT, "src", "Client", "Services", "HubVoteService.lua"))
    chest = hub[hub.find("local function buildDailyChest("):hub.find("function HubService.buildKiosk(")]
    for needle, why in (
        ('piece("Body", Vector3.new(3.2, 1.8, 2), CFrame.new(0, 0.9, 0)', "the daily chest does not stand on the deck"),
        ('piece("Lid", Vector3.new(3.2, 0.5, 2), CFrame.new(0, 2.05, 0)', "the daily chest's lid does not rest on it"),
        ('prompt.ActionText = "Open"', "the daily chest has no prompt"),
        ("local open = dailyChest", "opening the daily chest does nothing"),
    ):
        if needle not in chest:
            fail("HubService", why)
    if 'HubService.setDailyChest(function(player: Player)\n\t\tlocal result = EconomyService.claimDaily(player)\n\t\tHubVoteState:FireClient(player, "daily", result)' not in boot:
        fail("Bootstrap", "the daily chest is not wired to the save, or the player is not told")
    for needle, why in (
        ('elseif kind == "daily" then\n\t\t\tHubVoteService.onDaily(payload)', "the vote card never says what the daily chest did"),
        ('prompt.ActionText = if ready then "Open" else "Opened today"', "the chest's prompt does not say it was opened today"),
        ("workspace:GetServerTimeNow() >= nextAt", "the chest's prompt is not read on the server's clock"),
        ("TweenService:Create(lid, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = open }):Play()",
         "the chest's lid never lifts"),
    ):
        if needle not in banner:
            fail("HubVoteService", why)


# THE CHALLENGES BOARD: two posts with their feet on the deck, the panel held between them (its edges against
# them), a frame above and below it, the roof resting on the posts' tops; facing into the room; nothing written on it by
# the server. Each player's own screen writes their three on it (HubVoteService), and says one is done only while
# they watch it done.
def check_challenge_board():
    hub = read(HUB_SERVICE)
    banner = read(os.path.join(ROOT, "src", "Client", "Services", "HubVoteService.lua"))
    board = hub[hub.find("local function buildChallengeBoard("):hub.find("-- THE SHOP KIOSK: a striped seaside booth")]
    if not board:
        fail("HubService", "there is no challenges board")
        return
    number = r"(-?[\d.]+)"

    def part(name):
        found = re.search(r'plank\("%s", Vector3\.new\(%s, %s, %s\), CFrame\.new\(%s, %s, 0\)'
                          % (name, number, number, number, r"(-?[\d.]+|x)", number), board)
        return [0.0 if v == "x" else float(v) for v in found.groups()] if found else None

    post, panel, top, bottom, roof = part("Post"), part("Panel"), part("FrameTop"), part("FrameBottom"), part("Roof")
    sides = re.search(r"for _, x in ipairs\(\{ -([\d.]+), ([\d.]+) \}\) do\n\t\tplank\(\"Post\"", board)
    if not (post and panel and top and bottom and roof and sides) or sides.group(1) != sides.group(2):
        fail("HubService", "the challenges board is missing its posts, panel, frame or roof")
        return
    side = float(sides.group(1))
    post_w, post_h, _, _, post_y = post
    panel_w, panel_h, _, _, panel_y = panel
    near = lambda a, b: abs(a - b) < 1e-6
    if not near(post_y - post_h / 2, 0):
        fail("HubService", "the challenges board's posts do not stand on the deck")
    if not near(panel_w / 2 + post_w / 2, side):
        fail("HubService", "the challenges board's panel is not held between its posts")
    if not near(top[4] - top[1] / 2, panel_y + panel_h / 2) or not near(bottom[4] + bottom[1] / 2, panel_y - panel_h / 2):
        fail("HubService", "the challenges board's frame is not against its panel")
    if top[0] > panel_w or bottom[0] > panel_w or panel_y + panel_h / 2 + top[1] > post_y + post_h / 2:
        fail("HubService", "the challenges board's frame reaches past its posts")
    if not near(roof[4] - roof[1] / 2, post_y + post_h / 2) or roof[0] < 2 * side + post_w:
        fail("HubService", "the challenges board's roof does not rest on its posts")
    for needle, why in (
        ("local facing = CFrame.lookAt(at, Vector3.new(ARCADE.X, at.Y, ARCADE.Z))",
         "the challenges board does not face the arcade's middle"),
        ("part.CFrame = facing * offset", "the challenges board's pieces are not set by its facing"),
    ):
        if needle not in board:
            fail("HubService", why)
    if "SurfaceGui" in board or "TextLabel" in board:
        fail("HubService", "the server writes on the challenges board, the same for everyone")
    if "buildChallengeBoard(HUB_ORIGIN + AT.challenges, folder)" not in hub:
        fail("HubService", "the challenges board is never built")
    for needle, why in (
        ('local board = hub and hub:FindFirstChild("ChallengeBoard")', "nobody's screen finds the challenges board"),
        ("gui.Face = Enum.NormalId.Front", "the challenges are written on the back of the board"),
        ('gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")', "the challenges board is written the same for everyone"),
        ("gui.Adornee = panel", "the challenges are not written on the board's panel"),
        ('if name == "Challenges" or name == "ChallengesDone" then\n\t\t\t\tnoticeDone()',
         "a challenge done is not noticed (or a new day mistaken for one)"),
        ('if type(ids) == "string" and ids == knownIds and seenDone then', "a save loading or a new day is told as challenges done"),
        ('seenDone = type(doneValue) == "string"', "a challenge done earlier today is told again on joining"),
        ('HubVoteService.say("+" .. reward, title,', "the card never says a challenge is done"),
        ('foot.Text = ("New ones in %dh %02dm")', "the board does not say when new challenges come"),
        ("left = math.max(0, nextAt - workspace:GetServerTimeNow())", "the board's countdown is not on the server's clock"),
    ):
        if needle not in banner:
            fail("HubVoteService", why)
    if 'model.Name = name or "ChallengeBoard"' not in board:
        fail("HubService", "the materials board is named like the challenges board, so one screen finds the other")
    for needle, why in (
        ('local board = hub and hub:FindFirstChild("MaterialsBoard")', "nobody's screen finds the materials board"),
        ("face.Face = Enum.NormalId.Front", "the materials are written on the back of their board"),
        ('face.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")', "the materials board is written the same for everyone"),
        ("face.Adornee = panel", "the materials are not written on their board's panel"),
        ('cell.name.Text = if got then material.name else "?"', "the materials board gives away the ones still to find"),
        ('title.Text = ("Materials found  %d of %d"):format(found, #shop.MATERIALS)', "the materials board does not say how many"),
        ('Players.LocalPlayer:GetAttributeChangedSignal("Materials"):Connect(drawMaterials)',
         "the materials board does not change as you find them"),
    ):
        if needle not in banner:
            fail("HubVoteService", why)


# THE POST BOX: its plinth on the deck, the body standing on the plinth, the cap on the body's top; the slot and the
# plate on its face; Roblox's own prompt on it, heard by each player's own screen.
def check_post_box():
    hub = read(HUB_SERVICE)
    shop = read(os.path.join(ROOT, "src", "Client", "Services", "ShopService.lua"))
    box = hub[hub.find("local function buildPostBox("):hub.find("-- THE CHALLENGES BOARD: a notice board on two posts")]
    if not box:
        fail("HubService", "there is no post box")
        return
    number = r"(-?[\d.]+)"

    def round_part(name):
        found = re.search(r'pillar\("%s", Vector3\.new\(%s, %s, %s\), CFrame\.new\(0, %s, 0\), \w+, true\)'
                          % (name, number, number, number, number), box)
        return [float(v) for v in found.groups()] if found else None

    plinth, body, cap = round_part("Plinth"), round_part("Body"), round_part("Cap")
    if not (plinth and body and cap):
        fail("HubService", "the post box is missing its plinth, body or cap")
        return
    near = lambda a, b: abs(a - b) < 1e-6
    if not near(plinth[3] - plinth[0] / 2, 0):
        fail("HubService", "the post box's plinth does not stand on the deck")
    if not near(body[3] - body[0] / 2, plinth[3] + plinth[0] / 2):
        fail("HubService", "the post box's body does not stand on its plinth")
    if not near(cap[3] - cap[0] / 2, body[3] + body[0] / 2):
        fail("HubService", "the post box's cap does not rest on its body")
    for needle, why in (
        ("made.Shape = Enum.PartType.Cylinder", "the post box is not round"),
        ("made.CFrame = front * offset * (if round then CFrame.Angles(0, 0, math.rad(90)) else CFrame.identity)",
         "the post box's round pieces lie on their sides"),
        ('pillar("Slot", Vector3.new(1, 0.16, 0.12), CFrame.new(0, 3.4, -1)', "the post box's slot is not on its face"),
        ('prompt.Name = "CodePrompt"', "the post box has no prompt"),
        ('prompt.ActionText = "Post a code"', "the post box's prompt does not say what it is for"),
    ):
        if needle not in box:
            fail("HubService", why)
    if "buildPostBox(HUB_ORIGIN + AT.postBox, folder)" not in hub:
        fail("HubService", "the post box is never built")
    if 'elseif prompt.Name == "CodePrompt" and who == Players.LocalPlayer then\n\t\t\tShopService.openCodes()' not in shop:
        fail("ShopService", "the post box's prompt opens nothing")


def main():
    check_post_box()
    check_challenge_board()
    check_daily_chest()
    check_story_mode()
    check_one_run_at_a_time()
    check_levels_open_in_order()
    check_dashboard()
    check_paste_check()
    check_leaving()
    check_board_reads()
    check_runs_end()
    check_statues()
    check_countdown_ticks_evenly()
    check_pad_looks()
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

