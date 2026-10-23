"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 90: the back rooms, from the second test. He comes before you have looked round, never, or always early; he
walks as fast as you; he catches you from across a room; he never leaves the staff door or finds his way to you; the
lights near him steady; being caught doing nothing, or never seen, or not taking you to the lobby; nothing telling you
he is out; he follows you out; nothing walks at all; "Leave to the lobby" doing nothing down here; the lobby's sea
following you in (or its wind, set again by the server, or a breaker made while you are there, or the whole lobby
put back after a run), or the lobby silent after you leave; nothing sunk in the rooms, a sunk thing in your way, reaching across a corridor, or stretched across
it; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
AMB = S / "Client/Services/AmbienceService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
ROOMS = S / "Server/Services/BackRoomsService.lua"
STORYC = S / "Client/Services/StoryClient.lua"
ROOMSCHECK, PARSE = "check_backrooms.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (ROOMSCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('he comes too soon', ROOMS, ROOMSCHECK, 'local HUNT_AFTER, HUNT_CHANCE, HUNT_EARLY = 30, 0.35, NumberRange.new(12, 18)', 'local HUNT_AFTER, HUNT_CHANCE, HUNT_EARLY = 30, 0.35, NumberRange.new(3, 6)'),
    ('he always comes early', ROOMS, ROOMSCHECK, 'local HUNT_AFTER, HUNT_CHANCE, HUNT_EARLY = 30, 0.35,', 'local HUNT_AFTER, HUNT_CHANCE, HUNT_EARLY = 30, 1,'),
    ('he walks as fast as you', ROOMS, ROOMSCHECK, 'local WALK, WALK_LATE, CATCH = 11.5, 13.5, 3.2', 'local WALK, WALK_LATE, CATCH = 11.5, 16, 3.2'),
    ('he catches from across a room', ROOMS, ROOMSCHECK, 'local WALK, WALK_LATE, CATCH = 11.5, 13.5, 3.2', 'local WALK, WALK_LATE, CATCH = 11.5, 13.5, 9'),
    ('not out of the staff door', ROOMS, ROOMSCHECK, 'staffTile = { x = x + step[1], y = y + step[2] }', 'staffTile = { x = 1, y = 1 }'),
    ('not finding his way', ROOMS, ROOMSCHECK, 'path = wayTo(hx, hy, tx, ty)', 'path = { { x = tx, y = ty } }'),
    ('the lights steady near him', ROOMS, ROOMSCHECK, 'light.Brightness = LIGHT_BRIGHTNESS * (if math.random() < 0.6 then 0.12 else 0.4)', 'light.Brightness = LIGHT_BRIGHTNESS'),
    ('being caught doing nothing', ROOMS, ROOMSCHECK, '\t\t\tpcall(hunt.onCaught, player, head.Position)\n', ''),
    ('nothing tells you', ROOMS, ROOMSCHECK, 'remote:FireClient(player, "stalk", { at = head.Position, door = ', 'local _ = ({ at = head.Position, door = '),
    ('he follows you out', BOOT, ROOMSCHECK, '\tif BackRoomsService.callOff then\n\t\tBackRoomsService.callOff(player)\n\tend\n\tplayer:SetAttribute("BackRoomsFrom", nil)\n\tlocal character', '\tplayer:SetAttribute("BackRoomsFrom", nil)\n\tlocal character'),
    ('nothing walks', BOOT, ROOMSCHECK, '\t\tBackRoomsService.hunt(player, caughtInBackRooms)\n', ''),
    ('being caught unseen', BOOT, ROOMSCHECK, 'story:FireClient(player, "caught", { at = at })', 'local _ = story'),
    ('being caught not the lobby', BOOT, ROOMSCHECK, '\t\tsyncTimer(player)\n\t\tHubService.returnToHub(player)\n\t\tstoryLeave(player)\n\telse\n\t\tHubService.returnToHub(player)\n\tend\n', '\t\tsyncTimer(player)\n\t\tstoryLeave(player)\n\tend\n'),
    ('leaving does nothing', BOOT, ROOMSCHECK, 'backRoomsLeave = leaveBackRooms\n', ''),
    ('no scene for being caught', STORYC, ROOMSCHECK, 'elseif kind == "caught" and typeof(data) == "table" then\n\t\t\t\tcaught(data)', 'elseif kind == "caught" and typeof(data) == "table" then\n\t\t\t\tlocal _ = data'),
    ('no word he is out', STORYC, ROOMSCHECK, 'elseif kind == "stalk" and typeof(data) == "table" then\n\t\t\t\tstalked(data)', 'elseif kind == "stalk" and typeof(data) == "table" then\n\t\t\t\tlocal _ = data'),
    ("the lobby's sea down here", AMB, ROOMSCHECK, '\t\thushLobby(wanted ~= nil)\n', ''),
    ("the wind's volume set again", AMB, ROOMSCHECK, '\t\titem.SoundGroup = lobbyGroup()\n', '\t\titem.Volume = 0\n'),
    ('a new breaker heard', AMB, ROOMSCHECK, '\ttable.insert(hushWatch, hub.DescendantAdded:Connect(intoHush))\n', ''),
    ('the lobby back after a run heard', AMB, ROOMSCHECK, 'if child.Name == "Hub" then\n\t\t\t\twatchHub(child)', 'if child.Name == "Hub" then\n\t\t\t\tlocal _ = child'),
    ('the lobby silent after', AMB, ROOMSCHECK, 'TweenService:Create(group, TweenInfo.new(1.5), { Volume = 1 }):Play()', 'TweenService:Create(group, TweenInfo.new(1.5), { Volume = 0 }):Play()'),
    ('nothing sunk', ROOMS, ROOMSCHECK, '\tsinkThings(made)\n', ''),
    ('a sunk thing in your way', ROOMS, ROOMSCHECK, '\tp.CanCollide = false\n\tp.CanQuery = false\n\tp.CanTouch = false\n\treturn p\nend\n\n-- Each built', '\tp.CanCollide = true\n\tp.CanQuery = false\n\tp.CanTouch = false\n\treturn p\nend\n\n-- Each built'),
    ('reaching across a corridor', ROOMS, ROOMSCHECK, 'math.max(rng:NextNumber(0.4, 0.62), 1 - WALL_REACH / long)', 'rng:NextNumber(0.4, 0.62)'),
    ('stretched across a corridor', ROOMS, ROOMSCHECK, 'if wrong == "tall" or (wrong == "giant" and THINGS[name].tall > 2) then', 'if wrong == "tall" then'),
    ('a name never declared', ROOMS, PARSE, 'path = wayTo(hx, hy, tx, ty)', 'path = wayTo(hx, hy, tx, tys)'),
]

paths = {m[1] for m in MUTATIONS}
originals = {path: path.read_bytes() for path in paths}
missed = []
try:
    for label, path, checker, old, new in MUTATIONS:
        text = originals[path].decode("utf-8").replace("\r\n", "\n")
        assert text.count(old) == 1, "%s: anchor found %d times" % (label, text.count(old))
        path.write_bytes(text.replace(old, new).encode("utf-8"))
        result = run(checker)
        path.write_bytes(originals[path])
        caught = result.returncode != 0
        why = [line.strip() for line in (result.stdout + result.stderr).splitlines()
               if line.startswith("  ") or line.startswith("FAIL")][:2]
        print("%-8s %s  %s" % ("caught" if caught else "MISSED", label, "; ".join(why)[:170]))
        if not caught:
            missed.append(label)
finally:
    for path, data in originals.items():
        path.write_bytes(data)
print("\n%d of %d caught" % (len(MUTATIONS) - len(missed), len(MUTATIONS)))
sys.exit(1 if missed else 0)
