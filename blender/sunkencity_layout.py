"""The Sunken City (Level 3) laid out in Python, the way LevelService and SunkenCityService lay it.

Shared by check_sunkencity.py and plan_sunkencity.py. The route is ring_layout.py's; what is here is
the city's own: its heights, the street the route runs down, the blocks either side of it, the
aquarium off its checkpoint, the pier and the whirlpool, and the patrol the thing swims
(SunkenCityClient draws it from the numbers SunkenCityService gives it).

THE CITY IS A LINE NOW, NOT A RING. Everything below is measured along the route and away from it,
because that is how the Luau places it: a grid of blocks in the route's own direction, with any lot
the street runs into pushed back and shortened until its frontage is on the kerb.

Numbers are read from the Luau. The few that live in the Luau as literals inside a function rather
than as named constants are restated in MIRRORED below, each with the exact Luau text it stands
for; the check fails if that text is no longer there, so the two cannot drift apart quietly.
"""
import json
import math
import os
import re

from ring_layout import (BASE_SURFACE_Y, CAP_HALF, CAP_TOP, DESTROY_Y, RingLevel, SRC, beside_frame,  # noqa: F401
                         chunk_frame, finish_frame, kill_y, lua_numbers, xmax)

CITY_SOURCE = (SRC / "Server" / "Services" / "SunkenCityService.lua").read_text(encoding="utf-8")
CLIENT_SOURCE = (SRC / "Client" / "Services" / "SunkenCityClient.lua").read_text(encoding="utf-8")
PATH_SOURCE = (SRC / "Shared" / "SunkenPath.lua").read_text(encoding="utf-8")
K = lua_numbers(CITY_SOURCE)
# SunkenPath's constants are fields, `SunkenPath.NAME = number`, not locals.
P = {name: float(value) for name, value in re.findall(r"^SunkenPath\.([A-Z_]+) = ([\d.]+)", PATH_SOURCE, re.M)}

# Literals inside SunkenCityService's functions, restated. Each key is the exact Luau text.
MIRRORED = {
    "local foot = at + side * (sign * 38)": ("GANTRY_LEG", 38),
    "local beamY = waterLevel - 4.5": ("GANTRY_BEAM_DEPTH", 4.5),
    'Vector3.new(22, 6, 0.4), frame * CFrame.new(-8, -3.7, 0)': ("GANTRY_PANEL", (22, 6, -8, -3.7)),
    "for _, z in ipairs({ 3, PIER_L / 2 - 2, PIER_L - 8 }) do": ("PILE_Z", (3, None, -8)),
    "local miss = math.abs(index - 0.4 * #chunks)": ("AQUARIUM_SHARE", 0.4),
    "local belfryTop = waterLevel + 52": ("CLOCK_TOP", 52),
    "local side = 22": ("CLOCK_SIDE", 22),
    "local plaza = plazaAt + plazaSide * 230": ("PLAZA_OUT", 230),
    # The street: where a lot is skipped, how much of it the street takes, and what may break the
    # surface. These three lines ARE the shape of the city.
    "if near >= BOULEVARD_HALF + 14 and not harbourish then": ("LOT_SKIP", 14),
    "local bite = math.max(0, (BOULEVARD_HALF + 6) - (near - half))": ("LOT_BITE", 6),
    "local clearOfRoute = nearCentre - depth / 2 >= EMERGE_CLEAR + ROUTE_REACH": ("EMERGE_RULE", None),
    "local top = waterLevel + 7": ("LAMP_TOP", 7),
    "column(parent, \"LampPost\", 1.1, Vector3.new(foot.X, floorY, foot.Z), floorY, top,": ("LAMP_D", 1.1),
    "local foot = at + side * (sign * (BOULEVARD_HALF - 2))": ("LAMP_IN", 2),
}
M = {name: value for name, value in MIRRORED.values()}

LEVEL = RingLevel("Level3")


def heights(chunks):
    """SunkenCityService.heights: the surface, the floor, the murk, the tunnel and the shaft's bottom."""
    water = min(ch["y"] for ch in chunks) - K["WATER_UNDER_ROUTE"]
    return {
        "water": water,
        "floor": water - K["FLOOR_DEPTH"],
        "murk": water - K["MURK_DEPTH"],
        "tunnel": water - K["TUNNEL_BELOW"],
        "shaft": water - K["FLOOR_DEPTH"] - K["SHAFT_DEPTH"],
    }


# ===================================================================== the route as a line


def route_of(radius, chunks, finish_y):
    """SunkenCityService.routeOf: the chunks' plan positions with the finish on the end, and the
    directions everything is laid in."""
    points = [chunk_frame(radius, ch)[0] for ch in chunks]
    finish, _, tan = finish_frame(radius, chunks)
    points.append(finish)
    steps = [0.0]
    for index in range(1, len(points)):
        steps.append(steps[-1] + math.dist(points[index], points[index - 1]))
    run = (points[-1][0] - points[0][0], points[-1][1] - points[0][1])
    length = math.hypot(*run)
    forward = (run[0] / length, run[1] / length) if length > 1 else (0.0, 1.0)
    middle = (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))
    return {"points": points, "steps": steps, "total": steps[-1], "forward": forward,
            "side": (-forward[1], forward[0]), "middle": middle, "finish": finish, "tan": tan}


