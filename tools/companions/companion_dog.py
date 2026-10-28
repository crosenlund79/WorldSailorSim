"""The ship's dog: a fawn Pug (compact square body, short legs, round head
with a short flat muzzle and a dark mask, small folded dark ears, a tightly
curled tail over the hip). Proportions, colours, head, tail, face decals and
the keyed poses of every clip."""
import math

import numpy as np

from companion_render import (Prim, Style, chain, frame_from, mix, rot_y, rot_z, smoothstep, surface_point,
                              tangent_ellipse, unit, VIEW)
from companion_quadruped import Species
from companion_cat import blend, _add

FAWN = (194, 168, 132)
FAWN_LIGHT = (216, 198, 166)
FAWN_DARK = (156, 128, 96)
MASK = (54, 46, 42)
MASK_LIGHT = (84, 72, 64)
EYE = (52, 36, 28)
TONGUE = (196, 118, 116)


def _body(u, pr):
    top = smoothstep(0.55, 0.98, u[:, 2])
    trace = top * (1.0 - smoothstep(0.0, 0.3, np.abs(u[:, 1])))       # the darker trace along the spine
    under = smoothstep(-0.1, -0.8, u[:, 2])
    c = mix(FAWN, FAWN_DARK, top * 0.25 + trace * 0.35)
    return c + (np.asarray(FAWN_LIGHT) - c) * (under * 0.7)[:, None]


def _neck(u, pr):
    under = smoothstep(0.0, 0.8, u[:, 0] * 0.5 - u[:, 2] * 0.7)
    return mix(FAWN, FAWN_LIGHT, under * 0.7)


def _leg(u, pr):
    return np.broadcast_to(np.asarray(mix(FAWN, FAWN_LIGHT, 0.25 + 0.3 * pr.t)), (len(u), 3)).copy()


def _paw(u, pr):
    return np.broadcast_to(np.asarray(FAWN_LIGHT, dtype=np.float64), (len(u), 3)).copy()


def _cranium(u, pr):
    face = unit((1.0, 0.0, -0.15))
    d = np.linalg.norm(u - face[None, :], axis=1)
    mask = 1.0 - smoothstep(0.45, 0.85, d)
    # dark patches round the eyes join the mask
    for side in (-1, 1):
        e = unit((0.78, side * 0.5, 0.12))
        mask = np.maximum(mask, 1.0 - smoothstep(0.18, 0.42, np.linalg.norm(u - e[None, :], axis=1)))
    # the dark "thumbprint" on the forehead
    tp = unit((0.55, 0.0, 0.83))
    mask = np.maximum(mask, 0.55 * (1.0 - smoothstep(0.12, 0.3, np.linalg.norm(u - tp[None, :], axis=1))))
    return mix(FAWN, MASK, mask)


def _muzzle(u, pr):
    return mix(MASK, MASK_LIGHT, smoothstep(0.2, 0.9, u[:, 2]) * 0.4)


def _cheek(u, pr):
    front = smoothstep(0.2, 0.9, u[:, 0])
    return mix(FAWN, MASK, front * 0.85)


def _ear(u, pr):
    return np.broadcast_to(np.asarray(MASK, dtype=np.float64), (len(u), 3)).copy()


def _tail(u, pr):
    return mix(FAWN, FAWN_DARK, smoothstep(0.3, 0.95, u[:, 2]) * 0.35)


