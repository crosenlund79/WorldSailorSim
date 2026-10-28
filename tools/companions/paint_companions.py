"""Paints the ship's cat and dog (Iteration 13; Real Horizon look).

The companions are drawn like the rest of the Real Horizon art (see
DEV_GUIDES/ART_DIRECTION.md): a grounded maritime illustration, "visual
realism 7/10". They are seen from above and a little in front, so their faces
read at the small size they have in the cabin. Anatomy and proportions follow
real animals (a smaller head, a long body, slim legs and a tapering tail for
the cat; a tan-and-white, floppy-eared dog with a proper muzzle), and fur is
painted with soft tonal washes and many short directional strokes that follow
the lie of the coat. There are no thick outlines: edges come from tone (a
darker rim, soft contact shadows where one part lies on another) and at most
a faint blue-grey line. Eyes are small and realistic.

Every pose is painted on the same 256 x 256 canvas with the animal in the
same place, so poses line up when the game cross-fades between them (see
CompanionVisualSet).

Poses (the names CompanionVisualSet uses):
  resting     idle: lying with the head up on the paws, eyes half open
  sleeping    asleep: curled up (cat) / on its side (dog), eyes closed
  alert       sitting up and looking up (also shown when petted; the game
              draws any hearts itself, none are painted here)
  stretching  a long stretch, front paws forward

Writes assets/companions/<kind>/<pose>.png. The owner's original cat drawings
in Visuals/Cat are never read or changed.

Usage: python3 tools/companions/paint_companions.py
Requirements: Python 3 with Pillow and numpy.
"""
import math
import os

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "companions")
N = 256          # final canvas, px
SS = 4           # supersampling while painting
LINE = (42, 50, 54)     # the art direction's thin line: dark blue-grey
SHADOW = (24, 32, 38)

# A grey (mackerel) tabby: cool grey with darker bars, paler chin and chest.
CAT = {
    "fur": (126, 124, 118), "light": (176, 172, 162), "dark": (62, 62, 60), "stripe": (58, 58, 56),
    "pale": (206, 200, 186), "paw": (150, 146, 138), "ear": (184, 150, 140), "nose": (168, 116, 106),
    "iris": (150, 148, 84), "pupil": (18, 20, 18),
}
# A tan-and-white, floppy-eared hound (beagle type), in natural tones.
DOG = {
    "fur": (164, 118, 76), "light": (198, 156, 110), "dark": (104, 72, 46), "white": (226, 220, 204),
    "ear": (120, 82, 52), "nose": (40, 34, 32), "eye": (48, 32, 24), "tongue": (192, 116, 112),
    "collar": (132, 64, 54), "brass": (176, 150, 92),
}


# --- Drawing helpers (design units are final pixels) ------------------------------

def blank():
    return Image.new("L", (N * SS, N * SS), 0)


def _p(points):
    return [(x * SS, y * SS) for x, y in points]


def ellipse_points(c, r, angle=0.0, steps=72):
    a = math.radians(angle)
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        x, y = r[0] * math.cos(t), r[1] * math.sin(t)
        pts.append((c[0] + x * math.cos(a) - y * math.sin(a), c[1] + x * math.sin(a) + y * math.cos(a)))
    return pts


def ell(c, r, angle=0.0):
    m = blank()
    ImageDraw.Draw(m).polygon(_p(ellipse_points(c, r, angle)), fill=255)
    return m


def poly(points):
    m = blank()
    ImageDraw.Draw(m).polygon(_p(points), fill=255)
    return m


def bezier(points, steps=40):
    """A smooth curve through control points (quadratic B-spline style)."""
    if len(points) == 2:
        (x0, y0), (x1, y1) = points
        return [(x0 + (x1 - x0) * k / steps, y0 + (y1 - y0) * k / steps) for k in range(steps + 1)]
    if len(points) < 2:
        return points
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
    """A soft tapering tube along a smooth curve (tails, legs)."""
    w1 = w0 if w1 is None else w1
    curve = bezier(points)
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


def grow(m, px):
    return m.filter(ImageFilter.MaxFilter(max(3, int(px * SS) | 1)))


def shrink(m, px):
    return m.filter(ImageFilter.MinFilter(max(3, int(px * SS) | 1)))


