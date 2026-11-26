"""The Maw's tongue (the two-hundred-and-fifty-third pass, from "I don't like the shape of the tongue").

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_maw_tongue.py

Two parts' worth of spheres read as two ovals, or worse. This is one body: long, broad at its root and tapering to a
rounded tip, thick in the middle and thin at the edges, a groove down its middle that fades toward the tip, a flatter
underside to lie on the floor of the mouth, and a skin of small papillae on top. Its root pinches in where it goes back
into the throat, so the mesh is closed at both ends.

Writes meshes/Maw_Tongue.fbx. In Blender, +Y runs from the root to the tip and +Z is its top; Maw.lua places it (the
import's box is centred, so the code says where its middle goes) and turns it if it arrives the other way about.
"""

import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector, noise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_sealife as G  # noqa: E402  -- clear_scene, to_object, export

LENGTH = 30.0   # root to tip
WIDTH = 15.0    # at its broadest
THICK = 4.2     # at its thickest
GROOVE = 0.9    # the groove down its middle, deepest at the root
NT, NU = 48, 32  # rings along it, points round each ring
SEED = 253


def width_at(t):
    """Broad from just past the root, tapering to a rounded tip; pinched at both ends so the body is closed."""
    tip = math.sqrt(max(0.0, 1.0 - t ** 3))
    root = math.sin(min(1.0, t / 0.14) * math.pi / 2) ** 0.6
    return WIDTH * tip * root * (1.0 - 0.18 * t)


def thick_at(t):
    root = math.sin(min(1.0, t / 0.14) * math.pi / 2) ** 0.7
    return THICK * root * (1.0 - 0.55 * t) * math.sqrt(max(0.0, 1.0 - t ** 5))


def build():
    G.clear_scene()
    random.seed(SEED)
    bm = bmesh.new()
    rings = []
    for i in range(NT + 1):
        t = i / NT
        w, h = width_at(t), thick_at(t)
        ring = []
        for j in range(NU):
            phi = 2 * math.pi * j / NU
            u = math.cos(phi)
            s = math.sin(phi)
            x = 0.5 * w * u * (1 - 0.06 * abs(u))
            if s >= 0:
                # The top: a broad dome, the groove down the middle, papillae.
                z = 0.5 * h * (abs(s) ** 0.7)
                z -= GROOVE * (1 - 0.7 * t) * math.exp(-(u / 0.16) ** 2) * min(1.0, h / THICK * 2)
                z += 0.12 * noise.noise(Vector((x * 0.9, t * LENGTH * 0.9, 1.7))) * min(1.0, h)
            else:
                # The underside: flatter, to lie on the floor of the mouth.
                z = -0.5 * h * 0.55 * (abs(s) ** 0.45)
            ring.append(bm.verts.new((x, t * LENGTH, z)))
        rings.append(ring)
    for i in range(NT):
        a, b = rings[i], rings[i + 1]
        for j in range(NU):
            k = (j + 1) % NU
            try:
                bm.faces.new((a[j], a[k], b[k], b[j]))
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.02)
    # Close whatever is left open at the pinched ends.
    edges = [e for e in bm.edges if e.is_boundary]
    if edges:
        bmesh.ops.holes_fill(bm, edges=edges, sides=0)
    obj = G.to_object("Maw_Tongue", bm, smooth=True)
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    G.export([obj], "Maw_Tongue")
    d = obj.dimensions
    print("Maw_Tongue", len(obj.data.polygons), "tris", [round(d.x, 2), round(d.z, 2), round(d.y, 2)], "(Roblox x, y, z)")
    return obj


if __name__ == "__main__":
    build()
