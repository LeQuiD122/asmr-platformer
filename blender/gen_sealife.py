"""The Sunken City's animals and its kelp, as rigged meshes.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_sealife.py
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_sealife.py -- render

Writes meshes/Sea_*.fbx. Import every one into ReplicatedStorage/Assets/TileMeshes, keeping the
Bone children (FBX, not OBJ: an OBJ carries no rig). SunkenCityClient uses a mesh when it finds
one and the part-built animal it has always had when it does not, so importing is one animal at a
time and nothing breaks in between.

With `render`, it also draws each one twice -- at rest and posed the way the client moves it --
into blender/sealife_<name>.png, which is how the weights are checked: a posed wing that tears
away from the body, or a tail that bends at one hinge instead of along its length, is a weighting
fault and shows at once.

=== Why meshes ===

The animals were composed of spheres and boxes: a ray was a disc and two ovals, a shark a stretched
egg with slabs for fins. From the route, through twenty studs of water, what reads is the
silhouette, and a silhouette built of primitives reads as a toy. A lofted body tapers the way an
animal does, a fin can curve, and a rig lets the whole body bend instead of its pieces swinging on
hinges -- which is most of what makes something look like it is swimming rather than being carried.

=== The conventions the client relies on ===

    FACING    Every animal faces Blender +Y, which arrives as Roblox -Z: its LookVector. Up is
              Blender +Z, Roblox +Y.
    PIVOT     Roblox places a mesh by the centre of its bounding box. Every mesh here has anchor
              points added so that centre IS the animal's pivot (the origin) -- the client puts
              the part where the animal is, with no offsets to remember.
    PAIRS     The turtle and the gull are two meshes each (a colour per mesh is all Roblox gives
              without an uploaded texture): shell and body, body and wings. Each pair is anchored
              to one shared box, so the two drop into the same CFrame and line up exactly.
    BONES     Named, in chains nose to tail (Spine_1, Spine_2...), wings root to tip. The client
              finds them by name and bends them about the animal's own axes converted into each
              bone's rest frame, never assuming which way a bone's axes point after import --
              DeformationRenderer learned that the hard way.
    SIZE      Modelled at the size the client draws them, one Blender unit to one stud.
    EXTENTS   Every run writes blender/sealife_extents.json: each mesh's REAL geometry box (the
              anchor specks left out), in Blender axes. check_sunkencity.py reads it, so what it
              holds the animals to -- how near the surface a fin comes, how far a wing reaches --
              is measured off the meshes and not typed in twice.

=== The kelp is two meshes ===

Sea_Kelp is the stipe, its small blades and the float at the top, rigged Kelp_1..12 up its length;
the client bends every bone so the joints follow the same sway the part-built strand has always
had, which is what the checker already holds, and stretches or squeezes the chain to the strand's
height. Sea_KelpCanopy is the fronds streaming off the float along the current (+X), rigged
Frond_1..4 along them so they ripple; the client sets it on the stipe's top each frame. It is a
mesh of its own so the tank's strands can go without one: in the tank there is no room for a
canopy between the tunnel's glass and the tank's edge, and down there it would be under the
tunnel's roof anyway.
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "..", "meshes")
RENDER = "render" in sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else False


# --------------------------------------------------------------------------- #
# Scene and export
# --------------------------------------------------------------------------- #

def clear_scene():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.objects, bpy.data.armatures, bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def flat_layer(bm):
    return bm.faces.layers.int.get("flat") or bm.faces.layers.int.new("flat")


EXTENTS = {}
_extent_of = {}  # id(bmesh) -> its geometry's box, set by anchor


def to_object(name, bm, smooth=True):
    """Bodies smooth, plates (fins, wings, leaves) flat: smoothing a thin plate averages its two
    faces' normals across its edge and turns a fin into a sausage."""
    if id(bm) in _extent_of:
        EXTENTS[name] = _extent_of.pop(id(bm))
    flat = flat_layer(bm)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], ngon_method="EAR_CLIP")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    marks = [f[flat] for f in bm.faces]
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for poly, mark in zip(mesh.polygons, marks):
        poly.use_smooth = smooth and not mark
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def anchor(bm, low, high):
    """Two specks at opposite corners, so the bounding box is exactly low..high and its centre
    is where the animal's pivot is meant to be. A degenerate sliver each: invisible, and
    enough to set the box. The geometry's own box, before the specks, is kept for EXTENTS."""
    if bm.verts:
        _extent_of[id(bm)] = {
            "lo": [round(min(v.co[i] for v in bm.verts), 3) for i in range(3)],
            "hi": [round(max(v.co[i] for v in bm.verts), 3) for i in range(3)],
            "box_lo": list(low), "box_hi": list(high),
        }
    for corner in (low, high):
        c = Vector(corner)
        a = bm.verts.new(c)
        b = bm.verts.new(c + Vector((0.001, 0, 0)))
        d = bm.verts.new(c + Vector((0, 0.001, 0)))
        bm.faces.new((a, b, d))


def build_armature(name, specs):
    """`specs`: (bone, head, tail, parent) in order, parents first."""
    data = bpy.data.armatures.new(name + "_Rig")
    obj = bpy.data.objects.new(name + "_Rig", data)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    for bone, head, tail, parent in specs:
        eb = data.edit_bones.new(bone)
        eb.head = Vector(head)
        eb.tail = Vector(tail)
        if parent:
            eb.parent = data.edit_bones[parent]
            eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def skin(mesh_obj, arm_obj, weigh):
    """`weigh(co)` gives {bone: weight} for a vertex; normalised here, at most four kept."""
    groups = {}
    for bone in arm_obj.data.bones:
        groups[bone.name] = mesh_obj.vertex_groups.new(name=bone.name)
    for v in mesh_obj.data.vertices:
        weights = weigh(v.co)
        best = sorted(weights.items(), key=lambda kv: -kv[1])[:4]
        total = sum(w for _, w in best) or 1.0
        for bone, w in best:
            if w > 0:
                groups[bone].add([v.index], w / total, "REPLACE")
    mesh_obj.parent = arm_obj
    modifier = mesh_obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = arm_obj


