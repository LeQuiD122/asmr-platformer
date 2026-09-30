"""The sounds nobody recorded, synthesised: every material that was silent, and the gate chamber's three.

    python audio/gen_material_sfx.py

Writes 16-bit mono WAVs:

  audio/materials/<event>_<n>.wav   four takes each for the fourteen material events that had no
                                    sound at all (SOUND_BRIEF.md says what each wants, and each maker
                                    below says which line of the brief it follows)
  audio/story/<Name>.wav            GateGroan, WaterRush and Siren, for the Flooded Halls' last scene

HOW TO GET THEM INTO THE GAME, with no ids to copy:

  1. In Studio, Asset Manager -> Bulk Import, and pick every file in audio/materials/ (and audio/story/).
  2. In the Explorer, make a Folder in SoundService named MaterialSounds (and one named StorySounds).
  3. Drag each imported sound from the Asset Manager into its folder. Each becomes a Sound named after
     its file (iceCrack_1, iceCrack_2, ... and GateGroan, WaterRush, Siren).

AudioService reads SoundService.MaterialSounds when the game starts and gives every Sound in it to the
event its name starts with (iceCrack_3 -> iceCrack), alongside any ids in SOUND_IDS_BY_EVENT. The
Flooded Halls' scene looks in SoundService.StorySounds by name and uses a built-in sound for anything
it does not find. Nothing breaks while the folders are empty or missing.

Seeded from each file's name, so re-running writes the same takes.
"""
import pathlib
import sys
import zlib

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_button_sfx import (SR, axis, chirp, click, crackle, envelope, filt, finish, mix, peak, phase,  # noqa: E402
                            punch, taper)

HERE = pathlib.Path(__file__).resolve().parent
MATERIALS = HERE / "materials"
STORY = HERE / "story"


