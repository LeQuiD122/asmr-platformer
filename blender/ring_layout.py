"""A level laid on a ring, in Python, the way LevelService lays it in Luau.

Shared by the Sky Pools and Sunken City layouts (skypools_layout.py, sunkencity_layout.py), which
the checks and the plan pictures are built on. Every number is read from the Luau sources; only the
formulas are restated, and each says which Luau function it mirrors.

The random draws are Python's, not Roblox's, so a seed here is not a seed in Studio: what carries
over is the distribution, which is why the checks run hundreds of seeds at every run length.
"""
import math
import pathlib
import random
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import chunk_layout  # noqa: E402

SRC = ROOT / "src"
LEVEL_SOURCE = (SRC / "Server" / "Services" / "LevelService.lua").read_text(encoding="utf-8")
DEFS = (SRC / "Shared" / "LevelDefinitions.lua").read_text(encoding="utf-8")
CHUNK_DEFS = (SRC / "Shared" / "ChunkDefinitions.lua").read_text(encoding="utf-8")


def lua_numbers(text):
    """Every top-level `local NAME = number` and `local A, B = n, m` in a file."""
    found = {}
    pattern = r"^local ([A-Z_][A-Z0-9_]*(?:,\s*[A-Z_][A-Z0-9_]*)*)\s*=\s*([-\d.,\s]+?)\s*(?:--.*)?$"
    for names, values in re.findall(pattern, text, re.M):
        keys = [n.strip() for n in names.split(",")]
        nums = [v.strip() for v in values.split(",")]
        if len(keys) == len(nums):
            for key, num in zip(keys, nums):
                try:
                    found[key] = float(num)
                except ValueError:
                    pass
    return found


