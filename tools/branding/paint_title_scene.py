"""Paints the title and loading screen illustration (Operation Real Horizon).

Usage: python3 tools/branding/paint_title_scene.py

An overcast morning at sea, seen from low over the water: a high grey-blue
sky with layered stratus, a pale break of light, a hazy headland with a
lighthouse far off to port, and a cruising sloop close-hauled on starboard
tack, heeled a little, a bone in her teeth. Natural, subdued colours; painted
in soft layers (gouache-like washes and dry-brush wave strokes), no outlines.

The sea and the sky are kept quiet in the middle of the picture, where the
menu sits. Writes assets/ui/title_scene.png (1920 x 1080) and a night
variant assets/ui/title_scene_night.png. Generated, provisional art: the
creator's own painting can replace either file (same name and size), or be
supplied through art_replacements/10_shared_props/ui_illustrations.

Requirements: Python 3 with Pillow and numpy.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
W, H = 1920, 1080
HORIZON = 640
RNG = np.random.default_rng(1852)  # the nautical mile


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def value_noise(w, h, cell_x, cell_y, rng):
    gx, gy = int(w / cell_x) + 3, int(h / cell_y) + 3
    grid = rng.random((gy, gx)).astype(np.float32)
    img = Image.fromarray((grid * 255).astype(np.uint8)).resize((int(gx * cell_x), int(gy * cell_y)), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32)[:h, :w] / 255.0


def fbm(w, h, cell_x, cell_y, rng, octaves=4):
    out = np.zeros((h, w), np.float32)
    amp, total = 1.0, 0.0
    for _ in range(octaves):
        out += value_noise(w, h, cell_x, cell_y, rng) * amp
        total += amp
        amp *= 0.5
        cell_x, cell_y = max(2, cell_x / 2), max(2, cell_y / 2)
    return out / total


def gradient(top, bottom, h, w):
    t = np.linspace(0, 1, h, dtype=np.float32)[:, None, None]
    a = np.array(top, np.float32)[None, None, :]
    b = np.array(bottom, np.float32)[None, None, :]
    return np.broadcast_to(a + (b - a) * t, (h, w, 3)).copy()


def paint(night=False):
    rgb = np.zeros((H, W, 3), np.float32)
    # --- Sky: high overcast, lighter and warmer towards the horizon.
    if night:
        sky_top, sky_low = (16, 24, 32), (44, 56, 66)
    else:
        sky_top, sky_low = (122, 140, 150), (203, 211, 208)
    rgb[:HORIZON] = gradient(sky_top, sky_low, HORIZON, W)
    # Layered stratus: long soft bands, darker undersides.
    clouds = fbm(W, HORIZON, 520, 60, RNG, 5)
    bands = np.clip((clouds - 0.42) * 2.6, 0, 1)
    shade = np.array((84, 98, 108) if not night else (10, 16, 22), np.float32)
    light = np.array((226, 230, 226) if not night else (58, 70, 80), np.float32)
    y = np.linspace(0, 1, HORIZON, dtype=np.float32)[:, None]
    rgb[:HORIZON] = rgb[:HORIZON] * (1 - bands[..., None] * 0.35) + shade * (bands[..., None] * 0.35) * (1 - y[..., None] * 0.6)
    lit = np.clip((fbm(W, HORIZON, 380, 40, RNG, 4) - 0.55) * 3.0, 0, 1) * (0.25 + y * 0.5)
    rgb[:HORIZON] = rgb[:HORIZON] * (1 - lit[..., None] * 0.4) + light * lit[..., None] * 0.4
    # A pale break in the overcast, high to starboard (or the moon's glow).
    yy, xx = np.mgrid[0:HORIZON, 0:W].astype(np.float32)
    glow = np.exp(-(((xx - 1460) / 520) ** 2 + ((yy - 250) / 190) ** 2))
    glow_c = np.array((236, 234, 224) if not night else (120, 132, 140), np.float32)
    rgb[:HORIZON] = rgb[:HORIZON] * (1 - glow[..., None] * 0.35) + glow_c * glow[..., None] * 0.35
    # --- Distant land: two ranges in haze, a headland to port with a lighthouse.
    far = (150, 162, 166) if not night else (34, 42, 50)
    near = (112, 126, 130) if not night else (24, 30, 38)
    land = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(land)
    pts = [(0, HORIZON)]
    for x in range(0, 860, 20):
        h_ = 42 * math.exp(-((x - 260) / 300) ** 2) + 18 * math.sin(x / 95.0) ** 2 + 8
        pts.append((x, HORIZON - h_))
    pts += [(860, HORIZON), (0, HORIZON)]
    d.polygon(pts, fill=255)
    m = np.asarray(land.filter(ImageFilter.GaussianBlur(1.2)), np.float32)[..., None] / 255
    rgb = rgb * (1 - m) + np.array(far, np.float32) * m
    land = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(land)
    pts = [(0, HORIZON)]
    for x in range(0, 520, 12):
        h_ = 64 * math.exp(-((x - 120) / 220) ** 2) + 6 * math.sin(x / 31.0) + 10
        pts.append((x, HORIZON - h_))
    pts += [(560, HORIZON - 4), (580, HORIZON), (0, HORIZON)]
    d.polygon(pts, fill=255)
    m = np.asarray(land.filter(ImageFilter.GaussianBlur(1.0)), np.float32)[..., None] / 255
    rgb = rgb * (1 - m) + np.array(near, np.float32) * m
    # Haze over the land at the horizon line.
    haze_band = np.exp(-((np.arange(H, dtype=np.float32) - HORIZON) / 26) ** 2)[:, None, None]
    haze_c = np.array((206, 213, 210) if not night else (52, 62, 70), np.float32)
    rgb = rgb * (1 - haze_band * 0.45) + haze_c * haze_band * 0.45
    # --- Sea: hazy at the horizon, deep slate in front.
    sea_far = (150, 168, 172) if not night else (36, 48, 58)
    sea_mid = (82, 112, 124) if not night else (20, 32, 42)
    sea_near = (40, 64, 76) if not night else (8, 14, 20)
    n = H - HORIZON
    t = np.linspace(0, 1, n, dtype=np.float32)
    t1 = np.clip(t / 0.35, 0, 1)[:, None]
    t2 = np.clip((t - 0.35) / 0.65, 0, 1)[:, None]
    sea = np.where(t[:, None] < 0.35,
                   np.array(sea_far, np.float32) + (np.array(sea_mid, np.float32) - sea_far) * t1,
                   np.array(sea_mid, np.float32) + (np.array(sea_near, np.float32) - sea_mid) * t2)
    rgb[HORIZON:] = np.broadcast_to(sea[:, None, :], (n, W, 3))
    # Sky reflected in the swell: soft lighter streaks, wider near the viewer.
    sheen = fbm(W, n, 600, 18, RNG, 4)
    rgb[HORIZON:] += ((sheen - 0.5) * 34)[..., None] * (0.4 + t[:, None, None] * 0.6)
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    # Dry-brush wave strokes: perspective (short and thin far off, longer near).
    strokes = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(strokes)
    rng = np.random.default_rng(7)
    for i in range(5200):
        tt = rng.random() ** 1.7
        yy_ = HORIZON + 2 + tt * (n - 4)
        length = 6 + tt * 90 * rng.uniform(0.5, 1.4)
        x = rng.uniform(-50, W + 50)
        thick = max(1, int(1 + tt * 3))
        crest = rng.random() < 0.45
        if crest:
            c = (214, 222, 222, int(40 + 70 * tt)) if not night else (90, 104, 116, int(30 + 40 * tt))
        else:
            c = (22, 40, 50, int(50 + 80 * tt)) if not night else (2, 6, 10, int(60 + 60 * tt))
        bow = rng.uniform(1.0, 3.5) * (0.3 + tt)
        pts = [(x + length * k / 6, yy_ - math.sin(math.pi * k / 6) * bow) for k in range(7)]
        sd.line(pts, fill=c, width=thick, joint="curve")
    img.alpha_composite(strokes.filter(ImageFilter.GaussianBlur(0.6)))
    # Lighthouse on the headland.
    ld = ImageDraw.Draw(img, "RGBA")
    lx, ly = 128, HORIZON - 70
    tower = (210, 214, 210) if not night else (70, 78, 84)
    ld.polygon([(lx - 3, ly + 2), (lx + 3, ly + 2), (lx + 2.2, ly - 16), (lx - 2.2, ly - 16)], fill=tower + (235,))
    ld.rectangle([lx - 3, ly - 20, lx + 3, ly - 16], fill=(70, 76, 80, 235))
    ld.polygon([(lx - 3.5, ly - 20), (lx + 3.5, ly - 20), (lx, ly - 24)], fill=(60, 64, 68, 235))
    ld.rectangle([lx - 2.6, ly - 8, lx + 2.6, ly - 5.5], fill=(140, 80, 72, 235))
    if night:
        beam = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        bd = ImageDraw.Draw(beam)
        bd.polygon([(lx, ly - 18), (760, ly - 60), (760, ly + 4)], fill=(230, 220, 180, 30))
        bd.ellipse([lx - 6, ly - 24, lx + 6, ly - 12], fill=(255, 240, 200, 220))
        img.alpha_composite(beam.filter(ImageFilter.GaussianBlur(6)))
    # --- The yacht.
    yacht(img, 1330, HORIZON + 150, 1.0, night)
    # A gentle vignette, darker below, so the menu reads.
    vy, vx = np.mgrid[0:H, 0:W].astype(np.float32)
    vign = np.clip(((vx - W / 2) / (W * 0.62)) ** 2 + ((vy - H * 0.45) / (H * 0.7)) ** 2, 0, 1) * 0.55
    vign += np.clip((vy - H * 0.7) / (H * 0.3), 0, 1) * 0.25
    arr = np.asarray(img, np.float32)
    arr[..., :3] *= (1 - vign[..., None] * (0.6 if not night else 0.8))
    # Fine paper grain.
    arr[..., :3] += (RNG.random((H, W, 1)).astype(np.float32) - 0.5) * 6
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA").convert("RGB")
    name = "title_scene_night.png" if night else "title_scene.png"
    path = os.path.join(ROOT, "assets", "ui", name)
    out.save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT), out.size)


def yacht(img, cx, wl, s, night):
    """A 36-foot sloop, side view, close-hauled on starboard tack (sails to
    port of the centreline, seen from her port side), heeled 7 degrees."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer, "RGBA")
    heel = math.radians(-7)

    def rot(p):
        x, y = p[0] - cx, p[1] - wl
        return (cx + x * math.cos(heel) - y * math.sin(heel), wl + x * math.sin(heel) + y * math.cos(heel))

    L = 260 * s
    bow, stern = cx + L * 0.5, cx - L * 0.5
    sheer = lambda x: wl - 26 * s + 6 * s * ((x - cx) / L * 2 - 0.3) ** 2  # noqa: E731
    white = (214, 216, 210) if not night else (64, 72, 78)
    shade = (164, 170, 168) if not night else (40, 48, 54)
    hull = [(stern, sheer(stern) + 2), (stern + 8 * s, wl + 4 * s)]
    hull += [(stern + 8 * s + (bow - stern - 30 * s) * k / 10, wl + 6 * s) for k in range(11)]
    hull += [(bow, sheer(bow) - 6 * s)]
    hull += [(x, sheer(x)) for x in np.linspace(bow, stern, 16)]
    d.polygon([rot(p) for p in hull], fill=white + (255,))
    # Shadowed lower topsides, a navy boot top and the waterline.
    low = [(stern + 4 * s, wl - 6 * s), (bow - 18 * s, wl - 6 * s), (bow - 26 * s, wl + 6 * s), (stern + 8 * s, wl + 6 * s)]
    d.polygon([rot(p) for p in low], fill=shade + (200,))
    boot = [(stern + 7 * s, wl), (bow - 28 * s, wl), (bow - 30 * s, wl + 4 * s), (stern + 9 * s, wl + 4 * s)]
    d.polygon([rot(p) for p in boot], fill=(46, 72, 92, 255) if not night else (20, 30, 40, 255))
    # Toe rail, coachroof and its windows, the sprayhood, stanchions.
    d.line([rot((x, sheer(x) - 1)) for x in np.linspace(stern, bow, 20)], fill=(120, 126, 126, 255), width=2)
    roof = [(cx - 50 * s, sheer(cx - 50 * s)), (cx - 46 * s, sheer(cx) - 12 * s), (cx + 40 * s, sheer(cx) - 10 * s),
            (cx + 56 * s, sheer(cx + 56 * s))]
    d.polygon([rot(p) for p in roof], fill=white + (255,))
    for k in range(3):
        x0 = cx - 34 * s + k * 26 * s
        d.polygon([rot((x0, sheer(cx) - 7 * s)), rot((x0 + 18 * s, sheer(cx) - 7 * s)), rot((x0 + 17 * s, sheer(cx) - 3.5 * s)),
                   rot((x0 + 1 * s, sheer(cx) - 3.5 * s))], fill=(40, 52, 60, 255))
    hood = [(cx - 72 * s, sheer(cx - 72 * s) - 2), (cx - 66 * s, sheer(cx) - 22 * s), (cx - 50 * s, sheer(cx) - 20 * s),
            (cx - 46 * s, sheer(cx - 46 * s) - 2)]
    d.polygon([rot(p) for p in hood], fill=(58, 72, 84, 255) if not night else (24, 30, 36, 255))
    for x in np.linspace(stern + 10 * s, bow - 26 * s, 7):
        d.line([rot((x, sheer(x) - 1)), rot((x, sheer(x) - 17 * s))], fill=(150, 158, 160, 230), width=1)
    d.line([rot((x, sheer(x) - 16 * s)) for x in np.linspace(stern + 10 * s, bow - 26 * s, 12)], fill=(170, 176, 178, 200), width=1)
    # Rig: mast, boom, forestay, backstay.
    mast_x = cx + 22 * s
    top = (mast_x, wl - 390 * s)
    d.line([rot((mast_x, sheer(mast_x) - 8)), rot(top)], fill=(150, 156, 158, 255), width=max(2, int(4 * s)))
    d.line([rot(top), rot((bow - 4 * s, sheer(bow) - 6 * s))], fill=(90, 98, 102, 220), width=1)
    d.line([rot(top), rot((stern + 2 * s, sheer(stern)))], fill=(90, 98, 102, 220), width=1)
    boom_y = sheer(mast_x) - 40 * s
    d.line([rot((mast_x, boom_y)), rot((stern + 30 * s, boom_y + 4 * s))], fill=(120, 128, 130, 255), width=max(2, int(4 * s)))
    sail = (232, 232, 226) if not night else (78, 86, 92)
    sail_shade = (196, 198, 192) if not night else (54, 62, 68)
    # Mainsail with a little roach, panel seams and battens.
    main = [(mast_x - 3 * s, boom_y - 2 * s)]
    for k in range(13):
        tt = k / 12
        x = mast_x - 3 * s - 2 * s * tt
        y = boom_y - 4 * s - (boom_y - top[1] - 14 * s) * tt
        main.append((x, y))
    head = main[-1]
    clew = (stern + 34 * s, boom_y - 4 * s)
    for k in range(1, 12):
        tt = k / 12
        x = head[0] + (clew[0] - head[0]) * tt
        y = head[1] + (clew[1] - head[1]) * tt
        bulge = math.sin(math.pi * tt) * 16 * s
        main.append((x - bulge * 0.92, y - bulge * 0.38))
    main.append(clew)
    d.polygon([rot(p) for p in main], fill=sail + (255,))
    for k in range(1, 9):
        tt = k / 9
        a = (mast_x - 3 * s, boom_y - 4 * s - (boom_y - top[1] - 14 * s) * tt)
        b_idx = 13 + int((1 - tt) * 10)
        b = main[min(len(main) - 1, b_idx)]
        d.line([rot(a), rot(b)], fill=sail_shade + (150,), width=1)
    # Leech shade.
    d.line([rot(p) for p in main[13:]], fill=sail_shade + (255,), width=max(2, int(3 * s)))
    # Genoa, overlapping the mast, its clew low by the shrouds.
    tack = (bow - 6 * s, sheer(bow) - 8 * s)
    ghead = (mast_x + (bow - mast_x) * 0.1, wl - 352 * s)
    gclew = (cx - 40 * s, sheer(cx - 40 * s) - 14 * s)
    genoa = [tack]
    for k in range(1, 12):
        tt = k / 12
        genoa.append((tack[0] + (ghead[0] - tack[0]) * tt, tack[1] + (ghead[1] - tack[1]) * tt))
    genoa.append(ghead)
    for k in range(1, 12):
        tt = k / 12
        x = ghead[0] + (gclew[0] - ghead[0]) * tt
        y = ghead[1] + (gclew[1] - ghead[1]) * tt
        b = math.sin(math.pi * tt) * 22 * s
        genoa.append((x - b * 0.95, y - b * 0.3))
    genoa.append(gclew)
    for k in range(1, 8):
        tt = k / 8
        x = gclew[0] + (tack[0] - gclew[0]) * tt
        y = gclew[1] + (tack[1] - gclew[1]) * tt
        genoa.append((x, y + math.sin(math.pi * tt) * 6 * s))
    d.polygon([rot(p) for p in genoa], fill=lerp(sail, (255, 255, 255), 0.05) + (255,))
    d.line([rot(p) for p in genoa[12:24]], fill=sail_shade + (255,), width=max(2, int(3 * s)))
    d.line([rot(p) for p in genoa[24:]], fill=sail_shade + (230,), width=1)
    # Sheets.
    d.line([rot(gclew), rot((cx - 70 * s, sheer(cx - 70 * s)))], fill=(70, 74, 76, 200), width=1)
    d.line([rot(clew), rot((stern + 26 * s, sheer(stern + 26 * s)))], fill=(70, 74, 76, 200), width=1)
    # The sails' curvature: shade deepening towards the leech (the light is
    # high to starboard, behind them), a little translucency at the foot.
    for poly, depth in ((main, 0.22), (genoa, 0.16)):
        m = Image.new("L", img.size, 0)
        ImageDraw.Draw(m).polygon([rot(p) for p in poly], fill=255)
        xs_ = [rot(p)[0] for p in poly]
        x0, x1 = min(xs_), max(xs_)
        ramp = np.clip((x1 - np.arange(img.size[0], dtype=np.float32)) / max(1.0, x1 - x0), 0, 1) ** 1.5
        a = (np.asarray(m, np.float32) * ramp[None, :] * depth).astype(np.uint8)
        shade_l = Image.new("RGBA", img.size, (92, 104, 112, 0))
        shade_l.putalpha(Image.fromarray(a))
        layer.alpha_composite(shade_l)
    img.alpha_composite(layer)
    # Bow wave and wake.
    foam = Image.new("RGBA", img.size, (0, 0, 0, 0))
    fd = ImageDraw.Draw(foam)
    fc = (230, 234, 232) if not night else (90, 100, 108)
    bx, by = rot((bow - 26 * s, wl + 4 * s))
    for k in range(18):
        r = k * 9 * s
        fd.arc([bx - 30 * s - r, by - 6 * s, bx + 10 * s, by + 10 * s + k * 0.6], 160, 200, fill=fc + (int(170 - k * 8),), width=2)
    sx, sy = rot((stern + 8 * s, wl + 4 * s))
    for k in range(40):
        x = sx - k * 14 * s
        fd.line([(x, sy + 2 + k * 0.4), (x - 22 * s, sy + 3 + k * 0.45)], fill=fc + (int(140 - k * 3.2),), width=2)
    img.alpha_composite(foam.filter(ImageFilter.GaussianBlur(1.2)))
    # Reflection: the hull's dark shadow on the water under her lee.
    refl = Image.new("RGBA", img.size, (0, 0, 0, 0))
    rd = ImageDraw.Draw(refl)
    rd.polygon([(stern, wl + 8 * s), (bow - 30 * s, wl + 8 * s), (bow - 40 * s, wl + 26 * s), (stern + 10 * s, wl + 30 * s)],
               fill=(14, 26, 32, 70))
    img.alpha_composite(refl.filter(ImageFilter.GaussianBlur(6)))


if __name__ == "__main__":
    paint(False)
    paint(True)
