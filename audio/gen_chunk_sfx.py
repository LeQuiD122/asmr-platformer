"""Six chunk sounds remade to the Needoh's and the lava's standard (the seventy-eighth pass, from your first test).

    python audio/gen_chunk_sfx.py              every one
    python audio/gen_chunk_sfx.py saltCrunch   only the families named

Writes four takes each, 16-bit mono WAVs, over the old ones in audio/materials/:

  saltCrunch_1..4    the salt crust ("a bit weird" before: a crackle over a sine thump)
  claySquish_1..4    the clay (the same; its squelch was a buzzing tone)
  cloudHush_1..4     the cloud (one layer of hiss before)
  leafBrush_1..4     the lamb's ear (a thin high hiss before)
  snowPack_1..4      the snow (its squeak was a buzzing tone)
  charcoalSnap_1..4  the charcoal (a dull click before)

WHAT THE TWO YOU LIKED HAVE IN COMMON, and what every one here follows:
  * several layers, each a different part of the thing (the gel, its wobble, the skin, the swell back);
  * nothing made of a plain tone: every body is shaped noise or many tiny grains, so nothing buzzes or beeps;
  * soft high end: nothing harsh above about 8 kHz, and attacks a few milliseconds long, not clicks;
  * four takes that differ in what happens, not only in their random seed (a crust breaking cleanly, in two
    stages, ground slowly, settling), so a crossing never sounds like one sound on repeat.

HOW TO GET THEM IN: as before. In Studio, import the 24 files, put them in SoundService.MaterialSounds named as the
files, and delete the old four of each family first (old and new would otherwise be picked from at random).

Seeded from each file's name, so re-running writes the same takes.
"""
import pathlib
import sys
import zlib

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_button_sfx import SR, axis, envelope, filt, finish, mix, peak, phase, taper  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
MATERIALS = HERE / "materials"


def write(name, x):
    MATERIALS.mkdir(parents=True, exist_ok=True)
    x = np.asarray(x, dtype=float)
    wavfile.write(MATERIALS / name, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))


def noise(duration, rng):
    return rng.standard_normal(max(1, int(SR * duration)))


def band(x, low, high, order=2):
    return filt(x, "band", [low, high], order)


def brown(duration, rng):
    b = np.cumsum(noise(duration, rng))
    return filt(b - np.mean(b), "high", 20, order=2)


def grains(duration, count, rng, low, high, length=(0.002, 0.01), where=(1.2, 3.0), fade=1.0, soft=0.6):
    """Many tiny breaks, each a short burst of noise in its own band: the stuff of a crunch. `where` shapes when they
    fall (a beta distribution, front-loaded by default), `fade` how much quieter the late ones are, `soft` how much
    each grain's attack is rounded (0 a click, 1 a breath)."""
    n = int(SR * duration)
    out = np.zeros(n)
    for _ in range(count):
        at = rng.beta(*where)
        start = int(at * n)
        size = rng.uniform(*length)
        m = max(8, int(SR * size))
        centre = np.exp(rng.uniform(np.log(low), np.log(high)))
        width = centre * rng.uniform(0.35, 0.8)
        lo, hi = max(40.0, centre - width / 2), min(SR / 2 - 200, centre + width / 2)
        g = band(rng.standard_normal(m + 64), lo, hi)[64:]
        tt = np.arange(m) / SR
        attack = max(0.0003, soft * size * 0.3)
        g = g * envelope(tt, attack, size / 3.0)
        level = rng.uniform(0.3, 1.0) * (1 - at) ** fade
        end = min(n, start + m)
        out[start:end] += level * g[: end - start] / (np.max(np.abs(g)) + 1e-9)
    return out


def swell(t, attack, hold, release):
    """Up over `attack`, held, then easing away over `release`: a press, not a hit."""
    up = np.clip(t / max(attack, 1e-6), 0, 1) ** 0.8
    down = np.exp(-np.maximum(t - attack - hold, 0) / release)
    return up * down


