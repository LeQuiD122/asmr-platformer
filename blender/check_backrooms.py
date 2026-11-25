"""The back rooms of the baths (BackRoomsService), checked without Studio.

    python blender/check_backrooms.py

Reads the map out of BackRoomsService.lua (one character a tile) and the wiring out of Bootstrap and AmbienceService,
and holds them to what the back rooms are for:

  THE MAP     closed all round; one place to arrive (S) and one way out (D), in the outer wall; every floor tile can
              be walked to from S; the sealed room (x) cannot, and the locked staff door (L) stands on a corridor; the
              way out is a long walk from S (it is meant to be found, not seen).
  THE LIGHT   a tube in the ceiling over every floor tile where x and y are 2 more than a multiple of 3, and no floor
              tile further than three tiles from one; real lights (SurfaceLights, no Neon), modest, never dark (the one
              that stutters drops to a third, not to nothing).
  THE ROOM    walls carpet to ceiling, the ceiling resting on them, the tube panels set into it: nothing floats.
  THE WAY IN  BACKROOMS_FALLS falls in one run, once a run, never announced; the kill plane leaves the back rooms
              alone; a respawn is never left in them.
  THE WAY OUT the door's prompt; Hardcore back to the start (clock reset), Chill to the checkpoint, the lobby if the
              run is gone.
  THE SOUND   the baths' own hum (AmbienceService's backRooms bed).
  HIS HANDS   (the hundred-and-sixty-seventh pass) caught, he is squared up to you GRIP studs off on open floor and
              your screen sets you there; his hold, worked out from his rig's own joints, closes his hands at your sides
              at chest height with his fingers behind your back, his feet on the carpet, his elbows inside a corridor,
              nothing of him inside you and his face over yours; and the shots of it never past a wall.
"""
import math
import pathlib
import re
import sys
from collections import deque

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
ROOMS = (SRC / "Server" / "Services" / "BackRoomsService.lua").read_text(encoding="utf-8")
BOOT = (SRC / "Server" / "Bootstrap.server.lua").read_text(encoding="utf-8")
AMBIENCE = (SRC / "Client" / "Services" / "AmbienceService.lua").read_text(encoding="utf-8")
HUB = (SRC / "Server" / "Services" / "HubService.lua").read_text(encoding="utf-8")
SQUISH = (SRC / "Server" / "Services" / "SquishRoomService.lua").read_text(encoding="utf-8")
LAYOUT = (SRC / "Shared" / "LobbyLayout.lua").read_text(encoding="utf-8")

problems = []


def fail(message):
    problems.append(message)


def number(text, name):
    found = re.search(r"^local %s = (-?[0-9.]+)" % name, text, re.M)
    return float(found.group(1)) if found else None


# ===================================================================== the map
block = re.search(r"local MAP = \{\n(.*?)\n\}", ROOMS, re.S)
MAP = re.findall(r'^\t"([^"]*)",$', block.group(1), re.M) if block else []
if not MAP:
    print("FAIL: BackRoomsService has no MAP this check can read")
    sys.exit(1)
H, W = len(MAP), len(MAP[0])
if any(len(row) != W for row in MAP):
    fail("the map's rows are not all the same width")
cells = {(x, y): MAP[y][x] for y in range(H) for x in range(min(W, len(MAP[y])))}
for (x, y), c in cells.items():
    if c not in "#.SDLx":
        fail("the map has a tile it does not know: %r at %d,%d" % (c, x, y))
    edge = y in (0, H - 1) or x in (0, W - 1)
    if edge and c not in "#D":
        fail("the back rooms are open to the void at %d,%d" % (x, y))
starts = [p for p, c in cells.items() if c == "S"]
doors = [p for p, c in cells.items() if c == "D"]
if len(starts) != 1 or len(doors) != 1:
    fail("there must be one place to arrive (S) and one way out (D): %d and %d" % (len(starts), len(doors)))
floor = {p for p, c in cells.items() if c in ".S"}
reached = {}
if starts:
    reached[starts[0]] = 0
    queue = deque([starts[0]])
    while queue:
        x, y = queue.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n in floor and n not in reached:
                reached[n] = reached[(x, y)] + 1
                queue.append(n)
lost = floor - set(reached)
if lost:
    fail("floor that cannot be walked to from where you arrive: %s" % sorted(lost)[:6])
for (x, y), c in cells.items():
    if c == "x":
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if cells.get((x + dx, y + dy)) in (".", "S"):
                fail("the sealed room is open to the rooms at %d,%d" % (x, y))
    if c == "L" and not any(cells.get((x + dx, y + dy)) == "." for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
        fail("the locked staff door at %d,%d faces no corridor" % (x, y))
walk = 0
if doors:
    dx_, dy_ = doors[0]
    if not (dx_ in (0, W - 1) or dy_ in (0, H - 1)):
        fail("the way out is not in the outer wall")
    fronts = [reached.get((dx_ + a, dy_ + b)) for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1))]
    fronts = [f for f in fronts if f is not None]
    if not fronts:
        fail("the way out cannot be reached")
    else:
        walk = min(fronts)
        if walk < 30:
            fail("the way out is only %d tiles from where you arrive; it is meant to be found" % walk)

# ===================================================================== the light
rule = re.search(r"x % (\d+) == (\d+) and y % (\d+) == (\d+)", ROOMS)
if not rule or rule.group(1) != rule.group(3) or rule.group(2) != rule.group(4):
    fail("this check can no longer read where the tubes go")
    lights = []
else:
    step, off = int(rule.group(1)), int(rule.group(2))
    lights = [(x, y) for (x, y) in floor if x % step == off and y % step == off]
worst = 0
for (x, y) in reached:
    if lights:
        near = min(max(abs(x - lx), abs(y - ly)) for lx, ly in lights)
        worst = max(worst, near)
if not lights or worst > 3:
    fail("a floor tile is %d tiles from the nearest tube; no tile may be further than three (never dark)" % worst)
brightness = number(ROOMS, "LIGHT_BRIGHTNESS")
if brightness is None or not (0.6 <= brightness <= 1.2):
    fail("the tubes are too dim or too bright (LIGHT_BRIGHTNESS between 0.6 and 1.2)")
for needle, why in (
    ('Instance.new("SurfaceLight")', "the tubes give no real light"),
    ("light.Face = Enum.NormalId.Bottom", "the tubes do not shine down"),
    ("light.Shadows = false", "sixty tubes casting shadows"),
    ("failing.Brightness = LIGHT_BRIGHTNESS * 0.33", "the stuttering tube goes dark (it drops to a third)"),
):
    if needle not in ROOMS:
        fail(why)
if "Neon" in ROOMS:
    fail("the back rooms fake light with Neon")

# ===================================================================== the room: nothing floats
for needle, why in (
    ('part("Wall", Vector3.new(span * TILE, HEIGHT, TILE)', "the walls do not go from carpet to ceiling"),
    ("Vector3.new((from + span / 2) * TILE, HEIGHT / 2, (y + 0.5) * TILE)", "the walls do not stand on the carpet"),
    ("CFrame.new(ORIGIN + Vector3.new(cols * TILE / 2, HEIGHT + 0.5, rows * TILE / 2))", "the ceiling does not rest on the walls"),
    ("CFrame.new(tileAt(x, y, HEIGHT - 0.1))", "the tube panels are not set into the ceiling"),
    ('part("TubePanel", Vector3.new(TILE * 0.8, 0.2, TILE * 0.8)', "the tube panels are not set into the ceiling"),
    ("CFrame.new(ORIGIN + Vector3.new(cols * TILE / 2, -0.5, rows * TILE / 2))", "the carpet is not under the floor"),
):
    if needle not in ROOMS:
        fail(why)
