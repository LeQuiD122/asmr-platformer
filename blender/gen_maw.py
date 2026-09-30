"""The thing at the bottom of the flume: its mouth. Only its mouth; the rest of it is the dark.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_maw.py
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_maw.py -- render

Writes four meshes to meshes/ and blender/maw_extents.json:

    Maw_UpperJaw     the roof of the mouth and the head over it: a vaulted palate inside, a heavy
                     skull-like dome outside, a gum ridge round the rim where the teeth stand
    Maw_LowerJaw     the same, narrower and shorter, turned over: the floor of the mouth
    Maw_UpperTeeth   two rows of curved fangs along the upper rim, the longest at the front, a few
                     missing, every one a little different
    Maw_LowerTeeth   the same along the lower rim, set between the upper ones so the jaws close
                     like a trap rather than tooth on tooth

Import all four into ReplicatedStorage/Assets/TileMeshes. The client (Maw.lua) colours them (teeth a
wet bone white, jaws a dark flesh) because a MeshPart has one colour; without them it builds a rougher
mouth of parts, so nothing waits on the import.

=== The contract with the client ===

    HINGE    Every mesh's bounding box is centred on the jaw's hinge (Blender's origin; `anchor`
             sets the box), so in Roblox a jaw is placed at hinge * rotation with no offset, and
             opened by turning it about its own X.
    AXES     The mouth opens toward Blender +Y (Roblox -Z), the upper jaw is above (Blender +Z,
             Roblox +Y). The hinge runs along X.
    SIZES    Each mesh's Roblox size is written to maw_extents.json; Maw.lua keeps the same numbers
             in SIZE and refuses an import that does not match (an old one), and check_halls.py
             holds the two together.

Only its mouth, on purpose (LORE.md: what keeps the Hold is never seen whole).
"""

import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sealife as G  # noqa: E402  -- clear_scene, to_object, anchor, export

LENGTH = 52.0     # hinge to the tip of the upper jaw
HALF_W = 27.0     # half the upper jaw's width at the hinge
DOME = 10.0       # the dome over the upper jaw, at its highest
VAULT = 6.0       # the palate's vault inside it
GUM = 2.6         # the gum band round the rim
LOWER = 0.93      # the lower jaw, as a share of the upper
NT, NR = 44, 16   # the jaws' grid: round the rim, and in from it
SEED = 1911


def jaw_bm(scale, flip):
    """A jaw's shell: an outer dome and an inner vault over a half-ellipse, stitched at the rim and
    along the hinge. `flip` turns it over for the lower jaw."""
    L, W = LENGTH * scale, HALF_W * scale
    bm = bmesh.new()
    sign = -1.0 if flip else 1.0

    def surface(r, th, inner):
        x, y = W * r * math.sin(th), L * r * math.cos(th)
        back = 1.0 - y / L
        cap = math.sqrt(max(0.0, 1.0 - r * r))
        rim = math.exp(-((1.0 - r) / 0.09) ** 2)
        if inner:
            z = GUM * 0.2 + VAULT * cap * (0.5 + 0.5 * back)
            # The gum ridge just inside the rim, and ridges across the roof of the mouth.
            z -= 1.4 * rim
            z += 0.5 * math.sin(20.0 * y / L) * max(0.0, 1.0 - r / 0.85) ** 0.5
        else:
            # A heavy lip rolled over the rim.
            z = GUM + DOME * cap * (0.55 + 0.45 * back) + 1.8 * rim
            z = GUM + DOME * cap * (0.55 + 0.45 * back)
            # Skin: slow folds and a scatter of smaller ridges, stronger toward the back.
            z += 1.2 * noise.noise(Vector((x * 0.07, y * 0.07, 3.0))) * (0.4 + back)
            z += 0.35 * noise.noise(Vector((x * 0.3, y * 0.3, 9.0)))
        return Vector((x, y, sign * z))

    rows = {}
    for inner in (False, True):
        centre = bm.verts.new(surface(0.0, 0.0, inner))
        grid = []
        for i in range(NT + 1):
            th = -math.pi / 2 + math.pi * i / NT
            grid.append([centre] + [bm.verts.new(surface(j / NR, th, inner)) for j in range(1, NR + 1)])
        rows[inner] = grid
        for i in range(NT):
            a, b = grid[i], grid[i + 1]
            face = bm.faces.new((centre, b[1], a[1]) if not inner else (centre, a[1], b[1]))
            for j in range(1, NR):
                quad = (a[j], b[j], b[j + 1], a[j + 1]) if inner else (a[j], a[j + 1], b[j + 1], b[j])
                bm.faces.new(quad)
    top, vault = rows[False], rows[True]
    # The rim (the gum band), round the front.
    for i in range(NT):
        bm.faces.new((top[i][NR], top[i + 1][NR], vault[i + 1][NR], vault[i][NR]))
    # The hinge side: the two straight edges, top to vault, closed.
    for i in (0, NT):
        edge_top, edge_in = top[i], vault[i]
        for j in range(NR):
            quad = (edge_top[j], edge_in[j], edge_in[j + 1], edge_top[j + 1])
            bm.faces.new(quad if i == 0 else tuple(reversed(quad)))
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.0001)
    if flip:
        bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    return bm


