"""
Creamy keyboard: a RIGGED field of keycaps, one bone per key.

    "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe" --background --python gen_keyboard.py

Architecturally this is bubble wrap's cousin -- a lattice of discrete things on a plate,
one bone each, driven down by whatever is standing on them -- and the one place it differs
is the place the whole material lives.

A BUBBLE COLLAPSES; A KEY TRAVELS. Bursting a pocket changes its SHAPE: the dome inverts
onto the film, so its vertices are weighted by how far up the dome they sit and the rim
never moves. A keycap is rigid. It goes down as one piece, stays the same shape the whole
way, stops, and comes back. So every vertex of a cap carries weight 1.0 from its own bone
and nothing is shared -- which is also why this rig is far cheaper than the sheet's.

"Creamy" is a keyboard word and it means a specific thing: smooth travel, no scratch, and
a damped bottom-out with no ping and no bounce. That is a MOTION property, so most of it
lives in DeformationRenderer -- but the geometry has to earn it too. Keys are deeply
sculpted (dished tops, real taper) so the light moves across them as they sink, and the
gaps are wide enough that a sinking key reads against its neighbours instead of
disappearing into a texture.
"""

import bmesh
import math
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import uv_project

OUT_DIR = r"C:\Users\Arsenii\Downloads\asmr-platformer-implementation_1\RobloxProject\meshes"

# ChunkBuilder's TILE_THICKNESS: the layer between the slab's top face and the walkable
# plane. Everything below has to fit inside it.
TILE_LAYER = 0.9

# THE KEY PITCH IS A GAMEPLAY NUMBER, not a styling one.
#
# A character is about 2 studs across. At a real keyboard's proportions -- keys a finger
# wide -- a platform this size would carry a hundred tiny caps, and stepping on it would
# depress a dozen at once: the surface would read as a texture that shimmers rather than
# as keys you are pressing. At 2.4 a footfall lands on one or two, which is what makes the
# material legible AND what makes the sound design possible later, since one step should
# be one thock.
# THE LATTICE IS FITTED TO THE SLAB, not stamped onto it at a fixed pitch.
#
# It was a fixed 2.4 anchored to the mesh origin, copied from the bubble sheet where that
# rule earns its keep: pockets have to line up across the pieces of a tapered run, so every
# sheet must put them at the same absolute offsets whatever its width. The keyboard has no
# such neighbour -- it is one untapered slab -- so all that rule bought here was a field of
# small caps marooned in a wide empty bezel, which is exactly what it looked like.
#
# Fitting instead: pick a target cap size, work out how many fit inside the bezel, then
# divide the space by that count. The keys come out as large as they can be, evenly spread,
# and the border is a bezel rather than leftover.
KEY_TARGET = 2.8           # the cap size to aim for; actual is derived per slab
GAP = 0.35                 # gutter between caps, held constant so the grid reads regular
# A NARROW BEZEL. It was 0.75, which on a 16-stud board is nearly a tenth of the width
# given over to empty plate on each side -- the reference boards keep barely a cap's
# thickness of case around the outermost row.
BEZEL = 0.30               # case edge kept clear of caps
CORNER = 0.34              # cap corner radius
CORNER_STEPS = 5           # chords per corner quadrant

# Cap height, and the thin plate under it.
#
# The cap top IS the walkable plane, so this is also how far a key travels before it
# bottoms out. Both together have to fit inside TILE_LAYER (0.9): 0.58 + 0.30 = 0.88.
# THICKER CAPS, PAID FOR BY A THINNER PLATE. Both together must fit inside TILE_LAYER
# (0.9), and the plate only has to be visible as a rim between cap and case -- every stud
# it gives up goes into the part you actually see. 0.75 + 0.15 = 0.90 exactly.
KEY_HEIGHT = 0.75
PLATE_THICK = 0.15
PLATE_TOP = -KEY_HEIGHT    # plate top, in mesh space where z = 0 is the walkable plane

# Cap taper: the top face as a fraction of the bottom. Real keycaps taper hard; this is
# what stops a field of them reading as a tiled floor with grooves scratched in it,
# because the taper puts a lit sloping band around every single key.
TAPER = 0.78

