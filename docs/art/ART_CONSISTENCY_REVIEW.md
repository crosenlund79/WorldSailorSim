# Art consistency review

A look at all of the game's art together, made for the
[Illustrated Catalogue](ILLUSTRATED_ASSET_CATALOGUE.md). **No art was redrawn
or replaced.** Each finding has one of four classifications:

| Classification | Meaning |
|---|---|
| **Confirmed technical issue** | Measurable in the file; worth fixing when the art is next touched |
| **Minor visual inconsistency** | Visible on close inspection; the game works and reads well |
| **Artistic recommendation** | A matter of taste, for the Captain to decide |
| **No action needed** | Checked and fine, or different on purpose |

## How it was checked

- **By eye:** the six [contact sheets](contact_sheets/) and the game
  screenshots in [`previews/`](previews/), rendered by the game itself.
- **By measurement** (Pillow, over all 209 game pictures): size and colour mode,
  transparency, the drawn area inside each canvas (margins), pictures that touch
  their canvas edge, byte-identical duplicates, and missing files. How each
  picture is shown in game (scale) was read from the code.
- Small evidence pictures are in [`review/`](review/).

## Summary

| # | Finding | Classification |
|---|---|---|
| 1 | Fender shadows touch the bottom edge of two boat canvases | Confirmed technical issue (invisible in play) |
| 2 | The HUD's deck panel still shows the old Next Harbor sailboat symbol, faint on its cream panel | Minor visual inconsistency |
| 3 | Harbour pictures are not equally centred on their 2300 px strip | Minor visual inconsistency |
| 4 | The harbour illustrations are simpler and flatter than the boats, fish and companions | Artistic recommendation |
| 5 | Only the top band of a harbour picture is seen on deck | Artistic recommendation |
| 6 | Chart markers look the same by day and by night | Artistic recommendation |
| 7 | The brass star of a special harbour is small | Artistic recommendation |
| 8 | The companions' stretching pose sits higher in its canvas | No action needed |
| 9 | Boat ids differ from the boats' names | No action needed |
| 10 | Styles, scale, blur and transparency across the game | No action needed |
| 11 | Duplicates and missing pictures | No action needed |
| 12 | Pictures the game does not show | No action needed |

## Findings

### 1. Fender shadows touch the canvas edge (Confirmed technical issue)

- **Files:** `assets/vessels/arctic_wanderer_26/illustrated/deck/deck_base.png`
  (soft shadow reaches the bottom row, alpha up to 55 of 255) and
  `assets/vessels/starling_33/illustrated/deck/deck_details.png` (alpha up to 13).
- **What:** the fenders hang near the bottom of the canvas, and their soft
  shadow is cut off by the canvas edge. All other layers keep a margin.
- **In play:** not visible. The boat is drawn at about 0.4x, the cut is in the
  faint part of the shadow, and at the quay it falls on the water beside the
  pontoon ([boat_arctic_wanderer_26_moored.png](previews/boat_arctic_wanderer_26_moored.png)).
- **Evidence:** [review/fender_shadow_canvas_edge.png](review/fender_shadow_canvas_edge.png).
- **Suggestion:** if these boats are ever repainted, move the fenders a few
  pixels up in the painter (`tools/vessels/paint_illustrated_vessel.py`,
  `paint_illustrated_starling.py`). Not worth a repaint on its own.

### 2. The HUD's deck symbol (Minor visual inconsistency)

- **Files:** `src/ui/hud.tscn` and `src/ui/pause_menu.tscn` use
  `assets/branding/next_harbor_symbol.svg`; the main menu, loading screen and
  icon use the Little Captain's Hat set.
- **What:** the small sailboat in the deck panel comes from the game's earlier
  name. It suits the panel (a boat for "Deck"), but its cream sail almost
  disappears on the cream panel.
- **Evidence:** [review/hud_symbol.png](review/hud_symbol.png) (the panel at 2x
  and both symbols).
- **Suggestion:** the Captain may prefer the hat symbol there, or a darker sail.
  Keeping the old symbol is allowed: the Visual Identity report keeps the
  `next_harbor_*` files on purpose.

### 3. Harbour pictures not equally centred (Minor visual inconsistency)

- **Files:** `assets/harbours/looks/*.png` and the six special pictures, all
  2300 x 220.
- **What:** the game draws each strip once, centred on the quay
  (`harbour_dressing.gd`). Some fill the width (volcanic island, Jamestown,
  the Skala, Grand Harbour); others leave an empty band on the right, up to 100
  px for `nordic_timber.png` and `nyhavn.png` (about 4 %), so their houses sit
  slightly left of the quay's centre.
- **Evidence:** the right-hand ends of the strips on the
  [harbours sheet](contact_sheets/harbours_contact_sheet.png).
- **Suggestion:** none needed; the pontoon and the boat cover the centre. If
  the strips are repainted, a symmetric margin would make them line up.

