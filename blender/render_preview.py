"""
Renders a preview of the generated chunk meshes to a PNG.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python render_preview.py

Exists so the meshes can be inspected without opening Blender, and so whoever
wrote the generator can check the result instead of guessing at it. Uses the
Workbench engine: no material or light setup required, renders in a second or two,
and its studio shading shows silhouette and surface curvature clearly, which is
all that matters for judging form.
"""

import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

OUT_PNG = os.path.join(HERE, "preview.png")


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def main():
    import gen_chunk_meshes as gen

    clear_scene()

    honey = gen.build_slab("Honey", gen.HONEY_X, gen.HONEY_Y, 0.5, gen.honey_height, gen.honey_base)
    wrap = gen.build_slab("Wrap", gen.WRAP_X, gen.WRAP_Y, 0.24, gen.bubble_wrap_height)

    honey.location = (-10.0, 0.0, 0.0)
    wrap.location = (10.0, 0.0, 0.0)

    # Camera: high three-quarter view. Grazing enough to read the domed profile
    # and the bubble caps, which a top-down view flattens away entirely.
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = 34
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = (0.0, -40.0, 26.0)
    cam.rotation_euler = (math.radians(62), 0.0, 0.0)
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 640
    scene.render.film_transparent = False
    scene.render.filepath = OUT_PNG
    scene.render.image_settings.file_format = "PNG"

    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "SINGLE"
    shading.single_color = (0.82, 0.80, 0.86)
    shading.show_shadows = True
    shading.show_cavity = True
    shading.cavity_type = "BOTH"

    bpy.ops.render.render(write_still=True)
    print(f"wrote {OUT_PNG}")


main()
