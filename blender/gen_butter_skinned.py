"""
Skinned butter platforms. Blender 5.2 -> FBX -> Roblox skinned MeshParts.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_butter_skinned.py

Exports TWO meshes, one per slab size in P2_ButterWaxCurve (16 x 8 and 12 x 10). A rig
has a fixed bone grid and cannot be resized, so each size needs its own. Re-run this if
either segment's width or length changes in ChunkBuilder.

=== What this is ===

The BUTTER BODY, not the wax. The platform is a stick of butter under a wax coating:
this mesh is the butter, and ChunkBuilder lays irregular wax shards on top of it
(attachShell). The shards crack apart when stood on and the gaps expose this surface,
which is warmer and sits SHELL_THICKNESS lower -- that gap is where a crack gets its
depth from, which is the one thing a drawn crack could never have.

It replaces a plain box. From the side the old platform was a flat yellow slab face,
which is what a Part looks like and not at all what a stick of butter looks like.

=== Butter at room temperature, against the other three ===

  * IT IS A BLOCK. Flat top, vertical sides, a small radius on the edges and nothing
    more. Butter comes out of a mould and holds that shape; it is the only one of the
    four that is fundamentally rectangular. Honey's rim is a surface-tension bead,
    slime is a taut dome, soap is dished and rounded in plan -- all three are shaped
    by something other than a container.
    A first pass gave it heavily slumped edges on the theory that room-temperature
    butter sags. It does, barely, and the result read as a bread roll: rounded on
    every axis at once. What distinguishes this from a plain Part is not how ROUND it
    is but that its edges have any radius at all, plus the plan corners and the ridges.
  * CROWNED, barely. A stick from a mould is a shade higher down its centreline.
    Nothing like slime's dome: about a twelfth of it.
  * MOULD RIDGES. Faint parallel undulations along the long axis, from the wrapper.
    Honey has concentric rings, slime has irregular kneading, soap has broad wear --
    this is the only one with a DIRECTION, and direction is what says "pressed in a
    mould" rather than poured or worked.
  * MATTE AND OPAQUE. No drips, no bubbles, no dish.

=== Constraints this file respects ===

Identical to the honey, slime and soap rigs, and they are not optional:

  * Roblox blends at most FOUR bones per vertex.
  * Bones point along Blender +Z, which the FBX Y-up conversion turns into Roblox +Y,
    so a runtime offset of CFrame.new(0, -sink, 0) is straight down.
  * Bones are named Cell_<col>_<row> matching SubRegionGrid, and ROW ORDER IS MIRRORED
    to cancel the Blender +Y -> Roblox -Z flip.
  * Collision does not follow a skinned mesh. The Part tiles remain the floor.
"""

import bmesh
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import uv_project
import bpy
import math
import os

OUT_DIR = r"C:\Users\Arsenii\Downloads\asmr-platformer-implementation_1\RobloxProject\meshes"

# Every butter slab size in the game, from P2_ButterWaxCurve.
BUTTER_SIZES = ((16.0, 8.0), (12.0, 10.0))

RES = 0.4
# A 4oz stick is chunky, and at 1.6 the platform edge read as a thin yellow band with
# the wax sitting on a lip rather than coating a block. The extra depth costs nothing:
# the top is pinned to the walkable plane, so a thicker body only extends DOWNWARD over
# the invisible slab underneath.
#
# 2.3 -> 3.6 for DISPLACEMENT, not for looks. WAX_SINK is how far the surface drops
# under you, and a dent can never be deeper than the body it is pressed into: at 2.3 a
# 1.5-stud sink already used two thirds of the block and left the dent floor almost at
# the underside. The extra body is what buys room for a sink you can actually see.
#
# 3.6 is the ceiling, not a round number. The visible platform IS this mesh (the slab is
# set transparent once a skinned rig attaches), and the wax wraps SHELL_THICKNESS below
# the skirt, so the shell reaches 2.9 - (THICK + 1.17) in slab-local Y. The slab's own
# underside is at -2, so anything past 3.73 hangs the visible block below the collision
# volume it is supposed to be standing in for.
THICK = 3.6          # a stick of butter has real body
# A stick of butter is a BLOCK. Flat top, near-vertical sides, crisp edges with only a
# small radius on them -- the shape of something turned out of a mould, not something
# that sagged. The first version ran CROWN 0.12 / SLUMP 0.55 / SHOULDER 0.13 and came
# out a pillow: rounded on every axis at once, closer to a bread roll than to butter.
#
# What still separates it from a plain Part is that the edges have ANY radius at all,
# plus the plan corners and the mould ridges. A Part has perfectly sharp 90 degree
# edges and nothing else does, so a small consistent round is enough to read as moulded.
CROWN = 0.05         # barely a crown. Slime's dome is 0.55.
SLUMP = 0.12         # a hint of softening at the rim, not a sag
SHOULDER = 0.045     # tight edge roll, so the top stays flat almost to the rim
CORNER = 1.0         # plan corner radius, in studs
CORNER_MARGIN = 0.07

