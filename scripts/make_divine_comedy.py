"""Builds the Divine Comedy theme backdrop from the public-domain Paradiso woodcut
(Design/Art/paradiso-woodcut.png), cleaned up and vectorised:

1. Upscale 3x, denoise, and threshold locally so the engraved lines survive while
   the text showing through from the back of the page drops out.
2. Remove the printed "D" and "B" labels and the outer frame.
3. Find the free-standing stars and replace each with an exact geometric star
   (thin-rayed, solid, or outlined) at the same position, size and rotation.
4. Trace everything else (the angels, Dante and Beatrice) into smooth curves
   with potrace.
5. Write the vector master (Design/Art/paradiso-vector.svg) and render the phone
   backdrop: sepia ink on a soft parchment ground.

Usage: python3 scripts/make_divine_comedy.py
Needs: pip install pillow numpy opencv-python-headless potracer
"""
import json
import math
from pathlib import Path

import cv2
import numpy as np
import potrace
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Design/Art/paradiso-woodcut.png"
SVG_OUT = ROOT / "Design/Art/paradiso-vector.svg"
ASSET = ROOT / "Moth/Assets.xcassets/DivineComedyBackdrop.imageset"

SCALE = 3                      # working resolution relative to the scan
MARGIN = 14                    # scan pixels trimmed to drop the printed frame
LABELS = ((573, 700, 600, 726), (680, 664, 706, 692))   # "D" and "B", scan coords
W, H = 1290, 2796              # phone backdrop (iPhone Pro Max at 3x)
FOCUS_X = 0.58                 # horizontal centre of the crop: Dante and Beatrice

PARCHMENT = (234, 221, 193)
INK = (58, 42, 28)
FIGURE_OPACITY = 0.22
STAR_OPACITY = 0.30


# ---------------------------------------------------------------- clean-up

def ink_mask(scan):
    up = cv2.resize(scan, None, fx=SCALE, fy=SCALE, interpolation=cv2.INTER_CUBIC)
    den = cv2.fastNlMeansDenoising(up, None, h=7, templateWindowSize=7, searchWindowSize=21)
    den = cv2.GaussianBlur(den, (0, 0), 1.2)
    ink = cv2.adaptiveThreshold(den, 1, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY_INV, 61, 14)
    ink &= (den < 175).astype(np.uint8)          # nothing paler than the bleed-through
    for x0, y0, x1, y1 in LABELS:
        ink[y0 * SCALE:y1 * SCALE, x0 * SCALE:x1 * SCALE] = 0
    m = MARGIN * SCALE
    ink = ink[m:-m, m:-m]
    n, labels, stats, _ = cv2.connectedComponentsWithStats(ink, connectivity=8)
    keep = np.zeros(n, bool)
    keep[1:] = stats[1:, cv2.CC_STAT_AREA] >= 60
    return keep[labels].astype(np.uint8)


# ---------------------------------------------------------------- stars

def star_polygon(cx, cy, r, inner, angle):
    pts = []
    for i in range(16):
        a = math.radians(angle + i * 22.5 - 90)
        rr = r if i % 2 == 0 else r * inner
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def star_shapes(cx, cy, r, style, angle):
    """Filled polygons, optional outline, and optional rays describing one clean star."""
    if style == "asterisk":
        rays = []
        for k in range(8):
            a = math.radians(angle + k * 45 - 90)
            rays.append(((cx, cy), (cx + r * 0.95 * math.cos(a), cy + r * 0.95 * math.sin(a))))
        return {"rays": (rays, max(2.0, r * 0.16)), "dot": r * 0.2, "centre": (cx, cy)}
    if style == "ray":
        return {"fill": [star_polygon(cx, cy, r, 0.2, angle)]}
    if style == "solid":
        return {"fill": [star_polygon(cx, cy, r, 0.45, angle)]}
    if style == "outlined-ray":
        return {"outline": (star_polygon(cx, cy, r * 0.94, 0.55, angle), max(2.0, r * 0.13)),
                "fill": [star_polygon(cx, cy, r * 0.5, 0.22, angle + 22.5)]}
    return {"outline": (star_polygon(cx, cy, r * 0.94, 0.55, angle), max(2.0, r * 0.15)),
            "fill": [star_polygon(cx, cy, r * 0.42, 0.45, angle)]}


def rasterise(shapes, size, offset):
    canvas = np.zeros(size, np.uint8)
    ox, oy = offset
    for poly in shapes.get("fill", []):
        pts = np.array([[(x - ox) * 4, (y - oy) * 4] for x, y in poly], np.int32)
        cv2.fillPoly(canvas, [pts], 1, lineType=cv2.LINE_8, shift=2)
    if "outline" in shapes:
        poly, width = shapes["outline"]
        pts = np.array([[(x - ox) * 4, (y - oy) * 4] for x, y in poly], np.int32)
        cv2.polylines(canvas, [pts], True, 1, thickness=max(1, int(round(width))), lineType=cv2.LINE_8, shift=2)
    if "rays" in shapes:
        segments, width = shapes["rays"]
        for (x0, y0), (x1, y1) in segments:
            cv2.line(canvas, (int((x0 - ox) * 4), int((y0 - oy) * 4)), (int((x1 - ox) * 4), int((y1 - oy) * 4)),
                     1, thickness=max(1, int(round(width))), lineType=cv2.LINE_8, shift=2)
    if "dot" in shapes:
        cx, cy = shapes["centre"]
        cv2.circle(canvas, (int((cx - ox) * 4), int((cy - oy) * 4)), int(shapes["dot"] * 4), 1, -1, lineType=cv2.LINE_8, shift=2)
    return canvas