def export(objects, name):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".fbx")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True,
        # Roblox reads FBX in centimetres; Blender writes metres. 1/100 lands one unit on one stud.
        global_scale=0.01,
        add_leaf_bones=False, bake_anim=False, axis_forward="-Z", axis_up="Y",
        object_types={"ARMATURE", "MESH"}, mesh_smooth_type="FACE")
    mesh = next(o for o in objects if o.type == "MESH")
    tris = len(mesh.data.polygons)
    bones = len(objects[1].data.bones) if len(objects) > 1 and objects[1].type == "ARMATURE" else 0
    lo = Vector((min(v.co.x for v in mesh.data.vertices), min(v.co.y for v in mesh.data.vertices),
                 min(v.co.z for v in mesh.data.vertices)))
    hi = Vector((max(v.co.x for v in mesh.data.vertices), max(v.co.y for v in mesh.data.vertices),
                 max(v.co.z for v in mesh.data.vertices)))
    size = hi - lo
    flag = "" if tris <= 10000 else "   !! OVER ROBLOX'S 10000-TRIANGLE LIMIT"
    # In Roblox axes: Blender (x, y, z) arrives as (x, z, -y).
    print("  %-18s %5d tris %2d bones   Roblox size %.1f x %.1f x %.1f%s"
          % (name, tris, bones, size.x, size.z, size.y, flag))


# --------------------------------------------------------------------------- #
# Shapes
# --------------------------------------------------------------------------- #

