"""Level 4, the Flooded Halls, shot by shot: the flume, the fall into the mouth, and the gate chamber, restated from
FloodedHallsClient (the shots) and FloodedHallsService (where everything is), frame by frame, for check_shots.py.

In the slide's own frame: the mast on the Y axis, the top of the helix at (SLIDE_RADIUS, 0, 0). The chamber in its
own frame: its floor at y = 0, the gates at -Z, the sump at +Z (as `at(x, y, z)` has it in the client).
"""
import math
import pathlib
import re

import numpy as np

from shots import Frame, flat, mark_cuts, turn_y, unit, v

ROOT = pathlib.Path(__file__).resolve().parent.parent
SERVER = (ROOT / "src" / "Server" / "Services" / "FloodedHallsService.lua").read_text(encoding="utf-8")
CLIENT = (ROOT / "src" / "Client" / "Services" / "FloodedHallsClient.lua").read_text(encoding="utf-8")


def num(text, pattern):
    found = re.search(pattern, text, re.M)
    if not found:
        raise SystemExit("shots_halls.py: no longer found: %s" % pattern)
    return float(found.group(1))


SCALE = num(SERVER, r"^local SCALE = ([\d.]+)")
R = num(SERVER, r"^local SLIDE_RADIUS = ([\d.]+) \* SCALE") * SCALE
TURNS = num(SERVER, r"^local SLIDE_TURNS = ([\d.]+)")
DROP = num(SERVER, r"^local SLIDE_DROP = ([\d.]+) \* SCALE") * SCALE
HELIX = num(SERVER, r"^local SLIDE_HELIX = ([\d.]+)")
PLUNGE = num(SERVER, r"^local SLIDE_PLUNGE = ([\d.]+)")
SECONDS = num(SERVER, r"^local SLIDE_SECONDS = ([\d.]+)")
BANK = math.radians(num(SERVER, r"^local FLUME_BANK = math\.rad\(([\d.]+)\)"))
PIT_HALF = num(SERVER, r"^local PIT_HALF = ([\d.]+)")
MAW_SECONDS = num(SERVER, r"^\tMAW = ([\d.]+),")
JAWS = {k: float(x) for k, x in re.findall(r"^\t(\w+) = ([\d.]+), --", CLIENT[CLIENT.find("local JAWS = {"):CLIENT.find("local MAW_DEEP")], re.M)}
MAW_DEEP, MAW_RISE, LUNGE = (float(x) for x in re.search(r"^local MAW_DEEP, MAW_RISE, LUNGE = ([\d.]+), ([\d.]+), ([\d.]+)", CLIENT, re.M).groups())
TURN_AT, TURN = (float(x) for x in re.search(r"^local TURN_AT, TURN = ([\d.]+), ([\d.]+)", CLIENT, re.M).groups())
HANG = num(CLIENT, r"^local HANG = ([\d.]+)")
THROAT_FROM = num(CLIENT, r"^local THROAT = \{ from = ([\d.]+),")
THROAT_SPIT = num(CLIENT, r"^local THROAT = \{.*spit = ([\d.]+) \}")
BEAT = {k: float(x) for k, x in re.findall(r"^\t(\w+) = ([\d.]+),", CLIENT[CLIENT.find("local BEAT = {"):CLIENT.find("-- THE GATE CHAMBER, `b` seconds")], re.M)}
G_HALF_W = num(SERVER, r"^\tHALF_W = ([\d.]+),")
G_HALF_L = num(SERVER, r"^\tHALF_L = ([\d.]+),")
G_HIGH = num(SERVER, r"^\tHIGH = ([\d.]+),")
G_SECONDS = num(SERVER, r"^\tSECONDS = ([\d.]+),")
SUMP_Z = num(SERVER, r"^\tSUMP = Vector3\.new\(0, 0, ([\d.]+)\),")
SUMP_HALF = num(SERVER, r"^\tSUMP_HALF = ([\d.]+),")
WATER_DOWN = num(SERVER, r"^\tWATER_DOWN = ([\d.]+),")
STAND = v(*(float(x) for x in re.search(r"^\tSTAND = Vector3\.new\((-?[\d.]+), (-?[\d.]+), (-?[\d.]+)\),", SERVER, re.M).groups()))

