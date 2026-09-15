"""Every plan outline, run for real and checked for whether you can walk across it.

    python check_plan_shapes.py            # check, and print the contact sheet
    python check_plan_shapes.py --png      # also write plan_shapes.png

=== Why this runs the Lua instead of restating it ===

The other checkers parse the Luau and reproduce what it would do. That works for a layout
table, which is data. It does NOT work for a shape, which is a function: re-implementing
`heart` in Python gives you a second heart that drifts from the first, and the day they
disagree is the day the check starts lying.

So this loads PlanShapes.lua into an actual Lua interpreter and calls the real functions.
The Luau-only syntax -- type annotations and one if-expression -- is stripped first, which is
mechanical enough to be safe and is asserted afterwards by checking the shape table came out
the size the source says it is.

=== What it checks, and why each one has bitten ===

A shape decides where the floor is. On a granular platform the cubes ARE the floor and the
slab underneath does not collide, so anywhere the outline is empty is open air down to the
sea. That makes four things gameplay rather than styling:

  * ENTRY AND EXIT. A shape that does not reach both faces is a platform you cannot get onto
    or cannot leave. The heart's comment records this happening: the first version floated in
    the middle of the slab with no material at either end.
  * CROSSING. Reaching both faces is not enough if the two halves are not joined -- a shape
    can have floor at the entry, floor at the exit, and a gap between them.
  * LANE WIDTH, in studs rather than in normalised units, because 0.2 of a half-width is a
    comfortable path on one platform and a 2-stud beam on another. Measured against the
    actual width of every chunk that asks for the shape.
  * ISLANDS. Floor that is inside the outline but not reachable from the entry looks exactly
    like floor that is, right up until you jump to it.

The sample grid is not arbitrary: it is the cube grid the granular builder will actually use
for that chunk's size, so what this tests is the platform that gets built rather than an
idealised version of the shape.
"""
import argparse
import pathlib
import re
import sys
from collections import deque

import chunk_layout

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
PLAN_SHAPES = ROOT / "src" / "Shared" / "PlanShapes.lua"

# Mirrors SubRegionGrid.compute and the GRANULE_DIV in ChunkBuilder. These are the only two
# numbers restated rather than read, and both are checked against the source below.
CELL_SIZE_TARGET = 3.2
MIN_CELLS, MAX_CELLS = 2, 6

# A lane you can walk without falling off. A character is about 2 studs across the shoulders,
# so this is a little over one and a half characters -- narrow enough to be a real crossing
# and wide enough that missing it is a mistake rather than bad luck.
MIN_LANE_STUDS = 3.4

# How near the middle of an edge the floor has to come. Platforms meet face to face and you
# arrive walking down the centre line, so floor that only touches the entry edge out at one
# corner is not floor you can actually step onto.
EDGE_CENTRE = 0.30


# --------------------------------------------------------------- loading the real Lua

def to_lua(source: str) -> str:
    """Luau with the types taken out. Nothing here changes what any function computes."""
    out = []
    for line in source.splitlines():
        if line.startswith("export type "):
            continue
        # `local function f(u: number, v: number): boolean` and `function M.f(n: string?): T`
        head = re.match(r"^(\s*(?:local )?function [\w.]*)\((.*?)\)(\s*:\s*[\w?]+)?\s*$", line)
        if head:
            params = ", ".join(p.split(":")[0].strip() for p in head.group(2).split(",") if p.strip())
            out.append(f"{head.group(1)}({params})")
            continue
        # `local shapes: { [string]: Shape } = {`  ->  `local shapes = {`
        line = re.sub(r"^(\s*local \w+)\s*:\s*[^=]+=", r"\1 =", line)
        # `local x = if C then A else B`  ->  and/or. Safe only while the `then` branch is
        # never false or nil, which is true of the one use in this file (a number).
        line = re.sub(r"^(\s*local \w+ =) if (.+?) then (.+?) else (.+)$",
                      r"\1 (\2) and (\3) or (\4)", line)
        out.append(line)
    return "\n".join(out)