class Pug(Species):
    name = "dog"
    pelvis = (18, 16, 16)
    belly = (18, 18, 15.5)
    ribs = (22, 19, 18.5)
    shoulder = (8, 10, -4)
    hipjoint = (2, 10, -3)
    front = (14, 13, 6)
    hind = (15, 16, 9)
    front_r = (8.0, 5.0, 4.2)
    hind_r = (10.0, 5.6, 4.0)
    paw = (5.0, 4.2, 3.0)
    tail_root = (-0.8, 0.75)
    tail_r = (5.4, 3.8)
    tail_count = 12
    neck_r = 12.0
    head_r = (13.0, 14.5, 12.5)
    scale = 1.18

    style = Style(stroke_len=(1.3, 2.4), stroke_density=0.38, stroke_alpha=(0.30, 0.26), stroke_width=0.55,
                  edge_len=(0.8, 1.6), edge_density=0.10, edge_alpha=0.65, smooth=1.8)

    def colours(self):
        return {"body": _body, "neck": _neck, "leg": _leg, "paw": _paw}

    def extra_trunk(self, W, WR, spine, spine_tan, pose, col, out):
        return []

    def head(self, hc, Rh, pose, col, out):
        prims = []
        cr = Prim(hc, self.head_r, Rh, "head", _cranium, "dog.cranium", flow=_head_flow, fur=0.7, data={"part": "cranium"})
        prims.append(cr)
        out.anchor["cranium"] = cr
        mz = Prim(hc + Rh @ np.array([10.5, 0.0, -4.0]), (4.4, 8.0, 5.2), Rh, "head", _muzzle, "dog.muzzle",
                  flow=(-1, 0, 0), fur=0.3, data={"part": "muzzle"})
        prims.append(mz)
        out.anchor["muzzle"] = mz
        for side in (-1, 1):
            ch = Prim(hc + Rh @ np.array([5.0, side * 7.5, -5.5]), (6.0, 6.0, 5.5), Rh, "head", _cheek, "dog.cheek%d" % side,
                      flow=(-0.5, side * 0.6, -0.6), fur=0.5, data={"part": "cheek"})
            prims.append(ch)
        # small folded ("button") ears: up from the skull, then folded forward and down
        lift = pose.get("ears", 0.0)
        for side in (-1, 1):
            base = np.array([-1.0, side * 9.5, 8.5])
            fold = base + np.array([1.5, side * 3.5, 3.0 + lift * 0.15])
            tip = fold + rot_y(-lift) @ np.array([3.5, side * 1.5, -6.0])
            pts = [hc + Rh @ base, hc + Rh @ fold, hc + Rh @ tip]
            normal = Rh @ unit(np.array([0.5, side * 1.0, 0.4]))
            prims += chain(pts, lambda t: (5.8 - 1.5 * t, 1.6), "ear%d" % side, _ear, "dog.ear%d" % side, 6,
                           flat=lambda t, n=normal: n, flow=(1.0, 0, 0), fur=0.3, edge=1.0)
        return prims

    def tail(self, pts, col, pose):
        return chain(pts, lambda t: self.tail_r[0] * (1 - t) + self.tail_r[1] * t, "tail", _tail, "dog.tail",
                     self.tail_count, flow=(1.0, 0.0, 0.0), fur=0.8, edge=0.6)


def _head_flow(u):
    nose = np.array([1.0, 0.0, -0.2])
    return -(nose[None, :] - u) + np.array([0.0, 0.0, -0.1])


def face(built, pose):
    eyes = pose.get("eyes", 1.0)
    look = pose.get("look", (0.0, 0.0))
    tongue = pose.get("tongue", 0.0)

    def decal(ctx):
        cr = built.anchor["cranium"]
        mz = built.anchor["muzzle"]
        # forehead wrinkles
        for k, (z, w) in enumerate(((0.42, 0.34), (0.55, 0.28))):
            pts = [cr.world(unit(np.array([0.82 - z * 0.3, y, z]))[None])[0] for y in np.linspace(-w, w, 9)]
            mid = cr.world(unit(np.array([0.82 - z * 0.3, 0.0, z]))[None])[0]
            d0 = float(np.dot(mid, VIEW))
            ctx.polyline(pts, 0.6, MASK, 0.42, "head", d0, tol=6)
        for side in (-1, 1):
            u0 = unit((0.80, side * 0.50, 0.10))
            p, n = surface_point(cr, u0)
            if np.dot(n, VIEW) < 0.04:
                continue
            d0 = float(np.dot(p, VIEW))
            if eyes < 0.2:
                pts = tangent_ellipse(cr, u0, 0.17, 0.03, rot=-side * 8, steps=24)
                ctx.polyline(pts[:13], 0.8, (30, 24, 22), 0.85, "head", d0, tol=5)
                continue
            pts = tangent_ellipse(cr, u0, 0.17, 0.15 * eyes, rot=-side * 8)
            ctx.polygon(pts, EYE, 1.0, "head", d0, tol=5)
            lu = unit(u0 + np.array([0.0, look[0] * 0.05, look[1] * 0.04]))
            ctx.polygon(tangent_ellipse(cr, lu, 0.10, 0.10 * eyes), (20, 14, 12), 0.9, "head", d0, tol=5)
            ctx.polyline(pts + [pts[0]], 0.5, (24, 20, 18), 0.8, "head", d0, tol=5)
            hl = tangent_ellipse(cr, unit(u0 + np.array([0.02, -0.05, 0.06 * eyes])), 0.035, 0.035)
            ctx.polygon(hl, (240, 236, 230), 0.85, "head", d0, tol=5)
        # nose: a broad dark pad on the flat muzzle, with nostrils
        nu = unit((0.75, 0.0, 0.65))
        p, n = surface_point(mz, nu)
        d0 = float(np.dot(p, VIEW))
        ctx.polygon(tangent_ellipse(mz, nu, 0.30, 0.16), (28, 24, 24), 0.95, "head", d0, tol=6)
        ctx.polygon(tangent_ellipse(mz, unit(nu + np.array([0, 0, 0.1])), 0.12, 0.05), (110, 100, 96), 0.45, "head", d0, tol=6)
        for side in (-1, 1):
            ctx.polygon(tangent_ellipse(mz, unit(nu + np.array([0.0, side * 0.14, -0.04])), 0.05, 0.035), (8, 8, 8), 0.9, "head", d0, tol=6)
        # the wrinkle over the nose
        pts = [mz.world(unit(np.array([0.5, y, 0.86]))[None])[0] for y in np.linspace(-0.5, 0.5, 9)]
        ctx.polyline(pts, 0.7, (28, 24, 22), 0.55, "head", d0, tol=8)
        if tongue > 0.05:
            tp = mz.world(unit(np.array([0.9, 0.0, -0.45]))[None])[0]
            tip = tp + (mz.R @ np.array([0.5, 0.0, -1.0])) * 5.0 * tongue
            ctx.polyline([tp, tip], 3.0, TONGUE, 0.95)
            ctx.polyline([tp, tp + (tip - tp) * 0.8], 0.4, (150, 80, 80), 0.6)

    return decal


