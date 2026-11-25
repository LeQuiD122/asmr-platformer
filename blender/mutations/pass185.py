"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 185: each level its own surfaces. The red iron asked for, a surface used unmade, Harrow Bay's left out of the halls' metal, the levels never handed theirs.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
APPEAR = S / "Shared/MaterialAppearance.lua"
BOOT = S / "Server/Bootstrap.server.lua"
MADE = "check_made.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (MADE,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the red iron', APPEAR, MADE, '[Enum.Material.Metal] = "HallsPaint",', '[Enum.Material.Metal] = "HallsIron",'),
    ('used unmade', APPEAR, MADE, 'local useOwn = ownName ~= nil and have[ownName] == true', 'local useOwn = ownName ~= nil'),
    ("never past Harrow Bay's", APPEAR, MADE, 'if only and not only[item.Material] and not useOwn then', 'if only and not only[item.Material] then'),
    ('never handed over', BOOT, MADE, 'if worlds then worlds[child.Name] else nil)', 'nil)'),
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
