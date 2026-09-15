"""PBR maps for Hub_SunkenBlade: colour, normal, roughness, metalness.

    python gen_blade_pbr.py

Pure Python, no Blender: these are images, and Blender has nothing to offer that PIL does not.

=== Why these exist ===

The blades were shipped on Enum.Material.CorrodedMetal, which is a real PBR material and was
an honest answer to "I cannot upload textures". It is still not the same thing as a material
authored FOR this object: a built-in tiles at a fixed world scale and knows nothing about where
the fuller runs, where the chips are, or which end has been underwater for a century.

These four do. They are authored in the blade's own UV space, so the corrosion climbs from the
tip upward (the end that has been submerged), the fuller reads as a polished groove, and the
edge stays brighter than the flat because an edge is where the metal has been worn back.

=== What each map is for ===

  colour     what it is
  normal     the dents -- this is the one that does most of the work, because corrosion is
             geometry at a scale too small to model
  roughness  where it is polished and where it is eaten; the single strongest cue for metal
  metalness  bare steel is metal, rust is not, and the difference is what stops the rusted
             areas looking like painted-on brown

Upload all four, make a SurfaceAppearance under the MeshPart, and assign them to ColorMap,
NormalMap, RoughnessMap and MetalnessMap. HubService drops CorrodedMetal automatically when it
finds a SurfaceAppearance already there.
"""

import math
import os
import random

try:
    from PIL import Image
except ImportError:  # pragma: no cover - guidance is the useful behaviour here
    raise SystemExit("This needs Pillow: python -m pip install Pillow")

SIZE = 512
OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                        "..", "meshes", "blade_pbr"))

STEEL = (150, 156, 170)
RUST = (112, 74, 46)
DARK = (58, 52, 54)


def value_noise(seed, cells):
    """Smooth noise on a grid, bilinearly interpolated.

    Written out rather than imported because the whole point is control: the corrosion has to
    be coarse enough to read at 40 studs and fine enough not to look like camouflage, and that
    is one number here rather than a library's idea of a good default.
    """
    rng = random.Random(seed)
    grid = [[rng.random() for _ in range(cells + 1)] for _ in range(cells + 1)]

    def at(u, v):
        # CLAMPED, because u and v reach exactly 1.0 at the last pixel and int(1.0 * cells)
        # is cells -- one past the last cell whose neighbour exists. The grid is built with
        # cells + 1 entries for exactly that reason and the index still has to stay inside it.
        x, y = u * cells, v * cells
        x0, y0 = min(int(x), cells - 1), min(int(y), cells - 1)
        fx, fy = x - x0, y - y0
        # Smoothstep, so the cell boundaries do not show as a lattice.
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        a = grid[y0][x0] * (1 - fx) + grid[y0][x0 + 1] * fx
        b = grid[y0 + 1][x0] * (1 - fx) + grid[y0 + 1][x0 + 1] * fx
        return a * (1 - fy) + b * fy

    return at


def fields():
    """The three fields every map is built from, sampled once and shared.

    corrosion  how eaten this point is, 0 clean to 1 gone
    fuller     1 in the groove down the middle of the blade, 0 at the edges
    edge       1 at the very edges of the blade, where metal is worn brightest
    """
    coarse = value_noise(7, 6)
    fine = value_noise(23, 22)
    speckle = value_noise(101, 64)

    rows = []
    for py in range(SIZE):
        v = py / (SIZE - 1)
        row = []
        for px in range(SIZE):
            u = px / (SIZE - 1)

            # Across the blade: 0 at one edge, 1 at the other, 0.5 down the fuller.
            across = abs(u - 0.5) * 2
            fuller = max(0.0, 1.0 - (across / 0.34) ** 2)
            edge = max(0.0, (across - 0.72) / 0.28) ** 1.5

            # UP the blade is v, and the tip end is submerged: corrosion is heaviest low and
            # thins out toward the hilt, with plenty of noise so the transition is not a band.
            depth = (1.0 - v) ** 1.6
            grain = coarse(u, v) * 0.55 + fine(u, v) * 0.32 + speckle(u, v) * 0.13
            corrosion = max(0.0, min(1.0, depth * 1.15 + grain * 0.75 - 0.55))
            # The fuller holds water, so it eats faster; the edges shed it and stay cleaner.
            corrosion = max(0.0, min(1.0, corrosion + fuller * 0.18 - edge * 0.25))

            row.append((corrosion, fuller, edge))
        rows.append(row)
    return rows


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def build():
    os.makedirs(OUT_DIR, exist_ok=True)
    data = fields()

    colour = Image.new("RGB", (SIZE, SIZE))
    rough = Image.new("RGB", (SIZE, SIZE))
    metal = Image.new("RGB", (SIZE, SIZE))
    height = [[0.0] * SIZE for _ in range(SIZE)]

    cpix, rpix, mpix = colour.load(), rough.load(), metal.load()

    for py in range(SIZE):
        for px in range(SIZE):
            corrosion, fuller, edge = data[py][px]

            # COLOUR. Steel toward rust, darkened in the fuller because a groove is in shadow
            # from almost every angle, and lifted at the edge where it is worn bright.
            base = mix(STEEL, RUST, corrosion)
            base = mix(base, DARK, fuller * 0.35)
            base = mix(base, (205, 210, 222), edge * (1.0 - corrosion) * 0.55)
            cpix[px, py] = base

            # ROUGHNESS. Polished steel is smooth, rust is not, and that contrast is the
            # single strongest cue that something is metal at all.
            r = 0.22 + corrosion * 0.62 - edge * 0.10 + fuller * 0.05
            r = max(0.0, min(1.0, r))
            rpix[px, py] = (int(r * 255),) * 3

            # METALNESS. Bare steel is metal; rust is an oxide and is not. Without this the
            # corroded areas read as brown paint on shiny metal.
            m = max(0.0, min(1.0, 1.0 - corrosion * 0.9))
            mpix[px, py] = (int(m * 255),) * 3

            # Height for the normal map: pitting sinks, the fuller sinks, the edge stands.
            height[py][px] = -corrosion * 0.75 - fuller * 0.35 + edge * 0.2

    # NORMALS from the height field by central difference. This is the map that does the most
    # work: corrosion is geometry at a scale far too small to model, and a normal map is the
    # only way to get it without a million triangles.
    normal = Image.new("RGB", (SIZE, SIZE))
    npix = normal.load()
    strength = 3.4
    for py in range(SIZE):
        for px in range(SIZE):
            left = height[py][(px - 1) % SIZE]
            right = height[py][(px + 1) % SIZE]
            up = height[(py - 1) % SIZE][px]
            down = height[(py + 1) % SIZE][px]
            dx = (left - right) * strength
            dy = (up - down) * strength
            length = math.sqrt(dx * dx + dy * dy + 1.0)
            npix[px, py] = (int((dx / length * 0.5 + 0.5) * 255),
                            int((dy / length * 0.5 + 0.5) * 255),
                            int((1.0 / length * 0.5 + 0.5) * 255))

    for name, image in (("Blade_Color", colour), ("Blade_Normal", normal),
                        ("Blade_Roughness", rough), ("Blade_Metalness", metal)):
        path = os.path.join(OUT_DIR, name + ".png")
        image.save(path)
        print("    %-18s -> %s" % (name, path))


if __name__ == "__main__":
    build()
    print("Done. Upload the four PNGs, then add a SurfaceAppearance under Hub_SunkenBlade.")
