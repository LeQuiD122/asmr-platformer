"""
The solid backing under a bubble wrap sheet. Blender 5.2 -> FBX -> Roblox MeshParts.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_bubblewrap_body.py

=== Why this exists ===

Bubble wrap is the one material whose body was never a mesh. Every other platform in the
game is either a skinned surface or a field of parts, but bubble wrap is an OVERLAY: the
pocket sheet is a mesh and the solid slab it sits on is left VISIBLE, because you have to
be able to see the layer you are about to burst through. That slab is a plain Part.

A plain Part cannot carry PBR. SurfaceAppearance in this project is attached by hand to the
imported mesh TEMPLATES, and clones inherit it -- which is why every mesh in the game has
maps and nothing built at runtime does. So the only route to a textured body is for the
body to be a mesh, which is what this file makes.

=== Why one per size, and not one scaled ===

Six sizes, six exports, which is a lot of importing for one material. The alternative
was a single mesh scaled to fit, and it was rejected: box_project lays UVs out in WORLD
STUDS so that every platform shows detail at the same physical scale, and scaling a MeshPart
stretches those UVs. A single body would therefore show a different film grain on every
slab it was stretched to -- which is exactly the inconsistency the world-stud UV convention
exists to prevent.

=== The surface ===

Barely anything, and that is deliberate. This is a taut backing film seen BETWEEN pockets
and under them; it is not the thing you look at. It carries slack creases running one way,
because the sheet is pulled off a roll and the tension is directional, and nothing else.
Anything more here competes with the pockets for attention and wins, which is backwards.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import uv_project
import gen_lambs_ear as BED
import gen_butter_skinned as BUTTER
import gen_bubble_wrap as WRAP

OUT_DIR = BUTTER.OUT_DIR

# Shallow, and stretched. A film off a roll creases along the direction it was pulled, so
# the wavelength across the sheet is short and along it is long.
CREASE_DEPTH = 0.035
CREASE_ACROSS = 1.9      # studs between creases, across the roll
CREASE_ALONG = 7.5       # and along it

# MUCH COARSER THAN THE BEDS. gen_lambs_ear works at 0.12 because it has to resolve a leaf
# margin; this surface is a film whose deepest feature is 0.035 studs, and at 0.12 a 16 x 8
# body came out at 19,000 triangles to describe something that is very nearly flat. Six of
# those on one level is real cost for detail nobody can see. At 0.35 the creases -- 1.9
# studs apart at the shortest -- are still five samples wide, which is plenty.
RES = 0.35


def film_field(size_x, size_z):
    def field(x, y):
        # Two out-of-phase waves rather than one, so the creases do not line up into a
        # corduroy stripe -- a regular ribbed surface reads as manufactured trim, and this
        # is meant to read as slack.
        across = math.sin(math.tau * x / CREASE_ACROSS + math.sin(y * 0.31) * 0.8)
        along = math.sin(math.tau * y / CREASE_ALONG - 0.6)
        return CREASE_DEPTH * (across * 0.75 + along * 0.45)

    return field


def export_rigid(mesh_obj, filename):
    """No armature, unlike every other export here.

    The body does not deform. It is a backing sheet the pockets sit on, and the pockets are
    the skinned mesh -- giving this one a rig would be a second set of bones on the same
    platform for the renderer to find by world position and drive by mistake.
    """
    uv_project.box_project(mesh_obj.data, 6.0)

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, filename)
    for obj in bpy.data.objects:
        obj.select_set(False)
    mesh_obj.select_set(True)
    bpy.context.view_layer.objects.active = mesh_obj
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        global_scale=0.01,
        add_leaf_bones=False,
        bake_anim=False,
        axis_forward="-Z",
        axis_up="Y",
        object_types={"MESH"},
        mesh_smooth_type="FACE",
    )
    print(f"    exported {os.path.basename(path)}")


def mesh_name(size_x, size_z):
    return f"BubbleWrap_Body_{size_x:.0f}x{size_z:.0f}"


def build_one(size_x, size_z):
    name = mesh_name(size_x, size_z)
    BUTTER.clear_scene()
    # Borrowed topology, own resolution. build_surface reads the grid step off the module
    # it lives in, so it is swapped for the duration and put back -- leaving it changed
    # would silently coarsen the lamb's ear bed the next time anything imported it.
    previous, BED.RES = BED.RES, RES
    try:
        mesh_obj, _static, n_top = BED.build_surface(
            size_x, size_z, name, relief=film_field(size_x, size_z))
    finally:
        BED.RES = previous
    ok = BUTTER.validate_mesh(mesh_obj, n_top)

    tris = sum(len(p.vertices) - 2 for p in mesh_obj.data.polygons)
    zs = [v.co.z for v in mesh_obj.data.vertices]
    low, high = min(zs), max(zs)
    print(f"  {name}: {tris} tris, {'valid' if ok else 'INVALID'}")
    export_rigid(mesh_obj, name + ".fbx")
    entry = (f"\t\t[\"{size_x:.0f}x{size_z:.0f}\"] = "
             f"{{ height = {high - low:.2f}, offset = {high + 0.02 - (low + high) / 2.0:.2f} }},")
    return entry, ok


def main():
    sizes = WRAP.slab_sizes()
    print(f"\n  {len(sizes)} bubble wrap slab sizes, read from ChunkBuilder via chunk_layout\n")
    entries, all_ok = [], True
    for size_x, size_z in sizes:
        entry, ok = build_one(size_x, size_z)
        entries.append(entry)
        all_ok = all_ok and ok

    print("")
    print("  ChunkBuilder BODY_MESHES entry:")
    print("\tBubbleWrap = {")
    for entry in entries:
        print(entry)
    print("\t},")
    print("")
    print("Done." if all_ok else "!! a mesh failed validation -- DO NOT import.")


if __name__ == "__main__":
    main()
