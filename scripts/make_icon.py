"""Renders Moth's app icon and the saved alternates.

The icon is a Fraktur "M" (UnifrakturMaguntia, SIL OFL, in Shared/Fonts)
glowing orange on near-black: a light for the moth.

Usage: python3 scripts/make_icon.py   (needs Pillow and numpy)
Writes:
  Moth/Assets.xcassets/AppIcon.appiconset               the app icon (M1)
  Moth/Assets.xcassets/AppIcon-*.appiconset             alternate icons, chosen in Settings
  Moth/Assets.xcassets/IconPreview-*.imageset           small previews for the Settings picker
  Design/Icons/*.png                                    the icon and alternates at 1024px
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "Shared/Fonts/UnifrakturMaguntia-Book.ttf"

SIZE = 1024
S = 4  # supersampling factor
W = SIZE * S

INK = (10, 10, 12)
GLOW = (255, 120, 74)
CREAM = (244, 239, 230)
PARCHMENT = (236, 225, 200)
SEPIA = (60, 42, 26)
VERMILION = (226, 72, 42)
GOLD = (214, 172, 98)


def C(x):
    return x * W


def canvas(color):
    return Image.new("RGBA", (W, W), color + (255,))


def layer():
    return Image.new("RGBA", (W, W), (0, 0, 0, 0))


def soft_blur(img, radius):
    """Gaussian blur that doesn't darken a layer's edges toward black."""
    arr = np.asarray(img).astype(np.float32)
    alpha = arr[..., 3:4] / 255.0
    pre = Image.fromarray(np.clip(arr[..., :3] * alpha, 0, 255).astype(np.uint8), "RGB")
    pre = np.asarray(pre.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32)
    a = np.asarray(img.split()[3].filter(ImageFilter.GaussianBlur(radius))).astype(np.float32)[..., None] / 255.0
    rgb = np.where(a > 1e-4, pre / np.maximum(a, 1e-4), 0)
    return Image.fromarray(np.concatenate([np.clip(rgb, 0, 255), a * 255], axis=-1).astype(np.uint8), "RGBA")


def glow(img, draw, blur, strength):
    lit = layer()
    draw(ImageDraw.Draw(lit))
    halo = soft_blur(lit, C(blur))
    for _ in range(strength):
        img.alpha_composite(halo)
    img.alpha_composite(lit)


def fitted(text, width=None, height=None):
    probe = ImageFont.truetype(str(FONT), 1000)
    x0, y0, x1, y1 = probe.getbbox(text)
    scale = min(C(width) / (x1 - x0) if width else 1e9, C(height) / (y1 - y0) if height else 1e9)
    return ImageFont.truetype(str(FONT), int(1000 * scale))


def centered_text(draw, text, font, fill, cx=0.5, cy=0.5, **kwargs):
    """Draws text with the centre of its visible ink at (cx, cy); returns the origin used."""
    x0, y0, x1, y1 = draw.textbbox((0, 0), text, font=font, stroke_width=kwargs.get("stroke_width", 0))
    origin = (C(cx) - (x0 + x1) / 2, C(cy) - (y0 + y1) / 2)
    draw.text(origin, text, font=font, fill=fill, **kwargs)
    return origin


def circle(draw, cx, cy, r, **kwargs):
    draw.ellipse((C(cx - r), C(cy - r), C(cx + r), C(cy + r)), **kwargs)


def m1():
    """The app icon: glowing Fraktur M."""
    img = canvas(INK)
    font = fitted("M", width=0.6, height=0.56)
    glow(img, lambda d: centered_text(d, "M", font, GLOW), blur=0.03, strength=2)
    return img


def m7():
    """Alternate: the M as a glowing orange outline."""
    img = canvas(INK)
    font = fitted("M", width=0.6, height=0.56)
    glow(img, lambda d: centered_text(d, "M", font, INK, stroke_width=int(C(0.008)), stroke_fill=GLOW),
         blur=0.025, strength=2)
    return img


def m9():
    """Alternate: a smaller M inside a faint ring."""
    img = canvas(INK)
    d = ImageDraw.Draw(img)
    circle(d, 0.5, 0.5, 0.36, outline=(90, 50, 36), width=int(C(0.004)))
    circle(d, 0.5, 0.5, 0.33, outline=(60, 36, 28), width=int(C(0.002)))
    font = fitted("M", width=0.42, height=0.4)
    glow(img, lambda d: centered_text(d, "M", font, GLOW), blur=0.03, strength=2)
    return img


def m10():
    """Alternate: an illuminated manuscript initial."""
    img = canvas(PARCHMENT)
    d = ImageDraw.Draw(img)
    d.rectangle((C(0.2), C(0.2), C(0.8), C(0.8)), fill=VERMILION)
    for inset, width in ((0.2, 0.008), (0.225, 0.003)):
        d.rectangle((C(inset), C(inset), C(1 - inset), C(1 - inset)), outline=GOLD, width=int(C(width)))
    for x, y in ((0.2, 0.2), (0.8, 0.2), (0.2, 0.8), (0.8, 0.8)):
        circle(d, x, y, 0.022, fill=GOLD)
        circle(d, x, y, 0.009, fill=VERMILION)
    centered_text(d, "M", fitted("M", width=0.4, height=0.38), PARCHMENT)
    return img


def t8():
    """Alternate: the full wordmark on parchment with a red capital."""
    img = canvas(PARCHMENT)
    d = ImageDraw.Draw(img)
    font = fitted("Moth", width=0.72)
    x, y = centered_text(d, "Moth", font, SEPIA)
    d.text((x, y), "M", font=font, fill=VERMILION)
    return img


def export(img, path, size=SIZE):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").resize((size, size), Image.LANCZOS).save(path, optimize=True)
    print(f"wrote {path.relative_to(ROOT)}")


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def asset_catalog_icon(img, name):
    folder = ROOT / f"Moth/Assets.xcassets/{name}.appiconset"
    export(img, folder / "Icon.png")
    write_json(folder / "Contents.json", {
        "images": [{"filename": "Icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    })


def preview(img, name):
    folder = ROOT / f"Moth/Assets.xcassets/IconPreview-{name}.imageset"
    export(img, folder / "preview.png", size=180)
    write_json(folder / "Contents.json", {
        "images": [{"filename": "preview.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    })


def main():
    icon = m1()
    export(icon, ROOT / "Moth/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
    export(icon, ROOT / "Design/Icons/M1-app-icon.png")
    preview(icon, "Glow")
    alternates = (("Outline", "M7-outline", m7), ("Ring", "M9-ring", m9),
                  ("Illuminated", "M10-illuminated", m10), ("Wordmark", "T8-wordmark", t8))
    for name, design_name, render in alternates:
        img = render()
        export(img, ROOT / f"Design/Icons/alternates/{design_name}.png")
        asset_catalog_icon(img, f"AppIcon-{name}")
        preview(img, name)


if __name__ == "__main__":
    main()
