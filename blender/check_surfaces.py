"""Harrow Bay's surfaces: the textures of the lobby and of the levels' buildings (the hundred-and-sixty-ninth pass onward).

Run with plain Python from the project root:  python blender/check_surfaces.py

What it holds:
  THE MAPS. Every surface gen_surfaces.py makes (its MANIFEST) has its three maps in textures/, each 1024 square and
  tiling with no seam; the colour maps light and near white (a MaterialVariant's ColorMap is multiplied by the part's
  own colour, so a dark or coloured map would darken or tint every part it dresses); the normal maps true unit normals
  facing out (OpenGL, green up); the roughness maps grey.
  WHO WEARS THEM. MaterialAppearance.SURFACES names each of the nine Harrow surfaces for exactly the material its
  MaterialVariant is made on (a variant only shows on a part of its BaseMaterial); a level's buildings take only the
  stone, wood, render and marble ones; a part that already wears a variant, a textured mesh, or anything worn by a
  character keeps its own; a variant not yet made is skipped and said once. The lobby is dressed once it is built, and
  its decks are slate so the flagstones reach them; every level's world is dressed as it arrives, wherever it is put
  (the workspace, or its Levels folder), and each named there is one a service builds.
  WHAT THEY ARE BUILT OF. The Sunken City's buildings and the Sky Pools' roof are built of what they are (render, cast
  stone, slate, coursed stone, marble, timber), never plain plastic, which no surface reaches; the squish room is
  boards, render, timber and painted iron, dressed like the lobby; and no dressing ever reaches a chunk's own part.
  ONE MAKER. The slab, the backdrop's concrete and the pool tile are gen_surfaces.py's alone (gen_pbr.py no longer
  writes them), and HANDOFF says how to make each of the nine variants, on the right material, at the right size.

Exits non-zero on any failure.
"""
import ast
import pathlib
import re
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
problems = []


def fail(message):
    problems.append(message)


def read(path):
    return path.read_text(encoding="utf-8").replace("\r\n", "\n") if path.exists() else ""


GEN = read(ROOT / "blender" / "gen_surfaces.py")
PBR = read(ROOT / "blender" / "gen_pbr.py")
LOOK = read(SRC / "Shared" / "MaterialAppearance.lua")
HUB = read(SRC / "Server" / "Services" / "HubService.lua")
BOOT = read(SRC / "Server" / "Bootstrap.server.lua")
HANDOFF = read(ROOT / "HANDOFF.md")

# ===================================================================== the manifest
manifest = {}
for name, recipe, base, studs in re.findall(r"^    '(\w+)': \((\w+), '([\w ,]+)', (\d+), ", GEN, re.M):
    manifest[name] = (recipe, base, int(studs))
if len(manifest) < 12:
    fail("gen_surfaces.py: its MANIFEST cannot be read (%d surfaces found)" % len(manifest))
for name, (recipe, _, _) in manifest.items():
    if "def %s(" % recipe not in GEN:
        fail("gen_surfaces.py: %s is made by %s, which is not there" % (name, recipe))


# ===================================================================== the maps
def tiles(a):
    a = a.astype(float)
    inside = np.abs(np.diff(a, axis=1)).mean() + np.abs(np.diff(a, axis=0)).mean()
    across = np.abs(a[:, 0] - a[:, -1]).mean() + np.abs(a[0, :] - a[-1, :]).mean()
    return across <= inside * 1.6 + 1.0


