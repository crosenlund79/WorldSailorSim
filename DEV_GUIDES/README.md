# Developer guides

Practical, step-by-step instructions for working on Little Captain's Hat's
(developed as Next Harbor until Iteration 006) assets and
systems. These guides are the manual for day-to-day development: replacing
artwork, adding companion poses, changing sounds. Each guide uses the real
paths in this repository.

You can also read them inside the game. In a development build (run from the
Godot editor, or with `godot --path .`), the main menu has a **Developer guides**
button in the top-right corner. It shows these same files, so there is only one
version of each guide.

## The guides

| Guide | Read it when you want to… | Applies to |
|---|---|---|
| [ART_DIRECTION.md](ART_DIRECTION.md) | understand the Real Horizon look (illustrated mariner, modern marine electronics): the palette, drawing rules, the interface style and which generator makes which art | `src/art/`, `src/ui/theme/`, `tools/` |
| [SPRITES.md](SPRITES.md) | replace any artwork with a PNG: formats, transparency, import settings, sizes, alignment, fallback, common mistakes. Since 0.105b the no-code way is the Sprite Workshop: `art_replacements/README_START_HERE.md` | all sprites, `art_replacements/` |
| [COMPANION_ANIMATION.md](COMPANION_ANIMATION.md) | change the cat's and the dog's poses, adjust their placement, repaint them or switch back to your own drawings | `assets/companions/`, `Visuals/Cat/`, `data/companions/` |
| [VESSEL_ART.md](VESSEL_ART.md) | draw a boat's deck, cabin or sails, damage overlays and the provisions display; use the art templates; understand layouts, visual profiles and slots | `assets/vessels/`, `src/vessels/`, `data/vessels/` |
| [AUDIO.md](AUDIO.md) | replace a sound (purr, engine, storm wind, thunder, ambience, clicks); understand the audio buses | `assets/audio/` |
| [WEATHER.md](WEATHER.md) | tune where gales, thunderstorms and cyclones form, hazard levels, warnings and weather damage; restyle the chart's weather; use the F9 developer test tools and weather fixtures | `data/weather/`, `src/weather/`, `src/dev/` |
| [CAPTAINS_HAT.md](CAPTAINS_HAT.md) | replace the captain's hat drawings, move its hook aboard, tune how wind takes it and what a replacement costs | `assets/hat/`, `data/hat/`, `src/hat/` |
| [HARBOURS.md](HARBOURS.md) | give a harbour or take away a service (grocery, boatyard, haul-out, Go Ashore), set its tier, add a harbour, understand the gangplank and shore on every boat, add a Go Ashore event | `data/harbours/facilities/`, `src/harbour/` |
| [BOAT_CARE.md](BOAT_CARE.md) | tune how the boat wears, the boatyard's services, prices and times, the haul-out, the equipment catalogue and Passage Readiness | `data/boat/`, `src/boat_care/`, `src/ui/boat_care_menu.gd` |
| [CHART_REGIONS.md](CHART_REGIONS.md) | rebuild the detailed Danish chart from its sources, understand regions and level of detail, add another region | `data/navigation/regions/`, `tools/navigation/build_region.py` |
| [LIFE_ABOARD.md](LIFE_ABOARD.md) | tune the fish, lures and trophies, the reel dial, grades and keeping, sharks and junk, the galley's dishes, morning coffee, the anchorage model, anchorage waypoints, the anchor ball and light, life at anchor and the companion on deck; find the rod, stove, windlass and trophy board | `data/fishing/`, `src/fishing/`, `src/galley/`, `src/anchor/`, `src/aboard/` |
| [MODDING_FUTURE.md](MODDING_FUTURE.md) | keep the project open for user content later (no mod support exists) | design principles |

## Where things belong

| What | Where |
|---|---|
| Your original companion drawings | `Visuals/Cat/` (kept; a `Dog` folder next to it for your own dog) |
| Vessel sprites (deck and cabin layers) | `assets/vessels/<vessel_id>/deck/` and `.../cabin/` |
| Art templates for drawing vessels (generated) | `assets/vessels/<vessel_id>/templates/` |
| Companion art (game, illustrated) | `assets/companions/cat/`, `assets/companions/dog/` |
| Companion pose configuration | `data/companions/cat_visuals.tres`, `data/companions/dog_visuals.tres` |
| Fish, lures and rarities | `data/fishing/fishing.json` |
| Vessel definitions and visual profiles | `data/vessels/` |
| Sounds | `assets/audio/` (the current ones are placeholders in `assets/audio/placeholder/`) |
| Weather data (zones, seasons, cyclone basins) | `data/weather/weather_events.json` |
| Captain's hat drawings and balancing | `assets/hat/`, `data/hat/hat_art.tres`, `data/hat/hat_config.json` |
| Equipment catalogue (boat care) | `data/boat/equipment.json` |
| Detailed chart regions | `data/navigation/regions.json`, `data/navigation/regions/` |
| Harbour services and tiers | `data/harbours/facilities/` |

`<vessel_id>` is `arctic_wanderer_26` (the starter monohull), `starling_33`
(Wing 33, monohull), `halcyon_40` (Clam 40, catamaran) or `petrel_36`
(Frogleap 36, trimaran).

## Finding the latest implementation documentation

- [../README.md](../README.md): what the game does, controls, how to run it.
- [../ARCHITECTURE.md](../docs/technical/ARCHITECTURE.md): how the code fits together (autoloads,
  scenes, state, saves, weather, vessels, visuals, audio, tests).
- `ITERATION_*_REPORT.md` in the project root: what each iteration built and
  verified. The newest one is the most current.
- The scripts have doc comments (`##`) at the top of each file.

## Keeping the guides correct

**Rule:** whenever an iteration changes an asset workflow or a system described
here, the matching guide is updated **in the same iteration**. Instructions live
in one place only:
- `docs/artwork/ART_PIPELINE.md` in the root only points here;
- the reports describe what changed, not how to do things.

The automated tests check that every repository path written in backticks in
these guides exists (`tests/suites/test_dev_guides.gd`), so a renamed file is
noticed.
