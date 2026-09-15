"""
Footprint sole mesh. Blender 5.2 -> OBJ -> Roblox MeshPart.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_footprint.py

=== Why a mesh and not a GUI frame ===

The print was drawn as Frames on a SurfaceGui, which gave the shape (square heel,
arched toe) but nothing else: GUI elements are UNLIT. They receive no lighting, carry
no Material and have no Reflectance, so against a glossy honey surface a drawn print
reads as a flat sticker no matter how it is coloured.

As a MeshPart it takes the material's own appearance, so it picks up the same specular
highlight as the surface it sits in. It also sits BACK inside the depression, which the
GUI version had to give up because a SurfaceGui is a flat plane above the surface.

=== The shape ===

A stadium with one flat end: straight sides, a semicircular toe, a square heel. That is
"front two corners arched, back two square" expressed as an outline rather than as
per-corner radii, which no single primitive supports.

Dished rather than flat. A footprint in a viscous material is a shallow depression, and
the dish is what catches the light differently from the surrounding surface, which is
the entire point of making it a mesh.
"""

import bmesh
import bpy
import math
import os

OUT_DIR = r"C:\Users\Arsenii\Downloads\asmr-platformer-implementation_1\RobloxProject\meshes"

# Nominal size in studs. Scaled per-print at runtime from the foot part's own Size, so
# these only fix the PROPORTIONS.
WIDTH = 1.0
LENGTH = 1.7
DEPTH = 0.28        # how far the dish sinks below the rim
THICKNESS = 0.24    # body below the rim, so the part has substance from the side

ARC_SEGMENTS = 18   # around the toe
SIDE_SEGMENTS = 6   # up each straight side
# Concentric rings of the dish, as (inset fraction, depth fraction). Outer ring at the
# rim, centre at full depth. More than one ring keeps the dish from reading as a cone.
RINGS = ((1.0, 0.0), (0.62, 0.55), (0.28, 0.86))


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def outline():
    """
    Sole outline, counter-clockwise from the heel's left corner.

    Straight sides run to the arc's centre line, then a semicircle closes the toe. The
    heel is left as a hard edge, which is what makes the back two corners square.
    """
    half = WIDTH / 2.0
    arc_centre_y = LENGTH - half
    points = []

    # Left side, heel to the arc.
    for i in range(SIDE_SEGMENTS + 1):
        points.append((-half, arc_centre_y * i / SIDE_SEGMENTS))

    # Toe arc, left round to right, skipping the shared endpoints.
    for i in range(1, ARC_SEGMENTS):
        angle = math.pi - math.pi * i / ARC_SEGMENTS
        # No sign flip here. Negating x mirrors the arc, so the outline jumped from the
        # left side across to the right and back, self-intersecting: the mesh came out as
        # a box with a dome behind it and a visible tear.
        points.append((half * math.cos(angle), arc_centre_y + half * math.sin(angle)))

    # Right side, arc back down to the heel.
    for i in range(SIDE_SEGMENTS, -1, -1):
        points.append((half, arc_centre_y * i / SIDE_SEGMENTS))

    return points


# The SAND variant, and the berm is the whole of it.
#
# A print in a viscous material is a hollow and nothing else, because the material flows
# back in. A print in a GRANULAR one is a hollow plus the material that came out of it,
# shoved up into a lip around the rim. That lip is the only visible evidence the stuff
# was displaced rather than merely pressed, and it is what makes a print read as sand.
# Without it kinetic sand prints exactly like shallow honey, which is what it has been
# doing -- when it printed at all.
BERM_PEAK = 1.13    # where the lip crests, as a fraction of the sole outline
BERM_OUT = 1.30     # where the displaced material has fallen back to nothing
BERM_HEIGHT = 0.42  # crest height above the surface, as a fraction of DEPTH
SAND_DEPTH = 1.5    # the hollow, deeper than honey's: sand takes and holds a sharp wall

