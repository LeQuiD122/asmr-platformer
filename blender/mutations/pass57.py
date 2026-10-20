"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 57: getting further keeps a level open (someone carried into a level and finishing it keeps it, and the ones
before the next, open), and a new player is told that finishing a level opens the next. Counting only the level
before; counting from the wrong place; the self-test expecting a lock for someone who got further; the welcome or
the guide not saying it.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUB = S / "Server/Services/HubService.lua"
ECON = S / "Server/Services/EconomyService.lua"
ONBOARD = S / "Client/Services/OnboardingService.lua"
HUBCHECK, SHOP, PARSE = "check_hub.py", "check_shop.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HUBCHECK, SHOP, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("only the level before", HUB, HUBCHECK, "\t\tif reached then\n\t\t\ttable.insert(keys, tostring(level.levelId))\n\t\tend\n",
     "\t\tif level.levelId == before.levelId then\n\t\t\ttable.insert(keys, tostring(level.levelId))\n\t\tend\n"),
    ("counted from the wrong place", HUB, HUBCHECK, "\t\tif level.levelId == before.levelId then\n\t\t\treached = true\n\t\tend\n",
     "\t\tif level.levelId == levelId then\n\t\t\treached = true\n\t\tend\n"),
    ("the self-test expects a lock", ECON, SHOP,
     "\t\t\t\tlocal theirs = EconomyService.finishedLevels(other)\n\t\t\t\tfor _, level in ipairs(LevelDefinitions.All) do\n"
     "\t\t\t\t\tif theirs and theirs[tostring(level.levelId)] == true then\n\t\t\t\t\t\tothers = true\n\t\t\t\t\tend\n\t\t\t\tend\n",
     "\t\t\t\tlocal theirs = if other ~= player then EconomyService.finishedLevels(other) else nil\n"
     "\t\t\t\tif theirs and theirs[key] == true then\n\t\t\t\t\tothers = true\n\t\t\t\tend\n"),
    ("the welcome not saying it", ONBOARD, SHOP, "to its end, and finishing one opens the next. In Chill", "to its end. In Chill"),
    ("the guide not saying it", ONBOARD, SHOP, "the first level. Finishing it opens the next.\" }", "the first level.\" }"),
    ("a name never declared", HUB, PARSE, "\t\t\tfor _, key in ipairs(keys) do\n", "\t\t\tfor _, key in ipairs(keyz) do\n"),
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
