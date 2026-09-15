"""
Ice and jello soda meshes: the same geometry as wax/butter/slime, exported under their own
names so they can carry their own textures.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_ice_jello.py

WHY THIS FILE EXISTS AT ALL, given it generates nothing new.

Ice is a fractured shell over a smooth body, which is exactly what gen_wax_shell.py and
gen_butter_skinned.py already build -- the shard pattern has nothing butter-specific in it.
Jello is a soft rig that deforms and springs back, which is gen_slime_skinned.py. So the
right answer was to reuse those meshes, and for a while ChunkBuilder simply pointed the ice
and jello specs at the wax, butter and slime names.

That fails for one reason: a SurfaceAppearance is a child of the template MeshPart, and
both materials clone the SAME template. Sharing a mesh name means sharing a texture, so ice
would wear wax's crazing or wax would wear ice's crack network, with no third option. Two
materials that look identical are not two materials.

THE OBJECT NAME MATTERS, NOT THE FILENAME. Roblox takes a MeshPart's name from the object
inside the FBX, not from the file it arrived in -- so exporting `Wax_Shell_16x8_A` as
`Ice_Shell_16x8_A.fbx` produces a part called Wax_Shell_16x8_A that collides with the one
already imported. Everything here renames the object, its mesh data and its armature before
export, which is the whole job.

Re-run this whenever the wax, butter or slime generators change: these are copies, and a
copy that is not regenerated is a copy that has silently diverged.
"""

import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_butter_skinned as BUTTER
import gen_slime_skinned as SLIME
import gen_wax_shell as WAX


def rename(mesh_obj, arm_obj, name):
    """Rename the object, its mesh data and its rig.

    All three, because they are separate names in Blender and only the first is the one
    Roblox reads -- but leaving the other two saying "Wax" makes the file confusing to open
    later, and the armature name shows up in Studio's explorer under the imported part.
    """
    mesh_obj.name = name
    mesh_obj.data.name = name
    if arm_obj:
        arm_obj.name = name + "_Rig"
        arm_obj.data.name = name + "_Rig"


def ice_shells():
    """The cracking lid. Four plates: two variants at each of two sizes."""
    made = []
    for size_x, size_z in WAX.SIZES:
        for variant in WAX.VARIANTS:
            WAX.clear_scene()
            obj, arm, _entry, ok, _extra = WAX.build_variant(size_x, size_z, variant)
            name = f"Ice_Shell_{size_x:.0f}x{size_z:.0f}_{variant}"
            rename(obj, arm, name)
            WAX.export_fbx(obj, arm, name + ".fbx")
            made.append((name, ok))
    return made


def ice_bodies():
    """What shows through the lid once it crazes."""
    made = []
    for size_x, size_z in BUTTER.BUTTER_SIZES:
        BUTTER.clear_scene()
        mesh_obj, arm_obj, _entry, ok = BUTTER.build_variant(size_x, size_z)
        name = f"Ice_Platform_{size_x:.0f}x{size_z:.0f}"
        rename(mesh_obj, arm_obj, name)
        BUTTER.export_fbx(mesh_obj, arm_obj, name + ".fbx")
        made.append((name, ok))
    return made


def jello_body():
    """Slime's rig under another name. Mirrors gen_slime_skinned.main() without its report."""
    SLIME.clear_scene()
    cols, rows, cell_x, cell_z = SLIME.compute_grid(SLIME.PLATFORM_X, SLIME.PLATFORM_Z)
    mesh_obj, top_indices, static_indices = SLIME.build_surface()

    nx = int(round(SLIME.PLATFORM_X / SLIME.RES)) + 1
    ny = int(round(SLIME.PLATFORM_Z / SLIME.RES)) + 1
    ok = SLIME.validate_mesh(mesh_obj, (nx - 1) * (ny - 1))

    arm_obj, centres = SLIME.build_armature(cols, rows, cell_x, cell_z)
    SLIME.assign_weights(mesh_obj, top_indices, static_indices, centres, cell_x, cell_z)

    name = "Jello_Platform_Skinned"
    rename(mesh_obj, arm_obj, name)
    SLIME.export_fbx(mesh_obj, arm_obj, name + ".fbx")
    return [(name, ok)]


def main():
    made = []
    made += ice_shells()
    made += ice_bodies()
    made += jello_body()

    print("")
    all_ok = True
    for name, ok in made:
        print(f"  {name}: {'valid' if ok else 'INVALID'}")
        all_ok = all_ok and ok

    print("")
    print("  Import these alongside the wax/butter/slime originals -- they are separate")
    print("  MeshParts with separate names, so each can carry its own SurfaceAppearance.")
    print("  Ice uses Ice_Color/Normal/Roughness, jello uses Jello_Color/Normal/Roughness.")
    print("")
    print("Done." if all_ok else "!! a mesh failed validation -- DO NOT import.")


if __name__ == "__main__":
    main()
