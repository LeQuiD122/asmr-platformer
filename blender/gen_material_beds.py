"""
Foam, clay, charcoal and cloud platforms. Blender 5.2 -> FBX -> Roblox skinned MeshParts.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_material_beds.py

Four materials, one script, because all four are the SAME OBJECT with a different surface
field: a skinned heightfield platform on the bone lattice every rigged material here uses.
The topology lives in gen_lambs_ear.build_surface and is not repeated -- getting it to come
out manifold, correctly wound and free of stair-stepping cost several rounds, and none of
that is per-material. What is per-material is the twenty lines of field below.

=== The fields, and why each is combined the way it is ===

FOAM is a plane PIERCED by pits, and the pits are combined with a MINIMUM. That is the
whole trick: take the deepest pit at each point and overlapping pits merge into one larger
cavity, leaving the thin walls between them standing. Open-cell foam is exactly that -- a
solid with holes eaten through it -- and building it the other way round, as raised lumps,
gives closed-cell foam, which looks like packing material rather than memory foam.

CLAY is a smooth slab with THROWING RINGS, and the rings wobble. Perfect concentric circles
read as machined, which is the opposite of what a thrown surface is; the radius is
perturbed by two out-of-phase harmonics of the angle so every ring is a slightly different
irregular loop. Thumb dents on top of that, because a real piece has been handled.

CHARCOAL is FACETED, and it is the only field here with hard edges on purpose. Charcoal
fractures conchoidally: it does not crumble to grain like sand, it snaps into angular
pieces with sharp arrises. So the field is nearest-seed -- flat facets at random heights,
each with its own tilt -- blended over a band narrow enough to stay crisp and wide enough
that the edge lands where the facet is rather than on the nearest grid line.

CLOUD is metaballs with a very soft maximum. Everything else here wants its parts
distinguishable; a cloud wants the opposite, one puffy mass where you cannot say where a
lobe begins. SMOOTH_K is nearly three times the leaf bed's for that reason.
"""

import math
import os
import random
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import uv_project
import gen_lambs_ear as BED
import gen_butter_skinned as BUTTER

OUT_DIR = BUTTER.OUT_DIR
SPECS_ONLY = False

# ONE SIZE EACH. Every one of these chunks is a single straight platform, so a second rig
# would be two more imports for a shape nothing uses. 16 x 12 is the shape P6_JelloSoda
# already connects at, so the level generator needs no new case.
SIZE = (16.0, 12.0)

THICK = BUTTER.THICK
smoothstep = BUTTER.smoothstep


def inside(edge, softness, x):
    """1 well within `edge`, 0 past it, smooth across `softness`.

    THIS EXISTS BECAUSE THE OBVIOUS SPELLING IS WRONG. BUTTER.smoothstep(a, b, x) guards a
    degenerate range with `if b <= a: return 0.0 if x < a else 1.0` -- so the natural way to
    write a falloff, `smoothstep(edge, edge - soft, x)`, does not return a falling curve. It
    returns a step, and specifically it returns ZERO everywhere inside the shape, which
    produces a field that is flat and an export that is valid and empty.

    That has now cost three surfaces: the lamb's ear leaf profile, the salt crystals and the
    button caps. Every one of them looked right in the source. Anything fading OUT goes
    through here now instead.
    """
    return 1.0 - smoothstep(max(0.0, edge - softness), edge, x)


def soft_max(best, second, k):
    """Quadratic smooth maximum of the top two contributions.

    NOT softplus, which is what this was and which floats. `best + k*log1p(exp(-d/k))`
    exceeds the true maximum by k*ln(2) when the two are equal -- 0.33 studs at cloud's k --
    so wherever three lobes met at the same height it raised a little spike above all of
    them. Those came out in the render as small starburst cusps sitting proud of an
    otherwise smooth cloud, and they are not a lighting artefact, they are real geometry.

    The quadratic form has COMPACT SUPPORT: past a difference of k it returns the maximum
    exactly, and at zero difference it exceeds it by only k/4. So distant lobes are
    untouched and coincident ones barely lift.
    """
    if second <= -1e9:
        return best
    d = abs(best - second)
    if d >= k:
        return max(best, second)
    return max(best, second) + (k - d) ** 2 / (4.0 * k)


def scatter(size_x, size_z, spacing, margin, seed, jitter=0.7):
    """Jittered grid of (x, y, angle, roll) tuples covering the plan plus a margin.

    Jittered rather than uniform random, for the reason the leaf bed found: pure random
    scatter clumps and leaves bald patches, and a bald patch reads as a hole in the
    platform. Jittered rather than a plain grid because a grid that survives its own jitter
    is the single thing this project has rejected most often.
    """
    rng = random.Random(seed)
    x0, x1 = -size_x / 2 - margin, size_x / 2 + margin
    y0, y1 = -size_z / 2 - margin, size_z / 2 + margin
    cols = max(1, int(round((x1 - x0) / spacing)))
    rows = max(1, int(round((y1 - y0) / spacing)))
    step_x, step_y = (x1 - x0) / cols, (y1 - y0) / rows
    out = []
    for i in range(cols + 1):
        for j in range(rows + 1):
            out.append((
                x0 + i * step_x + rng.uniform(-1, 1) * step_x * jitter,
                y0 + j * step_y + rng.uniform(-1, 1) * step_y * jitter,
                rng.uniform(0.0, math.tau),
                rng.random(),
            ))
    return out


# ============================================================ foam
FOAM_PORE_R = 0.42      # about three and a half samples of radius at RES 0.12
FOAM_PORE_DEPTH = 0.34
# TIGHT. At 0.78 the pores were islands in a flat plain, which is a crumpet: open-cell
# foam is mostly hole, and the solid part is the thin walls left between them.
FOAM_SPACING = 0.62
FOAM_SWELL = 0.06       # the block is not perfectly flat before it is holed


def foam_field(size_x, size_z):
    pores = scatter(size_x, size_z, FOAM_SPACING, FOAM_PORE_R, 20260901)

    def field(x, y):
        # MINIMUM, not maximum: the deepest pit wins, so overlapping pores open into one
        # cavity instead of cancelling each other out.
        deepest = 0.0
        for cx, cy, _angle, roll in pores:
            dx, dy = x - cx, y - cy
            radius = FOAM_PORE_R * (0.65 + 0.7 * roll)
            d2 = dx * dx + dy * dy
            if d2 >= radius * radius:
                continue
            r = math.sqrt(d2) / radius
            pit = -FOAM_PORE_DEPTH * (0.6 + 0.8 * roll) * (1.0 - smoothstep(0.0, 1.0, r))
            if pit < deepest:
                deepest = pit
        swell = FOAM_SWELL * math.sin(x * 0.7 + 1.1) * math.cos(y * 0.55 - 0.4)
        return deepest + swell

    return field


# ============================================================ clay
#
# NOT CONCENTRIC RINGS. The first version put throwing rings around the slab centre and it
# came out as a TREE STUMP -- a bullseye with wood grain, identical on every copy of the
# chunk, with a starburst where the wobble harmonics collapse at radius zero. Rings belong
# on a thrown pot, and this is a slab.
#
# What a worked slab actually carries is FINGER DRAGS: a few long swept furrows in two or
# three directions, and some thumb dents. It is also mostly SMOOTH, and deliberately so --
# this is the material whose whole point is that it receives and keeps footprints, so the
# base surface has to stay quiet enough for a print to be the loudest thing on it.
CLAY_DRAG_DEPTH = 0.075
CLAY_DRAG_W = 0.38       # groove half width; three samples
CLAY_DRAG_CURVE = 0.030  # how much a drag bows as it crosses
CLAY_DENT_DEPTH = 0.11
CLAY_DENT_R = 0.62


