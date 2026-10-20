"""The scenes' own sounds, remade (the ninety-sixth pass): the gate, the water, the siren, the thing in the shaft.

    python audio/gen_story_sfx.py              every one
    python audio/gen_story_sfx.py Siren        only those named

Writes audio/story/<Name>.wav, the same nine names as before (and one new one, JournalAdd) (so each goes into SoundService.StorySounds in place
of the old one, and nothing in the game changes but the sound), each at the loudness of the one it replaces:

  GateGroan    Outfall 3 going up: iron dragged over iron, the real way it groans (friction catching and slipping,
               thousands of times a second, ringing the gate's own plate), the screw's clanks, water pouring off it
  WaterRush    the bay going out through the gate: a river of water, heavy and low, gulping and churning, in the
               chamber (it was a hiss: 5 kHz of noise)
  Siren        the flood siren far off: a rotor chopping air (a motor siren, winding up, holding, winding down),
               heard across the town and down through the water, its echoes coming back off the buildings
  MawRumble    the thing breathing: slow, enormous, wet, in the shaft
  MawGrowl     before you see it: a throat a building wide, a growl that catches and drags (a voice with jitter in it,
               never an even buzz), far down
  MawRoar      it opens: a thump of air, the roar tearing up out of it, wet, falling away
  JawsShut     the jaws closing: a vast soft thud, teeth meeting, air forced out, the water slapping back
  Heartbeat    a heartbeat from inside something: lub, dub (the valves closing, as a real heart sounds), slow
  SecretSting  finding something: a breath drawn in backwards that stops short, and a low felt-piano note, a fifth
               over it on a wooden bar, ringing on in a room
  JournalAdd   new (the journal looked for it and played a stock click instead): something put in your journal, a few
               quick pencil strokes on paper, the pencil set down, the page settling

Nothing here is a bare tone. Seeded from each name, so re-running writes the same files.
"""
import pathlib
import sys

import numpy as np
from scipy import signal

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import (SR, bp, brown, bubble, bubbles, drift, env, fade, felt_piano, finish, hp, limit, lp, match,  # noqa
                     modal, n_, peak, phase, pink, place, resonate, reverb, rng_for, sculpted, splash, strike, swell,
                     t_, white, wood_bar, write)

HERE = pathlib.Path(__file__).resolve().parent
STORY = HERE / "story"

# The loudness of the sound each replaces (measured from the old files), so the scene's own volumes still hold.
LEVELS = {"GateGroan": -15.7, "WaterRush": -14.5, "Siren": -15.0, "MawRumble": -16.5, "MawGrowl": -18.8,
          "MawRoar": -20.0, "JawsShut": -21.0, "Heartbeat": -20.5, "SecretSting": -16.5}


# ------------------------------------------------------------------------------------------------ voices
def pulses(seconds, f0, rng, jitter=0.03, shimmer=0.15, width=0.45, fry=None):
    """A glottal source: one rounded pulse per period of f0 (an array over time), each period a little off (jitter)
    and each pulse a little louder or softer (shimmer); `fry` (0..1 over time) makes periods catch and drag."""
    n = n_(seconds)
    out = np.zeros(n)
    i = 0
    while i < n:
        f = max(float(f0[min(i, n - 1)]), 8.0)
        period = 1.0 / f * (1 + rng.normal(0, jitter))
        if fry is not None:
            k = float(fry[min(i, n - 1)])
            if rng.uniform() < k * 0.6:
                period *= rng.uniform(1.4, 2.6)
        m = max(8, int(SR * period * width))
        shape = np.sin(np.linspace(0, np.pi, m)) ** 2
        shape = np.diff(np.concatenate([[0], shape]))  # the flow's derivative: what the throat actually radiates
        amp = 1 + rng.normal(0, shimmer)
        end = min(n, i + m)
        out[i:end] += amp * shape[:end - i]
        i += max(1, int(SR * period))
    return peak(out)


