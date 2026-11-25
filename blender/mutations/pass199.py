"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 199: the leviathan made again, and rock for the boxes. Only the old one laid; no tail; one hump; humps laid into each
other; a giant hump; the head drowned; a hump floating on the sea; the body off its middle; the head looking away; the
head lying flat; the head dressed as the body; the body keeping its made colours; a hide not the serpent's; a black hide;
a shadow from six hundred studs; boxes for islands; a box laid over the rock; a towering rock; rock standing in it.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUB = S / "Server/Services/HubService.lua"
MADE = "check_made.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (MADE,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('only the old one laid', HUB, MADE, 'if not madeLeviathan(leviathanAt, folder) then', 'if true then'),
    ('no tail', HUB, MADE, '\t{ name = "Sea_LeviathanTail", along = 480, size = 150, side = "Y", under = 0.28 },\n', ''),
    ('one hump', HUB, MADE, '\t{ name = "Sea_LeviathanHump", along = 345, size = 135, side = "X", under = 0.44, flip = true },\n', ''),
    ('humps laid into each other', HUB, MADE, 'along = 345, size = 135', 'along = 215, size = 135'),
    ('a giant hump', HUB, MADE, 'along = 175, size = 170, side = "X"', 'along = 175, size = 420, side = "X"'),
    ('the head drowned', HUB, MADE, 'along = -10, size = 175, side = "Z", under = 0.2 }', 'along = -10, size = 175, side = "Z", under = 0.5 }'),
    ('a hump floating on the sea', HUB, MADE, 'size = 170, side = "X", under = 0.34 }', 'size = 170, side = "X", under = 0.02 }'),
    ('the body off its middle', HUB, MADE, 'local LEVIATHAN_HALF = 240', 'local LEVIATHAN_HALF = 0'),
    ('the head looking away', HUB, MADE, 'local LEVIATHAN_HEAD = { look = 0.95, rear = 30 }', 'local LEVIATHAN_HEAD = { look = 0, rear = 30 }'),
    ('the head lying flat', HUB, MADE, 'local LEVIATHAN_HEAD = { look = 0.95, rear = 30 }', 'local LEVIATHAN_HEAD = { look = 0.95, rear = 0 }'),
    ('the head dressed as the body', HUB, MADE, 'if piece.name == "Sea_LeviathanHead" then', 'if piece.name == "Sea_LeviathanNeck" then'),
    ('the body keeping its made colours', HUB, MADE, '\t\t\t\t\tpart.TextureID = ""\n', '\t\t\t\t\tpart.TextureID = part.TextureID\n'),
    ("a hide not the serpent's", HUB, MADE, 'local LEVIATHAN_HIDE = { name = "SerpentHide"', 'local LEVIATHAN_HIDE = { name = "LevelHide"'),
    ('a black hide', HUB, MADE, 'tint = Color3.fromRGB(78, 90, 100) }', 'tint = Color3.fromRGB(10, 12, 14) }'),
    ('a shadow from six hundred studs', HUB, MADE,
     '\t\tpart.CanQuery = false\n\t\tpart.CastShadow = false\n\t\tpart.Size = template.Size * (piece.size',
     '\t\tpart.CanQuery = false\n\t\tpart.CastShadow = true\n\t\tpart.Size = template.Size * (piece.size'),
    ('boxes for islands', HUB, MADE, 'madeProp(if index % 2 == 1 then "Sea_Rock" else "Sea_RockPair")', 'madeProp("Sea_Box")'),
    ('a box laid over the rock', HUB, MADE, '\t\t\tstack.Parent = folder\n\t\t\tcontinue\n', '\t\t\tstack.Parent = folder\n'),
    ('a towering rock', HUB, MADE, 'local ISLANDS = { tall = 72, step = 20, under = 0.16 }', 'local ISLANDS = { tall = 140, step = 20, under = 0.16 }'),
    ('rock standing in it', HUB, MADE, 'local LEVIATHAN_FAR = 620', 'local LEVIATHAN_FAR = 500'),
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
