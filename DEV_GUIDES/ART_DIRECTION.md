# Art direction: Real Horizon

**Illustrated sailing realism. Cozy at heart.** About 7/10 realism, entirely 2D.

The official look of Little Captain's Hat (made official at the Great
Handover): a cruising yacht on a grey-blue sea, drawn by a maritime
illustrator. It is more believable and mature than the old storybook look,
and it must still feel cozy: calm pacing, a warm, welcoming life aboard,
small discoveries. Do not drift back toward the storybook look; do not push
toward photorealism for its own sake. Cozy first, less is more.

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
- **Proportion:** real objects at real sizes. A scene unit is about 1 cm
  (measured on the boats as painted in I025: the Starling 33's hull is 1000
  units for 10 m); the captain is 40 units across the shoulders. Harbour
  houses, quay fittings and neighbouring boats use the same scale
  (`HarbourDressing.METRE`); cabin interiors are painted by the shared
  `tools/vessels/cabin_joinery.py` (see `VESSEL_ART.md`).
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

The generated art is approved by the Captain; it does not automatically need
replacing. Generators overwrite their outputs, so re-run one only when a task
asks for that art to change, and never over a layer the Captain has replaced. The creator's own
drawings always win: `art_replacements/` (ArtworkResolver, READY rows) takes
priority over the generated files in `assets/`, and the generated files keep
the same paths, canvases and ids. See [SPRITES.md](SPRITES.md) and
[VESSEL_ART.md](VESSEL_ART.md). Generators:

| What | Generator |
|---|---|
| Boat decks and cabins | `tools/vessels/paint_illustrated_vessel.py`, `paint_illustrated_starling.py` (toolkit `illustrate.py`) |
| Sea surface | `src/water/sea_surface.gd` + `src/water/sea_surface.gdshader` (runtime) |
| Harbour quays and towns | `src/harbour/harbour_dressing.gd` (runtime, regional archetypes) |
| Harbour looks and special harbours (I021) | `tools/harbours/paint_harbour_looks.py`, `tools/harbours/paint_copenhagen_landmark.py` |
| Fish | `tools/fishing/paint_fish.py` |
| Companions (Ragdoll, Pug, parrot; animated clips, I024) | `tools/companions/paint_companion_clips.py` |
| Achievement badges (I024) | `tools/achievements/paint_badges.py` |
| Cabin laptop (I024) | `src/boat/laptop_prop.gd`, `src/ui/laptop/laptop_view.gd` (drawn at runtime) |
| Title scene and logo | `tools/branding/paint_title_scene.py`, `tools/branding/make_horizon_branding.py` |
| UI | `src/ui/theme/ui_theme.gd` (role palette) |
