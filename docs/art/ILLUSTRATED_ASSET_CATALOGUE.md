# The Captain's Illustrated Catalogue

Every picture in Little Captain's Hat, where it lives and how it is made. The
contact sheets show the art itself; this page says where each picture comes
from. Companion pages: the [art consistency review](ART_CONSISTENCY_REVIEW.md)
and the [catalogue report](ILLUSTRATED_CATALOGUE_REPORT.md).

**How the game's art is made.** There are three kinds, and many things use more
than one:

| Mark | Meaning |
|---|---|
| **PNG** | A picture file in the repository, loaded by the game |
| **Code** | Drawn by the game itself, in a GDScript `_draw()` function; there is no picture file |
| **Python** | The PNG was painted by a Python script in `tools/` (so it can be painted again the same way) |
| **Reused** | One picture serves many places (for example one harbour look for dozens of harbours) |

**Count.** 209 picture files belong to the game (outside `docs/`, `tests/` and
the Sprite Workshop's `art_replacements/`): 110 fish, 41 boat, 15 harbour, 8
companion, 28 branding (8 SVG and 20 PNG), the Captain's 4 original drawings and
3 chart rasters. 31 scripts draw in code.

## Contact sheets

| Sheet | Shows |
|---|---|
| [Boats and sails](contact_sheets/boats_contact_sheet.png) | Each boat's deck and cabin PNG layers, and the game's own screenshots of it moored, under sail and below decks |
| [Fish](contact_sheets/fish_contact_sheet.png) | The 26 fish and 3 pieces of junk, English and Danish names, rarity |
| [Companions](contact_sheets/companions_contact_sheet.png) | The cat's and the dog's four poses |
| [Harbours](contact_sheets/harbours_contact_sheet.png) | The nine harbour looks with example harbours, and the six special harbours |
| [Cabin things](contact_sheets/cabin_items_contact_sheet.png) | The ten cabin things, rendered by the game, with names and prices |
| [Chart symbols](contact_sheets/chart_symbols_contact_sheet.png) | The chart's markers, by day and by night |

Rebuild them with `python3 tools/art/build_contact_sheets.py` (see
[Regenerating](#regenerating) below). The pictures the game draws in code are
first photographed through the game by `tools/art/capture_previews.tscn`, into
[`previews/`](previews/).

## Boats and sails

Sheet: [boats_contact_sheet.png](contact_sheets/boats_contact_sheet.png).

| Boat (id) | Shown as | Canvas | Hull, deck, coachroof, details | Cabin |
|---|---|---|---|---|
| `arctic_wanderer_26` | Arctic Wanderer 26 | 1760 x 640 | PNG, Python | PNG, Python |
| `starling_33` | Wing 33 | 2240 x 800 | PNG, Python | PNG, Python |
| `petrel_36` | Frogleap 36 | 2400 x 1280 | PNG, Python | PNG, Python |
| `halcyon_40` | Clam 40 | 2240 x 1320 | PNG, Python | PNG, Python |

- **Layers.** `assets/vessels/<id>/illustrated/deck/` holds `hull_base`,
  `deck_base`, `coachroof` and `deck_details`; `.../cabin/` holds `cabin_base`,
  `furniture` and `cabin_details`. All layers of one area share one canvas and
  are drawn in the order listed in
  [`vessel_visual_profile.gd`](../../src/boat/visuals/vessel_visual_profile.gd)
  (a `shadow` layer is supported but none is painted). Painted by
  [`paint_illustrated_vessel.py`](../../tools/vessels/paint_illustrated_vessel.py)
  and [`paint_illustrated_starling.py`](../../tools/vessels/paint_illustrated_starling.py).
  The boat ids are older than the boats' names (Wing, Frogleap, Clam).
- **Sails, mast, boom and rigging: Code.**
  [`sail_rig.gd`](../../src/boat/sail_rig.gd) draws them from the trim and the
  wind; there are no sail PNGs. The sail cloths bought at the sailmaker change
  the colour only.
- **Also drawn in code on the boats:** the anchor ball and light
  ([`anchor_signals.gd`](../../src/boat/anchor_signals.gd)), solar panels
  ([`solar_panels.gd`](../../src/boat/visuals/solar_panels.gd)), wear and damage
  ([`damage_overlay.gd`](../../src/boat/visuals/damage_overlay.gd)), placeholder
  fittings ([`procedural_shape.gd`](../../src/boat/visuals/procedural_shape.gd),
  [`boat_fixture.gd`](../../src/boat/boat_fixture.gd)), the fenders' stowed
  state ([`fender_stowage.gd`](../../src/boat/fender_stowage.gd); the fenders
  themselves are painted into `deck_base.png`, `deck_details.png` on the Wing 33),
  and the haul-out picture ([`haul_out_scene.gd`](../../src/ui/haul_out_scene.gd)).
- **Not game art:** `assets/vessels/<id>/templates/` (painting guides for the
  Wing, Frogleap and Clam, made by
  [`render_art_templates.gd`](../../tools/vessels/render_art_templates.gd); the
  Arctic Wanderer has none) and `starling_33/demo/deck/coachroof.png` (a test
  picture for the Sprite Workshop's replacement rule, made by
  [`make_demo_coachroof.py`](../../tools/vessels/make_demo_coachroof.py) and used
  by `test_vessels`).
- Guide: [DEV_GUIDES/VESSEL_ART.md](../../DEV_GUIDES/VESSEL_ART.md).

## Cabin interiors and decorations

Sheets: [cabin_items_contact_sheet.png](contact_sheets/cabin_items_contact_sheet.png)
and the cabin column of the boats sheet.

| Thing | Made |
|---|---|
| Cabin floor, furniture and fittings | PNG, Python (the boat's `cabin/` layers, above) |
| The ten cabin things (rug, herbs, framed chart, oil lamp, books, bunting, model ship, sea glass, barometer, compass) | Code: [`cabin_decor.gd`](../../src/aboard/cabin_decor.gd); list, prices and places in [`trades.json`](../../data/harbours/trades/trades.json) |
| Food and water stores | Code: [`provision_display.gd`](../../src/boat/provision_display.gd) |
| Coffee mug, galley stove, rod holder, trophy board, windlass | Code: [`coffee_mug.gd`](../../src/aboard/coffee_mug.gd), [`galley_stove.gd`](../../src/aboard/galley_stove.gd), [`rod_holder.gd`](../../src/aboard/rod_holder.gd), [`trophy_board.gd`](../../src/aboard/trophy_board.gd), [`windlass.gd`](../../src/aboard/windlass.gd) |
| The framed world map on the cabin wall | Code: [`cabin_world_map.gd`](../../src/boat/cabin_world_map.gd), from the chart's own land data |
| The captain's hat (on its hook, worn, blowing away) | Code: [`hat_hook.gd`](../../src/hat/hat_hook.gd), [`player_hat.gd`](../../src/hat/player_hat.gd), [`hat_blow_away.gd`](../../src/hat/hat_blow_away.gd); [`hat_art.gd`](../../src/hat/hat_art.gd) can take PNGs, none are painted (`assets/hat/` holds only its README) |
| The player | Code: [`player.gd`](../../src/player/player.gd) |

Every cabin thing is drawn by the same function at each boat's own cabin spots,
so each is **reused** in all four cabins.

## Fish

Sheet: [fish_contact_sheet.png](contact_sheets/fish_contact_sheet.png).

- **26 species: PNG, Python.** `assets/fishing/<id>/` holds `body.png`,
  `tail.png` and `lid.png` (the closed eye, for the blink) on one 512 x 256
  canvas, and `thumb.png` (128 x 64) for lists. Painted by
  [`paint_fish.py`](../../tools/fishing/paint_fish.py), which also writes
  [`fish_art.json`](../../data/fishing/fish_art.json) (canvas, tail pivot,
  eye). [`fish_portrait.gd`](../../src/fishing/fish_portrait.gd) lays tail,
  body and lid together and animates them.
- **3 junk things** (old boot, tangled rope, rusty tin): one `art.png` and a
  `thumb.png` each.
- **Code:** the reel dial ([`reel_dial.gd`](../../src/ui/reel_dial.gd)).
- Names, rarities and seas: [`fishing.json`](../../data/fishing/fishing.json).

## Companions

Sheet: [companions_contact_sheet.png](contact_sheets/companions_contact_sheet.png).

- **Cat and dog: PNG, Python.** `assets/companions/<cat|dog>/` holds
  `resting`, `sleeping`, `alert` and `stretching` (256 x 256), painted by
  [`paint_companions.py`](../../tools/companions/paint_companions.py). The same
  four poses are **reused** on every boat.
- **Code (fallback):** [`ship_companion.gd`](../../src/companion/ship_companion.gd)
  draws a simple companion only if a pose picture is missing.
- **The Captain's originals:** `Visuals/Cat/` (four 1254 x 1254 drawings) are
  the Captain's own and are kept as they are; the game does not load them.
- Guide: [DEV_GUIDES/COMPANION_ANIMATION.md](../../DEV_GUIDES/COMPANION_ANIMATION.md).

## Harbours and arrival illustrations

Sheet: [harbours_contact_sheet.png](contact_sheets/harbours_contact_sheet.png).

- **The quay and pontoon around a moored boat: Code.**
  [`harbour_dressing.gd`](../../src/harbour/harbour_dressing.gd) draws the
  guest pontoon, lines, cleats, quay and signs, and places the harbour's
  illustration beyond the quay;
  [`shore_access.gd`](../../src/harbour/shore_access.gd) draws the gangplank.
- **Nine harbour looks: PNG, Python, Reused.** `assets/harbours/looks/*.png`
  (2300 x 220 each), painted by
  [`paint_harbour_looks.py`](../../tools/harbours/paint_harbour_looks.py). Each
  of the 239 harbours has one look, set in
  [`harbour_looks.json`](../../data/harbours/harbour_looks.json); the full list
  is in [HARBOUR_LOOKS.md](../iterations/i021/HARBOUR_LOOKS.md).
- **Arrival card:** the arrival card shows the same illustration as the deck
  (no separate picture). Examples:
  [`docs/screenshots/i021/`](../screenshots/i021/).

### Harbour gallery

| Look id | Picture | Harbours | Examples |
|---|---|---|---|
| `mediterranean` | [mediterranean.png](../../assets/harbours/looks/mediterranean.png) | 81 | Lisbon, Barcelona, Naples, Split, Piraeus, İzmir, Limassol, Las Palmas |
| `gabled_waterfront` | [gabled_waterfront.png](../../assets/harbours/looks/gabled_waterfront.png) | 45 | Kiel, Gothenburg, Tallinn, Harlingen, Svendborg, Willemstad, Cape Town |
| `nordic_timber` | [nordic_timber.png](../../assets/harbours/looks/nordic_timber.png) | 36 | Bergen, Reykjavík, Tórshavn, Mariehamn, Gilleleje, Auckland, St. John's |
| `atlantic_stone` | [atlantic_stone.png](../../assets/harbours/looks/atlantic_stone.png) | 33 | Helsinki, Dublin, Saint-Malo, Oban, A Coruña, St Peter Port, Hobart |
| `tropical_town` | [tropical_town.png](../../assets/harbours/looks/tropical_town.png) | 20 | Mindelo, Castries, Nassau, Papeete, Honolulu, Dakar, Galle |
| `volcanic_island` | [volcanic_island.png](../../assets/harbours/looks/volcanic_island.png) | 9 | Funchal, Horta, Arrecife, Puerto Ayora, Pago Pago |
| `aegean_island` | [aegean_island.png](../../assets/harbours/looks/aegean_island.png) | 7 | Hydra, Mykonos, Santorini, Paros, Skiathos |
| `tropical_island` | [tropical_island.png](../../assets/harbours/looks/tropical_island.png) | 6 | Port Elizabeth (Bequia), Fakarava, Bora Bora, Avarua, Nuku'alofa |
| `stone_town` | [stone_town.png](../../assets/harbours/looks/stone_town.png) | 2 | Essaouira, Zanzibar |

**Special harbours** have art of their own instead of their look (PNG, Python),
and a brass star on the chart:

| Harbour | Landmark | Picture | Art file | Look otherwise |
|---|---|---|---|---|
| Copenhagen | Nyhavn | [nyhavn.png](../../assets/harbours/copenhagen/nyhavn.png) | [copenhagen.tres](../../data/harbours/copenhagen.tres) | `gabled_waterfront` |
| Valletta | Grand Harbour bastions | [grand_harbour.png](../../assets/harbours/valletta/grand_harbour.png) | [valletta.tres](../../data/harbours/valletta.tres) | `mediterranean` |
| Symi | Gialos | [gialos.png](../../assets/harbours/symi/gialos.png) | [symi.tres](../../data/harbours/symi.tres) | `aegean_island` |
| Essaouira | The Skala | [skala.png](../../assets/harbours/essaouira/skala.png) | [essaouira.tres](../../data/harbours/essaouira.tres) | `stone_town` |
| Lunenburg | Lunenburg waterfront | [waterfront.png](../../assets/harbours/lunenburg/waterfront.png) | [lunenburg.tres](../../data/harbours/lunenburg.tres) | `nordic_timber` |
| St Helena | Jamestown | [jamestown.png](../../assets/harbours/st_helena/jamestown.png) | [st_helena.tres](../../data/harbours/st_helena.tres) | `volcanic_island` |

Nyhavn is painted by
[`paint_copenhagen_landmark.py`](../../tools/harbours/paint_copenhagen_landmark.py),
the other five by `paint_harbour_looks.py`.

**Are the assignments plausible?** Yes. The looks follow how a harbour town is
built, not only where it is: Cape Town and Willemstad have the gabled
waterfront (Cape Dutch and Dutch building), Helsinki and Hobart the stone
harbour (granite quays, sandstone warehouses), New Zealand and Atlantic Canada
the timber harbour, the Canaries' Las Palmas the Mediterranean town and
Madeira and the Azores the volcanic island. Each look's own description in
`harbour_looks.json` names the places it is meant for. Close calls that a
Captain may see differently, none of them wrong: Liverpool and Portsmouth (brick
cities, shown as Atlantic stone), Gdynia (a modern town, shown as gabled),
Le Havre (rebuilt in concrete, shown as Atlantic stone).

## Landmarks

The six special harbours' illustrations above are the game's landmarks
(`HarbourLandmark` in [`harbour_landmark.gd`](../../src/harbour/harbour_landmark.gd):
a title, a picture, an offset and a width, held by a
[`harbour_art.gd`](../../src/harbour/harbour_art.gd) resource per harbour).
There are no other landmark pictures; canals and sea areas are chart drawing.

## Chart icons and markers

Sheet: [chart_symbols_contact_sheet.png](contact_sheets/chart_symbols_contact_sheet.png).

All **Code**, in [`map_view.gd`](../../src/navigation/map_view.gd), on both the
navigation chart and the Dreamer's Map:

| Marker | Function |
|---|---|
| Harbour dot and name; selected harbour ring | `_draw_port` |
| Brass star of a special harbour | `_draw_special_star` |
| Visited-harbour pins (Dreamer's Map) | `_draw_pins` |
| Route waypoints | `_draw_waypoints` |
| Anchorage marks | `_draw_anchorage` |
| The boat | `_draw_boat` |
| Land, graticule, canals, routes | `_draw_world_tile`, `_draw_graticule`, `_draw_canals`, `_draw_courses` |

Also in code: the wind arrows ([`wind_layer.gd`](../../src/navigation/wind_layer.gd)),
the weather legend ([`weather_legend.gd`](../../src/navigation/weather_legend.gd))
and the anchorage overlay ([`anchorage_layer.gd`](../../src/navigation/anchorage_layer.gd)).
The land itself comes from data, not pictures: the chart rasters
`data/navigation/world/navmask.png`, `europe_navmask.png` and
`regions/denmark/navmask.png` are routing data (read, never shown).

## Weather and environment

All **Code**:

| What | Script |
|---|---|
| Wind streaks and rain on deck | [`weather_visuals.gd`](../../src/boat/weather_visuals.gd) |
| Light of the hour, cabin lamps, navigation lights | [`boat_lighting.gd`](../../src/boat/boat_lighting.gd) |
| Evening, night and morning colour at anchor | [`anchor_ambience.gd`](../../src/aboard/anchor_ambience.gd) |
| Water life: ripples, fish, birds, things afloat | [`water_life.gd`](../../src/water/water_life.gd) |
| Interaction highlights | [`interactable.gd`](../../src/interaction/interactable.gd) |

The deck screenshots of [`docs/screenshots/`](../screenshots/) show these in
play; they are not on a contact sheet because they move and change with time.

## Other

| What | Where | Made |
|---|---|---|
| Logo, icon, symbol (Little Captain's Hat, and the older Next Harbor set kept for history) | `assets/branding/*.svg`, PNG copies in `assets/branding/png/` | SVG by [`make_branding_svgs.py`](../../tools/make_branding_svgs.py); PNGs by [`export_branding.gd`](../../tools/export_branding.gd) |
| Interface theme | `assets/ui/next_harbor_theme.tres` | Code: [`build_theme.gd`](../../tools/build_theme.gd) |
| Fonts | `assets/fonts/` (Barlow, Patrick Hand; licences beside them) | Font files |
| The Sprite Workshop's slots for replacement art | `art_replacements/` ([start here](../../art_replacements/README_START_HERE.md)) | Empty slots and instructions; the game falls back to the art above |

## Regenerating

From the project folder (Linux; on Windows use `py` and the Godot executable's
own name):

```
# 1. Photograph the art drawn in code (needs a display; Xvfb and software OpenGL work)
xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 \
  res://tools/art/capture_previews.tscn -- --out=docs/art/previews
# 2. Build the six sheets (Python 3 with Pillow; no network)
python3 tools/art/build_contact_sheets.py
```

Step 2 alone is enough after a PNG changes. The sheets are byte-for-byte the
same when nothing changed; a missing picture becomes a grey "missing" tile
naming its path. Step 1 starts a game with scratch saves and settings
(`user://test_saves`), never the player's own.
