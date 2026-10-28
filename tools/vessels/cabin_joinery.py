"""Yacht interiors for the illustrated cabins (I025, A Little More Room Aboard).

Shared by both cabin painters (paint_illustrated_vessel.py for the Arctic
Wanderer 26, Frogleap 36 and Clam 40, paint_illustrated_starling.py for the
Wing 33). Every piece is painted from the boat's own cabin_visual.tscn shapes,
so the art keeps lining up with the unchanged collision, stations, spawn
points and companion spots; only the look changes:

- the hull's inside (hull_lining): the cut gelcoat edge and rubbing strake, a
  strip of pale headlining, varnished ceiling battens following the hull's
  curve and darkening towards the sole, frames at a regular spacing, a
  varnished trim where the sole meets the hull side, and a recessed opening
  with a rubber-sealed frame at every window of data/vessels/cabin_windows.json
  (the same openings CabinWindows fills with the world outside);
- the cabin sole: teak and holly in lift-out boards with brass finger rings,
  shading softly into the corners (soft ambient occlusion along the hull);
- marine joinery (cabinetry): rounded corners, varnished teak with grain and
  figure, a raised fiddle round every top, soft drop shadows;
- upholstery (settee): seat and back cushions with piping and buttons, a lee
  cloth tucked under the seat's front edge;
- berths (berth): a fitted mattress with piping, sheet, quilted duvet, plump
  pillows, a bunk board or lee cloth on the open side of a single, the infill
  seam of a V-berth;
- equipment: a gimballed stainless stove with pan supports and a pot rail, a
  stainless sink with its mixer tap, a top-loading fridge lid, a chart table
  with its hinged lid, chart and an instrument panel (plotter, VHF, switch
  panel), companionway steps with non-slip treads and stainless grab rails, an
  insulated engine box, louvred locker doors, a GRP heads moulding with a
  marine toilet and a teak shower grating.

Light comes from the upper left; shadows fall down and to the right.
Requires Pillow, numpy and shapely.
"""
import json
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

from illustrate import (BLANKET, CUSHION, HONEY, INK, ROOT, SEAGLASS, SHADOW_TINT, SS, STEEL, STEEL_DARK,
                        STEEL_LIGHT, _geom_mask, _lines_of, _polys_of, teak_sole)

WINDOWS_PATH = os.path.join(ROOT, "data", "vessels", "cabin_windows.json")

VARNISH = (110, 82, 58)          # varnished teak joinery
VARNISH_LIGHT = (150, 116, 84)   # a lit edge, trim and fiddles
BULKHEAD = (84, 64, 48)          # structural bulkhead ply, darker
CEILING = (82, 64, 50)           # the hull's ceiling battens (dark, varnished)
HULL_DARK = (46, 40, 35)         # the hull's inside between the battens
HEADLINING = (150, 146, 136)     # pale vinyl headlining under the side deck
GELCOAT = (198, 200, 194)        # the cut hull at deck level
RUBBING = (86, 92, 94)           # rubbing strake
SHEET = (210, 208, 200)          # fitted sheet
PILLOW = (226, 224, 216)
WORKTOP = (204, 204, 198)        # solid-surface worktop
GRP = (210, 211, 205)            # moulded heads unit
CANVAS = (168, 164, 150)         # lee cloth
BRASS = (170, 146, 96)
SCREEN = (34, 70, 82)            # a plotter's day screen
PANEL = (34, 38, 42)


def darker(c, k):
    return tuple(int(v * k) for v in c)


def lighter(c, k):
    return tuple(min(255, int(v * k + 8)) for v in c)


def load_windows(vessel):
    """The vessel's window openings: [{"at", "length", "thickness", "angle", "side"}]."""
    with open(WINDOWS_PATH) as f:
        data = json.load(f)
    return data.get("windows", {}).get(vessel, [])


def window_axes(w):
    """(outward, along) unit vectors of a window, as CabinWindows.axes() does."""
    base = {"port": (0.0, -1.0), "starboard": (0.0, 1.0), "forward": (1.0, 0.0), "aft": (-1.0, 0.0)}[w.get("side", "port")]
    a = math.radians(w.get("angle", 0.0))
    out = (base[0] * math.cos(a) - base[1] * math.sin(a), base[0] * math.sin(a) + base[1] * math.cos(a))
    along = (-out[1], out[0])
    return out, along


def window_shape(w, grow=0.0, radius=None):
    """The opening of window `w` (grown by `grow` units) as a rounded outline."""
    out, along = window_axes(w)
    cx, cy = w["at"]
    hl = w["length"] / 2 + grow
    ht = w["thickness"] / 2 + grow
    r = min(ht, 3.5) if radius is None else radius
    pts = []
    for (sx, sy, a0) in ((1, 1, 0), (-1, 1, 90), (-1, -1, 180), (1, -1, 270)):
        ccx, ccy = sx * (hl - r), sy * (ht - r)
        for i in range(7):
            ang = math.radians(a0 + i * 15)
            u, v = ccx + r * math.cos(ang), ccy + r * math.sin(ang)
            pts.append((cx + along[0] * u + out[0] * v, cy + along[1] * u + out[1] * v))
    return pts


def soft(pts, r=2.5):
    """A shape with its corners rounded by about r units (joinery is never sharp)."""
    p = Polygon(pts).buffer(0)
    if p.is_empty:
        return list(pts)
    q = p.buffer(-r, join_style=2).buffer(r, join_style=1, quad_segs=4)
    if q.is_empty or q.geom_type != "Polygon" or q.area < p.area * 0.6:
        return list(pts)
    return list(q.exterior.coords)[:-1]


