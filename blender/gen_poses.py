"""The keyed poses: the idles anyone stood still does now and then, and the emotes the shop sells (the hundred-and-fifty-
seventh and fifty-eighth passes).

    python blender/gen_poses.py            writes the KEYED table into src/Shared/Poses.lua (between its markers)
    python blender/gen_poses.py --check    says what it would write, and whether Poses.lua already has it

From your notes of 2026-10-31: "make more variations to the poses the player does by itself when standing afk, improve
the quality of the existing ones and make sure they are very high quality overall, some might be like an aura-farming
emote; and improve the existing emotes that can be bought, and add even more of them".

A pose here is KEYS through time, not a sine or two: each joint has its turns at the moments that matter (where a move
starts, the far point of a swing, a hold) and Poses.play draws a smooth curve through them that eases into and out of
every turn-back, the way a body slows at the end of a reach. Arms are mostly written as WHERE THE HAND AND THE ELBOW GO
(to the chin, on a hip, crossed over the chest, up past the temple), and the joints are solved to put them there on R15's
proportions (pose_keys.py), so a hand on a hip is on the hip and not in it. What is solved is written into Poses.lua as
plain numbers, so the game reads keys and nothing else.

Every pose starts and ends at rest (the emote or the idle eases in and out of it); check_feel.py holds them to a body that
never passes through itself and joints that never whip faster than a body moves.
"""
import math
import pathlib
import random
import sys
import zlib

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import pose_keys  # noqa: E402

POSES_LUA = HERE.parent / "src" / "Shared" / "Poses.lua"
BEGIN = "-- KEYED BEGIN (written by blender/gen_poses.py: edit the poses there, not here)"
END = "-- KEYED END"


# ---------------------------------------------------------------------------------------------------- solving an arm

def _arm_rest(side):
    s = pose_keys.REST[side + "Shoulder"]
    e = pose_keys.REST[side + "Elbow"]
    w = pose_keys.REST[side + "Wrist"]
    h = pose_keys.TIPS[side + "Wrist"][1]
    return s, tuple(e[i] - s[i] for i in range(3)), tuple(w[i] - e[i] for i in range(3)), tuple(h[i] - w[i] for i in range(3))


ARM_REST = {side: _arm_rest(side) for side in ("Right", "Left")}


def arm_points(side, shoulder, elbow, wrist=(0.0, 0.0, 0.0)):
    """The elbow and the hand's tip with the torso at rest: the arm alone, the same sums pose_keys.body does for it."""
    s, to_elbow, to_wrist, to_tip = ARM_REST[side]
    rs = pose_keys.angles(*shoulder)
    re = pose_keys.mat_mul(rs, pose_keys.angles(elbow, 0.0, 0.0))
    rw = pose_keys.mat_mul(re, pose_keys.angles(*wrist))
    a = pose_keys.mat_vec(rs, to_elbow)
    e = (s[0] + a[0], s[1] + a[1], s[2] + a[2])
    b = pose_keys.mat_vec(re, to_wrist)
    w = (e[0] + b[0], e[1] + b[1], e[2] + b[2])
    c = pose_keys.mat_vec(rw, to_tip)
    return e, (w[0] + c[0], w[1] + c[1], w[2] + c[2])


def solve(side, hand, elbow_at=None, start=None, wrist=(0.0, 0.0, 0.0)):
    """Shoulder (x, y, z) and elbow (x) putting `side`'s hand tip at `hand` (and its elbow near `elbow_at`), searched
    from `start`. Elbows bend only forward (0 to 2.6); shoulders stay inside what a shoulder reaches."""
    # Seeded from the target itself (not hash(), which Python salts per run), so the same poses come out the same.
    rng = random.Random(zlib.crc32(repr((side, hand, elbow_at, start is None)).encode("utf-8")))

    def cost(v):
        sx, sy, sz, ex = v
        if not (0 <= ex <= 2.6) or abs(sx) > 3.2 or abs(sy) > 2.0 or abs(sz) > 3.1:
            return 1e9
        e, h = arm_points(side, (sx, sy, sz), ex, wrist)
        c = sum((h[i] - hand[i]) ** 2 for i in range(3))
        if elbow_at:
            c += 0.5 * sum((e[i] - elbow_at[i]) ** 2 for i in range(3))
        # STAY ON THE SAME ARM: near where the last key left it, so two keys are never two different ways of reaching
        # (an arm that flips from one to the other between keys whips round to do it).
        if start:
            c += 0.03 * sum((v[i] - start[i]) ** 2 for i in range(4))
        return c + 0.002 * (sx * sx + sy * sy + sz * sz)

    best = list(start) if start else [0.5, 0.0, 0.3 if side == "Right" else -0.3, 1.0]
    best_cost = cost(best)
    tries = [best] + [[rng.uniform(-1.5, 2.8), rng.uniform(-1.2, 1.2), rng.uniform(-2.5, 2.8) * (1 if side == "Right" else -1),
                       rng.uniform(0, 2.4)] for _ in range(4 if start else 10)]
    for seed in tries:
        v, c, step = list(seed), cost(seed), 0.4
        while step > 1e-4:
            moved = False
            for i in range(4):
                for d in (step, -step):
                    trial = list(v)
                    trial[i] += d
                    tc = cost(trial)
                    if tc < c:
                        v, c, moved = trial, tc, True
            if not moved:
                step *= 0.5
        if c < best_cost:
            best, best_cost = v, c
    return best, math.sqrt(max(0.0, best_cost))


# ---------------------------------------------------------------------------------------------------- the poses
#
# Each pose: seconds, an optional loop (from, to: the part played over and over while it lasts), and its keys. A joint's
# keys are (t, x, y, z) or, for the Root, (t, x, y, z, px, py, pz). An ARM's keys are ("arm", t, hand, elbow, wrist):
# where its hand tip and elbow go (in the body's own frame at rest: X its right, Y up, Z behind; it faces -Z), solved
# into its shoulder, elbow and wrist. "rest" is an arm at its side.

REST = "rest"


def P(seconds, keys, loop=None):
    return {"seconds": seconds, "loop": loop, "keys": keys}


def mirror(hand):
    return (-hand[0], hand[1], hand[2])


POSES = {}

# ===== STANDING ABOUT: the idles (PlayerLife picks one now and then, for anyone stood still) =====

# LOOKING ROUND: the eyes lead and the head follows them, the shoulders a beat after; a held look one way, a sweep
# through the middle with a small dip of the chin, a held look the other, and back.
POSES["idleLook"] = P(4.8, {
    "Neck": [(0, 0, 0, 0), (0.55, 0.05, 0.7, -0.03), (1.55, 0.07, 0.76, -0.04), (2.15, -0.05, 0.02, 0),
             (2.65, 0.04, -0.68, 0.04), (3.7, 0.06, -0.72, 0.05), (4.5, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.8, 0, 0.2, 0), (1.7, 0, 0.22, 0), (2.35, 0, 0, 0), (2.9, 0, -0.18, 0), (3.9, 0, -0.2, 0),
              (4.7, 0, 0, 0)],
    "RightShoulder": [(0, 0, 0, 0), (0.9, 0.06, 0, 0.03), (2.3, 0, 0, 0), (3.0, -0.05, 0, 0.02), (4.7, 0, 0, 0)],
    "LeftShoulder": [(0, 0, 0, 0), (0.9, -0.05, 0, -0.02), (2.3, 0, 0, 0), (3.0, 0.06, 0, -0.03), (4.7, 0, 0, 0)],
})