def tooth(bm, base, inward, length, radius, bend, rng, down):
    """One fang: a cone from `base` along `down` (-Z for the upper jaw, +Z for the lower), leaning
    `inward`, curving back toward the throat over its length."""
    segments = 7
    rings = 6
    axis = Vector((0, 0, -1)) if down else Vector((0, 0, 1))
    lean = (axis + inward * 0.42 + Vector((0, -0.18, 0))).normalized()
    side = lean.cross(Vector((1, 0, 0)) if abs(lean.x) < 0.9 else Vector((0, 1, 0))).normalized()
    other = lean.cross(side).normalized()
    twist = rng.uniform(0, math.tau)
    verts = []
    for k in range(rings + 1):
        t = k / rings
        centre = base + lean * (length * t) + Vector((0, -1, 0)) * (bend * length * t * t)
        r = radius * (1 - t) ** 1.15 + 0.05
        ring = []
        for s in range(segments):
            a = twist + math.tau * s / segments
            ring.append(bm.verts.new(centre + side * (math.cos(a) * r) + other * (math.sin(a) * r * 0.8)))
        verts.append(ring)
    for k in range(rings):
        for s in range(segments):
            a, b = verts[k][s], verts[k][(s + 1) % segments]
            c, d = verts[k + 1][(s + 1) % segments], verts[k + 1][s]
            bm.faces.new((a, b, c, d))
    bm.faces.new(list(reversed(verts[0])))
    bm.faces.new(verts[rings])


def teeth_bm(scale, down, rng, offset):
    L, W = LENGTH * scale, HALF_W * scale
    bm = bmesh.new()
    gum = GUM * 0.2 * (-1 if not down else 1) * -1
    # THE LOWER TEETH ARE SHORT, and that is how the jaws shut: the long upper needles close OUTSIDE the
    # lower jaw, which fits inside them, and the lower teeth fit up into the vault of the palate.
    rows = ((0.975, 34, 1.0, 0.1), (0.86, 24, 0.6, 0.45), (0.74, 12, 0.4, 0.7)) if down else         ((0.965, 30, 0.36, 0.2), (0.85, 20, 0.28, 0.5))
    for row, (r, count, grow, tilt) in enumerate(rows):
        for k in range(count):
            if rng.random() < 0.07:
                continue  # a gap where one has gone
            th = -math.pi / 2 * 0.94 + math.pi * 0.94 * (k + 0.5 + offset) / count
            x, y = W * r * math.sin(th), L * r * math.cos(th)
            front = math.cos(th) ** 3
            length = (5.0 + 12.0 * front ** 2 + 2.0 * front) * grow * rng.uniform(0.72, 1.28) * (0.85 if not down else 1.0)
            base = Vector((x, y, gum if down else -gum))
            inward = Vector((-math.sin(th), -math.cos(th) * 0.6, 0)).normalized() * (1 + tilt)
            # Needles more than pegs: thin for their length, and curved back toward the throat.
            tooth(bm, base, inward, length, 0.13 * length + 0.3, rng.uniform(0.12, 0.3), rng, down)
    return bm


def finish(name, bm):
    """Box centred on the hinge (the origin), so Roblox's centre is the hinge."""
    lo = [min(v.co[i] for v in bm.verts) for i in range(3)]
    hi = [max(v.co[i] for v in bm.verts) for i in range(3)]
    half = [max(abs(lo[i]), abs(hi[i])) + 0.5 for i in range(3)]
    G.anchor(bm, (-half[0], -half[1], -half[2]), (half[0], half[1], half[2]))
    obj = G.to_object(name, bm, smooth=True)
    # Roblox axes: Blender (x, y, z) arrives as (x, z, -y).
    return obj, [round(2 * half[0], 2), round(2 * half[2], 2), round(2 * half[1], 2)]


def render(objects, path, open_angle):
    """A look at it, from above and in front, lit from over the shaft as it will be."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.render.resolution_x, scene.render.resolution_y = 900, 700
    for obj in objects:
        if obj.name.startswith("Maw_Upper"):
            obj.rotation_euler = (open_angle, 0, 0)
        elif obj.name.startswith("Maw_Lower"):
            obj.rotation_euler = (-open_angle * 0.8, 0, 0)
        obj.color = (0.92, 0.88, 0.78, 1) if "Teeth" in obj.name else (0.28, 0.08, 0.09, 1)
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (46, 84, 12) if open_angle > 0 else (38, 95, 30)
    target = Vector((0, 8, 0))
    cam.rotation_euler = (target - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = 30
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    rng = random.Random(SEED)
    G.clear_scene()
    extents = {}
    objects = []
    for name, bm in (
        ("Maw_UpperJaw", jaw_bm(1.0, False)),
        ("Maw_LowerJaw", jaw_bm(LOWER, True)),
        ("Maw_UpperTeeth", teeth_bm(1.0, True, rng, 0.0)),
        ("Maw_LowerTeeth", teeth_bm(LOWER, False, rng, 0.5)),
    ):
        obj, size = finish(name, bm)
        extents[name] = {"size": size, "tris": len(obj.data.polygons)}
        objects.append(obj)
    if "render" in sys.argv:
        render(objects, os.path.join(HERE, "maw_open.png"), math.radians(38))
        render(objects, os.path.join(HERE, "maw_closed.png"), 0.0)
        for obj in objects:
            obj.rotation_euler = (0, 0, 0)
    for obj in objects:
        G.export([obj], obj.name)
    with open(os.path.join(HERE, "maw_extents.json"), "w") as handle:
        json.dump(extents, handle, indent=1, sort_keys=True)
    print("maw: %s" % ", ".join("%s %s (%d tris)" % (n, e["size"], e["tris"]) for n, e in sorted(extents.items())))


main()