if ROOMS.count("outward * (TILE / 2 + 0.11)") + ROOMS.count("inward * (TILE / 2 + 0.11)") + ROOMS.count("TILE / 2 + 0.11), Vector3.new(0, 0, 1)") < 3:
    fail("a sign is not on its wall")

# ===================================================================== far from everything
origin = re.search(r"local ORIGIN = Vector3\.new\((-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\)", ROOMS)
# The lobby's origin is LobbyLayout's (the hundredth pass), and HubService takes it from there.
hub = re.search(r"LobbyLayout\.ORIGIN = Vector3\.new\((-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\)", LAYOUT) \
    if "local HUB_ORIGIN = LobbyLayout.ORIGIN" in HUB else None
squish = re.search(r"local ROOM_ORIGIN = Vector3\.new\((-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\)", SQUISH)
if origin and hub and squish:
    ox, oz = float(origin.group(1)), float(origin.group(3))
    for name, other in (("the lobby", hub), ("the squish room", squish)):
        gap = ((ox - float(other.group(1))) ** 2 + (oz - float(other.group(3))) ** 2) ** 0.5
        if gap < 3000:
            fail("the back rooms are only %.0f studs from %s" % (gap, name))
    # Levels are laid along +x from the origin, a run every RUN_SPACING: the back rooms keep to the other side.
    if ox > -3000:
        fail("the back rooms are on the side where levels are built")
else:
    fail("this check can no longer read where the back rooms, the lobby or the squish room are")

# ===================================================================== the way in and the way out
falls = number(BOOT, "BACKROOMS_FALLS")
if falls is None or not (5 <= falls <= 10):
    fail("BACKROOMS_FALLS is not a number of falls that only someone really stuck reaches (5 to 10)")
for needle, why in (
    ("state.falls = (state.falls or 0) + 1", "falls in a run are not counted"),
    ("state.falls >= BACKROOMS_FALLS and not state.backRooms then\n\t\t\t\tstate.backRooms = true", "the back rooms come more than once a run"),
    ('if player:GetAttribute("InLevel") == "backRooms" then\n\t\t\tcontinue', "the kill plane catches someone in the back rooms"),
    ('player:SetAttribute("InLevel", "backRooms")', "a client is not told it is in the back rooms (no hum, the level's own effects on)"),
    ("hrp.CFrame = BackRoomsService.arrival()", "nobody is ever put in the back rooms"),
    ("pcall(BackRoomsService.build, leaveBackRooms)", "the back rooms are never built, or have no way out"),
    ('player:SetAttribute("InLevel", if inRunNow then runBackdrop else nil)', "a respawn is left marked as in the back rooms"),
):
    if needle not in BOOT:
        fail("Bootstrap: " + why)
leave = BOOT[BOOT.find("local function leaveBackRooms("):BOOT.find("if BackRoomsService then\n\ttask.spawn(")]
# HE IS CALLED OFF AS YOU GO THE WAY OUT (in leaveBackRooms itself: the way back through the door calls him off too,
# and must not stand in for it).
leave_fn = BOOT[BOOT.find("local function leaveBackRooms("):BOOT.find("backRoomsLeave = leaveBackRooms")]
if "\tif BackRoomsService.callOff then\n\t\tBackRoomsService.callOff(player)\n\tend\n" not in leave_fn:
    fail("Bootstrap: he follows you out through the way out")
for needle, why in (
    ('player:SetAttribute("InLevel", runBackdrop)', "the way out leaves the client thinking it is still in the back rooms"),
    ("restartRunFor(player)", "Hardcore is not sent back to the start by the way out"),
    ("hrp.CFrame = CFrame.new(groundedRecovery(behind, state.checkpointPosition))", "Chill is not sent back to the checkpoint"),
    ("HubService.returnToHub(player)", "someone whose run is over is left in the back rooms"),
):
    if needle not in leave:
        fail("Bootstrap: " + why)
if "prompt.Triggered:Connect(function(player: Player)" not in ROOMS or 'prompt.ActionText = "Go back"' not in ROOMS:
    fail("BackRoomsService: the way out has no prompt")
if "backRooms = {\n\t\t{ name = \"BathsHum\"," not in AMBIENCE:
    fail("AmbienceService: the back rooms do not hum")

ECONOMY = (SRC / "Server" / "Services" / "EconomyService.lua").read_text(encoding="utf-8")
if 'check("the back rooms built, with one way out", wayOut == 1,' not in ECONOMY         or 'CollectionService:AddTag(door, "BackRoomsExit")' not in ROOMS:
    fail("the Self-test does not check the back rooms were built with their way out")

# THE LOBBY'S BACK CORRIDOR: walkable (its floor and walls solid), and at its end a way in for someone who has found
# the back rooms by falling (their save), from the lobby only; a dead end for everyone else. A fall into them marks
# them found. The test panel's "Back rooms" goes there now.
door = HUB[HUB.find("local function buildBackDoor("):HUB.find("function HubService.buildKiosk(")]
for needle, why in (
    ('if item:IsA("BasePart") and (item.Name == "BackWall" or item.Name == "BackFloor") then\n\t\t\titem.CanCollide = true',
     "the lobby's back corridor drops you through its floor"),
    ("threshold.CanTouch = true", "the lobby's back corridor has no way in at its end"),
    ("local enter = backRoomsDoor", "the end of the lobby's back corridor does nothing"),
    ('local frame = propAt("Hub_Doorframe", at + Vector3.new(0, 3.2, 0), parent, facing)',
     "the lobby's back doorframe is sunk to its middle in the deck (a MeshPart sits on its box's middle)"),
):
    if needle not in door:
        fail("HubService: " + why)


# AND YOU CAN WALK IT TO ITS END (the hundredth pass): from outside the house's doorway, through the door, down the
# first stretch and round the turn to the way in, on the corridor's own floor plan (its walls and the house's, in the
# doorway's frame), keeping a stud of body clear of every wall. Two of the turn's walls once ran straight across the
# first stretch, so the corridor ended seven studs in and its way in could never be reached; nothing said so.
def corridor_walls(block):
    walls = []
    number = r"(-?[\d.]+)"
    for sx, _, sz, cx, _, cz in re.findall(r'slab\("BackWall", Vector3\.new\(%s, %s, %s\), CFrame\.new\(%s, %s, %s\)'
                                           % ((number,) * 6), block):
        walls.append((float(cx), float(cz), float(sx), float(sz)))
    house = block[block.find("-- THE HOUSE ROUND IT"):block.find('slab("BackHouseRoof"')]
    for sx, sy, sz, cx, cy, cz in re.findall(r"\{ Vector3\.new\(%s, %s, %s\), CFrame\.new\(%s, %s, %s\) \}"
                                             % ((number,) * 6), house):
        # Only what reaches down to where you walk: the piece over the doorway is a lintel.
        if float(cy) - float(sy) / 2 < 2:
            walls.append((float(cx), float(cz), float(sx), float(sz)))
    return walls


