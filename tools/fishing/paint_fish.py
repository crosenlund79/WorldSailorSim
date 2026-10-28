"""Paints the fish, sharks and junk of Iteration 18 (Real Horizon look).

The style is a natural-history plate in gouache ("visual realism 7/10", see
DEV_GUIDES/ART_DIRECTION.md): each catch is drawn from the side, head to the
left, with believable proportions and fin placement, natural countershading
(a dark back fading through a silvery flank to a pale belly), its own markings,
a fine scale texture, a soft wet sheen along the upper flank and translucent,
rayed fins. Edges come mainly from tone (a darker rim and a lit upper edge);
the only line is a thin, translucent dark blue-grey one. Eyes are small and
realistic: a metallic iris ring, a dark pupil and one small highlight.

Every species is drawn from its own description below (body outline, fins,
tail, colours, markings, eye), so each is recognizable by its real features:
the mackerel's wavy back bars, the cod's barbel, speckles and pale lateral
line, the garfish's beak, the perch's bars and orange lower fins, the bream's
golden brow, the trout's black spots, the tunas' finlets and keels, the
sharks' gill slits and long upper tail lobe, and so on.

For the small animations the game plays (a blink, a tail flick), each fish is
written as layers on one canvas (W x H), so they stack exactly:
    body.png   the fish without its tail, eye open
    tail.png   the tail alone (drawn behind the body; it turns about the
               pivot written to data/fishing/fish_art.json)
    lid.png    the closed eye: shown for a moment to blink
    thumb.png  the whole fish, small and static (lists, trophies)
Junk has only art.png and thumb.png (it does not blink).

Writes assets/fishing/<id>/... and data/fishing/fish_art.json. Original work
for this project (no source images); same licence as the game's own art.

Usage: python3 tools/fishing/paint_fish.py [species_id ...]
Requirements: Python 3 with Pillow and numpy.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "fishing")
META = os.path.join(ROOT, "data", "fishing", "fish_art.json")
W, H = 512, 256      # final canvas, px
SS = 3               # supersampling while painting
THUMB = (128, 64)
LINE = (42, 50, 54)  # the art direction's thin line: dark blue-grey, translucent
INK = LINE           # kept for older call sites: no dark ink any more
SHADOW = (24, 34, 40)
CY = 122             # the fish's middle line


# --- Masks ---------------------------------------------------------------------------

def blank():
    return Image.new("L", (W * SS, H * SS), 0)


def _p(points):
    return [(x * SS, y * SS) for x, y in points]


def poly(points):
    m = blank()
    if len(points) >= 3:
        ImageDraw.Draw(m).polygon(_p(points), fill=255)
    return m


def ell(c, r, angle=0.0, steps=72):
    a = math.radians(angle)
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x, y = r[0] * math.cos(t), r[1] * math.sin(t)
        pts.append((c[0] + x * math.cos(a) - y * math.sin(a), c[1] + x * math.sin(a) + y * math.cos(a)))
    return poly(pts)


def smooth(points, steps=24):
    """A smooth curve through control points (quadratic B-spline style)."""
    if len(points) < 3:
        return list(points)
    out = []
    for i in range(len(points) - 2):
        p0 = ((points[i][0] + points[i + 1][0]) / 2, (points[i][1] + points[i + 1][1]) / 2) if i else points[0]
        p1 = points[i + 1]
        p2 = ((points[i + 1][0] + points[i + 2][0]) / 2, (points[i + 1][1] + points[i + 2][1]) / 2) if i < len(points) - 3 else points[-1]
        for k in range(steps):
            t = k / steps
            out.append(((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
                        (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]))
    out.append(points[-1])
    return out


def tube(points, w0, w1=None):
    w1 = w0 if w1 is None else w1
    curve = smooth(points) if len(points) > 2 else points
    if len(curve) == 2:
        (x0, y0), (x1, y1) = curve
        n = max(int(math.hypot(x1 - x0, y1 - y0) / 1.5), 2)
        curve = [(x0 + (x1 - x0) * k / n, y0 + (y1 - y0) * k / n) for k in range(n + 1)]
    m = blank()
    d = ImageDraw.Draw(m)
    for i, (x, y) in enumerate(curve):
        w = (w0 + (w1 - w0) * i / max(len(curve) - 1, 1)) / 2
        d.ellipse([(x - w) * SS, (y - w) * SS, (x + w) * SS, (y + w) * SS], fill=255)
    return m


def union(*masks):
    out = blank()
    for m in masks:
        out = ImageChops.lighter(out, m)
    return out


def minus(a, b):
    return ImageChops.subtract(a, b)


def clip(a, b):
    return ImageChops.multiply(a, b)


def soft(m, r):
    return m.filter(ImageFilter.GaussianBlur(SS * r))


def erode(m, px):
    return m.filter(ImageFilter.MinFilter(max(3, int(px * SS) | 1)))


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def smoothstep(e0, e1, x):
    """0 at e0, 1 at e1 (either order), smooth between."""
    d = e1 - e0
    if abs(d) < 1e-6:
        d = 1e-6
    t = np.clip((x - e0) / d, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def arr(mask):
    return np.asarray(mask, dtype=np.float32) / 255.0


def _noise(rng, cells, size):
    n = rng.normal(0.0, 1.0, (max(int(size[1] / cells), 2), max(int(size[0] / cells), 2))).astype(np.float32)
    img = Image.fromarray(((n * 40) + 128).clip(0, 255).astype(np.uint8)).resize(size, Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 128.0 - 1.0


# --- The painter -------------------------------------------------------------------------

class Painter:
    def __init__(self, seed=7):
        self.img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
        self.silhouette = blank()
        rng = np.random.default_rng(seed)
        size = (W * SS, H * SS)
        self.grain = _noise(rng, 3, size)        # fine paper/paint grain
        self.mottle = _noise(rng, 30, size)      # slow gouache unevenness
        self.yy, self.xx = np.mgrid[0:H * SS, 0:W * SS].astype(np.float32)

    def put(self, rgb, alpha):
        """Composites an RGB float array with an alpha array (0..1)."""
        a = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
        layer = Image.fromarray(np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), a]), "RGBA")
        self.img.alpha_composite(layer)

    def wash(self, mask, top, bottom=None, y0=None, y1=None, outline=True, ink_w=1.0, alpha=1.0, sheen=0.06,
             axis="y", fade=None, rim=0.16, line_alpha=95):
        """A gouache wash in `mask`: a gradient from `top` to `bottom` (down the
        shape, or along it with axis="x"), lit from the upper left, darker
        towards its rim, with a little grain and unevenness, and a thin
        translucent blue-grey line at its edge. `fade` (0..1 array) scales the
        alpha (translucent fins)."""
        box = mask.getbbox()
        if not box:
            return
        bottom = top if bottom is None else bottom
        if axis == "y":
            a0 = box[1] if y0 is None else y0 * SS
            a1 = box[3] if y1 is None else y1 * SS
            t = ((self.yy - a0) / max(a1 - a0, 1)).clip(0, 1)
        else:
            a0 = box[0] if y0 is None else y0 * SS
            a1 = box[2] if y1 is None else y1 * SS
            t = ((self.xx - a0) / max(a1 - a0, 1)).clip(0, 1)
        a = np.array(top, dtype=np.float32)
        b = np.array(bottom, dtype=np.float32)
        rgb = a[None, None, :] + (b - a)[None, None, :] * t[:, :, None]
        m = arr(mask)
        inner = arr(soft(mask, 2.5))
        light = 1.0 + sheen * (1.0 - t) - rim * (1.0 - inner) + self.grain * 0.03 + self.mottle * 0.03
        rgb = rgb * light[:, :, None]
        al = m * alpha
        if fade is not None:
            al = al * fade
        self.put(rgb, al)
        self.silhouette = union(self.silhouette, mask)
        if outline:
            self.outline(mask, ink_w, LINE, line_alpha)

    def outline(self, mask, width=1.0, colour=LINE, alpha=95):
        inner = erode(mask, width)
        ring = soft(minus(mask, inner), 0.3)
        self.ink(ring, colour, alpha)

    def ink(self, mask, colour=LINE, alpha=200):
        a = (np.array(mask, dtype=np.float32) * alpha / 255.0).astype(np.uint8)
        layer = Image.new("RGBA", self.img.size, tuple(colour) + (0,))
        layer.putalpha(Image.fromarray(a))
        self.img.alpha_composite(layer)

    def tint(self, alpha_arr, colour):
        rgb = np.broadcast_to(np.array(colour, dtype=np.float32), alpha_arr.shape + (3,))
        self.put(rgb, alpha_arr)

    def line(self, points, width, colour=LINE, alpha=150):
        self.ink(tube(points, width), colour, alpha)

    def dot(self, c, r, colour, alpha=255):
        self.ink(ell(c, (r, r)), colour, alpha)

    def colour_at(self, x, y, r=3):
        """The painted colour around a point (for the eyelid)."""
        box = (int((x - r) * SS), int((y - r) * SS), int((x + r) * SS), int((y + r) * SS))
        a = np.array(self.img.crop(box), dtype=np.float32)
        w = a[:, :, 3:4] / 255.0
        return tuple(int(v) for v in (a[:, :, :3] * w).sum((0, 1)) / max(w.sum(), 1e-6))

    def image(self, shadow=True):
        out = self.img
        if shadow:
            sh_mask = soft(self.silhouette, 5)
            sh_mask = ImageChops.offset(sh_mask, 3 * SS, 6 * SS)
            sh = Image.new("RGBA", self.img.size, SHADOW + (0,))
            sh.putalpha(sh_mask.point(lambda v: int(v * 0.2)))
            out = Image.alpha_composite(sh, self.img)
        return out.resize((W, H), Image.LANCZOS)


# --- The fish's shape --------------------------------------------------------------------

class Shape:
    """A fish body between the snout (x0) and the tail's root (x1): smooth top
    and bottom outlines from control points (t along the body, y from CY)."""

    def __init__(self, spec):
        self.x0, self.x1 = spec["x0"], spec["x1"]
        self.top = smooth([(self.x(t), CY + y) for t, y in spec["top"]], 30)
        self.bot = smooth([(self.x(t), CY + y) for t, y in spec["bot"]], 30)

    def x(self, t):
        return self.x0 + (self.x1 - self.x0) * t

    @staticmethod
    def _at(curve, x):
        for (ax, ay), (bx, by) in zip(curve, curve[1:]):
            if ax <= x <= bx or bx <= x <= ax:
                return ay + (by - ay) * ((x - ax) / (bx - ax) if bx != ax else 0)
        return curve[-1][1] if x > curve[-1][0] else curve[0][1]

    def top_at(self, t):
        return self._at(self.top, self.x(t))

    def bot_at(self, t):
        return self._at(self.bot, self.x(t))

    def mid_at(self, t):
        return (self.top_at(t) + self.bot_at(t)) / 2

    def mask(self):
        return poly(self.top + list(reversed(self.bot)))

    def root(self):
        """The tail's root (pivot) and half its height."""
        return (self.x1, (self.top[-1][1] + self.bot[-1][1]) / 2), abs(self.bot[-1][1] - self.top[-1][1]) / 2

    def columns(self):
        """Per canvas column (supersampled): the top and bottom outline, px."""
        xs = (np.arange(W * SS, dtype=np.float32) + 0.5) / SS
        tx, ty = zip(*self.top)
        bx, by = zip(*self.bot)
        return np.interp(xs, tx, ty), np.interp(xs, bx, by), xs


