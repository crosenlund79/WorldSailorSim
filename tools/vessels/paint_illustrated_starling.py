"""Paints the Starling 33's illustrated art-direction prototype (Visual Identity V01).

Usage: python3 tools/vessels/paint_illustrated_starling.py

Writes full-canvas PNG layers (2 px per scene unit, transparent elsewhere) to
assets/vessels/starling_33/illustrated/deck/ and .../cabin/, the slots of
data/vessels/starling_33_visuals_illustrated.tres. Every shape is taken from the
boat's own scenes (deck_visual.tscn, cabin_visual.tscn, cabin.tscn), so the art
lines up with the unchanged collision and stations.

The style follows the written art direction: slightly uneven dark-ink outlines,
warm muted colour washes with soft variation, plank and grain texture, light
hatching for shade (light from the upper left), small lived-in details. It is a
prototype for the owner to judge. These are generated stand-ins: the owner's
own drawings can replace any layer by saving a PNG with the same name.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from illustrate import *  # noqa: E402,F403
from illustrate import ROOT, nonskid_deck, topsides  # noqa: E402
from paint_illustrated_vessel import berth, cushions, fender, grab_bag, mug, book_row, winch_handle  # noqa: E402

OUT = os.path.join(ROOT, "assets", "vessels", "starling_33", "illustrated")
CANVAS = (-560, -200, 1120, 400)


def roof_front(roof):
    """The forward end of the coachroof (x)."""
    return max(x for x, _ in roof)


# =============================================================== deck
def paint_deck():
    v = parse(os.path.join(ROOT, "src/vessels/starling_33/deck_visual.tscn"))
    hull = shape(v, "HullBase/Hull")
    deck = shape(v, "DeckBase/DeckSurface")
    toe = v["HullBase/ToeRail"]["points"]

    # Hull: the cream topsides seen from above (a rim around the deck) and a
    # teak toe rail along the sheer.
    L = Layer(1, CANVAS)
    topsides(L, hull)
    # A teak toe rail along the sheer (the Wing 33's one traditional touch).
    L.ink(toe, 2.6, TEAK, closed=False, amp=0.0, alpha=255)
    L.ink(toe, 0.5, TEAK_DARK, closed=False, amp=0.0, alpha=160)
    L.save(os.path.join(OUT, "deck", "hull_base.png"))

    # Deck: marine teak (0.100b). Margin boards along the sheer, strips
    # sprung along the curve near the edge, fore-and-aft strips inside, a king
    # plank on the foredeck; the coachroof and cockpit are cut out with their
    # own margins. A teak-and-holly cockpit sole and teak benches.
    D = Layer(2, CANVAS)
    roof = shape(v, "Coachroof/Coachroof")
    cockpit = shape(v, "DeckBase/CockpitWell")
    D.shadow(deck, (2, 3), 3, 60)
    nonskid_deck(D, deck, holes=[roof, cockpit])
    D.shadow(cockpit, (3, 4), 3, 80)
    teak_sole(D, cockpit)
    for name in ("DeckBase/BenchPort", "DeckBase/BenchStarboard"):
        teak_deck(D, shape(v, name), strip=4.0, margin=3.5, sprung=0)
    # A cockpit cushion on the port bench: somewhere to sit at anchor.
    D.piece(D.rounded(-440, -96, 100, 22, 3), CUSHION, 0.9)
    D.line((-390, -94), (-390, -76), 0.5, INK, 90)
    hatch = shape(v, "DeckBase/Hatch")
    D.piece(hatch, CREAM, 1.2)
    D.fill(D.rounded(-232, -28, 46, 56, 3), SEAGLASS, 0.05)          # smoked acrylic sliding hatch
    D.save(os.path.join(OUT, "deck", "deck_base.png"))

    # Coachroof: cream roof with soft shade, sea-glass portlights, fore hatch.
    C = Layer(3, CANVAS)
    roof = shape(v, "Coachroof/Coachroof")
    C.shadow(roof, (7, 9), 6, 90)
    C.fill(roof, CREAM, 0.03, grain=80.0)
    C.tone_edges(roof, CREAM, 4.0)
    inner = [(x * 0.94 - 6, y * 0.82) for x, y in roof]
    C.speckle(inner, tuple(int(c * 0.86) for c in CREAM), density=0.28)     # non-skid panel on the roof
    C.ink(roof, 1.4)
    for i in range(4):
        n = v["Coachroof/Coachroof/Portlight%d" % i]
        pl = [(x - 55, y) for x, y in n["polygon"]]
        C.fill(pl, SEAGLASS, 0.05)
        C.line((pl[0][0] + 6, pl[0][1] + 4), (pl[1][0] - 14, pl[1][1] + 4), 0.6, (190, 204, 208), 120)
        C.ink(pl, 1.2, STEEL_DARK, alpha=200, amp=0.0)
    fore = [(x - 55, y) for x, y in v["Coachroof/Coachroof/ForeHatch"]["polygon"]]
    C.piece(fore, SEAGLASS, 1.3, shadow=False)
    C.line((fore[0][0] + 4, fore[0][1] + 4), (fore[0][0] + 20, fore[0][1] + 4), 0.6, (190, 204, 208), 120)
    # Grab rails and a few lived-in things on the roof.
    for sy in (-1, 1):
        C.piece(C.rounded(-180, sy * 82 - 3, 150, 6, 2), STEEL, 0.7, shadow=False)
    C.coil((40, -72), 13)
    # The sprayhood folded down over the companionway, in charcoal canvas.
    hood = C.rounded(-262, -70, 30, 140, 6)
    C.shadow(hood, (3, 4), 3, 80)
    C.fill(hood, CANVAS_GREY, 0.04)
    C.tone_edges(hood, CANVAS_GREY, 3.0)
    for k in range(1, 4):
        C.line((-262 + k * 7.5, -66), (-262 + k * 7.5, 66), 0.5, (40, 48, 54), 160, 0.0)
    C.ink(hood, 1.0)
    C.save(os.path.join(OUT, "deck", "coachroof.png"))

    # Deck details: wheel, winches, cleats, coils, fenders, lifelines, pulpits.
    T = Layer(4, CANVAS)
    life = v["DeckDetails/Lifelines"]["points"]
    T.ink(life, 0.7, STEEL_LIGHT, closed=False, amp=0.0, alpha=210)
    pulpit = v["DeckDetails/Pulpit"]["points"]
    T.ink(pulpit, 1.5, STEEL_DARK, closed=False, amp=0.0)
    T.ink(pulpit, 0.6, STEEL_LIGHT, closed=False, amp=0.0)
    push = v["DeckDetails/Pushpit"]["points"]
    T.ink(push, 1.5, STEEL_DARK, closed=False, amp=0.0)
    T.ink(push, 0.6, STEEL_LIGHT, closed=False, amp=0.0)
    for x, y in [(-470, -128), (-470, 128), (-300, -150), (-300, 150), (-100, -158), (-100, 158), (100, -158), (100, 158),
                 (300, -140), (300, 140)]:
        T.circle((x, y), 2.6, STEEL, 0.6, n=12, shadow=False)        # stanchion bases
    # The wheel on its pedestal.
    T.circle((-392, 0), 11, (58, 64, 68), 1.0)                          # pedestal with its compass
    T.circle((-392, 0), 6, (30, 36, 40), 0.6, n=16, shadow=False)
    wheel_r = 56
    T.ink([(-406, -wheel_r), (-406, wheel_r)], 3.6, STEEL_DARK, closed=False, amp=0.0)
    T.ink([(-406, -wheel_r), (-406, wheel_r)], 1.4, STEEL_LIGHT, closed=False, amp=0.0)
    for y in (-wheel_r, wheel_r):
        T.circle((-406, y), 3, (40, 44, 48), 0.6, n=10, shadow=False)
    # Winches by the cockpit, and cleats fore and aft.
    for x, y in [(-300, -112), (-300, 112), (-250, -86), (-250, 86)]:
        T.circle((x, y), 8.5, STEEL, 1.0)
        T.circle((x, y), 5.5, (66, 70, 74), 0.0, n=16, shadow=False)
        T.circle((x, y), 2.5, STEEL_LIGHT, 0.0, n=12, shadow=False)
    for x, y, a in [(-470, -116, 0), (-470, 116, 0), (430, -50, 0.5), (430, 50, -0.5), (250, -140, 0), (250, 140, 0)]:
        c, s = math.cos(a), math.sin(a)
        pts = [(-9, -2.5), (9, -2.5), (9, 2.5), (-9, 2.5)]
        T.piece([(x + px_ * c - py * s, y + px_ * s + py * c) for px_, py in pts], STEEL, 0.8)
    # Coiled sheets in the cockpit corners and a halyard coil at the mast.
    T.coil((-282, -78), 10)
    T.coil((-282, 78), 10, color=(160, 166, 172))
    winch_handle(T, -300, -112, 0.9)
    T.coil((215, 30), 9)
    # Anchor locker lid, bow roller with the anchor, swim ladder.
    T.piece(shape(v, "DeckDetails/AnchorLocker"), CREAM, 1.0)
    T.speckle(shape(v, "DeckDetails/AnchorLocker"), tuple(int(c * 0.86) for c in CREAM), density=0.3)
    T.piece(shape(v, "DeckDetails/BowRoller"), STEEL, 0.9)
    anchor = [(486, -3), (500, -3), (504, -9), (507, 0), (504, 9), (500, 3), (486, 3)]
    T.piece(anchor, STEEL_DARK, 0.8, shadow=False)
    T.piece(shape(v, "DeckDetails/SwimLadder"), STEEL, 0.8)
    for y in (-18, 0, 18):
        T.line((-512, y), (-500, y), 0.8, INK, 160)
    # Fenders tied to the lifelines on the harbour side (starboard, +y).
    for x in (-300, -40, 220):
        fender(T, x, 180)
    # A grab bag by the companionway and a mug in the cockpit: someone lives here.
    grab_bag(T, -470, -70)
    mug(T, -344, 52)
    T.save(os.path.join(OUT, "deck", "deck_details.png"))


# =============================================================== cabin
def paint_cabin():
    v = parse(os.path.join(ROOT, "src/vessels/starling_33/cabin_visual.tscn"))
    hull = shape(v, "CabinBase/HullShape")
    sole = shape(v, "CabinBase/CabinSole")

    B = Layer(11, CANVAS)
    B.fill(hull, (64, 56, 48), 0.05)                     # the hull's inside, dark timber
    B.ink(hull, 2.0, (40, 36, 32), amp=0.0)
    B.shadow(sole, (0, 0), 6, 120)
    teak_sole(B, sole, strip=11.0, color=HONEY, holly_alpha=70)
    B.grain(sole, (96, 78, 60), True, spacing=3.0, alpha=30)
    # Warm light pooling under the saloon lamp, a darker edge along the sides.
    light = Image.new("L", B.img.size, 0)
    ImageDraw.Draw(light).ellipse([B.px((-140, -90)), B.px((170, 90))], fill=30)
    light = light.filter(ImageFilter.GaussianBlur(40 * SS))
    glow = Image.new("RGBA", B.img.size, (240, 226, 196, 0))
    glow.putalpha(light)
    clipped = Image.new("RGBA", B.img.size, (0, 0, 0, 0))
    clipped.paste(glow, (0, 0), B.mask(sole))
    B.img.alpha_composite(clipped)
    B.save(os.path.join(OUT, "cabin", "cabin_base.png"))

    F = Layer(12, CANVAS)
    # Engine box and companionway steps.
    F.joinery(shape(v, "FurnitureVisual/EngineBox"), TEAK_DARK)
    steps = shape(v, "FurnitureVisual/CompanionwaySteps")
    F.joinery(steps, TEAK, horizontal=False)
    for k in range(1, 4):
        xs_ = [p[0] for p in steps]
        x = min(xs_) + (max(xs_) - min(xs_)) * k / 4
        F.line((x, min(p[1] for p in steps) + 2), (x, max(p[1] for p in steps) - 2), 0.8, (70, 58, 46), 200, 0.0)
    # Galley: teak counter, a two-burner stove, a round sink.
    galley = shape(v, "FurnitureVisual/Galley")
    F.joinery(galley, TEAK_DARK)
    top = [(x * 1.0, y) for x, y in galley]
    F.fill(F.rect(min(p[0] for p in galley) + 3, min(p[1] for p in galley) + 3, max(p[0] for p in galley) - min(p[0] for p in galley) - 6,
                  max(p[1] for p in galley) - min(p[1] for p in galley) - 9), (196, 198, 194), 0.02)   # solid-surface worktop
    F.piece(F.rect(-318, -138, 58, 30), (52, 56, 60), 1.0, shadow=False)         # gimballed stove
    for x in (-300, -276):
        F.circle((x, -123), 8, (34, 36, 38), 0.8, shadow=False)
        F.circle((x, -123), 4.5, (70, 74, 78), 0.0, n=12, shadow=False)
    F.line((-320, -106), (-258, -106), 1.2, STEEL, 230, 0.0)                     # stainless fiddle rail
    # (The right half of the counter is left plain: the provisions display
    # draws the food crates and water cans there.)
    # Navigation table with the chart, dividers and a lamp.
    nav = shape(v, "FurnitureVisual/NavTable")
    F.joinery(nav, TEAK_DARK)
    chart = [(x - 232, y + 116) for x, y in v["FurnitureVisual/NavTable/ChartPaper"]["polygon"]]
    F.piece(chart, (226, 226, 218), 0.8, shadow=False)
    F.ink([(x - 232, y + 116) for x, y in v["FurnitureVisual/NavTable/ChartCourse"]["points"]], 0.8, (180, 70, 60), closed=False, amp=0.0)
    F.ink([(-248, 104), (-262, 118), (-250, 132)], 0.6, STEEL_DARK, closed=False, amp=0.0)
    F.piece(F.rect(-196, 88, 18, 14), (28, 36, 42), 0.7, shadow=False)          # a small chartplotter repeater
    F.fill(F.rect(-194, 90, 14, 10), (62, 110, 122), 0.0)
    # Settees with plump cushions and the saloon table.
    for name, sy in (("FurnitureVisual/SetteePort", -1), ("FurnitureVisual/SetteeStarboard", 1)):
        base = shape(v, name)
        F.joinery(base, TEAK_DARK)
        for i in range(3):
            x0 = -112 + i * 80
            cy = 128 * sy
            r = F.rounded(x0, cy - 13, 78, 26, 3)
            F.shadow(r, (1.5, 2), 1.5, 70)
            F.fill(r, CUSHION, 0.04, grain=30.0)
            F.tone_edges(r, CUSHION, 2.2)
            F.ink(r, 0.9, (46, 56, 64), alpha=220, amp=0.0)
    table = F.rounded(-55, -33, 130, 66, 3)
    F.joinery(table, (118, 92, 68))
    F.line((-10, -30), (-10, 30), 0.6, (70, 56, 42), 200, 0.0)                    # drop-leaf hinges
    F.line((30, -30), (30, 30), 0.6, (70, 56, 42), 200, 0.0)
    F.ink(table, 1.4, (150, 124, 96), alpha=200, amp=0.0)                         # fiddle
    # Lockers and bulkheads forward, the V-berth with a blanket and pillow.
    for name in ("FurnitureVisual/StoragePort", "FurnitureVisual/StorageStarboard"):
        locker = shape(v, name)
        F.joinery(locker, TEAK_DARK, horizontal=False)
    for name in ("FurnitureVisual/BulkheadPort", "FurnitureVisual/BulkheadStarboard"):
        F.joinery(shape(v, name), (88, 74, 61))
    vberth = shape(v, "FurnitureVisual/VBerth")
    F.joinery(vberth, TEAK_DARK)
    xs_ = [p[0] for p in vberth]
    ys_ = [p[1] for p in vberth]
    cx, cy = (min(xs_) + max(xs_)) / 2, (min(ys_) + max(ys_)) / 2
    mattress = [(cx + (x - cx) * 0.95, cy + (y - cy) * 0.94) for x, y in vberth]
    F.fill(mattress, (214, 214, 208), 0.03)
    F.tone_edges(mattress, (214, 214, 208), 2.5)
    blanket = [(x + 370, y) for x, y in v["FurnitureVisual/VBerth/Blanket"]["polygon"]]
    F.shadow(blanket, (1, 2), 2, 60)
    F.fill(blanket, BLANKET, 0.05, grain=25.0)
    F.tone_edges(blanket, BLANKET, 3.0)
    F.ink(blanket, 0.8, (60, 70, 82), alpha=200, amp=0.0)
    pillow = [(x + 370, y) for x, y in v["FurnitureVisual/VBerth/Pillow"]["polygon"]]
    F.piece(pillow, (226, 226, 220), 0.8, shadow=False)
    F.save(os.path.join(OUT, "cabin", "furniture.png"))

    # Small details on top: books, a teapot and mugs, a lamp, a plant, a towel.
    X = Layer(13, CANVAS)
    book_row(X, 172, 100, 5)                                                       # pilot books and an almanac
    X.circle((-20, -6), 8, STEEL, 1.0)                                             # kettle
    X.line((-14, -12), (-8, -16), 1.0, STEEL_DARK, 220, 0.0)
    mug(X, 22, 8)
    mug(X, 40, -10, (96, 110, 124))
    X.piece(X.rect(-46, 10, 26, 18), (226, 226, 216), 0.7, shadow=False)          # tide tables, open
    X.line((-42, 16), (-25, 16), 0.4, INK, 120)
    X.line((-42, 21), (-30, 21), 0.4, INK, 120)
    X.piece(X.rounded(140, -58, 24, 14, 4), (50, 54, 58), 0.8)                     # binoculars
    X.piece(X.rounded(-236, -96, 9, 20, 2), (150, 156, 150), 0.6, shadow=False)   # tea towel on the galley rail
    X.circle((290, -40), 5, (208, 196, 160), 0.9, n=14)                            # reading lamp by the berth
    X.save(os.path.join(OUT, "cabin", "cabin_details.png"))


if __name__ == "__main__":
    parts = sys.argv[1:] or ["deck", "cabin"]
    if "deck" in parts:
        paint_deck()
    if "cabin" in parts:
        paint_cabin()
