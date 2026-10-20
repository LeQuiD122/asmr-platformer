"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 24: every screen on every device. A menu a controller cannot open or close, nothing selected when it
opens, the journal back on Y (which is Talk), a button too small for a thumb, a card wider than a phone, a
menu under the notch, and the run's corner panels back over the thumbstick and the jump button.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src/Client/Services"
PAUSE = S / "PauseMenuService.lua"
JOURNAL = S / "JournalService.lua"
DEATH = S / "DeathService.lua"
UI = S / "UIService.lua"
VOTE = S / "HubVoteService.lua"
WELCOME = S / "OnboardingService.lua"
CHECK, PARSE = "check_devices.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # A controller.
    ("no way into the pause menu", PAUSE, CHECK, "Enum.KeyCode.M, Enum.KeyCode.Escape, Enum.KeyCode.DPadDown)",
     "Enum.KeyCode.M, Enum.KeyCode.Escape)"),
    ("the journal back on Talk's button", JOURNAL, CHECK, "input.KeyCode == Enum.KeyCode.DPadUp", "input.KeyCode == Enum.KeyCode.ButtonY"),
    ("nothing selected in the pause menu", PAUSE, CHECK, "\t\t\tGuiService.SelectedObject = firstButton\n", "\n"),
    ("B does not close the pause menu", PAUSE, CHECK, 'BindActionAtPriority("PauseMenuBack"', 'BindActionAtPriority("PauseBack"'),
    ("nothing selected in the journal", JOURNAL, CHECK, "SelectedObject = ui.tabs[shownKind]", "SelectedObject = nil"),
    ("nothing selected on the death card", DEATH, CHECK, "SelectedObject = firstChoice", "SelectedObject = nil"),
    ("the welcome naming the wrong buttons", WELCOME, CHECK, "D-pad up opens your journal, D-pad down the menu",
     "Y opens your journal"),
    ("a selection left behind", DEATH, CHECK, "\t\tGuiService.SelectedObject = nil\n", "\n"),
    # A thumb.
    ("the journal's close too small", JOURNAL, CHECK, "close.Size = UDim2.fromOffset(44, 44)", "close.Size = UDim2.fromOffset(30, 30)"),
    ("the journal's tabs too short", JOURNAL, CHECK, "tabsRow.Size = UDim2.new(1, 0, 0, 44)", "tabsRow.Size = UDim2.new(1, 0, 0, 30)"),
    ("the pause tab too small", PAUSE, CHECK, "tab.Size = UDim2.new(0, 44, 0, 44)", "tab.Size = UDim2.new(0, 32, 0, 32)"),
    # A phone held upright.
    ("the banner wider than a phone", UI, CHECK, "completion.Size = UDim2.new(0.92, 0, 0, 172)", "completion.Size = UDim2.new(0, 520, 0, 172)"),
    ("the vote card wider than a phone", VOTE, CHECK, "panel.Size = UDim2.new(0.92, 0, 0, 116)", "panel.Size = UDim2.new(0, 440, 0, 116)"),
    ("the pause card uncapped", PAUSE, CHECK, "cardMost.MaxSize = Vector2.new(380, 304)", "cardMost.MaxSize = Vector2.new(980, 304)"),
    # A notch, a thumbstick, a jump button.
    ("the journal under the notch", JOURNAL, CHECK, "screen.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets",
     "screen.IgnoreGuiInset = true"),
    ("the best times over the thumbstick", UI, CHECK, "leaderboard.Position = UDim2.new(0, SPACE.xl, 0, SPACE.xl)",
     "leaderboard.Position = UDim2.new(0, SPACE.xl, 1, -SPACE.xl)"),
    ("the clock over the jump button", UI, CHECK, "timerPanel.Position = UDim2.new(1, -SPACE.xl, 0, top + 26 + SPACE.sm)",
     "timerPanel.Position = UDim2.new(1, -SPACE.xl, 1, -SPACE.xl)"),
    # The code still reads.
    ("a name never declared in the pause menu", PAUSE, PARSE, "\t\tif usingPad() and firstButton then",
     "\t\tif usingPad() and firstButon then"),
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