# The shots themselves, as written in the client: if one of these lines changes, the restatement below is out of
# date and check_shots.py says so rather than checking a shot the game no longer has.
SHOT_LINES = (
    "local eye = Cinema.clear(here - flat * 10 + up * 5, here, ignore)",
    "Cinema.point(CFrame.lookAt(eye, here + flat * 10 - up * 3), 62)",
    "local behind = pathAt(path, f - 0.045)",
    "local eye = behind.Position + behind.UpVector * 4.2 + Vector3.new(0, 1.5, 0)",
    "Cinema.point(CFrame.lookAt(eye, here + look * 6 + up * 0.8), 70)",
    "local ahead = CFrame.Angles(0, 0.9, 0) * out",
    "current.fallEye = Vector3.new(axis.X, here.Y - 10, axis.Z) + ahead * 55",
    "Cinema.point(CFrame.lookAt(current.fallEye :: Vector3, here + Vector3.new(0, 1, 0)), 46)",
    "elseif f < 0.64 and path then",
    "local ahead = pathAt(path, math.min(HELIX - 0.005, f + 0.04))",
    "local eye = ahead.Position + ahead.UpVector * 3 + Vector3.new(0, 1, 0)",
    "Cinema.point(CFrame.lookAt(eye, here + Vector3.new(0, 1, 0)), 64)",
    "local exit = if path then pathAt(path, HELIX - 0.005) else nil",
    "current.fallEye = endAt - up * 34 + Vector3.new(endRun.Z, 0, -endRun.X) * 16 + endRun * 10",
    "Cinema.point(CFrame.lookAt(current.fallEye :: Vector3, here), 58)",
    "Cinema.point(CFrame.lookAt(here + up * 15 + flat * 3, here - up * 12), 74)",
    "Cinema.point(CFrame.lookAt(pos + Vector3.new(0, 9, 0) + inward * 3 + side * 1.5, pos - Vector3.new(0, 30, 0), side), 66)",
    "local eye = pos + Vector3.new(0, 18 - 1 * k, 0) + inward * (20 - 2 * k) + side * 8",
    "local target = (hinge.Position + opens * 16):Lerp(pos, 0.62)",
    "Cinema.point(CFrame.lookAt(held + Vector3.new(0, 9, 0) + side * 2.5, held - Vector3.new(0, 6, 0), side), 72)",
    "Cinema.point(CFrame.lookAt(eye, target, Vector3.yAxis), 74 - 4 * k)",
    "local eye = face - Vector3.new(0, 4.4 - 0.8 * k, 0) + crown * 1.8 + side * 0.8",
    "Cinema.point(CFrame.lookAt(eye, face, root.CFrame.UpVector), 54 - 6 * k)",
    "local eye = hinge.Position + opens * 9 + inward * 5",
    "Cinema.point(CFrame.lookAt(eye, pos, side), 82)",
    "Cinema.point(CFrame.lookAt(hinge.Position + opens * 55 + inward * 24 + side * 14, hinge.Position + opens * 22,",
    "Cinema.point(CFrame.lookAt(at(9, 8, 11), root.Position + Vector3.new(0, 1, 0)), 58)",
    "Cinema.point(CFrame.lookAt(at(14, 17, -30):Lerp(at(9, 14, -24), u), at(-2, 3, 8)), 62)",
    "Cinema.point(CFrame.lookAt(root.Position - flat * 10 + Vector3.new(0, 4.5, 0) + left * 5, root.Position + flat * 8), 62)",
    "Cinema.point(CFrame.lookAt(at(-2, 3.6, -25.5), at(-8, 3.8, -21.1)), 46)",
    "local eye = at(-13, 6, -8):Lerp(at(-12, 6, -12), push)",
    "Cinema.point(CFrame.lookAt(eye, at(-4, 9, -34)), 70)",
    "Cinema.point(CFrame.lookAt(face * Vector3.new(0, 0, 7), face.Position), 42, true)",
    "local eye = at(-8, 5.5, -12):Lerp(at(-3, 8, -30), u)",
    "Cinema.point(CFrame.lookAt(eye, at(0, 12, -95)), 60 - 5 * u)",
)


