"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 40: a pass paid for is a pass had, and every Robux prompt on the dashboard. A failed ownership check read
as not owning, never asked again, or a pass found on asking again not applied; a product's or a pass's prompt
closing not logged, or logged unguarded.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ECON = S / "Server/Services/EconomyService.lua"
SHOP, PARSE = "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a failed check read as not owning", ECON, SHOP, "if not ok then\n\t\treturn nil\n\tend", "if not ok then\n\t\treturn false\n\tend"),
    ("a failed check never noted", ECON, SHOP, "\t\t\telseif has == nil then\n\t\t\t\ttable.insert(unsure, item)",
     "\t\t\telseif false then\n\t\t\t\ttable.insert(unsure, item)"),
    ("never asked again", ECON, SHOP, "\tif #unsure > 0 then\n\t\ttask.spawn(function()", "\tif false then\n\t\ttask.spawn(function()"),
    ("asked again at once", ECON, SHOP, "\t\t\t\tgap *= 2\n", ""),
    ("a pass found later not applied", ECON, SHOP, "\t\t\t\t\tpush(player)\n\t\t\t\t\tdress(player)\n", ""),
    ("a product's prompt not logged", ECON, SHOP, 'promptClosed(Players:GetPlayerByUserId(userId), "ProductPrompt"',
     'print(Players:GetPlayerByUserId(userId), "ProductPrompt"'),
    ("a pass's prompt not logged", ECON, SHOP, '\t\tpromptClosed(player, "PassPrompt", item, bought)\n', ""),
    ("logged unguarded", ECON, SHOP, "\t\tpcall(function()\n\t\t\tAnalyticsService:LogCustomEvent(player, event,",
     "\t\t(function()\n\t\t\tAnalyticsService:LogCustomEvent(player, event,"),
    ("a name never declared", ECON, PARSE, "\tlocal unsure = {}\n", "\tlocal unsure = unsureList\n"),
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
