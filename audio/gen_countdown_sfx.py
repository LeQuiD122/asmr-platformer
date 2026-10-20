"""The lobby's countdown, as sounds that belong to this game (the ninety-first pass, from your second test: "improve
the countdown of 10 sec sounds in the lobby, make them better").

    python audio/gen_countdown_sfx.py

Writes audio/story/CountdownTock_x3.wav: three takes, each in its own one-second slot (HubVoteService plays slot k from
k seconds):

  0  the tock      each second: a soft wooden tock, a block of warm wood tapped with a felt mallet
  1  the last three  the same wood a step brighter, a quick double tap, so the end can be heard closing in
  2  the chime     as it runs out: two warm marimba notes, a fifth apart, the second a little later

It was the engine's electronic ping, high and bright: the wrong kind of sound for a game of soft materials. Nothing here
is a bare tone: the wood is quickly damped resonances under a felt thump, and the marimba's notes are mallet hits that
ring and fade, with the bar's own overtone.
"""
import pathlib
import sys

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_button_sfx import SR, axis, filt, peak  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
SLOT = 1.0


def wood(pitch, rng, length=0.35):
    """A wooden tock: a felt-soft thump under two quickly damped resonances of a block, and a breath of knock."""
    t = axis(length)
    out = np.zeros_like(t)
    for ratio, decay, level in ((1.0, 0.045, 1.0), (2.76, 0.018, 0.35), (5.4, 0.008, 0.08)):
        out += level * np.sin(2 * np.pi * pitch * ratio * t + rng.uniform(0, 6)) * np.exp(-t / decay)
    knock = filt(rng.standard_normal(len(t)), "band", [600, 2400]) * np.exp(-t / 0.004)
    thump = np.sin(2 * np.pi * 140 * t) * np.exp(-t / 0.03)
    attack = np.clip(t / 0.0015, 0, 1)
    return (out + 0.12 * peak(knock) + 0.35 * thump) * attack


def marimba(freq, rng, length=0.9):
    """A marimba note: the bar's fundamental and its fourth-harmonic overtone, struck with a soft mallet, fading."""
    t = axis(length)
    body = np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.42)
    overtone = 0.25 * np.sin(2 * np.pi * freq * 3.93 * t) * np.exp(-t / 0.08)
    mallet = filt(rng.standard_normal(len(t)), "band", [300, 1800]) * np.exp(-t / 0.006) * 0.12
    attack = np.clip(t / 0.003, 0, 1)
    return (body + overtone + mallet) * attack


def finish(x, db):
    x = filt(x, "high", 60, order=2)
    x = filt(x, "low", 6000)
    x = peak(x) * 10 ** (db / 20)
    fade = int(SR * 0.01)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


def place(out, x, slot, at=0.0):
    start = int(SR * (slot * SLOT + at))
    end = min(start + len(x), int(SR * (slot + 1) * SLOT) - int(SR * 0.05))
    out[start:end] += x[: end - start]


if __name__ == "__main__":
    rng = np.random.default_rng(9100)
    out = np.zeros(int(SR * SLOT * 3))
    place(out, finish(wood(620, rng), -6.0), 0)
    double = np.zeros(int(SR * 0.5))
    first = wood(780, rng, 0.3)
    second = wood(780, rng, 0.3) * 0.7
    double[: len(first)] += first
    double[int(SR * 0.085): int(SR * 0.085) + len(second)] += second[: len(double) - int(SR * 0.085)]
    place(out, finish(double, -5.0), 1)
    chime = np.zeros(int(SR * 0.94))
    a, b = marimba(523.25, rng, 0.9), marimba(783.99, rng, 0.78)
    chime[: len(a)] += a
    chime[int(SR * 0.12): int(SR * 0.12) + len(b)] += 0.85 * b[: len(chime) - int(SR * 0.12)]
    place(out, finish(chime, -4.0), 2)
    path = HERE / "story" / "CountdownTock_x3.wav"
    wavfile.write(path, SR, (np.clip(out, -1, 1) * 32767).astype(np.int16))
    print("wrote", path)
