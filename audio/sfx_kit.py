"""The sound kit every generator in audio/ shares since the ninety-sixth pass: better parts to make things from.

The first generators built everything from three ideas (band-passed noise, a sine that drops in pitch, a handful of
echoes), and you can hear it: water that is hiss, chords that are sine waves, rooms that are four taps. This is what
replaces them, each piece modelled on how the real thing makes its sound:

  WATER      bubble(): a bubble's own ring (Minnaert's frequency, its damping, the pitch rising as it nears the
             surface: van den Doel's model). Every splash, drip, wash, fizz and gurgle here is clouds of them, so
             water sounds like water rather than like noise.
  STRUCK     strike(): a thing's own modes (frequencies, how long each rings) struck by a mallet as hard or soft as
             asked, so wood, plastic, glass, iron and bells each sound like what they are.
  INSTRUMENTS felt_piano(), wood_bar(), bell(), warm_pad(): additive voices with real partials (a piano string's
             stretch and its two-stage decay, a bar's tuned overtones, a bell's hum, prime, tierce and nominal),
             detuned strings beating against each other, never a bare sine.
  AIR        sculpted(): noise shaped by a spectrum that changes as it goes (wind, rushes, the sea), so a gust has
             a body that brightens as it rises, rather than one fixed filter with a wobble.
  ROOMS      reverb(): a synthesised impulse response for each space the game has (the tiled baths, a brick shaft,
             a culvert, the harbour at night, under the water, a concert hall for the chords), its high end dying
             faster than its low, as in a real room.
  LEVEL      lufs() and match(): loudness as BS.1770 measures it, so a remade sound is put at the loudness of the
             one it replaces and the mix the game sets does not move.

Mono, 44.1 kHz, 16 bit, as every sound in the game.
"""
import pathlib
import zlib

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100


# ------------------------------------------------------------------------------------------------ time and mixing
def n_(seconds):
    return int(round(SR * seconds))


def t_(seconds):
    return np.arange(n_(seconds)) / SR


def rng_for(name, salt=0):
    return np.random.default_rng(zlib.crc32(name.encode()) + salt)


def peak(x):
    m = np.max(np.abs(x)) if len(x) else 0.0
    return x / m if m > 0 else x


def place(total, layers):
    """[(start seconds, gain, signal)] laid into one signal `total` seconds long."""
    out = np.zeros(n_(total))
    for start, gain, x in layers:
        a = n_(start)
        if a >= len(out):
            continue
        b = min(len(out), a + len(x))
        out[a:b] += gain * np.asarray(x[:b - a], dtype=float)
    return out


def fade(x, fade_in=0.0, fade_out=0.0):
    """Raised-cosine fades: no corner at either end to click."""
    x = np.array(x, dtype=float)
    for length, head in ((n_(fade_in), True), (n_(fade_out), False)):
        length = min(length, len(x))
        if length > 1:
            w = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, length))
            if head:
                x[:length] *= w
            else:
                x[-length:] *= w[::-1]
    return x


def env(t, attack, decay, hold=0.0, curve=1.0):
    """A smooth rise over `attack`, a hold, then an exponential fall with time constant `decay`."""
    t = np.asarray(t, dtype=float)
    rise = np.clip(t / max(attack, 1e-6), 0, 1)
    rise = (0.5 - 0.5 * np.cos(np.pi * rise)) ** curve
    fall = np.exp(-np.maximum(t - attack - hold, 0) / max(decay, 1e-6))
    return rise * fall


def swell(t, total, rise, release, power=1.0):
    """Up over `rise`, held, down over the last `release` of `total`: a bed's or a long one-shot's shape."""
    up = np.clip(t / max(rise, 1e-6), 0, 1)
    down = np.clip((total - t) / max(release, 1e-6), 0, 1)
    return ((0.5 - 0.5 * np.cos(np.pi * up)) * (0.5 - 0.5 * np.cos(np.pi * down))) ** power


def phase(freq):
    """Phase (radians) of a frequency that changes sample by sample."""
    return 2 * np.pi * np.cumsum(np.asarray(freq, dtype=float)) / SR


