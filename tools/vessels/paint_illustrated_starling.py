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
from paint_illustrated_vessel import fender, grab_bag, mug, book_row, winch_handle  # noqa: E402
from paint_illustrated_vessel import illustrate_cabin, parse_nodes  # noqa: E402

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
def paint_details(X):
    """Small details on top: books, a teapot and mugs, a lamp, a towel."""
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


def paint_cabin():
    """The cabin (I025): the shared yacht-interior painting of
    paint_illustrated_vessel.illustrate_cabin (cabin_joinery.py), from the
    Wing 33's own cabin_visual.tscn, with its own small details."""
    path = os.path.join(ROOT, "src/vessels/starling_33/cabin_visual.tscn")
    nodes, order = parse_nodes(path)
    illustrate_cabin("starling_33", nodes, order, CANVAS, os.path.join(OUT, "cabin"), {"CabinDetails": paint_details},
                     seeds=(11, 12, 13))


if __name__ == "__main__":
    parts = sys.argv[1:] or ["deck", "cabin"]
    if "deck" in parts:
        paint_deck()
    if "cabin" in parts:
        paint_cabin()
