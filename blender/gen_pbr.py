"""
PBR surface maps for the platform materials.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_pbr.py

Every surface in this game is a flat colour on a built-in Roblox material, and that is the
ceiling on how it can look. What separates a good-looking Roblox game from a default one is
that essentially every surface carries a ColorMap, a NormalMap and a RoughnessMap.

Roughness is the one that matters most here and it is the least obvious. A wet surface is
not defined by being shiny -- it is defined by being shiny UNEVENLY. Uniform gloss reads as
plastic no matter how high you set it. Honey looks wet because the roughness varies across
it: mirror-flat where it has pooled, slightly hazier over a bubble.

=== Everything here tiles ===

The UVs repeat every 9 studs (honey) or 7 (slime), so a seam in the texture is a seam
repeated across the whole platform. Two mechanisms guarantee tiling:

  * the base undulation is a sum of sines with INTEGER frequencies over the tile, which is
    periodic by construction -- the same trick the sea mesh uses;
  * bubbles are placed on a TORUS: distance wraps at the edges, so a bubble near the right
    edge is also near the left one and its dome continues across the seam.

Neither needs blending or mirroring, both of which leave their own visible artefacts.

=== Non-Color, deliberately ===

All three maps are written with the image colorspace set to Non-Color so the float values
land in the PNG bytes unchanged. Normal and roughness maps are DATA, not pictures -- letting
Blender apply a display transform to them corrupts the values silently. The colour map is
authored directly in sRGB for the same reason: what is computed here is what Roblox reads.
"""

import bpy
import math
import numpy as np
import os
import sys

# This directory, so build_keyboard can import gen_keyboard for the shared ATLAS size.
# Blender puts the CWD on sys.path for a --python script, not the script's own folder.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

OUT_DIR = r"C:\Users\Arsenii\Downloads\asmr-platformer-implementation_1\RobloxProject\textures"

RES = 512

# Integer frequencies over the tile, so the field is seamless by construction.
BASE_WAVES = (
    (1, 2, 1.00, 0.00),
    (3, 1, 0.62, 1.10),
    (2, 4, 0.44, 2.30),
    (5, 3, 0.28, 0.60),
    (4, 7, 0.18, 3.00),
    (8, 5, 0.11, 1.80),
    (11, 9, 0.07, 2.60),
)


def base_field(rng, roughness_detail):
    """A smooth periodic height field in roughly [-1, 1]."""
    axis = np.arange(RES, dtype=np.float64) / RES
    u, v = np.meshgrid(axis, axis, indexing="ij")
    field = np.zeros((RES, RES), dtype=np.float64)
    for nx, ny, amplitude, phase in BASE_WAVES[:roughness_detail]:
        field += amplitude * np.sin(math.tau * (nx * u + ny * v) + phase)
    return field / np.abs(field).max()


def bubbles(rng, count, radius_lo, radius_hi, rim):
    """Domed bubbles placed on a TORUS, so every one continues across the tile edge.

    `rim` raises a lip around each dome. Honey wants none of it -- a bubble in honey is a
    trapped sphere pressing up under a smooth surface. Slime wants a lot, because its
    bubbles have burst and left a crater edge behind.
    """
    axis = np.arange(RES, dtype=np.float64) / RES
    u, v = np.meshgrid(axis, axis, indexing="ij")
    field = np.zeros((RES, RES), dtype=np.float64)

    for _ in range(count):
        cx, cy = rng.random(), rng.random()
        radius = rng.uniform(radius_lo, radius_hi)
        # Wrapped distance: the shorter way round the tile in each axis.
        dx = np.abs(u - cx)
        dx = np.minimum(dx, 1.0 - dx)
        dy = np.abs(v - cy)
        dy = np.minimum(dy, 1.0 - dy)
        d = np.sqrt(dx * dx + dy * dy) / radius

        inside = d < 1.0
        dome = np.zeros_like(field)
        # A spherical cap, so the bubble meets the surface tangentially instead of at a
        # crease. A cone or a gaussian both read as a dent rather than as a bubble.
        dome[inside] = np.sqrt(np.clip(1.0 - d[inside] ** 2, 0.0, 1.0))
        if rim > 0.0:
            lip = np.zeros_like(field)
            edge = (d > 0.72) & (d < 1.0)
            lip[edge] = np.sin((d[edge] - 0.72) / 0.28 * math.pi)
            dome += lip * rim
        field += dome * rng.uniform(0.6, 1.0)

    peak = np.abs(field).max()
    return field / peak if peak > 0 else field


def periodic_noise(rng, cells_u, cells_v, octaves=4):
    """Fractal value noise that tiles, and can be stretched along one axis.

    The sine sum above tops out around eleven harmonics before it costs more than it buys,
    which is fine for a viscous fluid and useless for sand: grain is high-frequency by
    definition. This lays random values on a lattice and interpolates, which gives detail at
    any scale for the same work.

    It TILES because the lattice wraps -- index (cells, k) is index (0, k) -- and every
    octave uses its own wrapping lattice, so the sum wraps too.

    `cells_u` and `cells_v` are separate on purpose. Equal counts give isotropic grain;
    4 against 40 gives streaks, which is what a knife through butter leaves behind.
    """
    axis = np.arange(RES, dtype=np.float64) / RES
    u, v = np.meshgrid(axis, axis, indexing="ij")
    total = np.zeros((RES, RES), dtype=np.float64)
    amplitude, weight = 1.0, 0.0

    for octave in range(octaves):
        nu = max(2, int(cells_u * 2 ** octave))
        nv = max(2, int(cells_v * 2 ** octave))
        lattice = rng.random((nu, nv))

        su, sv = u * nu, v * nv
        iu, iv = np.floor(su).astype(int), np.floor(sv).astype(int)
        fu, fv = su - iu, sv - iv
        # Smoothstep, so the lattice does not show up as a diamond grid.
        fu = fu * fu * (3.0 - 2.0 * fu)
        fv = fv * fv * (3.0 - 2.0 * fv)

        i0, i1 = iu % nu, (iu + 1) % nu
        j0, j1 = iv % nv, (iv + 1) % nv
        a = lattice[i0, j0] * (1 - fu) + lattice[i1, j0] * fu
        b = lattice[i0, j1] * (1 - fu) + lattice[i1, j1] * fu
        total += (a * (1 - fv) + b * fv) * amplitude

        weight += amplitude
        amplitude *= 0.5

    total /= weight
    return total * 2.0 - 1.0


def periodic_voronoi(rng, count):
    """Distance between the nearest and second-nearest scattered point, on a torus.

    Near zero exactly on the boundary between two cells and rising away from it, so it is a
    CRACK NETWORK rather than a set of blobs -- which is what wax crazing looks like and
    what a plain noise field cannot produce at any frequency.

    Running minima rather than one array per point: forty 512x512 float arrays is 84MB held
    for no reason.
    """
    axis = np.arange(RES, dtype=np.float64) / RES
    u, v = np.meshgrid(axis, axis, indexing="ij")
    nearest = np.full((RES, RES), 10.0)
    second = np.full((RES, RES), 10.0)

    for _ in range(count):
        cx, cy = rng.random(), rng.random()
        dx = np.abs(u - cx)
        dx = np.minimum(dx, 1.0 - dx)
        dy = np.abs(v - cy)
        dy = np.minimum(dy, 1.0 - dy)
        d = np.sqrt(dx * dx + dy * dy)
        closer = d < nearest
        second = np.where(closer, nearest, np.minimum(second, d))
        nearest = np.where(closer, d, nearest)

    edge = second - nearest
    return edge / edge.max()