def load_shapes():
    """{name: callable(u, v) -> bool}, straight out of PlanShapes.lua."""
    try:
        from lupa import LuaRuntime
    except ImportError:
        sys.exit("check_plan_shapes needs a Lua interpreter: pip install lupa")

    source = PLAN_SHAPES.read_text(encoding="utf-8")
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().warn = lambda *_: None  # Roblox global, used by PlanShapes.get
    # Luau keeps math.atan2; Lua dropped it at 5.4 in favour of a two-argument math.atan,
    # which is the same function under a different name. Shimmed in the interpreter rather
    # than changed in the source, because the source has to stay valid Luau.
    lua.execute("math.atan2 = math.atan")
    module = lua.execute(to_lua(source))

    shapes = {name: fn for name, fn in module.shapes.items()}
    # The stripper is mechanical, but "mechanical" is a claim: if it silently dropped a
    # function the checks below would pass by not running. Count the registrations in the
    # source and insist the loaded table matches.
    registry = re.search(r"local shapes[^=]*=\s*\{(.*?)\n\}", source, re.S).group(1)
    expected = len(re.findall(r"^\t(\w+) = ", registry, re.M))
    assert len(shapes) == expected, f"stripper lost shapes: {len(shapes)} loaded, {expected} in source"
    return shapes


# --------------------------------------------------------------- sampling and walking

def cube_grid(width: float, length: float, div: int):
    """(across, along) cube counts for a platform of this size, as ChunkBuilder will build it."""
    cols = min(max(round(width / CELL_SIZE_TARGET), MIN_CELLS), MAX_CELLS)
    rows = min(max(round(length / CELL_SIZE_TARGET), MIN_CELLS), MAX_CELLS)
    return cols * div, rows * div


def sample(shape, across: int, along: int):
    """A grid of booleans at cube centres. Row 0 is the entry face, row -1 the exit."""
    field = []
    for iz in range(along):
        v = (iz + 0.5) / along * 2 - 1
        field.append([bool(shape((ix + 0.5) / across * 2 - 1, v)) for ix in range(across)])
    return field


def walk(field):
    """Cells reachable from the entry row, 4-connected."""
    along, across = len(field), len(field[0])
    seen = [[False] * across for _ in range(along)]
    queue = deque()
    for ix in range(across):
        if field[0][ix]:
            seen[0][ix] = True
            queue.append((0, ix))
    while queue:
        iz, ix = queue.popleft()
        for dz, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nz, nx = iz + dz, ix + dx
            if 0 <= nz < along and 0 <= nx < across and field[nz][nx] and not seen[nz][nx]:
                seen[nz][nx] = True
                queue.append((nz, nx))
    return seen


def narrowest(field, seen, width: float):
    """The thinnest row of reachable floor, in studs. This is the lane you have to walk."""
    across = len(field[0])
    thinnest = None
    for iz, row in enumerate(field):
        cells = sum(1 for ix in range(across) if row[ix] and seen[iz][ix])
        if cells == 0:
            continue
        studs = cells * width / across
        if thinnest is None or studs < thinnest:
            thinnest = studs
    return thinnest


def touches_centre(row) -> bool:
    across = len(row)
    return any(row[ix] and abs((ix + 0.5) / across * 2 - 1) <= EDGE_CENTRE for ix in range(across))


def inspect(shape, width: float, length: float, div: int):
    """Everything worth knowing about one shape at one platform size."""
    across, along = cube_grid(width, length, div)
    field = sample(shape, across, along)
    seen = walk(field)
    reached_exit = any(field[-1][ix] and seen[-1][ix] for ix in range(across))
    islands = sum(1 for iz in range(along) for ix in range(across) if field[iz][ix] and not seen[iz][ix])
    return {
        "field": field,
        "seen": seen,
        "entry": touches_centre(field[0]),
        "exit": touches_centre(field[-1]),
        "crosses": reached_exit,
        "lane": narrowest(field, seen, width) if reached_exit else None,
        "islands": islands,
        "fill": sum(sum(row) for row in field) / (across * along),
        "size": (across, along),
    }


# --------------------------------------------------------------- what the chunks ask for

def chunk_forms():
    """[(chunk id, form, width, length)] for every segment naming a form."""
    chunks, consts = chunk_layout.load()
    out = []
    for chunk_id, segments in chunks.items():
        for seg in segments:
            form = seg.get("form")
            if form:
                out.append((chunk_id, form,
                            seg.get("width", consts["PATH_WIDTH"]), seg.get("length", 0)))
    return out


BUILDER = ROOT / "src" / "Server" / "ChunkBuilder.server.lua"


