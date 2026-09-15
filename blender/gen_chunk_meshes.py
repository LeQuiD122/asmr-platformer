"""
Chunk mesh generator for the ASMR platformer. Blender 5.2.

Run headless:
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_chunk_meshes.py

Or open it in Blender's Scripting workspace and press Run Script, which builds the
objects in the open scene so you can look at them before exporting.

=== Design notes ===

Modelled in Blender's Z-up convention. The OBJ exporter's defaults
(forward = -Z, up = Y) convert to Roblox's Y-up on the way out, so no manual
axis juggling is needed.

Units are studs: 1 Blender unit = 1 stud. Dimensions match the Luau chunk
definitions in ChunkBuilder.server.lua so the meshes drop in at 1:1.

Roblox caps a MeshPart at 10,000 triangles. Both meshes are built well under
that and the script prints actual counts so a resolution bump cannot silently
break the upload. The saving that makes this affordable is the underside: the
top is a fine heightfield, but the bottom is a single triangle fan from one
centre vertex, because nobody ever sees it.

Normals are recalculated by bmesh rather than being hand-wound, so face winding
in the builders below does not have to be correct.
"""

import bmesh
import bpy
import math
import os

OUT_DIR = r"C:\Users\Arsenii\Downloads\asmr-platformer-implementation_1\RobloxProject\meshes"


# --------------------------------------------------------------------------- #
# Scene helpers
# --------------------------------------------------------------------------- #

