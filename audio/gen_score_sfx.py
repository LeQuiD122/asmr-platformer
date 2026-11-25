"""The endings' score (the two-hundred-and-eleventh pass, from your note of 2026-11-13: "the scenes lack music,
specifically for setting up a specific mood for a climax of the animation, like they do in live-action movies").

    python audio/gen_score_sfx.py              every one
    python audio/gen_score_sfx.py ScoreHit     only those named

Writes audio/endings/<Name>.wav for SoundService.StorySounds:

  ShoreScoreLoop   City Shore, the climb to the board: wistful, D minor, a low string pedal and a felt-piano figure.
  SunkenScoreLoop  The Sunken City, the drain: uneasy, a low C with a tritone above it, a slow two-beat pulse.
  HallsScoreLoop   The Flooded Halls: dread, a low B, a minor-second cluster that breathes, a heartbeat of a pulse.
  HillScoreLoop    Hill House: warm and held, F with its suspended fourth, the piano turning over a slow figure.
  ScoreHit         The climax, every level's: a deep drum and a low boom, the strings struck together, a long tail.
                   Played at each level's own pitch (Cinema.climax).

Each bed is a seamless loop the scene starts quietly and lets grow (Cinema.score); the hit cuts it off on the moment
the ending turns on (the splash, the plunge, the drain, the jaws, the clock), and the level's own chord follows it.
Felt piano, soft strings and drums in a hall: low, soft, nothing high or electronic. Seeded from each name.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import (env, felt_piano, finish, finish_loop, lp, n_, peak, pink, place, reverb, rng_for, strike, t_,  # noqa
                     warm_pad, write)

HERE = pathlib.Path(__file__).resolve().parent
ENDINGS = HERE / "endings"
LOOP = 16.0  # seconds a bed loops over
OVER = 2.0   # seconds of overlap the loop is made seamless across


def note(name):
    names = {"C": -9, "C#": -8, "Db": -8, "D": -7, "Eb": -6, "E": -5, "F": -4, "F#": -3, "Gb": -3, "G": -2, "Ab": -1,
             "A": 0, "Bb": 1, "B": 2}
    letter, octave = name[:-1], int(name[-1])
    return 440.0 * 2 ** ((names[letter] + 12 * (octave - 4)) / 12)


def bed(rng, pedal, pad, figure, beat, velocity, pulse=None, pulse_every=2, breath=0.0):
    """A low string pedal, a pad over it, a felt-piano figure going round, and (if any) a soft low pulse."""
    total = LOOP + OVER + 1.0
    t = t_(total)
    low = warm_pad([note(n) for n in pedal], total, rng, attack=1.2, release=1.5, brightness=0.25)
    high = warm_pad([note(n) for n in pad], total, rng, attack=2.0, release=2.0, brightness=0.32)
    if breath:
        high = high * (1 - breath * 0.5 * (1 - np.cos(2 * np.pi * t / 8.0)))
    layers = [(0.0, 1.0, peak(low)), (0.0, 0.55, peak(high))]
    steps = int(total / beat)
    for k in range(steps):
        f = note(figure[k % len(figure)])
        v = velocity * (1.0 if k % len(figure) == 0 else 0.8) * rng.uniform(0.9, 1.05)
        layers.append((max(0.0, k * beat + rng.uniform(-0.006, 0.006)), 0.45, peak(felt_piano(f, beat * 2.2, rng, v))))
    if pulse:
        for k in range(0, steps, pulse_every):
            thump = strike(0.6, [note(pulse), note(pulse) * 1.5], [0.35, 0.15], [1, 0.3], rng, hardness=0.15)
            layers.append((k * beat, 0.5, peak(thump)))
    x = place(total, layers)
    x = reverb(x, "hall", rng, wet=0.35)[:n_(total)]
    return lp(x, 3200)


def shore_loop(rng):
    return bed(rng, ["D2", "A2"], ["F3", "A3", "D4"], ["A3", "D4", "F4", "A4", "G4", "F4", "E4", "D4"], 0.62, 0.32)


def sunken_loop(rng):
    return bed(rng, ["C2", "G2"], ["Gb3", "C4", "Eb4"], ["C4", "Gb4", "Eb4", "D4"], 1.0, 0.26, pulse="C2", pulse_every=2,
               breath=0.4)


def halls_loop(rng):
    return bed(rng, ["B1", "F#2"], ["B3", "C4", "F#4"], ["B3", "C4", "B3", "A3"], 1.0, 0.24, pulse="B1", pulse_every=1,
               breath=0.6)


def hill_loop(rng):
    return bed(rng, ["F2", "C3"], ["Bb3", "C4", "F4"], ["F4", "C4", "Bb3", "C4", "A3", "C4", "Bb3", "C4"], 0.7, 0.3)


def score_hit(rng):
    """The turn: a deep drum and a low boom under the strings struck together on an open chord, and a long tail."""
    d = 7.0
    t = t_(d)
    drum = strike(3.0, [note("A1"), note("A1") * 1.52, note("A1") * 2.3], [1.6, 0.8, 0.4], [1, 0.45, 0.2], rng,
                  hardness=0.35)
    boom = lp(pink(d, rng), 120) * env(t, 0.004, 1.2)
    stab = warm_pad([note(n) for n in ("A2", "E3", "A3", "B3", "E4")], d, rng, attack=0.04, release=4.0, brightness=0.4)
    piano = place(d, [(0.0, 1.0, felt_piano(note(n), 6.0, rng, 0.5)) for n in ("A1", "A2", "E3")])
    x = place(d, [(0.0, 1.0, peak(drum)), (0.0, 0.6, peak(boom)), (0.02, 0.8, peak(stab)), (0.0, 0.55, peak(piano))])
    x = reverb(x, "hall", rng, wet=0.4)[:n_(d)]
    return finish(x, -15.0, high_cut=4000, fade_out=2.5)


LOOPS = [("ShoreScoreLoop", shore_loop, -24.0), ("SunkenScoreLoop", sunken_loop, -24.0),
         ("HallsScoreLoop", halls_loop, -24.0), ("HillScoreLoop", hill_loop, -24.0)]

if __name__ == "__main__":
    only = set(sys.argv[1:])
    for name, make, level in LOOPS:
        if not only or name in only:
            print(write(ENDINGS / ("%s.wav" % name), finish_loop(make(rng_for(name, 21100)), LOOP, OVER, level)))
    if not only or "ScoreHit" in only:
        print(write(ENDINGS / "ScoreHit.wav", score_hit(rng_for("ScoreHit", 21100))))
