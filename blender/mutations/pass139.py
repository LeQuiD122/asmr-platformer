"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 139: the screen put right. The board's rows never cleared, a hundred of them, two refreshes drawn into each
other, a name looked up for each row; the folded clock under a phone's thumb, the gap under the clock; the clock, the
board and the panels in the lobby; the pause card a run's in the lobby, a way out of it, its face never put on; the
vote card in the server's words or with a dash; the death card switched on; a run's tokens told under its scene, held
for ever, or the black not seen.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
DEATH = S / "Client/Services/DeathService.lua"
PAUSE = S / "Client/Services/PauseMenuService.lua"
SHOPC = S / "Client/Services/ShopService.lua"
UIS = S / "Client/Services/UIService.lua"
VOTE = S / "Client/Services/HubVoteService.lua"
POLISH = "check_polish.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (POLISH,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the board's rows never cleared", UIS, POLISH, 'for _, child in ipairs(leaderboardContent:GetChildren()) do', 'for _, child in ipairs(leaderboard:GetChildren()) do'),
    ('a hundred rows', UIS, POLISH, 'local TOP_ROWS = 4', 'local TOP_ROWS = 100'),
    ('two refreshes drawn into each other', UIS, POLISH, '\t\tif refreshTicket ~= ticket then\n\t\t\treturn\n\t\tend\n', ''),
    ('a name looked up as each row is drawn', UIS, POLISH, 'who.Text = names[i]', 'who.Text = nameFor(entry.userId)'),
    ('the folded clock under the thumb', UIS, POLISH, '\t\ttimerPill.Position = timerPanel.Position\n', ''),
    ('the gap under the clock', UIS, POLISH, 'timerPanel.Position = UDim2.new(1, -SPACE.xl, 1, -(SPACE.xl + MODE_TALL + SPACE.sm))', 'timerPanel.Position = UDim2.new(1, -SPACE.xl, 1, -(SPACE.xl + 44 + SPACE.sm))'),
    ('the clock in the lobby', UIS, POLISH, 'timerPanel.Visible = timerShown and not timerFolded and onLevel()', 'timerPanel.Visible = timerShown and not timerFolded'),
    ('the board in the lobby', UIS, POLISH, 'return visible and (currentMode == "hardcore" or chillBoardEnabled) and onLevel()', 'return visible and (currentMode == "hardcore" or chillBoardEnabled)'),
    ('the panels never following you', UIS, POLISH, 'player:GetAttributeChangedSignal("InLevel"):Connect(showForPlace)', 'local _ = showForPlace'),
    ("the lobby's card a run's", PAUSE, POLISH, 'face.heading.Text = if rooms then "The back rooms" elseif running then "This run" else "In the lobby"', 'face.heading.Text = "This run"'),
    ('a way out of the lobby', PAUSE, POLISH, 'face.leave.Visible = level ~= nil', 'face.leave.Visible = true'),
    ("the card's face never put on", PAUSE, POLISH, '\t\tshowFace()\n\t\tframe.Visible = true', '\t\tframe.Visible = true'),
    ("the server's words on the vote card", VOTE, POLISH, 'cap(result.mode), cap(result.length),', 'tostring(result.mode), tostring(result.length),'),
    ('a dash on the vote card', VOTE, POLISH, '("%s  ·  %s run  ·  %d %s voted")', '("%s  -  %s run  -  %d %s voted")'),
    ('the death card switched on', DEATH, POLISH, 'local come = math.clamp(since / ARRIVE, 0, 1)', 'local come = 1'),
    ('tokens told under the scene', SHOPC, POLISH, 'while heldBack() and os.clock() - began < 60 do', 'while false do'),
    ('tokens held for ever', SHOPC, POLISH, 'while heldBack() and os.clock() - began < 60 do', 'while heldBack() do'),
    ('the black not seen', SHOPC, POLISH, '(ui ~= nil and type(ui.isBlack) == "function" and ui.isBlack())', 'false'),
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
