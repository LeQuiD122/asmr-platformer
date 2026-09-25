"""The thing under the route: a sea serpent, one rigged mesh the length of the street's shadow.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_serpent.py
    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_serpent.py -- render

Writes meshes/Sea_Serpent.fbx. Import it into ReplicatedStorage/Assets/TileMeshes WITH its Bone
children. Run it AFTER gen_sealife.py, which rewrites blender/sealife_extents.json that this adds
itself to. With `render`, it also draws blender/serpent_rest.png and serpent_posed.png.

=== What it replaces ===

The thing was eighteen stretched ellipsoids in a line, a fin on every other one and a slab for a
fluke: from the route, through thirty studs of water, a string of beads. This is one body: a
blunt head under a heavy brow with pale eyes (still the client's parts, so they can stay pale),
barbels hanging from the jaw, gill grooves behind it, a keel down the back carrying a scalloped
crest of spines, and a tail that thins to a fluke. It bends along its whole length instead of
hinging at eighteen joints.

=== The contract with the client and the checker ===

    BONES   Spine_1 .. Spine_18, head to tail, one per body segment. Bone k runs from the path
            point `(k - 1.5) * SPACING` behind the head to the next, so the client lays the chain
            through exactly the nineteen points SunkenPath gives the part-built body -- the thing
            is where it always was, to the stud.
    GIRTH   The part-built body's own profile (girthAt): half as wide as 0.9 of the girth and as
            tall as 0.75 of it. The crest stays under 1.3 girths over the centre line and the
            barbels over 0.75 under it, which is what check_sunkencity.py holds the thing to
            against the road signs, the chunks overhead and the floor.
    SIDE    No pectoral fins, on purpose: the body sways up to about 0.42 radians off the path, and
            a fin swept back off its side swings out by its length times that, past the 2.7 studs
            the dry flat leaves. What does stick out -- the fluke -- is measured under that sway
            and written to the extents file as `side_reach`, which the checker uses.
    PIVOT   The box is centred on the middle of the body (+/-110), joint 1 at +99 and joint 19 at
            -99 along Blender Y (the head forward, arriving as Roblox -Z).
"""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sealife as G  # noqa: E402  -- plate, loft, rig, skin, export

SEGMENTS = 18        # SunkenPath.SEGMENTS
SPACING = 11.0       # SunkenPath.SPACING
GIRTH = 8.0          # SunkenCityService's MONSTER_GIRTH
SWAY_TURN = 0.42     # the most the body turns off the path: the sway's slope and the wander's
MIDDLE = (SEGMENTS - 1) / 2 * SPACING   # the middle of the body, `behind` the head's centre
SNOUT = 8.8          # how far the head reaches in front of the first segment's centre
TAIL = (SEGMENTS - 1) * SPACING + 8.4   # where the body ends and the fluke begins
CREST_TOP = 10.0     # the crest's highest spine over the centre line (the checker allows 1.3 girths)


def y_of(behind):
    return MIDDLE - behind


def girth(behind):
    """girthAt, continued: the part-built body's profile, rounding off at the snout and the tail."""
    x = behind / ((SEGMENTS - 1) * SPACING)
    if x < 0.15:
        g = GIRTH * (0.75 + max(0.0, x) / 0.15 * 0.25)
    else:
        g = GIRTH * (1 - 0.75 * ((min(x, 1.0) - 0.15) / 0.85) ** 1.3)
    if behind < 0:
        g *= math.sqrt(max(0.0, 1 - (behind / SNOUT) ** 2)) * 0.85 + 0.15
    last = (SEGMENTS - 1) * SPACING
    if behind > last:
        g *= math.sqrt(max(0.0, 1 - ((behind - last) / (TAIL - last + 0.6)) ** 2)) * 0.8 + 0.2
    return g