def find_stars(ink):
    """Returns (stars, ink without them). Each star: (cx, cy, r, style, angle)."""
    n, labels, stats, _ = cv2.connectedComponentsWithStats(ink, connectivity=8)
    stars = []
    cleaned = ink.copy()
    for i in range(1, n):
        x, y, w, h, area = stats[i]
        if not (22 <= w <= 120 and 22 <= h <= 120 and 0.65 <= w / h <= 1.55):
            continue
        fill = area / (w * h)
        if not 0.12 <= fill <= 0.7:
            continue
        pad = 6
        x0, y0 = max(0, x - pad), max(0, y - pad)
        comp = (labels[y0:y + h + pad, x0:x + w + pad] == i).astype(np.uint8)
        cx, cy, r = x + w / 2, y + h / 2, max(w, h) / 2
        # Only stars in open sky: a hatch fragment inside a robe has other ink around it.
        # Look at a ring just outside the star's box (the sparkle inside an outlined
        # star is a separate piece of ink, so the box itself is ignored).
        m = int(r * 0.6)
        bx0, by0 = max(0, x - m), max(0, y - m)
        bx1, by1 = min(ink.shape[1], x + w + m), min(ink.shape[0], y + h + m)
        ring = np.ones((by1 - by0, bx1 - bx0), bool)
        ring[y - by0:y - by0 + h, x - bx0:x - bx0 + w] = False
        around = ink[by0:by1, bx0:bx1].astype(bool) & ring & (labels[by0:by1, bx0:bx1] != i)
        if around.sum() > 0.08 * ring.sum():
            continue
        best = (0.0, None)
        for style in ("asterisk", "ray", "solid", "outlined", "outlined-ray"):
            for step in range(18):
                angle = step * 2.5
                shapes = star_shapes(cx, cy, r, style, angle)
                tmpl = rasterise(shapes, comp.shape, (x0, y0))
                inter = np.logical_and(tmpl, comp).sum()
                union = np.logical_or(tmpl, comp).sum()
                iou = inter / union if union else 0
                if iou > best[0]:
                    best = (iou, (cx, cy, r, style, angle))
        if best[0] >= 0.25:
            stars.append(best[1])
            cleaned[labels == i] = 0
            cleaned[y:y + h, x:x + w] = 0        # and any sparkle inside it
    return stars, cleaned


# ---------------------------------------------------------------- tracing

