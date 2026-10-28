"""Paints a vessel's illustrated art profile from its own art scenes (0.100b).

Usage: python3 tools/vessels/paint_illustrated_vessel.py <vessel_id> [deck] [cabin]

For halcyon_40 (Clam 40), petrel_36 (Frogleap 36) and arctic_wanderer_26 (Arctic
Wanderer 26). The Wing 33 (starling_33) keeps its own painter,
paint_illustrated_starling.py, which shares the same toolkit.

Every shape of src/vessels/<id>/deck_visual.tscn and cabin_visual.tscn is
repainted in the illustrated style, chosen by the shape's palette colour
(those scenes use one small palette): cream hulls with ink outlines; marine
teak decks (margin boards, curved and fore-and-aft strips, caulking) with the
coachroof, cockpits, nets and hatches cut out; teak-and-holly cockpit soles;
trampolines as rope nets; planked furniture; plump cushions; made-up berths;
glass, metal and tiles. Then a few cozy details per boat (EXTRAS). Because
the shapes come from the scenes that also hold the layout, the art lines up
with the unchanged collision and stations.

Writes full-canvas PNGs (2 px per unit) to assets/vessels/<id>/illustrated/.
Shadow, rigging, mast and sails stay procedural. Requires Pillow, numpy and
shapely.
"""
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from illustrate import *  # noqa: E402,F403
from illustrate import ROOT, Layer, nonskid_deck, teak_deck, teak_sole, topsides  # noqa: E402
from shapely.geometry import Polygon  # noqa: E402

DECK_SLOTS = {"HullBase": "hull_base", "DeckBase": "deck_base", "Coachroof": "coachroof", "DeckDetails": "deck_details"}
CABIN_SLOTS = {"CabinBase": "cabin_base", "FurnitureVisual": "furniture", "CabinDetails": "cabin_details"}

# Palette of the generated scenes (rounded RGB) -> material.
MATERIALS = {
    (239, 229, 204): "cream",
    (212, 204, 180): "deck",
    (180, 171, 147): "sole",
    (138, 106, 74): "teak",
    (94, 71, 51): "darkwood",
    (110, 84, 64): "wood",
    (122, 92, 64): "steps",
    (63, 120, 128): "teal",
    (168, 180, 160): "berth",
    (166, 196, 201): "glass",
    (94, 100, 104): "metal",
    (61, 63, 65): "metal_dark",
    (185, 193, 197): "metal",
    (201, 210, 214): "metal_light",
    (22, 50, 64): "interior",
    (154, 122, 87): "cabin_sole",
    (122, 138, 143): "tile",
    (143, 163, 168): "tile_light",
    (42, 47, 51): "stove",
    (46, 74, 82): "net",
    (201, 209, 190): "fold",
    (75, 83, 87): "metal_dark",
    (75, 85, 87): "metal_dark",
    (16, 45, 59): "ink",
    (74, 54, 38): "darkwood",
    (46, 90, 96): "teal_dark",
}


def rgb(c):
    return tuple(int(round(float(x) * 255)) for x in c[:3])


def parse_nodes(path):
    """Node path -> {"type", "polygon", "points", "position", "size", "color", "width"} in scene order."""
    nodes, order, cur = {}, [], None
    for line in open(path):
        m = re.match(r'\[node name="([^"]+)"(?: type="([^"]+)")?(?:.*parent="([^"]*)")?', line)
        if m:
            parent = m.group(3) or ""
            cur = (parent + "/" if parent not in ("", ".") else "") + m.group(1)
            nodes[cur] = {"type": m.group(2) or "", "parent": parent}
            order.append(cur)
            continue
        if cur is None:
            continue
        m = re.match(r"(polygon|points) = PackedVector2Array\(([^)]*)\)", line)
        if m:
            v = [float(x) for x in m.group(2).split(",") if x.strip()]
            nodes[cur][m.group(1)] = list(zip(v[::2], v[1::2]))
        m = re.match(r"(position|size) = Vector2\(([-\d.e]+), ([-\d.e]+)\)", line)
        if m:
            nodes[cur][m.group(1)] = (float(m.group(2)), float(m.group(3)))
        m = re.match(r"(fill_color|color|default_color) = Color\(([^)]*)\)", line)
        if m:
            nodes[cur]["color"] = [float(x) for x in m.group(2).split(",")]
        m = re.match(r"width = ([\d.]+)", line)
        if m:
            nodes[cur]["width"] = float(m.group(1))
        m = re.match(r"script = ExtResource", line)
        if m:
            nodes[cur]["script"] = True
    return nodes, order