def section(behind, a):
    """A point round the body's section at `behind`, angle `a` from its side."""
    g = girth(behind)
    w, h = 0.9 * g, 0.75 * g
    c, s = math.cos(a), math.sin(a)
    # Annuli, faint: a body of rings rather than a hose. Pressed IN, never out, so the body is
    # never wider than the 0.9 girths the checker allows.
    ring = 1 - 0.05 * (0.5 + 0.5 * math.cos(2 * math.pi * behind / 5.6)) * (1 if behind > 6 else 0)
    # THE HEAD: wider at the jaw's hinge than at the snout, and flat on top, a skull rather than
    # the front of a hose.
    jaw = math.exp(-(((behind - 3.5) / 4.0) ** 2))
    w *= 1 + 0.08 * jaw
    if behind < 9 and s > 0:
        h *= 0.86 + 0.14 * max(0.0, min(1.0, (behind - 3) / 6))
    x, z = w * c * ring, h * s * ring
    # The brow: a heavy ridge over each eye, part of the skull, above where the client's eye parts
    # sit (0.72 and 0.3 of the head's girth out and up, 0.45 of a spacing in front of its middle).
    if s > 0:
        brow = 0.6 * math.exp(-(((behind + 3.8) / 3.0) ** 2)) * math.exp(-(((abs(c) - 0.62) / 0.16) ** 2))
        x += math.copysign(0.35 * brow, c)
        z += brow
    if s > 0:
        z += 0.08 * g * s ** 12        # the keel down the back
    else:
        z *= 0.88                      # a flatter belly
    # Three gill grooves on each side behind the head.
    for groove in (11.0, 12.8, 14.6):
        d = behind - groove
        if abs(d) < 0.6 and abs(c) > 0.55:
            dent = 0.28 * (1 - abs(d) / 0.6) * (abs(c) - 0.55) / 0.45
            x -= math.copysign(dent, c)
    # The jaw line: a crease along each side of the head, a little under the middle.
    if behind < 6 and -0.45 < s < -0.1:
        x *= 0.96
    return x, y_of(behind), z


def body(bm):
    stations = []
    s = -SNOUT
    while s < TAIL:
        stations.append(s)
        s += 0.5 if s < 18 else 1.4
    stations.append(TAIL)
    sides = 18
    rings = []
    for behind in stations:
        rings.append([bm.verts.new(section(behind, 2 * math.pi * k / sides)) for k in range(sides)])
    for i in range(len(rings) - 1):
        for k in range(sides):
            bm.faces.new((rings[i][k], rings[i][(k + 1) % sides], rings[i + 1][(k + 1) % sides], rings[i + 1][k]))
    for ring, behind in ((rings[0], stations[0] - 0.4), (rings[-1], stations[-1] + 0.3)):
        tip = bm.verts.new((0, y_of(behind), 0))
        for k in range(sides):
            bm.faces.new((ring[k], ring[(k + 1) % sides], tip))
    # Faces point outward whichever way the rings were wound: recalc_face_normals in to_object.


def head(bm):
    """The barbels, hanging from the corners of the jaw. (The brows are the skull's own, in section.)"""
    for side in (-1, 1):
        # Barbels, from the corners of the jaw, down and back.
        stations = []
        for j in range(8):
            t = j / 7
            stations.append((-2.2 - t * 3.3, side * (3.0 + 0.6 * t), y_of(2.0 + 2.5 * t + 0.4 * math.sin(t * 5)),
                             0.28 * (1 - 0.8 * t), 0.28 * (1 - 0.8 * t)))
        # Down to 5.5 under the centre line, inside the 0.75 girths the checker allows.
        G.loft(bm, stations, 6, True, True, axis="z")


def crest(bm):
    """A scalloped crest of raked spines along the keel, highest behind the head, gone by the tail."""
    start, end = 4.0, 150.0
    spines = 13
    top_line, base_line = [], []
    for j in range(spines):
        u0 = j / spines
        u1 = (j + 1) / spines
        s0 = start + (end - start) * u0
        s_peak = s0 + (end - start) / spines * 0.55   # raked back
        s1 = start + (end - start) * u1
        base_top = lambda s: 0.75 * girth(s) * (1 + 0.08 * 1.0) * 0.98   # the keel's top, just inside
        fade = (1 - (s_peak - start) / (end - start)) ** 0.5
        peak = base_top(s_peak) + (CREST_TOP - base_top(s_peak)) * fade * (0.8 + 0.2 * math.sin(j * 1.9))
        valley = base_top(s1) + 0.3 * (peak - base_top(s1))
        if j == 0:
            top_line.append((0, y_of(s0), base_top(s0) + 0.2))
        top_line.append((0, y_of(s_peak), peak))
        top_line.append((0, y_of(s1), valley if j < spines - 1 else base_top(s1) + 0.1))
    for k in range(spines, -1, -1):
        s = start + (end - start) * k / spines
        base_line.append((0, y_of(s), 0.75 * girth(s) - 0.6))
    G.plate(bm, top_line + base_line, (1, 0, 0), 0.3)


