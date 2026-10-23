"""Eleven chunk sounds, each as ONE FILE of four takes (the eighty-eighth pass, from your second test).

    python audio/gen_sheet_sfx.py              every one
    python audio/gen_sheet_sfx.py iceCrack     only the events named

Writes audio/sheets/<event>_x4.wav: four takes, each in its own one-second slot (take k starts at k seconds and is
over well before the next). AudioService reads a Sound named `<event>_x4` as four takes and plays each from its own
slot (Sound.PlaybackRegion), so a material gets four takes for ONE upload instead of four: eleven files here, not 44.

  chocolateSnap_x4       the chocolate you can crack: a dry woody snap and crumbs (it rang like glass tapped with a
                         fingernail: inharmonic partials left ringing)
  chocolateChunk_x4      the solid chocolate, now its own: a thick block cracking, deeper, heavier crumbs
  slimeBoing_x4          more slime: four wet boings to go with the one you uploaded
  jellyBounce_x4         the jellyfish, now its own: a round, soft gel bounce with a wobble and a little fizz
  soapCrumble_x4         more soap: a waxy press with fine dry crumbs, to go with the one you uploaded
  cookieCrunch_x4        the cookie (the hundred-and-tenth pass): a crisp break in two, a dry thud under it, and crumbs
                         skittering off, drier and crisper than the soap
  foamCompress_x4        the memory foam remade: a slow soft sink of air, nothing sharp
  switchClack_x4         the light switches remade: a toggle's two-stage click with a plastic body under it
  kineticSandImprint_x4  the sand remade: a dense hush of fine grains pressed together, and a soft thump
  iceCrack_x4            the ice remade: a crack, a crackle running off it and a hollow knock under it
  jelloWobble_x4         the jelly soda remade: a wet wobble with a carbonated fizz on its tail
  bubblePop_x4           the bubble wrap remade: a crisp pop that starts on its first sample (no lead-in), so it is
                         heard the moment your foot lands
  ooblSquelch_x4         the oobleck remade (the hundred-and-twenty-sixth pass, from your test: "I want oobleck to have
                         a better sound"): it goes firm under the blow, a thick muffled thup; then the foot sinks in,
                         a dense creamy squeeze with thick slow bubbles coming up; and it holds on as the foot comes
                         away, a soft sticky suck. No splash, nothing bright

AND SINCE THE NINETY-SIXTH PASS, the keypad's four short sounds (gen_keypad_sfx.py, made of sfx_kit.py's parts):

  button_clicky_x4       the keypad's cyan: the arcade microswitch's snap, the cap bottoming out, a rush of air
  button_linear_x3       violet: a deep creamy thock and a low wooden note held for you
  button_tactile_x3      pink: the bump in the travel and a rubbery, springy bounce
  button_release_x3      any switch back up: a lighter click, the cap tapping its bezel

THE SAME RULES AS gen_chunk_sfx.py: layers for the parts of the thing, nothing made of a plain undamped tone (a body
is shaped noise, grains or quickly damped resonances), soft high end, and four takes that differ in what happens.

Seeded from each event's name, so re-running writes the same files.
"""
import pathlib
import sys
import zlib

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_button_sfx import SR, axis, envelope, filt, finish, mix, peak, phase, punch, taper  # noqa: E402
from gen_chunk_sfx import band, brown, grains, noise, swell  # noqa: E402
from gen_keypad_sfx import SHEETS as KEYPAD  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent
SHEETS = HERE / "sheets"
SLOT = 1.0  # seconds a take has in its sheet: AudioService plays slot k from k * SLOT
TAKES = 4


def damped(freqs, decays, duration, rng, detune=0.02):
    """Quickly damped resonances: a knock, not a ring (each dies in a few tens of milliseconds)."""
    t = axis(duration)
    out = np.zeros_like(t)
    for f, d in zip(freqs, decays):
        f = f * (1 + rng.uniform(-detune, detune))
        out += np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / d)
    return out


def burst(duration, low, high, attack, decay, rng):
    t = axis(duration)
    return band(noise(duration, rng), low, high) * envelope(t, attack, decay)


