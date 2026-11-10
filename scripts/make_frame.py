"""Renders the profile picture frame: a square carved and gilded frame, aged a
little. Everything is drawn here: a height map of the carving (mouldings, a
running ornament, cartouches at the corners and the middle of each side) is lit
like old gilt.

There are twenty designs (OPTIONS below). Render one into the app:

    python3 scripts/make_frame.py --option 1

or a numbered contact sheet of all of them to choose from:

    python3 scripts/make_frame.py --gallery out_dir

The app's frame is Moth/Assets.xcassets/PortraitFrame.imageset/frame.png
(900×900, the opening transparent apart from the frame's shadow falling onto the
picture). The opening's inset is printed; HauntedPortrait.frameWidth must match.

Needs numpy, scipy and Pillow.
"""
import argparse
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

S = 1800   # working size; the app's image is half this
ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "Moth", "Assets.xcassets", "PortraitFrame.imageset")

# Gold: shadow to highlight, the colour of the shine, how strong the shine is.
PALETTES = {
    "antique":   ([(26, 15, 5), (78, 48, 14), (138, 94, 34), (186, 140, 64), (220, 182, 108), (240, 216, 156)], (255, 230, 170), 0.42),
    "rich":      ([(30, 16, 4), (100, 60, 12), (168, 116, 30), (214, 166, 64), (238, 204, 118), (252, 234, 182)], (255, 238, 196), 0.5),
    "red":       ([(28, 10, 4), (92, 40, 12), (156, 88, 32), (204, 136, 62), (232, 186, 118), (248, 222, 172)], (255, 226, 182), 0.45),
    "champagne": ([(30, 24, 14), (88, 72, 44), (146, 124, 84), (192, 172, 126), (224, 208, 168), (244, 236, 210)], (255, 248, 226), 0.4),
    "candlelit": ([(12, 7, 3), (44, 26, 8), (92, 60, 20), (144, 104, 44), (190, 150, 86), (222, 194, 136)], (255, 214, 150), 0.38),
    "burnished": ([(36, 20, 4), (112, 70, 14), (184, 132, 38), (226, 182, 82), (246, 218, 146), (255, 246, 214)], (255, 250, 230), 0.75),
}

# name, palette, frame width, running ornament, corner, centre, inner moulding, outer moulding, age (0–1), ornament scale
OPTIONS = [
    ("Salon",        "antique",   220, "scroll",   "shell",     "shell",     "pearls", "bead", 0.6, 1.0),
    ("Versailles",   "rich",      240, "acanthus", "shell",     "shell",     "pearls", "rope", 0.35, 1.0),
    ("Louis XV",     "burnished", 220, "plain",    "rocaille",  "rocaille",  "leaf",   "bead", 0.25, 1.0),
    ("Medici",       "red",       240, "rinceau",  "cartouche", "cartouche", "pearls", "bead", 0.55, 1.0),
    ("Duchess",      "champagne", 220, "garland",  "rosette",   "rosette",   "pearls", "rope", 0.3, 1.0),
    ("Candle Room",  "candlelit", 240, "scroll",   "acanthus",  "shell",     "pearls", "bead", 0.8, 1.0),
    ("Gadroon",      "rich",      220, "gadroon",  "acanthus",  "none",      "leaf",   "rope", 0.4, 1.0),
    ("Old Bank",     "antique",   260, "egg",      "cartouche", "shell",     "pearls", "bead", 0.6, 1.0),
    ("Rocaille",     "rich",      240, "plain",    "rocaille",  "rocaille",  "pearls", "rope", 0.45, 1.15),
    ("Hermitage",    "red",       220, "acanthus", "acanthus",  "rosette",   "leaf",   "bead", 0.5, 1.0),
    ("Fontainebleau","burnished", 250, "rinceau",  "shell",     "rocaille",  "pearls", "rope", 0.3, 1.1),
    ("Estate Sale",  "candlelit", 220, "egg",      "shell",     "none",      "pearls", "bead", 0.9, 1.0),
    ("Trianon",      "champagne", 240, "acanthus", "rocaille",  "shell",     "pearls", "bead", 0.35, 1.0),
    ("Bourbon",      "red",       260, "gadroon",  "cartouche", "cartouche", "pearls", "rope", 0.55, 1.1),
    ("Gilded Age",   "burnished", 230, "scroll",   "rosette",   "shell",     "leaf",   "rope", 0.2, 0.9),
    ("Chapel",       "antique",   240, "rinceau",  "acanthus",  "acanthus",  "pearls", "bead", 0.7, 1.0),
    ("Heirloom",     "rich",      220, "garland",  "shell",     "rosette",   "pearls", "bead", 0.5, 1.0),
    ("Auction House","candlelit", 260, "acanthus", "cartouche", "rocaille",  "leaf",   "rope", 0.75, 1.15),
    ("Petit Salon",  "champagne", 200, "scroll",   "shell",     "none",      "pearls", "bead", 0.4, 0.85),
    ("Grand Manner", "antique",   270, "acanthus", "rocaille",  "cartouche", "pearls", "rope", 0.55, 1.2),
]