def loft(bm, stations, sides, cap_front=True, cap_back=True, axis="y"):
    """A body through `stations`, each (s, u, v, ru, rv): position `s` along the axis, the section's
    centre offset (u, v) and radii (ru, rv). Along Y the section is in XZ; along Z it is in XY;
    along X it is in YZ."""
    rings = []
    for s, u, v, ru, rv in stations:
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            x = u + ru * math.cos(a)
            w = v + rv * math.sin(a)
            ring.append(bm.verts.new((x, s, w) if axis == "y" else (x, w, s) if axis == "z" else (s, x, w)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(sides):
            a, b = rings[i][k], rings[i][(k + 1) % sides]
            c, d = rings[i + 1][(k + 1) % sides], rings[i + 1][k]
            bm.faces.new((a, b, c, d))
    for cap, ring, (s, u, v, _, _) in ((cap_front, rings[0], stations[0]), (cap_back, rings[-1], stations[-1])):
        if cap:
            tip = bm.verts.new((u, s, v) if axis == "y" else (u, v, s) if axis == "z" else (s, u, v))
            for k in range(sides):
                bm.faces.new((ring[k], ring[(k + 1) % sides], tip))
    return rings


def plate(bm, outline, normal, thick):
    """A flat piece -- a fin, a wing, a leaf -- from a planar outline, `thick` studs through."""
    n = Vector(normal).normalized() * (thick / 2)
    flat = flat_layer(bm)
    top = [bm.verts.new(Vector(p) + n) for p in outline]
    bot = [bm.verts.new(Vector(p) - n) for p in outline]
    made = [bm.faces.new(top), bm.faces.new(list(reversed(bot)))]
    count = len(outline)
    for k in range(count):
        made.append(bm.faces.new((top[k], top[(k + 1) % count], bot[(k + 1) % count], bot[k])))
    for face in made:
        face[flat] = 1


def curve_outline(points, steps=4):
    """Rounds a polygon's corners a little: Catmull-Rom through the points, closed."""
    out = []
    count = len(points)
    for i in range(count):
        p0, p1, p2, p3 = (Vector(points[(i + j) % count]) for j in (-1, 0, 1, 2))
        for k in range(steps):
            t = k / steps
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    return out


def chain_weights(co, bones, along=1):
    """Weights for a chain laid along an axis: `bones` is [(name, start, end)]; a vertex blends
    between the two bones whose spans it sits nearest, so the body bends smoothly between joints."""
    s = co[along]
    weights = {}
    for name, start, end in bones:
        lo, hi = min(start, end), max(start, end)
        mid, half = (lo + hi) / 2, (hi - lo) / 2
        d = abs(s - mid) - half
        w = 1.0 if d <= 0 else max(0.0, 1 - d / max(0.6, half))
        if w > 0:
            weights[name] = w
    if not weights:
        nearest = min(bones, key=lambda b: min(abs(s - b[1]), abs(s - b[2])))
        weights[nearest[0]] = 1.0
    return weights


# --------------------------------------------------------------------------- #
# The animals
# --------------------------------------------------------------------------- #

def body_stations(length, width, height, peak=0.35, snout=0.18, tail=0.08, drop=0.0, count=18):
    """Nose (+Y) to tail (-Y), a fusiform section that is widest at `peak` of the way back."""
    out = []
    for i in range(count + 1):
        t = i / count
        y = length / 2 - t * length
        if t < peak:
            f = math.sin(0.5 * math.pi * (t / peak)) ** 0.8
            f = snout + (1 - snout) * f
        else:
            f = math.cos(0.5 * math.pi * ((t - peak) / (1 - peak))) ** 1.1
            f = tail + (1 - tail) * f
        out.append((y, 0.0, drop * (1 - f), width * f, height * f))
    return out


def build_shark():
    bm = bmesh.new()
    L = 10.0
    stations = body_stations(L, 1.15, 1.25, peak=0.34, snout=0.02, tail=0.14, count=24)
    # The snout drops a little and the head flattens: a shark's head is wider than it is tall.
    stations = [(y, u, v - 0.18 * max(0.0, (y - 2.0) / 3.0), ru * (1.08 if y > 1.5 else 1.0),
                 rv * (0.82 if y > 2.5 else 1.0)) for y, u, v, ru, rv in stations]
    loft(bm, stations, 14)
    tail_y = -L / 2
    # The caudal fin: a tall upper lobe swept back, a short lower one.
    plate(bm, curve_outline([(0, tail_y + 0.5, 0.2), (0, tail_y - 0.4, 1.2), (0, tail_y - 1.9, 2.6), (0, tail_y - 1.3, 1.0),
                             (0, tail_y - 0.9, 0.0), (0, tail_y - 1.5, -1.3), (0, tail_y - 0.3, -0.4)], 3), (1, 0, 0), 0.22)
    # The dorsal, falcate.
    plate(bm, curve_outline([(0, 1.3, 1.0), (0, 0.4, 2.9), (0, -0.4, 3.0), (0, -0.2, 2.4), (0, -0.9, 1.0)], 3), (1, 0, 0), 0.2)
    plate(bm, curve_outline([(0, -2.6, 0.55), (0, -3.0, 1.2), (0, -3.4, 0.5)], 2), (1, 0, 0), 0.12)
    plate(bm, curve_outline([(0, -2.8, -0.55), (0, -3.3, -1.05), (0, -3.5, -0.45)], 2), (1, 0, 0), 0.12)
    # Pectorals, long and swept down.
    for side in (-1, 1):
        plate(bm, curve_outline([(side * 0.8, 2.2, -0.5), (side * 2.8, 0.6, -1.3), (side * 3.0, 0.1, -1.4),
                                 (side * 0.9, 1.1, -0.6)], 3), (0, 0.2, 1), 0.14)
    anchor(bm, (-3.2, -7.8, -3.2), (3.2, 7.8, 3.2))
    mesh = to_object("Sea_Shark", bm)
    spine = [("Root", 5.0, 1.5), ("Spine_1", 1.5, -1.0), ("Spine_2", -1.0, -3.4), ("Spine_3", -3.4, -7.4)]
    rig = build_armature("Sea_Shark", [
        ("Root", (0, 5.0, 0), (0, 1.5, 0), None),
        ("Spine_1", (0, 1.5, 0), (0, -1.0, 0), "Root"),
        ("Spine_2", (0, -1.0, 0), (0, -3.4, 0), "Spine_1"),
        ("Spine_3", (0, -3.4, 0), (0, -7.4, 0), "Spine_2"),
    ])
    skin(mesh, rig, lambda co: chain_weights(co, spine))
    return [mesh, rig], "Sea_Shark", {"Spine_1": ("z", 0.25), "Spine_2": ("z", 0.35), "Spine_3": ("z", 0.45)}


def build_dolphin():
    bm = bmesh.new()
    L = 6.6
    # BEAK, MELON, BODY, laid station by station: a thin rostrum, the forehead rising steeply
    # behind it, the body at its fullest a third of the way back, and a narrow tail stock.
    shaped = []
    for i in range(25):
        t = i / 24
        y = L / 2 - t * L
        if t < 0.1:
            r = 0.14 + 0.9 * t
            h = r * 0.85
            v = -0.12
        else:
            if t < 0.72:
                body = math.sin(0.5 * math.pi * min(1.0, (t - 0.1) / 0.3)) ** 0.7
            else:
                body = math.cos(0.5 * math.pi * (t - 0.72) / 0.28) ** 0.9 * 0.97 + 0.03
            r = 0.2 + 0.54 * body
            h = r * 1.08 + 0.3 * math.exp(-((t - 0.15) / 0.05) ** 2)
            v = 0.12 * math.exp(-((t - 0.15) / 0.06) ** 2)
        shaped.append((y, 0.0, v, r, h))
    loft(bm, shaped, 14)
    # Dorsal fin, curved back; flippers; flukes lying flat.
    plate(bm, curve_outline([(0, 0.5, 0.55), (0, 0.0, 1.2), (0, -0.45, 1.75), (0, -0.95, 2.0), (0, -0.8, 1.55), (0, -0.9, 1.0), (0, -1.25, 0.55)], 3), (1, 0, 0), 0.12)
    for side in (-1, 1):
        plate(bm, curve_outline([(side * 0.55, 1.5, -0.35), (side * 1.6, 0.8, -0.9), (side * 1.7, 0.5, -1.0),
                                 (side * 0.6, 1.0, -0.45)], 3), (0, 0.1, 1), 0.12)
    ty = -L / 2
    plate(bm, curve_outline([(0, ty + 0.3, 0), (1.0, ty - 0.35, 0), (1.25, ty - 0.75, 0), (0.35, ty - 0.5, 0),
                             (0, ty - 0.3, 0), (-0.35, ty - 0.5, 0), (-1.25, ty - 0.75, 0), (-1.0, ty - 0.35, 0)], 3), (0, 0, 1), 0.1)
    anchor(bm, (-2, -4.6, -2), (2, 4.6, 2))
    mesh = to_object("Sea_Dolphin", bm)
    spine = [("Root", 3.3, 0.8), ("Spine_1", 0.8, -1.4), ("Spine_2", -1.4, -3.0), ("Flukes", -3.0, -4.4)]
    rig = build_armature("Sea_Dolphin", [
        ("Root", (0, 3.3, 0), (0, 0.8, 0), None),
        ("Spine_1", (0, 0.8, 0), (0, -1.4, 0), "Root"),
        ("Spine_2", (0, -1.4, 0), (0, -3.0, 0), "Spine_1"),
        ("Flukes", (0, -3.0, 0), (0, -4.4, 0), "Spine_2"),
    ])
    skin(mesh, rig, lambda co: chain_weights(co, spine))
    # Dolphins beat up and down: they bend about the side axis, not the up one.
    return [mesh, rig], "Sea_Dolphin", {"Spine_1": ("x", 0.15), "Spine_2": ("x", 0.25), "Flukes": ("x", 0.4)}


def build_grouper():
    bm = bmesh.new()
    L = 6.0
    stations = body_stations(L, 1.05, 1.35, peak=0.38, snout=0.3, tail=0.18, drop=0.2, count=18)
    loft(bm, stations, 14)
    # The spiny dorsal: a long plate with a serrated top.
    # Spines rising from the nape and falling toward the soft rear fin, the membrane between them
    # dipping; the fin's foot runs inside the back, so only the fin shows.
    spines = [(0, 1.9, 0.95)]
    for k in range(8):
        y = 1.6 - k * 0.38
        peak = 1.62 + 0.28 * math.sin(math.pi * (k + 1) / 9)
        spines.append((0, y, peak))
        spines.append((0, y - 0.19, peak - 0.3))
    spines += [(0, -1.5, 1.55), (0, -2.1, 1.35), (0, -2.35, 0.95), (0, -2.2, 0.8), (0, 1.8, 0.8)]
    plate(bm, spines, (1, 0, 0), 0.08)
    ty = -L / 2
    plate(bm, curve_outline([(0, ty + 0.4, 0.2), (0, ty - 0.6, 1.3), (0, ty - 1.2, 0.8), (0, ty - 1.25, -0.6),
                             (0, ty - 0.6, -1.2), (0, ty + 0.4, -0.3)], 3), (1, 0, 0), 0.16)
    for side in (-1, 1):
        plate(bm, curve_outline([(side * 1.0, 1.0, -0.2), (side * 1.9, 0.2, -0.5), (side * 1.6, -0.5, -0.6),
                                 (side * 1.0, 0.3, -0.4)], 3), (0, 0, 1), 0.12)
    # The lower jaw, jutting: a little wedge under the snout.
    loft(bm, [(3.1, 0, -0.45, 0.45, 0.2), (2.4, 0, -0.55, 0.6, 0.3), (1.8, 0, -0.5, 0.65, 0.35)], 10)
    anchor(bm, (-2.2, -4.4, -2.2), (2.2, 4.4, 2.2))
    mesh = to_object("Sea_Grouper", bm)
    spine = [("Root", 3.2, 0.6), ("Spine_1", 0.6, -1.6), ("Tail", -1.6, -4.3)]
    rig = build_armature("Sea_Grouper", [
        ("Root", (0, 3.2, 0), (0, 0.6, 0), None),
        ("Spine_1", (0, 0.6, 0), (0, -1.6, 0), "Root"),
        ("Tail", (0, -1.6, 0), (0, -4.3, 0), "Spine_1"),
    ])
    skin(mesh, rig, lambda co: chain_weights(co, spine))
    return [mesh, rig], "Sea_Grouper", {"Spine_1": ("z", 0.18), "Tail": ("z", 0.35)}


def build_eel():
    bm = bmesh.new()
    L = 12.0
    count = 40
    stations = []
    for i in range(count + 1):
        t = i / count
        y = L / 2 - t * L
        r = 0.5 * (min(1, t / 0.08) ** 0.6) * (1 - t) ** 0.35 + 0.04
        stations.append((y, 0.0, 0.0, r * 0.85, r))
    loft(bm, stations, 10)
    # A fin running along the back and round the tail, low and continuous: its foot runs just
    # inside the body, so what shows is the ridge.
    top, foot = [], []
    for i in range(16):
        t = i / 15
        y = L / 2 - 1.6 - t * (L - 1.7)
        r = 0.5 * (1 - (1.6 + t * (L - 1.7)) / L) ** 0.35 + 0.04
        top.append((0, y, r + 0.12 + 0.22 * math.sin(math.pi * t) * (1 - 0.5 * t)))
        foot.append((0, y, r * 0.6))
    plate(bm, top + [(0, -L / 2 - 0.25, 0.0)] + list(reversed(foot)), (1, 0, 0), 0.05)
    anchor(bm, (-1.4, -6.6, -1.4), (1.4, 6.6, 1.4))
    mesh = to_object("Sea_Eel", bm)
    names = ["Root"] + ["Spine_%d" % i for i in range(1, 8)]
    edges = [L / 2 - i * (L / 8) for i in range(9)]
    spine = [(names[i], edges[i], edges[i + 1]) for i in range(8)]
    specs = [(names[i], (0, edges[i], 0), (0, edges[i + 1], 0), names[i - 1] if i > 0 else None) for i in range(8)]
    rig = build_armature("Sea_Eel", specs)
    skin(mesh, rig, lambda co: chain_weights(co, spine))
    return [mesh, rig], "Sea_Eel", {names[i]: ("z", 0.3) for i in range(1, 8)}


def build_fish(scale=1.0, name="Sea_Fish"):
    """At `scale` 1 for the tank's and the flat's little fish; Sea_FishLarge, at 2, for the
    street's shoals, which are drawn big enough to see from the route through the water."""
    bm = bmesh.new()
    L = 2.0
    stations = body_stations(L, 0.26, 0.42, peak=0.35, snout=0.25, tail=0.12, count=10)
    loft(bm, stations, 10)
    ty = -L / 2
    plate(bm, [(0, ty + 0.15, 0), (0, ty - 0.5, 0.42), (0, ty - 0.35, 0.05), (0, ty - 0.35, -0.05), (0, ty - 0.5, -0.42)],
          (1, 0, 0), 0.05)
    plate(bm, [(0, 0.3, 0.35), (0, -0.1, 0.62), (0, -0.4, 0.35)], (1, 0, 0), 0.04)
    if scale != 1.0:
        for v in bm.verts:
            v.co *= scale
    k = scale
    anchor(bm, (-0.6 * k, -1.6 * k, -0.7 * k), (0.6 * k, 1.6 * k, 0.7 * k))
    mesh = to_object(name, bm)
    spine = [("Root", 1.0 * k, -0.3 * k), ("Tail", -0.3 * k, -1.5 * k)]
    rig = build_armature(name, [("Root", (0, 1.0 * k, 0), (0, -0.3 * k, 0), None),
                                ("Tail", (0, -0.3 * k, 0), (0, -1.5 * k, 0), "Root")])
    skin(mesh, rig, lambda co: chain_weights(co, spine))
    return [mesh, rig], name, {"Tail": ("z", 0.5)}


def build_ray():
    bm = bmesh.new()
    # Lofted ACROSS: sections in the YZ plane at stations of x, wingtip to wingtip, each a lens
    # from the leading edge to the trailing one. The leading edge sweeps back to the tips; the
    # body is thickest in the middle and the wings thin to nothing.
    span = 6.2
    count = 26
    rings = []
    sides = 10
    for i in range(count + 1):
        x = -span + 2 * span * i / count
        f = min(1.0, abs(x) / span)
        # Swept back to a point: the leading edge curves back to the tip, the trailing edge bows
        # back behind the body and comes forward to meet it.
        lead = 2.7 * (1 - f) ** 0.8 - 1.2 * f * f
        trail = -1.6 * (1 - f) ** 0.5 - 1.25 * f
        chord = max(0.08, lead - trail)
        mid = (lead + trail) / 2
        thick = 0.7 * (1 - f) ** 2.2 + 0.04 + (0.55 * (1 - f / 0.2) if f < 0.2 else 0)
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            ring.append(bm.verts.new((x, mid + chord / 2 * math.cos(a), thick / 2 * math.sin(a) + 0.1 * (1 - f))))
        rings.append(ring)
    for i in range(count):
        for k in range(sides):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
    for ring in (rings[0], rings[-1]):
        centre = sum((v.co for v in ring), Vector()) / sides
        tip = bm.verts.new(centre)
        for k in range(sides):
            bm.faces.new((ring[k], ring[(k + 1) % sides], tip))
    # The cephalic lobes, curled forward either side of the mouth, and the tail's whip.
    for side in (-1, 1):
        plate(bm, curve_outline([(side * 0.45, 2.5, 0.1), (side * 0.85, 3.4, 0.0), (side * 0.6, 3.5, -0.05),
                                 (side * 0.3, 2.7, 0.05)], 2), (0, 0, 1), 0.12)
    loft(bm, [(-1.5, 0, 0.05, 0.14, 0.12), (-4.0, 0, 0.0, 0.08, 0.07), (-7.2, 0, -0.05, 0.02, 0.02)], 6)
    anchor(bm, (-6.4, -7.6, -3), (6.4, 7.6, 3))
    mesh = to_object("Sea_Ray", bm)
    rig = build_armature("Sea_Ray", [
        ("Root", (0, 0.8, 0), (0, -0.8, 0), None),
        ("Wing_L1", (-1.4, 0, 0), (-3.6, 0, 0), "Root"),
        ("Wing_L2", (-3.6, 0, 0), (-6.2, 0, 0), "Wing_L1"),
        ("Wing_R1", (1.4, 0, 0), (3.6, 0, 0), "Root"),
        ("Wing_R2", (3.6, 0, 0), (6.2, 0, 0), "Wing_R1"),
        ("Tail", (0, -1.6, 0), (0, -7.2, 0), "Root"),
    ])

    def weigh(co):
        x, y = co.x, co.y
        if y < -1.7 and abs(x) < 0.4:
            return {"Tail": 1.0}
        side = "L" if x < 0 else "R"
        a = abs(x)
        if a < 1.0:
            return {"Root": 1.0}
        if a < 1.8:
            t = (a - 1.0) / 0.8
            return {"Root": 1 - t, "Wing_%s1" % side: t}
        if a < 3.2:
            return {"Wing_%s1" % side: 1.0}
        if a < 4.0:
            t = (a - 3.2) / 0.8
            return {"Wing_%s1" % side: 1 - t, "Wing_%s2" % side: t}
        return {"Wing_%s2" % side: 1.0}

    skin(mesh, rig, weigh)
    # Wings beat about the body's long axis.
    return [mesh, rig], "Sea_Ray", {"Wing_L1": ("y", 0.3), "Wing_L2": ("y", 0.3), "Wing_R1": ("y", -0.3),
                                    "Wing_R2": ("y", -0.3), "Tail": ("z", 0.3)}


def build_turtle():
    # THE SHELL: a dome, keeled, with a lip round it and a flat plastron under. Rigid.
    shell = bmesh.new()
    rings = 12
    sides = 20
    stations = []
    for i in range(1, rings):
        t = i / rings
        a = math.pi * t
        y = 2.5 * math.cos(a)
        r = math.sin(a)
        stations.append((y, 0.0, 0.0, 1.95 * r, 1.0 * r))
    verts = loft(shell, stations, sides)
    # Flatten the underside, raise a keel along the back, and SCUTES: the shell's plates, each a
    # low dome, so the shell reads as a turtle's and not an egg's.
    for ring in verts:
        for v in ring:
            if v.co.z < 0:
                v.co.z *= 0.25
            else:
                row = v.co.y / 1.05
                col = v.co.x / 0.95 + (0.5 if int(math.floor(row)) % 2 else 0)
                bump = math.cos(math.pi * (row - math.floor(row) - 0.5)) * math.cos(math.pi * (col - math.floor(col) - 0.5))
                v.co.z *= 1 + 0.12 * math.exp(-(v.co.x / 0.5) ** 2) + 0.13 * max(0.0, bump)
    loft(shell, [(2.55, 0, -0.1, 0.2, 0.05), (0, 0, -0.12, 2.1, 0.12), (-2.55, 0, -0.1, 0.2, 0.05)], sides)
    # BODY: head on a neck, four flippers, a stub of tail. Skinned.
    body = bmesh.new()
    loft(body, [(1.9, 0, 0.0, 0.42, 0.34), (2.6, 0, 0.1, 0.44, 0.36), (3.2, 0, 0.18, 0.5, 0.42),
                (3.75, 0, 0.2, 0.42, 0.36), (4.05, 0, 0.18, 0.18, 0.16)], 10)
    for side in (-1, 1):
        plate(body, curve_outline([(side * 1.3, 1.6, -0.15), (side * 2.6, 1.0, -0.3), (side * 3.9, -0.2, -0.45),
                                   (side * 3.6, -0.5, -0.45), (side * 2.2, 0.4, -0.3), (side * 1.3, 0.9, -0.2)], 3),
              (0, 0, 1), 0.2)
        plate(body, curve_outline([(side * 1.2, -1.7, -0.2), (side * 2.1, -2.3, -0.3), (side * 2.0, -2.8, -0.3),
                                   (side * 1.1, -2.2, -0.2)], 3), (0, 0, 1), 0.18)
    loft(body, [(-2.4, 0, -0.1, 0.22, 0.14), (-3.0, 0, -0.12, 0.05, 0.04)], 8)
    low, high = (-4.2, -4.4, -1.6), (4.2, 4.4, 1.6)
    anchor(shell, low, high)
    anchor(body, low, high)
    shell_obj = to_object("Sea_TurtleShell", shell)
    body_obj = to_object("Sea_Turtle", body)
    rig = build_armature("Sea_Turtle", [
        ("Root", (0, 0.5, 0), (0, -0.5, 0), None),
        ("Head", (0, 1.9, 0), (0, 4.0, 0), "Root"),
        ("Flipper_FL", (-1.3, 1.2, -0.2), (-3.8, -0.3, -0.45), "Root"),
        ("Flipper_FR", (1.3, 1.2, -0.2), (3.8, -0.3, -0.45), "Root"),
        ("Flipper_BL", (-1.2, -1.9, -0.2), (-2.0, -2.6, -0.3), "Root"),
        ("Flipper_BR", (1.2, -1.9, -0.2), (2.0, -2.6, -0.3), "Root"),
    ])

    def weigh(co):
        if co.y > 1.7 and abs(co.x) < 0.8:
            return {"Head": 1.0}
        if abs(co.x) > 1.1:
            side = "L" if co.x < 0 else "R"
            end = "F" if co.y > -0.9 else "B"
            return {"Flipper_%s%s" % (end, side): 1.0}
        return {"Root": 1.0}

    skin(body_obj, rig, weigh)
    return [[shell_obj], [body_obj, rig]], ["Sea_TurtleShell", "Sea_Turtle"], {
        "Flipper_FL": ("z", 0.5), "Flipper_FR": ("z", -0.5), "Flipper_BL": ("z", 0.3), "Flipper_BR": ("z", -0.3),
        "Head": ("x", 0.2)}


def build_jelly():
    bm = bmesh.new()
    # THE BELL: a dome whose rim is scalloped into sixteen lobes, with a little thickness.
    sides = 32
    rings_n = 9
    outer = []
    for i in range(rings_n + 1):
        t = i / rings_n
        phi = t * math.pi * 0.52
        ring = []
        for k in range(sides):
            a = 2 * math.pi * k / sides
            scallop = 1 + (0.09 * math.cos(16 * a) if t > 0.8 else 0)
            r = 1.35 * math.sin(phi) * scallop + 0.001
            z = 1.1 * math.cos(phi) - (0.12 * max(0, math.cos(16 * a)) if t > 0.9 else 0)
            ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), z)))
        outer.append(ring)
    for i in range(rings_n):
        for k in range(sides):
            bm.faces.new((outer[i][k], outer[i][(k + 1) % sides], outer[i + 1][(k + 1) % sides], outer[i + 1][k]))
    # The inside of the bell, a little smaller, joined at the rim.
    inner = []
    for i in range(rings_n + 1):
        ring = []
        for k in range(sides):
            v = outer[i][k].co
            ring.append(bm.verts.new((v.x * 0.86, v.y * 0.86, v.z * 0.8 - 0.1)))
        inner.append(ring)
    for i in range(rings_n):
        for k in range(sides):
            bm.faces.new((inner[i + 1][k], inner[i + 1][(k + 1) % sides], inner[i][(k + 1) % sides], inner[i][k]))
    for k in range(sides):
        bm.faces.new((outer[-1][k], inner[-1][k], inner[-1][(k + 1) % sides], outer[-1][(k + 1) % sides]))
    # FOUR ORAL ARMS: frilled ribbons, hanging and twisting.
    for arm in range(4):
        a = arm * math.pi / 2 + math.pi / 4
        pts_l, pts_r = [], []
        for j in range(10):
            t = j / 9
            z = -0.1 - 3.6 * t
            twist = a + 1.2 * t
            w = 0.34 * (1 - 0.5 * t) * (1 + 0.25 * math.sin(9 * t))
            cx, cy = 0.28 * math.cos(a), 0.28 * math.sin(a)
            pts_l.append((cx + w * math.cos(twist + math.pi / 2), cy + w * math.sin(twist + math.pi / 2), z))
            pts_r.append((cx - w * math.cos(twist + math.pi / 2), cy - w * math.sin(twist + math.pi / 2), z))
        plate(bm, pts_l + list(reversed(pts_r)), (math.cos(a), math.sin(a), 0), 0.05)
    # TWELVE TENTACLES from the rim, long and thin.
    for tentacle in range(12):
        a = 2 * math.pi * tentacle / 12
        r = 1.28
        stations = []
        for j in range(7):
            t = j / 6
            stations.append((-t * 5.2 - 0.05, r * math.cos(a) * (1 - 0.15 * t), r * math.sin(a) * (1 - 0.15 * t),
                             0.05 * (1 - 0.6 * t) + 0.01, 0.05 * (1 - 0.6 * t) + 0.01))
        # (lofted along Z: s is height, (u, v) the x, y of the centre)
        loft(bm, [(s, u, v, ru, rv) for s, u, v, ru, rv in stations], 4, False, True, axis="z")
    anchor(bm, (-1.8, -1.8, -6.4), (1.8, 1.8, 6.4))
    mesh = to_object("Sea_Jelly", bm)
    specs = [("Root", (0, 0, 0.2), (0, 0, 1.1), None)]
    for q in range(4):
        a = q * math.pi / 2 + math.pi / 4
        specs.append(("Rim_%d" % (q + 1), (0.9 * math.cos(a), 0.9 * math.sin(a), 0.4), (1.35 * math.cos(a), 1.35 * math.sin(a), 0.1), "Root"))
        specs.append(("Arm_%d" % (q + 1), (0.3 * math.cos(a), 0.3 * math.sin(a), -0.1), (0.3 * math.cos(a), 0.3 * math.sin(a), -2.0), "Root"))
        specs.append(("ArmTip_%d" % (q + 1), (0.3 * math.cos(a), 0.3 * math.sin(a), -2.0), (0.3 * math.cos(a), 0.3 * math.sin(a), -5.4), "Arm_%d" % (q + 1)))
    rig = build_armature("Sea_Jelly", specs)

    def weigh(co):
        a = math.atan2(co.y, co.x)
        q = int(((a - math.pi / 4) % (2 * math.pi)) / (math.pi / 2) + 0.5) % 4 + 1
        if co.z > 0.25:
            rim = min(1, max(0, (math.hypot(co.x, co.y) - 0.5) / 0.8))
            return {"Root": 1 - rim, "Rim_%d" % q: rim}
        if co.z > -0.2:
            return {"Rim_%d" % q: 1.0}
        t = min(1, -co.z / 3.0)
        return {"Arm_%d" % q: 1 - t, "ArmTip_%d" % q: t}

    skin(mesh, rig, weigh)
    return [mesh, rig], "Sea_Jelly", {"Arm_1": ("x", 0.25), "ArmTip_1": ("x", 0.35), "Arm_3": ("y", 0.25)}


