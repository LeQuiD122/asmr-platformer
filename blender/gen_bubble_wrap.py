"""
Rigged bubble wrap sheets: a continuous film with pockets moulded INTO it.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_bubble_wrap.py

Replaces spawning a Part per bubble. Separate spheres could never be bubble wrap: they
sat ON the surface rather than being part of it, they could not deform (a Part scales,
it does not flatten while its rim stays put), and there was no film between them at all
-- so the material read as a tray of marbles on a plate.

One bone per pocket, and the WEIGHTING is what makes a pop work. A vertex is weighted by
how far up its own dome it sits: the apex is 1.0, the rim is 0.0, the flat film is 0.0.
So pulling a bone straight down by BUBBLE_H collapses that dome into the sheet while its
rim and every neighbour stay exactly where they are. That is a pop. Nothing else in the
mesh moves, which is why one bone per pocket is worth the count.

THE SHEET IS NOT THE PLATFORM. Honey, slime and butter are rigs that BECOME the visible
platform, so ChunkBuilder hides the slab under them. Bubble wrap is a wrap: it is laid
over a slab that stays visible underneath. The whole sheet is authored to fit in the
TILE_THICKNESS layer (0.9 studs) that sits between the slab's top face and the walkable
plane, so it covers the slab without floating above it or sinking into it.
"""

import bpy
import contextlib
import bmesh
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import uv_project
import mathutils
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

OUT_DIR = r"C:\Users\Arsenii\Downloads\asmr-platformer-implementation_1\RobloxProject\meshes"

# The layer the TOP of the sheet has to live in: ChunkBuilder's TILE_THICKNESS. The
# pocket apexes are the walkable plane and the film hangs below them, so the top film
# plus a pocket must fit here or the film sinks through the slab's own top face.
TILE_LAYER = 0.9

# The wrap goes right around the slab, so it needs the slab's depth. Read from
# ChunkBuilder rather than typed, for the same reason the size list is.
def _slab_depth():
    import chunk_layout

    _, _, constants = chunk_layout.layout_all()
    return constants["SLAB_THICKNESS"]


# How far the wrap stands off the slab's sides.
#
# 0.36, and it is CORNER that sets it, not z-fighting clearance. The slab is a Part and
# its corners are a hard 90 degrees; round the film's plan and those square corners cut
# straight back out through it. A rounded rectangle offset by `w` from a square one
# contains the square's corner only while CORNER <= w / (sqrt2 - 1), so a 0.85 radius
# needs at least 0.352 of standoff. Under that, each corner grows an opaque nub of bare
# slab poking through the wrap.
WRAP_OUT = 0.36

# Plan corner radius. Roughly the butter block's 1.0, for consistency across the level:
# every other rig here turns its corners rather than meeting them square.
CORNER = 0.85
CORNER_STEPS = 6  # chords per corner quadrant

# Side and underside pockets, as a fraction of the top ones. ONE, i.e. no difference.
#
# This was 0.42, on the theory that wrap pulled taut round a block has flatter pockets
# on its walls, and it was a mistake. The radius never changed, only the height -- so a
# wall pocket was the same width as a top one at a third of the height, and a shallow
# cap of a given radius reads as a WIDER circle than a full dome of the same radius, not
# a smaller one. The sides ended up looking like big flat discs next to the top's tidy
# bubbles: the opposite of the intent.
#
# The cost is overhang. At full height the wrap stands WRAP_OUT + BUBBLE_H = 1.0 stud
# proud of the slab on every side, so a 16-wide platform LOOKS 18 wide while only 16 of
# it holds you up. Collision is the tile grid, so this is purely a read: turn it back
# down if the edges start reading as walkable when they are not.
SIDE_SCALE = 1.0

# Height against a 1.6 diameter -- the same 0.4 ratio as before, at 60% the size.
# The ratio is the part that matters and should not drift: taller reads as a studded
# rubber mat, shorter as pebbled glass.
BUBBLE_H = 0.64
# DERIVED, not chosen. The pocket apexes are the walkable plane and the film hangs
# below them, so for the film's underside to land exactly on the slab's top face it has
# to be whatever is left of the tile layer once a pocket has taken its share. Picked by
# hand it either floats the film above the slab or buries it inside.
FILM_THICK = TILE_LAYER - BUBBLE_H

# Pocket spacing and radius, in STUDS AND FIXED -- not a division of the slab.
#
# This is what lets a tapered run work. Divide the slab into N cells and a 16-wide piece
# and a 12-wide piece get different pocket sizes and, worse, different lattice PHASE, so
# the pattern jumps at every join. Anchored at the mesh origin on a fixed pitch, every
# sheet puts a pocket at x = 0, +/-PITCH, ... whatever its width -- and since slabs are
# centred on the path, adjacent pieces line up and the joins disappear.
#
# It is also simply true: a bubble wrap machine has one bubble size, and it does not
# change because you cut a narrower strip off the roll.
# 2.0 EXACTLY, because it has to divide the taper piece length. C4's tapered run is cut
# into 4-stud pieces, each its own slab with its own sheet centred on itself. The pieces
# sit 4 apart, so unless the pitch divides 4 the rows land at different offsets in chunk
# space and the lattice visibly jumps at every join. At the old 1.3 it did. Every slab
# depth in the game (4, 8, 12) is a multiple of 2.
PITCH = 2.0
# 0.8 against a 2.0 pitch leaves 0.4 studs of sealed film between neighbours, a fifth of
# the pitch. That ratio is what to hold if the size changes again: at a tighter one the
# pockets all but touch and run together into diagonal ridges, and the flat lattice has
# to stay wide enough to see, being the half of the read the pockets cannot carry.
BUBBLE_R = 0.8
EDGE_MARGIN = 0.12  # keep a whole pocket inside the slab rather than slicing one

