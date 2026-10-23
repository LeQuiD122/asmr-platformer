"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 125, from your test: his catch in the back rooms. Caught and nobody told; him walking on with you; never
taking hold, or his arms hanging; the face two slabs again; his face a flash; the lobby before the black.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
ROOMS = S / "Server/Services/BackRoomsService.lua"
STALK = S / "Client/Services/StalkerClient.lua"
STORYC = S / "Client/Services/StoryClient.lua"
STORY = "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('caught and nobody told', ROOMS, STORY, 'model:SetAttribute("Caught", true)', 'model:SetAttribute("Hunting", true)'),
    ('walking on with you', ROOMS, STORY, 'model:SetAttribute("Paused", true)', 'model:SetAttribute("Paused", false)'),
    ('never taking hold', STALK, STORY, 'if real:GetAttribute("Caught") == true then', 'if real:GetAttribute("Caught") == "yes" then'),
    ('his arms hanging', STALK, STORY, 'drive(one, "Shoulder" .. side, CFrame.Angles(1.65 * g, 0, -0.32 * sign * g))', 'drive(one, "Shoulder" .. side, CFrame.Angles(0, 0, 0))'),
    ('the face two slabs again', STORYC, STORY, 'local SCREAM = 1.6', 'local SCREAM = 1'),
    ('his face a flash', STORYC, STORY, 'local CAUGHT = { loom = 0.35, face = 1.9, black = 3.5 }', 'local CAUGHT = { loom = 0.35, face = 0.6, black = 3.5 }'),
    ('the lobby before the black', BOOT, STORY, 'task.wait(3.9)', 'task.wait(1.5)'),
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
