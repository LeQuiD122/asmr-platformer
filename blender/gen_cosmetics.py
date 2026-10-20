"""The shop's cosmetics as meshes: the things the trails leave, the auras carry and the steps press in.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python blender/gen_cosmetics.py -- [out] [--render]

Writes meshes/cosmetics/Cos_<Name>.fbx (seventeen), for ReplicatedStorage.Assets.Cosmetics in Studio (import each,
named as its file). CosmeticsClient and StepService draw them; without them the particles and the flat prints stand
in. Each is scaled so its largest extent is one stud (the game sizes it), under 900 triangles.

They were particles and ribbons only: flat sprites, the same few textures on everything, which is why next to a
simulator's shop they looked thin. These are small, soft, rounded things with weight, lit by the world like any part
(no textures: Roblox colours and materials them), sized in studs as they are worn, and few enough triangles that a
lobby full of them costs little.
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS and not ARGS[0].startswith("--") else os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "meshes", "cosmetics")
RENDER = "--render" in ARGS


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def obj_from_bm(bm, name):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    return ob


def smooth_subsurf(ob, levels=2):
    mod = ob.modifiers.new("sub", "SUBSURF")
    mod.levels = levels
    mod.render_levels = levels
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="sub")
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def extrude_outline(points, depth, name, bevel=0.18, levels=2, puff=0.35):
    """A flat outline extruded, bevelled, smoothed and puffed up in the middle: a soft, plump cut-out."""
    bm = bmesh.new()
    top = [bm.verts.new((x, y, depth / 2)) for x, y in points]
    bot = [bm.verts.new((x, y, -depth / 2)) for x, y in points]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    n = len(points)
    for i in range(n):
        bm.faces.new((top[i], top[(i + 1) % n], bot[(i + 1) % n], bot[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = obj_from_bm(bm, name)
    bev = ob.modifiers.new("bev", "BEVEL")
    bev.width = bevel
    bev.segments = 3
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="bev")
    smooth_subsurf(ob, levels)
    # puff: push the faces out along z by how far they are from the rim, like a pillow
    r = max(max(abs(x), abs(y)) for x, y in points)
    for v in ob.data.vertices:
        d = 1 - min(1, math.hypot(v.co.x, v.co.y) / r)
        v.co.z *= 1 + puff * d * 2.2
    return ob


def star_outline(points=5, outer=1.0, inner=0.52, round_=0.0):
    out = []
    for i in range(points * 2):
        a = math.pi / 2 + i * math.pi / points
        r = outer if i % 2 == 0 else inner
        out.append((math.cos(a) * r, math.sin(a) * r))
    return out


def heart_outline(n=64):
    out = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
        out.append((x / 17.0, (y + 2.5) / 17.0))
    return out


def metaballs(name, balls, resolution=0.08, threshold=0.6):
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution
    mb.render_resolution = resolution
    mb.threshold = threshold
    for (x, y, z), r, kind in balls:
        el = mb.elements.new()
        el.co = (x, y, z)
        el.radius = r
        if kind == "ellipsoid":
            el.type = "ELLIPSOID"
    ob = bpy.data.objects.new(name + "_mb", mb)
    bpy.context.collection.objects.link(ob)
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(deps))
    bpy.data.objects.remove(ob)
    out = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(out)
    for p in out.data.polygons:
        p.use_smooth = True
    return out


def uv_sphere(name, radius=1.0, segments=24, rings=14):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    ob = obj_from_bm(bm, name)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def ico(name, radius=1.0, subdiv=2):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius)
    return obj_from_bm(bm, name)


def decimate(ob, target):
    """Down to about `target` triangles, keeping the shape: a cosmetic is small and there may be dozens."""
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if tris <= target:
        return ob
    mod = ob.modifiers.new("dec", "DECIMATE")
    mod.ratio = target / tris
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier="dec")
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def displace(ob, scale, amount, seed=0, smooth=True):
    off = Vector((seed * 3.1, seed * 1.7, seed * 2.3))
    for v in ob.data.vertices:
        n = v.co.normalized()
        v.co += n * amount * noise.noise(v.co * scale + off)
    for p in ob.data.polygons:
        p.use_smooth = smooth


def normalise(ob, size):
    """Scaled so its largest extent is `size` studs, centred on its middle."""
    bb = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    lo = Vector((min(c.x for c in bb), min(c.y for c in bb), min(c.z for c in bb)))
    hi = Vector((max(c.x for c in bb), max(c.y for c in bb), max(c.z for c in bb)))
    centre = (lo + hi) / 2
    extent = max(hi - lo)
    for v in ob.data.vertices:
        v.co = (v.co - centre) * (size / extent)
    return ob


# ----- the things -----

def puffy_star():
    return normalise(extrude_outline(star_outline(), 0.34, "Cos_Star", bevel=0.12, puff=0.45), 1.0)


def puffy_heart():
    return normalise(extrude_outline(heart_outline(), 0.4, "Cos_Heart", bevel=0.12, puff=0.5), 1.0)


def snowflake():
    bm = bmesh.new()
    def bar(length, width, at, angle):
        m = Matrix.Translation(at) @ Matrix.Rotation(angle, 4, "Z") @ Matrix.Translation((length / 2, 0, 0))
        bmesh.ops.create_cube(bm, size=1.0, matrix=m @ Matrix.Diagonal((length, width, width * 0.8, 1)))
    for k in range(6):
        a = k * math.pi / 3
        bar(1.0, 0.11, Vector((0, 0, 0)), a)
        for at, l in ((0.45, 0.32), (0.72, 0.22)):
            base = Vector((math.cos(a) * at, math.sin(a) * at, 0))
            bar(l, 0.08, base, a + math.radians(55))
            bar(l, 0.08, base, a - math.radians(55))
    ob = obj_from_bm(bm, "Cos_Snowflake")
    bev = ob.modifiers.new("bev", "BEVEL")
    bev.width = 0.025
    bev.segments = 2
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="bev")
    return normalise(ob, 1.0)


def honey_drop():
    """A teardrop, revolved: round below, drawing smoothly to a point above (a drop as it falls)."""
    bm = bmesh.new()
    rings, segments = 22, 24
    verts = []
    for i in range(rings + 1):
        t = math.pi * i / rings
        r = math.sin(t) * math.sin(t / 2) ** 1.3
        z = -math.cos(t)
        ring = [bm.verts.new((math.cos(a) * r, math.sin(a) * r, z * 1.15)) for a in [k * 2 * math.pi / segments for k in range(segments)]]
        verts.append(ring)
    for i in range(rings):
        for k in range(segments):
            a, b = verts[i][k], verts[i][(k + 1) % segments]
            c, d = verts[i + 1][(k + 1) % segments], verts[i + 1][k]
            try:
                bm.faces.new((a, b, c, d))
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = obj_from_bm(bm, "Cos_HoneyDrop")
    for p in ob.data.polygons:
        p.use_smooth = True
    return normalise(ob, 1.0)


def cloud_puff(seed):
    rnd = random.Random(seed)
    balls = [((0, 0, 0), 1.0, "ball")]
    for _ in range(6):
        a = rnd.uniform(0, math.pi * 2)
        r = rnd.uniform(0.55, 0.95)
        balls.append(((math.cos(a) * r, math.sin(a) * r * 0.7, rnd.uniform(-0.1, 0.45)), rnd.uniform(0.55, 0.8), "ball"))
    ob = metaballs("Cos_Cloud_%d" % seed, balls, resolution=0.07)
    # flat-bottomed, the way a cumulus is
    for v in ob.data.vertices:
        if v.co.z < -0.35:
            v.co.z = -0.35 + (v.co.z + 0.35) * 0.25
    return normalise(ob, 1.0)


def gem_shard():
    bm = bmesh.new()
    top, bottom = bm.verts.new((0, 0, 1.0)), bm.verts.new((0, 0, -0.75))
    ring = [bm.verts.new((math.cos(a) * 0.42, math.sin(a) * 0.42, 0.15)) for a in [i * math.pi * 2 / 7 for i in range(7)]]
    for i in range(7):
        bm.faces.new((ring[i], ring[(i + 1) % 7], top))
        bm.faces.new((ring[(i + 1) % 7], ring[i], bottom))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    ob = obj_from_bm(bm, "Cos_Gem")
    return normalise(ob, 1.0)


def sea_glass(seed):
    ob = uv_sphere("Cos_SeaGlass_%d" % seed, 1.0, 24, 14)
    rnd = random.Random(seed)
    sx, sy, sz = rnd.uniform(0.8, 1.2), rnd.uniform(0.6, 0.9), rnd.uniform(0.28, 0.4)
    for v in ob.data.vertices:
        v.co.x *= sx
        v.co.y *= sy
        v.co.z *= sz
    displace(ob, 1.6, 0.12, seed)
    return normalise(ob, 1.0)


def sprinkle():
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.16, radius2=0.16, depth=0.9)
    ob = obj_from_bm(bm, "Cos_Sprinkle")
    bev = ob.modifiers.new("bev", "BEVEL")
    bev.width = 0.12
    bev.segments = 4
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="bev")
    for p in ob.data.polygons:
        p.use_smooth = True
    return normalise(ob, 1.0)


def firefly():
    # head, thorax and the long abdomen that glows, run together into one body
    balls = [((0, 0.55, 0.06), 0.42, "ball"), ((0, 0.18, 0.02), 0.55, "ball"), ((0, -0.25, 0), 0.62, "ball"),
             ((0, -0.62, -0.02), 0.6, "ball"), ((0, -0.92, -0.04), 0.5, "ball")]
    body = metaballs("Cos_Firefly", balls, resolution=0.09, threshold=0.45)
    for v in body.data.vertices:
        v.co.x *= 0.7
        v.co.z *= 0.65
    return decimate(normalise(body, 1.0), 700)


def firefly_wings():
    bm = bmesh.new()
    for side in (-1, 1):
        pts = []
        for i in range(16):
            a = math.pi * i / 15
            pts.append(bm.verts.new((side * (0.1 + math.sin(a) * 0.55), 0.1 + math.cos(a) * 0.3 - 0.15, 0.25)))
        bm.faces.new(pts if side > 0 else list(reversed(pts)))
    return normalise(obj_from_bm(bm, "Cos_FireflyWings"), 1.0)


def ember_chunk(seed):
    ob = ico("Cos_Ember_%d" % seed, 1.0, 2)
    displace(ob, 1.8, 0.35, seed, smooth=False)
    return normalise(ob, 1.0)


def slime_splat():
    rnd = random.Random(7)
    balls = [((0, 0, 0), 1.25, "ball")]
    for k in range(8):
        a = k / 8 * math.pi * 2 + rnd.uniform(-0.25, 0.25)
        # a run of drops out from the middle, getting smaller, so it reads as thrown out of it
        for step, (r, size) in enumerate(((0.85, 0.55), (1.2, 0.42), (1.5, 0.3))):
            if step == 2 and rnd.random() < 0.5:
                continue
            balls.append(((math.cos(a) * r * rnd.uniform(0.9, 1.1), math.sin(a) * r * rnd.uniform(0.9, 1.1), 0), size, "ball"))
    ob = metaballs("Cos_SlimeSplat", balls, resolution=0.1, threshold=0.5)
    for v in ob.data.vertices:
        v.co.z *= 0.2
    return decimate(normalise(ob, 1.0), 900)


def paw_print():
    balls = [((0, -0.25, 0), 0.62, "ball"), ((0.25, -0.35, 0), 0.4, "ball"), ((-0.25, -0.35, 0), 0.4, "ball")]
    for x, y in ((-0.62, 0.35), (-0.22, 0.72), (0.22, 0.72), (0.62, 0.35)):
        balls.append(((x, y, 0), 0.3, "ball"))
    ob = metaballs("Cos_PawPrint", balls, resolution=0.07, threshold=0.75)
    for v in ob.data.vertices:
        v.co.z *= 0.22
    return decimate(normalise(ob, 1.0), 900)


def sole_print():
    """A shoe's print: a broad forefoot, a narrow waist, a round heel, pressed flat (the ember and bubble steps)."""
    balls = [((0, 0.42, 0), 0.6, "ball"), ((0.05, 0.05, 0), 0.46, "ball"), ((0, -0.42, 0), 0.5, "ball")]
    ob = metaballs("Cos_Sole", balls, resolution=0.07, threshold=0.72)
    for v in ob.data.vertices:
        v.co.z *= 0.2
    return decimate(normalise(ob, 1.0), 900)