# Spread in how full each pocket is, as a fraction of BUBBLE_H.
#
# THE PITCH STAYS EXACT AND THE FULLNESS DOES NOT. Bubble wrap is sealed by a machine on
# a precise lattice, so jittering the spacing would be wrong and would look it -- that
# grid is the one grid in this project that is real. But no machine inflates two pockets
# identically, and a sheet where all of them match to the millimetre is the tell that
# something was generated. This is the only variation the material should carry.
FULLNESS_SPREAD = 0.1

# A pocket is built as a POLAR CAP, not sampled out of a heightfield.
#
# The heightfield version is the obvious one and it does not work. A pocket is 1.0 studs
# across, so on an axis-aligned grid fine enough to stay affordable it spans about six
# cells -- and a circle six cells wide on a square lattice is an OCTAGON. Every pocket
# came out visibly eight-sided from above. Resolving it properly needs roughly 0.08
# studs, which quadruples the triangle count of the whole sheet to pay for detail in the
# 45% of the area the pockets actually occupy.
#
# Radially it is exact and cheap: the rim is a real circle at any segment count, and the
# rings can be concentrated where the profile actually curves.
SEGMENTS = 14
RINGS = 5

# A FLAT COLLAR ringing every pocket, at film level, reaching this far past the rim.
#
# This is what makes a pocket blend into the film instead of meeting it at a visible
# crease, and the cause was shading rather than shape. The profile is already tangential
# at the rim, but a cap's rim vertices belong to cap faces ONLY -- so their normals
# average the steep outer band and come out tilted, while the film a millimetre away
# shades flat. Two different normals at the same place is a hard line, and no amount of
# reprofiling removes it.
#
# The collar gives those rim vertices a second, flat neighbour to average with, and its
# own outer edge is coplanar with the film and shades identically. The seam disappears.
#
# 1.2 rather than more: neighbouring rims are 0.4 studs apart at this pitch, so a collar
# reaching further than 0.2 would run into the next pocket's.
COLLAR = 1.2

# How many stacked sheets of pockets. 1 for ordinary bubble wrap; the giant variant
# overrides it. See GIANT for why a second layer exists at all.
LAYERS = 1
LAYER_DROP = 1.05


# ---------------------------------------------------------------- shaped variants

# GIANT BUBBLE WRAP: the same sheet at twice the pitch and twice the radius.
#
# Nothing in the runtime needs telling. DeformationRenderer finds a platform's bones by
# walking the mesh and matching them to tiles BY WORLD POSITION, so a sheet with a
# different lattice needs no code at all -- which is the payoff for having refused to
# hardcode the pitch anywhere on the Luau side.
#
# The pocket stays the same SHAPE, not the same proportions. A 3.2-stud pocket standing
# as tall as a 1.6-stud one would be a hemisphere the size of a football, and real wrap
# does not do that: the big-pocket rolls are relatively flatter, because the film is
# stretched over a wider die by the same machine. 0.74 against 3.2 across is the ratio
# the reference photographs show, and it also has to fit -- TILE_LAYER is 0.9 studs from
# the slab's top face to the walkable plane, and the film needs what is left.
#
# The one thing that does not scale is the COLLAR, which is a multiple of the radius and
# so scales itself. At this pitch neighbouring rims are 0.8 studs apart, twice the gap
# of the standard sheet, so 1.2 has more room than before rather than less.
GIANT = {
    "PITCH": 4.0,
    "BUBBLE_R": 1.5,
    "BUBBLE_H": 0.68,
    "FILM_THICK": TILE_LAYER - 0.68,
    # NO POCKETS ON THE SIDES OR THE UNDERSIDE, which the standard sheet has and needs.
    #
    # The wrap stands WRAP_OUT + BUBBLE_H proud of the slab on every face. On the
    # standard sheet that is a stud and it reads as film pulled round a block. At giant
    # size the same rule hangs 3-stud spheres off all four walls and the bottom of a slab
    # that is only 4 studs thick, so the platform stopped looking like a wrapped block
    # and started looking like a raft of balloons wider than the thing holding you up --
    # which is also a lie about where the floor is, since collision is the tile grid.
    #
    # A smooth band is the honest read: film pulled taut round the edge, pockets only
    # where you can actually see and stand on them. It also leaves the underside clear,
    # which the two-layer version needs, because what should show through from below is
    # the SECOND layer of bubbles and not a third set wrapped round the outside.
    "SIDE_SCALE": 0.0,
    # TWO LAYERS OF POCKETS, WHICH IS WHAT MAKES THIS A RISK PLATFORM.
    #
    # Standard bubble wrap pops and goes flat: nothing about it can hurt you, so it has
    # been a "risk" chunk by category and a completely harmless one in play. Stacking a
    # second sheet under the first gives the material a real failure mode -- burst
    # everything under your feet twice and the floor stops being floor.
    #
    # The lower layer is offset half a pitch on BOTH axes so its pockets sit in the
    # diamond gaps between the upper ones. That is what makes the second layer visible
    # through the first before you have touched it: staggered, you are looking down into
    # a second row of domes, and the platform reads as two sheets deep from the moment
    # you arrive. Stacked directly underneath it would be completely hidden, and the
    # collapse would arrive with no warning anywhere on screen.
    "LAYERS": 2,
    # Below the upper film by more than a pocket is tall, so the two rows never intersect.
    "LAYER_DROP": 1.05,
    # More of both: at twice the radius the same 14 segments put a visible flat every
    # 0.7 studs round a rim that is now 10 studs of circumference. 28 brings the chord
    # back to 0.36 studs, close to the standard sheet's 0.36 -- the number that matters
    # is the CHORD, not the segment count, and it is the rim that carries the read.
    # 26 x 5, not 28 x 6, and the trade is deliberate. 28 x 6 came to 23,404 triangles,
    # over Roblox's 21,000 per MeshPart -- so something had to go, and a RING buys less
    # than a SEGMENT here. Segments set the rim silhouette, which is the shape you
    # actually read on a pocket; rings only smooth a profile that is already gentle.
    "SEGMENTS": 26,
    "RINGS": 5,
}

