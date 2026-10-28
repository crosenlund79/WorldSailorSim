"""The quadruped puppet shared by the cat (Ragdoll) and the dog (Pug).

A pose is a plain dict in the animal's own body frame (+X forward, +Y the
near side, towards the viewer, +Z up; units are canvas px, the ground point
at the origin). The puppet turns it into ellipsoids for companion_render.

Pose keys (all optional except the spine):
  hip, chest        (x, z) of the pelvis and ribcage centres
  bend              lateral bend of the spine (px; + bends towards +Y)
  arch              vertical arch of the spine (px)
  head              (x, y, z) head centre; head_yaw / head_pitch / head_roll (deg)
  neck              extra neck thickness factor
  legs              {"fl"|"fr"|"hl"|"hr": {"p": (x, y, z) paw ground point,
                     "a": metacarpal/metatarsal angle (deg, + leans the
                     joint above the paw forward), "flex": paw roll}}
  tail              control points after the tail root (body frame, absolute)
  squash            flattens the trunk (lying)
  eyes              0 closed .. 1 open; look (y, z) pupil shift
  ears              ear angle (deg, + forward, - flattened back)
  yaw, roll, pitch  the whole animal (deg), turning about the ground point
  lift              (x, y, z) translation of the whole animal (world)
  tongue            0..1 (licking / panting)
"""
import math

import numpy as np

from companion_render import (Prim, chain, frame_from, ik, lerp, rot_x, rot_y, rot_z, unit)

LEG_KEYS = ("fl", "fr", "hl", "hr")   # far = l (-Y), near = r (+Y)


class Species:
    """Proportions of one quadruped (all px)."""
    name = "quad"
    pelvis = (22, 17, 18)
    belly = (26, 18, 18)
    ribs = (27, 19, 21)
    shoulder = (8, 11, 4)       # offset of the shoulder joint in the ribcage frame (x, |y|, z)
    hipjoint = (0, 11, 2)
    front = (20, 20, 8)         # upper arm, forearm, metacarpus
    hind = (22, 24, 13)         # thigh, shank, metatarsus
    front_r = (10, 6, 5)        # radii: shoulder, elbow, wrist
    hind_r = (13, 7, 5)
    paw = (6, 5, 3.5)
    tail_root = (-0.9, 0.55)    # along pelvis x radius, up z radius
    tail_r = (6, 4)
    tail_count = 14
    neck_r = 10
    style = None

    def colours(self):
        raise NotImplementedError


def body_frame(pose):
    R = rot_z(pose.get("yaw", 0.0)) @ rot_x(pose.get("roll", 0.0)) @ rot_y(-pose.get("pitch", 0.0))
    T = np.asarray(pose.get("lift", (0.0, 0.0, 0.0)), dtype=np.float64)
    return R, T


class Built:
    """What the puppet produced: prims plus named anchors for the decals."""

    def __init__(self):
        self.prims = []
        self.anchor = {}


