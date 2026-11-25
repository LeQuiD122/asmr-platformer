"""
One sculpted keycap, cloned for every key of every keyboard (the hundred-and-fifty-fifth pass).

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_keycap.py
    ... -- --preview C:\\path\\to\\preview.png      (also renders a picture of three of them)

From your test of 2026-10-31: "the regular keys should have a better key movement animation, more colour palettes,
their models could look better and be less spread apart". The keyboards were one rigged field (gen_keyboard.py), a bone
to a key: one mesh has one colour, so a key could never be its own, and its caps were square blocks tapered hard to
three quarters of their base on a pitch wider than the cell, so nearly a stud of case showed between their tops.

This is the key on its own, and ChunkBuilder clones it into every cell of a keyboard (attachKeycap), sized to the cell
less a hairline seam, its top on the walkable plane. It is the shape that reads as a key from a camera's distance:

  * WALLS THAT CURVE IN, not a straight taper: a little bulge low down and in toward the top, the way a sculpted cap is
    moulded, so the light rolls round every side instead of falling off a flat facet.
  * A ROUNDED TOP EDGE, a quarter round over onto the top, so the cap catches a rim of light all round its top.
  * A DISHED TOP, a shallow spherical hollow your foot sits in, darker in the middle, lighter at the rim.
  * CORNERS that open from tight at the foot to round at the top.

Authored at the size it is used (3.05 square, 0.9 tall: SubRegionGrid's 3.2 cell on a 16-stud board less its 0.15 seam,
by ChunkBuilder's TILE_THICKNESS), so the Size ChunkBuilder forces on it scales nothing out of shape. No rig and no UVs:
the colour is the part's own (MaterialAppearance.KEYCAPS) and the letter is printed on it (a SurfaceGui), so neither
needs a texture.
"""

import bmesh
import math
import os
import sys

import bpy

OUT_DIR = r"C:\Users\Arsenii\Downloads\asmr-platformer-implementation_1\RobloxProject\meshes"
NAME = "Keycap_Sculpted"

BASE = 3.05          # the cap's foot, square
HEIGHT = 0.90        # foot to rim
TOP_SCALE = 0.885    # the rim as a share of the foot: in close enough to read as a key, out enough to keep the gaps small
WALL_CURVE = 1.2     # how the wall draws in: over 1 it stands steep low down and curves in toward the top
CORNER_FOOT = 0.42   # corner radius at the foot
CORNER_TOP = 0.50    # and at the rim
ROUND = 0.13         # the quarter round over the top edge
DISH = 0.075         # how deep the top is hollowed in the middle
WALL_RINGS = 7       # rings up the wall
ROUND_RINGS = 4      # rings round the top edge
DISH_RINGS = 6       # rings into the dish
CORNER_STEPS = 6     # chords per corner


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def ring(half, radius, z):
    """Points anticlockwise round a rounded square of half-width `half`, at height `z`."""
    radius = min(radius, half - 1e-4)
    points = []
    corners = ((half - radius, half - radius, 0.0), (-(half - radius), half - radius, math.pi / 2),
               (-(half - radius), -(half - radius), math.pi), (half - radius, -(half - radius), 3 * math.pi / 2))
    for cx, cy, start in corners:
        for step in range(CORNER_STEPS + 1):
            angle = start + (math.pi / 2) * step / CORNER_STEPS
            points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius, z))
    return points