def normal_map(height, strength):
    """Tangent-space normal map from a height field, wrapping at the edges.

    np.gradient does not wrap, so the seam rows would get a one-sided difference and show
    as a visible line on every tile boundary. np.roll gives a true central difference
    across the wrap.
    """
    dx = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    dy = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5

    nx = -dx * strength * RES / 64.0
    ny = -dy * strength * RES / 64.0
    nz = np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)

    out = np.empty((RES, RES, 4), dtype=np.float64)
    out[..., 0] = nx / length * 0.5 + 0.5
    # GREEN IS +Y (the OpenGL convention). If bumps read as dents in game, this channel is
    # the one to invert -- it is the only difference between the two conventions and the
    # only thing that can be wrong here without anything else looking off.
    out[..., 1] = ny / length * 0.5 + 0.5
    out[..., 2] = nz / length * 0.5 + 0.5
    out[..., 3] = 1.0
    return out


def grey_map(values):
    out = np.empty((RES, RES, 4), dtype=np.float64)
    for channel in range(3):
        out[..., channel] = values
    out[..., 3] = 1.0
    return out


def colour_map(tint_lo, tint_hi, mix, alpha):
    """RGBA for AlphaMode = Overlay.

    Alpha is what makes this reusable: at 0 the part's own Color shows through untouched, at
    1 the texture wins. Kept low, so the palette in MaterialAppearance still drives the hue
    and this only adds variation on top. Baking the colour in would mean a new upload every
    time a colour is tweaked.
    """
    out = np.empty((RES, RES, 4), dtype=np.float64)
    for channel in range(3):
        out[..., channel] = tint_lo[channel] + (tint_hi[channel] - tint_lo[channel]) * mix
    out[..., 3] = alpha
    return out


def save(pixels, name):
    """Write one map, and PROVE it was written.

    The first version of this set the image colorspace AFTER filling the pixel buffer, and
    changing colorspace on a generated image RESETS that buffer. Every one of the six PNGs
    came out solid black -- and nothing complained: the files existed, were the right size,
    opened fine, and were entirely zero. A texture pipeline that silently produces black is
    worse than one that crashes, so the read-back at the bottom is not optional.
    """
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".png")

    image = bpy.data.images.new(name, RES, RES, alpha=True, float_buffer=False)
    # BEFORE the pixels, for the reason above.
    image.colorspace_settings.name = "Non-Color"
    image.alpha_mode = "STRAIGHT"

    # Blender's pixel buffer is bottom-up; flipping here keeps the maps the same way up as
    # the height field they were derived from, which matters for the normal map's green.
    flat = np.flip(np.transpose(pixels, (1, 0, 2)), axis=0).astype(np.float32).ravel()
    image.pixels.foreach_set(flat)
    image.update()

    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()

    # Read the file back off disk rather than trusting the in-memory image.
    check = bpy.data.images.load(path)
    check.colorspace_settings.name = "Non-Color"
    buf = np.empty(len(check.pixels), dtype=np.float32)
    check.pixels.foreach_get(buf)
    rgb = buf.reshape(-1, 4)[:, :3]
    if rgb.max() <= 0.0:
        raise RuntimeError(f"{name}.png wrote as solid black")
    return path, rgb.mean()


