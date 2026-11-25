"""Harrow Bay's surfaces: the textures of the lobby and of the levels' buildings (the hundred-and-sixty-ninth pass), and
the levels' own slab, concrete and pool tile maps made again at twice the size (the hundred-and-seventieth).

    python blender/gen_surfaces.py

From your note of 2026-11-03: "improve the textures of the lobby and the overall texture quality of the levels, I want
it to be a very pleasant looking game". Plain Python (numpy and Pillow), no Blender: every map is 1024 pixels square,
tiles with no seam (every field is periodic by construction, and each map is checked), and comes in three: a ColorMap,
a NormalMap (OpenGL, green up, as gen_pbr.py's) and a RoughnessMap.

THE COLOUR MAPS ARE LIGHT AND NEAR WHITE on purpose. A MaterialVariant's ColorMap is MULTIPLIED by the part's own Color
(HANDOFF, Slabs: MaterialVariant), so every part keeps the colour it was given and the map adds what a flat colour
cannot: a board's grain, knots and nails, a flagstone's joints and its chipped edges, marble's veins, a tile's grout.

MANIFEST, at the bottom, says what each is, the BaseMaterial its MaterialVariant must have (a variant only shows on a
part of that material), its StudsPerTile, and what it dresses. MaterialAppearance.SURFACES puts the nine Harrow ones on
the parts; check_surfaces.py holds the two to each other.
"""
import pathlib
import sys

import numpy as np
from PIL import Image

N = 1024


def rng(seed):
    return np.random.default_rng(seed)


def grid(n=N):
    """u, v in [0, 1), shape (n, n): u across (columns), v down (rows)."""
    a = (np.arange(n) + 0.5) / n
    return np.meshgrid(a, a)


def fractal(seed, n=N, beta=2.0, low=2.0, high=None, aniso=(1.0, 1.0)):
    """Periodic fractal noise from filtered white noise: power ~ 1/f^beta between `low` and `high` cycles per tile.
    `aniso` stretches it (frequencies along u and v scaled), e.g. (0.15, 1) for grain running along u."""
    r = rng(seed)
    white = r.standard_normal((n, n))
    fu = np.fft.fftfreq(n) * n
    fv = np.fft.fftfreq(n) * n
    FU, FV = np.meshgrid(fu, fv)
    f = np.sqrt((FU * aniso[0]) ** 2 + (FV * aniso[1]) ** 2)
    f[0, 0] = 1.0
    amp = f ** (-beta / 2.0)
    amp[f < low] *= (f[f < low] / low) ** 4
    if high:
        amp *= np.exp(-(f / high) ** 2)
    amp[0, 0] = 0.0
    out = np.real(np.fft.ifft2(np.fft.fft2(white) * amp))
    out -= out.mean()
    out /= out.std() + 1e-9
    return out


def norm01(a):
    lo, hi = np.percentile(a, 0.5), np.percentile(a, 99.5)
    return np.clip((a - lo) / (hi - lo + 1e-9), 0, 1)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def worley(seed, cells, n=N, jitter=0.85):
    """Periodic cellular noise: distance to the nearest and second nearest feature point (in cell widths), and the
    nearest's id, with `cells` x `cells` jittered points per tile. Each pixel looks only at its own cell and the eight
    round it."""
    r = rng(seed)
    offset = (r.random((cells, cells, 2)) - 0.5) * jitter
    u, v = grid(n)
    cu, cv = u * cells, v * cells
    iu, iv = np.floor(cu).astype(int), np.floor(cv).astype(int)
    d1 = np.full((n, n), 9.0)
    d2 = np.full((n, n), 9.0)
    ident = np.zeros((n, n), dtype=np.int64)
    for du in (-1, 0, 1):
        for dv in (-1, 0, 1):
            nu, nv = iu + du, iv + dv
            wu, wv = nu % cells, nv % cells
            px = nu + 0.5 + offset[wv, wu, 0]
            py = nv + 0.5 + offset[wv, wu, 1]
            d = np.sqrt((cu - px) ** 2 + (cv - py) ** 2)
            closer = d < d1
            d2 = np.where(closer, d1, np.minimum(d2, d))
            ident = np.where(closer, wv * cells + wu, ident)
            d1 = np.where(closer, d, d1)
    return d1, d2, ident


