"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 51: levels open in order. The first level not always open; opened without the one before finished; a locked
level taking a vote or winning one; boards left up, floating, or the window not dimmed; a locked pad telling you
every frame; a vote left on a level that locked again; a finish not kept, not loaded, not let go, or not saying
which level; the lobby not reading saves; the banner never saying so, or wiping it at once; no test button; the
self-test not checking a too-fast run.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUB = S / "Server/Services/HubService.lua"
ECON = S / "Server/Services/EconomyService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
BANNER = S / "Client/Services/HubVoteService.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
CHECK, PARSE = "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the first level not always open", HUB, CHECK, "if before == nil or reader == nil then\n\t\treturn true",
     "if reader == nil then\n\t\treturn true"),
    ("opened without the one before", HUB, CHECK, "finished[key] == true", "finished[key] ~= nil"),
    ("a locked level takes a vote", HUB, CHECK,
     "\t\tif not HubService.isOpen(value :: number) then\n\t\t\tHubService.tellLocked(player, value :: number)\n\t\t\treturn\n\t\tend\n",
     ""),
    ("a locked level wins", HUB, CHECK, "if HubService.isOpen(level.levelId) then\n\t\t\ttable.insert(levelOrder, level.levelId)",
     "if level.levelId then\n\t\t\ttable.insert(levelOrder, level.levelId)"),
    ("boards left up", HUB, CHECK, "board.Transparency = if open then 1 else 0", "board.Transparency = 0"),
    ("boards floating", HUB, CHECK, "window.Size.Z / 2 + 0.15", "window.Size.Z / 2 + 0.6"),
    ("window not dimmed", HUB, CHECK, "clear = 0.8 -- dim behind the boards", "clear = 0.45"),
    ("told every frame", HUB, CHECK, "os.clock() - told.at < LOCK_TELL_GAP then", "os.clock() - told.at < 0 then"),
    ("a vote left on a locked level", HUB, CHECK, "ballot.levelId = first.levelId", "ballot.levelId = ballot.levelId"),
    ("a finish not kept", ECON, CHECK, "finished[tostring(levelId)] = true\n\t\ttellLevels()", "tellLevels()"),
    ("a save loading opens nothing", ECON, CHECK,
     "\tdress(player)\n\t-- Whatever they have finished opens in the lobby for everyone here.\n\ttellLevels()\nend",
     "\tdress(player)\nend"),
    ("leaving locks nothing again", ECON, CHECK,
     "\t-- What they had opened closes again unless someone still here has finished it too.\n\ttellLevels()\n", ""),
    ("a finish not saying its level", BOOT, CHECK, "hardcore and newBest == true, finishedId)", "hardcore and newBest == true)"),
    ("the lobby not reading saves", BOOT, CHECK, "\tHubService.setFinishedReader(EconomyService.finishedLevels)\n", ""),
    ("the banner never says locked", BANNER, CHECK, '\t\telseif kind == "locked" then\n\t\t\tHubVoteService.onLocked(payload)\n', ""),
    ("the message wiped at once", BANNER, CHECK,
     'lastState, lastKind = state, "idle"\n\tif os.clock() < lockedUntil then\n\t\treturn\n\tend\n',
     'lastState, lastKind = state, "idle"\n'),
    ("no test button", DEV, CHECK, '\t{ action = "levels", text = "Levels open/locked" },\n', ""),
    ("the self-test not checking", ECON, CHECK,
     '\t\tcheck("a run finished at once opens no level", finishedOf(data)["1"] == wasFinished)\n', ""),
    ("a name never declared", HUB, PARSE, "if level.levelId == before.levelId then\n\t\t\treached = true",
     "if level.levelId == befor.levelId then\n\t\t\treached = true"),
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
