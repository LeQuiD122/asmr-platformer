"""Level 4, the Flooded Halls: clocking in at the time clock by Mr Barlow on the gangway, shot by shot, restated from
FloodedHallsClient (the shots) and StoryService (where the clock, where you stand, where he stands), frame by frame,
for check_shots.py.

In the clock's own frame: its foot on the deck at the origin, its face to -Z (the way people come along the deck), you
standing in front of it facing it, Mr Barlow to its right and a little behind it.
"""
import pathlib
import re

from shots import Frame, mark_cuts, v

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLIENT = (ROOT / "src" / "Client" / "Services" / "FloodedHallsClient.lua").read_text(encoding="utf-8").replace("\r\n", "\n")
STORY = (ROOT / "src" / "Server" / "Services" / "StoryService.lua").read_text(encoding="utf-8").replace("\r\n", "\n")


def num(text, pattern):
    found = re.search(pattern, text, re.M)
    if not found:
        raise SystemExit("shots_clock.py: no longer found: %s" % pattern)
    return [float(g) for g in found.groups()]


# Where the clock is from him (so where he is from it), and where you stand at it.
OFF_X, OFF_Z = num(STORY, r"local at = spot \* CFrame\.new\((-?[\d.]+), 0, (-?[\d.]+)\)")
STAND_Y, STAND_Z = num(STORY, r"local stand = at \* CFrame\.new\(0, ([\d.]+), (-?[\d.]+)\) \* CFrame\.Angles\(0, math\.pi, 0\)")
CARD, SHIFT = num(CLIENT, r"^local CLOCK = \{ card = ([\d.]+), shift = ([\d.]+),")

SHOT_LINES = (
    "Cinema.point(CFrame.lookAt(at * Vector3.new(1.4, 5, -5), at * Vector3.new(0.3, 4, -1)), 48)",
    "Cinema.point(CFrame.lookAt(at * Vector3.new(9, 5, -7), at * Vector3.new(1, 2.8, 0)), 55)",
)

STAND = v(0, STAND_Y, STAND_Z)  # your root, facing the clock (+Z)
BARLOW = v(-OFF_X, 0, -OFF_Z)  # his feet: the clock is OFF from him, so he is -OFF from it (same facing)
SLOT = v(0, 3.95, -0.56)
CLOSE = {"head": STAND + v(0, 2.1, 0), "feet": STAND + v(0, 0.3, 0)}
TWO = {"head": STAND + v(0, 2.1, 0), "feet": STAND - v(0, 3, 0), "barlow": BARLOW + v(0, 5, 0), "barlowFeet": BARLOW + v(0, 0.5, 0)}


def clock_in(fps=60):
    frames = []
    for i in range(int((CARD + SHIFT) * fps)):
        t = i / fps
        if t < CARD:
            frames.append(Frame(t, "clock: your card", v(1.4, 5, -5), v(0.3, 4, -1), 48, subject=dict(CLOSE, slot=SLOT)))
        else:
            frames.append(Frame(t, "clock: on shift", v(9, 5, -7), v(1, 2.8, 0), 55, subject=TWO))
    return mark_cuts(frames, {"clock: on shift"})


def scenery():
    lines = []
    # the clock: its pillar and body
    for y0, y1, h in ((0.2, 3.2, 0.35), (3.2, 5.4, 0.8)):
        d = 0.55 if h == 0.8 else 0.35
        lines.append(([v(-h, y0, -d), v(h, y0, -d), v(h, y1, -d), v(-h, y1, -d), v(-h, y0, -d)], "#455a64", 2))
    lines.append(([SLOT + v(-0.45, 0, 0), SLOT + v(0.45, 0, 0)], "#000000", 2))
    # the deck's far rail, behind the clock and Mr Barlow
    for z in (-6, 6):
        lines.append(([v(-1.7, 4.2, z), v(-1.7, 4.2, -z)], "#8d6e63", 1))
    # Mr Barlow, as a post
    lines.append(([BARLOW, BARLOW + v(0, 5.2, 0)], "#3949ab", 3))
    return lines
