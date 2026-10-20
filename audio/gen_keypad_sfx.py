"""The keypad's sounds, remade (the ninety-sixth pass): arcade buttons you want to press again.

They were "electric, a little explosive, futuristic": FM zaps, pews and a power-up, the one corner of the game that
sounded like a different game. Now they are what the chunk is: big arcade buttons and creamy keys, and what each
does for you is said in something you could find in a room, never a zap.

  button_clicky_x4     buttonClick    cyan, the fast lane: the arcade microswitch's crisp snap and the cap bottoming
                                      out, with a soft rush of air going past (the speed it gives you)
  button_linear_x3     buttonLinear   violet, a charge kept: a smooth key sinking to a deep, creamy thock, and one
                                      low wooden note held for you (a different one each take, all in one key)
  button_tactile_x3    buttonTactile  pink, a higher jump: the bump in the key's travel, then a rubbery, springy
                                      bounce under the foot
  button_release_x3    buttonRelease  any switch coming back up: the lighter click and the cap tapping its bezel
  button_combo_1, _2   buttonCombo    three in a row: three clicks and the wooden bars running up a chord
  button_circuit_1, _2 buttonCircuit  the whole lane: a run of buttons going down like dominoes, landing on a warm
                                      chord (piano and bars) with a soft low thump under it

The four short ones are SHEETS (gen_sheet_sfx.py imports their makers and writes audio/sheets/button_*_xN.wav: every
take in one upload, AudioService playing each from its own one-second slot); the combo and the circuit are longer than
a slot, so this file writes them, to audio/buttons/. Each at the old one's loudness; for SoundService.MaterialSounds.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import (SR, bp, brown, drift, env, fade, felt_piano, finish, hp, lp, modal, n_, peak, place,  # noqa: E402
                     reverb, rng_for, sculpted, strike, t_, white, wood_bar, write)

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "buttons"

LEVELS = {"button_clicky": -15.0, "button_linear": -15.5, "button_tactile": -14.5, "button_release": -15.0,
          "button_combo": -15.8, "button_circuit": -16.5}

# One key for every note the keypad plays: D major pentatonic, low and warm.
PENTA = [146.8, 164.8, 185.0, 220.0, 246.9, 293.7, 329.6, 370.0, 440.0]


def snap(rng, brightness=1.0):
    """An arcade microswitch: its leaf spring snapping over (a tiny, very short metal ring), in its plastic box."""
    leaf = strike(0.03, [rng.uniform(3600, 4300), rng.uniform(5600, 6400)], [0.006, 0.004], [1.0, 0.5], rng, 0.95)
    box = strike(0.05, [rng.uniform(1500, 1800), rng.uniform(2500, 2900)], [0.012, 0.008], [1.0, 0.5], rng, 0.8)
    tick = hp(white(0.004, rng), 3000) * np.exp(-t_(0.004) / 0.0006)
    return place(0.05, [(0.0, 0.5 * brightness, peak(leaf)), (0.0, 1.0, peak(box)), (0.0, 0.4 * brightness, peak(tick))])


def bottom(rng, low=1.0):
    """The cap landing on the bottom of its housing: a plastic body, hollow, quickly damped (the thock)."""
    f = [rng.uniform(380, 460) * low, rng.uniform(820, 960) * low, rng.uniform(1500, 1700)]
    return strike(0.12, f, [0.045, 0.03, 0.015], [1.0, 0.55, 0.2], rng, hardness=0.45)


def thock(rng):
    """A creamy key: a smooth slide, no click, ending on a deep rounded thock (a big case, a soft plate)."""
    body = strike(0.2, [rng.uniform(210, 250), rng.uniform(470, 530), rng.uniform(980, 1100)],
                  [0.08, 0.05, 0.025], [1.0, 0.45, 0.15], rng, hardness=0.3)
    slide = lp(bp(white(0.05, rng), 500, 2500), 2600) * env(t_(0.05), 0.02, 0.01)
    return place(0.2, [(0.0, 0.12, peak(slide)), (0.035, 1.0, peak(body))])


def rush(seconds, rng, rise=True):
    """A soft rush of air going past, brightening as it comes (no tone in it)."""
    t = t_(seconds)
    k = np.clip(t / seconds, 0, 1)

    def shape(times, freqs):
        kk = np.clip(times / seconds, 0, 1)
        centre = 500 + (1600 if rise else 900) * kk
        return 1 / (1 + (freqs / centre) ** 2.4) * (freqs > 120)
    return sculpted(seconds, rng, shape) * np.sin(np.pi * k) ** 1.5


def clicky(take, rng):
    d = 0.42
    layers = [(0.0, 1.0, peak(snap(rng))), (0.008, 0.85, peak(bottom(rng))),
              (0.01, 0.35, peak(rush(0.32, rng))),
              (0.006, 0.4, peak(lp(brown(0.2, rng), 160) * env(t_(0.2), 0.004, 0.04)))]
    if take == 3:
        layers.append((0.004, 0.5, peak(snap(rng, 0.6))))  # a double snap: the leaf catching twice
    x = reverb(place(d, layers), "small", rng, wet=0.12)[:n_(d)]
    return finish(x, LEVELS["button_clicky"], high_cut=8000, fade_out=0.05)


def linear(take, rng):
    d = 0.34
    note = [PENTA[0], PENTA[2], PENTA[3]][take - 1]
    held = wood_bar(note * 2, 0.3, rng, velocity=0.4, t60s=(0.32, 0.12, 0.05))
    x = place(d, [(0.0, 1.0, peak(thock(rng))), (0.045, 0.3, peak(held))])
    x = reverb(x, "small", rng, wet=0.15)[:n_(d)]
    return finish(x, LEVELS["button_linear"], high_cut=6000, fade_out=0.08)


def tactile(take, rng):
    d = 0.36
    bump = strike(0.03, [rng.uniform(2200, 2600)], [0.008], [1.0], rng, 0.7)
    # The spring under it: a rubber dome giving back, a soft bounce whose pitch drops as it settles.
    t = t_(0.25)
    f = rng.uniform(150, 180) * (1 + 0.15 * np.exp(-t / 0.02))
    bounce = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(t, 0.003, 0.022)
    bounce = lp(0.7 * bounce + lp(white(0.25, rng), 500) * env(t, 0.002, 0.03), 1200)
    x = place(d, [(0.0, 0.5, peak(bump)), (0.022, 0.9, peak(bottom(rng, low=0.85))), (0.03, 0.8, peak(bounce))])
    x = reverb(x, "small", rng, wet=0.12)[:n_(d)]
    return finish(x, LEVELS["button_tactile"], high_cut=7000, fade_out=0.06)


def release(take, rng):
    d = 0.15
    up = snap(rng, brightness=0.6)
    bezel = strike(0.06, [rng.uniform(1900, 2300), rng.uniform(3300, 3800)], [0.012, 0.008], [1.0, 0.4], rng, 0.6)
    x = place(d, [(0.0, 0.7, peak(up)), (0.012, 0.6, peak(bezel))])
    return finish(x, LEVELS["button_release"], high_cut=8000, fade_out=0.03)


def combo(take, rng):
    d = 1.05
    layers = []
    for k in range(3):
        layers.append((0.07 * k, 0.8, peak(place(0.15, [(0.0, 1.0, snap(rng)), (0.008, 0.8, bottom(rng))]))))
    notes = [PENTA[3], PENTA[5], PENTA[6], PENTA[8]] if take == 1 else [PENTA[2], PENTA[4], PENTA[5], PENTA[7]]
    for k, f in enumerate(notes):
        layers.append((0.24 + 0.075 * k, 0.5 - 0.05 * k, peak(wood_bar(f * 2, 0.8, rng, velocity=0.45))))
    x = reverb(place(d, layers), "hall", rng, wet=0.25)[:n_(d)]
    return finish(x, LEVELS["button_combo"], high_cut=7000, fade_out=0.2)


def circuit(take, rng):
    d = 1.5
    layers = []
    at, gap = 0.0, 0.055
    for k in range(9):
        layers.append((at, 0.45 + 0.04 * k, peak(place(0.15, [(0.0, 1.0, snap(rng, 0.8)), (0.006, 0.8, bottom(rng))]))))
        at += gap
        gap *= 0.9
    land = at + 0.04
    chord = [PENTA[0], PENTA[3], PENTA[5], PENTA[6]] if take == 1 else [PENTA[1], PENTA[3], PENTA[4], PENTA[7]]
    for k, f in enumerate(chord):
        layers.append((land + 0.02 * k, 0.45, peak(felt_piano(f, d - land, rng, velocity=0.45))))
        layers.append((land + 0.02 * k + 0.01, 0.2, peak(wood_bar(f * 2, d - land, rng, velocity=0.35))))
    layers.append((land, 0.6, peak(lp(brown(0.4, rng), 140) * env(t_(0.4), 0.006, 0.09))))
    x = reverb(place(d, layers), "hall", rng, wet=0.25)[:n_(d)]
    return finish(x, LEVELS["button_circuit"], high_cut=7000, fade_out=0.3)


# Sheets (gen_sheet_sfx.py writes these): each take under a second.
SHEETS = [("button_clicky", clicky, 4), ("button_linear", linear, 3), ("button_tactile", tactile, 3),
          ("button_release", release, 3)]
# Files of their own (here): longer than a sheet's slot.
EVENTS = [("button_combo", combo, 2), ("button_circuit", circuit, 2)]

if __name__ == "__main__":
    only = set(sys.argv[1:])
    for stem, make, takes in EVENTS:
        if only and stem not in only:
            continue
        for take in range(1, takes + 1):
            print(write(OUT / ("%s_%d.wav" % (stem, take)), make(take, rng_for(stem, 9500 + take))))
