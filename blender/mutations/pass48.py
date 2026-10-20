"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 48: the collection in the player list. The wrong folder (so Roblox shows nothing), more than keepsakes
counted, not shown on joining, not raised on picking one up, wrong after the self-test.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ECON = S / "Server/Services/EconomyService.lua"
STORY, PARSE = "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the wrong folder", ECON, STORY, 'stats.Name = "leaderstats"', 'stats.Name = "Leaderstats"'),
    ("more than keepsakes counted", ECON, STORY, 'if kept.kind == "keepsake" then\n\t\t\tcount += 1',
     "if kept.kind then\n\t\t\tcount += 1"),
    ("not shown on joining", ECON, STORY, "\tshowCollection(player)\n\tif not ready.Data.Welcomed then",
     "\tif not ready.Data.Welcomed then"),
    ("not raised on a pickup", ECON, STORY, '\tif kept.kind == "keepsake" then\n\t\tshowCollection(player)\n\tend\n', ""),
    ("wrong after the self-test", ECON, STORY, "\tlastNote[player] = realNote\n\tshowCollection(player)\n",
     "\tlastNote[player] = realNote\n"),
    ("a name never declared", ECON, PARSE, "local counter = value :: IntValue", "local counter = valu :: IntValue"),
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
