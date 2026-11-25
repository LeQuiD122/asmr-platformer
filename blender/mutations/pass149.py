"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 149: the run screen's presses. The clock folding or opening in silence; the best times put away in
silence; the helper never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
UIS = S / "Client/Services/UIService.lua"
POLISH, PARSE = "check_polish.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (POLISH, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the clock folds in silence', UIS, POLISH, '\tpressSound("close")\n\ttimerFolded = true', '\ttimerFolded = true'),
    ('the clock opens in silence', UIS, POLISH, '\tpressSound("open")\n\ttimerFolded = false', '\ttimerFolded = false'),
    ('the best times put away in silence', UIS, POLISH, '\tpressSound(if leaderboardOpen then "open" else "close")\n', ''),
    ("the run screen's helper never declared", UIS, PARSE, 'local function pressSound(kind: string)', 'local function pressSounds(kind: string)'),
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
