"""The leviathan: a sculpted sea creature for the lobby's horizon.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_hub_leviathan.py

=== What this is for ===

The lobby looks out over open sea, and the sunken blade already stands in it. A blade is a made
thing and says somebody was here; this says something LIVES here, which is the other half of
the same feeling and the one that makes a horizon uneasy rather than just empty.

=== Why it is TWO meshes ===

Roblox caps a MeshPart at ten thousand triangles, and the first version spent its whole budget
spread evenly over three hundred studs of body -- so nothing had enough geometry to be more
than a faceted tube, and the head, which is the only part anybody actually looks at, came out
as a crate with horns.

Split in two, each half gets its own ten thousand. The head can afford a subdivided skull,
set eyes, curved teeth and horns with a taper; the body can afford a smooth arc and fins with
real membrane instead of flat triangles.

They are built in ONE coordinate space and exported without moving, so importing both and
dropping them at the same position lines them up exactly. There is no assembly step.

=== Why it is mostly hidden ===

The most reliable way to make a sea creature look small is to show all of it. Nothing in the
water reads as vast once you can see where it stops. So the body is almost entirely under the
surface: what breaks the water is a long low back, a run of dorsal fins, and the head. There is
no belly and no tail fluke, because an opaque sea never has to be shown them.

=== Where the detail actually comes from ===

Three things, in order of how much they matter at distance:

  SILHOUETTE   Horns, the open jaw, teeth, and fins with a curved trailing edge. All of these
               change the outline against the sky, which is the only thing legible from far
               away. Detail that lives inside the outline is invisible at range.
  FORM         Cross-sections that change along the body -- a keeled back, flat cheeks, a
               narrow snout -- rather than one circle scaled up and down. This is what stops
               it reading as a tube.
  SKIN         Multi-octave noise displacement, so no two square studs of hide are the same.
               This is the part that only pays off up close, and it is applied last so it
               never fights the two above.
"""

import math
import os

import bmesh
import bpy
from mathutils import Vector

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "meshes")

# The spine, as a curve through space. Studs.
LENGTH = 300.0
ARCH = 26.0

# Stations along the body, and points around each. 120 x 18 is 4320 triangles, which leaves
# room for the fins inside one mesh budget.
BODY_SEGMENTS = 120
BODY_AROUND = 18

# The head is a separate mesh, so it can afford more than three times the density per stud.
HEAD_STATIONS = 34
HEAD_AROUND = 24

HEAD_AT = 0.035          # where along the spine the skull sits

# The armour lattice: plates around the body, and rows along it.
SCALE_COLS = 11
SCALE_ROWS = 54
# How far a plate stands proud, in studs. Small on purpose -- armour reads by its SHADOW at
# the plate edges, not by its thickness, and a big number turns the animal into a pinecone.
SCALE_RISE = 0.34


# --------------------------------------------------------------------------- #
# Noise. Deterministic, so two runs produce the same creature.
# --------------------------------------------------------------------------- #

def _hash3(i: int, j: int, k: int) -> float:
    """A stable pseudo-random value in 0..1 from three integers."""
    h = (i * 374761393 + j * 668265263 + k * 2147483647) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFFFF) / 0xFFFFFF


def _smooth(a: float) -> float:
    return a * a * (3.0 - 2.0 * a)


def value_noise(x: float, y: float, z: float) -> float:
    """Trilinear value noise in -1..1."""
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = _smooth(x - ix), _smooth(y - iy), _smooth(z - iz)
    total = 0.0
    for dz in (0, 1):
        for dy in (0, 1):
            for dx in (0, 1):
                weight = ((fx if dx else 1 - fx)
                    * (fy if dy else 1 - fy)
                    * (fz if dz else 1 - fz))
                total += weight * _hash3(ix + dx, iy + dy, iz + dz)
    return total * 2.0 - 1.0


def fbm(p: Vector, scale: float, octaves: int = 4) -> float:
    """Fractal noise: several octaves of value noise, each finer and quieter.

    ONE OCTAVE IS A LUMPY BALLOON. Skin has structure at several sizes at once -- broad
    muscle and fat under it, plates over that, and a fine grain over those -- and stacking
    octaves is the cheapest honest way to get all three from one function.
    """
    total, amplitude, frequency, norm = 0.0, 1.0, 1.0 / scale, 0.0
    for _ in range(octaves):
        total += amplitude * value_noise(p.x * frequency, p.y * frequency, p.z * frequency)
        norm += amplitude
        amplitude *= 0.5
        frequency *= 2.13        # not exactly 2, so octaves do not line up into a grid
    return total / norm



def scale_relief(along: float, around: float) -> float:
    """One row of overlapping armour plates, as a height in 0..1.

    ARMOUR IS THE ONE PATTERN NOISE CANNOT FAKE. Multi-octave noise gives lumpy hide -- fat
    and muscle under skin -- and that is right for the belly and wrong for the back, because
    plates are REGULAR. They sit in rows, each row offset half a plate from the one beside
    it, and every plate is the same size as its neighbours. Randomness is exactly the quality
    they do not have.

    So this is a lattice, not a noise: a squashed dome per cell, on a brick bond. The bond is
    what stops it reading as a chequerboard -- offsetting alternate columns by half means no
    two plate edges ever line up into a straight seam across the animal.
    """
    ring = around * SCALE_COLS
    column = math.floor(ring)
    run = along * SCALE_ROWS + (0.5 if column % 2 else 0.0)
    fa, fb = (ring % 1.0) - 0.5, (run % 1.0) - 0.5
    # Wider than tall, because a scale is a shingle: it overlaps the one behind it, so it is
    # stretched along the body rather than round it.
    reach = math.sqrt(fa * fa * 2.1 + fb * fb)
    if reach > 0.5:
        return 0.0
    return (1.0 - reach * 2.0) ** 1.4


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.objects, bpy.data.armatures):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


# --------------------------------------------------------------------------- #
# The spine
# --------------------------------------------------------------------------- #

