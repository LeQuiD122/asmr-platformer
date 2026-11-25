"""The keyed poses in src/Shared/Poses.lua, read and played the way Poses.play does, on an R15 body.

    python blender/pose_keys.py                      every keyed pose, its numbers
    python blender/pose_keys.py --draw OUT_DIR [name ...]   pictures: front and side, sampled through each pose

Shared by check_feel.py (which holds every keyed pose to a body that does not pass through itself, starts and ends at
rest, and moves at speeds a body moves at) and by whoever is writing a pose and wants to see it before Studio does.

THE BODY is Roblox's R15 at scale 1, near enough to judge a pose by: the root at the hips, the torso two studs wide, arms
hanging from the shoulders a little over two studs long, legs about two. Joint turns are R15's own: CFrame.Angles(x, y, z)
on the joint, in the character's axes (X to its right, Y up, Z behind it; it faces -Z), applied the way an animation's
Transform is (the child turned in the parent's frame about the joint).
"""
import math
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
POSES = ROOT / "src" / "Shared" / "Poses.lua"

# ---------------------------------------------------------------------------------------------------- the body at rest
# (name, parent, the joint's point at rest). The root's parent is the HumanoidRootPart, at the origin.
# R15's own rig attachments at scale 1 (the blocky body): the shoulder pivots at the upper torso's top edges, the upper
# arm hanging from there half a stud out and 0.76 down to the elbow, the forearm 0.76 to the wrist, the hand 0.28 more;
# the hips a stud apart, about a stud to the knee and a stud to the ankle; the ground three studs under the root.
JOINTS = [
    ("Root", None, (0.0, -0.2, 0.0)),
    ("Waist", "Root", (0.0, 0.0, 0.0)),
    ("Neck", "Waist", (0.0, 1.6, 0.0)),
    ("RightShoulder", "Waist", (1.0, 1.36, 0.0)),
    ("RightElbow", "RightShoulder", (1.5, 0.6, 0.0)),
    ("RightWrist", "RightElbow", (1.5, -0.16, 0.0)),
    ("LeftShoulder", "Waist", (-1.0, 1.36, 0.0)),
    ("LeftElbow", "LeftShoulder", (-1.5, 0.6, 0.0)),
    ("LeftWrist", "LeftElbow", (-1.5, -0.16, 0.0)),
    ("RightHip", "Root", (0.5, -0.4, 0.0)),
    ("RightKnee", "RightHip", (0.5, -1.45, 0.0)),
    ("RightAnkle", "RightKnee", (0.5, -2.55, 0.0)),
    ("LeftHip", "Root", (-0.5, -0.4, 0.0)),
    ("LeftKnee", "LeftHip", (-0.5, -1.45, 0.0)),
    ("LeftAnkle", "LeftKnee", (-0.5, -2.55, 0.0)),
]
PARENT = {name: parent for name, parent, _ in JOINTS}
REST = {name: point for name, _, point in JOINTS}
# Points carried by a joint: the hand's tip, the toe, the top of the head.
TIPS = {"RightWrist": ("RightHand", (1.5, -0.44, 0.0)), "LeftWrist": ("LeftHand", (-1.5, -0.44, 0.0)),
        "RightAnkle": ("RightToe", (0.5, -2.95, -0.55)), "LeftAnkle": ("LeftToe", (-0.5, -2.95, -0.55)),
        "Neck": ("HeadTop", (0.0, 2.8, 0.0))}
GROUND = -3.0
# The torso and the head, as boxes in their own part's frame (the upper torso turns with the waist, the lower with the root).
UPPER = ((-1.0, 0.0, -0.5), (1.0, 1.6, 0.5))
LOWER = ((-1.0, -0.4, -0.5), (1.0, 0.0, 0.5))
HEAD = ((-0.6, 1.6, -0.6), (0.6, 2.8, 0.6))


def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mat_vec(a, v):
    return tuple(sum(a[i][k] * v[k] for k in range(3)) for i in range(3))


def angles(x, y, z):
    """CFrame.Angles(x, y, z): Rx * Ry * Rz."""
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    ry = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rz = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    return mat_mul(mat_mul(rx, ry), rz)


IDENTITY = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]

# ---------------------------------------------------------------------------------------------------- reading the poses


