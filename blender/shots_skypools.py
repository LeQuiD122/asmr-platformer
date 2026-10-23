"""Level 2, the Sky Pools: the slide down through the cloud sea, the skim across the pool and the landing, shot by
shot, restated from SkyPoolsClient (the shots) and SkyPath (the ride), on runs laid by skypools_layout.py (the same
Python check_skypools.py tests), frame by frame, for check_shots.py.
"""
import math
import pathlib
import re

import numpy as np

from shots import Frame, flat, mark_cuts, unit, v
from skypools_layout import BASE_SURFACE_Y, RUNS, S, heights, kill_y, lay, slide_point, slide_spec

ROOT = pathlib.Path(__file__).resolve().parent.parent
CLIENT = (ROOT / "src" / "Client" / "Services" / "SkyPoolsClient.lua").read_text(encoding="utf-8").replace("\r\n", "\n")
SKYPATH = (ROOT / "src" / "Shared" / "SkyPath.lua").read_text(encoding="utf-8").replace("\r\n", "\n")


def num(text, pattern):
    found = re.search(pattern, text, re.M)
    if not found:
        raise SystemExit("shots_skypools.py: no longer found: %s" % pattern)
    return [float(g) for g in found.groups()]


SPEED, MIN_S, MAX_S, RAMP = num(SKYPATH, r"^SkyPath\.SPEED = ([\d.]+)\n^SkyPath\.MIN_SECONDS, SkyPath\.MAX_SECONDS = ([\d.]+), ([\d.]+)\n^SkyPath\.RAMP = ([\d.]+)")
SIT = num(SKYPATH, r"^SkyPath\.SIT_HEIGHT = ([\d.]+)")[0]
SKIM = num(SKYPATH, r"^SkyPath\.SKIM_SECONDS = ([\d.]+)")[0]
HOPS = [tuple(float(x) for x in h) for h in re.findall(r"\{ ([\d.]+), ([\d.]+), ([\d.]+) \}", SKYPATH[SKYPATH.find("SkyPath.HOPS = {"):SKYPATH.find("SkyPath.HOPS = {") + 120])]
PLUNGE_HOLD, BURST_LEAD, BURST_HOLD = num(CLIENT, r"^local PLUNGE_HOLD = ([\d.]+).*\n^local BURST_LEAD = ([\d.]+).*\n^local BURST_HOLD = ([\d.]+)")
OVER_TOP, UNDER_BOTTOM = num(CLIENT, r"local plunge = below\(cloudTop \+ ([\d.]+), 0\)\n\tlocal out = below\(cloudBottom - ([\d.]+), plunge\)")
HOLD = num(CLIENT, r"^local HOLD = ([\d.]+)")[0]
BELOW_HOLD, MIST_LEAST = num(CLIENT, r"^local BELOW_HOLD = ([\d.]+).*\n^local MIST_LEAST = ([\d.]+)")

SHOT_LINES = (
    "local eye = Cinema.clear(here - flat * 10 + Vector3.new(0, 5.5, 0), here, ignore)",
    "Cinema.point(CFrame.lookAt(eye, SkyPath.rideFrame(current.spec, current.distances, math.min(1, u + 0.12)).Position), 64)",
    "local eye = here + out * 22 + Vector3.new(0, 10, 0) - flat * 12",
    "Cinema.point(CFrame.lookAt(eye, here:Lerp(far, 0.3) + Vector3.new(0, 1, 0)), 56)",
    "scene.eye = Cinema.clear(here - flat * 14 + out * 9 + Vector3.new(0, 15, 0), here, ignore)",
    "Cinema.point(CFrame.lookAt(scene.eye :: Vector3, here), 60 - math.min(held, PLUNGE_HOLD) * 6)",
    "local eye = Cinema.clear(here - flat * 8 + out * 2.5 + Vector3.new(0, 3.5, 0), here, ignore)",
    "Cinema.point(CFrame.lookAt(eye, here + run * 4 + Vector3.new(0, 1.2, 0)), 66)",
    "local eye = mid + away * (150 - 28 * drift) + Vector3.new(0, 6 + 6 * drift, 0)",
    "Cinema.point(CFrame.lookAt(eye, mid:Lerp(marks.outAt, 0.38)), 66, true)",
    "scene.eye = Cinema.clear(marks.outAt + marks.outRun * 30 + away * 22 + Vector3.new(0, -24, 0), marks.outAt, ignore)",
    "Cinema.point(CFrame.lookAt(scene.eye :: Vector3, marks.outAt + Vector3.new(0, 5, 0)), 60, true)",
    "Cinema.point(CFrame.lookAt(scene.eye :: Vector3, here + Vector3.new(0, 1, 0)), 60, true)",
    "local eye = Cinema.clear(here + run * 14 + Vector3.new(0, 4.5, 0), here, ignore)",
    "Cinema.point(CFrame.lookAt(eye, here + Vector3.new(0, 1.2, 0)), 58)",
    "Cinema.point(CFrame.lookAt(landing + away * 20 + side * 10 + Vector3.new(0, 2.5, 0), here), 58)",
    "local eye = Vector3.new(at.X, landing.Y + 2.2, at.Z) + side * 13 - dir * (4 - s * 2.2)",
    "Cinema.point(CFrame.lookAt(eye, at + Vector3.new(0, 0.5, 0)), 56)",
    "Cinema.point(CFrame.lookAt(landing + away * (14 - 4 * k) + side * 4 + Vector3.new(0, 2.4, 0),\n\t\tlanding + Vector3.new(0, 0.6, 0)), 60)",
)


