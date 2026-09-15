"""The flooded halls: a tiled maze standing in shallow water.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_flooded_halls.py

=== What this is ===

A kit of architectural pieces for a new level: a liminal bathhouse, tiled floor to ceiling,
with a few inches of still green water lying across every floor. You wade rather than walk.

=== Why there are no tiles in these meshes ===

The tile grid is the whole look, and it is the one thing NOT modelled here.

A wall twenty studs across at the tile size in the references is roughly forty tiles wide by
thirty high -- twelve hundred tiles on one wall, each needing its own recessed grout line.
Modelled as geometry that is tens of thousands of triangles for a single flat surface, and
there are hundreds of surfaces in a maze. It would not fit in a mesh, let alone a level.

Roblox ships CeramicTiles as a built-in material with a full PBR set -- albedo, normal and
roughness, tiling at a fixed world scale. It is exactly the surface these images are made of,
it costs nothing, and it is applied with one property. So these meshes carry the FORMS the
material cannot give -- the round arches, the vaults, the entasis on a column -- and the
material carries the surface the forms cannot.

That division is the same one the sunken blade uses with CorrodedMetal, and for the same
reason: a built-in material with real maps beats an untextured mesh every time.

=== Why these five pieces ===

A maze is repetition, so the kit has to be small enough that every piece earns itself and
varied enough that a corridor does not read as one thing copied. These five cover it:

  ArchWall   a wall with a round-topped opening. The doorway AND the frame in one piece,
             because in the references the arch is the architecture rather than a hole in it.
  Column     a cylinder with entasis, standing in the water. The single most recognisable
             object in the whole reference set.
  Vault      a barrel ceiling. Flat ceilings read as a corridor; a vault reads as a bathhouse.
  CurveWall  a quarter turn. Straight walls alone make a grid maze look like a grid.
  Steps      a short flight down into deeper water, which is what makes the depth legible.

Each is kept light, because a maze places dozens of every one of them.
"""

import math
import os

import bmesh
import bpy
from mathutils import Vector

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "meshes")

# The module the whole kit is built on. One bay is this wide and this tall, so pieces butt
# together without thought.
BAY = 24.0
HEIGHT = 22.0
THICK = 2.0

# ===== THE FLUME'S NUMBERS =====
#
# UP HERE RATHER THAN INSIDE build_slide, because they are the one set of measurements in this
# file that a second file depends on. FloodedHallsService sweeps the ride along the same helix
# the tube is swept along, and blender/check_halls.py compares the two at the source -- both of
# which want a name they can find, not a local inside a function body.
#
# (check_halls used to scope its search to build_slide's body for exactly that reason, and the
# first version of it did not: it matched build_column's radius, which is a different 3.4
# entirely, and reported that the two files agreed.)
# ===== THE TRANSVERSE ARCH, AND THE HEIGHT THE WALKWAY CROSSES IT AT =====
#
# The route runs THROUGH this piece. It is the only member of the kit a player passes inside
# rather than beside, so where its opening sits is not a proportion, it is a clearance.
#
# THE FIRST VERSION SPRANG AT 0.30 OF THE WALL HEIGHT, which is a perfectly good place for an
# arch to spring and put its head 59 studs above the flooded floor. The walkway is at 56. So
# every third bay had an arch whose head cleared the walking surface by three studs, against a
# character five studs tall: you walked in at foot level and stopped, with the opening visible
# and apparently open in front of you. Nothing in the mesh was wrong; it was being asked to
# straddle a floor it had never been told about.
#
# WALKWAY_AT is FloodedHallsService's FLOOR_DROP divided by SCALE, and check_halls compares
# them. The springing goes below it and the head well above it, so the opening is already full
# width at the walking surface and stays clear of anybody's head.
WALKWAY_AT = 14.0
# WIDE ENOUGH AT HEAD HEIGHT, not at the springing. The springing is below the walkway, so the
# opening is already narrowing by the time it reaches anybody: at 0.34 it measured 32.6 to each
# side where the arch springs and 29.6 where a player's head is, which is inside the lane. The
# number that matters is always the one at the height somebody occupies.
ARCH_SPAN = BAY * 0.42
ARCH_SPRING = 10.0
# ===== AND HOW MANY RINGS IT HAS, WHICH TURNED OUT TO MATTER A GREAT DEAL =====
#
# The arch is moulded: an outer ring with smaller ones stepped in behind it, so that standing in
# the opening you look through a few concentric rings and read depth.
#
# EACH INNER LEAF USED TO SHRINK ITS SPRINGING AS WELL AS ITS SPAN -- arch_at(span * 0.9,
# spring * 0.9) -- which is fine while the springing is low and catastrophic once it is raised
# to straddle the walkway. Scaled from the floor, a 0.8 leaf's head came down eight studs while
# its opening narrowed by a fifth, so the three rings landed at nine, eighteen and twenty-six
# studs above the walking surface, each a different width. That does not read as one moulded
# opening. It reads as the arch having been built three times, which is exactly what was
# reported -- and the innermost ring was only twenty studs to each side, well inside the lane.
#
# Concentric about ONE springing now, and one inner leaf rather than two, stepped gently. The
# factor is a module constant because check_halls has to test the INNERMOST ring against the
# lane: the outer one clearing it says nothing about the one you actually walk through.
ARCH_LEAVES = (0.93,)

# ===== THE STEPS INTO A BASIN =====
#
# Up here for the same reason the flume's numbers are: FloodedHallsService has to know how long
# the flight is to place it, because a MeshPart is positioned by its bounding-box centre and the
# top tread is therefore half a flight away from wherever the CFrame goes.
#
# THE FIRST VERSION WAS A RAMP. Five treads of 1.6 over a bay and a half of width is 67 studs
# across and 32 deep -- wider than the basin it goes into, and so shallow that the treads read
# as notches in a bar. Rendered next to a five-stud figure it was obvious; it is invisible in
# the source, where 1.6 and 2.6 look like perfectly reasonable stair numbers. They are, at human
# scale. Nothing in this kit is at human scale.
STEP_TREADS = 7
STEP_RISE = 1.214
STEP_RUN = 1.6
STEP_WIDTH = 10.0
# What the flight measures, which is what the Lua duplicates and check_halls compares.
STEP_FLIGHT = STEP_TREADS * STEP_RUN