# How far the top face dishes in the middle. Small, but it is the difference between a cap
# and a block: a flat top takes one flat highlight, a dished one takes a gradient that
# moves as the key sinks.
DISH = 0.12

# Plan corner radius for the chassis, matching the other rigged materials.
PLATE_CORNER = 0.85
PLATE_CORNER_STEPS = 6


# ===================================================================== the atlas
#
# EVERY CAP GETS ITS OWN PATCH OF TEXTURE, and that is the only way legends are possible.
#
# The UVs used to be box-projected at one tile per key, which is right for a material whose
# surface is the same everywhere -- plastic grain, film wrinkles, sand. It cannot carry a
# legend, because every key samples the SAME tile and would therefore show the same letter.
# So the caps are laid out into a grid of cells instead: cap n takes cell n, and one
# texture can hold a different letter and a different cap colour in each.
#
# 6 x 6 = 36 cells against 25 keys on the current board. Spare cells cost nothing and mean
# a wider slab does not immediately start repeating itself.
#
# gen_pbr.py imports this constant rather than keeping its own copy: the map and the mesh
# have to agree about the grid exactly, and two numbers that must match are one number.
ATLAS = 6

# How far into a cell the cap's TOP face is mapped. The band outside it is plain cap colour
# with no legend on it, and the cap's SIDES are mapped into that band -- so the walls take
# the key's colour without dragging a letter down them.
TOP_INSET = 0.18