def corridor_walkable(block):
    threshold = re.search(r'slab\("BackRoomsThreshold", Vector3\.new\(([\d.]+), [\d.]+, ([\d.]+)\), '
                          r'CFrame\.new\((-?[\d.]+), [\d.]+, (-?[\d.]+)\)', block)
    walls = corridor_walls(block)
    if not threshold or len(walls) < 6:
        return None
    tw, td, tx, tz = (float(v) for v in threshold.groups())
    step, body = 0.25, 0.9
    xs = [-8 + i * step for i in range(int(28 / step))]
    zs = [-8 + j * step for j in range(int(30 / step))]

    def free(x, z):
        return all(abs(x - cx) > sx / 2 + body or abs(z - cz) > sz / 2 + body for cx, cz, sx, sz in walls)

    start = (int((0 - xs[0]) / step), int((-5 - zs[0]) / step))
    seen = {start}
    queue = deque([start])
    while queue:
        i, j = queue.popleft()
        x, z = xs[i], zs[j]
        if abs(x - tx) <= tw / 2 and abs(z - tz) <= td / 2:
            return True
        for di, dj in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ni, nj = i + di, j + dj
            if 0 <= ni < len(xs) and 0 <= nj < len(zs) and (ni, nj) not in seen and free(xs[ni], zs[nj]):
                seen.add((ni, nj))
                queue.append((ni, nj))
    return False


walkable = corridor_walkable(door)
if walkable is None:
    fail("HubService: this check can no longer read the lobby's back corridor (its walls or its way in)")
elif not walkable:
    fail("HubService: the lobby's back corridor cannot be walked to its way in (a wall across it, or its door shut)")
corridor = BOOT[BOOT.find("HubService.setBackRoomsDoor(function(player: Player)"):]
corridor = corridor[:corridor.find("\n\tend)\nend\n")]
for needle, why in (
    ('if HubService.isInRun(player) or player:GetAttribute("InLevel") ~= nil or player:GetAttribute("InSquishRoom") then\n\t\t\treturn',
     "the corridor's way in works from a run or the squish room"),
    ("if not (EconomyService and EconomyService.foundBackRooms and EconomyService.foundBackRooms(player)) then\n\t\t\treturn",
     "the corridor takes someone in who has never found the back rooms (the secret is out)"),
    ('enterBackRooms(player, found, "lobby")', "the corridor's way in goes nowhere, or forgets you came by it"),
):
    if needle not in corridor:
        fail("Bootstrap: " + why)
send = BOOT[BOOT.find("local function sendToBackRooms("):BOOT.find("local function leaveBackRooms(")]
if "pcall(EconomyService.markFoundBackRooms, player)" not in send:
    fail("Bootstrap: falling into the back rooms does not count them as found")
ECONOMY_TEXT = (SRC / "Server" / "Services" / "EconomyService.lua").read_text(encoding="utf-8")
if "FoundBackRooms = false," not in ECONOMY_TEXT or "profile.Data.FoundBackRooms = true" not in ECONOMY_TEXT:
    fail("EconomyService: finding the back rooms is not kept in the save")
DEV_TEXT = (SRC / "Client" / "Services" / "DevPanelClient.lua").read_text(encoding="utf-8")
if '{ action = "backRooms", text = "Back rooms" }' not in DEV_TEXT or 'if action ~= "backRooms"' not in BOOT:
    fail("the test panel cannot go to the back rooms")

# THE SIXTH SECRET: the first time a save finds the back rooms (asked before they are marked found), once the screen
# has come back, the secret's scene on Mrs Venn's notice, its card and the notice in the journal; never again after.
INTERACT = (SRC / "Server" / "Services" / "Interactables.lua").read_text(encoding="utf-8")
if 'backRooms = { order = 6, title = "The back rooms"' not in INTERACT:
    fail("Interactables: the back rooms are not one of the secrets")
send_text = BOOT[BOOT.find("local function sendToBackRooms("):BOOT.find("local function leaveBackRooms(")]
asked = send_text.find("local first = not (EconomyService and EconomyService.foundBackRooms and EconomyService.foundBackRooms(player))")
marked = send_text.find("pcall(EconomyService.markFoundBackRooms, player)")
if asked < 0 or marked < 0 or asked > marked:
    fail("Bootstrap: whether the back rooms are found for the first time is asked after they are marked found (never told)")
for needle, why in (
    ("if first and Interactables and Interactables.reveal and BackRoomsService.secretShot then", "the back rooms' secret is told every time, or never"),
    ("task.delay(1.2, function()", "the back rooms' secret is told under the black, before the screen comes back"),
    ('player.Parent and player:GetAttribute("InLevel") == "backRooms" then', "the back rooms' secret is told to someone who has already left them"),
    ('pcall(Interactables.reveal, player, "backRooms", eye, focus, anchor)', "the back rooms' secret is never told"),
):
    if needle not in send_text:
        fail("Bootstrap: " + why)
if "noticePlate = sign(\"Notice\"," not in ROOMS or "function BackRoomsService.secretShot()" not in ROOMS:
    fail("BackRoomsService: the secret's scene has nothing to look at")

# IN THE BACK ROOMS, NOT IN THE LOBBY: no vote card on their screen (packed away going in), and left out of the
# players the lobby talks to (HubService.hubPlayers).
hub_players = HUB[HUB.find("function HubService.hubPlayers()"):]
hub_players = hub_players[:hub_players.find("\nend\n")]
if 'player:GetAttribute("InLevel") ~= "backRooms"' not in hub_players:
    fail("HubService: someone in the back rooms is still sent the lobby's vote")
enter_text = BOOT[BOOT.find("local function enterBackRooms("):BOOT.find("local function sendToBackRooms(")]
if 'HubVoteState:FireClient(player, "clear", {})' not in enter_text:
    fail("Bootstrap: the lobby's vote card stays up in the back rooms")

# ===== FROM THE SECOND TEST (2026-10-16): what walks down here, what the rooms have kept, and the two fixes =====
STORY_CLIENT = (SRC / "Client" / "Services" / "StoryClient.lua").read_text(encoding="utf-8")
# WHAT WALKS DOWN HERE: E. Marsh, out of the staff door, after a while or now and then sooner; slower than you walk, so
# the way out can be reached; and able to reach every room you can.
hunt_after = re.search(r"^local HUNT_AFTER, HUNT_CHANCE, HUNT_EARLY = ([\d.]+), ([\d.]+), NumberRange\.new\(([\d.]+), ([\d.]+)\)", ROOMS, re.M)
marsh_walk = re.search(r"^local WALK, WALK_LATE, CATCH = ([\d.]+), ([\d.]+), ([\d.]+)", ROOMS, re.M)
if not hunt_after or not marsh_walk:
    fail("BackRoomsService: this check can no longer read when he comes or how fast he walks")
else:
    if float(hunt_after.group(1)) != 30:
        fail("BackRoomsService: he comes after %s s lost, not 30" % hunt_after.group(1))
    if not (0.15 <= float(hunt_after.group(2)) <= 0.5):
        fail("BackRoomsService: he comes early %s of the time: 'sometimes' is neither never nor always" % hunt_after.group(2))
    if float(hunt_after.group(3)) < 8:
        fail("BackRoomsService: he can come before you have taken in where you are")
    if float(marsh_walk.group(2)) >= 16 or float(marsh_walk.group(1)) >= float(marsh_walk.group(2)):
        fail("BackRoomsService: he walks as fast as you, so the way out can never be reached first")
    if float(marsh_walk.group(3)) > 4:
        fail("BackRoomsService: he catches you from %s studs away" % walk.group(3))
# He can reach every tile you can: one flood from the staff door's open side covers every floor tile.
staff = None
for y, row in enumerate(MAP):
    for x, c in enumerate(row):
        if c == "L":
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= y + dy < len(MAP) and 0 <= x + dx < len(MAP[y + dy]) and MAP[y + dy][x + dx] == ".":
                    staff = (x + dx, y + dy)
if staff is None:
    fail("BackRoomsService: there is no staff door for him to come out of")