SLIDE_RADIUS = 9.0
# THE BORE IS THE ONE MEASUREMENT HERE TAKEN FROM A BODY. It was 3.4 first, which is a 27-stud
# tube around a 4-stud character -- a storm drain, not a flume. Rendered with a stand-in figure
# in the mouth the error was obvious and it is not visible any other way, which is the whole
# argument for rendering it.
SLIDE_BORE = 1.8
SLIDE_WALL = 0.5
SLIDE_DROP = 26.0
SLIDE_TURNS = 1.25
# HOW MUCH THE MOUTH OPENS OUT. Up here because FloodedHallsService needs it too: the trough
# floor at the mouth is a flared bore below the tube's centre line, and that is exactly how far
# the whole flume has to be lifted for its entrance to be level with the apron beside it.
#
# It was 0.45. That is a flare you could park a bus in -- it stood the mouth eighteen studs
# above the apron, so the entrance read as a pipe hanging in the air next to the platform.
SLIDE_FLARE = 0.15


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.objects):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def finish(bm, name: str):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    # UV BY WORLD POSITION, not per face. CeramicTiles tiles in world space, so the mesh's own
    # UVs only matter if a SurfaceAppearance is ever added -- and if one is, a projection that
    # already matches the world grid is the one that will line up with the built-in material
    # it replaces. Cheap to do now, awkward to retrofit.
    mesh.uv_layers.new(name="UVMap")
    uv = mesh.uv_layers.active.data
    for poly in mesh.polygons:
        n = poly.normal
        for loop_index in poly.loop_indices:
            co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            if abs(n.z) > max(abs(n.x), abs(n.y)):
                uv[loop_index].uv = (co.x / BAY, co.y / BAY)
            elif abs(n.x) > abs(n.y):
                uv[loop_index].uv = (co.y / BAY, co.z / BAY)
            else:
                uv[loop_index].uv = (co.x / BAY, co.z / BAY)
    return obj


def quad(bm, a, b, c, d):
    bm.faces.new((bm.verts.new(a), bm.verts.new(b), bm.verts.new(c), bm.verts.new(d)))


def prism(bm, points, thickness, offset=0.0):
    """A closed solid from a flat outline in the XZ plane, extruded along Y.

    `offset` slides the whole prism along Y, which is what lets the arch be built as several
    leaves stacked front to back rather than as one slab with a hole in it.
    """
    front = [bm.verts.new((x, offset - thickness / 2.0, z)) for x, z in points]
    back = [bm.verts.new((x, offset + thickness / 2.0, z)) for x, z in points]
    n = len(points)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    for k in range(1, n - 1):
        bm.faces.new((front[0], front[k + 1], front[k]))
        bm.faces.new((back[0], back[k], back[k + 1]))


# --------------------------------------------------------------------------- #

def build_arch_wall():
    """A wall panel with a round-topped opening cut through it.

    THE OPENING IS THE PIECE. In the references you are almost never looking at a wall -- you
    are looking THROUGH one, down a run of arches that get smaller as they recede, and that
    receding run is what makes the space feel endless. So the arch is generous: two thirds of
    the bay wide and springing from low down, which is what gives the horseshoe profile rather
    than a doorway with a curved lintel.

    Built as an outline traced round the opening rather than as a boolean, because a boolean
    on a wall this simple produces a mess of coplanar triangles for no benefit.
    """
    bm = bmesh.new()
    half = BAY / 2.0
    span = ARCH_SPAN           # half-width of the opening
    spring = ARCH_SPRING       # where the curve starts -- see the note by the constants
    steps = 18

    # ===== AN ORDER OF THREE ARCHES, not one hole =====
    #
    # The single most repeated image in the references is arches INSIDE arches, each one
    # smaller and further away, and the eye reads that as depth long before it reads the room.
    # A wall with one opening cut through it cannot do that no matter how thick it is -- what
    # makes the effect is the STEP between rings, because each step catches the light on its
    # face and throws a hard edge round the opening.
    #
    # So the wall is built in three leaves, each with a slightly smaller arch than the one in
    # front. Standing in the doorway you look through three concentric rings; from across the
    # room they read as one deeply moulded surround.
    def arch_at(s_span, s_spring):
        profile = [(-s_span, 0.0)]
        for s in range(steps + 1):
            angle = math.pi * s / steps
            profile.append((-s_span * math.cos(angle), s_spring + s_span * math.sin(angle)))
        profile.append((s_span, 0.0))
        return profile

    arch = arch_at(span, spring)

    # THE WALL, as a ring of quads between the outer rectangle and the arch outline. Each
    # segment of the arch gets its own quad out to the nearest edge, so the wall closes
    # exactly round the opening with no gaps and no overlap.
    outer = [(-half, 0.0), (-half, HEIGHT), (half, HEIGHT), (half, 0.0)]

    def outer_at(x, z):
        """The point on the outer rectangle in the direction of (x, z) from the centre."""
        if z >= HEIGHT * 0.999:
            return (max(-half, min(half, x)), HEIGHT)
        return (half if x > 0 else -half, min(HEIGHT, max(0.0, z)))

    for a, b in zip(arch, arch[1:]):
        oa, ob = outer_at(*a), outer_at(*b)
        if oa == ob:
            continue
        prism(bm, [a, b, ob, oa], THICK)

    # The inner leaf, stepped in and sitting proud of the outer one. Shallow, and CONCENTRIC:
    # same springing, smaller span. See the note by ARCH_LEAVES -- shrinking the springing too
    # is what turned one moulded arch into three separate ones at three different heights.
    for index, shrink in enumerate(ARCH_LEAVES):
        offset = THICK * (0.5 + index * 0.42)
        inner_arch = arch_at(span * shrink, spring)
        for a, b in zip(inner_arch, inner_arch[1:]):
            oa, ob = outer_at(*a), outer_at(*b)
            if oa == ob:
                continue
            prism(bm, [a, b, ob, oa], THICK * 0.3, offset)

    # The head of the wall above the arch, and the two feet beside it.
    prism(bm, [(-half, HEIGHT), (half, HEIGHT), (half, spring + span), (-half, spring + span)],
          THICK) if spring + span < HEIGHT else None
    for side in (-1, 1):
        x0 = side * span
        x1 = side * half
        prism(bm, [(x0, 0.0), (x1, 0.0), (x1, spring), (x0, spring)], THICK)

    return finish(bm, "Hall_ArchWall")


