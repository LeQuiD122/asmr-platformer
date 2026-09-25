"""
Reads the chunk recipes out of ChunkBuilder.server.lua and reproduces the slab
layout they describe. Pure Python, no bpy: render_chunk_forms.py draws it and
check_chunk_forms.py asserts it, and only the first of those needs Blender.

IT PARSES THE LUAU RATHER THAN RESTATING IT. A second copy of the segment tables
is worth nothing the first time somebody edits one side and not the other -- both
the preview and the checker would go on describing geometry that no longer
exists, confidently and wrongly. The parser is deliberately strict and covers
only the subset the tables actually use, because a silently skipped field is
precisely the failure these tools exist to catch.

What it does NOT model, none of which affects layout: sub-region tiles, tile
meshes, the skinned honey mesh, corner bevels, and the stable cap plate. Slabs
only. Boxes come back as

    Box(x, y, z, sx, sy, sz, material, pitch)

in ROBLOX axes -- X lateral, Y up, Z along the route -- where (x, y, z) is the
slab CENTRE, matching what makePlatform is handed, and `pitch` is the rotation
about X that only the ramp uses.
"""

import math
import os
import re
from collections import namedtuple

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.normpath(os.path.join(HERE, "..", "src", "Server", "ChunkBuilder.server.lua"))

Box = namedtuple("Box", "x y z sx sy sz material pitch form")
# `form` defaults to None so the layout builders that never shape anything -- the
# junction, the shelves, the ramp -- keep their existing call signatures. Only the
# generic platform path fills it in.
Box.__new__.__defaults__ = (None,)

# Build order, and the order both tools present them in.
CHUNK_ORDER = [
    "S1_Straight", "S2_Junction", "P1_HoneyCorridor", "P2_ButterWaxCurve",
    "P3_KineticSandRamp", "P4_PaceChain_H_KS", "R1_SlimeLaunch", "R2_SoapBridge",
    "R3_BubbleWrapStairs", "R4_SoapStar", "R5_SoapPebbles", "R6_SoapHeart",
    "R7_SandTurtle", "R8_BubbleWrapGiant",
    # The shaped set: six soap outlines, two lego ones cut at brick resolution, and two
    # keypad arrangements. All ten cost one word each in the chunk table.
    "R18_SoapRing", "R19_SoapWave", "R20_SoapBone", "R21_SoapCrescent",
    "R31_SoapLeaf",
    "R23_LegoCross", "R24_LegoRing", "R29_LegoBone", "R30_LegoCrescent",
    "P14_ButtonDense", "P15_ButtonDome",
    # The sculpted rigs: a shape in the mesh rather than in the plan.
    "P18_HoneyComb", "P19_HoneyPool", "R37_SlimeBlister", "R38_SlimeChannel",
    "R32_LavaVent", "R33_ChocolateSwirl", "R34_SnowDrift",
    "P17_ClayTerrace", "R35_CharcoalSpine", "R36_CloudSwell",
    "P5_KeyboardRun",
    # Built from the imported asset packs: existing rigs, dressed by ChunkProps.
    "P20_NeedohField", "P21_KeyboardDusk", "P22_KeyboardMint", "P23_KeyboardLava",
    "P24_ButterBlocks",
    "P25_ButterStick",
    "P26_NeedohBoulders",
    "P27_NeedohGrid",
    "P28_NeedohDrift",
    "R9_IceCrack", "P6_JelloSoda", "P7_LambsEar",
    # The Sunken City's jellyfish bells.
    "R39_JellyfishHop", "P29_JellyfishBloom",
    "P8_Foam", "P9_LightSwitches", "P10_ClayPress",
    "R10_LegoStuds", "R11_CharcoalSnap", "R12_ChocolateMelt", "R13_CloudSink",
    "R14_ChocolateSnap",
    "P11_SaltFlat", "P12_ButtonPad",
    "R15_LavaCrust", "R16_Oobleck", "R17_MeltingSnow",
    "C1_SlimeToPace", "C2_PaceToStable",
    "C3_SoapWithWideLanding", "C4_BubbleWrapToStable",
]

