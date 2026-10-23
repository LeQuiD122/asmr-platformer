"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 28: the Studio test panel and the one chord. A test panel that works in the live game (listened to, its
remote made, built, or not checking again), tokens added somewhere new, and an ending whose chord has
nothing to fall back on.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
ECON = S / "Server/Services/EconomyService.lua"
BOOT = S / "Server/Bootstrap.server.lua"
DEV = S / "Client/Services/DevPanelClient.lua"
CINEMA = S / "Client/Services/Cinema.lua"
SHORE = S / "Client/Services/CityShoreClient.lua"
SKY = S / "Client/Services/SkyPoolsClient.lua"
HALLS = S / "Client/Services/FloodedHallsClient.lua"
SHOP, STORY, PARSE = "check_shop.py", "check_story.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (SHOP, STORY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    # The test panel stays in Studio.
    ("the panel listened to live", ECON, SHOP, '\tif RunService:IsStudio() then\n\t\tlocal dev = events:WaitForChild("DevPanel", 10)',
     '\tif true then\n\t\tlocal dev = events:WaitForChild("DevPanel", 10)'),
    ("the panel not checking again", ECON, SHOP, "local function onDev(player: Player, action: any)\n\tif not RunService:IsStudio() then",
     "local function onDev(player: Player, action: any)\n\tif false then"),
    ("the panel's remote made live", BOOT, SHOP, 'if game:GetService("RunService"):IsStudio() then\n\tensureRemoteEvent(remoteEventsFolder, "DevPanel")',
     'if true then\n\tensureRemoteEvent(remoteEventsFolder, "DevPanel")'),
    ("the panel built live", DEV, SHOP, "function DevPanelClient.start()\n\tif not RunService:IsStudio() then",
     "function DevPanelClient.start()\n\tif false then"),
    ("tokens added somewhere new", ECON, SHOP, "\t\tdata.SecondChances = (data.SecondChances or 0) + 1\n",
     "\t\tdata.SecondChances = (data.SecondChances or 0) + 1\n\t\tdata.Tokens += 5\n"),
    # The one chord.
    ("no stand-in in Cinema", CINEMA, STORY, "local alt = options and options.alt and folder and folder:FindFirstChild(options.alt)",
     "local alt = nil"),
    ("City Shore's chord with nothing behind it", SHORE, STORY, ', alt = "EndChord", altPitch = 0.89 })', " })"),
    ("the Sky Pools' chord with nothing behind it", SKY, STORY, ', alt = "EndChord", altPitch = 1.19 })', " })"),
    ("the Halls' chord with nothing behind it", HALLS, STORY, 'sound("HallsChord", nil, 0.7, 1, false) or sound("EndChord", nil, 0.7, 1, false)',
     'sound("HallsChord", nil, 0.7, 1, false)'),
    # The code still reads.
    ("a name never declared in the stand-in", CINEMA, PARSE, "made.PlaybackSpeed = (options.altPitch or 1) * (options.pitch or 1)",
     "made.PlaybackSpeed = (options.altPitch or 1) * (options.pitch or one)"),
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
