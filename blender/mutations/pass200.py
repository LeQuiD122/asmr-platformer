"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 200: the talk under you, their face, wide bubbles and a thought. The choices back up the screen, built across you,
no room for thumbs; no face, a likeness keeping its scripts, a likeness from behind; no dots; a narrow column again,
wrapping at everything, your own bubble narrow, letters on the rim; an answer without thinking, a longer wait, the dots
gone at once, the dots never brought up, the dots forever.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
TALK = S / "Client/Services/TalkClient.lua"
TOWNS = S / "Server/Services/Townsfolk.lua"
STORY = "check_story.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the choices back up the screen', TALK, STORY, 'local DOCK = { low = 26, touch = 104, away = 20 }', 'local DOCK = { low = 150, touch = 104, away = 20 }'),
    ('built across you', TALK, STORY, 'holder.Position = UDim2.new(0.5, 0, 1, -DOCK.low)', 'holder.Position = UDim2.new(0.5, 0, 1, -150)'),
    ('no room for thumbs', TALK, STORY, 'then DOCK.touch else DOCK.low', 'then DOCK.low else DOCK.low'),
    ('no face', TALK, STORY, 'local drawn, seen = pcall(likeness, ui.portrait, offer.head)\n\t\tui.initial.Visible = not (drawn and seen)',
     'local drawn, seen = false, false\n\t\tui.initial.Visible = true'),
    ('a likeness keeping its scripts', TALK, STORY,
     'if item:IsA("LuaSourceContainer") or item:IsA("Sound") or item:IsA("ProximityPrompt") or item:IsA("LayerCollector")',
     'if item:IsA("Sound") or item:IsA("ProximityPrompt") or item:IsA("LayerCollector")'),
    ('a likeness from behind', TALK, STORY, 'face.Position + face.LookVector * LIKENESS.back', 'face.Position - face.LookVector * LIKENESS.back'),
    ('no dots', TALK, STORY, '\tCollectionService:GetInstanceAddedSignal("ThinkingBubble"):Connect(thinkOut)\n', ''),
    ('a narrow column again', TOWNS, STORY, 'label.Size = if long then UDim2.fromOffset(SPEECH_WIDE, 0) else UDim2.new()', 'label.Size = UDim2.new()'),
    ('wrapping at everything', TOWNS, STORY, 'local WRAP_AT = 30', 'local WRAP_AT = 300'),
    ('your own bubble narrow', TOWNS, STORY, '\tlaidOut(label, text)\n\tlabel.TextWrapped = true\n\tlabel.TextSize = SPEECH_TEXT\n',
     '\tlabel.AutomaticSize = Enum.AutomaticSize.XY\n\tlabel.TextWrapped = true\n\tlabel.TextSize = SPEECH_TEXT\n'),
    ('letters on the rim', TOWNS, STORY, 'local BUBBLE_SIDE = 14', 'local BUBBLE_SIDE = 12'),
    ('an answer without thinking', TOWNS, STORY,
     '\ttask.wait(THINK.before)\n\tif npc.model.Parent and not npc.busy then\n\t\tTownsfolk.think(npc)\n\tend\n', '\ttask.wait(THINK.before)\n'),
    ('a longer wait', TOWNS, STORY, 'local THINK = { before = 0.6, hold = 0.8 }', 'local THINK = { before = 0.6, hold = 2.8 }'),
    ('the dots gone at once', TOWNS, STORY, 'local THINK = { before = 0.6, hold = 0.8 }', 'local THINK = { before = 1.3, hold = 0.1 }'),
    ('the dots never brought up', TOWNS, STORY, 'CollectionService:AddTag(gui, "ThinkingBubble")', 'CollectionService:AddTag(gui, "Thought")'),
    ('the dots forever', TOWNS, STORY, 'task.delay(THINK.before + THINK.hold + 3, function()', 'task.delay(math.huge, function()'),
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