# THE SHEAR FACE, which is what makes it kinetic sand rather than sand.
#
# Kinetic sand is cohesive: it behaves like a solid until it fails, so anything pressed
# into it leaves a CLEAN VERTICAL WALL and a flat floor -- the face a knife leaves, which
# is the whole of why the ASMR reads. Honey's rings are a dish, sloping evenly from rim
# to centre, and scaling that dish deeper (which is what sand was doing) just makes a
# deeper dish. A dish is what a viscous material leaves.
#
# So sand gets its own rings: barely any inset for almost the entire drop, then a floor.
# The 0.94 is the wall -- 6% of the sole's width for 92% of its depth.
SAND_RINGS = (
    (1.00, 0.00),   # the rim, at the surface: the top edge of the cut
    (0.94, 0.92),   # straight down
    (0.80, 1.00),   # the floor begins
)


def build(sand=False):
    ring = outline()
    n = len(ring)

    # Centroid, used as the inset target so the rings shrink toward the middle of the
    # shape rather than toward the origin.
    cx = sum(p[0] for p in ring) / n
    cy = sum(p[1] for p in ring) / n

    verts = []
    faces = []

    depth_scale = SAND_DEPTH if sand else 1.0

    # Dish: concentric inset rings, then a single centre vertex. On sand the berm rings
    # come FIRST, outside the rim, so the whole surface is still one ordered fan of rings
    # from the outermost inward and the existing ring-to-ring stitch covers both.
    profile = list(RINGS)
    if sand:
        profile = [
            (BERM_OUT, 0.0),
            (BERM_PEAK, -BERM_HEIGHT),
        ] + [(inset, depth * depth_scale) for inset, depth in SAND_RINGS]

    ring_indices = []
    for inset, depth in profile:
        start = len(verts)
        for x, y in ring:
            verts.append((
                cx + (x - cx) * inset,
                cy + (y - cy) * inset,
                -DEPTH * depth,
            ))
        ring_indices.append(start)

    centre = len(verts)
    verts.append((cx, cy, -DEPTH * depth_scale))

    # Stitch ring to ring.
    for r in range(len(ring_indices) - 1):
        a, b = ring_indices[r], ring_indices[r + 1]
        for i in range(n):
            j = (i + 1) % n
            faces.append((a + i, a + j, b + j, b + i))

    # Innermost ring to the centre.
    inner = ring_indices[-1]
    for i in range(n):
        faces.append((centre, inner + (i + 1) % n, inner + i))

    # Side wall down from the OUTERMOST ring, and a flat base. Taken from the ring's own
    # inset rather than from the bare outline: on the sand variant the outermost ring is
    # the berm's outer edge, well outside the sole, and a wall dropped from the sole
    # would have hung in mid-air under the lip.
    outer_inset = profile[0][0]
    floor = -DEPTH * depth_scale - THICKNESS
    rim = ring_indices[0]
    wall_start = len(verts)
    for x, y in ring:
        verts.append((cx + (x - cx) * outer_inset, cy + (y - cy) * outer_inset, floor))
    for i in range(n):
        j = (i + 1) % n
        faces.append((rim + i, rim + j, wall_start + j, wall_start + i))

    base = len(verts)
    verts.append((cx, cy, floor))
    for i in range(n):
        faces.append((base, wall_start + i, wall_start + (i + 1) % n))

    name = "Footprint_Sand" if sand else "Footprint_Sole"
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()

    # Dish smooth, wall and base flat, so the silhouette keeps a crisp edge.
    #
    # On sand only the BERM is smoothed: it is a soft pile of loose material and should
    # read as one. The cut itself must not be, because smoothing a near-vertical wall
    # into its floor rounds off exactly the edge the shape exists to have -- it would
    # shade like a dish again however the geometry is built.
    if sand:
        dish_faces = 2 * n
    else:
        dish_faces = (len(profile) - 1) * n + n
    for index, polygon in enumerate(mesh.polygons):
        polygon.use_smooth = index < dish_faces

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    zs = [v.co.z for v in mesh.vertices]
    print(f"  {name}: {len(mesh.vertices)} verts, {tris} tris, "
          f"rises {max(zs):+.3f} / sinks {min(zs):+.3f}")
    return obj


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for sand in (False, True):
        clear_scene()
        obj = build(sand=sand)
        for other in bpy.data.objects:
            other.select_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        path = os.path.join(OUT_DIR, obj.name + ".obj")
        bpy.ops.wm.obj_export(
            filepath=path,
            export_selected_objects=True,
            export_materials=False,
            export_triangulated_mesh=True,
        )
        print(f"  exported {path}")


main()
