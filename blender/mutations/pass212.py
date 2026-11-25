"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Passes 210 to 212: the solid chocolate built quietly; the endings' score (a bed and a hit, gone with the scene); the lift
pavilion in the garden (each piece on the one under it); Hill House finished outside and in; the Maw's gums matched; the
shop's items as little moving models. A box of a lift; a ceiling off its capitals; bars short of the ceiling; a dial
floating over the cornice; a cornice off its ceiling; the porch's wings back; a shutter over its window; shutters into
each other; the back lining facing the wall; the painting facing the wall; the barometer facing the wall; the ground
back in the hall; the hollow too shallow; a bare house; an unmatched upper jaw; the score with no bed; no climax; the bed
outliving the scene; a level with no hit; a level with no bed; the chocolate looking for a mesh; trails drawn flat; an
emote with no move; models moving under Reduce Motion; models never let go of; no fallback to the drawing.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ROOM = S / "Server/Services/SquishRoomService.lua"
HOUSE = S / "Server/Services/HillHouseService.lua"
MAW = S / "Client/Services/Maw.lua"
CINEMA = S / "Client/Services/Cinema.lua"
SHORE = S / "Client/Services/CityShoreClient.lua"
SKY = S / "Client/Services/SkyPoolsClient.lua"
BUILDER = S / "Server/ChunkBuilder.server.lua"
MODELS = S / "Client/Services/ShopModels.lua"
SHOP = S / "Client/Services/ShopService.lua"
SQUISH, HILL, HALLS, FEEL, SHOPC = "check_squishroom.py", "check_hillhouse.py", "check_halls.py", "check_feel.py", "check_shop.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SQUISH, HILL, HALLS, FEEL, SHOPC):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('a box of a lift', ROOM, SQUISH, 'round("LiftDrum", 0.4, 5.6,', 'round("LiftHat", 0.4, 5.6,'),
    ('a ceiling off its capitals', ROOM, SQUISH, '"LiftCeiling", Vector3.new(7.4, 0.5, 7.4), at(0, 10.15, 0)',
     '"LiftCeiling", Vector3.new(7.4, 0.5, 7.4), at(0, 10.6, 0)'),
    ('bars short of the ceiling', ROOM, SQUISH, 'round("LiftBar", 5.7, 0.16, at(-3.15, 7.05, along)',
     'round("LiftBar", 4.7, 0.16, at(-3.15, 7.05, along)'),
    ('a dial floating over the cornice', ROOM, SQUISH, '"LiftDialRim", Vector3.new(0.2, 2.4, 2.4), at(0, 12.1, -3.6)',
     '"LiftDialRim", Vector3.new(0.2, 2.4, 2.4), at(0, 13, -3.6)'),
    ('a cornice off its ceiling', ROOM, SQUISH, '"LiftRoof", Vector3.new(8.2, 0.5, 8.2), at(0, 10.65, 0)',
     '"LiftRoof", Vector3.new(8.2, 0.5, 8.2), at(0, 11.2, 0)'),
    ("the porch's wings back", HOUSE, HILL, 'part(parent, "PorchRoof", Vector3.new(3.5, 0.3, 2.9), slope,',
     'wedge(parent, "PorchRoof", Vector3.new(3.5, 0.3, 2.9), slope,'),
    ('a shutter over its window', HOUSE, HILL, 'CFrame.new(mid + side * (half + 0.85), cy, -0.62)',
     'CFrame.new(mid + side * (half + 0.5), cy, -0.62)'),
    ('shutters into each other', HOUSE, HILL, 'part(parent, "Shutter", Vector3.new(1.6, h[4] - h[3], 0.2)',
     'part(parent, "Shutter", Vector3.new(1.9, h[4] - h[3], 0.2)'),
    ('the back lining facing the wall', HOUSE, HILL,
     'centre * CFrame.new(0, floorY, inZ - 0.06) * CFrame.Angles(0, math.pi, 0), W - 2, { { -6, -2 } }',
     'centre * CFrame.new(0, floorY, inZ - 0.06), W - 2, { { 2, 6 } }'),
    ('the painting facing the wall', HOUSE, HILL, 'CFrame.new(-inX + 0.2, floorY + 6.2, 5) * CFrame.Angles(0, -math.pi / 2, 0)',
     'CFrame.new(-inX + 0.2, floorY + 6.2, 5) * CFrame.Angles(0, math.pi / 2, 0)'),
    ('the barometer facing the wall', HOUSE, HILL, 'CFrame.new(inX - 0.2, floorY + 5.5, 3.2) * CFrame.Angles(0, math.pi / 2, 0)',
     'CFrame.new(inX - 0.2, floorY + 5.5, 3.2) * CFrame.Angles(0, -math.pi / 2, 0)'),
    ('the ground back in the hall', HOUSE, HILL, 'Vector3.new(HOUSE_W - 2, STOREY + 2, HOUSE_D - 2),\n\t\tEnum.Material.Air)',
     'Vector3.new(HOUSE_W - 2, STOREY + 2, HOUSE_D - 2),\n\t\tEnum.Material.Ground)'),
    ('the hollow too shallow', HOUSE, HILL, 'local hollow = houseMid + Vector3.new(0, (STOREY - 2) / 2, 0)',
     'local hollow = houseMid + Vector3.new(0, (STOREY + 0.4) / 2, 0)'),
    ('a bare house', HOUSE, HILL, 'part(parent, "BookcaseBack",', 'part(parent, "BookcaseRear",'),
    ('an unmatched upper jaw', MAW, HALLS, '\t\t\tparts[1][2] = TEXTURED_FLESH\n', '\t\t\tparts[2][2] = TEXTURED_FLESH\n'),
    ('the score with no bed', CINEMA, FEEL, 'function Cinema.score(name: string)', 'function Cinema.scoreLater(name: string)'),
    ('no climax', CINEMA, FEEL, 'Cinema.sound("ScoreHit", 0.85, { keep = true, pitch = pitch or 1 })',
     'Cinema.sound("ScoreHit", 0, { keep = true, pitch = pitch or 1 })'),
    ('the bed outliving the scene', CINEMA, FEEL, '\tscoring.bed = nil\n\tscoring.token += 1\n\tif current.ending',
     '\tscoring.token += 1\n\tif current.ending'),
    ('a level with no hit', SKY, FEEL, 'Cinema.climax(1.12)', 'Cinema.sound("PoolPlunge2", 0)'),
    ('a level with no bed', SHORE, FEEL, 'Cinema.score("Shore")', 'Cinema.sound("Shore", 0)'),
    ('the chocolate looking for a mesh', BUILDER, FEEL, 'if MESHLESS[materialName] or CHUNKED[materialName] then',
     'if MESHLESS[materialName] then'),
    ('trails drawn flat', MODELS, SHOPC, 'BUILD.trail = function(world, item)', 'BUILD.ribbon = function(world, item)'),
    ('an emote with no move', MODELS, SHOPC, '\tShrug = function(t)', '\tShrugged = function(t)'),
    ('models moving under Reduce Motion', MODELS, SHOPC, 'if not Style.lessMotion() then\n\t\ttable.insert(live,',
     'if true then\n\t\ttable.insert(live,'),
    ('models never let go of', MODELS, SHOPC, 'if not entry.view.Parent then\n\t\t\t\ttable.remove(live, k)',
     'if not entry.view.Parent then\n\t\t\t\tcontinue'),
    ('no fallback to the drawing', SHOP, SHOPC, 'if not modelled then\n\t\tdrawIcon(icon, item)', 'if false then\n\t\tdrawIcon(icon, item)'),
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
