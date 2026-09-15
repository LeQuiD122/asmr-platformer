"""
Renders the SHAPED material variants, so the shape can be judged before anyone imports it.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python render_forms.py

Two images per form:
  <form>_top.png     top-down orthographic. The platformer camera looks down at a
                     shallow angle, so this is close to how the shape is actually read,
                     and it is the view that answers "is that a turtle".
  <form>_persp.png   3/4, which is the only view that shows how far the relief stands
                     proud of the bed -- and therefore how much the player will appear
                     to sink into it or float over it.

This exists because the sculpted forms are the first meshes in the project whose whole
purpose is to be RECOGNISED. A wrong bubble profile looks like slightly wrong bubble
wrap; a wrong turtle looks like a lump, and no amount of correct triangle counts or
passing validators will tell you which one you have. The check scripts assert the things
with right answers. This one is for the judgement call.

Lit low and from the side ON PURPOSE. The sand turtle's strongest cue is the channel dug
around its silhouette, and a channel is only visible as a shadow -- rendered under a
high, soft key light the entire sculpture flattens into a faint stain and looks like a
failure when it is not.
"""

import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_bubble_wrap as WRAP
import gen_keyboard as KEYS
import gen_sand_surface as SAND

OUT = HERE

# Kinetic sand, roughly MaterialAppearance's colour. Not pushed apart from the real
# palette the way the form study does it: here the question is whether the shape reads
# in the colour it will actually be, and a helpful false contrast would answer the wrong
# question.
SAND_RGB = (198, 150, 88)
# Bubble wrap: near white and glossy, so the pockets read by their highlights.
WRAP_RGB = (216, 226, 236)
# Warm ivory, matching MaterialAppearance.CreamyKeyboard.
KEY_RGB = (238, 230, 216)


def srgb(rgb):
    def channel(v):
        v = v / 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4

    return (channel(rgb[0]), channel(rgb[1]), channel(rgb[2]), 1.0)


def surface_material(name, rgb, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(rgb)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def light_the_scene():
    # A low key light for the shadows the grooves live in, plus a dim fill so the
    # shadowed side does not go to black and hide the flippers.
    key = bpy.data.lights.new("Key", type="SUN")
    key.energy = 4.0
    key.angle = math.radians(3.0)
    key_obj = bpy.data.objects.new("Key", key)
    key_obj.rotation_euler = (math.radians(52.0), 0.0, math.radians(38.0))
    bpy.context.collection.objects.link(key_obj)

    fill = bpy.data.lights.new("Fill", type="SUN")
    fill.energy = 1.1
    fill_obj = bpy.data.objects.new("Fill", fill)
    fill_obj.rotation_euler = (math.radians(60.0), 0.0, math.radians(220.0))
    bpy.context.collection.objects.link(fill_obj)

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.06, 0.08, 1.0)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    bpy.context.scene.world = world


