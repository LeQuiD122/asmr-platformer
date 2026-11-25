"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 213: VIP worth having (a fifth more a run, a free crate a day, the lounge behind its rope, the VIP-only things), the
rewarded ads (a second chance, a run boost; a few a day), the Run boost, the boutique (real avatar items, on theme) and
the season's things (sold only in their season). A VIP run paying no more; VIP's fifth a third; the gate stopping VIPs;
everyone through the gate; the VIP crate without VIP; the VIP crate twice a day; VIP things not given with VIP; ads
without end; a pretend ad outside Studio; an ad's reward not counted; a boost never used; a bought boost never given;
a limited thing sold out of season; a limited thing shown out of season; a season ending before it begins; the boutique
off theme; a boutique item that cannot be bought; ads by the dozen.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ECON = S / "Server/Services/EconomyService.lua"
CATALOG = S / "Shared/ShopCatalog.lua"
SHOP = S / "Client/Services/ShopService.lua"
CHECK = "check_shop.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


if run(CHECK).returncode != 0:
    sys.exit("%s fails before anything is mutated; fix that first" % CHECK)

MUTATIONS = [
    ('a VIP run paying no more', ECON, '\tif vip then\n\t\tamount = ShopCatalog.vipReward(amount)\n\tend', '\tif vip then\n\tend'),
    ("VIP's fifth a third", CATALOG, 'ShopCatalog.VIP = { tokens = 1.2,', 'ShopCatalog.VIP = { tokens = 1.33,'),
    ('the gate stopping VIPs', ECON, 'physics:CollisionGroupSetCollidable(VIP_GUESTS, VIP_GATE, false)',
     'physics:CollisionGroupSetCollidable(VIP_GUESTS, VIP_GATE, true)'),
    ('everyone through the gate', ECON, 'then VIP_GUESTS else "Default"\n\tpcall(vipGroups)', 'then VIP_GUESTS else VIP_GUESTS\n\tpcall(vipGroups)'),
    ('the VIP crate without VIP', ECON, 'if not (passes[player] and passes[player].VIP) then\n\t\t\treturn answer(player, false, "vip")',
     'if false then\n\t\t\treturn answer(player, false, "vip")'),
    ('the VIP crate twice a day', ECON, '\t\tdata.VipCrateDay = day\n', '\t\tdata.VipCrateDay = 0\n'),
    ('VIP things not given with VIP', ECON, 'local item = ShopCatalog.get(id)\n\t\tif item and item.earn == "vip" then',
     'local item = ShopCatalog.get(id)\n\t\tif item and item.earn == "vipp" then'),
    ('ads without end', ECON, 'if (adsLeft(profile.Data)[what] or 0) <= 0 then', 'if (adsLeft(profile.Data)[what] or 0) < -1 then'),
    ('a pretend ad outside Studio', ECON, 'if RunService:IsStudio() then\n\t\t\t\ttask.wait(1)', 'if true then\n\t\t\t\ttask.wait(1)'),
    ("an ad's reward not counted", ECON, 'if channel == Enum.ProductPurchaseChannel.AdReward then',
     'if channel == Enum.ProductPurchaseChannel.InExperience then'),
    ('a boost never used', ECON, '\tif boosted then\n\t\tprofile.Data.RunBoosts -= 1\n\t\tamount *= 2\n\tend',
     '\tif boosted then\n\t\tamount *= 2\n\tend'),
    ('a bought boost never given', ECON, 'elseif item.id == "RunBoost" then\n\t\t\t-- KEPT until a run is finished',
     'elseif item.id == "RunBoosts" then\n\t\t\t-- KEPT until a run is finished'),
    ('a limited thing sold out of season', ECON, 'if action == "buy" and item.limited and inSeason ~= "on" and inSeason ~= "early" then',
     'if action == "buy" and item.limited and inSeason == "soon" then'),
    ('a limited thing shown out of season', SHOP, 'or ((state == "on" or state == "early") and not table.find(list, item)) or owned(item.id)',
     'or true or owned(item.id)'),
    ('a season ending before it begins', CATALOG, 'limited = { from = "2026-11-14", to = "2026-11-28" }',
     'limited = { from = "2026-11-28", to = "2026-11-14" }'),
    ('the boutique off theme', ECON, 'and not restricted and name and fits and not string.find',
     'and not restricted and name and not string.find'),
    ('a boutique item that cannot be bought', SHOP, 'MarketplaceService:PromptPurchase(player, item.assetId)',
     'MarketplaceService:PromptPurchase(player, 0)'),
    ('ads by the dozen', CATALOG, 'boost = { product = "RunBoost", perDay = 3 }', 'boost = { product = "RunBoost", perDay = 12 }'),
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
