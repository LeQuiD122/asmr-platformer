"""Mr Barlow's pry bar swung into the Siren Room's loose bricks (the hundred-and-twenty-ninth pass, from the test of
2026-10-22: "I should actually hit the bricks and there should be some pieces flying out").

    python audio/gen_bar_sfx.py

Writes two files to audio/story/, for SoundService.StorySounds:

    BarStrike   one blow of the bar into old brick: iron meeting it dull (the bar is held, so it hardly rings), the
                brick's own knock under it, and the mortar crumbling out in a short spill of grit after. Played once
                a blow, a little lower each time.
    BrickBurst  the patch giving on the last blow: the bricks coming out together, knocking on each other, and
                landing one after another on the floorboards, a last one rolling over, and the dust settling.

Soft and low, as the game's sounds are: no clang, nothing bright. Seeded: re-running writes the same files.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import SR, bp, env, finish, lp, n_, peak, place, reverb, rng_for, strike, t_, white, write  # noqa

OUT = pathlib.Path(__file__).resolve().parent / "story"


def grit(seconds, rng, rate, decay, low=900, high=4200):
    """Grains of mortar falling: a sparse spill of tiny clicks, thinning out over `decay`."""
    t = t_(seconds)
    density = rate * np.exp(-t / decay)
    hits = (rng.random(len(t)) < density / SR) * rng.uniform(0.3, 1.0, len(t))
    grain = bp(white(0.012, rng), low, high) * np.hanning(n_(0.012))
    return np.convolve(hits, grain)[:len(t)]


def bar_strike(rng):
    d = 1.2
    # THE BLOW: iron into brick. The bar's own modes short (a hand is on it) and low; the brick's knock under it.
    iron = strike(0.5, [420, 1150, 2240], [0.1, 0.05, 0.025], [1.0, 0.35, 0.12], rng, hardness=0.5, detune=0.004)
    brick = strike(0.5, [118, 236, 455], [0.12, 0.06, 0.03], [1.0, 0.55, 0.25], rng, hardness=0.35)
    thud = lp(white(0.08, rng), 380) * env(t_(0.08), 0.002, 0.02)
    # THE MORTAR: a crumble as it breaks, then grit trickling out of the joint.
    crumble = bp(white(0.3, rng), 500, 2000) * env(t_(0.3), 0.004, 0.05)
    trickle = grit(0.9, rng, rate=900, decay=0.22, low=600, high=2400)
    x = place(d, [(0.0, 0.4, peak(lp(iron, 1600))), (0.0, 1.0, peak(brick)), (0.0, 0.7, peak(thud)),
                  (0.01, 0.25, peak(crumble)), (0.05, 0.14, peak(trickle))])
    x = reverb(x, "small", rng, wet=0.3)[:n_(d)]
    return finish(x, -19.0, high_cut=3000, fade_out=0.3)


def brick_burst(rng):
    d = 2.4
    layers = []
    # Out together: a heavy knock of brick on brick as the patch breaks.
    first = strike(0.6, [150, 310, 620], [0.14, 0.07, 0.04], [1.0, 0.5, 0.2], rng, hardness=0.4)
    layers.append((0.0, 1.0, peak(first)))
    layers.append((0.0, 0.3, peak(bp(white(0.4, rng), 500, 2000) * env(t_(0.4), 0.003, 0.08))))
    # Down onto the boards, one after another, each a dull wooden thump with the brick's knock in it.
    at = 0.22
    for k in range(7):
        f = rng.uniform(95, 140)
        board = strike(0.5, [f, f * 2.3, f * 3.9], [0.16, 0.08, 0.04], [1.0, 0.4, 0.15], rng, hardness=0.3)
        knock = strike(0.5, [rng.uniform(260, 340), rng.uniform(560, 700)], [0.06, 0.03], [1.0, 0.4], rng, hardness=0.45)
        layers.append((at, 0.85 - 0.07 * k, peak(peak(board) + 0.4 * peak(knock))))
        at += rng.uniform(0.07, 0.17)
    # The last one rolling over once, and the dust and grit settling.
    roll = strike(0.4, [128, 290], [0.1, 0.05], [1.0, 0.4], rng, hardness=0.3)
    layers.append((at + 0.18, 0.4, peak(roll)))
    layers.append((0.1, 0.15, peak(grit(2.0, rng, rate=700, decay=0.6, low=600, high=2400))))
    x = place(d, layers)
    x = reverb(x, "small", rng, wet=0.32)[:n_(d)]
    return finish(x, -18.0, high_cut=3000, fade_out=0.4)


if __name__ == "__main__":
    print(write(OUT / "BarStrike.wav", bar_strike(rng_for("BarStrike", 12900))))
    print(write(OUT / "BrickBurst.wav", brick_burst(rng_for("BrickBurst", 12901))))
