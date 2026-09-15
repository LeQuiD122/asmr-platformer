"""
Backdrop props: low-poly stylised meshes for the liminal horizon.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_backdrop.py

Everything in BackdropService is Roblox primitives -- boxes, spheres and cylinders --
and past a certain point that is the ceiling on how the horizon can look. A stretched
block is a stretched block; it cannot be a mushroom, a gabled roof or a tree. These are
the shapes the primitives could not be.

=== Optimised on purpose, and heavily ===

Nothing here is ever seen closer than about 300 studs, through 0.3-density haze, and the
whole backdrop is pivoted every frame -- so triangles cost more here than anywhere else
in the project and buy less. Every prop is built from a handful of primitives at the
lowest segment count that still reads: 8-12 around a cylinder, 6-8 rings on a dome. At
this distance the difference between 8 segments and 32 is invisible and the difference in
frame time is not.

=== Why OBJ and not FBX ===

Backdrop props are scenery: nothing deforms, so nothing needs an armature. OBJ is the
right format for exactly the reason the platform rigs need FBX -- see the handoff.
"""

import bmesh
import bpy
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import uv_project

OUT_DIR = r"C:\Users\Arsenii\Downloads\asmr-platformer-implementation_1\RobloxProject\meshes"

# Low, everywhere. See the module docstring: this is the whole design constraint.
SEGMENTS = 10
RINGS = 6

# === Two detail levels ===
#
# Every prop is exported TWICE: once at the counts above as `Backdrop_X`, and once at this
# multiplier as `Backdrop_X_Detail`.
#
# The single-detail assumption held while the whole backdrop sat past 2400 studs. It does
# not any more -- the near band starts at 800 studs and objects are scaled four to eleven
# times, so a 100-unit prop can be 700 studs tall and 950 away. That subtends about 40
# degrees, and at that size a 10-segment dome is visibly a polygon.
#
# BackdropService asks for the `_Detail` name in the near band and the plain one further
# out, falling back to whichever exists. Neither is required: a missing detail mesh just
# means the near band draws the low-poly one, which is what it did before.
DETAIL = 1.0
DETAIL_MULTIPLIER = 2.4

# How far every hard edge is chamfered back, in authored units. Props are placed at two to
# thirteen times scale, so 0.45 here lands between one and six studs in game -- enough to
# hold a highlight at 900 studs and small enough that no silhouette changes.
BEVEL = 0.45


def _seg(count):
    """Scale a segment count by the current detail level, never below a usable minimum.

    Call this ONLY where a segment count reaches bmesh directly. `tube` and `dome` apply it
    themselves, so `tube(..., segments=_seg(8))` scales TWICE -- 8 becomes 46 rather than 19
    at the detail multiplier, and the prop silently blows its triangle budget. That is how
    the lane rope reached 8320 against a limit of 6000.
    """
    return max(3, int(round(count * DETAIL)))


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def dome(bm, radius, height, at, segments=SEGMENTS, rings=RINGS, bottom=False):
    """Half a UV sphere, flat side down (or up). The workhorse: caps, canopies, hills
    and cloud lobes are all this shape at different proportions."""
    segments, rings = _seg(segments), _seg(rings)
    made = bmesh.ops.create_uvsphere(
        bm, u_segments=segments, v_segments=rings * 2, radius=1.0
    )
    verts = made["verts"]
    # Squash to the wanted proportions, then discard the half that is not needed.
    bmesh.ops.scale(bm, vec=(radius, radius, height), verts=verts)
    keep = []
    for v in verts:
        if (v.co.z < -1e-6) if not bottom else (v.co.z > 1e-6):
            keep.append(v)
    if keep:
        bmesh.ops.delete(bm, geom=keep, context="VERTS")
    remaining = [v for v in made["verts"] if v.is_valid]
    bmesh.ops.translate(bm, vec=at, verts=remaining)
    return remaining


def tube(bm, radius, depth, at, segments=SEGMENTS, taper=1.0):
    segments = _seg(segments)
    made = bmesh.ops.create_cone(
        bm,
        cap_ends=True,
        cap_tris=False,
        segments=segments,
        radius1=radius,
        radius2=radius * taper,
        depth=depth,
    )
    bmesh.ops.translate(bm, vec=at, verts=made["verts"])
    return made["verts"]


def box(bm, size, at, rotation=0.0, tilt=0.0):
    made = bmesh.ops.create_cube(bm, size=1.0)
    verts = made["verts"]
    bmesh.ops.scale(bm, vec=size, verts=verts)
    # Tilt (about Y) before spin (about Z), so `rotation` always means "which way is it
    # facing" regardless of how far the thing is leaning over.
    if tilt:
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_roty(tilt))
    if rotation:
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_rotz(rotation))
    bmesh.ops.translate(bm, vec=at, verts=verts)
    return verts


def _rotz(angle):
    import mathutils

    return mathutils.Matrix.Rotation(angle, 3, "Z")


def _roty(angle):
    import mathutils

    return mathutils.Matrix.Rotation(angle, 3, "Y")


def _rotx(angle):
    import mathutils

    return mathutils.Matrix.Rotation(angle, 3, "X")


# === The props ===


def island(bm):
    """A floating island: domed grass on top, a tapering spur of rock beneath.

    The taper is what sells it as FLOATING rather than as a hill with the ground cropped
    -- an island that ends flat reads as a mesh that was cut off, while one that comes to
    a point reads as something torn out and left hanging.
    """
    dome(bm, 30.0, 11.0, (0, 0, 0))
    tube(bm, 29.0, 12.0, (0, 0, -6.0), taper=0.78)
    tube(bm, 22.6, 22.0, (0, 0, -23.0), taper=0.45)
    # The spur runs to nearly twice the cap's radius below it. The first version stopped
    # about level with the cap width and read as a stack of discs -- a floating island is
    # sold by the LENGTH of what is hanging under it, not by the taper alone.
    tube(bm, 10.2, 26.0, (0, 0, -47.0), taper=0.10)


def mushroom(bm):
    """Stalk and cap. The cap is a dome with a slight lip, which is the one detail that
    separates a mushroom from a lampshade at this distance."""
    tube(bm, 4.2, 26.0, (0, 0, 13.0), taper=1.25)
    dome(bm, 20.0, 13.0, (0, 0, 25.0))
    # The lip: a shallow inverted dome under the cap's rim, so the underside is not a
    # flat disc when seen from below -- which, on a floating island, it usually is.
    dome(bm, 19.0, 4.0, (0, 0, 25.0), bottom=True)


def house(bm):
    """A gabled house. Two boxes and a prism, which is all a house is at this range --
    what matters is the ROOF PITCH, because that silhouette is what says 'house' from
    a thousand studs away when no window is resolvable."""
    box(bm, (26.0, 20.0, 22.0), (0, 0, 11.0))

    # The roof, as a prism: a box rotated 45 degrees about its long axis and squashed,
    # which gives two clean pitched faces without needing a custom mesh.
    made = bmesh.ops.create_cube(bm, size=1.0)
    verts = made["verts"]
    bmesh.ops.scale(bm, vec=(19.0, 19.0, 24.0), verts=verts)
    bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_roty(math.pi / 4))
    bmesh.ops.scale(bm, vec=(1.0, 1.0, 0.62), verts=verts)
    bmesh.ops.translate(bm, vec=(0, 0, 24.0), verts=verts)

    # A chimney, because an unbroken roofline reads as a shed.
    box(bm, (4.0, 4.0, 12.0), (7.0, 0, 30.0))


