"""THE SCENES' SHOTS, CHECKED THE WAY THE CAMERA SEES THEM: every scripted shot in levels 1 to 5, frame by frame.

    python blender/check_shots.py             the check (exit 1 on a problem) and a table of every shot
    python blender/check_shots.py --boards    and a storyboard per level: blender/shots_<level>.png

Each level's scenes are restated from its client (shots_<level>.py), the shots line for line, and played through
shots.py, which is Cinema.point as the game has it: the eye put where asked, the aim easing after its target unless
the code cuts, a vertical field of view, and the letterbox bars over the top and bottom of the picture. For every
shot it asks what a player would see:

    SEEN         the subject (you, unless a shot is meant to look away) is in the picture, not under a bar, all the
                 way through it, with the aim's lag (a fast subject and a slow aim lose each other)
    SIZE         you are the size the shot is meant to show you at: a speck, wide, medium or close, from its name in
                 INTENT below, so a "close" that is a speck or a "wide" that is a nose is a failure
    NOT IN YOU   the camera never comes within a stud and a half of you (it went through the rider once)
    LONG ENOUGH  no shot shorter than it can be read (MIN_SHOT), but for the beats that are meant to be quick

It also fails if any shot line it restates has changed in the client, so it never checks a shot the game no longer has.
"""
import sys

import shots
import shots_clock
import shots_halls
import shots_hill
import shots_shore
import shots_skypools
import shots_sunken
import shots_true

problems = []


def fail(message):
    problems.append(message)


# What each shot is meant to show you as: (smallest, largest) share of the picture's height between the bars. A shot
# you come toward (or go away from) is given its own range, from far to near.
SIZES = {"speck": (0.015, 0.16), "wide": (0.06, 0.45), "medium": (0.2, 1.0), "close": (0.3, 3.0),
         "coming at it": (0.03, 1.0), "going away": (0.04, 0.6)}
MIN_SHOT = 0.8
# Beats meant to be quick: a slam, not a shot to look round.
QUICK = {"maw: the bite, wide", "dive: the splash"}
INTENT = {
    # level 1: the high dive
    "dive: the leap": ("going away", True),
    # (The hundred-and-twenty-ninth pass, from your test: Maren's shot was the deck's floor. It is her reaction now, and
    # the hit is held from the surface before the camera goes under.)
    "dive: Maren": ("close", True),
    "dive: the turn": ("medium", True),
    "dive: the drop": ("medium", True),
    "dive: your face": ("close", True),
    "dive: the water": ("coming at it", True),
    "dive: the splash": (None, True),
    "dive: under the water": ("medium", True),
    # level 2: the slide
    "slide: the push": ("medium", True),
    "slide: the track": ("wide", True),
    "slide: the plunge": ("wide", True),
    # (The hundred-and-twenty-seventh pass, from your test: "I wanna see the player more often": the ride in the cloud
    # is shown with you in it, and the landing is close.)
    "slide: in the cloud": ("medium", True),
    "slide: under the cloud, wide": (None, True),
    "slide: waiting under the cloud": (None, True),
    "slide: through the cloud": ("coming at it", True),
    "slide: the face": ("medium", True),
    "slide: the pool": ("coming at it", True),
    "slide: the skim": ("medium", True),
    "slide: the landing": ("medium", True),
    # level 3: the drain, the outfall and the reveal
    "drain: the grab": ("close", True),
    "drain: round the funnel": ("medium", True),
    "drain: down the shaft": ("medium", True),
    "drain: the bottom": ("coming at it", True),
    "outfall: from ahead": ("medium", True),
    "outfall: alongside": ("close", True),
    "outfall: to the light": ("medium", True),
    "outfall: the station": ("coming at it", True),
    "reveal: the time card": (None, True),
    # level 4: the flume
    "over the shoulder": ("medium", True),
    "chasing": ("wide", True),
    "from the wall": ("wide", True),
    "from ahead": ("medium", True),
    "from below": ("wide", True),
    "from above": ("medium", True),
    # level 4: the mouth
    "maw: falling into black": ("medium", True),
    "maw: past you into it": ("wide", True),
    "maw: your face": ("close", True),
    "maw: from inside it": ("coming at it", True),
    "maw: the bite, wide": ("speck", True),
    "maw: down its throat": ("medium", True),
    # level 4: the gate chamber
    "chamber: up the ladder": ("medium", True),
    "chamber: the room": ("wide", True),
    "chamber: the walk": ("medium", True),
    "chamber: the key": ("close", True),
    "chamber: the wheel and the gate": ("wide", True),
    "chamber: midnight": (None, True),
    "chamber: the last line": (None, True),
    # level 4: clocking in at the time clock on the gangway (the hundred-and-fourteenth pass)
    "clock: your card": ("close", True),
    "clock: on shift": ("medium", True),
    # level 4: the true ending, for a rider who clocked in (the hundred-and-fifteenth pass): him, then you and him
    "true: someone in the light": ("coming at it", True),
    "true: his face": ("close", True),
    "true: the wave": ("wide", True),
    "true: into the morning": ("close", True),
    # level 5: his key, in the hall (the clock's shot is of the clock: its face and its pendulum both in the picture)
    "key: taking it": ("close", True),
    "key: his clock": (None, True),
    "key: the way out": ("medium", True),
}