# A SHIFT OF WEIGHT: onto the left leg, the right knee unlocking and its heel lifting, the hips dropping on that side and
# the shoulders tilting against them to keep the head over the feet; the shoulders roll back once; settled, and back.
POSES["idleShift"] = P(4.2, {
    "Root": [(0, 0, 0, 0), (0.7, 0, 0.05, 0.05), (3.4, 0, 0.05, 0.05), (4.2, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.8, 0, -0.03, -0.07), (3.3, 0, -0.03, -0.07), (4.2, 0, 0, 0)],
    "RightHip": [(0, 0, 0, 0), (0.7, 0.13, -0.1, 0.02), (3.4, 0.13, -0.1, 0.02), (4.2, 0, 0, 0)],
    "RightKnee": [(0, 0, 0, 0), (0.7, -0.28, 0, 0), (3.4, -0.28, 0, 0), (4.2, 0, 0, 0)],
    "RightAnkle": [(0, 0, 0, 0), (0.7, 0.14, 0, 0), (3.4, 0.14, 0, 0), (4.2, 0, 0, 0)],
    "LeftHip": [(0, 0, 0, 0), (0.7, 0, 0, -0.04), (3.4, 0, 0, -0.04), (4.2, 0, 0, 0)],
    "RightShoulder": [(0, 0, 0, 0), (1.3, 0, 0, 0.04), (1.8, -0.24, 0, 0.1), (2.3, 0.06, 0, 0.04), (2.8, 0, 0, 0.03), (4.2, 0, 0, 0)],
    "LeftShoulder": [(0, 0, 0, 0), (1.3, 0, 0, -0.04), (1.8, -0.24, 0, -0.1), (2.3, 0.06, 0, -0.04), (2.8, 0, 0, -0.03), (4.2, 0, 0, 0)],
    "Neck": [(0, 0, 0, 0), (0.9, -0.04, 0.08, 0.1), (3.2, -0.04, 0.08, 0.1), (4.2, 0, 0, 0)],
})

# THINKING IT OVER: a hand comes up to the chin, the other arm folds under its elbow, the head tilts one way and the other
# while a finger taps the chin, and the hands come down.
POSES["idlePonder"] = P(4.6, {
    "RightArm": [("arm", 0, REST), ("arm", 0.65, (0.1, 1.52, -0.8), (0.55, 0.62, -0.72), (0.2, 0, 0)),
                 ("arm", 3.9, (0.1, 1.52, -0.8), (0.55, 0.62, -0.72), (0.2, 0, 0)), ("arm", 4.6, REST)],
    "RightWrist": [(0, 0, 0, 0), (0.7, 0.2, 0, 0), (1.15, 0.42, 0, 0), (1.45, 0.16, 0, 0), (1.75, 0.42, 0, 0), (2.05, 0.16, 0, 0),
                   (2.4, 0.36, 0, 0), (3.9, 0.2, 0, 0), (4.6, 0, 0, 0)],
    "LeftArm": [("arm", 0, REST), ("arm", 0.75, (0.4, 0.62, -0.92), (-0.85, 0.66, -0.66)),
                ("arm", 3.8, (0.4, 0.62, -0.92), (-0.85, 0.66, -0.66)), ("arm", 4.6, REST)],
    "Neck": [(0, 0, 0, 0), (0.8, -0.12, 0.1, 0.12), (2.0, -0.08, 0.24, -0.06), (3.3, -0.12, 0.05, 0.14), (4.4, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.8, -0.08, 0.05, 0), (3.7, -0.08, 0.05, 0), (4.5, 0, 0, 0)],
})