FORMS = {"giant": GIANT}


@contextlib.contextmanager
def variant(**overrides):
    """Temporarily rebind module globals.

    `lattice`, `build_surface` and the validator all read these as globals, so a variant
    that passed parameters instead would leave the VALIDATOR checking the standard
    sheet's expectations against a different mesh -- the kind of check that passes
    without ever having looked at the thing it was given.
    """
    g = globals()
    previous = {k: g[k] for k in overrides}
    g.update(overrides)
    try:
        yield
    finally:
        g.update(previous)


def dome(t):
    """Pocket profile against normalised distance from its centre, 0 at the rim.

    Two properties, and both are needed; picking either one alone failed a render.

    FULL. An inflated pocket is still about 0.9 of its height at half radius and then
    turns down hard over the last fifth. The first version, (1 - t^2)^1.35, was only
    0.68 there, so the pockets came out pointed and the sheet rendered as a range of
    little grey tents.

    TANGENTIAL AT THE RIM. The second version, (1 - t^3)^0.65, was full enough but met
    the film at an angle, and on a smooth-shaded sheet that put a dark wedge at the base
    of every pocket where the normals interpolated across the join.

    The inner exponent buys the fullness, the outer one (above 1) forces the slope to
    vanish at t = 1. Solved together rather than tuned: 0.9 at half radius fixes the
    pair. It gives 0.90 at t = 0.5 and reaches the film flat.
    """
    return (1.0 - t ** 3.6) ** 1.2


def lattice(size_x, size_z):
    """Pocket centres, on a fixed pitch, straddling the origin.

    HALF-PITCH OFFSET, so the origin falls in the middle of a seal rather than on a
    pocket. Anchoring a pocket AT the origin wastes most of a pitch at both edges once
    the pockets are this big: on a 4-deep taper piece it fitted a single lonely row down
    the middle with 1.2 studs of bare film either side. Straddling fits two, with 0.2 to
    spare.

    Still a fixed rule rather than one chosen per slab, which is what keeps the taper
    joins invisible: every sheet puts pockets at the same absolute offsets whatever its
    own width, so neighbouring pieces continue each other's lattice instead of each
    restarting it from its own centre.
    """
    reach = BUBBLE_R + EDGE_MARGIN
    max_i = int((size_x / 2.0 - reach) / PITCH - 0.5)
    max_j = int((size_z / 2.0 - reach) / PITCH - 0.5)
    return [
        ((i + 0.5) * PITCH, (j + 0.5) * PITCH)
        for j in range(-max_j - 1, max_j + 1)
        for i in range(-max_i - 1, max_i + 1)
    ]


def outline(half_x, half_z, corner, per_corner):
    """The film's plan as a counter-clockwise rounded rectangle."""
    corner = max(0.0, min(corner, half_x * 0.9, half_z * 0.9))
    ix, iz = half_x - corner, half_z - corner
    poly = []
    for cx, cz, start in ((ix, -iz, -math.pi / 2.0), (ix, iz, 0.0),
                          (-ix, iz, math.pi / 2.0), (-ix, -iz, math.pi)):
        for k in range(per_corner + 1):
            angle = start + (math.pi / 2.0) * k / per_corner
            poly.append((cx + math.cos(angle) * corner, cz + math.sin(angle) * corner))
    return poly


