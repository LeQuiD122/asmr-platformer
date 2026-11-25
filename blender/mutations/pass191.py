"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 191: the chocolate and the keys over lava. The warm bar slow to break or melt, the tempered one slow, the keys still on the lava, slow to come back.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CONFIG = S / "Shared/MaterialConfig.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
LETGO = "check_letgo.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (LETGO,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the warm bar slow', CONFIG, LETGO, 'crumbleAfter = 1.0,\n\t\tregrowAfter = 6,\n\t\tdissolveTime = 1.0,', 'crumbleAfter = 1.8,\n\t\tregrowAfter = 6,\n\t\tdissolveTime = 1.0,'),
    ('its melt slow', CONFIG, LETGO, 'crumbleAfter = 1.0,\n\t\tregrowAfter = 6,\n\t\tdissolveTime = 1.0,', 'crumbleAfter = 1.0,\n\t\tregrowAfter = 6,\n\t\tdissolveTime = 1.8,'),
    ('the tempered bar slow', CONFIG, LETGO, 'a broken bar.\n\t\tcrumbleAfter = 0.8,', 'a broken bar.\n\t\tcrumbleAfter = 1.2,'),
    ('the keys still', RENDER, LETGO, 'local t = now * 2.6 + key.phase', 'local t = now * 1.3 + key.phase'),
    ('the keys hardly riding', RENDER, LETGO, 'CFrame.new(0, 0.2 * math.sin(t), 0)', 'CFrame.new(0, 0.06 * math.sin(t), 0)'),
    ('slow to come back', RENDER, LETGO, 'RISE = TweenInfo.new(0.38,', 'RISE = TweenInfo.new(0.7,'),
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