def stick_slip(seconds, f, rng, jitter=0.18, roughness=0.5):
    """Friction: a surface catching and slipping `f` times a second (an array over time), irregularly, each slip a
    little crack of force; rung through something's modes, it is a groan, a creak or a squeal."""
    n = n_(seconds)
    out = np.zeros(n)
    i = 0
    while i < n:
        rate = max(float(f[min(i, n - 1)]), 4.0)
        period = 1.0 / rate * max(0.2, 1 + rng.normal(0, jitter))
        out[i] = rng.uniform(0.4, 1.0) * (1 if rng.uniform() > 0.08 else 2.2)
        i += max(1, int(SR * period))
    grit = hp(white(seconds, rng), 2000) * roughness * 0.02
    return out + grit


# ------------------------------------------------------------------------------------------------ the gate chamber
def gate_groan(rng):
    d = 9.0
    t = t_(d)
    # The gate's plate: a big riveted iron sheet, inharmonic, ringing a second or two.
    plate = modal(2.2, [43, 71, 112, 158, 197, 263, 331, 412, 538, 690, 845], [2.0, 1.8, 1.6, 1.4, 1.2, 1.0, 0.8, 0.7,
                                                                               0.5, 0.4, 0.3],
                  [1.0, 0.8, 0.9, 0.6, 0.7, 0.5, 0.4, 0.35, 0.25, 0.18, 0.12], rng)
    # The drag: slow at first, catching, then the screw taking it at a steadier, slightly higher rate.
    rate = 22 + 14 * np.clip(t / 2.5, 0, 1) + 9 * drift(d, rng, rate=0.6) + 4 * drift(d, rng, rate=2.5)
    effort = swell(t, d, 0.9, 1.4) * (0.6 + 0.4 * (0.5 + 0.5 * drift(d, rng, rate=0.35)))
    groan = signal.fftconvolve(stick_slip(d, rate, rng) * effort, plate)[:n_(d)]
    groan = lp(groan, 1800)
    # Higher, thinner: the screw's thread squealing a little over it, now and then.
    squeal_rate = 180 + 60 * drift(d, rng, rate=0.8)
    thread = modal(0.6, [612, 1290, 1870], [0.25, 0.18, 0.12], [1.0, 0.5, 0.3], rng)
    squeal = signal.fftconvolve(stick_slip(d, squeal_rate, rng, jitter=0.08), thread)[:n_(d)]
    squeal *= np.clip(drift(d, rng, rate=0.5, lo=-0.6, hi=1.0), 0, 1) ** 2 * effort
    # The screw's clanks: iron on iron, a heavy thing knocked, every so often as it takes up.
    layers = [(0.0, 1.0, peak(groan)), (0.0, 0.16, peak(lp(squeal, 3200)))]
    at = 0.4
    while at < d - 1.0:
        clank = strike(1.4, [rng.uniform(140, 170), rng.uniform(380, 430), rng.uniform(760, 840), rng.uniform(1310, 1420)],
                       [0.9, 0.6, 0.35, 0.2], [1.0, 0.6, 0.35, 0.18], rng, hardness=0.7)
        layers.append((at, rng.uniform(0.25, 0.45), peak(clank)))
        at += rng.uniform(0.9, 1.8)
    # Water pouring off the gate's edge as it comes up out of it.
    pour_rate = 260 * np.clip((t - 1.0) / 3.0, 0, 1) * swell(t, d, 1.0, 1.0)
    pour = bubbles(d, rng, pour_rate, r_mm=(0.8, 5.0), beta=2.3, xi=(0.05, 0.25))
    layers.append((0.0, 0.22, peak(lp(pour, 3000))))
    x = place(d, layers)
    x = reverb(x, "cavern", rng, wet=0.45)[:n_(d)]
    return finish(x, LEVELS["GateGroan"], fade_out=1.2)


def water_rush(rng):
    d = 10.0
    t = t_(d)
    surge = 0.75 + 0.25 * drift(d, rng, rate=0.4) + 0.08 * drift(d, rng, rate=1.7)
    level = swell(t, d, 0.4, 0.6)
    # The body of it: heavy water, its spectrum where a river's is (most of it under a kilohertz), heaving.
    def shape(times, freqs):
        s = np.interp(times, t, surge) if times.ndim else surge
        f0 = 320 + 160 * s
        return (1 / (1 + (freqs / f0) ** 2.2)) * (freqs > 35) * (0.6 + 0.4 * s)
    body = sculpted(d, rng, shape)
    # Its gulps and churning: big bubbles, low, many of them; and a fizz of small ones on the top, quietly.
    gulps = bubbles(d, rng, 380 * surge * level, r_mm=(2.0, 14.0), beta=2.0, xi=(0.1, 0.4))
    churn = bubbles(d, rng, 1400 * surge * level, r_mm=(0.6, 3.0), beta=2.6, xi=(0.05, 0.2))
    spray = lp(bp(pink(d, rng), 1800, 6000), 7000) * (0.4 + 0.6 * surge)
    x = (1.0 * peak(body) + 0.45 * peak(gulps) + 0.3 * peak(churn) + 0.05 * peak(spray)) * level
    x = reverb(x, "tiles", rng, wet=0.35)[:n_(d)]
    return finish(x, LEVELS["WaterRush"], fade_in=0.3, fade_out=0.5)


