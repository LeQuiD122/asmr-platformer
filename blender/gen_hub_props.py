"""Static props for the lobby: a planter, its soil, and a plant that is actually a plant.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_hub_props.py

The first version of the planter was built out of Roblox primitives -- a cylinder, a square
slab of "soil" that did not fit the circle, and five green spheres. That reads as a
placeholder because it is one: spheres are not leaves, and a square inside a circle is a
mistake at any size.

None of these deform, so none of them is skinned. They are exported as plain meshes with no
armature, which is also why they are in one file: a prop is a prop.

=== Why the leaf is built the way it is ===

A leaf is a strip that curves along TWO axes at once -- it arches away from the stem and it
folds along its own spine -- and it tapers to a point. Those three things together are what
separate a leaf from a flattened sphere. Each is one line below, applied to a subdivided
strip, and the result reads as foliage from any angle rather than only from above.
"""

import math
import os
import sys

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import uv_project

OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "meshes"))

# Studs. Roblox imports at 0.01 scale, so a value here is a stud in game.
PLANTER_R = 3.5
PLANTER_H = 3.0
SOIL_R = 2.95


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.objects):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def finish(bm, name):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build_planter():
    """A tapered bowl with a rolled rim, built as a CLOSED SOLID with real wall thickness.

    The first version was a single surface -- one wall swept up a profile with a disc capping
    the bottom. That renders as a bowl only from the inside: a single-sided wall has one
    normal, so with backface culling the outside of the pot was see-through while the inside
    looked solid, which is exactly how it came out in game.

    The fix is not to flip the normals. A one-sided wall is wrong whichever way it faces --
    turn it around and the problem simply moves indoors. A pot has thickness, so the profile
    now runs up the outside, across the rim, back down the inside, and closes over the base.
    That is a watertight solid: every face has material behind it and recalc_face_normals has
    an inside and an outside to tell apart.
    """
    bm = bmesh.new()
    segments = 28
    wall = 0.22

    # Up the outside. The rim flares back out, which is what makes the lip catch light and
    # stops the silhouette ending on a hard edge.
    outer = [(PLANTER_R * 0.62, 0.0), (PLANTER_R * 0.80, PLANTER_H * 0.30),
             (PLANTER_R * 0.94, PLANTER_H * 0.72), (PLANTER_R, PLANTER_H * 0.90),
             (PLANTER_R * 1.06, PLANTER_H)]
    # Back down the inside, narrower by the wall thickness, to a floor sitting above the base.
    inner = [(PLANTER_R * 1.06 - wall, PLANTER_H), (PLANTER_R * 0.94 - wall, PLANTER_H * 0.86),
             (PLANTER_R * 0.86 - wall, PLANTER_H * 0.60), (PLANTER_R * 0.66 - wall, wall * 1.6)]
    profile = outer + inner

    rings = []
    for radius, height in profile:
        ring = [bm.verts.new((math.cos(a) * radius, math.sin(a) * radius, height))
                for a in (i / segments * math.tau for i in range(segments))]
        rings.append(ring)

    for lower, upper in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            bm.faces.new((lower[i], lower[j], upper[j], upper[i]))

    # Two caps, so the solid is closed at both ends: the outside base and the inside floor.
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(bm, "Hub_Planter")


def build_soil():
    """A round disc, gently mounded, that fits the bowl it sits in.

    Mounded rather than flat because soil in a pot is never level -- it settles into a slight
    dome around whatever is planted in it, and a flat disc reads as a lid.
    """
    bm = bmesh.new()
    segments, rings = 28, 5
    centre = bm.verts.new((0.0, 0.0, 0.42))
    previous = None
    for r in range(1, rings + 1):
        fraction = r / rings
        radius = SOIL_R * fraction
        # Domed by a cosine so the middle is highest and the edge meets the bowl flat.
        height = 0.42 * math.cos(fraction * math.pi / 2) ** 1.4
        ring = [bm.verts.new((math.cos(a) * radius, math.sin(a) * radius, height))
                for a in (i / segments * math.tau for i in range(segments))]
        if previous is None:
            for i in range(segments):
                bm.faces.new((centre, ring[i], ring[(i + 1) % segments]))
        else:
            for i in range(segments):
                j = (i + 1) % segments
                bm.faces.new((previous[i], previous[j], ring[j], ring[i]))
        previous = ring
    # A skirt down to the rim, so there is no gap between soil and pot.
    assert previous is not None
    skirt = [bm.verts.new((v.co.x, v.co.y, -0.5)) for v in previous]
    for i in range(segments):
        j = (i + 1) % segments
        bm.faces.new((previous[j], previous[i], skirt[i], skirt[j]))
    # CLOSED UNDERNEATH. This was a dome with a skirt and no floor, so the soil was an open
    # surface: from any angle that saw under the rim you were looking at the inside of its
    # back wall, which renders as a hole. An open shell is the same bug the planter had.
    bm.faces.new(skirt)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(bm, "Hub_Soil")


