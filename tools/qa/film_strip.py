#!/usr/bin/env python3
"""Joins numbered screenshots (NAME_00.png, NAME_01.png, ...) into one strip
image per NAME, cropped around a region, for motion reviews (I025).

Usage: python3 tools/qa/film_strip.py DIR [--crop x0,y0,x1,y1] [--cols N]
Writes DIR/NAME_strip.png for every NAME that has frames; the frames are kept.
"""
import argparse
import os
import re
from collections import defaultdict

from PIL import Image


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--crop", default="")
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--width", type=int, default=520, help="width of each frame in the strip")
    a = ap.parse_args()
    groups = defaultdict(list)
    for f in sorted(os.listdir(a.dir)):
        m = re.match(r"^(film_.+)_(\d\d)\.png$", f)
        if m:
            groups[m.group(1)].append(os.path.join(a.dir, f))
    crop = tuple(int(v) for v in a.crop.split(",")) if a.crop else None
    for name, files in groups.items():
        frames = []
        for f in files:
            im = Image.open(f).convert("RGB")
            if crop:
                sx, sy = im.width / 1600.0, im.height / 900.0
                im = im.crop((int(crop[0] * sx), int(crop[1] * sy), int(crop[2] * sx), int(crop[3] * sy)))
            h = int(im.height * a.width / im.width)
            frames.append(im.resize((a.width, h), Image.LANCZOS))
        cols = min(a.cols, len(frames))
        rows = (len(frames) + cols - 1) // cols
        fw, fh = frames[0].size
        sheet = Image.new("RGB", (cols * fw + (cols + 1) * 6, rows * fh + (rows + 1) * 6), (24, 30, 34))
        for i, im in enumerate(frames):
            sheet.paste(im, (6 + (i % cols) * (fw + 6), 6 + (i // cols) * (fh + 6)))
        out = os.path.join(a.dir, name + "_strip.png")
        sheet.save(out, optimize=True)
        print("wrote", out, len(frames), "frames")


if __name__ == "__main__":
    main()