def clay_field(size_x, size_z):
    rng = random.Random(20260902)
    # Few and far between, both of them. A worked surface has a handful of places the
    # potter touched, not a field of them; scattering densely turns the slab into foam.
    drags = []
    for _ in range(7):
        angle = rng.uniform(0.0, math.pi)
        drags.append((
            rng.uniform(-size_x / 2, size_x / 2),
            rng.uniform(-size_z / 2, size_z / 2),
            math.cos(angle), math.sin(angle),
            rng.uniform(-1.0, 1.0) * CLAY_DRAG_CURVE,
            rng.uniform(3.5, 9.0),          # half length of the stroke
            rng.uniform(0.7, 1.3),          # depth scale
        ))
    dents = scatter(size_x, size_z, 4.6, 0.0, 20260912, jitter=0.55)

    def field(x, y):
        pressed = 0.0
        for ox, oy, tx, ty, curve, half, scale in drags:
            dx, dy = x - ox, y - oy
            along = dx * tx + dy * ty
            if abs(along) >= half:
                continue
            # The stroke BOWS: a finger dragged across clay does not travel in a straight
            # line, and a set of perfectly straight parallel grooves reads as machining.
            across = abs(-dx * ty + dy * tx - curve * along * along)
            if across >= CLAY_DRAG_W:
                continue
            # Faded at both ends, so a drag starts and stops rather than running off the
            # slab -- an edge-to-edge groove reads as a saw cut.
            fade = 1.0 - smoothstep(0.0, 1.0, abs(along) / half)
            pressed -= (CLAY_DRAG_DEPTH * scale * fade
                        * (1.0 - smoothstep(0.0, 1.0, across / CLAY_DRAG_W)))

        for cx, cy, _angle, roll in dents:
            dx, dy = x - cx, y - cy
            radius = CLAY_DENT_R * (0.7 + 0.6 * roll)
            d2 = dx * dx + dy * dy
            if d2 >= radius * radius:
                continue
            r = math.sqrt(d2) / radius
            pressed -= CLAY_DENT_DEPTH * (1.0 - smoothstep(0.0, 1.0, r))

        # A slow swell, because a hand-flattened slab is never level.
        swell = 0.045 * math.sin(x * 0.42 + 0.7) * math.cos(y * 0.38 - 1.1)
        return pressed + swell


    return field


# ============================================================ charcoal
CHAR_FACET = 1.15        # seed spacing: the size of one broken piece
CHAR_HEIGHT = 0.24       # how far facets sit apart in height
CHAR_TILT = 0.10         # each facet leans its own way, so none are parallel
# One and a half samples at RES 0.12, not under one. At 0.11 the facet edges quantised to
# the lattice and came out as a sawtooth running along every arris -- the same failure the
# leaf margins had, and for the same reason: an edge narrower than the grid does not render
# sharp, it renders stepped.
CHAR_ARRIS = 0.18


def charcoal_field(size_x, size_z):
    seeds = scatter(size_x, size_z, CHAR_FACET, CHAR_FACET * 1.5, 20260903, jitter=0.75)

    def plane(seed, x, y):
        cx, cy, angle, roll = seed
        # Height of this facet's own plane at (x, y): a level plus a lean.
        return ((roll - 0.5) * 2.0 * CHAR_HEIGHT
                + ((x - cx) * math.cos(angle) + (y - cy) * math.sin(angle)) * CHAR_TILT)

    def field(x, y):
        best_d, best, second_d, second = 1e9, None, 1e9, None
        for seed in seeds:
            dx, dy = x - seed[0], y - seed[1]
            d = dx * dx + dy * dy
            if d < best_d:
                best_d, best, second_d, second = d, seed, best_d, best
            elif d < second_d:
                second_d, second = d, seed
        if best is None:
            return 0.0
        h = plane(best, x, y)
        if second is None:
            return h
        # A HARD nearest-seed edge quantises to the lattice. Blending over a narrow band
        # either side of the bisector puts the arris where the facets actually meet while
        # keeping it sharp -- charcoal's edges are meant to be sharp, unlike a leaf margin.
        gap = math.sqrt(second_d) - math.sqrt(best_d)
        if gap >= CHAR_ARRIS:
            return h
        t = smoothstep(0.0, 1.0, 0.5 + 0.5 * gap / CHAR_ARRIS)
        return plane(second, x, y) + (h - plane(second, x, y)) * t

    return field


# ============================================================ cloud
CLOUD_R = 1.35
CLOUD_H = 1.40
CLOUD_SPACING = 1.25
# Still well above the leaf bed's 0.18 -- a cloud wants its lobes inseparable where
# every other bed here wants its parts distinguishable -- but lower than the 0.48 it
# started at, because at 0.48 the puffs melted into bedsheet folds. Cumulus does have
# visible cauliflower lobes; what it does not have is countable spheres.
CLOUD_K = 0.38


def cloud_field(size_x, size_z):
    blobs = scatter(size_x, size_z, CLOUD_SPACING, CLOUD_R, 20260904)

    def field(x, y):
        best, second = -1e9, -1e9
        for cx, cy, _angle, roll in blobs:
            dx, dy = x - cx, y - cy
            radius = CLOUD_R * (0.7 + 0.6 * roll)
            d2 = dx * dx + dy * dy
            if d2 >= radius * radius:
                continue
            r = math.sqrt(d2) / radius
            h = CLOUD_H * (0.55 + 0.75 * roll) * (1.0 - smoothstep(0.0, 1.0, r))
            if h > best:
                best, second = h, best
            elif h > second:
                second = h
        if best <= -1e9:
            return 0.0
        return soft_max(best, second, CLOUD_K)

    return field


# ============================================================ lego
#
# THE ONE PLACE A GRID IS THE POINT. Everything else in this project goes out of its way to
# destroy any lattice that survives its jitter, because a repeating grid is the giveaway of
# generated content. Lego is the exception: the stud pitch IS the material, and jittering it
# would read as a manufacturing defect rather than as variety.
#
# What breaks the monotony instead is the BRICK SEAMS, laid in a running bond so the joints
# of one course fall over the middle of the course below. That is how real brickwork and
# real lego both look, and it gives the surface a second, offset rhythm over the first.
# SCALED UP FROM REAL LEGO, and it had to be. The real ratio is a 4.8mm stud on an 8mm
# pitch, which at 1.60 studs put only about eight samples across a stud -- so the circle
# quantised and every stud came out visibly octagonal. Keeping the RATIO honest at 0.30 and
# enlarging the whole brick fixes it without making the proportions wrong: at 2.10 a stud
# spans thirteen samples and reads round. Bigger brick also reads better at platform range,
# where a 16 stud slab now carries about eight studs across instead of ten.
LEGO_PITCH = 2.10        # stud centres
LEGO_STUD_R = 0.63       # 0.30 of the pitch, which is the real proportion
LEGO_STUD_H = 0.38
LEGO_CHAMFER = 0.16      # rounded lip on the stud, well over a sample
LEGO_BRICK = (4, 2)      # studs per brick, long axis by short
LEGO_SEAM_D = 0.075
LEGO_SEAM_W = 0.13


