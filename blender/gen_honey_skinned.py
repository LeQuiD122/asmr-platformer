"""
Skinned honey platform. Blender 5.2 -> FBX -> Roblox skinned MeshPart.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_honey_skinned.py

=== Why this exists ===

The tile approach could not stop reading as a grid, because deformation moved
independent rectangular cells and no amount of shaping changes the fact that a
cell moves as a unit. Here the platform is ONE continuous mesh with a bone per
sub-region cell. Moving a bone dents the surface smoothly, with the influence
falling off into undisturbed material, so a footfall has soft edges and the
surface reads as one substance.

The gameplay layer is untouched: the Part tiles stay as colliders and touch
triggers, DeformationService still owns per-cell state. Only the visual changes,
from "move this box" to "move this bone".

A second win: platform-scale surface features are possible again. A tile could
not know where it sat on the platform, so the meniscus had to appear on every
boundary tile and interior detail had to be periodic. One mesh knows its whole
extent, so the rim runs only around the true perimeter and the pour rings are
continuous.

=== Constraints this file respects ===

  * Roblox blends at most FOUR bones per vertex. Weights are trimmed to the
    strongest four and renormalised; leaving more in lets the importer drop
    influences arbitrarily, which shows up as lumpy, asymmetric denting.
  * Bones all point along Blender +Z, which the FBX Y-up conversion turns into
    Roblox +Y. Every bone therefore shares the mesh's orientation, so a runtime
    offset of CFrame.new(0, -sink, 0) is straight down with no per-bone axis maths.
  * Bones are named B_<i>_<j> on a grid BONES_PER_CELL times finer than the cell
    grid. The renderer matches them by world POSITION rather than by name, so the
    naming only matters for picking the coarse subset used by the ripple sweep
    (both indices odd).
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

# Matches P1_HoneyCorridor in ChunkBuilder.
PLATFORM_X, PLATFORM_Z = 16.0, 18.0
# How far in the flat underside ring sits, as a fraction of the rim. See the bottom
# cap below: this is what keeps the fan coplanar and the drips intact.
BOTTOM_INSET = 0.86

RES = 0.4          # surface sampling; ~8 samples per cell, enough for smooth dents
THICK = 1.35
BEAD = 0.5
DOME = 0.30

MAX_INFLUENCES = 4  # Roblox hard limit per vertex

# Bones per sub-region cell, per axis.
#
# 2 gives a bone roughly every 1.6 studs, which is close to foot scale (a print is about
# 1 by 1.7 studs). At 1 bone per cell the finest thing the surface could express was
# "this 3.2-stud cell was stepped on", so a foot-shaped hollow was impossible and had to
# be faked with an overlay part on top.
#
# Cost is quadratic: 2 gives 120 bones on this platform, 3 would give 270. Roblox's
# per-mesh limit is comfortably above 120 but not unlimited, and every bone is a
# candidate for the ripple sweep on the Luau side.
BONES_PER_CELL = 1

# Bone influence radius as a multiple of BONE SPACING (not cell size).
#
# Tight, and that is the point. At 1.3 a single bone spread its motion over a 4-stud
# circle, so pressing the one bone under a foot still produced a hollow wider than a cell
# and the finer grid bought nothing.
#
# The floor is about 0.70: a vertex at the corner between four bones sits
# sqrt(0.5^2 + 0.5^2) = 0.707 spacings from the nearest one, and any vertex with no bone in
# range falls back to Root and never moves at all, leaving frozen patches in the surface.
# 1.0 is the compromise found by rendering both ends: at 0.85 there is so little overlap
# that each bone moves its patch almost rigidly and a press reads as a faceted box; at 1.3 a
# single bone spreads over 4 studs and the fine grid buys nothing. Smoothness at 1.0 comes
# mostly from pressing SEVERAL bones with a falloff rather than from weight overlap.
INFLUENCE = 1.25

HONEY_DRIPS = ((0.06, 2.0), (0.21, 1.15), (0.38, 2.6), (0.52, 1.4),
               (0.69, 2.2), (0.83, 1.0), (0.94, 1.7))
DRIP_WIDTH = 0.022


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


# --------------------------------------------------------------------------- #
# Cell grid: must mirror SubRegionGrid.compute()
# --------------------------------------------------------------------------- #

CELL_TARGET = 3.2
MIN_CELLS, MAX_CELLS = 2, 6


def compute_grid(size_x, size_z):
    cols = max(MIN_CELLS, min(MAX_CELLS, math.floor(size_x / CELL_TARGET + 0.5)))
    rows = max(MIN_CELLS, min(MAX_CELLS, math.floor(size_z / CELL_TARGET + 0.5)))
    return cols, rows, size_x / cols, size_z / rows


# --------------------------------------------------------------------------- #
# Surface
# --------------------------------------------------------------------------- #

# ============================================================ sculpted form variants
#
# This generator predates the shared sculpt vocabulary and has its own surface function, so
# the hook is one global and one addition rather than the composition gen_material_beds uses.
# The sculpts themselves are IMPORTED from there: a sculpt is a pure height function of x and
# y and knows nothing about the surface it lands on, so there is no reason for a second copy
# to exist here and drift.
#
# The rest of the machinery -- rig, weights, validation, export -- is untouched. A variant is
# the same platform with a shape added to its height field.
import gen_material_beds as BEDS

SCULPT = None


def sculpted_height(x, y):
    """What the active form adds at this point, or nothing when there is no form."""
    return SCULPT(x, y) if SCULPT else 0.0


def cell_drops(height_at, size_x, size_z, cols, rows, cell_x, cell_z, walkable):
    """Per-cell floor drops below the walkable plane. See SkinnedSpec.drops in ChunkBuilder.

    Sampled as a MAXIMUM over each cell rather than at its centre: a centre sample on a
    surface with any texture on it lands wherever it lands, and a floor set to the bottom of
    a groove buries your feet in the material.
    """
    peak, cells = -1e9, []
    for row in range(rows):
        for col in range(cols):
            best = -1e9
            for sx in range(3):
                for sz in range(3):
                    x = -size_x / 2.0 + (col + (sx + 0.5) / 3.0) * cell_x
                    y = -size_z / 2.0 + (row + (sz + 0.5) / 3.0) * cell_z
                    best = max(best, height_at(x, y))
            cells.append(best)
            peak = max(peak, best)
    drops = [round(c - peak, 3) for c in cells]
    if min(drops) > -0.08:
        return "", peak
    return ", drops = { " + ", ".join(f"{d:g}" for d in drops) + " }", peak


def honey_height(u, v, x, y):
    edge = min(min(u, 1.0 - u), min(v, 1.0 - v)) * 2.0
    rim = smoothstep(0.0, 0.09, edge)
    bead = BEAD * math.exp(-(((edge - 0.10) / 0.075) ** 2))
    dome = DOME * math.sin(math.pi * u) * math.sin(math.pi * v)
    radial = math.hypot(x, y)
    rings = 0.075 * math.sin(radial * 1.75) * (1.0 - smoothstep(1.5, 8.5, radial))
    ripple = 0.035 * math.sin(x * 0.62) * math.cos(y * 0.48)
    return (THICK * rim + bead * rim + dome + (rings + ripple) * rim
            + sculpted_height(x, y) * rim)


def drip_base(t):
    z = 0.0
    for position, depth in HONEY_DRIPS:
        d = abs(t - position)
        d = min(d, 1.0 - d)
        z -= depth * math.exp(-((d / DRIP_WIDTH) ** 2))
    return z


def build_surface(name="Honey_Platform_Skinned"):
    nx = int(round(PLATFORM_X / RES)) + 1
    ny = int(round(PLATFORM_Z / RES)) + 1

    verts, faces = [], []
    top_indices = []

    for j in range(ny):
        for i in range(nx):
            u, v = i / (nx - 1), j / (ny - 1)
            x, y = (u - 0.5) * PLATFORM_X, (v - 0.5) * PLATFORM_Z
            top_indices.append(len(verts))
            verts.append((x, y, honey_height(u, v, x, y)))

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
    for k, idx in enumerate(ring):
        x, y, _ = verts[idx]
        wall.append(len(verts))
        static.append(len(verts))
        verts.append((x, y, drip_base(k / n)))

    for k in range(n):
        faces.append((ring[k], ring[(k + 1) % n], wall[(k + 1) % n], wall[k]))

    # === An inset FLAT RING, so the underside is planar ===
    #
    # The bottom used to be a single triangle fan from the centre straight out to the drip
    # rim -- and that rim is not level: drip_base sits at 0 between drips and dips to the
    # drip depth at each one. So most of the fan lay flat while a wedge under every drip
    # tilted, and each wedge picked up its own normal. Through a translucent surface that
    # reads as a dark star radiating from the middle of the platform, which is exactly what
    # it looked like from a low angle.
    #
    # Inserting a ring inset 86% of the way in, at z = 0, splits the two jobs apart: the
    # fan inside it is now entirely coplanar, so every triangle shades identically and the
    # star is gone, and all the height variation lives in one narrow band around the edge
    # where it reads as the underside curving up into the drips.
    #
    # The inset has to be real -- an inset of 1.0 would put the ring on top of the rim and
    # every connecting quad would be degenerate.
    inner = []
    for idx in ring:
        x, y, _ = verts[idx]
        inner.append(len(verts))
        static.append(len(verts))
        verts.append((x * BOTTOM_INSET, y * BOTTOM_INSET, 0.0))

    for k in range(n):
        faces.append((wall[k], wall[(k + 1) % n], inner[(k + 1) % n], inner[k]))

    centre = len(verts)
    static.append(centre)
    verts.append((0.0, 0.0, 0.0))
    for k in range(n):
        faces.append((centre, inner[k], inner[(k + 1) % n]))

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

    # UVs, AFTER the normals are settled -- box_project chooses a projection per face from
    # that face's normal, so running it first would key off whatever from_pydata happened
    # to produce. Without this the mesh carries no UV map at all and a SurfaceAppearance
    # on it renders wrong with no warning.
    #
    # 9.0 studs per tile: the texture repeats at the same physical size on every
    # platform, so a 16 x 18 slab and a 12 x 10 one show the same size of detail.
    uv_project.box_project(mesh, 9.0)

    return obj, top_indices, set(static)


# --------------------------------------------------------------------------- #
# Armature
# --------------------------------------------------------------------------- #

def build_armature(cols, rows, cell_x, cell_z):
    """
    One bone per sub-region cell, named Cell_<col>_<row>.

    REVERTED from a 2x finer grid (120 bones). The finer rig could express a foot-SIZED
    hollow, but not a foot-SHAPED one (bones 1.6 studs apart against a 1x1.7 print), and it
    read worse than the cell-scale version while costing a much more complicated renderer.
    BONES_PER_CELL is kept as the knob if it is ever worth revisiting.
    """
    arm_data = bpy.data.armatures.new("HoneyRig")
    arm_obj = bpy.data.objects.new("HoneyRig", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    root = arm_data.edit_bones.new("Root")
    root.head = (0.0, 0.0, 0.0)
    root.tail = (0.0, 0.0, 1.0)

    fine_cols = cols * BONES_PER_CELL
    fine_rows = rows * BONES_PER_CELL
    bone_x = PLATFORM_X / fine_cols
    bone_z = PLATFORM_Z / fine_rows

    centres = {}
    for col in range(1, fine_cols + 1):
        for row in range(1, fine_rows + 1):
            cx = -PLATFORM_X / 2 + (col - 0.5) * bone_x
            # ROW ORDER IS MIRRORED ON PURPOSE.
            #
            # The FBX conversion maps Blender +Y to Roblox -Z. SubRegionGrid numbers
            # row 1 from the most-negative Z, so a bone authored at the most-negative
            # Blender Y arrives at the most-POSITIVE Roblox Z, i.e. at row `rows`.
            # Authoring rows from +Y downward cancels the flip, so Cell_c_r lines up
            # with the tile of the same coordinates. Without this the dent appears
            # mirrored across the platform from wherever you are standing.
            cy = PLATFORM_Z / 2 - (row - 0.5) * bone_z
            name = f"Cell_{col}_{row}"
            bone = arm_data.edit_bones.new(name)
            # Along +Z so bone-local Y becomes Roblox up after the FBX conversion.
            bone.head = (cx, cy, THICK)
            bone.tail = (cx, cy, THICK + 0.6)
            bone.parent = root
            bone.use_connect = False
            centres[name] = (cx, cy)

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj, centres


def assign_weights(obj, top_indices, static_indices, centres, cell_x, cell_z):
    groups = {name: obj.vertex_groups.new(name=name) for name in centres}
    root_group = obj.vertex_groups.new(name="Root")

    # Radius from BONE spacing, not cell spacing. With BONES_PER_CELL = 1 the bones sit
    # 1.6 studs apart, so a cell-sized radius would have every bone influencing its
    # neighbours' neighbours and smear away the resolution this change exists to add.
    bone_x = cell_x / BONES_PER_CELL
    bone_z = cell_z / BONES_PER_CELL
    radius = max(bone_x, bone_z) * INFLUENCE
    uncovered = []
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
                # Smooth radial falloff, zero slope at the edge of influence so
                # dents blend rather than terminating in a visible ring.
                scored.append((math.cos(math.pi * 0.5 * (d / radius)) ** 2, name))

        if not scored:
            # No bone in range. Reported below, because a vertex pinned to Root is a
            # permanently frozen point in the surface.
            uncovered.append(index)
            root_group.add([index], 1.0, "REPLACE")
            continue

        scored.sort(reverse=True)
        scored = scored[:MAX_INFLUENCES]
        total = sum(w for w, _ in scored)
        for weight, name in scored:
            groups[name].add([index], weight / total, "REPLACE")

    if uncovered:
        print(f"  !! {len(uncovered)} vertices have NO bone in range and will never move. "
              f"Raise INFLUENCE (currently {INFLUENCE}).")
    else:
        print(f"  weights: every deformable vertex covered, radius {radius:.2f} studs")

    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = bpy.data.objects["HoneyRig"]
    obj.parent = bpy.data.objects["HoneyRig"]


# --------------------------------------------------------------------------- #
# Export
# --------------------------------------------------------------------------- #

def export_fbx(mesh_obj, arm_obj, filename):
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
        # Roblox imports this FBX at exactly 100x (measured: a 16-stud platform
        # arrived as 1600). FBX is centimetre-native while Blender exports metres,
        # so pre-scaling by 1/100 lands it at 1:1 and the import needs no fixing up.
        # ChunkBuilder forces Size from authored numbers anyway, so this is about
        # keeping the asset sane to inspect rather than about correctness.
        global_scale=0.01,
        # Leaf bones are Blender bookkeeping; Roblox reads them as real bones and
        # they clutter the imported hierarchy.
        add_leaf_bones=False,
        bake_anim=False,
        axis_forward="-Z",
        axis_up="Y",
        object_types={"ARMATURE", "MESH"},
        mesh_smooth_type="FACE",
    )
    print(f"  exported {path}")


# EVERY SIZE HONEY ACTUALLY APPEARS AT, not just the one it was first authored for.
#
# There was a single 16x18 rig, so P4 and C1 -- both 16x12 -- silently fell back to
# per-tile meshes. The handoff called that deliberate, and it reads more like a missing
# asset that got explained after the fact: honey is the flagship material and two of its
# three slabs did not deform at all. ChunkBuilder's rig audit is what surfaced it, as
# "Honey -- ONLY 1/3 slabs rigged".
#
# 16x18 keeps its original name so the mesh already imported into Studio stays valid.
SIZES = (
    (16.0, 18.0, "Honey_Platform_Skinned", None),
    (16.0, 12.0, "Honey_Platform_16x12", None),

    # THE FORMS, and both were chosen for what they do rather than for what they look like.
    #
    # A honeycomb is the obvious picture for honey and would normally be pure decal -- but
    # the comb's pitch is cell scale, so the collider grid can follow it: the walls come out
    # as raised footing and the cells as dips you step down into. It is the one decorative
    # idea here that also changes where your feet are.
    (16.0, 12.0, "Honey_Platform_16x12_Comb", "comb"),
    # And the pour that collected. The middle sits nearly two studs below the rim, so the
    # short way across is downhill into the deepest, slowest honey on the platform and back
    # out -- which is the material's whole character expressed as geometry.
    (16.0, 12.0, "Honey_Platform_16x12_Pool", "pool"),
)


def main():
    global PLATFORM_X, PLATFORM_Z

    global SCULPT

    entries = []
    only = {a for a in sys.argv[sys.argv.index("--") + 1:]} if "--" in sys.argv else None
    for size_x, size_z, name, form in SIZES:
        if only and name not in only and (form or "plain") not in only:
            continue
        PLATFORM_X, PLATFORM_Z = size_x, size_z
        SCULPT = BEDS.SCULPTS[form](size_x, size_z) if form else None
        clear_scene()
        cols, rows, cell_x, cell_z = compute_grid(PLATFORM_X, PLATFORM_Z)

        mesh_obj, top_indices, static_indices = build_surface(name)
        tris = sum(len(p.vertices) - 2 for p in mesh_obj.data.polygons)
        if tris > 10000:
            print(f"  !! {name} is over Roblox's 10000-triangle limit")

        arm_obj, centres = build_armature(cols, rows, cell_x, cell_z)
        assign_weights(mesh_obj, top_indices, static_indices, centres, cell_x, cell_z)
        print(f"  {name}: {cols}x{rows} cells, {len(centres)} bones, {tris} tris")

        export_fbx(mesh_obj, arm_obj, name + ".fbx")

        zs = [v.co.z for v in mesh_obj.data.vertices]
        low, high = min(zs), max(zs)
        # THE WALKABLE PLANE IS THE DOME'S MID-HEIGHT, not its peak.
        #
        # You stand on the average surface of a domed pour, not on its highest point, so
        # this is THICK + DOME/2 -- and a first pass that measured from `high` reported
        # 2.25 for the 16x18 against the 1.82 that has been working in game since it was
        # authored. The check that caught it: this formula reproduces 1.82 exactly.
        # THE WALKABLE PLANE MOVES FOR A SCULPTED VARIANT, and it has to.
        #
        # Plain honey walks at the dome's MID-height: the middle of the pour rises around
        # your ankles, which is the point of it. That only works because the dome is 0.6 of a
        # stud. A comb wall or a pool rim is three times that, and a plane set through the
        # middle of one would bury you to the knee in the high half and float you over the
        # low half -- so a variant uses the same convention the sculpted beds do: the plane
        # is the high point, and per-cell drops bring every collider down to the surface.
        plain = form is None
        walkable = (THICK + DOME / 2.0) if plain else (high + 0.02)
        drop_text = ""
        if not plain:
            # u and v have to be DERIVED from x and y, not passed as constants: `rim` and
            # `dome` are both functions of them, so a fixed (0.5, 0.5) would sample the
            # middle of the dome everywhere and report a platform with no shape at all.
            drop_text, _peak = cell_drops(
                lambda x, y: honey_height(x / size_x + 0.5, y / size_z + 0.5, x, y),
                size_x, size_z, cols, rows, cell_x, cell_z, walkable)
        entries.append(
            f"\t\t{{ sizeX = {size_x:.0f}, sizeZ = {size_z:.0f}, "
            f"meshHeight = {high - low:.2f}, "
            f"surfaceOffset = {walkable - (low + high) / 2.0:.2f}, "
            f'mesh = "{name}"' + (f', form = "{form}"' if form else "") + drop_text + " },"
        )

    print("")
    print("  ChunkBuilder SKINNED_PLATFORMS entry:")
    print("\tHoney = {")
    for entry in entries:
        print(entry)
    print("\t},")
    print("")
    print("Done.")


if __name__ == "__main__":
    main()
