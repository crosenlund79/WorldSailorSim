# Operation Real Horizon: report

*Illustrated Mariner × Atmospheric Sailing Simulator. Visual realism 7/10.*

A visual-only conversion of Little Captain's Hat in this experimental
repository. Gameplay, data, saves and the creator-art pipeline are unchanged.
The art direction is in [DEV_GUIDES/ART_DIRECTION.md](../../../DEV_GUIDES/ART_DIRECTION.md).

## What was transformed

| Area | Now |
|---|---|
| Palette | `src/art/marine_palette.gd` (+ `tools/art/marine_palette.py`): natural sea, fibreglass, steel, weathered teak, charcoal-navy electronics, cyan, amber |
| Interface | `UiTheme`: marine-electronics panels, hairline borders, 3 px corners, Barlow Condensed headings; dimmed night mode. Instrument dials (reel, sail trim, radar, plotter, anchor set gauge), voyage overview, haul-out schematic, pictograms (`src/ui/instrument_draw.gd`) |
| Sea and weather | `SeaSurface` shader on every deck: wind-oriented swell and chop, depth and tone variation, harbour shelter, whitecaps and foam streaks from ~18 kn, rain dimpling, sun glints; quieter wind streaks and rain; cooler dawn/dusk/night and blue-grey overcast light |
| Boats | All four repainted: white topsides with rubbing strake, grey non-skid decks, weathered teak only in cockpits, steel fittings, smoked acrylic, sprayhood, practical deck gear. Sails: white Dacron with panel seams, belly shading and a cast shadow; anodised boom; navy sail cover |
| Cabins | Teak-and-holly sole, varnished marine-timber joinery, slate upholstery, made-up berths, solid-surface galley, chart table with repeater; stores locker, chart print, steel hat hook, blue gas flames, red night-vision chart light |
| Harbours | Floating pontoon (galvanised edge, rubbing strip, shore power), aluminium passerelle, marina signage, four regional archetypes (Nordic, Atlantic, Mediterranean, tropical) for quay, town roofs, trees and the neighbours moored across the fairway; Nyhavn repainted from above |
| Chart | Chartplotter dusk palette: slate water, khaki land, pale coastline, magenta route, cyan waypoints; muted Dreamer's Map |
| People and animals | Captain in a softshell jacket and lifejacket; cat and dog naturalistic; hat toned down |
| Fish | 16 species and 3 junk items as field-guide plates (same layers, pivots and data) |
| Title and loading | Painted overcast-sea title scene (day and night), restrained wordmark logo and icon |

## Screenshots

All in [`docs/screenshots/real_horizon/`](../../screenshots/real_horizon/), from the running game
(`tests/screenshots_horizon.tscn`): title, harbour by day, cabin by day and night,
chart, under way in light air / fresh breeze / gale / dusk / night, every boat under
way, sail trim, an arrival in Kiel (generic Nordic harbour), radar and plotter,
Go Ashore, the reel and the voyage overview.

## Unfinished

- The **Classic** artwork setting still shows the old procedural placeholder art (it
  is the fallback the creator pipeline keeps; the default is the new look).
- Harbour towns are generated per archetype; only Copenhagen has a landmark.
- The neighbours across the fairway are simple and only partly in view on the larger boats.
- Weather has no cloud-cover simulation, so "overcast" is derived from the weather class.

## Mechanics and compatibility

- No gameplay rule, data value, save field or collision changed. Visual-only data
  changes: sailcloth colours in `data/harbours/trades/trades.json`.
- Creator art untouched: `Visuals/` and `art_replacements/` were not modified; every
  generated file keeps its path, canvas and id, so ArtworkResolver replacements still win.
- Tests: 4704 checks; style assertions updated for the new fonts and the new guide.