def write(folder, name, x):
    folder.mkdir(parents=True, exist_ok=True)
    x = np.asarray(x, dtype=float)
    wavfile.write(folder / name, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    rms = np.sqrt(np.mean(x ** 2))
    print("  %-24s %6.0f ms  peak %5.1f dB  rms %5.1f dB" % (
        name, 1000 * len(x) / SR, 20 * np.log10(np.max(np.abs(x)) + 1e-12), 20 * np.log10(rms + 1e-12)))


def noise(duration, rng):
    return rng.standard_normal(int(SR * duration))


def band(x, low, high, order=4):
    return filt(x, "band", [low, high], order)


def ring(duration, freqs, decay, rng, drop=0.0):
    """Inharmonic partials, each decaying, with a small fall in pitch: a struck brittle thing."""
    t = axis(duration)
    y = np.zeros_like(t)
    for index, f in enumerate(freqs):
        freq = f * (1 - drop * (1 - np.exp(-t / 0.05)))
        y += np.sin(phase(freq) + rng.uniform(0, 6.28)) * np.exp(-t / (decay / (1 + 0.35 * index))) / (1 + index * 0.4)
    return taper(peak(y), 0.3)


# ---------------------------------------------------------------- the fourteen materials
def ice_crack(take, rng):
    # "a bright, brittle crack with a hollow ring under it ... a long thin resonance"
    crack = band(noise(0.03, rng), 2500, 11000) * envelope(axis(0.03), 0.0004, 0.004)
    return finish(mix(0.38, [
        (0.000, 0.9, peak(crack)),
        (0.000, 0.35, click(0.01, rng)),
        (0.002, 0.45, ring(0.36, [rng.uniform(1700, 1900), rng.uniform(2800, 3100), rng.uniform(4300, 4700)], 0.12, rng, 0.02)),
        (0.004, 0.25, ring(0.3, [rng.uniform(170, 200)], 0.07, rng)),
        (0.010, 0.18, crackle(0.25, 220, 0.05, 3000, 9000, rng)),
    ]), -3.0)


def jello_wobble(take, rng):
    # "a soft rubbery whumph on the press with a pitch dip as it flexes, then a faint carbonated fizz"
    t = axis(0.5)
    freq = 120 - 40 * (1 - np.exp(-t / 0.05)) + 8 * np.sin(2 * np.pi * 6 * t) * np.exp(-t / 0.12)
    body = np.sin(phase(freq)) * envelope(t, 0.006, 0.11) * (1 + 0.35 * np.sin(2 * np.pi * 14 * t) * np.exp(-t / 0.1))
    wet = filt(noise(0.5, rng), "low", 900) * envelope(t, 0.004, 0.05)
    return finish(mix(0.52, [
        (0.000, 0.9, taper(peak(body))),
        (0.000, 0.3, taper(peak(wet))),
        (0.080, 0.16, crackle(0.42, 160, 0.3, 4500, 10000, rng)),
    ]), -5.0, lowpass=11000)


def leaf_brush(take, rng):
    # "a dry, soft brush with no attack ... high, airy, with a faint papery rustle"
    t = axis(0.4)
    air = band(noise(0.4, rng), 2200, 7500) * envelope(t, 0.09, 0.1)
    rustle = crackle(0.4, 90, 0.2, 3000, 8000, rng) * envelope(t, 0.06, 0.12)
    return finish(mix(0.42, [(0.0, 0.8, taper(peak(air))), (0.0, 0.25, taper(rustle))]), -16.0, lowpass=9000)


def foam_compress(take, rng):
    # "a soft compressing whump with air moving through the cells ... plus a faint creak"
    t = axis(0.45)
    whump = filt(noise(0.45, rng), "low", 380) * envelope(t, 0.03, 0.09)
    breath = band(noise(0.45, rng), 700, 2400) * envelope(t, 0.05, 0.12)
    creak = chirp(0.06, rng.uniform(300, 380), rng.uniform(420, 520), 0.03, index=0.4)
    return finish(mix(0.46, [
        (0.0, 0.9, taper(peak(whump))),
        (0.0, 0.35, taper(peak(breath))),
        (0.12, 0.08, creak),
    ]), -14.0, lowpass=5000)


def switch_clack(take, rng):
    # "the hardest attack in the game ... two-stage, the spring going over followed by the paddle
    # hitting its stop"
    over = click(0.012, rng)
    stop = band(noise(0.05, rng), 1200, 9000) * envelope(axis(0.05), 0.0003, 0.006)
    body = ring(0.08, [rng.uniform(850, 1000), rng.uniform(2100, 2400)], 0.018, rng)
    gap = rng.uniform(0.014, 0.022)
    return finish(mix(0.16, [
        (0.000, 0.45, over),
        (gap, 1.0, peak(stop)),
        (gap, 0.55, body),
        (gap, 0.5, punch(0.06, 260, 120, 0.01, 0.02, drive=2.0)),
    ]), -1.0)


def lego_click(take, rng):
    # "a dry plastic tick ... completely without resonance. Then ... squeak-and-release"
    tick = band(noise(0.02, rng), 2400, 7000) * envelope(axis(0.02), 0.0002, 0.0035)
    squeak = chirp(0.03, rng.uniform(1500, 1800), rng.uniform(2400, 2800), 0.012, index=0.6)
    return finish(mix(0.14, [
        (0.000, 1.0, peak(tick)),
        (rng.uniform(0.05, 0.07), 0.18, squeak),
        (rng.uniform(0.08, 0.1), 0.35, peak(band(noise(0.01, rng), 3000, 8000) * envelope(axis(0.01), 0.0002, 0.002))),
    ]), -4.0)


def charcoal_snap(take, rng):
    # "a dull, dry snap with no ring to it ... followed by a scatter of grit"
    snap = filt(noise(0.05, rng), "low", 2600) * envelope(axis(0.05), 0.0005, 0.011)
    return finish(mix(0.42, [
        (0.000, 1.0, peak(snap)),
        (0.000, 0.35, punch(0.08, 180, 90, 0.01, 0.025, drive=1.4)),
        (0.020, 0.3, crackle(0.36, 260, 0.1, 1400, 5000, rng)),
    ]), -4.0, lowpass=6000)


def chocolate_snap(take, rng):
    # "a clean, brittle crack with a little ring ... progressively duller and softer on later takes"
    warm = (take - 1) / 3.0  # 0 on the first take, 1 on the fourth
    crack = band(noise(0.03, rng), 1800, 9000) * envelope(axis(0.03), 0.0004, 0.004 + 0.006 * warm)
    layers = [
        (0.000, 1.0 - 0.7 * warm, peak(crack)),
        (0.002, 0.4 * (1 - warm), ring(0.2, [rng.uniform(2200, 2600), rng.uniform(3600, 4000)], 0.05, rng)),
        (0.000, 0.3 + 0.5 * warm, punch(0.18, 150, 80, 0.02, 0.06, drive=1.2)),
    ]
    return finish(mix(0.32, layers), -3.0 - 6 * warm, lowpass=11000 - 7500 * warm)


def clay_squish(take, rng):
    # "a wet, dense press with no tail at all ... a little suction on the release"
    t = axis(0.3)
    press = filt(noise(0.3, rng), "low", 850) * envelope(t, 0.004, 0.045)
    squelch = np.sin(phase(150 - 50 * t / 0.3) + 2.5 * np.sin(phase(np.full_like(t, 37.0)))) * envelope(t, 0.005, 0.04)
    suction = band(noise(0.04, rng), 600, 2400) * envelope(axis(0.04), 0.004, 0.008)
    return finish(mix(0.3, [
        (0.000, 1.0, taper(peak(press))),
        (0.000, 0.5, taper(peak(squelch))),
        (rng.uniform(0.15, 0.2), 0.3, peak(suction)),
    ]), -5.0, lowpass=4500)


def cloud_hush(take, rng):
    # "a breath. Airy, wide, with no attack and no defined end - white noise shaped like an exhale"
    d = rng.uniform(0.6, 0.85)
    t = axis(d)
    shape = np.sin(np.pi * np.clip(t / d, 0, 1)) ** 1.6
    air = band(noise(d, rng), 350, 4200) * shape
    return finish(taper(peak(air), 0.4), -13.0, lowpass=6000)


def salt_crunch(take, rng):
    # "a dry, sharp crunch with a lot of high frequency ... duller and quieter each take"
    worn = (take - 1) / 3.0
    grains = crackle(0.26, 2600 - 1800 * worn, 0.06, 2500 - 1200 * worn, 11000 - 6000 * worn, rng)
    return finish(mix(0.28, [
        (0.000, 1.0, grains),
        (0.000, 0.4 + 0.3 * worn, punch(0.1, 200, 110, 0.01, 0.03, drive=1.2)),
    ]), -3.0 - 7 * worn, lowpass=12000 - 6500 * worn)


def lava_crust(take, rng):
    # "a low, continuous hiss with a glassy tick layered on top as the crust forms ... No roaring"
    t = axis(0.6)
    hiss = band(noise(0.6, rng), 1400, 6000) * envelope(t, 0.06, 0.3)
    ticks = [(rng.uniform(0.05, 0.35), 0.35, ring(0.05, [rng.uniform(3200, 4200)], 0.012, rng)) for _ in range(3)]
    return finish(mix(0.62, [(0.0, 0.7, taper(peak(hiss)))] + ticks), -9.0, lowpass=9000)


def oobleck_squelch(take, rng):
    # "a thick, dense squelch with no splash at all ... a dull heavy slap with a short rubbery ring"
    slap = filt(noise(0.06, rng), "low", 700) * envelope(axis(0.06), 0.001, 0.012)
    rubber = ring(0.25, [rng.uniform(200, 240)], 0.07, rng, drop=0.08)
    return finish(mix(0.3, [
        (0.000, 1.0, peak(slap)),
        (0.000, 0.6, punch(0.16, 170, 70, 0.015, 0.05, drive=1.8)),
        (0.004, 0.45, rubber),
    ]), -3.0, lowpass=3500)


def snow_pack(take, rng):
    # "a soft compressing squeak - the high, almost rubbery noise cold snow makes under a boot - with a
    # dull thud under it. No crunch"
    t = axis(0.16)
    f0 = rng.uniform(900, 1200)
    squeak = np.sin(phase(f0 + 350 * np.sin(2 * np.pi * 38 * t) + 200 * t / 0.16)) * envelope(t, 0.01, 0.05)
    squeak *= 1 + 0.4 * np.sign(np.sin(2 * np.pi * 60 * t))
    return finish(mix(0.4, [
        (0.03, 0.45, taper(peak(band(squeak, 700, 4000)))),
        (0.000, 0.8, punch(0.25, 140, 60, 0.02, 0.07, drive=1.1)),
        (0.000, 0.25, taper(peak(filt(noise(0.2, rng), "low", 500) * envelope(axis(0.2), 0.01, 0.05)))),
    ]), -6.0, lowpass=7000)


MATERIAL_EVENTS = [
    ("iceCrack", ice_crack), ("jelloWobble", jello_wobble), ("leafBrush", leaf_brush),
    ("foamCompress", foam_compress), ("switchClack", switch_clack), ("legoClick", lego_click),
    ("charcoalSnap", charcoal_snap), ("chocolateSnap", chocolate_snap), ("claySquish", clay_squish),
    # (lavaCrust is written by gen_ending_sfx.py now: heavier and hotter. Not here, or a re-run would
    # put the old dry hiss back over it.)
    ("cloudHush", cloud_hush), ("saltCrunch", salt_crunch),
    ("ooblSquelch", oobleck_squelch), ("snowPack", snow_pack),
]


# ---------------------------------------------------------------- the gate chamber's three
def gate_groan(rng):
    """Outfall 3 going up: a low iron grind, a screw thread shrieking faintly over it, and clanks."""
    d = 9.0
    t = axis(d)
    base = 38 + 3 * np.sin(2 * np.pi * 0.7 * t) + rng.standard_normal(len(t)).cumsum() / SR * 3
    grind = np.sign(np.sin(phase(base))) * 0.5 + np.sin(phase(base * 2.01)) * 0.3
    grind = filt(grind, "low", 500)
    scrape = band(noise(d, rng), 380, 1100) * (0.5 + 0.5 * np.sin(2 * np.pi * 1.3 * t) ** 2)
    layers = [(0.0, 0.9, peak(grind)), (0.0, 0.35, peak(scrape))]
    for k in range(7):
        layers.append((rng.uniform(0.3, d - 0.6), 0.5, punch(0.4, 120, 45, 0.03, 0.12, drive=2.0)))
    swell = np.clip(t / 0.8, 0, 1) * np.clip((d - t) / 1.0, 0, 1)
    return finish(mix(d, layers) * swell, -2.0, lowpass=4000)


def water_rush(rng):
    """The bay going out through the gate: deep brown noise, surging slowly, with a hiss of spray."""
    d = 10.0
    t = axis(d)
    brown = np.cumsum(noise(d, rng))
    brown = filt(brown - np.mean(brown), "high", 25, order=2)
    body = filt(brown, "low", 900)
    spray = band(noise(d, rng), 2500, 8000)
    surge = 0.75 + 0.25 * np.sin(2 * np.pi * 0.23 * t) + 0.1 * np.sin(2 * np.pi * 0.61 * t)
    fade = np.clip(t / 0.05, 0, 1) * np.clip((d - t) / 0.05, 0, 1)
    return finish((0.85 * peak(body) + 0.2 * peak(spray)) * surge * fade, -3.0, lowpass=9000)


def siren(rng):
    """The flood siren, far off and above: a rise, a long hold, a fall, heard through a lot of water."""
    d = 11.0
    t = axis(d)
    rise, hold = 3.0, 4.5
    freq = np.where(t < rise, 170 + 330 * (t / rise) ** 0.7,
                    np.where(t < rise + hold, 500 + 6 * np.sin(2 * np.pi * 0.4 * t),
                             500 - 330 * np.clip((t - rise - hold) / (d - rise - hold), 0, 1) ** 1.3))
    tone = np.sin(phase(freq)) + 0.45 * np.sin(phase(freq * 2)) + 0.2 * np.sin(phase(freq * 3))
    level = np.clip(t / 1.2, 0, 1) * np.clip((d - t) / 2.0, 0, 1)
    far = filt(tone * level, "low", 1400)
    # A long smear, as if heard down a shaft: the signal plus a few decaying echoes of itself.
    out = far.copy()
    for k, lag in enumerate((0.23, 0.51, 0.87, 1.3)):
        shift = int(SR * lag)
        out[shift:] += far[:-shift] * (0.5 ** (k + 1))
    return finish(out, -6.0, lowpass=2500)


def maw_rumble(rng):
    """The thing at the bottom of the shaft, breathing: a slow sub-bass swell with a wet growl in it."""
    d = 7.0
    t = axis(d)
    breath = np.clip(np.sin(np.pi * t / d), 0, 1) ** 1.5
    base = 31 + 4 * np.sin(2 * np.pi * 0.19 * t)
    sub = np.sin(phase(base)) + 0.5 * np.sin(phase(base * 1.98))
    growl = band(noise(d, rng), 60, 260) * (0.6 + 0.4 * np.sin(2 * np.pi * 11 * t + np.sin(2 * np.pi * 0.7 * t)))
    wet = band(noise(d, rng), 300, 1400) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.37 * t)) ** 3
    return finish((peak(sub) * 0.9 + peak(growl) * 0.45 + peak(wet) * 0.12) * breath, -2.0, lowpass=1800)


