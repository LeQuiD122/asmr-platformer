"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 197: over and under itself. Back on the line it came up, not as deep as its own height, no lean, too much lean,
the way back at its depth, drawn at one depth, no lean drawn, a spike out of the dark, the heave's reach not widened;
(199) a turn no wider than its body (its skin a web across the loop), a turn into the sea floor.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
PATH = S / "Shared/SunkenPath.lua"
LETGO = "check_letgo.py"
SUNK = "check_sunkencity.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (LETGO, SUNK):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('back on the line it came up', PATH, LETGO, 'return span - r - (within - run - turn), 2 * r, 0', 'return span - r - (within - run - turn), 0, 0'),
    ('not as deep as its height', PATH, LETGO, 'SunkenPath.DIVE = 48', 'SunkenPath.DIVE = 10'),
    ('a turn no wider than its body', PATH, LETGO, 'SunkenPath.DIVE = 48', 'SunkenPath.DIVE = 24'),
    ('a turn into the sea floor', PATH, SUNK, 'SunkenPath.DIVE = 48', 'SunkenPath.DIVE = 70'),
    ('no lean', PATH, LETGO, 'SunkenPath.TURN_SIDE = 1\n', 'SunkenPath.TURN_SIDE = 0\n'),
    ('too much lean', PATH, LETGO, 'SunkenPath.TURN_SIDE = 1\n', 'SunkenPath.TURN_SIDE = 4\n'),
    ('drawn at one depth', PATH, LETGO, 'local y = b.waterY - b.depth - drop + ', 'local y = b.waterY - b.depth + 0 * drop + '),
    ('no lean drawn', PATH, LETGO, 'local here = at + side * (wander + sway + lean)', 'local here = at + side * (wander + sway)'),
    ('a spike out of the dark', PATH, LETGO, 'local deeper = 1 + drop / math.max(1, b.depth - SunkenPath.CREST)', 'local deeper = 1'),
    ("the heave's reach not widened", PATH, LETGO, 'local reach = math.max(0, 1 - near / (SunkenPath.CREST_REACH * deeper))', 'local reach = math.max(0, 1 - near / SunkenPath.CREST_REACH)'),
    ('the near turn flat', PATH, LETGO, 'return r - r * math.sin(a), r + r * math.cos(a), SunkenPath.TURN_SIDE * math.sin(a)', 'return r - r * math.sin(a), 0, SunkenPath.TURN_SIDE * math.sin(a)'),
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
