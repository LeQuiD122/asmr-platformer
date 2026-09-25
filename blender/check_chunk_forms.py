"""
Asserts the chunk layout contract. Plain Python, no Blender:

    python check_chunk_forms.py

Run this before pasting ChunkBuilder into Studio. The Studio loop for a geometry
change is paste, clear ServerStorage.ChunkTemplates and
ReplicatedStorage.Assets.Chunks, Play, walk to the chunk -- minutes per attempt,
and the failures it catches are the boring ones: a taper that pinched an entry
face below a jump target, a shelf buried inside its neighbour, a ramp piece
landing a stud off the slope so the chunk no longer meets a flat one flush.

The silhouette itself is a judgement call and belongs in render_chunk_forms.py.
This file only checks the things that have a right answer.
"""

import math
import os
import pathlib
import re
import sys

import chunk_layout as CL

ROOT_DIR = pathlib.Path(os.path.dirname(os.path.abspath(__file__))).parent
LEVELS = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "src", "Shared", "LevelDefinitions.lua"))

# A default jump clears about 8.2 studs horizontally and 6.4 vertically at
# WalkSpeed 16 / JumpPower 50 (see the GAP_LENGTH note in ChunkBuilder). Held
# slightly under, because a takeoff off honey is slower and off butter-wax is
# not where you intended.
MAX_GAP = 8.0

# Faces are jump targets and the route always arrives on the centre line, so a
# face has to be wide enough to land on and has to straddle X = 0. Rule 1 in
# ChunkBuilder's silhouette notes.
MIN_FACE_WIDTH = 10.0
FACE_MUST_CONTAIN = 1.5  # character half-width, roughly

# Two slabs meeting along Z are walked between, not jumped, so their lateral
# ranges have to share enough width to actually stand in.
MIN_LATERAL_OVERLAP = 4.0

EPS = 0.01

# (chunk, material, sizeX, sizeZ) allowed to fall back to per-tile meshes on purpose.
#
# EMPTY, and it should stay that way. It used to hold P4 and C1's 16 x 12 honey, on the
# stated grounds that keeping one unrigged size made both approaches visible in a single
# run. That was a rationalisation of a missing asset: honey is the flagship material and
# two of its three slabs did not deform at all. There is a 16 x 12 rig now.
#
# Anything added back here buys a silent failure -- a slab that looks approximately right
# and never responds -- which is the exact class of bug this checker exists to catch.
INTENTIONAL_FALLBACK = set()

failures = []
notes = []


def fail(chunk_id, message):
    failures.append("%-24s %s" % (chunk_id, message))


def aabb(box):
    """World-axis bounds. Only the ramp is pitched, but it is pitched enough that
    treating its pieces as unrotated would misreport both their length and their
    height."""
    c, s = abs(math.cos(box.pitch)), abs(math.sin(box.pitch))
    hz = box.sz / 2.0 * c + box.sy / 2.0 * s
    hy = box.sz / 2.0 * s + box.sy / 2.0 * c
    return (box.x - box.sx / 2.0, box.x + box.sx / 2.0,
            box.y - hy, box.y + hy,
            box.z - hz, box.z + hz)


def is_shelf(box, boxes):
    """A shelf is a slab sitting below the run it flanks. Identified by geometry
    rather than by name so it keeps working if the naming changes."""
    for other in boxes:
        if other is box:
            continue
        if other.y > box.y + EPS and other.z - other.sz / 2.0 < box.z + EPS \
                and other.z + other.sz / 2.0 > box.z - EPS:
            return True
    return False


def union_width(ranges):
    """Total covered width, and whether the cover straddles the centre line."""
    ordered = sorted(ranges)
    total, contains, cur = 0.0, False, None
    for lo, hi in ordered:
        if cur and lo <= cur[1] + EPS:
            cur = (cur[0], max(cur[1], hi))
        else:
            if cur:
                total += cur[1] - cur[0]
                contains = contains or (cur[0] <= -FACE_MUST_CONTAIN and cur[1] >= FACE_MUST_CONTAIN)
            cur = (lo, hi)
    if cur:
        total += cur[1] - cur[0]
        contains = contains or (cur[0] <= -FACE_MUST_CONTAIN and cur[1] >= FACE_MUST_CONTAIN)
    return total, contains


