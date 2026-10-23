"""The slide's arches (the hundred-and-eighth pass): the sound of passing under one on the way down.

    python audio/gen_arch_sfx.py

Writes audio/endings/ArchPass.wav, for SoundService.StorySounds:

    ArchPass    under an arch at speed: the air of it opening round you and closing behind, and a few soft glassy
                notes as it lights and sparkles, low and round (played a little higher or lower each arch, never much)

Soft and warm (the game's taste: low, round, nothing shrill or pitched up). Seeded: re-running writes the same file.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import (bell, bp, finish, lp, n_, peak, pink, reverb, rng_for, swell, t_, write)  # noqa

OUT = pathlib.Path(__file__).resolve().parent / "endings"


def add(out, x, at, gain=1.0):
    start = int(at * 44100)
    end = min(len(out), start + len(x))
    if end > start:
        part = x[:end - start].copy()
        tail = min(len(part), int(0.06 * 44100))
        if tail > 1 and end - start < len(x):
            part[-tail:] *= np.linspace(1, 0, tail)
        out[start:end] += part * gain


def arch_pass(rng):
    seconds = 1.6
    x = np.zeros(n_(seconds))
    # THE AIR: pink noise swelling to the moment under the arch and away, its band opening a little as it passes.
    t = t_(0.9)
    air = pink(0.9, rng) * swell(t, 0.9, 0.38, 0.5, power=1.6)
    air = bp(air, 180, 1400) * 0.8 + bp(air, 500, 2200) * 0.35 * swell(t, 0.9, 0.42, 0.3)
    add(x, peak(lp(air, 2400)), 0.0, 0.9)
    # THE SPARKLE: three soft glassy notes, close together, as it lights (a fifth and an octave, low for a chime).
    for k, f in enumerate([523.25, 783.99, 1046.5]):
        add(x, peak(bell(f, 1.1, rng, t60=1.1, hardness=0.25)), 0.34 + k * 0.045, 0.22 - k * 0.04)
    x = reverb(x, "open", rng, wet=0.22)[:n_(seconds)]
    return finish(x, -21.0, high_cut=4200, fade_out=0.35)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    print(write(OUT / "ArchPass.wav", arch_pass(rng_for("ArchPass", 10800))))
