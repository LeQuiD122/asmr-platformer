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
"""
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
    ('drive(one, "Hip" .. side, CFrame.Angles(leg * swing, 0, 0))', "his legs do not walk"),
    ('drive(one, "Shoulder" .. side, CFrame.Angles(1.4 + 0.12 * late, 0, -0.15 * sign))', "rushing, he does not reach for you"),
    ("if to.Magnitude < LOOK_NEAR and camera.CFrame.LookVector:Dot(-to.Unit) > 0.55 then", "his head never turns to look at you"),
    ("thud(one.at.Position, math.clamp(pace, 0.4, 1.2))", "his feet come down without a sound"),
    ("one.tilt += ((if paused then 0.7 else 0) - one.tilt)", "stopping, his head does not tip over"),
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
    ("eye = CFrame.lookAt(his - toward * 5.6 + across * 1.7 + Vector3.new(0, 0.5, 0), his)", "his face is not seen whole"),
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

if problems:
    print("PROBLEMS:")
    for line in dict.fromkeys(problems):
        print("  " + line)
    sys.exit(1)
print("back rooms: %d by %d tiles, closed all round, every floor tile walkable, the way out %d tiles from where you "
      "arrive, %d tubes and no tile more than %d from one, real light only, nothing floating, found after %d falls in a "
      "run and left as the fall would have." % (W, H, walk, len(lights), worst, falls or 0))