def cell_origin(index):
    """Bottom-left corner of cell `index`, in UV space."""
    slot = index % (ATLAS * ATLAS)
    return (slot % ATLAS) / ATLAS, (slot // ATLAS) / ATLAS


def assign_uvs(mesh, face_info, key_half):
    """Per-LOOP UVs, written by hand.

    Per loop rather than per vertex, because a cap's bottom ring is shared between its
    side walls and nothing else -- but the top ring belongs to both the walls and the top
    face, and those two need different UVs from the same vertex. Blender stores UVs on
    loops (face corners) precisely so that is expressible.
    """
    layer = mesh.uv_layers.new(name="UVMap") if not mesh.uv_layers else mesh.uv_layers.active
    step = 1.0 / ATLAS
    span = step * (1.0 - 2.0 * TOP_INSET)

    for poly in mesh.polygons:
        kind, centre, index = face_info[poly.index]
        u0, v0 = cell_origin(index)
        for loop_index in poly.loop_indices:
            if kind == "top":
                co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
                fx = (co.x - centre[0]) / key_half  # -1 .. 1 across the cap
                fy = (co.y - centre[1]) / key_half
                layer.data[loop_index].uv = (
                    u0 + step * TOP_INSET + span * (fx * 0.5 + 0.5),
                    v0 + step * TOP_INSET + span * (fy * 0.5 + 0.5),
                )
            else:
                # A small patch inside the plain border. Not a single point: a degenerate
                # UV triangle has no area for the sampler to filter over, which some
                # drivers render as a hard speckle rather than a flat colour.
                layer.data[loop_index].uv = (u0 + step * 0.05, v0 + step * 0.05)


def clear_scene():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for block in (bpy.data.meshes, bpy.data.armatures):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


_SLAB_DEPTH = None


def _slab_depth():
    """ChunkBuilder's SLAB_THICKNESS, read rather than typed: the chassis has to reach the
    bottom of the slab it hides, and a hardcoded copy would leave a stripe of bare
    concrete the moment that constant moved."""
    global _SLAB_DEPTH
    if _SLAB_DEPTH is None:
        import chunk_layout

        _, _, constants = chunk_layout.layout_all()
        _SLAB_DEPTH = constants["SLAB_THICKNESS"]
    return _SLAB_DEPTH


def rounded_rect(half_x, half_y, radius, steps):
    """Points anticlockwise around a rounded rectangle."""
    radius = min(radius, half_x, half_y)
    points = []
    corners = (
        (half_x - radius, half_y - radius, 0.0),
        (-(half_x - radius), half_y - radius, math.pi / 2),
        (-(half_x - radius), -(half_y - radius), math.pi),
        (half_x - radius, -(half_y - radius), 3 * math.pi / 2),
    )
    for cx, cy, base in corners:
        for s in range(steps + 1):
            angle = base + (math.pi / 2) * (s / steps)
            points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return points


def _fit(span):
    """How many caps fit along one axis inside the bezel, and how wide each one is.

    SEARCHED, not rounded. Rounding a target pitch picks a count and accepts whatever cap
    size falls out, which is how the field ended up with 0.5 studs of unclaimed space on
    one axis. Trying every count and keeping the one whose derived cap lands closest to the
    target means the caps always divide the space exactly -- the leftover is zero by
    construction rather than by luck.
    """
    usable = span - 2.0 * BEZEL
    best = None
    for count in range(1, 13):
        key = (usable - GAP * (count - 1)) / count
        if key <= 0.6:
            break
        score = abs(key - KEY_TARGET)
        if best is None or score < best[0]:
            best = (score, count, key)
    _score, count, key = best
    return count, key


def layout(size_x, size_z):
    """Cap centres and cap size for a slab, centred on it.

    SQUARE CAPS, using the smaller of the two axes' derived sizes. Solving each axis
    independently gives a slightly better fill and rectangular keys, and a keyboard whose
    caps are visibly wider than they are deep looks like a mistake rather than a design --
    every real cap in the reference photographs is square.
    """
    count_x, key_x = _fit(size_x)
    count_z, key_z = _fit(size_z)
    key = min(key_x, key_z)
    pitch = key + GAP
    centres = []
    for j in range(count_z):
        for i in range(count_x):
            centres.append((
                (i - (count_x - 1) / 2.0) * pitch,
                (j - (count_z - 1) / 2.0) * pitch,
            ))
    return centres, key


def build_surface(size_x, size_z, centres, key, name):
    """The chassis, plus one rigid cap per centre."""
    hx, hz = size_x / 2.0, size_z / 2.0
    key_half = key / 2.0
    # A THIN PLATE, not a box down to the bottom of the slab.
    #
    # The mesh used to enclose the whole slab, which meant the mesh WAS the platform and
    # the case could only ever be the same colour as the caps. Keeping it to a plate lets
    # ChunkBuilder treat this material as an OVERLAY: the slab stays visible underneath and
    # carries `baseColor`, so the board is a coloured case with cream caps on it -- two
    # tones out of one skinned mesh, which is otherwise impossible since a MeshPart has a
    # single Color.
    z_bottom = PLATE_TOP - PLATE_THICK

    verts, faces = [], []
    owner = {}      # vertex index -> (key centre, weight)
    static = []     # indices pinned to Root
    face_info = {}  # face index -> (kind, cap centre, atlas cell)

    # --- the chassis: a closed box under the keys ---
    plan = rounded_rect(hx, hz, PLATE_CORNER, PLATE_CORNER_STEPS)
    n_plan = len(plan)
    top = len(verts)
    for x, y in plan:
        verts.append((x, y, PLATE_TOP))
    bottom = len(verts)
    for x, y in plan:
        verts.append((x, y, z_bottom))
    for index in range(top, len(verts)):
        static.append(index)

    faces.append(tuple(range(top, top + n_plan)))
    faces.append(tuple(reversed(range(bottom, bottom + n_plan))))
    for k in range(n_plan):
        nk = (k + 1) % n_plan
        faces.append((top + k, bottom + k, bottom + nk, top + nk))
    plate_faces = len(faces)
    # The plate takes the LAST cell, which the map leaves plain: the case is a surface, not
    # a key, and a legend smeared across it would be nonsense.
    for index in range(plate_faces):
        face_info[index] = ("plate", (0.0, 0.0), ATLAS * ATLAS - 1)

    # --- the caps ---
    for cap_index, (cx, cy) in enumerate(centres):
        base = rounded_rect(key_half, key_half, CORNER, CORNER_STEPS)
        n = len(base)

        low = len(verts)
        for x, y in base:
            index = len(verts)
            verts.append((cx + x, cy + y, PLATE_TOP))
            owner[index] = ((cx, cy), 1.0)

        high = len(verts)
        for x, y in base:
            index = len(verts)
            verts.append((cx + x * TAPER, cy + y * TAPER, 0.0))
            owner[index] = ((cx, cy), 1.0)

        # The dished top: a fan to a centre vertex sunk by DISH, with the ring itself
        # eased down slightly toward the middle so the dish is a curve rather than a cone.
        centre_index = len(verts)
        verts.append((cx, cy, -DISH))
        owner[centre_index] = ((cx, cy), 1.0)

        for k in range(n):
            nk = (k + 1) % n
            face_info[len(faces)] = ("side", (cx, cy), cap_index)
            faces.append((low + k, low + nk, high + nk, high + k))
            face_info[len(faces)] = ("top", (cx, cy), cap_index)
            faces.append((high + k, high + nk, centre_index))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    # Recalc picks a direction; it does not pick the right one. The chassis top is the one
    # face with a known answer, so ask it and flip the lot if it disagrees -- the same
    # check the sand surface needed after its topology changed.
    bm.normal_update()
    if bm.faces[0].normal.z < 0.0:
        bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    # Smooth on the cap walls so the taper catches a gradient, FLAT on the chassis and on
    # the top faces: a keycap's top is a real plane with a real edge, and smoothing it into
    # the walls rounds off the very silhouette that says "key".
    for index, poly in enumerate(mesh.polygons):
        poly.use_smooth = index >= plate_faces and len(poly.vertices) == 4

    return obj, owner, static, plate_faces, face_info


def build_armature(centres, rig_name):
    arm_data = bpy.data.armatures.new(rig_name)
    arm_obj = bpy.data.objects.new(rig_name, arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    root = arm_data.edit_bones.new("Root")
    root.head = (0.0, 0.0, 0.0)
    root.tail = (0.0, 0.0, 1.0)

    names = {}
    for index, (cx, cy) in enumerate(centres, start=1):
        name = f"Key_{index}"
        bone = arm_data.edit_bones.new(name)
        # Head at this cap's own top, pointing up: the renderer drives these in plain world
        # axes, so every bone has to share the mesh's orientation.
        bone.head = (cx, cy, 0.0)
        bone.tail = (cx, cy, 0.4)
        bone.parent = root
        bone.use_connect = False
        names[(cx, cy)] = name

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj, names


def assign_weights(obj, arm_obj, owner, static_indices, names):
    """ONE bone per vertex at full weight.

    Deliberately not the graded weighting the bubble sheet uses. There a pocket has to
    collapse INTO the film it is sealed to, so its vertices are weighted by height and the
    rim stays put. A keycap is a rigid body on a stem: every part of it travels the same
    distance, and any share below 1.0 would stretch the cap as it sank.
    """
    groups = {name: obj.vertex_groups.new(name=name) for name in names.values()}
    root_group = obj.vertex_groups.new(name="Root")

    static = set(static_indices)
    for index in range(len(obj.data.vertices)):
        entry = owner.get(index)
        if index in static or entry is None:
            root_group.add([index], 1.0, "REPLACE")
            continue
        centre, share = entry
        groups[names[centre]].add([index], share, "REPLACE")

    modifier = obj.modifiers.new("Armature", "ARMATURE")
    modifier.object = arm_obj
    obj.parent = arm_obj


def validate(obj, size_x, size_z, key_count):
    ok = True
    verts = obj.data.vertices

    top = max(v.co.z for v in verts)
    if top > 1e-4:
        print(f"    !! a vertex sits {top:.3f} above the walkable plane")
        ok = False

    width = max(v.co.x for v in verts) * 2.0
    depth = max(v.co.y for v in verts) * 2.0
    if width > size_x + 1e-3 or depth > size_z + 1e-3:
        print(f"    !! mesh is {width:.2f} x {depth:.2f}, larger than its {size_x:g} x {size_z:g} slab")
        ok = False

    groups = len(obj.vertex_groups) - 1  # minus Root
    if groups != key_count:
        print(f"    !! {groups} vertex groups for {key_count} keys")
        ok = False

    if key_count == 0:
        print("    !! no keys fitted on this slab at all")
        ok = False

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    degenerate = sum(1 for f in bm.faces if f.calc_area() < 1e-7)
    bm.free()
    if degenerate:
        print(f"    !! {degenerate} degenerate faces")
        ok = False

    return ok


def export_fbx(mesh_obj, arm_obj, filename):
    # 2.4 studs per tile: ONE KEY PER TILE, deliberately. The map carries the fine plastic
    # grain of a single cap, so matching the tile to the pitch puts that grain at the same
    # scale on every key instead of drifting across the field.
    # NO BOX PROJECTION HERE. Every other rigged mesh in this project calls
    # uv_project.box_project at export, and doing so would overwrite the atlas layout
    # assign_uvs just built -- silently, leaving a keyboard with the same letter on all
    # twenty-five keys and no error anywhere. UVs for this material are authored, not
    # projected.

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, filename)
    for obj in bpy.data.objects:
        obj.select_set(False)
    mesh_obj.select_set(True)
    arm_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        global_scale=0.01,
        add_leaf_bones=False,
        bake_anim=False,
        axis_forward="-Z",
        axis_up="Y",
        object_types={"ARMATURE", "MESH"},
        # EDGE, not FACE: per-polygon smooth flags only survive the FBX round trip as edge
        # smoothing data. Exported as FACE the caps arrive fully flat shaded.
        mesh_smooth_type="EDGE",
    )
    print(f"  exported {os.path.basename(path)}")