def tree(bm):
    """Trunk and a cluster of canopy lobes. Lobes rather than one sphere for the same
    reason the cloud banks are clustered: a single sphere on a stick is a lollipop."""
    tube(bm, 2.8, 36.0, (0, 0, 18.0), segments=8, taper=0.65)
    # A crown TALLER THAN IT IS WIDE, stacked at several heights.
    #
    # The first version was four lobes all at one height on a short trunk, and side by side
    # with the mushroom the two were the same object -- a flat cap on a stick. What tells a
    # tree from a mushroom at distance is that a canopy has depth: lobes at different
    # heights break the top edge into something irregular, where a cap is one clean curve.
    lobes = (
        (0.0, 0.0, 34.0, 15.0, 13.0),
        (7.5, 2.0, 41.0, 11.0, 10.0),
        (-7.0, -2.5, 42.0, 10.5, 10.0),
        (1.5, 6.5, 40.0, 9.5, 9.0),
        (-1.0, -6.0, 39.0, 9.0, 8.5),
        (0.0, 0.0, 48.0, 9.0, 10.0),
    )
    for x, y, z, radius, height in lobes:
        dome(bm, radius, height, (x, y, z), segments=8, rings=4)


def cloud(bm):
    """A puffy cloud as clustered lobes with a flat base. Flat underneath because that
    is what a cumulus does, and it is the difference between a cloud and a bag of
    spheres -- which is exactly what the primitive version looked like."""
    lobes = ((0, 0, 0, 16.0), (13, 3, -2, 11.0), (-12, -2, -2, 12.0), (3, -11, -3, 10.0), (-4, 10, -3, 9.5))
    for x, y, z, radius in lobes:
        dome(bm, radius, radius * 0.82, (x, y, z), segments=8, rings=4)


def arch(bm):
    """A pipe arch: the poolroom tube, bent. Built as a ring of short segments rather
    than a real torus, which at this segment count is the same picture for a fraction of
    the geometry."""
    import mathutils

    radius, thickness, steps = 34.0, 7.0, _seg(9)
    for i in range(steps + 1):
        angle = math.pi * (i / steps)
        made = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=_seg(8),
            radius1=thickness, radius2=thickness, depth=radius * math.pi / steps * 1.15,
        )
        verts = made["verts"]
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_roty(math.pi / 2 - angle))
        bmesh.ops.translate(
            bm,
            vec=(math.cos(angle) * radius, 0.0, math.sin(angle) * radius),
            verts=verts,
        )


def statue(bm):
    """An abstract standing figure on a plinth.

    Deliberately FEATURELESS -- no face, no hands. A statue at this scale only has to read
    as "something in the shape of a person is standing there", and any detail finer than
    the silhouette is invisible through the haze anyway. The absence is also the better
    version: a monument to nobody in particular is more unsettling than a specific one.
    """
    box(bm, (34.0, 34.0, 8.0), (0, 0, 4.0))
    box(bm, (27.0, 27.0, 5.0), (0, 0, 10.0))
    # Legs, torso, head. The torso tapers upward, which is what keeps it from reading as
    # a chimney.
    tube(bm, 9.0, 26.0, (0, 0, 25.0), segments=8, taper=0.85)
    tube(bm, 11.0, 24.0, (0, 0, 50.0), segments=8, taper=0.72)
    dome(bm, 6.5, 8.0, (0, 0, 62.0), segments=8, rings=4)
    # Arms held out and DOWN from the shoulders, so the silhouette has gaps in it.
    #
    # These pointed straight up in the first version and the statue read as a figure with
    # horns. create_cone extrudes along Z, so the tilt has to carry the arm most of the way
    # past horizontal before it hangs at all: 0.3 radians is still essentially vertical,
    # which is what went wrong. 2.0 radians is out and slightly down, which is a person.
    for side in (-1.0, 1.0):
        length = 26.0
        tilt = side * 2.0
        made = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=_seg(6),
            radius1=3.4, radius2=2.6, depth=length,
        )
        bmesh.ops.rotate(bm, verts=made["verts"], cent=(0, 0, 0), matrix=_roty(tilt))
        # Hung FROM the shoulder rather than centred on it: the cone is built about its own
        # middle, so it has to be pushed half its length along the direction it now points.
        bmesh.ops.translate(
            bm,
            vec=(
                side * 11.0 + math.sin(tilt) * length / 2,
                0.0,
                58.0 + math.cos(tilt) * length / 2,
            ),
            verts=made["verts"],
        )


def umbrella(bm):
    """A poolside parasol. From the drained-pool references, and the one prop here whose
    shape is almost entirely its canopy -- so the canopy gets a real edge rather than
    ending in a hard rim, which is what separates fabric from a dish."""
    tube(bm, 2.0, 62.0, (0, 0, 31.0), segments=8)
    dome(bm, 30.0, 15.0, (0, 0, 58.0), segments=12, rings=5)
    # A drooping edge: a short inverted cone under the canopy rim, so the silhouette
    # curves down and out the way loaded fabric does.
    tube(bm, 30.0, 7.0, (0, 0, 55.0), segments=12, taper=0.80)
    dome(bm, 3.2, 4.0, (0, 0, 73.0), segments=6, rings=3)


def slide(bm):
    """A playplace tube slide, curving down out of nothing.

    Built as a chain of short tubes along a descending arc rather than a swept curve --
    same picture at this segment count, a fraction of the geometry, and it lets the run
    steepen toward the bottom the way a real slide does.
    """
    import mathutils

    steps, radius = _seg(9), 26.0
    for i in range(steps + 1):
        turn = (i / steps) * math.pi * 1.15
        # Descent accelerates: the drop is quadratic in the turn, not linear.
        drop = 74.0 * (i / steps) ** 1.55
        made = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=_seg(8),
            radius1=8.5, radius2=8.5, depth=20.0,
        )
        verts = made["verts"]
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_rotz(turn))
        bmesh.ops.translate(
            bm,
            vec=(math.cos(turn) * radius, math.sin(turn) * radius, 78.0 - drop),
            verts=verts,
        )
    # The tower it comes off, and the landing it ends on.
    tube(bm, 6.0, 84.0, (radius, 0.0, 42.0), segments=8)
    box(bm, (30.0, 24.0, 5.0), (math.cos(math.pi * 1.15) * radius, math.sin(math.pi * 1.15) * radius, 2.5))


def water_tower(bm):
    """A tank on legs. Punctuates a horizon of rectangles with something that is clearly
    a MACHINE rather than a building -- and legs mean you see sky through it."""
    tube(bm, 22.0, 26.0, (0, 0, 60.0), segments=12)
    dome(bm, 22.0, 10.0, (0, 0, 73.0), segments=12, rings=4)
    dome(bm, 22.0, 9.0, (0, 0, 47.0), segments=12, rings=4, bottom=True)
    for i in range(4):
        angle = (i / 4) * math.tau + math.pi / 4
        made = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=_seg(6),
            radius1=2.4, radius2=2.4, depth=52.0,
        )
        verts = made["verts"]
        # Legs splay outward, which is both what real ones do and what stops the tower
        # reading as a mushroom.
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_roty(0.16))
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_rotz(angle))
        bmesh.ops.translate(
            bm, vec=(math.cos(angle) * 15.0, math.sin(angle) * 15.0, 24.0), verts=verts
        )


def hoop(bm):
    """A ring sculpture standing on end: the civic art nobody can explain. Same segmented
    construction as the arch, closed into a full circle and set on a low base."""
    radius, thickness, steps = 30.0, 5.0, _seg(14)
    for i in range(steps):
        angle = math.tau * (i / steps)
        made = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=_seg(6),
            radius1=thickness, radius2=thickness, depth=radius * math.tau / steps * 1.2,
        )
        verts = made["verts"]
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_roty(math.pi / 2 - angle))
        bmesh.ops.translate(
            bm, vec=(math.cos(angle) * radius, 0.0, math.sin(angle) * radius + radius + 6.0), verts=verts
        )
    box(bm, (26.0, 18.0, 12.0), (0, 0, 6.0))


# === The ASMR props ===
#
# The horizon as a MUSEUM OF THE GAME'S OWN MATERIALS. Every surface you walk on exists out
# there at a monstrous size: the butter you deform, the slime, the honey, the soap. That
# turns the backdrop from generic liminal architecture into an explanation of where the
# level came from -- which is a much stronger reason for a giant object to be standing in
# an empty plain than "it is big and that is strange".
#
# The keyboard and the microphone are the two objects that say ASMR before anything else
# does, and neither is a platform material -- they are the genre itself, standing in the
# same field as the things it is about.


