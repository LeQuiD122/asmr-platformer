"""Each ending's own sounds, remade (the ninety-sixth pass): every one of the eighteen, scored like the end of a film.

    python audio/gen_ending_sfx.py               every one
    python audio/gen_ending_sfx.py EndChord      only those named

Writes audio/endings/<Name>.wav, the same eighteen names as before, for SoundService.StorySounds: each a drop-in
for the old one, at its loudness and (for the loops) its length, so the scenes play them as they did.

What changed is what they are made of (`sfx_kit.py`). The chords were sine waves; they are a felt piano and a soft
string section now, in a hall. The water was band-passed hiss; it is water now: bubbles ringing, drops landing,
cavities closing (the splash you go into the sea with is the same physics as a drip, at the size of a person). The
wind is air shaped by how fast you are going, and the tunnels and shafts are rooms with their own echoes.

  CITY SHORE     DiveBoard, DiveWind, DiveSplash, UnderwaterHum (loop), ShoreChord
  SKY POOLS      SlideRush (loop), CloudWhoosh, SkimSlap, PoolPlunge, PoolsChord
  SUNKEN CITY    WhirlRoar (loop), DrainFall, CulvertWash (loop), SunkenChord
  FLOODED HALLS  FlumeRush (loop), PlungeWind, HallsChord
  ALL FOUR       EndChord: the open chord any ending falls back on, at its own pitch

(The Needoh's and the lava crust's takes, which this file used to write, are gen_sheet_sfx.py's now.)

Seeded from each name, so re-running writes the same files.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import (SR, bp, brown, bubble, bubbles, drift, droplet, env, fade, felt_piano, finish, finish_loop, gliding, hp, lp,  # noqa
                     match, modal, n_, peak, phase, pink, place, resonate, reverb, reverb_loop, rng_for, sculpted,
                     seamless, splash, strike, swell, t_, warm_pad, white, wood_bar, write)

HERE = pathlib.Path(__file__).resolve().parent
ENDINGS = HERE / "endings"

# The loudness of each old file (measured), which the scenes' volumes were set against.
LEVELS = {"DiveBoard": -16.4, "DiveWind": -17.6, "DiveSplash": -19.0, "UnderwaterHum": -25.1, "ShoreChord": -17.0,
          "SlideRush": -18.0, "CloudWhoosh": -16.0, "SkimSlap": -18.1, "PoolPlunge": -20.5, "PoolsChord": -18.5,
          "WhirlRoar": -17.7, "DrainFall": -14.5, "CulvertWash": -19.2, "SunkenChord": -16.5, "FlumeRush": -18.0,
          "PlungeWind": -15.0, "HallsChord": -16.7, "EndChord": -17.4}


def chord(notes, seconds, rng, roll=0.07, velocity=0.4, pad=0.5, pad_attack=1.6, pad_release=3.0, brightness=0.45,
          space="hall", wet=0.4, piano=True):
    """A chord as the films end on one: the felt piano rolling it from the bottom up, the strings swelling in under it,
    both in a room."""
    layers = []
    if piano:
        for k, f in enumerate(notes):
            v = velocity * (1.0 - 0.08 * k) * rng.uniform(0.9, 1.05)
            layers.append((k * roll * rng.uniform(0.8, 1.2), 1.0 / (1 + 0.15 * k), felt_piano(f, seconds, rng, v)))
    if pad:
        strings = warm_pad(notes, seconds, rng, attack=pad_attack, release=pad_release, brightness=brightness)
        layers.append((0.0, pad * 2.5, strings))
    x = place(seconds, layers)
    return reverb(x, space, rng, wet=wet)[:n_(seconds)]


def wind(seconds, rng, speed, gusts=0.3, low=180, high=5000):
    """Air going past: the faster (`speed` 0..1 over time) the brighter and louder, buffeted by turbulence."""
    t = t_(seconds)
    turb = 0.75 + 0.25 * drift(seconds, rng, rate=4.0) + gusts * 0.2 * drift(seconds, rng, rate=11.0)

    def shape(times, freqs):
        s = np.interp(times, t, speed)
        centre = low + (high - low) * s ** 1.3
        body = 1 / (1 + (freqs / centre) ** 2) * (freqs > 40)
        rumble = 1 / (1 + (freqs / 90) ** 4) * (0.4 + s)
        return (body + 0.6 * rumble) * (0.25 + s)
    return sculpted(seconds, rng, shape) * turb


def stream(seconds, rng, rate, r_mm=(0.7, 5.0), body_hz=700, body=0.8):
    """Running water: bubbles at `rate` a second (a number or an array), over the low turbulent body of the flow."""
    t = t_(seconds)
    flow = bubbles(seconds, rng, rate, r_mm=r_mm, beta=2.3, xi=(0.05, 0.3))
    level = 0.8 + 0.2 * drift(seconds, rng, rate=0.5)

    def shape(times, freqs):
        return 1 / (1 + (freqs / body_hz) ** 2.4) * (freqs > 40)
    rush = sculpted(seconds, rng, shape) * level
    return peak(flow) + body * peak(rush)


# ================================================================ CITY SHORE
def dive_board(rng):
    d = 1.6
    # The board creaking as your weight goes to its end (friction in the fulcrum), then letting go: the board's own
    # deep flex, its wobble, and the roller rattling in time with it.
    creak_t = t_(0.4)
    creak = modal(0.4, [610, 980, 1430], [0.06, 0.05, 0.03], [1.0, 0.6, 0.3], rng)
    taps = np.zeros(n_(0.4))
    i = 0
    while i < len(taps):
        taps[i] = rng.uniform(0.3, 1.0) * np.sin(np.pi * i / len(taps))
        i += max(1, int(SR / (45 + 30 * i / len(taps)) * rng.uniform(0.7, 1.3)))
    creak = np.convolve(taps, creak)[:len(taps)] * env(creak_t, 0.05, 0.25)
    flex = strike(1.4, [64, 148, 290, 512], [0.9, 0.55, 0.3, 0.15], [1.0, 0.55, 0.3, 0.12], rng, hardness=0.3)
    wobble = 0.55 + 0.45 * np.cos(2 * np.pi * 8.5 * t_(1.4)) * np.exp(-t_(1.4) / 0.5)
    rattle = np.zeros(n_(1.4))
    for k in range(9):
        at = k / 8.5 + 0.02
        knock = strike(0.06, [rng.uniform(1700, 2100), rng.uniform(2900, 3300)], [0.02, 0.012], [1, 0.5], rng, 0.8)
        a = n_(at)
        rattle[a:a + len(knock)] += knock[:len(rattle) - a] * np.exp(-at / 0.35)
    x = place(d, [(0.0, 0.35, peak(creak)), (0.17, 1.0, peak(flex * wobble)), (0.17, 0.12, peak(rattle))])
    x = reverb(x, "open", rng, wet=0.25)[:n_(d)]
    return finish(x, LEVELS["DiveBoard"], high_cut=6000, fade_out=0.15)


def dive_wind(rng):
    d = 7.0
    t = t_(d)
    speed = np.clip(t / d, 0, 1) ** 1.2
    air = wind(d, rng, speed, gusts=1.0, low=220, high=2800)
    # Clothes and hair flapping: a low irregular flutter that quickens as you go faster.
    flap_rate = 9 + 14 * speed
    flap = 0.5 + 0.5 * np.sin(phase(flap_rate + 3 * drift(d, rng, rate=3)))
    flutter = lp(bp(white(d, rng), 120, 900), 1200) * flap ** 3 * (0.2 + speed)
    level = swell(t, d, 0.6, 0.08) * (0.3 + 0.7 * speed)
    x = (peak(air) + 0.3 * peak(flutter)) * level
    return finish(x, LEVELS["DiveWind"], high_cut=7000, fade_out=0.08)


def dive_splash(rng):
    d = 4.5
    t = t_(d)
    hit = splash(rng, size=3.0, seconds=1.6)
    boom = bubble(55, rng, xi=0.4, seconds=0.9)
    # Then under: the world shut off, the bubbles you brought down with you rising past your ears, slowly.
    under_t = t_(3.6)
    rising = bubbles(3.6, rng, 420 * np.exp(-under_t / 0.9), r_mm=(1.0, 8.0), beta=2.2, xi=(0.05, 0.2))
    pressure = lp(brown(3.6, rng), 260) * env(under_t, 0.15, 1.8)
    under = fade(reverb(lp(peak(rising), 1100, order=4) + 0.9 * peak(pressure), "under", rng, wet=0.5)[:n_(3.6)], 0, 0.6)
    x = place(d, [(0.0, 1.0, peak(hit)), (0.01, 0.7, peak(boom)), (0.55, 0.65, peak(under))])
    return finish(x, LEVELS["DiveSplash"], high_cut=7000, fade_out=0.6)


def underwater_hum(seconds, rng):
    t = t_(seconds)
    pressure = lp(brown(seconds, rng), 240) * (0.8 + 0.2 * drift(seconds, rng, rate=0.15))
    # Far bubbles, in slow strings of three or four, rising from the street below.
    trains = np.zeros(n_(seconds))
    at = rng.uniform(0.2, 1.5)
    while at < seconds - 1:
        for k in range(rng.integers(2, 6)):
            b = bubble(rng.uniform(260, 620), rng, xi=rng.uniform(0.08, 0.22))
            a = n_(at + k * rng.uniform(0.09, 0.2))
            if a + len(b) < len(trains):
                trains[a:a + len(b)] += b * rng.uniform(0.4, 1.0)
        at += rng.uniform(1.2, 3.0)
    # The lamp: its mains hum, heard through the water as something felt (a few rough harmonics, wavering).
    f = 50 * (1 + 0.002 * drift(seconds, rng, rate=0.3))
    ph = phase(np.full(n_(seconds), 1.0) * f)
    lamp = sum(np.sin(k * ph + rng.uniform(0, 6)) / k ** 1.3 for k in range(1, 7))
    lamp = lp(lamp, 300) * (0.6 + 0.4 * drift(seconds, rng, rate=0.1))
    x = peak(pressure) + 0.35 * peak(lp(trains, 900, order=4)) + 0.05 * peak(lamp)
    return reverb_loop(x, "under", rng, wet=0.35)


def shore_chord(rng):
    # G: warm and low, as the street lamp comes into view under the water.
    x = chord([98.0, 146.8, 196.0, 246.9, 293.7], 9.0, rng, roll=0.09, velocity=0.38, pad=0.5, brightness=0.35,
              pad_attack=2.0, pad_release=3.5)
    return finish(x, LEVELS["ShoreChord"], high_cut=4500, fade_out=2.5)


# ================================================================ SKY POOLS
def slide_rush(seconds, rng):
    t = t_(seconds)
    water = stream(seconds, rng, 1800 * (0.85 + 0.15 * drift(seconds, rng, rate=0.6)), r_mm=(0.6, 4.0), body_hz=900)
    # The sled's hull on the water: a low hollow drum, and a bump at every joint of the trough.
    hull = resonate(brown(seconds, rng), [(140, 1.0), (310, 0.4)], q=4) * (0.7 + 0.3 * drift(seconds, rng, rate=2))
    joints = np.zeros(n_(seconds))
    at = 0.3
    while at < seconds - 0.3:
        knock = strike(0.25, [rng.uniform(90, 120), rng.uniform(210, 260)], [0.12, 0.07], [1, 0.4], rng, 0.2)
        a = n_(at)
        joints[a:a + len(knock)] += knock[:len(joints) - a] * rng.uniform(0.5, 1.0)
        at += rng.uniform(0.55, 0.85)
    air = wind(seconds, rng, np.full(n_(seconds), 0.55), low=300, high=2500)
    return peak(water) + 0.5 * peak(hull) + 0.25 * peak(joints) + 0.3 * peak(air)


def cloud_whoosh(rng):
    d = 3.0
    t = t_(d)
    inside = np.sin(np.pi * np.clip(t / d, 0, 1)) ** 2
    # Into the cloud: a soft enormous whoosh, the world going muffled (the top falling away) and coming back.
    def shape(times, freqs):
        k = np.interp(times, t, inside)
        top = 2600 - 2000 * k
        return (1 / (1 + (freqs / top) ** 2.5)) * (1 / (1 + (90 / np.maximum(freqs, 1)) ** 2)) * (0.3 + k)
    air = sculpted(d, rng, shape)
    damp = lp(pink(d, rng), 400) * inside ** 2
    x = (peak(air) + 0.4 * peak(damp)) * swell(t, d, 0.4, 0.6)
    return finish(x, LEVELS["CloudWhoosh"], high_cut=5000, fade_out=0.2)


def skim_slap(rng):
    x = splash(rng, size=0.6, seconds=0.7)
    hull = strike(0.3, [180, 410], [0.08, 0.05], [1, 0.4], rng, hardness=0.35)
    x = place(0.7, [(0.0, 1.0, peak(x)), (0.0, 0.5, peak(hull))])
    return finish(x, LEVELS["SkimSlap"], high_cut=6500, fade_out=0.1)


def pool_plunge(rng):
    d = 2.2
    hit = splash(rng, size=1.6, seconds=1.4)
    under_t = t_(1.8)
    rising = bubbles(1.8, rng, 520 * np.exp(-under_t / 0.5), r_mm=(1.0, 6.0), beta=2.2, xi=(0.05, 0.2))
    under = fade(reverb(lp(rising, 1200, order=4), "under", rng, wet=0.4)[:n_(1.8)], 0, 0.4)
    x = place(d, [(0.0, 1.0, peak(hit)), (0.3, 0.55, peak(under))])
    return finish(x, LEVELS["PoolPlunge"], high_cut=6500, fade_out=0.4)


def pools_chord(rng):
    # C major with its seventh and ninth: bright, open, a little wistful; wooden bars catching the light on top.
    notes = [130.8, 261.6, 329.6, 392.0, 493.9, 587.3]
    x = chord(notes, 9.0, rng, roll=0.08, velocity=0.42, pad=0.45, brightness=0.6, pad_attack=1.4, pad_release=3.5)
    bars = place(9.0, [(0.5 + 0.22 * k, 0.35 - 0.04 * k, wood_bar(f, 6.0, rng, velocity=0.3))
                       for k, f in enumerate([523.3, 659.3, 784.0, 987.8])])
    bars = reverb(bars, "hall", rng, wet=0.5)[:n_(9.0)]
    x = peak(x) + 0.35 * peak(bars)
    return finish(x, LEVELS["PoolsChord"], high_cut=6500, fade_out=2.5)


# ================================================================ THE SUNKEN CITY
def whirl_roar(seconds, rng):
    t = t_(seconds)
    turn = 2.2  # seconds a turn of the swirl takes to come round past you
    sweep = 0.5 + 0.5 * np.sin(2 * np.pi * t / turn + 0.6 * drift(seconds, rng, rate=0.4))

    def shape(times, freqs):
        s = np.interp(times, t, sweep)
        centre = 260 + 520 * s
        return (1 / (1 + ((freqs - centre) / (centre * 0.8)) ** 2) + 0.5 / (1 + (freqs / 120) ** 2)) * (freqs > 30)
    swirl = sculpted(seconds, rng, shape)
    gulps = bubbles(seconds, rng, 140 * (0.6 + 0.4 * sweep), r_mm=(4.0, 18.0), beta=1.9, xi=(0.25, 0.5))
    churn = bubbles(seconds, rng, 900, r_mm=(0.8, 3.5), beta=2.5, xi=(0.05, 0.25))
    # Where it goes down: a big pipe's throat, resonating with the water pulled into it.
    throat = resonate(brown(seconds, rng), [(46, 1.0), (93, 0.6), (141, 0.3)], q=8) * (0.7 + 0.3 * sweep)
    return peak(swirl) + 0.45 * peak(lp(gulps, 1500)) + 0.25 * peak(churn) + 0.6 * peak(throat)


def drain_fall(rng):
    d = 4.5
    t = t_(d)
    speed = np.clip(t / 1.5, 0, 1)
    rush = stream(d, rng, 2200 * speed, r_mm=(0.8, 6.0), body_hz=800)
    air = wind(d, rng, 0.3 + 0.5 * speed, low=200, high=1800)
    pipe = gliding(d, rng, 70 - 14 * t / d, partials=((1.0, 1.0), (2.0, 0.4)), q=7)
    x = (peak(rush) + 0.45 * peak(air) + 0.4 * peak(pipe)) * swell(t, d, 0.3, 1.1)
    x = reverb(x, "shaft", rng, wet=0.55)[:n_(d)]
    return finish(x, LEVELS["DrainFall"], high_cut=6000, fade_out=0.5)


def culvert_wash(seconds, rng):
    water = stream(seconds, rng, 1100 * (0.8 + 0.2 * drift(seconds, rng, rate=0.4)), r_mm=(0.8, 6.5), body_hz=600)
    laps = np.zeros(n_(seconds))
    at = 0.2
    while at < seconds - 0.6:
        s = splash(rng, size=rng.uniform(0.25, 0.5), seconds=0.6)
        a = n_(at)
        laps[a:a + len(s)] += lp(s, 2500)[:len(laps) - a] * rng.uniform(0.3, 0.8)
        at += rng.uniform(0.8, 2.2)
    x = peak(water) + 0.4 * peak(laps)
    return reverb_loop(x, "culvert", rng, wet=0.5)


def sunken_chord(rng):
    # D minor, low, a long way under the water: the strings carry it, the piano a dull bell under them.
    x = chord([73.4, 110.0, 146.8, 174.6, 220.0], 9.0, rng, roll=0.11, velocity=0.3, pad=0.7, brightness=0.25,
              pad_attack=2.4, pad_release=3.6, space="cavern", wet=0.5)
    return finish(lp(x, 2400), LEVELS["SunkenChord"], fade_out=2.5)


# ================================================================ THE FLOODED HALLS
def flume_rush(seconds, rng):
    water = stream(seconds, rng, 2000 * (0.85 + 0.15 * drift(seconds, rng, rate=0.7)), r_mm=(0.6, 4.5), body_hz=1100)
    # The tube: a plastic pipe's hollow note under the water in it (noise in its modes), drumming at the joints.
    tube = resonate(pink(seconds, rng), [(185, 1.0), (372, 0.6), (561, 0.35), (748, 0.2)], q=10)
    joints = np.zeros(n_(seconds))
    at = 0.2
    while at < seconds - 0.3:
        knock = strike(0.3, [rng.uniform(150, 190), rng.uniform(340, 400)], [0.15, 0.08], [1, 0.5], rng, 0.25)
        a = n_(at)
        joints[a:a + len(knock)] += knock[:len(joints) - a] * rng.uniform(0.4, 1.0)
        at += rng.uniform(0.35, 0.6)
    x = peak(water) + 0.35 * peak(tube) + 0.3 * peak(joints)
    return reverb_loop(x, "tiles", rng, wet=0.3)


def plunge_wind(rng):
    d = 3.8
    t = t_(d)
    speed = np.clip(t / d, 0, 1)
    air = wind(d, rng, 0.25 + 0.6 * speed, low=200, high=2200)
    # Under it, from below, the thing: a low rumble growing, felt before it is heard.
    rumble = resonate(brown(d, rng), [(52, 1.0), (104, 0.5)], q=4) * speed ** 1.5
    x = (peak(air) + 0.8 * peak(rumble)) * swell(t, d, 0.2, 0.3)
    x = reverb(x, "shaft", rng, wet=0.4)[:n_(d)]
    return finish(x, LEVELS["PlungeWind"], high_cut=5000, fade_out=0.3)


def halls_chord(rng):
    # The tide going out: A with a suspended fourth, held, then the fourth falling to the third (D to C sharp): the
    # one chord in the game that resolves. The piano plays the resolution as the strings make it.
    d = 10.0
    t = t_(d)
    first = chord([110.0, 164.8, 220.0, 293.7], d, rng, roll=0.1, velocity=0.38, pad=0.0)
    strings_sus = warm_pad([110.0, 164.8, 220.0, 293.7], d, rng, attack=1.8, release=5.5, brightness=0.4)
    strings_res = warm_pad([110.0, 164.8, 220.0, 277.2], d, rng, attack=1.8, release=3.5, brightness=0.4)
    blend = np.clip((t - 4.2) / 1.4, 0, 1)
    strings = strings_sus * (1 - blend) + strings_res * blend
    resolve = place(d, [(4.6, 1.0, felt_piano(277.2, d - 4.6, rng, 0.4)), (4.68, 0.6, felt_piano(554.4, d - 4.68, rng, 0.25))])
    x = peak(first) + 0.6 * peak(reverb(strings, "hall", rng, wet=0.4)[:n_(d)]) + 0.5 * peak(
        reverb(resolve, "hall", rng, wet=0.4)[:n_(d)])
    return finish(x, LEVELS["HallsChord"], high_cut=4500, fade_out=2.5)


# ================================================================ ONE CHORD FOR ALL FOUR
def end_chord(rng):
    # Root, fifth, octave, ninth, a high fifth: no third, so it sounds right low and dark or high and bright.
    x = chord([110.0, 164.8, 220.0, 246.9, 329.6], 9.0, rng, roll=0.08, velocity=0.4, pad=0.5, brightness=0.45)
    return finish(x, LEVELS["EndChord"], high_cut=5000, fade_out=2.5)


ONE_SHOTS = [("DiveBoard", dive_board), ("DiveSplash", dive_splash), ("DiveWind", dive_wind), ("ShoreChord", shore_chord),
             ("CloudWhoosh", cloud_whoosh), ("SkimSlap", skim_slap), ("PoolPlunge", pool_plunge),
             ("PoolsChord", pools_chord), ("DrainFall", drain_fall), ("SunkenChord", sunken_chord),
             ("PlungeWind", plunge_wind), ("HallsChord", halls_chord), ("EndChord", end_chord)]
LOOPS = [("UnderwaterHum", underwater_hum, 14), ("SlideRush", slide_rush, 8), ("WhirlRoar", whirl_roar, 10),
         ("CulvertWash", culvert_wash, 10), ("FlumeRush", flume_rush, 8)]

if __name__ == "__main__":
    only = set(sys.argv[1:])
    for name, make in ONE_SHOTS:
        if not only or name in only:
            print(write(ENDINGS / ("%s.wav" % name), make(rng_for(name, 9500))))
    for name, make, seconds in LOOPS:
        if not only or name in only:
            rng = rng_for(name, 9500)
            print(write(ENDINGS / ("%s.wav" % name), finish_loop(make(seconds + 2.0, rng), seconds, 2.0, LEVELS[name])))
