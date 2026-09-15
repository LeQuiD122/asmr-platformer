"""Five posed mannequins, as static meshes.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_hub_poses.py

=== Why these exist ===

The lobby statue was meant to be a copy of the player's own avatar, posed by rotating its
Motor6Ds. Five rounds of work did not get there: the copy kept arriving with no joints in it at
all, and a rig with no joints cannot be posed by any means.

A mesh has no joints to lose. Each pose is baked here, once, and the statue simply shows the
one that was chosen -- which cannot fail the way the rigged version kept failing.

The trade is real and worth stating: a mannequin is not your avatar. So HubService still tries
the avatar first and only falls back to these, which means the day the rig works the statues
become personal again with no further work.

=== How a pose is built ===

Forward kinematics over a small skeleton. Each joint carries a rotation and an offset from its
parent; walking the tree accumulates a transform, and every bone is drawn as a tapered box
between the two points it spans. Posing is therefore just a table of angles -- the same way the
Luau POSES table works, so the two stay recognisably the same five poses.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import uv_project

OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "meshes"))

# Studs. A Roblox R15 character is around 5.5 tall, and the statue should read as a person on
# a plinth rather than as a doll, so this is built to match rather than to look neat.
UPPER_LEG, LOWER_LEG, FOOT = 1.25, 1.20, 0.26
TORSO, NECK, HEAD = 1.62, 0.20, 0.78
UPPER_ARM, LOWER_ARM, HAND = 1.02, 0.94, 0.24

# (rx, ry, rz) in degrees, in each joint's own frame. Limbs hang along -Z, so a Y rotation
# swings them out sideways and an X rotation swings them forward.
POSES = {
    # Feet together, arms at rest. The reference every other pose is a departure from.
    "Stand": {},

    # Arms out and down, chest open, chin up. The classic monument stance -- and the angles
    # are large on purpose: at eight studs away a 20-degree shoulder is invisible.
    "Hero": {
        "shoulder.R": (0, -62, 0), "shoulder.L": (0, 62, 0),
        "elbow.R": (-24, 0, 0), "elbow.L": (-24, 0, 0),
        "waist": (-10, 0, 0), "neck": (-12, 0, 0),
        "hip.R": (0, -7, 0), "hip.L": (0, 7, 0),
    },

    # One arm straight up, the other relaxed, head turned toward whoever is being waved at.
    "Wave": {
        "shoulder.R": (0, -156, 0), "elbow.R": (0, -34, 0),
        "shoulder.L": (0, 14, 0),
        "neck": (0, 0, 26), "waist": (0, 0, -8),
    },

    # Weight on one leg, hip cocked, shoulders counter-rotated, one hand resting on the hip.
    # The whole spine is involved, which is what separates a lean from a tilt.
    "Lean": {
        "waist": (4, 10, -26), "neck": (4, 0, -20),
        "hip.R": (0, -14, 0), "hip.L": (-8, 6, 0), "knee.L": (16, 0, 0),
        "shoulder.R": (0, -30, 0),
        "shoulder.L": (-28, 46, 0), "elbow.L": (-84, 0, 0),
    },

    # Crouched, arms forward, about to move. The knees are the tell: everything else can lean
    # without reading as ready, but bent knees cannot mean anything else.
    "Ready": {
        "waist": (26, 0, 0), "neck": (-22, 0, 0),
        "shoulder.R": (-74, -18, 0), "shoulder.L": (-74, 18, 0),
        "elbow.R": (-56, 0, 0), "elbow.L": (-56, 0, 0),
        "hip.R": (-36, -6, 0), "hip.L": (-36, 6, 0),
        "knee.R": (64, 0, 0), "knee.L": (64, 0, 0),
    },
}

# name -> (parent, offset from parent, bone length, half-width at the joint, half-width at the
# far end, drawn upward). The last flag is the one that is easy to get wrong: the torso and
# neck rise from their joint, everything else hangs from it.
SKELETON = [
    ("waist", None, Vector((0, 0, 0)), TORSO, 0.44, 0.52, True),
    ("neck", "waist", Vector((0, 0, TORSO)), NECK, 0.20, 0.22, True),
    ("head", "neck", Vector((0, 0, NECK)), HEAD, 0.40, 0.36, True),
    ("shoulder.R", "waist", Vector((0.56, 0, TORSO - 0.16)), UPPER_ARM, 0.20, 0.17, False),
    ("elbow.R", "shoulder.R", Vector((0, 0, -UPPER_ARM)), LOWER_ARM, 0.17, 0.14, False),
    ("hand.R", "elbow.R", Vector((0, 0, -LOWER_ARM)), HAND, 0.16, 0.15, False),
    ("shoulder.L", "waist", Vector((-0.56, 0, TORSO - 0.16)), UPPER_ARM, 0.20, 0.17, False),
    ("elbow.L", "shoulder.L", Vector((0, 0, -UPPER_ARM)), LOWER_ARM, 0.17, 0.14, False),
    ("hand.L", "elbow.L", Vector((0, 0, -LOWER_ARM)), HAND, 0.16, 0.15, False),
    ("hip.R", "waist", Vector((0.26, 0, 0)), UPPER_LEG, 0.24, 0.21, False),
    ("knee.R", "hip.R", Vector((0, 0, -UPPER_LEG)), LOWER_LEG, 0.21, 0.18, False),
    ("foot.R", "knee.R", Vector((0, 0, -LOWER_LEG)), FOOT, 0.20, 0.19, False),
    ("hip.L", "waist", Vector((-0.26, 0, 0)), UPPER_LEG, 0.24, 0.21, False),
    ("knee.L", "hip.L", Vector((0, 0, -UPPER_LEG)), LOWER_LEG, 0.21, 0.18, False),
    ("foot.L", "knee.L", Vector((0, 0, -LOWER_LEG)), FOOT, 0.20, 0.19, False),
]


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.objects):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def add_bone(bm, transform, length, near, far, up):
    """A tapered box spanning the bone, in world space.

    THE DIRECTION MATTERS AND IT IS NOT THE SAME FOR EVERY BONE. Limbs hang, so they are drawn
    down their joint's -Z. The torso and neck RISE from theirs, and their children are attached
    at +Z accordingly -- so drawing them downward like a limb put the body below the hips and
    left the head and both arms floating in the air above an empty torso, which is exactly how
    the first render came out.
    """
    if length <= 0:
        return
    reach = length if up else -length
    rings = []
    for depth, half in ((0.0, near), (reach, far)):
        corners = [(-half, -half * 0.72), (half, -half * 0.72),
                   (half, half * 0.72), (-half, half * 0.72)]
        rings.append([bm.verts.new(transform @ Vector((x, y, depth))) for x, y in corners])

    lower, upper = rings
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((lower[i], lower[j], upper[j], upper[i]))
    bm.faces.new(list(reversed(lower)))
    bm.faces.new(upper)


def build_pose(name):
    angles = POSES[name]
    bm = bmesh.new()
    world = {}

    for bone, parent, offset, length, near, far, up in SKELETON:
        rx, ry, rz = angles.get(bone, (0, 0, 0))
        local = Matrix.Translation(offset) @ Euler(
            (math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_matrix().to_4x4()
        base = world[parent] if parent else Matrix.Identity(4)
        world[bone] = base @ local
        add_bone(bm, world[bone], length, near, far, up)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])

    mesh = bpy.data.meshes.new("Hub_Pose_" + name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new("Hub_Pose_" + name, mesh)
    bpy.context.collection.objects.link(obj)

    # Dropped so the lowest point sits at z = 0, which is what lets HubService place every
    # pose with one offset instead of five. A Lean and a Ready are different heights, and a
    # statue that sinks into its own plinth when you change its pose is not acceptable.
    lowest = min((obj.matrix_world @ v.co).z for v in mesh.vertices)
    for v in mesh.vertices:
        v.co.z -= lowest
    return obj


def export(obj):
    uv_project.box_project(obj.data, 1.4)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, obj.name + ".fbx")
    for other in bpy.data.objects:
        other.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True, global_scale=0.01, add_leaf_bones=False,
        bake_anim=False, axis_forward="-Z", axis_up="Y",
        # MESH only. There is no armature here on purpose -- that is the entire point.
        object_types={"MESH"}, mesh_smooth_type="FACE")
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("    %-20s %5d tris  ->  %s" % (obj.name, tris, os.path.basename(path)))


def main():
    for name in POSES:
        clear_scene()
        export(build_pose(name))
    print("Done.")


if __name__ == "__main__":
    main()
