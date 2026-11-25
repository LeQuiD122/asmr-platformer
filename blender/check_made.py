"""What was made in Studio's generators, and where the code puts it (the hundred-and-eighty-third to eighty-ninth passes, the ninety-fourth and the ninety-eighth).

Run with plain Python from the project root:  python blender/check_made.py

The models and surfaces themselves live in the place (ReplicatedStorage/Assets/Props, MaterialService/LevelSurfaces); the
code only ever asks for them by name and builds what it built before when one is not there. What this holds is the code:

  THE DAILY CHEST (183). The made chest's Body and Lid laid on the deck as made, turned as the old chest was (its lock to
  the arcade's middle), five plain parts without it; its lid lifts on its own Hinge where it has one.
  A DROWNED BATTLEFIELD (184). The war round the lobby's blades: far out (250 to 640), never within 70 of a blade or of
  each other, a share of each under the sea, two volleys of seven arrows all leaning one way, smoke off a wreck and two
  far points; nothing colliding, touched, in the camera's way or casting a shadow; whatever is missing left out and said.
  EACH LEVEL ITS OWN SURFACES (185). The Flooded Halls' concrete, enamelled iron and tile, the Sunken City's stone, brick,
  render and slate, each used only where it has been made (and only then reaching past Harrow Bay's), handed over by
  Bootstrap as each world is dressed.
  THE STREETS (186). Lamps on the corners, anchors in the silt, pots under the moored boats, each placed only if made,
  nothing of them colliding, touched or in the camera's way.
  WHAT FLOATS (187). The halls' debris made things where they are made, the same draws in the same order either way.
  THE GARDEN (188). Every made thing and every new tree in Hill House's garden inside its fence and clear of the house,
  the path, the old tree, the bench and Mrs Dunn; the well and the hives solid, the rest not.
  THE LOBBY'S BENCHES AND URNS (189). The made bench as long as the seat, turned to face out, the seat kept and unseen at its
  slats; the made urn six studs tall; the parts as before without them.
  THE SIEGE AND THE SHIPS (198). Two siege towers, two war hammers, a ballista and two ships' masts added to the field; a
  shield wall and a thicket of spears where they fell together, each within half the room between pieces; every piece
  named for what it is; and no cloud banks by the deck (as slabs they were sheets of glass on the air, as the cloud mesh
  white boulders over the battlefield): the lobby's sky has the levels' own clouds instead, from the first moment.
  THE SERPENT, DRESSED (194). The Sunken City's serpent in its made hide (over the material it was made for, tinted light
  enough to show) and with the made head, as wide as the body, carried on its first segment where the pale eyes were and
  moved with it; the eyes and the plain body as before where either is not made; nothing of the head in anyone's way.
  THE LEVIATHAN MADE AGAIN (199). The lobby's leviathan a made head surfacing, rearing, looking round at the lobby, then two
  humps or more and the tail, each cut by the sea and none laid into the next, the body in the serpent's own hide and the
  head in its made skin, nothing of it colliding, touched, in the camera's way or casting a shadow; the old one only when
  the made head is not there. The far islands made sea stacks by turns, on the sea, in scale, none standing in it.

Exits non-zero on any failure.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
problems = []


def fail(message):
    problems.append(message)


def read(*parts):
    path = SRC.joinpath(*parts)
    return path.read_text(encoding="utf-8").replace("\r\n", "\n") if path.exists() else ""


def between(text, start, end):
    at = text.find(start)
    if at < 0:
        return ""
    stop = text.find(end, at + len(start))
    return text[at:stop if stop >= 0 else len(text)]


HUB = read("Server", "Services", "HubService.lua")
VOTE = read("Client", "Services", "HubVoteService.lua")
APPEAR = read("Shared", "MaterialAppearance.lua")
BOOT = read("Server", "Bootstrap.server.lua")
CITY = read("Server", "Services", "SunkenCityService.lua")
HALLS = read("Server", "Services", "FloodedHallsService.lua")
HILL = read("Server", "Services", "HillHouseService.lua")

# ===== the one way in: a made model by name, or nothing =====
made = between(HUB, "local function madeProp(name: string): Model?", "\nend\n")
if 'folder and folder:FindFirstChild(name)' not in made or 'assets:FindFirstChild("Props")' not in made:
    fail("HubService.madeProp does not look in ReplicatedStorage/Assets/Props")
if "return if found and found:IsA(\"Model\") then found else nil" not in made:
    fail("HubService.madeProp hands back something that is not a made model")

# ===== 183: THE DAILY CHEST =====
chest = between(HUB, "local function buildDailyChest(at: Vector3, parent: Folder)", "\nend\n")
for needle, why in (
    ('local made = madeProp("DailyChest")', "the daily chest never asks for the made chest"),
    ("copy.CFrame = face * part.CFrame", "the made chest is not laid as made, turned as the old one was (its lock to the arcade)"),
    ("copy.Anchored = true", "the made chest's parts are left to fall"),
    ("if not body then\n\t\tmodel:ClearAllChildren()", "a made chest with no Body leaves half of itself under the plain one"),
    ('piece("Lid", Vector3.new(3.2, 0.5, 2)', "the plain chest is gone, so a place without the made one has no chest"),
    ("prompt.Parent = body", "the chest's prompt is not on its body"),
):
    if needle not in chest:
        fail(why)
lift = between(VOTE, "local function liftLid()", "\nend\n")
if 'local at = lid:GetAttribute("Hinge")' not in lift or \
        'local hinge = rest * (if typeof(at) == "Vector3" then CFrame.new(at) else CFrame.new(0, -lid.Size.Y / 2, lid.Size.Z / 2))' not in lift:
    fail("the lid does not lift on its own hinge, so the made lid swings round the bottom of its hasp")
if "CFrame.Angles(math.rad(70), 0, 0)" not in lift:
    fail("the lid no longer lifts up and back")

# ===== 184: A DROWNED BATTLEFIELD =====
war = re.search(r"local WAR = \{ near = ([0-9.]+), far = ([0-9.]+), clear = ([0-9.]+), seaY = (-?[0-9.]+), seed = ([0-9]+) \}", HUB)
if not war:
    fail("the battlefield has no WAR numbers")
else:
    near, far, clear, sea = (float(war.group(i)) for i in range(1, 5))
    if near < 220:
        fail("the battlefield comes nearer the deck than the blades do (%.0f)" % near)
    if far > 700:
        fail("the battlefield runs out past where the sea is drawn (%.0f)" % far)
    if clear < 50:
        fail("the battlefield's pieces may stand in each other or in a blade (%.0f apart)" % clear)
    if sea != -190:
        fail("the battlefield is not at the sea's own height (-190)")
pieces = re.findall(r'\{ name = "(War_\w+)", count = (\d+), scale = \{ ([0-9.]+), ([0-9.]+) \}, under = ([0-9.]+), lean = \{ ([0-9.]+), ([0-9.]+) \} \}', HUB)
names = {p[0] for p in pieces}
for name in ("War_Gauntlet", "War_Helm", "War_Breastplate", "War_Shield", "War_Axe", "War_Spear", "War_Banner", "War_Cannon"):
    if name not in names:
        fail("the battlefield has no %s" % name)
for name, count, lo, hi, under, lean0, lean1 in pieces:
    if float(lo) > float(hi) or float(lean0) > float(lean1):
        fail("%s's ranges run backwards" % name)
    if not 0.1 <= float(under) <= 0.45:
        fail("%s is %s under the water: drowned or floating" % (name, under))
clusters = {name: (int(extra), float(radius)) for name, extra, radius in
            re.findall(r"(War_\w+) = \{ extra = (\d+), radius = ([0-9.]+) \}", HUB)}
if sum(int(p[1]) for p in pieces) + sum(extra for extra, _ in clusters.values()) > 40:
    fail("the battlefield is crowded past forty pieces (its sea is a million square studs: one to every 25,000)")
field = between(HUB, "local function warField(folder: Folder, blades: { Vector3 })", "\nlocal function buildSurroundings")
for needle, why in (
    ("local taken: { Vector3 } = table.clone(blades)", "the battlefield does not keep clear of the blades"),
    ("if Vector2.new(at.X - other.X, at.Z - other.Z).Magnitude < WAR.clear then", "the battlefield's pieces may stand in each other"),
    ("for _ = 1, 40 do", "a crowded sea is not given up on (a piece may go anywhere)"),
    ("piece.CanCollide = false", "a battlefield piece collides"),
    ("piece.CanTouch = false", "a battlefield piece can be touched"),
    ("piece.CanQuery = false", "a battlefield piece is in the camera's way"),
    ("piece.CastShadow = false", "a battlefield piece throws a shadow across the deck"),
    ("piece.Size = template.Size * scale", "a battlefield piece is not drawn at its scale"),
    ("piece.CFrame = turned * CFrame.new(0, piece.Size.Y * (0.5 - under), 0)", "a battlefield piece is not part under the water"),
    ('local arrowMade = madeProp("War_Arrow")', "there are no volleys of arrows"),
    ("for _ = 1, 7 do", "a volley is not seven arrows"),
    ("local lean = rng:NextNumber(22, 30)", "a volley's arrows do not lean together"),
    ('smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"', "there is no smoke"),
    ("smoke.LightEmission = 0", "the smoke glows"),
    ('warnOnce("warfield"', "a missing piece of the battlefield is not said"),
):
    if needle not in field:
        fail(why)
rate = re.search(r"smoke\.Rate = ([0-9.]+)", field)
if not rate or float(rate.group(1)) > 3:
    fail("the smoke is thick enough to hide the sea")
blades = between(HUB, "local BLADE_Y = -190", "-- AN OCEAN UNDER THE WHOLE THING")
if "table.insert(bladeAt, HUB_ORIGIN + Vector3.new(math.cos(angle) * far, 0, math.sin(angle) * far))" not in blades:
    fail("the blades' places are not handed to the battlefield")
if "warField(folder, bladeAt)" not in blades:
    fail("the battlefield is never laid")
if HUB.find("local function warField(") > HUB.find("local function buildSurroundings("):
    fail("warField is written below the room that lays it")

# ===== 185: EACH LEVEL ITS OWN SURFACES =====
worlds = between(APPEAR, "MaterialAppearance.WORLD_SURFACES = {", "} :: { [string]: { [Enum.Material]: string | { string } } }")


def pool(world, material):
    """The names a world's material asks for: one, or its pool."""
    block = between(worlds, "\t%s = {" % world, "\t},")
    found = re.search(r'\[Enum\.Material\.%s\] = (?:"(\w+)"|\{ ([^}]*) \}),' % material, block)
    if not found:
        return []
    return [found.group(1)] if found.group(1) else re.findall(r'"(\w+)"', found.group(2))


