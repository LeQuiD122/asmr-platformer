"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 59: one run at a time. Nothing knowing a run is on; a vote, a run or the Start pad going ahead while one is;
the Start pad not saying why; saying it every frame; never sending it; keeping it after leaving; the card never
showing it.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUB = S / "Server/Services/HubService.lua"
BANNER = S / "Client/Services/HubVoteService.lua"
CHECK, PARSE = "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("nothing knows", HUB, CHECK, "\treturn next(inRun) ~= nil\n", "\treturn false\n"),
    ("a vote while a run is on", HUB, CHECK, "\t-- NOT WHILE A RUN IS ON (runOn).\n\tif HubService.runOn() then\n\t\treturn\n\tend\n",
     "\t-- NOT WHILE A RUN IS ON (runOn).\n"),
    ("a run over a run", HUB, CHECK,
     '\tif HubService.runOn() then\n\t\twarn("HubService: a run is still on, so this one does not start.")',
     '\tif false then\n\t\twarn("HubService: a run is still on, so this one does not start.")'),
    ("Start goes ahead", HUB, CHECK,
     "\t\t-- NOT WHILE A RUN IS ON (runOn): whoever stepped on it is told why.\n\t\tif HubService.runOn() then\n",
     "\t\t-- NOT WHILE A RUN IS ON (runOn): whoever stepped on it is told why.\n\t\tif false then\n"),
    ("Start says nothing", HUB, CHECK, "\t\t\t\tHubService.tellBusy(stepped)\n", ""),
    ("said every frame", HUB, CHECK, "if last and os.clock() - last < LOCK_TELL_GAP then", "if false then"),
    ("never sent", HUB, CHECK, 'pcall(notify :: any, player, "busy", { playing = playing })', "true, nil"),
    ("kept after leaving", HUB, CHECK, "\tbusyTold[player] = nil\n", ""),
    ("the card never shows it", BANNER, CHECK, '\t\telseif kind == "busy" then\n\t\t\tHubVoteService.onBusy(payload)\n', ""),
    ("a name never declared", HUB, PARSE, "\tbusyTold[player] = os.clock()\n", "\tbusyTold[playr] = os.clock()\n"),
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
