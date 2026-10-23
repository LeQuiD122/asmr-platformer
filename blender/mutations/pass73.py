"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 73: the starter pack. Not a pass, no tokens, no trail, not once only, not first in Featured; its trail sold, or
given by nothing; given without the pass, every time, without tokens, trail, dashboard or word; nothing on joining, on
a late answer, or when bought; a pass you own not shown Owned; nowhere in a new save; the self-test not giving it
twice, not checking it, not seeing a pass owned, not trying to buy the trail, or leaving it on; the test panel's
doing nothing, or no button; left in Featured once yours, no "Once only"; the pill silent about it or its trail; the
trail's price not leading to it, or saying to finish the story; its tile saying so too.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CAT = S / "Shared/ShopCatalog.lua"
ECON = S / "Server/Services/EconomyService.lua"
SHOPC = S / "Client/Services/ShopService.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

STARTER_TILE = '\telseif item.earn == "starter" and not owned(item.id) then\n\t\t-- In the starter pack only: where it comes from, where a price would be.\n\t\tfill, edge, ink, words = LOOK.robux, LOOK.robuxEdge, LOOK.robuxInk, "Starter pack"\n'

MUTATIONS = [
    ("not a pass", CAT, SHOP, '{ id = "StarterPack", tab = "Passes", kind = "pass",', '{ id = "StarterPack", tab = "Passes", kind = "product",'),
    ("no tokens in it", CAT, SHOP, "robux = 99, passId = 0, tokens = 500,", "robux = 99, passId = 0, tokens = 0,"),
    ("no trail in it", CAT, SHOP, 'gives = "SeaGlass", once = true,', 'once = true,'),
    ("not once only", CAT, SHOP, 'gives = "SeaGlass", once = true,', 'gives = "SeaGlass",'),
    ("not first in Featured", CAT, SHOP, '{ "StarterPack", "VIP", "BgCrate",', '{ "VIP", "StarterPack", "BgCrate",'),
    ("its trail sold", CAT, SHOP, '\t\tearn = "starter", colour = rgb(130, 212, 190)', '\t\tprice = 200, colour = rgb(130, 212, 190)'),
    ("its trail given by nothing", CAT, SHOP, 'earn = "starter", colour', 'earn = "starters", colour'),
    ("given without the pass", ECON, SHOP, "profile:IsActive() and owned and owned.StarterPack and starter", "profile:IsActive() and starter"),
    ("given every time", ECON, SHOP, "\tif data.StarterGranted then\n\t\treturn\n\tend\n", ""),
    ("given without tokens", ECON, SHOP, "\tdata.Tokens += starterTokens\n", ""),
    ("given without its trail", ECON, SHOP, "\t\tdata.Owned[gift.id] = true\n", ""),
    ("off the dashboard", ECON, SHOP, "IAP.Name, starter.id)", "IAP.Name)"),
    ("given without a word", ECON, SHOP, "{ starter = true, gift =", "{ gift ="),
    ("nothing on joining", ECON, SHOP, '\tplayer:SetAttribute("DoubleTokens", owned.DoubleTokens == true)\n\tgrantStarter(player)\n',
     '\tplayer:SetAttribute("DoubleTokens", owned.DoubleTokens == true)\n'),
    ("nothing on a late answer", ECON, SHOP, "\t\t\t\t\tgrantStarter(player)\n", ""),
    ("nothing when bought", ECON, SHOP, "\t\t\tgrantStarter(player)\n\t\t\tpush(player)\n\t\t\tdress(player)\n\t\tend\n\tend)",
     "\t\t\tpush(player)\n\t\t\tdress(player)\n\t\tend\n\tend)"),
    ("a pass you own not shown Owned", ECON, SHOP, "\tif passes[player] and passes[player][id] then\n\t\treturn true\n\tend\n", ""),
    ("nowhere in a new save", ECON, SHOP, "\tStarterGranted = false,", "\tStarterGiven = false,"),
    ("the self-test not giving it twice", ECON, SHOP, "\t\tgrantStarter(player)\n\t\tgrantStarter(player)\n", "\t\tgrantStarter(player)\n"),
    ("the self-test not checking it", ECON, SHOP, "and data.Tokens == beforeStarter + (pack.tokens or 0)", "and true"),
    ("the self-test not seeing a pass owned", ECON, SHOP, 'check("a pass you own shows as owned", owns(player, "StarterPack"))',
     'check("a pass you own shows as owned", true)'),
    ("the self-test not trying the trail", ECON, SHOP, 'glass.ok == false and glass.reason == "earned"', "true"),
    ("the self-test leaving it on", ECON, SHOP, "\t\tstarterPasses.StarterPack = realStarter\n", ""),
    ("the test panel's doing nothing", ECON, SHOP, "\t\t\towned.StarterPack = true\n\t\t\tgrantStarter(player)\n", "\t\t\towned.StarterPack = true\n"),
    ("the test panel's not undone", ECON, SHOP, "\t\t\tdata.StarterGranted = false\n", ""),
    ("no button for it", DEV, SHOP, '\t{ action = "starter", text = "Starter pack on/off" },\n', ""),
    ("left in Featured once yours", SHOPC, SHOP, 'if not (shop.tab == "Featured" and item.once and owned(item.id)) then',
     "if true then"),
    ("no once only", SHOPC, SHOP, 'elseif item.once then "Once only"', ""),
    ("the pill silent about it", SHOPC, SHOP, '\t\t\ttable.insert(reasons, "Starter pack")\n', ""),
    ("the pill silent about its trail", SHOPC, SHOP, '\t\tribbon = ("  and the %s trail"):format(string.lower(info.gift))\n', ""),
    ("the trail's price leading nowhere", SHOPC, SHOP, '\t\t\tShopService.showTab("Passes")\n', ""),
    ("the trail saying to finish the story", SHOPC, SHOP,
     '\tif item.earn == "starter" and not owned(item.id) then\n\t\tlocal pack = ShopCatalog.get("StarterPack")',
     '\tif false then\n\t\tlocal pack = ShopCatalog.get("StarterPack")'),
    ("its tile saying so too", SHOPC, SHOP, STARTER_TILE, ""),
    ("a name never declared", ECON, PARSE, "\tdata.Tokens += starterTokens\n", "\tdata.Tokens += starterToken\n"),
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
