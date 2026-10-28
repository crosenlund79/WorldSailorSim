"""The ship's cat: a seal-point Ragdoll (semi-long coat, colour-point, blue
eyes, full plumed tail). Proportions, colours, head and tail of the puppet,
the face decals, and the keyed poses of every clip."""
import math

import numpy as np

from companion_render import (Prim, Style, chain, frame_from, lerp, mix, rot_y, rot_z, smoothstep, surface_point,
                              tangent_ellipse, unit, VIEW)
from companion_quadruped import Species

CREAM = (226, 216, 196)
IVORY = (238, 233, 220)
FAWN = (196, 178, 150)
SEAL = (92, 72, 60)
SEAL_DARK = (66, 52, 46)
SEAL_LIGHT = (140, 116, 96)
EAR_INNER = (176, 150, 140)
EYE = (98, 146, 188)
EYE_DARK = (54, 84, 120)
PUPIL = (16, 20, 26)
NOSE = (82, 62, 58)


def _body(u, pr):
    top = smoothstep(0.15, 0.95, u[:, 2])
    under = smoothstep(-0.1, -0.85, u[:, 2])
    c = mix(CREAM, FAWN, top * 0.55)
    return c + (np.asarray(IVORY) - c) * (under * 0.6)[:, None]


def _neck(u, pr):
    front = smoothstep(-0.2, 0.7, u[:, 0] * 0.6 - u[:, 2] * 0.6)
    return mix(CREAM, IVORY, front)


def _leg(u, pr):
    t = pr.t
    if pr.data.get("front"):
        k = smoothstep(0.2, 0.75, t)
    else:
        k = smoothstep(0.35, 0.85, t)
    base = mix(CREAM, SEAL_LIGHT, 0.0)
    dark = mix(SEAL_LIGHT, SEAL, smoothstep(0.6, 1.0, t))
    c = mix(base, dark, k)
    return np.broadcast_to(c, (len(u), 3)).copy()


def _paw(u, pr):
    return np.broadcast_to(np.asarray(SEAL, dtype=np.float64), (len(u), 3)).copy()


def _tail(u, pr):
    k = smoothstep(0.0, 0.45, pr.t) * 0.85
    c = mix(SEAL_LIGHT, SEAL, k)
    side = smoothstep(-0.2, -0.9, u[:, 2]) * 0.35
    out = np.broadcast_to(c, (len(u), 3)).copy()
    return out + (np.asarray(SEAL_LIGHT) - out) * side[:, None]


def _cranium(u, pr):
    face = unit((1.0, 0.0, 0.05))
    d = np.linalg.norm(u - face[None, :], axis=1)
    mask = 1.0 - smoothstep(0.55, 1.15, d)
    # the paler forehead between the eyes (the Ragdoll's inverted V)
    fore = smoothstep(0.25, 0.75, u[:, 2]) * (1.0 - smoothstep(0.0, 0.35, np.abs(u[:, 1]))) * 0.55
    mask = np.clip(mask - fore, 0, 1)
    c = mix(CREAM, SEAL, mask * 0.92)
    return c


def _muzzle(u, pr):
    chin = smoothstep(0.0, -0.8, u[:, 2]) * 0.25
    return mix(SEAL, SEAL_LIGHT, chin)


def _cheek(u, pr):
    face = smoothstep(-0.3, 0.8, u[:, 0])
    return mix(CREAM, SEAL_LIGHT, face * 0.75)


def _ear(u, pr):
    return np.broadcast_to(np.asarray(mix(SEAL, SEAL_DARK, pr.t * 0.6)), (len(u), 3)).copy()


def _ruff(u, pr):
    return np.broadcast_to(np.asarray(IVORY, dtype=np.float64), (len(u), 3)).copy() * (0.98 + 0.02 * u[:, :1])


