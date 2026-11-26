"""The Flooded Halls' pool fittings (the two-hundred-and-fifty-sixth pass, "polish level 4's textures and models in
the pools").

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_pool_kit.py

Two pieces the pools were missing or had as stand-ins:

  Pool_LaneRope   A lane rope as a lane rope is made: a cord with a string of ridged disc floats threaded on it, not a
                  smooth cylinder (which read as a pole lying on the water). One 32-stud length; the service stretches
                  it to each run's length and colours each length, so the runs of red, white and blue stay.
  Pool_Ladder     A steel grab-rail ladder: two tubes rising off the deck, bending over the coping and dropping down the
                  wall into the water, with four treads between them. Six studs wide.

Writes meshes/Pool_LaneRope.fbx and meshes/Pool_Ladder.fbx. In Blender +X is along the rope / out over the pool for the
ladder, +Z up; the export turns z-up to y-up.
"""

import math
import os
import sys

import bmesh
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sealife as G  # noqa: E402  -- clear_scene, to_object, export

ROPE_LENGTH = 32.0
FLOAT_PITCH = 1.34      # float to float
FLOAT_RADIUS = 0.9
FLOAT_WIDTH = 1.12
AROUND = 14

LADDER_WIDTH = 6.0
TUBE = 0.28
RISE = 3.6              # how high the rails stand over the deck
DROP = 13.0             # how far they go down the wall
TREADS = (-2.4, -5.4, -8.4, -11.4)


def lathe_x(bm, profile, x0, around=AROUND):
    """A solid of revolution about +X: profile is [(dx, r)], closed at both ends."""
    rings = []
    for dx, r in profile:
        ring = []
        for j in range(around):
            a = j / around * math.tau
            ring.append(bm.verts.new((x0 + dx, math.cos(a) * r, math.sin(a) * r)))
        rings.append(ring)
    for lo, hi in zip(rings, rings[1:]):
        for j in range(around):
            k = (j + 1) % around
            bm.faces.new((lo[j], lo[k], hi[k], hi[j]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))


def build_rope():
    G.clear_scene()
    bm = bmesh.new()
    # The cord, end to end.
    lathe_x(bm, [(0, 0.16), (ROPE_LENGTH, 0.16)], -ROPE_LENGTH / 2, around=8)
    count = int(ROPE_LENGTH / FLOAT_PITCH)
    start = -ROPE_LENGTH / 2 + (ROPE_LENGTH - (count - 1) * FLOAT_PITCH) / 2
    w, r = FLOAT_WIDTH, FLOAT_RADIUS
    # A float: a disc with a rounded rim and a ridge round its middle, the way the moulded ones are.
    profile = [
        (-w / 2, 0.2), (-w / 2, r * 0.62), (-w * 0.38, r * 0.9), (-w * 0.16, r * 0.93),
        (0.0, r), (w * 0.16, r * 0.93), (w * 0.38, r * 0.9), (w / 2, r * 0.62), (w / 2, 0.2),
    ]
    for i in range(count):
        lathe_x(bm, profile, start + i * FLOAT_PITCH)
    obj = G.to_object("Pool_LaneRope", bm, smooth=True)
    G.export([obj], "Pool_LaneRope")
    return obj


def tube(bm, path, radius, around=10):
    """A closed tube swept along a polyline."""
    rings = []
    for i, p in enumerate(path):
        a = path[max(0, i - 1)]
        b = path[min(len(path) - 1, i + 1)]
        t = (b - a).normalized()
        side = t.cross(Vector((0, 1, 0)))
        if side.length < 1e-4:
            side = t.cross(Vector((1, 0, 0)))
        side.normalize()
        up = side.cross(t).normalized()
        ring = []
        for j in range(around):
            ang = j / around * math.tau
            ring.append(bm.verts.new(p + (side * math.cos(ang) + up * math.sin(ang)) * radius))
        rings.append(ring)
    for lo, hi in zip(rings, rings[1:]):
        for j in range(around):
            k = (j + 1) % around
            bm.faces.new((lo[j], lo[k], hi[k], hi[j]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))


