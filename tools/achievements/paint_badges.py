"""Paints the achievement badges (Real Horizon look).

Each badge is a small round maritime pin, about 120 px across on a 128 x 128
transparent canvas: a thin brushed-steel rim lit from the upper left, a
recessed disc in a muted category colour, and one clear pictogram in
off-white and sea tones with soft shading (light from the upper left, a soft
shadow down-right) and at most a thin translucent blue-grey edge line. No
gold, no gloss, no bold outlines (DEV_GUIDES/ART_DIRECTION.md). The same base,
shading and primitives are shared by every icon so the set reads as one series;
the three speed badges share one dial design.

Icon ids come from data/progression/achievements.json ("icon", disc colour by
"category"); "secret" is the extra badge shown for undiscovered secrets.
The game greys locked badges and draws its own lock glyph, so every
pictogram is a clear light shape on a darker disc that survives greying.

Writes assets/achievements/<icon>.png and a review sheet
/tmp/badges_review/sheet.png (128 px and 48 px, colour and greyed).
Original work for this project; same licence as the game's own art.

Usage: python3 tools/achievements/paint_badges.py
Requirements: Python 3 with Pillow and numpy. Deterministic.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "art"))
import marine_palette as mp  # noqa: E402

DATA = os.path.join(ROOT, "data", "progression", "achievements.json")
OUT = os.path.join(ROOT, "assets", "achievements")
REVIEW = "/tmp/badges_review"
FONT = os.path.join(ROOT, "assets", "fonts", "BarlowCondensed-SemiBold.ttf")

SIZE = 128
SS = 4
N = SIZE * SS
CX = CY = 64.0
R_OUT = 60.0         # badge outer radius (120 px across)
R_IN = 55.6          # disc radius inside the rim

# Category discs: muted, distinct in hue and in value.
CATEGORY = {
    "voyages": mp.DEEP_SEA,
    "seamanship": (62, 94, 98),
    "performance": (168, 128, 76),
    "life": (122, 96, 74),
    "companionship": (134, 106, 120),
    "discoveries": (66, 108, 92),
    "reputation": (70, 132, 146),
    "secret": (86, 96, 102),
}

# Pictogram tones.
WHITE = (232, 230, 220)
HAZE = mp.SEA_HAZE
SKY = (170, 186, 192)
SEAL = (138, 172, 182)
SEAM = (96, 132, 144)
DARK = (46, 58, 64)
PANEL = (34, 46, 54)
STEEL = (160, 170, 172)
TEAK = (164, 134, 104)
SAND = (212, 196, 164)
RED = (172, 84, 70)
AMBER = (226, 180, 104)
PALE_GOLD = (238, 222, 176)
GREEN = (96, 140, 108)
LEAF = (132, 160, 112)
CYAN = (96, 176, 192)
SHADOW = (18, 26, 32)


# --- Geometry -------------------------------------------------------------------------

def tf(pts, ox=0.0, oy=0.0, s=1.0, rot=0.0):
    """Scale, rotate (degrees, clockwise on screen) and move local points."""
    c, si = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    return [(ox + s * (x * c - y * si), oy + s * (x * si + y * c)) for x, y in pts]


def ell(cx, cy, rx, ry=None, a0=0.0, a1=360.0, n=64):
    ry = rx if ry is None else ry
    return [(cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def bez(p0, p1, p2, p3, n=40):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def sine(x0, x1, y, amp, wl, phase=0.0, n=60):
    return [(x0 + (x1 - x0) * i / n,
             y + amp * math.sin(2 * math.pi * ((x0 + (x1 - x0) * i / n) / wl) + phase)) for i in range(n + 1)]


def star_pts(cx, cy, r, ri, n=5, rot=-90.0):
    pts = []
    for i in range(2 * n):
        a = math.radians(rot + i * 180.0 / n)
        rr = r if i % 2 == 0 else ri
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


def rrect(x0, y0, x1, y1, r, n=8):
    pts = []
    for cx, cy, a in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        pts += ell(cx, cy, r, r, a, a + 90, n)
    return pts


# --- Masks ----------------------------------------------------------------------------

class Shape:
    """A supersampled coverage mask drawn in 128-px badge coordinates."""

    def __init__(self):
        self.img = Image.new("L", (N, N), 0)
        self.d = ImageDraw.Draw(self.img)

    @staticmethod
    def _s(pts):
        return [(x * SS, y * SS) for x, y in pts]

    def poly(self, pts, cut=False):
        self.d.polygon(self._s(pts), fill=0 if cut else 255)
        return self

    def circle(self, cx, cy, r, ry=None, cut=False):
        ry = r if ry is None else ry
        self.d.ellipse([(cx - r) * SS, (cy - ry) * SS, (cx + r) * SS, (cy + ry) * SS], fill=0 if cut else 255)
        return self

    def line(self, pts, w, cut=False, caps=True):
        f = 0 if cut else 255
        self.d.line(self._s(pts), fill=f, width=max(1, round(w * SS)), joint="curve")
        if caps:
            for x, y in (pts[0], pts[-1]):
                self.circle(x, y, w / 2, cut=cut)
        return self

    def arc(self, cx, cy, r, a0, a1, w, cut=False, caps=True):
        return self.line(ell(cx, cy, r, r, a0, a1, 48), w, cut, caps)

    def dashed(self, pts, w, dash, gap):
        seg, acc, on = [pts[0]], 0.0, True
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            acc += math.hypot(x1 - x0, y1 - y0)
            seg.append((x1, y1))
            if acc >= (dash if on else gap):
                if on and len(seg) > 1:
                    self.line(seg, w)
                seg, acc, on = [(x1, y1)], 0.0, not on
        if on and len(seg) > 1:
            self.line(seg, w)
        return self

    def text(self, x, y, s, size, cut=False):
        f = ImageFont.truetype(FONT, int(size * SS))
        self.d.text((x * SS, y * SS), s, font=f, fill=0 if cut else 255, anchor="mm")
        return self

    def clip(self, other):
        self.img = ImageChops.multiply(self.img, other.img)
        self.d = ImageDraw.Draw(self.img)
        return self

    def minus(self, other):
        self.img = ImageChops.subtract(self.img, other.img)
        self.d = ImageDraw.Draw(self.img)
        return self

    def copy(self):
        s = Shape()
        s.img = self.img.copy()
        s.d = ImageDraw.Draw(s.img)
        return s


def band(y0, y1, x0=0, x1=128):
    return Shape().poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])


def _arr(img):
    return np.asarray(img, dtype=np.float32) / 255.0


def _shift(a, dx, dy):
    out = np.zeros_like(a)
    dx, dy = int(round(dx)), int(round(dy))
    h, w = a.shape
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = a[max(-dy, 0):h - max(dy, 0), max(-dx, 0):w - max(dx, 0)]
    return out


def _blur(a, r):
    img = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return _arr(img.filter(ImageFilter.GaussianBlur(r)))


YY, XX = np.mgrid[0:N, 0:N].astype(np.float32) / SS


# --- Canvas ---------------------------------------------------------------------------

class Canvas:
    """The disc's paint (RGB floats). Every layer gets the same treatment."""

    def __init__(self, disc):
        self.rgb = np.zeros((N, N, 3), np.float32)
        self.rgb[:] = np.array(disc, np.float32)

    def over(self, color, a):
        col = np.asarray(color, np.float32)
        a = a[..., None] if a.ndim == 2 else a
        self.rgb = self.rgb * (1 - a) + col * a

    def paint(self, shape, color, alpha=1.0, shade=1.0, shadow=1.0, edge=1.0):
        m = _arr(shape.img)
        if m.max() <= 0:
            return
        if shadow:
            sm = _blur(_shift(m, 1.3 * SS, 1.7 * SS), 1.5 * SS)
            self.over(SHADOW, sm * 0.30 * shadow * alpha)
        ys, xs = np.nonzero(m > 0.5)
        if len(xs):
            x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
        else:
            x0, x1, y0, y1 = 0, N, 0, N
        t = ((np.arange(N)[None, :] - x0) / max(1, x1 - x0) + (np.arange(N)[:, None] - y0) / max(1, y1 - y0)) / 2
        t = np.clip(t, 0, 1)[..., None]
        col = np.asarray(color, np.float32) * (1.07 - 0.15 * t * shade)
        if shade:
            k = 1.1 * SS
            hl = _blur(np.clip(m - _shift(m, k, k), 0, 1), 0.5 * SS)[..., None]
            sh = _blur(np.clip(m - _shift(m, -k, -k), 0, 1), 0.5 * SS)[..., None]
            col = col + (255 - col) * 0.20 * hl * shade
            col = col * (1 - 0.20 * sh * shade)
        col = np.clip(col, 0, 255)
        a = (m * alpha)[..., None]
        self.rgb = self.rgb * (1 - a) + col * a
        if edge:
            dil = _arr(shape.img.filter(ImageFilter.MaxFilter(5)))
            e = np.clip(dil - m, 0, 1)
            self.over(mp.LINE, e * 0.32 * edge * alpha)

    def fill(self, shape, color, alpha=1.0):
        """A flat, soft layer (glows, fog, rain): no shading, shadow or line."""
        self.paint(shape, color, alpha, shade=0, shadow=0, edge=0)

    def glow(self, cx, cy, r, color, strength):
        d = np.hypot(XX - cx, YY - cy)
        self.over(color, np.clip(1 - d / r, 0, 1) ** 2 * strength)


