"""The Flooded Halls' hanging lamps (the two-hundred-and-fifty-eighth pass, "the lamp models are too simple").

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_hall_lamps.py

A lamp was a rod, a flat green cylinder and a ball. A bath house's lamps are enamel shades on chains:

  Hall_LampShade  A dished enamel shade with a rolled rim, a brass fitter on top that the chain hangs from, and a
                  cup inside for the bulb to sit in. Closed (outer and inner skins joined at the rim), so it has a
                  thickness from below. 5.6 across, 3.4 high.
  Hall_Chain      A chain of oval links, each turned a quarter to the last. 14 long, hung from its top.

Writes meshes/Hall_LampShade.fbx and meshes/Hall_Chain.fbx (+Z up in Blender, the export turns it to +Y).
"""

import math
import os
import sys

import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sealife as G  # noqa: E402  -- clear_scene, to_object, export

AROUND = 32
CHAIN_LENGTH = 14.0
LINK_PITCH = 0.62


def lathe(bm, profile, around=AROUND, close_ends=True):
    """A surface turned about +Z from [(r, z)]; closed at an end whose radius is above zero."""
    rings = []
    for r, z in profile:
        ring = [bm.verts.new((math.cos(j / around * math.tau) * r, math.sin(j / around * math.tau) * r, z))
                for j in range(around)]
        rings.append(ring)
    for lo, hi in zip(rings, rings[1:]):
        for j in range(around):
            k = (j + 1) % around
            bm.faces.new((lo[j], lo[k], hi[k], hi[j]))
    if close_ends:
        bm.faces.new(tuple(reversed(rings[0])))
        bm.faces.new(tuple(rings[-1]))
    return rings


def build_shade():
    G.clear_scene()
    bm = bmesh.new()
    # The shade: down the outside from the fitter to a rolled rim, and back up the inside, as one closed loop.
    outside = [(0.55, 0.0), (0.75, -0.18), (1.15, -0.55), (1.7, -1.05), (2.2, -1.6), (2.55, -2.1), (2.72, -2.42)]
    rim = [(2.82, -2.5), (2.84, -2.62), (2.76, -2.7), (2.62, -2.64)]
    inside = [(2.46, -2.32), (2.1, -1.78), (1.6, -1.25), (1.05, -0.74), (0.66, -0.36), (0.5, -0.2)]
    lathe(bm, outside + rim + inside)
    # The fitter: a brass collar the chain hangs from, with a ring on top.
    lathe(bm, [(0.42, -0.1), (0.48, 0.0), (0.48, 0.55), (0.36, 0.7), (0.2, 0.82)], around=16)
    # The cup for the bulb, under the fitter inside the shade.
    lathe(bm, [(0.32, -0.15), (0.36, -0.55), (0.3, -0.8)], around=16)
    obj = G.to_object("Hall_LampShade", bm, smooth=True)
    G.export([obj], "Hall_LampShade")


def link(bm, centre, turned):
    """One oval link: a ring of tube round a stadium, 0.5 long and 0.32 wide."""
    major_len, major_w, tube, steps, sides = 0.25, 0.16, 0.06, 16, 6
    rot = Matrix.Rotation(math.pi / 2 if turned else 0.0, 4, "Z")
    rings = []
    for s in range(steps):
        a = s / steps * math.tau
        # The centreline of the link, in its own XZ plane.
        p = Vector((math.cos(a) * major_w, 0.0, math.sin(a) * (major_len + major_w * 0.4)))
        tangent = Vector((-math.sin(a) * major_w, 0.0, math.cos(a) * (major_len + major_w * 0.4))).normalized()
        out = tangent.cross(Vector((0, 1, 0))).normalized()
        ring = []
        for k in range(sides):
            b = k / sides * math.tau
            q = p + (out * math.cos(b) + Vector((0, 1, 0)) * math.sin(b)) * tube
            ring.append(bm.verts.new(rot @ q + centre))
        rings.append(ring)
    for s in range(steps):
        lo, hi = rings[s], rings[(s + 1) % steps]
        for k in range(sides):
            m = (k + 1) % sides
            bm.faces.new((lo[k], lo[m], hi[m], hi[k]))


def build_chain():
    G.clear_scene()
    bm = bmesh.new()
    count = int(CHAIN_LENGTH / LINK_PITCH)
    for i in range(count):
        link(bm, Vector((0, 0, -0.3 - i * LINK_PITCH)), i % 2 == 1)
    obj = G.to_object("Hall_Chain", bm, smooth=True)
    G.export([obj], "Hall_Chain")


if __name__ == "__main__":
    build_shade()
    build_chain()