def camera_top(size_x, size_z):
    cam = bpy.data.cameras.new("Top")
    cam.type = "ORTHO"
    # 1.25, not 1.08: a wrapped sheet is legitimately wider than its slab (meshPad
    # is 2.86 on the giant one) and the tighter frame sliced the outer pockets off.
    cam.ortho_scale = max(size_x, size_z) * 1.25
    obj = bpy.data.objects.new("Top", cam)
    obj.location = (0.0, 0.0, 40.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.collection.objects.link(obj)
    return obj


def camera_persp(size_x, size_z):
    cam = bpy.data.cameras.new("Persp")
    cam.lens = 55.0
    obj = bpy.data.objects.new("Persp", cam)
    span = max(size_x, size_z)
    obj.location = (span * 1.05, -span * 1.45, span * 1.00)
    obj.rotation_euler = (math.radians(58.0), 0.0, math.radians(35.0))
    bpy.context.collection.objects.link(obj)
    return obj


def render(camera, path, samples=64):
    scene = bpy.context.scene
    # CYCLES, not EEVEE: EEVEE renders flat and unlit under --background, which this
    # project has already been caught by once.
    scene.render.engine = "CYCLES"
    scene.cycles.samples = samples
    scene.render.resolution_x = 900
    scene.render.resolution_y = 760
    scene.render.film_transparent = False
    scene.camera = camera
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("  wrote", os.path.basename(path))


def render_sand_form(form, size_x, size_z):
    recipe = SAND.FORMS[form]
    SAND.clear_scene()
    with SAND.variant(SCULPT=recipe["sculpt"](size_x, size_z), **recipe["overrides"]):
        obj, _static, _follow, _faces = SAND.build_surface(
            size_x, size_z, "Sand_" + form, int(size_x * 977 + size_z * 131) + 5081
        )

    obj.data.materials.append(surface_material("Sand", SAND_RGB, 0.92))
    light_the_scene()

    zs = [v.co.z for v in obj.data.vertices]
    print(f"  {form}: relief {min(zs):+.2f} .. {max(zs):+.2f} studs about the walkable plane")

    render(camera_top(size_x, size_z), os.path.join(OUT, f"form_{form}_top.png"))
    render(camera_persp(size_x, size_z), os.path.join(OUT, f"form_{form}_persp.png"))


def render_wrap_form(form, size_x, size_z):
    WRAP.clear_scene()
    with WRAP.variant(**WRAP.FORMS[form]):
        centres = WRAP.lattice(size_x, size_z)
        obj, _owner, _static, _spans = WRAP.build_surface(size_x, size_z, centres, "Wrap_" + form)
    # TRANSLUCENT, because that is how the material renders in game and it is the only
    # way this image answers the question being asked of it. A stacked sheet's whole
    # point is the layer you can see but have not popped yet; rendered opaque, the second
    # layer is invisible and the picture says the platform is fine when it may not be.
    mat = surface_material("Wrap", WRAP_RGB, 0.10)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Transmission Weight"].default_value = 0.85
    bsdf.inputs["IOR"].default_value = 1.05
    obj.data.materials.append(mat)
    light_the_scene()
    print(f"  {form}: {len(centres)} pockets on a {size_x:g} x {size_z:g} sheet")
    render(camera_top(size_x, size_z), os.path.join(OUT, f"form_wrap_{form}_top.png"))
    render(camera_persp(size_x, size_z), os.path.join(OUT, f"form_wrap_{form}_persp.png"))


def render_keyboard(size_x, size_z):
    KEYS.clear_scene()
    centres, key = KEYS.layout(size_x, size_z)
    obj, _owner, _static, _plate, face_info = KEYS.build_surface(size_x, size_z, centres, key, "Keyboard")
    KEYS.assign_uvs(obj.data, face_info, key / 2.0)
    # TEXTURED, because the whole point of this render is the atlas. An untextured
    # keyboard render tells you the caps are the right size and nothing about whether a
    # letter landed on each one -- and a UV atlas that is subtly misaddressed looks
    # completely fine in the mesh and completely wrong in game.
    mat = surface_material("Keys", (255, 255, 255), 0.66)
    tree = mat.node_tree
    bsdf = tree.nodes["Principled BSDF"]
    texture = tree.nodes.new("ShaderNodeTexImage")
    path = os.path.join(os.path.dirname(OUT), "textures", "Keyboard_Color.png")
    if os.path.exists(path):
        texture.image = bpy.data.images.load(path)
        texture.interpolation = "Cubic"
        tree.links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        print("    !! Keyboard_Color.png missing -- run gen_pbr.py first")
    obj.data.materials.append(mat)
    light_the_scene()
    print(f"  keyboard: {len(centres)} keys of {key:.2f} on a {size_x:g} x {size_z:g} field")
    render(camera_top(size_x, size_z), os.path.join(OUT, "form_keyboard_top.png"))
    render(camera_persp(size_x, size_z), os.path.join(OUT, "form_keyboard_persp.png"))


def main():
    for size_x, size_z in KEYS.slab_sizes():
        render_keyboard(size_x, size_z)
    for form, size_x, size_z in SAND.form_slabs():
        if form in SAND.FORMS:
            render_sand_form(form, size_x, size_z)
    for form, size_x, size_z in WRAP.form_slabs():
        if form in WRAP.FORMS:
            render_wrap_form(form, size_x, size_z)
    print("Done.")


if __name__ == "__main__":
    main()
