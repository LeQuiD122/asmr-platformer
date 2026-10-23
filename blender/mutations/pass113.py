"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 113: Hill House's people. Mr Gale or Mrs Dunn never stood up, or with nothing to say; neither knowing
about the key; a line told without its gesture; no voice or look of their own; a dash in what they say; Mr Gale on the
bridge's side, over the landing's edge or in the way over; Mrs Dunn on the path or in the gateway; the people never
stood up; a topic waiting on a clue nothing gives; his clock's clue with no note; a caption in the hall with a dash; a
name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CONV = S / "Shared/Conversations.lua"
HILLC = S / "Client/Services/HillHouseClient.lua"
HOUSE = S / "Server/Services/HillHouseService.lua"
TOWNS = S / "Server/Services/Townsfolk.lua"
HILL, STORY, PARSE = "check_hillhouse.py", "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HILL, STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('Mr Gale never stood up', HOUSE, STORY, 'Townsfolk.spawn(model, "Gale", feet, "stand",', 'Townsfolk.spawn(model, "Gael", feet, "stand",'),
    ('Mrs Dunn with nothing to say', TOWNS, STORY, '\tDunn = {\n\t\t"Morning, love.', '\tDunnX = {\n\t\t"Morning, love.'),
    ('neither knowing about the key', TOWNS, STORY, '"Big day, the paper says. Key holder for Outfall 3. They\'ll want you at the station by nine.",\n\t\t"The key\'s on its hook where it always was. He used to say a key wants a place, so nobody has to look for it.",', '"Big day, the paper says. They\'ll want you at the station by nine.",\n\t\t"It\'s on its hook where it always was. He used to say a thing wants a place, so nobody has to look for it.",'),
    ('a line told without its gesture', TOWNS, STORY, '\tGale = { "greet", "worry", "point", "remember", "warn", "shrug" },', '\tGale = { "greet", "worry", "point", "remember", "warn" },'),
    ('no voice of her own', TOWNS, STORY, 'Gale = 0.86, Dunn = 1.06,', 'Gale = 0.86,'),
    ('no look of his own', TOWNS, STORY, '\tGale = { skin = Color3.fromRGB(222, 182, 150)', '\tGaleX = { skin = Color3.fromRGB(222, 182, 150)'),
    ('a dash in what they say', TOWNS, STORY, '"Go on up, then. I\'ll not keep you."', '"Go on up, then -- I\'ll not keep you."'),
    ("Mr Gale on the bridge's side", HOUSE, HILL, 'local away = if landing.RightVector:Dot(out) > 0 then -1 else 1', 'local away = if landing.RightVector:Dot(out) > 0 then 1 else -1'),
    ("Mr Gale over the landing's edge", HOUSE, HILL, 'CFrame.new(away * (LANDING.X / 2 - 2.5), LANDING.Y / 2, -(LANDING.Z / 2 - 2.5))', 'CFrame.new(away * (LANDING.X / 2 - 0.5), LANDING.Y / 2, -(LANDING.Z / 2 - 2.5))'),
    ('Mr Gale in the way over', HOUSE, HILL, 'CFrame.new(away * (LANDING.X / 2 - 2.5), LANDING.Y / 2, -(LANDING.Z / 2 - 2.5))', 'CFrame.new(away * (LANDING.X / 2 - 6.9), LANDING.Y / 2, -(LANDING.Z / 2 - 4.9))'),
    ('Mrs Dunn on the path', HOUSE, HILL, 'local stand = gate + inward * 5 + across * 4.8', 'local stand = gate + inward * 5 + across * 1.2'),
    ('Mrs Dunn in the gateway', HOUSE, HILL, 'local stand = gate + inward * 5 + across * 4.8', 'local stand = gate + inward * 0.5 + across * 4.8'),
    ('the people never stood up', HOUSE, HILL, '\tpeople(model, garden, landing, out, endAt, inward, across, topY)\n', ''),
    ('a topic waiting on a clue nothing gives', CONV, STORY, 'say = "The second pint was for me, wasn\'t it.", needs = "father"', 'say = "The second pint was for me, wasn\'t it.", needs = "milk"'),
    ("his clock's clue with no note", CONV, STORY, '\tclock = { title = "His clock"', '\tclocks = { title = "His clock"'),
    ('a caption in the hall with a dash', HILLC, STORY, '"Four minutes to midnight since 1979. It is going again."', '"Four minutes to midnight since 1979 -- it is going again."'),
    ('a name never declared', HOUSE, PARSE, 'local stand = gate + inward * 5', 'local stand = gates + inward * 5'),
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