def audit(level, frames, quick=QUICK):
    rows = []
    for r in shots.measure(frames):
        size, must_be_long = INTENT.get(r.name, (None, True))
        rows.append(r)
        if r.name not in INTENT:
            fail("%s: the shot %r has no INTENT here" % (level, r.name))
        if r.looks_at == "subject" and r.lost:
            fail("%s: in %r you are out of the picture or under a bar for %d of %d frames (furthest %.2f across, %.2f up)"
                 % (level, r.name, r.lost, r.frames, r.worst_x, r.worst_y))
        if size and r.looks_at == "subject" and r.max_size > 0:
            lo, hi = SIZES[size]
            if r.min_size < lo or r.max_size > hi:
                fail("%s: %r is meant to be %s, and you are %.2f to %.2f of the picture's height" % (
                    level, r.name, size, r.min_size, r.max_size))
        if r.min_depth < 1.5:
            fail("%s: in %r the camera comes within %.1f studs of you" % (level, r.name, r.min_depth))
        if r.name not in quick and r.length + 1 / shots.FPS < MIN_SHOT - 0.01:
            fail("%s: %r lasts %.2f s, too short to read" % (level, r.name, r.length))
    return rows


def table(level, rows):
    print("== %s" % level)
    for r in rows:
        print("  %-34s %6.2f s  seen %s  across <=%.2f up <=%.2f  size %.2f..%.2f" % (
            r.name, r.length, "all" if not r.lost else "LOST %d/%d" % (r.lost, r.frames), r.worst_x, r.worst_y,
            r.min_size if r.min_size < 9 else 0, r.max_size))


def stale(level, lines, text):
    for line in lines:
        if line not in text:
            fail("%s: the client's shot line %r has changed; restate it in shots_*.py" % (level, line))


# ----- level 1 -----
stale("City Shore", shots_shore.SHOT_LINES, shots_shore.CLIENT)
dive, tip = shots_shore.dive()
shore_rows = audit("City Shore", dive)

# ----- level 2: every run length, on several laid runs -----
stale("Sky Pools", shots_skypools.SHOT_LINES, shots_skypools.CLIENT)
sky_rows = []
for label, count in shots_skypools.RUNS:
    for seed in (0, 100, 200):
        frames_, ride_ = shots_skypools.slide(count, seed)
        rows_ = audit("Sky Pools %s seed %d" % (label, seed), frames_)
        if label == "medium" and seed == 0:
            sky_rows, sky_frames, sky_ride = rows_, frames_, ride_

# ----- level 3 -----
stale("Sunken City", shots_sunken.SHOT_LINES, shots_sunken.CLIENT)
sunken = shots_sunken.ride()
sunken_rows = audit("Sunken City", sunken)

# ----- level 4 -----
stale("Flooded Halls", shots_halls.SHOT_LINES, shots_halls.CLIENT)
flume = shots_halls.flume()
maw, rest = shots_halls.maw(t0=shots_halls.SECONDS)
chamber = shots_halls.chamber(t0=shots_halls.SECONDS + shots_halls.MAW_SECONDS)
halls_rows = audit("Flooded Halls", flume + maw + chamber)
stale("Flooded Halls, the time clock", shots_clock.SHOT_LINES, shots_clock.CLIENT)
clocking = shots_clock.clock_in()
clock_rows = audit("Flooded Halls, the time clock", clocking)
stale("Flooded Halls, the true ending", shots_true.SHOT_LINES, shots_true.CLIENT)
true_end = shots_true.true_ending()
true_rows = audit("Flooded Halls, the true ending", true_end)
if shots_true.DONE + 0.8 > shots_true.SECONDS + shots_true.TRUE_MORE + 0.01:
    fail("Flooded Halls, the true ending: it runs to %.1f s and the server gives the gates %.1f" % (
        shots_true.DONE + 0.8, shots_true.SECONDS + shots_true.TRUE_MORE))

# ----- level 5 -----
stale("Hill House", shots_hill.SHOT_LINES, shots_hill.CLIENT)
hill = shots_hill.hall()
hill_rows = audit("Hill House", hill)

if "--boards" in sys.argv:
    here = shots.ROOT / "blender"
    shots.storyboard(dive, shots_shore.scenery(tip), here / "shots_shore.png", "Level 1, City Shore: the high dive")
    shots.storyboard(sky_frames, shots_skypools.scenery(sky_ride), here / "shots_skypools.png",
                     "Level 2, the Sky Pools: the slide (medium, seed 0)")
    shots.storyboard(sunken, shots_sunken.scenery(), here / "shots_sunken.png",
                     "Level 3, the Sunken City: the drain, Outfall 3 and the time card")
    shots.storyboard(flume + maw, shots_halls.scenery_flume_and_maw(rest), here / "shots_halls.png",
                     "Level 4, the Flooded Halls: the flume and the mouth")
    shots.storyboard(chamber, shots_halls.scenery_chamber(), here / "shots_halls_chamber.png",
                     "Level 4, the Flooded Halls: the gate chamber")
    shots.storyboard(hill, shots_hill.scenery(), here / "shots_hill.png", "Level 5, Hill House: his key, in the hall")
    shots.storyboard(clocking, shots_clock.scenery(), here / "shots_clock.png",
                     "Level 4, the Flooded Halls: clocking in, by Mr Barlow on the gangway")
    shots.storyboard(true_end, shots_true.scenery(), here / "shots_true.png",
                     "Level 4, the Flooded Halls: the true ending, for a rider who clocked in")

if "--quiet" not in sys.argv:
    table("Level 1, City Shore", shore_rows)
    table("Level 2, the Sky Pools (medium, seed 0)", sky_rows)
    table("Level 3, the Sunken City", sunken_rows)
    table("Level 4, the Flooded Halls", halls_rows)
    table("Level 4, the time clock", clock_rows)
    table("Level 4, the true ending", true_rows)
    table("Level 5, Hill House", hill_rows)

if problems:
    for problem in problems:
        print("FAIL: " + problem)
    sys.exit(1)
print("shots: every scripted shot in the levels keeps you in the picture, at the size it means, for long enough")