def spine(t: float) -> Vector:
    """Where the centreline is at t in 0..1, nose to tail.

    IT REARS. The first build laid the whole animal along the waterline with only its back
    and a raised nose breaking the surface, which reads as something drifting -- a whale, or
    a reef. Every sea serpent worth being afraid of comes UP out of the water: the neck
    stands, the head is held high and looks down at you, and the body goes back under in
    coils behind it. That vertical neck is the single silhouette that says "serpent", and no
    amount of detail on a horizontal one substitutes for it.

    Two pieces, joined so their positions and slopes agree at t = 0.32:

      THE NECK    An S from the head down into the water. Not an arc -- an arc is a croquet
                  hoop. The S comes from a smoothstep fall in height against a sweep that
                  bulges forward in the middle, so the throat is thrown out ahead of the
                  shoulder the way a striking snake's is.
      THE BODY    Two coils breaking the surface astern, the second lower and further off,
                  then a tail that leaves through the water rather than ending anywhere you
                  can see.
    """
    if t < 0.32:
        f = t / 0.32
        ease = f * f * (3.0 - 2.0 * f)
        # STEEPER THAN THE FIRST REAR. Seventy studs of fall against seventy of sweep is a
        # forty-five degree ramp, and a ramp reads as something climbing out onto a beach.
        # Seventy of fall against forty-five of sweep is fifty-seven degrees, which is a neck
        # standing up. The difference between the two is the whole pose.
        z = 62.0 - 70.0 * ease
        # Swept back as it falls, and bulged forward through the middle: the S.
        x = -95.0 + 45.0 * f + 18.0 * math.sin(f * math.pi)
        y = -12.0 + 14.0 * math.sin(f * 2.2)
        return Vector((x, y, z))

    f = (t - 0.32) / 0.68
    first = math.exp(-((f - 0.20) ** 2) / 0.014)
    second = 0.55 * math.exp(-((f - 0.56) ** 2) / 0.022)
    z = -8.0 + 24.0 * (first + second)
    x = -50.0 + f * 240.0
    y = -12.0 + 30.0 * math.sin(f * 2.6 + 0.4)
    return Vector((x, y, z))


def head_frame():
    """The skull's own frame, taken from the top of the neck and pitched down.

    NOT frame_at(). The spine's tangent at the top of the neck points DOWNWARD -- t runs
    nose to tail, so "forward along the curve" is into the neck -- and building the skull
    along it would drive the snout straight down through the animal's own throat.

    So the snout runs along the REVERSE of the tangent, and then the whole head is pitched
    a little further down than that. A serpent reared over you is not looking at the horizon;
    it is looking at the thing it has come up for.
    """
    here, forward, _, _ = frame_at(0.012)
    snout = -forward
    # Pitched down about the head's own left-right axis.
    side = snout.cross(Vector((0, 0, 1)))
    if side.length < 1e-6:
        side = Vector((0, 1, 0))
    side.normalize()
    # ONLY A LITTLE. At 0.34 radians the head hung off the end of the neck looking at its own
    # feet, which reads as dead rather than dangerous. 0.14 keeps the skull essentially in
    # line with the neck with just enough tilt to be looking DOWN at something.
    snout = (snout * math.cos(0.14) + side.cross(snout) * math.sin(0.14)).normalized()
    right = snout.cross(Vector((0, 0, 1)))
    if right.length < 1e-6:
        right = Vector((0, 1, 0))
    right.normalize()
    return here, snout, right, right.cross(snout).normalized()


def girth(t: float) -> float:
    # THE NECK IS THICK AND NEARLY EVEN. A taper toward the head makes a fish; a serpent's
    # neck is a column of muscle that barely narrows until it meets the skull, and the
    # thickening into the shoulder is what makes the reared part look heavy enough to hold
    # itself up.
    if t < 0.32:
        f = t / 0.32
        # Thickened to carry the heavier skull. A neck that visibly could not hold the head
        # up is the sort of thing nobody consciously notices and everybody finds unconvincing.
        return 9.5 + 6.5 * f * f
    f = (t - 0.32) / 0.68
    return 14.0 * (1.0 - 0.74 * max(0.0, (f - 0.22) / 0.78) ** 1.35)


def frame_at(t: float):
    here = spine(t)
    ahead, behind = spine(min(1.0, t + 0.004)), spine(max(0.0, t - 0.004))
    forward = ahead - behind
    if forward.length < 1e-6:
        forward = Vector((1, 0, 0))
    forward.normalize()
    right = forward.cross(Vector((0, 0, 1)))
    if right.length < 1e-6:
        right = Vector((0, 1, 0))
    right.normalize()
    return here, forward, right, right.cross(forward).normalized()


# --------------------------------------------------------------------------- #
# The body
# --------------------------------------------------------------------------- #

def body_section(angle: float, t: float, radius: float) -> tuple:
    """The cross-section at one station, as (across, vertical) in studs.

    NOT A CIRCLE, and not the same shape twice. A swimming animal is deep and narrow, keeled
    along the spine where the fins root, and it flattens toward the tail as the body turns
    into a blade. Sweeping one circle is what made the first build read as a pipe.
    """
    across = math.cos(angle)
    vertical = math.sin(angle)

    # Deeper below than above: the back is a shallow curve, the flanks fall away.
    depth = 0.74 if vertical > 0 else 1.30
    # Flattened side to side toward the tail, so the last third reads as an oar rather than
    # a tube trailing off.
    squeeze = 1.15 - 0.42 * max(0.0, (t - 0.45) / 0.55)

    # THE KEEL. A raised ridge along the top where the dorsal fins root, tallest at the
    # shoulder. Without it the fins look glued to a smooth back.
    keel = 0.16 * max(0.0, vertical) ** 3 * math.exp(-((t - 0.32) ** 2) / 0.05)

    return across * radius * squeeze, vertical * radius * depth * (1.0 + keel)


def build_body(bm):
    rings = []
    for i in range(BODY_SEGMENTS + 1):
        t = i / BODY_SEGMENTS
        here, forward, right, up = frame_at(t)
        radius = girth(t)
        ring = []
        for j in range(BODY_AROUND):
            angle = j / BODY_AROUND * math.tau
            across, vertical = body_section(angle, t, radius)
            point = here + right * across + up * vertical
            # SKIN, applied along the surface normal rather than straight up, so a lump on
            # the flank pushes sideways instead of lifting the back.
            normal = (right * across + up * vertical).normalized()
            hide = fbm(point * 1.0, 11.0, 4) * 0.55 + fbm(point * 1.0, 3.1, 3) * 0.22
            # PLATES ON TOP, BELLY BELOW. The armour fades out under the waterline where the
            # body is soft, which is both true of the animal and free: nobody ever sees it.
            back = max(0.0, math.sin(angle))
            hide += SCALE_RISE * scale_relief(t, j / BODY_AROUND) * back
            ring.append(bm.verts.new(point + normal * hide))
        rings.append(ring)

    for a, b in zip(rings, rings[1:]):
        for j in range(BODY_AROUND):
            k = (j + 1) % BODY_AROUND
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))


