"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 99: one look for the whole game. A face named outside Style (an old font back on a caption, a sign's face
set in a service, the old way of setting a face); the screen's family not Nunito; a face the game has lost; the world's
print on a screen (a sign's face over someone's head); a file setting faces without Style; the shop's kit not Style's;
the run's panels in a purple of their own again; the menus' accent written out; a menu's corners its own again; the
journal's cover its own colour; the story's caption in the paper's face; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CINEMA = S / "Client/Services/Cinema.lua"
DEATH = S / "Client/Services/DeathService.lua"
JOURNAL = S / "Client/Services/JournalService.lua"
PAUSE = S / "Client/Services/PauseMenuService.lua"
SHOPC = S / "Client/Services/ShopService.lua"
STYLE = S / "Shared/Style.lua"
SUNKS = S / "Server/Services/SunkenCityService.lua"
TOWNS2 = S / "Server/Services/Townsfolk.lua"
UIS = S / "Client/Services/UIService.lua"
STORY, STYLECHECK, PARSE = "check_story.py", "check_style.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, STYLECHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('an old font on a caption', CINEMA, STYLECHECK, '\twords.FontFace = Style.FONT.body\n', '\twords.Font = Enum.Font.GothamMedium\n'),
    ("a sign's face set in a service", SUNKS, STYLECHECK, 'piece.FontFace = if quiet then Style.FONT.murmur else Style.FONT.shout', 'piece.FontFace = Font.fromEnum(Enum.Font.Kalam)'),
    ("the screen's family not Nunito", STYLE, STYLECHECK, 'heading = nunito(Enum.FontWeight.Bold),', 'heading = Font.fromEnum(Enum.Font.GothamBold),'),
    ('a face the game has lost', STYLE, STYLECHECK, '\tnumber = nunito(', '\tnumbers = nunito('),
    ("the world's print over a head", TOWNS2, STYLECHECK, 'label.FontFace = Style.FONT.shout', 'label.FontFace = Style.WORLD.signHeavy'),
    ("the shop's kit not Style's", SHOPC, STYLECHECK, 'local CHUNKY = Style.FONT.display', 'local CHUNKY = Style.FONT.body'),
    ("the run's panels purple again", UIS, STYLECHECK, '\tsurface = Style.COLOUR.panel,', '\tsurface = Color3.fromRGB(22, 19, 28),'),
    ('the accent written out', PAUSE, STYLECHECK, 'local ACCENT = Style.COLOUR.accent', 'local ACCENT = Color3.fromRGB(246, 206, 148)'),
    ("a menu's corners its own", PAUSE, STYLECHECK, 'round.CornerRadius = Style.RADIUS.panel', 'round.CornerRadius = UDim.new(0, 18)'),
    ("the journal's cover its own", JOURNAL, STYLECHECK, 'local COVER = Style.COLOUR.panel', 'local COVER = Color3.fromRGB(20, 19, 27)'),
    ("the caption in the paper's face", CINEMA, STORY, '\twords.FontFace = Style.FONT.body\n', '\twords.FontFace = Style.FONT.paper\n'),
    ('a name never declared', DEATH, PARSE, 'local FALLEN = Style.COLOUR.danger', 'local FALLEN = Styles.COLOUR.danger'),
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
