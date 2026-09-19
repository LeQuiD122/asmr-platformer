"""The Sunken City (Level 3) laid out in Python, the way LevelService and SunkenCityService lay it.

Shared by check_sunkencity.py and plan_sunkencity.py. The ring is ring_layout.py's; what is here is
the city's own: its heights, the aquarium off its checkpoint, the pier and the whirlpool, and the
path the thing swims (SunkenCityClient draws it from the numbers SunkenCityService gives it).

Numbers are read from the Luau. The few that live in the Luau as literals inside a function rather
than as named constants are restated in MIRRORED below, each with the exact Luau text it stands
for; the check fails if that text is no longer there, so the two cannot drift apart quietly.
"""
import math
import re

from ring_layout import (BASE_SURFACE_Y, CAP_HALF, CAP_TOP, DESTROY_Y, RingLevel, SRC, beside_frame,  # noqa: F401
                         chunk_frame, finish_frame, kill_y, lua_numbers, xmax)

CITY_SOURCE = (SRC / "Server" / "Services" / "SunkenCityService.lua").read_text(encoding="utf-8")
CLIENT_SOURCE = (SRC / "Client" / "Services" / "SunkenCityClient.lua").read_text(encoding="utf-8")
PATH_SOURCE = (SRC / "Shared" / "SunkenPath.lua").read_text(encoding="utf-8")
K = lua_numbers(CITY_SOURCE)
# SunkenPath's constants are fields, `SunkenPath.NAME = number`, not locals.
P = {name: float(value) for name, value in re.findall(r"^SunkenPath\.([A-Z_]+) = ([\d.]+)", PATH_SOURCE, re.M)}


def turn_constant(name):
    """A constant written as a share of a turn: `local NAME = 0.1 * 2 * math.pi`."""
    found = re.search(r"^local %s = ([\d.]+) \* 2 \* math.pi" % name, CITY_SOURCE, re.M)
    return float(found.group(1)) * 2 * math.pi if found else None


K["HARBOUR_SWERVE_HALF"] = turn_constant("HARBOUR_SWERVE_HALF")
K["HARBOUR_SECTOR_HALF"] = turn_constant("HARBOUR_SECTOR_HALF")

# Literals inside SunkenCityService's functions, restated. Each key is the exact Luau text.
MIRRORED = {
    "local foot = centre + out * (radius + side * 38)": ("GANTRY_LEG", 38),
    "local beamY = waterLevel - 4.5": ("GANTRY_BEAM_DEPTH", 4.5),
    'Vector3.new(22, 6, 0.4), frame * CFrame.new(-8, -3.7, 0)': ("GANTRY_PANEL", (22, 6, -8, -3.7)),
    "local r = radius + BOULEVARD_HALF + EMERGE_CLEAR + rng:NextNumber(20, 300)": ("BUOY_FROM", 20),
    "centre + boatOut * (radius + 150)": ("BOAT_OUT", 150),
    "local boatAt = harbourAngle - 0.08 * 2 * math.pi": ("BOAT_ANGLE", -0.08),
    "local base = centre + out * (radius + 230)": ("CRANE_OUT", 230),
    "for _, z in ipairs({ 3, PIER_L / 2 - 2, PIER_L - 8 }) do": ("PILE_Z", (3, None, -8)),
    "local miss = math.abs(index - 0.4 * #chunks)": ("AQUARIUM_SHARE", 0.4),
    "local top = waterLevel + 44": ("CLOCK_TOP", 44),
    "local side = 22": ("CLOCK_SIDE", 22),
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


def aquarium(radius, ch):
    """The aquarium's pieces in plan: the tower's centre, the tunnel's two ends and the gallery's
    middle, with the frame's outward and along directions."""
    edge, out, along = beside_frame(radius, ch)

    def at(x, z=0.0):
        return (edge[0] + out[0] * x + along[0] * z, edge[1] + out[1] * x + along[1] * z)

    xc = K["AQ_NECK"] + K["ROT_R"] - K["ROT_WALL"]
    t0 = xc + K["ROT_R"] - 0.3
    t1 = t0 + K["TUNNEL_L"]
    room = t1 + K["ROOM_L"] / 2 - 0.3
    return {"edge": edge, "out": out, "along": along, "tower": at(xc), "tunnel": (at(t0), at(t1)), "room": at(room),
            "far": at(room + K["ROOM_L"] / 2), "xc": xc, "t0": t0, "t1": t1, "room_x": room, "at": at,
            "landing_y": ch["y"] + CAP_TOP}


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


def flat_checkpoint(chunks, aquarium_ch):
    """SunkenCityService.build's pick for the dry flat: the straight chunk nearest FLAT_SHARE of the way,
    never the first, the last or the aquarium's."""
    best, gap = None, math.inf
    for ch in chunks[1:-1]:
        if ch["id"] == "S1_Straight" and ch is not aquarium_ch:
            miss = abs(ch["index"] - K["FLAT_SHARE"] * len(chunks))
            if miss < gap:
                best, gap = ch, miss
    return best


def flat(radius, ch):
    """The dry flat's building in plan (as a box in the frame beside its checkpoint) and its landing height."""
    edge, out, along = beside_frame(radius, ch)
    x0, x1 = K["FLAT_GANG"], K["FLAT_GANG"] + K["FLAT_D"]
    mid = ((x0 + x1) / 2)
    centre = (edge[0] + out[0] * mid, edge[1] + out[1] * mid)
    return {"edge": edge, "out": out, "along": along, "x": (x0, x1), "z": (-K["FLAT_W"] / 2, K["FLAT_W"] / 2),
            "centre": centre, "landing_y": ch["y"] + CAP_TOP}


def wrap(a):
    return (a + math.pi) % (2 * math.pi) - math.pi


def swerve_at(theta, harbour):
    """SunkenCityClient.swerveAt."""
    d = wrap(theta - harbour)
    half = K["HARBOUR_SWERVE_HALF"]
    if abs(d) >= half:
        return 0.0
    return K["HARBOUR_SWERVE"] * 0.5 * (1 + math.cos(math.pi * d / half))


def monster_radius(radius, theta, harbour):
    """How far out the thing's centre line is at an angle, before its sway."""
    return radius - K["MONSTER_INSET"] + swerve_at(theta, harbour)


def monster_reach():
    """How far the thing's body reaches from its centre line: sideways (sway plus half its width), up
    (half its height, and the back fins above that) and down."""
    g = K["MONSTER_GIRTH"]
    return {"side": P["SWAY"] + 0.9 * g, "up": 1.3 * g, "down": 0.75 * g}


def bands(radius):
    """SunkenCityService's bands: (from, to, kind)."""
    out = []
    inner_from = K["PLAZA_RADIUS"] + K["STREET"] / 2
    inner_to = radius - K["BOULEVARD_HALF"] - K["STREET"] / 2
    depth = inner_to - inner_from
    if depth >= 30:
        count = max(1, int((depth + K["STREET"]) // (K["INNER_BAND"] + K["STREET"])))
        each = (depth - (count - 1) * K["STREET"]) / count
        for index in range(1, count + 1):
            start = inner_from + (index - 1) * (each + K["STREET"])
            out.append((start, start + each, "nearInner" if index == count else "inner"))
    outer_from = radius + K["BOULEVARD_HALF"] + K["STREET"] / 2
    for index in range(1, int(K["OUTER_BANDS"]) + 1):
        start = outer_from + (index - 1) * (K["OUTER_BAND"] + K["STREET"])
        out.append((start, start + K["OUTER_BAND"], "nearOuter" if index == 1 else "outer%d" % index))
    return out