# ------------------------------------------------------------------------------------------------ filters
def _sos(kind, cutoff, order):
    nyq = SR / 2 * 0.999
    if np.ndim(cutoff):
        cutoff = [min(max(c, 5.0), nyq) for c in cutoff]
    else:
        cutoff = min(max(cutoff, 5.0), nyq)
    return signal.butter(order, cutoff, btype=kind, fs=SR, output="sos")


def lp(x, cutoff, order=2):
    return signal.sosfilt(_sos("low", cutoff, order), x)


def hp(x, cutoff, order=2):
    return signal.sosfilt(_sos("high", cutoff, order), x)


def bp(x, low, high, order=2):
    return signal.sosfilt(_sos("band", [low, high], order), x)


def lp0(x, cutoff, order=2):
    """Zero-phase: for shaping a whole bed without smearing its transients."""
    return signal.sosfiltfilt(_sos("low", cutoff, order), x)


def hp0(x, cutoff, order=2):
    return signal.sosfiltfilt(_sos("high", cutoff, order), x)


def biquad(kind, fc, q=0.707, gain_db=0.0):
    """RBJ cookbook biquads (peak, lowshelf, highshelf) as (b, a)."""
    a_lin = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * fc / SR
    alpha = np.sin(w0) / (2 * q)
    c = np.cos(w0)
    if kind == "peak":
        b = [1 + alpha * a_lin, -2 * c, 1 - alpha * a_lin]
        a = [1 + alpha / a_lin, -2 * c, 1 - alpha / a_lin]
    elif kind == "lowshelf":
        s = 2 * np.sqrt(a_lin) * alpha
        b = [a_lin * ((a_lin + 1) - (a_lin - 1) * c + s), 2 * a_lin * ((a_lin - 1) - (a_lin + 1) * c),
             a_lin * ((a_lin + 1) - (a_lin - 1) * c - s)]
        a = [(a_lin + 1) + (a_lin - 1) * c + s, -2 * ((a_lin - 1) + (a_lin + 1) * c), (a_lin + 1) + (a_lin - 1) * c - s]
    elif kind == "highshelf":
        s = 2 * np.sqrt(a_lin) * alpha
        b = [a_lin * ((a_lin + 1) + (a_lin - 1) * c + s), -2 * a_lin * ((a_lin - 1) + (a_lin + 1) * c),
             a_lin * ((a_lin + 1) + (a_lin - 1) * c - s)]
        a = [(a_lin + 1) - (a_lin - 1) * c + s, 2 * ((a_lin - 1) - (a_lin + 1) * c), (a_lin + 1) - (a_lin - 1) * c - s]
    else:
        raise ValueError(kind)
    return np.array(b) / a[0], np.array(a) / a[0]


def eq(x, kind, fc, gain_db, q=0.707):
    b, a = biquad(kind, fc, q, gain_db)
    return signal.lfilter(b, a, x)


def resonate(x, centres, q=6.0):
    """Through resonances (a throat, a pipe, a tube): peaking bands summed, each `(centre, gain)`."""
    out = np.zeros_like(x)
    for centre, gain in centres:
        bw = centre / q
        out += gain * bp(x, max(centre - bw / 2, 10), centre + bw / 2, order=1)
    return out


# ------------------------------------------------------------------------------------------------ noise
def white(seconds, rng):
    return rng.standard_normal(n_(seconds))


def coloured(seconds, rng, slope_db_per_octave):
    """Noise with a spectral slope: -3 is pink, -6 brown, 0 white."""
    n = n_(seconds)
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    spec *= (f / 1000.0) ** (slope_db_per_octave / 6.0206)
    spec[0] = 0
    return peak(np.fft.irfft(spec, n))


def pink(seconds, rng):
    return coloured(seconds, rng, -3.0)


def brown(seconds, rng):
    return coloured(seconds, rng, -6.0)


def drift(seconds, rng, rate=0.3, lo=-1.0, hi=1.0, points=None):
    """A slow random wander between lo and hi (smooth: a cubic through random points `rate` times a second)."""
    count = points or max(4, int(seconds * rate) + 4)
    knots = rng.uniform(-1, 1, count)
    x = np.linspace(0, 1, count)
    from scipy.interpolate import CubicSpline
    curve = CubicSpline(x, knots, bc_type="natural")(np.linspace(0, 1, n_(seconds)))
    curve = np.clip(curve, -1.2, 1.2) / 1.2
    return lo + (hi - lo) * (curve + 1) / 2


