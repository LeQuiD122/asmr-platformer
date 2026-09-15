"""The Needoh platform: a bed of rounded cubes that gives underfoot.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_needoh.py

=== Why this exists rather than props on a jello slab ===

The first Needoh chunk was the free model's mesh scattered on top of a JelloSoda platform. That
gets the LOOK and none of the feel: the props are rigid decoration sitting on a surface that
deforms independently of them, so you press into the jello between the Needohs and the Needohs
themselves stay hard. A material in this game is a thing that gives when you stand on it, and
that one did not.

This is a real surface with a real rig, built the same way every other soft material here is:
one skinned mesh, one bone per cell, weighted so the top deforms and the base does not.

=== Why it borrows slime's rig ===

gen_slime_skinned.py already solves the hard half -- grid sizing, bone placement, vertex
weighting, validation and export -- and none of that is slime-specific. What IS slime-specific
is one function: the height field. So this swaps that out and reuses everything else, which is
what gen_ice_jello.py does for jello and for the same reason.

=== The shape ===

A Needoh is a rounded cube, and a bed of them is a lattice of squircles rather than a field of
domes. The difference matters: a dome has one high point and falls away in every direction, so a
grid of domes reads as bubble wrap. A squircle is flat across its top with the fall-off pushed
out to the edges, which is what makes each cell read as a solid block that happens to be soft --
and it gives the player a flat place to stand, which a dome does not.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_slime_skinned as SLIME

# ===== THE FORMS =====
#
# One layout is a texture; four are a MATERIAL. A player who meets the same 3x2 bed every time
# learns it in one crossing and never looks at it again, and the whole point of a soft surface
# here is that you look at it. These differ in the two things the eye actually reads at walking
# speed -- how MANY blobs there are and how ROUND they are -- and each is a different problem
# underfoot, because the flat landings end up different sizes and in different places.
#
#   pack       the original. Six rounded cubes, generous flats, easy going.
#   boulders   four huge ones. The flats are wide, but the grooves between them are deep
#              enough to see down, so it reads as stepping between things rather than on a
#              surface.
#   grid       fifteen small ones, nearly spherical. No single blob is big enough to stand on
#              squarely, so your feet are always across a seam -- the fiddliest of the four.
#   drift      offset rows, like brickwork, with sizes varying down the platform. The offset
#              is the point: nothing lines up, so there is no straight line to walk down.
FORMS = {
    "pack":     dict(cells=(3, 2), squareness=2.8, blob=1.70, shelf=0.34, stagger=0.0, vary=0.0),
    "boulders": dict(cells=(2, 2), squareness=3.4, blob=2.35, shelf=0.42, stagger=0.0, vary=0.0),
    "grid":     dict(cells=(5, 3), squareness=2.2, blob=1.15, shelf=0.22, stagger=0.0, vary=0.0),
    "drift":    dict(cells=(4, 3), squareness=2.6, blob=1.55, shelf=0.30, stagger=0.5, vary=0.42),
}

# The live settings. Swapped by build_form() rather than passed down, because the height
# function has to keep the signature slime's builder calls it with.
CELLS_X, CELLS_Z = 3, 2
SQUARENESS = 2.8
BLOB = 1.70
SHELF = 0.34
# How far alternate rows are offset along the platform, as a fraction of a cell. Zero is a
# square lattice; a half is a brick bond.
STAGGER = 0.0
# How much blob height varies cell to cell, as a fraction of BLOB. Zero is a uniform bed.
VARY = 0.0


def needoh_height(u: float, v: float, x: float, y: float) -> float:
    """A lattice of squircle-topped blobs, on the same bed slime uses."""
    # The bed. Reusing slime's sculpted base and rim keeps this platform's edges identical to
    # every other soft slab's, which is what lets the level generator butt them together.
    edge = min(min(u, 1.0 - u), min(v, 1.0 - v)) * 2.0
    rim = SLIME.smoothstep(0.0, SLIME.SHOULDER, edge)

    # Which cell this sample falls in, and where inside it. The stagger shifts alternate rows
    # along the platform, which is what turns a square lattice into a brick bond.
    cv = v * CELLS_Z
    row = math.floor(cv)
    cu = u * CELLS_X + (STAGGER if row % 2 == 1 else 0.0)
    fu, fv = (cu % 1.0) * 2.0 - 1.0, (cv % 1.0) * 2.0 - 1.0

    # THE SQUIRCLE. |a|^n + |b|^n = 1 with a large n: flat across the middle, rounded only near
    # the corners.
    radial = (abs(fu) ** SQUARENESS + abs(fv) ** SQUARENESS) ** (1.0 / SQUARENESS)

    # INVERTED EXPLICITLY, rather than by passing the band backwards. smoothstep here guards
    # against b <= a by degenerating into a hard step -- and a hard step that reads ONE at
    # radial >= 1, which is outside the cell. Handing it a descending band therefore does not
    # flip the ramp, it turns the surface inside out: every blob became a spike in the groove.
    body = 1.0 - SLIME.smoothstep(SHELF, 1.0, radial)

    # Per-cell unevenness, so a bed of identical blobs does not read as a print. Keyed off the
    # cell index rather than off position, so it travels with the cell rather than across it.
    # VARY scales it up into a real size difference for the forms that want one.
    cell_seed = math.floor(cu) * 7.0 + row * 13.0
    wobble = 0.06 * math.sin(cell_seed * 2.399) + 0.04 * math.sin(cell_seed * 5.077 + 1.3)
    wobble += VARY * BLOB * 0.5 * math.sin(cell_seed * 1.117 + 0.4)

    return (SLIME.sculpted_height(x, y)
        + SLIME.THICK * rim
        + (BLOB + wobble) * body * rim)


def report(mesh_obj, cols, rows, cell_x, cell_z, form, mesh_name):
    """Prints the SKINNED_PLATFORMS row this mesh needs, measured rather than guessed.

    THE SCULPTED-BED CONVENTION, not plain slime's. Slime draws its walkable plane partway
    up a 0.55-stud dome, because on a gentle dome that plane is never far from the surface
    under your feet. A Needoh bed is not gentle: the tops stand 1.19 studs above the grooves,
    so one plane through the middle would bury you on every blob and float you over every
    seam. Instead the plane is the highest point and per-cell drops bring each collider down
    to whatever is actually beneath it -- which is how salt and lava are already built.

    The drops are a MAXIMUM per cell, which is the whole reason cell_drops samples rather
    than reading the centre: a cell whose centre lands in a groove would otherwise get a
    floor at groove depth, and a floor at groove depth puts your feet inside the blob next
    to it.
    """
    def height_at(x, y):
        u = (x + SLIME.PLATFORM_X / 2.0) / SLIME.PLATFORM_X
        v = (y + SLIME.PLATFORM_Z / 2.0) / SLIME.PLATFORM_Z
        return needoh_height(u, v, x, y)

    zs = [vert.co.z for vert in mesh_obj.data.vertices]
    low, high = min(zs), max(zs)
    centre = (low + high) / 2.0
    walkable = high + 0.02
    drop_text = SLIME.cell_drops(height_at, SLIME.PLATFORM_X, SLIME.PLATFORM_Z,
        cols, rows, cell_x, cell_z)

    print('        { sizeX = %.0f, sizeZ = %.0f, meshHeight = %.2f, surfaceOffset = %.2f, '
          'mesh = "%s"%s%s },'
          % (SLIME.PLATFORM_X, SLIME.PLATFORM_Z, high - low, walkable - centre, mesh_name,
             "" if form == "pack" else (', form = "%s"' % form), drop_text))


def build_form(name: str) -> bool:
    """Build and export one form. Returns whether the mesh validated."""
    global CELLS_X, CELLS_Z, SQUARENESS, BLOB, SHELF, STAGGER, VARY
    setting = FORMS[name]
    CELLS_X, CELLS_Z = setting["cells"]
    SQUARENESS = setting["squareness"]
    BLOB = setting["blob"]
    SHELF = setting["shelf"]
    STAGGER = setting["stagger"]
    VARY = setting["vary"]

    SLIME.clear_scene()
    cols, rows, cell_x, cell_z = SLIME.compute_grid(SLIME.PLATFORM_X, SLIME.PLATFORM_Z)
    mesh_obj, top_indices, static_indices = SLIME.build_surface()

    nx = int(round(SLIME.PLATFORM_X / SLIME.RES)) + 1
    ny = int(round(SLIME.PLATFORM_Z / SLIME.RES)) + 1
    ok = SLIME.validate_mesh(mesh_obj, (nx - 1) * (ny - 1))

    arm_obj, centres = SLIME.build_armature(cols, rows, cell_x, cell_z)
    SLIME.assign_weights(mesh_obj, top_indices, static_indices, centres, cell_x, cell_z)

    # The original keeps its bare name, so the ChunkBuilder entry that already points at it
    # and the copy already imported into the place both go on working untouched.
    mesh_name = ("Needoh_Platform_Skinned" if name == "pack"
        else "Needoh_Platform_Skinned_" + name.capitalize())
    mesh_obj.name = mesh_name
    mesh_obj.data.name = mesh_name
    arm_obj.name = mesh_name + "_Rig"
    SLIME.export_fbx(mesh_obj, arm_obj, mesh_name + ".fbx")
    print("    %-36s %s" % (mesh_name, "ok" if ok else "MESH VALIDATION FAILED"))
    report(mesh_obj, cols, rows, cell_x, cell_z, name, mesh_name)
    return ok


def main():
    # SWAPPED IN, then put back. build_surface() calls slime_height by name, and forking the
    # whole function to change one line would mean maintaining two copies of the grid, the
    # face winding and the skirt -- all identical, and none of them the part that differs.
    original = SLIME.slime_height
    SLIME.slime_height = needoh_height
    print("")
    print("  ChunkBuilder SKINNED_PLATFORMS entry:")
    print("    Needoh = {")
    try:
        for name in FORMS:
            build_form(name)
    finally:
        SLIME.slime_height = original
    print("    },")
    print("")
    print("Done. Import every Needoh_Platform_Skinned* into Assets/TileMeshes.")


if __name__ == "__main__":
    main()
