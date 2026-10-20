"""The lobby's own sound (the ninety-sixth pass): the sea far below, the fountain, the wind, chimes and a buoy far off.

    python audio/gen_lobby_sfx.py

Writes audio/lobby/, for a Folder SoundService.LobbySounds: SEVEN files. Every sound in the lobby was the engine's one
splash (impact_water.mp3) at a different pitch, the sea, the wind, the breakers and the fountain alike, and in play it
was "too repetitive". Nothing here is a loop of one sample: the beds are long and seamless, and over them the client
(AmbienceService) plays single takes at random gaps, pitches, loudness and places, never one of the last two again,
so no two minutes in the lobby sound the same. The single takes come as SHEETS, many takes in one file, played by slot
(so 7 files to import, not 28):

    SeaBed_1, _2           30 s each, seamless: the open sea a long way below the deck, its swell breathing, waves
                           breaking somewhere along the shore all the time, softly
    FountainBed            16 s, seamless: the jets falling into the basin, thousands of drops, the water churning
    Surf_x8                eight waves (9 s slots), each breaking far below and fizzing back out, its own size
    FountainSplash_x10     ten (1.5 s slots), five kinds: a plop, a plink, a spill over the lip, a run of drops
                           slowing, a gurgle
    WindGust_x5            five soft gusts over the deck (9 s slots), each with its own rise and fall
    BuoyBell_x2            a bell on a buoy out to sea, rung once or twice by the swell, far off (7.5 s slots)

(The garden's wind chimes, chime() below, wait for the promenade's quiet garden.)

Soft, low and warm (the lobby is where you rest): little above 6 kHz, nothing pitched up. Made of the same parts as
every sound since this pass (`sfx_kit.py`): the water is bubbles and drops, as real water is.
Seeded, so re-running writes the same files.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import (SR, beach_wave, bell, bp, brown, bubble, bubbles, drift, droplet, env, fade, finish,  # noqa
                     finish_loop, hp, lp,
                     match, modal, n_, peak, pink, place, reverb, reverb_loop, rng_for, sculpted, seamless, splash,
                     strike, swell, t_, white, write, write_sheet)

OUT = pathlib.Path(__file__).resolve().parent / "lobby"


def add(out, x, at, gain=1.0):
    a = n_(at)
    if a < len(out):
        b = min(len(out), a + len(x))
        out[a:b] += gain * x[:b - a]


# ----- the sea -----
def sea_bed(rng, seconds=30.0, overlap=4.0):
    total = seconds + overlap
    t = t_(total)
    swell_ = np.zeros(len(t))
    for period in rng.uniform(6.5, 12.5, 4):
        swell_ += (0.5 + 0.5 * np.sin(2 * np.pi * t / period + rng.uniform(0, 6))) ** 2
    swell_ /= swell_.max()

    def shape(times, freqs):
        s = np.interp(times, t, swell_)
        return (1 / (1 + (freqs / (260 + 260 * s)) ** 2.4)) * (freqs > 45) * (0.45 + 0.55 * s)
    body = sculpted(total, rng, shape)
    shore = np.zeros(len(t))
    at = rng.uniform(0, 2)
    while at < total:
        add(shore, lp(beach_wave(rng), 1600, order=4), at, rng.uniform(0.2, 0.5))
        at += rng.uniform(2.5, 5.0)
    x = peak(body) + 0.6 * peak(shore)
    x = reverb_loop(x, "open", rng, wet=0.25)
    return finish_loop(x, seconds, overlap, -23.0, low_cut=35, high_cut=3200)


def surf(rng):
    size = rng.uniform(0.6, 1.0)
    x = beach_wave(rng, seconds=rng.uniform(5.5, 7.5), size=size)
    x = reverb(lp(x, 3000, order=4), "open", rng, wet=0.3)
    return finish(x, rng.uniform(-22.0, -19.5), high_cut=3600, fade_in=0.05, fade_out=0.6)


# ----- the fountain -----
def fountain_bed(rng, seconds=16.0, overlap=3.0):
    total = seconds + overlap
    t = t_(total)
    curtain = np.zeros(n_(total))
    count = int(total * 380)
    for when in rng.uniform(0, total - 0.05, count):
        d = droplet(rng, size=rng.uniform(0.7, 2.2), xi=(0.05, 0.3), pitch=(900, 3200))
        add(curtain, d, when, rng.uniform(0.05, 0.4))
    under = bubbles(total, rng, 600 * (0.85 + 0.15 * drift(total, rng, rate=0.4)), r_mm=(1.0, 6.0), beta=2.3,
                    xi=(0.03, 0.2))

    def shape(times, freqs):
        return 1 / (1 + (freqs / 1400) ** 2) * (freqs > 150)
    churn = sculpted(total, rng, shape) * (0.8 + 0.2 * drift(total, rng, rate=0.27))
    x = 0.8 * peak(curtain) + 0.45 * peak(lp(under, 2500)) + 0.5 * peak(churn) + 0.15 * peak(lp(brown(total, rng), 160))
    x = reverb_loop(x, "open", rng, wet=0.2)
    return finish_loop(x, seconds, overlap, -22.0, low_cut=35, high_cut=6000)


def fountain_splash(take, rng):
    kind = take % 5
    seconds = {0: 0.6, 1: 0.45, 2: 1.4, 3: 1.1, 4: 0.9}[kind]
    x = np.zeros(n_(seconds))
    if kind == 0:  # a plop: something heavier into the basin, a low round bubble
        add(x, splash(rng, size=0.35, seconds=0.5), 0.0, 0.6)
        add(x, bubble(rng.uniform(320, 520), rng, xi=0.2), 0.004, 1.0)
    elif kind == 1:  # a plink: one drop, small and clear, not high
        add(x, droplet(rng, size=rng.uniform(1.1, 1.6), xi=(0.2, 0.4), pitch=(1000, 1600)), 0.0, 1.0)
    elif kind == 2:  # a spill over the lip: a short pour, its drops in it
        t = t_(seconds)
        pour = bubbles(seconds, rng, 1400 * np.interp(t, [0, 0.12, 0.9, seconds], [0, 1, 0.6, 0]), r_mm=(0.6, 3.5),
                       beta=2.4, xi=(0.03, 0.2))
        add(x, peak(pour), 0.0, 0.8)
        for when in rng.uniform(0.1, seconds - 0.15, 14):
            add(x, droplet(rng, size=rng.uniform(0.8, 1.8)), when, rng.uniform(0.1, 0.3))
    elif kind == 3:  # a run of drops, slowing, as a jet catches and lets go
        when, gap = 0.0, rng.uniform(0.05, 0.08)
        while when < seconds - 0.25:
            add(x, droplet(rng, size=rng.uniform(0.9, 1.5)), when, rng.uniform(0.5, 1.0))
            when += gap
            gap *= rng.uniform(1.2, 1.45)
    else:  # a gurgle: a few low bubbles in a hurry, air caught under the basin's lip
        times = np.sort(rng.uniform(0, 0.5, 5))
        for when in times - times[0]:
            add(x, bubble(rng.uniform(220, 420), rng, xi=rng.uniform(0.1, 0.3)), when, rng.uniform(0.5, 1.0))
    x = reverb(x, "open", rng, wet=0.2)[:n_(seconds)]
    return finish(x, rng.uniform(-23.5, -20.5), high_cut=5200, fade_in=0.0005, fade_out=0.05)


# ----- the wind -----
def wind_gust(rng):
    seconds = rng.uniform(5.0, 8.5)
    t = t_(seconds)
    peak_at = rng.uniform(0.35, 0.6) * seconds
    strength = np.exp(-((t - peak_at) / (seconds * 0.28)) ** 2) * (0.85 + 0.15 * drift(seconds, rng, rate=3))

    def shape(times, freqs):
        s = np.interp(times, t, strength)
        centre = 240 + 520 * s
        return (1 / (1 + (freqs / centre) ** 2.4)) * (1 / (1 + (60 / np.maximum(freqs, 1)) ** 2)) * (0.1 + s)
    x = sculpted(seconds, rng, shape)
    return finish(x, rng.uniform(-26.0, -23.0), high_cut=2600, fade_in=0.3, fade_out=0.4)


# ----- the chimes and the bell -----
def chime(freq, rng):
    """A metal tube struck softly: a free bar's partials (1, 2.76, 5.40, 8.93), the fundamental ringing longest, each a
    pair a hair apart so it shimmers as it dies."""
    seconds = 4.5
    x = strike(seconds, [freq, freq * 2.76, freq * 5.40, freq * 8.93], [3.2, 1.6, 0.7, 0.3], [1.0, 0.45, 0.16, 0.05],
               rng, hardness=0.35, detune=0.002)
    x += strike(seconds, [freq * 1.0015, freq * 2.763], [3.0, 1.4], [0.6, 0.25], rng, hardness=0.35)
    x = reverb(x, "open", rng, wet=0.25)[:n_(seconds)]
    return finish(x, -22.0, high_cut=7000, fade_out=0.4)


def buoy_bell(rng):
    seconds = 7.0
    f = rng.uniform(370, 420)
    x = place(seconds, [(0.0, 1.0, bell(f, seconds, rng, t60=4.5, hardness=0.4)),
                        (rng.uniform(1.6, 2.4), 0.65, bell(f, seconds - 2.4, rng, t60=4.0, hardness=0.3))])
    x = reverb(lp(x, 1600, order=4), "harbour", rng, wet=0.45)[:n_(seconds)]
    return finish(x, -27.0, high_cut=1800, fade_out=0.6)


# Each sheet's slot, in seconds: AmbienceService.LOBBY has the same numbers (check_audio.py holds them to it).
SLOTS = {"Surf": 9.0, "FountainSplash": 1.5, "WindGust": 9.0, "BuoyBell": 7.5}

if __name__ == "__main__":
    rng = rng_for("LobbySounds", 9500)
    for k in (1, 2):
        print(write(OUT / ("SeaBed_%d.wav" % k), sea_bed(rng)))
    print(write(OUT / "FountainBed.wav", fountain_bed(rng)))
    print(write_sheet(OUT / "Surf_x8.wav", [surf(rng) for _ in range(8)], SLOTS["Surf"]))
    print(write_sheet(OUT / "FountainSplash_x10.wav", [fountain_splash(k, rng) for k in range(1, 11)], SLOTS["FountainSplash"]))
    print(write_sheet(OUT / "WindGust_x5.wav", [wind_gust(rng) for _ in range(5)], SLOTS["WindGust"]))
    print(write_sheet(OUT / "BuoyBell_x2.wav", [buoy_bell(rng) for _ in range(2)], SLOTS["BuoyBell"]))