def lego_field(size_x, size_z):
    brick_x = LEGO_BRICK[0] * LEGO_PITCH
    brick_y = LEGO_BRICK[1] * LEGO_PITCH

    def field(x, y):
        # The stud nearest this point, on a fixed lattice anchored at the mesh origin so
        # two slabs of different sizes still agree about where a stud goes.
        sx = round(x / LEGO_PITCH) * LEGO_PITCH
        sy = round(y / LEGO_PITCH) * LEGO_PITCH
        r = math.hypot(x - sx, y - sy)
        # Flat on top with a rounded lip, not a dome: a lego stud is a cylinder, and the
        # chamfer band is what keeps its edge from quantising to the lattice.
        stud = LEGO_STUD_H * (1.0 - smoothstep(LEGO_STUD_R - LEGO_CHAMFER, LEGO_STUD_R, r))

        # RUNNING BOND: every other course is offset by half a brick.
        course = math.floor((y + brick_y / 2) / brick_y)
        offset = (brick_x / 2) if course % 2 else 0.0
        along = abs(((x + offset + brick_x / 2) % brick_x) - brick_x / 2)
        across = abs(((y + brick_y / 2) % brick_y) - brick_y / 2)
        seam = 0.0
        if along < LEGO_SEAM_W:
            seam -= LEGO_SEAM_D * (1.0 - smoothstep(0.0, 1.0, along / LEGO_SEAM_W))
        if across < LEGO_SEAM_W:
            seam -= LEGO_SEAM_D * (1.0 - smoothstep(0.0, 1.0, across / LEGO_SEAM_W))
        return stud + seam

    return field


# ============================================================ light switches
#
# Faceplates with a rocker in each, and the rocker is ASYMMETRIC AT REST -- one end proud,
# the other sunk -- so a switch reads as OFF before anything has touched it. That asymmetry
# is doing the work a per-switch hinge would otherwise have to: the bone lattice here
# translates, it does not rotate, so the flip is sold by the paddle already looking like a
# thing that flips plus the light coming on. A symmetrical paddle would read as a button,
# which is the keyboard, which is the material this has to not be.
SW_PITCH = 3.40          # faceplate centres; close to the 3.2 stud bone cell
SW_PLATE = 1.42          # faceplate half width
SW_PLATE_H = 0.13
SW_BEVEL = 0.20
SW_ROCKER = (0.92, 0.62) # paddle half length (across the throw) by half width
SW_HIGH = 0.34           # the proud end
SW_LOW = 0.11            # the sunk end
SW_GAP = 0.16            # groove between paddle and plate


def lightswitch_field(size_x, size_z):
    def field(x, y):
        px = round(x / SW_PITCH) * SW_PITCH
        py = round(y / SW_PITCH) * SW_PITCH
        dx, dy = x - px, y - py

        # Faceplate: a rounded square standing off the wall, bevelled at its rim.
        plate_d = max(abs(dx), abs(dy))
        if plate_d >= SW_PLATE:
            return 0.0
        h = SW_PLATE_H * (1.0 - smoothstep(SW_PLATE - SW_BEVEL, SW_PLATE, plate_d))

        # The paddle sits in the plate with a groove all round it.
        if abs(dy) >= SW_ROCKER[1] + SW_GAP or abs(dx) >= SW_ROCKER[0] + SW_GAP:
            return h
        if abs(dy) >= SW_ROCKER[1] or abs(dx) >= SW_ROCKER[0]:
            return h - 0.05   # the groove

        # THE THROW. A linear ramp from the sunk end to the proud one, with the ends
        # rounded off so the paddle has a lip rather than a knife edge.
        along = (dx / SW_ROCKER[0] + 1.0) * 0.5      # 0 at the sunk end, 1 at the proud
        face = SW_LOW + (SW_HIGH - SW_LOW) * along
        lip = 1.0 - smoothstep(SW_ROCKER[1] - 0.14, SW_ROCKER[1], abs(dy))
        return h + face * lip

    return field


# ============================================================ chocolate
#
# A MOULDED BAR, and deliberately NOT a fractured shell over a soft body.
#
# That was the first plan -- reuse the wax shell and butter body the way ice does -- and it
# is wrong twice. Mechanically it makes chocolate a third copy of butter, which is the exact
# collision the material has to avoid. Visually it would put the same Voronoi crack pattern
# on a third surface, and a generated pattern seen three times stops being a pattern and
# starts being a signature.
#
# What chocolate actually looks like is a GRID OF SEGMENTS with deep valleys between them:
# the snap lines are moulded in, not fractured, and they are straight and regular because a
# bar comes out of a tray. The segments dome very slightly, because the mould fills from the
# middle and the surface pulls in as it sets.
CHOC_SEG = (2.70, 2.05)  # segment pitch, long axis by short
CHOC_GROOVE = 0.30       # half width of the valley between segments
CHOC_DEPTH = 0.30        # how deep those valleys run
CHOC_DOME = 0.055        # the slight crown on each segment
CHOC_BEVEL = 0.34        # the draft angle on a segment's side, in studs


def chocolate_field(size_x, size_z):
    def field(x, y):
        # Distance to the nearest segment boundary, on each axis independently.
        du = abs(((x + CHOC_SEG[0] / 2) % CHOC_SEG[0]) - CHOC_SEG[0] / 2)
        dv = abs(((y + CHOC_SEG[1] / 2) % CHOC_SEG[1]) - CHOC_SEG[1] / 2)
        edge = min(CHOC_SEG[0] / 2 - du, CHOC_SEG[1] / 2 - dv)

        # A moulded bar has DRAFT: the sides of each segment slope so it releases from the
        # tray. Straight walls would be both wrong and a one-sample cliff.
        rise = CHOC_DEPTH * smoothstep(CHOC_GROOVE, CHOC_GROOVE + CHOC_BEVEL, edge)
        # The crown, strongest at the middle of a segment and gone at its rim.
        centre = min(1.0, edge / (min(CHOC_SEG) / 2))
        return rise + CHOC_DOME * smoothstep(0.0, 1.0, centre)

    return field


# LEGO IS NOT HERE ANY MORE. Its field is kept below because the PBR maps are still used --
# the bricks are Parts and take their texture through a MaterialVariant named LegoABS -- but
# no mesh is generated, because lego has no mesh. It is built entirely out of parts, one
# full-depth brick per cell, the way soap is built out of cubes.
#
# A generator that still exported an unused FBX would be a trap: somebody would import it,
# nothing would change, and working out why would cost an afternoon.
# ============================================================ salt
#
# CUBES, and they have to be actual cubes. Salt crystallises in the cubic system -- that is
# the one fact everybody half-knows about it -- so a rounded granular field would read as
# sugar or as sand, both of which are already in this game. Flat tops, sharp arrises, and
# every crystal at its own random yaw so the field never lines up into a grid.
# PACKED LOOSER THAN THEY ARE WIDE. The first pass had a 0.62 pitch against crystals 0.92
# across, so every one overlapped two neighbours and the field fused into rubble -- angular
# rubble, but rubble, with not a cube visible in it. A crystal has to be able to finish
# before the next one starts or there is no crystal to see.
SALT_PITCH = 1.20
SALT_SIZE = 0.55         # half width of one crystal
SALT_H = 0.34
# Resolvable, unlike the 0.05 it started at. At RES 0.12 that was under half a sample, so
# every arris quantised into a sawtooth -- which is most of what made the first render look
# like broken stone rather than cut cubes.
SALT_BEVEL = 0.16


def salt_field(size_x, size_z):
    crystals = scatter(size_x, size_z, SALT_PITCH, SALT_SIZE * 2, 20260921, jitter=0.55)

    def field(x, y):
        tallest = 0.0
        for cx, cy, angle, roll in crystals:
            dx, dy = x - cx, y - cy
            if dx * dx + dy * dy > (SALT_SIZE * 1.5) ** 2:
                continue
            # Rotated into the crystal's own frame, then a SQUARE test rather than a round
            # one -- this is the whole difference between a salt grain and a sand grain.
            ca, sa = math.cos(angle), math.sin(angle)
            u = abs(dx * ca + dy * sa)
            v = abs(-dx * sa + dy * ca)
            half = SALT_SIZE * (0.55 + 0.75 * roll)
            edge = max(u, v)
            if edge >= half:
                continue
            top = SALT_H * (0.5 + 1.0 * roll)
            # Flat on top with a tiny bevel at the rim, so the arris reads without the
            # vertical wall quantising to the sample grid.
            h = top * inside(half, SALT_BEVEL, edge)
            tallest = max(tallest, h)
        return tallest

    return field