# --- Poses ------------------------------------------------------------------------------

def _legs(fl, fr, hl, hr):
    return {"fl": fl, "fr": fr, "hl": hl, "hr": hr}


def curl_tail(base_x=-38.0, z=51.0, phase=0.0, wag=0.0):
    """The tight curl over the hip: a 1.2-turn loop lying on the back."""
    pts = []
    cx, cy, cz = base_x + 7.5, 2.0 + wag, z + 8.0
    for k in range(1, 9):
        a = math.radians(200 - k * 50 + phase)
        r = 9.5 - k * 0.6
        pts.append((cx + r * math.cos(a), cy + 2.5 * math.sin(a * 0.5) + wag * k / 8, cz + r * math.sin(a) * 0.9))
    return pts


def stand():
    return {
        "hip": (-27, 41), "chest": (13, 42), "bend": 0.0, "arch": 1.0,
        "head": (42, 4, 58), "head_yaw": 50, "head_pitch": 14, "head_roll": 0,
        "legs": _legs({"p": (22, -9, 0), "a": -8}, {"p": (22, 9, 0), "a": -8},
                      {"p": (-34, -9, 0), "a": -24}, {"p": (-34, 9, 0), "a": -24}),
        "tail": curl_tail(),
        "eyes": 1.0, "ears": 0.0, "look": (0.0, 0.0), "breath": 0.0, "yaw": 0.0, "roll": 0.0, "pitch": 0.0,
        "lift": (0.0, 0.0, 0.0), "squash": 1.0, "tongue": 0.0,
    }


def resting():
    p = stand()
    p.update({
        "hip": (-24, 16), "chest": (11, 18), "squash": 0.95,
        "head": (40, 5, 34), "head_yaw": 46, "head_pitch": 6,
        "legs": _legs({"p": (40, -8, 0), "a": -86}, {"p": (42, 8, 0), "a": -86},
                      {"p": (-12, -14, 0), "a": -84}, {"p": (-10, 15, 0), "a": -84}),
        "tail": curl_tail(-34, 26),
        "eyes": 0.8,
    })
    return p


def sit():
    p = stand()
    p.update({
        "hip": (-16, 18), "chest": (6, 38), "arch": -1.0,
        "head": (20, 4, 62), "head_yaw": 48, "head_pitch": 8,
        "legs": _legs({"p": (14, -8, 0), "a": -4}, {"p": (14, 8, 0), "a": -4},
                      {"p": (2, -15, 0), "a": -82}, {"p": (3, 15, 0), "a": -82}),
        "tail": curl_tail(-34, 22, phase=-30),
    })
    return p