def jaws_shut(rng):
    """The jaws closing: a vast thud, bone on bone, and a wet crunch of water after it. Nothing gory."""
    return finish(mix(2.6, [
        (0.000, 1.0, punch(2.4, 70, 22, 0.09, 0.7, drive=3.0)),
        (0.000, 0.7, peak(filt(noise(0.5, rng), "low", 900) * envelope(axis(0.5), 0.001, 0.07))),
        (0.004, 0.45, ring(0.5, [rng.uniform(140, 170), rng.uniform(310, 350)], 0.12, rng, drop=0.1)),
        (0.060, 0.35, peak(band(noise(1.2, rng), 400, 3000) * envelope(axis(1.2), 0.01, 0.25))),
    ]), -1.0, lowpass=5000)


def heartbeat(rng):
    """A heartbeat heard from inside something: two soft thumps, slow, muffled, looped by the scene."""
    beat = punch(0.3, 60, 38, 0.03, 0.08, drive=1.3)
    return finish(mix(1.4, [(0.0, 1.0, beat), (0.26, 0.7, beat)]), -4.0, lowpass=400)


def secret_sting(rng):
    """Finding something: a slow swell that stops short, and one low, detuned note under it."""
    d = 3.6
    t = axis(d)
    swell = band(noise(d, rng), 500, 3000) * np.clip(t / 2.2, 0, 1) ** 3 * (t < 2.2)
    note = (np.sin(phase(np.full_like(t, 110.0))) + np.sin(phase(np.full_like(t, 110.9))) * 0.8
            + 0.3 * np.sin(phase(np.full_like(t, 164.8)))) * envelope(np.maximum(t - 2.2, 0), 0.01, 0.9) * (t >= 2.2)
    return finish(0.5 * peak(swell) + peak(note), -4.0, lowpass=4000)