for name in manifest:
    for kind in ("Color", "Normal", "Roughness"):
        path = ROOT / "textures" / ("%s_%s.png" % (name, kind))
        if not path.exists():
            fail("textures/%s is missing: run python blender/gen_surfaces.py" % path.name)
            continue
        img = Image.open(path)
        if img.size != (1024, 1024) or img.mode != "RGB":
            fail("textures/%s is %s %s, not a 1024 square RGB map" % (path.name, img.size, img.mode))
            continue
        a = np.asarray(img)
        if not tiles(a):
            fail("textures/%s does not tile: its edges do not meet" % path.name)
        if kind == "Color":
            mean = a.reshape(-1, 3).mean(axis=0) / 255.0
            if not 0.68 <= mean.mean() <= 0.99:
                fail("textures/%s averages %.2f: a colour map multiplies the part's colour, so it must be light"
                     % (path.name, mean.mean()))
            if mean.max() - mean.min() > 0.07:
                fail("textures/%s is tinted %s: a colour map multiplies the part's colour, so it must be near white"
                     % (path.name, np.round(mean, 2)))
        elif kind == "Normal":
            n = a.reshape(-1, 3).astype(float) / 127.5 - 1.0
            length = np.sqrt((n * n).sum(axis=1))
            if np.abs(length - 1).max() > 0.03 or n[:, 2].min() <= 0.2:
                fail("textures/%s is not a normal map of unit normals facing out" % path.name)
            if np.abs(n[:, :2].mean(axis=0)).max() > 0.03:
                fail("textures/%s leans to one side on average (its green or red is off centre)" % path.name)
        else:
            if not (a[..., 0] == a[..., 1]).all() or not (a[..., 1] == a[..., 2]).all():
                fail("textures/%s is not grey" % path.name)
            if not 0.05 <= a.mean() / 255.0 <= 0.98:
                fail("textures/%s averages %.2f, out of a roughness map's range" % (path.name, a.mean() / 255.0))

# ===================================================================== who wears them
surfaces = dict(re.findall(r"^\t\[Enum\.Material\.(\w+)\] = \"(\w+)\",", LOOK[LOOK.find("MaterialAppearance.SURFACES = {"):
                                                                              LOOK.find("MaterialAppearance.LEVEL_SURFACES")],
                           re.M))
level = re.findall(r"^\t\[Enum\.Material\.(\w+)\] = true,", LOOK[LOOK.find("MaterialAppearance.LEVEL_SURFACES = {"):
                                                                   LOOK.find("local surfacesSaid")], re.M)
if len(surfaces) != 9:
    fail("MaterialAppearance: SURFACES names %d surfaces, not the nine Harrow ones" % len(surfaces))
for material, name in surfaces.items():
    if name not in manifest:
        fail("MaterialAppearance: %s is put on %s parts, and gen_surfaces.py does not make it" % (name, material))
    elif manifest[name][1] != material:
        fail("MaterialAppearance: %s is put on %s parts, but its variant is made on %s, so it would never show"
             % (name, material, manifest[name][1]))
if not level or any(m not in surfaces for m in level) or "Metal" in level or "Fabric" in level:
    fail("MaterialAppearance: a level's buildings are dressed in something that is not one of the nine, or in its "
         "machinery's metal or its costume's cloth")
for needle, why in (
    ('if not item:IsA("BasePart") or item.MaterialVariant ~= "" then', "a part that already wears a variant loses it"),
    ('if (item:IsA("MeshPart") and item.TextureID ~= "") or item:FindFirstChildOfClass("SurfaceAppearance") then',
     "a textured mesh is dressed over its own texture"),
    ("if name and have[name] and not worn(item) then", "a variant not yet made, or a character's clothes, is dressed"),
    # (Harrow Bay's nine are looked for one by one, and so, since the hundred-and-eighty-fifth pass, is a level's own.)
    ("for _, name in pairs(MaterialAppearance.SURFACES) do\n\t\tlocal variant = MaterialService:FindFirstChild(name, true)\n"
     "\t\thave[name] = variant ~= nil and variant:IsA(\"MaterialVariant\")\n\t\tif not have[name] then",
     "a variant not yet made is taken as made"),
    ("for _, name in ipairs(names) do\n\t\t\tlocal variant = MaterialService:FindFirstChild(name, true)\n"
     "\t\t\thave[name] = variant ~= nil and variant:IsA(\"MaterialVariant\")",
     "a level's own surface not yet made is taken as made"),
    ("if model:FindFirstChildOfClass(\"Humanoid\") then\n\t\t\treturn true", "a character's clothes are dressed"),
    ("if #missing > 0 and not surfacesSaid then\n\t\tsurfacesSaid = true", "the missing variants are said every time, or never"),
    ("return root.DescendantAdded:Connect(one)", "a part added later is not dressed"),
    ("local variant = MaterialService:FindFirstChild(name, true)", "a variant in a folder under MaterialService is not found"),
    ('have[name] = variant ~= nil and variant:IsA("MaterialVariant")', "a variant not yet made is put on parts anyway"),
):
    if needle not in LOOK:
        fail("MaterialAppearance: " + why)