def siren(rng):
    d = 11.0
    t = t_(d)
    rise, hold = 3.0, 4.5
    # A motor siren's pitch: it winds up (fast, then slower as it nears speed), holds with the motor's waver, and
    # runs down as the power goes off.
    up = 160 + 330 * (1 - np.exp(-3.2 * np.clip(t / rise, 0, 1))) / (1 - np.exp(-3.2))
    held = 490 + 7 * drift(d, rng, rate=0.7) + 3 * np.sin(2 * np.pi * 0.42 * t)
    down = 490 - 330 * np.clip((t - rise - hold) / (d - rise - hold), 0, 1) ** 1.25
    f = np.where(t < rise, up, np.where(t < rise + hold, held, down))
    # The rotor chops the air: a rounded pulse, rich in harmonics, a little breathy (air through the ports).
    ph = phase(f)
    tone = np.tanh(2.4 * np.sin(ph)) + 0.25 * np.tanh(2.0 * np.sin(2 * ph + 0.7))
    breath = bp(white(d, rng), 400, 2400) * (0.5 + 0.5 * np.sin(ph)) ** 2
    voice = tone + 0.18 * peak(breath)
    level = swell(t, d, 1.0, 2.4)
    # Far off and over the town: the top gone, the slap of it coming back off the fronts, then down through water.
    far = lp(voice * level, 1600, order=2)
    out = far.copy()
    for k, (lag, gain) in enumerate(((0.23, 0.5), (0.51, 0.32), (0.87, 0.22), (1.3, 0.15), (1.9, 0.09))):
        shift = n_(lag)
        out[shift:] += lp(far, 1200 - 150 * k)[:-shift] * gain
    out = reverb(out, "harbour", rng, wet=0.5)[:n_(d)]
    return finish(lp(out, 2200), LEVELS["Siren"], fade_in=0.2, fade_out=1.5)


# ------------------------------------------------------------------------------------------------ the thing in the shaft
def maw_rumble(rng):
    d = 7.0
    t = t_(d)
    # Two breaths: in (rising, the air drawn down past you), out (heavier, wetter).
    breath = np.clip(np.sin(np.pi * t / d), 0, 1) ** 1.4
    pulse = 0.65 + 0.35 * drift(d, rng, rate=0.5)

    def shape(times, freqs):
        b = np.interp(times, t, breath)
        return (1 / (1 + (freqs / (70 + 90 * b)) ** 3)) * (freqs > 22) * (0.2 + b)
    air = sculpted(d, rng, shape)
    throat = resonate(brown(d, rng), [(58, 1.0), (124, 0.7), (205, 0.4)], q=5) * breath * pulse
    wet = bubbles(d, rng, 30 * breath, r_mm=(8.0, 30.0), beta=1.8, xi=(0.2, 0.5))
    x = 1.0 * peak(air) + 0.8 * peak(throat) + 0.25 * peak(lp(wet, 900))
    x = reverb(x, "cavern", rng, wet=0.5)[:n_(d)]
    return finish(x, LEVELS["MawRumble"], fade_in=0.4, fade_out=1.0, high_cut=1600)


