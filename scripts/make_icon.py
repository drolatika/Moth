"""Renders Noll's app icon: a record with a bookmark ribbon tucked into it.

Usage: python3 scripts/make_icon.py
Writes Noll/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024x1024).
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
S = 4  # supersampling factor
W = SIZE * S

INK_TOP = (30, 28, 38)
INK_BOTTOM = (12, 11, 16)
DISC = (8, 8, 10)
GROOVE = (24, 23, 29)
ACCENT = (255, 90, 54)
RIM = (46, 44, 56)
CREAM = (244, 239, 230)


def vertical_gradient(top, bottom):
    img = Image.new("RGB", (1, W))
    for y in range(W):
        t = y / (W - 1)
        img.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img.resize((W, W))


def circle(draw, cx, cy, r, **kwargs):
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), **kwargs)


def main():
    icon = vertical_gradient(INK_TOP, INK_BOTTOM).convert("RGBA")
    cx, cy = W * 0.5, W * 0.54
    disc_r = W * 0.355

    # Soft drop shadow under the record.
    shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    circle(ImageDraw.Draw(shadow), cx, cy + W * 0.02, disc_r, fill=(0, 0, 0, 150))
    icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(W * 0.03)))

    d = ImageDraw.Draw(icon)
    circle(d, cx, cy, disc_r, fill=DISC, outline=RIM, width=int(W * 0.006))
    for frac in (0.92, 0.82, 0.72, 0.62):
        circle(d, cx, cy, disc_r * frac, outline=GROOVE, width=int(W * 0.004))

    # Centre label and spindle hole: the "0" in Noll.
    circle(d, cx, cy, disc_r * 0.40, fill=ACCENT)
    circle(d, cx, cy, disc_r * 0.075, fill=INK_BOTTOM)

    # Bookmark ribbon hanging from the top edge, notched at the bottom.
    rw = W * 0.14
    rx = W * 0.6
    ry_bottom = W * 0.40
    notch = W * 0.06
    ribbon = [
        (rx, -10),
        (rx + rw, -10),
        (rx + rw, ry_bottom),
        (rx + rw / 2, ry_bottom - notch),
        (rx, ry_bottom),
    ]
    ribbon_shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(ribbon_shadow).polygon([(x + W * 0.012, y + W * 0.012) for x, y in ribbon], fill=(0, 0, 0, 140))
    icon.alpha_composite(ribbon_shadow.filter(ImageFilter.GaussianBlur(W * 0.012)))
    ImageDraw.Draw(icon).polygon(ribbon, fill=CREAM)

    out = Path(__file__).resolve().parent.parent / "Noll/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
    icon.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS).save(out, optimize=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
