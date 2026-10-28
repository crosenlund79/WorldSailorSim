"""The ship's parrot: a green-cheeked conure (a small parrot, not a macaw):
mostly green, grey-brown crown, a grey breast with pale scalloping, a maroon
belly patch, a long maroon-red tail, blue flight feathers, a pale eye ring and
a dark beak. Puppet, colours, face decals and the keyed poses of every clip.

Body frame: +X forward (the bird faces right), +Y the near side, +Z up; the
origin is the perch / feet point (canvas (128, 176)). In flight the bird's
centre is drawn at canvas (128, 128), i.e. FLIGHT_Z above the perch point.
"""
import math

import numpy as np

from companion_render import (CE, Prim, Style, VIEW, chain, frame_from, lerp, mix, rot_x, rot_y, rot_z, smoothstep,
                              surface_point, tangent_ellipse, unit)
from companion_cat import blend, _add

GREEN = (94, 132, 72)
GREEN_LIGHT = (130, 160, 94)
GREEN_DARK = (60, 92, 52)
CROWN = (106, 96, 84)
BREAST = (130, 122, 110)
FRINGE = (196, 188, 168)
SCALE_DARK = (88, 80, 72)
MAROON = (122, 46, 46)
TAIL = (120, 50, 44)
TAIL_DARK = (96, 38, 36)
BLUE = (66, 98, 146)
BLUE_DARK = (44, 66, 104)
EYE_RING = (226, 222, 210)
IRIS = (44, 32, 28)
BEAK = (62, 62, 66)
FEET = (128, 118, 112)

SCALE = 1.5               # puppet units -> canvas px (the puppet is modelled at a smaller scale)
FLIGHT_Z = 48.0 / CE / SCALE   # body-frame height of the bird's centre in flight (canvas (128, 128))

STYLE = Style(stroke_len=(1.2, 2.2), stroke_density=0.26, stroke_alpha=(0.24, 0.22), stroke_width=0.55,
              edge_len=(0.6, 1.2), edge_density=0.05, edge_alpha=0.5, smooth=1.2, line_alpha=0.36,
              inner_line_alpha=0.26)


def _scallop(u, rows=7.0, phase=0.0):
    v = u[:, 2] * rows + 0.45 * np.cos(u[:, 1] * 11.0) + phase
    f = v - np.floor(v)
    return smoothstep(0.62, 0.86, f) * (1 - smoothstep(0.9, 1.0, f))


def _body(u, pr):
    # local x along the body axis (towards the head), z towards the back
    back = smoothstep(-0.15, 0.35, u[:, 2])
    front = 1.0 - back
    breast = front * smoothstep(-0.25, 0.25, u[:, 0])
    belly = front * (1.0 - smoothstep(-0.2, 0.25, u[:, 0])) * (1.0 - smoothstep(-0.95, -0.75, u[:, 0]))
    c = mix(GREEN, GREEN_LIGHT, 0.0)
    c = c + (np.asarray(BREAST) - c) * breast[:, None]
    sc = _scallop(u[:, [0, 1, 0]] * np.array([1, 1, 1]), rows=9.0) * breast
    c = c + (np.asarray(FRINGE) - c) * (sc * 0.55)[:, None]
    c = c + (np.asarray(MAROON) - c) * (belly * 0.95)[:, None]
    return c


def _breast(u, pr):
    front = 1.0 - smoothstep(-0.25, 0.3, u[:, 2])
    grey = front * smoothstep(-0.15, 0.2, u[:, 0])
    maroon = front * (1.0 - smoothstep(-0.25, 0.05, u[:, 0]))
    c = np.broadcast_to(np.asarray(GREEN, dtype=np.float64), (len(u), 3)).copy()
    c = c + (np.asarray(BREAST) - c) * grey[:, None]
    sc = _scallop(u[:, [1, 2, 0]], rows=8.0) * grey
    c = c + (np.asarray(FRINGE) - c) * (sc * 0.5)[:, None]
    return c + (np.asarray(MAROON) - c) * (maroon * 0.95)[:, None]