def fin(bm, t: float, height: float, rake: float, tatter: float,
        around: float = math.pi / 2):
    """One dorsal fin: a solid tapering blade with a curved trailing edge.

    BUILT AS A RING PER STEP, not as a ribbon between two edge curves. The ribbon version was
    a single-sided sheet -- it had a leading and a trailing edge and no thickness at all
    between them, so the "solid" fin was a plane you could see through edge-on, and closing
    its tip meant asking for a face with the same vertex twice.

    Four points a step -- leading edge, two flanks, trailing edge -- makes it an actual blade
    with a section, which also means it catches light on one side and not the other. That
    shading difference is most of what makes a fin read as a fin at distance.

    The trailing edge carries the character: stiff and swept back at the front, sagging into
    a slack curve behind, bitten into by tears on the older ones. A straight trailing edge is
    a shark fin; a torn one is an old animal.
    """
    here, forward, right, up = frame_at(t)
    # WHERE ON THE BODY IT ROOTS, so the same builder can put a spine on the spine or low on
    # a flank. A single row down the back is a stegosaur; rows down the sides as well are
    # something that would be unpleasant to swim past on any side.
    across_v, up_v = body_section(around, t, girth(t))
    base = here + right * (across_v * 0.96) + up * (up_v * 0.96)
    # A flank spine leans out and down rather than straight up, following the surface it
    # grows from -- a spine sticking vertically out of a hip is a fence post.
    lean = right * math.cos(around) + up * math.sin(around)
    root = max(1.8, height * 0.42)

    rings = []
    steps = 6
    for s in range(steps + 1):
        f = s / steps
        # Grown along the surface normal it roots on, not always straight up.
        rise = height * f
        sweep = -forward * (height * rake * f * f)
        centre = base + lean * rise + sweep

        # Chord shrinks toward the tip; the trailing half sags and is notched by tears.
        # SHARPENED. At an exponent of 0.75 the chord held most of its width almost to the
        # tip and then rounded off, which with the sag below made every fin a leaf. Leaves
        # are not frightening. 1.5 pulls the width in early so the fin is a spike with a
        # curved trailing edge rather than a paddle.
        chord = root * (1.0 - f) ** 1.5
        sag = height * 0.13 * math.sin(f * math.pi)
        bite = 1.0 - tatter * 0.55 * max(0.0, math.sin(f * math.pi * 3.0))
        thick = max(0.18, height * 0.085 * (1.0 - f) ** 0.6)
        # The blade's own across-axis, perpendicular to both the body and the spine's lean.
        blade = forward.cross(lean).normalized()

        lead = centre + forward * chord
        trail = centre - forward * (chord * 1.25 * bite) - lean * (sag * 0.35) - forward * sag
        flank = centre - forward * (chord * 0.15)
        rings.append([
            bm.verts.new(lead),
            bm.verts.new(flank + blade * thick),
            bm.verts.new(trail),
            bm.verts.new(flank - blade * thick),
        ])

    for a, b in zip(rings, rings[1:]):
        for j in range(4):
            k = (j + 1) % 4
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))


# --------------------------------------------------------------------------- #
# The head
# --------------------------------------------------------------------------- #

# Along the skull, from behind the jaw hinge (-1) to the tip of the snout (+1):
# (position, half-width, top, bottom) as fractions of the head box.
SKULL = (
    # THE SNOUT CLOSES TO ALMOST NOTHING. Ending the run at a 0.16 half-width and capping it
    # with a fan left a four-stud flat disc on the front of the face -- a tube cut off with a
    # saw, which is the one thing that most reliably says "generated" rather than "grown".
    (1.09, 0.04, 0.02, -0.06),
    (1.00, 0.16, 0.10, -0.20),
    (0.90, 0.30, 0.26, -0.34),
    (0.74, 0.44, 0.40, -0.44),
    (0.54, 0.60, 0.54, -0.54),
    (0.30, 0.80, 0.66, -0.62),
    (0.06, 0.98, 0.82, -0.70),
    (-0.22, 1.00, 0.90, -0.74),
    (-0.52, 0.86, 0.74, -0.72),
    (-0.78, 0.62, 0.52, -0.66),
    (-1.00, 0.46, 0.34, -0.58),
)

# SHORTER AND DEEPER than the first proportions. At 34 long by 11 tall the skull was three
# times as long as it was deep, which is a crocodile -- a low snout that closes on a fish. A
# serpent's head in every reference is short, tall and heavy at the back, because the mass is
# jaw muscle. 28 by 15 moves it from reptile to dragon without touching a single vertex.
# BIGGER THAN THE NECK IT SITS ON, which it was not.
#
# A head narrower than its own neck is a snake's, and a snake swallows things whole -- it does
# not frighten anyone by biting them. Every predator that kills with its jaws carries a skull
# WIDER than the neck behind it, because the muscle that closes those jaws has to anchor
# somewhere and that somewhere is the back of the head.
#
# 36 x 19 against a neck that reaches 16 across is the right relationship, and it changes the
# read completely: the animal stops looking like a tube with a face drawn on the end and
# starts looking like something built around a bite.
HEAD_LEN, HEAD_WIDE, HEAD_TALL = 36.0, 19.0, 17.0

# The lower jaw's own stations, lifted out of build_jaw so the TEETH can read them too.
#
# They were private to the jaw builder, so every tooth was placed against hand-guessed
# constants instead -- a fixed height and a fixed distance out, on a jaw whose height and
# width change along its whole length. That is why the teeth floated: they were pinned to
# numbers that only happened to be right near the middle of the mouth.
JAW_STATIONS = (
    (0.94, 0.16, -0.30, -0.62),
    (0.72, 0.38, -0.46, -0.92),
    (0.44, 0.58, -0.66, -1.22),
    (0.10, 0.72, -0.84, -1.48),
    (-0.34, 0.70, -0.88, -1.54),
    (-0.66, 0.54, -0.80, -1.36),
)


def jaw_swing(along: float) -> float:
    """How far the lower jaw has dropped at this point along it.

    Shared by the jaw and by the teeth in it, because a tooth that does not swing with the
    jaw it is rooted in stays hanging in the air where the mouth used to be shut.
    """
    return -0.86 * max(0.0, (along + 0.66) / 1.60) ** 1.2


def station_at(table, along: float):
    """(half-width, top, bottom) anywhere along a station table, by interpolation.

    THE TEETH ARE ROOTED WITH THIS. A station table describes a surface only at the handful
    of places it lists; anything placed BETWEEN those places has to be interpolated or it is
    guessing. Guessing is what put the teeth outside the mouth.
    """
    if along >= table[0][0]:
        return table[0][1], table[0][2], table[0][3]
    if along <= table[-1][0]:
        return table[-1][1], table[-1][2], table[-1][3]
    for near, far in zip(table, table[1:]):
        if far[0] <= along <= near[0]:
            f = (near[0] - along) / (near[0] - far[0])
            return (near[1] + (far[1] - near[1]) * f,
                    near[2] + (far[2] - near[2]) * f,
                    near[3] + (far[3] - near[3]) * f)
    return table[-1][1], table[-1][2], table[-1][3]
