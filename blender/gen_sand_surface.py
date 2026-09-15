"""
Kinetic sand surface: a RIGGED skin per slab size.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_sand_surface.py

This was a rigid OBJ and that was the wrong call. A rigid surface cannot deform, so the
only thing a footfall could do was stamp a separate part onto it -- and a part laid on an
unbroken plane reads as a sticker no matter how well it is modelled. It is the same
objection this project already recorded against drawing marks with a decal, and it
applies just as much to a mesh sitting at surface level.

So the sand surface is skinned. THE SURFACE ITSELF DENTS: bones under your foot are
driven down, bones in a ring just outside are driven UP, and that ring is the berm --
material displaced out of the hollow, which is the thing that makes a print read as
granular rather than as a dish pressed into rubber.

BONE PITCH IS THE WHOLE DESIGN CONSTRAINT. A footprint is about 1.2 studs across, so a
per-cell rig like honey's (one bone per ~3.2-stud sub-region) cannot resolve one at all
-- that is why sand was left meshless for so long. At 0.9 studs it resolves comfortably,
and sand slabs are small (16x4 and 16x6.18), so the count lands near 100. The wax shell
already carries 123.

One mesh per slab size, so the relief never repeats: a tiled noise field is highly
legible, the eye finds the same clump arrangement over and over and reads a lattice.
"""

import bmesh
import contextlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import uv_project
import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

OUT_DIR = r"C:\Users\Arsenii\Downloads\asmr-platformer-implementation_1\RobloxProject\meshes"

# The layer the skin fills: ChunkBuilder's TILE_THICKNESS, between the slab's top face
# and the walkable plane.
TILE_LAYER = 0.9

# Resting relief, peak to trough.
#
# 0.075 was far too timid -- a surface that flat is a plane with a suggestion of texture,
# and it is why nine meshes made no visible difference. Kinetic sand at rest is not a
# worked flat bed: it is a heap of CLUMPS, rounded lumps an inch or two proud of each
# other with creases between them. Against a 16-stud platform, 0.4 is about the same
# proportion the reference photographs show on a tray.
AMPLITUDE = 1.25

# How much of that stands ABOVE the walkable plane, as a fraction. The rest hangs below.
#
# Not zero, which is what it was. With everything below the plane the character walks on
# the peaks and visibly floats over every valley; with a little above it, the feet sink
# into the crests instead -- which is what the reference photographs show and what sand
# should do. It is capped low because the collider is flat at the plane, so this is the
# distance a foot appears to sink, not a step to climb.
RISE = 0.18

# How far in from a face's border its relief is faded out. FIXED IN STUDS.
#
# This was AMPLITUDE * 3, which quietly coupled the two: on a 4-deep slab that put the
# margin at 1.2 against a half-depth of 2, so the relief only reached full height within
# 40% of the half-width and the whole surface came out damped. It only has to be wide
# enough to close the seam between faces.
FADE_MARGIN = 0.45

# Sampling step. Finer than the rigid version was, because the mesh now has to hold the
# SHAPE of a dent rather than only catch light: at 0.3 a 1.2-stud footprint spanned four
# samples and came out an octagon, the same failure the bubble wrap pockets had.
RES = 0.18

# The walls and the underside get a COARSER step. Only the top has to hold the shape of a
# footprint; the rest just has to look like clumped sand, and at 0.18 the four 4.9-deep
# walls alone were three quarters of the block's triangles.
WALL_RES = 0.45

# Plan corner radius, to match the butter block's 1.0 and the bubble wrap's 0.85. Sand
# can round freely where those two could not: its slab is HIDDEN (sand is not an OVERLAY
# any more), so there are no square concrete corners left to poke out through a rounded
# outline. Rounding only ever makes the mesh smaller than its slab, which the import
# check is happy with.
CORNER = 1.0

# Bone lattice. See the module docstring: this is what decides whether a footprint is
# even representable.
BONE_PITCH = 0.9
# How far down the wall follows the surface, in studs. Below this the block is anchored,
# so a platform can lose its top without its base changing shape.
WALL_FOLLOW = 2.2
# Weight falloff radius, as a multiple of the pitch. Above 1 so neighbouring bones
# overlap and a dent melts into the surface instead of stepping at every bone boundary.
INFLUENCE = 1.7
MAX_INFLUENCES = 4


def _hash01(ix, iy, seed):
    h = (ix * 374761393 + iy * 668265263 + seed * 2654435761) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


def value_noise(x, y, seed):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    sx = fx * fx * (3.0 - 2.0 * fx)
    sy = fy * fy * (3.0 - 2.0 * fy)
    a = _hash01(ix, iy, seed)
    b = _hash01(ix + 1, iy, seed)
    c = _hash01(ix, iy + 1, seed)
    d = _hash01(ix + 1, iy + 1, seed)
    return (a * (1 - sx) + b * sx) * (1 - sy) + (c * (1 - sx) + d * sx) * sy


def billow(x, y, seed):
    """Value noise folded about its midpoint: ROUNDED PEAKS, CREASED VALLEYS.

    This is the shape of clumped material and plain noise is not. Smooth noise gives
    rolling dunes -- every peak and every trough equally soft -- which is what sand looks
    like after wind, not after being squeezed. Folding it puts a crease wherever the
    field crosses its midpoint, so the surface becomes rounded lumps meeting in sharp
    seams: exactly how kinetic sand sits once it has been handled.
    """
    return 1.0 - abs(2.0 * value_noise(x, y, seed) - 1.0)


