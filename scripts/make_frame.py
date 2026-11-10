"""Renders the profile picture frame: a square carved and gilded frame in the
baroque manner (acanthus scrolls along the sides, shell cartouches at the corners
and the middle of each side, a pearl-beaded inner moulding), aged and a little
grimy. Everything is drawn here: a height map of the carving is lit like old gilt.

Writes Moth/Assets.xcassets/PortraitFrame.imageset/frame.png (900×900, the
opening transparent apart from the frame's shadow falling onto the picture).

    python3 scripts/make_frame.py

Needs numpy, scipy and Pillow.
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

S = 1800            # working size; the output is half this
FW = 220            # frame width at working size
BAND = (36, 150)    # where the carved ornament band sits, as distance from the outer edge
OUT = os.path.join(os.path.dirname(__file__), "..", "Moth", "Assets.xcassets", "PortraitFrame.imageset")

rng = np.random.default_rng(7)


def relief(mask, radius):
    """Rounded relief for a filled shape: rises over `radius` px from its edge."""
    dist = ndimage.distance_transform_edt(mask)
    return np.sqrt(np.clip(dist / radius, 0, 1))


def spiral(draw, cx, cy, r0, start, turns, direction, w0, w1, steps=60):
    """A tapering spiral stroke, the bones of every scroll."""
    points = []
    for i in range(steps + 1):
        t = i / steps
        a = start + direction * t * turns * 2 * math.pi
        r = r0 * (1 - 0.78 * t)
        points.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    for i in range(steps):
        t = i / steps
        w = w0 + (w1 - w0) * t
        draw.line([points[i], points[i + 1]], fill=255, width=max(1, int(w)))
        draw.ellipse([points[i][0] - w / 2, points[i][1] - w / 2, points[i][0] + w / 2, points[i][1] + w / 2], fill=255)
    return points


def leaf(draw, x, y, length, width, angle, lobes=3):
    """An acanthus leaf: a few overlapping lobes along a curved spine."""
    for k in range(lobes):
        t = (k + 0.5) / lobes
        lx = x + math.cos(angle) * length * t
        ly = y + math.sin(angle) * length * t
        w = width * (1 - 0.45 * t)
        poly = []
        for j in range(20):
            a = j / 20 * 2 * math.pi
            px = math.cos(a) * length / lobes * 0.75
            py = math.sin(a) * w * 0.5
            poly.append((lx + px * math.cos(angle) - py * math.sin(angle), ly + px * math.sin(angle) + py * math.cos(angle)))
        draw.polygon(poly, fill=255)


# MARK: the ornament band, drawn once as a straight strip

def band_strip():
    length, height = S, BAND[1] - BAND[0]
    period = 225
    scrolls = Image.new("L", (length, height))
    leaves = Image.new("L", (length, height))
    berries = Image.new("L", (length, height))
    veins = Image.new("L", (length, height))
    ds, dl, db, dv = (ImageDraw.Draw(i) for i in (scrolls, leaves, berries, veins))
    mid = height / 2
    for x0 in range(-period, length + period, period):
        # Two opposed C-scrolls making a running S.
        spiral(ds, x0 + 62, mid + 8, 40, math.pi * 0.9, 1.3, 1, 19, 6)
        spiral(ds, x0 + 162, mid - 8, 40, -math.pi * 0.1, 1.3, 1, 19, 6)
        # Acanthus leaves curling off them, above and below.
        leaf(dl, x0 + 88, mid - 6, 92, 52, -0.55)
        leaf(dl, x0 + 136, mid + 6, 92, 52, math.pi - 0.55)
        leaf(dl, x0 + 10, mid - 30, 64, 36, 0.3, lobes=2)
        leaf(dl, x0 + 214, mid + 30, 64, 36, math.pi + 0.3, lobes=2)
        # Veins cut into the leaves.
        dv.line([(x0 + 92, mid - 8), (x0 + 150, mid - 44)], fill=255, width=4)
        dv.line([(x0 + 132, mid + 8), (x0 + 74, mid + 44)], fill=255, width=4)
        # Berries in the gaps.
        for bx, by, r in ((x0 + 112, mid, 11), (x0 + 30, mid + 38, 8), (x0 + 194, mid - 38, 8)):
            db.ellipse([bx - r, by - r, bx + r, by + r], fill=255)
    h = np.maximum.reduce([
        relief(np.array(leaves) > 0, 13) * 0.5,
        relief(np.array(scrolls) > 0, 9) * 0.75,
        relief(np.array(berries) > 0, 9) * 0.8,
    ])
    h -= ndimage.gaussian_filter((np.array(veins) > 0).astype(float), 1.5) * 0.25
    return np.clip(h, 0, None)


# MARK: the frame's height map

ys, xs = np.mgrid[0:S, 0:S].astype(float)
d_top, d_bottom, d_left, d_right = ys, S - 1 - ys, xs, S - 1 - xs
d = np.minimum.reduce([d_top, d_bottom, d_left, d_right])
side = np.argmin(np.stack([d_top, d_bottom, d_left, d_right]), axis=0)
# Position along each side, running clockwise so the pattern turns the corners the same way.
along = np.choose(side, [xs, S - 1 - xs, S - 1 - ys, ys])


def profile(d):
    """The moulding's cross-section, outside to inside."""
    h = np.zeros_like(d)
    bead = d < 14
    h[bead] = 0.55 * np.sqrt(np.clip(1 - ((d[bead] - 7) / 7) ** 2, 0, 1))
    cove = (d >= 14) & (d < BAND[0])
    h[cove] = 0.22 + 0.2 * ((d[cove] - 25) / 11) ** 2
    band = (d >= BAND[0]) & (d < BAND[1])
    h[band] = 0.3
    torus = (d >= 150) & (d < 172)
    h[torus] = 0.4 + 0.42 * np.sqrt(np.clip(1 - ((d[torus] - 161) / 11) ** 2, 0, 1))
    channel = (d >= 172) & (d < 198)
    h[channel] = 0.26
    fillet = (d >= 198) & (d < 212)
    h[fillet] = 0.36 - (d[fillet] - 198) / 14 * 0.24
    lip = (d >= 212) & (d < FW)
    h[lip] = 0.1
    return h