def trace(mask):
    """potrace → list of closed polygons (flattened Béziers) plus SVG path data."""
    # potracer traces the False pixels, so hand it the inverse of the ink.
    plist = potrace.Bitmap(~mask.astype(bool)).trace(turdsize=30, alphamax=1.0, opticurve=True, opttolerance=0.3)
    polys, svg = [], []

    def xy(p):
        return (p.x, p.y) if hasattr(p, "x") else (p[0], p[1])

    for curve in plist:
        start = xy(curve.start_point)
        pts, d = [start], [f"M{start[0]:.1f},{start[1]:.1f}"]
        prev = start
        for seg in curve.segments:
            end = xy(seg.end_point)
            if seg.is_corner:
                c = xy(seg.c)
                pts += [c, end]
                d.append(f"L{c[0]:.1f},{c[1]:.1f}L{end[0]:.1f},{end[1]:.1f}")
            else:
                c1, c2 = xy(seg.c1), xy(seg.c2)
                for k in range(1, 9):
                    t = k / 8
                    u = 1 - t
                    pts.append((u**3 * prev[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t**3 * end[0],
                                u**3 * prev[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t**3 * end[1]))
                d.append(f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} {end[0]:.1f},{end[1]:.1f}")
            prev = end
        d.append("Z")
        polys.append(pts)
        svg.append("".join(d))
    return polys, svg


def write_svg(size, figure_paths, stars):
    w, h = size
    star_paths = []
    for cx, cy, r, style, angle in stars:
        shapes = star_shapes(cx, cy, r, style, angle)
        for poly in shapes.get("fill", []):
            star_paths.append('<path d="M' + "L".join(f"{x:.1f},{y:.1f}" for x, y in poly) + 'Z"/>')
        if "outline" in shapes:
            poly, width = shapes["outline"]
            star_paths.append(f'<path fill="none" stroke="currentColor" stroke-width="{width:.1f}" d="M'
                              + "L".join(f"{x:.1f},{y:.1f}" for x, y in poly) + 'Z"/>')
        if "rays" in shapes:
            segments, width = shapes["rays"]
            d = "".join(f"M{a[0]:.1f},{a[1]:.1f}L{b[0]:.1f},{b[1]:.1f}" for a, b in segments)
            star_paths.append(f'<path fill="none" stroke="currentColor" stroke-linecap="round" stroke-width="{width:.1f}" d="{d}"/>'
                              f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{shapes["dot"]:.1f}"/>')
    SVG_OUT.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" color="#3a2a1c">\n'
        f'<rect width="{w}" height="{h}" fill="#eaddc1"/>\n'
        f'<path fill="currentColor" fill-rule="evenodd" d="{" ".join(figure_paths)}"/>\n'
        f'<g fill="currentColor">{"".join(star_paths)}</g>\n</svg>\n')
    print(f"wrote {SVG_OUT.relative_to(ROOT)}")


# ---------------------------------------------------------------- rendering

def parchment(w, h, seed=3):
    rnd = np.random.default_rng(seed)
    base = np.ones((h, w, 3), np.float32) * np.array(PARCHMENT, np.float32)
    grain = np.zeros((h, w), np.float32)
    for scale, amp in ((6, 7.0), (30, 5.0), (120, 4.0)):
        noise = rnd.standard_normal((h // scale + 2, w // scale + 2)).astype(np.float32)
        grain += cv2.resize(noise, (w, h), interpolation=cv2.INTER_CUBIC) * amp
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    r = np.sqrt(((xx - w / 2) / (w * 0.62)) ** 2 + ((yy - h / 2) / (h * 0.62)) ** 2)
    vignette = np.clip(r - 0.55, 0, 1) * 38
    tone = base + grain[..., None] * np.array([1.0, 0.95, 0.85]) - vignette[..., None] * np.array([0.9, 1.0, 1.25])
    return np.clip(tone, 0, 255)


def render(figure_polys, stars, art_size):
    aw, ah = art_size
    s = H / ah
    ox = (aw * s) * FOCUS_X - W / 2
    sub = 16                                     # cv2 subpixel shift 4 → 1/16 px

    def place(x, y):
        return ((x * s - ox) * sub, (y * s) * sub)

    def to_pts(poly):
        return np.array([place(x, y) for x, y in poly], np.int64).astype(np.int32)

    figures = np.zeros((H, W), np.uint8)
    cv2.fillPoly(figures, [to_pts(p) for p in figure_polys], 255, lineType=cv2.LINE_AA, shift=4)

    star_layer = np.zeros((H, W), np.uint8)
    for cx, cy, r, style, angle in stars:
        shapes = star_shapes(cx, cy, r, style, angle)
        polys = [to_pts(p) for p in shapes.get("fill", [])]
        if polys:
            cv2.fillPoly(star_layer, polys, 255, lineType=cv2.LINE_AA, shift=4)
        if "outline" in shapes:
            poly, width = shapes["outline"]
            cv2.polylines(star_layer, [to_pts(poly)], True, 255, thickness=max(1, int(round(width * s))),
                          lineType=cv2.LINE_AA, shift=4)
        if "rays" in shapes:
            segments, width = shapes["rays"]
            for a, b in segments:
                pa, pb = to_pts([a, b])
                cv2.line(star_layer, tuple(int(v) for v in pa), tuple(int(v) for v in pb), 255,
                         thickness=max(1, int(round(width * s))), lineType=cv2.LINE_AA, shift=4)
            centre = to_pts([(cx, cy)])[0]
            cv2.circle(star_layer, (int(centre[0]), int(centre[1])), int(shapes["dot"] * s * 16), 255, -1,
                       lineType=cv2.LINE_AA, shift=4)

    ground = parchment(W, H)
    alpha = (figures.astype(np.float32) / 255 * FIGURE_OPACITY
             + star_layer.astype(np.float32) / 255 * STAR_OPACITY).clip(0, 1)[..., None]
    out = ground * (1 - alpha) + np.array(INK, np.float32) * alpha
    return Image.fromarray(out.astype(np.uint8), "RGB"), figures, star_layer


def main():
    scan = cv2.imread(str(SOURCE), cv2.IMREAD_GRAYSCALE)
    ink = ink_mask(scan)
    stars, remainder = find_stars(ink)
    print(f"{len(stars)} stars redrawn as clean vectors")
    polys, svg_paths = trace(remainder)
    print(f"{len(polys)} traced paths")
    art_size = (ink.shape[1], ink.shape[0])
    write_svg(art_size, svg_paths, stars)

    backdrop, _, _ = render(polys, stars, art_size)
    ASSET.mkdir(parents=True, exist_ok=True)
    for old in ASSET.glob("backdrop.*"):
        old.unlink()
    backdrop.save(ASSET / "backdrop.jpg", quality=92, optimize=True, progressive=True)
    (ASSET / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "backdrop.jpg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    print(f"wrote {(ASSET / 'backdrop.jpg').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
