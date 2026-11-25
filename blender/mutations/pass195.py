"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 195: still, nothing drawn. The strands swayed standing still, moved their whole way at any pace, the try-on held
still, the full sway only past a sprint, a teleport counted as running, a jump up counted as travel, the sway slow to
follow you.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
COSMETIC = S / "Client/Services/CosmeticsClient.lua"
LETGO = "check_letgo.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (LETGO,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('swaying standing still', COSMETIC, LETGO, 'local sway = if trying then 1 else math.clamp((w.pace - STRANDS.still) / (STRANDS.moving - STRANDS.still), 0, 1)', 'local sway = 1'),
    ('the whole way at any pace', COSMETIC, LETGO, 'local centre = s.at:Lerp(strandPlace(s, now), sway)', 'local centre = strandPlace(s, now)'),
    ('the try-on held still', COSMETIC, LETGO, 'local trying = root:FindFirstChild("ShopPreviewTrailTop") ~= nil', 'local trying = false'),
    ('full sway past a sprint', COSMETIC, LETGO, 'local STRANDS = { still = 1, moving = 8,', 'local STRANDS = { still = 1, moving = 40,'),
    ('a teleport as running', COSMETIC, LETGO, 'if pace > STRANDS.jump then 0 else math.min(pace, STRANDS.moving)', 'if false then 0 else math.min(pace, STRANDS.moving)'),
    ('a jump up as travel', COSMETIC, LETGO, 'Vector3.new(root.Position.X - lastAt.X, 0, root.Position.Z - lastAt.Z).Magnitude / dt', '(root.Position - lastAt).Magnitude / dt'),
    ('slow to follow you', COSMETIC, LETGO, 'ease = 6, jump = 60 }', 'ease = 0.5, jump = 60 }'),
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
