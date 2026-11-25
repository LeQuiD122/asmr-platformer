"""The sound of every press in the game's menus (the hundred-and-forty-fourth pass: "keep polishing").

    python audio/gen_ui_sfx.py

Writes audio/shop/UiTaps_x8.wav, for the Folder SoundService.ShopSounds: eight takes, each in its own slot (SLOTS), played
one at a time by AudioService.press (its PRESSES name these slots, from 0):

  1-4  tap      a press: a felt-tipped tap on a small wooden box with a cushion in it, four ways (lower, higher, the
                cushion first and the knock a breath after, a tap that settles with a second, smaller one)
  5    open     a card coming up: two felt piano notes, G then the D above it
  6    close    a card going away: the same two notes, down
  7    good     something good (bought, found, earned): a soft bubble and a marimba note after it
  8    no       not now (too dear, not yet): two low knocks, the second softer

Soft and low (the sound taste: low to mid, soft attacks, nothing shrill, never a ping): every press the menus made was the
engine's electronic ping an octave up, which is the one sound the game was never to make. Seeded: re-running writes the
same file.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import (bubble, env, felt_piano, finish, lp, n_, peak, place, reverb, rng_for, strike, t_,  # noqa: E402
                     white, wood_bar, write_sheet)

OUT = pathlib.Path(__file__).resolve().parent / "shop"
# The sheet's slot, in seconds: AudioService has the same number, PRESS_SLOT (check_audio.py holds them to it).
SLOTS = {"UiTaps": 0.8}


def cushion(rng, seconds=0.05, top=1100):
    """The pad under the finger: a short soft hush, all low."""
    return peak(lp(white(seconds, rng), top)) * env(t_(seconds), 0.0015, 0.008)


def tap(take, rng):
    """One press. The four differ in what happens, not only in pitch, so no two sound like copies."""
    if take == 0:  # lower: a hollow knock, the box's body
        knock = strike(0.4, [262, 610, 1180], [0.07, 0.03, 0.012], [1.0, 0.3, 0.08], rng, hardness=0.2)
        layers = [(0.0, 0.35, cushion(rng)), (0.004, 1.0, peak(knock))]
    elif take == 1:  # higher and shorter: the lid's edge
        knock = strike(0.3, [348, 905, 1640], [0.045, 0.02, 0.01], [1.0, 0.25, 0.07], rng, hardness=0.25)
        layers = [(0.0, 0.25, cushion(rng, 0.03)), (0.002, 1.0, peak(knock))]
    elif take == 2:  # the cushion first, the knock a breath after: a slow press
        knock = strike(0.4, [295, 700, 1350], [0.06, 0.025, 0.01], [1.0, 0.28, 0.07], rng, hardness=0.15)
        layers = [(0.0, 0.6, cushion(rng, 0.09, 900)), (0.03, 0.85, peak(knock))]
    else:  # a tap that settles: a second, smaller one after it
        knock = strike(0.35, [318, 760, 1480], [0.05, 0.022, 0.01], [1.0, 0.28, 0.07], rng, hardness=0.22)
        again = strike(0.3, [324, 770], [0.035, 0.015], [1.0, 0.2], rng, hardness=0.18)
        layers = [(0.0, 0.3, cushion(rng)), (0.003, 1.0, peak(knock)), (0.062, 0.32, peak(again))]
    x = place(0.6, layers)
    x = reverb(x, "small", rng, wet=0.14)[:n_(0.7)]
    return finish(x, -25.0, low_cut=90, high_cut=3200, fade_out=0.12)


def two_notes(first, second, rng, velocity, level):
    a = felt_piano(first, 0.7, rng, velocity=velocity)
    b = felt_piano(second, 0.62, rng, velocity=velocity * 0.85)
    x = place(0.72, [(0.0, 1.0, peak(a)), (0.085, 0.8, peak(b))])
    x = reverb(x, "small", rng, wet=0.18)[:n_(0.74)]
    return finish(x, level, low_cut=80, high_cut=3000, fade_out=0.28)


def good(rng):
    pop = bubble(430, rng, xi=0.16, seconds=0.12)
    note = wood_bar(392.0, 0.62, rng, velocity=0.3)
    x = place(0.72, [(0.0, 0.7, peak(pop)), (0.05, 1.0, peak(note))])
    x = reverb(x, "small", rng, wet=0.16)[:n_(0.74)]
    return finish(x, -23.0, low_cut=90, high_cut=3200, fade_out=0.25)


def no(rng):
    first = strike(0.3, [178, 410, 830], [0.06, 0.025, 0.01], [1.0, 0.25, 0.06], rng, hardness=0.12)
    second = strike(0.3, [168, 392, 800], [0.05, 0.02, 0.01], [1.0, 0.22, 0.05], rng, hardness=0.1)
    x = place(0.6, [(0.0, 0.3, cushion(rng)), (0.004, 1.0, peak(first)), (0.13, 0.62, peak(second))])
    x = reverb(x, "small", rng, wet=0.12)[:n_(0.7)]
    return finish(x, -26.0, low_cut=70, high_cut=2600, fade_out=0.15)


if __name__ == "__main__":
    takes = [tap(k, rng_for("UiTap", k)) for k in range(4)]
    takes.append(two_notes(196.0, 293.66, rng_for("UiOpen"), 0.32, -24.0))
    takes.append(two_notes(293.66, 196.0, rng_for("UiClose"), 0.28, -25.0))
    takes.append(good(rng_for("UiGood")))
    takes.append(no(rng_for("UiNo")))
    print(write_sheet(OUT / "UiTaps_x8.wav", takes, SLOTS["UiTaps"]))