# MARK: drawing helpers

def relief(mask, radius):
    """Rounded relief for a filled shape: rises over `radius` px from its edge."""
    dist = ndimage.distance_transform_edt(mask)
    return np.sqrt(np.clip(dist / radius, 0, 1))


def dot(draw, x, y, r):
    draw.ellipse([x - r, y - r, x + r, y + r], fill=255)


def stroke(draw, pts, w0, w1):
    n = len(pts) - 1
    for i in range(n):
        w = w0 + (w1 - w0) * i / n
        draw.line([pts[i], pts[i + 1]], fill=255, width=max(1, int(w)))
        dot(draw, pts[i][0], pts[i][1], w / 2)


def spiral(draw, cx, cy, r0, start, turns, direction, w0, w1, steps=60):
    """A tapering spiral stroke: the bones of every scroll."""
    pts = []
    for i in range(steps + 1):
        t = i / steps
        a = start + direction * t * turns * 2 * math.pi
        r = r0 * (1 - 0.78 * t)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    stroke(draw, pts, w0, w1)


def leaf(draw, x, y, length, width, angle, lobes=3):
    """An acanthus leaf: overlapping lobes along a spine."""
    for k in range(lobes):
        t = (k + 0.5) / lobes
        lx, ly = x + math.cos(angle) * length * t, y + math.sin(angle) * length * t
        w = width * (1 - 0.45 * t)
        poly = []
        for j in range(20):
            a = j / 20 * 2 * math.pi
            px, py = math.cos(a) * length / lobes * 0.75, math.sin(a) * w * 0.5
            poly.append((lx + px * math.cos(angle) - py * math.sin(angle), ly + px * math.sin(angle) + py * math.cos(angle)))
        draw.polygon(poly, fill=255)


def flame_leaf(draw, x, y, length, width, angle, curl=0.5):
    """A rocaille leaf: long, curving and pointed like a flame."""
    left, right = [], []
    for i in range(25):
        t = i / 24
        a = angle + curl * t * t
        cx = x + math.cos(angle) * length * t - math.sin(a) * length * 0.12 * t * t * np.sign(curl or 1)
        cy = y + math.sin(angle) * length * t + math.cos(a) * length * 0.12 * t * t * np.sign(curl or 1)
        w = width * math.sin(math.pi * min(1, t * 1.15)) * (1 - 0.6 * t) / 2
        nx, ny = -math.sin(a), math.cos(a)
        left.append((cx + nx * w, cy + ny * w))
        right.append((cx - nx * w, cy - ny * w))
    draw.polygon(left + right[::-1], fill=255)


