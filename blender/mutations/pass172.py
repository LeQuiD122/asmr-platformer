"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 172: he comes nearer. Never stood ahead; ahead on one level only; his face; no screen told he is ahead; facing
away; never gone; gone at any distance, or too far off to be seen; popped, not faded; told late and never gone.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
STORYC = S / "Client/Services/StoryClient.lua"
STORYSV = S / "Server/Services/StoryService.lua"
STORY = "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('never stood ahead', STORYSV, STORY, '\t\t\t\tpcall(watcherAhead, folder, cap, chunks[index - 1])\n', ''),
    ('ahead on one level only', STORYSV, STORY, '\t\tfor _, fraction in ipairs(WATCHER_AT) do', '\t\tif level.backdrop == "floodedHalls" then end\n\t\tfor _, fraction in ipairs(WATCHER_AT) do'),
    ('his face', STORYSV, STORY, 'Color3.fromRGB(30, 32, 36) }, true, 240)', 'Color3.fromRGB(30, 32, 36) }, false, 240)'),
    ('no screen told he is ahead', STORYSV, STORY, 'npc.model:SetAttribute("Ahead", true)', 'npc.model:SetAttribute("Near", true)'),
    ('facing away', STORYSV, STORY, 'CFrame.lookAt(spot.Position, Vector3.new(behind.X, spot.Position.Y, behind.Z))', 'CFrame.lookAt(spot.Position, spot.Position + (spot.Position - behind) * Vector3.new(1, 0, 1))'),
    ('never gone', STORYC, STORY, '\t\t\taheadGone(model)\n', ''),
    ('gone at any distance', STORYC, STORY, 'or (root.Position - his.Position).Magnitude > AHEAD.near then', 'or false then'),
    ('gone too far off to be seen', STORYC, STORY, 'local AHEAD = { near = 34, fade = 0.7 }', 'local AHEAD = { near = 300, fade = 0.7 }'),
    ('popped, not faded', STORYC, STORY, 'item.LocalTransparencyModifier = math.max(item.LocalTransparencyModifier, k)', 'item.LocalTransparencyModifier = 1'),
    ('told late and never gone', STORYC, STORY, 'waiting = model:GetAttributeChangedSignal("Ahead"):Connect(function()', 'waiting = model:GetAttributeChangedSignal("Near"):Connect(function()'),
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
