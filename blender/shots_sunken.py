"""Level 3, the Sunken City: down the drain, along Outfall 3 and the reveal in the pumping station, shot by shot,
restated from SunkenCityClient (the shots), SunkenPath (the ride) and SunkenCityService (where it all is), frame by
frame, for check_shots.py.

In the whirlpool's own frame: the vortex at the origin on the water's surface (y = 0), the culvert running out
along -X under the sea floor, the station at its end.
"""
import math
import pathlib
import re

import numpy as np

from shots import Frame, flat, mark_cuts, unit, v

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLIENT = (ROOT / "src" / "Client" / "Services" / "SunkenCityClient.lua").read_text(encoding="utf-8").replace("\r\n", "\n")
SERVER = (ROOT / "src" / "Server" / "Services" / "SunkenCityService.lua").read_text(encoding="utf-8").replace("\r\n", "\n")
PATH = (ROOT / "src" / "Shared" / "SunkenPath.lua").read_text(encoding="utf-8").replace("\r\n", "\n")


def num(text, pattern):
    found = re.search(pattern, text, re.M)
    if not found:
        raise SystemExit("shots_sunken.py: no longer found: %s" % pattern)
    return [float(g) for g in found.groups()]


VORTEX_R = num(SERVER, r"^local VORTEX_R = ([\d.]+)")[0]
FUNNEL_DEPTH = num(SERVER, r"^local FUNNEL_DEPTH = ([\d.]+)")[0]
SHAFT_DEPTH = num(SERVER, r"^local SHAFT_DEPTH = ([\d.]+)")[0]
FLOOR_DEPTH = num(SERVER, r"^local FLOOR_DEPTH = ([\d.]+)")[0]
DRAIN_R = num(SERVER, r"^local DRAIN_R = ([\d.]+)")[0]
OUT_L, OUT_HALF, OUT_H = num(SERVER, r"local OUT_L, OUT_HALF, OUT_H = ([\d.]+), ([\d.]+), ([\d.]+)")
HALL_L, HALL_W, HALL_H = num(SERVER, r"local HALL_L, HALL_W, HALL_H = ([\d.]+), ([\d.]+), ([\d.]+)")
DRAIN_SECONDS = num(PATH, r"^SunkenPath\.DRAIN_SECONDS = ([\d.]+)")[0]
OUTFALL_SECONDS = num(PATH, r"^SunkenPath\.OUTFALL_SECONDS = ([\d.]+)")[0]
REVEAL_SECONDS = num(PATH, r"^SunkenPath\.REVEAL_SECONDS = ([\d.]+)")[0]
CIRCLE_OUT, CIRCLE_UP, CIRCLE_TURN = num(CLIENT, r"CIRCLE = \{ out = ([\d.]+), up = ([\d.]+), turn = ([\d.]+) \}")
SHAFT_UP = num(CLIENT, r"^\tSHAFT_UP = ([\d.]+),")[0]
FOV = num(CLIENT, r"^\tFOV = ([\d.]+),")[0]

SHOT_LINES = (
    "Cinema.point(CFrame.lookAt(clearOf(head + out * 7 + Vector3.new(0, 1.2, 0), head), head), 46)",
    "local eye = Vector3.new(spec.vortex.X - 10, spec.bottomY + 0.5, spec.vortex.Z)",
    "Cinema.point(CFrame.lookAt(clearOf(eye, head), head - Vector3.new(0, 3, 0)), 78)",
    "if at.Y < spec.funnelY - 8 then",
    "local eye = Vector3.new(spec.vortex.X + 1.4, at.Y - 11, spec.vortex.Z + 1.1)",
    "Cinema.point(CFrame.lookAt(eye, head + Vector3.new(0, 6, 0), Vector3.zAxis), 78)",
    "local blend = math.clamp((u - 0.44) / 0.1, 0, 1)",
    "Cinema.point(circling:Lerp(down, blend), cutscene.FOV - 14 * blend * u)",
    "Cinema.point(CFrame.lookAt(clearOf(head + run * 10 + Vector3.new(0, 1.8, 0), head), head), 58)",
    "Cinema.point(CFrame.lookAt(clearOf(head + side * 2.4 - run * 1.5 + Vector3.new(0, 2.6, 0), head), head), 56)",
    "local eye = clearOf(head - run * 9 + Vector3.new(0, 4, 0), head)",
    "Cinema.point(CFrame.lookAt(eye, head + run * 10 - Vector3.new(0, 1, 0)), 64)",
    "Cinema.point(CFrame.lookAt(reveal.eye, head), 70)",
    "Cinema.point(CFrame.lookAt(eye, look:Lerp(reveal.card, e)), 70 - 30 * e, true)",
)