def warp(field, du, dv):
    """Sample `field` at (u + du, v + dv) with wrap-around (du, dv in tile units), nearest-neighbour bilinear."""
    n = field.shape[0]
    u, v = grid(n)
    x = ((u + du) % 1.0) * n - 0.5
    y = ((v + dv) % 1.0) * n - 0.5
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx, fy = x - x0, y - y0
    x0 %= n
    y0 %= n
    x1 = (x0 + 1) % n
    y1 = (y0 + 1) % n
    return (field[y0, x0] * (1 - fx) * (1 - fy) + field[y0, x1] * fx * (1 - fy)
            + field[y1, x0] * (1 - fx) * fy + field[y1, x1] * fx * fy)


def normal_map(height, strength):
    """Tangent-space normal map (OpenGL, +Y up) from a height field in [0, 1], wrapping at the edges."""
    n = height.shape[0]
    dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * n / 1024.0
    dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * n / 1024.0
    nx = -dx * strength
    ny = dy * strength  # rows run down the image, and +Y (green) is up the image
    nz = np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / length, ny / length, nz / length], -1) * 0.5 + 0.5
    return (np.clip(rgb, 0, 1) * 255 + 0.5).astype(np.uint8)


def to8(a):
    return (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)


def tint(value, rgb):
    """A grey value field (0..1) tinted by an rgb triple (0..1)."""
    return np.stack([value * np.asarray(c, dtype=float) for c in rgb], -1)


# ===================================================================== the surfaces


def boards(seed=11, planks=8):
    """Seaside deck boards running along u: strong grain, a few knots, one staggered butt joint a board, nail heads where
    the joists are, rounded arrises, thin dark gaps."""
    r = rng(seed)
    u, v = grid()
    row = np.floor(v * planks).astype(int)
    inrow = v * planks - row
    cut = r.random(planks)[row]
    pos = (u - cut) % 1.0
    along = np.minimum(pos, 1 - pos)  # tile units to the board's butt joint
    side = (pos > 0.5).astype(int)
    plank_id = row * 2 + side
    grain = fractal(seed + 1, beta=1.5, low=3, aniso=(0.05, 1.0))
    streak = fractal(seed + 2, beta=1.1, low=30, aniso=(0.04, 1.0))
    wob = fractal(seed + 3, beta=2.6, low=2) * 0.02
    rings = np.sin((v * planks + wob * planks + grain * 0.05) * 2 * np.pi * 5.0) * 0.5 + 0.5
    rings = rings ** 4
    shade = r.uniform(0.86, 1.0, planks * 2)[plank_id]
    warm = r.uniform(-0.012, 0.012, planks * 2)[plank_id]
    knots = np.zeros_like(u)
    for _ in range(7):
        kx, ky = r.random(), (r.integers(planks) + r.uniform(0.35, 0.65)) / planks
        dx = (u - kx + 0.5) % 1.0 - 0.5
        dy = (v - ky + 0.5) % 1.0 - 0.5
        d = np.sqrt((dx / 0.022) ** 2 + (dy / 0.009) ** 2)
        knots = np.maximum(knots, np.exp(-d * d * 1.4) * r.uniform(0.6, 1.0))
    nails = np.zeros_like(u)
    for joist in (0.0, 0.5):
        for off in (0.006, -0.006):
            dx = (u - joist - off + 0.5) % 1.0 - 0.5
            for k in range(planks):
                for yy in (0.28, 0.72):
                    dy = (v - (k + yy) / planks + 0.5) % 1.0 - 0.5
                    nails = np.maximum(nails, 1 - smooth(0.0016, 0.0032, np.sqrt(dx * dx + dy * dy)))
            break
    edge = np.minimum(inrow, 1 - inrow)
    gap = 1 - smooth(0.008, 0.02, edge)
    jgap = 1 - smooth(0.0012, 0.003, along)
    gaps = np.maximum(gap, jgap)
    arris = smooth(0.0, 0.1, edge) * smooth(0.0, 0.012, along)
    value = shade * (0.84 + 0.09 * grain * 0.33 + 0.06 * streak * 0.33 - 0.09 * rings - 0.32 * knots - 0.35 * nails)
    value = value * (1 - 0.5 * gaps)
    colour = tint(value, (1.0, 0.975 + warm, 0.94 - warm))
    height = 0.55 + 0.25 * arris + 0.03 * grain * 0.33 + 0.02 * streak * 0.33 - 0.04 * rings - 0.06 * knots - 0.1 * nails
    height = np.where(gaps > 0.5, 0.08 + 0.2 * (1 - gaps), height)
    rough = np.clip(0.8 + 0.05 * streak * 0.33 + 0.08 * rings - 0.05 * knots + 0.12 * gaps - 0.2 * nails, 0, 1)
    return colour, height, rough, 5.0


