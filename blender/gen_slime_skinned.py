"""
Skinned slime platform. Blender 5.2 -> FBX -> Roblox skinned MeshPart.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_slime_skinned.py

=== Why this exists ===

Slime was per-tile meshes, and per-tile meshes cannot stop reading as a grid: the
tiles are edge-matched so they meet flush at rest, but the moment one moves and its
neighbour does not, the seam opens. Worse, the boundary tiles are pushed outward by
BOUNDARY_OVERHANG to expose their drips, so even a platform standing perfectly still
showed a ring of separate slabs around its rim. This is the same fix honey got, for
the same reason: ONE continuous mesh with a bone per sub-region cell.

=== How this differs from gen_honey_skinned.py ===

Same rig, deliberately different surface. Honey and slime are the two materials a
player is most likely to confuse -- both glossy, both translucent, both slowing you
on contact -- so if they share a silhouette there is nothing left to tell them apart.

  * POURED versus KNEADED. Honey's surface carries concentric rings, because a
    poured liquid spreads radially from where it landed. Slime's carries irregular
    low-frequency lumps from several non-radial waves beaten against each other: a
    worked, folded gel that never levelled out. Radial symmetry is honey's alone.
  * SHOULDER versus BEAD. Honey has a surface-tension bead, a raised lip right at
    the rim. Slime has no lip; it rounds over the edge in a wide fillet, the way a
    set gel block slumps rather than wets.
  * DOME. Nearly twice honey's, because slime holds its own shape. A pool of honey
    is flat with a meniscus; a lump of slime bulges.
  * BUBBLES. Trapped air, as shallow convex bumps. Honey has none -- it is poured
    and settles clear -- and it is the single most legible "this is slime" cue at
    a glance.
  * TENDRILS versus DRIPS. Honey hangs seven fat blobs off the rim. Slime hangs
    four strands that are half the width and half again the length, because slime
    fails in threads where honey fails in droplets.

=== Constraints this file respects ===

Identical to the honey rig, and they are not optional:

  * Roblox blends at most FOUR bones per vertex.
  * Bones point along Blender +Z, which the FBX Y-up conversion turns into Roblox
    +Y, so a runtime offset of CFrame.new(0, -sink, 0) is straight down.
  * Bones are named Cell_<col>_<row> matching SubRegionGrid, and ROW ORDER IS
    MIRRORED to cancel the Blender +Y -> Roblox -Z flip.
  * Collision does not follow a skinned mesh. The Part tiles remain the floor.

=== Size lock ===

A rig has a fixed bone grid, so this mesh is only valid on a platform whose
SubRegionGrid comes out the same shape. Authored for 16 x 12 (a 5 x 4 grid), which
is the slime section of BOTH R1_SlimeLaunch and C1_SlimeToPace -- C1's was 10 long
and was changed to 12 so that one rig covers both. Do not resize either without
regenerating this.
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

# Matches the slime sections of R1_SlimeLaunch and C1_SlimeToPace in ChunkBuilder.
PLATFORM_X, PLATFORM_Z = 16.0, 12.0
# How far in the flat underside ring sits, as a fraction of the rim. See the bottom
# cap below: this is what keeps the fan coplanar and the drips intact.
BOTTOM_INSET = 0.86

RES = 0.4          # surface sampling; ~8 samples per cell, enough for smooth dents

THICK = 1.5        # slab body. Thicker than honey's 1.35: slime holds its own shape.
DOME = 0.55        # centre bulge, nearly 2x honey's 0.30
SHOULDER = 0.16    # width of the rounded edge fillet, as a fraction of half-width

MAX_INFLUENCES = 4  # Roblox hard limit per vertex
BONES_PER_CELL = 1  # see gen_honey_skinned; the finer rig was tried and reverted
INFLUENCE = 1.25    # bone radius as a multiple of bone spacing

# Trapped air, as (x, y, height, radius) in studs. Hand-placed rather than random so
# the mesh is reproducible: a regenerated asset has to be re-imported by hand, and a
# surface that shuffles every run makes it impossible to tell a real change from noise.
SLIME_BUBBLES = (
    (-4.6, 3.0, 0.30, 1.45),
    (2.9, 3.6, 0.19, 0.95),
    (5.2, -0.7, 0.26, 1.25),
    (-1.4, -1.1, 0.34, 1.70),
    (-5.4, -3.2, 0.17, 0.90),
    (1.1, -4.0, 0.23, 1.15),
    (-2.2, 4.2, 0.14, 0.80),
)

# Long, few, and thin RELATIVE TO THEIR LENGTH. Honey's are (position, depth) with
# DRIP_WIDTH 0.022 and depths from 1.0 to 2.6 across seven of them; these are half as
# many and up to 4.0 deep, which is what makes them read as strands beside honey's
# droplets.
#
# The width is NOT thinner than honey's, and trying to make it thinner is what broke
# the first version. Width here is a fraction of the PERIMETER, and the perimeter is
# only ~140 vertices at RES 0.4, so 0.011 spanned 1.5 vertices: not a thin strand but
# a degenerate one-vertex spike, which rendered as a black sliver at the platform
# edge. Thinness has to come from the depth-to-width ratio, not from collapsing the
# geometry. check_ring_resolution below fails loudly rather than letting this recur.
SLIME_TENDRILS = ((0.13, 3.4), (0.37, 2.6), (0.61, 4.0), (0.86, 3.0))
TENDRIL_WIDTH = 0.024
MIN_TENDRIL_VERTS = 2.5

# How far the underside hangs below the rim EVERYWHERE, before any tendril.
#
# Not cosmetic -- without it the mesh is broken. The top surface tapers to z = 0 at
# the perimeter, and the skirt ring is built directly beneath it, so anywhere the
# tendril term evaluates to zero the two rings land on the same point: a wall of
# zero height, which is a run of degenerate faces and duplicated vertices. Blender's
# recalc_face_normals cannot resolve inside from outside across a collapsed wall and
# flipped the ENTIRE top surface, which rendered as a black sliver along the edge.
#
# Honey has no such constant and does not need one, purely by accident: its seven
# drips sit close enough together that their gaussian tails never quite reach zero
# between neighbours, so its skirt always has some height. Slime's four are sparse
# and narrow enough that the tails vanish completely in the gaps. Relying on that is
# what made this a slime-only bug, and validate_mesh below now checks for it.
SKIRT = 0.45


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

def bubble_height(x, y):
    total = 0.0
    for bx, by, height, radius in SLIME_BUBBLES:
        d = math.hypot(x - bx, y - by)
        total += height * math.exp(-((d / radius) ** 2))
    return total


# ============================================================ sculpted form variants
#
# Same hook honey has, and the sculpts come from the same place. A sculpt is a pure height
# function of x and y that knows nothing about the surface it lands on, so gen_material_beds
# owns the vocabulary and this generator owns nothing but the call.
import gen_material_beds as BEDS

SCULPT = None
# Filled by main so the reporter can name the mesh it just built.
MESH_NAMES = {}

# Both were picked for what they DO. Slime is the launcher, so what matters about a shape on
# it is where it puts your feet at the moment it throws you.
FORMS = (
    (None, "Slime_Platform_Skinned"),
    # Bubbles risen under the skin, roughly a cell across each, merged where they touch. The
    # bounciest thing to walk on rather than a texture: your footing is on top of a blister
    # or down in the gap between two, and the collider grid is fine enough to tell them apart.
    ("blister", "Slime_Platform_16x12_Blister"),
    # A trough down the travel axis with a bank either side. The one form that shapes the
    # ROUTE -- crossing is a choice of lane -- and it takes nothing away, so unlike a hole
    # nobody can fall through it.
    ("channel", "Slime_Platform_16x12_Channel"),
)


def sculpted_height(x, y):
    """What the active form adds at this point, or nothing when there is no form."""
    return SCULPT(x, y) if SCULPT else 0.0


def cell_drops(height_at, size_x, size_z, cols, rows, cell_x, cell_z):
    """Per-cell floor drops below the walkable plane. See SkinnedSpec.drops in ChunkBuilder.

    A MAXIMUM over each cell, not a centre sample: on a field of blisters a centre sample
    lands in a gap as often as on a dome, and a floor set to the bottom of a gap puts your
    feet inside the next blister along.
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
        return ""
    return ", drops = { " + ", ".join(f"{d:g}" for d in drops) + " }"