def relief(x, y, seed):
    """Three octaves of billow, in 0..1. The coarsest carries the mounds you read the
    surface by; the finest only breaks up their silhouette, since the Sand material's
    own texture handles anything below this scale."""
    # FREQUENCIES DROPPED, not just the amplitude raised. Hills have to read from across
    # the level, and at distance fine detail averages itself into a flat tone -- only
    # features several studs wide survive. The coarsest octave now runs about a mound
    # every three studs instead of every one and a half, and carries more of the weight.
    return (
        billow(x * 0.32, y * 0.32, seed) * 0.62
        + billow(x * 0.9, y * 0.9, seed + 7) * 0.25
        + billow(x * 2.4, y * 2.4, seed + 19) * 0.13
    )


_SLAB_DEPTH = None


def _slab_depth():
    """ChunkBuilder's SLAB_THICKNESS, read rather than typed: the wrap has to reach the
    bottom of the slab it encloses, and a hardcoded copy would leave a stripe of bare
    concrete the moment that constant moved."""
    global _SLAB_DEPTH
    if _SLAB_DEPTH is None:
        import chunk_layout

        _, _, constants = chunk_layout.layout_all()
        _SLAB_DEPTH = constants["SLAB_THICKNESS"]
    return _SLAB_DEPTH


# ---------------------------------------------------------------- sculpted forms

# A SAND TURTLE IS SCULPTED INTO THE BED, NOT CUT OUT OF IT.
#
# The obvious build is the one soap uses: give the platform a turtle-shaped outline and
# let the plan do the work. That is wrong here for two separate reasons.
#
# Collision is the first. A granular platform IS its cubes, so a soap heart's outline is
# also its floor. A skinned platform is decoration over a rectangular slab -- ChunkBuilder
# sets CanCollide false on every mesh -- so cutting a turtle out of the plan would leave
# the player walking on thin air in the four bays between the flippers.
#
# The second is that for sand the slab is INVISIBLE (`slab.Transparency = 1`, since sand
# is not an OVERLAY). This mesh is not a decal on a platform; it IS the platform, all of
# it. A turtle-shaped plan would be a turtle-shaped island with nothing around it, which
# is a different level design, not a different texture.
#
# So the bed stays a full rectangle and the turtle is a sculpture standing on it -- which
# is what a sand turtle is anyway. Nobody cuts a turtle-shaped hole in a beach.
#
# HEIGHT IS THE WHOLE READ, and the first four versions of this got it wrong by being
# timid. The shell stood 0.31 studs proud of the bed, and at that scale a turtle is a
# stain: the silhouette was right, the anatomy was right, the grooves were right, and it
# still looked like a lump in a tray, because a reference sand turtle is an OBJECT --
# something with a dome you could put your hand over. The shell now stands 1.40, and
# almost every other constant here changed only to make room for that.

# Margin in studs kept clear on every side. It has to clear FADE_MARGIN so the edge fade
# does not eat the tail -- but it is also the run the bed has to climb back to plane
# level in, so it cannot be generous either. 1.3 is both.
TURTLE_MARGIN = 1.1

# Half-extents of the design below, in turtle units, used to scale it onto a slab.
TURTLE_HALF_X, TURTLE_HALF_Y = 1.40, 1.60
# The design is not symmetric front to back -- the head reaches further than the tail --
# so it is re-centred by this much before scaling.
TURTLE_SHIFT_Y = 0.10

# (cx, cy, ax, ay, rotation, top). +y is the direction of travel, so the head faces the
# way you are going. Every part is an ellipse, the body is their union, and `top` is the
# field value that part reaches at its peak.
#
# Index 0 is the carapace and the code depends on that: the shell gets the outline groove
# and the scute pattern.
#
# EVERYTHING IS CHUNKY, and that is the slope budget talking rather than a style choice.
# A smoothstep profile of rise h over half-width w peaks at 1.5 * h / w, and past about
# 45 degrees the surface stair-steps at TURTLE_RES. Now that the sculpture is four times
# taller, every part needs to be correspondingly wider to stay under that -- a part does
# not get to be tall AND narrow. Which is lucky, because a moulded beach turtle has
# exactly these proportions: a fat dome, a blunt head and four stubby paddles. The thin,
# elegant, anatomically-correct flippers of version two were both unbuildable and wrong.
TURTLE_PARTS = (
    (0.00, 0.00, 0.95, 1.00, 0.00, 0.992),    # carapace
    (0.00, 1.10, 0.50, 0.50, 0.00, 0.860),    # head, blunt and set close to the shell
    (0.00, -1.14, 0.26, 0.28, 0.00, 0.710),   # tail
    (0.88, 0.42, 0.55, 0.38, 0.50, 0.800),    # front paddles, swept forward and out
    (-0.88, 0.42, 0.55, 0.38, -0.50, 0.800),
    (0.80, -0.62, 0.45, 0.33, -0.60, 0.760),  # rear paddles, smaller and tucked back
    (-0.80, -0.62, 0.45, 0.33, 0.60, 0.760),
)

