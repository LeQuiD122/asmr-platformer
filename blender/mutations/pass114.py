"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 114: clocking in. No time clock beside him, or nothing under it; its rack in the far rail, the clock in
the way along the deck, or behind him; clocked in before it is earned; silent when it is too soon, a dash in what he
says, or not pointing to Mr Wick; nothing giving the clue; clocking in marking nothing, carried into the next level, or
not standing you at it; never punched on your screen; no note; he says nothing; the client never hearing it, leaving
the prompt up, never punching the card, playing it as an ending, or with no stand-in for its sound; its sound not
listed; the card's shot moved without the check; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
CONV = S / "Shared/Conversations.lua"
HC = S / "Client/Services/FloodedHallsClient.lua"
STORYSV = S / "Server/Services/StoryService.lua"
SHOTS, TRUE, PARSE = "check_shots.py", "check_trueending.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOTS, TRUE, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('no time clock beside him', STORYSV, TRUE, '\ttimeClock(parent, spot, npc)\nend', 'end'),
    ('nothing under it', STORYSV, TRUE, 'prop(model, "ClockPillar"', 'prop(model, "ClockPost"'),
    ('its rack in the far rail', STORYSV, TRUE, 'local at = spot * CFrame.new(-2.0, 0, -2.5)', 'local at = spot * CFrame.new(-2.6, 0, -2.5)'),
    ('in the way along the deck', STORYSV, TRUE, 'local at = spot * CFrame.new(-2.0, 0, -2.5)', 'local at = spot * CFrame.new(3.4, 0, -2.5)'),
    ('behind him', STORYSV, TRUE, 'local at = spot * CFrame.new(-2.0, 0, -2.5)', 'local at = spot * CFrame.new(-2.0, 0, 2.5)'),
    ('clocked in before it is earned', STORYSV, TRUE, 'if not Townsfolk.knows(player, "clue:price") then', 'if not Townsfolk.knows(player, "clue:face") then'),
    ('silent when it is too soon', STORYSV, TRUE, 'Townsfolk.say(npc, if Townsfolk.knows(player, "clue:father") then NOT_YET.father else NOT_YET.first)', 'local _ = NOT_YET'),
    ('a dash in what he says', STORYSV, TRUE, '"Ask me about him first. Then sign."', '"Ask me about him first -- then sign."'),
    ('not pointing to Mr Wick', STORYSV, TRUE, 'Mr Wick on the pier knew him.', 'Somebody knew him.'),
    ('nothing giving the clue', CONV, TRUE, 'needs = "father", clue = "price"', 'needs = "father"'),
    ('clocking in marking nothing', STORYSV, TRUE, 'player:SetAttribute("ClockedIn", true)', 'player:SetAttribute("ClockedIn", false)'),
    ('carried into the next level', STORYSV, TRUE, '\t\tplayer:SetAttribute("ClockedIn", nil)\n', ''),
    ('not standing you at it', STORYSV, TRUE, '\t\t\troot.CFrame = stand\n', ''),
    ('never punched on your screen', STORYSV, TRUE, 'halls:FireClient(player, "clockin", model)', 'halls:FireClient(player, "clocked", model)'),
    ('no note', CONV, TRUE, '\tclocked = { title = "Clocked in",', '\tclockedIn = { title = "Clocked in",'),
    ('he says nothing', STORYSV, TRUE, 'Townsfolk.say(npc, CLOCKED)', 'local _ = CLOCKED'),
    ('the client never hearing it', HC, TRUE, 'if kind == "clockin" and', 'if kind == "clocked" and'),
    ('the prompt left up', HC, TRUE, '\t\tprompt.Enabled = false\n', ''),
    ('never punching the card', HC, TRUE, '\t\t\t\t\twords.Text = stamped\n', ''),
    ('played as an ending', HC, TRUE, '\tCinema.begin({ hush = false })\n\tholdMine("key")', '\tCinema.begin()\n\tholdMine("key")'),
    ('no stand-in for its sound', HC, TRUE, 'sound("ClockPunch", CLICK,', 'sound("ClockPunch", nil,'),
    ('its sound not listed', BOOT, TRUE, 'ClockStart = true,\n\t\tClockPunch = true, MorningChord', 'ClockStart = true,\n\t\tMorningChord'),
    ("the card's shot moved without the check", HC, SHOTS, 'Cinema.point(CFrame.lookAt(at * Vector3.new(1.4, 5, -5), at * Vector3.new(0.3, 4, -1)), 48)', 'Cinema.point(CFrame.lookAt(at * Vector3.new(1.3, 5.2, -4.4), at * Vector3.new(0, 3.95, -0.56)), 46)'),
    ('a name never declared', HC, PARSE, 'local token = clocking.token', 'local token = clockinn.token'),
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