def build_gull():
    body = bmesh.new()
    loft(body, [(1.3, 0, 0.1, 0.12, 0.12), (1.0, 0, 0.1, 0.38, 0.4), (0.3, 0, 0, 0.5, 0.5), (-0.6, 0, 0, 0.42, 0.4),
                (-1.3, 0, 0.05, 0.2, 0.15), (-1.7, 0, 0.1, 0.05, 0.04)], 10)
    loft(body, [(1.2, 0, 0.35, 0.05, 0.05), (1.45, 0, 0.45, 0.34, 0.33), (1.85, 0, 0.5, 0.3, 0.3), (2.1, 0, 0.45, 0.05, 0.05)], 10)
    plate(body, [(0, 2.05, 0.46), (0, 2.6, 0.38), (0, 2.1, 0.36)], (1, 0, 0), 0.14)
    plate(body, curve_outline([(0.25, -1.3, 0.1), (0.5, -2.0, 0.1), (-0.5, -2.0, 0.1), (-0.25, -1.3, 0.1)], 2), (0, 0, 1), 0.06)
    wings = bmesh.new()
    for side in (-1, 1):
        plate(wings, curve_outline([(side * 0.35, 0.6, 0.2), (side * 1.8, 0.75, 0.3), (side * 3.4, 0.4, 0.25), (side * 4.1, -0.1, 0.2),
                                    (side * 3.2, -0.3, 0.2), (side * 1.8, -0.35, 0.2), (side * 0.35, -0.5, 0.2)], 3), (0, 0, 1), 0.08)
    low, high = (-4.3, -2.8, -1.0), (4.3, 2.8, 1.0)
    anchor(body, low, high)
    anchor(wings, low, high)
    body_obj = to_object("Sea_Gull", body)
    wing_obj = to_object("Sea_GullWings", wings, smooth=False)
    rig = build_armature("Sea_GullWings", [
        ("Root", (0, 0.3, 0.2), (0, -0.3, 0.2), None),
        ("Wing_L1", (-0.35, 0, 0.2), (-2.0, 0, 0.2), "Root"),
        ("Wing_L2", (-2.0, 0, 0.2), (-4.1, 0, 0.2), "Wing_L1"),
        ("Wing_R1", (0.35, 0, 0.2), (2.0, 0, 0.2), "Root"),
        ("Wing_R2", (2.0, 0, 0.2), (4.1, 0, 0.2), "Wing_R1"),
    ])

    def weigh(co):
        side = "L" if co.x < 0 else "R"
        a = abs(co.x)
        if a < 0.4:
            return {"Root": 1.0}
        if a < 1.7:
            return {"Wing_%s1" % side: 1.0}
        if a < 2.3:
            t = (a - 1.7) / 0.6
            return {"Wing_%s1" % side: 1 - t, "Wing_%s2" % side: t}
        return {"Wing_%s2" % side: 1.0}

    skin(wing_obj, rig, weigh)
    return [[body_obj], [wing_obj, rig]], ["Sea_Gull", "Sea_GullWings"], {
        "Wing_L1": ("y", 0.5), "Wing_L2": ("y", 0.3), "Wing_R1": ("y", -0.5), "Wing_R2": ("y", -0.3)}


