"""The townsfolk's voices: no words, only the sounds people make as they talk (the eighty-ninth pass, from your second
test: "5-10 unique sounds tailored to their response, mumbling or expressing emotions, not actual words").

    python audio/gen_voice_sfx.py

Writes audio/story/TownsfolkVoice_x9.wav: nine vocal takes, one for each of Poses.GESTURES in its order, each in its
own two-second slot (take k from 2k seconds). StoryClient plays the take for the gesture a line is told with, from the
speaker's head, at their own pitch (Townsfolk's VOICES: Pip high, Mr Wick and Mr Barlow low).

  greet     "heh-yo!"        bright, rising: a hello
  explain   a mumbled babble of five syllables, falling like a sentence, never a word
  point     "ooh, deh!"       a lift and a jab
  shrug     "hmm? eh?"        a closed-mouth hum rising into a question
  worry     "mmh-mmh..."      a hum that trembles
  remember  "hmmmm..."        long and low, slowly falling, thinking
  warn      "tsk, ah-ah!"     a click of the tongue and two firm syllables
  lean      a whispered mumble, no voice in it at all: between you and me
  sad       "ohhh..."         a breathy sigh, falling away

HOW: formant synthesis. A glottal pulse (Rosenberg's shape, with jitter, shimmer and breath in it) through a bank of
vowel formants that move from syllable to syllable, nasal hums lowpassed, whispered syllables from noise through the
same formants, consonants from short bursts, and a little room on it. Seeded, so re-running writes the same file.
"""
import pathlib
import sys

import numpy as np
from scipy import signal
from scipy.io import wavfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_button_sfx import SR, filt, peak  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
SLOT = 2.0
ORDER = ("greet", "explain", "point", "shrug", "worry", "remember", "warn", "lean", "sad")

# Vowel formants (Hz) and their bandwidths, a neutral adult voice (StoryClient pitches each speaker).
VOWELS = {
    "a": (730, 1090, 2440), "e": (530, 1840, 2480), "i": (300, 2200, 2950), "o": (570, 840, 2410),
    "u": (320, 870, 2240), "@": (500, 1450, 2450), "m": (260, 1000, 2200),
}
BANDWIDTHS = (80, 110, 170)


def glottal(f0, rng, shimmer=0.06, jitter=0.012):
    """A train of Rosenberg glottal pulses following `f0` (Hz, per sample), differentiated (lip radiation)."""
    f = f0 * (1 + jitter * filt(rng.standard_normal(len(f0)), "low", 30, order=1) * 3)
    ph = np.cumsum(f) / SR
    cyc = np.floor(ph)
    x = ph - cyc
    open_, close = 0.42, 0.18
    g = np.where(x < open_, 0.5 * (1 - np.cos(np.pi * x / open_)),
                 np.where(x < open_ + close, np.cos(0.5 * np.pi * (x - open_) / close), 0.0))
    amp = 1 + shimmer * np.interp(cyc, np.arange(int(cyc.max()) + 2), rng.standard_normal(int(cyc.max()) + 2))
    g = g * amp
    d = np.diff(g, prepend=0.0)
    # Breath in the voice: noise riding on the open phase.
    breath = rng.standard_normal(len(g)) * (x < open_ + close) * 0.05
    return d / (np.max(np.abs(d)) + 1e-9) + breath


def formant_track(segments, n):
    """Per-sample formant frequencies for a list of (vowel, start, end) segments, glided between neighbours."""
    tracks = np.zeros((3, n))
    keys_t, keys_f = [], []
    for vowel, start, end in segments:
        mid = (start + end) / 2
        keys_t += [start + 0.25 * (end - start), mid, end - 0.25 * (end - start)]
        keys_f += [VOWELS[vowel]] * 3
    t = np.arange(n) / SR
    keys_f = np.array(keys_f)
    for i in range(3):
        tracks[i] = np.interp(t, keys_t, keys_f[:, i])
    return tracks


