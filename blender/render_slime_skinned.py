"""
Proves the slime rig deforms, and shows how its surface differs from honey's.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python render_slime_skinned.py

Renders three images:
  slime_skinned_rest.png      the surface at rest, grazing angle
  slime_skinned_pressed.png   a footfall pressed in, the same way pressNear does it
  slime_vs_honey.png          both platforms side by side

The third is the one that matters. Slime and honey are the two materials a player
is most likely to confuse, so the question is never "does the slime look good" on
its own -- it is whether the two read as different substances when seen together.
Judging either in isolation is what let them drift toward each other in the first
place.

On the first two, look for the dent falling off SMOOTHLY into the surrounding
surface. A hard-edged rectangular depression means the bone influence radius or the
weight falloff is wrong, i.e. exactly the tile problem the rig exists to remove.
"""

import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# The pose is COMPUTED the way the runtime press does: every bone within a radius of
# a point, scaled by a cos-squared falloff. Hand-picking values tells you nothing
# about whether a real press looks smooth.
PRESS_AT = (0.0, 0.0)     # world XY (Blender) of the footfall
PRESS_RADIUS = 2.4        # must match FOOT_PRESS_RADIUS in DeformationRenderer
PRESS_DEPTH = -1.0        # must match SLIME_PRESS -- shallower than honey's 1.55


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
        # Bones point along +Z, so bone-local Y is world up: a negative Y in pose
        # space presses straight down.
        bone.location = (0.0, depth, 0.0)
    bpy.context.view_layer.update()


def setup_render(filename, cam_loc, pitch, lens, colour, res=(1300, 780)):
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
    shading.color_type = colour[0]
    if colour[0] == "SINGLE":
        shading.single_color = colour[1]
    shading.show_shadows = True
    shading.show_cavity = True
    shading.cavity_type = "BOTH"

    bpy.ops.render.render(write_still=True)
    print(f"wrote {scene.render.filepath}")


def srgb(rgb):
    def channel(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (channel(rgb[0]), channel(rgb[1]), channel(rgb[2]), 1.0)


def build(gen):
    cols, rows, cell_x, cell_z = gen.compute_grid(gen.PLATFORM_X, gen.PLATFORM_Z)
    mesh_obj, top_indices, static_indices = gen.build_surface()
    arm_obj, centres = gen.build_armature(cols, rows, cell_x, cell_z)
    gen.assign_weights(mesh_obj, top_indices, static_indices, centres, cell_x, cell_z)
    return mesh_obj, arm_obj, centres


def main():
    import gen_slime_skinned as slime

    # Grazing angle: a dent is read from how the surface curves into it, which a
    # top-down view flattens away completely. Distance solved from the lens rather
    # than eyeballed -- a 16-stud platform needs 10/tan(24.2 deg) = 22 studs of
    # standoff on a 40mm lens just to fit, so the obvious-looking 20 crops it.
    cam = (0.0, -26.5, 14.1)
    slime_colour = ("SINGLE", (0.42, 0.80, 0.40))

    slime.clear_scene()
    _, arm_obj, centres = build(slime)
    setup_render("slime_skinned_rest.png", cam, 62, 40, slime_colour)

    apply_pose(arm_obj, computed_pose(centres))
    setup_render("slime_skinned_pressed.png", cam, 62, 40, slime_colour)

    # Side by side, both at rest, each in its own colour.
    import gen_honey_skinned as honey

    slime.clear_scene()
    slime_mesh, slime_arm, _ = build(slime)
    # ONLY the armature moves. assign_weights parents the mesh to the rig, so setting
    # a location on both applies the offset twice and throws the two platforms twice
    # as far apart as asked -- which reads as a framing problem rather than as the
    # placement problem it is.
    slime_arm.location = (-10.0, 0.0, 0.0)
    slime_mesh.color = srgb((110, 200, 96))

    honey_mesh, honey_arm, _ = build(honey)
    honey_arm.location = (10.0, 0.0, 0.0)
    honey_mesh.color = srgb((232, 146, 26))

    # Two 16-wide platforms 20 apart span 36 studs, which needs 18/tan(25.3 deg) =
    # 38 of standoff on a 38mm lens before any margin at all.
    setup_render("slime_vs_honey.png", (0.0, -39.0, 24.4), 58, 38,
                 ("OBJECT", None), res=(1700, 850))


main()
