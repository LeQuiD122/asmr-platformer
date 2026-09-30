"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
SERVER = ROOT / "src/Server/Services/SunkenCityService.lua"
CLIENT = ROOT / "src/Client/Services/SunkenCityClient.lua"
PATH = ROOT / "src/Shared/SunkenPath.lua"
POSES = ROOT / "src/Shared/Poses.lua"
SKY = ROOT / "src/Server/Services/SkyPoolsService.lua"
APPEAR = ROOT / "src/Shared/MaterialAppearance.lua"
CITY, SKYCHECK, PARSE = "check_sunkencity.py", "check_skypools.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CITY, SKYCHECK, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the flood not water you can swim in", SERVER, CITY,
     "slab(space, space.bottom, depth, Enum.Material.Water)", "slab(space, space.bottom, depth, Enum.Material.Air)"),
    ("the water never going back down", SERVER, CITY,
     "slab(space, space.top - over, over + 1, Enum.Material.Air)", "slab(space, space.top - over, over + 1, Enum.Material.Water)"),
    ("the gallery filled at the wrong rate", SERVER, CITY,
     "local rate = (room.top - room.bottom) / TAP.rise", "local rate = (room.top - room.bottom) / 3"),
    ("washing people out again", SERVER, CITY, "\trise = 8, -- seconds for the gallery to fill\n",
     "\trise = 8, -- seconds for the gallery to fill\n\twash = 1.5,\n"),
    ("no time to swim", SERVER, CITY, "\thold = 40,", "\thold = 20,"),
    ("draining in an instant", SERVER, CITY, "\tdrain = 6,", "\tdrain = 1,"),
    ("a flood left behind in the next level", SERVER, CITY,
     "table.insert(swimWater.fills, { cf = space.volume.CFrame, size = space.volume.Size })", "local _ = space"),
    ("the water never cleared", SERVER, CITY,
     "\t\tfor _, space in ipairs(spaces) do\n\t\t\tterrain:FillBlock(space.volume.CFrame, space.volume.Size + Vector3.new(4, 4, 4), Enum.Material.Air)\n\t\tend\n\t\tfor _, thing in ipairs(made) do",
     "\t\tfor _, thing in ipairs(made) do"),
    ("the torrent pouring on under the water", SERVER, CITY, "falls.Rate = 220 * above", "falls.Rate = 220"),
    ("nothing floating up", SERVER, CITY, 'loose("Leaflet"', 'loose("Leaf"'),
    ("boxes of see-through water again", SERVER, CITY, 'loose("SeaLanding"', 'loose("FloodWater"'),
    ("terrain rewritten while it stands still", SERVER, CITY, "if math.abs(level - written) > 0.02 then", "if true then"),
    ("the chest facing away again", SERVER, CITY,
     "chestAt * CFrame.new(0, -1.55, 0) * CFrame.Angles(0, math.pi, 0)", "chestAt * CFrame.new(0, -1.55, 0)"),
    ("the server's ride stiff again", SERVER, CITY, "frame *= SunkenPath.tumble(u, os.clock())", "frame = frame"),
    ("the server not flailing the rider", SERVER, CITY, "Poses.turn(joint, turn)", "local _ = joint"),
    ("the rider's joints left turned", SERVER, CITY, "\t\ttask.wait()\n\tend\n\tgiveBack()", "\t\ttask.wait()\n\tend\n\tlocal _ = giveBack"),
    ("the hello not heard", SERVER, CITY, 'if what == "hello" then', 'if what == "hi" then'),
    ("not listening when a client says hello", SERVER, CITY, "task.spawn(drainRemote)", "local _ = drainRemote"),
    ("no Studio check", SERVER, CITY, "task.defer(studio.check)", "local _ = studio.check"),
    ("no Studio notice", SERVER, CITY, "\t\t\t\t\t\tstudio.notice(player)", "\t\t\t\t\t\tlocal _ = player"),
    ("the Ferris wheel's spots cut back to five", SERVER, CITY,
     "shares = { 0.55, 0.62, 0.48, 0.7, 0.3, 0.4, 0.66, 0.35, 0.52, 0.25, 0.44, 0.75, 0.58, 0.2, 0.8, 0.15 }",
     "shares = { 0.55, 0.62, 0.48, 0.7, 0.3 }"),
    ("the sound under water crisp again", CLIENT, CITY,
     "SoundService.AmbientReverb = Enum.ReverbType.UnderWater", "SoundService.AmbientReverb = Enum.ReverbType.NoReverb"),
    ("the client's own flail", CLIENT, CITY, "local turn = Poses.flail(name, t, w, r6)", "local turn = CFrame.identity"),
    ("the client never saying hello", CLIENT, CITY, 'rideEvent:FireServer("hello", SunkenCityClient.VERSION)', "-- no hello"),
    ("a LocalScript copy never starting", CLIENT, CITY, 'if (script :: any):IsA("LocalScript") then', "if false then"),
    ("Poses without the flail", POSES, CITY, "function Poses.flail(", "function Poses.flap("),
    ("Sky Pools' pools Glass again", SKY, SKYCHECK,
     "local part = block(parent, name, size, cf, WATER, SHEEN, false)",
     "local part = block(parent, name, size, cf, WATER, Enum.Material.Glass, false)"),
    ("the soda Glass again", APPEAR, SKYCHECK,
     "material = Enum.Material.SmoothPlastic,\n\t\ttransparency = 0.2,\n\t\treflectance = 0.08,",
     "material = Enum.Material.Glass,\n\t\ttransparency = 0.2,\n\t\treflectance = 0.08,"),
    ("a call split over two lines", CLIENT, PARSE, 'print("SunkenCityClient: running, " .. SunkenCityClient.VERSION)',
     'print\n("SunkenCityClient: running, " .. SunkenCityClient.VERSION)'),
    ("an if with no then", CLIENT, PARSE, 'if first == "flail" then', 'if first == "flail"'),
    ("a statement after continue", CLIENT, PARSE, "\t\t\tswimmers[marker] = nil\n\t\t\tcontinue\n\t\tend\n\t\tif (marker.Position",
     "\t\t\tswimmers[marker] = nil\n\t\t\tcontinue\n\t\t\tprint(1)\n\t\tend\n\t\tif (marker.Position"),
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
        why = [line.strip() for line in (result.stdout + result.stderr).splitlines() if line.startswith("  ")][:2]
        print("%-8s %s  %s" % ("caught" if caught else "MISSED", label, "; ".join(why)[:170]))
        if not caught:
            missed.append(label)
finally:
    for path, data in originals.items():
        path.write_bytes(data)
print("\n%d of %d caught" % (len(MUTATIONS) - len(missed), len(MUTATIONS)))
