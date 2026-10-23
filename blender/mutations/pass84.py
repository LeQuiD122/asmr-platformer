"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 84: the flume ridden like a person, and the mouth that has you. The client, Poses and the server disagreeing on
the ride; laid back through the floor, floating over it, or barely laid back; the server's clock read every frame;
straight lines between the path's steps; stood in the trough; the shots facing the roof; no wake; no thoughts, too
few, a dash in one, or one still up after the ride; no growl, or a growl in the tube; the mouth lit before it opens;
time never stopping; hanging among the teeth; not in it when it shuts; it opening or shutting without a roar or a
hit; no breath; a shot in the pit's wall or inside a jaw; no red in its throat, steady light, saliva that never
snaps, Neon; no water, or water that never runs; the growl not listed; legs that never move; never panicking; a
name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
HC = S / "Client/Services/FloodedHallsClient.lua"
HS = S / "Server/Services/FloodedHallsService.lua"
MAW = S / "Client/Services/Maw.lua"
POSES = S / "Shared/Poses.lua"
BOOT = S / "Server/Bootstrap.server.lua"
HALLS, PARSE = "check_halls.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (HALLS, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the tube a different length", HC, HALLS, "local HELIX = 0.68 --", "local HELIX = 0.6 --"),
    ("the pose a different ride", POSES, HALLS, "Poses.FLUME_SECONDS = 11 --", "Poses.FLUME_SECONDS = 12 --"),
    ("laid back through the floor", HC, HALLS, "local LIE_DROP = 2.4\n", "local LIE_DROP = 4\n"),
    ("floating over the floor", HC, HALLS, "local LIE_DROP = 2.4\n", "local LIE_DROP = 0.5\n"),
    ("barely laid back", POSES, HALLS, "Poses.FLUME_RECLINE = math.rad(62)", "Poses.FLUME_RECLINE = math.rad(20)"),
    ("the server's clock every frame", HC, HALLS, "local t = os.clock() - current.clockAt",
     "local t = workspace:GetServerTimeNow() - current.began"),
    ("straight lines between steps", HC, HALLS, "\n\t\t+ (3 * p1 - p0 - 3 * p2 + p3) * u * u * u)\n", ")\n"),
    ("stood in the trough", HC, HALLS, "return frame * CFrame.new(0, -LIE_DROP * w, 0) * CFrame.Angles(recline * w, 0, 0)",
     "return frame"),
    ("the shots facing the roof", HC, HALLS, "pathAt(path, math.min(f, HELIX - 0.005)).LookVector", "root.CFrame.LookVector"),
    ("no wake", HC, HALLS, "current.wake = startWake(root)", "current.wake = nil"),
    ("no thoughts", HC, HALLS, "\t\t\t\tCinema.think(Players.LocalPlayer.Character, thought[2] :: string, thought[3] :: number)\n", ""),
    ("a dash in a thought", HC, HALLS, '"Too fast. Way too fast!"', '"Too fast -- way too fast!"'),
    ("too few thoughts", HC, HALLS, '\t{ 7.7, "Where is the bottom?!", 1.6 },\n\t{ 9.7, "...what was that?", 1.3 },\n', ""),
    ("a thought after the ride", HC, HALLS, '{ 9.7, "...what was that?", 1.3 }', '{ 10.2, "...what was that?", 1.3 }'),
    ("no growl", HC, HALLS, 'current.growl = sound("MawGrowl", BASS, 0.6, 0.18, false)', "current.growl = nil"),
    ("a growl in the tube", HC, HALLS, "local GROWL_AT = 0.84", "local GROWL_AT = 0.5"),
    ("lit before it opens", HC, HALLS, "\tif m < JAWS.reveal then\n\t\tMaw.light(mouth, 0)\n",
     "\tif m < JAWS.reveal then\n\t\tMaw.light(mouth, 0.5)\n"),
    ("time never stopping", HC, HALLS, "\telseif m < JAWS.into then\n\t\treturn HANG\n", "\telseif m < JAWS.into then\n\t\treturn 30\n"),
    ("hanging among the teeth", HC, HALLS, "\treveal = 0.8,", "\treveal = 1.9,"),
    ("not in it when it shuts", HC, HALLS, "\tsnap = 5.0,", "\tsnap = 4.1,"),
    ("it opens without a sound", HC, HALLS, '\t\tkeep(current, sound("MawRoar", BASS, 1, 0.32, false))\n', ""),
    ("it opening not hit", HC, HALLS, "\t\tCinema.impact(1.4)\n", ""),
    ("it shutting not hit", HC, HALLS, "\t\t\tCinema.impact(2)\n\t\t\tCinema.shake(3.8)\n", "\t\t\tCinema.shake(3.8)\n"),
    ("no breath", HC, HALLS, "\t\tMaw.breathe(mouth, 10)\n", ""),
    ("a shot in the pit's wall", HC, HALLS, "inward * (20 - 2 * k) + side * 8\n", "inward * (20 - 2 * k) + side * 80\n"),
    ("a shot inside a jaw", HC, HALLS, "opens * 55 + inward * 24 + side * 14, hinge.Position", "opens * 6 + inward * 2 + side * 1, hinge.Position"),
    ("no red in its throat", MAW, HALLS, "gullet.Color = Color3.fromRGB(255, 56, 40)", "gullet.Color = Color3.fromRGB(255, 255, 255)"),
    ("steady light", MAW, HALLS, "dip = if math.noise(clock * 3.1, 0.5) > 0.38 then 0.4 else 1", "dip = 1"),
    ("saliva that never snaps", MAW, HALLS, "local snapped = span > strand.snaps", "local snapped = false"),
    ("Neon in the mouth", MAW, HALLS, "\t\t\tpart.Transparency = 0.35\n", "\t\t\tpart.Transparency = 0.35\n\t\t\tpart.Material = Enum.Material.Neon\n"),
    ("no water", HS, HALLS, '\t\tgame:GetService("CollectionService"):AddTag(water, "FlumeWater")\n', ""),
    ("water that never runs", HC, HALLS, "pcall(moveWater, os.clock())", "pcall(moveWater, 0)"),
    ("the growl not listed", BOOT, HALLS, '"MawGrowl", "MawRoar", "TownsfolkVoice_x9"', '"MawRoar", "TownsfolkVoice_x9"'),
    ("legs that never move", POSES, HALLS, "local hip = math.pi / 2 - Poses.FLUME_RECLINE * lie", "local hip = 0"),
    ("never panicking", POSES, HALLS, "local toPanic = ease((t - 2.8) / 0.8)", "local toPanic = 0"),
    ("a name never declared", HC, PARSE, "local tumble = current.tumble or 0", "local tumble = current.tumble or zero"),
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