# ---------------------------------------------------------------------------------------------------- the makers
def chocolate_snap(take, rng):
    """A bar of chocolate snapping: a dry break, a woody knock, crumbs; never a ring."""
    d = 0.55
    snap_at = 0.0
    layers = []
    if take == 4:
        # Bent first: a short creak of tiny breaks, then the snap.
        layers.append((0.0, 0.35, grains(0.05, 10, rng, 1200, 3200, length=(0.0006, 0.002), where=(1, 1))))
        snap_at = 0.045
    for k, offset in enumerate([snap_at] + ([snap_at + 0.035] if take == 2 else [])):
        level = 1.0 if k == 0 else 0.7
        layers.append((offset, level, burst(0.03, 1100, 4200, 0.0004, 0.005, rng)))
        layers.append((offset, 0.8 * level, damped([rng.uniform(380, 520), rng.uniform(850, 1050), rng.uniform(1500, 1750)],
                                                   [0.016, 0.009, 0.005], 0.09, rng)))
    crumbs = {1: 5, 2: 6, 3: 14, 4: 7}[take]
    layers.append((snap_at + 0.015, 0.32, grains(0.3, crumbs, rng, 900, 3400, length=(0.001, 0.004), where=(1.4, 4))))
    return finish(mix(d, layers), -2.0, lowpass=6500)


def chocolate_chunk(take, rng):
    """A block of solid chocolate cracking: deeper and heavier, a thud under the break, chunks after."""
    d = 0.7
    layers = [(0.0, 0.7, punch(0.12, 110, 62, 0.02, 0.04, drive=1.4))]
    breaks = {1: [0.0], 2: [0.0, 0.04], 3: [0.0], 4: [0.02]}[take]
    if take == 4:
        layers.append((0.0, 0.3, grains(0.04, 8, rng, 600, 2000, length=(0.001, 0.003), where=(1, 1))))
    for k, at in enumerate(breaks):
        level = 1.0 if k == 0 else 0.8
        layers.append((at, level, burst(0.04, 700, 2800, 0.0006, 0.008, rng)))
        layers.append((at, 0.9 * level, damped([rng.uniform(180, 260), rng.uniform(380, 520), rng.uniform(760, 900)],
                                                [0.028, 0.017, 0.009], 0.15, rng)))
    crumbs = {1: 9, 2: 10, 3: 22, 4: 12}[take]
    layers.append((0.02, 0.38, grains(0.45, crumbs, rng, 500, 2400, length=(0.002, 0.007), where=(1.3, 3.5))))
    return finish(mix(d, layers), -1.5, lowpass=5000)


def slime_boing(take, rng):
    """Slime: a wet boing (a pitch that bounces and settles) inside a gloop of bubbles."""
    d = 0.6
    t = axis(d)
    base = {1: 150, 2: 180, 3: 130, 4: 165}[take] * rng.uniform(0.97, 1.03)
    bounce = {1: 0.55, 2: 0.4, 3: 0.7, 4: 0.5}[take]
    f = base * (1 + bounce * np.exp(-t / 0.045)) * (1 + 0.07 * np.sin(2 * np.pi * rng.uniform(6, 8) * t) * np.exp(-t / 0.22))
    tone = np.tanh(1.6 * np.sin(phase(f))) * envelope(t, 0.006, 0.18)
    tone = filt(tone, "low", 900)
    bubbles = grains(d, {1: 6, 2: 9, 3: 5, 4: 12}[take], rng, 250, 1300, length=(0.006, 0.02), where=(1.3, 2.5), soft=0.8)
    wet = band(noise(d, rng), 200, 1100) * envelope(t, 0.004, 0.05)
    return finish(peak(tone) + 0.45 * peak(bubbles) + 0.35 * peak(wet), -2.0, lowpass=3500)


def jelly_bounce(take, rng):
    """The jellyfish: round and soft, a gel bell that wobbles as it gives, a wet plap, a breath of fizz."""
    d = 0.75
    t = axis(d)
    # Pitched where a phone's or a laptop's speaker can play it (a body at 100 Hz is felt on headphones and lost on those).
    base = {1: 150, 2: 172, 3: 138, 4: 160}[take] * rng.uniform(0.97, 1.03)
    wob = rng.uniform(5, 7)
    f = base * (1 + 0.25 * np.exp(-t / 0.06)) * (1 + 0.09 * np.sin(2 * np.pi * wob * t) * np.exp(-t / 0.35))
    body = np.sin(phase(f)) * envelope(t, 0.012, 0.3)
    body += 0.45 * np.sin(phase(f * 2.01)) * envelope(t, 0.012, 0.14) + 0.15 * np.sin(phase(f * 3.02)) * envelope(t, 0.01, 0.06)
    plap = filt(band(noise(d, rng), 180, 900) * envelope(t, 0.002, 0.018), "low", 1200)
    fizz = grains(d, {1: 10, 2: 16, 3: 8, 4: 20}[take], rng, 2000, 5200, length=(0.0005, 0.0015), where=(2, 2.5), soft=0.4)
    return finish(peak(body) + 0.5 * peak(plap) + 0.08 * peak(fizz), -2.5, lowpass=5500)