def offset_of(nodes, name):
    x = y = 0.0
    while name:
        n = nodes.get(name)
        if n is None:
            break
        px, py = n.get("position", (0.0, 0.0))
        x, y = x + px, y + py
        name = n["parent"] if n["parent"] not in (".", "") else ""
        if name in ("", "."):
            break
    return x, y


def outline(nodes, name):
    n = nodes[name]
    ox, oy = offset_of(nodes, name)
    if "polygon" in n:
        return [(x + ox, y + oy) for x, y in n["polygon"]]
    if "size" in n:
        w, h = n["size"]
        return [(ox - w / 2, oy - h / 2), (ox + w / 2, oy - h / 2), (ox + w / 2, oy + h / 2), (ox - w / 2, oy + h / 2)]
    return None


def line_points(nodes, name):
    n = nodes[name]
    ox, oy = offset_of(nodes, n["parent"]) if n["parent"] not in ("", ".") else (0.0, 0.0)
    px, py = n.get("position", (0.0, 0.0))
    return [(x + ox + px, y + oy + py) for x, y in n.get("points", [])]


def material(n):
    c = n.get("color")
    if not c:
        return "wood"
    key = rgb(c)
    if key in MATERIALS:
        return MATERIALS[key]
    best = min(MATERIALS, key=lambda k: sum((a - b) ** 2 for a, b in zip(k, key)))
    return MATERIALS[best]


def slot_children(order, slot):
    return [p for p in order if p.startswith(slot + "/")]


# ------------------------------------------------------------------ painting

