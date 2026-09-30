"""Each mutation must make its checker fail. Files are restored byte for byte whatever happens."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
SERVER = ROOT / "src/Server/Services/SunkenCityService.lua"
CLIENT = ROOT / "src/Client/Services/SunkenCityClient.lua"
RIG = ROOT / "src/Shared/SeaRig.lua"
BUILDER = ROOT / "src/Server/ChunkBuilder.server.lua"
FERRIS = ROOT / "blender/gen_ferris.py"
CITY, FORMS = "check_sunkencity.py", "check_chunk_forms.py"

MUTATIONS = [
    ("the Ferris frame a stud off the floor", FERRIS, CITY, "FRAME_DOWN = 126.0", "FRAME_DOWN = 120.0"),
    ("the Ferris wheel's radius disagreeing", SERVER, CITY, "\tradius = 36, -- to the cabins' pins", "\tradius = 30, -- to the cabins' pins"),
    ("the Ferris wheel not kept off the route", SERVER, CITY,
     "near - FERRIS.reach >= EMERGE_CLEAR + ROUTE_REACH", "near >= 0"),
    ("the city not kept off the Ferris wheel", SERVER, CITY,
     "if ferrisAt and Vector3.new(point.X - ferrisAt.X, 0, point.Z - ferrisAt.Z).Magnitude < reach + FERRIS.clear then",
     "if ferrisAt and false then"),
    ("the Ferris wheel bigger than its reach", SERVER, CITY, "\treach = 40, -- the most", "\treach = 30, -- the most"),
    ("the Ferris wheel beside the street", SERVER, CITY, "\tout = 250, -- off the route's line", "\tout = 70, -- off the route's line"),
    ("SeaRig expecting a shark of the wrong size", RIG, CITY,
     "Sea_Shark = Vector3.new(6.4, 6.4, 15.6),", "Sea_Shark = Vector3.new(6.4, 6.4, 12),"),
    ("the canopy up through the surface", CLIENT, CITY, "\tcanopyDown = 3.5,", "\tcanopyDown = 1.0,"),
    ("the canopy rippling out of the water", CLIENT, CITY, "\tripple = 0.1, -- radians a frond bone", "\tripple = 0.5, -- radians a frond bone"),
    ("the ray's wings onto the tunnel's roof", CLIENT, CITY, "\trayBeat = { 0.22, 0.18 },", "\trayBeat = { 0.5, 0.4 },"),
    ("the dolphins pointing straight up", CLIENT, CITY, "\tpitch = 0.7,", "\tpitch = 1.3,"),
    ("the dolphins' fins through the surface", SERVER, CITY,
     'elseif kind == "dolphins" then rng:NextNumber(4, 6)', 'elseif kind == "dolphins" then rng:NextNumber(3, 6)'),
    ("the mesh kelp bending its own way", CLIENT, CITY,
     "joints[i + 1] = frame:PointToObjectSpace(kelpJoint(k, i, clock))",
     "joints[i + 1] = frame:PointToObjectSpace(k.marker.Position + Vector3.new(0, i * 8, 0))"),
    ("the street's kelp given no current", SERVER, CITY, "rng,\n\t\t\t\t\t\t\tdir, true)", "rng,\n\t\t\t\t\t\t\tnil, true)"),
    ("the tank's kelp given a canopy", SERVER, CITY,
     "Vector3.new(frame.RightVector.X, 0, frame.RightVector.Z).Unit, false)",
     "Vector3.new(frame.RightVector.X, 0, frame.RightVector.Z).Unit, true)"),
    ("a jellyfish's tentacles into the sea", BUILDER, CITY, "meshHeight = 7.78, surfaceOffset = 3.91",
     "meshHeight = 17.78, surfaceOffset = 3.91"),
    ("the grouper onto the tunnel's roof", CLIENT, CITY, "grouper = 1.4, shark = 1", "grouper = 1.8, shark = 1"),
    ("the Ferris wheel moved unguarded", CLIENT, CITY, 'guard("the Ferris wheel", moveFerris)', "moveFerris()"),
    ("the turtle flapping harder than checked", CLIENT, CITY,
     'SeaRig.bend2(rig, "Flipper_FL", FORWARD, math.sin(stroke) * 0.4', 'SeaRig.bend2(rig, "Flipper_FL", FORWARD, math.sin(stroke) * 0.8'),
    ("a jellyfish form nobody built", BUILDER, FORMS,
     '{ name = "Platform", material = "Jellyfish", length = 12, form = "moon" },',
     '{ name = "Platform", material = "Jellyfish", length = 12, form = "mooon" },'),
    ("a jellyfish bell at a size it has no rig for", BUILDER, FORMS,
     '{ name = "Bell", material = "Jellyfish", length = 12, form = "moon" },',
     '{ name = "Bell", material = "Jellyfish", length = 10, form = "moon" },'),
    ("a jellyfish mesh never exported", BUILDER, FORMS, 'mesh = "Jellyfish_Platform_16x12_Moon"', 'mesh = "Jellyfish_Platform_16x12_Mood"'),
    ("a jellyfish gap too long to bounce", BUILDER, FORMS,
     '{ name = "Bell", material = "Jellyfish", length = 12, form = "moon" },\n\t\t{ gap = GAP_LENGTH, name = "gap" },',
     '{ name = "Bell", material = "Jellyfish", length = 12, form = "moon" },\n\t\t{ gap = 12, name = "gap" },'),
]

paths = {m[1] for m in MUTATIONS}
originals = {path: path.read_bytes() for path in paths}
missed = []
try:
    for label, path, checker, old, new in MUTATIONS:
        text = originals[path].decode("utf-8").replace("\r\n", "\n")
        assert text.count(old) == 1, "%s: anchor found %d times" % (label, text.count(old))
        path.write_bytes(text.replace(old, new).encode("utf-8"))
        run = subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                             cwd=str(ROOT / "blender"))
        path.write_bytes(originals[path])
        caught = run.returncode != 0
        why = [line.strip() for line in (run.stdout + run.stderr).splitlines() if line.startswith("  ")][:2]
        print("%-8s %s  %s" % ("caught" if caught else "MISSED", label, "; ".join(why)[:160]))
        if not caught:
            missed.append(label)
finally:
    for path, data in originals.items():
        path.write_bytes(data)
print("\n%d of %d caught" % (len(MUTATIONS) - len(missed), len(MUTATIONS)))
