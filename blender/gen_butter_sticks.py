"""Three sticks of butter laid side by side, as a platform you walk along.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_butter_sticks.py

=== Why this is not the imported mesh ===

The free model's wrapped stick is a static MeshPart with no armature. Dropped in as a platform
it would be a hard object with a nice label on it, and this game does not have hard objects --
every surface here gives when you stand on it. So the stick is REBUILT as a skinned surface,
the same way the Needoh bed was, and for the same reason: the imported mesh gets the look and
cannot get the feel.

=== Why three, and why lengthwise ===

One stick is 3-ish studs wide and a chunk is twelve. A single stick down the middle would be a
balance beam, which is a different chunk and a much meaner one. Three laid side by side fill
the width, and the two grooves between them run the length of the run -- so they read as three
distinct sticks while never once being something you have to step over.

Lengthwise also puts the ROUNDED ENDS at the entry and the exit, which is where the eye reads
the shape from. Turned across the run they would read as three logs.

=== Why the profile is nearly square ===

Butter is cut, not moulded. A generous radius would make these look like soap. The cross
section is a squircle at a high exponent: flat top, flat sides, and only the arris knocked off
-- which is exactly what a wire cutter leaves.
"""

import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_slime_skinned as SLIME

STICKS = 3

# High, because butter is cut square. 6 leaves a crisp edge with the arris knocked off; drop
# this toward 2 and the sticks turn into bars of soap.
SQUARE = 6.0

# How far a stick stands above the bed it sits in.
RISE = 1.45
# The fraction of a stick's half-width that stays flat, across and along. The rest is the
# rounding at the edge.
FLAT_ACROSS = 0.74
# Along its length the stick is flat almost end to end -- the rounding is only the cut face at
# each end, which is a small part of a 16-stud stick.
FLAT_ALONG = 0.90

# The gap between neighbouring sticks, as a fraction of a stick. Small: sticks in a pack touch,
# and the groove only has to be legible, not crossable.
GAP = 0.14


def stick_height(u: float, v: float, x: float, y: float) -> float:
    """Three rounded bars running the length of the platform."""
    # The bed, identical to every other soft slab's so the level generator can butt them up.
    edge = min(min(u, 1.0 - u), min(v, 1.0 - v)) * 2.0
    rim = SLIME.smoothstep(0.0, SLIME.SHOULDER, edge)

    # ACROSS the run: which stick, and where inside it.
    across = v * STICKS
    fv = (across % 1.0) * 2.0 - 1.0
    # ALONG the run: one stick spans the whole length, so this is just the position in it.
    fu = u * 2.0 - 1.0

    # A squircle in the two directions independently rather than one radial term, because the
    # stick is far longer than it is wide -- a single radius would taper it toward the ends
    # like a lozenge instead of cutting it flat.
    across_body = 1.0 - SLIME.smoothstep(FLAT_ACROSS, 1.0 - GAP, abs(fv))
    along_body = 1.0 - SLIME.smoothstep(FLAT_ALONG, 1.0, abs(fu))

    # Combined with a power mean rather than a product: a product rounds the four corners
    # twice over and pinches them, which on a cut edge looks like the butter has melted.
    body = (across_body ** SQUARE * along_body ** SQUARE) ** (1.0 / SQUARE)

    return SLIME.sculpted_height(x, y) + SLIME.THICK * rim + RISE * body * rim


