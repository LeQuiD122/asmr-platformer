"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 202: the serpent rolled through its turns (seen in play: a flat striped web across the loop). No roll, the roll
not laid on the bone, the across ignored, banking on the straights, across along the street not over it, the serpent
posed without its across, its across left in the world's space; the crest one plate again, or in long pieces.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
RIG = S / "Shared/SeaRig.lua"
PATH = S / "Shared/SunkenPath.lua"
CLIENT = S / "Client/Services/SunkenCityClient.lua"
SERPGEN = ROOT / "blender/gen_serpent.py"
LETGO = "check_letgo.py"
SUNK = "check_sunkencity.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (LETGO, SUNK):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('no roll', RIG, LETGO, 'local up = Vector3.yAxis - b * b.Y + across * math.abs(b.Y)', 'local up = Vector3.yAxis - b * b.Y'),
    ('the roll not laid on the bone', RIG, LETGO, 'return frameAlong(b, up) * frameAlong(a, Vector3.yAxis):Inverse()',
     'return frameAlong(b, up)'),
    ('the across ignored', RIG, LETGO, 'turn = rolled(from.Unit, to.Unit, across[index] or Vector3.zero)',
     'turn = rolled(from.Unit, to.Unit, Vector3.zero)'),
    ('banking on the straights', PATH, LETGO, '\t\tif lean ~= 0 then\n\t\t\tlocal _, dir = SunkenPath.walk(b, s)',
     '\t\tif true then\n\t\t\tlocal _, dir = SunkenPath.walk(b, s)'),
    ('across along the street', PATH, LETGO, 'out[index] = Vector3.new(-dir.Z, 0, dir.X)', 'out[index] = dir'),
    ('posed without its across', CLIENT, LETGO, 'SeaRig.follow(mesh.chain, mesh.rig.rest, joints, true, mesh.posed, mesh.across)',
     'SeaRig.follow(mesh.chain, mesh.rig.rest, joints, true, mesh.posed)'),
    ("its across left in the world's space", CLIENT, LETGO, 'mesh.across[index] = frame:VectorToObjectSpace(acrossWorld[index])',
     'mesh.across[index] = acrossWorld[index]'),
    ('the crest one plate again', SERPGEN, SUNK, '    half = 0.15   # 0.3 thick, as the plate was\n',
     '    half = 0.15   # 0.3 thick, as the plate was\n    G.plate(bm, [(0, 0, 0), (0, 1, 0), (0, 0, 1)], (1, 0, 0), 0.3)\n'),
    ('the crest in long pieces', SERPGEN, SUNK, 'CREST_STEP = 1.4     #', 'CREST_STEP = 40.0    #'),
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