# Flat underside: butter sits on a surface, it does not hang off one. Non-zero for the
# same reason slime's and soap's are -- a skirt of zero height collapses onto the top
# ring and produces degenerate faces plus inverted normals.
SKIRT = 0.5

# Mould ridges: parallel, along the LONG axis, and very shallow.
RIDGE_COUNT = 7
RIDGE_DEPTH = 0.022

MAX_INFLUENCES = 4
INFLUENCE = 1.25
CELL_TARGET = 3.2
MIN_CELLS, MAX_CELLS = 2, 6


def smoothstep(a, b, x):
    if b <= a:
        return 0.0 if x < a else 1.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.armatures):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def compute_grid(size_x, size_z):
    cols = max(MIN_CELLS, min(MAX_CELLS, math.floor(size_x / CELL_TARGET + 0.5)))
    rows = max(MIN_CELLS, min(MAX_CELLS, math.floor(size_z / CELL_TARGET + 0.5)))
    return cols, rows, size_x / cols, size_z / rows


def plan_radius(size_x, size_z):
    """The plan corner radius actually in force, once CORNER is capped by the slab."""
    return min(CORNER, size_x / 2.0 * 0.8, size_z / 2.0 * 0.8)


def clamp_to_plan(x, y, size_x, size_z):
    """Pull a grid point back onto the rounded-rectangle plan.

    THE PLAN CORNER HAS TO BE REAL GEOMETRY, not just a dip in the height field. The
    surface is sampled on a plain rectangular grid, so without this the block keeps four
    square corners of material out at (half_x, half_z) -- low, because `rim` has fallen
    to zero there, but present, and 0.38 studs tall once the skirt is added.

    The wax band wraps a ROUNDED outline, and those square corners sat 0.27 studs
    outside it: bare butter showing through the coating at all four corners. It could
    not be fixed from the wax side, because the only band that encloses a rectangle is a
    square one, and squaring the band squares the lid with it.
    """
    half_x, half_y = size_x / 2.0, size_z / 2.0
    radius = plan_radius(size_x, size_z)
    qx = abs(x) - (half_x - radius)
    qy = abs(y) - (half_y - radius)
    if qx <= 0.0 or qy <= 0.0:
        return x, y  # on a straight run, where the plan already is the rectangle
    reach = math.hypot(qx, qy)
    if reach <= radius:
        return x, y
    scale = radius / reach
    return (math.copysign((half_x - radius) + qx * scale, x),
            math.copysign((half_y - radius) + qy * scale, y))


def rounded_edge(x, y, size_x, size_z):
    """Signed, normalised inward distance from a rounded-rectangle outline. Negative in
    the rectangle's own corners. Same formulation as the soap generator: the two-case
    version (arc inside the corner, box elsewhere) is continuous in value but not in
    gradient, and creases the surface along four diagonals."""
    half_x, half_y = size_x / 2.0, size_z / 2.0
    radius = plan_radius(size_x, size_z)
    qx = abs(x) - (half_x - radius)
    qy = abs(y) - (half_y - radius)
    inward = radius - (math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0))
    reference = min(half_x, half_y)
    return inward / reference if reference > 0 else 0.0


def butter_height(x, y, size_x, size_z, corner_edge, long_axis_x):
    edge = rounded_edge(x, y, size_x, size_z)
    # Falloff starts below the value at the rectangle's own corner so `rim` never
    # saturates anywhere on the mesh; a surface that saturates has a flat region, and
    # the edge of a flat region is a crease.
    rim = smoothstep(corner_edge - CORNER_MARGIN, SHOULDER, edge)

    # SLUMP. The edge does not just stop, it rolls over and settles -- so the profile
    # near the rim is pulled down harder than a plain falloff would, and the very
    # outside sits lower than the body rather than meeting it at a hard shoulder.
    slump = SLUMP * (1.0 - smoothstep(0.0, SHOULDER * 1.8, max(edge, 0.0)))

    # Crown along the centreline of the LONG axis.
    across = (y / (size_z / 2.0)) if long_axis_x else (x / (size_x / 2.0))
    crown = CROWN * max(0.0, 1.0 - across * across)

    # Mould ridges, parallel to the long axis.
    along = x if long_axis_x else y
    span = (size_x if long_axis_x else size_z) / 2.0
    ridges = RIDGE_DEPTH * math.sin(RIDGE_COUNT * math.pi * (along / span))

    return (THICK + crown + ridges) * rim - slump * THICK * 0.28