def shell(draw, cx, cy, radius, facing, lobes=9, spread=2.2):
    """A rocaille shell: soft rounded lobes around a fan."""
    pts = [(cx, cy)]
    steps = lobes * 10
    for i in range(steps + 1):
        a = facing - spread / 2 + spread * i / steps
        lobe = 0.84 + 0.16 * math.sqrt(abs(math.sin(i / 10 * math.pi)))
        pts.append((cx + radius * lobe * math.cos(a), cy + radius * lobe * math.sin(a)))
    draw.polygon(pts, fill=255)


def ribs(draw, cx, cy, radius, facing, spread, count):
    """Shell ribs that swirl a little as they run out to the rim."""
    for i in range(1, count):
        a0 = facing - spread / 2 + spread * i / count
        pts = []
        for j in range(12):
            t = 0.3 + 0.55 * j / 11
            a = a0 + 0.18 * math.sin(t * math.pi) * (1 if i % 2 else -1)
            pts.append((cx + radius * t * math.cos(a), cy + radius * t * math.sin(a)))
        draw.line(pts, fill=255, width=3)


def rosette(draw, groove, cx, cy, radius, petals=8):
    for k in range(petals):
        a = k / petals * 2 * math.pi
        leaf(draw, cx, cy, radius, radius * 0.55, a, lobes=2)
        groove.line([(cx, cy), (cx + radius * 0.8 * math.cos(a), cy + radius * 0.8 * math.sin(a))], fill=255, width=3)


# MARK: running ornaments, drawn as a straight strip