def check_faces(chunk_id, boxes):
    """Entry and exit faces: wide enough to land on, and straddling X = 0.

    Only the slabs at the face's HIGHEST level count. A shelf reaches the same Z
    but sits a step down, so counting it would let a chunk pass on the strength
    of a ledge nobody is aiming for."""
    bounds = [aabb(b) for b in boxes]
    z_min = min(b[4] for b in bounds)
    z_max = max(b[5] for b in bounds)

    for label, edge, key in (("entry", z_min, 4), ("exit", z_max, 5)):
        at_edge = [(box, bb) for box, bb in zip(boxes, bounds) if abs(bb[key] - edge) < 0.5]
        top = max(bb[3] for _, bb in at_edge)
        ranges = [(bb[0], bb[1]) for _, bb in at_edge if bb[3] > top - EPS]
        width, contains = union_width(ranges)
        if width < MIN_FACE_WIDTH - EPS:
            fail(chunk_id, "%s face is %.1f studs wide, under the %.0f a jump target needs"
                 % (label, width, MIN_FACE_WIDTH))
        if not contains:
            fail(chunk_id, "%s face does not straddle X = 0; the route arrives on the centre line"
                 % label)


def check_route(chunk_id, boxes):
    """No hole along Z bigger than a jump, and no step sideways wider than the
    slabs share."""
    main = [(b, aabb(b)) for b in boxes if not is_shelf(b, boxes)]
    spans = sorted(((bb[4], bb[5], bb[0], bb[1]) for _, bb in main))

    covered = spans[0][1]
    for lo, hi, _, _ in spans[1:]:
        if lo > covered + EPS:
            gap = lo - covered
            if gap > MAX_GAP:
                fail(chunk_id, "%.1f-stud hole in the route at Z %.1f, past the %.1f a jump clears"
                     % (gap, covered, MAX_GAP))
        covered = max(covered, hi)

    # Lateral continuity, checked only where one slab HANDS OFF to the next along
    # the route -- B starting where A ends. Two other arrangements look the same
    # to a naive sort by Z and are both fine:
    #
    #   across a deliberate gap you are airborne and free to steer;
    #   slabs that overlap in Z are running side by side, not in sequence, and
    #   meet along a shared lateral edge you simply walk across. S2's arm is the
    #   whole point of that chunk and shares exactly 0 studs with the main run by
    #   this measure, which says nothing about whether you can get onto it.
    for i in range(len(spans) - 1):
        lo_a, hi_a, x0a, x1a = spans[i]
        lo_b, hi_b, x0b, x1b = spans[i + 1]
        if lo_b > hi_a + EPS or lo_b < hi_a - EPS:
            continue
        overlap = min(x1a, x1b) - max(x0a, x0b)
        if overlap < MIN_LATERAL_OVERLAP - EPS:
            fail(chunk_id, "slabs meeting at Z %.1f share only %.1f studs laterally; "
                 "under %.0f there is no line through" % (lo_b, overlap, MIN_LATERAL_OVERLAP))


def check_overlaps(chunk_id, boxes):
    bounds = [aabb(b) for b in boxes]
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, b = bounds[i], bounds[j]
            # The ramp's pieces genuinely share their seams once the pitch is
            # flattened into an AABB, so they are not interpenetration.
            if boxes[i].pitch or boxes[j].pitch:
                continue
            ox = min(a[1], b[1]) - max(a[0], b[0])
            oy = min(a[3], b[3]) - max(a[2], b[2])
            oz = min(a[5], b[5]) - max(a[4], b[4])
            if ox > EPS and oy > EPS and oz > EPS:
                fail(chunk_id, "two slabs interpenetrate by %.1f x %.1f x %.1f studs" % (ox, oy, oz))
                return


