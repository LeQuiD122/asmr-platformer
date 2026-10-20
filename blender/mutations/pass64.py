"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 64: the back rooms. Open to the void; floor cut off; the sealed room opened; no way out, or one beside where
you arrive; tubes too far apart, too bright, Neon, or a stutter that goes dark; walls short of the ceiling, panels
hanging below it; built beside the lobby; reached after two falls, or every fall after; caught by the kill plane;
the client not told; never built; a respawn left in them; the way out not putting you back (either mode, or an
ended run); no prompt; no hum.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ROOMS = S / "Server/Services/BackRoomsService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
AMB = S / "Client/Services/AmbienceService.lua"
CHECK, PARSE = "check_backrooms.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

# Mutations of the map that touch two rows, built from the map as it stands.
TEXT = ROOMS.read_text(encoding="utf-8").replace("\r\n", "\n")
ROW1 = '\t"#S......#............#...........#",\n'
ROW2 = '\t"#.......#............#...........#",\n'
ROW20 = '\t"#................#....##.........D",\n'
# The way out moved into the wall beside where you arrive (row 2, x = 0), and the real one walled up.
start, end = TEXT.index(ROW1), TEXT.index(ROW20) + len(ROW20)
BLOCK = TEXT[start:end]
DOOR_NEAR = BLOCK.replace(ROW1 + ROW2, ROW1 + '\t"D.......#............#...........#",\n', 1) \
    .replace(ROW20, '\t"#................#....##.........#",\n')

MUTATIONS = [
    ("open to the void", ROOMS, CHECK, ROW1, '\t".S......#............#...........#",\n'),
    ("floor cut off", ROOMS, CHECK, ROW1 + ROW2, '\t"#S#.....#............#...........#",\n\t"###.....#............#...........#",\n'),
    ("the sealed room opened", ROOMS, CHECK, '\t"#...........#....#...Lxxxxxxx#...#",\n', '\t"#...........#....#....xxxxxxx#...#",\n'),
    ("no way out", ROOMS, CHECK, ROW20, '\t"#................#....##.........#",\n'),
    ("the way out beside the arrival", ROOMS, CHECK, BLOCK, DOOR_NEAR),
    ("tubes too far apart", ROOMS, CHECK, "x % 3 == 2 and y % 3 == 2", "x % 5 == 2 and y % 5 == 2"),
    ("too bright", ROOMS, CHECK, "local LIGHT_BRIGHTNESS = 0.9", "local LIGHT_BRIGHTNESS = 3"),
    ("Neon", ROOMS, CHECK, "CFrame.new(tileAt(x, y, HEIGHT - 0.1)), PANEL, Enum.Material.SmoothPlastic, made)",
     "CFrame.new(tileAt(x, y, HEIGHT - 0.1)), PANEL, Enum.Material.Neon, made)"),
    ("a stutter that goes dark", ROOMS, CHECK, "failing.Brightness = LIGHT_BRIGHTNESS * 0.33", "failing.Brightness = 0"),
    ("walls short of the ceiling", ROOMS, CHECK, 'part("Wall", Vector3.new(span * TILE, HEIGHT, TILE)',
     'part("Wall", Vector3.new(span * TILE, HEIGHT - 2, TILE)'),
    ("panels hanging", ROOMS, CHECK, "CFrame.new(tileAt(x, y, HEIGHT - 0.1))", "CFrame.new(tileAt(x, y, HEIGHT - 1))"),
    ("beside the lobby", ROOMS, CHECK, "local ORIGIN = Vector3.new(-9000, 600, -9000)", "local ORIGIN = Vector3.new(-300, 600, -900)"),
    ("after two falls", BOOT, CHECK, "local BACKROOMS_FALLS = 7", "local BACKROOMS_FALLS = 2"),
    ("every fall after", BOOT, CHECK, "state.falls >= BACKROOMS_FALLS and not state.backRooms then",
     "state.falls >= BACKROOMS_FALLS then"),
    ("caught by the kill plane", BOOT, CHECK,
     '\t\tif player:GetAttribute("InLevel") == "backRooms" then\n\t\t\tcontinue\n\t\tend\n', ""),
    ("the client not told", BOOT, CHECK, '\tplayer:SetAttribute("InLevel", "backRooms")\n', ""),
    ("never built", BOOT, CHECK, "pcall(BackRoomsService.build, leaveBackRooms)", "true, nil"),
    ("a respawn left in them", BOOT, CHECK,
     '\t\t\tplayer:SetAttribute("InLevel", if inRunNow then runBackdrop else nil)\n', ""),
    ("Hardcore not sent back", BOOT, CHECK, "\t\t\trestartRunFor(player)\n\t\t\tTimerService.resetTimer(player)\n",
     "\t\t\tTimerService.resetTimer(player)\n"),
    ("Chill not sent back", BOOT, CHECK,
     "CHILL_SETBACK_STUDS\n\t\t\thrp.CFrame = CFrame.new(groundedRecovery(behind, state.checkpointPosition))\n",
     "CHILL_SETBACK_STUDS\n"),
    ("left there when the run is over", BOOT, CHECK,
     "\telse\n\t\tHubService.returnToHub(player)\n\tend\n\tScreenFade:FireClient(player, { black = false, time = 0.7 })",
     "\tend\n\tScreenFade:FireClient(player, { black = false, time = 0.7 })"),
    ("still told it is there", BOOT, CHECK, '\t\tplayer:SetAttribute("InLevel", runBackdrop)\n\t\tif state.mode == "hardcore" then\n\t\t\trestartRunFor',
     '\t\tif state.mode == "hardcore" then\n\t\t\trestartRunFor'),
    ("no prompt", ROOMS, CHECK, 'prompt.ActionText = "Go back"', 'prompt.ActionText = ""'),
    ("no hum", AMB, CHECK, '\tbackRooms = {\n\t\t{ name = "BathsHum", volume = 0.55 },\n', '\tbackRooms = {\n'),
    ("the self-test not looking", S / "Server/Services/EconomyService.lua", CHECK,
     'check("the back rooms built, with one way out", wayOut == 1,', 'check("the back rooms built, with one way out", true,'),
    ("a name never declared", ROOMS, PARSE, "\tmade.Name = \"BackRooms\"\n\tlocal rows, cols = #MAP, #MAP[1]\n",
     "\tmade.Name = \"BackRooms\"\n\tlocal rows, cols = #MAP, #MAPS[1]\n"),
]

paths = {m[1] for m in MUTATIONS}
originals = {path: path.read_bytes() for path in paths}
missed = []
try:
    for label, path, checker, old, new in MUTATIONS:
        text = originals[path].decode("utf-8").replace("\r\n", "\n")
        assert text.count(old) == 1, "%s: anchor found %d times" % (label, text.count(old))
        assert old != new, "%s: no change" % label
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