def along_route(route, s):
    """The point `s` studs along the route, and the way it runs there."""
    at = min(max(s, 0.0), route["total"])
    low, high = 0, len(route["steps"]) - 1
    while high - low > 1:
        mid = (low + high) // 2
        if route["steps"][mid] <= at:
            low = mid
        else:
            high = mid
    span = route["steps"][high] - route["steps"][low]
    within = (at - route["steps"][low]) / span if span > 0 else 0.0
    a, b = route["points"][low], route["points"][high]
    run = (b[0] - a[0], b[1] - a[1])
    length = math.hypot(*run)
    direction = (run[0] / length, run[1] / length) if length > 0.001 else route["forward"]
    return (a[0] + run[0] * within, a[1] + run[1] * within), direction


def near_route(route, point):
    """How far a point is from the route in plan, and which way is away from it."""
    best, away = math.inf, route["side"]
    for index in range(len(route["points"]) - 1):
        a, b = route["points"][index], route["points"][index + 1]
        run = (b[0] - a[0], b[1] - a[1])
        length = math.hypot(*run)
        if length <= 0.001:
            continue
        unit = (run[0] / length, run[1] / length)
        along = min(max((point[0] - a[0]) * unit[0] + (point[1] - a[1]) * unit[1], 0.0), length)
        foot = (a[0] + unit[0] * along, a[1] + unit[1] * along)
        gap = math.dist(point, foot)
        if gap < best:
            best = gap
            away = ((point[0] - foot[0]) / gap, (point[1] - foot[1]) / gap) if gap > 0.01 else route["side"]
    return best, away


def along_of(route, point):
    """How far along the route a point is."""
    best, at = math.inf, 0.0
    for index in range(len(route["points"]) - 1):
        a, b = route["points"][index], route["points"][index + 1]
        run = (b[0] - a[0], b[1] - a[1])
        length = math.hypot(*run)
        if length <= 0.001:
            continue
        unit = (run[0] / length, run[1] / length)
        along = min(max((point[0] - a[0]) * unit[0] + (point[1] - a[1]) * unit[1], 0.0), length)
        gap = math.dist(point, (a[0] + unit[0] * along, a[1] + unit[1] * along))
        if gap < best:
            best, at = gap, route["steps"][index] + along
    return at


def harbour_along(route):
    """SunkenCityService.harbourAlong: how much of the route's end belongs to the harbour."""
    return min(K["HARBOUR_ALONG"], route["total"] * K["HARBOUR_ALONG_SHARE"])


