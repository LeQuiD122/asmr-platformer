"""The camera as Roblox and Cinema have it, for checking the scenes' shots from here.

Every scene in the game is shot by Cinema.point(CFrame.lookAt(eye, target, up), fov): a camera that is put at the
eye at once and AIMS after its target (eased, AIM_RATE a second; a cut, a jump of more than CUT_STUDS or a turn of
more than CUT_ANGLE snaps it), with a vertical field of view and the letterbox bars over the top and bottom BARS of
the picture. A shot can look exactly where it means to and still lose its subject: under a bar, off the edge while
the aim catches up with something fast, too far to be anything but a speck, or so close it is a nose. This works
each of those out the way the game does, frame by frame at 60 a second, for the scenes check_shots.py restates.

    look_at(eye, target, up)          the camera's axes, as CFrame.lookAt makes them
    project(axes, eye, fov, point)    where a point lands in the picture: x across, y up, -1 to 1, and its depth
    Aim                               Cinema.point's easing and cuts
    Frame / Shot                      what a scene asks of the camera in one frame, and a run of frames
    measure(frames)                   per shot: where the subject is in the picture and how big, all through it
    storyboard(frames, path, title)   a contact sheet of every shot (start, middle, end), drawn as the camera sees it

Numbers that are the game's own (BARS, AIM_RATE, CUT_STUDS, CUT_ANGLE) are read from Cinema.lua, so this cannot
drift from it.
"""
import math
import pathlib
import re
from dataclasses import dataclass, field

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent.parent
CINEMA = (ROOT / "src" / "Client" / "Services" / "Cinema.lua").read_text(encoding="utf-8")


def _cinema(name, pattern=r"([\d.]+)"):
    found = re.search(r"^local %s = %s" % (name, pattern), CINEMA, re.M)
    if not found:
        raise SystemExit("shots.py: Cinema.lua no longer has %s" % name)
    return float(found.group(1))


BARS = _cinema("BARS")
AIM_RATE = _cinema("AIM_RATE")
CUT_STUDS = _cinema("CUT_STUDS")
CUT_ANGLE = math.radians(_cinema("CUT_ANGLE", r"math\.rad\(([\d.]+)\)"))
ASPECT = 16 / 9
FPS = 60
VISIBLE_Y = 1 - 2 * BARS  # the half-height of the picture not under a bar, in the -1..1 units of the whole


def v(x, y=None, z=None):
    if y is None:
        return np.asarray(x, dtype=float)
    return np.array([x, y, z], dtype=float)


def unit(a):
    a = np.asarray(a, dtype=float)
    n = np.linalg.norm(a)
    return a / n if n > 1e-9 else a


def flat(a):
    a = np.asarray(a, dtype=float)
    return unit(v(a[0], 0, a[2]))


def turn_y(a, angle):
    """CFrame.Angles(0, angle, 0) * a: Roblox turns +X toward -Z for a positive angle."""
    c, s = math.cos(angle), math.sin(angle)
    return v(c * a[0] + s * a[2], a[1], -s * a[0] + c * a[2])


def look_at(eye, target, up=(0, 1, 0)):
    """Rows: right, up, forward (the LookVector), as CFrame.lookAt builds them."""
    forward = unit(v(target) - v(eye))
    up = v(up)
    right = np.cross(forward, up)
    if np.linalg.norm(right) < 1e-6:  # looking along the up vector: Roblox falls back on another axis
        right = np.cross(forward, v(0, 0, 1) if abs(forward[2]) < 0.9 else v(1, 0, 0))
    right = unit(right)
    true_up = unit(np.cross(right, forward))
    return np.array([right, true_up, forward])


def project(axes, eye, fov, point):
    """(x, y, depth): x and y from -1 to 1 across the whole picture (bars included), depth along the look."""
    d = v(point) - v(eye)
    x, y, z = float(d @ axes[0]), float(d @ axes[1]), float(d @ axes[2])
    if z <= 1e-4:
        return None
    t = math.tan(math.radians(fov) / 2)
    return x / (z * t * ASPECT), y / (z * t), z


def in_picture(p, margin=0.0):
    """Inside the picture and not under a bar."""
    return p is not None and abs(p[0]) <= 1 - margin and abs(p[1]) <= VISIBLE_Y - margin


# ----- Cinema.point's aim -----

