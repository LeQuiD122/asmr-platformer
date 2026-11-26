"""Store thumbnails, third round (2026-11-25, "improve the thumbnails").

    python release/thumbs_v3.py

What the second round got wrong: the player was small in every picture, none of them showed a material doing anything
(the game's whole point), the serpent's was most of a frame of dark water, and the best moment in the game, the Maw
opening under you, was not there. So:

    1. SQUISH EVERYTHING!  you, close, jumping over City Shore's arcade buttons with your prints pressed into them
    2. DON'T FALL IN!       the Maw open under you in the dark of the shaft (staged in Studio, the scene's own light)
    3. 5 WORLDS TO SQUISH   all five levels as cards
    4. 28 MATERIALS!        six materials doing what they do, as cards

All real captures from Studio (2026-11-24/25), nothing painted. Writes release/store_drafts/thumb_v3_*.png and a
contact sheet; the repo's copies go to media/thumbnails/.
"""
import pathlib

from PIL import Image, ImageDraw, ImageFilter

import compose
from thumbs_v2 import W, H, band, frame, vignette

HERE = pathlib.Path(__file__).resolve().parent
DRAFTS = HERE / "store_drafts"
SHOTS = HERE.parent / "screenshots"
MEDIA = HERE.parent / "media" / "thumbnails"


def backdrop(path, darken=0.35, blur=14):
    """A level, blurred and darkened, behind the cards."""
    img = frame(path, 0.5, 0.5).convert("RGB").filter(ImageFilter.GaussianBlur(blur))
    shade = Image.new("RGB", img.size, (24, 8, 40))
    return Image.blend(img, shade, darken).convert("RGBA")


def place_card(img, path, centre, size, tilt, label):
    c = compose.card(path, size, tilt, label=label)
    sh = Image.new("RGBA", c.size, (20, 0, 40, 0))
    sh.putalpha(c.getchannel("A").filter(ImageFilter.GaussianBlur(14)).point(lambda v: v * 150 // 255))
    x, y = int(centre[0] - c.width / 2), int(centre[1] - c.height / 2)
    img.alpha_composite(sh, (x + 10, y + 18))
    img.alpha_composite(c, (x, y))


def number(img, n, centre, r=46):
    """A level's number, in a gold disc pinned to its card's corner."""
    layer = Image.new("RGBA", (r * 2 + 16, r * 2 + 16), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([8, 10, r * 2 + 8, r * 2 + 10], fill=(60, 20, 80, 160))
    d.ellipse([4, 4, r * 2 + 4, r * 2 + 4], fill=(120, 50, 20, 255))
    d.ellipse([9, 9, r * 2 - 1, r * 2 - 1], fill=(255, 206, 70, 255))
    f = compose.font(int(r * 1.15))
    text = str(n)
    tw = d.textlength(text, font=f)
    d.text((r + 4 - tw / 2, r - r * 0.62), text, font=f, fill=(255, 255, 255), stroke_width=5, stroke_fill=(110, 40, 20))
    img.alpha_composite(layer, (int(centre[0] - r), int(centre[1] - r)))


def save(img, name):
    out = DRAFTS / name
    img.convert("RGB").save(out, optimize=True)
    return out


def build():
    made = []

    # 1. You, jumping over the arcade buttons.
    img = compose.pop(frame(DRAFTS / "raw_v3_buttons_close.jpg", 0.5, 0.5), saturation=1.12, contrast=1.05)
    compose.speed_lines(img, 960, 640, 330, 1150, count=30, alpha=55, seed=5)
    vignette(img, 80)
    compose.sparkles(img, 16, 11, box=(560, 820, 1360, 1060), sizes=(14, 38))
    band(img, 0, 260)
    compose.title3d(img, "SQUISH EVERYTHING!", (W // 2, 118), 138)
    compose.burst(img, "", (1620, 820), 165, lines=["SO", "SQUISHY!"], size=64, tilt=10)
    made.append(save(img, "thumb_v3_1_squish.png"))

    # 2. The Maw, open under you.
    img = compose.pop(frame(DRAFTS / "raw_v3_maw_dive.jpg", 0.5, 0.45), saturation=1.1, contrast=1.1, brightness=1.08)
    vignette(img, 120)
    band(img, H - 300, 300, colour=(30, 0, 6), strength=190)
    compose.title3d(img, "DON'T FALL IN!", (W // 2, H - 150), 170, fill_top=(255, 236, 226),
                    fill_bottom=(255, 70, 54), outline=(60, 0, 12), tilt=2)
    made.append(save(img, "thumb_v3_2_maw.png"))

    # 3. Five worlds.
    img = backdrop(SHOTS / "city-shore.jpg")
    band(img, 0, 290)
    cards = [
        ("city-shore.jpg", "CITY SHORE", (350, 465), -4),
        ("sky-pools.jpg", "SKY POOLS", (960, 450), 3),
        ("sunken-city.jpg", "SUNKEN CITY", (1570, 465), -3),
        ("flooded-halls.jpg", "FLOODED HALLS", (650, 855), 3),
        ("hill-house.jpg", "HILL HOUSE", (1270, 855), -3),
    ]
    for k, (name, label, at, tilt) in enumerate(cards):
        place_card(img, SHOTS / name, at, (500, 280), tilt, label)
        number(img, k + 1, (at[0] - 245, at[1] - 150))
    compose.title3d(img, "5 WORLDS TO SQUISH", (W // 2, 140), 150)
    made.append(save(img, "thumb_v3_3_worlds.png"))

    # 4. The materials, doing what they do.
    img = backdrop(SHOTS / "squish-room.jpg", darken=0.45)
    band(img, 0, 290)
    cards = [
        (DRAFTS / "raw_v3_bubblewrap.jpg", "BUBBLE WRAP", (350, 465), -4),
        (SHOTS / "lava-keys.jpg", "KEYS OVER LAVA", (960, 450), 3),
        (SHOTS / "butter-sticks.jpg", "BUTTER", (1570, 465), -3),
        (SHOTS / "snow.jpg", "SNOW", (350, 855), 3),
        (SHOTS / "creamy-keyboard.jpg", "KEYBOARD", (960, 870), -2),
        (DRAFTS / "raw_v3_lego.jpg", "TOY BRICKS", (1570, 855), 3),
    ]
    # Tight on the material: the squish room's marble floor round each pad says nothing.
    for path, _, _, _ in cards:
        compose.CROPS[path.name] = {"card": (400, 40, 1510, 660)}
    for path, label, at, tilt in cards:
        place_card(img, path, at, (500, 280), tilt, label)
    compose.title3d(img, "28 MATERIALS!", (W // 2, 140), 160)
    compose.burst(img, "", (1700, 150), 120, lines=["SO", "SATISFYING!"], size=40, tilt=12)
    made.append(save(img, "thumb_v3_4_materials.png"))

    sheet = Image.new("RGB", (W, H))
    for i, path in enumerate(made):
        sheet.paste(Image.open(path).resize((W // 2, H // 2)), ((i % 2) * W // 2, (i // 2) * H // 2))
    sheet.save(DRAFTS / "thumb_v3_sheet.jpg", quality=88)
    MEDIA.mkdir(parents=True, exist_ok=True)
    for path in made:
        print(path.name)


if __name__ == "__main__":
    build()