def band_strip(style, height, scale):
    length = S
    low, high, top, groove = (Image.new("L", (length, height)) for _ in range(4))
    dl, dh, dt, dg = (ImageDraw.Draw(i) for i in (low, high, top, groove))
    mid = height / 2
    k = height / 114 * scale

    if style == "scroll":
        period = int(225 * k)
        for x0 in range(-period, length + period, period):
            spiral(dh, x0 + 62 * k, mid + 8 * k, 40 * k, math.pi * 0.9, 1.3, 1, 19 * k, 6 * k)
            spiral(dh, x0 + 162 * k, mid - 8 * k, 40 * k, -math.pi * 0.1, 1.3, 1, 19 * k, 6 * k)
            leaf(dl, x0 + 88 * k, mid - 6 * k, 92 * k, 52 * k, -0.55)
            leaf(dl, x0 + 136 * k, mid + 6 * k, 92 * k, 52 * k, math.pi - 0.55)
            leaf(dl, x0 + 10 * k, mid - 30 * k, 64 * k, 36 * k, 0.3, lobes=2)
            leaf(dl, x0 + 214 * k, mid + 30 * k, 64 * k, 36 * k, math.pi + 0.3, lobes=2)
            dg.line([(x0 + 92 * k, mid - 8 * k), (x0 + 150 * k, mid - 44 * k)], fill=255, width=4)
            dg.line([(x0 + 132 * k, mid + 8 * k), (x0 + 74 * k, mid + 44 * k)], fill=255, width=4)
            for bx, by, r in ((112, 0, 11), (30, 38, 8), (194, -38, 8)):
                dot(dt, x0 + bx * k, mid + by * k, r * k)
    elif style == "acanthus":
        # Big leaves overlapping one after another, all curling the same way.
        period = int(120 * k)
        for x0 in range(-period * 2, length + period, period):
            leaf(dl, x0, mid + 30 * k, 170 * k, 88 * k, -0.42, lobes=4)
            dg.line([(x0 + 10 * k, mid + 24 * k), (x0 + 140 * k, mid - 38 * k)], fill=255, width=4)
            spiral(dh, x0 + 150 * k, mid - 30 * k, 18 * k, math.pi / 2, 1.1, 1, 10 * k, 4 * k)
    elif style == "rinceau":
        # A vine running in waves, curling off into a scroll at every crest.
        period = int(200 * k)
        stem = [(x, mid + math.sin(x / period * 2 * math.pi) * 26 * k) for x in range(-period, length + period, 6)]
        stroke(dh, stem, 13 * k, 13 * k)
        for x0 in range(-period, length + period, period):
            for half, sign in ((0.25, -1), (0.75, 1)):
                x = x0 + half * period
                y = mid + sign * 26 * k
                spiral(dh, x + 30 * k, y + sign * 4 * k, 30 * k, math.pi if sign < 0 else 0, 1.2, sign, 11 * k, 4 * k)
                leaf(dl, x - 10 * k, y, 70 * k, 40 * k, -sign * 0.9 + (math.pi if sign > 0 else 0), lobes=3)
                dot(dt, x + 60 * k, y - sign * 30 * k, 8 * k)
    elif style == "garland":
        # Rosettes strung on a ribbon, with leaf pairs between.
        period = int(150 * k)
        ribbon = [(x, mid + math.sin(x / period * 2 * math.pi) * 12 * k) for x in range(-period, length + period, 6)]
        stroke(dl, ribbon, 16 * k, 16 * k)
        for x0 in range(-period, length + period, period):
            rosette(dh, dg, x0, mid, 34 * k, petals=7)
            dot(dt, x0, mid, 9 * k)
            leaf(dl, x0 + 75 * k, mid, 56 * k, 30 * k, -0.7, lobes=2)
            leaf(dl, x0 + 75 * k, mid, 56 * k, 30 * k, math.pi + 0.7, lobes=2)
            for j in (-1, 1):
                dot(dt, x0 + 75 * k + j * 22 * k, mid + 34 * k, 7 * k)
    elif style == "egg":
        # Egg-and-dart: eggs in raised shells, with darts between.
        period = int(84 * k)
        for x0 in range(-period, length + period, period):
            ex, ew, eh = x0 + period / 2, period * 0.34, height * 0.36
            dl.ellipse([ex - ew - 9 * k, mid - eh - 9 * k, ex + ew + 9 * k, mid + eh + 9 * k], fill=255)
            dg.ellipse([ex - ew - 3 * k, mid - eh - 3 * k, ex + ew + 3 * k, mid + eh + 3 * k], outline=255, width=max(2, int(4 * k)))
            dh.ellipse([ex - ew, mid - eh, ex + ew, mid + eh], fill=255)
            dt.polygon([(x0, mid - eh), (x0 + 7 * k, mid + eh * 0.2), (x0, mid + eh), (x0 - 7 * k, mid + eh * 0.2)], fill=255)
    elif style == "gadroon":
        # Slanting convex lobes, packed close.
        period = int(46 * k)
        for x0 in range(-period * 3, length + period * 3, period):
            poly = []
            for j in range(24):
                a = j / 24 * 2 * math.pi
                px, py = math.cos(a) * height * 0.48, math.sin(a) * period * 0.42
                rot = -0.55
                poly.append((x0 + px * math.sin(rot) + py * math.cos(rot), mid + px * math.cos(rot) - py * math.sin(rot)))
            dh.polygon(poly, fill=255)
    # "plain": nothing; the band is a smooth swell.

    h = np.maximum.reduce([
        relief(np.array(low) > 0, 13 * k) * 0.5,
        relief(np.array(high) > 0, 10 * k) * 0.75,
        relief(np.array(top) > 0, 8 * k) * 0.82,
    ])
    h -= ndimage.gaussian_filter((np.array(groove) > 0).astype(float), 1.5) * 0.22
    return np.clip(h, 0, None)


# MARK: cartouches, drawn for the top-left corner and the top centre

