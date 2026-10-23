"""Hill House from above (the hundred-and-eleventh pass): python blender/plan_hillhouse.py writes blender/plan_hillhouse.png.

Drawn from HillHouseService's own numbers, for a route end on the spiral's circle heading round it: the route's circle
and the widest chunk's band either side of it, the landing, the footbridge, the crag and its fence, the house, the
apple tree and the bench, and which way is out to sea.
"""
import math
import pathlib
import re

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Circle, Polygon  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
SRC = HERE.parent / "src"
HOUSE = (SRC / "Server" / "Services" / "HillHouseService.lua").read_text(encoding="utf-8")
LEVEL_SERVICE = (SRC / "Server" / "Services" / "LevelService.lua").read_text(encoding="utf-8")
OUT = HERE / "plan_hillhouse.png"


def num(text, name):
    return float(re.search(r"^local %s = (-?[\d.]+)" % name, text, re.M).group(1))


route_r = num(LEVEL_SERVICE, "SPIRAL_RADIUS")
crag_r, clear, ahead = num(HOUSE, "CRAG_R"), num(HOUSE, "CLEAR"), num(HOUSE, "AHEAD")
w, d = (float(v) for v in re.search(r"^local HOUSE_W, HOUSE_D, STOREY, ROOF_H = ([\d.]+), ([\d.]+),", HOUSE, re.M).groups())
lx, _, lz = (float(v) for v in re.search(r"^local LANDING = Vector3\.new\(([\d.]+), ([\d.]+), ([\d.]+)\)", HOUSE, re.M).groups())

# The route ends at (route_r, 0), heading +y (round the circle); out is +x.
P = (route_r, 0.0)
C = (route_r + clear + crag_r + 8, ahead)
land_mid = (route_r, lz / 2)

fig, ax = plt.subplots(figsize=(10, 10))
ax.set_facecolor("#efe6dc")
ax.add_patch(Circle((0, 0), route_r + 11, color="#d8cfc4", zorder=1))
ax.add_patch(Circle((0, 0), route_r - 11, color="#efe6dc", zorder=1.1))
ax.add_patch(Circle((0, 0), route_r, fill=False, ls="--", color="#8a7f73", zorder=2))
ax.text(0, 0, "the route's centre\n(the spiral goes round,\nclimbing, at radius %d)" % route_r, ha="center", va="center", fontsize=9)
ax.add_patch(Circle(C, crag_r, color="#7fa26f", zorder=3))
ax.add_patch(Circle(C, crag_r - 1.5, fill=False, color="white", lw=2, zorder=4))
ax.text(C[0], C[1] + crag_r + 3, "the crag's top, fence round it", ha="center", fontsize=9)
# Landing and bridge.
ax.add_patch(Polygon([(P[0] - lx / 2, 0), (P[0] + lx / 2, 0), (P[0] + lx / 2, lz), (P[0] - lx / 2, lz)], color="#b8b0a0", zorder=5))
tx, ty = C[0] - land_mid[0], C[1] - land_mid[1]
m = math.hypot(tx, ty)
ux, uy = tx / m, ty / m
start = (land_mid[0] + ux * (min(lx, lz) / 2 - 0.5), land_mid[1] + uy * (min(lx, lz) / 2 - 0.5))
end = (C[0] - ux * (crag_r - 3), C[1] - uy * (crag_r - 3))
px, py = -uy * 3, ux * 3
ax.add_patch(Polygon([(start[0] + px, start[1] + py), (end[0] + px, end[1] + py), (end[0] - px, end[1] - py),
                      (start[0] - px, start[1] - py)], color="#7a5c42", zorder=6))
ax.text((start[0] + end[0]) / 2, (start[1] + end[1]) / 2 - 7, "footbridge %.0f studs" % math.hypot(end[0] - start[0], end[1] - start[1]),
        ha="center", fontsize=8)
# The house: front four past the middle, facing the gate.
ix, iy = -ux, -uy  # inward from the gate is toward the far side: from end toward C
ix, iy = ux, uy
ax_x, ax_y = -iy, ix
f = (C[0] + ix * 4, C[1] + iy * 4)
corners = []
for a, b in ((-w / 2, 0), (w / 2, 0), (w / 2, d), (-w / 2, d)):
    corners.append((f[0] + ax_x * a + ix * b, f[1] + ax_y * a + iy * b))
ax.add_patch(Polygon(corners, color="#ece4d6", ec="#4a5060", lw=2, zorder=7))
ax.text(f[0] + ix * d / 2, f[1] + iy * d / 2, "Hill House", ha="center", va="center", fontsize=10, zorder=8)
tree = (C[0] - ax_x * 20 + ix * 2, C[1] - ax_y * 20 + iy * 2)
ax.add_patch(Circle(tree, 4, color="#5c8c50", zorder=7))
ax.text(tree[0], tree[1], "apple", ha="center", va="center", fontsize=7, zorder=8, color="white")
benchp = (C[0] + ax_x * 22 - ix * 4, C[1] + ax_y * 22 - iy * 4)
ax.add_patch(Circle(benchp, 1.6, color="#7a5c42", zorder=7))
ax.text(benchp[0], benchp[1] - 4, "bench", ha="center", fontsize=7)
# Who is up here (the hundred-and-thirteenth pass): Mr Gale on the landing away from the bridge's side, Mrs Dunn inside
# the gate beside the path.
side_in, end_in = (float(v) for v in re.search(r"away \* \(LANDING\.X / 2 - ([\d.]+)\), LANDING\.Y / 2, -\(LANDING\.Z / 2 - ([\d.]+)\)",
                                               HOUSE).groups())
d_in, d_across = (float(v) for v in re.search(r"local stand = gate \+ inward \* ([\d.]+) \+ across \* ([\d.]+)", HOUSE).groups())
gale = (P[0] - (lx / 2 - side_in), lz / 2 + (lz / 2 - end_in))
dunn = (end[0] + ix * d_in + ax_x * d_across, end[1] + iy * d_in + ax_y * d_across)
for (px_, py_), who in ((gale, "Mr Gale"), (dunn, "Mrs Dunn")):
    ax.add_patch(Circle((px_, py_), 1.0, color="#2f3d63", zorder=9))
    ax.text(px_ - 2, py_, who, ha="right", va="center", fontsize=7, zorder=9)
ax.annotate("out to sea, over the mist", xy=(C[0] + crag_r + 30, 0), xytext=(C[0] + crag_r - 10, -40),
            arrowprops=dict(arrowstyle="->"), fontsize=9)
ax.plot([P[0]], [P[1]], "ko")
ax.text(P[0] + 2, P[1] - 5, "the route's end", fontsize=8)
ax.set_xlim(-route_r - 20, C[0] + crag_r + 40)
ax.set_ylim(-route_r - 20, route_r + 40)
ax.set_aspect("equal")
ax.set_title("Hill House from above, from HillHouseService.lua: clear of the route by %d studs" % clear)
fig.savefig(OUT, dpi=90, bbox_inches="tight")
print("wrote", OUT)
