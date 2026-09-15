"""
Proves the honey rig deforms, and shows what a footfall looks like.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python render_honey_skinned.py

Renders honey_skinned_rest.png and honey_skinned_pressed.png. The second presses
three adjacent cell bones down, which is roughly what standing on the platform
does. The thing to look for is whether the dent falls off SMOOTHLY into the
surrounding surface: if the bone influence radius or the weight falloff were wrong
you would see a hard-edged rectangular depression, i.e. exactly the tile problem
this whole approach exists to remove.
"""

import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# The pose is COMPUTED the way pressNear does at runtime: every bone within a radius of a
# point, scaled by a cos-squared falloff. Hand-picking four values told me nothing about
# whether the real press looks smooth, which is the only question this render answers.
PRESS_AT = (0.0, 0.0)     # world XY (Blender) of the footfall
PRESS_RADIUS = 2.4        # must match FOOT_PRESS_RADIUS in DeformationRenderer
PRESS_DEPTH = -1.55       # must match HONEY_PRESS


def computed_pose(arm, centres):
    pressed = []
    for name, (cx, cy) in centres.items():
        d = math.hypot(cx - PRESS_AT[0], cy - PRESS_AT[1])
        if d <= PRESS_RADIUS:
            falloff = math.cos(math.pi * 0.5 * (d / PRESS_RADIUS)) ** 2
            amount = PRESS_DEPTH * falloff
            if abs(amount) >= 0.02:
                pressed.append((name, amount))
    return pressed


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
    shading.color_type = "SINGLE"
    shading.single_color = (0.82, 0.72, 0.48)
    shading.show_shadows = True
    shading.show_cavity = True
    shading.cavity_type = "BOTH"

    bpy.ops.render.render(write_still=True)
    print(f"wrote {scene.render.filepath}")


def main():
    import gen_honey_skinned as gen

    gen.clear_scene()
    cols, rows, cell_x, cell_z = gen.compute_grid(gen.PLATFORM_X, gen.PLATFORM_Z)
    mesh_obj, top_indices, static_indices = gen.build_surface()
    arm_obj, centres = gen.build_armature(cols, rows, cell_x, cell_z)
    gen.assign_weights(mesh_obj, top_indices, static_indices, centres, cell_x, cell_z)

    # Grazing angle: a dent is read from how the surface curves into it, which a
    # top-down view flattens away completely.
    cam = (0.0, -21.0, 11.0)
    setup_render("honey_skinned_rest.png", cam, 62, 40)

    # Bones point along +Z, so bone-local Y is world up: a negative Y in pose space
    # presses straight down.
    pose = computed_pose(arm_obj, centres)
    print(f"  pressing {len(pose)} bones within {PRESS_RADIUS} studs")
    for name, depth in pose:
        bone = arm_obj.pose.bones.get(name)
        if not bone:
            print(f"  !! no pose bone {name}")
            continue
        bone.location = (0.0, depth, 0.0)
        print(f"  pressed {name} by {depth}")

    bpy.context.view_layer.update()
    setup_render("honey_skinned_pressed.png", cam, 62, 40)


main()
