# Art direction: Real Horizon

*Illustrated Mariner × Atmospheric Sailing Simulator. Visual realism 7/10.*

This fork of Little Captain's Hat replaces the warm storybook look with a
grounded, atmospheric one: a cruising yacht on a grey-blue sea, drawn by a
maritime illustrator. Gameplay is unchanged; only presentation moved.

## The picture we are making

- **The sea is the main character.** Restrained blues and blue-greens, slow
  depth variation, wave shading that follows the wind, haze towards the edges.
  Calm water is glassy; a gale is dark, streaked and busy.
- **Boats are real cruising yachts.** Weathered white fibreglass with grey
  non-skid, teak only where yachts carry it (cockpit seats and soles),
  brushed-steel fittings, lifelines on stanchions, sprayhoods, real sail
  shapes. A 26-footer looks plain and practical; a 40-foot catamaran looks
  roomy and expensive.
- **Cabins are liveable.** Dark marine timber, pale headlining, compact
  galleys, a real chart table, berths with fitted cushions, restrained warm
  light at night.
- **Harbours are places.** Regional architecture and materials: tarred timber
  and red/ochre boathouses in Scandinavia, granite and slate on the Atlantic,
  stucco and terracotta in the Mediterranean. Believable proportions.
- **Instruments, not ornaments.** The interface is a modern multifunction
  display: charcoal-navy glass, white figures, functional cyan, amber for
  warnings, hairline separators, 2–4 px corners.

## Palette

The values live in `src/art/marine_palette.gd` (GDScript) and
`tools/art/marine_palette.py` (painters). Use the role, not a new hex.

| Role | Hex | Role | Hex |
|---|---|---|---|
| Deep sea | `#294653` | Marine white (fibreglass) | `#D8D9D2` |
| Open water | `#527887` | Brushed steel | `#77888C` |
| Coastal water | `#638C8B` | Weathered teak | `#887663` |
| Overcast sky | `#A4B4BA` | Dark marine timber | `#665646` |
| Sea haze | `#CBD3D0` | Electronic panels | `#202D35` |
| Instrument cyan | `#5AA8B8` | Warning amber | `#D49A4B` |

Light is applied on top of materials (BoatLighting, SeaSurface): never paint
a sunset into a texture. Sun is near-neutral white; dusk is a soft rose-grey,
not amber; night is a deep blue-grey with warm lamps and cool LED instruments.

## Drawing rules

- **Line:** thin, dark blue-grey (`#2A3236`), low opacity, almost straight.
  No doubled "quick pen" lines, no bold cartoon outlines. Edges come mainly
  from tone (a lit edge and a shadow edge), as in a gouache illustration.
- **Shading:** light from the upper left, soft cast shadows down-right,
  restrained. Gentle material texture (non-skid dots, wood grain, sailcloth
  panels) at a scale that reads at 1×.
- **Colour:** natural and subdued. Saturation comes from small accents (a red
  ensign, a yellow buoy, an orange fender, nav lights), never whole surfaces.
- **Proportion:** real objects at real sizes. A scene unit is about 2.5 cm;
  the captain is 40 units across the shoulders.
- **Avoid:** parchment, brass frames, toy-round buttons, hand-lettered UI,
  glossy photo textures, 3D renders, global desaturation filters.

## Interface

- Panels: `surface` (charcoal navy) with a 1 px `border`; HUD panels are
  slightly translucent glass.
- Typography: Barlow for body and figures; Barlow Condensed for headings and
  instrument captions.
- Accent: cyan for the active/selected element and data highlights; amber
  only for warnings and cautions; green only for success.
- The day mood is a sunlit display; the night mood is the same layout dimmed.

## Replacing the art (unchanged pipeline)

Everything here is provisional art made by generators. The creator's own
drawings always win: `art_replacements/` (ArtworkResolver, READY rows) takes
priority over the generated files in `assets/`, and the generated files keep
the same paths, canvases and ids. See [SPRITES.md](SPRITES.md) and
[VESSEL_ART.md](VESSEL_ART.md). Generators:

| What | Generator |
|---|---|
| Boat decks and cabins | `tools/vessels/paint_illustrated_vessel.py`, `paint_illustrated_starling.py` (toolkit `illustrate.py`) |
| Sea surface | `src/water/sea_surface.gd` + `src/water/sea_surface.gdshader` (runtime) |
| Harbour quays and towns | `src/harbour/harbour_dressing.gd` (runtime, regional archetypes) |
| UI | `src/ui/theme/ui_theme.gd` (role palette) |
