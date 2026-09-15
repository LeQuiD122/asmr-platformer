"""Renders any piece of the flooded-halls kit on its own, for judging before importing.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python render_kit.py

=== Why ===

Meshes in this kit have been placed wrong more often than they have been modelled wrong, and
every one of those mistakes was a fact about the mesh that nobody had looked at: steps modelled
descending and then stood on the floor, a dome hung inside a room a third its height, a flume
whose bounding box was not centred where the placing code assumed.

So this prints the EXTENTS as well as drawing the piece, in the same world studs the Lua uses,
with the axes named the way Roblox names them. The export is z-up to y-up, so Blender (x, y, z)
arrives as Roblox (x, z, -y), and that mapping is where most of the confusion comes from.

A grey bar five studs tall stands beside each piece. That is a Roblox character; everything in
this kit is modelled at a quarter of world size and multiplied by SCALE on the way in, so the
only way to tell whether a handrail is a handrail is to put a person next to it.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# Which pieces to draw, and how much room each needs in the frame.
WANTED = [
    ("build_arch_wall", 30.0),
    ("build_ripple", 3.4),
    ("build_steps", 24.0),
    ("build_column", 30.0),
    ("build_rail", 16.0),
]

# The arch is the only piece the route passes THROUGH, so it is the only one whose render has
# to answer a question rather than show a shape: standing on the walkway, do you fit? The
# figure goes in the opening at walkway height and a plate marks the walkway itself.
THROUGH = {"build_arch_wall"}
SCALE = 4.0


def clear():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def main():
    import gen_flooded_halls as gen

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.image_settings.file_format = "PNG"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "SINGLE"
    shading.single_color = (0.78, 0.80, 0.84)
    shading.show_shadows = True
    shading.show_cavity = True
    shading.cavity_type = "BOTH"

    print("")
    print("kit extents, in WORLD studs (model size x %g), Roblox axes:" % SCALE)
    for name, span in WANTED:
        clear()
        obj = getattr(gen, name)()
        points = [v.co for v in obj.data.vertices]
        rx = (min(p.x for p in points), max(p.x for p in points))
        ry = (min(p.z for p in points), max(p.z for p in points))
        rz = (-max(p.y for p in points), -min(p.y for p in points))
        print("  %-16s X %8.1f..%8.1f   Y %8.1f..%8.1f   Z %8.1f..%8.1f"
              % (obj.name, rx[0] * SCALE, rx[1] * SCALE, ry[0] * SCALE, ry[1] * SCALE,
                 rz[0] * SCALE, rz[1] * SCALE))

        # A PERSON, at the kit's own scale. 5 studs of Roblox character is 1.25 model units.
        stand_on = ry[0]
        stand_at = rx[1] + 1.2
        if name in THROUGH:
            # In the opening, on the walkway, facing the way the route runs.
            stand_on = gen.WALKWAY_AT
            stand_at = 0.0
            bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, stand_on - 0.1))
            deck = bpy.context.active_object
            deck.name = "Walkway"
            deck.scale = (5.0, 6.0, 0.2)
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=(stand_at, 0.0, stand_on + 0.625))
        who = bpy.context.active_object
        who.name = "Person"
        who.scale = (0.5, 0.5, 1.25)

        cam_data = bpy.data.cameras.new("Cam")
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = span
        cam = bpy.data.objects.new("Cam", cam_data)
        bpy.context.collection.objects.link(cam)
        scene.camera = cam
        # AIMED AT THE PIECE'S OWN CENTRE, in all three axes.
        #
        # An ortho camera has to stand ON the line it is pointing along, so the offset is not a
        # free choice: it is the view direction backwards. For euler (64, 0, 45) that direction
        # works out as (-0.64, 0.64, -0.44), so the camera sits at the centre plus its
        # negative. Guessing the offset instead -- which the first version did, and skipped
        # centring in Blender's y entirely -- puts the piece half out of frame, pointing away.
        centre = ((rx[0] + rx[1]) / 2,
                  (min(p.y for p in points) + max(p.y for p in points)) / 2,
                  (ry[0] + ry[1]) / 2)
        aim = (0.636, -0.636, 0.438)
        cam.location = (centre[0] + aim[0] * span * 2,
                        centre[1] + aim[1] * span * 2,
                        centre[2] + aim[2] * span * 2)
        cam.rotation_euler = (math.radians(64), 0.0, math.radians(45))
        scene.render.filepath = os.path.join(HERE, "kit_%s.png" % name.replace("build_", ""))
        bpy.ops.render.render(write_still=True)
        print("      wrote kit_%s.png" % name.replace("build_", ""))


main()