def build_honey():
    rng = np.random.default_rng(20260814)
    # Honey is VISCOUS: broad slow undulation, very little fine detail. Adding high
    # frequencies here is what makes a fluid read as a rough solid.
    surface = base_field(rng, 4) * 0.75
    trapped = bubbles(rng, 26, 0.020, 0.055, rim=0.0) * 0.55
    height = surface + trapped

    # Roughness 0.03 to 0.13 -- glass, essentially, but NOT uniform glass. The variation is
    # the whole point: a constant value at any level reads as plastic.
    rough = 0.03 + 0.10 * (0.5 + 0.5 * base_field(rng, 7))
    rough += 0.05 * np.clip(trapped, 0, None)

    mix = 0.5 + 0.5 * surface
    return {
        "Honey_Color": colour_map((0.62, 0.30, 0.05), (1.0, 0.72, 0.26), mix, 0.30),
        "Honey_Normal": normal_map(height, 0.9),
        "Honey_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_slime():
    rng = np.random.default_rng(20260815)
    # Slime is LUMPIER and full of burst bubbles, so: more frequencies, more craters, and a
    # pronounced rim on each one.
    surface = base_field(rng, 6) * 0.6
    pockets = bubbles(rng, 54, 0.016, 0.048, rim=0.45) * 0.8
    height = surface + pockets

    # Wetter than plastic, drier than honey, and roughest exactly on the bubble rims where
    # the film has stretched thin.
    rough = 0.14 + 0.16 * (0.5 + 0.5 * base_field(rng, 7))
    rough += 0.14 * np.clip(pockets, 0, None)

    mix = 0.5 + 0.5 * surface
    return {
        "Slime_Color": colour_map((0.30, 0.55, 0.22), (0.72, 0.94, 0.55), mix, 0.34),
        "Slime_Normal": normal_map(height, 1.5),
        "Slime_Roughness": grey_map(np.clip(rough, 0, 1)),
    }



def build_butter():
    rng = np.random.default_rng(20260816)
    # Knife smears: noise stretched hard along one axis. Butter's whole surface identity is
    # that it was SPREAD -- directionless bumpiness reads as clay.
    smear = periodic_noise(rng, 3, 34, octaves=4)
    grain = periodic_noise(rng, 24, 24, octaves=3) * 0.22
    height = smear * 0.8 + grain

    # Matte, and nowhere near honey. Butter is soft-scattering, not wet -- but the smear
    # ridges catch a little more light than the troughs, which is the only gloss it has.
    rough = 0.52 - 0.14 * smear + 0.06 * grain
    mix = 0.5 + 0.5 * smear
    return {
        "Butter_Color": colour_map((0.82, 0.68, 0.32), (1.0, 0.94, 0.68), mix, 0.28),
        "Butter_Normal": normal_map(height, 1.1),
        "Butter_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_wax():
    rng = np.random.default_rng(20260817)
    # Crazing, from a Voronoi edge field. The shell is already fractured into shards by the
    # geometry; this is the finer craquelure within each one.
    cracks = periodic_voronoi(rng, 40)
    # Inverted and sharpened: 1 at a cell boundary, falling away fast.
    crack_line = np.clip(1.0 - cracks * 5.0, 0.0, 1.0)
    peel = periodic_noise(rng, 12, 12, octaves=4) * 0.30
    height = peel - crack_line * 0.85

    # Semi-matte with the cracks reading DULLER, because a broken edge scatters. Making
    # cracks shinier is the usual mistake and it turns wax into cracked glass.
    rough = 0.34 + 0.10 * peel + 0.30 * crack_line
    mix = 0.5 + 0.5 * peel
    return {
        "Wax_Color": colour_map((0.74, 0.71, 0.64), (1.0, 0.98, 0.94), mix, 0.26),
        "Wax_Normal": normal_map(height, 1.3),
        "Wax_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_sand():
    rng = np.random.default_rng(20260818)
    # SIX octaves starting fine. Kinetic sand is nothing but grain, and grain is the one
    # thing the sine field genuinely cannot do -- this is why periodic_noise exists.
    grain = periodic_noise(rng, 40, 40, octaves=6)
    clump = periodic_noise(rng, 6, 6, octaves=3) * 0.45
    height = grain * 0.75 + clump

    # Rough almost everywhere, which is what sand IS. The variation is small on purpose:
    # a wide roughness range would read as patches of wet sand.
    rough = 0.82 + 0.10 * grain
    mix = 0.5 + 0.5 * clump
    return {
        "Sand_Color": colour_map((0.66, 0.58, 0.42), (0.94, 0.88, 0.74), mix, 0.42),
        "Sand_Normal": normal_map(height, 1.7),
        "Sand_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_bubblewrap():
    rng = np.random.default_rng(20260819)
    # The POCKETS ARE GEOMETRY, already modelled and rigged. Putting them in the normal map
    # too would double them up -- a painted bubble beside a real one is worse than either.
    # This is only the film between them: slack, creased, and slightly directional.
    creases = periodic_noise(rng, 5, 22, octaves=5)
    slack = periodic_noise(rng, 14, 14, octaves=3) * 0.30
    height = creases * 0.55 + slack

    # Thin plastic: fairly glossy, and glossiest where it is stretched flat over a pocket.
    rough = 0.26 + 0.14 * np.abs(creases)
    mix = 0.5 + 0.5 * slack
    return {
        "BubbleWrap_Color": colour_map((0.72, 0.80, 0.86), (0.96, 1.0, 1.0), mix, 0.22),
        "BubbleWrap_Normal": normal_map(height, 0.7),
        "BubbleWrap_Roughness": grey_map(np.clip(rough, 0, 1)),
    }



def build_bubblewrap_giant():
    """The giant sheet's film. Its own maps, not the standard sheet's, and the difference
    is not decoration.

    A SurfaceAppearance is applied per MESH, and the giant sheet's pockets are twice the
    width at twice the pitch -- so the bare film between seals spans four times the area.
    Reusing the standard maps would print the same crease every 2 studs across a sheet
    whose real features are 4 apart: the painted detail would visibly disagree with the
    geometry it is sitting on, at exactly the scale the eye is using to judge how big the
    bubbles are. This is the general rule for any variant that changes feature size, and
    it is why a variant is not finished when its mesh exports.

    Physically it is the same plastic under less support. A film sealed every 4 studs
    instead of every 2 sags further between seals and creases at a longer wavelength, so
    every frequency here is halved and the relief is deepened to match.
    """
    rng = np.random.default_rng(20260820)
    # Half the frequency of the standard sheet's 5 x 22 / 14 x 14, for double the span.
    creases = periodic_noise(rng, 3, 11, octaves=5)
    slack = periodic_noise(rng, 7, 7, octaves=3) * 0.30
    height = creases * 0.62 + slack

    # Marginally glossier: a bigger pocket stretches the film flatter over its dome, and
    # the standard sheet's roughness was tuned against a tighter, more crumpled surface.
    rough = 0.22 + 0.14 * np.abs(creases)
    mix = 0.5 + 0.5 * slack
    return {
        "BubbleWrapGiant_Color": colour_map((0.72, 0.80, 0.86), (0.96, 1.0, 1.0), mix, 0.22),
        # Stronger than 0.7: the features are twice as wide, and a normal map's apparent
        # depth is read against feature WIDTH, so the same strength on a wider crease
        # comes out looking flatter than the sheet it is meant to match.
        "BubbleWrapGiant_Normal": normal_map(height, 0.85),
        "BubbleWrapGiant_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


# A 5 x 7 BITMAP FONT, written out rather than rendered from a typeface.
#
# Blender can render text, but only by building a font object, a camera and a render pass
# per glyph -- minutes of work per run, and a dependency on whatever fonts the machine
# happens to have. Legends this size resolve to about thirty pixels on the finished cap,
# which is squarely bitmap-font territory: at that scale a hinted typeface and a hand
# bitmap are indistinguishable, and only one of them is reproducible on any machine.
GLYPHS = {
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
    "B": ("11110", "10001", "10001", "11110", "10001", "10001", "11110"),
    "C": ("01110", "10001", "10000", "10000", "10000", "10001", "01110"),
    "D": ("11110", "10001", "10001", "10001", "10001", "10001", "11110"),
    "E": ("11111", "10000", "10000", "11110", "10000", "10000", "11111"),
    "F": ("11111", "10000", "10000", "11110", "10000", "10000", "10000"),
    "G": ("01110", "10001", "10000", "10111", "10001", "10001", "01111"),
    "H": ("10001", "10001", "10001", "11111", "10001", "10001", "10001"),
    "I": ("11111", "00100", "00100", "00100", "00100", "00100", "11111"),
    "J": ("00111", "00010", "00010", "00010", "00010", "10010", "01100"),
    "K": ("10001", "10010", "10100", "11000", "10100", "10010", "10001"),
    "L": ("10000", "10000", "10000", "10000", "10000", "10000", "11111"),
    "M": ("10001", "11011", "10101", "10101", "10001", "10001", "10001"),
    "N": ("10001", "11001", "10101", "10011", "10001", "10001", "10001"),
    "O": ("01110", "10001", "10001", "10001", "10001", "10001", "01110"),
    "P": ("11110", "10001", "10001", "11110", "10000", "10000", "10000"),
    "Q": ("01110", "10001", "10001", "10001", "10101", "10010", "01101"),
    "R": ("11110", "10001", "10001", "11110", "10100", "10010", "10001"),
    "S": ("01111", "10000", "10000", "01110", "00001", "00001", "11110"),
    "T": ("11111", "00100", "00100", "00100", "00100", "00100", "00100"),
    "U": ("10001", "10001", "10001", "10001", "10001", "10001", "01110"),
    "V": ("10001", "10001", "10001", "10001", "10001", "01010", "00100"),
    "W": ("10001", "10001", "10001", "10101", "10101", "11011", "10001"),
    "X": ("10001", "10001", "01010", "00100", "01010", "10001", "10001"),
    "Y": ("10001", "10001", "01010", "00100", "00100", "00100", "00100"),
    "Z": ("11111", "00001", "00010", "00100", "01000", "10000", "11111"),
}

# THE PALETTE, AND WHY IT IS THREE TONES AND NOT ONE.
#
# Every reference board is at least two: a field of light caps, a set of accents, and
# legends that contrast with whichever cap they sit on. One flat colour across twenty-five
# identical caps is what made the first version read as a moulded tray rather than as a
# keyboard, and no amount of shading fixes that -- the variation is the signal.
#
# Cream dominates and rose punctuates, in roughly the proportion a real board uses for its
# modifiers. Blush sits between them so the accents do not read as two unrelated colours.
CAP_CREAM = (0.968, 0.949, 0.914)
CAP_BLUSH = (0.945, 0.702, 0.737)
CAP_ROSE = (0.855, 0.475, 0.553)
INK_DARK = (0.639, 0.318, 0.404)   # on cream
INK_LIGHT = (0.992, 0.973, 0.957)  # on blush and rose


def _glyph_mask(letter, cell_px):
    """A soft mask for one letter, in this file's [x, y] pixel order.

    THE AXIS ORDER IS THE TRAP HERE. `save` writes with
    np.flip(np.transpose(pixels, (1, 0, 2)), axis=0), so every array in this module is
    indexed [x, y] with y measured DOWNWARD from the top -- not [row, column]. Nothing had
    ever depended on that, because every other map is isotropic noise and a transposed
    field of noise is still a field of noise. A letter is the first thing in the project
    with an orientation, and the first version of this came out rotated ninety degrees for
    exactly that reason.

    Supersampled 3x and box-filtered down. A crisp bitmap scaled up gives stair-stepped
    strokes that read as a rendering fault at this size; the eye forgives a slightly soft
    legend and does not forgive a jagged one.
    """
    rows = GLYPHS[letter]
    scale = max(2, int(cell_px * 0.42 / 7.0))
    up = 3
    gw, gh = 5 * scale * up, 7 * scale * up
    fine = np.zeros((gw, gh), dtype=np.float64)
    for r, row in enumerate(rows):
        for c, on in enumerate(row):
            if on == "1":
                # r counts DOWN from the top of the glyph, and so does y. No flip.
                fine[
                    c * scale * up : (c + 1) * scale * up,
                    r * scale * up : (r + 1) * scale * up,
                ] = 1.0
    return fine.reshape(gw // up, up, gh // up, up).mean(axis=(1, 3))


def build_keyboard():
    """A UV ATLAS: one cell per keycap, each with its own colour and its own letter.

    This is the one map in the project that is not a tileable material sample, and it could
    not be. Every other surface here is the same everywhere, so a small tile repeated across
    it is exactly right. A keyboard is a grid of things that must DIFFER -- and since a
    MeshPart has one Color and one texture, the only place that difference can live is the
    texture, addressed by per-cap UVs. gen_keyboard.assign_uvs builds the other half of this
    arrangement; ATLAS is imported from there so the two cannot drift apart.

    Alpha is high, against the convention the other maps follow. They keep it low so
    MaterialAppearance still drives the hue and a colour tweak needs no re-upload -- but a
    per-key palette is precisely what a single part Color cannot express, so here the
    texture has to win.
    """
    import gen_keyboard

    atlas = gen_keyboard.ATLAS
    rng = np.random.default_rng(20260822)
    cell = RES / atlas

    out = np.zeros((RES, RES, 4), dtype=np.float64)
    out[..., 3] = 0.94

    # Fine plastic grain over the whole sheet, so the caps are not flat fields of colour.
    grain = periodic_noise(rng, 40, 40, octaves=2)

    # SHUFFLED, NOT SAMPLED. Drawing independently from 26 letters for 25 caps gives four
    # F's and no B by the birthday problem, which reads as a texture glitch rather than as
    # a keyboard. A shuffled deck spends each letter once and only repeats once the
    # alphabet runs out.
    letters = list(GLYPHS.keys())
    rng.shuffle(letters)
    for index in range(atlas * atlas):
        # `cell_origin` in gen_keyboard lays cells out in UV space, where v counts UP from
        # the bottom. This array's y counts DOWN from the top, so the row index has to be
        # mirrored -- get this wrong and every legend lands on the wrong key, which looks
        # exactly like a working atlas until you compare two of them.
        col, urow = index % atlas, index // atlas
        x0, x1 = int(col * cell), int((col + 1) * cell)
        y0, y1 = int((atlas - 1 - urow) * cell), int((atlas - urow) * cell)

        # The LAST cell is the case: plain rose, no legend. gen_keyboard maps the plate
        # there deliberately.
        if index == atlas * atlas - 1:
            base, ink, letter = CAP_ROSE, None, None
        else:
            roll = rng.random()
            if roll < 0.66:
                base, ink = CAP_CREAM, INK_DARK
            elif roll < 0.90:
                base, ink = CAP_BLUSH, INK_LIGHT
            else:
                base, ink = CAP_ROSE, INK_LIGHT
            letter = letters[index % len(letters)]

        patch = grain[x0:x1, y0:y1]
        for channel in range(3):
            # +/- 2% of grain. Any more and it stops being moulded plastic and starts
            # looking like the cap is dirty.
            out[x0:x1, y0:y1, channel] = base[channel] * (0.98 + 0.04 * patch)

        if letter is not None:
            mask = _glyph_mask(letter, cell)
            gw, gh = mask.shape
            ox = x0 + int((x1 - x0 - gw) / 2)
            oy = y0 + int((y1 - y0 - gh) / 2)
            if gh <= (y1 - y0) and gw <= (x1 - x0):
                region = out[ox : ox + gw, oy : oy + gh, :3]
                for channel in range(3):
                    region[..., channel] = region[..., channel] * (1.0 - mask) + ink[channel] * mask

    # Height and roughness stay whole-sheet fields rather than per-cell: the grain is the
    # same plastic on every cap, and letting cells differ here would put a visible seam
    # between neighbouring keys for no gain.
    height = grain * 0.30 + periodic_noise(rng, 3, 3, octaves=2) * 0.22
    rough = 0.66 - 0.06 * grain
    return {
        "Keyboard_Color": out,
        "Keyboard_Normal": normal_map(height, 0.45),
        "Keyboard_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_ice():
    """Crazed ice: a crack network, not a noise field.

    THE CRACKS ARE THE MATERIAL, and no amount of layered noise produces them. A crack is a
    THIN CONTINUOUS LINE that closes on itself and divides the surface into plates -- noise
    at any frequency gives you blobs and ridges that never join up. `periodic_voronoi`
    returns the distance between the nearest and second-nearest scattered point, which is
    zero exactly on the boundary between two cells and rises away from it: that is a
    connected network of lines by construction, which is why wax already uses it.

    Two scales, because real ice has both. A few long structural fractures running right
    across the sheet, and a dense craze of hairlines between them. One scale alone reads as
    either a cracked plate or as frosted glass, never as ice.
    """
    rng = np.random.default_rng(20260823)
    structural = periodic_voronoi(rng, 6)    # the few long fractures
    craze = periodic_voronoi(rng, 30)        # the hairline network between them
    frost = periodic_noise(rng, 26, 26, octaves=3)

    # Cracks are GROOVES: the voronoi value is near zero on a fracture, so used directly it
    # cuts the surface down exactly where the line runs.
    height = np.clip(structural, 0, 0.12) * 4.5 + np.clip(craze, 0, 0.06) * 2.6 + frost * 0.06

    # WHITER IN THE CRACKS. A fracture in ice is not a dark line -- it is air, and it
    # scatters, so it goes pale. Getting this backwards is what makes CG ice look like
    # cracked stone.
    # THE MULTIPLIERS ARE THE LINE WIDTH. Voronoi's F2-F1 rises smoothly away from a
    # boundary, so scaling it decides how far from the fracture the pale band reaches
    # before it clips to 1. At 3.2 the bands were soft gradients and the sheet read as
    # frosted glass; a real fracture is a hard thin line, so they are scaled hard.
    crack = 1.0 - np.clip(structural * 9.0, 0, 1) * 0.80 - np.clip(craze * 16.0, 0, 1) * 0.40
    crack = np.clip(crack, 0, 1)

    # Glassy almost everywhere, matte along the fractures. That contrast is most of what
    # sells it: a uniformly shiny blue surface is a swimming pool, not ice.
    rough = 0.10 + 0.55 * crack + 0.05 * frost
    return {
        "Ice_Color": colour_map((0.72, 0.85, 0.93), (0.97, 0.99, 1.0), crack, 0.55),
        # Strong: the fractures are the entire read at a distance, and they are thin.
        "Ice_Normal": normal_map(height, 1.15),
        "Ice_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_jello():
    """Soda jelly: suspended carbonation under a wet, glossy skin.

    The bubbles are SUSPENDED, not burst, and that is the one decision that matters. The
    `bubbles` helper takes a `rim` argument that raises a lip around each dome -- slime
    wants a lot of it, because slime's bubbles have popped and left a crater edge. A bubble
    in setting jelly never reached the surface: it is trapped underneath, pressing up
    against a skin that stays smooth over it. So rim is near zero and the domes are soft.

    Without that distinction this map is slime's, and jello sits next to slime in the level.
    """
    rng = np.random.default_rng(20260824)
    trapped = bubbles(rng, 46, 0.012, 0.045, rim=0.05)
    # A slow swell across the whole surface: jelly is cast in a mould and never settles
    # perfectly flat.
    swell = periodic_noise(rng, 4, 4, octaves=2)
    height = trapped * 0.75 + swell * 0.30

    # WET AND EVEN. Roughness barely moves -- a jelly is uniformly glossy, and variation
    # here would read as it drying out, which is the opposite of appetising. The faint
    # lift over each bubble is the light scattering through thinner material above it.
    rough = 0.07 + 0.06 * trapped
    return {
        # Amber, lighter where a bubble sits under the skin.
        "Jello_Color": colour_map((0.86, 0.52, 0.28), (0.99, 0.78, 0.52), trapped, 0.42),
        # Gentle: these are soft swellings under a skin, not dents in it.
        "Jello_Normal": normal_map(height, 0.55),
        "Jello_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_lambsear():
    """Velvet nap. FUZZ ONLY -- no leaf outlines anywhere in here.

    gen_lambs_ear.py puts the leaves in the MESH, at roughly three studs a leaf, and this
    tile is five studs across. Drawing leaf shapes here too would lay a second set of
    leaves at a different scale across the first, and two conflicting sets of leaves read
    as neither. So this map does the one thing geometry cannot do at this scale: hair.

    THE HAIRS ARE THE MATERIAL. Lamb's ear is silver because it is covered in fine white
    hairs over a green blade, and the green only shows where the hairs part. That is a
    COLOUR effect driven by a very high frequency field, not a shape effect -- at a
    hair's width there is nothing to model, only something to scatter light.
    """
    rng = np.random.default_rng(20260827)
    # 96 cells across five studs is about one cycle every 1.6 hundredths of a stud, which
    # is as fine as this resolution will carry. Two octaves, not six: hairs are all one
    # size, unlike sand grain, and extra octaves only muddy them into noise.
    hair = periodic_noise(rng, 96, 96, octaves=2)
    # The direction hairs lie in. Stretched 8 to 1, because a nap has a GRAIN -- the hairs
    # on a leaf all sweep from the midrib outward, and an isotropic fuzz reads as mould
    # rather than as velvet.
    lie = periodic_noise(rng, 10, 80, octaves=3)
    # Where the fuzz thins and the green blade shows through.
    thin = periodic_noise(rng, 7, 7, octaves=3)

    height = hair * 0.55 + lie * 0.30 + thin * 0.15

    # SILVER WHERE THE HAIRS ARE, green where they part. The mix is weighted hard toward
    # the hair field so the surface reads pale overall with green in the hollows, which is
    # the way round that makes a plant look furry instead of dusty.
    silver = np.clip(hair * 0.72 + lie * 0.20 + thin * 0.30, 0, 1)

    # MATTE, AND NEARLY UNIFORM. Velvet has no specular highlight to speak of -- its sheen
    # comes from light scattering off the hairs, which is in the colour above, not here.
    # Any real variation in roughness would read as damp patches on a plant whose whole
    # point is that it is dry to the touch.
    rough = 0.86 - 0.07 * silver
    return {
        "LambsEar_Color": colour_map((0.44, 0.51, 0.36), (0.86, 0.89, 0.80), silver, 0.52),
        # Strong, because the hairs are the entire read at this scale and they are tiny.
        "LambsEar_Normal": normal_map(height, 1.9),
        "LambsEar_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_foam():
    """Open-cell foam. The BIG pores are in the mesh; this is the fine cell structure
    between them, which is a network of walls and therefore a voronoi, not a noise field."""
    rng = np.random.default_rng(20260905)
    cells = periodic_voronoi(rng, 34)
    grain = periodic_noise(rng, 30, 30, octaves=3)
    height = np.clip(cells, 0, 0.30) * 1.4 + grain * 0.18

    # DRY AND UNIFORMLY MATTE. Foam has no specular at all -- it is the least reflective
    # thing in the game -- and variation here would read as it being damp, which for a
    # material whose appeal is that it is dry and soft is the one wrong note.
    rough = 0.90 - 0.05 * grain
    return {
        "Foam_Color": colour_map((0.80, 0.78, 0.72), (0.96, 0.95, 0.91),
                                 np.clip(cells * 3.0, 0, 1), 0.40),
        "Foam_Normal": normal_map(height, 1.3),
        "Foam_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_clay():
    """Unfired earthenware: grog speckle and a fine tooth, and nothing else.

    QUIET ON PURPOSE. This is the one material whose whole point is that it keeps the
    footprints pressed into it, so every decision here is about not competing with them.
    A busy clay would bury the very marks it exists to hold.
    """
    rng = np.random.default_rng(20260906)
    tooth = periodic_noise(rng, 44, 44, octaves=4)
    grog = periodic_noise(rng, 90, 90, octaves=2)   # the coarse particles in the body
    height = tooth * 0.35 + np.clip(grog - 0.62, 0, 1) * 2.2

    rough = 0.78 + 0.10 * tooth
    return {
        "Clay_Color": colour_map((0.55, 0.36, 0.27), (0.74, 0.55, 0.44), tooth, 0.34),
        "Clay_Normal": normal_map(height, 0.85),
        "Clay_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_charcoal():
    """Charcoal: sooty and matte, with GRAPHITE SHEEN on the high points.

    That contrast is the whole read and it is a roughness effect, not a colour one. A
    uniformly black matte surface is a hole in the screen -- it has no shape, because
    nothing on it catches light. Charcoal in life is dusty in its hollows and slightly
    metallic on its arrises, where handling has burnished it, and that is what makes a
    lump of it legible as a solid object at all.
    """
    rng = np.random.default_rng(20260907)
    soot = periodic_noise(rng, 52, 52, octaves=5)
    burnish = periodic_noise(rng, 9, 9, octaves=2)
    height = soot * 0.55

    # LOW roughness where it is burnished. Inverted from every other material here, where
    # the smooth places are the rough ones.
    rough = 0.88 - 0.42 * np.clip((burnish - 0.55) * 3.0, 0, 1)
    return {
        # Barely any colour range: what varies is the sheen above, not the hue.
        "Charcoal_Color": colour_map((0.10, 0.095, 0.09), (0.26, 0.25, 0.24), soot, 0.55),
        "Charcoal_Normal": normal_map(height, 1.5),
        "Charcoal_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_cloud():
    """Cloud: as close to featureless as a map here gets.

    Almost nothing, and that is the design. Vapour has no surface, so anything crisp
    immediately turns it into a solid -- cotton wool, or worse, polystyrene. The normal is
    weak, the roughness is near total, and the colour moves only enough to keep the mass
    from flattening into a silhouette.
    """
    rng = np.random.default_rng(20260908)
    billow = periodic_noise(rng, 7, 7, octaves=4)
    wisp = periodic_noise(rng, 22, 22, octaves=3)
    height = billow * 0.6 + wisp * 0.2

    return {
        # Cool in the hollows, warm white on the crowns: that is where a cloud gets its
        # depth, since it has no edges to give it any.
        "Cloud_Color": colour_map((0.78, 0.82, 0.90), (1.0, 1.0, 1.0), billow, 0.45),
        "Cloud_Normal": normal_map(height, 0.35),
        "Cloud_Roughness": grey_map(np.clip(0.95 - 0.05 * billow, 0, 1)),
    }


def build_lego():
    """ABS: GLOSSY AND ALMOST PERFECTLY UNIFORM.

    The odd one out in this whole file. Every other material here earns its look from
    variation, and lego earns its look from the absence of it -- injection-moulded plastic
    is flawless by design, and a brick carrying wear or grain reads as a cheap knock-off
    rather than as the real thing. So the roughness is low and nearly flat, and the only
    texture at all is the faint flow pattern the mould leaves.
    """
    rng = np.random.default_rng(20260909)
    flow = periodic_noise(rng, 5, 40, octaves=2)    # stretched: plastic flows one way
    height = flow * 0.10

    return {
        "Lego_Color": colour_map((0.92, 0.92, 0.94), (1.0, 1.0, 1.0), flow, 0.12),
        "Lego_Normal": normal_map(height, 0.25),
        # 0.22, the glossiest surface in the game after chocolate.
        "Lego_Roughness": grey_map(np.clip(0.22 + 0.05 * flow, 0, 1)),
    }


def build_lightswitch():
    """Faceplate plastic: matte, with the faint orange peel of a textured moulding."""
    rng = np.random.default_rng(20260910)
    peel = periodic_noise(rng, 60, 60, octaves=3)
    height = peel * 0.30

    return {
        "LightSwitch_Color": colour_map((0.86, 0.85, 0.81), (0.97, 0.96, 0.93), peel, 0.28),
        "LightSwitch_Normal": normal_map(height, 0.55),
        # Between lego's gloss and foam's matte, which is where wall plastic sits.
        "LightSwitch_Roughness": grey_map(np.clip(0.54 + 0.08 * peel, 0, 1)),
    }


def build_chocolate():
    """Tempered chocolate: high gloss, with BLOOM.

    Bloom is the detail that makes it chocolate rather than brown plastic. Cocoa butter
    that has warmed and recrystallised leaves a pale dusty film in patches, and it is
    matte where the tempered surface around it is mirror-like. It also sets the material's
    mechanic up for free: the bar you are told melts is already showing, at rest, the
    marks of having melted once before.
    """
    rng = np.random.default_rng(20260911)
    bloom = periodic_noise(rng, 6, 6, octaves=3)
    bloom = np.clip((bloom - 0.52) * 3.4, 0, 1)
    grain = periodic_noise(rng, 40, 40, octaves=2)
    height = bloom * 0.22 + grain * 0.10

    # Mirror where tempered, dusty where bloomed. The widest roughness range in the file,
    # and the whole point.
    rough = 0.16 + 0.62 * bloom
    return {
        "Chocolate_Color": colour_map((0.26, 0.15, 0.09), (0.62, 0.50, 0.42), bloom, 0.50),
        "Chocolate_Normal": normal_map(height, 0.65),
        "Chocolate_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_bubblewrap_body():
    """The backing film under the pockets. Clear polythene: glossy, faintly hazy, scuffed.

    THE QUIETEST MAP IN THE FILE, and it has to be. This surface is seen between and under
    the pockets, and the pockets are the material -- anything with real contrast here would
    pull the eye off them onto their own backing. So the colour barely moves, and what
    little variation exists is in the ROUGHNESS: scuffs and handling marks, which is how
    polythene actually differs from itself.
    """
    rng = np.random.default_rng(20260913)
    # Stretched hard along one axis: film comes off a roll and every scuff on it runs the
    # way it was pulled. Isotropic scuffing reads as frosted glass, not as plastic.
    scuff = periodic_noise(rng, 6, 54, octaves=3)
    haze = periodic_noise(rng, 14, 14, octaves=2)
    height = scuff * 0.16 + haze * 0.10

    # Glossy, with the scuffs duller. Polythene is shiny where it is untouched and matte
    # exactly where something has dragged across it.
    rough = 0.20 + 0.34 * np.clip(scuff * 1.4, 0, 1)
    return {
        "BubbleWrapBody_Color": colour_map((0.86, 0.90, 0.92), (0.97, 0.99, 1.0), haze, 0.22),
        "BubbleWrapBody_Normal": normal_map(height, 0.40),
        "BubbleWrapBody_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_salt():
    """Rock salt: crystalline, and the sparkle is a ROUGHNESS effect.

    The cubes are in the mesh. What a texture has to add is the thing that separates salt
    from chalk, which is that a cut crystal face is nearly specular while a fractured one is
    dull -- so the surface glitters in points rather than glowing evenly. That is a few
    hundred very low-roughness specks scattered over an otherwise matte field, and it is not
    something a colour map can fake: paint the sparkle in and it stays lit when the light
    moves, which reads as dirt.
    """
    rng = np.random.default_rng(20260925)
    facets = periodic_noise(rng, 70, 70, octaves=2)
    grain = periodic_noise(rng, 26, 26, octaves=3)
    height = grain * 0.30 + facets * 0.14

    # The top few per cent of the facet field become mirror-bright; everything else stays
    # chalky. A wide roughness range with almost nothing in the middle is what glitter is.
    sparkle = np.clip((facets - 0.72) * 6.0, 0, 1)
    rough = 0.74 - 0.62 * sparkle + 0.06 * grain
    return {
        # Barely any colour variation: salt is white, and what little there is comes from
        # thickness rather than pigment.
        "Salt_Color": colour_map((0.88, 0.89, 0.90), (1.0, 1.0, 1.0), grain, 0.30),
        "Salt_Normal": normal_map(height, 0.9),
        "Salt_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_lava():
    """Obsidian rafts on molten rock. TWO MATERIALS IN ONE MAP, and they share no properties.

    The plates are volcanic glass: near-black, and the glossiest thing in this whole file.
    The channels between them are incandescent: the brightest colour anywhere in the game.
    Nothing in between -- a gradient from crust to melt would read as rusty metal, because
    what makes lava lava is that the transition is SHARP and the contrast enormous.

    The channel network comes from voronoi for the same reason wax's cracks do: a crack is a
    connected line that closes on itself, and no amount of layered noise produces one.
    """
    rng = np.random.default_rng(20260926)
    channels = periodic_voronoi(rng, 9)
    crackle = periodic_voronoi(rng, 34)     # finer crazing across the plates themselves
    glassy = periodic_noise(rng, 30, 30, octaves=3)

    # 1 deep in a channel, 0 out on a plate.
    molten = np.clip(1.0 - channels * 7.0, 0, 1)
    molten = np.maximum(molten, np.clip(1.0 - crackle * 26.0, 0, 1) * 0.55)
    height = -np.clip(channels, 0, 0.16) * 2.2 + glassy * 0.10

    # GLASS IS SMOOTH, MELT IS NOT. Obsidian is close to a mirror; liquid rock is matte
    # because it is radiating rather than reflecting. Getting this the usual way round --
    # shiny lava, dull rock -- is the single most common mistake in a lava texture.
    rough = 0.16 + 0.62 * molten + 0.08 * glassy
    return {
        # Alpha near 1: this map has to WIN over the part colour, because the whole point is
        # a contrast the palette cannot express on its own.
        "Lava_Color": colour_map((0.06, 0.05, 0.06), (1.0, 0.52, 0.10), molten, 0.92),
        "Lava_Normal": normal_map(height, 1.4),
        "Lava_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_oobleck():
    """Cornflour slurry: pale, dense, and almost featureless.

    Deliberately the flattest map here. Oobleck has no grain, no sheen worth the name and no
    colour -- it is white slurry -- and the ONE thing it does have is that it looks dry where
    it is stressed and wet where it is not. So the roughness moves and the colour barely
    does, which is the inverse of most materials in this file.
    """
    rng = np.random.default_rng(20260927)
    stress = periodic_noise(rng, 11, 11, octaves=3)
    fine = periodic_noise(rng, 48, 48, octaves=2)
    height = fine * 0.16 + stress * 0.12

    # Matte where it has stiffened, wet where it has relaxed. That patchiness IS the
    # material: a uniformly wet version is milk and a uniformly dry one is plaster.
    rough = 0.30 + 0.46 * np.clip((stress - 0.45) * 2.4, 0, 1)
    return {
        "Oobleck_Color": colour_map((0.86, 0.85, 0.80), (0.97, 0.97, 0.94), stress, 0.26),
        "Oobleck_Normal": normal_map(height, 0.45),
        "Oobleck_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_buttons():
    """Arcade button plastic: glossy caps, matte housing, and a worn spot on the crown.

    The wear is the detail worth having. A button that has been pressed ten thousand times
    is polished smooth exactly where thumbs land and still textured everywhere else, and
    that single asymmetry is what makes a control panel look used rather than modelled.
    """
    rng = np.random.default_rng(20260928)
    moulding = periodic_noise(rng, 40, 40, octaves=3)
    wear = periodic_noise(rng, 5, 5, octaves=2)
    height = moulding * 0.22

    # Glossy overall -- these are ABS caps -- and glossier still where they are worn.
    rough = 0.30 + 0.16 * moulding - 0.18 * np.clip((wear - 0.5) * 2.2, 0, 1)
    return {
        "Buttons_Color": colour_map((0.90, 0.90, 0.92), (1.0, 1.0, 1.0), wear, 0.16),
        "Buttons_Normal": normal_map(height, 0.35),
        "Buttons_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_snow():
    """Snow: white, and the entire read is SPARKLE plus BLUE SHADOW.

    Two things make snow look like snow and neither is its colour. The first is that it
    glitters in points, because it is a heap of ice crystals catching light at every angle --
    the same trick as the salt above, cranked harder. The second is that its hollows go BLUE:
    snow is deep enough for light to scatter inside it, and what comes back out of a dent has
    lost its warm end. A white surface with grey shadows is polystyrene.
    """
    rng = np.random.default_rng(20260929)
    crystals = periodic_noise(rng, 84, 84, octaves=2)
    packing = periodic_noise(rng, 18, 18, octaves=4)
    height = crystals * 0.22 + packing * 0.40

    sparkle = np.clip((crystals - 0.76) * 7.0, 0, 1)
    rough = 0.80 - 0.68 * sparkle + 0.08 * packing
    return {
        # Cold blue in the hollows, warm white on the crowns. `packing` is the depth field,
        # so this is a real ambient-occlusion tint rather than a random mottle.
        "Snow_Color": colour_map((0.72, 0.79, 0.92), (1.0, 1.0, 1.0), packing, 0.44),
        "Snow_Normal": normal_map(height, 1.1),
        "Snow_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_slab():
    """The solid body under the material layer: one neutral set for all six.

    === Why this ColorMap is nearly white, when every other one is coloured ===

    SurfaceAppearance in Overlay mode BLENDS over part.Color using the map's alpha, so those
    maps can carry real colour. A MaterialVariant has no alpha mode -- its ColorMap is
    MULTIPLIED by part.Color, exactly like a built-in material. Bake a colour in here and
    every slab in the game comes out that colour no matter what MaterialAppearance says.

    Kept between 0.72 and 1.0, so the six baseColors -- from dark brown butter to pale
    lavender stable -- all survive the multiply and stay distinguishable.

    One set rather than six, for the same reason: the slab is the cake, not the icing. It is
    the same stone under every material and only its tint changes.
    """
    rng = np.random.default_rng(20260820)
    pores = periodic_noise(rng, 30, 30, octaves=5)
    swell = periodic_noise(rng, 5, 5, octaves=3) * 0.5
    height = pores * 0.55 + swell

    # Matte. This is structure, and structure that catches highlights competes with the
    # material sitting on top of it -- which is the thing meant to look wet.
    rough = 0.74 + 0.11 * pores
    # Deliberately shallow: 0.72 to 1.0 rather than 0 to 1, so the multiply never crushes a
    # dark baseColor into mud.
    mix = 0.5 + 0.5 * (pores * 0.6 + swell * 0.4)
    return {
        "Slab_Color": colour_map((0.72, 0.72, 0.72), (1.0, 1.0, 1.0), mix, 1.0),
        "Slab_Normal": normal_map(height, 1.2),
        "Slab_Roughness": grey_map(np.clip(rough, 0, 1)),
    }



def build_water():
    """Ripple for the sea, RETUNED for a 200-stud repeat.

    This was authored for a 40-stud repeat, which put every feature in it below the mesh's
    own 61-to-297-stud waves -- detail underneath detail, invisible from 700 studs up, an
    upload that changed nothing. The mesh now stops at 180 studs and this owns everything
    from 200 down.

    That is a much wider band than before, so the noise starts COARSE -- two cells across the
    tile, i.e. 100-stud features -- and runs seven octaves down to about 1.5 studs. Starting
    fine was the original mistake and it is the whole difference between a texture that
    reads at distance and one that averages to grey.
    """
    rng = np.random.default_rng(20260821)
    swell = periodic_noise(rng, 2, 3, octaves=7)
    cross = periodic_noise(rng, 3, 2, octaves=6) * 0.7
    chop = periodic_noise(rng, 9, 7, octaves=4) * 0.35
    height = swell * 0.55 + cross * 0.35 + chop

    # Very low, and only slightly varied. Water is the glossiest thing in the game, and the
    # variation is what stops it reading as a mirror -- it is also the half of this set that
    # was doing real work even at the wrong scale, because roughness changes WHERE the
    # surface glints regardless of how large the features are.
    rough = 0.05 + 0.08 * (0.5 + 0.5 * swell) + 0.04 * chop
    mix = 0.5 + 0.5 * cross
    return {
        # Near-white and barely there: the sea's colour is set in BackdropService and the
        # tiles are tinted by part.Color. This only breaks up the flatness.
        "Water_Color": colour_map((0.84, 0.91, 0.96), (1.0, 1.0, 1.0), mix, 0.22),
        "Water_Normal": normal_map(height, 1.8),
        "Water_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


def build_concrete():
    """Weathered concrete, for the backdrop towers, colonnade and facades.

    Board-marked rather than smooth: faint horizontal lines from the shuttering, plus
    aggregate pitting and broad staining. Board marks are what stop a 2000-stud tower
    reading as a painted box, and they are cheap -- one anisotropic octave.

    Kept LOW CONTRAST on purpose. This sits 700 to 5200 studs away behind 0.26-density fog,
    and detail authored to look right up close arrives as noise. What survives that distance
    is the broad staining; the fine grain is there for the near band only.
    """
    rng = np.random.default_rng(20260822)
    boards = periodic_noise(rng, 2, 26, octaves=3)
    aggregate = periodic_noise(rng, 34, 34, octaves=5)
    staining = periodic_noise(rng, 4, 4, octaves=3)
    height = boards * 0.35 + aggregate * 0.55

    rough = 0.68 + 0.12 * aggregate + 0.06 * staining
    mix = 0.5 + 0.5 * (staining * 0.7 + boards * 0.3)
    return {
        # Near-white for the same reason the slab set is: these are tinted by the pastel
        # palette in BackdropService, and a coloured map would flatten all six tints into one.
        "Concrete_Color": colour_map((0.70, 0.70, 0.72), (1.0, 1.0, 1.0), mix, 1.0),
        "Concrete_Normal": normal_map(height, 1.0),
        "Concrete_Roughness": grey_map(np.clip(rough, 0, 1)),
    }



def build_pooltile():
    """Small square mosaic tile, for the aquapark structures.

    The single most aquapark thing there is. Concrete says municipal building; 20-stud
    mosaic with grout lines between says LEISURE CENTRE, and it does it instantly and from
    a long way off, because a regular grid at a legible size is a texture no natural surface
    has.

    Built from a square wave rather than noise: the grout has to be STRAIGHT and evenly
    spaced or it reads as crazing. Fifteen tiles across the repeat, so at the 200-stud
    StudsPerTile these end up around 13 studs each -- big enough to resolve at 900 studs and
    small enough to still read as tiling rather than as panels.
    """
    rng = np.random.default_rng(20260823)
    axis = np.arange(RES, dtype=np.float64) / RES
    u, v = np.meshgrid(axis, axis, indexing="ij")

    tiles = 15
    # THE GRID IS OFFSET BY HALF A TILE, and the seam check is what found this.
    #
    # Without the +0.5 the texture edge falls in the MIDDLE of a tile, so tile 0's left half
    # butts against tile 14's right half -- two different shades meeting with no grout line
    # between them, which is a mosaic tile split down the middle repeated across the whole
    # surface. Offset, both edges land on grout and both resolve to the same tile index.
    su, sv = u * tiles + 0.5, v * tiles + 0.5

    # Distance to the nearest grout line in each axis, as a 0-1 ramp.
    fu = np.abs(su % 1.0 - 0.5) * 2.0
    fv = np.abs(sv % 1.0 - 0.5) * 2.0
    grout = np.clip((1.0 - fu) * 9.0, 0, 1) + np.clip((1.0 - fv) * 9.0, 0, 1)
    grout = np.clip(grout, 0, 1)

    # Per-tile shade variation, which is what stops a mosaic reading as printed wallpaper.
    # Real pools are laid from mixed batches and no two tiles match. Modulo, not clip, so the
    # lattice wraps with the grid above.
    shade = rng.random((tiles, tiles))
    iu = np.floor(su).astype(int) % tiles
    iv = np.floor(sv).astype(int) % tiles
    per_tile = shade[iu, iv] * 2.0 - 1.0

    stain = periodic_noise(rng, 3, 3, octaves=4)
    height = -grout * 0.9 + per_tile * 0.10

    # Glazed tile is GLOSSY and the grout between it is not, which is the whole read: a
    # uniform roughness over a tile pattern looks like printed lino.
    rough = 0.16 + 0.62 * grout + 0.06 * stain
    mix = 0.5 + 0.5 * (per_tile * 0.55 + stain * 0.45)
    return {
        # Near-white, because BackdropService tints these from the pastel palette and a
        # MaterialVariant's ColorMap multiplies rather than replaces.
        "PoolTile_Color": colour_map((0.66, 0.74, 0.78), (1.0, 1.0, 1.0), mix, 1.0),
        "PoolTile_Normal": normal_map(height, 1.6),
        "PoolTile_Roughness": grey_map(np.clip(rough, 0, 1)),
    }


# Maps that are ATLASES, not tiling samples, and must be exempt from the seam check.
#
# The check is right about them and wrong to fail them: an atlas has twenty-five different
# keycaps in it, so of course its left edge does not continue into its right. It is never
# tiled -- gen_keyboard addresses it by explicit per-cap UVs. Exempting it by name beats
# the alternatives, which are deleting a check that catches a real and invisible bug on
# every other map, or quietly loosening its threshold until nothing trips it.
ATLAS_MAPS = {"Keyboard_Color"}


def verify(pixels, name):
    """The seam check. A texture that does not tile is the one failure that shows up
    everywhere at once and is invisible in the file itself."""
    if name in ATLAS_MAPS:
        print(f"  {name}: atlas, seam check skipped (addressed by explicit UVs)")
        return True
    problems = []
    for axis, label in ((0, "left/right"), (1, "top/bottom")):
        near = np.take(pixels, 0, axis=axis)
        far = np.take(pixels, RES - 1, axis=axis)
        # Opposite edges are one step apart on a torus, so they should be close but not
        # identical; a real seam shows up as a jump far larger than the local variation.
        step = np.abs(np.take(pixels, 1, axis=axis) - near).mean()
        gap = np.abs(far - near).mean()
        if gap > max(step * 4.0, 0.02):
            problems.append(f"{label} seam (edge gap {gap:.4f} vs step {step:.4f})")
    print(f"  {name}: {'ok' if not problems else '!! ' + '; '.join(problems)}")
    return not problems


def main():
    all_ok = True
    for label, maps in (
        ("honey", build_honey()),
        ("slime", build_slime()),
        ("butter", build_butter()),
        ("wax", build_wax()),
        ("sand", build_sand()),
        ("bubble wrap", build_bubblewrap()),
        ("bubble wrap, giant", build_bubblewrap_giant()),
        ("creamy keyboard", build_keyboard()),
        ("ice", build_ice()),
        ("jello soda", build_jello()),
        ("lamb's ear", build_lambsear()),
        ("foam", build_foam()),
        ("clay", build_clay()),
        ("charcoal", build_charcoal()),
        ("cloud", build_cloud()),
        ("lego", build_lego()),
        ("light switches", build_lightswitch()),
        ("chocolate", build_chocolate()),
        ("bubble wrap body", build_bubblewrap_body()),
        ("salt", build_salt()),
        ("lava", build_lava()),
        ("oobleck", build_oobleck()),
        ("buttons", build_buttons()),
        ("snow", build_snow()),
        ("slab", build_slab()),
        ("water", build_water()),
        ("concrete", build_concrete()),
        ("pool tile", build_pooltile()),
    ):
        print(f"  --- {label} ---")
        for name, pixels in maps.items():
            all_ok = verify(pixels, name) and all_ok
            _, mean = save(pixels, name)
            print(f"    wrote {name}.png, mean rgb {mean:.3f}")

    print("")
    print(f"  84 PNGs written to {OUT_DIR}")
    print("  Upload each to Roblox, then paste the asset ids into MaterialAppearance.")
    print("")
    print("Done." if all_ok else "!! a map failed its seam check -- it will tile visibly.")


if __name__ == "__main__":
    main()