def add_leaf(bm, angle, tilt, length, width, droop):
    """One leaf: a strip that arches, folds along its spine, and tapers to a point."""
    steps, half = 9, 3
    grid = []
    for s in range(steps + 1):
        along = s / steps
        # TAPER: widest a third of the way out, pinched to nothing at the tip. A leaf that is
        # widest at its base looks like a paddle.
        spread = width * math.sin(min(1.0, along * 1.35) * math.pi) ** 0.7
        # ARCH: rises then falls away, so the leaf leans out and nods over.
        rise = math.sin(along * math.pi * 0.75) * length * 0.42 - droop * along ** 2.4
        row = []
        for c in range(-half, half + 1):
            across = c / half
            # FOLD: the blade cups along its own spine, deepest in the middle of its length.
            cup = (across ** 2) * spread * 0.55 * math.sin(along * math.pi)
            point = (across * spread, along * length, rise - cup)
            # Rotate the whole leaf out from the centre by its own angle and tilt.
            x, y, z = point
            y2 = y * math.cos(tilt) - z * math.sin(tilt)
            z2 = y * math.sin(tilt) + z * math.cos(tilt)
            row.append(bm.verts.new((x * math.cos(angle) - y2 * math.sin(angle),
                                     x * math.sin(angle) + y2 * math.cos(angle),
                                     z2)))
        grid.append(row)

    # SINGLE LAYER, and deliberately so. A leaf seen from behind would vanish under backface
    # culling, and half the leaves on a rosette always are -- but the fix is not to add
    # mirrored faces here: bmesh refuses them outright, because two windings over the same
    # four verts are the same face to it. Roblox solves this at the other end with
    # MeshPart.DoubleSided, which HubService sets on this prop.
    for s in range(steps):
        for c in range(half * 2):
            bm.faces.new((grid[s][c], grid[s][c + 1], grid[s + 1][c + 1], grid[s + 1][c]))


def build_plant():
    """A rosette of leaves at three heights, which is what stops it reading as a bush.

    Real foliage has an outer skirt that lies almost flat, a middle tier that leans, and a
    few young leaves standing near-upright in the centre. Three tiers with different tilts
    and lengths gives that for the cost of a loop.
    """
    bm = bmesh.new()
    # TILT IS MEASURED FROM THE HORIZONTAL, and the first version had it backwards: the
    # rotation lifts the leaf, so a LARGE tilt is upright and a small one lies flat. Giving
    # the outer skirt 74 degrees stood every tier on end and the plant came out as a closed
    # bud -- an artichoke rather than a houseplant.
    #
    # The widths went up with it. At 0.95 across against 4.6 long these were blades of grass;
    # foliage needs to be roughly a third as wide as it is long before it reads as a leaf.
    tiers = [
        (7, math.radians(16), 4.6, 1.90, 1.6),   # outer skirt, nearly flat, longest, widest
        (6, math.radians(44), 3.6, 1.50, 0.9),   # middle, leaning out
        (4, math.radians(70), 2.5, 1.00, 0.25),  # inner, near upright and short
    ]
    for index, (count, tilt, length, width, droop) in enumerate(tiers):
        # Offset each tier so leaves sit in the gaps of the one below rather than on top of
        # it, which is the difference between a plant and a stack of plants.
        offset = (index * math.tau) / (count * 2.0)
        for i in range(count):
            add_leaf(bm, offset + i / count * math.tau, tilt, length, width, droop)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(bm, "Hub_Plant")


