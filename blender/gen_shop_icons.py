"""The store icons for the game's passes and products (the two-hundred-and-thirteenth pass, from your note of 2026-11-13:
everything sold "has to be very good quality and live up to their name, so that the players really do wanna buy").

    python blender/gen_shop_icons.py            every icon, into shop_icons/<id>.png (512 square)
    python blender/gen_shop_icons.py VIP        only those named

What Roblox shows on the game's page and in its own purchase window. Chunky simulator style, the shop's own: a glossy
rounded badge in the item's colours with a dark rim, faint rays behind, one big clear picture of the thing (a gold
crown, coins, a gift, a porthole, a flag), and its words in Nunito, white with a dark outline. Drawn at twice the size
and scaled down, so every edge is smooth. Nunito comes from Studio's own fonts (the game uses no other face).
"""
import math
import pathlib
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE.parent / "shop_icons"
S = 1024  # drawn at twice 512


def nunito():
    exe = subprocess.run(["powershell", "-NoProfile", "-Command",
                          "(Get-Process RobloxStudioBeta | Select-Object -First 1).Path"], capture_output=True, text=True).stdout.strip()
    if exe:
        path = pathlib.Path(exe).parent / "content" / "fonts" / "Nunito-Regular.ttf"
        if path.exists():
            return str(path)
    for guess in sorted(pathlib.Path.home().glob("AppData/Local/Roblox/Versions/*/content/fonts/Nunito-Regular.ttf")):
        return str(guess)
    sys.exit("Nunito not found: open Studio (its fonts are where this reads Nunito from)")


FONT = nunito()


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def radial(size, inner, outer):
    img = Image.new("RGB", (size, size), outer)
    px = img.load()
    c = size / 2
    for y in range(size):
        for x in range(size):
            d = min(1.0, math.hypot(x - c, y - c * 0.8) / (size * 0.72))
            px[x, y] = mix(inner, outer, d ** 1.4)
    return img


def badge(colours):
    """The rounded badge: a dark rim, the radial body, faint rays, and a gloss across its top."""
    light, mid, dark, rim = colours
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((40, 40, S - 40, S - 40), radius=190, fill=255)
    body = radial(S // 4, light, mid).resize((S, S), Image.BICUBIC).convert("RGBA")
    # Rays turning out from behind the picture.
    rays = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rays)
    c = (S / 2, S * 0.44)
    for k in range(16):
        a0 = k * math.pi * 2 / 16
        a1 = a0 + math.pi / 16
        rd.polygon([c, (c[0] + math.cos(a0) * S, c[1] + math.sin(a0) * S), (c[0] + math.cos(a1) * S, c[1] + math.sin(a1) * S)],
                   fill=(255, 255, 255, 34))
    body = Image.alpha_composite(body, rays)
    # A darker floor at the bottom, for weight.
    shade = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shade).ellipse((-S * 0.3, S * 0.72, S * 1.3, S * 1.6), fill=dark + (120,))
    body = Image.alpha_composite(body, shade.filter(ImageFilter.GaussianBlur(40)))
    base.paste(body, (0, 0), mask)
    # The rim, thick and dark, and a pale line inside it.
    d = ImageDraw.Draw(base)
    d.rounded_rectangle((40, 40, S - 40, S - 40), radius=190, outline=rim + (255,), width=34)
    d.rounded_rectangle((74, 74, S - 74, S - 74), radius=158, outline=(255, 255, 255, 70), width=8)
    # The gloss: a soft white sweep across the top third.
    gloss = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(gloss).ellipse((90, 70, S - 90, S * 0.42), fill=(255, 255, 255, 46))
    gmask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(gmask).rounded_rectangle((74, 74, S - 74, S - 74), radius=158, fill=255)
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(gloss.filter(ImageFilter.GaussianBlur(6)), (0, 0), gmask)
    return Image.alpha_composite(base, clipped)