def keycap(bm, width, depth, height, at, taper=0.78):
    """One keycap.

    A 4-segment cone is a SQUARE FRUSTUM, which is exactly a keycap: wider at the base,
    narrower at the top, flat on both. It costs the same twelve triangles a plain box does
    and reads as a key instead of a tile, so there is no reason to use a box here.
    """
    made = bmesh.ops.create_cone(
        bm, cap_ends=True, cap_tris=False, segments=4,
        # A 4-segment cone's "radius" is its CIRCUMradius, so a square of side s needs
        # s / sqrt(2). Getting this wrong gives keys 40% too big and a grid that overlaps.
        radius1=depth * 0.7071, radius2=depth * 0.7071 * taper, depth=height,
    )
    verts = made["verts"]
    bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_rotz(math.pi / 4))
    # Stretched along X afterwards, so wide keys (space, shift) keep the same taper and
    # the same top-to-base ratio as the 1u keys around them.
    bmesh.ops.scale(bm, vec=(width / depth, 1.0, 1.0), verts=verts)
    bmesh.ops.translate(bm, vec=at, verts=verts)


def keyboard(bm):
    """A mechanical keyboard, at the size of a city block.

    A real 60% layout rather than a uniform grid. The stagger and the wide modifiers are
    the entire read -- an even grid of squares is a waffle, and what makes a keyboard
    recognisable from a long way off is the ragged left edge and that one very wide key
    along the bottom.
    """
    unit, gap = 6.0, 0.8
    rows = (
        [1] * 13 + [2],
        [1.5] + [1] * 12 + [1.5],
        [1.75] + [1] * 11 + [2.25],
        [2.25] + [1] * 10 + [2.75],
        [1.25] * 3 + [6.25] + [1.25] * 4,
    )
    span = max(sum(r) for r in rows)
    case_w, case_d = span * unit + 5, len(rows) * unit + 5

    box(bm, (case_w, case_d, 7.0), (0, 0, 3.5))
    # A raised back lip, so the profile is a wedge and not a plank.
    box(bm, (case_w, unit * 0.6, 13.0), (0, case_d / 2 - unit * 0.3, 6.5))

    for r, widths in enumerate(rows):
        y = ((len(rows) - 1) / 2 - r) * unit
        x = -sum(widths) / 2
        for w in widths:
            keycap(
                bm,
                w * unit - gap,
                unit - gap,
                5.0,
                ((x + w / 2) * unit, y, 9.5),
            )
            x += w


def butter(bm):
    """A stick of butter with its wax shell torn back, and one pat cut off the end.

    Straight off the ButterWax platform, which is the material this backdrop is furthest
    from explaining otherwise. The shell has to be A SIZE LARGER than the butter and stop
    partway along -- an even coating reads as a painted block, while a shell that ends in a
    torn lip with something softer coming out of it reads as a shell.
    """
    # The exposed butter, and a pat lifted off the end at an angle.
    #
    # A LOW DOME ON TOP, which is the one detail keeping this out of the skyline. A pure
    # rectangular block standing on a plain next to 116 rectangular towers is a building,
    # whatever colour it is painted; the soft crown is what makes it something that was cut
    # rather than built.
    box(bm, (32, 30, 22), (26, 0, 11))
    dome(bm, 15.0, 6.0, (26, 0, 22), segments=10, rings=4)
    box(bm, (13, 28, 7), (50, 0, 4), rotation=0.22)
    # The shell over the rest, a size larger, with a thick torn edge where it ends.
    box(bm, (56, 36, 30), (-18, 0, 15))
    box(bm, (5, 40, 35), (9, 0, 17))


def microphone(bm):
    """A studio condenser on a stand: the single most recognisable object in the genre.

    The shock mount matters more than the capsule. A cylinder on a stick is a lollipop --
    the ring suspended around it, with gaps you can see through, is what makes it a
    microphone and not a lamp.
    """
    tube(bm, 20.0, 5.0, (0, 0, 2.5), segments=12)
    tube(bm, 3.2, 62.0, (0, 0, 33.0), segments=8)
    # The capsule: body, grille band, domed head.
    tube(bm, 11.0, 34.0, (0, 0, 82.0), segments=12)
    tube(bm, 12.2, 12.0, (0, 0, 92.0), segments=12)
    dome(bm, 11.0, 9.0, (0, 0, 99.0), segments=12, rings=4)
    # The shock mount: a ring of short segments AROUND the capsule.
    #
    # This has to lie in the XY plane. Copied from the arch and the hoop, it inherited
    # their XZ orientation -- which encircles the Y axis, not the microphone -- and the
    # segments came out as spikes radiating from the capsule instead of a ring around it.
    # The arch and the hoop are meant to stand up on edge; a shock mount is not.
    #
    # Two rotations rather than one: swing the segment's Z axis onto X, then spin it around
    # to the tangent at this angle. The tangent at theta is (-sin, cos, 0), which is exactly
    # +X rotated by theta + 90 degrees.
    radius, steps = 20.0, _seg(12)
    for i in range(steps):
        angle = math.tau * (i / steps)
        made = bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=_seg(5),
            radius1=2.2, radius2=2.2, depth=radius * math.tau / steps * 1.25,
        )
        verts = made["verts"]
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_roty(math.pi / 2))
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_rotz(angle + math.pi / 2))
        bmesh.ops.translate(
            bm, vec=(math.cos(angle) * radius, math.sin(angle) * radius, 86.0), verts=verts
        )
    # Two arms tying the ring back to the post, so it is suspended rather than floating.
    for side in (-1.0, 1.0):
        box(bm, (radius, 3.0, 3.0), (side * radius / 2, 0.0, 86.0))


def honey_dipper(bm):
    """A dipper standing in its pot. The grooves are the whole object -- a smooth rod in a
    jar is a spoon, and it is the stack of alternating discs that says honey."""
    tube(bm, 21.0, 28.0, (0, 0, 14.0), segments=12, taper=1.18)
    tube(bm, 26.0, 5.0, (0, 0, 30.0), segments=12)
    # Honey standing proud of the rim, because a pot you cannot see into is just a pot.
    dome(bm, 23.0, 7.0, (0, 0, 31.0), segments=12, rings=4)
    for i in range(6):
        wide = i % 2 == 0
        tube(bm, 10.0 if wide else 6.5, 5.0, (0, 0, 36.0 + i * 5.0), segments=10)
    tube(bm, 2.6, 40.0, (0, 0, 84.0), segments=8)
    dome(bm, 4.2, 5.0, (0, 0, 103.0), segments=8, rings=3)


def soap(bm):
    """A bar of soap mid-carve, with curls shaved off beside it. Soap carving is the other
    thing the genre is made of, and the curls are what date the bar -- an untouched bar is
    just a rounded box."""
    box(bm, (56, 36, 13), (0, 0, 10.5))
    box(bm, (50, 30, 5), (0, 0, 19.0))
    box(bm, (50, 30, 5), (0, 0, 3.5))
    for x, y, turn in ((36, 12, 0.5), (44, -9, -0.8), (30, -21, 0.25), (48, 20, 1.1)):
        box(bm, (18, 6, 3.5), (x, y, 2.0), rotation=turn)


def slime_jar(bm):
    """Slime bulging over the rim of its jar, with one run down the side. The overflow is
    the point: slime level with the rim is water."""
    tube(bm, 22.0, 42.0, (0, 0, 21.0), segments=14)
    tube(bm, 25.0, 6.0, (0, 0, 43.0), segments=14)
    dome(bm, 24.0, 16.0, (0, 0, 45.0), segments=14, rings=5)
    # The run: a short tapered tube hanging off one side, which is the only asymmetry in
    # the shape and therefore the thing that keeps it from reading as a cupcake.
    tube(bm, 5.0, 26.0, (24.0, 0.0, 33.0), segments=6, taper=0.45)
    dome(bm, 3.0, 4.0, (24.0, 0.0, 20.0), segments=6, rings=3, bottom=True)