def arr(m):
    return np.asarray(m, dtype=np.float32) / 255.0


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def _noise(rng, cells):
    size = N * SS
    n = rng.normal(0.0, 1.0, (max(size // cells, 2), max(size // cells, 2))).astype(np.float32)
    img = Image.fromarray(((n * 40) + 128).clip(0, 255).astype(np.uint8)).resize((size, size), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 128.0 - 1.0


def away(origin, bend=0.0):
    """A fur direction: lying away from `origin` (degrees), bent a little."""
    def f(x, y):
        return math.degrees(math.atan2(y - origin[1], x - origin[0])) + bend
    return f


def along(angle):
    return lambda x, y: angle


class Painter:
    def __init__(self, seed=7):
        self.img = Image.new("RGBA", (N * SS, N * SS), (0, 0, 0, 0))
        self.silhouette = blank()
        self.rng = np.random.default_rng(seed)
        self.grain = _noise(self.rng, 4)
        self.mottle = _noise(self.rng, 40)
        self.yy, self.xx = np.mgrid[0:N * SS, 0:N * SS].astype(np.float32)

    def put(self, rgb, alpha):
        a = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)
        self.img.alpha_composite(Image.fromarray(np.dstack([np.clip(rgb, 0, 255).astype(np.uint8), a]), "RGBA"))

    def ink(self, mask, colour=LINE, alpha=200):
        a = (np.array(mask, dtype=np.float32) * alpha / 255.0).astype(np.uint8)
        layer = Image.new("RGBA", self.img.size, tuple(colour) + (0,))
        layer.putalpha(Image.fromarray(a))
        self.img.alpha_composite(layer)

    def line(self, points, width, colour=LINE, alpha=170):
        self.ink(tube(points, width), colour, alpha)

    def dot(self, c, r, colour, alpha=255):
        self.ink(ell(c, (r, r)), colour, alpha)

    def contact(self, mask, dx=1.5, dy=2.5, blur=2.5, alpha=110):
        """A soft shadow that `mask` casts onto what is already painted."""
        sh = ImageChops.offset(soft(mask, blur), int(dx * SS), int(dy * SS))
        self.ink(clip(sh, self.silhouette), SHADOW, alpha)

    def fill(self, mask, colour, light=(0.3, 0.25), shade=0.32, rim=0.2, edge=40, alpha=1.0, contact=True):
        """A soft gouache wash in `mask`: lit from the upper left, darker
        towards its rim, with a little grain; a faint blue-grey edge."""
        box = mask.getbbox()
        if not box:
            return
        if contact:
            self.contact(mask)
        cx = box[0] + (box[2] - box[0]) * light[0]
        cy = box[1] + (box[3] - box[1]) * light[1]
        size = max(box[2] - box[0], box[3] - box[1])
        d = np.sqrt((self.xx - cx) ** 2 + (self.yy - cy) ** 2) / max(size, 1)
        f = (1.08 - d * shade * 1.5).clip(1.0 - shade, 1.1)
        inner = arr(soft(mask, 3.0))
        f = f - rim * (1.0 - inner) + self.grain * 0.02 + self.mottle * 0.03
        rgb = np.array(colour, dtype=np.float32)[None, None, :] * f[:, :, None]
        self.put(rgb, arr(mask) * alpha)
        self.silhouette = union(self.silhouette, mask)
        if edge:
            ring = soft(minus(mask, shrink(mask, 0.9)), 0.3)
            self.ink(ring, LINE, edge)

    def patch(self, mask, colour, alpha=1.0, blur=1.2, light=(0.3, 0.25), shade=0.18):
        """A soft-edged coat patch (white chest, blaze) inside earlier fills."""
        m = soft(mask, blur)
        box = m.getbbox()
        if not box:
            return
        cx = box[0] + (box[2] - box[0]) * light[0]
        cy = box[1] + (box[3] - box[1]) * light[1]
        size = max(box[2] - box[0], box[3] - box[1])
        d = np.sqrt((self.xx - cx) ** 2 + (self.yy - cy) ** 2) / max(size, 1)
        f = (1.05 - d * shade * 1.5).clip(1.0 - shade, 1.08) + self.grain * 0.02
        rgb = np.array(colour, dtype=np.float32)[None, None, :] * f[:, :, None]
        self.put(rgb, arr(clip(m, self.silhouette)) * alpha)

    def fur(self, mask, flow, light, dark, n=None, length=(2.0, 4.0), width=0.7, alpha=(0.34, 0.26), jitter=14, lit=(0.3, 0.25),
            region=None):
        """Short directional strokes: lighter ones towards the light, darker
        ones away from it. `flow(x, y)` gives the lie of the coat (degrees)."""
        m = mask if region is None else clip(mask, region)
        a = np.asarray(m.resize((N, N), Image.BILINEAR))
        ys, xs = np.nonzero(a > 100)
        if len(xs) == 0:
            return
        n = n or int(len(xs) * 0.65)
        idx = self.rng.integers(0, len(xs), n)
        box = mask.getbbox()
        bx0, by0, bx1, by1 = [v / SS for v in box]
        lx, ly = bx0 + (bx1 - bx0) * lit[0], by0 + (by1 - by0) * lit[1]
        span = max(bx1 - bx0, by1 - by0)
        lite_m, dark_m = blank(), blank()
        dl, dd = ImageDraw.Draw(lite_m), ImageDraw.Draw(dark_m)
        for i in idx:
            x = xs[i] + self.rng.uniform(0, 1)
            y = ys[i] + self.rng.uniform(0, 1)
            ang = math.radians(flow(x, y) + self.rng.normal(0, jitter))
            L = self.rng.uniform(*length)
            x1, y1 = x + math.cos(ang) * L, y + math.sin(ang) * L
            near = 1.0 - min(math.hypot(x - lx, y - ly) / span, 1.0)
            target = dl if self.rng.uniform() < 0.25 + 0.55 * near else dd
            w = max(1, int(width * SS))
            target.line([(x * SS, y * SS), ((x + x1) / 2 * SS, (y + y1) / 2 * SS)], fill=255, width=w)
            target.line([((x + x1) / 2 * SS, (y + y1) / 2 * SS), (x1 * SS, y1 * SS)], fill=255, width=max(1, w // 2))
        inner = soft(shrink(mask, 0.6), 0.4)
        self.ink(clip(soft(lite_m, 0.15), inner), light, int(255 * alpha[0]))
        self.ink(clip(soft(dark_m, 0.15), inner), dark, int(255 * alpha[1]))

    def edge_fur(self, mask, flow, colour, n=90, length=(1.2, 2.6)):
        """Fine hairs breaking the outline, so it does not read as a cut-out."""
        ring = minus(mask, shrink(mask, 2.2))
        a = np.asarray(ring.resize((N, N), Image.BILINEAR))
        ys, xs = np.nonzero(a > 60)
        if len(xs) == 0:
            return
        hairs = blank()
        d = ImageDraw.Draw(hairs)
        for i in self.rng.integers(0, len(xs), n):
            x, y = xs[i] + 0.5, ys[i] + 0.5
            ang = math.radians(flow(x, y) + self.rng.normal(0, 18))
            L = self.rng.uniform(*length)
            d.line([(x * SS, y * SS), ((x + math.cos(ang) * L) * SS, (y + math.sin(ang) * L) * SS)], fill=255, width=max(1, int(0.6 * SS)))
        self.ink(soft(hairs, 0.15), colour, 150)
        self.silhouette = union(self.silhouette, hairs)

    def stripes(self, body, bands, colour, flow, alpha=0.6):
        """Tabby bars: soft, broken bands with ragged furry edges. Each band
        bends a little and tapers (stripes follow the barrel of the body)."""
        m = blank()
        for pts, w in bands:
            if len(pts) == 2:
                (x0, y0), (x1, y1) = pts
                mx, my = (x0 + x1) / 2, (y0 + y1) / 2
                L = math.hypot(x1 - x0, y1 - y0)
                if L > 14:   # bow long bars gently toward the tail (left)
                    pts = [(x0, y0), (mx - L * 0.08, my), (x1, y1)]
            m = union(m, tube(pts, w * 0.8, w * 0.4))
        m = clip(m, shrink(body, 1.0))
        broken = arr(soft(m, 0.9)) * (0.75 + 0.35 * self.mottle).clip(0.4, 1.1)
        rgb = np.broadcast_to(np.array(colour, np.float32), broken.shape + (3,))
        self.put(rgb, broken * alpha)
        self.fur(clip(grow(m, 1.4), body), flow, colour, colour, length=(1.8, 3.4), alpha=(0.0, 0.35), jitter=10)

    def finish(self, path):
        # A soft shadow under the animal, like the boats' fixtures.
        shadow = soft(self.silhouette, 4)
        shadow = ImageChops.offset(shadow, 3 * SS, 5 * SS)
        sh = Image.new("RGBA", self.img.size, SHADOW + (0,))
        sh.putalpha(shadow.point(lambda v: int(v * 0.26)))
        out = Image.alpha_composite(sh, self.img)
        out = out.resize((N, N), Image.LANCZOS)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        out.save(path)
        print("wrote", os.path.relpath(path, ROOT))


# --- The cat's head ---------------------------------------------------------------------

def cat_eye(p, e, s, side, state):
    """A small almond eye: green-gold iris, slit pupil, one highlight."""
    if state == "closed":
        p.line([(e[0] - 3.4 * s, e[1] - 0.2 * s), (e[0], e[1] + 1.0 * s), (e[0] + 3.4 * s, e[1] - 0.2 * s)], 0.8 * s, CAT["dark"], 210)
        return
    shape = ell(e, (3.3 * s, 2.3 * s), -side * 10)
    iris = np.array(CAT["iris"], np.float32)
    shade = ((p.yy / SS - (e[1] - 2.3 * s)) / (4.6 * s)).clip(0, 1)
    p.put(iris[None, None, :] * (0.78 + 0.36 * shade)[..., None], arr(shape))      # darker under the lid
    p.ink(clip(ell((e[0], e[1]), (0.75 * s, 2.1 * s)), shape), CAT["pupil"], 245)
    p.ink(soft(minus(shape, shrink(shape, 0.7 * s)), 0.15), (30, 30, 28), 220)   # the dark rim cats have
    if state == "half":
        lid = ell((e[0], e[1] - 2.3 * s), (4.4 * s, 2.5 * s), -side * 10)
        p.ink(clip(soft(lid, 0.2), grow(shape, 1.0)), CAT["fur"], 255)
        p.line([(e[0] - 3.3 * s, e[1] - 0.2 * s), (e[0], e[1] - 0.6 * s), (e[0] + 3.3 * s, e[1] - 0.2 * s)], 0.8 * s, CAT["dark"], 220)
    else:
        p.dot((e[0] - 0.9 * s, e[1] - 0.8 * s), 0.55 * s, (250, 250, 244), 235)
    # the dark tear-line running down from the inner corner (tabby marking)
    inner = (e[0] - side * 3.0 * s, e[1] + 0.6 * s)
    p.line([inner, (inner[0] - side * 0.6 * s, inner[1] + 2.6 * s)], 0.6 * s, CAT["dark"], 110)


def cat_head(p, c, s=1.0, eyes="open", ears_angle=0.0, tilt=0.0):
    """A cat's head seen from above and in front: a rounded wedge, ears set
    wide, a short muzzle; tabby 'M' on the brow."""
    head = union(ell(c, (19 * s, 16 * s), tilt), ell((c[0], c[1] + 5 * s), (14 * s, 12 * s), tilt))
    ears = []
    for side in (-1, 1):
        a = math.radians(ears_angle * side)
        base = (c[0] + side * 11 * s, c[1] - 10 * s)
        tip = (c[0] + side * 17 * s + math.sin(a) * 5 * s, c[1] - 26 * s + abs(math.sin(a)) * 3 * s)
        outer = poly(bezier([(base[0] - side * 7.5 * s, base[1] + 3 * s), (tip[0] - side * 1.5 * s, tip[1] + 4 * s), tip,
                             (tip[0] + side * 1.2 * s, tip[1] + 4 * s), (base[0] + side * 8.5 * s, base[1] + 5 * s)], 10))
        ears.append((outer, base, tip, side))
    for outer, base, tip, side in ears:
        p.fill(outer, CAT["fur"], edge=45)
        inner = poly(bezier([(base[0] - side * 4.5 * s, base[1] + 2 * s), (tip[0] - side * 0.4 * s, tip[1] + 5.5 * s),
                             (base[0] + side * 5.5 * s, base[1] + 3 * s)], 8))
        p.patch(clip(inner, outer), CAT["ear"], alpha=0.85, blur=0.8)
        p.fur(inner, away((base[0], base[1] + 6 * s), 0), CAT["pale"], CAT["dark"], n=40, length=(1.6, 3.2), alpha=(0.6, 0.2))
    p.fill(head, CAT["fur"], light=(0.32, 0.2), edge=40)
    nose = (c[0], c[1] + 6.5 * s)
    p.fur(head, away((nose[0], nose[1] - 4 * s)), CAT["light"], CAT["dark"], length=(1.6, 3.2), alpha=(0.45, 0.35))
    # paler muzzle, chin and the fur around the eyes
    muzzle = union(ell((c[0] - 4.2 * s, c[1] + 8.5 * s), (5.6 * s, 4.4 * s)), ell((c[0] + 4.2 * s, c[1] + 8.5 * s), (5.6 * s, 4.4 * s)),
                   ell((c[0], c[1] + 12.5 * s), (5 * s, 3.4 * s)))
    p.patch(clip(muzzle, head), CAT["pale"], alpha=0.9, blur=1.2)
    for side in (-1, 1):
        p.patch(ell((c[0] + side * 7.5 * s, c[1] + 0.5 * s), (5.2 * s, 3.6 * s)), CAT["light"], alpha=0.55, blur=1.4)
    # tabby markings: the 'M' on the brow, lines from the eyes over the cheeks
    for k, dx in enumerate((-5.5, -2, 2, 5.5)):
        p.ink(clip(soft(tube([(c[0] + dx * s, c[1] - 14 * s), (c[0] + dx * 0.8 * s, c[1] - 7.5 * s)], 1.5 * s, 0.7 * s), 0.4), head),
              CAT["stripe"], 170)
    for side in (-1, 1):
        p.ink(clip(soft(tube([(c[0] + side * 11 * s, c[1] + 1 * s), (c[0] + side * 15.5 * s, c[1] + 2.5 * s), (c[0] + side * 18 * s, c[1] + 0.5 * s)],
                             1.3 * s, 0.6 * s), 0.4), head), CAT["stripe"], 150)
        p.ink(clip(soft(tube([(c[0] + side * 9 * s, c[1] + 5 * s), (c[0] + side * 16 * s, c[1] + 7 * s)], 1.1 * s, 0.5 * s), 0.4), head),
              CAT["stripe"], 120)
    for side in (-1, 1):
        cat_eye(p, (c[0] + side * 7.2 * s, c[1] - 0.2 * s), s, side, eyes)
    # nose leather, the line down to the mouth, the mouth
    p.ink(soft(poly([(nose[0] - 2.4 * s, nose[1] - 1.4 * s), (nose[0] + 2.4 * s, nose[1] - 1.4 * s), (nose[0], nose[1] + 1.4 * s)]), 0.25),
          CAT["nose"], 245)
    p.ink(soft(ell((nose[0] - 0.6 * s, nose[1] - 0.9 * s), (0.8 * s, 0.4 * s)), 0.15), (214, 176, 166), 160)
    p.line([(nose[0], nose[1] + 1.2 * s), (nose[0], nose[1] + 3 * s)], 0.5 * s, CAT["dark"], 150)
    for side in (-1, 1):
        p.line([(nose[0], nose[1] + 3 * s), (nose[0] + side * 1.6 * s, nose[1] + 4.0 * s), (nose[0] + side * 3.2 * s, nose[1] + 3.5 * s)],
               0.5 * s, CAT["dark"], 140)
    for side in (-1, 1):  # fine pale whiskers
        for k in range(3):
            y0 = nose[1] + (1.6 + k * 1.3) * s
            p.line([(nose[0] + side * 4.5 * s, y0), (nose[0] + side * 12 * s, y0 + (k - 1.4) * 1.4 * s),
                    (nose[0] + side * 19 * s, y0 + (k - 1.2) * 3.0 * s)], 0.35 * s, (232, 230, 222), 150)
    p.edge_fur(head, away((c[0], c[1] + 2 * s)), CAT["fur"], n=70)
    return head


def cat_body(p, mask, origin, bands, light_side=(0.3, 0.25)):
    p.fill(mask, CAT["fur"], light=light_side)
    p.fur(mask, away(origin), CAT["light"], CAT["dark"], alpha=(0.3, 0.24))
    p.stripes(mask, bands, CAT["stripe"], away(origin))
    p.edge_fur(mask, away(origin), CAT["fur"])


def cat_paw(p, c, r, angle=0.0, flow=0.0):
    m = ell(c, r, angle)
    p.fill(m, CAT["paw"], edge=35)
    p.fur(m, along(flow), CAT["light"], CAT["dark"], n=40, length=(1.4, 2.6), alpha=(0.45, 0.25))
    # the toes: two faint creases
    for k in (-1, 1):
        ox = c[0] + math.cos(math.radians(angle)) * r[0] * 0.55
        oy = c[1] + math.sin(math.radians(angle)) * r[0] * 0.55
        dx, dy = -math.sin(math.radians(angle)) * k * r[1] * 0.35, math.cos(math.radians(angle)) * k * r[1] * 0.35
        p.line([(ox + dx, oy + dy), (ox + dx - math.cos(math.radians(angle)) * 2.2, oy + dy - math.sin(math.radians(angle)) * 2.2)],
               0.5, CAT["dark"], 110)
    return m


def cat_tail(p, pts, w0, w1, rings):
    t = tube(pts, w0, w1)
    p.fill(t, CAT["fur"], edge=40)
    curve = bezier(pts)
    p.fur(t, lambda x, y: _along_curve(curve, x, y), CAT["light"], CAT["dark"], alpha=(0.4, 0.3))
    bands = []
    for f in rings:
        i = int(f * (len(curve) - 2))
        (x0, y0), (x1, y1) = curve[i], curve[i + 1]
        a = math.atan2(y1 - y0, x1 - x0) + math.pi / 2
        w = (w0 + (w1 - w0) * f) * 0.7
        bands.append(([(x0 - math.cos(a) * w, y0 - math.sin(a) * w), (x0 + math.cos(a) * w, y0 + math.sin(a) * w)], 3.4 - f))
    p.stripes(t, bands, CAT["stripe"], lambda x, y: _along_curve(curve, x, y), alpha=0.75)
    tip = curve[-1]
    p.ink(clip(soft(ell(tip, (w1 * 0.9, w1 * 0.9)), 1.0), t), CAT["stripe"], 200)   # the dark tail tip
    p.edge_fur(t, lambda x, y: _along_curve(curve, x, y) + 30, CAT["fur"], n=60)
    return t


def _along_curve(curve, x, y):
    best, bi = 1e9, 0
    for i in range(0, len(curve) - 1, 3):
        d = (curve[i][0] - x) ** 2 + (curve[i][1] - y) ** 2
        if d < best:
            best, bi = d, i
    j = min(bi + 1, len(curve) - 1)
    return math.degrees(math.atan2(curve[j][1] - curve[bi][1], curve[j][0] - curve[bi][0] + 1e-6))


# --- The cat --------------------------------------------------------------------------

def cat_resting(path):
    """Lying like a loaf, head up, paws tucked in front, tail round the side."""
    p = Painter(1)
    cat_tail(p, [(74, 152), (60, 188), (104, 204), (160, 202)], 13, 7, (0.25, 0.42, 0.58, 0.74, 0.88))
    body = union(ell((118, 150), (56, 38), -8), ell((84, 160), (32, 31)))
    cat_body(p, body, (176, 140), [([(80, 116), (72, 140), (76, 166)], 6), ([(98, 110), (92, 136), (96, 166)], 6),
                                    ([(116, 108), (114, 132), (118, 160)], 6), ([(134, 112), (136, 134)], 5),
                                    ([(64, 140), (60, 160)], 5), ([(110, 112), (140, 112)], 2.4), ([(70, 128), (112, 108)], 3.0)])
    chest = ell((166, 166), (17, 14))
    p.patch(chest, CAT["pale"], alpha=0.75, blur=3)
    for x0, c in ((150, (154, 183)), (180, (180, 184))):
        leg = tube([(x0, 168), (c[0] - 2, c[1])], 10, 9)
        p.fill(leg, CAT["fur"], edge=30)
        p.fur(leg, along(80), CAT["light"], CAT["dark"], n=70, alpha=(0.3, 0.24))
        cat_paw(p, c, (7.5, 6), 10, 10)
    cat_head(p, (166, 140), 1.12, "half", ears_angle=-4)
    p.finish(path)


def cat_sleeping(path):
    """Curled into a round bed, nose tucked to the tail, eyes closed."""
    p = Painter(2)
    body = union(ell((128, 146), (62, 50)), ell((150, 136), (40, 40)))
    cat_body(p, body, (110, 166), [([(82, 108), (70, 140), (78, 178)], 7), ([(104, 98), (96, 132), (102, 180)], 7),
                                    ([(128, 94), (126, 120)], 6), ([(152, 98), (164, 120)], 6), ([(174, 112), (186, 134)], 5),
                                    ([(88, 104), (160, 96)], 3.2)])
    # the hind leg folded along the flank
    haunch = ell((168, 162), (24, 18), -30)
    p.fill(haunch, CAT["fur"], edge=30)
    p.fur(haunch, away((150, 150)), CAT["light"], CAT["dark"], alpha=(0.4, 0.3))
    p.stripes(haunch, [([(156, 150), (166, 166)], 4), ([(170, 148), (180, 162)], 4)], CAT["stripe"], away((150, 150)))
    cat_paw(p, (146, 184), (9, 6), -10)
    cat_head(p, (110, 166), 1.0, "closed", ears_angle=14, tilt=-8)
    cat_tail(p, [(190, 150), (198, 184), (160, 204), (106, 202), (78, 190)], 13, 7, (0.2, 0.36, 0.52, 0.68, 0.84))
    p.finish(path)


def cat_alert(path):
    """Sitting up, front legs straight, looking up attentively."""
    p = Painter(3)
    cat_tail(p, [(156, 196), (192, 198), (204, 172)], 11, 6.5, (0.3, 0.55, 0.78))
    body = union(ell((128, 170), (38, 32)), ell((128, 142), (26, 28)))
    cat_body(p, body, (128, 112), [([(96, 160), (100, 186)], 5.5), ([(160, 160), (156, 186)], 5.5), ([(104, 140), (108, 160)], 4.5),
                                    ([(152, 140), (148, 160)], 4.5), ([(92, 176), (98, 194)], 4)], light_side=(0.35, 0.2))
    p.patch(ell((128, 150), (14, 20)), CAT["pale"], alpha=0.8, blur=3)
    for x in (116, 140):
        leg = tube([(x, 160), (x, 192)], 10, 9)
        p.fill(leg, CAT["fur"], edge=30)
        p.fur(leg, along(90), CAT["light"], CAT["dark"], n=120, alpha=(0.4, 0.3))
        p.stripes(leg, [([(x - 5, 172), (x + 5, 172)], 2.2), ([(x - 5, 181), (x + 5, 181)], 2.0)], CAT["stripe"], along(90), alpha=0.5)
        cat_paw(p, (x, 196), (6.5, 5.5), 90, 90)
    cat_head(p, (128, 110), 1.2, "open", ears_angle=-6)
    p.finish(path)


def cat_stretching(path):
    """The long stretch: front legs reaching forward, hindquarters up behind."""
    p = Painter(4)
    cat_tail(p, [(62, 146), (42, 124), (44, 92), (58, 78)], 12, 6.5, (0.2, 0.4, 0.6, 0.8))
    for y in (132, 164):
        leg = tube([(96, y), (80, y + 6)], 14, 11)
        p.fill(leg, CAT["fur"], edge=35)
        p.fur(leg, along(170), CAT["light"], CAT["dark"], n=150, alpha=(0.4, 0.3))
        cat_paw(p, (76, y + 7), (6.5, 5), 180, 180)
    body = union(ell((120, 148), (54, 27), -4), ell((86, 146), (26, 28)))
    cat_body(p, body, (180, 150), [([(86, 122), (82, 170)], 6), ([(106, 122), (104, 172)], 6), ([(126, 122), (126, 170)], 6),
                                    ([(146, 126), (148, 166)], 5), ([(70, 132), (160, 124)], 3.0)])
    for y in (158, 178):
        leg = tube([(158, y - 2), (210, y + 4)], 10.5, 8.5)
        p.fill(leg, CAT["fur"], edge=35)
        p.fur(leg, along(5), CAT["light"], CAT["dark"], n=150, alpha=(0.4, 0.3))
        p.stripes(leg, [([(176, y - 5), (176, y + 5)], 2.2), ([(194, y - 3), (194, y + 7)], 2.0)], CAT["stripe"], along(5), alpha=0.5)
        cat_paw(p, (213, y + 4), (7.5, 6), 4, 4)
    cat_head(p, (178, 150), 1.05, "closed", ears_angle=-16)
    p.finish(path)


# --- The dog --------------------------------------------------------------------------

def dog_head(p, c, s=1.0, eyes="open", tongue=False, ears_up=0.0):
    """A hound's head from above and in front: a domed skull, a long muzzle
    towards the viewer, soft ears hanging at the sides, a white blaze."""
    for side in (-1, 1):
        ear = tube([(c[0] + side * 13 * s, c[1] - 10 * s), (c[0] + side * (21 + ears_up * 3) * s, c[1] - (1 + ears_up * 4) * s),
                    (c[0] + side * 20 * s, c[1] + 14 * s)], 11 * s, 9.5 * s)
        p.fill(ear, DOG["ear"], light=(0.5 - side * 0.2, 0.2), edge=45)
        p.fur(ear, along(90 - side * 8), DOG["fur"], DOG["dark"], length=(2.0, 4.0), alpha=(0.4, 0.4), jitter=8)
    skull = ell((c[0], c[1] - 2 * s), (17 * s, 15 * s))
    muzzle = union(ell((c[0], c[1] + 10 * s), (10.5 * s, 10 * s)), ell((c[0], c[1] + 4 * s), (13 * s, 9 * s)))
    head = union(skull, muzzle)
    p.fill(head, DOG["fur"], light=(0.32, 0.18), edge=40)
    nose = (c[0], c[1] + 15 * s)
    p.fur(head, away((nose[0], nose[1] + 2 * s)), DOG["light"], DOG["dark"], length=(1.4, 2.8), alpha=(0.35, 0.3))
    blaze = union(ell((c[0], c[1] + 11 * s), (8.5 * s, 8 * s)),
                  poly([(c[0] - 2.2 * s, c[1] - 16 * s), (c[0] + 2.2 * s, c[1] - 16 * s), (c[0] + 4.5 * s, c[1] + 4 * s), (c[0] - 4.5 * s, c[1] + 4 * s)]))
    p.patch(clip(blaze, head), DOG["white"], alpha=0.95, blur=1.0)
    p.fur(clip(grow(blaze, 1.0), head), away((nose[0], nose[1])), DOG["white"], mix(DOG["white"], DOG["dark"], 0.35), n=160,
          length=(1.2, 2.4), alpha=(0.3, 0.25))
    # the stop and the brow: soft tone, not lines
    for side in (-1, 1):
        e = (c[0] + side * 7.5 * s, c[1] - 1 * s)
        p.ink(soft(ell((e[0], e[1] - 3.2 * s), (4.5 * s, 2.0 * s)), 1.0), DOG["dark"], 70)
        p.ink(soft(ell((e[0], e[1] + 0.6 * s), (4.4 * s, 3.4 * s)), 1.0), DOG["dark"], 55)
        if eyes == "open":
            eye = ell(e, (2.7 * s, 2.3 * s), side * 8)
            p.ink(eye, DOG["eye"], 255)
            p.ink(clip(ell((e[0] + 0.3 * s, e[1] + 0.3 * s), (1.6 * s, 1.5 * s)), eye), (20, 14, 12), 240)
            p.ink(soft(minus(eye, shrink(eye, 0.6 * s)), 0.15), (24, 18, 16), 220)
            p.dot((e[0] - 0.8 * s, e[1] - 0.8 * s), 0.55 * s, (248, 244, 236), 230)
        else:
            p.line([(e[0] - 2.8 * s, e[1] - 0.2 * s), (e[0], e[1] + 0.9 * s), (e[0] + 2.8 * s, e[1] - 0.2 * s)], 0.8 * s, (44, 32, 26), 210)
    # nose, philtrum, mouth
    nm = soft(union(ell(nose, (4.2 * s, 3.0 * s)), ell((nose[0], nose[1] + 1.2 * s), (2.6 * s, 2.2 * s))), 0.2)
    p.ink(nm, DOG["nose"], 250)
    p.ink(soft(ell((nose[0] - 1.2 * s, nose[1] - 1.2 * s), (1.6 * s, 0.8 * s)), 0.3), (120, 112, 106), 170)
    for side in (-1, 1):
        p.ink(soft(ell((nose[0] + side * 1.8 * s, nose[1] + 0.6 * s), (0.8 * s, 0.6 * s)), 0.15), (14, 12, 12), 230)
    p.line([(nose[0], nose[1] + 2.6 * s), (nose[0], nose[1] + 5 * s)], 0.5 * s, (70, 56, 48), 160)
    p.line([(nose[0] - 5.5 * s, nose[1] + 4.6 * s), (nose[0], nose[1] + 5.2 * s), (nose[0] + 5.5 * s, nose[1] + 4.6 * s)], 0.55 * s, (70, 56, 48), 150)
    if tongue:
        t = ell((nose[0], nose[1] + 8.4 * s), (2.8 * s, 3.4 * s))
        p.fill(t, DOG["tongue"], contact=False, edge=60)
        p.line([(nose[0], nose[1] + 6.2 * s), (nose[0], nose[1] + 9.6 * s)], 0.4 * s, (140, 76, 72), 150)
    p.edge_fur(head, away((c[0], c[1] + 4 * s)), DOG["fur"], n=50)
    return head


def dog_body(p, mask, origin, belly=None, light_side=(0.3, 0.25)):
    p.fill(mask, DOG["fur"], light=light_side)
    p.fur(mask, away(origin), DOG["light"], DOG["dark"], length=(1.8, 3.4), alpha=(0.28, 0.22))
    if belly is not None:
        p.patch(clip(belly, mask), DOG["white"], alpha=0.95, blur=2.5)
        p.fur(clip(grow(belly, 1.0), mask), away(origin), DOG["white"], mix(DOG["white"], DOG["dark"], 0.3), n=200,
              length=(1.6, 3.0), alpha=(0.3, 0.25))
    p.edge_fur(mask, away(origin), DOG["fur"], n=120)


def dog_leg(p, pts, w0, w1, flow, paw, paw_r, paw_angle=0.0):
    leg = tube(pts, w0, w1)
    p.fill(leg, DOG["fur"], edge=35)
    p.fur(leg, along(flow), DOG["light"], DOG["dark"], n=150, alpha=(0.35, 0.3))
    p.patch(clip(ell(paw, (paw_r[0] * 1.6, paw_r[1] * 1.15), paw_angle), leg), DOG["white"], alpha=0.9, blur=1.0)
    m = ell(paw, paw_r, paw_angle)
    p.fill(m, DOG["white"], edge=40, shade=0.25)
    p.fur(m, along(flow), (240, 236, 226), mix(DOG["white"], DOG["dark"], 0.35), n=40, length=(1.2, 2.2), alpha=(0.4, 0.3))
    for k in (-1, 1):
        a = math.radians(paw_angle)
        ox, oy = paw[0] + math.cos(a) * paw_r[0] * 0.5, paw[1] + math.sin(a) * paw_r[0] * 0.5
        dx, dy = -math.sin(a) * k * paw_r[1] * 0.35, math.cos(a) * k * paw_r[1] * 0.35
        p.line([(ox + dx, oy + dy), (ox + dx - math.cos(a) * 2.4, oy + dy - math.sin(a) * 2.4)], 0.5, (120, 104, 90), 120)


def dog_tail(p, pts, w0, w1):
    t = tube(pts, w0, w1)
    p.fill(t, DOG["fur"], edge=40)
    curve = bezier(pts)
    p.fur(t, lambda x, y: _along_curve(curve, x, y), DOG["light"], DOG["dark"], alpha=(0.35, 0.3))
    p.patch(ell(curve[-1], (w1 * 1.2, w1 * 1.6)), DOG["white"], alpha=0.95, blur=1.0)   # the hound's white tail tip
    p.edge_fur(t, lambda x, y: _along_curve(curve, x, y) + 30, DOG["fur"], n=40)


def dog_collar(p, pts, w=6.5):
    m = tube(pts, w, w)
    p.fill(m, DOG["collar"], contact=True, edge=60, shade=0.2)
    p.ink(clip(soft(tube([(x, y - w * 0.25) for x, y in pts], w * 0.25), 0.4), m), (176, 112, 96), 90)
    return m


def dog_resting(path):
    """Lying down, head up between the forepaws."""
    p = Painter(5)
    dog_tail(p, [(70, 168), (54, 186), (60, 206)], 10, 6)
    body = union(ell((138, 160), (36, 30), -6), ell((110, 162), (40, 26), -2), ell((82, 168), (30, 28)))
    dog_body(p, body, (170, 150), belly=ell((128, 188), (34, 12)))
    for x in (68, 92):
        m = ell((x, 196), (12, 8))
        p.fill(m, DOG["fur"], edge=35)
        p.fur(m, along(0), DOG["light"], DOG["dark"], n=60, alpha=(0.35, 0.3))
        p.patch(ell((x + 6, 197), (6, 5.5)), DOG["white"], alpha=0.95, blur=0.8)
    for x in (150, 182):
        dog_leg(p, [(x - 14, 184), (x + 4, 194)], 12, 10.5, 15, (x + 9, 196), (8.5, 6.5), 10)
    dog_collar(p, [(150, 138), (146, 158), (150, 176)])
    dog_head(p, (170, 150), 1.15, "open")
    p.finish(path)


def dog_sleeping(path):
    """Asleep on its side, legs out, chin down."""
    p = Painter(6)
    dog_tail(p, [(58, 152), (46, 176), (52, 196)], 10, 6)
    for y in (184, 196):
        dog_leg(p, [(82, y - 14), (70, y + 4)], 12, 10, 110, (68, y + 8), (7, 6), 110)
    body = union(ell((140, 156), (38, 32), 4), ell((112, 158), (42, 28), 2), ell((80, 160), (29, 31)))
    dog_body(p, body, (176, 156), belly=ell((124, 184), (38, 12)))
    p.contact(ell((180, 192), (20, 10)), 0, -2, 2.5, 60)
    for y in (186, 198):
        dog_leg(p, [(158, y - 10), (192, y)], 11.5, 10, 15, (196, y + 1), (8, 6.5), 15)
    dog_collar(p, [(154, 138), (150, 160), (154, 178)])
    dog_head(p, (174, 156), 1.05, "closed")
    p.finish(path)


def dog_alert(path):
    """Sitting up, looking up, ears lifted a little, tongue just showing."""
    p = Painter(7)
    dog_tail(p, [(160, 200), (192, 198), (204, 174)], 10, 6)
    body = union(ell((128, 176), (40, 28)), ell((128, 146), (25, 28)))
    dog_body(p, body, (128, 104), belly=ell((128, 156), (13, 24)), light_side=(0.35, 0.2))
    for x in (114, 142):
        dog_leg(p, [(x, 156), (x, 196)], 11, 9.5, 90, (x, 200), (7.5, 6), 90)
    dog_collar(p, [(110, 126), (128, 131), (146, 126)])
    p.ink(soft(ell((128, 136), (3.2, 3.6)), 0.3), DOG["brass"], 240)
    p.ink(soft(ell((127, 135), (1.0, 1.0)), 0.3), (226, 210, 160), 200)
    dog_head(p, (128, 102), 1.25, "open", tongue=True, ears_up=1.0)
    p.finish(path)


def dog_stretching(path):
    """The play bow: forelegs stretched forward, hindquarters up."""
    p = Painter(8)
    dog_tail(p, [(58, 132), (42, 112), (44, 84)], 10, 6)
    for y in (132, 166):
        dog_leg(p, [(92, y), (76, y + 6)], 13, 11, 170, (72, y + 7), (7, 6), 180)
    body = union(ell((140, 152), (34, 26), -6), ell((112, 146), (40, 22), -3), ell((82, 146), (27, 30)))
    dog_body(p, body, (180, 150), belly=ell((128, 170), (34, 8)))
    for y in (158, 180):
        dog_leg(p, [(160, y - 2), (210, y + 4)], 11, 9.5, 5, (215, y + 4), (8.5, 6.5), 4)
    dog_collar(p, [(150, 132), (156, 164)])
    dog_head(p, (180, 150), 1.1, "closed", tongue=True)
    p.finish(path)


if __name__ == "__main__":
    for kind, poses in (("cat", (cat_resting, cat_sleeping, cat_alert, cat_stretching)),
                        ("dog", (dog_resting, dog_sleeping, dog_alert, dog_stretching))):
        for paint in poses:
            name = paint.__name__.split("_", 1)[1]
            paint(os.path.join(OUT, kind, name + ".png"))
