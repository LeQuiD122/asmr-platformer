"""Hill House's hall (the hundred-and-twelfth pass): taking his key, and his clock going again.

    python audio/gen_hall_sfx.py

Writes four files to audio/endings/, for SoundService.StorySounds:

    KeyLift     his key lifted off its hook: the green ribbon's soft brush, and the key's bow touching the brass hook
                once as it comes away, small and round
    ClockStart  his longcase clock, stopped since 1979, going again: the movement freed with a soft wooden knock and a
                low purr of its wheels, then tick, tock, tick, tock in the case, a second apart, going on as it fades
    ClockPunch  the time clock by the flume (the hundred-and-fourteenth pass): the lever down, the card stamped with a
                heavy soft chunk, and the recorder's small bell
    MorningChord  the true ending (the hundred-and-fifteenth pass): the Flooded Halls' open chord carried home, on a felt
                piano over low strings, as his face is seen

Soft and low (the game's taste: nothing shrill, nothing pitched up; the clock's ticks are wood more than metal). Seeded:
re-running writes the same files.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import (bp, env, felt_piano, finish, lp, n_, peak, pink, place, reverb, rng_for, strike, swell, t_, warm_pad,  # noqa
                     white, write)

OUT = pathlib.Path(__file__).resolve().parent / "endings"


def add(out, x, at, gain=1.0):
    start = int(at * 44100)
    end = min(len(out), start + len(x))
    if end > start:
        out[start:end] += x[:end - start] * gain


def key_lift(rng):
    seconds = 1.5
    x = np.zeros(n_(seconds))
    # THE RIBBON: a short soft brush of cloth as the hand closes on it and lifts.
    t = t_(0.55)
    brush = pink(0.55, rng) * swell(t, 0.55, 0.18, 0.3, power=1.4)
    add(x, peak(bp(brush, 350, 2200)), 0.0, 0.35)
    # THE KEY on the hook: one small touch of brass on brass, struck softly (a key's modes, low for a key's).
    for at, gain, hardness in ((0.24, 0.5, 0.3), (0.31, 0.18, 0.2)):
        tink = strike(0.9, [1480, 2390, 3610], [0.5, 0.3, 0.16], [1.0, 0.45, 0.2], rng, hardness=hardness, detune=0.003)
        add(x, peak(lp(tink, 3200)), at, gain)
    x = reverb(x, "small", rng, wet=0.25)[:n_(seconds)]
    return finish(x, -24.0, high_cut=3800, fade_out=0.3)


def tick(rng, low, case):
    """One beat of the escapement in its wooden case: the pallet's small click, rounded, and the case's knock."""
    click = strike(0.4, [low * 4.1, low * 6.7], [0.05, 0.03], [0.5, 0.25], rng, hardness=0.35)
    knock = strike(0.4, [case, case * 2.3, case * 3.9], [0.16, 0.08, 0.04], [1.0, 0.4, 0.15], rng, hardness=0.2)
    body = peak(lp(click, 2600)) * 0.35 + peak(knock)
    return peak(body)


def clock_punch(rng):
    """The time clock at the flume (the hundred-and-fourteenth pass): the lever brought down, a heavy soft chunk as the
    card is stamped, and the recorder's small bell, low and round."""
    seconds = 1.6
    x = np.zeros(n_(seconds))
    # THE LEVER: a short dry slide of brass, coming down.
    t = t_(0.18)
    slide = pink(0.18, rng) * env(t, 0.06, 0.05)
    add(x, peak(bp(slide, 400, 2000)), 0.0, 0.18)
    # THE CHUNK: the stamp going through the card, iron in its case, low.
    chunk = strike(0.6, [118, 263, 451], [0.22, 0.1, 0.05], [1.0, 0.45, 0.2], rng, hardness=0.3)
    add(x, peak(lp(chunk, 2200)), 0.16, 0.9)
    add(x, tick(rng, 240, 140), 0.17, 0.4)
    # THE BELL, once, small and soft, a beat after.
    ting = strike(1.3, [880, 2340, 4480], [1.0, 0.45, 0.2], [1.0, 0.3, 0.08], rng, hardness=0.25, detune=0.002)
    add(x, peak(lp(ting, 3000)), 0.3, 0.16)
    x = reverb(x, "small", rng, wet=0.22)[:n_(seconds)]
    return finish(x, -23.0, high_cut=3600, fade_out=0.5)


def morning_chord(rng):
    """The true ending (the hundred-and-fifteenth pass), as his face is seen: the chord the Flooded Halls' own leaves
    open (it ends on A, the dominant) carried home to D. The felt piano rolls it slowly from the bottom up, the strings
    swell in under it with a low D beneath, and it rings on, warm and low."""
    d = 11.0
    notes = [146.8, 220.0, 293.7, 370.0]
    layers = []
    for k, f in enumerate(notes):
        v = 0.36 * (1.0 - 0.08 * k) * rng.uniform(0.92, 1.04)
        layers.append((k * 0.16 * rng.uniform(0.85, 1.15), 1.0 / (1 + 0.15 * k), felt_piano(f, d, rng, v)))
    strings = warm_pad([73.4] + notes, d, rng, attack=2.4, release=5.0, brightness=0.38)
    layers.append((0.0, 1.1, strings))
    x = reverb(place(d, layers), "hall", rng, wet=0.42)[:n_(d)]
    return finish(x, -17.0, high_cut=4200, fade_out=3.0)


def clock_start(rng):
    seconds = 6.0
    x = np.zeros(n_(seconds))
    # FREED: a soft knock as the pendulum is set going, and the wheels' low purr turning over under it.
    add(x, tick(rng, 260, 150), 0.0, 0.8)
    t = t_(0.7)
    purr = pink(0.7, rng) * env(t, 0.03, 0.18) * (0.6 + 0.4 * np.sin(2 * np.pi * 38 * t))
    add(x, peak(bp(purr, 120, 700)), 0.04, 0.3)
    # TICK, TOCK: a second apart, the tock a shade lower than the tick, as a real one is; the last ones fade with it.
    for k in range(5):
        at = 0.9 + k * 1.0
        if k % 2 == 0:
            beat = tick(rng, 300, 210)
        else:
            beat = tick(rng, 270, 188)
        add(x, beat, at, 0.62 * (1.0 - 0.1 * max(0, k - 2)))
    # The room under it: the faintest air of the hall, so the ticks are somewhere.
    add(x, peak(lp(white(seconds, rng), 400)) * 0.015, 0.0)
    x = reverb(x, "small", rng, wet=0.3)[:n_(seconds)]
    return finish(x, -23.0, high_cut=3600, fade_out=1.6)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    print(write(OUT / "KeyLift.wav", key_lift(rng_for("KeyLift", 11200))))
    print(write(OUT / "ClockStart.wav", clock_start(rng_for("ClockStart", 11201))))
    print(write(OUT / "ClockPunch.wav", clock_punch(rng_for("ClockPunch", 11400))))
    print(write(OUT / "MorningChord.wav", morning_chord(rng_for("MorningChord", 11500))))
