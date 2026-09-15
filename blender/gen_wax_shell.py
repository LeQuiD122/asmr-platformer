"""
Skinned wax coating, fractured into Voronoi shards. Blender 5.2 -> FBX -> Roblox.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_wax_shell.py

Exports one mesh per butter slab size (16 x 8 and 12 x 10), matching gen_butter_skinned.

=== Why a mesh, and why Voronoi ===

The wax was built out of Parts three times and read as squares every time. The reason is
structural, not cosmetic: EXACT TILING WITH BOXES FORCES AXIS-ALIGNED RECTANGLES. A
recursive split can vary the sizes as much as it likes and mix in diagonal wedges, but
every cut still runs parallel to X or Z, so the crack lines stay parallel to the
platform's own edges and the eye reads a grid. Rotating a box breaks the tiling.

A Voronoi partition has none of that. Its cells are convex polygons whose edges sit at
whatever angle the seed points dictate, which is what actual fracture looks like -- and
because the whole coating is ONE MeshPart, there are no part boundaries to draw
outlines either. The only lines visible are the grooves between shards, which are the
cracks.

=== How it moves ===

Every shard is weighted RIGIDLY to its own bone: one bone, weight 1, no blending. That
is the opposite of the honey and slime rigs, where overlapping influences are the whole
point -- there a dent has to melt into the surrounding surface, here a shard is a piece
of brittle solid and has to move as one rather than bending. Pushing its bone out and
down separates it cleanly from its neighbours and widens the grooves into open cracks.

Roblox blends at most four bones per vertex; using exactly one is well inside that and
also the cheapest possible skinning.

=== Constraints shared with the other rigs ===

  * Bones point along Blender +Z, which the FBX Y-up conversion turns into Roblox +Y.
  * FBX exports at global_scale 0.01 because Roblox imports these at 100x.
  * Collision does not follow a skinned mesh. The Part tiles remain the floor.

Bones here are named Shard_<i> and are NOT on the sub-region grid, so the renderer
matches them by world position rather than by name -- a shard belongs to whichever cell
contains it.
"""

import bmesh
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import uv_project
import bpy
import math
import os
import random
import sys

# Blender runs a --python script without putting its directory on the path, so the
# import of the butter generator below fails unless this is done first.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

OUT_DIR = r"C:\Users\Arsenii\Downloads\asmr-platformer-implementation_1\RobloxProject\meshes"

# Must match ChunkBuilder's SHELL_THICKNESS and the butter rig's sizes.
SHELL_THICKNESS = 0.3
# 16x12 IS THE BUTTER STICKS, and a flat shell over them is not a compromise: a stick of
# butter comes WRAPPED, and one wrapper spans all three. The tops are flat and level end
# to end, so the plates sit on them exactly as they sit on a flat butter slab, and the
# grooves between the sticks are simply bridged -- which is what paper does.
SIZES = ((16.0, 8.0), (12.0, 10.0))

# RELIEF: a height offset for the plates, so a coating can follow a surface that is not flat.
#
# Every shell here used to be a flat slab, which is right over butter and ice -- both are flat
# slabs themselves. Over the three butter STICKS it was wrong in the most obvious way possible:
# a flat sheet laid across three ridges bridges them completely and hides the whole chunk under
# a white lid, which is what the screenshot shows.
#
# Set this to a function of (x, z) returning studs to ADD to every plate vertex, and the
# coating drapes instead. It must be <= 0 everywhere so the top of the mesh is unchanged and
# the measured surfaceOffset stays valid.
RELIEF = None


def relief_at(x, z):
    return RELIEF(x, z) if RELIEF else 0.0

# Square studs per PLATE in the coarse tier. Big on purpose -- see make_seeds.
BASE_AREA = 11.0

# NO GROOVE. Shards share their edges exactly, so at rest the coating is one unbroken
# surface with nothing to see: an intact wax film has no cracks in it, and any inset
# here draws them from the moment the platform is built. The cracks are the gaps the
# renderer opens by moving bones apart, and they exist only where someone has stood.
#
# Zero rather than negative: overlapping shards would double the transparency along
# every shared edge and draw exactly the lines this is removing.
GROOVE = 0.0