else:
    seen, todo = {staff}, [staff]
    while todo:
        cx, cy = todo.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = cx + dx, cy + dy
            if 0 <= ny < len(MAP) and 0 <= nx < len(MAP[ny]) and MAP[ny][nx] in ".S" and (nx, ny) not in seen:
                seen.add((nx, ny))
                todo.append((nx, ny))
    floor_tiles = {(x, y) for y, row in enumerate(MAP) for x, c in enumerate(row) if c in ".S"}
    if floor_tiles - seen:
        fail("BackRoomsService: %d tiles he can never reach (you could wait there forever)" % len(floor_tiles - seen))
for needle, why in (
    ("staffTile = { x = x + step[1], y = y + step[2] }", "he does not come out of the staff door"),
    ("path = wayTo(hx, hy, tx, ty)", "he does not find his way to you through the rooms"),
    ("light.Brightness = LIGHT_BRIGHTNESS * (if math.random() < 0.6 then 0.12 else 0.4)",
     "the lights nearest him do not die and stutter"),
    ("pcall(hunt.onCaught, player, head.Position)", "being caught does nothing"),
    ('remote:FireClient(player, "stalk", { at = head.Position, door = ', "you are never told something is coming, "
                                                                           "or the door he comes out of is not heard"),
    ("function BackRoomsService.callOff(player: Player)", "he is never called off"),
):
    if needle not in ROOMS:
        fail("BackRoomsService: " + why)
for needle, why in (
    ("BackRoomsService.hunt(player, caughtInBackRooms)", "nothing walks in the back rooms"),
    ('story:FireClient(player, "caught", { at = at })', "being caught is not seen"),
    ("backRoomsLeave = leaveBackRooms\n", "'Leave to the lobby' does nothing in the back rooms"),
    ('if player:GetAttribute("InLevel") == "backRooms" and not (levelInstance and HubService.isInRun(player)) then',
     "'Leave to the lobby' does nothing in the back rooms"),
):
    if needle not in BOOT:
        fail("Bootstrap: " + why)
caught_fn = BOOT[BOOT.find("local function caughtInBackRooms("):BOOT.find("local function enterBackRooms(")]
if "HubService.returnToHub(player)" not in caught_fn:
    fail("Bootstrap: being caught does not take you to the lobby")
for needle, why in (
    ('elseif kind == "caught" and typeof(data) == "table" then\n\t\t\t\tcaught(data)', "being caught has no scene"),
    ('elseif kind == "stalk" and typeof(data) == "table" then\n\t\t\t\tstalked(data)', "nothing tells you he is out"),
):
    if needle not in STORY_CLIENT:
        fail("StoryClient: " + why)
# ===== THE HUNDRED-AND-THIRD PASS: the way back, the place looked at closely, him made worse, the screamer =====
# NEVER QUITE DARK round him: every brightness the lights near him are set to is an eighth of a tube or more.
near_block = ROOMS[ROOMS.find("local function lightsNear("):ROOMS.find("local function chase(")]
levels = [float(v) for v in re.findall(r"then ([\d.]+) else ([\d.]+)\)", near_block) for v in v]
if not levels or min(levels) < 0.1:
    fail("BackRoomsService: the lights near him go dark (an eighth of a tube at the least, so he is always seen)")
# THE WAY BACK, from the lobby only: the door behind where you arrive takes back someone who came by the corridor.
for needle, why in (
    ('part("ReturnDoorway", Vector3.new(3.2, 6.4, 0.1)', "there is no door behind you to go back by"),
    ('walker:GetAttribute("BackRoomsFrom") == "lobby"', "the way back works for someone who fell in"),
    ("function BackRoomsService.setReturn(fn: (Player) -> ())", "the way back goes nowhere"),
    ('spill.Enabled = false', "the way back's light is on for everyone"),
):
    if needle not in ROOMS:
        fail("BackRoomsService: " + why)
for needle, why in (
    ('player:SetAttribute("BackRoomsFrom", how or "fall")', "how you came is not kept, so the way back cannot tell"),
    ('enterBackRooms(player, hrp, "fall")', "a fall is taken for the corridor"),
    ("BackRoomsService.setReturn(backThroughTheDoor)", "the door behind you does nothing"),
    ('HubService.returnToHub(player, if HubService.backDoorReturn then HubService.backDoorReturn() else nil)',
     "the way back does not put you back in the corridor"),
    ('player:GetAttribute("BackRoomsFrom") ~= "lobby" then', "the way back works for someone who fell in"),
):
    if needle not in BOOT:
        fail("Bootstrap: " + why)
for needle, why in (
    ("backReturnAt = CFrame.lookAt((turn * CFrame.new(5.2, 3, 10)).Position, (turn * CFrame.new(0, 3, 10)).Position)",
     "the corridor has no place to come back to, short of its way in"),
    ("hrp.CFrame = at or CFrame.new(HubService.spawnPosition())", "coming back puts you at the spawn, not the corridor"),
):
    if needle not in HUB:
        fail("HubService: " + why)
# The place back to is short of the corridor's way in (so arriving does not send you straight back down).
way_in = re.search(r'slab\("BackRoomsThreshold", Vector3\.new\(([\d.]+), [\d.]+, ([\d.]+)\), CFrame\.new\(([\d.]+), [\d.]+, ([\d.]+)\)', HUB)
back_to = re.search(r"backReturnAt = CFrame\.lookAt\(\(turn \* CFrame\.new\(([\d.]+), [\d.]+, ([\d.]+)\)\)", HUB)
if way_in and back_to:
    if float(way_in.group(3)) - float(way_in.group(1)) / 2 - float(back_to.group(1)) < 2:
        fail("HubService: coming back puts you on the corridor's way in, and straight back down")
# THE PLACE LOOKED AT CLOSELY: carpet and plaster, the ceiling's grid, the skirting and the damp; nothing colliding.
for needle, why in (
    ("CARPET, Enum.Material.Carpet, made)", "the carpet is not carpet"),
    ("WALL, Enum.Material.Plaster, made)", "the walls are not plaster"),
    ('flat("CeilingGrid", Vector3.new(0.22, 0.12, rows * TILE)', "the ceiling has no grid"),
    ('flat("Skirting", Vector3.new(TILE, 0.55, 0.12)', "the walls have no skirting"),
    ('flat("Damp", Vector3.new(', "the walls have no damp"),
):
    if needle not in ROOMS:
        fail("BackRoomsService: " + why)
flat_fn = ROOMS[ROOMS.find("local function flat("):ROOMS.find("for gx = 0, cols do")]
if "p.CanCollide = false" not in flat_fn:
    fail("BackRoomsService: the dressing can be walked into")
# HIM, WORSE: stooped and bowed under the ceiling, the seam where his face is not, rushing down a straight. And still
# slower than you over a straight: a rush is short.
# JOINTED AND WALKING (the hundred-and-twenty-first pass, from your test: "the animation for the monster in the
# backrooms is messed up and should be scarier"): he was one stiff block jumped along a few times a second, his seam
# left behind when his head twitched. Now every limb hangs on a joint (the stoop and the bow in the joints' rests), the
# seam is welded to the head, he is moved smoothly, and every screen draws him walking (StalkerClient).
for needle, why in (
    ('welded(head, seam, CFrame.new(0, -0.08, -0.56))', "his face has no seam to open, or it is left behind as his head turns"),
    ('joint("Spine", hips, torso, CFrame.new(0, 0.2, 0) * CFrame.Angles(math.rad(-16), 0, 0)', "he stands straight, not stooped"),
    ('joint("HeadJ", neck, head, CFrame.new(0, 0.45, 0) * CFrame.Angles(math.rad(-18), 0, 0)', "his head is not bowed"),
    ('joint("Knee" .. tag, thigh, shin,', "his legs have no knees to walk on"),
    ('joint("Elbow" .. tag, upper, lower,', "his arms have no elbows"),
    ("p.Anchored = false\n\tp.Massless = true", "his limbs are fixed in place, and nothing can move them"),
    ("rushUntil = now + 0.6", "he never rushes"),
    ('model:SetAttribute("Rushing", now < rushUntil)', "no screen is told when he rushes"),
    ('model:SetAttribute("Paused", not walking)', "no screen is told when he stops"),
):
    if needle not in ROOMS:
        fail("BackRoomsService: " + why)
