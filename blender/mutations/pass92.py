"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 92: from the third test. The dive: the diver thinking nothing off the board, turning over or with the
water coming; a thought with a dash; the drop looking up at the sky again, away from the sea; no face on the way
down. The fall into the mouth: the air thickened past the level's own (it hid the mouth), or set outright; the sky
still lighting the shaft; the shaft's lamps left lit, or left dim after; the dark fading on after the light is back;
falling into it on your back; your face never seen, or seen too briefly, or the wide shot cut short. The paste
check: a module with another's code in it unnoticed on either side, or only among the stamped ones, or every module
required whatever it is (one taken out of the game would be started), or an unstamped one not looked at; an old copy
reported as well as misplaced code; a script missed for how its name is written; anything named ProfileStore taken
for loleris's, on the paste check or when saving. A name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
BOOT = S / "Server/Bootstrap.server.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
ECON = S / "Server/Services/EconomyService.lua"
HC = S / "Client/Services/FloodedHallsClient.lua"
SHORE = S / "Client/Services/CityShoreClient.lua"
HALLS, HUB, SHOP, STAMPS, STORY, PARSE = "check_halls.py", "check_hub.py", "check_shop.py", "check_stamps.py", "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HALLS, HUB, SHOP, STAMPS, STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('nothing thought off the board', SHORE, STORY, '\t\t\t\tthink("brave", "Okay. Don\'t look down.", 1.8)\n', ''),
    ('nothing thought turning over', SHORE, STORY, '\t\t\t\tthink("looked", "I looked down.", 1.6)\n', ''),
    ('nothing thought with the water coming', SHORE, STORY, '\t\t\t\tthink("arms", "Arms together. Arms together!", 2)\n', ''),
    ('a thought with a dash', SHORE, STORY, 'think("looked", "I looked down.", 1.6)', 'think("looked", "I looked -- down.", 1.6)'),
    ('the drop looking up again', SHORE, STORY, 'here - Vector3.new(0, 22, 0), current.facing)', 'here + Vector3.new(0, 22, 0), current.facing)'),
    ('no face on the way down', SHORE, STORY, 'shot("face")', 'shot("close")'),
    ('the air thick again', HC, HALLS, 'airAtMost = 0.36,', 'airAtMost = 0.82,'),
    ('the air set outright', HC, HALLS, 'local DARK = { ambient = Color3.fromRGB(24, 26, 34), exposure = -0.1,', 'local DARK = { ambient = Color3.fromRGB(24, 26, 34), density = 0.82, exposure = -0.1,'),
    ('the sky lighting the shaft', HC, HALLS, 'EnvironmentDiffuseScale = 0, EnvironmentSpecularScale = 0', 'EnvironmentDiffuseScale = 1, EnvironmentSpecularScale = 1'),
    ("the shaft's lamps left lit", HC, HALLS, '\t\t\t\t\tlit.dimmed[item] = item.Brightness\n\t\t\t\t\ttween(item, { Brightness = item.Brightness * DARK.dim })\n', ''),
    ('the failing fitting left lit', HC, HALLS, '\t\t\t\t\titem.Enabled = false\n\t\t\t\t\ttable.insert(lit.off, item)\n', ''),
    ('the failing fitting left off', HC, HALLS, '\t\tlight.Enabled = true\n', '\t\tlocal _ = light\n'),
    ('the face shot through your chest', HC, HALLS, '+ crown * 1.8 + side * 0.8', '+ side * 0.8'),
    ('the client requiring everything', CBOOT, STAMPS, '\tfor _, name in ipairs(ours) do\n\t\tlocal found = Services:FindFirstChild(name)\n', '\tfor _, found in ipairs(Services:GetChildren()) do\n\t\tlocal _ = ours\n'),
    ('an unstamped module not looked at', CBOOT, STAMPS, '"InputService", "SeaService" }', '"InputService" }'),
    ("the shaft's lamps left dim", HC, HALLS, '\t\t\tlight.Brightness = brightness\n', ''),
    ('the dark fading on', HC, HALLS, '\t\tmade:Cancel()\n', '\t\tlocal _ = made\n'),
    ('falling in on your back', HC, HALLS, 'CFrame.Angles(math.pi / 2 + tumble - math.pi * over, 0, tumble * 0.4)', 'CFrame.Angles(math.pi / 2 + tumble, 0, tumble * 0.4)'),
    ('your face never seen', HC, HALLS, 'Cinema.point(CFrame.lookAt(eye, face, root.CFrame.UpVector), 54 - 6 * k)', 'Cinema.point(CFrame.lookAt(eye, pos), 54)'),
    ('your face too brief', HC, HALLS, '\tface = 1.8,', '\tface = 2.4,'),
    ('the wide shot cut short', HC, HALLS, '\tface = 1.8,', '\tface = 1.2,'),
    ("another's code unnoticed (server)", BOOT, STAMPS, '\t\t\t\tif whose and whose ~= name then\n', '\t\t\t\tif false then\n'),
    ('only the stamped looked at', BOOT, STAMPS, 'for _, side in ipairs({ { names = SERVER_MODULES, folder = serverServices,', 'for _, side in ipairs({ { names = {}, folder = serverServices,'),
    ("another's code unnoticed (client)", CBOOT, STAMPS, '\t\t\tif whose and whose ~= found.Name then\n', '\t\t\tif false then\n'),
    ('an old copy said twice', BOOT, STAMPS, 'if stamp ~= expected[name] and not misplaced[name] then', 'if stamp ~= expected[name] then'),
    ('BootStrap missed', BOOT, HUB, 'if named == want or named == want .. ".server" or named == want .. ".client" then', 'if named == name then'),
    ('ProfileService taken for ProfileStore', BOOT, HUB, 'elseif type(loaded) ~= "table" or type((loaded :: any).New) ~= "function" then', 'elseif false then'),
    ('a wrong ProfileStore called anyway', ECON, SHOP, 'if type(result) ~= "table" or type((result :: any).New) ~= "function" then', 'if false then'),
    ('a name never declared', HC, PARSE, '\ttween(grade, { Brightness = 0, Contrast = 0.14,', '\ttweens(grade, { Brightness = 0, Contrast = 0.14,'),
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
