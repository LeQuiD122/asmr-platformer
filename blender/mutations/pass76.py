"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 76: what the review of passes 18 to 49 found. A place on the board read and written in two steps again, or a
slower time written over a better one; a best read and written in two steps, a slower one written, a stored 0
standing in the way, or a new best not said; an emote's stop passed on for anyone at all, more than once, never for
an emote played, or a player who left kept.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
LEAD = S / "Server/Services/LeaderboardService.lua"
BEST = S / "Server/Services/BestTimeService.lua"
ECON = S / "Server/Services/EconomyService.lua"
HUBCHECK, SHOP, PARSE = "check_hub.py", "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUBCHECK, SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the board read and written in two steps", LEAD, HUBCHECK,
     "\t\tstore:UpdateAsync(key, function(existing: any): any\n\t\t\timproved = false\n\t\t\tif typeof(existing) == \"number\" and existing > 0 and existing <= stored then",
     "\t\tlocal existing = store:GetAsync(key)\n\t\tdo\n\t\t\timproved = false\n\t\t\tif typeof(existing) == \"number\" and existing > 0 and existing <= stored then"),
    ("a slower time over a better on the board", LEAD, HUBCHECK,
     'if typeof(existing) == "number" and existing > 0 and existing <= stored then',
     'if typeof(existing) == "number" and existing > 0 and existing < 0 then'),
    ("a best read and written in two steps", BEST, SHOP,
     "\t\tstore:UpdateAsync(key, function(existing: any): any\n",
     "\t\tstore:SetAsync(key, timeSeconds)\n\t\tstore:UpdateAsync(key, function(existing: any): any\n"),
    ("a slower best written", BEST, SHOP, 'if typeof(existing) == "number" and existing > 0 and existing <= timeSeconds then',
     'if typeof(existing) == "number" and existing > 0 and existing < 0 then'),
    ("a stored 0 in the way", BEST, SHOP, 'if typeof(existing) == "number" and existing > 0 and existing <= timeSeconds then',
     'if typeof(existing) == "number" and existing <= timeSeconds then'),
    ("a new best not said", BEST, SHOP, "\t\tremember(player, key, timeSeconds)\n\t\treturn true\n",
     "\t\tremember(player, key, timeSeconds)\n\t\treturn false\n"),
    ("a stop passed on for anyone", ECON, SHOP, '\tif id == "stop" then\n\t\tif not emoting[player] then\n\t\t\treturn\n\t\tend\n',
     '\tif id == "stop" then\n'),
    ("a stop passed on more than once", ECON, SHOP, '\t\temoting[player] = nil\n\t\tremote:FireAllClients(player, "stop"',
     '\t\tremote:FireAllClients(player, "stop"'),
    ("a stop never passed on", ECON, SHOP, "\temoting[player] = true\n\tremote:FireAllClients(player, item.id",
     "\tremote:FireAllClients(player, item.id"),
    ("a player who left kept", ECON, SHOP, "\t\tlastJournal[player] = nil\n\t\temoting[player] = nil\n",
     "\t\tlastJournal[player] = nil\n"),
    ("a name never declared", BEST, PARSE, "\t\tremember(player, key, kept)\n", "\t\tremember(player, key, keep)\n"),
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