def sculpted(seconds, rng, shape, hop=256, size=2048):
    """Noise made frame by frame from a spectrum that changes as it goes. `shape(times, freqs)` returns the
    magnitude for every frame (rows) and bin (columns); the phases are random, the frames overlap-added."""
    n = n_(seconds)
    frames = int(np.ceil(n / hop)) + 2
    times = np.arange(frames) * hop / SR
    freqs = np.fft.rfftfreq(size, 1 / SR)
    mag = np.broadcast_to(np.asarray(shape(times[:, None], freqs[None, :]), dtype=float), (frames, len(freqs)))
    spec = mag * np.exp(1j * rng.uniform(0, 2 * np.pi, mag.shape))
    window = signal.windows.hann(size, sym=False)
    out = np.zeros(frames * hop + size)
    for k in range(frames):
        frame = np.fft.irfft(spec[k], size) * window
        out[k * hop:k * hop + size] += frame
    return peak(out[size // 2:size // 2 + n])


def gliding(seconds, rng, centre, partials=((1.0, 1.0),), q=8.0):
    """Noise in resonances that move: a pipe's or a throat's note sliding as it changes (`centre`, an array over
    time, Hz), with `partials` [(ratio, gain)]. A resonance, never a tone: the noise keeps it breathing."""
    t = t_(seconds)
    centre = np.broadcast_to(np.asarray(centre, dtype=float), t.shape)

    def shape(times, freqs):
        c = np.interp(times, t, centre)
        out = 0
        for ratio, gain in partials:
            f = c * ratio
            out = out + gain / (1 + ((freqs - f) / (f / q)) ** 2)
        return out
    return sculpted(seconds, rng, shape)


# ------------------------------------------------------------------------------------------------ water
def bubble(f0, rng=None, xi=0.1, amp=1.0, seconds=None):
    """One bubble's ring (van den Doel): Minnaert's frequency f0, damped as a bubble that size is, its pitch rising
    as it nears the surface (xi: 0 for none, ~0.1 usual, ~0.4 for a gulp)."""
    d = 0.043 * f0 + 0.0014 * f0 ** 1.5
    life = seconds or min(0.6, 7.0 / d)
    t = t_(life)
    f = f0 * (1 + xi * d * t)
    start = rng.uniform(0, 2 * np.pi) if rng is not None else 0.0
    y = np.sin(phase(f) + start) * np.exp(-d * t)
    ramp = min(len(y), max(8, int(SR * 0.25 / f0)))  # a quarter of its first cycle: forming, not switched on
    y[:ramp] *= np.sin(np.linspace(0, np.pi / 2, ramp)) ** 2
    return amp * y


def radius_to_hz(r_mm):
    return 3.26 / (r_mm / 1000.0)


def bubbles(seconds, rng, rate, r_mm=(0.5, 6.0), beta=2.4, xi=(0.05, 0.25), loud=1.0, size_gain=1.2):
    """A cloud of bubbles: `rate` a second (a number, or an array over the sound's time), radii drawn from a power law
    between r_mm (more small than big, as in real water), each as loud as its size."""
    n = n_(seconds)
    out = np.zeros(n)
    rate_curve = np.full(n, float(rate)) if np.ndim(rate) == 0 else np.interp(np.arange(n), np.linspace(0, n, len(rate)), rate)
    expected = rate_curve.sum() / SR
    count = rng.poisson(max(expected, 0))
    if count == 0:
        return out
    cdf = np.cumsum(rate_curve)
    cdf /= cdf[-1]
    starts = np.searchsorted(cdf, rng.uniform(0, 1, count))
    lo, hi = r_mm
    u = rng.uniform(0, 1, count)
    # Inverse transform for p(r) ~ r^-beta on [lo, hi].
    k = 1 - beta
    radii = (lo ** k + u * (hi ** k - lo ** k)) ** (1 / k)
    for start, r in zip(starts, radii):
        f0 = radius_to_hz(r)
        b = bubble(f0, rng, xi=rng.uniform(*xi), amp=(r / hi) ** size_gain * rng.uniform(0.6, 1.0))
        end = min(n, start + len(b))
        out[start:end] += b[:end - start]
    return out * loud


def droplet(rng, size=1.0, xi=(0.15, 0.45), pitch=(900, 2600)):
    """One drop landing in water: a tiny tick of the surface, then its bubble ringing up (a fountain's plink at the
    default rise; a splash's falling spray with a low `xi`, so it patters rather than plinks)."""
    tick = hp(white(0.004, rng), 2500) * np.exp(-t_(0.004) / 0.0008)
    f0 = rng.uniform(*pitch) / size
    ring = bubble(f0, rng, xi=rng.uniform(*xi), amp=1.0)
    return place(len(ring) / SR + 0.01, [(0.0, 0.35, tick), (rng.uniform(0.001, 0.004), 1.0, ring)])


def splash(rng, size=1.0, seconds=None):
    """Something going into water, `size` 0.3 (a hand) to 3 (a body from a height). As a real splash is: the slap of
    the surface; the crown of spray thrown up, thousands of tiny drops and bubbles at once, fused into a fizz; the
    cavity closing behind it with a low thump; a burst of bubbles under it; and the spray falling back, pattering,
    thinning out."""
    d = seconds or (0.5 + 0.55 * size)
    t = t_(d)
    slap = lp(hp(white(0.06, rng), 250), 3800 / (0.6 + 0.4 * size)) * env(t_(0.06), 0.0005, 0.007 + 0.006 * size)
    crown = env(t, 0.012 + 0.01 * size, 0.09 + 0.1 * size)
    grain = np.clip(0.55 + 0.45 * drift(d, rng, rate=60), 0, 1)
    hiss = lp(bp(white(d, rng), 900, 6500), 5000) * crown * grain
    fizz = bubbles(d, rng, 5000 * size * crown, r_mm=(0.25, 1.4), beta=2.8, xi=(0.0, 0.1), size_gain=0.4)
    cavity = bubble(rng.uniform(110, 170) / size ** 0.45, rng, xi=0.1, amp=1.0, seconds=0.25 + 0.1 * size)
    burst = bubbles(d, rng, 1200 * size * np.exp(-t / (0.05 + 0.04 * size)), r_mm=(0.8, 3.5 + 1.5 * size), beta=2.3,
                    xi=(0.02, 0.15))
    rain = np.zeros(n_(d))
    for _ in range(int(40 * size + 10)):
        at = 0.06 + rng.gamma(1.6, 0.07 + 0.07 * size)
        if at < d - 0.1:
            dr = droplet(rng, size=rng.uniform(0.6, 1.5), xi=(0.03, 0.15), pitch=(1300, 3800))
            a = n_(at)
            b = min(len(rain), a + len(dr))
            rain[a:b] += dr[:b - a] * rng.uniform(0.1, 0.4) * np.exp(-at / (0.25 + 0.25 * size))
    churn = lp(bp(white(d, rng), 200, 2000), 2200) * env(t, 0.006, 0.06 + 0.07 * size)
    return place(d, [(0.0, 0.9, peak(slap)), (0.004, 0.45 + 0.1 * size, peak(cavity)), (0.0, 0.55, peak(hiss)),
                     (0.0, 0.35, peak(fizz)), (0.003, 0.45, peak(burst)), (0.0, 0.3, peak(churn)),
                     (0.0, 0.3, peak(rain) if rain.any() else rain)])


def beach_wave(rng, seconds=7.0, size=None):
    """One wave on a beach, heard from far up: it gathers (a low swell of sound), breaks (a crash, a burst of
    bubbles), and its foam fizzes out over the sand, drawing back with the sand hissing under it."""
    t = t_(seconds)
    build = rng.uniform(0.9, 1.6)
    size = size or rng.uniform(0.6, 1.0)
    gather = lp(pink(seconds, rng), 300 + 400 * size) * np.clip(t / build, 0, 1) ** 2
    gather *= 0.5 + 0.5 * np.cos(np.pi * np.clip((t - build) / 0.5, 0, 1))  # handing over to the crash, smoothly
    after = np.maximum(t - build, 0)
    crash = lp(bp(white(seconds, rng), 200, 4000), 3000) * env(after, 0.22, 0.45 + 0.2 * size) * (t >= build)
    burst = bubbles(seconds, rng, 2600 * size * env(after, 0.15, 0.45) * (t >= build), r_mm=(0.6, 5.0), beta=2.4,
                    xi=(0.02, 0.15))
    foam_env = env(after, 0.3, 1.4 + size) * (t >= build)
    foam = bubbles(seconds, rng, 9000 * foam_env, r_mm=(0.2, 1.0), beta=3.0, xi=(0.0, 0.08), size_gain=0.3)
    drag = lp(bp(white(seconds, rng), 1200, 7000), 6000) * env(np.maximum(t - build - 1.2, 0), 0.6, 1.2) * (t >= build + 1.2)
    return size * (0.6 * peak(gather) + 1.0 * peak(crash) + 0.5 * peak(burst) + 0.55 * peak(foam) + 0.22 * peak(drag))


# ------------------------------------------------------------------------------------------------ struck things
def modal(seconds, freqs, t60s, amps, rng, detune=0.0):
    """A thing's modes ringing: each frequency for its own T60, at its own amplitude, from a random phase."""
    t = t_(seconds)
    out = np.zeros_like(t)
    for f, t60, a in zip(freqs, t60s, amps):
        if f >= SR * 0.45:
            continue
        f = f * (1 + rng.uniform(-detune, detune))
        out += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi)) * np.exp(-6.91 * t / t60)
    return out