def flags(seed=21, rows=4, per_row=3):
    """Promenade flagstones in running bond: each stone its own shade, fine grain, chipped arrises, recessed joints."""
    r = rng(seed)
    u, v = grid()
    jag = fractal(seed + 1, beta=2.2, low=6) * 0.004
    vv = (v + jag) % 1.0
    row = np.floor(vv * rows).astype(int)
    shift = (row % 2) * 0.5 / per_row + r.uniform(-0.05, 0.05, rows)[row]
    uu = (u + shift + jag * 0.7) % 1.0
    col = np.floor(uu * per_row).astype(int)
    fx = uu * per_row - col
    fy = vv * rows - row
    stone = row * per_row + col
    edge = np.minimum(np.minimum(fx, 1 - fx) / per_row * rows, np.minimum(fy, 1 - fy))
    joint = 1 - smooth(0.012, 0.03, edge)
    grainy = fractal(seed + 2, beta=1.0, low=60)
    blot = fractal(seed + 3, beta=2.4, low=3)
    pits_d1, _, _ = worley(seed + 4, 40)
    pits = 1 - smooth(0.0, 0.18, pits_d1)
    shade = r.uniform(0.82, 1.0, rows * per_row)[stone]
    value = shade * (0.9 + 0.035 * grainy + 0.06 * blot - 0.12 * pits * (r.random() * 0.5 + 0.5))
    value = value * (1 - 0.45 * joint)
    colour = tint(value, (1.0, 0.985, 0.96))
    tilt = (r.uniform(-1, 1, rows * per_row)[stone] * (fx - 0.5) + r.uniform(-1, 1, rows * per_row)[stone] * (fy - 0.5)) * 0.04
    height = 0.6 + tilt + 0.03 * grainy + 0.05 * blot - 0.1 * pits
    height = height * (1 - joint) + 0.1 * joint
    rough = np.clip(0.8 + 0.06 * grainy + 0.15 * joint - 0.05 * blot, 0, 1)
    return colour, height, rough, 6.0


