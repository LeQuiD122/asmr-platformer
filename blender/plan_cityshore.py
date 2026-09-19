"""City Shore's new backdrop in plan, from BackdropService's own numbers: the crescent of land, the
beach, the promenade, the hotel row, the towers, the parks, the aquapark in the bay, the dive's
landing circle and the sun. Placement repeats the service's rules; the random draws differ."""
import math
import pathlib
import random
import re

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Wedge, Polygon

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = (ROOT / "src" / "Server" / "Services" / "BackdropService.lua").read_text(encoding="utf-8")


def num(name):
    return float(re.search(r"^local %s = ([\d.]+)" % name, SRC, re.M).group(1))


def rad(name):
    return math.radians(float(re.search(r"^local %s = math.rad\(([\d.]+)\)" % name, SRC, re.M).group(1)))


SHORE_NEAR, LAND_FAR, LAND_TOP = num("SHORE_NEAR"), num("LAND_FAR"), num("LAND_TOP")
CITY_HALF = rad("CITY_HALF")
BEACH_WET, BEACH_DRY = [float(x) for x in re.search(r"local BEACH_WET, BEACH_DRY = (\d+), (\d+)", SRC).groups()]
PROMENADE = num("PROMENADE")
SPIRAL = 90
CIRCLE_OUT, CIRCLE_R = 324, 300

rng = random.Random(7)
SUN = 0.0  # the sun's bearing; the city faces away from it
CITY = SUN + math.pi


def from_city(angle):
    return (angle - CITY + math.pi) % (2 * math.pi) - math.pi


def shore_at(offset):
    return SHORE_NEAR if abs(offset) <= CITY_HALF else None


occupied = []


def clear_of(x, z, margin):
    return all((x - ox) ** 2 + (z - oz) ** 2 >= (r + margin) ** 2 for ox, oz, r in occupied)


def on_land(x, z, behind):
    s = shore_at(from_city(math.atan2(z, x)))
    return s is not None and math.hypot(x, z) >= s + behind


def land_spot(near, far, behind, margin, tries):
    for _ in range(tries):
        a = CITY + rng.uniform(-CITY_HALF, CITY_HALF)
        out = math.sqrt(rng.random()) * (far - near) + near
        x, z = math.cos(a) * out, math.sin(a) * out
        if on_land(x, z, behind) and clear_of(x, z, margin):
            return x, z
    return None


def water_spot(near, far, margin, tries, sea_only=False):
    for _ in range(tries):
        a = rng.uniform(0, 2 * math.pi)
        out = math.sqrt(rng.random()) * (far - near) + near
        s = shore_at(from_city(a))
        wet = (s is None) if sea_only else (s is None or out < s - BEACH_WET * 0.5 - margin * 0.5)
        if wet:
            x, z = math.cos(a) * out, math.sin(a) * out
            if clear_of(x, z, margin):
                return x, z
    return None


fig, axes = plt.subplots(1, 2, figsize=(17, 8.6), gridspec_kw={"width_ratios": [1.15, 1]})
ax = axes[0]
ax.set_facecolor("#2e6a92")
ax.add_patch(Circle((0, 0), 6200, color="#2e6a92"))

# the land, slice by slice, as the service builds it
step = math.radians(4)
for i in range(int(CITY_HALF * 2 / step) + 1):
    off = -CITY_HALF + i * step
    s = shore_at(off)
    if s is None:
        continue
    a0, a1 = CITY + off - step / 2, CITY + off + step / 2

    def band(r0, r1, colour):
        pts = [(math.cos(a) * r0, math.sin(a) * r0) for a in (a0, a1)] + \
              [(math.cos(a) * r1, math.sin(a) * r1) for a in (a1, a0)]
        ax.add_patch(Polygon(pts, closed=True, color=colour, lw=0))
    band(s - BEACH_WET, s + BEACH_DRY, "#f0dab2")
    band(s + BEACH_DRY, s + BEACH_DRY + PROMENADE, "#f2eadc")
    band(s + BEACH_DRY + PROMENADE, LAND_FAR, "#d6cec2")

