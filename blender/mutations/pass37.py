"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 37: the test panel's keepsakes and journal. A button missing, a button that does nothing, the journal
not emptied, 27 lines in the corner at once, and keepsakes without their words.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
DEV = S / "Client/Services/DevPanelClient.lua"
ECON = S / "Server/Services/EconomyService.lua"
INTER = S / "Server/Services/Interactables.lua"
STORY, PARSE = "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("no All keepsakes button", DEV, STORY, '\t{ action = "keepsakes", text = "All keepsakes" },\n', ""),
    ("no Clear journal button", DEV, STORY, '\t{ action = "journal", text = "Clear journal (rejoin)" },\n', ""),
    ("All keepsakes does nothing", ECON, STORY, '\telseif action == "keepsakes" then\n\t\ttask.spawn(giveAllKeepsakes, player)\n', ""),
    ("the journal not emptied", ECON, STORY, "\t\tdata.Journal = {}\n", ""),
    ("27 lines at once", ECON, STORY, "{ material = item.material, from = item.from }, true)",
     "{ material = item.material, from = item.from }, false)"),
    ("keepsakes without their words", INTER, STORY, ", line = entry.line, from = entry.from }", " }"),
    ("a name never declared", ECON, PARSE, "for _, item in ipairs(story.keepsakeList()) do",
     "for _, item in ipairs(stroy.keepsakeList()) do"),
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
