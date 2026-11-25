"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 215: the crown held on the head, prints facing the way you walk, the drawn penguin print, the side rail, the plaza's
fingerpost and flower troughs. A crown left behind as you run; honey paws pointing back; prints that cannot turn; a drawn
print looked for as a mesh; the rail during a run; a 2x that offers nothing; no rail; no fingerpost or troughs; a
fingerpost sunk in the inlay; troughs past the inlay's edge.
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
    ('a crown left behind as you run', COSMETICS, 'part.CFrame = head.CFrame * CFrame.new(0, lift, 0)', 'part.CFrame = CFrame.new(head.Position) * CFrame.new(0, lift, 0)'),
    ('honey paws pointing back', CATALOG, 'shine = 0.3, yaw = 180 } } },', 'shine = 0.3 } } },'),
    ('prints that cannot turn', STEP, 'frame = frame * CFrame.Angles(0, math.rad(piece.yaw or 0), 0)', 'frame = frame'),
    ('a drawn print looked for as a mesh', STEP, 'if not (piece and template) or piece.mesh == "Flat" then', 'if not (piece and template) then'),
    ('the rail during a run', SHOP, 'screen.Enabled = player:GetAttribute("InLevel") == nil', 'screen.Enabled = true'),
    ('a 2x that offers nothing', SHOP, 'MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, item.passId)', 'print(item.passId)'),
    ('no rail', SHOP, '\tbuildRail()\n', '\t-- buildRail()\n'),
    ('no fingerpost or troughs', HUB, '\tbuildFingerpost(HUB_ORIGIN + AT.fingerpost, folder)\n', '\n'),
    ('a fingerpost sunk in the inlay', HUB, 'local base = at + Vector3.new(0, 0.325, 0) -- on the inlay', 'local base = at -- on the inlay'),
    ('troughs past the inlay', HUB, 'local inset = plaza.w / 2 - LobbyLayout.MARGIN - 1', 'local inset = plaza.w / 2 - 1'),
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