def mesh_name(size_x, size_z):
    return "Keyboard_Field_{:g}x{:g}".format(size_x, size_z).replace(".", "_")


def slab_sizes():
    """Every distinct creamy keyboard slab, READ FROM ChunkBuilder rather than typed here.

    A rig is matched to a slab by exact size, and a slab with no rig falls back to per-tile
    meshes in complete silence. Hardcoding the list means a chunk edit that resizes a
    keyboard slab breaks the material with no error anywhere.
    """
    import chunk_layout

    layouts, _, _ = chunk_layout.layout_all()
    sizes = set()
    for boxes in layouts.values():
        for box in boxes:
            if box.material == "CreamyKeyboard":
                sizes.add((round(box.sx, 2), round(box.sz, 2)))
    return sorted(sizes)


def main():
    sizes = slab_sizes()
    print(f"  {len(sizes)} distinct creamy keyboard slab sizes in ChunkBuilder\n")

    entries, all_ok = [], True
    for size_x, size_z in sizes:
        clear_scene()
        name = mesh_name(size_x, size_z)
        centres, key = layout(size_x, size_z)
        obj, owner, static, _plate_faces, face_info = build_surface(size_x, size_z, centres, key, name)
        arm, names = build_armature(centres, name + "_Rig")
        assign_weights(obj, arm, owner, static, names)
        ok = validate(obj, size_x, size_z, len(centres))
        all_ok = all_ok and ok

        tris = sum(len(poly.vertices) - 2 for poly in obj.data.polygons)
        zs = [v.co.z for v in obj.data.vertices]
        low, high = min(zs), max(zs)
        print(f"  {name}: {len(centres)} keys of {key:.2f}, {tris} tris, {'valid' if ok else 'INVALID'}")
        assign_uvs(obj.data, face_info, key / 2.0)
        export_fbx(obj, arm, name + ".fbx")
        entries.append(
            f"		{{ sizeX = {size_x:g}, sizeZ = {size_z:g}, "
            f"meshHeight = {high - low:.2f}, surfaceOffset = {-(low + high) / 2.0:.2f}, "
            f'mesh = "{name}" }},'
        )

    print("")
    print("  ChunkBuilder SKINNED_PLATFORMS entry:")
    print("	CreamyKeyboard = {")
    for entry in entries:
        print(entry)
    print("	},")
    print("")
    print(f"  KEY_HEIGHT = {KEY_HEIGHT}  (DeformationRenderer presses bones down by a fraction of this)")
    print("")
    print("Done." if all_ok else "!! a mesh failed validation -- DO NOT import.")


if __name__ == "__main__":
    main()