# the harbour walls at the ends
for side in (-1, 1):
    a = CITY + side * (CITY_HALF + math.radians(2))
    ax.plot([math.cos(a) * (SHORE_NEAR - BEACH_WET), math.cos(a) * LAND_FAR],
            [math.sin(a) * (SHORE_NEAR - BEACH_WET), math.sin(a) * LAND_FAR], color="#e4ded4", lw=4)

# parks
for _ in range(12):
    w = rng.uniform(220, 460)
    spot = land_spot(1700, 4600, 480, w * 0.6, 40)
    if spot:
        ax.add_patch(Circle(spot, w / 2, color="#96be8e"))
        occupied.append((*spot, w * 0.5))

# hotels
DECO = ["#f4b0a4", "#a8dcc8", "#a6cee8", "#f6e2a0", "#ccbae6", "#facca9", "#f6f2ea"]
edge = CITY_HALF - math.radians(4)
off = -edge
hotels = 0
while off <= edge:
    s = shore_at(off)
    if s:
        width, depth = rng.uniform(150, 240), rng.uniform(110, 170)
        reach = s + BEACH_DRY + PROMENADE + 50 + depth / 2 + rng.uniform(0, 60)
        a = CITY + off + rng.uniform(-0.012, 0.012)
        x, z = math.cos(a) * reach, math.sin(a) * reach
        if clear_of(x, z, width * 0.5):
            # a rectangle facing the middle
            tx, tz = -math.sin(a), math.cos(a)
            rx, rz = math.cos(a), math.sin(a)
            pts = [(x + tx * sx * width / 2 + rx * sz * depth / 2, z + tz * sx * width / 2 + rz * sz * depth / 2)
                   for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            ax.add_patch(Polygon(pts, closed=True, color=rng.choice(DECO), ec="#8a7f74", lw=0.4))
            occupied.append((x, z, width * 0.6))
            hotels += 1
    off += math.radians(5.8) * rng.uniform(0.85, 1.15)

# towers, three bands
towers = 0
for count, near, far, wl, wh in ((14, 1500, 2500, 110, 190), (20, 2500, 3800, 150, 260), (22, 3800, 5500, 190, 340)):
    for _ in range(count):
        w = rng.uniform(wl, wh)
        spot = land_spot(near, far, 480, w * 0.8, 60)
        if spot:
            glass = rng.random() < 0.34
            ax.add_patch(Circle(spot, w * 0.5, color="#42687c" if glass else rng.choice(DECO), ec="#5a5048", lw=0.4))
            occupied.append((*spot, w * 0.72))
            towers += 1

# facades
for _ in range(9):
    w = rng.uniform(480, 900)
    spot = land_spot(1700, 3200, 520, w * 0.6, 40)
    if spot:
        a = math.atan2(spot[1], spot[0])
        tx, tz = -math.sin(a) * w / 2, math.cos(a) * w / 2
        ax.plot([spot[0] - tx, spot[0] + tx], [spot[1] - tz, spot[1] + tz], color="#9a8e84", lw=3)
        occupied.append((*spot, w * 0.55))

# the dive's landing circle, at one bearing the route might end on
end = math.radians(200)
cx, cz = math.cos(end) * (SPIRAL + CIRCLE_OUT), math.sin(end) * (SPIRAL + CIRCLE_OUT)
ax.add_patch(Circle((cx, cz), CIRCLE_R, fill=False, ec="#ffffff", lw=1.2, ls="--"))
ax.text(cx, cz, "dive lands\nin here", color="white", fontsize=7, ha="center", va="center")

# aquapark ring, and a few props
ax.add_patch(Circle((0, 0), 800, fill=False, ec="#bfe6f0", lw=0.8, ls=":"))
ax.add_patch(Circle((0, 0), 1080, fill=False, ec="#bfe6f0", lw=0.8, ls=":"))
placed = 0
for _ in range(14):
    r = rng.uniform(60, 160)
    spot = water_spot(800, 1080, r, 40)
    if spot:
        ax.add_patch(Circle(spot, r, color="#e8f2f6", alpha=0.9))
        occupied.append((*spot, r))
        placed += 1

# the level and the sun
ax.add_patch(Circle((0, 0), SPIRAL + 14, color="#ffe9a8"))
ax.text(0, 0, "level", fontsize=7, ha="center", va="center")
ax.annotate("", xy=(5600 * math.cos(SUN), 5600 * math.sin(SUN)), xytext=(4200 * math.cos(SUN), 4200 * math.sin(SUN)),
            arrowprops=dict(arrowstyle="->", color="#ffcf6e", lw=2.5))
ax.text(5000 * math.cos(SUN), 5000 * math.sin(SUN) + 260, "low sun", color="#ffcf6e", ha="center", fontsize=9)
ax.text(-3800, 0, "the city", color="#3e342e", fontsize=12, ha="center", rotation=90)
ax.text(3000, -2400, "open sea:\nsandbars, giant objects,\nthe glitter", color="#e8f2f6", fontsize=9, ha="center")
ax.set_xlim(-6300, 6300)
ax.set_ylim(-6300, 6300)
ax.set_aspect("equal")
ax.set_title("City Shore from above: %d hotels, %d towers, aquapark ring 800-1080" % (hotels, towers))
ax.set_xticks([])
ax.set_yticks([])

# section, looking at the city from the level
bx = axes[1]
bx.set_facecolor("#a8c8ec")
bx.fill_between([-200, 6200], -800, 0, color="#2e6a92")
xs = [0, SHORE_NEAR - BEACH_WET, SHORE_NEAR + BEACH_DRY, SHORE_NEAR + BEACH_DRY + PROMENADE, 6000]
ys = [-40, -40, LAND_TOP, LAND_TOP + 2, LAND_TOP]
bx.fill_between([SHORE_NEAR - BEACH_WET, SHORE_NEAR + BEACH_DRY], [-40, LAND_TOP], -120, color="#f0dab2")
bx.fill_between([SHORE_NEAR + BEACH_DRY, 6000], LAND_TOP, -120, color="#d6cec2")
hx = SHORE_NEAR + BEACH_DRY + PROMENADE + 50
for i in range(3):
    h = [240, 320, 180][i]
    bx.add_patch(plt.Rectangle((hx + i * 20, LAND_TOP), 150, h, color=DECO[i], ec="#8a7f74"))
    bx.add_patch(plt.Rectangle((hx + i * 20 + 50, LAND_TOP), 30, h * 1.4, color="#fcfaf4", ec="#8a7f74"))
tr = random.Random(3)
for x in range(1650, 5500, 180):
    h = 700 + (x - 1500) / 4000 * 2300 * tr.uniform(0.6, 1.0)
    bx.add_patch(plt.Rectangle((x, LAND_TOP), tr.uniform(100, 220), h, color=tr.choice(DECO + ["#42687c"]), alpha=0.85))
bx.axhline(700, color="#c0392b", lw=1, ls="--")
bx.text(200, 730, "you, on the spiral (700 up)", color="#c0392b", fontsize=9)
bx.plot([SPIRAL, SPIRAL], [0, 700], color="#8a6d3b", lw=3)
bx.text(SHORE_NEAR, -300, "beach", ha="center", fontsize=8)
bx.text(hx + 80, -300, "promenade\n+ hotels", ha="center", fontsize=8)
bx.text(3500, -300, "towers, taller going back", ha="center", fontsize=8)
bx.set_xlim(-200, 6200)
bx.set_ylim(-800, 3400)
bx.set_title("Section, level to the city (studs; sea level 0)")
fig.tight_layout()
out = pathlib.Path(__file__).with_name("cityshore_plan.png")
fig.savefig(out, dpi=90)
print("wrote", out, "| hotels", hotels, "towers", towers, "aquapark props", placed)
