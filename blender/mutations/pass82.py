"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 82: the Sky Pools slide says where it is going. The old wait under the cloud back; when the ride goes into the
cloud and comes out never worked out, or worked out inside it; the plunge a flash; the camera waiting under the cloud
from the start; the wide shot too close, or aimed away from where they come out; the track looking only at the rider;
an eye inside the cloud (the track's, the plunge's, the one waiting under it); bursting through not hit, no puff, the
camera not turning after them; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
SKYC = S / "Client/Services/SkyPoolsClient.lua"
SKY, PARSE = "check_skypools.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SKY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the old wait under the cloud", SKYC, SKY, 'scene.cutTo("below")', 'scene.cutTo("under")'),
    ("the cloud never marked", SKYC, SKY, "\tpcall(scene.markClouds, ride :: Ride)\n", ""),
    ("coming out marked inside the cloud", SKYC, SKY, "local out = below(cloudBottom - 8, plunge)",
     "local out = below(cloudBottom + 30, plunge)"),
    ("the plunge a flash", SKYC, SKY, "local PLUNGE_HOLD = 1.1", "local PLUNGE_HOLD = 0.2"),
    ("waiting under the cloud from the start", SKYC, SKY, "local BURST_LEAD = 1.3", "local BURST_LEAD = 9"),
    ("the wide shot too close", SKYC, SKY, "local eye = mid + away * (150 - 28 * drift)",
     "local eye = mid + away * (40 - 28 * drift)"),
    ("the wide shot aimed at the pool only", SKYC, SKY, "mid:Lerp(marks.outAt, 0.38)", "mid:Lerp(marks.outAt, 0)"),
    ("the track looking only at the rider", SKYC, SKY, "CFrame.lookAt(eye, here:Lerp(far, 0.3)", "CFrame.lookAt(eye, here:Lerp(far, 0)"),
    ("the track's eye down in the cloud", SKYC, SKY, "local eye = here + out * 22 + Vector3.new(0, 10, 0) - flat * 12",
     "local eye = here + out * 22 + Vector3.new(0, 0, 0) - flat * 12"),
    ("the plunge watched from inside the cloud", SKYC, SKY, "here - flat * 14 + out * 9 + Vector3.new(0, 15, 0)",
     "here - flat * 14 + out * 9 + Vector3.new(0, 0, 0)"),
    ("the eye under the cloud inside it", SKYC, SKY, "away * 22 + Vector3.new(0, -24, 0)", "away * 22 + Vector3.new(0, -1, 0)"),
    ("bursting through not hit", SKYC, SKY, "\t\t\tCinema.impact(0.7)\n", ""),
    ("no puff coming out", SKYC, SKY, "\t\t\tscene.puff(here)\n", ""),
    ("the camera not turning after them", SKYC, SKY,
     "\t\tCinema.point(CFrame.lookAt(scene.eye :: Vector3, here + Vector3.new(0, 1, 0)), 60, true)\n",
     "\t\tCinema.point(CFrame.lookAt(scene.eye :: Vector3, marks.outAt), 60, true)\n"),
    ("a name never declared", SKYC, PARSE, "local drift = math.clamp(held / 5, 0, 1)", "local drift = math.clamp(helds / 5, 0, 1)"),
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