def build_column():
    """A fluted column with a moulded base and a capital.

    === Why it is worth the triangles ===

    There are two of these in every bay and they are the only thing in the level at arm's
    length the whole way along it. Walls are flat by definition and read as material; the
    columns are the only piece with a PROFILE, which means they are the only piece that can
    say the building was designed rather than extruded. A tapered cylinder says neither.

    === What it is made of, bottom to top ===

      PLINTH      A square block. In the references the columns meet the water in a square
                  base rather than growing out of it like a stalk, and the corners of it
                  breaking the surface is half of what makes the water read as water.
      BASE        A torus and a scotia -- a convex roll and the concave hollow above it. Two
                  mouldings is the minimum that reads as a base rather than as a wider bit.
      SHAFT       Fluted, with entasis. See below.
      NECK        An astragal: a small bead marking where the shaft stops.
      CAPITAL     An echinus flaring out to a square abacus, which is what the ceiling
                  actually lands on.

    === Entasis, and flutes ===

    ENTASIS is the slight outward bulge every classical column has. Perfectly straight sides
    read as concave, and a column that looks concave looks like it is buckling. A couple of
    percent is enough; nobody consciously sees it, they just stop finding the column subtly
    wrong.

    FLUTES are the vertical grooves. They are what make a column catch the light: a smooth
    cylinder has exactly one highlight running down it, while a fluted one has a dozen, and
    they shift as you walk past. That movement is most of what makes a colonnade feel like a
    colonnade instead of a row of posts -- and it costs nothing but angular resolution, which
    the shaft needs anyway to avoid faceting.
    """
    bm = bmesh.new()
    radius = 3.4
    around = 40
    flutes = 12
    flute_deep = 0.05

    def ring(z, r, fluted):
        made = []
        for j in range(around):
            angle = j / around * math.tau
            here = r
            if fluted:
                # Cosine-lobed rather than cut: a real flute is a shallow hollow, and a lobed
                # radius gives that with no extra vertices at all.
                here = r * (1.0 - flute_deep * (0.5 + 0.5 * math.cos(flutes * angle)))
            made.append(bm.verts.new(
                (math.cos(angle) * here, math.sin(angle) * here, z)))
        return made

    # The profile, bottom to top: height, radius as a multiple of the shaft's, and whether the
    # flutes run through it. Mouldings are never fluted -- that is what makes them read as
    # separate members rather than as the shaft changing its mind.
    plinth_top = 2.2
    profile = [
        (plinth_top, 1.30, False),          # the base's bottom fillet
        (plinth_top + 0.55, 1.34, False),   # torus, at its widest
        (plinth_top + 1.05, 1.16, False),   # scotia, pinched in above it
        (plinth_top + 1.5, 1.08, False),    # and out again to meet the shaft
        (plinth_top + 1.9, 1.0, True),      # the shaft starts
    ]
    shaft_from = plinth_top + 1.9
    shaft_to = HEIGHT * 0.80
    stations = 10
    for s in range(1, stations + 1):
        f = s / stations
        # Widest a third of the way up, tapering to the neck.
        bulge = 1.0 + 0.035 * math.sin(f * math.pi) - 0.085 * f
        profile.append((shaft_from + (shaft_to - shaft_from) * f, bulge, True))
    profile += [
        (shaft_to + 0.24, 1.02, False),     # astragal: the bead under the capital
        (shaft_to + 0.5, 0.94, False),
        (shaft_to + 0.75, 0.98, False),     # the capital springs
        (shaft_to + 1.5, 1.22, False),      # echinus, flaring
        (shaft_to + 2.1, 1.46, False),
        (shaft_to + 2.35, 1.5, False),
    ]

    rings = [ring(z, radius * r, fluted) for z, r, fluted in profile]
    for lower, upper in zip(rings, rings[1:]):
        for j in range(around):
            k = (j + 1) % around
            bm.faces.new((lower[j], lower[k], upper[k], upper[j]))
    for k in range(1, around - 1):
        bm.faces.new((rings[0][0], rings[0][k + 1], rings[0][k]))

    def block(half, z0, z1):
        """A square member: the plinth at the bottom, the abacus at the top."""
        outline = [(-half, z0), (half, z0), (half, z1), (-half, z1)]
        front = [bm.verts.new((x, -half, z)) for x, z in outline]
        back = [bm.verts.new((x, half, z)) for x, z in outline]
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((front[i], front[j], back[j], back[i]))
        bm.faces.new(tuple(reversed(front)))
        bm.faces.new(tuple(back))

    block(radius * 1.45, 0.0, plinth_top)
    # The abacus carries the ceiling, so it runs to the full height of the order.
    block(radius * 1.52, shaft_to + 2.35, HEIGHT)
    return finish(bm, "Hall_Column")


