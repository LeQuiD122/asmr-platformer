"""The treasure chest past the aquarium's window: what every aquarium has, made properly.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_treasure.py
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_treasure.py -- render

Writes meshes/Treasure_Wood, Treasure_Iron, Treasure_Gold, Treasure_Gems and Treasure_Pearls (.fbx),
and adds their boxes to blender/sealife_extents.json (run it after gen_sealife.py). Import all five
into ReplicatedStorage/Assets/TileMeshes. SunkenCityService sets them on the chest's rock; without
them it builds the old chest of parts.

It was a box, two bands, a squashed gold egg and a slab for a lid. This is a sea chest: planked walls
and a barrel lid thrown open on its hinges, iron bands, corner brackets, rivets, a lock plate with
the hasp hanging off it and a handle each end; a heap of coins inside, more spilling over the front
onto the rock, a goblet and a crown on the heap, rubies, and a string of pearls over the edge.

    PIVOT   The five meshes share one box, centred on the middle of the chest's BASE, so the server
            puts them at the top of the rock and the chest sits on it. The front (the lock) faces
            Blender +Y, which arrives as Roblox -Z: the part's LookVector.
"""

import json
import math
import os
import random
import sys

import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sealife as G  # noqa: E402

W, D, H = 5.4, 3.6, 2.6      # the body: wide (x), deep (y), tall (z)
LID_OPEN = math.radians(112)  # how far the lid is thrown back


def cuboid(bm, centre, size, m=None):
    t = Matrix.Translation(Vector(centre)) @ (m or Matrix.Identity(4)) @ Matrix.Diagonal((size[0], size[1], size[2], 1.0))
    made = bmesh.ops.create_cube(bm, size=1.0, matrix=t)
    flat = G.flat_layer(bm)
    for f in {f for v in made["verts"] for f in v.link_faces}:
        f[flat] = 1


def disc(bm, centre, radius, thick, tilt, sides=8):
    """A coin."""
    t = Matrix.Translation(Vector(centre)) @ tilt
    ring_top, ring_bot = [], []
    for k in range(sides):
        a = 2 * math.pi * k / sides
        p = Vector((radius * math.cos(a), radius * math.sin(a), 0))
        ring_top.append(bm.verts.new(t @ (p + Vector((0, 0, thick / 2)))))
        ring_bot.append(bm.verts.new(t @ (p - Vector((0, 0, thick / 2)))))
    bm.faces.new(ring_top)
    bm.faces.new(list(reversed(ring_bot)))
    for k in range(sides):
        bm.faces.new((ring_top[k], ring_bot[k], ring_bot[(k + 1) % sides], ring_top[(k + 1) % sides]))


def ball(bm, centre, radius):
    made = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=radius,
                                      matrix=Matrix.Translation(Vector(centre)))
    return made


def gem(bm, centre, size):
    """A cut stone: an octahedron, a little long."""
    c = Vector(centre)
    pts = [c + Vector(p) for p in ((size, 0, 0), (-size, 0, 0), (0, size, 0), (0, -size, 0), (0, 0, size * 1.3),
                                   (0, 0, -size * 1.3))]
    v = [bm.verts.new(p) for p in pts]
    for a, b in ((0, 2), (2, 1), (1, 3), (3, 0)):
        bm.faces.new((v[a], v[b], v[4]))
        bm.faces.new((v[b], v[a], v[5]))
    flat = G.flat_layer(bm)
    for f in bm.faces:
        f[flat] = 1


def heap_height(x, y):
    """The top of the coin heap inside: domed, highest a little behind the middle, over the rim."""
    u, v = x / (W / 2 - 0.3), (y + 0.2) / (D / 2 - 0.3)
    r = min(1.0, math.hypot(u, v))
    return 1.0 + (H + 0.3 - 1.0) * (1 - r * r) ** 0.45


def lid_frame():
    """The lid's transform: hinged along the back top edge, thrown back LID_OPEN."""
    hinge = Vector((0, -D / 2, H))
    return Matrix.Translation(hinge) @ Matrix.Rotation(-LID_OPEN, 4, "X") @ Matrix.Translation(-hinge)