def fin_on(shape, edge, t0, t1, height, kind="soft", sweep=0.35, rays=0):
    """A fin along the top or bottom edge between t0 and t1 (height in px,
    outward; sweep leans it toward the tail). Kinds: soft (rounded), spiny
    (a row of points), tri (triangular), long (a low ribbon)."""
    sign = -1 if edge == "top" else 1
    at = shape.top_at if edge == "top" else shape.bot_at
    base = [(shape.x(t0 + (t1 - t0) * k / 12), at(t0 + (t1 - t0) * k / 12)) for k in range(13)]
    length = shape.x(t1) - shape.x(t0)
    out = []
    if kind == "spiny":
        n = max(rays, 5)
        for k in range(n + 1):
            f = k / n
            x = shape.x(t0 + (t1 - t0) * f)
            hgt = height * (0.55 + 0.45 * math.sin(math.pi * min(f * 1.4, 1.0) / 1.0 * 0.9 + 0.2))
            out.append((x + length * sweep * 0.25, at(t0 + (t1 - t0) * f) + sign * hgt))
            if k < n:
                xm = shape.x(t0 + (t1 - t0) * (f + 0.5 / n))
                out.append((xm + length * sweep * 0.2, at(t0 + (t1 - t0) * (f + 0.5 / n)) + sign * hgt * 0.7))
    elif kind == "tri":
        out = [(shape.x(t0) + length * (0.35 + sweep), at(t0) + sign * height), (shape.x(t1) + length * sweep * 0.5, at(t1) + sign * height * 0.18)]
    elif kind == "long":
        for k in range(13):
            f = k / 12
            out.append((shape.x(t0 + (t1 - t0) * f) + length * 0.03, at(t0 + (t1 - t0) * f) + sign * height * (0.8 + 0.2 * math.sin(f * math.pi))))
    else:  # soft, rounded
        for k in range(13):
            f = k / 12
            hgt = height * math.sin(math.pi * (0.15 + 0.85 * f)) ** 0.7
            out.append((shape.x(t0 + (t1 - t0) * f) + length * sweep * f, at(t0 + (t1 - t0) * f) + sign * hgt))
    return poly(base + list(reversed(out)))


def pectoral(shape, t, length, droop=25, width=0.42):
    """A side fin behind the gill, lying along the body."""
    x = shape.x(t)
    y = shape.mid_at(t) + (shape.bot_at(t) - shape.mid_at(t)) * 0.35
    a = math.radians(droop)
    tip = (x + length * math.cos(a), y + length * math.sin(a))
    w = length * width
    return poly(smooth([(x, y - w * 0.35), ((x + tip[0]) / 2, (y + tip[1]) / 2 - w * 0.45), tip,
                        ((x + tip[0]) / 2 - w * 0.1, (y + tip[1]) / 2 + w * 0.35), (x, y + w * 0.3)], 12))


def tail_mask(root, half, kind, length, spread):
    """The tail fin from its root. Kinds: fork, deepfork, square, round,
    notch (slightly forked), shark (long upper lobe), plaice (fan)."""
    x, y = root
    h = half
    if kind == "fork":
        pts = smooth([(x - 10, y - h), (x + length * 0.55, y - spread * 0.75), (x + length, y - spread), (x + length * 0.82, y - spread * 0.55),
                      (x + length * 0.38, y), (x + length * 0.82, y + spread * 0.55), (x + length, y + spread), (x + length * 0.55, y + spread * 0.75),
                      (x - 10, y + h)], 6)
    elif kind == "deepfork":
        pts = smooth([(x - 10, y - h), (x + length * 0.45, y - spread * 0.7), (x + length, y - spread * 1.05), (x + length * 0.7, y - spread * 0.45),
                      (x + length * 0.2, y), (x + length * 0.7, y + spread * 0.45), (x + length, y + spread * 1.05), (x + length * 0.45, y + spread * 0.7),
                      (x - 10, y + h)], 6)
    elif kind == "square":
        pts = smooth([(x - 10, y - h), (x + length * 0.6, y - spread * 0.85), (x + length, y - spread), (x + length * 0.97, y),
                      (x + length, y + spread), (x + length * 0.6, y + spread * 0.85), (x - 10, y + h)], 6)
    elif kind == "notch":
        pts = smooth([(x - 10, y - h), (x + length * 0.6, y - spread * 0.8), (x + length, y - spread), (x + length * 0.85, y),
                      (x + length, y + spread), (x + length * 0.6, y + spread * 0.8), (x - 10, y + h)], 6)
    elif kind == "round" or kind == "plaice":
        pts = smooth([(x - 10, y - h), (x + length * 0.5, y - spread), (x + length, y - spread * 0.55), (x + length * 1.05, y),
                      (x + length, y + spread * 0.55), (x + length * 0.5, y + spread), (x - 10, y + h)], 14)
    else:  # shark: long upper lobe, short lower one
        pts = smooth([(x - 12, y - h), (x + length * 0.55, y - spread * 1.1), (x + length, y - spread * 1.55), (x + length * 0.82, y - spread * 0.9),
                      (x + length * 0.45, y - spread * 0.05), (x + length * 0.42, y + spread * 0.55), (x + length * 0.2, y + spread * 0.25),
                      (x - 12, y + h)], 6)
    return poly(pts)


# --- Species -------------------------------------------------------------------------------