# ============================================================ molten lava with obsidian
#
# TWO SURFACES AT ONCE, and the gap between them is the material. Obsidian plates float on
# the melt with channels of liquid rock running between them, so the plates sit HIGH and
# flat while the channels sit low and smooth -- and the depth of that channel is what will
# make the glow read once the emissive texture is on it.
#
# The plate field is nearest-seed like charcoal's, because both are fracture patterns. What
# separates them is the profile: charcoal's facets tilt and meet at arrises, while these are
# level rafts with a rounded shoulder, like something floating.
LAVA_PLATE = 2.4         # seed spacing: one raft of crust
LAVA_RISE = 0.34         # how far a plate stands above the melt
LAVA_CHANNEL = 0.42      # half width of the liquid running between plates
LAVA_SHOULDER = 0.30     # the rounded edge of a raft


def lava_field(size_x, size_z):
    seeds = scatter(size_x, size_z, LAVA_PLATE, LAVA_PLATE, 20260922, jitter=0.7)

    def field(x, y):
        best_d, second_d = 1e9, 1e9
        for cx, cy, _angle, _roll in seeds:
            dx, dy = x - cx, y - cy
            d = dx * dx + dy * dy
            if d < best_d:
                best_d, second_d = d, best_d
            elif d < second_d:
                second_d = d
        if best_d > 1e8:
            return 0.0
        # Distance to the bisector between this plate and its nearest neighbour, which is
        # where the channel runs.
        gap = (math.sqrt(second_d) - math.sqrt(best_d)) * 0.5
        # Low in the channel, rising over the shoulder onto the raft.
        return LAVA_RISE * smoothstep(LAVA_CHANNEL, LAVA_CHANNEL + LAVA_SHOULDER, gap)

    return field


# ============================================================ non-newtonian fluid
#
# A liquid caught in the act of being solid.
#
# Oobleck has no texture of its own worth speaking of -- it is a smooth pale slurry -- so
# what makes it read is that the surface is FROZEN MID-RIPPLE. Concentric waves spreading
# from a few points, sharp-crested rather than sinusoidal, because a shear-thickening fluid
# under impact throws stiff peaks instead of smooth swells. Standing still it would settle
# flat; this is the surface a moment after something hit it, which is the only interesting
# moment the material has.
OOB_RINGS = 5
OOB_WAVE = 1.15          # studs between crests
OOB_AMP = 0.085
OOB_DECAY = 5.5          # how fast a ring dies out from its centre


def oobleck_field(size_x, size_z):
    rng = random.Random(20260923)
    sources = [
        (rng.uniform(-size_x / 2, size_x / 2), rng.uniform(-size_z / 2, size_z / 2),
         rng.uniform(0.7, 1.3), rng.uniform(0, math.tau))
        for _ in range(OOB_RINGS)
    ]

    def field(x, y):
        total = 0.0
        for cx, cy, strength, phase in sources:
            distance = math.hypot(x - cx, y - cy)
            fade = math.exp(-distance / OOB_DECAY)
            if fade < 0.02:
                continue
            wave = math.sin(math.tau * distance / OOB_WAVE + phase)
            # SHARPENED. Raising the crest and flattening the trough turns a sine into
            # something with a peak on it, which is what a stiffened fluid actually throws.
            crest = wave * abs(wave) ** 0.55
            total += OOB_AMP * strength * fade * crest
        return total

    return field


# ============================================================ clicky buttons
#
# THE PLATE ONLY. The caps are rigid Parts that ChunkBuilder drops into these wells, and the
# mesh carries nothing but the housings they sit in.
#
# The first version modelled the caps into the heightfield and it was wrong twice over. They
# came out as domes on a fixed 3.9 pitch that did not divide the platform, so the row at each
# edge was sliced in half -- and a half a button is not a button, it is a bump. Worse, a cap
# baked into a skinned mesh can only be "pressed" by moving a bone, which drags everything
# within a cell and a quarter along with it: the whole plate flexes instead of one button
# going down. That is the lego rubber problem exactly, and a button is the one thing in this
# game that MUST move rigidly, because a spring under a cap is the entire idea.
#
# ONE WELL PER BONE CELL, so a button is always whole and always alone in its cell. The pitch
# is read from compute_grid rather than chosen, which is what guarantees both: a well is
# centred on its cell and sized to fit inside it with room to spare, so no well can ever
# reach an edge or a neighbour.
BTN_WELL = 0.42          # well radius as a fraction of the cell's short side
BTN_WELL_D = 0.16        # how deep the housing is cut
BTN_RIM = 0.10           # of the cell: the rounded lip around the well


def button_field(size_x, size_z, div=1):
    """Wells on a div x div sub-lattice inside every cell.

    `div` is the density knob and the only thing separating one keypad from another. At 1 it
    is one big button per cell, which is what the plain plate has always been; at 2 the plate
    carries four to a cell, so four times the buttons at half the pitch.

    IT SUBDIVIDES THE CELL rather than laying an independent pitch over the plate, and that
    is not a stylistic choice. Cells are the unit everything else here is built on -- bones,
    tiles, colliders, floor drops -- so a lattice that divides a cell evenly divides all of
    them evenly too, and the pattern comes out symmetric about the plate's centre for free.
    An independent pitch lands wherever it lands and leaves half a button at two edges,
    which is exactly what it was asked not to do.
    """
    cols, rows, cell_x, cell_z = BUTTER.compute_grid(size_x, size_z)
    pitch_x, pitch_z = cell_x / div, cell_z / div
    short = min(pitch_x, pitch_z)
    well_r = short * BTN_WELL
    rim = short * BTN_RIM

    def field(x, y):
        # Nearest SUB-LATTICE point. This is the line that makes every button whole: snapping
        # to a point that exists for every position means no well is ever clipped by an edge.
        col = min(cols * div - 1, max(0, math.floor((x + size_x / 2) / pitch_x)))
        row = min(rows * div - 1, max(0, math.floor((y + size_z / 2) / pitch_z)))
        cx = -size_x / 2 + (col + 0.5) * pitch_x
        cy = -size_z / 2 + (row + 0.5) * pitch_z

        r = math.hypot(x - cx, y - cy)
        if r >= well_r + rim:
            return 0.0
        # A dish with a rounded lip: flat at the bottom where the cap sits, curving up to
        # the plate around it.
        return -BTN_WELL_D * inside(well_r + rim, rim, r)

    return field


# ============================================================ snow
#
# Soft drifts, and a CRUST. Fresh snow is smooth and rounded; snow that has thawed once and
# refrozen carries a thin brittle skin over the top, and that skin is what tells you this
# chunk is melting rather than freshly fallen. So: broad low mounds, with a fine crazing on
# them that a normal map alone could not place at this scale.
SNOW_DRIFT = 3.6         # spacing of the mounds
SNOW_RISE = 0.42
SNOW_CRUST = 1.05        # spacing of the crust plates
SNOW_CRUST_D = 0.045     # and how deep their joins run


