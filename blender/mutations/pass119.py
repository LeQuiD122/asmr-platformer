"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 119, from your test: one speech bubble, and you tell your line with your body. No bubble in Style; the
people's lines, or yours, out of it; no tail; your choices back on the dark panel, or not the bubble's cream, ink, face
or rim; who you are talking to not in a bubble; your line said standing still, or never told on anyone's screen; a
player's gesture stiffening their walk; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
STORYC = S / "Client/Services/StoryClient.lua"
STYLE = S / "Shared/Style.lua"
TALK = S / "Client/Services/TalkClient.lua"
TOWNS = S / "Server/Services/Townsfolk.lua"
STORY, PARSE = "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('no bubble in Style', STYLE, STORY, 'Style.BUBBLE = {', 'Style.SPEECH = {'),
    ("the people's lines out of it", TOWNS, STORY, '\telse\n\t\tasBubble(gui, label, Style.BUBBLE.rim)\n\tend', '\telse\n\t\tlabel.BackgroundColor3 = Color3.fromRGB(250, 248, 242)\n\tend'),
    ('yours out of it', TOWNS, STORY, 'asBubble(gui, label, Style.BUBBLE.rimMine)', 'label.BackgroundColor3 = Style.COLOUR.ink'),
    ('no tail', TOWNS, STORY, 'tail.Name = "Tail"', 'tail.Name = "Point"'),
    ('your choices back on the dark panel', TALK, STORY, 'button.BackgroundColor3 = bubble.fill', 'button.BackgroundColor3 = Style.COLOUR.panel'),
    ("not the bubble's ink", TALK, STORY, 'button.TextColor3 = bubble.ink', 'button.TextColor3 = bubble.fill'),
    ("not the bubble's face", TALK, STORY, 'button.FontFace = bubble.font', 'button.FontFace = Style.FONT.body'),
    ("not the bubble's rim", TALK, STORY, 'edge.Color = bubble.rim', 'edge.Color = bubble.fill'),
    ('who you are talking to not in a bubble', TALK, STORY, 'eyebrow.BackgroundColor3 = Style.BUBBLE.fill', 'eyebrow.BackgroundTransparency = 1'),
    ('your line said standing still', TOWNS, STORY, 'character:SetAttribute("Gesture", gestureForText(text))', 'character:SetAttribute("Said", gestureForText(text))'),
    ("never told on anyone's screen", TOWNS, STORY, 'CollectionService:AddTag(character, "Teller")', 'local _ = CollectionService'),
    ("never told on anyone's screen, client", STORYC, STORY, 'for _, tag in ipairs({ "Townsperson", "Teller" }) do', 'for _, tag in ipairs({ "Townsperson" }) do'),
    ("a player's gesture stiffening their walk", STORYC, STORY, 'if by or not own then\n', 'if true then\n'),
    ('a name never declared', TALK, PARSE, 'local bubble = Style.BUBBLE\n', 'local bubble = Style.BUBBLES\n\tlocal _ = bubbl\n'),
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
