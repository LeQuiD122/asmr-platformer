"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
SERVER = ROOT / "src/Server/Services/SunkenCityService.lua"
CLIENT = ROOT / "src/Client/Services/SunkenCityClient.lua"
PATH = ROOT / "src/Shared/SunkenPath.lua"
POSES = ROOT / "src/Shared/Poses.lua"
NPC = ROOT / "src/Server/Services/Townsfolk.lua"
BOOT = ROOT / "src/Client/Bootstrap.client.lua"
CITY, PARSE = "check_sunkencity.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CITY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("the newer avatar joints not found", POSES, CITY,
     'elseif item:IsA("AnimationConstraint") and not found[item.Name] then', 'elseif false then'),
    ("the newer avatar joints never turned", POSES, CITY,
     "attachment.CFrame = joint.rest * by", "attachment.CFrame = joint.rest"),
    ("no head over heels down the shaft", PATH, CITY,
     "local flip = 4 * math.pi * e * e * (3 - 2 * e)", "local flip = 0"),
    ("no grab at the whirlpool", PATH, CITY,
     "local grab = 1 - math.clamp(u / 0.05, 0, 1)", "local grab = 0"),
    ("the rider's own client adding speed", SERVER, CITY,
     "root:SetNetworkOwner(nil)", "root:GetNetworkOwner()"),
    ("a thin sluice floor again", SERVER, CITY,
     '"ShaftFloor", Vector3.new(DRAIN_R * 2 + 2, 6,', '"ShaftFloor", Vector3.new(DRAIN_R * 2 + 2, 1,'),
    ("no trail off the rider", SERVER, CITY, 'trail.Name = "DrainTrail"', 'trail.Name = "Trail"'),
    ("no splash at the bottom", SERVER, CITY, "splashes:Emit(count)", "splashes:Emit(0)"),
    ("the client letting speed build up", CLIENT, CITY,
     "rider.AssemblyLinearVelocity = Vector3.zero", "rider.AssemblyLinearVelocity = rider.AssemblyLinearVelocity"),
    ("no close shot of the grab", CLIENT, CITY, "\tif u < 0.1 then\n\t\tlocal out", "\tif false then\n\t\tlocal out"),
    ("no shot from the bottom", CLIENT, CITY, "\tif u >= 0.9 then\n\t\tlocal eye", "\tif false then\n\t\tlocal eye"),
    ("the camera leaving before the station is seen", CLIENT, CITY,
     "\t\tcutscene.revealShot(current.reveal, r)\n", "\t\tcutscene.finish()\n"),
    ("the people's joints Motor6D only", NPC, CITY, "Poses.joints(model)", "{}"),
    ("the attendant just standing there", NPC, CITY, "function Townsfolk.panic(", "function Townsfolk.stand("),
    ("the attendant never swimming", NPC, CITY, "function POSES.swim(", "function POSES.float("),
    ("the cap never put back", NPC, CITY, "\t\t\tputBack(npc)\n", "\t\t\tlocal _ = npc\n"),
    ("the flood never telling the attendant", SERVER, CITY, "Townsfolk.panic(function(): number", "Townsfolk.find(function(): number"),
    ("the attendant with no way out", SERVER, CITY, 'Townsfolk.route("Attendant", aq.escape)', 'local _ = aq.escape'),
    ("no jets through the cracks", SERVER, CITY, 'loose("CrackJet"', 'loose("Jet"'),
    ("no surge across the floor", SERVER, CITY, 'loose("Surge"', 'loose("Wave"'),
    ("the notice left floating", SERVER, CITY, "torn.part.CFrame = torn.rest", "torn.part.CFrame = torn.part.CFrame"),
    ("a still whirlpool throat", SERVER, CITY, 'block(parent, "WhirlThroat"', 'block(parent, "WhirlHole"'),
    ("an unstarted client told apart from nothing", SERVER, CITY, "\t\tstudio.loads = true\n", "\t\tlocal _ = true\n"),
    ("the Ferris wheel on one side only", SERVER, CITY, "for _, side in ipairs({ 1, -1 }) do", "for _, side in ipairs({ 1 }) do"),
    ("the old Bootstrap, starting nothing", BOOT, CITY, '"SkyPoolsClient", "SunkenCityClient"', '"SkyPoolsClient"'),
    ("the flood read before it is declared", SERVER, PARSE, "\t\t\ttable.insert(notices, item)", "\t\t\ttable.insert(flood.panes, item)"),
    ("a local read outside its block", NPC, PARSE, "\tbubbles:Destroy()\nend", "\tbubbles:Destroy()\n\tprint(shape)\nend"),
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
