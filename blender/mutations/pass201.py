"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 201: the chunks' own surfaces, laid without a repeat, and a made stall for the shop. Soap blank again, the Needoh
bare, no stable surface, stable's never worn; the cast stone square, the sea wall wandering, nothing laid Organic;
blocks where the stall is made, a box round its awning, its back to the room, the block counter showing through, a
giant stall, no kiosk at all without it, the lamp left in the old place.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
APPEAR = S / "Shared/MaterialAppearance.lua"
HUB = S / "Server/Services/HubService.lua"
MADE = "check_made.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (MADE,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('soap blank again', APPEAR, MADE, 'Soap = "ChunkSoap",', 'Soap = "",'),
    ('the Needoh bare', APPEAR, MADE, '\tNeedoh = "ChunkNeedoh",\n', ''),
    ('no stable surface', APPEAR, MADE, '\tstable = "ChunkStable",\n', ''),
    ("stable's never worn", APPEAR, MADE, 'applyPartVariant(part, materialName or "stable")', 'applyPartVariant(part, materialName)'),
    ('the cast stone square', APPEAR, MADE, 'MaterialAppearance.ORGANIC = { "HarrowCast", "HarrowRender", "HarrowMarble", "HarrowPaint" }',
     'MaterialAppearance.ORGANIC = { "HarrowRender", "HarrowMarble", "HarrowPaint" }'),
    ('the sea wall wandering', APPEAR, MADE, 'MaterialAppearance.ORGANIC = { "HarrowCast", "HarrowRender", "HarrowMarble", "HarrowPaint" }',
     'MaterialAppearance.ORGANIC = { "HarrowCast", "HarrowRender", "HarrowMarble", "HarrowPaint", "HarrowStone" }'),
    ('nothing laid Organic', APPEAR, MADE, '\tlayOrganic(MaterialService)\n', ''),
    ('blocks where the stall is made', HUB, MADE, 'local stallMade = madeProp("Shop_Stall")', 'local stallMade = madeProp("Shop_Stand")'),
    ('a box round its awning', HUB, MADE, '\t\tstall.CanCollide = false\n', '\t\tstall.CanCollide = true\n'),
    ('its back to the room', HUB, MADE, 'stall.Size.Y / 2, 0)) * CFrame.Angles(0, -math.pi / 2, 0)',
     'stall.Size.Y / 2, 0)) * CFrame.Angles(0, math.pi / 2, 0)'),
    ('the block counter showing through', HUB, MADE, '\t\tcounter.Transparency = 1\n', '\t\tcounter.Transparency = 0\n'),
    ('a giant stall', HUB, MADE, 'local KIOSK_STALL = { long = 8.4, x = 0.6 }', 'local KIOSK_STALL = { long = 20, x = 0.6 }'),
    ('no kiosk at all without it', HUB, MADE, '\t\t\tpiece("KioskAwning",', '\t\t\tpiece("KioskRoof",'),
    ('the lamp left in the old place', HUB, MADE, 'Vector3.new(0.6, 0.3, 0.6), lampAt, teal)',
     'Vector3.new(0.6, 0.3, 0.6), Vector3.new(0.6, 8.85, 0), teal)'),
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