STORY_SOUNDS = [("GateGroan", gate_groan), ("WaterRush", water_rush), ("Siren", siren), ("MawRumble", maw_rumble),
                ("JawsShut", jaws_shut), ("Heartbeat", heartbeat), ("SecretSting", secret_sting)]


# ---------------------------------------------------------------- the levels' ambience, as seamless loops
AMBIENCE = HERE / "ambience"


def seamless(make, seconds, rng, fade=2.0):
    """`make(duration, rng)` rendered a little long, and its tail crossfaded into its head, so the loop
    point is inaudible: sample L-1 runs straight on into sample 0."""
    x = make(seconds + fade, rng)
    n, length = int(SR * fade), int(SR * seconds)
    w = np.linspace(0.0, 1.0, n)
    out = x[:length].copy()
    out[:n] = x[:n] * w + x[length:length + n] * (1 - w)
    return out


def pink(duration, rng):
    white = noise(duration, rng)
    spectrum = np.fft.rfft(white)
    f = np.fft.rfftfreq(len(white), 1 / SR)
    spectrum[1:] /= np.sqrt(f[1:])
    spectrum[0] = 0
    return peak(np.fft.irfft(spectrum, len(white)))


def shore_sea(duration, rng):
    """The sea on the sands a long way down: waves arriving every six to nine seconds, hissing back."""
    t = axis(duration)
    y = 0.25 * filt(pink(duration, rng), "low", 500)
    at = rng.uniform(0, 3)
    while at < duration:
        local = t - at
        crash = np.where(local >= 0, np.clip(local / 1.2, 0, 1) ** 2 * np.exp(-np.maximum(local - 1.2, 0) / 2.2), 0)
        y += crash * band(noise(duration, rng), 300, 5000) * rng.uniform(0.6, 1.0)
        at += rng.uniform(6, 9)
    return finish(y, -6.0, lowpass=4500)