def snow_field(size_x, size_z):
    drifts = scatter(size_x, size_z, SNOW_DRIFT, SNOW_DRIFT, 20260924)
    plates = scatter(size_x, size_z, SNOW_CRUST, SNOW_CRUST, 20260934, jitter=0.8)

    def field(x, y):
        # The drifts: a soft maximum, so they merge into one bank rather than reading as
        # separate heaps.
        best, second = -1e9, -1e9
        for cx, cy, _angle, roll in drifts:
            dx, dy = x - cx, y - cy
            radius = SNOW_DRIFT * (0.55 + 0.5 * roll)
            d2 = dx * dx + dy * dy
            if d2 >= radius * radius:
                continue
            h = SNOW_RISE * (0.6 + 0.7 * roll) * (1.0 - smoothstep(0.0, 1.0, math.sqrt(d2) / radius))
            if h > best:
                best, second = h, best
            elif h > second:
                second = h
        drift = 0.0 if best <= -1e9 else soft_max(best, second, 0.5)

        # The crust: nearest-seed joins, cut shallow. Only the LINES matter, so the plates
        # themselves stay level and all the shape is in where they meet.
        b, s = 1e9, 1e9
        for cx, cy, _angle, _roll in plates:
            dx, dy = x - cx, y - cy
            d = dx * dx + dy * dy
            if d < b:
                b, s = d, b
            elif d < s:
                s = d
        join = (math.sqrt(s) - math.sqrt(b)) * 0.5 if s < 1e8 else 1.0
        crust = -SNOW_CRUST_D * (1.0 - smoothstep(0.0, 0.16, join))
        return drift + crust

    return field


RECIPES = {
    "Foam": (foam_field, 5.0),
    "Clay": (clay_field, 6.0),
    "Charcoal": (charcoal_field, 4.0),
    "Cloud": (cloud_field, 7.0),
    "LightSwitch": (lightswitch_field, 3.4),
    "Chocolate": (chocolate_field, 5.4),
    "Salt": (salt_field, 3.0),
    "Lava": (lava_field, 6.5),
    "Oobleck": (oobleck_field, 5.0),
    "Buttons": (button_field, 3.9),
    "Snow": (snow_field, 5.5),
}


# ============================================================ sculpted form variants
#
# A SHAPE STANDING ON THE BED, not cut out of it. This is the sand turtle's approach applied
# to the other eleven beds, and the reasoning transfers exactly: every mesh here has
# CanCollide false and the slab underneath is what you walk on, so cutting a shape out of the
# plan would leave you walking on air around it. Nobody cuts a crater-shaped hole in a lava
# field either -- a vent is something the field DOES, not a hole in the world.
#
# So a sculpt is just another height contribution added to the material's own field. The
# material keeps its texture everywhere; the sculpt puts a form on top of it. Two lines of
# composition, and every one of the eleven beds can have as many variants as there are
# sculpts, with no change to the field functions themselves.
#
# === Why they are all so gentle ===
#
# `check_field_tapers` refuses any two neighbouring samples differing by more than one sample
# step -- anything past 45 degrees is a staircase whatever it looks like from a helpful
# angle. That is not a limitation to work around, it is the reason these read as MOULDED
# rather than as stuck on: a crater rim with a vertical wall is a cardboard cutout of a
# crater. Every profile below goes through a smoothstep with a transition measured in studs.
#
# `RIM_FADE` is the other half. A sculpt that is still non-zero at the platform edge leaves a
# wall at the rim, which is the same failure the lamb's ear bed shipped three broken renders
# on. Everything is masked to nothing well inside the boundary.
RIM_FADE = 2.6      # studs of margin where a sculpt is faded out entirely


def rim_mask(size_x, size_z):
    """1 in the middle, 0 at the platform edge. Every sculpt multiplies through this."""
    def mask(x, y):
        return min(inside(size_x / 2.0, RIM_FADE, abs(x)),
                   inside(size_z / 2.0, RIM_FADE, abs(y)))
    return mask


def mound_sculpt(size_x, size_z):
    """A single soft dome. The plainest form there is, and the one a heap of anything makes.

    Radius is 0.34 of each half-extent rather than a fixed number of studs, so it fills the
    same fraction of the platform whatever size it is asked for.
    """
    mask = rim_mask(size_x, size_z)
    rx, rz = size_x * 0.34, size_z * 0.34

    def sculpt(x, y):
        r = math.sqrt((x / rx) ** 2 + (y / rz) ** 2)
        return 2.30 * (1.0 - smoothstep(0.0, 1.0, min(1.0, r))) * mask(x, y)

    return sculpt


def crater_sculpt(size_x, size_z):
    """A raised rim with a bowl inside it. A vent.

    The BOWL IS SHALLOWER THAN THE RIM IS TALL, deliberately. A crater whose floor drops as
    far as its rim rises is a hole with a lip, and on a platform you walk over it reads as
    damage. Two thirds keeps it a basin.
    """
    mask = rim_mask(size_x, size_z)
    radius = min(size_x, size_z) * 0.30

    def sculpt(x, y):
        r = math.sqrt(x * x + y * y) / radius
        # A ring: rises to the rim at r = 1 and falls away on both sides.
        rim = 1.85 * (1.0 - smoothstep(0.0, 0.62, abs(r - 1.0)))
        bowl = -1.15 * (1.0 - smoothstep(0.0, 1.0, min(1.0, r / 0.72)))
        return (rim + bowl) * mask(x, y)

    return sculpt


def ridge_sculpt(size_x, size_z):
    """A spine running corner to corner, broken by a notch in the middle.

    THE NOTCH IS THE POINT. An unbroken ridge across a platform is a wall you walk around;
    one with a gap in the middle is a feature you walk THROUGH, and it stops the sculpt from
    dictating the route.
    """
    mask = rim_mask(size_x, size_z)
    width = min(size_x, size_z) * 0.18
    slope = math.atan2(size_z, size_x)
    sin_a, cos_a = math.sin(slope), math.cos(slope)

    def sculpt(x, y):
        across = abs(-x * sin_a + y * cos_a)          # distance from the spine
        along = abs(x * cos_a + y * sin_a)            # distance along it from the centre
        spine = 2.40 * (1.0 - smoothstep(0.0, width, across))
        notch = 1.0 - inside(2.4, 1.9, along)         # 0 at the middle, 1 out at the ends
        return spine * notch * mask(x, y)

    return sculpt


def terrace_sculpt(size_x, size_z):
    """Three concentric plateaus. A thumb pressed into a slab, or a rice paddy from above.

    The steps are smoothed over 0.9 studs each -- wide enough to pass the taper check and
    narrow enough that you can count them, which is the whole read.
    """
    mask = rim_mask(size_x, size_z)
    outer = min(size_x, size_z) * 0.42
    step = 0.85

    def sculpt(x, y):
        r = max(abs(x) / (size_x * 0.5), abs(y) / (size_z * 0.5)) * min(size_x, size_z) * 0.5
        height = 0.0
        for level in range(3):
            edge = outer * (1.0 - level * 0.30)
            height += step * inside(edge, 0.9, r)
        return height * mask(x, y)

    return sculpt


def swirl_sculpt(size_x, size_z):
    """A piped spiral: two turns of a raised coil, tapering as it goes out.

    Distance to an Archimedean spiral has no closed form, so it is found by testing the few
    turns that could possibly be nearest -- which at two turns is three candidates, and
    cheaper than it sounds because the loop never runs more than that.
    """
    mask = rim_mask(size_x, size_z)
    pitch = min(size_x, size_z) * 0.155     # radius gained per turn
    width = pitch * 0.42

    def sculpt(x, y):
        r = math.sqrt(x * x + y * y)
        angle = math.atan2(y, x)
        best = 1e9
        for turn in range(4):
            spiral_r = pitch * (angle / (2.0 * math.pi) + turn)
            if spiral_r < 0.0:
                continue
            best = min(best, abs(r - spiral_r))
        coil = 1.65 * (1.0 - smoothstep(0.0, width, best))

        # THE CENTRE OF A SPIRAL IS A SINGULARITY, and it measured 87 degrees.
        #
        # The coil's height depends on the ANGLE, and every angle meets at the origin: at a
        # radius of a tenth of a stud the surface ran from full height at one bearing to
        # nothing at the opposite one, across an arc a third of a stud long. No amount of
        # smoothing the profile helps, because the profile is not what is steep.
        #
        # So the innermost turn is replaced by a dome of the same height. Piped icing does
        # the same thing for the same reason -- a nozzle cannot make a spiral tighter than
        # its own bore, so the middle of a rosette is a blob.
        centre = 1.0 - smoothstep(0.0, pitch * 1.15, r)
        height = coil * (1.0 - centre) + 1.65 * centre

        # Tapers outward, the way piped icing thins as the nozzle lifts.
        return height * inside(pitch * 2.6, pitch * 1.6, r) * mask(x, y)

    return sculpt