H = profile(d)

# Pearls along the inner channel.
pearl_pitch = 22
pearl_t = (along % pearl_pitch) - pearl_pitch / 2
pearl_r = np.sqrt(pearl_t ** 2 + (d - 185) ** 2)
pearls = np.sqrt(np.clip(1 - (pearl_r / 9) ** 2, 0, 1)) * 0.36
H = np.where((d >= 172) & (d < 198), H + pearls, H)

# Cartouches: shells and scrolls at the corners and the middle of each side.
cart = Image.new("L", (S, S))
cart_hi = Image.new("L", (S, S))
dc, dh = ImageDraw.Draw(cart), ImageDraw.Draw(cart_hi)


def shell(draw, cx, cy, radius, facing, ribs=9, spread=2.2):
    pts = [(cx, cy)]
    for i in range(ribs * 4 + 1):
        a = facing - spread / 2 + spread * i / (ribs * 4)
        scallop = 1 - 0.12 * abs(math.sin(i / 4 * math.pi))
        pts.append((cx + radius * scallop * math.cos(a), cy + radius * scallop * math.sin(a)))
    draw.polygon(pts, fill=255)


corner = 104
# Top-left corner: a shell facing into the frame, scrolls along both sides, a boss.
shell(dc, corner, corner, 112, math.pi / 4)
for sx, sy, start, direction in ((corner + 110, 52, math.pi, 1), (52, corner + 110, -math.pi / 2, -1)):
    spiral(dh, sx, sy, 38, start, 1.25, direction, 19, 6)
leaf(dc, corner + 50, corner - 52, 130, 58, 0.0)
leaf(dc, corner - 52, corner + 50, 130, 58, math.pi / 2)
dh.ellipse([corner - 28, corner - 28, corner + 28, corner + 28], fill=255)
# Middle of the top side: a smaller shell flanked by scrolls and leaves.
mx = S / 2
shell(dc, mx, 160, 100, -math.pi / 2, ribs=7, spread=2.4)
spiral(dh, mx - 86, 100, 34, 0, 1.25, -1, 17, 5)
spiral(dh, mx + 86, 100, 34, math.pi, 1.25, 1, 17, 5)
leaf(dc, mx - 44, 116, 140, 56, math.pi)
leaf(dc, mx + 44, 116, 140, 56, 0)
dh.ellipse([mx - 22, 98, mx + 22, 142], fill=255)

cart_mask = np.array(cart) > 0
cart_hi_mask = np.array(cart_hi) > 0
for k in (1, 2, 3):
    cart_mask |= np.rot90(np.array(cart) > 0, k)
    cart_hi_mask |= np.rot90(np.array(cart_hi) > 0, k)
cart_h = np.maximum(relief(cart_mask, 18) * 0.8, relief(cart_hi_mask, 10) * 1.05)

