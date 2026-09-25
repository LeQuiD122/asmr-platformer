"""Level 3, The Sunken City, as built: from above, and in section through the aquarium and the drain.

Run with plain Python from the project root:  python blender/plan_sunkencity.py [seed]

Laid by sunkencity_layout.py, the same Python check_sunkencity.py tests. The lots are drawn as the
ground they stand on: SunkenCityService fills each one from Roblox's random numbers, which Python
cannot reproduce, so the picture shows where buildings may stand and what may break the surface,
not which building stands where. Writes blender/sunkencity_plan.png.
"""
import math
import pathlib
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Circle, Ellipse, Polygon, Wedge  # noqa: E402

from ring_layout import CAP_TOP, chunk_frame, xmax  # noqa: E402
from sunkencity_layout import (K, LEVEL, M, along_route, aquarium, aquarium_checkpoint, city_lots,  # noqa: E402
                               finale, flat, flat_checkpoint, heights, monster_span, route_of)

SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 0
COUNT = dict(LEVEL.runs)["medium"]
radius, chunks, finish_y = LEVEL.lay(COUNT, SEED)
h = heights(chunks)
kill = min(ch["y"] for ch in chunks) - 40
fin = finale(radius, chunks, finish_y)
vortex = fin["vortex"]
route = route_of(radius, chunks, finish_y)
aq_ch = aquarium_checkpoint(chunks)
aq = aquarium(radius, aq_ch) if aq_ch else None
flat_ch = flat_checkpoint(chunks, aq_ch)
fl = flat(radius, flat_ch) if flat_ch else None

WATER, DEEP, ROUTE, THING = "#3f7f80", "#1d3a40", "#e8dfcf", "#1a262d"
COLOURS = {"S": "#d9d2c6", "P": "#f1c9a8", "R": "#e79aa0"}


def quad(origin, out, along, x0, x1, z0, z1):
    return [(origin[0] + out[0] * x + along[0] * z, origin[1] + out[1] * x + along[1] * z)
            for x, z in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))]


fig = plt.figure(figsize=(18, 10))
ax = fig.add_axes([0.02, 0.05, 0.5, 0.88])
sx = fig.add_axes([0.56, 0.55, 0.42, 0.38])
dx = fig.add_axes([0.56, 0.07, 0.42, 0.38])

# ===================================================================== from above
ax.set_facecolor(WATER)
# EVERY LOT, as the ground it stands on. Pale where anything on it may break the surface, darker
# where it stays under: that difference is the one rule the city is laid by.
for lot in city_lots(route):
    colour = "#7d8f88" if lot["emerges"] else "#5f7d78"
    half = K["BLOCK"] / 2
    away = lot["away"]
    along_dir = (-away[1], away[0])
    depth = lot["depth"]
    corners = []
    for dx_, dz_ in ((-depth / 2, -half), (depth / 2, -half), (depth / 2, half), (-depth / 2, half)):
        corners.append((lot["centre"][0] + away[0] * dx_ + along_dir[0] * dz_,
                        lot["centre"][1] + away[1] * dx_ + along_dir[1] * dz_))
    ax.add_patch(Polygon(corners, closed=True, color=colour, alpha=0.75, ec="#4c6b66", lw=0.3))

# The street itself, either side of the route.
for sign in (-1, 1):
    edge = []
    for step in range(81):
        at, direction = along_route(route, route["total"] * step / 80)
        side = (-direction[1], direction[0])
        edge.append((at[0] + side[0] * sign * K["BOULEVARD_HALF"], at[1] + side[1] * sign * K["BOULEVARD_HALF"]))
    ax.plot(*zip(*edge), color="#9cb8b2", ls="--", lw=0.8)

# The clock tower on its plaza, off the street about a third of the way along.
plaza_at, plaza_dir = along_route(route, route["total"] * 0.34)
plaza_side = (-plaza_dir[1], plaza_dir[0])
plaza = (plaza_at[0] + plaza_side[0] * M["PLAZA_OUT"], plaza_at[1] + plaza_side[1] * M["PLAZA_OUT"])
ax.add_patch(Circle(plaza, K["PLAZA_RADIUS"], color="#6f8f86", alpha=0.8))
side = M["CLOCK_SIDE"]
ax.add_patch(Polygon([(plaza[0] - side / 2, plaza[1] - side / 2), (plaza[0] + side / 2, plaza[1] - side / 2),
                      (plaza[0] + side / 2, plaza[1] + side / 2), (plaza[0] - side / 2, plaza[1] + side / 2)],
                     color="#c9c5b8"))
ax.text(plaza[0], plaza[1] - side, "clock tower", ha="center", color="#eef3f0", fontsize=8)

