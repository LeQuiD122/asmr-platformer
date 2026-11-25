"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 183: the daily chest. Never asked for, not turned as the old one, a broken one left half under the plain one, the lid on the bottom of its hasp.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUB = S / "Server/Services/HubService.lua"
VOTE = S / "Client/Services/HubVoteService.lua"
MADE = "check_made.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (MADE,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the made chest never asked for', HUB, MADE, 'local made = madeProp("DailyChest")', 'local made = nil'),
    ('laid unturned', HUB, MADE, 'copy.CFrame = face * part.CFrame', 'copy.CFrame = part.CFrame'),
    ('half under the plain one', HUB, MADE, 'if not body then\n\t\tmodel:ClearAllChildren()', 'if not body then'),
    ('the lid on its hasp', VOTE, MADE, 'local hinge = rest * (if typeof(at) == "Vector3" then CFrame.new(at) else CFrame.new(0, -lid.Size.Y / 2, lid.Size.Z / 2))', 'local hinge = rest * CFrame.new(0, -lid.Size.Y / 2, lid.Size.Z / 2)'),
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