def corner_ornament(style, dl, dh, dg, c, k):
    if style == "shell":
        shell(dl, c, c, 112 * k, math.pi / 4)
        ribs(dg, c, c, 112 * k, math.pi / 4, 2.2, 9)
        spiral(dh, c + 110 * k, 52 * k, 38 * k, math.pi, 1.25, 1, 19 * k, 6 * k)
        spiral(dh, 52 * k, c + 110 * k, 38 * k, -math.pi / 2, 1.25, -1, 19 * k, 6 * k)
        leaf(dl, c + 50 * k, c - 52 * k, 130 * k, 58 * k, 0.0)
        leaf(dl, c - 52 * k, c + 50 * k, 130 * k, 58 * k, math.pi / 2)
        dot(dh, c, c, 28 * k)
    elif style == "rocaille":
        # A frilled shell turned out of the corner, C-scrolls and flame leaves sweeping along the sides.
        shell(dl, c * 0.8, c * 0.8, 120 * k, -3 * math.pi / 4, lobes=11, spread=2.0)
        ribs(dg, c * 0.8, c * 0.8, 120 * k, -3 * math.pi / 4, 2.0, 11)
        for sign in (1, -1):
            def p(x, y):
                return (x, y) if sign > 0 else (y, x)
            spiral(dh, *p(c + 120 * k, 60 * k), 40 * k, math.pi if sign > 0 else -math.pi / 2, 1.2, sign, 22 * k, 6 * k)
            x, y = p(c + 40 * k, c + 10 * k)
            flame_leaf(dl, x, y, 200 * k, 80 * k, 0.12 if sign > 0 else math.pi / 2 - 0.12, curl=-0.6 * sign)
        flame_leaf(dl, c + 20 * k, c + 20 * k, 120 * k, 60 * k, math.pi / 4, curl=0.0)
        dot(dh, c + 10 * k, c + 10 * k, 30 * k)
    elif style == "acanthus":
        # A burst of acanthus from the corner, the outer leaves running along each side.
        for a, length in ((0.05, 210), (math.pi / 2 - 0.05, 210), (math.pi / 4, 150), (math.pi / 4 - 0.4, 170), (math.pi / 4 + 0.4, 170)):
            leaf(dl, c * 0.55, c * 0.55, length * k, 80 * k, a, lobes=4)
            dg.line([(c * 0.55, c * 0.55), (c * 0.55 + length * 0.8 * k * math.cos(a), c * 0.55 + length * 0.8 * k * math.sin(a))], fill=255, width=4)
        dot(dh, c * 0.6, c * 0.6, 32 * k)
        spiral(dh, c + 150 * k, 46 * k, 30 * k, math.pi, 1.2, 1, 16 * k, 5 * k)
        spiral(dh, 46 * k, c + 150 * k, 30 * k, -math.pi / 2, 1.2, -1, 16 * k, 5 * k)
    elif style == "rosette":
        rosette(dl, dg, c, c, 80 * k, petals=10)
        dot(dh, c, c, 30 * k)
        for a in (0.0, math.pi / 2):
            leaf(dl, c + 70 * k * math.cos(a), c + 70 * k * math.sin(a), 140 * k, 56 * k, a, lobes=3)
        spiral(dh, c + 190 * k, 50 * k, 30 * k, math.pi, 1.2, 1, 15 * k, 5 * k)
        spiral(dh, 50 * k, c + 190 * k, 30 * k, -math.pi / 2, 1.2, -1, 15 * k, 5 * k)
    elif style == "cartouche":
        # An oval cartouche set on the diagonal, ringed and bossed, with scrolls either side.
        cx = cy = c
        ring = [(cx + 74 * k * math.cos(t) * math.cos(math.pi / 4) - 52 * k * math.sin(t) * math.sin(math.pi / 4),
                 cy + 74 * k * math.cos(t) * math.sin(math.pi / 4) + 52 * k * math.sin(t) * math.cos(math.pi / 4))
                for t in np.linspace(0, 2 * math.pi, 80)]
        stroke(dh, ring, 18 * k, 18 * k)
        dl.polygon(ring, fill=255)
        dot(dh, cx, cy, 26 * k)
        for sign in (1, -1):
            def p(x, y):
                return (x, y) if sign > 0 else (y, x)
            spiral(dh, *p(c + 100 * k, 50 * k), 34 * k, math.pi if sign > 0 else -math.pi / 2, 1.25, sign, 18 * k, 6 * k)
            x, y = p(c + 70 * k, c - 30 * k)
            leaf(dl, x, y, 150 * k, 56 * k, 0.0 if sign > 0 else math.pi / 2)