def mallet(width_ms):
    """The force of a strike: a raised-cosine pulse, wide for a soft mallet (it rounds the top off), narrow for hard."""
    m = max(3, n_(width_ms / 1000))
    return np.sin(np.linspace(0, np.pi, m)) ** 2


def strike(seconds, freqs, t60s, amps, rng, hardness=0.5, detune=0.0):
    """Modes struck by a mallet: hardness 0 (felt) to 1 (steel)."""
    body = modal(seconds, freqs, t60s, amps, rng, detune)
    width = 6.0 * (1 - hardness) ** 2 + 0.08
    y = signal.fftconvolve(body, mallet(width))[:len(body)]
    return y


# ------------------------------------------------------------------------------------------------ instruments
def felt_piano(f, seconds, rng, velocity=0.5, strings=3, b_stretch=0.00035):
    """A felt piano note: a string's partials, stretched (inharmonic as a real string is), the felt rounding off
    the top, three strings a fraction of a cent apart beating as they ring, a quick first decay and a long one."""
    t = t_(seconds)
    out = np.zeros_like(t)
    top = 1100 + 2600 * velocity
    detunes = [0.0] if strings == 1 else np.linspace(-0.9, 0.9, strings) * rng.uniform(0.6, 1.1)
    for n in range(1, 40):
        fn = n * f * np.sqrt(1 + b_stretch * n * n)
        if fn > 9000:
            break
        level = (1 / n ** 1.05) * np.exp(-(fn / top) ** 1.6)
        if level < 1e-4:
            continue
        fast = 0.9 / (1 + 0.35 * (n - 1)) * (220 / max(f, 60)) ** 0.35
        slow = 9.0 / (1 + 0.5 * (n - 1)) * (220 / max(f, 60)) ** 0.5
        decay = 0.55 * np.exp(-6.91 * t / fast) + 0.45 * np.exp(-6.91 * t / slow)
        for cents in detunes:
            fc = fn * 2 ** (cents / 1200)
            out += level * decay * np.sin(2 * np.pi * fc * t + rng.uniform(0, 2 * np.pi)) / len(detunes)
    thump = lp(white(0.03, rng), 900) * env(t_(0.03), 0.0005, 0.006)
    out = place(seconds, [(0.0, 1.0, out), (0.0, 0.05 + 0.08 * velocity, peak(thump) * np.max(np.abs(out)))])
    out[:n_(0.002)] *= np.linspace(0, 1, n_(0.002))
    return out


