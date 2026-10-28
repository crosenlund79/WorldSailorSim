"""A small painterly renderer for the companion clips (I024).

The animals are modelled as soft 3D puppets: ellipsoids (head, ribcage,
pelvis, muzzle, paws) and chains of ellipsoids (legs, tails, ears, feathers).
Every frame is ray-cast from the game's view (from above and a little in
front: the camera is ELEVATION degrees above the horizon, looking along -Y),
then painted in the Real Horizon manner (DEV_GUIDES/ART_DIRECTION.md):

  * soft tonal washes lit from the upper left (wrap lighting on the puppet's
    smoothed normals, a little occlusion where parts meet),
  * short directional fur / feather strokes anchored to each part's surface,
    so the coat moves with the animal instead of "boiling" between frames,
  * a few fine hairs breaking the outline,
  * at most a thin, translucent blue-grey line (#2A3236),
  * a soft contact shadow on the ground.

Everything is deterministic: random strokes are seeded by stable part keys.

World units are final canvas pixels. +X right, +Y towards the viewer, +Z up.
The ground point of the animal is `origin` on the canvas.
"""
import hashlib
import math

import numpy as np
from PIL import Image, ImageDraw

N = 256                  # final canvas, px
SS = 3                   # supersampling
S = N * SS
ELEVATION = math.radians(50.0)
SE, CE = math.sin(ELEVATION), math.cos(ELEVATION)
VIEW = np.array([0.0, CE, SE])          # towards the camera
LINE = (42, 50, 54)                     # the art direction's line colour
SHADOW = (24, 32, 38)


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


LIGHT = unit((-0.55, 0.12, 0.83))       # upper left of the picture, a little from the front


def rot_x(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]], dtype=np.float64)


def rot_y(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]], dtype=np.float64)


def rot_z(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]], dtype=np.float64)


def frame_from(xdir, up=(0.0, 0.0, 1.0)):
    """A rotation whose local x is `xdir` and whose local z leans to `up`."""
    x = unit(xdir)
    y = np.cross(unit(up), x)
    if np.linalg.norm(y) < 1e-6:
        y = np.cross((0.0, 1.0, 0.0), x)
    y = unit(y)
    z = np.cross(x, y)
    return np.column_stack([x, y, z])


def lerp(a, b, t):
    return np.asarray(a, dtype=np.float64) + (np.asarray(b, dtype=np.float64) - np.asarray(a, dtype=np.float64)) * t


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    """Colour mix; `t` may be an array (n,) -> (n, 3)."""
    a = np.asarray(a, dtype=np.float64)
    b = np.asarray(b, dtype=np.float64)
    t = np.asarray(t, dtype=np.float64)
    if t.ndim:
        return a[None, :] + (b - a)[None, :] * t[:, None]
    return a + (b - a) * t


def seed_of(key):
    return int(hashlib.md5(key.encode()).hexdigest()[:8], 16)


# --- Blur (numpy only) ---------------------------------------------------------------

def _box(a, r, axis):
    if r < 1:
        return a
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad), axis=axis)
    n = a.shape[axis]
    hi = np.take(c, np.arange(2 * r + 1, 2 * r + 1 + n), axis=axis)
    lo = np.take(c, np.arange(0, n), axis=axis)
    return (hi - lo) / (2 * r + 1)


def blur(a, sigma):
    """Approximate gaussian (three box passes) on a float array (H, W[, C])."""
    if sigma <= 0.3:
        return a
    w = math.sqrt(4 * sigma * sigma + 1)
    r = max(1, int(round((w - 1) / 2)))
    out = a.astype(np.float32)
    for _ in range(3):
        out = _box(out, r, 0)
        out = _box(out, r, 1)
    return out


# --- Primitives --------------------------------------------------------------------------