# Field values are in the 0..1 space `relief` returns. drop = (field - (1 - RISE)) *
# AMPLITUDE, so at amplitude 3.2 and RISE 0.18 the field maps to studs about the walkable
# plane as z = (field - 0.82) * 3.2:
#   slab border   0.820 ->  0.00   forced there by edge_fade; the reference for everything
#   bed, middle   0.586 -> -0.75   the sand the turtle is sitting on
#   shell top     0.992 -> +0.55   the player sinks half a stud into the dome
#   head top      0.860 -> +0.13
#   front paddle  0.800 -> -0.06
#   rear paddle   0.760 -> -0.19
#   tail          0.710 -> -0.35
#   outline        0.531 -> -0.93
# So the dome stands 1.40 studs above the bed and 1.75 above the groove at its rim, and
# the limbs sit BETWEEN the two -- which is the arrangement that makes it read as one
# animal rather than as a mound with bumps round it.
#
# WHY NOT TALLER STILL: the ceiling is not arbitrary. Anything above z = 0 is geometry
# the player walks through, because the collider is a flat plane at the walkable height
# and nothing about a mesh changes that. Half a stud reads as standing ankle-deep in the
# dome, which is what sand should do. Two studs would read as wading through it. That is
# what validate()'s AMPLITUDE * RISE limit is protecting, and it is why the bed went DOWN
# to make room rather than the turtle going further up.
TURTLE_AMPLITUDE = 3.2
TURTLE_BED_EDGE = 0.820
TURTLE_BED_MID = 0.586
TURTLE_BOWL_START = 0.42   # fraction of the half-span where the bowl begins to fall

# One groove, around the carapace, cutting across the limb roots exactly as a real
# shell's edge overlaps the legs beneath it. Wide enough to be several samples across,
# and comfortably narrower than the shell it is drawn around.
#
# There is deliberately NO groove around the limbs. A channel drawn around a part has to
# be narrower than the part, and at version three's sizes the flippers were 0.6 studs
# across against a 1.2-stud channel -- it met itself in the middle and dug them away
# entirely, which is what turned them into dark pits. They are chunky enough now that a
# groove would fit, but they also stand half a stud proud of the bed, so it would be
# buying with triangles something the height already gives away.
TURTLE_SHELL_GROOVE_D = 0.109
TURTLE_SHELL_GROOVE_W = 1.60
TURTLE_SCUTE_D = 0.090
TURTLE_OUTLINE_D = 0.055
TURTLE_OUTLINE_W = 1.30

# Peak-to-trough clumping in the bed, in field units. AMPLITUDE multiplies it, so 0.13
# here is +/- 0.21 studs on the surface. The bed's job is to be the DULL half of a
# contrast; at the plain surface's spread it competes with the sculpture until the
# silhouette stops being the thing you see first.
TURTLE_BED_NOISE = 0.13
# How much clumping survives on the sculpture. Not zero: a perfectly smooth shell reads
# as plastic, and the whole point is that it is still made of sand.
TURTLE_SHELL_NOISE = 0.10

# Smoothing radius for the union, in field units. Paddles grow out of a shell; they are
# not laid on top of one, and a plain max() creases visibly where they meet.
TURTLE_BLEND = 0.02

# THE SLAB IS SQUARE, AND THAT IS WHAT MADE THE TURTLE BIG.
#
# It was 14 x 12, and the sculpture came out filling barely half of it -- a figurine on a
# tray rather than the subject. The scale is min(usable_x / HALF_X, usable_y / HALF_Y),
# and since the design is longer than it is wide, DEPTH was always the binding term: 4.7
# usable studs against a 1.60 half-extent. Widening to 16 x 16 lifts the scale from 2.94
# studs per unit to 4.19, and the turtle goes from 59% of the platform's width to 73%.
#
# It also made every slope GENTLER rather than steeper, which is why the sampling could
# be coarsened to pay for the extra area: heights are fixed in studs, so scaling the
# design up by 1.43 widens every bank by the same factor and drops each one by 30%.
#
# 0.28 rather than 0.24 because 16 x 16 at 0.24 is about 23,800 triangles, over Roblox's
# 21,000 per MeshPart. This lands near 18,000.
TURTLE_RES = 0.28
# Likewise the rig: 14 x 12 at the standard 0.9 is 224 bones for one platform. 1.15 keeps
# it near the 123 the wax shell already carries, and still resolves a footprint, which is
# the only thing the pitch has to be fine enough for.
TURTLE_BONE_PITCH = 1.15


def _smoothstep(edge0, edge1, x):
    t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


def _smax(a, b, k):
    """Polynomial smooth maximum. Rounds the join instead of creasing it."""
    h = min(1.0, max(0.0, 0.5 + 0.5 * (a - b) / k))
    return b * (1.0 - h) + a * h + k * h * (1.0 - h)


def _part_k(px, py, part):
    """Normalised ellipse radius: exactly 1 on the boundary."""
    cx, cy, ax, ay, rot, _top = part
    dx, dy = px - cx, py - cy
    if rot:
        c, s = math.cos(rot), math.sin(rot)
        dx, dy = dx * c + dy * s, -dx * s + dy * c
    return math.hypot(dx / ax, dy / ay)