FUNNEL_Y = -FUNNEL_DEPTH
SHAFT_BOTTOM = -FLOOR_DEPTH - SHAFT_DEPTH
BOTTOM_Y = SHAFT_BOTTOM + 3
X0 = -DRAIN_R - 0.5
X1 = X0 - OUT_L
FAR = X1 - HALL_L
O_FROM, O_MOUTH, O_TO = v(0, SHAFT_BOTTOM + 3, 0), v(X0 - 1, SHAFT_BOTTOM + 3, 0), v(X1 - 9, SHAFT_BOTTOM + 3, 0)
O_WATER = SHAFT_BOTTOM + 0.7
REVEAL_EYE = v(FAR + 3, SHAFT_BOTTOM + HALL_H - 2.5, -HALL_W / 2 + 3)
CARD = v(X1 - 8, SHAFT_BOTTOM + 4.9, HALL_W / 2 - 0.5)
CARD_EYE = CARD + v(0, 0.1, -2.4)


def smooth(u):
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


def drain_at(u, start):
    r0 = max(2, math.hypot(start[0], start[2]))
    a0 = math.atan2(start[2], start[0])
    if u < 0.5:
        s = u / 0.5
        r = r0 + (1.5 - r0) * s
        a = a0 + s * 2.2 * 2 * math.pi
        here = v(math.cos(a) * r, start[1] + (FUNNEL_Y - start[1]) * s * s, math.sin(a) * r)
        facing = v(-math.sin(a), 0, math.cos(a))
        up = v(0, 1, 0)
    else:
        s = (u - 0.5) / 0.5
        a = a0 + 2.2 * 2 * math.pi + s * 3 * 2 * math.pi
        here = v(math.cos(a) * 1.2, FUNNEL_Y + (BOTTOM_Y - FUNNEL_Y) * s * s, math.sin(a) * 1.2)
        facing = v(math.cos(a), 0, math.sin(a))
        e = min(1, s / 0.9)
        flip = 4 * math.pi * e * e * (3 - 2 * e)
        up = v(0, 1, 0) * math.cos(flip) + facing * math.sin(flip)
    return here, facing, up


def outfall_at(w):
    e = 1 - (1 - min(1, max(0, w))) ** 1.6
    first, second = np.linalg.norm(O_MOUTH - O_FROM), np.linalg.norm(O_TO - O_MOUTH)
    along = e * (first + second)
    if along <= first:
        at, run = O_FROM + (O_MOUTH - O_FROM) * (along / max(0.01, first)), O_MOUTH - O_FROM
    else:
        at, run = O_MOUTH + (O_TO - O_MOUTH) * ((along - first) / max(0.01, second)), O_TO - O_MOUTH
    return at, flat(run)


