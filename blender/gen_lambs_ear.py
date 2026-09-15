"""
Skinned lamb's ear platforms. Blender 5.2 -> FBX -> Roblox skinned MeshParts.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_lambs_ear.py

Exports TWO meshes, 16 x 8 and 12 x 10, matching the sizes P7_LambsEar uses. A rig has a
fixed bone grid and cannot be resized, so each size needs its own.

=== What this is ===

A BED OF OVERLAPPING LEAVES, and the leaves are in the MESH rather than the texture.

That split is the whole design and it is the opposite of what wax and ice do. There the
mesh carries big shapes and the texture carries the fine detail, because a fracture is a
line and lines belong in a normal map. Here the identity of the material is the SHAPE of
a leaf -- an ovate lobe with a soft rim, lying over its neighbours -- and a shape that
size cannot live in a tiling texture without repeating visibly across a 16 stud slab.

So the mesh grows leaves and the texture grows FUZZ. Nothing in Lambs_Ear_Color draws a
leaf outline; if it did there would be two sets of leaves at two different scales lying
across each other, which reads as neither.

=== Why the leaves are this big ===

LEAF_A 2.3 makes a leaf 4.6 studs long, which is nearly as long as a Roblox character is
tall. Real lamb's ear leaves are hand-sized, so this is a plant scaled up rather than a
faithful one -- and it has to be, because of the sampling floor this project keeps
rediscovering. A feature has to be several samples across to survive being turned into
triangles, and at RES 0.16 a hand-sized leaf's rim ramp would be under one sample and the
leaf would come out as a bump.

The number that matters is the RIM RAMP, not the leaf. It runs from r = LEAF_PLATEAU out
to r = 1, which on the short axis is (1 - 0.52) * 1.05 = 0.50 studs, a little over three
samples. That is the edge you actually see, and three samples is the minimum that reads
as an edge rather than as noise.

=== Shingling ===

Leaves are combined with a SOFT MAXIMUM, not a sum and not a hard max. A sum would pile
overlapping leaves into a mound; a hard max gives a vertical wall at every overlap, which
at this resolution is a one-sample cliff that aliases. The soft max leaves a rounded
crease about SMOOTH_K wide where one leaf lies over another, and that crease is the read:
it is how you can tell there are separate leaves at all.
"""

import math
import os
import random
import sys

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import uv_project
import gen_butter_skinned as BUTTER

OUT_DIR = BUTTER.OUT_DIR

SIZES = ((16.0, 8.0), (12.0, 10.0))

# Finer than butter's 0.4 by a factor of 2.5, because butter's surface is smooth and this
# one has to resolve a leaf rim. See the sampling note in the docstring.
RES = 0.12

# Borrowed wholesale so the platform sits at the same height as every other skinned one
# and ChunkBuilder's placement maths does not become a special case.
THICK = BUTTER.THICK
SKIRT = BUTTER.SKIRT
SHOULDER = BUTTER.SHOULDER
# ZERO, where butter uses 0.07, and this is what lets the plan be rounded without
# clamp_to_plan. The rim falloff now reaches zero exactly AT the rectangle's own corner
# instead of somewhere beyond it, so the surface descends to meet the skirt along a
# rounded contour and there is no material left standing outside that contour -- which is
# the entire thing the clamp was there to remove.
#
# Butter keeps a margin so the falloff never saturates, on the grounds that the edge of a
# flat region is a crease. At zero the only place rim reaches 0 is the four corner points
# themselves, which is not a region and cannot crease.
CORNER_MARGIN = 0.0

LEAF_A = 1.55        # half length, studs
LEAF_B = 0.70        # half width at the widest point

