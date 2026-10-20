"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 87: the fall into the mouth, in the dark. The shaft lit as you are shot out; the dark not put back before
the chamber, or left on when the scene ends; the air not made black; the water off the lip a lit column; you not
seen in the dark; the mouth not coming for you, not waiting deep, or not lunging; its beats out of order; the shot of
the bite against the mast or down among the jaws; its lights shining through its jaws; the mouth unable to move;
the water falling all the way down the shaft; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HC = S / "Client/Services/FloodedHallsClient.lua"
HS = S / "Server/Services/FloodedHallsService.lua"
MAW = S / "Client/Services/Maw.lua"
HALLS, PARSE = "check_halls.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HALLS, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the shaft lit as you are shot out', HC, HALLS, '\t\t\t\tdarken(current, root)\n', ''),
    ('the dark not put back for the chamber', HC, HALLS, '\trelight(current)\n\tchamberStep(', '\tchamberStep('),
    ('the dark left on', HC, HALLS, '\tholdMine(nil)\n\trelight(current)\n', '\tholdMine(nil)\n'),
    ('the air not black', HC, HALLS, 'DARK.airAtMost), Color = DARK.colour, Decay = DARK.colour,', 'DARK.airAtMost), Color = Color3.new(1, 1, 1), Decay = DARK.colour,'),
    ('the pour a lit column', HC, HALLS, '\t\tpour.Enabled = false\n', ''),
    ('you unseen in the dark', HC, HALLS, 'glimmer.Brightness = 1.2', 'glimmer.Brightness = 0'),
    ('the mouth not coming for you', HC, HALLS, 'Maw.place(mouth, rest + Vector3.new(0, MAW_RISE * lunge, 0))', 'Maw.place(mouth, rest)'),
    ('the mouth not waiting deep', HC, HALLS, 'Maw.facing(from - Vector3.new(0, MAW_DEEP, 0)', 'Maw.facing(from - Vector3.new(0, 20, 0)'),
    ('no lunge', HC, HALLS, 'local MAW_DEEP, MAW_RISE, LUNGE = 116, 34, 0.55', 'local MAW_DEEP, MAW_RISE, LUNGE = 116, 4, 0.55'),
    ('the beats out of order', HC, HALLS, '\tbite = 3.5,', '\tbite = 2.0,'),
    ('the bite shot against the mast', HC, HALLS, 'opens * 55 + inward * 24 + side * 14, hinge.Position', 'opens * 55 + inward * 36 + side * 2, hinge.Position'),
    ('the bite shot among the jaws', HC, HALLS, 'opens * 55 + inward * 24 + side * 14, hinge.Position', 'opens * 30 + inward * 24 + side * 14, hinge.Position'),
    ('lit before it opens', HC, HALLS, '\tif m < JAWS.reveal then\n\t\tMaw.light(mouth, 0)\n', '\tif m < JAWS.reveal then\n\t\tMaw.light(mouth, 1)\n'),
    ('the glow through the jaws', MAW, HALLS, 'glow.Shadows = true', 'glow.Shadows = false'),
    ('the throat through the jaws', MAW, HALLS, 'gullet.Shadows = true', 'gullet.Shadows = false'),
    ('the mouth unable to move', MAW, HALLS, 'function Maw.place(built: Built, hinge: CFrame)', 'function Maw.put(built: Built, hinge: CFrame)'),
    ('the water down the whole shaft', HS, HALLS, 'pour.Lifetime = NumberRange.new(0.6, 0.9)', 'pour.Lifetime = NumberRange.new(3, 4)'),
    ('a name never declared', HC, PARSE, 'glimmer.Brightness = 1.2', 'glimmers.Brightness = 1.2'),
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
