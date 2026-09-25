"""The drowned Ferris wheel: the Sunken City's landmark on the far side of the street.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_ferris.py
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_ferris.py -- render

Run it AFTER gen_sealife.py, which rewrites blender/sealife_extents.json that this adds to.

Writes meshes/Ferris_Wheel.fbx, Ferris_Frame.fbx and Ferris_Gondola.fbx. Import all three into
ReplicatedStorage/Assets/TileMeshes. SunkenCityService stands the frame and hangs the wheel and
its cabins from it; SunkenCityClient turns the wheel and keeps every cabin hanging upright. With
none imported, the service builds a plainer wheel from parts in the same place.

=== Why a Ferris wheel ===

Every city has towers and a clock; a drowned one reads as drowned by what should not be in water.
A fairground wheel standing in the sea, its lowest cabins under the surface and the rest still
going round, very slowly, for nobody, is the one silhouette on this level nothing else has --
and it is a circle, in a city of rectangles, which is why it is seen from everywhere.

=== Conventions ===

    AXLE      Along Blender X, which arrives as Roblox X: the wheel turns about its part's X axis.
    CENTRE    The wheel's box is centred on the axle (anchored so), and the frame's box is too, so
              both are placed at the axle's CFrame with no offsets. The frame reaches FRAME_DOWN
              below the axle, to the sea floor.
    CABIN     The cabin's box is centred on the cabin; it hangs HANG below its pivot on the rim.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sealife as G  # noqa: E402  -- the same loft, plate, anchor and export

RADIUS = 36.0        # to the outer rim
INNER = 31.0         # the inner rim of the truss
HALF_WIDTH = 3.0     # each side of the wheel, from the middle
CABINS = 16
FRAME_DOWN = 126.0   # the axle stands this far over the sea floor (hub 26 over the water, floor 100 under it)
HANG = 3.0           # a cabin's middle, under its pivot


def tube(bm, a, b, r, sides=6):
    """A straight tube from a to b."""
    a, b = Vector(a), Vector(b)
    axis = (b - a).normalized()
    helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
    u = axis.cross(helper).normalized()
    v = axis.cross(u).normalized()
    rings = []
    for end in (a, b):
        rings.append([bm.verts.new(end + (u * math.cos(2 * math.pi * k / sides) + v * math.sin(2 * math.pi * k / sides)) * r)
                      for k in range(sides)])
    for k in range(sides):
        bm.faces.new((rings[0][k], rings[0][(k + 1) % sides], rings[1][(k + 1) % sides], rings[1][k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[1])


def hoop(bm, x, radius, r, segments=64, sides=6):
    """A ring about the X axis at `x`: the rim."""
    rings = []
    for i in range(segments):
        a = 2 * math.pi * i / segments
        centre = Vector((x, radius * math.cos(a), radius * math.sin(a)))
        out = Vector((0, math.cos(a), math.sin(a)))
        side = Vector((1, 0, 0))
        rings.append([bm.verts.new(centre + (out * math.cos(2 * math.pi * k / sides) + side * math.sin(2 * math.pi * k / sides)) * r)
                      for k in range(sides)])
    for i in range(segments):
        for k in range(sides):
            a, b = rings[i][k], rings[i][(k + 1) % sides]
            c, d = rings[(i + 1) % segments][(k + 1) % sides], rings[(i + 1) % segments][k]
            bm.faces.new((a, b, c, d))


def build_wheel():
    bm = bmesh.new()
    for side in (-1, 1):
        x = side * HALF_WIDTH
        hoop(bm, x, RADIUS, 0.45)
        hoop(bm, x, INNER, 0.35)
        # The truss between the rims: a zigzag, which is what makes a wheel look like it holds.
        for i in range(CABINS * 2):
            a0 = 2 * math.pi * i / (CABINS * 2)
            a1 = 2 * math.pi * (i + 1) / (CABINS * 2)
            outer = Vector((x, RADIUS * math.cos(a0), RADIUS * math.sin(a0)))
            inner = Vector((x, INNER * math.cos(a1), INNER * math.sin(a1)))
            tube(bm, outer, inner, 0.18, 4)
        # Spokes from the hub's flange to the inner rim, raked in toward the hub.
        for i in range(CABINS):
            a = 2 * math.pi * (i + 0.5) / CABINS
            tube(bm, (side * 5.0, 2.6 * math.cos(a), 2.6 * math.sin(a)), (x, INNER * math.cos(a), INNER * math.sin(a)), 0.25, 5)
    # The cabins' axles across the wheel, standing out past the rims.
    for i in range(CABINS):
        a = 2 * math.pi * i / CABINS
        y, z = RADIUS * math.cos(a), RADIUS * math.sin(a)
        tube(bm, (-HALF_WIDTH - 0.8, y, z), (HALF_WIDTH + 0.8, y, z), 0.3, 6)
    # The hub: a drum with flanges.
    G.loft(bm, [(-5.4, 0, 0, 2.4, 2.4), (-5.0, 0, 0, 3.0, 3.0), (-4.2, 0, 0, 3.0, 3.0), (-3.8, 0, 0, 2.2, 2.2),
                (3.8, 0, 0, 2.2, 2.2), (4.2, 0, 0, 3.0, 3.0), (5.0, 0, 0, 3.0, 3.0), (5.4, 0, 0, 2.4, 2.4)], 16, True, True,
           axis="x")
    G.anchor(bm, (-7, -RADIUS - 1, -RADIUS - 1), (7, RADIUS + 1, RADIUS + 1))
    return G.to_object("Ferris_Wheel", bm)


def build_frame():
    bm = bmesh.new()
    # Two A-frames, one each side of the wheel, from the axle's bearings to the sea floor, braced
    # all the way down; and the axle across between them.
    foot_x, foot_y = 9.0, 30.0
    for side in (-1, 1):
        top = Vector((side * 7.2, 0, 0))
        feet = [Vector((side * foot_x, -foot_y, -FRAME_DOWN)), Vector((side * foot_x, foot_y, -FRAME_DOWN))]
        for foot in feet:
            tube(bm, top, foot, 0.95, 8)
        # Braces between the two legs every so often, and a diagonal in each bay.
        previous = None
        for k in range(1, 9):
            t = k / 9
            a = top.lerp(feet[0], t)
            b = top.lerp(feet[1], t)
            tube(bm, a, b, 0.4, 6)
            if previous:
                tube(bm, previous[0], b, 0.28, 5)
            previous = (a, b)
        # The bearing block.
        G.loft(bm, [(top.y + 1.6, top.x, 0, 1.4, 1.4), (top.y - 1.6, top.x, 0, 1.4, 1.4)], 8)
        # A footing on the floor under each leg.
        for foot in feet:
            G.loft(bm, [(foot.y + 2.2, foot.x, foot.z + 1.0, 2.2, 1.0), (foot.y - 2.2, foot.x, foot.z + 1.0, 2.2, 1.0)], 6)
    # Cross ties between the two frames, low down.
    for k in (4, 7):
        t = k / 9
        for end in (-1, 1):
            a = Vector((-7.2, 0, 0)).lerp(Vector((-foot_x, end * foot_y, -FRAME_DOWN)), t)
            b = Vector((7.2, 0, 0)).lerp(Vector((foot_x, end * foot_y, -FRAME_DOWN)), t)
            tube(bm, a, b, 0.35, 6)
    tube(bm, (-7.6, 0, 0), (7.6, 0, 0), 1.1, 12)
    G.anchor(bm, (-12, -34, -FRAME_DOWN - 1), (12, 34, FRAME_DOWN + 1))
    return G.to_object("Ferris_Frame", bm)


def rounded_stack(bm, levels, sides=16, power=4.0):
    """A solid through horizontal rounded-square sections, each (z, half-x, half-y), capped both ends."""
    rings = []
    for z, rx, ry in levels:
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides + math.pi / sides
            c, s = math.cos(a), math.sin(a)
            d = (abs(c) ** power + abs(s) ** power) ** (1 / power)
            ring.append(bm.verts.new((rx * c / d, ry * s / d, z)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
    for ring, z in ((rings[0], levels[0][0]), (rings[-1], levels[-1][0])):
        centre = bm.verts.new((0, 0, z))
        for k in range(sides):
            bm.faces.new((ring[k], ring[(k + 1) % sides], centre))


def build_gondola():
    bm = bmesh.new()
    # An OPEN CABIN, the way the old ones were: a rounded tub to the waist, a post at each corner,
    # the window openings between them, a roof with an overhang, and the stirrup it hangs by.
    rounded_stack(bm, [(-1.8, 1.05, 0.85), (-1.6, 1.4, 1.15), (-0.2, 1.5, 1.25), (0.05, 1.55, 1.3)])
    for x in (-1.3, 1.3):
        for y in (-1.05, 1.05):
            tube(bm, (x, y, 0.0), (x, y, 1.75), 0.1, 5)
    rounded_stack(bm, [(1.7, 1.7, 1.45), (1.95, 1.75, 1.5), (2.25, 1.25, 1.0), (2.4, 0.4, 0.3)])
    for side in (-1, 1):
        tube(bm, (side * 0.9, 0, 2.2), (side * 0.2, 0, HANG), 0.1, 5)
    tube(bm, (-0.4, 0, HANG), (0.4, 0, HANG), 0.18, 6)
    # A little past the stirrup's bar, both ways, so the box stays centred on the cabin.
    G.anchor(bm, (-2.2, -2.2, -HANG - 0.3), (2.2, 2.2, HANG + 0.3))
    return G.to_object("Ferris_Gondola", bm)


def main():
    print("")
    print("The Ferris wheel, to meshes/:")
    for builder in (build_wheel, build_frame, build_gondola):
        G.clear_scene()
        obj = builder()
        G.export([obj], obj.name)
        if G.RENDER:
            G.COLOURS[obj.name] = (0.8, 0.78, 0.74)
            G.preview([obj], obj.name, {})
    # Their real boxes go into the same file gen_sealife.py writes, for check_sunkencity.py.
    path = os.path.join(HERE, "sealife_extents.json")
    try:
        with open(path, encoding="utf-8") as f:
            known = json.load(f)
    except (OSError, ValueError):
        known = {}
    known.update({name: box for name, box in G.EXTENTS.items() if name.startswith("Ferris_")})
    with open(path, "w", encoding="utf-8") as f:
        json.dump(known, f, indent=1, sort_keys=True)
    print("  added the wheel to blender/sealife_extents.json")
    print("")
    print("Import all three into ReplicatedStorage/Assets/TileMeshes.")


if __name__ == "__main__":
    main()
