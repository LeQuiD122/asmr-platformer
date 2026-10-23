"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 133, from your test: his catch, followable. Over in a flash; taken away before the black; never side on;
never saying what you see; slabs again; his head through the face; his face not whole; the server not waiting.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
ROOMS = S / "Server/Services/BackRoomsService.lua"
STORYC = S / "Client/Services/StoryClient.lua"
ROOMSCHECK, STORY = "check_backrooms.py", "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (ROOMSCHECK, STORY):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('over in a flash', STORYC, STORY, 'local CAUGHT = { loom = 0.35, face = 1.9, black = 3.5 }', 'local CAUGHT = { loom = 0.35, face = 1.15, black = 2.15 }'),
    ('taken away before the black', ROOMS, STORY, 'task.delay(4.5, function()', 'task.delay(3, function()'),
    ('never side on', STORYC, STORY, 'local from = mid + across * (8 - 1.5 * k) - toward * 1 + Vector3.new(0, 1.8, 0)', 'local from = me + across * (4.4 - 0.7 * k) - toward * 1.4 + Vector3.new(0, 0.3, 0)'),
    ('never saying what you see', STORYC, STORY, 'Cinema.think(character, "What IS that?!", 1.2)', 'local _ = character'),
    ('slabs again', STORYC, STORY, 'round.MeshType = Enum.MeshType.Sphere', 'round.MeshType = Enum.MeshType.Brick'),
    ('his head through the face', STORYC, STORY, '\t\t\t\t\t\titem.LocalTransparencyModifier = 1\n', '\t\t\t\t\t\titem.LocalTransparencyModifier = 0\n'),
    ('his face not whole', STORYC, ROOMSCHECK, 'eye = CFrame.lookAt(his - toward * 5.6 + across * 1.7 + Vector3.new(0, 0.5, 0), his)', 'eye = CFrame.lookAt(his - toward * 1.6 + across * 0.7 + Vector3.new(0, 0.5, 0), his)'),
    ('the server not waiting', BOOT, STORY, 'task.wait(3.9)', 'task.wait(2.4)'),
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