def ashlar(seed=31, rows=5):
    """Sea wall: coursed blocks of uneven length, rough pitted faces, deep joints."""
    r = rng(seed)
    u, v = grid()
    row = np.floor(v * rows).astype(int)
    fy = v * rows - row
    block = np.zeros_like(row)
    fx = np.zeros_like(u)
    width = np.zeros_like(u)
    for k in range(rows):
        cuts = np.sort(r.random(r.integers(2, 4)))
        mask = row == k
        pos = (u[mask] - cuts[0]) % 1.0
        rel = np.sort((cuts - cuts[0]) % 1.0)
        idx = np.searchsorted(rel, pos, side='right') - 1
        start = rel[idx]
        end = np.where(idx + 1 < len(rel), rel[np.minimum(idx + 1, len(rel) - 1)], 1.0)
        fx[mask] = (pos - start) / (end - start)
        width[mask] = (end - start)
        block[mask] = k * 4 + idx
    edge = np.minimum(np.minimum(fx, 1 - fx) * width * rows, np.minimum(fy, 1 - fy))
    joint = 1 - smooth(0.02, 0.06, edge)
    face = fractal(seed + 2, beta=1.8, low=4)
    grit = fractal(seed + 3, beta=0.8, low=80)
    d1, _, _ = worley(seed + 4, 24)
    pits = 1 - smooth(0.0, 0.25, d1)
    bulge = smooth(0.0, 0.25, edge)
    shade = r.uniform(0.86, 1.0, rows * 4)[block]
    value = shade * (0.92 + 0.05 * face + 0.03 * grit - 0.1 * pits) * (1 - 0.4 * joint)
    colour = tint(value, (0.99, 0.98, 0.95))
    height = 0.3 + 0.35 * bulge + 0.08 * face + 0.02 * grit - 0.12 * pits
    height = height * (1 - joint) + 0.02 * joint
    rough = np.clip(0.86 + 0.05 * grit + 0.08 * joint, 0, 1)
    return colour, height, rough, 7.0


def render(seed=41):
    """Painted render: broad trowel sweeps, a fine speckle, nothing loud."""
    u, v = grid()
    sweep = fractal(seed, beta=2.8, low=2, aniso=(1.0, 0.35))
    sweep2 = warp(fractal(seed + 1, beta=2.8, low=2, aniso=(0.35, 1.0)), sweep * 0.02, sweep * 0.02)
    speck = fractal(seed + 2, beta=0.4, low=200)
    value = 0.93 + 0.03 * sweep + 0.02 * sweep2 + 0.012 * speck
    colour = tint(value, (1.0, 0.99, 0.975))
    height = norm01(0.6 * sweep + 0.4 * sweep2) * 0.7 + 0.3 * norm01(speck) * 0.4
    rough = np.clip(0.84 + 0.04 * speck, 0, 1)
    return colour, height, rough, 2.0


def marble(seed=51):
    """Polished marble: a pale ground, soft clouds, and veins that wander, branch and fade."""
    base = fractal(seed, beta=2.4, low=2)
    w1 = fractal(seed + 1, beta=3.6, low=1.5, high=12) * 0.08
    w2 = fractal(seed + 2, beta=3.6, low=1.5, high=12) * 0.08
    field = warp(fractal(seed + 3, beta=3.6, low=1.5, high=10, aniso=(0.4, 1.0)), w1, w2)
    s = np.abs(np.sin(field * 1.5))
    veins = np.exp(-(s / 0.17) ** 2)
    halo = np.exp(-(s / 0.45) ** 2)
    second = warp(fractal(seed + 4, beta=3.4, low=2, high=16), w2 * 1.5, w1 * 1.5)
    thin = np.exp(-(np.abs(np.sin(second * 2.0)) / 0.07) ** 2)
    fade = smooth(-0.8, 0.9, fractal(seed + 5, beta=2.2, low=2))
    value = 0.95 + 0.02 * base - 0.36 * veins * (0.45 + 0.55 * fade) - 0.07 * halo - 0.16 * thin * fade
    value = np.minimum(value, 1.0)
    colour = tint(value, (1.0, 0.993, 0.982))
    height = 0.5 + 0.02 * base - 0.03 * veins
    rough = np.clip(0.14 + 0.1 * veins + 0.04 * thin + 0.02 * base, 0, 1)
    return colour, height, rough, 1.0