# Seed jitter as a fraction of the grid spacing. 0 gives a regular lattice, which
# produces near-hexagonal cells of equal size -- tidy, and just as artificial as the
# rectangles. High values clump seeds together and make slivers.
JITTER = 0.42

# TWO TIERS. A single lattice, however jittered or thinned, gives every cell the same
# order of area -- the fracture comes out evenly diced. Real breakage is bimodal: large
# plates survive intact next to a region that shattered into chips.
#
# So the coarse lattice lays down plates, and a fraction of them are then shattered by
# dropping a cluster of extra seeds inside one plate's territory. Those seeds carve that
# plate up between them and leave every other plate untouched.
SHATTER_FRACTION = 0.42
CHIPS_PER_CLUSTER = (3, 5)

# Two fracture patterns per size, so two platforms of the same size are not identical.
# Combined with the 180-degree yaw ChunkBuilder can apply, that is four distinct looks
# from four imported meshes.
VARIANTS = ("A", "B")

# The coating wraps the whole block, not just the top: a band around the sides and a
# plate underneath, both fractured the same way. Depths are DERIVED from the butter
# generator rather than typed here, so the wrap follows the block if it is ever
# retuned -- a hardcoded drop would leave a stripe of bare butter the moment THICK
# changed, and it would be visible only from below.
import gen_butter_skinned as butter  # noqa: E402

BAND_CLEARANCE = 0.02
BAND_TOP = 0.0
BAND_BOTTOM = -(SHELL_THICKNESS + BAND_CLEARANCE) - (butter.THICK + butter.CROWN + butter.SKIRT)
# The plan outline the band follows. Matches the butter's own corner radius so the
# coating turns the corner with the block rather than cutting across it.
BAND_CORNER = butter.CORNER
# Outline samples. This sets how round the corners read AND, through `densify` below,
# how finely a band shard is cut as it crosses one -- so it is also what decides whether
# the band's inner face stays outside the butter at the corners.
#
# 120 put only four samples on each quadrant, and four chords across a 1-stud arc bow
# 0.019 studs inward against BAND_CLEARANCE of 0.02. That is a clearance of one
# thousandth of a stud, which is not a clearance at all. 240 leaves 0.015.
BAND_STEPS = 240
BAND_AREA_PER_SHARD = 4.5

# THE PLATES ARE ROUNDED TOO. They used to be clipped to a plain rectangle, so the band
# turned each corner on an arc while the lid and the underside cut straight across it --
# four square wax corners sitting on a rounded block.
#
# DERIVED, not chosen. The plates reach out to the band's OUTER face, and offsetting a
# rounded rectangle outward by d raises its radius by exactly d. So this is the only
# value at which the plate rim meets the band all the way around: larger and the plate
# pulls in and exposes a sliver of the band's top face at each corner, smaller and it
# overhangs into thin air.
#
# Rounding the wax MORE than this means rounding the butter body underneath by the same
# amount, because a plan corner tighter on the block than on its coating pushes bare
# butter out through the wrap. That is a change to the body's silhouette, which is
# deliberately squarish, so it is not something to do quietly here.
PLATE_CORNER = BAND_CORNER + SHELL_THICKNESS
PLATE_CORNER_STEPS = 8  # chords per corner quadrant

# Voronoi occasionally produces a sliver too small to survive triangulation. Below this
# a cell is dropped rather than exported as a degenerate face.
MIN_SHARD_AREA = 0.08


def clip_halfplane(poly, nx, nz, c):
    """Sutherland-Hodgman: keep the part of `poly` where n . r <= c."""
    if not poly:
        return []
    out = []
    count = len(poly)
    for i in range(count):
        ax, az = poly[i]
        bx, bz = poly[(i + 1) % count]
        da = nx * ax + nz * az - c
        db = nx * bx + nz * bz - c
        if da <= 0:
            out.append((ax, az))
        if (da > 0) != (db > 0):
            t = da / (da - db)
            out.append((ax + (bx - ax) * t, az + (bz - az) * t))
    return out


