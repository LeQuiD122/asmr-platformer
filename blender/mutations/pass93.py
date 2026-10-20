"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 93: the shots of all four levels, played through the camera as the game has it (check_shots.py). The
letterbox bars deeper than the shots were framed for; an aim too slow to keep up; the mouth's beats crammed back into
a flash; time not stopping over it; the flume looking past the end of the tube again; the funnel's circling camera in
your face, or its lens narrowed; the plunge a flash; the dive's water shot from too high; the camera under the water above it; the chamber's walk rushed; a shot changed in the client and not restated in shots_*.py; a name never
declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CINEMA = S / "Client/Services/Cinema.lua"
HC = S / "Client/Services/FloodedHallsClient.lua"
SHORE = S / "Client/Services/CityShoreClient.lua"
SKY = S / "Client/Services/SkyPoolsClient.lua"
SUNK = S / "Client/Services/SunkenCityClient.lua"
HALLS, SHOTS, PARSE = "check_halls.py", "check_shots.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HALLS, SHOTS, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the bars twice as deep', CINEMA, SHOTS, 'local BARS = 0.11', 'local BARS = 0.3'),
    ('a lazy aim', CINEMA, SHOTS, 'local AIM_RATE = 7', 'local AIM_RATE = 1'),
    ("the mouth's beats crammed", HC, SHOTS, '\tface = 1.8,', '\tface = 0.95,'),
    ('time not stopping over it', HC, HALLS, 'local HANG = 2', 'local HANG = 6'),
    ('the flume looking past the tube', HC, SHOTS, 'local ahead = pathAt(path, math.min(HELIX - 0.005, f + 0.04))', 'local ahead = pathAt(path, math.min(1, f + 0.04))'),
    ('the circling camera in your face', SUNK, SHOTS, 'CIRCLE = { out = 15, up = 8, turn = 0.45 }', 'CIRCLE = { out = 2, up = 1, turn = 0.45 }'),
    ("the funnel's lens narrowed", SUNK, SHOTS, '\tFOV = 62,', '\tFOV = 14,'),
    ('the plunge a flash', SKY, SHOTS, 'local PLUNGE_HOLD = 1.1 --', 'local PLUNGE_HOLD = 0.3 --'),
    ('the water shot from too high', SHORE, SHOTS, 'local WATER_SHOT = 120', 'local WATER_SHOT = 420'),
    ('the camera over the surface', SHORE, SHOTS, 'eye = Vector3.new(eye.X, math.min(eye.Y, current.water - 1.5), eye.Z)', 'eye = Vector3.new(eye.X, eye.Y, eye.Z)'),
    ("the chamber's walk rushed", HC, SHOTS, '\twalk = 14,\n', '\twalk = 9.8,\n'),
    ('a shot changed, not restated', SKY, SHOTS, 'landing + away * 32 + Vector3.new(0, 4, 0)', 'landing + away * 26 + Vector3.new(0, 4, 0)'),
    ('a name never declared', SUNK, PARSE, 'local eye = Vector3.new(spec.vortex.X - 10, spec.bottomY + 0.5, spec.vortex.Z)', 'local eye = Vector3.new(specs.vortex.X - 10, spec.bottomY + 0.5, spec.vortex.Z)'),
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
