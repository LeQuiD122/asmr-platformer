"""The levels' ambience beds, remade (the ninety-sixth pass): six seamless loops for SoundService.AmbienceSounds.

    python audio/gen_ambience_sfx.py               every one
    python audio/gen_ambience_sfx.py ShoreSea      only those named

Writes audio/ambience/<Name>.wav, the same six names, lengths and loudness as before, so each drops in for the old:

  ShoreSea      City Shore: the sea on the sands far below. Each wave its own: it gathers, breaks, and the fizz of it
                runs out over the sand and draws back. Never two alike.
  RoofWind      the Sky Pools: wind over a terrace high above the clouds, in gusts that come and go; no whistle.
  PartyFar      the party through a wall: a song you nearly know, its bass and its kick, and people talking, all of it
                muffled by the wall and a little seasick.
  HarbourNight  the Sunken City at eight minutes to midnight: water lapping at stone and knocking in a hollow under the
                quay, a mooring rope creaking, and a bell on a buoy far out, rung by the swell.
  BathsHum      the Flooded Halls: an old tube light's hum, air moving through tiled rooms, and drips in the dark,
                each landing in its own puddle, the tiles ringing with it.
  HoldDrone     the Hold, under every level: low strings that hardly move, beating slowly against each other, and
                far off, voices that never become words. Meant to be noticed only when it stops.

Seeded from each name, so re-running writes the same files.
"""
import pathlib
import sys

import numpy as np
from scipy import signal

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import (SR, beach_wave, bell, bp, brown, bubble, bubbles, drift, droplet, env, fade, felt_piano, finish_loop, hp, lp, match,  # noqa
                     modal, n_, peak, phase, pink, place, resonate, reverb, reverb_loop, rng_for, sculpted, seamless,
                     splash, strike, swell, t_, warm_pad, white, write)

HERE = pathlib.Path(__file__).resolve().parent
AMBIENCE = HERE / "ambience"

LEVELS = {"ShoreSea": -19.0, "RoofWind": -20.5, "PartyFar": -20.0, "HarbourNight": -24.3, "BathsHum": -21.0,
          "HoldDrone": -19.5, "HillMorning": -22.0}


def add(out, x, at, gain=1.0):
    a = n_(at)
    if a < len(out):
        b = min(len(out), a + len(x))
        out[a:b] += gain * x[:b - a]


def shore_sea(seconds, rng):
    out = 0.12 * lp(pink(seconds, rng), 420)
    # Further along the beach, other waves, softer and duller, breaking in their own time between the near ones.
    far = np.zeros(n_(seconds))
    at = rng.uniform(0, 3)
    while at < seconds:
        add(far, lp(beach_wave(rng), 1400, order=4), at, rng.uniform(0.25, 0.45))
        at += rng.uniform(3.0, 5.5)
    out += far
    at = rng.uniform(0, 2)
    while at < seconds:
        add(out, beach_wave(rng), at, rng.uniform(0.55, 1.0))
        at += rng.uniform(5.5, 9.0)
    out = lp(out, 3000, order=4)
    return reverb_loop(out, "open", rng, wet=0.3)


def roof_wind(seconds, rng):
    t = t_(seconds)
    gust = np.clip(0.45 + 0.4 * drift(seconds, rng, rate=0.18) + 0.15 * drift(seconds, rng, rate=0.9), 0.05, 1)

    def shape(times, freqs):
        g = np.interp(times, t, gust)
        centre = 220 + 900 * g
        return (1 / (1 + (freqs / centre) ** 2.2)) * (1 / (1 + (70 / np.maximum(freqs, 1)) ** 2)) * (0.2 + g)
    air = sculpted(seconds, rng, shape)
    # Something soft in it now and then: a parasol's canvas lifting and settling in the stronger gusts.
    flap = lp(bp(white(seconds, rng), 140, 800), 900) * (0.5 + 0.5 * np.sin(phase(6 + 5 * gust))) ** 4
    flap *= np.clip(gust - 0.6, 0, 1) * 2
    return peak(air) + 0.15 * peak(flap)


def babble(seconds, rng, voices=12):
    """People talking at once, too far to hear a word: voiced syllables at each one's own pitch and pace, vowels
    moving, pauses between phrases."""
    t = t_(seconds)
    out = np.zeros(n_(seconds))
    vowels = [(300, 870), (500, 1500), (700, 1100), (400, 2000), (650, 1700), (350, 900)]
    for _ in range(voices):
        f0 = rng.uniform(95, 230) * (1 + 0.06 * drift(seconds, rng, rate=2.5))
        ph = phase(f0)
        src = sum(np.sin(k * ph) / k for k in range(1, 18))
        syllables = 0.5 + 0.5 * np.sin(phase(np.full(len(t), rng.uniform(3.5, 5.5)) + 2 * drift(seconds, rng, rate=2)))
        phrases = (drift(seconds, rng, rate=0.5) > -0.2).astype(float)
        phrases = lp(phrases, 6)
        f1, f2 = vowels[rng.integers(len(vowels))]
        voice = resonate(src, [(f1, 1.0), (f2, 0.5)], q=5) * syllables ** 2 * phrases
        out += voice * rng.uniform(0.5, 1.0)
    return out