# THIS LIST IS HAND-MAINTAINED, and that is a trap worth naming: adding a chunk to
# ChunkBuilder and forgetting it here means the checker reports "all N chunks pass"
# while never having looked at the new one. The count in that message is the number
# of entries below, not the number of chunks that exist.
#
# `defined_chunks()` below is the guard. ChunkDefinitions.lua had the same trap in its
# AllIds list and it bit for real -- five chunks were defined, laid out, sequenced into a
# level and never built, because the one hand-written list that decides what gets built
# had not been updated. That list is derived now; this one still cannot be, because its
# ORDER is what the render grid uses. So it gets checked instead.


def defined_chunks():
    """Every chunk declared in ChunkDefinitions.lua, straight out of the source."""
    path = os.path.normpath(os.path.join(HERE, "..", "src", "Shared", "ChunkDefinitions.lua"))
    with open(path, encoding="utf-8") as handle:
        return set(re.findall(r"^ChunkDefinitions\.([A-Za-z0-9_]+) = \{", handle.read(), re.M))


def check_order_covers_definitions():
    """Raises if a chunk exists that CHUNK_ORDER has never heard of."""
    missing = sorted(defined_chunks() - set(CHUNK_ORDER))
    if missing:
        raise SystemExit(
            "chunk_layout.CHUNK_ORDER is missing "
            + ", ".join(missing)
            + " -- every check below would have passed without looking at them."
        )

SPECIAL = ("P3_KineticSandRamp", "S2_Junction")


# ---------------------------------------------------------------- Lua parsing

def tokenize(text, start):
    """Tokens from `start` onward. Unknown punctuation becomes an opaque 'op' so
    the tokenizer never trips over Luau syntax past the table we care about; the
    parser stops at the matching brace long before reaching any of it."""
    tokens = []
    i, n = start, len(text)
    while i < n:
        c = text[i]
        if c in " \t\r\n":
            i += 1
        elif text.startswith("--", i):
            if text.startswith("--[[", i):
                end = text.find("]]", i)
                i = n if end < 0 else end + 2
            else:
                end = text.find("\n", i)
                i = n if end < 0 else end + 1
        elif c in "{},=":
            tokens.append((c, c))
            i += 1
        elif c in "\"'":
            quote, j, buf = c, i + 1, []
            while j < n and text[j] != quote:
                if text[j] == "\\":
                    buf.append(text[j + 1])
                    j += 2
                else:
                    buf.append(text[j])
                    j += 1
            tokens.append(("str", "".join(buf)))
            i = j + 1
        elif c.isdigit() or (c == "." and i + 1 < n and text[i + 1].isdigit()):
            j = i
            while j < n and (text[j].isdigit() or text[j] == "."):
                j += 1
            tokens.append(("num", float(text[i:j])))
            i = j
        elif c.isalpha() or c == "_":
            j = i
            while j < n and (text[j].isalnum() or text[j] == "_"):
                j += 1
            tokens.append(("name", text[i:j]))
            i = j
        else:
            tokens.append(("op", c))
            i += 1
    return tokens


class Parser:
    def __init__(self, tokens, consts):
        self.tokens = tokens
        self.pos = 0
        self.consts = consts

    def peek(self):
        return self.tokens[self.pos] if self.pos < len(self.tokens) else (None, None)

    def take(self, kind=None):
        tok = self.peek()
        if kind is not None and tok[0] != kind:
            raise ValueError("expected %s, got %r at token %d" % (kind, tok, self.pos))
        self.pos += 1
        return tok

    def value(self):
        kind, val = self.peek()
        if kind == "op" and val == "-":
            self.take()
            return -self.value()
        if kind in ("num", "str"):
            self.take()
            return val
        if kind == "name":
            self.take()
            if val in ("true", "false"):
                return val == "true"
            if val not in self.consts:
                raise ValueError("unknown constant %r in the chunk table" % val)
            return self.consts[val]
        if kind == "{":
            return self.table()
        raise ValueError("unexpected token %r at %d" % ((kind, val), self.pos))

    def table(self):
        """A Lua table constructor: a dict when it has named fields, a list when
        positional. The chunk tables never mix the two, and mixing is an error
        rather than something to guess at."""
        self.take("{")
        named, positional = {}, []
        while True:
            kind, val = self.peek()
            if kind == "}":
                self.take()
                break
            if kind == ",":
                self.take()
                continue
            if kind == "name" and self.tokens[self.pos + 1][0] == "=":
                self.take()
                self.take("=")
                named[val] = self.value()
            else:
                positional.append(self.value())
        if named and positional:
            raise ValueError("chunk table mixes named and positional fields")
        return named if named or not positional else positional


