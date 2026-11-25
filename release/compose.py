"""The release art: the game icon, the store thumbnails and the badge icons, composed from Studio shots.

    python release/compose.py

Shots (release/shots/*.jpg) are taken in Studio in front of a flat green screen (or are real views of the levels); the
green is keyed out here and the cut-outs laid over drawn art in the look of the big Roblox games of the moment: a
sunburst behind, big chunky titles with a thick dark outline and a drop shadow, sparkles. Writes release/out/.
"""
import math
import pathlib
import random

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
SHOTS = HERE / "shots"
OUT = HERE / "out"
FONT = r"C:\Windows\Fonts\seguibl.ttf"  # Segoe UI Black: the chunkiest face on this machine
KEY = (0, 255, 0)


def font(size):
    return ImageFont.truetype(FONT, size)


# ---- KEYING: the green screen out, its spill off the edges ----
def cut_out(path, tolerance=125, soft=30):
    img = Image.open(path).convert("RGB")
    px = img.load()
    w, h = img.size
    alpha = Image.new("L", (w, h), 0)
    ap = alpha.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            # How green it is: green over the larger of red and blue.
            greenness = g - max(r, b)
            if greenness > tolerance:
                a = 0
            elif greenness < tolerance - soft:
                a = 255
            else:
                a = int(255 * (tolerance - greenness) / soft)
            ap[x, y] = a
            # Despill only what is the screen's (far greener than the slime pal, which is green itself), and at the edges.
            if greenness > tolerance - soft - 10 or (greenness > 40 and 0 < a < 255):
                px[x, y] = (r, max(r, b) + min(30, greenness // 4), b)
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    out = img.convert("RGBA")
    out.putalpha(alpha)
    box = alpha.point(lambda v: 255 if v > 40 else 0).getbbox()
    return out.crop(box) if box else out


def pop(img, saturation=1.25, contrast=1.08, brightness=1.04):
    rgb, a = img.convert("RGB"), img.getchannel("A")
    rgb = ImageEnhance.Color(rgb).enhance(saturation)
    rgb = ImageEnhance.Contrast(rgb).enhance(contrast)
    rgb = ImageEnhance.Brightness(rgb).enhance(brightness)
    rgb = rgb.convert("RGBA")
    rgb.putalpha(a)
    return rgb


# ---- THE DRAWN PARTS ----
def sunburst(w, h, inner, outer, ray_a, ray_b, rays=18, centre=None):
    cx, cy = centre or (w / 2, h / 2)
    base = Image.new("RGB", (w, h), outer)
    d = ImageDraw.Draw(base)
    reach = math.hypot(w, h)
    for k in range(rays):
        a0 = 2 * math.pi * k / rays
        a1 = a0 + math.pi / rays
        d.polygon([(cx, cy), (cx + reach * math.cos(a0), cy + reach * math.sin(a0)),
                   (cx + reach * math.cos(a1), cy + reach * math.sin(a1))], fill=ray_a if k % 2 == 0 else ray_b)
    # A glow in the middle, fading out.
    glow = Image.new("L", (w, h), 0)
    gd = ImageDraw.Draw(glow)
    r = min(w, h) * 0.75
    for i in range(40, 0, -1):
        rr = r * i / 40
        gd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=int(255 * (1 - i / 40) ** 0.8))
    glow = glow.filter(ImageFilter.GaussianBlur(r / 10))
    base = Image.composite(Image.new("RGB", (w, h), inner), base, glow)
    # A soft dark edge, to hold the eye in.
    vig = Image.new("L", (w, h), 0)
    vd = ImageDraw.Draw(vig)
    vd.rectangle([0, 0, w, h], fill=90)
    vd.ellipse([-w * 0.15, -h * 0.2, w * 1.15, h * 1.2], fill=0)
    vig = vig.filter(ImageFilter.GaussianBlur(min(w, h) / 8))
    return Image.composite(Image.new("RGB", (w, h), (40, 10, 60)), base, vig).convert("RGBA")


def sparkle(img, x, y, size, colour=(255, 255, 255, 255)):
    d = ImageDraw.Draw(img)
    s = size
    d.polygon([(x, y - s), (x + s * 0.22, y - s * 0.22), (x + s, y), (x + s * 0.22, y + s * 0.22), (x, y + s),
               (x - s * 0.22, y + s * 0.22), (x - s, y), (x - s * 0.22, y - s * 0.22)], fill=colour)


def sparkles(img, count, seed, box=None, sizes=(10, 34)):
    rng = random.Random(seed)
    w, h = img.size
    x0, y0, x1, y1 = box or (0, 0, w, h)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    for _ in range(count):
        sparkle(layer, rng.uniform(x0, x1), rng.uniform(y0, y1), rng.uniform(*sizes),
                rng.choice([(255, 255, 255, 235), (255, 246, 190, 235), (255, 220, 250, 225)]))
    glow = layer.filter(ImageFilter.GaussianBlur(6))
    img.alpha_composite(glow)
    img.alpha_composite(layer)


def shadow_under(img, cut, at, strength=120, blur=18, drop=(10, 18)):
    """A cut-out's soft shadow, then the cut-out, at `at` (its top left)."""
    # (On a canvas with room round it, so the blur fades out instead of stopping square at the cut-out's edge.)
    room = blur * 3
    alpha = Image.new("L", (cut.width + room * 2, cut.height + room * 2), 0)
    alpha.paste(cut.getchannel("A").point(lambda v: v * strength // 255), (room, room))
    alpha = alpha.filter(ImageFilter.GaussianBlur(blur))
    sh = Image.new("RGBA", alpha.size, (30, 10, 50, 255))
    sh.putalpha(alpha)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    layer.paste(sh, (at[0] + drop[0] - room, at[1] + drop[1] - room), sh)
    img.alpha_composite(layer)
    img.alpha_composite(cut, (int(at[0]), int(at[1])))


def title(img, text, centre, size, fill_top=(255, 244, 120), fill_bottom=(255, 150, 40), outline=(60, 20, 70),
          stroke=None, tilt=-4, shadow=(30, 0, 50)):
    """A big chunky word or two: a gradient fill, a thick outline, a drop shadow, a slight tilt."""
    f = font(size)
    stroke = stroke or max(6, size // 9)
    pad = stroke * 3
    left, top, right, bottom = f.getbbox(text, stroke_width=stroke)
    w, h = right - left + pad * 2, bottom - top + pad * 2
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((pad - left, pad - top), text, font=f, fill=255)
    edge = Image.new("L", (w, h), 0)
    ImageDraw.Draw(edge).text((pad - left, pad - top), text, font=f, fill=255, stroke_width=stroke, stroke_fill=255)
    grad = Image.new("RGBA", (w, h))
    gd = ImageDraw.Draw(grad)
    for y in range(h):
        t = y / max(1, h - 1)
        gd.line([(0, y), (w, y)], fill=tuple(int(fill_top[i] + (fill_bottom[i] - fill_top[i]) * t) for i in range(3)) + (255,))
    word = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    word.paste(Image.new("RGBA", (w, h), outline + (255,)), (0, 0), edge)
    word.paste(grad, (0, 0), mask)
    # A shine on the top half of the letters.
    shine = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shine).rectangle([0, 0, w, int(h * 0.42)], fill=70)
    shine = Image.composite(shine, Image.new("L", (w, h), 0), mask)
    word.alpha_composite(Image.merge("RGBA", (Image.new("L", (w, h), 255),) * 3 + (shine,)))
    word = word.rotate(tilt, resample=Image.BICUBIC, expand=True)
    sh = Image.new("RGBA", word.size, shadow + (0,))
    sh.putalpha(word.getchannel("A").point(lambda v: v * 200 // 255))
    sh = sh.filter(ImageFilter.GaussianBlur(4))
    x, y = int(centre[0] - word.width / 2), int(centre[1] - word.height / 2)
    img.alpha_composite(sh, (x + stroke // 2 + 4, y + stroke + 6))
    img.alpha_composite(word, (x, y))
    return word.size


def fit(cut, height=None, width=None):
    """Scaled to a height or a width, premultiplied (so no dark or bright fringe), with a clear margin round it so its
    edge never rings into a line."""
    pad = 6
    framed = Image.new("RGBA", (cut.width + pad * 2, cut.height + pad * 2), (0, 0, 0, 0))
    framed.paste(cut, (pad, pad))
    scale = (height / cut.height) if height else (width / cut.width)
    size = (max(1, int(framed.width * scale)), max(1, int(framed.height * scale)))
    out = framed.convert("RGBa").resize(size, Image.BICUBIC).convert("RGBA")
    box = out.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    return out.crop(box) if box else out


# THE LEVELS' SHOTS (reshot cinematically 2026-11-18): the part of each worth showing, for a card (16:9) and a badge
# (square), in the shot's pixels: the City Shore's spiral without the pink horizon under it, and each landmark centred.
CROPS = {
    "level1.jpg": {"card": (480, 0, 1360, 495), "badge": (690, 0, 1150, 460)},
    "level2.jpg": {"card": (447, 60, 1387, 589), "badge": (622, 41, 1212, 631)},
    "level3.jpg": {"card": (356, 0, 1478, 631), "badge": (560, 0, 1191, 631)},
    "level4.jpg": {"card": (356, 0, 1478, 631), "badge": (602, 0, 1233, 631)},
    "level5.jpg": {"card": (356, 0, 1478, 631), "badge": (586, 0, 1217, 631)},
}


def graded(shot):
    """A light cinematic grade: a little more contrast and colour, a soft vignette."""
    shot = ImageEnhance.Contrast(shot).enhance(1.12)
    shot = ImageEnhance.Color(shot).enhance(1.18)
    w, h = shot.size
    vig = Image.new("L", (w, h), 0)
    ImageDraw.Draw(vig).ellipse([-w * 0.2, -h * 0.25, w * 1.2, h * 1.25], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(min(w, h) / 6))
    dark = ImageEnhance.Brightness(shot).enhance(0.62)
    return Image.composite(shot, dark, vig)


def level_shot(path, use):
    shot = Image.open(path).convert("RGB")
    box = CROPS.get(pathlib.Path(path).name, {}).get(use)
    if box:
        shot = shot.crop(box)
    return graded(shot)


def card(shot_path, size, tilt, label=None, border=(255, 255, 255)):
    """A real view of a level as a tilted card with a white border and its name under it."""
    w, h = size
    shot = level_shot(shot_path, "card")
    sw, sh = shot.size
    scale = max(w / sw, h / sh)
    shot = shot.resize((int(sw * scale) + 1, int(sh * scale) + 1), Image.LANCZOS)
    shot = shot.crop(((shot.width - w) // 2, (shot.height - h) // 2, (shot.width - w) // 2 + w, (shot.height - h) // 2 + h))
    b = 12
    frame = Image.new("RGBA", (w + b * 2, h + b * 2 + (64 if label else 0)), border + (255,))
    frame.paste(shot, (b, b))
    if label:
        f = font(40)
        d = ImageDraw.Draw(frame)
        tw = d.textlength(label, font=f)
        d.text(((frame.width - tw) / 2, h + b + 6), label, font=f, fill=(70, 30, 90))
    round_mask = Image.new("L", frame.size, 0)
    ImageDraw.Draw(round_mask).rounded_rectangle([0, 0, frame.width - 1, frame.height - 1], radius=22, fill=255)
    frame.putalpha(round_mask)
    return frame.rotate(tilt, resample=Image.BICUBIC, expand=True)


def circle_badge(inner, ring=(255, 214, 90), ring_dark=(170, 100, 20), size=512, glyph=None):
    """A badge: a picture in a round frame with a gold rim (Roblox crops the upload to a circle)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, size - 1, size - 1], fill=ring_dark + (255,))
    d.ellipse([10, 10, size - 11, size - 11], fill=ring + (255,))
    pic = inner.convert("RGBA")
    s = size - 60
    scale = max(s / pic.width, s / pic.height)
    pic = pic.resize((int(pic.width * scale) + 1, int(pic.height * scale) + 1), Image.LANCZOS)
    pic = pic.crop(((pic.width - s) // 2, (pic.height - s) // 2, (pic.width - s) // 2 + s, (pic.height - s) // 2 + s))
    m = Image.new("L", (s, s), 0)
    ImageDraw.Draw(m).ellipse([0, 0, s - 1, s - 1], fill=255)
    img.paste(pic, (30, 30), m)
    # A gloss over the top of it.
    gloss = Image.new("L", (size, size), 0)
    ImageDraw.Draw(gloss).ellipse([60, 40, size - 60, size * 0.55], fill=60)
    gloss = gloss.filter(ImageFilter.GaussianBlur(20))
    img.alpha_composite(Image.merge("RGBA", (Image.new("L", (size, size), 255),) * 3 + (gloss,)))
    return img


# ---- THE PIECES OF ART ----
def key_glyph(size, colour=(255, 214, 90), edge=(120, 70, 10)):
    """A big chunky key, bow on the left, two teeth, for the story badges."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size
    bw = int(s * 0.07)

    def body(fill, g):
        d.ellipse([s * 0.1 - g, s * 0.32 - g, s * 0.46 + g, s * 0.68 + g], fill=fill)
        d.rounded_rectangle([s * 0.4 - g, s * 0.45 - g, s * 0.9 + g, s * 0.56 + g], radius=int(s * 0.03), fill=fill)
        d.rectangle([s * 0.72 - g, s * 0.5, s * 0.79 + g, s * 0.7 + g], fill=fill)
        d.rectangle([s * 0.82 - g, s * 0.5, s * 0.89 + g, s * 0.66 + g], fill=fill)
    body(edge, bw // 2)
    body(colour, 0)
    d.ellipse([s * 0.19, s * 0.41, s * 0.37, s * 0.59], fill=edge)
    d.ellipse([s * 0.2, s * 0.42, s * 0.36, s * 0.58], fill=(0, 0, 0, 0))
    d.ellipse([s * 0.15, s * 0.35, s * 0.3, s * 0.45], fill=(255, 250, 220, 160))
    return img.rotate(30, resample=Image.BICUBIC)


def flames(img, cx, base_y, width, height, seed=3):
    rng = random.Random(seed)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for colour, scale in (((255, 90, 30, 255), 1.0), ((255, 170, 40, 255), 0.72), ((255, 236, 120, 255), 0.45)):
        for k in range(9):
            x = cx + (k - 4) / 4 * width / 2 * scale
            h = height * scale * rng.uniform(0.6, 1.0) * (1 - abs(k - 4) / 6)
            w = width / 6 * scale
            d.polygon([(x - w, base_y), (x, base_y - h), (x + w, base_y)], fill=colour)
    layer = layer.filter(ImageFilter.GaussianBlur(3))
    img.alpha_composite(layer)


def swatch_grid(size):
    colours = [(239, 159, 39), (151, 196, 89), (236, 96, 120), (181, 212, 244), (250, 199, 117), (206, 203, 246),
               (255, 128, 48), (240, 214, 160), (236, 244, 250), (130, 212, 190), (222, 170, 220), (255, 226, 110),
               (120, 90, 80), (170, 236, 120), (255, 170, 196), (160, 222, 246)]
    img = Image.new("RGBA", (size, size), (255, 246, 250, 255))
    d = ImageDraw.Draw(img)
    n = 4
    cell = size / n
    for k, c in enumerate(colours):
        x, y = (k % n) * cell, (k // n) * cell
        d.ellipse([x + cell * 0.1, y + cell * 0.1, x + cell * 0.9, y + cell * 0.9], fill=c + (255,), outline=(255, 255, 255),
                  width=int(cell * 0.06))
    return img


def save(img, name, size=None):
    OUT.mkdir(exist_ok=True)
    out = img.convert("RGB")
    if size:
        out = out.resize(size, Image.LANCZOS)
    out.save(OUT / name)
    print("wrote", OUT / name, out.size)


def split_row(row):
    """The row of pals cut into one picture each, by the gaps of clear air between them."""
    a = row.getchannel("A")
    w, h = a.size
    cols = [a.crop((x, 0, x + 1, h)).getextrema()[1] for x in range(w)]
    # Where two pals touch, the narrowest column between them parts them.
    cols = [0 if v < 120 else v for v in cols]
    pieces, start = [], None
    for x, v in enumerate(cols + [0]):
        if v > 40 and start is None:
            start = x
        elif v <= 40 and start is not None:
            if x - start > 20:
                piece = row.crop((start, 0, x, h))
                box = piece.getchannel("A").point(lambda q: 255 if q > 40 else 0).getbbox()
                pieces.append(piece.crop(box) if box else piece)
            start = None
    return pieces


def build():
    pals = pop(cut_out(SHOTS / "pals_icon.jpg"))
    row = pop(cut_out(SHOTS / "pals_row.jpg"))
    hero = pop(cut_out(SHOTS / "player_cheer.jpg"), saturation=1.15)
    singles = split_row(row)
    print(len(singles), "pals cut from the row")

    # ===== THE ICON (512): the pals together on a candy sunburst, SQUISH over them. Made at 1024, then halved. =====
    for with_text in (True, False):
        S = 1024
        img = sunburst(S, S, (255, 246, 196), (176, 96, 250), (255, 150, 206), (255, 190, 226), rays=16, centre=(S / 2, S * 0.46))
        cut = fit(pals, width=int(S * 0.94))
        if cut.height > S * (0.74 if with_text else 0.86):
            cut = fit(pals, height=int(S * (0.74 if with_text else 0.86)))
        sparkles(img, 22, 7, (40, 60, S - 40, S * 0.6), (14, 40))
        shadow_under(img, cut, ((S - cut.width) // 2, S - cut.height - 40), drop=(0, 26))
        if with_text:
            title(img, "SQUISH", (S / 2, S * 0.15), 220, tilt=-5)
        save(img, "icon.png" if with_text else "icon_no_text.png", (512, 512))

    W, H = 1920, 1080
    # ===== THUMBNAIL 1: the hero, cheering, among the pals; the name over them. =====
    img = sunburst(W, H, (255, 244, 200), (90, 150, 255), (140, 200, 255), (176, 220, 255), rays=22, centre=(W * 0.5, H * 0.55))
    sparkles(img, 40, 11, (0, 0, W, H * 0.7), (14, 44))
    man = fit(hero, height=int(H * 0.74))
    # The pals either side of the hero, each its own size, side by side and never over each other.
    def lay(group, x0, x1, heights):
        scaled = [fit(p, height=int(H * hh)) for p, hh in zip(group, heights)]
        room = (x1 - x0) - sum(q.width for q in scaled)
        gap = max(10, room / max(1, len(scaled) - 1)) if len(scaled) > 1 else 0
        x = x0 + (max(0, room - gap * (len(scaled) - 1)) / 2 if len(scaled) > 1 else room / 2)
        for k, q in enumerate(scaled):
            shadow_under(img, q, (int(x), H - q.height - 34 - 46 * (k % 2)), drop=(10, 18))
            x += q.width + gap
    half = (len(singles) + 1) // 2
    lay(singles[:half], W * 0.02, W * 0.36, [0.27, 0.22, 0.25, 0.22][:half])
    lay(singles[half:], W * 0.64, W * 0.98, [0.24, 0.29, 0.23, 0.22][:len(singles) - half])
    shadow_under(img, man, (int(W * 0.5 - man.width / 2), H - man.height - 16), drop=(14, 20))
    title(img, "SQUISH OBBY", (W / 2, H * 0.14), 200, tilt=-3)
    title(img, "SO SATISFYING!", (W * 0.82, H * 0.38), 80, fill_top=(255, 255, 255), fill_bottom=(255, 210, 240), tilt=8)
    save(img, "thumb1_hero.png")

    # ===== THUMBNAIL 2: COLLECT CUTE PALS! =====
    img = sunburst(W, H, (255, 240, 248), (196, 90, 210), (255, 150, 210), (255, 186, 226), rays=20, centre=(W / 2, H * 0.58))
    sparkles(img, 44, 21, (0, 0, W, H), (12, 40))
    r = fit(row, width=int(W * 0.96))
    shadow_under(img, r, ((W - r.width) // 2, int(H * 0.56 - r.height / 2)), drop=(12, 24))
    title(img, "COLLECT CUTE PALS!", (W / 2, H * 0.16), 150, tilt=-3)
    title(img, "SQUISH OBBY", (W / 2, H * 0.88), 110, fill_top=(255, 255, 255), fill_bottom=(220, 235, 255), tilt=2)
    save(img, "thumb2_pals.png")

    # ===== THUMBNAIL 3: 5 WORLDS, as cards fanned out. =====
    img = sunburst(W, H, (255, 236, 190), (255, 120, 90), (255, 170, 110), (255, 196, 140), rays=20, centre=(W / 2, H * 0.6))
    names = ["City Shore", "Sky Pools", "Sunken City", "Flooded Halls", "Hill House"]
    # Three across the top, two under them, every name clear.
    spots = [(0.18, 0.445, 4), (0.5, 0.425, 0), (0.82, 0.445, -4), (0.33, 0.825, 2), (0.67, 0.825, -2)]
    for k in range(5):
        c = card(SHOTS / ("level%d.jpg" % (k + 1)), (520, 293), spots[k][2], names[k])
        x, y = int(W * spots[k][0] - c.width / 2), int(H * spots[k][1] - c.height / 2)
        shadow_under(img, c, (x, y), strength=150, blur=14, drop=(10, 16))
    sparkles(img, 30, 31, (0, 0, W, H * 0.4), (12, 40))
    title(img, "5 WORLDS TO SQUISH!", (W / 2, H * 0.14), 150, tilt=-3)
    save(img, "thumb3_worlds.png")

    # ===== THUMBNAIL 4: the bay itself, the lobby, with the hero and the pals; NEW GAME! =====
    lobby = Image.open(SHOTS / "lobby.jpg").convert("RGB")
    lw, lh = lobby.size
    crop_w = int(lh * 16 / 9)
    lobby = lobby.crop(((lw - crop_w) // 2, 0, (lw - crop_w) // 2 + crop_w, lh)).resize((W, H), Image.LANCZOS)
    lobby = ImageEnhance.Color(lobby).enhance(1.35)
    lobby = ImageEnhance.Contrast(lobby).enhance(1.08).filter(ImageFilter.GaussianBlur(1.2))
    img = lobby.convert("RGBA")
    man = fit(hero, height=int(H * 0.7))
    shadow_under(img, man, (int(W * 0.06), H - man.height - 10), drop=(14, 20))
    p = fit(pals, height=int(H * 0.5))
    shadow_under(img, p, (int(W * 0.96 - p.width), H - p.height - 30), drop=(12, 20))
    title(img, "SQUISH OBBY", (W * 0.56, H * 0.15), 190, tilt=-3)
    ribbon = Image.new("RGBA", (620, 120), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ribbon)
    rd.rounded_rectangle([0, 0, 619, 119], radius=34, fill=(255, 70, 120, 255), outline=(255, 255, 255, 255), width=8)
    f = font(74)
    tw = rd.textlength("NEW GAME!", font=f)
    rd.text(((620 - tw) / 2, 8), "NEW GAME!", font=f, fill=(255, 255, 255), stroke_width=4, stroke_fill=(120, 20, 60))
    ribbon = ribbon.rotate(-8, resample=Image.BICUBIC, expand=True)
    shadow_under(img, ribbon, (W - ribbon.width - 40, int(H * 0.3)), strength=140, blur=8, drop=(6, 10))
    save(img, "thumb4_bay.png")

    # ===== THE BADGES (512, a picture in a gold rim) =====
    badges = OUT / "badges"
    badges.mkdir(parents=True, exist_ok=True)

    def badge(img, name):
        img.convert("RGBA").save(badges / name)
        print("wrote", badges / name)
    for k in range(5):
        badge(circle_badge(level_shot(SHOTS / ("level%d.jpg" % (k + 1)), "badge")), "level%d.png" % (k + 1))
    back = Image.open(SHOTS / "backrooms.jpg").convert("RGB")
    bw_, bh_ = back.size
    back = back.crop((bw_ - bh_, 0, bw_, bh_))
    badge(circle_badge(back, ring=(240, 220, 120), ring_dark=(90, 80, 30)), "backRooms.png")
    for name, colours, extra in (("story", ((220, 255, 220), (40, 150, 80), (90, 200, 120), (120, 220, 150)), None),
                                 ("storyHardcore", ((255, 230, 160), (180, 30, 30), (230, 70, 40), (250, 110, 60)), "fire"),
                                 ("trueEnding", ((255, 250, 220), (200, 140, 30), (255, 206, 90), (255, 226, 140)), "shine")):
        art = sunburst(512, 512, colours[0], colours[1], colours[2], colours[3], rays=14)
        if extra == "fire":
            flames(art, 256, 470, 420, 260)
        art.alpha_composite(key_glyph(380), (66, 70))
        if extra == "shine":
            sparkles(art, 16, 5, (40, 40, 472, 472), (10, 30))
        hard = name == "storyHardcore"
        badge(circle_badge(art, ring=(255, 140, 70) if hard else (255, 214, 90),
                           ring_dark=(120, 30, 20) if hard else (170, 100, 20)), name + ".png")
    badge(circle_badge(swatch_grid(512), ring=(255, 190, 226), ring_dark=(150, 60, 120)), "materials.png")


# ===== THE SECOND LOOK (2026-11-18, "make the other thumbnails better too, take inspo from the popular games") =====
#
# What the big games' thumbnails do, done here: subjects big and close, cut by the frame's edges; each one a STICKER
# (a white outline and a coloured glow round it); titles EXTRUDED (a stack of darker copies under the face, so the
# letters stand off the picture); hook words in a STARBURST badge; a real view of the game behind, blurred and graded,
# with light rays out of it; LIGHT BEAMS under the prized things; name tags under the pals.

PALS = ["Pal_Needoh", "Pal_Slime", "Pal_Jelly", "Pal_Bee", "Pal_Cloud", "Pal_Lava"]
PAL_NAMES = {"Pal_Needoh": ("Squish", 350), "Pal_Slime": ("Gloop", 450), "Pal_Jelly": ("Wibble", 550),
             "Pal_Bee": ("Bumble", 700), "Pal_Cloud": ("Nimbus", 850), "Pal_Lava": ("Cinder", 1200)}
PAL_GLOW = {"Pal_Needoh": (120, 190, 255), "Pal_Slime": (140, 240, 110), "Pal_Jelly": (255, 140, 200),
            "Pal_Bee": (255, 214, 80), "Pal_Cloud": (200, 210, 255), "Pal_Lava": (255, 120, 40)}


def pal_cut(name):
    """A pal's own close-up, keyed, its middle only (a falling leaf drifted through the side of some shots)."""
    img = Image.open(SHOTS / "pals" / (name + ".jpg")).convert("RGB")
    w, h = img.size
    tmp = OUT / "_tmp_pal.png"
    OUT.mkdir(exist_ok=True)
    img.crop((w // 2 - 330, 0, w // 2 + 330, h)).save(tmp)
    cut = pop(cut_out(tmp), saturation=1.2, contrast=1.06, brightness=1.4 if name == "Pal_Cloud" else 1.04)
    tmp.unlink()
    return cut


def sticker(cut, outline=10, colour=(255, 255, 255), glow=(255, 220, 120), glow_size=26):
    """A cut-out as a sticker: a white outline hugging it, and a soft coloured glow past that."""
    pad = outline + glow_size * 2
    a = Image.new("L", (cut.width + pad * 2, cut.height + pad * 2), 0)
    a.paste(cut.getchannel("A"), (pad, pad))
    edge = a.point(lambda v: 255 if v > 60 else 0).filter(ImageFilter.MaxFilter(outline * 2 + 1))
    edge = edge.filter(ImageFilter.GaussianBlur(1.2))
    halo = edge.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(glow_size))
    out = Image.new("RGBA", a.size, (0, 0, 0, 0))
    g = Image.new("RGBA", a.size, glow + (255,))
    g.putalpha(halo.point(lambda v: min(255, int(v * 1.4))))
    out.alpha_composite(g)
    e = Image.new("RGBA", a.size, colour + (255,))
    e.putalpha(edge)
    out.alpha_composite(e)
    out.alpha_composite(cut, (pad, pad))
    return out


def title3d(img, text, centre, size, fill_top=(255, 248, 140), fill_bottom=(255, 150, 30), outline=(70, 20, 80),
            depth=None, tilt=-3):
    """The chunky title, extruded: copies stepped down and right in a darker outline colour, then the face over them."""
    f = font(size)
    stroke = max(7, size // 8)
    depth = depth or max(6, size // 14)
    pad = stroke * 3 + depth
    left, top, right, bottom = f.getbbox(text, stroke_width=stroke)
    w, h = right - left + pad * 2, bottom - top + pad * 2
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text((pad - left, pad - top), text, font=f, fill=255)
    edge = Image.new("L", (w, h), 0)
    ImageDraw.Draw(edge).text((pad - left, pad - top), text, font=f, fill=255, stroke_width=stroke, stroke_fill=255)
    word = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    deep = tuple(max(0, int(c * 0.55)) for c in outline)
    for k in range(depth, 0, -1):
        step = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        step.paste(Image.new("RGBA", (w, h), deep + (255,)), (0, 0), edge)
        word.alpha_composite(step, (k // 2, k))
    word.paste(Image.new("RGBA", (w, h), outline + (255,)), (0, 0), edge)
    grad = Image.new("RGBA", (w, h))
    gd = ImageDraw.Draw(grad)
    for y in range(h):
        t = y / max(1, h - 1)
        gd.line([(0, y), (w, y)], fill=tuple(int(fill_top[i] + (fill_bottom[i] - fill_top[i]) * t) for i in range(3)) + (255,))
    word.paste(grad, (0, 0), mask)
    shine = Image.new("L", (w, h), 0)
    ImageDraw.Draw(shine).rectangle([0, 0, w, int(h * 0.44)], fill=80)
    shine = Image.composite(shine, Image.new("L", (w, h), 0), mask)
    word.alpha_composite(Image.merge("RGBA", (Image.new("L", (w, h), 255),) * 3 + (shine,)))
    word = word.rotate(tilt, resample=Image.BICUBIC, expand=True)
    sh = Image.new("RGBA", (word.width + 60, word.height + 60), (0, 0, 0, 0))
    a = Image.new("L", sh.size, 0)
    a.paste(word.getchannel("A"), (30, 30))
    a = a.filter(ImageFilter.GaussianBlur(10)).point(lambda v: v * 150 // 255)
    sh = Image.new("RGBA", sh.size, (20, 0, 40, 255))
    sh.putalpha(a)
    x, y = int(centre[0] - word.width / 2), int(centre[1] - word.height / 2)
    img.alpha_composite(sh, (x - 30 + 6, y - 30 + 14))
    img.alpha_composite(word, (x, y))


def burst(img, text, centre, radius, fill=(255, 230, 60), edge=(200, 60, 20), ink=(120, 30, 10), points=14, tilt=-12,
          size=None, lines=None):
    """A starburst badge with words in it."""
    r = radius
    pad = 20
    layer = Image.new("RGBA", (r * 2 + pad * 2, r * 2 + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    c = r + pad
    pts = []
    for k in range(points * 2):
        ang = math.pi * k / points
        rr = r if k % 2 == 0 else r * 0.78
        pts.append((c + rr * math.cos(ang), c + rr * math.sin(ang)))
    d.polygon(pts, fill=edge + (255,))
    inner = [(c + (x - c) * 0.9, c + (y - c) * 0.9) for x, y in pts]
    d.polygon(inner, fill=fill + (255,))
    words = lines or [text]
    fs = size or int(r * 0.42)
    f = font(fs)
    total = len(words) * fs * 1.0
    y = c - total / 2 - fs * 0.12
    for line in words:
        tw = d.textlength(line, font=f)
        d.text((c - tw / 2, y), line, font=f, fill=(255, 255, 255), stroke_width=max(3, fs // 10), stroke_fill=ink)
        y += fs * 1.0
    layer = layer.rotate(tilt, resample=Image.BICUBIC, expand=True)
    sh = Image.new("RGBA", layer.size, (40, 0, 20, 0))
    sh.putalpha(layer.getchannel("A").filter(ImageFilter.GaussianBlur(8)).point(lambda v: v * 140 // 255))
    x, y = int(centre[0] - layer.width / 2), int(centre[1] - layer.height / 2)
    img.alpha_composite(sh, (x + 6, y + 12))
    img.alpha_composite(layer, (x, y))


def scene_bg(path, w, h, blur=7, rays=True, ray_colour=(255, 246, 210), centre=None, crop=None, darken=0.0):
    """A real view of the game, filling the frame, blurred and graded, light rays coming out of the middle."""
    shot = Image.open(path).convert("RGB")
    if crop:
        shot = shot.crop(crop)
    sw, sh = shot.size
    scale = max(w / sw, h / sh)
    shot = shot.resize((int(sw * scale) + 1, int(sh * scale) + 1), Image.LANCZOS)
    shot = shot.crop(((shot.width - w) // 2, (shot.height - h) // 2, (shot.width - w) // 2 + w, (shot.height - h) // 2 + h))
    shot = ImageEnhance.Color(shot).enhance(1.35)
    shot = ImageEnhance.Contrast(shot).enhance(1.1).filter(ImageFilter.GaussianBlur(blur))
    if darken:
        shot = ImageEnhance.Brightness(shot).enhance(1 - darken)
    img = shot.convert("RGBA")
    if rays:
        cx, cy = centre or (w / 2, h / 2)
        layer = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(layer)
        reach = math.hypot(w, h)
        n = 20
        for k in range(n):
            a0 = 2 * math.pi * k / n
            a1 = a0 + math.pi / n * 0.8
            d.polygon([(cx, cy), (cx + reach * math.cos(a0), cy + reach * math.sin(a0)),
                       (cx + reach * math.cos(a1), cy + reach * math.sin(a1))], fill=70)
        glow = Image.new("L", (w, h), 0)
        gd = ImageDraw.Draw(glow)
        rr = min(w, h) * 0.6
        gd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=200)
        glow = glow.filter(ImageFilter.GaussianBlur(rr / 2.5))
        layer = ImageChops_lighter(layer.filter(ImageFilter.GaussianBlur(3)), glow)
        light = Image.new("RGBA", (w, h), ray_colour + (255,))
        light.putalpha(layer)
        img.alpha_composite(light)
    vig = Image.new("L", (w, h), 0)
    ImageDraw.Draw(vig).rectangle([0, 0, w, h], fill=120)
    ImageDraw.Draw(vig).ellipse([-w * 0.1, -h * 0.15, w * 1.1, h * 1.15], fill=0)
    vig = vig.filter(ImageFilter.GaussianBlur(min(w, h) / 7))
    dark = Image.new("RGBA", (w, h), (30, 10, 50, 255))
    dark.putalpha(vig)
    img.alpha_composite(dark)
    return img


def ImageChops_lighter(a, b):
    from PIL import ImageChops
    return ImageChops.lighter(a, b)


def beam(img, x, base_y, width, height, colour):
    """A soft beam of light standing up out of the floor, under a pal."""
    w, h = int(width), int(height)
    m = int(w / 3)
    layer = Image.new("L", (w + m * 2, h + m * 2), 0)
    d = ImageDraw.Draw(layer)
    for k in range(h):
        t = k / h
        half = w / 2 * (0.45 + 0.4 * t)
        d.line([(m + w / 2 - half, m + k), (m + w / 2 + half, m + k)], fill=int(150 * t ** 1.6))
    layer = layer.filter(ImageFilter.GaussianBlur(w / 9))
    light = Image.new("RGBA", layer.size, colour + (255,))
    light.putalpha(layer)
    full = Image.new("RGBA", img.size, (0, 0, 0, 0))
    full.paste(light, (int(x - w / 2 - m), int(base_y - h - m)), light)
    img.alpha_composite(full)
    # A pool of light on the floor.
    pw_, ph_ = int(w * 1.3), int(w * 0.36)
    m2 = int(w / 4)
    pool = Image.new("L", (pw_ + m2 * 2, ph_ + m2 * 2), 0)
    ImageDraw.Draw(pool).ellipse([m2, m2, m2 + pw_, m2 + ph_], fill=190)
    pool = pool.filter(ImageFilter.GaussianBlur(w / 14))
    p = Image.new("RGBA", pool.size, colour + (255,))
    p.putalpha(pool)
    full = Image.new("RGBA", img.size, (0, 0, 0, 0))
    full.paste(p, (int(x - pool.width / 2), int(base_y - pool.height / 2)), p)
    img.alpha_composite(full)


def tag(img, text, price, centre, colour):
    """A name tag under a pal: its name, and its price in tokens on a gold coin."""
    f = font(46)
    fp = font(34)
    d0 = ImageDraw.Draw(img)
    tw = d0.textlength(text, font=f)
    pw = d0.textlength(str(price), font=fp)
    w, h = int(max(tw, pw + 50) + 70), 118
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle([0, 0, w - 1, 62], radius=30, fill=colour + (255,), outline=(255, 255, 255, 255), width=5)
    d.text(((w - tw) / 2, 2), text, font=f, fill=(255, 255, 255), stroke_width=4, stroke_fill=(60, 20, 70))
    # The price, on a dark pill under it, with a coin.
    pw_total = int(pw + 58)
    px = (w - pw_total) // 2
    d.rounded_rectangle([px, 66, px + pw_total, 112], radius=22, fill=(40, 24, 60, 235))
    d.ellipse([px + 8, 72, px + 42, 106], fill=(255, 206, 60, 255), outline=(170, 110, 10, 255), width=3)
    d.text((px + 48, 68), str(price), font=fp, fill=(255, 236, 150))
    img.alpha_composite(layer, (int(centre[0] - w / 2), int(centre[1] - h / 2)))


def refine():
    W, H = 1920, 1080
    pals = {n: pal_cut(n) for n in PALS}
    hero = pop(cut_out(SHOTS / "hero_close.jpg"), saturation=1.15)

    # ===== THE ICON, the same look: a few pals big as stickers (an icon is seen small), SQUISH extruded over them,
    # OBBY in a burst. Made at 1024 and halved, with and without the words. =====
    for with_text in (True, False):
        S = 1024
        icon = sunburst(S, S, (255, 248, 210), (140, 70, 230), (255, 140, 210), (255, 186, 230), rays=18,
                        centre=(S / 2, S * 0.56))
        sparkles(icon, 18, 71, (30, 30, S - 30, S * 0.7), (16, 46))
        lift = 0 if with_text else -60
        layout = [("Pal_Bee", 0.15, 0.47, 230, -12), ("Pal_Cloud", 0.85, 0.46, 250, 8), ("Pal_Slime", 0.2, 0.8, 300, 6),
                  ("Pal_Lava", 0.81, 0.79, 320, -6), ("Pal_Needoh", 0.5, 0.74, 420, 0)]
        for name, x, y, size, rot in layout:
            p = pals[name]
            p = fit(p, height=size) if p.height >= p.width else fit(p, width=size)
            if rot:
                p = p.rotate(rot, resample=Image.BICUBIC, expand=True)
            st = sticker(p, outline=12, glow=PAL_GLOW[name], glow_size=26)
            icon.alpha_composite(st, (int(S * x - st.width / 2), int(S * y - st.height / 2 + (lift if with_text else 0))))
        if with_text:
            title3d(icon, "SQUISH", (S / 2, S * 0.15), 230, tilt=-5)
            burst(icon, "OBBY", (S * 0.5, S * 0.355), 128, size=82, fill=(255, 80, 120), edge=(255, 255, 255),
                  ink=(120, 10, 50), tilt=-6, points=16)
        save(icon, "icon.png" if with_text else "icon_no_text.png", (512, 512))

    # ===== THUMBNAIL 1: the hero huge in the middle, the pals round him as stickers, the spiral behind. =====
    img = scene_bg(SHOTS / "level1.jpg", W, H, blur=6, crop=CROPS["level1.jpg"]["card"], centre=(W / 2, H * 0.45))
    sparkles(img, 26, 41, (0, 0, W, H * 0.6), (14, 44))
    man = sticker(fit(hero, height=int(H * 0.8)), outline=12, glow=(255, 236, 140), glow_size=30)
    img.alpha_composite(man, (int(W * 0.5 - man.width / 2), H - man.height + 90))
    spots = [("Pal_Bee", 0.13, 0.36, 0.25, -10), ("Pal_Cloud", 0.86, 0.33, 0.24, 8), ("Pal_Needoh", 0.17, 0.86, 0.42, 0),
             ("Pal_Lava", 0.84, 0.84, 0.4, 0), ("Pal_Slime", 0.32, 0.93, 0.26, 0), ("Pal_Jelly", 0.68, 0.93, 0.26, 0)]
    for name, x, y, hh, rot in spots:
        p = fit(pals[name], height=int(H * hh))
        if rot:
            p = p.rotate(rot, resample=Image.BICUBIC, expand=True)
        s = sticker(p, outline=9, glow=PAL_GLOW[name], glow_size=24)
        img.alpha_composite(s, (int(W * x - s.width / 2), int(H * y - s.height / 2)))
    title3d(img, "SQUISH OBBY", (W / 2, H * 0.13), 196, tilt=-3)
    burst(img, "", (W * 0.86, H * 0.6), 150, lines=["SO", "SQUISHY!"], size=50, tilt=12)
    save(img, "thumb1_hero.png")

    # ===== THUMBNAIL 2: COLLECT CUTE PALS! Six on beams, name tags and prices, NEW! in a burst. =====
    img = sunburst(W, H, (255, 244, 250), (150, 70, 210), (255, 140, 210), (255, 184, 228), rays=22, centre=(W / 2, H * 0.62))
    floor = Image.new("RGBA", (W, int(H * 0.3)), (0, 0, 0, 0))
    fd = ImageDraw.Draw(floor)
    fd.ellipse([-W * 0.1, 0, W * 1.1, floor.height * 2], fill=(255, 220, 240, 150))
    img.alpha_composite(floor.filter(ImageFilter.GaussianBlur(30)), (0, int(H * 0.72)))
    sparkles(img, 40, 51, (0, 0, W, H * 0.7), (12, 40))
    row = [("Pal_Bee", 0.12), ("Pal_Slime", 0.27), ("Pal_Needoh", 0.42), ("Pal_Lava", 0.58), ("Pal_Jelly", 0.73), ("Pal_Cloud", 0.88)]
    for k, (name, x) in enumerate(row):
        cx = W * x
        base = H * 0.78
        beam(img, cx, base, 230, 560, PAL_GLOW[name])
    for k, (name, x) in enumerate(row):
        cx = W * x
        base = H * 0.78
        box = 250 if name not in ("Pal_Needoh", "Pal_Lava") else 280
        p = pals[name]
        p = fit(p, height=box) if p.height >= p.width else fit(p, width=box)
        s = sticker(p, outline=8, glow=PAL_GLOW[name], glow_size=20)
        img.alpha_composite(s, (int(cx - s.width / 2), int(base - s.height + 40 - (40 if name in ("Pal_Bee", "Pal_Cloud") else 0))))
        nm, price = PAL_NAMES[name]
        tag(img, nm, price, (cx, base + 70), tuple(int(c * 0.75) for c in PAL_GLOW[name]))
    title3d(img, "COLLECT CUTE PALS!", (W * 0.53, H * 0.15), 144, tilt=-3)
    burst(img, "NEW!", (W * 0.07, H * 0.34), 100, fill=(255, 80, 120), edge=(255, 255, 255), ink=(120, 10, 50), size=52, tilt=-14)
    save(img, "thumb2_pals.png")

    # ===== THUMBNAIL 4: the bay, the hero and his pals stepping out of it, NEW GAME! =====
    img = scene_bg(SHOTS / "lobby.jpg", W, H, blur=3, rays=True, centre=(W * 0.62, H * 0.35), darken=0.05)
    sparkles(img, 24, 61, (W * 0.3, 0, W, H * 0.5), (12, 38))
    man = sticker(fit(hero, height=int(H * 0.8)), outline=12, glow=(255, 236, 140), glow_size=30)
    img.alpha_composite(man, (int(W * 0.2 - man.width / 2), H - man.height + 50))
    group = [("Pal_Cloud", 0.66, 0.5, 0.24), ("Pal_Bee", 0.88, 0.46, 0.22), ("Pal_Lava", 0.78, 0.66, 0.3),
             ("Pal_Slime", 0.56, 0.86, 0.28), ("Pal_Needoh", 0.75, 0.88, 0.36), ("Pal_Jelly", 0.93, 0.88, 0.28)]
    for name, x, y, hh in group:
        s = sticker(fit(pals[name], height=int(H * hh)), outline=8, glow=PAL_GLOW[name], glow_size=20)
        img.alpha_composite(s, (int(W * x - s.width / 2), int(H * y - s.height / 2)))
    title3d(img, "SQUISH OBBY", (W * 0.58, H * 0.15), 190, tilt=-3)
    burst(img, "", (W * 0.43, H * 0.5), 130, lines=["NEW", "GAME!"], size=54, fill=(255, 80, 120), edge=(255, 255, 255),
          ink=(120, 10, 50), tilt=-10)
    save(img, "thumb4_bay.png")


# ===== THE THIRD LOOK (2026-11-19, "work even more on these") =====
#
# The next layer the big games' art has: a RIM LIGHT on each subject (a bright edge on its upper side, so it reads as
# round and lit), CONTACT SHADOWS (each thing sits on something), glossy PODIUMS, ACTION (splash drops, speed lines),
# the squishy ball SQUASHED a little (it says squish before a word is read), and a last GRADE (sharper, a touch more
# colour, darker edges). The worlds thumbnail is brought into the same look.


def rim(cut, strength=150, colour=(255, 255, 255), shift=(-6, -8), width=7):
    """A bright edge on a cut-out's upper left, where the light comes from."""
    a = cut.getchannel("A")
    moved = Image.new("L", a.size, 0)
    moved.paste(a, shift)
    band = ImageChops_subtract(a, moved).filter(ImageFilter.GaussianBlur(width / 3))
    band = band.point(lambda v: min(255, v * strength // 255))
    band = ImageChops_multiply(band, a)
    light = Image.new("RGBA", cut.size, colour + (255,))
    light.putalpha(band)
    out = cut.copy()
    out.alpha_composite(light)
    return out.filter(ImageFilter.UnsharpMask(radius=2, percent=70, threshold=2))


def ImageChops_subtract(a, b):
    from PIL import ImageChops
    return ImageChops.subtract(a, b)


def ImageChops_multiply(a, b):
    from PIL import ImageChops
    return ImageChops.multiply(a, b)


def contact(img, cx, y, w, strength=150):
    """A soft dark oval on the ground under something."""
    h = max(8, int(w * 0.22))
    m = int(w * 0.3)
    layer = Image.new("L", (w + m * 2, h + m * 2), 0)
    ImageDraw.Draw(layer).ellipse([m, m, m + w, m + h], fill=strength)
    layer = layer.filter(ImageFilter.GaussianBlur(w / 12))
    dark = Image.new("RGBA", layer.size, (40, 10, 50, 255))
    dark.putalpha(layer)
    full = Image.new("RGBA", img.size, (0, 0, 0, 0))
    full.paste(dark, (int(cx - w / 2 - m), int(y - h / 2 - m)), dark)
    img.alpha_composite(full)


def podium(img, cx, top_y, w, colour, depth=None):
    """A round glossy podium: its side, its top, a shine across the top."""
    depth = depth or int(w * 0.16)
    th = int(w * 0.28)
    layer = Image.new("RGBA", (w + 40, th + depth + 40), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    side = tuple(int(c * 0.62) for c in colour)
    d.rectangle([20, 20 + th // 2, 20 + w, 20 + th // 2 + depth], fill=side + (255,))
    d.ellipse([20, 20 + depth, 20 + w, 20 + depth + th], fill=side + (255,))
    d.ellipse([20, 20, 20 + w, 20 + th], fill=colour + (255,), outline=(255, 255, 255, 255), width=5)
    d.ellipse([20 + w * 0.18, 20 + th * 0.18, 20 + w * 0.62, 20 + th * 0.48], fill=(255, 255, 255, 90))
    img.alpha_composite(layer, (int(cx - w / 2 - 20), int(top_y - th / 2 - 20)))


def drops(img, cx, cy, spread, colour, count=9, seed=1, size=(14, 34)):
    """Splash drops flung out round a point: each a round drop with a shine on it."""
    rng = random.Random(seed)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    dark = tuple(int(c * 0.7) for c in colour)
    for k in range(count):
        # An even fan, left to right over the top, each a little jittered, so they read as a splash, not a chain.
        ang = math.pi * (1.08 + 0.84 * (k + rng.uniform(-0.3, 0.3)) / max(1, count - 1))
        r = rng.uniform(spread * 0.7, spread)
        x, y = cx + math.cos(ang) * r, cy + math.sin(ang) * r * 0.45
        s = rng.uniform(*size)
        d.ellipse([x - s, y - s, x + s, y + s], fill=dark + (255,))
        d.ellipse([x - s * 0.85, y - s * 0.9, x + s * 0.8, y + s * 0.7], fill=colour + (255,))
        d.ellipse([x - s * 0.5, y - s * 0.6, x - s * 0.1, y - s * 0.2], fill=(255, 255, 255, 200))
    img.alpha_composite(layer)


def speed_lines(img, cx, cy, inner, outer, count=34, colour=(255, 255, 255), alpha=90, seed=2):
    """Thin lines out of a middle, like a comic's: there is energy here."""
    rng = random.Random(seed)
    layer = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(layer)
    for k in range(count):
        a = 2 * math.pi * k / count + rng.uniform(-0.05, 0.05)
        r0 = inner * rng.uniform(0.9, 1.2)
        r1 = outer * rng.uniform(0.8, 1.1)
        w = rng.uniform(2, 7)
        p0 = (cx + math.cos(a) * r0, cy + math.sin(a) * r0)
        p1 = (cx + math.cos(a + 0.012) * r1, cy + math.sin(a + 0.012) * r1)
        p2 = (cx + math.cos(a - 0.012) * r1, cy + math.sin(a - 0.012) * r1)
        d.polygon([p0, p1, p2], fill=alpha)
    layer = layer.filter(ImageFilter.GaussianBlur(1.5))
    light = Image.new("RGBA", img.size, colour + (255,))
    light.putalpha(layer)
    img.alpha_composite(light)


def squash(cut, x=1.1, y=0.9):
    return cut.resize((int(cut.width * x), int(cut.height * y)), Image.LANCZOS)


def final(img):
    """The last grade: a touch more colour and contrast, sharper, darker at the edges."""
    w, h = img.size
    rgb = img.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(1.08)
    rgb = ImageEnhance.Contrast(rgb).enhance(1.05)
    rgb = rgb.filter(ImageFilter.UnsharpMask(radius=2, percent=45, threshold=3))
    vig = Image.new("L", (w, h), 0)
    ImageDraw.Draw(vig).rectangle([0, 0, w, h], fill=80)
    ImageDraw.Draw(vig).ellipse([-w * 0.08, -h * 0.12, w * 1.08, h * 1.12], fill=0)
    vig = vig.filter(ImageFilter.GaussianBlur(min(w, h) / 8))
    dark = Image.new("RGB", (w, h), (30, 8, 45))
    return Image.composite(dark, rgb, vig).convert("RGBA")


def place(img, st, cx, bottom):
    """A sticker stood with its feet at `bottom`, centred on `cx` (its glow and outline hang past)."""
    img.alpha_composite(st, (int(cx - st.width / 2), int(bottom - st.height)))


def pal_sticker(pals, name, size, rot=0, squashed=False, outline=10, glow_size=22):
    p = pals[name]
    p = fit(p, height=size) if p.height >= p.width else fit(p, width=size)
    if squashed:
        p = squash(p)
    p = rim(p)
    if rot:
        p = p.rotate(rot, resample=Image.BICUBIC, expand=True)
    return sticker(p, outline=outline, glow=PAL_GLOW[name], glow_size=glow_size)


def refine2():
    W, H = 1920, 1080
    pals = {n: pal_cut(n) for n in PALS}
    hero = backlit(rim(lifted(pop(cut_out(SHOTS / "hero_close.jpg"), saturation=1.15)), strength=170, width=9))

    # ===== THE ICON =====
    for with_text in (True, False):
        S = 1024
        icon = sunburst(S, S, (255, 250, 220), (130, 60, 225), (255, 136, 210), (255, 184, 230), rays=18,
                        centre=(S / 2, S * 0.6))
        speed_lines(icon, S / 2, S * 0.62, S * 0.3, S * 0.75, alpha=70)
        sparkles(icon, 16, 71, (30, 30, S - 30, S * 0.65), (16, 46))
        off = 0 if with_text else -70
        # A glossy slime floor under them, a pink puddle catching the light.
        floor = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        fd = ImageDraw.Draw(floor)
        fd.ellipse([S * 0.02, S * 0.84 + off, S * 0.98, S * 1.14 + off], fill=(236, 96, 170, 255))
        fd.ellipse([S * 0.04, S * 0.82 + off, S * 0.96, S * 1.1 + off], fill=(255, 150, 206, 255))
        fd.ellipse([S * 0.2, S * 0.845 + off, S * 0.6, S * 0.9 + off], fill=(255, 230, 245, 150))
        icon.alpha_composite(floor)
        for name, x, size, rot, lift in (("Pal_Slime", 0.19, 280, 6, 0), ("Pal_Lava", 0.83, 300, -6, 0)):
            st = pal_sticker(pals, name, size, rot)
            contact(icon, S * x, S * 0.9 + off, int(size * 0.8))
            place(icon, st, S * x, S * 0.93 + off)
        for name, x, y, size, rot in (("Pal_Bee", 0.15, 0.5, 220, -12), ("Pal_Cloud", 0.85, 0.48, 240, 8)):
            st = pal_sticker(pals, name, size, rot)
            icon.alpha_composite(st, (int(S * x - st.width / 2), int(S * y - st.height / 2 + off)))
        contact(icon, S * 0.5, S * 0.93 + off, 380, strength=170)
        st = pal_sticker(pals, "Pal_Needoh", 385, squashed=True, outline=13, glow_size=28)
        place(icon, st, S * 0.5, S * 0.99 + off)
        wobble(icon, S * 0.5, S * 0.99 + off - st.height / 2 + 20, st.width * 0.36)
        if with_text:
            title3d(icon, "SQUISH", (S / 2, S * 0.15), 230, tilt=-5)
            burst(icon, "OBBY", (S * 0.5, S * 0.355), 128, size=82, fill=(255, 80, 120), edge=(255, 255, 255),
                  ink=(120, 10, 50), tilt=-6, points=16)
        save(final(icon), "icon.png" if with_text else "icon_no_text.png", (512, 512))

    # ===== THUMBNAIL 1: the hero bursting out of the spiral, a slime squishing under him =====
    img = scene_bg(SHOTS / "level1.jpg", W, H, blur=6, crop=CROPS["level1.jpg"]["card"], centre=(W / 2, H * 0.5))
    speed_lines(img, W / 2, H * 0.55, H * 0.35, W * 0.8, count=40, alpha=80)
    sparkles(img, 22, 41, (0, 0, W, H * 0.55), (14, 44))
    # The slime he lands on, squashed flat, splashing.
    contact(img, W * 0.5, H * 1.0, 720, strength=170)
    slime = pal_sticker(pals, "Pal_Slime", 300, squashed=True)
    slime = slime.resize((int(slime.width * 1.6), int(slime.height * 0.75)), Image.LANCZOS)
    place(img, slime, W * 0.5, H + 70)
    drops(img, W * 0.5, H * 0.97, 360, (140, 236, 110), count=11, seed=9, size=(12, 26))
    man = sticker(fit(hero, height=int(H * 0.8)), outline=12, glow=(255, 236, 140), glow_size=30)
    img.alpha_composite(man, (int(W * 0.5 - man.width / 2), H - man.height + 10))
    for name, x, y, size, rot in (("Pal_Bee", 0.14, 0.38, 270, -10), ("Pal_Cloud", 0.86, 0.36, 280, 8)):
        st = pal_sticker(pals, name, size, rot)
        img.alpha_composite(st, (int(W * x - st.width / 2), int(H * y - st.height / 2)))
    for name, x, size in (("Pal_Needoh", 0.15, 430), ("Pal_Jelly", 0.33, 270), ("Pal_Lava", 0.85, 420)):
        st = pal_sticker(pals, name, size, squashed=name == "Pal_Needoh")
        contact(img, W * x, H * 0.99, int(size * 0.9))
        place(img, st, W * x, H + 40)
    title3d(img, "SQUISH OBBY", (W / 2, H * 0.13), 196, tilt=-3)
    burst(img, "", (W * 0.67, H * 0.52), 140, lines=["SO", "SQUISHY!"], size=50, tilt=12)
    save(final(img), "thumb1_hero.png")

    # ===== THUMBNAIL 2: COLLECT CUTE PALS! on podiums, under beams, with their names and prices =====
    img = sunburst(W, H, (255, 244, 250), (150, 70, 210), (255, 140, 210), (255, 184, 228), rays=22, centre=(W / 2, H * 0.6))
    sparkles(img, 36, 51, (0, 0, W, H * 0.65), (12, 40))
    row = [("Pal_Bee", 0.115), ("Pal_Slime", 0.27), ("Pal_Needoh", 0.425), ("Pal_Lava", 0.575), ("Pal_Jelly", 0.73),
           ("Pal_Cloud", 0.885)]
    top = H * 0.74
    for name, x in row:
        beam(img, W * x, top, 220, 540, PAL_GLOW[name])
    for name, x in row:
        podium(img, W * x, top, 250, tuple(int(c * 0.85 + 30) for c in PAL_GLOW[name]))
    for name, x in row:
        big = name in ("Pal_Needoh", "Pal_Lava")
        st = pal_sticker(pals, name, 250 if big else 220, outline=8, glow_size=18)
        flying = name in ("Pal_Bee", "Pal_Cloud")
        place(img, st, W * x, top + 40 - (60 if flying else 0))
        # Its reflection in the shiny floor under the podium, fading away.
        ref = st.transpose(Image.FLIP_TOP_BOTTOM)
        fade = Image.new("L", ref.size, 0)
        fdr = ImageDraw.Draw(fade)
        for yy in range(ref.height):
            fdr.line([(0, yy), (ref.width, yy)], fill=int(70 * max(0, 1 - yy / (ref.height * 0.5))))
        from PIL import ImageChops
        ref.putalpha(ImageChops.multiply(ref.getchannel("A"), fade))
        img.alpha_composite(ref, (int(W * x - ref.width / 2), int(top + 120)))
        nm, price = PAL_NAMES[name]
        tag(img, nm, price, (W * x, top + 150), tuple(int(c * 0.75) for c in PAL_GLOW[name]))
    title3d(img, "COLLECT CUTE PALS!", (W * 0.53, H * 0.14), 144, tilt=-3)
    burst(img, "NEW!", (W * 0.07, H * 0.33), 100, fill=(255, 80, 120), edge=(255, 255, 255), ink=(120, 10, 50), size=52,
          tilt=-14)
    save(final(img), "thumb2_pals.png")

    # ===== THUMBNAIL 3: 5 WORLDS, cards as stickers, a pal peeking in each bottom corner =====
    img = sunburst(W, H, (255, 240, 200), (255, 110, 80), (255, 166, 110), (255, 196, 140), rays=22, centre=(W / 2, H * 0.6))
    sparkles(img, 26, 31, (0, 0, W, H * 0.45), (12, 40))
    names = ["City Shore", "Sky Pools", "Sunken City", "Flooded Halls", "Hill House"]
    spots = [(0.18, 0.445, 4), (0.5, 0.425, 0), (0.82, 0.445, -4), (0.33, 0.825, 2), (0.67, 0.825, -2)]
    for k in range(5):
        c = card(SHOTS / ("level%d.jpg" % (k + 1)), (520, 293), spots[k][2], names[k])
        c = sticker(c, outline=0 + 1, glow=(255, 236, 160), glow_size=18)
        img.alpha_composite(c, (int(W * spots[k][0] - c.width / 2), int(H * spots[k][1] - c.height / 2)))
    for name, x, size, rot in (("Pal_Needoh", 0.06, 300, 8), ("Pal_Lava", 0.95, 290, -8)):
        st = pal_sticker(pals, name, size, rot)
        place(img, st, W * x, H + 50)
    title3d(img, "5 WORLDS TO SQUISH!", (W * 0.5, H * 0.13), 146, tilt=-3)
    save(final(img), "thumb3_worlds.png")

    # ===== THUMBNAIL 4: the bay, the hero and his pals stepping out of it, NEW GAME! =====
    img = scene_bg(SHOTS / "lobby.jpg", W, H, blur=3, rays=True, centre=(W * 0.62, H * 0.35), darken=0.08)
    # A darker foot to the picture, so the subjects stand out of it.
    foot = Image.new("L", (W, H), 0)
    fdraw = ImageDraw.Draw(foot)
    for yy in range(H):
        fdraw.line([(0, yy), (W, yy)], fill=int(170 * max(0, (yy / H - 0.5) / 0.5) ** 1.6))
    shade = Image.new("RGBA", (W, H), (30, 10, 50, 255))
    shade.putalpha(foot)
    img.alpha_composite(shade)
    sparkles(img, 20, 61, (W * 0.3, 0, W, H * 0.45), (12, 38))
    contact(img, W * 0.2, H * 0.99, 420)
    man = sticker(fit(hero, height=int(H * 0.8)), outline=12, glow=(255, 236, 140), glow_size=30)
    img.alpha_composite(man, (int(W * 0.2 - man.width / 2), H - man.height + 50))
    for name, x, y, size, rot in (("Pal_Cloud", 0.64, 0.5, 250, 6), ("Pal_Bee", 0.92, 0.3, 200, -10)):
        st = pal_sticker(pals, name, size, rot)
        img.alpha_composite(st, (int(W * x - st.width / 2), int(H * y - st.height / 2)))
    podium(img, W * 0.76, H * 0.83, 560, (255, 170, 214))
    st = pal_sticker(pals, "Pal_Lava", 290)
    place(img, st, W * 0.885, H * 0.78)
    for name, x, size, bottom in (("Pal_Slime", 0.575, 250, 0.93), ("Pal_Jelly", 0.95, 220, 0.99)):
        st = pal_sticker(pals, name, size)
        place(img, st, W * x, H * bottom)
    st = pal_sticker(pals, "Pal_Needoh", 340, squashed=True, outline=12)
    place(img, st, W * 0.735, H * 0.96)
    title3d(img, "SQUISH OBBY", (W * 0.58, H * 0.15), 190, tilt=-3)
    burst(img, "", (W * 0.42, H * 0.5), 130, lines=["NEW", "GAME!"], size=54, fill=(255, 80, 120), edge=(255, 255, 255),
          ink=(120, 10, 50), tilt=-10)
    save(final(img), "thumb4_bay.png")


# ===== THE FOURTH LOOK (2026-11-19, "make the badges better too in the same style and improve these even more") =====


def lifted(cut, gamma=0.78):
    """Shadows opened up (a black outfit reads as a hole at thumbnail size), the alpha kept."""
    a = cut.getchannel("A")
    rgb = cut.convert("RGB").point(lambda v: int(255 * (v / 255) ** gamma))
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out


def backlit(cut, colour=(140, 220, 255)):
    """A coloured back light on the right edge, as the big games' art has (one warm side, one cool)."""
    return rim(cut, strength=210, colour=colour, shift=(9, -1), width=10)


_title3d_plain = title3d


def title3d(img, text, centre, size, fill_top=(255, 250, 160), fill_bottom=(255, 140, 30), outline=(70, 20, 80),
            depth=None, tilt=-3):
    """The extruded title, now with a highlight along the top of every letter and a soft glow round it."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    _title3d_plain(layer, text, centre, size, fill_top, fill_bottom, outline, depth, tilt)
    a = layer.getchannel("A")
    glow = a.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(size / 7)).point(lambda v: v * 120 // 255)
    g = Image.new("RGBA", img.size, (255, 236, 170, 255))
    g.putalpha(glow)
    img.alpha_composite(g)
    img.alpha_composite(rim(layer, strength=150, colour=(255, 255, 255), shift=(0, -5), width=6))


def wobble(img, cx, cy, r, colour=(255, 255, 255)):
    """Comic wobble arcs either side of something: it just went squish."""
    for side in (-1, 1):
        for k, (rr, wdt) in enumerate(((r * 1.08, 12), (r * 1.22, 9))):
            box = [cx - rr, cy - rr * 0.8, cx + rr, cy + rr * 0.8]
            start, end = (150, 210) if side < 0 else (-30, 30)
            arc = Image.new("RGBA", img.size, (0, 0, 0, 0))
            d = ImageDraw.Draw(arc)
            d.arc(box, start, end, fill=(60, 20, 80, 255), width=wdt + 8)
            d.arc(box, start, end, fill=colour + (255,), width=wdt)
            img.alpha_composite(arc)


def gold_ring(size, light=(255, 236, 140), dark=(196, 120, 20), edge=(90, 40, 10), inner_frac=0.8):
    """A chunky round ring: dark outline, a gold band lit from above, a thin dark line inside."""
    S = size
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([0, 0, S - 1, S - 1], fill=edge + (255,))
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        t = y / (S - 1)
        gd.line([(0, y), (S, y)], fill=tuple(int(light[i] + (dark[i] - light[i]) * t) for i in range(3)) + (255,))
    band = Image.new("L", (S, S), 0)
    ImageDraw.Draw(band).ellipse([S * 0.025, S * 0.025, S * 0.975, S * 0.975], fill=255)
    img.paste(grad, (0, 0), band)
    i0 = S * (1 - inner_frac) / 2
    d.ellipse([i0 - S * 0.015, i0 - S * 0.015, S - i0 + S * 0.015, S - i0 + S * 0.015], fill=edge + (255,))
    return img, (i0, S - i0)


def badge_v2(inner, number=None, ring=((255, 236, 140), (196, 120, 20), (90, 40, 10)), size=1024):
    """A badge: the picture in a chunky gold ring, a gloss over the top, its number on a medallion if it has one."""
    S = size
    img, (a, b) = gold_ring(S, *ring)
    s = int(b - a)
    pic = inner.convert("RGBA")
    scale = max(s / pic.width, s / pic.height)
    pic = pic.resize((int(pic.width * scale) + 1, int(pic.height * scale) + 1), Image.LANCZOS)
    pic = pic.crop(((pic.width - s) // 2, (pic.height - s) // 2, (pic.width - s) // 2 + s, (pic.height - s) // 2 + s))
    m = Image.new("L", (s, s), 0)
    ImageDraw.Draw(m).ellipse([0, 0, s - 1, s - 1], fill=255)
    img.paste(pic, (int(a), int(a)), m)
    # Inner shadow at the picture's rim, then a gloss across the top of the whole badge.
    shade = Image.new("L", (S, S), 0)
    ImageDraw.Draw(shade).ellipse([a, a, b, b], fill=255)
    ImageDraw.Draw(shade).ellipse([a + S * 0.03, a + S * 0.045, b - S * 0.03, b - S * 0.01], fill=0)
    shade = shade.filter(ImageFilter.GaussianBlur(S / 60))
    sh = Image.new("RGBA", (S, S), (20, 5, 30, 255))
    sh.putalpha(shade.point(lambda v: v * 150 // 255))
    img.alpha_composite(sh)
    gloss = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gloss).ellipse([S * 0.12, S * 0.05, S * 0.88, S * 0.52], fill=70)
    gloss = gloss.filter(ImageFilter.GaussianBlur(S / 40))
    clip = Image.new("L", (S, S), 0)
    ImageDraw.Draw(clip).ellipse([S * 0.02, S * 0.02, S * 0.98, S * 0.98], fill=255)
    from PIL import ImageChops
    gloss = ImageChops.multiply(gloss, clip)
    img.alpha_composite(Image.merge("RGBA", (Image.new("L", (S, S), 255),) * 3 + (gloss,)))
    sparkle(img, S * 0.2, S * 0.2, S * 0.05, (255, 255, 255, 240))
    if number is not None:
        r = int(S * 0.14)
        cx, cy = S / 2, S * 0.86
        med, _ = gold_ring(r * 2, (255, 240, 160), (230, 150, 30), (90, 40, 10), inner_frac=0.78)
        img.alpha_composite(med, (int(cx - r), int(cy - r)))
        title3d(img, str(number), (cx, cy - 4), int(r * 1.25), fill_top=(255, 255, 255), fill_bottom=(255, 226, 170),
                outline=(110, 50, 10), tilt=0)
    return img


def key_sticker(size, glow=(255, 236, 140)):
    k = key_glyph(size)
    box = k.getchannel("A").getbbox()
    k = k.crop(box)
    return sticker(rim(k, strength=170), outline=12, glow=glow, glow_size=26)


def crown_glyph(w):
    """A little gold crown: three points with gems, on a band."""
    h = int(w * 0.62)
    img = Image.new("RGBA", (w + 40, h + 40), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    o = 20
    pts = [(o, o + h), (o, o + h * 0.3), (o + w * 0.25, o + h * 0.62), (o + w * 0.5, o), (o + w * 0.75, o + h * 0.62),
           (o + w, o + h * 0.3), (o + w, o + h)]
    d.polygon(pts, fill=(120, 60, 10, 255))
    inner = [(x + (o + w / 2 - x) * 0.06, y + (o + h * 0.6 - y) * 0.08) for x, y in pts]
    d.polygon(inner, fill=(255, 210, 70, 255))
    d.rectangle([o + w * 0.04, o + h * 0.74, o + w * 0.96, o + h * 0.94], fill=(240, 170, 40, 255))
    for gx, gy, c in ((0.5, 0.16, (255, 80, 120)), (0.08, 0.38, (100, 200, 255)), (0.92, 0.38, (120, 240, 140))):
        rr = w * 0.07
        d.ellipse([o + w * gx - rr, o + h * gy - rr, o + w * gx + rr, o + h * gy + rr], fill=c + (255,))
    return sticker(rim(img, strength=170), outline=10, glow=(255, 236, 140), glow_size=22)


def glossy_ball(d_img, cx, cy, r, colour):
    d = ImageDraw.Draw(d_img)
    dark = tuple(int(c * 0.62) for c in colour)
    d.ellipse([cx - r - 6, cy - r - 6, cx + r + 6, cy + r + 6], fill=(255, 255, 255, 255))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=dark + (255,))
    d.ellipse([cx - r * 0.95, cy - r * 0.98, cx + r * 0.9, cy + r * 0.8], fill=colour + (255,))
    d.ellipse([cx - r * 0.6, cy - r * 0.7, cx - r * 0.05, cy - r * 0.25], fill=(255, 255, 255, 190))


def badges_v2():
    out = OUT / "badges"
    out.mkdir(parents=True, exist_ok=True)
    S = 1024
    I = int(S * 0.8)

    def write(img, name):
        graded_img = final(img)
        graded_img.putalpha(img.getchannel("A"))  # (the grade is for the picture; the corners stay clear)
        graded_img.resize((512, 512), Image.LANCZOS).save(out / name)
        print("wrote", out / name)

    # THE LEVELS: the cinematic view, its number on a medallion.
    for k in range(5):
        shot = level_shot(SHOTS / ("level%d.jpg" % (k + 1)), "badge")
        shot = ImageEnhance.Brightness(shot).enhance(1.08)
        write(badge_v2(shot, number=k + 1), "level%d.png" % (k + 1))

    # THE STORY: the key, a sticker, on a green burst with speed lines.
    art = sunburst(I, I, (230, 255, 220), (30, 130, 70), (90, 200, 120), (130, 225, 150), rays=16)
    speed_lines(art, I / 2, I / 2, I * 0.25, I * 0.7, count=26, alpha=70)
    k = key_sticker(int(I * 0.78))
    art.alpha_composite(k, (int(I / 2 - k.width / 2), int(I / 2 - k.height / 2)))
    sparkles(art, 10, 3, (40, 40, I - 40, I - 40), (14, 36))
    write(badge_v2(art), "story.png")

    # HARDCORE: the key in flames, the ring red-hot.
    art = sunburst(I, I, (255, 236, 170), (150, 20, 20), (230, 70, 40), (250, 120, 60), rays=16)
    flames(art, I / 2, I * 0.95, I * 0.95, I * 0.6, seed=5)
    k = key_sticker(int(I * 0.74), glow=(255, 150, 60))
    art.alpha_composite(k, (int(I / 2 - k.width / 2), int(I * 0.42 - k.height / 2)))
    write(badge_v2(art, ring=((255, 170, 110), (180, 40, 20), (70, 10, 5))), "storyHardcore.png")

    # THE BACK ROOMS: the yellow corridor, darkened, a big question mark: a secret.
    back = Image.open(SHOTS / "backrooms.jpg").convert("RGB")
    bw_, bh_ = back.size
    back = back.crop((bw_ - bh_, 0, bw_, bh_)).resize((I, I), Image.LANCZOS)
    back = ImageEnhance.Brightness(ImageEnhance.Contrast(back).enhance(1.15)).enhance(0.72).convert("RGBA")
    title3d(back, "?", (I / 2, I * 0.5), int(I * 0.62), fill_top=(255, 250, 190), fill_bottom=(240, 190, 40),
            outline=(60, 40, 10), tilt=8)
    write(badge_v2(back, ring=((250, 236, 150), (170, 140, 40), (60, 45, 10))), "backRooms.png")

    # EVERY MATERIAL: glossy blobs of the materials' colours in a ring round a sparkle.
    art = sunburst(I, I, (255, 246, 255), (150, 80, 220), (230, 170, 250), (246, 206, 255), rays=16)
    colours = [(239, 159, 39), (151, 196, 89), (236, 96, 120), (120, 180, 255), (250, 199, 117), (196, 170, 246),
               (255, 128, 48), (130, 212, 190), (255, 226, 110), (120, 90, 80)]
    layer = Image.new("RGBA", (I, I), (0, 0, 0, 0))
    for n, c in enumerate(colours):
        a = 2 * math.pi * n / len(colours) - math.pi / 2
        glossy_ball(layer, I / 2 + math.cos(a) * I * 0.3, I / 2 + math.sin(a) * I * 0.3, I * 0.085, c)
    art.alpha_composite(rim(layer, strength=120))
    sparkle(art, I / 2, I / 2, I * 0.16, (255, 255, 255, 255))
    sparkle(art, I / 2, I / 2, I * 0.09, (255, 236, 150, 255))
    write(badge_v2(art, ring=((255, 210, 240), (200, 90, 170), (80, 20, 70))), "materials.png")

    # THE TRUE ENDING: the golden key under a crown, gold on gold.
    art = sunburst(I, I, (255, 252, 230), (210, 140, 30), (255, 206, 90), (255, 230, 150), rays=16)
    speed_lines(art, I / 2, I / 2, I * 0.25, I * 0.7, count=26, alpha=80)
    k = key_sticker(int(I * 0.7))
    art.alpha_composite(k, (int(I / 2 - k.width / 2), int(I * 0.58 - k.height / 2)))
    c = crown_glyph(int(I * 0.42))
    art.alpha_composite(c, (int(I / 2 - c.width / 2), int(I * 0.12)))
    sparkles(art, 12, 9, (40, 40, I - 40, I - 40), (14, 36))
    write(badge_v2(art), "trueEnding.png")


if __name__ == "__main__":
    build()
    refine2()
    badges_v2()
