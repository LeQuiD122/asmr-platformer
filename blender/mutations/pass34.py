"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 34: what only shows with many players, in the store. A board read on every look, kept too briefly, read
twice at once, left marked as being read after a failure, blanked by a failure, slow to show a new time, or
blind to the season turning; a personal best read on every redraw, shown late after a new one, or kept after
its player has gone.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
LEAD = S / "Server/Services/LeaderboardService.lua"
BEST = S / "Server/Services/BestTimeService.lua"
HUBCHECK, PARSE = "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUBCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("read on every look", LEAD, HUBCHECK, "if kept and os.clock() - kept.at < FRESH then\n\t\treturn table.clone(kept.rows)",
     "if false then\n\t\treturn table.clone(kept.rows)"),
    ("kept a moment", LEAD, HUBCHECK, "local FRESH = 30", "local FRESH = 1"),
    ("read twice at once", LEAD, HUBCHECK, "\tif fetching[key] then\n", "\tif false then\n"),
    ("stuck after a failure", LEAD, HUBCHECK,
     "\t\tfetching[key] = nil\n\t\tfailedAt[key] = os.clock()", "\t\tfailedAt[key] = os.clock()"),
    ("blank after a failure", LEAD, HUBCHECK,
     "\t\tend\n\t\treturn if kept then table.clone(kept.rows) else {}\n\tend\n\tlocal results = {}",
     "\t\tend\n\t\treturn {}\n\tend\n\tlocal results = {}"),
    ("a new time shown late", LEAD, HUBCHECK, "\tif improved then\n\t\tforget(levelId, mode)\n\tend\n", ""),
    ("blind to the season", LEAD, HUBCHECK, 'local key = boardName(levelId, mode) .. "#" .. tostring(count)',
     'local key = tostring(levelId) .. mode .. "#" .. tostring(count)'),
    ("your best read every redraw", BEST, HUBCHECK, "if kept and os.clock() - kept.at < FRESH then\n\t\treturn kept.value",
     "if false then\n\t\treturn kept.value"),
    ("a new best shown late", BEST, HUBCHECK, "\tremember(player, key, timeSeconds)\n", ""),
    ("bests kept after leaving", BEST, HUBCHECK, "\tknown[player] = nil\n", ""),
    ("a name never declared", LEAD, PARSE, 'local prefix = boardName(levelId, mode) .. "#"', 'local prefix = boardNam(levelId, mode) .. "#"'),
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