def painted_metal(seed=61):
    """Painted iron: orange peel, a few fine scuffs, the paint's own sheen."""
    peel = fractal(seed, beta=0.9, low=90)
    scuffs = fractal(seed + 1, beta=1.4, low=30, aniso=(0.06, 1.0))
    scuff = smooth(1.8, 2.6, scuffs)
    blot = fractal(seed + 2, beta=2.4, low=3)
    value = 0.95 + 0.02 * blot - 0.1 * scuff
    colour = tint(value, (1.0, 1.0, 1.0))
    height = 0.5 + 0.05 * peel - 0.06 * scuff
    rough = np.clip(0.42 + 0.04 * peel + 0.18 * scuff + 0.03 * blot, 0, 1)
    return colour, height, rough, 1.5


def canvas(seed=71, threads=96):
    """Awning canvas: a plain weave, slubs in the yarn."""
    u, v = grid()
    slub_u = fractal(seed, beta=1.0, low=20, aniso=(1.0, 0.05)) * 0.15
    slub_v = fractal(seed + 1, beta=1.0, low=20, aniso=(0.05, 1.0)) * 0.15
    a = np.sin(u * threads * 2 * np.pi) * 0.5 + 0.5
    b = np.sin(v * threads * 2 * np.pi) * 0.5 + 0.5
    over = np.where((np.floor(u * threads) + np.floor(v * threads)) % 2 == 0, a + slub_u, b + slub_v)
    blot = fractal(seed + 2, beta=2.2, low=3)
    value = 0.9 + 0.07 * (over - 0.5) + 0.03 * blot
    colour = tint(value, (1.0, 0.99, 0.97))
    height = norm01(over)
    rough = np.clip(0.9 + 0.04 * over, 0, 1)
    return colour, height, rough, 3.0


# ===================================================================== the levels
def slab(seed=81):
    """The stone under every chunk: a fine sandstone with faint beds and pores."""
    u, v = grid()
    grit = fractal(seed, beta=0.6, low=120)
    cloud = fractal(seed + 1, beta=2.2, low=2)
    beds = np.sin((v + fractal(seed + 2, beta=2.6, low=2) * 0.03) * 2 * np.pi * 9) * 0.5 + 0.5
    d1, _, _ = worley(seed + 3, 48)
    pores = 1 - smooth(0.0, 0.14, d1)
    value = 0.9 + 0.025 * grit + 0.045 * cloud + 0.03 * (beds - 0.5) - 0.1 * pores
    colour = tint(value, (1.0, 0.99, 0.97))
    height = 0.55 + 0.04 * grit + 0.05 * cloud + 0.02 * beds - 0.14 * pores
    rough = np.clip(0.82 + 0.05 * grit + 0.06 * pores, 0, 1)
    return colour, height, rough, 4.0


def board_concrete(seed=91, boards_=6):
    """Board-marked concrete: the shuttering's planks printed in it, tie holes, a few rain stains."""
    r = rng(seed)
    u, v = grid()
    row = np.floor(v * boards_).astype(int)
    fy = v * boards_ - row
    grain = fractal(seed + 1, beta=1.5, low=4, aniso=(0.07, 1.0))
    step = r.uniform(-1, 1, boards_)[row] * 0.05
    line = 1 - smooth(0.0, 0.025, np.minimum(fy, 1 - fy))
    grit = fractal(seed + 2, beta=0.7, low=100)
    d1, _, _ = worley(seed + 3, 36)
    pores = 1 - smooth(0.0, 0.12, d1)
    stain = smooth(0.4, 1.6, fractal(seed + 4, beta=2.0, low=3, aniso=(1.0, 0.12)))
    ties = np.zeros_like(u)
    for tx in (0.25, 0.75):
        for ty in (0.5 / boards_ * 3, 0.5 / boards_ * 3 + 0.5):
            dx = (u - tx + 0.5) % 1.0 - 0.5
            dy = (v - ty + 0.5) % 1.0 - 0.5
            ties = np.maximum(ties, 1 - smooth(0.006, 0.011, np.sqrt(dx * dx + dy * dy)))
    value = (0.9 + 0.03 * grain + 0.02 * grit - 0.1 * pores - 0.06 * line + step * 0.4 - 0.1 * stain) * (1 - 0.6 * ties)
    colour = tint(value, (1.0, 0.995, 0.985))
    height = 0.55 + 0.03 * grain + step - 0.1 * line - 0.12 * pores - 0.4 * ties + 0.02 * grit
    rough = np.clip(0.84 + 0.05 * grit + 0.06 * pores - 0.08 * stain, 0, 1)
    return colour, height, rough, 4.0