def dune_sculpt(size_x, size_z):
    """One asymmetric bank: a long windward slope and a short lee face.

    The asymmetry is the whole thing. A symmetric bank is a mound; what makes a drift read as
    a drift is that it was PUSHED -- shallow on the side the wind came from and steep on the
    side it fell down. Steep here still means under the taper limit.
    """
    mask = rim_mask(size_x, size_z)
    crest = size_z * 0.06          # where the top of the bank sits, just past the middle
    windward = size_z * 0.32       # the long climb up to it
    lee = size_z * 0.26            # and the short drop off the back

    def sculpt(x, y):
        # The first version had both halves the wrong way round: `inside` returns 1 BELOW its
        # edge, so the windward branch came out 1 at the far rim and 0 at the crest -- a ramp
        # running off the platform rather than a bank standing on it. It rendered as a
        # mattress, which is what a full-platform ramp looks like from the front.
        # NOT `inside` HERE, and this is a fourth entry on that helper's list.
        #
        # `inside` clamps its lower bound with `max(0.0, edge - softness)` because it is built
        # for a DISTANCE, which is never negative. `y` is a signed coordinate, and the
        # windward climb starts at crest - windward = -3.12 -- so the clamp moved the start of
        # the ramp to 0 and squeezed a 3.8-stud climb into 0.7. The mesh came out at 80
        # degrees where the source plainly says it should be 47.
        #
        # Written out because the shape is not a falloff from an edge, it is a ramp between
        # two signed heights, and that is what smoothstep already is.
        if y >= crest:
            profile = 1.0 - smoothstep(crest, crest + lee, y)   # the short drop off the back
        else:
            profile = smoothstep(crest - windward, crest, y)    # the long climb up to it
        # Bows along X so the bank is a crescent rather than a straight wall across.
        bow = 1.0 - 0.55 * (x / (size_x * 0.5)) ** 2
        return 2.80 * profile * max(0.0, bow) * mask(x, y)

    return sculpt


def comb_sculpt(size_x, size_z):
    """A HONEYCOMB: raised walls, recessed cells between them.

    Built as the Voronoi boundary of a TRIANGULAR lattice, which is the cheapest honest
    hexagon there is -- the cells of a triangular lattice's Voronoi diagram are hexagons
    exactly, so the walls come out with the right angles for free and no cell is ever
    clipped into a pentagon by an arithmetic edge case. Snow's crust uses the same
    two-nearest-seeds trick for its plate joins; this is that with the sign flipped and the
    seeds on a regular grid instead of a jittered one.

    THE PITCH IS CELL SCALE ON PURPOSE. At roughly four studs a cell the comb is about the
    size of a sub-region, so the collider grid can actually follow it -- the walls come out
    as raised footing and the cells as dips you step down into. A finer comb would be
    prettier and would be pure decal: the floor would not know it was there.
    """
    mask = rim_mask(size_x, size_z)
    pitch = 4.2
    rows_step = pitch * 0.866        # sin 60: the row spacing of a triangular lattice
    wall = 0.85                      # how far the walls stand above the cell floors
    thickness = 0.62                 # studs of wall, measured across the top

    def sculpt(x, y):
        # The two nearest lattice seeds. Their difference in distance is zero exactly on a
        # cell boundary and grows inward, so it IS the distance to the nearest wall.
        best, second = 1e9, 1e9
        row0 = int(math.floor(y / rows_step))
        col0 = int(math.floor(x / pitch))
        for row in range(row0 - 1, row0 + 3):
            offset = (row % 2) * pitch * 0.5
            for col in range(col0 - 1, col0 + 3):
                dx = x - (col * pitch + offset)
                dy = y - row * rows_step
                d = math.sqrt(dx * dx + dy * dy)
                if d < best:
                    best, second = d, best
                elif d < second:
                    second = d
        if second >= 1e8:
            return 0.0
        join = (second - best) * 0.5
        return wall * (1.0 - smoothstep(0.0, thickness, join)) * mask(x, y)

    return sculpt


def pool_sculpt(size_x, size_z):
    """A BASIN: the middle of the platform is lower than its rim.

    The only sculpt here that goes DOWN as its main gesture -- the crater has a bowl but
    spends most of its height on the rim above it. This is the inverse of the mound, and it
    is the one shape whose function is unambiguous: you walk down into it and back out, and
    the way round the edge is longer than the way through.
    """
    mask = rim_mask(size_x, size_z)
    rx, rz = size_x * 0.36, size_z * 0.36

    def sculpt(x, y):
        r = math.sqrt((x / rx) ** 2 + (y / rz) ** 2)
        # A raised lip first, so the basin reads as something the material was POURED into
        # rather than as a dent. Small: most of the depth is below the plate, not above it.
        lip = 0.45 * (1.0 - smoothstep(0.0, 0.55, abs(r - 1.05)))
        bowl = -1.95 * (1.0 - smoothstep(0.0, 1.0, min(1.0, r)))
        return (lip + bowl) * mask(x, y)

    return sculpt


def blister_sculpt(size_x, size_z):
    """A field of DOMES of mixed size, merged where they touch.

    Bubbles risen under a skin: a soft maximum rather than a sum, so where two overlap you
    get one larger blister and not a lump with a seam up the middle -- the same reason the
    cloud bed uses soft_max and the snow drifts do.

    Sized so a dome is roughly a cell across, which is what makes this the bounciest thing
    to walk on rather than a texture: your footing is on top of one blister or down in the
    gap between two, and the collider grid is fine enough to tell the difference.
    """
    mask = rim_mask(size_x, size_z)
    domes = scatter(size_x, size_z, 4.0, 1.2, 20260118, jitter=0.55)

    def sculpt(x, y):
        best, second = -1e9, -1e9
        for cx, cy, _angle, roll in domes:
            # THE SIZE RANGE IS NARROW, and both ends of it were found the hard way.
            #
            # Too big and the domes overlap every neighbour, the soft maximum merges the lot,
            # and the surface reads as gentle waves rather than as bubbles. Too small and
            # they fall below the mesh's own sampling -- slime is built at 0.4 studs a
            # sample, so a dome under about 1.7 studs of radius spans four samples and
            # renders as a faceted CONE. Sharp spikes and soft waves are the two failure
            # modes and there is not much room between them.
            radius = 2.3 * (0.78 + 0.30 * roll)
            dx, dy = x - cx, y - cy
            d2 = dx * dx + dy * dy
            if d2 >= radius * radius:
                continue
            h = 2.00 * (0.62 + 0.6 * roll) * (1.0 - smoothstep(0.0, 1.0, math.sqrt(d2) / radius))
            if h > best:
                best, second = h, best
            elif h > second:
                second = h
        if best <= -1e9:
            return 0.0
        # Tighter than the cloud's blend, which wants one indivisible mass; the point here
        # is the opposite, that you can count them.
        return soft_max(best, second, 0.45) * mask(x, y)

    return sculpt