def soap_crumble(take, rng):
    """Soap: a waxy press, dull and soft, and fine dry crumbs coming off it."""
    d = 0.5
    t = axis(d)
    press = filt(band(noise(d, rng), 140, 900) * envelope(t, 0.004, 0.03), "low", 1000)
    crumbs = grains(d, {1: 12, 2: 20, 3: 8, 4: 26}[take], rng, 1100, 4000, length=(0.0008, 0.003), where=(1.3, 3.0))
    layers = [(0.0, 1.0, press), (0.006, 0.45, crumbs)]
    if take == 3:
        layers.append((0.09, 0.6, filt(band(noise(0.2, rng), 140, 800) * envelope(axis(0.2), 0.004, 0.025), "low", 900)))
    return finish(mix(d, layers), -3.0, lowpass=5500)


def cookie_crunch(take, rng):
    """A cookie giving way under a foot: a crisp break, often in two (the top, then the middle), a dry thud under it,
    and crumbs skittering off, crisper and drier than the soap's."""
    d = 0.6
    layers = [(0.0, 0.5, punch(0.1, 140, 80, 0.015, 0.03, drive=1.2))]
    breaks = {1: [0.0, 0.035], 2: [0.0], 3: [0.0, 0.05, 0.09], 4: [0.01, 0.04]}[take]
    for k, at in enumerate(breaks):
        level = 1.0 if k == 0 else 0.7 - 0.1 * k
        layers.append((at, level, burst(0.03, 900, 3600, 0.0004, 0.006, rng)))
    crumbs = {1: 22, 2: 30, 3: 18, 4: 34}[take]
    layers.append((0.015, 0.42, grains(0.5, crumbs, rng, 1200, 4200, length=(0.0008, 0.0025), where=(1.2, 3.2))))
    return finish(mix(d, layers), -2.0, lowpass=5200)


def foam_compress(take, rng):
    """Memory foam: a slow soft sink of air, a deeper push under it, a whisper of fabric; nothing sharp."""
    d = 0.8
    t = axis(d)
    attack = {1: 0.03, 2: 0.07, 3: 0.03, 4: 0.05}[take]
    air = filt(band(noise(d, rng), 120, 1300), "low", 1400) * envelope(t, attack, 0.22)
    push = filt(brown(d, rng), "low", 260) * envelope(t, attack * 1.2, 0.18)
    rustle = grains(d, {1: 8, 2: 14, 3: 6, 4: 10}[take], rng, 900, 2600, length=(0.004, 0.012), where=(1.5, 3), soft=0.9)
    layers = [(0.0, 1.0, peak(air)), (0.0, 0.7, peak(push)), (0.0, 0.12, peak(rustle))]
    if take == 3:
        layers.append((0.16, 0.6, peak(filt(band(noise(0.4, rng), 120, 1100), "low", 1200) * envelope(axis(0.4), 0.03, 0.15))))
    return finish(mix(d, layers), -4.0, lowpass=3000)


def switch_clack(take, rng):
    """A light switch: the toggle's two-stage click, a plastic body knocked under it, a little spring."""
    d = 0.3
    gap = {1: 0.006, 2: 0.008, 3: 0.005, 4: 0.009}[take]
    first, second = (1.0, 0.75) if take in (1, 3) else (0.7, 1.0)
    layers = [
        (0.0, first, burst(0.02, 1600, 6000, 0.0003, 0.0025, rng)),
        (gap, second, burst(0.03, 800, 2600, 0.0004, 0.006, rng)),
        (gap, 0.55, damped([rng.uniform(1700, 2000), rng.uniform(2500, 2900)], [0.008, 0.005], 0.05, rng)),
        (gap, 0.5, punch(0.05, 240, 170, 0.008, 0.015, drive=1.2)),
        (gap + 0.01, 0.12, damped([rng.uniform(3200, 3600)], [0.02], 0.06, rng)),
    ]
    return finish(mix(d, layers), -2.0, lowpass=9000)