for world, material, name in (
    ("FloodedHalls", "Concrete", "HallsConcrete"), ("FloodedHalls", "Metal", "HallsPaint"),
    ("FloodedHalls", "CeramicTiles", "HallsTile"), ("SunkenCity", "Concrete", "CityAshlar"),
    ("SunkenCity", "Brick", "CityBrick"), ("SunkenCity", "Plaster", "CityRender"), ("SunkenCity", "Slate", "CitySlate"),
):
    if name not in pool(world, material):
        fail("%s's %s is not its own %s" % (world, material, name))
# NOT ONE SURFACE ON EVERYTHING (192): the city's stone, render and slate each a pool with Harrow Bay's in it, and the
# Sky Pools' and Hill House's render and the like pooled too.
for world, material, least in (("SunkenCity", "Concrete", 2), ("SunkenCity", "Plaster", 2), ("SunkenCity", "Slate", 2),
                               ("SkyPools", "Concrete", 2), ("SkyPools", "Plaster", 2), ("HillHouse", "Plaster", 2),
                               ("HillHouse", "Slate", 2)):
    names = pool(world, material)
    if len(set(names)) < least:
        fail("%s's %s is one surface on everything again (the repetition)" % (world, material))
    if not any(n.startswith("Harrow") for n in names):
        fail("%s's %s pool has none of Harrow Bay's in it, so with none of its own made it is bare" % (world, material))
