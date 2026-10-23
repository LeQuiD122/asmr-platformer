"""Level 5, Hill House: taking his key in the hall, shot by shot, restated from HillHouseClient (the shots) and
HillHouseService (where the hall's things are), frame by frame, for check_shots.py.

In the house's own frame: the middle of its ground floor at the origin, -Z the front (the door and the key's hook on
the front wall), +X the right-hand wall with his clock against it.
"""
import pathlib
import re

from shots import Frame, mark_cuts, v

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLIENT = (ROOT / "src" / "Client" / "Services" / "HillHouseClient.lua").read_text(encoding="utf-8").replace("\r\n", "\n")
SERVER = (ROOT / "src" / "Server" / "Services" / "HillHouseService.lua").read_text(encoding="utf-8").replace("\r\n", "\n")


def num(text, pattern):
    found = re.search(pattern, text, re.M)
    if not found:
        raise SystemExit("shots_hill.py: no longer found: %s" % pattern)
    return [float(g) for g in found.groups()]


W, D = num(SERVER, r"^local HOUSE_W, HOUSE_D, STOREY, ROOF_H = ([\d.]+), ([\d.]+),")
HOOK_X, HOOK_Y, _ = num(SERVER, r"^local KEY_HOOK = Vector3\.new\(([\d.]+), ([\d.]+), ([\d.]+)\)")
STAND = num(SERVER, r"^local KEY_STAND = ([\d.]+)")[0]
FLOOR = num(SERVER, r"^\tlocal floorY = ([\d.]+)\n\tlocal inner = -D / 2 \+ 1")[0]
CLOCK_IN, CLOCK_Z = num(SERVER, r"local clock = centre \* CFrame\.new\(W / 2 - 1 - ([\d.]+), floorY, (-?[\d.]+)\)")
FACE_UP, FACE_OUT = num(SERVER, r"local face = clock \* CFrame\.new\(0, ([\d.]+), -([\d.]+)\)")
PIVOT_UP, PIVOT_OUT = num(SERVER, r"local pivot = clock \* CFrame\.new\(0, ([\d.]+), -([\d.]+)\)")
BOB_DOWN = num(SERVER, r"pivot \* CFrame\.new\(0, -([\d.]+), 0\) \* CFrame\.Angles\(0, math\.pi / 2, 0\)")[0]
BACK_X, BACK_UP, BACK_IN = num(SERVER, r"back = \(centre \* CFrame\.new\((-?[\d.]+), floorY \+ ([\d.]+), D / 2 - ([\d.]+)\)\)")
KEY_SHOT, CLOCK_SHOT, WAY_SHOT = num(CLIENT, r"^local KEY_SHOT, CLOCK_SHOT, WAY_SHOT = ([\d.]+), ([\d.]+), ([\d.]+)")
WAY_WALK = num(CLIENT, r"^local WAY_WALK = ([\d.]+)")[0]
DOOR_X, DOOR_UP, DOOR_IN = num(SERVER, r"door = \(centre \* CFrame\.new\((-?[\d.]+), floorY \+ ([\d.]+), inner \+ ([\d.]+)\)\)\.Position")

SHOT_LINES = (
    "local head = spot.Position + Vector3.new(0, 1.6, 0)",
    "local eye = head + side * 3 + facing * 1.5 + Vector3.new(0, -0.5, 0)",
    "Cinema.point(CFrame.lookAt(eye, keyAt:Lerp(head, 0.5)), 56)",
    "local toClock = Vector3.new(face.X - spot.Position.X, 0, face.Z - spot.Position.Z).Unit",
    "local right = toClock:Cross(Vector3.yAxis)",
    "local eye = head - toClock * (3 - 0.6 * k) + right * 1 + Vector3.new(0, 0.5, 0)",
    "Cinema.point(CFrame.lookAt(eye, face + Vector3.new(0, -1.6, 0)), 50)",
    "Cinema.point(CFrame.lookAt(back, here + Vector3.new(0, 0.4, 0)), 50)",
)

