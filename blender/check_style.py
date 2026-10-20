"""One look for the whole game, checked without Studio (the ninety-ninth pass).

    python blender/check_style.py

From your notes: "verify that the style of text, and their fonts and the textures and the stylistic choices are similar
throughout the game, so that we do not have an inconsistency in one place vs another". What it holds:
  * ONE PLACE FOR EVERY FACE: Shared/Style.lua names every font the game uses; no other file names a font of its own
    (no Enum.Font, Font.new, Font.fromEnum or Font.fromName, and no old-style `.Font =`), so a face cannot drift.
  * ONE FAMILY FOR EVERY WORD (the hundred-and-second pass): every face in Style, the screen's and the world's, is
    Nunito, told apart by weight and slant alone.
  * THE WORLD'S PRINT STAYS IN THE WORLD: Style.WORLD (the town's signs, letters, the time card) is used only where
    words are printed on a part (a SurfaceGui), never on a screen or over someone's head.
  * THE MENUS SHARE ONE PALETTE: every menu and the run's own panels take their panel, ink and accent from
    Style.COLOUR (the run's panels were a purple of their own); and their corners and outlines from Style.RADIUS and
    Style.STROKE.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
problems = []


def fail(message):
    problems.append(message)


style_path = SRC / "Shared" / "Style.lua"
STYLE = style_path.read_text(encoding="utf-8") if style_path.exists() else ""
if not STYLE:
    fail("src/Shared/Style.lua is missing: the game's faces and colours have no one place")

# ONE PLACE FOR EVERY FACE.
FONT_WORDS = re.compile(r"Enum\.Font\.\w+|Font\.new\(|Font\.fromEnum\(|Font\.fromName\(|\.Font = ")
sources = {p: p.read_text(encoding="utf-8") for p in SRC.rglob("*.lua")}
for path, text in sources.items():
    if path == style_path:
        continue
    for m in FONT_WORDS.finditer(text):
        line = text.count("\n", 0, m.start()) + 1
        fail("%s:%d names a font of its own (%s): take it from Style" % (path.relative_to(SRC), line, m.group().strip()))

# ONE FAMILY FOR EVERY WORD (the hundred-and-second pass: "They should all be ONE style!!!"): every face in Style,
# the screen's and the world's, is Nunito, told apart by weight and slant alone.
for block_name in ("Style.FONT = {", "Style.WORLD = {"):
    start = STYLE.find(block_name)
    block = STYLE[start:STYLE.find("}", start)] if start >= 0 else ""
    if not block:
        fail("Style has no %s" % block_name[:-4])
    for m in re.finditer(r"Enum\.Font\.(\w+)|Font\.fromEnum|Font\.fromName", block):
        fail("%s has a face that is not Nunito (%s)" % (block_name[:-4], m.group()))
    for line in re.findall(r"^	\w+ = (.*)$", block, re.M):
        if not line.startswith("nunito(Enum.FontWeight."):
            fail("%s has a face that is not Nunito (%s)" % (block_name[:-4], line.split(" --")[0]))
if 'local NUNITO = "rbxasset://fonts/families/Nunito.json"' not in STYLE or "return Font.new(NUNITO, weight," not in STYLE:
    fail("Style's one family is not Nunito")
if len(re.findall(r'families/(\w+)\.json', STYLE)) != 1:
    fail("Style names another family besides Nunito")
font_block = STYLE[STYLE.find("Style.FONT = {"):STYLE.find("}", STYLE.find("Style.FONT = {"))]
for key in ("display", "heading", "body", "number", "paper", "shout", "murmur"):
    if not re.search(r"^	%s = " % key, font_block, re.M):
        fail("Style.FONT has no %s" % key)

# THE WORLD'S PRINT STAYS IN THE WORLD: Style.WORLD only in a file that prints on parts, and within reach of the
# SurfaceGui it prints on.
for path, text in sources.items():
    if path == style_path:
        continue
    for m in re.finditer(r"Style\.WORLD\.\w+", text):
        before = text[max(0, m.start() - 1600):m.start()]
        if 'Instance.new("SurfaceGui")' not in before:
            line = text.count("\n", 0, m.start()) + 1
            fail("%s:%d puts the world's print (%s) somewhere that is not a part's face" % (path.relative_to(SRC), line,
                                                                                           m.group()))

# EVERY FILE THAT SETS TEXT TAKES ITS FACE FROM STYLE.
for path, text in sources.items():
    if path == style_path:
        continue
    # (Or through the shop's kit, whose faces are Style's: ShopService's CHUNKY and BODY.)
    own = [v for v in re.findall(r"FontFace = ([\w.]+)", text) if not v.startswith("kit.")]
    if own and 'local Style = require(' not in text:
        fail("%s sets a face without the game's Style" % path.relative_to(SRC))
shop = sources.get(SRC / "Client" / "Services" / "ShopService.lua", "")
if "local CHUNKY = Style.FONT.display" not in shop or "local BODY = Style.FONT.heading" not in shop:
    fail("ShopService: the kit's faces (CHUNKY, BODY) are not Style's, and the shop, the emotes and the test panel use them")

# THE MENUS SHARE ONE PALETTE, AND THEIR CORNERS AND OUTLINES.
NEEDLES = {
    ("Client", "Services", "UIService.lua"): ("surface = Style.COLOUR.panel", "textPrimary = Style.COLOUR.ink",
                                              "gold = Style.COLOUR.accent", "local RADIUS = Style.RADIUS.button"),
    ("Client", "Services", "PauseMenuService.lua"): ("local ACCENT = Style.COLOUR.accent", "Style.RADIUS.panel",
                                                     "Style.STROKE.panel"),
    ("Client", "Services", "HubVoteService.lua"): ("local ACCENT = Style.COLOUR.accent", "Style.COLOUR.panel",
                                                   "Style.RADIUS.panel"),
    ("Client", "Services", "DeathService.lua"): ("Style.COLOUR.accent", "Style.RADIUS.button"),
    ("Client", "Services", "JournalService.lua"): ("local COVER = Style.COLOUR.panel", "local ACCENT = Style.COLOUR.accent"),
    ("Client", "Services", "Cinema.lua"): ("Style.RADIUS.panel", "Style.STROKE.panel"),
}
for rel, needles in NEEDLES.items():
    text = sources.get(SRC.joinpath(*rel), "")
    for needle in needles:
        if needle not in text:
            fail("%s: its look is its own again (%s)" % (rel[-1], needle))
# The shared colours, defined once: the panel and the accent are not written out anywhere but Style.
for path, text in sources.items():
    if path == style_path or "Client" not in path.parts:
        continue
    for literal, name in (("Color3.fromRGB(20, 19, 27)", "the panel"), ("Color3.fromRGB(246, 206, 148)", "the accent")):
        if literal in text:
            fail("%s writes out %s's colour (%s) instead of Style's" % (path.relative_to(SRC), name, literal))

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("style: every word in the game in one family, Nunito, by weight and slant alone, every face from Style (the world's "
      "print on parts only), and the menus and the run's panels in one palette, one set of corners and outlines.")