if "CityRust" in worlds or "HallsIron" in worlds or '"CityStone"' in worlds:
    fail("a dropped surface is asked for (the red and cyan rust, the red iron, the camouflage CityStone, 241)")
dress = between(APPEAR, "function MaterialAppearance.dress(root: Instance", "\nend\n")
for needle, why in (
    ("own: { [Enum.Material]: string | { string } }?): RBXScriptConnection", "dress takes no level's own surfaces"),
    ("for material, entry in pairs(own or {}) do", "dress never looks for a level's own surfaces"),
    ("if have[name] then\n\t\t\t\ttable.insert(made, name)", "a pool keeps a surface that is not made"),
    ("local index = if typeof(look) == \"number\" then look else math.floor(at.X / 37) + math.floor(at.Z / 41) * 7",
     "a building does not take its pool's surface by its own number, or a part by where it stands"),
    ("ownName = pool[(math.floor(index) % #pool) + 1]", "a part takes its pool's surface some other way"),
    ("local useOwn = ownName ~= nil and have[ownName] == true", "a level's own surface is used whether or not it is made"),
    ("if only and not only[item.Material] and not useOwn then", "a level's own surface never reaches past Harrow Bay's (the halls' metal)"),
    ("local name = if useOwn then ownName else MaterialAppearance.SURFACES[item.Material]", "a level's own surface does not come first"),
    ("if name and have[name] and not worn(item) then", "a surface is put on that is not made, or on someone's clothes"),
):
    if needle not in dress:
        fail(why)
if "pcall(MaterialAppearance.dress, child, MaterialAppearance.LEVEL_SURFACES, if worlds then worlds[child.Name] else nil)" not in BOOT:
    fail("Bootstrap never hands a level its own surfaces")

city_block = between(CITY, "cityBlock = function(parent: Instance, name: string", "\n\tend\n")
if 'local look = parent:GetAttribute("Look")' not in city_block or 'made:SetAttribute("Look", look)' not in city_block:
    fail("a building's parts are not given its number, so a building wears a patchwork of its pool")
lots = between(CITY, "local w, d = lotW - 6, depth - 10", "local pick = rng:NextNumber()")
if 'parent:SetAttribute("Look", (parent:GetAttribute("Look") or 0) + 1)' not in lots:
    fail("the city's buildings are not numbered as they are begun")
if "rng:" in lots:
    fail("numbering the buildings draws from the city's random numbers, so the whole city moves")

# ===== 186: THE STREETS =====
place = between(CITY, "function streetKit.place(parent: Instance, name: string, feet: CFrame, tall: number): BasePart?", "\nend\n")
for needle, why in (
    ("local template = streetKit.made(name)\n\tif not template then\n\t\treturn nil", "a street prop that is not made is not left out"),
    ("piece.Size = template.Size * (tall / template.Size.Y)", "a street prop is not drawn at its height"),
    ("piece.CFrame = feet * CFrame.new(0, piece.Size.Y / 2, 0)", "a street prop does not stand on its feet"),
    ("piece.CanCollide = false", "a street prop collides"),
    ("piece.CanTouch = false", "a street prop can be touched"),
    ("piece.CanQuery = false", "a street prop is in the camera's way"),
):
    if needle not in place:
        fail(why)
madeCity = between(CITY, "function streetKit.made(name: string): BasePart?", "\nend\n")
if 'assets:FindFirstChild("Props")' not in madeCity:
    fail("streetKit.made does not look in ReplicatedStorage/Assets/Props")
side = between(CITY, "function streetKit.sideStreets(", "\nfunction streetKit.metro(")
for needle, why in (
    ("local lampFoot = spot - route.forward * (STREET / 2 + 1.2)", "the corner lamp is not across from the sign"),
    ('streetKit.place(parent, "City_Lamp", CFrame.new(lampFoot.X, floorY, lampFoot.Z)', "the corner lamps do not stand on the street"),
    ("if row % 3 == 0 and step == 40 then", "the anchors are not now and then"),
    ('streetKit.place(parent, "City_Anchor", CFrame.new(fell.X, floorY - 1.2, fell.Z)', "an anchor is not in the silt"),
    ('streetKit.place(parent, "City_LobsterPots",\n\t\t\t\t\t\t\tCFrame.new(pots.X, floorY, pots.Z)', "the pots are not on the street under their boat"),
):
    if needle not in side:
        fail(why)
for spot in ("lampFoot", "fell", "pots"):
    if "not blocked(%s, " % spot not in side:
        fail("a street prop (%s) may stand in something" % spot)
if CITY.find("function streetKit.place(") > CITY.find("function streetKit.sideStreets("):
    fail("streetKit.place is written below the streets that use it")

# ===== 187: WHAT FLOATS =====
floats = between(HALLS, "local floaters: { BasePart } = {}", "-- ===== ONE LIGHT IN THE LEVEL IS FAILING =====")
for needle, why in (
    ('{ "Halls_Lifebuoy", "Halls_Lounger", "Halls_Lifebuoy", "Halls_Duckboard" }', "the halls' floating things are not theirs"),
    ("local size = Vector3.new(rng:NextNumber(1.2, 3.2), rng:NextNumber(0.4, 1.0), rng:NextNumber(1.2, 3.2)) * SCALE",
     "the debris's draws change with what is made, so the rest of the halls moves"),
    ("junk.Size = template.Size * SCALE", "a floating thing is not at the halls' scale"),
    ("WATER_DEPTH - junk.Size.Y * 0.35", "a floating thing does not float"),
    ("junk.CanCollide = false", "a floating thing collides"),
    ("junk.CanQuery = false", "a floating thing is in the camera's way"),
):
    if needle not in floats:
        fail(why)
