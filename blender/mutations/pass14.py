"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
TOWNS = S / "Server/Services/Townsfolk.lua"
STORY_SRC = S / "Server/Services/StoryService.lua"
DIVE = S / "Server/Services/DiveFinaleService.lua"
SHORE = S / "Client/Services/CityShoreClient.lua"
SKY = S / "Server/Services/SkyPoolsService.lua"
SKYC = S / "Client/Services/SkyPoolsClient.lua"
SUNK = S / "Server/Services/SunkenCityService.lua"
SUNKC = S / "Client/Services/SunkenCityClient.lua"
PATH = S / "Shared/SunkenPath.lua"
POSES = S / "Shared/Poses.lua"
BOOT = S / "Server/Bootstrap.server.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
STORY, CITY, PARSE, LUA, SKYCHECK = ("check_story.py", "check_sunkencity.py", "check_luau_syntax.py", "check_lua.py",
                                     "check_skypools.py")


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, CITY, PARSE, LUA, SKYCHECK):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # The story.
    ("Okafor sunk into her lounger", SKY, STORY, "bed * CFrame.new(0.55, 1.72, -0.6)", "bed * CFrame.new(0.55, 0, -0.6)"),
    ("the lobby back after four seconds", BOOT, STORY, "\t\t\tsceneState[player] = nil\n\t\t\ttask.wait(6)\n",
     "\t\t\tsceneState[player] = nil\n\t\t\ttask.wait(4)\n"),
    ("no DiveCinema remote", BOOT, STORY, 'ensureRemoteEvent(remoteEventsFolder, "DiveCinema")', 'local _ = "DiveCinema"'),
    ("the story never staged", BOOT, STORY, "pcall(StoryService.stage, level, built, players)", "pcall(print, level, built, players)"),
    ("CityShoreClient never started", CBOOT, STORY, '"SunkenCityClient", "CityShoreClient", "FloodedHallsClient",', '"SunkenCityClient", "FloodedHallsClient",'),
    ("a double dash in what Okafor says", TOWNS, STORY, "Is it three yet? It's always nearly three.",
     "Is it three yet -- it's always nearly three."),
    ("an em dash in a caption", SUNKC, STORY, '"Outfall 3. The gates are still closed."',
     '"Outfall 3 \u2014 the gates are still closed."'),
    ("the time card in nobody's name", SUNK, STORY, "format(string.upper(player.DisplayName))", 'format("SOMEONE")'),
    ("Rudy with nothing to say", TOWNS, STORY, "\tRudy = {\n\t\t\"Last song!", "\tRudi = {\n\t\t\"Last song!"),
    ("only one on the Sky Pools knowing the key man", TOWNS, STORY,
     "Under the pumps... ask the key man.", "Under the pumps... ask anyone."),
    ("the Sky Pools on another day", STORY_SRC, STORY, "14 August. Three o'clock.", "15 August. Three o'clock."),
    ("Pip never stood up", STORY_SRC, STORY, "pcall(pip, folder, mid)", "local _ = pip"),
    # City Shore's dive.
    ("the diver stood back up for the water", DIVE, STORY, "CFrame = CFrame.new(surface) * turn,",
     "CFrame = CFrame.lookAt(surface, surface + Vector3.zAxis),"),
    ("nobody told of the dive", DIVE, STORY,
     'remote:FireAllClients("dive", player, workspace:GetServerTimeNow(), finale.circle.Y, tip)',
     'remote:FireClient(player, "dive", player, workspace:GetServerTimeNow(), finale.circle.Y, tip)'),
    ("Maren silent", DIVE, STORY, 'Townsfolk.shout("Maren")', 'Townsfolk.find("Maren")'),
    ("the diver left lying down", SHORE, STORY, "humanoid.PlatformStand = false", "humanoid.PlatformStand = true"),
    ("a broken dive scene keeping the camera", SHORE, STORY, "pcall(endScene, true)", "local _ = endScene"),
    ("the splash never heard", SHORE, STORY, 'elseif kind == "splash" then', 'elseif kind == "splosh" then'),
    # The Sky Pools' slide.
    ("the pose taken for a sled", SKYC, STORY, 'if first == "pose" then', 'if false then'),
    ("IsA on a string", SKYC, STORY, 'typeof(sled) == "Instance" and ', ""),
    ("the camera kept after the landing", SKYC, STORY, "\t\tscene.landedAt = nil\n\t\tCinema.finish()\n",
     "\t\tscene.landedAt = nil\n"),
    ("the rider's arms up on their screen only", SKY, STORY,
     'remote:FireAllClients("pose", player, startedAt, seconds + SkyPath.SKIM_SECONDS)',
     'remote:FireClient(player, "pose", player, startedAt, seconds + SkyPath.SKIM_SECONDS)'),
    ("nobody at the Sky Pools", SKY, STORY, "pcall(people, model, mouth)", "local _ = people"),
    ("Rudy silent", SKY, STORY, 'Townsfolk.shout("Rudy")', 'Townsfolk.find("Rudy")'),
    ("Poses without the sled", POSES, STORY, "function Poses.sled(", "function Poses.sit("),
    # The Sunken City's ending and fish.
    ("the outfall rushed", PATH, CITY, "SunkenPath.OUTFALL_SECONDS = 16", "SunkenPath.OUTFALL_SECONDS = 2"),
    ("the station barely seen", PATH, CITY, "SunkenPath.REVEAL_SECONDS = 7", "SunkenPath.REVEAL_SECONDS = 0.5"),
    ("fish that ignore you", SUNKC, CITY, "local SCATTER = 13", "local SCATTER = 0"),
    ("the shoals sparse again", SUNK, CITY, "local SHOAL_EVERY = 45", "local SHOAL_EVERY = 110"),
    ("no splash at the outfall", SUNK, CITY, "thud(outfall.path.to - Vector3.new(0, 2.6, 0), 20)",
     "local _ = outfall.path.to"),
    # The code still reads.
    ("an end lost in the landing hold", SKYC, PARSE, "\t\treturn\n\tend\n\tlocal spec = scene.spec",
     "\t\treturn\n\tlocal spec = scene.spec"),
    ("a scene helper read before it exists", SKYC, PARSE,
     "\tlocal character = Players.LocalPlayer.Character\n\tlocal ignore = if character",
     "\tlocal character = rideGui\n\tlocal ignore = if character"),
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