def kinetic_sand(take, rng):
    """Kinetic sand: a dense hush of fine grains pressed together, packing, and a soft thump under it."""
    d = 0.6
    t = axis(d)
    count = {1: 160, 2: 220, 3: 120, 4: 260}[take]
    span = {1: 0.28, 2: 0.4, 3: 0.22, 4: 0.45}[take]
    sand = grains(span, count, rng, 500, 3200, length=(0.0005, 0.002), where=(1.4, 2.4), fade=0.8, soft=0.5)
    sand = np.concatenate([sand, np.zeros(int(SR * d) - len(sand))])
    thump = filt(brown(d, rng), "low", 200) * envelope(t, 0.01, 0.06)
    layers = [(0.0, 1.0, peak(sand)), (0.0, 0.55, peak(thump))]
    if take == 2:
        layers.append((0.14, 0.45, peak(filt(brown(0.3, rng), "low", 220) * envelope(axis(0.3), 0.01, 0.05))))
    return finish(mix(d, layers), -3.0, lowpass=4500)


def ice_crack(take, rng):
    """Ice: a crack, a crackle running off it, and a hollow knock under it; a low creak on the heavier ones."""
    d = 0.6
    layers = [
        (0.0, 1.0, burst(0.03, 1800, 6000, 0.0003, 0.004, rng)),
        (0.002, 0.5, grains(0.08, {1: 14, 2: 22, 3: 10, 4: 28}[take], rng, 1500, 5500, length=(0.0005, 0.002), where=(1, 3))),
        (0.0, 0.6, damped([rng.uniform(650, 820), rng.uniform(1300, 1600)], [0.06, 0.035], 0.25, rng)),
    ]
    if take in (2, 4):
        t = axis(0.25)
        creak = band(noise(0.25, rng), 180, 420) * (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(25, 40) * t)) * envelope(t, 0.02, 0.08)
        layers.append((0.03, 0.35, creak))
    if take == 3:
        layers.append((0.05, 0.6, burst(0.03, 1800, 5500, 0.0003, 0.004, rng)))
    return finish(mix(d, layers), -2.5, lowpass=7500)


def jello_wobble(take, rng):
    """Jelly soda: a wet low wobble as it gives, and a carbonated fizz on its tail."""
    d = 0.8
    t = axis(d)
    base = {1: 150, 2: 168, 3: 136, 4: 160}[take] * rng.uniform(0.97, 1.03)
    f = base * (1 + 0.12 * np.sin(2 * np.pi * rng.uniform(8, 11) * t) * np.exp(-t / 0.3))
    body = np.sin(phase(f)) * envelope(t, 0.01, 0.28) + 0.4 * np.sin(phase(f * 2.02)) * envelope(t, 0.01, 0.12)
    squelch = filt(band(noise(d, rng), 200, 1200) * envelope(t, 0.003, 0.03), "low", 1400)
    fizz = grains(d, {1: 26, 2: 40, 3: 20, 4: 50}[take], rng, 2200, 6000, length=(0.0004, 0.0012), where=(1.6, 2.2),
                  fade=0.4, soft=0.3)
    return finish(peak(body) + 0.5 * peak(squelch) + 0.12 * peak(fizz), -2.5, lowpass=6500)


def bubble_pop(take, rng):
    """A bubble of bubble wrap popping: on its very first sample, a crisp snap, a little tonal pock and a puff of air."""
    d = 0.25
    t = axis(d)
    snap = band(noise(d, rng), 900, 5000, order=2) * np.exp(-t / 0.0025)
    snap[:16] *= np.linspace(0.6, 1.0, 16)  # no lead-in: loud from the first millisecond, only the hard edge taken off
    pock = damped([{1: 1900, 2: 2300, 3: 1600, 4: 2600}[take]], [0.006], d, rng)
    puff = band(noise(d, rng), 300, 2000) * np.exp(-t / 0.015)
    x = peak(snap) + 0.55 * peak(pock) + 0.2 * peak(puff)
    x = filt(x, "low", 8000)
    x = filt(x, "high", 60, order=2)
    return taper(peak(x) * (10 ** (-2.0 / 20)), 0.6)