EYE_AT = 0.16            # position along the skull
EYE_OUT = 0.86           # how far out to the side


def skull_profile(angle: float, half: float, top: float, bottom: float) -> tuple:
    """A cross-section of the cranium: flat cheeks, a ridged crown, a narrow underside."""
    across = math.cos(angle)
    vertical = math.sin(angle)
    mid, span = (top + bottom) / 2.0, (top - bottom) / 2.0
    # SUPERELLIPSE, so the cheek is a broad flat plane rather than a curve. Bone is faceted;
    # a circular section is a sausage.
    flat = 2.6
    shape = (abs(across) ** flat + abs(vertical) ** flat) ** (-1.0 / flat)
    return across * shape * half, mid + vertical * shape * span


def build_head(bm):
    here, forward, right, up = head_frame()

    def at(f, r, u):
        return here + forward * (HEAD_LEN * f) + right * (HEAD_WIDE * r) + up * (HEAD_TALL * u)

    eye_centres = []
    for side in (1, -1):
        eye_centres.append(at(EYE_AT, side * EYE_OUT * 0.86, 0.30))

    rings = []
    for along, half, top, bottom in SKULL:
        ring = []
        for j in range(HEAD_AROUND):
            angle = j / HEAD_AROUND * math.tau
            across, vertical = skull_profile(angle, half, top, bottom)
            point = at(along, across, vertical)

            # THE SOCKETS, cut by pulling the surface in toward each eye rather than by
            # booleaning a hole. A dent keeps the mesh closed and manifold, and at this
            # distance a recess reads as an eye socket exactly as well as a hole would.
            for centre in eye_centres:
                reach = (point - centre).length
                if reach < 5.4:
                    pull = (1.0 - reach / 5.4) ** 2 * 2.3
                    point = point + (centre - point).normalized() * pull

            # ---- GILL SLITS, raked back behind the jaw hinge.
            #
            # Cut as grooves rather than modelled as holes, for the same reason the eye
            # sockets are: a dent keeps the mesh closed, and at any distance a dark line
            # reads as a slit exactly as well as an opening would. Three of them, angled
            # back, because vertical slits read as decoration and raked ones read as
            # anatomy -- water goes in at the front and out behind.
            cut = 0.0
            if -0.86 < along < -0.30 and abs(math.cos(angle)) > 0.45:
                for slit in (-0.42, -0.56, -0.70):
                    # The rake: the slit sits further back the further DOWN the flank it is.
                    place = slit - 0.09 * math.sin(angle)
                    reach = abs(along - place)
                    if reach < 0.035:
                        cut = max(cut, (1.0 - reach / 0.035) * 0.9)

            # ---- SCARS. Three long gouges raked across the snout and cheek.
            #
            # Nothing else on this animal says it has SURVIVED anything. Armour and horns say
            # it is equipped; a healed wound says it has been in a fight and is still here,
            # which is a different and worse thought. They run across the grain of the plates
            # rather than along it, because that is how a claw crosses a body.
            #
            # Only on one flank. A matched pair of scars is a pattern, and a pattern is
            # decoration.
            scar = 0.0
            if math.sin(angle) > -0.30 and math.cos(angle) > 0.15:
                for place, lean, deep in ((0.52, 0.30, 0.60), (0.30, 0.24, 0.44),
                                          (0.08, 0.34, 0.34)):
                    line = place + lean * math.sin(angle)
                    reach = abs(along - line)
                    if reach < 0.045:
                        scar = max(scar, (1.0 - reach / 0.045) * deep)

            # ---- THROAT PLEATS, on the underside only.
            #
            # Loose skin under the jaw, folded in rings the way every big-mouthed hunter's is
            # -- it has to unfold when the jaw opens. Ridges rather than grooves, and only
            # below the midline, so from the side they show as a banded throat and from above
            # they are not there at all.
            pleat = 0.0
            if math.sin(angle) < -0.25 and along > -0.70:
                band = math.sin(along * 26.0) * 0.5 + 0.5
                pleat = (band ** 2.4) * 0.55 * (-math.sin(angle) - 0.25) / 0.75

            # Hide: coarser than the body's, because a skull is plated rather than fleshy.
            normal = (point - at(along, 0, (top + bottom) / 2.0))
            if normal.length > 1e-6:
                normal.normalize()
                # ASYMMETRIC. A skull that mirrors to the millimetre is a prop, so one flank
                # carries more damage than the other -- the noise is sampled at a point
                # nudged sideways, which breaks the mirror without needing a second pass.
                skew = point + Vector((0, 2.4, 0))
                point = point + normal * (
                    fbm(skew, 7.0, 4) * 0.46
                    + fbm(skew, 2.2, 2) * 0.24
                    + pleat
                    - cut
                    - scar)
            ring.append(bm.verts.new(point))
        rings.append(ring)

    for a, b in zip(rings, rings[1:]):
        for j in range(HEAD_AROUND):
            k = (j + 1) % HEAD_AROUND
            bm.faces.new((a[j], a[k], b[k], b[j]))
    for k in range(1, HEAD_AROUND - 1):
        bm.faces.new((rings[0][0], rings[0][k + 1], rings[0][k]))
        bm.faces.new((rings[-1][0], rings[-1][k], rings[-1][k + 1]))

    return at, eye_centres


def build_eye(bm, centre: Vector, look: Vector):
    """An actual eyeball set in its socket, with a slit pupil ridge over it.

    A socket with nothing in it reads as damage. The eye only has to be a sphere that catches
    light differently from the hide around it -- what makes it read as WATCHING is that it
    protrudes very slightly from the recess, so it holds a highlight the skull does not.
    """
    # Bigger, now that the skull is. An eye that shrinks as the head grows reads as a
    # different animal -- a small eye in a big head is a grazer, because it does not need to
    # judge distance to something that is running away.
    radius = 3.1
    stacks, slices = 9, 14
    grid = []
    for s in range(stacks + 1):
        phi = s / stacks * math.pi
        row = []
        for r in range(slices):
            theta = r / slices * math.tau
            offset = Vector((
                math.sin(phi) * math.cos(theta),
                math.sin(phi) * math.sin(theta),
                math.cos(phi)))
            # Slightly lens-shaped rather than spherical, bulging along the look direction.
            point = centre + offset * radius + look * (offset.dot(look) * 0.45)
            row.append(bm.verts.new(point))
        grid.append(row)
    for s in range(stacks):
        for r in range(slices):
            q = (r + 1) % slices
            bm.faces.new((grid[s][r], grid[s][q], grid[s + 1][q], grid[s + 1][r]))


