"""The Sunken City's boats: what people took to the streets in when the streets became water.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_boats.py
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_boats.py -- render

Writes meshes/Boat_Row.fbx, Boat_LaunchHull.fbx and Boat_LaunchTop.fbx, and adds their boxes to
blender/sealife_extents.json (run it after gen_sealife.py). Import all three into
ReplicatedStorage/Assets/TileMeshes. SunkenCityService moors them in the side streets, some turned
over; SunkenCityClient bobs them with the buoys. Without the meshes they are plain hulls of parts.

    PIVOT   Every box is centred on the WATERLINE (z = 0), so the server puts a boat at the water's
            height and it floats at its own draught. The launch's hull and top share one box.
    DECKS   Well above the waterline -- a rowboat's floor 0.8 over it, the launch's deck 1.2 -- so a
            bobbing boat never lays a flat face on the water's (SURFACE_CLEAR's reason).
"""

import json
import math
import os
import sys

import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sealife as G  # noqa: E402


def hull(bm, length, beam, top, keel, sides=12, stations=17, bow=0.5, stern=0.85):
    """A hull along Y (bow at +Y): a U from gunwale to gunwale, closed flat across the top at `top`,
    `keel` deep at its lowest. The bow draws to a point; the stern stays `stern` of the beam."""
    rings = []
    for i in range(stations):
        t = i / (stations - 1)
        y = -length / 2 + t * length
        if t < 0.5:
            w = beam / 2 * (stern + (1 - stern) * math.sin(math.pi * t) ** 0.6)
        else:
            u = (t - 0.5) / 0.5
            w = beam / 2 * (1 - u ** (1 / max(bow, 0.05)) * 0.97)
        d = (top - keel) * (0.75 + 0.25 * math.sin(math.pi * min(1, t * 1.2)))
        rise = 0.35 * max(0.0, (t - 0.75) / 0.25) ** 2  # the sheer rising to the bow
        ring = []
        for k in range(sides + 1):
            a = math.pi + math.pi * k / sides
            ring.append(bm.verts.new((w * math.cos(a), y, top + rise + d * math.sin(a))))
        rings.append(ring)
    n = sides + 1
    for i in range(stations - 1):
        for k in range(n):
            a, b = rings[i][k], rings[i][(k + 1) % n]
            c, d_ = rings[i + 1][(k + 1) % n], rings[i + 1][k]
            bm.faces.new((a, b, c, d_))
    for ring, flip in ((rings[0], True), (rings[-1], False)):
        centre = bm.verts.new(sum((v.co for v in ring), Vector()) / n)
        for k in range(n):
            face = (ring[k], ring[(k + 1) % n], centre)
            bm.faces.new(tuple(reversed(face)) if flip else face)
    return rings


def cuboid(bm, centre, size, rz=0.0, rx=0.0):
    m = (Matrix.Translation(Vector(centre)) @ Matrix.Rotation(rz, 4, "Z") @ Matrix.Rotation(rx, 4, "X")
         @ Matrix.Diagonal((size[0], size[1], size[2], 1.0)))
    made = bmesh.ops.create_cube(bm, size=1.0, matrix=m)
    flat = G.flat_layer(bm)
    for f in {f for v in made["verts"] for f in v.link_faces}:
        f[flat] = 1


def rowboat():
    bm = bmesh.new()
    # The hull floor 0.8 over the water, the gunwales 0.55 over that, the keel 0.6 under.
    rings = hull(bm, 8.0, 3.2, 0.8, -0.6)
    # Gunwale strakes, following the sheer, both sides.
    for i in range(len(rings) - 1):
        for side in (0, -1):
            a, b = rings[i][side].co, rings[i + 1][side].co
            mid = (a + b) / 2
            run = b - a
            cuboid(bm, (mid.x, mid.y, mid.z + 0.28), (0.14, run.length + 0.05, 0.55), math.atan2(-run.x, run.y))
    # Two thwarts and an oar across them.
    for y in (-1.2, 1.3):
        cuboid(bm, (0, y, 1.15), (2.6, 0.45, 0.14))
    cuboid(bm, (0.3, 0.1, 1.3), (0.16, 6.2, 0.12), 0.25)
    cuboid(bm, (0.3 + 0.78, 0.1 + 2.9, 1.3), (0.5, 0.9, 0.06), 0.25)
    G.anchor(bm, (-2.0, -4.6, -1.6), (2.0, 4.6, 1.6))
    return [G.to_object("Boat_Row", bm, True)]


def launch():
    hull_bm, top_bm = bmesh.new(), bmesh.new()
    hull(hull_bm, 16.0, 5.6, 1.2, -1.4, sides=14, stations=21, bow=0.55, stern=0.9)
    # THE TOP: a cabin aft of amidships with a raked windscreen, a band of windows, a rail round the
    # foredeck on its stanchions, and a mast with a lamp-bracket.
    cuboid(top_bm, (0, -2.2, 2.3), (4.2, 6.0, 2.2))
    cuboid(top_bm, (0, -2.2, 3.5), (4.6, 6.6, 0.25))
    cuboid(top_bm, (0, 1.1, 2.4), (4.0, 0.2, 1.9), 0.0, math.radians(-28))
    for side in (-1, 1):
        cuboid(top_bm, (side * 2.12, -2.2, 2.55), (0.06, 5.0, 0.8))
    for i in range(6):
        y = 2.5 + i * 1.0
        w = 2.5 * (1 - max(0.0, (y - 5.0) / 3.2) ** 1.5)
        for side in (-1, 1):
            cuboid(top_bm, (side * w, y, 1.75), (0.1, 0.1, 1.1))
    for side in (-1, 1):
        pts = [(side * 2.5 * (1 - max(0.0, (2.5 + i - 5.0) / 3.2) ** 1.5), 2.5 + i, 2.3) for i in range(6)]
        for a, b in zip(pts, pts[1:]):
            a, b = Vector(a), Vector(b)
            mid, run = (a + b) / 2, b - a
            cuboid(top_bm, tuple(mid), (0.08, run.length + 0.08, 0.08), math.atan2(-run.x, run.y))
    cuboid(top_bm, (0, -3.2, 4.1), (0.18, 0.18, 1.6))  # the mast, inside the shared box
    lo, hi = (-3.2, -9.0, -5.0), (3.2, 9.0, 5.0)
    G.anchor(hull_bm, lo, hi)
    G.anchor(top_bm, lo, hi)
    return [G.to_object("Boat_LaunchHull", hull_bm, True), G.to_object("Boat_LaunchTop", top_bm, False)]


def main():
    print("\nThe boats, to meshes/:")
    for builder in (rowboat, launch):
        G.clear_scene()
        objects = builder()
        for obj in objects:
            G.export([obj], obj.name)
        if G.RENDER:
            G.COLOURS.update({"Boat_Row": (0.55, 0.4, 0.26), "Boat_LaunchHull": (0.88, 0.88, 0.85),
                              "Boat_LaunchTop": (0.17, 0.24, 0.38)})
            G.preview(objects, objects[0].name.replace("Boat_", "Boat"), {})
    path = os.path.join(HERE, "sealife_extents.json")
    try:
        with open(path, encoding="utf-8") as f:
            known = json.load(f)
    except (OSError, ValueError):
        known = {}
    known.update({name: box for name, box in G.EXTENTS.items() if name.startswith("Boat_")})
    with open(path, "w", encoding="utf-8") as f:
        json.dump(known, f, indent=1, sort_keys=True)
    print("  added the boats to blender/sealife_extents.json")


if __name__ == "__main__":
    main()
