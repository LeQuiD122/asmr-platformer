"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 144: one soft sound for every press. The ping back in the shop or in the press; the shop not through
the press, or its names not turned into kinds; a refusal or a short purchase silent; the sheet played whole; the same
tap twice running; the press's slot or a kind's slot not the sheet's, or the sheet's slot changed; the sheet missing
from the paste check; the pause card, the death card, the journal's closing and the words chosen silent; the journal's
helper never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
AUDIO = S / "Client/Services/AudioService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
DEATH = S / "Client/Services/DeathService.lua"
JOURNAL = S / "Client/Services/JournalService.lua"
PAUSE = S / "Client/Services/PauseMenuService.lua"
SHOPC = S / "Client/Services/ShopService.lua"
TALK = S / "Client/Services/TalkClient.lua"
UIGEN = ROOT / "audio/gen_ui_sfx.py"
AUDIOCHECK, POLISH, PARSE = "check_audio.py", "check_polish.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (AUDIOCHECK, POLISH, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the ping back in the shop', SHOPC, POLISH, 'made.SoundId = "rbxasset://sounds/clickfast.wav"\n\tmade.PlaybackSpeed = 0.75', 'made.SoundId = "rbxasset://sounds/electronicpingshort.wav"\n\tmade.PlaybackSpeed = 0.75'),
    ('the ping back in the press', AUDIO, POLISH, 's.SoundId = "rbxasset://sounds/clickfast.wav"\n\t\ts.PlaybackSpeed = if kind', 's.SoundId = "rbxasset://sounds/electronicpingshort.wav"\n\t\ts.PlaybackSpeed = if kind'),
    ('the shop not through the press', SHOPC, POLISH, '\t\t\taudio.press(kind, volume)\n', '\t\t\taudio.playSfx(kind, volume)\n'),
    ("the shop's names not turned into kinds", SHOPC, POLISH, 'local kind = if event == "bubblePop" then "good" elseif event == "buttonClick" then "tap" else event', 'local kind = event'),
    ('a crate refused silent', SHOPC, POLISH, 'uiSound("no", 0.45)\n\ttoast(CRATE_WORDS[result.reason]', 'toast(CRATE_WORDS[result.reason]'),
    ('a short purchase silent', SHOPC, POLISH, '\t\t\tuiSound("no", 0.45)\n\t\t\ttoast("Not enough tokens.")', '\t\t\ttoast("Not enough tokens.")'),
    ('the sheet played whole', AUDIO, POLISH, '(take :: any).PlaybackRegion = NumberRange.new(from, from + PRESS_SLOT - 0.05)', '(take :: any).PlaybackRegion = NumberRange.new(from, 99)'),
    ('the same tap twice running', AUDIO, POLISH, '\t\t\tif pick == lastTap then', '\t\t\tif false then'),
    ('the press out of its slot', AUDIO, AUDIOCHECK, 'local PRESS_SLOT = 0.8', 'local PRESS_SLOT = 1.0'),
    ('a kind with no slot', AUDIO, AUDIOCHECK, 'no = { slots = { 7 }, volume = 0.45 },', 'no = { slots = { 8 }, volume = 0.45 },'),
    ("the sheet's slot changed", UIGEN, AUDIOCHECK, 'SLOTS = {"UiTaps": 0.8}', 'SLOTS = {"UiTaps": 0.9}'),
    ('the sheet not in the paste check', BOOT, AUDIOCHECK, '"ShopTab_x9",\n\t\t"UiTaps_x8" }', '"ShopTab_x9" }'),
    ('the pause card silent', PAUSE, POLISH, '\tpressSound(if open then "open" else "close")\n', ''),
    ('Try again silent', DEATH, POLISH, 'again.Activated:Connect(function()\n\t\tpressSound("tap")\n', 'again.Activated:Connect(function()\n'),
    ('the journal shut in silence', JOURNAL, POLISH, '\t\tpressSound("close")\n\t\tContextActionService:UnbindAction("JournalClose")', '\t\tContextActionService:UnbindAction("JournalClose")'),
    ('the words chosen in silence', TALK, POLISH, '\t\tpressSound("tap")\n\t\tchoose(index)', '\t\tchoose(index)'),
    ("the journal's helper never declared", JOURNAL, PARSE, 'local function pressSound(kind: string)', 'local function pressSounds(kind: string)'),
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
