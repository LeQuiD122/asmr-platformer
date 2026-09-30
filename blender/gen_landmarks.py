"""The Sunken City's landmarks: four tall buildings the skyline is read by.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_landmarks.py
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_landmarks.py -- render

Writes meshes/Landmark_*.fbx (ten of them) and adds each one's box to blender/sealife_extents.json
(run it after gen_sealife.py, which rewrites that file). Import them all into
ReplicatedStorage/Assets/TileMeshes. SunkenCityService stands each landmark in its own square of
open water; without the meshes it builds a plainer tower of parts in the same place.

=== Why these four ===

The city was blocks, and blocks from a distance are a field of flat tops. A skyline is read by a
handful of shapes nothing else has, so each of these is one silhouette:

    DECO      An Art Deco skyscraper: stepped setbacks, stone piers over dark glass, and a brass
              crown of sunburst arches with a needle on it -- the tallest thing in the city.
    NEEDLE    The observation tower: a tapering shaft on three flared fins, a saucer pod with a
              band of dark glass round it, and a mast. The one round silhouette on the skyline.
    TWIN      Two slender octagonal towers stepping in toward their spires, and a skybridge
              between them on its own legs.
    LEAN      A glass office block that has started to go over: its top floors broken off at one
              corner, panes missing, the floors showing. The server stands it tilted, away from the
              route; it is modelled upright here.

=== Conventions ===

    UP        Blender Z, arriving as Roblox Y. Every landmark stands on the sea floor at z = 0 and
              its box runs to its top, so the box's centre is half its height up: the server puts
              the part at the floor plus half the height, and the base is on the floor.
    COLOURS   One per mesh, so a landmark is two or three meshes sharing one box: the server drops
              them all at the same CFrame and they line up (the same trick as the turtle's shell).
    SIZE      One Blender unit to one stud. Under 10,000 triangles a mesh.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sealife as G  # noqa: E402  -- loft, plate, anchor, to_object, export

FLOOR_DEPTH = 100.0   # SunkenCityService's FLOOR_DEPTH: the water is this far over the floor
STOREY = 3.6


def cuboid(bm, matrix):
    """The unit cube through `matrix`, flat-shaded."""
    made = bmesh.ops.create_cube(bm, size=1.0, matrix=matrix)
    flat = G.flat_layer(bm)
    for f in {f for v in made["verts"] for f in v.link_faces}:
        f[flat] = 1


def box(bm, centre, size, rz=0.0):
    """A box, flat-shaded, turned `rz` about the vertical."""
    cuboid(bm, Matrix.Translation(Vector(centre)) @ Matrix.Rotation(rz, 4, "Z") @ Matrix.Diagonal(
        (size[0], size[1], size[2], 1.0)))


def ring_band(bm, z0, z1, radius, sides, out=0.0):
    """A band round a vertical axis, from z0 to z1, standing `out` proud of `radius`."""
    G.loft(bm, [(z0, 0, 0, radius, radius), (z0 + 0.05, 0, 0, radius + out, radius + out),
                (z1 - 0.05, 0, 0, radius + out, radius + out), (z1, 0, 0, radius, radius)], sides, False, False, axis="z")


# ============================================================================ DECO

DECO_TIERS = ((44.0, 0.0, 160.0), (36.0, 160.0, 196.0), (28.0, 196.0, 220.0), (20.0, 220.0, 234.0))
DECO_TOP = 282.0


def deco():
    stone, glass, crown = bmesh.new(), bmesh.new(), bmesh.new()
    for width, z0, z1 in DECO_TIERS:
        half = width / 2
        # The glass core, dark; the stone lattice over it.
        box(glass, (0, 0, (z0 + z1) / 2), (width - 0.4, width - 0.4, z1 - z0))
        piers = max(4, int(width / 5.5))
        for face in range(4):
            rz = face * math.pi / 2
            c, s = math.cos(rz), math.sin(rz)
            for k in range(piers + 1):
                u = -half + width * k / piers
                wide = 2.4 if k in (0, piers) else 1.2
                x, y = half + 0.3, u
                box(stone, (x * c - y * s, x * s + y * c, (z0 + z1) / 2), (0.9, wide, z1 - z0), rz)
            # Spandrels: a stone band at every storey, so the glass reads as windows.
            z = z0 + STOREY
            while z < z1 - 1:
                x = half + 0.1
                box(stone, (x * c, x * s, z), (0.5, width, 0.6), rz)
                z += STOREY
        # A cornice at every setback.
        box(stone, (0, 0, z1 - 0.6), (width + 2.2, width + 2.2, 1.2))
    # The plinth on the floor, wider than the shaft.
    box(stone, (0, 0, 3.0), (50, 50, 6))
    # THE CROWN: three stepped brass drums, a row of sunburst arches standing round each, and the needle.
    z = DECO_TIERS[-1][2]
    for width, high in ((18.0, 7.0), (13.0, 7.0), (8.0, 7.0)):
        box(crown, (0, 0, z + high / 2), (width, width, high))
        half = width / 2
        for face in range(4):
            rz = face * math.pi / 2
            c, s = math.cos(rz), math.sin(rz)
            arches = 5
            for k in range(arches):
                u = -half + width * (k + 0.5) / arches
                x = half + 0.15
                cx, cy = x * c - u * s, x * s + u * c
                w = width / arches * 0.42
                # A pointed arch standing proud of the drum's face.
                pts = [(0, -w, z + 0.4), (0, w, z + 0.4), (0, w, z + high * 0.55), (0, 0, z + high * 1.05),
                       (0, -w, z + high * 0.55)]
                rot = Matrix.Rotation(rz, 3, "Z")
                G.plate(crown, [tuple(rot @ Vector(p) + Vector((cx, cy, 0))) for p in pts], tuple(rot @ Vector((1, 0, 0))), 0.25)
        z += high
    G.loft(crown, [(z, 0, 0, 2.2, 2.2), (z + 4, 0, 0, 1.6, 1.6), (z + 16, 0, 0, 0.8, 0.8), (DECO_TOP, 0, 0, 0.1, 0.1)], 8, axis="z")
    lo, hi = (-26, -26, 0), (26, 26, DECO_TOP)
    out = []
    for bm, name, smooth in ((stone, "Landmark_DecoStone", False), (glass, "Landmark_DecoGlass", False),
                             (crown, "Landmark_DecoCrown", False)):
        G.anchor(bm, lo, hi)
        out.append(G.to_object(name, bm, smooth))
    return out


# ============================================================================ NEEDLE

NEEDLE_POD = 232.0
NEEDLE_TOP = 300.0


def needle():
    shaft, pod, glass = bmesh.new(), bmesh.new(), bmesh.new()
    # The shaft, tapering, with a collar every thirty studs.
    G.loft(shaft, [(0, 0, 0, 8.0, 8.0), (60, 0, 0, 6.8, 6.8), (140, 0, 0, 5.6, 5.6), (NEEDLE_POD, 0, 0, 4.6, 4.6)],
           20, True, False, axis="z")
    for z in range(30, int(NEEDLE_POD), 30):
        r = 8.0 - (8.0 - 4.6) * z / NEEDLE_POD
        ring_band(shaft, z, z + 1.2, r, 20, 0.5)
    # Three flared fins round the foot, which are what make it stand rather than balance.
    for k in range(3):
        a = 2 * math.pi * k / 3
        c, s = math.cos(a), math.sin(a)
        outline = [(0, 0, 0), (15, 0, 0), (13, 0, 8), (6, 0, 60), (0, 0, 120)]
        G.plate(shaft, [(x * c + 4 * c, x * s + 4 * s, z) for x, _, z in outline], (-s, c, 0), 1.4)
    # THE POD: a saucer with a flared underside, and the mast out of its roof.
    G.loft(pod, [(NEEDLE_POD - 4, 0, 0, 4.6, 4.6), (NEEDLE_POD, 0, 0, 8, 8), (NEEDLE_POD + 4, 0, 0, 15, 15),
                 (NEEDLE_POD + 8, 0, 0, 18, 18), (NEEDLE_POD + 12, 0, 0, 18.5, 18.5), (NEEDLE_POD + 16, 0, 0, 17, 17),
                 (NEEDLE_POD + 19, 0, 0, 12, 12), (NEEDLE_POD + 21, 0, 0, 6, 6), (NEEDLE_POD + 22, 0, 0, 3, 3)], 32, axis="z")
    G.loft(pod, [(NEEDLE_POD + 21.5, 0, 0, 1.4, 1.4), (NEEDLE_POD + 40, 0, 0, 1.0, 1.0), (NEEDLE_TOP, 0, 0, 0.2, 0.2)], 8, axis="z")
    for z in (NEEDLE_POD + 30, NEEDLE_POD + 44, NEEDLE_POD + 56):
        G.loft(pod, [(z, 0, 0, 1.2, 1.2), (z + 0.3, 0, 0, 2.6, 2.6), (z + 0.8, 0, 0, 2.6, 2.6), (z + 1.1, 0, 0, 1.2, 1.2)], 12, axis="z")
    # The observation deck's glass, all the way round.
    ring_band(glass, NEEDLE_POD + 8.6, NEEDLE_POD + 14.4, 18.2, 32, 0.9)
    lo, hi = (-19.5, -19.5, 0), (19.5, 19.5, NEEDLE_TOP)
    out = []
    for bm, name in ((shaft, "Landmark_NeedleShaft"), (pod, "Landmark_NeedlePod"), (glass, "Landmark_NeedleGlass")):
        G.anchor(bm, lo, hi)
        out.append(G.to_object(name, bm, True))
    return out


# ============================================================================ TWIN

TWIN_APART = 22.0     # each tower's axis, either side of the middle
TWIN_TOP = 300.0
TWIN_BRIDGE = 150.0


def twin():
    body, glass = bmesh.new(), bmesh.new()
    steps = ((0.0, 196.0, 11.0), (196.0, 222.0, 9.5), (222.0, 238.0, 8.0), (238.0, 250.0, 6.0))
    for side in (-1, 1):
        x = side * TWIN_APART

        def at(stations):
            return [(z, x, 0, r, r) for z, _, _, r, _ in stations]

        for z0, z1, r in steps:
            G.loft(body, at([(z0, 0, 0, r, r), (z1, 0, 0, r, r)]), 8, True, True, axis="z")
            # Dark glass bands, a storey apart, standing a little proud: the windows, all round.
            z = z0 + 1.2
            while z < z1 - 1.4:
                G.loft(glass, at([(z, 0, 0, r + 0.25, r + 0.25), (z + 2.0, 0, 0, r + 0.25, r + 0.25)]), 8, False, False,
                       axis="z")
                z += STOREY
        G.loft(body, at([(250.0, 0, 0, 2.0, 2.0), (262.0, 0, 0, 1.2, 1.2), (TWIN_TOP, 0, 0, 0.15, 0.15)]), 8, axis="z")
    # The skybridge, two storeys deep, and the legs it stands on, down to each tower.
    box(body, (0, 0, TWIN_BRIDGE), (2 * TWIN_APART - 2 * 9.0, 4.4, 5.0))
    for side in (-1, 1):
        a = Vector((side * 4.0, 0, TWIN_BRIDGE - 2.5))
        b = Vector((side * (TWIN_APART - 10.0), 0, TWIN_BRIDGE - 26.0))
        mid = (a + b) / 2
        d = b - a
        ang = math.atan2(d.z, d.x)
        cuboid(body, Matrix.Translation(mid) @ Matrix.Rotation(-ang, 4, "Y") @ Matrix.Diagonal((d.length, 1.4, 1.4, 1.0)))
    box(glass, (0, 0, TWIN_BRIDGE + 0.6), (2 * TWIN_APART - 2 * 9.0 + 0.4, 4.8, 2.2))
    lo, hi = (-TWIN_APART - 12, -12, 0), (TWIN_APART + 12, 12, TWIN_TOP)
    out = []
    for bm, name in ((body, "Landmark_TwinBody"), (glass, "Landmark_TwinGlass")):
        G.anchor(bm, lo, hi)
        out.append(G.to_object(name, bm, False))
    return out


# ============================================================================ LEAN

LEAN_W, LEAN_D = 32.0, 24.0
LEAN_TOP = 205.0
LEAN_FLOOR = 4.5


def lean():
    frame, glass = bmesh.new(), bmesh.new()
    import random
    rnd = random.Random(7)
    floors = int(LEAN_TOP / LEAN_FLOOR)
    broken_from = floors - 6
    hw, hd = LEAN_W / 2, LEAN_D / 2
    for f in range(floors + 1):
        z = max(0.35, f * LEAN_FLOOR)  # the ground slab sits ON the floor, inside the shared box
        if f >= broken_from:
            # The top floors have lost their +x, +y corner: two slabs making an L, the break ragged.
            bite = 0.45 + 0.08 * (f - broken_from)
            box(frame, (-hw * bite / 2, 0, z), (LEAN_W * (1 - bite / 2), LEAN_D + 0.6, 0.7))
            box(frame, (hw * (1 - bite / 2), -hd / 2, z), (LEAN_W * bite / 2, LEAN_D / 2, 0.7))
            if f < floors:
                # A slab hanging off the break, torn.
                box(frame, (hw * 0.55, hd * 0.45, z - 1.5), (6, 5, 0.6), 0.5 + 0.1 * f)
        else:
            box(frame, (0, 0, z), (LEAN_W + 0.6, LEAN_D + 0.6, 0.7))
    # Columns round the edge and the core in the middle.
    for x in (-hw, -hw / 3, hw / 3, hw):
        for y in (-hd, hd):
            top = LEAN_TOP if not (x > 0 and y > 0) else broken_from * LEAN_FLOOR
            box(frame, (x, y, top / 2), (1.0, 1.0, top))
    box(frame, (-2, 0, LEAN_TOP / 2 + 2), (8, 6, LEAN_TOP + 4))
    # The curtain wall, a pane a floor a face, some gone, and none where the corner broke.
    for f in range(floors):
        z = f * LEAN_FLOOR + LEAN_FLOOR / 2 + 0.35
        for face, (cx, cy, sx, sy) in enumerate(((hw + 0.2, 0, 0.2, LEAN_D), (-hw - 0.2, 0, 0.2, LEAN_D),
                                                 (0, hd + 0.2, LEAN_W, 0.2), (0, -hd - 0.2, LEAN_W, 0.2))):
            if f >= broken_from and face in (0, 2):
                continue
            if rnd.random() < 0.1:
                continue
            box(glass, (cx, cy, z), (sx, sy, LEAN_FLOOR - 0.8))
    lo, hi = (-20, -16, 0), (20, 16, LEAN_TOP + 4)
    out = []
    for bm, name in ((frame, "Landmark_LeanFrame"), (glass, "Landmark_LeanGlass")):
        G.anchor(bm, lo, hi)
        out.append(G.to_object(name, bm, False))
    return out


# ============================================================================

COLOURS = {"Landmark_DecoStone": (0.8, 0.76, 0.66), "Landmark_DecoGlass": (0.14, 0.17, 0.21),
           "Landmark_DecoCrown": (0.71, 0.58, 0.33), "Landmark_NeedleShaft": (0.84, 0.83, 0.79),
           "Landmark_NeedlePod": (0.88, 0.87, 0.84), "Landmark_NeedleGlass": (0.17, 0.23, 0.27),
           "Landmark_TwinBody": (0.72, 0.74, 0.76), "Landmark_TwinGlass": (0.2, 0.26, 0.32),
           "Landmark_LeanFrame": (0.74, 0.74, 0.72), "Landmark_LeanGlass": (0.29, 0.41, 0.48)}


def preview(objects, tag):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x, scene.render.resolution_y = 700, 1000
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    for o in objects:
        o.color = COLOURS.get(o.name, (0.6, 0.6, 0.6)) + (1.0,)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 330
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    d = Vector((0.8, -1.0, 0.35)).normalized()
    cam.location = Vector((0, 0, 160)) + d * 600
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(HERE, "landmark_%s.png" % tag)
    bpy.ops.render.render(write_still=True)


def main():
    print("\nThe landmarks, to meshes/:")
    for builder, tag in ((deco, "deco"), (needle, "needle"), (twin, "twin"), (lean, "lean")):
        G.clear_scene()
        objects = builder()
        for obj in objects:
            G.export([obj], obj.name)
        if G.RENDER:
            preview(objects, tag)
    path = os.path.join(HERE, "sealife_extents.json")
    try:
        with open(path, encoding="utf-8") as f:
            known = json.load(f)
    except (OSError, ValueError):
        known = {}
    known.update({name: box_ for name, box_ in G.EXTENTS.items() if name.startswith("Landmark_")})
    with open(path, "w", encoding="utf-8") as f:
        json.dump(known, f, indent=1, sort_keys=True)
    print("  added the landmarks to blender/sealife_extents.json")
    print("\nImport every Landmark_*.fbx into ReplicatedStorage/Assets/TileMeshes.")


if __name__ == "__main__":
    main()
