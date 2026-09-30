"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
TOWNS = S / "Server/Services/Townsfolk.lua"
STORY_SRC = S / "Server/Services/StoryService.lua"
CINEMA = S / "Client/Services/Cinema.lua"
HALLS = S / "Server/Services/FloodedHallsService.lua"
HALLSC = S / "Client/Services/FloodedHallsClient.lua"
SHORE = S / "Client/Services/CityShoreClient.lua"
DIVE = S / "Server/Services/DiveFinaleService.lua"
SKYPATH = S / "Shared/SkyPath.lua"
PATH = S / "Shared/SunkenPath.lua"
SUNKC = S / "Client/Services/SunkenCityClient.lua"
BOOT = S / "Server/Bootstrap.server.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
LEVELDEFS = S / "Shared/LevelDefinitions.lua"
HUB = S / "Server/Services/HubService.lua"
AUDIO = S / "Client/Services/AudioService.lua"
POSES = S / "Shared/Poses.lua"
STORY, HALLCHECK, PARSE, LUA, SKYCHECK, CITY, HUBCHECK = ("check_story.py", "check_halls.py", "check_luau_syntax.py",
                                                          "check_lua.py", "check_skypools.py", "check_sunkencity.py",
                                                          "check_hub.py")


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, HALLCHECK, PARSE, LUA, SKYCHECK, CITY, HUBCHECK):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # Slow enough to read.
    ("speech back to its old length", TOWNS, STORY, "local READ = 2", "local READ = 1"),
    ("captions down in half the time", CINEMA, STORY, "local CAPTION_SECONDS = 7", "local CAPTION_SECONDS = 3.5"),
    ("the opening back to six seconds", STORY_SRC, STORY, "task.wait(12)", "task.wait(6)"),
    ("the opening without its level", STORY_SRC, STORY, '("Level %d"):format(levelId)', '("%s"):format(words[1])'),
    # Always in shot.
    ("invisible in first person", CINEMA, STORY, "item.LocalTransparencyModifier = 0",
     "item.LocalTransparencyModifier = item.LocalTransparencyModifier"),
    ("kept drawn after the scene", CINEMA, STORY,
     "\tpcall(function()\n\t\tRunService:UnbindFromRenderStep(SHOW)\n\tend)\n\tif current.focus then",
     "\tif current.focus then"),
    ("no dip to black", CINEMA, STORY, "function Cinema.dip(", "function Cinema.fade("),
    # The people.
    ("Mrs Venn never at the baths", STORY_SRC, STORY, "pcall(venn, folder, first)", "local _ = venn"),
    ("Mr Barlow with nothing to say", TOWNS, STORY, '\tBarlow = {\n\t\t"There you are.', '\tBarlowe = {\n\t\t"There you are.'),
    ("Tobi in plain colours", TOWNS, STORY, "\tTobi = { skin", "\tToby = { skin"),
    ("nobody dressed", TOWNS, STORY, "pcall(dress, model, look)", "pcall(print, model, look)"),
    ("nobody talking with their hands", TOWNS, STORY, 'turn(npc, "RightShoulder", CFrame.Angles(0.6, 0, 0.12), 0.45)',
     'turn(npc, "RightShoulder", CFrame.identity, 0.45)'),
    ("no night engineer's spot", HALLS, STORY, 'halls:SetAttribute("EngineerSpot"', 'halls:SetAttribute("EngineSpot"'),
    # The notes.
    ("a dash in a note", STORY_SRC, STORY, '"HARBOUR HIGH WATER.', '"HARBOUR HIGH WATER -- AUGUST.'),
    ("two things to read at the pools", STORY_SRC, STORY,
     '\t\t{ title = "A note on a lounger", lying = true, body = "Gone down to find the man with the keys. Back by three. Keep my seat.\\n\\nT." },\n',
     ""),
    ("the rota in nobody's name", STORY_SRC, STORY, "KEY HOLDER, OUTFALL 3: %s.", "KEY HOLDER, OUTFALL 3: unknown."),
    # (Notes are taken into the journal with E since the eighteenth pass; a note with no nook still goes out.)
    ("a note with nowhere to go left out", STORY_SRC, STORY, "pcall(note, folder, cap, entry)", "pcall(print, folder, cap, entry)"),
    # The levels in order.
    ("the pads unnumbered", HUB, STORY, "makeSign(pad, LevelDefinitions.titleOf(level),", "makeSign(pad, level.name,"),
    ("the Sunken City at another time", LEVELDEFS, STORY, 'storyTime = "11:52 PM"', 'storyTime = "11:00 PM"'),
    # Half speed.
    ("the slide at full speed", SKYPATH, STORY, "SkyPath.SPEED = 36", "SkyPath.SPEED = 70"),
    ("the drain at full speed", PATH, STORY, "SunkenPath.DRAIN_SECONDS = 13", "SunkenPath.DRAIN_SECONDS = 6.5"),
    ("the dive's carry at full speed", DIVE, STORY, "local CARRY_SPEED = 120", "local CARRY_SPEED = 350"),
    ("the diver's fall uncapped", SHORE, STORY, "local FALL_SPEED = 110", "local FALL_SPEED = 400"),
    # F7.
    ("the panel shown from the start", SUNKC, STORY, "local panel = { on = false }", "local panel = { on = true }"),
    ("F7 ignored when handled", SUNKC, STORY, "and not input:GetFocusedTextBox()", "and not key.UserInputState"),
    # Sound for every material.
    ("the sound folder never read", AUDIO, STORY, 'SoundService:FindFirstChild("MaterialSounds")', 'SoundService:FindFirstChild("Nothing")'),
    ("a material with no takes", AUDIO, STORY, "\tchocolateSnap = {},\n", "\tchocolateSnapped = {},\n"),
    ("the flume's pose missing", POSES, STORY, "function Poses.flume(", "function Poses.slide("),
    # The Flooded Halls' ending.
    ("the flume at full speed", HALLS, HALLCHECK, "local SLIDE_SECONDS = 11", "local SLIDE_SECONDS = 4.6"),
    ("no gate chamber", HALLS, HALLCHECK, "pcall(buildGates, halls, endFrame, pitAt)", "pcall(print, halls, endFrame, pitAt)"),
    ("the finish in reach", HALLS, HALLCHECK, "chamberFrame * CFrame.new(0, -40, 0)", "chamberFrame * CFrame.new(0, 3, 0)"),
    ("the kill plane not told", HALLS, HALLCHECK, 'insideGates(workspace:FindFirstChild("FloodedHalls"), root.Position)', "false"),
    ("no key", HALLS, HALLCHECK, "\t\t\t\t\t\tgiveKey(character)\n", "\t\t\t\t\t\tlocal _ = character\n"),
    ("the chamber near the delete line", HALLS, HALLCHECK, "\tBELOW = 150,", "\tBELOW = 400,"),
    ("the key too late", HALLS, HALLCHECK, "\tKEY_AT = 14,", "\tKEY_AT = 34,"),
    ("no mouth before the chamber", HALLSC, HALLCHECK, "mawStep(current, root, humanoid, t - current.slide)",
     "chamberStep(current, root, humanoid, t - current.slide)"),
    ("the rider left walking slowly", HALLSC, HALLCHECK, "humanoid.WalkSpeed = current.speed", "humanoid.WalkSpeed = 9"),
    ("no HallsCinema remote", BOOT, HALLCHECK, 'ensureRemoteEvent(remoteEventsFolder, "HallsCinema")', 'local _ = "HallsCinema"'),
    ("the halls' client never started", CBOOT, HALLCHECK, '"CityShoreClient", "FloodedHallsClient",', '"CityShoreClient",'),
    ("the sump left full after the level", HALLS, HALLCHECK,
     "size + Vector3.new(8, 8, 8),\n\t\t\t\t\tEnum.Material.Air)", "size + Vector3.new(8, 8, 8),\n\t\t\t\t\tEnum.Material.Water)"),
    # The code still reads.
    ("an if with no then", HALLSC, PARSE, "\tif b < BEAT.climb then\n", "\tif b < BEAT.climb\n"),
    ("a name never declared", HALLSC, PARSE, "local ahead = frame.LookVector", "local ahead = frameLook"),
    ("a name never declared in dress", TOWNS, PARSE, 'local sleeves = look.sleeves or "short"', "local sleeves = look.sleeves or shortSleeves"),
    ("the slide's clamp out of bounds", SKYPATH, SKYCHECK, "SkyPath.MIN_SECONDS, SkyPath.MAX_SECONDS = 16, 30",
     "SkyPath.MIN_SECONDS, SkyPath.MAX_SECONDS = 16, 60"),
    ("the Sandbox without a time", LEVELDEFS, HUBCHECK, '\tstoryTime = "",\n', ""),
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
               if line.startswith("  ") or line.startswith("FAIL") or "THE ENDING" in line or "Floode" in line][:2]
        print("%-8s %s  %s" % ("caught" if caught else "MISSED", label, "; ".join(why)[:170]))
        if not caught:
            missed.append(label)
finally:
    for path, data in originals.items():
        path.write_bytes(data)
print("\n%d of %d caught" % (len(MUTATIONS) - len(missed), len(MUTATIONS)))
sys.exit(1 if missed else 0)
