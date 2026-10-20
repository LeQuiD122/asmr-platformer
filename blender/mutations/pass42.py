"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 42: the fingerprints. A module changed and not stamped again, a changed module with no stamp, Bootstrap
expecting the wrong modules; the server not comparing or not handing the client its stamps; the client not
comparing, not naming what it found, or never run.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
SHOP_MODULE = S / "Client/Services/ShopService.lua"
MATERIALS = S / "Shared/MaterialConfig.lua"
BOOT = S / "Server/Bootstrap.server.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
STAMPS, PARSE = "check_stamps.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STAMPS, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("changed and not stamped again", SHOP_MODULE, STAMPS, 'ShopService.STAMP = "', '-- a change\nShopService.STAMP = "'),
    ("a changed module with no stamp", MATERIALS, STAMPS, '\tSTAMP = "', '\tOLDSTAMP = "'),
    ("Bootstrap expecting the wrong module", BOOT, STAMPS, '\t\tShopService = "', '\t\tShopServiceOld = "'),
    ("the client not handed its stamps", BOOT, STAMPS, 'ReplicatedStorage:SetAttribute("PasteStamps"',
     'ReplicatedStorage:SetAttribute("Stamps"'),
    ("the server not comparing", BOOT, STAMPS,
     "\t\t\t\tif stamp ~= expected[name] and not misplaced[name] then\n\t\t\t\t\ttable.insert(problems",
     "\t\t\t\tif false then\n\t\t\t\t\ttable.insert(problems"),
    ("the client not comparing", CBOOT, STAMPS, "\t\t\tif stamp ~= expected[name] then\n\t\t\t\ttable.insert(stale, name)",
     "\t\t\tif false then\n\t\t\t\ttable.insert(stale, name)"),
    ("the client not naming them", CBOOT, STAMPS, 'warn(("PASTE CHECK (client): %d old cop%s', 'print(("PASTE CHECK (client): %d old cop%s'),
    ("the client's half never run", CBOOT, STAMPS, "\t\tlocal ok, err = pcall(pasteCheckClient)", "\t\tlocal ok, err = true, nil"),
    ("a name never declared", CBOOT, PARSE, "\tlocal stale = {}\n\tfor _, name in ipairs(names) do\n\t\tlocal found = Services:FindFirstChild(name)",
     "\tlocal stale = {}\n\tfor _, name in ipairs(names) do\n\t\tlocal found = Servics:FindFirstChild(name)"),
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
