"""The keypad's sounds, synthesised: electric, a little explosive, futuristic, and satisfying.

    python audio/gen_button_sfx.py

Writes 16-bit mono WAVs into audio/buttons/, several takes per event so a keypad never repeats the
same file twice running (AudioService picks a different take each time). Upload them in Studio
(Asset Manager -> Import, or the Creator Hub), then paste the ids into SOUND_IDS_BY_EVENT in
src/Client/Services/AudioService.lua under the event named in each file:

    button_clicky_*.wav   -> buttonClick     the cyan fast lane: a zap with a punch under it
    button_linear_*.wav   -> buttonLinear    violet: a softer charged "vwomp"
    button_tactile_*.wav  -> buttonTactile   pink: a double pulse, the bump in the travel
    button_release_*.wav  -> buttonRelease   any switch coming back up: a short rising "pew"
    button_combo_*.wav    -> buttonCombo     three clicky in a row: charge, discharge, shimmer
    button_circuit_*.wav  -> buttonCircuit   the whole lane: power-up, overload, sparkling resolve

WHAT MAKES IT SATISFYING RATHER THAN HARSH, in one place, because every sound here is built from
the same four ideas:

  * a PUNCH -- a sine that drops in pitch in a few tens of milliseconds, soft-clipped. It is most
    of what "explosive" means to the ear, and it lives low, where nothing is shrill;
  * a ZAP -- FM with a falling carrier and a decaying index, so it starts as a bright crackle of
    sidebands and collapses into a tone, which is what electricity sounds like in every film;
  * a CRACKLE tail -- sparse impulses, band-passed, thinning out: the arcing after the snap;
  * everything decays FAST and is low-passed at the end, because a satisfying click is the one
    that is already gone when you want the next one.
"""
import pathlib
import zlib

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
OUT = pathlib.Path(__file__).resolve().parent / "buttons"


# ---------------------------------------------------------------- building blocks
def axis(duration):
    return np.arange(int(SR * duration)) / SR


def envelope(t, attack, decay):
    rise = np.clip(t / max(attack, 1e-6), 0.0, 1.0)
    return rise * np.exp(-np.maximum(t - attack, 0.0) / decay)


def phase(freq):
    return 2 * np.pi * np.cumsum(freq) / SR


def taper(y, fraction=0.25):
    """Every layer ends at silence. A layer cut off while it still has amplitude clicks, and the
    first render of the release chirp did exactly that: a clean sweep, then a hard edge at 80 ms."""
    n = max(2, int(len(y) * fraction))
    y = y.copy()
    y[-n:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, n))
    return y


