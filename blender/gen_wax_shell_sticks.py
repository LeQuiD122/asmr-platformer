"""The wrapper for the butter sticks: the same cracking shell, draped over the ridges.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_wax_shell_sticks.py

=== Why this is not just another size in gen_wax_shell ===

It nearly is. It uses that file's shard partition, its rig, its weights and its export -- the
cracking behaviour is entirely inherited, so these plates break exactly the way the butter
slab's do, which is the point.

The one thing it changes is that the plates are no longer flat. A flat sheet over three
ridges bridges them and hides the chunk under a white lid; the wrapper has to sit DOWN in the
grooves between the sticks the way paper does. gen_wax_shell now takes a relief function for
exactly that, and this file supplies the one that matches the stick surface.

=== Why the relief is the stick height field itself ===

Not an approximation of it. The same function that generated the butter underneath is called
here, offset so its highest point is zero -- so the coating is parallel to the surface it
coats at every point, and the gap between them is a constant SHELL_THICKNESS rather than
something that opens and closes across the platform.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_butter_sticks as STICKS
import gen_slime_skinned as SLIME
import gen_wax_shell as SHELL

SIZE_X, SIZE_Z = 16.0, 12.0


def surface_peak() -> float:
    """The highest point of the stick surface, which the plates are measured down from."""
    best = -1e9
    steps = 96
    for i in range(steps + 1):
        for j in range(steps + 1):
            u, v = i / steps, j / steps
            x = -SIZE_X / 2.0 + u * SIZE_X
            y = -SIZE_Z / 2.0 + v * SIZE_Z
            best = max(best, STICKS.stick_height(u, v, x, y))
    return best


def main():
    peak = surface_peak()

    def relief(x, z):
        # The generator hands plate coordinates as (x, z) where z is the across-run axis --
        # the same axis the stick field calls y. Named differently in the two files because
        # one is thinking in Blender's plane and the other in Roblox's.
        u = (x + SIZE_X / 2.0) / SIZE_X
        v = (z + SIZE_Z / 2.0) / SIZE_Z
        # Clamped to 0 at the top so the coating never rises above the mesh it was measured
        # against, which would invalidate the surfaceOffset ChunkBuilder places it by.
        return min(0.0, STICKS.stick_height(u, v, x, z) - peak)

    SHELL.RELIEF = relief
    try:
        entries, all_ok = [], True
        for variant in SHELL.VARIANTS:
            SHELL.clear_scene()
            obj, arm, entry, ok, _ = SHELL.build_variant(SIZE_X, SIZE_Z, variant)
            all_ok = all_ok and ok
            # RENAMED so it cannot be confused with a flat 16x12 shell. Two coatings of the
            # same size that drape differently would otherwise be one lookup apart.
            name = "Wax_Shell_Sticks_%dx%d_%s" % (SIZE_X, SIZE_Z, variant)
            obj.name = name
            obj.data.name = name
            arm.name = name + "_Rig"
            SHELL.export_fbx(obj, arm, name + ".fbx")
            entries.append(entry.replace(
                SHELL.mesh_name(SIZE_X, SIZE_Z, variant), name))
    finally:
        SHELL.RELIEF = None

    print("")
    print("  ChunkBuilder WAX_SHELLS entry:")
    print("    ButterStick = {")
    for entry in entries:
        print(entry)
    print("    },")
    print("    (surface peak %.2f, so the coating drops to %.2f in the deepest groove)"
          % (peak, relief(0.0, -SIZE_Z / 2.0 + SIZE_Z / STICKS.STICKS)))
    print("")
    print("Done." if all_ok else "!! a mesh failed validation -- DO NOT import.")


if __name__ == "__main__":
    main()
