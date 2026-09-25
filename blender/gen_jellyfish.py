"""
The jellyfish bell: a platform that bounces you. Blender 5.2 -> FBX -> Roblox skinned MeshPart.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_jellyfish.py
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_jellyfish.py -- render

Writes meshes/Jellyfish_Platform_16x12.fbx and Jellyfish_Platform_16x12_Moon.fbx. Import both into
ReplicatedStorage/Assets/TileMeshes WITH their Bone children, and paste the SKINNED_PLATFORMS entries
this prints into ChunkBuilder (they are already there as of writing; re-paste them if anything here
changes). With `render` it also draws each one into blender/jellyfish_<form>.png.

=== What it is ===

The Sunken City's own material. Everything else on that route is a material from the kit; a
jellyfish is the one that belongs to the sea -- a bell floating level with the route, which you
bounce on (MaterialConfig.Jellyfish: a bounce on every landing, higher than jello's) and cross from
bell to bell. Two bells, on slime's rig:

    Jellyfish_Platform_16x12        a compass jelly: a high bell, sixteen raised radial canals, a
                                    ring of warts toward the margin, a scalloped margin and twelve
                                    long tentacles off it
    Jellyfish_Platform_16x12_Moon   a moon jelly: flatter, the four horseshoe rings in the middle of
                                    it that are the one thing everybody knows about a moon jelly,
                                    faint canals, and a fringe of short tentacles all the way round

Both hang four frilled oral arms under the middle. The BELL IS ROUND, and it rises out of a thin
margin membrane that fills the rest of the platform's rectangle: the platform's floor is its tile
grid, so a round bell alone would leave its corners standing on nothing you can see. The first
build was a rounded rectangle all the way out, and it read as a mattress; the round rise is what
makes it a jellyfish. The colliders follow the membrane down at the corners (the drops).

=== Constraints, the same as slime's and not optional ===

  * One bone per sub-region cell, Cell_<col>_<row>, rows mirrored for the Blender +Y -> Roblox -Z
    flip; the grid, the validation and the export are slime's own functions, so the two rigs
    cannot drift apart.
  * At most four bone influences a vertex.
  * The walkable plane is the bell's top, and per-cell drops bring the colliders down the dome to
    the surface under each of them.
  * What hangs under it -- the tentacles and the arms -- stays within check_sunkencity.py's limit
    over the water: the route's chunks stand 7 over it at the lowest.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sealife as G  # noqa: E402  -- the loft, for the oral arms
import gen_slime_skinned as SLIME  # noqa: E402  -- the grid, the checks and the export
import uv_project  # noqa: E402

RENDER = "render" in sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else False

PLATFORM_X, PLATFORM_Z = 16.0, 12.0
RES = 0.4
THICK = 1.1          # the bell's body, before the dome
FLAP = 0.28          # the margin membrane round the bell, filling the corners
PLAN_P = 2.4         # the bell's outline: a superellipse this round (2 is an ellipse)
SKIRT = 0.5          # how far the margin hangs under the rim everywhere
MAX_INFLUENCES = 4
INFLUENCE = 1.25

FORMS = ((None, "Jellyfish_Platform_16x12"), ("moon", "Jellyfish_Platform_16x12_Moon"))
DOME = {None: 1.8, "moon": 1.0}

# The compass jelly's tentacles, as tubes from under the bell's edge: (angle round it, length).
# Tubes, not the margin pulled down: the first build hung them off the skirt, and a skirt pulled
# down in twelve places is a curtain with twelve points, not twelve strands.
TENTACLES = tuple((2 * math.pi * (k + 0.5) / 12, (4.6, 3.4, 5.0, 3.8, 4.4, 3.2, 4.8, 3.6, 4.2, 3.3, 5.0, 3.9)[k])
                  for k in range(12))
LAPPETS = 16         # the compass jelly's scallops round its rim
FRINGE = 24          # the moon jelly's, finer


def polar(x, y):
    """The bell's own angle and radius, squashed to the platform's 4:3 so the canals fan evenly."""
    sx, sy = x / (PLATFORM_X / 2), y / (PLATFORM_Z / 2)
    return math.atan2(sy, sx), math.hypot(sx, sy)


def plan_r(x, y):
    """1 on the bell's outline, 0 at its middle."""
    return ((abs(x) / (PLATFORM_X / 2)) ** PLAN_P + (abs(y) / (PLATFORM_Z / 2)) ** PLAN_P) ** (1 / PLAN_P)


def compass(x, y):
    a, r = polar(x, y)
    canals = (0.12 * max(0.0, math.cos(16 * a)) ** 4 * SLIME.smoothstep(0.1, 0.3, r)
              * (1 - SLIME.smoothstep(0.85, 1.0, plan_r(x, y))))
    warts = 0.0
    for k in range(32):
        wa = 2 * math.pi * (k + 0.5) / 32
        wr = 0.76 + 0.06 * math.sin(k * 2.3)
        wx, wy = wr * math.cos(wa) * PLATFORM_X / 2, wr * math.sin(wa) * PLATFORM_Z / 2
        warts += 0.08 * math.exp(-((math.hypot(x - wx, y - wy) / 0.35) ** 2))
    return canals + warts