class Ride:
    """One laid slide: where the sled is at u of the ride (its share of the length, ramped as SkyPath.share)."""

    def __init__(self, count, seed, samples=200):
        radius, chunks, finish_y = lay(count, seed)
        self.cloud_top, self.pool_y, _, _ = heights(BASE_SURFACE_Y, kill_y(chunks))
        self.spec = slide_spec(radius, chunks, finish_y)
        self.ctop = self.cloud_top + 8
        self.cbot = self.cloud_top - S["CLOUD_THICK"] * 1.3
        self.centre = v(self.spec["centre"][0], 0, self.spec["centre"][1])
        self.samples = samples
        self.dist = [0.0]
        for i in range(1, samples + 1):
            self.dist.append(self.dist[-1] + float(np.linalg.norm(self.point(i / samples) - self.point((i - 1) / samples))))
        self.seconds = min(MAX_S, max(MIN_S, self.dist[-1] / SPEED))

    def point(self, f):
        (x, z), y, _ = slide_point(self.spec, f)
        return v(x, y, z)

    def share(self, u):
        norm = 1 - RAMP / 2
        return (u * u / (2 * RAMP)) / norm if u < RAMP else (u - RAMP / 2) / norm

    def at(self, u):
        t = min(1, max(0, self.share(min(1, max(0, u))))) * self.dist[-1]
        lo = 0
        while lo < self.samples - 1 and self.dist[lo + 1] < t:
            lo += 1
        span = self.dist[lo + 1] - self.dist[lo]
        return self.point((lo + ((t - self.dist[lo]) / span if span > 0 else 0)) / self.samples) + v(0, SIT, 0)

    def first_below(self, y, start):
        u = start
        while u < 1:
            if self.at(u)[1] < y:
                return u
            u += 0.002
        return 1

    def run_out(self):
        last, before = self.point(1), self.point(0.985)
        return flat(last - before)

    def skim(self, s):
        t = min(SKIM, max(0, s))
        along = SPEED * t - 0.5 * (SPEED / SKIM) * t * t
        hop = 0
        for a, b, h in HOPS:
            if a <= t < b:
                u = (t - a) / (b - a)
                hop = h * 4 * u * (1 - u)
        sink = (t - (SKIM - 0.5)) / 0.5 * 1.2 if t > SKIM - 0.5 else 0
        return self.point(1) + v(0, SIT, 0) + self.run_out() * along + v(0, hop - sink, 0)


def rider(seat, run):
    """Sitting up on the sled, arms up: the head over the seat, the feet out in front."""
    return {"head": seat + v(0, 2.6, 0), "feet": seat + flat(run) * 1.6 - v(0, 0.6, 0)}