def centre_ornament(style, dl, dh, dg, mx, y, k):
    if style == "shell":
        shell(dl, mx, y + 56 * k, 100 * k, -math.pi / 2, lobes=7, spread=2.4)
        ribs(dg, mx, y + 56 * k, 100 * k, -math.pi / 2, 2.4, 7)
        spiral(dh, mx - 86 * k, y - 4 * k, 34 * k, 0, 1.25, -1, 17 * k, 5 * k)
        spiral(dh, mx + 86 * k, y - 4 * k, 34 * k, math.pi, 1.25, 1, 17 * k, 5 * k)
        leaf(dl, mx - 44 * k, y + 12 * k, 140 * k, 56 * k, math.pi)
        leaf(dl, mx + 44 * k, y + 12 * k, 140 * k, 56 * k, 0)
        dot(dh, mx, y + 16 * k, 22 * k)
    elif style == "rocaille":
        shell(dl, mx, y + 40 * k, 104 * k, -math.pi / 2, lobes=9, spread=2.5)
        ribs(dg, mx, y + 40 * k, 104 * k, -math.pi / 2, 2.5, 9)
        for sign in (-1, 1):
            spiral(dh, mx + sign * 100 * k, y + 6 * k, 34 * k, 0 if sign < 0 else math.pi, 1.2, sign, 18 * k, 5 * k)
            flame_leaf(dl, mx + sign * 50 * k, y + 26 * k, 190 * k, 70 * k, 0 if sign > 0 else math.pi, curl=0.5 * sign)
        dot(dh, mx, y + 22 * k, 24 * k)
    elif style == "rosette":
        rosette(dl, dg, mx, y + 10 * k, 66 * k, petals=9)
        dot(dh, mx, y + 10 * k, 24 * k)
        for sign in (-1, 1):
            leaf(dl, mx + sign * 60 * k, y + 10 * k, 130 * k, 50 * k, 0 if sign > 0 else math.pi)
    elif style == "cartouche":
        dl.ellipse([mx - 70 * k, y - 34 * k, mx + 70 * k, y + 54 * k], fill=255)
        dh.ellipse([mx - 70 * k, y - 34 * k, mx + 70 * k, y + 54 * k], outline=255, width=int(16 * k))
        dot(dh, mx, y + 10 * k, 24 * k)
        for sign in (-1, 1):
            spiral(dh, mx + sign * 104 * k, y + 4 * k, 30 * k, 0 if sign < 0 else math.pi, 1.25, sign, 16 * k, 5 * k)
            leaf(dl, mx + sign * 120 * k, y + 20 * k, 120 * k, 46 * k, 0 if sign > 0 else math.pi)
    elif style == "acanthus":
        for a, length in ((math.pi, 190), (0, 190), (-math.pi / 2 + 0.5, 110), (-math.pi / 2 - 0.5, 110)):
            leaf(dl, mx, y + 20 * k, length * k, 70 * k, a, lobes=4)
        dot(dh, mx, y + 14 * k, 28 * k)


# MARK: the frame