def build_vault():
    """A barrel ceiling for one bay.

    A FLAT CEILING MAKES A CORRIDOR. Every one of the references has a curved or coffered top,
    and it is doing more work than it looks: a barrel vault throws the light coming in at the
    sides across the whole ceiling, so the room is lit by a glow with no visible source. A flat
    slab just goes dark.

    Open at both ends and along the bottom, so bays chain into a continuous tunnel.
    """
    bm = bmesh.new()
    half = BAY / 2.0
    rise = BAY * 0.30
    steps = 16
    inner, outer = [], []
    for s in range(steps + 1):
        angle = math.pi * s / steps
        x = -half * math.cos(angle)
        z = rise * math.sin(angle)
        inner.append((x, z))
        # The vault has thickness, so the ceiling reads as masonry rather than as a membrane.
        outer.append((x * (1.0 + THICK / BAY), z + THICK))

    ia = [bm.verts.new((x, -half, z)) for x, z in inner]
    ib = [bm.verts.new((x, half, z)) for x, z in inner]
    oa = [bm.verts.new((x, -half, z)) for x, z in outer]
    ob = [bm.verts.new((x, half, z)) for x, z in outer]
    for i in range(steps):
        bm.faces.new((ia[i], ib[i], ib[i + 1], ia[i + 1]))      # the soffit you look up at
        bm.faces.new((oa[i + 1], ob[i + 1], ob[i], oa[i]))      # the back
        bm.faces.new((ia[i], ia[i + 1], oa[i + 1], oa[i]))      # the two open ends
        bm.faces.new((ib[i + 1], ib[i], ob[i], ob[i + 1]))
    bm.faces.new((ia[0], oa[0], ob[0], ib[0]))
    bm.faces.new((ia[steps], ib[steps], ob[steps], oa[steps]))
    return finish(bm, "Hall_Vault")


def build_curve_wall():
    """A quarter turn, so the maze is not all right angles.

    Straight walls on a grid make a grid, and a grid reads as a floor plan. One curved piece
    breaks that: a corridor that bends has no visible end, which is the whole point of a maze
    you are meant to feel lost in.
    """
    bm = bmesh.new()
    radius = BAY * 0.7
    steps = 14
    inner, outer = [], []
    for s in range(steps + 1):
        angle = math.pi / 2 * s / steps
        inner.append((math.cos(angle) * radius, math.sin(angle) * radius))
        outer.append((math.cos(angle) * (radius + THICK), math.sin(angle) * (radius + THICK)))

    low_i = [bm.verts.new((x, y, 0.0)) for x, y in inner]
    high_i = [bm.verts.new((x, y, HEIGHT)) for x, y in inner]
    low_o = [bm.verts.new((x, y, 0.0)) for x, y in outer]
    high_o = [bm.verts.new((x, y, HEIGHT)) for x, y in outer]
    for i in range(steps):
        bm.faces.new((low_i[i], high_i[i], high_i[i + 1], low_i[i + 1]))
        bm.faces.new((low_o[i + 1], high_o[i + 1], high_o[i], low_o[i]))
        bm.faces.new((high_i[i], high_o[i], high_o[i + 1], high_i[i + 1]))
        bm.faces.new((low_i[i + 1], low_o[i + 1], low_o[i], low_i[i]))
    bm.faces.new((low_i[0], low_o[0], high_o[0], high_i[0]))
    bm.faces.new((low_i[steps], high_i[steps], high_o[steps], low_o[steps]))
    return finish(bm, "Hall_CurveWall")


def build_steps():
    """A flight down into a basin, ending in the water rather than at the bottom.

    WATER YOU CANNOT MEASURE IS NOT WET. A single depth everywhere reads as a green floor; a
    flight of steps going down into one, where the treads fade out before they reach anything,
    is the moment the level tells you how deep it is.

    So the flight is deliberately SHORTER than the shallowest basin. It is not a way down, it
    is a measuring stick: you count treads until you cannot see them any more, and that is the
    only number this level ever gives you about the water.

    Each tread carries a nosing -- a small overhang at the front. It is the difference between
    a staircase and a stack of boxes: the nosing casts a hard line of shadow along every tread,
    which is what makes a flight read as a flight from across a room.
    """
    bm = bmesh.new()
    half = STEP_WIDTH / 2.0
    nose = 0.22
    for i in range(STEP_TREADS):
        z0 = -i * STEP_RISE
        y0 = i * STEP_RUN
        # The riser and the tread under it, as one block from the front of the nosing back.
        prism_pts = [(-half, z0 - STEP_RISE), (half, z0 - STEP_RISE), (half, z0), (-half, z0)]
        front = [bm.verts.new((x, y0 - nose, z)) for x, z in prism_pts]
        back = [bm.verts.new((x, y0 + STEP_RUN, z)) for x, z in prism_pts]
        for a in range(4):
            b = (a + 1) % 4
            bm.faces.new((front[a], front[b], back[b], back[a]))
        bm.faces.new(tuple(reversed(front)))
        bm.faces.new(tuple(back))

    # THE CHEEKS: a solid side to the flight, so it is built into the basin rather than
    # floating in it. Without them the staircase is a set of treads with daylight down both
    # sides, which no masonry stair has ever had.
    deep = STEP_TREADS * STEP_RISE
    run = STEP_TREADS * STEP_RUN
    for side in (-1, 1):
        x = side * (half + 0.35)
        outline = [(0.0, 0.0), (run, -deep), (run, -deep - 1.1), (0.0, -1.1)]
        wall_front = [bm.verts.new((x - 0.35, y, z)) for y, z in outline]
        wall_back = [bm.verts.new((x + 0.35, y, z)) for y, z in outline]
        for a in range(4):
            b = (a + 1) % 4
            bm.faces.new((wall_front[a], wall_front[b], wall_back[b], wall_back[a]))
        bm.faces.new(tuple(reversed(wall_front)))
        bm.faces.new(tuple(wall_back))

    return finish(bm, "Hall_Steps")