for ch in chunks:
    origin, out, tan = chunk_frame(radius, ch)
    reach = xmax(ch["id"])
    ax.add_patch(Polygon(quad(origin, out, tan, -reach, reach, 0, ch["length"]), closed=True,
                         color=COLOURS[ch["id"][0]], ec="#5a524a", lw=0.4))

# The thing's patrol: up the street and back, turning short of the harbour.
patrol = []
for step in range(81):
    at, _ = along_route(route, monster_span(route) * step / 80)
    patrol.append(at)
ax.plot(*zip(*patrol), color=THING, lw=2.2, ls=(0, (6, 4)))
mid = patrol[len(patrol) // 2]
ax.text(mid[0], mid[1] - 90, "the thing patrols the street,\nturning back before the harbour", ha="center",
        color="#e8f0ee", fontsize=8)

ax.add_patch(Polygon(quad(fin["finish"], fin["out"], fin["tan"], -K["PIER_W"] / 2, K["PIER_W"] / 2, 0, K["PIER_L"]),
                     color="#b8b4a8"))
ax.add_patch(Circle(vortex, K["VORTEX_R"] + 3, color="#d6e8e2"))
ax.add_patch(Circle(vortex, K["VORTEX_R"] * 0.6, color="#29545a"))
ax.text(vortex[0], vortex[1] + 60, "pier, whirlpool\nand the harbour", ha="center", color="#f0f5f3", fontsize=8)
if aq:
    ax.add_patch(Circle(aq["tower"], K["ROT_R"], color="#c9c5b8"))
    ax.plot([aq["tunnel"][0][0], aq["tunnel"][1][0]], [aq["tunnel"][0][1], aq["tunnel"][1][1]], color="#bfe6ea", lw=4)
    ax.add_patch(Polygon(quad(aq["at"](aq["room_x"]), aq["out"], aq["along"], -K["ROOM_L"] / 2, K["ROOM_L"] / 2,
                              -K["ROOM_W"] / 2, K["ROOM_W"] / 2), color="#a8a496"))
    ax.text(aq["far"][0], aq["far"][1] + 34, "aquarium", ha="center", color="#f0f5f3", fontsize=8)
if fl:
    ax.add_patch(Polygon(quad(fl["edge"], fl["out"], fl["along"], 0, fl["x"][1], -2, 2), color="#8a6a4a"))
    ax.add_patch(Polygon(quad(fl["edge"], fl["out"], fl["along"], fl["x"][0], fl["x"][1], fl["z"][0], fl["z"][1]),
                         color="#c4baa8", ec="#6b6259", lw=0.6))
    ax.text(fl["centre"][0], fl["centre"][1] + 34, "the dry flat\n(the mirror)", ha="center", color="#f0f5f3",
            fontsize=8)
xs = [p[0] for p in route["points"]] + [vortex[0]]
ys = [p[1] for p in route["points"]] + [vortex[1]]
span = max(max(xs) - min(xs), max(ys) - min(ys)) / 2 + K["CITY_SIDE"] * 0.55
cx, cy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
ax.set_xlim(cx - span, cx + span)
ax.set_ylim(cy - span, cy + span)
ax.set_aspect("equal")
ax.set_xticks([])
ax.set_yticks([])
ax.set_title("The Sunken City from above: %d chunks down a %.0f-stud street (seed %d). Pale blocks may break the "
             "surface; the ones on the kerb stay under it." % (len(chunks), route["total"], SEED), fontsize=9)


# ===================================================================== sections
def water_column(axis, left, right):
    axis.axhspan(h["floor"] - 20, h["floor"], color="#46584f")
    axis.axhspan(h["floor"], h["water"], color=WATER, alpha=0.55)
    axis.axhline(h["water"], color="#a9d0cc", lw=1.2)
    axis.axhline(kill, color="#c55", lw=0.8, ls="--")
    axis.text(left + 4, kill - 5, "kill plane", color="#ffb4b4", fontsize=7)
    axis.set_facecolor("#b9c8c6")
    axis.set_xlim(left, right)


def thing(axis, at):
    top = h["water"] - K["MONSTER_DEPTH"]
    axis.add_patch(Ellipse((at, top), K["MONSTER_GIRTH"] * 1.8, K["MONSTER_GIRTH"] * 1.5, color=THING))
    axis.text(at, top - 14, "the thing", ha="center", color="#e8f0ee", fontsize=7)


# Through the aquarium: outward from the middle, along the checkpoint's radial line.
water_column(sx, -110, 170)
if aq:
    landing = aq["landing_y"]
    base = 7.4
    sx.add_patch(plt.Rectangle((-10, landing - 4), 20, 4, color=COLOURS["S"]))
    sx.add_patch(plt.Rectangle((base, landing - K["NECK_THICK"]), K["AQ_NECK"], K["NECK_THICK"], color="#b8b4a8"))
    tower_x = base + aq["xc"]
    sx.add_patch(plt.Rectangle((tower_x - K["ROT_R"], h["floor"]), 2 * K["ROT_R"], landing + K["ROT_ROOF"] - h["floor"],
                               fill=False, ec="#d8d4c8", lw=2))
    turns = max(1, int((landing - h["tunnel"]) / 1.05))
    stair = [(tower_x + 6 * math.cos(i * math.radians(18)), landing - i * (landing - h["tunnel"]) / turns) for i in range(turns + 1)]
    sx.plot(*zip(*stair), color="#e8e2d4", lw=1)
    t0, t1 = base + aq["t0"], base + aq["t1"]
    sx.add_patch(plt.Rectangle((t0, h["tunnel"]), t1 - t0, K["TUNNEL_H"], color="#bfe6ea", alpha=0.75))
    for x in range(int(t0), int(t1) + 1, int(K["TUNNEL_BAY"])):
        sx.plot([x, x], [h["floor"], h["tunnel"]], color="#8b9690", lw=1)
    sx.add_patch(plt.Rectangle((t1, h["floor"]), K["ROOM_L"], h["water"] - 8 - h["floor"], color="#8f9a93"))
    sx.add_patch(plt.Rectangle((t1 + 1, h["tunnel"]), K["ROOM_L"] - 2, K["ROOM_H"], color="#e3dccb"))
    sx.text(t1 + K["ROOM_L"] / 2, h["tunnel"] + 4, "gallery", ha="center", fontsize=7)
    sx.text(tower_x, landing + K["ROT_ROOF"] + 4, "door, stair down", ha="center", fontsize=7)
thing(sx, 0)
sx.add_patch(plt.Rectangle((-19, h["water"] - 11.2), 22, 6, color="#2f7e5a"))
sx.text(-8, h["water"] - 16, "road sign", ha="center", fontsize=6, color="#e0f0e8")
sx.set_ylim(h["floor"] - 20, h["water"] + 45)
sx.set_title("Section across the street at the aquarium: route, landing, stair tower, tunnel, gallery", fontsize=9)

# Through the pier and the drain, along the route's end.
water_column(dx, -40, K["PIER_L"] + K["VORTEX_GAP"] + 60)
pier_top = fin["pier_top"]
dx.add_patch(plt.Rectangle((-20, pier_top - 4), 20, 4, color=COLOURS["S"]))
dx.add_patch(plt.Rectangle((0, pier_top - 2.5), K["PIER_L"], 2.5, color="#b8b4a8"))
for z in (3, K["PIER_L"] / 2 - 2, K["PIER_L"] - 8):
    dx.plot([z, z], [h["floor"], pier_top - 2.5], color="#8b9690", lw=2)
v = K["PIER_L"] + K["VORTEX_GAP"]
funnel = [(v - K["VORTEX_R"], h["water"]), (v - 1.5, h["water"] - K["FUNNEL_DEPTH"]), (v + 1.5, h["water"] - K["FUNNEL_DEPTH"]),
          (v + K["VORTEX_R"], h["water"])]
dx.add_patch(Polygon(funnel, color="#d6e8e2", alpha=0.8))
dx.add_patch(plt.Rectangle((v - 2.5, h["floor"]), 5, h["water"] - K["FUNNEL_DEPTH"] - h["floor"], color=DEEP, alpha=0.8))
dx.add_patch(plt.Rectangle((v - K["DRAIN_R"] - 1, h["shaft"]), 2 * K["DRAIN_R"] + 2, h["floor"] - h["shaft"], color="#0b0e10"))
dx.text(v, h["shaft"] + 8, "the shaft: the\nrun ends here", ha="center", color="#dfe8e6", fontsize=7)
dx.annotate("step off the end", xy=(v - 6, h["water"] + 2), xytext=(K["PIER_L"] - 18, pier_top + 18), fontsize=8,
            arrowprops=dict(arrowstyle="->", color="#333"))
dx.set_ylim(h["shaft"] - 10, pier_top + 30)
dx.set_title("Section through the pier and the drain: the whirlpool pulls you round, down the current, into the dark",
             fontsize=9)

out_path = pathlib.Path(__file__).with_name("sunkencity_plan.png")
fig.savefig(out_path, dpi=85)
print("wrote %s | street %.0f studs, water %.0f, floor %.0f, kill %.0f, tunnel %.0f, shaft %.0f"
      % (out_path, route["total"], h["water"], h["floor"], kill, h["tunnel"], h["shaft"]))