def maw_growl(rng):
    d = 4.6
    t = t_(d)
    f0 = 38 + 9 * np.clip(t / 1.4, 0, 1) - 6 * np.clip((t - 3.0) / 1.6, 0, 1) + 3 * drift(d, rng, rate=2.0)
    fry = np.clip(0.35 + 0.4 * drift(d, rng, rate=3.0), 0, 1)
    src = pulses(d, f0, rng, jitter=0.06, shimmer=0.25, fry=fry)
    body = resonate(src, [(160, 1.0), (360, 0.6), (780, 0.25), (1300, 0.08)], q=3.5)
    breath = resonate(white(d, rng), [(220, 1.0), (520, 0.5)], q=2.5) * (0.4 + 0.6 * fry)
    shape = swell(t, d, 1.2, 1.6, power=1.5)
    x = (peak(body) + 0.3 * peak(breath)) * shape
    x = reverb(x, "cavern", rng, wet=0.55)[:n_(d)]
    return finish(x, LEVELS["MawGrowl"], high_cut=1500, fade_out=0.8)


def maw_roar(rng):
    d = 3.2
    t = t_(d)
    f0 = 50 + 34 * np.clip(t / 0.32, 0, 1) - 46 * np.clip((t - 0.55) / 2.5, 0, 1) ** 1.3 + 4 * drift(d, rng, rate=6)
    fry = np.clip(0.2 + 0.5 * np.clip((t - 1.4) / 1.5, 0, 1) + 0.2 * drift(d, rng, rate=5), 0, 1)
    src = pulses(d, f0, rng, jitter=0.05, shimmer=0.2, width=0.55, fry=fry)
    sub = pulses(d, f0 / 2, rng, jitter=0.07, shimmer=0.3, width=0.6)  # the half-speed buzz under a big voice
    body = resonate(src + 0.5 * sub, [(230, 1.0), (620, 0.75), (1400, 0.35), (2500, 0.12)], q=3.0)
    rush = resonate(white(d, rng), [(300, 1.0), (900, 0.6), (2000, 0.25)], q=2.0) * env(t, 0.08, 1.0)
    thump = lp(brown(0.8, rng), 140) * env(t_(0.8), 0.02, 0.18)
    slobber = bubbles(d, rng, 60 * env(t, 0.3, 1.2), r_mm=(3.0, 14.0), beta=2.0, xi=(0.2, 0.5))
    shape = env(t, 0.07, 1.25)
    x = place(d, [(0.0, 0.9, peak(thump)), (0.02, 1.0, peak(body * shape)), (0.0, 0.4, peak(rush)),
                  (0.25, 0.18, peak(lp(slobber, 1500)))])
    x = reverb(x, "cavern", rng, wet=0.5)[:n_(d)]
    return finish(x, LEVELS["MawRoar"], high_cut=5000, fade_out=0.6)


def jaws_shut(rng):
    d = 2.6
    # A body as big as a room meeting itself: a deep soft thud (very low modes, quickly damped), the teeth meeting a
    # moment after (hard, short, bony: no ring), the air forced out, and the water it was full of slapping back.
    thud = strike(d, [38, 61, 94, 140], [0.9, 0.6, 0.4, 0.25], [1.0, 0.8, 0.5, 0.3], rng, hardness=0.1)
    teeth = np.zeros(n_(0.25))
    for k in range(5):
        knock = strike(0.25, [rng.uniform(520, 700), rng.uniform(1150, 1450), rng.uniform(2100, 2600)],
                       [0.05, 0.03, 0.02], [1.0, 0.6, 0.3], rng, hardness=0.75)
        a = n_(rng.uniform(0, 0.03))
        teeth[a:] += knock[:len(teeth) - a] * rng.uniform(0.5, 1.0)
    gust = resonate(white(1.2, rng), [(240, 1.0), (700, 0.5)], q=2) * env(t_(1.2), 0.02, 0.25)
    slosh = splash(rng, size=2.2, seconds=1.8)
    x = place(d, [(0.0, 1.0, peak(thud)), (0.012, 0.45, peak(teeth)), (0.02, 0.35, peak(gust)),
                  (0.12, 0.4, peak(lp(slosh, 2500)))])
    x = reverb(x, "cavern", rng, wet=0.4)[:n_(d)]
    return finish(x, LEVELS["JawsShut"], high_cut=4500, fade_out=0.8)