def ride(fps=60, start=v(18, 1.5, 4)):
    frames = []
    for i in range(int(DRAIN_SECONDS * fps)):
        t = i / fps
        u = t / DRAIN_SECONDS
        at, facing, up = drain_at(u, start)
        head = at + v(0, 1.5, 0)
        body = {"head": at + up * 1.5, "feet": at - up * 2.5}
        if u < 0.1:
            out = flat(at)
            # a close shot of the face: judged by the head and shoulders, not the feet
            frames.append(Frame(t, "drain: the grab", head + out * 7 + v(0, 1.2, 0), head, 46,
                                subject={"head": at + up * 2.1, "feet": at + up * 0.3}))
        elif u >= 0.9:
            frames.append(Frame(t, "drain: the bottom", v(-10, BOTTOM_Y + 0.5, 0), head - v(0, 3, 0), 78, subject=body))
        elif at[1] < FUNNEL_Y - 8:
            frames.append(Frame(t, "drain: down the shaft", v(1.4, at[1] - 11, 1.1), head + v(0, 6, 0), 78, up=v(0, 0, 1),
                                subject=body))
        else:
            a = t * CIRCLE_TURN
            rnd = head + v(math.cos(a) * CIRCLE_OUT, CIRCLE_UP, math.sin(a) * CIRCLE_OUT)
            over = v(0, FUNNEL_Y + SHAFT_UP, 0)
            blend = smooth((u - 0.44) / 0.1)
            eye = rnd + (over - rnd) * blend
            frames.append(Frame(t, "drain: round the funnel", eye, head, FOV - 14 * blend * u,
                                up=v(0, 0, 1) if blend > 0.5 else v(0, 1, 0), subject=body))
    t0 = DRAIN_SECONDS
    for i in range(int(OUTFALL_SECONDS * fps)):
        w = i / fps / OUTFALL_SECONDS
        t = t0 + i / fps
        at, run = outfall_at(w)
        lift = min(1, w / 0.08) * (1 - min(1, max(0, (w - 0.88) / 0.12)))
        floating = O_WATER + 0.9
        here = v(at[0], at[1] + (floating - at[1]) * lift, at[2])
        head = here + v(0, 0.6, 0)
        tip = math.radians(78) * lift
        up = v(0, 1, 0) * math.cos(tip) - run * math.sin(tip)  # tipped back, feet first: the head trails
        body = {"head": here + up * 1.5, "feet": here - up * 2.5}
        side = unit(np.cross(run, v(0, 1, 0)))
        if w < 0.3:
            frames.append(Frame(t, "outfall: from ahead", head + run * 10 + v(0, 1.8, 0), head, 58, subject=body))
        elif w < 0.62:
            frames.append(Frame(t, "outfall: alongside", head + side * 2.4 - run * 1.5 + v(0, 2.6, 0), head, 56,
                                subject={"head": here + up * 2.1, "feet": here + up * 0.3}))
        elif w < 0.9:
            frames.append(Frame(t, "outfall: to the light", head - run * 9 + v(0, 4, 0), head + run * 10 - v(0, 1, 0), 64,
                                subject=body))
        else:
            frames.append(Frame(t, "outfall: the station", REVEAL_EYE, head, 70, subject=body))
    t1 = t0 + OUTFALL_SECONDS
    end_at, _ = outfall_at(1)
    standing = {"head": end_at + v(0, 1.5, 0), "feet": end_at - v(0, 3, 0)}
    for i in range(int(REVEAL_SECONDS * fps)):
        r = i / fps / REVEAL_SECONDS
        e = smooth(r)
        eye = REVEAL_EYE + (CARD_EYE - REVEAL_EYE) * e
        look = REVEAL_EYE + (CARD - REVEAL_EYE) * min(1, e * 1.6)
        frames.append(Frame(t1 + i / fps, "reveal: the time card", eye, look + (CARD - look) * e, 70 - 30 * e, looks_at="away",
                            subject={"card": CARD}))
    return mark_cuts(frames, {"drain: the grab", "outfall: from ahead", "reveal: the time card"})


def scenery():
    lines = []
    for k in range(6):
        r = VORTEX_R * (1 - k / 6)
        y = -FUNNEL_DEPTH * (k / 5) ** 1.6
        lines.append(([v(math.cos(a) * r, y, math.sin(a) * r) for a in np.linspace(0, 2 * math.pi, 40)], "#4dd0e1", 1))
    for y in np.linspace(FUNNEL_Y, SHAFT_BOTTOM, 8):
        lines.append(([v(math.cos(a) * DRAIN_R, y, math.sin(a) * DRAIN_R) for a in np.linspace(0, 2 * math.pi, 30)], "#78909c", 1))
    floor, roof = SHAFT_BOTTOM, SHAFT_BOTTOM + OUT_H
    for z in (-OUT_HALF, OUT_HALF):
        for y in (floor, roof):
            lines.append(([v(X0, y, z), v(X1, y, z)], "#a1887f", 1))
    for x in np.linspace(X0, X1, 8):
        lines.append(([v(x, floor, -OUT_HALF), v(x, roof, -OUT_HALF), v(x, roof, OUT_HALF), v(x, floor, OUT_HALF)], "#bcaaa4", 1))
    hw = HALL_W / 2
    for y in (floor, floor + HALL_H):
        lines.append(([v(X1, y, -hw), v(FAR, y, -hw), v(FAR, y, hw), v(X1, y, hw), v(X1, y, -hw)], "#8d6e63", 1))
    lines.append(([CARD + v(-0.5, -0.7, 0), CARD + v(0.5, -0.7, 0), CARD + v(0.5, 0.7, 0), CARD + v(-0.5, 0.7, 0), CARD + v(-0.5, -0.7, 0)],
                  "#ffb300", 2))
    return lines