def build(sp, pose):
    R, T = body_frame(pose)

    def W(p):                      # body -> world
        return T + R @ np.asarray(p, dtype=np.float64)

    def WR(M):
        return R @ M

    out = Built()
    hx, hz = pose["hip"]
    cx, cz = pose["chest"]
    H = np.array([hx, 0.0, hz])
    C = np.array([cx, 0.0, cz])
    mid = (H + C) / 2 + np.array([0.0, pose.get("bend", 0.0), pose.get("arch", 0.0)])

    def spine(t):
        return (1 - t) ** 2 * H + 2 * (1 - t) * t * mid + t * t * C

    def spine_tan(t):
        return unit(2 * (1 - t) * (mid - H) + 2 * t * (C - mid))

    col = sp.colours()
    body_up = pose.get("body_up", (0.0, 0.0, 1.0))
    # Trunk: pelvis, belly, ribcage (one piece, smoothed together).
    trunk = []
    sq = pose.get("squash", 1.0)
    samples = (("pelvis", 0.06), ("t1", 0.2), ("t2", 0.35), ("belly", 0.5), ("t3", 0.65), ("t4", 0.8), ("ribs", 0.93))

    def trunk_r(t):
        if t <= 0.5:
            k = (t - 0.06) / 0.44
            a, b, na, nb = sp.pelvis, sp.belly, "pelvis", "belly"
        else:
            k = (t - 0.5) / 0.43
            a, b, na, nb = sp.belly, sp.ribs, "belly", "ribs"
        k = k * k * (3 - 2 * k)
        r = [a[i] + (b[i] - a[i]) * k for i in range(3)]
        sc = pose.get(na + "_scale", 1.0) + (pose.get(nb + "_scale", 1.0) - pose.get(na + "_scale", 1.0)) * k
        return r, sc

    for name, t in samples:
        rad, sc = trunk_r(t)
        breath = pose.get("breath", 0.0) * (0.4 + 0.6 * t)
        rx = rad[0] if name in ("pelvis", "ribs") else rad[0] * 0.62
        r = (rx, rad[1] * sc * (1 + breath) / math.sqrt(sq), rad[2] * sc * sq * (1 + breath * 0.7))
        Rl = frame_from(spine_tan(t), body_up)
        pr = Prim(W(spine(t)), r, WR(Rl), "body", col["body"], sp.name + "." + name, flow=(-1.0, 0.0, -0.35),
                  fur=1.0 if name in ("pelvis", "ribs", "belly") else 0.6, data={"part": name})
        trunk.append(pr)
        out.anchor[name] = pr
    out.prims += trunk
    ribs = out.anchor["ribs"]
    pelvis = out.anchor["pelvis"]
    Rrib = frame_from(spine_tan(0.93), body_up)
    Rpel = frame_from(spine_tan(0.06), body_up)

    # Head and neck.
    hc = np.asarray(pose["head"], dtype=np.float64)
    Rh_body = rot_z(pose.get("head_yaw", 0.0)) @ rot_y(-pose.get("head_pitch", 0.0)) @ rot_x(pose.get("head_roll", 0.0))
    Rh = WR(Rh_body)
    neck_base = spine(0.93) + Rrib @ np.array([sp.ribs[0] * 0.55, 0.0, sp.ribs[2] * 0.35])
    neck_top = hc - Rh_body @ np.array([sp.head_r[0] * 0.55, 0.0, sp.head_r[2] * 0.2])
    nk = []
    for k in range(4):
        t = k / 3
        p = lerp(neck_base, neck_top, t)
        r = sp.neck_r * pose.get("neck", 1.0) * (1.0 - 0.15 * t)
        Rl = frame_from(unit(neck_top - neck_base), body_up)
        nk.append(Prim(W(p), (r * 1.1, r, r * 1.05), WR(Rl), "body", col["neck"], sp.name + ".neck%d" % k,
                       flow=(-1.0, 0.0, -0.6), data={"part": "neck", "t": t}))
    out.prims += nk
    out.prims += sp.extra_trunk(W, WR, spine, spine_tan, pose, col, out)

    head_prims = sp.head(W(hc), Rh, pose, col, out)
    out.prims += head_prims

    # Legs.
    legs = pose.get("legs", {})
    for key in LEG_KEYS:
        leg = legs.get(key)
        if leg is None:
            continue
        side = 1.0 if key[1] == "r" else -1.0
        front = key[0] == "f"
        if front:
            jo = np.array([sp.shoulder[0], side * sp.shoulder[1], sp.shoulder[2]])
            J0 = spine(0.93) + Rrib @ jo
            L1, L2, L3 = sp.front
            r1, r2, r3 = sp.front_r
        else:
            jo = np.array([sp.hipjoint[0], side * sp.hipjoint[1], sp.hipjoint[2]])
            J0 = spine(0.06) + Rpel @ jo
            L1, L2, L3 = sp.hind
            r1, r2, r3 = sp.hind_r
        paw = np.asarray(leg["p"], dtype=np.float64)
        a = math.radians(leg.get("a", -15.0 if front else -30.0))
        fwd = unit(leg.get("fwd", (1.0, 0.0, 0.0)))
        up = np.array([0.0, 0.0, 1.0])
        if "up" in leg:
            up = unit(leg["up"])
        paw_c = paw + up * sp.paw[2]
        low = paw_c + (up * math.cos(a) + fwd * math.sin(a)) * L3
        if front:
            hint = -fwd * 1.0 + up * 0.05
        else:
            hint = fwd * 1.0 + up * 0.05
        hint = leg.get("hint", hint)
        J1 = ik(L1, L2, J0, low, hint)
        name = "leg_" + key
        segs = [(J0, J1, r1, r2, 5), (J1, low, r2, r3, 5), (low, paw_c, r3, sp.paw[1] * 0.9, 3)]
        n = 0
        for seg_i, (p0, p1, ra, rb, cnt) in enumerate(segs):
            for k in range(cnt):
                t = k / max(cnt - 1, 1)
                if n and k == 0:
                    continue
                p = lerp(p0, p1, t)
                r = ra + (rb - ra) * t
                Rl = frame_from(unit(np.asarray(p1) - np.asarray(p0)), (0.0, 0.0, 1.0) if abs(unit(p1 - p0)[2]) < 0.95 else (1.0, 0.0, 0.0))
                seg_t = (n + 0.0) / 11.0
                piece = "body" if (seg_i == 0 and t < 0.75) else name
                out.prims.append(Prim(W(p), (r * 1.05, r, r), WR(Rl), piece, col["leg"], "%s.%s.%d" % (sp.name, key, n),
                                      flow=(1.0, 0.0, 0.0), t=seg_t, data={"part": "leg", "front": front}))
                n += 1
        Rp = frame_from(fwd, up)
        pw = Prim(W(paw_c + fwd * sp.paw[0] * 0.25), sp.paw, WR(Rp), name, col["paw"], "%s.%s.paw" % (sp.name, key),
                  flow=(1.0, 0.0, -0.2), t=1.0, data={"part": "paw"})
        out.prims.append(pw)
        out.anchor["paw_" + key] = pw
        out.anchor["joint_" + key] = W(J1)

    # Tail.
    tail = pose.get("tail")
    if tail:
        root = spine(0.06) + Rpel @ np.array([sp.pelvis[0] * sp.tail_root[0], 0.0, sp.pelvis[2] * sp.tail_root[1]])
        pts = [W(root)] + [W(np.asarray(p, dtype=np.float64)) for p in tail]
        out.prims += sp.tail(pts, col, pose)
    sc = getattr(sp, "scale", 1.0)
    if sc != 1.0:
        for pr in out.prims:
            pr.c = pr.c * sc
            pr.r = pr.r * sc
        for k, v in list(out.anchor.items()):
            if isinstance(v, tuple):          # (points, normal) of an ear
                out.anchor[k] = ([np.asarray(q) * sc for q in v[0]], v[1])
            elif isinstance(v, np.ndarray):
                out.anchor[k] = v * sc
    return out