### 4. Harbour illustrations simpler than the rest (Artistic recommendation)

- The boats, fish and companions have shading, soft shadows and texture; the
  harbour strips are flatter, with repeated house shapes (see the
  [harbours sheet](contact_sheets/harbours_contact_sheet.png) next to the
  [boats](contact_sheets/boats_contact_sheet.png)). They are consistent with
  each other, and they read well at play size.
- A richer pass would be a job for the Sprite Workshop (artist-made
  replacements), not for this inspection.

### 5. Only the top band of a harbour shows on deck (Artistic recommendation)

- The strip sits beyond the quay at the screen's edge, so in play mostly the
  roofs and upper storeys are seen (for example
  [deck_special_copenhagen.png](../screenshots/i021/deck_special_copenhagen.png)).
  The whole strip is seen on the arrival card. Painting detail into the lower
  part of a strip is therefore mostly seen on the arrival card only.

### 6. Chart markers by day and by night (Artistic recommendation)

- The chart keeps its colours at night; the Harbor Dusk theme changes the
  panels around it. The day and night crops on the
  [chart symbols sheet](contact_sheets/chart_symbols_contact_sheet.png) are
  therefore alike. This is the design of the Chartroom pass, and the markers
  are readable in both.

### 7. The special harbour star is small (Artistic recommendation)

- The brass star (`_draw_special_star`) is a little smaller than the harbour
  dot and sits beside it (see Valletta and Copenhagen on the chart sheet). It is
  meant to be a quiet hint; a Captain who wants it easier to spot could ask for
  it a little larger.

### 8. The stretching pose sits higher (No action needed)

- In both companions, `stretching.png` ends about 18 px higher in its 256 px
  canvas than the other three poses (which end at y = 219 to 223).
- It is the raised hind end of the stretch, and the companion is drawn at
  72 units, so the shift is about 5 units. If it ever looks like a hop when the
  pose changes, `CompanionPoseArt.offset` can correct it without touching the
  art.
- **Evidence:** [review/companion_baselines.png](review/companion_baselines.png).

### 9. Boat ids and names (No action needed)

- `starling_33`, `petrel_36` and `halcyon_40` are shown as Wing 33, Frogleap 36
  and Clam 40. The folders keep the ids so saves and paths stay valid. The
  sheets give both.

### 10. Style, scale, blur, transparency (No action needed)

- **Style:** the fish (one painter), the companions (one painter) and the four
  boats (one toolkit, `tools/vessels/illustrate.py`) are each consistent: same
  ink outline, the same kind of soft shadow and colour wash. Cabin things,
  chart markers and the hat are drawn in code in the same flat-ink manner.
- **Scale and blur:** every PNG is drawn smaller than its file (boats about
  0.4x, companions 256 to 72, harbour strips 2300 to 1150 wide, fish
  portraits fitted into about 420 x 230), so nothing is enlarged or blurred in play.
  Code-drawn art is drawn at screen resolution.
- **Transparency:** every game PNG with a transparent background has clean
  alpha (fully clear around the drawing, the full range from 0 to 255 inside
  it); nothing sits on an unintended solid background. The templates are opaque
  on purpose.
- **Aspect ratios:** all layers of a boat share one canvas; all fish 512 x 256
  (thumbs 128 x 64); all companions 256 x 256; all harbour strips 2300 x 220.
  Fish thumbs fill the width (0 to 2 px margin); the junk thumbs are centred
  with side margins because the junk is not long and thin.
- **Labels:** chart names are outlined and readable on land and water, by day
  and by night (chart symbols sheet).

### 11. Duplicates and missing pictures (No action needed)

- No two game pictures are byte-identical.
- No picture is missing: every tile on all six sheets was found, and
  `tools/qa/check_game_content.py` (which checks every `res://` path) passes.

### 12. Pictures the game does not show (No action needed)

- `Visuals/Cat/*.png` (four 1254 x 1254 opaque drawings): the Captain's own
  originals, kept on purpose and never to be changed.
- `assets/vessels/*/templates/*.png`: painting guides (no Arctic Wanderer set;
  `render_art_templates.tscn` can make one).
- `assets/vessels/starling_33/demo/deck/coachroof.png`: a test picture for the
  Sprite Workshop's replacement rule (`test_vessels`).
- `assets/branding/next_harbor_*`: the earlier brand, kept for history (one
  symbol is still in use, finding 2).
- `data/navigation/**/navmask.png`: chart routing data, not pictures.

## Not rendered on the sheets

Nothing had to be imitated. These are documented in the catalogue but not on a
sheet, because they move or depend on the moment: weather (wind streaks, rain),
light of the hour and anchor ambience, water life, the player, the hat, the
anchor ball and light, wear and damage, the haul-out picture, the cabin's food
stores and world map (visible in the cabin screenshots), the chart's wind
arrows, weather legend and anchorage overlay.
