"""
Per-cell tile meshes for the ASMR platformer. Blender 5.2.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_tile_meshes.py

=== Why tiles rather than platform-sized meshes ===

Deformation acts on individual sub-region cells, and a platform-sized mesh is one
rigid object that cannot dip under a foot. So every material is a tile mesh, and
the Luau side scales each MeshPart to its cell size (cells run about 2.7 to 3.2
studs depending on platform dimensions, so one nominal 3.2 tile stretches to fit).

Two families:

  INDEPENDENT  (bubble wrap, kinetic sand, soap, butter-wax)
    Height falls to zero at all four borders, so each tile is a closed rounded
    object. Visible seams are wanted: these materials are granular or breakable
    and reading as discrete lumps is correct.

  EDGE-MATCHED  (honey, slime)
    Continuous materials, where seams would fight the illusion of one pool. The
    interior edges sit at exactly EDGE_H so neighbouring tiles form an unbroken
    surface, and only the platform's outer boundary rolls down with a meniscus.
    Three variants, placed by the generator with rotation:
      Interior  all four edges shared
      Edge      one outer side
      Corner    two adjacent outer sides
    A seam only becomes visible when a tile actually sinks, which is exactly when
    you want to see one.

    Surface detail on these is periodic and vanishes at the tile border, because a
    tile cannot know where it sits on the platform. Platform-scale features (one
    big dome, concentric pour rings) are therefore impossible here. That is fine:
    a liquid levels, so a 16-stud pool 1.4 studs deep really is nearly flat, and
    the earlier platform-sized attempt with a pronounced dome read as a cushion.

=== Luau-side requirements this contract implies ===

  * TILE_GAP must be 0 for honey and slime, or the shared edges cannot meet.
    Keep the existing gap for the four independent materials.
  * ChunkBuilder must choose Interior/Edge/Corner per cell from its grid position
    and rotate the Edge/Corner variants to face outward.
  * Meshes are visual only: CanCollide = false, with the existing Part slab
    keeping collision. Box fidelity on a tile with a meniscus would put solid
    invisible floor outside the visible surface.
"""

import bmesh
import bpy
import math
import os

OUT_DIR = r"C:\Users\Arsenii\Downloads\asmr-platformer-implementation_1\RobloxProject\meshes"

TILE = 3.2      # nominal cell size in studs
EDGE_H = 1.0    # shared rim height for the edge-matched family


# --------------------------------------------------------------------------- #
# Maths helpers
# --------------------------------------------------------------------------- #

def smoothstep(a, b, x):
    if b <= a:
        return 0.0 if x < a else 1.0
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def _hash2(i, j, seed):
    n = (i * 374761393 + j * 668265263 + seed * 1442695040) & 0x7FFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0x7FFFFFFF
    n = n ^ (n >> 16)
    return (n % 1000003) / 1000003.0


def value_noise(x, y, freq, seed):
    """Smoothed value noise. Deterministic, so reruns produce identical meshes."""
    fx, fy = x * freq, y * freq
    i, j = math.floor(fx), math.floor(fy)
    tx, ty = fx - i, fy - j
    sx = tx * tx * (3.0 - 2.0 * tx)
    sy = ty * ty * (3.0 - 2.0 * ty)
    a = _hash2(i, j, seed)
    b = _hash2(i + 1, j, seed)
    c = _hash2(i, j + 1, seed)
    d = _hash2(i + 1, j + 1, seed)
    return (a * (1 - sx) + b * sx) * (1 - sy) + (c * (1 - sx) + d * sx) * sy


def fbm(x, y, freq, seed, octaves=3):
    total, amp, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        total += amp * (value_noise(x, y, freq * (2 ** o), seed + o * 17) - 0.5)
        norm += amp
        amp *= 0.5
    return total / norm


# --------------------------------------------------------------------------- #
# Mesh builder
# --------------------------------------------------------------------------- #

