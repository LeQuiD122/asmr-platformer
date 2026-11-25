"""The lobby's billboards' own posters (the two-hundred-and-fourteenth pass): what the immersive ad boards show anyone
Roblox serves no ad to (their AdGui's FallbackImage), instead of Roblox's logo. The bay advertising itself.

    python blender/gen_ad_posters.py        writes shop_icons/AdPoster_SquishRoom.png and AdPoster_Boutique.png (1600x900)

Old seaside posters in the shop's chunky style: a warm ground with rays, a big picture, the words in Nunito.
"""
import math
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen_shop_icons as icons  # noqa: E402  (its Nunito, its coins, crown and words)

OUT = pathlib.Path(__file__).resolve().parent.parent / "shop_icons"
W, H = 3200, 1800  # drawn at twice 1600x900


def ground(top, bottom, rays=(255, 255, 255, 30)):
    img = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        d.line([(0, y), (W, y)], fill=icons.mix(top, bottom, y / H))
    ray = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rd = ImageDraw.Draw(ray)
    c = (W * 0.27, H * 0.5)
    for k in range(20):
        a0 = k * math.pi * 2 / 20
        rd.polygon([c, (c[0] + math.cos(a0) * W * 2, c[1] + math.sin(a0) * W * 2),
                    (c[0] + math.cos(a0 + math.pi / 20) * W * 2, c[1] + math.sin(a0 + math.pi / 20) * W * 2)], fill=rays)
    img = Image.alpha_composite(img, ray)
    edge = ImageDraw.Draw(img)
    edge.rectangle((0, 0, W - 1, H - 1), outline=(255, 255, 255, 200), width=40)
    return img


def text(img, words, x, y, size, ink, outline):
    from PIL import ImageFont
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    font = ImageFont.truetype(icons.FONT, size)
    thick = max(4, size // 14)
    d.text((x, y + size * 0.08), words, font=font, fill=outline, stroke_width=thick + size // 10, stroke_fill=outline)
    d.text((x, y), words, font=font, fill=outline, stroke_width=thick + size // 10, stroke_fill=outline)
    d.text((x, y), words, font=font, fill=ink, stroke_width=thick, stroke_fill=ink)
    return Image.alpha_composite(img, layer)


def chunk(d, x, y, w, h, top, side, ink):
    """A soft chunk seen a little from above: its top, its front, rounded."""
    d.rounded_rectangle((x, y + h * 0.3, x + w, y + h), radius=int(h * 0.2), fill=side, outline=ink, width=12)
    d.rounded_rectangle((x, y, x + w, y + h * 0.55), radius=int(h * 0.25), fill=top, outline=ink, width=12)


def squish_room():
    img = ground(icons.rgb("f8d6e6"), icons.rgb("c9b8ef"))
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ink = icons.rgb("3a2350")
    # A little pile of the bay's chunks: slime, honey, soap, chocolate, bubble wrap.
    chunk(d, 260, 980, 560, 420, icons.rgb("a8ec7a"), icons.rgb("5fb83c"), ink)
    chunk(d, 760, 1060, 520, 380, icons.rgb("ffd27a"), icons.rgb("e89a28"), ink)
    chunk(d, 520, 640, 520, 400, icons.rgb("f4f6ff"), icons.rgb("bcd2f2"), ink)
    chunk(d, 1020, 700, 420, 360, icons.rgb("8a5636"), icons.rgb("5e3620"), ink)
    for k in range(5):
        bx, by = 560 + k * 90, 700
        d.ellipse((bx, by, bx + 70, by + 40), fill=(255, 255, 255), outline=ink, width=6)
    img = icons.with_shadow(img, layer) if False else Image.alpha_composite(img, layer)
    img = text(img, "THE SQUISH", 1560, 380, 230, (255, 255, 255), ink)
    img = text(img, "ROOM", 1560, 660, 230, (255, 255, 255), ink)
    img = text(img, "Every material, all at once.", 1600, 1110, 120, ink, (255, 255, 255))
    img = text(img, "Take the lift in the garden.", 1600, 1290, 120, ink, (255, 255, 255))
    return img


def boutique():
    img = ground(icons.rgb("fbe3c7"), icons.rgb("f0b98f"))
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    ink = icons.rgb("4a2410")
    # A sailor hat and a yellow raincoat on a rail.
    d.rounded_rectangle((180, 360, 1380, 400), radius=20, fill=icons.rgb("8a5a30"), outline=ink, width=10)
    # The raincoat.
    coat = [(520, 470), (760, 470), (900, 1400), (380, 1400)]
    d.polygon(coat, fill=icons.rgb("ffd23f"))
    d.line(coat + [coat[0]], fill=ink, width=14, joint="curve")
    d.line([(640, 470), (640, 1400)], fill=ink, width=10)
    for y in (700, 900, 1100):
        d.ellipse((660, y, 700, y + 40), fill=icons.rgb("f0f0f0"), outline=ink, width=6)
    d.line([(640, 400), (640, 470)], fill=ink, width=12)
    # Its sleeves, and its hood up over the hanger.
    for side in (-1, 1):
        sleeve = [(640 + side * 110, 480), (640 + side * 230, 520), (640 + side * 330, 1050), (640 + side * 230, 1080),
                  (640 + side * 160, 640)]
        d.polygon(sleeve, fill=icons.rgb("ffc82a"))
        d.line(sleeve + [sleeve[0]], fill=ink, width=12, joint="curve")
    d.ellipse((540, 380, 740, 560), fill=icons.rgb("ffd23f"), outline=ink, width=12)
    d.ellipse((585, 430, 695, 540), fill=icons.rgb("e0a820"), outline=ink, width=8)
    # The hat.
    d.ellipse((960, 980, 1360, 1120), fill=(250, 250, 250), outline=ink, width=12)
    d.pieslice((1000, 820, 1320, 1120), 180, 360, fill=(250, 250, 250), outline=ink, width=12)
    d.rectangle((1004, 950, 1316, 990), fill=icons.rgb("2a4fa0"))
    img = Image.alpha_composite(img, layer)
    img = icons.crown(img, 2900, 1430, 360) if False else img
    img = text(img, "THE BOUTIQUE", 1480, 380, 190, (255, 255, 255), ink)
    img = text(img, "Real Roblox outfits", 1540, 700, 130, ink, (255, 255, 255))
    img = text(img, "for the bay. In the shop.", 1540, 880, 130, ink, (255, 255, 255))
    img = text(img, "VIP lounge: the Hall of Fame", 1540, 1250, 110, icons.rgb("3a2f8a"), (255, 255, 255))
    return img


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    for name, make in (("AdPoster_SquishRoom", squish_room), ("AdPoster_Boutique", boutique)):
        make().resize((1600, 900), Image.LANCZOS).convert("RGB").save(OUT / (name + ".png"))
        print("wrote", OUT / (name + ".png"))