order = [floats.find(s) for s in ("local leg = legs[rng:NextInteger(1, #legs)]", "local side = if rng:NextNumber() < 0.5",
                                  "local size = Vector3.new(rng:NextNumber", "junk.CFrame = legFrame(leg, rng:NextNumber(0, leg.length),",
                                  "* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)")]
if -1 in order or order != sorted(order):
    fail("the debris's draws are not in their old order, so the halls' failing light and everything after it moves")

# ===== 188: THE GARDEN =====
crag = re.search(r"local CRAG_R = ([0-9.]+)", HILL)
house = re.search(r"local HOUSE_W, HOUSE_D, STOREY, ROOF_H = ([0-9.]+), ([0-9.]+)", HILL)
garden = re.findall(r'\{ "(Hill_\w+)", (-?[0-9.]+), (-?[0-9.]+), ([0-9.]+), ([0-9.]+) \}', between(HILL, "local GARDEN = {", "\n}\n"))
trees = re.findall(r"\{ (-?[0-9.]+), (-?[0-9.]+) \}", between(HILL, "local GARDEN_TREES = {", "\n"))
if not (crag and house and garden and trees):
    fail("Hill House's garden has no GARDEN, GARDEN_TREES, CRAG_R or house size to check")
else:
    fence = float(crag.group(1)) - 1.5
    half_w, deep = float(house.group(1)) / 2, float(house.group(2))
    # Things already in the garden: the old tree, the bench (6 long), Mrs Dunn inside the gate, the path's lamb's ear.
    fixed = [((-20.0, 2.0), 4.0, "the old apple tree"), ((22.0, -4.0), 3.5, "the bench"),
             ((4.8, -(fence - 5.0)), 2.5, "Mrs Dunn")]
    reach = {"Hill_Well": 3.0, "Hill_Wheelbarrow": 2.0, "Hill_Birdbath": 1.4, "Hill_Beehive": 1.3, "Hill_Roses": 1.6}
    placed = []
    for name, across, inward, tall, _turn in garden:
        a, i = float(across), float(inward)
        r = reach.get(name, 2.0)
        if math.hypot(a, i) + r > fence:
            fail("%s at (%s, %s) stands in or past the fence" % (name, across, inward))
        if abs(a) < half_w + r + 0.5 and 4 - r - 0.5 < i < 4 + deep + r:
            fail("%s at (%s, %s) stands in the house" % (name, across, inward))
        if abs(a) < 3.4 + r and i < 4:
            fail("%s at (%s, %s) stands on the path or its lamb's ear" % (name, across, inward))
        for (fa, fi), fr, what in fixed:
            if math.hypot(a - fa, i - fi) < r + fr:
                fail("%s at (%s, %s) stands in %s" % (name, across, inward, what))
        for (pa, pi_, pr, pname) in placed:
            if math.hypot(a - pa, i - pi_) < r + pr - 0.2:
                fail("%s and %s stand in each other" % (name, pname))
        placed.append((a, i, r, name))
        if float(tall) > 8:
            fail("%s is drawn %s tall" % (name, tall))
    for across, inward in trees:
        a, i = float(across), float(inward)
        if math.hypot(a, i) + 4 > fence:
            fail("a new apple tree at (%s, %s) reaches past the fence" % (across, inward))
        if abs(a) < half_w + 4 and -0.5 < i < 4 + deep + 4:
            fail("a new apple tree at (%s, %s) grows through the house" % (across, inward))
        for (pa, pi_, pr, pname) in placed:
            if math.hypot(a - pa, i - pi_) < pr + 2:
                fail("a new apple tree at (%s, %s) stands in %s" % (across, inward, pname))
dressing = between(HILL, "local function dressGarden(garden: Instance, top: Vector3, inward: Vector3, across: Vector3)", "\nend\n")
for needle, why in (
    ('assets:FindFirstChild("Props")', "the garden does not look in Assets/Props"),
    ("if template then", "a garden thing that is not made is not left out"),
    ("piece.Size = template.Size * ((spot[4] :: number) / template.Size.Y)", "a garden thing is not drawn at its height"),
    ("* CFrame.new(0, piece.Size.Y / 2, 0)", "a garden thing does not stand on the grass"),
    ("piece.CanCollide = GARDEN_SOLID[name] == true", "the garden's solid things are not the well and the hives alone"),
    ("appleTree(garden, top + across * spot[1] + inward * spot[2])", "the new apple trees are not planted"),
):
    if needle not in dressing:
        fail(why)
if 'local GARDEN_SOLID = { Hill_Well = true, Hill_Beehive = true }' not in HILL:
    fail("the garden's solid things are not the well and the hives")
if "bench(garden, top + across * 22 - inward * 4, out)\n\tdressGarden(garden, top, inward, across)" not in HILL:
    fail("the garden is never dressed")
if HILL.find("local function dressGarden(") < HILL.find("local function appleTree("):
    fail("dressGarden is written above the apple tree it plants")

