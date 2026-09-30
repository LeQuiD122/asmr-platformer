"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 17: endings silence the level, every level has its own ambience, the secrets (letters, the pry bar,
lockers, loose bricks, a loose board, the Siren Tower) and the mouth at the bottom of the flume.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CINEMA = S / "Client/Services/Cinema.lua"
AMB = S / "Client/Services/AmbienceService.lua"
SUNKC = S / "Client/Services/SunkenCityClient.lua"
SKY = S / "Server/Services/SkyPoolsService.lua"
SUNK = S / "Server/Services/SunkenCityService.lua"
HUB = S / "Server/Services/HubService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
INTER = S / "Server/Services/Interactables.lua"
STORY_SRC = S / "Server/Services/StoryService.lua"
STORYC = S / "Client/Services/StoryClient.lua"
MAW = S / "Client/Services/Maw.lua"
HALLS = S / "Server/Services/FloodedHallsService.lua"
HALLSC = S / "Client/Services/FloodedHallsClient.lua"
STORY, HALLCHECK, PARSE = "check_story.py", "check_halls.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, HALLCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # An ending silences the level.
    ("an ending that never hushes", CINEMA, STORY, 'Players.LocalPlayer:SetAttribute("Hushed", true)', "local _ = true"),
    ("a secret's scene silencing the level", STORYC, STORY,
     '\tbusy = true\n\tCinema.begin({ hush = false })\n\tsound("SecretSting"', '\tbusy = true\n\tCinema.begin()\n\tsound("SecretSting"'),
    ("the Sunken City's mood bringing it back", SUNKC, STORY, "(1 - 0.6 * inside) * hush", "(1 - 0.6 * inside)"),
    ("the Sky Pools' water never tagged", SKY, STORY, 'CollectionService:AddTag(s, "Ambience")', "local _ = s"),
    ("the Sunken City's water never tagged", SUNK, STORY, 'CollectionService:AddTag(s, "Ambience")', "local _ = s"),
    ("the lobby still counted a level", HUB, STORY, 'player:SetAttribute("InLevel", nil)', "local _ = player"),
    # Every level its own sound.
    ("the Sky Pools with no ambience", AMB, STORY, "\tskyPools = {", "\tskyPool = {"),
    ("an ambience bed with no file", AMB, STORY, '{ name = "BathsHum", volume = 0.3 }', '{ name = "BathsHums", volume = 0.3 }'),
    # The secrets.
    ("the card counting wrong", INTER, STORY, "local TOTAL = 5", "local TOTAL = 4"),
    ("a secret nobody can find", STORY_SRC, STORY, 'at, "photograph", CFrame.new(', 'at, "polaroid", CFrame.new('),
    ("a dash in a secret", INTER, STORY, '"Somebody put it where nobody would look."', '"Somebody put it -- where nobody would look."'),
    ("no Siren Tower", STORY_SRC, STORY, "pcall(sirenTower, folder, instance, chunks, used, reserved)", "pcall(print, folder, instance, chunks, used, reserved)"),
    ("no pry bar anywhere", STORY_SRC, STORY, "pcall(Interactables.pryBar, folder, besideRoute(cap, -1, 2.6))", "pcall(print, folder)"),
    ("the Sunken City's letter back on a post", STORY_SRC, STORY, '{ title = "Missing", lying = true, body = ',
     '{ title = "Missing", body = '),
    ("the aquarium's locker unmarked", SUNK, STORY, 'lockerSpot:SetAttribute("Kind", "AquariumLocker")',
     'lockerSpot:SetAttribute("Kind", "Locker")'),
    ("nobody looks under the boards", STORYC, STORY, 'elseif kind == "peek" and', 'elseif kind == "look" and'),
    ("no StoryMoment remote", BOOT, STORY, 'ensureRemoteEvent(remoteEventsFolder, "StoryMoment")', 'local _ = "StoryMoment"'),
    # The mouth.
    ("the mouth's meshes refused", MAW, STORY, "Maw_UpperJaw = Vector3.new(55.0, 27.56, 105.0)", "Maw_UpperJaw = Vector3.new(55.0, 27.56, 93.0)"),
    ("the mouth too quick to see", HALLS, STORY, "\tMAW = 8.5,", "\tMAW = 2,"),
    ("the chamber before the mouth has shut", HALLS, STORY, "\t\t\t\ttask.wait(GATES.MAW)\n", "\t\t\t\tlocal _ = GATES.MAW\n"),
    ("the mouth never played", HALLSC, HALLCHECK, "mawStep(current, root, humanoid, t - current.slide)",
     "chamberStep(current, root, humanoid, t - current.slide)"),
    ("the Hold unnamed in the dark", HALLSC, HALLCHECK, '"The Hold", "It keeps what it is given."', '"The Hold", "It keeps."'),
    ("no cut to black", HALLSC, HALLCHECK, "\t\t\tCinema.black(true)\n", "\t\t\tCinema.black(true, 3)\n"),
    # The code still reads.
    ("a name never declared", INTER, PARSE, "\tlocal count = 0\n", "\tlocal count = zero\n"),
    ("a block left open in the mouth", MAW, PARSE, "\tMaw.set(built, 0.05, 0.05)\n\treturn built\nend\n",
     "\tMaw.set(built, 0.05, 0.05)\n\treturn built\n"),
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