def channel_sculpt(size_x, size_z):
    """A TROUGH down the travel axis, with a bank either side.

    The one sculpt that shapes the ROUTE rather than the surface. The banks are walkable and
    the groove between them is a stud and a half lower, so crossing the platform is a choice
    of lane -- and unlike the ring or the bone it takes nothing away, so nobody can fall
    through it. The groove narrows toward the middle, which stops it reading as an extrusion.
    """
    mask = rim_mask(size_x, size_z)
    half = size_x * 0.5

    def sculpt(x, y):
        # Waisted: the trough pinches at the centre of the platform and opens at both faces,
        # so it is a shape rather than a slot cut straight through.
        width = size_x * (0.30 - 0.10 * (1.0 - abs(y) / (size_z * 0.5)))
        groove = -1.55 * (1.0 - smoothstep(width * 0.55, width, abs(x)))
        bank = 1.15 * (1.0 - smoothstep(0.0, half * 0.34, abs(abs(x) - half * 0.62)))
        return (groove + bank) * mask(x, y)

    return sculpt


# HOW MUCH SCULPT COUNTS AS "FULLY ON TOP OF" THE BED, in studs.
#
# Adding a sculpt to a field is not enough, and three of the first six variants proved it:
# the lava crater and the chocolate swirl read immediately, and the snow dune, the charcoal
# ridge and the cloud mound were invisible. All three sit on beds whose OWN relief is as
# tall as the form was -- a metaball cloud is nothing but lumps, so one more lump is not a
# shape, it is another lump.
#
# So the sculpt damps the bed underneath it as it rises. Past this height the material's own
# texture is gone entirely and what you see is the form's surface, which is what "a sculpture
# standing on a bed" has to mean: the turtle is not a turtle-shaped ripple in the sand.
#
# The bed is untouched wherever the sculpt is flat, so the platform still reads as its
# material everywhere around the form.
SCULPT_DOMINATE = 0.75


SCULPTS = {
    "mound": mound_sculpt,
    "crater": crater_sculpt,
    "ridge": ridge_sculpt,
    "terrace": terrace_sculpt,
    "swirl": swirl_sculpt,
    "dune": dune_sculpt,
    # The four below were written for honey and slime, which have their own generators --
    # but a sculpt is a pure height function and knows nothing about the surface it lands
    # on, so every bed can use them and these can use every bed's.
    "comb": comb_sculpt,
    "pool": pool_sculpt,
    "blister": blister_sculpt,
    "channel": channel_sculpt,
}

# WHICH BED GETS WHICH FORM, one each, chosen so the sculpt is something the material would
# actually do. A crater in snow would be a fine mesh and a nonsense object.
# The third column is how hard the form suppresses the bed under it, in studs of sculpt --
# see SCULPT_DOMINATE. Lower means the form takes over sooner.
#
# CLOUD IS THE EXCEPTION and it is worth the column on its own. Damping a cloud gives a
# smooth dome sitting in a field of lumps, which reads as a bald patch rather than as a
# bigger cloud: the metaball texture IS the material, so the form has to be built out of it
# rather than laid over it. At 3.0 the mound barely damps at all and comes out as one large
# swell in the same lumpy surface, which is what a cumulus is.
VARIANTS = [
    {"material": "Lava", "form": "crater", "sculpt": "crater"},        # a vent
    {"material": "Chocolate", "form": "swirl", "sculpt": "swirl"},     # piped
    {"material": "Snow", "form": "dune", "sculpt": "dune"},            # a drift
    {"material": "Clay", "form": "terrace", "sculpt": "terrace"},      # pressed in steps
    {"material": "Charcoal", "form": "ridge", "sculpt": "ridge"},      # a broken spine
    {"material": "Cloud", "form": "mound", "sculpt": "mound", "dominate": 3.0},

    # THE KEYPADS, and they are the reason a variant is a record rather than a tuple: a
    # button plate varies by how many buttons are on it, which is a different FIELD, not a
    # sculpt laid over one.
    #
    # An earlier pass gave buttons the same treatment as soap -- a PlanShapes outline cutting
    # caps out of the grid -- and it was wrong on its own terms. The plate underneath is a
    # rigged mesh and stays a full rectangle, so removing caps does not change the platform's
    # shape at all; it just leaves gaps in a keypad. A keypad with buttons missing is not a
    # variation on a keypad, it is a broken one.
    {"material": "Buttons", "form": "dense", "div": 2},
    # And a plate that is genuinely a different shape, with its buttons still complete and
    # still symmetric -- they ride the dome because each one sits on its cell's collider,
    # and the collider now follows the mesh.
    {"material": "Buttons", "form": "dome", "sculpt": "mound", "dominate": None},
]




def sculpted(make_field, make_sculpt, dominate=SCULPT_DOMINATE):
    """The material's own field with a form standing on it, damping it as it rises."""
    def build(size_x, size_z):
        base = make_field(size_x, size_z)
        relief = make_sculpt(size_x, size_z)

        def field(x, y):
            height = relief(x, y)
            # Weighted on the sculpt's MAGNITUDE, so a crater's bowl suppresses the texture
            # exactly as much as its rim does. Signed would leave the dug-out middle full of
            # the surface it was dug out of.
            # SMOOTHSTEPPED, not a linear ramp, and the difference is a failed slope check.
            #
            # A linear `min(1, h/dominate)` switches the bed off at a constant rate, and the
            # beds it switches off are not themselves smooth -- chocolate has square grooves
            # and snow has crust lines cut as steps. Fading a discontinuous surface out at a
            # constant rate leaves the discontinuity in the result, just scaled: the swirl
            # came out at 84 degrees and the dune at 80, both exactly where the damping was
            # steepest rather than where the sculpt was.
            #
            # Smoothstep has zero derivative at both ends, so the bed's own detail is
            # untouched where it is fully present, gone where it is fully suppressed, and
            # nowhere is it being scaled fast enough for its own steps to show through.
            # `dominate = None` means ADD, damping nothing. The keypad dome needs it: its
            # bed is not a texture the form stands on, it is a pattern of wells that has to
            # RIDE the form -- damped even gently, the buttons nearest the top dissolved and
            # the plate came out as a bare hill with buttons around its foot.
            if dominate is None:
                return base(x, y) + height
            weight = smoothstep(0.0, dominate, abs(height))
            return base(x, y) * (1.0 - weight) + height

        return field

    return build


def check_field_tapers(name, field, size_x, size_z):
    """No field may leave a WALL at the platform rim.

    The lamb's ear bed shipped three broken renders because its profile ended in a cliff,
    and slope statistics were too weak to separate that from a legitimately steep edge. The
    property is exact, so it is tested exactly: sample the field densely and require no two
    neighbouring samples to differ by more than one sample step. Anything past 45 degrees
    at this spacing is a staircase whatever it looks like from a helpful angle.
    """
    step = BED.RES
    worst = 0.0
    where = (0.0, 0.0)
    x = -size_x / 2
    while x < size_x / 2:
        y = -size_z / 2
        while y < size_z / 2:
            here = field(x, y)
            for dx, dy in ((step, 0.0), (0.0, step)):
                rise = abs(field(x + dx, y + dy) - here)
                if rise > worst:
                    worst, where = rise, (x, y)
            y += step * 2
        x += step * 2
    angle = math.degrees(math.atan2(worst, step))
    ok = angle <= 78.0
    print(f"    field slope: steepest {angle:.1f} deg at ({where[0]:+.1f}, {where[1]:+.1f}) -- "
          f"{'ok' if ok else 'TOO STEEP, expect stair-stepping'}")
    return ok


def export_fbx(mesh_obj, arm_obj, filename, uv_studs):
    uv_project.box_project(mesh_obj.data, uv_studs)
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
    print(f"    exported {os.path.basename(path)}")


