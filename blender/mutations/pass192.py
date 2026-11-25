"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 192: not one surface on everything. A pool of one, numbered by nothing, a building patchwork, the numbering drawing.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
APPEAR = S / "Shared/MaterialAppearance.lua"
CITY = S / "Server/Services/SunkenCityService.lua"
MADE = "check_made.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (MADE,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a pool of one', APPEAR, MADE, '[Enum.Material.Concrete] = { "CityStone", "HarrowCast", "CityAshlar" },', '[Enum.Material.Concrete] = "CityStone",'),
    ("Harrow Bay's out of the pool", APPEAR, MADE, '[Enum.Material.Plaster] = { "HarrowRender", "CityWash" },\n\t},\n\tHillHouse', '[Enum.Material.Plaster] = { "CityWash", "CityRender" },\n\t},\n\tHillHouse'),
    ('numbered by nothing', APPEAR, MADE, 'local index = if typeof(look) == "number" then look else', 'local index = if false then look else'),
    ('a building patchwork', CITY, MADE, 'made:SetAttribute("Look", look)', 'made:SetAttribute("Seen", look)'),
    ('the numbering drawing', CITY, MADE, 'parent:SetAttribute("Look", (parent:GetAttribute("Look") or 0) + 1)', 'parent:SetAttribute("Look", rng:NextInteger(1, 9))'),
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
