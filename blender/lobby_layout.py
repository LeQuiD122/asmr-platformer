"""The lobby's layout, read out of src/Shared/LobbyLayout.lua (the hundredth pass): what plan_lobby.py draws and
check_hub.py checks. Read from the Luau, never copied, so the two cannot disagree; the functions of it (arc, walk)
restated line for line, and every thing's footprint on the deck as HubService builds it (footprints)."""
import math
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
LAYOUT = ROOT / "src" / "Shared" / "LobbyLayout.lua"
HUB = ROOT / "src" / "Server" / "Services" / "HubService.lua"
LEVELS = ROOT / "src" / "Shared" / "LevelDefinitions.lua"


def _block(text, name):
    start = text.find("LobbyLayout.%s = {" % name)
    if start < 0:
        return ""
    depth, i = 0, text.index("{", start)
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
    return ""


def _num(value):
    value = value.strip()
    if value == "math.pi":
        return math.pi
    if value == "-math.pi":
        return -math.pi
    m = re.match(r"^(-?)math\.pi\s*/\s*([\d.]+)$", value)
    if m:
        return (-1 if m.group(1) else 1) * math.pi / float(m.group(2))
    return float(value)


def read():
    text = LAYOUT.read_text(encoding="utf-8")
    layout = {"text": text}
    origin = re.search(r"LobbyLayout\.ORIGIN = Vector3\.new\((-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\)", text)
    layout["origin"] = tuple(float(v) for v in origin.groups()) if origin else None
    layout["margin"] = float(re.search(r"LobbyLayout\.MARGIN = ([\d.]+)", text).group(1))
    layout["sea_drop"] = float(re.search(r"LobbyLayout\.SEA_DROP = ([\d.]+)", text).group(1))
    decks = {}
    for name, x, z, w, d in re.findall(r"(\w+) = \{ x = (-?[\d.]+), z = (-?[\d.]+), w = ([\d.]+), d = ([\d.]+) \}",
                                       _block(text, "DECKS")):
        decks[name] = dict(x=float(x), z=float(z), w=float(w), d=float(d))
    layout["decks"] = decks
    layout["walks"] = [dict(to=to, width=float(width))
                       for to, width in re.findall(r'\{ to = "(\w+)", width = ([\d.]+) \}', _block(text, "WALKS"))]
    at = {}
    for name, x, y, z in re.findall(r"(\w+) = Vector3\.new\((-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\)", _block(text, "AT")):
        at[name] = (float(x), float(y), float(z))
    layout["at"] = at
    arc = _block(text, "ARC")
    layout["arc"] = dict(radius=float(re.search(r"radius = ([\d.]+)", arc).group(1)),
                         spread=float(re.search(r"spread = ([\d.]+)", arc).group(1)))
    layout["benches"] = [dict(x=float(x), z=float(z), facing=_num(f))
                         for x, z, f in re.findall(r"\{ x = (-?[\d.]+), z = (-?[\d.]+), facing = ([^}]+?) \}",
                                                   _block(text, "BENCHES"))]
    layout["planters"] = [(float(x), float(z)) for x, z in
                          re.findall(r"\{ x = (-?[\d.]+), z = (-?[\d.]+) \}", _block(text, "PLANTERS"))]
    layout["lamps"] = [(float(x), float(z)) for x, z in
                       re.findall(r"\{ x = (-?[\d.]+), z = (-?[\d.]+) \}", _block(text, "LAMPS"))]
    return layout


def arc(layout, count):
    """LobbyLayout.arc: the level pads' places, round the start."""
    sx, _, sz = layout["at"]["start"]
    half = math.radians(layout["arc"]["spread"]) / 2
    out = []
    for index in range(count):
        t = index / (count - 1) if count > 1 else 0.5
        angle = -half + 2 * half * t
        out.append((sx + math.sin(angle) * layout["arc"]["radius"], sz - math.cos(angle) * layout["arc"]["radius"]))
    return out