def rect_boundary(half_x, half_z):
    """The plain rectangle, counter-clockwise."""
    return [(-half_x, -half_z), (half_x, -half_z), (half_x, half_z), (-half_x, half_z)]


def rounded_rect(half_x, half_z, radius, per_corner):
    """A rounded rectangle as a convex polygon, counter-clockwise.

    A polygon rather than a special case in the clipper: `clip_halfplane` already takes
    any convex outline, so the corner arcs cost nothing beyond a few more edges, and
    every downstream test that treats the boundary as a list of segments keeps working.
    """
    radius = max(0.0, min(radius, half_x * 0.9, half_z * 0.9))
    if radius < 1e-6:
        return rect_boundary(half_x, half_z)
    ix, iz = half_x - radius, half_z - radius
    quadrants = (
        (ix, -iz, -math.pi / 2.0),
        (ix, iz, 0.0),
        (-ix, iz, math.pi / 2.0),
        (-ix, -iz, math.pi),
    )
    poly = []
    for cx, cz, start in quadrants:
        for k in range(per_corner + 1):
            angle = start + (math.pi / 2.0) * k / per_corner
            poly.append((cx + math.cos(angle) * radius, cz + math.sin(angle) * radius))
    # The straights need no samples of their own: consecutive quadrants end and begin at
    # the two ends of a straight, so the polygon edge between them IS that straight.
    return poly


def voronoi_cells(seeds, boundary):
    """Each cell as a convex polygon, clipped to `boundary`.

    Built by half-plane intersection rather than by a sweep: for a few dozen seeds the
    O(n^2) cost is nothing, and clipping to an outline needs no special cases -- the
    platform edge is just more half-planes of the same kind that are already there.
    """
    cells = []
    for i, (px, pz) in enumerate(seeds):
        poly = boundary[:]
        for j, (qx, qz) in enumerate(seeds):
            if i == j:
                continue
            # Perpendicular bisector of p and q, keeping the side nearer p.
            poly = clip_halfplane(
                poly, qx - px, qz - pz,
                (qx * qx + qz * qz - px * px - pz * pz) / 2.0,
            )
            if not poly:
                break
        cells.append(poly)
    return cells


def inset(poly, d):
    """Shrink a convex polygon by `d` on every edge, opening the grooves."""
    out = poly[:]
    count = len(poly)
    for k in range(count):
        ax, az = poly[k]
        bx, bz = poly[(k + 1) % count]
        ex, ez = bx - ax, bz - az
        length = math.hypot(ex, ez)
        if length < 1e-9:
            continue
        # Outward normal of a counter-clockwise edge.
        nx, nz = ez / length, -ex / length
        out = clip_halfplane(out, nx, nz, nx * ax + nz * az - d)
        if not out:
            return []
    return out


def make_seeds(half_x, half_z, rng):
    """Coarse plates, some of which are shattered into clusters of chips.

    The jitter keeps every edge at its own angle; the two tiers are what give the sizes
    real spread. A cluster of seeds dropped inside one plate divides only that plate,
    because Voronoi territory is local -- its neighbours keep their area."""
    base = max(4, int(round(4 * half_x * half_z / BASE_AREA)))
    aspect = half_x / half_z
    rows = max(2, int(round(math.sqrt(base / aspect))))
    cols = max(2, int(round(base / rows)))
    step_x, step_z = (2 * half_x) / cols, (2 * half_z) / rows

    seeds = []
    for c in range(cols):
        for r in range(rows):
            bx = -half_x + (c + 0.5 + (rng.random() - 0.5) * JITTER * 2) * step_x
            bz = -half_z + (r + 0.5 + (rng.random() - 0.5) * JITTER * 2) * step_z
            seeds.append((bx, bz))

            if rng.random() < SHATTER_FRACTION:
                for _ in range(rng.randint(*CHIPS_PER_CLUSTER)):
                    angle = rng.random() * math.tau
                    reach = min(step_x, step_z) * (0.12 + rng.random() * 0.34)
                    seeds.append((
                        max(-half_x, min(half_x, bx + math.cos(angle) * reach)),
                        max(-half_z, min(half_z, bz + math.sin(angle) * reach)),
                    ))
    return seeds


