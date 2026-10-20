"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 54: a level the run opened, told on coming back to the lobby. Not kept when leaving; not told, or told twice;
announcing a level that was open already; never sent; the notifier fixed to "locked"; the banner never saying it,
wiping it at once, making no sound, or keeping it up for good; a countdown from before the run coming back.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUB = S / "Server/Services/HubService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
BANNER = S / "Client/Services/HubVoteService.lua"
CHECK, PARSE = "check_hub.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("not kept when leaving", HUB, CHECK, "\t\topenWhenLeft[player] = openWhenLeft[player] or HubService.openNow()\n", ""),
    ("not told", HUB, CHECK, "\tif wasOpen then\n\t\tHubService.tellOpened(player, wasOpen)\n\tend\n", ""),
    ("told twice", HUB, CHECK, "\topenWhenLeft[player] = nil\n\tif wasOpen then", "\tif wasOpen then"),
    ("an open level announced", HUB, CHECK, "before[level.levelId] == false and HubService.isOpen(level.levelId)",
     "HubService.isOpen(level.levelId)"),
    ("never sent", HUB, CHECK, 'pcall(notify :: any, player, "opened", { names = names })', "true, nil"),
    ("the notifier fixed to locked", BOOT, CHECK,
     "payload: any)\n\tHubVoteState:FireClient(player, kind, payload)\nend)\n",
     'payload: any)\n\tHubVoteState:FireClient(player, "locked", payload)\nend)\n'),
    ("the banner never says it", BANNER, CHECK, '\t\telseif kind == "opened" then\n\t\t\tHubVoteService.onOpened(payload)\n', ""),
    ("wiped at once", BANNER, CHECK, "\tlockedUntil = os.clock() + OPENED_FOR\n", "\tlockedUntil = os.clock()\n"),
    ("no sound", BANNER, CHECK, "\tHubVoteService.say(\"NEW\", title, body)\n\ttock(2)\n", "\tHubVoteService.say(\"NEW\", title, body)\n"),
    ("not held", BANNER, CHECK, '\tHubVoteService.say("NEW", title, body)\n', ""),
    ("up for good", BANNER, CHECK, "\t\telseif state then\n\t\t\tHubVoteService.onIdle(state)\n\t\telse\n\t\t\tshow(false)\n\t\tend\n",
     "\t\telseif state then\n\t\t\tHubVoteService.onIdle(state)\n\t\tend\n"),
    ("an old countdown back", BANNER, CHECK,
     '\tlockedUntil = 0\n\t-- The ballot is over: nothing from it is shown again after a held message (a stale countdown would be).\n'
     '\tlastState, lastKind = nil, "idle"\n', "\tlockedUntil = 0\n"),
    ("a name never declared", HUB, PARSE, "openWhenLeft[player] = openWhenLeft[player] or HubService.openNow()",
     "openWhenLeft[player] = openWhenLeft[playr] or HubService.openNow()"),
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