# =====================================================================================
# LIGHT FIXTURES
#
# The lamps were a neon ball on a column and a neon box under a beam. Both are the shape you
# reach for when the light matters and the fixture does not, and in a room this bare the
# fixture is most of what you actually see -- a glowing sphere reads as a placeholder for a
# light, not as a lamp.
#
# Both are built the same way: a metal FRAME mesh and a separate GLASS mesh that sits inside
# it. Two meshes rather than one because they want different materials -- the frame is dark
# and matte, the glass is neon and lit -- and a MeshPart carries exactly one.
# =====================================================================================

def _ring(bm, radius, height, segments):
    return [bm.verts.new((math.cos(a) * radius, math.sin(a) * radius, height))
            for a in (i / segments * math.tau + math.pi / segments
                      for i in range(segments))]


def _bridge(bm, lower, upper):
    for i in range(len(lower)):
        j = (i + 1) % len(lower)
        bm.faces.new((lower[i], lower[j], upper[j], upper[i]))


def build_lantern():
    """A hanging lantern: a finial, a flared cap, six corner ribs and a footed base.

    SIX SIDES rather than round. A hexagonal lantern reads as something built out of panels,
    which is what a lantern is; a cylinder reads as a tin can. The ribs are what sell it:
    they are the frame the glass panels sit in, and they catch light along their edges.
    """
    bm = bmesh.new()
    sides = 6
    body_r = 0.62

    # The cap: a wide brim tapering to a point, so the silhouette has a top rather than
    # just stopping.
    cap = [(0.10, 2.42), (0.30, 2.26), (0.94, 1.86), (0.86, 1.72), (body_r, 1.62)]
    rings = [_ring(bm, r, h, sides) for r, h in cap]
    for lower, upper in zip(rings, rings[1:]):
        _bridge(bm, upper, lower)
    peak = bm.verts.new((0.0, 0.0, 2.56))
    for i in range(sides):
        bm.faces.new((peak, rings[0][i], rings[0][(i + 1) % sides]))

    # The base: a mirrored, shallower version of the cap so the lantern sits on something.
    foot = [(body_r, 0.16), (0.86, 0.06), (0.70, -0.10), (0.24, -0.22)]
    frings = [_ring(bm, r, h, sides) for r, h in foot]
    for lower, upper in zip(frings, frings[1:]):
        _bridge(bm, lower, upper)
    bm.faces.new(list(reversed(frings[-1])))

    # SIX CORNER RIBS spanning cap to base. Square in section and set slightly proud of the
    # glass, so each reads as a separate piece of metal rather than a painted line.
    for i in range(sides):
        angle = i / sides * math.tau + math.pi / sides
        cx, cy = math.cos(angle) * body_r, math.sin(angle) * body_r
        nx, ny = math.cos(angle), math.sin(angle)
        tx, ty = -ny, nx
        half = 0.075
        corners = [(-half, -half), (half, -half), (half, half), (-half, half)]
        low = [bm.verts.new((cx + tx * u + nx * v, cy + ty * u + ny * v, 0.14))
               for u, v in corners]
        high = [bm.verts.new((cx + tx * u + nx * v, cy + ty * u + ny * v, 1.62))
                for u, v in corners]
        _bridge(bm, low, high)
        bm.faces.new(list(reversed(low)))
        bm.faces.new(high)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(bm, "Hub_Lantern")


def build_lantern_glass():
    """The lit volume inside the lantern frame: a closed six-sided drum."""
    bm = bmesh.new()
    sides = 6
    low = _ring(bm, 0.58, 0.18, sides)
    high = _ring(bm, 0.58, 1.58, sides)
    _bridge(bm, low, high)
    bm.faces.new(list(reversed(low)))
    bm.faces.new(high)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(bm, "Hub_LanternGlass")


def build_lamp_bowl():
    """A column-top uplighter: a shallow dish on a stem, throwing light at the canopy.

    Aimed UP on purpose. A downlight on a 22-stud column would put a hard pool on the floor
    and leave the top of the room black; bouncing it off the canopy is what makes a ceiling
    read as a ceiling, and keeps the light soft, which is the whole brief.
    """
    bm = bmesh.new()
    segments = 20
    profile = [(0.22, 0.0), (0.30, 0.34), (0.26, 0.62), (0.92, 1.18), (1.30, 1.64),
               (1.22, 1.60), (0.84, 1.10), (0.22, 0.60)]
    rings = [_ring(bm, r, h, segments) for r, h in profile]
    for lower, upper in zip(rings, rings[1:]):
        _bridge(bm, lower, upper)
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(bm, "Hub_LampBowl")


