"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 180: under the sea is a fall. The catch too deep, the shelters or the swim not spared, the rider caught, the plane never asking.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
CITY = S / "Server/Services/SunkenCityService.lua"
LETGO = "check_letgo.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (LETGO,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('caught too deep', CITY, LETGO, 'local catch = 4', 'local catch = 40'),
    ('caught in the aquarium', CITY, LETGO, '\tfor _, box in ipairs(watch.shelters) do\n\t\tif box.Parent then', '\tfor _, box in ipairs({}) do\n\t\tif box.Parent then'),
    ('caught in its doorway', CITY, LETGO, 'local margin = 8', 'local margin = 0'),
    ('caught swimming', CITY, LETGO, 'for _, fill in ipairs(swimWater.fills) do', 'for _, fill in ipairs({}) do'),
    ('the rider caught', CITY, LETGO, 'player:GetAttribute("InLevel") ~= "sunkenCity" or riding[player] or arrivedAt[player]', 'player:GetAttribute("InLevel") ~= "sunkenCity"'),
    ('never told the sea', CITY, LETGO, 'swimWater.watch = { shelters = shelters, water = waterLevel }', 'swimWater.watch = nil'),
    ('the plane never asking', BOOT, LETGO, 'or (SunkenCityService ~= nil and SunkenCityService.underSea ~= nil and SunkenCityService.underSea(player))', 'or false'),
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