def moon(x, y):
    total = 0.0
    for q in range(4):
        a = math.pi / 4 + q * math.pi / 2
        cx, cy = 1.9 * math.cos(a), 1.6 * math.sin(a)
        dx, dy = x - cx, y - cy
        d = math.hypot(dx, dy)
        # A horseshoe: a ring, open on the side that faces the middle of the bell.
        facing = (-dx * math.cos(a) - dy * math.sin(a)) / max(d, 1e-6)
        total += 0.16 * math.exp(-(((d - 1.05) / 0.26) ** 2)) * (1 - SLIME.smoothstep(0.55, 0.85, facing))
    a, r = polar(x, y)
    return total + 0.035 * max(0.0, math.cos(16 * a)) ** 10 * SLIME.smoothstep(0.35, 0.6, r)


def height(form, u, v, x, y):
    edge = min(min(u, 1.0 - u), min(v, 1.0 - v)) * 2.0
    rim = SLIME.smoothstep(0.0, 0.1, edge)  # down to the skirt at the platform's own edge
    r = plan_r(x, y)
    bell = SLIME.smoothstep(0.0, 0.45, 1.0 - r)
    dome = DOME[form] * max(0.0, 1.0 - r * r) ** 0.7
    detail = moon(x, y) if form == "moon" else compass(x, y)
    return rim * (FLAP + (THICK - FLAP) * bell + (dome + detail) * bell)


def hem(form, t):
    """Where the underside of the margin hangs, `t` of the way round it."""
    if form == "moon":
        return -(SKIRT + 0.45 + 0.45 * math.cos(2 * math.pi * FRINGE * t))
    return -(SKIRT + 0.3 * (0.5 + 0.5 * math.cos(2 * math.pi * LAPPETS * t)))


def tentacles(bm):
    """From under the bell's edge, curling out a little and then hanging."""
    for a, long_ in TENTACLES:
        c, s = math.cos(a), math.sin(a)
        k = 0.9 / (abs(c) ** PLAN_P + abs(s) ** PLAN_P) ** (1 / PLAN_P)
        x0, y0 = c * k * PLATFORM_X / 2, s * k * PLATFORM_Z / 2
        stations = []
        for j in range(8):
            t = j / 7
            out = 0.7 * math.sin(math.pi * min(1.0, t * 1.4))
            sway = 0.25 * math.sin(t * 7 + a * 3)
            stations.append((0.15 - long_ * t, x0 + c * out - s * sway, y0 + s * out + c * sway,
                             0.13 * (1 - 0.72 * t), 0.13 * (1 - 0.72 * t)))
        G.loft(bm, stations, 5, True, True, axis="z")


def oral_arms(bm):
    """Four frilled arms hanging under the middle, twisting as they go down. They start inside
    the body, so they hang from it rather than beside it."""
    for q in range(4):
        a = math.pi / 4 + q * math.pi / 2
        stations = []
        for j in range(10):
            t = j / 9
            twist = a + 1.6 * t
            reach = 0.9 + 0.5 * t
            cx = reach * math.cos(a) + 0.25 * math.cos(3 * twist)
            cy = reach * math.sin(a) + 0.25 * math.sin(3 * twist)
            r = 0.34 * (1 - 0.55 * t) + 0.06 + 0.07 * math.sin(t * 14)
            stations.append((0.25 - 4.2 * t, cx, cy, r, r * 0.7))
        G.loft(bm, stations, 8, True, True, axis="z")


def build_surface(form, name):
    nx = int(round(PLATFORM_X / RES)) + 1
    ny = int(round(PLATFORM_Z / RES)) + 1
    verts, faces = [], []
    for j in range(ny):
        for i in range(nx):
            u, v = i / (nx - 1), j / (ny - 1)
            x, y = (u - 0.5) * PLATFORM_X, (v - 0.5) * PLATFORM_Z
            verts.append((x, y, height(form, u, v, x, y)))

    def top(i, j):
        return j * nx + i

    for j in range(ny - 1):
        for i in range(nx - 1):
            faces.append((top(i, j), top(i + 1, j), top(i + 1, j + 1), top(i, j + 1)))
    top_face_count = len(faces)

    ring = [top(i, 0) for i in range(nx - 1)] + [top(nx - 1, j) for j in range(ny - 1)] \
        + [top(i, ny - 1) for i in range(nx - 1, 0, -1)] + [top(0, j) for j in range(ny - 1, 0, -1)]
    n = len(ring)
    static = set()
    wall = []
    for k, idx in enumerate(ring):
        x, y, _ = verts[idx]
        wall.append(len(verts))
        static.add(len(verts))
        verts.append((x, y, hem(form, k / n)))
    for k in range(n):
        faces.append((ring[k], ring[(k + 1) % n], wall[(k + 1) % n], wall[k]))
    # The flat underside, inset, as slime's is (see BOTTOM_INSET there).
    inner = []
    for idx in ring:
        x, y, _ = verts[idx]
        inner.append(len(verts))
        static.add(len(verts))
        verts.append((x * SLIME.BOTTOM_INSET, y * SLIME.BOTTOM_INSET, 0.0))
    for k in range(n):
        faces.append((wall[k], wall[(k + 1) % n], inner[(k + 1) % n], inner[k]))
    centre = len(verts)
    static.add(centre)
    verts.append((0.0, 0.0, 0.0))
    for k in range(n):
        faces.append((centre, inner[k], inner[(k + 1) % n]))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    first_arm = len(bm.verts)
    oral_arms(bm)
    if form != "moon":
        tentacles(bm)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()
    for index in range(first_arm, len(mesh.vertices)):
        static.add(index)
    for index, poly in enumerate(mesh.polygons):
        poly.use_smooth = True
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    uv_project.box_project(mesh, 7.0)
    print(f"  {n / LAPPETS:.1f} rim vertices a lappet, {n / FRINGE:.1f} a fringe scallop")
    return obj, static, top_face_count