def read_keyed(text=None):
    """{name: {"seconds": s, "loop": (a, b) or None, "keys": {joint: [(t, x, y, z, px, py, pz), ...]}}}"""
    text = text if text is not None else POSES.read_text(encoding="utf-8").replace("\r\n", "\n")
    start = text.find("local KEYED: { [string]: Keyed } = {")
    end = text.find("\n}\n", start)
    if start < 0 or end < 0:
        return {}
    block = text[start:end]
    poses = {}
    for match in re.finditer(r"^\t(\w+) = \{ seconds = ([\d.]+)(?:, loop = \{ ([\d.]+), ([\d.]+) \})?, keys = \{\n(.*?)^\t\} \},",
                             block, re.M | re.S):
        keys = {}
        for joint, track in re.findall(r"^\t\t(\w+) = \{ (.*) \},$", match.group(5), re.M):
            frames = []
            for key in re.findall(r"\{ ([^{}]*) \}", track):
                values = [float(v) for v in key.split(",")]
                values += [0.0] * (7 - len(values))
                frames.append(tuple(values))
            keys[joint] = frames
        loop = (float(match.group(3)), float(match.group(4))) if match.group(3) else None
        poses[match.group(1)] = {"seconds": float(match.group(2)), "loop": loop, "keys": keys}
    return poses


def local_time(pose, t):
    loop = pose["loop"]
    if loop and t > loop[1]:
        span = loop[1] - loop[0]
        # Out of the loop for the last of it, so it ends where it ends.
        tail = pose["seconds"] - t
        last = max(k[-1][0] for k in pose["keys"].values())
        if tail <= last - loop[1]:
            return last - tail
        return loop[0] + (t - loop[1]) % span
    return t


def sample(track, t):
    """Poses.play's curve: a cubic through every key, still at the first and last, and still at any key where a value
    turns back (so a joint eases into and out of each turn and never overshoots a key)."""
    n = len(track)
    if t <= track[0][0]:
        return track[0][1:]
    if t >= track[-1][0]:
        return track[-1][1:]
    i = 0
    while i < n - 2 and track[i + 1][0] <= t:
        i += 1
    a, b = track[i], track[i + 1]
    d = b[0] - a[0]
    u = (t - a[0]) / d
    out = []
    for k in range(1, 7):
        def slope(j):
            if j <= 0 or j >= n - 1:
                return 0.0
            before, here, after = track[j - 1][k], track[j][k], track[j + 1][k]
            if (here - before) * (after - here) <= 0:
                return 0.0
            return (after - before) / (track[j + 1][0] - track[j - 1][0])
        ma, mb = slope(i) * d, slope(i + 1) * d
        h00, h10, h01, h11 = 2 * u ** 3 - 3 * u ** 2 + 1, u ** 3 - 2 * u ** 2 + u, -2 * u ** 3 + 3 * u ** 2, u ** 3 - u ** 2
        out.append(h00 * a[k] + h10 * ma + h01 * b[k] + h11 * mb)
    return tuple(out)


def weight(t, seconds):
    return max(0.0, min(1.0, min(t / 0.3, (seconds - t) / 0.4)))


def turns(pose, t):
    """{joint: (x, y, z, px, py, pz)} at `t`, as Poses.play gives them. A keyed pose eases in and out of rest by its own
    first and last keys, so it is never scaled by Poses.weight (a spin scaled down would turn back the way it came)."""
    lt = local_time(pose, t)
    return {joint: sample(track, lt) for joint, track in pose["keys"].items()}


def body(turned):
    """World points of every joint and tip, and the rotation of each, for a set of turns."""
    rot, pos = {}, {}
    for name, parent, rest in JOINTS:
        x, y, z, px, py, pz = turned.get(name, (0, 0, 0, 0, 0, 0))
        local = angles(x, y, z)
        if parent is None:
            rot[name] = local
            pos[name] = (rest[0] + px, rest[1] + py, rest[2] + pz)
        else:
            prot = rot[parent]
            offset = tuple(rest[i] - REST[parent][i] for i in range(3))
            moved = mat_vec(prot, offset)
            pos[name] = tuple(pos[parent][i] + moved[i] for i in range(3))
            rot[name] = mat_mul(prot, local)
    points = dict(pos)
    for joint, (tip, rest) in TIPS.items():
        offset = tuple(rest[i] - REST[joint][i] for i in range(3))
        moved = mat_vec(rot[joint], offset)
        points[tip] = tuple(pos[joint][i] + moved[i] for i in range(3))
    return points, rot, pos


def inside(point, box, rot, pivot, rest_pivot, margin):
    """Whether a world point is inside a part's box, the part turned by `rot` about its joint."""
    rel = tuple(point[i] - pivot[i] for i in range(3))
    # Into the part's frame: the inverse (transpose) of its rotation.
    local = tuple(sum(rot[k][i] * rel[k] for k in range(3)) for i in range(3))
    local = tuple(local[i] + rest_pivot[i] for i in range(3))
    lo, hi = box
    return all(lo[i] + margin < local[i] < hi[i] - margin for i in range(3))


