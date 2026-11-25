"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 155: the keyboards, key by key. A creamy board rigged again; a key's letter upside down; a key not filling
its cell; a board never coloured; colourways short; the keys over lava painted creamy; every placed board alike; a key that
never springs; no weight on the keys round it; the cap's mesh off its cell.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
APPEAR = S / "Shared/MaterialAppearance.lua"
BUILDER = S / "Server/ChunkBuilder.server.lua"
CHUNKSV = S / "Server/Services/ChunkService.lua"
KEYGEN = ROOT / "blender/gen_keycap.py"
RENDER = S / "Client/Services/DeformationRenderer.lua"
FEEL = "check_feel.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (FEEL,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the creamy boards rigged again', BUILDER, FEEL, 'local KEYED: { [string]: boolean } = { CreamyKeyboard = true, LavaKeys = true }', 'local KEYED: { [string]: boolean } = { LavaKeys = true }'),
    ("a key's letter upside down", BUILDER, FEEL, 'cap.CFrame = tile.CFrame * CFrame.Angles(0, math.pi, 0)', 'cap.CFrame = tile.CFrame'),
    ('a key not filling its cell', BUILDER, FEEL, 'cap.Size = tile.Size', 'cap.Size = tile.Size * Vector3.new(0.8, 1, 0.8)'),
    ('a board never coloured', BUILDER, FEEL, '\t\tMaterialAppearance.paintKeys(slab, nil)\n', ''),
    ('colourways short', APPEAR, FEEL, 'MaterialAppearance.CREAMY_WAYS = { "StrawberryMilk", "Dusk", "Mint", "PeachSoda",', 'MaterialAppearance.CREAMY_WAYS = { "StrawberryMilk",'),
    ('the keys over lava painted creamy', APPEAR, FEEL, 'if material == "LavaKeys" then "Lava" else way or', 'if material == "LavaKeysX" then "Lava" else way or'),
    ('every placed board alike', CHUNKSV, FEEL, '\t\tMaterialAppearance.paintKeys(clone, nil)\n', ''),
    ('a key never springs back', RENDER, FEEL, 'UP = TweenInfo.new(0.26, Enum.EasingStyle.Back', 'UP = TweenInfo.new(0.26, Enum.EasingStyle.Quint'),
    ('no weight on the keys round it', RENDER, FEEL, 'for _, other in ipairs(Keys.around(tile)) do', 'for _, other in ipairs({}) do'),
    ("the cap's mesh off its cell", KEYGEN, FEEL, 'BASE = 3.05', 'BASE = 2.8'),
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
