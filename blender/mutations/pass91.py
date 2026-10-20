"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 91: the lobby, polished, and one text for the story. The embers back to a few plain streams, or a streak
drawn as a dot; the VIP badge one flat colour, without its crown, its shine or its outline, the crown not three
points, or its shine never swept, never moving, or a bar again (showing past the badge's round ends); the countdown's ping back, its sounds never found, the last three seconds like the
rest, or nothing as it runs out; a level opening in silence; the countdown's sounds not listed; the keepsakes' total
counting the module's stamp; a line of the story in another typeface; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
CAT = S / "Shared/ShopCatalog.lua"
CINEMA = S / "Client/Services/Cinema.lua"
ECON = S / "Server/Services/EconomyService.lua"
JOURNAL = S / "Client/Services/JournalService.lua"
SHOPC = S / "Client/Services/ShopService.lua"
STORYC = S / "Client/Services/StoryClient.lua"
VOTE = S / "Client/Services/HubVoteService.lua"
HUB, SHOP, STORY, PARSE = "check_hub.py", "check_shop.py", "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUB, SHOP, STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the embers plain again', CAT, SHOP, 'accel = Vector3.new(0, -6, 0), light = 1, streak = true,', 'accel = Vector3.new(0, -6, 0), light = 1,'),
    ('a streak drawn as a dot', CAT, SHOP, '\t\tm.Orientation = Enum.ParticleOrientation.VelocityParallel\n', ''),
    ('the badge one flat colour', ECON, SHOP, 'local fill = Instance.new("UIGradient")', 'local fill = Instance.new("Frame")'),
    ('no crown', ECON, SHOP, 'crown.Name = "Crown"', 'crown.Name = "Top"'),
    ('no shine', ECON, SHOP, 'shine.Name = "Shine"', 'shine.Name = "Glint"'),
    ('no outline', ECON, SHOP, 'word.TextStrokeTransparency = 0\n', 'word.TextStrokeTransparency = 1\n'),
    ('a crown of one point', ECON, SHOP, 'for k = 0, 2 do', 'for k = 0, 0 do'),
    ('the shine never swept', SHOPC, SHOP, '\tshineVipBadges()\n', ''),
    ('the shine never moving', SHOPC, SHOP, '{ Offset = Vector2.new(1, 0) }):Play()', '{ Offset = Vector2.new(-1, 0) }):Play()'),
    ('the shine a bar again', ECON, SHOP, 'shineCorner.CornerRadius = UDim.new(0.5, 0)', 'shineCorner.CornerRadius = UDim.new(0, 0)'),
    ('the ping back', VOTE, SHOP, 'TICK.SoundId = "rbxasset://sounds/clickfast.wav"', 'TICK.SoundId = "rbxasset://sounds/electronicpingshort.wav"'),
    ("the countdown's sounds never found", VOTE, SHOP, 'folder:FindFirstChild("CountdownTock_x3")', 'folder:FindFirstChild("CountdownTock")'),
    ('the last three like the rest', VOTE, SHOP, 'tock(if left <= 3 then 1 else 0)', 'tock(0)'),
    ('nothing as it runs out', VOTE, SHOP, '\t\ttock(2)\n', ''),
    ('a level opening in silence', VOTE, HUB, '\tHubVoteService.say("NEW", title, body)\n\ttock(2)\n', '\tHubVoteService.say("NEW", title, body)\n'),
    ("the countdown's sounds not listed", BOOT, SHOP, ', "TownsfolkVoice_x9", "CountdownTock_x3", "JournalAdd", "DoorSlam"', ', "TownsfolkVoice_x9", "JournalAdd", "DoorSlam"'),
    ('the stamp counted as a keepsake', JOURNAL, SHOP, 'if typeof(entry) == "table" and typeof(entry.thing) == "string" then', 'if typeof(entry) == "table" or typeof(entry) == "string" then'),
    ('a thought in Garamond', CINEMA, STORY, '\twords.FontFace = Style.FONT.body\n', '\twords.FontFace = Style.FONT.paper\n'),
    ('a whisper in Garamond', STORYC, STORY, '\tlabel.FontFace = Style.FONT.body\n', '\tlabel.FontFace = Style.FONT.paper\n'),
    ('a name never declared', VOTE, PARSE, '\tlocal from = which * TICK_SLOT\n', '\tlocal from = which * TICK_SLOTS\n'),
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