def wood_bar(f, seconds, rng, velocity=0.5, ratios=(1.0, 3.93, 9.2), t60s=(1.2, 0.35, 0.09)):
    """A tuned wooden bar (a marimba's, a kalimba's tine is close): the fundamental, the bar's tuned overtones dying
    much faster, and a soft knock of the mallet."""
    freqs = [f * r for r in ratios]
    amps = [1.0, 0.35 * (0.4 + velocity), 0.12 * velocity]
    body = strike(seconds, freqs, [t * (110 / max(f, 80)) ** 0.25 for t in t60s], amps, rng, hardness=0.25 + 0.4 * velocity)
    knock = lp(white(0.02, rng), 1800) * env(t_(0.02), 0.0005, 0.004)
    return place(seconds, [(0.0, 1.0, body), (0.0, 0.04, peak(knock) * np.max(np.abs(body)))])


BELL_PARTIALS = [  # (ratio to the prime, relative amplitude, relative T60): a minor-third bell's hum to its nominal
    (0.5, 0.7, 1.0), (1.0, 1.0, 0.75), (1.183, 0.8, 0.6), (1.506, 0.5, 0.45), (2.0, 0.9, 0.4), (2.514, 0.35, 0.25),
    (2.662, 0.3, 0.22), (3.011, 0.2, 0.16), (4.166, 0.12, 0.1)]