# ================================================================ THE SALT CRUST
def salt_crunch(take, rng):
    """A thin crust of salt giving underfoot: a crisp first break, the crust's weight under it (felt, not a tone),
    and grains settling after. Crunchy and clean, like rock salt under a boot: never a hiss, never a thump."""
    d = 0.55
    t = axis(d)
    # The crust's give: a short, dense burst low in the mids, the weight of the step going through.
    give = filt(noise(d, rng), "band", [180, 900], 2) * envelope(t, 0.003, 0.05)
    if take == 1:    # a clean break: one sharp crack, then the grains
        first = grains(0.12, 70, rng, 1500, 7500, (0.0015, 0.006), (1.0, 4.0), 1.2, 0.2)
        settle = grains(0.4, 40, rng, 1200, 5500, (0.002, 0.008), (1.5, 2.5), 1.0, 0.5)
        layers = [(0.0, 0.55, taper(peak(give))), (0.0, 1.0, peak(first)), (0.06, 0.35, peak(settle))]
    elif take == 2:  # in two stages: the top skin, then the crust under it a beat later
        top = grains(0.08, 45, rng, 2000, 7500, (0.0015, 0.005), (1.0, 3.0), 1.0, 0.2)
        under = grains(0.14, 70, rng, 900, 5000, (0.002, 0.008), (1.0, 3.0), 1.0, 0.3)
        layers = [(0.0, 0.8, peak(top)), (0.07, 0.6, taper(peak(give))), (0.07, 1.0, peak(under)),
                  (0.16, 0.3, peak(grains(0.35, 30, rng, 1100, 5000, (0.002, 0.008), (1.5, 2.0), 1.0, 0.5)))]
    elif take == 3:  # ground: the foot turning on it, a slow grind of grains rather than one break
        grind = grains(0.42, 180, rng, 900, 6500, (0.002, 0.007), (1.6, 1.8), 0.4, 0.35)
        grind *= swell(axis(0.42), 0.08, 0.15, 0.12)
        layers = [(0.0, 0.45, taper(peak(give))), (0.0, 1.0, peak(grind))]
    else:            # settling: softer, deeper, the crust already broken here
        soft = grains(0.2, 80, rng, 700, 4500, (0.003, 0.01), (1.2, 3.0), 1.0, 0.5)
        layers = [(0.0, 0.7, taper(peak(give))), (0.0, 0.9, peak(soft)),
                  (0.12, 0.3, peak(grains(0.4, 35, rng, 900, 4000, (0.002, 0.008), (1.5, 2.0), 1.0, 0.6)))]
    return finish(mix(d, layers), -4.0 - 1.5 * (take == 4), lowpass=8500)


# ================================================================ THE CLAY
def clay_squish(take, rng):
    """Thick clay taking a foot: a dense, soft press with a slow give (the clay squeezing out to the edges), a
    tacky crackle as it sticks and unsticks, and a soft wet pull as the foot comes away. Duller and heavier than the
    Needoh, and with no wobble: clay keeps the shape you leave."""
    d = 0.6
    t = axis(d)
    # The press: low, dense, swelling in over a few hundredths, held while the clay spreads, then easing.
    press = filt(brown(d, rng), "low", 520) * swell(t, 0.025, 0.06, 0.09)
    # The spread: mid noise moving down as the clay thins out under the edge.
    spread = filt(noise(d, rng), "band", [260, 1300], 2) * swell(t, 0.04, 0.05, 0.08)
    # The tack: tiny soft ticks as it sticks and lets go, mostly while pressing.
    tack = grains(0.3, 26, rng, 700, 2600, (0.002, 0.006), (1.4, 3.0), 1.0, 0.6)
    # The pull: the foot coming away, a short soft wet smack with a little suck under it.
    pull_at = rng.uniform(0.3, 0.38)
    pull = band(noise(0.06, rng), 450, 1800) * envelope(axis(0.06), 0.004, 0.012)
    suck_t = axis(0.09)
    suck = band(noise(0.09, rng), 220, 700) * envelope(suck_t, 0.02, 0.025)
    layers = [(0.0, 1.0, taper(peak(press))), (0.0, 0.4, taper(peak(spread))), (0.01, 0.22, peak(tack)),
              (pull_at, 0.35, peak(pull)), (pull_at - 0.01, 0.3, peak(suck))]
    if take == 2:    # an air pocket squeezed out: a small soft blurp under the press
        size = 0.09
        b_t = axis(size)
        blurp = band(noise(size, rng), 120, 420) * envelope(b_t, 0.01, 0.03)
        layers.append((rng.uniform(0.05, 0.1), 0.45, peak(blurp)))
    elif take == 3:  # a smear: the foot sliding a little, a longer drag through it
        drag_t = axis(0.25)
        drag = filt(noise(0.25, rng), "band", [300, 1100], 2) * swell(drag_t, 0.06, 0.06, 0.06)
        layers.append((0.08, 0.45, taper(peak(drag))))
    elif take == 4:  # heavy: deeper and shorter, a lot of clay at once
        layers[0] = (0.0, 1.0, taper(peak(filt(brown(d, rng), "low", 380) * swell(t, 0.02, 0.04, 0.07))))
    return finish(mix(d, layers), -5.0, lowpass=4200)