build = HUB[HUB.find("function HubService.build()"):]
if not re.search(r"HubService\.refreshBoard\(\)\n\n.*?local dressOk, dressErr = pcall\(MaterialAppearance\.dress, folder\)",
                 build, re.S):
    fail("HubService: the lobby is not dressed once it is built")
if 'floor("HubFloor", Vector3.new(deck.w, 2, deck.d), Vector3.new(deck.x, 0, deck.z), Enum.Material.Slate,' not in HUB:
    fail("HubService: the lobby's decks are not slate, so the flagstones never reach them")
worlds = re.search(r"local LEVEL_WORLDS = \{ (.*) \}", BOOT)
# (Since the hundred-and-eighty-fifth pass with the level's own surfaces, WORLD_SURFACES, handed over as well.)
if not worlds or not re.search(r"local function dressWorld\(child: Instance\)\n\tif LEVEL_WORLDS\[child\.Name\] and not "
                               r"dressedWorlds\[child\] then\n\t\tdressedWorlds\[child\] = true\n(?:\t\t--[^\n]*\n)*"
                               r"\t\tlocal worlds = \(MaterialAppearance :: any\)\.WORLD_SURFACES\n"
                               r"\t\tpcall\(MaterialAppearance\.dress, child, MaterialAppearance\.LEVEL_SURFACES, "
                               r"if worlds then worlds\[child\.Name\] else nil\)\n", BOOT):
    fail("Bootstrap: a level's world is not dressed as it arrives, is dressed twice, or is dressed in everything")
else:
    named = re.findall(r"(\w+) = true", worlds.group(1))
    servers = "".join(read(p) for p in sorted((SRC / "Server" / "Services").glob("*.lua")))
    for name in named:
        if not re.search(r'\.Name = "%s"\n' % name, servers):
            fail("Bootstrap: dresses a world named %s, and no service builds one by that name" % name)
    if len(named) < 5:
        fail("Bootstrap: dresses %d of the levels' worlds, not all five" % len(named))
    # WHERE EACH IS PUT (the hundred-and-seventy-third pass): a world is dressed only where it is watched for. The
    # backdrop and the halls go straight into the workspace; the Sky Pools, the Sunken City and Hill House into its
    # Levels folder, handed to the service's build (or start) as the parent. Watching the workspace alone, those three
    # were never dressed.
    put = {}
    for path in sorted((SRC / "Server" / "Services").glob("*.lua")):
        text = read(path)
        for var, name in re.findall(r'^\t(\w+)\.Name = "(\w+)"\n', text, re.M):
            if name not in named:
                continue
            parent = re.compile(r"^\t%s\.Parent = (\w+)\n" % re.escape(var), re.M).search(
                text, text.find('\t%s.Name = "%s"\n' % (var, name)))
            where = parent.group(1) if parent else None
            if where and where != "workspace":
                call = re.search(r"%s\.(?:build|start)\(([^\n]*)" % path.stem, BOOT)
                where = "Levels" if call and 'workspace:WaitForChild("Levels")' in call.group(1) else None
            put[name] = where
    watched = {
        "workspace": "workspace.ChildAdded:Connect(function(child: Instance)\n\tdressWorld(child)\n\twatchLevels(child)"
                     "\nend)" in BOOT,
        "Levels": 'if folder.Name == "Levels" and folder:IsA("Folder") then\n\t\tfolder.ChildAdded:Connect(dressWorld)'
                  in BOOT and "workspace.ChildAdded:Connect(function(child: Instance)\n\tdressWorld(child)\n\t"
                  "watchLevels(child)\nend)" in BOOT,
    }
    for name in named:
        if put.get(name) is None:
            fail("Bootstrap: cannot tell where the %s world is put, so whether it is ever dressed" % name)
        elif not watched[put[name]]:
            fail("Bootstrap: the %s world is put into %s, which nothing watches, so it is never dressed"
                 % (name, put[name]))
    if "for _, child in ipairs(workspace:GetChildren()) do\n\tdressWorld(child)\n\twatchLevels(child)\nend" not in BOOT \
            or "folder.ChildAdded:Connect(dressWorld)\n\t\tfor _, child in ipairs(folder:GetChildren()) do\n\t\t\t" \
               "dressWorld(child)" not in BOOT:
        fail("Bootstrap: a world already there when the server starts is never dressed")

