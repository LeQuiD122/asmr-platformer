"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 43: the self-test. The save not put back, or "put back" from itself; a real run lost; the shop's own handler
not used; the button missing or doing nothing.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ECON = S / "Server/Services/EconomyService.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the save not put back", ECON, SHOP, "\tfor key, value in pairs(before) do\n\t\tdata[key] = value\n\tend\n", ""),
    ("put back from itself", ECON, SHOP, "local before = deepCopy(data)", "local before = data"),
    ("a real run lost", ECON, SHOP, "\truns[player] = realRun\n", ""),
    ("not the shop's own handler", ECON, SHOP, 'local result = handle(player, "buy", pick.id)',
     'local result = { ok = true, reason = nil }'),
    ("the button does nothing", ECON, SHOP, 'elseif action == "selftest" then\n\t\ttask.spawn(selfTest, player)',
     'elseif action == "selftest" then\n\t\ttask.spawn(print, player)'),
    ("no button", DEV, SHOP, '\t{ action = "selftest", text = "Self-test" },\n', ""),
    ("a name never declared", ECON, PARSE, "local realRun = runs[player]", "local realRun = runz[player]"),
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