def check_ramp(consts):
    """The ramp is the one chunk whose surface is not a set of flat tops, so its
    entry and exit heights cannot be read off a bounding box. Walk the pieces
    end to end instead and confirm the walkable surface starts at SURFACE_Y,
    finishes RAMP_RISE above it, and is continuous in between -- a chunk that
    fails this does not meet a flat neighbour flush, which shows up in game as a
    lip you trip on rather than as anything obviously broken."""
    boxes = CL.layout_ramp(consts)
    theta = boxes[0].pitch
    forward = (math.sin(theta), math.cos(theta))   # (y, z)
    up = (math.cos(theta), -math.sin(theta))

    def surface(box, end):
        """A point on the WALKABLE plane -- the top of the tiles, which sit
        TILE_THICKNESS above the slab's top face along its own up axis, not
        vertically. `end` picks the piece's -Z or +Z end."""
        top_y = box.y + box.sy / 2.0 * up[0]
        top_z = box.z + box.sy / 2.0 * up[1]
        return (top_y + end * box.sz / 2.0 * forward[0] + consts["TILE_THICKNESS"] * up[0],
                top_z + end * box.sz / 2.0 * forward[1] + consts["TILE_THICKNESS"] * up[1])

    def height_at(box, z):
        """Walkable height where the plane crosses a given Z. Measuring at the
        piece's own end instead is off by TILE_THICKNESS * sin(theta) in Z -- about
        a fifth of a stud here -- because the tile layer is offset perpendicular to
        the slope, not straight up. The contract is about the height at Z = 0 and
        Z = RAMP_RUN, so evaluate there."""
        y0, z0 = surface(box, -1)
        return y0 + (z - z0) * math.tan(theta)

    entry_y = height_at(boxes[0], 0.0)
    exit_y = height_at(boxes[-1], consts["RAMP_RUN"])

    if abs(entry_y - consts["SURFACE_Y"]) > 0.1:
        fail("P3_KineticSandRamp", "walkable surface at Z 0 is Y %.2f; the contract publishes "
             "EntrySurfaceY %.2f, so the ramp does not meet a flat chunk flush"
             % (entry_y, consts["SURFACE_Y"]))
    want_y = consts["SURFACE_Y"] + consts["RAMP_RISE"]
    if abs(exit_y - want_y) > 0.1:
        fail("P3_KineticSandRamp", "walkable surface at Z %.0f is Y %.2f; Rise %.0f promises %.2f"
             % (consts["RAMP_RUN"], exit_y, consts["RAMP_RISE"], want_y))

    for i in range(len(boxes) - 1):
        ay, az = surface(boxes[i], +1)
        by, bz = surface(boxes[i + 1], -1)
        if abs(ay - by) > 0.05 or abs(az - bz) > 0.05:
            fail("P3_KineticSandRamp", "piece %d and %d do not meet: (%.2f, %.2f) vs (%.2f, %.2f)"
                 % (i + 1, i + 2, az, ay, bz, by))


def check_honey_lock(layouts, consts):
    """Honey_Platform_Skinned is rigged for one platform size and a rig cannot be
    resized -- setting Size moves the mesh and leaves every Bone behind. If this
    slab ever stops being 16 x 18 the honey corridor silently falls back to
    per-tile meshes, which looks merely worse rather than broken, so nothing in
    game tells you it happened."""
    spec = (16.0, 18.0)
    for box in layouts["P1_HoneyCorridor"]:
        if box.material == "Honey" and abs(box.sx - spec[0]) < EPS and abs(box.sz - spec[1]) < EPS:
            return
    sizes = ["%.1f x %.1f" % (b.sx, b.sz) for b in layouts["P1_HoneyCorridor"] if b.material == "Honey"]
    fail("P1_HoneyCorridor", "no %.0f x %.0f honey slab (found: %s). The skinned rig is size-locked "
         "to that and cannot be rescaled in code." % (spec[0], spec[1], ", ".join(sizes) or "none"))