def walk(layout, to):
    """LobbyLayout.walk: (centre x, centre z, length, width, along x)."""
    plaza, deck = layout["decks"]["plaza"], layout["decks"][to]
    width = next((w["width"] for w in layout["walks"] if w["to"] == to), 20)
    if deck["x"] != plaza["x"]:
        sign = 1 if deck["x"] > plaza["x"] else -1
        a = plaza["x"] + sign * plaza["w"] / 2
        b = deck["x"] - sign * deck["w"] / 2
        return (a + b) / 2, deck["z"], abs(b - a), width, True
    sign = 1 if deck["z"] > plaza["z"] else -1
    a = plaza["z"] + sign * plaza["d"] / 2
    b = deck["z"] - sign * deck["d"] / 2
    return deck["x"], (a + b) / 2, abs(b - a), width, False


def walk_rect(layout, to):
    """The walk as an axis-aligned box: (min x, max x, min z, max z)."""
    x, z, length, width, along_x = walk(layout, to)
    hx, hz = (length / 2, width / 2) if along_x else (width / 2, length / 2)
    return x - hx, x + hx, z - hz, z + hz


def deck_of(layout, x, z):
    """Which deck (x, z) stands on, inside its inlay; None if on none."""
    m = layout["margin"]
    for name, d in layout["decks"].items():
        if abs(x - d["x"]) <= d["w"] / 2 - m and abs(z - d["z"]) <= d["d"] / 2 - m:
            return name
    return None


def over(layout, x, z, slack):
    """LobbyLayout.over: over a deck or a walk, give or take `slack`."""
    for d in layout["decks"].values():
        if abs(x - d["x"]) <= d["w"] / 2 + slack and abs(z - d["z"]) <= d["d"] / 2 + slack:
            return True
    for w in layout["walks"]:
        x0, x1, z0, z1 = walk_rect(layout, w["to"])
        if x0 - slack <= x <= x1 + slack and z0 - slack <= z <= z1 + slack:
            return True
    return False


# ===================================================================== footprints
#
# Every thing on the decks as the shape it takes up on the floor, in HubService's own sizes. A shape is a dict:
#   kind    "circle" (x, z, r) or "rect" (x, z, w, d, yaw: Roblox's turn about Y, local (x, z) going to
#           (x cos + z sin, -x sin + z cos) in the world)
#   name    what it is; group: the same object's pieces share one
#   role    "thing" (stands inside an inlay, clear of every other), "step" (a key you walk onto: may sit on the
#           way to the start), "column" (the plaza's, on the trim band, outside the inlay by design), "walk" (on a
#           walk, not a deck), "clear" (a place that must stay empty: the spawn)

def _yaw_toward(x, z, tx, tz):
    """The yaw of CFrame.lookAt((x, z), (tx, tz)): local -Z toward the target."""
    dx, dz = tx - x, tz - z
    return math.atan2(-dx, -dz)


def _corners(shape):
    c, s = math.cos(shape["yaw"]), math.sin(shape["yaw"])
    out = []
    for lx, lz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        lx, lz = lx * shape["w"] / 2, lz * shape["d"] / 2
        out.append((shape["x"] + lx * c + lz * s, shape["z"] - lx * s + lz * c))
    return out


def extent(shape):
    """The shape's box on the floor: (min x, max x, min z, max z)."""
    if shape["kind"] == "circle":
        return shape["x"] - shape["r"], shape["x"] + shape["r"], shape["z"] - shape["r"], shape["z"] + shape["r"]
    pts = _corners(shape)
    return min(p[0] for p in pts), max(p[0] for p in pts), min(p[1] for p in pts), max(p[1] for p in pts)


def _axes(shape):
    c, s = math.cos(shape["yaw"]), math.sin(shape["yaw"])
    return [(c, -s), (s, c)]


def _project(shape, axis):
    if shape["kind"] == "circle":
        centre = shape["x"] * axis[0] + shape["z"] * axis[1]
        return centre - shape["r"], centre + shape["r"]
    values = [p[0] * axis[0] + p[1] * axis[1] for p in _corners(shape)]
    return min(values), max(values)


def gap(a, b):
    """The clearance between two shapes (negative when they overlap): the largest separation along any axis that
    can separate them (each rectangle's two sides, and for a circle the line to the other's nearest corner)."""
    if a["kind"] == "circle" and b["kind"] == "circle":
        return math.hypot(a["x"] - b["x"], a["z"] - b["z"]) - a["r"] - b["r"]
    axes = []
    for shape in (a, b):
        if shape["kind"] == "rect":
            axes += _axes(shape)
    for circle, rect in ((a, b), (b, a)):
        if circle["kind"] == "circle" and rect["kind"] == "rect":
            near = min(_corners(rect), key=lambda p: math.hypot(p[0] - circle["x"], p[1] - circle["z"]))
            dx, dz = near[0] - circle["x"], near[1] - circle["z"]
            length = math.hypot(dx, dz)
            if length > 1e-9:
                axes.append((dx / length, dz / length))
    best = -math.inf
    for axis in axes:
        a0, a1 = _project(a, axis)
        b0, b1 = _project(b, axis)
        best = max(best, b0 - a1, a0 - b1)
    return best