def report(mesh_obj, cols, rows, cell_x, cell_z):
    """The SKINNED_PLATFORMS row, measured. Same convention as the Needoh bed."""
    def height_at(x, y):
        u = (x + SLIME.PLATFORM_X / 2.0) / SLIME.PLATFORM_X
        v = (y + SLIME.PLATFORM_Z / 2.0) / SLIME.PLATFORM_Z
        return stick_height(u, v, x, y)

    zs = [vert.co.z for vert in mesh_obj.data.vertices]
    low, high = min(zs), max(zs)
    centre = (low + high) / 2.0
    walkable = high + 0.02
    drop_text = SLIME.cell_drops(height_at, SLIME.PLATFORM_X, SLIME.PLATFORM_Z,
        cols, rows, cell_x, cell_z)

    print("")
    print("  ChunkBuilder SKINNED_PLATFORMS entry:")
    print("    ButterStick = {")
    print('        { sizeX = %.0f, sizeZ = %.0f, meshHeight = %.2f, surfaceOffset = %.2f, '
          'mesh = "ButterSticks_Platform_Skinned"%s },'
          % (SLIME.PLATFORM_X, SLIME.PLATFORM_Z, high - low, walkable - centre, drop_text))
    print("    },")
    print("    (bbox %.2f .. %.2f, centre %.2f, walkable plane %.2f, %d x %d cells)"
          % (low, high, centre, walkable, cols, rows))
    print("")


def main():
    original = SLIME.slime_height
    SLIME.slime_height = stick_height
    try:
        SLIME.clear_scene()
        cols, rows, cell_x, cell_z = SLIME.compute_grid(SLIME.PLATFORM_X, SLIME.PLATFORM_Z)
        mesh_obj, top_indices, static_indices = SLIME.build_surface()

        nx = int(round(SLIME.PLATFORM_X / SLIME.RES)) + 1
        ny = int(round(SLIME.PLATFORM_Z / SLIME.RES)) + 1
        ok = SLIME.validate_mesh(mesh_obj, (nx - 1) * (ny - 1))

        arm_obj, centres = SLIME.build_armature(cols, rows, cell_x, cell_z)
        SLIME.assign_weights(mesh_obj, top_indices, static_indices, centres, cell_x, cell_z)

        # ONE LABEL PER STICK. Without a UV map at all a texture cannot land anywhere, which
        # is why the new sticks came out blank next to the imported butter that carries its
        # wrapper print.
        #
        # U runs the length of a stick and V runs across that stick alone -- not across the
        # whole platform -- so the image wraps once per stick and the print reads the right
        # way up on all three. Mapping V over the full width would stretch one label across
        # the lot and put two thirds of it down the grooves.
        # MAPPED TO THE FLAT TOP, not around the whole stick.
        #
        # Spreading V over the stick's full width put most of the wrapper image on the
        # rounded shoulders, where it is stretched and seen edge-on -- so the label read as
        # sitting crooked and running off the side. The part of a stick you actually see the
        # print on is the flat top, which is the band between the two shoulder rolls.
        #
        # So that band is remapped to the whole of V, and everything outside it clamps to the
        # texture edge. The image lands square on the top face, once per stick, right way up.
        mesh = mesh_obj.data
        if not mesh.uv_layers:
            mesh.uv_layers.new(name="UVMap")
        uv = mesh.uv_layers.active.data
        # Where the flat top starts and ends within one stick, in 0..1 across it. FLAT_ACROSS
        # is measured from the centre, so the band is symmetric about the middle.
        edge = (1.0 - FLAT_ACROSS) / 2.0
        span = FLAT_ACROSS
        for poly in mesh.polygons:
            for loop_index in poly.loop_indices:
                co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
                u = (co.x + SLIME.PLATFORM_X / 2.0) / SLIME.PLATFORM_X
                across = (co.y + SLIME.PLATFORM_Z / 2.0) / SLIME.PLATFORM_Z * STICKS
                v = ((across % 1.0) - edge) / span
                uv[loop_index].uv = (u, min(1.0, max(0.0, v)))

        name = "ButterSticks_Platform_Skinned"
        mesh_obj.name = name
        mesh_obj.data.name = name
        arm_obj.name = name + "_Rig"
        SLIME.export_fbx(mesh_obj, arm_obj, name + ".fbx")
        print("    %-30s %s" % (name, "ok" if ok else "MESH VALIDATION FAILED"))
        report(mesh_obj, cols, rows, cell_x, cell_z)
    finally:
        SLIME.slime_height = original

    print("Done. Import ButterSticks_Platform_Skinned into ReplicatedStorage/Assets/TileMeshes.")


if __name__ == "__main__":
    main()
