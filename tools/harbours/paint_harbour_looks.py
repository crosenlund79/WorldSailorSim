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
    def __init__(self, seed):
        self.seed = seed
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
        d, px0, py0, orient = self._local
        if orient == "v":
            pts = [(v, u) for u, v in pts]
        d.polygon([(x * SS - px0, y * SS - py0) for x, y in pts], fill=tuple(col[:3]) + (a,))

    def plane(self, L, pts, col, tex=None, orient="h", origin=None):
        """A flat surface (roof plane, wall top, paving) filled with a material."""
        xs = [q[0] for q in pts]
        ys = [q[1] for q in pts]
        bx0, by0, bx1, by1 = min(xs) - 1, min(ys) - 1, max(xs) + 1, max(ys) + 1
        px0, py0 = int(math.floor(bx0 * SS)), int(math.floor(by0 * SS))
        bw, bh = int(math.ceil(bx1 * SS)) - px0, int(math.ceil(by1 * SS)) - py0
        tile = Image.new("RGB", (bw, bh), tuple(col[:3]))  # RGB, so translucent strokes blend
        if tex:
            d = ImageDraw.Draw(tile, "RGBA")
            self._local = (d, px0, py0, orient)

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
            TEX[tex](self, R, Ln, E, u0, u1, v0, v1, col, o)
        mask = Image.new("L", (bw, bh), 0)
        ImageDraw.Draw(mask).polygon([(x * SS - px0, y * SS - py0) for x, y in pts], fill=255)
        self.layers[L].paste(tile.convert("RGBA"), (px0, py0), mask)

    def box(self, L, x, y, w, h, col, tex=None, orient="h", origin=None):
        self.plane(L, [(x, y), (x + w, y), (x + w, y + h), (x, y + h)], col, tex, orient, origin)

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
    def save(self, rel, fade=8.0):
        base = self.layers["ground"]
        for name, (dx, dy), blur, k in LAYERS:
            lay = self.layers[name]
            a = np.asarray(lay.getchannel("A"))
            if not a.any():
                continue
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
        if fade:
            ramp = np.clip(np.minimum(np.arange(ww), np.arange(ww)[::-1]) / (fade * SS), 0, 1)
            arr[..., 3] *= ramp[None, :]
        img = Image.fromarray(arr.astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(0.5))
        out = os.path.join(ROOT, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        img.resize((W * FINAL, H * FINAL), Image.LANCZOS).save(out, optimize=True)
        print("wrote", rel)


# --- Archetypes ------------------------------------------------------------------------

def nordic_timber():
    """Painted timber houses and boat sheds (falu red, ochre, white) with steep black and
    red roofs, a granite quay, a fishing shed on piles over the water: the fishing
    harbours of Scandinavia, the Faroes and Iceland, and timber towns elsewhere."""
    p = Painter(2101)
    rng = p.rng
    Q = 19
    p.box("ground", 0, Q, W, H - Q, (104, 108, 90), "grass")
    p.box("ground", 0, 0, W, Q, (134, 134, 128), "slabs")
    p.quay_edge(0, W, (134, 134, 128))
    pier0, pier1 = 700, 782
    # the fishing shed on piles: the quay is cut back to the water there
    p.layers["ground"].paste((0, 0, 0, 0), (pier0 * SS, 0, pier1 * SS, (Q + 1) * SS))
    p.rect("ground", pier0 + 6, 3, pier1 - pier0 - 2, Q - 1, SHADOW, 60)  # its shadow on the water
    for px in range(pier0 + 4, pier1 - 2, 9):
        for py in (2, 9, 16):
            p.sphere("ground", px, py, 1.1, (70, 62, 54), amb=0.45)
    walls = [(122, 52, 42), (174, 140, 80), (210, 206, 194), (122, 52, 42), (96, 58, 46), (166, 128, 74), (204, 198, 184),
             (128, 112, 92)]
    roofs_black = [(66, 68, 70), (74, 76, 76), (60, 62, 64)]
    roofs_red = [(118, 70, 58), (126, 78, 62)]
    x = 6.0
    i = 0
    while x < W - 30:
        if x + 66 > pier0 - 6 and x < pier1 + 6:
            x = pier1 + 8
        shed = i % 3 != 1
        if shed:  # a boat shed, gable-end to the water, boarded
            w = rng.uniform(32, 46)
            d = rng.uniform(46, 62)
            facade = walls[i % len(walls)]
            roof = rng.choice(roofs_black + roofs_red)
            p.lip(x, Q + 1, w, 7, facade, "board", 1, glass=(58, 46, 40), frame=shade(facade, 1.25) if facade[0] < 150 else (240, 238, 230))
            p.gable_roof(x, Q + 8, w, d - 8, roof, "tile" if roof in roofs_red else "shingle")
            p.gable_face(x, Q + 8, w, facade, "plain", h=min(8, w * 0.2), coping=(220, 216, 206), tex="board")
        else:  # a timber house with its ridge along the quay
            w = rng.uniform(48, 66)
            d = rng.uniform(40, 52)
            facade = walls[(i + 2) % len(walls)]
            roof = rng.choice(roofs_black + roofs_red)
            p.lip(x, Q + 3, w, 7.5, facade, "board", None, frame=(226, 224, 216))
            p.ridge_roof(x, Q + 10.5, w, d - 10.5, roof, "tile" if roof in roofs_red else "shingle", 0.48)
            p.chimney(x + w * rng.uniform(0.3, 0.7), Q + 10.5 + (d - 10.5) * 0.48 - 2, 4.4, 3.6, (120, 112, 104), 1)
            if rng.random() < 0.5:
                p.dormer(x + w * 0.4, Q + 11, 9, 9, roof, facade, "shingle")
        x += w + rng.uniform(5, 16)
        if rng.random() < 0.45:  # a birch or rowan behind
            p.tree(x - rng.uniform(0, 6), rng.uniform(80, 98), rng.uniform(8, 12), (98, 118, 78))
        i += 1
    # the shed on piles, and its plank landing
    p.box("roof", pier0 + 2, 1, pier1 - pier0 - 4, 7, (110, 96, 78), "board")
    p.lip(pier0 + 4, 8, pier1 - pier0 - 8, 7, (122, 52, 42), "board", 2, glass=(56, 44, 38), frame=(206, 200, 188))
    p.gable_roof(pier0 + 4, 15, pier1 - pier0 - 8, 44, (66, 68, 70), "shingle")
    p.gable_face(pier0 + 4, 15, pier1 - pier0 - 8, (122, 52, 42), "plain", h=9, coping=(218, 214, 204), tex="board")
    for k in range(3):  # fish boxes and a coil of rope on the quay
        bx = rng.uniform(40, 680)
        p.box("detail", bx, 8, 7, 5, rng.choice([(150, 156, 160), (110, 132, 140), (176, 150, 100)]))
        p.rect("detail", bx, 8, 7, 0.5, (220, 220, 214), 160)
    p.sphere("detail", 820, 10, 2.6, (150, 136, 108), amb=0.5, rough=0.3)
    p.bollards(5.5, 30, W - 20, 96)
    p.save("assets/harbours/looks/nordic_timber.png")


def gabled_waterfront():
    """Brick and rendered townhouses with stepped and curved gables shown at their roof
    ends, red tile and a few dark glazed roofs over a granite-sett quay, and a church
    tower with a green copper spire: Danish and German harbour towns, the Hanseatic
    Baltic, the Low Countries and Dutch-built waterfronts."""
    p = Painter(2102)
    rng = p.rng
    Q = 21
    p.box("ground", 0, Q, W, H - Q, (118, 116, 106), "setts")
    p.box("ground", 0, 0, W, Q, (128, 128, 122), "setts")
    p.quay_edge(0, W, (132, 132, 126))
    p.box("ground", 0, Q - 3, W, 3, (122, 74, 60), "brick")  # the brick gutter band
    facades = [(132, 68, 54), (184, 152, 100), (204, 196, 174), (112, 62, 52), (150, 90, 66), (166, 170, 152), (196, 176, 136),
               (124, 76, 62)]
    roofs = [(134, 74, 58), (144, 84, 64), (128, 70, 56), (66, 66, 66), (140, 80, 62)]
    kinds = ["stepped", "neck", "plain", "stepped", "neck", "stepped", "plain"]
    x = 6.0
    i = 0
    tower_x = 560
    while x < W - 28:
        if abs(x - tower_x) < 34:
            x = tower_x + 36
        facade = facades[i % len(facades)]
        brick = facade in ((132, 68, 54), (112, 62, 52), (150, 90, 66), (124, 76, 62))
        roof = rng.choice(roofs)
        if i % 5 == 2:  # a broad merchant's house, ridge along the quay
            w = rng.uniform(56, 72)
            p.lip(x, Q + 1, w, 8, facade, "brick" if brick else "render", None)
            p.ridge_roof(x, Q + 9, w, 50, roof, "tile", 0.46)
            p.dormer(x + w / 2 - 6, Q + 9.5, 12, 10, roof, facade)
            p.chimney(x + 3, Q + 9 + 23 - 2, 5, 4, (128, 82, 66))
            p.chimney(x + w - 8, Q + 9 + 23 - 2, 5, 4, (128, 82, 66))
        else:  # a narrow town house, gable to the water
            w = rng.uniform(30, 44)
            d = rng.uniform(52, 66)
            p.lip(x, Q + 1, w, 8, facade, "brick" if brick else "render", 2 if w < 38 else 3)
            p.gable_roof(x, Q + 9, w, d, roof, "tile")
            p.gable_face(x, Q + 9, w, facade, kinds[i % len(kinds)], h=min(10, w * 0.26), tex="brick" if brick else None,
                         coping=(206, 202, 190))
            p.chimney(x + w / 2 - 2.5, Q + 9 + d * 0.6, 5, 4, (128, 82, 66), 2)
        x += w + rng.uniform(0, 1.2)
        if rng.random() < 0.18:
            x += rng.uniform(6, 9)  # a narrow lane down to the quay
        i += 1
    # the church: brick nave behind, a square tower with a green copper spire
    p.lip(tower_x - 30, Q + 1, 60, 9, (128, 70, 56), "brick", 2, arch=True, frame=None)
    p.gable_roof(tower_x - 30, Q + 10, 60, 70, (126, 74, 60), "tile")
    p.tower(tower_x - 13, Q + 1, 26, (128, 70, 56), (118, 146, 130), None, 8, n=8, wall_tex="brick")
    for _ in range(5):
        p.tree(rng.uniform(40, W - 40), rng.uniform(88, 104), rng.uniform(9, 13), (90, 108, 76))
    p.bollards(6, 24, W - 20, 90)
    p.save("assets/harbours/looks/gabled_waterfront.png")


def atlantic_stone():
    """Grey granite and sandstone terraces with slate roofs and big chimney stacks on the
    party walls, a few whitewashed or colour-washed fronts, behind a granite quay with
    heavy capstones and iron bollards: Scotland, Ireland, Wales, Brittany, Galicia, the
    Channel Islands and old stone ports like Hobart's."""
    p = Painter(2103)
    rng = p.rng
    Q = 22
    p.box("ground", 0, Q, W, H - Q, (114, 116, 106), "grass")
    p.box("ground", 0, 0, W, Q, (132, 132, 126), "slabs")
    p.quay_edge(0, W, (128, 128, 122))
    fronts = [(150, 148, 142), (172, 156, 128), (212, 210, 202), (140, 140, 136), (200, 194, 172), (164, 176, 180), (156, 150, 138),
              (196, 186, 160)]
    stones = ((150, 148, 142), (172, 156, 128), (140, 140, 136), (156, 150, 138))
    slates = [(78, 84, 90), (86, 90, 96), (72, 76, 82)]
    x = 6.0
    i = 0
    while x < W - 40:
        ws = [rng.uniform(34, 48) for _ in range(rng.randint(3, 5))]  # a terrace under one slate roof
        while ws and x + sum(ws) > W - 6:
            ws.pop()
        if not ws:
            break
        tw = sum(ws)
        d = rng.uniform(42, 50)
        slate = rng.choice(slates)
        ry = Q + 10 + d * 0.47
        xx = x
        for k, w in enumerate(ws):
            front = fronts[(i + k) % len(fronts)]
            p.lip(xx, Q + 2, w, 8, front, "ashlar" if front in stones else "render", 2)
            p.ridge_roof(xx, Q + 10, w, d, shade(slate, rng.uniform(0.94, 1.06)), "slate", 0.47, verge=False,
                         ridge_cap=(112, 108, 102))
            if k:
                p.line("roof", [(xx, Q + 2), (xx, Q + 10 + d)], LINE, 70, 0.3)
            if rng.random() < 0.22:
                p.dormer(xx + w / 2 - 5, Q + 10.5, 10, 9, slate, (206, 204, 196), "slate")
            elif rng.random() < 0.3:  # a skylight
                p.rect("detail", xx + w * 0.3, Q + 13, 4, 5, (70, 80, 88))
                p.rect("detail", xx + w * 0.3, Q + 13, 4, 0.6, (170, 176, 178))
            xx += w
        p.rect("roof", x, Q + 10, 0.8, d, shade(slate, 1.3), 170)
        p.rect("roof", x + tw - 0.8, Q + 10, 0.8, d, shade(slate, 0.6), 170)
        xx = x
        for k in range(len(ws) + 1):  # chimney stacks astride the party walls and gables
            p.chimney(xx - (0 if k == 0 else 7 if k == len(ws) else 3.5), ry - 2.5, 7, 5,
                      (138, 134, 126) if rng.random() < 0.6 else (166, 150, 124), rng.choice((2, 3, 4)))
            if k < len(ws):
                p.rect("detail", xx, Q + 10 + d, 0.9, H - Q - 10 - d, (150, 148, 140))  # back-yard walls
                xx += ws[k]
        x += tw + rng.uniform(7, 12)  # a wynd between terraces
        i += len(ws)
    for bx in range(28, W - 20, 64):
        p.sphere("detail", bx, 6.5, 1.6, (52, 56, 58), amb=0.4)
    for k in range(3):  # lobster creels stacked on the quay
        bx = rng.uniform(60, W - 80)
        for j in range(3):
            p.box("detail", bx + j * 5, 10, 4.4, 6, (120, 98, 70))
            p.line("detail", [(bx + j * 5, 13), (bx + j * 5 + 4.4, 13)], (80, 64, 46), 160, 0.3)
    p.save("assets/harbours/looks/atlantic_stone.png")


def mediterranean():
    """Warm rendered houses (ochre, cream, faded rose) with green and grey shutters under
    terracotta pantiles, hip and pitched, a church with its bell tower seen from above,
    café awnings on a pale limestone quay, umbrella pines behind: Italy, southern France,
    Spain, Portugal, Croatia, mainland Greece, Türkiye, Cyprus and Malta."""
    p = Painter(2104)
    rng = p.rng
    Q = 22
    p.box("ground", 0, Q, W, H - Q, (168, 156, 132), "flags")
    p.box("ground", 0, 0, W, Q, (188, 180, 162), "flags")
    p.quay_edge(0, W, (184, 176, 158))
    walls = [(204, 168, 112), (216, 204, 178), (196, 140, 112), (208, 186, 140), (186, 150, 118), (218, 210, 190), (198, 122, 92)]
    shutters = [(92, 112, 94), (110, 122, 130), (122, 96, 76), (98, 118, 104)]
    tiles = [(162, 100, 78), (170, 114, 88), (152, 94, 74), (164, 108, 84), (146, 100, 84)]
    church = 500
    x = 6.0
    i = 0
    while x < W - 26:
        if church - 70 < x < church + 64:
            x = church + 64
        w = rng.uniform(38, 58)
        d = rng.uniform(40, 56)
        wall = walls[i % len(walls)]
        tile = rng.choice(tiles)
        yo = Q + 1 + rng.uniform(0, 1.5)
        p.lip(x, yo, w, 8, wall, "render", None, glass=(62, 60, 58), frame=None, shutter=shutters[i % len(shutters)])
        if rng.random() < 0.45:
            p.hip_roof(x, yo + 8, w, d, tile, "pantile")
        else:
            p.ridge_roof(x, yo + 8, w, d, tile, "pantile", 0.5, ridge_cap=shade(tile, 0.96))
        if rng.random() < 0.4:
            p.chimney(x + w * rng.uniform(0.2, 0.7), yo + 8 + d * 0.6, 4, 3.4, shade(wall, 0.92), 1)
        if rng.random() < 0.35:  # a café awning over the quay
            p.awning(x + 4, yo - 9, w - 8, 9, (186, 172, 146), (150, 82, 66) if rng.random() < 0.4 else None)
        x += w + rng.uniform(0, 2)
        if rng.random() < 0.15:
            x += rng.uniform(5, 8)
        if rng.random() < 0.22:
            p.tree(x + rng.uniform(-10, 10), rng.uniform(86, 100), rng.uniform(13, 17), (84, 100, 70), lumps=8)
        i += 1
    # the church: a nave gable-end to the water with a pediment, and its bell tower
    p.lip(church - 64, Q + 1, 70, 10, (212, 196, 160), "ashlar", 1, arch=True, frame=None, glass=(70, 62, 54))
    p.gable_roof(church - 64, Q + 11, 70, 76, (158, 100, 80), "pantile")
    p.gable_face(church - 64, Q + 11, 70, (214, 198, 164), "pediment", h=12, coping=(232, 224, 206), tex="ashlar")
    p.tower(church + 18, Q + 1, 30, (206, 188, 150), (160, 100, 78), "pantile", 10, openings=2)
    for _ in range(4):
        p.tree(rng.uniform(40, W - 40), rng.uniform(94, 106), rng.uniform(10, 14), (88, 104, 72), lumps=7)
    p.bollards(6, 20, W - 20, 110, (78, 76, 72))
    p.save("assets/harbours/looks/mediterranean.png")


def aegean_island():
    """Whitewashed cubic houses packed close with flat roofs at different heights, blue
    doors and shutters as small accents, outside stairs, a chapel with its blue dome,
    bougainvillea, a quay of flagstones with whitewashed joints and the dry terraced hill
    behind: the Cyclades and the small Greek islands."""
    p = Painter(2105)
    rng = p.rng
    Q = 20
    p.box("ground", 0, Q, W, H - Q, (178, 166, 136), "grass")
    for k in range(7):  # dry-stone terrace walls on the hill behind
        y = 84 + k * 4.2
        p.line("ground", [(0, y + rng.uniform(-1, 1))] + [(xx, y + rng.uniform(-1.5, 1.5)) for xx in range(60, W + 60, 60)],
               (146, 132, 104), 170, 0.6)
    p.box("ground", 0, 0, W, Q, (176, 172, 162), "flags")
    for xx in range(0, W, 9):  # the whitewashed joints
        p.line("ground", [(xx + rng.uniform(-2, 2), 4.5), (xx + rng.uniform(-2, 2), Q)], (232, 230, 224), 140, 0.4)
    p.quay_edge(0, W, (200, 198, 190))
    p.rect("ground", 0, 0, W, 1.2, (236, 234, 228), 230)
    white = (230, 228, 220)
    blues = [(64, 98, 128), (72, 106, 134), (70, 118, 116), (64, 98, 128)]
    chapel = 640
    for row in (1, 0):  # the row behind first, so the front row's shadows fall on it
        x = 4.0 + row * 9
        i = row * 3
        while x < W - 20:
            if row == 0 and chapel - 46 < x < chapel + 36:
                x = chapel + 36
            w = rng.uniform(22, 38)
            d = rng.uniform(22, 32)
            L = "roof2" if (rng.random() < 0.45) != (row == 1) else "roof"
            yo = (Q + 1 + rng.uniform(0, 3)) if row == 0 else (Q + 34 + rng.uniform(0, 8))
            accent = blues[i % len(blues)]
            p.lip(x, yo, w, 7 if row == 0 else 8, white, "render", max(1, int(w / 14)), glass=accent, frame=None, L=L,
                  shutter=accent if rng.random() < 0.3 else None)
            ly = yo + (7 if row == 0 else 8)
            p.flat_roof(x, ly, w, d, white, 1.1, L)
            if rng.random() < 0.35:
                p.stair_hut(x + rng.uniform(2, w - 11), ly + rng.uniform(3, d - 11), 9, 8, white, accent, "detail")
            elif rng.random() < 0.4:
                p.tank(x + w * rng.uniform(0.3, 0.8), ly + d * rng.uniform(0.3, 0.7), 2.0)
            if rng.random() < 0.3:  # an outside stair up to the roof, along the side wall
                for k in range(5):
                    p.rect("detail", x + w - 0.5 + k * 0.1, ly + 2 + k * 2.2, 3.2, 2.0, shade(white, 1.02 - k * 0.03))
                    p.rect("detail", x + w - 0.5, ly + 3.6 + k * 2.2, 3.2, 0.4, (180, 178, 170))
            if rng.random() < 0.22:  # bougainvillea over a doorway
                p.tree(x + rng.uniform(2, w - 2), yo + rng.uniform(-1, 3), rng.uniform(2.6, 3.6), (138, 74, 98), lumps=4, L="detail")
            x += w + rng.uniform(0.3, 2.5)
            if rng.random() < 0.16:
                x += rng.uniform(5, 8)  # a stepped lane up from the quay
            i += 1
    # the chapel: white walls, a blue dome on its drum, a small bell gable
    p.lip(chapel - 44, Q + 1, 40, 8, white, "render", 1, glass=(64, 98, 128), frame=None, arch=True)
    p.flat_roof(chapel - 44, Q + 9, 40, 40, (236, 234, 228), 1.0)
    p.sphere("roof2", chapel - 24, Q + 29, 13, (228, 226, 220), amb=0.6, gain=0.8)
    p.sphere("tall", chapel - 24, Q + 29, 11, (70, 104, 136), amb=0.38)
    p.sphere("tall", chapel - 24, Q + 29, 1.6, (232, 230, 224), amb=0.6)
    p.box("detail", chapel - 34, Q + 9, 20, 3, (236, 234, 228))
    p.rect("detail", chapel - 26, Q + 9.5, 4, 2, (90, 84, 76))
    for _ in range(7):  # olive trees on the hill
        p.tree(rng.uniform(30, W - 30), rng.uniform(92, 106), rng.uniform(5, 8), (118, 124, 98), lumps=5)
    for _ in range(4):  # tables under a vine on the quay
        p.awning(rng.uniform(40, W - 80), 7, rng.uniform(20, 30), 9, (150, 156, 112))
    p.save("assets/harbours/looks/aegean_island.png")


def stone_town():
    """Lime-washed and sand-coloured masonry with flat roof terraces, parapets, stair huts
    and courtyards, a square minaret, behind a crenellated sea wall: Morocco's Atlantic
    coast and the Swahili coast's stone towns."""
    p = Painter(2106)
    rng = p.rng
    p.box("ground", 0, 0, W, H, (170, 156, 128), "flags")
    # the sea wall: a broad wall-walk with merlons along the water side
    stone = (182, 166, 134)
    p.box("roof", 0, 0, W, 12, stone, "ashlar")
    p.rect("roof", 0, 0, W, 0.8, shade(stone, 1.2), 220)
    p.rect("roof", 0, 12, W, 0.8, shade(stone, 0.66), 220)
    for mx in range(2, W - 4, 8):
        p.box("detail", mx, 0.6, 5, 3, shade(stone, 1.08), "ashlar")
        p.rect("detail", mx, 0.6, 5, 0.5, shade(stone, 1.22))
    walls = [(216, 210, 194), (200, 182, 148), (222, 216, 202), (206, 188, 150), (212, 204, 186)]
    doors = [(66, 96, 126), (92, 70, 52), (70, 104, 96), (92, 70, 52)]
    Y0 = 18
    minaret = 820
    x = 4.0
    i = 0
    while x < W - 24:
        if minaret - 6 < x < minaret + 30:
            x = minaret + 30
        w = rng.uniform(36, 62)
        d = rng.uniform(40, 60)
        wall = walls[i % len(walls)]
        tall = rng.random() < 0.35
        L = "roof2" if tall else "roof"
        Y0 = 18 + rng.uniform(-1, 3)
        p.lip(x, Y0, w, 7, wall, "render", max(1, int(w / 18)), glass=doors[i % len(doors)], frame=None, arch=True, L=L)
        p.flat_roof(x, Y0 + 7, w, d, wall, 1.3, L)
        if w > 48 and rng.random() < 0.5:  # a courtyard open to the sky, with a tree
            cx, cy = x + w / 2, Y0 + 7 + d / 2
            p.box(L, cx - 8, cy - 7, 16, 14, (150, 136, 112), "flags")
            p.rect(L, cx - 8, cy - 7, 16, 2, SHADOW, 90)
            p.rect(L, cx - 8, cy - 7, 2, 14, SHADOW, 70)
            if rng.random() < 0.5:
                p.palm(cx + 1, cy, 8, (98, 114, 76))
            else:
                p.tree(cx + 1, cy, 6, (92, 110, 74), L="tree")
        elif rng.random() < 0.5:
            p.stair_hut(x + rng.uniform(3, w - 14), Y0 + 7 + rng.uniform(3, 12), 11, 10, wall, doors[(i + 1) % len(doors)], "detail")
        if rng.random() < 0.4:  # washing on a line across the terrace
            wy = Y0 + 7 + rng.uniform(16, d - 6)
            p.line("detail", [(x + 4, wy), (x + w - 4, wy)], (110, 104, 96), 200, 0.25)
            for k in range(rng.randint(3, 6)):
                p.rect("detail", x + 6 + k * 5, wy, 3, 2.2, rng.choice([(226, 222, 212), (160, 92, 78), (96, 116, 140), (188, 170, 120)]))
        if rng.random() < 0.3:
            p.tank(x + w * 0.8, Y0 + 7 + d * 0.3, 2.0, (150, 150, 146))
        x += w + rng.uniform(0, 1.2)
        if rng.random() < 0.18:
            x += rng.uniform(4, 7)
        i += 1
    # the square minaret with its lantern
    p.lip(minaret, Y0 - 1, 24, 6, (204, 188, 150), "ashlar", 1, glass=(70, 62, 54), frame=None, arch=True, L="roof2")
    p.box("roof2", minaret, Y0 + 5, 24, 24, (204, 188, 150), "ashlar")
    for mx in range(0, 24, 4):
        p.rect("tall", minaret + mx, Y0 + 5, 2.6, 2, (98, 128, 108))
    p.box("tall", minaret + 6, Y0 + 11, 12, 12, (210, 196, 162), "ashlar")
    p.facets("tall", minaret + 12, Y0 + 17, 6, 4, (98, 128, 108), rot=-math.pi * 3 / 4)
    p.sphere("tall", minaret + 12, Y0 + 17, 1.3, (176, 156, 96), amb=0.5)
    for k in range(4):  # cannon on the wall-walk
        gx = 90 + k * 270
        p.box("detail", gx, 4.5, 3.4, 9, (72, 76, 68))
        p.rect("detail", gx, 4.5, 1.0, 9, (110, 114, 100))
    p.save("assets/harbours/looks/stone_town.png")


def tropical_town():
    """Low houses under painted corrugated tin (red oxide, green, galvanised grey), each
    with a veranda roof along the front, pastel walls, palms and dark mango trees, a
    concrete quay with a timber wharf: the Caribbean, West Africa, the Indian Ocean,
    Central America and the larger Pacific towns."""
    p = Painter(2107)
    rng = p.rng
    Q = 21
    p.box("ground", 0, Q, W, H - Q, (118, 116, 84), "grass")
    p.box("ground", 0, 0, W, Q, (162, 160, 152), "slabs")
    p.quay_edge(0, W, (158, 156, 148))
    p.box("ground", 300, 0, 120, Q, (122, 106, 86), "board", "v")  # a timber wharf section
    p.rect("ground", 300, 0, 120, 1.0, (150, 136, 112), 220)
    walls = [(198, 180, 128), (128, 156, 146), (196, 160, 146), (212, 206, 190), (152, 168, 124), (178, 146, 160), (140, 156, 176)]
    tins = [(136, 76, 62), (92, 114, 100), (150, 154, 150), (106, 126, 136), (128, 84, 66), (160, 162, 156)]
    x = 8.0
    i = 0
    while x < W - 30:
        w = rng.uniform(36, 52)
        d = rng.uniform(34, 46)
        wall = walls[i % len(walls)]
        tin = rng.choice(tins)
        yo = Q + 3 + rng.uniform(0, 4)
        p.lip(x + 2, yo, w - 4, 6, wall, "board" if rng.random() < 0.4 else "render", None, glass=(60, 64, 62), frame=(214, 212, 204),
              shutter=shade(wall, 0.75))
        # the veranda roof, lower and lighter, on its posts
        p.box("roof", x - 2, yo + 6, w + 4, 8, shade(tin, 1.1), "tin", "h", yo + 6)
        p.rect("roof", x - 2, yo + 6, w + 4, 0.6, shade(tin, 1.3), 200)
        p.line("roof", [(x - 2, yo + 14), (x + w + 2, yo + 14)], shade(tin, 0.5), 160, 0.4)
        p.hip_roof(x, yo + 14, w, d, tin, "tin")
        x += w + rng.uniform(10, 22)
        if rng.random() < 0.6:
            p.palm(x - rng.uniform(4, 10), rng.uniform(40, 86), rng.uniform(14, 18))
        if rng.random() < 0.45:
            p.tree(x - rng.uniform(0, 8), rng.uniform(80, 100), rng.uniform(12, 16), (64, 86, 58), lumps=9)
        i += 1
    for _ in range(3):  # painted wooden boats drawn up on the quay
        p.boat(rng.uniform(40, 280), 11, 18, 5.5, rng.choice([(150, 70, 58), (70, 110, 118), (190, 170, 100)]), ang=0.0)
    p.bollards(6, 450, W - 20, 100)
    p.save("assets/harbours/looks/tropical_town.png")


def tropical_island():
    """Small timber houses under tin and thatched fale roofs among coconut palms, on a
    sand beach in place of a paved quay, an outrigger canoe drawn up: the islands of
    Polynesia, the Cook Islands, Tonga and the Grenadines."""
    p = Painter(2108)
    rng = p.rng
    B = 26
    p.box("ground", 0, B - 4, W, H - B + 4, (108, 118, 84), "grass")
    for _ in range(40):  # sandy paths and darker scrub in the grass
        p.ellipse("ground", rng.uniform(0, W), rng.uniform(B + 4, H), rng.uniform(6, 20), rng.uniform(2, 5),
                  rng.choice([(150, 146, 116), (90, 102, 70), (122, 128, 92)]), 110)
    p.box("ground", 0, 0, W, B, (206, 196, 168), "sand")
    p.box("ground", 0, 0, W, 4, (164, 156, 136), "sand")  # wet sand at the water's edge
    for k in range(0, W, 6):  # the lapping edge and wrack line, irregular
        p.ellipse("ground", k + rng.uniform(0, 6), rng.uniform(4, 5.5), rng.uniform(3, 6), 1.2, (178, 170, 148), 220)
        if rng.random() < 0.3:
            p.ellipse("ground", k, rng.uniform(8, 11), rng.uniform(1, 3), 0.5, (126, 116, 92), 160)
    # the beach fades into the water at the top
    g = p.layers["ground"]
    a = np.asarray(g, np.uint8).copy()
    ramp = np.clip(np.arange(a.shape[0]) / (2.5 * SS), 0, 1)
    a[..., 3] = (a[..., 3] * ramp[:, None]).astype(np.uint8)
    p.layers["ground"] = Image.fromarray(a, "RGBA")
    p.draws["ground"] = ImageDraw.Draw(p.layers["ground"], "RGBA")
    k = 0.0
    while k < W:  # the edge of the bush behind the beach, in clumps
        if rng.random() < 0.6:
            for _ in range(rng.randint(1, 3)):
                p.tree(k + rng.uniform(0, 14), B + rng.uniform(0, 7), rng.uniform(4, 7), (88, 104, 70), lumps=4)
        k += rng.uniform(18, 46)
    thatch = (170, 148, 106)
    walls = [(186, 160, 118), (206, 204, 192), (164, 178, 162), (196, 184, 156)]
    x = 20.0
    i = 0
    while x < W - 50:
        if i % 3 != 1:  # an open-sided fale under a thatched hip roof
            w = rng.uniform(30, 40)
            d = rng.uniform(22, 30)
            yo = B + rng.uniform(4, 14)
            p.hip_roof(x, yo, w, d, thatch, "thatch")
        else:  # a small timber house under tin
            w = rng.uniform(28, 36)
            d = rng.uniform(22, 28)
            yo = B + rng.uniform(4, 12)
            p.lip(x, yo, w, 5, walls[i % len(walls)], "board", 2, glass=(58, 60, 58), frame=(220, 218, 210))
            p.ridge_roof(x, yo + 5, w, d, rng.choice([(140, 80, 66), (110, 128, 120), (150, 152, 146)]), "tin", 0.5)
        x += w + rng.uniform(26, 50)
        for _ in range(rng.randint(1, 3)):
            p.palm(x - rng.uniform(6, 22), rng.uniform(16, 96), rng.uniform(13, 18), (96, 116, 72))
        i += 1
    # an outrigger canoe and a dinghy drawn up on the sand
    p.boat(240, 13, 30, 4.4, (120, 98, 74), (150, 128, 96))
    for s in (-8, 8):
        p.line("detail", [(240 + s, 13), (240 + s, 21)], (110, 92, 70), 230, 0.6)
    p.box("detail", 230, 20.5, 22, 2.2, (128, 108, 82))
    p.boat(760, 12, 16, 6, (196, 194, 184), (168, 160, 140))
    p.save("assets/harbours/looks/tropical_island.png")


def volcanic_island():
    """Black basalt quay and dark lava rock at the shore, green slopes divided into small
    fields by black stone walls, a few white houses with dark basalt corners and red
    tile roofs, and a white church with basalt trim: the Azores, Madeira, Lanzarote, the
    Galápagos, the Marquesas, Samoa and St Helena."""
    p = Painter(2109)
    rng = p.rng
    Q = 18
    p.box("ground", 0, Q, W, H - Q, (150, 146, 136), "flags")  # the village's street
    greens = [(98, 120, 80), (110, 128, 84), (88, 110, 74), (122, 130, 88), (78, 98, 66), (104, 124, 78)]
    rows = [52 + k * 12 for k in range(6)]

    def edge(k, x):
        return rows[k] + 3 * math.sin(x / 70 + k * 1.7)

    for k in range(len(rows) - 1):  # small fields between black stone walls up the slope
        xa = -10.0
        while xa < W + 10:
            xb = xa + rng.uniform(26, 64)
            cell = [(xa, edge(k, xa)), (xb, edge(k, xb)), (xb, edge(k + 1, xb)), (xa, edge(k + 1, xa))]
            p.plane("ground", cell, rng.choice(greens), "grass")
            p.line("ground", [(xb, edge(k, xb)), (xb, edge(k + 1, xb))], (46, 46, 44), 230, 0.8)
            xa = xb
    first = [(x, edge(0, x)) for x in range(-10, W + 20, 10)]
    p.plane("ground", [(-10, Q)] + [(W + 20, Q)] + first[::-1], (104, 122, 82), "grass")
    for k in range(len(rows)):
        pts = [(x, edge(k, x)) for x in range(-10, W + 20, 10)]
        p.line("ground", pts, (46, 46, 44), 240, 0.9)
        p.line("ground", [(x, y - 0.5) for x, y in pts], (120, 118, 112), 110, 0.3)
    p.box("ground", 0, 0, W, Q, (70, 68, 66), "blocks")
    p.rect("ground", 0, 0, W, 0.8, (110, 108, 104), 220)
    # lava rock at the shore on both sides of the harbour
    for x0, x1 in ((0, 250), (880, W)):
        pts = [(x0, 0), (x1, 0)]
        xx = x1
        while xx > x0:
            pts.append((xx, rng.uniform(22, 46)))
            xx -= rng.uniform(10, 24)
        pts.append((x0, 40))
        p.plane("roof", pts, (66, 62, 60), "rock")
    tile = (154, 94, 74)
    white = (226, 224, 216)
    church = 600

    def house(hx, yo, w, d, L="roof"):
        p.lip(hx, yo, w, 6, white, "render", max(1, int(w / 14)), glass=(66, 84, 96), frame=None, L=L)
        p.rect(L, hx, yo, 2, 6, (54, 52, 50))
        p.rect(L, hx + w - 2, yo, 2, 6, (54, 52, 50))
        if rng.random() < 0.5:
            p.ridge_roof(hx, yo + 6, w, d, shade(tile, rng.uniform(0.94, 1.06)), "tile", 0.5, L=L)
            p.chimney(hx + w * 0.72, yo + 6 + d * 0.5 - 2, 4, 4, white, 1)
        else:
            p.hip_roof(hx, yo + 6, w, d, shade(tile, rng.uniform(0.94, 1.06)), "tile", L)

    x = 262.0
    while x < 868:  # the village along the harbour
        if church - 34 < x < church + 82:
            x = church + 82
        w = rng.uniform(24, 40)
        if x + w > 870:
            break
        house(x, Q + 2 + rng.uniform(0, 4), w, rng.uniform(20, 28))
        x += w + rng.uniform(1, 12)
    for hx in (296, 380, 470, 700, 790):  # a second row up the street
        house(hx + rng.uniform(-10, 10), Q + 34 + rng.uniform(0, 6), rng.uniform(24, 34), rng.uniform(16, 22))
    for _ in range(7):  # farmhouses among the fields
        house(rng.choice((rng.uniform(20, 220), rng.uniform(900, W - 50))), rng.uniform(56, 86), rng.uniform(20, 28), 16)
    # the white church with black basalt trim, gable to the sea, and its tower
    p.lip(church - 30, Q + 2, 50, 9, (230, 228, 220), "render", 1, glass=(56, 54, 52), frame=None, arch=True)
    for ex in (church - 30, church + 18):
        p.rect("roof", ex, Q + 2, 2, 9, (54, 52, 50))
    p.gable_roof(church - 30, Q + 11, 50, 52, (150, 92, 72), "tile")
    p.gable_face(church - 30, Q + 11, 50, (230, 228, 220), "pediment", h=10, coping=(60, 58, 56))
    p.tower(church + 22, Q + 1, 22, (230, 228, 220), (150, 92, 72), "tile", 8)
    for ex, ey, ew, eh in ((church + 22, Q + 9, 1.4, 22), (church + 42.6, Q + 9, 1.4, 22)):
        p.rect("roof2", ex, ey, ew, eh, (54, 52, 50))
    for _ in range(14):  # trees and hedges between the fields
        p.tree(rng.uniform(30, W - 30), rng.uniform(56, 106), rng.uniform(5, 9), (70, 94, 62), lumps=5)
    p.bollards(5, 270, 870, 80, (40, 40, 40))
    p.save("assets/harbours/looks/volcanic_island.png")


# --- Landmarks of the special harbours --------------------------------------------------

def valletta_bastions():
    """Valletta: the honey limestone bastions straight out of Grand Harbour - the tall
    scarp lit by the sun, the rounded cordon, the parapet and wall-walk, sentry boxes
    (gardjoli) at the salient points - and behind them the dense flat roofs of the city
    over deep, shaded streets, with closed timber balconies (gallariji) on the fronts,
    the Carmelite dome and St Paul's spire."""
    p = Painter(1566)  # the year Valletta was founded
    rng = p.rng
    stone = (206, 182, 132)
    p.box("ground", 0, 12, W, H - 12, (118, 104, 82), "flags")  # the streets, deep in shade; the sea to the wall's foot
    # the curtain wall: scarp, cordon, parapet and wall-walk
    p.box("roof", 0, 12, W, 9, shade(stone, 1.08), "ashlar")
    p.rect("roof", 0, 21, W, 1.4, shade(stone, 1.26))
    p.rect("roof", 0, 22.4, W, 0.9, SHADOW, 90)
    p.box("roof", 0, 23.3, W, 3.2, shade(stone, 1.04), "ashlar")
    p.box("roof", 0, 26.5, W, 9, shade(stone, 0.92), "flags")
    p.rect("roof", 0, 26.5, W, 1.4, SHADOW, 70)
    p.rect("roof", 0, 35, W, 0.8, shade(stone, 0.7))
    for ex in range(20, W, 34):  # embrasures in the parapet
        p.rect("roof", ex, 23.3, 3, 3.2, shade(stone, 0.62))
    for bx in (170, 560, 960):  # the bastions, jutting out towards the water
        a, b = 82, 46
        p.plane("roof", [(bx - a, 12), (bx - b, 0.4), (bx - b, 12)], shade(stone, 1.2), "ashlar")
        p.plane("roof", [(bx - b, 0.4), (bx + b, 0.4), (bx + b, 12), (bx - b, 12)], shade(stone, 1.1), "ashlar")
        p.plane("roof", [(bx + b, 0.4), (bx + a, 12), (bx + b, 12)], shade(stone, 0.86), "ashlar")
        top = [(bx - a + 12, 21), (bx - b + 6, 9), (bx + b - 6, 9), (bx + a - 12, 21)]
        p.plane("roof", top + [(bx + a - 12, 27), (bx - a + 12, 27)], shade(stone, 0.96), "flags")
        p.line("roof", top, shade(stone, 1.3), 255, 1.2)  # the cordon round the salient
        p.line("roof", [(q[0], q[1] + 1.2) for q in top], SHADOW, 90, 0.8)
        p.line("roof", [(bx - a, 12), (bx - b, 0.4), (bx + b, 0.4), (bx + a, 12)], LINE, 70, 0.3)
        for sx in (bx - b + 3, bx + b - 3):  # gardjola: a hexagonal sentry box with its little dome
            p.facets("detail", sx, 4.0, 3.2, 6, shade(stone, 1.06))
            p.sphere("detail", sx, 4.0, 2.2, shade(stone, 1.05), amb=0.5)
    # the city behind: flat-roofed blocks between straight streets
    roofs = [(206, 182, 132), (216, 200, 160), (196, 176, 136), (186, 178, 160), (210, 190, 146)]
    balconies = [(92, 112, 92), (124, 70, 58), (86, 102, 118), (146, 128, 92), (92, 112, 92)]
    for row, (y0, y1) in enumerate(((40, 72), (77, H + 2))):
        x = 3.0 + row * 22
        while x < W - 10:
            blockw = min(rng.uniform(80, 120), W - 3 - x)
            xx = x
            while xx < x + blockw - 10:
                w = min(rng.uniform(15, 28), x + blockw - xx)
                L = "roof2" if rng.random() < 0.35 else "roof"
                col = rng.choice(roofs)
                p.lip(xx, y0, w, 5, shade(col, 0.96), "ashlar", max(1, int(w / 10)), glass=(70, 64, 56), frame=None, L=L)
                p.flat_roof(xx, y0 + 5, w, y1 - y0 - 5, col, 1.0, L, "flags")
                if rng.random() < 0.65:  # a gallarija, the closed timber balcony
                    gw = min(w - 3, rng.uniform(7, 11))
                    gx = xx + rng.uniform(1.5, max(1.6, w - gw - 1.5))
                    bc = rng.choice(balconies)
                    p.box("detail", gx, y0 - 2.6, gw, 4.0, bc, "board", "v")
                    p.rect("detail", gx, y0 - 2.6, gw, 0.6, shade(bc, 1.3))
                if rng.random() < 0.35:
                    p.stair_hut(xx + 2, y0 + 8, 7, 7, col, (90, 80, 66), "detail")
                if rng.random() < 0.35:
                    p.tank(xx + w * 0.7, y0 + (y1 - y0) * 0.65, 1.6, (176, 172, 164))
                xx += w
            x += blockw + 5  # a straight street running up from the harbour
    # the Carmelite church's dome on its drum, and St Paul's spire
    p.sphere("roof2", 430, 72, 24, shade(stone, 1.0), amb=0.55, gain=0.9)
    p.sphere("tall", 430, 72, 19, (148, 148, 144), amb=0.36)
    for k in range(12):
        a = 2 * math.pi * k / 12
        p.line("tall", [(430 + 4 * math.cos(a), 72 + 4 * math.sin(a)), (430 + 18.5 * math.cos(a), 72 + 18.5 * math.sin(a))],
               (110, 110, 108), 120, 0.4)
    p.sphere("tall", 430, 72, 4.2, shade(stone, 1.05), amb=0.5)
    p.tower(752, 42, 18, shade(stone, 1.02), shade(stone, 0.98), None, 6, n=8)
    p.save("assets/harbours/valletta/grand_harbour.png")


def symi_harbour():
    """Symi: tiers of neoclassical houses at Gialos in ochre, rose, cream and soft grey,
    pediments facing the harbour and tiled hip roofs, stepping up the hill with stair
    lanes between them, and the clock tower on the quay."""
    p = Painter(1881)  # the clock tower's year
    rng = p.rng
    Q = 20
    p.box("ground", 0, Q, W, H - Q, (176, 166, 144), "flags")
    p.box("ground", 0, 0, W, Q, (186, 180, 166), "flags")
    p.quay_edge(0, W, (190, 184, 170))
    walls = [(202, 166, 112), (196, 150, 132), (216, 206, 182), (166, 172, 170), (186, 130, 98), (208, 186, 142), (178, 160, 150),
             (224, 220, 208)]
    tiles = [(160, 98, 76), (150, 94, 74), (168, 110, 86), (142, 96, 80)]
    clock = 560
    tiers = ((Q + 1, 7, "roof", 24), (Q + 33, 9, "roof2", 22), (Q + 64, 10, "roof2", 26))
    for tier in (2, 1, 0):  # back to front, so each tier's shadow falls on the one above
        y0, lip, L, dd = tiers[tier]
        x = 4.0 + tier * 11
        i = tier * 3
        while x < W - 20:
            if tier == 0 and clock - 6 < x + 30 and x < clock + 24:
                x = clock + 24
            w = rng.uniform(28, 44)
            d = dd + rng.uniform(-3, 3)
            yo = y0 + rng.uniform(-1.5, 2)
            wall = walls[i % len(walls)]
            tile = rng.choice(tiles)
            p.lip(x, yo, w, lip, wall, "render", max(2, int(w / 12)), glass=(70, 92, 96), frame=(230, 226, 214), L=L,
                  trim=(232, 228, 216))
            ly = yo + lip
            kind = rng.random()
            if kind < 0.3:
                p.gable_roof(x, ly, w, d, tile, "tile", L)
                p.gable_face(x, ly, w, wall, "pediment", h=min(6, w * 0.15), coping=(234, 230, 220))
            elif kind < 0.88:
                p.hip_roof(x, ly, w, d, tile, "tile", L)
            else:
                p.flat_roof(x, ly, w, d, (222, 218, 206), 1.0, L)
            x += w + rng.uniform(0.5, 3)
            if rng.random() < 0.2:  # a stepped lane up the hill
                for k in range(int(dd / 2.5)):
                    p.rect("ground", x + 0.5, y0 + lip + k * 2.5, 5, 0.5, (150, 140, 120), 200)
                x += 6
            i += 1
    p.tower(clock, 3, 16, (222, 212, 188), (150, 94, 74), "tile", 5)
    p.ellipse("roof2", clock + 8, 5.5, 1.6, 1.4, (238, 236, 228))  # the clock face
    for k in range(4):  # café awnings along the quay
        p.awning(70 + k * 280 + rng.uniform(-20, 20), 9, 30, 8, (192, 182, 160))
    p.save("assets/harbours/symi/gialos.png")


def essaouira_skala():
    """Essaouira: the Skala, the ochre sea rampart with its merlons and the row of old
    bronze cannon pointing out to sea, a square bastion tower, and the white medina with
    blue doors and shutters behind."""
    p = Painter(1765)
    rng = p.rng
    stone = (176, 148, 108)
    p.box("ground", 0, 0, W, H, (180, 166, 136), "flags")
    WW = 22
    p.box("roof", 0, 0, W, WW, shade(stone, 0.98), "slabs")
    p.box("roof", 0, 0, W, 4, shade(stone, 1.1), "ashlar")
    p.rect("roof", 0, 0, W, 0.8, shade(stone, 1.24))
    p.rect("roof", 0, WW - 0.8, W, 0.8, shade(stone, 0.66))
    for mx in range(3, W - 6, 26):  # merlons with embrasures between, cannon in each
        p.box("detail", mx, 0.5, 17, 5.5, shade(stone, 1.06), "ashlar")
        p.rect("detail", mx, 0.5, 17, 0.7, shade(stone, 1.25))
        p.rect("detail", mx + 16.3, 0.5, 0.7, 5.5, shade(stone, 0.75))
    for gx in range(23, W - 10, 26):
        p.box("detail", gx - 3, 9, 6, 7, (104, 82, 60), "board", "v")  # the carriage
        p.box("detail", gx - 1.6, 1.0, 3.2, 12, (84, 92, 78))
        p.rect("detail", gx - 1.6, 1.0, 1.0, 12, (122, 130, 108))
        p.ellipse("detail", gx, 1.4, 1.9, 1.0, (70, 76, 64))
    # the square bastion tower at the north end
    p.box("roof2", 880, 0, 80, 40, shade(stone, 1.02), "slabs")
    p.rect("roof2", 880, 0, 80, 0.8, shade(stone, 1.24))
    for mx in range(882, 958, 9):
        p.box("tall", mx, 0, 6, 3, shade(stone, 1.08), "ashlar")
    for my in range(5, 38, 9):
        p.box("tall", 880, my, 3, 6, shade(stone, 1.12), "ashlar")
        p.box("tall", 957, my, 3, 6, shade(stone, 0.9), "ashlar")
    # the medina behind: white terraces, a few ochre houses, blue accents
    walls = [(226, 224, 216), (230, 228, 222), (204, 186, 150), (224, 220, 210), (218, 214, 204)]
    blue = (66, 100, 134)
    for row, (y0, y1) in enumerate(((WW + 4, 66), (70, H + 2))):
        x = 4.0 + row * 14
        i = row
        while x < W - 16:
            if row == 0 and 872 < x + 40 and x < 962:
                x = 962
            w = rng.uniform(28, 48)
            wall = walls[i % len(walls)]
            L = "roof2" if rng.random() < 0.35 else "roof"
            p.lip(x, y0, w, 5.5, wall, "render", max(1, int(w / 16)), glass=blue if rng.random() < 0.6 else (72, 64, 56), frame=None,
                  arch=True, L=L)
            p.flat_roof(x, y0 + 5.5, w, y1 - y0 - 5.5, wall, 1.1, L)
            if rng.random() < 0.4:
                p.stair_hut(x + rng.uniform(2, w - 12), y0 + 9, 10, 9, wall, blue, "detail")
            if rng.random() < 0.3:
                p.tank(x + w * 0.7, y0 + 22, 1.8, (160, 160, 156))
            x += w + rng.uniform(0, 1.5)
            if rng.random() < 0.15:
                x += 5
            i += 1
    for _ in range(3):
        p.palm(rng.uniform(80, 860), rng.uniform(70, 100), 9, (100, 112, 74))
    p.save("assets/harbours/essaouira/skala.png")


def lunenburg_waterfront():
    """Lunenburg: the red timber fish stores and chandleries of the old fishing town,
    gable-end to the wharves with white trim and black roofs, and behind them the
    painted houses with the town's 'bump' dormers and a white church spire."""
    p = Painter(1753)  # the town's founding
    rng = p.rng
    Q = 22
    p.box("ground", 0, Q, W, H - Q, (118, 116, 104), "grass")
    p.box("ground", 0, 0, W, Q, (118, 104, 86), "board", "v")
    p.rect("ground", 0, 0, W, 1.0, (152, 138, 114), 220)
    for px in range(4, W, 12):
        p.sphere("ground", px, 1.6, 1.1, (82, 74, 64), amb=0.45)
    red = (138, 60, 50)
    stores = [red, red, (172, 140, 80), red, (110, 120, 128), red]
    x = 14.0
    i = 0
    while x < W - 80:
        w = rng.uniform(64, 92)
        d = rng.uniform(40, 50)
        col = stores[i % len(stores)]
        p.lip(x, Q + 1, w, 8, col, "board", 3, frame=(230, 228, 220), trim=(228, 226, 218))
        p.rect("roof", x, Q + 1, 1.2, 8, (228, 226, 218))
        p.rect("roof", x + w - 1.2, Q + 1, 1.2, 8, (228, 226, 218))
        p.gable_roof(x, Q + 9, w, d, (70, 72, 74), "shingle")
        p.gable_face(x, Q + 9, w, col, "plain", h=10, coping=(232, 230, 222), tex="board")
        x += w + rng.uniform(14, 26)
        i += 1
    houses = [(184, 150, 84), (104, 120, 136), (130, 146, 118), (132, 66, 56), (212, 206, 192), (150, 110, 120), (96, 128, 128)]
    x = 6.0
    i = 0
    while x < W - 30:  # the painted houses up the hill, with their bump dormers
        w = rng.uniform(34, 46)
        y0 = 76 + rng.uniform(-2, 3)
        col = houses[i % len(houses)]
        p.lip(x, y0, w, 6, col, "board", 2, frame=(230, 228, 220), L="roof2")
        p.ridge_roof(x, y0 + 6, w, 30, (78, 80, 82), "shingle", 0.48, L="roof2")
        p.dormer(x + w / 2 - 5, y0, 10, 12, (78, 80, 82), col, "shingle")
        x += w + rng.uniform(4, 10)
        if rng.random() < 0.3:
            p.tree(x - 2, 104, 8, (90, 110, 76))
        i += 1
    p.tower(1000, 62, 16, (226, 224, 216), (222, 220, 212), None, 5, n=8, wall_tex="board")  # the white church spire
    for _ in range(3):  # dories at the wharf
        p.boat(rng.uniform(40, W - 60), 11, 16, 5, (196, 190, 176), (138, 116, 86))
    p.save("assets/harbours/lunenburg/waterfront.png")


def st_helena_jamestown():
    """Jamestown, St Helena: the town's one street of Georgian houses squeezed into a
    narrow valley between steep dark volcanic cliffs, the sea wall and landing, the
    church at the valley mouth, and the long straight stair of Jacob's Ladder."""
    p = Painter(1659)
    rng = p.rng
    V0, V1 = 450, 700
    p.box("ground", V0 - 40, 0, V1 - V0 + 80, H, (150, 140, 120), "flags")
    p.box("ground", V0 - 40, 0, V1 - V0 + 80, 9, (120, 118, 112), "blocks")  # the sea wall
    p.rect("ground", V0 - 40, 0, V1 - V0 + 80, 0.8, (160, 158, 150), 220)
    cliff = (82, 72, 66)
    for side in (0, 1):  # the two cliffs, falling to the sea
        if side == 0:
            pts = [(0, 0), (V0 - 6, 0), (V0 + 6, 20), (V0 + 4, 60), (V0 + 14, H), (0, H)]
        else:
            pts = [(W, 0), (V1 + 6, 0), (V1 - 6, 24), (V1 - 2, 60), (V1 - 12, H), (W, H)]
        p.plane("roof", pts, cliff, "rock")
        edge = pts[1:5] if side == 0 else pts[1:5]
        p.line("roof", edge, (40, 36, 34), 160, 0.8)
    relief = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    rd = ImageDraw.Draw(relief, "RGBA")
    for side in (0, 1):  # the cliffs' relief: ridges lit on their left, gullies in shade
        for _ in range(14):
            gx = rng.uniform(20, V0 - 50) if side == 0 else rng.uniform(V1 + 40, W - 20)
            pts = [(gx, rng.uniform(-4, 6))]
            while pts[-1][1] < H + 6:
                pts.append((pts[-1][0] + rng.uniform(-6, 6), pts[-1][1] + rng.uniform(6, 14)))
            wd = rng.uniform(6, 14)
            lit = [(x - wd * rng.uniform(0.6, 1.0), y) for x, y in pts]
            dark = [(x + wd * rng.uniform(0.6, 1.0), y) for x, y in pts]
            rd.polygon([(x * SS, y * SS) for x, y in pts + lit[::-1]], fill=(222, 206, 180, 50))
            rd.polygon([(x * SS, y * SS) for x, y in pts + dark[::-1]], fill=SHADOW + (80,))
    relief = relief.filter(ImageFilter.GaussianBlur(2.5 * SS))
    ra = np.asarray(relief, np.uint8).copy()
    ra[..., 3] = (ra[..., 3].astype(np.float32) * (np.asarray(p.layers["roof"].getchannel("A"), np.float32) / 255)).astype(np.uint8)
    p.layers["roof"].alpha_composite(Image.fromarray(ra, "RGBA"))
    for _ in range(40):  # scrub and green ledges clinging to the cliffs
        gx = rng.choice((rng.uniform(20, V0 - 30), rng.uniform(V1 + 30, W - 20)))
        p.tree(gx, rng.uniform(14, H - 6), rng.uniform(2.5, 5), (96, 108, 78), lumps=3, L="detail")
    # Jacob's Ladder: a straight stair up the western cliff
    a, b = (V0 + 2, 64), (V0 - 150, H + 2)
    p.line("detail", [a, b], (196, 190, 176), 255, 2.4)
    for k in range(60):
        t = k / 60
        x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        p.line("detail", [(x - 0.4, y - 1.4), (x + 0.4, y + 1.4)], (130, 124, 112), 200, 0.25)
    walls = [(222, 218, 206), (212, 196, 152), (196, 204, 194), (220, 206, 190), (214, 212, 202)]
    roofs = [(84, 88, 94), (128, 74, 64), (92, 96, 100)]
    # the church at the valley mouth, then the houses up the street
    p.lip(V0 + 8, 11, 44, 8, (214, 208, 196), "ashlar", 2, arch=True, frame=None)
    p.ridge_roof(V0 + 8, 19, 44, 34, (84, 88, 94), "slate", 0.5)
    p.tower(V0 + 12, 2, 15, (214, 208, 196), (84, 88, 94), "slate", 5)
    for row, y0 in enumerate((12, 52, 84)):
        x = V0 + (60 if row == 0 else 20 + row * 6)
        i = row * 2
        while x < V1 - 28 - row * 4:
            w = rng.uniform(24, 34)
            col = walls[i % len(walls)]
            p.lip(x, y0, w, 7, col, "render", 2, frame=(236, 234, 226))
            if rng.random() < 0.5:
                p.hip_roof(x, y0 + 7, w, 26, rng.choice(roofs), "slate")
            else:
                p.ridge_roof(x, y0 + 7, w, 26, rng.choice(roofs), "slate", 0.5)
            x += w + rng.uniform(0.5, 2)
            i += 1
    for _ in range(4):
        p.tree(rng.uniform(V0 + 40, V1 - 40), rng.uniform(44, 50), rng.uniform(5, 7), (86, 106, 72))
    p.save("assets/harbours/st_helena/jamestown.png", fade=0)


ALL = {f.__name__: f for f in (nordic_timber, gabled_waterfront, atlantic_stone, mediterranean, aegean_island, stone_town,
                               tropical_town, tropical_island, volcanic_island, valletta_bastions, symi_harbour,
                               essaouira_skala, lunenburg_waterfront, st_helena_jamestown)}

if __name__ == "__main__":
    for name in sys.argv[1:] or ALL:
        ALL[name]()