# ===================================================================== what the levels' buildings are built of
# (the hundred-and-seventy-fourth pass) A surface reaches a part only through its material, and the Sunken City's
# buildings and the Sky Pools' roof were all plain plastic. Each architectural piece is built of what it is: render,
# cast stone, slate, coursed stone, marble, timber (the nine's materials, dressed in a level), or brick and cloth
# (Roblox's own). Never a car, a sign, a boat or the growth on a wall, which keep their paint.
OURS = set(level) | {"Brick", "Fabric"}
CITY = read(SRC / "Server" / "Services" / "SunkenCityService.lua")
built_at = CITY.find("local BUILT_OF: { [string]: Enum.Material } = {")
built_of = dict(re.findall(r"(\w+) = Enum\.Material\.(\w+)", CITY[built_at:CITY.find("\n\t}\n", built_at)])) \
    if built_at >= 0 else {}
WANT_CITY = {"House": "Plaster", "Flats": "Plaster", "Apartments": "Plaster", "Office": "Concrete",
             "Cornice": "Concrete", "Quoin": "Concrete", "Roof": "Slate", "FlatRoof": "Slate", "Nave": "Rock",
             "ChurchTower": "Rock", "ClockTower": "Rock", "Warehouse": "Brick", "Boards": "WoodPlanks"}
for name, material in WANT_CITY.items():
    if built_of.get(name) != material:
        fail("SunkenCityService: the city's %s is not built of %s (BUILT_OF), so it wears no surface"
             % (name, material))
for name, material in built_of.items():
    if material not in OURS:
        fail("SunkenCityService: the city's %s is built of %s, which no surface dresses" % (name, material))
    if re.match(r"(Car|Bus|Van|Tram|Bogie|Hull|Barge|Wreck|Crane|Road|Signal|Billboard|Phone|Shelter|Weed|Algae|"
                r"RoofWeed|Stain|Belfry$|Spire)", name):
        fail("SunkenCityService: the city's %s is given a building's material, and keeps its own paint" % name)
if "\t\t\tmaterial or BUILT_OF[name] or Enum.Material.SmoothPlastic, false)" not in CITY:
    fail("SunkenCityService: cityBlock never asks BUILT_OF, so the city is plain plastic again")
SKY = read(SRC / "Server" / "Services" / "SkyPoolsService.lua")
constants = dict(re.findall(r"^local (PAVING|CAST|MARBLE|RENDER|CANVAS|TIMBER) = Enum\.Material\.(\w+)$", SKY, re.M))
if constants != {"PAVING": "Slate", "CAST": "Concrete", "MARBLE": "Marble", "RENDER": "Plaster", "CANVAS": "Fabric",
                 "TIMBER": "Wood"}:
    fail("SkyPoolsService: what the roof is built of is not paving slate, cast concrete, marble, rendered plaster, "
         "canvas and timber (%s)" % constants)
for name, constant, count in (("Deck", "PAVING", 3), ("Prow", "PAVING", 1), ("Coping", "MARBLE", 1),
                              ("Column", "CAST", 2), ("Collar", "CAST", 2), ("Tower", "CAST", 1),
                              ("Capital", "CAST", 1), ("Basin", "MARBLE", 1), ("FountainStem", "CAST", 2),
                              ("FountainBowl", "MARBLE", 2), ("CabanaWall", "RENDER", 3), ("CabanaRoof", "CANVAS", 1),
                              ("LoungerSlat", "TIMBER", 1), ("FinalPoolRim", "MARBLE", 1)):
    calls = []
    for m in re.finditer(r'(?<![\w.])(?:block|column)\(parent, "%s"' % name, SKY):
        i, depth = m.end(), 1
        while depth and i < len(SKY):
            depth += (SKY[i] == "(") - (SKY[i] == ")")
            i += 1
        calls.append(SKY[m.start():i])
    built = [call for call in calls if re.search(r",\s+%s, (true|false)\)$" % constant, call)]
    if len(calls) != count or len(built) != count:
        fail("SkyPoolsService: %d of the roof's %d %s pieces are built of %s (%d expected)"
             % (len(built), len(calls), name, constant, count))