def perimeter_points(half_x, half_z, corner, spacing):
    """Points evenly spaced BY ARC LENGTH around the plan, as (x, y, out_x, out_y).

    Walls used to be four separate flat runs, each with the corner arcs cut off its
    ends, and that left 2.56 studs of bare film at both ends of every long wall -- most
    of a pocket and a half, in the most visible place there is. Walking the perimeter
    instead puts pockets round the corners as well, each taking its outward direction
    from where it actually sits, so the band never breaks.

    Spacing is nudged to divide the perimeter exactly. A loop is closed, so holding the
    pitch at precisely 2.0 leaves one odd gap where the walk meets itself, and an
    irregular gap reads far worse than every pocket being 2% out of step.
    """
    corner = max(0.0, min(corner, half_x * 0.9, half_z * 0.9))
    ix, iz = half_x - corner, half_z - corner
    quarter = math.pi / 2.0
    segments = [
        ("line", (-ix, -half_z), (ix, -half_z), (0.0, -1.0)),
        ("arc", (ix, -iz), -quarter, 0.0),
        ("line", (half_x, -iz), (half_x, iz), (1.0, 0.0)),
        ("arc", (ix, iz), 0.0, quarter),
        ("line", (ix, half_z), (-ix, half_z), (0.0, 1.0)),
        ("arc", (-ix, iz), quarter, math.pi),
        ("line", (-half_x, iz), (-half_x, -iz), (-1.0, 0.0)),
        ("arc", (-ix, -iz), math.pi, 3 * quarter),
    ]
    lengths = [
        math.dist(s[1], s[2]) if s[0] == "line" else abs(s[3] - s[2]) * corner
        for s in segments
    ]
    total = sum(lengths)
    count = max(4, int(round(total / spacing)))
    step = total / count

    points = []
    for i in range(count):
        d = i * step
        for seg, length in zip(segments, lengths):
            if d <= length:
                if seg[0] == "line":
                    t = d / length if length > 1e-9 else 0.0
                    points.append((
                        seg[1][0] + (seg[2][0] - seg[1][0]) * t,
                        seg[1][1] + (seg[2][1] - seg[1][1]) * t,
                        seg[3][0], seg[3][1],
                    ))
                else:
                    angle = seg[2] + (d / corner if corner > 1e-9 else 0.0)
                    points.append((
                        seg[1][0] + math.cos(angle) * corner,
                        seg[1][1] + math.sin(angle) * corner,
                        math.cos(angle), math.sin(angle),
                    ))
                break
            d -= length
    return points


def rows_on(span, pitch, margin):
    """Lattice positions along one axis, straddling zero -- the 1D half of `lattice`."""
    reach = int(span / 2.0 / pitch - margin / pitch - 0.5)
    return [(j + 0.5) * pitch for j in range(-reach - 1, reach + 1)]


def inside_plan(x, y, half_x, half_z, corner, margin):
    """True when a disc of `margin` at (x, y) is wholly inside the rounded plan.

    Used to drop pockets that the rounded corners have cut into. A pocket sliced by the
    corner would hang half off the film with its rim in mid-air, which is worse than the
    slightly wider gap left by leaving it out.
    """
    qx = abs(x) - (half_x - corner)
    qy = abs(y) - (half_z - corner)
    if qx <= 0.0 or qy <= 0.0:
        return abs(x) + margin <= half_x and abs(y) + margin <= half_z
    return math.hypot(qx, qy) + margin <= corner


def fullness(cx, cy):
    """How inflated the pocket at (cx, cy) is, as a multiplier on BUBBLE_H.

    Keyed to the pocket's own LATTICE POSITION rather than to its index in the list, so
    that two sheets of different widths agree about the pocket at a given place. Index
    would restart at every slab and put the same first-pocket fullness at the left edge
    of all six sheets, which is a repeat at exactly the seam the fixed pitch exists to
    hide. Deterministic for the same reason -- a regenerated mesh must match the one
    already imported.
    """
    key = int(round(cx * 16.0)) * 73856093 ^ int(round(cy * 16.0)) * 19349663
    unit = ((key * 1103515245 + 12345) % 2147483648) / 2147483648.0
    return 1.0 + (unit - 0.5) * 2.0 * FULLNESS_SPREAD


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.armatures):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def lower_centres(size_x, size_z):
    """The second layer's pocket centres: EXACTLY the first layer's, one drop below.

    They were staggered half a pitch, on the reasoning that offset pockets peek through
    the gaps above them and advertise the second layer. In a bounded plan that argument
    loses to arithmetic: a staggered lattice does not fit the same count, so a 4 x 4 top
    layer got a 3 x 3 bottom one, and the platform read as a small odd square floating
    inside a bigger one -- the mismatch was the first thing anybody noticed about it.

    Aligned is both tidier and a better description of the thing. The material is
    translucent, so a dome sitting directly under another dome reads as DEPTH: two
    bubbles thick, which is exactly the fact the player needs. It also makes the state
    legible mid-collapse -- pop the top pocket and the one still inflated underneath is
    revealed in the same place, rather than somewhere off to the side.
    """
    if LAYERS < 2:
        return []
    return list(lattice(size_x, size_z))