def bell(f_prime, seconds, rng, t60=6.0, hardness=0.45, partials=BELL_PARTIALS):
    """A cast bell rung once: its hum, prime, minor tierce, quint and nominal (the partials real bells have, which is
    why a bell sounds like a bell and not a chime), each ringing on for its own time, the clapper's hit on top."""
    freqs = [f_prime * r for r, _, _ in partials]
    amps = [a for _, a, _ in partials]
    t60s = [t60 * d for _, _, d in partials]
    body = strike(seconds, freqs, t60s, amps, rng, hardness=hardness, detune=0.002)
    # Every partial of a real bell is a pair a hair apart (it is never quite round): a slow warble.
    warble = 1 + 0.06 * np.sin(2 * np.pi * rng.uniform(0.6, 1.4) * t_(seconds) + rng.uniform(0, 6.28))
    return body * warble


def warm_pad(notes, seconds, rng, attack=1.5, release=2.5, brightness=0.5, voices=5, stagger=0.0):
    """A soft held chord: each note several detuned voices of a rounded saw (strings, a choir's 'oo'), a slow vibrato
    wandering in each, the top rolled off; swelling in over `attack` and away over `release`."""
    t = t_(seconds)
    out = np.zeros_like(t)
    top = 600 + 2400 * brightness
    for k, f in enumerate(notes):
        start = k * stagger
        shape = swell(np.maximum(t - start, 0), seconds - start, attack, release) * (t >= start)
        for v in range(voices):
            cents = (v - (voices - 1) / 2) * 7 / max(voices - 1, 1) * 2 + rng.uniform(-1.5, 1.5)
            vib = 1 + 0.0025 * drift(seconds, rng, rate=0.8) + 0.0012 * np.sin(2 * np.pi * rng.uniform(4.6, 5.6) * t)
            fv = f * 2 ** (cents / 1200) * vib
            ph = phase(fv) + rng.uniform(0, 2 * np.pi)
            voice = np.zeros_like(t)
            for n in range(1, 24):
                if n * f > 7000:
                    break
                voice += np.sin(n * ph) / n * np.exp(-(n * f / top) ** 2)
            out += voice * shape / voices
    return out


# ------------------------------------------------------------------------------------------------ rooms
SPACES = {
    # rt60 low / high (s), predelay (s), early reflections [(s, gain)], diffusion
    "small": dict(rt_low=0.35, rt_high=0.18, pre=0.004, early=[(0.006, 0.4), (0.011, 0.3), (0.017, 0.2)]),
    "tiles": dict(rt_low=2.6, rt_high=1.6, pre=0.014, early=[(0.019, 0.5), (0.031, 0.42), (0.047, 0.35), (0.066, 0.3)]),
    "shaft": dict(rt_low=2.2, rt_high=0.9, pre=0.02, early=[(0.028, 0.55), (0.056, 0.45), (0.084, 0.38), (0.112, 0.3)]),
    "culvert": dict(rt_low=3.2, rt_high=1.1, pre=0.03, early=[(0.045, 0.55), (0.09, 0.45), (0.135, 0.36), (0.18, 0.28),
                                                               (0.225, 0.2)]),
    "harbour": dict(rt_low=1.4, rt_high=0.5, pre=0.06, early=[(0.08, 0.25), (0.19, 0.15)]),
    "open": dict(rt_low=0.6, rt_high=0.25, pre=0.03, early=[(0.05, 0.15)]),
    "under": dict(rt_low=1.8, rt_high=0.35, pre=0.01, early=[(0.015, 0.4), (0.03, 0.3)]),
    "hall": dict(rt_low=3.4, rt_high=2.2, pre=0.025, early=[(0.021, 0.35), (0.037, 0.3), (0.052, 0.26), (0.071, 0.2)]),
    "cavern": dict(rt_low=5.5, rt_high=1.8, pre=0.05, early=[(0.07, 0.5), (0.15, 0.4), (0.24, 0.3)]),
}