def roof_wind(duration, rng):
    """Wind across a roof high over the sea: gusts, and a faint whistle that comes and goes."""
    t = axis(duration)
    gust = 0.5 + 0.3 * np.sin(2 * np.pi * 0.08 * t) + 0.2 * np.sin(2 * np.pi * 0.21 * t + 1)
    body = filt(pink(duration, rng), "band", [150, 1400]) * gust
    whistle = band(noise(duration, rng), 820, 980, order=6) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.05 * t)) ** 4
    return finish(peak(body) + 0.25 * peak(whistle), -6.0, lowpass=6000)


def party_far(duration, rng):
    """The party through a wall: the same four chords, slow, muffled, a little seasick, and a thump."""
    t = axis(duration)
    wobble = 1 + 0.004 * np.sin(2 * np.pi * 0.3 * t)
    chords = [(220.0, 277.2, 329.6), (196.0, 246.9, 293.7), (174.6, 220.0, 261.6), (196.0, 246.9, 311.1)]
    y = np.zeros_like(t)
    for index, chord in enumerate(chords * 4):
        start = index * duration / 16
        local = t - start
        on = (local >= 0) & (local < duration / 16 + 0.3)
        for f in chord:
            y += on * np.sign(np.sin(phase(np.full_like(t, f) * wobble))) * 0.2 * np.clip(local / 0.3, 0, 1)
    beat = np.zeros_like(t)
    for k in range(int(duration * 1.6)):
        start = int(SR * k / 1.6)
        kick = punch(0.3, 90, 45, 0.02, 0.06)
        beat[start:start + len(kick)] += kick[:len(beat) - start]
    return finish(filt(y, "low", 600) + 0.8 * filt(beat, "low", 200), -8.0, lowpass=700)


