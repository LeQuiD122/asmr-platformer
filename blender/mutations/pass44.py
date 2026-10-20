"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 44: the self-test, wider. A second chance not tried twice, a note it should ignore not tried, its notes left
counted against the player, a wait while the save is changed, the kept leaderboard not timed.
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
    ("a second chance not tried twice", ECON, SHOP, "local second = EconomyService.spendChance(player)", "local second = false"),
    ("an ignored note not tried", ECON, SHOP, 'onNote(player, "Tokens", 999)', 'onNote(player, "favourite", 999)'),
    ("its notes counted against the player", ECON, SHOP, "\tlastNote[player] = realNote\n", ""),
    ("a wait while the save is changed", ECON, SHOP, "\t\tlocal tokens = data.Tokens\n",
     "\t\tlocal tokens = data.Tokens\n\t\ttask.wait()\n"),
    ("the kept board not timed", ECON, SHOP, "againOk and took < 0.05", "againOk"),
    ("a name never declared", ECON, PARSE, "local realNote = lastNote[player]", "local realNote = lastNotes[player]"),
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