def paint_shape(L, nodes, name, holes_for_deck, king=None):
    """Real Horizon materials: fibreglass hulls, roofs and decks with grey
    non-skid, weathered teak in the cockpit, brushed steel, smoked acrylic,
    varnished marine timber and fitted upholstery below."""
    n = nodes[name]
    if n["type"] == "Label" or "/Labels" in name:
        return
    mat = material(n)
    alpha = n.get("color", [0, 0, 0, 1])[3] if n.get("color") and len(n["color"]) > 3 else 1.0
    if n["type"] == "Line2D":
        pts = line_points(nodes, name)
        if len(pts) < 2:
            return
        width = n.get("width", 2.0)
        if "ToeRail" in name:
            L.ink(pts, max(width * 0.55, 1.6), STEEL, closed=False, amp=0.0, alpha=235)
            L.ink(pts, 0.5, STEEL_LIGHT, closed=False, amp=0.0, alpha=180)
        elif mat in ("teak", "darkwood"):
            L.ink(pts, width * 0.6, TEAK if mat == "teak" else TEAK_DARK, closed=False, amp=0.0, alpha=255)
            L.ink(pts, 0.6, INK, closed=False, amp=0.0, alpha=150)
        elif mat in ("metal_light", "metal"):
            # Lifelines and pulpits: stainless tube with a highlight.
            L.ink(pts, max(width * 0.45, 0.9), STEEL_DARK, closed=False, amp=0.0, alpha=int(230 * min(alpha + 0.2, 1)))
            L.ink(pts, max(width * 0.2, 0.4), STEEL_LIGHT, closed=False, amp=0.0, alpha=int(230 * min(alpha + 0.2, 1)))
        elif mat == "glass" or mat == "teal":
            L.ink(pts, width * 0.55, SEAGLASS, closed=False, amp=0.0, alpha=230)
            L.ink(pts, 0.5, (190, 204, 208), closed=False, amp=0.0, alpha=110)
        elif mat == "ink":
            L.ink(pts, width * 0.5, INK, closed=False, amp=0.0, alpha=int(255 * alpha))
        else:
            L.ink(pts, max(width * 0.5, 0.7), INK, closed=False, amp=0.0, alpha=int(180 * alpha))
        return
    pts = outline(nodes, name)
    if not pts or len(pts) < 3:
        return
    if mat == "cream":
        if "Hull" in name or "Aka" in name or "Ama" in name or "Bridgedeck" in name:
            if "Bridgedeck" in name or "Aka" in name:
                nonskid_deck(L, pts, margin=6.0)
            else:
                topsides(L, pts)
        else:
            # Coachroof and other mouldings: smooth gelcoat, lit and shaded.
            L.shadow(pts, (5, 7), 5, 80)
            L.fill(pts, CREAM, 0.03, grain=80.0)
            L.tone_edges(pts, CREAM, 3.5)
            L.ink(pts, 1.4)
    elif mat == "deck":
        holes = [h for h in holes_for_deck if Polygon(h).intersects(Polygon(pts))]
        nonskid_deck(L, pts, holes=holes)
    elif mat == "sole":
        if "Locker" in name or "Hatch" in name:
            L.piece(pts, CREAM, 1.2)
            L.speckle(pts, tuple(int(c * 0.85) for c in CREAM), density=0.3)
        else:
            L.shadow(pts, (3, 4), 3, 70)
            teak_sole(L, pts)
    elif mat == "teak":
        L.shadow(pts, (3, 4), 3, 70)
        teak_deck(L, pts, strip=4.0, margin=3.5, sprung=0)
    elif mat in ("wood", "darkwood", "steps"):
        color = {"wood": TEAK_DARK, "darkwood": (88, 74, 61), "steps": TEAK}[mat]
        L.joinery(pts, color)
    elif mat in ("teal", "teal_dark"):
        if alpha < 0.95:  # glass in a tint (sliding doors, windows)
            L.fill(pts, SEAGLASS, 0.06, alpha=int(255 * max(alpha, 0.7)))
            L.ink(pts, 1.0)
            return
        cushions(L, pts)
    elif mat == "berth":
        pillows = [outline(nodes, c) for c in nodes if c.startswith(name + "/") and "Pillow" in c]
        px = [x for o in pillows if o for x, _ in o]
        berth(L, pts, sum(px) / len(px) if px else None)
    elif mat == "fold":
        L.fill(pts, (214, 216, 210), 0.03)
        L.ink(pts, 0.8, alpha=140)
    elif mat == "glass":
        L.fill(pts, SEAGLASS if "Window" in name or "Portlight" in name else (120, 140, 148), 0.05, alpha=int(255 * max(alpha, 0.75)))
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        # Sky reflected in the acrylic: a pale diagonal sheen.
        L.line((min(xs) + 3, min(ys) + 3), (min(xs) + (max(xs) - min(xs)) * 0.5, min(ys) + 3), 0.7, (200, 214, 218), 120)
        L.ink(pts, 1.4, STEEL_DARK, alpha=200, amp=0.0)
    elif mat in ("metal", "metal_dark", "metal_light"):
        color = {"metal": STEEL, "metal_dark": STEEL_DARK, "metal_light": STEEL_LIGHT}[mat]
        L.piece(pts, color, 1.0)
    elif mat == "interior":
        # The hull's inside: dark timber ceiling strips against the topsides.
        L.fill(pts, (64, 56, 48), 0.05, alpha=int(255 * alpha))
        L.ink(pts, 2.0, (40, 36, 32), alpha=int(235 * alpha), amp=0.0)
    elif mat == "cabin_sole":
        L.shadow(pts, (0, 0), 6, 120)
        teak_sole(L, pts, strip=11.0, color=HONEY, holly_alpha=70)
        L.grain(pts, (96, 78, 60), True, spacing=3.0, alpha=30)
    elif mat in ("tile", "tile_light"):
        # Galley worktop: solid-surface, pale grey.
        L.fill(pts, (198, 200, 196) if mat == "tile" else (212, 214, 210), 0.02)
        L.tone_edges(pts, (198, 200, 196), 2.0)
        L.ink(pts, 1.1)
    elif mat == "stove":
        L.piece(pts, (44, 48, 52), 0.9, shade=False, shadow=False)
    elif mat == "net":
        paint_net(L, pts)
    elif mat == "ink":
        L.fill(pts, INK, 0.0, alpha=int(255 * alpha))


