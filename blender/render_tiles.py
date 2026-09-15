"""
Renders the tile meshes for inspection.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python render_tiles.py

Two images:
  tiles_preview.png   every tile laid out in a row, to judge each in isolation
  tiles_matched.png   a 3x3 block of edge-matched honey tiles (corners, edges,
                      interior, correctly rotated) to check the seams actually
                      close. Judging an edge-matched tile on its own is pointless:
                      the whole question is whether neighbours meet flush.
"""

import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def setup_render(filename, res_x, res_y, cam_loc, cam_pitch, lens):
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.lens = lens
    cam = bpy.data.objects.new("Cam", cam_data)
    cam.location = cam_loc
    cam.rotation_euler = (math.radians(cam_pitch), 0.0, 0.0)
    bpy.context.collection.objects.link(cam)
    bpy.context.scene.camera = cam

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.filepath = os.path.join(HERE, filename)
    scene.render.image_settings.file_format = "PNG"

    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "SINGLE"
    shading.single_color = (0.80, 0.78, 0.84)
    shading.show_shadows = True
    shading.show_cavity = True
    shading.cavity_type = "BOTH"

    bpy.ops.render.render(write_still=True)
    print(f"wrote {scene.render.filepath}")


def clear():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def render_row():
    import gen_tile_meshes as gen
    clear()
    built = gen.build_all()

    # 5 x 2 grid rather than one long row. A row of ten needs the camera so far
    # back that each tile lands ~100px wide, which is useless for judging surface
    # detail; a grid keeps them large enough to actually see.
    cols, spacing = 5, 4.4
    for index, (obj, _) in enumerate(built):
        col, row = index % cols, index // cols
        obj.location = ((col - (cols - 1) / 2.0) * spacing, -row * spacing, 0.0)

    setup_render("tiles_preview.png", 1600, 800, (0.0, -22.0, 18.0), 48, 40)


def render_matched(label="Honey", bead=0.55, amp=0.12, seed=311, drips="HONEY_DRIPS",
                   filename="tiles_matched.png"):
    """3x3 of edge-matched tiles, rotated so the outer sides face out. Seam check.

    Parameterised because soap joined honey and slime as an edge-matched material.
    Judging an edge-matched tile on its own is pointless: the whole question is
    whether neighbours meet flush, and soap has to meet flush across a whole
    platform or the bar reads as a field of tiles."""
    import gen_tile_meshes as gen
    clear()

    drip_set = getattr(gen, drips) if drips else None
    interior = gen.make_continuous_height((), bead, amp, seed)
    edge_h = gen.make_continuous_height(("-y",), bead, amp, seed)
    corner_h = gen.make_continuous_height(("-y", "-x"), bead, amp, seed)
    edge_b = gen.make_drip_base(("-y",), drip_set) if drip_set else None
    corner_b = gen.make_drip_base(("-y", "-x"), drip_set) if drip_set else None

    T = gen.TILE
    # (col, row) -> (variant, z-rotation in degrees).
    #
    # Edge is authored with its outer side on -y; a rotation of theta about Z maps
    # that side to:  0 -> -y,  90 -> +x,  180 -> +y,  270 -> -x.
    # Corner is authored with outer sides on -y and -x, mapping to:
    #   0 -> (-y,-x),  90 -> (+x,-y),  180 -> (+y,+x),  270 -> (-x,+y).
    #
    # An earlier version of this table used +90 for the left column, which points
    # the meniscus at +x, i.e. inward. This exact table is what ChunkBuilder needs
    # on the Luau side, so it is worth having verified here first.
    layout = {
        (0, 0): ("corner", 0),   (1, 0): ("edge", 0),   (2, 0): ("corner", 90),
        (0, 1): ("edge", 270),   (1, 1): ("interior", 0), (2, 1): ("edge", 90),
        (0, 2): ("corner", 270), (1, 2): ("edge", 180), (2, 2): ("corner", 180),
    }

    for (col, row), (variant, rot) in layout.items():
        if variant == "interior":
            obj = gen.build(f"I_{col}{row}", T, T, 0.15, interior)
        elif variant == "edge":
            obj = gen.build(f"E_{col}{row}", T, T, 0.15, edge_h, edge_b)
        else:
            obj = gen.build(f"C_{col}{row}", T, T, 0.15, corner_h, corner_b)
        obj.location = ((col - 1) * T, (row - 1) * T, 0.0)
        obj.rotation_euler = (0.0, 0.0, math.radians(rot))

    setup_render(filename, 1100, 750, (0.0, -11.0, 8.0), 56, 40)


render_row()
render_matched()
