"""Each mutation must make its checker fail. Files are restored byte for byte whatever happens."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
CLIENT = ROOT / "src/Client/Services/SunkenCityClient.lua"
PATH = ROOT / "src/Shared/SunkenPath.lua"
SERPENT = ROOT / "blender/gen_serpent.py"
EXTENTS = ROOT / "blender/sealife_extents.json"
CITY = "check_sunkencity.py"

MUTATIONS = [
    ("the serpent a different length from the path", SERPENT, CITY, "SEGMENTS = 18        #", "SEGMENTS = 16        #"),
    ("the serpent fatter than the service's girth", SERPENT, CITY, "GIRTH = 8.0          #", "GIRTH = 9.0          #"),
    ("the serpent's fluke measured at too small a turn", SERPENT, CITY, "SWAY_TURN = 0.42     #", "SWAY_TURN = 0.3      #"),
    ("the serpent rolling over where it turns back", CLIENT, CITY,
     "SeaRig.follow(mesh.chain, mesh.rig.rest, joints, true, mesh.posed)",
     "SeaRig.follow(mesh.chain, mesh.rig.rest, joints, false, mesh.posed)"),
    ("the serpent never moved", CLIENT, CITY, "if b and (#segments > 0 or thingMesh) then", "if b and #segments > 0 then"),
    ("the serpent's fluke into the dry flat", EXTENTS, CITY, '"side_reach": 7.669', '"side_reach": 12.0'),
    ("the mood written every frame", CLIENT, CITY, "if key == moodWritten and shade then", "if false then"),
    ("a frame searching the game", CLIENT, CITY, "local function moveFerris()\n\tlocal now = workspace:GetServerTimeNow()",
     "local function moveFerris()\n\tlocal now = workspace:GetServerTimeNow() + #CollectionService:GetTagged(\"SunkenFerris\") * 0"),
    ("the body worked out a point at a time again", PATH, CITY, "function SunkenPath.body(", "function SunkenPath.wholeBody("),
]

paths = {m[1] for m in MUTATIONS}
originals = {path: path.read_bytes() for path in paths}
missed = []
try:
    for label, path, checker, old, new in MUTATIONS:
        text = originals[path].decode("utf-8").replace("\r\n", "\n")
        assert text.count(old) == 1, "%s: anchor found %d times" % (label, text.count(old))
        path.write_bytes(text.replace(old, new).encode("utf-8"))
        run = subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                             cwd=str(ROOT / "blender"))
        path.write_bytes(originals[path])
        caught = run.returncode != 0
        why = [line.strip() for line in (run.stdout + run.stderr).splitlines() if line.startswith("  ")][:2]
        print("%-8s %s  %s" % ("caught" if caught else "MISSED", label, "; ".join(why)[:170]))
        if not caught:
            missed.append(label)
finally:
    for path, data in originals.items():
        path.write_bytes(data)
print("\n%d of %d caught" % (len(MUTATIONS) - len(missed), len(MUTATIONS)))