class Ragdoll(Species):
    name = "cat"
    pelvis = (22, 18, 19)
    belly = (22, 19.5, 19)
    ribs = (25, 20, 22)
    shoulder = (10, 10, -2)
    hipjoint = (2, 11, -1)
    front = (23, 22, 9)
    hind = (25, 27, 14)
    front_r = (9.5, 6.0, 4.8)
    hind_r = (12.0, 6.0, 4.4)
    paw = (6.2, 5.0, 3.6)
    tail_root = (-0.85, 0.6)
    tail_r = (7.0, 5.4)
    tail_count = 16
    neck_r = 11.5
    head_r = (14.5, 16.0, 13.5)
    scale = 1.08

    style = Style(stroke_len=(2.6, 5.2), stroke_density=0.42, stroke_alpha=(0.40, 0.32), stroke_width=0.6,
                  edge_len=(1.8, 3.6), edge_density=0.26, edge_alpha=0.8, smooth=1.8)

    def colours(self):
        return {"body": _body, "neck": _neck, "leg": _leg, "paw": _paw}

    def extra_trunk(self, W, WR, spine, spine_tan, pose, col, out):
        # The ivory ruff over the chest and the breeches on the thighs.
        Rr = frame_from(spine_tan(0.95), (0, 0, 1))
        p = spine(0.95) + Rr @ np.array([self.ribs[0] * 0.62, 0.0, -2.0])
        ruff = Prim(W(p), (11, 13.5, 14), WR(Rr), "body", _ruff, "cat.ruff", flow=(-0.3, 0.0, -1.0), data={"part": "ruff"})
        out.anchor["ruff"] = ruff
        return [ruff]

    def head(self, hc, Rh, pose, col, out):
        prims = []
        cr = Prim(hc, self.head_r, Rh, "head", _cranium, "cat.cranium", flow=_head_flow, fur=0.8, data={"part": "cranium"})
        prims.append(cr)
        out.anchor["cranium"] = cr
        mz = Prim(hc + Rh @ np.array([9.0, 0.0, -4.2]), (5.8, 6.4, 4.6), Rh, "head", _muzzle, "cat.muzzle",
                  flow=(-1, 0, 0), fur=0.4, data={"part": "muzzle"})
        prims.append(mz)
        out.anchor["muzzle"] = mz
        for side in (-1, 1):
            ch = Prim(hc + Rh @ np.array([1.0, side * 8.0, -4.5]), (7.5, 6.0, 6.5), Rh, "head", _cheek, "cat.cheek%d" % side,
                      flow=(-0.6, side * 0.7, -0.5), fur=0.9, data={"part": "cheek"})
            prims.append(ch)
        # Ears: flat tapering chains; + angle tips them forward.
        ang = pose.get("ears", 0.0)
        for side in (-1, 1):
            base = np.array([-2.0, side * 6.6, 8.5])
            tip = base + rot_y(-ang) @ np.array([0.0, side * 3.6, 10.0])
            mid = (base + tip) / 2 + np.array([0.6, side * 0.8, 0.0])
            pts = [hc + Rh @ base, hc + Rh @ mid, hc + Rh @ tip]
            normal = Rh @ unit(rot_y(-ang) @ np.array([1.0, side * 0.35, 0.2]))
            ear = chain(pts, lambda t: (8.6 * (1 - t ** 1.4) + 1.3, 2.6 * (1 - t) + 1.0), "ear%d" % side, _ear, "cat.ear%d" % side, 6,
                        flat=lambda t, n=normal: n, flow=(1.0, 0, 0), fur=0.6, edge=1.0)
            prims += ear
            out.anchor["ear%d" % side] = (pts, normal)
        return prims

    def tail(self, pts, col, pose):
        fluff = pose.get("tail_fluff", 1.0)
        return chain(pts, lambda t: (self.tail_r[0] * (1 - t) + self.tail_r[1] * t) * fluff * (1 - 0.25 * t * t * t), "tail",
                     _tail, "cat.tail", self.tail_count, flow=(1.0, 0.0, -0.25), fur=1.25, edge=1.2)


def _head_flow(u):
    # fur lies away from the nose
    nose = np.array([1.0, 0.0, -0.1])
    return -(nose[None, :] - u) + np.array([0.0, 0.0, -0.1])


# --- Face decals ------------------------------------------------------------------