if "nextFrame = now + 0.14" in ROOMS or "head.CFrame = frame * headRest" in ROOMS:
    fail("BackRoomsService: he is jumped along in jerks again, his head turned apart from his seam")
STALKER = (SRC / "Client" / "Services" / "StalkerClient.lua").read_text(encoding="utf-8") if (SRC / "Client" / "Services" / "StalkerClient.lua").exists() else ""
if not STALKER:
    fail("there is no StalkerClient: he is never drawn walking")
for needle, why in (
    ("hide(real)", "his own stiff body is drawn under the walking one"),
    ("\t\tanimate(one, dt, now, camera)\n", "he is drawn, but never walking"),
    ("one.at = one.at:Lerp(root.CFrame, 1 - math.exp(-dt * FOLLOW))", "he jumps from place to place"),
    ('drive(one, "Knee" .. side, CFrame.Angles(0.75 * math.max(0, -leg) * math.min(pace, 1.2), 0, 0))',
     "his knees bend the ordinary way (or not at all)"),
    ('drive(one, "Hip" .. side, CFrame.Angles(leg * swing * (if side == "R" then 0.7 else 1), 0, 0))', "his legs do not walk"),
    ('drive(one, "Shoulder" .. side, CFrame.Angles(1.4 + 0.12 * late, 0, -0.15 * sign))', "rushing, he does not reach for you"),
    ("if to.Magnitude < LOOK_NEAR and camera.CFrame.LookVector:Dot(-to.Unit) > 0.55 then", "his head never turns to look at you"),
    ("thud(one.at.Position, math.clamp(pace, 0.4, 1.2))", "his feet come down without a sound"),
    ("one.tilt += ((if paused and not staring then 0.7 else 0) - one.tilt)", "stopping, his head does not tip over"),
    ("if item:IsA(\"Sound\") then\n\t\t\titem:Destroy()", "his breath is heard twice"),
):
    if needle not in STALKER:
        fail("StalkerClient: " + why)
turn = re.search(r"^local LOOK_TURN, LOOK_PITCH, LOOK_NEAR = math\.rad\(([\d.]+)\)", STALKER, re.M)
if not turn or float(turn.group(1)) <= 100:
    fail("StalkerClient: his head turns only as far as a neck should (it should go further)")
CLIENT_BOOT_ = (SRC / "Client" / "Bootstrap.client.lua").read_text(encoding="utf-8")
if '"StalkerClient" }) do' not in CLIENT_BOOT_ or '"StalkerClient",' not in BOOT:
    fail("StalkerClient is never started, or not in the paste check")
# THE DREAD AND THE SCREAMER on your screen; the back rooms' own light, given back as you leave.
for needle, why in (
    ('local slam = folder and folder:FindFirstChild("DoorSlam")', "the staff door is not heard opening"),
    ("lightsWave(door)", "the lights do not go out from the door toward you"),
    ("heart.PlaybackSpeed = 0.85 + 0.6 * near", "your heart does not quicken as he nears"),
    ("fx.Saturation = -0.5 * near", "the picture does not drain as he nears"),
    ("face = screamerFace()", "being caught has no face to see"),
    ('sound("ScreamerStab", "rbxasset://sounds/bass.mp3", 1, 1)', "the screamer is silent"),
    ("light.Brightness = 0\n\tend\n\tsound(\"TubeDie\"", "the lights do not go out before he is there"),
    # (Not zoomed to a narrow lens a stud off his face any more, the hundred-and-thirty-third pass: that was two slabs.
    # Over your shoulder at a size you can read, and it flies at the lens.)
    # (And never past a wall behind you, the hundred-and-sixty-seventh pass.)
    # (Aimed a little over his head since pass 222, so the lid going up stays in the picture.)
    # (From the way with the most room since pass 223, still through Cinema.clear.)
    ("eye = CFrame.lookAt(Cinema.clear(aim + best * off + Vector3.new(0, 0.05, 0), aim, current.ignore), aim)",
     "his face is not seen whole, or the camera is past a wall"),
    ("local best, room = back, roomAlong(aim, back, 6.5, current.ignore)", "in a small room the lens is shoved up to his face"),
    ("local aim = his + Vector3.new(0, 0.45, 0)", "the lid going up leaves the picture"),
    # (Pass 222: the made head shudders, throws open past wide, its fangs grow and its spit snaps.)
    ("setFang(entry, tipped, grow)", "the fangs do not come out of the gums as he opens"),
    ("strand.broken = true", "the spit does not snap, or joins again"),
    ("current.mine[item] = true", "your own hair or hat can fill the shot of his face"),
    ("local fits = math.deg(2 * math.atan(2.1 / math.max(near, 0.5)))", "in a small room his face fills the screen"),
    ('piece("Chin"', "his lower fangs stand on nothing"),
    ("local lidRoot = -hh * 0.4", "his upper fangs are inside his head, never seen"),
    ("1 + 2.70158 * q * q * q + 1.70158 * q * q", "the mouth does not throw open past wide"),
    ("local from = his:Lerp(eye.Position + eye.LookVector * 1.4, lunge)", "his face does not lunge at you"),
    ('grade.Name = "BackRoomsGrade"', "the back rooms have no light of their own"),
    ("backRoomsLight(down)", "the back rooms' light stays on after you leave"),
    ('local open = Players.LocalPlayer:GetAttribute("BackRoomsFrom") == "lobby"', "the door you came in by is lit for "
                                                                                    "someone who fell in"),
):
    if needle not in STORY_CLIENT:
        fail("StoryClient: " + why)

# ONLY THE HUM: the lobby's sounds hushed while you are down here (and, since the hundred-and-thirtieth pass, in every
# level: "I have lobby sounds in my level games"), and given back.
if "hushLobby(wanted ~= nil)" not in AMBIENCE:
    fail("AmbienceService: the lobby's sea follows you into the back rooms")
# Hushed through a sound group of the screen's own, because the server keeps setting the wind's volume and keeps
# making new breakers: anything new in the lobby while you are down there goes into the group too.
for needle, why in (
    ("\t\titem.SoundGroup = lobbyGroup()\n", "the lobby's sounds are hushed by their own volumes, which the server sets again"),
    ("hub.DescendantAdded:Connect(intoHush)", "a breaker made while you are down there is heard"),
    ('if child.Name == "Hub" then\n\t\t\t\twatchHub(child)', "the lobby put back after a run is heard down there"),
    ("TweenService:Create(group, TweenInfo.new(1.5), { Volume = 1 }):Play()", "the lobby stays silent after you leave"),
):
    if needle not in AMBIENCE:
        fail("AmbienceService: " + why)
# WHAT THE ROOMS HAVE KEPT: sunk into walls, carpet and ceiling, held by them (never less than two fifths in), never
# reaching across a corridor out of a wall, never solid.
# (Looked for in decor itself: the dressing's own helper, flat, says the same thing and must not stand in for it.)
decor_fn = ROOMS[ROOMS.find("local function decor("):ROOMS.find("-- Each built standing on its base")]
if "p.CanCollide = false" not in decor_fn:
    fail("BackRoomsService: a sunk thing is in your way")