def build_brow(bm, at, side: int):
    """A bone shelf over the eye, jutting out past the socket.

    THE ONE FEATURE THAT MAKES A FACE LOOK ANGRY. A brow is a shadow: it hangs over the eye
    so the socket is dark from every direction above, and an eye you cannot quite see into is
    worse than one you can. It is also why birds of prey look fierce and doves do not -- the
    skull, not the expression.

    Jutting out PAST the eye rather than merely above it, because a ridge flush with the
    socket casts nothing.
    """
    # ROOTED ON THE SKULL, by reading the same table the skull is built from.
    #
    # This used hand-picked numbers for how far out and how high the ridge ran, and the skull
    # underneath is not a constant width -- it is 0.70 of a half-width at the snout end of the
    # sweep and 1.00 at the cheek. So the ridge started BURIED, came out 0.10 proud through
    # the middle, and went back under at the far end: a bar floating over the face, attached
    # at neither end. Exactly the same mistake the teeth had, in a different place.
    #
    # Now every station reads the skull's actual half-width there and sits just inside it,
    # with an overhang that rises and falls to nothing at both ends -- so the ridge grows out
    # of the face, juts over the eye, and dies back into the cheek.
    rings = []
    steps = 7
    for s in range(steps + 1):
        f = s / steps
        along = 0.46 - 0.66 * f
        half, top, _ = station_at(SKULL, along)
        thick = 1.4 + 2.0 * math.sin(f * math.pi)
        # Inside the surface by a little less than the ridge is thick, so the two always meet.
        out = half * 0.90 + 0.17 * math.sin(f * math.pi)
        # Just below the crown, which is where a brow is -- above the eye and under the skull's
        # own high line.
        rise = top * 0.74
        ring = []
        for j in range(5):
            angle = j / 5 * math.tau
            ring.append(bm.verts.new(at(
                along + math.cos(angle) * thick / HEAD_LEN,
                side * out,
                rise + math.sin(angle) * thick / HEAD_TALL)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for j in range(5):
            k = (j + 1) % 5
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))


def build_jaw(bm, at):
    """The lower jaw, hinged open. An open mouth is the difference between something
    swimming past and something that has noticed you."""
    # Depth roughly doubled from the first build, and growing toward the hinge: a jaw is
    # mostly MUSCLE and the muscle is at the back where the leverage is. Shallower than this
    # it was a rod with teeth glued to it, and read as exactly that.
    stations = JAW_STATIONS
    rings = []
    for along, half, top, bottom in stations:
        # The gape: the jaw swings down about the hinge at the back, so the drop grows
        # toward the snout rather than being a constant offset.
        # WIDER. At 0.42 the mouth was ajar; the references are all wide open, and a gape is
        # the difference between a creature that is there and one that is about to do
        # something. The exponent keeps the hinge tight so it still swings rather than
        # detaching.
        swing = jaw_swing(along)
        ring = []
        for j in range(14):
            angle = j / 14 * math.tau
            across, vertical = skull_profile(angle, half, top + swing, bottom + swing)
            point = at(along, across, vertical)
            point = point + Vector((0, 0, 0))
            ring.append(bm.verts.new(point))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for j in range(14):
            k = (j + 1) % 14
            bm.faces.new((a[j], a[k], b[k], b[j]))
    for k in range(1, 13):
        bm.faces.new((rings[0][0], rings[0][k + 1], rings[0][k]))
        bm.faces.new((rings[-1][0], rings[-1][k], rings[-1][k + 1]))


def build_tooth(bm, at, along: float, side: int, out: float, up_at: float,
                length: float, curve: float):
    """One tooth: a tapered, backward-curving cone rather than a straight spike.

    The curve is the whole point. A straight cone is a traffic bollard; teeth hook backward,
    and the hook is visible in silhouette even when the tooth is two pixels wide.
    """
    rings = []
    steps = 4
    for s in range(steps + 1):
        f = s / steps
        radius = (1.0 - f) ** 0.8 * 0.62
        # Backward hook, growing with height.
        back = -curve * f * f
        centre_f = along + back
        centre_u = up_at - length * f if length > 0 else up_at - length * f
        ring = []
        for j in range(5):
            angle = j / 5 * math.tau
            ring.append(bm.verts.new(at(
                centre_f + math.cos(angle) * radius * 0.045,
                side * out + math.sin(angle) * radius * 0.05,
                centre_u)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for j in range(5):
            k = (j + 1) % 5
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))



def horn_axis(at, along: float, side: int, out: float, rise: float, sweep: float,
              steps: int = 8):
    """The centreline of one crest spine, as a list of points.

    PULLED OUT OF build_horn so the WEBBING can use it too. A membrane between two spines has
    to follow exactly the curves the spines themselves follow, and the only way to guarantee
    that is for both to be generated from the same function rather than from two descriptions
    that agree today.
    """
    return [at(along - sweep * (s / steps) ** 2,
               side * (out + 0.30 * (s / steps)),
               0.62 + rise * (s / steps))
            for s in range(steps + 1)]


def web(bm, inner, outer, sag: float, tear: float):
    """The membrane between two crest spines.

    THIS IS WHAT TURNS SPIKES INTO A FRILL, and it is the biggest single change to the
    outline. Six separate spines read as a row of thorns; the same six with skin stretched
    between them read as one structure that has been RAISED -- and a raised frill is a threat
    display, which is the thing the whole creature is for.
    """
    steps = len(inner) - 1
    left, right = [], []
    for s in range(steps + 1):
        f = s / steps
        # The membrane does not reach the tips: skin runs out before bone does, so the last
        # of each spine stands clear. That gap is what keeps them reading as spines.
        #
        # AT 1.45 IT RAN OUT AT TWO THIRDS and the frill was a stub round the roots -- from
        # any distance the crest went back to being a spray of loose spikes, which is the one
        # thing the webbing exists to prevent. 1.08 leaves only the last hand's width of each
        # spine bare, so the fan is skin with bone through it rather than bone with a hem.
        span = max(0.0, 1.0 - f * 1.08)
        # And it hangs. A taut sheet is a sail; a slack one is an animal.
        drop = sag * math.sin(f * math.pi) * (1.0 - tear * 0.6)
        a, b = inner[s], outer[s]
        edge = a.lerp(b, min(1.0, span))
        left.append(bm.verts.new(a + Vector((0, 0, -drop * 0.15))))
        right.append(bm.verts.new(edge + Vector((0, 0, -drop))))
    # ONE SHEET, and MeshPart.DoubleSided does the rest.
    #
    # The membrane has no thickness, which at this size is right -- skin stretched between two
    # spines is a film, and giving it two studs of depth would make it a wall. But a
    # zero-thickness sheet is invisible from behind, and adding the same face wound the other
    # way is not the fix: bmesh identifies a face by its vertices, so the reversed copy is the
    # SAME face and it refuses to make it twice.
    #
    # HubService sets DoubleSided on the head part, which is the property that exists for
    # exactly this and costs no geometry at all.
    for s in range(steps):
        bm.faces.new((left[s], right[s], right[s + 1], left[s + 1]))