def _quat(m):
    # rotation matrix (columns right, up, back as Roblox has them) to quaternion; we keep rows, so transpose
    r = np.array([m[0], m[1], -m[2]]).T
    tr = r[0, 0] + r[1, 1] + r[2, 2]
    if tr > 0:
        s = math.sqrt(tr + 1) * 2
        q = np.array([0.25 * s, (r[2, 1] - r[1, 2]) / s, (r[0, 2] - r[2, 0]) / s, (r[1, 0] - r[0, 1]) / s])
    elif r[0, 0] > r[1, 1] and r[0, 0] > r[2, 2]:
        s = math.sqrt(1 + r[0, 0] - r[1, 1] - r[2, 2]) * 2
        q = np.array([(r[2, 1] - r[1, 2]) / s, 0.25 * s, (r[0, 1] + r[1, 0]) / s, (r[0, 2] + r[2, 0]) / s])
    elif r[1, 1] > r[2, 2]:
        s = math.sqrt(1 + r[1, 1] - r[0, 0] - r[2, 2]) * 2
        q = np.array([(r[0, 2] - r[2, 0]) / s, (r[0, 1] + r[1, 0]) / s, 0.25 * s, (r[1, 2] + r[2, 1]) / s])
    else:
        s = math.sqrt(1 + r[2, 2] - r[0, 0] - r[1, 1]) * 2
        q = np.array([(r[1, 0] - r[0, 1]) / s, (r[0, 2] + r[2, 0]) / s, (r[1, 2] + r[2, 1]) / s, 0.25 * s])
    return q / np.linalg.norm(q)


def _matrix(q):
    w, x, y, z = q
    r = np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    right, up, back = r[:, 0], r[:, 1], r[:, 2]
    return np.array([right, up, -back])


def _slerp(a, b, t):
    dot = float(a @ b)
    if dot < 0:
        b, dot = -b, -dot
    if dot > 0.9995:
        q = a + (b - a) * t
        return q / np.linalg.norm(q)
    theta = math.acos(dot)
    return (math.sin((1 - t) * theta) * a + math.sin(t * theta) * b) / math.sin(theta)


class Aim:
    """Cinema.point: the eye is put where asked; the aim eases after what it is asked to look at, unless cut."""

    def __init__(self):
        self.q = None
        self.eye = None

    def step(self, eye, wanted, dt, cut):
        wq = _quat(wanted)
        jump = self.eye is not None and np.linalg.norm(v(eye) - self.eye) > CUT_STUDS
        if self.q is not None:
            have = _matrix(self.q)[2]
            turned = math.acos(max(-1.0, min(1.0, float(have @ wanted[2])))) > CUT_ANGLE
        else:
            turned = True
        if cut or self.q is None or jump or turned:
            self.q = wq
        else:
            self.q = _slerp(self.q, wq, 1 - math.exp(-AIM_RATE * dt))
        self.eye = v(eye)
        return _matrix(self.q)


# ----- a scene, frame by frame -----

@dataclass
class Frame:
    t: float
    shot: str
    eye: np.ndarray
    target: np.ndarray
    fov: float
    up: np.ndarray = field(default_factory=lambda: v(0, 1, 0))
    cut: bool = False
    subject: dict = field(default_factory=dict)  # name -> point (head, feet, ...): what the shot is OF
    looks_at: str = "subject"  # "subject", or "away" for a shot that is meant to be of something else


@dataclass
class ShotReport:
    name: str
    start: float
    end: float
    worst_x: float = 0.0  # furthest the subject strays across (|x|, 1 is the edge)
    worst_y: float = 0.0  # furthest up or down (|y|; VISIBLE_Y is the edge of a bar)
    min_size: float = 9.0  # the subject's height, as a share of the picture between the bars
    max_size: float = 0.0
    lost: int = 0  # frames the subject is out of the picture or under a bar
    frames: int = 0
    min_depth: float = 1e9
    looks_at: str = "subject"

    @property
    def length(self):
        return self.end - self.start


def mark_cuts(frames, cutting):
    """Cinema.cut() where the code calls it: the first frame of each shot named in `cutting` (and the very first
    frame, since Cinema.begin starts on a cut). Any other change of shot is a pan from where the last one looked,
    unless the eye jumps or the aim turns far enough for Cinema to take it as a cut anyway."""
    last = None
    for k, f in enumerate(frames):
        if k == 0 or (f.shot != last and f.shot in cutting):
            f.cut = True
        last = f.shot
    return frames


def run(frames):
    """Cinema.point over the frames: the aim each frame actually has."""
    aim = Aim()
    out = []
    last = None
    for f in frames:
        dt = 1 / FPS if last is None else max(1e-4, f.t - last)
        last = f.t
        wanted = look_at(f.eye, f.target, f.up)
        out.append((f, aim.step(f.eye, wanted, dt, f.cut)))
    return out