for needle, why in (
    ("\tsinkThings(made)\n", "nothing is sunk into the back rooms"),
    ("math.max(rng:NextNumber(0.4, 0.62), 1 - WALL_REACH / long)", "a thing in a wall reaches across the corridor"),
    ('if wrong == "tall" or (wrong == "giant" and THINGS[name].tall > 2) then', "a thing in a wall is stretched across the corridor"),
):
    if needle not in ROOMS:
        fail("BackRoomsService: " + why)
reach = re.search(r"^local WALL_REACH = ([\d.]+)", ROOMS, re.M)
if not reach or float(reach.group(1)) > (number(ROOMS, "TILE") or 4) / 2 + 0.3:
    fail("BackRoomsService: a thing may reach more than half a corridor out of a wall")
shares = re.findall(r"rng:NextNumber\(([\d.]+), ([\d.]+)\)", ROOMS[ROOMS.find("local function sinkThings("):ROOMS.find("-- ===== WHAT WALKS DOWN HERE")])
if not shares or min(float(a) for a, _ in shares if float(a) < 1) < 0.4:
    fail("BackRoomsService: a thing is sunk less than two fifths in, so it hangs off the wall rather than out of it")
tall_things = dict((n, float(t)) for n, t in re.findall(r"^\t(\w+) = \{ tall = ([\d.]+), make", ROOMS, re.M))
height = number(ROOMS, "HEIGHT")
for name, tall in tall_things.items():
    for scale in (1.9, 2.3):
        if height and tall * scale * (1 - 0.45) > height - 0.5:
            fail("BackRoomsService: the %s, stretched or giant, would come up through the ceiling" % name)

# ===================================================================== in his hands (167)
# From your note of 2026-11-03: "fix the issue with the backrooms animation where it incorrectly positions the characters
# in the hands of the monster". His hands closed six studs out from him and above your head, round nothing, wherever you
# were. Now: at the catch he is squared up to you GRIP studs off on open floor and facing you (BackRoomsService), your
# own screen sets you exactly there in the black (StoryClient's holdMe), and his hold (StalkerClient's HOLD) is checked
# here by his rig's own sums: his hands at your sides at chest height, his fingers behind your back, his feet on the
# carpet, his elbows inside a four-stud corridor, his body and head clear of yours, his face over yours.
grip = re.search(r"^local GRIP = ([\d.]+)", ROOMS, re.M)
GRIP = float(grip.group(1)) if grip else 0.0
for needle, why in (
    ("local spot = squaredUp(target.Position, here)\n\t\t\tif spot then\n\t\t\t\there = spot\n"
     "\t\t\t\tmodel:PivotTo(CFrame.lookAt(here, Vector3.new(target.Position.X, here.Y, target.Position.Z)))\n"
     '\t\t\t\tmodel:SetAttribute("Grip", GRIP)', "he is not squared up to you at the catch, or your screen is not told how far"),
    ("if back.Magnitude > 0.05 and openLine(feet, feet + back.Unit * GRIP) then", "he is not held back the way he came"),
    ("if openLine(feet, spot) and (spot - him).Magnitude < nearest then", "he may be squared up into a wall"),
    ("\t\tif not walkable(x, y) then\n\t\t\treturn false", "open floor is not read from the rooms"),
):
    if needle not in ROOMS:
        fail("BackRoomsService: " + why)
catch_at = ROOMS.find("-- CAUGHT.")
if not (catch_at > 0 and 0 < ROOMS.find("local spot = squaredUp(", catch_at) < ROOMS.find('model:SetAttribute("Caught", true)', catch_at)):
    fail("BackRoomsService: he is squared up after every screen is told he has you")
for needle, why in (
    ("if one.grab == 0 then\n\t\t\tone.at = root.CFrame", "his hold is drawn eased after where he is, not where he holds you"),
    ('drive(one, "Hip", CFrame.new(0, -HOLD.hips * g, 0))', "his hips are not in the hold"),
    ('drive(one, "Spine", CFrame.Angles(-HOLD.spine * g, 0, 0))', "his back is not in the hold"),
    ('drive(one, "Hip" .. side, CFrame.Angles(-HOLD.thigh * g, 0, 0))', "his thighs are not in the hold"),
    ('drive(one, "Knee" .. side, CFrame.Angles(HOLD.knee * g, 0, 0))', "his knees are not in the hold"),
    ('drive(one, "Shoulder" .. side, CFrame.Angles(HOLD.shoulder * g, -HOLD.shoulderYaw * sign * g,\n'
     '\t\t\t\t-HOLD.shoulderRoll * sign * g))', "his shoulders are not in the hold"),
    ('drive(one, "Elbow" .. side, CFrame.Angles(HOLD.elbow * g, 0, -HOLD.elbowTwist * sign * g))', "his elbows are not in the hold"),
    ('drive(one, "NeckJ", CFrame.Angles(HOLD.neck * g, 0, 0))', "his neck is not in the hold"),
    ('drive(one, "HeadJ", CFrame.Angles(HOLD.head * g, 0,', "his head is not in the hold"),
):
    if needle not in STALKER:
        fail("StalkerClient: " + why)
for needle, why in (
    ("local spot = Vector3.new(his.Position.X, root.Position.Y, his.Position.Z) + ahead.Unit * grip",
     "you are not set where his hands close"),
    ("root.CFrame = CFrame.lookAt(spot, Vector3.new(his.Position.X, spot.Y, his.Position.Z))", "you are not turned to him"),
    ("Cinema.black(true, 0.06)\n\tlocal camera = workspace.CurrentCamera\n\tlocal eye = camera.CFrame\n"
     "\tlocal character = Players.LocalPlayer.Character\n"
     '\tlocal root = character and character:FindFirstChild("HumanoidRootPart")\n\tholdMe(character)',
     "you are moved into his hands where it can be seen, or never"),
    ("Cinema.point(CFrame.lookAt(Cinema.clear(want, mid, current.ignore), mid), 60 - 4 * k)",
     "the shot of him holding you can be in a wall"),
    ("if math.max(left, right) >= 5 then", "the shot of him holding you is not taken from the side with room"),
):
    if needle not in STORY_CLIENT:
        fail("StoryClient: " + why)

# HIM, REFINED (223 and 224, from "make the backrooms character even better" and "refine him"): round limbs over his
# rig's own blocks, an office man's clothes, five jointed fingers, socked feet, a hump, a suit that reads against the
# walls; and on each screen his fingers flex and his back heaves.
for needle, why in (
    ("local function rounded(model: Model, limb: Part): Part", "his limbs are flat sticks again"),
    ('rigPart(model, "Tie"', "he has lost his collar and tie"),
    ('rigPart(model, "Sole"', "his feet are black blocks again"),
    ('rigPart(model, "Hump"', "his stoop has no hump"),
    ("local suit, skin = Color3.fromRGB(46, 43, 44)", "his suit is black again, a cut-out against the walls"),
):
    if needle not in ROOMS:
        fail("BackRoomsService: " + why)
for needle, why in (
    ("local function flex(one: Seen, curl: number, now: number, restless: number)", "his fingers never move"),
    ("flex(one, 0.75 * g, now, 0.06)", "his fingers do not close on you"),
    ("local breath = math.sin(now * 2.2)", "he does not breathe"),
):
    if needle not in STALKER:
        fail("StalkerClient: " + why)

