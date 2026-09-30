"""Each ending's own sounds, a new Needoh squeeze and a new lava crust, synthesised.

    python audio/gen_ending_sfx.py

Writes 16-bit mono WAVs:

  audio/endings/<Name>.wav        every ending's own sounds (below), for SoundService.StorySounds
  audio/materials/needohSquish_<n>.wav   four takes of the squeeze toy (it was sharing clay's sound)
  audio/materials/lavaCrust_<n>.wav      four new takes of the lava crust, replacing the old ones

THE ENDINGS, each scored like the end of a film, and each in its own voice:

  CITY SHORE     DiveBoard (the board letting you go), DiveWind (the fall, rising), DiveSplash (going in,
                 and the water closing), UnderwaterHum (the dark under the harbour, looped), ShoreChord
                 (the last chord, warm, as the street lamp comes into view).
  SKY POOLS      SlideRush (water in the trough, looped), CloudWhoosh (through the cloud sea), SkimSlap
                 (each hop across the pool), PoolPlunge (tipping in), PoolsChord (bright, a little wistful).
  SUNKEN CITY    WhirlRoar (the whirlpool turning, looped), DrainFall (down the shaft), CulvertWash (carried
                 along Outfall 3, looped), SunkenChord (dark, as the time card comes into view).
  FLOODED HALLS  FlumeRush (the flume, looped), PlungeWind (the fall into the dark), HallsChord (the tide
                 going out: the only chord in the game that resolves).

HOW TO GET THEM INTO THE GAME (as with the other story sounds): Asset Manager, Bulk Import every file in
audio/endings/, and drag them into the Folder SoundService.StorySounds. Each scene looks its sounds up
there by name, and plays a built-in stand-in for any it does not find. The material takes go into
SoundService.MaterialSounds, as before (and the four old lavaCrust sounds come out of it first).

Seeded from each name, so re-running writes the same files.
"""
import pathlib
import sys
import zlib

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_button_sfx import SR, axis, envelope, filt, finish, mix, peak, phase, punch, taper  # noqa: E402
from gen_material_sfx import MATERIALS, band, noise, ring, seamless, write  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
ENDINGS = HERE / "endings"


def brown(duration, rng):
    """Deep rumbling noise: white noise summed, its drift taken out."""
    b = np.cumsum(noise(duration, rng))
    return filt(b - np.mean(b), "high", 20, order=2)


def echo(x, lags, decay):
    """The signal and a few decaying copies of itself: a shaft, a tunnel, a tiled room."""
    out = x.copy()
    for k, lag in enumerate(lags):
        shift = int(SR * lag)
        if shift < len(x):
            out[shift:] += x[:-shift] * (decay ** (k + 1))
    return out


def pad(duration, notes, attack, release, shimmer=0.0, rng=None):
    """A soft chord: each note two slightly detuned sines and a quiet octave, swelling in and dying away."""
    t = axis(duration)
    y = np.zeros_like(t)
    for index, freq in enumerate(notes):
        start = 0.12 * index
        local = np.maximum(t - start, 0)
        voice = (np.sin(phase(np.full_like(t, freq))) + 0.8 * np.sin(phase(np.full_like(t, freq * 1.004)))
                 + 0.25 * np.sin(phase(np.full_like(t, freq * 2.0))))
        level = np.clip(local / attack, 0, 1) * np.clip((duration - t) / release, 0, 1) * (t >= start)
        y += voice * level
    if shimmer and rng is not None:
        y += shimmer * band(noise(duration, rng), 3000, 9000) * np.clip(t / attack, 0, 1) * np.clip((duration - t) / release, 0, 1)
    return y