def build_armature(name, cols, rows, cell_x, cell_z):
    data = bpy.data.armatures.new(name + "_Rig")
    arm = bpy.data.objects.new(name + "_Rig", data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    root = data.edit_bones.new("Root")
    root.head, root.tail = (0.0, 0.0, 0.0), (0.0, 0.0, 1.0)
    centres = {}
    for col in range(1, cols + 1):
        for row in range(1, rows + 1):
            cx = -PLATFORM_X / 2 + (col - 0.5) * cell_x
            cy = PLATFORM_Z / 2 - (row - 0.5) * cell_z  # mirrored rows, as slime's
            bone = data.edit_bones.new(f"Cell_{col}_{row}")
            bone.head, bone.tail = (cx, cy, THICK), (cx, cy, THICK + 0.6)
            bone.parent = root
            bone.use_connect = False
            centres[bone.name] = (cx, cy)
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm, centres


def assign_weights(obj, arm, static, centres, cell_x, cell_z):
    groups = {name: obj.vertex_groups.new(name=name) for name in centres}
    root = obj.vertex_groups.new(name="Root")
    radius = max(cell_x, cell_z) * INFLUENCE
    for index, vert in enumerate(obj.data.vertices):
        if index in static:
            root.add([index], 1.0, "REPLACE")
            continue
        scored = []
        for name, (cx, cy) in centres.items():
            d = math.hypot(vert.co.x - cx, vert.co.y - cy)
            if d < radius:
                scored.append((math.cos(math.pi * 0.5 * (d / radius)) ** 2, name))
        if not scored:
            root.add([index], 1.0, "REPLACE")
            continue
        scored.sort(reverse=True)
        scored = scored[:MAX_INFLUENCES]
        total = sum(w for w, _ in scored)
        for weight, name in scored:
            groups[name].add([index], weight / total, "REPLACE")
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = arm
    obj.parent = arm


def preview(obj, form):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x, scene.render.resolution_y = 900, 600
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    obj.color = (0.86, 0.72, 0.9, 1.0)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 24
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    direction = Vector((0.7, -1.0, 0.55)).normalized()
    cam.location = Vector((0, 0, -1.2)) + direction * 60
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(HERE, "jellyfish_%s.png" % (form or "compass"))
    bpy.ops.render.render(write_still=True)


def build(form, name):
    SLIME.clear_scene()
    cols, rows, cell_x, cell_z = SLIME.compute_grid(PLATFORM_X, PLATFORM_Z)
    obj, static, n_top = build_surface(form, name)
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"  {len(obj.data.vertices)} verts, {tris} tris" + ("  !! OVER 10000" if tris > 10000 else ""))
    if not SLIME.validate_mesh(obj, n_top):
        print("  !! exporting anyway so it can be looked at, but DO NOT import this.")
    arm, centres = build_armature(name, cols, rows, cell_x, cell_z)
    assign_weights(obj, arm, static, centres, cell_x, cell_z)
    zs = [v.co.z for v in obj.data.vertices]
    low, high = min(zs), max(zs)
    centre = (low + high) / 2
    walkable = high + 0.02
    drops = SLIME.cell_drops(lambda x, y: height(form, x / PLATFORM_X + 0.5, y / PLATFORM_Z + 0.5, x, y),
                             PLATFORM_X, PLATFORM_Z, cols, rows, cell_x, cell_z)
    print("  ChunkBuilder SKINNED_PLATFORMS entry:")
    print(f"    {{ sizeX = {PLATFORM_X:.0f}, sizeZ = {PLATFORM_Z:.0f}, meshHeight = {high - low:.2f}, "
          f"surfaceOffset = {walkable - centre:.2f}, mesh = \"{name}\"" + (f", form = \"{form}\"" if form else "")
          + drops + " },")
    print(f"  hangs {walkable - low:.2f} under the plane you walk on")
    SLIME.export_fbx(obj, arm, name + ".fbx")
    if RENDER:
        preview(obj, form)


def main():
    for form, name in FORMS:
        print(f"\n=== {name} ===")
        build(form, name)
    print("\nImport both into ReplicatedStorage/Assets/TileMeshes, keeping the Bone children.")


if __name__ == "__main__":
    main()
