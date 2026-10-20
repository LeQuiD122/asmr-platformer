"""The back rooms' scare (the hundred-and-third pass): what you hear when he comes, and when he reaches you.

    python audio/gen_backrooms_sfx.py

Writes three files into audio/story/, for SoundService.StorySounds (where the story's sounds are):

    DoorSlam       the staff door thrown open against the wall: the latch, a short dry hinge, and the bang, in the
                   back rooms' own low hard room
    TubeDie        a ceiling tube going out: the ballast's clunk, its hum dropping away, the tube ticking as it cools
    ScreamerStab   when he reaches you: the lights gone, then everything at once, a low cluster of strings driven hard,
                   a sub boom falling away under it, a scrape across it, and the room ringing after

Low and heavy rather than shrill (the game's sounds are low; the scare is in the weight and the suddenness, not in a
high pitch). Seeded: re-running writes the same files.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import (SR, bp, env, finish, gliding, lp, modal, n_, peak, place, reverb, rng_for, strike, t_,  # noqa
                     warm_pad, white, write)

OUT = pathlib.Path(__file__).resolve().parent / "story"


def add(out, x, at, gain=1.0):
    x = np.array(x, dtype=float)
    k = min(len(x), n_(0.06))
    if k > 1:
        x[-k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    a = n_(at)
    if a < len(out):
        b = min(len(out), a + len(x))
        out[a:b] += gain * x[:b - a]


def door_slam(rng):
    seconds = 2.0
    x = np.zeros(n_(seconds))
    latch = strike(0.12, [1250, 2300], [0.04, 0.02], [1.0, 0.4], rng, hardness=0.75)
    add(x, peak(latch), 0.0, 0.35)
    t = t_(0.22)
    creak = bp(white(0.22, rng), 260, 620) * (0.5 + 0.5 * np.sin(2 * np.pi * 34 * t) ** 2) * env(t, 0.02, 0.18)
    add(x, peak(creak), 0.05, 0.25)
    bang = strike(1.2, [88, 152, 241, 330, 512], [0.5, 0.32, 0.2, 0.12, 0.06], [1.0, 0.8, 0.55, 0.3, 0.15], rng,
                  hardness=0.6, detune=0.02)
    add(x, peak(bang), 0.24, 1.0)
    add(x, peak(lp(white(0.08, rng), 1200) * env(t_(0.08), 0.0005, 0.02)), 0.24, 0.5)
    x = reverb(x, "shaft", rng, wet=0.35)[:n_(seconds)]
    return finish(x, -14.0, high_cut=3200, fade_out=0.4)


def tube_die(rng):
    seconds = 1.4
    x = np.zeros(n_(seconds))
    t = t_(seconds)
    hum = (np.sin(2 * np.pi * 120 * t) + 0.45 * np.sin(2 * np.pi * 240 * t) + 0.2 * np.sin(2 * np.pi * 360 * t))
    hum *= np.clip(1 - t / 0.09, 0, 1) ** 2 * np.clip(t / 0.01, 0, 1)
    add(x, hum, 0.0, 0.35)
    clunk = strike(0.4, [140, 310, 620], [0.15, 0.08, 0.04], [1.0, 0.5, 0.2], rng, hardness=0.55)
    add(x, peak(clunk), 0.06, 0.9)
    for when in np.sort(rng.uniform(0.2, 1.0, 5)):  # the tube ticking as it cools
        tick = strike(0.05, [rng.uniform(1500, 2000)], [0.02], [1.0], rng, hardness=0.6)
        add(x, peak(tick), when, rng.uniform(0.06, 0.14))
    x = reverb(x, "small", rng, wet=0.25)[:n_(seconds)]
    return finish(x, -20.0, high_cut=3600, fade_out=0.2)


def screamer_stab(rng):
    seconds = 3.2
    x = np.zeros(n_(seconds))
    # A cluster of low strings, every note a semitone from the next, struck at once and driven hard.
    notes = [55.0, 58.27, 61.74, 82.41, 87.31, 92.5, 110.0, 116.54]
    strings = warm_pad(notes, 2.6, rng, attack=0.015, release=1.6, brightness=0.95, voices=4)
    strings = np.tanh(3.0 * peak(strings)) * env(t_(2.6), 0.005, 1.4)
    add(x, strings, 0.0, 0.9)
    t = t_(2.0)
    boom = np.sin(2 * np.pi * np.cumsum(np.linspace(58, 30, len(t))) / SR) * env(t, 0.004, 1.2)
    add(x, boom, 0.0, 0.8)
    scrape = bp(white(0.9, rng), 500, 1900) * (0.6 + 0.4 * np.sin(2 * np.pi * 41 * t_(0.9)) ** 2) * env(t_(0.9), 0.003, 0.5)
    add(x, peak(scrape), 0.0, 0.3)
    hit = lp(white(0.1, rng), 2000) * env(t_(0.1), 0.0003, 0.03)
    add(x, peak(hit), 0.0, 0.7)
    x = reverb(x, "hall", rng, wet=0.3)[:n_(seconds)]
    return finish(x, -11.5, low_cut=26, high_cut=3400, fade_out=0.6)


if __name__ == "__main__":
    print(write(OUT / "DoorSlam.wav", door_slam(rng_for("DoorSlam", 10300))))
    print(write(OUT / "TubeDie.wav", tube_die(rng_for("TubeDie", 10300))))
    print(write(OUT / "ScreamerStab.wav", screamer_stab(rng_for("ScreamerStab", 10300))))