def filt(x, kind, cutoff, order=4):
    sos = signal.butter(order, cutoff, btype=kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def peak(x):
    return x / (np.max(np.abs(x)) + 1e-12)


def zap(duration, start, end, sweep, index, index_decay, decay, ratio=1.41):
    """FM with a falling carrier: a bright crackle of sidebands collapsing into a tone."""
    t = axis(duration)
    carrier = end + (start - end) * np.exp(-t / sweep)
    depth = index * np.exp(-t / index_decay)
    y = np.sin(phase(carrier) + depth * np.sin(phase(carrier * ratio)))
    return taper(y * envelope(t, 0.0008, decay))


def crush(x, levels):
    """Bit-crushed copy, for a little digital grit on the attack."""
    return np.round(x * levels) / levels


def punch(duration, high, low, sweep, decay, drive=1.6):
    """A pitch-dropping sine, soft-clipped: the thump under the zap."""
    t = axis(duration)
    freq = low + (high - low) * np.exp(-t / sweep)
    y = np.sin(phase(freq)) * envelope(t, 0.002, decay)
    return taper(np.tanh(y * drive) / np.tanh(drive))


def crackle(duration, rate, decay, low, high, rng):
    """Sparse arcing impulses, thinning out, band-passed into the sizzle range."""
    n = int(SR * duration)
    t = np.arange(n) / SR
    chance = rate * np.exp(-t / decay) / SR
    spikes = (rng.random(n) < chance) * rng.choice([-1.0, 1.0], n) * rng.uniform(0.35, 1.0, n)
    tail = np.exp(-np.arange(28) / 3.5)
    y = np.convolve(spikes, tail, mode="same")
    return peak(filt(y, "band", [low, high]))


def click(duration, rng):
    t = axis(duration)
    return taper(peak(filt(rng.standard_normal(len(t)), "high", 2600)) * np.exp(-t / 0.0014))


def chirp(duration, start, end, decay, index=1.2):
    """An exponential sweep UP: the release, and the charging before a discharge."""
    t = axis(duration)
    freq = start * (end / start) ** np.clip(t / duration, 0, 1)
    y = np.sin(phase(freq) + index * np.sin(phase(freq * 2.01)))
    return taper(y * envelope(t, 0.001, decay), 0.45)


def shimmer(duration, freqs, attack, decay, vibrato=6.5, cents=7, stagger=0.0):
    """A soft chord or arpeggio of sines with a slow vibrato: the futuristic resolve."""
    t = axis(duration)
    y = np.zeros_like(t)
    for index, freq in enumerate(freqs):
        start = stagger * index
        local = np.maximum(t - start, 0.0)
        wobble = freq * (2 ** (cents / 1200 * np.sin(2 * np.pi * vibrato * local)))
        voice = np.sin(phase(wobble)) * envelope(local, attack, decay) * (t >= start)
        y += voice
    return taper(peak(y), 0.3)


def hum(duration, freq, decay):
    """A low mains-like buzz: three harmonics with a tremolo."""
    t = axis(duration)
    y = sum(np.sin(2 * np.pi * freq * k * t) / k for k in (1, 2, 3))
    tremolo = 0.75 + 0.25 * np.sin(2 * np.pi * 9 * t)
    return taper(peak(y) * tremolo * envelope(t, 0.004, decay))


def mix(total, layers):
    """(offset seconds, gain, signal) -> one buffer."""
    out = np.zeros(int(SR * total))
    for offset, gain, layer in layers:
        start = int(SR * offset)
        end = min(len(out), start + len(layer))
        out[start:end] += gain * layer[: end - start]
    return out


def finish(x, level_db, lowpass=12500):
    x = filt(x, "low", lowpass)
    x = filt(x, "high", 28, order=2)          # nothing below hearing to waste headroom on
    x = np.tanh(peak(x) * 1.25) / np.tanh(1.25)  # gentle glue, never a hard clip
    fade = int(SR * 0.012)
    x[-fade:] *= np.linspace(1, 0, fade)
    return peak(x) * (10 ** (level_db / 20))


def write(name, x):
    OUT.mkdir(parents=True, exist_ok=True)
    wavfile.write(OUT / name, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
    rms = np.sqrt(np.mean(x ** 2))
    print("  %-26s %5.0f ms  peak %5.1f dB  rms %5.1f dB" % (
        name, 1000 * len(x) / SR, 20 * np.log10(np.max(np.abs(x))), 20 * np.log10(rms + 1e-12)))


# ---------------------------------------------------------------- the sounds
def clicky(take, rng):
    start = rng.uniform(1700, 2300)
    body = zap(0.30, start, rng.uniform(160, 220), 0.034, rng.uniform(6, 8.5), 0.05, 0.06)
    return finish(mix(0.42, [
        (0.000, 0.45, click(0.02, rng)),
        (0.002, 0.42, body),
        (0.002, 0.18, crush(body, 12)),
        (0.000, 0.95, punch(0.30, rng.uniform(140, 165), rng.uniform(48, 58), 0.028, 0.09)),
        (0.010, 0.30, crackle(0.36, rng.uniform(220, 300), 0.10, 2200, 8000, rng)),
        (0.004, 0.10, zap(0.10, start * 1.8, start * 2.6, 0.06, 1.0, 0.1, 0.05)),
    ]), -1.0)


def linear(take, rng):
    return finish(mix(0.34, [
        (0.000, 0.50, zap(0.26, rng.uniform(820, 980), rng.uniform(150, 180), 0.06, 2.0, 0.08, 0.08)),
        (0.000, 0.70, punch(0.26, 120, 46, 0.035, 0.08, drive=1.3)),
        (0.010, 0.13, hum(0.2, rng.uniform(105, 118), 0.12)),
        (0.020, 0.16, crackle(0.26, 80, 0.08, 1800, 6500, rng)),
    ]), -3.0, lowpass=10000)


def tactile(take, rng):
    return finish(mix(0.36, [
        (0.000, 0.30, click(0.02, rng)),
        (0.000, 0.40, zap(0.05, rng.uniform(1300, 1500), 240, 0.02, 4, 0.03, 0.03)),
        (0.055, 0.50, zap(0.10, rng.uniform(1050, 1200), 200, 0.03, 5, 0.04, 0.045)),
        (0.055, 0.80, punch(0.24, 135, 50, 0.03, 0.08)),
        (0.060, 0.24, crackle(0.24, 130, 0.07, 2000, 7000, rng)),
    ]), -2.0)


def release(take, rng):
    top = rng.uniform(1800, 2200)
    return finish(mix(0.15, [
        (0.000, 0.55, chirp(0.12, rng.uniform(330, 400), top, 0.035)),
        (0.000, 0.20, click(0.015, rng)),
        (0.010, 0.18, crackle(0.12, 70, 0.05, 2500, 8000, rng)),
    ]), -5.0)


def combo(take, rng):
    charge = [chirp(0.05, 480 * k, 1500 * k, 0.04) for k in (1.0, 1.26, 1.5)]
    body = zap(0.5, rng.uniform(2600, 3000), 110, 0.05, 9, 0.07, 0.12)
    boom = filt(rng.standard_normal(int(SR * 0.5)), "low", 2400) * envelope(axis(0.5), 0.002, 0.13)
    return finish(mix(1.05, [
        (0.000, 0.32, charge[0]),
        (0.045, 0.32, charge[1]),
        (0.090, 0.34, charge[2]),
        (0.130, 0.55, body),
        (0.130, 0.20, crush(body, 10)),
        (0.130, 0.42, peak(boom)),
        (0.130, 1.00, punch(0.7, 95, 32, 0.08, 0.30, drive=2.2)),
        (0.150, 0.40, crackle(0.75, 420, 0.22, 2000, 8500, rng)),
        (0.200, 0.20, shimmer(0.8, [880.0, 1108.7, 1318.5], 0.06, 0.34)),
    ]), -1.0)


def circuit(take, rng):
    t = axis(0.3)
    rise = 180 * (1900 / 180) ** (t / 0.3)
    powerup = np.sin(phase(rise) + (5 * t / 0.3) * np.sin(phase(rise * 1.5))) * (t / 0.3) ** 1.5
    powerup *= 0.7 + 0.3 * np.sin(2 * np.pi * (8 + 30 * t / 0.3) * t)
    boom = filt(rng.standard_normal(int(SR * 0.9)), "low", 1600) * envelope(axis(0.9), 0.002, 0.24)
    layers = [
        (0.000, 0.40, powerup),
        (0.290, 0.55, peak(boom)),
        (0.290, 1.00, punch(1.1, 78, 27, 0.12, 0.55, drive=2.6)),
        (0.290, 0.60, zap(0.6, rng.uniform(3000, 3400), 90, 0.06, 10, 0.08, 0.16)),
        (0.310, 0.45, crackle(1.15, 520, 0.36, 1800, 9000, rng)),
        (0.360, 0.18, shimmer(1.1, [1046.5, 1318.5, 1568.0, 2093.0], 0.02, 0.42, stagger=0.065)),
    ]
    for _ in range(5):
        layers.append((rng.uniform(0.33, 0.95), 0.22,
                       zap(0.08, rng.uniform(2000, 3000), 300, 0.02, 5, 0.03, rng.uniform(0.018, 0.035))))
    return finish(mix(1.5, layers), -1.0)


EVENTS = [
    ("button_clicky", clicky, 4),
    ("button_linear", linear, 3),
    ("button_tactile", tactile, 3),
    ("button_release", release, 3),
    ("button_combo", combo, 2),
    ("button_circuit", circuit, 2),
]

if __name__ == "__main__":
    print("writing %s" % OUT)
    for stem, make, takes in EVENTS:
        for take in range(1, takes + 1):
            # Seeded from the name, so re-running writes the same takes rather than new ones.
            rng = np.random.default_rng(zlib.crc32(stem.encode()) + take)
            write("%s_%d.wav" % (stem, take), make(take, rng))
