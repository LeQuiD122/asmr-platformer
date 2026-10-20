"""The Sunken City's whirlpool, as meshes: a smooth funnel rather than rings of flat boards.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_whirlpool.py
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_whirlpool.py -- render

Writes thirteen meshes to meshes/ and blender/whirlpool_extents.json:

    Whirl_Band1 .. Whirl_Band6   the funnel's water, in six rings from the rim to the hole. Each is a
                                 smooth surface of revolution, so turning it is invisible except for
                                 what is on it: spiral ripples, laid along the way the water winds in,
                                 fading to nothing at both edges of the ring so the rings always meet
                                 without a step however far apart they have turned.
    Whirl_Foam1 .. Whirl_Foam6   the foam on each ring: tapered streaks along the ripples' crests and
                                 flecks between them, lying just over the water. A ring's foam turns
                                 with its water (SunkenCityService puts the two in one model).
    Whirl_Lip                    the crest of foam round the rim, lumpy, over the edge of the hole the
                                 harbour's glass has cut for the whirlpool.

Import all thirteen into ReplicatedStorage/Assets/TileMeshes. SunkenCityService colours them (a
MeshPart has one colour: the water darkening ring by ring toward the hole, the foam pale) and the
client turns each ring's model at its own speed, faster further in. Without them the whirlpool is
built of parts as before, so nothing waits on the import.

=== The contract with the server ===

    CENTRE   Every mesh's bounding box is centred on the whirlpool's middle at the water's level (the
             origin), so in Roblox each one is placed at CFrame.new(vortex) with no offset.
    PROFILE  The water is SINK + DEPTH * ((R - r) / (R - HOLE)) ^ 1.6 under the surface at radius r,
             the same funnel the parts were and the one the drain's ride goes down (SunkenPath): flat
             at the rim, steepest at the hole, DEPTH + SINK down where the throat starts.
    TURN     The client turns a ring by CFrame.Angles(0, -spin * t, 0): clockwise from above. The
             ripples and foam wind in the other way (anticlockwise going in), so as they turn, every
             crest is carried INWARD along itself: the water reads as pouring in, not spreading out.
    SIZES    Each mesh's Roblox size goes to whirlpool_extents.json; SunkenCityService keeps the same
             numbers in WHIRL_SIZE and refuses an import that does not match, and check_sunkencity.py
             holds the two together.
"""

import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sealife as G  # noqa: E402  -- clear_scene, anchor, export

R = 22.0          # VORTEX_R: where the funnel starts, at the rim
DEPTH = 16.0      # FUNNEL_DEPTH: rim to hole
HOLE = 1.5        # where the funnel meets the throat
SINK = 0.25       # the water sits this far under the harbour's glass, which is at the water's level
THROAT = 2.5      # the throat goes on down this far below the hole, curling to straight down
LIP_IN, LIP_OUT = R - 1.4, R + 3.4  # over the band (R - 1 to R + 3) where the glass's cut is stepped
# The rings, rim to hole, and how fast each turns (radians a second; the client's Spin).
EDGES = (R + 1.5, 17.0, 12.5, 8.6, 5.6, 3.3, HOLE)
SPINS = (0.3, 0.42, 0.6, 0.85, 1.2, 1.7)
SEGMENTS = 160    # round the funnel: smooth at any distance the pier gives
BAND_SEGMENTS = (160, 160, 160, 160, 144, 120)  # fewer on the small inner rings, under 10000 triangles both sides
# The ripples' spirals: how many, and how far round per unit of ln(r). Wound TIGHT, as a whirlpool's water
# is: it goes round many times for every stud it comes in, so a crest is nearly a circle (a pitch of about
# sixteen degrees), not a spoke.
ARMS, WIND = 6, 3.4
ARMS2, WIND2 = 10, 2.9    # a second, finer set, out of step with the first, so no two crests match
THREADS = (16, 14, 12, 10, 8, 6)  # foam threads on each ring
SEED = 3874
# What SunkenCityService colours the rings (WHIRL_WATER), here only for the renders: the harbour's water
# at the rim, darkening a little ring by ring toward the hole. Small steps: the shading does the rest.
WATER = ((58, 116, 116), (52, 106, 108), (45, 94, 98), (38, 82, 88), (31, 68, 76), (22, 50, 58))