def city_lots(route, blocked=None):
    """SunkenCityService.city's grid, as lots: where each block ends up after the street has taken
    its bite out of it, how far it is from the route, and whether anything on it may break the
    surface. The buildings themselves are not laid here; what the check needs is the ground."""
    lots = []
    pitch = K["BLOCK"] + K["STREET"]
    half = K["BLOCK"] / 2
    start = route["points"][0]
    rows = max(1, int((route["total"] + 2 * K["CITY_BEYOND"]) // pitch))
    cols = max(1, int(K["CITY_SIDE"] * 2 // pitch))
    for row in range(rows + 1):
        for col in range(cols + 1):
            s = -K["CITY_BEYOND"] + (row + 0.5) * pitch
            across = -K["CITY_SIDE"] + (col + 0.5) * pitch
            spot = (start[0] + route["forward"][0] * s + route["side"][0] * across,
                    start[1] + route["forward"][1] * s + route["side"][1] * across)
            near, away = near_route(route, spot)
            along = along_of(route, spot)
            harbourish = along > route["total"] - harbour_along(route) and near < K["HARBOUR_REACH"]
            if near < K["BOULEVARD_HALF"] + M["LOT_SKIP"] or harbourish:
                continue
            bite = max(0.0, (K["BOULEVARD_HALF"] + M["LOT_BITE"]) - (near - half))
            depth = K["BLOCK"] - bite
            if depth < K["LOT_MIN"]:
                continue
            centre = (spot[0] + away[0] * bite / 2, spot[1] + away[1] * bite / 2)
            reach = math.hypot(depth, K["BLOCK"]) / 2
            if blocked and blocked(centre, reach):
                continue
            near_centre, _ = near_route(route, centre)
            # Which way it faces: the street on the kerb, the grid further back (see the Luau).
            grid_way = route["side"] if across >= 0 else (-route["side"][0], -route["side"][1])
            facing = away if near < 320 else grid_way
            lots.append({"centre": centre, "near": near_centre, "depth": depth, "away": facing,
                         # Whether anything on it may break the surface is judged the way the Luau
                         # judges it: by where its frontage actually is, once the street has taken
                         # its bite.
                         "emerges": near_centre - depth / 2 >= K["EMERGE_CLEAR"] + K["ROUTE_REACH"],
                         "inner": near_centre - depth / 2})
    return lots


# ===================================================================== what stands beside the route


def aquarium_checkpoint(chunks):
    """SunkenCityService.build's pick: the straight chunk nearest two fifths of the way, never the
    first or the last."""
    best, gap = None, math.inf
    for ch in chunks[1:-1]:
        if ch["id"] == "S1_Straight":
            miss = abs(ch["index"] - M["AQUARIUM_SHARE"] * len(chunks))
            if miss < gap:
                best, gap = ch, miss
    return best


def aquarium(radius, ch, side=-1):
    """The aquarium's pieces in plan: the tower's centre, the tunnel's two ends and the gallery's
    middle, with the frame's outward and along directions. On the LEFT of the street."""
    edge, out, along = beside_frame(radius, ch, side)

    def at(x, z=0.0):
        return (edge[0] + out[0] * x + along[0] * z, edge[1] + out[1] * x + along[1] * z)

    xc = K["AQ_NECK"] + K["ROT_R"] - K["ROT_WALL"]
    t0 = xc + K["ROT_R"] - 0.3
    t1 = t0 + K["TUNNEL_L"]
    room = t1 + K["ROOM_L"] / 2 - 0.3
    return {"edge": edge, "out": out, "along": along, "tower": at(xc), "tunnel": (at(t0), at(t1)), "room": at(room),
            "far": at(room + K["ROOM_L"] / 2), "xc": xc, "t0": t0, "t1": t1, "room_x": room, "at": at,
            "landing_y": ch["y"] + CAP_TOP}


def flat_checkpoint(chunks, aquarium_ch):
    """SunkenCityService.build's pick for the dry flat: the straight chunk nearest FLAT_SHARE of the
    way, never the first, the last three or the aquarium's."""
    best, gap = None, math.inf
    for ch in chunks[1:-3]:
        if ch["id"] == "S1_Straight" and ch is not aquarium_ch:
            miss = abs(ch["index"] - K["FLAT_SHARE"] * len(chunks))
            if miss < gap:
                best, gap = ch, miss
    return best


def flat(radius, ch, side=1):
    """The dry flat's building in plan and its landing height. On the RIGHT of the street."""
    edge, out, along = beside_frame(radius, ch, side)
    x0, x1 = K["FLAT_GANG"], K["FLAT_GANG"] + K["FLAT_D"]
    mid = (x0 + x1) / 2
    centre = (edge[0] + out[0] * mid, edge[1] + out[1] * mid)
    return {"edge": edge, "out": out, "along": along, "x": (x0, x1), "z": (-K["FLAT_W"] / 2, K["FLAT_W"] / 2),
            "centre": centre, "landing_y": ch["y"] + CAP_TOP}


def finale(radius, chunks, finish_y):
    """The pier, its piles and the whirlpool, in plan, from the finish frame."""
    finish, out, tan = finish_frame(radius, chunks)

    def at(x, z):
        return (finish[0] + out[0] * x + tan[0] * z, finish[1] + out[1] * x + tan[1] * z)

    pier_l, pier_w = K["PIER_L"], K["PIER_W"]
    piles = []
    for z in (3, pier_l / 2 - 2, pier_l - 8):
        for x in (-pier_w / 2 + 2, pier_w / 2 - 2):
            piles.append(at(x, z))
    return {"finish": finish, "out": out, "tan": tan, "vortex": at(0, pier_l + K["VORTEX_GAP"]), "piles": piles,
            "pier_top": finish_y + CAP_TOP, "at": at}


# ===================================================================== the thing


def monster_span(route):
    """How far along the route it patrols: up the line and back, turning MONSTER_KEEP short of the
    harbour (SunkenPath.along)."""
    return max(60.0, route["total"] - K["MONSTER_KEEP"])


def serpent_extents():
    """The serpent mesh as gen_serpent.py built it (blender/sealife_extents.json), or None."""
    try:
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "sealife_extents.json"),
                  encoding="utf-8") as handle:
            return json.load(handle).get("Sea_Serpent")
    except (OSError, ValueError):
        return None


def monster_reach():
    """How far the thing's body reaches from its own centre line: sideways (sway plus half its
    width), up (half its height, and the back fins above that) and down. The part-built body's
    numbers, or the serpent mesh's where it reaches further: its width, or its fluke turned with
    the tail as far as the body turns off the path (`side_reach`), its crest and its barbels."""
    g = K["MONSTER_GIRTH"]
    side, up, down = 0.9 * g, 1.3 * g, 0.75 * g
    mesh = serpent_extents()
    if mesh:
        side = max(side, mesh.get("side_reach", 0.0), abs(mesh["lo"][0]), mesh["hi"][0])
        up = max(up, mesh["hi"][2])
        down = max(down, -mesh["lo"][2])
    return {"side": P["SWAY"] + side, "up": up, "down": down}


def monster_from_route():
    """And how far from the ROUTE's own line, which is what everything beside the street is measured
    against: its wander off the line plus its body."""
    return K["MONSTER_SWING"] + monster_reach()["side"]