# ================================================================ THE CLOUD
def cloud_hush(take, rng):
    """A cloud holding you for a moment: a soft cushioned fwump (no thud, just air pushed aside) and a long airy
    breath out, its colour falling as it thins. The quietest thing after the lamb's ear."""
    d = rng.uniform(0.75, 1.0)
    t = axis(d)
    cushion = filt(noise(d, rng), "low", 320) * swell(t, 0.03, 0.02, 0.07)
    # The breath: band-passed noise whose band sinks from bright to soft as it fades.
    breath = np.zeros_like(t)
    steps = 12
    chunk = len(t) // steps
    raw = noise(d, rng)
    for k in range(steps):
        lo = 1300 * (1 - k / steps) + 320
        hi = 3400 * (1 - k / steps) + 950
        seg = band(raw, lo, hi)[k * chunk:(k + 1) * chunk]
        breath[k * chunk:k * chunk + len(seg)] = seg
    shape = np.sin(np.pi * np.clip(t / d, 0, 1)) ** (1.2 + 0.3 * take)
    breath = filt(breath, "low", 3800) * shape
    layers = [(0.0, 0.7, taper(peak(cushion))), (0.02, 1.0, taper(peak(breath), 0.4))]
    if take in (2, 4):  # a few soft puffs of the cloud coming apart
        layers.append((0.1, 0.25, peak(grains(d - 0.1, 14, rng, 500, 2200, (0.02, 0.06), (1.5, 2.0), 1.0, 1.0))))
    return finish(mix(d, layers), -13.0, lowpass=4200)


# ================================================================ THE LAMB'S EAR
def leaf_brush(take, rng):
    """Lamb's ear: soft, fuzzy, velvety leaves. A felt-soft brush with no attack at all, the fuzz in it (many tiny
    hairs, not a hiss), and a little warmth underneath. Almost below what you notice; if it sounds like a footstep
    it is wrong."""
    d = rng.uniform(0.45, 0.6)
    t = axis(d)
    shape = swell(t, 0.1, 0.06, 0.12)
    felt = filt(noise(d, rng), "band", [500, 3200], 2) * shape
    # The fuzz: many tiny soft grains, very dense, very quiet, so the brush has a texture.
    fuzz = grains(d, 260, rng, 1200, 4800, (0.004, 0.012), (1.6, 1.6), 0.2, 1.0) * shape
    warm = filt(noise(d, rng), "band", [180, 600], 2) * shape
    tilt = 1.0 if take % 2 else 0.6   # brushing one way, then the other: the colour shifts a little
    return finish(mix(d, [(0.0, 1.0, taper(peak(felt))), (0.0, 0.45 * tilt, taper(peak(fuzz))),
                          (0.0, 0.5, taper(peak(warm)))]), -16.0, lowpass=4800)


