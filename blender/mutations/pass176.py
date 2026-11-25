"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 176: the squish room like the lobby, and never a chunk. A sample dressed; a chunk told by nothing; the room
never dressed; the floor plastic; the walls not rendered; a lift's side left plastic; the slab not marked.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
APPEAR = S / "Shared/MaterialAppearance.lua"
BUILDER = S / "Server/ChunkBuilder.server.lua"
SQUISHS = S / "Server/Services/SquishRoomService.lua"
SURF = "check_surfaces.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SURF,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a sample dressed', APPEAR, SURF, '\t\tif chunkPart(item) then\n\t\t\treturn\n\t\tend\n', ''),
    ('a chunk told by nothing', APPEAR, SURF, 'if at:GetAttribute("Material") ~= nil then', 'if at:GetAttribute("Chunk") ~= nil then'),
    ('the room never dressed', SQUISHS, SURF, '\tlocal dressOk, dressErr = pcall(MaterialAppearance.dress, folder)\n', '\tlocal dressOk, dressErr = true, nil\n'),
    ('the floor plastic', SQUISHS, SURF, '(z0 + z1) / 2), PALETTE.floor, true, BOARDS)', '(z0 + z1) / 2), PALETTE.floor, true)'),
    ('the walls not rendered', SQUISHS, SURF, 'local RENDER = Enum.Material.Plaster', 'local RENDER = Enum.Material.SmoothPlastic'),
    ("a lift's side left plastic", SQUISHS, SURF, 'part(cabin, "LiftSide", Vector3.new(0.4, 10, 7), at(3.3, 5.4, 0), PALETTE.cabin, true, IRON)', 'part(cabin, "LiftSide", Vector3.new(0.4, 10, 7), at(3.3, 5.4, 0), PALETTE.cabin, true)'),
    ('the slab not marked', BUILDER, SURF, 'slab:SetAttribute("Material", materialName)', 'slab:SetAttribute("MaterialName", materialName)'),
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