# ===== 189: THE LOBBY'S BENCHES AND URNS =====
bench = between(HUB, "local function buildBench(at: Vector3, facing: number, parent: Folder)", "\nend\n")
for needle, why in (
    ('local made = madeProp("Lobby_Bench")', "the lobby's benches never ask for the made bench"),
    ("bench.Size = look.Size * (9 / look.Size.X)", "the made bench is not as long as its seat"),
    ("bench.CFrame = turn * CFrame.Angles(0, math.pi, 0) * CFrame.new(0, bench.Size.Y / 2, 0)",
     "the made bench faces into its own back (its front is its -Z)"),
    ("seat.Transparency = 1", "the seat shows through the made bench"),
    ("seat.CFrame = turn * CFrame.new(0, bench.Size.Y * 0.36, 0) * CFrame.Angles(0, math.pi, 0)",
     "the seat is not at the made bench's slats, or faces into its back"),
    ("bench.CanCollide = false", "the made bench collides as well as its seat"),
    ('local backRail = decorPart("BenchBack"', "a place without the made bench has no back to its benches"),
    ("prompt.Parent = seat", "the bench's Sit prompt is not on its seat"),
):
    if needle not in bench:
        fail(why)
planter = between(HUB, "local function buildPlanter(at: Vector3, seed: number, parent: Folder)", "\nend\n")
for needle, why in (
    ('local made = madeProp("Lobby_Urn")', "the lobby's planters never ask for the made urn"),
    ("urn.Size = urnLook.Size * (6 / urnLook.Size.Y)", "the made urn is not six studs tall"),
    ("urn.CFrame = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * CFrame.new(0, urn.Size.Y / 2, 0)",
     "the made urn does not stand on the deck, turned its own way"),
    ("urn.CanCollide = false", "the made urn collides"),
    ('{ "Hub_Planter", Vector3.new(0, 1.5, 0)', "a place without the made urn has no planters"),
):
    if needle not in planter:
        fail(why)

# ===== 194: THE SERPENT, DRESSED =====
SEA = read("Client", "Services", "SunkenCityClient.lua")
sea_made = between(SEA, "local function madeSea(name: string): MeshPart?", "\nend\n")
if 'assets:FindFirstChild("Props")' not in sea_made or 'model:FindFirstChild("Mesh")' not in sea_made:
    fail("SunkenCityClient.madeSea does not look for a made model's Mesh in ReplicatedStorage/Assets/Props")
if 'return if mesh and mesh:IsA("MeshPart") then mesh else nil' not in sea_made:
    fail("SunkenCityClient.madeSea hands back something that is not a mesh")
names = re.search(r'local SERPENT = \{ hide = "(\w+)", tint = Color3\.fromRGB\((\d+), (\d+), (\d+)\), head = "(\w+)",\s*'
                  r'width = ([\d.]+), forward = ([\d.]+) \}', SEA)
if not names:
    fail("the serpent's made things are not named in one SERPENT table")
else:
    if names.group(1) != "SerpentHide" or names.group(5) != "Sea_Head":
        fail("the serpent asks for %s and %s, which are not what was made (SerpentHide, Sea_Head)"
             % (names.group(1), names.group(5)))
    if not 0.8 <= float(names.group(6)) <= 1.2:
        fail("the made head is drawn %s of the body's width" % names.group(6))
    if not 0 <= float(names.group(7)) <= 11:
        fail("the made head sits %s studs forward of the first segment, past the next joint" % names.group(7))
    if min(int(names.group(n)) for n in (2, 3, 4)) < 90:
        fail("the serpent's hide is tinted so dark it cannot be made out")
serpent = between(SEA, "local function buildThing(b: SunkenPath.Brief)", "\nend\n")
for needle, why in (
    ('local hide = game:GetService("MaterialService"):FindFirstChild(SERPENT.hide, true)', "the serpent never asks for its made hide"),
    ('if hide and hide:IsA("MaterialVariant") then', "the serpent puts on a hide that is not a material"),
    ("rig.part.Material = hide.BaseMaterial", "the serpent's hide goes over another material, so it never shows"),
    ("rig.part.MaterialVariant = hide.Name", "the serpent's hide is never put on"),
    ("rig.part.Color = SERPENT.tint", "the serpent's hide is tinted the old body's near-black"),
    ("local made = madeSea(SERPENT.head)", "the serpent never asks for its made head"),
    ("piece.Size = made.Size * (rig.part.Size.X * SERPENT.width / made.Size.X)",
     "the made head is not as wide as the body, kept in proportion"),
    ("table.insert(eyes, piece)\n\t\t\ttable.insert(eyeRest, segment * CFrame.new(0, 0, -SERPENT.forward))",
     "the made head is not carried on the first segment, as the eyes are"),
    ("for _, side in ipairs(if made then {} else { -1, 1 }) do",
     "the pale eyes are drawn over the made head's own, or left out without it"),
):
    if needle not in serpent:
        fail(why)
head_piece = between(serpent, "local piece = made:Clone()", "table.insert(eyes, piece)")
for prop in ("piece.Anchored = true", "piece.CanCollide = false", "piece.CanTouch = false", "piece.CanQuery = false",
             "piece.CastShadow = false", "piece.Parent = holder"):
    if prop not in head_piece:
        fail("the made head is not %s" % prop.replace("piece.", ""))
if "eye.CFrame = head * mesh.eyeRest[index]" not in between(SEA, "local function moveThing(", "\nend\n"):
    fail("what the serpent's head carries is not moved with its head")

# ===== 198: THE SIEGE, THE SHIPS, WHERE THEY FELL TOGETHER, AND CLOUDS NOT PANES =====
war_names = {p[0] for p in pieces}
for name in ("War_SiegeTower", "War_Hammer", "War_Ballista", "War_Mast"):
    if name not in war_names:
        fail("the battlefield has no %s" % name)
if "local WAR_CLUSTERS = {" not in HUB:
    fail("nothing on the battlefield fell together: no shield wall, no thicket of spears")
for name in ("War_Shield", "War_Spear"):
    if name not in clusters:
        fail("%s fell alone: no cluster of them" % name)