# ================================================================ CITY SHORE
def dive_board(rng):
    """The springboard letting go: a wooden creak, a deep flex thunk, and the board's wobble ringing on."""
    creak = band(noise(0.35, rng), 700, 2400) * (0.5 + 0.5 * np.sin(2 * np.pi * 34 * axis(0.35))) * envelope(axis(0.35), 0.05, 0.12)
    thunk = punch(0.5, 160, 70, 0.02, 0.12, drive=2.0)
    wobble = ring(1.4, [96, 191, 287], 0.35, rng, drop=0.02)
    wobble = wobble * (0.6 + 0.4 * np.sin(2 * np.pi * 7.5 * axis(1.4)))
    return finish(mix(1.6, [(0.0, 0.5, taper(peak(creak))), (0.18, 1.0, thunk), (0.2, 0.55, taper(peak(wobble)))]), -3.0,
                  lowpass=6000)


def dive_wind(rng):
    """The fall: air rushing past, rising in pitch and loudness as the water comes up, buffeting."""
    d = 7.0
    t = axis(d)
    rise = (t / d) ** 1.4
    rushes = []
    for lo, hi in ((200, 900), (500, 2200), (1400, 5200)):
        rushes.append(band(noise(d, rng), lo, hi))
    body = rushes[0] * (0.6 + 0.4 * rise) + rushes[1] * (0.3 + 0.7 * rise) + rushes[2] * (0.1 + 0.9 * rise ** 2)
    buffet = 0.75 + 0.25 * np.sin(2 * np.pi * (3 + 5 * rise) * t + np.sin(2 * np.pi * 0.9 * t))
    level = np.clip(t / 0.6, 0, 1) * (0.35 + 0.65 * rise) * np.clip((d - t) / 0.08, 0, 1)
    return finish(peak(body) * buffet * level, -3.0, lowpass=9000)


def dive_splash(rng):
    """Going in: the crack of the surface, a deep boom, spray falling back, then the water closing over
    you and everything going muffled and full of bubbles."""
    d = 4.5
    crack = filt(noise(0.08, rng), "high", 1800) * envelope(axis(0.08), 0.0008, 0.02)
    boom = punch(1.6, 90, 28, 0.06, 0.55, drive=2.6)
    spray = band(noise(1.8, rng), 1200, 7000) * envelope(axis(1.8), 0.02, 0.5)
    under = filt(brown(3.4, rng), "low", 380) * np.clip(axis(3.4) / 0.2, 0, 1) * np.exp(-axis(3.4) / 2.2)
    bubbles = []
    for _ in range(26):
        f = rng.uniform(260, 900)
        size = rng.uniform(0.04, 0.09)
        b = np.sin(phase(f * (1 + 0.6 * axis(size) / size))) * envelope(axis(size), 0.004, size / 3)
        bubbles.append((0.35 + rng.uniform(0, 2.6), rng.uniform(0.15, 0.35), taper(b)))
    return finish(mix(d, [(0.0, 0.8, peak(crack)), (0.0, 1.0, boom), (0.02, 0.5, taper(peak(spray))),
                          (0.3, 0.7, taper(peak(under)))] + bubbles), -1.5, lowpass=7000)


def underwater_hum(duration, rng):
    """Down under the harbour: the water's own low pressure, slow bubbles, and far off, a lamp buzzing."""
    t = axis(duration)
    low = filt(brown(duration, rng), "low", 220) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.11 * t))
    buzz = (np.sin(2 * np.pi * 60 * t) + 0.4 * np.sin(2 * np.pi * 120 * t)) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * t))
    y = 0.9 * peak(low) + 0.06 * buzz
    for _ in range(int(duration * 1.2)):
        f = rng.uniform(300, 700)
        size = rng.uniform(0.05, 0.12)
        at = int(SR * rng.uniform(0, duration - size))
        b = np.sin(phase(f * (1 + 0.5 * axis(size) / size))) * envelope(axis(size), 0.005, size / 3)
        y[at:at + len(b)] += 0.12 * b
    return y


def shore_chord(rng):
    """The last chord, as the street lamp comes into view under the water: warm, low, unhurried."""
    return finish(pad(9.0, [98.0, 146.8, 196.0, 246.9, 293.7], 2.5, 3.5, 0.03, rng), -6.0, lowpass=3500)