def face(built, pose):
    eyes = pose.get("eyes", 1.0)
    look = pose.get("look", (0.0, 0.0))
    tongue = pose.get("tongue", 0.0)

    def decal(ctx):
        cr = built.anchor["cranium"]
        mz = built.anchor["muzzle"]
        # inner ears
        for side in (-1, 1):
            pts, normal = built.anchor["ear%d" % side]
            b, m, t = [np.asarray(p) for p in pts]
            if np.dot(normal, VIEW) < 0.05:
                continue
            across = unit(np.cross(normal, t - b))
            off = normal * 1.8
            tri = [b - across * 4.2 + off, m - across * 1.6 + off, t + (b - t) * 0.12 + off, m + across * 1.6 + off, b + across * 4.2 + off]
            d0 = float(np.dot(b + off, VIEW))
            ctx.polygon(tri, EAR_INNER, 0.85, "ear%d" % side, d0, tol=6.0, soften=0.6)
            # pale tufts
            ctx.polyline([b + off, (b + m) / 2 + off + across * 0.5], 0.5, IVORY, 0.6, "ear%d" % side, d0, tol=6.0)
            ctx.polyline([b + off - across * 1.5, (b + m) / 2 + off - across * 1.2], 0.5, IVORY, 0.5, "ear%d" % side, d0, tol=6.0)
        for side in (-1, 1):
            u0 = unit((0.80, side * 0.47, 0.20))
            p, n = surface_point(cr, u0)
            fac = float(np.dot(n, VIEW))
            if fac < 0.06:
                continue
            d0 = float(np.dot(p, VIEW))
            if eyes < 0.2:
                pts = tangent_ellipse(cr, u0, 0.19, 0.03, rot=-side * 14, steps=24)
                lower = pts[:13]
                ctx.polyline(lower, 0.8, SEAL_DARK, 0.85, "head", d0, tol=5)
                continue
            pts = tangent_ellipse(cr, u0, 0.19, 0.125 * eyes, rot=-side * 14, steps=28)
            ctx.polygon(pts, EYE, 1.0, "head", d0, tol=5)
            # darker upper iris under the lid
            up = tangent_ellipse(cr, u0 + np.array([0, 0, 0.06 * eyes]), 0.17, 0.07 * eyes, rot=-side * 14)
            ctx.polygon(up, EYE_DARK, 0.45, "head", d0, tol=5, soften=0.4)
            lu = unit(u0 + np.array([0.0, look[0] * 0.08, look[1] * 0.06]))
            pup = tangent_ellipse(cr, lu, 0.05 + 0.02 * (1 - eyes), 0.105 * eyes, rot=-side * 6)
            ctx.polygon(pup, PUPIL, 0.95, "head", d0, tol=5)
            ctx.polyline(pts + [pts[0]], 0.55, (34, 30, 30), 0.75, "head", d0, tol=5)
            hl = tangent_ellipse(cr, unit(u0 + np.array([0.02, -0.04, 0.06 * eyes])), 0.03, 0.03)
            ctx.polygon(hl, (246, 248, 250), 0.85, "head", d0, tol=5)
        # nose leather and mouth on the muzzle
        nu = unit((0.86, 0.0, 0.5))
        p, n = surface_point(mz, nu)
        if np.dot(n, VIEW) > -0.2:
            d0 = float(np.dot(p, VIEW))
            tri = tangent_ellipse(mz, nu, 0.22, 0.14, steps=3, rot=180)
            ctx.polygon(tri, NOSE, 0.95, "head", d0, tol=6, soften=0.3)
            ctx.polygon(tangent_ellipse(mz, unit(nu + np.array([0, -0.05, 0.08])), 0.05, 0.03), (150, 128, 122), 0.5, "head", d0, tol=6)
            m0 = mz.world(unit(np.array([0.95, 0.0, 0.05]))[None])[0]
            for side in (-1, 1):
                m1 = mz.world(unit(np.array([0.8, side * 0.4, -0.1]))[None])[0]
                ctx.polyline([p + (m0 - p) * 0.3, m0, m1], 0.45, SEAL_DARK, 0.7, "head", float(np.dot(m0, VIEW)), tol=8)
            if tongue > 0.05:
                tp = mz.world(unit(np.array([1.0, 0.0, -0.35]))[None])[0]
                tip = tp + (mz.R @ np.array([1.0, 0.0, -0.4])) * 3.5 * tongue
                ctx.polyline([tp, tip], 2.4 * tongue + 0.6, (196, 130, 128), 0.95)
        # whiskers: fine, pale, faint
        for side in (-1, 1):
            base = mz.world(unit(np.array([0.6, side * 0.75, 0.05]))[None])[0]
            bn = mz.normal(unit(np.array([0.6, side * 0.75, 0.05]))[None])[0]
            if np.dot(bn, VIEW) < -0.1:
                continue
            for k in range(3):
                dirv = mz.R @ unit(np.array([0.15, side * 1.0, 0.25 - k * 0.22]))
                ctx.polyline([base, base + dirv * 7 + mz.R @ np.array([0, 0, -1.2]), base + dirv * 13 + mz.R @ np.array([0, 0, -3.5])],
                             0.32, (236, 234, 228), 0.55)

    return decal