def lua_list(text, name):
    body = re.search(r"^local %s = \{([^}]*)\}" % name, text, re.M).group(1)
    return [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?", body)]


L = lua_numbers(LEVEL_SOURCE)
STEP_CHOICES = lua_list(LEVEL_SOURCE, "STEP_CHOICES")
PACE_STEP_CHOICES = lua_list(LEVEL_SOURCE, "PACE_STEP_CHOICES")
GAP = L["CHUNK_GAP"]
MEANDER_STEP = L["MEANDER_STEP"]
SPIRAL_RADIUS = L["SPIRAL_RADIUS"]
BASE_SURFACE_Y = L["BASE_SURFACE_Y"]
DESTROY_Y = -500  # Workspace.FallenPartsDestroyHeight's default, which this project never changes

LAYOUTS, CONTRACTS, C = chunk_layout.layout_all()
S1 = LAYOUTS["S1_Straight"][0]
CAP_HALF = S1.sx / 2 - C["CAP_INSET"]
CAP_TOP = S1.y + S1.sy / 2 + C["CAP_THICKNESS"]  # above the chunk's origin


def declared_category(cid):
    """The category ChunkDefinitions gives a chunk, which is on the same line as its id."""
    found = re.search(r'id = "%s"[^\n]*?category = "(\w+)"' % re.escape(cid), CHUNK_DEFS)
    return found.group(1) if found else None


def category(token):
    """LevelService.categoryForSlot."""
    if token == "S":
        return "stable"
    return "pace" if token.startswith("M") else "risk"


def xmax(cid):
    """How far a chunk reaches from the route's centre line, shelves and all."""
    return max(abs(b.x) + b.sx / 2 for b in LAYOUTS[cid])


def lowest(cid):
    """How far a chunk's geometry hangs under its origin."""
    return min(b.y - b.sy / 2 for b in LAYOUTS[cid])


def top_of(cid):
    """A chunk's walkable top above its origin: the cap on a stable chunk, the slab otherwise."""
    return CAP_TOP if cid.startswith("S") else S1.y + S1.sy / 2


class Meander:
    """LevelService's meanderTo and meanderHeading. The route's heading swings from side to side on
    a long sine, so where it has got to is only known by walking it -- in the same MEANDER_STEP
    pieces, in the same order, so this lands where the Luau lands."""

    def __init__(self, amplitude, wavelength):
        self.amplitude, self.wavelength = amplitude, wavelength
        self.pos, self.along = (0.0, 0.0), 0.0

    def to(self, s):
        while self.along < s - 0.001:
            step = min(MEANDER_STEP, s - self.along)
            heading = self.amplitude * math.sin(2 * math.pi * (self.along + step / 2) / self.wavelength)
            self.pos = (self.pos[0] + math.sin(heading) * step, self.pos[1] + math.cos(heading) * step)
            self.along += step
        return self.pos

    def heading(self, s):
        heading = self.amplitude * math.sin(2 * math.pi * s / self.wavelength)
        return (math.sin(heading), math.cos(heading))


class RingLevel:
    """One level definition with a shape LevelService lays -- a ring or a meander -- and that route."""

    def __init__(self, name):
        start = DEFS.index("LevelDefinitions.%s = {" % name)
        self.block = DEFS[start:DEFS.index("\n}\n", start)]
        self.pool_ids = re.findall(r'"(\w+)"', self.block[self.block.index("allowedChunkIds"):
                                                         self.block.index("allowedMaterials")])
        ring = re.search(r"ring = \{(.*)\},\n", self.block)
        meander = re.search(r"meander = \{(.*)\},\n", self.block)
        self.ring_text = ring.group(1) if ring else (meander.group(1) if meander else "")
        self.has_ring = ring is not None
        self.is_meander = meander is not None and 'layout = "meander"' in self.block

        def field(pattern, default):
            found = re.search(pattern, self.ring_text)
            return float(found.group(1)) if found else default

        self.turn = field(r"turn = ([\d.]+)", 0.75)
        self.amplitude = field(r"amplitude = ([\d.]+)", 0.7)
        self.wavelength = field(r"wavelength = ([\d.]+)", 900.0)
        self.step_scale = field(r"stepScale = ([\d.]+)", 1.0)
        self.descends = "descend = true" in self.ring_text
        wave = re.search(r"wave = \{\s*height = ([\d.]+),\s*every = ([\d.]+)\s*\}", self.ring_text)
        self.wave = (float(wave.group(1)), float(wave.group(2))) if wave else None
        template = re.search(r"templates = \{\s*(\w+)", self.block).group(1)
        self.slots = re.findall(r'"(\w+)"', re.search(r"local %s = \{(.*?)\}" % template, DEFS, re.S).group(1))
        self.min_chunks = int(re.search(r"minChunks = (\d+)", self.block).group(1))
        # HubService: short and long are the level's own count scaled by a half and by one and a half.
        self.runs = (("short", max(4, int(self.min_chunks * 0.5))), ("medium", self.min_chunks),
                     ("long", int(self.min_chunks * 1.5)))
        self.by_category = {}
        for cid in self.pool_ids:
            self.by_category.setdefault(declared_category(cid), []).append(cid)

    def field_text(self, name):
        found = re.search(r'%s = "(\w+)"' % name, self.block)
        return found.group(1) if found else None

    def ring_radius(self, template):
        """LevelService.ringRadius."""
        means, planned = {}, 0.0
        for token in template:
            cat = category(token)
            if cat not in means:
                ids = self.by_category.get(cat, [])
                means[cat] = sum(CONTRACTS[c][0] for c in ids) / len(ids) if ids else 20.0
            planned += means[cat] + GAP
        return max(SPIRAL_RADIUS, planned / (2 * math.pi * self.turn))

    def lay(self, count, seed):
        """The route as LevelService.startLevel lays it: (radius, chunks, finish height). `radius` is
        None on a meander, which has no middle. Every chunk carries where it is and which way it
        faces, so anything built beside it is placed the way the Luau places it whatever the shape."""
        rng = random.Random(seed)
        template = [self.slots[i % len(self.slots)] for i in range(count)]
        radius = None if self.is_meander else self.ring_radius(template)
        walk = Meander(self.amplitude, self.wavelength) if self.is_meander else None
        sign = -1 if self.descends else 1
        angle, y = 0.0, BASE_SURFACE_Y
        chunks = []
        for index, token in enumerate(template, 1):
            cid = rng.choice(self.by_category[category(token)])
            if index > 1:
                steps = STEP_CHOICES if category(token) == "stable" else PACE_STEP_CHOICES
                y += sign * self.step_scale * rng.choice(steps)
                if self.wave:
                    height, every = self.wave
                    y += height * (math.sin(2 * math.pi * index / every) - math.sin(2 * math.pi * (index - 1) / every))
            length, rise = CONTRACTS[cid]
            if walk:
                # `angle` is studs travelled on a meander, as it is in LevelService.
                pos, tan = walk.to(angle), walk.heading(angle)
                out = (tan[1], -tan[0])  # Vector3.yAxis:Cross(tangent), the chunk's right
            else:
                pos = (math.cos(angle) * radius, math.sin(angle) * radius)
                out, tan = (math.cos(angle), math.sin(angle)), (-math.sin(angle), math.cos(angle))
            chunks.append({"id": cid, "index": index, "angle": angle, "y": y, "length": length, "rise": rise,
                           "pos": pos, "out": out, "tan": tan})
            angle += (length + GAP) if walk else (length + GAP) / radius
            y += rise
        return radius, chunks, y


def chunk_frame(radius, ch):
    """A chunk's entry point in plan, and its outward and along directions."""
    if "pos" in ch:
        return ch["pos"], ch["out"], ch["tan"]
    a = ch["angle"]
    out, tan = (math.cos(a), math.sin(a)), (-math.sin(a), math.cos(a))
    return (out[0] * radius, out[1] * radius), out, tan


def kill_y(chunks):
    """LevelService: minSurfaceY - 40."""
    return min(ch["y"] for ch in chunks) - 40


def finish_frame(radius, chunks):
    """Where the route runs out, in plan, and which way is outward and forward there."""
    last = chunks[-1]
    origin, out, tan = chunk_frame(radius, last)
    return (origin[0] + tan[0] * last["length"], origin[1] + tan[1] * last["length"]), out, tan


def beside_frame(radius, ch, side=None):
    """The frame beside a checkpoint (SkyPoolsService.terraceBeside, SunkenCityService.besideFrame):
    the cap's outer edge, which way it faces, and along the route.

    With no `side`, it faces away from the middle, which is what a ring is built round. With a side
    of +1 or -1 it faces that way off the chunk itself, which is what a route that goes somewhere
    has instead."""
    origin, right, tan = chunk_frame(radius, ch)
    mid = (origin[0] + tan[0] * ch["length"] / 2, origin[1] + tan[1] * ch["length"] / 2)
    if side is None:
        m = math.hypot(*mid)
        out = (mid[0] / m, mid[1] / m)
    else:
        out = (right[0] * side, right[1] * side)
    edge = (mid[0] + out[0] * CAP_HALF, mid[1] + out[1] * CAP_HALF)
    # Vector3.yAxis:Cross(out), as terraceBeside takes it.
    return edge, out, (out[1], -out[0])


def rect(origin, out, tan, x0, x1, z0, z1, y0, y1, name):
    """A box: a rectangle in plan in some frame, with a height range."""
    return {"o": origin, "out": out, "tan": tan, "x": (x0, x1), "z": (z0, z1), "y": (y0, y1), "name": name}


def inside(r, point, pad):
    dx, dz = point[0] - r["o"][0], point[1] - r["o"][1]
    x, z = dx * r["out"][0] + dz * r["out"][1], dx * r["tan"][0] + dz * r["tan"][1]
    return r["x"][0] - pad <= x <= r["x"][1] + pad and r["z"][0] - pad <= z <= r["z"][1] + pad


def chunk_rects(radius, chunks):
    """Every chunk as a box: its full reach either side, its length, and its height."""
    out = []
    for ch in chunks:
        origin, o, t = chunk_frame(radius, ch)
        reach = xmax(ch["id"])
        out.append(rect(origin, o, t, -reach, reach, 0, ch["length"], ch["y"] + lowest(ch["id"]),
                        ch["y"] + max(0.0, ch["rise"]) + 4, "chunk %d" % ch["index"]))
    return out


def rect_distance(r, point):
    """Horizontal distance from a point to a box's plan rectangle (0 inside it)."""
    dx, dz = point[0] - r["o"][0], point[1] - r["o"][1]
    x, z = dx * r["out"][0] + dz * r["out"][1], dx * r["tan"][0] + dz * r["tan"][1]
    ex = max(r["x"][0] - x, 0, x - r["x"][1])
    ez = max(r["z"][0] - z, 0, z - r["z"][1])
    return math.hypot(ex, ez)