def sleeping():
    """On its side, legs towards the viewer, chin down; the snoring breath."""
    p = stand()
    p.update({
        "roll": 82.0, "lift": (0.0, -8.0, 15.0), "squash": 0.95,
        "hip": (-26, 0), "chest": (12, 0), "arch": 0.0, "bend": -3.0,
        "head": (41, 1, 2), "head_yaw": 4, "head_pitch": -48, "head_roll": 0,
        "legs": _legs({"p": (40, -5, -22), "a": -70, "fwd": (1, 0, 0.3)}, {"p": (44, 7, -18), "a": -60, "fwd": (1, 0, 0.4)},
                      {"p": (-46, -5, -20), "a": -40, "fwd": (1, 0, -0.3)}, {"p": (-48, 7, -16), "a": -30, "fwd": (1, 0, -0.4)}),
        "tail": curl_tail(-34, 0, phase=-80),
        "eyes": 0.0,
    })
    return p


TROT_STRIDE = 40.0


def trot_frames(base=None, frames=8, stride=TROT_STRIDE, duty=0.5, lift=(7.0, 7.0)):
    """A short-legged trot on a treadmill (diagonal pairs); a planted foot moves
    back exactly stride/frames px per frame."""
    from companion_cat import walk_frames
    base = base or stand()
    ex = stride / Pug.scale * duty
    offs = {"fl": 0.0, "hr": 0.0, "fr": 0.5, "hl": 0.5}
    out = []
    for f in range(frames):
        ph = f / frames
        p = blend(base, base, 0)
        legs = {}
        for key, off in offs.items():
            leg = dict(base["legs"][key])
            x0, y0, _ = leg["p"]
            phi = (ph + off) % 1.0
            front = key[0] == "f"
            if phi < duty:
                x = x0 + ex * (0.5 - phi / duty)
                z = 0.0
                a = leg["a"] - 10 * (phi / duty)
            else:
                s = (phi - duty) / (1 - duty)
                x = x0 - ex / 2 + ex * (s * s * (3 - 2 * s))
                z = (lift[0] if front else lift[1]) * math.sin(math.pi * s)
                a = (leg["a"] + 70 * math.sin(math.pi * s)) if front else (leg["a"] - 30 * math.sin(math.pi * s))
            leg["p"] = (x, y0, z)
            leg["a"] = a
            legs[key] = leg
        p["legs"] = legs
        bob = math.cos(4 * math.pi * ph)
        p["chest"] = _add(base["chest"], (0, 1.2 * bob))
        p["hip"] = _add(base["hip"], (0, 1.2 * bob))
        p["head"] = _add(base["head"], (0, 0, 1.0 * bob))
        p["roll"] = 3.0 * math.sin(2 * math.pi * ph)
        p["tail"] = curl_tail(phase=6 * math.sin(2 * math.pi * ph))
        out.append(p)
    return out