def build_horn(bm, at, along: float, side: int, out: float, rise: float,
               sweep: float, thick: float):
    """A swept, tapering, twisted horn -- round in section, not a flat plate.

    THE RING HAS TO BE MEASURED IN STUDS. `at` takes fractions of the head box, and that box
    is 34 long by 13 wide by 11 tall -- so an offset of "0.3" means nine studs forward, four
    studs sideways and three studs up. Building the ring from one radius in those units gave
    every horn a section three times wider than it was tall: flat plates standing off the
    skull, which is what the render showed.

    Dividing each component by its own box dimension makes the radius mean the same distance
    in all three directions, and the horn comes out round.

    The ring lies in the horizontal plane because these horns rise far more than they spread,
    so that plane is very nearly perpendicular to the horn's own axis.
    """
    axis = horn_axis(at, along, side, out, rise, sweep)
    rings = []
    steps = len(axis) - 1
    for s in range(steps + 1):
        f = s / steps
        radius = thick * (1.0 - f) ** 0.7          # studs
        centre_f = along - sweep * f * f
        centre_r = side * (out + 0.30 * f)
        centre_u = 0.62 + rise * f
        ring = []
        for j in range(7):
            # The twist: each ring turned a little further than the one below, so the horn
            # has a spiral ridge running up it rather than being a smooth cone.
            angle = j / 7 * math.tau + f * 1.4
            wobble = 1.0 + 0.22 * math.cos(angle * 3.0)     # a fluted, not circular, section
            ring.append(bm.verts.new(at(
                centre_f + math.cos(angle) * radius * wobble / HEAD_LEN,
                centre_r + math.sin(angle) * radius * wobble / HEAD_WIDE,
                centre_u)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for j in range(7):
            k = (j + 1) % 7
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))


# --------------------------------------------------------------------------- #

def finish(bm, name: str):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    # Unwrapped along the long axis: one wrap, no repeats. A box projection on something
    # three hundred studs long tiles dozens of times and destroys any gradient drawn on it.
    xs = [v.co.x for v in mesh.vertices]
    low, span = min(xs), (max(xs) - min(xs)) or 1.0
    mesh.uv_layers.new(name="UVMap")
    uv = mesh.uv_layers.active.data
    for poly in mesh.polygons:
        for loop_index in poly.loop_indices:
            co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv[loop_index].uv = ((math.atan2(co.z, co.y) / math.tau) % 1.0, (co.x - low) / span)
    return obj


def export(obj):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, obj.name + ".fbx")
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True, global_scale=0.01, add_leaf_bones=False,
        bake_anim=False, axis_forward="-Z", axis_up="Y", object_types={"MESH"},
        mesh_smooth_type="FACE")
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    ceiling = "" if tris <= 10000 else "   !! OVER ROBLOX'S 10000-TRIANGLE MESH LIMIT"
    print("    %-22s %6d tris%s" % (obj.name, tris, ceiling))
    return tris



def flipper(bm, t: float, side: int, length: float, rake: float):
    """A steering paddle at the shoulder: broad at the root, swept to a blunt point.

    THE ONE THING THAT SAYS IT SWIMS. A body and a head and a row of fins along the spine
    describe a shape in water; a limb describes an ANIMAL in water. It is also the only
    feature here that reads as bilateral, so it is what tells the eye the far side exists.
    """
    here, forward, right, up = frame_at(t)
    root = here + right * (girth(t) * side * 0.86) - up * (girth(t) * 0.30)

    rings = []
    steps = 6
    for s in range(steps + 1):
        f = s / steps
        # Swept back and drooping as it reaches out, the way a paddle held against a current
        # does. A flipper straight out to the side reads as a plank.
        centre = (root
            + right * (side * length * f)
            - forward * (length * rake * f * f)
            - up * (length * 0.22 * f * f))
        chord = length * 0.52 * (1.0 - f * f * 0.72)
        thick = max(0.22, length * 0.075 * (1.0 - f) ** 0.7)
        rings.append([
            bm.verts.new(centre + forward * chord),
            bm.verts.new(centre + up * thick),
            bm.verts.new(centre - forward * chord * 1.12),
            bm.verts.new(centre - up * thick),
        ])
    for a, b in zip(rings, rings[1:]):
        for j in range(4):
            k = (j + 1) % 4
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))


def fluke(bm, t: float, height: float):
    """A vertical tail fin, mostly drowned.

    Deliberately the LAST thing above water and barely that. A fluke fully out of the sea
    tells you where the animal ends, and not knowing where it ends is the entire reason the
    body was built to trail off in the first place. This is a hint that there is a tail, not
    a display of one.
    """
    here, forward, right, up = frame_at(t)
    rings = []
    steps = 5
    for s in range(steps + 1):
        f = s / steps
        centre = here + up * (height * f) - forward * (height * 0.55 * f * f)
        chord = height * 0.44 * (1.0 - f) ** 0.9
        thick = max(0.16, height * 0.06 * (1.0 - f))
        rings.append([
            bm.verts.new(centre + forward * chord),
            bm.verts.new(centre + right * thick),
            bm.verts.new(centre - forward * chord * 1.4),
            bm.verts.new(centre - right * thick),
        ])
    for a, b in zip(rings, rings[1:]):
        for j in range(4):
            k = (j + 1) % 4
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))


def build_body_mesh():
    bm = bmesh.new()
    build_body(bm)
    t, index = 0.10, 0
    while t < 0.80:
        wobble = math.sin(index * 2.399) * 0.5 + math.sin(index * 5.077 + 1.3) * 0.5
        falloff = math.exp(-((t - 0.30) ** 2) / 0.06)
        height = (6.5 + 18.0 * falloff) * (0.70 + 0.44 * (wobble * 0.5 + 0.5))
        fin(bm, t, height, 0.34 + 0.20 * wobble, abs(wobble) * 0.5)
        t += 0.024 + 0.020 * (1.0 - falloff) + 0.007 * wobble
        index += 1

    # TWO MORE ROWS, low on the flanks and raked back. The dorsal row alone leaves the body
    # a smooth tube seen from anywhere but directly side-on; these break the outline from
    # above and below as well, so there is no angle the animal looks harmless from.
    #
    # Shorter than the dorsals and set further apart, because a flank bristling as densely as
    # the spine reads as a caterpillar rather than as armour.
    t, index = 0.16, 0
    while t < 0.72:
        wobble = math.sin(index * 3.117) * 0.5 + math.sin(index * 4.331 + 0.9) * 0.5
        falloff = math.exp(-((t - 0.34) ** 2) / 0.07)
        height = (3.4 + 7.6 * falloff) * (0.68 + 0.44 * (wobble * 0.5 + 0.5))
        for side in (1, -1):
            fin(bm, t, height, 0.52 + 0.18 * wobble, abs(wobble) * 0.7,
                around=side * 0.30 * math.pi)
        t += 0.042 + 0.026 * (1.0 - falloff)
        index += 1

    # A pair of flippers at the shoulder, and one further back at half the size -- a long
    # animal has more than one pair, and the second says the body goes on doing things after
    # the part you were looking at.
    for side in (1, -1):
        flipper(bm, 0.36, side, 26.0, 0.42)
        flipper(bm, 0.62, side, 15.0, 0.55)
    fluke(bm, 0.965, 13.0)
    return finish(bm, "Hub_Leviathan_Body")