def candle(bm):
    """A pillar candle that has burned a long way down.

    The RUNS are the whole object. A smooth cylinder with a wick is a bollard; wax that has
    spilled over the rim and set partway down the side is unmistakable, and it is the one
    shape here that records something having happened over time rather than just standing.

    Unlit on purpose. A Roblox MeshPart carries a single colour, so a flame would be the
    same wax white as the candle -- a pale blob on a stick, which is worse than no flame.
    """
    tube(bm, 18.0, 66.0, (0, 0, 33.0))
    # The pool at the top: a rim standing slightly proud around a dished middle, which is
    # what a burned-down candle actually looks like from above.
    tube(bm, 18.5, 5.0, (0, 0, 67.0))
    dome(bm, 15.0, 5.5, (0, 0, 68.5), bottom=True)

    # Each run hangs from just under the rim at its own length. EQUAL lengths would read as
    # fluting -- a decorative column -- and it is the raggedness that says spillage.
    for angle, length in ((0.0, 26.0), (0.9, 41.0), (1.8, 17.0), (2.8, 33.0), (3.9, 22.0), (5.1, 45.0)):
        x, y = math.cos(angle) * 17.0, math.sin(angle) * 17.0
        tube(bm, 3.4, length, (x, y, 65.0 - length / 2), segments=6, taper=0.7)
        # A rounded blob at the bottom of each run, where it stopped and set.
        dome(bm, 2.5, 3.5, (x, y, 65.0 - length), segments=6, rings=3, bottom=True)

    tube(bm, 1.1, 10.0, (0, 0, 72.0), segments=4)


def foam(bm):
    """A stack of foam blocks, the top one cut clean through and the halves pushed apart.

    Cutting foam is its own corner of the genre, and the cut is the entire point -- a stack
    of plain blocks is a pallet. There is no boolean here: the top block is simply built as
    TWO pieces with a gap and a slight twist between them, which reads as a cut from any
    angle and costs twelve triangles instead of a solver.
    """
    box(bm, (64.0, 48.0, 24.0), (0, 0, 12.0))
    box(bm, (56.0, 44.0, 20.0), (3.0, -2.0, 34.0), rotation=0.08)
    box(bm, (23.0, 38.0, 18.0), (-13.0, 1.0, 53.0), rotation=-0.05)
    box(bm, (23.0, 38.0, 18.0), (14.0, 3.0, 53.5), rotation=0.11)
    # An offcut leaning against the stack, and a slice lying flat beside it.
    box(bm, (30.0, 34.0, 5.0), (46.0, -8.0, 16.0), rotation=0.22, tilt=1.15)
    box(bm, (26.0, 30.0, 4.0), (40.0, 30.0, 2.0), rotation=-0.5)


# === The aquapark ===
#
# The horizon read as a city because it was 116 towers and almost nothing else. A skyline is
# made of repeated verticals; a waterpark is made of CURVES AND CANTILEVERS -- things that
# lean out over water, spiral, and stop in mid-air. Those are the shapes that cannot be
# mistaken for architecture, and they are why this reads as somewhere else entirely.
#
# All of them are unmistakably ABANDONED at this scale too: a flume with no water in it and
# a bucket that will never tip are the liminal reading, and they get it from silhouette
# rather than from decay detail, which would vanish in the haze anyway.


def slide_tower(bm):
    """A stepped tower with a tube slide spiralling off it.

    The HELIX is the whole object. A stepped tower alone is architecture -- it is the tube
    wrapping down and away that says waterpark and nothing else, so the spiral gets three
    full turns and a long run-out rather than a token curl.
    """
    for width, height, z in ((30.0, 18.0, 9.0), (24.0, 16.0, 26.0), (18.0, 14.0, 41.0)):
        box(bm, (width, width, height), (0, 0, z))

    made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(4),
                                 radius1=15.0, radius2=1.0, depth=12.0)
    bmesh.ops.rotate(bm, verts=made["verts"], cent=(0, 0, 0), matrix=_rotz(math.pi / 4))
    bmesh.ops.translate(bm, vec=(0, 0, 54.0), verts=made["verts"])

    turns, steps = 3.0, _seg(30)
    for i in range(steps + 1):
        f = i / steps
        angle = f * math.tau * turns
        # The radius OPENS OUT as it descends and the drop accelerates, which is what a real
        # flume does and what stops the helix reading as a spring.
        radius = 20.0 + f * 26.0
        z = 46.0 - 44.0 * f ** 1.35
        made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(8),
                                     radius1=5.5, radius2=5.5, depth=13.0)
        verts = made["verts"]
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_roty(math.pi / 2))
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_rotz(angle + math.pi / 2))
        bmesh.ops.translate(
            bm, vec=(math.cos(angle) * radius, math.sin(angle) * radius, z), verts=verts
        )


def flume(bm):
    """An open chute on legs, running out and stopping in mid-air.

    Open rather than a closed tube: you see along the inside of it, and an empty channel
    reads as DRAINED far more strongly than a pipe, which could be full of anything.
    """
    steps = _seg(16)
    span, drop = 100.0, 34.0
    for i in range(steps + 1):
        f = i / steps
        x = (f - 0.5) * span
        z = 46.0 - drop * f ** 1.6
        sway = math.sin(f * math.pi * 1.2) * 16.0
        run = span / steps * 1.3
        # Two walls and a floor rather than a closed section: the U is what makes it a chute.
        box(bm, (run, 3.0, 11.0), (x, sway - 7.0, z + 4.0))
        box(bm, (run, 3.0, 11.0), (x, sway + 7.0, z + 4.0))
        box(bm, (run, 17.0, 3.0), (x, sway, z))
        if i % 4 == 0:
            tube(bm, 2.2, z + 40.0, (x, sway, (z - 40.0) / 2), segments=6)


def splash_bucket(bm):
    """The giant tipping bucket on its frame, held at an angle.

    Tilted rather than upright on purpose: a level bucket is a water tank, and the whole
    charm of the thing is being caught mid-decision.
    """
    made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(14),
                                 radius1=15.0, radius2=21.0, depth=26.0)
    verts = made["verts"]
    bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_roty(0.42))
    bmesh.ops.translate(bm, vec=(0, 0, 52.0), verts=verts)
    tube(bm, 22.0, 4.0, (0, 0, 64.0), segments=14)

    # An A-frame splayed in BOTH axes, so it reads as a structure rather than two posts.
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(5),
                                         radius1=2.6, radius2=2.6, depth=58.0)
            v = made["verts"]
            bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_roty(sx * 0.20))
            bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_rotx(sy * 0.20))
            bmesh.ops.translate(bm, vec=(sx * 14.0, sy * 14.0, 27.0), verts=v)
    box(bm, (44.0, 6.0, 3.0), (0, 0, 46.0))


def float_ring(bm):
    """An inflatable ring, lying flat. The one prop that belongs ON the water rather than
    standing in it, and the roundest thing on the whole horizon."""
    radius, thickness, steps = 22.0, 7.0, _seg(16)
    for i in range(steps):
        angle = math.tau * (i / steps)
        made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(8),
                                     radius1=thickness, radius2=thickness,
                                     depth=radius * math.tau / steps * 1.25)
        verts = made["verts"]
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_roty(math.pi / 2))
        bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_rotz(angle + math.pi / 2))
        bmesh.ops.translate(
            bm, vec=(math.cos(angle) * radius, math.sin(angle) * radius, 0.0), verts=verts
        )