for name, (extra, radius) in clusters.items():
    if name not in war_names:
        fail("a cluster of %s, which the battlefield does not have" % name)
    if war and radius > float(war.group(3)) / 2:
        fail("a cluster of %s reaches %.0f, into the next piece's room (%.0f apart)" % (name, radius, float(war.group(3))))
    if extra > 5:
        fail("a cluster of %s is %d deep, a heap and not a fall" % (name, extra))
for needle, why in (
    ("local cluster = WAR_CLUSTERS[kind.name]", "no piece is laid with its cluster"),
    ("if cluster and count == 1 then", "every piece of a kind is a cluster, not the first"),
    ("* rng:NextNumber(cluster.radius * 0.45, cluster.radius)", "a cluster's pieces are not laid round the first, clear of it"),
    ("piece.Name = if template.Parent then template.Parent.Name else template.Name",
     "the battlefield's pieces are all called Mesh, not what they are"),
):
    if needle not in field:
        fail(why)
clouds = between(HUB, "-- CLOUDS IN THE SKY, NOT BY THE DECK", "-- FOUR WAVING ARMS AND A LANTERN RING.")
if not clouds:
    fail("the lobby's clouds are not said to be in the sky and not by the deck")
else:
    if "FarCloud_" in clouds or "Backdrop_Cloud" in clouds:
        fail("the lobby hangs cloud banks by the deck again (glass slabs, or white boulders over the battlefield)")
    BACKDROP = read("Server", "Services", "BackdropService.lua")
    theirs = re.search(r"clouds\.Cover = ([0-9.]+)\s+clouds\.Density = ([0-9.]+)\s+clouds\.Color = (Color3\.fromRGB\([0-9, ]+\))",
                       BACKDROP)
    ours = re.search(r"sky\.Cover = ([0-9.]+)\s+sky\.Density = ([0-9.]+)\s+sky\.Color = (Color3\.fromRGB\([0-9, ]+\))", clouds)
    if not ours:
        fail("the lobby's sky has no clouds of its own before a first run")
    elif not theirs or ours.groups() != theirs.groups():
        fail("the lobby's sky clouds are not the levels' (BackdropService.ensureSkyClouds), so the sky changes after a first run")
    if 'if terrain and not terrain:FindFirstChildOfClass("Clouds") then' not in clouds:
        fail("the lobby makes its sky clouds over the ones a level already made")

# ===== 199: THE LEVIATHAN MADE AGAIN, AND ROCK FOR THE BOXES =====
made_lev = between(HUB, "local function madeLeviathan(at: Vector3, folder: Folder): boolean", "\nend\n")
body_rows = re.findall(r'\{ name = "(Sea_Leviathan\w+)", along = (-?[0-9.]+), size = ([0-9.]+), side = "([XYZ])", '
                       r'under = ([0-9.]+)(, flip = true)? \}', between(HUB, "local LEVIATHAN_BODY = {", "\n}\n"))
if not made_lev:
    fail("the lobby has no made leviathan (madeLeviathan), only the old one lying flat on the sea")
elif not body_rows:
    fail("the made leviathan has no body to lay (LEVIATHAN_BODY)")
else:
    names = [row[0] for row in body_rows]
    if names[0] != "Sea_LeviathanHead" or names[-1] != "Sea_LeviathanTail" or names.count("Sea_LeviathanHump") < 2:
        fail("the made leviathan is not a head, then two humps or more, then the tail (%s)" % ", ".join(names))
    alongs = [float(row[1]) for row in body_rows]
    sizes = [float(row[2]) for row in body_rows]
    for (name, a, size), (_, b, next_size) in zip(zip(names, alongs, sizes), list(zip(names, alongs, sizes))[1:]):
        if b - a < 0.75 * (size + next_size) / 2:
            fail("the leviathan's %s and the piece after it are %.0f apart, laid into each other" % (name, b - a))
    for name, size, under in zip(names, sizes, [float(row[4]) for row in body_rows]):
        if not 80 <= size <= 260:
            fail("the leviathan's %s is %.0f studs, out of scale with the war round it" % (name, size))
        if not 0.1 <= under <= 0.6:
            fail("the leviathan's %s is %.2f under the sea: its cut shows, or it is drowned" % (name, under))
    if float(body_rows[0][4]) > 0.35:
        fail("the leviathan's head is too far under the sea for its jaws to show")
    half = re.search(r"local LEVIATHAN_HALF = ([0-9.]+)", HUB)
    if not half or abs(float(half.group(1)) - (alongs[0] + alongs[-1]) / 2) > 40:
        fail("the made leviathan is not laid round its middle, so it moves off its place in the sea")
    head = re.search(r"local LEVIATHAN_HEAD = \{ look = ([0-9.]+), rear = ([0-9.]+) \}", HUB)
    if not head or not 0.3 <= float(head.group(1)) <= 1.5:
        fail("the leviathan's head does not look round at the lobby")
    if not head or not 10 <= float(head.group(2)) <= 45:
        fail("the leviathan's head does not rear up out of the water (10 to 45 degrees)")
    for needle, why in (
        ("part.CanCollide = false", "the leviathan collides"),
        ("part.CanTouch = false", "the leviathan can be touched"),
        ("part.CanQuery = false", "the leviathan is in the camera's way"),
        ("part.CastShadow = false", "the leviathan casts a shadow across the lobby from six hundred studs off"),
        ('if piece.name == "Sea_LeviathanHead" then', "the leviathan's head is dressed as its body, over its eyes and teeth"),
        ("part.MaterialVariant = hide.Name", "the leviathan's body is not in the serpent's hide"),
        ('part.TextureID = ""', "the leviathan's body keeps the made texture under the hide, each piece its own colour"),
        ('warnOnce("leviathan"', "a piece of the leviathan missing is not said"),
    ):
        if needle not in made_lev:
            fail(why)
    hide = re.search(r'local LEVIATHAN_HIDE = \{ name = "(\w+)", tint = Color3\.fromRGB\((\d+), (\d+), (\d+)\) \}', HUB)
    serpent = re.search(r'local SERPENT = \{ hide = "(\w+)"', read("Client", "Services", "SunkenCityClient.lua"))
    if not hide or not serpent or hide.group(1) != serpent.group(1):
        fail("the leviathan's hide is not the serpent's, so the lobby's monster and the city's are two skins")
    elif not all(40 <= int(hide.group(i)) <= 140 for i in (2, 3, 4)):
        fail("the leviathan's hide is tinted too dark to see or too pale to be wet")