def check_footprint(chunk_id, boxes, length):
    """Geometry has to stay inside the Length the chunk publishes. LevelService
    advances its cursor by Length + CHUNK_GAP and nothing else, so a chunk that
    runs past its own Length quietly eats into the gap after it and eventually
    into the chunk itself -- the same failure that used to bury every composite
    chunk when the cursor was advanced by PrimaryPart.Size.Z."""
    bounds = [aabb(b) for b in boxes]
    over = max(b[5] for b in bounds) - length
    # The ramp is allowed a little: its pieces are pitched, so a slab corner
    # projects past the run even though the walkable surface ends exactly on it.
    budget = 1.5 if any(b.pitch for b in boxes) else EPS
    if over > budget:
        fail(chunk_id, "geometry runs %.1f studs past the published Length of %.0f"
             % (over, length))


def summarise(chunk_id, boxes, contract):
    length, rise = contract
    main = [b for b in boxes if not is_shelf(b, boxes)]
    widths = [b.sx for b in main]
    notes.append("  %-24s len %5.1f   rise %+3.0f   width %4.1f - %4.1f   slabs %2d"
                 % (chunk_id, length, rise, min(widths), max(widths), len(boxes)))


def check_skinned_coverage(layouts):
    """Every slab of a rigged material must have a rig at exactly its size.

    A miss is completely silent in game. skinnedSpecFor returns nil, attachSkinnedVisual
    never runs, the platform falls back to per-tile meshes, and the result is the grid
    look the rigs exist to remove -- appearing on some platforms of a material and not
    others, which reads as a rendering bug rather than as a missing asset.

    This is not hypothetical: R2_SoapBridge is a tapered run, so soap arrives at three
    different sizes, and a single rig would have covered one of them.

    INTENTIONAL_FALLBACK is an allowlist rather than a switch to turn this off. P4 and
    C1's honey is 16 x 12 on purpose -- deliberately not a rig size, so the per-tile
    approach stays visible in every run for comparison. Listing the two exceptions
    keeps that decision written down and leaves everything else failing."""
    try:
        skinned = CL.load_skinned()
    except ValueError as exc:
        fail("SKINNED_PLATFORMS", str(exc))
        return

    for chunk_id in CL.CHUNK_ORDER:
        for box in layouts[chunk_id]:
            variants = box.material and skinned.get(box.material)
            if not variants:
                continue  # material has no rig at all; per-tile is the intended path
            if (chunk_id, box.material, round(box.sx, 1), round(box.sz, 1)) in INTENTIONAL_FALLBACK:
                continue
            if not any(abs(v["sizeX"] - box.sx) <= 0.1 and abs(v["sizeZ"] - box.sz) <= 0.1
                       for v in variants):
                have = ", ".join("%.0fx%.0f" % (v["sizeX"], v["sizeZ"]) for v in variants)
                fail(chunk_id, "%s slab is %.0f x %.0f but the only %s rigs are %s, so it "
                     "falls back to per-tile meshes"
                     % (box.material, box.sx, box.sz, box.material, have))