def box(bm, centre, size):
    c, s = Vector(centre), Vector(size) / 2
    v = [bm.verts.new(c + Vector((sx * s.x, sy * s.y, sz * s.z)))
         for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        bm.faces.new([v[i] for i in f])


def build_ladder():
    G.clear_scene()
    bm = bmesh.new()
    # The rail's line in X-Z: from its foot in the deck, up, over the coping in a half-round bend, down the wall.
    path = [Vector((-2.6, 0, -0.4)), Vector((-2.6, 0, RISE - 1.4))]
    bend = 1.4
    centre = Vector((-2.6 + bend, 0, RISE - 1.4))
    for s in range(1, 12):
        a = math.pi - s / 12 * math.pi
        path.append(centre + Vector((math.cos(a) * bend, 0, math.sin(a) * bend)))
    path.append(Vector((-2.6 + 2 * bend, 0, RISE - 1.4)))
    wall_x = -2.6 + 2 * bend
    path.append(Vector((wall_x, 0, -DROP)))
    for side in (-1, 1):
        y = side * LADDER_WIDTH / 2
        tube(bm, [p + Vector((0, y, 0)) for p in path], TUBE)
        # The flange where it goes into the deck.
        lathe = [Vector((-2.6, y, -0.4)), Vector((-2.6, y, 0.05))]
        tube(bm, lathe, TUBE * 2.2, around=12)
    for z in TREADS:
        box(bm, (wall_x + 0.15, 0, z), (1.1, LADDER_WIDTH, 0.34))
    obj = G.to_object("Pool_Ladder", bm, smooth=True)
    G.export([obj], "Pool_Ladder")
    return obj


def build_ring():
    """A swim ring (pass 262): a fat torus, 4 across, 1.1 thick, lost on the bottom of the pool."""
    G.clear_scene()
    bm = bmesh.new()
    major, minor, around, sides = 1.45, 0.55, 28, 14
    rings = []
    for i in range(around):
        a = i / around * math.tau
        centre = Vector((math.cos(a) * major, math.sin(a) * major, 0))
        out = Vector((math.cos(a), math.sin(a), 0))
        ring = []
        for j in range(sides):
            b = j / sides * math.tau
            ring.append(bm.verts.new(centre + out * math.cos(b) * minor + Vector((0, 0, math.sin(b) * minor * 0.9))))
        rings.append(ring)
    for i in range(around):
        lo, hi = rings[i], rings[(i + 1) % around]
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new((lo[j], lo[k], hi[k], hi[j]))
    obj = G.to_object("Pool_Ring", bm, smooth=True)
    G.export([obj], "Pool_Ring")


def build_kickboard():
    """A kickboard (pass 262): a foam board, rounded at one end, square at the other, with a hand hole near the round
    end. 2.4 by 3.6, a third of a stud thick, its edges bevelled soft."""
    G.clear_scene()
    bm = bmesh.new()
    w, l, t = 2.4, 3.6, 0.32
    outline = []
    # The square end, then round the rounded end.
    outline.append((-w / 2, -l / 2))
    outline.append((w / 2, -l / 2))
    for s in range(13):
        a = s / 12 * math.pi
        outline.append((math.cos(a) * w / 2, l / 2 - w / 2 + math.sin(a) * w / 2))
    top = [bm.verts.new((x, y, t / 2)) for x, y in outline]
    bottom = [bm.verts.new((x * 0.94, y * 0.97, -t / 2)) for x, y in outline]
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((bottom[i], bottom[j], top[j], top[i]))
    bm.faces.new(top)
    bm.faces.new(list(reversed(bottom)))
    obj = G.to_object("Pool_Kickboard", bm, smooth=False)
    G.export([obj], "Pool_Kickboard")


if __name__ == "__main__":
    # export() prints each piece's triangles and Roblox size.
    build_rope()
    build_ladder()
    build_ring()
    build_kickboard()
