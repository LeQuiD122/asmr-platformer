"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 61: the move between a story's levels. Two moves at once; never marked, or never unmarked; the kill plane
taking a held player for a fall; not hidden; left black; players falling through the gap, or left frozen; a leaver
kept; and the dive's blackout back (the gate it used to have, narrowed to the dive now that the story fades).
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
CHECK, PARSE = "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("two moves at once", BOOT, CHECK, "if storyRun ~= run or run.moving then", "if storyRun ~= run then"),
    ("never marked", BOOT, CHECK, "\trun.moving = true\n", ""),
    ("never unmarked", BOOT, CHECK, "\trun.moving = false\n", ""),
    ("held players fall", BOOT, CHECK, "\t\t\tstoryMoving[player] = true\n", ""),
    ("the kill plane takes them", BOOT, CHECK, "\t\tif storyMoving[player] then\n\t\t\tcontinue\n\t\tend\n", ""),
    ("not hidden", BOOT, CHECK, "\t\t\tScreenFade:FireClient(player, { black = true, time = STORY_FADE })\n", ""),
    ("left black", BOOT, CHECK, "\t\t\tScreenFade:FireClient(player, { black = false, time = STORY_FADE })\n", ""),
    ("through the gap", BOOT, CHECK, "\t\t\t\troot.Anchored = true\n", ""),
    ("left frozen", BOOT, CHECK, "\tfor _, root in ipairs(held) do\n\t\troot.Anchored = false\n\tend\n", ""),
    ("a leaver kept", BOOT, CHECK, "\tstoryLeave(player)\n\tstoryMoving[player] = nil\n", "\tstoryLeave(player)\n"),
    ("the dive's blackout back", BOOT, CHECK,
     "\t\t\t\t\t\t-- the move between its levels (storyNext).\n\t\t\t\t\t\tif finishRunFor then\n",
     "\t\t\t\t\t\t-- the move between its levels (storyNext).\n\t\t\t\t\t\tScreenFade:FireClient(player, { black = true })\n"
     "\t\t\t\t\t\tif finishRunFor then\n"),
    ("a name never declared", BOOT, PARSE, "\t\t\tstoryMoving[player] = true\n", "\t\t\tstoryMovng[player] = true\n"),
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