def cabana(bm):
    """A changing cabin under a canopy.

    Small, and that is the point: something at human scale standing between the giants is
    what makes the giants read as giant. Without it they are just large objects.
    """
    box(bm, (22.0, 20.0, 26.0), (0, 0, 13.0))
    box(bm, (30.0, 28.0, 3.0), (0, 0, 27.0))
    for k in range(4):
        box(bm, (2.4, 2.4, 12.0), ((k % 2 * 2 - 1) * 13.0, (k // 2 * 2 - 1) * 12.0, 33.0))
    # A canopy floating above the posts, so the silhouette has a gap you can see sky through.
    box(bm, (34.0, 32.0, 2.4), (0, 0, 40.0))


def lifeguard_chair(bm):
    """A tall chair facing water, with nobody in it.

    Splayed legs, a cantilevered seat and a little roof -- every one of those is a
    horizontal at a height nothing else out here has, which is what makes it legible.
    """
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(5),
                                         radius1=1.8, radius2=1.8, depth=40.0)
            v = made["verts"]
            bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_roty(sx * 0.13))
            bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_rotx(sy * 0.13))
            bmesh.ops.translate(bm, vec=(sx * 8.0, sy * 8.0, 20.0), verts=v)
    box(bm, (20.0, 18.0, 2.6), (0, 0, 40.0))
    box(bm, (2.6, 18.0, 16.0), (-9.0, 0, 48.0))
    box(bm, (22.0, 20.0, 2.0), (2.0, 0, 60.0))


def diving_platform(bm):
    """The tiered concrete diving tower: three decks stepping out over nothing.

    The best silhouette available for this, because a stack of CANTILEVERS is a shape with
    no other explanation -- there is no building, tree or machine that puts three unsupported
    slabs at three heights over the same spot. It reads instantly and from any angle.
    """
    box(bm, (18.0, 16.0, 82.0), (0, 0, 41.0))
    for z, reach in ((26.0, 26.0), (48.0, 32.0), (72.0, 38.0)):
        box(bm, (reach, 18.0, 3.6), (reach / 2 - 4.0, 0, z))
        # A rail down each side of the deck, stopping short of the tip the way they do.
        for side in (-1.0, 1.0):
            box(bm, (reach * 0.7, 1.6, 9.0), (reach * 0.35 - 2.0, side * 8.0, z + 6.0))
        tube(bm, 1.6, 9.0, (reach - 5.0, 0, z + 6.0), segments=5)


def pool_ladder(bm):
    """Chrome rails curling over at the top, with three treads.

    The CURL is the whole thing. Two straight posts are a fence; the quarter-turn where a
    handrail bends over the edge to be gripped is unmistakably a pool, and it is the one
    piece of aquapark furniture that is basically pure line.
    """
    steps = _seg(7)
    for side in (-1.0, 1.0):
        tube(bm, 1.5, 30.0, (0, side * 7.0, 15.0), segments=6)
        for k in range(steps):
            a = math.pi / 2 * (k / (steps - 1))
            radius = 9.0
            made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(6),
                                         radius1=1.5, radius2=1.5,
                                         depth=radius * math.pi / 2 / steps * 1.4)
            v = made["verts"]
            bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_roty(-a))
            bmesh.ops.translate(
                bm,
                vec=(math.sin(a) * radius, side * 7.0, 30.0 + math.cos(a) * radius - radius),
                verts=v,
            )
    for k in range(3):
        box(bm, (7.0, 16.0, 1.6), (1.0, 0, 6.0 + k * 7.0))


def lounger(bm):
    """A sun lounger, reclined and empty.

    The only strongly HORIZONTAL prop in the set, which is why it is here -- everything else
    on this horizon stands up, and a low flat thing beside them gives the eye a rest and the
    scene a floor.
    """
    box(bm, (34.0, 16.0, 2.4), (0, 0, 7.0))
    # The backrest, propped at an angle rather than upright: nobody leaves a lounger flat.
    box(bm, (18.0, 16.0, 2.4), (-22.0, 0, 12.0), tilt=-0.62)
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            tube(bm, 1.0, 7.0, (sx * 14.0, sy * 6.5, 3.5), segments=5)


def mushroom_fountain(bm):
    """The kiddie-pool umbrella fountain: a thick stem under a wide flat disc.

    Flat and lipped, NOT domed -- the backdrop already has a mushroom and a parasol, and a
    third rounded cap would just be those again. What makes this one different is that its
    top is a plate with a downturned rim, which is the shape water sheets off.
    """
    tube(bm, 5.0, 30.0, (0, 0, 15.0), segments=10)
    tube(bm, 26.0, 4.0, (0, 0, 32.0), segments=16)
    tube(bm, 27.0, 7.0, (0, 0, 29.0), segments=16, taper=0.86)
    # A shallow basin at the foot, so it reads as plumbed in rather than planted.
    tube(bm, 34.0, 3.0, (0, 0, 1.5), segments=16)


def lane_rope(bm):
    """A lane divider: floats threaded on a line, running out and stopping.

    Long, thin and horizontal, which is a proportion nothing else here has. It also lies ON
    the water, so it is one of the few props that reads as belonging to the surface rather
    than standing in it.
    """
    # NOT scaled by detail. How many floats a lane divider has is a design decision, not a
    # smoothness setting -- running it through _seg multiplied the float count AND each
    # float's segments, and the detail variant came out at 13900 triangles against a 6000
    # budget. Detail should refine what is there, never add more of it.
    count = 22
    for k in range(count):
        x = (k / (count - 1) - 0.5) * 130.0
        radius = 3.4 if k % 3 else 4.6
        tube(bm, radius, 4.6, (x, 0, 0), segments=8)
    # ALONG X, not up. tube() extrudes along Z like every other cone here, so this line ran
    # 134 studs vertically -- a lane rope standing on end. The aspect check that decides
    # whether a prop lies on the water or stands in it is what surfaced it: a divider came
    # out at 0.91 tall-to-long when it should be under 0.1.
    made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(4),
                                 radius1=0.8, radius2=0.8, depth=134.0)
    bmesh.ops.rotate(bm, verts=made["verts"], cent=(0, 0, 0), matrix=_roty(math.pi / 2))
    # An anchor float at each end, larger than the rest.
    for side in (-1.0, 1.0):
        dome(bm, 6.0, 5.0, (side * 68.0, 0, -2.0), segments=8, rings=4)


def palm(bm):
    """A plastic palm, leaning, with drooping fronds.

    Aquapark planting is fake and everyone knows it, so this is deliberately simple: a bent
    trunk and eight straight tapered fronds angled down. The LEAN is what sells it -- a
    vertical palm reads as a feather duster.
    """
    steps = _seg(7)
    for k in range(steps):
        f = k / (steps - 1)
        made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(7),
                                     radius1=3.4 - f * 1.6, radius2=3.4 - f * 1.7,
                                     depth=54.0 / steps * 1.3)
        v = made["verts"]
        bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_roty(f * 0.45))
        bmesh.ops.translate(bm, vec=(f * f * 13.0, 0.0, 4.0 + f * 52.0), verts=v)

    for i in range(8):
        angle = math.tau * i / 8
        made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(4),
                                     radius1=3.6, radius2=0.5, depth=34.0)
        v = made["verts"]
        bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_roty(math.pi / 2 - 0.5))
        bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_rotz(angle))
        bmesh.ops.translate(
            bm,
            vec=(13.0 + math.cos(angle) * 14.0, math.sin(angle) * 14.0, 56.0),
            verts=v,
        )