def ease(u):
    u = min(1.0, max(0.0, u))
    return u * u * (3 - 2 * u)


# ----- the flume -----

def helix(t):
    a = t * TURNS * math.pi * 2
    return v(math.cos(a) * R, -DROP * t, -math.sin(a) * R)


def slide_point(f):
    if f <= HELIX:
        return helix(f / HELIX)
    g = (f - HELIX) / (1 - HELIX)
    out = helix(1)
    return v(out[0], out[1] - PLUNGE * g * g, out[2])


def path_frame(f):
    """The path's frame at f: where, the way along (LookVector), and up (banked into the turn in the tube)."""
    f = min(1.0, max(0.0, f))
    here = slide_point(f)
    a, b = max(0.0, f - 0.002), min(1.0, f + 0.002)
    look = unit(slide_point(b) - slide_point(a))
    if f <= HELIX:
        inward = flat(-here)
        up = unit(v(0, 1, 0) * math.cos(BANK) + inward * math.sin(BANK))
    else:
        up = v(0, 1, 0)
    return here, look, up


def rider_flume(f):
    """Lying back in the trough, feet first: the root a little sunk, the head uphill and the feet downhill."""
    here, look, up = path_frame(min(f, HELIX - 0.001) if f <= HELIX else f)
    if f > HELIX:
        look = path_frame(HELIX - 0.005)[1]
    root = here - up * 0.6
    return root, {"head": root - look * 2.1 + up * 0.7, "feet": root + look * 2.6}


def flume(fps=60):
    frames = []
    state = {}
    steps = int(SECONDS * fps)
    for i in range(steps):
        t = i / fps
        f = t / SECONDS
        root, body = rider_flume(f)
        here = root
        look = path_frame(min(f, HELIX - 0.005))[1]
        fl = flat(look)
        up = v(0, 1, 0)
        out = flat(here)
        if f < 0.09:
            frames.append(Frame(t, "over the shoulder", here - fl * 10 + up * 5, here + fl * 10 - up * 3, 62, subject=body))
        elif f < 0.34:
            b_here, _, b_up = path_frame(f - 0.045)
            eye = b_here + b_up * 4.2 + v(0, 1.5, 0)
            frames.append(Frame(t, "chasing", eye, here + look * 6 + up * 0.8, 70, subject=body))
        elif f < 0.5:
            if "wall" not in state:
                ahead = turn_y(out, 0.9)
                state["wall"] = v(0, here[1] - 10, 0) + ahead * 55
            frames.append(Frame(t, "from the wall", state["wall"], here + v(0, 1, 0), 46, subject=body))
        elif f < 0.64:
            a_here, _, a_up = path_frame(min(HELIX - 0.005, f + 0.04))
            eye = a_here + a_up * 3 + v(0, 1, 0)
            frames.append(Frame(t, "from ahead", eye, here + v(0, 1, 0), 64, subject=body))
        elif f < 0.8:
            if "below" not in state:
                end_at, end_run, _ = path_frame(HELIX - 0.005)
                er = flat(end_run)
                state["below"] = end_at - up * 34 + v(er[2], 0, -er[0]) * 16 + er * 10
            frames.append(Frame(t, "from below", state["below"], here, 58, subject=body))
        else:
            frames.append(Frame(t, "from above", here + up * 15 + fl * 3, here - up * 12, 74, subject=body))
    return mark_cuts(frames, {"from the wall", "from below"})


