"""Level 1, City Shore: the high dive, shot by shot, restated from CityShoreClient (the shots) and DiveFinaleService
(the deck, the board, Maren, the water), frame by frame, for check_shots.py.

In the deck's own frame (DiveFinaleService's finishFrame): the deck 36 wide across X and 30 deep along Z from z = 0,
the board running out along +X to its tip at x = BOARD_TO, the water far below.
"""
import math
import pathlib
import re

import numpy as np

from shots import Frame, flat, mark_cuts, unit, v

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLIENT = (ROOT / "src" / "Client" / "Services" / "CityShoreClient.lua").read_text(encoding="utf-8").replace("\r\n", "\n")
SERVER = (ROOT / "src" / "Server" / "Services" / "DiveFinaleService.lua").read_text(encoding="utf-8").replace("\r\n", "\n")


def num(text, name):
    found = re.search(r"^local %s = (-?[\d.]+)" % name, text, re.M)
    if not found:
        raise SystemExit("shots_shore.py: %s is gone" % name)
    return float(found.group(1))


FALL_SPEED = num(CLIENT, "FALL_SPEED")
DRIFT = num(CLIENT, "DRIFT")
HANG_SECONDS, HANG_SPEED = (float(x) for x in re.search(r"^local HANG_SECONDS, HANG_SPEED = ([\d.]+), ([\d.]+)", CLIENT, re.M).groups())
CARRY_SPEED = num(CLIENT, "CARRY_SPEED")
SPLASH_SINK = num(CLIENT, "SPLASH_SINK")
WATER_SHOT = num(CLIENT, "WATER_SHOT")
DECK_WIDE = num(SERVER, "DECK_WIDE")
DECK_DEEP = num(SERVER, "DECK_DEEP")
BOARD_TO = num(SERVER, "BOARD_TO")
BOARD_TOP = num(SERVER, "BOARD_TOP")
ZONE_TOP = num(SERVER, "ZONE_TOP")
COMMIT_ABOVE = num(SERVER, "COMMIT_ABOVE")
FALLBACK_WATER = num(SERVER, "FALLBACK_WATER")
GRAVITY = 196.2
WATER = FALLBACK_WATER - 53  # the log: the deck at y 53, the water 753 under it; in the deck's frame, -753

SHOT_LINES = (
    "local eye = current.tip + side * 7 - current.facing * 3 + Vector3.new(0, -4, 0)",
    "Cinema.point(CFrame.lookAt(eye, here + Vector3.new(0, -0.5, 0)) * CFrame.Angles(0, 0, tip), 60 - 10 * math.min(1, t / 1.6))",
    "local eye = head - toward * 3.2 + Vector3.new(0, 1.3, 0) + Vector3.new(-toward.Z, 0, toward.X) * 1.4",
    "Cinema.point(CFrame.lookAt(eye, here), 44)",
    "local round = side * math.cos(a) + current.facing * math.sin(a)",
    "Cinema.point(CFrame.lookAt(here + round * 12 + Vector3.new(0, -3, 0), here) * CFrame.Angles(0, 0, -0.1), 64)",
    "if down >= 0.5 then",
    "local eye = Cinema.clear(face - current.facing * 4.2 - Vector3.new(0, 2.2, 0) + side * 1.1, face, { character })",
    "Cinema.point(CFrame.lookAt(eye, face) * CFrame.Angles(0, 0, 0.07 * math.sin(t * 2.3)), 58)",
    "local eye = Cinema.clear(here + Vector3.new(0, 9, 0) - current.facing * 4 + side * 2.5, here, { character })",
    "Cinema.point(CFrame.lookAt(eye, here - Vector3.new(0, 22, 0), current.facing) * CFrame.Angles(0, 0, lean), 78)",
    "Cinema.point(CFrame.lookAt(below + current.facing * 22 + side * 6 + Vector3.new(0, 2.5, 0), here - Vector3.new(0, 14, 0)), 50)",
    "local eye = here - current.facing * 7 + side * 1.5 + Vector3.new(0, 3 - math.min(since, 10) * 0.2, 0)",
    "eye = Vector3.new(eye.X, math.min(eye.Y, current.water - 1.5), eye.Z)",
    "Cinema.point(CFrame.lookAt(eye, here:Lerp(lamp, math.clamp((since - 2) / 3.5, 0, 0.7))), 66)",
)


def smooth(u):
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


def body(here, facing, t, carried_turn=None):
    """Head and feet, turned over head first as the client turns them (root.CFrame ... Angles(-0.95 pi over, ...))."""
    over = smooth((t - 0.35) / 1.4) if carried_turn is None else carried_turn
    theta = -math.pi * 0.95 * over
    up = v(0, 1, 0) * math.cos(theta) - facing * math.sin(theta)
    return {"head": here + up * 1.5, "feet": here - up * 2.5}, over