# A BIG STRETCH AND A YAWN: both arms up overhead from the sides, the back arching and the head going back with the yawn,
# a lean to one side and the other with the arms up, the arms coming down wide, and a roll of the shoulders.
POSES["idleYawn"] = P(4.6, {
    "RightShoulder": [(0, 0, 0, 0), (0.95, 0.2, 0, 2.75), (1.7, 0.2, 0, 2.86), (2.7, 0.2, 0, 2.8), (3.5, 0, 0, 0.4), (4.0, -0.2, 0, 0.1),
                      (4.6, 0, 0, 0)],
    "LeftShoulder": [(0, 0, 0, 0), (0.95, 0.2, 0, -2.75), (1.7, 0.2, 0, -2.86), (2.7, 0.2, 0, -2.8), (3.5, 0, 0, -0.4),
                     (4.0, -0.2, 0, -0.1), (4.6, 0, 0, 0)],
    "RightElbow": [(0, 0, 0, 0), (0.95, 0.4, 0, 0), (2.7, 0.3, 0, 0), (3.5, 0.15, 0, 0), (4.6, 0, 0, 0)],
    "LeftElbow": [(0, 0, 0, 0), (0.95, 0.4, 0, 0), (2.7, 0.3, 0, 0), (3.5, 0.15, 0, 0), (4.6, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (1.0, 0.14, 0, 0), (1.8, 0.1, 0, 0.15), (2.55, 0.1, 0, -0.13), (3.3, 0, 0, 0), (4.6, 0, 0, 0)],
    "Neck": [(0, 0, 0, 0), (1.0, 0.34, 0, 0), (1.8, 0.26, 0, 0.08), (2.55, 0.26, 0, -0.08), (3.3, -0.06, 0, 0), (4.6, 0, 0, 0)],
})

# LOOKING AT A HAND: the right hand comes up in front, turned to look at the back of it, then the palm; a flick of the
# fingers, and down.
POSES["idleHand"] = P(3.8, {
    "RightArm": [("arm", 0, REST), ("arm", 0.6, (0.5, 1.3, -1.2), (0.95, 0.62, -0.72), (0.1, 0.9, 0)),
                 ("arm", 1.6, (0.5, 1.3, -1.2), (0.95, 0.62, -0.72), (0.1, 0.9, 0)),
                 ("arm", 2.0, (0.48, 1.35, -1.18), (0.95, 0.62, -0.72), (-0.3, 0.2, 0)), ("arm", 2.15, (0.48, 1.42, -1.16), (0.95, 0.62, -0.72), (0.4, 0.2, 0)),
                 ("arm", 2.35, (0.48, 1.35, -1.18), (0.95, 0.62, -0.72), (-0.1, 0.2, 0)), ("arm", 2.8, (0.5, 1.25, -1.18), (0.95, 0.62, -0.72)),
                 ("arm", 3.8, REST)],
    "Neck": [(0, 0, 0, 0), (0.7, -0.28, -0.14, 0.06), (2.6, -0.25, -0.1, 0.04), (3.5, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.7, -0.04, -0.06, 0), (2.7, -0.04, -0.06, 0), (3.6, 0, 0, 0)],
})

# WAITING: hands on hips and the right foot tapping, the head tilted, a sigh of the shoulders halfway.
POSES["idleTap"] = P(4.4, {
    "RightArm": [("arm", 0, REST), ("arm", 0.55, (1.02, -0.28, -0.2), (1.85, 0.48, 0.28)), ("arm", 3.8, (1.02, -0.28, -0.2), (1.85, 0.48, 0.28)),
                 ("arm", 4.4, REST)],
    "LeftArm": [("arm", 0, REST), ("arm", 0.6, mirror((1.02, -0.28, -0.2)), mirror((1.85, 0.48, 0.28))),
                ("arm", 3.8, mirror((1.02, -0.28, -0.2)), mirror((1.85, 0.48, 0.28))), ("arm", 4.4, REST)],
    "RightAnkle": [(0, 0, 0, 0), (0.8, 0, 0, 0), (1.0, 0.32, 0, 0), (1.2, 0, 0, 0), (1.45, 0.32, 0, 0), (1.65, 0, 0, 0), (1.9, 0.32, 0, 0),
                   (2.1, 0, 0, 0), (2.9, 0, 0, 0), (3.1, 0.3, 0, 0), (3.3, 0, 0, 0), (3.55, 0.3, 0, 0), (3.75, 0, 0, 0), (4.4, 0, 0, 0)],
    "RightKnee": [(0, 0, 0, 0), (0.7, -0.12, 0, 0), (3.9, -0.12, 0, 0), (4.4, 0, 0, 0)],
    "Neck": [(0, 0, 0, 0), (0.7, 0.02, 0.1, 0.12), (2.3, 0.08, 0.06, 0.1), (2.55, -0.04, 0.06, 0.1), (3.9, 0.02, 0.1, 0.12), (4.4, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.7, 0.04, 0, 0.03), (2.3, 0.08, 0, 0.03), (2.6, 0.02, 0, 0.03), (3.9, 0.04, 0, 0.03), (4.4, 0, 0, 0)],
})

# AURA, ARMS CROSSED: the arms fold across the chest, the chin comes up, the weight goes onto one hip, and the head turns
# slowly away to look at something far off, as if it is all beneath you; a small nod to nobody, and back.
POSES["idleAuraCrossed"] = P(6.4, {
    "RightArm": [("arm", 0, REST), ("arm", 0.7, (-0.25, 0.7, -0.86), (1.05, 0.64, -0.74)), ("arm", 5.7, (-0.25, 0.7, -0.86), (1.05, 0.64, -0.74)),
                 ("arm", 6.4, REST)],
    "LeftArm": [("arm", 0, REST), ("arm", 0.8, (0.3, 0.84, -0.98), (-1.05, 0.76, -0.88)), ("arm", 5.6, (0.3, 0.84, -0.98), (-1.05, 0.76, -0.88)),
                ("arm", 6.4, REST)],
    "Neck": [(0, 0, 0, 0), (0.9, 0.14, 0, 0), (1.8, 0.16, -0.5, -0.04), (3.9, 0.16, -0.55, -0.05), (4.4, 0.06, -0.5, -0.04),
             (4.75, 0.18, -0.45, -0.04), (5.6, 0.12, 0, 0), (6.3, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (1.0, 0.07, -0.12, -0.05), (5.4, 0.07, -0.14, -0.05), (6.3, 0, 0, 0)],
    "Root": [(0, 0, 0, 0), (1.0, 0, 0.06, 0.05), (5.4, 0, 0.06, 0.05), (6.3, 0, 0, 0)],
    "RightHip": [(0, 0, 0, 0), (1.0, 0.1, -0.12, 0.03), (5.4, 0.1, -0.12, 0.03), (6.3, 0, 0, 0)],
    "RightKnee": [(0, 0, 0, 0), (1.0, -0.22, 0, 0), (5.4, -0.22, 0, 0), (6.3, 0, 0, 0)],
    "RightAnkle": [(0, 0, 0, 0), (1.0, 0.1, 0, 0), (5.4, 0.1, 0, 0), (6.3, 0, 0, 0)],
})

# AURA, IN THE BREEZE: the chin up to the horizon, a long look out at it, a hand sweeping back through the hair past the
# temple as if the wind had it, the look held, and down.
POSES["idleAuraBreeze"] = P(5.8, {
    "Neck": [(0, 0, 0, 0), (0.8, 0.16, 0.32, 0.02), (2.0, 0.2, 0.36, -0.06), (3.0, 0.2, 0.4, -0.08), (4.8, 0.16, 0.34, 0), (5.7, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.9, 0.05, 0.12, 0), (4.9, 0.05, 0.14, 0), (5.7, 0, 0, 0)],
    "RightArm": [("arm", 0, REST), ("arm", 1.2, REST), ("arm", 1.75, (0.8, 2.25, -0.45), (1.6, 1.68, -0.45)),
                 ("arm", 2.25, (0.82, 2.62, 0.05), (1.62, 2.0, 0.0)), ("arm", 2.7, (0.72, 2.35, 0.62), (1.55, 1.8, 0.35)),
                 ("arm", 3.4, REST)],
    "RightWrist": [(0, 0, 0, 0), (1.75, 0.3, 0, 0), (2.25, -0.2, 0, 0), (2.7, -0.3, 0, 0), (3.4, 0, 0, 0)],
    "LeftShoulder": [(0, 0, 0, 0), (1.0, -0.04, 0, -0.06), (5.0, -0.04, 0, -0.06), (5.8, 0, 0, 0)],
    "Root": [(0, 0, 0, 0), (1.0, 0, 0, -0.03), (5.0, 0, 0, -0.03), (5.8, 0, 0, 0)],
    "LeftKnee": [(0, 0, 0, 0), (1.0, -0.14, 0, 0), (5.0, -0.14, 0, 0), (5.8, 0, 0, 0)],
})

# AURA, HANDS IN POCKETS: hands down into the front pockets, leaning back a little on one leg, the head tilted and a slow
# nod, the shoulders loose.
POSES["idleAuraPockets"] = P(5.4, {
    "RightArm": [("arm", 0, REST), ("arm", 0.7, (0.72, -0.52, -0.6), (1.3, 0.55, 0.1)), ("arm", 4.7, (0.72, -0.52, -0.6), (1.3, 0.55, 0.1)),
                 ("arm", 5.4, REST)],
    "LeftArm": [("arm", 0, REST), ("arm", 0.75, mirror((0.72, -0.52, -0.6)), mirror((1.3, 0.55, 0.1))),
                ("arm", 4.7, mirror((0.72, -0.52, -0.6)), mirror((1.3, 0.55, 0.1))), ("arm", 5.4, REST)],
    "Waist": [(0, 0, 0, 0), (0.9, 0.08, 0.06, 0.04), (4.6, 0.08, 0.06, 0.04), (5.3, 0, 0, 0)],
    "Neck": [(0, 0, 0, 0), (1.0, 0.04, -0.12, 0.12), (2.2, 0.08, -0.14, 0.13), (2.55, -0.06, -0.14, 0.13), (2.9, 0.06, -0.14, 0.12),
             (4.6, 0.04, -0.12, 0.12), (5.3, 0, 0, 0)],
    "Root": [(0, 0, 0, 0), (0.9, 0, 0.04, -0.04), (4.6, 0, 0.04, -0.04), (5.3, 0, 0, 0)],
    "LeftHip": [(0, 0, 0, 0), (0.9, 0.12, 0.1, -0.02), (4.6, 0.12, 0.1, -0.02), (5.3, 0, 0, 0)],
    "LeftKnee": [(0, 0, 0, 0), (0.9, -0.24, 0, 0), (4.6, -0.24, 0, 0), (5.3, 0, 0, 0)],
    "LeftAnkle": [(0, 0, 0, 0), (0.9, 0.11, 0, 0), (4.6, 0.11, 0, 0), (5.3, 0, 0, 0)],
})

# AURA, DUSTED OFF: the right hand brushes something off the chest and the collar, twice, unhurried, the chin up and the
# eyes away, and a last look back. (Not the other shoulder: R15's arms do not reach across that far.)
POSES["idleAuraBrush"] = P(3.9, {
    "RightArm": [("arm", 0, REST), ("arm", 0.55, (-0.3, 1.32, -0.7), (0.75, 0.75, -0.85), (0.2, 0, 0)),
                 ("arm", 0.85, (0.55, 1.12, -0.95), (0.9, 0.62, -0.75), (-0.3, 0, 0)),
                 ("arm", 1.15, (-0.3, 1.32, -0.7), (0.75, 0.75, -0.85), (0.2, 0, 0)),
                 ("arm", 1.45, (0.55, 1.12, -0.95), (0.9, 0.62, -0.75), (-0.3, 0, 0)), ("arm", 2.2, REST)],
    "Neck": [(0, 0, 0, 0), (0.5, -0.1, 0.22, 0.06), (1.5, -0.1, 0.24, 0.06), (2.0, 0.16, -0.28, -0.04), (3.2, 0.16, -0.3, -0.04),
             (3.8, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.6, 0, 0.1, 0), (1.6, 0, 0.1, 0), (2.1, 0.05, -0.08, 0), (3.2, 0.05, -0.08, 0), (3.9, 0, 0, 0)],
    "LeftShoulder": [(0, 0, 0, 0), (0.5, 0, 0, -0.08), (1.6, 0, 0, -0.08), (2.2, 0, 0, 0), (3.9, 0, 0, 0)],
})

# ===== THE EMOTES (the shop's: EmoteService plays them on every client) =====

# WAVE: a little dip of anticipation, the arm up and out, the forearm waving from the elbow, the head tilting to whoever
# it is for and the body leaning away from the arm a touch; down with a last small wave.
_wave_hi = ((1.12, 2.8, -0.35), (2.15, 2.55, -0.35))
POSES["emoteWave"] = P(2.9, {
    "RightArm": [("arm", 0, REST), ("arm", 0.22, (1.6, -0.5, -0.25), (1.55, 0.6, 0.0)), ("arm", 0.6, _wave_hi[0], (1.62, 1.95, -0.25)),
                 ("arm", 0.85, _wave_hi[1], (1.62, 1.95, -0.25)), ("arm", 1.1, _wave_hi[0], (1.62, 1.95, -0.25)),
                 ("arm", 1.35, _wave_hi[1], (1.62, 1.95, -0.25)), ("arm", 1.6, _wave_hi[0], (1.62, 1.95, -0.25)),
                 ("arm", 1.85, _wave_hi[1], (1.62, 1.95, -0.25)), ("arm", 2.1, (1.45, 2.72, -0.35), (1.62, 1.95, -0.25)),
                 ("arm", 2.9, REST)],
    "Neck": [(0, 0, 0, 0), (0.6, 0.06, 0.16, 0.12), (2.1, 0.06, 0.16, 0.12), (2.8, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.6, 0.03, 0.05, -0.06), (2.1, 0.03, 0.05, -0.06), (2.8, 0, 0, 0)],
    "LeftShoulder": [(0, 0, 0, 0), (0.6, 0, 0, -0.08), (2.1, 0, 0, -0.08), (2.8, 0, 0, 0)],
})

# STRETCH: up onto the toes with both arms overhead, reaching, then a long lean to one side and the other with the arms
# still up, the back arching; down off the toes, the arms coming down wide, and a roll of the neck.
POSES["emoteStretch"] = P(4.0, {
    "RightShoulder": [(0, 0, 0, 0), (0.8, 0.15, 0, 2.9), (2.7, 0.15, 0, 2.9), (3.3, 0, 0, 0.5), (4.0, 0, 0, 0)],
    "LeftShoulder": [(0, 0, 0, 0), (0.8, 0.15, 0, -2.9), (2.7, 0.15, 0, -2.9), (3.3, 0, 0, -0.5), (4.0, 0, 0, 0)],
    "RightElbow": [(0, 0, 0, 0), (0.8, 0.2, 0, 0), (2.7, 0.2, 0, 0), (3.3, 0.1, 0, 0), (4.0, 0, 0, 0)],
    "LeftElbow": [(0, 0, 0, 0), (0.8, 0.2, 0, 0), (2.7, 0.2, 0, 0), (3.3, 0.1, 0, 0), (4.0, 0, 0, 0)],
    "Root": [(0, 0, 0, 0, 0, 0, 0), (0.8, 0, 0, 0, 0, 0.22, 0), (1.4, 0, 0, 0, 0, 0.22, 0), (1.8, 0, 0, 0, 0, 0, 0), (4.0, 0, 0, 0, 0, 0, 0)],
    "RightAnkle": [(0, 0, 0, 0), (0.8, -0.34, 0, 0), (1.4, -0.34, 0, 0), (1.8, 0, 0, 0), (4.0, 0, 0, 0)],
    "LeftAnkle": [(0, 0, 0, 0), (0.8, -0.34, 0, 0), (1.4, -0.34, 0, 0), (1.8, 0, 0, 0), (4.0, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.8, 0.14, 0, 0), (1.5, 0.1, 0, 0), (2.0, 0.08, 0, 0.24), (2.6, 0.08, 0, -0.22), (3.2, 0, 0, 0), (4.0, 0, 0, 0)],
    "Neck": [(0, 0, 0, 0), (0.8, 0.3, 0, 0), (2.0, 0.2, 0, 0.1), (2.6, 0.2, 0, -0.1), (3.3, -0.1, 0.2, 0.12), (3.7, -0.1, -0.2, -0.12),
             (4.0, 0, 0, 0)],
})

# SPIN: a crouch to wind up, round once on the spot with a little hop and the arms flung wide, and a ta-da at the end.
POSES["emoteSpin"] = P(2.1, {
    "Root": [(0, 0, 0, 0, 0, 0, 0), (0.22, 0, -0.35, 0, 0, -0.18, 0), (0.75, 0, 3.0, 0, 0, 0.35, 0), (1.25, 0, 6.2832, 0, 0, 0, 0),
             (2.1, 0, 6.2832, 0, 0, 0, 0)],
    "RightKnee": [(0, 0, 0, 0), (0.22, -0.45, 0, 0), (0.6, -0.1, 0, 0), (1.25, -0.3, 0, 0), (1.5, 0, 0, 0), (2.1, 0, 0, 0)],
    "LeftKnee": [(0, 0, 0, 0), (0.22, -0.45, 0, 0), (0.6, -0.1, 0, 0), (1.25, -0.3, 0, 0), (1.5, 0, 0, 0), (2.1, 0, 0, 0)],
    "RightHip": [(0, 0, 0, 0), (0.22, 0.22, 0, 0), (0.6, 0.05, 0, 0), (1.25, 0.15, 0, 0), (1.5, 0, 0, 0), (2.1, 0, 0, 0)],
    "LeftHip": [(0, 0, 0, 0), (0.22, 0.22, 0, 0), (0.6, 0.05, 0, 0), (1.25, 0.15, 0, 0), (1.5, 0, 0, 0), (2.1, 0, 0, 0)],
    "RightShoulder": [(0, 0, 0, 0), (0.22, 0.2, 0, 0.2), (0.55, 0, 0, 1.5), (1.15, 0, 0, 1.45), (1.5, 0.1, 0, 2.3), (1.85, 0.1, 0, 2.3),
                      (2.1, 0, 0, 0)],
    "LeftShoulder": [(0, 0, 0, 0), (0.22, 0.2, 0, -0.2), (0.55, 0, 0, -1.5), (1.15, 0, 0, -1.45), (1.5, 0.1, 0, -2.3),
                     (1.85, 0.1, 0, -2.3), (2.1, 0, 0, 0)],
    "Neck": [(0, 0, 0, 0), (0.22, -0.12, 0, 0), (0.75, 0.1, 0, 0), (1.5, 0.16, 0, 0), (2.1, 0, 0, 0)],
})

# SIT AND SQUISH: down to the floor cross-legged, a squeeze toy held in both hands in front, squeezed on a slow beat, the
# head down to watch it and swaying a little, the body rocking with the squeezes. (EmoteService puts the toy in the hands.)
_sq_open = ((0.2, -0.02, -1.02), (0.9, 0.22, -0.52))
_sq_shut = ((0.12, 0.0, -0.98), (0.86, 0.18, -0.52))
# (A LOOP plays its keys from its first moment to its last over and over while the pose lasts, and the keys after it are
# the way out, played once at the end: `seconds` is the loop's end, whole loops, and the way out, so the loop is always
# at its own start when the way out begins and nothing jumps. check_feel.py holds that.)
# DOWN AS A BODY GOES DOWN: a squat first (the knees bent, the feet flat, the hips not yet low), then the hips to the floor
# and the legs crossed; up the same way back. Lowered and folded together, the shins swept through the floor on the way.
POSES["emoteSitSquish"] = P(20, {
    "Root": [(0, 0, 0, 0, 0, 0, 0), (0.4, 0, 0, 0, 0, -0.75, 0), (0.8, 0, 0, 0, 0, -1.85, 0), (2.0, 0, 0, 0, 0, -1.85, 0),
             (2.4, 0, 0, 0, 0, -0.75, 0), (3.0, 0, 0, 0, 0, 0, 0)],
    "RightHip": [(0, 0, 0, 0), (0.4, 0.95, 0, 0.3), (0.8, 1.5, 0, 0.72), (2.0, 1.5, 0, 0.72), (2.4, 0.95, 0, 0.3), (3.0, 0, 0, 0)],
    "LeftHip": [(0, 0, 0, 0), (0.4, 0.95, 0, -0.3), (0.8, 1.5, 0, -0.72), (2.0, 1.5, 0, -0.72), (2.4, 0.95, 0, -0.3), (3.0, 0, 0, 0)],
    "RightKnee": [(0, 0, 0, 0), (0.4, -1.9, 0, 0), (0.8, -2.65, 0, 0), (2.0, -2.65, 0, 0), (2.4, -1.9, 0, 0), (3.0, 0, 0, 0)],
    "RightAnkle": [(0, 0, 0, 0), (0.4, 0.3, 0, 0), (0.8, -1.0, 0, 0), (2.0, -1.0, 0, 0), (2.4, 0.3, 0, 0), (3.0, 0, 0, 0)],
    "LeftKnee": [(0, 0, 0, 0), (0.4, -1.9, 0, 0), (0.8, -2.65, 0, 0), (2.0, -2.65, 0, 0), (2.4, -1.9, 0, 0), (3.0, 0, 0, 0)],
    "LeftAnkle": [(0, 0, 0, 0), (0.4, 0.3, 0, 0), (0.8, -1.0, 0, 0), (2.0, -1.0, 0, 0), (2.4, 0.3, 0, 0), (3.0, 0, 0, 0)],
    "RightArm": [("arm", 0, REST), ("arm", 1.0, _sq_open[0], _sq_open[1]), ("arm", 1.5, _sq_shut[0], _sq_shut[1]),
                 ("arm", 2.0, _sq_open[0], _sq_open[1]), ("arm", 3.0, REST)],
    "LeftArm": [("arm", 0, REST), ("arm", 1.0, mirror(_sq_open[0]), mirror(_sq_open[1])), ("arm", 1.5, mirror(_sq_shut[0]), mirror(_sq_shut[1])),
                ("arm", 2.0, mirror(_sq_open[0]), mirror(_sq_open[1])), ("arm", 3.0, REST)],
    "Waist": [(0, 0, 0, 0), (1.0, -0.12, 0, 0), (1.5, -0.18, 0, 0.03), (2.0, -0.12, 0, 0), (3.0, 0, 0, 0)],
    "Neck": [(0, 0, 0, 0), (1.0, -0.32, 0.06, 0.06), (1.5, -0.36, -0.04, -0.04), (2.0, -0.32, 0.06, 0.06), (3.0, 0, 0, 0)],
}, loop=(1.0, 2.0))

# AURA (the dance): one hand on the hip, the other arm out low to the side rolling in slow waves from the shoulder to the
# fingers, the body swaying with it from the knees, the chin up and the eyes half away: calm, unbothered, entirely sure of
# itself. A beat of three seconds, over and over while it lasts.
_au_out = ((2.55, 1.0, -0.55), (1.85, 1.15, -0.25))
_au_up = ((2.5, 1.6, -0.75), (1.8, 1.4, -0.35))
_au_in = ((1.7, 1.25, -1.5), (1.55, 1.15, -0.65))
POSES["emoteAura"] = P(10.8, {
    "LeftArm": [("arm", 0, REST), ("arm", 0.7, mirror((1.02, -0.28, -0.2)), mirror((1.85, 0.48, 0.28))),
                ("arm", 3.9, mirror((1.02, -0.28, -0.2)), mirror((1.85, 0.48, 0.28))), ("arm", 4.8, REST)],
    "RightArm": [("arm", 0, REST), ("arm", 0.9, _au_out[0], _au_out[1], (0.2, 0, 0)), ("arm", 1.65, _au_up[0], _au_up[1], (-0.35, 0, 0)),
                 ("arm", 2.4, _au_in[0], _au_in[1], (0.3, 0, 0)), ("arm", 3.15, _au_up[0], _au_up[1], (-0.35, 0, 0)),
                 ("arm", 3.9, _au_out[0], _au_out[1], (0.2, 0, 0)), ("arm", 4.8, REST)],
    "Root": [(0, 0, 0, 0), (0.9, 0, 0, 0.04), (2.4, 0, 0.05, -0.04), (3.9, 0, 0, 0.04), (4.8, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.9, 0.05, -0.05, -0.05), (2.4, 0.05, 0.1, 0.05), (3.9, 0.05, -0.05, -0.05), (4.8, 0, 0, 0)],
    "RightKnee": [(0, 0, 0, 0), (0.9, -0.08, 0, 0), (1.65, -0.26, 0, 0), (2.4, -0.08, 0, 0), (3.15, -0.26, 0, 0), (3.9, -0.08, 0, 0),
                  (4.8, 0, 0, 0)],
    "LeftKnee": [(0, 0, 0, 0), (0.9, -0.2, 0, 0), (1.65, -0.06, 0, 0), (2.4, -0.2, 0, 0), (3.15, -0.06, 0, 0), (3.9, -0.2, 0, 0),
                 (4.8, 0, 0, 0)],
    "Neck": [(0, 0, 0, 0), (0.9, 0.16, -0.25, -0.06), (2.4, 0.12, 0.1, 0.06), (3.9, 0.16, -0.25, -0.06), (4.8, 0, 0, 0)],
}, loop=(0.9, 3.9))

# CHEER: both arms thrown up, pumping, a bounce in the knees with each, the head back with a grin.
_ch_hi = ((0.88, 3.3, -0.35), (1.45, 2.3, -0.2))
_ch_lo = ((1.15, 2.75, -0.5), (1.65, 1.88, -0.3))
POSES["emoteCheer"] = P(2.8, {
    "RightArm": [("arm", 0, REST), ("arm", 0.35, _ch_hi[0], _ch_hi[1]), ("arm", 0.65, _ch_lo[0], _ch_lo[1]), ("arm", 0.95, _ch_hi[0], _ch_hi[1]),
                 ("arm", 1.25, _ch_lo[0], _ch_lo[1]), ("arm", 1.55, _ch_hi[0], _ch_hi[1]), ("arm", 2.1, _ch_hi[0], _ch_hi[1]), ("arm", 2.8, REST)],
    "LeftArm": [("arm", 0, REST), ("arm", 0.35, mirror(_ch_hi[0]), mirror(_ch_hi[1])), ("arm", 0.65, mirror(_ch_lo[0]), mirror(_ch_lo[1])),
                ("arm", 0.95, mirror(_ch_hi[0]), mirror(_ch_hi[1])), ("arm", 1.25, mirror(_ch_lo[0]), mirror(_ch_lo[1])),
                ("arm", 1.55, mirror(_ch_hi[0]), mirror(_ch_hi[1])), ("arm", 2.1, mirror(_ch_hi[0]), mirror(_ch_hi[1])), ("arm", 2.8, REST)],
    "RightKnee": [(0, 0, 0, 0), (0.35, -0.05, 0, 0), (0.65, -0.3, 0, 0), (0.95, -0.05, 0, 0), (1.25, -0.3, 0, 0), (1.55, -0.05, 0, 0), (2.8, 0, 0, 0)],
    "LeftKnee": [(0, 0, 0, 0), (0.35, -0.05, 0, 0), (0.65, -0.3, 0, 0), (0.95, -0.05, 0, 0), (1.25, -0.3, 0, 0), (1.55, -0.05, 0, 0), (2.8, 0, 0, 0)],
    "Root": [(0, 0, 0, 0, 0, 0, 0), (0.35, 0, 0, 0, 0, 0.05, 0), (0.65, 0, 0, 0, 0, -0.14, 0), (0.95, 0, 0, 0, 0, 0.05, 0),
             (1.25, 0, 0, 0, 0, -0.14, 0), (1.55, 0, 0, 0, 0, 0.05, 0), (2.8, 0, 0, 0, 0, 0, 0)],
    "RightHip": [(0, 0, 0, 0), (0.65, 0.16, 0, 0), (0.95, 0.03, 0, 0), (1.25, 0.16, 0, 0), (1.55, 0.03, 0, 0), (2.8, 0, 0, 0)],
    "LeftHip": [(0, 0, 0, 0), (0.65, 0.16, 0, 0), (0.95, 0.03, 0, 0), (1.25, 0.16, 0, 0), (1.55, 0.03, 0, 0), (2.8, 0, 0, 0)],
    "Neck": [(0, 0, 0, 0), (0.35, 0.3, 0, 0), (1.55, 0.3, 0, 0), (2.1, 0.22, 0, 0.08), (2.8, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.35, 0.1, 0, 0), (2.1, 0.1, 0, 0), (2.8, 0, 0, 0)],
})

# BOW: a hand to the chest, the other behind the back, a slow bow from the waist with the head following, held a breath,
# and up.
POSES["emoteBow"] = P(2.8, {
    "RightArm": [("arm", 0, REST), ("arm", 0.5, (0.15, 1.05, -0.68), (0.9, 0.62, -0.66)), ("arm", 2.2, (0.15, 1.05, -0.68), (0.9, 0.62, -0.66)),
                 ("arm", 2.8, REST)],
    "LeftArm": [("arm", 0, REST), ("arm", 0.5, (0.0, 0.25, 0.8), (-1.25, 0.6, 0.45)), ("arm", 2.2, (0.0, 0.25, 0.8), (-1.25, 0.6, 0.45)),
                ("arm", 2.8, REST)],
    "Waist": [(0, 0, 0, 0), (0.55, 0, 0, 0), (1.1, -0.62, 0, 0), (1.6, -0.6, 0, 0), (2.15, 0, 0, 0), (2.8, 0, 0, 0)],
    "Neck": [(0, 0, 0, 0), (0.6, 0, 0, 0), (1.15, -0.28, 0, 0), (1.6, -0.25, 0, 0), (2.15, 0.04, 0, 0), (2.8, 0, 0, 0)],
    "RightHip": [(0, 0, 0, 0), (1.1, 0.12, 0, 0), (1.6, 0.12, 0, 0), (2.15, 0, 0, 0)],
    "LeftHip": [(0, 0, 0, 0), (1.1, 0.12, 0, 0), (1.6, 0.12, 0, 0), (2.15, 0, 0, 0)],
})

# ROYAL WAVE (the VIP's own, the two-hundred-and-thirteenth pass): the slow wave of someone the crowd came to see. The
# left hand goes to the small of the back (as in the bow), the right forearm comes up to the shoulder's height and the
# hand turns at the wrist, cupped, side to side and unhurried; the chin lifts, the chest opens, and the head turns slowly
# across the crowd and back. Held a moment at the end, then down.
_royal_hand, _royal_elbow = (1.05, 2.0, -0.62), (1.45, 0.85, -0.3)
POSES["emoteRoyalWave"] = P(3.8, {
    "RightArm": [("arm", 0, REST), ("arm", 0.55, _royal_hand, _royal_elbow),
                 ("arm", 0.95, _royal_hand, _royal_elbow, (0.0, 0.55, 0.0)), ("arm", 1.4, _royal_hand, _royal_elbow, (0.0, -0.4, 0.0)),
                 ("arm", 1.85, _royal_hand, _royal_elbow, (0.0, 0.55, 0.0)), ("arm", 2.3, _royal_hand, _royal_elbow, (0.0, -0.4, 0.0)),
                 ("arm", 2.75, _royal_hand, _royal_elbow, (0.0, 0.3, 0.0)), ("arm", 3.1, _royal_hand, _royal_elbow),
                 ("arm", 3.8, REST)],
    "LeftArm": [("arm", 0, REST), ("arm", 0.5, (-0.1, 0.3, 1.05), (-1.3, 0.65, 0.65)), ("arm", 3.1, (-0.1, 0.3, 1.05), (-1.3, 0.65, 0.65)),
                ("arm", 3.8, REST)],
    "Neck": [(0, 0, 0, 0), (0.55, 0.12, 0, 0), (1.3, 0.12, 0.28, 0), (2.4, 0.12, -0.28, 0), (3.1, 0.1, 0, 0), (3.8, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.55, 0.06, 0, 0), (1.3, 0.06, 0.08, 0), (2.4, 0.06, -0.08, 0), (3.1, 0.05, 0, 0), (3.8, 0, 0, 0)],
})

# GROOVE: a little dance on the spot, a two-step from the knees, the hips swaying, the arms swinging loose and bent, the head
# bobbing on the beat; a beat a second, over and over while it lasts.
POSES["emoteGroove"] = P(8.9, {
    "Root": [(0, 0, 0, 0, 0, 0, 0), (0.4, 0, 0.1, 0.05, 0, -0.1, 0), (0.9, 0, 0, 0, 0, 0, 0), (1.4, 0, -0.1, -0.05, 0, -0.1, 0),
             (1.9, 0, 0, 0, 0, 0, 0), (2.4, 0, 0.1, 0.05, 0, -0.1, 0), (2.9, 0, 0, 0, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.4, 0.04, -0.16, -0.06), (0.9, 0, 0, 0), (1.4, 0.04, 0.16, 0.06), (1.9, 0, 0, 0), (2.4, 0.04, -0.16, -0.06),
              (2.9, 0, 0, 0)],
    "RightKnee": [(0, 0, 0, 0), (0.4, -0.32, 0, 0), (0.9, -0.06, 0, 0), (1.4, -0.12, 0, 0), (1.9, -0.06, 0, 0), (2.4, -0.32, 0, 0), (2.9, 0, 0, 0)],
    "LeftKnee": [(0, 0, 0, 0), (0.4, -0.12, 0, 0), (0.9, -0.06, 0, 0), (1.4, -0.32, 0, 0), (1.9, -0.06, 0, 0), (2.4, -0.12, 0, 0), (2.9, 0, 0, 0)],
    "RightHip": [(0, 0, 0, 0), (0.4, 0.18, 0, 0), (0.9, 0.03, 0, 0), (1.4, 0.06, 0, 0), (1.9, 0.03, 0, 0), (2.4, 0.18, 0, 0), (2.9, 0, 0, 0)],
    "LeftHip": [(0, 0, 0, 0), (0.4, 0.06, 0, 0), (0.9, 0.03, 0, 0), (1.4, 0.18, 0, 0), (1.9, 0.03, 0, 0), (2.4, 0.06, 0, 0), (2.9, 0, 0, 0)],
    "RightShoulder": [(0, 0, 0, 0), (0.4, 0.55, 0, 0.25), (0.9, 0.1, 0, 0.3), (1.4, -0.3, 0, 0.25), (1.9, 0.1, 0, 0.3), (2.4, 0.55, 0, 0.25),
                      (2.9, 0, 0, 0)],
    "LeftShoulder": [(0, 0, 0, 0), (0.4, -0.3, 0, -0.25), (0.9, 0.1, 0, -0.3), (1.4, 0.55, 0, -0.25), (1.9, 0.1, 0, -0.3), (2.4, -0.3, 0, -0.25),
                     (2.9, 0, 0, 0)],
    "RightElbow": [(0, 0, 0, 0), (0.4, 1.3, 0, 0), (0.9, 1.1, 0, 0), (1.4, 1.3, 0, 0), (1.9, 1.1, 0, 0), (2.4, 1.3, 0, 0), (2.9, 0, 0, 0)],
    "LeftElbow": [(0, 0, 0, 0), (0.4, 1.3, 0, 0), (0.9, 1.1, 0, 0), (1.4, 1.3, 0, 0), (1.9, 1.1, 0, 0), (2.4, 1.3, 0, 0), (2.9, 0, 0, 0)],
    "Neck": [(0, 0, 0, 0), (0.4, 0.04, 0, 0.06), (0.65, -0.1, 0, 0.06), (0.9, 0.04, 0, -0.06), (1.15, -0.1, 0, -0.06), (1.4, 0.04, 0, 0.06),
             (1.65, -0.1, 0, 0.06), (1.9, 0.04, 0, -0.06), (2.15, -0.1, 0, -0.06), (2.4, 0.04, 0, 0.06), (2.9, 0, 0, 0)],
}, loop=(0.4, 2.4))

# SHRUG: palms up and out, the shoulders up round the ears, the head tilted and a little pull of the face to one side; and
# let fall.
POSES["emoteShrug"] = P(2.0, {
    "RightArm": [("arm", 0, REST), ("arm", 0.4, (1.95, 0.72, -0.95), (1.4, 0.65, -0.1), (0, -0.6, 0)), ("arm", 1.3, (1.95, 0.78, -0.95), (1.4, 0.7, -0.1), (0, -0.6, 0)),
                 ("arm", 2.0, REST)],
    "LeftArm": [("arm", 0, REST), ("arm", 0.4, mirror((1.95, 0.72, -0.95)), mirror((1.4, 0.65, -0.1)), (0, 0.6, 0)),
                ("arm", 1.3, mirror((1.95, 0.78, -0.95)), mirror((1.4, 0.7, -0.1)), (0, 0.6, 0)), ("arm", 2.0, REST)],
    "Neck": [(0, 0, 0, 0), (0.4, -0.06, 0.08, 0.2), (1.3, -0.04, 0.08, 0.22), (2.0, 0, 0, 0)],
    "Waist": [(0, 0, 0, 0), (0.4, 0.04, 0, 0.03), (1.3, 0.04, 0, 0.03), (2.0, 0, 0, 0)],
})

# FLEX: both arms up into a double biceps, a squeeze, a turn to show one side and the other, and down.
_fx = ((1.45, 2.4, -0.3), (1.9, 1.42, -0.05))
POSES["emoteFlex"] = P(2.8, {
    "RightArm": [("arm", 0, REST), ("arm", 0.45, _fx[0], _fx[1]), ("arm", 0.75, (1.4, 2.3, -0.4), (1.9, 1.38, -0.05)), ("arm", 1.05, _fx[0], _fx[1]),
                 ("arm", 2.2, _fx[0], _fx[1]), ("arm", 2.8, REST)],
    "LeftArm": [("arm", 0, REST), ("arm", 0.45, mirror(_fx[0]), mirror(_fx[1])), ("arm", 0.75, mirror((1.4, 2.3, -0.4)), mirror((1.9, 1.38, -0.05))),
                ("arm", 1.05, mirror(_fx[0]), mirror(_fx[1])), ("arm", 2.2, mirror(_fx[0]), mirror(_fx[1])), ("arm", 2.8, REST)],
    "Waist": [(0, 0, 0, 0), (0.45, 0.06, 0, 0), (1.3, 0.06, 0.32, 0), (1.9, 0.06, -0.32, 0), (2.3, 0.04, 0, 0), (2.8, 0, 0, 0)],
    "Neck": [(0, 0, 0, 0), (0.45, 0.1, 0, 0), (1.3, 0.1, 0.2, 0), (1.9, 0.1, -0.2, 0), (2.3, 0.05, 0, 0), (2.8, 0, 0, 0)],
    "RightKnee": [(0, 0, 0, 0), (0.45, -0.14, 0, 0), (2.3, -0.14, 0, 0), (2.8, 0, 0, 0)],
    "LeftKnee": [(0, 0, 0, 0), (0.45, -0.14, 0, 0), (2.3, -0.14, 0, 0), (2.8, 0, 0, 0)],
})


# ---------------------------------------------------------------------------------------------------- arms into joints

def expand(pose):
    """The pose's keys with every arm solved into its shoulder, elbow and wrist."""
    keys = {}
    worst = 0.0
    for joint, track in pose["keys"].items():
        if not joint.endswith("Arm"):
            keys[joint] = [tuple(k) for k in track]
            continue
        side = joint[:-3]
        shoulder, elbow, wrist = [], [], []
        previous = None
        for key in track:
            _, t, hand = key[0], key[1], key[2]
            elbow_at = key[3] if len(key) > 3 else None
            turn = key[4] if len(key) > 4 else (0.0, 0.0, 0.0)
            if hand == REST:
                s, e = (0.0, 0.0, 0.0), 0.0
                turn = (0.0, 0.0, 0.0)
            else:
                v, miss = solve(side, hand, elbow_at, previous, turn)
                worst = max(worst, miss)
                s, e = (v[0], v[1], v[2]), v[3]
                previous = v
            shoulder.append((t,) + tuple(s))
            elbow.append((t, e, 0.0, 0.0))
            wrist.append((t,) + tuple(turn))
        keys.setdefault(side + "Shoulder", shoulder)
        keys.setdefault(side + "Elbow", elbow)
        # A wrist written apart (a tap, a flick) is its own track and wins over the arm's.
        if side + "Wrist" not in pose["keys"]:
            keys[side + "Wrist"] = wrist
    return {"seconds": pose["seconds"], "loop": pose["loop"], "keys": keys}, worst


def number(v):
    text = ("%.3f" % v).rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


ORDER = ["Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist",
         "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle"]


def spec_hash():
    """What the poses are written as here, as one short hash: Poses.lua carries it, so a check can tell (without solving
    every arm again) whether the table there was written from these."""
    import hashlib
    return hashlib.sha1(repr(sorted((name, repr(pose)) for name, pose in POSES.items())).encode("utf-8")).hexdigest()[:12]


def luau(expanded):
    lines = [BEGIN, "-- spec " + spec_hash(), "local KEYED: { [string]: Keyed } = {"]
    for name, pose in expanded.items():
        head = "\t%s = { seconds = %s" % (name, number(pose["seconds"]))
        if pose["loop"]:
            head += ", loop = { %s, %s }" % (number(pose["loop"][0]), number(pose["loop"][1]))
        lines.append(head + ", keys = {")
        for joint in ORDER:
            track = pose["keys"].get(joint)
            if not track:
                continue
            width = 7 if joint == "Root" and any(len(k) > 4 and any(abs(x) > 1e-9 for x in k[4:]) for k in track) else 4
            keys = ", ".join("{ " + ", ".join(number(v) for v in (list(k) + [0, 0, 0])[:width]) + " }" for k in track)
            lines.append("\t\t%s = { %s }," % (joint, keys))
        lines.append("\t} },")
    lines.append("}")
    lines.append("")
    lines.append("-- How long each lasts, for whoever plays it (EmoteService, PlayerLife).")
    lines.append("Poses.LENGTH = {")
    for name, pose in expanded.items():
        lines.append("\t%s = %s," % (name, number(pose["seconds"])))
    lines.append("}")
    for name in expanded:
        lines.append("")
        lines.append("function Poses.%s(name: string, t: number, w: number, r6: boolean): CFrame?" % name)
        lines.append("\treturn play(KEYED.%s, name, t, r6)" % name)
        lines.append("end")
    lines.append(END)
    return "\n".join(lines)


def main():
    if "--check" in sys.argv:
        text = POSES_LUA.read_text(encoding="utf-8")
        fresh = ("-- spec " + spec_hash()) in text
        print("Poses.lua is %s" % ("written from these poses" if fresh else "OUT OF DATE: run blender/gen_poses.py"))
        sys.exit(0 if fresh else 1)
    expanded = {}
    for name, pose in POSES.items():
        expanded[name], miss = expand(pose)
        print("  %-12s %4.1fs  %2d joints  hands within %.2f studs of where they were asked" % (
            name, pose["seconds"], len(expanded[name]["keys"]), miss))
    block = luau(expanded)
    text = POSES_LUA.read_text(encoding="utf-8")
    newline = "\r\n" if "\r\n" in text else "\n"
    text = text.replace("\r\n", "\n")
    start, end = text.find(BEGIN), text.find(END)
    if start < 0 or end < 0:
        print("!! Poses.lua has no KEYED markers: add them where the table goes")
        sys.exit(1)
    current = text[start:end + len(END)]
    if "--check" in sys.argv:
        print("Poses.lua is %s" % ("up to date" if current == block else "OUT OF DATE: run without --check"))
        sys.exit(0 if current == block else 1)
    text = text[:start] + block + text[end + len(END):]
    POSES_LUA.write_bytes(text.replace("\n", newline).encode("utf-8"))
    print("  wrote %d poses into src/Shared/Poses.lua" % len(expanded))


if __name__ == "__main__":
    main()