# PROPORTION IS WHAT MAKES A LOBE A LEAF. At 2.30 by 1.05 rising 0.55 a leaf was eight
# times longer than it was tall -- a lens so flat that the only part of it you could see
# was where it met its neighbours, and a field of those reads as CRACKED MUD. Dropping
# the plan to 1.55 by 0.70 without dropping the height puts it at three to one, which is
# about what a real leaf is, and the curvature becomes something you can see across
# rather than a hint at the edges.
#
# THE CREASE HAS TO BE RESOLVED AFTER ALL. It was set to 0.10 against a 0.16 sample on
# the theory that a leaf margin is a discontinuity and wants to be sharp -- but a step
# narrower than the grid does not come out sharp, it comes out QUANTISED, and the render
# showed every leaf outline stepping along the lattice in visible 0.16 stud jags. So the
# grid went to 0.12 and the crease to 0.18: an edge about one and a half samples wide,
# which is enough for its position to land where the leaf actually is.
#
# LIFT ABOVE RISE IS WHAT MAKES A LEAF LIE ON TOP OF ANOTHER. At 0.38 against a 0.50 rise
# the two were comparable, so the boundary between neighbouring leaves landed halfway up
# both of them and cut each one into a polygon -- the surface came out as a mosaic of
# cells, which is why it kept reading as cracked mud however leaf-shaped the lobes were.
# At 0.75 a leaf that sits high clears its neighbour completely, so its whole outline
# shows and the one underneath is genuinely underneath.
#
# NO PLATEAU, and this is the correction that turned a slab into a bed.
#
# The first version held each leaf at full height inside r < 0.52 and ramped only over
# the outer half. With the leaves covering 95% of the surface -- which is what a mat of
# lamb's ear is -- taking the maximum of a field of FLAT-TOPPED domes produces a flat
# plane. Every leaf centre sat at exactly LEAF_RISE, so the whole bed did, and the only
# thing left to see was the odd rim poking through. It read as a slab with scabs on it.
#
# A leaf has to curve all the way from its midrib to its edge, so the profile is a
# smoothstep with no flat part: zero slope at the centre, zero slope at the rim, curved
# everywhere in between. Then overlapping leaves give a surface of overlapping curves
# instead of one plateau.
LEAF_RISE = 0.26
LEAF_LIFT = 0.30     # how far one leaf can lie above another -- this is the shingling
LEAF_PLATEAU = 0.55  # r below which the blade is flat; the margin rolls off from here
# Ovate, not elliptical. A lamb's ear leaf is widest below its middle and tapers to a
# rounded tip, and the asymmetry is most of what makes a lobe read as a leaf rather than
# as a blob: every blob is symmetrical.
LEAF_TAPER = 0.34    # how much narrower the tip half is than the base half
MIDRIB_DEPTH = 0.070 # a vein, not a crack -- at 0.085 it read as the latter
MIDRIB_W = 0.50      # groove half width, as a fraction of LEAF_B
SMOOTH_K = 0.18      # crease radius where two leaves overlap

# Jittered grid rather than uniform random. Pure random scatter clumps and leaves bald
# patches, and a bald patch in a leaf bed reads as a hole in the platform. The jitter is
# large enough that no row or column survives, and every leaf takes a free rotation.
LEAF_SPACING = 1.05
LEAF_JITTER = 0.68   # as a fraction of spacing
SEED = 20260826



def smoothstep(a, b, x):
    return BUTTER.smoothstep(a, b, x)


def scatter_leaves(size_x, size_z):
    """Leaf centres, angles and lift heights, covering the plan plus a margin.

    The margin is a full leaf length: a leaf whose centre is off the slab still lays part
    of itself across the rim, and without them every edge of the platform would be a row
    of leaf tips pointing inward, which is a border and reads as a manufactured edge.
    """
    rng = random.Random(SEED + int(size_x) * 97 + int(size_z))
    margin = LEAF_A
    leaves = []
    x0, x1 = -size_x / 2 - margin, size_x / 2 + margin
    y0, y1 = -size_z / 2 - margin, size_z / 2 + margin
    cols = max(1, int(round((x1 - x0) / LEAF_SPACING)))
    rows = max(1, int(round((y1 - y0) / LEAF_SPACING)))
    step_x = (x1 - x0) / cols
    step_y = (y1 - y0) / rows
    for i in range(cols + 1):
        for j in range(rows + 1):
            cx = x0 + i * step_x + rng.uniform(-1, 1) * step_x * LEAF_JITTER
            cy = y0 + j * step_y + rng.uniform(-1, 1) * step_y * LEAF_JITTER
            angle = rng.uniform(0.0, math.pi * 2.0)
            lift = rng.uniform(0.0, LEAF_LIFT)
            leaves.append((cx, cy, math.cos(angle), math.sin(angle), lift))
    return leaves


