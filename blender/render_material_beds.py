"""
Close looks at the foam, clay, charcoal and cloud beds.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python render_material_beds.py

One image per material, at roughly the distance a player's own camera sits from the ground
they are standing on. That distance is the point: at platform range every one of these is a
grey rectangle, which is how the sand turtle stayed a lump through four rounds of being
looked at from too far away.

What each one has to show, or it is not done:
  foam      -- holes THROUGH a surface, with thin walls standing between them. If it reads
               as bumps rather than holes the pits are being combined with max, not min.
  clay      -- nested rings that are visibly not circular, and a few thumb dents.
  charcoal  -- flat facets meeting at sharp arrises, none of them parallel.
  cloud     -- one puffy mass. If separate balls are countable, CLOUD_K is too small.
"""

import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_material_beds as BEDS
import gen_lambs_ear as BED
import gen_butter_skinned as BUTTER

# Object colours only, so the render shows SHAPE. These are not the in-game palette and
# are not meant to be -- a convincing colour on an unconvincing surface is how a bad mesh
# survives review.
TINT = {
    "Foam": (232, 226, 210),
    "Clay": (196, 148, 118),
    "Charcoal": (74, 72, 72),
    "Cloud": (240, 243, 248),
    "Lego": (208, 62, 54),
    "LightSwitch": (238, 236, 228),
    "Chocolate": (98, 60, 34),
    "Salt": (246, 246, 244),
    "Lava": (54, 44, 48),
    "Oobleck": (232, 230, 220),
    "Buttons": (216, 74, 78),
    "Snow": (250, 252, 255),
}


def srgb(rgb):
    def channel(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return (channel(rgb[0]), channel(rgb[1]), channel(rgb[2]), 1.0)


def setup_render(filename, cam_loc, pitch, lens, res=(1100, 860)):
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
    # Cavity shading on. Flat workbench lighting hides shallow valleys, and a shallow
    # valley is exactly what a foam wall and a clay ring both are.
    shading.show_cavity = True
    shading.cavity_type = "BOTH"
    bpy.ops.render.render(write_still=True)
    print(f"wrote {os.path.basename(scene.render.filepath)}")


def draw(label, material, field, size_x, size_z, wide=False):
    BUTTER.clear_scene()
    mesh_obj, _static, _n = BED.build_surface(size_x, size_z, "probe_" + label, relief=field)
    mesh_obj.color = srgb(TINT[material])
    if wide:
        # THE WHOLE PLATFORM, which is a different question from the one the close camera
        # answers. The framing below is a macro shot: it exists to judge whether a bed's
        # TEXTURE reads, and at that distance a sculpt fills the frame and looks like an
        # abstract. A form has to be seen against the platform it sits on or there is no
        # telling how big it is.
        setup_render(f"bed_{label.lower()}.png", (0.0, -19.0, 15.0), 61.0, 42)
    else:
        # Aimed at the middle of the slab. From (0, -7, 10.5) the surface at z = 3.7 is
        # 7 studs out and 6.8 down, which is 44 degrees below horizontal.
        setup_render(f"bed_{label.lower()}.png", (0.0, -7.0, 10.5), 46.0, 50)


def main():
    size_x, size_z = BEDS.SIZE
    # `-- Lava Snow` renders just those; `-- forms` renders only the sculpted variants,
    # which is what you want when you are judging a shape rather than a texture.
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = {a for a in argv if a != "forms"}
    forms_only = "forms" in argv

    if not forms_only:
        for material, (make_field, _uv) in BEDS.RECIPES.items():
            if only and material not in only:
                continue
            draw(material, material, make_field(size_x, size_z), size_x, size_z)

    for spec in BEDS.VARIANTS:
        material, form = spec["material"], spec["form"]
        if only and material not in only:
            continue
        make_field, _uv = BEDS.RECIPES[material]
        if "div" in spec:
            make_field = lambda sx, sz, d=spec["div"]: BEDS.button_field(sx, sz, div=d)
        if "sculpt" in spec:
            make_field = BEDS.sculpted(make_field, BEDS.SCULPTS[spec["sculpt"]],
                                       spec.get("dominate", BEDS.SCULPT_DOMINATE))
        draw(f"{material}_{form}", material, make_field(size_x, size_z), size_x, size_z, wide=True)


if __name__ == "__main__":
    main()
