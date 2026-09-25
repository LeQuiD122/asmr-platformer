"""Sky Pools (Level 2) laid out in Python, the way LevelService and SkyPoolsService lay it in Luau.

Shared by check_skypools.py (which holds the layout to its rules) and plan_skypools.py (which draws
it), so the picture and the check can never be of two different levels. The route itself is
ring_layout.py's, which the Sunken City shares; what is here is Sky Pools' own: its numbers, its
heights, the shape of a terrace, and the slide.

Sky Pools is laid as a MEANDER now rather than a ring, so there is no middle to build round: the
terraces take alternating sides of the route and the tower stands ahead of the finish. Everything
below reads which one the level declared, so this file stays right either way.
"""
import math
import re

from ring_layout import (BASE_SURFACE_Y, C, CAP_HALF, CAP_TOP, CONTRACTS, DESTROY_Y, GAP, LAYOUTS, ROOT,  # noqa: F401
                         SRC, RingLevel, beside_frame, chunk_frame, declared_category, finish_frame, kill_y,
                         lua_numbers, xmax)

SKY = (SRC / "Server" / "Services" / "SkyPoolsService.lua").read_text(encoding="utf-8")
S = lua_numbers(SKY)
S["DECK_THICK"] = S["POOL_DEPTH"] + 1  # `local DECK_THICK = POOL_DEPTH + 1`

# The slide's width, speed and timing live in the shared module both sides read, as `SkyPath.NAME`.
SKYPATH = (SRC / "Shared" / "SkyPath.lua").read_text(encoding="utf-8")
P = {}
for line in SKYPATH.splitlines():
    found = re.match(r"^SkyPath\.(.+?)\s*=\s*([-\d.,\s]+?)\s*(?:--.*)?$", line)
    if found:
        keys = [k.strip().replace("SkyPath.", "") for k in found.group(1).split(",")]
        values = [v.strip() for v in found.group(2).split(",")]
        if len(keys) == len(values):
            for key, value in zip(keys, values):
                try:
                    P[key] = float(value)
                except ValueError:
                    pass

LEVEL = RingLevel("Level2")
LEVEL2 = LEVEL.block
POOL_IDS = LEVEL.pool_ids
RING = LEVEL.has_ring
IS_MEANDER = LEVEL.is_meander
AMPLITUDE, WAVELENGTH = LEVEL.amplitude, LEVEL.wavelength
DESCENDS = LEVEL.descends
TURN = LEVEL.turn
STEP_SCALE = LEVEL.step_scale
SLOTS = LEVEL.slots
MIN_CHUNKS = LEVEL.min_chunks
RUNS = LEVEL.runs
BY_CATEGORY = LEVEL.by_category
ring_radius = LEVEL.ring_radius
lay = LEVEL.lay


def heights(start_y, kill_y_value):
    """SkyPoolsService.heights: (cloudTop, poolY, seaY, topY)."""
    cloud_top = kill_y_value + S["CLOUD_ABOVE_KILL"]
    pool_y = max(cloud_top - S["CLOUD_THICK"] - S["FINAL_BELOW"], DESTROY_Y + S["POOL_ABOVE_DESTROY"])
    return cloud_top, pool_y, pool_y - S["SEA_BELOW"], start_y + S["TOWER_ABOVE"]


def chosen_terraces(chunks):
    """SkyPoolsService.build's pick: the first stable chunk, then the nearest to each fifth."""
    stable = [ch for ch in chunks[:-1] if ch["id"] == "S1_Straight"]
    chosen = []
    if stable:
        chosen.append(stable[0])
        for share in (0.2, 0.4, 0.6, 0.8):
            wanted = share * len(chunks)
            pick = min((ch for ch in stable if ch not in chosen), key=lambda ch: abs(ch["index"] - wanted),
                       default=None)
            if pick:
                chosen.append(pick)
    return chosen


