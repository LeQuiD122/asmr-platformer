"""Level 4, the Flooded Halls: the true ending (the hundred-and-fifteenth pass), shot by shot, restated from
FloodedHallsClient (TRUE, MARSH and the shots) and FloodedHallsService (the chamber, where you stand at the wheel, where
Edwin Marsh waits), frame by frame, for check_shots.py.

In the gate chamber's own frame: the floor's top at y = 0, the gates in the wall at -Z, Outfall 3 running on to -Z past
them into the daylight, the sump at +Z. You stand at the wheel facing the gates; he walks up the outfall toward you.
"""
import pathlib
import re

from shots import Frame, mark_cuts, v

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLIENT = (ROOT / "src" / "Client" / "Services" / "FloodedHallsClient.lua").read_text(encoding="utf-8").replace("\r\n", "\n")
SERVER = (ROOT / "src" / "Server" / "Services" / "FloodedHallsService.lua").read_text(encoding="utf-8").replace("\r\n", "\n")


def num(text, pattern):
    found = re.search(pattern, text, re.M)
    if not found:
        raise SystemExit("shots_true.py: no longer found: %s" % pattern)
    return [float(g) for g in found.groups()]


LIGHT, FACE, WAVE, MORNING, DONE = num(
    CLIENT, r"^local TRUE = \{ light = ([\d.]+), face = ([\d.]+), wave = ([\d.]+), morning = ([\d.]+), done = ([\d.]+) \}")
STOP, WALK, BACK = num(CLIENT, r"^local MARSH = \{ stop = (-?[\d.]+), walk = ([\d.]+), back = (-?[\d.]+) \}")
STAND_X, STAND_Z = num(SERVER, r"^\tSTAND = Vector3\.new\((-?[\d.]+), 0, (-?[\d.]+)\),")
MARSH_AT = num(SERVER, r"^\tMARSH_AT = (-?[\d.]+),")[0]
SECONDS, TRUE_MORE = num(SERVER, r"^\tSECONDS = ([\d.]+),\n\tKEY_AT = [\d.]+,\n(?:\t--[^\n]*\n)*\tTRUE = ([\d.]+),")

SHOT_LINES = (
    "Cinema.point(CFrame.lookAt(at(-6, 7, -12), at(0, 4, -60)), 50)",
    "Cinema.point(CFrame.lookAt(at(0, 5.2, MARSH.stop + 7), at(0, 4.7, MARSH.stop)), 38)",
    "Cinema.point(CFrame.lookAt(at(17, 6, -27), at(-4, 3.5, -33)), 52)",
    "Cinema.point(CFrame.lookAt(at(-6.8, 5.3, -17), at(0, 5, -70)), 52)",
)

YOU = v(STAND_X, 3, STAND_Z)  # your root at the wheel, facing the gates
ROOT_UP = 3.05  # his root over his feet (a little taller than you)


def his_z(t):
    span = STOP - MARSH_AT
    if t < FACE:
        u = min(1.0, max(0.0, (t - LIGHT - 0.6) * WALK / max(1.0, span)))
        return MARSH_AT + span * u
    if t < MORNING:
        return STOP
    return max(BACK, STOP - max(0.0, t - MORNING - 0.8) * WALK)


def him(t):
    z = his_z(t)
    return {"marsh": v(0, ROOT_UP + 2.25, z), "marshFeet": v(0, 0.3, z)}


def true_ending(fps=60):
    frames = []
    t = LIGHT
    while t < DONE:
        h = him(t)
        if t < FACE:
            frames.append(Frame(t, "true: someone in the light", v(-6, 7, -12), v(0, 4, -60), 50,
                                subject={"head": h["marsh"], "feet": h["marshFeet"]}))
        elif t < WAVE:
            frames.append(Frame(t, "true: his face", v(0, 5.2, STOP + 7), v(0, 4.7, STOP), 38,
                                subject={"head": h["marsh"], "feet": v(0, ROOT_UP + 0.4, STOP)}))
        elif t < MORNING:
            frames.append(Frame(t, "true: the wave", v(17, 6, -27), v(-4, 3.5, -33), 52,
                                subject=dict(h, head=YOU + v(0, 2.1, 0), feet=YOU - v(0, 3, 0))))
        else:
            # Over your shoulder: your head and shoulders, and him going away into the light until he is gone.
            subject = {"head": YOU + v(0, 2.1, 0), "feet": YOU + v(0, 1.2, 0)}
            if t < DONE - 2.6:
                subject["marsh"] = h["marsh"]
            frames.append(Frame(t, "true: into the morning", v(-6.8, 5.3, -17), v(0, 5, -70), 52, subject=subject))
        t += 1 / fps
    return mark_cuts(frames, {"true: someone in the light", "true: his face", "true: the wave", "true: into the morning"})


def scenery():
    lines = []
    # the gate's opening in the far wall, and Outfall 3 running on to the daylight
    for z in (-38, -41):
        lines.append(([v(-11, 0, z), v(-11, 28, z), v(11, 28, z), v(11, 0, z)], "#78909c", 1))
    for x in (-11, 11):
        lines.append(([v(x, 0, -41), v(x, 0, -101)], "#90a4ae", 1))
        lines.append(([v(x, 28, -41), v(x, 28, -101)], "#90a4ae", 1))
    lines.append(([v(-11, 0, -101), v(-11, 28, -101), v(11, 28, -101), v(11, 0, -101), v(-11, 0, -101)], "#fff59d", 3))
    # the wheel's pedestal
    lines.append(([v(-8, 0, -24), v(-8, 5.2, -24)], "#455a64", 3))
    return lines
