"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 97: the shop's things, modelled. A trail with no pieces; an aura moving as a trail does; a mesh that is
never made; a piece the size of a person; a flood of pieces, or too many round you; Neon for a piece; what is worn not
tagged on the character; the try-on not drawn over what is worn; pieces drawn however far off, with no limit in all, or
limits too loose; pieces that can be walked into; pieces made and destroyed each time; Neon allowed by the client; the
steps flat prints only; the client's Bootstrap not starting it; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CAT = S / "Shared/ShopCatalog.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
COSM = S / "Client/Services/CosmeticsClient.lua"
STEPS = S / "Client/Services/StepService.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a trail with no pieces', CAT, SHOP, 'Sprinkles = { motion = "toss"', 'Sprinklez = { motion = "toss"'),
    ('an aura moving as a trail', CAT, SHOP, 'Starlight = { motion = "orbit"', 'Starlight = { motion = "toss"'),
    ('a mesh never made', CAT, SHOP, 'mesh = "Cos_Snowflake"', 'mesh = "Cos_Snowflakes"'),
    ('a piece the size of a person', CAT, SHOP, '{ mesh = "Cos_Sprinkle", size = 0.34', '{ mesh = "Cos_Sprinkle", size = 3.4'),
    ('a flood of pieces', CAT, SHOP, 'Sprinkles = { motion = "toss", every = 0.45', 'Sprinkles = { motion = "toss", every = 0.1'),
    ('too many round you', CAT, SHOP, 'Snowfall = { motion = "fall", count = 8', 'Snowfall = { motion = "fall", count = 20'),
    ('Neon for a piece', CAT, SHOP, 'rgb(236, 226, 255) }, material = "Glass",', 'rgb(236, 226, 255) }, material = "Neon",'),
    ('what is worn not tagged', CAT, SHOP, 'top:SetAttribute("PieceTrail", trail.id)', 'top:SetAttribute("PieceTrails", trail.id)'),
    ('the try-on not drawn', COSM, SHOP, 'root:FindFirstChild("ShopPreviewTrailTop") or root:FindFirstChild("CosmeticTrailTop")', 'root:FindFirstChild("CosmeticTrailTop")'),
    ('drawn however far off', COSM, SHOP, '(root.Position - eye).Magnitude < NEAR', '(root.Position - eye).Magnitude < 1e9'),
    ('no limit in all', COSM, SHOP, 'if #live >= PIECES_MAX then', 'if false then'),
    ('limits too loose', COSM, SHOP, 'local PIECES_MAX = 260', 'local PIECES_MAX = 2600'),
    ('pieces to walk into', COSM, SHOP, 'made.CanCollide = false', 'made.CanCollide = true'),
    ('pieces never kept', COSM, SHOP, 'table.insert(pool[mesh], part)', 'part:Destroy()'),
    ('a squash kept from the pool', COSM, SHOP, 'made:SetAttribute("Base", made.Size)', 'made:SetAttribute("Bases", made.Size)'),
    ('Neon allowed', COSM, SHOP, 'elseif piece.material == "Neon" then Enum.Material.SmoothPlastic', 'elseif piece.material == "Neon" then Enum.Material.Neon'),
    ('the steps flat only', STEPS, SHOP, 'local made = meshPrint(id, CFrame.fromMatrix(at, right, up), life)', 'local made = nil'),
    ('never started', CBOOT, SHOP, '"SearchlightClient", "CosmeticsClient",', '"SearchlightClient",'),
    ('a name never declared', COSM, PARSE, 'spawn(player, look, here - heading * 0.9', 'spawns(player, look, here - heading * 0.9'),
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
