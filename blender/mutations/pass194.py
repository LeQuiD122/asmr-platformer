"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 194: the serpent, dressed. No hide asked for, the hide over plastic, the hide never on, the old near-black tint, no
head asked for, the head at its made size, the head left at the middle of the body, pale eyes over its own, the head in
the way, the head looked for in the wrong place.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
SEA = S / "Client/Services/SunkenCityClient.lua"
MADE = "check_made.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (MADE,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('no hide asked for', SEA, MADE, 'local hide = game:GetService("MaterialService"):FindFirstChild(SERPENT.hide, true)', 'local hide = nil'),
    ('the hide over plastic', SEA, MADE, 'rig.part.Material = hide.BaseMaterial', 'rig.part.Material = Enum.Material.SmoothPlastic'),
    ('the hide never on', SEA, MADE, 'rig.part.MaterialVariant = hide.Name', 'rig.part.MaterialVariant = ""'),
    ('the old near-black tint', SEA, MADE, 'tint = Color3.fromRGB(150, 160, 170)', 'tint = Color3.fromRGB(28, 40, 48)'),
    ('no head asked for', SEA, MADE, 'local made = madeSea(SERPENT.head)', 'local made = nil'),
    ('the head at its made size', SEA, MADE, 'piece.Size = made.Size * (rig.part.Size.X * SERPENT.width / made.Size.X)', 'piece.Size = made.Size'),
    ('the head left mid-body', SEA, MADE, 'table.insert(eyeRest, segment * CFrame.new(0, 0, -SERPENT.forward))', 'table.insert(eyeRest, CFrame.new(0, 0, -SERPENT.forward))'),
    ('pale eyes over its own', SEA, MADE, 'for _, side in ipairs(if made then {} else { -1, 1 }) do', 'for _, side in ipairs({ -1, 1 }) do'),
    ('the head in the way', SEA, MADE, 'piece.CanCollide = false', 'piece.CanCollide = true'),
    ('looked for elsewhere', SEA, MADE, 'local props = assets and assets:FindFirstChild("Props")', 'local props = assets and assets:FindFirstChild("TileMeshes")'),
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
