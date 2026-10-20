"""The Needoh's and the lava crust's takes, as you liked them (the twenty-first pass's, kept unchanged).

    python audio/gen_needoh_lava_sfx.py

Writes audio/materials/needohSquish_1..4.wav and lavaCrust_1..4.wav, for SoundService.MaterialSounds. These were made
by gen_ending_sfx.py in the twenty-first pass; when that file was remade (the ninety-sixth pass) these two were kept as
they were, because you liked them, and their makers moved here word for word, so a re-run writes the same files byte
for byte. Seeded from each event's name and take.
"""
import pathlib
import sys
import zlib

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_button_sfx import SR, axis, envelope, filt, finish, mix, peak, phase, punch, taper  # noqa: E402,F401
from gen_material_sfx import MATERIALS, band, noise, ring, seamless, write  # noqa: E402,F401


def brown(duration, rng):
    """Deep rumbling noise: white noise summed, its drift taken out."""
    b = np.cumsum(noise(duration, rng))
    return filt(b - np.mean(b), "high", 20, order=2)


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


if __name__ == "__main__":
    print("writing %s" % MATERIALS)
    for event, make in (("needohSquish", needoh_squish), ("lavaCrust", lava_crust)):
        for take in range(1, 5):
            rng = np.random.default_rng(zlib.crc32(event.encode()) + take + 1800)
            write(MATERIALS, "%s_%d.wav" % (event, take), make(take, rng))
