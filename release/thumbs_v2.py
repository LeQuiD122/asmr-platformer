"""Store thumbnails, second round (2026-11-21): the real gameplay shots, with a few big words on each.

    python release/thumbs_v2.py

The plain gameplay thumbnails on the store page said nothing; the top games' thumbnails each carry two or three chunky
words. Each shot is cropped to 16:9, scaled to 1920 by 1080 (Lanczos, then a light unsharp mask, since the Studio game
view is smaller than that), given a little more colour, and captioned with compose.py's extruded title. A dark band
under the title keeps it readable whatever is behind. Writes release/store_drafts/thumb_v2_*.png and a contact sheet.
"""
import pathlib

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

import compose

HERE = pathlib.Path(__file__).resolve().parent
DRAFTS = HERE / "store_drafts"
W, H = 1920, 1080


def frame(path, centre_x=0.5, centre_y=0.5, zoom=1.0):
    """The shot cropped to 16:9 around a point (fractions of the image), scaled to 1920 by 1080."""
    img = Image.open(path).convert("RGB")
    iw, ih = img.size
    ch = ih / zoom
    cw = ch * 16 / 9
    if cw > iw:
        cw = iw
        ch = cw * 9 / 16
    x0 = min(max(0, iw * centre_x - cw / 2), iw - cw)
    y0 = min(max(0, ih * centre_y - ch / 2), ih - ch)
    img = img.crop((int(x0), int(y0), int(x0 + cw), int(y0 + ch))).resize((W, H), Image.LANCZOS)
    img = img.filter(ImageFilter.UnsharpMask(radius=2.2, percent=70, threshold=2))
    img = ImageEnhance.Color(img).enhance(1.18)
    img = ImageEnhance.Contrast(img).enhance(1.06)
    return img.convert("RGBA")


def band(img, top, height, colour=(30, 10, 40), strength=150):
    """A soft dark band behind a title, fading out above and below."""
    layer = Image.new("RGBA", img.size, colour + (0,))
    mask = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(mask)
    for y in range(height):
        t = y / max(1, height - 1)
        a = int(strength * (1 - abs(t - 0.5) * 2) ** 0.6)
        d.line([(0, top + y), (img.width, top + y)], fill=a)
    layer.putalpha(mask)
    img.alpha_composite(layer)


def vignette(img, strength=90):
    w, h = img.size
    mask = Image.new("L", (w // 8, h // 8), 0)
    d = ImageDraw.Draw(mask)
    for k in range(40):
        t = k / 40
        d.rectangle([int(t * w / 40), int(t * h / 40), w // 8 - int(t * w / 40), h // 8 - int(t * h / 40)],
                    outline=int(strength * (1 - t)))
    mask = mask.resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(40))
    dark = Image.new("RGBA", (w, h), (10, 0, 20, 0))
    dark.putalpha(mask)
    img.alpha_composite(dark)


def save(img, name):
    out = DRAFTS / name
    img.convert("RGB").save(out, optimize=True)
    return out


def build():
    made = []

    # 1. The arcade buttons in City Shore.
    img = frame(DRAFTS / "raw_city_shore_buttons.jpg", 0.5, 0.5)
    vignette(img)
    band(img, 0, 300)
    compose.title3d(img, "SQUISH EVERYTHING!", (W // 2, 150), 150)
    compose.burst(img, "", (1580, 760), 150, lines=["SO", "SQUISHY!"], size=58, tilt=10)
    made.append(save(img, "thumb_v2_1_squish.png"))

    # 2. The high dive (retaken 2026-11-21: the bay's props are the modelled ones now, and the view is sharper).
    img = frame(DRAFTS / "raw_v2_dive.jpg", 0.46, 0.5)
    vignette(img)
    band(img, 0, 290)
    compose.title3d(img, "TAKE THE HIGH DIVE!", (W // 2, 140), 140, fill_top=(200, 250, 255),
                    fill_bottom=(60, 170, 255), outline=(20, 40, 90))
    made.append(save(img, "thumb_v2_2_dive.png"))

    # 3. The Sky Pools.
    img = frame(DRAFTS / "raw_sky_pools.jpg", 0.5, 0.5)
    vignette(img)
    band(img, 0, 290)
    compose.title3d(img, "5 WORLDS TO SQUISH", (W // 2, 140), 150)
    compose.burst(img, "", (300, 820), 130, lines=["SKY", "POOLS"], size=56, tilt=-10,
                  fill=(120, 220, 255), edge=(30, 90, 170), ink=(20, 40, 100))
    made.append(save(img, "thumb_v2_3_worlds.png"))

    # 4. The serpent: cold letters on the dark, nothing cheerful.
    img = frame(DRAFTS / "raw_sunken_serpent_dark.jpg", 0.5, 0.5)
    band(img, 0, 290, colour=(0, 6, 14), strength=170)
    compose.title3d(img, "DON'T WAKE THE SERPENT", (W // 2, 140), 128, fill_top=(230, 252, 255),
                    fill_bottom=(110, 200, 220), outline=(6, 22, 36), tilt=0)
    made.append(save(img, "thumb_v2_4_serpent.png"))

    sheet = Image.new("RGB", (W, H))
    for i, path in enumerate(made):
        sheet.paste(Image.open(path).resize((W // 2, H // 2)), ((i % 2) * W // 2, (i // 2) * H // 2))
    sheet.save(DRAFTS / "thumb_v2_sheet.jpg", quality=88)
    for path in made:
        print(path.name)


if __name__ == "__main__":
    build()