# A LEVEL THAT NAMES A CHUNK IT HAS NOT ALLOWED, or allows one it never walks.
#
# `fixedSequence` and `allowedChunkIds` are two hand-kept lists of the same thing, and a
# chunk added to one and forgotten in the other fails at generation time rather than here.
# `minChunks`/`maxChunks` is a third copy of the same fact -- it pins the sequence length --
# and it drifts the moment anyone inserts a chunk without recounting by hand.
#
# All three are now checked against each other, because the sandbox carries 120 entries and
# nobody is counting those by eye. Written after a hand-rolled version of this same query
# reported forty-odd false positives by matching the wrong level's table: the scan below
# takes each `LevelDefinitions.<Name> = {` block whole, so a field can only ever be read
# from the level it belongs to.
# A RIGGED CHUNK ASKING FOR A FORM THAT HAS NO MESH, and a mesh that has no file.
#
# `form` means two different things depending on the material. On soap, lego or buttons it
# names an outline in PlanShapes and check_plan_shapes covers it. On a rigged material it
# names an FBX VARIANT -- lava's crater, snow's dune, bubble wrap's giant -- and nothing was
# checking those at all.
#
# The failure is quiet, which is what makes it worth a check: `skinnedSpecFor` finds no spec
# with that form, falls back to the plain sheet, warns once into the output log, and builds a
# platform that looks entirely finished and is simply the wrong one. A typo in a chunk recipe
# is indistinguishable from a variant nobody has generated yet.
#
# The second half checks the mesh exists on disk. The spec can be right and the FBX never
# exported, and the symptom is the same platform falling back to per-tile meshes.
def check_rigged_forms():
    chunks, consts = CL.load()
    skinned = CL.load_skinned()
    meshes = ROOT_DIR / "meshes"

    # ONLY THE TWO THAT CUT AN OUTLINE OUT OF PARTS -- and CAPPED is deliberately not one of
    # them any more. Buttons is both rigged and capped, and for a while its form named a
    # PlanShapes outline that skipped caps; it now names a mesh variant like every other
    # rigged material, so its forms are checked here rather than excluded from here.
    source = open(CL.SOURCE, "r", encoding="utf-8").read()
    cuts = set()
    for table in ("GRANULAR", "BRICKED"):
        line = re.search(r"^local " + table + r"[^=]*= \{(.*?)\}", source, re.M).group(1)
        cuts |= set(re.findall(r"(\w+) = true", line))

    for chunk_id, segments in chunks.items():
        for seg in segments:
            material, form = seg.get("material"), seg.get("form")
            if not form or material not in skinned or material in cuts:
                continue
            wanted = [s for s in skinned[material] if s.get("form") == form]
            if not wanted:
                have = sorted({s.get("form") for s in skinned[material] if s.get("form")})
                fail(chunk_id, "asks %s for form '%s', and SKINNED_PLATFORMS has no such "
                               "variant (%s). It will silently build the plain sheet."
                     % (material, form, ", ".join(have) if have else "no variants at all"))

    for material, specs in skinned.items():
        for spec in specs:
            name = spec.get("mesh")
            if name and not (meshes / (name + ".fbx")).exists():
                fail(material, "SKINNED_PLATFORMS names mesh '%s' and %s.fbx is not in "
                               "meshes/. Generate it before importing." % (name, name))


# A FLOOR DROP TABLE THAT DOES NOT MATCH THE GRID IT INDEXES.
#
# `drops` is read as `drops[(row - 1) * cols + col]`, so its length has to be exactly the
# cell count for that slab size -- and the cell count comes from SubRegionGrid, which the
# generator restates rather than reads. A table one short is not an error in Luau: the last
# cell indexes past the end, gets nil, falls back to zero, and one corner of the platform
# floats while the rest sits correctly.
#
# Positives are the other half. Every drop is meant to bring a collider DOWN to the surface
# from a plane set at the mesh's high point; a positive one would push a floor up through the
# mesh, which is the original bug with the sign flipped.
def check_floor_drops():
    for material, specs in CL.load_skinned().items():
        for spec in specs:
            drops = spec.get("drops")
            if not drops:
                continue
            cols = max(2, min(6, round(spec["sizeX"] / 3.2)))
            rows = max(2, min(6, round(spec["sizeZ"] / 3.2)))
            name = spec.get("mesh", material)
            if len(drops) != cols * rows:
                fail(material, "%s carries %d floor drops for a %dx%d cell grid, which needs "
                               "%d. The tail of the platform will read nil and sit flat."
                     % (name, len(drops), cols, rows, cols * rows))
            above = [d for d in drops if d > 0.0]
            if above:
                fail(material, "%s has %d positive floor drop(s) (max %+.2f). Drops only ever "
                               "bring a collider down to the mesh; a positive one lifts it "
                               "through the surface." % (name, len(above), max(above)))