# --- Poses ------------------------------------------------------------------------------
# Body frame: +X forward, +Y near side (towards the viewer), +Z up; px.

def _legs(fl, fr, hl, hr):
    return {"fl": fl, "fr": fr, "hl": hl, "hr": hr}


def stand():
    return {
        "hip": (-40, 52), "chest": (21, 51), "bend": 0.0, "arch": 2.0,
        "head": (58, 4, 77), "head_yaw": 44, "head_pitch": 14, "head_roll": 0,
        "legs": _legs({"p": (30, -9, 0), "a": -10}, {"p": (30, 9, 0), "a": -10},
                      {"p": (-44, -9, 0), "a": -30}, {"p": (-44, 9, 0), "a": -30}),
        "tail": [(-70, 3, 58), (-86, 6, 60), (-100, 8, 68), (-108, 9, 82)],
        "eyes": 1.0, "ears": 0.0, "look": (0.0, 0.0), "breath": 0.0, "yaw": 0.0, "roll": 0.0, "pitch": 0.0,
        "lift": (0.0, 0.0, 0.0), "squash": 1.0, "tongue": 0.0, "tail_fluff": 1.0,
    }


def resting():
    """Lying like a sphinx: forelegs forward on the floor, hind legs folded,
    the plumed tail along the near side."""
    p = stand()
    p.update({
        "hip": (-30, 19), "chest": (18, 21), "arch": 1.0, "squash": 0.92,
        "head": (53, 5, 55), "head_yaw": 42, "head_pitch": 12,
        "legs": _legs({"p": (50, -9, 0), "a": -88}, {"p": (52, 9, 0), "a": -88},
                      {"p": (-14, -14, 0), "a": -86}, {"p": (-12, 15, 0), "a": -86}),
        "tail": [(-60, 10, 14), (-50, 26, 8), (-28, 34, 7), (-4, 36, 7)],
        "eyes": 0.75,
    })
    return p


def sit():
    p = stand()
    p.update({
        "hip": (-16, 21), "chest": (12, 50), "arch": -2.0,
        "head": (26, 4, 84), "head_yaw": 44, "head_pitch": 8,
        "legs": _legs({"p": (22, -8, 0), "a": -6}, {"p": (22, 8, 0), "a": -6},
                      {"p": (8, -15, 0), "a": -84}, {"p": (9, 15, 0), "a": -84}),
        "tail": [(-38, 10, 8), (-30, 26, 7), (-8, 32, 7), (14, 30, 7)],
    })
    return p