# BIGGER, AND REFINED AGAIN (pass 225): the hall and the south wing, his badge and buttons, the limp, the hold light,
# your thought cleared at the cut.
if W < 50 or H < 32:
    fail("the back rooms shrank back (pass 225 made them 54 by 36)")
for src, needle, why in (
    (ROOMS, r'badgeWords.Text = "E. MARSH\nSTAFF"', "his staff badge is gone"),
    (ROOMS, 'rigPart(model, "Button"', "his jacket's buttons are gone"),
    (ROOMS, 'rigPart(model, "DampHem"', "his damp trouser hems are gone"),
    (STALKER, "local limp = 0.2 * math.max(0, -s) * math.min(pace, 1.2)", "he no longer limps"),
    (STALKER, 'spot.Name = "HoldLight"', "he is a black shape in the hold again"),
    (STALKER, 'item:IsA("SurfaceGui") then', "his hidden body's badge words float on screen"),
    (STORY_CLIENT, 'gui:FindFirstChild("CinemaThought")', "your thought hangs on into his face"),
):
    if needle not in src:
        fail(why)

# PASS 226: he stops dead when he first sees you, then comes; his tie swings; his neck cracks; the catch's hits are
# dark, never the white flash.
CINEMA_SRC = (SRC / "Client" / "Services" / "Cinema.lua").read_text(encoding="utf-8")
for src, needle, why in (
    (ROOMS, 'model:SetAttribute("Spotted", now)', "he no longer stops dead when he sees you"),
    (STALKER, "tie.weld.C0 = tie.rest * tie.pivot:Inverse() * CFrame.Angles(hang, 0, 0) * tie.pivot", "his tie hangs dead"),
    (STALKER, 'real:GetAttribute("Spotted") ~= nil and not one.spotted', "his head does not snap round to you"),
    (CINEMA_SRC, "effect.Brightness = if dark then -0.18 else 0.12", "an impact cannot be dark"),
    (STORY_CLIENT, "Cinema.impact(1.6, true)", "his head throwing open flashes white again"),
    (STORY_CLIENT, "Cinema.impact(2, true)", "his lunge flashes white again"),
    (STORY_CLIENT, "Cinema.impact(0.6, true)", "the cut to his hold flashes white again"),
):
    if needle not in src:
        fail(why)

# PASS 227: his own mouth. His made head cut at the lips (MarshMouth), the face shot opening his skull and his own jaw
# (not a lid over a second mouth), the walking copy wearing the two pieces with his jaw moving; the lid kept only as
# the fallback.
MOUTH_SRC = (SRC / "Client" / "Services" / "MarshMouth.lua").read_text(encoding="utf-8")     if (SRC / "Client" / "Services" / "MarshMouth.lua").exists() else ""
for src, needle, why in (
    (MOUTH_SRC, "AssetService:CreateEditableMeshAsync(Content.fromUri(template.MeshId))", "his head is not cut from its own mesh"),
    (MOUTH_SRC, "local x = across(a, b, a.d / (a.d - b.d))", "triangles across his lips are not cut where they cross"),
    (MOUTH_SRC, "MarshMouth.HINGE = Vector3.new(0, -0.42 + MarshMouth.SLOPE * 0.95, 0.15)", "his jaw is not hinged under his ears"),
    (STORY_CLIENT, "if template and mouth then", "the face shot does not open his own mouth"),
    (STORY_CLIENT, "if template and not own then", "the lid is no longer only the fallback"),
    (STORY_CLIENT, 'or string.sub(item.Name, 1, 5) == "Mouth") then', "his walking head's pieces stay in the face shot"),
    (STORY_CLIENT, "task.spawn(MarshMouth.prepare)", "his head is never cut"),
    (STALKER, "weld.C0 = mouth.base * h * CFrame.Angles(-math.rad(38) * one.open, 0, 0) * h:Inverse()", "his jaw does not move as he walks"),
    (STALKER, "gape(one, 0.85 * g + 0.06 * math.sin(now * 13), dt)", "his mouth does not open over you in the hold"),
):
    if needle not in src:
        fail(why)

# PASS 228: his eyes. His lids cut from his skull and hinged up into his head, an eye behind each; shut until he has
# seen you, then open; flying open in the face shot.
for src, needle, why in (
    (MOUTH_SRC, "side = lidOf(a, b, c) or 1", "his lids are not cut from his skull"),
    (MOUTH_SRC, 'ball("MouthEye", ', "there is nothing behind his lids"),
    (STALKER, "stare(one, if one.spotted ~= nil then 1 else 0, dt)", "his eyes do not open when he sees you"),
    (STORY_CLIENT, "entry.part.CFrame = tipped * MarshMouth.lidTurn(entry.eyelid, face.scale, face.eyeOpen or 1)", "his eyes do not open in the face shot"),
):
    if needle not in src:
        fail(why)

# PASS 229: the sea's monsters' jaws, cut the same way (MarshMouth.jaw): the serpent's worked as it swims, the
# leviathan's breathing and roaring in the lobby.
SUNK_CLIENT = (SRC / "Client" / "Services" / "SunkenCityClient.lua").read_text(encoding="utf-8")
for src, needle, why in (
    (MOUTH_SRC, "local front, back = split(down, ahead)", "a sea monster's jaw takes its throat with it"),
    (MOUTH_SRC, "function MarshMouth.leviathan()", "the leviathan's jaw never moves"),
    (SUNK_CLIENT, "SerpentJaw.work(eye, nearness)", "the serpent's jaw never moves"),
    (STORY_CLIENT, "task.spawn(MarshMouth.leviathan)", "the leviathan's jaw is never started"),
):
    if needle not in src:
        fail(why)

# HIS RIG, as BackRoomsService builds it (each joint's line, so a rig changed there is a sum to redo here).
RIG = (
    'joint("Hip", root, hips, CFrame.new(0, 5.3, 0), CFrame.identity)',
    'joint("Hip" .. tag, hips, thigh, CFrame.new(side * 0.34, -0.1, 0), CFrame.new(0, 1.3, 0))',
    'joint("Knee" .. tag, thigh, shin, CFrame.new(0, -1.3, 0), CFrame.new(0, 1.25, 0))',
    'rigPart(model, "Foot", Vector3.new(0.42, 0.24, 0.9), suit, Enum.Material.Fabric), CFrame.new(0, -1.3, -0.22))',
    'joint("Spine", hips, torso, CFrame.new(0, 0.2, 0) * CFrame.Angles(math.rad(-16), 0, 0), CFrame.new(0, -1.15, 0))',
    'joint("Shoulder" .. tag, torso, upper, CFrame.new(side * 0.72, 1.05, 0) * CFrame.Angles(math.rad(16), 0, 0),\n'
    '\t\t\tCFrame.new(0, 1.15, 0))',
    'joint("Elbow" .. tag, upper, lower, CFrame.new(0, -1.15, 0), CFrame.new(0, 1.15, 0))',
    "welded(lower, hand, CFrame.new(0, -1.4, -0.02))",
    # (Five two-jointed fingers since pass 223; the middle one reaches as the three pegs did, about 1.2 below the hand.)
    'local long = ({ 0.62, 0.86, 0.95, 0.88, 0.66 })[k]',
    'joint("NeckJ", torso, neck, CFrame.new(0, 1.15, 0) * CFrame.Angles(math.rad(-22), 0, 0), CFrame.new(0, -0.42, 0))',
    'joint("HeadJ", neck, head, CFrame.new(0, 0.45, 0) * CFrame.Angles(math.rad(-18), 0, 0), CFrame.new(0, -0.72, 0))',
    "welded(head, seam, CFrame.new(0, -0.08, -0.56))",
)
for line in RIG:
    if line not in ROOMS:
        fail("BackRoomsService: his rig has changed (%s...), so the sums for his hold here must be redone" % line[:40])