def build():
    rings = []
    foot = BASE / 2.0
    rim_half = foot * TOP_SCALE
    wall_top = HEIGHT - ROUND
    # THE WALL: from the foot to where the round begins, steep low down and drawing in toward the top (a curve, never
    # past the foot: the cap's box is exactly its cell less the seam).
    for k in range(WALL_RINGS + 1):
        t = k / WALL_RINGS
        half = foot - (foot - rim_half) * (t ** WALL_CURVE)
        radius = CORNER_FOOT + (CORNER_TOP - CORNER_FOOT) * t
        rings.append(ring(half, radius, wall_top * t))
    # THE ROUND over the top edge: a quarter circle in from the wall's last ring onto the top.
    for k in range(1, ROUND_RINGS + 1):
        a = (math.pi / 2) * k / ROUND_RINGS
        inset = ROUND * (1 - math.cos(a))
        rings.append(ring(rim_half - inset, CORNER_TOP - inset * 0.6, wall_top + ROUND * math.sin(a)))
    top_half = rim_half - ROUND
    # THE DISH: rings drawing in to the middle, sinking as they go.
    for k in range(1, DISH_RINGS + 1):
        f = 1 - k / (DISH_RINGS + 0.5)
        z = HEIGHT - DISH * (1 - f * f)
        rings.append(ring(top_half * f, max(0.02, (CORNER_TOP - ROUND * 0.6) * f), z))

    verts, faces = [], []
    starts = []
    for points in rings:
        starts.append(len(verts))
        verts.extend(points)
    n = len(rings[0])
    for r in range(len(rings) - 1):
        a, b = starts[r], starts[r + 1]
        for k in range(n):
            nk = (k + 1) % n
            faces.append((a + k, a + nk, b + nk, b + k))
    # The middle of the dish, and the foot closed.
    centre = len(verts)
    verts.append((0.0, 0.0, HEIGHT - DISH))
    last = starts[-1]
    for k in range(n):
        faces.append((last + k, last + (k + 1) % n, centre))
    faces.append(tuple(reversed(range(starts[0], starts[0] + n))))

    mesh = bpy.data.meshes.new(NAME)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    obj = bpy.data.objects.new(NAME, mesh)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    # The foot faces down: if recalc chose the other way round, turn the lot.
    foot_face = bm.faces[-1]
    if foot_face.normal.z > 0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    # Smooth everywhere but the foot (never seen, and a smoothed foot would shade the wall's base oddly).
    for index, poly in enumerate(mesh.polygons):
        poly.use_smooth = index != len(mesh.polygons) - 1
    # Its origin in the middle of its box, as every tile mesh's is, so a Size set in Studio scales it about its centre.
    for v in mesh.vertices:
        v.co.z -= HEIGHT / 2
    mesh.update()
    return obj


def validate(obj):
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    ok = True
    width, depth, height = max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)
    if abs(width - BASE) > 0.02 or abs(depth - BASE) > 0.02 or abs(height - HEIGHT) > 0.02:
        print(f"  !! the cap is {width:.3f} x {depth:.3f} x {height:.3f}, not {BASE} x {BASE} x {HEIGHT}")
        ok = False
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-8)
    open_edges = sum(1 for e in bm.edges if not e.is_manifold)
    bm.free()
    if degenerate:
        print(f"  !! {degenerate} degenerate faces")
        ok = False
    if open_edges:
        print(f"  !! {open_edges} open edges: the cap is not closed")
        ok = False
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"  {NAME}: {width:.2f} x {depth:.2f} x {height:.2f}, {len(obj.data.vertices)} vertices, {tris} triangles")
    return ok


def export(obj):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, NAME + ".fbx")
    for other in bpy.data.objects:
        other.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, global_scale=0.01, axis_forward="-Z", axis_up="Y",
                             object_types={"MESH"}, mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False)
    print(f"  exported {os.path.basename(path)}")


def preview(obj, path):
    """Three caps on a case, lit from above and the side, for a look before importing."""
    scene = bpy.context.scene
    colours = ((0.97, 0.94, 0.89, 1), (0.93, 0.62, 0.70, 1), (0.91, 0.38, 0.55, 1))
    for index, colour in enumerate(colours):
        copy = obj.copy()
        copy.data = obj.data
        copy.location = ((index - 1) * 3.2, 0, HEIGHT / 2)
        material = bpy.data.materials.new(f"cap{index}")
        material.diffuse_color = colour
        material.use_nodes = True
        material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = colour
        material.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.45
        copy.data = obj.data.copy()
        copy.data.materials.clear()
        copy.data.materials.append(material)
        bpy.context.collection.objects.link(copy)
    obj.hide_render = True
    bpy.ops.mesh.primitive_plane_add(size=14, location=(0, 0, 0))
    case = bpy.context.active_object
    case_material = bpy.data.materials.new("case")
    case_material.use_nodes = True
    case_material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.91, 0.61, 0.68, 1)
    case.data.materials.append(case_material)
    camera_data = bpy.data.cameras.new("cam")
    camera = bpy.data.objects.new("cam", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (5.5, -8.5, 6.0)
    direction = (-camera.location[0], -camera.location[1], -camera.location[2] + 0.4)
    import mathutils
    camera.rotation_euler = mathutils.Vector(direction).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 3.5
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(35))
    bpy.context.collection.objects.link(sun)
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in
        bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 900, 600
    scene.render.filepath = path
    world = scene.world or bpy.data.worlds.new("world")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.82, 0.82, 0.86, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
    bpy.ops.render.render(write_still=True)
    print(f"  preview {path}")


def main():
    clear_scene()
    obj = build()
    ok = validate(obj)
    export(obj)
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if "--preview" in argv:
        preview(obj, argv[argv.index("--preview") + 1])
    print("")
    print("  Import meshes/Keycap_Sculpted.fbx into ReplicatedStorage/Assets/TileMeshes (a MeshPart named Keycap_Sculpted).")
    print("Done." if ok else "!! the cap failed validation -- DO NOT import.")


if __name__ == "__main__":
    main()