def on_outer_edge(a, b, boundary, eps=1e-6):
    """True when an edge lies along the outline's own perimeter.

    This is what decides which shard edges get a vertical wall, so it has to follow the
    boundary exactly. The axis-aligned version it replaces tested four lines, which was
    only ever right for a square outline -- against the rounded plates every edge lying
    on a corner chord came back False and the rim was left open there.

    BOTH endpoints must sit on the SAME boundary segment. Two points on different
    segments span the interior, and walling that would put a face through the shard.
    """
    count = len(boundary)
    for k in range(count):
        ax, az = boundary[k]
        bx, bz = boundary[(k + 1) % count]
        ex, ez = bx - ax, bz - az
        length = math.hypot(ex, ez)
        if length < 1e-9:
            continue
        # A convex polygon touches the supporting line of an edge along that edge alone,
        # so lying on the line is enough -- no separate in-segment test is needed.
        nx, nz = ez / length, -ex / length
        c = nx * ax + nz * az
        if abs(nx * a[0] + nz * a[1] - c) < eps and abs(nx * b[0] + nz * b[1] - c) < eps:
            return True
    return False


def polygon_area(poly):
    n = len(poly)
    return abs(sum(poly[k][0] * poly[(k + 1) % n][1] - poly[(k + 1) % n][0] * poly[k][1]
                   for k in range(n))) / 2.0