# Shell ribs: grooves fanning across the shells.
ribs = Image.new("L", (S, S))
dr = ImageDraw.Draw(ribs)
for i in range(1, 9):
    a = math.pi / 4 - 1.1 + 2.2 * i / 9
    dr.line([(corner, corner), (corner + 108 * math.cos(a), corner + 108 * math.sin(a))], fill=255, width=4)
for i in range(1, 7):
    a = -math.pi / 2 - 1.2 + 2.4 * i / 7
    dr.line([(mx, 160), (mx + 96 * math.cos(a), 160 + 96 * math.sin(a))], fill=255, width=4)
rib_mask = np.array(ribs) > 0
for k in (1, 2, 3):
    rib_mask |= np.rot90(np.array(ribs) > 0, k)
cart_h -= ndimage.gaussian_filter(rib_mask.astype(float), 1.5) * 0.25 * (cart_h > 0)

# The running ornament fills the band except where a cartouche sits on it.
strip = band_strip()
in_band = (d >= BAND[0]) & (d < BAND[1])
v = np.clip(d - BAND[0], 0, strip.shape[0] - 1).astype(int)
u = (along.astype(int)) % strip.shape[1]
band_h = np.where(in_band, strip[v, u], 0)
keep_out = ndimage.binary_dilation(cart_mask | cart_hi_mask, iterations=10)
band_h = np.where(keep_out, 0, band_h)
H = H + band_h
H = np.where(cart_h > 0.01, np.maximum(H, 0.3 + cart_h), H)

frame = d < FW
H = ndimage.gaussian_filter(H, 1.3)

# MARK: lighting

Z = H * 38
gy, gx = np.gradient(Z)
n = np.dstack([-gx, -gy, np.ones_like(Z)])
n /= np.linalg.norm(n, axis=2, keepdims=True)
light = np.array([-0.5, -0.7, 0.6])
light /= np.linalg.norm(light)
diffuse = np.clip((n * light).sum(axis=2), 0, 1)
half = light + np.array([0, 0, 1.0])
half /= np.linalg.norm(half)
spec = np.clip((n * half).sum(axis=2), 0, 1) ** 36

cavity = ndimage.gaussian_filter(Z, 7) - Z
ao = np.clip(1 - cavity * 0.075, 0.25, 1)

ramp = np.array([
    (18, 15, 6), (58, 50, 22), (108, 92, 42), (160, 136, 68), (206, 182, 112), (240, 222, 164),
], float)


def gold(t):
    t = np.clip(t, 0, 1) * (len(ramp) - 1)
    i = np.clip(t.astype(int), 0, len(ramp) - 2)
    f = (t - i)[..., None]
    return ramp[i] * (1 - f) + ramp[i + 1] * f


color = gold(0.04 + 0.96 * diffuse ** 1.25) * ao[..., None]
color += spec[..., None] * np.array([255, 236, 180]) * 0.5

# Age: the gilt rubbed thin in patches, grime settled in the hollows.
patches = ndimage.gaussian_filter(rng.random((S, S)), 22)
patches = (patches - patches.min()) / (patches.max() - patches.min())
color *= (0.82 + 0.26 * patches)[..., None]
grime = np.clip(cavity * 0.06, 0, 1)[..., None]
color = color * (1 - grime * 0.6) + np.array([46, 44, 24]) * grime * 0.6
speckle = ndimage.gaussian_filter(rng.random((S, S)), 1.2)
color *= (0.94 + 0.12 * speckle)[..., None]
# A dark outer edge so the frame sits on any background.
edge = np.clip(1 - d / 4, 0, 1)[..., None]
color = color * (1 - 0.6 * edge)

rgba = np.zeros((S, S, 4))
rgba[..., :3] = np.clip(color, 0, 255)
rgba[..., 3] = np.where(frame, 255, 0)

# The frame's shadow falling onto the picture, heaviest under the top and left.
inside = d - FW
weight = np.choose(side, [1.0, 0.45, 0.9, 0.55])
shadow = np.clip(1 - inside / 46, 0, 1) ** 2 * 0.62 * weight
rgba[..., :3] = np.where(frame[..., None], rgba[..., :3], 0)
rgba[..., 3] = np.where(frame, 255, np.where(inside >= 0, shadow * 255, 0))

image = Image.fromarray(rgba.astype(np.uint8), "RGBA").resize((S // 2, S // 2), Image.LANCZOS)
os.makedirs(OUT, exist_ok=True)
image.save(os.path.join(OUT, "frame.png"), optimize=True)
with open(os.path.join(OUT, "Contents.json"), "w") as f:
    json.dump({"images": [{"filename": "frame.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, f, indent=2)
print("wrote", os.path.join(OUT, "frame.png"))