KELP_TALL = 94.0
KELP_NODES = 12
KELP_BLADE = 5.5     # a small blade's length; it reaches 0.7 of it out from the stipe
CANOPY_FAN = 0.45    # the canopy's fronds fan this far either side of the current, in radians
# For the preview only: where the canopy sits on the stipe. Exported, it is at its own origin.
PREVIEW_AT = {"Sea_KelpCanopy_Rig": (0, 0, KELP_TALL)}


def build_kelp():
    # THE STIPE: a thin, slightly wavering stalk from the holdfast to the top.
    bm = bmesh.new()
    stations = []
    for i in range(49):
        t = i / 48
        z = t * KELP_TALL
        r = 0.32 * (1 - 0.45 * t) + 0.05
        stations.append((z, 0.12 * math.sin(t * 17), 0.12 * math.cos(t * 13), r, r))
    loft(bm, stations, 7, False, True, axis="z")
    # SMALL BLADES up the stipe, alternating round it, where giant kelp carries them.
    node_gap = KELP_TALL / KELP_NODES
    for n in range(5, KELP_NODES):
        z0 = n * node_gap - 1.0
        a = (n * 2.39) % (2 * math.pi)
        out = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-math.sin(a), math.cos(a), 0))
        long = KELP_BLADE
        pts_l, pts_r = [], []
        for j in range(9):
            t = j / 8
            base = Vector((0, 0, z0)) + out * (long * t * 0.7) + Vector((0, 0, long * t * 0.7))
            width = 0.75 * math.sin(math.pi * min(1, t * 1.1)) + 0.05
            pts_l.append(base + side * (width + 0.1 * math.sin(t * 20)))
            pts_r.append(base - side * (width - 0.1 * math.sin(t * 20)))
        plate(bm, pts_l + list(reversed(pts_r)), out.cross(side) + out * 0.2, 0.05)
    # The gas float at the top, the size of a fist.
    top = KELP_TALL
    loft(bm, [(top + 1.3, 0, 0, 0.3, 0.3), (top + 0.6, 0, 0, 0.85, 0.85), (top - 0.1, 0, 0, 0.9, 0.9),
              (top - 0.8, 0, 0, 0.5, 0.5), (top - 1.4, 0, 0, 0.3, 0.3)], 12, True, True, axis="z")
    anchor(bm, (-5, -5, 0), (5, 5, KELP_TALL + 1.5))
    mesh = to_object("Sea_Kelp", bm)
    specs = []
    for n in range(KELP_NODES):
        specs.append(("Kelp_%d" % (n + 1), (0, 0, n * node_gap), (0, 0, (n + 1) * node_gap), "Kelp_%d" % n if n > 0 else None))
    rig = build_armature("Sea_Kelp", specs)
    spans = [("Kelp_%d" % (n + 1), n * node_gap, (n + 1) * node_gap) for n in range(KELP_NODES)]
    skin(mesh, rig, lambda co: chain_weights(co, spans, along=2))

    # THE CANOPY: long fronds streaming off the float along the current (+X), rippling -- what is
    # seen from the route, lying just under the surface. Its origin is the top of the stipe, and
    # its box is centred there, so the client puts the part at the stipe's top and nothing else.
    cm = bmesh.new()
    for ribbon in range(8):
        # A fan of +/- CANOPY_FAN round the current: the client lays the current along the street,
        # and a fan any wider reaches across it toward the road signs or into the blocks.
        a = -CANOPY_FAN + 2 * CANOPY_FAN * ribbon / 7
        out = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-math.sin(a), math.cos(a), 0))
        long = 10.5 + 1.5 * math.sin(ribbon * 1.7)
        pts_l, pts_r = [], []
        for j in range(14):
            t = j / 13
            base = out * (long * t) + Vector((0, 0, 0.4 + 1.2 * math.sin(math.pi * t) - 0.8 * t))
            width = 0.6 * math.sin(math.pi * min(1.0, 0.15 + t)) + 0.08
            ripple = 0.18 * math.sin(t * 16 + ribbon)
            pts_l.append(base + side * (width + ripple))
            pts_r.append(base - side * (width - ripple))
        plate(cm, pts_l + list(reversed(pts_r)), (0, 0, 1), 0.05)
    anchor(cm, (-13, -7, -3), (13, 7, 3))
    canopy = to_object("Sea_KelpCanopy", cm)
    fronds = [("Frond_1", 0.0, 3.0), ("Frond_2", 3.0, 6.0), ("Frond_3", 6.0, 9.0), ("Frond_4", 9.0, 12.5)]
    canopy_rig = build_armature("Sea_KelpCanopy", [
        (name, (a, 0, 0.4), (b, 0, 0.4), fronds[i - 1][0] if i > 0 else None) for i, (name, a, b) in enumerate(fronds)])
    skin(canopy, canopy_rig, lambda co: chain_weights(co, fronds, along=0))
    bends = {"Kelp_%d" % n: ("x", 0.06) for n in range(2, KELP_NODES + 1)}
    bends.update({"Frond_1": ("y", 0.1), "Frond_2": ("y", -0.1), "Frond_3": ("y", 0.1), "Frond_4": ("y", -0.1)})
    return [[mesh, rig], [canopy, canopy_rig]], ["Sea_Kelp", "Sea_KelpCanopy"], bends