def paint_net(L, pts):
    """A trampoline or safety net: dark mesh over the water, a rope border."""
    L.fill(pts, (30, 44, 52), 0.04, alpha=170)
    L.hatch(pts, spacing=7.0, width=0.45, alpha=120, angle=0.0, color=(120, 130, 132))
    L.hatch(pts, spacing=7.0, width=0.45, alpha=120, angle=90.0, color=(120, 130, 132))
    L.ink(pts, 2.0, (150, 154, 150), alpha=230, amp=0.0)
    L.ink(pts, 0.8, INK, alpha=160)


def cushions(L, pts):
    """A settee: a timber base with fitted upholstery and piping."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    L.joinery(pts, TEAK_DARK)
    along_x = (x1 - x0) >= (y1 - y0)
    length = (x1 - x0) if along_x else (y1 - y0)
    count = max(1, int(round(length / 80.0)))
    gap = 1.5
    for i in range(count):
        if along_x:
            a = x0 + gap + i * (length - gap) / count
            r = L.rounded(a, y0 + 2.5, (length - gap) / count - gap, (y1 - y0) - 5, 3)
        else:
            a = y0 + gap + i * (length - gap) / count
            r = L.rounded(x0 + 2.5, a, (x1 - x0) - 5, (length - gap) / count - gap, 3)
        L.shadow(r, (1.5, 2), 1.5, 70)
        L.fill(r, CUSHION, 0.04, grain=30.0)
        L.tone_edges(r, CUSHION, 2.2)
        L.ink(r, 0.9, (46, 56, 64), alpha=220, amp=0.0)


def berth(L, pts, pillow_x=None):
    """A made-up berth: a fitted mattress with a pale sheet and a folded
    duvet in muted blue over the part away from the pillows."""
    L.joinery(pts, TEAK_DARK)
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    sx = 1 - 6 / max(1.0, max(xs) - min(xs))
    sy = 1 - 6 / max(1.0, max(ys) - min(ys))
    mattress = [(cx + (x - cx) * sx, cy + (y - cy) * sy) for x, y in pts]
    L.fill(mattress, (214, 214, 208), 0.03)
    L.tone_edges(mattress, (214, 214, 208), 2.5)
    x0, x1 = min(xs), max(xs)
    if pillow_x is not None and pillow_x < (x0 + x1) / 2:
        a, b = x0 + (x1 - x0) * 0.4, x1 + 1  # pillows aft: the duvet forward
    else:
        a, b = x0 - 1, x0 + (x1 - x0) * 0.6
    clip = Polygon(mattress).intersection(Polygon([(a, min(ys) - 1), (b, min(ys) - 1), (b, max(ys) + 1), (a, max(ys) + 1)]))
    if not clip.is_empty and clip.geom_type == "Polygon":
        bl = list(clip.exterior.coords)[:-1]
        L.shadow(bl, (1, 2), 2, 60)
        L.fill(bl, BLANKET, 0.05, grain=25.0)
        L.tone_edges(bl, BLANKET, 3.0)
        # A folded-back edge: a lighter band.
        edge_x = a if pillow_x is not None and pillow_x < (x0 + x1) / 2 else b
        L.line((edge_x, min(ys) + 4), (edge_x, max(ys) - 4), 2.0, (130, 142, 156), 200, 0.0)
        L.ink(bl, 0.8, (60, 70, 82), alpha=200, amp=0.0)
    L.ink(mattress, 0.8)


def illustrate(vessel, area):
    path = os.path.join(ROOT, "src/vessels/%s/%s_visual.tscn" % (vessel, area))
    nodes, order = parse_nodes(path)
    canvas_line = re.search(r"canvas = Rect2\(([^)]*)\)", open(path).read())
    canvas = tuple(int(float(x)) for x in canvas_line.group(1).split(","))
    slots = DECK_SLOTS if area == "deck" else CABIN_SLOTS
    out = os.path.join(ROOT, "assets", "vessels", vessel, "illustrated", area)
    holes = []
    for name in order:
        n = nodes[name]
        if name.startswith("Coachroof/") and name.count("/") == 1 and material(n) in ("cream",) and n["type"] != "Line2D":
            o = outline(nodes, name)
            if o and len(o) >= 3:
                holes.append(o)
        if name.startswith("DeckBase/") and material(n) in ("sole", "net") and n["type"] != "Line2D":
            o = outline(nodes, name)
            if o and len(o) >= 3:
                holes.append(o)
    roof_front = max((x for h in holes for x, _ in h), default=None)
    # Nets drawn only as lines in the scene (the trimaran's): one net per
    # group of NetLine<g><n> lines, over their outline.
    net_groups = {}
    for name in order:
        m = re.match(r"DeckBase/NetLine(\d)\d+$", name)
        if m:
            net_groups.setdefault(m.group(1), []).extend(line_points(nodes, name))
    king = KING.get(vessel)
    for i, (slot, file_name) in enumerate(slots.items()):
        L = Layer(100 + i, canvas)
        for name in slot_children(order, slot):
            if nodes[name]["type"] == "Label" or "/Labels" in name:
                continue
            if any(seg.startswith("Net") and seg[3:].isdigit() or seg.startswith("NetLine") or seg.startswith("NetCross")
                   for seg in name.split("/")[1:]):
                continue  # the procedural net lines: the net is painted by its polygon
            paint_shape(L, nodes, name, holes, king=(lambda pts, k=king: k(pts, roof_front)) if king else None)
        if slot == "DeckBase":
            for pts in net_groups.values():
                hull = Polygon(pts).convex_hull if len(pts) >= 3 else None
                if hull is not None and hull.geom_type == "Polygon":
                    paint_net(L, list(hull.exterior.coords)[:-1])
        extra = EXTRAS.get((vessel, slot))
        if extra:
            extra(L)
        L.save(os.path.join(out, file_name + ".png"))


# ------------------------------------------------------------------ boat by boat

def _king_monohull(pts, roof_front):
    """A king plank on a single hull's foredeck, from the coachroof to near the bow."""
    xs = [p[0] for p in pts]
    if roof_front is None or max(xs) - roof_front < 80:
        return None
    return (roof_front + 6, max(xs) - 30)


