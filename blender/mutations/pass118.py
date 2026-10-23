"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 118, from your Studio test. The clouds see-through again, or their undersides; honey, slime or a honey
drip on Glass; Hill House's mist see-through, or several sheets again; grass up through the hall's floor or the path;
the bare ground left when the level goes; a bubble walked into heard, one going by itself heard, or one tapped
unheard; Hill House first in the lobby again, the story in the lobby's order, the story's card naming the wrong level
next, or a save's story place counted along the lobby; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
APPEAR = S / "Shared/MaterialAppearance.lua"
BOOT = S / "Server/Bootstrap.server.lua"
ECON = S / "Server/Services/EconomyService.lua"
HOUSE = S / "Server/Services/HillHouseService.lua"
LEVELS = S / "Shared/LevelDefinitions.lua"
LIFE = S / "Client/Services/LobbyLife.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
SKYS = S / "Server/Services/SkyPoolsService.lua"
HILL, HUB, SKYCHECK, PARSE = "check_hillhouse.py", "check_hub.py", "check_skypools.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HILL, HUB, SKYCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the clouds see-through again', SKYS, SKYCHECK, '\t\t\tpuff.Transparency = 0\n', '\t\t\tpuff.Transparency = 0.08\n'),
    ('their undersides', SKYS, SKYCHECK, '\t\t\t\tunder.Transparency = 0\n', '\t\t\t\tunder.Transparency = 0.2\n'),
    ('honey on Glass', APPEAR, SKYCHECK, '\t\tmaterial = Enum.Material.SmoothPlastic,\n\t\ttransparency = 0.08,', '\t\tmaterial = Enum.Material.Glass,\n\t\ttransparency = 0.08,'),
    ('slime on Glass', APPEAR, SKYCHECK, 'read as wet.\n\t\tmaterial = Enum.Material.SmoothPlastic,', 'read as wet.\n\t\tmaterial = Enum.Material.Glass,'),
    ('a honey drip on Glass', RENDER, SKYCHECK, 'HoneyString = { colour = Color3.fromRGB(228, 158, 40), material = Enum.Material.SmoothPlastic,', 'HoneyString = { colour = Color3.fromRGB(228, 158, 40), material = Enum.Material.Glass,'),
    ("Hill House's mist see-through", HOUSE, HILL, '\tsheet.CastShadow = false\n\tlocal wind = Vector3.new(1, 0, 0.4).Unit', '\tsheet.CastShadow = false\n\tsheet.Transparency = 0.45\n\tlocal wind = Vector3.new(1, 0, 0.4).Unit'),
    ('several sheets again', HOUSE, HILL, '\tsheet.CastShadow = false\n\tlocal wind = Vector3.new(1, 0, 0.4).Unit', '\tsheet.CastShadow = false\n\tcylinder(parent, "Mist", 3, 1900, CFrame.new(centre.X, topY - 1, centre.Z), PALETTE.mist, Enum.Material.SmoothPlastic)\n\tlocal wind = Vector3.new(1, 0, 0.4).Unit'),
    ("grass up through the hall's floor", HOUSE, HILL, '\t\tVector3.new(HOUSE_W + 4, 3, HOUSE_D + 4), Enum.Material.Ground)', '\t\tVector3.new(HOUSE_W + 4, 3, HOUSE_D + 4), Enum.Material.Grass)'),
    ('grass up the path', HOUSE, HILL, 'Vector3.new(4.5, 3, pathLong + 3), Enum.Material.Ground)', 'Vector3.new(4.5, 3, pathLong + 3), Enum.Material.Grass)'),
    ('the bare ground left when the level goes', HOUSE, HILL, '\ttable.insert(filled, { cf = cf, size = size + Vector3.new(4, 4, 4) })\n', ''),
    ('a bubble walked into heard', LIFE, HUB, 'if (point - at).Magnitude < size / 2 + POP_REACH then\n\t\t\t\t\tpop(index, false, true)', 'if (point - at).Magnitude < size / 2 + POP_REACH then\n\t\t\t\t\tpop(index, true, true)'),
    ('one going by itself heard', LIFE, HUB, 'pop(index, false, b.part.Parent ~= nil)', 'pop(index, true, b.part.Parent ~= nil)'),
    ('one tapped unheard', LIFE, HUB, '\t\tpop(best, true, true)\n', '\t\tpop(best, false, true)\n'),
    ('Hill House first in the lobby again', LEVELS, HILL, 'LevelDefinitions.All = {\n\tLevelDefinitions.Level1,', 'LevelDefinitions.All = {\n\tLevelDefinitions.Level5,\n\tLevelDefinitions.Level1,'),
    ("the story in the lobby's order", BOOT, HILL, 'local level = LevelDefinitions.Story[run.index]', 'local level = LevelDefinitions.All[run.index]'),
    ("the story's card naming the wrong level next", BOOT, HILL, 'next = if last then nil else LevelDefinitions.Story[story.index + 1].name,', 'next = if last then nil else LevelDefinitions.All[story.index + 1].name,'),
    ("a save's story place counted along the lobby", ECON, HILL, 'return math.clamp(math.floor(at or 1), 1, #LevelDefinitions.Story)', 'return math.clamp(math.floor(at or 1), 1, #LevelDefinitions.All)'),
    ('a name never declared', HOUSE, PARSE, 'local houseMid = frontMid + inward * (HOUSE_D / 2)', 'local houseMid = frontMid + inwards * (HOUSE_D / 2)'),
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