# --------------------------------------------------------------------------- #
# Preview
# --------------------------------------------------------------------------- #

COLOURS = {
    "Sea_Shark": (0.36, 0.41, 0.45), "Sea_Dolphin": (0.44, 0.51, 0.57), "Sea_Grouper": (0.38, 0.36, 0.31),
    "Sea_Eel": (0.19, 0.23, 0.2), "Sea_Fish": (0.67, 0.75, 0.78), "Sea_Ray": (0.23, 0.27, 0.29),
    "Sea_TurtleShell": (0.34, 0.38, 0.24), "Sea_Turtle": (0.47, 0.49, 0.36), "Sea_Jelly": (0.89, 0.77, 0.91),
    "Sea_Gull": (0.94, 0.94, 0.93), "Sea_GullWings": (0.69, 0.71, 0.74), "Sea_Kelp": (0.35, 0.42, 0.2),
}


def pose(rig, bends, amount):
    """Bends each named bone about one of the ANIMAL's axes (x across, y forward, z up), turned
    into that bone's own rest frame -- exactly what SunkenCityClient does, so the preview shows
    what the game will."""
    from mathutils import Quaternion
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    for name, (axis, angle) in bends.items():
        bone = rig.pose.bones.get(name)
        if bone:
            world = Vector({"x": (1, 0, 0), "y": (0, 1, 0), "z": (0, 0, 1)}[axis])
            local = (bone.bone.matrix_local.to_3x3().inverted() @ world).normalized()
            bone.rotation_mode = "QUATERNION"
            bone.rotation_quaternion = Quaternion(local, angle * amount)
    bpy.ops.object.mode_set(mode="OBJECT")