def collisions(turned, margin=0.12):
    """The hands, elbows, knees and toes that pass into the torso or the head."""
    points, rot, pos = body(turned)
    found = []
    for name in ("RightHand", "LeftHand", "RightWrist", "LeftWrist", "RightElbow", "LeftElbow"):
        for label, box, joint in (("upper torso", UPPER, "Waist"), ("lower torso", LOWER, "Root"), ("head", HEAD, "Neck")):
            if inside(points[name], box, rot[joint], pos[joint], REST[joint], margin):
                found.append("%s in the %s" % (name, label))
    return found


def speeds(pose, step=1 / 30):
    """The fastest any joint turns (radians a second), and where."""
    fastest, at, joint_at = 0.0, 0.0, ""
    t = 0.0
    while t + step <= pose["seconds"]:
        a, b = turns(pose, t), turns(pose, t + step)
        for joint in a:
            change = max(abs(b[joint][k] - a[joint][k]) for k in range(3)) / step
            if change > fastest:
                fastest, at, joint_at = change, t, joint
        t += step
    return fastest, at, joint_at


# ---------------------------------------------------------------------------------------------------- pictures


def draw(pose_name, pose, out_dir, frames=8):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    bones = [("Root", "Waist"), ("Waist", "Neck"), ("Neck", "HeadTop"), ("Waist", "RightShoulder"),
             ("RightShoulder", "RightElbow"), ("RightElbow", "RightWrist"), ("RightWrist", "RightHand"),
             ("Waist", "LeftShoulder"), ("LeftShoulder", "LeftElbow"), ("LeftElbow", "LeftWrist"),
             ("LeftWrist", "LeftHand"), ("Root", "RightHip"), ("RightHip", "RightKnee"), ("RightKnee", "RightAnkle"),
             ("RightAnkle", "RightToe"), ("Root", "LeftHip"), ("LeftHip", "LeftKnee"), ("LeftKnee", "LeftAnkle"),
             ("LeftAnkle", "LeftToe")]
    fig, axes = plt.subplots(2, frames, figsize=(2.1 * frames, 5.2))
    for column in range(frames):
        t = pose["seconds"] * column / (frames - 1) * 0.98 + 0.01
        turned = turns(pose, t)
        points, rot, pos = body(turned)
        hits = collisions(turned)
        for row, (h, label) in enumerate(((0, "front"), (2, "side"))):
            ax = axes[row][column]
            for a, b in bones:
                pa, pb = points[a], points[b]
                colour = "#c0392b" if a.startswith("Right") or b.startswith("Right") else (
                    "#2c6fbb" if a.startswith("Left") or b.startswith("Left") else "#333333")
                if h == 0:
                    ax.plot([-pa[0], -pb[0]], [pa[1], pb[1]], color=colour, linewidth=3)
                else:
                    ax.plot([pa[2], pb[2]], [pa[1], pb[1]], color=colour, linewidth=3)
            head = points["Neck"]
            top = points["HeadTop"]
            centre = tuple((head[i] + top[i]) / 2 for i in range(3))
            circle = plt.Circle((-centre[0] if h == 0 else centre[2], centre[1]), 0.55, fill=False, color="#333333")
            ax.add_patch(circle)
            ax.axhline(GROUND, color="#999999", linewidth=1)
            ax.set_xlim(-3, 3)
            ax.set_ylim(-3.4, 3.4)
            ax.set_aspect("equal")
            ax.set_xticks([])
            ax.set_yticks([])
            title = "%s %.1fs" % (label, t)
            if hits and row == 0:
                title += " !"
            ax.set_title(title, fontsize=8, color="#c0392b" if hits else "#333333")
    fig.suptitle(pose_name, fontsize=11)
    fig.tight_layout()
    path = pathlib.Path(out_dir) / ("pose_%s.png" % pose_name)
    fig.savefig(path, dpi=70)
    plt.close(fig)
    return path


def main():
    poses = read_keyed()
    args = sys.argv[1:]
    if args and args[0] == "--draw":
        out_dir = args[1]
        names = args[2:] or sorted(poses)
        for name in names:
            print(draw(name, poses[name], out_dir))
        return
    for name, pose in sorted(poses.items()):
        fastest, at, joint = speeds(pose)
        worst = []
        t = 0.0
        while t <= pose["seconds"]:
            worst += collisions(turns(pose, t))
            t += 0.1
        print("%-16s %4.1fs  %d joints  fastest %.1f rad/s (%s at %.1fs)%s" % (
            name, pose["seconds"], len(pose["keys"]), fastest, joint, at,
            ("  THROUGH ITSELF: " + ", ".join(sorted(set(worst)))) if worst else ""))


if __name__ == "__main__":
    main()