def slime_height(u, v, x, y):
    edge = min(min(u, 1.0 - u), min(v, 1.0 - v)) * 2.0

    # Wide rounded shoulder instead of honey's narrow rim plus bead. A gel block
    # slumps over its own edge; it does not wet the surface and pull up a lip.
    rim = smoothstep(0.0, SHOULDER, edge)

    # Strong bulge. The 0.7 exponent flattens the top of the dome relative to a
    # plain sine, so the middle of the platform is broadly raised rather than
    # peaked -- a lump that settled, not a droplet.
    dome = DOME * (math.sin(math.pi * u) ** 0.7) * (math.sin(math.pi * v) ** 0.7)

    # Kneaded, not poured. Three waves at unrelated frequencies and angles, so
    # nothing lines up into the concentric rings that are honey's signature. There
    # is deliberately no math.hypot here: any radial term reintroduces them.
    knead = (
        0.085 * math.sin(x * 0.47 + y * 0.21)
        + 0.055 * math.sin(x * 0.19 - y * 0.63 + 1.7)
        + 0.035 * math.sin(x * 0.88 + y * 0.71 + 3.1)
    )

    return sculpted_height(x, y) + THICK * rim + (dome + knead + bubble_height(x, y)) * rim


def tendril_base(t):
    z = -SKIRT
    for position, depth in SLIME_TENDRILS:
        d = abs(t - position)
        d = min(d, 1.0 - d)
        z -= depth * math.exp(-((d / TENDRIL_WIDTH) ** 2))
    return z