# ===================================================================== the squish room, and never a chunk
# (the hundred-and-seventy-sixth pass) The squish room is the lobby's, so it wears the lobby's surfaces: boarded
# underfoot, rendered walls and ceiling, timber trim, the lifts painted iron, dressed once it is built. Its samples are
# chunks, and no dressing ever reaches a chunk's own: its slab carries its material's name, and all on it hangs from it.
for needle, why in (
    ("local function chunkPart(item: Instance): boolean\n\tlocal at: Instance? = item\n\twhile at and at:IsA(\"BasePart\") "
     "do\n\t\tif at:GetAttribute(\"Material\") ~= nil then\n\t\t\treturn true", "cannot tell a chunk's own part"),
    ("if chunkPart(item) then\n\t\t\treturn\n\t\tend", "a chunk's own part is dressed (the squish room's samples)"),
):
    if needle not in LOOK:
        fail("MaterialAppearance: " + why)
if 'slab:SetAttribute("Material", materialName)' not in read(SRC / "Server" / "ChunkBuilder.server.lua"):
    fail("ChunkBuilder: a slab no longer carries its material's name, so a dressing cannot keep off a chunk")
SQUISH = read(SRC / "Server" / "Services" / "SquishRoomService.lua")
room = dict(re.findall(r"^local (BOARDS|RENDER|TIMBER|IRON) = Enum\.Material\.(\w+)$", SQUISH, re.M))
if room != {"BOARDS": "WoodPlanks", "RENDER": "Plaster", "TIMBER": "Wood", "IRON": "Metal"}:
    fail("SquishRoomService: the room is not boards, render, timber and painted iron (%s)" % room)
for name, constant, count in (("Floor", "BOARDS", 1), ("Wall", "RENDER", 1), ("Ceiling", "RENDER", 1),
                              ("Skirting", "TIMBER", 1), ("ShelfPlinth", "TIMBER", 1), ("LiftBack", "IRON", 1),
                              ("LiftSide", "IRON", 2), ("LiftJamb", "IRON", 2), ("LiftLintel", "IRON", 1),
                              ("LiftRoof", "IRON", 1), ("LiftPlinth", "IRON", 1)):
    calls = []
    for m in re.finditer(r'(?<![\w.])part\(\w+, "%s",' % name, SQUISH):
        i, depth = m.end(), 1
        while depth and i < len(SQUISH):
            depth += (SQUISH[i] == "(") - (SQUISH[i] == ")")
            i += 1
        calls.append(SQUISH[m.start():i])
    built = [call for call in calls if re.search(r", (true|false), %s\)$" % constant, call)]
    if len(calls) != count or len(built) != count:
        fail("SquishRoomService: %d of the room's %d %s pieces are built of %s (%d expected)"
             % (len(built), len(calls), name, constant, count))
if not re.search(r"\tbuildHall\(folder, pads\)\n\tlocal dressOk, dressErr = pcall\(MaterialAppearance\.dress, folder\)",
                 SQUISH):
    fail("SquishRoomService: the room is not dressed once it is built")

# ===================================================================== the variants, made in one go
# tools/make_variants.lua (Studio's Command Bar) makes every MaterialVariant the game asks for: the nine Harrow ones as
# gen_surfaces.py made them, the three slab variants by the names MaterialAppearance asks for, and the backdrop's two by
# the names its services ask for, each on its material at its size, wearing maps gen_surfaces.py makes.
MAKE = read(ROOT / "tools" / "make_variants.lua")
made = {name: (base, int(studs), wears) for name, base, studs, wears in
        re.findall(r'^\t\{ "(\w+)", Enum\.Material\.(\w+), (\d+), "(\w+)" \},', MAKE, re.M)}