def resonate(x, tracks, gains=(1.0, 0.55, 0.25), hop=128):
    """x through three formant resonators whose centres follow `tracks`, a hop at a time (state carried across)."""
    out = np.zeros_like(x)
    for i in range(3):
        zi = np.zeros(2)
        for start in range(0, len(x), hop):
            end = min(len(x), start + hop)
            fc = float(np.mean(tracks[i, start:end]))
            bw = BANDWIDTHS[i]
            r = np.exp(-np.pi * bw / SR)
            theta = 2 * np.pi * fc / SR
            a = [1, -2 * r * np.cos(theta), r * r]
            b = [(1 - r) * np.sqrt(1 - 2 * r * np.cos(2 * theta) + r * r), 0, 0]
            y, zi = signal.lfilter(b, a, x[start:end], zi=zi)
            out[start:end] += gains[i] * y
    return out


def envelope_of(segments, n, attack=0.02, release=0.05):
    """Loudness: up in each syllable, down between them."""
    env = np.zeros(n)
    t = np.arange(n) / SR
    for _vowel, start, end, *level in [(s[0], s[1], s[2], s[3] if len(s) > 3 else 1.0) for s in segments]:
        up = np.clip((t - start) / attack, 0, 1)
        down = np.clip((end - t) / release, 0, 1)
        env = np.maximum(env, up * down * level[0])
    return filt(env, "low", 40, order=1)


def voiced(syllables, f0_points, rng, breathiness=0.0, nasal=False):
    """Syllables (vowel, start, end[, level]) sung along a pitch contour (time, Hz) points."""
    n = int(SR * (max(s[2] for s in syllables) + 0.25))
    t = np.arange(n) / SR
    pts = np.array(f0_points)
    f0 = np.interp(t, pts[:, 0], pts[:, 1])
    f0 = f0 * (1 + 0.012 * np.sin(2 * np.pi * 5.2 * t))
    src = glottal(f0, rng)
    if breathiness:
        src = (1 - breathiness) * src + breathiness * filt(rng.standard_normal(n), "band", [400, 5000]) * 0.4
    tracks = formant_track([(s[0], s[1], s[2]) for s in syllables], n)
    voice = resonate(src, tracks)
    if nasal:
        voice = filt(voice, "low", 900) * 1.8 + 0.07 * voice
    return voice * envelope_of(syllables, n)


def whispered(syllables, rng):
    n = int(SR * (max(s[2] for s in syllables) + 0.25))
    src = filt(rng.standard_normal(n), "band", [300, 6000]) * 0.5
    tracks = formant_track([(s[0], s[1], s[2]) for s in syllables], n)
    return resonate(src, tracks, gains=(0.8, 0.7, 0.5)) * envelope_of(syllables, n, 0.03, 0.06)


def burst(at, length, low, high, level, n, rng):
    x = np.zeros(n)
    s, m = int(SR * at), int(SR * length)
    if s + m < n:
        b = filt(rng.standard_normal(m + 64), "band", [low, high])[64:]
        b *= np.exp(-np.arange(m) / (SR * length / 3))
        x[s:s + m] += level * b / (np.max(np.abs(b)) + 1e-9)
    return x


def room(x, rng):
    """A little room: a short, dark, decaying tail, so it is a person in a place and not a box."""
    m = int(SR * 0.18)
    ir = rng.standard_normal(m) * np.exp(-np.arange(m) / (SR * 0.045))
    ir = filt(ir, "low", 3500)
    ir[0] = 0
    wet = signal.fftconvolve(x, ir)[: len(x)]
    return x + 0.12 * wet / (np.max(np.abs(wet)) + 1e-9) * np.max(np.abs(x))


def fit(x, n):
    out = np.zeros(n)
    out[: min(n, len(x))] = x[:n]
    return out