def build_surface(size_x, size_z, name):
    corner_edge = rounded_edge(size_x / 2.0, size_z / 2.0, size_x, size_z)
    long_axis_x = size_x >= size_z
    nx = int(round(size_x / RES)) + 1
    ny = int(round(size_z / RES)) + 1

    verts, faces = [], []
    for j in range(ny):
        for i in range(nx):
            u, v = i / (nx - 1), j / (ny - 1)
            x, y = (u - 0.5) * size_x, (v - 0.5) * size_z
            # Clamped BEFORE the height is sampled, so the profile is evaluated at the
            # point the vertex actually ends up at rather than at the grid position it
            # came from -- otherwise the corner ring carries the height of a place that
            # is no longer on the mesh.
            x, y = clamp_to_plan(x, y, size_x, size_z)
            verts.append((x, y, butter_height(x, y, size_x, size_z, corner_edge, long_axis_x)))

    def top(i, j):
        return j * nx + i

    for j in range(ny - 1):
        for i in range(nx - 1):
            faces.append((top(i, j), top(i + 1, j), top(i + 1, j + 1), top(i, j + 1)))
    top_face_count = len(faces)

    ring = []
    for i in range(nx - 1):
        ring.append(top(i, 0))
    for j in range(ny - 1):
        ring.append(top(nx - 1, j))
    for i in range(nx - 1, 0, -1):
        ring.append(top(i, ny - 1))
    for j in range(ny - 1, 0, -1):
        ring.append(top(0, j))

    n = len(ring)
    wall, static = [], []
    for idx in ring:
        x, y, _ = verts[idx]
        # Sides go straight DOWN. Pushing the skirt ring outward past the top ring is
        # what makes a side look slumped, and butter from a mould has vertical sides.
        scale = 1.0
        wall.append(len(verts))
        static.append(len(verts))
        verts.append((x * scale, y * scale, -SKIRT))

    for k in range(n):
        faces.append((ring[k], ring[(k + 1) % n], wall[(k + 1) % n], wall[k]))

    centre = len(verts)
    static.append(centre)
    verts.append((0.0, 0.0, -SKIRT))
    for k in range(n):
        faces.append((centre, wall[k], wall[(k + 1) % n]))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    for index, poly in enumerate(mesh.polygons):
        poly.use_smooth = index < top_face_count

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    return obj, set(static), top_face_count


