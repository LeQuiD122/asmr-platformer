"""Hill House (level 5, the hundred-and-eleventh pass; its hall the hundred-and-twelfth), checked without Studio.

    python blender/check_hillhouse.py

What it holds:
  * THE LEVEL: first in the story's order and the lobby's (LevelDefinitions.All), at eight in the morning, ending at
    the house, with its own light, its pad's sky and its banner; its badge kept by its level id.
  * CLEAR OF THE ROUTE: the crag is put out beyond the route's circle (LevelService's SPIRAL_RADIUS), its nearest edge
    far enough outside it that no chunk on any turn can be inside the hill, with its rocks on the far side only; and
    nothing goes down from the landing or the bridge through the spiral below.
  * IT ALL FITS: the footbridge a sensible length; the house, the tree and the bench inside the fence; the fence
    round the top; the mist above the kill plane and under the lowest chunk.
  * WIRED AND PUT AWAY: Bootstrap builds it at the route's end and stands the old finish line down; stops it before a
    new level and when the level goes; its ground (terrain) cleared; its door's prompt "Go in", the door swinging in
    (and ending nothing: the level ends in the hall).
  * THE HALL: "Take the key" ends it, once a player, after the scene has started (HillScene "key"); his clock's hands
    at four minutes to midnight; everything the scene reads (the attributes, the pendulum and the key by name, the
    pendulum hung where the server hangs it) there; HillHouseClient started and listened for, its two sounds listed
    and made; the hall's lights soft (nothing over 1.5).
  * WHO IS UP HERE: Mr Gale on the landing, on the far side from the bridge and never on the way over, his crate
    standing on the landing; Mrs Dunn inside the gate, off the path; both stood up when the house is built.
  * NO NEON, and the house's name in the world's print on a SurfaceGui.
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
problems = []


def fail(message):
    problems.append(message)


def read(*parts):
    path = SRC.joinpath(*parts)
    return path.read_text(encoding="utf-8") if path.exists() else ""


HOUSE = read("Server", "Services", "HillHouseService.lua")
LEVELS = read("Shared", "LevelDefinitions.lua")
LEVEL_SERVICE = read("Server", "Services", "LevelService.lua")
BOOT = read("Server", "Bootstrap.server.lua")
LIGHT = read("Server", "Services", "LightingService.lua")
UI = read("Client", "Services", "UIService.lua")
HUB = read("Server", "Services", "HubService.lua")
CATALOG = read("Shared", "ShopCatalog.lua")
CHUNKS = read("Server", "ChunkBuilder.server.lua")
CLIENT = read("Client", "Services", "HillHouseClient.lua")
CLIENT_BOOT = read("Client", "Bootstrap.client.lua")

if not HOUSE:
    fail("there is no src/Server/Services/HillHouseService.lua")


def number(text, name):
    found = re.search(r"^local %s = (-?[\d.]+)" % name, text, re.M)
    if not found:
        fail("this check can no longer read %s" % name)
        return None
    return float(found.group(1))


# ===================================================================== the level
level = LEVELS[LEVELS.find("LevelDefinitions.Level5 = {"):]
level = level[:level.find("\n}\n")]
if not level:
    fail("LevelDefinitions has no Level5")
for needle, why in (
    ("levelId = 5,", "Hill House is not level 5"),
    ('name = "Hill House",', "level 5 is not called Hill House"),
    ('storyTime = "8:00 AM",', "Hill House is not at eight in the morning"),
    ('backdrop = "hillHouse",', "Hill House has no backdrop of its own (its light, its pad)"),
    ('finale = "house",', "Hill House does not end at the house"),
):
    if needle not in level:
        fail("LevelDefinitions: " + why)
# TWO ORDERS (the hundred-and-eighteenth pass): the lobby's by number, Hill House the last pad beside the Flooded
# Halls' and opening after them; the story's by its clock, Hill House first, at eight in the morning.
order = re.search(r"LevelDefinitions\.All = \{(.*?)\}", LEVELS, re.S)
listed = re.findall(r"LevelDefinitions\.(\w+)", order.group(1)) if order else []
if listed != ["Level1", "Level2", "Level3", "Level4", "Level5"]:
    fail("LevelDefinitions.All is not the lobby's order by number, Hill House last beside the Flooded Halls (%s)" % listed)
story = re.search(r"LevelDefinitions\.Story = \{(.*?)\}", LEVELS, re.S)
told = re.findall(r"LevelDefinitions\.(\w+)", story.group(1)) if story else []
if told != ["Level5", "Level1", "Level2", "Level3", "Level4"]:
    fail("LevelDefinitions.Story is not the story's clock, Hill House first at eight in the morning (%s)" % told)
for needle, why in (
    ("local level = LevelDefinitions.Story[run.index]", "the story plays its levels in the lobby's order"),
    ("next = if last then nil else LevelDefinitions.Story[story.index + 1].name,", "the story's card names the wrong level next"),
):
    if needle not in BOOT:
        fail("Bootstrap: " + why)
if "LevelDefinitions.All[run.index]" in BOOT or "LevelDefinitions.All[story.index" in BOOT:
    fail("Bootstrap: part of the story still counts along the lobby's order")
ECON = read("Server", "Services", "EconomyService.lua")
if "return math.clamp(math.floor(at or 1), 1, #LevelDefinitions.Story)" not in ECON:
    fail("EconomyService: a save's place in the story is not counted along the story")
if "hillHouse = {" not in LIGHT:
    fail("LightingService has no hillHouse palette, so Hill House is lit like the default")
clock = re.search(r"hillHouse = \{.*?clock = ([\d.]+),", LIGHT, re.S)
if not clock or not 6.5 <= float(clock.group(1)) <= 9:
    fail("Hill House's light is not the morning (clock %s)" % (clock.group(1) if clock else "unread"))
if '[5] = { name = "Hill House"' not in UI or 'motif = "door" },' not in UI or 'elseif look.motif == "door" then' not in UI:
    fail("UIService: Hill House has no banner of its own (its door motif)")
if "hillHouse = {" not in HUB:
    fail("HubService: Hill House's pad has no sky")
if "level = { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }," not in CATALOG:
    fail("ShopCatalog: Hill House has no badge")
if "(badges.level[level.levelId] or 0) == 0" not in BOOT:
    fail("Bootstrap: the paste check reads the levels' badges by place in the list, which Hill House changed")

# ===================================================================== clear of the route
route_r = number(LEVEL_SERVICE, "SPIRAL_RADIUS")
crag_r, clear, ahead = number(HOUSE, "CRAG_R"), number(HOUSE, "CLEAR"), number(HOUSE, "AHEAD")
house_w, house_d = (float(v) for v in (re.search(r"^local HOUSE_W, HOUSE_D, STOREY, ROOF_H = ([\d.]+), ([\d.]+),", HOUSE, re.M)
                                        or re.match(r"(0), (0)", "0, 0")).groups())
landing = re.search(r"^local LANDING = Vector3\.new\(([\d.]+), ([\d.]+), ([\d.]+)\)", HOUSE, re.M)
widths = [float(w) for w in re.findall(r"\bwidth = ([\d.]+)", CHUNKS)] or [22.0]
widest_half = max(widths) / 2
if None not in (route_r, crag_r, clear, ahead) and landing and house_w:
    # Where HillHouseService puts the crag for a route end on the circle, heading round it.
    first_out = clear + crag_r + 8
    centre_dist = math.hypot(route_r + first_out, ahead)
    nearest = centre_dist - crag_r
    if clear - widest_half < 10:
        fail("the crag's edge is only %.1f studs past the widest chunk's edge (CLEAR %.0f, chunks up to %.0f across)"
             % (clear - widest_half, clear, widest_half * 2))
    if nearest < route_r + clear - 0.01:
        fail("the crag's first place is inside its own clearance (the loop would move it, but it should not have to)")
    if "if fromCentre - CRAG_R >= routeR + CLEAR then" not in HOUSE or "C += out * 2" not in HOUSE:
        fail("HillHouseService does not push the crag out until it is clear of the route")
    # The footbridge: from the landing to three studs onto the top.
    lx, lz = float(landing.group(1)), float(landing.group(3))
    land_mid = (0.0, lz / 2)  # along the heading from the route's end; outward is x
    crag = (first_out, ahead)
    to_crag = math.hypot(crag[0] - land_mid[0], crag[1] - land_mid[1])
    bridge = to_crag - (min(lx, lz) / 2 - 0.5) - (crag_r - 3)
    if not 10 <= bridge <= 50:
        fail("the footbridge is %.1f studs long; it should be a short walk (10 to 50)" % bridge)
    # The house inside the fence: its front wall four past the middle, going back HOUSE_D, HOUSE_W across.
    fence = crag_r - 1.5
    corner = math.hypot(4 + house_d + 0.6, house_w / 2 + 1)
    if corner > fence - 1:
        fail("the house's back corners (%.1f from the middle) are not inside the fence (%.1f)" % (corner, fence))
    for name, pattern in (("apple tree", r"appleTree\(garden, top - across \* ([\d.]+) \+ inward \* ([\d.]+)\)"),
                          ("bench", r"bench\(garden, top \+ across \* ([\d.]+) - inward \* ([\d.]+), out\)")):
        found = re.search(pattern, HOUSE)
        if not found:
            fail("this check can no longer read where the %s stands" % name)
        elif math.hypot(float(found.group(1)), float(found.group(2))) + 4 > fence:
            fail("the %s stands against or past the fence" % name)
    if not re.search(r"local a = rng:NextNumber\(-1\.2, 1\.2\)", HOUSE) or "local dir = (out * math.cos(a)" not in HOUSE:
        fail("the crag's rocks are not kept to its far side from the route")
for needle, why in (
    ("-- THE LANDING at the route's end, flush with the last chunk", "the landing is not at the route's end"),
):
    if needle not in HOUSE:
        fail("HillHouseService: " + why)
if re.search(r'"LandingLeg"|"Trestle"', HOUSE):
    fail("HillHouseService: a leg goes down from the landing or the bridge, through the spiral below")
if 'part(model, "BridgeBrace"' not in HOUSE or "local foot = endAt + toward * 1 +" not in HOUSE:
    fail("HillHouseService: the footbridge is not braced off the crag")
if 'local guard = part(model, "BridgeGuard"' not in HOUSE:
    fail("HillHouseService: nothing stops a step off the side of the footbridge")
mist = number(HOUSE, "MIST_OVER_KILL")
if mist is not None and not 0 < mist < 40:
    fail("the mist's top is not just over the kill plane (so a fall goes into it), under the lowest chunk")
if "picketFence(garden, top, CRAG_R - 1.5, topY, endAt)" not in HOUSE:
    fail("HillHouseService: the top has no fence round it")

# ===================================================================== wired and put away
for needle, why in (
    ('local hillModule = Services:WaitForChild("HillHouseService", 5)', "Bootstrap never looks for HillHouseService"),
    ("HillHouseService.start(levelInstance.finishFrame, workspace:WaitForChild(\"Levels\"), levelInstance.centre,",
     "Bootstrap never builds the house at the route's end"),
    ("if houseOk then\n\t\t\t\tif levelInstance.finishPart then\n\t\t\t\t\tlevelInstance.finishPart.CanTouch = false",
     "the old finish line is not stood down, so the run ends before the house"),
    ("\tif HillHouseService then\n\t\tpcall(HillHouseService.stop)\n\tend\n\tlevelInstance = LevelService.startLevel",
     "the house is not taken down before the next level is built"),
    ("\tif HillHouseService then\n\t\tpcall(HillHouseService.stop)\n\tend\n\tLevelService.endLevel()",
     "the house's ground stays when the level goes"),
    ('ending = "at his front door"', "Bootstrap does not say how Hill House ends"),
):
    if needle not in BOOT:
        fail("Bootstrap: " + why)
for needle, why in (
    ("workspace.Terrain:FillBlock(region.cf, region.size, Enum.Material.Air)", "the crag's ground is never cleared"),
    ("\tclearTerrain()\nend", "stopping does not clear the crag's ground"),
    ("\tHillHouseService.stop()\n\tlocal model = Instance.new(\"Model\")", "a second start builds a second house"),
    ('open.ActionText = "Go in"', "the door does not say what it does"),
    ("local turn = hinge.CFrame * CFrame.Angles(0, math.rad(-100), 0)", "the door swings out at you"),
    ("if arrived[player] then\n\t\t\treturn", "the door ends the level for the same player twice"),
    ("open.Enabled = false", "the door's prompt stays up once it is open"),
    ('take.ActionText = "Take the key"', "the key's prompt does not say what it does"),
    ('scene:FireClient(player, "key", model)', "taking the key plays no scene"),
    ("task.delay(KEY_ARRIVE, function()\n\t\t\tif player.Parent then\n\t\t\t\tonArrive(player)", "taking the key ends nothing"),
    ("\tif takePrompt then\n\t\ttakePrompt:Destroy()", "the key's prompt is left behind when the house goes"),
):
    if needle not in HOUSE:
        fail("HillHouseService: " + why)

# ===================================================================== the hall
door_handler = HOUSE.split("open.Triggered:Connect", 1)[-1].split("local take = ", 1)[0]
if "onArrive" in door_handler:
    fail("HillHouseService: the door still ends the level; it is the key in the hall that does")
stopped = re.search(r"^local CLOCK_STOPPED_HOUR, CLOCK_STOPPED_MINUTE = (\d+), (\d+)", HOUSE, re.M)
if not stopped or (stopped.group(1), stopped.group(2)) != ("11", "56"):
    fail("HillHouseService: his clock is not stopped at four minutes to midnight (11:56), as the scene says")
for name in ("HallSpot", "HallKey", "ClockFace", "ClockFacing", "PendulumPivot", "HallBack"):
    if 'model:SetAttribute("%s"' % name not in HOUSE:
        fail("HillHouseService: the house never says where its %s is, and the scene reads it" % name)
    if 'GetAttribute("%s")' % name not in CLIENT:
        fail("HillHouseClient: the scene does not read %s" % name)
for name in ("PendulumRod", "PendulumBob"):
    if '"%s"' % name not in HOUSE or 'FindFirstChild("%s", true)' % name not in CLIENT:
        fail("the %s is not built by that name, or the scene does not find it" % name)
if 'key.Name = "HallKey"' not in HOUSE or 'FindFirstChild("HallKey", true)' not in CLIENT:
    fail("the key on its hook is not built as HallKey, or the scene does not hide it")
for part, server, client in (
    ("rod", r'"PendulumRod", Vector3\.new\([^)]*\), pivot \* CFrame\.new\(0, (-[\d.]+), 0\)',
     r"rod\.CFrame = swung \* CFrame\.new\(0, (-[\d.]+), 0\)"),
    ("bob", r'"PendulumBob", Vector3\.new\([^)]*\), pivot \* CFrame\.new\(0, (-[\d.]+), 0\)',
     r"bob\.CFrame = swung \* CFrame\.new\(0, (-[\d.]+), 0\)"),
):
    a, b = re.search(server, HOUSE), re.search(client, CLIENT)
    if not (a and b) or a.group(1) != b.group(1):
        fail("HillHouseClient swings the pendulum's %s from somewhere other than where the server hangs it" % part)
for value in re.findall(r"\.Brightness = ([\d.]+)", HOUSE):
    if float(value) > 1.5:
        fail("HillHouseService: a light at Brightness %s; the hall is lit softly (1.5 at most)" % value)
for needle, why in (
    ('ensureRemoteEvent(remoteEventsFolder, "HillScene")', "never makes RemoteEvents.HillScene"),
    ('"HillHouseClient", "HubLeverService"', "does not list HillHouseClient for the paste check"),
    ('"KeyLift", "ClockStart"', "does not list the hall's sounds (KeyLift, ClockStart)"),
):
    if needle not in BOOT:
        fail("Bootstrap: " + why)
if '"HillHouseClient", "AmbienceService"' not in CLIENT_BOOT:
    fail("the client Bootstrap never starts HillHouseClient")
if not CLIENT:
    fail("there is no src/Client/Services/HillHouseClient.lua")
# YOU ACT IT (the hundred-and-twentieth pass): reaching up, the key in your hand, to the door; given back after.
for needle, why in (
    ('model:SetAttribute("HallDoor", hall.door)', "the hall never says where its door is, to go to"),
):
    if needle not in HOUSE:
        fail("HillHouseService: " + why)
for needle, why in (
    ('local door = model:GetAttribute("HallDoor")', "you never go to the door"),
    ("humanoid:MoveTo(door)", "you never go to the door"),
    ("current.handKey = keyInHand(character)", "the key never comes away in your hand"),
    ("if not current.keyed and t >= KEY_TAKEN then\n\t\tcurrent.keyed = true\n\t\thideKey(current.model, true)",
     "the key leaves its hook before your hand is at it, or never"),
    ("local function heldPose(name: string, t: number): CFrame?", "you stand still while you take it"),
    ("RunService.Stepped:Connect(function()\n\t\tlocal ok, err = pcall(poseScene)", "you are posed before the animations, which undo it"),
    ("if humanoid and current.speed then\n\t\thumanoid.WalkSpeed = current.speed", "your walk is left slow after the scene"),
    ("Cinema.point(CFrame.lookAt(back, here + Vector3.new(0, 0.4, 0)), 50)", "the last shot does not follow you to the door"),
):
    if needle not in CLIENT:
        fail("HillHouseClient: " + why)
for needle, why in (
    ('remotes:WaitForChild("HillScene", 20)', "does not listen for the server's word"),
    ('kind == "key"', "does not answer \"key\""),
    ("Cinema.done()", "never says the scene has been watched, so the lobby would wait for it"),
    ("Cinema.finish(", "never gives the camera back"),
):
    if needle not in CLIENT:
        fail("HillHouseClient: " + why)
for name in re.findall(r'Cinema\.sound\("(\w+)"', CLIENT):
    if not (ROOT / "audio" / "endings" / (name + ".wav")).exists():
        fail("HillHouseClient plays %s, and audio/endings/%s.wav is not made" % (name, name))
    if '"%s"' % name not in BOOT:
        fail("Bootstrap does not list the hall's sound %s" % name)
# ===================================================================== who is up here
for needle, why in (
    ('Townsfolk.spawn(model, "Gale", feet, "stand",', "nobody meets you at the top of the climb (Mr Gale)"),
    ('Townsfolk.spawn(garden, "Dunn", CFrame.lookAt(stand, Vector3.new(gate.X, topY, gate.Z)), "stand",',
     "nobody is at the gate (Mrs Dunn), or she faces away from it"),
    ("\tpeople(model, garden, landing, out, endAt, inward, across, topY)\n", "the people are never stood up"),
    ("local away = if landing.RightVector:Dot(out) > 0 then -1 else 1", "Mr Gale stands on the bridge's side of the landing"),
):
    if needle not in HOUSE:
        fail("HillHouseService: " + why)
gale_at = re.search(r"local spot = landing \* CFrame\.new\(away \* \(LANDING\.X / 2 - ([\d.]+)\), LANDING\.Y / 2, "
                    r"-\(LANDING\.Z / 2 - ([\d.]+)\)\)", HOUSE)
lx, ly, lz = (float(v) for v in re.search(r"^local LANDING = Vector3\.new\(([\d.]+), ([\d.]+), ([\d.]+)\)", HOUSE, re.M).groups())
if not gale_at:
    fail("this check can no longer read where Mr Gale stands")
else:
    # On the landing, in from its edges; and well off the line you walk from the top of the climb to the bridge.
    side_in, end_in = float(gale_at.group(1)), float(gale_at.group(2))
    if not (1.5 <= side_in < lx / 2 and 1.5 <= end_in < lz / 2):
        fail("Mr Gale stands at or over the landing's edge (%.1f in from its side, %.1f from its end)" % (side_in, end_in))
    gx, gz = -(lx / 2 - side_in), -(lz / 2 - end_in)  # the bridge's side is +x here
    ax, az, bx, bz = 0.0, lz / 2, min(lx, lz) / 2 - 0.5, 0.0  # from where you come up to where the bridge leaves
    t = max(0.0, min(1.0, ((gx - ax) * (bx - ax) + (gz - az) * (bz - az)) / ((bx - ax) ** 2 + (bz - az) ** 2)))
    if math.hypot(gx - (ax + t * (bx - ax)), gz - (az + t * (bz - az))) < 4:
        fail("Mr Gale stands in the way from the top of the climb to the bridge")
dunn_at = re.search(r"local stand = gate \+ inward \* ([\d.]+) \+ across \* ([\d.]+)", HOUSE)
if not dunn_at or float(dunn_at.group(2)) < 2.6 + 1.6:
    fail("Mrs Dunn stands on the path or in the lamb's ear beside it")
elif float(dunn_at.group(1)) < 2:
    fail("Mrs Dunn stands in the gateway")

# THE MIST IS SOLID (the hundred-and-eighteenth pass): see-through and nineteen hundred studs across, it was drawn after
# the chunks across the spiral and painted over the honey, slime and soda. And no grass in the house or up the path.
mist_fn = HOUSE[HOUSE.find("local function mistSheets("):HOUSE.find("local function farHill(")]
if not mist_fn or re.search(r"sheet\.Transparency\s*=\s*(?!0\b)", mist_fn) or mist_fn.count('cylinder(parent, "Mist"') != 1:
    fail("HillHouseService: the mist is see-through again (or more than one sheet), and it hides the translucent chunks")
for needle, why in (
    ("fillBlock(CFrame.lookAt(houseMid - Vector3.new(0, 1.5, 0), houseMid - Vector3.new(0, 1.5, 0) + inward),\n"
     "\t\tVector3.new(HOUSE_W + 4, 3, HOUSE_D + 4), Enum.Material.Ground)", "grass grows up through the hall's floor"),
    ("Vector3.new(4.5, 3, pathLong + 3), Enum.Material.Ground)", "grass grows up through the stepping stones"),
    ("table.insert(filled, { cf = cf, size = size + Vector3.new(4, 4, 4) })", "the bare ground is not cleared with the crag"),
    # (The hundred-and-twenty-eighth pass, from your test: the grass still grew in the hall. A fill over the grass
    # leaves a cell grass where it fills no more of it than the grass did; each cell's material is changed outright.)
    ("workspace.Terrain:ReplaceMaterial(Region3.new(Vector3.new(x, y0, z), Vector3.new(x + 4, y0 + 16, z + 4)), 4,\n"
     "\t\t\t\t\tEnum.Material.Grass, Enum.Material.Ground)", "the grass under the house is filled over, not taken away"),
    ("local y0 = math.floor((mid.Y - 8) / 4) * 4", "the cells changed are not on the terrain's grid of four"),
    ("bareGround(houseMid, inward, HOUSE_W + 2, HOUSE_D + 2)", "grass grows up through the hall's floor"),
    ("bareGround(pathMid, inward, 4.5, pathLong + 3)", "grass grows up through the stepping stones"),
):
    if needle not in HOUSE:
        fail("HillHouseService: " + why)

# THE CAMERA KEPT IN THE HALL (the hundred-and-twenty-eighth pass, from your test: "I should not be able to go through
# the floor, my camera I mean"): the upstairs floor is solid (the camera went up through the hall's ceiling into the
# empty upstairs), and while your head is in the hall your camera is pulled in to the first wall, ceiling or floor it
# would pass (it went out through the window glass, which no camera stops at).
if not re.search(r'part\(parent, "Floor", [^\n]*\n\t\tEnum\.Material\.WoodPlanks, true\)', HOUSE):
    fail("HillHouseService: the upstairs floor is not solid, and the camera goes up through the hall's ceiling")
for needle, why in (
    ('model:SetAttribute("HallBox", hall.box)', "the hall never says where its room is"),
    ('model:SetAttribute("HallSize", hall.boxSize)', "the hall never says how big its room is"),
    ("boxSize = Vector3.new(W - 2, STOREY - 0.3 - floorY, D - 2)", "the hall's room is not wall to wall, floor to ceiling"),
):
    if needle not in HOUSE:
        fail("HillHouseService: " + why)
for needle, why in (
    ('RunService:BindToRenderStep("HillHallCamera", Enum.RenderPriority.Camera.Value + 1, function()',
     "the camera is not kept in the hall, or is kept in it before it has moved for the frame"),
    ('local box, size = model:GetAttribute("HallBox"), model:GetAttribute("HallSize")', "the camera never reads the hall"),
    ("camera.CFrame = CFrame.new(box:PointToWorldSpace(focus + run * math.max(t, 0))) * camera.CFrame.Rotation",
     "the camera is not pulled in along its own line"),
    ('if scene or (Cinema and Cinema.active()) or Players.LocalPlayer:GetAttribute("InLevel") == nil then',
     "the hall's walls hold a scene's camera too"),
):
    if needle not in CLIENT:
        fail("HillHouseClient: " + why)

# THE KEY'S SCENE SHOT AND ACTED AGAIN (the same pass, from your test: "the animation and the camera positioning should
# be fixed"): the first shot in front of you and to one side (it was behind your head, all hair and shoulder); you turn
# to the clock and it is over your shoulder, all of it in the picture; you start when it ticks; the key reached for at
# your chest, held at it, and carried low to the door.
for needle, why in (
    ("local eye = head + side * 3 + facing * 1.5 + Vector3.new(0, -0.5, 0)", "the key is taken with the camera behind your head"),
    ("(root :: BasePart).CFrame = (root :: BasePart).CFrame:Lerp(CFrame.lookAt(here, here + toClock), 0.12)",
     "you never turn to the clock"),
    ("local eye = head - toClock * (3 - 0.6 * k) + right * 1 + Vector3.new(0, 0.5, 0)", "the clock is not seen over your shoulder"),
    ("+ 0.22 * start, 0, 0)", "you do not start when the clock ticks"),
    ("return CFrame.Angles(1.7 * reach * (1 - bring) + 0.85 * bring * (1 - lower) + 0.3 * lower, 0,",
     "your arm reaches up over the key, or sticks out as you go"),
):
    if needle not in CLIENT:
        fail("HillHouseClient: " + why)

code = "\n".join(line.split("--", 1)[0] for line in HOUSE.splitlines())
if "Neon" in code:
    fail("HillHouseService: something is Neon; this project lights nothing with fake light")
if 'words.FontFace = Style.WORLD.sign' not in HOUSE or 'Instance.new("SurfaceGui")' not in HOUSE:
    fail("HillHouseService: the house's name is not in the world's print on its gatepost")

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("hill house: level 5, first in the story at eight in the morning, ending at the house; the crag clear of the "
      "route on every turn, the footbridge a short walk braced off the crag, the house and garden inside the fence, "
      "the mist under the route; wired, stood down and its ground cleared; the key in the hall ends it, after its "
      "scene, with his clock at four to midnight and the pendulum where the server hangs it; Mr Gale and Mrs Dunn "
      "out of the way; no Neon.")