def play_structure(bm):
    """The multi-level aqua play frame: decks, posts, a tube off one side, a bucket on top.

    The most COMPLEX silhouette in the set, and deliberately so. Everything else out here is
    one clear shape; this is a tangle of horizontals and verticals with holes through it,
    which is exactly what the big centrepiece frame looks like from across a pool. Its
    legibility comes from being busy where everything around it is simple.
    """
    posts = ((-22.0, -22.0), (22.0, -22.0), (-22.0, 22.0), (22.0, 22.0))
    for px, py in posts:
        tube(bm, 2.6, 72.0, (px, py, 36.0), segments=7)

    for z, half in ((22.0, 24.0), (42.0, 20.0), (60.0, 15.0)):
        box(bm, (half * 2, half * 2, 2.6), (0, 0, z))
        # A rail around each deck, which is what gives the frame its stack of horizontals.
        for sx, sy in ((0.0, 1.0), (0.0, -1.0), (1.0, 0.0), (-1.0, 0.0)):
            box(bm,
                (half * 2 if sy != 0 else 1.8, half * 2 if sx != 0 else 1.8, 9.0),
                (sx * half, sy * half, z + 6.0))

    # A tube dropping off one corner, short and steep.
    for i in range(9):
        f = i / 8
        angle = f * math.pi * 0.9
        made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(7),
                                     radius1=5.0, radius2=5.0, depth=11.0)
        v = made["verts"]
        bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_roty(math.pi / 2))
        bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_rotz(angle + math.pi / 2))
        bmesh.ops.translate(
            bm,
            vec=(30.0 + math.cos(angle) * 18.0, math.sin(angle) * 18.0, 42.0 - 34.0 * f ** 1.4),
            verts=v,
        )

    # The dump bucket, tipped, on a short mast above the top deck.
    tube(bm, 2.0, 16.0, (0, 0, 70.0), segments=6)
    made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(12),
                                 radius1=8.0, radius2=11.0, depth=14.0)
    bmesh.ops.rotate(bm, verts=made["verts"], cent=(0, 0, 0), matrix=_roty(0.5))
    bmesh.ops.translate(bm, vec=(0, 0, 82.0), verts=made["verts"])


def rock_fall(bm):
    """An artificial rock outcrop with a sheet of water off it.

    Fake rock, and it should look fake: a few big angular masses at odd rotations rather
    than anything eroded. Real waterpark rockwork is sprayed concrete over a frame and reads
    as chunky and faceted, which is also the cheapest thing to build.

    The FALL is a single flat sheet, not a tube. Falling water has no thickness from the
    side, and a cylinder here would read as a pipe.
    """
    # MORE MASSES, AT SHARPER ANGLES. Four boxes at gentle rotations read as four boxes --
    # what makes sprayed rockwork look like rock is that no two faces agree on a direction,
    # so these are tilted as well as turned, and there are enough of them to overlap.
    masses = (
        (36.0, 32.0, 44.0, -6.0, -4.0, 20.0, 0.30, 0.16),
        (28.0, 26.0, 58.0, 8.0, 6.0, 28.0, -0.45, -0.22),
        (22.0, 24.0, 36.0, -16.0, 12.0, 17.0, 0.80, 0.28),
        (18.0, 20.0, 26.0, 14.0, -14.0, 12.0, -0.20, 0.34),
        (24.0, 18.0, 30.0, -2.0, 16.0, 22.0, 1.10, -0.30),
        (14.0, 16.0, 20.0, -20.0, -12.0, 9.0, 0.55, 0.40),
        (20.0, 22.0, 16.0, 4.0, -2.0, 48.0, -0.70, 0.20),
    )
    for sx, sy, sz, x, y, z, turn, tip in masses:
        box(bm, (sx, sy, sz), (x, y, z), rotation=turn, tilt=tip)

    # The fall, CLEAR OF THE ROCK rather than inside it. The first version put the sheet at
    # the same x as the widest mass, so it was swallowed whole -- a waterfall you cannot see
    # is just an expensive box.
    box(bm, (2.4, 26.0, 52.0), (30.0, 0.0, 26.0))
    box(bm, (14.0, 30.0, 3.0), (28.0, 0.0, 51.0))
    # A wider, shallower spill at the foot where it lands.
    tube(bm, 30.0, 3.0, (28.0, 0.0, 2.0), segments=14)
    tube(bm, 20.0, 2.0, (28.0, 0.0, 4.0), segments=14)


def water_cannon(bm):
    """A swivel cannon on a post, aimed out over the water.

    Small, and the only prop here that POINTS. Everything else stands, spans or lies flat --
    a barrel angled at the sky gives the eye a direction, and a few of these scattered
    around read as a park somebody once played in.
    """
    tube(bm, 3.4, 26.0, (0, 0, 13.0), segments=8)
    tube(bm, 5.0, 5.0, (0, 0, 27.0), segments=8)
    # The yoke, then the barrel through it at an angle.
    for side in (-1.0, 1.0):
        box(bm, (2.0, 2.0, 11.0), (0.0, side * 5.0, 33.0))
    made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(9),
                                 radius1=3.6, radius2=2.4, depth=26.0)
    bmesh.ops.rotate(bm, verts=made["verts"], cent=(0, 0, 0), matrix=_roty(1.05))
    bmesh.ops.translate(bm, vec=(9.0, 0.0, 41.0), verts=made["verts"])


def pirate_ship(bm):
    """A ship marooned in the pool: hull, two masts, yards, a bowsprit.

    MASTS AND YARDS are the read -- a hull alone is a boat-shaped box, and it is the crossed
    verticals and horizontals above it that say ship from any distance. Half-sunk on purpose,
    because a waterpark galleon never floats; it sits on the bottom with its deck at water
    level.
    """
    box(bm, (76.0, 26.0, 20.0), (0, 0, 10.0))
    box(bm, (64.0, 22.0, 8.0), (0, 0, 22.0))
    # A raised stern, which is what stops it reading as a barge.
    box(bm, (22.0, 22.0, 18.0), (-30.0, 0, 30.0))
    # The bow, tapered to a point.
    made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(4),
                                 radius1=13.0, radius2=1.0, depth=24.0)
    bmesh.ops.rotate(bm, verts=made["verts"], cent=(0, 0, 0), matrix=_rotz(math.pi / 4))
    bmesh.ops.rotate(bm, verts=made["verts"], cent=(0, 0, 0), matrix=_roty(math.pi / 2))
    bmesh.ops.translate(bm, vec=(48.0, 0.0, 12.0), verts=made["verts"])

    for x, height in ((14.0, 62.0), (-14.0, 50.0)):
        tube(bm, 2.2, height, (x, 0, 26.0 + height / 2), segments=7)
        for k, (up, span) in enumerate(((0.62, 40.0), (0.86, 26.0))):
            box(bm, (2.0, span, 1.8), (x, 0, 26.0 + height * up))
    # The bowsprit, angled up off the bow.
    made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(6),
                                 radius1=1.8, radius2=1.0, depth=30.0)
    bmesh.ops.rotate(bm, verts=made["verts"], cent=(0, 0, 0), matrix=_roty(1.15))
    bmesh.ops.translate(bm, vec=(60.0, 0.0, 26.0), verts=made["verts"])


def wave_slide(bm):
    """An open body slide that undulates on the way down, rather than spiralling.

    The spiral tube and this cover the two slide shapes a waterpark actually has, and they
    are not interchangeable: one is a helix seen end-on, the other a curve seen side-on. With
    only the helix, every slide on the horizon had the same outline.
    """
    steps = _seg(20)
    span = 108.0
    for i in range(steps + 1):
        f = i / steps
        x = (f - 0.5) * span
        # Three dips on the way down, deepening as the run steepens.
        z = 52.0 - 44.0 * f + math.sin(f * math.pi * 3.0) * 7.0 * (1.0 - f * 0.4)
        run = span / steps * 1.35
        box(bm, (run, 20.0, 3.0), (x, 0.0, z))
        box(bm, (run, 2.6, 10.0), (x, -9.0, z + 5.0))
        box(bm, (run, 2.6, 10.0), (x, 9.0, z + 5.0))
        if i % 5 == 0:
            tube(bm, 2.0, z + 30.0, (x, 0.0, (z - 30.0) / 2), segments=6)


