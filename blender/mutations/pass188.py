"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 188: the garden. The well in the house, a rose on Mrs Dunn, a tree past the fence, never dressed, roses solid, a rose on the path.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HILL = S / "Server/Services/HillHouseService.lua"
MADE = "check_made.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (MADE,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the well in the house', HILL, MADE, '{ "Hill_Well", -24, -18, 7, 0.4 },', '{ "Hill_Well", -2, 10, 7, 0.4 },'),
    ('a rose on Mrs Dunn', HILL, MADE, '{ "Hill_Roses", -6.5, -39, 2.8, 0.5 },', '{ "Hill_Roses", 4.8, -37.5, 2.8, 0.5 },'),
    ('a tree past the fence', HILL, MADE, 'local GARDEN_TREES = { { 28, 18 }, { -12, 30 }, { 28, -24 } }', 'local GARDEN_TREES = { { 28, 18 }, { -12, 30 }, { 40, -24 } }'),
    ('never dressed', HILL, MADE, 'bench(garden, top + across * 22 - inward * 4, out)\n\tdressGarden(garden, top, inward, across)', 'bench(garden, top + across * 22 - inward * 4, out)'),
    ('roses solid', HILL, MADE, 'local GARDEN_SOLID = { Hill_Well = true, Hill_Beehive = true }', 'local GARDEN_SOLID = { Hill_Well = true, Hill_Beehive = true, Hill_Roses = true }'),
    ('a rose on the path', HILL, MADE, '{ "Hill_Roses", -7, 1.6, 3, 0 },', '{ "Hill_Roses", -1, -10, 3, 0 },'),
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