# ================================================================ SKY POOLS
def slide_rush(duration, rng):
    """Water sheeting down the trough under you, the sled's hull hissing on it, and the air going by."""
    t = axis(duration)
    sheet = band(noise(duration, rng), 800, 4500) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.5 * t))
    hull = band(noise(duration, rng), 150, 600) * (0.7 + 0.3 * np.sin(2 * np.pi * 2.3 * t))
    air = band(noise(duration, rng), 2500, 8000) * 0.4
    return 0.8 * peak(sheet) + 0.6 * peak(hull) + 0.3 * peak(air)


def cloud_whoosh(rng):
    """Through the cloud sea: a big soft whoosh, the world going muffled and coming back."""
    d = 3.0
    t = axis(d)
    shape = np.sin(np.pi * np.clip(t / d, 0, 1)) ** 2
    sweep = filt(noise(d, rng), "low", 600) * 0.6 + band(noise(d, rng), 400, 3000) * shape
    return finish(peak(sweep) * shape, -5.0, lowpass=5000)


def skim_slap(rng):
    """The sled's float slapping the water on a hop, and the spray off it."""
    slap = filt(noise(0.05, rng), "band", [300, 2500]) * envelope(axis(0.05), 0.0008, 0.012)
    body = punch(0.3, 180, 80, 0.015, 0.06, drive=1.8)
    spray = band(noise(0.6, rng), 1500, 7000) * envelope(axis(0.6), 0.01, 0.18)
    return finish(mix(0.7, [(0.0, 1.0, peak(slap)), (0.0, 0.7, body), (0.01, 0.45, taper(peak(spray)))]), -2.0,
                  lowpass=8000)


def pool_plunge(rng):
    """Tipping out of the sled into the pool: a round splash, and bubbles going up past your ears."""
    splash = band(noise(1.0, rng), 500, 6000) * envelope(axis(1.0), 0.005, 0.25)
    body = punch(0.8, 120, 45, 0.04, 0.25, drive=2.0)
    bubbles = []
    for _ in range(14):
        f = rng.uniform(400, 1100)
        size = rng.uniform(0.03, 0.07)
        b = np.sin(phase(f * (1 + 0.6 * axis(size) / size))) * envelope(axis(size), 0.003, size / 3)
        bubbles.append((0.25 + rng.uniform(0, 1.4), rng.uniform(0.15, 0.3), taper(b)))
    return finish(mix(2.2, [(0.0, 0.8, taper(peak(splash))), (0.0, 0.8, body)] + bubbles), -2.5, lowpass=7500)


def pools_chord(rng):
    """The last chord of the Sky Pools: bright, open, and a little wistful, with sunlight on water in it."""
    return finish(pad(9.0, [261.6, 329.6, 392.0, 493.9, 587.3], 2.0, 3.5, 0.06, rng), -7.0, lowpass=7000)


# ================================================================ THE SUNKEN CITY
def whirl_roar(duration, rng):
    """The whirlpool turning: a deep roar with the water's swirl sweeping round through it, and a
    sucking drone under it where it goes down."""
    t = axis(duration)
    roar = filt(brown(duration, rng), "low", 700)
    swirl_rate = 0.45
    sweep = band(noise(duration, rng), 500, 2600) * (0.55 + 0.45 * np.sin(2 * np.pi * swirl_rate * t) ** 2)
    suck = np.sin(phase(np.full_like(t, 41.0) + 3 * np.sin(2 * np.pi * swirl_rate * t))) * 0.6
    return 0.9 * peak(roar) + 0.5 * peak(sweep) + 0.3 * suck


def drain_fall(rng):
    """Down the shaft: rushing water and air, echoing off brick, and the pipe's own low note."""
    d = 4.5
    t = axis(d)
    rush = band(noise(d, rng), 300, 3500) * np.clip(t / 0.3, 0, 1) * np.clip((d - t) / 1.0, 0, 1)
    pipe = np.sin(phase(np.full_like(t, 72.0) - 18 * t / d)) * 0.4 * np.clip(t / 0.5, 0, 1) * np.clip((d - t) / 1.2, 0, 1)
    return finish(echo(peak(rush) + pipe, (0.09, 0.19, 0.31), 0.45), -3.0, lowpass=6000)