def _head(u, pr):
    crown = smoothstep(0.05, 0.5, u[:, 2]) * (1.0 - smoothstep(0.55, 0.95, u[:, 0]))
    throat = smoothstep(-0.2, -0.75, u[:, 2]) * smoothstep(-0.2, 0.5, u[:, 0])
    c = mix(GREEN, GREEN_LIGHT, smoothstep(0.0, 0.8, np.abs(u[:, 1])) * 0.35)    # the green cheeks
    c = c + (np.asarray(CROWN) - c) * crown[:, None]
    c = c + (np.asarray(BREAST) - c) * throat[:, None]
    sc = _scallop(u, rows=8.0) * throat
    c = c + (np.asarray(FRINGE) - c) * (sc * 0.5)[:, None]
    return c


def _wing(u, pr):
    t = pr.t
    c = mix(GREEN, BLUE, smoothstep(0.45, 0.75, t))
    c = mix(c, BLUE_DARK, smoothstep(0.85, 1.0, t) * 0.5)
    edge = smoothstep(0.55, 0.95, np.abs(u[:, 1]))
    out = np.broadcast_to(c, (len(u), 3)).copy()
    return out * (1.0 - 0.18 * edge[:, None])


def _covert(u, pr):
    sc = _scallop(u[:, [0, 2, 1]], rows=5.0)
    c = np.broadcast_to(np.asarray(GREEN, dtype=np.float64), (len(u), 3)).copy()
    return c + (np.asarray(GREEN_DARK) - c) * (sc * 0.6)[:, None]


def _primary(u, pr):
    k = pr.data.get("k", 0)
    base = mix(BLUE, BLUE_DARK, 0.15 * k)
    tipdark = smoothstep(0.4, 0.95, u[:, 0]) * 0.35
    c = np.broadcast_to(np.asarray(base), (len(u), 3)).copy()
    return c + (np.asarray(BLUE_DARK) - c) * tipdark[:, None]


def _tail(u, pr):
    t = pr.t
    c = mix(GREEN_DARK, TAIL, smoothstep(0.0, 0.3, t))
    c = mix(c, TAIL_DARK, smoothstep(0.75, 1.0, t) * 0.6)
    return np.broadcast_to(c, (len(u), 3)).copy()


def _beak(u, pr):
    return mix(BEAK, (98, 98, 100), smoothstep(0.2, 0.9, u[:, 2]) * 0.4)


def _feet(u, pr):
    return np.broadcast_to(np.asarray(FEET, dtype=np.float64), (len(u), 3)).copy()


def _vent(u, pr):
    return np.broadcast_to(np.asarray(GREEN_DARK, dtype=np.float64), (len(u), 3)).copy()


def perched():
    return {
        "body": (-2.0, 19.0), "pitch": 64.0, "fluff": 1.0, "breath": 0.0,
        "head_off": (2.0, 0.0, 0.0), "head_yaw": 40.0, "head_pitch": 4.0, "head_roll": 0.0, "head_tuck": 0.0,
        "wing": 0.0, "beat": 0.0, "flex": 0.0, "wing_lift": 0.0,
        "tail_angle": -32.0, "tail_spread": 0.0, "tail_len": 1.0,
        "feet": 1.0, "legs": 0.0, "eyes": 1.0, "look": (0.0, 0.0),
        "yaw": 34.0, "roll": 0.0, "lift": (0.0, 0.0, 0.0), "beak_open": 0.0,
    }


class Built:
    def __init__(self):
        self.prims = []
        self.anchor = {}