def leaf_relief(x, y, leaves):
    """Height of the leaf bed above its floor at one point.

    Returns the soft maximum over every leaf covering the point, or 0 where none does --
    the floor between leaves, which is visible only in the gaps and is what gives the bed
    depth.
    """
    best = 0.0
    second = 0.0
    for cx, cy, ca, sa, lift in leaves:
        dx, dy = x - cx, y - cy
        # Cheap reject before the rotation: nothing outside the leaf's own bounding
        # circle can contribute, and most leaves are outside it for most points.
        if dx * dx + dy * dy > (LEAF_A + 0.01) ** 2:
            continue
        du = dx * ca + dy * sa
        dv = -dx * sa + dy * ca
        along = du / LEAF_A
        if abs(along) >= 1.0:
            continue
        # The ovate taper: the half nearer the tip is narrower than the half nearer the
        # base. Applied to the WIDTH rather than to the height, so the leaf keeps its
        # full thickness right to the tip and comes to a rounded point in plan.
        width = LEAF_B * (1.0 - LEAF_TAPER * along)
        r = math.hypot(along, dv / width)
        if r >= 1.0:
            continue
        # Zero slope at the centre AND at the rim, curved in between. No exponent below
        # 1 anywhere: a profile like (1 - r^2)^0.4 has an infinite derivative at the rim
        # and comes out as a knife edge, which this project has already paid for once on
        # the sand turtle.
        # A FLAT BLADE WITH A FAST MARGIN, not a dome. Once the profile was actually
        # being evaluated, a pure dome came out as a field of rolling mounds -- soft,
        # smooth, and no more leaf-like than the pedestals had been. A leaf is mostly a
        # flat blade: it holds its height across the middle and then rolls to nothing over
        # a short margin, and it is that roll, at a DIFFERENT height on each overlapping
        # leaf, that reads as one leaf lying across another.
        #
        # The margin runs 0.55 -> 1 in r, which on the short axis is 0.32 studs, a little
        # under three samples. That is the narrowest it can be and still land where the
        # leaf is rather than on the nearest grid line.
        #
        # ONE MINUS smoothstep, not smoothstep with its arguments reversed.
        #
        # BUTTER.smoothstep(a, b, x) guards against a degenerate range with `if b <= a:
        # return 0.0 if x < a else 1.0`, so asking it to run from 1 down to 0 does not
        # give a falling curve -- it gives a STEP, zero everywhere inside the leaf. Every
        # leaf was therefore a flat pedestal with vertical sides, which is what the first
        # three renders were showing: a mosaic of polygonal slabs that read as cracked
        # mud, and no amount of adjusting the proportions was ever going to change it,
        # because the profile those proportions describe was not being evaluated.
        p = 1.0 - smoothstep(LEAF_PLATEAU, 1.0, r)
        # THE LIFT IS SCALED BY THE PROFILE, NOT ADDED TO IT.
        #
        # Added, `lift` was a pedestal the whole leaf stood on: at its rim the profile had
        # fallen to zero but the pedestal had not, so every leaf ended in a vertical wall
        # up to 0.75 studs tall. That wall is what came out as the stair-stepping, and no
        # amount of resolution was going to fix it, because a cliff has no width to
        # resolve -- it just lands on whichever grid line is nearest.
        #
        # Multiplied, a lifted leaf is simply a TALLER leaf that still tapers to nothing
        # at its margin, which is what a leaf does. Shingling then comes out of height:
        # a tall leaf covers a short one, and the edge you see is where the two domes
        # cross, not a manufactured step.
        h = (LEAF_RISE + lift) * p
        # The midrib. Multiplied by p so the groove fades out with the leaf rather than
        # cutting a trench across the bed beyond the leaf tip.
        h -= MIDRIB_DEPTH * p * math.exp(-((dv / (LEAF_B * MIDRIB_W)) ** 2))
        if h > best:
            best, second = h, best
        elif h > second:
            second = h

    if best <= 0.0:
        return 0.0
    if second <= 0.0:
        return best
    # Softplus smooth maximum of the top two. Only the top two, because the sum over all
    # of them inflates the height wherever leaves are dense -- five overlapping leaves
    # would raise the bed by k*ln(5) for no reason anyone could see.
    return best + SMOOTH_K * math.log1p(math.exp(-(best - second) / SMOOTH_K))