KING = {"petrel_36": _king_monohull, "arctic_wanderer_26": _king_monohull}


def fender(L, x, y, length=26, width=13, horizontal=False):
    """A white fender with its line, hung over the side."""
    if horizontal:
        L.line((x - length / 2 - 8, y), (x - length / 2, y), 0.6, ROPE, 220)
        r = L.rounded(x - length / 2, y - width / 2, length, width, width / 2 - 0.5)
    else:
        L.line((x, y - length / 2 - 8), (x, y - length / 2), 0.6, ROPE, 220)
        r = L.rounded(x - width / 2, y - length / 2, width, length, width / 2 - 0.5)
    L.shadow(r, (2, 3), 2, 70)
    L.fill(r, (226, 228, 224), 0.02)
    L.tone_edges(r, (226, 228, 224), 3.0)
    L.ink(r, 0.9)


def winch_handle(L, x, y, angle=0.4):
    c, s_ = math.cos(angle), math.sin(angle)
    L.line((x, y), (x + 16 * c, y + 16 * s_), 1.6, (58, 62, 66), 255, 0.0)
    L.circle((x + 16 * c, y + 16 * s_), 2.2, (40, 42, 44), 0.6, n=10, shadow=False)


def grab_bag(L, x, y, w=22, h=14):
    """The orange grab bag every passage-maker keeps by the companionway."""
    r = L.rounded(x, y, w, h, 3)
    L.piece(r, (196, 104, 52), 0.9)
    L.line((x + 3, y + h / 2), (x + w - 3, y + h / 2), 0.6, (60, 62, 64), 160, 0.0)


def mug(L, x, y, color=(222, 222, 216)):
    L.circle((x, y), 4.2, color, 0.8, n=14)
    L.circle((x, y), 2.8, (70, 56, 44), 0.0, n=12, shadow=False)


def book_row(L, x, y, n=4, vertical=False):
    colors = ((96, 108, 120), (132, 120, 98), (80, 92, 84), (150, 146, 136), (108, 82, 74))
    for i in range(n):
        if vertical:
            L.piece(L.rect(x, y + i * 7, 12, 6), colors[i % len(colors)], 0.6, shadow=False)
        else:
            L.piece(L.rect(x + i * 7, y, 6, 12), colors[i % len(colors)], 0.6, shadow=False)


