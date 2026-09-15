"""A colossal sunken blade, for the horizon.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_hub_monument.py

The lobby floats over open water and the far distance was a row of rectangular pillars, which
is the same mistake the lamps and the fountain made in their first versions: a shape that says
"something is there" without saying what. A skyline of boxes reads as a city because that is
the only thing a box at that distance can read as, and this room is not a city.

A SWORD THE SIZE OF A TOWER, driven into the sea and left, says something specific instead --
and it is legible in silhouette, which is the only thing that survives 400 studs of haze. That
is the whole design brief for a horizon prop: the outline has to carry it, because nothing else
will arrive.

=== Where the detail goes ===

Detail on a horizon piece is worth spending only where it changes the OUTLINE. So:

  - the fuller, the groove down the blade, is modelled as a real recess rather than a texture,
    because at this scale it catches a highlight along its whole length and splits the blade
    into two lit faces instead of one flat one;
  - the quillons sweep and taper, so the crossguard is a shape rather than a bar;
  - the blade is chipped along one edge and bent very slightly, because a perfectly straight
    sword reads as a prop and a damaged one reads as a thing that has been here a long time;
  - the grip is ringed, which gives the narrowest part of the silhouette something to do.

None of it is expensive: the whole piece is about 3000 triangles, drawn a handful of times.
"""

import math
import os
import sys

import bmesh
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import uv_project

OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "meshes"))

# Studs, at native scale. HubService scales these up hard -- they are meant to be read from
# hundreds of studs away -- so the proportions matter and the absolute size does not.
BLADE_LEN, BLADE_WIDE, BLADE_THICK = 46.0, 5.2, 1.15
GRIP_LEN, GUARD_SPAN = 7.0, 13.0


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.objects):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def finish(bm, name):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj


def ring(bm, points, height):
    return [bm.verts.new((x, y, height)) for x, y in points]


def bridge(bm, lower, upper):
    for i in range(len(lower)):
        j = (i + 1) % len(lower)
        bm.faces.new((lower[i], lower[j], upper[j], upper[i]))


def blade_section(width, thick, fuller, chip):
    """The cross-section of the blade at one height, as eight points.

    Eight rather than four because of the FULLER: the groove needs a point either side of it
    and one at its floor on each face, and that is what turns a flat slab into a blade with a
    highlight running down it.
    """
    half_w, half_t = width / 2, thick / 2
    groove = half_t - fuller
    return [
        (-half_w, 0.0),                      # the edge
        (-half_w * 0.55, half_t),            # bevel up to the flat
        (0.0, groove),                       # the fuller floor, near face
        (half_w * 0.55, half_t),
        (half_w - chip, 0.0),                # the other edge, bitten into
        (half_w * 0.55, -half_t),
        (0.0, -groove),                      # the fuller floor, far face
        (-half_w * 0.55, -half_t),
    ]


