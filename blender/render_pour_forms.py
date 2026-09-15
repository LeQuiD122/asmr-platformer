"""The honey and slime form variants, framed so the whole platform is in shot.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python render_pour_forms.py

Separate from render_material_beds because honey and slime do not share the bed pipeline:
each has its own surface builder, its own rim and its own drips, so there is no `relief`
callback to hand a field to. What they DO share is the sculpt vocabulary and the camera, and
both of those are imported rather than restated.

The camera is the WIDE one. The close framing the bed renderer defaults to is for judging a
texture, and at that distance a sculpt fills the frame and reads as an abstract -- a form has
to be seen against the platform it stands on or there is no telling how big it is.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_honey_skinned as HONEY
import gen_slime_skinned as SLIME
import gen_material_beds as BEDS
import render_material_beds as SHEET

# Object colours only, so the render shows SHAPE rather than material. Close enough to the
# in-game hues to tell the two apart at a glance and no closer.
TINT = {"honey": (0.86, 0.58, 0.14), "slime": (0.44, 0.80, 0.36)}


def draw(label, tint, mesh_obj):
    """Placed by aiming at the mesh, not by nudging a constant until it looks right.

    Two attempts got this wrong the same way. The bed renderer's wide camera is a fixed
    POSITION with a fixed pitch, and a slime rig is nearly eight studs tall against a bed's
    four -- so slime overflowed the frame. Backing the camera off further did not help,
    because the pitch is fixed: moving the camera up and back along the wrong line just aims
    it past the platform entirely, which is what the second attempt did.

    `pitch` is the angle between the view direction and straight down, so the view runs along
    (0, sin p, -cos p). Putting the camera at `target - D * that` aims it AT the target by
    construction, whatever the target's height turns out to be. D comes from the horizontal
    field of view at this focal length and the width that has to fit in it.
    """
    mesh_obj.color = (tint[0], tint[1], tint[2], 1.0)
    zs = [v.co.z for v in mesh_obj.data.vertices]
    pitch, lens = 61.0, 42.0

    # 22 studs across a 36mm sensor at this focal length. The platform is 16 wide, so that
    # leaves a rim of clear space either side rather than a shape running off the edge.
    half_fov = math.atan2(18.0, lens)
    distance = 11.0 / math.tan(half_fov)

    angle = math.radians(pitch)
    target_z = max(zs)
    SHEET.setup_render(
        f"pour_{label}.png",
        (0.0, -distance * math.sin(angle), target_z + distance * math.cos(angle)),
        pitch, lens)

def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = set(argv) or None

    for size_x, size_z, name, form in HONEY.SIZES:
        if not form or (only and form not in only):
            continue
        HONEY.PLATFORM_X, HONEY.PLATFORM_Z = size_x, size_z
        HONEY.SCULPT = BEDS.SCULPTS[form](size_x, size_z)
        HONEY.clear_scene()
        mesh_obj, _top, _static = HONEY.build_surface(name)
        draw(f"honey_{form}", TINT["honey"], mesh_obj)

    for form, name in SLIME.FORMS:
        if not form or (only and form not in only):
            continue
        SLIME.SCULPT = BEDS.SCULPTS[form](SLIME.PLATFORM_X, SLIME.PLATFORM_Z)
        SLIME.clear_scene()
        mesh_obj, _top, _static = SLIME.build_surface()
        draw(f"slime_{form}", TINT["slime"], mesh_obj)


if __name__ == "__main__":
    main()
