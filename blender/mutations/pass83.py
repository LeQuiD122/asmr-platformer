"""Each mutation must make its checker fail. The checkers must pass first; files are restored byte for byte.

Pass 83: the Sunken City's whirlpool as smooth meshes. A ring the wrong size or missing from what the service
expects; the rings' speeds or colours not the generator's, or an inner ring no faster; another funnel; the ripples
or the foam wound the wrong way, or the client turning the other way; wound loosely; the meshes and the parts both
or neither; the meshes stopping the camera's rays; see-through water; a ring's foam left behind, a ring or the
crest never turned; a missing mesh not sending it back to the parts; a mesh not in meshes/, or over the triangle
limit; ripples tall enough to swallow the rider; a name never declared.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]  # blender/mutations/ -> the project
S = ROOT / "src"
SUNK = S / "Server/Services/SunkenCityService.lua"
SUNKC = S / "Client/Services/SunkenCityClient.lua"
GEN = ROOT / "blender/gen_whirlpool.py"
EXT = ROOT / "blender/whirlpool_extents.json"
CITY, PARSE = "check_sunkencity.py", "check_luau_syntax.py"


def run(checker):
    return subprocess.run([sys.executable, str(ROOT / "blender" / checker)], capture_output=True, text=True,
                          cwd=str(ROOT / "blender"))


for checker in (CITY, PARSE):
    if run(checker).returncode != 0:
        sys.exit("%s fails before anything is mutated; fix that first" % checker)

MUTATIONS = [
    ("a ring the wrong size", SUNK, CITY, "\tWhirl_Band3 = Vector3.new(26.0, 17.71, 26.0),\n", "\tWhirl_Band3 = Vector3.new(26.0, 9.0, 26.0),\n"),
    ("a ring not expected", SUNK, CITY, "\tWhirl_Foam6 = Vector3.new(7.19, 33.18, 7.41),\n", ""),
    ("the hole's ring slower", SUNK, CITY, "local WHIRL_SPIN = { 0.3, 0.42, 0.6, 0.85, 1.2, 1.7 }",
     "local WHIRL_SPIN = { 0.3, 0.42, 0.6, 0.85, 1.2, 1.1 }"),
    ("another colour", SUNK, CITY, "Color3.fromRGB(22, 50, 58) }", "Color3.fromRGB(2, 5, 8) }"),
    ("another funnel", GEN, CITY, "R = 22.0          # VORTEX_R", "R = 20.0          # VORTEX_R"),
    ("ripples wound with the turn", GEN, CITY, "ARMS * (phi + WIND * lr)", "ARMS * (phi - WIND * lr)"),
    ("foam across the ripples", GEN, CITY, "phi = crest - WIND * math.log(r)", "phi = crest + WIND * math.log(r)"),
    ("the client turning it the other way", SUNKC, CITY, "CFrame.Angles(0, -ring.spin * clock, 0)", "CFrame.Angles(0, ring.spin * clock, 0)"),
    ("wound loosely", GEN, CITY, "ARMS, WIND = 6, 3.4", "ARMS, WIND = 6, 1.3"),
    ("both or neither", SUNK, CITY, "\tif not whirlOfMeshes(parent, vortex) then\n\t\twhirlOfParts(parent, vortex, rng)\n\tend\n",
     "\twhirlOfMeshes(parent, vortex)\n"),
    ("the meshes stop the camera", SUNK, CITY,
     "\t\tpart.CanQuery = false\n\t\tpart.CastShadow = false\n\t\tpart.Material = Enum.Material.SmoothPlastic\n\t\tpart.Color = colour\n",
     "\t\tpart.CastShadow = false\n\t\tpart.Material = Enum.Material.SmoothPlastic\n\t\tpart.Color = colour\n"),
    ("see-through water", SUNK, CITY, 'place(model, "Whirl_Band" .. ring, WHIRL_WATER[ring], 0, 0.12)',
     'place(model, "Whirl_Band" .. ring, WHIRL_WATER[ring], 0.3, 0.12)'),
    ("a ring's foam left behind", SUNK, CITY, '\t\tplace(model, "Whirl_Foam" .. ring, FOAM, 0.12, 0)\n', ""),
    ("the rings never turned", SUNK, CITY, '\t\tCollectionService:AddTag(model, "SunkenWhirlRing")\n\tend\n\tlocal lip = ',
     "\tend\n\tlocal lip = "),
    ("the crest never turned", SUNK, CITY, '\tCollectionService:AddTag(lip, "SunkenWhirlRing")\n', ""),
    ("a missing mesh not sending it back", SUNK, CITY, "\t\tif not whirlTemplate(name) then\n\t\t\treturn false",
     "\t\tif not whirlTemplate(name) then\n\t\t\tcontinue"),
    ("a mesh not in meshes/", EXT, CITY, '"Whirl_Lip": {', '"Whirl_Rim": {'),
    ("over the triangle limit", EXT, CITY, '"tris": 9122', '"tris": 19122'),
    ("ripples that swallow the rider", GEN, CITY, "amp = (0.1 + 0.22 * (1 - r / R))", "amp = (0.1 + 1.22 * (1 - r / R))"),
    ("a name never declared", SUNK, PARSE, 'place(lip, "Whirl_Lip", FOAM, 0, 0.04)', 'place(lipp, "Whirl_Lip", FOAM, 0, 0.04)'),
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