# =====================================================================================
# THE MODE LEVER
#
# A real handle rather than a stick with a ball on it. The lever is the one thing in this
# room a player is meant to grab, and it is rendered on the client so it can swing for one
# person only, which means its SHAPE is all that tells you it is grabbable.
# =====================================================================================

def build_lever_handle():
    """A knurled grip on a tapered shaft, topped with a faceted knob.

    The knurl is the point. Bands of shallow flats around the grip catch light at different
    angles as the lever swings, so the movement stays legible when the handle is small on
    screen. A smooth cylinder rotating about its own axis looks static.
    """
    bm = bmesh.new()
    segments = 14

    shaft = [(0.20, 0.0), (0.17, 0.55), (0.15, 1.10), (0.155, 1.45)]
    rings = [_ring(bm, r, h, segments) for r, h in shaft]

    # The grip: alternate rings pinched in, which is what makes the flats.
    for index, height in enumerate((1.55, 1.70, 1.85, 2.00, 2.15, 2.30)):
        rings.append(_ring(bm, 0.30 if index % 2 == 0 else 0.24, height, segments))

    # The knob: squat and faceted, wider than the grip so the hand stops there.
    for radius, height in ((0.30, 2.42), (0.44, 2.60), (0.46, 2.82), (0.36, 3.02), (0.14, 3.16)):
        rings.append(_ring(bm, radius, height, segments))

    for lower, upper in zip(rings, rings[1:]):
        _bridge(bm, lower, upper)
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(bm, "Hub_LeverHandle")


def build_lever_base():
    """The socket the handle swings in: a stepped plinth with a raised collar.

    The collar matters more than it looks. Without it the handle appears to pass through a
    flat plate; with it there is a visible hole for the shaft to enter, and the lever reads
    as hinged inside something rather than stuck onto it.
    """
    bm = bmesh.new()
    segments = 24
    profile = [(2.30, 0.0), (2.30, 0.34), (2.05, 0.46), (1.30, 0.62),
               (1.18, 0.94), (0.86, 1.06), (0.52, 0.88)]
    rings = [_ring(bm, r, h, segments) for r, h in profile]
    for lower, upper in zip(rings, rings[1:]):
        _bridge(bm, lower, upper)
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(bm, "Hub_LeverBase")


# =====================================================================================
# THE FOUNTAIN
#
# It was a cylinder, a flat disc, and a second flat disc in neon on top. From a standing
# player's eye level a flat disc is a line, so what you actually saw was a glowing white
# lozenge hovering over the pool with a wisp of particles above it: no tiers, no basin, no
# reason for the water to be where it is.
#
# A fountain is a stack of BOWLS. Water lands in one, fills it, and spills over the rim into
# the next -- and it is the rims, seen edge-on from across a room, that make the silhouette
# read as a fountain rather than as a post. This is two of them on a baluster stem.
# =====================================================================================

def _bowl_profile(radius, floor, rim, wall):
    """Outside up, across the rim, back down the inside, closing on a floor.

    Same closed-solid rule as the planter: a swept single surface has one normal, so it is
    see-through from whichever side the normal is not facing.
    """
    return [
        (radius * 0.30, floor - 0.10), (radius * 0.72, floor), (radius * 0.93, rim * 0.55),
        (radius, rim * 0.86), (radius * 1.05, rim), (radius * 1.05 - wall, rim),
        (radius * 0.88 - wall, rim * 0.60), (radius * 0.60 - wall, floor + 0.14),
        (radius * 0.22, floor + 0.14),
    ]