hold = dict((k, float(v)) for k, v in re.findall(r"(\w+) = ([\d.]+)", STALKER[STALKER.find("local HOLD = {"):
                                                                                STALKER.find("}", STALKER.find("local HOLD = {"))]))


def mat(rows):
    return [list(r) for r in rows]


def mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def move(x, y, z):
    return mat(((1, 0, 0, x), (0, 1, 0, y), (0, 0, 1, z), (0, 0, 0, 1)))


def turn(rx, ry, rz):
    # Roblox's CFrame.Angles(rx, ry, rz): X, then Y, then Z, each about the frame before it.
    cx, sx, cy, sy, cz, sz = (math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz))
    x = mat(((1, 0, 0, 0), (0, cx, -sx, 0), (0, sx, cx, 0), (0, 0, 0, 1)))
    y = mat(((cy, 0, sy, 0), (0, 1, 0, 0), (-sy, 0, cy, 0), (0, 0, 0, 1)))
    z = mat(((cz, -sz, 0, 0), (sz, cz, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1)))
    return mul(mul(x, y), z)


def at(m):
    return (m[0][3], m[1][3], m[2][3])


def hung(parent, c0, transform, c1_y):
    # A Motor6D: the child at parent * C0 * Transform * C1:Inverse(), every C1 here a plain offset up the child.
    return mul(mul(mul(parent, c0), transform), move(0, -c1_y, 0))


KEYS = ("hips", "spine", "thigh", "knee", "shoulder", "shoulderYaw", "shoulderRoll", "elbow", "elbowTwist", "neck", "head")
if GRIP <= 0 or any(k not in hold for k in KEYS):
    fail("StalkerClient or BackRoomsService: his hold or GRIP cannot be read, so it cannot be checked")
else:
    rad = math.radians
    hips = hung(move(0, 0, 0), move(0, 5.3, 0), move(0, -hold["hips"], 0), 0)
    torso = hung(hips, mul(move(0, 0.2, 0), turn(rad(-16), 0, 0)), turn(-hold["spine"], 0, 0), -1.15)
    body = {}
    for tag, side, sign in (("L", -1, 1), ("R", 1, -1)):
        upper = hung(torso, mul(move(side * 0.72, 1.05, 0), turn(rad(16), 0, 0)),
                     turn(hold["shoulder"], -hold["shoulderYaw"] * sign, -hold["shoulderRoll"] * sign), 1.15)
        lower = hung(upper, move(0, -1.15, 0), turn(hold["elbow"], 0, -hold["elbowTwist"] * sign), 1.15)
        hand = mul(lower, move(0, -1.4, -0.02))
        body["hand" + tag] = at(hand)
        body["tip" + tag] = at(mul(hand, move(0, -0.72 - 0.475, 0)))
        body["elbow" + tag] = at(mul(upper, move(0, -1.15, 0)))
        thigh = hung(hips, move(side * 0.34, -0.1, 0), turn(-hold["thigh"], 0, 0), 1.3)
        shin = hung(thigh, move(0, -1.3, 0), turn(hold["knee"], 0, 0), 1.25)
        body["foot" + tag] = at(mul(shin, move(0, -1.3, -0.22)))
    neck = hung(torso, mul(move(0, 1.15, 0), turn(rad(-22), 0, 0)), turn(hold["neck"], 0, 0), -0.42)
    head = hung(neck, mul(move(0, 0.45, 0), turn(rad(-18), 0, 0)), turn(hold["head"], 0, 0.45), -0.72)  # (tipped, as drawn)
    body["head"] = at(head)
    body["face"] = at(mul(head, move(0, -0.08, -0.56)))
    body["torso"] = at(torso)
    body["torsoTop"] = at(mul(torso, move(0, 1.15, 0)))

    # YOU, GRIP studs in front of him and facing him: a body two studs across, a stud deep, from the carpet to 5.2 (the
    # chest from 2.95 to 4.55 on R15, 2 to 4 on R6), your head's middle at 4.6.
    def outside(p, margin):
        gaps = (abs(p[0]) - 1.0, max(-p[1], p[1] - 5.2), abs(p[2] + GRIP) - 0.5)
        return max(gaps) >= margin

    for tag in ("L", "R"):
        hx, hy, hz = body["hand" + tag]
        if not (1.0 <= abs(hx) <= 1.45 and 3.1 <= hy <= 4.0 and -GRIP - 0.5 <= hz <= -GRIP + 0.3):
            fail("StalkerClient: his %s hand closes at (%.2f, %.2f, %.2f), not at your side at chest height "
                 "(%.1f in front of him)" % ("left" if tag == "L" else "right", hx, hy, hz, GRIP))
        tx, ty, tz = body["tip" + tag]
        if not (tz < -GRIP - 0.5 and abs(tx) < 1.05 and 2.9 <= ty <= 4.3):
            fail("StalkerClient: his %s fingers end at (%.2f, %.2f, %.2f), not round behind your back"
                 % ("left" if tag == "L" else "right", tx, ty, tz))
        if abs(body["foot" + tag][1] - 0.12) > 0.08:
            fail("StalkerClient: holding you, his %s foot is %.2f off the carpet" % (tag, body["foot" + tag][1] - 0.12))
        if abs(body["elbow" + tag][0]) > 1.8:
            fail("StalkerClient: holding you, his elbows stand %.2f out, through a four-stud corridor's walls"
                 % abs(body["elbow" + tag][0]))
        if not outside(body["elbow" + tag], 0.15):
            fail("StalkerClient: holding you, his elbow is inside you")
    for part in ("torso", "torsoTop", "head"):
        if not outside(body[part], 0.3):
            fail("StalkerClient: holding you, his %s is inside you" % part)
    fx, fy, fz = body["face"]
    if not (fy > 5.0 and math.dist(body["face"], (0, 4.6, -GRIP)) < 1.8 and fz > -GRIP):
        fail("StalkerClient: holding you, his face is at (%.2f, %.2f, %.2f), not over yours" % (fx, fy, fz))

# THE HEAD THAT OPENS IS THE HEAD HE WEARS (pass 221): where Assets/Props.Marsh_Head is worn (BackRoomsService), the
# screamer opens that model and hides the one he wears, not the old two halves in front of it.
STORY = (SRC / "Client" / "Services" / "StoryClient.lua").read_text(encoding="utf-8")
if '"Marsh_Head"' in ROOMS:
    for needle, why in (
        ('FindFirstChild("Marsh_Head")', "the screamer does not look for the made head"),
        ('head.Name = "Lid"', "the screamer does not open the made head (its lid)"),
        ('item.Name == "MadeHead"', "the made head he wears is not hidden while his face opens"),
        ("if template then {} else { -1, 1 }", "the old halves are still built where the made head is"),
        ("if lid and jaw and hinge then", "placeScreamer does not tip the made head open"),
    ):
        if needle not in STORY:
            fail("StoryClient: " + why)

if problems:
    print("PROBLEMS:")
    for line in dict.fromkeys(problems):
        print("  " + line)
    sys.exit(1)
print("back rooms: %d by %d tiles, closed all round, every floor tile walkable, the way out %d tiles from where you "
      "arrive, %d tubes and no tile more than %d from one, real light only, nothing floating, found after %d falls in a "
      "run and left as the fall would have; caught, held in his hands %.1f studs off." % (W, H, walk, len(lights), worst,
                                                                                   falls or 0, GRIP))