def build_armature(size_x, size_z, cols, rows, rig_name):
    arm_data = bpy.data.armatures.new(rig_name)
    arm_obj = bpy.data.objects.new(rig_name, arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    root = arm_data.edit_bones.new("Root")
    root.head = (0.0, 0.0, 0.0)
    root.tail = (0.0, 0.0, 1.0)

    bone_x, bone_z = size_x / cols, size_z / rows
    centres = {}
    for col in range(1, cols + 1):
        for row in range(1, rows + 1):
            cx = -size_x / 2 + (col - 0.5) * bone_x
            # ROW ORDER IS MIRRORED: the FBX conversion maps Blender +Y to Roblox -Z,
            # and SubRegionGrid numbers row 1 from the most-negative Z.
            cy = size_z / 2 - (row - 0.5) * bone_z
            name = f"Cell_{col}_{row}"
            bone = arm_data.edit_bones.new(name)
            bone.head = (cx, cy, THICK)
            bone.tail = (cx, cy, THICK + 0.6)
            bone.parent = root
            bone.use_connect = False
            centres[name] = (cx, cy)

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj, centres


def assign_weights(obj, arm_obj, static_indices, centres, cell_x, cell_z):
    groups = {name: obj.vertex_groups.new(name=name) for name in centres}
    root_group = obj.vertex_groups.new(name="Root")
    radius = max(cell_x, cell_z) * INFLUENCE
    uncovered = 0
    mesh = obj.data

    for index in range(len(mesh.vertices)):
        if index in static_indices:
            root_group.add([index], 1.0, "REPLACE")
            continue
        co = mesh.vertices[index].co
        scored = []
        for name, (cx, cy) in centres.items():
            d = math.hypot(co.x - cx, co.y - cy)
            if d < radius:
                scored.append((math.cos(math.pi * 0.5 * (d / radius)) ** 2, name))
        if not scored:
            uncovered += 1
            root_group.add([index], 1.0, "REPLACE")
            continue
        scored.sort(reverse=True)
        scored = scored[:MAX_INFLUENCES]
        total = sum(w for w, _ in scored)
        for weight, name in scored:
            groups[name].add([index], weight / total, "REPLACE")

    if uncovered:
        print(f"  !! {uncovered} vertices have NO bone in range. Raise INFLUENCE ({INFLUENCE}).")
    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = arm_obj
    obj.parent = arm_obj
    return uncovered == 0


def validate_mesh(obj, n_top):
    """See gen_slime_skinned.validate_mesh: the first slime mesh exported happily while
    having an entire top surface of inverted normals, which Roblox culls."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    problems = []
    if sum(1 for e in bm.edges if e.is_boundary):
        problems.append("open edges")
    if sum(1 for e in bm.edges if not e.is_manifold):
        problems.append("non-manifold edges")
    degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-6)
    if degenerate:
        problems.append(f"{degenerate} zero-area faces (raise SKIRT)")
    downward = sum(1 for f in bm.faces[:n_top] if f.normal.z < 0)
    if downward:
        problems.append(f"{downward} of {n_top} top faces point DOWN and Roblox will cull them")
    bm.free()
    if problems:
        print("  !! validation FAILED: " + "; ".join(problems))
        return False
    return True


def export_fbx(mesh_obj, arm_obj, filename):
    # UVs, applied HERE rather than in the builder, so every mesh that leaves this file has
    # them whatever route it took to get built. Roblox's SurfaceAppearance reads the UV map
    # and renders wrong with no warning at all when there is none.
    #
    # 8.0 studs per tile, sized for knife smears. The scale is in studs rather than repeats so
    # every platform size shows the same physical detail instead of stretching it to fit.
    uv_project.box_project(mesh_obj.data, 8.0)

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, filename)
    for obj in bpy.data.objects:
        obj.select_set(False)
    mesh_obj.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        global_scale=0.01,
        add_leaf_bones=False,
        bake_anim=False,
        axis_forward="-Z",
        axis_up="Y",
        object_types={"ARMATURE", "MESH"},
        mesh_smooth_type="FACE",
    )
    print(f"  exported {os.path.basename(path)}")


def mesh_name(size_x, size_z):
    return f"Butter_Platform_{size_x:.0f}x{size_z:.0f}"


# ChunkBuilder lays the wax shell in the top SHELL_THICKNESS of the cell, so the butter
# surface has to sit that far BELOW the walkable plane -- otherwise a crack opens onto
# something at exactly the height of the wax and has no depth at all.
SHELL_THICKNESS = 0.3


def build_variant(size_x, size_z):
    name = mesh_name(size_x, size_z)
    cols, rows, cell_x, cell_z = compute_grid(size_x, size_z)
    mesh_obj, static, n_top = build_surface(size_x, size_z, name)
    arm_obj, centres = build_armature(size_x, size_z, cols, rows, name + "_Rig")
    covered = assign_weights(mesh_obj, arm_obj, static, centres, cell_x, cell_z)
    ok = validate_mesh(mesh_obj, n_top) and covered

    tris = sum(len(p.vertices) - 2 for p in mesh_obj.data.polygons)
    zs = [v.co.z for v in mesh_obj.data.vertices]
    low, high = min(zs), max(zs)
    # PLUS, not minus. surfaceOffset is measured from the bbox centre UP to the plane
    # ChunkBuilder will align with SURFACE_Y, so declaring a plane ABOVE the mesh's real
    # top is what pushes the mesh down. Subtracting instead raised the butter 0.6 studs
    # over the wax and buried the whole shell -- the only sign of it in game was plates
    # poking out from underneath as they tilted on a step.
    #
    # Measured from the butter's HIGHEST point, not a representative one. The crown and
    # the mould ridges put the real peak 0.052 above THICK + CROWN*0.4, so aligning to
    # that average pushed the ridges up through the wax's underside -- they showed as a
    # chevron pattern across an intact platform, which reads as the coating being dirty
    # rather than as two surfaces intersecting. CLEARANCE keeps a hair of air between
    # them so the two never z-fight.
    CLEARANCE = 0.02
    walkable = THICK + CROWN + RIDGE_DEPTH + CLEARANCE + SHELL_THICKNESS
    print(f"  {name}: {cols}x{rows} grid, {len(centres)} bones, {tris} tris, "
          f"{'valid' if ok else 'INVALID'}")
    entry = (f"\t\t{{ sizeX = {size_x:.0f}, sizeZ = {size_z:.0f}, "
             f"meshHeight = {high - low:.2f}, surfaceOffset = {walkable - (low + high) / 2.0:.2f}, "
             f'mesh = "{name}" }},')
    return mesh_obj, arm_obj, entry, ok


def main():
    entries, all_ok = [], True
    for size_x, size_z in BUTTER_SIZES:
        clear_scene()
        mesh_obj, arm_obj, entry, ok = build_variant(size_x, size_z)
        all_ok = all_ok and ok
        export_fbx(mesh_obj, arm_obj, mesh_name(size_x, size_z) + ".fbx")
        entries.append(entry)

    print("")
    print("  ChunkBuilder SKINNED_PLATFORMS entry:")
    print("\tButterWax = {")
    for entry in entries:
        print(entry)
    print("\t},")
    print("")
    print("Done." if all_ok else "!! a mesh failed validation -- DO NOT import.")


if __name__ == "__main__":
    main()