mapped = set(re.findall(r"^\t(\w+) = \{ Color = 0, Normal = 0, Roughness = 0 \},", MAKE, re.M))
if not made:
    fail("tools/make_variants.lua: its VARIANTS cannot be read")
for material, name in surfaces.items():
    if made.get(name, (None, None, None))[:2] != (material, manifest.get(name, (None, None, 0))[2]):
        fail("tools/make_variants.lua: does not make %s on %s at %s studs, as gen_surfaces.py made it"
             % (name, material, manifest.get(name, (None, None, "?"))[2]))
slab_at = LOOK.find("local SlabVariants")
slab_names = dict(re.findall(r'^\t\[Enum\.Material\.(\w+)\] = "(\w*)",', LOOK[slab_at:LOOK.find("\n}", slab_at)], re.M))
if not slab_names or any(not n for n in slab_names.values()):
    fail("MaterialAppearance: a slab variant has no name, so no slab wears its stone")
# YOURS (the hundred-and-seventy-seventh pass): the three slab variants made in Studio long ago, maps on, read through
# the Studio MCP on 2026-11-04. Any other name leaves them unworn again.
elif slab_names != {"Concrete": "ConcreteMeshTile", "Plaster": "PlasterMeshTile", "Slate": "SlateMeshTile"}:
    fail("MaterialAppearance: the slab variants are not the ones made in Studio (ConcreteMeshTile, PlasterMeshTile, "
         "SlateMeshTile), so the slabs wear nothing (%s)" % slab_names)
for material, name in slab_names.items():
    if made.get(name) != (material, manifest.get("Slab", (None, None, 0))[2], "Slab"):
        fail("tools/make_variants.lua: does not make the slab variant %s on %s wearing the Slab maps" % (name, material))
for constant, source in (("CONCRETE_VARIANT", "BackdropService.lua"), ("POOLTILE_VARIANT", "BackdropService.lua"),
                         ("POOL_TILE_VARIANT", "FloodedHallsService.lua"), ("TILE_VARIANT", "SkyPoolsService.lua")):
    text = read(SRC / "Server" / "Services" / source)
    found = re.search(r'^local %s = "(\w+)"' % constant, text, re.M)
    names = [found.group(1)] if found else []
    # The halls' pool takes its own generated mosaic first and falls back to a made one (pass 256).
    listed = re.search(r'^local %sS = \{([^}]*)\}' % constant, text, re.M)
    if listed:
        names = re.findall(r'"(\w+)"', listed.group(1))
    if not any(name in made for name in names):
        fail("tools/make_variants.lua: does not make %s's %s" % (source, constant))
for name, (_, _, wears) in made.items():
    if wears not in manifest or wears not in mapped:
        fail("tools/make_variants.lua: %s wears %s's maps, which gen_surfaces.py does not make or MAPS has no line for"
             % (name, wears))

# ===================================================================== one maker, and the steps
for owned in ("Slab_", "Concrete_", "PoolTile_"):
    if owned in PBR:
        fail("gen_pbr.py still writes %s maps, which are gen_surfaces.py's: two makers of one file" % owned)
for name, (_, base, studs) in manifest.items():
    if not name.startswith("Harrow"):
        continue
    row = re.search(r"^\| `%s` \| (\w+) \| (\d+) \|" % name, HANDOFF, re.M)
    if not row:
        fail("HANDOFF: no row saying how to make the %s MaterialVariant" % name)
    elif row.group(1) != base or int(row.group(2)) != studs:
        fail("HANDOFF: says to make %s on %s at %s studs, and gen_surfaces.py made it for %s at %d"
             % (name, row.group(1), row.group(2), base, studs))

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("surfaces: %d made (%d maps, 1024 square, tiling, light near-white colour, true normals, grey roughness); the "
      "nine Harrow ones each on the material its variant is made for, the lobby dressed once built and its decks "
      "slate, the levels' %d worlds in their stone, wood, render and marble wherever each is put, the drowned city "
      "and the hotel roof built of what they are, the squish room like the lobby, never a chunk; one maker, and the "
      "steps in HANDOFF."
      % (len(manifest), len(manifest) * 3, len(re.findall(r"(\w+) = true", worlds.group(1))) if worlds else 0))