def barbel(bm, at, along: float, side: int, out: float, drop: float, length: float,
           thick: float):
    """A whisker hanging off the jaw: long, limp and tapering to nothing.

    Straight out of the engraving. Barbels do something no horn can: they hang DOWN, so they
    break the one edge of the silhouette everything else leaves alone, and they are the only
    part of the animal that looks soft. A creature made entirely of spikes and plates reads
    as armour; two or three drooping whiskers make the rest of it read as alive.

    Curved forward as they fall, because they trail -- a barbel hanging straight down belongs
    on something that is not moving.
    """
    rings = []
    steps = 7
    for s in range(steps + 1):
        f = s / steps
        radius = thick * (1.0 - f) ** 0.55
        centre = at(along + length * 0.42 * f * f,
                    side * (out + 0.10 * f),
                    drop - length * f)
        ring = []
        for j in range(5):
            angle = j / 5 * math.tau
            ring.append(bm.verts.new(centre + Vector((
                math.cos(angle) * radius,
                math.sin(angle) * radius,
                0.0))))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for j in range(5):
            k = (j + 1) % 5
            bm.faces.new((a[j], a[k], b[k], b[j]))
    bm.faces.new(tuple(reversed(rings[0])))
    bm.faces.new(tuple(rings[-1]))


def build_head_mesh():
    bm = bmesh.new()
    at, eyes = build_head(bm)
    _, forward, right, up = head_frame()
    for index, centre in enumerate(eyes):
        side = 1 if index == 0 else -1
        build_eye(bm, centre, (right * side * 0.8 + forward * 0.5 + up * 0.2).normalized())
    for side in (1, -1):
        build_brow(bm, at, side)
        # A horn straight off the brow, over the eye. The crest is behind the skull and
        # reads as a frill; this one sits on the FACE, so it is in every view of the head
        # including the one where the animal is looking at you.
        # Rooted the same way: started well inside the skull's half-width at that station so
        # its base is buried and it emerges through the surface, rather than beginning in mid
        # air beside the head.
        eye_half, eye_top, _ = station_at(SKULL, 0.20)
        build_horn(bm, at, 0.20, side, eye_half * 0.74, eye_top * 0.80, 0.30, 1.7)
    build_jaw(bm, at)

    # TEETH. Uneven lengths, two gaps, upper and lower interlocking.
    # FOURTEEN A SIDE, TOP AND BOTTOM, and the front four are fangs.
    #
    # Ten short pegs read as a comb. What is frightening about a mouth is that the teeth are
    # too long to close over -- they stand outside the lip, they interlock, and the ones at
    # the front are half again the length of the ones at the back. Nothing else in the whole
    # model does as much work per triangle as this does.
    for i in range(14):
        along = 0.94 - i * 0.135
        # Two gaps, at different places top and bottom, so the sets do not mirror.
        if i in (5, 11):
            continue
        # Longest at the front. The curve is deliberately steep: a gradual taper reads as a
        # saw, and a saw is a tool rather than a threat.
        front = max(0.0, (along + 0.30) / 1.24) ** 1.6
        scale = (0.52 + 0.92 * front) * (0.82 + 0.30 * abs(math.sin(i * 2.1)))
        # ROOTED IN THE SURFACE, not at a constant.
        #
        # The upper teeth grow out of the bottom edge of the upper jaw and the lower ones out
        # of the top edge of the lower jaw, and both of those edges move -- they are shallow
        # and narrow at the snout and deep and wide at the hinge. Reading the actual station
        # tables puts every tooth in the gum it belongs to instead of on a plane that only
        # crossed the mouth somewhere near the middle.
        #
        # 0.82 of the half-width sets them just inside the outer face, which is where a tooth
        # sits: proud enough to catch light down its outside edge, not stuck on the cheek.
        half, _, bottom = station_at(SKULL, along)
        for side in (1, -1):
            build_tooth(bm, at, along, side, half * 0.82, bottom + 0.03,
                        0.34 * scale, 0.13 * scale)
        if i in (2, 9):
            continue
        jaw_half, jaw_top, _ = station_at(JAW_STATIONS, along - 0.068)
        for side in (1, -1):
            # Offset half a tooth so the two sets interlock rather than meeting point to
            # point -- what real jaws do, and what makes a gape read as closable.
            #
            # Swung with the jaw, because a tooth that stays put while its jaw drops is left
            # hanging in the air where the mouth used to be shut.
            build_tooth(bm, at, along - 0.068, side, jaw_half * 0.82,
                        jaw_top + jaw_swing(along - 0.068) - 0.03,
                        -0.30 * scale, 0.11 * scale)

    # THE CREST. Not two horns -- a FAN of them radiating off the back of the skull, which
    # is the feature every sea-serpent worth the name has and the one thing a pair of horns
    # cannot stand in for. A pair reads as a bull; a fan reads as a frill raised in threat,
    # and it is the silhouette that carries at distance.
    #
    # The fan is swept through an arc: the innermost spines stand nearly straight up off the
    # crown, and each one further out lies flatter and further back, so the outline is a
    # continuous sweep rather than a row of pickets. Lengths taper outward, and the whole
    # set is thrown backward hard, as if the animal is moving forward through it.
    for side in (1, -1):
        axes = []
        for index in range(6):
            f = index / 5.0
            # Inner spines: high, upright, long. Outer: low, raked back, shorter.
            #
            # MEASURED AGAINST THE SKULL rather than set as an absolute. At a flat 0.16..1.18
            # the outermost pair of the fan sat 0.26 beyond the actual half-width at their own
            # station -- the last floaters over the snout. Scaling by the local half-width
            # keeps the fan spreading exactly as it did while guaranteeing every root stays
            # buried: 0.30 of the width at the inside, 0.96 at the outside.
            crest_half, _, _ = station_at(SKULL, -0.10 - 0.34 * f)
            out = crest_half * (0.30 + 0.66 * f)
            rise = 2.35 - 1.35 * f * f
            sweep = 0.44 + 0.62 * f
            thick = 3.2 - 1.6 * f
            # Never evenly spaced. An even fan is a comb, and the eye finds a comb instantly.
            along = -0.10 - 0.34 * f + 0.06 * math.sin(index * 2.7)
            build_horn(bm, at, along, side, out, rise, sweep, thick)
            axes.append(horn_axis(at, along, side, out, rise, sweep))

        # THE WEBBING, between each neighbouring pair. Sag grows outward so the frill droops
        # at its trailing edge, and one panel per side is torn -- an intact frill on something
        # this old would be the only undamaged thing on it.
        for index in range(len(axes) - 1):
            # deeper toward the outside, so the frill's trailing edge scallops instead of
            # running straight. A straight-edged frill is a fan; a scalloped one is skin.
            web(bm, axes[index], axes[index + 1],
                sag=2.6 + 3.4 * (index / 4.0),
                tear=1.0 if index == 3 else 0.0)
        # Two more off the JAW itself, low and forward, so the crest wraps the face rather
        # than sitting on top of it like a hat.
        # THE FLOATING ONES. These two sat at 0.92 and 0.74 out, on a snout whose actual
        # half-width there is 0.77 and 0.57 -- so both hung clear of the face by about a
        # sixth of its width, and their bases started ABOVE the skull's top line as well.
        # From the front they read as a handful of teeth hanging in the air over the nose,
        # which is exactly what they looked like.
        #
        # Rooted on the surface now, like everything else on this head: inside the local
        # half-width so the base is buried, and starting below the local crown so the spine
        # emerges through the skin rather than beginning beside it.
        for place, rise, sweep, thick in ((0.34, 0.30, 0.22, 1.3), (0.58, 0.22, 0.14, 1.0)):
            jaw_half, jaw_top, _ = station_at(SKULL, place)
            build_horn(bm, at, place, side, jaw_half * 0.78, rise, sweep, thick)

        # BARBELS off the jawline. Three a side at different lengths, because two matched
        # pairs read as a moustache and three uneven ones read as something that grew.
        barbel(bm, at, 0.56, side, 0.52, -1.10, 0.95, 0.55)
        barbel(bm, at, 0.30, side, 0.64, -1.16, 1.35, 0.62)
        barbel(bm, at, 0.02, side, 0.58, -1.12, 0.72, 0.44)

    return finish(bm, "Hub_Leviathan_Head")