def depth(r):
    """How far under the water's level the funnel is at radius r (positive is down)."""
    if r >= R:
        return SINK
    if r >= HOLE:
        return SINK + DEPTH * ((R - r) / (R - HOLE)) ** 1.6
    # The throat: on past the hole, curling over to straight down.
    s = (HOLE - r) / (HOLE - 1.0)
    return SINK + DEPTH + THROAT * s ** 0.7


def envelope(r, outer, inner):
    """The ripples on a ring: nothing at either edge (and flat there, sin squared), most in the middle."""
    x = (outer - r) / (outer - inner)
    return math.sin(math.pi * min(1.0, max(0.0, x))) ** 2


def ripple(r, phi, band):
    """Height of the ripples at (r, phi) on ring `band`: two spirals winding in anticlockwise."""
    outer, inner = EDGES[band], EDGES[band + 1]
    if r >= R - 0.5 or r <= HOLE:
        return 0.0
    # Never steeper than the ripple is long: near the hole the crests crowd together, and a ripple as tall
    # as it is wide is a spike, not water.
    amp = (0.1 + 0.22 * (1 - r / R)) * envelope(r, outer, inner) * min(1.0, wavelength(r) / 2.2)
    lr = math.log(max(r, 0.5))
    return amp * (0.7 * math.sin(ARMS * (phi + WIND * lr)) + 0.3 * math.sin(ARMS2 * (phi + WIND2 * lr) + 1.7))


def wavelength(r):
    """How far apart the main ripple's crests are, going in, at radius r."""
    return 2 * math.pi * max(r, 0.5) / (ARMS * WIND)


def surface(r, phi, band):
    return -depth(r) + ripple(r, phi, band)


def radii(outer, inner, rows):
    """`rows` + 1 radii from outer to inner, closer together where the funnel is steep."""
    out = []
    for k in range(rows + 1):
        t = k / rows
        out.append(outer + (inner - outer) * t)
    return out


def band_bm(band):
    outer, inner = EDGES[band], EDGES[band + 1]
    # Five rows to a ripple at the ring's inner edge, where they are closest: under the 10000 triangles.
    rows = min(15, max(10, math.ceil((outer - inner) / (wavelength(max(inner, 2.0)) / 5))))
    rs = radii(outer, inner, rows)
    if band == len(EDGES) - 2:
        # The innermost ring goes on down the throat.
        rs += [HOLE - (HOLE - 1.0) * k / 4 for k in range(1, 5)]
    n = BAND_SEGMENTS[band]
    bm = bmesh.new()
    # Twice: the water's top, seen from the pier and the ride, and its UNDERSIDE, seen from the shaft as
    # the camera falls with the rider looking back up (a mesh's face is seen from one side only).
    for under in (False, True):
        grid = []
        for r in rs:
            row = []
            for j in range(n):
                phi = 2 * math.pi * j / n
                row.append(bm.verts.new((r * math.cos(phi), r * math.sin(phi), surface(r, phi, band))))
            grid.append(row)
        for k in range(len(rs) - 1):
            for j in range(n):
                a, b = grid[k][j], grid[k][(j + 1) % n]
                c, d = grid[k + 1][(j + 1) % n], grid[k + 1][j]
                # Wound so the top looks up (outer row anticlockwise, then in) and the underside down.
                bm.faces.new((d, c, b, a) if under else (a, b, c, d))
    return bm


def along(r):
    """Which way the water goes at radius r, as (out, round) per stud: along the spiral, nearly round."""
    n = math.sqrt(1 + WIND * WIND)
    return 1 / n, -WIND / n