# ----- the fall into the mouth -----

def fall_speed(m, v0):
    if m < JAWS["dark"]:
        return v0 - 30 * m
    if m < JAWS["reveal"]:
        a = v0 - 30 * JAWS["dark"]
        return a + (HANG - a) * ease((m - JAWS["dark"]) / (JAWS["reveal"] - JAWS["dark"]))
    if m < JAWS["into"]:
        return HANG
    if m < JAWS["into"] + 0.25:
        return HANG + (45 - HANG) * ease((m - JAWS["into"]) / 0.25)
    return 45 + 35 * (m - JAWS["into"] - 0.25)


def body_up(theta, phi):
    # CFrame.Angles(theta, 0, phi) * (0, 1, 0)
    return v(-math.sin(phi), math.cos(phi) * math.cos(theta), math.cos(phi) * math.sin(theta))


def maw(fps=60, t0=0.0):
    frames = []
    start = slide_point(1)
    v0 = 2 * PLUNGE / ((1 - HELIX) * SECONDS)
    radial = flat(start)
    rest = start - v(0, MAW_DEEP, 0)
    opens = v(0, 1, 0)
    side = v(radial[2], 0, -radial[0])  # Vector3.yAxis:Cross(radial)
    d, tumble = 0.0, 0.0
    last = 0.0
    end = JAWS["crunch"]
    for i in range(int(end * fps)):
        m = i / fps
        s = last
        while s < m:
            h = min(0.01, m - s)
            d += fall_speed(s + h / 2, v0) * h
            s += h
        over = ease((m - JAWS["reveal"] - TURN_AT) / TURN)
        tumble += (m - last) * 0.9 * min(1.2, max(0.12, fall_speed(m, v0) / 45)) * (1 - 0.75 * over)
        last = m
        lunge = 0 if m < JAWS["reveal"] else 1 - (1 - min(1, max(0, (m - JAWS["reveal"]) / LUNGE))) ** 3
        hinge = rest + v(0, MAW_RISE * lunge, 0)
        inward = flat(-hinge)
        pos = start - v(0, d, 0)
        floor = hinge[1] + 8
        if pos[1] < floor:
            pos = v(pos[0], floor, pos[2])
        theta, phi = math.pi / 2 + tumble - math.pi * over, tumble * 0.4
        bu = body_up(theta, phi)
        head = pos + bu * 1.5
        body = {"head": head, "feet": pos - bu * 2.5}
        t = t0 + m
        if m < JAWS["reveal"]:
            frames.append(Frame(t, "maw: falling into black", pos + v(0, 9, 0) + inward * 3 + side * 1.5, pos - v(0, 30, 0), 66,
                                up=side, subject=body))
        elif m < JAWS["face"]:
            k = ease((m - JAWS["reveal"]) / (JAWS["face"] - JAWS["reveal"]))
            eye = pos + v(0, 18 - 1 * k, 0) + inward * (20 - 2 * k) + side * 8
            target = (hinge + opens * 16) * 0.38 + pos * 0.62
            frames.append(Frame(t, "maw: past you into it", eye, target, 74 - 4 * k,
                                subject=dict(body, mouth=hinge + opens * 16)))
        elif m < JAWS["into"]:
            k = ease((m - JAWS["face"]) / (JAWS["into"] - JAWS["face"]))
            crown = flat(bu) if np.linalg.norm(v(bu[0], 0, bu[2])) > 0.1 else inward
            eye = head - v(0, 4.4 - 0.8 * k, 0) + crown * 1.8 + side * 0.8
            frames.append(Frame(t, "maw: your face", eye, head, 54 - 6 * k, up=bu,
                                subject={"head": head + bu * 0.6, "feet": head - bu * 0.7}))
        elif m < JAWS["bite"]:
            eye = hinge + opens * 9 + inward * 5
            frames.append(Frame(t, "maw: from inside it", eye, pos, 82, up=side, subject=body))
        else:
            eye = hinge + opens * 55 + inward * 24 + side * 14
            frames.append(Frame(t, "maw: the bite, wide", eye, hinge + opens * 22, 70,
                                subject=dict(body, mouth=hinge + opens * 22)))
            held = pos
    # DOWN ITS THROAT (the hundred-and-twenty-fourth pass): held where the jaws shut, turning over, from over you.
    begin = JAWS["crunch"] + THROAT_FROM
    for i in range(int(begin * fps), int((MAW_SECONDS - THROAT_SPIT) * fps)):
        m = i / fps
        spin = (m - begin) * 0.9
        across = v(math.cos(spin), 0, -math.sin(spin))
        body = {"head": held + across * 1.6, "feet": held - across * 2.6}
        frames.append(Frame(t0 + m, "maw: down its throat", held + v(0, 9, 0) + side * 2.5, held - v(0, 6, 0), 72, up=side,
                            subject=body))
    return mark_cuts(frames, {f.shot for f in frames}), rest