def oobleck(take, rng):
    """Oobleck: cornflour and water. Struck, it goes firm for a moment: a thick, muffled thup, like patting a full bag
    of cream; then it lets go and the foot sinks into it slowly, a dense creamy squeeze; thick slow blorps come up
    through it; and it holds on as the foot comes away, a soft sticky suck. No splash, nothing bright, low and soft.
    Four takes that differ in what happens: a quick firm step; one that sinks a long way; a stamp, where it stays firm
    and shudders; and one that holds on as you pull away."""
    d = 0.9
    firm = {1: 0.9, 2: 0.7, 3: 1.0, 4: 0.8}[take]
    # THE THUP: the surface going firm under the blow, muffled and dense, a quickly damped body under it.
    thup = filt(brown(0.12, rng), "low", 420) * envelope(axis(0.12), 0.004, 0.03)
    body = damped([rng.uniform(88, 104), rng.uniform(150, 175), rng.uniform(230, 260)], [0.035, 0.022, 0.012], 0.2, rng)
    layers = [(0.0, firm, taper(peak(thup))), (0.0, 0.5 * firm, peak(body))]
    # THE SINK: a thick creamy squeeze, its weight moving lower as the foot goes in.
    sink = {1: 0.28, 2: 0.55, 3: 0.18, 4: 0.4}[take]
    st = axis(sink)
    high = band(noise(sink, rng), 380, 1100) * swell(st, 0.05, 0.03, sink * 0.25)
    low = filt(brown(sink, rng), "low", 360) * swell(st, sink * 0.4, 0.04, sink * 0.3)
    squeeze = peak(high) * np.linspace(1, 0.3, len(st)) + peak(low) * np.linspace(0.4, 1, len(st))
    layers.append((0.03, 0.6, taper(peak(squeeze))))
    # THE BLORPS: thick, slow bubbles coming up through it, low, each a pitch rising as it closes, quickly damped.
    for _ in range({1: 1, 2: 3, 3: 0, 4: 2}[take]):
        size = rng.uniform(0.04, 0.07)
        bt = axis(size)
        f0 = rng.uniform(170, 260)
        blorp = np.sin(phase(f0 * (1 + 0.9 * bt / size))) * envelope(bt, 0.006, size * 0.35)
        layers.append((rng.uniform(0.08, 0.08 + sink), 0.3, filt(blorp, "low", 900)))
    # A STAMP shudders: it stays firm, a dense rubbery quiver for a moment.
    if take == 3:
        q = axis(0.16)
        quiver = filt(noise(0.16, rng), "band", [90, 300], 2) * (0.6 + 0.4 * np.sin(2 * np.pi * 22 * q)) * envelope(q, 0.004, 0.05)
        layers.append((0.02, 0.5, peak(quiver)))
    # THE PULL: it holds on as the foot comes away: a soft sticky suck, then the last of it letting go.
    pull_at = {1: 0.42, 2: 0.66, 3: 0.3, 4: 0.5}[take]
    hold = {1: 0.06, 2: 0.08, 3: 0.04, 4: 0.16}[take]
    pt = axis(hold + 0.08)
    suck = band(noise(hold + 0.08, rng), 160, 620) * swell(pt, hold, 0.0, 0.03)
    smack = band(noise(0.05, rng), 500, 1600) * envelope(axis(0.05), 0.003, 0.01)
    layers += [(pull_at, 0.38, taper(peak(suck))), (pull_at + hold, 0.28, peak(smack))]
    return finish(mix(d, layers), -3.0, lowpass=3200)


EVENTS = [("chocolateSnap", chocolate_snap), ("chocolateChunk", chocolate_chunk), ("slimeBoing", slime_boing),
          ("jellyBounce", jelly_bounce), ("soapCrumble", soap_crumble), ("cookieCrunch", cookie_crunch),
          ("foamCompress", foam_compress),
          ("switchClack", switch_clack), ("kineticSandImprint", kinetic_sand), ("iceCrack", ice_crack),
          ("jelloWobble", jello_wobble), ("bubblePop", bubble_pop), ("ooblSquelch", oobleck)]
# The ninety-sixth pass's: the keypad's four short sounds (some three takes). (Not the lava crust and the Needoh: you
# liked them as they are, gen_needoh_lava_sfx.py's.)
EVENTS += [(stem, make) for stem, make, _ in KEYPAD]
TAKES_OF = {stem: takes for stem, _, takes in KEYPAD}


def sheet(event, make):
    rng = np.random.default_rng(zlib.crc32(event.encode()) + 8800)
    takes = TAKES_OF.get(event, TAKES)
    out = np.zeros(int(SR * SLOT * takes))
    lengths = []
    for take in range(1, takes + 1):
        x = np.asarray(make(take, rng), dtype=float)
        assert len(x) <= int(SR * (SLOT - 0.05)), (event, take, len(x) / SR)
        start = int(SR * SLOT * (take - 1))
        out[start:start + len(x)] = x
        lengths.append(len(x) / SR)
    return out, lengths


if __name__ == "__main__":
    wanted = set(sys.argv[1:])
    SHEETS.mkdir(parents=True, exist_ok=True)
    for event, make in EVENTS:
        if wanted and event not in wanted:
            continue
        x, lengths = sheet(event, make)
        wavfile.write(SHEETS / ("%s_x%d.wav" % (event, len(lengths))), SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))
        print("  %-24s %d takes, %s s" % (event, len(lengths), ", ".join("%.2f" % v for v in lengths)))
