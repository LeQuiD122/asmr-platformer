"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 106: the backgrounds and their crate. Odds that do not add up, the mythic one in the crate, a rarity with
nothing in it, a rarity out of order, two rarities one colour; a background ShopLook does not draw, one that is a
default, one of the wrong rarity, a theme with nothing that gives it, a background neither in the crate nor a pass;
a crate that can give what you have, or something when you have them all; the crate bought as a thing, handled after
a buy, opened where the policy keeps it out, rolled on the client's word, opened without the tokens, taking them and
giving nothing; the policy never asked, or offered when it did not answer, or the Studio leave reaching the live game;
the shop not told; the mythic one never found owned; the odds not said before paying, or written out by hand; a
background in the crates told to finish the story; Escape closing the shop under a crate; the reveal silent or not
its rarity's, its takes not the sheet's; the crate not fitted to the screen; presses answered under it; a name never
declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CAT = S / "Shared/ShopCatalog.lua"
ECON = S / "Server/Services/EconomyService.lua"
LOOK = S / "Client/Services/ShopLook.lua"
SHOPC = S / "Client/Services/ShopService.lua"
AUDIOCHECK, SHOP, PARSE = "check_audio.py", "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (AUDIOCHECK, SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('odds that do not add up', CAT, SHOP, 'odds = { common = 60, rare = 25, epic = 11, legendary = 4 }', 'odds = { common = 60, rare = 25, epic = 11, legendary = 5 }'),
    ('the mythic one in the crate', CAT, SHOP, 'order = { "common", "rare", "epic", "legendary" },\n\todds = { common = 60, rare = 25, epic = 11, legendary = 4 }', 'order = { "common", "rare", "epic", "legendary", "mythic" },\n\todds = { common = 60, rare = 25, epic = 10, legendary = 4, mythic = 1 }'),
    ('a rarity with nothing in it', CAT, SHOP, 'theme = "backRooms", rarity = "legendary",\n\t\tearn = "crate",', 'theme = "backRooms", rarity = "legendary",\n\t\trobux = 99, passId = 0,'),
    ('a rarity out of order', CAT, SHOP, 'order = { "common", "rare", "epic", "legendary" }', 'order = { "rare", "common", "epic", "legendary" }'),
    ('two rarities one colour', CAT, SHOP, 'rare = { name = "Rare", word = "rare", colour = rgb(66, 134, 214) }', 'rare = { name = "Rare", word = "rare", colour = rgb(112, 164, 96) }'),
    ('a background not drawn', CAT, SHOP, 'theme = "honey", rarity = "common"', 'theme = "treacle", rarity = "common"'),
    ('a background that is a default', CAT, SHOP, 'theme = "slime", rarity = "common"', 'theme = "soap", rarity = "common"'),
    ('a background of the wrong rarity', CAT, SHOP, 'theme = "lava", rarity = "epic"', 'theme = "lava", rarity = "rare"'),
    ('a theme nothing gives', CAT, SHOP, 'theme = "cloud", rarity = "epic"', 'theme = "lava", rarity = "epic"'),
    ('neither in the crate nor a pass', CAT, SHOP, 'rarity = "mythic",\n\t\trobux = 399, passId = 0,', 'rarity = "mythic",\n\t\tprice = 3990,'),
    ('a crate that gives what you have', CAT, SHOP, 'if item.earn == "crate" and item.rarity == rarity and not has(item.id) then', 'if item.earn == "crate" and item.rarity == rarity then'),
    ('something when you have them all', CAT, SHOP, 'if total <= 0 then\n\t\treturn nil\n\tend\n\tlocal at', 'if total <= 0 then\n\t\treturn ITEMS[1]\n\tend\n\tlocal at'),
    ('the crate bought as a thing', ECON, SHOP, 'if action ~= "crate" or item.kind ~= "crate" or not item.price then', 'if item.kind ~= "crate" or not item.price then'),
    ('handled after a buy', ECON, SHOP, 'if action == "crate" or item.kind == "crate" then', 'if action == "crate" and item.kind == "crate" then'),
    ('opened where the policy says no', ECON, SHOP, 'if randomOk[player] ~= true then\n\t\t\treturn answer(player, false, "restricted")', 'if randomOk[player] == false and false then\n\t\t\treturn answer(player, false, "restricted")'),
    ("rolled on the client's word", ECON, SHOP, 'end, crateDice:NextNumber(), crateDice:NextNumber())', 'end, tonumber(id) or 0, 0)'),
    ('opened without the tokens', ECON, SHOP, 'if data.Tokens < item.price then\n\t\t\treturn answer(player, false, "short")', 'if data.Tokens < 0 then\n\t\t\treturn answer(player, false, "short")'),
    ('taking the tokens, giving nothing', ECON, SHOP, 'data.Tokens -= item.price\n\t\tdata.Owned[won.id] = true', 'data.Tokens -= item.price'),
    ('the policy never asked', ECON, SHOP, 'return PolicyService:GetPolicyInfoForPlayerAsync(player)', 'return { ArePaidRandomItemsRestricted = false }'),
    ('offered when it did not answer', ECON, SHOP, 'randomOk[player] = okPolicy and type(policy) == "table" and policy.ArePaidRandomItemsRestricted == false', 'randomOk[player] = not (okPolicy and type(policy) == "table" and policy.ArePaidRandomItemsRestricted == true)'),
    ('the Studio leave reaching the live game', ECON, SHOP, 'if RunService:IsStudio() and not randomOk[player] then\n\t\trandomOk[player] = true', 'if not randomOk[player] then\n\t\trandomOk[player] = true'),
    ('the shop not told', ECON, SHOP, 'crates = randomOk[player] == true,', 'crates = true,'),
    ('the mythic one never found owned', ECON, SHOP, 'if (item.kind == "pass" or item.kind == "background") and item.passId', 'if item.kind == "pass" and item.passId'),
    ('the odds not said before paying', SHOPC, SHOP, 'confirm(("Open a crate for %d tokens? Always one you do not have. %s."):format(price, ShopCatalog.crateOdds(owned)),', 'confirm(("Open a crate for %d tokens? Always one you do not have%s."):format(price, ""),'),
    ('the odds written out by hand', SHOPC, SHOP, 'toast(ShopCatalog.crateOdds(owned) .. ".")', 'toast("Common 60%, rare 25%, epic 11%, legendary 4%.")'),
    ('a crate background told to finish the story', SHOPC, SHOP, '\tif item.kind == "crate" then\n\t\topenCrate(item)\n\t\treturn\n\tend\n', ''),
    ('Escape closing the shop under a crate', SHOPC, SHOP, 'if ShopLook and ShopLook.crating() then\n\t\t\t\tShopLook.dismiss()', 'if ShopLook and false then\n\t\t\t\tShopLook.dismiss()'),
    ('the reveal silent', LOOK, SHOP, 'playSound("ShopSounds/CrateReveal_x5", 0.7, level)', 'local _ = level'),
    ("the reveal not its rarity's", LOOK, SHOP, 'local level = RARITY_TAKE[won.rarity] or 1', 'local level = 1'),
    ("the reveal's takes not the sheet's", LOOK, AUDIOCHECK, 'local RARITY_TAKE = { common = 1, rare = 2, epic = 3, legendary = 4, mythic = 5 }', 'local RARITY_TAKE = { common = 1, rare = 2, epic = 3, legendary = 4, mythic = 6 }'),
    ('not fitted to the screen', LOOK, SHOP, 'Style.fit(stage, Vector2.new(340, 430))', 'local _ = stage'),
    ('presses answered under a crate', LOOK, SHOP, '\t\tbite()\n\t\t-- (Not while a crate is open over it.)\n\t\tif look.crating then\n\t\t\treturn\n\t\tend\n', '\t\tbite()\n'),
    ('a name never declared', LOOK, PARSE, 'local won = c.won\n', 'local won = c.wonn and wonId\n'),
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