def preview(objects, name, bends):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 600
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.display.shading.show_shadows = True
    meshes = [o for o in objects if o.type == "MESH"]
    for o in meshes:
        o.color = COLOURS.get(o.name, (0.6, 0.6, 0.6)) + (1.0,)
    rigs = [o for o in objects if o.type == "ARMATURE"]
    lo = Vector((min(min((o.matrix_world @ v.co).x for v in o.data.vertices) for o in meshes),
                 min(min((o.matrix_world @ v.co).y for v in o.data.vertices) for o in meshes),
                 min(min((o.matrix_world @ v.co).z for v in o.data.vertices) for o in meshes)))
    hi = Vector((max(max((o.matrix_world @ v.co).x for v in o.data.vertices) for o in meshes),
                 max(max((o.matrix_world @ v.co).y for v in o.data.vertices) for o in meshes),
                 max(max((o.matrix_world @ v.co).z for v in o.data.vertices) for o in meshes)))
    centre = (lo + hi) / 2
    reach = max((hi - lo).length, 2.0)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = reach * 0.9
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    direction = Vector((0.75, -0.9, 0.7)).normalized()
    cam.location = centre + direction * reach * 2
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    for amount, tag in ((0.0, "rest"), (1.0, "posed")):
        for rig in rigs:
            pose(rig, bends, amount)
        scene.render.filepath = os.path.join(HERE, "sealife_%s_%s.png" % (name.replace("Sea_", "").lower(), tag))
        bpy.ops.render.render(write_still=True)
    for rig in rigs:
        pose(rig, bends, 0.0)