def party_far(seconds, rng):
    # 120 a minute: 32 beats in the 16 seconds, so the loop falls on the bar.
    beat = 0.5
    bars = [(110.0, 138.6, 164.8), (98.0, 123.5, 146.8), (87.3, 110.0, 130.8), (98.0, 123.5, 155.6)]
    t = t_(seconds + 2)
    music = np.zeros(len(t))
    for bar in range(int((seconds + 2) / (4 * beat)) + 1):
        root, third, fifth = bars[bar % 4]
        start = bar * 4 * beat
        for k in range(4):
            at = start + k * beat
            kick = strike(0.35, [55, 92], [0.18, 0.08], [1, 0.4], rng, hardness=0.3)
            add(music, kick, at, 0.9)
            if k in (1, 3):
                add(music, felt_piano(root * 2, 0.45, rng, 0.35) + felt_piano(third * 2, 0.45, rng, 0.3)
                    + felt_piano(fifth * 2, 0.45, rng, 0.3), at, 0.35)
            bass = felt_piano(root / 2 if k % 2 == 0 else root, beat * 0.95, rng, 0.5, strings=1)
            add(music, bass, at, 0.5)
    seasick = 1 + 0.004 * np.sin(2 * np.pi * 0.27 * t)
    idx = np.clip(np.cumsum(seasick) - 1, 0, len(music) - 1)
    music = np.interp(idx, np.arange(len(music)), music)
    talk = babble(seconds + 2, rng)
    x = peak(music) + 0.45 * peak(talk)
    # Through a wall: the top gone, the wall's own low resonance, and the room on the other side of it.
    x = lp(x, 520, order=4) + 0.4 * resonate(x, [(95, 1.0)], q=3)
    return reverb_loop(x, "small", rng, wet=0.3)


def harbour_night(seconds, rng):
    out = 0.15 * lp(pink(seconds, rng), 300)
    at = 0.1
    while at < seconds:
        lap = splash(rng, size=rng.uniform(0.18, 0.4), seconds=0.6)
        add(out, lp(lap, 1500, order=4), at, rng.uniform(0.15, 0.45))
        if rng.uniform() < 0.35:
            # Knocking in a hollow under the quay: water closing a pocket of air.
            add(out, bubble(rng.uniform(140, 230), rng, xi=0.08), at + rng.uniform(0.05, 0.3), rng.uniform(0.3, 0.6))
        at += rng.uniform(0.6, 1.8)
    # The mooring rope creaking as the boat rides the swell.
    at = rng.uniform(1, 4)
    while at < seconds - 1.5:
        d = rng.uniform(0.5, 1.1)
        taps = np.zeros(n_(d))
        i = 0
        while i < len(taps):
            taps[i] = rng.uniform(0.3, 1.0) * np.sin(np.pi * i / len(taps)) ** 2
            i += max(1, int(SR / rng.uniform(60, 110)))
        creak = signal.fftconvolve(taps, modal(0.2, [rng.uniform(420, 520), rng.uniform(900, 1100), 1650],
                                               [0.05, 0.035, 0.02], [1, 0.5, 0.2], rng))[:len(taps)]
        add(out, creak, at, 0.12)
        at += rng.uniform(4, 9)
    # The buoy's bell, far out: rung once or twice by each roll of the swell.
    at = rng.uniform(2, 5)
    while at < seconds:
        ring = peak(lp(bell(523.3, 6.0, rng, t60=4.0, hardness=0.4), 1800))
        add(out, ring, at, 0.06)
        if rng.uniform() < 0.5:
            add(out, peak(lp(bell(523.3, 5.0, rng, t60=4.0, hardness=0.3), 1800)), at + rng.uniform(0.6, 1.2), 0.035)
        at += rng.uniform(6, 11)
    return reverb_loop(out, "harbour", rng, wet=0.35)


def baths_hum(seconds, rng):
    t = t_(seconds)
    # A tube light: the ballast's hum at twice the mains, rough with harmonics, wavering; a faint buzz over it.
    ph = phase(np.full(n_(seconds), 100.0) * (1 + 0.001 * drift(seconds, rng, rate=0.2)))
    hum = sum(np.sin(k * ph + rng.uniform(0, 6)) / k ** 1.6 for k in range(1, 9))
    buzz = bp(np.sign(np.sin(ph)) + 0.3 * white(seconds, rng), 1800, 4500) * 0.04
    air = bp(pink(seconds, rng), 70, 700) * (0.8 + 0.2 * drift(seconds, rng, rate=0.15))
    drips = np.zeros(n_(seconds))
    at = rng.uniform(0.2, 1.0)
    while at < seconds - 0.3:
        add(drips, droplet(rng, size=rng.uniform(0.8, 1.4), xi=(0.1, 0.3), pitch=(700, 1900)), at, rng.uniform(0.3, 1.0))
        at += rng.uniform(0.9, 3.2)
    trickle = bubbles(seconds, rng, 120 * (0.6 + 0.4 * drift(seconds, rng, rate=0.3)), r_mm=(0.6, 3.0), beta=2.4,
                      xi=(0.03, 0.15))
    wet = reverb_loop(peak(drips) + 0.25 * peak(lp(trickle, 2500)), "tiles", rng, wet=0.6)
    return 0.2 * peak(lp(hum, 900)) + 0.06 * peak(buzz) + 0.6 * peak(air) + 0.7 * peak(wet)