def build_one(material, make_field, uv_studs, form=None, cap_div=None):
    size_x, size_z = SIZE
    # The form goes in the FILENAME, because `skinnedSpecFor` matches on size first and form
    # second -- two rigs of the same dimensions are indistinguishable to it otherwise, and it
    # would pick whichever came first in the table.
    name = f"{material}_Platform_{size_x:.0f}x{size_z:.0f}"
    if form:
        name += "_" + form.capitalize()
    field = make_field(size_x, size_z)

    print(f"\n  {material}" + (f" [{form}]" if form else ""))
    ok = check_field_tapers(material, field, size_x, size_z)

    BUTTER.clear_scene()
    cols, rows, cell_x, cell_z = BUTTER.compute_grid(size_x, size_z)
    mesh_obj, static, n_top = BED.build_surface(size_x, size_z, name, relief=field)
    arm_obj, centres = BUTTER.build_armature(size_x, size_z, cols, rows, name + "_Rig")
    covered = BUTTER.assign_weights(mesh_obj, arm_obj, static, centres, cell_x, cell_z)
    ok = BUTTER.validate_mesh(mesh_obj, n_top) and covered and ok

    tris = sum(len(p.vertices) - 2 for p in mesh_obj.data.polygons)
    zs = [v.co.z for v in mesh_obj.data.vertices]
    low, high = min(zs), max(zs)

    # A FLAT BED IS ALWAYS A BUG. Every field here is meant to put something on the surface,
    # so a field returning zero everywhere exports perfectly happily as a smooth slab with a
    # material name on it. Salt and the buttons both shipped that way for one run, and
    # neither the mesh validator nor the slope check had anything to say about them: a plane
    # is manifold, correctly wound and not steep.
    #
    # MEASURED AS A RANGE, not as a peak. The first version tested `high - THICK`, which
    # assumes every field builds UPWARD -- and the button plate carves wells DOWN and puts
    # nothing above the base at all, so a perfectly good surface was reported flat. What
    # matters is whether the field varies, not which way it went.
    lo, hi = 1e9, -1e9
    step = BED.RES * 3
    px = -size_x / 2 + 1.0
    while px < size_x / 2 - 1.0:
        py = -size_z / 2 + 1.0
        while py < size_z / 2 - 1.0:
            value = field(px, py)
            lo, hi = min(lo, value), max(hi, value)
            py += step
        px += step
    if hi - lo < 0.02:
        print(f"    !! FLAT: the field spans {hi - lo:.4f} studs. It returned nothing --"
              f" check for a smoothstep written backwards (see `inside`).")
        ok = False

    walkable = high + 0.02

    # ============ WHERE THE FLOOR ACTUALLY IS, cell by cell.
    #
    # `walkable` above is the mesh's HIGHEST point, and every tile on a skinned platform is
    # placed at exactly that one height. On a plain bed nobody notices -- lava's relief is a
    # third of a stud. On a sculpted one the peak is nearly three studs above the bed, so you
    # stand on a flat plane level with the top of the ridge and the whole platform is under
    # your feet with nothing touching them. That is what "it looks like I'm floating on
    # charcoal" is: not a bug in the mesh, a collider that was never told the mesh had a
    # shape.
    #
    # So each cell gets its own drop below that plane. NEGATIVE by construction: the plane
    # stays the ceiling, so nothing can poke up through a floor, and every cell comes down to
    # meet the surface underneath it.
    #
    # SAMPLED AS A MAXIMUM over the cell, not at its centre. A centre sample on a lumpy bed
    # lands wherever it lands -- in a crust groove as often as on a crest -- and a floor set
    # to the bottom of a groove buries your feet in the surface. The high point is the thing
    # you would actually stand on.
    #
    # The grid is BUTTER.compute_grid, which is the same formula as SubRegionGrid.compute in
    # the Luau, because the bones are matched to cells by position -- that is not a
    # coincidence to rely on quietly, so check_chunk_forms asserts the count.
    peak = -1e9
    drops = []
    for row in range(rows):
        for col in range(cols):
            best = -1e9
            for sx in range(3):
                for sz in range(3):
                    cx = -size_x / 2.0 + (col + (sx + 0.5) / 3.0) * cell_x
                    cz = -size_z / 2.0 + (row + (sz + 0.5) / 3.0) * cell_z
                    best = max(best, field(cx, cz))
            drops.append(best)
            peak = max(peak, best)
    # Relative to the flattest reading of the plane the tiles are placed at. The dense
    # `high` above is taken over the whole mesh including its rim, so the cell maxima are
    # rebased on their own peak rather than on it -- otherwise every cell of a plain bed
    # would carry a small non-zero drop for no reason.
    drops = [round(d - peak, 3) for d in drops]
    drop_text = ""
    if min(drops) < -0.08:
        drop_text = ", drops = { " + ", ".join(f"{d:g}" for d in drops) + " }"
    print(f"    {cols}x{rows} grid, {len(centres)} bones, {tris} tris, "
          f"relief {high - THICK:+.2f}, floor drops {min(drops):+.2f}..{max(drops):+.2f}, "
          f"{'valid' if ok else 'INVALID'}")
    if not SPECS_ONLY:
        export_fbx(mesh_obj, arm_obj, name + ".fbx", uv_studs)
    entry = (f"\t\t{{ sizeX = {size_x:.0f}, sizeZ = {size_z:.0f}, "
             f"meshHeight = {high - low:.2f}, surfaceOffset = {walkable - (low + high) / 2.0:.2f}, "
             f'mesh = "{name}"' + (f', form = "{form}"' if form else "")
             + (f", capDiv = {cap_div}" if cap_div and cap_div != 1 else "")
             + drop_text + " },")
    return material, entry, ok


def main():
    results, all_ok = [], True
    # `-- Lava Snow` builds only those; `-- variants` skips the eleven plain beds, which is
    # what you want after adding a sculpt: the plain fields have not changed, and rebuilding
    # them means eleven identical FBXs to re-import for nothing.
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    variants_only = "variants" in argv
    # `-- specs` prints the SKINNED_PLATFORMS rows and exports nothing. The drops below are
    # collider data rather than geometry, so a change to them needs a paste and no re-import.
    global SPECS_ONLY
    SPECS_ONLY = "specs" in argv
    only = {a for a in argv if a not in ("variants", "specs")} or None
    for material, (make_field, uv_studs) in RECIPES.items():
        if variants_only or (only and material not in only):
            continue
        material, entry, ok = build_one(material, make_field, uv_studs)
        results.append((material, entry))
        all_ok = all_ok and ok

    # THE VARIANTS RUN SECOND AND SHARE THE PLAIN BED'S UV SCALE. A form variant is the same
    # material with a shape on it, so a different texture scale between the two would make
    # the plain platform and the sculpted one read as different substances -- which is the
    # one thing a variant must not do.
    for spec in VARIANTS:
        material, form = spec["material"], spec["form"]
        if only and material not in only:
            continue
        make_field, uv_studs = RECIPES[material]
        if "div" in spec:
            div = spec["div"]
            make_field = lambda sx, sz, d=div: button_field(sx, sz, div=d)
        if "sculpt" in spec:
            make_field = sculpted(make_field, SCULPTS[spec["sculpt"]],
                                  spec.get("dominate", SCULPT_DOMINATE))
        _, entry, ok = build_one(material, make_field, uv_studs, form,
                                 cap_div=spec.get("div", 1) if material == "Buttons" else None)
        results.append((material, entry))
        all_ok = all_ok and ok

    print("")
    print("  ChunkBuilder SKINNED_PLATFORMS entries:")
    for material, entry in results:
        print(f"\t{material} = {{")
        print(entry)
        print("\t},")
    print("")
    print("Done." if all_ok else "!! a mesh failed validation -- DO NOT import.")


if __name__ == "__main__":
    main()
