"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 182: the lobby's lights and arrows. The start pad Neon, its inlay solid or its lamp bright; the chosen ring a disc or its lamps bright; the arrows back on the plaza (199: none there now); the walk's in its planks.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HUB = S / "Server/Services/HubService.lua"
LETGO = "check_letgo.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (LETGO,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the start pad Neon', HUB, LETGO, 'startPad.Material = Enum.Material.SmoothPlastic', 'startPad.Material = Enum.Material.Neon'),
    ('its inlay solid', HUB, LETGO, 'startInlay.Transparency = 0.62', 'startInlay.Transparency = 0.1'),
    ('its lamp bright', HUB, LETGO, 'startLamp.Brightness = 0.6', 'startLamp.Brightness = 2'),
    ('the chosen ring a disc', HUB, LETGO, 'part.Transparency = if on then 0.55 else 1', 'part.Transparency = if on then 0.1 else 1'),
    ("the ring's lamp bright", HUB, LETGO, '\t\tglow.Brightness = 0.75\n\t\tglow.Range = 12', '\t\tglow.Brightness = 1.6\n\t\tglow.Range = 18'),
    ("the ring's beam bright", HUB, LETGO, '\t\tbeam.Range = 10\n\t\tbeam.Brightness = 0.5', '\t\tbeam.Range = 14\n\t\tbeam.Brightness = 1.2'),
    # (199: the plaza's run is gone, so its two rows here are one: the run put back under the spawn's camera.)
    ("arrows back on the plaza", HUB, LETGO, 'for _, run in ipairs({ { z = gatesWalk.Z + 8, y = 1.09, count = 5 } }) do',
     'for _, run in ipairs({ { z = AT.spawn.Z - 7.6, y = 1.415, count = 3 }, { z = gatesWalk.Z + 8, y = 1.09, count = 5 } }) do'),
    ("the walk's arrows in its planks", HUB, LETGO, '{ z = gatesWalk.Z + 8, y = 1.09, count = 5 }', '{ z = gatesWalk.Z + 8, y = 1.04, count = 5 }'),
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