def build_blade():
    bm = bmesh.new()
    steps = 20

    rings = []
    for step in range(steps + 1):
        along = step / steps
        height = GRIP_LEN + along * BLADE_LEN

        # TAPERED IN BOTH AXES, and more sharply toward the point. A blade that narrows only
        # in width stays a plank; narrowing the thickness too is what makes the last few studs
        # read as a point rather than a chisel.
        width = BLADE_WIDE * (1.0 - along ** 1.8 * 0.86)
        thick = BLADE_THICK * (1.0 - along ** 1.5 * 0.62)
        fuller = min(thick * 0.42, 0.34) * math.sin(min(1.0, along * 1.25) * math.pi) ** 0.5

        # A chip out of one edge, a third of the way up, and another near the top. Irregular
        # on purpose: two identical notches read as a pattern, which is the opposite of damage.
        chip = 0.0
        if 0.28 < along < 0.36:
            chip = 0.55 * math.sin((along - 0.28) / 0.08 * math.pi)
        elif 0.72 < along < 0.77:
            chip = 0.30 * math.sin((along - 0.72) / 0.05 * math.pi)

        # A very slight bend, so the silhouette is not a ruled line.
        lean = (along ** 2) * 1.3

        section = blade_section(width, thick, fuller, chip)
        rings.append([bm.verts.new((x + lean, y, height)) for x, y in section])

    for lower, upper in zip(rings, rings[1:]):
        bridge(bm, lower, upper)

    # The point: gather the last ring to a single vertex rather than capping it flat.
    tip = bm.verts.new((1.3 + BLADE_WIDE * 0.02, 0.0, GRIP_LEN + BLADE_LEN + 1.8))
    top = rings[-1]
    for i in range(len(top)):
        bm.faces.new((tip, top[i], top[(i + 1) % len(top)]))

    # ===== the crossguard =====
    #
    # Swept and tapered, not a bar. The quillons drop as they go out, which is what makes a
    # guard look forged rather than assembled, and the sweep is the only curve in the whole
    # silhouette that is not the blade.
    guard = []
    for step in range(13):
        across = (step / 12) * 2 - 1
        span = across * GUARD_SPAN / 2
        drop = -abs(across) ** 1.6 * 2.6
        girth = 1.5 * (1.0 - abs(across) ** 2.2 * 0.72)
        guard.append((span, drop, girth))

    lower_ring = None
    for span, drop, girth in guard:
        points = [(span, -girth * 0.7), (span, girth * 0.7)]
        this = [
            bm.verts.new((points[0][0], points[0][1], GRIP_LEN + drop - girth)),
            bm.verts.new((points[1][0], points[1][1], GRIP_LEN + drop - girth)),
            bm.verts.new((points[1][0], points[1][1], GRIP_LEN + drop + girth)),
            bm.verts.new((points[0][0], points[0][1], GRIP_LEN + drop + girth)),
        ]
        if lower_ring:
            bridge(bm, lower_ring, this)
        else:
            bm.faces.new(list(reversed(this)))
        lower_ring = this
    bm.faces.new(lower_ring)

    # ===== the grip =====
    #
    # Ringed, because the narrowest part of the outline needs something to break it up.
    sides = 10
    previous = None
    for step in range(11):
        height = (step / 10) * GRIP_LEN
        radius = 1.05 if step % 2 == 0 else 0.86
        points = [(math.cos(a) * radius, math.sin(a) * radius * 0.72)
                  for a in (i / sides * math.tau for i in range(sides))]
        this = ring(bm, points, height)
        if previous:
            bridge(bm, previous, this)
        previous = this

    # ===== the pommel =====
    for radius, height in ((1.4, -0.1), (2.1, -0.9), (1.9, -1.9), (0.9, -2.6)):
        points = [(math.cos(a) * radius, math.sin(a) * radius * 0.8)
                  for a in (i / sides * math.tau for i in range(sides))]
        this = ring(bm, points, height)
        bridge(bm, this, previous) if previous else None
        previous = this
    bm.faces.new(previous)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return finish(bm, "Hub_SunkenBlade")


def main():
    clear_scene()
    obj = build_blade()
    # UNWRAPPED ALONG THE BLADE, not box-projected.
    #
    # box_project tiles at a fixed number of studs, so on a 55-stud sword at 6 studs a tile the
    # texture repeated nine times up the length -- which is exactly the banding in the
    # screenshot, and it also destroyed the whole point of the maps: they are authored with V
    # running once from submerged tip to dry hilt, and a gradient that repeats nine times is
    # not a gradient.
    #
    # So V is the height fraction over the WHOLE piece and U is the angle around it. One
    # wrap, no repeats, and the corrosion lands where it was drawn to land.
    mesh = obj.data
    zs = [v.co.z for v in mesh.vertices]
    low, high = min(zs), max(zs)
    span = (high - low) or 1.0
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    uv = mesh.uv_layers.active.data
    for poly in mesh.polygons:
        for loop_index in poly.loop_indices:
            co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            angle = math.atan2(co.y, co.x)
            uv[loop_index].uv = ((angle / math.tau) % 1.0, (co.z - low) / span)
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, obj.name + ".fbx")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.fbx(
        filepath=path, use_selection=True, global_scale=0.01, add_leaf_bones=False,
        bake_anim=False, axis_forward="-Z", axis_up="Y", object_types={"MESH"},
        mesh_smooth_type="FACE")
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print("    %-18s %5d tris  ->  %s" % (obj.name, tris, os.path.basename(path)))
    print("Done.")


if __name__ == "__main__":
    main()