def check_levels():
    source = open(LEVELS, "r", encoding="utf-8").read()
    defined = CL.defined_chunks() | set(CL.SPECIAL)

    for level in re.finditer(r"^LevelDefinitions\.(\w+) = \{(.*?)^\}", source, re.S | re.M):
        name, body = level.group(1), level.group(2)

        def listed(field):
            found = re.search(field + r" = \{(.*?)\n\t\},", body, re.S)
            return re.findall(r'"(\w+)"', found.group(1)) if found else None

        allowed, sequence = listed("allowedChunkIds"), listed("fixedSequence")
        if allowed is None:
            continue

        for chunk in sorted(set(allowed) - defined):
            fail(name, "allows '%s', which is not a chunk ChunkBuilder defines." % chunk)
        if sequence is None:
            continue
        for chunk in sorted(set(sequence) - set(allowed)):
            fail(name, "walks '%s' but does not list it in allowedChunkIds." % chunk)
        for chunk in sorted(set(allowed) - set(sequence)):
            fail(name, "allows '%s' but never walks it. In a fixed sequence that is dead "
                       "weight, and usually means a chunk was added to one list only." % chunk)

        pinned = re.search(r"minChunks = (\d+),\s*\n\tmaxChunks = (\d+),", body)
        if pinned and {int(pinned.group(1)), int(pinned.group(2))} != {len(sequence)}:
            fail(name, "pins minChunks/maxChunks at %s/%s but walks %d chunks."
                 % (pinned.group(1), pinned.group(2), len(sequence)))


def check_no_bypass_shelves():
    """NO DRY LANE BESIDE THE MATERIAL, and no ledge to be caught by.

    The stable straight and the honey corridor used to carry flanking shelves: five and four studs
    of solid ground each side, a stud below the top. Two things came of that, both reported from
    play. The shelf of a stable chunk reaches level with its neighbour, so you could walk ALONGSIDE
    the honey instead of over it -- the one chunk whose whole job is to be walked on was the one
    you could skip. And stepping off the side of the Needoh field landed you on the next stable
    chunk's shelf, so nothing in a route made of platforms over a void could be fallen off.

    The shelf feature itself stays: the butter-wax bend keeps a catch on the outside of its turn,
    and the soap chunk keeps flanks because soap dissolves and the chunk has to stay crossable. What
    may not come back is a shelf beside a material you are meant to cross."""
    with open(CL.SOURCE, "r", encoding="utf-8") as handle:
        text = handle.read()
    for chunk_id in ("S1_Straight", "P1_HoneyCorridor"):
        block = re.search(r"\n\t%s = \{(.*?)\n\t\}," % chunk_id, text, re.S)
        if not block:
            failures.append("%s is no longer a linear chunk this check can read." % chunk_id)
        elif "shelf" in block.group(1):
            failures.append("%s has flanking shelves again: a dry lane beside the material lets the "
                            "chunk be walked past, and catches anyone falling off its neighbour."
                            % chunk_id)
    landing = re.search(r"name = \"HoneyLanding\",(.*?)\},", text, re.S)
    if landing and "shelf" in landing.group(1):
        failures.append("C1_SlimeToPace's honey landing has a shelf again, for the reason above.")


def main():
    CL.check_order_covers_definitions()
    layouts, contracts, consts = CL.layout_all()
    check_no_bypass_shelves()

    for chunk_id in CL.CHUNK_ORDER:
        boxes = layouts[chunk_id]
        check_faces(chunk_id, boxes)
        check_route(chunk_id, boxes)
        check_overlaps(chunk_id, boxes)
        check_footprint(chunk_id, boxes, contracts[chunk_id][0])
        summarise(chunk_id, boxes, contracts[chunk_id])

    check_ramp(consts)
    check_honey_lock(layouts, consts)
    check_skinned_coverage(layouts)
    check_levels()
    check_rigged_forms()
    check_floor_drops()

    print("chunk layout, as parsed from ChunkBuilder.server.lua:")
    print("\n".join(notes))
    print("")

    if failures:
        print("FAILED (%d):" % len(failures))
        for line in failures:
            print("  " + line)
        return 1
    print("all %d chunks pass the layout contract." % len(CL.CHUNK_ORDER))
    return 0


sys.exit(main())
