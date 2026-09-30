"""Each mutation must make its checker fail. Files are restored byte for byte whatever happens."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
SERVER = ROOT / "src/Server/Services/SunkenCityService.lua"
CLIENT = ROOT / "src/Client/Services/SunkenCityClient.lua"
NPC = ROOT / "src/Server/Services/Townsfolk.lua"
RIG = ROOT / "src/Shared/SeaRig.lua"
CITY = "check_sunkencity.py"

MUTATIONS = [
    ("the tunnel's panes tappable again", SERVER, CITY,
     'if item:IsA("BasePart") and item.Name == "ViewingWindow" then',
     'if item:IsA("BasePart") and (item.Name == "ViewingWindow" or item.Name == "TunnelGlass") then'),
    # (the flood's two client mutations moved to mut_pass11: the server draws the water now)
    ("the swimmers under the route again", SERVER, CITY,
     "local across = math.min(SWIM_REACH - math.abs(out), math.abs(out) - ROUTE_REACH + 2)",
     "local across = SWIM_REACH - math.abs(out)"),
    ("the shoals under the route again", SERVER, CITY,
     "rng:NextNumber(15, SHOAL_OUT))", "rng:NextNumber(-SHOAL_OUT, SHOAL_OUT))"),
    ("the rays up through the surface", SERVER, CITY,
     'elseif kind == "ray" then rng:NextNumber(5.5, 11)', 'elseif kind == "ray" then rng:NextNumber(3, 11)'),
    ("the Deco tower a different height", SERVER, CITY,
     '{ name = "Deco", height = 282,', '{ name = "Deco", height = 250,'),
    ("the Twin towers wider than their square", SERVER, CITY,
     '{ name = "Twin", height = 300, reach = 38,', '{ name = "Twin", height = 300, reach = 30,'),
    ("the leaning tower's front off the floor", SERVER, CITY, "lean = 5, sink = 1.5,", "lean = 5, sink = 0.5,"),
    ("a landmark where the things at the back swim", SERVER, CITY,
     "share = 0.22, out = 330, side = 1,", "share = 0.22, out = 360, side = 1,"),
    ("utility poles by the route", SERVER, CITY, "if row % 2 == 0 and near >= 70 and near <= 250",
     "if row % 2 == 0 and near >= 40 and near <= 250"),
    ("the attendant deaf to the glass", SERVER, CITY, "Townsfolk.react(heard)", "Townsfolk.react(nil)"),
    ("the one who watches standing in the air", SERVER, CITY, "deco * CFrame.new(0, 160, -20)", "deco * CFrame.new(0, 160, -30)"),
    ("nobody when a character cannot be built", NPC, CITY, "return plainFigure(name, colours)", "return Instance.new(\"Model\")"),
    ("SeaRig expecting the wrong twin towers", RIG, CITY, "Landmark_TwinBody = Vector3.new(68, 300, 24)",
     "Landmark_TwinBody = Vector3.new(68, 280, 24)"),
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
        print("%-8s %s  %s" % ("caught" if caught else "MISSED", label, "; ".join(why)[:170]))
        if not caught:
            missed.append(label)
finally:
    for path, data in originals.items():
        path.write_bytes(data)
print("\n%d of %d caught" % (len(MUTATIONS) - len(missed), len(MUTATIONS)))