def _halcyon_deck(L):
    # Sheets coiled by the winches, cockpit cushions, fenders ready on the side.
    L.coil((-252, -112), 10)
    L.coil((-252, 112), 10, color=(160, 166, 172))
    winch_handle(L, -262, -96)
    for y in (-100, 30):
        r = L.rounded(-380, y, 22, 60, 3)
        L.piece(r, CUSHION, 0.9)
    grab_bag(L, -330, 96)
    for x in (-300, -40, 220):                                   # fenders, harbour side
        fender(L, x, 297)


def _halcyon_roof(L):
    # A sail bag lashed on the coachroof and a halyard coil at the mast.
    bag = L.rounded(-70, -152, 70, 22, 8)
    L.piece(bag, CANVAS_GREY, 1.0)
    L.line((-50, -152), (-50, -130), 0.6, ROPE, 200, 0.0)
    L.line((-20, -152), (-20, -130), 0.6, ROPE, 200, 0.0)
    L.coil((60, 120), 12)


def _halcyon_details(L):
    # The saloon of a well-run cruising boat: pilot books, mugs, binoculars, a lamp.
    book_row(L, -232, -298, 5)
    L.circle((-30, 60), 8, STEEL, 1.0)                              # kettle
    L.line((-24, 54), (-18, 50), 1.0, STEEL_DARK, 220, 0.0)
    mug(L, -70, 80)
    mug(L, -10, 84, (96, 110, 124))
    L.piece(L.rounded(30, -48, 24, 14, 4), (50, 54, 58), 0.8)      # binoculars
    L.piece(L.rect(-46, 10, 26, 18), (226, 226, 216), 0.7, shadow=False)  # a chart folded on the table
    L.circle((-330, -280), 5, (208, 196, 160), 0.9, n=14)           # reading lamp


def _petrel_deck(L):
    L.coil((-182, -48), 9)
    L.coil((-182, 48), 9, color=(160, 166, 172))
    winch_handle(L, -190, -36)
    L.piece(L.rounded(-360, -84, 50, 18, 3), CUSHION, 0.9)
    for x in (-250, 60):                                          # fenders on the starboard float
        fender(L, x, 288)


def _petrel_details(L):
    L.circle((-10, -4), 7, STEEL, 1.0)                            # kettle on the table
    mug(L, 24, 6)
    book_row(L, 140, 84, 3)
    L.piece(L.rounded(112, -66, 22, 12, 4), (50, 54, 58), 0.8)     # binoculars
    L.circle((250, -38), 4.5, (208, 196, 160), 0.9, n=14)


def _wanderer_deck(L):
    # A small, practical boat: tiller, a couple of coiled sheets, a bucket, fenders.
    L.coil((-215, -52), 8)
    L.coil((-215, 52), 8, color=(160, 166, 172))
    winch_handle(L, -222, -40)
    L.circle((-318, 38), 5, (86, 98, 108), 0.8, n=14)             # a bucket
    for x in (-220, 40):
        fender(L, x, 145, 22, 12)


def _wanderer_roof(L):
    L.coil((40, -44), 9)


def _wanderer_details(L):
    L.circle((26, -4), 6, STEEL, 0.9)                              # kettle on the little table
    mug(L, 54, 6)
    book_row(L, 146, 87, 3)                                         # pilot books on the shelf
    L.piece(L.rounded(-170, -64, 8, 16, 2), (150, 156, 150), 0.6, shadow=False)  # tea towel
    L.piece(L.rounded(90, -20, 7, 16, 2), (40, 44, 48), 0.6, shadow=False)        # handheld VHF


EXTRAS = {
    ("halcyon_40", "DeckBase"): _halcyon_deck,
    ("halcyon_40", "Coachroof"): _halcyon_roof,
    ("halcyon_40", "CabinDetails"): _halcyon_details,
    ("petrel_36", "DeckBase"): _petrel_deck,
    ("petrel_36", "CabinDetails"): _petrel_details,
    ("arctic_wanderer_26", "DeckBase"): _wanderer_deck,
    ("arctic_wanderer_26", "Coachroof"): _wanderer_roof,
    ("arctic_wanderer_26", "CabinDetails"): _wanderer_details,
}


if __name__ == "__main__":
    vessel = sys.argv[1]
    areas = sys.argv[2:] or ["deck", "cabin"]
    for area in areas:
        illustrate(vessel, area)
