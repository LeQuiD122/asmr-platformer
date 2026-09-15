"""Renders the flume on its own, from three sides, so it can be judged before it is imported.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python render_slide.py

THE PREVIOUS TWO FLUMES WERE SHIPPED WITHOUT LOOKING AT THEM, and both were wrong in ways one
glance would have caught: the first was a torn shard, the second sat twenty studs under the
floor it was supposed to land on. A mesh nobody has seen is a guess.

Three views, because the failures were different in each. The ELEVATION shows the drop and
whether the tube ends where it should. The PLAN shows the helix reading as a helix rather than
as a bend. The THREE-QUARTER is what it will actually look like from across the chamber, which
is the only view a player ever gets.

A stand-in figure is drawn at the mouth: two boxes, roughly five studs of person at the kit's
own scale. The flume is the one piece here sized around a body rather than around a bay, and
without something body-sized in shot there is no way to tell whether the bore is a tube you sit
in or a gutter you straddle.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

OUT_PNG = os.path.join(HERE, "slide.png")


def clear():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def box(name, size, at):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    made = bpy.context.active_object
    made.name = name
    made.scale = size
    return made


def main():
    import gen_flooded_halls as gen

    clear()
    slide = gen.build_slide()

    # The rider, at the mouth. Radius and bore mirrored from build_slide; a Roblox character is
    # about 5 studs tall, which is 1.25 at the kit's scale of 4.
    radius, bore = 9.0, 3.4
    stand_at = (radius, 0.0, -bore + 0.6)
    box("Legs", (0.5, 0.5, 0.8), (stand_at[0], stand_at[1], stand_at[2] + 0.4))
    box("Body", (0.6, 0.45, 0.7), (stand_at[0], stand_at[1], stand_at[2] + 1.15))

    # The floor the mouth is supposed to be level with, so a flume that sits too high or too
    # low says so rather than looking fine in isolation.
    box("Apron", (5.0, 3.0, 0.1), (radius - 2.5, 0.0, -bore - 0.05))

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    # SQUARE, and that is not a detail. ortho_scale sets the LARGER screen dimension, so a wide
    # frame around a tall object crops the object rather than the background -- the first pass
    # rendered the middle third of the flume and nothing else, which is exactly as useful as
    # not rendering it.
    scene.render.resolution_x = 1000
    scene.render.resolution_y = 1000
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"

    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "SINGLE"
    shading.single_color = (0.78, 0.80, 0.84)
    shading.show_shadows = True
    shading.show_cavity = True
    shading.cavity_type = "BOTH"

    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam

    # Framed on the flume's own middle, which is half its drop down rather than the origin.
    deep = -13.0
    views = [
        ("elevation", (0.0, -90.0, deep), (math.radians(90), 0.0, 0.0), 44.0),
        ("plan", (0.0, 0.0, 70.0), (0.0, 0.0, 0.0), 34.0),
        ("three-quarter", (60.0, -60.0, 34.0), (math.radians(60), 0.0, math.radians(45)), 52.0),
    ]
    for name, where, facing, span in views:
        cam.location = where
        cam.rotation_euler = facing
        cam_data.ortho_scale = span
        scene.render.filepath = os.path.join(HERE, "slide_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        print("wrote slide_%s.png" % name)

    tris = sum(len(p.vertices) - 2 for p in slide.data.polygons)
    bounds = [v.co for v in slide.data.vertices]
    print("    %d tris, x %.1f..%.1f  y %.1f..%.1f  z %.1f..%.1f"
          % (tris,
             min(v.x for v in bounds), max(v.x for v in bounds),
             min(v.y for v in bounds), max(v.y for v in bounds),
             min(v.z for v in bounds), max(v.z for v in bounds)))
    print("    the bounding box has to be square across and exactly the drop deep, or the Lua")
    print("    cannot place it from its centre.")


main()