def granule_shape() -> tuple:
    """(pieces per cell per axis, layers, budget) for the one and only cube size."""
    text = BUILDER.read_text(encoding="utf-8")

    def const(name):
        return int(re.search(r"^local " + name + r" = (\d+)", text, re.M).group(1))

    return const("GRANULE_DIV"), const("GRANULE_LAYERS"), const("GRANULE_BUDGET")


def material_sets() -> tuple:
    """(granular, bricked, capped) -- the three forms built out of parts."""
    text = BUILDER.read_text(encoding="utf-8")

    def names(table):
        line = re.search(r"^local " + table + r"[^=]*= \{(.*?)\}", text, re.M).group(1)
        return set(re.findall(r"(\w+) = true", line))

    return names("GRANULAR"), names("BRICKED"), names("CAPPED")


# --------------------------------------------------------------- output

GLYPH = {"floor": "#", "island": "!", "empty": "."}


def picture(result) -> list:
    rows = []
    for iz, row in enumerate(result["field"]):
        rows.append("".join(
            GLYPH["floor"] if cell and result["seen"][iz][ix]
            else GLYPH["island"] if cell
            else GLYPH["empty"]
            for ix, cell in enumerate(row)))
    return rows


def contact_sheet(shapes, div, per_row=4):
    """Every shape side by side at a common reference size, entry face at the bottom."""
    names = sorted(shapes)
    blocks = []
    for name in names:
        result = inspect(shapes[name], 18.0, 18.0, div)
        rows = picture(result)[::-1]  # entry at the bottom, the way you walk it
        label = name[:len(rows[0])].center(len(rows[0]))
        blocks.append([label] + rows)
    lines = []
    for start in range(0, len(blocks), per_row):
        group = blocks[start:start + per_row]
        for index in range(len(group[0])):
            lines.append("   ".join(block[index] for block in group))
        lines.append("")
    return lines


