"""Paints Copenhagen's landmark illustration for the harbour (Real Horizon).

Usage: python3 tools/harbours/paint_copenhagen_landmark.py

Nyhavn seen from above, as the rest of the harbour is: the cobbled quay along
the water, then the row of 17th- and 18th-century gabled town houses - their
water-facing facades just visible below the eaves in the real, weathered
Nyhavn colours (ochre, oxblood, faded blue, cream, terracotta), their roofs of
red clay tile and dark slate with dormers and chimneys, light from the upper
left. Painted in soft layers with fine texture, no ink outlines. A generated
stand-in for the owner's own art (same file, size and placement as before).

Writes assets/harbours/copenhagen/nyhavn.png (2 px per scene unit, 1150 x 110
units, transparent background). data/harbours/copenhagen.tres places it.
Requires Pillow and numpy.
"""
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "harbours", "copenhagen", "nyhavn.png")
SS, FINAL = 4, 2
W_UNITS, H_UNITS = 1150, 110
QUAY = 26          # the cobbled quay in front of the houses (units)
LIP = 10           # the facade seen below the eaves
FACADES = [(184, 146, 82), (128, 62, 52), (102, 124, 138), (214, 206, 182), (176, 104, 70), (150, 156, 120),
           (196, 170, 96), (118, 58, 56), (84, 104, 120), (206, 192, 160), (164, 120, 84)]
TILE = [(126, 82, 68), (116, 76, 64), (134, 90, 74)]
SLATE = [(66, 72, 78), (58, 63, 68)]

random.seed(1673)  # the year Nyhavn was dug
img = Image.new("RGBA", (W_UNITS * SS, H_UNITS * SS), (0, 0, 0, 0))
d = ImageDraw.Draw(img, "RGBA")


def P(x, y):
    return (x * SS, y * SS)


def rect(x, y, w, h, fill):
    d.rectangle([P(x, y), P(x + w, y + h)], fill=fill if len(fill) == 4 else fill + (255,))


def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


# The cobbled quay: granite setts in rows, a kerb along the houses.
rect(0, 0, W_UNITS, QUAY, (132, 134, 128))
for row in range(int(QUAY / 4)):
    y = row * 4
    x = -random.uniform(0, 4)
    while x < W_UNITS:
        w = random.uniform(3.2, 4.6)
        rect(x, y + 0.4, w - 0.6, 3.2, shade((132, 134, 128), random.uniform(0.86, 1.06)))
        x += w
rect(0, QUAY - 2, W_UNITS, 2, (112, 114, 110))

x = 4.0
i = 0
while x < W_UNITS - 50:
    w = random.uniform(54, 82)
    depth = H_UNITS - QUAY
    facade = FACADES[i % len(FACADES)]
    roof = random.choice(TILE) if random.random() < 0.7 else random.choice(SLATE)
    # The cast shadow down-right onto the quay and the next house.
    d.rectangle([P(x + 3, QUAY + 3), P(x + w + 4, H_UNITS)], fill=(10, 14, 16, 60))
    # The facade's lip with its window heads and the eaves' shadow.
    rect(x, QUAY, w, LIP, facade)
    cols = max(2, int(w / 15))
    for c in range(cols):
        wx = x + (c + 0.5) * w / cols - 2.6
        rect(wx, QUAY + 3.2, 5.2, 6.8, shade(facade, 0.38))
        rect(wx, QUAY + 3.2, 5.2, 1.0, (210, 210, 200))  # white frames
    rect(x, QUAY + LIP - 1.4, w, 1.4, shade(facade, 0.6))
    # The roof: ridge along the street; the near plane lit, the far in shade.
    top = QUAY + LIP
    ridge = top + depth * 0.4
    rect(x, top, w, ridge - top, shade(roof, 1.12))
    rect(x, ridge, w, H_UNITS - ridge, shade(roof, 0.86))
    # Courses of tiles (or slates), finer on slate.
    step = 2.4 if roof in TILE else 2.0
    yy = top + step
    while yy < H_UNITS:
        d.line([P(x + 0.5, yy), P(x + w - 0.5, yy)], fill=shade(roof, 0.7) + (120,), width=max(1, int(0.35 * SS)))
        yy += step
    if roof in TILE:
        xx = x + 1.5
        while xx < x + w:
            d.line([P(xx, top + 0.5), P(xx, H_UNITS)], fill=shade(roof, 0.75) + (60,), width=max(1, int(0.3 * SS)))
            xx += 3.0
    d.line([P(x, ridge), P(x + w, ridge)], fill=shade(roof, 0.55) + (255,), width=int(1.0 * SS))
    # Dormers on the street side, a chimney or two on the ridge.
    for _ in range(random.choice((0, 1, 2))):
        dx = x + random.uniform(8, max(9, w - 20))
        rect(dx + 1.5, top + 4, 12, 9, (10, 14, 16, 70))
        rect(dx, top + 2.5, 12, 9, shade(roof, 1.0))
        rect(dx + 2, top + 3, 8, 3, (52, 62, 70))
    if random.random() < 0.7:
        cx = x + random.uniform(6, max(7, w - 14))
        rect(cx + 2, ridge - 3, 7, 7, (10, 14, 16, 80))
        rect(cx, ridge - 5, 7, 7, (118, 90, 76))
        rect(cx + 2, ridge - 3, 3, 3, (40, 34, 30))
    # Eaves line and the party wall to the next house.
    d.line([P(x, top), P(x + w, top)], fill=(30, 34, 36, 150), width=int(0.6 * SS))
    d.line([P(x + w, QUAY), P(x + w, H_UNITS)], fill=(30, 34, 36, 160), width=int(0.8 * SS))
    x += w + random.uniform(0, 1.5)
    i += 1

# Fine grain, then a touch of softness.
arr = np.asarray(img, np.float32)
noise = (np.random.default_rng(1673).random(arr.shape[:2]) - 0.5)[..., None] * 10
arr[..., :3] = np.clip(arr[..., :3] + noise, 0, 255)
img = Image.fromarray(arr.astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(0.6))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.resize((W_UNITS * FINAL, H_UNITS * FINAL), Image.LANCZOS).save(OUT, optimize=True)
print("wrote", os.path.relpath(OUT, ROOT))