def make_ir(space, rng):
    """A room's impulse response: its early reflections, then a diffuse tail whose highs die faster than its lows."""
    p = SPACES[space]
    length = p["rt_low"] * 1.2 + p["pre"] + 0.1
    t = t_(length)
    tail = np.zeros_like(t)
    edges = [40, 160, 500, 1500, 4000, 9000, 18000]
    rts = np.geomspace(p["rt_low"], p["rt_high"], len(edges) - 1)
    for (lo, hi), rt in zip(zip(edges[:-1], edges[1:]), rts):
        tail += bp(white(length, rng), lo, hi, order=2) * np.exp(-6.91 * t / rt)
    tail *= np.clip((t - p["pre"]) / 0.02, 0, 1)
    ir = 0.35 * tail / (np.sqrt(np.sum(tail ** 2)) + 1e-12)
    for at, gain in p["early"]:
        k = n_(p["pre"] * 0.5 + at)
        if k < len(ir):
            spread = lp(white(0.003, rng), 6000) * np.hanning(n_(0.003))
            ir[k:k + len(spread)] += gain * 0.25 * spread[:len(ir) - k]
    return ir


def reverb(x, space, rng, wet=0.3, dry=1.0):
    """The sound in a room: dry plus its convolution with the room's response (the result keeps x's length plus the
    tail, so a one-shot rings on)."""
    ir = make_ir(space, rng)
    w = signal.fftconvolve(x, ir)
    out = np.zeros(len(w))
    out[:len(x)] += dry * x
    scale = np.sqrt(np.mean(x ** 2) + 1e-12) / (np.sqrt(np.mean(w[:len(x)] ** 2)) + 1e-12)
    out += wet * w * scale
    return out


def reverb_loop(x, space, rng, wet=0.3):
    """Reverb on a loop: the tail that runs past the end is folded back over the start, so it still loops."""
    y = reverb(x, space, rng, wet)
    out = y[:len(x)].copy()
    rest = y[len(x):]
    while len(rest):
        k = min(len(rest), len(out))
        out[:k] += rest[:k]
        rest = rest[k:]
    return out


# ------------------------------------------------------------------------------------------------ level
def _k_weight(x):
    b1, a1 = biquad("highshelf", 1500.0, 1 / np.sqrt(2), 4.0)
    w0 = 2 * np.pi * 38.0 / SR
    alpha = np.sin(w0) / (2 * 0.5)
    b2 = np.array([(1 + np.cos(w0)) / 2, -(1 + np.cos(w0)), (1 + np.cos(w0)) / 2])
    a2 = np.array([1 + alpha, -2 * np.cos(w0), 1 - alpha])
    return signal.lfilter(b2 / a2[0], a2 / a2[0], signal.lfilter(b1, a1, x))


def lufs(x):
    """Loudness (LUFS, BS.1770): gated over 400 ms blocks; for a sound shorter than a block, over its loud part."""
    x = np.asarray(x, dtype=float)
    if not len(x) or not np.any(x):
        return -120.0
    y = _k_weight(x)
    block, hop = n_(0.4), n_(0.1)
    if len(y) < block:
        env_ = np.abs(x)
        active = env_ > np.max(env_) * 10 ** (-40 / 20)
        ms = np.mean(y[active] ** 2) if active.any() else np.mean(y ** 2)
        return -0.691 + 10 * np.log10(ms + 1e-15)
    powers = np.array([np.mean(y[i:i + block] ** 2) for i in range(0, len(y) - block + 1, hop)])
    loud = -0.691 + 10 * np.log10(powers + 1e-15)
    gated = powers[loud > -70]
    if not len(gated):
        return -120.0
    rel = -0.691 + 10 * np.log10(np.mean(gated)) - 10
    gated = powers[(loud > -70) & (loud > rel)]
    return -0.691 + 10 * np.log10(np.mean(gated) + 1e-15)