def heartbeat(rng):
    d = 1.4

    def sound(strength, low):
        # A heart sound: the valve closing, a short low thump ringing at the chest's own resonances.
        knock = lp(white(0.12, rng), 160) * env(t_(0.12), 0.006, 0.025)
        ring = strike(0.22, [low, low * 1.6, low * 2.5], [0.12, 0.08, 0.05], [1.0, 0.5, 0.2], rng, hardness=0.05)
        return strength * place(0.22, [(0.0, 0.6, peak(knock)), (0.0, 1.0, peak(ring))])
    x = place(d, [(0.0, 1.0, sound(1.0, 46)), (0.27, 0.72, sound(0.8, 58))])
    x = lp(x, 260, order=2)
    return finish(x, LEVELS["Heartbeat"], low_cut=24, fade_in=0.0005, fade_out=0.15)


def secret_sting(rng):
    d = 3.6
    note_at = 2.1
    note = felt_piano(110.0, d - note_at + 1.5, rng, velocity=0.45) + 0.6 * felt_piano(164.8, d - note_at + 1.5, rng,
                                                                                     velocity=0.35)
    bar = wood_bar(329.6, d - note_at + 1.5, rng, velocity=0.3)
    struck = place(d - note_at + 1.5, [(0.0, 1.0, peak(note)), (0.03, 0.25, peak(bar))])
    # The breath drawn in backwards: the note's own room, reversed, swelling up into it and stopping short.
    room = reverb(struck, "hall", rng, wet=1.0, dry=0.0)
    back = room[::-1][-n_(note_at):]
    back = fade(back * np.clip(np.linspace(0, 1, len(back)) * 1.15, 0, 1) ** 2.5, 0.0, 0.025)
    tail = reverb(struck, "hall", rng, wet=0.35)
    x = place(d, [(0.0, 0.9, peak(back)), (note_at, 1.0, peak(tail))])
    return finish(x, LEVELS["SecretSting"], high_cut=5000, fade_out=0.5)


def journal_add(rng):
    """Something put in your journal: a few quick strokes of a pencil on paper (graphite's fine grain dragged, the
    paper's soft body under it), the pencil set down, and the page settling. Quiet, close, and different each time it
    would be if it were not one file: so it is short and plain enough to bear hearing often."""
    d = 1.1
    out = np.zeros(n_(d))
    at = 0.02
    for k, length in enumerate((0.16, 0.12, 0.2)):
        t = t_(length)
        stroke = np.sin(np.pi * np.clip(t / length, 0, 1)) ** 1.5
        grain = bubbles(length, rng, 2600 * stroke, r_mm=(0.9, 2.4), beta=2.6, xi=(0.0, 0.05), size_gain=0.3)
        drag = lp(bp(white(length, rng), 900, 3500), 3800) * stroke * (0.7 + 0.3 * drift(length, rng, rate=30))
        body = lp(bp(white(length, rng), 250, 1100), 1200) * stroke
        piece = 0.35 * peak(grain) + 0.45 * peak(drag) + 0.6 * peak(body)
        a = n_(at)
        out[a:a + len(piece)] += piece[:len(out) - a]
        at += length + rng.uniform(0.03, 0.07)
    tap = strike(0.12, [rng.uniform(900, 1100), rng.uniform(2100, 2500)], [0.03, 0.015], [1.0, 0.3], rng, hardness=0.4)
    a = n_(at + 0.05)
    out[a:a + len(tap)] += 0.5 * peak(tap)[:len(out) - a]
    settle_t = t_(0.4)
    settle = lp(bp(white(0.4, rng), 200, 1600), 1500) * env(settle_t, 0.08, 0.12)
    a = n_(at + 0.12)
    out[a:a + len(settle)] += 0.35 * peak(settle)[:len(out) - a]
    x = reverb(out, "small", rng, wet=0.15)[:n_(d)]
    return finish(x, -20.0, high_cut=5000, fade_out=0.15)


SOUNDS = [("GateGroan", gate_groan), ("WaterRush", water_rush), ("Siren", siren), ("MawRumble", maw_rumble),
          ("MawGrowl", maw_growl), ("MawRoar", maw_roar), ("JawsShut", jaws_shut), ("Heartbeat", heartbeat),
          ("SecretSting", secret_sting), ("JournalAdd", journal_add)]

if __name__ == "__main__":
    only = set(sys.argv[1:])
    for name, make in SOUNDS:
        if only and name not in only:
            continue
        print(write(STORY / ("%s.wav" % name), make(rng_for(name, 9500))))
