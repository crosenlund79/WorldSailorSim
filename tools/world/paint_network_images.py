"""Paints the Traveller Network's atmospheric images (I028 Tier 5): small,
soft scenes of harbours, cafés, sails, ice and sea, with people only as blurred
silhouettes, in the Real Horizon palette. Deterministic (seeded); writes
assets/network/net_NN.png (360 x 220) and a manifest of what each shows.

Usage: python3 tools/world/paint_network_images.py
"""
import json
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "network")
W, H = 360, 220
PALETTES = {
    "dawn": ((231, 196, 160), (196, 170, 160), (70, 98, 112), (40, 62, 74)),
    "day": ((178, 206, 214), (214, 226, 224), (62, 112, 128), (36, 70, 84)),
    "dusk": ((214, 140, 104), (126, 96, 118), (52, 66, 86), (26, 38, 52)),
    "night": ((30, 40, 62), (54, 66, 92), (20, 30, 44), (12, 18, 28)),
    "arctic": ((206, 222, 230), (232, 238, 240), (92, 132, 150), (52, 86, 102)),
    "tropic": ((150, 206, 214), (232, 222, 190), (40, 150, 160), (20, 96, 110)),
    "fog": ((190, 196, 196), (210, 212, 210), (126, 138, 140), (98, 108, 110)),
}


def gradient(draw, top, bottom, y0, y1):
    for y in range(y0, y1):
        f = (y - y0) / max(y1 - y0 - 1, 1)
        draw.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bottom[i] - top[i]) * f) for i in range(3)))


def sky_and_sea(img, pal, horizon):
    d = ImageDraw.Draw(img)
    gradient(d, pal[1], pal[0], 0, horizon)
    gradient(d, pal[2], pal[3], horizon, H)


def shimmer(img, rng, horizon, colour):
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(60):
        x = rng.randint(0, W)
        y = rng.randint(horizon + 4, H)
        d.line([(x, y), (x + rng.randint(6, 24), y)], fill=colour + (rng.randint(30, 90),), width=1)


def sun(img, x, y, r, colour):
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for k in range(6, 0, -1):
        gd.ellipse([x - r * k * 0.6, y - r * k * 0.6, x + r * k * 0.6, y + r * k * 0.6], fill=colour + (int(18 * (7 - k)),))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(6)))


def town(img, rng, horizon, colours, dark=False):
    d = ImageDraw.Draw(img, "RGBA")
    x = -10
    while x < W:
        w = rng.randint(16, 34)
        h = rng.randint(14, 34)
        c = rng.choice(colours)
        if dark:
            c = tuple(int(v * 0.35) for v in c)
        d.rectangle([x, horizon - h, x + w, horizon], fill=c + (255,))
        d.polygon([(x - 2, horizon - h), (x + w / 2, horizon - h - rng.randint(6, 14)), (x + w + 2, horizon - h)], fill=tuple(int(v * 0.6) for v in c) + (255,))
        if dark:
            for _ in range(rng.randint(0, 3)):
                wx = x + rng.randint(3, max(w - 5, 4))
                wy = horizon - rng.randint(4, max(h - 4, 5))
                d.rectangle([wx, wy, wx + 3, wy + 3], fill=(250, 214, 140, 230))
        x += w + rng.randint(0, 6)


def boat(img, x, y, s, colour, sail=True):
    d = ImageDraw.Draw(img, "RGBA")
    d.polygon([(x - 18 * s, y), (x + 20 * s, y), (x + 14 * s, y + 6 * s), (x - 12 * s, y + 6 * s)], fill=colour + (255,))
    if sail:
        d.line([(x, y), (x, y - 40 * s)], fill=colour + (255,), width=max(1, int(s)))
        d.polygon([(x + 1, y - 38 * s), (x + 1, y - 2 * s), (x + 22 * s, y - 4 * s)], fill=(240, 236, 226, 235))
        d.polygon([(x - 1, y - 34 * s), (x - 1, y - 4 * s), (x - 14 * s, y - 4 * s)], fill=(226, 222, 212, 215))