def fluke(bm):
    """Flat, and under five studs either side: turned with the tail it reaches about eight."""
    ty = y_of(TAIL)
    outline = [(0, 1.6), (2.6, -1.2), (5.4, -4.6), (4.6, -6.2), (1.6, -4.2), (0, -4.8), (-1.6, -4.2), (-4.6, -6.2),
               (-5.4, -4.6), (-2.6, -1.2)]
    G.plate(bm, G.curve_outline([(x * 0.9, ty + y * 0.9, 0) for x, y in outline], 3), (0, 0, 1), 0.35)


def side_reach(mesh):
    """The furthest anything reaches from the path, with the body turned SWAY_TURN off it. For the
    body itself that is its half-width (the checker adds the sway of the centre line); for the
    fluke, which is rigid past the last joint, its half-width and its length behind that joint,
    turned together."""
    last_joint = y_of((SEGMENTS - 0.5) * SPACING)
    worst = 0.0
    c, s = math.cos(SWAY_TURN), math.sin(SWAY_TURN)
    for v in mesh.data.vertices:
        x, y = abs(v.co.x), v.co.y
        if abs(x - 9) < 0.01 and abs(abs(y) - 110) < 0.01:
            continue  # an anchor speck
        if y < last_joint:
            worst = max(worst, x * c + (last_joint - y) * s)
        else:
            worst = max(worst, x)
    return round(worst, 3)


def build():
    bm = bmesh.new()
    body(bm)
    head(bm)
    crest(bm)
    fluke(bm)
    G.anchor(bm, (-9, -110, -11), (9, 110, 11))
    mesh = G.to_object("Sea_Serpent", bm)
    joints = [y_of((k - 1.5) * SPACING) for k in range(1, SEGMENTS + 2)]
    specs = [("Spine_%d" % k, (0, joints[k - 1], 0), (0, joints[k], 0), "Spine_%d" % (k - 1) if k > 1 else None)
             for k in range(1, SEGMENTS + 1)]
    rig = G.build_armature("Sea_Serpent", specs)
    spans = [("Spine_%d" % k, joints[k - 1], joints[k]) for k in range(1, SEGMENTS + 1)]
    G.skin(mesh, rig, lambda co: G.chain_weights(co, spans, along=1))
    return mesh, rig


def preview(mesh, rig):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x, scene.render.resolution_y = 1400, 700
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "OBJECT"
    mesh.color = (0.16, 0.22, 0.26, 1.0)
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    for tag, centre, scale, direction, amount in (("rest", (0, 0, 0), 230, (0.9, -0.25, 0.55), 0.0),
                                                   ("posed", (0, 0, 0), 230, (0.9, -0.25, 0.55), 1.0),
                                                   ("head", (0, 92, 0), 34, (0.8, 0.9, 0.5), 0.0)):
        bends = {"Spine_%d" % k: ("z", 0.09 * math.sin(k * 0.7)) for k in range(2, SEGMENTS + 1)}
        G.pose(rig, bends, amount)
        cam_data.ortho_scale = scale
        d = Vector(direction).normalized()
        cam.location = Vector(centre) + d * 300
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(HERE, "serpent_%s.png" % tag)
        bpy.ops.render.render(write_still=True)
    G.pose(rig, {}, 0.0)


def main():
    G.clear_scene()
    mesh, rig = build()
    G.export([mesh, rig], "Sea_Serpent")
    reach = side_reach(mesh)
    print("  side reach under a %.2f-radian turn: %.2f (0.9 girth is %.2f)" % (SWAY_TURN, reach, 0.9 * GIRTH))
    if G.RENDER:
        preview(mesh, rig)
    path = os.path.join(HERE, "sealife_extents.json")
    try:
        with open(path, encoding="utf-8") as f:
            known = json.load(f)
    except (OSError, ValueError):
        known = {}
    box = G.EXTENTS.get("Sea_Serpent", {})
    box["side_reach"] = reach
    known["Sea_Serpent"] = box
    with open(path, "w", encoding="utf-8") as f:
        json.dump(known, f, indent=1, sort_keys=True)
    print("  added the serpent to blender/sealife_extents.json")
    print("\nImport meshes/Sea_Serpent.fbx into ReplicatedStorage/Assets/TileMeshes, keeping the Bone children.")


if __name__ == "__main__":
    main()