def build_surface(size_x, size_z, centres, name):
    """A film box wrapping the whole slab, with a polar cap for every pocket on it.

    SIX FACES, not one. The sheet used to be a mat lying on the platform's top, so from
    any angle but straight down the platform was a bare slab with a bubbled lid. It is
    a WRAP: the film encloses the block and the pockets stand off all six sides.

    The caps are OPEN surfaces resting on the film rather than holes cut through it.
    Cutting a hundred circular holes in six rectangles needs a constrained triangulation
    and buys nothing: a cap's rim sits exactly on its face and meets it tangentially, so
    the two read as one surface. They share only a curve, never an area, so there is
    nothing for the depth buffer to fight over.

    ONLY THE TOP POCKETS ARE RIGGED. You cannot step on a wall or on the underside, so
    those pockets can never burst and a bone on them would be a bone that never moves.
    Leaving them off keeps the rig to what actually animates and avoids having to encode
    a per-face collapse direction, since every remaining bone now collapses along -Z.
    """
    hx, hz = size_x / 2.0 + WRAP_OUT, size_z / 2.0 + WRAP_OUT
    z_slab_top = -FILM_THICK
    z_bot = z_slab_top - _slab_depth() - FILM_THICK

    verts, faces = [], []
    # index -> (pocket centre, share of that pocket's bone). TOP pockets only.
    owner = {}

    # --- the film, one closed box around the slab ---
    # Wound by hand rather than left to recalc_face_normals: the caps are open surfaces,
    # and recalc infers inside from outside using connectivity, so on a mesh that is not
    # a closed solid it is free to decide the whole thing faces the wrong way.
    plan = outline(hx, hz, CORNER, CORNER_STEPS)
    n_plan = len(plan)
    top = len(verts)
    for x, y in plan:
        verts.append((x, y, 0.0))
    bottom = len(verts)
    for x, y in plan:
        verts.append((x, y, z_bot))
    faces.append(tuple(range(top, top + n_plan)))
    faces.append(tuple(reversed(range(bottom, bottom + n_plan))))
    for k in range(n_plan):
        nk = (k + 1) % n_plan
        faces.append((top + k, bottom + k, bottom + nk, top + nk))

    # --- the second sheet's film, a plane inside the box ---
    #
    # THE LOWER POCKETS NEED SOMETHING TO REST ON. A cap here is an open surface laid on
    # the film, not a hole cut through it, so the first version's lower caps were nine
    # saucers suspended in the middle of an empty box attached to nothing -- and through
    # translucent film they read as angular junk floating inside the platform rather than
    # as a second sheet. The fix is not the caps; it is that the sheet they belong to was
    # never built.
    if LAYERS >= 2:
        lower_film = len(verts)
        for x, y in plan:
            verts.append((x, y, -LAYER_DROP))
        faces.append(tuple(range(lower_film, lower_film + n_plan)))
    film_faces = len(faces)

    # (first face, last face, intended outward normal) per cap, so the winding check can
    # be exact. Comparing every pocket face against +Z was right only while they all sat
    # on the lid; a wrap has pockets pointing five other ways.
    cap_spans = []

    def add_cap(origin, u_axis, normal, height, full, key):
        """One pocket, on any face, standing off it along `normal`.

        Generalised from the top-only version so the walls and the underside can reuse
        it: a cap is a centre, an in-plane axis and an outward direction, and nothing
        about it cares which face of the block it happens to be on.

        THE SECOND AXIS IS DERIVED, not passed. A cap's rings are wound in order of
        increasing angle from u toward v, so the winding comes out correct only when
        (u, v, normal) is right-handed. Handing both axes in, three of the six faces
        were built left-handed -- the +Y wall, the -X wall and the underside -- and
        every one of their pockets was inside out, which Roblox culls and Blender
        renders perfectly happily. Taking v as normal x u makes that unrepresentable.
        """
        v_axis = (
            normal[1] * u_axis[2] - normal[2] * u_axis[1],
            normal[2] * u_axis[0] - normal[0] * u_axis[2],
            normal[0] * u_axis[1] - normal[1] * u_axis[0],
        )

        def point(du, dv, dn):
            return (
                origin[0] + u_axis[0] * du + v_axis[0] * dv + normal[0] * dn,
                origin[1] + u_axis[1] * du + v_axis[1] * dv + normal[1] * dn,
                origin[2] + u_axis[2] * du + v_axis[2] * dv + normal[2] * dn,
            )

        first_face = len(faces)
        apex = len(verts)
        verts.append(point(0.0, 0.0, height * full))
        if key is not None:
            owner[apex] = (key, 1.0)

        rings = []
        for r in range(1, RINGS + 2):
            if r > RINGS:
                # The collar: flat, at film level, just past the rim.
                t, radius, stand = 1.0, BUBBLE_R * COLLAR, 0.0
            else:
                # Rings BUNCHED TOWARD THE RIM, since that is where the profile turns.
                # Spaced evenly they put a single chord across the outer band, which
                # drops 59% of the height over the last quarter of the radius and reads
                # as a facet however smoothly it is shaded.
                t = (r / RINGS) ** 0.72
                radius = BUBBLE_R * t
                stand = height * full * dome(t)
            ring = []
            for s in range(SEGMENTS):
                angle = math.tau * s / SEGMENTS
                index = len(verts)
                verts.append(point(math.cos(angle) * radius, math.sin(angle) * radius, stand))
                # The share IS the normalised profile height, so driving the bone in by
                # BUBBLE_H lands the apex exactly on the film and does not move the rim
                # at all. Exact here, where a heightfield could only approximate it.
                if key is not None:
                    # The collar is film, not pocket: weight 0, so it stays put while
                    # the dome inside it collapses. Weighting it with the rim would
                    # drag a ring of surrounding film down with every pop.
                    owner[index] = (key, 0.0 if r > RINGS else dome(t))
                ring.append(index)
            rings.append(ring)

        for s in range(SEGMENTS):
            ns = (s + 1) % SEGMENTS
            faces.append((apex, rings[0][s], rings[0][ns]))
            for r in range(len(rings) - 1):
                faces.append((rings[r + 1][s], rings[r + 1][ns],
                              rings[r][ns], rings[r][s]))
        cap_spans.append((first_face, len(faces), normal))

    # A pocket needs room for its COLLAR too, not just its rim, or the flat ring that
    # blends it into the film runs off the edge of the film.
    reach = BUBBLE_R * COLLAR

    # --- top pockets: the rigged ones ---
    for cx, cy in centres:
        if inside_plan(cx, cy, hx, hz, CORNER, reach):
            add_cap((cx, cy, 0.0), (1, 0, 0), (0, 0, 1),
                    BUBBLE_H, fullness(cx, cy), (cx, cy, 1))

    # The lower sheet, staggered half a pitch so it shows through the gaps above it.
    for cx, cy in lower_centres(size_x, size_z):
        if inside_plan(cx, cy, hx, hz, CORNER, reach):
            add_cap((cx, cy, -LAYER_DROP), (1, 0, 0), (0, 0, 1),
                    BUBBLE_H, fullness(cx, cy), (cx, cy, 2))

    # --- the band around the sides: decoration, unrigged ---
    #
    # ONE CONTINUOUS BAND, walked by arc length, rather than four flat runs. Each pocket
    # takes its outward direction from the point it sits on, so the band carries straight
    # round the corners instead of stopping short of them.
    wall_h = -z_bot
    side = BUBBLE_H * SIDE_SCALE
    # SIDE_SCALE 0 means a SMOOTH BAND, not flat pockets. Zero-height caps would be discs
    # of triangles lying in the film plane, z-fighting with it and costing a few thousand
    # triangles to be invisible. Skipping them outright is what "no pockets on the sides"
    # should mean.
    for px, py, nx, ny in (perimeter_points(hx, hz, CORNER, PITCH) if side > 1e-6 else ()):
        normal = (nx, ny, 0.0)
        # Tangent, so (u, v=normal x u, normal) comes out right-handed with v straight up.
        u_axis = (-ny, nx, 0.0)
        for v in rows_on(wall_h, PITCH, BUBBLE_R + EDGE_MARGIN):
            add_cap((px, py, z_bot / 2.0 + v), u_axis, normal,
                    side, fullness(px + py, v), None)

    for cx, cy in lattice(hx * 2.0, hz * 2.0):
        if inside_plan(cx, cy, hx, hz, CORNER, reach):
            add_cap((cx, cy, z_bot), (1, 0, 0), (0, 0, -1),
                    side, fullness(cx, cy), None)

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    # SMOOTH SHADE THE POCKETS, FLAT SHADE THE FILM. Four rings is not many, and flat
    # shaded that reads as a faceted cone. The profile meets the film tangentially (see
    # `dome`), so the rim's normal is already straight up and matches the film it lands
    # on -- smoothing across the join is correct rather than a cheat. The film's own
    # faces stay flat because it genuinely turns a right angle at its edges.
    for poly in mesh.polygons[film_faces:]:
        poly.use_smooth = True

    static = set(range(top, bottom + 4))
    return obj, owner, static, cap_spans