def build(name, size_x, size_y, res, height_fn, base_fn=None):
    nx = max(2, int(round(size_x / res))) + 1
    ny = max(2, int(round(size_y / res))) + 1

    verts, faces = [], []
    for j in range(ny):
        for i in range(nx):
            u, v = i / (nx - 1), j / (ny - 1)
            x, y = (u - 0.5) * size_x, (v - 0.5) * size_y
            verts.append((x, y, height_fn(u, v, x, y)))

    def top(i, j):
        return j * nx + i

    for j in range(ny - 1):
        for i in range(nx - 1):
            faces.append((top(i, j), top(i + 1, j), top(i + 1, j + 1), top(i, j + 1)))
    top_faces = len(faces)

    ring = []
    for i in range(nx - 1):
        ring.append(top(i, 0))
    for j in range(ny - 1):
        ring.append(top(nx - 1, j))
    for i in range(nx - 1, 0, -1):
        ring.append(top(i, ny - 1))
    for j in range(ny - 1, 0, -1):
        ring.append(top(0, j))

    n = len(ring)
    wall = []
    for k, idx in enumerate(ring):
        x, y, _ = verts[idx]
        wall.append(len(verts))
        verts.append((x, y, base_fn(k / n) if base_fn else 0.0))

    for k in range(n):
        faces.append((ring[k], ring[(k + 1) % n], wall[(k + 1) % n], wall[k]))

    centre = len(verts)
    verts.append((0.0, 0.0, 0.0))
    for k in range(n):
        faces.append((centre, wall[k], wall[(k + 1) % n]))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    for index, poly in enumerate(mesh.polygons):
        poly.use_smooth = index < top_faces

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    flag = "  !! OVER 10000 TRI LIMIT" if tris > 10000 else ""
    print(f"  {name:<26} {len(mesh.vertices):>5} verts  {tris:>5} tris{flag}")
    return obj


# --------------------------------------------------------------------------- #
# Independent tiles
# --------------------------------------------------------------------------- #

def all_edge_rim(u, v, roll):
    edge = min(min(u, 1 - u), min(v, 1 - v)) * 2.0
    return smoothstep(0.0, roll, edge)


# --- Bubble wrap: 2x2 caps on a film ---------------------------------------- #
WRAP_SHEET, WRAP_RISE, WRAP_FILL = 0.30, 0.42, 0.46
WRAP_PERIOD = TILE / 2.0


def bubble_tile(u, v, x, y):
    """
    cos-squared caps, not sphere caps: a sphere has a vertical tangent at its rim
    so neighbours meet in a hard X ridge and each dome renders as a pyramid.
    Resolution is set so each cap gets ~10 samples across; below about 8 the square
    grid's own symmetry shows through and they cone again.
    """
    rim = all_edge_rim(u, v, 0.14)
    base = WRAP_SHEET * rim
    inset = smoothstep(0.01, 0.10, min(min(u, 1 - u), min(v, 1 - v)) * 2.0)
    if inset <= 0.0:
        return base
    cx = (math.floor(x / WRAP_PERIOD) + 0.5) * WRAP_PERIOD
    cy = (math.floor(y / WRAP_PERIOD) + 0.5) * WRAP_PERIOD
    r = math.hypot(x - cx, y - cy)
    radius = WRAP_PERIOD * WRAP_FILL
    if r >= radius:
        return base
    return base + WRAP_RISE * math.cos(math.pi * 0.5 * (r / radius)) ** 2 * inset


# --- Kinetic sand: compacted granular patch --------------------------------- #
def sand_tile(u, v, x, y):
    rim = all_edge_rim(u, v, 0.20)
    mound = 0.38 * math.sin(math.pi * u) * math.sin(math.pi * v)
    grain = 0.55 * fbm(x, y, 0.75, 91, octaves=4)
    return (0.62 + mound + grain) * rim


# --- Soap: worn bar, smooth and heavily rounded ----------------------------- #
def soap_tile(u, v, x, y):
    # Generous roll on every edge. A used bar of soap has no sharp edge left
    # anywhere, and that rounding is most of what identifies it.
    rim = all_edge_rim(u, v, 0.42)
    dome = 0.46 * math.sin(math.pi * u) * math.sin(math.pi * v)
    return 0.72 * rim + dome * rim


# --- Butter-wax: hard shell, shallow angular planes ------------------------- #
def wax_tile(u, v, x, y):
    # Tight roll so the silhouette stays crisp: this is the one material here
    # that should read as rigid rather than yielding.
    rim = all_edge_rim(u, v, 0.09)
    planes = 0.62 * fbm(x, y, 0.55, 404, octaves=2)
    crystal = 0.09 * fbm(x, y, 2.6, 77, octaves=2)
    return (0.72 + planes + crystal) * rim


# --------------------------------------------------------------------------- #
# Edge-matched tiles
# --------------------------------------------------------------------------- #

SIDES = ("-y", "+x", "+y", "-x")  # ring order used by build(): t 0..0.25 is -y, etc.


