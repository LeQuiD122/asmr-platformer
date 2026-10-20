"""The squish room, checked without Studio.

    python blender/check_squishroom.py

What it holds:
  * EVERY MATERIAL, REAL: a slab of each material in MaterialConfig (looked up, not listed), cloned from
    the chunk templates and registered with DeformationService, its walking surface flush with the floor.
  * NOTHING IS A FALL: a pit under every slab, with a floor to land on and walls, never deeper than a
    jump; the hall closed in by four walls and a ceiling.
  * NEVER SEEN FROM ELSEWHERE: the room stands beyond every level's horizon and the lobby's.
  * EVERYTHING STANDS ON SOMETHING: signs on legs, lamps on the ceiling with real lights (no Neon), lifts
    on plinths; the lobby's lift in clear floor, and put away with the lobby during a run.
  * IT KEEPS YOU: anyone in it is left out of the lobby's vote; the way back is refused, with a word, while
    the lobby is away; a respawn keeps you in it.
  * THE KEEPSAKE SHELF: a cubby for every keepsake, against the front wall and clear of the lift and the side
    wall, under the ceiling, standing on the floor with every toy set down on a board; each player's own
    collection on it (JournalService), counted on its board, and its prompt opening the journal.
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


ROOM = read("Server", "Services", "SquishRoomService.lua")
CLIENT = read("Client", "Services", "SquishRoomClient.lua")
HUB = read("Server", "Services", "HubService.lua")
BOOT = read("Server", "Bootstrap.server.lua")
CLIENT_BOOT = read("Client", "Bootstrap.client.lua")

if not ROOM:
    fail("SquishRoomService.lua is missing")
if not CLIENT:
    fail("SquishRoomClient.lua is missing")


def vector(name):
    match = re.search(r"local %s = Vector3\.new\((-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\)" % name, ROOM)
    return tuple(float(v) for v in match.groups()) if match else None


def number(name):
    match = re.search(r"local %s = (-?[\d.]+)" % name, ROOM)
    return float(match.group(1)) if match else None


# ===================================================================== far away
origin = vector("ROOM_ORIGIN")
# The lobby's origin is LobbyLayout's (the hundredth pass), and HubService takes it from there.
LAYOUT = read("Shared", "LobbyLayout.lua")
hub = re.search(r"LobbyLayout\.ORIGIN = Vector3\.new\((-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\)", LAYOUT) \
    if "local HUB_ORIGIN = LobbyLayout.ORIGIN" in HUB else None
if not hub:
    fail("cannot read where the lobby is (LobbyLayout.ORIGIN, taken by HubService)")
if not origin:
    fail("ROOM_ORIGIN is missing")
else:
    if math.hypot(origin[0], origin[2]) < 7000:
        fail("the room is within 7000 studs of the levels' centre, inside a horizon (backdrops reach 6200)")
    if hub and math.hypot(origin[0] - float(hub.group(1)), origin[2] - float(hub.group(3))) < 7000:
        fail("the room is near enough the lobby to be seen from it")
    if not (0 < origin[1] < 2000):
        fail("the room is below the height where characters are destroyed, or absurdly high")

# ===================================================================== every material, real
for needle, why in (
    ("for name in pairs(Materials) do", "the room does not look up every material in MaterialConfig"),
    ('ServerStorage:WaitForChild("ChunkTemplates", 60)', "the room does not wait for ChunkBuilder's templates"),
    ("local slab = source:Clone()", "the slabs are not the real ones cloned from the templates"),
    ("DeformationService.registerPlatform(piece)", "the slabs are not registered, so they are only pictures"),
    ("pad.model:PivotTo(CFrame.new(Vector3.new(cx, y, cz) - pad.centreOffset) * rotation)",
     "a slab's walking surface is not set flush with the floor"),
    ('child.Name:match("^SubRegion_")', "a slab's walking surface is not found from its cells"),
):
    if needle not in ROOM:
        fail("SquishRoomService: " + why)

# ===================================================================== nothing is a fall
pit_max = number("PIT_MAX")
if pit_max is None or pit_max > 6.8:
    fail("PIT_MAX lets a pit be deeper than a jump (7.2 studs) gets you out of")
for needle, why in (
    ('"PitFloor"', "a slab has no pit floor under it: what gives way is a fall into nothing"),
    ('"PitWall"', "the pits have no walls"),
    ("depth = math.clamp(top - bottom + 1, 3, PIT_MAX)", "the pit's depth is not held to a jump"),
    ('part(folder, "Ceiling"', "the hall has no ceiling"),
):
    if needle not in ROOM:
        fail("SquishRoomService: " + why)
if ROOM.count('part(folder, "Wall"') != 1 or ROOM.count("Vector3.new(cx, y + WALL_HEIGHT / 2, zA - 1)") != 1 \
        or "Vector3.new(xB + 1, y + WALL_HEIGHT / 2, cz)" not in ROOM:
    fail("the hall is not closed in by four walls")

# ===================================================================== everything stands on something
if "Enum.Material.Neon" in ROOM:
    fail("SquishRoomService lights something with Neon: lamps are real lights")
for needle, why in (
    ('"SignLeg"', "the signs have nothing to stand on"),
    ('"CeilingLamp"', "the hall has no lamps"),
    ('Instance.new("PointLight")', "the lamps give no light"),
    ('"LiftPlinth"', "the lifts stand on nothing"),
    ('"LiftRoof"', "the lifts have no roof"),
    ("local prompt = buildLift(hub, liftBase,", "the lobby's lift is not part of the lobby, so it would hang in the air during a run"),
):
    if needle not in ROOM:
        fail("SquishRoomService: " + why)
# THE LOBBY'S LIFT, where the lobby's layout puts it (in the garden), its door toward the garden's middle (+X) and
# letting you out in front of it; that it stands clear of everything else in the lobby is check_hub's to measure.
for needle, why in (
    ('local LobbyLayout = require(Shared:WaitForChild("LobbyLayout"))\nlocal LOBBY_LIFT_AT = LobbyLayout.AT.lift',
     "the lobby's lift is not where the lobby's layout puts it"),
    ("local liftBase = CFrame.lookAt(base, base + Vector3.new(1, 0, 0))", "the lobby's lift does not face the garden"),
    ("room.lobbyArrive = base + Vector3.new(7, 3.5, 0)", "the lobby's lift lets you out behind its own door"),
):
    if needle not in ROOM:
        fail("SquishRoomService: " + why)
lift = re.search(r"\tlift = Vector3\.new\((-?[\d.]+), ([\d.]+), (-?[\d.]+)\)", LAYOUT)
if not lift or float(lift.group(2)) != 1:
    fail("LobbyLayout: the lobby's lift does not stand on the deck")
if ROOM.count('prompt.Name = "SquishLiftPrompt"') != 1 or ROOM.count("buildLift(") < 3:
    fail("the lifts are not both built with the same prompt")

# ===================================================================== it keeps you
for needle, text, why in (
    ('if not inRun[player] and not player:GetAttribute("InSquishRoom") and ', HUB,
     "the lobby's vote can pull someone out of the squish room into a run"),
    ("function HubService.origin(): Vector3", HUB, "the lobby does not say where it is"),
    ('player:SetAttribute("InSquishRoom", true)', ROOM, "entering the room does not take you out of the lobby's vote"),
    ('player:SetAttribute("InSquishRoom", nil)', ROOM, "leaving the room does not put you back in the lobby's vote"),
    ('if not back or not workspace:FindFirstChild("Hub") then', ROOM, "the way back can drop you where the lobby was during a run"),
    ('tell(player, "closed")', ROOM, "you are not told why the way back is shut"),
    ('if not player:GetAttribute("InSquishRoom") then', ROOM, "a respawn in the room puts you somewhere else"),
    ('ensureRemoteEvent(remoteEventsFolder, "SquishRoom")', BOOT, "Bootstrap never makes the SquishRoom remote"),
    ("(require(squishModule) :: any).build(HubService.origin())", BOOT, "the room is never built"),
    ("local ok, err = pcall(function()\n\t\t\t\t(require(squishModule)", BOOT, "a broken room could stop the whole server Bootstrap"),
    ('if kind == "closed" then', CLIENT, "the client never says why the way back is shut"),
    ('if kind == "going" then\n\t\t\t\tcover()', CLIENT, "the lift has no fade"),
    ('elseif kind == "arrived" then\n\t\t\t\tuncover()', CLIENT, "the fade never lifts when you arrive"),
    ("if ui.coveredAt == stamp then\n\t\t\tuncover()", CLIENT, "a lost word could leave the screen covered for good"),
    ("player:RequestStreamAroundAsync(to, 6)", ROOM, "you are moved before the place is streamed in, and can fall through it"),
    ('tell(player, "arrived")', ROOM, "the client is never told you have arrived"),
    ('tell(player, "building")', ROOM, "the lift fades and goes nowhere while the room is still being built"),
):
    if needle not in text:
        fail(why)
start_list = re.search(r'for _, name in ipairs\(\{(.*?)\}\) do', CLIENT_BOOT, re.S)
if not start_list or '"SquishRoomClient"' not in start_list.group(1):
    fail("the client Bootstrap never starts SquishRoomClient")
for text in re.findall(r'say\("([^"]*)"\)', CLIENT):
    if "--" in text or "—" in text or "–" in text:
        fail("the room's word has a dash in it")

# NOT FROM A RUN: the run would wait for someone who had gone to the squish room (the test panel could).
enter = ROOM[ROOM.find("function SquishRoomService.enter("):]
enter = enter[:enter.find("\nend\n")]
if 'if player:GetAttribute("InLevel") then\n\t\ttell(player, "running")' not in enter:
    fail("SquishRoomService: a runner can go into the squish room from the middle of a run")
if 'elseif kind == "running" then\n\t\t\t\tsay(' not in CLIENT:
    fail("SquishRoomClient: says nothing when the squish room refuses a runner")

# ===================================================================== the keepsake shelf
KEEPSAKES = read("Shared", "Keepsakes.lua")
JOURNAL = read("Client", "Services", "JournalService.lua")
INTERACT = read("Server", "Services", "Interactables.lua")
grid = re.search(r"local SHELF_COLUMNS, SHELF_ROWS = (\d+), (\d+)", ROOM)
cubby = vector("CUBBY")
board, plinth, left = number("SHELF_BOARD"), number("SHELF_PLINTH"), number("SHELF_LEFT")
row_width, margin, wall_height = number("ROW_WIDTH"), number("MARGIN"), number("WALL_HEIGHT")
lift = re.search(r'part\(cabin, "LiftPlinth", Vector3\.new\(([\d.]+), [\d.]+, ([\d.]+)\), at\(0, [\d.]+, 0\)', ROOM)
lift_at = re.search(r"CFrame\.lookAt\(Vector3\.new\(cx, y, zA \+ ([\d.]+)\), Vector3\.new\(cx, y, zA \+ [\d.]+\)\)", ROOM)
keepsakes = len(re.findall(r"^\t\w+ = \{", KEEPSAKES[KEEPSAKES.find("local Keepsakes"):], re.M))
if not (grid and cubby and board and plinth and left and row_width and margin and wall_height and lift and lift_at):
    fail("the keepsake shelf's numbers (or the lift's, or the hall's) are not where this reads them")
else:
    columns, rows = int(grid.group(1)), int(grid.group(2))
    width = columns * cubby[0] + (columns + 1) * board
    height = rows * cubby[1] + (rows + 1) * board
    depth = cubby[2] + board
    if columns * rows < keepsakes:
        fail("the shelf has %d cubbies for %d keepsakes" % (columns * rows, keepsakes))
    half_hall = row_width / 2 + margin
    lift_half = float(lift.group(1)) / 2
    shelf_right = -left + width / 2
    shelf_left = -left - width / 2
    if shelf_right > -lift_half - 3:
        fail("the shelf runs into the lift home, or within 3 studs of it (its edge %.1f studs from the hall's "
             "middle, the lift's at %.1f)" % (shelf_right, -lift_half))
    if shelf_left < -half_hall + 2:
        fail("the shelf runs into the side wall")
    if plinth + height + 1.8 > wall_height - 2:
        fail("the shelf and its board do not fit under the ceiling")
    lift_front = float(lift_at.group(1)) - float(lift.group(2)) / 2
    if depth + 0.3 > lift_front and shelf_right > -lift_half:
        fail("the shelf stands where the lift does")
for needle, why in (
    ("pcall(buildShelf, folder, cx - SHELF_LEFT, zA + 0.3, y)", "the shelf is not built against the front wall, "
     "in front of its skirting"),
    ('CFrame.new(middleX, y + SHELF_PLINTH / 2, zMid)', "the shelf's plinth is not on the floor"),
    ("toy.WorldPivot = box", "a toy is scaled about its pivot, which may be anywhere"),
    ("floorY + size.Y / 2 - box.Position.Y", "a toy is not set down on its board"),
    ("CFrame.new(x, floorY + 0.7, wallZ + SHELF_BOARD + 0.14) * CFrame.Angles(-0.12, 0, 0)",
     "a card is not standing on its board, leaning on the back"),
    ('CollectionService:AddTag(toy, "ShelfToy")', "the toys are not tagged for each player's own collection"),
    ('CollectionService:AddTag(card, "ShelfEmpty")', "the cards are not tagged for each player's own collection"),
    ('CollectionService:AddTag(sign, "ShelfCount")', "the board on top is not tagged for each player's count"),
    ('toy:SetAttribute("JournalId", id)', "a toy does not say which keepsake it is"),
    ('prompt.Name = "KeepsakeShelfPrompt"', "the shelf has no prompt"),
):
    if needle not in ROOM:
        fail("SquishRoomService: " + why)
if "function Interactables.toy(" not in INTERACT or "function Interactables.keepsakeList(" not in INTERACT:
    fail("Interactables cannot make a toy on its own or list the keepsakes")
if "local model, first = Interactables.toy(parent, cf, material)" not in INTERACT:
    fail("Interactables.keepsake no longer makes its toy the way the shelf does")
for needle, why in (
    ('if CollectionService:HasTag(item, "ShelfToy") then have else not have', "the shelf does not show your own "
     "collection (toys found, cards for the rest)"),
    ('label.Text = ("KEEPSAKES  %d of %d"):format(counts.keepsake or 0, keepsakeTotal)', "the shelf's board does not "
     "count your keepsakes"),
    ("if kind == \"keepsake\" then\n\t\trefreshShelf()", "a keepsake picked up does not appear on the shelf"),
    ("refreshShelf()\n\t\t\treturn", "the journal read back does not fill the shelf"),
    ('CollectionService:GetInstanceAddedSignal("ShelfToy"):Connect(shelfItem)', "the shelf is not shown as yours "
     "when it streams in"),
    ('if prompt.Name == "KeepsakeShelfPrompt" and who == Players.LocalPlayer then\n\t\t\tJournalService.open("keepsake")',
     "the shelf's prompt does not open the journal at the keepsakes"),
):
    if needle not in JOURNAL:
        fail("JournalService: " + why)

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("squish room: every material real and registered, flush with the floor over a pit no deeper than a jump, "
      "a keepsake shelf with a cubby for each, "
      "closed in, beyond every horizon, standing on something throughout, its lobby lift in clear floor and put "
      "away with the lobby, and keeping you out of the lobby's vote until you take the lift back.")
