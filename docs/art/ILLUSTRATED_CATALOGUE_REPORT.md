# The Captain's Illustrated Catalogue: report

A documentation and visual inspection pass: an index of every picture in the
game, contact sheets of the art itself, and a consistency review. **No
gameplay, interface, save format, game data or artwork was changed.** Version
stays 0.108a, save format 12.

## 1. Commits

| | Commit |
|---|---|
| Starting point (the Harbourmaster's Inspection complete) | `5b30c4b6de70341decb74121e7ef9b9b0197d6ad` |
| The catalogue, sheets, previews, review, tools and this report | the branch head after this pass (stated in the delivery) |

No backup branch was moved or created (`backup/post-turbocharge-pre-i019`,
`backup/post-i019-pre-i020`, `backup/post-engine-room-pre-i021` unchanged);
nothing was force-pushed.

## 2. What was made

| File | What |
|---|---|
| [ILLUSTRATED_ASSET_CATALOGUE.md](ILLUSTRATED_ASSET_CATALOGUE.md) | The index: every category, its source files and painter scripts, and whether each picture is a PNG, drawn in code, painted by Python, and/or reused; the harbour gallery |
| [ART_CONSISTENCY_REVIEW.md](ART_CONSISTENCY_REVIEW.md) | Twelve findings, each classified, with files and evidence pictures in [`review/`](review/) |
| [`contact_sheets/`](contact_sheets/) | The six sheets (below) |
| [`previews/`](previews/) | 35 pictures of code-drawn art, photographed through the game |
| `tools/art/build_contact_sheets.py` | Builds the sheets from the repository's files (Python 3 with Pillow) |
| `tools/art/capture_previews.gd` / `.tscn` | Photographs the code-drawn art through the game itself |

Also: links from the [library index](../README.md) and the
[testing guide](../testing/README.md), and the capture tool's entry in the
three GDScript guides (English, Danish, architecture).

## 3. Categories and counts

| Category | Pictures | How made |
|---|---|---|
| Boats and sails | 4 boats x 7 layers (28 PNG); 12 templates and 1 demo (not shown in play) | PNG painted by Python; sails, mast and rigging drawn in code |
| Cabin interiors and decorations | 9 cabin things (10 since Operation Paperwork), stores, mug, stove, rod holder, trophy board, windlass, world map, hat | Code (the cabin floor and furniture are the boats' PNG layers) |
| Fish | 26 species x 4 PNG, 3 junk x 2 PNG (110) | PNG painted by Python |
| Companions | 2 kinds x 4 poses (8) | PNG painted by Python; a code-drawn fallback |
| Harbours and arrival illustrations | 9 looks, reused by 239 harbours | PNG painted by Python; quay and pontoon drawn in code |
| Landmarks | 6 special harbours | PNG painted by Python |
| Chart icons and markers | 7 marker kinds captured (and anchorage marks) | Code |
| Weather and environment | wind, rain, light, anchor ambience, water life | Code |
| Other | 28 branding files, theme, fonts; the Captain's 4 original drawings | SVG by Python, PNG by Godot; the originals untouched |

209 picture files in all (outside `docs/`, `tests/`, `art_replacements/`); 31
scripts draw in code.

## 4. Sheets generated

| Sheet | Tiles | Missing |
|---|---|---|
| [boats_contact_sheet.png](contact_sheets/boats_contact_sheet.png) | 20 (per boat: deck layers, cabin layers, moored, under sail, cabin) | 0 |
| [fish_contact_sheet.png](contact_sheets/fish_contact_sheet.png) | 29 (26 fish, 3 junk) | 0 |
| [companions_contact_sheet.png](contact_sheets/companions_contact_sheet.png) | 8 | 0 |
| [harbours_contact_sheet.png](contact_sheets/harbours_contact_sheet.png) | 15 (9 looks, 6 special) | 0 |
| [cabin_items_contact_sheet.png](contact_sheets/cabin_items_contact_sheet.png) | 9 | 0 |
| [chart_symbols_contact_sheet.png](contact_sheets/chart_symbols_contact_sheet.png) | 14 (7 markers, by day and night) | 0 |

Every sheet uses the same paper background, tile, fonts (the game's Barlow) and
labels: English and Danish name (Danish from `locale/da.po`, the game's own
translation; all found), id and the source path. Transparent art is shown on a
grey check. Every picture is a real game file or a picture taken from the
running game; nothing was imitated or redrawn.

## 5. Not rendered

Nothing was impossible to render. Left off the sheets on purpose, because they
move or change with the moment (they are in the catalogue and visible in the
game screenshots): weather, light of the hour, anchor ambience, water life, the
player and the hat, the anchor ball and light, wear and damage, the haul-out
picture, the chart's wind arrows, weather legend and anchorage overlay.

## 6. Main findings

From the [review](ART_CONSISTENCY_REVIEW.md); nothing was changed because of
them:

- **Confirmed technical issue:** on the Arctic Wanderer 26 and the Wing 33 the
  fenders' soft shadow is cut by the bottom of the canvas. Invisible in play;
  worth fixing only if those boats are repainted.
- **Minor visual inconsistencies:** the deck panel of the HUD still shows the
  old Next Harbor sailboat symbol, faint on its cream panel; the harbour strips
  are not equally centred on their canvas (up to 4 %).
- **Artistic recommendations for the Captain:** the harbour illustrations are
  simpler than the boats, fish and companions; only their top band shows on
  deck; chart markers look alike by day and night; the special harbour's brass
  star is small.
- **No action needed:** styles are consistent within each family; nothing is
  enlarged or blurred in play; transparency is clean; no duplicates; nothing
  missing; the harbour looks are assigned plausibly (by how a town is built,
  not only where it is).

## 7. How to regenerate

```
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \
  res://tools/art/capture_previews.tscn -- --out=docs/art/previews
python3 tools/art/build_contact_sheets.py            # or --only fish (repeatable)
```

The first step is needed only when code-drawn art changes. The builder reads
only repository files and `docs/art/previews/`, never its own sheets; uses no
network; and a missing file becomes a labelled grey tile.

## 8. Validation

- **Sheets open** (each was opened and checked by eye) and **regeneration is
  deterministic:** two consecutive builds gave byte-identical files (MD5 of all
  six equal).
- **Missing files handled:** with the previews folder pointed at an empty
  folder, the cabin-things and chart sheets were still written, with 9 and 14
  grey "missing" tiles.
- **Labels match the assets:** names, ids, rarities and prices are read from
  the same data files the game reads; every Danish name was found.
- **Source paths exist** and **links resolve:** `tools/docs/check_links.py`
  passes; `test_dev_guides` passes.
- `tools/docs/check_gdscript_guides.py`: passes (282 scripts).
- `tools/qa/check_game_content.py`: 31 checks PASS, 0 FAIL, 7 INFO (as before).
- **Gameplay unchanged:** the diff touches only `docs/` and `tools/art/`. No
  `src/`, `data/`, `assets/`, `locale/` or `tests/` file, scene, resource,
  translation or save code changed. The capture tool runs the game with scratch
  saves and settings (`user://test_saves`, `user://test_settings.cfg`).
- **Windows was not tested.** The builder is plain Python and Pillow and should
  run there; the capture tool needs Godot with a display.