def build(pose):
    out = Built()
    Rw = rot_z(pose.get("yaw", 0.0)) @ rot_x(pose.get("roll", 0.0))
    T = np.asarray(pose.get("lift", (0.0, 0.0, 0.0)), dtype=np.float64)

    def W(p):
        return T + Rw @ np.asarray(p, dtype=np.float64)

    def WR(M):
        return Rw @ M

    fl = pose.get("fluff", 1.0) * (1 + pose.get("breath", 0.0))
    bx, bz = pose["body"]
    C = np.array([bx, 0.0, bz])
    pitch = pose.get("pitch", 60.0)
    axis = np.array([math.cos(math.radians(pitch)), 0.0, math.sin(math.radians(pitch))])
    Rb = frame_from(axis, (0.0, 0.0, 1.0)) if abs(pitch) < 85 else frame_from(axis, (-1.0, 0.0, 0.0))
    back = Rb[:, 2]                           # towards the bird's back
    body = Prim(W(C), (15.5, 10.0 * fl, 10.5 * fl), WR(Rb), "body", _body, "parrot.body", flow=(-1.0, 0.0, 0.0),
                fur=1.0, edge=1.0)
    out.prims.append(body)
    out.anchor["body"] = body
    # the breast fullness and the vent
    out.prims.append(Prim(W(C + axis * 6.0 - back * 2.5), (11.0, 8.8 * fl, 8.6 * fl), WR(Rb), "body", _breast, "parrot.breast",
                          flow=(-1.0, 0.0, 0.0), fur=0.8))
    out.prims.append(Prim(W(C - axis * 12.0 + back * 0.5), (6.5, 5.5 * fl, 5.5 * fl), WR(Rb), "body", _vent, "parrot.vent",
                          flow=(-1.0, 0.0, 0.0), fur=0.5))

    # head on a short neck
    tuck = pose.get("head_tuck", 0.0)
    neck = C + axis * (15.0 - 7.0 * tuck) + back * (1.5 + 3.0 * tuck)
    hc = neck + axis * 4.0 + np.asarray(pose.get("head_off", (0.0, 0.0, 0.0)), dtype=np.float64)
    Rh_body = rot_z(pose.get("head_yaw", 0.0)) @ rot_y(-pose.get("head_pitch", 0.0)) @ rot_x(pose.get("head_roll", 0.0))
    Rh = WR(Rh_body)
    hr = 7.6 * (1 + 0.06 * (fl - 1))
    head = Prim(W(hc), (hr, hr * 0.95, hr * 0.98), Rh, "head", _head, "parrot.head", flow=_head_flow, fur=0.8)
    out.prims.append(head)
    out.anchor["head"] = head
    out.prims.append(Prim(W((hc + neck) / 2 - axis * 3), (7.0, 7.0 * fl, 7.0 * fl), WR(Rb), "body", _head,
                          "parrot.neck", flow=(-1.0, 0.0, 0.0), fur=0.6))
    # beak: a hooked upper mandible and a small lower one
    bo = pose.get("beak_open", 0.0)
    b0 = hc + Rh_body @ np.array([6.0, 0.0, -0.5])
    b1 = hc + Rh_body @ np.array([9.4, 0.0, -2.4])
    b2 = hc + Rh_body @ np.array([9.6, 0.0, -5.6])
    out.prims += chain([W(b0), W(b1), W(b2)], lambda t: 3.0 * (1 - t) + 0.7, "head", _beak, "parrot.beak", 7, fur=0.0, edge=1.0)
    l0 = hc + Rh_body @ np.array([5.6, 0.0, -3.5 - bo])
    l1 = hc + Rh_body @ np.array([7.8, 0.0, -5.0 - bo * 1.5])
    out.prims += chain([W(l0), W(l1)], lambda t: 2.2 * (1 - t) + 0.8, "head", _beak, "parrot.lower", 4, fur=0.0, edge=0.6)
    out.anchor["beak_tip"] = W(b2)

    # tail: overlapping long feathers from the vent
    ta = math.radians(pitch + 180 + pose.get("tail_angle", -32.0) + 32.0)
    tdir = np.array([math.cos(ta), 0.0, math.sin(ta)])
    tdir = unit(tdir)
    root = C - axis * 13.0 + back * 1.0
    L = 40.0 * pose.get("tail_len", 1.0)
    spread = pose.get("tail_spread", 0.0)
    for k, off in enumerate((-1.0, 1.0, 0.0)):
        side = np.array([0.0, 1.0, 0.0])
        d = unit(tdir + side * off * (0.06 + 0.25 * spread))
        nrm = unit(np.cross(d, side))
        if np.dot(nrm, back) < 0:
            nrm = -nrm
        mid = root + d * L * 0.5 + nrm * 0.8 * (1 if off else 0)
        tip = root + d * L
        out.prims += chain([W(root), W(mid), W(tip)], lambda t: (5.0 * (1 - t) + 2.0 + 1.2 * math.sin(math.pi * t), 1.2),
                           "tail", _tail, "parrot.tail%d" % k, 9, flat=lambda t, n=WR(np.eye(3)) @ nrm: n,
                           flow=(1.0, 0.0, 0.0), fur=0.6, edge=1.0)

    # wings
    wing = pose.get("wing", 0.0)
    for side in (1, -1):
        out.prims += _wing_prims(W, WR, C, axis, back, Rb, side, pose, wing, fl)

    # feet and legs
    feet = pose.get("feet", 1.0)
    if feet > 0:
        tuck_f = pose.get("legs", 0.0)
        for side in (1, -1):
            hip = C - axis * 3.0 - back * 7.5 + np.array([0.0, side * 3.5, 0.0])
            if pose.get("dangle"):
                foot = hip + np.array([2.5, side * 0.4, -9.0])
            elif tuck_f < 0.5:
                foot = np.array([2.0 + 6.0 * tuck_f, side * 3.8, 0.8])
            else:
                foot = C - axis * 6.0 - back * 9.0 + np.array([0, side * 3.0, 0])
            if pose.get("foot_raise") and side == 1:
                foot = np.asarray(pose["foot_raise"], dtype=np.float64)
            out.prims += chain([W(hip), W(foot)], lambda t: 1.8 - 0.4 * t, "feet%d" % side, _feet, "parrot.leg%d" % side, 4,
                               fur=0.0, edge=0.7)
            if tuck_f < 0.5:
                for k, d in enumerate(((1.0, 0.25), (1.0, -0.25), (-1.0, 0.3), (-1.0, -0.3))):
                    toe = foot + np.array([d[0] * 3.6, side * 0.4 + d[1] * 1.2, -0.3])
                    out.prims += chain([W(foot), W(toe)], lambda t: 1.15 - 0.4 * t, "feet%d" % side, _feet,
                                       "parrot.toe%d.%d" % (side, k), 3, fur=0.0, edge=0.5)
    for pr in out.prims:
        pr.c = pr.c * SCALE
        pr.r = pr.r * SCALE
    out.anchor["beak_tip"] = out.anchor["beak_tip"] * SCALE
    return out