def build_dome():
    """A shallow dome for the one big room in the maze.

    A MAZE OF IDENTICAL BAYS HAS NO PAYOFF. You wander, and then you wander somewhere that
    looks the same, and there is nothing to have found. One room that is unmistakably
    different -- taller, open, domed, lit from a ring of openings round its base -- turns the
    whole maze into something with a middle, and finding it means something.

    Shallow rather than hemispherical: a half-sphere over a wide room is a planetarium, and
    the references are bathhouses. A third of the radius in rise reads as masonry.
    """
    bm = bmesh.new()
    radius = BAY * 1.55
    rise = radius * 0.42
    rings, stacks = 28, 10
    grid = []
    for s in range(stacks + 1):
        f = s / stacks
        # An ellipse in section, not a circle: the springing stays vertical so the dome meets
        # its walls square instead of overhanging them.
        r = radius * math.cos(f * math.pi / 2)
        z = rise * math.sin(f * math.pi / 2)
        row = []
        for j in range(rings):
            angle = j / rings * math.tau
            row.append((math.cos(angle) * r, math.sin(angle) * r, z))
        grid.append(row)

    inner = [[bm.verts.new(pt) for pt in row] for row in grid]
    outer = [[bm.verts.new((pt[0] * 1.05, pt[1] * 1.05, pt[2] + THICK)) for pt in row]
             for row in grid]
    for s in range(stacks):
        for j in range(rings):
            k = (j + 1) % rings
            bm.faces.new((inner[s][j], inner[s][k], inner[s + 1][k], inner[s + 1][j]))
            bm.faces.new((outer[s + 1][j], outer[s + 1][k], outer[s][k], outer[s][j]))
    # The open rim at the bottom, closed between the two shells.
    for j in range(rings):
        k = (j + 1) % rings
        bm.faces.new((inner[0][k], inner[0][j], outer[0][j], outer[0][k]))
    # And the crown, where the two shells meet.
    for j in range(rings):
        k = (j + 1) % rings
        bm.faces.new((inner[stacks][j], inner[stacks][k], outer[stacks][k], outer[stacks][j]))
    return finish(bm, "Hall_Dome")


def build_hand():
    """A hand breaking the surface, wrist down.

    THE ONE THING IN THE LEVEL THAT WAS ALIVE. Everything else here is architecture, and
    architecture is only unsettling for so long -- the eye accepts an empty room quickly. A
    hand does not get accepted. It is also the only object in the kit with a scale everybody
    already knows, so it tells you how big the room is at the same time as it tells you
    something is wrong.

    Modelled half-open and relaxed rather than clutching. A grasping hand is a threat and
    reads as a monster; a slack one reads as a body, which is worse.

    Small -- about seven studs across the fingers -- so at any distance it is a pale shape you
    are not certain about until you have looked twice. That uncertainty is the whole effect.
    """
    bm = bmesh.new()

    def tube(path, radii, sides=6):
        rings = []
        for (x, y, z), r in zip(path, radii):
            ring = []
            for j in range(sides):
                a = j / sides * math.tau
                ring.append(bm.verts.new((x + math.cos(a) * r, y + math.sin(a) * r * 0.72, z)))
            rings.append(ring)
        for a, b in zip(rings, rings[1:]):
            for j in range(sides):
                k = (j + 1) % sides
                bm.faces.new((a[j], a[k], b[k], b[j]))
        bm.faces.new(tuple(reversed(rings[0])))
        bm.faces.new(tuple(rings[-1]))

    # The forearm, going down into the water and stopping -- there is no body, and not showing
    # one is what leaves the question open.
    tube([(0, 0, -4.2), (0, 0, -1.6), (0, 0, 0.4)], [0.95, 0.85, 0.80])
    # The palm, as a flattened block.
    palm = [(-1.35, -0.55, 0.4), (1.35, -0.55, 0.4), (1.35, 0.55, 0.4), (-1.35, 0.55, 0.4)]
    top = [(-1.25, -0.5, 2.5), (1.25, -0.5, 2.5), (1.25, 0.5, 2.5), (-1.25, 0.5, 2.5)]
    lo = [bm.verts.new(pt) for pt in palm]
    hi = [bm.verts.new(pt) for pt in top]
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bm.faces.new(tuple(reversed(lo)))
    bm.faces.new(tuple(hi))

    # Four fingers, each curling slightly and at its own length. Uniform fingers read as a
    # glove; the length difference is what makes it a hand.
    for index, (offset, length, curl) in enumerate((
            (-0.95, 2.9, 0.30), (-0.32, 3.3, 0.22),
            (0.32, 3.1, 0.26), (0.95, 2.5, 0.36))):
        path, radii = [], []
        for s in range(4):
            f = s / 3
            path.append((offset + curl * f * f * 0.8, -curl * length * f * f,
                         2.5 + length * f))
            radii.append(0.34 * (1.0 - f * 0.45))
        # SEVEN SIDES, NOT FIVE. At five a finger seen edge-on is a flat slat, and four flat
        # slats standing out of water read as a fence rather than a hand. Two more segments
        # each is forty triangles across the whole hand and it is the difference between the
        # thing working and not.
        tube(path, radii, sides=7)

    # The thumb, out to the side and lower, which is the silhouette that says HAND rather than
    # a bundle of sticks.
    tube([(-1.3, 0.1, 1.5), (-2.1, -0.4, 2.2), (-2.6, -0.9, 2.9)], [0.40, 0.34, 0.26], sides=7)
    return finish(bm, "Hall_Hand")