def hold_drone(seconds, rng):
    t = t_(seconds)
    # Low strings, very dark, two of them a little apart so they beat slowly, the bow pressure wandering.
    strings = warm_pad([41.2, 61.7, 82.4], seconds, rng, attack=0.01, release=0.01, brightness=0.15, voices=4)
    strings2 = warm_pad([41.5, 82.9], seconds, rng, attack=0.01, release=0.01, brightness=0.1, voices=3)
    bow = 0.75 + 0.25 * drift(seconds, rng, rate=0.12)
    # Voices far off: breath through a mouth shaping vowels, slowly, never a word.
    f1 = 380 + 200 * drift(seconds, rng, rate=0.08)
    f2 = 900 + 500 * drift(seconds, rng, rate=0.06)

    def vowel(times, freqs):
        a = np.interp(times, t, f1)
        b = np.interp(times, t, f2)
        return 1 / (1 + ((freqs - a) / (a / 6)) ** 2) + 0.6 / (1 + ((freqs - b) / (b / 8)) ** 2)
    voices = sculpted(seconds, rng, vowel) * (0.5 + 0.5 * drift(seconds, rng, rate=0.05)) ** 3
    x = (peak(strings) + 0.6 * peak(strings2)) * bow + 0.12 * peak(voices)
    return reverb_loop(lp(x, 1400), "cavern", rng, wet=0.35)


def pigeon(rng):
    """A wood pigeon in the garden: hoo, HOO hoo, hoo hoo. A soft, breathy, low note, falling a little through each."""
    f0 = rng.uniform(430, 490)
    notes = [(0.32, 1.0, 0.7, 0.1), (0.5, 1.06, 1.0, 0.1), (0.28, 1.0, 0.6, 0.22), (0.28, 0.98, 0.65, 0.1),
             (0.42, 0.96, 0.75, 0.0)]
    parts = []
    for dur, ratio, level, gap in notes:
        tt = t_(dur)
        f = f0 * ratio * (1 - 0.05 * tt / dur)
        voice = np.sin(phase(f)) + 0.22 * np.sin(2 * phase(f)) + 0.06 * np.sin(3 * phase(f))
        breath = bp(white(dur, rng), 260, 900) * 0.18
        shape = swell(tt, dur, 0.07, 0.14, power=1.2)
        parts.append((voice + breath) * shape * level)
        parts.append(np.zeros(int(gap * SR)))
    return lp(np.concatenate(parts), 1800)


def hill_morning(seconds, rng):
    """Hill House at eight: a soft breeze through the grass and the apple tree, the sea far below under the mist, and
    now and then a wood pigeon in the garden, low and slow."""
    t = t_(seconds)
    gust = np.clip(0.4 + 0.35 * drift(seconds, rng, rate=0.12) + 0.1 * drift(seconds, rng, rate=0.7), 0.05, 1)

    def shape(times, freqs):
        g = np.interp(times, t, gust)
        centre = 240 + 560 * g
        return (1 / (1 + (freqs / centre) ** 2.4)) * (1 / (1 + (60 / np.maximum(freqs, 1)) ** 2)) * (0.2 + g)
    air = sculpted(seconds, rng, shape)
    # The apple tree's leaves, a fine rustle on the stronger gusts.
    leaves = bp(white(seconds, rng), 900, 2400) * np.clip(gust - 0.45, 0, 1) ** 2
    # The sea, far below, under the mist: a low hush.
    sea = lp(pink(seconds, rng), 240)
    out = peak(air) + 0.05 * peak(leaves) + 0.3 * peak(sea)
    at = rng.uniform(3, 6)
    while at < seconds - 4:
        add(out, peak(pigeon(rng)), at, 0.18)
        at += rng.uniform(10, 15)
    return reverb_loop(lp(out, 2200), "open", rng, wet=0.25)


BEDS = [("ShoreSea", shore_sea, 26), ("RoofWind", roof_wind, 20), ("PartyFar", party_far, 16),
        ("HarbourNight", harbour_night, 24), ("BathsHum", baths_hum, 20), ("HoldDrone", hold_drone, 30),
        ("HillMorning", hill_morning, 28)]

if __name__ == "__main__":
    only = set(sys.argv[1:])
    for name, make, seconds in BEDS:
        if only and name not in only:
            continue
        rng = rng_for(name, 9500)
        print(write(AMBIENCE / ("%s.wav" % name), finish_loop(make(seconds + 2.0, rng), seconds, 2.0, LEVELS[name])))
