"""The shop's own sounds (the hundred-and-fifth pass): opening it, closing it, its tabs, a cookie, and its crates.

    python audio/gen_shop_sfx.py

Writes audio/shop/, for a Folder SoundService.ShopSounds:

    ShopOpen          a sweet jar's lid twisted off with a soft pop, and a few warm notes tumbling out
    ShopClose         the lid set back on and pressed down: a hollow thock and a click
    ShopTab_x9        a different small sound for each kind of thing in the shop, in the order of its tabs
                      (ShopCatalog.TABS, then Backgrounds): Featured a sparkle of notes, Steps two footfalls on wood,
                      Trails a soft swish, Sounds a squeak toy, Auras a bell's shimmer, Emotes a rubber boing, Passes a
                      ticket stamped, Tokens coins chinking, Backgrounds a roll of paper unrolling
    CookieCrunch_x4   biting a crisp biscuit: the snap, crumbs falling (the cursor's bite, the cookie background)
    CrateShake        a crate of backgrounds shaken: a box rattling with something soft inside
    CrateReveal_x5    what came out, by its rarity: common a soft pop, rare a chime, epic notes rising, legendary a bell
                      and a shimmer, mythic a deep warm chord with the floor under it

Soft and warm (the game's taste: low, round, nothing shrill or pitched up). Seeded: re-running writes the same files.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from sfx_kit import (SR, bell, bp, bubble, env, felt_piano, finish, lp, n_, peak, reverb, rng_for,  # noqa
                     strike, t_, white, wood_bar, write, write_sheet)

OUT = pathlib.Path(__file__).resolve().parent / "shop"

# Each sheet's slot, in seconds: ShopLook has the same numbers (check_audio.py holds them to it).
SLOTS = {"ShopTab": 1.2, "CookieCrunch": 0.9, "CrateReveal": 3.0}


def add(out, x, at, gain=1.0):
    x = np.array(x, dtype=float)
    k = min(len(x), n_(0.06))
    if k > 1:
        x[-k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    a = n_(at)
    if a < len(out):
        b = min(len(out), a + len(x))
        out[a:b] += gain * x[:b - a]


def shop_open(rng):
    seconds = 1.6
    x = np.zeros(n_(seconds))
    t = t_(0.3)
    twist = bp(white(0.3, rng), 700, 2400) * (0.5 + 0.5 * np.sin(2 * np.pi * 38 * t) ** 2) * env(t, 0.03, 0.25)
    add(x, peak(twist), 0.0, 0.18)
    add(x, peak(bubble(380, rng, xi=0.12)), 0.3, 0.7)
    add(x, peak(lp(white(0.03, rng), 1500) * env(t_(0.03), 0.0003, 0.008)), 0.3, 0.3)
    for k, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        add(x, peak(wood_bar(f, 1.0, rng, velocity=0.35)), 0.38 + k * 0.07, 0.32 - 0.04 * k)
    x = reverb(x, "open", rng, wet=0.22)[:n_(seconds)]
    return finish(x, -20.0, high_cut=4500, fade_out=0.3)


def shop_close(rng):
    seconds = 0.9
    x = np.zeros(n_(seconds))
    lid = strike(0.4, [210, 470, 980], [0.14, 0.06, 0.03], [1.0, 0.45, 0.15], rng, hardness=0.35)
    add(x, peak(lid), 0.0, 1.0)
    add(x, peak(strike(0.1, [1500, 2600], [0.03, 0.015], [1.0, 0.3], rng, hardness=0.6)), 0.11, 0.3)
    x = reverb(x, "small", rng, wet=0.2)[:n_(seconds)]
    return finish(x, -21.0, high_cut=4000, fade_out=0.15)


def tab(take, rng):
    seconds = 1.1
    x = np.zeros(n_(seconds))
    if take == 0:  # Featured: a sparkle of notes
        for k, f in enumerate([783.99, 987.77, 1174.66]):
            add(x, peak(wood_bar(f, 0.8, rng, velocity=0.3)), k * 0.05, 0.4)
    elif take == 1:  # Steps: two footfalls on wood
        for k in range(2):
            add(x, peak(strike(0.25, [160, 340, 620], [0.08, 0.04, 0.02], [1.0, 0.4, 0.15], rng, hardness=0.3)),
                k * 0.16, 0.9 - 0.2 * k)
    elif take == 2:  # Trails: a soft swish
        t = t_(0.45)
        sweep = bp(white(0.45, rng), 300, 2400) * np.sin(np.pi * np.clip(t / 0.45, 0, 1)) ** 2
        add(x, peak(lp(sweep, 2600)), 0.0, 0.8)
    elif take == 3:  # Sounds: a squeak toy
        t = t_(0.28)
        f = np.interp(t, [0, 0.12, 0.28], [520, 760, 600])
        squeak = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(t, 0.01, 0.2)
        squeak += 0.3 * bp(white(0.28, rng), 500, 1800) * env(t, 0.01, 0.15)
        add(x, peak(squeak), 0.0, 0.6)
    elif take == 4:  # Auras: a bell's shimmer
        add(x, peak(bell(880, 1.0, rng, t60=1.4, hardness=0.3)), 0.0, 0.6)
    elif take == 5:  # Emotes: a rubber boing
        t = t_(0.5)
        f = 180 * (1 + 0.35 * np.exp(-t * 6) * np.sin(2 * np.pi * 9 * t))
        boing = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(t, 0.004, 0.4)
        add(x, peak(boing), 0.0, 0.8)
    elif take == 6:  # Passes: a ticket stamped, and a little bell
        add(x, peak(strike(0.3, [140, 290, 610], [0.1, 0.05, 0.02], [1.0, 0.5, 0.2], rng, hardness=0.5)), 0.0, 0.9)
        add(x, peak(bell(1318.5, 0.9, rng, t60=0.9, hardness=0.4)), 0.09, 0.25)
    elif take == 7:  # Tokens: coins chinking into a palm
        for k in range(4):
            f = rng.uniform(2200, 3000)
            coin = strike(0.4, [f, f * 1.41, f * 2.03], [0.25, 0.15, 0.08], [1.0, 0.5, 0.25], rng, hardness=0.7)
            add(x, peak(lp(coin, 4200)), k * rng.uniform(0.05, 0.09), 0.5 - 0.08 * k)
    else:  # Backgrounds: a roll of paper unrolling across a table
        t = t_(0.6)
        roll = bp(white(0.6, rng), 250, 1600) * (0.6 + 0.4 * np.sin(2 * np.pi * 14 * t) ** 2) * env(t, 0.05, 0.45)
        add(x, peak(roll), 0.0, 0.7)
        add(x, peak(strike(0.2, [190, 420], [0.06, 0.03], [1.0, 0.3], rng, hardness=0.3)), 0.55, 0.5)
    x = reverb(x, "open", rng, wet=0.18)[:n_(seconds)]
    return finish(x, rng.uniform(-23.0, -21.5), high_cut=4500, fade_out=0.2)


def cookie_crunch(take, rng):
    seconds = 0.8
    x = np.zeros(n_(seconds))
    snap = strike(0.15, [rng.uniform(900, 1300), rng.uniform(1900, 2500)], [0.03, 0.015], [1.0, 0.5], rng, hardness=0.7)
    add(x, peak(snap), 0.0, 0.8)
    add(x, peak(bp(white(0.06, rng), 900, 3400) * env(t_(0.06), 0.0005, 0.02)), 0.0, 0.7)
    when = 0.05
    for _ in range(rng.integers(6, 11)):  # crumbs falling and landing
        crumb = strike(0.05, [rng.uniform(1600, 3000)], [0.012], [1.0], rng, hardness=0.75)
        add(x, peak(crumb), when, rng.uniform(0.08, 0.25))
        when += rng.uniform(0.02, 0.07)
    x = reverb(x, "small", rng, wet=0.15)[:n_(seconds)]
    return finish(x, rng.uniform(-22.0, -20.5), high_cut=3600, fade_out=0.1)


def crate_shake(rng):
    seconds = 1.4
    x = np.zeros(n_(seconds))
    for k in range(7):
        box = strike(0.18, [150, 330, 700], [0.07, 0.035, 0.02], [1.0, 0.45, 0.2], rng, hardness=0.35, detune=0.03)
        add(x, peak(box), k * 0.16 + rng.uniform(0, 0.03), 0.5 + 0.06 * k)
        t = t_(0.12)
        rattle = bp(white(0.12, rng), 600, 2600) * env(t, 0.002, 0.08)
        add(x, peak(rattle), k * 0.16 + 0.02, 0.25)
    x = reverb(x, "small", rng, wet=0.2)[:n_(seconds)]
    return finish(x, -20.0, high_cut=4200, fade_out=0.2)


def crate_reveal(rarity, rng):
    seconds = 2.8
    x = np.zeros(n_(seconds))
    add(x, peak(bubble(300, rng, xi=0.14)), 0.0, 0.6)  # the lid off
    root = 261.63
    if rarity == 0:  # common: the pop, and one soft note
        add(x, peak(wood_bar(root * 2, 1.0, rng, velocity=0.3)), 0.06, 0.4)
    elif rarity == 1:  # rare: a chime
        for k, r in enumerate([2.0, 2.5]):
            add(x, peak(bell(root * r, 1.6, rng, t60=1.6, hardness=0.35)), 0.06 + k * 0.1, 0.35)
    elif rarity == 2:  # epic: notes rising
        for k, r in enumerate([1.0, 1.25, 1.5, 2.0, 2.5]):
            add(x, peak(wood_bar(root * r, 1.2, rng, velocity=0.4)), 0.06 + k * 0.08, 0.35)
    elif rarity == 3:  # legendary: a bell, and a shimmer of notes over it
        add(x, peak(bell(root, 2.6, rng, t60=3.0, hardness=0.4)), 0.06, 0.6)
        for k, r in enumerate([3.0, 4.0, 5.0, 6.0]):
            add(x, peak(wood_bar(root * r, 0.9, rng, velocity=0.25)), 0.2 + k * 0.06, 0.18)
    else:  # mythic: a deep warm chord, with the floor under it
        for k, r in enumerate([0.5, 1.0, 1.5, 2.0, 2.5, 3.0]):
            add(x, peak(felt_piano(root * r, 2.6, rng, velocity=0.45)), 0.06 + k * 0.03, 0.3)
        t = t_(1.6)
        add(x, np.sin(2 * np.pi * 55 * t) * env(t, 0.02, 1.2), 0.06, 0.4)
    x = reverb(x, "hall", rng, wet=0.25)[:n_(seconds)]
    return finish(x, -19.0 + rarity * 0.6, high_cut=4500, fade_out=0.4)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    print(write(OUT / "ShopOpen.wav", shop_open(rng_for("ShopOpen", 10500))))
    print(write(OUT / "ShopClose.wav", shop_close(rng_for("ShopClose", 10500))))
    rng = rng_for("ShopTab", 10500)
    print(write_sheet(OUT / "ShopTab_x9.wav", [tab(k, rng) for k in range(9)], SLOTS["ShopTab"]))
    rng = rng_for("CookieCrunch", 10500)
    print(write_sheet(OUT / "CookieCrunch_x4.wav", [cookie_crunch(k, rng) for k in range(4)], SLOTS["CookieCrunch"]))
    print(write(OUT / "CrateShake.wav", crate_shake(rng_for("CrateShake", 10500))))
    rng = rng_for("CrateReveal", 10500)
    print(write_sheet(OUT / "CrateReveal_x5.wav", [crate_reveal(k, rng) for k in range(5)], SLOTS["CrateReveal"]))