def inset(pts, d, r=None):
    q = Polygon(pts).buffer(-d, join_style=2)
    if q.is_empty or q.geom_type != "Polygon":
        return None
    if r:
        q2 = q.buffer(-r, join_style=2).buffer(r, join_style=1, quad_segs=4)
        if not q2.is_empty and q2.geom_type == "Polygon":
            q = q2
    return list(q.exterior.coords)[:-1]


def bbox(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def geom_fill(L, geom, color, variation=0.05, grain=50.0, alpha=255):
    if geom is None or geom.is_empty:
        return
    L.fill(None, color, variation, grain=grain, alpha=alpha, mask=_geom_mask(L, geom))


def geom_line(L, geom, width, color, alpha=200):
    d = ImageDraw.Draw(L.img, "RGBA")
    for ln in _lines_of(geom):
        if len(ln) >= 2:
            d.line([L.px(p) for p in ln], fill=color + (alpha,), width=max(1, int(width * SS)), joint="curve")


def soft_shade(L, geom, clip, blur, alpha, color=SHADOW_TINT):
    """A blurred tone of `geom`, kept inside `clip` (soft occlusion, light pools)."""
    m = _geom_mask(L, geom).filter(ImageFilter.GaussianBlur(blur * SS))
    m = Image.fromarray((np.asarray(m, np.float32) * alpha / 255.0).astype(np.uint8))
    if clip is not None:
        m = Image.fromarray(np.minimum(np.asarray(m), np.asarray(_geom_mask(L, clip))))
    layer = Image.new("RGBA", L.img.size, color + (0,))
    layer.putalpha(m)
    L.img.alpha_composite(layer)


# ======================================================================= shell

def hull_outline(hulls, sole, band):
    """The hull as seen in the cabin: the scene's hull shapes, widened where
    needed so the wall band is at least `band` units all round the sole."""
    return unary_union([Polygon(h).buffer(0) for h in hulls] + [Polygon(sole).buffer(band, join_style=2)])


def cabin_sole(L, sole, boards=110.0, rings=()):
    """Teak and holly in lift-out boards: athwartships joints every `boards`
    units, a brass finger ring at each of `rings`, soft shade into the
    corners along the hull."""
    L.shadow(sole, (0, 0), 6, 120)
    teak_sole(L, sole, strip=11.0, color=HONEY, holly_alpha=70)
    L.grain(sole, (96, 78, 60), True, spacing=3.0, alpha=30)
    poly = Polygon(sole).buffer(0)
    minx, miny, maxx, maxy = poly.bounds
    x = minx + boards * 0.75
    while x < maxx - 30:
        seg = LineString([(x, miny), (x, maxy)]).intersection(poly.buffer(-6.0))
        geom_line(L, seg, 0.6, (52, 42, 34), 130)
        geom_line(L, seg.parallel_offset(0.8, "left") if seg.geom_type == "LineString" else seg, 0.4, (170, 140, 104), 90)
        x += boards
    for (rx, ry) in rings:
        L.circle((rx, ry), 3.4, (60, 48, 38), 0.0, n=16, shadow=False)        # the recess
        L.circle((rx, ry), 2.4, BRASS, 0.5, n=16, shadow=False)              # the ring, flush
        L.circle((rx - 0.5, ry - 0.5), 1.2, (90, 74, 52), 0.0, n=12, shadow=False)
    # Soft occlusion where the sole meets the hull side and in the corners.
    edge = poly.difference(poly.buffer(-16.0))
    soft_shade(L, edge, poly, 7.0, 95)


def hull_lining(L, hull, sole, windows, band):
    """The hull's inside seen from above, between the sole and the sheer: the
    cut hull and rubbing strake, a strip of pale headlining under the side
    deck, varnished ceiling battens following the hull's curve (darker
    towards the sole, where the topsides turn under), frames every ~60 units,
    a varnished trim along the sole, and a recessed, sealed frame at every
    window opening."""
    sole_p = Polygon(sole).buffer(0)
    wall = hull.difference(sole_p)
    if wall.is_empty:
        return
    geom_fill(L, wall, HULL_DARK, 0.04)
    rim = 2.0
    head = max(2.5, band * 0.26)
    lining = hull.buffer(-rim, join_style=2).difference(hull.buffer(-(rim + head), join_style=2)).difference(sole_p)
    geom_fill(L, lining, HEADLINING, 0.03, grain=40.0)
    # The headlining's padded seams (buttoned vinyl): a faint line along it.
    geom_line(L, hull.buffer(-(rim + head * 0.5), join_style=2).difference(sole_p.buffer(1.0)).boundary
              .intersection(lining.buffer(0.2)), 0.35, darker(HEADLINING, 0.8), 90)
    # Battens: strips following the hull, a dark gap between.
    a = rim + head + 0.8
    strip = 3.2 if band >= 16 else 2.6
    k = 0
    while True:
        ring = hull.buffer(-a, join_style=2).difference(hull.buffer(-(a + strip - 0.7), join_style=2)).difference(sole_p.buffer(0.4))
        if ring.is_empty or a > band + rim:
            break
        tone = 1.0 + (0.06 if k % 2 else -0.03) - min(k * 0.07, 0.3)
        geom_fill(L, ring, tuple(int(min(255, c * tone)) for c in CEILING), 0.05, grain=30.0)
        a += strip
        k += 1
    # Where the hull runs on beyond the band (under the cockpit, in the
    # bow): a deep, quiet shadow rather than more battens.
    deep = hull.buffer(-(band + rim + 2.0), join_style=2).difference(sole_p.buffer(2.0))
    if not deep.is_empty:
        soft_shade(L, deep, wall, band * 0.6, 70)
    # The topsides turn under towards the sole: deepen the shade there.
    soft_shade(L, sole_p.buffer(band * 0.55, join_style=2).difference(sole_p), wall, band * 0.25, 120)
    # Frames: ribs across the band every ~60 units along the sole's edge.
    edge = sole_p.exterior
    d = 30.0
    while d < edge.length:
        p = edge.interpolate(d)
        q = edge.interpolate(min(d + 1.0, edge.length))
        tx, ty = q.x - p.x, q.y - p.y
        n = math.hypot(tx, ty) or 1.0
        nx, ny = ty / n, -tx / n
        if sole_p.contains(Point(p.x + nx * 2, p.y + ny * 2)):
            nx, ny = -nx, -ny
        rib = LineString([(p.x, p.y), (p.x + nx * band * 2.2, p.y + ny * band * 2.2)]).intersection(
            wall.difference(lining.buffer(0.3)).difference(deep))
        geom_line(L, rib, 2.0, darker(CEILING, 0.72), 230)
        geom_line(L, rib.parallel_offset(0.9, "left") if rib.geom_type == "LineString" else rib, 0.45, lighter(CEILING, 1.2), 110)
        d += 60.0
    # The cut gelcoat at the sheer, and the rubbing strake outside it.
    geom_fill(L, hull.difference(hull.buffer(-rim, join_style=2)), GELCOAT, 0.02)
    geom_line(L, hull.boundary, 1.3, RUBBING, 235)
    # The sole's edge: a varnished trim with its lit top.
    L.ink(list(sole_p.exterior.coords)[:-1], 1.8, VARNISH, amp=0.0, alpha=255)
    L.ink(list(sole_p.exterior.coords)[:-1], 0.5, VARNISH_LIGHT, amp=0.0, alpha=170)
    # Window recesses: a dark rubber-sealed frame round a dark opening (the
    # world outside is drawn into the opening by CabinWindows at runtime).
    for w in windows:
        outer = window_shape(w, 2.2, radius=1.0)            # square-cornered frame round the rounded glass
        L.shadow(outer, (0.8, 1.2), 1.4, 80)
        L.fill(outer, (66, 72, 74), 0.02)                    # anodised frame
        L.fill(window_shape(w, 0.6), (22, 26, 28), 0.02)     # rubber seal
        L.fill(window_shape(w), (34, 46, 54), 0.03)          # smoked acrylic
        L.line(window_shape(w)[0], window_shape(w)[6], 0.4, (90, 104, 112), 120, 0.0)
        L.ink(outer, 0.4, (96, 102, 104), alpha=180, amp=0.0)


def deck_beyond(L, vessel, hull, sole, min_depth=25.0):
    """Where the hull runs on well beyond the sole fore or aft (the space
    under a cockpit), the deck above it is shown instead of a dark void: the
    boat's own illustrated deck layers, darkened and a little greyed (it is
    above and outside the cabin), behind a varnished bulkhead at the sole's
    end. Returns the area it covered (or None)."""
    sole_p = Polygon(sole).buffer(0)
    sx0, sy0, sx1, sy1 = sole_p.bounds
    hx0, hy0, hx1, hy1 = hull.bounds
    regions = []
    if sx0 - hx0 >= min_depth:
        regions.append((hull.intersection(Polygon([(hx0 - 5, hy0 - 5), (sx0 - 1.0, hy0 - 5), (sx0 - 1.0, hy1 + 5), (hx0 - 5, hy1 + 5)])), sx0 - 1.0))
    if hx1 - sx1 >= min_depth:
        regions.append((hull.intersection(Polygon([(sx1 + 1.0, hy0 - 5), (hx1 + 5, hy0 - 5), (hx1 + 5, hy1 + 5), (sx1 + 1.0, hy1 + 5)])), sx1 + 1.0))
    if not regions:
        return None
    folder = os.path.join(ROOT, "assets", "vessels", vessel, "illustrated", "deck")
    deck = None
    for name in ("hull_base", "deck_base", "coachroof", "deck_details"):
        path = os.path.join(folder, name + ".png")
        if os.path.exists(path):
            img = Image.open(path).convert("RGBA")
            deck = img if deck is None else Image.alpha_composite(deck, img)
    if deck is None:
        return None
    deck = deck.resize(L.img.size, Image.BILINEAR)
    rgb = np.asarray(deck, np.float32)
    grey = rgb[..., :3].mean(axis=2, keepdims=True)
    rgb[..., :3] = (rgb[..., :3] * 0.75 + grey * 0.25) * 0.45
    deck = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGBA")
    covered = unary_union([g for g, _ in regions])
    mask = Image.fromarray(np.minimum(np.asarray(_geom_mask(L, covered)), np.asarray(deck)[..., 3]))
    clipped = Image.new("RGBA", L.img.size, (0, 0, 0, 0))
    clipped.paste(deck, (0, 0), mask)
    L.img.alpha_composite(clipped)
    for geom, x in regions:
        # The cabin's end bulkhead, and the shade it casts onto the deck beyond.
        span = LineString([(x, hy0 - 5), (x, hy1 + 5)]).intersection(hull.buffer(-2.0))
        away = -1.0 if x < sx0 + 1 else 1.0
        soft_shade(L, LineString([(x + away * 4, hy0), (x + away * 4, hy1)]).buffer(5.0), geom, 4.0, 120)
        geom_line(L, span, 4.0, BULKHEAD, 255)
        geom_line(L, LineString([(x - away * 1.4, hy0), (x - away * 1.4, hy1)]).intersection(hull.buffer(-2.0)), 0.8,
                  VARNISH_LIGHT, 200)
    geom_line(L, hull.boundary, 1.3, RUBBING, 235)
    return covered


def floats(L, pts):
    """A trimaran's float seen from inside: outside the hull, muted gelcoat
    with its non-skid and a dark waterline, as if in the shade of the cabin."""
    L.shadow(pts, (3, 5), 6, 110)
    L.fill(pts, (92, 98, 98), 0.03, grain=80.0)
    inner = inset(pts, 6.0)
    if inner:
        L.fill(inner, (80, 86, 86), 0.04)
        L.speckle(inner, (70, 76, 76), density=0.25)
    L.tone_edges(pts, (92, 98, 98), 4.0)
    L.ink(pts, 1.1, RUBBING, alpha=200, amp=0.0)


# ===================================================================== joinery

def cabinetry(L, pts, color=VARNISH, r=2.5, fiddle=True, horizontal=None, shadow=True):
    """Varnished marine joinery: rounded corners, grain and figure along the
    long side, a raised fiddle round the top (lit on its upper-left edge), a
    soft shadow down and to the right. Returns the rounded outline."""
    s = soft(pts, r)
    x0, y0, x1, y1 = bbox(s)
    if horizontal is None:
        horizontal = (x1 - x0) >= (y1 - y0)
    if shadow:
        L.shadow(s, (3, 4.5), 4.0, 95)
    L.fill(s, color, 0.05, grain=40.0)
    L.grain(s, darker(color, 0.74), horizontal, spacing=1.7, alpha=50)
    L.grain(s, darker(color, 0.6), horizontal, spacing=7.0, alpha=34)
    L.tone_edges(s, color, 2.0)
    if fiddle and min(x1 - x0, y1 - y0) > 10:
        rim = inset(s, 2.0, 1.5)
        if rim:
            L.ink(rim, 0.55, darker(color, 0.55), alpha=170, amp=0.0)
            L.ink([(x + 0.5, y + 0.5) for x, y in rim], 0.4, lighter(color, 1.25), alpha=90, amp=0.0)
    L.ink(s, 1.0)
    return s


def bulkhead(L, pts):
    """A structural bulkhead: dark ply, a varnished trim capping its edge."""
    s = cabinetry(L, pts, BULKHEAD, r=1.5, fiddle=False)
    x0, y0, x1, y1 = bbox(s)
    if (x1 - x0) >= (y1 - y0):
        L.line((x0 + 1.5, (y0 + y1) / 2), (x1 - 1.5, (y0 + y1) / 2), 1.6, VARNISH_LIGHT, 200, 0.0)
    else:
        L.line(((x0 + x1) / 2, y0 + 1.5), ((x0 + x1) / 2, y1 - 1.5), 1.6, VARNISH_LIGHT, 200, 0.0)


def locker(L, pts, louvres=True):
    """A locker or wardrobe: joinery with louvred doors (ventilation, as on
    every yacht) and a small brass catch."""
    s = cabinetry(L, pts, VARNISH, fiddle=False)
    x0, y0, x1, y1 = bbox(s)
    w, h = x1 - x0, y1 - y0
    if min(w, h) < 14:
        return
    horizontal = w >= h
    n = max(1, int(round((w if horizontal else h) / 40.0)))
    for i in range(n):
        if horizontal:
            a, b = x0 + 3 + i * (w - 6) / n, x0 + 3 + (i + 1) * (w - 6) / n - 1.5
            door = L.rounded(a, y0 + 3, b - a, h - 6, 1.5)
        else:
            a, b = y0 + 3 + i * (h - 6) / n, y0 + 3 + (i + 1) * (h - 6) / n - 1.5
            door = L.rounded(x0 + 3, a, w - 6, b - a, 1.5)
        L.ink(door, 0.6, darker(VARNISH, 0.55), alpha=180, amp=0.0)
        dx0, dy0, dx1, dy1 = bbox(door)
        if louvres:
            if horizontal:
                y = dy0 + 3
                while y < dy1 - 2.5:
                    L.line((dx0 + 3, y), (dx1 - 3, y), 0.5, darker(VARNISH, 0.5), 150, 0.0)
                    y += 2.6
            else:
                x = dx0 + 3
                while x < dx1 - 2.5:
                    L.line((x, dy0 + 3), (x, dy1 - 3), 0.5, darker(VARNISH, 0.5), 150, 0.0)
                    x += 2.6
        L.circle(((dx0 + dx1) / 2, (dy0 + dy1) / 2), 1.1, BRASS, 0.3, n=10, shadow=False)


def shelf(L, pts, inboard):
    """A bookshelf with a fiddle rail on its open side."""
    s = cabinetry(L, pts, VARNISH, fiddle=False)
    x0, y0, x1, y1 = bbox(s)
    y = y0 + 1.5 if inboard[1] < 0 else y1 - 1.5
    L.line((x0 + 2, y), (x1 - 2, y), 1.4, STEEL, 230, 0.0)
    L.line((x0 + 2, y - 0.5), (x1 - 2, y - 0.5), 0.4, STEEL_LIGHT, 200, 0.0)


def table(L, pts, leaves=()):
    """The saloon table: warm varnish, a fiddle all round, drop-leaf hinges."""
    s = cabinetry(L, pts, (124, 94, 66), r=3.5, fiddle=False)
    rim = inset(s, 1.8, 2.0)
    if rim:
        L.ink(rim, 1.3, (150, 118, 86), alpha=230, amp=0.0)          # the raised fiddle
        L.ink(rim, 0.4, (74, 56, 40), alpha=170, amp=0.0)
    x0, y0, x1, y1 = bbox(s)
    horizontal = (x1 - x0) >= (y1 - y0)
    for k in (0.3, 0.7):
        if horizontal:
            x = x0 + (x1 - x0) * k
            L.line((x, y0 + 3), (x, y1 - 3), 0.5, (70, 54, 40), 190, 0.0)
            for yy in (y0 + 5, y1 - 5):
                L.piece(L.rect(x - 1.2, yy - 1.5, 2.4, 3.0), BRASS, 0.2, shade=False, shadow=False)
        else:
            y = y0 + (y1 - y0) * k
            L.line((x0 + 3, y), (x1 - 3, y), 0.5, (70, 54, 40), 190, 0.0)


def steps(L, pts, treads=()):
    """Companionway steps: varnished, non-slip treads with a lit nosing,
    stainless grab rails along both sides."""
    s = cabinetry(L, pts, (128, 100, 72), fiddle=False)
    x0, y0, x1, y1 = bbox(s)
    vertical_treads = (y1 - y0) >= (x1 - x0)
    for t in treads:
        if len(t) < 2:
            continue
        (ax, ay), (bx, by) = t[0], t[-1]
        L.line((ax, ay), (bx, by), 1.6, (84, 64, 46), 230, 0.0)          # the riser's shadow
        off = (1.6, 0) if vertical_treads else (0, 1.6)
        L.line((ax + off[0], ay + off[1]), (bx + off[0], by + off[1]), 0.6, (176, 146, 108), 200, 0.0)  # nosing
        for g in (3.5, 5.5):
            o = (g, 0) if vertical_treads else (0, g)
            L.line((ax + o[0], ay + o[1]), (bx + o[0], by + o[1]), 0.45, (64, 56, 50), 150, 0.0)  # non-slip grooves
    # Grab rails on the long sides.
    if vertical_treads:
        for y in (y0 + 1.6, y1 - 1.6):
            L.line((x0 + 2, y), (x1 - 2, y), 1.3, STEEL_DARK, 230, 0.0)
            L.line((x0 + 2, y - 0.4), (x1 - 2, y - 0.4), 0.4, STEEL_LIGHT, 220, 0.0)
    else:
        for x in (x0 + 1.6, x1 - 1.6):
            L.line((x, y0 + 2), (x, y1 - 2), 1.3, STEEL_DARK, 230, 0.0)
            L.line((x - 0.4, y0 + 2), (x - 0.4, y1 - 2), 0.4, STEEL_LIGHT, 220, 0.0)


def engine_box(L, pts):
    """The engine box under the steps: joinery with an insulated lift-off
    lid, two finger pulls."""
    s = cabinetry(L, pts, (96, 72, 52), fiddle=False)
    lid = inset(s, 3.0, 1.5)
    if lid:
        L.ink(lid, 0.6, (56, 42, 32), alpha=200, amp=0.0)
        x0, y0, x1, y1 = bbox(lid)
        cx = (x0 + x1) / 2
        for fy in (y0 + (y1 - y0) * 0.22, y1 - (y1 - y0) * 0.22):
            L.piece(L.rounded(cx - 2.5, fy - 1.2, 5, 2.4, 1.1), (40, 32, 26), 0.0, shade=False, shadow=False)


def settee(L, pts, centre=(0.0, 0.0)):
    """A saloon settee: varnished base, back cushions against the hull side
    (buttoned), seat cushions with piping, and the lee cloth tucked under the
    seat's front edge (a settee is a sea berth too)."""
    cabinetry(L, pts, VARNISH, fiddle=False)
    x0, y0, x1, y1 = bbox(pts)
    w, h = x1 - x0, y1 - y0
    along_x = w >= h
    length = w if along_x else h
    depth = h if along_x else w
    # Which side is outboard (against the hull): the far one from the centre.
    if along_x:
        out_neg = abs(y0 - centre[1]) > abs(y1 - centre[1])
    else:
        out_neg = abs(x0 - centre[0]) > abs(x1 - centre[0])
    back = depth * 0.3
    count = max(1, int(round(length / 72.0)))
    gap = 1.4
    piece = (length - 3 - gap * (count - 1)) / count

    def cushion(a, b, c0, c1, color, buttons=False):
        r = L.rounded(a, c0, b - a, c1 - c0, 2.6) if along_x else L.rounded(c0, a, c1 - c0, b - a, 2.6)
        L.shadow(r, (1.2, 1.8), 1.6, 80)
        L.fill(r, color, 0.04, grain=30.0)
        L.tone_edges(r, color, 2.2)
        pipe = inset(r, 1.1, 1.5)
        if pipe:
            L.ink(pipe, 0.45, lighter(color, 1.28), alpha=150, amp=0.0)   # piping
        L.ink(r, 0.8, (40, 50, 58), alpha=220, amp=0.0)
        if buttons:
            mid = (c0 + c1) / 2
            t = a + 7
            while t < b - 5:
                p = (t, mid) if along_x else (mid, t)
                L.circle(p, 0.7, darker(color, 0.65), 0.0, n=8, shadow=False)
                t += 12

    lo, hi = (y0, y1) if along_x else (x0, x1)
    base0 = x0 if along_x else y0
    if out_neg:
        back_span, seat_span = (lo + 1.5, lo + back), (lo + back + 0.8, hi - 2.6)
        front = hi - 1.6
    else:
        back_span, seat_span = (hi - back, hi - 1.5), (lo + 2.6, hi - back - 0.8)
        front = lo + 1.6
    for i in range(count):
        a = base0 + 1.5 + i * (piece + gap)
        cushion(a, a + piece, back_span[0], back_span[1], darker(CUSHION, 0.9), buttons=True)
        cushion(a, a + piece, seat_span[0], seat_span[1], CUSHION)
    # The lee cloth: pale canvas showing under the seat's front edge, its lanyard ends.
    a, b = base0 + 4, base0 + length - 4
    if along_x:
        L.line((a, front), (b, front), 1.2, CANVAS, 220, 0.0)
        for x in (a, b):
            L.line((x, front - 1), (x, front + 1), 0.6, (90, 84, 72), 200, 0.0)
    else:
        L.line((front, a), (front, b), 1.2, CANVAS, 220, 0.0)
        for y in (a, b):
            L.line((front - 1, y), (front + 1, y), 0.6, (90, 84, 72), 200, 0.0)


def berth(L, pts, pillows=(), single=False, vberth=False, centre=(0.0, 0.0)):
    """A made-up berth: a varnished base, a fitted mattress with piping and a
    pale sheet, a quilted duvet folded back, plump pillows; a bunk board and
    lee cloth on the open side of a single berth; the infill seam of a V-berth."""
    s = cabinetry(L, pts, VARNISH, fiddle=False)
    mattress = inset(s, 2.8, 3.0) or s
    L.fill(mattress, SHEET, 0.03)
    L.tone_edges(mattress, SHEET, 2.6)
    pipe = inset(mattress, 1.0, 2.0)
    if pipe:
        L.ink(pipe, 0.4, (236, 234, 228), alpha=150, amp=0.0)
    x0, y0, x1, y1 = bbox(mattress)
    pillow_boxes = [bbox(p) for p in pillows if p]
    px = sum((b[0] + b[2]) / 2 for b in pillow_boxes) / len(pillow_boxes) if pillow_boxes else None
    head_aft = px is not None and px < (x0 + x1) / 2
    if head_aft:
        a, b = x0 + (x1 - x0) * 0.36, x1 + 1
    else:
        a, b = x0 - 1, x0 + (x1 - x0) * 0.64
    clip = Polygon(mattress).intersection(Polygon([(a, y0 - 1), (b, y0 - 1), (b, y1 + 1), (a, y1 + 1)]))
    if not clip.is_empty and clip.geom_type == "Polygon":
        duvet = list(clip.exterior.coords)[:-1]
        L.shadow(duvet, (1, 2), 2, 60)
        L.fill(duvet, BLANKET, 0.05, grain=25.0)
        L.tone_edges(duvet, BLANKET, 3.0)
        # Quilting: stitch lines across the duvet.
        cx0, cy0, cx1, cy1 = bbox(duvet)
        x = cx0 + 10
        while x < cx1 - 4:
            seg = LineString([(x, cy0), (x, cy1)]).intersection(clip.buffer(-1.5))
            geom_line(L, seg, 0.4, darker(BLANKET, 0.78), 110)
            x += 12
        edge_x = a if head_aft else b
        L.line((edge_x, y0 + 3), (edge_x, y1 - 3), 2.4, (134, 146, 160), 210, 0.0)   # the sheet folded over
        L.ink(duvet, 0.7, (56, 66, 78), alpha=200, amp=0.0)
    for p in pillows:
        if not p:
            continue
        r = soft(p, 3.0)
        L.shadow(r, (1, 1.6), 1.6, 70)
        L.fill(r, PILLOW, 0.03)
        L.tone_edges(r, PILLOW, 2.4)
        bx0, by0, bx1, by1 = bbox(r)
        L.line(((bx0 + bx1) / 2, by0 + 3), ((bx0 + bx1) / 2 + 1, by1 - 3), 0.4, (180, 178, 170), 120, 0.0)
        L.ink(r, 0.6, alpha=170, amp=0.0)
    if vberth:
        # The infill cushion's seam along the centre line, aft of the pillows.
        L.line((x0 + 3, (y0 + y1) / 2), ((x0 + x1) / 2, (y0 + y1) / 2), 0.5, (150, 148, 140), 140, 0.0)
    if single:
        # A bunk board along the open side and a lee cloth rolled on it.
        bx0, by0, bx1, by1 = bbox(s)
        inboard_y = by0 if abs(by0 - centre[1]) < abs(by1 - centre[1]) else by1
        L.line((bx0 + 3, inboard_y), (bx1 - 3, inboard_y), 2.6, VARNISH_LIGHT, 240, 0.0)
        L.line((bx0 + 8, inboard_y + (1.8 if inboard_y == by0 else -1.8)), (bx1 - 8, inboard_y + (1.8 if inboard_y == by0 else -1.8)),
               1.4, CANVAS, 220, 0.0)
    L.ink(mattress, 0.7)


# =================================================================== equipment

def worktop(L, pts):
    """A galley counter: joinery with an inset solid-surface worktop and a
    fiddle all round."""
    s = cabinetry(L, pts, VARNISH, fiddle=False)
    top = inset(s, 2.6, 1.5)
    if top:
        L.fill(top, WORKTOP, 0.02)
        L.tone_edges(top, WORKTOP, 1.6)
        L.ink(top, 0.5, (120, 120, 114), alpha=170, amp=0.0)
    return s


def stove(L, burners):
    """A gimballed stainless stove: its top, pan supports over each burner,
    a stainless pot rail round it."""
    boxes = [bbox(b) for b in burners]
    x0 = min(b[0] for b in boxes) - 4
    y0 = min(b[1] for b in boxes) - 4
    x1 = max(b[2] for b in boxes) + 4
    y1 = max(b[3] for b in boxes) + 4
    top = L.rounded(x0, y0, x1 - x0, y1 - y0, 2)
    L.piece(top, (66, 70, 74), 0.7, shade=True, shadow=False)
    for (bx0, by0, bx1, by1) in boxes:
        c = ((bx0 + bx1) / 2, (by0 + by1) / 2)
        r = (bx1 - bx0) / 2
        L.circle(c, r, (30, 32, 34), 0.5, n=20, shadow=False)
        L.circle(c, r * 0.45, (58, 60, 62), 0.0, n=14, shadow=False)
        for ang in (45, 135):
            a = math.radians(ang)
            L.line((c[0] - r * math.cos(a), c[1] - r * math.sin(a)), (c[0] + r * math.cos(a), c[1] + r * math.sin(a)),
                   0.8, (20, 22, 24), 230, 0.0)
    rail = L.rounded(x0 - 1.5, y0 - 1.5, x1 - x0 + 3, y1 - y0 + 3, 2.5)
    L.ink(rail, 0.9, STEEL, alpha=230, amp=0.0)
    L.ink([(x + 0.3, y - 0.3) for x, y in rail], 0.3, STEEL_LIGHT, alpha=200, amp=0.0)


def sink(L, pts, centre=(0.0, 0.0)):
    """A deep stainless sink, its drain and a mixer tap on the hull side."""
    s = soft(pts, 2.5)
    L.fill(s, (168, 176, 178), 0.02)
    inner = inset(s, 1.6, 2.0) or s
    L.fill(inner, (122, 130, 134), 0.03)
    soft_shade(L, Polygon(inner).buffer(0).difference(Polygon(inner).buffer(-3.0)), Polygon(inner).buffer(0), 1.5, 120)
    x0, y0, x1, y1 = bbox(s)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    L.circle((cx, cy), 1.6, (70, 76, 80), 0.3, n=12, shadow=False)
    L.ink(s, 0.7, STEEL_DARK, alpha=220, amp=0.0)
    ty = y0 - 1.5 if abs(y0 - centre[1]) > abs(y1 - centre[1]) else y1 + 1.5
    L.circle((cx, ty), 1.6, STEEL, 0.4, n=12)
    L.line((cx, ty), (cx, cy + (ty - cy) * 0.35), 1.0, STEEL_LIGHT, 230, 0.0)


def fridge(L, pts):
    """A top-loading fridge lid in the worktop, with its seal and finger pull."""
    s = soft(pts, 2.0)
    L.fill(s, (222, 224, 220), 0.02)
    L.tone_edges(s, (222, 224, 220), 1.6)
    L.ink(s, 0.8, (110, 116, 118), alpha=220, amp=0.0)
    x0, y0, x1, y1 = bbox(s)
    L.piece(L.rounded((x0 + x1) / 2 - 4, y0 + 2.5, 8, 2.4, 1.0), (90, 96, 100), 0.0, shade=False, shadow=False)


def chart(L, pts):
    """A paper chart on the table: a coast, soundings, a pencilled course."""
    L.piece(pts, (226, 224, 212), 0.6, shadow=False)
    x0, y0, x1, y1 = bbox(pts)
    w, h = x1 - x0, y1 - y0
    coast = [(x0 + w * 0.08, y0 + h * 0.25), (x0 + w * 0.3, y0 + h * 0.18), (x0 + w * 0.45, y0 + h * 0.35),
             (x0 + w * 0.7, y0 + h * 0.22), (x0 + w * 0.92, y0 + h * 0.3)]
    L.ink(coast, 0.6, (150, 140, 110), closed=False, amp=0.0, alpha=200)
    for i in range(1, 4):
        L.line((x0 + 2, y0 + h * i / 4), (x1 - 2, y0 + h * i / 4), 0.25, (150, 170, 180), 90, 0.0)
    L.line((x0 + w * 0.15, y1 - h * 0.25), (x0 + w * 0.8, y0 + h * 0.45), 0.5, (176, 70, 60), 220, 0.0)


def instrument_panel(L, x0, y0, x1, y1):
    """The chart table's instrument panel: a plotter, a VHF, a switch panel."""
    w, h = x1 - x0, y1 - y0
    if w < 6 or h < 6:
        return
    L.piece(L.rounded(x0, y0, w, h, 1.5), PANEL, 0.6, shadow=True)
    horizontal = w >= h
    if horizontal:
        sw = min(w * 0.42, h * 1.5)
        L.fill(L.rounded(x0 + 1.5, y0 + 1.5, sw, h - 3, 1.0), SCREEN, 0.02)                  # plotter
        L.line((x0 + 3, y0 + h * 0.6), (x0 + sw * 0.8, y0 + h * 0.4), 0.4, (120, 190, 200), 200, 0.0)
        vx = x0 + sw + 3
        if vx + 6 < x1:
            L.fill(L.rect(vx, y0 + 1.6, min(8, x1 - vx - 2), h * 0.35), (90, 140, 96), 0.0)  # VHF display
        k = vx
        while k < x1 - 2:
            L.circle((k + 1, y1 - 2.2), 0.6, (200, 70, 50) if int(k) % 3 else (120, 200, 120), 0.0, n=8, shadow=False)
            k += 2.6
    else:
        sh = min(h * 0.42, w * 1.5)
        L.fill(L.rounded(x0 + 1.5, y0 + 1.5, w - 3, sh, 1.0), SCREEN, 0.02)
        L.line((x0 + w * 0.3, y0 + 3), (x0 + w * 0.6, y0 + sh * 0.8), 0.4, (120, 190, 200), 200, 0.0)
        vy = y0 + sh + 3
        if vy + 6 < y1:
            L.fill(L.rect(x0 + 1.6, vy, w * 0.35, min(8, y1 - vy - 2)), (90, 140, 96), 0.0)
        k = vy
        while k < y1 - 2:
            L.circle((x1 - 2.2, k + 1), 0.6, (200, 70, 50) if int(k) % 3 else (120, 200, 120), 0.0, n=8, shadow=False)
            k += 2.6


def nav_station(L, pts, chart_pts=None, instruments=None, centre=(0.0, 0.0)):
    """A chart table: joinery with a hinged lid (hinge along the hull side),
    the chart on it, and the instrument panel: the scene's own Instruments
    shape when it has one, otherwise the end of the table the chart leaves free."""
    s = cabinetry(L, pts, VARNISH, fiddle=True)
    x0, y0, x1, y1 = bbox(s)
    hinge_y = y0 + 2.5 if abs(y0 - centre[1]) > abs(y1 - centre[1]) else y1 - 2.5
    L.line((x0 + 3, hinge_y), (x1 - 3, hinge_y), 0.6, (60, 46, 34), 200, 0.0)
    if chart_pts:
        chart(L, chart_pts)
    if instruments:
        ix0, iy0, ix1, iy1 = bbox(instruments)
        instrument_panel(L, ix0, iy0, ix1, iy1)
    elif chart_pts:
        cx0, cy0, cx1, cy1 = bbox(chart_pts)
        left, right = cx0 - x0, x1 - cx1
        if max(left, right) >= 10:
            if right >= left:
                instrument_panel(L, cx1 + 2.5, y0 + 3.5, x1 - 3, y1 - 3.5)
            else:
                instrument_panel(L, x0 + 3, y0 + 3.5, cx0 - 2.5, y1 - 3.5)


def mast_post(L, pts):
    """The keel-stepped mast's compression post: brushed aluminium, a collar."""
    x0, y0, x1, y1 = bbox(pts)
    c = ((x0 + x1) / 2, (y0 + y1) / 2)
    r = (x1 - x0) / 2
    L.circle(c, r, (168, 174, 176), 0.9, n=24)
    L.circle(c, r * 0.7, (190, 196, 198), 0.0, n=20, shadow=False)
    L.circle((c[0] - r * 0.3, c[1] - r * 0.3), r * 0.22, (226, 230, 230), 0.0, n=12, shadow=False)


def round_seat(L, pts):
    x0, y0, x1, y1 = bbox(pts)
    c = ((x0 + x1) / 2, (y0 + y1) / 2)
    r = (x1 - x0) / 2
    L.circle(c, r, VARNISH, 0.8, n=24)
    L.circle(c, r * 0.78, CUSHION, 0.6, n=22, shadow=False)


def heads_unit(L, pts):
    """A moulded GRP heads compartment."""
    s = soft(pts, 3.0)
    L.shadow(s, (3, 4.5), 4.0, 90)
    L.fill(s, GRP, 0.02)
    L.tone_edges(s, GRP, 2.6)
    L.ink(s, 1.0)


def toilet(L, pts):
    """A marine toilet: bowl, seat, and the pump handle beside it."""
    x0, y0, x1, y1 = bbox(pts)
    c = ((x0 + x1) / 2, (y0 + y1) / 2)
    rx, ry = (x1 - x0) / 2, (y1 - y0) / 2
    oval = [(c[0] + rx * math.cos(t), c[1] + ry * math.sin(t)) for t in np.linspace(0, 2 * math.pi, 24, endpoint=False)]
    L.piece(oval, (232, 232, 228), 0.7)
    inner = [(c[0] + rx * 0.62 * math.cos(t), c[1] + ry * 0.62 * math.sin(t)) for t in np.linspace(0, 2 * math.pi, 20, endpoint=False)]
    L.fill(inner, (196, 204, 206), 0.02)
    L.ink(inner, 0.4, alpha=140, amp=0.0)
    L.line((x1 + 1.5, c[1] - ry * 0.2), (x1 + 5, c[1] - ry * 0.7), 1.0, STEEL_DARK, 230, 0.0)


def basin(L, pts):
    s = soft(pts, 4.0)
    L.piece(s, (230, 230, 226), 0.6, shadow=False)
    inner = inset(s, 2.0, 3.0)
    if inner:
        L.fill(inner, (198, 206, 208), 0.02)
    x0, y0, x1, y1 = bbox(s)
    L.circle(((x0 + x1) / 2, (y0 + y1) / 2), 0.9, STEEL_DARK, 0.0, n=10, shadow=False)


def shower_tray(L, pts):
    """A shower tray with a teak grating."""
    s = soft(pts, 2.5)
    L.fill(s, (196, 200, 198), 0.02)
    L.ink(s, 0.8)
    grate = inset(s, 3.0, 1.0)
    if not grate:
        return
    L.fill(grate, (132, 108, 82), 0.05)
    x0, y0, x1, y1 = bbox(grate)
    horizontal = (x1 - x0) >= (y1 - y0)
    k = (y0 if horizontal else x0) + 2.4
    while k < (y1 if horizontal else x1) - 1:
        if horizontal:
            L.line((x0 + 0.5, k), (x1 - 0.5, k), 0.7, (70, 56, 42), 210, 0.0)
        else:
            L.line((k, y0 + 0.5), (k, y1 - 0.5), 0.7, (70, 56, 42), 210, 0.0)
        k += 3.0
    L.ink(grate, 0.5, (70, 56, 42), alpha=200, amp=0.0)


def drain(L, pts):
    x0, y0, x1, y1 = bbox(pts)
    L.circle(((x0 + x1) / 2, (y0 + y1) / 2), (x1 - x0) / 2, STEEL, 0.4, n=12, shadow=False)


def glass_door(L, pts):
    """A sliding glass door (the catamaran's saloon): smoked acrylic in a frame."""
    L.fill(pts, SEAGLASS, 0.06, alpha=210)
    L.ink(pts, 1.0, STEEL_DARK, alpha=220, amp=0.0)
