"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 174: what the drowned city and the hotel roof are built of. The city plain plastic again; the houses not
rendered; the church in brick; a car given a building's stone; the roofs in what no surface dresses; the terraces
plastic again; one deck left plastic; the coping cast; the tower plastic.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
SKYS = S / "Server/Services/SkyPoolsService.lua"
SUNKS = S / "Server/Services/SunkenCityService.lua"
SURF = "check_surfaces.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SURF,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the city plain plastic again', SUNKS, SURF, '\t\t\tmaterial or BUILT_OF[name] or Enum.Material.SmoothPlastic, false)', '\t\t\tmaterial or Enum.Material.SmoothPlastic, false)'),
    ('the houses not rendered', SUNKS, SURF, 'House = Enum.Material.Plaster, Chimney', 'House = Enum.Material.SmoothPlastic, Chimney'),
    ('the church in brick', SUNKS, SURF, 'Nave = Enum.Material.Rock, Buttress', 'Nave = Enum.Material.Brick, Buttress'),
    ("a car given a building's stone", SUNKS, SURF, 'Sandbag = Enum.Material.Fabric,', 'Sandbag = Enum.Material.Fabric, CarBody = Enum.Material.Concrete,'),
    ('the roofs in what no surface dresses', SUNKS, SURF, 'Roof = Enum.Material.Slate, FlatRoof', 'Roof = Enum.Material.Granite, FlatRoof'),
    ('the terraces plastic again', SKYS, SURF, 'local PAVING = Enum.Material.Slate', 'local PAVING = Enum.Material.SmoothPlastic'),
    ('one deck left plastic', SKYS, SURF, 'frame * CFrame.new((ax + bx) / 2, -DECK_THICK / 2, (az + bz) / 2), DECK, PAVING, true)', 'frame * CFrame.new((ax + bx) / 2, -DECK_THICK / 2, (az + bz) / 2), DECK, Enum.Material.SmoothPlastic, true)'),
    ('the coping cast', SKYS, SURF, 'frame * CFrame.new(edge[1], 0.1, edge[2]), COPING,\n\t\t\tMARBLE, true)', 'frame * CFrame.new(edge[1], 0.1, edge[2]), COPING,\n\t\t\tCAST, true)'),
    ('the tower plastic', SKYS, SURF, 'column(parent, "Tower", TOWER_D, centre, seaY, topY - 8, STONE, CAST, true)', 'column(parent, "Tower", TOWER_D, centre, seaY, topY - 8, STONE, Enum.Material.SmoothPlastic, true)'),
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