def culvert_wash(duration, rng):
    """Carried along Outfall 3: a stream running over concrete, echoing down a long brick tunnel."""
    t = axis(duration)
    stream = band(noise(duration, rng), 400, 3000) * (0.75 + 0.25 * np.sin(2 * np.pi * 0.3 * t))
    low = filt(brown(duration, rng), "low", 300)
    y = 0.8 * peak(stream) + 0.5 * peak(low)
    return echo(y, (0.12, 0.27, 0.45), 0.4)


def sunken_chord(rng):
    """The last chord of the Sunken City: dark, minor, a long way under the water."""
    return finish(echo(pad(9.0, [73.4, 110.0, 146.8, 174.6, 220.0], 2.5, 3.8), (0.21, 0.47), 0.35), -6.0,
                  lowpass=2600)


# ================================================================ THE FLOODED HALLS
def flume_rush(duration, rng):
    """The flume: water hissing down a plastic tube, the tube drumming a little, the halls around it."""
    t = axis(duration)
    hiss = band(noise(duration, rng), 1200, 6500) * (0.8 + 0.2 * np.sin(2 * np.pi * 0.7 * t))
    drum = band(noise(duration, rng), 90, 300) * (0.6 + 0.4 * np.sin(2 * np.pi * 3.1 * t) ** 2)
    return echo(0.8 * peak(hiss) + 0.5 * peak(drum), (0.15, 0.33), 0.3)


def plunge_wind(rng):
    """Out of the tube and falling into the dark: air, and a low rumble growing under it."""
    d = 3.8
    t = axis(d)
    air = band(noise(d, rng), 400, 3200) * (0.4 + 0.6 * t / d)
    rumble = filt(brown(d, rng), "low", 140) * (t / d) ** 1.5
    level = np.clip(t / 0.2, 0, 1) * np.clip((d - t) / 0.3, 0, 1)
    return finish((0.7 * peak(air) + 0.8 * peak(rumble)) * level, -3.0, lowpass=5000)


def halls_chord(rng):
    """The tide going out: the one chord in the game that resolves, a suspension falling home."""
    d = 10.0
    t = axis(d)
    first = pad(d, [110.0, 164.8, 220.0, 293.7], 1.8, 5.5)
    second = pad(d, [110.0, 164.8, 220.0, 277.2], 1.8, 3.5)
    blend = np.clip((t - 4.0) / 1.5, 0, 1)
    return finish(first * (1 - blend) + second * blend, -6.0, lowpass=4000)


# ================================================================ THE MATERIALS
def needoh_squish(take, rng):
    """A NEE-DOH being squeezed: a slow, gloopy, dough-soft squish of gel moving inside a rubber skin, a
    faint rubbery creak as the skin stretches, and a soft wet suck as it swells back. Nothing like clay,
    which is a dense slap with no give: this is all give, slow, round, and a little funny."""
    d = rng.uniform(0.55, 0.7)
    t = axis(d)
    squeeze = 0.35
    # The gel: low filtered noise, swelling in slowly (the squeeze takes time) and easing off.
    gel = filt(noise(d, rng), "low", 520) * np.clip(t / squeeze, 0, 1) ** 0.7 * np.exp(-np.maximum(t - squeeze, 0) / 0.12)
    # Its "gloop": a wobbling low tone, the gel shifting inside.
    wobble = np.sin(phase(120 + 55 * np.sin(2 * np.pi * rng.uniform(5.5, 7.5) * t) - 40 * t / d))
    wobble *= np.clip(t / 0.08, 0, 1) * np.exp(-t / 0.28)
    # The skin: a soft rubber creak, a fast little flutter in the mids as it stretches.
    creak = band(noise(d, rng), 900, 2600) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * rng.uniform(55, 80) * t)))
    creak *= np.clip((t - 0.05) / 0.15, 0, 1) * np.exp(-np.maximum(t - 0.2, 0) / 0.08)
    # The swell back: a wet suck, rising.
    suck = np.sin(phase(260 + 380 * np.clip((t - squeeze) / 0.18, 0, 1))) * envelope(np.maximum(t - squeeze, 0), 0.02, 0.07)
    suck *= t >= squeeze
    return finish(mix(d, [(0.0, 1.0, taper(peak(gel))), (0.0, 0.55, taper(peak(wobble))),
                          (0.0, 0.18, taper(peak(creak))), (0.0, 0.35, taper(peak(suck)))]), -4.0, lowpass=5000)