def sleeping():
    """Curled up: the back away from the viewer, nose tucked to the tail."""
    p = stand()
    p.update({
        "hip": (-26, 17), "chest": (22, 16), "bend": -34.0, "arch": 0.0, "squash": 0.86,
        "head": (44, 34, 16), "head_yaw": 128, "head_pitch": -8, "head_roll": -16,
        "legs": _legs({"p": (30, 10, 0), "a": -88, "fwd": (0.2, 1.0, 0.0)}, {"p": (32, 22, 0), "a": -88, "fwd": (0.0, 1.0, 0.0)},
                      {"p": (-10, 14, 0), "a": -86}, {"p": (-6, 20, 0), "a": -86}),
        "tail": [(-52, 20, 9), (-36, 34, 7), (-8, 40, 7), (16, 36, 7)],
        "eyes": 0.0, "ears": -6.0,
    })
    return p


def blend(a, b, t):
    if isinstance(a, dict):
        keys = set(a) | set(b)
        return {k: blend(a.get(k, b.get(k)), b.get(k, a.get(k)), t) for k in keys}
    if isinstance(a, (list, tuple)):
        if len(a) != len(b):
            return a if t < 0.5 else b
        return type(a)(blend(x, y, t) for x, y in zip(a, b)) if isinstance(a, tuple) else [blend(x, y, t) for x, y in zip(a, b)]
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a + (b - a) * t
    return a if t < 0.5 else b


def _add(v, d):
    return tuple(x + y for x, y in zip(v, d))


def _tail_sway(tail, amp_y, amp_z, phase):
    out = []
    n = len(tail)
    for i, pt in enumerate(tail):
        k = (i + 1) / n
        ph = phase - k * 0.9
        out.append((pt[0], pt[1] + amp_y * k * k * math.sin(ph), pt[2] + amp_z * k * k * math.cos(ph)))
    return out


WALK_STRIDE = 64.0   # px the body travels per full walk cycle (8 frames)


def walk_frames(base=None, frames=8, stride=WALK_STRIDE, duty=0.6, lift=(9.0, 10.0)):
    """A lateral-sequence walk on a treadmill: each foot in stance moves
    backwards exactly stride/frames px per frame, so when the game moves the
    companion stride px per cycle the planted feet stay still."""
    base = base or stand()
    ex = stride / Ragdoll.scale * duty
    offs = {"hl": 0.0, "fl": 0.25, "hr": 0.5, "fr": 0.75}
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
                a = leg["a"] + (-14 * (phi / duty) if front else -8 * (phi / duty))
            else:
                s = (phi - duty) / (1 - duty)
                x = x0 - ex / 2 + ex * (s * s * (3 - 2 * s))
                z = (lift[0] if front else lift[1]) * math.sin(math.pi * s)
                a = (leg["a"] + 80 * math.sin(math.pi * s ** 0.8)) if front else (leg["a"] - 35 * math.sin(math.pi * s))
            leg["p"] = (x, y0, z)
            leg["a"] = a
            legs[key] = leg
        p["legs"] = legs
        bob = math.cos(4 * math.pi * ph)
        p["chest"] = _add(base["chest"], (0, -1.0 * bob))
        p["hip"] = _add(base["hip"], (0, -1.0 * math.cos(4 * math.pi * ph + 1.2)))
        p["head"] = _add(base["head"], (0, 0, -0.8 * bob))
        p["bend"] = 2.5 * math.sin(2 * math.pi * ph)
        p["tail"] = _tail_sway(base["tail"], 5.0, 2.0, 2 * math.pi * ph)
        out.append(p)
    return out


def walk_base():
    p = stand()
    p["head_pitch"] = 4
    p["head_yaw"] = 32
    p["head"] = (60, 4, 74)
    p["tail"] = [(-68, 3, 72), (-80, 6, 86), (-90, 8, 98), (-92, 9, 110)]
    return p


