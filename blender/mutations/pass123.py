"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 123, from your test of 2026-10-22. The honey prints laid backwards; the fountain's bubbles Glass again, solid,
without their glint, or rising to the canopy; what you said kept from one run to the next, a person never forgetting, or
nothing marked new; the bubbles not written out, without the speaker's name, all at once, or too slowly to read; no arrow
on the choice you are on; the shop's arrow keys gone or the left one going right; a tile's icon held by its top, or
swelling over its name.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CONV = S / "Shared/Conversations.lua"
LIFE = S / "Client/Services/LobbyLife.lua"
SHOPC = S / "Client/Services/ShopService.lua"
STEPS = S / "Client/Services/StepService.lua"
TALK = S / "Client/Services/TalkClient.lua"
TOWNS = S / "Server/Services/Townsfolk.lua"
HUB, SHOP, STORY = "check_hub.py", "check_shop.py", "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUB, SHOP, STORY):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the prints laid backwards', STEPS, SHOP, 'local MESH_TURN = CFrame.Angles(0, math.pi, 0)', 'local MESH_TURN = CFrame.Angles(0, 0, 0)'),
    ('the arrow keys doing nothing', SHOPC, SHOP, 'Enum.KeyCode.ButtonR1, Enum.KeyCode.Left,', 'Enum.KeyCode.ButtonR1,'),
    ('the left arrow going right', SHOPC, SHOP, 'local back = input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.Left', 'local back = input.KeyCode == Enum.KeyCode.ButtonL1 or input.KeyCode == Enum.KeyCode.Right'),
    ('the icon swelling over its name', SHOPC, SHOP, 'TweenService:Create(swell, spring, { Scale = 1.08 }):Play()', 'TweenService:Create(swell, spring, { Scale = 1.2 }):Play()'),
    ('the icon held by its top', SHOPC, SHOP, 'icon.AnchorPoint = Vector2.new(0.5, 0.5)', 'icon.AnchorPoint = Vector2.new(0.5, 0)'),
    ('the bubbles Glass', LIFE, HUB, 'Color3.fromHSV(rng:NextNumber(0, 1), 0.22, 1),\n\t\tEnum.Material.SmoothPlastic)', 'Color3.fromHSV(rng:NextNumber(0, 1), 0.22, 1),\n\t\tEnum.Material.Glass)'),
    ('a bubble a solid ball', LIFE, HUB, 'ball.Transparency = 0.78', 'ball.Transparency = 0.3'),
    ('no glint', LIFE, HUB, 'b.glint.Position = at + Vector3.new(-0.2, 0.28, -0.16) * size', 'local _ = at'),
    ('bubbles up to the canopy', LIFE, HUB, 'rise = rng:NextNumber(0.45, 0.9)', 'rise = rng:NextNumber(0.45, 2.4)'),
    ('what was said kept from run to run', CONV, STORY, 'local said = saidNow or known', 'local said = known'),
    ('a person never forgetting', TOWNS, STORY, 'talking = 0, said = {} }', 'talking = 0 }'),
    ('nothing marked new', TOWNS, STORY, 'fresh = not known[topic.id]', 'fresh = false'),
    ('the bubbles never written out', TOWNS, STORY, 'CollectionService:AddTag(gui, "SpeechBubble")', 'local _ = gui'),
    ('no name on a bubble', TOWNS, STORY, 'tag.Name = "Speaker"', 'tag.Name = "Tag"'),
    ('a bubble all at once', TALK, STORY, 'words.MaxVisibleGraphemes = shown', 'words.MaxVisibleGraphemes = -1'),
    ('written out too slowly to read', TALK, STORY, 'local WRITE_RATE = 48', 'local WRITE_RATE = 12'),
    ('no arrow on your choice', TALK, STORY, 'arrow.Name = "Arrow"', 'arrow.Name = "Pointer"'),
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