def build_surface():
    nx = int(round(PLATFORM_X / RES)) + 1
    ny = int(round(PLATFORM_Z / RES)) + 1

    verts, faces = [], []
    top_indices = []

    for j in range(ny):
        for i in range(nx):
            u, v = i / (nx - 1), j / (ny - 1)
            x, y = (u - 0.5) * PLATFORM_X, (v - 0.5) * PLATFORM_Z
            top_indices.append(len(verts))
            verts.append((x, y, slime_height(u, v, x, y)))

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
    span = TENDRIL_WIDTH * n
    if span < MIN_TENDRIL_VERTS:
        print(f"  !! each tendril spans only {span:.1f} perimeter vertices. Below "
              f"{MIN_TENDRIL_VERTS} it is a single-vertex spike, not a strand, and renders "
              f"as a black sliver at the platform edge. Raise TENDRIL_WIDTH or lower RES.")
    else:
        print(f"  tendrils: {span:.1f} perimeter vertices wide over {n} total")

    wall, static = [], []
    for k, idx in enumerate(ring):
        x, y, _ = verts[idx]
        wall.append(len(verts))
        static.append(len(verts))
        verts.append((x, y, tendril_base(k / n)))

    for k in range(n):
        faces.append((ring[k], ring[(k + 1) % n], wall[(k + 1) % n], wall[k]))

    # === An inset FLAT RING, so the underside is planar ===
    #
    # The bottom used to be a single triangle fan from the centre straight out to the drip
    # rim -- and that rim is not level: tendril_base sits at 0 between drips and dips to the
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

    mesh = bpy.data.meshes.new("Slime_Platform_Skinned")
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    for index, poly in enumerate(mesh.polygons):
        poly.use_smooth = index < top_face_count

    obj = bpy.data.objects.new("Slime_Platform_Skinned", mesh)
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
    # 7.0 studs per tile: the texture repeats at the same physical size on every
    # platform, so a 16 x 18 slab and a 12 x 10 one show the same size of detail.
    uv_project.box_project(mesh, 7.0)

    return obj, top_indices, set(static)