def build_fountain():
    """ONE CONTINUOUS PROFILE, revolved. No floating pieces, no seams.

    The first version stacked five separate solids -- foot, lower bowl, baluster, upper bowl,
    finial -- each closed at both ends and each simply positioned near the next. Where the
    stem met the lower bowl there was a visible step: the bowl's inner floor closed at radius
    0.22 and the stem began at 0.95, so the tube appeared to hover inside the basin with a
    gap all the way round it.

    Revolving a single profile makes that impossible to get wrong. The line runs up the
    outside of the foot, up the outside of the lower bowl, over its rim, back down its inside,
    across its floor, up the baluster, into the upper bowl, over that rim, down its inside and
    into the finial -- one unbroken silhouette, closed with a cap at each end.
    """
    bm = bmesh.new()
    segments = 26

    # (radius, height), bottom to top. Reading down the list traces the outline you would see
    # if you sliced the fountain in half.
    profile = [
        (0.00, 0.00),                                            # centre of the base
        (2.40, 0.00), (2.40, 0.34), (2.10, 0.50), (1.62, 0.66),  # stepped foot
        (1.70, 0.95), (2.60, 1.55), (3.15, 2.05),                # lower bowl, outside
        (3.30, 2.30), (3.10, 2.34),                              # its rim, rolled over
        (2.60, 2.05), (1.90, 1.62), (1.30, 1.46),                # lower bowl, inside
        (0.92, 1.50), (0.62, 2.05), (0.50, 2.60),                # the baluster, pinched
        (0.62, 3.05), (1.05, 3.45),                              # flaring into the upper stem
        (1.55, 3.95), (1.98, 4.45), (2.10, 4.70),                # upper bowl, outside
        (1.95, 4.76), (1.55, 4.50), (1.05, 4.20), (0.70, 4.12),  # its rim and inside
        (0.52, 4.30), (0.44, 4.85),                              # up into the finial
        (0.54, 5.10), (0.40, 5.42), (0.00, 5.62),                # the finial itself
    ]

    rings = [_ring(bm, r, h, segments) if r > 0.001 else None for r, h in profile]
    for index in range(len(rings) - 1):
        lower, upper = rings[index], rings[index + 1]
        if lower is None:
            # A zero-radius ring is a point: fan the next ring to it rather than bridging.
            apex = bm.verts.new((0.0, 0.0, profile[index][1]))
            for i in range(segments):
                bm.faces.new((apex, upper[(i + 1) % segments], upper[i]))
        elif upper is None:
            apex = bm.verts.new((0.0, 0.0, profile[index + 1][1]))
            for i in range(segments):
                bm.faces.new((apex, lower[i], lower[(i + 1) % segments]))
        else:
            _bridge(bm, lower, upper)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(bm, "Hub_Fountain")


# =====================================================================================
# THE FLOOR ARROW
#
# It was two rectangles set at an angle to each other, and that is what it looked like: two
# rectangles. A chevron is ONE shape with a concave notch in it -- the notch is the whole
# reason the eye reads it as pointing rather than as a pair of sticks -- and no arrangement of
# rectangles produces a notch, because a rectangle has no inside corner to give.
# =====================================================================================

