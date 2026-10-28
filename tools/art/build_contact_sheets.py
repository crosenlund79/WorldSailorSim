#!/usr/bin/env python3
"""The Captain's Illustrated Catalogue: builds the contact sheets in docs/art/contact_sheets/.

Every picture on a sheet is one of the game's own files, read from the repository:
the PNG art (boat layers, fish, companions, harbour illustrations) and the previews
of the art the game draws in code, which tools/art/capture_previews.tscn renders
through the game itself into docs/art/previews/. Nothing is redrawn here; a file
that is missing becomes a grey "missing" tile with its path, and the sheet is
still written.

Names are given in English and Danish, the Danish taken from locale/da.po.

Run (Python 3 with Pillow, no network):
    python3 tools/art/build_contact_sheets.py            # all six sheets
    python3 tools/art/build_contact_sheets.py --only fish
To refresh the previews first (Godot, rendered; see capture_previews.gd):
    xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \\
      res://tools/art/capture_previews.tscn -- --out=docs/art/previews

The output is deterministic: the same files in give the same bytes out. The sheets
are never read as input.
"""
import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs/art/contact_sheets"
PREVIEWS = ROOT / "docs/art/previews"
FONTS = ROOT / "assets/fonts"

PAPER = (239, 230, 210)
TILE = (248, 243, 230)
INK = (59, 47, 37)
SOFT = (120, 104, 88)
LINE = (210, 196, 170)
MISSING = (200, 200, 200)
CHECKER = ((236, 232, 224), (222, 216, 206))

PAD = 16
VESSELS = ["arctic_wanderer_26", "starling_33", "petrel_36", "halcyon_40"]
DECK_LAYERS = ["shadow", "hull_base", "deck_base", "coachroof", "deck_details"]
CABIN_LAYERS = ["cabin_base", "furniture", "cabin_details"]
POSES = ["resting", "sleeping", "alert", "stretching"]
CHART_SYMBOLS = [
    ("harbour", "An ordinary harbour (Messina)"),
    ("selected", "The selected harbour (Catania)"),
    ("destination_special", "Destination and special harbour star (Valletta)"),
    ("boat_in_harbour", "The boat in harbour (Syracuse)"),
    ("waypoint", "A route waypoint"),
    ("visited_pin", "Dreamer's Map: a visited pin (Kiel)"),
    ("visited_cluster", "Dreamer's Map: visited pins together (Copenhagen)"),
]


def font(weight, size):
    return ImageFont.truetype(str(FONTS / f"Barlow-{weight}.ttf"), size)


F_TITLE, F_SUB, F_NAME, F_TEXT = font("SemiBold", 34), font("Regular", 17), font("SemiBold", 17), font("Regular", 15)


# --- Repository data ---------------------------------------------------------------------

