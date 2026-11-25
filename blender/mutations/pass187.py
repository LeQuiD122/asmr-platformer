"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 187: what floats. Not the baths' things, not at the halls' scale, the draws moved.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HALLS = S / "Server/Services/FloodedHallsService.lua"
MADE = "check_made.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (MADE,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('not theirs', HALLS, MADE, '{ "Halls_Lifebuoy", "Halls_Lounger", "Halls_Lifebuoy", "Halls_Duckboard" }', '{ "Debris" }'),
    ("not at the halls' scale", HALLS, MADE, 'junk.Size = template.Size * SCALE', 'junk.Size = template.Size'),
    ('the draws moved', HALLS, MADE, '\t\tlocal size = Vector3.new(rng:NextNumber(1.2, 3.2), rng:NextNumber(0.4, 1.0), rng:NextNumber(1.2, 3.2)) * SCALE\n\t\tlocal template = if #floaters > 0 then floaters[(index - 1) % #floaters + 1] else nil\n\t\tlocal junk: BasePart\n\t\tif template then\n\t\t\tjunk = template:Clone()\n\t\t\tjunk.Size = template.Size * SCALE\n\t\telse\n\t\t\tlocal board = Instance.new("Part")\n\t\t\tboard.Size = size', '\t\tlocal template = if #floaters > 0 then floaters[(index - 1) % #floaters + 1] else nil\n\t\tlocal junk: BasePart\n\t\tif template then\n\t\t\tjunk = template:Clone()\n\t\t\tjunk.Size = template.Size * SCALE\n\t\telse\n\t\t\tlocal board = Instance.new("Part")\n\t\t\tboard.Size = Vector3.new(rng:NextNumber(1.2, 3.2), rng:NextNumber(0.4, 1.0), rng:NextNumber(1.2, 3.2)) * SCALE'),
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