# Geometry (x0, x1, top, bot, tail, fins, eye) is unchanged from the first
# painting, so the tail pivots and eyes in fish_art.json stay where they were.
# Colours: back (top), flank (the silvery middle), belly; fin (dorsal and side
# fins), fin_lower (anal and pelvic, if different), tail_col; markings.
SPECIES = {
    "herring": dict(
        x0=70, x1=390, top=[(0, 2), (0.06, -18), (0.25, -36), (0.5, -38), (0.8, -24), (1, -11)],
        bot=[(0, 2), (0.08, 18), (0.3, 34), (0.6, 32), (0.85, 18), (1, 11)],
        back=(50, 80, 100), flank=(156, 174, 182), belly=(226, 230, 228), fin=(168, 178, 180), tail_col=(104, 124, 134),
        tail=("deepfork", 92, 52), dorsal=[("top", 0.42, 0.6, 30, "soft")], anal=[("bot", 0.72, 0.86, 14, "soft")],
        pelvic=("bot", 0.46, 0.54, 12), pectoral=(0.2, 38), eye=(0.11, -4, 13), scales=0.75,
        marks=["sheen_band"], mouth="up", iris=(196, 192, 176)),
    "mackerel": dict(
        x0=60, x1=388, top=[(0, 3), (0.06, -16), (0.25, -32), (0.5, -36), (0.8, -22), (1, -8)],
        bot=[(0, 3), (0.08, 16), (0.3, 30), (0.6, 30), (0.85, 16), (1, 8)],
        back=(42, 96, 94), flank=(160, 180, 176), belly=(230, 232, 226), fin=(124, 138, 132), tail_col=(58, 86, 86),
        tail=("deepfork", 88, 50), dorsal=[("top", 0.32, 0.46, 30, "spiny"), ("top", 0.58, 0.7, 20, "soft")],
        anal=[("bot", 0.6, 0.72, 16, "soft")], pelvic=("bot", 0.25, 0.31, 10), finlets=(0.73, 0.98, 5), pectoral=(0.2, 34),
        eye=(0.1, -3, 12), scales=0.25, marks=["mackerel_waves", "iridescence"], mouth="flat", iris=(190, 186, 170)),
    "flatfish": dict(
        x0=74, x1=372, top=[(0, 10), (0.05, -16), (0.2, -50), (0.5, -62), (0.8, -44), (1, -12)],
        bot=[(0, 12), (0.06, 26), (0.22, 54), (0.5, 64), (0.8, 46), (1, 12)],
        back=(122, 104, 78), flank=(130, 110, 82), belly=(112, 94, 70), fin=(130, 110, 82), tail_col=(122, 102, 76),
        tail=("plaice", 64, 44), dorsal=[("top", 0.1, 0.94, 18, "long")], anal=[("bot", 0.18, 0.94, 18, "long")],
        pectoral=(0.24, 0), eye=(0.13, -26, 10), second_eye=(0.2, -36, 9), scales=0.0, marks=["plaice_spots", "mottle"],
        mouth="flat", fin_rays=True, flat=True, iris=(176, 160, 120)),
    "cod": dict(
        x0=66, x1=384, top=[(0, 6), (0.06, -22), (0.22, -44), (0.45, -46), (0.75, -30), (1, -14)],
        bot=[(0, 8), (0.08, 26), (0.3, 46), (0.6, 40), (0.85, 22), (1, 14)],
        back=(98, 94, 66), flank=(160, 150, 112), belly=(222, 214, 192), fin=(118, 110, 80), tail_col=(104, 98, 68),
        tail=("square", 78, 46), dorsal=[("top", 0.26, 0.42, 30, "soft"), ("top", 0.47, 0.64, 28, "soft"), ("top", 0.68, 0.86, 24, "soft")],
        anal=[("bot", 0.48, 0.64, 22, "soft"), ("bot", 0.68, 0.86, 20, "soft")], pelvic=("bot", 0.15, 0.2, 16),
        pectoral=(0.22, 40), eye=(0.12, -10, 12), scales=0.2, marks=["speckles", "lateral_pale"], mouth="down", barbel=True,
        iris=(170, 160, 120)),
    "perch": dict(
        x0=72, x1=380, top=[(0, 6), (0.06, -22), (0.22, -52), (0.45, -58), (0.75, -34), (1, -14)],
        bot=[(0, 8), (0.08, 24), (0.3, 44), (0.6, 40), (0.85, 22), (1, 14)],
        back=(66, 84, 48), flank=(146, 150, 90), belly=(226, 220, 184), fin=(118, 120, 92), fin_lower=(196, 110, 66),
        tail_col=(166, 112, 72), tail=("notch", 80, 46), dorsal=[("top", 0.24, 0.5, 40, "spiny", 9), ("top", 0.56, 0.74, 28, "soft")],
        anal=[("bot", 0.62, 0.76, 22, "soft")], pelvic=("bot", 0.3, 0.38, 22), pectoral=(0.22, 34),
        eye=(0.12, -10, 13), scales=0.8, marks=["perch_bars"], mouth="flat", dorsal_spot=True, iris=(196, 168, 92)),
    "garfish": dict(
        x0=30, x1=420, top=[(0, 4), (0.03, 1), (0.16, -6), (0.24, -15), (0.5, -18), (0.85, -14), (1, -7)],
        bot=[(0, 6), (0.03, 7), (0.16, 8), (0.24, 14), (0.5, 17), (0.85, 13), (1, 7)],
        back=(36, 80, 82), flank=(150, 174, 168), belly=(228, 232, 224), fin=(100, 124, 118), tail_col=(56, 92, 88),
        tail=("fork", 54, 32), dorsal=[("top", 0.8, 0.94, 18, "soft")], anal=[("bot", 0.78, 0.92, 16, "soft")],
        pelvic=("bot", 0.58, 0.63, 9), pectoral=(0.27, 22), eye=(0.205, -2, 9), scales=0.15, marks=["gar_band"], mouth="beak",
        iris=(196, 196, 180)),
    "gilthead_bream": dict(
        x0=74, x1=376, top=[(0, 8), (0.05, -16), (0.18, -50), (0.42, -64), (0.75, -38), (1, -12)],
        bot=[(0, 10), (0.08, 28), (0.3, 50), (0.6, 46), (0.85, 24), (1, 12)],
        back=(92, 106, 118), flank=(180, 186, 188), belly=(232, 232, 226), fin=(146, 152, 156), tail_col=(112, 120, 128),
        tail=("fork", 82, 52), dorsal=[("top", 0.24, 0.84, 30, "spiny", 11)], anal=[("bot", 0.62, 0.84, 22, "soft")],
        pelvic=("bot", 0.3, 0.38, 16), pectoral=(0.24, 40), eye=(0.13, -12, 12), scales=0.8,
        marks=["gold_brow", "gill_spot", "faint_lines"], mouth="flat", iris=(196, 186, 150)),
    "sea_trout": dict(
        x0=66, x1=386, top=[(0, 4), (0.06, -20), (0.25, -40), (0.5, -42), (0.8, -26), (1, -13)],
        bot=[(0, 6), (0.08, 20), (0.3, 38), (0.6, 36), (0.85, 20), (1, 13)],
        back=(64, 80, 90), flank=(176, 182, 182), belly=(234, 232, 224), fin=(140, 146, 148), tail_col=(98, 108, 114),
        tail=("square", 80, 48), dorsal=[("top", 0.38, 0.54, 32, "soft")], adipose=(0.8, 0.86),
        anal=[("bot", 0.66, 0.78, 20, "soft")], pelvic=("bot", 0.46, 0.54, 14), pectoral=(0.2, 34), eye=(0.11, -6, 12),
        scales=0.3, marks=["trout_spots", "lateral_faint"], mouth="flat", iris=(188, 180, 150)),
    "sea_bass": dict(
        x0=66, x1=386, top=[(0, 6), (0.06, -20), (0.25, -42), (0.5, -44), (0.8, -26), (1, -12)],
        bot=[(0, 8), (0.08, 22), (0.3, 40), (0.6, 38), (0.85, 20), (1, 12)],
        back=(76, 90, 100), flank=(172, 180, 182), belly=(234, 234, 228), fin=(132, 140, 146), tail_col=(100, 110, 118),
        tail=("notch", 80, 48), dorsal=[("top", 0.3, 0.48, 36, "spiny", 8), ("top", 0.54, 0.7, 26, "soft")],
        anal=[("bot", 0.62, 0.74, 20, "soft")], pelvic=("bot", 0.3, 0.38, 16), pectoral=(0.22, 36), eye=(0.11, -8, 12),
        scales=0.8, marks=["gill_spot", "lateral_dark"], mouth="flat", iris=(190, 186, 170)),
    "bonito": dict(
        x0=62, x1=388, top=[(0, 4), (0.06, -20), (0.25, -42), (0.5, -44), (0.8, -24), (1, -7)],
        bot=[(0, 4), (0.08, 20), (0.3, 38), (0.6, 38), (0.85, 18), (1, 7)],
        back=(38, 56, 84), flank=(154, 164, 174), belly=(228, 230, 230), fin=(78, 90, 110), tail_col=(46, 62, 88),
        tail=("deepfork", 96, 62), dorsal=[("top", 0.26, 0.5, 32, "spiny", 9), ("top", 0.58, 0.66, 20, "tri")],
        anal=[("bot", 0.6, 0.68, 18, "tri")], pelvic=("bot", 0.22, 0.27, 12), finlets=(0.7, 0.98, 6), pectoral=(0.22, 30),
        eye=(0.1, -6, 12), scales=0.0, marks=["bonito_stripes"], mouth="flat", keel=True, iris=(180, 176, 160)),
    "mahi_mahi": dict(
        x0=70, x1=384, top=[(0, 0), (0.02, -40), (0.08, -54), (0.3, -50), (0.6, -38), (0.85, -22), (1, -10)],
        bot=[(0, 4), (0.08, 26), (0.3, 36), (0.6, 30), (0.85, 18), (1, 10)],
        back=(42, 104, 92), flank=(150, 160, 84), belly=(218, 198, 104), fin=(46, 92, 112), fin_lower=(176, 168, 92),
        tail_col=(186, 170, 92), tail=("deepfork", 96, 60), dorsal=[("top", 0.06, 0.96, 17, "long")], anal=[("bot", 0.5, 0.95, 13, "long")],
        pectoral=(0.2, 30), eye=(0.12, -10, 11), scales=0.0, marks=["mahi_dots"], mouth="flat", fin_rays=True,
        pectoral_col=(170, 166, 96), iris=(170, 160, 110)),
    "skipjack": dict(
        x0=62, x1=388, top=[(0, 4), (0.06, -22), (0.25, -46), (0.5, -48), (0.8, -26), (1, -7)],
        bot=[(0, 4), (0.08, 22), (0.3, 42), (0.6, 42), (0.85, 20), (1, 7)],
        back=(32, 44, 70), flank=(150, 158, 170), belly=(226, 228, 230), fin=(60, 72, 96), tail_col=(40, 52, 78),
        tail=("deepfork", 98, 64), dorsal=[("top", 0.26, 0.46, 34, "spiny", 9), ("top", 0.56, 0.64, 22, "tri")],
        anal=[("bot", 0.6, 0.68, 20, "tri")], pelvic=("bot", 0.22, 0.27, 12), finlets=(0.7, 0.98, 6), pectoral=(0.22, 30),
        eye=(0.1, -6, 12), scales=0.0, marks=["skipjack_stripes"], mouth="flat", keel=True, iris=(176, 172, 160)),
    "snapper": dict(
        x0=56, x1=382, top=[(0, 6), (0.04, -6), (0.12, -30), (0.24, -56), (0.42, -64), (0.72, -36), (1, -12)],
        bot=[(0, 10), (0.1, 18), (0.34, 38), (0.62, 36), (0.86, 20), (1, 12)],
        back=(168, 74, 68), flank=(206, 132, 116), belly=(232, 204, 190), fin=(190, 108, 96), tail_col=(176, 88, 80),
        tail=("notch", 82, 50), dorsal=[("top", 0.22, 0.5, 36, "spiny", 10), ("top", 0.54, 0.76, 28, "soft")],
        anal=[("bot", 0.62, 0.78, 24, "soft")], pelvic=("bot", 0.3, 0.38, 18), pectoral=(0.22, 38), eye=(0.12, -12, 13),
        scales=0.8, marks=[], mouth="flat", iris=(178, 74, 62)),
    "yellowfin": dict(
        x0=60, x1=388, top=[(0, 4), (0.06, -22), (0.25, -48), (0.5, -50), (0.8, -26), (1, -7)],
        bot=[(0, 4), (0.08, 22), (0.3, 44), (0.6, 44), (0.85, 20), (1, 7)],
        back=(30, 40, 66), flank=(152, 158, 168), belly=(224, 226, 230), fin=(70, 80, 100), tail_col=(44, 54, 80),
        tail=("deepfork", 104, 70), dorsal=[("top", 0.26, 0.44, 34, "spiny", 9), ("top", 0.52, 0.62, 70, "tri", 0, 0.9)],
        anal=[("bot", 0.54, 0.64, 66, "tri", 0, 0.9)], pelvic=("bot", 0.22, 0.27, 14), finlets=(0.68, 0.98, 7), pectoral=(0.2, 58),
        eye=(0.1, -6, 12), scales=0.0, marks=["yellow_band", "belly_dashes"], mouth="flat", keel=True,
        finlet_col=(214, 182, 72), iris=(180, 176, 160)),
    "blue_shark": dict(
        x0=24, x1=392, top=[(0, 10), (0.05, -4), (0.16, -24), (0.36, -34), (0.65, -24), (0.9, -12), (1, -8)],
        bot=[(0, 12), (0.06, 18), (0.2, 26), (0.45, 30), (0.75, 18), (0.9, 10), (1, 8)],
        back=(40, 58, 96), flank=(72, 98, 142), belly=(230, 232, 232), fin=(54, 74, 116), tail_col=(48, 66, 106),
        tail=("shark", 110, 46), dorsal=[("top", 0.38, 0.52, 42, "tri", 0, 0.2), ("top", 0.82, 0.86, 10, "tri")],
        anal=[("bot", 0.82, 0.86, 10, "tri")], pelvic=("bot", 0.6, 0.66, 12), pectoral=(0.22, 86, 32, 0.3), eye=(0.1, -2, 8),
        scales=0.0, marks=["gills"], mouth="shark", shark=True, countershade=True, iris=(70, 74, 70)),
    "blacktip_reef_shark": dict(
        x0=40, x1=390, top=[(0, 10), (0.05, -6), (0.16, -28), (0.38, -38), (0.65, -26), (0.9, -12), (1, -8)],
        bot=[(0, 12), (0.06, 20), (0.2, 30), (0.45, 32), (0.75, 20), (0.9, 10), (1, 8)],
        back=(112, 106, 96), flank=(146, 140, 128), belly=(232, 230, 224), fin=(118, 112, 102), tail_col=(112, 106, 96),
        tail=("shark", 100, 46), dorsal=[("top", 0.36, 0.52, 46, "tri", 0, 0.15), ("top", 0.8, 0.85, 12, "tri")],
        anal=[("bot", 0.8, 0.85, 12, "tri")], pelvic=("bot", 0.6, 0.66, 13), pectoral=(0.22, 62, 32, 0.34), eye=(0.1, -2, 8),
        scales=0.0, marks=["gills", "flank_band"], mouth="shark", shark=True, countershade=True, black_tips=True,
        iris=(120, 116, 90)),
}

