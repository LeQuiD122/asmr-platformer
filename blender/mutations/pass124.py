"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 124, from your test: one locker of a row, the coat whole, the mouth understood. A locker's prompt not saying
where it stands shut, every prompt in a row on, or nothing picking; the close look inside the coat; a blank coat; the
mouth not seen to be one, the throat never gone down or blacked out; a throat shot changed and not restated.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HC = S / "Client/Services/FloodedHallsClient.lua"
INTERACT = S / "Server/Services/Interactables.lua"
STORYC = S / "Client/Services/StoryClient.lua"
SHOTS, STORY = "check_shots.py", "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOTS, STORY):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a locker's prompt not saying where it stands", INTERACT, STORY, 'p:SetAttribute("RowAt", door.Position)', 'p:SetAttribute("Row", door.Position)'),
    ('every prompt in a row on', STORYC, STORY, 'item.Enabled = item == best', 'item.Enabled = true'),
    ('nothing picking one', STORYC, STORY, '\toneOfARow()\n', '\tlocal _ = oneOfARow\n'),
    ('the close look inside the coat', STORYC, STORY, 'local back = if span then span + 1.4 - 1.2 * u else reach - 0.7 * u', 'local back = reach - 0.7 * u'),
    ('a blank coat', INTERACT, STORY, 'bit("CoatButton"', 'bit("CoatStud"'),
    ('not a mouth', HC, STORY, '"Is that... a MOUTH?!"', '"What is that?"'),
    ('coming up not knowing', HC, STORY, '"It... spat me out?"', '"Where am I?"'),
    ('never down its throat', HC, STORY, 'local function buildThroat(at: Vector3): Throat', 'local function buildGullet(at: Vector3): Throat'),
    ('the throat blacked out', HC, STORY, 'current.swallowed = true', 'current.swallowed = false'),
    ('a throat shot changed, not restated', HC, SHOTS, 'Cinema.point(CFrame.lookAt(held + Vector3.new(0, 9, 0) + side * 2.5, held - Vector3.new(0, 6, 0), side), 72)', 'Cinema.point(CFrame.lookAt(held + Vector3.new(0, 9, 0) + side * 2.5, held - Vector3.new(0, 6, 0), side), 60)'),
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
