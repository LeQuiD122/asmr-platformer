"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 214: the boutique's banner, the lobby's billboards (Roblox's immersive ads), VIP early and the VIP chest, the trails
and steps made with generated meshes, prints on the lobby's deck, the crown worn upright. A banner leading nowhere; a
banner over Wear itself; a billboard too small to serve ads; a billboard hidden by the pads; Roblox's logo for anyone
not shown an ad; no video ads; one billboard; no VIP early; a VIP chest paying the same; prints under the deck; a tilted
crown; glass pieces back.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
SHOP = S / "Client/Services/ShopService.lua"
HUB = S / "Server/Services/HubService.lua"
CATALOG = S / "Shared/ShopCatalog.lua"
ECON = S / "Server/Services/EconomyService.lua"
STEP = S / "Client/Services/StepService.lua"
COSMETICS = S / "Client/Services/CosmeticsClient.lua"
CHECK = "check_shop.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


if run(CHECK).returncode != 0:
    sys.exit("%s fails before anything is mutated; fix that first" % CHECK)

MUTATIONS = [
    ('a banner leading nowhere', SHOP, '\t\tShopService.showTab("Wear")\n\tend)\n\tbanner.MouseEnter', '\t\tShopService.showTab("Featured")\n\tend)\n\tbanner.MouseEnter'),
    ('a banner over Wear itself', SHOP, 'local showing = shop.tab ~= "Wear"', 'local showing = true'),
    ('a billboard too small to serve ads', HUB, 'local AD_BOARD = { w = 16, h = 9,', 'local AD_BOARD = { w = 6, h = 3,'),
    ('a billboard hidden by the pads', HUB, 'foot = 11.5, post = 0.7 }', 'foot = 3.6, post = 0.7 }'),
    ("Roblox's logo for anyone not shown an ad", HUB, '\tad.FallbackImage = fallback\n', '\n'),
    ('no video ads', HUB, 'ad.EnableVideoAds = true', 'ad.EnableVideoAds = false'),
    ('one billboard', HUB, '\tbuildAdBoard(HUB_ORIGIN + AT.adBoardEast,', '\t-- buildAdBoard(HUB_ORIGIN + AT.adBoardEast,'),
    ('no VIP early', CATALOG, 'if vip and at < from and at >= from - ShopCatalog.VIP.early * 86400 then',
     'if false and at < from and at >= from - ShopCatalog.VIP.early * 86400 then'),
    ('a VIP chest paying the same', ECON, 'amount = math.floor(amount * ShopCatalog.VIP.daily + 0.5)', 'amount = amount'),
    ('prints under the deck', STEP, 'if up.Y > 0.9 then\n\t\tat = onDeck(at)', 'if up.Y > 9 then\n\t\tat = onDeck(at)'),
    ('a tilted crown', COSMETICS, 'local tilt = if one.motion == "halo" then 0 else 0.3', 'local tilt = 0.3'),
    ('glass pieces back', CATALOG, '{ mesh = "Cos_JellyBean", size = 0.42, colours = { rgb(255, 150, 180) }, shine = 0.3 }',
     '{ mesh = "Cos_JellyBean", size = 0.42, colours = { rgb(255, 150, 180) }, material = "Glass", shine = 0.3 }'),
]

paths = {m[1] for m in MUTATIONS}
originals = {path: path.read_bytes() for path in paths}
missed = []
try:
    for label, path, old, new in MUTATIONS:
        text = originals[path].decode("utf-8").replace("\r\n", "\n")
        assert text.count(old) == 1, "%s: anchor found %d times" % (label, text.count(old))
        path.write_bytes(text.replace(old, new).encode("utf-8"))
        result = run(CHECK)
        path.write_bytes(originals[path])
        caught = result.returncode != 0
        why = [line.strip() for line in (result.stdout + result.stderr).splitlines() if line.startswith("FAIL")][:2]
        print("%-8s %s  %s" % ("caught" if caught else "MISSED", label, "; ".join(why)[:170]))
        if not caught:
            missed.append(label)
finally:
    for path, data in originals.items():
        path.write_bytes(data)
print("\n%d of %d caught" % (len(MUTATIONS) - len(missed), len(MUTATIONS)))
sys.exit(1 if missed else 0)