JUNK = ["old_boot", "tangled_rope", "rusty_tin"]
TIP = (36, 36, 38)


# --- Painting a fish ----------------------------------------------------------------------

def near(mask, r):
    """1 on and near `mask`, falling to 0 about r px away (fin translucency)."""
    return arr(soft(mask, r)).clip(0, 0.5) * 2.0


def fin_rays(p, m, origin_pts, tip_pts, colour, alpha=70, width=0.9):
    for (x0, y0), (x1, y1) in zip(origin_pts, tip_pts):
        p.ink(clip(tube([(x0, y0), (x1, y1)], width, width * 0.5), m), colour, alpha)


def paint_fins(p, shape, spec, which, body):
    masks = []
    close = near(body, 14)
    for entry in spec.get(which, []):
        edge_name, t0, t1, height, kind = entry[:5]
        rays = entry[5] if len(entry) > 5 else 0
        sweep = entry[6] if len(entry) > 6 else 0.35
        m = fin_on(shape, edge_name, t0, t1, height, kind, sweep, rays)
        m = minus(m, body)
        colour = spec["fin"] if edge_name == "top" else spec.get("fin_lower", spec["fin"])
        if spec.get("finlet_col") and kind == "tri" and height > 40:
            colour = spec["finlet_col"]
        if spec.get("shark"):
            fade = 1.0
            p.wash(m, mix(colour, spec["back"], 0.4), mix(colour, (220, 222, 220), 0.12), rim=0.2, line_alpha=90)
        else:
            fade = 0.62 + 0.33 * close
            outer = mix(colour, (232, 230, 222), 0.22)
            if edge_name == "top":
                p.wash(m, outer, mix(colour, LINE, 0.08), fade=fade, rim=0.08, line_alpha=70)
            else:
                p.wash(m, mix(colour, LINE, 0.08), outer, fade=fade, rim=0.08, line_alpha=70)
        box = m.getbbox()
        if spec.get("black_tips") and box:
            tip_y = (box[1] if edge_name == "top" else box[3]) / SS
            depth = (box[3] - box[1]) / SS * 0.3
            yy = (p.yy / SS)
            g = smoothstep(tip_y + depth, tip_y + depth * 0.3, yy) if edge_name == "top" else smoothstep(tip_y - depth, tip_y - depth * 0.3, yy)
            p.tint(arr(m) * g * 0.9, TIP)
        if spec.get("dorsal_spot") and kind == "spiny" and box:
            spot = clip(soft(ell((shape.x(t1) - 12, shape.top_at(t1) - height * 0.32), (9, 8)), 2.5), m)
            p.ink(spot, (40, 42, 34), 170)
        if box and (spec.get("fin_rays") or kind in ("spiny", "soft", "long")):
            n = max(rays, 6) if kind == "spiny" else max(6, int((box[2] - box[0]) / SS / 7))
            base_pts, tip_pts = [], []
            for k in range(n + 1 if kind == "spiny" else n):
                f = k / n if kind == "spiny" else (k + 0.5) / n
                t = t0 + (t1 - t0) * f
                x = shape.x(t)
                y_in = shape.top_at(t) if edge_name == "top" else shape.bot_at(t)
                y_out = box[1] / SS - 2 if edge_name == "top" else box[3] / SS + 2
                base_pts.append((x, y_in))
                tip_pts.append((x + (box[2] - box[0]) / SS * sweep * 0.22 + 3, y_out))
            dark = mix(colour, LINE, 0.55)
            fin_rays(p, m, base_pts, tip_pts, dark, 120 if kind == "spiny" else 70, 1.3 if kind == "spiny" else 0.9)
        masks.append(m)
    return masks