def terrace_frame(radius, ch, index=1):
    """terraceBeside's frame. Away from the middle on a ring; on a meander the terraces take
    alternating sides of the route, the first to its right, as build() alternates them."""
    if IS_MEANDER:
        return beside_frame(radius, ch, 1 if index % 2 == 1 else -1)
    return beside_frame(radius, ch)


# ===================================================================== the shape of a terrace


def terrace_plan(x0, wide, long):
    """SkyPoolsService.terrace, in its own frame: every edge, every column and everything that
    stands on the deck. One place, so the check and the picture cannot disagree about it."""
    x1 = x0 + wide
    lz = long / 2
    entry_half = max(6, long * S["ENTRY_SHARE"])
    pool_w = min(S["POOL_W"], wide * 0.5)
    px0 = x0 + wide * S["POOL_FROM"]
    px1 = px0 + pool_w
    pz = min(S["POOL_L"], long * 0.42) / 2
    pool_x = (px0 + px1) / 2
    nose_r = min(lz - 4, wide * 0.22, x1 - px1 - 0.8)
    shoulder = min(6, (px0 - x0) * 0.6)
    inner_z = min(8, lz - 6)
    outer_z = min(8, lz - 8.2)
    steps_end = px0 + S["BEACH_STEPS"] * S["STEP_RUN"]
    channel = min(10, pz * 1.4)
    lip_x = x1 + nose_r - 0.5
    sun_z = min(pz + 4.6, lz - 4.3)
    shade_z = -min(pz + 5, lz - 3)
    spread = max(3.4, pool_w * 0.2)
    towel_x = min(pool_x + pool_w * 0.38, px1 - 2.2)
    chair_z = -pz - S["LIFEGUARD_BACK"]
    plan = {
        "x0": x0, "x1": x1, "lz": lz, "entry_half": entry_half, "px0": px0, "px1": px1, "pz": pz,
        "pool_x": pool_x, "pool_w": pool_w, "nose_r": nose_r, "shoulder": shoulder, "inner_z": inner_z,
        "outer_z": outer_z, "steps_end": steps_end, "channel": channel, "lip_x": lip_x, "sun_z": sun_z,
        "shade_z": shade_z,
        # The deck, strip by strip: the walk in, its two shoulders, the two sun decks, the band.
        "decks": [
            (x0, px0, -entry_half, entry_half),
            (px0 - shoulder, px0, -(lz - 3), -entry_half),
            (px0 - shoulder, px0, entry_half, lz - 3),
            (px0, px1, -lz, -pz),
            (px0, px1, pz, lz),
            (px1, x1, -(lz - 5), lz - 5),
        ],
        "prow": (x1, 0.0, nose_r),
        "pool": (px0, px1, -pz, pz),
        "columns": [(px0 - 2.5, -inner_z), (px0 - 2.5, inner_z), (px1 + 2.5, -outer_z), (px1 + 2.5, outer_z),
                    (px0 + 3.5, -(lz - 3)), (px0 + 3.5, lz - 3), (px1 - 3.5, -(lz - 3)), (px1 - 3.5, lz - 3),
                    (x1, 0.0)],
        "spill": (px1, lip_x, -channel / 2 - 0.6, channel / 2 + 0.6),
        # Everything that stands on the deck, as (x0, x1, z0, z1) boxes in this frame.
        "stands": {
            "loungers": [(pool_x + dx - 1.4, pool_x + dx + 1.4, sun_z - 3.0, sun_z + 4.1)
                         for dx in (-spread, spread)],
            "parasol": [(pool_x - 1.3, pool_x + 1.3, sun_z - 1.3, sun_z + 1.3)],
            "towel": [(towel_x - 1.7, towel_x + 1.7, sun_z - 3.8, sun_z + 1.8)],
            "pergola": [(pool_x - 5.9, pool_x + 5.9, shade_z - 4.9, shade_z + 1.9)],
            "planters": [(px0 - shoulder - 4.1, px0 - shoulder - 0.7, side * (entry_half - 2.2) - 1.7,
                          side * (entry_half - 2.2) + 1.7) for side in (-1, 1)],
            "cabana": [(px0 + S["CABANA_FROM"], px0 + S["CABANA_FROM"] + S["CABANA_W"], pz + 1.5, lz - 0.5)],
            "lifeguard": [(pool_x - 1.6, pool_x + 1.6, chair_z - 1.6, chair_z + 3.5),
                          (pool_x + 3.6, pool_x + 4.4, chair_z - 1.4, chair_z + 1.4)],
            # Only the board's stand is on the deck; its plank reaches out over the water on purpose.
            "board": [(pool_x + 4.5 - 1.6, pool_x + 4.5 + 1.6, shade_z - 2.6, shade_z + 0.6)],
        },
        # The board's plank and the ladder are over or in the pool, which is where they belong.
        "over_water": {
            "board": [(pool_x + 3, pool_x + 6, shade_z - 2.5, shade_z + 9.5)],
            "ladder": [(pool_x + 2.6, pool_x + 5.4, pz - 2, pz)],
        },
    }
    return plan