def dive(fps=60, under_for=5.0):
    tip = v(BOARD_TO, BOARD_TOP, DECK_DEEP / 2)
    here = v(BOARD_TO + 2, BOARD_TOP - ZONE_TOP - 0.5, DECK_DEEP / 2)  # just under the board, off its end
    facing = flat(here - tip)
    side = v(-facing[2], 0, facing[0])
    maren_head = v(8, 4.8, 9)
    vel = v(DRIFT, -math.sqrt(2 * GRAVITY * (ZONE_TOP + 0.5)), 0)
    frames = []
    carry_from = None
    turned = None
    drop_top = None
    splash_at = None
    t = 0.0
    dt = 1 / fps
    while True:
        height = here[1] - WATER
        if splash_at is None and here[1] <= WATER - SPLASH_SINK + 1e-6:
            splash_at = t
        if splash_at is not None and t - splash_at > under_for:
            break
        # the fall: the client's caps, then the server's carry from COMMIT_ABOVE over the water
        if splash_at is None:
            if height > COMMIT_ABOVE:
                vel = vel + v(0, -GRAVITY * dt, 0)
                limit = HANG_SPEED if t < HANG_SECONDS else FALL_SPEED
                vel = v(vel[0], max(vel[1], -limit), vel[2])
                here = here + vel * dt
            else:
                if carry_from is None:
                    carry_from = here.copy()
                    turned = smooth((t - 0.35) / 1.4)
                here = v(here[0], max(WATER - SPLASH_SINK, here[1] - CARRY_SPEED * dt), here[2])
        else:
            # the server sinks them SINK_DEPTH over SINK_TIME (eased), then holds them there
            sunk = 7 * smooth((t - splash_at) / 0.7)
            here = v(here[0], WATER - SPLASH_SINK - sunk, here[2])
        pose, _ = body(here, facing, t, turned)
        if splash_at is None:
            if t < 1.6:
                tiltk = 0.12 * min(1, max(0, (t - 0.6) / 1.0))
                eye = tip + side * 7 - facing * 3 + v(0, -4, 0)
                frames.append(Frame(t, "dive: the leap", eye, here + v(0, -0.5, 0), 60 - 10 * min(1, t / 1.6), subject=pose))
            elif t < 2.7:
                toward = flat(here - maren_head)
                eye = maren_head - toward * 3.2 + v(0, 1.3, 0) + v(-toward[2], 0, toward[0]) * 1.4
                frames.append(Frame(t, "dive: Maren", eye, here, 44, subject=pose))
            elif t < 4.2:
                a = (t - 2.7) * 0.9
                rnd = side * math.cos(a) + facing * math.sin(a)
                frames.append(Frame(t, "dive: the turn", here + rnd * 12 + v(0, -3, 0), here, 64, subject=pose))
            elif height > WATER_SHOT:
                if drop_top is None:
                    drop_top = height
                down = min(1, max(0, (drop_top - height) / max(1, drop_top - WATER_SHOT)))
                if down >= 0.5:
                    face = pose["head"]
                    eye = face - facing * 4.2 - v(0, 2.2, 0) + side * 1.1
                    frames.append(Frame(t, "dive: your face", eye, face, 58,
                                        subject={"head": face + v(0, -0.7, 0), "feet": face + v(0, 0.8, 0)}))
                else:
                    eye = here + v(0, 9, 0) - facing * 4 + side * 2.5
                    frames.append(Frame(t, "dive: the drop", eye, here - v(0, 22, 0), 78, up=facing, subject=pose))
            else:
                below = v(here[0], WATER, here[2])
                frames.append(Frame(t, "dive: the water", below + facing * 22 + side * 6 + v(0, 2.5, 0), here - v(0, 14, 0), 50,
                                    subject=pose))
        else:
            since = t - splash_at
            lamp = v(here[0], WATER - 120 + 14.4, here[2]) + facing * 22
            eye = here - facing * 7 + side * 1.5 + v(0, 3 - min(since, 10) * 0.2, 0)
            eye = v(eye[0], min(eye[1], WATER - 1.5), eye[2])
            target = here + (lamp - here) * min(0.7, max(0, (since - 2) / 3.5))
            frames.append(Frame(t, "dive: under the water", eye, target, 66, subject=pose,
                                looks_at="subject" if since < 2.05 else "away"))
        t += dt
    return mark_cuts(frames, {f.shot for f in frames}), tip


def scenery(tip):
    w, d = DECK_WIDE / 2, DECK_DEEP
    lines = [([v(-w, 0, 0), v(w, 0, 0), v(w, 0, d), v(-w, 0, d), v(-w, 0, 0)], "#90a4ae", 2),
             ([v(4, BOARD_TOP, DECK_DEEP / 2), tip], "#ffffff", 4)]
    for y in range(-60, int(WATER), -60):  # the tower's face, schematically: a column under the deck
        lines.append(([v(-w, y, 0), v(w, y, 0), v(w, y, d), v(-w, y, d), v(-w, y, 0)], "#b0bec5", 1))
    for k in range(-6, 7):  # the sea, as a grid
        lines.append(([v(-300 + 0, WATER, k * 50 + 15), v(600, WATER, k * 50 + 15)], "#4fc3f7", 1))
        lines.append(([v(k * 50 + 150, WATER, -300), v(k * 50 + 150, WATER, 330)], "#4fc3f7", 1))
    return lines