def foam_bm(band, rng):
    outer, inner = EDGES[band], EDGES[band + 1]
    bm = bmesh.new()
    width_most = 0.16 + 0.035 * (outer - inner)
    # THREADS of foam along the ripples' crests, the way foam is drawn out into lines on turning water:
    # long, thin, uneven, broken here and there.
    for thread in range(THREADS[band]):
        k = rng.randrange(ARMS)
        crest = (math.pi / 2 + 2 * math.pi * k) / ARMS + rng.uniform(-0.06, 0.06)
        a = rng.uniform(0.0, 0.3)
        b = rng.uniform(0.7, 1.0)
        steps = 44
        left, right = [], []
        for i in range(steps + 1):
            s = a + (b - a) * i / steps
            r = outer + (inner - outer) * s
            phi = crest - WIND * math.log(r)
            lace = noise.noise(Vector((thread * 2.3 + band * 17.0, s * 9.0, 0.5)))
            taper = max(0.0, math.sin(math.pi * i / steps)) ** 0.6
            w = max(0.0, width_most * taper * (0.75 + 0.6 * lace))
            for side, sink in ((-1, left), (1, right)):
                rr = r + side * w * 0.5
                pp = phi + side * w * 0.5 * 0.25 / max(r, 1.0)
                sink.append(bm.verts.new((rr * math.cos(pp), rr * math.sin(pp), surface(rr, pp, band) + 0.08)))
        for i in range(steps):
            # Broken where the lace is thinnest: a thread of foam is never one unbroken line.
            if (left[i].co - right[i].co).length < 0.035 and (left[i + 1].co - right[i + 1].co).length < 0.035:
                continue
            bm.faces.new((left[i], right[i], right[i + 1], left[i + 1]))
    # FLECKS between them, drawn out along the way the water goes.
    out_, round_ = along(1.0)
    for _ in range(int(10 + 4 * (outer - inner))):
        r = rng.uniform(inner + 0.25, outer - 0.25)
        phi = rng.uniform(0, 2 * math.pi)
        long_ = rng.uniform(0.35, 1.1) * (0.5 + 0.5 * r / R)
        wide = long_ * rng.uniform(0.18, 0.32)
        ring = []
        for m in range(8):
            t = 2 * math.pi * m / 8
            u, v = math.cos(t) * long_ * rng.uniform(0.85, 1.1), math.sin(t) * wide * rng.uniform(0.8, 1.15)
            # u along the flow, v across it: (out, round) = u * along + v * (round, -out).
            dr = u * out_ + v * (-round_)
            dround = u * round_ + v * out_
            rr = r + dr
            pp = phi + dround / max(r, 1.0)
            ring.append(bm.verts.new((rr * math.cos(pp), rr * math.sin(pp), surface(rr, pp, band) + 0.08)))
        bm.faces.new(ring)
    return bm


def lip_bm():
    """The crest of churned foam round the rim: lumpy along it, and ragged on its inner edge, where it
    breaks up as the water takes it in. The edge wanders in and out smoothly (a curve, never steps)."""
    bm = bmesh.new()
    rows = 12
    grid = []
    for k in range(rows + 1):
        t = k / rows
        row = []
        for j in range(SEGMENTS):
            phi = 2 * math.pi * j / SEGMENTS
            ragged = 0.5 + 0.5 * noise.noise(Vector((math.cos(phi) * 4.5, math.sin(phi) * 4.5, 0.3)))
            inner = LIP_IN + 1.1 * max(0.0, min(1.0, ragged))
            r = LIP_OUT + (inner - LIP_OUT) * t
            crest = math.exp(-((r - (R + 0.9)) / 1.3) ** 2)
            lumps = noise.noise(Vector((math.cos(phi) * 9, math.sin(phi) * 9, r * 0.7)))
            z = -0.15 + crest * (0.42 + 0.28 * lumps) + 0.05 * noise.noise(Vector((phi * 13, r * 1.5, 2.0)))
            row.append(bm.verts.new((r * math.cos(phi), r * math.sin(phi), max(z, -depth(r) + 0.12))))
        grid.append(row)
    for k in range(rows):
        for j in range(SEGMENTS):
            a, b = grid[k][j], grid[k][(j + 1) % SEGMENTS]
            c, d = grid[k + 1][(j + 1) % SEGMENTS], grid[k + 1][j]
            bm.faces.new((a, b, c, d))
    return bm