def turtle_sculpt(size_x, size_z):
    """A closure that rewrites the top sheet's height field into a turtle.

    Returns values in the same 0..1 space `relief` produces, so it drops straight into
    the existing drop calculation with no other change.
    """
    usable_x = max(0.5, size_x / 2.0 - TURTLE_MARGIN)
    usable_y = max(0.5, size_z / 2.0 - TURTLE_MARGIN)
    # ONE scale for both axes. Scaling them separately would stretch the turtle to the
    # slab's aspect ratio, and a turtle stretched 2:1 is a lizard.
    scale = min(usable_x / TURTLE_HALF_X, usable_y / TURTLE_HALF_Y)
    half_x, half_z = size_x / 2.0, size_z / 2.0
    shell_thin = min(TURTLE_PARTS[0][2], TURTLE_PARTS[0][3])

    def sculpt(x, y, noise, seed):
        ux = x / scale
        uy = y / scale - TURTLE_SHIFT_Y

        # The bowl. Distance measured as a SUPERELLIPSE so the hollow follows the slab
        # rather than sitting as a circle inside a rectangle.
        #
        # It was max(|x|/hx, |y|/hz), the square metric, which does follow the slab -- and
        # has a CREASE along both diagonals, because that is where the two terms swap
        # which one is larger. The bowl is the largest feature on the platform, so its
        # crease ran corner to corner as four visible seams across the sand. A p-norm is
        # the same shape with the corner rounded off and no discontinuity anywhere.
        r = (abs(x / half_x) ** 6.0 + abs(y / half_z) ** 6.0) ** (1.0 / 6.0)
        bed = TURTLE_BED_MID + (TURTLE_BED_EDGE - TURTLE_BED_MID) * _smoothstep(
            TURTLE_BOWL_START, 1.0, r
        )

        lift = 0.0
        limb_lift = 0.0
        shell_k = _part_k(ux, uy, TURTLE_PARTS[0])
        for index, part in enumerate(TURTLE_PARTS):
            k = shell_k if index == 0 else _part_k(ux, uy, part)
            if k < 1.0:
                # THE PROFILE MUST HAVE ZERO SLOPE AT ITS RIM.
                #
                # It was (1 - k*k) ** 0.42, chosen so the dome would hold its height and
                # then fall away sharply enough to give the shell an edge. Any exponent
                # below 0.5 has an INFINITE derivative at k = 1: every part was a
                # vertical cliff at its own rim by construction, and a vertical wall
                # sampled on a fixed grid is a staircase. A smoothstep is flat at BOTH
                # ends, so the sculpture meets the bed tangentially everywhere. It is
                # also the truer surface, since sand will not stand in a vertical wall.
                #
                # HOW MUCH OF THE RADIUS EACH PART HOLDS BEFORE IT FALLS. This is what
                # decides whether the turtle looks MOULDED or melted, and version five
                # got it wrong by being frugal with a budget it was not spending.
                #
                # Falling over the whole radius is the gentlest bank available, so it was
                # the safe choice while the slope budget was tight. But a part that starts
                # descending at its centre has no edge anywhere -- it is a soft mound --
                # and six soft mounds in a heap read as a melted lump however correct
                # their outlines are. Squaring the slab freed the budget: it dropped the
                # steep-pair count from 3.3% to 0.6%, which is room to hold each form
                # nearly flat and then bank it hard, the way a moulded plastic turtle is
                # shaped. Measured back at ~41 degrees, still inside the limit.
                #
                # The carapace holds the most, because the player STANDS on it and a
                # dome that curves from its own centre is the one part of the platform
                # that looks like it should slide you off.
                plateau = 0.45 if index == 0 else 0.35
                here = (part[5] - bed) * _smoothstep(1.0, plateau, k)
                lift = _smax(lift, here, TURTLE_BLEND)
                if index > 0:
                    limb_lift = max(limb_lift, here)

        field = bed + lift

        # THERE IS NO GROOVE ROUND THE CARAPACE ANY MORE, and removing it is what
        # finally stopped this mesh tearing.
        #
        # It was dug when the shell stood 0.31 studs proud of the bed and needed an
        # artificial edge, because at that height it had no real one. Every attempt to
        # keep it cost something: cut straight through the limbs it put a 1.4-stud drop
        # inside half a stud of run; faded at the limbs it moved the cliff into the fade
        # itself; widened it started eating the shell. At 1.30 studs the dome's own bank
        # IS the edge -- a 41-degree wall a stud and a half tall, which reads far harder
        # than any channel did, and needs no special case where a paddle crosses it.
        #
        # Worth keeping as a rule: a groove is what you draw when a form is too shallow
        # to cast its own shadow. Making the form taller is the better fix, and it is
        # cheaper -- height costs nothing, and every groove costs a slope budget.

        # A shallow line all the way round the animal, separating the limbs from the
        # sand.
        #
        # There was none of this until the limbs got chunky, and for a good reason: a
        # channel drawn around a part must be narrower than the part, and the early
        # flippers were 0.6 studs across against a 1.2-stud channel -- it met itself in
        # the middle and dug them away. The paddles are 2.6 to 3.3 studs wide now, so it
        # fits. Deliberately shallow: it is there to draw an edge from directly above,
        # where a height difference alone flattens out, and a deep one would re-open
        # every tearing problem this mesh has already had.
        union_sd = min(
            (_part_k(ux, uy, part) - 1.0) * min(part[2], part[3]) for part in TURTLE_PARTS
        ) * scale
        if 0.0 < union_sd < TURTLE_OUTLINE_W:
            field -= TURTLE_OUTLINE_D * math.sin(math.pi * union_sd / TURTLE_OUTLINE_W)

        # Scutes: two concentric grooves, marking off a central plate and a marginal
        # band.
        #
        # THERE ARE NO RADIAL GROOVES, and their absence is a sampling result rather than
        # a style choice. A real carapace has six plates around the middle one, and six
        # spokes drawn on this shell come out about 0.4 studs wide -- against the sample
        # step, which side of the spoke a sample lands on is very nearly arbitrary, and
        # the surface tears into slivers. Widening them to a legal ~1 stud each spends
        # most of the circumference on groove and leaves no plates between. A feature must
        # be several samples across, and on a curved band the width that counts is ARC
        # LENGTH, not the parameter you happened to write it in.
        if shell_k < 0.96:
            inner = math.exp(-(((shell_k - 0.45) / 0.13) ** 2))
            margin = math.exp(-(((shell_k - 0.82) / 0.13) ** 2))
            field -= TURTLE_SCUTE_D * max(inner, margin)

        # Texture contrast, the cue that survives longest at distance: the sculpture is
        # smooth where the bed around it is clumped. Driven by how far the surface has
        # been lifted, so it needs no second distance field to go wrong.
        #
        # THE FINEST OCTAVE IS DROPPED, and `noise` -- the standard three-octave relief --
        # is deliberately ignored. Its top octave runs a feature every 0.42 studs, which
        # against this variant's sample step is not texture but JITTER: neighbouring
        # samples get uncorrelated values, and that lands on top of whatever slope the
        # sculpture already had. The Sand material's own texture and the normal map carry
        # everything below this scale anyway, which is the same argument `relief` already
        # makes for its own frequency choices.
        clumps = (
            billow(x * 0.32, y * 0.32, seed) * 0.70
            + billow(x * 0.9, y * 0.9, seed + 7) * 0.30
        )
        on_body = _smoothstep(0.01, 0.06, lift)
        gain = 1.0 - on_body * (1.0 - TURTLE_SHELL_NOISE)
        field += (clumps - 0.5) * TURTLE_BED_NOISE * gain

        return min(1.0, max(0.0, field))

    return sculpt


