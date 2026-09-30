"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 18: the journal (nothing put on the screen, keepsakes as things), the nooks off the route, the
Siren Tower's bridge, captions that can be read and endings the lobby waits for, the view locked for a
run, the flume drawn by the rider, the mouth with no disc in it, the Sky Pools' skim and camera, the
Sunken City's swirl and shaft, fish that do not spin, bubble wrap heard at once, soap with no cracks.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
CINEMA = S / "Client/Services/Cinema.lua"
JOURNAL = S / "Client/Services/JournalService.lua"
VIEW = S / "Client/Services/ViewModeService.lua"
CBOOT = S / "Client/Bootstrap.client.lua"
BOOT = S / "Server/Bootstrap.server.lua"
INTER = S / "Server/Services/Interactables.lua"
STORY_SRC = S / "Server/Services/StoryService.lua"
SHORE = S / "Client/Services/CityShoreClient.lua"
HALLS = S / "Server/Services/FloodedHallsService.lua"
HALLSC = S / "Client/Services/FloodedHallsClient.lua"
MAW = S / "Client/Services/Maw.lua"
SKYPATH = S / "Shared/SkyPath.lua"
SKY = S / "Server/Services/SkyPoolsService.lua"
SKYC = S / "Client/Services/SkyPoolsClient.lua"
SUNK = S / "Server/Services/SunkenCityService.lua"
SUNKC = S / "Client/Services/SunkenCityClient.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
STORY, HALLCHECK, SKYCHECK, CITYCHECK, PARSE = ("check_story.py", "check_halls.py", "check_skypools.py",
                                                  "check_sunkencity.py", "check_luau_syntax.py")


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (STORY, HALLCHECK, SKYCHECK, CITYCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # The journal: taken, not shown.
    ("a keepsake that goes nowhere", INTER, STORY,
     'Interactables.take(player, { title = entry.thing, body = entry.line }, model, "keepsake"',
     'Interactables.whisper(player, entry.thing, model, "keepsake"'),
    ("a note on the screen again", INTER, STORY, "function Interactables.take(", "function Interactables.read(player: Player, a: any) end\nfunction Interactables.take("),
    ("the journal deaf to what was taken", JOURNAL, STORY, 'if kind == "journal" and typeof(data) == "table" then',
     'if kind == "journals" and typeof(data) == "table" then'),
    ("the journal holding the mouse", JOURNAL, STORY, "\tdim.Modal = true\n", "\tdim.Modal = false\n"),
    ("the corner line over a scene", JOURNAL, STORY, "while (Cinema and Cinema.active()) or isOpen do",
     "while isOpen do"),
    ("what you took left on your screen", JOURNAL, STORY, 'elseif kind == "hide" and typeof(data) == "Instance" then',
     'elseif kind == "hidden" and typeof(data) == "Instance" then'),
    # The nooks.
    ("notes back on the route", STORY_SRC, STORY, "pcall(nookNote, folder, nook, entry)", "pcall(note, folder, nook, entry)"),
    ("no keepsake in any nook", STORY_SRC, STORY, "pcall(nookKeepsake, folder, nook, material)", "pcall(print, folder, nook, material)"),
    ("a notice read, not taken", STORY_SRC, STORY, 'Interactables.take(player, entry, paper, "note")',
     'Interactables.whisper(player, entry.title)'),
    # The bridge.
    ("a bridge you can fall off", STORY_SRC, STORY, "\t\tguard.CanCollide = true\n", "\t\tguard.CanCollide = false\n"),
    ("a rail that is not there", STORY_SRC, STORY, "\t\trail.CanCollide = true\n", "\t\trail.CanCollide = false\n"),
    # Captions and endings.
    ("a caption gone before it is read", CINEMA, STORY,
     "local hold = math.max(seconds or CAPTION_SECONDS, READ_BASE + READ_WORD * count)", "local hold = seconds or CAPTION_SECONDS"),
    ("a caption over the last one", CINEMA, STORY, "local start = math.max(now, current.freeAt)", "local start = now"),
    ("the camera given back mid caption", CINEMA, STORY, "if not now and os.clock() < current.readUntil then",
     "if false and os.clock() < current.readUntil then"),
    ("the camera looking straight down in the lobby", CINEMA, STORY,
     "camera.CFrame = CFrame.lookAt(at - flat * 11 + Vector3.new(0, 3.5, 0), at)", "local _ = at"),
    ("the lobby cutting an ending off", BOOT, STORY, 'while sceneState[player] == "began" and waited < SCENE_WAIT',
     'while false and waited < SCENE_WAIT'),
    ("the banner over the last caption", CBOOT, STORY, "while Cinema and not Cinema.told() and waited < BANNER_WAIT do",
     "while false and waited < BANNER_WAIT do"),
    ("a dive that never says it is told", SHORE, STORY, "\t\tCinema.done()\n", "\t\tlocal _ = Cinema\n"),
    ("the carry in the server's steps", SHORE, STORY,
     "root.CFrame = CFrame.new(Vector3.new(from.X, y, from.Z)) * (root.CFrame - root.CFrame.Position)", "local _ = y"),
    # The view.
    ("first person not locked", VIEW, STORY, "player.CameraMode = Enum.CameraMode.LockFirstPerson",
     "player.CameraMode = Enum.CameraMode.Classic"),
    ("the view never started", CBOOT, STORY, '"JournalService", "ViewModeService"', '"JournalService"'),
    # The flume and the mouth.
    ("the server moving the rider every frame again", HALLS, HALLCHECK, "if drawing[player] or os.clock() - started < 0.5 then",
     "if false then"),
    ("the ride not drawn from the path", HALLSC, HALLCHECK, "\t\t\troot.CFrame = pathAt(path, f)\n", "\t\t\tlocal _ = pathAt(path, f)\n"),
    ("the disc back in the mouth", MAW, HALLCHECK, "\t-- A TONGUE along the lower jaw", "\tlocal throat = Instance.new(\"Part\")\n\tthroat.Name = \"Throat\"\n\t-- A TONGUE along the lower jaw"),
    # The Sky Pools.
    ("a skim out over the rim", SKYPATH, SKYCHECK, "SkyPath.SKIM_SECONDS = 2.8", "SkyPath.SKIM_SECONDS = 7"),
    ("the rider stood where the slide ended", SKY, SKYCHECK, "local landing = SkyPath.skimEnd(spec)",
     "local landing = SkyPath.point(spec, 1)"),
    ("the face shot on top of them", SKYC, SKYCHECK, "here + run * 14 + Vector3.new(0, 4.5, 0)", "here + run * 7 + Vector3.new(0, 2.2, 0)"),
    # The Sunken City.
    ("a whirlpool with no swirl", SUNK, CITYCHECK, 'swirl.Name = "WhirlSwirl"', 'swirl.Name = "Whirl"'),
    ("a bare drain shaft", SUNK, CITYCHECK, '"ShaftFlange"', '"ShaftBand"'),
    ("fish spinning when tapped", SUNKC, CITYCHECK, "local a = shoal.turn + index", "local a = clock * speed + index"),
    # The materials.
    ("bubble wrap waiting for the server", RENDER, STORY, 'AudioService.playSfx("BubbleWrap", part, true)', "local _ = part"),
    ("cracks back on soap", RENDER, STORY, "\t\tstartCrumbling(tile)\n\telse\n\t\tcrumbling[tile] = nil\n\t\tsettleTile(tile, 0.5)",
     "\t\tFissure.grow(tile, {})\n\t\tstartCrumbling(tile)\n\telse\n\t\tcrumbling[tile] = nil\n\t\tsettleTile(tile, 0.5)"),
    # The code still reads.
    ("a name never declared in the journal", JOURNAL, PARSE, "\tlocal count = 0\n\tfor _, entry in ipairs(entries) do",
     "\tlocal count = none\n\tfor _, entry in ipairs(entries) do"),
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