def measure(frames):
    """Each shot in turn: where its subject goes in the picture and how big it is, frame by frame, as aimed."""
    reports = []
    current = None
    for f, axes in run(frames):
        if current is None or current.name != f.shot or f.cut and current.frames > 0 and f.shot != current.name:
            current = ShotReport(f.shot, f.t, f.t, looks_at=f.looks_at)
            reports.append(current)
        current.end = f.t
        current.frames += 1
        if f.looks_at != "subject":
            continue  # a shot that has turned to look at something else: you may leave it now
        pts = {k: project(axes, f.eye, f.fov, p) for k, p in f.subject.items()}
        seen = [p for p in pts.values() if p is not None]
        if not seen or any(not in_picture(p) for p in seen):
            current.lost += 1
        for p in seen:
            current.worst_x = max(current.worst_x, abs(p[0]))
            current.worst_y = max(current.worst_y, abs(p[1]))
            current.min_depth = min(current.min_depth, p[2])
        head, feet = f.subject.get("head"), f.subject.get("feet")
        if head is not None and feet is not None:
            # HOW BIG THEY LOOK, whichever way they lie: their length, at the depth of their middle, as a share of the
            # picture's height between the bars (a rider lying along the look would otherwise measure as nothing).
            middle = (v(head) + v(feet)) / 2
            depth = float((middle - v(f.eye)) @ axes[2])
            if depth > 1e-3:
                length = float(np.linalg.norm(v(head) - v(feet)))
                size = length / (depth * 2 * math.tan(math.radians(f.fov) / 2) * VISIBLE_Y)
                current.min_size = min(current.min_size, size)
                current.max_size = max(current.max_size, size)
    return reports


# ----- the storyboard -----

def storyboard(frames, scenery, path, title, per_shot=3):
    """Every shot at its start, middle and end, as the camera (with its aim's lag) sees it: the bars, the subject
    as a figure (head and feet), and the scenery as lines. `scenery` is a list of (points, colour, width)."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    aimed = run(frames)
    shots = []
    for f, axes in aimed:
        if not shots or shots[-1][0] != f.shot:
            shots.append((f.shot, []))
        shots[-1][1].append((f, axes))
    picks = []
    for name, run_ in shots:
        n = len(run_)
        idx = sorted({0, n // 2, n - 1}) if per_shot >= 3 else [n // 2]
        for i in idx:
            picks.append(run_[i])
    cols = 3
    rows = math.ceil(len(picks) / cols)
    fig, grid = plt.subplots(rows, cols, figsize=(cols * 4.8, rows * 2.9), squeeze=False)
    for k, (f, axes) in enumerate(picks):
        ax = grid[k // cols][k % cols]
        ax.set_xlim(-1, 1)
        ax.set_ylim(-1, 1)
        ax.set_aspect(1 / ASPECT * 1.0)
        ax.set_facecolor("#cfd8dc")
        ax.set_xticks([])
        ax.set_yticks([])
        for points, colour, width in scenery:
            xs, ys = [], []
            for p in points:
                q = project(axes, f.eye, f.fov, p)
                if q is None or abs(q[0]) > 4 or abs(q[1]) > 4:
                    if len(xs) > 1:
                        ax.plot(xs, ys, color=colour, lw=width)
                    xs, ys = [], []
                    continue
                xs.append(q[0])
                ys.append(q[1])
            if len(xs) > 1:
                ax.plot(xs, ys, color=colour, lw=width)
        head, feet = f.subject.get("head"), f.subject.get("feet")
        ph = project(axes, f.eye, f.fov, head) if head is not None else None
        pf = project(axes, f.eye, f.fov, feet) if feet is not None else None
        if ph and pf:
            ax.plot([ph[0], pf[0]], [ph[1], pf[1]], color="#d84315", lw=3)
            ax.plot([ph[0]], [ph[1]], "o", color="#d84315", ms=6)
        elif ph:
            ax.plot([ph[0]], [ph[1]], "o", color="#d84315", ms=6)
        for extra, p in f.subject.items():
            if extra in ("head", "feet"):
                continue
            q = project(axes, f.eye, f.fov, p)
            if q:
                ax.plot([q[0]], [q[1]], "x", color="#6a1b9a", ms=7)
        ax.axhspan(VISIBLE_Y, 1, color="black")
        ax.axhspan(-1, -VISIBLE_Y, color="black")
        ax.text(-0.97, 0.83, "%s  t=%.2f  fov %d" % (f.shot, f.t, f.fov), color="white", fontsize=8, va="center")
    for k in range(len(picks), rows * cols):
        grid[k // cols][k % cols].axis("off")
    fig.suptitle(title, fontsize=12)
    fig.tight_layout()
    fig.savefig(path, dpi=70)
    plt.close(fig)
    return path