def load_danish():
    spec = importlib.util.spec_from_file_location("i18n_check", ROOT / "tools/i18n/check.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    entries = module.parse(ROOT / "locale/da.po")
    return {key: value["str"][0] for key, value in entries.items() if value["str"] and value["str"][0]}


DA = {}


def da(text, context=""):
    return DA.get((context, text), "?")


def tres_value(path, key):
    match = re.search(rf'^{key} = "(.*)"$', path.read_text(encoding="utf-8"), re.M)
    return match.group(1) if match else None


def port_name(port_id):
    path = ROOT / f"data/navigation/ports/{port_id}.tres"
    return (tres_value(path, "display_name") or port_id) if path.exists() else port_id


def rel(path):
    return path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else path.as_posix()


# --- Drawing -----------------------------------------------------------------------------

def open_rgba(path):
    return Image.open(path).convert("RGBA") if path.exists() else None


def composite(paths):
    """Layers that share one canvas, drawn in order; missing layers are skipped."""
    layers = [open_rgba(p) for p in paths]
    present = [im for im in layers if im is not None]
    if not present:
        return None
    out = Image.new("RGBA", present[0].size, (0, 0, 0, 0))
    for im in present:
        if im.size == out.size:
            out.alpha_composite(im)
    return out


def checker(size, step=12):
    image = Image.new("RGB", size, CHECKER[0])
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], step):
        for x in range(0, size[0], step):
            if (x // step + y // step) % 2:
                draw.rectangle([x, y, x + step - 1, y + step - 1], fill=CHECKER[1])
    return image


def fit(image, box, max_up=2.0):
    scale = min(box[0] / image.width, box[1] / image.height, max_up)
    size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
    return image.resize(size, Image.LANCZOS)


def wrap(draw, text, face, width):
    """Lines that fit the width; a path too long for one line breaks after a slash."""
    pieces = []  # (text, joined to the piece before without a space)
    for word in text.split():
        if draw.textlength(word, font=face) <= width or "/" not in word:
            pieces.append((word, False))
        else:
            parts = re.split(r"(?<=/)", word)
            pieces += [(part, n > 0) for n, part in enumerate(parts) if part]
    lines, line = [], ""
    for piece, glued in pieces:
        trial = line + piece if glued or not line else f"{line} {piece}"
        if draw.textlength(trial, font=face) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = piece
    if line:
        lines.append(line)
    return lines


class Tile:
    """One picture (or None when missing), its source path and a few label lines."""

    def __init__(self, image, source, name, lines=(), transparent=True):
        self.image, self.source, self.name, self.lines, self.transparent = image, source, name, list(lines), transparent


def tile_text(tile, width, draw):
    out = [(F_NAME, INK, line) for line in wrap(draw, tile.name, F_NAME, width)]
    for line in tile.lines:
        out += [(F_TEXT, SOFT, part) for part in wrap(draw, line, F_TEXT, width)]
    sources = tile.source if isinstance(tile.source, list) else [tile.source]
    for source in sources:
        out += [(F_TEXT, SOFT, part) for part in wrap(draw, source, F_TEXT, width)]
    return out


def sheet(name, title, subtitle, tiles, cols, box):
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    cell_w = box[0] + 2 * PAD
    texts = [tile_text(t, box[0], probe) for t in tiles]
    rows = [list(range(i, min(i + cols, len(tiles)))) for i in range(0, len(tiles), cols)]
    row_h = [box[1] + 2 * PAD + max(sum(f.size + 5 for f, _, _ in texts[i]) for i in row) for row in rows]
    width = PAD + cols * (cell_w + PAD)
    subtitle = [part for line in subtitle for part in wrap(probe, line, F_SUB, width - 4 * PAD)]
    head = 2 * PAD + 44 + 24 * len(subtitle)
    height = head + sum(h + PAD for h in row_h) + PAD
    image = Image.new("RGB", (width, height), PAPER)
    draw = ImageDraw.Draw(image)
    draw.text((PAD * 2, PAD), title, font=F_TITLE, fill=INK)
    for n, line in enumerate(subtitle):
        draw.text((PAD * 2, PAD + 48 + 24 * n), line, font=F_SUB, fill=SOFT)
    y = head
    for row, h in zip(rows, row_h):
        for col, i in enumerate(row):
            tile, x = tiles[i], PAD + col * (cell_w + PAD)
            draw.rectangle([x, y, x + cell_w - 1, y + h - 1], fill=TILE, outline=LINE)
            bx, by = x + PAD, y + PAD
            if tile.image is None:
                draw.rectangle([bx, by, bx + box[0] - 1, by + box[1] - 1], fill=MISSING)
                draw.text((bx + 10, by + 10), "missing", font=F_NAME, fill=INK)
            else:
                picture = fit(tile.image, box)
                px, py = bx + (box[0] - picture.width) // 2, by + (box[1] - picture.height) // 2
                if tile.transparent:
                    base = checker(picture.size).convert("RGBA")
                    base.alpha_composite(picture)
                    picture = base
                image.paste(picture.convert("RGB"), (px, py))
            ty = by + box[1] + PAD // 2
            for face, colour, line in texts[i]:
                draw.text((bx, ty), line, font=face, fill=colour)
                ty += face.size + 5
        y += h + PAD
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}_contact_sheet.png"
    image.save(path, optimize=False)
    missing = sum(1 for t in tiles if t.image is None)
    print(f"{rel(path)}: {len(tiles)} tiles, {missing} missing, {image.width} x {image.height}")
    return missing