def parse_constants(text):
    """Numeric top-level constants. Two forms appear: a single `local NAME = n`,
    and the paired `local A, B = v, v`.

    `(?:--.*)?` matters more than it looks: most of these carry a trailing
    comment (PATH_WIDTH is `= 16 -- lateral, X`), and an anchored pattern without
    it matches nothing at all, which then surfaces far away as a KeyError on a
    constant that is plainly right there in the file."""
    consts = {}
    tail = r"[ \t]*(?:--.*)?$"
    for name, raw in re.findall(r"^local ([A-Z][A-Z0-9_]*)\s*=\s*(-?[\d.]+)" + tail, text, re.M):
        consts[name] = float(raw)
    for a, b, va, vb in re.findall(
        r"^local ([A-Z][A-Z0-9_]*),\s*([A-Z][A-Z0-9_]*)\s*=\s*([\w.]+),\s*([\w.]+)" + tail, text, re.M
    ):
        for name, raw in ((a, va), (b, vb)):
            consts[name] = float(raw) if re.match(r"^-?[\d.]+$", raw) else consts[raw]
    # Derived in the Luau by expression rather than literal, so restated here.
    consts["SURFACE_Y"] = consts["SLAB_THICKNESS"] / 2.0 + consts["TILE_THICKNESS"]
    return consts


def load_skinned():
    """{material: [spec, ...]} out of ChunkBuilder's SKINNED_PLATFORMS.

    Used to check that every slab of a rigged material actually has a rig its size.
    A miss is silent in game: skinnedSpecFor returns nil, the platform quietly falls
    back to per-tile meshes, and you get the grid on some platforms and not others."""
    with open(SOURCE, "r", encoding="utf-8") as handle:
        text = handle.read()
    consts = parse_constants(text)
    marker = re.search(r"local SKINNED_PLATFORMS[^=]*=\s*\{", text)
    if not marker:
        raise ValueError("could not find SKINNED_PLATFORMS in " + SOURCE)
    return Parser(tokenize(text, marker.end() - 1), consts).table()


def load():
    """(chunk recipes, constants) straight out of the Luau source."""
    with open(SOURCE, "r", encoding="utf-8") as handle:
        text = handle.read()
    consts = parse_constants(text)
    marker = re.search(r"local LinearChunks[^=]*=\s*\{", text)
    if not marker:
        raise ValueError("could not find the LinearChunks table in " + SOURCE)
    chunks = Parser(tokenize(text, marker.end() - 1), consts).table()
    missing = [c for c in CHUNK_ORDER if c not in chunks and c not in SPECIAL]
    if missing:
        raise ValueError("no recipe parsed for: " + ", ".join(missing))
    return chunks, consts


# ------------------------------------------------------- layout (mirrors Luau)

def taper_pieces(seg, length, C):
    width = seg.get("width", C["PATH_WIDTH"])
    end = seg.get("widthEnd")
    if end is None or abs(end - width) <= 0.01:
        return 1
    if seg.get("taperPieces"):
        return int(seg["taperPieces"])
    count = math.floor(length / C["TAPER_PIECE_LENGTH"] + 0.5)
    return int(min(max(count, C["TAPER_MIN_PIECES"]), C["TAPER_MAX_PIECES"]))


def _shelves(seg, y, z_centre, length, main_width, offset_x, C, out):
    shelf = seg.get("shelf")
    if not shelf:
        return
    sides = shelf.get("sides", "both")
    dx = main_width / 2.0 + shelf.get("gap", 0.4) + shelf["width"] / 2.0
    shelf_y = y - shelf.get("drop", C["STEP_RISE"])
    for side, sign in (("west", -1.0), ("east", 1.0)):
        if sides in ("both", side):
            out.append(Box(offset_x + sign * dx, shelf_y, z_centre,
                           shelf["width"], C["SLAB_THICKNESS"], length,
                           shelf.get("material"), 0.0))


