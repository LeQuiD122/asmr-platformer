"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 154: bubble wrap pops. A trampoline again; four pops to a cell; no ring under a landing; the ring's
cells never coming back; a landing that pops forever; a ring going off at once.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
DEFORMS = S / "Server/Services/DeformationService.lua"
MATS = S / "Shared/MaterialConfig.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
FEEL = "check_feel.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (FEEL,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('bubble wrap a trampoline again', MATS, FEEL, '\t\tpopCount = 2,\n\t\tdecayDuration = 7,', '\t\tpopCount = 2,\n\t\tmicroBounceHeight = 4,\n\t\tdecayDuration = 7,'),
    ('four pops a cell', MATS, FEEL, '\t\tpopCount = 2,', '\t\tpopCount = 4,'),
    ('no ring under a landing', DEFORMS, FEEL, '\t\t\tringPop(platform, state, cell, player)\n', ''),
    ("the ring's cells never come back", DEFORMS, FEEL, '\t\t\t\t\t\tother.state = "decaying"\n', '\t\t\t\t\t\tother.state = "deformed"\n'),
    ('a landing that pops forever', DEFORMS, FEEL, '\t\t\t-- Spent: a landing across two cells is one landing.\n\t\t\tfall.speed = 0\n\t\t\tringPop', '\t\t\tringPop'),
    ('a ring going off at once', RENDER, FEEL, '\t\tctx.cause = "rung"\n', ''),
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