def body_colour(p, shape, spec, body):
    """The body: countershading per column (dark back, silvery flank, pale
    belly), rounded shading, rim darkening, the wet sheen along the upper
    flank and a little gouache unevenness."""
    top, bot, xs = shape.columns()
    yy = (p.yy + 0.5) / SS
    v = ((yy - top[None, :]) / np.maximum(bot - top, 1.0)[None, :]).clip(0, 1)
    xt = ((xs - shape.x0) / (shape.x1 - shape.x0)).clip(0, 1)[None, :]
    back = np.array(spec["back"], np.float32)
    flank = np.array(spec.get("flank", mix(spec["back"], spec["belly"], 0.5)), np.float32)
    belly = np.array(spec["belly"], np.float32)
    if spec.get("countershade"):
        s1 = smoothstep(0.12, 0.42, v)
        s2 = smoothstep(0.5, 0.58, v + 0.03 * np.sin(xt * 9.0))
    elif spec.get("flat"):
        s1 = smoothstep(0.2, 0.6, v) * 0.5
        s2 = smoothstep(0.6, 1.0, v) * 0.6
    else:
        s1 = smoothstep(0.1, 0.5, v)
        s2 = smoothstep(0.48, 0.82, v)
    rgb = back + (flank - back) * s1[..., None]
    rgb = rgb + (belly - rgb) * s2[..., None]
    nv = v * 2.0 - 1.0
    lam = np.sqrt(np.clip(1.0 - nv * nv, 0, 1))
    light = 0.8 + 0.2 * lam - 0.05 * nv + 0.05 * (1.0 - xt)
    if spec.get("flat"):
        light = 0.9 + 0.1 * lam + 0.04 * (1.0 - xt)
    inner = arr(soft(body, 4))
    light = light - 0.16 * (1.0 - inner) + p.grain * 0.025 + p.mottle * 0.035
    rgb = rgb * light[..., None]
    # Wet sheen: a broken soft highlight along the upper flank.
    if not spec.get("flat"):
        fade_x = smoothstep(0.02, 0.18, xt) * smoothstep(1.0, 0.7, xt)
        g = np.exp(-((v - 0.3) / 0.075) ** 2) * fade_x * (0.75 + 0.5 * p.mottle).clip(0.3, 1.2)
        strength = 0.12 if spec.get("shark") else 0.22
        rgb = rgb + (np.array([244, 246, 244], np.float32) - rgb) * (g * strength)[..., None]
    p.put(rgb, arr(body))
    p.silhouette = union(p.silhouette, body)


_SCALES = {}


