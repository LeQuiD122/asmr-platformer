"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 134, from your test: the halls' galleries, signs and hanging lamps. No galleries; one hanging in the air; no
railing; one through an arch; up across the windows; the hanging lamps lit behind you; the signs not in the town's
print.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HC = S / "Client/Services/FloodedHallsClient.lua"
HS = S / "Server/Services/FloodedHallsService.lua"
HALLS = "check_halls.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HALLS,):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('no galleries', HS, HALLS, 'local function buildGallery(halls: Model, leg: HallRoute.Leg, along: number, length: number, side: number)', 'local function buildGallery(halls: Model, leg: HallRoute.Leg, along: number, length: number, side: number?)'),
    ('a gallery hanging in the air', HS, HALLS, 'fitting(halls, "GalleryStrut", Vector3.new(0.6, 0.6, long), cf, IRON, Enum.Material.Metal)', 'local _ = cf'),
    ('no railing', HS, HALLS, 'fitting(halls, "GalleryBaluster"', 'fitting(halls, "GalleryPost"'),
    ('a gallery through an arch', HS, HALLS, 'buildGallery(halls, leg, along - (bayHalf + gap) / 2, bayHalf - gap, side)', 'buildGallery(halls, leg, along, bayHalf * 2, side)'),
    ('galleries across the windows', HS, HALLS, 'local GALLERY_Y = 42', 'local GALLERY_Y = 52'),
    ('the hanging lamps lit behind you', HC, HALLS, '(item.Name == "RoofLight" or item.Name == "PendantLight")', '(item.Name == "RoofLight")'),
    ("the signs not in the town's print", HS, HALLS, 'text.FontFace = Style.WORLD.sign\n\ttext.TextColor3 = ENAMEL_INK', 'text.FontFace = Style.FONT.body\n\ttext.TextColor3 = ENAMEL_INK'),
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