# --- Badge base -----------------------------------------------------------------------

def _hash_noise(seed, shape):
    rng = np.random.RandomState(seed)
    return rng.normal(0, 1, shape).astype(np.float32)


def compose(canvas, disc):
    """Rim + recessed disc around the painted content; returns a 128 px RGBA image."""
    dx, dy = XX - CX + 0.5 / SS, YY - CY + 0.5 / SS
    r = np.hypot(dx, dy)
    nx, ny = dx / np.maximum(r, 1e-3), dy / np.maximum(r, 1e-3)
    lit = (nx * -0.7071 + ny * -0.7071)  # +1 facing the upper-left light
    rgb = canvas.rgb.copy()

    # Disc: soft diagonal light and a gentle vignette, recessed under the rim.
    base = np.asarray(disc, np.float32)
    t = np.clip(((XX - 8) + (YY - 8)) / 224.0, 0, 1)
    disc_tone = 1.06 - 0.16 * t
    vign = 1 - 0.10 * np.clip((r - 30) / 26, 0, 1) ** 2
    inner_shadow = 1 - 0.30 * np.clip(lit, 0, 1) * np.clip(1 - (R_IN - r) / 3.2, 0, 1)
    inner_light = 1 + 0.10 * np.clip(-lit, 0, 1) * np.clip(1 - (R_IN - r) / 1.6, 0, 1)
    mod = (disc_tone * vign * inner_shadow * inner_light)[..., None]
    # Apply the disc light to the content too, gently, so pictograms sit in it.
    rgb = rgb * (0.55 + 0.45 * mod)
    # Faint hairline ring inside the disc (chart-plotter medallion).
    ring = np.clip(1 - np.abs(r - (R_IN - 4.2)) / 0.45, 0, 1)
    under = np.clip(np.abs(canvas.rgb - base).sum(-1) / 30.0, 0, 1)  # skip over pictograms
    rgb = rgb * (1 - (ring * 0.16 * (1 - under))[..., None]) + np.array(HAZE, np.float32) * (ring * 0.16 * (1 - under))[..., None]

    # Rim: brushed steel, concentric grain, lit edge upper-left.
    steel = np.asarray(mp.BRUSHED_STEEL, np.float32)
    grain = _hash_noise(11, 512)[np.clip((r * 8).astype(int), 0, 511)] * 0.025
    rim_tone = 1 + 0.20 * lit + grain
    edge_hi = np.clip(1 - (R_OUT - r) / 1.1, 0, 1) * np.clip(lit, 0, 1) * 0.35
    inner_hi = np.clip(1 - np.abs(r - (R_IN + 0.5)) / 0.7, 0, 1) * np.clip(-lit, 0, 1) * 0.25
    rim = steel * rim_tone[..., None]
    rim = rim + (255 - rim) * (edge_hi + inner_hi)[..., None]
    in_rim = np.clip((r - R_IN) * SS + 0.5, 0, 1)[..., None]
    rgb = rgb * (1 - in_rim) + rim * in_rim
    # Thin translucent line at the outer edge and the rim/disc seam.
    seam = np.clip(1 - np.abs(r - R_IN) / 0.35, 0, 1) * 0.35
    outer = np.clip(1 - (R_OUT - r) / 0.5, 0, 1) * 0.40
    line = np.asarray(mp.LINE, np.float32)
    for a in (seam, outer):
        rgb = rgb * (1 - a[..., None]) + line * a[..., None]

    alpha = np.clip((R_OUT - r) * SS + 0.5, 0, 1)
    out = np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    # Downsample in premultiplied space so the edge carries no dark fringe.
    pre = np.asarray(img, np.float32)
    pre[..., :3] *= pre[..., 3:4] / 255.0
    small = Image.fromarray(pre.astype(np.uint8), "RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    s = np.asarray(small, np.float32)
    a = s[..., 3:4]
    s[..., :3] = np.where(a > 0, s[..., :3] * 255.0 / np.maximum(a, 1), 0)
    return Image.fromarray(np.clip(s, 0, 255).astype(np.uint8), "RGBA")


# --- Shared motifs --------------------------------------------------------------------

def waves(c, rows, color=SEAL, w=2.2, x0=20, x1=108, alpha=1.0):
    for y, amp, wl, ph in rows:
        c.paint(Shape().line(sine(x0, x1, y, amp, wl, ph), w), color, alpha, shade=0.5, shadow=0.6, edge=0.5)


def yacht(c, cx, wl, s=1.0, rot=0.0, hull=WHITE, sail=HAZE, crew=None):
    """A sloop from the side, bow right, waterline at (cx, wl)."""
    T = lambda pts: tf(pts, cx, wl, s, rot)  # noqa: E731
    main = Shape().poly(T([(-1.4, -36), (-1.4, -6.5), (-17, -6.5)]))
    jib = Shape().poly(T([(1.6, -32), (20, -6.5), (2.6, -6.5)]))
    c.paint(main, sail)
    c.paint(jib, WHITE)
    c.paint(Shape().line(T([(0, -5), (0, -38)]), 1.4 * s, caps=False), DARK, shade=0, shadow=0.4, edge=0)
    if crew:
        crew(T)
    h = Shape().poly(T([(-20, -6.5)] + bez((-20, -6.5), (-4, -7.2), (12, -7.6), (24, -9.0), 12)
                       + [(19, 0.5), (12, 1.8), (-12, 1.8), (-18, -0.5)]))
    c.paint(h, hull)
    c.paint(Shape().line(T([(-18.5, -1.2), (20, -1.2)]), 0.9 * s, caps=False).clip(h), SEAM, shade=0, shadow=0, edge=0)


def anchor(c, cx, cy, s=1.0, rot=0.0, color=WHITE):
    T = lambda pts: tf(pts, cx, cy, s, rot)  # noqa: E731
    a = Shape()
    a.line(T(ell(0, -26, 4.6, 4.6)), 2.6 * s, caps=False)
    a.line(T([(-11, -18), (11, -18)]), 3.6 * s)
    a.line(T([(0, -21.5), (0, 18)]), 4.4 * s)
    a.line(T(ell(0, -2, 20, 20, 25, 155, 40)), 4.2 * s)
    for ang, sign in ((25, 1), (155, -1)):
        rad = math.radians(ang)
        ex, ey = 20 * math.cos(rad), -2 + 20 * math.sin(rad)
        tx, ty = (math.sin(rad), -math.cos(rad)) if sign > 0 else (-math.sin(rad), math.cos(rad))
        nx, ny = math.cos(rad), math.sin(rad)
        a.poly(T([(ex + tx * 9, ey + ty * 9), (ex + nx * 4.2 - tx * 1.5, ey + ny * 4.2 - ty * 1.5),
                  (ex - nx * 4.2 - tx * 1.5, ey - ny * 4.2 - ty * 1.5)]))
    a.circle(*T([(0, 18)])[0], 3.2 * s)
    c.paint(a, color)


def fish_shape(cx, cy, s=1.0, rot=0.0, depth=9.0, length=44.0):
    """Body+tail+fins mask, back mask and eye position for a side-view fish (head right)."""
    T = lambda pts: tf(pts, cx, cy, s, rot)  # noqa: E731
    hl = length / 2
    top, bot = [], []
    for i in range(41):
        t = i / 40
        x = hl - t * (length * 0.86)
        prof = math.sin(math.pi * min(1.0, t * 1.05)) ** 0.75
        top.append((x, -depth * prof * (1.05 if t < 0.5 else 1.0)))
        bot.append((x, depth * 0.85 * prof))
    tb = hl - length * 0.86
    body = top + [(tb, -1.6), (tb - 9, -depth * 0.95), (tb - 6.5, 0), (tb - 9, depth * 0.95), (tb, 1.6)] + bot[::-1]
    sh = Shape().poly(T(body))
    sh.poly(T([(-length * 0.05, -depth * 0.9), (-length * 0.22, -depth * 1.5), (-length * 0.3, -depth * 0.75)]))
    sh.poly(T([(-length * 0.12, depth * 0.7), (-length * 0.24, depth * 1.25), (-length * 0.28, depth * 0.62)]))
    back = sh.copy().clip(Shape().poly(T([(-60, -40), (60, -40), (60, -depth * 0.12), (-60, -depth * 0.05)])))
    eye = T([(hl - length * 0.16, -depth * 0.22)])[0]
    gill = T(ell(hl - length * 0.12, 0, length * 0.10, depth * 0.62, 120, 240, 16))
    return sh, back, eye, gill


def paint_fish(c, cx, cy, s=1.0, rot=0.0, body=WHITE, back=SEAL, depth=9.0, length=44.0):
    sh, bk, eye, gill = fish_shape(cx, cy, s, rot, depth, length)
    c.paint(sh, body)
    c.paint(bk, back, alpha=0.85, shade=0, shadow=0, edge=0)
    c.paint(Shape().line(gill, 0.9 * s, caps=False), DARK, 0.45, shade=0, shadow=0, edge=0)
    c.paint(Shape().circle(eye[0], eye[1], 1.7 * s), DARK, shade=0, shadow=0, edge=0)


def captain_hat(c, cx, cy, s=1.0, rot=0.0):
    """A peaked captain's cap in three-quarter view (visor to the right)."""
    T = lambda pts: tf(pts, cx, cy, s, rot)  # noqa: E731
    crown = Shape().poly(T(ell(0, -11, 30, 8.5)))
    crown.poly(T([(-30, -11), (30, -11), (24, 2), (-23, 2)]))
    c.paint(crown, WHITE)
    c.paint(Shape().poly(T([(-23.5, -4), (24.5, -4), (23.5, 4), (-22.5, 4)])), PANEL)
    c.paint(Shape().line(T([(-22, -4.2), (23, -4.2)]), 1.2 * s, caps=False), AMBER, shade=0, shadow=0, edge=0)
    em = Shape().poly(T(ell(4, -7, 4.6, 3.8)))
    c.paint(em, AMBER, shade=0.6, shadow=0.5, edge=0.6)
    visor = Shape().poly(T([(-6, 3)] + bez((-6, 3), (8, 4), (22, 3), (31, 8), 12) + bez((31, 8), (24, 13), (6, 12), (-6, 3), 12)))
    c.paint(visor, DARK)


def paw(c, cx, cy, s=1.0, rot=0.0, color=WHITE):
    T = lambda pts: tf(pts, cx, cy, s, rot)  # noqa: E731
    p = Shape().poly(T(ell(0, 4, 7, 5.8)))
    for x, y, r in ((-7.4, -3.6, 2.8), (-2.6, -8.4, 3.0), (2.6, -8.4, 3.0), (7.4, -3.6, 2.8)):
        p.circle(*T([(x, y)])[0], r * s)
    c.paint(p, color)


def foot(c, cx, cy, s=1.0, rot=0.0, color=WHITE, left=True):
    T = lambda pts: tf(pts, cx, cy, s, rot)  # noqa: E731
    m = -1 if left else 1
    f = Shape().poly(T(ell(m * 0.8, -4, 5.0, 7.4)))
    f.poly(T(ell(m * 0.2, 9.5, 3.8, 4.4)))
    c.paint(f, color)


def globe(c, cx, cy, r, ocean=SEAL, land=SAND):
    g = Shape().circle(cx, cy, r)
    c.paint(g, ocean)
    lands = Shape()
    lands.poly([(cx - r * 0.6, cy - r * 0.75), (cx - r * 0.1, cy - r * 0.85), (cx + r * 0.05, cy - r * 0.45),
                (cx - r * 0.25, cy - r * 0.1), (cx - r * 0.2, cy + r * 0.35), (cx - r * 0.45, cy + r * 0.7),
                (cx - r * 0.6, cy + r * 0.2), (cx - r * 0.85, cy - r * 0.2)])
    lands.poly([(cx + r * 0.35, cy - r * 0.2), (cx + r * 0.8, cy - r * 0.3), (cx + r * 0.95, cy + r * 0.15),
                (cx + r * 0.6, cy + r * 0.6), (cx + r * 0.35, cy + r * 0.3)])
    lands.clip(g)
    c.paint(lands, land, shade=0.5, shadow=0.4, edge=0.5)
    grid = Shape()
    for k in (0.38, 0.75):
        grid.line(ell(cx, cy, r * k, r, -90, 270), 1.0, caps=False)
    grid.line([(cx, cy - r), (cx, cy + r)], 1.0, caps=False)
    for k in (-0.5, 0.0, 0.5):
        half = r * math.sqrt(1 - k * k)
        grid.line(ell(cx, cy + k * r, half, half * 0.12, 0, 180), 1.0, caps=False)
    grid.clip(g)
    c.paint(grid, WHITE, 0.55, shade=0, shadow=0, edge=0)
    # Sphere shading.
    d = np.hypot(XX - (cx - r * 0.35), YY - (cy - r * 0.35)) / (r * 1.6)
    gm = _arr(g.img)
    c.over(SHADOW, np.clip(d - 0.35, 0, 1) * 0.45 * gm)
    c.over(WHITE, np.clip(0.35 - d, 0, 1) * 0.5 * gm)


def rain(c, x0, x1, y0, y1, slope=0.45, n=9, seed=3, alpha=0.55):
    rng = np.random.RandomState(seed)
    s = Shape()
    for i in range(n):
        x = x0 + (x1 - x0) * (i + rng.uniform(0.1, 0.9)) / n
        y = y0 + rng.uniform(0, (y1 - y0) * 0.4)
        ln = rng.uniform(10, 18)
        s.line([(x, y), (x - ln * slope, y + ln)], 1.1)
    c.fill(s, HAZE, alpha)


def sparkle(c, cx, cy, r, color=WHITE):
    c.paint(Shape().poly(star_pts(cx, cy, r, r * 0.26, 4)), color, shade=0.4, shadow=0.5, edge=0.4)


# --- Icons ----------------------------------------------------------------------------

def i_cast_off(c):
    yacht(c, 86, 56, 0.95, -8)
    waves(c, [(64, 1.0, 12, 0.0)], HAZE, 1.4, 66, 108, 0.7)
    deck = Shape().poly([(10, 82), (118, 82), (118, 92), (10, 92)])
    c.paint(deck, TEAK)
    c.paint(Shape().poly([(10, 92), (118, 92), (118, 98), (10, 98)]), (110, 92, 74), shade=0.3, edge=0.5)
    gaps = Shape()
    for x in range(22, 118, 14):
        gaps.line([(x, 82.5), (x, 91.5)], 0.8, caps=False)
    c.fill(gaps, DARK, 0.35)
    cleat = Shape().poly(ell(42, 76.5, 16, 3.4)).poly([(38, 77), (46, 77), (47.5, 82.5), (36.5, 82.5)])
    c.paint(cleat, STEEL)
    rope = Shape()
    rope.line(bez((38, 72), (34, 64), (46, 62), (46, 70), 20) + bez((46, 70), (50, 79), (62, 70), (72, 64), 20), 2.8)
    rope.line(bez((72, 64), (78, 61), (80, 60), (82, 61.5), 8), 2.6)
    c.paint(rope, WHITE)
    waves(c, [(106, 1.4, 14, 0.0)], SEAL, 2.0, 18, 110)


def i_thousand_miles(c):
    c.paint(Shape().text(64, 46, "1000", 34), WHITE)
    wake = Shape()
    wake.line(bez((18, 92), (40, 84), (62, 92), (86, 80), 40), 2.4)
    c.paint(wake, SEAL, shade=0.5)
    c.paint(Shape().dashed(bez((22, 99), (44, 91), (66, 99), (88, 87), 60), 1.4, 3, 3), HAZE, 0.8, shade=0, edge=0)
    boat = Shape().poly(tf([(-8, -3.2), (4, -3.2), (9, 0), (4, 3.2), (-8, 3.2)], 94, 78, 1.0, -22))
    c.paint(boat, WHITE)


def i_harbours(c):
    def house(x, w, h, body, roof):
        c.paint(Shape().poly([(x, 80), (x + w, 80), (x + w, 80 - h), (x, 80 - h)]), body)
        c.paint(Shape().poly([(x - 1.5, 80 - h + 0.5), (x + w / 2, 80 - h - w * 0.5), (x + w + 1.5, 80 - h + 0.5)]), roof)
        c.paint(Shape().poly([(x + w * 0.38, 80), (x + w * 0.62, 80), (x + w * 0.62, 80 - h * 0.5), (x + w * 0.38, 80 - h * 0.5)]),
                DARK, 0.7, shade=0, shadow=0, edge=0)
    house(28, 20, 18, (176, 98, 76), (92, 70, 58))
    house(51, 18, 24, SAND, (92, 70, 58))
    house(72, 22, 16, WHITE, (74, 84, 90))
    # bollards & quay
    quay = Shape().poly([(10, 80), (118, 80), (118, 92), (10, 92)])
    c.paint(quay, STEEL)
    joints = Shape()
    for x in range(18, 118, 12):
        joints.line([(x, 86), (x, 92)], 0.7, caps=False)
    joints.line([(10, 86), (118, 86)], 0.7, caps=False)
    c.fill(joints, DARK, 0.3)
    c.paint(Shape().line([(101, 52), (101, 80)], 1.3, caps=False), DARK, shade=0, edge=0)
    c.paint(Shape().poly([(101.5, 52), (110, 55), (101.5, 58)]), RED, shade=0.3)
    waves(c, [(100, 1.3, 14, 0.0), (108, 1.3, 14, 1.6)], SEAL, 2.0)


def i_globe(c):
    globe(c, 64, 64, 33)


def i_far_harbour(c):
    c.glow(66, 54, 26, AMBER, 0.35)
    hills = Shape().poly([(10, 72)] + sine(10, 118, 68, 1.5, 40) + [(118, 72)])
    hills.poly([(40, 72), (46, 64), (56, 62), (68, 60), (80, 63), (90, 72)])
    c.paint(hills, (78, 104, 112), shade=0.3, shadow=0.3, edge=0.4)
    c.paint(Shape().poly([(64.2, 61), (67.8, 61), (67, 51), (65, 51)]), WHITE, shade=0.4)
    c.paint(Shape().circle(66, 49.5, 2.4), AMBER, shade=0, shadow=0, edge=0)
    rays = Shape()
    rays.poly([(66, 49.5), (34, 44), (34, 50)])
    rays.poly([(66, 49.5), (98, 46), (98, 52)])
    c.fill(rays, PALE_GOLD, 0.28)
    refl = Shape()
    for i, y in enumerate((76, 81, 87, 94)):
        refl.line([(66 - 3 + i, y), (66 + 3 - i, y)], 1.2)
    c.fill(refl, AMBER, 0.75)
    waves(c, [(80, 0.9, 12, 0.0), (90, 1.2, 15, 1.0), (101, 1.5, 18, 2.0)], SEAL, 1.6, 14, 114)


def i_atlantic(c):
    west = Shape().poly([(0, 18), (34, 22), (30, 38), (38, 50), (28, 64), (34, 80), (24, 96), (0, 110)])
    east = Shape().poly([(128, 16), (96, 26), (100, 40), (92, 52), (98, 62), (94, 76), (102, 92), (128, 108)])
    c.paint(west, SAND, shade=0.6)
    c.paint(east, SAND, shade=0.6)
    route = bez((36, 80), (52, 50), (74, 44), (90, 50))
    c.paint(Shape().dashed(route, 2.2, 4.5, 3.5), WHITE, shadow=0.6)
    c.paint(Shape().poly(tf([(0, -4.5), (7, 0), (0, 4.5)], 90, 50.5, 1.0, 20)), WHITE)
    c.paint(Shape().circle(36, 80, 2.8), WHITE)
    waves(c, [(88, 1.0, 10, 0.0), (96, 1.0, 10, 1.4)], SEAL, 1.6, 50, 80)


def i_pacific(c):
    c.paint(Shape().circle(64, 98, 32, 12).clip(band(0, 98)), SAND)
    trunk = bez((58, 92), (60, 74), (64, 56), (72, 44), 20)
    tr = Shape()
    for i in range(len(trunk) - 1):
        tr.line(trunk[i:i + 2], 5.2 - 2.4 * i / len(trunk))
    c.paint(tr, TEAK)
    fr = Shape()
    for ang, ln, droop in ((-170, 26, 10), (-130, 22, 8), (-60, 22, 8), (-15, 26, 11), (160, 18, 8)):
        a = math.radians(ang)
        tip = (72 + ln * math.cos(a), 44 + ln * math.sin(a) + droop)
        mid = (72 + ln * 0.55 * math.cos(a), 44 + ln * 0.55 * math.sin(a) - 3)
        nx, ny = -math.sin(a) * 3.2, math.cos(a) * 3.2
        fr.poly(bez((72, 44), (mid[0] - nx, mid[1] - ny), (mid[0] - nx, mid[1] - ny), tip, 12)
                + bez(tip, (mid[0] + nx, mid[1] + ny + 2), (mid[0] + nx, mid[1] + ny + 2), (72, 44), 12))
    c.paint(fr, LEAF)
    c.paint(Shape().circle(70, 47, 2).circle(74, 47.5, 2), (96, 76, 56), shade=0.3, shadow=0.4, edge=0)
    waves(c, [(97, 2.0, 18, 0.5), (106, 2.2, 20, 2.2)], WHITE, 2.4)


def i_southern_cross(c):
    dots = Shape()
    for x, y, r in ((30, 36, 0.9), (94, 30, 1.0), (102, 76, 0.9), (34, 84, 1.0), (52, 40, 0.7), (82, 94, 0.7), (24, 62, 0.7)):
        dots.circle(x, y, r)
    c.fill(dots, HAZE, 0.8)
    for x, y, r in ((64, 30, 9.5), (61, 94, 11), (40, 60, 8), (88, 54, 9), (76, 74, 4.2)):
        c.glow(x, y, r * 1.6, WHITE, 0.15)
        c.paint(Shape().poly(star_pts(x, y, r, r * 0.42, 5)), PALE_GOLD if r > 10 else WHITE)


def i_long_haul(c):
    c.paint(Shape().line([(14, 60), (114, 60)], 0.8, caps=False), HAZE, 0.5, shade=0, shadow=0, edge=0)
    wake = Shape().poly([(64, 70.5), (14, 66), (14, 68.5), (64, 72.5)])
    wake.poly([(64, 72), (20, 76), (20, 78), (64, 73.6)])
    c.fill(wake, WHITE, 0.75)
    yacht(c, 80, 72, 0.9)
    waves(c, [(86, 1.0, 14, 0.0), (96, 1.3, 16, 1.4), (106, 1.5, 18, 2.6)], SEAL, 1.8)


def i_clean_hull(c):
    hp = [(22, 54)] + bez((22, 54), (50, 52), (80, 51), (106, 48), 16) + [(98, 64)] + bez((98, 64), (84, 72), (50, 74), (28, 66), 16)
    hull = Shape().poly(hp)
    c.paint(Shape().poly([(56, 70), (74, 70), (70, 96), (60, 96)]), PANEL)
    c.paint(Shape().poly([(31, 66), (37, 66), (36, 84), (32, 84)]), PANEL)
    c.paint(hull, WHITE)
    anti = hull.copy().clip(Shape().poly([(0, 66), (128, 58), (128, 128), (0, 128)]))
    c.paint(anti, SEAM, shade=0.6, shadow=0, edge=0)
    c.paint(Shape().line([(26, 64.6), (100, 57.8)], 1.3, caps=False).clip(hull), RED, shade=0, shadow=0, edge=0)
    sparkle(c, 88, 34, 9)
    sparkle(c, 102, 40, 4.5)
    sparkle(c, 76, 28, 3.5)


def i_heavy_weather(c):
    rain(c, 26, 112, 22, 50, 0.5, 11, 5, 0.5)
    yacht(c, 60, 78, 0.95, 24)
    sea = Shape().poly([(0, 128)] + sine(0, 128, 82, 5, 34, 1.2) + [(128, 128)])
    c.paint(sea, SEAM, shade=0.5)
    crest = Shape()
    for y, ph in ((82, 1.2), (96, 2.6)):
        pts = sine(10, 118, y, 5 if y == 82 else 4, 34, ph)
        crest.line(pts, 2.2)
    c.paint(crest, WHITE, shade=0.4, shadow=0.4, edge=0.4)


def i_anchor_night(c):
    for x, y, r in ((30, 40, 1.1), (42, 28, 0.8), (100, 64, 0.9), (94, 84, 0.8), (28, 74, 0.8)):
        c.fill(Shape().circle(x, y, r), HAZE, 0.9)
    sparkle(c, 76, 30, 3.6, HAZE)
    moon = Shape().circle(90, 40, 12).minus(Shape().circle(96, 35, 10.5))
    c.glow(88, 42, 20, PALE_GOLD, 0.15)
    c.paint(moon, PALE_GOLD)
    anchor(c, 56, 70, 1.05)


def i_anchor_hold(c):
    c.paint(Shape().dashed(bez((22, 22), (30, 30), (36, 34), (48, 42)), 2.4, 3.2, 1.8), STEEL)
    anchor(c, 66, 74, 1.0, -28, WHITE)
    bed = Shape().poly([(0, 128), (0, 92)] + sine(0, 128, 88, 2.2, 30, 0.4) + [(128, 92), (128, 128)])
    c.paint(bed, SAND)
    pebbles = Shape().circle(44, 98, 2.4).circle(92, 100, 2).circle(70, 104, 1.6)
    c.paint(pebbles, TEAK, shade=0.4, shadow=0.4, edge=0.4)
    puffs = Shape().circle(84, 86, 3).circle(90, 84, 2.2).circle(52, 87, 2.6)
    c.fill(puffs, HAZE, 0.55)


def i_radio(c):
    c.paint(Shape().poly(rrect(62, 18, 68, 42, 2.5)), DARK)
    body = Shape().poly(rrect(42, 36, 74, 104, 7))
    c.paint(body, HAZE)
    c.paint(Shape().poly(rrect(47, 44, 69, 62, 2.5)), PANEL, shade=0.3)
    c.paint(Shape().text(58, 53, "16", 13), CYAN, shade=0, shadow=0, edge=0)
    grille = Shape()
    for y in (72, 77, 82, 87):
        grille.line([(50, y), (66, y)], 1.6)
    c.paint(grille, DARK, 0.6, shade=0, shadow=0, edge=0)
    c.paint(Shape().poly(rrect(39.5, 50, 43, 64, 1.4)), DARK, shade=0.3, shadow=0.3, edge=0)
    for i, r in enumerate((10, 17, 24)):
        c.paint(Shape().arc(78, 44, r, -48, 48, 2.6), WHITE, 1.0 - 0.2 * i)


def speed_dial(c, value):
    cx, cy, R = 64, 64, 37
    c.paint(Shape().circle(cx, cy, R + 2.6), STEEL)
    c.paint(Shape().circle(cx, cy, R), WHITE, shadow=0, edge=0.5)
    ang = lambda v: 135 + v / 14.0 * 270  # noqa: E731
    c.paint(Shape().arc(cx, cy, R - 4, ang(0), ang(value), 3.0, caps=False), CYAN, shade=0, shadow=0, edge=0)
    ticks = Shape()
    for v in range(15):
        a = math.radians(ang(v))
        r0 = R - 9.5 if v % 2 == 0 else R - 7.5
        ticks.line([(cx + r0 * math.cos(a), cy + r0 * math.sin(a)),
                    (cx + (R - 6) * math.cos(a), cy + (R - 6) * math.sin(a))], 1.6 if v % 2 == 0 else 1.0, caps=False)
    c.paint(ticks, DARK, 0.85, shade=0, shadow=0, edge=0)
    c.paint(Shape().text(cx, cy + 20, str(value), 19), DARK, shade=0, shadow=0, edge=0)
    a = ang(value)
    needle = Shape().poly(tf([(-6, -2.2), (R - 8, 0), (-6, 2.2)], cx, cy, 1.0, a))
    c.paint(needle, RED, shade=0.5, shadow=0.8, edge=0.5)
    c.paint(Shape().circle(cx, cy, 4.2), DARK, shade=0.5, shadow=0.5, edge=0)


def i_days_run(c):
    c.paint(Shape().dashed(ell(64, 78, 36, 36, 180, 360, 80), 1.6, 3.5, 3), HAZE, 0.9, shade=0, shadow=0.4, edge=0)
    for x in (28, 100):
        c.paint(Shape().line([(x, 74), (x, 82)], 1.6), HAZE, shade=0, edge=0)
    sx, sy = 64 + 36 * math.cos(math.radians(305)), 78 + 36 * math.sin(math.radians(305))
    c.glow(sx, sy, 18, AMBER, 0.3)
    c.paint(Shape().circle(sx, sy, 8), AMBER)
    c.fill(Shape().poly([(64, 82.5), (24, 80.5), (24, 82.5)]), WHITE, 0.7)
    yacht(c, 66, 82, 0.6)
    waves(c, [(92, 1.2, 14, 0.0), (101, 1.4, 16, 1.6)], SEAL, 1.8)


def i_supper(c):
    steam = Shape()
    for x in (52, 64, 76):
        steam.line([(x + 2 * math.sin(i / 3.0), 44 - i * 1.3) for i in range(14)], 1.6)
    c.fill(steam, HAZE, 0.75)
    c.paint(Shape().line([(88, 76), (113, 87)], 6.0), DARK)
    c.paint(Shape().circle(60, 72, 32, 20), (88, 96, 100))
    c.paint(Shape().circle(60, 71, 26.5, 15.5), (58, 64, 68), shade=0.6, shadow=0, edge=0)
    paint_fish(c, 60, 71, 0.82, -6, (218, 176, 116), (176, 128, 80), 8.0, 44)


def i_lighthouse(c):
    rays = Shape().poly([(64, 34), (18, 24), (18, 38)]).poly([(64, 34), (110, 24), (110, 38)])
    c.fill(rays, PALE_GOLD, 0.30)
    c.glow(64, 34, 16, AMBER, 0.35)
    rocks = Shape().circle(52, 96, 12, 7).circle(74, 97, 14, 7.5).circle(62, 92, 9, 5)
    tower = Shape().poly([(55, 92), (73, 92), (70.5, 46), (57.5, 46)])
    c.paint(tower, WHITE)
    bands = tower.copy().clip(Shape().poly([(0, 56), (128, 56), (128, 63), (0, 63)]).poly([(0, 72), (128, 72), (128, 79), (0, 79)]))
    c.paint(bands, RED, shade=0.4, shadow=0, edge=0)
    c.paint(Shape().poly([(53, 46.5), (75, 46.5), (75, 43), (53, 43)]), DARK)
    c.paint(Shape().poly([(58, 43), (70, 43), (70, 33), (58, 33)]), AMBER, shade=0.4)
    c.paint(Shape().poly([(56, 33.5), (72, 33.5), (64, 25)]), RED)
    c.paint(Shape().line([(64, 37.5), (64, 43)], 1.0, caps=False).line([(58, 38), (70, 38)], 0.8, caps=False), DARK, 0.6,
            shade=0, shadow=0, edge=0)
    c.paint(rocks, STEEL, shade=0.6)
    waves(c, [(104, 1.4, 14, 0.0)], SEAL, 2.0)


def i_ashore(c):
    bol = Shape().poly(rrect(26, 64, 38, 92, 2)).poly(ell(32, 64, 9, 4.2))
    c.paint(bol, STEEL)
    quay = Shape().poly([(10, 92), (118, 92), (118, 98), (10, 98)])
    c.paint(quay, SAND, shade=0.4)
    waves(c, [(106, 1.3, 14, 0.0)], SEAL, 2.0)
    for i, (x, y, rot) in enumerate(((54, 76, 18), (78, 64, 22), (66, 40, 18), (90, 28, 22))):
        foot(c, x, y, 1.15, rot, WHITE, left=i % 2 == 0)


def planks(c):
    c.fill(Shape().circle(64, 64, 60), (88, 72, 58))
    pl = Shape()
    for y in range(8, 124, 16):
        pl.poly([(0, y), (128, y), (128, y + 14), (0, y + 14)])
    c.paint(pl, TEAK, shade=0.3, shadow=0.5, edge=0.4)
    grain = Shape()
    for i, y in enumerate(range(8, 124, 16)):
        grain.line(sine(4, 124, y + 5 + (i % 3), 0.6, 40, i), 0.6, caps=False)
        x = 18 + (i * 37) % 80
        grain.line([(x, y + 0.5), (x, y + 13.5)], 0.7, caps=False)
    c.fill(grain, DARK, 0.25)


def i_paw_pontoon(c):
    planks(c)
    for x, y, rot in ((38, 92, 20), (58, 70, 30), (76, 52, 20), (96, 32, 30)):
        paw(c, x, y, 1.1, rot)


def i_paw_globe(c):
    globe(c, 64, 64, 33)
    paw(c, 66, 66, 1.45, 8, WHITE)


def i_two_at_sea(c):
    for x, y, r in ((30, 42, 0.9), (40, 28, 1.1), (56, 22, 0.8), (78, 30, 1.0), (96, 40, 0.9), (102, 56, 0.8),
                    (26, 60, 0.8), (88, 22, 0.7), (50, 38, 0.7), (66, 40, 0.8)):
        c.fill(Shape().circle(x, y, r), WHITE, 0.9)
    sparkle(c, 70, 26, 4, WHITE)
    sparkle(c, 36, 48, 3, HAZE)

    def crew(T):
        s = Shape()
        s.circle(*T([(-10, -12)])[0], 2.6)
        s.poly(T([(-13, -6.4), (-7, -6.4), (-8, -10), (-12, -10)]))
        cat = T([(-3.5, -8.4)])[0]
        s.circle(cat[0], cat[1], 2.0)
        s.poly(T([(-5.2, -9.5), (-5, -12.2), (-3.6, -10.2)]))
        s.poly(T([(-3.4, -10.2), (-2, -12.2), (-1.8, -9.5)]))
        s.poly(T([(-5.5, -6.4), (-1.5, -6.4), (-2.4, -8.6), (-4.6, -8.6)]))
        c.paint(s, DARK, shade=0, shadow=0.4, edge=0)
    yacht(c, 64, 88, 1.1, 0, crew=crew)
    waves(c, [(96, 1.1, 14, 0.0), (104, 1.3, 16, 1.4)], SEAL, 1.8)


def i_fish(c):
    paint_fish(c, 64, 64, 1.45, -6)


def i_field_guide(c):
    cover = Shape().poly([(20, 40), (64, 46), (108, 40), (110, 92), (64, 98), (18, 92)])
    c.paint(cover, (66, 84, 74))
    left = Shape().poly([(24, 38)] + bez((24, 38), (40, 36), (56, 38), (64, 44), 10) + [(64, 92)] + bez((64, 92), (54, 86), (40, 85), (24, 87), 10))
    right = Shape().poly([(64, 44)] + bez((64, 44), (72, 38), (88, 36), (104, 38), 10) + [(104, 87)] + bez((104, 87), (88, 85), (74, 86), (64, 92), 10))
    c.paint(left, WHITE)
    c.paint(right, WHITE)
    lines = Shape()
    for y in (52, 59, 66, 73):
        lines.line([(31, y), (56, y + 2.5)], 1.2)
    c.paint(lines, DARK, 0.35, shade=0, shadow=0, edge=0)
    paint_fish(c, 84, 62, 0.62, -6, SEAL, SEAM)
    c.paint(Shape().line([(74, 78), (96, 76)], 1.2), DARK, 0.35, shade=0, shadow=0, edge=0)


def i_trophy_fish(c):
    paint_fish(c, 62, 56, 1.75, -4, WHITE, SEAL, 11.0, 44)
    tape = Shape().poly([(14, 82), (114, 82), (114, 94), (14, 94)])
    c.paint(tape, AMBER, shade=0.5)
    ticks = Shape()
    for i, x in enumerate(range(18, 114, 4)):
        ticks.line([(x, 82.5), (x, 86.5 if i % 5 else 89.5)], 0.9, caps=False)
    c.fill(ticks, DARK, 0.7)


def i_postcards(c):
    def card(cx, cy, rot, col):
        sh = Shape().poly(tf(rrect(-26, -17, 26, 17, 1.5, 2), cx, cy, 1.0, rot))
        c.paint(sh, col)
        return lambda pts: tf(pts, cx, cy, 1.0, rot)  # noqa: E731
    card(58, 74, -14, SAND)
    card(68, 66, 8, HAZE)
    T = card(62, 56, -4, WHITE)
    c.paint(Shape().poly(T([(13, -13), (22, -13), (22, -3), (13, -3)])), RED, shade=0.3, shadow=0.3, edge=0.3)
    c.paint(Shape().line(T([(2, -15), (2, 15)]), 0.8, caps=False), DARK, 0.4, shade=0, shadow=0, edge=0)
    ln = Shape()
    for y in (3, 8, 13):
        ln.line(T([(7, y), (21, y)]), 1.0, caps=False)
    c.paint(ln, DARK, 0.45, shade=0, shadow=0, edge=0)
    pic = Shape().poly(T([(-23, 14)] + sine(-23, -1, 5, 1.5, 9) + [(-1, 14)]))
    c.paint(pic, SEAL, shade=0.3, shadow=0, edge=0)
    c.paint(Shape().circle(*T([(-8, -6)])[0], 3.6), AMBER, shade=0.3, shadow=0, edge=0)


def i_laptop(c):
    c.paint(Shape().poly(rrect(30, 30, 98, 78, 3)), (70, 80, 86))
    c.paint(Shape().poly([(35, 35), (93, 35), (93, 73), (35, 73)]), PANEL, shade=0.2, shadow=0, edge=0)
    c.paint(Shape().line(sine(40, 88, 60, 4, 24, 0.6), 2.2), CYAN, shade=0, shadow=0, edge=0)
    c.paint(Shape().circle(78, 46, 3.4), PALE_GOLD, shade=0, shadow=0, edge=0)
    base = Shape().poly([(26, 79), (102, 79), (112, 92), (16, 92)])
    c.paint(base, HAZE)
    keys = Shape()
    for y in (82.5, 85.5):
        keys.line([(30 - (y - 79) * 0.6, y), (98 + (y - 79) * 0.6, y)], 1.0, caps=False)
    keys.poly([(56, 88.2), (72, 88.2), (72.5, 90.8), (55.5, 90.8)])
    c.fill(keys, DARK, 0.3)


def renown(c, stars):
    for x, y, r in stars:
        c.glow(x, y, r * 1.5, WHITE, 0.12)
        c.paint(Shape().poly(star_pts(x, y, r, r * 0.45, 5)), PALE_GOLD)
    waves(c, [(86, 2.0, 22, 0.4), (96, 2.2, 24, 2.0)], WHITE, 2.4, 22, 106)


def i_renown_250(c):
    renown(c, [(64, 52, 21)])


def i_renown_1000(c):
    renown(c, [(40, 60, 11.5), (88, 60, 11.5), (64, 46, 16.5)])


def i_hat_lost(c):
    wind = Shape()
    for y, x0, x1, ph in ((36, 18, 62, 0.0), (82, 22, 70, 1.0), (94, 50, 104, 2.0)):
        wind.line(sine(x0, x1, y, 1.6, 30, ph), 1.6)
    wind.line(bez((20, 58), (32, 56), (36, 46), (30, 44)), 1.6)
    c.fill(wind, HAZE, 0.75)
    captain_hat(c, 68, 62, 1.05, -24)
    for x, y in ((98, 38), (104, 50)):
        c.fill(Shape().line([(x, y), (x + 6, y - 2)], 1.4), HAZE, 0.7)


def i_hat_storm(c):
    rain(c, 14, 84, 16, 50, 0.55, 9, 7, 0.55)
    captain_hat(c, 58, 74, 1.1, -6)
    skin = (206, 170, 140)
    c.paint(Shape().line([(76, 46), (86, 38)], 8), skin)
    c.paint(Shape().line([(120, 8), (88, 36)], 15, caps=False), (200, 170, 92))
    c.paint(Shape().line([(94, 30.5), (86, 37.5)], 15, caps=False), (178, 150, 80), shade=0.4)
    hand = Shape().poly(tf(ell(0, 0, 12, 8), 70, 50, 1.0, 30))
    for x0, y0, x1, y1 in ((66, 44, 52, 52), (64, 49, 50, 57), (64, 54, 52, 61)):
        hand.line([(x0, y0), (x1, y1)], 4.4)
    hand.poly(tf(ell(0, 0, 7, 3.4), 72, 58, 1.0, -60))
    c.paint(hand, skin)
    wind = Shape()
    for y, x0, x1, ph in ((86, 92, 120, 0.0), (66, 96, 122, 1.4)):
        wind.line(sine(x0, x1, y, 1.4, 22, ph), 1.5)
    c.fill(wind, HAZE, 0.7)
    waves(c, [(100, 2.0, 18, 0.4), (108, 2.0, 18, 2.0)], SEAL, 2.0)


def i_hat_original(c):
    captain_hat(c, 58, 58, 1.1, -4)
    tails = Shape().poly([(84, 84), (78, 106), (84, 102), (88, 107), (90, 86)])
    tails.poly([(92, 86), (98, 106), (101, 100), (106, 103), (98, 82)])
    c.paint(tails, RED, shade=0.5)
    ros = Shape().poly(star_pts(92, 80, 12, 9.5, 14))
    c.paint(ros, RED)
    c.paint(Shape().circle(92, 80, 6.2), PALE_GOLD)


def i_hat_ocean(c):
    c.paint(Shape().line([(10, 48), (118, 48)], 0.9, caps=False), HAZE, 0.6, shade=0, shadow=0, edge=0)
    waves(c, [(56, 0.7, 10, 0.0), (64, 1.0, 13, 1.0)], SEAL, 1.4, 16, 112)
    captain_hat(c, 64, 76, 0.95, 8)
    sea = Shape().poly([(0, 128)] + sine(0, 128, 84, 2.4, 26, 0.3) + [(128, 128)])
    c.paint(sea, SEAM, 0.92, shade=0.4, shadow=0.4, edge=0.5)
    waves(c, [(84, 2.4, 26, 0.3)], WHITE, 1.8, 6, 122, 0.9)
    waves(c, [(98, 1.6, 20, 1.6), (108, 1.6, 20, 3.0)], SEAL, 1.8)


def i_secret(c):
    env = Shape().poly(rrect(32, 44, 96, 86, 2))
    c.paint(env, HAZE)
    flap = Shape()
    flap.line([(33, 45), (64, 68), (95, 45)], 1.2, caps=False)
    flap.line([(33, 85), (56, 64)], 1.0, caps=False)
    flap.line([(95, 85), (72, 64)], 1.0, caps=False)
    c.paint(flap, DARK, 0.35, shade=0, shadow=0, edge=0)
    seal = Shape().poly(star_pts(64, 68, 10.5, 9.4, 12))
    c.paint(seal, (150, 92, 82))
    c.paint(Shape().text(64, 68, "?", 15), (226, 204, 192), shade=0, shadow=0, edge=0)
    rng = np.random.RandomState(13)
    fog = np.zeros((N, N), np.float32)
    for y in (34, 58, 80, 98):
        fog += np.exp(-((YY - y - rng.uniform(-2, 2)) / 5.5) ** 2) * (0.6 + 0.4 * np.sin(XX / 13.0 + y))
    c.over(HAZE, np.clip(fog, 0, 1) * 0.22)


ICONS = {name[2:]: fn for name, fn in globals().items() if name.startswith("i_")}
ICONS["speed_7"] = lambda c: speed_dial(c, 7)
ICONS["speed_9"] = lambda c: speed_dial(c, 9)
ICONS["speed_12"] = lambda c: speed_dial(c, 12)


# --- Main -----------------------------------------------------------------------------

def badge(icon, category):
    disc = CATEGORY[category]
    c = Canvas(disc)
    ICONS[icon](c)
    return compose(c, disc)


def review_sheet(items, path):
    cols = 6
    cell_w, cell_h = 150, 210
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell_w * 2 + 20, rows * cell_h), (236, 238, 236))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(FONT, 14)
    for half, grey in ((0, False), (1, True)):
        for i, (icon, img) in enumerate(items):
            x = half * (cols * cell_w + 20) + (i % cols) * cell_w
            y = (i // cols) * cell_h
            im = img
            if grey:
                g = ImageOps.grayscale(img.convert("RGB")).convert("RGB")
                g = Image.blend(g, Image.new("RGB", g.size, (128, 128, 128)), 0.25)
                im = Image.merge("RGBA", (*g.split(), img.split()[3]))
            bg = (40, 52, 60) if (i // cols) % 2 else (236, 238, 236)
            d.rectangle([x, y, x + cell_w - 1, y + cell_h - 1], fill=bg)
            sheet.paste(im, (x + 11, y + 6), im)
            sm = im.resize((48, 48), Image.LANCZOS)
            sheet.paste(sm, (x + 11, y + 140), sm)
            sm2 = im.resize((64, 64), Image.LANCZOS)
            sheet.paste(sm2, (x + 70, y + 132), sm2)
            d.text((x + 75, y + 200), icon, fill=(200, 60, 60), font=font, anchor="mm")
    sheet.save(path)


def main():
    with open(DATA, encoding="utf-8") as f:
        data = json.load(f)
    todo = []
    for a in data["achievements"]:
        if a["icon"] not in [t[0] for t in todo]:
            todo.append((a["icon"], a["category"]))
    todo.append(("secret", "secret"))
    missing = [i for i, _ in todo if i not in ICONS]
    if missing:
        sys.exit("No painter for icons: %s" % ", ".join(missing))
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(REVIEW, exist_ok=True)
    items = []
    for icon, cat in todo:
        img = badge(icon, cat)
        img.save(os.path.join(OUT, icon + ".png"), optimize=True)
        items.append((icon, img))
    review_sheet(items, os.path.join(REVIEW, "sheet.png"))
    print("Wrote %d badges to %s; review sheet %s" % (len(items), OUT, os.path.join(REVIEW, "sheet.png")))


if __name__ == "__main__":
    main()