def outward_distance(u, v, outer):
    """Normalised distance to the nearest OUTER side, 1.0 when there are none."""
    d = []
    if "-x" in outer:
        d.append(u)
    if "+x" in outer:
        d.append(1 - u)
    if "-y" in outer:
        d.append(v)
    if "+y" in outer:
        d.append(1 - v)
    return min(d) * 2.0 if d else 1.0


def make_continuous_height(outer, bead, ripple_amp, ripple_seed):
    """
    NOTE ON WHY THE BEAD IS NOT MASKED AT SHARED EDGES.

    It looks like it should need to be: the meniscus runs parallel to the outer
    edge, so it also crosses the two borders perpendicular to that edge, lifting
    them above EDGE_H. But every tile that can sit across one of those borders is
    another boundary tile (Edge or Corner) whose bead is driven by distance to the
    SAME outer direction, so the two profiles agree exactly and meet flush. The
    only tile that meets a non-bead border is an Interior one, and that border is
    the far side, where the Gaussian has already decayed to nothing.

    Masking it at shared edges (tried, reverted) forces the bead to zero wherever
    two boundary tiles meet, which punches a visible notch into the rim at every
    junction along the platform edge. The ridges that motivated the mask turned out
    to be a rotation error in the placement table, not a mesh problem.
    """
    def fn(u, v, x, y):
        d = outward_distance(u, v, outer)
        if outer:
            rim = smoothstep(0.0, 0.16, d)
            meniscus = bead * math.exp(-(((d - 0.24) / 0.15) ** 2))
        else:
            rim, meniscus = 1.0, 0.0

        # Periodic and zero-valued on every border, so neighbouring tiles stay
        # flush. sin(2*pi*u) gives four alternating lobes instead of one dome per
        # tile; a single dome per tile is what produces a quilted surface.
        wave = ripple_amp * math.sin(2 * math.pi * u) * math.sin(2 * math.pi * v)
        wave += ripple_amp * 0.45 * fbm(x, y, 0.9, ripple_seed, octaves=2) * \
            math.sin(math.pi * u) * math.sin(math.pi * v)

        return (EDGE_H + wave) * rim + meniscus * rim

    return fn


HONEY_DRIPS = ((0.18, 1.6), (0.46, 0.95), (0.74, 1.35))
SLIME_DRIPS = ((0.30, 1.1), (0.62, 1.5))
DRIP_W = 0.055


def make_drip_base(outer, drips):
    """
    Drips only along the OUTER sides. Each side owns a quarter of the ring in
    build()'s ordering, so a side's drips are placed inside its own quarter.
    """
    lobes = []
    for side in outer:
        quarter = SIDES.index(side) * 0.25
        for position, depth in drips:
            lobes.append((quarter + position * 0.25, depth))

    def fn(t):
        z = 0.0
        for position, depth in lobes:
            d = abs(t - position)
            d = min(d, 1.0 - d)
            z -= depth * math.exp(-((d / DRIP_W) ** 2))
        return z

    return fn


# --------------------------------------------------------------------------- #
# Export
# --------------------------------------------------------------------------- #

def export(obj, filename):
    os.makedirs(OUT_DIR, exist_ok=True)
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


def clear():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def build_all():
    """Returns [(obj, filename)] without exporting, so previews can reuse it."""
    out = []

    out.append((build("BubbleWrap_Tile", TILE, TILE, 0.11, bubble_tile), "BubbleWrap_Tile.obj"))
    out.append((build("KineticSand_Tile", TILE, TILE, 0.13, sand_tile), "KineticSand_Tile.obj"))
    out.append((build("Soap_Tile", TILE, TILE, 0.15, soap_tile), "Soap_Tile.obj"))
    out.append((build("ButterWax_Tile", TILE, TILE, 0.14, wax_tile), "ButterWax_Tile.obj"))

    for label, bead, amp, seed, drips in (
        ("Honey", 0.55, 0.12, 311, HONEY_DRIPS),
        ("Slime", 0.65, 0.20, 512, SLIME_DRIPS),
    ):
        for variant, outer in (
            ("Interior", ()),
            ("Edge", ("-y",)),
            ("Corner", ("-y", "-x")),
        ):
            name = f"{label}_Tile_{variant}"
            height = make_continuous_height(outer, bead, amp, seed)
            base = make_drip_base(outer, drips) if (outer and drips) else None
            out.append((build(name, TILE, TILE, 0.15, height, base), f"{name}.obj"))

    return out


def main():
    clear()
    print("Building tile meshes...")
    for obj, filename in build_all():
        export(obj, filename)
    print(f"Done. Wrote to {OUT_DIR}")


if __name__ == "__main__":
    main()