def render(option):
    name, palette, fw, band_style, corner_style, centre_style, inner, outer, age, scale = option
    rng = np.random.default_rng(7)
    f = fw / 220
    k = f * scale
    band = (round(36 * f), round(150 * f))

    ys, xs = np.mgrid[0:S, 0:S].astype(float)
    d = np.minimum.reduce([ys, S - 1 - ys, xs, S - 1 - xs])
    side = np.argmin(np.stack([ys, S - 1 - ys, xs, S - 1 - xs]), axis=0)
    along = np.choose(side, [xs, S - 1 - xs, S - 1 - ys, ys])

    def seg(lo, hi):
        return (d >= lo * f) & (d < hi * f)

    H = np.zeros((S, S))
    m = seg(0, 14); H[m] = 0.55 * np.sqrt(np.clip(1 - ((d[m] / f - 7) / 7) ** 2, 0, 1))
    m = seg(14, 36); H[m] = 0.22 + 0.2 * ((d[m] / f - 25) / 11) ** 2
    m = seg(36, 150)
    H[m] = 0.3 + (0.5 * np.sin(np.pi * (d[m] / f - 36) / 114) if band_style == "plain" else 0)
    m = seg(150, 172); H[m] = 0.4 + 0.42 * np.sqrt(np.clip(1 - ((d[m] / f - 161) / 11) ** 2, 0, 1))
    m = seg(172, 198); H[m] = 0.26
    m = seg(198, 212); H[m] = 0.36 - (d[m] / f - 198) / 14 * 0.24
    m = seg(212, 220); H[m] = 0.1

    if outer == "rope":
        # A twisted rope on the outer bead.
        m = seg(0, 14)
        twist = 0.5 + 0.5 * np.cos((along + d * 1.0) / (9 * f) * math.pi)
        H[m] = H[m] * (0.6 + 0.4 * twist[m])
    if inner == "pearls":
        pitch = 22 * f
        t = (along % pitch) - pitch / 2
        r = np.sqrt(t ** 2 + (d - 185 * f) ** 2)
        H = np.where(seg(172, 198), H + np.sqrt(np.clip(1 - (r / (9 * f)) ** 2, 0, 1)) * 0.36, H)
    else:
        # Small leaf tips along the channel.
        pitch = 30 * f
        t = (along % pitch) / pitch
        tip = np.clip(1 - np.abs(t - 0.5) * 2.4 - np.abs(d - 185 * f) / (11 * f), 0, 1)
        H = np.where(seg(172, 198), H + tip * 0.34, H)

    # Cartouches.
    low, high, groove = (Image.new("L", (S, S)) for _ in range(3))
    dl, dh, dg = (ImageDraw.Draw(i) for i in (low, high, groove))
    corner_ornament(corner_style, dl, dh, dg, 104 * f, k)
    centre_ornament(centre_style, dl, dh, dg, S / 2, 104 * f, k)

    def all_sides(image):
        a = np.array(image) > 0
        return a | np.rot90(a, 1) | np.rot90(a, 2) | np.rot90(a, 3)

    low_m, high_m, groove_m = all_sides(low), all_sides(high), all_sides(groove)
    frame = d < fw
    low_m &= frame
    high_m &= frame
    cart_h = np.maximum(relief(low_m, 18 * k) * 0.8, relief(high_m, 10 * k) * 1.05)
    cart_h -= ndimage.gaussian_filter(groove_m.astype(float), 2.0) * 0.18 * (cart_h > 0)

    if band_style != "plain":
        strip = band_strip(band_style, band[1] - band[0], scale)
        in_band = (d >= band[0]) & (d < band[1])
        v = np.clip(d - band[0], 0, strip.shape[0] - 1).astype(int)
        u = along.astype(int) % strip.shape[1]
        band_h = np.where(in_band, strip[v, u], 0)
        band_h = np.where(ndimage.binary_dilation(low_m | high_m, iterations=10), 0, band_h)
        H = H + band_h
    H = np.where(cart_h > 0.01, np.maximum(H, 0.3 + cart_h), H)
    H = ndimage.gaussian_filter(H, 1.3)

    # Lighting.
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

    ramp_list, shine, shine_amount = PALETTES[palette]
    ramp = np.array(ramp_list, float)
    t = np.clip(0.04 + 0.96 * diffuse ** 1.25, 0, 1) * (len(ramp) - 1)
    i = np.clip(t.astype(int), 0, len(ramp) - 2)
    frac = (t - i)[..., None]
    color = (ramp[i] * (1 - frac) + ramp[i + 1] * frac) * ao[..., None]
    color += spec[..., None] * np.array(shine) * shine_amount

    # Age: gilt rubbed thin in patches, grime in the hollows, a fine speckle.
    patches = ndimage.gaussian_filter(rng.random((S, S)), 22)
    patches = (patches - patches.min()) / (patches.max() - patches.min())
    color *= (1 - 0.18 * age + 0.26 * age * patches)[..., None]
    grime = np.clip(cavity * 0.06 * age, 0, 1)[..., None]
    color = color * (1 - grime * 0.6) + np.array([48, 32, 14]) * grime * 0.6
    speckle = ndimage.gaussian_filter(rng.random((S, S)), 1.2)
    color *= (1 - 0.06 * age + 0.12 * age * speckle)[..., None]
    color *= (1 - 0.6 * np.clip(1 - d / 4, 0, 1))[..., None]

    rgba = np.zeros((S, S, 4))
    rgba[..., :3] = np.where(frame[..., None], np.clip(color, 0, 255), 0)
    inside = d - fw
    weight = np.choose(side, [1.0, 0.45, 0.9, 0.55])
    shadow = np.clip(1 - inside / 46, 0, 1) ** 2 * 0.62 * weight
    rgba[..., 3] = np.where(frame, 255, np.where(inside >= 0, shadow * 255, 0))
    return Image.fromarray(rgba.astype(np.uint8), "RGBA").resize((S // 2, S // 2), Image.LANCZOS)


def placeholder(size, inset):
    """Stands in for your photo on the contact sheet."""
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    top, bottom = (58, 46, 38), (22, 17, 14)
    for y in range(size):
        t = y / size
        draw.line([(0, y), (size, y)], fill=tuple(int(top[j] * (1 - t) + bottom[j] * t) for j in range(3)) + (255,))
    c = size / 2
    draw.ellipse([c - size * 0.13, size * 0.3, c + size * 0.13, size * 0.62], fill=(84, 70, 58, 255))
    draw.ellipse([c - size * 0.3, size * 0.66, c + size * 0.3, size * 1.15], fill=(84, 70, 58, 255))
    return image


def gallery(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    tile, label = 380, 46
    cols, rows = 5, 4
    sheet = Image.new("RGB", (cols * tile, rows * (tile + label)), (19, 18, 19))
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", 22)
    for index, option in enumerate(OPTIONS):
        frame = render(option)
        frame.save(os.path.join(out_dir, f"{index + 1:02d}.png"))
        inset = int(frame.width * option[2] / S)
        base = Image.new("RGBA", frame.size, (19, 18, 19, 255))
        photo = placeholder(frame.width - 2 * inset + 8, inset)
        base.alpha_composite(photo, (inset - 4, inset - 4))
        base.alpha_composite(frame)
        small = base.convert("RGB").resize((tile - 24, tile - 24), Image.LANCZOS)
        x, y = (index % cols) * tile, (index // cols) * (tile + label)
        sheet.paste(small, (x + 12, y + 12))
        ImageDraw.Draw(sheet).text((x + tile / 2, y + tile + 10), f"{index + 1}. {option[0]}",
                                   fill=(236, 227, 208), font=font, anchor="mt")
        print("rendered", index + 1, option[0], flush=True)
    sheet.save(os.path.join(out_dir, "sheet.png"))
    print("wrote", os.path.join(out_dir, "sheet.png"))


def write_asset(number):
    option = OPTIONS[number - 1]
    image = render(option)
    os.makedirs(OUT, exist_ok=True)
    image.save(os.path.join(OUT, "frame.png"), optimize=True)
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": "frame.png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, f, indent=2)
    print(f"wrote option {number} ({option[0]}); opening inset {option[2] / S:.4f} of the width "
          f"= {option[2] / S * 300:.2f}pt on the 300pt portrait")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--option", type=int, default=1)
    parser.add_argument("--gallery")
    args = parser.parse_args()
    if args.gallery:
        gallery(args.gallery)
    else:
        write_asset(args.option)