INNER = -D / 2 + 1
SPOT = v(HOOK_X, FLOOR + 3, INNER + STAND)  # where you stand, facing the hook (-Z)
FACING, SIDE = v(0, 0, -1), v(1, 0, 0)
HEAD = SPOT + v(0, 1.6, 0)
KEY = v(HOOK_X, FLOOR + HOOK_Y - 2.3, INNER + 0.15 + 0.45)  # the key's shank, as the server hangs it
CLOCK = v(W / 2 - 1 - CLOCK_IN, FLOOR, CLOCK_Z)
OUT = v(-1, 0, 0)  # the clock faces into the hall
FACE = CLOCK + v(0, FACE_UP, 0) + OUT * FACE_OUT
BOB = CLOCK + v(0, PIVOT_UP - BOB_DOWN, 0) + OUT * PIVOT_OUT
BACK = v(BACK_X, FLOOR + BACK_UP, D / 2 - BACK_IN)
DOOR = v(DOOR_X, FLOOR + DOOR_UP, INNER + DOOR_IN)  # just inside the open door, where you go with the key


def walking(t):
    """Where you are, `t` seconds into the way out: from the hook to the door at WAY_WALK, then there."""
    gap = DOOR - SPOT
    u = min(1.0, t * WAY_WALK / max(0.01, float((gap @ gap) ** 0.5)))
    return SPOT + gap * u


def lerp(a, b, u):
    return a + (b - a) * u


def hall(fps=60):
    frames = []
    total = KEY_SHOT + CLOCK_SHOT + WAY_SHOT
    for i in range(int(total * fps)):
        t = i / fps
        if t < KEY_SHOT:
            # a close shot, in front of you and to one side: judged by the head and shoulders, as the drain's grab is
            frames.append(Frame(t, "key: taking it", HEAD + SIDE * 3 + FACING * 1.5 + v(0, -0.5, 0), lerp(KEY, HEAD, 0.5), 56,
                                subject={"head": SPOT + v(0, 2.1, 0), "feet": SPOT + v(0, 0.3, 0), "key": KEY}))
        elif t < KEY_SHOT + CLOCK_SHOT:
            # over your shoulder at the clock: you, its face and its pendulum's bob all in the picture as it starts
            to_clock = FACE - SPOT
            to_clock = v(to_clock[0], 0, to_clock[2])
            to_clock = to_clock / float((to_clock @ to_clock) ** 0.5)
            right = v(-to_clock[2], 0, to_clock[0])
            k = min(1.0, max(0.0, (t - KEY_SHOT) / CLOCK_SHOT))
            frames.append(Frame(t, "key: his clock", HEAD - to_clock * (3 - 0.6 * k) + right + v(0, 0.5, 0), FACE + v(0, -1.6, 0),
                                50, subject={"you": SPOT + v(0, 2.1, 0), "face": FACE, "bob": BOB}))
        else:
            here = walking(t - KEY_SHOT - CLOCK_SHOT)
            frames.append(Frame(t, "key: the way out", BACK, here + v(0, 0.4, 0), 50,
                                subject={"head": here + v(0, 2.1, 0), "feet": here - v(0, 3, 0)}))
    return mark_cuts(frames, {"key: his clock", "key: the way out"})


def scenery():
    lines = []
    hw, hd = W / 2 - 1, D / 2 - 1
    for y in (FLOOR, FLOOR + 10):
        lines.append(([v(-hw, y, -hd), v(hw, y, -hd), v(hw, y, hd), v(-hw, y, hd), v(-hw, y, -hd)], "#8d6e63", 1))
    for x in (-hw, hw):
        for z in (-hd, hd):
            lines.append(([v(x, FLOOR, z), v(x, FLOOR + 10, z)], "#8d6e63", 1))
    # the door in the front wall, open
    lines.append(([v(-1.6, FLOOR, -hd), v(-1.6, FLOOR + 7, -hd), v(1.6, FLOOR + 7, -hd), v(1.6, FLOOR, -hd)], "#2e7d32", 2))
    # the clock: its case, and its face
    c = CLOCK
    lines.append(([c + v(-0.6, 0, -1.2), c + v(-0.6, 7.6, -1.2), c + v(-0.6, 7.6, 1.2), c + v(-0.6, 0, 1.2), c + v(-0.6, 0, -1.2)],
                  "#5d4037", 2))
    lines.append(([FACE + v(0, -0.9, -0.9), FACE + v(0, 0.9, -0.9), FACE + v(0, 0.9, 0.9), FACE + v(0, -0.9, 0.9),
                   FACE + v(0, -0.9, -0.9)], "#fff8e1", 2))
    # the key on its hook
    lines.append(([v(HOOK_X, FLOOR + HOOK_Y, INNER + 0.4), KEY], "#43a047", 2))
    return lines
