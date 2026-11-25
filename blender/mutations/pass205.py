"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 205: your note of 2026-11-07, the fixes. The tape a band again, its print big, its paper solid; soda's rings slime
green, no fizz, slime's goo under it; the whirlpool slow through the funnel, the client's or the server's clock even; the
tunnel's mouths open, a wedge turned into the tunnel, the rooms not marked, the gallery's window open to the camera, the
camera never told its rooms, held in a scene; the aquarium's water clear, a pale haze, the air put back blindly; an
untouched ballot short, the gates' start medium, the keys' choice taken by any run, the workshop's start a default one,
a workshop run's choice carried over, the keys Neon, the keys back on the gates; the gaps easy, the corner overreaching.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
TELE = S / "Client/Services/Teleprinter.lua"
RENDER = S / "Client/Services/DeformationRenderer.lua"
PATH = S / "Shared/SunkenPath.lua"
SUNKC = S / "Client/Services/SunkenCityClient.lua"
SUNKS = S / "Server/Services/SunkenCityService.lua"
VIEW = S / "Client/Services/ViewModeService.lua"
HUB = S / "Server/Services/HubService.lua"
LAYOUT = S / "Shared/LobbyLayout.lua"
LEVEL = S / "Server/Services/LevelService.lua"
TOUCH, FEEL, SUNK, HUBCHECK, HALLS = "check_touch.py", "check_feel.py", "check_sunkencity.py", "check_hub.py", "check_halls.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (TOUCH, FEEL, SUNK, HUBCHECK, HALLS):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ('the tape a band again', TELE, TOUCH, 'local STRIP = { height = 26,', 'local STRIP = { height = 46,'),
    ('the tape in big print', TELE, TOUCH, 'type = 15, paper = 0.12,', 'type = 28, paper = 0.12,'),
    ('the tape on solid paper', TELE, TOUCH, 'strip.BackgroundTransparency = STRIP.paper', 'strip.BackgroundTransparency = 0'),
    ("soda's rings slime green", RENDER, FEEL,
     '\t\t\t\telseif ctx.material == "JelloSoda" then MaterialAppearance.Appearances.JelloSoda.color:Lerp(Color3.new(1, 1, 1), 0.55)\n', ''),
    ('no fizz on soda', RENDER, FEEL, '\t\t\t\tSLIME.fizz(tile, feet[1] and feet[1].position or tile.Position)\n', '\t\t\t\tlocal _ = feet\n'),
    ("slime's goo under soda", RENDER, FEEL, 'if ctx.material ~= "JelloSoda" and (not marks[tile] or #marks[tile] < 3) then',
     'if (not marks[tile] or #marks[tile] < 3) then'),
    ('the funnel as slow as ever', PATH, SUNK, 'SunkenPath.FUNNEL_TIME = 0.4', 'SunkenPath.FUNNEL_TIME = 0.5'),
    ("the client's drain clock even", SUNKC, SUNK, 'local u = SunkenPath.drainShare(t, current.seconds)',
     'local u = math.max(0, t / current.seconds)'),
    ("the server's drain clock even", SUNKS, SUNK,
     'local u = if SunkenPath and SunkenPath.drainShare then SunkenPath.drainShare(t, seconds) else t / seconds',
     'local u = t / seconds'),
    ("the tower's mouth open", SUNKS, SUNK, '\tmouth(xc + ROT_R - ROT_WALL / 2 - 0.5,', '\tlocal _ = (xc + ROT_R - ROT_WALL / 2 - 0.5,'),
    ("the gallery's mouth open", SUNKS, SUNK, '\tmouth(tunnelTo - 0.8, 1.2, TUNNEL_W / 2 + 0.6, ty + TUNNEL_H, wallColour)\n', ''),
    ('a wedge turned into the tunnel', SUNKS, SUNK,
     '* (if side < 0 then CFrame.Angles(math.pi, 0, 0) else CFrame.Angles(0, 0, math.pi))', '* CFrame.identity'),
    ('the rooms not marked', SUNKS, SUNK, 'CollectionService:AddTag(keep, "CameraRoom")', 'CollectionService:AddTag(keep, "Room")'),
    ("the gallery's window open to the camera", SUNKS, SUNK,
     '\tcameraRoom(Vector3.new(ROOM_L - 0.6, ROOM_H - 0.6, ROOM_W - 0.6), room * CFrame.new(0, ty + ROOM_H / 2, 0), true)\n', ''),
    ('the camera never told its rooms', VIEW, SUNK, '\tkeep.watch()\n', ''),
    ('the camera held in a scene', VIEW, SUNK, 'if state.view == "third" and not scene then\n\t\tkeep.hold(',
     'if state.view == "third" then\n\t\tkeep.hold('),
    ("the aquarium's water clear", SUNKC, SUNK, 'MURK = { density = 0.52,', 'MURK = { density = 0.2,'),
    ("the aquarium's murk a pale haze", SUNKC, SUNK, 'colour = Color3.fromRGB(18, 56, 64), decay', 'colour = Color3.fromRGB(200, 220, 230), decay'),
    ('the air put back blindly', SUNKC, SUNK, 'if atmosphere.Parent and math.abs(atmosphere.Density - MURK.density) < 0.05 then',
     'if atmosphere.Parent then'),
    ('an untouched ballot short', HUB, HUBCHECK, 'local LENGTH_ORDER = { "long", "medium", "short" }',
     'local LENGTH_ORDER = { "short", "medium", "long" }'),
    ("the gates' start medium", HUB, HUBCHECK, 'local DEFAULT_RUN = { mode = "chill", length = "long" }',
     'local DEFAULT_RUN = { mode = "chill", length = "medium" }'),
    ("the keys' choice taken by any run", HUB, HUBCHECK,
     'length = if fromWorkshop then winner("length", LENGTH_ORDER) :: string else DEFAULT_RUN.length,',
     'length = winner("length", LENGTH_ORDER) :: string,'),
    ("the workshop's start a default one", HUB, HUBCHECK, 'HubService.callVote(true)', 'HubService.callVote(false)'),
    ("a workshop run's choice carried over", HUB, HUBCHECK,
     '\t\t-- Taken: the next vote is the gates\' again unless the workshop calls it.\n\t\tfromWorkshop = false\n', ''),
    ('the keys Neon', HUB, HUBCHECK, '\t\tinlay.Material = Enum.Material.SmoothPlastic\n\t\tinlay.Color = row.colour',
     '\t\tinlay.Material = Enum.Material.Neon\n\t\tinlay.Color = row.colour'),
    ('the keys back on the gates', LAYOUT, HUBCHECK, 'lengthRow = Vector3.new(-66, 0, 95),', 'lengthRow = Vector3.new(0, 0, -94),'),
    ('the gaps easy again', LEVEL, HALLS, 'local CHUNK_GAP = 6', 'local CHUNK_GAP = 5'),
    ('the climb easy again', LEVEL, HALLS, 'local STEP_CHOICES = { 3, 4, 4, 1, 4, 3, 3 }', 'local STEP_CHOICES = { 3, 4, 3, 0, 4, 3, 2 }'),
    ('the corner overreaching', LEVEL, HALLS, 'local CORNER_BAR = 8', 'local CORNER_BAR = 9'),
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