def check_profile_tapers():
    """A LEAF MUST REACH ZERO AT ITS OWN RIM. Asserted, not eyeballed.

    This is the one bug this mesh has actually had, and it had it three times. `lift` is
    what makes one leaf lie above another, and when it is ADDED to the profile rather than
    scaling it, a leaf's height at its margin is `lift` rather than nothing -- so the leaf
    ends in a wall up to 0.75 studs tall and the whole bed reads as broken paving.
    It is invisible in the numbers the generator prints and it survived two rounds of
    adjusting proportions, because the proportions were never the problem.

    Slope statistics do not catch it reliably: the buggy bed measures 72.9 degrees at its
    worst against a healthy 68.9, which is not enough separation to set a threshold on
    (check_form_slopes.py reports the angle for information, but this is the real test).
    The property itself is exact, so it gets tested exactly: take one leaf, walk out along
    it, and require what is left at the rim to be a rounding error.
    """
    tallest = [(0.0, 0.0, 1.0, 0.0, LEAF_LIFT)]
    peak = leaf_relief(0.0, 0.0, tallest)
    rim = max(
        leaf_relief(LEAF_A * t, 0.0, tallest)
        for t in (0.995, 0.999, 0.9999)
    )
    ok = rim <= peak * 0.01
    print(f"  profile taper: peak {peak:.3f}, rim {rim:.4f} -- "
          f"{'ok' if ok else 'FAILED, leaves end in a wall (is lift added instead of scaled?)'}")
    return ok


def surface_height(x, y, size_x, size_z, corner_edge, leaves):
    """Leaf relief, brought down to meet the skirt at the platform's outline."""
    edge = BUTTER.rounded_edge(x, y, size_x, size_z)
    rim = smoothstep(corner_edge - CORNER_MARGIN, SHOULDER, edge)
    return (THICK + leaf_relief(x, y, leaves)) * rim