SOURCE_NOTE = "Transparent art on a grey check; picture sizes are fitted to the tile (at most 2x enlarged)."


def preview(file_name):
    path = PREVIEWS / file_name
    return open_rgba(path), rel(path)


# --- The six sheets ----------------------------------------------------------------------

def boats():
    tiles = []
    for vessel in VESSELS:
        name = tres_value(ROOT / f"data/vessels/{vessel}.tres", "display_name") or vessel
        folder = ROOT / f"assets/vessels/{vessel}/illustrated"
        deck = [folder / "deck" / f"{layer}.png" for layer in DECK_LAYERS]
        cabin = [folder / "cabin" / f"{layer}.png" for layer in CABIN_LAYERS]
        tiles.append(Tile(composite(deck), f"{rel(folder)}/deck/*.png", f"{name} ({vessel})",
                          ["Deck PNG layers: " + ", ".join(p.stem for p in deck if p.exists())]))
        tiles.append(Tile(composite(cabin), f"{rel(folder)}/cabin/*.png", f"{name}: cabin",
                          ["Cabin PNG layers: " + ", ".join(p.stem for p in cabin if p.exists())]))
        for shot, label in [("moored", "In game: moored (Copenhagen, midday)"),
                            ("underway", "In game: under sail (sails, mast and rigging drawn in code)"),
                            ("cabin", "In game: the cabin with every cabin thing")]:
            image, source = preview(f"boat_{vessel}_{shot}.png")
            tiles.append(Tile(image, source, label, transparent=False))
    return sheet("boats", "Boats and sails", [
        "Each row: the boat's PNG layers on their shared canvas (as stored, bow to the left), then three game screenshots.",
        "Sails, mast, boom and rigging have no PNG: the game draws them (src/boat/sail_rig.gd), so they appear only in the screenshots.",
        SOURCE_NOTE], tiles, 5, (330, 186))


def fish():
    data = json.loads((ROOT / "data/fishing/fishing.json").read_text(encoding="utf-8"))
    tiles = []
    for species in data["species"]:
        folder = ROOT / f"assets/fishing/{species['id']}"
        image = composite([folder / "tail.png", folder / "body.png"])
        tiles.append(Tile(image, f"{rel(folder)}/{{tail,body}}.png", f"{species['name']} / {da(species['name'])}",
                          [f"{species['id']} · {species['rarity'].replace('_', ' ')}"]))
    for junk in data["junk"]:
        folder = ROOT / f"assets/fishing/{junk['id']}"
        tiles.append(Tile(open_rgba(folder / "art.png"), f"{rel(folder)}/art.png",
                          f"{junk['name']} / {da(junk['name'])}", [f"{junk['id']} · junk"]))
    return sheet("fish", "Fish and the things that are not fish", [
        "Each fish is its tail and body layers together (512 x 256, by tools/fishing/paint_fish.py); the closed-eye lid and the",
        "128 x 64 thumb are in the same folder. Order as in data/fishing/fishing.json. " + SOURCE_NOTE], tiles, 6, (256, 128))


def companions():
    tiles = []
    for kind, label in [("cat", "Cat / Kat"), ("dog", "Dog / Hund")]:
        for pose in POSES:
            path = ROOT / f"assets/companions/{kind}/{pose}.png"
            tiles.append(Tile(open_rgba(path), rel(path), f"{label}: {pose}"))
    return sheet("companions", "Ship's companions", [
        "The four poses of each companion (256 x 256, by tools/companions/paint_companions.py).",
        "The older drawn fallback (src/companion/ship_companion.gd) is used only when a pose is missing. " + SOURCE_NOTE],
        tiles, 4, (256, 256))