def scale_pattern(step):
    """Overlapping scale arcs (dark edge, and a lighter edge just below)."""
    if step not in _SCALES:
        dark, lite = blank(), blank()
        dd, dl = ImageDraw.Draw(dark), ImageDraw.Draw(lite)
        r = step * SS * 0.62
        for row in range(0, int(H / (step * 0.62)) + 3):
            for col in range(0, W // step + 2):
                cx = (col * step + (step / 2 if row % 2 else 0)) * SS
                cy = row * step * 0.62 * SS
                dd.arc([cx - r, cy - r, cx + r, cy + r], 25, 155, fill=255, width=max(1, SS // 2 + 1))
                dl.arc([cx - r, cy - r + SS, cx + r, cy + r + SS], 40, 140, fill=255, width=max(1, SS // 2))
        _SCALES[step] = (soft(dark, 0.25), soft(lite, 0.25))
    return _SCALES[step]


def paint_body(p, shape, spec):
    body = shape.mask()
    body_colour(p, shape, spec, body)
    amount = spec.get("scales", 0)
    if amount > 0:
        dark, lite = scale_pattern(6 if amount < 0.5 else 7)
        inner = soft(erode(body, 5), 3)
        top, bot, _ = shape.columns()
        v = (((p.yy + 0.5) / SS - top[None, :]) / np.maximum(bot - top, 1.0)[None, :]).clip(0, 1)
        # Scales read on the back and flank; the belly is smoother.
        weight = arr(inner) * (1.0 - 0.6 * smoothstep(0.55, 0.95, v)) * amount
        p.tint(arr(dark) * weight * 0.32, mix(spec["back"], LINE, 0.55))
        p.tint(arr(lite) * weight * 0.22, (236, 238, 234))
    elif spec.get("shark"):
        # Smooth skin: only a faint fine texture.
        p.tint(arr(erode(body, 3)) * np.clip(p.grain, 0, 1) * 0.08, LINE)
    return body


def paint_marks(p, shape, spec, body):
    marks = spec.get("marks", [])
    inner = soft(erode(body, 3), 1.2)
    rng = np.random.default_rng(len(spec["back"]) * 31 + int(spec["x1"]))
    if "mackerel_waves" in marks:
        for k in range(17):
            t = 0.19 + k * 0.047
            x = shape.x(t)
            y_top = shape.top_at(t)
            y_mid = shape.mid_at(t) - 1
            j = rng.uniform(-2, 2)
            m = tube([(x - 3 + j, y_top + 1), (x + 5, y_top + (y_mid - y_top) * 0.35), (x - 3, y_top + (y_mid - y_top) * 0.7),
                      (x + 3 + j, y_mid)], 3.0, 1.4)
            p.ink(clip(soft(m, 0.5), inner), (22, 38, 40), 205)
        # the faint dark wavy line along the flank of the Atlantic mackerel
        p.ink(clip(soft(tube([(shape.x(t / 20), shape.mid_at(t / 20) + 3 + 2 * math.sin(t)) for t in range(5, 19)], 1.4), 0.6), inner),
              (60, 80, 84), 60)
    if "iridescence" in marks:
        top, bot, xs = shape.columns()
        v = (((p.yy + 0.5) / SS - top[None, :]) / np.maximum(bot - top, 1.0)[None, :])
        g = np.exp(-((v - 0.5) / 0.1) ** 2) * arr(inner)
        p.tint(g * 0.22, (150, 176, 196))
    if "sheen_band" in marks:
        top, bot, xs = shape.columns()
        v = (((p.yy + 0.5) / SS - top[None, :]) / np.maximum(bot - top, 1.0)[None, :])
        g = np.exp(-((v - 0.42) / 0.07) ** 2) * arr(inner)
        p.tint(g * 0.3, (176, 196, 210))
    if "mottle" in marks:
        g = (p.mottle.clip(0.15, 1.0) - 0.15) * arr(inner)
        p.tint(g * 0.5, (86, 70, 50))
        g2 = ((-p.mottle).clip(0.3, 1.0) - 0.3) * arr(inner)
        p.tint(g2 * 0.4, (170, 150, 116))
    if "plaice_spots" in marks:
        for k in range(16):
            t = rng.uniform(0.16, 0.92)
            y = rng.uniform(shape.top_at(t) + 12, shape.bot_at(t) - 12)
            r = rng.uniform(4.0, 6.0)
            spot = ell((shape.x(t), y), (r, r * 0.9))
            p.ink(clip(soft(ell((shape.x(t), y), (r + 2.2, r + 2.0)), 1.2), inner), (226, 214, 190), 70)
            p.ink(clip(soft(spot, 0.6), inner), (196, 112, 60), 215)
    if "speckles" in marks:
        for k in range(240):
            t = rng.uniform(0.08, 0.99)
            y = rng.uniform(shape.top_at(t) + 2, shape.mid_at(t) + 14)
            r = rng.uniform(0.9, 2.0)
            p.ink(clip(soft(ell((shape.x(t), y), (r, r * 0.85)), 0.3), inner), mix((74, 62, 38), (120, 104, 70), rng.uniform()), 150)
    if "lateral_pale" in marks or "lateral_dark" in marks or "lateral_faint" in marks or not ({"gills", "gar_band"} & set(marks) or spec.get("flat")):
        if "lateral_pale" in marks:
            colour, width, alpha = (236, 228, 204), 2.0, 190
        elif "lateral_dark" in marks:
            colour, width, alpha = mix(spec["back"], LINE, 0.4), 1.6, 150
        else:
            colour, width, alpha = mix(spec["back"], LINE, 0.25), 1.0, 70
        pts = [(shape.x(t / 24), shape.top_at(t / 24) + (shape.mid_at(t / 24) - shape.top_at(t / 24)) * (0.55 if t < 8 else 0.75))
               for t in range(4, 25)]
        p.ink(clip(soft(tube(pts, width), 0.3), inner), colour, alpha)
    if "perch_bars" in marks:
        for k in range(6):
            t = 0.26 + k * 0.11
            w = 7 if k % 2 == 0 else 5
            band = poly([(shape.x(t) - w, shape.top_at(t) - 2), (shape.x(t) + w + 2, shape.top_at(t) - 2),
                         (shape.x(t) + 3, shape.bot_at(t) - 16), (shape.x(t) - 2, shape.bot_at(t) - 20)])
            p.ink(clip(soft(band, 2.2), inner), (36, 50, 30), 150)
    if "gar_band" in marks:
        pts = [(shape.x(t / 20), shape.mid_at(t / 20) + 1) for t in range(4, 21)]
        p.ink(clip(soft(tube(pts, 3.0), 0.8), inner), (200, 216, 214), 140)
        p.ink(clip(soft(tube([(x, y - 2.6) for x, y in pts], 1.0), 0.4), inner), (40, 70, 72), 80)
    if "gold_brow" in marks:
        e = spec["eye"]
        x = shape.x(e[0]) + 2
        brow = tube([(x - 22, shape.top_at(e[0]) + 18), (x - 6, shape.top_at(e[0]) + 9), (x + 14, shape.top_at(e[0]) + 11), (x + 24, shape.top_at(e[0]) + 18)], 6, 3)
        p.ink(clip(soft(brow, 1.2), inner), (200, 168, 88), 210)
    if "gill_spot" in marks:
        t = spec["eye"][0] + 0.1
        p.ink(clip(soft(ell((shape.x(t), shape.mid_at(t) - 10), (5.5, 4.5)), 1.0), inner), (46, 44, 48), 190)
    if "faint_lines" in marks:
        for k in range(6):
            frac = 0.22 + k * 0.11
            pts = [(shape.x(t / 20), shape.top_at(t / 20) + (shape.bot_at(t / 20) - shape.top_at(t / 20)) * frac) for t in range(5, 20)]
            p.ink(clip(soft(tube(pts, 1.2), 0.4), inner), mix(spec["back"], LINE, 0.3), 60)
    if "trout_spots" in marks:
        for k in range(60):
            t = rng.uniform(0.12, 0.95)
            y = rng.uniform(shape.top_at(t) + 3, shape.mid_at(t) + 4)
            x = shape.x(t)
            s = rng.uniform(1.3, 2.2)
            a = rng.uniform(-0.5, 0.5)
            m = union(ell((x, y), (s, s * 0.8), math.degrees(a)), tube([(x - s * 1.3, y - s * 0.9), (x + s * 1.3, y + s * 0.9)], 0.9),
                      tube([(x - s * 1.2, y + s * 0.8), (x + s * 1.2, y - s * 0.8)], 0.8))
            p.ink(clip(soft(m, 0.5), inner), (38, 38, 42), 160)
    if "bonito_stripes" in marks:
        for k in range(8):
            t0 = 0.18 + k * 0.09
            pts = [(shape.x(t0), shape.top_at(t0) + 2), (shape.x(t0 + 0.06), shape.top_at(t0 + 0.06) + (shape.mid_at(t0 + 0.06) - shape.top_at(t0 + 0.06)) * 0.6),
                   (shape.x(t0 + 0.12), shape.mid_at(t0 + 0.12) - 3)]
            p.ink(clip(soft(tube(pts, 2.6, 2.0), 0.6), inner), (26, 34, 52), 200)
    if "skipjack_stripes" in marks:
        for k in range(4):
            frac = 0.6 + k * 0.09
            pts = [(shape.x(t / 20), shape.top_at(t / 20) + (shape.bot_at(t / 20) - shape.top_at(t / 20)) * frac) for t in range(5, 19)]
            p.ink(clip(soft(tube(pts, 2.6, 1.6), 0.7), inner), (58, 66, 88), 175)
    if "mahi_dots" in marks:
        for k in range(60):
            t = rng.uniform(0.15, 0.95)
            y = rng.uniform(shape.top_at(t) + 6, shape.bot_at(t) - 8)
            r = rng.uniform(1.2, 2.4)
            p.ink(clip(soft(ell((shape.x(t), y), (r, r)), 0.4), inner), (40, 92, 112), 170)
    if "yellow_band" in marks:
        pts = [(shape.x(t / 20), shape.mid_at(t / 20) - 4) for t in range(3, 19)]
        p.ink(clip(soft(tube(pts, 5.0, 2.0), 1.4), inner), (206, 178, 80), 170)
    if "belly_dashes" in marks:
        for k in range(16):
            t = 0.3 + k * 0.04
            y = shape.mid_at(t) + 12
            p.ink(clip(soft(tube([(shape.x(t), y), (shape.x(t) - 1, y + 12)], 1.8), 0.5), inner), (204, 210, 222), 150)
    if "flank_band" in marks:
        # the pale band that runs back into the dark of the blacktip's flank
        pts = [(shape.x(t / 20), shape.mid_at(t / 20) + 6) for t in range(9, 16)]
        p.ink(clip(soft(tube(pts, 4.0, 1.0), 1.5), inner), (214, 210, 200), 120)
    if "gills" in marks:
        for k in range(5):
            t = spec["eye"][0] + 0.1 + k * 0.02
            x = shape.x(t)
            m = tube([(x - 1, shape.mid_at(t) - 9), (x + 1.5, shape.mid_at(t)), (x, shape.mid_at(t) + 8)], 1.1)
            p.ink(clip(soft(m, 0.3), inner), mix(spec["back"], LINE, 0.6), 150)
            p.ink(clip(soft(ImageChops.offset(m, SS, 0), 0.3), inner), (226, 230, 230), 50)


def paint_head(p, shape, spec, body):
    """Mouth, gill cover, barbel, all by tone and a thin line."""
    mouth = spec.get("mouth", "flat")
    nose = (shape.x0, (shape.top[0][1] + shape.bot[0][1]) / 2)
    L = shape.x1 - shape.x0
    inner = soft(erode(body, 2), 0.6)
    dark = mix(spec["back"], LINE, 0.6)
    if mouth == "beak":
        p.ink(clip(tube([(nose[0] + 2, nose[1]), (shape.x(0.16), nose[1] + 1)], 0.9), inner), dark, 140)
    elif mouth == "shark":
        p.ink(clip(tube([(shape.x(0.05), shape.bot_at(0.05) - 2), (shape.x(0.1), shape.bot_at(0.1) - 4), (shape.x(0.13), shape.bot_at(0.13) - 2)], 1.2),
                   inner), dark, 150)
        # nostril
        p.ink(clip(soft(ell((shape.x(0.035), shape.bot_at(0.035) - 4), (2.4, 1.0)), 0.3), inner), dark, 130)
    else:
        dy = {"up": -3, "down": 4, "flat": 0}[mouth]
        lip = [(nose[0] + 2, nose[1] + dy), (nose[0] + L * 0.035, nose[1] + dy + 1.5), (nose[0] + L * 0.065, nose[1] + dy + 3)]
        p.ink(clip(tube(lip, 1.3, 0.8), inner), dark, 160)
        p.ink(clip(tube([(x + 0.5, y + 1.6) for x, y in lip], 1.0, 0.6), inner), (236, 232, 222), 60)
        # the upper jaw bone (maxilla), a faint tonal shape
        jaw = ell((nose[0] + L * 0.05, nose[1] + dy - 1), (L * 0.035, 3.0), 12)
        p.ink(clip(soft(jaw, 1.2), inner), dark, 45)
    if not spec.get("shark") and not spec.get("flat"):
        t = spec["eye"][0] + 0.09
        gx = shape.x(t)
        edge = [(gx - 6, shape.top_at(t) + 8), (gx + 2, shape.mid_at(t)), (gx - 4, shape.bot_at(t) - 6)]
        # the gill cover: a soft shadow behind its edge, a lit rim on it
        shade = tube([(x + 3.5, y) for x, y in edge], 6.0)
        p.ink(clip(soft(shade, 2.0), inner), dark, 70)
        p.ink(clip(tube(edge, 1.0), inner), dark, 120)
        p.ink(clip(soft(tube([(x - 1.6, y) for x, y in edge], 1.4), 0.6), inner), (240, 240, 234), 70)
        # the cheek: a little rounder and lighter below the eye
        e = spec["eye"]
        cheek = ell((shape.x(e[0]) + 4, shape.mid_at(e[0]) + 6), (L * 0.04, 9))
        p.ink(clip(soft(cheek, 3), inner), (236, 236, 230), 45)
    if spec.get("barbel"):
        pts = [(shape.x(0.06), shape.bot_at(0.06) - 1), (shape.x(0.06) + 1, shape.bot_at(0.06) + 8), (shape.x(0.06) - 2, shape.bot_at(0.06) + 13)]
        p.wash(tube(pts, 2.0, 1.2), mix(spec["belly"], spec["back"], 0.4), outline=True, line_alpha=70, rim=0.05)


def eye_point(shape, spec):
    t, dy, r = spec["eye"]
    return (shape.x(t), shape.top_at(t) + (shape.mid_at(t) - shape.top_at(t)) * 0.55 + dy), r


def paint_eye(p, c, r, spec):
    """A realistic fish eye: a soft socket, a metallic iris ring, a dark pupil,
    one small highlight. Smaller than the old cartoon eye."""
    shark = spec.get("shark")
    re = r * (0.72 if shark else 0.8)
    iris = mix(spec.get("iris", (190, 184, 160)), spec["back"], 0.3)
    socket = soft(ell(c, (re * 1.25, re * 1.18)), 1.0)
    p.ink(socket, mix(spec["back"], LINE, 0.5), 60)
    # the iris, lit from above
    m = ell(c, (re, re))
    yy = (p.yy / SS - (c[1] - re)) / (2 * re)
    base = np.array(iris, np.float32)
    rgb = base[None, None, :] * (1.08 - 0.3 * yy.clip(0, 1))[..., None]
    p.put(rgb, arr(m))
    pupil = re * (0.7 if shark else 0.64)
    p.dot((c[0] + re * 0.04, c[1] + re * 0.02), pupil, (14, 18, 22))
    if shark:
        p.dot((c[0] + re * 0.04, c[1] + re * 0.02), pupil * 0.95, (14, 18, 22))
    p.outline(m, 0.8, LINE, 120)
    p.ink(soft(ell((c[0] - re * 0.32, c[1] - re * 0.34), (re * 0.17, re * 0.14)), 0.2), (252, 252, 248), 235)
    p.ink(soft(ell((c[0] + re * 0.3, c[1] + re * 0.36), (re * 0.12, re * 0.08)), 0.3), (230, 236, 236), 90)


def paint_lid(p, c, r, colour, spec):
    """The closed eye: skin over the eye, with a soft crease."""
    m = soft(ell(c, (r * 1.02, r * 0.98)), 0.5)
    p.wash(m, mix(colour, (255, 255, 255), 0.06), mix(colour, LINE, 0.06), outline=False, sheen=0.04, rim=0.06)
    p.ink(soft(tube([(c[0] - r * 0.7, c[1] - r * 0.02), (c[0], c[1] + r * 0.26), (c[0] + r * 0.7, c[1] - r * 0.02)], max(r * 0.12, 1.0)), 0.3),
          mix(colour, LINE, 0.6), 170)


def paint_species(sid):
    spec = SPECIES[sid]
    shape = Shape(spec)
    root, half = shape.root()
    kind, length, spread = spec["tail"]

    # The tail, alone: darker at its root, lighter and translucent at its tips.
    tail_p = Painter()
    tail = tail_mask(root, half, kind, length, spread)
    tc = spec["tail_col"]
    if spec.get("shark"):
        tail_p.wash(tail, mix(tc, LINE, 0.1), mix(tc, (210, 214, 214), 0.15), axis="x", rim=0.2, line_alpha=90)
    else:
        xs = (tail_p.xx / SS - root[0]) / max(length, 1)
        fade = 1.0 - 0.32 * smoothstep(0.2, 1.0, xs)
        tail_p.wash(tail, mix(tc, LINE, 0.12), mix(tc, (232, 230, 224), 0.28), axis="x", fade=fade, rim=0.08, line_alpha=70)
        n = 13
        ends = []
        for k in range(n):
            f = (k / (n - 1)) * 2 - 1
            ends.append((root[0] + length * (1.0 - 0.45 * (1 - abs(f)) if kind in ("fork", "deepfork", "notch") else 1.05), root[1] + f * spread * 1.1))
        starts = [(root[0] - 6, root[1] + ((k / (n - 1)) * 2 - 1) * half * 0.8) for k in range(n)]
        fin_rays(tail_p, tail, starts, ends, mix(tc, LINE, 0.5), 65, 0.9)
    if spec.get("black_tips"):
        xs = (tail_p.xx / SS - root[0]) / length
        ys = (tail_p.yy / SS - root[1]) / spread
        g = smoothstep(0.55, 0.85, xs) * smoothstep(-0.55, -0.85, ys) + smoothstep(0.3, 0.42, xs) * smoothstep(0.25, 0.45, ys)
        tail_p.tint(arr(tail) * g.clip(0, 1) * 0.9, TIP)

    # The body with its fins and face.
    p = Painter()
    body_m = shape.mask()
    fin_masks = []
    fin_masks += paint_fins(p, shape, spec, "dorsal", body_m)
    fin_masks += paint_fins(p, shape, spec, "anal", body_m)
    if spec.get("pelvic"):
        edge, t0, t1, height = spec["pelvic"]
        m = minus(fin_on(shape, edge, t0, t1, height, "soft", 0.6), body_m)
        col = spec.get("fin_lower", spec["fin"])
        if spec.get("shark"):
            p.wash(m, mix(col, spec["back"], 0.3), rim=0.2, line_alpha=90)
        else:
            p.wash(m, mix(col, LINE, 0.06), mix(col, (232, 230, 222), 0.2), fade=0.62 + 0.33 * near(body_m, 10), rim=0.08, line_alpha=70)
    if spec.get("adipose"):
        t0, t1 = spec["adipose"]
        m = minus(fin_on(shape, "top", t0, t1, 9, "soft", 0.3), body_m)
        p.wash(m, spec["back"], rim=0.12, line_alpha=80)
    body = paint_body(p, shape, spec)
    paint_marks(p, shape, spec, body)
    if spec.get("finlets"):
        t0, t1, n = spec["finlets"]
        for k in range(n):
            t = t0 + (t1 - t0) * k / max(n - 1, 1)
            for edge in ("top", "bot"):
                y = shape.top_at(t) if edge == "top" else shape.bot_at(t)
                sign = -1 if edge == "top" else 1
                m = poly([(shape.x(t) - 3, y - sign * 1), (shape.x(t) + 6, y + sign * 7), (shape.x(t) + 4, y - sign * 1)])
                c = spec.get("finlet_col", spec["fin"])
                p.wash(m, mix(c, (240, 236, 220), 0.1), mix(c, LINE, 0.15), rim=0.05, line_alpha=80)
    if spec.get("keel"):
        pts = [(shape.x(0.86), shape.mid_at(0.86)), (shape.x(1.0), shape.mid_at(1.0))]
        p.ink(soft(tube(pts, 3.0, 2.0), 0.6), mix(spec["back"], LINE, 0.3), 170)
        p.ink(soft(tube([(x, y - 1.6) for x, y in pts], 1.0), 0.4), (210, 214, 216), 60)
    paint_head(p, shape, spec, body)
    pec = spec["pectoral"]
    if pec[1] > 0:
        pm = pectoral(shape, pec[0], pec[1], pec[2] if len(pec) > 2 else 25, pec[3] if len(pec) > 3 else 0.42)
        col = spec.get("pectoral_col", spec["fin"])
        if spec.get("shark"):
            p.wash(pm, mix(col, spec["back"], 0.3), mix(col, (200, 206, 210), 0.12), rim=0.2, line_alpha=90)
            p.ink(clip(soft(tube([(shape.x(pec[0]) + 2, shape.mid_at(pec[0]) + 4), (shape.x(pec[0]) + pec[1] * 0.8, shape.mid_at(pec[0]) + pec[1] * 0.45)], 2.0), 1.0),
                       pm), (230, 232, 232), 50)
        else:
            x0 = shape.x(pec[0])
            fade = 0.55 + 0.4 * (1.0 - ((p.xx / SS - x0) / max(pec[1], 1)).clip(0, 1))
            p.wash(pm, mix(col, (236, 234, 226), 0.15), mix(col, LINE, 0.08), axis="x", fade=fade, rim=0.06, line_alpha=75)
            box = pm.getbbox()
            if box:
                y_c = shape.mid_at(pec[0]) + (shape.bot_at(pec[0]) - shape.mid_at(pec[0])) * 0.35
                a = math.radians(pec[2] if len(pec) > 2 else 25)
                starts, ends = [], []
                for k in range(6):
                    f = (k - 2.5) / 2.5
                    starts.append((x0 + 1, y_c + f * pec[1] * 0.12))
                    ends.append((x0 + pec[1] * math.cos(a) * 1.05, y_c + pec[1] * math.sin(a) + f * pec[1] * 0.3))
                fin_rays(p, pm, starts, ends, mix(col, LINE, 0.5), 60, 0.8)
        if spec.get("black_tips"):
            tip = soft(ell((shape.x(pec[0]) + pec[1] * 0.9, shape.mid_at(pec[0]) + pec[1] * 0.55), (17, 13)), 2.0)
            p.ink(clip(pm, tip), TIP, 220)
    eye_c, eye_r = eye_point(shape, spec)
    lid_colour = p.colour_at(eye_c[0], eye_c[1], eye_r * 0.8)
    paint_eye(p, eye_c, eye_r, spec)
    eyes = [(eye_c, eye_r)]
    if spec.get("second_eye"):
        t, dy, r = spec["second_eye"]
        c2 = (shape.x(t), shape.top_at(t) + 12 + dy * 0.2)
        paint_eye(p, c2, r, spec)
        eyes.append((c2, r))

    lid_p = Painter()
    for c, r in eyes:
        paint_lid(lid_p, c, r, lid_colour, spec)
    return {"tail": tail_p.image(), "body": p.image(), "lid": lid_p.image(shadow=False),
            "meta": {"tail_pivot": [round(root[0], 1), round(root[1], 1)], "eye": [round(eye_c[0], 1), round(eye_c[1], 1), eye_r],
                     "canvas": [W, H], "kind": "shark" if spec.get("shark") else "fish"}}


# --- Junk --------------------------------------------------------------------------------

def paint_junk(jid):
    p = Painter(seed=11)
    rng = np.random.default_rng(5)
    if jid == "old_boot":
        # A worn leather work boot, waterlogged and grey with salt, a little weed.
        shaft = poly(smooth([(196, 40), (262, 34), (270, 120), (274, 150), (360, 168), (378, 192), (372, 206), (184, 206), (178, 160), (190, 120)], 10))
        p.wash(shaft, (96, 80, 64), (70, 58, 48), rim=0.22, line_alpha=100)
        g = (p.mottle.clip(0.2, 1) - 0.2) * arr(erode(shaft, 4))
        p.tint(g * 0.45, (150, 146, 132))                      # salt bloom
        for k in range(40):                                    # scuffs and creases
            x, y = rng.uniform(190, 360), rng.uniform(60, 200)
            m = clip(tube([(x, y), (x + rng.uniform(4, 12), y + rng.uniform(-2, 2))], 1.0), erode(shaft, 4))
            p.ink(soft(m, 0.3), (52, 44, 38), 70)
        p.ink(clip(soft(tube([(274, 150), (300, 168), (340, 176), (372, 196)], 2.0), 0.8), shaft), (48, 40, 34), 90)   # toe-cap seam
        p.ink(clip(soft(tube([(262, 40), (268, 120), (272, 150)], 6), 3), shaft), (40, 34, 30), 70)                       # shade at the back
        p.ink(clip(soft(tube([(200, 46), (196, 120), (190, 190)], 5), 2.5), shaft), (190, 180, 160), 60)                 # lit front edge
        sole = poly([(180, 198), (376, 198), (378, 214), (182, 216)])
        p.wash(sole, (64, 58, 52), (46, 42, 38), rim=0.2, line_alpha=100)
        p.ink(clip(tube([(184, 201), (374, 201)], 1.0), sole), (120, 112, 100), 90)
        for k in range(5):                                     # eyelets and a frayed lace
            y = 70 + k * 18
            p.dot((210, y + 1), 1.6, (120, 116, 104), 200)
            p.dot((252, y - 3), 1.6, (120, 116, 104), 200)
            p.line([(210, y + 1), (252, y - 3)], 1.6, (168, 158, 136), 200)
        p.line([(252, 52), (262, 40), (258, 26), (266, 18)], 1.4, (168, 158, 136), 190)
        p.ink(soft(tube([(200, 46), (258, 42)], 3.0), 0.6), (44, 36, 30), 120)  # the opening
        weed = union(tube([(236, 46), (228, 30), (240, 18), (234, 8)], 5, 2), tube([(242, 44), (250, 28), (246, 16)], 4, 2),
                     tube([(300, 170), (322, 150), (318, 128)], 5, 2), tube([(306, 172), (332, 162), (340, 146)], 4, 2))
        p.wash(weed, (98, 114, 66), (66, 84, 50), rim=0.15, line_alpha=80)
        for k in range(10):                                    # barnacles
            c = (rng.uniform(280, 366), rng.uniform(182, 200))
            p.dot(c, rng.uniform(1.4, 2.6), (196, 190, 176), 200)
            p.dot((c[0] + 0.4, c[1] + 0.4), 0.8, (90, 84, 76), 200)
    elif jid == "tangled_rope":
        # Old three-strand hemp line in a loose tangle.
        loops = []
        for k in range(7):
            cx, cy = 256 + rng.uniform(-60, 60), 128 + rng.uniform(-36, 36)
            rx, ry = rng.uniform(34, 70), rng.uniform(20, 44)
            pts = [(cx + rx * math.cos(a), cy + ry * math.sin(a)) for a in np.linspace(0, 2 * math.pi * 1.1, 40)]
            loops.append(pts)
        loops.append([(214, 160), (170, 190), (130, 214), (100, 210)])
        for pts in loops:
            m = tube(pts, 8)
            p.wash(m, (186, 168, 130), (146, 128, 96), rim=0.35, line_alpha=90)
            for q in range(0, len(pts) - 1):                   # the twist of the strands
                x, y = pts[q]
                x2, y2 = pts[q + 1]
                for s in range(3):
                    f = (s + 0.5) / 3
                    px, py = x + (x2 - x) * f, y + (y2 - y) * f
                    p.ink(clip(soft(tube([(px - 2.6, py - 2.6), (px + 2.6, py + 2.6)], 1.0), 0.3), m), (104, 88, 62), 110)
        fray = [(100, 210), (92, 204), (90, 214), (94, 220)]
        for q in fray[1:]:
            p.line([(100, 210), q], 0.9, (150, 132, 100), 180)
    else:  # rusty tin
        body = poly([(196, 70), (326, 70), (326, 200), (196, 200)])
        xs = (p.xx / SS - 196) / 130
        cyl = (0.78 + 0.32 * np.sin(np.clip(xs, 0, 1) * math.pi * 0.9 + 0.25))
        rgb = np.array((150, 148, 140), np.float32)[None, None, :] * cyl[..., None]
        p.put(rgb * (1 + p.grain[..., None] * 0.03), arr(body))
        p.silhouette = union(p.silhouette, body)
        for y in (84, 186):                                    # rolled ribs
            p.ink(clip(soft(tube([(196, y), (326, y)], 2.0), 0.5), body), (96, 92, 86), 110)
            p.ink(clip(soft(tube([(196, y + 2), (326, y + 2)], 1.0), 0.3), body), (210, 206, 196), 80)
        label = poly([(196, 104), (326, 104), (326, 166), (196, 166)])
        lab = np.array((150, 86, 66), np.float32)[None, None, :] * cyl[..., None]
        p.put(lab, arr(label) * 0.92)
        p.ink(clip(tube([(214, 136), (306, 136)], 3), label), (214, 200, 168), 150)
        p.ink(clip(tube([(226, 124), (296, 124)], 1.4), label), (214, 200, 168), 110)
        # faded, peeling label
        g = (p.mottle.clip(0.25, 1) - 0.25) * arr(label)
        p.tint(g * 0.9, (150, 148, 140))
        top = ell((261, 70), (65, 12))
        p.wash(top, (178, 176, 168), (128, 124, 116), rim=0.25, line_alpha=100)
        p.ink(clip(soft(ell((261, 71), (56, 8)), 0.6), top), (100, 96, 90), 90)
        for k in range(46):                                    # rust
            c = (rng.uniform(198, 324), rng.uniform(68, 200))
            r = (rng.uniform(1.5, 7), rng.uniform(1.5, 5))
            p.ink(clip(soft(ell(c, r, rng.uniform(0, 180)), 1.2), union(body, top)), mix((140, 76, 40), (104, 58, 34), rng.uniform()), 170)
        p.ink(clip(soft(tube([(200, 196), (322, 196)], 5), 2.0), body), (118, 66, 36), 150)   # rust along the bottom seam
        p.outline(body, 1.0, LINE, 100)
        lid = poly([(262, 64), (330, 40), (336, 48), (270, 70)])
        p.wash(lid, (176, 172, 164), (138, 134, 126), rim=0.2, line_alpha=100)
        p.ink(clip(soft(ell((320, 48), (8, 4)), 1.0), lid), (140, 76, 40), 150)
    return p.image()


# --- Output -------------------------------------------------------------------------------

def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)


def thumb_of(layers):
    comp = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for layer in layers:
        comp.alpha_composite(layer)
    box = comp.getbbox() or (0, 0, W, H)
    pad = 6
    box = (max(box[0] - pad, 0), max(box[1] - pad, 0), min(box[2] + pad, W), min(box[3] + pad, H))
    crop = comp.crop(box)
    crop.thumbnail(THUMB, Image.LANCZOS)
    out = Image.new("RGBA", THUMB, (0, 0, 0, 0))
    out.alpha_composite(crop, ((THUMB[0] - crop.width) // 2, (THUMB[1] - crop.height) // 2))
    return out


def main(ids):
    meta = {}
    if os.path.exists(META):
        with open(META) as f:
            meta = json.load(f).get("art", {})
    for sid in ids:
        if sid in SPECIES:
            layers = paint_species(sid)
            for name in ("tail", "body", "lid"):
                save(layers[name], os.path.join(OUT, sid, name + ".png"))
            save(thumb_of([layers["tail"], layers["body"]]), os.path.join(OUT, sid, "thumb.png"))
            meta[sid] = layers["meta"]
        elif sid in JUNK:
            art = paint_junk(sid)
            save(art, os.path.join(OUT, sid, "art.png"))
            save(thumb_of([art]), os.path.join(OUT, sid, "thumb.png"))
            meta[sid] = {"canvas": [W, H], "kind": "junk"}
        else:
            print("unknown:", sid)
            continue
        print("painted", sid)
    with open(META, "w") as f:
        json.dump({"note": "Written by tools/fishing/paint_fish.py: the layer canvas, the tail's pivot and the eye (canvas px).",
                   "art": meta}, f, indent=1, sort_keys=True)


if __name__ == "__main__":
    main(sys.argv[1:] or list(SPECIES) + JUNK)
