"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 142: one notice at a time, never under a scene. A notice under a scene or held for ever; a second over the
first; the notices piling up; a challenge or a friend said over the ending or the black; the black not seen; Start
while a run is on answered late.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
VOTE = S / "Client/Services/HubVoteService.lua"
POLISH = "check_polish.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (POLISH,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a notice under a scene', VOTE, POLISH, 'while heldBack() and os.clock() - began < 90 do', 'while false do'),
    ('a notice held for ever', VOTE, POLISH, 'while heldBack() and os.clock() - began < 90 do', 'while heldBack() do'),
    ('a second notice over the first', VOTE, POLISH, '\t\ttask.wait(OPENED_FOR)\n\t\tnoticing = false', '\t\tnoticing = false'),
    ('the notices piling up', VOTE, POLISH, 'local NOTICES_KEPT = 4', 'local NOTICES_KEPT = 40'),
    ('a challenge done over the ending', VOTE, POLISH, 'HubVoteService.tell("+" .. reward, title,', 'HubVoteService.say("+" .. reward, title,'),
    ('a friend told over the black', VOTE, POLISH, 'HubVoteService.tell("+" .. percent .. "%", "Running with a friend",', 'HubVoteService.say("+" .. percent .. "%", "Running with a friend",'),
    ('the black not seen', VOTE, POLISH, '(ui ~= nil and type(ui.isBlack) == "function" and ui.isBlack())', 'false'),
    ('Start answered late', VOTE, POLISH, 'HubVoteService.say("WAIT", "A run is still on",', 'HubVoteService.tell("WAIT", "A run is still on",'),
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