# ----- the gate chamber -----

def chamber(fps=60, t0=0.0):
    frames = []
    arrive = v(SUMP_Z * 0, -WATER_DOWN - 3, SUMP_Z + 2)
    lad_z = SUMP_Z - SUMP_HALF + 0.45
    surface = v(0, -WATER_DOWN - 1.2, lad_z + 1.3)
    top = v(0, 3, lad_z + 0.6)
    stand_at = v(0, 3, lad_z - 2.4)
    stand = STAND + v(0, 3, 0)
    ahead = v(0, 0, -1)
    face_at = v(G_HALF_W, 15, -12) + v(-0.85, 0, 0)  # the clock face, 0.85 out from the east wall, facing -X
    gates = G_SECONDS
    walk_from = None
    for i in range(int(min(gates + 0.8, 60) * fps)):
        b = i / fps
        t = t0 + b
        if b < 1.2:
            continue
        if b < BEAT["climb"]:
            if b < 1.4:
                pos = arrive + (surface - arrive) * ease(b / 1.4)
            elif b < 3:
                pos = surface + (top - surface) * ease((b - 1.4) / 1.6)
            else:
                pos = top + (stand_at - top) * ease((b - 3) / 0.6)
            body = {"head": pos + v(0, 1.6, 0), "feet": pos - v(0, 3, 0)}
            frames.append(Frame(t, "chamber: up the ladder", v(9, 8, 11), pos + v(0, 1, 0), 58, subject=body))
            continue
        if b < BEAT["room"]:
            u = ease((b - BEAT["climb"]) / (BEAT["room"] - BEAT["climb"]))
            pos = stand_at
            eye = v(14, 17, -30) + (v(9, 14, -24) - v(14, 17, -30)) * u
            frames.append(Frame(t, "chamber: the room", eye, v(-2, 3, 8), 62,
                                subject={"head": pos + v(0, 1.6, 0), "feet": pos - v(0, 3, 0)}))
            continue
        if b < BEAT["walk"]:
            if walk_from is None:
                walk_from = stand_at
            go = stand - walk_from
            dist = np.linalg.norm(go)
            s = min(dist, 9 * (b - BEAT["room"]))
            pos = walk_from + unit(go) * s
            look = flat(go)
            left = v(-look[2], 0, look[0])
            frames.append(Frame(t, "chamber: the walk", pos - look * 10 + v(0, 4.5, 0) + left * 5, pos + look * 8, 62,
                                subject={"head": pos + v(0, 1.6, 0), "feet": pos - v(0, 3, 0)}))
            continue
        pos = stand
        body = {"head": pos + v(0, 1.6, 0), "feet": pos - v(0, 3, 0)}
        if b < BEAT["wheel"]:
            frames.append(Frame(t, "chamber: the key", v(-2, 3.6, -25.5), v(-8, 3.8, -21.1), 46,
                                subject={"head": pos + v(0, 2.2, 0), "feet": v(-8, 2.3, -22.8)}))
        elif b < BEAT["midnight"]:
            push = ease((b - BEAT["wheel"]) / (BEAT["midnight"] - BEAT["wheel"]))
            eye = v(-13, 6, -8) + (v(-12, 6, -12) - v(-13, 6, -8)) * push
            frames.append(Frame(t, "chamber: the wheel and the gate", eye, v(-4, 9, -34), 70,
                                subject={"head": pos + v(0, 2.2, 0), "feet": pos, "gate": v(0, 14.5, -G_HALF_L - 3)}))
        elif b < BEAT["last"]:
            frames.append(Frame(t, "chamber: midnight", face_at + v(-7, 0, 0), face_at, 42, looks_at="away",
                                subject={"clock": face_at}))
        else:
            u = ease((b - BEAT["last"]) / max(1, gates - BEAT["last"]))
            eye = v(-8, 5.5, -12) + (v(-3, 8, -30) - v(-8, 5.5, -12)) * u
            frames.append(Frame(t, "chamber: the last line", eye, v(0, 12, -95), 60 - 5 * u, looks_at="away",
                                subject={"gate": v(0, 12, -60)}))
    return mark_cuts(frames, {"chamber: up the ladder", "chamber: the walk", "chamber: the key",
                              "chamber: the wheel and the gate"})