def limit(x, ceiling_db=-1.0):
    """Peaks above the ceiling rounded down (a soft knee), everything under it left exactly as it was."""
    c = 10 ** (ceiling_db / 20)
    knee = 0.8 * c
    y = np.array(x, dtype=float)
    over = np.abs(y) > knee
    if over.any():
        s = np.sign(y[over])
        a = np.abs(y[over]) - knee
        y[over] = s * (knee + (c - knee) * np.tanh(a / (c - knee)))
    return y


def match(x, target_lufs, ceiling_db=-1.0):
    """To the loudness asked, then any peak over the ceiling softly held under it."""
    x = np.asarray(x, dtype=float) - np.mean(x)
    gain = 10 ** ((target_lufs - lufs(x)) / 20)
    return limit(x * gain, ceiling_db)


def finish(x, target_lufs, low_cut=30.0, high_cut=None, fade_in=0.0005, fade_out=0.02, ceiling_db=-1.0):
    """The last step of every one-shot: no rumble below hearing, the top rolled where asked, smooth ends, to level."""
    y = hp(np.asarray(x, dtype=float), low_cut, order=2)
    if high_cut:
        y = lp(y, high_cut, order=2)
    y = fade(y, fade_in, fade_out)
    return match(y, target_lufs, ceiling_db)


def seamless(x, loop_seconds, overlap_seconds):
    """A loop `loop_seconds` long from a render at least that plus the overlap: the overlap past the end crossfaded
    (equal power) into the start, so the last sample runs straight on into the first."""
    n, m = n_(loop_seconds), n_(overlap_seconds)
    assert len(x) >= n + m, (len(x), n + m)
    out = np.array(x[:n], dtype=float)
    w = np.linspace(0, np.pi / 2, m)
    out[:m] = x[:m] * np.sin(w) + x[n:n + m] * np.cos(w)
    return out


def finish_loop(x, loop_seconds, overlap_seconds, target_lufs, low_cut=30.0, high_cut=None, ceiling_db=-3.0):
    """The last step of every bed: filtered while it is still a long render (a filter run after the seam would start
    cold at the loop point and click there), then made seamless, then put to level. Nothing touches it after."""
    y = hp(np.asarray(x, dtype=float), low_cut, order=2)
    if high_cut:
        y = lp(y, high_cut, order=2)
    y = seamless(y, loop_seconds, overlap_seconds)
    return match(y - np.mean(y), target_lufs, ceiling_db)


# ------------------------------------------------------------------------------------------------ files
def write(path, x):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    x = np.asarray(x, dtype=float)
    data = np.clip(np.round(x * 32767), -32768, 32767).astype(np.int16)
    wavfile.write(path, SR, data)
    return describe(x, path.name)


def write_sheet(path, takes, slot):
    """Several takes in ONE file (one upload), take k starting at k * `slot` seconds and over before the next begins
    (each faded out inside its slot): the game plays a take by its slot (Sound.PlaybackRegion)."""
    out = np.zeros(n_(slot * len(takes)))
    for k, x in enumerate(takes):
        x = np.asarray(x, dtype=float)
        room = n_(slot - 0.05)
        if len(x) > room:
            x = fade(x[:room], 0, 0.15)
        out[n_(slot * k):n_(slot * k) + len(x)] = x
    return write(path, out)


def read(path):
    rate, data = wavfile.read(str(path))
    assert rate == SR, (path, rate)
    if data.ndim > 1:
        data = data.mean(axis=1)
    return data.astype(float) / 32768.0


def centroid(x):
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)))) if len(x) < SR * 4 else None
    if spec is None:
        f, _, z = signal.stft(x, SR, nperseg=4096)
        mags = np.abs(z).mean(axis=1)
        return float(np.sum(f * mags) / (np.sum(mags) + 1e-12))
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return float(np.sum(f * spec) / (np.sum(spec) + 1e-12))


def describe(x, name=""):
    return "%-28s %6.2f s  peak %5.1f dB  %6.1f LUFS  centroid %5.0f Hz" % (
        name, len(x) / SR, 20 * np.log10(np.max(np.abs(x)) + 1e-12), lufs(x), centroid(x))
