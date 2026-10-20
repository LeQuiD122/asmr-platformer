"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 41: the paste check says what a test needs to know. The data stores never asked about, or asked unguarded;
a Robux item with no id taken as on sale, an item not sold for Robux listed, or the list never said.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
HUBCHECK, PARSE = "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUBCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the data stores never told", BOOT, HUBCHECK, "\tif not storesOk then\n", "\tif false then\n"),
    ("the data stores asked unguarded", BOOT, HUBCHECK, "local storesOk = pcall(function()\n\t\tgame:GetService",
     "local storesOk = true\n\tdo (function()\n\t\tgame:GetService"),
    ("a pass with no id taken as on sale", BOOT, HUBCHECK, "(item.passId or 0) == 0 else", "(item.passId or 1) == 0 else"),
    ("a token item listed", BOOT, HUBCHECK, "if item.robux and unset then", "if unset then"),
    ("the list never said", BOOT, HUBCHECK, 'print("PASTE CHECK: not on sale yet', 'print("PASTE CHECK: unsold'),
    ("a name never declared", BOOT, PARSE, 'local catalogModule = shared and shared:FindFirstChild("ShopCatalog")',
     'local catalogModule = shard and shared:FindFirstChild("ShopCatalog")'),
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
