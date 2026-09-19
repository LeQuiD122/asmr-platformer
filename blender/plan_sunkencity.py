"""Level 3, The Sunken City, as built: from above, and in section through the aquarium and the drain.

Run with plain Python from the project root:  python blender/plan_sunkencity.py [seed]

Laid by sunkencity_layout.py, the same Python check_sunkencity.py tests. The lots themselves are
drawn as their bands only: SunkenCityService fills them from Roblox's random numbers, which Python
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
from sunkencity_layout import (K, LEVEL, M, aquarium, aquarium_checkpoint, bands, finale, flat, flat_checkpoint,  # noqa: E402
                               heights, monster_radius)

SEED = int(sys.argv[1]) if len(sys.argv) > 1 else 0
COUNT = dict(LEVEL.runs)["medium"]
radius, chunks, finish_y = LEVEL.lay(COUNT, SEED)
h = heights(chunks)
kill = min(ch["y"] for ch in chunks) - 40
fin = finale(radius, chunks, finish_y)
vortex = fin["vortex"]
harbour = math.atan2(vortex[1], vortex[0])
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
# Outermost first: each band is a disc with the water painted back inside it, so a band drawn after a
# wider one would be erased by that one's water.
for start, end, kind in reversed(bands(radius)):
    emerge = start - (radius + K["ROUTE_REACH"]) >= K["EMERGE_CLEAR"] or (radius - K["ROUTE_REACH"]) - end >= K["EMERGE_CLEAR"]
    colour = "#6f8f86" if kind in ("nearInner", "nearOuter") else ("#7d8f88" if emerge else "#5f7d78")
    ax.add_patch(Circle((0, 0), end, color=colour, alpha=0.55))
    ax.add_patch(Circle((0, 0), start, color=WATER))
ax.add_patch(Circle((0, 0), radius + K["BOULEVARD_HALF"], fill=False, ec="#9cb8b2", ls="--", lw=0.8))
ax.add_patch(Circle((0, 0), radius - K["BOULEVARD_HALF"], fill=False, ec="#9cb8b2", ls="--", lw=0.8))
outer_edge = radius + K["BOULEVARD_HALF"] + K["STREET"] / 2 + K["OUTER_BANDS"] * (K["OUTER_BAND"] + K["STREET"])
ax.add_patch(Wedge((0, 0), outer_edge + 10, math.degrees(harbour - K["HARBOUR_SECTOR_HALF"]),
                   math.degrees(harbour + K["HARBOUR_SECTOR_HALF"]), width=outer_edge - radius - K["BOULEVARD_HALF"],
                   color=WATER))
ax.text(math.cos(harbour) * (radius + 260), math.sin(harbour) * (radius + 260), "the harbour", ha="center", color="#dfeeea",
        fontsize=9)
side = M["CLOCK_SIDE"]
ax.add_patch(Polygon([(-side / 2, -side / 2), (side / 2, -side / 2), (side / 2, side / 2), (-side / 2, side / 2)],
                     color="#c9c5b8"))
ax.text(0, -32, "clock tower", ha="center", color="#eef3f0", fontsize=8)
for ch in chunks:
    origin, out, tan = chunk_frame(radius, ch)
    reach = xmax(ch["id"])
    ax.add_patch(Polygon(quad(origin, out, tan, -reach, reach, 0, ch["length"]), closed=True, color=COLOURS[ch["id"][0]],
                         ec="#5a524a", lw=0.4))
path = []
for step in range(361):
    theta = step / 360 * 2 * math.pi
    r = monster_radius(radius, theta, harbour)
    path.append((math.cos(theta) * r, math.sin(theta) * r))
ax.plot(*zip(*path), color=THING, lw=2.2, ls=(0, (6, 4)))
ax.text(path[90][0] * 0.82, path[90][1] * 0.82, "the thing's round,\nagainst the route", ha="center", color="#e8f0ee", fontsize=8)
ax.add_patch(Polygon(quad(fin["finish"], fin["out"], fin["tan"], -K["PIER_W"] / 2, K["PIER_W"] / 2, 0, K["PIER_L"]),
                     color="#b8b4a8"))
ax.add_patch(Circle(vortex, K["VORTEX_R"] + 3, color="#d6e8e2"))
ax.add_patch(Circle(vortex, K["VORTEX_R"] * 0.6, color="#29545a"))
ax.text(vortex[0] * 1.18, vortex[1] * 1.18, "pier and\nwhirlpool", ha="center", color="#f0f5f3", fontsize=8)
if aq:
    ax.add_patch(Circle(aq["tower"], K["ROT_R"], color="#c9c5b8"))
    ax.plot([aq["tunnel"][0][0], aq["tunnel"][1][0]], [aq["tunnel"][0][1], aq["tunnel"][1][1]], color="#bfe6ea", lw=4)
    ax.add_patch(Polygon(quad(aq["at"](aq["room_x"]), aq["out"], aq["along"], -K["ROOM_L"] / 2, K["ROOM_L"] / 2,
                              -K["ROOM_W"] / 2, K["ROOM_W"] / 2), color="#a8a496"))
    ax.text(aq["far"][0] * 1.12, aq["far"][1] * 1.12, "aquarium", ha="center", color="#f0f5f3", fontsize=8)
if fl:
    ax.add_patch(Polygon(quad(fl["edge"], fl["out"], fl["along"], 0, fl["x"][1], -2, 2), color="#8a6a4a"))
    ax.add_patch(Polygon(quad(fl["edge"], fl["out"], fl["along"], fl["x"][0], fl["x"][1], fl["z"][0], fl["z"][1]),
                         color="#c4baa8", ec="#6b6259", lw=0.6))
    ax.text(fl["centre"][0] * 1.16, fl["centre"][1] * 1.16, "the dry flat\n(the mirror)", ha="center", color="#f0f5f3",
            fontsize=8)
view = outer_edge + 40
ax.set_xlim(-view, view)
ax.set_ylim(-view, view)
ax.set_aspect("equal")
ax.set_xticks([])
ax.set_yticks([])
ax.set_title("The Sunken City from above: %d chunks round a %.0f-stud ring (seed %d). Pale bands may break the "
             "surface; the bands by the boulevard stay under it." % (len(chunks), radius, SEED), fontsize=9)


# ===================================================================== sections
def water_column(axis, left, right):
    axis.axhspan(h["floor"] - 20, h["floor"], color="#46584f")
    axis.axhspan(h["floor"], h["water"], color=WATER, alpha=0.55)
    axis.axhspan(h["floor"], h["murk"], color=DEEP, alpha=0.45)
    axis.axhline(h["water"], color="#a9d0cc", lw=1.2)
    axis.axhline(kill, color="#c55", lw=0.8, ls="--")
    axis.text(left + 4, kill - 5, "kill plane", color="#ffb4b4", fontsize=7)
    axis.text(left + 4, h["murk"] - 6, "murk", color="#9fb6b2", fontsize=7)
    axis.set_facecolor("#b9c8c6")
    axis.set_xlim(left, right)


def thing(axis, at):
    top = h["water"] - K["MONSTER_DEPTH"]
    axis.add_patch(Ellipse((at, top), K["MONSTER_GIRTH"] * 1.8, K["MONSTER_GIRTH"] * 1.5, color=THING))
    axis.text(at, top - 14, "the thing", ha="center", color="#e8f0ee", fontsize=7)


# Through the aquarium: outward from the middle, along the checkpoint's radial line.
water_column(sx, radius - 110, radius + 170)
if aq:
    landing = aq["landing_y"]
    base = radius + 7.4
    sx.add_patch(plt.Rectangle((radius - 10, landing - 4), 20, 4, color=COLOURS["S"]))
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
thing(sx, radius - K["MONSTER_INSET"])
sx.add_patch(plt.Rectangle((radius - 19, h["water"] - 11.2), 22, 6, color="#2f7e5a"))
sx.text(radius - 8, h["water"] - 16, "road sign", ha="center", fontsize=6, color="#e0f0e8")
sx.set_ylim(h["floor"] - 20, h["water"] + 45)
sx.set_title("Section through the aquarium: route, landing, stair tower, tunnel on pillars, gallery", fontsize=9)

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
print("wrote %s | ring %.0f, water %.0f, floor %.0f, kill %.0f, tunnel %.0f, shaft %.0f"
      % (out_path, radius, h["water"], h["floor"], kill, h["tunnel"], h["shaft"]))
