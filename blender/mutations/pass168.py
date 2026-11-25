"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 168: the halls lit as their own. The level's light never applied; no palette for the halls; the halls too
bright again; the haze a second ambient; the walls blooming; the sky's fill in every bay; the halls setting the light
themselves; the far blur unnamed.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
HS = S / "Server/Services/FloodedHallsService.lua"
LIGHTS = S / "Server/Services/LightingService.lua"
HALLS = "check_halls.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HALLS,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the level's light never applied", BOOT, HALLS, 'local levelLightOk, levelLightErr = pcall(LightingService.apply, level.backdrop)', 'local levelLightOk, levelLightErr = pcall(function() end)'),
    ('no palette for the halls', LIGHTS, HALLS, '\tfloodedHalls = {', '\tfloodedHallsOld = {'),
    ('the halls too bright again', LIGHTS, HALLS, '\t\tbrightness = 0.8,', '\t\tbrightness = 1.9,'),
    ('the haze a second ambient', LIGHTS, HALLS, '\t\tdensity = 0.28,\n\t\thaze = 0.45,', '\t\tdensity = 0.28,\n\t\thaze = 1.05,'),
    ('the walls blooming', LIGHTS, HALLS, '\t\tbloomThreshold = 2.2,', '\t\tbloomThreshold = 1.05,'),
    ("the sky's fill in every bay", LIGHTS, HALLS, 'outdoor = Color3.fromRGB(58, 62, 58),', 'outdoor = Color3.fromRGB(122, 120, 134),'),
    ('the halls setting the light themselves', HS, HALLS, '\tblur.Parent = game:GetService("Lighting")\n', '\tlocal lighting = game:GetService("Lighting")\n\tlighting.Brightness = 0.55\n\tblur.Parent = lighting\n'),
    ('the far blur unnamed', HS, HALLS, 'blur.Name = "HallsBlur"', 'blur.Name = "Blur"'),
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
