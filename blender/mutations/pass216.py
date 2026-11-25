"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 216: the pals. Five pals, not six; a pal of a motion nobody knows; a pal too big; a pal for 5 tokens;
no Pals tab; a pal never named on you; a pal not looked for; dragged after a teleport; floating off the ground; made
however far off; never moved; worn without owning it; never tried on.
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
LAYOUT = S / "Shared/LobbyLayout.lua"
CHECK = "check_shop.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


if run(CHECK).returncode != 0:
    sys.exit("%s fails before anything is mutated; fix that first" % CHECK)

MUTATIONS = [
    ('five pals, not six', CATALOG, '\t{ id = "PalLava", tab = "Pals", kind = "pal",', '\t{ id = "PalLava", tab = "Hidden", kind = "pal",'),
    ('a motion nobody knows', CATALOG, 'mesh = "Pal_Bee", size = 1.4, motion = "buzz"', 'mesh = "Pal_Bee", size = 1.4, motion = "warp"'),
    ('a pal too big', CATALOG, 'mesh = "Pal_Cloud", size = 2.2,', 'mesh = "Pal_Cloud", size = 6,'),
    ('a pal for 5 tokens', CATALOG, 'blurb = "A squishy little ball that hops along after you",\n\t\tprice = 350,',
     'blurb = "A squishy little ball that hops along after you",\n\t\tprice = 5,'),
    ('no Pals tab', CATALOG, 'ShopCatalog.TABS = { "Featured", "Pals",', 'ShopCatalog.TABS = { "Featured",'),
    ('a pal never named on you', CATALOG, 'at:SetAttribute("PiecePal", pal.id)', 'at:SetAttribute("Piece", pal.id)'),
    ('a pal not looked for', COSMETICS, 'local tag = root and (root:FindFirstChild("ShopPreviewPal") or root:FindFirstChild("CosmeticPal"))',
     'local tag = root and root:FindFirstChild("ShopPreviewPal")'),
    ('dragged after a teleport', COSMETICS, 'if fresh or (pal.at - want).Magnitude > PAL_JUMP then', 'if fresh then'),
    ('floating off the ground', COSMETICS, 'local hit = workspace:Raycast(Vector3.new(pal.at.X, root.Position.Y + 2, pal.at.Z), Vector3.new(0, -10, 0), rayParams)',
     'local hit = nil'),
    ('dropping into a gap', COSMETICS, 'if ground < feet - 4 or ground > feet + 4 then\n\t\t\t\tground = feet', 'if false then\n\t\t\t\tground = feet'),
    ('left behind when you jump', COSMETICS, 'ground = math.max(ground, feet - 1)', 'ground = ground'),
    ('made however far off', COSMETICS, '(root.Position - eye).Magnitude < NEAR) then\n\t\t\tdropPal(player)', 'true) then\n\t\t\tdropPal(player)'),
    ('never moved', COSMETICS, '\tmovePals(dt, now, eye)\n', '\n'),
    ('worn without owning it', ECON, 'if pal and pal.kind == "pal" and owns(player, pal.id) then pal else nil)',
     'if pal and pal.kind == "pal" then pal else nil)'),
    ('never tried on', SHOP, 'if item.kind == "pal" then item else nil)', 'nil)'),
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
