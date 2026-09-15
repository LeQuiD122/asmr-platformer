"""
Box-projected UVs, shared by the rigged platform generators.

=== Why this exists at all ===

Roblox's SurfaceAppearance -- the thing that carries a ColorMap, NormalMap and
RoughnessMap, and the only route to a genuinely wet-looking honey -- reads the mesh's UV
map. None of the generators here ever made one, because until now nothing sampled a
texture. A SurfaceAppearance on a mesh with no UVs does not warn; it just renders wrong.

=== Why box projection rather than a real unwrap ===

These are slabs. Every face points almost exactly along one axis, so choosing a projection
per face by its dominant normal gives a distortion-free result for effectively all of them,
in about twenty lines, with no seams to place and no dependence on Blender's unwrapper
producing the same layout run to run. A real unwrap buys nothing here and costs
reproducibility.

=== Why the scale is in STUDS ===

Texture scale is expressed as "how many studs one tile of the texture covers", not as a
number of repeats. A 16 x 18 platform and a 12 x 10 one must show the same size of ripple
or they look like different materials -- which is exactly what a per-mesh repeat count
would give you.
"""

import bmesh


def box_project(mesh, studs_per_tile):
    """Give `mesh` a UV map projected per face along its dominant axis.

    The mesh is assumed to be authored in Blender units that equal studs.
    """
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.faces.ensure_lookup_table()

    uv_layer = bm.loops.layers.uv.verify()
    scale = 1.0 / float(studs_per_tile)

    for face in bm.faces:
        normal = face.normal
        ax, ay, az = abs(normal.x), abs(normal.y), abs(normal.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                # Top and bottom faces: project straight down. This is the case that
                # matters -- it is the surface you actually look at.
                u, v = co.x, co.y
            elif ax >= ay:
                u, v = co.y, co.z
            else:
                u, v = co.x, co.z
            loop[uv_layer].uv = (u * scale, v * scale)

    bm.to_mesh(mesh)
    bm.free()
    return mesh
