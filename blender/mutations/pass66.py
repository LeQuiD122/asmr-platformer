"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 66: the back rooms are the sixth secret. Not a secret; the count left at five; asked after being marked found
(never told), told every time, told under the black, told to someone gone, never told; nothing to look at; and a
dash in its words.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
INTER = S / "Server/Services/Interactables.lua"
BOOT = S / "Server/Bootstrap.server.lua"
ROOMS = S / "Server/Services/BackRoomsService.lua"
BACK, STORY, PARSE = "check_backrooms.py", "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (BACK, STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

FIRST = "\tlocal first = not (EconomyService and EconomyService.foundBackRooms and EconomyService.foundBackRooms(player))\n"

MUTATIONS = [
    ("not a secret", INTER, BACK, 'backRooms = { order = 6, title = "The back rooms"', 'backroom = { order = 6, title = "The back rooms"'),
    ("the count left at five", INTER, STORY, "local TOTAL = 6", "local TOTAL = 5"),
    ("asked after being marked found", BOOT, BACK,
     FIRST + '\tenterBackRooms(player, hrp, "fall")\n\tif EconomyService and EconomyService.markFoundBackRooms then\n'
     "\t\tpcall(EconomyService.markFoundBackRooms, player)\n\tend\n",
     '\tenterBackRooms(player, hrp, "fall")\n\tif EconomyService and EconomyService.markFoundBackRooms then\n'
     "\t\tpcall(EconomyService.markFoundBackRooms, player)\n\tend\n" + FIRST),
    ("told every time", BOOT, BACK, "if first and Interactables and Interactables.reveal and BackRoomsService.secretShot then",
     "if Interactables and Interactables.reveal and BackRoomsService.secretShot then"),
    ("told under the black", BOOT, BACK, "\t\ttask.delay(1.2, function()\n\t\t\tlocal eye, focus, anchor", "\t\ttask.spawn(function()\n\t\t\tlocal eye, focus, anchor"),
    ("told to someone gone", BOOT, BACK, 'if eye and focus and anchor and player.Parent and player:GetAttribute("InLevel") == "backRooms" then',
     "if eye and focus and anchor then"),
    ("never told", BOOT, BACK, '\t\t\t\tpcall(Interactables.reveal, player, "backRooms", eye, focus, anchor)\n', ""),
    ("nothing to look at", ROOMS, BACK, 'noticePlate = sign("Notice",', 'sign("Notice",'),
    ("a dash in its words", INTER, STORY, '"Staff only. You came down once too often."', '"Staff only -- you came down once too often."'),
    ("a name never declared", BOOT, PARSE, "\t\t\tlocal eye, focus, anchor = BackRoomsService.secretShot()\n",
     "\t\t\tlocal eye, focus, anchor = BackRoomService.secretShot()\n"),
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
