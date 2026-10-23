"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 132, from your test: the mouth longer and harder, its throat with drama. No creak; no crunches, or the last in
the dark; the throat too short; the slam a tap; its walls still; nothing rushing past; the picture still; no panic; its red
left on; the flume's end not hit.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HC = S / "Client/Services/FloodedHallsClient.lua"
HS = S / "Server/Services/FloodedHallsService.lua"
HALLS, STORY = "check_halls.py", "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HALLS, STORY):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('no creak', HC, STORY, 'local CREAK = 0.9', 'local CREAK = 0.3'),
    ('no crunches', HC, STORY, 'for index, at in ipairs(CRUNCHES) do', 'for index, at in ipairs({}) do'),
    ('the last crunch in the dark', HC, STORY, 'local CRUNCHES = { 0.45, 0.9 }', 'local CRUNCHES = { 0.45, 1.3 }'),
    ('the throat too short', HS, STORY, '\tMAW = 13.5,', '\tMAW = 9.5,'),
    ('the slam a tap', HC, HALLS, '\t\t\tCinema.impact(2)\n\t\t\tCinema.shake(3.8)\n', '\t\t\tCinema.impact(0.5)\n\t\t\tCinema.shake(3.8)\n'),
    ('its walls still', HC, STORY, 'wall.part.CFrame = wall.rest - wall.out * squeeze', 'wall.part.CFrame = wall.rest'),
    ('nothing rushing past', HC, STORY, 'wet.Name = "Wet"', 'wet.Name = "Drips"'),
    ('the picture still in its throat', HC, STORY, 'Cinema.waver(0.9)', 'Cinema.waver(0.2)'),
    ('no panic', HC, STORY, '"Let me OUT!"', '"Hmm."'),
    ('its red left on', HC, STORY, 'local function dropThroat(current: Scene)', 'local function dropThroatLater(current: Scene)'),
    ("the flume's end not hit", HC, STORY, 'Cinema.impact(1)\n\t\tCinema.shake(1.2)', 'Cinema.impact(0)\n\t\tCinema.shake(1.2)'),
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