class Prim:
    """An ellipsoid: centre c, radii r (local x, y, z), rotation R (columns =
    local axes in world). `colour(u, prim)` gives the base colour for local
    unit-sphere points u (n, 3). `flow` is the lie of the coat in local
    coordinates (a vector, or a callable u -> vectors)."""

    def __init__(self, c, r, R=None, piece="body", colour=(128, 128, 128), key="p", flow=(-1.0, 0.0, -0.3),
                 fur=1.0, t=0.0, edge=1.0, data=None):
        self.c = np.asarray(c, dtype=np.float64)
        self.r = np.maximum(np.asarray(r, dtype=np.float64), 0.05)
        self.R = np.eye(3) if R is None else np.asarray(R, dtype=np.float64)
        self.piece = piece
        self.colour = colour
        self.key = key
        self.flow = flow
        self.fur = fur
        self.t = t
        self.edge = edge
        self.data = data or {}

    @property
    def A(self):
        return self.R * self.r[None, :]

    def world(self, u):
        """Local unit-sphere points (n, 3) -> world points."""
        return self.c[None, :] + (u * self.r[None, :]) @ self.R.T

    def normal(self, u):
        n = (u / self.r[None, :]) @ self.R.T
        return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)

    def base_colour(self, u):
        if callable(self.colour):
            return np.asarray(self.colour(u, self), dtype=np.float64)
        return np.broadcast_to(np.asarray(self.colour, dtype=np.float64), (len(u), 3)).copy()


def chain(points, radii, piece, colour, key, count, flat=None, up=(0, 0, 1), flow=None, fur=1.0, edge=1.0, overlap=1.6,
          thickness=None):
    """Ellipsoids along a smooth curve through `points` (Catmull-Rom).
    radii: callable t -> radius (or (width, thickness) when flat).
    `flat`: a callable t -> plane normal for flat chains (ears, feathers)."""
    pts = [np.asarray(p, dtype=np.float64) for p in points]
    curve = catmull(pts, 64)
    lengths = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(curve, axis=0), axis=1))])
    total = max(lengths[-1], 1e-6)
    prims = []
    for k in range(count):
        t = k / max(count - 1, 1)
        s = t * total
        i = int(np.searchsorted(lengths, s, side="right") - 1)
        i = min(max(i, 0), len(curve) - 2)
        f = (s - lengths[i]) / max(lengths[i + 1] - lengths[i], 1e-9)
        c = curve[i] + (curve[i + 1] - curve[i]) * f
        tan = unit(curve[i + 1] - curve[i])
        step = total / max(count - 1, 1)
        rad = radii(t)
        if flat is not None:
            nrm = unit(flat(t))
            R = frame_from(tan, nrm)          # local z = plane normal
            w, th = rad
            r = (max(step * overlap * 0.5, th), w, th)
        else:
            R = frame_from(tan, up)
            r = (max(step * overlap * 0.5, rad * 0.9), rad, rad)
        prims.append(Prim(c, r, R, piece, colour, "%s.%d" % (key, k), flow if flow is not None else (1.0, 0.0, 0.0),
                          fur=fur, t=t, edge=edge))
    return prims