SCULPT = None

# What each form needs. Keyed by the `form` string in ChunkBuilder's segment table.
FORMS = {
    "turtle": {
        "sculpt": turtle_sculpt,
        "overrides": {
            "AMPLITUDE": TURTLE_AMPLITUDE,
            "RES": TURTLE_RES,
            "BONE_PITCH": TURTLE_BONE_PITCH,
        },
    },
}


@contextlib.contextmanager
def variant(**overrides):
    """Temporarily rebind module globals.

    Every downstream step reads these as globals: the armature reads BONE_PITCH, the
    validator checks AMPLITUDE * RISE, the grid reads RES. Threading a parameter through
    all of them would leave the validator checking the PLAIN surface's limits against a
    variant's geometry -- exactly the kind of check that passes without looking.
    """
    g = globals()
    previous = {k: g[k] for k in overrides}
    g.update(overrides)
    try:
        yield
    finally:
        g.update(previous)


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.armatures):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def edge_fade(u, v, half_u, half_v, margin):
    """1 in the middle of a face, easing to 0 at its border.

    THIS IS WHAT MAKES THE BLOCK WATERTIGHT. Six faces each carrying their own relief
    would meet at six different heights along every shared rim and leave the block full
    of splits. Fading every face's relief to nothing at its own border means all six
    arrive at the nominal box there and join exactly, with no need to stitch anything.
    """
    du = min(1.0, max(0.0, (half_u - abs(u)) / margin))
    dv = min(1.0, max(0.0, (half_v - abs(v)) / margin))
    fade = min(du, dv)
    return fade * fade * (3.0 - 2.0 * fade)


def plan_radius(size_x, size_z):
    return min(CORNER, size_x * 0.5 * 0.8, size_z * 0.5 * 0.8)