def build_armature(layers, rig_name):
    arm_data = bpy.data.armatures.new(rig_name)
    arm_obj = bpy.data.objects.new(rig_name, arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    root = arm_data.edit_bones.new("Root")
    root.head = (0.0, 0.0, 0.0)
    root.tail = (0.0, 0.0, 1.0)

    names = {}
    # LAYER 2 IS NAMED "Bubble2_", AND THE PREFIX IS THE WHOLE INTERFACE.
    #
    # DeformationRenderer collects a sheet's pockets with a `^Bubble_` match, so bones
    # named Bubble2_ are invisible to every code path that already exists -- the lower
    # layer simply does not respond until the client is told the cell has moved on to it.
    # There is no version flag on the mesh and nothing to keep in step: a client that has
    # never heard of layers meets a two-layer sheet and pops the top one forever, which is
    # the old behaviour rather than an error.
    for layer, points in enumerate(layers, start=1):
        prefix = "Bubble_" if layer == 1 else f"Bubble{layer}_"
        base = 0.0 if layer == 1 else -LAYER_DROP
        for index, (cx, cy) in enumerate(points, start=1):
            name = prefix + str(index)
            bone = arm_data.edit_bones.new(name)
            # Head at THIS pocket's own apex, pointing up: the renderer drives these in
            # plain world axes, so every bone has to share the mesh's own orientation.
            # Fullness matters here only for tidiness -- Transform is relative to the
            # rest pose, so the collapse travels the same distance wherever the head sits.
            top = base + BUBBLE_H * fullness(cx, cy)
            bone.head = (cx, cy, top)
            bone.tail = (cx, cy, top + 0.4)
            bone.parent = root
            bone.use_connect = False
            names[(cx, cy, layer)] = name

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj, names


def assign_weights(obj, arm_obj, owner, static_indices, names):
    """ONE bone per vertex, weighted by height up its own dome.

    Deliberately NOT the blended weighting honey and slime use. There the point is that a
    dent melts into the surface around it, so several bones share every vertex. Here the
    opposite is required: a pocket must collapse without disturbing the film it is
    sealed to, or popping one bubble visibly drags its neighbours down and the sheet
    behaves like rubber instead of like plastic film with air pockets in it.
    """
    groups = {name: obj.vertex_groups.new(name=name) for name in names.values()}
    root_group = obj.vertex_groups.new(name="Root")

    for index in range(len(obj.data.vertices)):
        entry = owner.get(index)
        if index in static_indices or entry is None:
            root_group.add([index], 1.0, "REPLACE")
            continue
        centre, share = entry
        share = min(1.0, max(0.0, share))
        if share > 0.0:
            groups[names[centre]].add([index], share, "REPLACE")
        if share < 1.0:
            root_group.add([index], 1.0 - share, "REPLACE")

    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = arm_obj
    obj.parent = arm_obj


def validate_mesh(obj, cap_spans, bubble_count):
    """NO manifold or open-edge test, unlike the honey/slime/butter rigs.

    Those are closed solids and an open edge means a hole. This sheet is a closed film
    box with open caps resting on it, so every cap rim is legitimately a boundary --
    checking for open edges here would fail every mesh the generator can produce.

    What still matters is winding, which is the failure that actually ships: Roblox culls
    back faces, so a pocket wound inside out is simply invisible in game while looking
    perfect in Blender.
    """
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    problems = []
    degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-7)
    if degenerate:
        problems.append(f"{degenerate} zero-area faces")
    if bm.faces[0].normal.z < 0.9:
        problems.append("the film's top face does not point UP")
    # Each cap against ITS OWN outward direction. Testing every pocket face for +Z was
    # right only while they all sat on the lid, and on a wrap it condemned all 1344
    # underside faces for pointing down, which is what they are supposed to do.
    inverted = 0
    for first, last, normal in cap_spans:
        for face in bm.faces[first:last]:
            if face.normal.dot(mathutils.Vector(normal)) <= 0.0:
                inverted += 1
    if inverted:
        problems.append(f"{inverted} pocket faces point INWARD and Roblox will cull them")
    if bubble_count == 0:
        problems.append("no pockets fit on this slab at all")
    # The whole sheet is now about five studs deep, because it wraps the slab -- so the
    # thing to check is no longer the total. It is that the TOP film's underside lands
    # on the slab's top face: any lower and the film cuts down through the slab it is
    # supposed to be lying on, and the pockets sink with it.
    # The rounded plan must still ENCLOSE the slab's square corners. A rounded rectangle
    # offset by w from a square one contains that square's corner only while the radius
    # is at most w / (sqrt2 - 1); past it each corner grows a nub of bare slab poking
    # out through the wrap, which is visible from exactly four angles and no others.
    limit = WRAP_OUT / (math.sqrt(2.0) - 1.0)
    if CORNER > limit + 1e-9:
        problems.append(
            f"CORNER {CORNER} exceeds {limit:.3f} for WRAP_OUT {WRAP_OUT}, "
            "so the slab's corners cut back out through the film"
        )
    if FILM_THICK > TILE_LAYER - BUBBLE_H + 1e-9:
        problems.append(
            f"top film is {FILM_THICK:.2f} against {TILE_LAYER - BUBBLE_H:.2f} of room, "
            "so it sinks through the slab"
        )
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
    # 5.0 studs per tile, sized for film wrinkles. The scale is in studs rather than repeats so
    # every platform size shows the same physical detail instead of stretching it to fit.
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
        # EDGE, not FACE: the per-polygon smooth flags set in build_surface only survive
        # the FBX round trip as edge smoothing data. Exported as FACE the sheet arrives
        # in Roblox fully flat shaded again, faceted pockets and all.
        mesh_smooth_type="EDGE",
    )
    print(f"  exported {os.path.basename(path)}")