def _head_flow(u):
    beak = np.array([1.0, 0.0, -0.1])
    return -(beak[None, :] - u)


def _wing_prims(W, WR, C, axis, back, Rb, side, pose, wing, fl):
    prims = []
    if wing < 0.5:
        # folded against the flank, primaries crossing over the tail base
        lift = pose.get("wing_lift", 0.0) if side == 1 else 0.0
        flank = Rb[:, 1] * side
        shoulder = C + axis * 9.0 + back * 5.5 + flank * 6.0 * fl
        elbow = C - axis * 3.0 + back * 6.0 + flank * (7.0 * fl + lift * 3)
        tip = C - axis * 23.0 + back * (6.0 + lift * 4) + flank * (4.0 + lift * 3)
        nrm = unit(flank * 1.0 + back * 0.35)
        prims += chain([W(shoulder), W(elbow), W(tip)], lambda t: (6.0 * (1 - t) + 2.6 + 2.0 * math.sin(math.pi * t), 2.2),
                       "wing%d" % side, _wing, "parrot.wing%d" % side, 10, flat=lambda t, n=WR(np.eye(3)) @ nrm: n,
                       flow=(-1.0, 0.0, 0.0), fur=0.8, edge=1.0)
        prims.append(Prim(W(lerp(shoulder, elbow, 0.45) + nrm * 1.2), (9.0, 6.0, 1.8), WR(frame_from(elbow - shoulder, nrm)),
                          "wing%d" % side, _covert, "parrot.covert%d" % side, flow=(-1.0, 0.0, 0.0), fur=0.7))
        return prims
    # spread: the near wing (side 1) towards +Y, beat angle about the body axis
    beat = math.radians(pose.get("beat", 0.0))
    flex = pose.get("flex", 0.0)
    span_dir = unit(np.array([0.0, side * math.cos(beat), math.sin(beat)]))
    chord = -unit(axis)
    shoulder = C + axis * 6.0 + back * 4.0 + np.array([0.0, side * 6.0, 0.0])
    span = 44.0 * (1.0 - 0.38 * flex)
    wrist = shoulder + span_dir * span * 0.45 + chord * (2.0 + 5.0 * flex)
    tipp = wrist + unit(span_dir * (1.0 - 0.5 * flex) + chord * (0.35 + 0.9 * flex)) * span * 0.55
    nrm = unit(np.cross(span_dir, chord))
    if nrm[2] < 0:
        nrm = -nrm
    # arm (coverts and secondaries)
    prims += chain([W(shoulder), W(wrist)], lambda t: (8.5 - 1.0 * t, 1.8), "wing%d" % side, _covert,
                   "parrot.arm%d" % side, 7, flat=lambda t, n=WR(np.eye(3)) @ nrm: n, flow=(-1.0, 0.0, 0.0), fur=0.7)
    for k in range(4):
        a = lerp(shoulder, wrist, 0.15 + 0.25 * k) + chord * 6.5
        b = a + chord * 7.0 + span_dir * 1.5
        prims += chain([W(a), W(b)], lambda t: (3.6 - 1.0 * t, 0.9), "wing%d" % side, _wing, "parrot.sec%d.%d" % (side, k), 4,
                       flat=lambda t, n=WR(np.eye(3)) @ nrm: n, flow=(1.0, 0.0, 0.0), fur=0.4)
        for pr in prims[-4:]:
            pr.t = 0.5
    # hand and the fanned blue primaries
    for k in range(6):
        f = k / 5.0
        d = unit(lerp(unit(tipp - wrist), chord, 0.08 + 0.5 * f * (1 - 0.5 * flex)))
        L = span * 0.55 * (1.0 - 0.32 * f)
        prims += chain([W(wrist), W(wrist + d * L * 0.5), W(wrist + d * L)], lambda t: (2.8 - 0.8 * t + 0.6 * math.sin(math.pi * t), 0.9),
                       "wing%d" % side, _primary, "parrot.prim%d.%d" % (side, k), 7, flat=lambda t, n=WR(np.eye(3)) @ nrm: n,
                       flow=(1.0, 0.0, 0.0), fur=0.4)
        for pr in prims[-7:]:
            pr.data["k"] = k
    prims += chain([W(wrist), W(lerp(wrist, tipp, 0.35))], lambda t: (6.5 - 2.5 * t, 1.6), "wing%d" % side, _covert,
                   "parrot.hand%d" % side, 4, flat=lambda t, n=WR(np.eye(3)) @ nrm: n, flow=(1.0, 0.0, 0.0), fur=0.5)
    return prims