def people(img, rng, n, y, colour, blur=2.2):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x = rng.randint(40, 120)
    for _ in range(n):
        h = rng.randint(30, 44)
        d.ellipse([x - 5, y - h, x + 5, y - h + 10], fill=colour + (230,))
        d.rounded_rectangle([x - 8, y - h + 9, x + 8, y], radius=5, fill=colour + (230,))
        x += rng.randint(26, 60)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(blur)))


def cafe(img, rng, pal):
    d = ImageDraw.Draw(img, "RGBA")
    d.rectangle([0, 0, W, H], fill=pal[1] + (255,))
    d.rectangle([0, 140, W, H], fill=(120, 96, 78, 255))
    for i in range(3):
        cx = 60 + i * 120
        d.ellipse([cx - 34, 128, cx + 34, 146], fill=(236, 230, 214, 255))
        d.rectangle([cx - 3, 140, cx + 3, 190], fill=(70, 60, 52, 255))
        d.ellipse([cx - 8, 124, cx + 8, 132], fill=(250, 248, 240, 255))
    # a café front behind the tables: a warm wall, lit windows, a string of lights
    d.rectangle([0, 40, W, 122], fill=(168, 128, 98, 255))
    for i in range(4):
        x0 = 20 + i * 88
        d.rectangle([x0, 60, x0 + 56, 108], fill=(250, 214, 150, 255))
        d.line([x0 + 28, 60, x0 + 28, 108], fill=(120, 90, 70, 255), width=2)
    for x in range(0, W, 18):
        d.ellipse([x - 2, 48 + (x // 18) % 2 * 3, x + 2, 52 + (x // 18) % 2 * 3], fill=(255, 238, 180, 255))
    people(img, rng, 3, 150, (52, 48, 46), 3.0)


def ice(img, rng, horizon):
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(5):
        x = rng.randint(0, W)
        w = rng.randint(40, 110)
        h = rng.randint(16, 50)
        d.polygon([(x, horizon + 2), (x + w * 0.3, horizon - h), (x + w * 0.7, horizon - h * 0.7), (x + w, horizon + 2)], fill=(240, 246, 248, 245))
        d.polygon([(x + w * 0.3, horizon - h), (x + w * 0.45, horizon + 2), (x, horizon + 2)], fill=(196, 216, 226, 220))


def mountains(img, rng, horizon, colour):
    d = ImageDraw.Draw(img, "RGBA")
    pts = [(0, horizon)]
    x = 0
    while x < W:
        x += rng.randint(20, 60)
        pts.append((x, horizon - rng.randint(20, 70)))
    pts += [(W, horizon)]
    d.polygon(pts, fill=colour + (255,))


def whale(img, x, y):
    d = ImageDraw.Draw(img, "RGBA")
    d.polygon([(x - 14, y), (x - 4, y - 18), (x, y - 6), (x + 4, y - 18), (x + 14, y), (x, y + 4)], fill=(40, 52, 60, 255))


def aurora(img, rng):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for k in range(4):
        y = 30 + k * 12
        pts = [(x, y + 14 * math.sin(x / 40.0 + k)) for x in range(0, W + 10, 10)]
        d.line(pts, fill=(110, 230, 170, 120), width=10)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(8)))


def palms(img, rng, horizon):
    d = ImageDraw.Draw(img, "RGBA")
    for _ in range(3):
        x = rng.randint(10, W - 10)
        top = horizon - rng.randint(50, 80)
        d.line([(x, horizon + 6), (x + 8, top)], fill=(60, 52, 40, 255), width=4)
        for a in range(7):
            ang = a / 7 * math.pi * 2
            d.line([(x + 8, top), (x + 8 + 26 * math.cos(ang), top + 12 * math.sin(ang) + 6)], fill=(40, 90, 60, 255), width=3)


def lighthouse(img, x, horizon):
    d = ImageDraw.Draw(img, "RGBA")
    d.polygon([(x - 8, horizon), (x + 8, horizon), (x + 5, horizon - 60), (x - 5, horizon - 60)], fill=(236, 232, 224, 255))
    d.rectangle([x - 6, horizon - 40, x + 6, horizon - 32], fill=(170, 60, 50, 255))
    d.rectangle([x - 6, horizon - 68, x + 6, horizon - 60], fill=(250, 220, 140, 255))


SCENES = [
    ("harbour_dawn", "dawn", "harbour"), ("harbour_day", "day", "harbour"), ("harbour_dusk", "dusk", "harbour"), ("marina_night", "night", "harbour"),
    ("sail_dusk", "dusk", "sail"), ("sail_day", "day", "sail"), ("sail_tropic", "tropic", "sail"), ("cafe_morning", "dawn", "cafe"),
    ("cafe_evening", "dusk", "cafe"), ("ice_day", "arctic", "ice"), ("fjord", "arctic", "fjord"), ("whale", "day", "whale"),
    ("aurora", "night", "aurora"), ("tropic_anchorage", "tropic", "palms"), ("fog_harbour", "fog", "harbour"), ("lighthouse_dusk", "dusk", "lighthouse"),
    ("pontoon_people", "day", "pontoon"), ("crew_dawn", "dawn", "pontoon"), ("volcano_coast", "dusk", "fjord"), ("ice_dusk", "dusk", "ice"),
    ("two_sails", "day", "sails"), ("night_sail", "night", "sail"), ("whale_dawn", "dawn", "whale"), ("lighthouse_fog", "fog", "lighthouse"),
]


def paint(index, name, palette, motif):
    rng = random.Random(28000 + index)
    pal = PALETTES[palette]
    img = Image.new("RGBA", (W, H))
    horizon = rng.randint(96, 128)
    if motif == "cafe":
        cafe(img, rng, pal)
        return img
    sky_and_sea(img, pal, horizon)
    if palette in ("dawn", "dusk", "tropic", "day"):
        sun(img, rng.randint(60, W - 60), horizon - rng.randint(10, 50), 14, (255, 236, 196))
    if motif == "aurora":
        aurora(img, rng)
    if motif in ("harbour", "pontoon"):
        town(img, rng, horizon, [(196, 150, 110), (150, 70, 60), (220, 210, 190), (120, 140, 150)], dark=palette == "night")
    if motif in ("fjord",):
        mountains(img, rng, horizon, tuple(int(v * 0.55) for v in pal[2]))
    if motif == "ice":
        ice(img, rng, horizon)
    if motif == "palms":
        palms(img, rng, horizon)
    if motif == "lighthouse":
        lighthouse(img, rng.randint(240, 320), horizon + 4)
    shimmer(img, rng, horizon, tuple(min(v + 40, 255) for v in pal[0]))
    if motif in ("sail", "sails", "harbour", "fjord", "ice", "palms", "lighthouse", "whale"):
        for k in range(2 if motif == "sails" else 1):
            boat(img, rng.randint(80, 280), horizon + rng.randint(14, 40), rng.uniform(0.8, 1.3), tuple(int(v * 0.4) for v in pal[3]))
    if motif == "whale":
        whale(img, rng.randint(60, 300), horizon + rng.randint(30, 60))
    if motif == "pontoon":
        d = ImageDraw.Draw(img, "RGBA")
        d.rectangle([0, H - 50, W, H - 30], fill=(140, 120, 96, 255))
        people(img, rng, rng.randint(2, 4), H - 34, (44, 44, 48), 2.6)
    if palette == "fog":
        img.alpha_composite(Image.new("RGBA", img.size, (210, 214, 212, 90)))
    return img.filter(ImageFilter.GaussianBlur(0.6))


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = []
    for i, (name, palette, motif) in enumerate(SCENES):
        path = os.path.join(OUT, "net_%02d.png" % (i + 1))
        paint(i, name, palette, motif).convert("RGB").save(path, optimize=True)
        manifest.append({"id": "net_%02d" % (i + 1), "scene": name, "motif": motif, "palette": palette})
    json.dump({"note": "Traveller Network images (tools/world/paint_network_images.py); 'motif' lets posts pick a fitting picture.", "images": manifest},
              open(os.path.join(OUT, "manifest.json"), "w"), indent="\t")
    print(len(manifest), "images")


if __name__ == "__main__":
    main()