def outline(half_x, half_z, radius, steps):
    """The platform's rounded-rectangle plan, sampled evenly BY ARC LENGTH, as
    (x, z, outward normal x, outward normal z).

    By arc length rather than by angle or by axis: parameterise any other way and the
    band's shards bunch up at the corners while the straights stretch.

    Built as an explicit list of segments walked counter-clockwise. The first attempt
    tried to walk a flat table of leg lengths and got its own termination test wrong --
    it compared against the LAST leg's kind, which is a corner, so every corner matched
    and the walk stopped at the first one. Every point past the bottom edge came out on
    the wrong part of the outline.
    """
    radius = min(radius, half_x * 0.9, half_z * 0.9)
    ix, iz = half_x - radius, half_z - radius
    half_pi = math.pi / 2.0

    segments = (
        ("line", (-ix, -half_z), (ix, -half_z), (0.0, -1.0)),
        ("arc", (ix, -iz), -half_pi, 0.0, None),
        ("line", (half_x, -iz), (half_x, iz), (1.0, 0.0)),
        ("arc", (ix, iz), 0.0, half_pi, None),
        ("line", (ix, half_z), (-ix, half_z), (0.0, 1.0)),
        ("arc", (-ix, iz), half_pi, math.pi, None),
        ("line", (-half_x, iz), (-half_x, -iz), (-1.0, 0.0)),
        ("arc", (-ix, -iz), math.pi, 3 * half_pi, None),
    )

    lengths = []
    for seg in segments:
        if seg[0] == "line":
            lengths.append(math.dist(seg[1], seg[2]))
        else:
            lengths.append(abs(seg[3] - seg[2]) * radius)
    total = sum(lengths)

    points = []
    for i in range(steps):
        d = total * i / steps
        for index, (seg, length) in enumerate(zip(segments, lengths)):
            if d <= length or index == len(segments) - 1:
                t = d / length if length > 1e-9 else 0.0
                if seg[0] == "line":
                    points.append((
                        seg[1][0] + (seg[2][0] - seg[1][0]) * t,
                        seg[1][1] + (seg[2][1] - seg[1][1]) * t,
                        seg[3][0], seg[3][1],
                    ))
                else:
                    angle = seg[2] + (seg[3] - seg[2]) * t
                    points.append((
                        seg[1][0] + math.cos(angle) * radius,
                        seg[1][1] + math.sin(angle) * radius,
                        math.cos(angle), math.sin(angle),
                    ))
                break
            d -= length
    return points, total


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.armatures):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def build_shards(size_x, size_z, name, seed):
    """One mesh holding every shard as a separate closed prism, plus the vertex ranges
    each shard occupies so weights can be assigned rigidly."""
    half_x, half_z = size_x / 2.0, size_z / 2.0
    rng = random.Random(seed)

    verts, faces, groups = [], [], []

    # The plates reach all the way out to the band's OUTER face, so the three pieces
    # close into one box. Sized to the platform alone they stopped at the band's inner
    # face, leaving a hairline gap running right around the top and the bottom -- which
    # is what made the coating read as present in some places and missing in others.
    wrap = BAND_CLEARANCE + SHELL_THICKNESS
    plate_x, plate_z = half_x + wrap, half_z + wrap
    # Both plates share one outline, and it is the band's outer face (see PLATE_CORNER).
    plate_bound = rounded_rect(plate_x, plate_z, PLATE_CORNER, PLATE_CORNER_STEPS)

    def add_plate(top_z, facing_up, tier):
        """A flat fractured slab, used for both the top of the coating and the plate
        underneath it. `facing_up` flips the winding so the outward face is the one you
        can actually see."""
        # Seeds are still scattered over the full RECTANGLE, not the rounded outline. A
        # seed out in a clipped corner simply owns nothing and its cell drops out below,
        # and keeping the call identical keeps the random stream identical -- seeding
        # from the rounded area instead would draw a different number of values here and
        # re-roll the band and the underside that follow it off the same generator.
        for poly in voronoi_cells(make_seeds(plate_x, plate_z, rng), plate_bound):
            shape = inset(poly, GROOVE) if GROOVE > 0 else poly
            if len(shape) < 3 or polygon_area(shape) < MIN_SHARD_AREA:
                continue
            start = len(verts)
            n = len(shape)
            # THE TOP PLATE ONLY. add_plate is called twice -- once for the coating you see
            # and once for the plate far underneath at BAND_BOTTOM -- and draping BOTH was
            # the tangle of shards hanging under the butter chunk. The underside is nowhere
            # near the surface being followed, so relief there does not drape it, it shreds
            # it: every shard gets pulled a different distance out of a plane it shared with
            # its neighbours.
            drape = relief_at if facing_up else (lambda x, z: 0.0)
            for x, z in shape:
                verts.append((x, z, top_z + drape(x, z)))
            for x, z in shape:
                verts.append((x, z, top_z - SHELL_THICKNESS + drape(x, z)))
            for k in range(1, n - 1):
                if facing_up:
                    faces.append((start, start + k, start + k + 1))
                    faces.append((start + n, start + n + k + 1, start + n + k))
                else:
                    faces.append((start, start + k + 1, start + k))
                    faces.append((start + n, start + n + k, start + n + k + 1))
            for k in range(n):
                nk = (k + 1) % n
                if on_outer_edge(shape[k], shape[nk], plate_bound):
                    faces.append((start + k, start + n + k, start + n + nk, start + nk))
            cx = sum(p[0] for p in shape) / n
            cz = sum(p[1] for p in shape) / n
            groups.append({"first": start, "last": len(verts) - 1, "tier": tier,
                           "cx": cx, "cz": cz, "area": polygon_area(shape)})

    def add_band():
        """The wrap around the sides.

        Fractured in (ARC LENGTH, HEIGHT) space and then mapped onto the outline, so the
        shards follow the perimeter and turn the corners with it. Fracturing in world XZ
        instead would cut the band with vertical planes and leave every corner shard
        wedge-shaped.

        It is a closed loop, so it has no left or right boundary -- only a top and a
        bottom edge get walls, and neighbouring shards share their vertical edges."""
        path, perimeter = outline(half_x + BAND_CLEARANCE, half_z + BAND_CLEARANCE,
                                  BAND_CORNER, BAND_STEPS)
        # Between the undersides of the two plates, so the band tucks under the top
        # plate and over the bottom one instead of butting against their edges.
        height = (BAND_TOP - SHELL_THICKNESS) - BAND_BOTTOM
        half_s, half_h = perimeter / 2.0, height / 2.0
        count = max(6, int(round(perimeter * height / BAND_AREA_PER_SHARD)))

        def to_world(s_along, h, outward):
            # INTERPOLATED between outline samples, not snapped to the nearest one.
            # Snapping quantises the arc-length coordinate to BAND_STEPS, so any shard
            # edge shorter than one step collapses to a point and the face it belongs
            # to comes out with zero area.
            t = (s_along + half_s) / perimeter * len(path)
            i0 = int(math.floor(t)) % len(path)
            i1 = (i0 + 1) % len(path)
            f = t - math.floor(t)
            a, b = path[i0], path[i1]
            px = a[0] + (b[0] - a[0]) * f
            pz = a[1] + (b[1] - a[1]) * f
            nx = a[2] + (b[2] - a[2]) * f
            nz = a[3] + (b[3] - a[3]) * f
            scale = math.hypot(nx, nz) or 1.0
            reach = SHELL_THICKNESS if outward else 0.0
            return (px + nx / scale * reach, pz + nz / scale * reach,
                    (BAND_TOP - SHELL_THICKNESS) - (half_h - h))

        # WHERE THE OUTLINE TURNS. Along a straight run the normal is constant, and a
        # chord between two samples IS the outline, so cutting a shard there would add
        # vertices and change nothing. All of the error is in the arcs.
        step = perimeter / len(path)
        turning = set()
        for i in range(len(path)):
            if (abs(path[i][2] - path[i - 1][2]) > 1e-9
                    or abs(path[i][3] - path[i - 1][3]) > 1e-9):
                turning.add(i)

        def split_at_corners(shape):
            """The shard cut into pieces that each sit between two adjacent corner
            samples, so no FACE spans an arc.

            The failure this fixes: a shard is triangulated as a fan, so a shard lying
            across a corner comes out as one flat plate that CHAMFERS the corner off.
            The plate sits r(1 - cos(theta/2)) inside the outline, which for a shard
            spanning a quadrant of the 1-stud radius is 0.29 studs, against 0.02 studs
            of clearance -- so the butter showed through at all four corners.

            Measuring shard AREA found nothing wrong and could not have: every shard was
            present and the band covered the block exactly in (arc length, height)
            space. The hole opened in the MAPPING, and only a view of the corner shows
            it. Following the arc along the shard's own outline is not enough either --
            that leaves the boundary correct and the fan interior still flat.

            Cut with the same half-plane clipper the fracture itself uses, so the pieces
            tile the shard with no gap. Neighbouring shards stay watertight because the
            cut positions are global: a shared edge is cut at the same arc-lengths from
            both sides, and its two sets of points interpolate to the same places.
            """
            lo = min(p[0] for p in shape)
            hi = max(p[0] for p in shape)
            pieces = []
            rest = shape
            for i in range(len(path)):
                s = i * step - half_s
                if i not in turning or not (lo < s < hi):
                    continue
                piece = clip_halfplane(rest, 1.0, 0.0, s)
                rest = clip_halfplane(rest, -1.0, 0.0, -s)
                if len(piece) >= 3 and polygon_area(piece) > 1e-9:
                    pieces.append(piece)
                if len(rest) < 3:
                    return pieces
            if len(rest) >= 3 and polygon_area(rest) > 1e-9:
                pieces.append(rest)
            return pieces

        # A genuine rectangle, and it stays one: this is (arc length, height) space, so
        # rounding it would round the band's TOP AND BOTTOM EDGES in elevation, not its
        # plan corners. The band already turns the plan corner through `outline`.
        band_bound = rect_boundary(half_s, half_h)
        for poly in voronoi_cells(make_seeds(half_s, half_h, rng), band_bound):
            shape = inset(poly, GROOVE) if GROOVE > 0 else poly
            if len(shape) < 3 or polygon_area(shape) < MIN_SHARD_AREA:
                continue
            # ONE SHARD, SEVERAL PIECES, STILL ONE BONE. The pieces are consecutive in
            # the vertex list, so the group below still covers all of them with a single
            # range and the shard moves as the one rigid plate it is meant to be.
            shard_start = len(verts)
            centre_x, centre_z, sampled = 0.0, 0.0, 0
            for piece in split_at_corners(shape):
                start = len(verts)
                n = len(piece)
                for s_along, h in piece:
                    verts.append(to_world(s_along, h, False))
                for s_along, h in piece:
                    verts.append(to_world(s_along, h, True))
                band_faces = []
                for k in range(1, n - 1):
                    band_faces.append((start, start + k + 1, start + k))
                    band_faces.append((start + n, start + n + k, start + n + k + 1))
                for k in range(n):
                    nk = (k + 1) % n
                    # The cut edges are INTERIOR to the shard and must stay open. They
                    # sit at an arc-length the boundary test never matches, so they are
                    # skipped for free -- walling them would put a face through the
                    # middle of a plate.
                    if on_outer_edge(piece[k], piece[nk], band_bound):
                        band_faces.append((start + k, start + nk, start + n + nk, start + n + k))

                # WINDING IS ENFORCED, not assumed.
                #
                # The band's shards are polygons in (arc length, height) mapped onto a
                # curved outline, so whether a given winding ends up facing in or out
                # depends on how the parameterisation lands -- and it lands differently
                # on the straights and on the corners. Guessing produced faces pointing
                # into the block along parts of the perimeter, which is why the butter
                # showed through at the ends.
                #
                # So: measure each face's normal, compare it with the outward direction
                # at its own centroid, and reverse the ones facing the wrong way.
                # Inner-ring faces should look toward the block, outer-ring faces away.
                for index, face in enumerate(band_faces):
                    pts = [verts[i] for i in face]
                    ux = (pts[1][0] - pts[0][0], pts[1][1] - pts[0][1], pts[1][2] - pts[0][2])
                    vx = (pts[2][0] - pts[0][0], pts[2][1] - pts[0][1], pts[2][2] - pts[0][2])
                    normal = (ux[1] * vx[2] - ux[2] * vx[1],
                              ux[2] * vx[0] - ux[0] * vx[2],
                              ux[0] * vx[1] - ux[1] * vx[0])
                    cx = sum(q[0] for q in pts) / len(pts)
                    cz = sum(q[1] for q in pts) / len(pts)
                    reach = math.hypot(cx, cz) or 1.0
                    outward = normal[0] * cx / reach + normal[1] * cz / reach
                    inner_ring = face[0] < start + n
                    want_inward = inner_ring
                    if (outward < 0) != want_inward:
                        band_faces[index] = tuple(reversed(face))
                faces.extend(band_faces)
                for k in range(n):
                    centre_x += verts[start + k][0]
                    centre_z += verts[start + k][1]
                    sampled += 1

            if sampled == 0:
                continue
            # The bone sits at the centroid of the WHOLE shard, averaged over every
            # piece, so cutting a shard for geometry does not move where it pivots.
            groups.append({"first": shard_start, "last": len(verts) - 1, "tier": "S",
                           "cx": centre_x / sampled, "cz": centre_z / sampled,
                           "area": polygon_area(shape)})

    # TIERS ARE NAMED, not inferred from height at runtime. The renderer treats the
    # three completely differently -- the top follows the foot, the sides trail it as a
    # secondary effect, and the underside never moves at all -- and a height threshold
    # would silently reclassify shards the moment the block's thickness changed.
    add_plate(0.0, True, "T")        # top
    add_band()                       # sides, tagged S
    add_plate(BAND_BOTTOM, False, "U")  # underside

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    # NO recalc_face_normals. It infers inside from outside using connectivity, and
    # with the interior walls gone this is no longer a closed solid -- on an open mesh
    # it can decide the whole thing faces the wrong way. The winding is already correct
    # by construction: Voronoi cells come out counter-clockwise, so the top fan faces
    # +Z and the reversed bottom fan faces -Z. validate_mesh checks that it stayed so.
    return obj, groups