if "if not madeLeviathan(leviathanAt, folder) then" not in HUB:
    fail("the old leviathan is laid as well as the made one, or the made one is never laid")
elif HUB.find('{ "Hub_Leviathan_Body", "Hub_Leviathan_Head" }') < HUB.find("if not madeLeviathan(leviathanAt, folder) then"):
    fail("the old leviathan is not left for when the made one is not there")
# The far islands, made sea stacks by turns, boxes only without them; none standing in the leviathan.
islands = between(HUB, "-- A MADE SEA STACK where there is one", "-- Dropped to meet the water at -170")
for needle, why in (
    ('madeProp(if index % 2 == 1 then "Sea_Rock" else "Sea_RockPair")', "the far islands are boxes, not made rock"),
    ("Vector3.new(math.cos(angle) * far, SEA_Y, math.sin(angle) * far)", "the made islands are not on the sea"),
    ("stack.CanCollide = false", "the far islands collide"),
    ("stack.CastShadow = false", "the far islands cast shadows"),
    ("\t\t\tcontinue\n", "a made island has a box laid over it as well"),
):
    if needle not in islands:
        fail(why)
rock = re.search(r"local ISLANDS = \{ tall = ([0-9.]+), step = ([0-9.]+), under = ([0-9.]+) \}", HUB)
if not rock:
    fail("the far islands' height is not set (ISLANDS)")
else:
    tall, step, under = (float(rock.group(i)) for i in (1, 2, 3))
    if tall < 50 or tall + 2 * step + 10 > 150:
        fail("the far islands are %.0f to %.0f tall, out of scale with the war round them" % (tall, tall + 2 * step + 10))
    if not 0.08 <= under <= 0.3:
        fail("the far islands are %.2f under the sea: their made base shows, or they are drowned" % under)
# ===== 201: THE CHUNKS' OWN SURFACES, LAID WITHOUT A REPEAT, AND A MADE STALL FOR THE SHOP =====
APPEAR = read("Shared", "MaterialAppearance.lua")
variants = between(APPEAR, "local PartVariants: { [string]: string } = {", "\n}\n")
for needle, why in (
    ('Soap = "ChunkSoap",', "soap's surface is blank again, so its bars never wear one"),
    ('Needoh = "ChunkNeedoh",', "the Needoh is bare smooth plastic again"),
    ('stable = "ChunkStable",', "the plain stable chunks have no surface of their own"),
):
    if needle not in variants:
        fail(why)
if 'applyPartVariant(part, materialName or "stable")' not in between(APPEAR, "function MaterialAppearance.apply(", "\nend\n"):
    fail("a part with no material is dressed as stable but never wears stable's surface")
organic = re.search(r"MaterialAppearance\.ORGANIC = \{ ([^}]*) \}", APPEAR)
laid = set(re.findall(r'"(\w+)"', organic.group(1))) if organic else set()
for name in ("HarrowCast", "HarrowRender", "HarrowMarble"):
    if name not in laid:
        fail("%s is laid square again, the same blotch every few studs in a grid" % name)
for name in ("HarrowStone", "HarrowFlags", "HarrowBoards", "HarrowTimber"):
    if name in laid:
        fail("%s is laid Organic, so its courses, joints or grain wander off line" % name)
dressing = between(APPEAR, "function MaterialAppearance.dress(", "\nend\n")
if "layOrganic(MaterialService)" not in dressing or \
        "variant.MaterialPattern = Enum.MaterialPattern.Organic" not in between(APPEAR, "local function layOrganic(", "\nend\n"):
    fail("the surfaces meant to be laid Organic never are")
kiosk = between(HUB, "function HubService.buildKiosk(folder: Folder)", "\nend\n")
stall_long = re.search(r"local KIOSK_STALL = \{ long = ([0-9.]+), x = (-?[0-9.]+) \}", HUB)
if not stall_long or not 6 <= float(stall_long.group(1)) <= 11:
    fail("the made stall is not the kiosk's size (KIOSK_STALL)")
for needle, why in (
    ('local stallMade = madeProp("Shop_Stall")', "the shop is still two dozen plastic blocks where the stall is made"),
    ("stall.CanCollide = false", "the made stall collides as a box round its awning"),
    ("CFrame.Angles(0, -math.pi / 2 + (if typeof(yaw) == \"number\" then yaw else 0), 0)",
     "the made stall does not face the room (a quarter turn, and its own FrontYaw)"),
    ("counter.Transparency = 1", "the kiosk's block counter shows through the made stall"),
    ("prompt.Parent = counter", "the shop's prompt is not on the counter"),
    ('piece("KioskAwning"', "without the made stall the kiosk is not built at all"),
    ("lamp.Parent = piece(\"KioskLampHousing\", Vector3.new(0.6, 0.3, 0.6), lampAt, teal)",
     "the kiosk's lamp does not hang under the made stall's awning"),
):
    if needle not in kiosk:
        fail(why)

