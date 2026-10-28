"""Paints the ship's companions (cat, dog, parrot).

Since Iteration I024 the companions are animated clips painted by
paint_companion_clips.py (the soft-puppet renderer in companion_render.py);
this script is kept as the old entry point and simply runs it.

Usage: python3 tools/companions/paint_companions.py   (same as paint_companion_clips.py)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import paint_companion_clips  # noqa: E402

if __name__ == "__main__":
    paint_companion_clips.main(sys.argv[1:])
