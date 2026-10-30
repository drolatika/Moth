"""Builds the Divine Comedy theme backdrop from a public-domain woodcut of the
Paradiso (Design/Art/paradiso-woodcut.png): a field of eight-pointed stars, the
angels faded in behind the header, and Dante and Beatrice stencilled faintly low
on the page. All drawn as pale gold lines on transparency; the theme supplies the
night-indigo colour underneath.

Usage: python3 scripts/make_divine_comedy.py   (needs Pillow and numpy)
Writes Moth/Assets.xcassets/DivineComedyBackdrop.imageset/
"""
import json
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Design/Art/paradiso-woodcut.png"
OUT = ROOT / "Moth/Assets.xcassets/DivineComedyBackdrop.imageset"
W, H = 1290, 2796           # iPhone Pro Max at 3x
GOLD = (222, 204, 162)


def ink(img):
    """Woodcut ink as alpha (0..1); drops the faint text showing through the page."""
    gray = np.asarray(img.convert("L")).astype(np.float32)
    return np.clip((175 - gray) / 100, 0, 1)


def to_layer(alpha):
    a = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
    rgb = np.empty(a.shape + (3,), np.uint8)
    rgb[...] = GOLD
    return Image.fromarray(np.dstack([rgb, a]), "RGBA")


def resize_alpha(alpha, size):
    im = Image.fromarray((alpha * 255).astype(np.uint8), "L").resize(size, Image.LANCZOS)
    return np.asarray(im).astype(np.float32) / 255


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def angels(src):
    box = (16, 16, src.width - 16, 540)          # inside the printed border
    crop = ink(src.crop(box))
    h = round((box[3] - box[1]) * W / (box[2] - box[0]))
    a = resize_alpha(crop, (W, h))
    fade = 1 - smoothstep(0.45, 1.0, np.linspace(0, 1, h))[:, None]
    return to_layer(a * fade * 0.17), (0, 0)


def dante_and_beatrice(src):
    box = (470, 680, 800, 975)
    a = ink(src.crop(box))
    # erase the printed "D" and "B" labels
    for (x0, y0, x1, y1) in ((573, 700, 600, 726), (680, 664, 706, 692)):
        a[max(0, y0 - box[1]):y1 - box[1], max(0, x0 - box[0]):x1 - box[0]] = 0
    hgt, wid = a.shape
    yy, xx = np.mgrid[0:hgt, 0:wid]
    cx, cy = 160, 150
    r = np.sqrt(((xx - cx) / 165) ** 2 + ((yy - cy) / 150) ** 2)
    a = a * (1 - smoothstep(0.7, 1.05, r))
    scale = 2.4
    size = (round(wid * scale), round(hgt * scale))
    a = resize_alpha(a, size)
    return to_layer(a * 0.16), ((W - size[0]) // 2, H - 280 - size[1])


def star_points(cx, cy, r, inner, rot):
    pts = []
    for i in range(16):
        ang = math.radians(rot + i * 22.5 - 90)
        rr = r if i % 2 == 0 else r * inner
        pts.append((cx + rr * math.cos(ang), cy + rr * math.sin(ang)))
    return pts


def stars(seed=11):
    s = 2
    layer = Image.new("RGBA", (W * s, H * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rnd = random.Random(seed)
    placed = []
    attempts = 0
    while len(placed) < 260 and attempts < 20000:
        attempts += 1
        x, y = rnd.uniform(20, W - 20), rnd.uniform(20, H - 20)
        r = rnd.choice([8, 10, 12, 14, 17, 22])
        if any((x - px) ** 2 + (y - py) ** 2 < (r + pr + 34) ** 2 for px, py, pr in placed):
            continue
        placed.append((x, y, r))
        alpha = int(255 * rnd.uniform(0.14, 0.32))
        rot = rnd.uniform(0, 45)
        outline = star_points(x * s, y * s, r * s, 0.42, rot)
        if r >= 13 and rnd.random() < 0.6:
            # engraved star: outlined, with a smaller solid star inside
            d.polygon(outline, outline=GOLD + (alpha,), width=max(1, s))
            d.polygon(star_points(x * s, y * s, r * s * 0.45, 0.4, rot), fill=GOLD + (alpha,))
        else:
            d.polygon(outline, fill=GOLD + (alpha,))
    return layer.resize((W, H), Image.LANCZOS)


def main():
    src = Image.open(SOURCE).convert("RGB")
    canvas = stars()
    for layer, pos in (angels(src), dante_and_beatrice(src)):
        canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(0.6)), pos)
    OUT.mkdir(parents=True, exist_ok=True)
    canvas.save(OUT / "backdrop.png", optimize=True)
    (OUT / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "backdrop.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    print(f"wrote {(OUT / 'backdrop.png').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
