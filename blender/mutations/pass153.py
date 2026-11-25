"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 153: the butter, bare. The sticks wrapped again; raised over where you walk; the renderer driving a
wrapper; no curls; the wrapper's print borrowed back.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BUILDER = S / "Server/ChunkBuilder.server.lua"
PROPS = S / "Server/ChunkProps.server.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
FEEL = "check_feel.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (FEEL,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the sticks wrapped again', BUILDER, FEEL, 'local WAX_SHELLS: { [string]: { WaxSpec } } = {\n\tButterWax = {', 'local WAX_SHELLS: { [string]: { WaxSpec } } = {\n\tButterStick = {\n\t\t{ sizeX = 16, sizeZ = 12, surfaceOffset = 2.385, mesh = "Wax_Shell_Sticks_16x12_A" },\n\t},\n\tButterWax = {'),
    ('the sticks raised over the plane', BUILDER, FEEL, 'meshHeight = 7.34, surfaceOffset = 3.69,', 'meshHeight = 7.34, surfaceOffset = 3.39,'),
    ('the renderer drives a wrapper', RENDER, FEEL, 'BUTTER_STICK.SHELL = false', 'BUTTER_STICK.SHELL = true'),
    ('no curls', RENDER, FEEL, 'BUTTER_STICK.CURLS = 2', 'BUTTER_STICK.CURLS = 0'),
    ("the wrapper's print borrowed back", PROPS, FEEL, '\tP25_ButterStick = {},', '\tP25_ButterStick = {\n\t\ttextureFrom = "Butter_Stick",\n\t},'),
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
