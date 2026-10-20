"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 39: the dashboard's view of the levels. A start, a late joiner's start, a finish, leaving from the menu or
leaving the server not logged; a finish logged as a fail; the logging unguarded; the kiosk's visits uncounted.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
HUB = S / "Server/Services/HubService.lua"
HUBCHECK, PARSE = "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUBCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a start not logged", BOOT, HUBCHECK, '\t\tprogression(player, "start")\n\t\t-- The mode the run ACTUALLY',
     "\t\t-- The mode the run ACTUALLY"),
    ("a late joiner's start not logged", BOOT, HUBCHECK, '\tHubService.markInRun({ player })\n\tprogression(player, "start")\n',
     "\tHubService.markInRun({ player })\n"),
    ("a finish not logged", BOOT, HUBCHECK, '\t\tprogression(player, "complete")\n', ""),
    ("leaving from the menu not logged", BOOT, HUBCHECK, '\t\tprogression(player, "fail")\n\t\t-- THE CLOCK STOPS',
     "\t\t-- THE CLOCK STOPS"),
    ("leaving the server not logged", BOOT, HUBCHECK, '\tif runningFor[player] then\n\t\tprogression(player, "fail")\n\tend\n', ""),
    ("a finish logged as a fail", BOOT, HUBCHECK,
     'elseif status == "complete" then\n\t\t\tAnalyticsService:LogProgressionCompleteEvent(',
     'elseif status == "complete" then\n\t\t\tAnalyticsService:LogProgressionFailEvent('),
    ("the logging unguarded", BOOT, HUBCHECK, '\tpcall(function()\n\t\tif status == "start" then',
     '\t(function()\n\t\tif status == "start" then'),
    ("the kiosk's visits uncounted", HUB, HUBCHECK, 'LogCustomEvent(player, "ShopKiosk")', 'LogCustomEvent(player, "Shop")'),
    ("a name never declared", BOOT, PARSE, "local level = HubService.levelById(instance.levelId)",
     "local level = HubService.levelById(instanse.levelId)"),
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