def clear_scene():
    """Empty the scene. Background Blender starts with a cube, camera and light."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def smoothstep(edge0, edge1, x):
    if edge1 <= edge0:
        return 0.0 if x < edge0 else 1.0
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


# --------------------------------------------------------------------------- #
# Slab builder
# --------------------------------------------------------------------------- #

def build_slab(name, size_x, size_y, res, height_fn, base_fn=None):
    """
    Heightfield top, extruded down to a base.

    height_fn(u, v, x, y) -> z, where u/v are normalised 0..1 across the slab and
    x/y are stud coordinates measured from the centre. Returning 0 at the border
    is what closes the silhouette cleanly against the side wall.

    base_fn(t) -> z, optional, where t is normalised position 0..1 around the
    perimeter. Lets the bottom edge dip below the base plane, which is how a
    viscous material gets drips hanging over its rim. Without it the underside is
    flat at z = 0.
    """
    nx = max(2, int(round(size_x / res))) + 1
    ny = max(2, int(round(size_y / res))) + 1

    verts = []
    faces = []

    for j in range(ny):
        for i in range(nx):
            u = i / (nx - 1)
            v = j / (ny - 1)
            x = (u - 0.5) * size_x
            y = (v - 0.5) * size_y
            verts.append((x, y, height_fn(u, v, x, y)))

    def top(i, j):
        return j * nx + i

    for j in range(ny - 1):
        for i in range(nx - 1):
            faces.append((top(i, j), top(i + 1, j), top(i + 1, j + 1), top(i, j + 1)))

    top_face_count = len(faces)

    # Perimeter ring, walked counter-clockwise seen from above.
    ring = []
    for i in range(nx - 1):
        ring.append(top(i, 0))
    for j in range(ny - 1):
        ring.append(top(nx - 1, j))
    for i in range(nx - 1, 0, -1):
        ring.append(top(i, ny - 1))
    for j in range(ny - 1, 0, -1):
        ring.append(top(0, j))

    # Side wall: the ring projected down to the base plane, optionally sagging.
    wall = []
    ring_count = len(ring)
    for k, idx in enumerate(ring):
        x, y, _ = verts[idx]
        base_z = base_fn(k / ring_count) if base_fn else 0.0
        wall.append(len(verts))
        verts.append((x, y, base_z))

    n = len(ring)
    for k in range(n):
        faces.append((ring[k], ring[(k + 1) % n], wall[(k + 1) % n], wall[k]))

    # Underside as a fan rather than a matching grid: same silhouette, a few
    # hundred triangles instead of a few thousand.
    centre = len(verts)
    verts.append((0.0, 0.0, 0.0))
    for k in range(n):
        faces.append((centre, wall[k], wall[(k + 1) % n]))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()

    # Smooth shading on the organic top only; the wall and base stay faceted so
    # the silhouette keeps a crisp edge.
    for index, polygon in enumerate(mesh.polygons):
        polygon.use_smooth = index < top_face_count

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    # Outward normals, so winding above does not have to be right.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    print(f"  {name}: {len(mesh.vertices)} verts, {tris} tris")
    if tris > 10000:
        print(f"  !! {name} exceeds Roblox's 10000-triangle MeshPart limit")

    return obj


# --------------------------------------------------------------------------- #
# Chunk 1: honey
# --------------------------------------------------------------------------- #

HONEY_X, HONEY_Y = 16.0, 18.0   # matches P1_HoneyCorridor
HONEY_THICK = 1.35
HONEY_DOME = 0.3
HONEY_BEAD = 0.34

# Drips hanging over the rim: (position around the perimeter 0..1, depth in studs).
# These do more for reading as honey than anything on the top surface does. A flat
# pool with a rounded edge is physically right but reads as a stick of butter,
# because "thick liquid" is communicated by sag, and sag only shows at an edge.
# Hand-placed rather than random so the spacing stays uneven without clustering.
HONEY_DRIPS = (
    (0.06, 2.0),
    (0.21, 1.15),
    (0.38, 2.6),
    (0.52, 1.4),
    (0.69, 2.2),
    (0.83, 1.0),
    (0.94, 1.7),
)
DRIP_WIDTH = 0.024  # as a fraction of the perimeter; ~1.4 studs on this slab


def honey_base(t):
    z = 0.0
    for position, depth in HONEY_DRIPS:
        d = abs(t - position)
        d = min(d, 1.0 - d)  # perimeter wraps
        z -= depth * math.exp(-((d / DRIP_WIDTH) ** 2))
    return z


def honey_height(u, v, x, y):
    """
    A thick pour that has settled.

    The shape that matters is the MENISCUS: a viscous liquid does not taper to a
    feather edge, it holds a raised bead just inside the rim where surface tension
    pulls against the substrate. Without that bead a domed slab reads as an
    inflated plastic pillow, which is exactly what the first version looked like.

    So: a tight roll-off at the very edge, a ridge just inside it, then the broad
    dome across the middle.
    """
    edge = min(min(u, 1.0 - u), min(v, 1.0 - v)) * 2.0

    # Tight edge roll (was 0.22, which rounded over nearly 2 studs).
    rim = smoothstep(0.0, 0.09, edge)

    # Meniscus ridge, peaking a short way in from the border.
    bead = HONEY_BEAD * math.exp(-(((edge - 0.10) / 0.075) ** 2))

    # Deliberately shallow. A liquid LEVELS: a 16-stud-wide pool 1.4 studs deep is
    # physically almost flat, and a pronounced dome across it reads as a stuffed
    # cushion. The thickness and the rim bead carry the "thick liquid" read; the
    # dome is only here to stop the middle looking machined.
    dome = HONEY_DOME * math.sin(math.pi * u) * math.sin(math.pi * v)

    # Very slight. At 0.11 this produced a quilted, fabric-like cross-hatch.
    ripple = 0.035 * math.sin(x * 0.62) * math.cos(y * 0.48)

    # Concentric pour rings, fading out from the centre. This is the other
    # unmistakable honey cue: something thick was poured in one spot and the
    # standing waves froze before they levelled. Cross-hatched noise cannot say
    # that; only radial rings can.
    radial = math.hypot(x, y)
    rings = 0.075 * math.sin(radial * 1.75) * (1.0 - smoothstep(1.5, 8.5, radial))

    return HONEY_THICK * rim + bead * rim + dome + (ripple + rings) * rim


# --------------------------------------------------------------------------- #
# Chunk 2: bubble wrap
# --------------------------------------------------------------------------- #

WRAP_X, WRAP_Y = 16.0, 12.0     # matches C4's bubble wrap section
WRAP_SHEET = 0.42

# Bubble size is driven by SAMPLING, not by taste. A radial bump on a square grid
# needs roughly 8 samples across its diameter or the grid's 4-fold symmetry shows
# through and every dome renders as a pyramid. At 0.24-stud resolution that means
# a diameter of about 2 studs, so the period has to be large enough to hold one.
# Earlier values (1.4-stud bubbles at 0.26 res, about 5 samples) produced cones.
BUBBLE_PERIOD = 2.2
BUBBLE_RISE = 0.55
BUBBLE_FILL = 0.45   # bubble radius as a fraction of the lattice period


def bubble_wrap_height(u, v, x, y):
    """
    Sheet thickness plus a lattice of bubble caps.

    The cap profile is cos-squared, NOT a true sphere. A sphere cap has a vertical
    tangent where it meets the sheet, so neighbouring caps collide in a hard X-shaped
    ridge and each dome reads as a faceted pyramid. cos-squared flattens to zero
    slope at the rim, so caps blend into the film and stay round even at a
    resolution where a sphere would look creased.

    Radius is also well under half the period, leaving visible flat film between
    bubbles. Bubbles that touch look like an egg carton; bubbles with gaps look
    like bubble wrap.

    Caps are only raised where a whole one fits, so the border is plain film
    instead of a row of sliced-open domes.
    """
    edge = min(min(u, 1.0 - u), min(v, 1.0 - v)) * 2.0
    rim = smoothstep(0.0, 0.06, edge)
    base = WRAP_SHEET * rim

    inset = smoothstep(0.05, 0.16, edge)
    if inset <= 0.0:
        return base

    cx = (math.floor(x / BUBBLE_PERIOD) + 0.5) * BUBBLE_PERIOD
    cy = (math.floor(y / BUBBLE_PERIOD) + 0.5) * BUBBLE_PERIOD
    r = math.hypot(x - cx, y - cy)
    radius = BUBBLE_PERIOD * BUBBLE_FILL
    if r >= radius:
        return base

    cap = BUBBLE_RISE * math.cos(math.pi * 0.5 * (r / radius)) ** 2
    return base + cap * inset


# --------------------------------------------------------------------------- #
# Export
# --------------------------------------------------------------------------- #

def export_obj(obj, filename):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, filename)

    for other in bpy.data.objects:
        other.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

    bpy.ops.wm.obj_export(
        filepath=path,
        export_selected_objects=True,
        export_materials=False,
        export_triangulated_mesh=True,
        apply_modifiers=True,
    )
    print(f"  exported {path}")


def main():
    clear_scene()
    print("Building chunk meshes...")

    honey = build_slab("Honey_Corridor", HONEY_X, HONEY_Y, 0.5, honey_height, honey_base)
    wrap = build_slab("BubbleWrap_Sheet", WRAP_X, WRAP_Y, 0.24, bubble_wrap_height)

    export_obj(honey, "Honey_Corridor.obj")
    export_obj(wrap, "BubbleWrap_Sheet.obj")

    print("Done.")


main()