def build_surface(size_x, size_z, name, relief=None):
    """`relief` is any (x, y) -> height-above-THICK field; the leaf bed is the default.

    Parameterised because the TOPOLOGY here is the reusable part, not the leaves. Getting
    a heightfield platform to come out manifold, correctly wound and free of stair-stepping
    took several rounds -- rectangular lattice with no clamp, flatter-diagonal
    triangulation, faces wound by hand with no recalc afterwards -- and every other bed in
    the game wants exactly that and a different field on top. gen_material_beds.py passes
    foam, clay, charcoal and cloud through here.
    """
    """Butter's topology -- gridded top, skirt ring, bottom fan -- with leaves on top and
    one difference that matters: the top is triangulated HERE rather than left as quads.
    """
    corner_edge = BUTTER.rounded_edge(size_x / 2.0, size_z / 2.0, size_x, size_z)
    leaves = scatter_leaves(size_x, size_z)
    field = relief or (lambda x, y: leaf_relief(x, y, leaves))
    nx = int(round(size_x / RES)) + 1
    ny = int(round(size_z / RES)) + 1

    # A PLAIN RECTANGULAR LATTICE. No clamp_to_plan, and that is deliberate.
    #
    # Butter pulls its grid points back onto a rounded outline, because a wax band has to
    # wrap that outline and any material outside it shows through the coating. Nothing is
    # laid over this surface, so the clamp buys nothing here -- and it costs a great deal.
    # At RES 0.16 a corner holds nearly forty clamped points and runs of them land within
    # a thousandth of a stud of each other, which gives sliver triangles whose normals tip
    # below the horizon. Welding those away then merges points in the INTERIOR of the
    # grid, which pinches two sheets of surface together at a vertex: non-manifold edges,
    # and open edges wherever a collapsed triangle had to be dropped.
    #
    # Without it the lattice is perfectly regular and manifold by construction, and the
    # plan still comes out rounded because CORNER_MARGIN = 0 brings the rim falloff to
    # zero along a rounded contour before the rectangle's corners are reached.
    verts = []
    for j in range(ny):
        for i in range(nx):
            u, v = i / (nx - 1), j / (ny - 1)
            x, y = (u - 0.5) * size_x, (v - 0.5) * size_z
            edge = BUTTER.rounded_edge(x, y, size_x, size_z)
            rim = smoothstep(corner_edge - CORNER_MARGIN, SHOULDER, edge)
            verts.append((x, y, (THICK + field(x, y)) * rim))

    def top(i, j):
        return j * nx + i

    # TRIANGULATED ALONG THE FLATTER DIAGONAL, which the sand turtle paid for.
    #
    # A quad whose four corners are not coplanar has to fold along one diagonal or the
    # other, and the two choices are different surfaces. Left to the exporter the choice
    # is arbitrary and therefore inconsistent, so a leaf rim came out folded outward along
    # one row of quads and inward along the next -- which does not read as a soft edge, it
    # reads as a zigzag. Folding along the diagonal whose ends are closest in height keeps
    # the crease where the surface actually creases.
    def emit(tri, out):
        """Append one top triangle, wound so its normal points UP -- or drop it.

        On a heightfield the two are the same question: project to XY and the normal
        points up exactly when the winding is counter-clockwise, whatever the surface is
        doing in Z. So this is not a repair applied after the fact, it is the guarantee
        itself, and it is why no top face can come out inverted however steep a leaf rim
        gets. Anything with no area left after welding is a collapsed corner quad and is
        dropped: the vertices it referred to are now one vertex and there is no hole.
        """
        if tri[0] == tri[1] or tri[1] == tri[2] or tri[0] == tri[2]:
            return  # collapsed by the weld; it had no area to contribute
        p, q, r = (verts[i] for i in tri)
        area2 = (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
        if area2 == 0.0:
            return
        out.append(tri if area2 > 0 else (tri[0], tri[2], tri[1]))

    faces = []
    for j in range(ny - 1):
        for i in range(nx - 1):
            a, b = top(i, j), top(i + 1, j)
            c, d = top(i + 1, j + 1), top(i, j + 1)
            if abs(verts[a][2] - verts[c][2]) <= abs(verts[b][2] - verts[d][2]):
                emit((a, b, c), faces)
                emit((a, c, d), faces)
            else:
                emit((a, b, d), faces)
                emit((b, c, d), faces)
    top_face_count = len(faces)

    walk = []
    for i in range(nx - 1):
        walk.append(top(i, 0))
    for j in range(ny - 1):
        walk.append(top(nx - 1, j))
    for i in range(nx - 1, 0, -1):
        walk.append(top(i, ny - 1))
    for j in range(ny - 1, 0, -1):
        walk.append(top(0, j))

    ring = walk
    n = len(ring)
    wall, static = [], []
    for idx in ring:
        x, y, _ = verts[idx]
        wall.append(len(verts))
        static.append(len(verts))
        verts.append((x, y, -SKIRT))

    # WOUND OUTWARD BY HAND, because recalc_face_normals is not run on this mesh.
    #
    # The ring walks the border counter-clockwise seen from above, so for a wall quad the
    # outward face is the one that goes ALONG the ring at the bottom and back at the top,
    # not the other way round -- butter's order gives inward normals and relies on recalc
    # to turn them. That was fine there and is not fine here: recalc recomputes the whole
    # mesh from scratch, so it also overwrote the top faces, and the winding this file
    # works so hard to guarantee never survived to the export. Eight faces came out
    # inverted anyway, in the corners, where the geometry is thin enough that recalc's
    # choice is a coin toss.
    for k in range(n):
        faces.append((ring[k], wall[k], wall[(k + 1) % n], ring[(k + 1) % n]))

    centre = len(verts)
    static.append(centre)
    verts.append((0.0, 0.0, -SKIRT))
    # Clockwise from above, so the underside faces DOWN.
    for k in range(n):
        faces.append((centre, wall[(k + 1) % n], wall[k]))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    for index, poly in enumerate(mesh.polygons):
        poly.use_smooth = index < top_face_count

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    # No recalc_face_normals. Every face above was wound deliberately, and the check in
    # validate_mesh is what confirms it rather than a pass that would silently redo it.
    return obj, set(static), top_face_count


def export_fbx(mesh_obj, arm_obj, filename):
    """Butter's exporter with a finer UV scale.

    5.0 studs per tile rather than 8.0. The texture is pure fuzz at this point -- see the
    docstring -- and fuzz is a fine-grained thing: stretched to 8 studs the individual
    hairs turn into streaks, which reads as wet fur rather than dry felt.
    """
    uv_project.box_project(mesh_obj.data, 5.0)

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
    return f"LambsEar_Platform_{size_x:.0f}x{size_z:.0f}"


def build_variant(size_x, size_z):
    name = mesh_name(size_x, size_z)
    cols, rows, cell_x, cell_z = BUTTER.compute_grid(size_x, size_z)
    mesh_obj, static, n_top = build_surface(size_x, size_z, name)
    arm_obj, centres = BUTTER.build_armature(size_x, size_z, cols, rows, name + "_Rig")
    covered = BUTTER.assign_weights(mesh_obj, arm_obj, static, centres, cell_x, cell_z)
    ok = BUTTER.validate_mesh(mesh_obj, n_top) and covered

    tris = sum(len(p.vertices) - 2 for p in mesh_obj.data.polygons)
    zs = [v.co.z for v in mesh_obj.data.vertices]
    low, high = min(zs), max(zs)
    # NO SHELL_THICKNESS TERM, unlike butter and ice. Nothing is laid on top of this
    # surface, so the leaves themselves are what you walk on and the walkable plane is
    # their highest point plus a hair of clearance.
    CLEARANCE = 0.02
    walkable = high + CLEARANCE
    # BALD PATCHES ARE THE FAILURE MODE WORTH MEASURING. A leaf bed with a gap in it
    # reads as a hole in the platform, and the scatter is random enough to leave one. So
    # the interior is sampled for how much of it no leaf covers; anything above a few per
    # cent means LEAF_SPACING is too wide for LEAF_A and LEAF_B.
    leaves = scatter_leaves(size_x, size_z)
    samples, bare = 0, 0
    step = 0.5
    x = -size_x / 2 + 1.0
    while x < size_x / 2 - 1.0:
        y = -size_z / 2 + 1.0
        while y < size_z / 2 - 1.0:
            samples += 1
            if leaf_relief(x, y, leaves) < 0.02:
                bare += 1
            y += step
        x += step
    coverage = 100.0 * (1.0 - bare / max(1, samples))

    print(f"  {name}: {cols}x{rows} grid, {len(centres)} bones, {tris} tris, "
          f"leaves cover {coverage:.1f}%, crown {high - THICK:+.2f}, "
          f"{'valid' if ok else 'INVALID'}")
    entry = (f"\t\t{{ sizeX = {size_x:.0f}, sizeZ = {size_z:.0f}, "
             f"meshHeight = {high - low:.2f}, surfaceOffset = {walkable - (low + high) / 2.0:.2f}, "
             f'mesh = "{name}" }},')
    return mesh_obj, arm_obj, entry, ok


def main():
    entries, all_ok = [], True
    all_ok = check_profile_tapers() and all_ok
    for size_x, size_z in SIZES:
        BUTTER.clear_scene()
        mesh_obj, arm_obj, entry, ok = build_variant(size_x, size_z)
        all_ok = all_ok and ok
        export_fbx(mesh_obj, arm_obj, mesh_name(size_x, size_z) + ".fbx")
        entries.append(entry)

    print("")
    print("  ChunkBuilder SKINNED_PLATFORMS entry:")
    print("\tLambsEar = {")
    for entry in entries:
        print(entry)
    print("\t},")
    print("")
    print("Done." if all_ok else "!! a mesh failed validation -- DO NOT import.")


if __name__ == "__main__":
    main()
