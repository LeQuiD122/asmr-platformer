"""Level 2, Sky Pools, as built: from above and unrolled, for one medium run.

Run with plain Python from the project root:  python blender/plan_skypools.py [seed]

Laid by skypools_layout.py, which is the same Python the check (check_skypools.py) tests, so this
picture is of the level the check passed rather than of a proposal. Writes blender/skypools_plan.png.
"""
import math
import pathlib
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Circle, Polygon  # noqa: E402

from skypools_layout import (BASE_SURFACE_Y, CAP_TOP, RUNS, S, chosen_terraces, chunk_frame,  # noqa: E402
                             finish_frame, heights, kill_y, lay, slide_point, slide_spec, terrace_frame, xmax)

SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 0
COUNT = dict(RUNS)["medium"]
radius, chunks, finish_y = lay(COUNT, SEED)
cloud_top, pool_y, sea_y, top_y = heights(BASE_SURFACE_Y, kill_y(chunks))
spec = slide_spec(radius, chunks, finish_y)
terraces = chosen_terraces(chunks)
COLOURS = {"S": "#d9d2c6", "P": "#f1c9a8", "R": "#e79aa0", "C": "#e79aa0"}
POOL, DECK, SLIDE, STONE = "#3aa3c4", "#f4f5f2", "#8e7cc3", "#b9c4cc"


def quad(origin, out, along, x0, x1, z0, z1):
    return [(origin[0] + out[0] * x + along[0] * z, origin[1] + out[1] * x + along[1] * z)
            for x, z in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))]


fig = plt.figure(figsize=(17.5, 9.2))
ax = fig.add_axes([0.02, 0.06, 0.44, 0.86])
bx = fig.add_axes([0.5, 0.08, 0.48, 0.82])

# ===================================================================== from above
ax.set_facecolor("#dfeaf6")
ax.add_patch(Circle((0, 0), S["CLOUD_REACH"], color="#f7fafd"))
ax.add_patch(Circle((0, 0), S["FINAL_RADIUS"], color=POOL, alpha=0.35))
ax.text(0, -S["FINAL_RADIUS"] + 16, "final pool, under the clouds", ha="center", fontsize=7, color="#10485a")
ax.add_patch(Circle((0, 0), S["BASIN_D"] / 2, color="#ffffff", ec="#7aa9c0", lw=1.2, zorder=5))
ax.add_patch(Circle((0, 0), S["TOWER_D"] / 2, color=STONE, zorder=6))
ax.text(0, 0, "tower", ha="center", va="center", fontsize=7, zorder=7)
for ch in chunks:
    origin, out, tan = chunk_frame(radius, ch)
    reach = xmax(ch["id"])
    ax.add_patch(Polygon(quad(origin, out, tan, -reach, reach, 0, ch["length"]), closed=True,
                         color=COLOURS[ch["id"][0]], ec="#6b6259", lw=0.4))
for n, ch in enumerate(terraces):
    edge, out, along = terrace_frame(radius, ch)
    lz = S["TERRACE_L"] / 2
    ax.add_patch(Polygon(quad(edge, out, along, 0, S["NECK"] + S["TERRACE_W"], -lz, lz), closed=True, color=DECK,
                         ec="#7a8c99", lw=0.6))
    pool_x = S["NECK"] + S["TERRACE_W"] * 0.55
    ax.add_patch(Polygon(quad(edge, out, along, pool_x - S["POOL_W"] / 2, pool_x + S["POOL_W"] / 2,
                              -S["POOL_L"] / 2, S["POOL_L"] / 2), closed=True, color=POOL))
    tip = (edge[0] + out[0] * (S["NECK"] + S["TERRACE_W"] + 60), edge[1] + out[1] * (S["NECK"] + S["TERRACE_W"] + 60))
    ax.text(tip[0], tip[1], "start" if n == 0 else "terrace %d" % n, ha="center", va="center", fontsize=8,
            color="#1f5e70")
finish, out, tan = finish_frame(radius, chunks)
ax.add_patch(Polygon(quad(finish, out, tan, -S["WALK_W"] / 2, S["WALK_W"] / 2 + 34, 0, S["WALK_L"]), closed=True,
                     color=DECK, ec="#7a8c99", lw=0.6))
plan = [slide_point(spec, i / 300)[0] for i in range(301)]
ax.plot(*zip(*plan), color=SLIDE, lw=3, zorder=4)
mid = plan[150]
ax.text(mid[0] * 0.7, mid[1] * 0.7, "the slide", fontsize=9, color="#5a4a8a", ha="center")
ax.text(finish[0] * 1.35, finish[1] * 1.35, "finale deck", ha="center", fontsize=8, color="#5a4a8a")
ring = radius + 530
ax.add_patch(Circle((0, 0), ring, fill=False, ls=":", ec="#8fb3c0"))
ax.text(0, ring + 25, "scenery pools on columns, somewhere on this ring", ha="center", fontsize=8, color="#4a6f7a")
view = radius + 800
ax.set_xlim(-view, view)
ax.set_ylim(-view, view)
ax.set_aspect("equal")
ax.set_xticks([])
ax.set_yticks([])
ax.set_title("Sky Pools from above: %d chunks round a %.0f-stud ring, %d terraces (seed %d)"
             % (len(chunks), radius, len(terraces), SEED))

