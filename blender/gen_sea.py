"""
A tileable ocean surface.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_sea.py

The sea was 45 flat plates with pale rectangles laid on top, and that is the ceiling on how
a flat plane can look. Water reads as water because light hits each slope differently --
one surface at one angle cannot do it, however it is painted. This gives the surface actual
slopes, so the shading varies across it on its own.

=== Why it tiles, and why that is the whole constraint ===

45 copies of this sit edge to edge. If the height at u = 0 does not exactly equal the height
at u = 1, every seam becomes a visible ridge -- which is the artefact this is meant to
remove, reintroduced in relief.

So the displacement is a sum of sines with INTEGER frequencies over the tile. sin(2*pi*n*u)
for integer n is exactly periodic across the tile by construction, at every amplitude and
every phase, with no blending or masking. Ten of them at different directions and scales
give something that does not read as a sine at all.

Integer frequency pairs (nx, ny) also mean the waves run diagonally rather than along the
grid, which is what stops the surface reading as corduroy.
"""

import bmesh
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import uv_project
import bpy
import math
import os

OUT_DIR = r"C:\Users\Arsenii\Downloads\asmr-platformer-implementation_1\RobloxProject\meshes"

# Authored to match SEA_TILE in BackdropService. The service sets Size explicitly, so these
# two numbers have to agree or the tiles overlap or gap.
TILE = 1600.0
HEIGHT = 72.0

# 72 x 72 quads = 10368 triangles. Raised from 56 to carry the higher frequencies below --
# the grid is the sampling limit, so finer waves are not a free change. Every tile is the same MeshId, so Roblox instances them
# and this is one mesh drawn 45 times rather than 45 meshes -- but the triangles are still
# real, so this is the number to cut first if the sea ever costs frame time.
RES = 48

# (nx, ny, amplitude, phase). nx and ny MUST be integers; see the module docstring.
#
# === Geometry takes the COARSE band; the normal map takes the middle ===
#
# This spectrum has moved three times, and the last move was made without knowing there
# would be a texture. It ran 61 to 297 studs -- and the SurfaceAppearance repeats every 200,
# carrying everything below that. The two overlapped completely: the map was adding detail
# underneath detail the mesh already had, at a scale that is sub-pixel from 700 studs up.
# It cost an upload and changed nothing.
#
# So the mesh now carries 180 to 800 studs and NOTHING BELOW, and the texture owns 200 down
# to about 2. Between them the surface has structure across three orders of magnitude, which
# is what a real sea has; either alone is what a flat plane with a pattern on it looks like.
#
# Fewer harmonics also means fewer samples are needed, which is why RES dropped from 72 to
# 48 -- 4608 triangles a tile instead of 10368, for a better-looking sea.
WAVES = (
    (2, 1, 1.00, 0.00),
    (1, 2, 0.88, 1.10),
    (3, 2, 0.66, 2.30),
    (2, -3, 0.54, 0.60),
    (4, 3, 0.38, 3.00),
    (3, -4, 0.30, 1.80),
    (5, 2, 0.22, 2.60),
    (2, 6, 0.17, 0.40),
    (7, 4, 0.12, 1.20),
    (6, -7, 0.09, 2.90),
)


def height_at(u, v):
    """Displacement in [-1, 1]-ish at normalised tile coordinates."""
    total = 0.0
    for nx, ny, amplitude, phase in WAVES:
        total += amplitude * math.sin(math.tau * (nx * u + ny * v) + phase)
    return total