def add_anchor(obj, point: Vector, size: float = 0.02):
    """A speck of geometry at a fixed point, purely to stretch the bounding box.

    THIS IS HOW THE TWO HALVES ARE JOINED, and it replaces two rounds of arithmetic that were
    wrong in two different ways.

    Roblox positions a MeshPart by its bounding-box CENTRE. Two meshes modelled in one scene
    therefore do NOT line up when dropped at one point -- their centres stack and the real
    distance between them is discarded. The obvious repair is to measure that distance and add
    it back, which is what the last two attempts did: first in studs (wrong, because nothing
    guarantees a Blender unit arrives as a stud), then as a fraction of the body (right about
    scale, still relying on my reading of how the exporter maps Blender's axes onto Roblox's
    -- and the head came out on the wrong END of the animal, which is what a sign error in
    that mapping looks like).

    Both attempts were solving the wrong problem. If the two meshes share ONE bounding box,
    they share one centre, and dropping them at the same CFrame lines them up exactly -- with
    no offset, no axis conversion, and nothing for me to get the sign of wrong.

    So each mesh gets two invisible specks, at the two opposite corners of the box that
    encloses BOTH. Four triangles each, two hundredths of a stud across, six hundred studs
    from the camera. They cannot be seen and they cannot be wrong.
    """
    mesh = obj.data
    work = bmesh.new()
    work.from_mesh(mesh)
    a = work.verts.new(point)
    b = work.verts.new(point + Vector((size, 0, 0)))
    c = work.verts.new(point + Vector((0, size, 0)))
    d = work.verts.new(point + Vector((0, 0, size)))
    work.faces.new((a, b, c))
    work.faces.new((a, c, d))
    work.faces.new((a, d, b))
    work.faces.new((b, d, c))
    work.to_mesh(mesh)
    work.free()


def bounds_of(obj):
    xs = [v.co.x for v in obj.data.vertices]
    ys = [v.co.y for v in obj.data.vertices]
    zs = [v.co.z for v in obj.data.vertices]
    return (Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs))))


def main():
    clear_scene()
    pieces = [build_head_mesh(), build_body_mesh()]

    # The box that holds both, before either is anchored.
    low = Vector((1e9, 1e9, 1e9))
    high = Vector((-1e9, -1e9, -1e9))
    for obj in pieces:
        lo, hi = bounds_of(obj)
        low = Vector((min(low.x, lo.x), min(low.y, lo.y), min(low.z, lo.z)))
        high = Vector((max(high.x, hi.x), max(high.y, hi.y), max(high.z, hi.z)))

    # Both corners on both meshes, so both bounding boxes become that shared box exactly.
    for obj in pieces:
        add_anchor(obj, low)
        add_anchor(obj, high - Vector((0.02, 0.02, 0.02)))

    total = 0
    for obj in pieces:
        total += export(obj)

    # WHERE THE MODELLED WATERLINE SITS INSIDE THAT BOX.
    #
    # The whole creature is designed around z = 0 being the surface -- the back breaks it, the
    # neck rises out of it, the belly is under it. But the box that encloses everything is
    # dominated by the reared neck and the crest, which are ALL above the water, so its centre
    # sits a long way above z = 0.
    #
    # Roblox places the part by that centre. So dropping it at sea level does not put the
    # waterline at sea level -- it sinks the animal by the whole distance between the two, and
    # what shows is the little that happens to poke back out.
    #
    # Printed as a fraction of the box height, for the same reason the head offset was: it is
    # then immune to the export scale, the import fitting and the Size multiplier alike.
    tall = high.z - low.z
    centre_z = (low.z + high.z) / 2.0
    print("")
    print("  HubService LEVIATHAN_WATERLINE (raise by this fraction of the part's height):")
    print("    %.4f" % (centre_z / tall))
    print("    (box spans z %.1f .. %.1f, so its centre is %.1f above the modelled surface)"
          % (low.z, high.z, centre_z))
    print("")
    print("  Both meshes now share one bounding box, %.0f x %.0f x %.0f."
          % (high.x - low.x, high.y - low.y, high.z - low.z))
    print("  Place them at the SAME CFrame in HubService -- no offset, no axis conversion.")
    print("    %-22s %6d tris across both meshes" % ("(combined)", total))
    print("")
    print("Import BOTH into ReplicatedStorage/Assets/TileMeshes.")


if __name__ == "__main__":
    main()