# --------------------------------------------------------------------------- #

BUILDERS = [build_shark, build_dolphin, build_grouper, build_eel, build_fish, lambda: build_fish(2.0, "Sea_FishLarge"),
            build_ray, build_turtle, build_jelly, build_gull, build_kelp]


def main():
    print("")
    print("The Sunken City's sea life, to meshes/:")
    for builder in BUILDERS:
        clear_scene()
        objects, names, bends = builder()
        if isinstance(names, str):
            groups, names = [objects], [names]
        else:
            groups = objects
        for group, name in zip(groups, names):
            export(group, name)
        if RENDER:
            flat = [o for group in groups for o in group]
            for o in flat:
                if o.name in PREVIEW_AT:
                    o.location = PREVIEW_AT[o.name]
            bpy.context.view_layer.update()
            preview(flat, names[-1], bends)
    with open(os.path.join(HERE, "sealife_extents.json"), "w", encoding="utf-8") as f:
        json.dump(EXTENTS, f, indent=1, sort_keys=True)
    print("  wrote blender/sealife_extents.json (%d meshes)" % len(EXTENTS))
    print("")
    print("Import every Sea_*.fbx into ReplicatedStorage/Assets/TileMeshes, keeping the Bone children.")


if __name__ == "__main__":
    main()
