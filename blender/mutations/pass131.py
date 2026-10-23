"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 131, from your test: the Sunken City's fall hit like the dive. Taken without a jolt; going under not hit; no
speed down the shaft; the bottom not hit; no wake; set down dry; the station's camera through a pillar; turned into the
culvert's wall; the alongside shot moved without the check.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
SUNK = S / "Client/Services/SunkenCityClient.lua"
SUNKPATH = S / "Shared/SunkenPath.lua"
SHOTS, STORY = "check_shots.py", "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOTS, STORY):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('taken without a jolt', SUNK, STORY, 'current.grabbed = true\n\t\t\t\tCinema.impact(1)', 'current.grabbed = true\n\t\t\t\tCinema.impact(0)'),
    ('going under not hit', SUNK, STORY, 'current.wentUnder = true\n\t\t\t\tCinema.impact(1.2)', 'current.wentUnder = true\n\t\t\t\tCinema.impact(0)'),
    ('no speed down the shaft', SUNK, STORY, 'Cinema.speedLines(if below then 0.85 else 0.25 + 0.45 * math.clamp(u / 0.45, 0, 1))', 'Cinema.speedLines(0)'),
    ('the bottom not hit', SUNK, STORY, 'current.hitBottom = true\n\t\tCinema.impact(1.5)', 'current.hitBottom = true\n\t\tCinema.impact(0)'),
    ('no wake', SUNK, STORY, 'current.wake = makeWake()', 'current.wake = nil'),
    ('set down dry', SUNK, STORY, 'impactWater(frame.Position, 0.8, o.waterY)', 'local _ = o'),
    ('through a pillar', SUNK, STORY, 'local eye = clearOf(reveal.eye:Lerp(reveal.cardEye, e), look:Lerp(reveal.card, e))', 'local eye = reveal.eye:Lerp(reveal.cardEye, e)'),
    ("into the culvert's wall", SUNKPATH, STORY, 'math.sin(t * 0.7) * 0.22 * lift', 'math.sin(t * 0.7) * 0.5 * lift'),
    ('the alongside shot moved without the check', SUNK, SHOTS, 'head + side * 2.4 - run * 1.5 + Vector3.new(0, 2.6, 0)', 'head + side * 3.6 - run * 1.5 + Vector3.new(0, 2.6, 0)'),
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
