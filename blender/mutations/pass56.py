"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 56: the climb through the levels on the dashboard, and the Self-test opening and locking a level through the
lobby. A first finish not counted, counted on every finish, or unguarded; a locked pad not counted, or counted on
every step; who stepped kept after they leave; the self-test not checking City Shore, not opening Sky Pools, not
seeing it lock again, passing with nothing wired, or leaving the lobby as it made it; the reader never wired.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ECON = S / "Server/Services/EconomyService.lua"
HUB = S / "Server/Services/HubService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
SHOP, HUBCHECK, PARSE = "check_shop.py", "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, HUBCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

FIRST_LOG = ('\t\t-- THE DASHBOARD: each level\'s first finish in a save (FirstFinish_<level id>), the climb through the levels.\n'
             '\t\tpcall(function()\n\t\t\tAnalyticsService:LogCustomEvent(player, ("FirstFinish_%d"):format(levelId))\n\t\tend)\n')

MUTATIONS = [
    ("a first finish not counted", ECON, HUBCHECK, FIRST_LOG, ""),
    ("counted on every finish", ECON, HUBCHECK,
     "\tif levelId ~= nil and finished[tostring(levelId)] ~= true then\n\t\tfinished[tostring(levelId)] = true\n\t\ttellLevels()\n" + FIRST_LOG + "\tend\n",
     "\tif levelId ~= nil and finished[tostring(levelId)] ~= true then\n\t\tfinished[tostring(levelId)] = true\n\t\ttellLevels()\n\tend\n"
     '\tpcall(function()\n\t\tAnalyticsService:LogCustomEvent(player, ("FirstFinish_%d"):format(levelId or 0))\n\tend)\n'),
    ("unguarded", ECON, HUBCHECK, '\t\tpcall(function()\n\t\t\tAnalyticsService:LogCustomEvent(player, ("FirstFinish_%d"):format(levelId))\n\t\tend)\n',
     '\t\tAnalyticsService:LogCustomEvent(player, ("FirstFinish_%d"):format(levelId))\n'),
    ("a locked pad not counted", HUB, HUBCHECK,
     '\t\t\tgame:GetService("AnalyticsService"):LogCustomEvent(player, ("LockedPad_%d"):format(levelId))\n', ""),
    ("counted on every step", HUB, HUBCHECK, "\tif not logged[levelId] then\n\t\tlogged[levelId] = true\n", "\tif true then\n"),
    ("kept after leaving", HUB, HUBCHECK, "\tlockLogged[player] = nil\n", ""),
    ("City Shore not checked", ECON, SHOP, '\t\t\tcheck("City Shore is open", isOpen(opener.levelId) == true)\n', ""),
    ("Sky Pools not opened", ECON, SHOP, "\t\t\tfinished[key] = true\n\t\t\ttellLevels()\n", "\t\t\ttellLevels()\n"),
    ("not seen locking again", ECON, SHOP, "isOpen(opened.levelId) == others)", "true)"),
    ("passing with nothing wired", ECON, SHOP,
     'check("the lobby reads the saves", false, "no lobby wired to the save: paste the current server Bootstrap")',
     'check("the lobby reads the saves", true)'),
    ("the lobby left as the test made it", ECON, SHOP, "\tstepGear(player)\n\ttellLevels()\n", "\tstepGear(player)\n"),
    ("the reader never wired", BOOT, SHOP, "\t\tEconomyService.setOpenReader(HubService.isOpen)\n", ""),
    ("a name never declared", ECON, PARSE, "local key = tostring(opener.levelId)", "local key = tostring(openr.levelId)"),
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