def clips():
    """name -> (list of poses, fps, loop)."""
    c = {}
    # resting: breathing and a slow tail sway
    rs = []
    for f in range(8):
        ph = 2 * math.pi * f / 8
        p = resting()
        p["breath"] = 0.035 * math.sin(ph)
        p["head"] = _add(p["head"], (0, 0, 0.6 * math.sin(ph)))
        tail = p["tail"]
        p["tail"] = [(x, y + 3.5 * ((i + 1) / len(tail)) ** 2 * math.sin(ph * 1 - i * 0.5), z) for i, (x, y, z) in enumerate(tail)]
        p["eyes"] = 0.7 if f not in (5,) else 0.35
        rs.append(p)
    c["resting"] = (rs, 6, True)

    c["walk"] = (walk_frames(walk_base()), 10, True)

    # turn: from facing right to facing the viewer and back (frames 1-2 face the viewer)
    tf = []
    for f, yaw in enumerate((32, 84, 90, 36)):
        p = blend(stand(), walk_base(), 0.5)
        p["yaw"] = yaw
        p["head_yaw"] = 18 if f in (1, 2) else 26
        p["head_pitch"] = 14
        legs = p["legs"]
        if f in (0, 3):     # a step while turning
            k = "fr" if f == 0 else "hl"
            legs[k] = dict(legs[k], p=_add(legs[k]["p"], (0, 0, 5)), a=legs[k]["a"] + 30)
        p["tail"] = _tail_sway(p["tail"], 6.0, 0.0, f * 1.4)
        tf.append(p)
    c["turn"] = (tf, 10, False)

    # sit: upright, breathing, the tail tip curling
    sf = []
    for f in range(6):
        ph = 2 * math.pi * f / 6
        p = sit()
        p["breath"] = 0.03 * math.sin(ph)
        tail = p["tail"]
        p["tail"] = tail[:-1] + [_add(tail[-1], (2.0 * math.sin(ph), 3.0 * math.sin(ph), 2.5 * max(0, math.sin(ph))))]
        p["head_yaw"] = 44 + 4 * math.sin(ph)
        sf.append(p)
    c["sit"] = (sf, 5, True)

    # lie_down: standing -> resting
    ld = []
    for f, t in enumerate((0.0, 0.38, 0.75, 1.0)):
        p = blend(stand(), resting(), t)
        if f in (1, 2):   # crouch: the hindquarters go down first
            p["hip"] = _add(p["hip"], (0, -6 * (1 if f == 1 else 0.5)))
        ld.append(p)
    c["lie_down"] = (ld, 8, False)

    # sleeping: curled, slow breathing
    sl = []
    for f in range(6):
        ph = 2 * math.pi * f / 6
        p = sleeping()
        p["breath"] = 0.05 * math.sin(ph)
        p["head"] = _add(p["head"], (0, 0, 0.5 * math.sin(ph)))
        p["ears"] = -6 + (8 if f == 3 else 0)
        sl.append(p)
    c["sleeping"] = (sl, 3, True)

    # wake: lifts its head, opens its eyes
    wk = []
    awake = sleeping()
    awake.update({"head": (44, 30, 32), "head_yaw": 70, "head_pitch": 12, "head_roll": 0, "eyes": 1.0, "ears": 4.0})
    for f, t in enumerate((0.15, 0.5, 0.85, 1.0)):
        p = blend(sleeping(), awake, t)
        p["eyes"] = (0.0, 0.25, 0.7, 1.0)[f]
        wk.append(p)
    c["wake"] = (wk, 6, False)

    # stretching: the long forward stretch, then a hind leg, then standing
    bow = stand()
    bow.update({"hip": (-34, 58), "chest": (26, 26), "arch": -6, "head": (60, 6, 40), "head_pitch": 10, "head_yaw": 30,
                "legs": _legs({"p": (66, -9, 0), "a": -80}, {"p": (70, 9, 0), "a": -80},
                              {"p": (-38, -9, 0), "a": -26}, {"p": (-38, 9, 0), "a": -26}),
                "tail": [(-68, 3, 82), (-74, 5, 98), (-76, 7, 112), (-70, 8, 122)], "eyes": 0.1, "ears": -10})
    hind = stand()
    hind.update({"hip": (-26, 48), "chest": (30, 52), "head": (64, 4, 78), "head_pitch": 16,
                 "legs": _legs({"p": (36, -9, 0), "a": -10}, {"p": (36, 9, 0), "a": -10},
                               {"p": (-36, -9, 0), "a": -30}, {"p": (-70, 12, 8), "a": -70}),
                 "tail": [(-64, 3, 70), (-76, 5, 82), (-84, 7, 96), (-86, 8, 108)], "eyes": 0.4})
    st = [stand(), blend(stand(), bow, 0.55), bow, dict(bow, eyes=0.0, tongue=0.0), hind, blend(hind, stand(), 0.6)]
    st[2] = dict(st[2])
    st[3]["head"] = _add(bow["head"], (2, 0, 2))
    c["stretching"] = (st, 6, False)

    # groom: sitting, licking a forepaw, then washing the face with it
    gr = []
    for f in range(8):
        p = sit()
        p["legs"] = dict(p["legs"])
        if f < 4:
            ph = 2 * math.pi * f / 4
            p["legs"]["fr"] = {"p": (30, 18, 34 + 2.5 * math.sin(ph)), "a": 60, "fwd": (0.7, 0.4, 0.6)}
            p["head"] = (32, 13, 72 - 2.5 * math.sin(ph))
            p["head_pitch"] = -34
            p["head_yaw"] = 56
            p["head_roll"] = 8
            p["eyes"] = 0.3
            p["tongue"] = 0.9 if f % 2 == 0 else 0.35
        else:
            ang = math.pi * (f - 4) / 4
            p["legs"]["fr"] = {"p": (36 + 4 * math.cos(ang), 20, 44 + 16 * math.sin(ang)), "a": 70, "fwd": (0.6, 0.3, 0.8)}
            p["head"] = (30, 8, 80)
            p["head_pitch"] = -8 - 6 * math.sin(ang)
            p["head_roll"] = -16 * math.sin(ang)
            p["head_yaw"] = 48
            p["eyes"] = 0.0
            p["ears"] = -10
        gr.append(p)
    c["groom"] = (gr, 8, True)

    # alert: lying, head up, ears forward, looking at the viewer
    al = []
    for f in range(4):
        p = resting()
        p["head"] = (54, 6, 58)
        p["head_yaw"] = 62 + (4 if f in (1, 2) else 0)
        p["head_pitch"] = 18
        p["ears"] = 12 if f != 2 else 4
        p["eyes"] = 1.0
        p["look"] = (0.6, 0.2)
        p["tail"] = p["tail"][:-1] + [_add(p["tail"][-1], (0, 3.0 * (f % 2), 2.0 * (f % 2)))]
        al.append(p)
    c["alert"] = (al, 4, True)

    # pet: standing, leaning into the hand, slow blink, tail up
    pt = []
    for f in range(6):
        ph = 2 * math.pi * f / 6
        p = stand()
        p["chest"] = _add(p["chest"], (2 + 2 * math.sin(ph), 1))
        p["head"] = (60 + 2 * math.sin(ph), 6, 82 + 1.5 * math.sin(ph))
        p["head_yaw"] = 46
        p["head_pitch"] = 26
        p["head_roll"] = -14 + 9 * math.sin(ph)
        p["eyes"] = (0.8, 0.45, 0.08, 0.08, 0.45, 0.8)[f]
        p["ears"] = -4
        p["tail"] = [(-62, 2, 78), (-64, 4, 96), (-62, 5, 112), (-54 + 2 * math.sin(ph), 6, 120)]
        pt.append(p)
    c["pet"] = (pt, 6, True)

    # settle: a little circle on the spot, then lying down
    se = []
    for f, yaw in enumerate((0, 75, 160, 250, 320, 360)):
        if f < 4:
            p = blend(stand(), walk_base(), 0.5)
            p["head_yaw"] = 34
            legs = p["legs"]
            k = ("fr", "hl", "fl", "hr")[f]
            legs[k] = dict(legs[k], p=_add(legs[k]["p"], (0, 0, 6)), a=legs[k]["a"] + 34)
        elif f == 4:
            p = blend(stand(), resting(), 0.5)
            p["hip"] = _add(p["hip"], (0, -6))
        else:
            p = resting()
        p["yaw"] = yaw % 360 if f < 5 else 0
        if f == 4:
            p["yaw"] = -40
        se.append(p)
    c["settle"] = (se, 6, False)
    return c