def shadow_of(layer, blur=18, offset=(0, 22), alpha=110):
    a = layer.split()[3].point(lambda v: min(255, v) * alpha // 255)
    sh = Image.new("RGBA", layer.size, (20, 10, 30, 0))
    sh.putalpha(a)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    out.paste(sh, offset, sh)
    return out


def with_shadow(base, layer):
    return Image.alpha_composite(Image.alpha_composite(base, shadow_of(layer)), layer)


def words(base, text, y, size, ink=(255, 255, 255), outline=(40, 24, 60)):
    """Chunky words: Nunito thickened with a stroke of its own colour, a dark outline round that, a drop under it."""
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    font = ImageFont.truetype(FONT, size)
    while d.textlength(text, font=font) > S * 0.78 and size > 40:
        size -= 6
        font = ImageFont.truetype(FONT, size)
    w = d.textlength(text, font=font)
    x = (S - w) / 2
    thick = max(4, size // 14)
    d.text((x, y + size * 0.09), text, font=font, fill=outline, stroke_width=thick + size // 9, stroke_fill=outline)
    d.text((x, y), text, font=font, fill=outline, stroke_width=thick + size // 9, stroke_fill=outline)
    d.text((x, y), text, font=font, fill=ink, stroke_width=thick, stroke_fill=ink)
    return Image.alpha_composite(base, layer)


# ----------------------------------------------------------------------------------------------------- the pictures

GOLD = (rgb("ffd45a"), rgb("f2a922"), rgb("a8620c"), rgb("fff1b0"))


def coin(d, cx, cy, r, tilt=0.42, colours=GOLD):
    """A gold coin seen a little from above: its rim's thickness, its face, a ring on the face, a star and a glint."""
    light, mid, dark, shine = colours
    ry = r * tilt
    thick = r * 0.22
    d.ellipse((cx - r, cy - ry + thick, cx + r, cy + ry + thick), fill=dark, outline=rgb("5a3204"), width=max(3, int(r * 0.06)))
    d.rectangle((cx - r, cy, cx + r, cy + thick), fill=dark)
    d.ellipse((cx - r, cy - ry, cx + r, cy + ry), fill=mid, outline=rgb("5a3204"), width=max(3, int(r * 0.06)))
    d.ellipse((cx - r * 0.74, cy - ry * 0.74, cx + r * 0.74, cy + ry * 0.74), outline=light, width=max(3, int(r * 0.07)))
    # The star on its face, squashed with it.
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = r * (0.42 if k % 2 == 0 else 0.18)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * tilt))
    d.polygon(pts, fill=light)
    d.ellipse((cx - r * 0.55, cy - ry * 0.7, cx - r * 0.2, cy - ry * 0.35), fill=shine)


def coin_pile(base, cx, cy, count, r):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    # Laid from the back of the pile to its front, so the front ones cover the back.
    spots = []
    rows = max(1, int(math.sqrt(count)))
    k = 0
    for row in range(rows + 2):
        per = row + 1
        for i in range(per):
            if k >= count:
                break
            x = cx + (i - (per - 1) / 2) * r * 1.25
            y = cy - (rows + 1 - row) * r * 0.42
            spots.append((x, y))
            k += 1
    for x, y in sorted(spots, key=lambda s: s[1]):
        coin(d, x, y, r)
    return with_shadow(base, layer)


def stack(d, cx, cy, n, r):
    for k in range(n):
        coin(d, cx + math.sin(k * 1.7) * r * 0.06, cy - k * r * 0.24, r)


def crown(base, cx, cy, w):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    h = w * 0.62
    ink = rgb("5a3204")
    pts = [(cx - w / 2, cy + h / 2), (cx - w / 2, cy - h * 0.15), (cx - w * 0.27, cy + h * 0.12), (cx, cy - h / 2),
           (cx + w * 0.27, cy + h * 0.12), (cx + w / 2, cy - h * 0.15), (cx + w / 2, cy + h / 2)]
    d.polygon(pts, fill=GOLD[1], outline=ink)
    d.line(pts + [pts[0]], fill=ink, width=int(w * 0.045), joint="curve")
    # Its band, with three jewels.
    d.rounded_rectangle((cx - w / 2, cy + h * 0.24, cx + w / 2, cy + h / 2 + w * 0.04), radius=int(w * 0.04), fill=GOLD[2],
                        outline=ink, width=int(w * 0.04))
    for k, colour in ((-1, rgb("e8506a")), (0, rgb("5aa8f0")), (1, rgb("e8506a"))):
        jx = cx + k * w * 0.3
        d.ellipse((jx - w * 0.07, cy + h * 0.3, jx + w * 0.07, cy + h * 0.44 + w * 0.03), fill=colour, outline=ink, width=int(w * 0.025))
    # Balls on its three points, and the gloss down its left.
    for px, py in ((cx - w / 2, cy - h * 0.15), (cx, cy - h / 2), (cx + w / 2, cy - h * 0.15)):
        d.ellipse((px - w * 0.075, py - w * 0.075, px + w * 0.075, py + w * 0.075), fill=GOLD[0], outline=ink, width=int(w * 0.03))
    d.polygon([(cx - w * 0.42, cy + h * 0.18), (cx - w * 0.42, cy - h * 0.02), (cx - w * 0.3, cy + h * 0.14)], fill=GOLD[3])
    return with_shadow(base, layer)


def gift(base, cx, cy, w, box, ribbon):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ink = (30, 40, 50)
    h = w * 0.72
    d.rounded_rectangle((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), radius=int(w * 0.06), fill=box, outline=ink, width=int(w * 0.04))
    d.rounded_rectangle((cx - w * 0.56, cy - h / 2 - w * 0.2, cx + w * 0.56, cy - h / 2 + w * 0.02), radius=int(w * 0.05),
                        fill=mix(box, (255, 255, 255), 0.2), outline=ink, width=int(w * 0.04))
    d.rectangle((cx - w * 0.09, cy - h / 2 - w * 0.2, cx + w * 0.09, cy + h / 2), fill=ribbon, outline=ink, width=int(w * 0.03))
    for side in (-1, 1):
        d.ellipse((cx + side * w * 0.05 - w * 0.2 + (side > 0) * w * 0.15, cy - h / 2 - w * 0.42,
                   cx + side * w * 0.05 + w * 0.05 + (side > 0) * w * 0.15, cy - h / 2 - w * 0.18),
                  fill=ribbon, outline=ink, width=int(w * 0.03))
    d.ellipse((cx - w * 0.08, cy - h / 2 - w * 0.28, cx + w * 0.08, cy - h / 2 - w * 0.14), fill=mix(ribbon, (0, 0, 0), 0.15),
              outline=ink, width=int(w * 0.03))
    return with_shadow(base, layer)


def gem(d, cx, cy, r, colour):
    ink = (20, 50, 46)
    pts = [(cx, cy - r), (cx + r * 0.8, cy - r * 0.2), (cx + r * 0.5, cy + r), (cx - r * 0.5, cy + r), (cx - r * 0.8, cy - r * 0.2)]
    d.polygon(pts, fill=colour, outline=ink)
    d.line(pts + [pts[0]], fill=ink, width=max(3, int(r * 0.12)), joint="curve")
    d.polygon([(cx, cy - r * 0.8), (cx + r * 0.35, cy - r * 0.2), (cx - r * 0.35, cy - r * 0.2)], fill=mix(colour, (255, 255, 255), 0.5))


def porthole(base, cx, cy, r):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ink = (10, 20, 24)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=rgb("b88a3a"), outline=ink, width=int(r * 0.06))
    for k in range(8):
        a = k * math.pi / 4
        bx, by = cx + math.cos(a) * r * 0.86, cy + math.sin(a) * r * 0.86
        d.ellipse((bx - r * 0.06, by - r * 0.06, bx + r * 0.06, by + r * 0.06), fill=rgb("f0cf80"), outline=ink, width=4)
    inner = r * 0.72
    water = radial(64, rgb("2a8a8a"), rgb("061a20")).resize((int(inner * 2), int(inner * 2)))
    m = Image.new("L", water.size, 0)
    ImageDraw.Draw(m).ellipse((0, 0, water.size[0] - 1, water.size[1] - 1), fill=255)
    layer.paste(water, (int(cx - inner), int(cy - inner)), m)
    d = ImageDraw.Draw(layer)
    for bx, by, br in ((-0.25, 0.2, 0.09), (-0.05, -0.05, 0.06), (0.18, -0.3, 0.11), (0.3, 0.25, 0.05)):
        x, y, rr = cx + bx * inner * 1.6, cy + by * inner * 1.6, br * inner * 1.6
        d.ellipse((x - rr, y - rr, x + rr, y + rr), outline=(220, 250, 250), width=6)
    d.arc((cx - inner, cy - inner, cx + inner, cy + inner), 200, 250, fill=(255, 255, 255), width=14)
    d.ellipse((cx - inner, cy - inner, cx + inner, cy + inner), outline=ink, width=int(r * 0.05))
    return with_shadow(base, layer)


def flag_and_arrow(base, cx, cy, w):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ink = (60, 14, 20)
    # The checkpoint's flag on its pole.
    d.rounded_rectangle((cx - w * 0.04, cy - w * 0.5, cx + w * 0.04, cy + w * 0.42), radius=8, fill=rgb("f4f0ea"), outline=ink, width=10)
    d.polygon([(cx + w * 0.04, cy - w * 0.48), (cx + w * 0.46, cy - w * 0.34), (cx + w * 0.04, cy - w * 0.18)], fill=rgb("ff5a6e"),
              outline=ink)
    d.line([(cx + w * 0.04, cy - w * 0.48), (cx + w * 0.46, cy - w * 0.34), (cx + w * 0.04, cy - w * 0.18)], fill=ink, width=12, joint="curve")
    d.ellipse((cx - w * 0.3, cy + w * 0.36, cx + w * 0.3, cy + w * 0.5), fill=rgb("9a2a3a"), outline=ink, width=10)
    # The arrow coming round back to it.
    box = (cx - w * 0.62, cy - w * 0.62, cx + w * 0.38, cy + w * 0.38)
    d.arc(box, 120, 330, fill=ink, width=int(w * 0.13))
    d.arc(box, 120, 330, fill=rgb("ffffff"), width=int(w * 0.08))
    a = math.radians(330)
    tx, ty = (box[0] + box[2]) / 2 + math.cos(a) * w * 0.5, (box[1] + box[3]) / 2 + math.sin(a) * w * 0.5
    d.polygon([(tx - w * 0.1, ty - w * 0.14), (tx + w * 0.16, ty + w * 0.02), (tx - w * 0.06, ty + w * 0.16)], fill=rgb("ffffff"), outline=ink)
    return with_shadow(base, layer)


def jar(base, cx, cy, w, fill_coins):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ink = (40, 30, 60)
    h = w * 1.05
    # Coins inside first, then the jar's pale body over them (a film, not glass: it reads as a jar of coins).
    for k in range(fill_coins):
        coin(d, cx + ((k * 37) % 5 - 2) * w * 0.1, cy + h * 0.36 - (k // 3) * w * 0.13, w * 0.17)
    d.rounded_rectangle((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), radius=int(w * 0.18), outline=ink, width=int(w * 0.04))
    d.rounded_rectangle((cx - w * 0.38, cy - h / 2 - w * 0.12, cx + w * 0.38, cy - h / 2 + w * 0.04), radius=int(w * 0.04),
                        fill=rgb("e8506a"), outline=ink, width=int(w * 0.035))
    d.line([(cx - w * 0.36, cy - h * 0.3), (cx - w * 0.36, cy + h * 0.1)], fill=(255, 255, 255), width=int(w * 0.05))
    return with_shadow(base, layer)


def chest(base, cx, cy, w):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ink = (40, 20, 6)
    h = w * 0.55
    wood, band = rgb("9a5a28"), GOLD[1]
    # Coins heaped out of it.
    for k in range(14):
        coin(d, cx + ((k * 53) % 9 - 4) * w * 0.09, cy - h * 0.5 - (k % 3) * w * 0.05 - (k // 7) * w * 0.06, w * 0.14)
    d.rounded_rectangle((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), radius=int(w * 0.05), fill=wood, outline=ink, width=int(w * 0.035))
    for x in (-0.36, 0.36):
        d.rectangle((cx + x * w - w * 0.05, cy - h / 2, cx + x * w + w * 0.05, cy + h / 2), fill=band, outline=ink, width=8)
    d.rounded_rectangle((cx - w * 0.08, cy - h * 0.18, cx + w * 0.08, cy + h * 0.16), radius=10, fill=GOLD[0], outline=ink, width=8)
    for k in range(3):
        coin(d, cx + (k - 1) * w * 0.34, cy + h / 2 + w * 0.02, w * 0.12)
    return with_shadow(base, layer)


# ----------------------------------------------------------------------------------------------------- each icon

def icon_vip():
    img = badge((rgb("cfc8ff"), rgb("8b7fe0"), rgb("3a2f8a"), rgb("231c5c")))
    img = crown(img, S / 2, S * 0.4, S * 0.5)
    return words(img, "VIP", S * 0.6, 230, outline=rgb("231c5c"))


def icon_double():
    img = badge((rgb("ffe7a8"), rgb("f2a922"), rgb("8a4a06"), rgb("5a3204")))
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    stack(d, S * 0.36, S * 0.5, 4, S * 0.15)
    stack(d, S * 0.62, S * 0.54, 6, S * 0.15)
    img = with_shadow(img, layer)
    return words(img, "2x", S * 0.52, 300, outline=rgb("5a3204"))


def icon_starter():
    img = badge((rgb("c8f4e6"), rgb("50c0a0"), rgb("0e6a56"), rgb("08443a")))
    img = gift(img, S * 0.5, S * 0.42, S * 0.42, rgb("ff6f8e"), rgb("ffd45a"))
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    gem(d, S * 0.24, S * 0.52, S * 0.07, rgb("8ee6cc"))
    gem(d, S * 0.78, S * 0.5, S * 0.06, rgb("a6ecd8"))
    coin(d, S * 0.76, S * 0.62, S * 0.07)
    coin(d, S * 0.25, S * 0.64, S * 0.06)
    img = with_shadow(img, layer)
    return words(img, "STARTER", S * 0.66, 170, outline=rgb("08443a"))


def icon_hold():
    img = badge((rgb("4ab0b0"), rgb("146a6e"), rgb("04262a"), rgb("02161a")))
    img = porthole(img, S / 2, S * 0.43, S * 0.27)
    return words(img, "THE HOLD", S * 0.7, 150, outline=rgb("02161a"))


def icon_chance():
    img = badge((rgb("ffd0d6"), rgb("f0708a"), rgb("8a1e34"), rgb("5a0e1e")))
    img = flag_and_arrow(img, S * 0.53, S * 0.47, S * 0.42)
    return words(img, "2ND CHANCE", S * 0.7, 140, outline=rgb("5a0e1e"))


def icon_pack(amount, picture):
    img = badge((rgb("fff0bf"), rgb("f2b23a"), rgb("8a4a06"), rgb("5a3204")))
    img = picture(img)
    return words(img, str(amount), S * 0.68, 190, outline=rgb("5a3204"))


def up_arrow(base, cx, cy, w):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ink = (10, 50, 30)
    pts = [(cx, cy - w * 0.62), (cx + w * 0.42, cy - w * 0.12), (cx + w * 0.16, cy - w * 0.12), (cx + w * 0.16, cy + w * 0.5),
           (cx - w * 0.16, cy + w * 0.5), (cx - w * 0.16, cy - w * 0.12), (cx - w * 0.42, cy - w * 0.12)]
    d.polygon(pts, fill=rgb("7cf0a0"))
    d.line(pts + [pts[0]], fill=ink, width=int(w * 0.07), joint="curve")
    d.polygon([(cx - w * 0.05, cy - w * 0.45), (cx - w * 0.28, cy - w * 0.17), (cx - w * 0.1, cy - w * 0.17)], fill=(220, 255, 230))
    return with_shadow(base, layer)


def icon_boost():
    img = badge((rgb("d4f7c8"), rgb("4cc46a"), rgb("12602a"), rgb("0a3a18")))
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    stack(d, S * 0.36, S * 0.56, 3, S * 0.15)
    img = with_shadow(img, layer)
    img = up_arrow(img, S * 0.64, S * 0.42, S * 0.36)
    return words(img, "2x RUN", S * 0.66, 190, outline=rgb("0a3a18"))


ICONS = {
    "VIP": icon_vip,
    "DoubleTokens": icon_double,
    "StarterPack": icon_starter,
    "BgHold": icon_hold,
    "SecondChance": icon_chance,
    "RunBoost": icon_boost,
    "Pack100": lambda: icon_pack(100, lambda img: coin_pile(img, S / 2, S * 0.6, 3, S * 0.17)),
    "Pack300": lambda: icon_pack(300, lambda img: jar(img, S / 2, S * 0.42, S * 0.38, 15)),
    "Pack800": lambda: icon_pack(800, lambda img: coin_pile(img, S / 2, S * 0.63, 10, S * 0.125)),
    "Pack2000": lambda: icon_pack(2000, lambda img: chest(img, S / 2, S * 0.5, S * 0.5)),
}

if __name__ == "__main__":
    only = set(sys.argv[1:])
    OUT.mkdir(exist_ok=True)
    for name, make in ICONS.items():
        if only and name not in only:
            continue
        img = make().resize((512, 512), Image.LANCZOS)
        img.save(OUT / (name + ".png"))
        print("wrote", OUT / (name + ".png"))
