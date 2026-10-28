"""Paints Copenhagen's landmark illustration for the harbour (Real Horizon).

Usage: python3 tools/harbours/paint_copenhagen_landmark.py

Nyhavn seen from above, as the rest of the harbour is: the cobbled quay along
the water, then three of the 17th- and 18th-century town houses at their real
size (I025: about 1 cm per scene unit, like the boats' decks) - their
water-facing facades just visible below the eaves in Nyhavn's own colours
(ochre, oxblood, faded blue) with white window frames, their roofs of red clay
tile and dark slate with dormers and chimneys, light from the upper left.

Since I025 the painting itself lives with the other harbour illustrations in
paint_harbour_looks.py (`nyhavn`), so it shares their scale, facade line and
materials; this script stays as the documented entry point.

Writes assets/harbours/copenhagen/nyhavn.png (2 px per scene unit, 1150 x 110
units, transparent background). data/harbours/copenhagen.tres places it.
Requires Pillow and numpy.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from paint_harbour_looks import nyhavn  # noqa: E402

if __name__ == "__main__":
    nyhavn()
