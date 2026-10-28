"""Generates the Real Horizon branding SVGs for Little Captain's Hat.

Usage: python3 tools/branding/make_horizon_branding.py

A restrained title treatment: the name in tracked Barlow Condensed capitals
(converted to outline paths, so the SVGs render identically everywhere,
including Godot's SVG importer), a fine instrument-cyan rule, and a small
line drawing of a captain's cap above it. The same file names as before
(assets/branding/little_captains_hat_*.svg), so every screen that shows the
logo keeps working; the old Next Harbor files stay untouched for history.
Re-export the PNGs afterwards with:
    godot --headless --path . -s res://tools/export_branding.gd

Requirements: Python 3 with fontTools.
"""
import os

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
FONT = os.path.join(ROOT, "assets", "fonts", "BarlowCondensed-SemiBold.ttf")
OUT = os.path.join(ROOT, "assets", "branding")
NAME = "LITTLE CAPTAIN’S HAT"
WHITE, NAVY, CYAN, STEEL = "#E9EEEC", "#1B2932", "#5AA8B8", "#77888C"


def wordmark(text, size, tracking_em, x0, baseline):
    font = TTFont(FONT)
    gs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    hmtx = font["hmtx"]
    paths, x = [], 0.0
    for i, ch in enumerate(text):
        gname = cmap[ord(ch)]
        if ch != " ":
            pen = SVGPathPen(gs)
            gs[gname].draw(TransformPen(pen, (scale, 0, 0, -scale, x0 + x, baseline)))
            paths.append(pen.getCommands())
        x += hmtx[gname][0] * scale
        if i < len(text) - 1:
            x += tracking_em * size
    return " ".join(paths), x


def cap(cx, cy, s, ink, accent):
    """A captain's cap in profile as a fine line drawing (about 120 x 60 at s=1)."""
    w = 2.6 / s
    g = f'<g transform="translate({cx} {cy}) scale({s})" fill="none" stroke="{ink}" stroke-width="{w}" ' \
        f'stroke-linejoin="round" stroke-linecap="round">'
    g += '<path d="M-52 -6 Q -50 -34 0 -38 Q 54 -40 58 -14 Q 40 -4 0 -4 Q -34 -3 -52 -6 Z"/>'
    g += '<path d="M-44 -5 L -40 14 Q 0 20 42 14 L 46 -8"/>'
    g += f'<path d="M-40 14 Q 0 21 42 14" stroke="{accent}"/>'
    g += '<path d="M-40 14 Q -48 22 -60 24 Q -20 34 30 26 Q 42 22 42 14"/>'
    g += f'<circle cx="2" cy="4" r="4.5" stroke="{accent}"/>'
    return g + "</g>"


def logo(ink, accent, rule):
    size, tracking = 92, 0.06
    probe, width = wordmark(NAME, size, tracking, 0, 0)
    w, h = int(width + 80), 300
    x0 = (w - width) / 2
    text, _ = wordmark(NAME, size, tracking, x0, 236)
    body = cap(w / 2, 82, 1.15, ink, accent)
    body += f'<rect x="{x0}" y="148" width="{width}" height="2" fill="{rule}"/>'
    body += f'<rect x="{w / 2 - 34}" y="146" width="68" height="6" fill="{accent}"/>'
    body += f'<path d="{text}" fill="{ink}"/>'
    return svg(w, h, body, "Little Captain’s Hat")


def symbol(bg=None, ink=WHITE, accent=CYAN):
    body = ""
    if bg:
        body += f'<rect x="8" y="8" width="240" height="240" rx="28" fill="{bg}"/>'
        body += f'<rect x="8" y="8" width="240" height="240" rx="28" fill="none" stroke="{accent}" stroke-width="4" opacity="0.6"/>'
    body += cap(128, 120, 1.6, ink, accent)
    body += f'<rect x="56" y="186" width="144" height="5" rx="2" fill="{accent}"/>'
    return svg(256, 256, body, "Little Captain’s Hat")


def svg(w, h, body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="0 0 {w} {h}"><title>{title}</title>{body}</svg>\n')


def write(name, content):
    path = os.path.join(OUT, name)
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    write("little_captains_hat_logo.svg", logo(WHITE, CYAN, STEEL))
    write("little_captains_hat_logo_on_light.svg", logo(NAVY, "#3F8796", STEEL))
    write("little_captains_hat_symbol.svg", symbol())
    write("little_captains_hat_icon.svg", symbol(bg="#202D35"))