def build_spiral():
    """A spiral stair winding round a column, rising out of the water.

    THE ONE PIECE THAT GOES UP. Everything else in this kit is a floor, a wall or a ceiling --
    the whole maze is one level, and a maze on one level is a floor plan you walk around. A
    stair says the building has more of itself somewhere you cannot see, and it does that from
    across a room, before you reach it and discover it goes nowhere.

    Wound round a column rather than free-standing, because a free-standing spiral needs a
    newel and a balustrade to look structural and both are fiddly geometry that will read as
    noise at this scale. Round a column that is already there, the column IS the newel.

    Treads are cantilevered wedges with no risers, so daylight comes down between them -- which
    is what makes a stair over water read as light rather than as a ramp.
    """
    bm = bmesh.new()
    inner = 3.9              # clears the column's widest point
    outer = BAY * 0.46
    treads = 22
    rise = 1.15
    thick = 0.55
    sweep = math.radians(15.5)   # per tread

    for i in range(treads):
        a0 = i * sweep
        a1 = a0 + sweep * 0.88   # a gap between treads, so light falls through
        z = i * rise
        ring = []
        for radius in (inner, outer):
            for angle in (a0, a1):
                ring.append((math.cos(angle) * radius, math.sin(angle) * radius))
        # Wound in the order that makes a convex quad: inner-start, outer-start, outer-end,
        # inner-end. Listing the four corners by radius then angle gives them out of order and
        # produces a bow-tie, which bmesh accepts and the renderer draws inside out.
        plan = [ring[0], ring[2], ring[3], ring[1]]
        low = [bm.verts.new((x, y, z)) for x, y in plan]
        high = [bm.verts.new((x, y, z + thick)) for x, y in plan]
        for k in range(4):
            j = (k + 1) % 4
            bm.faces.new((low[k], low[j], high[j], high[k]))
        bm.faces.new(tuple(reversed(low)))
        bm.faces.new(tuple(high))
    return finish(bm, "Hall_Spiral")



def build_cove():
    """A coved skirting: the quarter-round where a tiled wall meets a tiled floor.

    THE DETAIL THAT SAYS "WET ROOM". Every tiled space built to be hosed down has coving --
    a sharp internal corner traps water and grows mould, so the tile is curved into the floor
    instead. It is in every reference image and it is completely invisible until it is missing,
    at which point the room reads as a render rather than a building.

    It also does real work for the light: a cove catches a thin bright line along its length
    wherever light rakes down a wall, and that line is what separates wall from floor when both
    are the same tile in the same colour. Without it the two planes merge into one pale field.
    """
    bm = bmesh.new()
    radius = 1.6
    steps = 7
    section = []
    for s in range(steps + 1):
        angle = math.pi / 2 * s / steps
        # Concave: the surface curves AWAY from the corner, so the centre of the arc is out
        # in the room rather than inside the masonry.
        section.append((radius - math.cos(angle) * radius, radius - math.sin(angle) * radius))
    # Closed off with the two flat faces that bed into the wall and the floor.
    section.append((0.0, 0.0))

    front = [bm.verts.new((-BAY / 2.0, x, z)) for x, z in section]
    back = [bm.verts.new((BAY / 2.0, x, z)) for x, z in section]
    n = len(section)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    for k in range(1, n - 1):
        bm.faces.new((front[0], front[k + 1], front[k]))
        bm.faces.new((back[0], back[k], back[k + 1]))
    return finish(bm, "Hall_Cove")


def build_rail():
    """A handrail: a thin tube on posts, going down into the water.

    IT IS THE ONLY MAN-MADE OBJECT IN THE LEVEL AT HUMAN SCALE. Everything else -- arches,
    columns, vaults -- is architecture, and architecture has no fixed size: a tiled wall could
    be three metres or thirty. A handrail is always the same height because it is made for a
    hand, so the moment one appears the whole room snaps to a scale.

    Two of the references have exactly this, going down into water, and in both it is the thing
    that tells you the pool is deep enough to need one.
    """
    bm = bmesh.new()

    def tube(a, b, radius, sides=8):
        axis = Vector(b) - Vector(a)
        length = axis.length
        if length < 1e-6:
            return
        axis = axis.normalized()
        # Any vector not parallel to the axis gives a usable pair of perpendiculars.
        up = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
        right = axis.cross(up).normalized()
        up = right.cross(axis).normalized()
        rings = []
        for end in (Vector(a), Vector(b)):
            ring = []
            for j in range(sides):
                angle = j / sides * math.tau
                ring.append(bm.verts.new(
                    end + right * (math.cos(angle) * radius) + up * (math.sin(angle) * radius)))
            rings.append(ring)
        for j in range(sides):
            k = (j + 1) % sides
            bm.faces.new((rings[0][j], rings[0][k], rings[1][k], rings[1][j]))
        bm.faces.new(tuple(reversed(rings[0])))
        bm.faces.new(tuple(rings[1]))

    # The rail itself, sloping down and then bending to vertical where it enters the water --
    # which is the shape of every poolside handrail there has ever been.
    tube((0, 0, 10.5), (0, 7.5, 6.0), 0.22)
    tube((0, 7.5, 6.0), (0, 9.6, 0.4), 0.22)
    # Two posts.
    tube((0, 0.4, 0.0), (0, 0.4, 10.6), 0.26)
    tube((0, 6.4, 0.0), (0, 6.4, 7.4), 0.26)
    return finish(bm, "Hall_Rail")