angle = re.search(r"local LEVIATHAN_ANGLE = ([0-9.]+)", HUB)
far = re.search(r"local LEVIATHAN_FAR = ([0-9.]+)", HUB)
half = re.search(r"local LEVIATHAN_HALF = ([0-9.]+)", HUB)
if angle and far and half and body_rows:
    mid = (math.cos(float(angle.group(1))) * float(far.group(1)), math.sin(float(angle.group(1))) * float(far.group(1)))
    to_hub = (-mid[0] / math.hypot(*mid), -mid[1] / math.hypot(*mid))
    run = (-to_hub[1], to_hub[0])
    for name, along, size in ((row[0], float(row[1]), float(row[2])) for row in body_rows):
        at = (mid[0] + run[0] * (along - float(half.group(1))), mid[1] + run[1] * (along - float(half.group(1))))
        for index in range(1, 10):
            turn = index / 9 * math.pi * 2 + 0.2
            spot = (math.cos(turn) * (400 + index % 3 * 70), math.sin(turn) * (400 + index % 3 * 70))
            if math.hypot(at[0] - spot[0], at[1] - spot[1]) < size / 2 + 50:
                fail("far island %d stands in the leviathan's %s" % (index, name))

# ===== 204: THE SKY POOLS IN THEIR OWN STONE =====
# Made in Studio's material generator on 2026-11-06 and kept under MaterialService.LevelSurfaces: white marble with soft
# grey veins, pale smooth stone, cream travertine pavers. The drowned city's dark ashlar is out of the Sky Pools.
for material, name in (("Marble", "SkyMarble"), ("Slate", "SkyPaving"), ("Concrete", "SkyStone")):
    if name not in pool("SkyPools", material):
        fail("the Sky Pools' %s is not their own %s (it wears what was made for somewhere else)" % (material, name))
if "CityAshlar" in pool("SkyPools", "Concrete"):
    fail("the Sky Pools' columns and tower wear the drowned city's dark blue ashlar again")

# ===== 204: THE CITY SHORE'S HILLS, WINDOWS AND NO NEON =====
# The land ended 6000 out and the bare sky showed under the skyline as a pink band with a hard top. Two ridges of hills
# stand along its far edge, high enough that even the dips between their hills stand over the level's eye line (the
# level is 700 over the backdrop's water line), no hill past a part's 2048; the towers wear windows at their own scale;
# nothing glows by being Neon; and the version is bumped, or a saved place keeps the old horizon.
BACKDROP = read("Server", "Services", "BackdropService.lua")
base_y = re.search(r"^local BASE_Y = (-?\d+)", BACKDROP, re.M)
land_top = re.search(r"^local LAND_TOP = (\d+)", BACKDROP, re.M)
ridges = re.findall(r"\{ from = LAND_FAR ([+-] \d+), rise = \{ (\d+), (\d+) \}, wide = \{ (\d+), (\d+) \}, colour = ",
                    between(BACKDROP, "local RIDGES = {", "\n}\n"))
EYE = 40  # the City Shore's lowest chunks stand about 26 up; an eye over them
if not (base_y and land_top) or len(ridges) < 2:
    fail("the City Shore has no ridges of hills behind its city (RIDGES), so the bare sky shows under the skyline")
else:
    ground = int(base_y.group(1)) + int(land_top.group(1))
    for shift, low, high, narrow, broad in ridges:
        if int(high) > 1024 or int(broad) > 2048:
            fail("a ridge's hills are bigger than a part can be (2048 a side)")
        if ground - 30 + int(low) < EYE:
            fail("a ridge's lowest hill tops out under the level's eye line, so sky shows over it below the horizon")
    back = max(ridges, key=lambda r: int(r[0].replace(" ", "")))
    # Neighbours overlap by half their width, so the lowest point between two is 0.866 of the lower one's rise.
    if ground - 30 + 0.866 * int(back[1]) < EYE:
        fail("the dips between the back ridge's hills fall under the level's eye line, and the pink band shows in them")
hill_fn = between(BACKDROP, "local function hills(parent: Instance)", "\nend\n")
for needle, why in (
    ("local offset = -CITY_HALF - math.rad(4)", "the hills do not run the whole of the land behind the city"),
    ("while offset <= CITY_HALF + math.rad(4) do", "the hills stop short of the land's ends"),
    ("offset += wide * 0.5 / radius", "the hills do not overlap their neighbours by half, and sky shows between them"),
    ("mesh.MeshType = Enum.MeshType.Sphere", "the hills are boxes"),
):
    if needle not in hill_fn:
        fail(why)
if "\tquays(model)\n\thills(model)\n" not in BACKDROP:
    fail("the hills are never raised")
if 'local WINDOWS_VARIANT = "BackdropWindows"' not in BACKDROP or "useVariant(stage, WINDOWS_VARIANT)" not in BACKDROP:
    fail("the City Shore's towers are painted boxes with no windows again")
if "{ CONCRETE_VARIANT, POOLTILE_VARIANT, WINDOWS_VARIANT }" not in BACKDROP:
    fail("a missing window surface goes unsaid")
if "Enum.Material.Neon" in BACKDROP:
    fail("something on the City Shore's horizon glows by being Neon (its windows, its glitter)")
version = re.search(r"^local BACKDROP_VERSION = (\d+)", BACKDROP, re.M)
if not version or int(version.group(1)) < 6:
    fail("the backdrop's version is not bumped, so a saved place keeps the horizon without hills")

if problems:
    print("MADE PROBLEMS (%d):" % len(problems))
    for problem in problems:
        print("  " + problem)
    sys.exit(1)
print("made: the daily chest as made, lid on its own hinge; a drowned battlefield round the blades, %d pieces and two "
      "volleys, far out, apart, part under, smoking; the halls' and the city's own surfaces where made; lamps, anchors "
      "and pots in the streets; the halls' floating things in the same draws; %d things and %d trees in Hill House's "
      "garden, clear of everything; the lobby's made benches and urns; the serpent in its made hide and head; the siege and the ships, a shield wall, a "
      "thicket of spears, the sky's clouds and none by the deck; the leviathan made again, %d pieces cut by the sea, and "
      "rock for the boxes." % (
          sum(int(p[1]) for p in pieces), len(garden), len(trees), len(body_rows)))