def face(built, pose):
    eyes = pose.get("eyes", 1.0)
    look = pose.get("look", (0.0, 0.0))

    def decal(ctx):
        hd = built.anchor["head"]
        for side in (-1, 1):
            u0 = unit((0.38, side * 0.86, 0.22))
            p, n = surface_point(hd, u0)
            if np.dot(n, VIEW) < 0.02:
                continue
            d0 = float(np.dot(p, VIEW))
            ring = tangent_ellipse(hd, u0, 0.30, 0.30)
            ctx.polygon(ring, EYE_RING, 0.95, "head", d0, tol=4, soften=0.15)
            if eyes < 0.2:
                pts = tangent_ellipse(hd, u0, 0.2, 0.03, steps=24)
                ctx.polyline(pts[:13], 0.6, (70, 66, 60), 0.85, "head", d0, tol=4)
                continue
            lu = unit(u0 + np.array([look[0] * 0.06, 0.0, look[1] * 0.05]))
            iris = tangent_ellipse(hd, lu, 0.19, 0.19 * eyes)
            ctx.polygon(iris, IRIS, 1.0, "head", d0, tol=4)
            hl = tangent_ellipse(hd, unit(lu + np.array([0.05, 0.0, 0.08 * eyes])), 0.05, 0.05)
            ctx.polygon(hl, (240, 240, 236), 0.8, "head", d0, tol=4)
            if eyes < 0.95:   # the lid
                lid = tangent_ellipse(hd, unit(u0 + np.array([0, 0, 0.12 + 0.2 * (1 - eyes)])), 0.24, 0.12 + 0.12 * (1 - eyes))
                ctx.polygon(lid, (210, 204, 190), 0.9, "head", d0, tol=4)
        # the nostril / cere at the base of the beak
        cu = unit((0.86, 0.0, 0.45))
        p, n = surface_point(hd, cu)
        if np.dot(n, VIEW) > 0:
            ctx.polygon(tangent_ellipse(hd, cu, 0.16, 0.08), (150, 140, 128), 0.7, "head", float(np.dot(p, VIEW)), tol=4)

    return decal