def mesh_name(size_x, size_z, form=None):
    stem = "Sheet" if form is None else form.capitalize()
    return f"BubbleWrap_{stem}_{size_x:.0f}x{size_z:.0f}"


def build_variant(size_x, size_z, form=None):
    name = mesh_name(size_x, size_z, form)
    centres = lattice(size_x, size_z)
    mesh_obj, owner, static, cap_spans = build_surface(size_x, size_z, centres, name)
    lower = lower_centres(size_x, size_z)
    arm_obj, names = build_armature([centres, lower], name + "_Rig")
    assign_weights(mesh_obj, arm_obj, owner, static, names)
    ok = validate_mesh(mesh_obj, cap_spans, len(centres) + len(lower))

    tris = sum(len(p.vertices) - 2 for p in mesh_obj.data.polygons)
    verts = mesh_obj.data.vertices
    zs = [v.co.z for v in verts]
    low, high = min(zs), max(zs)
    # The pocket APEXES are the walkable plane: you stand on the bubbles, not on the
    # film between them. surfaceOffset is measured from the bbox centre up to that.
    walkable = BUBBLE_H
    # How much wider the wrapped mesh is than its slab, MEASURED rather than derived
    # from the constants. ChunkBuilder asserts the imported size, and a wrap is
    # legitimately bigger than the thing it wraps -- so it has to be told by how much,
    # or the assertion has to be loosened into something that no longer catches a
    # genuinely mis-imported mesh.
    pad = max(v.co.x for v in verts) * 2.0 - size_x
    total = len(centres) + len(lower) + len(mesh_obj.vertex_groups) - 1
    layered = "" if not lower else f" (+{len(lower)} lower)"
    print(f"  {name}: {len(centres)}{layered} rigged pockets, {tris} tris, "
          f"pad {pad:.2f}, {'valid' if ok else 'INVALID'}")
    shape = "" if form is None else f', form = "{form}"'
    entry = (f"\t\t{{ sizeX = {size_x:.0f}, sizeZ = {size_z:.0f}, "
             f"meshHeight = {high - low:.2f}, surfaceOffset = {walkable - (low + high) / 2.0:.2f}, "
             f"meshPad = {pad:.2f}, "
             f'mesh = "{name}"{shape} }},')
    return mesh_obj, arm_obj, entry, ok