def in_box(box, point, pad=0.0):
    return box[0] - pad <= point[0] <= box[1] + pad and box[2] - pad <= point[1] <= box[3] + pad


def boxes_overlap(a, b, margin=0.0):
    return a[0] < b[1] + margin and b[0] < a[1] + margin and a[2] < b[3] + margin and b[2] < a[3] + margin


def under_terrace(plan, point, pad=0.0):
    """True where there is something at deck level over `point`: a deck strip, the prow or the pool's
    own floor, which sits at the same underside and is carried by the same columns."""
    if in_box(plan["pool"], point, pad):
        return True
    for box in plan["decks"]:
        if in_box(box, point, pad):
            return True
    cx, cz, r = plan["prow"]
    return math.hypot(point[0] - cx, point[1] - cz) <= r + pad


def on_deck(plan, point, pad=0.0):
    """True where you could stand: a deck strip or the prow, but not over the water."""
    if in_box(plan["pool"], point, -0.4):
        return False
    for box in plan["decks"]:
        if in_box(box, point, pad):
            return True
    cx, cz, r = plan["prow"]
    return math.hypot(point[0] - cx, point[1] - cz) <= r + pad


# ===================================================================== the slide


def slide_spec(radius, chunks, finish_y):
    """SkyPoolsService.build's slide: round the tower, in and down to the pool. On a meander the
    tower stands TOWER_AHEAD past the mouth, and the slide sweeps away from the walkway's terrace."""
    finish, out, tan = finish_frame(radius, chunks)
    mouth = (finish[0] + tan[0] * S["WALK_L"], finish[1] + tan[1] * S["WALK_L"])
    _, pool_y, _, _ = heights(BASE_SURFACE_Y, kill_y(chunks))
    centre = ((mouth[0] - out[0] * S["TOWER_ASIDE"], mouth[1] - out[1] * S["TOWER_ASIDE"]) if IS_MEANDER
              else (0.0, 0.0))
    flat = (mouth[0] - centre[0], mouth[1] - centre[1])
    spec = {"centre": centre, "mouth": mouth, "forward": tan, "aside": out,
            "a0": math.atan2(flat[1], flat[0]), "r0": math.hypot(*flat),
            "r1": S["SLIDE_END_RADIUS"], "y0": finish_y + CAP_TOP, "y1": pool_y + 0.4,
            "turns": S["SLIDE_TURNS"]}
    early = slide_point(spec, 0.03)[0]
    if (early[0] - mouth[0]) * tan[0] + (early[1] - mouth[1]) * tan[1] < 0:
        spec["turns"] = -S["SLIDE_TURNS"]
    return spec


def slide_point(spec, f):
    """SkyPath.point: ((x, z), y, radius from the tower)."""
    theta = spec["a0"] + f * spec["turns"] * 2 * math.pi
    r = spec["r0"] + (spec["r1"] - spec["r0"]) * f
    ease = f * f * (3 - 2 * f)
    cx, cz = spec["centre"]
    return (cx + math.cos(theta) * r, cz + math.sin(theta) * r), spec["y0"] + (spec["y1"] - spec["y0"]) * ease, r