# --------------------------------------------------------------------------- #
# Armature
# --------------------------------------------------------------------------- #

def build_armature(cols, rows, cell_x, cell_z):
    """One bone per sub-region cell, named Cell_<col>_<row>."""
    arm_data = bpy.data.armatures.new("SlimeRig")
    arm_obj = bpy.data.objects.new("SlimeRig", arm_data)
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
            # ROW ORDER IS MIRRORED ON PURPOSE. The FBX conversion maps Blender +Y to
            # Roblox -Z, and SubRegionGrid numbers row 1 from the most-negative Z, so
            # authoring rows from +Y downward is what makes Cell_c_r line up with the
            # tile of the same coordinates. Without it every dent appears mirrored
            # across the platform from wherever you are standing.
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
    modifier.object = bpy.data.objects["SlimeRig"]
    obj.parent = bpy.data.objects["SlimeRig"]


# --------------------------------------------------------------------------- #
# Export
# --------------------------------------------------------------------------- #

def validate_mesh(obj, n_top):
    """Topology checks, run before export.

    These exist because the first version of this mesh exported and imported
    perfectly happily while being wrong: a collapsed skirt gave it 37 degenerate
    faces, 43 duplicated vertices, and an ENTIRE top surface of inverted normals.
    Nothing failed. It rendered as a dark sliver along one edge, which looks like a
    lighting artifact rather than like broken geometry, and would have been much
    harder to diagnose after a Studio import than it is here.

    The normal check is the important one. A closed mesh whose faces point inward
    renders black or invisible depending on backface culling, and Roblox culls.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()

    problems = []
    open_edges = sum(1 for e in bm.edges if e.is_boundary)
    nonmanifold = sum(1 for e in bm.edges if not e.is_manifold)
    degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-6)
    downward = sum(1 for f in bm.faces[:n_top] if f.normal.z < 0)

    seen, coincident = set(), 0
    for vert in bm.verts:
        key = (round(vert.co.x, 5), round(vert.co.y, 5), round(vert.co.z, 5))
        if key in seen:
            coincident += 1
        seen.add(key)
    bm.free()

    if open_edges:
        problems.append(f"{open_edges} open edges (the mesh is not a closed solid)")
    if nonmanifold:
        problems.append(f"{nonmanifold} non-manifold edges")
    if degenerate:
        problems.append(f"{degenerate} zero-area faces (usually a collapsed skirt: raise SKIRT)")
    if coincident:
        problems.append(f"{coincident} duplicated vertices (usually a collapsed skirt: raise SKIRT)")
    if downward:
        problems.append(f"{downward} of {n_top} top faces point DOWN and will be culled by Roblox")

    if problems:
        print("  !! mesh validation failed:")
        for line in problems:
            print(f"     - {line}")
        return False
    print(f"  mesh valid: closed, manifold, {n_top} top faces all pointing up")
    return True


def report_chunkbuilder_numbers(obj, form=None, drop_text=""):
    """Prints the SKINNED_PLATFORMS entry this mesh needs.

    ChunkBuilder places a skinned visual at SURFACE_Y - surfaceOffset above the slab
    centre, where surfaceOffset is the distance from the mesh's BOUNDING-BOX CENTRE
    up to the plane you walk on. The bounding box is dragged far below the surface by
    the tendrils, so that centre is nowhere near the walkable height and guessing it
    puts the platform through the floor. Deriving it here is the only way it stays
    correct when the tendrils are retuned.

    The walkable plane is taken as THICK + DOME * 0.4 -- a representative height
    between the flat body and the peak of the dome. That is the same rule the honey
    rig's 1.82 was measured under (1.35 + 0.30*0.4 = 1.47, against a bbox centre of
    -0.35), so the two meshes sit at a consistent height relative to their tiles.
    """
    zs = [v.co.z for v in obj.data.vertices]
    low, high = min(zs), max(zs)
    centre = (low + high) / 2.0
    # THE WALKABLE PLANE MOVES FOR A SCULPTED VARIANT. Plain slime walks at a representative
    # height between the flat body and the peak of its 0.55-stud dome. A blister stands three
    # times that and a channel bank more again, so a plane drawn through the middle of one
    # would bury you in the high half and float you over the low half. A variant uses the
    # sculpted-bed convention instead: the plane is the high point, and per-cell drops bring
    # every collider down to the surface under it.
    walkable = (THICK + DOME * 0.4) if SCULPT is None else (high + 0.02)
    print("")
    print("  ChunkBuilder SKINNED_PLATFORMS entry:")
    print(f"    Slime = {{ sizeX = {PLATFORM_X:.0f}, sizeZ = {PLATFORM_Z:.0f}, "
          f"meshHeight = {high - low:.2f}, surfaceOffset = {walkable - centre:.2f}, "
          f'mesh = "{MESH_NAMES[form]}"' + (f', form = "{form}"' if form else "")
          + drop_text + " },")
    print(f"    (bbox {low:.2f} .. {high:.2f}, centre {centre:.2f}, walkable plane {walkable:.2f})")
    print("")


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
        # Roblox imports this FBX at exactly 100x: FBX is centimetre-native while
        # Blender exports metres, so pre-scaling by 1/100 lands it at 1:1.
        global_scale=0.01,
        # Leaf bones are Blender bookkeeping; Roblox reads them as real bones.
        add_leaf_bones=False,
        bake_anim=False,
        axis_forward="-Z",
        axis_up="Y",
        object_types={"ARMATURE", "MESH"},
        mesh_smooth_type="FACE",
    )
    print(f"  exported {path}")


def build(form, name):
    global SCULPT

    SCULPT = BEDS.SCULPTS[form](PLATFORM_X, PLATFORM_Z) if form else None
    clear_scene()
    cols, rows, cell_x, cell_z = compute_grid(PLATFORM_X, PLATFORM_Z)
    print(f"Cells: {cols} x {rows} of {cell_x:.2f} x {cell_z:.2f} studs")

    mesh_obj, top_indices, static_indices = build_surface()
    tris = sum(len(p.vertices) - 2 for p in mesh_obj.data.polygons)
    print(f"Mesh: {len(mesh_obj.data.vertices)} verts, {tris} tris")
    if tris > 10000:
        print("  !! over Roblox's 10000-triangle limit")

    nx = int(round(PLATFORM_X / RES)) + 1
    ny = int(round(PLATFORM_Z / RES)) + 1
    if not validate_mesh(mesh_obj, (nx - 1) * (ny - 1)):
        print("  !! exporting anyway so the mesh can be inspected, but DO NOT import this.")

    arm_obj, centres = build_armature(cols, rows, cell_x, cell_z)
    print(f"Bones: {len(centres)} on a {cols * BONES_PER_CELL} x {rows * BONES_PER_CELL} grid, "
          f"{cell_x / BONES_PER_CELL:.2f} x {cell_z / BONES_PER_CELL:.2f} studs apart")
    assign_weights(mesh_obj, top_indices, static_indices, centres, cell_x, cell_z)

    zs = [v.co.z for v in mesh_obj.data.vertices]
    walkable = (THICK + DOME * 0.4) if form is None else (max(zs) + 0.02)
    drop_text = "" if form is None else cell_drops(
        lambda x, y: slime_height(x / PLATFORM_X + 0.5, y / PLATFORM_Z + 0.5, x, y),
        PLATFORM_X, PLATFORM_Z, cols, rows, cell_x, cell_z)
    report_chunkbuilder_numbers(mesh_obj, form, drop_text)
    export_fbx(mesh_obj, arm_obj, name + ".fbx")


def main():
    # `-- blister channel` builds just those; no argument builds all three.
    only = {a for a in sys.argv[sys.argv.index("--") + 1:]} if "--" in sys.argv else None
    for form, name in FORMS:
        MESH_NAMES[form] = name
        if only and (form or "plain") not in only and name not in only:
            continue
        print(f"\n=== {name} ===")
        build(form, name)
    print("Done.")


if __name__ == "__main__":
    main()
