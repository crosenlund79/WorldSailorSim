"""Paints the harbour illustrations of I021 (A Wider, Warmer World) in the Real Horizon
style (DEV_GUIDES/ART_DIRECTION.md), seen from above like the rest of the harbour and
like Copenhagen's Nyhavn strip (tools/harbours/paint_copenhagen_landmark.py).

Every image is a strip of 1150 x 110 scene units at 2 px per unit (2300 x 220 px,
transparent background), drawn centred beyond the guest pontoon by HarbourDressing.
The top edge is the water side. From the top down: the quay (paving, a sea wall, a
beach or a timber wharf), then the row of buildings seen from above - a thin band of
facade below the eaves with the window heads (the water-facing walls are just visible
in this slightly tilted top-down view), then the roofs: pitched roofs with a lit near
plane and a shaded far plane, hip roofs, gables shown as roof ends, flat roof
terraces with parapets - and behind them yards, trees, hills or cliffs. Only the top
30-50 units show above the screen edge in play, so each place's identity is carried
there: the quay material, the facade colours and the roofs.

Light from the upper left; cast shadows fall down-right (each height layer casts its
own soft shadow onto what lies below it). Form comes from tone, with only thin
translucent blue-grey lines; colours natural and subdued, saturation only in small
accents. Fine grain and material texture (tile courses, slate, corrugated tin,
thatch, ashlar, setts) at a scale that reads at 1x.

Two kinds:
  * archetypes (assets/harbours/looks/<id>.png): one per kind of harbour, chosen per
    harbour in data/harbours/harbour_looks.json. Kinds follow what a harbour looks like
    (its buildings, materials, land and climate), never the continent alone.
  * landmarks (assets/harbours/<port>/<name>.png): one place's own view, for the
    special harbours (data/harbours/<port>.tres).

Original drawings; no source artwork is traced or copied. Deterministic (fixed seeds).
Requires Pillow and numpy.

Usage: python3 tools/harbours/paint_harbour_looks.py [name ...]   (default: all)
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SS, FINAL = 4, 2
W, H = 1150, 110
LINE = (42, 50, 54)          # thin blue-grey line (marine palette LINE)
SHADOW = (14, 20, 26)
HAZE = (203, 211, 208)       # sea haze (marine palette SEA_HAZE)
HAZE_FROM = 64               # where the haze starts, down the picture (units)
_L = np.array([-0.46, -0.55, 0.70])
LIGHT3 = _L / np.linalg.norm(_L)
LIGHT2 = (-0.8, -0.6)  # towards the light, in the picture plane
# Height layers, drawn in this order; each casts a soft shadow down-right onto what
# was drawn before it: (name, shadow offset in units, blur in units, strength).
LAYERS = (("roof", (2.4, 3.2), 1.0, 0.36), ("roof2", (3.4, 4.4), 1.1, 0.34), ("detail", (1.3, 1.7), 0.5, 0.40),
          ("tree", (4.0, 5.0), 1.6, 0.38), ("tall", (9.0, 11.5), 1.8, 0.32))


def shade(c, k):
    return tuple(max(0, min(255, int(round(v * k)))) for v in c[:3])


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


# --- Material textures (drawn in plane-local u, v: u along the eaves, v down the slope) --

def _bond(course, wmin, wmax, mott, joint_k, joint_a, joint_w=0.35, stagger=True, odd=0.0, odd_k=0.85):
    def tex(p, R, Ln, E, u0, u1, v0, v1, col, o):
        rng = p.rng
        v = o - math.ceil((o - v0) / course) * course
        row = 0
        while v < v1:
            u = u0 - (rng.uniform(0, wmax) if not stagger else (row % 2) * (wmin + wmax) / 4) - wmax
            while u < u1:
                w = rng.uniform(wmin, wmax)
                k = 1 + rng.uniform(-mott, mott)
                if odd and rng.random() < odd:
                    k *= odd_k
                R(u + 0.12, v + 0.1, u + w - 0.12, v + course - 0.1, shade(col, k))
                Ln(u + w, v, u + w, v + course, shade(col, joint_k), joint_a * 0.7, joint_w * 0.8)
                u += w
            Ln(u0, v + course, u1, v + course, shade(col, joint_k), joint_a, joint_w)
            row += 1
            v += course
    return tex


TEX = {
    "tile": _bond(2.3, 2.5, 3.0, 0.07, 0.62, 150, 0.45),
    "slate": _bond(1.7, 1.8, 3.0, 0.06, 0.62, 140, 0.3, stagger=False, odd=0.12),
    "shingle": _bond(1.5, 1.2, 2.6, 0.08, 0.6, 140, 0.3, stagger=False, odd=0.1),
    "brick": _bond(1.1, 2.2, 2.4, 0.08, 0.72, 120, 0.25),
    "ashlar": _bond(3.0, 4.0, 8.0, 0.05, 0.76, 110, 0.3, stagger=False),
    "setts": _bond(3.6, 3.0, 4.6, 0.08, 0.7, 150, 0.5, stagger=False),
    "slabs": _bond(7.0, 8.0, 16.0, 0.05, 0.74, 140, 0.45, stagger=False),
    "flags": _bond(5.0, 5.0, 11.0, 0.06, 0.78, 120, 0.4, stagger=False),
    "blocks": _bond(4.2, 6.0, 12.0, 0.06, 0.7, 160, 0.5, stagger=False),
}


def _pantile(p, R, Ln, E, u0, u1, v0, v1, col, o):
    rng = p.rng
    u = u0 - 3
    while u < u1:  # the rolls of the pantiles running down the slope
        R(u, v0, u + 1.3, v1, shade(col, 1.10))
        R(u + 1.3, v0, u + 2.6, v1, shade(col, 0.93))
        Ln(u + 2.5, v0, u + 2.5, v1, shade(col, 0.66), 150, 0.35)
        v = o - math.ceil((o - v0) / 3.2) * 3.2
        while v < v1:
            if rng.random() < 0.18:
                R(u, v, u + 2.6, v + 3.2, shade(col, rng.uniform(0.84, 1.16)), 110)
            Ln(u, v, u + 2.6, v, shade(col, 0.72), 90, 0.3)
            v += 3.2
        u += 2.6


def _tin(p, R, Ln, E, u0, u1, v0, v1, col, o):
    rng = p.rng
    u = u0 - 1
    i = 0
    while u < u1:
        Ln(u, v0, u, v1, shade(col, 1.12 if i % 2 else 0.84), 120, 0.3)
        u += 0.8
        i += 1
    v = o + 17
    while v < v1:  # sheet laps
        Ln(u0, v, u1, v, shade(col, 0.7), 110, 0.35)
        v += 17
    for _ in range(int((u1 - u0) * (v1 - v0) / 300)):  # weathering and a little rust
        E(rng.uniform(u0, u1), rng.uniform(v0, v1), rng.uniform(1.5, 5), rng.uniform(1, 3), (132, 86, 58), rng.randint(25, 60))


def _thatch(p, R, Ln, E, u0, u1, v0, v1, col, o):
    rng = p.rng
    for _ in range(int((u1 - u0) * (v1 - v0) * 1.6)):
        u = rng.uniform(u0, u1)
        v = rng.uniform(v0, v1)
        Ln(u, v, u + rng.uniform(-0.3, 0.3), v + rng.uniform(1.5, 3.5), shade(col, rng.uniform(0.7, 1.22)), 170, 0.3)


def _render(p, R, Ln, E, u0, u1, v0, v1, col, o):
    rng = p.rng
    for _ in range(int((u1 - u0) * (v1 - v0) / 14)):
        E(rng.uniform(u0, u1), rng.uniform(v0, v1), rng.uniform(0.8, 3.5), rng.uniform(0.6, 2.4),
          shade(col, rng.uniform(0.9, 1.06)), rng.randint(40, 110))


def _board(p, R, Ln, E, u0, u1, v0, v1, col, o):
    u = u0 + 0.8
    while u < u1:
        Ln(u, v0, u, v1, shade(col, 0.74), 150, 0.3)
        u += 1.7


def _grass(p, R, Ln, E, u0, u1, v0, v1, col, o):
    rng = p.rng
    for _ in range(int((u1 - u0) * (v1 - v0) / 10)):
        E(rng.uniform(u0, u1), rng.uniform(v0, v1), rng.uniform(1, 5), rng.uniform(0.8, 3),
          shade(col, rng.uniform(0.82, 1.14)), rng.randint(60, 150))


def _sand(p, R, Ln, E, u0, u1, v0, v1, col, o):
    rng = p.rng
    for _ in range(int((u1 - u0) * (v1 - v0) / 3)):
        E(rng.uniform(u0, u1), rng.uniform(v0, v1), 0.3, 0.3, shade(col, rng.uniform(0.86, 1.1)), 150)


def _rock(p, R, Ln, E, u0, u1, v0, v1, col, o):
    """Rough rock: jittered facets each turned to or from the light, and strata."""
    rng = p.rng
    cell = 7.0
    v = v0 - cell
    while v < v1 + cell:
        u = u0 - cell
        while u < u1 + cell:
            cu, cv = u + rng.uniform(0, cell), v + rng.uniform(0, cell)
            pts = []
            for k in range(rng.randint(4, 6)):
                a = 2 * math.pi * k / 5 + rng.uniform(-0.4, 0.4)
                r = rng.uniform(0.5, 1.0) * cell * 0.8
                pts.append((cu + r * math.cos(a), cv + r * 0.8 * math.sin(a)))
            p._poly_local(pts, shade(col, rng.uniform(0.72, 1.24)), rng.randint(140, 230))
            u += cell * rng.uniform(0.6, 1.0)
        v += cell * rng.uniform(0.6, 0.9)
    for _ in range(int((u1 - u0) / 6)):
        u = rng.uniform(u0, u1)
        vv = rng.uniform(v0, v1)
        Ln(u, vv, u + rng.uniform(4, 16), vv + rng.uniform(-2, 2), shade(col, 0.55), 120, 0.4)


TEX.update({"pantile": _pantile, "tin": _tin, "thatch": _thatch, "render": _render, "board": _board,
            "grass": _grass, "sand": _sand, "rock": _rock})


class Painter:
    def __init__(self, seed, sk=1.0):
        self.seed = seed
        self.sk = sk  # shadow scale: true-scale buildings cast longer, softer shadows (I025)
        self.rng = random.Random(seed)
        self.layers = {"ground": Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))}
        for name, *_ in LAYERS:
            self.layers[name] = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
        self.draws = {k: ImageDraw.Draw(v, "RGBA") for k, v in self.layers.items()}
        self._local = None

    # --- primitives (units) -----------------------------------------------------------
    def _draw(self, L, pts, a, fn):
        """Draws with ImageDraw; translucent ink is composited over the layer (a plain
        ImageDraw call on an RGBA image would replace the pixels, alpha and all)."""
        if a >= 255:
            fn(self.draws[L], [(x * SS, y * SS) for x, y in pts])
            return
        xs = [q[0] for q in pts]
        ys = [q[1] for q in pts]
        x0, y0 = max(0, int(min(xs) * SS) - 8), max(0, int(min(ys) * SS) - 8)
        x1, y1 = min(W * SS, int(max(xs) * SS) + 9), min(H * SS, int(max(ys) * SS) + 9)
        if x1 <= x0 or y1 <= y0:
            return
        over = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
        fn(ImageDraw.Draw(over, "RGBA"), [(x * SS - x0, y * SS - y0) for x, y in pts])
        self.layers[L].alpha_composite(over, (x0, y0))

    def poly(self, L, pts, col, a=255):
        ink = tuple(col[:3]) + (int(a),)
        self._draw(L, pts, a, lambda d, q: d.polygon(q, fill=ink))

    def rect(self, L, x, y, w, h, col, a=255):
        if w <= 0 or h <= 0:
            return
        ink = tuple(col[:3]) + (int(a),)
        self._draw(L, [(x, y), (x + w, y + h)], a, lambda d, q: d.rectangle([q[0], (q[1][0] - 1, q[1][1] - 1)], fill=ink))

    def line(self, L, pts, col=LINE, a=110, w=0.4):
        ink = tuple(col[:3]) + (int(a),)
        wd = max(1, int(round(w * SS)))
        self._draw(L, pts, a, lambda d, q: d.line(q, fill=ink, width=wd))

    def ellipse(self, L, cx, cy, rx, ry, col, a=255):
        ink = tuple(col[:3]) + (int(a),)
        self._draw(L, [(cx - rx, cy - ry), (cx + rx, cy + ry)], a, lambda d, q: d.ellipse(q, fill=ink))

    def _poly_local(self, pts, col, a):
        d, px0, py0, orient, k = self._local
        pts = [(u * k, v * k) for u, v in pts]
        if orient == "v":
            pts = [(v, u) for u, v in pts]
        d.polygon([(x * SS - px0, y * SS - py0) for x, y in pts], fill=tuple(col[:3]) + (a,))

    def plane(self, L, pts, col, tex=None, orient="h", origin=None, tk=1.0):
        """A flat surface (roof plane, wall top, paving) filled with a material; `tk`
        scales the material's courses and joints (I025: tiles, slates and setts at
        their real size)."""
        xs = [q[0] for q in pts]
        ys = [q[1] for q in pts]
        bx0, by0, bx1, by1 = min(xs) - 1, min(ys) - 1, max(xs) + 1, max(ys) + 1
        px0, py0 = int(math.floor(bx0 * SS)), int(math.floor(by0 * SS))
        bw, bh = int(math.ceil(bx1 * SS)) - px0, int(math.ceil(by1 * SS)) - py0
        tile = Image.new("RGB", (bw, bh), tuple(col[:3]))  # RGB, so translucent strokes blend
        if tex:
            d = ImageDraw.Draw(tile, "RGBA")
            self._local = (d, px0, py0, orient, tk)

            def xy(u, v):
                return ((u, v) if orient == "h" else (v, u))

            def R(u0, v0, u1, v1, c, a=255):
                (x0, y0), (x1, y1) = xy(u0, v0), xy(u1, v1)
                d.rectangle([x0 * SS - px0, y0 * SS - py0, x1 * SS - px0 - 1, y1 * SS - py0 - 1], fill=tuple(c[:3]) + (a,))

            def Ln(u0, v0, u1, v1, c, a, w):
                (x0, y0), (x1, y1) = xy(u0, v0), xy(u1, v1)
                d.line([(x0 * SS - px0, y0 * SS - py0), (x1 * SS - px0, y1 * SS - py0)], fill=tuple(c[:3]) + (int(a),),
                       width=max(1, int(round(w * SS))))

            def E(u, v, ru, rv, c, a=255):
                (x, y), (rx, ry) = xy(u, v), xy(ru, rv)
                d.ellipse([(x - rx) * SS - px0, (y - ry) * SS - py0, (x + rx) * SS - px0, (y + ry) * SS - py0],
                          fill=tuple(c[:3]) + (int(a),))

            if orient == "h":
                u0, u1, v0, v1 = bx0, bx1, by0, by1
                o = by0 + 1 if origin is None else origin
            else:
                u0, u1, v0, v1 = by0, by1, bx0, bx1
                o = bx0 + 1 if origin is None else origin
            if tk != 1.0:
                R0, Ln0, E0 = R, Ln, E

                def R(a, b, c, e, cc, al=255):
                    R0(a * tk, b * tk, c * tk, e * tk, cc, al)

                def Ln(a, b, c, e, cc, al, w):
                    Ln0(a * tk, b * tk, c * tk, e * tk, cc, al, w * tk * 0.45)

                def E(u, v, ru, rv, cc, al=255):
                    E0(u * tk, v * tk, ru * tk, rv * tk, cc, al)

                u0, u1, v0, v1, o = u0 / tk, u1 / tk, v0 / tk, v1 / tk, o / tk
            TEX[tex](self, R, Ln, E, u0, u1, v0, v1, col, o)
        mask = Image.new("L", (bw, bh), 0)
        ImageDraw.Draw(mask).polygon([(x * SS - px0, y * SS - py0) for x, y in pts], fill=255)
        self.layers[L].paste(tile.convert("RGBA"), (px0, py0), mask)

    def box(self, L, x, y, w, h, col, tex=None, orient="h", origin=None, tk=1.0):
        self.plane(L, [(x, y), (x + w, y), (x + w, y + h), (x, y + h)], col, tex, orient, origin, tk)

    def sphere(self, L, cx, cy, r, col, ry=None, amb=0.42, rough=0.0, a=1.0, gain=1.15):
        """A shaded dome / lump / drum seen from above, lit from the upper left."""
        ry = ry or r
        img = self.layers[L]
        x0, y0 = max(0, int((cx - r) * SS) - 2), max(0, int((cy - ry) * SS) - 2)
        x1, y1 = min(W * SS, int((cx + r) * SS) + 3), min(H * SS, int((cy + ry) * SS) + 3)
        if x1 <= x0 or y1 <= y0:
            return
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        nx = ((xx + 0.5) / SS - cx) / r
        ny = ((yy + 0.5) / SS - cy) / ry
        rr = nx * nx + ny * ny
        nz = np.sqrt(np.clip(1 - rr, 0, 1))
        lam = np.clip(nx * LIGHT3[0] + ny * LIGHT3[1] + nz * LIGHT3[2], 0, 1)
        k = amb + (1 - amb) * lam * gain
        if rough:
            nrng = np.random.default_rng(self.rng.randint(0, 1 << 30))
            small = nrng.random((max(2, (y1 - y0) // 5), max(2, (x1 - x0) // 5))).astype(np.float32)
            noise = np.asarray(Image.fromarray((small * 255).astype(np.uint8)).resize((x1 - x0, y1 - y0), Image.BILINEAR), np.float32) / 255
            k = k * (1 + rough * (noise - 0.5) * 2)
        out = np.zeros((y1 - y0, x1 - x0, 4), np.float32)
        for i in range(3):
            out[..., i] = np.clip(col[i] * k, 0, 255)
        edge = np.clip((1 - np.sqrt(rr)) * min(r, ry) * SS, 0, 1)
        out[..., 3] = edge * 255 * a
        img.alpha_composite(Image.fromarray(out.astype(np.uint8), "RGBA"), (x0, y0))

    def facets(self, L, cx, cy, r, n, col, rot=None, tex=None, apex=(0, 0)):
        """A pyramid or spire roof seen from above: n facets shaded by facing."""
        rot = -math.pi / 2 - math.pi / n if rot is None else rot
        pts = [(cx + r * math.cos(rot + 2 * math.pi * i / n), cy + r * math.sin(rot + 2 * math.pi * i / n)) for i in range(n)]
        ax, ay = cx + apex[0], cy + apex[1]
        for i in range(n):
            a, b = pts[i], pts[(i + 1) % n]
            mid = math.atan2((a[1] + b[1]) / 2 - cy, (a[0] + b[0]) / 2 - cx)
            k = 0.86 + 0.30 * (math.cos(mid) * LIGHT2[0] + math.sin(mid) * LIGHT2[1])
            self.plane(L, [(ax, ay), a, b], shade(col, k), tex, "h" if abs(math.sin(mid)) > 0.7 else "v")
            self.line(L, [(ax, ay), a], shade(col, 0.6), 120, 0.3)

    # --- trees ----------------------------------------------------------------------
    def tree(self, cx, cy, r, col, lumps=None, L="tree"):
        rng = self.rng
        n = lumps or rng.randint(4, 7)
        parts = []
        for _ in range(n):
            a = rng.uniform(0, 2 * math.pi)
            d = rng.uniform(0, r * 0.45)
            parts.append((cx + d * math.cos(a), cy + d * math.sin(a), r * rng.uniform(0.45, 0.68)))
        self.sphere(L, cx, cy, r * 0.92, shade(col, 0.8), amb=0.5, rough=0.2)
        for px, py, pr in sorted(parts, key=lambda q: q[0] + q[1], reverse=True):
            self.sphere(L, px, py, pr, col, amb=0.45, rough=0.28)

    def palm(self, cx, cy, r, col=(98, 112, 74), L="tree"):
        rng = self.rng
        n = rng.randint(9, 12)
        off = rng.uniform(0, 2 * math.pi)
        fronds = []
        for i in range(n):
            a = off + 2 * math.pi * i / n + rng.uniform(-0.15, 0.15)
            lit = math.cos(a) * LIGHT2[0] + math.sin(a) * LIGHT2[1]
            fronds.append((lit, a))
        for i in range(3):  # a few old fronds hanging lower, brown
            a = rng.uniform(0, 2 * math.pi)
            self._frond(L, cx, cy, a, r * 0.8, rng.uniform(-0.3, 0.3), (122, 112, 82), 0.85)
        for lit, a in sorted(fronds):
            k = 0.8 + 0.28 * lit
            self._frond(L, cx, cy, a, r * rng.uniform(0.82, 1.05), rng.uniform(-0.35, 0.35), col, k)
        self.sphere(L, cx, cy, r * 0.12, (110, 100, 70), amb=0.5)

    def _frond(self, L, cx, cy, a, length, bend, col, k):
        steps = 10
        mid, left, right = [], [], []
        for i in range(steps + 1):
            t = i / steps
            aa = a + bend * t
            x, y = cx + length * t * math.cos(aa), cy + length * t * math.sin(aa)
            wdt = length * 0.17 * math.sin(math.pi * min(1.0, t * 1.1)) ** 0.7
            mid.append((x, y))
            left.append((x - wdt * math.sin(aa), y + wdt * math.cos(aa)))
            right.append((x + wdt * math.sin(aa), y - wdt * math.cos(aa)))
        c = shade(col, k)
        self.poly(L, left + right[::-1], c)
        for i in range(1, steps):  # leaflets
            for side in (left, right):
                self.line(L, [mid[i], side[i]], shade(c, 0.72), 140, 0.25)
        self.line(L, mid, shade(c, 1.22), 170, 0.35)

    # --- buildings --------------------------------------------------------------------
    def lip(self, x, y, w, h, facade, tex=None, windows=None, glass=(54, 62, 68), frame=(206, 204, 194),
            shutter=None, arch=False, L="roof", door=None, trim=None):
        """The strip of water-facing wall seen below the eaves, with the window heads."""
        self.box(L, x, y, w, h, facade, tex)
        n = windows if windows is not None else max(1, int(w / 13))
        ww = min(5.0, w / n * 0.42)
        for c in range(n):
            wx = x + (c + 0.5) * w / n - ww / 2
            wy = y + h * 0.38
            if door is not None and c == n // 2 and n > 2:
                self.rect(L, wx - 0.5, wy - 0.6, ww + 1, h - (wy - y) + 0.6, door)
                continue
            if shutter:
                self.rect(L, wx - ww * 0.55, wy, ww * 0.5, h - (wy - y), shutter)
                self.rect(L, wx + ww * 1.05, wy, ww * 0.5, h - (wy - y), shutter)
            self.rect(L, wx, wy, ww, h - (wy - y), glass)
            if arch:
                self.ellipse(L, wx + ww / 2, wy, ww / 2, ww / 2.4, glass)
            elif frame:
                self.rect(L, wx - 0.3, wy - 0.7, ww + 0.6, 0.8, frame)
        if trim:
            self.rect(L, x, y, w, 0.9, trim)
        self.rect(L, x, y + h - 1.5, w, 1.5, SHADOW, 70)  # the eaves' shadow on the wall
        self.line(L, [(x, y), (x + w, y)], LINE, 90, 0.3)

    def ridge_roof(self, x, y, w, d, roof, tex="tile", ridge=0.45, L="roof", verge=True, ridge_cap=None):
        """A pitched roof with its ridge along the quay: near plane lit, far in shade."""
        ry = y + d * ridge
        self.box(L, x, y, w, ry - y, shade(roof, 1.08), tex, "h", y)
        self.box(L, x, ry, w, y + d - ry, shade(roof, 0.80), tex, "h", ry)
        self.rect(L, x, y, w, 0.6, shade(roof, 1.2), 160)  # the eaves catch the light
        self.rect(L, x, ry - 0.8, w, 1.6, ridge_cap or shade(roof, 0.92))
        self.line(L, [(x, ry + 0.8), (x + w, ry + 0.8)], shade(roof, 0.5), 150, 0.35)
        self.rect(L, x, ry - 0.8, w, 0.4, shade(roof, 1.25), 140)
        if verge:
            self.rect(L, x, y, 0.8, d, shade(roof, 1.25), 150)
            self.rect(L, x + w - 0.8, y, 0.8, d, shade(roof, 0.6), 150)
        self.line(L, [(x, y + d), (x + w, y + d)], LINE, 80, 0.3)

    def gable_roof(self, x, y, w, d, roof, tex="tile", L="roof"):
        """A pitched roof end-on to the quay: left plane lit, right in shade."""
        self.box(L, x, y, w / 2, d, shade(roof, 1.12), tex, "v", x)
        self.box(L, x + w / 2, y, w / 2, d, shade(roof, 0.76), tex, "v", x + w / 2)
        self.rect(L, x + w / 2 - 0.8, y, 1.6, d, shade(roof, 0.95))
        self.line(L, [(x + w / 2 + 0.8, y), (x + w / 2 + 0.8, y + d)], shade(roof, 0.5), 140, 0.35)
        self.rect(L, x, y, 0.7, d, shade(roof, 1.25), 150)
        self.rect(L, x + w - 0.7, y, 0.7, d, shade(roof, 0.55), 150)
        self.line(L, [(x, y + d), (x + w, y + d)], LINE, 80, 0.3)

    def hip_roof(self, x, y, w, d, roof, tex="tile", L="roof"):
        i = min(w, d) * 0.48
        my = y + d / 2
        a, b = (x + i, my), (x + w - i, my)
        if w < d:
            a, b = (x + w / 2, y + i), (x + w / 2, y + d - i)
        self.plane(L, [(x, y), (x + w, y), b, a], shade(roof, 1.06), tex, "h", y)
        self.plane(L, [(x, y + d), (x + w, y + d), b, a], shade(roof, 0.80), tex, "h", y)
        self.plane(L, [(x, y), a, (x, y + d)], shade(roof, 1.16), tex, "v", x)
        self.plane(L, [(x + w, y), b, (x + w, y + d)], shade(roof, 0.70), tex, "v", x)
        for p0 in ((x, y), (x, y + d)):
            self.line(L, [p0, a], shade(roof, 1.3), 150, 0.45)
        for p0 in ((x + w, y), (x + w, y + d)):
            self.line(L, [p0, b], shade(roof, 0.55), 150, 0.45)
        self.line(L, [a, b], shade(roof, 0.6), 160, 0.6)
        self.rect(L, x, y, w, 0.6, shade(roof, 1.2), 150)

    def flat_roof(self, x, y, w, d, col, parapet=1.3, L="roof", tex="render"):
        """A roof terrace: parapet rim lit along its top and left, shadow inside."""
        self.box(L, x, y, w, d, shade(col, 1.04), tex)
        p = parapet
        self.box(L, x + p, y + p, w - 2 * p, d - 2 * p, shade(col, 0.93), tex)
        self.rect(L, x + p, y + p, w - 2 * p, 1.4, SHADOW, 55)
        self.rect(L, x + p, y + p + 1.4, 1.4, d - 2 * p - 1.4, SHADOW, 45)
        self.rect(L, x, y, w, 0.5, shade(col, 1.12), 200)
        self.rect(L, x, y, 0.5, d, shade(col, 1.1), 200)
        self.rect(L, x + w - 0.6, y, 0.6, d, shade(col, 0.72), 200)
        self.rect(L, x, y + d - 0.6, w, 0.6, shade(col, 0.76), 200)

    def gable_face(self, x, y, w, facade, kind="plain", h=None, L="detail", coping=(196, 192, 182), tex=None):
        """A gable rising above the roof, seen leaning back over the roof from the
        tilted top-down view: stepped, neck, pointed or a classical pediment."""
        h = h if h is not None else min(9.0, w * 0.22)
        if kind == "stepped":
            n = 3 if w < 44 else 4
            seg = w / (2 * n + 1)
            pts = [(x, y)]
            for k in range(2 * n + 1):
                hk = 1.6 + (h - 1.6) * min(k, 2 * n - k) / n
                pts += [(x + k * seg, y + hk), (x + (k + 1) * seg, y + hk)]
            pts.append((x + w, y))
            self.plane(L, pts, facade, tex, "h", y)
            for k in range(2 * n + 1):  # the copings on each step
                hk = 1.6 + (h - 1.6) * min(k, 2 * n - k) / n
                self.rect(L, x + k * seg, y + hk - 0.8, seg, 0.8, coping)
        elif kind == "neck":
            nw = w * 0.34
            sh = h * 0.42
            cx = x + w / 2
            pts = [(x, y), (x, y + 1.4), (cx - nw / 2 - 4, y + 1.4), (cx - nw / 2 - 1.5, y + sh * 0.8), (cx - nw / 2, y + sh),
                   (cx - nw / 2, y + h), (cx - nw / 4, y + h + 1.2), (cx + nw / 4, y + h + 1.2), (cx + nw / 2, y + h),
                   (cx + nw / 2, y + sh), (cx + nw / 2 + 1.5, y + sh * 0.8), (cx + nw / 2 + 4, y + 1.4), (x + w, y + 1.4), (x + w, y)]
            self.plane(L, pts, facade, tex, "h", y)
            self.line(L, pts[1:-1], coping, 230, 0.6)
        elif kind == "pediment":
            pts = [(x, y), (x, y + 1.0), (x + w / 2, y + h), (x + w, y + 1.0), (x + w, y)]
            self.plane(L, pts, facade, tex, "h", y)
            self.line(L, pts[1:-1], coping, 240, 0.8)
            self.ellipse(L, x + w / 2, y + h * 0.5, 1.4, 1.0, shade(facade, 0.7))
        else:
            pts = [(x, y), (x + w / 2, y + h), (x + w, y)]
            self.plane(L, pts, facade, tex, "h", y)
            self.line(L, pts, coping, 200, 0.5)
            self.rect(L, x + w / 2 - 1.8, y + h * 0.25, 3.6, h * 0.35, (52, 58, 62))
        return h

    def chimney(self, x, y, w=5.0, h=3.6, col=(150, 130, 116), pots=2, L="detail"):
        self.rect(L, x, y, w, h, col)
        self.rect(L, x, y, w, 0.5, shade(col, 1.2))
        self.rect(L, x, y, 0.5, h, shade(col, 1.15))
        self.rect(L, x + w - 0.5, y, 0.5, h, shade(col, 0.7))
        for i in range(pots):
            self.sphere(L, x + (i + 0.5) * w / pots, y + h / 2, min(1.2, w / pots * 0.35), (140, 92, 70), amb=0.5)
            self.ellipse(L, x + (i + 0.5) * w / pots, y + h / 2, 0.5, 0.5, (30, 28, 26))

    def dormer(self, x, y, w, d, roof, face, tex="tile", L="detail"):
        self.rect(L, x, y, w, 2.4, face)
        self.rect(L, x + w * 0.25, y + 0.8, w * 0.5, 1.6, (54, 62, 68))
        self.gable_roof(x - 0.5, y + 2.4, w + 1, d - 2.4, roof, tex, L)

    def stair_hut(self, x, y, w, d, col, door=(70, 62, 54), L="roof2"):
        """The little stair head on a roof terrace: a box, its door facing the water."""
        self.rect(L, x, y, w, 2.4, shade(col, 0.9))
        self.rect(L, x + w * 0.35, y + 0.6, w * 0.3, 1.8, mix(door, shade(col, 0.6), 0.5))
        self.box(L, x, y + 2.4, w, d - 2.4, shade(col, 1.04), "render")
        self.rect(L, x, y + 2.4, w, 0.5, shade(col, 1.15))
        self.rect(L, x + w - 0.6, y + 2.4, 0.6, d - 2.4, shade(col, 0.78))
        self.rect(L, x, y + d - 0.6, w, 0.6, shade(col, 0.8))

    def tower(self, x, y, s, wall, roof, tex=None, lip=6.0, n=4, openings=1, wall_tex="ashlar", glass=(64, 58, 52)):
        """A tower seen from above: its water-facing wall just showing, then a pyramid
        (n=4) or spire (n=8) roof over the whole square, casting a long shadow."""
        self.lip(x, y, s, lip, wall, wall_tex, openings, glass=glass, frame=None, arch=True, L="roof2")
        self.box("roof2", x, y + lip, s, s, wall, wall_tex)
        if n == 4:
            self.facets("tall", x + s / 2, y + lip + s / 2, s * 0.7071, 4, roof, rot=-math.pi * 3 / 4, tex=tex)
        else:
            self.facets("tall", x + s / 2, y + lip + s / 2, s * 0.54, n, roof, tex=tex)
        self.sphere("tall", x + s / 2, y + lip + s / 2, max(0.9, s * 0.05), (150, 136, 110), amb=0.5)

    def tank(self, cx, cy, r, col=(170, 172, 168), L="detail"):
        self.sphere(L, cx, cy, r, col, amb=0.55, gain=0.9)
        self.ellipse(L, cx, cy, r * 0.35, r * 0.35, shade(col, 0.8))

    def bollards(self, y, x0, x1, step, col=(60, 64, 66)):
        x = x0
        while x < x1:
            self.sphere("detail", x, y, 1.3, col, amb=0.4)
            x += step

    def awning(self, x, y, w, d, col, stripe=None):
        self.box("detail", x, y, w, d, col)
        if stripe:
            sx = x
            while sx < x + w:
                self.rect("detail", sx, y, 1.6, d, stripe, 200)
                sx += 3.2
        self.rect("detail", x, y, w, 0.6, shade(col, 1.15), 200)
        self.rect("detail", x, y + d - 0.8, w, 0.8, shade(col, 0.8), 200)

    def boat(self, x, y, length, beam, hull, inside=(150, 136, 112), ang=0.0, L="detail"):
        """A small boat drawn up (seen from above), bow towards ang."""
        ca, sa = math.cos(ang), math.sin(ang)
        pts, inner = [], []
        for i in range(17):
            t = i / 16
            s = -length / 2 + length * t
            half = beam / 2 * math.sin(math.pi * min(1.0, 0.15 + t * 0.85)) ** 0.6
            pts.append((s, half))
        outline = pts + [(s, -h) for s, h in reversed(pts)]
        inner = [(s * 0.86, h * 0.7) for s, h in pts] + [(s * 0.86, -h * 0.7) for s, h in reversed(pts)]

        def tr(q):
            return [(x + u * ca - v * sa, y + u * sa + v * ca) for u, v in q]

        self.poly(L, tr(outline), hull)
        self.poly(L, tr(inner), inside)
        self.line(L, tr(outline) + tr(outline)[:1], shade(hull, 0.6), 120, 0.3)
        for s in (-length * 0.15, length * 0.15):
            self.line(L, tr([(s, -beam * 0.33), (s, beam * 0.33)]), shade(inside, 0.7), 200, 0.6)

    # --- ground ---------------------------------------------------------------------
    def quay_edge(self, x0, x1, col):
        """The quay's edge at the water: a lit arris and the capstones."""
        self.box("ground", x0, 0, x1 - x0, 4.0, shade(col, 1.06), "blocks")
        self.rect("ground", x0, 0, x1 - x0, 0.7, shade(col, 1.22), 220)
        self.rect("ground", x0, 4.0, x1 - x0, 0.6, shade(col, 0.66), 200)

    # --- output ---------------------------------------------------------------------
    def save(self, rel, fade=8.0, haze=0.0):
        base = self.layers["ground"]
        for name, (dx, dy), blur, k in LAYERS:
            lay = self.layers[name]
            a = np.asarray(lay.getchannel("A"))
            if not a.any():
                continue
            dx, dy, blur = dx * self.sk, dy * self.sk, blur * math.sqrt(self.sk)
            ox, oy = int(dx * SS), int(dy * SS)
            s = np.zeros_like(a)
            s[oy:, ox:] = a[:a.shape[0] - oy, :a.shape[1] - ox]
            s = np.asarray(Image.fromarray(s).filter(ImageFilter.GaussianBlur(blur * SS)), np.float32) / 255
            under = np.asarray(base.getchannel("A"), np.float32) / 255
            sh = np.zeros(a.shape + (4,), np.uint8)
            sh[..., :3] = SHADOW
            sh[..., 3] = np.clip(s * k * under * 255, 0, 255).astype(np.uint8)
            base = Image.alpha_composite(base, Image.fromarray(sh, "RGBA"))
            base = Image.alpha_composite(base, lay)
        arr = np.asarray(base, np.float32).copy()
        g = np.random.default_rng(self.seed)
        hh, ww = arr.shape[:2]
        low = g.random((hh // 24 + 2, ww // 24 + 2)).astype(np.float32)
        low = np.asarray(Image.fromarray((low * 255).astype(np.uint8)).resize((ww, hh), Image.BICUBIC), np.float32) / 255
        arr[..., :3] *= (1 + (low[..., None] - 0.5) * 0.07)  # gentle weathering
        arr[..., :3] += (g.random((hh, ww)) - 0.5)[..., None] * 9  # fine grain
        arr[..., :3] = np.clip(arr[..., :3], 0, 255)
        if haze:  # atmospheric distance: the back of the picture towards the sea haze
            t = np.clip((np.arange(hh, dtype=np.float32) / SS - HAZE_FROM) / (H - HAZE_FROM), 0, 1)[:, None, None]
            arr[..., :3] = arr[..., :3] * (1 - haze * t) + np.array(HAZE, np.float32) * haze * t
        if fade:
            ramp = np.clip(np.minimum(np.arange(ww), np.arange(ww)[::-1]) / (fade * SS), 0, 1)
            arr[..., 3] *= ramp[None, :]
        img = Image.fromarray(arr.astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(0.5))
        out = os.path.join(ROOT, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        img.resize((W * FINAL, H * FINAL), Image.LANCZOS).save(out, optimize=True)
        print("wrote", rel)


# --- I025: the harbour at its real size -----------------------------------------------
#
# The decks are drawn at about 1 cm per scene unit (the Starling 33's 10 m hull is 1000
# units), so a waterfront house of 5-9 m frontage is 500-900 units wide and the strip
# (1150 x 110 units) holds one or two buildings and a lane. Only its top half shows in
# play, so each place is carried by what is there: the quay's material, the facade's
# colour and its window heads, doors and shutters at their real size, and the roof's
# material and form. The top 14 units stay clear for HarbourDressing's granite coping;
# the house fronts stand on the dressing's own facade line (FRONT); the back of the
# picture fades a little towards the sea haze, with less detail (atmospheric distance).

TK_ROOF = 12.0     # roof materials: tile courses ~28 units, slates ~20, pantile rolls ~31
SK = 6.0           # shadows of true-scale buildings
GROUND_Y, FRONT, EAVES = 14.0, 26.0, 52.0
OVER = 10.0        # the eaves' overhang past the walls
FRAME_WHITE = (232, 230, 222)
GLASS = (52, 60, 66)


def ground(p, col, tex, tk):
    """The look's own quay surface between the coping and the house fronts, and on
    under the lanes."""
    p.box("ground", 0, GROUND_Y, W, H - GROUND_Y, col, tex, tk=tk)
    p.rect("ground", 0, GROUND_Y, W, 1.2, shade(col, 0.7), 150)
    p.rect("ground", 0, FRONT - 3, W, 3, shade(col, 0.76), 150)  # the gutter along the fronts


def front(p, x, w, facade, tex=None, tk=1.0, pitch=250.0, win=100.0, frame=FRAME_WHITE, shutter=None, doors=None,
          arch=False, L="roof", glass=GLASS):
    """The top of the water-facing wall below the eaves (the boat's slight look-down):
    window heads about 1 m wide at their real spacing, shutters folded back, doors."""
    p.box(L, x, FRONT, w, EAVES - FRONT, facade, tex, tk=tk)
    n = max(1, int(round(w / pitch)))
    doors = doors or {}
    for c in range(n):
        cx = x + (c + 0.5) * w / n
        if c in doors:
            dw = 130.0
            p.rect(L, cx - dw / 2, FRONT + 3, dw, EAVES - FRONT - 3, doors[c])
            if arch:
                p.ellipse(L, cx, FRONT + 4, dw / 2, 5, shade(facade, 0.9))
            p.line(L, [(cx, FRONT + 6), (cx, EAVES)], shade(doors[c], 0.6), 160, 1.2)
            continue
        wy0, wy1 = FRONT + 6, EAVES - 5
        if shutter:
            p.rect(L, cx - win / 2 - 46, wy0, 42, wy1 - wy0, shutter)
            p.rect(L, cx + win / 2 + 4, wy0, 42, wy1 - wy0, shutter)
            for k in range(1, 5):  # louvres
                p.line(L, [(cx - win / 2 - 46, wy0 + k * 3.4), (cx - win / 2 - 4, wy0 + k * 3.4)], shade(shutter, 0.7), 120, 0.6)
                p.line(L, [(cx + win / 2 + 4, wy0 + k * 3.4), (cx + win / 2 + 46, wy0 + k * 3.4)], shade(shutter, 0.7), 120, 0.6)
        p.rect(L, cx - win / 2, wy0, win, wy1 - wy0, glass)
        if arch:
            p.ellipse(L, cx, wy0, win / 2, 4, glass)
        if frame:  # the frame, and glazing bars dividing each casement into small lights
            p.rect(L, cx - win / 2 - 3, wy0 - 3, win + 6, 3, frame)
            p.rect(L, cx - win / 2 - 3, wy0, 3, wy1 - wy0, frame)
            p.rect(L, cx + win / 2, wy0, 3, wy1 - wy0, frame)
            p.rect(L, cx - 1.5, wy0, 3, wy1 - wy0, frame)
            p.rect(L, cx - win / 2, (wy0 + wy1) / 2 - 1.2, win, 2.4, frame)
            cols = max(1, int(round((win / 2) / 11.5)))
            for side in (-1, 1):
                for k in range(1, cols):
                    bx = cx + side * (1.5 + k * (win / 2 - 1.5) / cols)
                    p.rect(L, bx - 1.2, wy0, 2.4, wy1 - wy0, frame)
    p.rect(L, x, FRONT, w, 1.0, shade(facade, 1.15), 160)
    p.rect(L, x, EAVES - 5, w, 5, SHADOW, 70)  # the eaves' shadow on the wall
    p.rect(L, x, FRONT, 2.5, EAVES - FRONT, shade(facade, 1.12), 160)
    p.rect(L, x + w - 2.5, FRONT, 2.5, EAVES - FRONT, shade(facade, 0.7), 160)


def roof_ridge(p, x, w, roof, tex, L="roof", over=OVER, gutter=(118, 122, 122)):
    """A pitched roof with its ridge along the quay (beyond the picture): the near plane
    facing the light, a zinc gutter along the eaves."""
    p.box(L, x - over, EAVES, w + 2 * over, H - EAVES, shade(roof, 1.06), tex, "h", EAVES, tk=TK_ROOF)
    p.rect(L, x - over, EAVES + 3, w + 2 * over, 2.0, shade(roof, 1.25), 150)
    p.rect(L, x - over, EAVES - 1, w + 2 * over, 4.5, gutter)
    p.rect(L, x - over, EAVES - 1, w + 2 * over, 1.2, shade(gutter, 1.3))
    p.rect(L, x - over, EAVES, 4, H - EAVES, shade(roof, 1.25), 150)
    p.rect(L, x + w + over - 4, EAVES, 4, H - EAVES, shade(roof, 0.6), 150)


def roof_gable(p, x, w, roof, tex, L="roof", barge=None, over=OVER):
    """A pitched roof end-on to the quay: the left plane lit, the right in shade, the
    ridge running away from the water."""
    mid = x + w / 2
    p.box(L, x - over, EAVES, mid - x + over, H - EAVES, shade(roof, 1.12), tex, "v", x - over, tk=TK_ROOF)
    p.box(L, mid, EAVES, x + w + over - mid, H - EAVES, shade(roof, 0.76), tex, "v", mid, tk=TK_ROOF)
    p.rect(L, mid - 6, EAVES, 12, H - EAVES, shade(roof, 0.92))
    p.rect(L, mid - 6, EAVES, 3, H - EAVES, shade(roof, 1.2), 150)
    p.line(L, [(mid + 6, EAVES), (mid + 6, H)], shade(roof, 0.45), 160, 1.0)
    if barge:  # bargeboards along the verges, a little of them showing
        p.rect(L, x - over, EAVES, 7, H - EAVES, barge)
        p.rect(L, x + w + over - 7, EAVES, 7, H - EAVES, shade(barge, 0.75))


def roof_hip(p, x, w, roof, tex, L="roof", over=OVER):
    """A hipped roof: the near plane between the two hips, the hip ends either side."""
    x0, x1 = x - over, x + w + over
    i = H - EAVES
    p.plane(L, [(x0, EAVES), (x1, EAVES), (x1 - i, H), (x0 + i, H)], shade(roof, 1.04), tex, "h", EAVES, tk=TK_ROOF)
    p.plane(L, [(x0, EAVES), (x0 + i, H), (x0, H)], shade(roof, 1.16), tex, "v", x0, tk=TK_ROOF)
    p.plane(L, [(x1, EAVES), (x1, H), (x1 - i, H)], shade(roof, 0.7), tex, "v", x1 - i, tk=TK_ROOF)
    p.line(L, [(x0, EAVES), (x0 + i, H)], shade(roof, 1.35), 170, 1.6)
    p.line(L, [(x1, EAVES), (x1 - i, H)], shade(roof, 0.5), 170, 1.6)
    p.rect(L, x0, EAVES - 1, x1 - x0, 4.5, (118, 122, 122))


def roof_flat(p, x, w, col, floor="flags", tk=8.0, parapet=18.0, L="roof", edge=None):
    """A roof terrace: the parapet's lit top, the floor inside in its shadow."""
    p.box(L, x, EAVES - 2, w, H - EAVES + 2, shade(col, 0.95), floor, tk=tk)
    p.rect(L, x, EAVES - 2, w, parapet, edge or shade(col, 1.06))
    p.rect(L, x, EAVES - 2, parapet, H - EAVES + 2, edge or shade(col, 1.08))
    p.rect(L, x + w - parapet, EAVES - 2, parapet, H - EAVES + 2, shade(edge or col, 0.82))
    p.rect(L, x + parapet, EAVES - 2 + parapet, w - 2 * parapet, 9, SHADOW, 55)
    p.rect(L, x + parapet, EAVES - 2 + parapet, 9, H, SHADOW, 45)
    p.rect(L, x, EAVES - 2, w, 1.5, shade(edge or col, 1.2), 200)


def gable_face(p, x, w, facade, kind="stepped", h=40.0, tex=None, tk=1.0, coping=(206, 202, 190), L="detail"):
    """A gable rising above the eaves, leaning back over the roof in the tilted top-down
    view: stepped, curved (neck) or a classical pediment."""
    mid = x + w / 2
    if kind == "stepped":
        n = 4
        pts = [(x, EAVES)]
        for k in range(n):
            xa = x + (k + 0.3) * (w / 2) / (n + 0.3)
            pts += [(xa, EAVES + h * k / n), (xa, EAVES + h * (k + 1) / n)]
        pts.append((mid - w * 0.06, EAVES + h))
        right = [(2 * mid - qx, qy) for qx, qy in reversed(pts)]
        pts = pts + [(mid + w * 0.06, EAVES + h)] + right[1:]
    elif kind == "neck":
        pts = [(x, EAVES)]
        for k in range(9):
            t = k / 8
            pts.append((x + w * 0.3 * t, EAVES + h * 0.55 * math.sin(t * math.pi / 2)))
        pts += [(mid - w * 0.14, EAVES + h), (mid + w * 0.14, EAVES + h)]
        for k in range(8, -1, -1):
            t = k / 8
            pts.append((x + w - w * 0.3 * t, EAVES + h * 0.55 * math.sin(t * math.pi / 2)))
    else:  # a pediment or a plain gable
        pts = [(x, EAVES), (mid, EAVES + h), (x + w, EAVES)]
    p.plane(L, pts, facade, tex, tk=tk)
    p.line(L, pts, coping, 230, 3.0)
    p.line(L, [(qx + 1.5, qy + 2.5) for qx, qy in pts], SHADOW, 80, 1.6)
    if kind == "pediment":
        p.line(L, [(x, EAVES + 1.5), (x + w, EAVES + 1.5)], coping, 230, 3.0)


def cornice(p, x, w, col=(236, 232, 222), L="detail"):
    """A classical cornice along the eaves (neoclassical fronts)."""
    p.rect(L, x - OVER, EAVES - 3, w + 2 * OVER, 9, col)
    p.rect(L, x - OVER, EAVES + 6, w + 2 * OVER, 3, SHADOW, 70)


def chimney(p, x, y, w, d, col, pots=2, L="detail"):
    p.rect(L, x, y, w, d, col)
    p.rect(L, x, y, w, 2.5, shade(col, 1.2))
    p.rect(L, x, y, 2.5, d, shade(col, 1.15))
    p.rect(L, x + w - 2.5, y, 2.5, d, shade(col, 0.7))
    for i in range(pots):
        cx = x + (i + 0.5) * w / pots
        p.sphere(L, cx, y + d / 2, min(11.0, w / pots * 0.36), (140, 92, 70), amb=0.5)
        p.ellipse(L, cx, y + d / 2, 5, 5, (30, 28, 26))


def dormer(p, x, w, roof, face, tex="tile", L="detail"):
    """A dormer on the near roof plane: its little face and window, a gabled roof."""
    y = EAVES + 16
    p.rect(L, x, y, w, 16, face)
    p.rect(L, x + w * 0.22, y + 4, w * 0.56, 12, GLASS)
    p.rect(L, x + w * 0.22 - 2, y + 2, w * 0.56 + 4, 2, FRAME_WHITE)
    mid = x + w / 2
    p.box(L, x - 6, y + 16, w / 2 + 6, H - y - 16, shade(roof, 1.14), tex, "v", x - 6, tk=TK_ROOF)
    p.box(L, mid, y + 16, w / 2 + 6, H - y - 16, shade(roof, 0.8), tex, "v", mid, tk=TK_ROOF)
    p.rect(L, mid - 3, y + 16, 6, H - y - 16, shade(roof, 0.9))


def skylight(p, x, roof, L="detail"):
    p.rect(L, x, EAVES + 22, 56, 80, shade(roof, 0.55))
    p.rect(L, x + 5, EAVES + 27, 46, 70, (58, 72, 82))
    p.rect(L, x + 5, EAVES + 27, 46, 4, (120, 136, 146), 160)


def lamp(p, x, y=20.0):
    p.sphere("detail", x, y, 6, (58, 64, 68), amb=0.45)


# --- The nine looks ----------------------------------------------------------------------

def nordic_timber():
    """A small tarred boathouse (naust) gable-end to the water, its doors on the quay, and
    a painted timber house with white window frames and a red tile roof, a birch in the
    lane: the fishing harbours of Scandinavia, the Faroes and Iceland, and timber towns
    elsewhere (Atlantic Canada, New Zealand)."""
    p = Painter(2101, SK)
    ground(p, (128, 128, 122), "slabs", 6.0)
    # the boathouse: falu red boarding, black tarred roof, double doors
    red = (122, 52, 42)
    front(p, 24, 430, red, "board", 10.0, pitch=430, doors={0: (70, 46, 38)}, frame=None)
    roof_gable(p, 24, 430, (62, 64, 66), "shingle", barge=(226, 222, 212))
    # the birch in the lane
    p.tree(520, 128, 120, (112, 128, 84))
    # the house: ochre boarding, red tile, a dormer and a chimney
    ochre = (184, 150, 88)
    front(p, 572, 560, ochre, "board", 10.0, pitch=230, frame=FRAME_WHITE)
    roof_ridge(p, 572, 560, (126, 76, 60), "tile")
    dormer(p, 660, 150, (126, 76, 60), ochre)
    chimney(p, 900, 92, 56, 56, (118, 110, 104), 1)
    p.sphere("detail", 300, 19, 8, (150, 138, 112), amb=0.5, rough=0.3)  # a coil of rope by the doors
    p.box("detail", 120, 15, 60, 9, (90, 116, 132))  # a fish box
    p.save("assets/harbours/looks/nordic_timber.png", haze=0.12)


def gabled_waterfront():
    """A brick town house gable-end to the water with a stepped gable, and a broad
    rendered merchant's house with its ridge along the quay, red tile, a dormer and two
    chimneys, over granite setts: Danish and German harbour towns, the Hanseatic Baltic,
    the Low Countries, and Dutch- and Cape Dutch-built waterfronts."""
    p = Painter(2102, SK)
    ground(p, (124, 124, 118), "setts", 3.6)
    brick = (132, 70, 56)
    front(p, 16, 480, brick, "brick", 7.0, pitch=170, win=90)
    roof_gable(p, 16, 480, (134, 76, 60), "tile")
    gable_face(p, 16, 480, brick, "stepped", 30, "brick", 7.0)
    ochre = (196, 168, 112)
    front(p, 506, 630, ochre, "render", 6.0, pitch=210, win=96, doors={1: (70, 76, 82)})
    roof_ridge(p, 506, 630, (140, 82, 62), "tile")
    dormer(p, 740, 160, (140, 82, 62), ochre)
    chimney(p, 520, 88, 60, 50, (128, 82, 66))
    chimney(p, 1060, 88, 60, 50, (128, 82, 66))
    p.save("assets/harbours/looks/gabled_waterfront.png", haze=0.12)


def atlantic_stone():
    """A granite terrace: grey ashlar and a white-rendered house with sash windows, grey
    slate roofs and a big chimney stack on the party wall: Scotland, Ireland, Wales,
    Brittany, Normandy, Galicia, the Channel Islands, Helsinki's stone quays and Hobart's
    sandstone warehouses."""
    p = Painter(2103, SK)
    ground(p, (122, 124, 120), "flags", 8.0)
    granite = (150, 148, 140)
    front(p, 12, 600, granite, "ashlar", 8.0, pitch=220, win=92, doors={1: (52, 74, 92)})
    roof_ridge(p, 12, 600, (80, 86, 92), "slate")
    white = (222, 220, 212)
    front(p, 612, 528, white, "render", 6.0, pitch=230, win=92)
    roof_ridge(p, 612, 528, (74, 80, 86), "slate")
    chimney(p, 560, 76, 120, 58, (136, 134, 126), 3)  # the stack on the party wall
    skylight(p, 300, (80, 86, 92))
    p.save("assets/harbours/looks/atlantic_stone.png", haze=0.12)


def mediterranean():
    """An ochre house with green shutters under terracotta pantiles, a lane, and a pale
    house with a roof terrace, a pergola and a lemon tree in a pot, over limestone flags:
    Italy, southern France and the French Atlantic's limestone towns, Spain, Portugal,
    Croatia, mainland Greece, Türkiye, Cyprus and Malta."""
    p = Painter(2104, SK)
    ground(p, (196, 186, 166), "flags", 9.0)
    ochre = (214, 178, 124)
    front(p, 14, 560, ochre, "render", 6.0, pitch=270, win=96, frame=None, shutter=(84, 108, 86))
    roof_ridge(p, 14, 560, (170, 100, 72), "pantile", gutter=(160, 96, 70))
    pale = (226, 216, 196)
    front(p, 676, 460, pale, "render", 6.0, pitch=230, win=96, frame=None, shutter=(96, 122, 136), doors={0: (108, 84, 62)})
    roof_flat(p, 676, 460, (214, 204, 186), "flags", 9.0)
    for px in range(720, 1100, 70):  # a pergola's beams
        p.rect("detail", px, 74, 9, 36, (120, 100, 78))
    p.rect("detail", 712, 74, 400, 8, (120, 100, 78))
    p.tree(1080, 98, 32, (96, 114, 72), lumps=5)  # a lemon tree in its pot
    p.tree(625, 140, 100, (86, 100, 66))  # a pine over the lane
    p.save("assets/harbours/looks/mediterranean.png", haze=0.12)


def aegean_island():
    """A whitewashed house with a blue door and shutters under a flat roof, whitewashed
    steps up the lane, and the white chapel with its blue dome: the Cyclades and the
    small Greek islands."""
    p = Painter(2105, SK)
    ground(p, (190, 186, 176), "flags", 7.0)
    for x in range(0, W, 46):  # the whitewashed joints of the paving
        p.line("ground", [(x, GROUND_Y), (x, FRONT - 3)], (240, 238, 232), 150, 1.4)
    white = (236, 234, 228)
    blue = (54, 98, 140)
    front(p, 16, 500, white, "render", 5.0, pitch=250, win=86, frame=None, shutter=blue, doors={1: blue})
    roof_flat(p, 16, 500, (230, 228, 220), "render", 5.0, parapet=20)
    p.box("ground", 520, FRONT, 100, H - FRONT, (226, 222, 214), "flags", tk=6.0)  # the stepped lane
    for y in range(int(FRONT), H, 18):
        p.rect("ground", 520, y, 100, 2.5, (250, 248, 244), 220)
    # the chapel: whitewashed front with an arched blue door, a barrel vault, the dome
    front(p, 630, 500, white, "render", 5.0, pitch=500, doors={0: blue}, arch=True)
    p.box("roof", 630, EAVES - 2, 500, H - EAVES + 2, (232, 230, 224), "render", tk=5.0)
    p.rect("roof", 630, EAVES - 2, 500, 3, (248, 246, 240), 220)
    p.sphere("tall", 880, 196, 150, (58, 104, 150), amb=0.48, gain=1.05)
    p.sphere("detail", 1080, 70, 18, (190, 160, 90), amb=0.5)  # the bell in its gable
    p.save("assets/harbours/looks/aegean_island.png", haze=0.10)


def stone_town():
    """Lime-washed masonry with a carved timber door and a roof terrace behind a
    crenellated parapet, a warm ochre house beside it: Morocco's Atlantic coast and the
    Swahili coast's stone towns."""
    p = Painter(2106, SK)
    ground(p, (176, 168, 150), "flags", 9.0)
    lime = (222, 214, 196)
    front(p, 14, 600, lime, "render", 5.0, pitch=300, win=80, frame=None, glass=(70, 64, 56),
          shutter=(64, 102, 112), doors={1: (98, 70, 48)}, arch=True)
    roof_flat(p, 14, 600, (216, 206, 186), "render", 5.0, parapet=22)
    for mx in range(14, 614, 60):  # the parapet's crenellations
        p.rect("detail", mx, EAVES - 2, 30, 20, shade(lime, 1.04))
    warm = (204, 172, 140)
    front(p, 686, 450, warm, "render", 5.0, pitch=225, win=80, frame=None, glass=(70, 64, 56), shutter=(64, 102, 112))
    roof_flat(p, 686, 450, (200, 176, 146), "flags", 8.0, parapet=20)
    p.box("detail", 760, 80, 140, 30, (110, 92, 70), "board", tk=8.0)  # a timber screen on the terrace
    p.save("assets/harbours/looks/stone_town.png", haze=0.12)


def tropical_town():
    """A sea-green timber house with a veranda under a red tin roof, a palm in the lane,
    and a small yellow chattel house with louvred shutters under galvanised tin: the
    Caribbean, West Africa, the Indian Ocean, Central America and the larger Pacific
    towns."""
    p = Painter(2107, SK)
    ground(p, (150, 150, 142), "flags", 9.0)
    green = (156, 186, 172)
    front(p, 14, 520, green, "board", 10.0, pitch=260, win=96, frame=FRAME_WHITE, shutter=(80, 112, 126), doors={1: (110, 86, 64)})
    p.box("roof", 4, EAVES, 540, 40, (150, 82, 70), "tin", "v", 4, tk=TK_ROOF)  # the veranda roof
    p.rect("roof", 4, EAVES + 40, 540, 3, (100, 56, 48))
    p.box("roof", 4, EAVES + 43, 540, H - EAVES - 43, (138, 74, 64), "tin", "v", 4, tk=TK_ROOF)
    p.palm(640, 136, 150)
    yellow = (224, 206, 146)
    front(p, 734, 400, yellow, "board", 10.0, pitch=200, win=86, frame=FRAME_WHITE, shutter=(84, 118, 104))
    roof_hip(p, 734, 400, (160, 166, 168), "tin")
    p.save("assets/harbours/looks/tropical_town.png", haze=0.12)


def tropical_island():
    """A beach landing: palms, a small painted timber house with a tin roof and a thatched
    open house on posts: the islands of Polynesia, the Cook Islands, Tonga and the
    Grenadines."""
    p = Painter(2108, SK)
    ground(p, (214, 200, 168), "sand", 1.0)
    p.rect("ground", 0, GROUND_Y, W, 6, (190, 178, 150), 140)  # the wet sand by the water's edge
    p.palm(110, 120, 150)
    p.palm(250, 62, 120)
    blue = (110, 150, 168)
    front(p, 340, 400, blue, "board", 10.0, pitch=133, win=86, frame=FRAME_WHITE, doors={1: (226, 222, 210)})
    roof_ridge(p, 340, 400, (150, 84, 70), "tin")
    # the thatched fale: an open house on posts under a thatched hip roof
    for px in (820, 960, 1100):
        p.sphere("detail", px, 40, 9, (108, 86, 62), amb=0.5)
    roof_hip(p, 800, 340, (176, 150, 100), "thatch")
    p.save("assets/harbours/looks/tropical_island.png", haze=0.10)


def volcanic_island():
    """Black basalt paving, a white house with dark basalt corners and window surrounds
    under a red tile hip roof, a hydrangea hedge in the lane, and a white gable-end house
    with basalt trim: the Azores, Madeira, Lanzarote, the Galápagos, the Marquesas,
    Samoa and St Helena."""
    p = Painter(2109, SK)
    ground(p, (74, 72, 70), "blocks", 8.0)
    white = (230, 228, 220)
    basalt = (58, 56, 54)
    front(p, 14, 560, white, "render", 5.0, pitch=240, win=90, frame=basalt, doors={1: (84, 58, 44)})
    for ex in (14, 554):
        p.rect("roof", ex, FRONT, 20, EAVES - FRONT, basalt)
    roof_hip(p, 14, 560, (160, 96, 74), "tile")
    for k in range(4):  # hydrangeas along the lane
        p.tree(616 + k * 22, 44 + (k % 2) * 24, 22, (104, 128, 176), lumps=4)
    p.tree(640, 120, 60, (84, 110, 70))
    front(p, 700, 436, white, "render", 5.0, pitch=218, win=90, frame=basalt)
    for ex in (700, 1116):
        p.rect("roof", ex, FRONT, 20, EAVES - FRONT, basalt)
    roof_gable(p, 700, 436, (152, 92, 72), "tile", barge=basalt)
    p.save("assets/harbours/looks/volcanic_island.png", haze=0.12)


# --- Landmarks of the special harbours ------------------------------------------------------

def nyhavn():
    """Copenhagen, Nyhavn: the cobbled quay and three of the 17th- and 18th-century town
    houses in Nyhavn's own colours - ochre, oxblood and faded blue - with white window
    frames, red tile and dark slate roofs, dormers and chimneys."""
    p = Painter(1673, SK)  # the year Nyhavn was dug
    ground(p, (132, 134, 128), "setts", 3.6)
    houses = [(14, 380, (196, 156, 86), (134, 86, 70), "tile", "ridge"),
              (394, 340, (128, 62, 52), (134, 86, 70), "tile", "gable"),
              (734, 402, (104, 128, 144), (70, 76, 82), "slate", "ridge")]
    for x, w, facade, roof, tex, form in houses:
        front(p, x, w, facade, "render", 6.0, pitch=180, win=86, doors={0: (66, 58, 52)} if form == "gable" else None)
        if form == "gable":
            roof_gable(p, x, w, roof, tex, barge=shade(facade, 1.1))
        else:
            roof_ridge(p, x, w, roof, tex)
            dormer(p, x + w * 0.32, 130, roof, facade, tex)
    chimney(p, 300, 90, 54, 48, (118, 90, 76))
    chimney(p, 1060, 88, 54, 48, (118, 90, 76))
    p.save("assets/harbours/copenhagen/nyhavn.png", haze=0.10)


def valletta_bastions():
    """Valletta: the Grand Harbour waterfront under the bastions - the honey limestone
    stores of the 1750s with their arched doors painted red, green, blue and ochre and
    small-paned windows between them, the flat limestone roof with its parapet; the
    bastion wall rises beyond."""
    p = Painter(1566, SK)  # the year Valletta was founded
    stone = (206, 182, 132)
    ground(p, (176, 162, 134), "flags", 9.0)
    doors = {0: (138, 58, 48), 2: (60, 96, 74), 4: (54, 82, 118), 6: (180, 140, 62)}
    front(p, 10, 1130, stone, "ashlar", 8.0, pitch=141, win=80, doors=doors, arch=True, frame=(226, 218, 196))
    for k in (0, 2, 4, 6):  # the stone arches round the doors
        cx = 10 + (k + 0.5) * 1130 / 8
        p.ellipse("roof", cx, FRONT + 3, 80, 6, shade(stone, 1.12))
    roof_flat(p, 10, 1130, (196, 176, 136), "flags", 9.0, parapet=22, edge=shade(stone, 1.06))
    p.box("roof2", 10, 92, 1130, 18, shade(stone, 1.1), "ashlar", tk=8.0)  # the foot of the bastion
    p.save("assets/harbours/valletta/grand_harbour.png", haze=0.10)


def symi_harbour():
    """Symi, Gialos: neoclassical captains' houses - ochre and salmon render with white
    pilasters and cornices, tall shuttered windows - under tiled hip roofs, a lane of
    steps between them."""
    p = Painter(1832, SK)
    ground(p, (198, 190, 172), "flags", 8.0)
    ochre = (214, 170, 112)
    front(p, 14, 520, ochre, "render", 6.0, pitch=173, win=84, frame=FRAME_WHITE, shutter=(70, 104, 112), doors={1: (88, 70, 56)})
    roof_hip(p, 14, 520, (168, 98, 72), "tile")
    cornice(p, 14, 520)
    p.box("ground", 540, FRONT, 80, H - FRONT, (214, 208, 196), "flags", tk=6.0)
    for y in range(int(FRONT), H, 18):
        p.rect("ground", 540, y, 80, 2.5, (240, 236, 228), 200)
    salmon = (206, 150, 126)
    front(p, 628, 510, salmon, "render", 6.0, pitch=170, win=84, frame=FRAME_WHITE, shutter=(84, 112, 104))
    roof_hip(p, 628, 510, (164, 96, 70), "tile")
    cornice(p, 628, 510)
    for ex in (14, 530, 628, 1134):  # the white pilasters at the corners
        p.rect("detail", ex - 2, FRONT, 10, EAVES - FRONT, (236, 232, 222))
    p.save("assets/harbours/symi/gialos.png", haze=0.10)


def essaouira_skala():
    """Essaouira: the Skala, the old sea bastion - the crenellated parapet along the
    water, the stone wall-walk behind it and the bronze cannons on their timber carriages
    pointing out to sea through the embrasures."""
    p = Painter(1765, SK)
    stone = (178, 164, 136)
    ground(p, (150, 140, 118), "blocks", 8.0)
    p.box("roof", 0, GROUND_Y, W, 30, shade(stone, 1.04), "ashlar", tk=8.0)  # the parapet
    p.rect("roof", 0, GROUND_Y, W, 2.5, shade(stone, 1.25), 200)
    embrasures = [120, 400, 680, 960]
    for ex in embrasures:
        p.rect("roof", ex - 34, GROUND_Y, 68, 30, (118, 108, 90))
    p.box("ground", 0, GROUND_Y + 30, W, H - GROUND_Y - 30, (164, 152, 128), "flags", tk=9.0)  # the wall-walk
    p.rect("ground", 0, GROUND_Y + 30, W, 10, SHADOW, 60)
    for ex in embrasures:  # a cannon on its carriage in each embrasure, muzzle to the sea
        p.box("detail", ex - 52, 54, 104, 70, (110, 88, 64), "board", "v", tk=8.0)
        p.sphere("detail", ex - 44, 92, 14, (84, 70, 52), amb=0.45)
        p.sphere("detail", ex + 44, 92, 14, (84, 70, 52), amb=0.45)
        barrel = [(ex - 15, 22), (ex + 15, 22), (ex + 20, 100), (ex - 20, 100)]
        p.poly("detail", barrel, (70, 84, 74))
        p.poly("detail", [(ex - 15, 22), (ex - 5, 22), (ex - 7, 100), (ex - 20, 100)], (104, 122, 104))
        p.ellipse("detail", ex, 22, 15, 5, (40, 44, 40))
    p.save("assets/harbours/essaouira/skala.png", haze=0.10)


def lunenburg_waterfront():
    """Lunenburg: the big ox-blood red fishing warehouses of the waterfront, clapboard
    with white trim, gable-end to the wharf, over the timber wharf, and a smaller ochre
    building with black trim beside them."""
    p = Painter(1753, SK)
    ground(p, (128, 112, 92), "board", 9.0)
    red = (136, 52, 42)
    front(p, 14, 680, red, "board", 9.0, pitch=227, win=96, frame=FRAME_WHITE, doors={1: (226, 222, 212)})
    roof_gable(p, 14, 680, (64, 66, 68), "shingle", barge=(232, 228, 218))
    ochre = (206, 168, 84)
    front(p, 760, 376, ochre, "board", 9.0, pitch=188, win=90, frame=(40, 40, 40))
    roof_gable(p, 760, 376, (66, 68, 70), "shingle", barge=(44, 44, 44))
    for bx in (60, 400, 860):  # bollards of timber on the wharf
        p.sphere("detail", bx, 20, 12, (96, 82, 64), amb=0.45)
    p.save("assets/harbours/lunenburg/waterfront.png", haze=0.10)


def st_helena_jamestown():
    """St Helena, Jamestown: the wharf's basalt paving, a Georgian house in cream render
    with a grey hipped roof, and the dark cliff of the valley's side rising beside it."""
    p = Painter(1659, SK)
    ground(p, (88, 86, 82), "blocks", 8.0)
    cream = (222, 212, 186)
    front(p, 14, 620, cream, "render", 6.0, pitch=207, win=88, frame=FRAME_WHITE, doors={1: (70, 84, 72)})
    roof_hip(p, 14, 620, (100, 104, 104), "slate")
    pts = [(700, GROUND_Y + 4), (W, GROUND_Y)]
    xx = W
    rng = p.rng
    while xx > 700:
        pts.append((xx, H))
        xx -= rng.uniform(40, 90)
    pts += [(700, H), (680, 60)]
    p.plane("tall", [(690, GROUND_Y + 6), (W, GROUND_Y + 2), (W, H), (720, H), (680, 64)], (96, 84, 72), "rock", tk=6.0)
    for _ in range(6):  # scrub on the cliff
        p.tree(rng.uniform(760, W - 30), rng.uniform(40, 100), rng.uniform(14, 26), (92, 106, 70), lumps=4)
    p.save("assets/harbours/st_helena/jamestown.png", fade=0, haze=0.10)


ALL = {f.__name__: f for f in (nordic_timber, gabled_waterfront, atlantic_stone, mediterranean, aegean_island, stone_town,
                               tropical_town, tropical_island, volcanic_island, nyhavn, valletta_bastions, symi_harbour,
                               essaouira_skala, lunenburg_waterfront, st_helena_jamestown)}

if __name__ == "__main__":
    for name in sys.argv[1:] or ALL:
        ALL[name]()