def build_armature(groups, rig_name):
    arm_data = bpy.data.armatures.new(rig_name)
    arm_obj = bpy.data.objects.new(rig_name, arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    root = arm_data.edit_bones.new("Root")
    root.head = (0.0, 0.0, 0.0)
    root.tail = (0.0, 0.0, 1.0)

    for index, g in enumerate(groups, start=1):
        bone = arm_data.edit_bones.new(f"Shard_{g['tier']}_{index}")
        bone.head = (g["cx"], g["cz"], 0.0)
        bone.tail = (g["cx"], g["cz"], 0.6)
        bone.parent = root
        bone.use_connect = False

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def assign_weights(obj, arm_obj, groups):
    """RIGID: every vertex of a shard belongs to that shard's bone alone.

    The honey and slime rigs blend several bones per vertex on purpose, so a dent melts
    into the surface around it. A shard of brittle wax must do the opposite -- it is one
    solid piece and has to translate and tilt without deforming, or the crack looks like
    the surface sagging rather than a plate lifting."""
    for index, g in enumerate(groups, start=1):
        group = obj.vertex_groups.new(name=f"Shard_{g['tier']}_{index}")
        group.add(list(range(g["first"], g["last"] + 1)), 1.0, "REPLACE")

    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = arm_obj
    obj.parent = arm_obj


def validate_mesh(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    problems = []
    if sum(1 for f in bm.faces if f.calc_area() < 1e-7):
        problems.append("zero-area faces")
    up = sum(1 for f in bm.faces if f.normal.z > 0.9)
    down = sum(1 for f in bm.faces if f.normal.z < -0.9)
    if up == 0:
        problems.append("no upward faces at all")
    if down == 0:
        problems.append("no downward faces at all")
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
    # 6.0 studs per tile, sized for crazing. The scale is in studs rather than repeats so
    # every platform size shows the same physical detail instead of stretching it to fit.
    uv_project.box_project(mesh_obj.data, 6.0)

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


def mesh_name(size_x, size_z, variant):
    return f"Wax_Shell_{size_x:.0f}x{size_z:.0f}_{variant}"


def build_variant(size_x, size_z, variant):
    name = mesh_name(size_x, size_z, variant)
    seed = int(size_x * 131 + size_z * 17) + ord(variant) * 9173
    obj, groups = build_shards(size_x, size_z, name, seed)
    arm = build_armature(groups, name + "_Rig")
    assign_weights(obj, arm, groups)
    ok = validate_mesh(obj)

    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    zs = [v.co.z for v in obj.data.vertices]
    areas = sorted(g["area"] for g in groups)
    print(f"  {name}: {len(groups)} shards, {tris} tris, "
          f"area {areas[0]:.2f}..{areas[-1]:.2f} ({areas[-1] / areas[0]:.1f}x), "
          f"{'valid' if ok else 'INVALID'}")
    # surfaceOffset is measured from the bbox CENTRE up to the plane ChunkBuilder aligns
    # with SURFACE_Y, and the shell's top is that plane (local z = 0).
    #
    # COMPUTED, not assumed to be half the thickness. That held while the coating was a
    # flat lid, but it now wraps the sides and the underside, so the bounding box reaches
    # far below the top and its centre is nowhere near it. The stale value would have
    # floated the wax about 1.6 studs above the platform.
    surface_offset = -(min(zs) + max(zs)) / 2.0
    entry = (f"\t\t{{ sizeX = {size_x:.0f}, sizeZ = {size_z:.0f}, "
             f"surfaceOffset = {surface_offset:.3f}, "
             f'mesh = "{name}" }},')
    return obj, arm, entry, ok, groups


def main():
    entries, all_ok = [], True
    for size_x, size_z in SIZES:
        for variant in VARIANTS:
            clear_scene()
            obj, arm, entry, ok, _ = build_variant(size_x, size_z, variant)
            all_ok = all_ok and ok
            export_fbx(obj, arm, mesh_name(size_x, size_z, variant) + ".fbx")
            entries.append(entry)

    print("")
    print("  ChunkBuilder WAX_SHELLS entry:")
    for entry in entries:
        print(entry)
    print("")
    print("Done." if all_ok else "!! a mesh failed validation -- DO NOT import.")


if __name__ == "__main__":
    main()
