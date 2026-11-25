"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 160: the real price. The catalogue's number drawn; Roblox's price never used; an id asked as the wrong
kind of thing; someone asking late never answered; the prices never asked; something off sale offered; the best value from
the catalogue; the second chance at the catalogue's price, or offered off sale; an answer with no price taken as on sale;
the paste check not asking Roblox; asking unguarded.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
CAT = S / "Shared/ShopCatalog.lua"
DEATH = S / "Client/Services/DeathService.lua"
SHOPC = S / "Client/Services/ShopService.lua"
STANDARDS = "check_standards.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STANDARDS,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the catalogue's number drawn", SHOPC, STANDARDS, 'fill, edge, ink, words = LOOK.robux, LOOK.robuxEdge, LOOK.robuxInk, "R$ " .. tostring(ShopCatalog.robuxFor(item))', 'fill, edge, ink, words = LOOK.robux, LOOK.robuxEdge, LOOK.robuxInk, "R$ " .. tostring(item.robux)'),
    ("Roblox's price never used", CAT, STANDARDS, 'return if known and known.robux then known.robux else item.robux', 'return item.robux'),
    ('an id asked as the wrong kind of thing', CAT, STANDARDS, 'GetProductInfo(id, if isPass then Enum.InfoType.GamePass else Enum.InfoType.Product)', 'GetProductInfo(id, if isPass then Enum.InfoType.Product else Enum.InfoType.GamePass)'),
    ('someone asking late never answered', CAT, STANDARDS, 'if asked == "answered" then\n\t\tif answered then\n\t\t\ttask.spawn(answered)', 'if asked == "answered" then\n\t\tif false then\n\t\t\ttask.spawn(answered)'),
    ('the prices never asked', SHOPC, STANDARDS, '\tShopCatalog.askPrices(function()\n\t\tif shop.open then\n\t\t\trender()\n\t\tend\n\tend)\n', ''),
    ('something off sale offered', SHOPC, STANDARDS, '(not isPass and productId == 0) or not ShopCatalog.onSale(item) then', '(not isPass and productId == 0) then'),
    ('the best value from the catalogue', SHOPC, STANDARDS, 'local robux = ShopCatalog.robuxFor(item)', 'local robux = item.robux'),
    ("the second chance at the catalogue's price", DEATH, STANDARDS, '("Second chance  R$ %d"):format(chancePrice(item))', '("Second chance  R$ %d"):format(item.robux or 0)'),
    ('the second chance offered off sale', DEATH, STANDARDS, 'if productId ~= 0 and chanceOnSale(item) and not chance.buying then', 'if productId ~= 0 and not chance.buying then'),
    ('an answer with no price taken as on sale', CAT, STANDARDS, 'onSale = robux ~= nil and (info :: any).IsForSale ~= false }', 'onSale = true }'),
    ('the paste check not asking Roblox', BOOT, STANDARDS, 'elseif price and price ~= item.robux then', 'elseif false then'),
    ('asking unguarded', CAT, STANDARDS, 'local ok, info = pcall(function()\n\t\t\t\t\treturn MarketplaceService', 'local ok, info = (function()\n\t\t\t\t\treturn MarketplaceService'),
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