def build_ripple():
    """A ring of surface ripple, to be grown and faded out over a water plane.

    === Why a mesh and not a decal ===

    The water in this level is one enormous flat plate, which is right -- still water on a flat
    floor IS one plane, and cutting it up puts a seam at every doorway. But a plane that never
    moves is a sheet of green glass, and every reference image of standing water has the
    surface doing something, however slight.

    Roblox cannot ripple a part, and the usual dodge -- a scrolling texture -- needs an uploaded
    asset this project does not have. What it CAN do is resize a MeshPart every frame. So the
    motion is a handful of these, grown from a few studs across to forty and faded out as they
    go, which is exactly what a drip landing on still water looks like from above.

    === Why two rings ===

    A single ring reads as a hoop someone dropped in. A real ripple is a train: a leading crest
    and a smaller one chasing it, the gap between them widening as they travel. Two concentric
    rings of different heights give that for about four hundred triangles, and it is the
    difference between "a circle appeared" and "something fell in the water".

    Flat on purpose -- a hundredth of the ring's width in height. Seen from the walkway fifty
    studs up, anything taller reads as a pipe lying in the pool.
    """
    bm = bmesh.new()
    around = 30
    sides = 8

    def ring(radius, tall, wide):
        rings = []
        for j in range(around):
            angle = j / around * math.tau
            out = Vector((math.cos(angle), math.sin(angle), 0.0))
            loop = []
            for k in range(sides):
                a = k / sides * math.tau
                loop.append(bm.verts.new(
                    out * (radius + math.cos(a) * wide) + Vector((0, 0, math.sin(a) * tall))))
            rings.append(loop)
        for j in range(around):
            n = (j + 1) % around
            for k in range(sides):
                m = (k + 1) % sides
                bm.faces.new((rings[j][k], rings[j][m], rings[n][m], rings[n][k]))

    # The leading crest, and the smaller one chasing it.
    ring(1.0, 0.05, 0.10)
    ring(0.70, 0.032, 0.07)
    return finish(bm, "Hall_Ripple")


def build_slide():
    """The flume: a helical trough that drops out of the last chamber and stops in mid-air.

    === What it is for ===

    It is how the level ends. You walk off the end of the walkway onto a tiled apron, hold E,
    and it takes you down one and a quarter turns and then RUNS OUT -- over the pit in the
    chamber floor, with nothing under it. The rest of the way down is a fall in the dark.

    So the piece has to do two contradictory things: read as a cheerful moulded-plastic water
    slide from across a tiled hall, and end abruptly enough that the drop is obviously not an
    accident. Hence the run-out that the previous version had is GONE. A flume that flattens
    off at the bottom is a flume that delivers you somewhere. This one does not.

    === What was wrong with the first two ===

    The first came out as a torn dark shard, because it was modelled as a SURFACE where it
    needed to be an OBJECT: no thickness, so every edge was a razor; no rim, so both ends were
    holes in a sheet; and 0.62 of a turn, which is a bend rather than a helix.

    The second fixed all that and then sat in the wrong place, twice over. Its drop was 34
    against a 22-unit ceiling height, so the bottom finished twenty studs UNDER the floor it
    was supposed to land on. And the ride that ran through it spiralled the other way: the
    export is z-up to y-up, so a Blender point (x, y, z) arrives as (x, z, -y), and the Lua
    that drove the rider had been written with a +sin where the mesh has a -sin. The rider
    left through the wall on the first quarter turn.

    Both of those are now single facts stated in one place each. The drop and the radius are
    the numbers in FloodedHallsService, and the handedness is written down in the comment above
    slidePoint() there.

    === The bounding box is part of the contract ===

    Roblox positions a MeshPart by its BOUNDING-BOX CENTRE, so a mesh whose bounds wander with
    its content cannot be placed accurately from Lua. Four tiny anchor triangles pin the bounds
    to exactly [-RAD, RAD] across and [-DROP, 0] down, which makes the centre exactly the helix
    axis at half depth -- which is the one point the placing code can compute without knowing
    anything about how the tube is built.
    """
    bm = bmesh.new()

    # From the module constants above, which FloodedHallsService mirrors and check_halls
    # compares. Divided by SCALE on the Lua side; if either moves the ride leaves the tube.
    radius = SLIDE_RADIUS
    drop = SLIDE_DROP
    bore = SLIDE_BORE
    wall = SLIDE_WALL
    turns = SLIDE_TURNS
    steps = 56
    sides = 11
    # HOW MUCH OF THE CIRCLE IS THERE. 250 degrees leaves the top open wide enough to see a
    # rider through and narrow enough that it still reads as a tube rather than a gutter.
    sweep = math.radians(250.0)
    # The mouth flares, because the one place a slide is generous is where you get into it.
    flare_over = 0.1
    flare_by = SLIDE_FLARE

    def station(t_at):
        """Centre of the tube at t along it, and the two axes across it."""
        angle = t_at * turns * math.tau
        centre = Vector((math.cos(angle) * radius, math.sin(angle) * radius, -drop * t_at))
        ahead_t = min(1.0, t_at + 1.0 / steps)
        ahead_angle = ahead_t * turns * math.tau
        ahead = Vector((math.cos(ahead_angle) * radius, math.sin(ahead_angle) * radius,
                        -drop * ahead_t))
        axis = ahead - centre
        if axis.length < 1e-6:
            axis = Vector((0, 1, 0))
        axis.normalize()
        side = axis.cross(Vector((0, 0, 1)))
        if side.length < 1e-6:
            side = Vector((1, 0, 0))
        side.normalize()
        return centre, side, side.cross(axis).normalized()

    def arc(centre, side, up, r):
        """One cross-section, from one top edge round the bottom to the other."""
        points = []
        for j in range(sides):
            # Centred on straight down and opening upward, so the gap is above the rider's
            # head rather than off to one side.
            a = -math.pi / 2 - sweep / 2 + (j / (sides - 1)) * sweep
            points.append(centre + side * (math.cos(a) * r) + up * (math.sin(a) * r))
        return points

    inner_rings, outer_rings = [], []
    for s in range(steps + 1):
        t_at = s / steps
        centre, side, up = station(t_at)
        # The flare, eased out over the first tenth so the mouth opens rather than steps.
        grow = 1.0
        if t_at < flare_over:
            ease = 1.0 - t_at / flare_over
            grow = 1.0 + flare_by * ease * ease
        inner_rings.append([bm.verts.new(pt) for pt in arc(centre, side, up, bore * grow)])
        outer_rings.append([bm.verts.new(pt)
                            for pt in arc(centre, side, up, bore * grow + wall)])

    for a, b in zip(inner_rings, inner_rings[1:]):
        for j in range(sides - 1):
            # Wound so the INSIDE faces the rider. This is the surface anyone looking at the
            # flume actually sees down the length of.
            bm.faces.new((a[j + 1], a[j], b[j], b[j + 1]))
    for a, b in zip(outer_rings, outer_rings[1:]):
        for j in range(sides - 1):
            bm.faces.new((a[j], a[j + 1], b[j + 1], b[j]))

    # THE LIP, along both top edges. The single detail that makes it read as a flume: a
    # continuous bright line tracing the whole helix, legible from right across the hall when
    # none of the surface detail is.
    for edge in (0, sides - 1):
        for a, b in zip(range(steps), range(1, steps + 1)):
            bm.faces.new((inner_rings[a][edge], outer_rings[a][edge],
                          outer_rings[b][edge], inner_rings[b][edge]))

    # And the two cut ends, so the tube is closed rather than a hole in a sheet. The bottom one
    # matters more than the top: it is the edge you go over, and it is what the eye reads as
    # "this stops here" from the moment the chamber comes into view.
    for ring_pair, flip in ((0, False), (steps, True)):
        for j in range(sides - 1):
            quad = (inner_rings[ring_pair][j], inner_rings[ring_pair][j + 1],
                    outer_rings[ring_pair][j + 1], outer_rings[ring_pair][j])
            bm.faces.new(tuple(reversed(quad)) if flip else quad)

    # ===== THE BOUNDS =====
    #
    # See the docstring. Four specks, too small to see and too small to matter, whose only job
    # is to make the bounding box a number the Lua can rely on.
    # THE PAD IS THE POINT. Anchors set a MINIMUM box, they do not clip anything -- so anchors
    # placed exactly at z = 0 and z = -drop are useless the moment the trough itself overhangs
    # them, which it does by a bore and a wall at both ends. The first attempt did exactly that
    # and came out with its centre half a unit low, which is two studs once the mesh is scaled:
    # enough to leave the mouth hanging over the apron rather than meeting it.
    #
    # Padded past every piece of geometry at both ends instead, the box is symmetric about
    # -drop/2 whatever the trough does, and that midpoint is the one thing the Lua relies on.
    reach = bore * (1.0 + flare_by) + wall + 0.2
    rad = radius + reach

    def speck(x, y, z):
        a = bm.verts.new((x, y, z))
        b = bm.verts.new((x + 0.02, y, z))
        c = bm.verts.new((x, y + 0.02, z))
        bm.faces.new((a, b, c))

    for sx in (-rad, rad):
        for sy in (-rad, rad):
            speck(sx, sy, reach)
            speck(sx, sy, -drop - reach)

    return finish(bm, "Hall_Slide")


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
    flag = "" if tris <= 10000 else "   !! OVER ROBLOX'S 10000-TRIANGLE LIMIT"
    print("    %-20s %6d tris%s" % (obj.name, tris, flag))
    return tris