def catmull(pts, steps=32):
    if len(pts) == 2:
        return np.array([lerp(pts[0], pts[1], k / steps) for k in range(steps + 1)])
    ext = [pts[0] + (pts[0] - pts[1])] + list(pts) + [pts[-1] + (pts[-1] - pts[-2])]
    out = []
    per = max(4, steps // (len(pts) - 1))
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for k in range(per):
            t = k / per
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return np.array(out)


def ik(a, b, root, target, hint):
    """Two-bone IK: the joint between bones of length a and b, bent towards
    `hint` (a world direction)."""
    root = np.asarray(root, dtype=np.float64)
    target = np.asarray(target, dtype=np.float64)
    d_vec = target - root
    d = np.linalg.norm(d_vec)
    d = min(max(d, abs(a - b) + 1e-3), a + b - 1e-3)
    u = unit(d_vec)
    h = np.asarray(hint, dtype=np.float64)
    h = unit(h - np.dot(h, u) * u)
    x = (a * a - b * b + d * d) / (2 * d)
    y = math.sqrt(max(a * a - x * x, 0.0))
    return root + u * x + h * y


# --- Scene and rendering ----------------------------------------------------------------

class Style:
    def __init__(self, **kw):
        self.stroke_len = (2.0, 4.0)        # px (final)
        self.stroke_density = 0.35          # strokes per px^2 of part surface
        self.stroke_alpha = (0.42, 0.34)    # light, dark strokes
        self.stroke_width = 0.65            # px (final)
        self.edge_len = (1.5, 3.0)
        self.edge_density = 0.25
        self.edge_alpha = 0.75
        self.line_alpha = 0.33              # outer outline
        self.inner_line_alpha = 0.22        # where one part overlaps another
        self.smooth = 1.6                   # normal smoothing within a piece (px)
        self.ao = 0.32
        self.ambient = 0.55
        self.diffuse = 0.58
        self.wrap = 0.55
        self.shadow_alpha = 0.30
        self.contact_alpha = 0.30
        self.__dict__.update(kw)


class Scene:
    def __init__(self, origin=(128.0, 160.0), style=None):
        self.origin = origin
        self.prims = []
        self.decals = []        # callables (ctx) after shading and fur
        self.style = style or Style()
        self.shadow = "ground"  # or "flight" or None

    def add(self, items):
        if isinstance(items, Prim):
            self.prims.append(items)
        else:
            self.prims.extend(items)

    def screen(self, p):
        p = np.asarray(p, dtype=np.float64)
        return (self.origin[0] + p[..., 0], self.origin[1] + p[..., 1] * SE - p[..., 2] * CE)


class Ctx:
    """What decals can use: the buffers of the ray-cast frame."""

    def __init__(self, scene, depth, idx, piece_map, pieces, rgb):
        self.scene = scene
        self.depth = depth
        self.idx = idx
        self.piece_map = piece_map
        self.pieces = pieces
        self.rgb = rgb
        self.overlay = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    def to_px(self, p):
        x, y = self.scene.screen(p)
        return x * SS, y * SS

    def visible_mask(self, piece, d0, tol=3.0):
        pid = self.pieces.get(piece, -99)
        return (self.piece_map == pid) & (np.abs(self.depth - d0) < tol)

    def paint(self, mask_img, colour, alpha, piece=None, depth=None, tol=3.0):
        """Composite an L-mode mask (S x S) in `colour`, optionally clipped to
        the visible surface of `piece` near depth `depth`."""
        m = np.asarray(mask_img, dtype=np.float32) / 255.0
        if piece is not None:
            if isinstance(piece, (list, tuple)):
                vis = np.zeros_like(m, dtype=bool)
                for pc in piece:
                    vis |= self.visible_mask(pc, depth, tol) if depth is not None else (self.piece_map == self.pieces.get(pc, -99))
            else:
                vis = self.visible_mask(piece, depth, tol) if depth is not None else (self.piece_map == self.pieces.get(piece, -99))
            m = m * vis
        a = (np.clip(m * alpha, 0, 1) * 255).astype(np.uint8)
        layer = Image.new("RGBA", (S, S), tuple(int(v) for v in colour) + (0,))
        layer.putalpha(Image.fromarray(a))
        self.overlay.alpha_composite(layer)

    def polygon(self, pts_world, colour, alpha, piece=None, depth=None, tol=3.0, soften=0.0):
        m = Image.new("L", (S, S), 0)
        xy = [self.to_px(p) for p in pts_world]
        ImageDraw.Draw(m).polygon([(float(x), float(y)) for x, y in xy], fill=255)
        if soften:
            m = Image.fromarray(np.clip(blur(np.asarray(m, np.float32), soften * SS), 0, 255).astype(np.uint8))
        self.paint(m, colour, alpha, piece, depth, tol)

    def polyline(self, pts_world, width, colour, alpha, piece=None, depth=None, tol=3.0, soften=0.0):
        m = Image.new("L", (S, S), 0)
        xy = [tuple(float(v) for v in self.to_px(p)) for p in pts_world]
        d = ImageDraw.Draw(m)
        w = max(1, int(round(width * SS)))
        d.line(xy, fill=255, width=w, joint="curve")
        for x, y in (xy[0], xy[-1]):
            d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=255)
        if soften:
            m = Image.fromarray(np.clip(blur(np.asarray(m, np.float32), soften * SS), 0, 255).astype(np.uint8))
        self.paint(m, colour, alpha, piece, depth, tol)


def surface_point(prim, u):
    """World point and normal on `prim` in local direction u."""
    u = unit(u)[None, :]
    return prim.world(u)[0], prim.normal(u)[0]


