"""Sky Pools (Level 2) laid out in Python, the way LevelService and SkyPoolsService lay it in Luau.

Shared by check_skypools.py (which holds the layout to its rules) and plan_skypools.py (which draws
it), so the picture and the check can never be of two different levels. The ring itself is
ring_layout.py's, which the Sunken City shares; what is here is Sky Pools' own: its numbers, its
heights, its terraces and its slide.
"""
import math

from ring_layout import (BASE_SURFACE_Y, C, CAP_HALF, CAP_TOP, CONTRACTS, DESTROY_Y, GAP, LAYOUTS, ROOT,  # noqa: F401
                         SRC, RingLevel, beside_frame, chunk_frame, declared_category, finish_frame, kill_y,
                         lua_numbers, xmax)

SKY = (SRC / "Server" / "Services" / "SkyPoolsService.lua").read_text(encoding="utf-8")
S = lua_numbers(SKY)
S["DECK_THICK"] = S["POOL_DEPTH"] + 1  # `local DECK_THICK = POOL_DEPTH + 1`

LEVEL = RingLevel("Level2")
LEVEL2 = LEVEL.block
POOL_IDS = LEVEL.pool_ids
RING = LEVEL.has_ring
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


def terrace_frame(radius, ch):
    """terraceBeside's frame: the cap's outer edge, outward from the middle, and along the route."""
    return beside_frame(radius, ch)


def slide_spec(radius, chunks, finish_y):
    finish, _, tan = finish_frame(radius, chunks)
    mouth = (finish[0] + tan[0] * S["WALK_L"], finish[1] + tan[1] * S["WALK_L"])
    _, pool_y, _, _ = heights(BASE_SURFACE_Y, kill_y(chunks))
    return {"a0": math.atan2(mouth[1], mouth[0]), "r0": math.hypot(*mouth), "r1": S["SLIDE_END_RADIUS"],
            "y0": finish_y + CAP_TOP, "y1": pool_y + 0.4, "turns": S["SLIDE_TURNS"]}


def slide_point(spec, f):
    """SkyPoolsService's slidePoint: ((x, z), y, radius)."""
    theta = spec["a0"] + f * spec["turns"] * 2 * math.pi
    r = spec["r0"] + (spec["r1"] - spec["r0"]) * f
    ease = f * f * (3 - 2 * f)
    return (math.cos(theta) * r, math.sin(theta) * r), spec["y0"] + (spec["y1"] - spec["y0"]) * ease, r