def main():
    clear_scene()
    total = 0
    sizes = {}
    # HALL_SPIRAL IS NOT BUILT ANY MORE. It was the one landmark in the level and it was also
    # the one thing in it shaped like the route the level is not: a spiral rising into the
    # ceiling and stopping. With the route following the building's own corridors, a spiral
    # stair standing in the middle of it is the single most confusing object that could be
    # there. The builder is kept below in case a future room wants one.
    for builder in (build_arch_wall, build_column, build_vault,
                    build_curve_wall, build_steps, build_dome, build_hand,
                    build_cove, build_rail, build_slide, build_ripple):
        clear_scene()
        made = builder()
        points = [v.co for v in made.data.vertices]
        # Roblox axes: the export is z-up to y-up, so blender z is height and blender y is
        # depth. Recorded in the order a Vector3 wants them.
        sizes[made.name] = (
            max(p.x for p in points) - min(p.x for p in points),
            max(p.z for p in points) - min(p.z for p in points),
            max(p.y for p in points) - min(p.y for p in points),
        )
        total += export(made)
    print("    %-20s %6d tris across the kit" % ("(all eleven)", total))
    print("")
    # ===== THE SIZE TABLE, READY TO PASTE =====
    #
    # FloodedHallsService keeps a copy of what every piece measures and warns on the way in if
    # what is actually in Assets does not match. That is the only way this project can tell
    # "the code is wrong" apart from "you have not re-imported it yet", and it has now been the
    # answer twice. Printing it here is what stops the table going stale the moment a mesh
    # changes shape -- which is exactly when it matters.
    # WRITTEN OUT AS WELL AS PRINTED, so check_halls.py can compare the table in the Lua
    # against what this file last built without having to start Blender to find out. A printed
    # reminder is only read by whoever happens to be looking; a file is read by the gate.
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "kit_sizes.txt"),
              "w", encoding="utf-8") as handle:
        for name, size in sorted(sizes.items()):
            handle.write("%s %.3f %.3f %.3f\n" % (name, size[0], size[1], size[2]))

    print("EXPECTED_SIZE for FloodedHallsService.lua -- paste over the table there:")
    print("local EXPECTED_SIZE: { [string]: Vector3 } = {")
    for name, size in sorted(sizes.items()):
        print("\t%s = Vector3.new(%.3f, %.3f, %.3f)," % (name, size[0], size[1], size[2]))
    print("}")
    print("")
    print("Import all eleven into ReplicatedStorage/Assets/TileMeshes.")
    print("Set Material = Enum.Material.CeramicTiles on every one -- the tile grid is the")
    print("built-in material, not the mesh.")


if __name__ == "__main__":
    main()