def inside_inlay(layout, shape):
    """The deck whose inlay the shape lies wholly inside, or None."""
    x0, x1, z0, z1 = extent(shape)
    m = layout["margin"]
    for name, d in layout["decks"].items():
        if x0 >= d["x"] - d["w"] / 2 + m and x1 <= d["x"] + d["w"] / 2 - m \
                and z0 >= d["z"] - d["d"] / 2 + m and z1 <= d["z"] + d["d"] / 2 - m:
            return name
    return None


def on_walk(layout, shape):
    """The walk the shape lies wholly on, or None."""
    x0, x1, z0, z1 = extent(shape)
    for w in layout["walks"]:
        a0, a1, b0, b1 = walk_rect(layout, w["to"])
        if x0 >= a0 and x1 <= a1 and z0 >= b0 and z1 <= b1:
            return w["to"]
    return None


def pad_count(hub_text=None):
    """padLevels: every level, the story's pad and the sandbox."""
    hub_text = hub_text if hub_text is not None else HUB.read_text(encoding="utf-8")
    count = len(re.findall(r"levelId = \d+", LEVELS.read_text(encoding="utf-8")))
    count += len(re.findall(r"^\tstory = true,$", hub_text, re.M))
    return count


def _size(pattern, text, index, fallback):
    m = re.search(pattern, text)
    return float(m.group(index)) if m else fallback