def build_chevron():
    """One solid chevron, MITRED: every cut runs square to the arm it ends.

    The first version put both ends of each arm on a vertical line -- p1 at (-W, -D) and p2 at
    (-W, -D + band). That is a vertical slice through a bar running at 34 degrees, so it left a
    long square corner jutting past the end of the stroke on each side, and those corners are
    what read as "rectangles poking out".

    Cutting perpendicular to the arm instead gives the flat, chisel-ended chevron of an actual
    floor marking. The end points come from the arm's own normal rather than from a fixed x,
    which is also why they cannot drift out of agreement with the angle again.
    """
    width, depth, band, thick = 3.6, 2.4, 1.3, 0.16
    length = math.hypot(width, depth)

    # Unit vector along the right arm, and the normal that points back up the shape. The left
    # arm is its mirror, so one calculation serves both.
    ux, uy = width / length, -depth / length
    nx, ny = -uy, ux

    # Where the two offset inner edges meet on the centre line. Solved rather than guessed:
    # walk the right arm's inner edge from its start until x reaches zero.
    steps = -(nx * band) / ux
    inner_tip = ny * band + uy * steps

    outline = [
        (0.0, 0.0),                                             # outer tip
        (-width, -depth),                                       # outer left end
        (-width + -nx * band, -depth + ny * band),              # inner left end, square cut
        (0.0, inner_tip),                                       # INNER TIP, the notch
        (width + nx * band, -depth + ny * band),                # inner right end, square cut
        (width, -depth),                                        # outer right end
    ]

    bm = bmesh.new()
    low = [bm.verts.new((x, y, 0.0)) for x, y in outline]
    high = [bm.verts.new((x, y, thick)) for x, y in outline]

    # Two convex quads rather than one concave hexagon: an n-gon with an inside corner
    # triangulates unpredictably and can crease along the wrong diagonal.
    bm.faces.new((high[0], high[1], high[2], high[3]))
    bm.faces.new((high[0], high[3], high[4], high[5]))
    bm.faces.new((low[3], low[2], low[1], low[0]))
    bm.faces.new((low[5], low[4], low[3], low[0]))

    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        bm.faces.new((low[i], low[j], high[j], high[i]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(bm, "Hub_Chevron")


# =====================================================================================
# THE DOOR THAT SHOULD NOT BE THERE
#
# Backrooms Level 0 is the one worth borrowing from, and specifically because of its palette:
# mono-yellow wallpaper, damp beige carpet, and buzzing fluorescent ceiling panels. Set against
# a lobby built out of cool lilac and pale marble, that yellow is not a decoration -- it is a
# wrongness. Nothing else in the room is warm, so a doorway leaking that colour reads as a
# place at once, with no sign explaining it.
#
# It is a FRAME rather than a door: the point of Level 0 is that there is nothing stopping you
# going in, which is worse than a locked door. What is behind it gets built from parts in
# HubService, so the wallpaper and the flicker can be lit and animated.
#
# Deliberately battered. A clean frame reads as architecture; a frame with a chipped jamb and
# a sagging lintel reads as something that has been here a while and is not maintained.
# =====================================================================================

def build_doorframe():
    bm = bmesh.new()
    width, height, depth, jamb = 3.2, 6.4, 0.55, 0.42

    def slab(x0, x1, y0, y1, z0, z1):
        corners = [
            (x0, z0, y0), (x1, z0, y0), (x1, z1, y0), (x0, z1, y0),
            (x0, z0, y1), (x1, z0, y1), (x1, z1, y1), (x0, z1, y1),
        ]
        v = [bm.verts.new(c) for c in corners]
        for face in ((0, 1, 2, 3), (7, 6, 5, 4), (0, 4, 5, 1),
                     (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)):
            bm.faces.new([v[i] for i in face])

    half = width / 2
    # Two jambs. The right one is a hair narrower and a hair shorter, which is enough
    # asymmetry to stop the frame reading as a stamped-out rectangle.
    slab(-half - jamb, -half, 0.0, height, -depth / 2, depth / 2)
    slab(half, half + jamb * 0.92, 0.0, height - 0.12, -depth / 2, depth / 2)
    # The lintel, oversailing both jambs and sagging very slightly toward the middle.
    slab(-half - jamb, half + jamb, height - 0.46, height, -depth / 2 - 0.06, depth / 2 + 0.06)
    # A threshold strip, so the frame meets the floor in something rather than just stopping.
    slab(-half - jamb * 0.6, half + jamb * 0.6, 0.0, 0.1, -depth / 2 - 0.1, depth / 2 + 0.1)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(bm, "Hub_Doorframe")


def export(obj, uv_studs):
    uv_project.box_project(obj.data, uv_studs)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, obj.name + ".fbx")
    for other in bpy.data.objects:
        other.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        global_scale=0.01,
        add_leaf_bones=False,
        bake_anim=False,
        axis_forward="-Z",
        axis_up="Y",
        # MESH only. None of these deform, so an armature would be a rig for the renderer to
        # find by world position and drive by mistake.
        object_types={"MESH"},
        mesh_smooth_type="FACE",
    )
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("    %-14s %5d tris  ->  %s" % (obj.name, tris, os.path.basename(path)))


def main():
    props = (
        (build_planter, 3.0), (build_soil, 2.0), (build_plant, 2.5),
        (build_lantern, 1.2), (build_lantern_glass, 1.2), (build_lamp_bowl, 1.6),
        (build_lever_handle, 1.0), (build_lever_base, 1.6),
        (build_fountain, 2.4), (build_chevron, 1.2), (build_doorframe, 1.4),
    )
    for build, uv in props:
        clear_scene()
        export(build(), uv)
    print("Done.")


if __name__ == "__main__":
    main()