# --- Clips --------------------------------------------------------------------------------

def flying(beat, flex):
    p = perched()
    p.update({"yaw": 6.0, "body": (0.0, FLIGHT_Z), "pitch": 6.0, "wing": 1.0, "beat": beat, "flex": flex, "legs": 1.0,
              "tail_angle": -2.0, "tail_spread": 0.15, "head_yaw": 18.0, "head_pitch": -6.0, "head_off": (3.0, 0.0, -2.0)})
    return p


FLY_BEATS = ((62, 0.25), (30, 0.0), (-14, 0.0), (-46, 0.05), (-20, 0.45), (28, 0.6))


def clips():
    c = {}
    rs = []
    for f in range(6):
        ph = 2 * math.pi * f / 6
        p = perched()
        p["roll"] = 2.5 * math.sin(ph)
        p["breath"] = 0.025 * math.sin(2 * ph)
        p["head_yaw"] = 40 + 3 * math.sin(ph)
        p["head_roll"] = 3 * math.sin(ph + 0.6)
        p["tail_angle"] = -32 + 1.5 * math.sin(ph)
        rs.append(p)
    c["resting"] = (rs, 4, True)

    c["blink"] = ([dict(perched(), eyes=e) for e in (0.45, 0.0, 0.9)], 10, False)

    ht = []
    for f, (yaw, pitch, roll) in enumerate(((50, 4, 0), (80, 8, -8), (108, 6, -14), (70, 2, -4), (6, 14, 10), (36, 4, 0))):
        ht.append(dict(perched(), head_yaw=yaw, head_pitch=pitch, head_roll=roll))
    c["head_turn"] = (ht, 6, False)

    hop = []
    for f, (dx, dz, crouch, wing) in enumerate(((0, 0, 1, 0), (2, 5, 0, 0.2), (5.5, 7.5, 0, 0.3), (8.5, 4, 0, 0.2), (10, 0, 1, 0),
                                                (10, 0, 0, 0))):
        p = perched()
        p["lift"] = (dx, 0.0, dz)
        p["body"] = (-2.0, 19.0 - 4.0 * crouch)
        p["pitch"] = 60 - 12 * (1 if dz > 0 else 0) - 6 * crouch
        p["wing_lift"] = wing * 3
        p["tail_angle"] = -32 + (10 if dz > 0 else 0)
        if dz > 0:
            p["legs"] = 0.3
        hop.append(p)
    c["hop"] = (hop, 10, False)

    crouch = dict(perched(), body=(-2.0, 15.0), pitch=46.0, wing=1.0, beat=66.0, flex=0.55, head_yaw=24, yaw=12.0)
    k1 = flying(76, 0.15)
    k1.update({"lift": (0.0, 0.0, -FLIGHT_Z + 20.0), "pitch": 34, "legs": 0.0, "dangle": 1, "tail_spread": 0.4})
    k2 = flying(-38, 0.0)
    k2.update({"lift": (0.0, 0.0, -18.0), "pitch": 18})
    to = [crouch, k1, k2, flying(30, 0.0)]
    c["takeoff"] = (to, 12, False)

    c["fly"] = ([flying(b, fx) for b, fx in FLY_BEATS], 12, True)

    a = flying(62, 0.25)
    a.update({"lift": (-6.0, 0.0, -10.0), "pitch": 24})
    b = flying(72, 0.05)
    b.update({"lift": (-2.0, 0.0, -FLIGHT_Z + 22.0), "pitch": 42, "legs": 0.0, "dangle": 1, "tail_spread": 0.8})
    cc = dict(perched(), body=(-2.0, 17.0), pitch=54.0, wing=1.0, beat=58.0, flex=0.6, tail_spread=0.5, yaw=12.0)
    ln = [a, b, cc, perched()]
    c["land"] = (ln, 12, False)

    ru = []
    for f, (fl, roll, wl) in enumerate(((1.15, 0, 0.5), (1.32, 6, 1.0), (1.36, -7, 1.0), (1.22, 4, 0.5), (1.08, -2, 0.2), (1.0, 0, 0))):
        p = perched()
        p["fluff"] = fl
        p["roll"] = roll
        p["wing_lift"] = wl
        p["head_roll"] = -roll * 2
        p["tail_spread"] = 0.6 * wl
        p["eyes"] = 0.6 if f in (1, 2) else 1.0
        ru.append(p)
    c["ruffle"] = (ru, 10, False)

    pr = []
    for f in range(8):
        ph = 2 * math.pi * f / 8
        p = perched()
        p["head_yaw"] = 150 + 8 * math.sin(ph)
        p["head_pitch"] = -34 - 6 * math.sin(2 * ph)
        p["head_off"] = (-5.0, 5.0, -2.0 - 1.5 * math.sin(ph))
        p["wing_lift"] = 0.6 + 0.3 * math.sin(ph)
        p["eyes"] = 0.7
        p["beak_open"] = 0.8 if f % 2 else 0.0
        pr.append(p)
    c["preen"] = (pr, 8, True)

    def sleep_pose(ph=0.0):
        p = perched()
        p.update({"fluff": 1.22, "head_tuck": 1.0, "head_yaw": 150, "head_pitch": -10, "head_off": (-6.0, 3.0, -2.0),
                  "eyes": 0.0, "breath": 0.03 * math.sin(ph), "body": (-2.0, 17.0), "pitch": 66.0, "tail_angle": -38})
        return p

    c["sleeping"] = ([sleep_pose(2 * math.pi * f / 4) for f in range(4)], 2, True)

    wk = []
    for f, t in enumerate((0.25, 0.6, 0.85, 1.0)):
        p = blend(sleep_pose(), perched(), t)
        p["eyes"] = (0.0, 0.4, 0.8, 1.0)[f]
        wk.append(p)
    c["wake"] = (wk, 6, False)

    al = []
    for f in range(6):
        ph = 2 * math.pi * f / 6
        p = perched()
        p["head_yaw"] = 74 + 8 * math.sin(ph)
        p["head_pitch"] = 6 + 6 * math.sin(2 * ph)
        p["head_roll"] = (0, -18, -10, 0, 14, 6)[f]
        p["head_off"] = (2.0 + 2.0 * math.sin(2 * ph), 0.0, 1.5 * math.cos(2 * ph))
        p["look"] = (0.0, 0.3)
        p["pitch"] = 64
        al.append(p)
    c["alert"] = (al, 8, True)
    return c