def harbour_night(duration, rng):
    """The harbour at eight minutes to midnight: water lapping at stone, and a bell on a buoy, far off."""
    t = axis(duration)
    y = 0.15 * filt(pink(duration, rng), "low", 300)
    at = 0.0
    while at < duration:
        lap = filt(noise(0.5, rng), "band", [200, 1200]) * envelope(axis(0.5), 0.05, 0.12)
        start = int(SR * at)
        y[start:start + len(lap)] += peak(lap)[:len(y) - start] * rng.uniform(0.3, 0.7)
        at += rng.uniform(0.7, 2.0)
    for start_s in np.arange(rng.uniform(1, 4), duration, rng.uniform(7, 10)):
        bell = ring(4.0, [410, 1020, 1480, 2190], 1.4, rng)
        start = int(SR * start_s)
        y[start:start + len(bell)] += 0.18 * filt(bell, "low", 2000)[:len(y) - start]
    return finish(y, -6.0, lowpass=3000)


def baths_hum(duration, rng):
    """The baths: an old tube light's hum and buzz, air moving through tiled rooms, and water somewhere."""
    t = axis(duration)
    hum = np.sin(2 * np.pi * 50 * t) + 0.5 * np.sin(2 * np.pi * 100.3 * t) + 0.25 * np.sin(2 * np.pi * 150 * t)
    buzz = band(np.sign(np.sin(2 * np.pi * 100 * t)) + 0.05 * noise(duration, rng), 1800, 6000)
    flicker = 0.7 + 0.3 * (np.sin(2 * np.pi * 0.13 * t) > 0.92)
    air = filt(pink(duration, rng), "band", [80, 900])
    water = band(noise(duration, rng), 1500, 4000) * (0.3 + 0.7 * np.sin(2 * np.pi * 0.09 * t) ** 8)
    return finish(0.5 * peak(hum) + 0.12 * peak(buzz) * flicker + 0.5 * peak(air) + 0.15 * peak(water), -8.0,
                  lowpass=7000)


def hold_drone(duration, rng):
    """The Hold itself: very low, two tones a little apart so they beat, and a breath of voices far off
    that never quite become words. Meant to be noticed only when it stops."""
    t = axis(duration)
    low = np.sin(2 * np.pi * 41.0 * t) + np.sin(2 * np.pi * 41.35 * t) + 0.4 * np.sin(2 * np.pi * 61.7 * t)
    voices = band(noise(duration, rng), 280, 340, order=6) + 0.7 * band(noise(duration, rng), 760, 860, order=6)
    voices *= (0.5 + 0.5 * np.sin(2 * np.pi * 0.045 * t + 0.6)) ** 3
    return finish(peak(low) + 0.18 * peak(voices), -6.0, lowpass=1500)


AMBIENCE_BEDS = [("ShoreSea", shore_sea, 26), ("RoofWind", roof_wind, 20), ("PartyFar", party_far, 16),
                 ("HarbourNight", harbour_night, 24), ("BathsHum", baths_hum, 20), ("HoldDrone", hold_drone, 30)]

if __name__ == "__main__":
    print("writing %s" % MATERIALS)
    for event, make in MATERIAL_EVENTS:
        for take in range(1, 5):
            rng = np.random.default_rng(zlib.crc32(event.encode()) + take)
            write(MATERIALS, "%s_%d.wav" % (event, take), make(take, rng))
    print("writing %s" % STORY)
    for name, make in STORY_SOUNDS:
        rng = np.random.default_rng(zlib.crc32(name.encode()))
        write(STORY, "%s.wav" % name, make(rng))
    print("writing %s" % AMBIENCE)
    for name, make, seconds in AMBIENCE_BEDS:
        rng = np.random.default_rng(zlib.crc32(name.encode()))
        write(AMBIENCE, "%s.wav" % name, seamless(make, seconds, rng))
