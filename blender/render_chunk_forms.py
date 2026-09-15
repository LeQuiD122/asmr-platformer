"""
Renders the chunk SILHOUETTES for inspection, before any of it is pasted into Studio.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python render_chunk_forms.py

Two images:
  chunk_forms_top.png     top-down orthographic grid of all 13 chunks. Answers the
                          only question form variety is really asking: do the
                          footprints differ, or is it still 13 rectangles?
  chunk_forms_persp.png   the same grid in 3/4. Tiers are invisible from directly
                          above, so the shelves, the stepped chunks and the ramp's
                          climb all need the second view.

Layout comes from chunk_layout.py, which parses ChunkBuilder.server.lua. The
numbers that have a right answer are asserted separately by check_chunk_forms.py;
this file is for the part that is a judgement call. Run both -- passing the
contract and looking wrong are entirely compatible.

Same reasoning as render_tiles.py, applied to layout instead of to meshes: the
Studio loop for a geometry change is paste, clear ChunkTemplates and
Assets.Chunks, Play, walk over there. Looking first is minutes cheaper every time.
"""

import bpy
import mathutils
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import chunk_layout as CL

# 5 across puts 13 into 3 rows (5, 5, 3) and makes the grid wider than it is
# deep, which both cameras want: a 4-wide grid strands a single chunk on a fourth
# row, and the 3/4 camera then has to pull back far enough to frame that one
# straggler, shrinking everything else.
COLS = 5
CELL = 44.0

# Pushed apart from MaterialAppearance's real palette on purpose. Soap and bubble
# wrap sit within 10/255 of each other there, which is right in game and useless
# in a form study, where the only job colour has is telling two slabs apart.
PALETTE = {
    None: (176, 166, 190),
    "Honey": (232, 146, 26),
    "ButterWax": (238, 214, 150),
    "KineticSand": (198, 150, 88),
    "Slime": (110, 200, 96),
    "Soap": (150, 190, 230),
    "BubbleWrap": (216, 226, 236),
}


def srgb(rgb):
    def channel(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (channel(rgb[0]), channel(rgb[1]), channel(rgb[2]), 1.0)


def clear():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def add_box(box, origin):
    """Roblox (x, y, z) -> Blender (x, z, y): Roblox is Y-up, Blender is Z-up.

    The pitch carries over as a rotation about X in both, but it changes sign:
    in Roblox the +Z end of the ramp is lifted by a NEGATIVE X rotation, and the
    same lift about Blender's +Y is a positive one."""
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    obj = bpy.context.active_object
    obj.scale = (box.sx, box.sz, box.sy)
    obj.location = (box.x + origin[0], box.z + origin[1], box.y)
    obj.rotation_euler = (box.pitch, 0.0, 0.0)
    obj.color = srgb(PALETTE[box.material])
    return obj


def add_label(text, x, y):
    bpy.ops.object.text_add(location=(x, y, 0.05))
    obj = bpy.context.active_object
    obj.data.body = text
    obj.data.size = 2.6
    obj.data.align_x = "CENTER"
    obj.color = srgb((38, 34, 46))
    return obj


def scene_bounds():
    """World-space XY bounds of everything in the scene.

    Taken from bound_box through matrix_world rather than from location and
    dimensions. `dimensions` is the local bounding box scaled, with the object's
    ROTATION left out, so the pitched ramp pieces come back shorter than they
    are; and working from the boxes alone misses the labels entirely, which are
    the widest things in a cell. Both of those crop the frame."""
    lo = [1e9, 1e9]
    hi = [-1e9, -1e9]
    for obj in bpy.context.scene.objects:
        if obj.type not in ("MESH", "FONT"):
            continue
        for corner in obj.bound_box:
            world = obj.matrix_world @ mathutils.Vector(corner)
            for axis in (0, 1):
                lo[axis] = min(lo[axis], world[axis])
                hi[axis] = max(hi[axis], world[axis])
    return lo, hi


def build_grid(layouts):
    """All 13 laid out COLS-across."""
    for index, chunk_id in enumerate(CL.CHUNK_ORDER):
        boxes = layouts[chunk_id]

        # Centred in the cell on X, but anchored to the cell's near edge on Z, so
        # entry faces line up across a row and a difference in length reads as a
        # difference in length rather than as an offset.
        xs = [b.x + b.sx / 2.0 for b in boxes] + [b.x - b.sx / 2.0 for b in boxes]
        mid_x = (min(xs) + max(xs)) / 2.0

        col, row = index % COLS, index // COLS
        cell_x = (col - (COLS - 1) / 2.0) * CELL
        cell_y = -row * CELL + CELL / 2.0 - 4.0

        for box in boxes:
            add_box(box, (cell_x - mid_x, cell_y))
        add_label(chunk_id, cell_x, cell_y - 6.0)


def render(filename, res_x, res_y, camera):
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.filepath = os.path.join(HERE, filename)
    scene.render.image_settings.file_format = "PNG"

    shading = scene.display.shading
    shading.light = "STUDIO"
    # OBJECT rather than the SINGLE the mesh previews use: here the whole point is
    # telling one material's slab from the next at a glance.
    shading.color_type = "OBJECT"
    shading.show_shadows = True
    shading.show_cavity = True
    shading.cavity_type = "BOTH"

    bpy.ops.render.render(write_still=True)
    print("wrote " + scene.render.filepath)


def make_camera(name, location, rotation, ortho_scale=None, lens=42.0):
    data = bpy.data.cameras.new(name)
    if ortho_scale:
        data.type = "ORTHO"
        data.ortho_scale = ortho_scale
    else:
        data.lens = lens
    cam = bpy.data.objects.new(name, data)
    cam.location = location
    cam.rotation_euler = rotation
    bpy.context.collection.objects.link(cam)
    return cam


def main():
    layouts, contracts, consts = CL.layout_all()
    clear()
    build_grid(layouts)
    lo, hi = scene_bounds()

    centre = ((lo[0] + hi[0]) / 2.0, (lo[1] + hi[1]) / 2.0)
    span_x, span_y = hi[0] - lo[0], hi[1] - lo[1]
    print("scene spans %.1f x %.1f studs, centred on (%.1f, %.1f)"
          % (span_x, span_y, centre[0], centre[1]))

    # Both frames take their aspect from the grid rather than fixing it, so a
    # chunk growing longer costs resolution rather than getting cropped.
    width = 1700
    render("chunk_forms_top.png", width, int(width * span_y / span_x),
           make_camera("Top", (centre[0], centre[1], 200.0), (0.0, 0.0, 0.0),
                       ortho_scale=span_x * 1.05))

    # 3/4 at 48 degrees. Shallower shows the tiers better but starts hiding the
    # back rows behind the front ones, and both readings have to survive one
    # image. Distance solves the horizontal field of view for the lens, so the
    # grid frames itself whatever it grows to; the 0.6 is headroom for the
    # vertical, where perspective throws the near row lower than a flat bounding
    # box predicts and a tight fit crops the front of the grid.
    pitch = math.radians(48.0)
    lens = 40.0
    half_fov = math.atan(18.0 / lens)  # 36mm sensor
    distance = (span_x * 0.6) / math.tan(half_fov)
    render("chunk_forms_persp.png", width, int(width * 0.62),
           make_camera("Persp",
                       (centre[0],
                        centre[1] - distance * math.sin(pitch),
                        distance * math.cos(pitch)),
                       (pitch, 0.0, 0.0), lens=lens))


main()
