"""
Measures the SLOPE of a sculpted form's top sheet, which is the thing that decides
whether it renders as a shape or as a row of torn slivers.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python check_form_slopes.py

The sand turtle went through four rounds of "widen this, soften that, fade the other"
against renders, and every round fixed something real without fixing the tearing,
because the tearing was never where it looked like it was. A render shows you WHERE a
surface breaks; it does not tell you how steep it got or which feature did it.

So: for every horizontally adjacent pair of samples on the top sheet, the rise over the
run. Anything past about 45 degrees is a staircase at these sample steps, and the report
names the worst offenders by location so the feature responsible is identifiable rather
than guessed at.
"""

import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_sand_surface as SAND
import gen_lambs_ear as LEAF

# Past this the surface stair-steps at the sample step, whatever it looks like in a
# render taken from a helpful angle.
STEEP_DEGREES = 45.0

# How much of the leaf bed's rim to leave out of the slope report, in studs. See the note
# at the exclusion itself.
MARGIN = 0.6

# The leaf bed gets its OWN threshold, and moving the number needs justifying rather than
# just asserting, so: 45 degrees is calibrated for the sand turtle, a smooth animal shape
# sampled at RES 0.28 where anything that steep is a tear. A leaf MARGIN is supposed to be
# steep -- it is the edge of a blade lying over another blade, and at RES 0.12 the bed runs
# up to about 69 degrees there with no stepping visible in a render at any angle.
#
# So the line goes at 72, just above the margins, and it is a LOOSE net rather than the
# real test. Measured: a healthy bed peaks at 68.9 degrees and the pedestal bug -- leaves
# ending in a wall, the one failure this mesh keeps having -- peaks at 72.9. Under a stud
# of separation is not something to hang a check on, because `lift` is random per leaf and
# the worst case depends on the draw.
#
# gen_lambs_ear.check_profile_tapers() is the definitive test for that bug and it is exact:
# it walks one leaf out to its rim and requires nothing left there. This stays because a
# steepening bed is worth seeing whatever caused it, and because the steepest angle is
# printed either way.
LEAF_STEEP_DEGREES = 72.0


def report(form, size_x, size_z):
    recipe = SAND.FORMS[form]
    SAND.clear_scene()
    with SAND.variant(SCULPT=recipe["sculpt"](size_x, size_z), **recipe["overrides"]):
        res = SAND.RES
        obj, _static, _follow, top_faces = SAND.build_surface(
            size_x, size_z, "probe_" + form, int(size_x * 977 + size_z * 131) + 5081
        )
        nx = max(2, int(round(size_x / res)) + 1)
        ny = max(2, int(round(size_z / res)) + 1)

    co = [v.co for v in obj.data.vertices]
    worst = []
    steep = 0
    pairs = 0
    for j in range(ny):
        for i in range(nx):
            here = j * nx + i
            for di, dj in ((1, 0), (0, 1)):
                oi, oj = i + di, j + dj
                if oi >= nx or oj >= ny:
                    continue
                other = oj * nx + oi
                a, b = co[here], co[other]
                run = math.hypot(b.x - a.x, b.y - a.y)
                if run < 1e-6:
                    continue
                angle = math.degrees(math.atan2(abs(b.z - a.z), run))
                pairs += 1
                if angle > STEEP_DEGREES:
                    steep += 1
                worst.append((angle, a.x, a.y, a.z))

    worst.sort(reverse=True)
    print(f"\n  {form} {size_x:g} x {size_z:g}   top sheet {nx} x {ny} at RES {res}")
    print(f"    {steep} of {pairs} adjacent pairs steeper than {STEEP_DEGREES:g} deg"
          f"  ({100.0 * steep / max(1, pairs):.2f}%)")
    print("    steepest samples (deg, x, y, z):")
    for angle, x, y, z in worst[:8]:
        print(f"      {angle:5.1f}   ({x:+6.2f}, {y:+6.2f})  z={z:+.2f}")
    return steep


def report_leaf_bed(size_x, size_z):
    """The same measurement on the lamb's ear bed, which is not a sand form but fails the
    same way and did.

    Its leaves went through three shapes that all looked like broken paving, and the cause
    was a vertical wall at every leaf margin -- the shingling lift was ADDED to the profile
    rather than scaling it, so each leaf ended in a cliff up to 0.75 studs tall. That is
    exactly what this check measures, and it would have named it in one run instead of
    three renders.
    """
    LEAF.BUTTER.clear_scene()
    obj, _static, _n_top = LEAF.build_surface(size_x, size_z, "probe_lambsear")
    nx = int(round(size_x / LEAF.RES)) + 1
    ny = int(round(size_z / LEAF.RES)) + 1

    co = [v.co for v in obj.data.vertices]
    worst, steep, pairs = [], 0, 0
    for j in range(ny):
        for i in range(nx):
            here = j * nx + i
            for di, dj in ((1, 0), (0, 1)):
                oi, oj = i + di, j + dj
                if oi >= nx or oj >= ny:
                    continue
                a, b = co[here], co[oj * nx + oi]
                # THE PERIMETER IS EXCLUDED, and it has to be or this measures the wrong
                # thing. The rim falloff takes the surface from full height to zero inside
                # about 0.18 studs so the bed ends in a wall and the skirt carries on down
                # -- that wall is deliberate, it is how every platform in the game ends,
                # and left in it swamps the report with 1400 pairs at 83 degrees and hides
                # whatever the leaves are doing. What is being asked here is only ever
                # "does the LEAF FIELD step", so only the leaf field is sampled.
                if (abs(a.x) > size_x / 2 - MARGIN or abs(a.y) > size_z / 2 - MARGIN
                        or abs(b.x) > size_x / 2 - MARGIN or abs(b.y) > size_z / 2 - MARGIN):
                    continue
                run = math.hypot(b.x - a.x, b.y - a.y)
                if run < 1e-6:
                    continue
                angle = math.degrees(math.atan2(abs(b.z - a.z), run))
                pairs += 1
                if angle > LEAF_STEEP_DEGREES:
                    steep += 1
                worst.append((angle, a.x, a.y, a.z))

    worst.sort(reverse=True)
    print("")
    print(f"  lambsear {size_x:g} x {size_z:g}   top sheet {nx} x {ny} at RES {LEAF.RES}")
    print(f"    {steep} of {pairs} adjacent pairs steeper than {LEAF_STEEP_DEGREES:g} deg"
          f"  ({100.0 * steep / max(1, pairs):.2f}%), steepest {worst[0][0]:.1f}")
    print("    steepest samples (deg, x, y, z):")
    for angle, x, y, z in worst[:5]:
        print(f"      {angle:5.1f}   ({x:+6.2f}, {y:+6.2f})  z={z:+.2f}")
    return steep


def main():
    total = 0
    for form, size_x, size_z in SAND.form_slabs():
        if form in SAND.FORMS:
            total += report(form, size_x, size_z)
    for size_x, size_z in LEAF.SIZES:
        total += report_leaf_bed(size_x, size_z)
    print("")
    print("Clean." if total == 0 else f"!! {total} steep pairs -- expect visible stepping.")


if __name__ == "__main__":
    main()