def tangent_ellipse(prim, u0, a, b, rot=0.0, steps=28, up=(0.0, 0.0, 1.0)):
    """Points of a small ellipse drawn on the surface of `prim` around local
    direction u0 (a, b in local unit-sphere units)."""
    u0 = unit(u0)
    upv = np.asarray(up, dtype=np.float64)
    t1 = np.cross(upv, u0)
    if np.linalg.norm(t1) < 1e-6:
        t1 = np.cross((0.0, 1.0, 0.0), u0)
    t1 = unit(t1)
    t2 = unit(np.cross(u0, t1))
    cr, sr = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    e1, e2 = t1 * cr + t2 * sr, -t1 * sr + t2 * cr
    pts = []
    for k in range(steps):
        th = 2 * math.pi * k / steps
        u = unit(u0 + e1 * a * math.cos(th) + e2 * b * math.sin(th))
        pts.append(prim.world(u[None, :])[0])
    return pts


def render(scene, path=None):
    st = scene.style
    prims = scene.prims
    gx, gy = scene.origin
    depth = np.full((S, S), -1e9, dtype=np.float64)
    idx = np.full((S, S), -1, dtype=np.int32)
    U = np.zeros((S, S, 3), dtype=np.float64)
    P = np.array([[1, 0, 0], [0, SE, -CE]], dtype=np.float64)
    for i, pr in enumerate(prims):
        A = pr.A
        M = P @ A
        ex, ey = np.linalg.norm(M[0]), np.linalg.norm(M[1])
        cx, cy = scene.screen(pr.c)
        x0 = max(int((cx - ex) * SS) - 1, 0)
        x1 = min(int((cx + ex) * SS) + 2, S)
        y0 = max(int((cy - ey) * SS) - 1, 0)
        y1 = min(int((cy + ey) * SS) + 2, S)
        if x0 >= x1 or y0 >= y1:
            continue
        ys, xs = np.mgrid[y0:y1, x0:x1]
        X = (xs + 0.5) / SS - gx
        Ys = (ys + 0.5) / SS - gy
        p0 = np.stack([X, Ys * SE, -Ys * CE], axis=-1)
        Ainv = np.linalg.inv(A)
        q0 = (p0 - pr.c) @ Ainv.T
        d = Ainv @ VIEW
        a = d @ d
        b = 2 * (q0 @ d)
        cc = np.einsum("...i,...i", q0, q0) - 1.0
        disc = b * b - 4 * a * cc
        hit = disc >= 0
        s = (-b + np.sqrt(np.maximum(disc, 0))) / (2 * a)
        sub = depth[y0:y1, x0:x1]
        win = hit & (s > sub)
        if not win.any():
            continue
        sub[win] = s[win]
        idx[y0:y1, x0:x1][win] = i
        U[y0:y1, x0:x1][win] = (q0 + s[..., None] * d)[win]

    mask = idx >= 0
    piece_names = []
    for pr in prims:
        if pr.piece not in piece_names:
            piece_names.append(pr.piece)
    pieces = {n: k for k, n in enumerate(piece_names)}
    prim_piece = np.array([pieces[p.piece] for p in prims] + [-1], dtype=np.int32)
    piece_map = prim_piece[idx]          # idx -1 -> last entry (-1)

    # Per-pixel base colour, normal, mottle.
    rgb = np.zeros((S, S, 3), dtype=np.float64)
    nrm = np.zeros((S, S, 3), dtype=np.float64)
    flat_idx = idx.ravel()
    order = np.argsort(flat_idx, kind="stable")
    sorted_idx = flat_idx[order]
    starts = np.searchsorted(sorted_idx, np.arange(len(prims) + 1))
    Uf = U.reshape(-1, 3)
    rgbf = rgb.reshape(-1, 3)
    nrmf = nrm.reshape(-1, 3)
    for i, pr in enumerate(prims):
        sel = order[starts[i]:starts[i + 1]] if i + 1 <= len(prims) else []
        if len(sel) == 0:
            continue
        u = Uf[sel]
        col = pr.base_colour(u)
        rng = np.random.default_rng(seed_of(pr.key + ":m"))
        k1, k2 = rng.normal(0, 1, 3) * 2.6, rng.normal(0, 1, 3) * 5.0
        ph = rng.uniform(0, 6.3, 2)
        mot = 0.5 * np.sin(u @ k1 + ph[0]) + 0.5 * np.sin(u @ k2 + ph[1])
        rgbf[sel] = col * (1.0 + 0.035 * mot)[:, None]
        nrmf[sel] = pr.normal(u)

    # Smooth normals within each piece (soft joins between a piece's parts).
    if st.smooth > 0:
        sm = np.zeros_like(nrm)
        for name, pid in pieces.items():
            pm = piece_map == pid
            if not pm.any():
                continue
            yy, xx = np.nonzero(pm)
            pad = int(st.smooth * SS * 3) + 2
            y0, y1 = max(yy.min() - pad, 0), min(yy.max() + pad + 1, S)
            x0, x1 = max(xx.min() - pad, 0), min(xx.max() + pad + 1, S)
            sub_m = pm[y0:y1, x0:x1].astype(np.float32)
            num = blur(nrm[y0:y1, x0:x1] * sub_m[..., None], st.smooth * SS)
            den = blur(sub_m, st.smooth * SS)
            res = num / np.maximum(den[..., None], 1e-6)
            sm[y0:y1, x0:x1][pm[y0:y1, x0:x1]] = res[pm[y0:y1, x0:x1]]
        nrm = sm / np.maximum(np.linalg.norm(sm, axis=-1, keepdims=True), 1e-9)

    lam = nrm @ LIGHT
    diff = np.clip((lam + st.wrap) / (1 + st.wrap), 0, 1)
    facing = np.clip(nrm @ VIEW, 0, 1)
    shade = st.ambient + st.diffuse * diff
    # Occlusion where one part sits in front of / against another.
    dmin = depth[mask].min() if mask.any() else 0
    dd = np.where(mask, depth, dmin - 10.0).astype(np.float32)
    occl = np.clip((blur(dd, 2.2 * SS) - dd) / 7.0, 0, 1)
    occl2 = np.clip((blur(dd, 6.0 * SS) - dd) / 16.0, 0, 1)
    shade = shade * (1 - st.ao * occl - st.ao * 0.6 * occl2)
    # Tone edge: a gentle darker rim where the surface turns away.
    shade = shade * (0.9 + 0.1 * np.clip(facing * 2.2, 0, 1))
    rng = np.random.default_rng(11)
    grain = rng.normal(0, 1, (S, S)) * 0.012
    col = rgb * (shade + grain)[..., None]
    # Cool the shadows slightly towards the line colour (gouache look).
    cool = np.clip(1.0 - diff, 0, 1)[..., None] * 0.10
    col = col * (1 - cool) + np.asarray(LINE, dtype=np.float64)[None, None, :] * 1.6 * cool
    col = np.clip(col, 0, 255)

    img = np.zeros((S, S, 4), dtype=np.uint8)
    img[..., :3] = col.astype(np.uint8)
    img[..., 3] = (mask * 255).astype(np.uint8)
    base = Image.fromarray(img, "RGBA")

    # Fur / feather strokes anchored to the parts.
    strokes = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hairs = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ds = ImageDraw.Draw(strokes)
    dh = ImageDraw.Draw(hairs)
    for i, pr in enumerate(prims):
        if pr.fur <= 0:
            continue
        rm = float(np.mean(pr.r))
        area = 4 * math.pi * (pr.r[0] * pr.r[1] + pr.r[1] * pr.r[2] + pr.r[0] * pr.r[2]) / 3
        n = int(area * st.stroke_density * pr.fur)
        if n < 1:
            continue
        rng = np.random.default_rng(seed_of(pr.key))
        u = rng.normal(0, 1, (n, 3))
        u /= np.linalg.norm(u, axis=1, keepdims=True)
        jit = rng.normal(0, 1, (n, 3)) * 0.25
        lens = rng.uniform(st.stroke_len[0], st.stroke_len[1], n)
        lit_roll = rng.uniform(0, 1, n)
        if callable(pr.flow):
            f = np.asarray(pr.flow(u), dtype=np.float64)
        else:
            f = np.broadcast_to(np.asarray(pr.flow, dtype=np.float64), (n, 3))
        f = f + jit
        t = f - np.sum(f * u, axis=1, keepdims=True) * u
        t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-9)
        # local step so that the world length is about `lens`
        step = lens[:, None] / max(rm, 1e-3)
        u_mid = u + t * step * 0.5
        u_end = u + t * step
        u_mid /= np.linalg.norm(u_mid, axis=1, keepdims=True)
        u_end /= np.linalg.norm(u_end, axis=1, keepdims=True)
        w0, wm, we = pr.world(u), pr.world(u_mid), pr.world(u_end)
        nw = pr.normal(u)
        fac = nw @ VIEW
        sx0, sy0 = scene.screen(w0)
        sxm, sym = scene.screen(wm)
        sxe, sye = scene.screen(we)
        px = np.clip((sx0 * SS).astype(int), 0, S - 1)
        py = np.clip((sy0 * SS).astype(int), 0, S - 1)
        dep = w0 @ VIEW
        my_piece = pieces[pr.piece]
        vis_piece = piece_map[py, px] == my_piece
        vis_depth = np.abs(depth[py, px] - dep) < 2.0
        width = max(1, int(round(st.stroke_width * SS)))
        # inner strokes
        inner = vis_piece & vis_depth & (fac > 0.12)
        for k in np.nonzero(inner)[0]:
            base_c = col[py[k], px[k]]
            lit = lit_roll[k] < 0.18 + 0.7 * diff[py[k], px[k]]
            if lit:
                c = np.clip(base_c * 1.13 + 10, 0, 255)
                a = st.stroke_alpha[0]
            else:
                c = base_c * 0.76
                a = st.stroke_alpha[1]
            cc = tuple(int(v) for v in c) + (int(255 * a),)
            ds.line([(sx0[k] * SS, sy0[k] * SS), (sxm[k] * SS, sym[k] * SS), (sxe[k] * SS, sye[k] * SS)], fill=cc, width=width)
        # hairs breaking the outline
        if pr.edge > 0 and st.edge_density > 0:
            m_edge = (fac > -0.05) & (fac < 0.35) & vis_piece & (np.abs(depth[py, px] - dep) < 4.0)
            keep = rng.uniform(0, 1, n) < st.edge_density * pr.edge / max(st.stroke_density, 1e-6) * 0.5
            sel = np.nonzero(m_edge & keep)[0]
            if len(sel):
                # outward in screen space
                nsx, nsy = nw[:, 0], nw[:, 1] * SE - nw[:, 2] * CE
                el = rng.uniform(st.edge_len[0], st.edge_len[1], n)
                tsx, tsy = sxe - sx0, sye - sy0
                tl = np.maximum(np.hypot(tsx, tsy), 1e-6)
                nl = np.maximum(np.hypot(nsx, nsy), 1e-6)
                dx = 0.55 * tsx / tl + 0.8 * nsx / nl
                dy = 0.55 * tsy / tl + 0.8 * nsy / nl
                dl = np.maximum(np.hypot(dx, dy), 1e-6)
                for k in sel:
                    base_c = col[py[k], px[k]]
                    c = tuple(int(v) for v in np.clip(base_c * (1.0 + 0.08 * (diff[py[k], px[k]] - 0.5)), 0, 255)) + (int(255 * st.edge_alpha),)
                    x0s, y0s = sx0[k] - nsx[k] / nl[k] * 0.8, sy0[k] - nsy[k] / nl[k] * 0.8
                    x1s, y1s = x0s + dx[k] / dl[k] * el[k], y0s + dy[k] / dl[k] * el[k]
                    dh.line([(x0s * SS, y0s * SS), (x1s * SS, y1s * SS)], fill=c, width=max(1, int(round(0.55 * SS))))

    # strokes stay inside the silhouette; hairs may leave it
    sa = np.asarray(strokes, dtype=np.float32)
    sa[..., 3] *= mask
    strokes = Image.fromarray(sa.astype(np.uint8), "RGBA")
    base.alpha_composite(strokes)

    ctx = Ctx(scene, depth, idx, piece_map, pieces, col)
    for decal in scene.decals:
        decal(ctx)
    base.alpha_composite(ctx.overlay)

    # Hairs go under the outline but over the body edge.
    comp = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    comp.alpha_composite(hairs)
    comp.alpha_composite(base)
    hair_front = np.asarray(hairs, dtype=np.float32).copy()
    hair_front[..., 3] *= 0.55 * mask      # some hairs also lie over the edge
    comp.alpha_composite(Image.fromarray(hair_front.astype(np.uint8), "RGBA"))

    # Lines: the outer silhouette and where a part overlaps another.
    m = mask.astype(np.float32)
    er = np.minimum.reduce([np.roll(m, s, a) for s in (-1, 1) for a in (0, 1)] + [m])
    outer = m - er
    inner = np.zeros_like(m)
    for s in (-1, 1):
        for ax in (0, 1):
            nb_piece = np.roll(piece_map, s, ax)
            nb_depth = np.roll(depth, s, ax)
            inner = np.maximum(inner, ((nb_piece != piece_map) & (nb_piece >= 0) & mask & (nb_depth < depth - 2.5)).astype(np.float32))
    pa = np.array([max(p.edge, 0.0) for p in prims] + [0.0])
    inner *= np.clip(pa[idx], 0, 1)
    line = np.maximum(outer * st.line_alpha, inner * st.inner_line_alpha)
    line = np.clip(blur(line, 0.35 * SS) * 1.6, 0, 1)
    la = Image.new("RGBA", (S, S), LINE + (0,))
    la.putalpha(Image.fromarray((line * 255).astype(np.uint8)))
    comp.alpha_composite(la)

    # Ground shadow.
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    if scene.shadow:
        sh_soft = Image.new("L", (S, S), 0)
        sh_hard = Image.new("L", (S, S), 0)
        for pr in prims:
            if pr.data.get("no_shadow"):
                continue
            A = pr.A
            ez = np.linalg.norm(A[2])
            ex, ey = np.linalg.norm(A[0]), np.linalg.norm(A[1])
            h = max(pr.c[2], 0.0)
            bottom = max(pr.c[2] - ez, 0.0)
            g = np.array([pr.c[0] + 0.35 * h, pr.c[1] + 0.2 * h, 0.0])
            sx, sy = scene.screen(g)
            rx, ry = ex * 1.05, ey * SE * 1.05
            if scene.shadow == "flight":
                v1, v2 = 255, 0
                rx, ry = rx * 1.3, ry * 1.3
            else:
                v1 = int(255 * math.exp(-bottom / 14.0))
                v2 = int(255 * math.exp(-bottom / 2.5))
            box = [(sx - rx) * SS, (sy - ry) * SS, (sx + rx) * SS, (sy + ry) * SS]
            if v1 > 4:
                _max_ellipse(sh_soft, box, v1)
            if v2 > 4:
                _max_ellipse(sh_hard, [(sx - rx * 0.85) * SS, (sy - ry * 0.7) * SS, (sx + rx * 0.85) * SS, (sy + ry * 0.7) * SS], v2)
        soft = blur(np.asarray(sh_soft, np.float32), 4.0 * SS) / 255.0
        hard = blur(np.asarray(sh_hard, np.float32), 1.4 * SS) / 255.0
        alpha = np.clip(soft * st.shadow_alpha + hard * st.contact_alpha, 0, 0.6)
        if scene.shadow == "flight":
            alpha = np.clip(blur(soft, 5.0 * SS) * 0.10, 0, 0.07)
        shl = Image.new("RGBA", (S, S), SHADOW + (0,))
        shl.putalpha(Image.fromarray((alpha * 255).astype(np.uint8)))
        out.alpha_composite(shl)
    out.alpha_composite(comp)
    final = out.convert("RGBa").resize((N, N), Image.LANCZOS).convert("RGBA")
    if path:
        final.save(path, optimize=True)
    return final


def _max_ellipse(img, box, value):
    tmp = Image.new("L", img.size, 0)
    ImageDraw.Draw(tmp).ellipse(box, fill=value)
    img.paste(Image.fromarray(np.maximum(np.asarray(img), np.asarray(tmp))))