def footprints(layout, hub_text=None, pads=None):
    hub_text = hub_text if hub_text is not None else HUB.read_text(encoding="utf-8")
    pads = pads if pads is not None else pad_count(hub_text)
    at = layout["at"]
    out = []

    def circle(name, x, z, r, role="thing", group=None):
        out.append(dict(kind="circle", name=name, x=x, z=z, r=r, role=role, group=group or name))

    def rect(name, x, z, w, d, yaw=0.0, role="thing", group=None):
        out.append(dict(kind="rect", name=name, x=x, z=z, w=w, d=d, yaw=yaw, role=role, group=group or name))

    # THE LEVEL PADS, with the window and its frame standing on each one's back edge.
    pad = _size(r"local PAD_SIZE = Vector3\.new\(([\d.]+),", hub_text, 1, 10.0)
    sx, _, sz = at["start"]
    for i, (x, z) in enumerate(arc(layout, pads)):
        rect("level pad %d" % (i + 1), x, z, pad + 0.2, pad + 0.6, _yaw_toward(x, z, sx, sz))
    rect("start pad", sx, sz, 14, 8)
    housing = _size(r"housing\.Size = Vector3\.new\([\d.]+, ([\d.]+),", hub_text, 1, 7.6)
    for row, count in (("modeRow", 2), ("lengthRow", 3)):
        rx, _, rz = at[row]
        for i in range(count):
            circle("%s key %d" % (row[:-3], i + 1), rx + (i - (count - 1) / 2) * 12, rz, housing / 2, "step")
    # The key you step on (its socket round it is a rim on the floor, and the sockets nearly touch by design).
    key = _size(r"key\.Size = Vector3\.new\([\d.]+, ([\d.]+),", hub_text, 1, 4.2)
    poses = re.search(r"local POSE_ORDER = (\{[^}]*\})", hub_text)
    count = len(re.findall(r'"\w+"', poses.group(1))) if poses else 5
    px, _, pz = at["poseRow"]
    for i in range(count):
        circle("pose key %d" % (i + 1), px + (i - (count - 1) / 2) * 6, pz, key / 2, "step")
    x, _, z = at["statue"]
    rect("statue plinth", x, z, 6, 6)
    x, _, z = at["board"]
    rect("leaderboard", x - 0.3, z, 1.4, 22.7)
    circle("board lever", x - 3.2, z + 8, 2.2, group="leaderboard")  # at the board's near corner, by design
    x, _, z = at["kiosk"]
    rect("shop kiosk", x + 0.7, z, 5.7, 7.92)
    arcade = layout["decks"]["arcade"]
    x, _, z = at["chest"]
    rect("daily chest", x, z, 3.2, 2.1, _yaw_toward(x, z, arcade["x"], arcade["z"]))
    roof = _size(r'plank\("Roof", Vector3\.new\(([\d.]+),', hub_text, 1, 8.4)
    for name in ("challenges", "materials"):
        x, _, z = at[name]
        rect("%s board" % name, x, z, roof, 1.4, _yaw_toward(x, z, arcade["x"], arcade["z"]))
    x, _, z = at["postBox"]
    circle("post box", x, z, 1.2)
    # THE BACK HOUSE: its roof from x -3.4 to 11.7 and z -1.9 to 13.9 in the doorway's own frame, the doorway
    # facing +X (turned a quarter the other way, so the house runs back west).
    x, _, z = at["backDoor"]
    yaw = -math.pi / 2
    lx, lz = 4.15, 6.0
    c, s = math.cos(yaw), math.sin(yaw)
    rect("back house", x + lx * c + lz * s, z - lx * s + lz * c, 15.1, 15.8, yaw)
    for b in layout["benches"]:
        rect("bench", b["x"], b["z"], 9, 2.6, b["facing"], group="bench %g %g" % (b["x"], b["z"]))
    for x, z in layout["planters"]:
        circle("planter", x, z, 3.8, group="planter %g %g" % (x, z))
    x, _, z = at["pool"]
    rect("pool", x, z, 26, 13)
    x, _, z = at["viewer"]
    circle("viewer", x, z, 1.3)
    x, _, z = at["lift"]
    rect("squish lift", x, z, 7.6, 7.6)
    for x, z in layout["lamps"]:
        role = "thing" if deck_of(layout, x, z) else "walk"
        circle("lamp post", x, z, 0.8, role, group="lamp %g %g" % (x, z))
    # THE PLAZA'S COLUMNS, on its trim band (2.5 in from the edge): the corners and the quarter points, so each
    # walk's way in is framed by two.
    plaza = layout["decks"]["plaza"]
    hx, hz = plaza["w"] / 2 - 2.5, plaza["d"] / 2 - 2.5
    for x, z in ((-hx, -hz), (hx, -hz), (-hx, hz), (hx, hz),
                 (-hx / 2, -hz), (hx / 2, -hz), (-hx / 2, hz), (hx / 2, hz),
                 (-hx, -hz / 2), (-hx, hz / 2), (hx, -hz / 2), (hx, hz / 2)):
        circle("column", plaza["x"] + x, plaza["z"] + z, 2.3, "column", group="column %g %g" % (x, z))
    x, _, z = at["spawn"]
    rect("spawn", x, z, 10, 10, role="clear")
    return out


def lanes(layout):
    """The ways that must stay clear: every walk's way onto each of its two decks (12 studs deep, as wide as the
    walk), and the line from the spawn to the start (6 studs wide)."""
    out = []
    depth = 12
    for w in layout["walks"]:
        x0, x1, z0, z1 = walk_rect(layout, w["to"])
        x, z, length, width, along_x = walk(layout, w["to"])
        if along_x:
            out.append(("onto the %s walk" % w["to"], (x0 - depth, x0, z0, z1)))
            out.append(("onto the %s walk" % w["to"], (x1, x1 + depth, z0, z1)))
        else:
            out.append(("onto the %s walk" % w["to"], (x0, x1, z0 - depth, z0)))
            out.append(("onto the %s walk" % w["to"], (x0, x1, z1, z1 + depth)))
    sx, _, sz = layout["at"]["spawn"]
    tx, _, tz = layout["at"]["start"]
    out.append(("the way from the spawn to the start", (sx - 3, sx + 3, min(sz, tz) + 5, max(sz, tz) - 5)))
    return out


def in_lane(shape, box):
    """How far the shape reaches into an axis-aligned box (negative when clear)."""
    x0, x1, z0, z1 = box
    lane = dict(kind="rect", x=(x0 + x1) / 2, z=(z0 + z1) / 2, w=x1 - x0, d=z1 - z0, yaw=0.0)
    return -gap(shape, lane)