def slab_sizes():
    """Every distinct bubble-wrap slab, READ FROM ChunkBuilder rather than typed here.

    A rig is matched to a slab by exact size, and a slab with no rig falls back to
    per-tile meshes in complete silence. Hardcoding the list means a chunk edit that
    resizes a bubble wrap slab breaks the material with no error anywhere.
    """
    import chunk_layout

    layouts, _, _ = chunk_layout.layout_all()
    sizes = set()
    for boxes in layouts.values():
        for box in boxes:
            if box.material == "BubbleWrap" and box.form is None:
                sizes.add((round(box.sx, 2), round(box.sz, 2)))
    return sorted(sizes)


def form_slabs():
    """Shaped bubble wrap slabs, as (form, size_x, size_z), read from the same source
    for the same reason: a form named in ChunkBuilder that nobody generated should show
    up as a missing mesh at BUILD time, not as a platform that quietly came out plain."""
    import chunk_layout

    layouts, _, _ = chunk_layout.layout_all()
    found = set()
    for boxes in layouts.values():
        for box in boxes:
            if box.material == "BubbleWrap" and box.form is not None:
                found.add((box.form, round(box.sx, 2), round(box.sz, 2)))
    return sorted(found)


def main():
    sizes = slab_sizes()
    print(f"  {len(sizes)} plain bubble wrap slab sizes, {len(form_slabs())} shaped\n")

    entries, all_ok = [], True
    for size_x, size_z in sizes:
        clear_scene()
        mesh_obj, arm_obj, entry, ok = build_variant(size_x, size_z)
        all_ok = all_ok and ok
        export_fbx(mesh_obj, arm_obj, mesh_name(size_x, size_z) + ".fbx")
        entries.append(entry)

    for form, size_x, size_z in form_slabs():
        recipe = FORMS.get(form)
        if recipe is None:
            print(f"  !! ChunkBuilder asks for bubble wrap form '{form}' and this")
            print("     generator has no recipe for it. Add one to FORMS.")
            all_ok = False
            continue
        clear_scene()
        with variant(**recipe):
            mesh_obj, arm_obj, entry, ok = build_variant(size_x, size_z, form)
            all_ok = all_ok and ok
            export_fbx(mesh_obj, arm_obj, mesh_name(size_x, size_z, form) + ".fbx")
        entries.append(entry)

    print("")
    print("  ChunkBuilder SKINNED_PLATFORMS entry:")
    print("\tBubbleWrap = {")
    for entry in entries:
        print(entry)
    print("\t},")
    print("")
    print(f"  BUBBLE_H = {BUBBLE_H}  (DeformationRenderer drives bones down by this to pop)")
    print("")
    print("Done." if all_ok else "!! a mesh failed validation -- DO NOT import.")


if __name__ == "__main__":
    main()
