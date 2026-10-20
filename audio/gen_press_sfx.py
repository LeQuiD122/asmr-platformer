"""The lobby's presses and the leaderboard's lever (the hundred-and-first pass).

    python audio/gen_press_sfx.py

Writes audio/lobby/, into the same Folder as the lobby's own sound (SoundService.LobbySounds): SEVEN sheets, several
takes in each, played one slot at a time at the thing pressed (AmbienceService.press, HubLeverService), so you hear
them from where they are and not from across the promenade:

    PadPress_x4        a level pad: a soft stone thock under your weight, and a note from the window above it
    KeyPress_x4        a mode or length key: a round arcade key going down, its spring, and coming back up
    PosePress_x4       a pose key: two quick notes on a wooden toy xylophone, a different pair each
    StartPress_x2      the start pad: a big plunger going home, a latch, and a warm chord rising out of it
    LockedPress_x2     a locked pad: a dull knock on the boards across its window
    LeverHardcore_x2   the lever thrown to Hardcore: a ratchet cranked down notch by notch, a heavy iron clunk, a
                       low boom under it
    LeverChill_x2      the lever thrown to Chill: a light wooden click-clack and two soft notes going down

Soft, low and warm, as the game's sounds are (little above 5 kHz, nothing pitched up); the lever's Hardcore is the
one dramatic sound here, and it is dramatic by being deep, not by being loud. Seeded: re-running writes the same files.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import (SR, bp, env, felt_piano, finish, hp, lp, modal, n_, peak, place, reverb, rng_for,  # noqa
                     strike, t_, white, wood_bar, write_sheet)

OUT = pathlib.Path(__file__).resolve().parent / "lobby"

# Each sheet's slot, in seconds: AmbienceService.PRESSES and HubLeverService.LEVER have the same numbers (check_audio.py
# holds them to it).
SLOTS = {"PadPress": 1.4, "KeyPress": 0.8, "PosePress": 1.2, "StartPress": 2.6, "LockedPress": 1.0,
         "LeverHardcore": 3.2, "LeverChill": 1.6}


def add(out, x, at, gain=1.0):
    """x into out at `at` seconds, its last 60 ms tapered to nothing: a part that ends where its array ends would
    otherwise stop dead mid-ring, and a stop is a click."""
    x = np.array(x, dtype=float)
    k = min(len(x), n_(0.06))
    if k > 1:
        x[-k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    a = n_(at)
    if a < len(out):
        b = min(len(out), a + len(x))
        out[a:b] += gain * x[:b - a]


def thock(rng, f=150.0, seconds=0.5, hard=0.3):
    """A soft heavy press: a low body ringing briefly, the felt-damped hit on top."""
    body = strike(seconds, [f, f * 2.31, f * 4.1, f * 6.6], [0.28, 0.12, 0.06, 0.03], [1.0, 0.5, 0.22, 0.08], rng,
                  hardness=hard, detune=0.01)
    knock = lp(white(0.03, rng), 1400) * env(t_(0.03), 0.0005, 0.007)
    return place(seconds, [(0.0, 1.0, peak(body)), (0.0, 0.35, peak(knock))])


def click(rng, centre=2200.0, seconds=0.05, level=1.0):
    """A small hard click: a burst of band-passed noise a few milliseconds long, and the part it hits ringing."""
    t = t_(seconds)
    burst = bp(white(seconds, rng), centre * 0.5, centre * 1.6) * env(t, 0.0003, 0.004)
    ring = modal(seconds, [centre * 0.62, centre * 1.31], [0.025, 0.012], [0.6, 0.25], rng)
    return level * (0.7 * peak(burst) + 0.3 * peak(ring))


# ----- the level pad -----
PAD_NOTES = [392.0, 440.0, 523.25, 587.33]  # G4 A4 C5 D5: the window's note, one per take


def pad_press(take, rng):
    seconds = 1.2
    x = np.zeros(n_(seconds))
    add(x, thock(rng, f=rng.uniform(120, 150), seconds=0.6, hard=0.2), 0.0, 1.0)
    add(x, lp(white(0.12, rng), 600) * env(t_(0.12), 0.002, 0.05), 0.0, 0.18)  # stone settling
    note = wood_bar(PAD_NOTES[take % len(PAD_NOTES)], 1.0, rng, velocity=0.35)
    add(x, peak(note), rng.uniform(0.03, 0.05), 0.22)
    x = reverb(x, "open", rng, wet=0.22)[:n_(seconds)]
    return finish(x, rng.uniform(-22.0, -20.5), high_cut=4200, fade_out=0.15)


# ----- the mode and length keys -----
def key_press(take, rng):
    seconds = 0.7
    x = np.zeros(n_(seconds))
    add(x, click(rng, centre=rng.uniform(1500, 2100), level=0.8), 0.0)
    add(x, thock(rng, f=rng.uniform(220, 280), seconds=0.25, hard=0.45), 0.004, 0.9)  # the cap bottoming out
    t = t_(0.18)
    spring = np.sin(2 * np.pi * np.cumsum(np.linspace(190, 150, len(t))) / SR) * env(t, 0.002, 0.07)
    add(x, spring, 0.006, 0.12)
    add(x, click(rng, centre=rng.uniform(1700, 2300), level=0.45), rng.uniform(0.11, 0.16))  # and back up
    x = reverb(x, "small", rng, wet=0.18)[:n_(seconds)]
    return finish(x, rng.uniform(-22.0, -20.0), high_cut=4500, fade_out=0.1)


# ----- the pose keys -----
POSE_PAIRS = [(523.25, 659.25), (587.33, 783.99), (659.25, 523.25), (440.0, 587.33)]


def pose_press(take, rng):
    seconds = 1.1
    x = np.zeros(n_(seconds))
    a, b = POSE_PAIRS[take % len(POSE_PAIRS)]
    add(x, click(rng, centre=1400, level=0.35), 0.0)
    add(x, peak(wood_bar(a, 0.9, rng, velocity=0.45)), 0.005, 0.7)
    add(x, peak(wood_bar(b, 0.9, rng, velocity=0.4)), rng.uniform(0.09, 0.12), 0.6)
    x = reverb(x, "open", rng, wet=0.2)[:n_(seconds)]
    return finish(x, rng.uniform(-23.0, -21.0), high_cut=4500, fade_out=0.2)


# ----- the start pad -----
def start_press(take, rng):
    seconds = 2.4
    x = np.zeros(n_(seconds))
    add(x, thock(rng, f=rng.uniform(70, 85), seconds=0.9, hard=0.15), 0.0, 1.0)  # the plunger going home
    add(x, click(rng, centre=1300, level=0.5), 0.07)  # the latch
    root = [261.63, 293.66][take % 2]
    for k, ratio in enumerate([1.0, 1.25, 1.5, 2.0]):  # the chord rising out of it, one note after another
        add(x, peak(felt_piano(root * ratio, 2.1, rng, velocity=0.35)), 0.14 + k * 0.07, 0.3 - 0.03 * k)
    x = reverb(x, "hall", rng, wet=0.25)[:n_(seconds)]
    return finish(x, -19.5 + rng.uniform(-0.5, 0.5), high_cut=4200, fade_out=0.4)


# ----- a locked pad -----
def locked_press(take, rng):
    seconds = 0.9
    x = np.zeros(n_(seconds))
    for k, when in enumerate([0.0, rng.uniform(0.16, 0.2)]):
        wood = strike(0.4, [175, 410, 760], [0.12, 0.05, 0.025], [1.0, 0.4, 0.15], rng, hardness=0.3, detune=0.02)
        add(x, peak(wood), when, 1.0 - 0.35 * k)
    x = reverb(x, "small", rng, wet=0.2)[:n_(seconds)]
    return finish(x, rng.uniform(-24.0, -22.5), high_cut=3000, fade_out=0.1)


# ----- the lever -----
def lever_hardcore(take, rng):
    """Cranked down notch by notch, slowing as it goes, then the weight of it landing: a heavy iron clunk, and a low
    boom under it that you feel more than hear."""
    seconds = 3.0
    x = np.zeros(n_(seconds))
    when, gap = 0.0, rng.uniform(0.085, 0.1)
    notches = 5 + take
    for k in range(notches):
        f = rng.uniform(1100, 1300) * (1 - 0.04 * k)
        tick = strike(0.12, [f, f * 1.73, f * 2.6], [0.05, 0.03, 0.015], [1.0, 0.45, 0.2], rng, hardness=0.7)
        add(x, peak(tick), when, 0.32 + 0.04 * k)
        when += gap
        gap *= 1.13
    grind_len = when
    t = t_(grind_len)
    grind = bp(white(grind_len, rng), 180, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 26 * t) ** 2) * env(t, 0.05, grind_len)
    add(x, peak(grind), 0.0, 0.12)
    land = when + 0.04
    clunk = strike(1.6, [68, 104, 171, 262, 410], [0.9, 0.6, 0.35, 0.2, 0.1], [1.0, 0.7, 0.45, 0.25, 0.12], rng,
                   hardness=0.55, detune=0.01)
    add(x, peak(clunk), land, 1.0)
    tb = t_(2.2)
    boom = np.sin(2 * np.pi * 44 * tb) * env(tb, 0.01, 1.3) + 0.3 * np.sin(2 * np.pi * 66 * tb) * env(tb, 0.01, 0.8)
    add(x, boom, land, 0.55)
    x = reverb(x, "hall", rng, wet=0.3)[:n_(seconds)]
    return finish(x, rng.uniform(-18.5, -17.5), low_cut=28, high_cut=3200, fade_out=0.5)


def lever_chill(take, rng):
    """A light flick: a wooden click going over, a softer clack as it settles, and two soft notes going down."""
    seconds = 1.5
    x = np.zeros(n_(seconds))
    add(x, peak(strike(0.15, [880, 2050], [0.04, 0.02], [1.0, 0.4], rng, hardness=0.35)), 0.0, 0.7)
    add(x, peak(strike(0.15, [760, 1850], [0.04, 0.02], [1.0, 0.35], rng, hardness=0.3)), rng.uniform(0.09, 0.12), 0.5)
    hi, lo = [(659.25, 523.25), (587.33, 493.88)][take % 2]
    add(x, peak(wood_bar(hi, 1.2, rng, velocity=0.3)), 0.16, 0.32)
    add(x, peak(wood_bar(lo, 1.2, rng, velocity=0.28)), 0.32, 0.3)
    x = reverb(x, "open", rng, wet=0.25)[:n_(seconds)]
    return finish(x, rng.uniform(-23.5, -22.0), high_cut=4200, fade_out=0.3)


MAKERS = [("PadPress", pad_press, 4), ("KeyPress", key_press, 4), ("PosePress", pose_press, 4),
          ("StartPress", start_press, 2), ("LockedPress", locked_press, 2), ("LeverHardcore", lever_hardcore, 2),
          ("LeverChill", lever_chill, 2)]

if __name__ == "__main__":
    for name, make, count in MAKERS:
        rng = rng_for(name, 10100)
        print(write_sheet(OUT / ("%s_x%d.wav" % (name, count)), [make(k, rng) for k in range(count)], SLOTS[name]))