# ----- what is drawn round them -----

def scenery_flume_and_maw(rest):
    lines = []
    trough = [slide_point(i / 200 * HELIX) for i in range(201)]
    lines.append((trough, "#00838f", 2))
    for side in (-1, 1):
        lip = []
        for i in range(201):
            f = i / 200 * HELIX
            here, look, up = path_frame(f)
            across = unit(np.cross(look, up))
            lip.append(here + across * side * 4 + up * 2.5)
        lines.append((lip, "#80cbc4", 1))
    lines.append(([v(0, 30, 0), v(0, -500, 0)], "#5d4037", 3))  # the mast
    for y in (0, -60, -120, -180, -240, -300, -360):
        h = PIT_HALF
        lines.append(([v(-h, y, -h), v(h, y, -h), v(h, y, h), v(-h, y, h), v(-h, y, -h)], "#90a4ae", 1))
    # the mouth: its rim and teeth, a ring of points round the hinge, opened up
    for lift in (0, MAW_RISE):
        hinge = rest + v(0, lift, 0)
        ring = [hinge + v(math.cos(a) * 26, 30, math.sin(a) * 26) for a in np.linspace(0, 2 * math.pi, 40)]
        lines.append((ring, "#7cb342" if lift else "#c5e1a5", 2 if lift else 1))
    return lines


def scenery_chamber():
    w, l, h = G_HALF_W, G_HALF_L, G_HIGH
    box = []
    for y in (0, h):
        box.append(([v(-w, y, -l), v(w, y, -l), v(w, y, l), v(-w, y, l), v(-w, y, -l)], "#8d6e63", 1))
    for x in (-w, w):
        for z in (-l, l):
            box.append(([v(x, 0, z), v(x, h, z)], "#8d6e63", 1))
    box.append(([v(-12, 0, -l - 1), v(12, 0, -l - 1), v(12, 29, -l - 1), v(-12, 29, -l - 1), v(-12, 0, -l - 1)], "#26a69a", 2))
    s = SUMP_HALF
    box.append(([v(-s, 0, SUMP_Z - s), v(s, 0, SUMP_Z - s), v(s, 0, SUMP_Z + s), v(-s, 0, SUMP_Z + s), v(-s, 0, SUMP_Z - s)], "#1565c0", 2))
    box.append(([v(-8, 0, -24), v(-8, 5.2, -24)], "#ffb300", 3))  # the wheel's post
    return box