def mosaic(seed=101, tiles=12):
    """Glazed pool mosaic: small tiles a shade apart, domed, glossy, in matt grout."""
    r = rng(seed)
    u, v = grid()
    col = np.floor(u * tiles).astype(int)
    row = np.floor(v * tiles).astype(int)
    fx = u * tiles - col
    fy = v * tiles - row
    tile = row * tiles + col
    edge = np.minimum(np.minimum(fx, 1 - fx), np.minimum(fy, 1 - fy))
    grout = 1 - smooth(0.035, 0.07, edge)
    dome = smooth(0.0, 0.3, edge)
    shade = r.uniform(0.86, 1.0, tiles * tiles)[tile]
    hue = r.uniform(-0.035, 0.035, tiles * tiles)[tile]
    glaze = fractal(seed + 1, beta=2.0, low=8) * 0.015
    value = shade + glaze
    colour = np.stack([value * (0.97 - hue), value * (0.995 + hue * 0.3), value * (1.0 + hue)], -1)
    # The grout one colour all over, whatever tile it runs beside.
    colour = colour * (1 - grout[..., None]) + 0.74 * grout[..., None]
    height = 0.45 + 0.35 * dome + glaze
    height = height * (1 - grout) + 0.05 * grout
    rough = np.clip(0.12 + 0.03 * fractal(seed + 2, beta=1.0, low=30) + 0.72 * grout, 0, 1)
    return colour, height, rough, 4.5


def ripples(seed=111):
    """Capillary ripples on the sea: crossing wave trains and a fine chop."""
    r = rng(seed)
    u, v = grid()
    h = np.zeros_like(u)
    for _ in range(9):
        a = r.uniform(0, 2 * np.pi)
        k = r.integers(3, 14)
        kx, ky = int(round(np.cos(a) * k)), int(round(np.sin(a) * k))
        if kx == 0 and ky == 0:
            continue
        h += np.sin(2 * np.pi * (kx * u + ky * v) + r.uniform(0, 2 * np.pi)) / np.sqrt(kx * kx + ky * ky)
    h = norm01(h) * 0.7 + 0.3 * norm01(fractal(seed + 1, beta=1.6, low=12))
    colour = tint(np.full_like(u, 0.98), (1.0, 1.0, 1.0))
    rough = np.clip(0.05 + 0.04 * h, 0, 1)
    return colour, h, rough, 3.0


def timber(seed=121):
    """Timber: posts, benches and beams. The grain of the boards without their gaps, joints or nails."""
    grain = fractal(seed, beta=1.5, low=3, aniso=(0.05, 1.0))
    streak = fractal(seed + 1, beta=1.1, low=30, aniso=(0.04, 1.0))
    u, v = grid()
    wob = fractal(seed + 2, beta=2.6, low=2) * 0.02
    rings = (np.sin((v * 6 + wob * 6 + grain * 0.05) * 2 * np.pi * 5.0) * 0.5 + 0.5) ** 4
    value = 0.86 + 0.03 * grain + 0.02 * streak - 0.08 * rings
    colour = tint(value, (1.0, 0.975, 0.94))
    height = 0.55 + 0.01 * grain + 0.007 * streak - 0.04 * rings
    rough = np.clip(0.78 + 0.02 * streak + 0.07 * rings, 0, 1)
    return colour, height, rough, 4.0