def spray_dome(bm):
    """A sphere fountain on a low pedestal, with spray arms radiating from it.

    The only prop that is basically a SPHERE, which matters more than it sounds: a horizon of
    boxes, tubes and cones has no round mass anywhere in it, and one is enough to break the
    pattern.
    """
    tube(bm, 16.0, 5.0, (0, 0, 2.5), segments=14)
    tube(bm, 8.0, 12.0, (0, 0, 10.0), segments=10)
    dome(bm, 15.0, 15.0, (0, 0, 16.0), segments=14, rings=7)
    dome(bm, 15.0, 6.0, (0, 0, 16.0), segments=14, rings=5, bottom=True)
    for i in range(6):
        angle = math.tau * i / 6
        made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(5),
                                     radius1=1.4, radius2=0.6, depth=20.0)
        v = made["verts"]
        bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_roty(0.95))
        bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_rotz(angle))
        bmesh.ops.translate(
            bm,
            vec=(math.cos(angle) * 13.0, math.sin(angle) * 13.0, 30.0),
            verts=v,
        )


# === The beach ===
#
# The sandbars were bare sand with a few loungers on them. These are what a shore has that a
# poolside does not: things left behind rather than installed, and things that only make
# sense where water meets land.


def sandcastle(bm):
    """A stepped castle with turrets. Unmistakable, and quietly the most liminal thing here.

    Everything else on this horizon was BUILT by somebody with a budget. A sandcastle at
    four hundred studs was built by hand, by someone who then left -- which is the same
    reading the empty colonnade is going for, arrived at from the opposite direction.
    """
    for radius, z, height in ((30.0, 7.0, 14.0), (23.0, 19.0, 12.0), (16.0, 29.0, 10.0)):
        tube(bm, radius, height, (0, 0, z), segments=12)
    for i in range(4):
        angle = math.tau * i / 4 + math.pi / 4
        x, y = math.cos(angle) * 24.0, math.sin(angle) * 24.0
        tube(bm, 6.0, 30.0, (x, y, 22.0), segments=8)
        # A conical cap on each turret: the one detail that makes it a castle not a cake.
        made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(8),
                                     radius1=7.0, radius2=0.5, depth=12.0)
        bmesh.ops.translate(bm, vec=(x, y, 43.0), verts=made["verts"])
    # A moat, dug and abandoned.
    tube(bm, 46.0, 3.0, (0, 0, 1.0), segments=14)


def surfboard(bm):
    """A board planted upright in the sand.

    Tall, flat and rounded at both ends, which is a silhouette nothing else here has -- every
    other vertical is a post, a tower or a trunk. Leaning slightly, because a board pushed
    into sand never stands straight.
    """
    N = 22
    LONG, WIDE, THICK = 46.0, 9.0, 1.6
    bm_verts = []
    for k in range(N):
        f = k / (N - 1)
        # A rounded blade: widest at the middle, tapering to points.
        w = WIDE * math.sin(math.pi * f) ** 0.55
        bm_verts.append((f, w))
    rim = []
    for side in (1.0, -1.0):
        for f, w in (bm_verts if side > 0 else reversed(bm_verts)):
            rim.append(bm.verts.new((side * w, 0.0, f * LONG)))
    for z in (THICK, -THICK):
        pass
    # Extrude by hand: a front face and a back face joined at the rim.
    front = [bm.verts.new((v.co.x, THICK, v.co.z)) for v in rim]
    back = [bm.verts.new((v.co.x, -THICK, v.co.z)) for v in rim]
    n = len(rim)
    for k in range(n):
        bm.faces.new((front[k], front[(k + 1) % n], back[(k + 1) % n], back[k]))
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for v in rim:
        bm.verts.remove(v)
    # A fin, and the lean.
    box(bm, (1.4, 5.0, 7.0), (0.0, -4.0, 5.0))


def beach_hut(bm):
    """A raised hut on stilts with a ladder up one side.

    The lifeguard chair is a seat; this is a ROOM in the air, and the difference at distance
    is a solid box with a pitched roof rather than an open frame. Both belong on a shore and
    they do not read as the same object.
    """
    for sx in (-1.0, 1.0):
        for sy in (-1.0, 1.0):
            tube(bm, 2.2, 30.0, (sx * 13.0, sy * 11.0, 15.0), segments=6)
    box(bm, (32.0, 26.0, 3.0), (0, 0, 31.0))
    box(bm, (28.0, 22.0, 20.0), (0, 0, 42.0))
    # A pitched roof, from a rotated box the way the house does it.
    made = bmesh.ops.create_cube(bm, size=1.0)
    verts = made["verts"]
    bmesh.ops.scale(bm, vec=(22.0, 22.0, 26.0), verts=verts)
    bmesh.ops.rotate(bm, verts=verts, cent=(0, 0, 0), matrix=_roty(math.pi / 4))
    bmesh.ops.scale(bm, vec=(1.0, 1.0, 0.55), verts=verts)
    bmesh.ops.translate(bm, vec=(0, 0, 54.0), verts=verts)
    # The ladder, which is what puts it in the air rather than on the ground.
    for k in range(6):
        box(bm, (10.0, 1.4, 1.4), (18.0, 0.0, 4.0 + k * 5.0))
    for side in (-1.0, 1.0):
        box(bm, (1.6, 1.6, 32.0), (18.0, side * 4.5, 16.0))


def dinghy(bm):
    """A small boat, upturned on the sand.

    Upside down on purpose. A boat the right way up is moored and in use; a hull turned over
    on a beach has been out of the water long enough for somebody to have stored it, and
    that reads immediately from its flat bottom facing the sky.
    """
    # A DOME, ELONGATED, not a tapered cone. A 9-segment cone laid on its side is a faceted
    # wedge and reads as a doorstop; half an ellipsoid with its flat face down is the shape
    # of a hull turned over, which is the entire object.
    hull = dome(bm, 22.0, 11.0, (0, 0, 0), segments=12, rings=5)
    bmesh.ops.scale(bm, vec=(1.0, 0.46, 1.0), verts=hull)
    bmesh.ops.translate(bm, vec=(0, 0, 2.0), verts=hull)

    # The keel, running the length of the upturned bottom, and a flat transom at the stern.
    box(bm, (40.0, 2.6, 2.6), (0, 0, 13.0))
    box(bm, (3.0, 18.0, 9.0), (-21.0, 0, 6.0))

    # Two oars leaning against it.
    for side, turn in ((-1.0, 0.5), (1.0, -0.35)):
        made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(5),
                                     radius1=1.4, radius2=0.9, depth=34.0)
        v = made["verts"]
        bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_roty(1.05))
        bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_rotz(turn))
        bmesh.ops.translate(bm, vec=(-4.0, side * 11.0, 11.0), verts=v)


def beach_flags(bm):
    """A line of pennants strung between two poles.

    Almost nothing but LINE, which is the point: after a dozen solid props the horizon needs
    something that is mostly gaps. The triangles are what stop the rope reading as a wire.
    """
    span = 64.0
    for side in (-1.0, 1.0):
        tube(bm, 1.4, 42.0, (side * span / 2, 0, 21.0), segments=6)
    box(bm, (span, 0.8, 0.8), (0, 0, 40.0))
    for k in range(9):
        f = (k + 0.5) / 9
        x = (f - 0.5) * span
        # A slack line: the pennants hang lower in the middle.
        sag = math.sin(f * math.pi) * 4.0
        made = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=_seg(3),
                                     radius1=4.0, radius2=0.4, depth=9.0)
        v = made["verts"]
        bmesh.ops.rotate(bm, verts=v, cent=(0, 0, 0), matrix=_rotz(math.pi / 2))
        bmesh.ops.translate(bm, vec=(x, 0.0, 40.0 - sag - 5.0), verts=v)


