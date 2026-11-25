"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 156: the keys over lava. Safe again; no lava under the keys; the lava a floor; the keys in Neon; a key
that never sinks; the keys' bob fighting a press; the pool that never flows.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
APPEAR = S / "Shared/MaterialAppearance.lua"
BUILDER = S / "Server/ChunkBuilder.server.lua"
MATS = S / "Shared/MaterialConfig.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
FEEL = "check_feel.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (FEEL,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the keys over lava safe again', MATS, FEEL, 'LavaKeys = {\n\t\tcategory = "risk",', 'LavaKeys = {\n\t\tcategory = "pace",'),
    ('no lava under the keys', BUILDER, FEEL, '\tpool.Name = "LavaPool"\n', '\tpool.Name = "LavaBlock"\n'),
    ('the lava a floor', BUILDER, FEEL, '\tpool.CanCollide = false\n', '\tpool.CanCollide = true\n'),
    ('the keys over lava in Neon', APPEAR, FEEL, '\tLavaKeys = {\n\t\tcolor = Color3.fromRGB(46, 40, 38),\n\t\tmaterial = Enum.Material.Basalt,', '\tLavaKeys = {\n\t\tcolor = Color3.fromRGB(46, 40, 38),\n\t\tmaterial = Enum.Material.Neon,'),
    ('a key over lava never sinks', RENDER, FEEL, 'Enum.EasingDirection.In), -Keys.SINK)', 'Enum.EasingDirection.In), 0)'),
    ('the bob fighting a press', RENDER, FEEL, 'if cap.Parent and not cap:GetAttribute("KeyHeld") then', 'if cap.Parent then'),
    ('the pool never flows', RENDER, FEEL, 'skinTexture.OffsetStudsU = (now * 0.35) % 7', 'skinTexture.OffsetStudsU = 0'),
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