def lava_crust(take, rng):
    """A crust on something molten, and it is about to go: a thick low bubbling glop underneath, a crack
    of the crust with a hot hiss out of it, and a spit of something gloopy. Heavier and hotter than the
    old dry hiss; still not a roar, because nothing here roars."""
    d = 0.9
    t = axis(d)
    hiss = band(noise(d, rng), 1600, 7000) * envelope(t, 0.02, 0.35)
    under = filt(brown(d, rng), "low", 160) * envelope(t, 0.03, 0.4)
    bloops = []
    for _ in range(3 + take % 2):
        f = rng.uniform(70, 140)
        size = rng.uniform(0.12, 0.2)
        b = np.sin(phase(f * (1 + 0.9 * axis(size) / size))) * envelope(axis(size), 0.01, size / 2.5)
        bloops.append((rng.uniform(0.0, 0.5), rng.uniform(0.35, 0.55), taper(b)))
    crack = ring(0.08, [rng.uniform(2600, 3600), rng.uniform(4200, 5200)], 0.02, rng)
    spit = band(noise(0.12, rng), 400, 2200) * envelope(axis(0.12), 0.004, 0.03)
    return finish(mix(d, [(0.0, 0.55, taper(peak(hiss))), (0.0, 0.8, taper(peak(under))),
                          (rng.uniform(0.02, 0.1), 0.45, crack), (rng.uniform(0.2, 0.5), 0.35, peak(spit))] + bloops),
                  -5.0, lowpass=8000)


ONE_SHOTS = [("DiveBoard", dive_board), ("DiveSplash", dive_splash), ("DiveWind", dive_wind), ("ShoreChord", shore_chord),
             ("CloudWhoosh", cloud_whoosh), ("SkimSlap", skim_slap), ("PoolPlunge", pool_plunge),
             ("PoolsChord", pools_chord), ("DrainFall", drain_fall), ("SunkenChord", sunken_chord),
             ("PlungeWind", plunge_wind), ("HallsChord", halls_chord)]
LOOPS = [("UnderwaterHum", underwater_hum, 14, -8.0), ("SlideRush", slide_rush, 8, -5.0),
         ("WhirlRoar", whirl_roar, 10, -3.0), ("CulvertWash", culvert_wash, 10, -5.0), ("FlumeRush", flume_rush, 8, -5.0)]

if __name__ == "__main__":
    print("writing %s" % ENDINGS)
    for name, make in ONE_SHOTS:
        rng = np.random.default_rng(zlib.crc32(name.encode()))
        write(ENDINGS, "%s.wav" % name, make(rng))
    for name, make, seconds, level in LOOPS:
        rng = np.random.default_rng(zlib.crc32(name.encode()))
        y = seamless(make, seconds, rng)
        write(ENDINGS, "%s.wav" % name, peak(filt(y, "high", 28, order=2)) * (10 ** (level / 20)))
    print("writing %s" % MATERIALS)
    for event, make in (("needohSquish", needoh_squish), ("lavaCrust", lava_crust)):
        for take in range(1, 5):
            rng = np.random.default_rng(zlib.crc32(event.encode()) + take + 1800)
            write(MATERIALS, "%s_%d.wav" % (event, take), make(take, rng))
