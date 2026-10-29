"""Paints the opening story's stills (Between Horizons, I027 Tier 4).

Usage: python3 tools/branding/paint_opening_scenes.py

Two scenes in the title painting's manner (paint_title_scene.py: soft
gouache-like washes, dry-brush strokes, no outlines, natural subdued colour),
for the new-game opening (src/ui/opening_story.gd):

  desk_at_dusk.png  - "For years, the sea had been calling": an office window
                      at dusk over the city roofs and the harbour, a sail far
                      out on the water; on the desk a chart with a pencilled
                      course, dividers and a mug.
  harbour_dawn.png  - "Until one day...": a guest pontoon at dawn in a little
                      mist, a small sloop moored alongside, a sea bag set
                      down on the planks.

The third and last still is the title painting itself (assets/ui/
title_scene.png). Writes assets/opening/*.png (1920 x 1080). Generated,
provisional art: the Captain's own painting replaces a file of the same name
and size, or comes through art_replacements/10_shared_props.

Requirements: Python 3 with Pillow and numpy.
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from paint_title_scene import fbm, gradient  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
W, H = 1920, 1080
OUT = os.path.join(ROOT, "assets", "opening")


def wash(rgb, mask, colour, amount=1.0, blur=1.0):
    """Lays `colour` over `rgb` through a mask (L image), softened."""
    m = np.asarray(mask.filter(ImageFilter.GaussianBlur(blur)), np.float32)[..., None] / 255.0 * amount
    return rgb * (1 - m) + np.array(colour, np.float32) * m


def poly_mask(points):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).polygon(points, fill=255)
    return m


def rect_mask(box):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).rectangle(box, fill=255)
    return m


def finish(rgb, rng, vignette=0.5):
    vy, vx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = np.clip(((vx - W / 2) / (W * 0.62)) ** 2 + ((vy - H * 0.5) / (H * 0.66)) ** 2, 0, 1) * vignette
    rgb = rgb * (1 - v[..., None] * 0.6)
    rgb += (rng.random((H, W, 1)).astype(np.float32) - 0.5) * 6  # paper grain
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")


def desk_at_dusk():
    rng = np.random.default_rng(1902)
    # The window: dusk sky, city roofs, the harbour and the sea beyond.
    win = (180, 110, 1740, 760)
    sky_h = 520
    rgb = np.zeros((H, W, 3), np.float32)
    rgb[:] = (52, 50, 54)  # the room, in shadow
    sky = gradient((96, 104, 128), (214, 172, 140), sky_h, W)
    clouds = np.clip((fbm(W, sky_h, 460, 50, rng, 5) - 0.48) * 2.2, 0, 1)[..., None]
    sky = sky * (1 - clouds * 0.25) + np.array((132, 120, 138), np.float32) * clouds * 0.25
    rgb[:sky_h] = sky
    sea_y = 470
    sea = gradient((176, 150, 138), (88, 98, 112), H - sea_y, W)
    rgb[sea_y:] = sea
    # A sail far out, catching the last light.
    rgb = wash(rgb, poly_mask([(1240, 462), (1252, 420), (1260, 462)]), (236, 222, 206), 0.9, 0.6)
    # The far shore and the harbour cranes.
    shore = [(0, 472)] + [(x, 466 - 8 * math.sin(x / 140.0) ** 2) for x in range(0, W + 40, 40)] + [(W, 480), (0, 480)]
    rgb = wash(rgb, poly_mask(shore), (120, 112, 120), 0.8, 1.5)
    for cx in (520, 600, 690):
        rgb = wash(rgb, poly_mask([(cx, 470), (cx + 6, 470), (cx + 6, 400), (cx + 70, 396), (cx + 70, 402), (cx + 6, 406)]),
                   (92, 88, 98), 0.85, 0.8)
    # City roofs in front, darker, a few windows lit.
    roofs = [(0, H)]
    x = 0
    while x < W:
        w = rng.integers(70, 160)
        h = rng.integers(70, 190)
        roofs += [(x, 760 - h), (x + w * 0.5, 760 - h - rng.integers(0, 40)), (x + w, 760 - h)]
        x += w
    roofs += [(W, H)]
    rgb = wash(rgb, poly_mask(roofs), (58, 60, 70), 0.95, 2.2)
    # A farther row of roofs in the haze behind, and the dusk light on their ridges.
    far = [(0, 700)] + [(x, 640 - 30 * abs(math.sin(x / 70.0))) for x in range(0, W + 30, 30)] + [(W, 700)]
    rgb = wash(rgb, poly_mask(far), (104, 96, 108), 0.35, 3.0)
    ridges = Image.new("L", (W, H), 0)
    ImageDraw.Draw(ridges).line(roofs[1:-1], fill=255, width=3)
    rgb = wash(rgb, ridges, (190, 150, 128), 0.5, 1.5)
    lights = Image.new("L", (W, H), 0)
    ld = ImageDraw.Draw(lights)
    for _ in range(160):
        lx, ly = rng.integers(0, W), rng.integers(600, 760)
        ld.rectangle([lx, ly, lx + 5, ly + 7], fill=int(rng.integers(120, 255)))
    rgb = wash(rgb, lights, (236, 196, 132), 0.8, 0.8)
    # The window frame and mullions: everything outside the glass is the room.
    outside = Image.new("L", (W, H), 255)
    ImageDraw.Draw(outside).rectangle(win, fill=0)
    rgb = wash(rgb, outside, (60, 56, 60), 1.0, 0.8)
    frame = Image.new("L", (W, H), 0)
    fd = ImageDraw.Draw(frame)
    fd.rectangle(win, outline=255, width=26)
    fd.rectangle([(win[0] + win[2]) // 2 - 9, win[1], (win[0] + win[2]) // 2 + 9, win[3]], fill=255)
    fd.rectangle([win[0], 360, win[2], 374], fill=255)
    rgb = wash(rgb, frame, (82, 78, 80), 1.0, 1.0)
    # Warm light from the desk lamp on the room's side.
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lamp = np.exp(-(((xx - 260) / 520) ** 2 + ((yy - 900) / 300) ** 2))[..., None]
    rgb = rgb * (1 - lamp * 0.35) + np.array((214, 168, 110), np.float32) * lamp * 0.35
    # The desk, and the chart spread on it: sea, a coastline, a course.
    desk = [(0, 820), (W, 790), (W, H), (0, H)]
    rgb = wash(rgb, poly_mask(desk), (104, 78, 58), 1.0, 1.0)
    grain = fbm(W, H, 900, 8, rng, 3)[..., None]
    rgb = rgb + (grain - 0.5) * 18 * (np.asarray(poly_mask(desk), np.float32)[..., None] / 255.0)
    chart = [(560, 860), (1500, 836), (1580, 1080), (480, 1080)]
    rgb = wash(rgb, poly_mask(chart), (214, 210, 190), 1.0, 1.0)
    rgb = wash(rgb, poly_mask([(560, 860), (1050, 848), (980, 1080), (480, 1080)]), (188, 206, 206), 0.55, 2.0)
    coast = [(1050, 848), (1010, 900), (1040, 950), (990, 1010), (1010, 1080), (1580, 1080), (1500, 836)]
    rgb = wash(rgb, poly_mask(coast), (222, 206, 160), 0.7, 1.5)
    grid = Image.new("L", (W, H), 0)
    gd = ImageDraw.Draw(grid)
    for k in range(1, 7):
        gd.line([(560 - k * 13, 860 + k * 36), (1500 + k * 13, 836 + k * 36)], fill=120, width=1)
    for k in range(1, 9):
        gd.line([(560 + k * 118, 858), (480 + k * 138, H)], fill=120, width=1)
    rgb = wash(rgb, grid, (120, 132, 140), 0.35, 0.6)
    soundings = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(soundings)
    for _ in range(70):
        px, py = rng.integers(560, 960), rng.integers(880, 1060)
        sd.text((px, py), str(int(rng.integers(3, 40))), fill=150)
    rgb = wash(rgb, soundings, (90, 100, 110), 0.5, 0.3)
    rose = Image.new("L", (W, H), 0)
    rd = ImageDraw.Draw(rose)
    rd.ellipse([1300, 940, 1420, 1060], outline=170, width=2)
    rd.polygon([(1360, 944), (1366, 1000), (1360, 1056), (1354, 1000)], fill=170)
    rd.polygon([(1304, 1000), (1360, 994), (1416, 1000), (1360, 1006)], fill=150)
    rgb = wash(rgb, rose, (130, 96, 80), 0.6, 0.5)
    course = Image.new("L", (W, H), 0)
    cd = ImageDraw.Draw(course)
    cd.line([(640, 1040), (760, 960), (900, 930), (1000, 870)], fill=200, width=3)
    for px, py in ((640, 1040), (760, 960), (900, 930), (1000, 870)):
        cd.ellipse([px - 5, py - 5, px + 5, py + 5], outline=200, width=2)
    rgb = wash(rgb, course, (80, 72, 78), 0.8, 0.4)
    # Dividers across the chart, and a mug beside it.
    div = Image.new("L", (W, H), 0)
    dd = ImageDraw.Draw(div)
    dd.line([(1180, 900), (1120, 1040)], fill=255, width=5)
    dd.line([(1180, 900), (1250, 1030)], fill=255, width=5)
    dd.ellipse([1172, 890, 1190, 908], fill=255)
    rgb = wash(rgb, div, (176, 150, 96), 0.9, 0.6)
    # The mug: a glazed cylinder, its rim, the tea, a handle and its shadow.
    rgb = wash(rgb, poly_mask([(1650, 1010), (1790, 1004), (1800, 1030), (1640, 1034)]), (60, 44, 34), 0.45, 8.0)
    body = Image.new("L", (W, H), 0)
    bd = ImageDraw.Draw(body)
    bd.rectangle([1650, 910, 1750, 1010], fill=255)
    bd.ellipse([1650, 996, 1750, 1024], fill=255)
    rgb = wash(rgb, body, (70, 92, 110), 1.0, 1.0)
    xs = np.arange(W, dtype=np.float32)
    shade_x = np.clip((xs - 1650) / 100.0, 0, 1)
    cyl = (0.25 - 0.55 * np.sin(shade_x * math.pi)) * (np.asarray(body, np.float32) / 255.0)
    rgb += cyl[..., None] * 40
    rim = Image.new("L", (W, H), 0)
    ImageDraw.Draw(rim).ellipse([1650, 898, 1750, 922], fill=255)
    rgb = wash(rgb, rim, (96, 118, 134), 1.0, 0.8)
    tea = Image.new("L", (W, H), 0)
    ImageDraw.Draw(tea).ellipse([1658, 902, 1742, 918], fill=255)
    rgb = wash(rgb, tea, (92, 62, 40), 1.0, 0.8)
    handle = Image.new("L", (W, H), 0)
    ImageDraw.Draw(handle).arc([1728, 930, 1790, 990], -80, 80, fill=255, width=12)
    rgb = wash(rgb, handle, (64, 86, 104), 1.0, 1.0)
    return finish(rgb, rng, 0.55)


def harbour_dawn():
    rng = np.random.default_rng(1919)
    horizon = 560
    rgb = np.zeros((H, W, 3), np.float32)
    rgb[:horizon] = gradient((150, 164, 180), (232, 206, 176), horizon, W)
    yy, xx = np.mgrid[0:horizon, 0:W].astype(np.float32)
    sun = np.exp(-(((xx - 1380) / 260) ** 2 + ((yy - 520) / 110) ** 2))[..., None]
    rgb[:horizon] = rgb[:horizon] * (1 - sun * 0.5) + np.array((246, 220, 180), np.float32) * sun * 0.5
    clouds = np.clip((fbm(W, horizon, 600, 40, rng, 5) - 0.5) * 2.0, 0, 1)[..., None]
    rgb[:horizon] = rgb[:horizon] * (1 - clouds * 0.2) + np.array((200, 176, 170), np.float32) * clouds * 0.2
    # The town across the water, in mist.
    town = [(0, horizon)]
    x = 0
    while x < W:
        w = rng.integers(40, 110)
        h = rng.integers(20, 70)
        town += [(x, horizon - h), (x + w, horizon - h)]
        x += w
    town += [(W, horizon), (0, horizon)]
    rgb = wash(rgb, poly_mask(town), (150, 150, 160), 0.6, 2.5)
    rgb = wash(rgb, poly_mask([(900, horizon - 70), (912, horizon - 150), (924, horizon - 70)]), (140, 140, 150), 0.6, 2.0)  # a spire
    # Calm water, the dawn light lying on it.
    n = H - horizon
    rgb[horizon:] = gradient((200, 186, 170), (70, 92, 104), n, W)
    sheen = fbm(W, n, 700, 10, rng, 4)[..., None]
    rgb[horizon:] += (sheen - 0.5) * 22
    glint = np.exp(-((np.arange(W, dtype=np.float32)[None, :] - 1380) / 140) ** 2)[..., None] \
        * np.exp(-(np.arange(n, dtype=np.float32)[:, None] / 260))[..., None]
    rgb[horizon:] = rgb[horizon:] * (1 - glint * 0.45) + np.array((244, 222, 186), np.float32) * glint * 0.45
    # Mist low over the water.
    mist = np.exp(-((np.arange(H, dtype=np.float32) - horizon) / 50) ** 2)[:, None, None]
    rgb = rgb * (1 - mist * 0.5) + np.array((226, 216, 204), np.float32) * mist * 0.5
    # The sloop alongside, upright, her mainsail stowed under its cover.
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
    moored_sloop(img, 1270, 744, 1.85)
    rgb = np.asarray(img.convert("RGB"), np.float32)
    # The pontoon: planks running towards the viewer, a cleat, a sea bag.
    pontoon = [(560, 740), (1000, 740), (1260, H), (0, H), (0, 930)]
    rgb = wash(rgb, poly_mask(pontoon), (138, 116, 92), 1.0, 1.0)
    planks = Image.new("L", (W, H), 0)
    pd = ImageDraw.Draw(planks)
    for k in range(1, 28):
        t = (k / 28) ** 1.6
        y = 740 + t * (H - 740)
        x0 = 560 - t * 560
        x1 = 1000 + t * 260
        pd.line([(x0, y), (x1, y)], fill=150, width=max(1, int(1 + t * 3)))
    rgb = wash(rgb, planks, (92, 76, 62), 0.7, 0.6)
    # Plank joints converging away from the viewer, and the pontoon's edge in shade.
    joints = Image.new("L", (W, H), 0)
    jd = ImageDraw.Draw(joints)
    for k in range(1, 9):
        jd.line([(560 + k * 55, 740), (k * 157, H)], fill=110, width=2)
    rgb = wash(rgb, joints, (100, 82, 66), 0.6, 0.8)
    rgb = wash(rgb, poly_mask([(1000, 740), (1012, 740), (1276, H), (1260, H)]), (70, 60, 52), 0.9, 1.0)
    rgb = wash(rgb, poly_mask([(1012, 742), (1030, 760), (1296, H), (1276, H)]), (60, 74, 80), 0.6, 2.0)  # its shadow on the water
    # A cleat with the boat's line made fast.
    rgb = wash(rgb, poly_mask([(880, 790), (960, 790), (952, 804), (888, 804)]), (64, 66, 68), 1.0, 0.6)
    line = Image.new("L", (W, H), 0)
    ImageDraw.Draw(line).line([(950, 796), (1010, 770), (1080, 742)], fill=255, width=4, joint="curve")
    rgb = wash(rgb, line, (210, 200, 176), 0.9, 0.6)
    # The sea bag: a canvas duffel lying on the planks, straps and a shadow.
    rgb = wash(rgb, poly_mask([(500, 960), (790, 960), (800, 984), (490, 986)]), (60, 50, 42), 0.45, 8.0)
    duffel = Image.new("L", (W, H), 0)
    ImageDraw.Draw(duffel).rounded_rectangle([510, 880, 780, 970], radius=44, fill=255)
    rgb = wash(rgb, duffel, (58, 82, 102), 1.0, 1.2)
    top_light = Image.new("L", (W, H), 0)
    ImageDraw.Draw(top_light).rounded_rectangle([540, 888, 750, 914], radius=13, fill=255)
    rgb = wash(rgb, top_light, (104, 132, 150), 0.6, 4.0)
    for sx in (590, 700):
        rgb = wash(rgb, rect_mask([sx, 880, sx + 12, 970]), (196, 182, 140), 0.85, 0.8)
    rgb = wash(rgb, rect_mask([600, 870, 690, 878]), (60, 48, 38), 0.9, 0.8)  # the handle
    return finish(rgb, rng, 0.45)


def moored_sloop(img, cx, wl, s):
    """A small cruising sloop alongside, side view, upright: white topsides
    with a navy boot stripe, the coachroof and its windows, the mast and its
    stays, the mainsail stowed on the boom under a blue cover, and her
    reflection in the still water."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer, "RGBA")
    L = 300 * s
    bow, stern = cx + L * 0.5, cx - L * 0.5
    sheer = lambda x: wl - 26 * s + 8 * s * ((x - cx) / L * 2 - 0.25) ** 2  # noqa: E731
    hull = [(stern, sheer(stern) + 2), (stern + 6 * s, wl + 5 * s)]
    hull += [(stern + 6 * s + (bow - stern - 34 * s) * k / 10, wl + 7 * s) for k in range(11)]
    hull += [(bow, sheer(bow) - 8 * s)]
    hull += [(x, sheer(x)) for x in np.linspace(bow, stern, 18)]
    d.polygon(hull, fill=(228, 228, 222, 255))
    d.polygon([(stern + 4 * s, wl - 7 * s), (bow - 22 * s, wl - 7 * s), (bow - 30 * s, wl + 7 * s), (stern + 6 * s, wl + 7 * s)],
              fill=(176, 180, 178, 190))
    d.polygon([(stern + 6 * s, wl), (bow - 32 * s, wl), (bow - 34 * s, wl + 5 * s), (stern + 8 * s, wl + 5 * s)], fill=(46, 72, 92, 255))
    d.line([(x, sheer(x) - 1) for x in np.linspace(stern, bow, 24)], fill=(130, 120, 104, 255), width=3)  # teak toe rail
    roof = [(cx - 60 * s, sheer(cx - 60 * s)), (cx - 54 * s, sheer(cx) - 14 * s), (cx + 46 * s, sheer(cx) - 12 * s),
            (cx + 66 * s, sheer(cx + 66 * s))]
    d.polygon(roof, fill=(232, 232, 226, 255))
    for k in range(3):
        x0 = cx - 40 * s + k * 30 * s
        d.polygon([(x0, sheer(cx) - 8 * s), (x0 + 20 * s, sheer(cx) - 8 * s), (x0 + 19 * s, sheer(cx) - 4 * s),
                   (x0 + 1 * s, sheer(cx) - 4 * s)], fill=(44, 56, 64, 255))
    for x in np.linspace(stern + 10 * s, bow - 30 * s, 8):
        d.line([(x, sheer(x) - 1), (x, sheer(x) - 18 * s)], fill=(160, 166, 168, 230), width=2)
    d.line([(x, sheer(x) - 17 * s) for x in np.linspace(stern + 10 * s, bow - 30 * s, 14)], fill=(176, 180, 182, 210), width=2)
    mast_x = cx + 18 * s
    top = (mast_x, wl - 420 * s)
    d.line([(mast_x, sheer(mast_x) - 12 * s), top], fill=(186, 190, 192, 255), width=max(3, int(4 * s)))
    d.line([top, (bow - 6 * s, sheer(bow) - 8 * s)], fill=(110, 118, 122, 220), width=2)
    d.line([top, (stern + 3 * s, sheer(stern))], fill=(110, 118, 122, 220), width=2)
    d.line([(mast_x - 2 * s, wl - 230 * s), (mast_x + 26 * s, sheer(mast_x + 26 * s)), (mast_x - 2 * s, wl - 230 * s),
            (mast_x - 30 * s, sheer(mast_x - 30 * s))], fill=(120, 128, 132, 160), width=1)  # spreader and shrouds
    boom_y = sheer(mast_x) - 44 * s
    d.line([(mast_x, boom_y), (stern + 28 * s, boom_y + 4 * s)], fill=(140, 146, 148, 255), width=max(3, int(4 * s)))
    cover = [(mast_x - 4 * s, boom_y - 12 * s), (stern + 32 * s, boom_y - 6 * s), (stern + 30 * s, boom_y + 3 * s), (mast_x - 4 * s, boom_y + 2 * s)]
    d.polygon(cover, fill=(46, 76, 104, 255))
    d.line([(mast_x - 4 * s, boom_y - 6 * s), (stern + 32 * s, boom_y - 2 * s)], fill=(70, 104, 132, 200), width=2)
    soft = layer.filter(ImageFilter.GaussianBlur(0.5))
    img.alpha_composite(soft)
    # Her reflection: flipped, softened and broken a little by the water.
    refl = layer.crop((0, 0, img.size[0], int(wl + 8 * s))).transpose(Image.FLIP_TOP_BOTTOM)
    arr = np.asarray(refl, np.float32)
    arr[..., 3] *= 0.32
    ripple = Image.fromarray(arr.astype(np.uint8), "RGBA").filter(ImageFilter.GaussianBlur(3))
    holder = Image.new("RGBA", img.size, (0, 0, 0, 0))
    holder.paste(ripple, (0, int(wl + 8 * s)))
    img.alpha_composite(holder)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, painter in (("desk_at_dusk.png", desk_at_dusk), ("harbour_dawn.png", harbour_dawn)):
        img = painter()
        path = os.path.join(OUT, name)
        img.save(path, optimize=True)
        print("wrote", os.path.relpath(path, ROOT), img.size)


if __name__ == "__main__":
    main()