def finish(name, bm, smooth=True):
    """Box centred on the whirlpool's middle at the water's level (the origin)."""
    lo = [min(v.co[i] for v in bm.verts) for i in range(3)]
    hi = [max(v.co[i] for v in bm.verts) for i in range(3)]
    half = [max(abs(lo[i]), abs(hi[i])) + 0.5 for i in range(3)]
    G.anchor(bm, (-half[0], -half[1], -half[2]), (half[0], half[1], half[2]))
    bmesh.ops.triangulate(bm, faces=bm.faces[:], ngon_method="EAR_CLIP")
    # A fleck laid over a steep, rippled bit of the funnel can come out wound the wrong way: turned over.
    bm.normal_update()
    backwards = [f for f in bm.faces if f.normal.z < -0.05 and f.calc_area() > 0.001]
    if backwards and not name.startswith("Whirl_Band"):
        bmesh.ops.reverse_faces(bm, faces=backwards)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    # Facing up, every face: it is seen from above, and a single-sided face seen from behind is not seen.
    down = sum(1 for p in mesh.polygons if p.normal.z < -0.05 and p.area > 0.001)
    if down and not name.startswith("Whirl_Band"):
        print("!! %s: %d faces look down, and will not be seen from above" % (name, down))
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    # Roblox axes: Blender (x, y, z) arrives as (x, z, -y).
    return obj, [round(2 * half[0], 2), round(2 * half[2], 2), round(2 * half[1], 2)]


def render(objects, path, eye, target, lens):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    scene.display.shading.show_specular_highlight = True
    scene.render.resolution_x, scene.render.resolution_y = 1000, 700
    # SunkenCityService's WHIRL_WATER, as 0-1.
    water = [(c[0] / 255, c[1] / 255, c[2] / 255) for c in WATER]
    for obj in objects:
        if obj.name.startswith("Whirl_Band"):
            obj.color = water[int(obj.name[-1]) - 1] + (1,)
        else:
            obj.color = (0.84, 0.91, 0.89, 1)
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = eye
    cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
    cam_data.lens = lens
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    rng = random.Random(SEED)
    G.clear_scene()
    extents = {}
    objects = []
    pieces = []
    for band in range(len(EDGES) - 1):
        pieces.append(("Whirl_Band%d" % (band + 1), band_bm(band)))
        pieces.append(("Whirl_Foam%d" % (band + 1), foam_bm(band, rng)))
    pieces.append(("Whirl_Lip", lip_bm()))
    for name, bm in pieces:
        obj, size = finish(name, bm)
        extents[name] = {"size": size, "tris": len(obj.data.polygons)}
        objects.append(obj)
    if "render" in sys.argv:
        render(objects, os.path.join(HERE, "whirlpool_pier.png"), (0, -40, 13), (0, 2, -6), 26)
        render(objects, os.path.join(HERE, "whirlpool_top.png"), (0.01, 0, 58), (0, 0, 0), 30)
        render(objects, os.path.join(HERE, "whirlpool_inside.png"), (9, -9, -4), (-3, 3, -12), 22)
    for obj in objects:
        G.export([obj], obj.name)
    with open(os.path.join(HERE, "whirlpool_extents.json"), "w") as handle:
        json.dump(extents, handle, indent=1, sort_keys=True)
    print("whirlpool: %s" % ", ".join("%s %s (%d tris)" % (n, e["size"], e["tris"]) for n, e in sorted(extents.items())))


main()