# ================================================================ THE SNOW
def snow_pack(take, rng):
    """Cold snow packing down: the squeaky crunch of crystals compressing (a dense rush of soft grains, lower and
    softer than salt) with the squeak of snow on snow in it (a stick-slip creak, not a tone), and a soft whump of the
    pack under it. Fresh powder squeaks least, packed snow most."""
    d = 0.5
    t = axis(d)
    crunch = grains(0.3, 150 + 30 * take, rng, 450, 3400, (0.003, 0.01), (1.5, 2.6), 0.8, 0.5)
    whump = filt(noise(d, rng), "low", 300) * swell(t, 0.02, 0.03, 0.06)
    # The squeak: a train of tiny clicks at a rate that rises and falls (the foot sticking and slipping), each
    # ringing a little in a soft band: a creak, never a beep.
    squeak = np.zeros(int(SR * 0.22))
    when = 0.0
    rate = rng.uniform(170, 240)
    while when < 0.2:
        idx = int(when * SR)
        squeak[idx:idx + 3] += rng.uniform(0.5, 1.0)
        rate *= rng.uniform(0.94, 1.08)
        when += 1.0 / rate
    squeak = band(squeak, 900, 2600) * swell(axis(0.22), 0.03, 0.06, 0.06)
    squeaky = [0.15, 0.35, 0.5, 0.25][take - 1]
    layers = [(0.0, 1.0, peak(crunch)), (0.0, 0.6, taper(peak(whump))), (0.03, squeaky, taper(peak(squeak)))]
    if take == 3:  # a crust on top: a few brighter breaks first
        layers.append((0.0, 0.4, peak(grains(0.06, 25, rng, 1800, 5500, (0.0015, 0.005), (1.0, 3.0), 1.0, 0.3))))
    return finish(mix(d, layers), -6.0, lowpass=6500)


# ================================================================ THE CHARCOAL
def charcoal_snap(take, rng):
    """A lump of charcoal under a foot: a dry, chalky crack (light and hollow, as charcoal is), a crumble of it
    going to pieces, and a soft fall of ash after. On the later takes a little warmth: it lights when stepped on."""
    d = 0.6
    t = axis(d)
    crack = filt(noise(0.05, rng), "band", [700, 4200], 2) * envelope(axis(0.05), 0.0012, 0.012)
    # Its hollowness: a short knock low in the mids, shaped noise (a light, porous thing, not a ringing one).
    knock = filt(noise(0.08, rng), "band", [240, 650], 2) * envelope(axis(0.08), 0.002, 0.02)
    crumble = grains(0.25, 60, rng, 500, 3500, (0.003, 0.012), (1.3, 2.5), 1.0, 0.45)
    ash = grains(0.45, 40, rng, 900, 3000, (0.004, 0.012), (2.0, 2.0), 0.6, 0.9)
    layers = [(0.0, 0.9, taper(peak(crack))), (0.0, 0.6, taper(peak(knock))), (0.015, 0.7, peak(crumble)),
              (0.12, 0.22, peak(ash))]
    if take == 2:    # it breaks in two
        layers.append((rng.uniform(0.05, 0.08), 0.6, taper(peak(filt(noise(0.04, rng), "band", [800, 3800], 2)
                                                                * envelope(axis(0.04), 0.001, 0.01)))))
    if take >= 3:    # and it catches: a soft warm breath of flame under the ash
        flare = filt(noise(0.4, rng), "band", [300, 1400], 2) * swell(axis(0.4), 0.08, 0.08, 0.1)
        layers.append((0.06, 0.28 + 0.08 * (take == 4), taper(peak(flare))))
    return finish(mix(d, layers), -4.5, lowpass=6500)


FAMILIES = [("saltCrunch", salt_crunch), ("claySquish", clay_squish), ("cloudHush", cloud_hush),
            ("leafBrush", leaf_brush), ("snowPack", snow_pack), ("charcoalSnap", charcoal_snap)]

if __name__ == "__main__":
    only = set(sys.argv[1:])
    print("writing %s" % MATERIALS)
    for event, make in FAMILIES:
        if only and event not in only:
            continue
        for take in range(1, 5):
            rng = np.random.default_rng(zlib.crc32(event.encode()) + take + 7800)
            write("%s_%d.wav" % (event, take), make(take, rng))
            print("  %s_%d.wav" % (event, take))