def write_png(panels, path, per_row=5):
    """A contact sheet. `panels` is [(label, sublabel, result)] already inspected.

    Entry face at the BOTTOM of every tile, so the picture is oriented the way you walk the
    platform rather than the way the array is indexed -- which is worth the four extra
    characters, because a wave read upside down looks like a different shape.
    """
    from PIL import Image, ImageDraw
    cell, pad, head = 9, 16, 26
    widest = max(len(r["field"][0]) for _, _, r in panels)
    tallest = max(len(r["field"]) for _, _, r in panels)
    tile_w, tile_h = widest * cell, tallest * cell + head
    cols = min(per_row, len(panels))
    rows = (len(panels) + per_row - 1) // per_row
    image = Image.new("RGB", (cols * (tile_w + pad) + pad, rows * (tile_h + pad) + pad), (22, 24, 30))
    draw = ImageDraw.Draw(image)
    for index, (label, sub, result) in enumerate(panels):
        field, seen = result["field"], result["seen"]
        along, across = len(field), len(field[0])
        ox = pad + (index % per_row) * (tile_w + pad)
        oy = pad + (index // per_row) * (tile_h + pad)
        draw.text((ox, oy), label, fill=(226, 231, 242))
        draw.text((ox, oy + 12), sub, fill=(128, 136, 154))
        for iz in range(along):
            for ix in range(across):
                if not field[iz][ix]:
                    continue
                colour = (232, 236, 244) if seen[iz][ix] else (214, 96, 72)
                y = oy + head + (along - 1 - iz) * cell
                draw.rectangle([ox + ix * cell, y, ox + ix * cell + cell - 2, y + cell - 2], fill=colour)
    image.save(path)
    return path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--png", action="store_true", help="also write plan_shapes.png")
    args = parser.parse_args()

    shapes = load_shapes()
    div, layers, budget = granule_shape()
    problems = []

    # ---- every shape, at a reference size, so unused ones are still held to the contract
    for name in sorted(shapes):
        result = inspect(shapes[name], 18.0, 18.0, div)
        if not result["entry"]:
            problems.append(f"{name}: no floor within {EDGE_CENTRE} of the middle of the entry "
                            "face -- you cannot step onto this platform.")
        if not result["exit"]:
            problems.append(f"{name}: no floor within {EDGE_CENTRE} of the middle of the exit "
                            "face -- you cannot leave this platform.")
        elif not result["crosses"]:
            problems.append(f"{name}: has floor at both faces but they are NOT JOINED -- the "
                            "platform is split, and the far half is unreachable.")
        if result["islands"]:
            problems.append(f"{name}: {result['islands']} cube(s) of floor cannot be reached "
                            "from the entry. Floor you can see and cannot get to reads as a bug.")

    # ---- and every shape a chunk actually asks for, at that chunk's real size
    # CAPPED IS NOT IN THIS LIST ANY MORE. A keypad's form used to name a PlanShapes
    # outline and skip the caps outside it; it now names a MESH, because cutting caps out of
    # a plate that stays a full rectangle changed nothing about the platform and only left
    # gaps in a keypad. Its forms belong to check_chunk_forms with the other rigged ones.
    granular, bricked, _capped = material_sets()
    chunks, consts = chunk_layout.load()
    built = []
    heaviest = []
    for chunk_id, form, width, length in chunk_forms():
        segment = next((s for s in chunks.get(chunk_id, []) if s.get("form") == form), {})
        material = segment.get("material")
        if material in bricked:
            # ONE BRICK PER CELL, so the outline is cut at cell resolution -- six steps
            # across where soap gets eighteen. Same shape, a quarter of the detail, and a
            # lane that is a whole cell wide or nothing.
            here = 1
        elif material in granular:
            here = div
        else:
            # `form` MEANS TWO DIFFERENT THINGS depending on the material, which is worth
            # knowing before reading a warning from here. On a parts-built platform it names
            # a function in PlanShapes and cuts the field. On a rigged one it names an FBX
            # variant -- bubble wrap's "giant" is a mesh, not an outline, and demanding it be
            # a registered shape reported a chunk that has never been wrong.
            continue
        if form not in shapes:
            problems.append(f"{chunk_id}: form '{form}' is not a shape in PlanShapes, and "
                            f"{material} is built out of parts -- so it silently falls back "
                            "to the rounded rectangle and builds as a plain platform.")
            continue
        result = inspect(shapes[form], width, length, here)
        built.append((chunk_id, f"{form} / {material} / {result['size'][0]} across", result))
        # WHAT IT COSTS IN PARTS, which is the check that did not exist when a grain profile
        # put 2576 anchored cubes on one hexagon. The outline is doing the work here: a shape
        # that removes half the platform halves the bill, so cutting a hole is cheaper than
        # not cutting one, which is a pleasant thing to be true.
        if material in granular:
            parts = sum(sum(row) for row in result["field"]) * layers
            heaviest.append((parts, chunk_id))
            if parts > budget:
                problems.append(
                    f"{chunk_id}: '{form}' on a {width:g} x {length:g} {material} platform "
                    f"spawns {parts} cube parts, over the {budget} budget. Every one is an "
                    "anchored Part, and this is what laggy looks like before you launch it.")

        if result["lane"] is not None and result["lane"] < MIN_LANE_STUDS:
            problems.append(
                f"{chunk_id}: '{form}' on a {width:g} x {length:g} {material} platform narrows to "
                f"{result['lane']:.1f} studs, under the {MIN_LANE_STUDS} a character can walk. "
                "Widen the platform or pick a fuller shape.")

    print("\n".join(contact_sheet(shapes, div)))
    print(f"{len(shapes)} shapes, {len(chunk_forms())} chunk segments using one")
    if heaviest:
        worst = sorted(heaviest, reverse=True)[:3]
        print("heaviest granular platforms, in cube parts (budget %d): %s"
              % (budget, ", ".join(f"{cid} {n}" for n, cid in worst)))
    if args.png:
        # TWO PICTURES, because they answer different questions. The first is the vocabulary:
        # every outline at one size, so they can be compared with each other. The second is
        # what actually gets built, at the resolution each chunk really uses -- which is the
        # only place the difference between eighteen steps of soap and six of lego shows.
        vocab = [(name, f"{cube_grid(18.0, 18.0, div)[0]} across", inspect(shapes[name], 18.0, 18.0, div))
                 for name in sorted(shapes)]
        print("wrote", write_png(vocab, HERE / "plan_shapes.png"))
        print("wrote", write_png(built, HERE / "chunk_shapes.png", per_row=4))

    if problems:
        print("\nPROBLEMS:")
        for problem in problems:
            print("  " + problem)
        return 1
    print("every shape is enterable, crossable and wide enough.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
