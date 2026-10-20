"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 105: the shop's look. A background with no sound, one never drawn, a press on one doing nothing, a rarity
that is not one; a default sold in the crates, two defaults only, never one at random; two tabs one colour, their
sounds out of order, a tab with no take; a press on a button cracking the background; the cookie under a finger; the
system's cursor never back; presses answered once shut; the opening with the closing's sound; your soap not your own;
the effects under the shop; an image for a background; ShopService not putting it in, not closing it, the tabs one
colour, a controller's tab silent, the title not recoloured; the module not started; slots that are not the
generator's (in the file, in ShopLook, the water's drip); a sound asked for that is not there, or not checked for by
Bootstrap; a background pressing with a material that has no sound; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
LOOK = S / "Client/Services/ShopLook.lua"
SHOPC = S / "Client/Services/ShopService.lua"
SHOPGEN = ROOT / "audio/gen_shop_sfx.py"
AUDIOCHECK, SHOP, PARSE = "check_audio.py", "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (AUDIOCHECK, SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a background with no sound', LOOK, SHOP, 'effect = "flakes", sound = "MaterialSounds/soapCrumble", ', 'effect = "flakes", '),
    ('a background never drawn', LOOK, SHOP, 'decor = "frost",', 'decor = "snowflakes",'),
    ('a press doing nothing', LOOK, SHOP, 'effect = "sparks", sound', 'effect = "embers", sound'),
    ('a rarity that is not one', LOOK, SHOP, 'rarity = "mythic"', 'rarity = "ultra"'),
    ('a default sold in the crates', LOOK, SHOP, 'name = "Cookie", rarity = "default"', 'name = "Cookie", rarity = "common"'),
    ('two defaults only', LOOK, SHOP, 'ShopLook.DEFAULTS = { "cookie", "soap", "ice" }', 'ShopLook.DEFAULTS = { "cookie", "soap" }'),
    ('never one at random', LOOK, SHOP, 'id = ShopLook.DEFAULTS[math.random(1, #ShopLook.DEFAULTS)]', 'id = ShopLook.DEFAULTS[1]'),
    ('two tabs one colour', LOOK, SHOP, 'Trails = rgb(160, 204, 255)', 'Trails = rgb(176, 222, 160)'),
    ("the tabs' sounds out of order", LOOK, SHOP, 'TAB_ORDER = { "Featured", "Steps", "Trails"', 'TAB_ORDER = { "Featured", "Trails", "Steps"'),
    ('a press on a button cracking it', LOOK, SHOP, 'if onPanel and not onButton then', 'if onPanel then'),
    ('the cookie under a finger', LOOK, SHOP, 'local usingMouse = UserInputService.MouseEnabled and not UserInputService.TouchEnabled', 'local usingMouse = true'),
    ('the cursor never back', LOOK, SHOP, 'UserInputService.MouseIconEnabled = true', 'UserInputService.MouseIconEnabled = false'),
    ('presses answered once shut', LOOK, SHOP, 'look.pressing:Disconnect()\n\t\tlook.pressing = nil', 'look.pressing = nil'),
    ("opening with the closing's sound", LOOK, SHOP, 'playSound("ShopSounds/ShopOpen", 0.6)', 'playSound("ShopSounds/ShopClose", 0.6)'),
    ('your soap not your own', LOOK, SHOP, 'if folderName == "MaterialSounds" and AudioService and', 'if folderName == "MaterialSound" and AudioService and'),
    ('the effects under the shop', LOOK, SHOP, 'fx.DisplayOrder = (screen.DisplayOrder or 30) + 1', 'fx.DisplayOrder = (screen.DisplayOrder or 30) - 1'),
    ('an image for a background', LOOK, SHOP, 'local f = Instance.new("Frame")\n\tf.AnchorPoint', 'local f = Instance.new("ImageLabel")\n\tf.AnchorPoint'),
    ('not put in the shop', SHOPC, SHOP, '\t\tShopLook.attach(panel, screen)', '\t\tShopLook.attached = true'),
    ('not closing its look', SHOPC, SHOP, '\t\tShopLook.closed()\n', '\t\tlocal _ = ShopLook\n'),
    ('the tabs one colour (ShopService)', SHOPC, SHOP, 'ShopLook.TAB_COLOURS[button.Name]', 'ShopLook.TAB_COLOURS[shop.tab]'),
    ("a controller's tab silent", SHOPC, SHOP, 'ShopLook.tab(nextTab)', 'ShopLook.tab(shop.tab)'),
    ('the title not recoloured', SHOPC, SHOP, 'ui.title.BackgroundColor3 = theme.title', 'ui.title.BackgroundColor3 = LOOK.edge'),
    ('the module not started', BOOT, SHOP, '"ShopLook", "SquishRoomClient"', '"SquishRoomClient"'),
    ("a file's slots not the generator's", SHOPGEN, AUDIOCHECK, 'SLOTS = {"ShopTab": 1.2,', 'SLOTS = {"ShopTab": 1.25,'),
    ("ShopLook's slots not the generator's", LOOK, AUDIOCHECK, 'local SLOT = { ShopTab = 1.2,', 'local SLOT = { ShopTab = 1.0,'),
    ("the drip in slots not the water's", LOOK, AUDIOCHECK, 'material = 1.0, Drip = 1.0 }', 'material = 1.0, Drip = 0.5 }'),
    ('a sound that is not there', LOOK, AUDIOCHECK, 'playSound("ShopSounds/ShopClose", 0.55)', 'playSound("ShopSounds/ShopShut", 0.55)'),
    ('a tab with no take', LOOK, AUDIOCHECK, '"Tokens", "Backgrounds" }', '"Tokens", "Backgrounds", "Pets" }'),
    ('a sound Bootstrap does not check for', BOOT, AUDIOCHECK, '"ShopOpen", "ShopTab_x9" }', '"ShopOpen" }'),
    ('a material with no sound', LOOK, AUDIOCHECK, 'sound = "MaterialSounds/cloudHush"', 'sound = "MaterialSounds/cloudPuff"'),
    ('a name never declared', LOOK, PARSE, 'local index = table.find(ShopLook.TAB_ORDER, name)', 'local index = table.find(ShopLook.TAB_ORDER, nam)'),
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