def cast(seed=131):
    """Cast stone: kerbs, posts and walls. Smooth, a fine aggregate, a few blowholes, the mould's faint mottle."""
    grit = fractal(seed, beta=0.6, low=120)
    mottle = fractal(seed + 1, beta=2.4, low=2)
    d1, _, _ = worley(seed + 2, 30)
    holes = 1 - smooth(0.0, 0.1, d1)
    value = 0.91 + 0.02 * grit + 0.04 * mottle - 0.14 * holes
    colour = tint(value, (1.0, 0.99, 0.98))
    height = 0.55 + 0.025 * grit + 0.02 * mottle - 0.25 * holes
    rough = np.clip(0.82 + 0.04 * grit + 0.08 * holes, 0, 1)
    return colour, height, rough, 3.0


# ===================================================================== what is made, and where it goes
# name: (recipe, the MaterialVariant's BaseMaterial, its StudsPerTile, what it dresses). The nine Harrow surfaces are new
# MaterialVariants (MaterialAppearance.SURFACES puts them on the parts); Slab, Concrete and PoolTile are the maps of
# the levels' existing variants (the slabs', ConcreteBackdrop and PoolTileBackdrop), made again here at twice the size.
MANIFEST = {
    'HarrowBoards': (boards, 'WoodPlanks', 8, 'deck boards: the lobby\'s boardwalks and any boarded floor'),
    'HarrowTimber': (timber, 'Wood', 6, 'timber: posts, benches, beams'),
    'HarrowFlags': (flags, 'Slate', 12, 'flagstones: the lobby\'s decks, paths and plinths'),
    'HarrowStone': (ashlar, 'Rock', 10, 'coursed stone: the sea wall and rock'),
    'HarrowMarble': (marble, 'Marble', 16, 'veined marble: the fountain, statues and planters'),
    'HarrowRender': (render, 'Plaster', 12, 'render: walls'),
    'HarrowCast': (cast, 'Concrete', 10, 'cast stone: kerbs, posts and walls'),
    'HarrowCanvas': (canvas, 'Fabric', 4, 'canvas: awnings and cloth'),
    'HarrowPaint': (painted_metal, 'Metal', 8, 'painted iron: railings and lamps (the lobby only)'),
    'Slab': (slab, 'Concrete, Plaster and Slate', 4, 'the stone under every chunk (your three slab variants)'),
    'Concrete': (board_concrete, 'Concrete', 16, 'ConcreteBackdrop: the levels\' concrete'),
    'PoolTile': (mosaic, 'Concrete', 6, 'PoolTileBackdrop: the pools\' and the halls\' tile'),
}


def seam_ok(img):
    """A map tiles if the step from its last column round to its first (and last row to first) is no bigger than the
    steps inside it."""
    a = img.astype(float)
    inside = np.abs(np.diff(a, axis=1)).mean() + np.abs(np.diff(a, axis=0)).mean()
    across = np.abs(a[:, 0] - a[:, -1]).mean() + np.abs(a[0, :] - a[-1, :]).mean()
    return across <= inside * 1.6 + 1.0


def main():
    out = pathlib.Path(__file__).resolve().parent.parent / 'textures'
    out.mkdir(exist_ok=True)
    good = True
    for name, (recipe, base, studs, use) in MANIFEST.items():
        colour, height, rough, strength = recipe()
        maps = {
            'Color': to8(colour),
            'Normal': normal_map(height, strength),
            'Roughness': np.repeat(to8(rough)[..., None], 3, axis=-1),
        }
        for kind, pixels in maps.items():
            ok = seam_ok(pixels)
            good = good and ok
            Image.fromarray(pixels, 'RGB').save(out / ('%s_%s.png' % (name, kind)))
            print('  %-13s %-9s %s' % (name, kind, 'tiles' if ok else 'SEAM'))
        print('    %s on %s, %d studs a tile: %s' % (name, base, studs, use))
    print('%d maps written to %s' % (len(MANIFEST) * 3, out))
    if not good:
        print('!! a map does not tile')
        sys.exit(1)


if __name__ == '__main__':
    main()
