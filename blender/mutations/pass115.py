"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 115: the true ending. Edwin Marsh with no look, or the Watcher's face; given lines; never stood in the
chamber, with no ribbon, or not stood up with the baths' people; waiting in the room or past the grille; told nowhere,
or facing away; no more time given, the rider's screen not told it, or the run ending first; seen on every screen;
played for a rider who did not clock in, or never played; its beats out of order, starting late, or longer than the
time given; walking into the room, or not going back into the light; not reaching the gate in time; the day not
ending; nobody waving back; him not waving; no chord, or nothing standing in; never going out of sight; never ending;
its chord not listed; a shot moved without the check; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
HC = S / "Client/Services/FloodedHallsClient.lua"
HS = S / "Server/Services/FloodedHallsService.lua"
STORYSV = S / "Server/Services/StoryService.lua"
TOWNS = S / "Server/Services/Townsfolk.lua"
SHOTS, TRUE, PARSE = "check_shots.py", "check_trueending.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOTS, TRUE, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('no look', TOWNS, TRUE, '\tMarsh = { skin = Color3.fromRGB(214, 176, 146)', '\tMarshX = { skin = Color3.fromRGB(214, 176, 146)'),
    ("the Watcher's face, not his", TOWNS, TRUE, 'Marsh = { skin = Color3.fromRGB(214, 176, 146), hair = Color3.fromRGB(70, 56, 46), hairStyle = "short",', 'Marsh = { skin = Color3.fromRGB(214, 176, 146), hair = Color3.fromRGB(70, 56, 46),'),
    ('given lines', TOWNS, TRUE, "\t-- LEVEL 5, HILL HOUSE, eight in the morning (first in the story's clock: before any of it).\n\tGale = {", '\tMarsh = {\n\t\t"Hello.",\n\t\t"It\'s you.",\n\t\t"Go on.",\n\t},\n\t-- LEVEL 5, HILL HOUSE, eight in the morning (first in the story\'s clock: before any of it).\n\tGale = {'),
    ('never stood in the chamber', STORYSV, TRUE, 'local npc = Townsfolk.spawn(chamber, "Marsh", spot, "stand",', 'local npc = Townsfolk.spawn(halls, "Marsh", spot, "stand",'),
    ('no ribbon', STORYSV, TRUE, 'Townsfolk.wear(npc, "Ribbon",', 'Townsfolk.wear(npc, "Scarf",'),
    ("not stood up with the baths' people", STORYSV, TRUE, '\t\t\tpcall(barlow, folder)\n\t\t\tpcall(marsh)\n', '\t\t\tpcall(barlow, folder)\n'),
    ('waiting in the room', HS, TRUE, '\tMARSH_AT = -66,', '\tMARSH_AT = -30,'),
    ('waiting past the grille', HS, TRUE, '\tMARSH_AT = -66,', '\tMARSH_AT = -100,'),
    ('told nowhere', HS, TRUE, 'model:SetAttribute("MarshSpot", frame * CFrame.new(0, 0, g.MARSH_AT) * CFrame.Angles(0, math.pi, 0))', 'local _ = g.MARSH_AT'),
    ('facing away', HS, TRUE, 'frame * CFrame.new(0, 0, g.MARSH_AT) * CFrame.Angles(0, math.pi, 0)', 'frame * CFrame.new(0, 0, g.MARSH_AT)'),
    ('no more time given', HS, TRUE, 'local gates = GATES.SECONDS + (if player:GetAttribute("ClockedIn") == true then GATES.TRUE else 0)', 'local gates = GATES.SECONDS'),
    ("the rider's screen not told it", HS, TRUE, 'if chamber then gates else 0, if chamber then GATES.MAW else 0)', 'if chamber then GATES.SECONDS else 0, if chamber then GATES.MAW else 0)'),
    ('the run ending first', HS, TRUE, '\t\t\t\ttask.wait(gates)\n', '\t\t\t\ttask.wait(GATES.SECONDS)\n'),
    ('seen on every screen', HC, TRUE, '\t\t\t\titem.LocalTransparencyModifier = 1\n\t\t\t\ttable.insert(opening.marshParts, item)', '\t\t\t\ttable.insert(opening.marshParts, item)'),
    ('played for a rider who did not clock in', HC, TRUE, 'opening.trueEnd = opening.marsh ~= nil and opening.chamber ~= nil and Players.LocalPlayer:GetAttribute("ClockedIn") == true', 'opening.trueEnd = opening.marsh ~= nil and opening.chamber ~= nil'),
    ('never played', HC, TRUE, '\telseif current.trueEnd then\n\t\ttrueStep(current, b)\n', ''),
    ('its beats out of order', HC, TRUE, 'local TRUE = { light = 35, face = 41.6, wave = 46.2, morning = 51.2, done = 57.2 }', 'local TRUE = { light = 35, face = 47, wave = 46.2, morning = 51.2, done = 57.2 }'),
    ('starting late', HC, TRUE, 'local TRUE = { light = 35, face = 41.6, wave = 46.2, morning = 51.2, done = 57.2 }', 'local TRUE = { light = 36, face = 41.6, wave = 46.2, morning = 51.2, done = 57.2 }'),
    ('longer than the time given', HS, TRUE, '\tTRUE = 16,', '\tTRUE = 9,'),
    ('walking into the room', HC, TRUE, 'local MARSH = { stop = -45, walk = 3.6, back = -78 }', 'local MARSH = { stop = -30, walk = 3.6, back = -78 }'),
    ('not going back into the light', HC, TRUE, 'local MARSH = { stop = -45, walk = 3.6, back = -78 }', 'local MARSH = { stop = -45, walk = 3.6, back = -40 }'),
    ('not reaching the gate in time', HC, TRUE, 'local MARSH = { stop = -45, walk = 3.6, back = -78 }', 'local MARSH = { stop = -45, walk = 2, back = -78 }'),
    ('the day not ending', HC, TRUE, '"15 August. The tide went out, and the day ended."', '"14 August. 9:14 in the morning."'),
    ('nobody waving back', HC, TRUE, '\t\t\tholdMine("wave")\n', ''),
    ('him not waving', HC, TRUE, 'by = Poses.wave(name, b - TRUE.wave, raised, r6)', 'by = walkPose(name, b)'),
    ('nothing standing in for the chord', HC, TRUE, 'sound("MorningChord", nil, 0.7, 1, false) or sound("EndChord", nil, 0.7, 1, false)', 'sound("MorningChord", nil, 0.7, 1, false)'),
    ('never going out of sight', HC, TRUE, 'seen = 1 - math.clamp((b - (TRUE.done - 2.6)) / 2.2, 0, 1)', 'seen = 1'),
    ('never ending', HC, TRUE, '\telse\n\t\tendScene()\n\tend\nend\n\n-- THE GATE CHAMBER', '\tend\nend\n\n-- THE GATE CHAMBER'),
    ('its chord not listed', BOOT, TRUE, '"ClockPunch",\n\t\t"MorningChord", "PoolsSong", "BarStrike", "BrickBurst" }', '"ClockPunch",\n\t\t"PoolsSong", "BarStrike", "BrickBurst" }'),
    ("his face's shot moved without the check", HC, SHOTS, 'Cinema.point(CFrame.lookAt(at(0, 5.2, MARSH.stop + 7), at(0, 4.7, MARSH.stop)), 38)', 'Cinema.point(CFrame.lookAt(at(0, 5.2, MARSH.stop + 3), at(0, 4.7, MARSH.stop)), 38)'),
    ('a name never declared', HC, PARSE, 'local span = MARSH.stop - from.Z', 'local span = MARSH.stop - form.Z'),
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