def slide(count=None, seed=0, fps=60):
    count = count or dict(RUNS)["medium"]
    r = Ride(count, seed)
    frames = []
    u_in = r.first_below(r.ctop + OVER_TOP, 0)
    u_out = r.first_below(r.cbot - UNDER_BOTTOM, u_in)
    out_at = r.at(u_out)
    out_run = flat(r.at(min(1, u_out + 0.02)) - out_at)
    landing_pool = r.point(1)
    state = {"shot": None, "since": 0.0}
    total = int(r.seconds * fps)
    for i in range(total):
        t = i / fps
        u = t / r.seconds
        here = r.at(u)
        ahead = r.at(min(1, u + 0.02))
        run = unit(ahead - here)
        fl = flat(run)
        out = flat(here - r.centre)
        body = rider(here, run)

        def start(name):
            if state["shot"] != name:
                state["shot"] = name
                state["since"] = t
        if u < 0.1:
            start("slide: the push")
            frames.append(Frame(t, "slide: the push", here - fl * 10 + v(0, 5.5, 0), r.at(min(1, u + 0.12)), 64, subject=body))
        elif u < u_in:
            start("slide: the track")
            far = r.at(min(1, u_in + 0.03))
            frames.append(Frame(t, "slide: the track", here + out * 22 + v(0, 10, 0) - fl * 12, here + (far - here) * 0.3 + v(0, 1, 0), 56,
                                subject=body))
        elif u < u_out:
            left = (u_out - u) * r.seconds
            since = (u - u_in) * r.seconds
            if since < PLUNGE_HOLD and left > BURST_LEAD:
                if state["shot"] != "slide: the plunge":
                    start("slide: the plunge")
                    state["eye"] = here - fl * 14 + out * 9 + v(0, 15, 0)
                held = t - state["since"]
                frames.append(Frame(t, "slide: the plunge", state["eye"], here, 60 - min(held, PLUNGE_HOLD) * 6, subject=body))
            elif left > BURST_LEAD + BELOW_HOLD and (state["shot"] == "slide: in the cloud"
                                                    or left > BURST_LEAD + BELOW_HOLD + MIST_LEAST):
                # Riding through the cloud with them, close behind and over (the cloud thinned round them on screen).
                start("slide: in the cloud")
                frames.append(Frame(t, "slide: in the cloud", here - fl * 8 + out * 2.5 + v(0, 3.5, 0), here + run * 4 + v(0, 1.2, 0),
                                    66, subject=body))
            elif left > BURST_LEAD and (state["shot"] == "slide: under the cloud, wide" or left > BURST_LEAD + 1):
                start("slide: under the cloud, wide")
                held = t - state["since"]
                landing = landing_pool + v(0, SIT, 0)
                mid = (out_at + landing) / 2
                away = flat(mid - r.centre)
                drift = min(1, max(0, held / 5))
                eye = mid + away * (150 - 28 * drift) + v(0, 6 + 6 * drift, 0)
                eye = v(eye[0], min(eye[1], r.cbot - 16), eye[2])
                frames.append(Frame(t, "slide: under the cloud, wide", eye, mid + (out_at - mid) * 0.38, 66, looks_at="away",
                                    subject={"exit": out_at, "pool": landing_pool}))
            else:
                if state["shot"] != "slide: waiting under the cloud":
                    start("slide: waiting under the cloud")
                    away = flat(out_at - r.centre)
                    state["wait"] = out_at + out_run * 30 + away * 22 + v(0, -24, 0)
                frames.append(Frame(t, "slide: waiting under the cloud", state["wait"], out_at + v(0, 5, 0), 60, looks_at="away",
                                    subject={"exit": out_at}))
        elif (u - u_out) * r.seconds < BURST_HOLD:
            if "wait" not in state:
                away = flat(out_at - r.centre)
                state["wait"] = out_at + out_run * 30 + away * 22 + v(0, -24, 0)
            start("slide: through the cloud")
            frames.append(Frame(t, "slide: through the cloud", state["wait"], here + v(0, 1, 0), 60, subject=body))
        elif u < 0.86:
            start("slide: the face")
            frames.append(Frame(t, "slide: the face", here + run * 14 + v(0, 4.5, 0), here + v(0, 1.2, 0), 58, subject=body))
        else:
            start("slide: the pool")
            landing = r.point(1)
            last = r.point(0.97)
            away = flat(landing - last)
            side = v(-away[2], 0, away[0])
            frames.append(Frame(t, "slide: the pool", landing + away * 20 + side * 10 + v(0, 2.5, 0), here, 58, subject=body))
    # THE SKIM across the pool, then the landing held.
    t0 = r.seconds
    landing = r.point(1)
    d = r.run_out()
    side = v(-d[2], 0, d[0])
    for i in range(int(SKIM * fps)):
        s = i / fps
        at = r.skim(s)
        eye = v(at[0], landing[1] + 2.2, at[2]) + side * 13 - d * (4 - s * 2.2)
        frames.append(Frame(t0 + s, "slide: the skim", eye, at + v(0, 0.5, 0), 56, subject=rider(at, d)))
    end = landing + d * (SPEED * SKIM * 0.5)
    away = flat(end - landing) if np.linalg.norm(flat(end - landing)) > 0.01 else d
    side = v(-away[2], 0, away[0])
    for i in range(int(HOLD * fps)):
        s = i / fps
        k = min(1, s / HOLD)
        swimmer = {"head": end + v(0, 1.2, 0), "feet": end - v(0, 2.5, 0)}
        frames.append(Frame(t0 + SKIM + s, "slide: the landing", end + away * (14 - 4 * k) + side * 4 + v(0, 2.4, 0),
                            end + v(0, 0.6, 0), 60, subject=swimmer))
    cutting = {"slide: the push", "slide: the track", "slide: the plunge", "slide: in the cloud", "slide: under the cloud, wide",
               "slide: waiting under the cloud", "slide: the face", "slide: the pool", "slide: the skim"}
    return mark_cuts(frames, cutting), r


def scenery(r):
    lines = []
    path = [r.point(i / 150) for i in range(151)]
    lines.append((path, "#00838f", 2))
    for y, colour in ((r.ctop, "#eceff1"), (r.cbot, "#b0bec5")):
        c = r.centre
        for k in range(-5, 6):
            lines.append(([c + v(-400, 0, k * 70) + v(0, y, 0), c + v(400, 0, k * 70) + v(0, y, 0)], colour, 1))
    pool = r.point(1)
    ring = [pool + v(math.cos(a) * S["FINAL_RADIUS"], 0, math.sin(a) * S["FINAL_RADIUS"]) for a in np.linspace(0, 2 * math.pi, 40)]
    lines.append((ring, "#29b6f6", 2))
    return lines