# ===================================================================== unrolled
bx.set_facecolor("#cfe3f5")
bx.axhspan(cloud_top - S["CLOUD_THICK"], cloud_top, color="#ffffff", alpha=0.95)
bx.text(20, cloud_top - S["CLOUD_THICK"] / 2, "the cloud sea", va="center", fontsize=9, color="#7a8c99")
bx.axhspan(sea_y - 60, sea_y, color="#2e6a92")
bx.axhline(kill_y(chunks), color="#c55", lw=0.8, ls="--")
bx.text(20, kill_y(chunks) - 14, "kill plane", fontsize=7, color="#a33")
along = 0.0
positions = {}
for ch in chunks:
    positions[ch["index"]] = along
    top = ch["y"] + (CAP_TOP if ch["id"].startswith("S") else 2)
    bx.add_patch(plt.Rectangle((along, top - 4), ch["length"], 4, color=COLOURS[ch["id"][0]], ec="#6b6259", lw=0.3))
    along += ch["length"] + 5
for ch in terraces:
    x = positions[ch["index"]] + ch["length"] / 2
    top = ch["y"] + CAP_TOP
    bx.plot([x - 12, x + 12], [top, top], color="#7a8c99", lw=4)
    bx.plot([x, x], [top - 4, sea_y], color=STONE, lw=1)
    bx.plot([x + 14, x + 14], [top - 1, sea_y], color="#6fc3d8", lw=1.6, alpha=0.7)
end = along - 5
bx.plot([end, end + S["WALK_L"]], [finish_y + CAP_TOP] * 2, color="#7a8c99", lw=4)
# the slide, unrolled by distance along it
distance, prev, pts = end + S["WALK_L"], None, []
for i in range(301):
    p, y, _ = slide_point(spec, i / 300)
    if prev:
        distance += math.hypot(math.hypot(p[0] - prev[0][0], p[1] - prev[0][1]), y - prev[1])
    pts.append((distance, y))
    prev = (p, y)
bx.plot(*zip(*pts), color=SLIDE, lw=3)
bx.add_patch(plt.Rectangle((distance - 40, pool_y - S["FINAL_DEEP"]), 2 * S["FINAL_RADIUS"], S["FINAL_DEEP"], color=POOL))
bx.text(distance + 60, pool_y + 18, "final pool: the splash\nends the level", ha="center", fontsize=8)
bx.plot([distance + 2 * S["FINAL_RADIUS"] - 40] * 2, [pool_y, sea_y], color="#6fc3d8", lw=2, alpha=0.7)
bx.text(distance + 2 * S["FINAL_RADIUS"] - 30, (pool_y + sea_y) / 2, "drains to\nthe sea", fontsize=8, color="#2e6a92")
# the tower, for scale, drawn at the left
bx.plot([-50, -50], [sea_y, top_y], color=STONE, lw=7)
bx.add_patch(plt.Rectangle((-50 - S["BASIN_D"] / 2, top_y - 8), S["BASIN_D"], 8, color="#ffffff", ec="#7aa9c0"))
bx.text(-50, top_y + 12, "fountain tower", ha="center", fontsize=8)
bx.set_xlim(-110, distance + 2 * S["FINAL_RADIUS"] + 60)
bx.set_ylim(sea_y - 40, top_y + 40)
bx.set_xlabel("distance along the route, then along the slide (studs)")
bx.set_ylabel("height (studs)")
bx.set_title("Unrolled: down from %d to %d, then %.0f studs of slide down to the pool at %d"
             % (BASE_SURFACE_Y, finish_y, distance - end - S["WALK_L"], pool_y))
for key, label in (("S", "stable chunk (checkpoint)"), ("P", "pace chunk"), ("R", "risk chunk")):
    bx.bar(0, 0, color=COLOURS[key], label=label)
bx.legend(loc="lower left", fontsize=8)
out_path = pathlib.Path(__file__).with_name("skypools_plan.png")
fig.savefig(out_path, dpi=85)
print("wrote %s | radius %.0f, surface %d to %d, clouds %d, pool %d, sea %d, slide %.0f studs"
      % (out_path, radius, BASE_SURFACE_Y, finish_y, cloud_top, pool_y, sea_y, distance - end - S["WALK_L"]))
