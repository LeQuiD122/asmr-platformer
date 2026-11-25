"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 167: in his hands. Never squared up; squared up into a wall; open floor not read from the rooms; your screen
not told how far; his old hold; his feet through the carpet; his elbows through the walls; his face away from yours; his
hold eased after him; you never set in his hands, or set in front of them; the shot of it in a wall, or from the side
with the wall.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ROOMS = S / "Server/Services/BackRoomsService.lua"
STALK = S / "Client/Services/StalkerClient.lua"
STORYC = S / "Client/Services/StoryClient.lua"
ROOMSCHECK = "check_backrooms.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (ROOMSCHECK,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('never squared up', ROOMS, ROOMSCHECK, '\t\t\tlocal spot = squaredUp(target.Position, here)\n', '\t\t\tlocal spot = nil\n'),
    ('squared up into a wall', ROOMS, ROOMSCHECK, 'if openLine(feet, spot) and (spot - him).Magnitude < nearest then', 'if (spot - him).Magnitude < nearest then'),
    ('open floor not read from the rooms', ROOMS, ROOMSCHECK, '\t\tif not walkable(x, y) then\n\t\t\treturn false', '\t\tif false then\n\t\t\treturn false'),
    ('your screen not told how far', ROOMS, ROOMSCHECK, 'model:SetAttribute("Grip", GRIP)', 'model:SetAttribute("Reach", GRIP)'),
    ('his old hold', STALK, ROOMSCHECK, 'local HOLD = { hips = 1.2, spine = 0.97, thigh = 0.69, knee = 1.35, shoulder = 0.43, shoulderYaw = 0.9, shoulderRoll = 0.76,\n\telbow = 1.9, elbowTwist = 0.87, neck = 0.6, head = 0.6 }', 'local HOLD = { hips = 0.7, spine = 0.7, thigh = 0.3, knee = 0.7, shoulder = 1.65, shoulderYaw = 0, shoulderRoll = 0.32,\n\telbow = 0.95, elbowTwist = 0, neck = 0, head = 0 }'),
    ('his feet through the carpet', STALK, ROOMSCHECK, 'local HOLD = { hips = 1.2,', 'local HOLD = { hips = 1.8,'),
    ('his elbows through the walls', STALK, ROOMSCHECK, 'shoulderYaw = 0.9, shoulderRoll = 0.76,', 'shoulderYaw = 0, shoulderRoll = 0.76,'),
    ('his face away from yours', STALK, ROOMSCHECK, 'neck = 0.6, head = 0.6 }', 'neck = 0, head = 0 }'),
    ('his hold eased after him', STALK, ROOMSCHECK, 'if one.grab == 0 then\n\t\t\tone.at = root.CFrame', 'if false then\n\t\t\tone.at = root.CFrame'),
    ('you never set in his hands', STORYC, ROOMSCHECK, '\tholdMe(character)\n', '\n'),
    ('you set in front of his hands', STORYC, ROOMSCHECK, '+ ahead.Unit * grip', '+ ahead.Unit * (grip + 2)'),
    ('the shot of it in a wall', STORYC, ROOMSCHECK, 'Cinema.point(CFrame.lookAt(Cinema.clear(want, mid, current.ignore), mid), 60 - 4 * k)', 'Cinema.point(CFrame.lookAt(want, mid), 60 - 4 * k)'),
    ('the shot of it from the side with the wall', STORYC, ROOMSCHECK, 'if math.max(left, right) >= 5 then', 'if true then'),
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
