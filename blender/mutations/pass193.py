"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 193: the Needoh, met. Slow to give, slow to fill, its spring too small or too big.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CONFIG = S / "Shared/MaterialConfig.lua"
LETGO = "check_letgo.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (LETGO,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('slow to give', CONFIG, LETGO, 'chargeAfter = 0.12,', 'chargeAfter = 0.25,'),
    ('slow to fill', CONFIG, LETGO, 'chargeTime = 0.7,', 'chargeTime = 1.1,'),
    ('its spring too small', CONFIG, LETGO, 'chargeJump = 2.6,', 'chargeJump = 2.2,'),
    ('its spring too big', CONFIG, LETGO, 'chargeJump = 2.6,', 'chargeJump = 4,'),
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
