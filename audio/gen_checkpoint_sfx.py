"""A checkpoint reached, as a sound that belongs to this game (the hundred-and-thirty-eighth pass: "polishing the game").

    python audio/gen_checkpoint_sfx.py

Writes audio/story/CheckpointChime_x3.wav: three takes, each in its own SLOT seconds (RunFeel plays one at random, never
the same twice running, as you reach a checkpoint further on than any before in the run):

  each take  two low marimba bars struck with felt, a fifth apart, the second a breath after the first, and under them
             the air the slab lets out as you land on it

Low and soft on purpose (the sound taste: low to mid, soft attacks, never a ping): the notes sit an octave under the
countdown's chime (gen_countdown_sfx.py), which is the same wood, so the lobby and the run sound like one place. Nothing
here is a bare tone: each bar is a mallet hit that rings and fades, with the bar's own overtone.
"""
import pathlib
import sys

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_button_sfx import SR, axis, filt, peak  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
SLOT = 1.5
# The three takes' two bars (Hz): C and G, B flat and F, D and A, from middle C up (low enough to be soft, high enough
# for a phone's speaker to carry).
DYADS = ((261.63, 392.00), (233.08, 349.23), (293.66, 440.00))


def bar(freq, rng, length=1.3):
    """One marimba bar under a felt mallet: its fundamental ringing, its fourth-harmonic overtone gone at once, a soft
    thump of felt, and a little of the bar's second partial."""
    t = axis(length)
    body = np.sin(2 * np.pi * freq * t + rng.uniform(0, 6)) * np.exp(-t / 0.5)
    second = 0.12 * np.sin(2 * np.pi * freq * 2.01 * t) * np.exp(-t / 0.16)
    overtone = 0.16 * np.sin(2 * np.pi * freq * 3.93 * t) * np.exp(-t / 0.05)
    felt = filt(rng.standard_normal(len(t)), "band", [220, 1100]) * np.exp(-t / 0.009) * 0.1
    attack = np.clip(t / 0.005, 0, 1)
    return (body + second + overtone + felt) * attack


def breath(rng, length=0.6):
    """The air out of the slab: a soft hush, rising and falling, low in the band."""
    t = axis(length)
    air = filt(rng.standard_normal(len(t)), "band", [280, 1400])
    shape = np.clip(t / 0.09, 0, 1) * np.exp(-np.maximum(t - 0.09, 0) / 0.16)
    return peak(air) * shape


def take(f1, f2, rng):
    out = np.zeros(int(SR * (SLOT - 0.08)))
    a, b = bar(f1, rng), bar(f2, rng, 1.2)
    out[: len(a)] += a[: len(out)]
    late = int(SR * 0.075)
    out[late: late + len(b)] += 0.75 * b[: len(out) - late]
    air = breath(rng)
    out[: len(air)] += 0.05 * air
    out = filt(out, "high", 70, order=2)
    out = filt(out, "low", 4200)
    fade = int(SR * 0.25)
    out[-fade:] *= np.linspace(1, 0, fade) ** 2
    return out


if __name__ == "__main__":
    rng = np.random.default_rng(13800)
    out = np.zeros(int(SR * SLOT * len(DYADS)))
    for k, (f1, f2) in enumerate(DYADS):
        x = peak(take(f1, f2, rng)) * 10 ** (-5.5 / 20)
        start = int(SR * SLOT * k)
        out[start: start + len(x)] += x
    path = HERE / "story" / "CheckpointChime_x3.wav"
    wavfile.write(path, SR, (np.clip(out, -1, 1) * 32767).astype(np.int16))
    print("wrote", path)