def layout_linear(segments, C):
    """Returns (boxes, length, rise). The last two are what ChunkBuilder's
    finalize() publishes as the Length and Rise attributes, and they are the only
    thing ChunkService and LevelService read when placing the chunk -- so they are
    worth carrying around rather than re-deriving from a bounding box, which is
    exactly the mistake finalize() exists to avoid."""
    out = []
    z, y, last_length = 0.0, 0.0, 0.0
    for seg in segments:
        if seg.get("gap") is not None:
            z += seg["gap"]
            continue
        if seg.get("rise") is not None:
            y += seg["rise"]

        width = seg.get("width", C["PATH_WIDTH"])
        length = seg.get("length", 12.0)
        offset_x = seg.get("offsetX", 0.0)
        z_start = (z - last_length) if seg.get("sameZ") else z

        pieces = taper_pieces(seg, length, C)
        piece_length = length / pieces
        for i in range(1, pieces + 1):
            t = (i - 1) / (pieces - 1) if pieces > 1 else 0.0
            piece_width = width + (seg.get("widthEnd", width) - width) * t
            z_centre = z_start + (i - 0.5) * piece_length
            out.append(Box(offset_x, y, z_centre, piece_width, C["SLAB_THICKNESS"],
                           piece_length, seg.get("material"), 0.0, seg.get("form")))
            _shelves(seg, y, z_centre, piece_length, piece_width, offset_x, C, out)

        if not seg.get("sameZ"):
            z += length
            last_length = length
    return out, z, y


def layout_ramp(C):
    """P3. Pitched pieces, so these are the only boxes carrying a rotation."""
    angle = math.atan2(C["RAMP_RISE"], C["RAMP_RUN"])
    slope = math.hypot(C["RAMP_RUN"], C["RAMP_RISE"])
    pieces = int(C["RAMP_PIECES"])
    out = []
    for i in range(1, pieces + 1):
        t = (i - 0.5) / pieces
        width = (C["RAMP_WIDTH_BOTTOM"]
                 + (C["RAMP_WIDTH_TOP"] - C["RAMP_WIDTH_BOTTOM"]) * ((i - 1) / (pieces - 1)))
        # Top-face centre, then a step PERPENDICULAR to the slope by half the slab
        # thickness -- not straight down. Same derivation as the Luau, which gets
        # it by applying the translation after the rotation.
        top_y = C["SLAB_THICKNESS"] / 2.0 + t * C["RAMP_RISE"]
        top_z = t * C["RAMP_RUN"]
        out.append(Box(0.0,
                       top_y - (C["SLAB_THICKNESS"] / 2.0) * math.cos(angle),
                       top_z + (C["SLAB_THICKNESS"] / 2.0) * math.sin(angle),
                       width, C["SLAB_THICKNESS"], slope / pieces, "KineticSand", angle))
    return out


def layout_junction(C):
    """S2. Restated by hand because it is a special builder, not a segment list.
    The corner wedge is omitted: it is cosmetic fill, and squaring it off would
    overstate the footprint, which is the one thing these tools are read for."""
    W, T = C["PATH_WIDTH"], C["SLAB_THICKNESS"]
    shelf_w, shelf_gap = 5.0, 0.4
    return [
        Box(0.0, 0.0, 10.0, W, T, 20.0, None, 0.0),
        Box(W, 0.0, 12.0, 16.0, T, 16.0, None, 0.0),
        Box(-(W / 2.0 + shelf_gap + shelf_w / 2.0), -C["STEP_RISE"], 10.0,
            shelf_w, T, 20.0, None, 0.0),
    ]


def layout(chunk_id, chunks, C):
    """(boxes, length, rise) for any chunk. The two special builders publish their
    contract as literals in the Luau, so they are restated as literals here."""
    if chunk_id == "P3_KineticSandRamp":
        return layout_ramp(C), C["RAMP_RUN"], C["RAMP_RISE"]
    if chunk_id == "S2_Junction":
        return layout_junction(C), 20.0, 0.0
    return layout_linear(chunks[chunk_id], C)


def layout_all():
    """({id: boxes}, {id: (length, rise)}, constants)."""
    chunks, consts = load()
    layouts, contracts = {}, {}
    for cid in CHUNK_ORDER:
        boxes, length, rise = layout(cid, chunks, consts)
        layouts[cid], contracts[cid] = boxes, (length, rise)
    return layouts, contracts, consts
