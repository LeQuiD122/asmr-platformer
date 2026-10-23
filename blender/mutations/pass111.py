"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 111: Hill House. Not first in the story; not at eight; not ending at the house; no light, banner, pad sky
or badge of its own; its badge read by place; the crag too near the route, never pushed clear, its rocks on the
route's side; a leg down through the spiral; the bridge not braced, or no guard; the house past the fence; no fence;
the mist too high; never built, the finish line not stood down, not taken down before the next level or when it goes;
its ground never cleared; the door swinging out, saying nothing, ending twice or nothing; Neon; its name not in the
world's print; fewer than four things to read; no bed of its own; the bed not checked for; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
AMB = S / "Client/Services/AmbienceService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
CAT = S / "Shared/ShopCatalog.lua"
HOUSE = S / "Server/Services/HillHouseService.lua"
HUBS = S / "Server/Services/HubService.lua"
LEVELS = S / "Shared/LevelDefinitions.lua"
LIGHTS = S / "Server/Services/LightingService.lua"
STORYSV = S / "Server/Services/StoryService.lua"
UIS = S / "Client/Services/UIService.lua"
HILL, HUB, STORY, PARSE = "check_hillhouse.py", "check_hub.py", "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HILL, HUB, STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('not first in the story', LEVELS, HILL, 'LevelDefinitions.Story = {\n\tLevelDefinitions.Level5,\n\tLevelDefinitions.Level1,', 'LevelDefinitions.Story = {\n\tLevelDefinitions.Level1,\n\tLevelDefinitions.Level5,'),
    ('not at eight', LEVELS, HILL, 'storyTime = "8:00 AM",', 'storyTime = "9:00 PM",'),
    ('not ending at the house', LEVELS, HILL, 'finale = "house",', 'finale = "none",'),
    ('no light of its own', LIGHTS, HILL, '\thillHouse = {\n\t\tsky = Color3.fromRGB(176, 206, 236),', '\thillHouses = {\n\t\tsky = Color3.fromRGB(176, 206, 236),'),
    ('lit at night', LIGHTS, HILL, '\t\tclock = 7.9,\n\t\tbrightness = 1.8,', '\t\tclock = 22,\n\t\tbrightness = 1.8,'),
    ('no banner', UIS, HILL, 'vignette = Color3.fromRGB(18, 16, 12), motif = "door" },', 'vignette = Color3.fromRGB(18, 16, 12), motif = "tiles" },'),
    ('no pad sky', HUBS, HILL, '\thillHouse = {\n\t\tsky = Color3.fromRGB(236, 214, 190),', '\thillHouseX = {\n\t\tsky = Color3.fromRGB(236, 214, 190),'),
    ('no badge', CAT, HILL, '[4] = 0, [5] = 0 },', '[4] = 0 },'),
    ('its badge read by place', BOOT, HILL, '(badges.level[level.levelId] or 0) == 0', '(badges.level[1] or 0) == 0'),
    ('the crag too near the route', HOUSE, HILL, 'local CLEAR = 26', 'local CLEAR = 12'),
    ('never pushed clear', HOUSE, HILL, '\t\tC += out * 2\n', '\t\tC += out * 0\n'),
    ("its rocks on the route's side", HOUSE, HILL, 'local a = rng:NextNumber(-1.2, 1.2)', 'local a = rng:NextNumber(-3.1, 3.1)'),
    ('a leg down through the spiral', HOUSE, HILL, 'part(model, "Landing", LANDING, landing, PALETTE.stone, Enum.Material.Concrete, true)', 'part(model, "Landing", LANDING, landing, PALETTE.stone, Enum.Material.Concrete, true)\n\tpart(model, "LandingLeg", Vector3.new(1, 90, 1), landing * CFrame.new(0, -45, 0), PALETTE.timber, Enum.Material.Wood)'),
    ('the bridge not braced', HOUSE, HILL, 'part(model, "BridgeBrace"', 'part(model, "BridgeStrut"'),
    ('no guard', HOUSE, HILL, 'local guard = part(model, "BridgeGuard"', 'local guard = part(model, "BridgeEdge"'),
    ('the house past the fence', HOUSE, HILL, 'local HOUSE_W, HOUSE_D, STOREY, ROOF_H = 26, 18, 11, 8', 'local HOUSE_W, HOUSE_D, STOREY, ROOF_H = 26, 40, 11, 8'),
    ('no fence', HOUSE, HILL, '\tpicketFence(garden, top, CRAG_R - 1.5, topY, endAt)\n', ''),
    ('the mist too high', HOUSE, HILL, 'local MIST_OVER_KILL = 6', 'local MIST_OVER_KILL = 60'),
    ('never built', BOOT, HILL, 'HillHouseService.start(levelInstance.finishFrame, workspace:WaitForChild("Levels"), levelInstance.centre,', 'HillHouseService.begin(levelInstance.finishFrame, workspace:WaitForChild("Levels"), levelInstance.centre,'),
    ('the finish line not stood down', BOOT, HILL, 'if houseOk then\n\t\t\t\tif levelInstance.finishPart then\n\t\t\t\t\tlevelInstance.finishPart.CanTouch = false', 'if houseOk then\n\t\t\t\tif levelInstance.finishPart then\n\t\t\t\t\tlevelInstance.finishPart.CanTouch = true'),
    ('not taken down before the next level', BOOT, HILL, '\tif HillHouseService then\n\t\tpcall(HillHouseService.stop)\n\tend\n\tlevelInstance = LevelService.startLevel', '\tlevelInstance = LevelService.startLevel'),
    ('not taken down when it goes', BOOT, HILL, '\tif HillHouseService then\n\t\tpcall(HillHouseService.stop)\n\tend\n\tLevelService.endLevel()', '\tLevelService.endLevel()'),
    ('its ground never cleared', HOUSE, HILL, '\ttable.clear(arrived)\n\tclearTerrain()\nend', '\ttable.clear(arrived)\nend'),
    ('the door swinging out', HOUSE, HILL, 'math.rad(-100)', 'math.rad(100)'),
    ('the door saying nothing', HOUSE, HILL, 'open.ActionText = "Go in"', 'open.ActionText = ""'),
    ('ending twice', HOUSE, HILL, '\t\tif arrived[player] then\n\t\t\treturn\n\t\tend\n', ''),
    ('ending nothing', HOUSE, HILL, '\t\tonArrive(player)\n', '\t\tlocal _ = onArrive\n'),
    ('Neon', HOUSE, HILL, 'door.Reflectance = 0.08', 'door.Material = Enum.Material.Neon'),
    ("its name not in the world's print", HOUSE, HILL, 'words.FontFace = Style.WORLD.sign', 'words.FontFace = Style.FONT.display'),
    ('fewer than four things to read', STORYSV, STORY, '\t\t{ title = "On the gatepost", body = "HILL HOUSE.\\n\\nNo circulars, thank you. Milk on the step.\\n\\nE. Marsh" },\n', ''),
    ('no bed of its own', AMB, STORY, '\thillHouse = {\n\t\t{ name = "HillMorning"', '\thillHouseX = {\n\t\t{ name = "HillMorning"'),
    ('the bed not checked for', BOOT, HUB, '"HarbourNight", "HillMorning", "HoldDrone"', '"HarbourNight", "HoldDrone"'),
    ('a name never declared', HOUSE, PARSE, 'local routeR = Vector3.new(P.X - centre.X', 'local routeR = Vector3.new(PP.X - centre.X'),
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