BUILDERS = [puffy_star, puffy_heart, snowflake, honey_drop, lambda: cloud_puff(1), lambda: cloud_puff(2), gem_shard,
            lambda: sea_glass(1), lambda: sea_glass(2), sprinkle, firefly, firefly_wings, lambda: ember_chunk(1),
            lambda: ember_chunk(2), slime_splat, paw_print, sole_print]


def export(ob):
    decimate(ob, 900)
    os.makedirs(OUT, exist_ok=True)
    for other in bpy.data.objects:
        other.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, ob.name + ".fbx"), use_selection=True, global_scale=0.01,
                             add_leaf_bones=False, bake_anim=False, axis_forward="-Z", axis_up="Y",
                             object_types={"MESH"}, mesh_smooth_type="FACE")
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    print("    %-20s %5d tris" % (ob.name, tris))


def render_sheet(names):
    """Every mesh laid out in a row of rows, lit softly, for a look at them."""
    clear_scene()
    cols = 4
    for k, build in enumerate(BUILDERS):
        ob = decimate(build(), 900)
        ob.location = ((k % cols) * 1.6, -(k // cols) * 1.6, 0)
        ob.rotation_euler = (math.radians(35), 0, math.radians(20))
        mat = bpy.data.materials.new("m%d" % k)
        mat.diffuse_color = [(1, 0.8, 0.3, 1), (1, 0.45, 0.6, 1), (0.85, 0.92, 1, 1), (1, 0.7, 0.15, 1)][k % 4]
        ob.data.materials.append(mat)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    bpy.context.collection.objects.link(cam)
    cam.location = (2.4, -2.6, 9.5)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 7.2
    bpy.context.scene.camera = cam
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.render.resolution_x, sc.render.resolution_y = 1000, 1000
    sh = sc.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_shadows = True
    sh.show_cavity = True
    sc.render.filepath = os.path.join(OUT, "cosmetics_sheet.png")
    bpy.ops.render.render(write_still=True)
    print("wrote", sc.render.filepath)


def main():
    for build in BUILDERS:
        clear_scene()
        export(build())
    if RENDER:
        render_sheet(None)


if __name__ == "__main__":
    main()