PROPS = {
    "Backdrop_Island": island,
    "Backdrop_Mushroom": mushroom,
    "Backdrop_House": house,
    "Backdrop_Tree": tree,
    "Backdrop_Cloud": cloud,
    "Backdrop_Arch": arch,
    "Backdrop_Statue": statue,
    "Backdrop_Umbrella": umbrella,
    "Backdrop_Slide": slide,
    "Backdrop_WaterTower": water_tower,
    "Backdrop_Hoop": hoop,
    "Backdrop_Keyboard": keyboard,
    "Backdrop_Butter": butter,
    "Backdrop_Microphone": microphone,
    "Backdrop_HoneyDipper": honey_dipper,
    "Backdrop_Soap": soap,
    "Backdrop_SlimeJar": slime_jar,
    "Backdrop_Candle": candle,
    "Backdrop_Foam": foam,
    "Backdrop_SlideTower": slide_tower,
    "Backdrop_Flume": flume,
    "Backdrop_SplashBucket": splash_bucket,
    "Backdrop_FloatRing": float_ring,
    "Backdrop_Cabana": cabana,
    "Backdrop_LifeguardChair": lifeguard_chair,
    "Backdrop_DivingPlatform": diving_platform,
    "Backdrop_PoolLadder": pool_ladder,
    "Backdrop_Lounger": lounger,
    "Backdrop_MushroomFountain": mushroom_fountain,
    "Backdrop_LaneRope": lane_rope,
    "Backdrop_Palm": palm,
    "Backdrop_PlayStructure": play_structure,
    "Backdrop_RockFall": rock_fall,
    "Backdrop_WaterCannon": water_cannon,
    "Backdrop_PirateShip": pirate_ship,
    "Backdrop_WaveSlide": wave_slide,
    "Backdrop_SprayDome": spray_dome,
    "Backdrop_Sandcastle": sandcastle,
    "Backdrop_Surfboard": surfboard,
    "Backdrop_BeachHut": beach_hut,
    "Backdrop_Dinghy": dinghy,
    "Backdrop_BeachFlags": beach_flags,
}


def build(name, make):
    bm = bmesh.new()
    make(bm)
    # One weld pass. The props are unions of overlapping primitives, so the seams carry
    # duplicate vertices that cost memory and shade badly for nothing.
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0005)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # === CHAMFER EVERY HARD EDGE ===
    #
    # The single clearest difference between geometry that looks cheap and geometry that
    # looks expensive, and it is not detail -- it is that a perfectly sharp 90-degree edge
    # does not exist in the physical world and cannot catch a highlight. Every real edge has
    # a radius, however small, and that radius is a bright line along the corner. Without it
    # a box is two flat tones meeting at a hard seam, which is what "untextured Roblox part"
    # looks like.
    #
    # One segment, not more. A single chamfer face produces two edges at about 45 degrees --
    # both above the split threshold below, so the chamfer stays flat-shaded and reads as a
    # crisp bright line rather than a soft blur. Rounding it further would cost triangles to
    # make the highlight weaker.
    #
    # clamp_overlap matters: these props are unions of overlapping primitives at wildly
    # different sizes, from a 36-stud tower stage to a 1.4-radius handrail. Without it the
    # offset that suits the tower turns the handrail inside out.
    sharp_edges = [
        edge
        for edge in bm.edges
        if len(edge.link_faces) == 2 and edge.calc_face_angle(0.0) > math.radians(45.0)
    ]
    if sharp_edges:
        bmesh.ops.bevel(
            bm,
            geom=sharp_edges,
            offset=BEVEL * DETAIL,
            offset_type="OFFSET",
            segments=1,
            profile=0.5,
            affect="EDGES",
            clamp_overlap=True,
        )
        # Chamfering a union of overlapping primitives leaves slivers wherever two shells
        # nearly coincide -- 50 zero-area faces on the flume alone. They render as nothing
        # and validate as broken, so they go here rather than being explained later.
        bmesh.ops.dissolve_degenerate(bm, dist=1e-4, edges=bm.edges)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # SHARP EDGES SPLIT BEFORE SMOOTHING, and skipping this ruined every box-based prop.
    #
    # Everything here was smooth-shaded unconditionally, which is right for a dome and
    # catastrophic for a cube: smoothing averages the normals across a 90-degree corner, so
    # a stick of butter shaded like a pipe and a bar of soap like a rolling pin. They were
    # modelled correctly and lit as though they were something else.
    #
    # Splitting the steep edges first gives each side its own normals, so corners stay
    # crisp while domes and tubes still shade smoothly. Same triangle count -- only the
    # vertices at the seams are duplicated. 40 degrees sits above the ~36 between adjacent
    # faces of a 10-segment tube and well below a box's 90.
    sharp = [
        edge
        for edge in bm.edges
        if len(edge.link_faces) == 2 and edge.calc_face_angle(0.0) > math.radians(40.0)
    ]
    if sharp:
        bmesh.ops.split_edges(bm, edges=sharp)

    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()
    for poly in mesh.polygons:
        poly.use_smooth = True

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def validate(obj, budget):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    problems = []
    degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-7)
    if degenerate:
        problems.append(f"{degenerate} zero-area faces")
    if len(bm.faces) == 0:
        problems.append("no faces at all")
    tris = sum(len(f.verts) - 2 for f in bm.faces)
    if tris > budget:
        problems.append(f"{tris} tris is over the {budget} budget for this detail level")
    bm.free()
    if problems:
        print("    !! " + "; ".join(problems))
        return False, tris
    return True, tris


def export_obj(obj, filename):
    # 20 studs per tile. These are scaled four to eleven times on placement, so the texture
    # ends up far coarser in world terms than on a platform -- which is right for something
    # seen at 900 studs through haze.
    uv_project.box_project(obj.data, 20.0)
    os.makedirs(OUT_DIR, exist_ok=True)
    for other in bpy.data.objects:
        other.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.wm.obj_export(
        filepath=os.path.join(OUT_DIR, filename),
        export_selected_objects=True,
        export_materials=False,
        export_triangulated_mesh=True,
    )


def main():
    global DETAIL

    all_ok = True
    base_tris = {}
    skipped = []
    # Low detail first, so the export order matches the order they are read in game.
    # Budgets raised twice now, both times for the chamfer pass. A bevel roughly doubles a
    # box-heavy prop -- the keyboard has 61 keycaps and every one of them gains twelve
    # chamfer faces -- and that is simply what the difference between a hard edge and a lit
    # one costs. These are still small meshes drawn a handful of times each.
    passes = ((1.0, "", 3200), (DETAIL_MULTIPLIER, "_Detail", 12000))
    for detail, suffix, budget in passes:
        DETAIL = detail
        print(f"  --- detail x{detail:.1f}{' (' + suffix.lstrip('_') + ')' if suffix else ''}, "
              f"budget {budget} tris ---")
        for name, make in sorted(PROPS.items()):
            clear_scene()
            obj = build(name + suffix, make)
            ok, tris = validate(obj, budget)
            all_ok = all_ok and ok

            # NOT EXPORTED IF IT IS THE SAME MESH. Props built entirely from boxes -- the
            # house, the soap, the foam -- have no segment counts to scale, so their detail
            # pass produces an identical mesh. Writing it anyway would cost a manual Studio
            # import per prop for no visible difference, and every skipped file is one less
            # chance to import the wrong thing. BackdropService already falls back to the
            # plain name when the detail name is absent, so this needs no support in game.
            if suffix and base_tris.get(name) == tris:
                skipped.append(name + suffix)
                continue

            if not suffix:
                base_tris[name] = tris
            size = obj.dimensions
            print(f"  {name + suffix}: {tris} tris, "
                  f"{size.x:.0f} x {size.y:.0f} x {size.z:.0f} studs, "
                  f"{'valid' if ok else 'INVALID'}")
            export_obj(obj, name + suffix + ".obj")
    DETAIL = 1.0

    if skipped:
        print("")
        print(f"  {len(skipped)} detail mesh(es) identical to the base and not written: "
              + ", ".join(skipped))

    print("")
    print("  Import into ReplicatedStorage/Assets/Backdrop (OBJ, no bones needed).")
    print("  BackdropService prefers *_Detail near the player, plain further out, and")
    print("  falls back to primitives for anything missing. Neither set is required.")
    print("")
    print("Done." if all_ok else "!! a prop failed validation -- DO NOT import.")


if __name__ == "__main__":
    main()
