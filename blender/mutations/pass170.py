"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 170: the levels' surfaces. A level's world dressed in everything; a world dressed that nobody builds; a
level's machinery painted; the slabs unnamed again; two makers of the slab.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
APPEAR = S / "Shared/MaterialAppearance.lua"
BOOT = S / "Server/Bootstrap.server.lua"
PBRGEN = ROOT / "blender/gen_pbr.py"
SURF = "check_surfaces.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SURF,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a level's world dressed in everything", BOOT, SURF, '\t\tpcall(MaterialAppearance.dress, child, MaterialAppearance.LEVEL_SURFACES, if worlds then worlds[child.Name] else nil)\n', '\t\tpcall(MaterialAppearance.dress, child, nil, if worlds then worlds[child.Name] else nil)\n'),
    ('a world dressed that nobody builds', BOOT, SURF, 'SkyPools = true, SunkenCity = true }', 'SkyPools = true, SunkenCity = true, SandCastle = true }'),
    ("a level's machinery painted", APPEAR, SURF, '\t[Enum.Material.Concrete] = true,\n} :: { [Enum.Material]: boolean }', '\t[Enum.Material.Concrete] = true,\n\t[Enum.Material.Metal] = true,\n} :: { [Enum.Material]: boolean }'),
    ('the slabs unnamed again', APPEAR, SURF, '[Enum.Material.Concrete] = "ConcreteMeshTile",', '[Enum.Material.Concrete] = "",'),
    ('two makers of the slab', PBRGEN, SURF, '        ("water", build_water()),\n', '        ("water", build_water()),\n        ("slab", "Slab_Color"),\n'),
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
