"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 179: he is not there. The Watcher left in the group that meets everything, the group meeting the rest, solid in what he is dressed in after, or on your screen once faded.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
STORY = S / "Server/Services/StoryService.lua"
STORYC = S / "Client/Services/StoryClient.lua"
LETGO = "check_letgo.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (LETGO,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the Watcher left in Default', STORY, LETGO, '\t\t\t\tif group then\n\t\t\t\t\titem.CollisionGroup = group', '\t\t\t\tif false then\n\t\t\t\t\titem.CollisionGroup = group'),
    ('his group meeting everything', STORY, LETGO, 'physics:CollisionGroupSetCollidable(name, "Default", false)', 'physics:CollisionGroupSetCollidable(name, "Default", true)'),
    ('his coat solid', STORY, LETGO, 'npc.model.DescendantAdded:Connect(nothing)', '-- (what he is dressed in after: as made)'),
    ('faded and still solid on your screen', STORYC, LETGO, 'item.CollisionGroup = "Apparitions"', 'item.CollisionGroup = "Default"'),
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
