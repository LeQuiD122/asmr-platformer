"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 206: the chunks' feel, from your note of 2026-11-07. Bubble wrap and foam never giving way, or giving way under a
walker, or their holes slow to fill; foam's cell left where it was with no floor under it, or turned inside out; the
light switches a rubber plate again, never given rockers, a rocker resting level, its pilot light left behind, a rocker
that collides, one not pressed where you stand, one that does not tip whole.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CONFIG = S / "Shared/MaterialConfig.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
BUILDER = S / "Server/ChunkBuilder.server.lua"
FEEL = "check_feel.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


if run(FEEL).returncode != 0:
    sys.exit("%s fails before anything is mutated; fix that first" % FEEL)

MUTATIONS = [
    ('bubble wrap never giving way', CONFIG, FEEL, 'whole again six seconds later.\n\t\tcrumbleAfter = 1.6,\n',
     'whole again six seconds later.\n'),
    ('bubble wrap giving way under a walker', CONFIG, FEEL, 'whole again six seconds later.\n\t\tcrumbleAfter = 1.6,\n',
     'whole again six seconds later.\n\t\tcrumbleAfter = 0.4,\n'),
    ('foam never giving way', CONFIG, FEEL, '\t\tcrumbleAfter = 2.0,\n', ''),
    ("foam's holes slow to fill", CONFIG, FEEL, '\t\tcrumbleAfter = 2.0,\n\t\tregrowAfter = 6,\n',
     '\t\tcrumbleAfter = 2.0,\n\t\tregrowAfter = 20,\n'),
    ("foam's cell left with no floor under it", RENDER, FEEL,
     '\t\t\tsetResidual(tile, bone, give, -NEW_MATS.Foam.drop)\n', '\t\t\tsetResidual(tile, bone, give, 0)\n'),
    ('foam turned inside out', RENDER, FEEL, 'tick = 0.1, drop = 2.9,', 'tick = 0.1, drop = 4.5,'),
    ('the switches a rubber plate again', BUILDER, FEEL,
     '\t-- (No LightSwitch rig since the two-hundred-and-fifth pass',
     '\tLightSwitch = {\n\t\t{ sizeX = 16, sizeZ = 12, mesh = "LightSwitch_Platform_16x12" },\n\t},\n\t-- (No LightSwitch rig since the two-hundred-and-fifth pass'),
    ('the switches never given rockers', BUILDER, FEEL, '\t\t\tif ROCKED[materialName] then\n\t\t\t\tattachRocker(tile, materialName)\n',
     '\t\t\tif ROCKED[materialName] then\n\t\t\t\tlocal _ = tile\n'),
    ('a rocker resting level', BUILDER, FEEL,
     'pivot * CFrame.Angles(-ROCKER.TILT, 0, 0) * CFrame.new(0, ROCKER.THICK / 2 - ROCKER.SINK, 0))',
     'pivot * CFrame.new(0, ROCKER.THICK / 2 - ROCKER.SINK, 0))'),
    ("a rocker's pilot light left behind", BUILDER, FEEL, '\tpilot:SetAttribute("Offset", onPaddle)\n', ''),
    # (Since the two-hundred-and-eighth pass a rocker is under your foot: the fault now is one you walk through.)
    ('a rocker you walk through', BUILDER, FEEL, '\tpaddle.CanCollide = true\n', '\tpaddle.CanCollide = false\n'),
    ('a rocker thrown by the half already down', RENDER, FEEL,
     'if near ~= far and (switchOn[tile] == true) ~= far then', 'if near ~= far then'),
    ('a rocker that does not tip whole', RENDER, FEEL,
     'local goal = (pivot :: CFrame) * CFrame.Angles(if on then tilt else -tilt, 0, 0) * CFrame.new(0, rise, 0)',
     'local goal = (pivot :: CFrame) * CFrame.new(0, if on then -0.3 else 0, 0)'),
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