def _plan_sd(px, py, hx, hz, r):
    """Signed distance to the rounded rectangle: negative inside."""
    qx = abs(px) - (hx - r)
    qy = abs(py) - (hz - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def clamp_to_plan(x, y, size_x, size_z):
    """Map a grid point onto the rounded plan by SCALING it toward the centre.

    The obvious version projects each outside point onto the nearest bit of the arc, the
    way the butter block does. It fails here: projection is not monotonic, so near a
    corner diagonal two neighbouring grid points can swap places, and the quad between
    them turns inside out. The validator caught exactly four such faces per mesh -- one
    per corner -- which Roblox would have culled into four holes.

    Scaling along the ray from the centre cannot reorder anything, because every point on
    a ray is multiplied by the same factor and that factor depends only on the DIRECTION.
    So the footprint rounds and the grid stays a grid.
    """
    hx, hz = size_x / 2.0, size_z / 2.0
    r = plan_radius(size_x, size_z)
    m = max(abs(x) / hx, abs(y) / hz)
    if m < 1e-9:
        return x, y
    # The point where this ray leaves the SQUARE, then how far along it the rounded
    # outline sits. Bisection rather than algebra: the rounded-rect boundary along an
    # arbitrary ray has three cases and this has none.
    bx, by = x / m, y / m
    lo, hi = 0.0, 1.0
    for _ in range(24):
        mid = (lo + hi) * 0.5
        if _plan_sd(bx * mid, by * mid, hx, hz, r) < 0.0:
            lo = mid
        else:
            hi = mid
    k = (lo + hi) * 0.5
    return x * k, y * k


def build_surface(size_x, size_z, name, seed):
    """A block of sand with a ROUNDED PLAN: relief on the top, the wall and the underside.

    Built as a top grid, a wall extruded from that grid's own rim, and a bottom grid --
    rather than six independent faces. The rim is shared by construction, so the rounded
    outline cannot disagree between the top and the wall, which it would if each face
    drew its own.
    """
    depth = TILE_LAYER + _slab_depth()
    margin = FADE_MARGIN
    nx = max(2, int(round(size_x / RES)) + 1)
    ny = max(2, int(round(size_z / RES)) + 1)

    verts, faces, static = [], [], []
    wall_follow = {}

    def sheet(z_base, sign, lift_it):
        """One clamped grid of relief. `sign` is +1 for the top (relief hangs down from
        the walkable plane) and -1 for the underside (it hangs up into the block)."""
        first = len(verts)
        for j in range(ny):
            for i in range(nx):
                x = (i / (nx - 1) - 0.5) * size_x
                y = (j / (ny - 1) - 0.5) * size_z
                x, y = clamp_to_plan(x, y, size_x, size_z)
                fade = edge_fade(x, y, size_x / 2.0, size_z / 2.0, margin)
                lift = RISE if lift_it else 0.0
                field = relief(x, y, seed)
                if SCULPT is not None and lift_it:
                    field = SCULPT(x, y, field, seed)
                drop = (field - (1.0 - lift)) * AMPLITUDE * fade
                index = len(verts)
                verts.append((x, y, z_base + sign * drop))
                # NOTHING IN A SHEET IS PINNED, top or bottom.
                #
                # The underside used to be entirely static, and that is the flat plane
                # that stopped a hole being see-through: the top of a collapsing cell
                # dropped away and the sheet 5 studs below it stayed, so you were looking
                # into a pocket rather than through the block. A cell giving way has to
                # take its whole COLUMN -- top, wall and floor -- and since the weights
                # fall off by XY distance from the bone, only the column NEAR that cell
                # goes. The rest of the block's base is untouched.
        for j in range(ny - 1):
            for i in range(nx - 1):
                p = first + j * nx + i
                a, b, c, d = p, p + 1, p + nx + 1, p + nx
                if SCULPT is None or not lift_it:
                    # Plain relief is gentle enough that its quads are near planar, and
                    # leaving them as quads keeps the nine unsculpted meshes byte-for-
                    # byte what is already imported in Studio.
                    faces.append((a, b, c, d) if sign > 0 else (a, d, c, b))
                    continue
                # A SCULPTED SHEET IS TRIANGULATED BY HAND, ALONG THE FLATTER DIAGONAL.
                #
                # This is what was actually tearing the turtle, and it survived four
                # rounds of blaming the height field because it is not in the height
                # field. A quad whose four corners are not coplanar has no single
                # surface, so it gets split into two triangles somewhere downstream --
                # and along a ridge that runs diagonally to the grid, consecutive quads
                # fold OPPOSITE WAYS. That alternation is the row of identical little
                # spikes: not a slope artefact at all, which is why widening grooves,
                # softening profiles and dropping octaves each helped a bit and none of
                # them fixed it.
                #
                # Splitting along whichever diagonal has the smaller height difference
                # picks the fold that follows the ridge instead of cutting across it. It
                # costs nothing -- a quad was already going to be two triangles.
                if abs(verts[a][2] - verts[c][2]) <= abs(verts[b][2] - verts[d][2]):
                    split = ((a, b, c), (a, c, d))
                else:
                    split = ((a, b, d), (b, c, d))
                for tri in split:
                    faces.append(tri if sign > 0 else tuple(reversed(tri)))
        return first

    top_first = sheet(0.0, 1, True)
    top_faces = len(faces)
    bottom_first = sheet(-depth, -1, False)

    def rim(first):
        """The grid's perimeter, walked once round."""
        ring = [first + i for i in range(nx - 1)]
        ring += [first + j * nx + (nx - 1) for j in range(ny - 1)]
        ring += [first + (ny - 1) * nx + i for i in range(nx - 1, 0, -1)]
        ring += [first + j * nx for j in range(ny - 1, 0, -1)]
        return ring

    # The wall, extruded between the two rims. Its relief is faded to nothing at both
    # ends so it meets the sheets exactly, the same rule that closes every other seam.
    top_ring, bottom_ring = rim(top_first), rim(bottom_first)
    levels = max(2, int(round(depth / WALL_RES)))
    rings = [top_ring]
    for level in range(1, levels):
        f = level / levels
        ring = []
        for k, index in enumerate(top_ring):
            x, y, _ = verts[index]
            inward = math.hypot(x, y) or 1.0
            fade = math.sin(math.pi * f)
            push = (relief(x * 0.8, -depth * f, seed + 977) - 1.0) * AMPLITUDE * 0.6 * fade
            here = len(verts)
            ring.append(here)
            # THE UPPER WALL MOVES WITH THE SURFACE ABOVE IT.
            #
            # Every wall vertex used to be pinned to the Root, so when a cell collapsed
            # the top dropped out and the wall stayed standing round it like the rim of
            # a box -- the sand fell and its own edge did not. Weighting the top band to
            # the same bones lets the edge go with it.
            #
            # NO DEPTH FADE any more. It used to taper to nothing over the top 2.2
            # studs so the base of the block could never move -- but the wall's bottom
            # ring IS the underside sheet's rim, so fading the wall and freeing the
            # underside are contradictory instructions about the same vertices. The
            # column moves as one piece instead, which is also what falling sand does.
            verts.append((x + x / inward * push, y + y / inward * push, -depth * f))
        rings.append(ring)
    rings.append(bottom_ring)

    for r in range(len(rings) - 1):
        a, b = rings[r], rings[r + 1]
        n = len(a)
        for k in range(n):
            nk = (k + 1) % n
            faces.append((a[k], a[nk], b[nk], b[k]))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # RECALC PICKS A DIRECTION; IT DOES NOT PICK THE RIGHT ONE.
    #
    # It makes the winding CONSISTENT and then orients the result outward from the
    # volume -- but which way that comes out depends on the topology it was handed, and
    # triangulating the top sheet was enough to flip it: every surface face came back
    # pointing down and the whole block was inside out. This project has been caught by
    # the same operator once before, on the sea sheet, and the lesson is the same one.
    # The top faces are the ones with a known answer, so ask them and flip if they
    # disagree, rather than trusting the operator to have guessed.
    bm.normal_update()
    up = sum(1 for f in bm.faces[:top_faces] if f.normal.z > 0.0)
    if up * 2 < top_faces:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    for poly in mesh.polygons:
        poly.use_smooth = True

    return obj, set(static), wall_follow, top_faces


def build_armature(size_x, size_z, rig_name):
    arm_data = bpy.data.armatures.new(rig_name)
    arm_obj = bpy.data.objects.new(rig_name, arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    root = arm_data.edit_bones.new("Root")
    root.head = (0.0, 0.0, 0.0)
    root.tail = (0.0, 0.0, 1.0)

    # Straddling the origin, so the lattice is symmetric on a slab of any size and two
    # slabs of different widths still agree about where a bone sits.
    cols = max(1, int(size_x / BONE_PITCH))
    rows = max(1, int(size_z / BONE_PITCH))
    centres = {}
    for c in range(cols):
        for r in range(rows):
            cx = -size_x / 2.0 + (c + 0.5) * (size_x / cols)
            cy = -size_z / 2.0 + (r + 0.5) * (size_z / rows)
            bone_name = f"Grain_{c + 1}_{r + 1}"
            bone = arm_data.edit_bones.new(bone_name)
            bone.head = (cx, cy, 0.0)
            bone.tail = (cx, cy, 0.5)
            bone.parent = root
            bone.use_connect = False
            centres[bone_name] = (cx, cy)

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj, centres


def assign_weights(obj, arm_obj, static_indices, wall_follow, centres):
    groups = {name: obj.vertex_groups.new(name=name) for name in centres}
    root_group = obj.vertex_groups.new(name="Root")
    radius = BONE_PITCH * INFLUENCE
    mesh = obj.data
    uncovered = 0

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
        # A wall vertex only PARTLY follows: the rest of it belongs to the Root, which
        # is what keeps the bottom of the block still while its top edge falls away.
        share = wall_follow.get(index, 1.0)
        for weight, name in scored:
            groups[name].add([index], weight / total * share, "REPLACE")
        if share < 1.0:
            root_group.add([index], 1.0 - share, "REPLACE")

    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = arm_obj
    obj.parent = arm_obj
    return uncovered


def validate(obj, size_x, size_z, top_faces, uncovered):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    problems = []
    # NO open-edge test. The block is six relief grids meeting at their rims rather than
    # one welded solid, so every face border is legitimately a boundary -- they land in
    # the same place because `edge_fade` takes each face's relief to zero there, which is
    # what the seam check below actually measures.
    if sum(1 for f in bm.faces if f.calc_area() < 1e-7):
        problems.append("zero-area faces")
    down = sum(1 for f in bm.faces[:top_faces] if f.normal.z <= 0)
    if down:
        problems.append(f"{down} of {top_faces} surface faces point DOWN")
    zs = [v.co.z for v in obj.data.vertices]
    # A CREST MAY STAND PROUD OF THE WALKABLE PLANE, by RISE, so a foot sinks into it.
    # More than that and it stops being a foot sinking in and becomes a step to climb
    # that the flat collider knows nothing about.
    if max(zs) > AMPLITUDE * RISE + 1e-4:
        problems.append(f"relief rises {max(zs):.3f} above the walkable plane")
    if uncovered:
        problems.append(f"{uncovered} vertices have no bone in range (raise INFLUENCE)")
    # The seams: no vertex may sit outside the nominal box, or the faces have parted
    # company and the block has a split in it.
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    if max(xs) - min(xs) > size_x + 1e-4 or max(ys) - min(ys) > size_z + 1e-4:
        problems.append("relief pushes outside the slab footprint")
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
    # 3.0 studs per tile, sized for grain, which has to be fine. The scale is in studs rather than repeats so
    # every platform size shows the same physical detail instead of stretching it to fit.
    uv_project.box_project(mesh_obj.data, 3.0)

    os.makedirs(OUT_DIR, exist_ok=True)
    for obj in bpy.data.objects:
        obj.select_set(False)
    mesh_obj.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.export_scene.fbx(
        filepath=os.path.join(OUT_DIR, filename),
        use_selection=True,
        global_scale=0.01,
        add_leaf_bones=False,
        bake_anim=False,
        axis_forward="-Z",
        axis_up="Y",
        object_types={"ARMATURE", "MESH"},
        mesh_smooth_type="EDGE",
    )


def mesh_name(size_x, size_z, form=None):
    stem = "Sand_Surface" if form is None else "Sand_" + form.capitalize()
    return "{}_{:g}x{:g}".format(stem, size_x, size_z).replace(".", "_")


def slab_sizes():
    import chunk_layout

    layouts, _, _ = chunk_layout.layout_all()
    sizes = set()
    for boxes in layouts.values():
        for box in boxes:
            if box.material == "KineticSand" and box.form is None:
                sizes.add((round(box.sx, 2), round(box.sz, 2)))
    return sorted(sizes)


def form_slabs():
    """Shaped sand slabs, as (form, size_x, size_z).

    Read out of the layout rather than typed here, so a form named in ChunkBuilder
    that nobody generated shows up as a missing mesh at BUILD time rather than as a
    platform that quietly came out plain at play time.
    """
    import chunk_layout

    layouts, _, _ = chunk_layout.layout_all()
    found = set()
    for boxes in layouts.values():
        for box in boxes:
            if box.material == "KineticSand" and box.form is not None:
                found.add((box.form, round(box.sx, 2), round(box.sz, 2)))
    return sorted(found)


def build_one(size_x, size_z, form, entries):
    """One mesh, exported, with its ChunkBuilder spec line appended to `entries`."""
    clear_scene()
    name = mesh_name(size_x, size_z, form)
    # Shaped variants get their own seed offset. Without it a turtle and a plain sheet
    # of the same size would share a clump field, and the bed around the sculpture would
    # be pixel-identical to the ordinary platform two chunks earlier.
    seed = int(size_x * 977 + size_z * 131) + (0 if form is None else 5081)
    obj, static, wall_follow, top_faces = build_surface(size_x, size_z, name, seed)
    arm, centres = build_armature(size_x, size_z, name + "_Rig")
    uncovered = assign_weights(obj, arm, static, wall_follow, centres)
    ok = validate(obj, size_x, size_z, top_faces, uncovered)

    tris = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
    zs = [v.co.z for v in obj.data.vertices]
    low, high = min(zs), max(zs)
    print(f"  {name}: {len(centres)} bones, {tris} tris, {'valid' if ok else 'INVALID'}")
    export_fbx(obj, arm, name + ".fbx")
    shape = "" if form is None else f', form = "{form}"'
    entries.append(
        f"\t\t{{ sizeX = {size_x:g}, sizeZ = {size_z:g}, "
        f"meshHeight = {high - low:.2f}, surfaceOffset = {-(low + high) / 2.0:.2f}, "
        f'mesh = "{name}"{shape} }},'
    )
    return ok


def main():
    sizes = slab_sizes()
    forms = form_slabs()
    print(f"  {len(sizes)} plain kinetic sand slab sizes, {len(forms)} shaped\n")

    entries, all_ok = [], True
    for size_x, size_z in sizes:
        all_ok = build_one(size_x, size_z, None, entries) and all_ok

    for form, size_x, size_z in forms:
        recipe = FORMS.get(form)
        if recipe is None:
            # Loud, and it fails the run. A shaped slab with no recipe would otherwise
            # just not get a mesh, and ChunkBuilder would fall back to the plain sheet
            # without anyone finding out until they looked at the platform in game.
            print(f"  !! ChunkBuilder asks for sand form '{form}' and this generator")
            print("     has no recipe for it. Add one to FORMS.")
            all_ok = False
            continue
        with variant(SCULPT=recipe["sculpt"](size_x, size_z), **recipe["overrides"]):
            all_ok = build_one(size_x, size_z, form, entries) and all_ok

    print("")
    print("  ChunkBuilder SKINNED_PLATFORMS entry:")
    print("\tKineticSand = {")
    for entry in entries:
        print(entry)
    print("\t},")
    print("")
    print(f"  BONE_PITCH = {BONE_PITCH}  (DeformationRenderer matches bones by position)")
    print("")
    print("Done." if all_ok else "!! a mesh failed validation -- DO NOT import.")


if __name__ == "__main__":
    main()
