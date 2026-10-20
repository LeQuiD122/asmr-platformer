"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 65: the lobby's back corridor leads to the back rooms, for someone who has found them. A corridor you fall
through; no way in at its end, or one that does nothing; one that works from a run or the squish room; one that lets
anyone in (the secret out); one that goes nowhere; a fall into them not counted as finding them; not kept in the
save; no test button.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUB = S / "Server/Services/HubService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
ECON = S / "Server/Services/EconomyService.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
CHECK, PARSE = "check_backrooms.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a corridor you fall through", HUB, CHECK, "\t\t\titem.CanCollide = true\n", "\t\t\titem.CanCollide = false\n"),
    ("no way in at its end", HUB, CHECK, "\tthreshold.CanTouch = true\n", "\tthreshold.CanTouch = false\n"),
    ("a way in that does nothing", HUB, CHECK, "\t\tlocal enter = backRoomsDoor\n", "\t\tlocal enter = nil\n"),
    ("from a run or the squish room", BOOT, CHECK,
     'if HubService.isInRun(player) or player:GetAttribute("InLevel") ~= nil or player:GetAttribute("InSquishRoom") then',
     'if player:GetAttribute("InLevel") == "backRooms" then'),
    ("anyone let in", BOOT, CHECK,
     "\t\tif not (EconomyService and EconomyService.foundBackRooms and EconomyService.foundBackRooms(player)) then\n\t\t\treturn\n\t\tend\n",
     ""),
    ("a way in to nowhere", BOOT, CHECK, '\t\t\tenterBackRooms(player, found, "lobby")\n\t\tend\n\tend)\nend\n',
     "\t\tend\n\tend)\nend\n"),
    ("a fall not counted as finding them", BOOT, CHECK,
     "\tif EconomyService and EconomyService.markFoundBackRooms then\n\t\tpcall(EconomyService.markFoundBackRooms, player)\n\tend\n\t-- A Hardcore fall",
     "\t-- A Hardcore fall"),
    ("not kept in the save", ECON, CHECK, "\t\tprofile.Data.FoundBackRooms = true\n", ""),
    ("no test button", DEV, CHECK, '\t{ action = "backRooms", text = "Back rooms" },\n', ""),
    ("a name never declared", HUB, PARSE, "\t\tlocal enter = backRoomsDoor\n", "\t\tlocal enter = backRoomDoor\n"),
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