def harbours():
    data = json.loads((ROOT / "data/harbours/harbour_looks.json").read_text(encoding="utf-8"))
    by_look = {}
    for port, look in data["harbours"].items():
        by_look.setdefault(look, []).append(port)
    tiles = []
    for look, info in data["looks"].items():
        path = ROOT / info["texture"].removeprefix("res://")
        ports = by_look.get(look, [])
        examples = ", ".join(port_name(p) for p in ports[:8]) + (" ..." if len(ports) > 8 else "")
        tiles.append(Tile(open_rgba(path), rel(path), f"{look}: {info['title']} / {da(info['title'])}",
                          [f"{len(ports)} harbours, e.g. {examples}"]))
    for port, special in data["special"].items():
        art = ROOT / f"data/harbours/{port}.tres"
        texture = re.search(r'type="Texture2D" path="res://([^"]+)"', art.read_text(encoding="utf-8")) if art.exists() else None
        path = ROOT / texture.group(1) if texture else art
        landmark = tres_value(art, "title") if art.exists() else "?"
        name = port_name(port)
        tiles.append(Tile(open_rgba(path), [rel(path), rel(art)],
                          f"Special: {name} / {da(name, 'place')}: {landmark} (brass star on the chart)",
                          [special["text"][:1].upper() + special["text"][1:] + f"; otherwise a {data['harbours'].get(port, '?')} harbour."]))
    return sheet("harbours", "Harbours and arrival illustrations", [
        "The nine harbour looks (assets/harbours/looks/, by tools/harbours/paint_harbour_looks.py) and the six special harbours",
        "with art of their own. Each strip is 2300 x 220 and shown whole; on deck only its upper band rises above the screen edge.",
        "Look per harbour: data/harbours/harbour_looks.json (examples in file order). " + SOURCE_NOTE], tiles, 1, (1380, 132))


def cabin_items():
    data = json.loads((ROOT / "data/harbours/trades/trades.json").read_text(encoding="utf-8"))
    tiles = []
    for item in data["decor"]:
        image, source = preview(f"decor_{item['id']}.png")
        tiles.append(Tile(image, source, f"{item['name']} / {da(item['name'])}",
                          [f"{item['id']} · {item['place']} · {item['price']} €"], transparent=False))
    return sheet("cabin_items", "Cabin things", [
        "Drawn by the game (src/aboard/cabin_decor.gd, no PNG); rendered by tools/art/capture_previews.tscn on a cabin-floor",
        "colour, the rug at 2x and the rest at 3x their cabin size. Order and prices as in data/harbours/trades/trades.json."],
        tiles, 3, (260, 220))


def chart_symbols():
    tiles = []
    for symbol, label in CHART_SYMBOLS:
        for mood in ("day", "night"):
            image, source = preview(f"chart_{symbol}_{mood}.png")
            tiles.append(Tile(image, source, f"{label}: {mood}", transparent=False))
    return sheet("chart_symbols", "Chart icons and markers", [
        "Cropped from the real chart and Dreamer's Map (src/navigation/map_view.gd draws them; no PNG), by day and by night",
        "(Vintage Chartroom and Harbor Dusk). Rendered by tools/art/capture_previews.tscn; enlarged 2x here."],
        tiles, 4, (250, 120))


SHEETS = {"boats": boats, "fish": fish, "companions": companions, "harbours": harbours,
          "cabin_items": cabin_items, "chart_symbols": chart_symbols}


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", choices=sorted(SHEETS), action="append", help="build just this sheet (repeatable)")
    args = parser.parse_args()
    DA.update(load_danish())
    missing = sum(SHEETS[name]() for name in (args.only or SHEETS))
    if missing:
        print(f"{missing} picture(s) missing: shown as grey tiles")
    return 0


if __name__ == "__main__":
    sys.exit(main())
