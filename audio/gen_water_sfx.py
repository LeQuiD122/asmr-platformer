"""The levels' water (the ninety-eighth pass): every splash, drip and stream that was the engine's one splash.

    python audio/gen_water_sfx.py

Writes audio/water/, for a Folder SoundService.WaterSounds: SIX files. The pools of the Sky Pools, the Sunken City's
streets and harbour, the baths' drips, the dive seen from the shore: every one of them was impact_water.mp3 at another
pitch, so all the water in the game was one sound. Now it is water, made as water is (sfx_kit.py: bubbles ringing,
drops landing, cavities closing), and every take is picked at random and never the last one again (WaterSounds.lua):

    Splash_x6         a body going into water, six ways (2 s slots): from a hop to a fall from a height
    Dip_x8            a hand or a foot in water, eight (1 s slots): a step into a pool, a kick, a slap of the surface
    Drip_x8           a drip, eight (1 s slots): into a puddle, a pool, off a ledge onto wet stone
    Lap               12 s, seamless: water lapping at a stone edge, the hollow knock of it under a lip
    Pour              10 s, seamless: water falling into water, a waterfall's foot or a spout into a basin
    Stream            10 s, seamless: water running, fast and shallow, over stone and down a channel

Seeded, so re-running writes the same files.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import (bp, brown, bubble, bubbles, drift, droplet, env, fade, finish, finish_loop, lp, n_, peak,  # noqa
                     pink, place, reverb, reverb_loop, rng_for, sculpted, splash, t_, white, write, write_sheet)

OUT = pathlib.Path(__file__).resolve().parent / "water"
# Each sheet's slot, in seconds: WaterSounds.lua has the same numbers (check_audio.py holds them to it).
SLOTS = {"Splash": 2.0, "Dip": 1.0, "Drip": 1.0}


def add(out, x, at, gain=1.0):
    a = n_(at)
    if a < len(out):
        b = min(len(out), a + len(x))
        out[a:b] += gain * x[:b - a]


def body_splash(k, rng):
    size = [0.8, 1.0, 1.2, 1.4, 1.7, 2.1][k]
    x = splash(rng, size=size, seconds=1.9)
    return finish(reverb(x, "open", rng, wet=0.15)[:n_(1.9)], -19.0 + 0.6 * k, high_cut=7000, fade_out=0.3)


def dip(k, rng):
    kind = k % 4
    if kind == 0:  # a foot stepping into a pool: a soft slap and a gulp of bubbles
        x = splash(rng, size=0.35, seconds=0.8)
    elif kind == 1:  # a kick: two quick slaps and spray
        x = place(0.9, [(0.0, 1.0, splash(rng, size=0.3, seconds=0.6)), (0.12, 0.7, splash(rng, size=0.25, seconds=0.6))])
    elif kind == 2:  # a hand through the surface: a swish, bubbles drawn after it
        t = t_(0.8)
        swish = lp(bp(white(0.8, rng), 300, 2200), 2400) * env(t, 0.06, 0.15)
        trail = bubbles(0.8, rng, 500 * env(t, 0.05, 0.2), r_mm=(0.8, 3.0), beta=2.4, xi=(0.03, 0.15))
        x = 0.8 * peak(swish) + 0.6 * peak(trail)
    else:  # a slap of the surface, flat and wet
        x = splash(rng, size=0.45, seconds=0.8)
    return finish(x, -21.0, high_cut=6000, fade_out=0.12)


def drip(k, rng):
    if k % 3 == 2:
        # Onto wet stone, not water: a tiny wet tick and a smear of spray.
        t = t_(0.3)
        tick = lp(bp(white(0.3, rng), 1200, 5000), 5000) * env(t, 0.0005, 0.006)
        smear = lp(bp(white(0.3, rng), 600, 3000), 3000) * env(t, 0.004, 0.03)
        x = 0.9 * peak(tick) + 0.4 * peak(smear)
    else:
        x = droplet(rng, size=rng.uniform(0.8, 1.6), xi=(0.15, 0.35), pitch=(800, 2000))
        if k % 3 == 1:
            # A second, smaller drop off the first.
            x = place(0.7, [(0.0, 1.0, x), (rng.uniform(0.15, 0.3), 0.45, droplet(rng, size=1.4, xi=(0.2, 0.4)))])
    x = reverb(x, "small", rng, wet=0.3)[:n_(0.9)]
    return finish(x, -24.0, high_cut=6000, fade_out=0.15)


def lap(seconds, rng):
    out = 0.1 * lp(pink(seconds, rng), 300)
    at = 0.05
    while at < seconds:
        s = splash(rng, size=rng.uniform(0.15, 0.35), seconds=0.6)
        add(out, lp(s, 1800, order=4), at, rng.uniform(0.25, 0.6))
        if rng.uniform() < 0.4:
            add(out, bubble(rng.uniform(150, 260), rng, xi=0.08), at + rng.uniform(0.05, 0.3), rng.uniform(0.3, 0.6))
        at += rng.uniform(0.5, 1.5)
    return reverb_loop(out, "small", rng, wet=0.25)


def pour(seconds, rng):
    t = t_(seconds)
    level = 0.85 + 0.15 * drift(seconds, rng, rate=0.6)
    churn = bubbles(seconds, rng, 2600 * level, r_mm=(0.8, 6.0), beta=2.3, xi=(0.05, 0.25))
    deep = bubbles(seconds, rng, 120 * level, r_mm=(5.0, 14.0), beta=1.9, xi=(0.1, 0.3))

    def shape(times, freqs):
        return 1 / (1 + (freqs / 1100) ** 2.2) * (freqs > 60)
    roar = sculpted(seconds, rng, shape) * level
    x = peak(churn) + 0.4 * peak(lp(deep, 900)) + 0.7 * peak(roar)
    return reverb_loop(x, "open", rng, wet=0.2)


def stream(seconds, rng):
    level = 0.8 + 0.2 * drift(seconds, rng, rate=0.5)
    run = bubbles(seconds, rng, 900 * level, r_mm=(0.7, 4.5), beta=2.4, xi=(0.05, 0.3))
    gurgle = bubbles(seconds, rng, 40 * level, r_mm=(4.0, 10.0), beta=2.0, xi=(0.15, 0.35))

    def shape(times, freqs):
        return 1 / (1 + (freqs / 800) ** 2.4) * (freqs > 50)
    flow = sculpted(seconds, rng, shape) * level
    x = peak(run) + 0.35 * peak(lp(gurgle, 1200)) + 0.6 * peak(flow)
    return reverb_loop(x, "small", rng, wet=0.2)


if __name__ == "__main__":
    rng = rng_for("WaterSounds", 9800)
    print(write_sheet(OUT / "Splash_x6.wav", [body_splash(k, rng) for k in range(6)], SLOTS["Splash"]))
    print(write_sheet(OUT / "Dip_x8.wav", [dip(k, rng) for k in range(8)], SLOTS["Dip"]))
    print(write_sheet(OUT / "Drip_x8.wav", [drip(k, rng) for k in range(8)], SLOTS["Drip"]))
    print(write(OUT / "Lap.wav", finish_loop(lap(14.0, rng), 12.0, 2.0, -24.0)))
    print(write(OUT / "Pour.wav", finish_loop(pour(12.0, rng), 10.0, 2.0, -20.0)))
    print(write(OUT / "Stream.wav", finish_loop(stream(12.0, rng), 10.0, 2.0, -22.0)))
