"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 50: the VIP tag. Shown on a level, given to everyone, left on someone without VIP, not put on with the rest,
not taken off on a level; the shop not saying so; no way to see it in Studio.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ECON = S / "Server/Services/EconomyService.lua"
CAT = S / "Shared/ShopCatalog.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("shown on a level", ECON, SHOP, 'shown.Enabled = player:GetAttribute("InLevel") == nil', "shown.Enabled = true"),
    ("given to everyone", ECON, SHOP, "local isVip = passes[player] ~= nil and passes[player].VIP == true", "local isVip = true"),
    ("left on without VIP", ECON, SHOP, "\t\tif existing then\n\t\t\texisting:Destroy()\n\t\tend\n\t\treturn", "\t\treturn"),
    ("not put on with the rest", ECON, SHOP, '"Cosmetic")\n\tvipTag(player)\nend', '"Cosmetic")\nend'),
    ("not off on a level", ECON, SHOP,
     '\t\tplayer:GetAttributeChangedSignal("InLevel"):Connect(function()\n\t\t\tvipTag(player)\n\t\tend)\n', ""),
    ("drawn from any distance", ECON, SHOP, "\t\tgui.MaxDistance = 80\n", ""),
    ("the shop not saying so", CAT, SHOP, "A VIP tag over your head and in chat", "A VIP tag in chat"),
    ("no way to see it in Studio", DEV, SHOP, '\t{ action = "vip", text = "VIP on/off" },\n', ""),
    ("a name never declared", ECON, PARSE, "local isVip = passes[player] ~= nil and passes[player].VIP == true",
     "local isVip = passs[player] ~= nil and passes[player].VIP == true"),
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
