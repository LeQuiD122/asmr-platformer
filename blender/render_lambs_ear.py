"""
Shows whether the lamb's ear bed reads as LEAVES.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python render_lambs_ear.py

Renders three images:
  lambs_ear_rest.png      the bed at rest, grazing angle
  lambs_ear_pressed.png   a footfall pressed in, the way the runtime press does it
  lambs_ear_close.png     one corner at close range, to judge a single leaf

The third is the one that decides it. This material lives or dies on whether a viewer
can pick out INDIVIDUAL leaves lying over each other, and at platform distance a bed of
leaves and a bed of lumps look identical -- which is how the sand turtle stayed a lump
through several rounds of looking at it from too far away.

What to look for, in order:
  - separate leaves, with a visible rim where one lies over another. If it reads as a
    single undulating blanket, SMOOTH_K is too large or LEAF_LIFT too small.
  - the midrib groove running the length of a leaf, not across it.
  - no bald patches. A gap in the bed reads as a hole in the platform; the generator
    prints a coverage percentage for this and it should be in the mid nineties.
  - no rows or columns. The scatter is a jittered grid and a grid that survives its
    jitter is the one thing this project has rejected most often.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_lambs_ear as LEAF

# Matched to the runtime press so the picture shows what a player will see, not a pose
# chosen to flatter the rig. See LAMBS.press in DeformationRenderer.
PRESS_AT = (0.0, 0.0)
PRESS_RADIUS = 2.4
PRESS_DEPTH = -1.15


def computed_pose(centres, depth=PRESS_DEPTH, at=PRESS_AT):
    pressed = []
    for name, (cx, cy) in centres.items():
        d = math.hypot(cx - at[0], cy - at[1])
        if d <= PRESS_RADIUS:
            falloff = math.cos(math.pi * 0.5 * (d / PRESS_RADIUS)) ** 2
            amount = depth * falloff
            if abs(amount) >= 0.02:
                pressed.append((name, amount))
    return pressed


def apply_pose(arm_obj, pose):
    for name, depth in pose:
        bone = arm_obj.pose.bones.get(name)
        if not bone:
            print(f"  !! no pose bone {name}")
            continue
        # Bones point along +Z, so bone-local Y is world up.
        bone.location = (0.0, depth, 0.0)
    bpy.context.view_layer.update()


def srgb(rgb):
    def channel(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (channel(rgb[0]), channel(rgb[1]), channel(rgb[2]), 1.0)


def setup_render(filename, cam_loc, pitch, lens, res=(1300, 780)):
    for obj in list(bpy.data.objects):
        if obj.type == "CAMERA":
            bpy.data.objects.remove(obj, do_unlink=True)

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = cam_loc
    cam.rotation_euler = (math.radians(pitch), 0.0, 0.0)
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.filepath = os.path.join(HERE, filename)
    scene.render.image_settings.file_format = "PNG"

    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "OBJECT"
    shading.show_shadows = True
    # CAVITY ON, and it is not decoration. Workbench with flat lighting hides exactly
    # the creases this mesh is judged on -- the seam where one leaf lies over another is
    # a shallow valley, and without cavity shading the bed looks smooth whatever it is
    # actually doing.
    shading.show_cavity = True
    shading.cavity_type = "BOTH"

    bpy.ops.render.render(write_still=True)
    print(f"wrote {scene.render.filepath}")


def build(size_x, size_z):
    name = LEAF.mesh_name(size_x, size_z)
    cols, rows, cell_x, cell_z = LEAF.BUTTER.compute_grid(size_x, size_z)
    mesh_obj, static, _n_top = LEAF.build_surface(size_x, size_z, name)
    arm_obj, centres = LEAF.BUTTER.build_armature(size_x, size_z, cols, rows, name + "_Rig")
    LEAF.BUTTER.assign_weights(mesh_obj, arm_obj, static, centres, cell_x, cell_z)
    mesh_obj.color = srgb((172, 183, 148))
    return mesh_obj, arm_obj, centres


def main():
    size_x, size_z = 16.0, 8.0

    # Grazing, and solved rather than eyeballed: a 16 stud slab on a 40mm lens needs
    # about 22 studs of standoff to fit at all.
    far = (0.0, -26.5, 14.1)

    LEAF.BUTTER.clear_scene()
    _, arm_obj, centres = build(size_x, size_z)
    setup_render("lambs_ear_rest.png", far, 62, 40)

    apply_pose(arm_obj, computed_pose(centres))
    setup_render("lambs_ear_pressed.png", far, 62, 40)

    # CLOSE, over one corner. Roughly the distance a player's own camera sits from the
    # ground they are standing on, which is the only view that decides whether this is a
    # leaf or a lump.
    LEAF.BUTTER.clear_scene()
    build(size_x, size_z)
    # Aimed at the middle of the slab, not past its near edge. From (0, -7, 10) the
    # centre at (0, 0, 4) is 7 studs out and 6 down, so the camera pitches 40.6 degrees
    # below horizontal, which is 49.4 from Blender's straight-down zero.
    setup_render("lambs_ear_close.png", (0.0, -7.0, 10.0), 49.4, 50, res=(1100, 900))


if __name__ == "__main__":
    main()