def build():
    rnd = random.Random(11)
    wood, iron, gold, gems, pearls = (bmesh.new() for _ in range(5))

    # WOOD: a floor, four walls of planks, the inner floor the gold lies on, and the barrel lid.
    cuboid(wood, (0, 0, 0.15), (W, D, 0.3))
    for k in range(4):
        z = 0.3 + 0.075 + k * 0.575 + 0.29
        for side in (-1, 1):
            cuboid(wood, (0, side * (D / 2 - 0.12), z), (W - 0.02, 0.24 + rnd.uniform(-0.03, 0.03), 0.55))
            cuboid(wood, (side * (W / 2 - 0.12), 0, z), (0.24 + rnd.uniform(-0.03, 0.03), D - 0.5, 0.55))
    cuboid(wood, (0, 0, 1.0), (W - 0.5, D - 0.5, 0.12))
    lid = lid_frame()
    staves = 7
    r = D / 2
    for k in range(staves):
        a = math.pi * (k + 0.5) / staves
        y, z = -r * math.cos(a), H + r * math.sin(a)
        m = lid @ Matrix.Translation(Vector((0, y, z))) @ Matrix.Rotation(math.pi / 2 - a, 4, "X")
        cuboid(wood, (0, 0, 0), (W - 0.04, math.pi * r / staves + 0.02, 0.2), m)
    for side in (-1, 1):
        pts = [(side * (W / 2 - 0.1), -r * math.cos(math.pi * k / 10), H + r * math.sin(math.pi * k / 10)) for k in range(11)]
        pts = [tuple(lid @ Vector(p)) for p in pts]
        G.plate(wood, pts, tuple(lid.to_3x3() @ Vector((1, 0, 0))), 0.2)

    # IRON: bands round the body and over the lid, corner brackets, rivets, the lock and its hasp,
    # and a handle at each end.
    for x in (-1.75, 1.75):
        for side in (-1, 1):
            cuboid(iron, (x, side * (D / 2 + 0.03), H / 2 + 0.1), (0.34, 0.06, H - 0.1))
        cuboid(iron, (x, 0, 0.02), (0.34, D + 0.1, 0.06))
        for k in range(12):
            a = math.pi * (k + 0.5) / 12
            y, z = -(r + 0.12) * math.cos(a), H + (r + 0.12) * math.sin(a)
            m = lid @ Matrix.Translation(Vector((x, y, z))) @ Matrix.Rotation(math.pi / 2 - a, 4, "X")
            cuboid(iron, (0, 0, 0), (0.34, math.pi * (r + 0.12) / 12 + 0.02, 0.06), m)
        for side in (-1, 1):
            for z in (0.5, 1.3, 2.1):
                cuboid(iron, (x, side * (D / 2 + 0.08), z), (0.12, 0.08, 0.12))
    for sx in (-1, 1):
        for sy in (-1, 1):
            for z in (0.35, H - 0.2):
                cuboid(iron, (sx * (W / 2 - 0.02), sy * (D / 2 - 0.3), z), (0.08, 0.7, 0.45))
                cuboid(iron, (sx * (W / 2 - 0.3), sy * (D / 2 + 0.02), z), (0.7, 0.08, 0.45))
    cuboid(iron, (0, D / 2 + 0.06, H - 0.55), (0.9, 0.08, 0.9))
    # The hasp, torn from the lid and hanging off the plate.
    cuboid(iron, (0, D / 2 + 0.12, H - 1.05), (0.28, 0.06, 0.8), Matrix.Rotation(0.2, 4, "Y"))
    for side in (-1, 1):
        cx = side * (W / 2 + 0.25)
        for k in range(10):
            a = math.pi * k / 9
            y, z = 0.55 * math.cos(a), 1.55 - 0.55 * math.sin(a) * 0.7
            cuboid(iron, (cx, y, z), (0.12, 0.2, 0.12))
        cuboid(iron, (side * (W / 2 + 0.06), 0, 1.55), (0.12, 1.3, 0.3))

    # GOLD: the heap inside and coins on it, more spilling over the front onto the rock, a goblet and
    # a crown.
    stations = []
    for i in range(9):
        t = i / 8
        stations.append((1.0 + (H + 0.22 - 1.0) * math.sin(math.pi / 2 * t), 0, -0.2,
                         (W / 2 - 0.3) * math.cos(math.pi / 2 * t) ** 0.35 + 0.05, (D / 2 - 0.35) * math.cos(math.pi / 2 * t) ** 0.35 + 0.05))
    G.loft(gold, stations, 20, True, True, axis="z")
    for _ in range(150):
        x = rnd.uniform(-W / 2 + 0.45, W / 2 - 0.45)
        y = rnd.uniform(-D / 2 + 0.5, D / 2 - 0.5)
        z = heap_height(x, y) + 0.03
        tilt = Matrix.Rotation(rnd.uniform(-0.7, 0.7), 4, "X") @ Matrix.Rotation(rnd.uniform(-0.7, 0.7), 4, "Y")
        disc(gold, (x, y, z + rnd.uniform(0, 0.08)), 0.33, 0.07, tilt)
    for _ in range(26):
        # Over the front edge and down the face onto the rock in front of the chest.
        t = rnd.random()
        x = rnd.uniform(-1.3, 1.3) + (t - 0.5) * 0.6
        if t < 0.45:
            y, z = D / 2 + 0.1 + t * 0.4, H + 0.1 - t * 1.2
        else:
            y, z = D / 2 + 0.2 + (t - 0.45) * 2.6, 0.05 + rnd.uniform(0, 0.15)
        tilt = Matrix.Rotation(rnd.uniform(-1.2, 1.2), 4, "X") @ Matrix.Rotation(rnd.uniform(-1.2, 1.2), 4, "Y")
        disc(gold, (x, y, z), 0.28, 0.06, tilt)
    gx, gy = -1.4, 0.6
    gz = heap_height(gx, gy) - 0.1
    G.loft(gold, [(gz, gx, gy, 0.35, 0.35), (gz + 0.12, gx, gy, 0.3, 0.3), (gz + 0.2, gx, gy, 0.07, 0.07),
                  (gz + 0.75, gx, gy, 0.07, 0.07), (gz + 0.85, gx, gy, 0.22, 0.22), (gz + 1.25, gx, gy, 0.36, 0.36),
                  (gz + 1.3, gx, gy, 0.37, 0.37)], 12, True, False, axis="z")
    cx, cy = 1.3, -0.4
    cz = heap_height(cx, cy) - 0.15
    G.loft(gold, [(cz, cx, cy, 0.55, 0.55), (cz + 0.3, cx, cy, 0.55, 0.55)], 16, False, False, axis="z")
    for k in range(6):
        a = 2 * math.pi * k / 6
        base = Vector((cx + 0.55 * math.cos(a), cy + 0.55 * math.sin(a), cz + 0.3))
        tangent = Vector((-math.sin(a), math.cos(a), 0))
        pts = [base - tangent * 0.2, base + tangent * 0.2, base + Vector((0, 0, 0.42))]
        G.plate(gold, [tuple(p) for p in pts], (math.cos(a), math.sin(a), 0), 0.05)

    # GEMS: rubies on the heap, one on the crown, one on the goblet.
    for _ in range(9):
        x = rnd.uniform(-W / 2 + 0.7, W / 2 - 0.7)
        y = rnd.uniform(-D / 2 + 0.6, D / 2 - 0.6)
        gem(gems, (x, y, heap_height(x, y) + 0.12), rnd.uniform(0.12, 0.2))
    gem(gems, (cx, cy + 0.56, cz + 0.2), 0.14)
    gem(gems, (gx, gy + 0.36, gz + 1.05), 0.1)

    # PEARLS: a string over the front edge, sagging, one end on the heap and the other on the rock.
    a = Vector((0.4, D / 2 - 0.4, heap_height(0.4, D / 2 - 0.4)))
    b = Vector((1.5, D / 2 + 1.1, 0.12))
    for k in range(24):
        t = k / 23
        p = a.lerp(b, t)
        over = Vector((0, 0, 0.9 * math.sin(math.pi * min(1.0, t * 1.5)) * (1 - t)))
        ball(pearls, tuple(p + over), 0.11)

    lo, hi = (-4.5, -4.5, -6.0), (4.5, 4.5, 6.0)
    out = []
    for bm, name, smooth in ((wood, "Treasure_Wood", False), (iron, "Treasure_Iron", False), (gold, "Treasure_Gold", True),
                             (gems, "Treasure_Gems", False), (pearls, "Treasure_Pearls", True)):
        G.anchor(bm, lo, hi)
        out.append(G.to_object(name, bm, smooth))
    return out


def main():
    G.clear_scene()
    objects = build()
    print("\nThe treasure, to meshes/:")
    for obj in objects:
        G.export([obj], obj.name)
    if G.RENDER:
        G.COLOURS.update({"Treasure_Wood": (0.42, 0.28, 0.17), "Treasure_Iron": (0.2, 0.2, 0.22),
                          "Treasure_Gold": (0.93, 0.74, 0.3), "Treasure_Gems": (0.75, 0.08, 0.12),
                          "Treasure_Pearls": (0.95, 0.94, 0.9)})
        G.preview(objects, "Treasure", {})
    path = os.path.join(HERE, "sealife_extents.json")
    try:
        with open(path, encoding="utf-8") as f:
            known = json.load(f)
    except (OSError, ValueError):
        known = {}
    known.update({name: box for name, box in G.EXTENTS.items() if name.startswith("Treasure_")})
    with open(path, "w", encoding="utf-8") as f:
        json.dump(known, f, indent=1, sort_keys=True)
    print("  added the treasure to blender/sealife_extents.json")


if __name__ == "__main__":
    main()