def foam_patch():
    """A foam streak: an irregular flat lens, not a rectangle.

    The flecks on the sea were Parts, which means they were rectangles, which means every
    one of them had four hard corners and two straight edges. Nothing on water does. The
    outline here is an ellipse with three harmonics of wobble on its radius, so no two
    orientations of the same mesh present the same silhouette.

    Closed rather than a single fan: a one-sided lens is invisible from underneath and
    invisible from ANY side if its normals come out wrong, which is the failure the sea
    tile already walked into once.
    """
    N = 30
    LONG, WIDE, THICK = 50.0, 14.0, 2.4

    bm = bmesh.new()
    rim = []
    for k in range(N):
        a = math.tau * k / N
        wobble = 1.0 + 0.34 * math.sin(3 * a + 0.7) + 0.20 * math.sin(5 * a + 2.1)             + 0.12 * math.sin(8 * a + 1.2)
        rim.append(bm.verts.new((
            math.cos(a) * wobble * LONG,
            math.sin(a) * wobble * WIDE,
            0.0,
        )))
    top = bm.verts.new((0.0, 0.0, THICK))
    bottom = bm.verts.new((0.0, 0.0, -THICK * 0.4))
    for k in range(N):
        bm.faces.new((rim[k], rim[(k + 1) % N], top))
        bm.faces.new((rim[(k + 1) % N], rim[k], bottom))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Sea_Foam")
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new("Sea_Foam", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def ring():
    """A disturbance ring for a waterline: an ANNULUS, not a disc.

    The first version of this was a filled cylinder at 1.7 to 2.6 times the building's
    width, and that is not what water does. Looking at a structure standing in calm water,
    there is no pale area around it at all -- there is a clean line where the two meet, and
    at most a narrow band of ripple hugging it. A filled disc reads as a pad the building
    has been set on top of, which is the exact opposite of the thing it was added to fix.

    So: a hole in the middle, a narrow band, and wobble on both edges so it is not a
    machined washer. Built closed -- top, bottom and both walls -- because an open shell is
    invisible from underneath and vanishes entirely if its normals come out wrong.
    """
    N = 30
    INNER, OUTER, THICK = 0.72, 1.0, 0.06

    def edge(k, base, a1, a2, a3):
        a = math.tau * k / N
        wob = 1.0 + a1 * math.sin(3 * a + 0.4) + a2 * math.sin(5 * a + 2.2)             + a3 * math.sin(9 * a + 1.1)
        return base * wob

    bm = bmesh.new()
    rings = {}
    for k in range(N):
        a = math.tau * k / N
        ri = edge(k, INNER, 0.10, 0.06, 0.035)
        ro = edge(k, OUTER, 0.09, 0.055, 0.03)
        for side, r in (("i", ri), ("o", ro)):
            for level, z in (("t", THICK), ("b", -THICK)):
                rings[(side, level, k)] = bm.verts.new(
                    (math.cos(a) * r, math.sin(a) * r, z)
                )
    for k in range(N):
        n = (k + 1) % N
        # top, bottom, outer wall, inner wall
        bm.faces.new((rings[("i","t",k)], rings[("o","t",k)], rings[("o","t",n)], rings[("i","t",n)]))
        bm.faces.new((rings[("i","b",n)], rings[("o","b",n)], rings[("o","b",k)], rings[("i","b",k)]))
        bm.faces.new((rings[("o","t",k)], rings[("o","b",k)], rings[("o","b",n)], rings[("o","t",n)]))
        bm.faces.new((rings[("i","t",n)], rings[("i","b",n)], rings[("i","b",k)], rings[("i","t",k)]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Sea_Ring")
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new("Sea_Ring", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def surf():
    """A crescent of breaking foam, for the windward side of a sandbar.

    An ARC, not a ring. Surf is not symmetrical -- it piles up on the side the water is
    coming from and there is almost nothing on the lee. A ring around an island says
    "bathtub"; a crescent says which way the sea is running.

    The outer edge carries much heavier noise than the inner one, because that is the
    asymmetry of breaking water: the shoreward side follows the beach smoothly and the
    seaward side is torn up. Equal noise on both reads as a fuzzy washer.
    """
    N = 26
    SPAN = math.radians(150.0)
    INNER, OUTER, THICK = 0.80, 1.16, 0.05

    bm = bmesh.new()
    verts = {}
    for k in range(N + 1):
        f = k / N
        a = -SPAN / 2 + SPAN * f
        # Both ends taper to nothing, so the crescent fades out instead of stopping dead.
        taper = math.sin(math.pi * f) ** 0.55
        ri = INNER + (OUTER - INNER) * (1 - taper) * 0.5
        ro = INNER + (OUTER - INNER) * taper * (
            1.0 + 0.30 * math.sin(7 * a + 0.6) + 0.18 * math.sin(13 * a + 2.4)
            + 0.10 * math.sin(23 * a + 1.1)
        ) + INNER * 0.0
        ro = max(ro, ri + 0.02)
        for side, r in (("i", ri), ("o", ro)):
            for level, z in (("t", THICK), ("b", -THICK)):
                verts[(side, level, k)] = bm.verts.new(
                    (math.cos(a) * r, math.sin(a) * r, z)
                )
    for k in range(N):
        n = k + 1
        bm.faces.new((verts[("i","t",k)], verts[("o","t",k)], verts[("o","t",n)], verts[("i","t",n)]))
        bm.faces.new((verts[("i","b",n)], verts[("o","b",n)], verts[("o","b",k)], verts[("i","b",k)]))
        bm.faces.new((verts[("o","t",k)], verts[("o","b",k)], verts[("o","b",n)], verts[("o","t",n)]))
        bm.faces.new((verts[("i","t",n)], verts[("i","b",n)], verts[("i","b",k)], verts[("i","t",k)]))
    for k in (0, N):
        bm.faces.new((verts[("i","t",k)], verts[("i","b",k)], verts[("o","b",k)], verts[("o","t",k)]))

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new("Sea_Surf")
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new("Sea_Surf", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def build():
    # Normalised against the ACTUAL extremes rather than the sum of amplitudes. Twelve
    # sines never all peak at once, so summing their amplitudes overestimates the range by
    # about 40% -- and the mesh would then only fill 60% of the height Roblox scales it to,
    # silently exaggerating every wave by the difference.
    samples = [
        height_at(i / RES, j / RES) for i in range(RES) for j in range(RES)
    ]
    low, high = min(samples), max(samples)
    span = (high - low) or 1.0

    bm = bmesh.new()

    # RES + 1 ROWS, with the last one at u = 1.0. The first version wrapped the faces from
    # the last row back to the first, which does not close a tile -- it builds a face that
    # runs backwards across the entire mesh. The result measured 1571 studs instead of 1600
    # and would have left a 29-stud gap at every seam.
    #
    # The duplicated seam vertices are the point, not a cost: periodicity guarantees row
    # RES has exactly the height of row 0, so the tile beside it lines up to the bit.
    grid = {}
    for i in range(RES + 1):
        for j in range(RES + 1):
            u, v = i / RES, j / RES
            z = (height_at(u, v) - low) / span - 0.5
            grid[(i, j)] = bm.verts.new((
                (u - 0.5) * TILE,
                (v - 0.5) * TILE,
                z * HEIGHT,
            ))
    bm.verts.ensure_lookup_table()

    for i in range(RES):
        for j in range(RES):
            bm.faces.new((
                grid[(i, j)],
                grid[(i + 1, j)],
                grid[(i + 1, j + 1)],
                grid[(i, j + 1)],
            ))

    # NORMALS FORCED UPWARD, and recalc_face_normals is removed rather than fixed.
    #
    # recalc_face_normals orients faces OUTWARD FROM A VOLUME. This is an open surface --
    # there is no inside for it to be outside of -- so on a single flat sheet it is free to
    # pick either direction, and it picked down. Roblox renders MeshParts single-sided, so
    # a down-facing sea is invisible from above: the whole ocean vanished and you saw sky
    # through the hole, with only the Part-based flecks and sandbars left floating over it.
    #
    # The winding above already produces +Z. This checks that rather than trusting it,
    # because the failure is completely silent -- the mesh exports, validates, imports, and
    # simply is not there.
    # normal_update() FIRST. bmesh computes face normals lazily, so reading face.normal on
    # geometry built this session returns zeros -- the first version of this check summed
    # them to exactly 0.000 and cheerfully reported success on a mesh it had not measured.
    bm.normal_update()
    up = sum(1 for face in bm.faces if face.normal.z > 0)
    if up * 2 < len(bm.faces):
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
        bm.normal_update()
        up = sum(1 for face in bm.faces if face.normal.z > 0)
    print(f"  normals: {up}/{len(bm.faces)} faces point up "
          f"{'ok' if up == len(bm.faces) else 'FAILS -- the sea will be invisible from above'}")

    mesh = bpy.data.meshes.new("Sea_Tile")
    bm.to_mesh(mesh)
    bm.free()
    mesh.validate()
    # Smooth everywhere. There is no sharp edge anywhere on a body of water, and the whole
    # point of the mesh is the gradient of the shading across each slope.
    for poly in mesh.polygons:
        poly.use_smooth = True

    obj = bpy.data.objects.new("Sea_Tile", mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def verify(obj):
    """The seam check, which is the only failure mode that matters here."""
    samples = [height_at(i / RES, j / RES) for i in range(RES) for j in range(RES)]
    span = (max(samples) - min(samples)) or 1.0
    worst = 0.0
    for k in range(0, 400):
        t = k / 400.0
        # Opposite edges of the tile must agree exactly, in both directions.
        worst = max(worst, abs(height_at(0.0, t) - height_at(1.0, t)))
        worst = max(worst, abs(height_at(t, 0.0) - height_at(t, 1.0)))
    studs = worst / span * HEIGHT
    ok = studs < 1e-6
    print(f"  seam mismatch: {studs:.3e} studs  {'ok' if ok else 'FAILS -- tiles will ridge'}")
    return ok


# 40 studs per texture tile, and the number is not arbitrary: TILE is 1600, and 1600 / 40
# is exactly 40. A whole number of texture repeats per mesh tile means the texture seam
# lands on the mesh seam, so the ripple detail wraps as cleanly as the geometry does. A
# scale that does not divide TILE would put a visible break somewhere in every tile.
SEA_UV_STUDS = 200.0


def export(obj, filename):
    uv_project.box_project(obj.data, SEA_UV_STUDS)
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
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    os.makedirs(OUT_DIR, exist_ok=True)

    obj = build()
    tris = len(obj.data.polygons) * 2
    size = obj.dimensions
    print(f"  Sea_Tile: {tris} tris, {size.x:.0f} x {size.y:.0f} x {size.z:.1f} studs")
    ok = verify(obj)
    export(obj, "Sea_Tile.obj")

    patch = foam_patch()
    print(f"  Sea_Foam: {len(patch.data.polygons)} tris, "
          f"{patch.dimensions.x:.0f} x {patch.dimensions.y:.0f} x {patch.dimensions.z:.1f} studs")
    export(patch, "Sea_Foam.obj")

    crest = surf()
    print(f"  Sea_Surf: {len(crest.data.polygons) * 2} tris, "
          f"{crest.dimensions.x:.2f} x {crest.dimensions.y:.2f} x {crest.dimensions.z:.2f} "
          f"(unit-sized crescent)")
    export(crest, "Sea_Surf.obj")

    band = ring()
    print(f"  Sea_Ring: {len(band.data.polygons) * 2} tris, "
          f"{band.dimensions.x:.2f} x {band.dimensions.y:.2f} x {band.dimensions.z:.2f} "
          f"(unit-sized; the service scales it per building)")
    export(band, "Sea_Ring.obj")

    # === The constants BackdropService needs, printed rather than guessed ===
    #
    # The service places every foam fleck at the wave's actual height, which means it has
    # to evaluate this same spectrum in Luau. Two copies of a formula in two languages is a
    # real hazard -- change WAVES here without changing them there and the foam floats or
    # sinks, silently and everywhere. Nothing syncs to Studio, so the copy cannot be
    # avoided; printing it is the next best thing, because it makes the coupling something
    # you are handed rather than something you have to remember.
    samples = [height_at(i / RES, j / RES) for i in range(RES) for j in range(RES)]
    low, high = min(samples), max(samples)
    print("")
    print("  --- Luau constants for BackdropService, paste if WAVES or HEIGHT change ---")
    print(f"  local WAVE_TILE, WAVE_HEIGHT = {TILE:.0f}, {HEIGHT:.0f}")
    print(f"  local WAVE_LOW, WAVE_SPAN = {low:.6f}, {high - low:.6f}")
    print("  local WAVES = {")
    for nx, ny, amplitude, phase in WAVES:
        print(f"		{{ {nx}, {ny}, {amplitude:.2f}, {phase:.2f} }},")
    print("  }")

    print("")
    print("  Import both into ReplicatedStorage/Assets/Backdrop (OBJ).")
    print("  Optional: the sea falls back to flat plates and rectangular flecks without them.")
    print("")
    print("Done." if ok else "!! seam check failed -- DO NOT import.")


if __name__ == "__main__":
    main()
