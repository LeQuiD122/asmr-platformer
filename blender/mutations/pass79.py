"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 79: the shop's words and look. A description in other letters, cut off, or shrunk past reading; an "i" smaller
than a thumb, silent to a hover or a press; a gap between an icon and its name; nothing to say about a kind of thing
or a way of earning one; a dash in the "i"'s words; the "i" card left up; an "i" card a thumb can't fit; the device
rules broken by it.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
SHOPC = S / "Client/Services/ShopService.lua"
SHOP, DEVICES, PARSE = "check_shop.py", "check_devices.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, DEVICES, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a description in other letters", SHOPC, SHOP, 'local blurb = label(tile, "Blurb", item.blurb, CHUNKY,',
     'local blurb = label(tile, "Blurb", item.blurb, BODY,'),
    ("a description cut off", SHOPC, SHOP, "\tblurb.TextScaled = true\n", ""),
    ("shrunk past reading", SHOPC, SHOP, "fit.MinTextSize = 10", "fit.MinTextSize = 4"),
    ("an \"i\" smaller than a thumb", SHOPC, SHOP, "\tmore.Position = UDim2.fromOffset(2, 2)\n\tmore.Size = UDim2.fromOffset(MIN_TOUCH, MIN_TOUCH)",
     "\tmore.Position = UDim2.fromOffset(2, 2)\n\tmore.Size = UDim2.fromOffset(26, 26)"),
    ("silent to a hover", SHOPC, SHOP, "\t\tshowInfo(item, more, true)\n", ""),
    ("silent to a press", SHOPC, SHOP, "\t\t\tshowInfo(item, more, false)\n", "\t\t\thideInfo()\n"),
    ("a gap under the icon", SHOPC, SHOP, "local nameY = top + iconD + math.floor(8 * t)", "local nameY = cellH - priceH - 60"),
    ("nothing to say about an aura", SHOPC, SHOP, '\taura = "A glow all around you, for everyone to see. Wear one at a time.",\n', ""),
    ("nothing to say about the starter pack", SHOPC, SHOP, '\tstarter = "Not sold on its own: it comes with the starter pack.",\n', ""),
    ("a dash in its words", SHOPC, SHOP, '"Prints where you walk, for everyone to see.', '"Prints -- where you walk, for everyone to see.'),
    ("the card left up over a new tab", SHOPC, SHOP, "\t\treturn\n\tend\n\thideInfo()\n", "\t\treturn\n\tend\n"),
    ("an \"i\" card a thumb can't fit", SHOPC, DEVICES, '\tlocal info = Instance.new("Frame")\n', '\tlocal info = Instance.new("TextButton")\n'),
    ("a name never declared", SHOPC, PARSE, "\tui.infoTitle.Text = item.name\n", "\tui.infoTitle.Text = items.name\n"),
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