def clips():
    c = {}
    rs = []
    for f in range(8):
        ph = 2 * math.pi * f / 8
        p = resting()
        p["breath"] = 0.035 * math.sin(ph)
        p["head"] = _add(p["head"], (0, 0, 0.5 * math.sin(ph)))
        p["tail"] = curl_tail(-34, 26, phase=(10 if f in (2, 3) else 0))
        p["eyes"] = 0.8 if f != 6 else 0.3
        rs.append(p)
    c["resting"] = (rs, 5, True)

    walk_base = stand()
    walk_base["head_pitch"] = 8
    walk_base["head_yaw"] = 36
    c["walk"] = (trot_frames(walk_base), 10, True)

    tf = []
    for f, yaw in enumerate((32, 84, 90, 36)):
        p = stand()
        p["yaw"] = yaw
        p["head_yaw"] = 14 if f in (1, 2) else 24
        legs = p["legs"]
        if f in (0, 3):
            k = "fr" if f == 0 else "hl"
            legs[k] = dict(legs[k], p=_add(legs[k]["p"], (0, 0, 4)), a=legs[k]["a"] + 30)
        tf.append(p)
    c["turn"] = (tf, 10, False)

    sf = []
    for f in range(6):
        ph = 2 * math.pi * f / 6
        p = sit()
        p["breath"] = 0.03 * math.sin(ph)
        p["head_yaw"] = 48 + 5 * math.sin(ph)
        p["tongue"] = 0.5 + 0.2 * math.sin(2 * ph)
        sf.append(p)
    c["sit"] = (sf, 5, True)

    ld = []
    for f, t in enumerate((0.0, 0.38, 0.75, 1.0)):
        p = blend(stand(), resting(), t)
        if f == 1:
            p["hip"] = _add(p["hip"], (0, -4))
        ld.append(p)
    c["lie_down"] = (ld, 8, False)

    sl = []
    for f in range(6):
        ph = 2 * math.pi * f / 6
        p = sleeping()
        p["breath"] = 0.06 * math.sin(ph)
        p["head"] = _add(p["head"], (0.6 * math.sin(ph), 0, 0))
        p["legs"]["fr"] = dict(p["legs"]["fr"], p=_add(p["legs"]["fr"]["p"], (0, 0, 2.0 * (f == 4))))
        sl.append(p)
    c["sleeping"] = (sl, 3, True)

    wk = []
    for f, t in enumerate((0.0, 0.35, 0.75, 1.0)):
        a, b = sleeping(), resting()
        p = blend(a, b, t)
        p["roll"] = 82 * (1 - t)
        p["lift"] = (0.0, -8.0 * (1 - t), 15.0 * (1 - t))
        p["eyes"] = (0.0, 0.4, 0.85, 1.0)[f]
        wk.append(p)
    c["wake"] = (wk, 6, False)

    bow = stand()
    bow.update({"hip": (-26, 44), "chest": (16, 20), "arch": -4, "head": (44, 6, 30), "head_pitch": 14, "head_yaw": 38,
                "legs": _legs({"p": (46, -9, 0), "a": -84}, {"p": (48, 9, 0), "a": -84},
                              {"p": (-32, -9, 0), "a": -20}, {"p": (-32, 9, 0), "a": -20}),
                "tail": curl_tail(-38, 58, phase=20), "tongue": 0.6})
    st = [stand(), blend(stand(), bow, 0.55), bow, dict(bow, tail=curl_tail(-38, 58, phase=-20), eyes=0.5),
          blend(bow, stand(), 0.55), stand()]
    c["stretching"] = (st, 6, False)

    tw = []
    for f in range(6):
        ph = 2 * math.pi * f / 6
        p = stand()
        p["tail"] = curl_tail(phase=40 * math.sin(ph), wag=6.0 * math.sin(ph))
        p["hip"] = _add(p["hip"], (0, 0.6 * math.cos(2 * ph)))
        p["bend"] = 3.0 * math.sin(ph)
        p["tongue"] = 0.8
        p["head_yaw"] = 40
        p["head_pitch"] = 16
        tw.append(p)
    c["tail_wag"] = (tw, 12, True)

    al = []
    for f in range(6):
        ph = 2 * math.pi * f / 6
        p = resting()
        p["head"] = (42, 5, 40)
        p["head_yaw"] = 64
        p["head_pitch"] = 14
        p["head_roll"] = (-4, -16, -22, -22, -14, -4)[f]
        p["ears"] = 14 if f in (2, 3) else 4
        p["eyes"] = 1.0
        p["look"] = (0.6, 0.2)
        al.append(p)
    c["alert"] = (al, 6, True)

    pt = []
    for f in range(6):
        ph = 2 * math.pi * f / 6
        p = stand()
        p["bend"] = 7.0 * math.sin(ph)
        p["hip"] = _add(p["hip"], (0, 1.0 * math.cos(2 * ph)))
        p["head"] = (43, 5 + 2 * math.sin(ph + 1), 58)
        p["head_yaw"] = 52 + 6 * math.sin(ph)
        p["head_pitch"] = 22
        p["head_roll"] = 8 * math.sin(ph)
        p["eyes"] = 0.45
        p["ears"] = -8
        p["tongue"] = 1.0
        p["tail"] = curl_tail(phase=30 * math.sin(2 * ph), wag=4 * math.sin(2 * ph))
        legs = p["legs"]
        k = ("fl", "hr", "fr", "hl", "fl", "hr")[f]
        legs[k] = dict(legs[k], p=_add(legs[k]["p"], (0, 0, 3)))
        pt.append(p)
    c["pet"] = (pt, 8, True)

    se = []
    for f, yaw in enumerate((0, 80, 170, 260, 320, 360)):
        if f < 4:
            p = stand()
            legs = p["legs"]
            k = ("fr", "hl", "fl", "hr")[f]
            legs[k] = dict(legs[k], p=_add(legs[k]["p"], (0, 0, 5)), a=legs[k]["a"] + 30)
            p["yaw"] = yaw
        elif f == 4:
            p = blend(stand(), resting(), 0.55)
            p["yaw"] = -36
        else:
            p = resting()
        se.append(p)
    c["settle"] = (se, 6, False)
    return c