def make(kind, rng):
    if kind == "greet":
        v = voiced([("e", 0.03, 0.2), ("o", 0.24, 0.5)], [(0, 170), (0.18, 215), (0.26, 205), (0.42, 235), (0.55, 190)], rng)
        n = len(v)
        x = v + burst(0.0, 0.05, 1200, 4000, 0.18, n, rng)  # the breath of the h
    elif kind == "explain":
        syl, t0, pts = [], 0.03, []
        plan = [("@", 0.12), ("e", 0.1), ("a", 0.14), ("@", 0.09), ("o", 0.16)]
        f = 165
        for vowel, d in plan:
            syl.append((vowel, t0, t0 + d))
            pts += [(t0, f), (t0 + d, f * 0.96)]
            t0 += d + 0.045
            f *= 0.95
        v = voiced(syl, pts, rng)
        n = len(v)
        x = v
        for k, (vowel, start, end) in enumerate(syl[1:]):
            x = x + burst(start - 0.03, 0.02, 1800 if k % 2 else 600, 4500 if k % 2 else 2200, 0.08, n, rng)
    elif kind == "point":
        v = voiced([("u", 0.02, 0.32), ("e", 0.42, 0.56, 1.1)], [(0, 175), (0.2, 205), (0.32, 190), (0.42, 230), (0.56, 180)], rng)
        n = len(v)
        x = v + burst(0.38, 0.025, 2500, 5000, 0.25, n, rng)  # the d
    elif kind == "shrug":
        v = voiced([("m", 0.02, 0.42), ("e", 0.52, 0.7)], [(0, 150), (0.35, 160), (0.42, 195), (0.52, 185), (0.7, 240)], rng,
                   nasal=False)
        hum = voiced([("m", 0.02, 0.42)], [(0, 150), (0.35, 160), (0.42, 195)], rng, nasal=True)
        n = max(len(v), len(hum))
        x = fit(v, n) * 0.55 + fit(hum, n)
    elif kind == "worry":
        t = np.linspace(0, 1.1, 50)
        pts = [(tt, 170 + 10 * np.sin(2 * np.pi * 6.5 * tt) + 12 * np.sin(np.pi * tt / 1.1)) for tt in t]
        x = voiced([("m", 0.03, 0.42), ("m", 0.55, 1.05, 0.85)], pts, rng, breathiness=0.2, nasal=True)
    elif kind == "remember":
        x = voiced([("m", 0.03, 1.25)], [(0, 150), (0.3, 142), (0.9, 128), (1.25, 140)], rng, nasal=True)
    elif kind == "warn":
        v = voiced([("a", 0.18, 0.3, 1.1), ("a", 0.42, 0.58)], [(0, 210), (0.3, 200), (0.42, 185), (0.58, 160)], rng)
        n = len(v)
        x = v + burst(0.0, 0.012, 2500, 6000, 0.6, n, rng)  # tsk
    elif kind == "lean":
        x = whispered([("@", 0.03, 0.14), ("i", 0.2, 0.32), ("a", 0.38, 0.5), ("u", 0.56, 0.7)], rng)
        n = len(x)
        x = x + burst(0.0, 0.05, 3500, 7000, 0.3, n, rng)  # the ps of psst
    elif kind == "sad":
        v = voiced([("o", 0.04, 0.9)], [(0, 160), (0.4, 140), (0.9, 105)], rng, breathiness=0.35)
        n = len(v) + int(SR * 0.35)
        exhale = burst(0.75, 0.4, 500, 3000, 0.25, n, rng)
        x = fit(v, n) + exhale
    else:
        raise ValueError(kind)
    x = filt(x, "high", 70, order=2)
    x = filt(x, "low", 7000)
    x = room(x, rng)
    x = peak(x) * 10 ** (-3 / 20)
    fade = int(SR * 0.02)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


if __name__ == "__main__":
    out = np.zeros(int(SR * SLOT * len(ORDER)))
    for k, kind in enumerate(ORDER):
        rng = np.random.default_rng(8900 + k)
        x = make(kind, rng)
        assert len(x) <= int(SR * (SLOT - 0.05)), (kind, len(x) / SR)
        start = int(SR * SLOT * k)
        out[start:start + len(x)] = x
        print("  %-9s %.2f s" % (kind, len(x) / SR))
    path = HERE / "story" / ("TownsfolkVoice_x%d.wav" % len(ORDER))
    wavfile.write(path, SR, (np.clip(out, -1, 1) * 32767).astype(np.int16))
    print("wrote", path)
