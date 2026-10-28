# Little Captain's Hat: Architecture

The game was developed as Next Harbor until Iteration 006; older parts of this
document and the iteration reports use that name.

This document describes how the game is put together (as of Iteration 004)
and where future systems are meant to plug in. It is kept short on purpose; the scripts have
doc comments for details.

## Guiding rules

- **State lives in plain data, not in scenes.** `GameSession` owns a
  `SessionState` object. Scenes read it and request changes; they never *are* the state.
- **Requests go up as signals, services are called down.** Screens and menus emit
  signals; the application shell (`App`) reacts by calling services and switching screens.
- **One place per responsibility.** Scene switching, the modal menu stack, saving,
  settings and audio each have one owner.
- **One timeline.** Game time and vessel movement are advanced only by the
  `Simulation` service, never by scenes, menus or timers.
- **Navigation data is geographic.** Ports, routes, the vessel, weather and wind use
  WGS84 longitude/latitude; projection to the screen is a display concern.
- **One wind.** Every consumer (simulation, ETA, chart, HUD, sails) asks the same
  `WindField` query; presentation never decides propulsion.
- **No speculative systems.** Nothing exists yet for money, provisions, equipment
  and so on. The extension points below describe where they will go.

## Autoloads (6)

| Autoload | Script | Responsibility |
|---|---|---|
| `SettingsManager` | `src/settings/settings_manager.gd` | Preferences: load/validate/save `user://settings.cfg`, apply bus volumes, window mode, VSync, UI scale. |
| `AudioManager` | `src/audio/audio_manager.gd` | Music, looping ambience, named loops with fades (the engine), pooled one-shots (SFX/UI) on the right buses. Owns no game state. |
| `GameSession` | `src/core/game_session.gd` | Authoritative session state and its mutations, with change signals. |
| `Simulation` | `src/core/simulation.gd` | The single simulation timeline: advances the game clock and the active voyage, evaluates wind and propulsion at fixed evaluation points, assesses the weather (warnings, exposure) at the same points, detects arrival, sleeping, wind-aware ETAs. Pausable. |
| `SaveManager` | `src/persistence/save_manager.gd` | Save slots: JSON read/write, validation, metadata. Converts files ↔ `SessionState` only. |
| `SessionLog` | `src/diagnostics/session_log.gd` | The diagnostic session log (Visual Identity V01): one JSON Lines file per run in `user://diagnostics/`, meaningful events only, bounded, flushed per line. Reads the game, never changes it. |

Screen transitions are deliberately **not** an autoload: they belong to the
application shell, the only code that changes screens.

Dependency direction (no cycles): UI/screens → `App` (via signals) → services
(`GameSession`, `Simulation`, `SaveManager`, `SettingsManager`, `AudioManager`)
→ data classes and data services (`SessionState`, `PlannedRoute`, `Voyage`,
`PropulsionState`, `PortCatalog`, `SeaRouter`, `WeatherModel`, `WindField`,
`VesselProfile`, …). `Simulation` reads and writes
the session only through `GameSession`; `SaveManager` only converts files ↔
`SessionState`. `PortCatalog`, `SeaRouter`, `WeatherModel`, `WindField` and
`VesselProfile` are shared, lazily loaded data services (`get_default()`);
`GameSession` releases them on exit. `PropulsionController` is pure logic with no
state of its own.

## Scene architecture

```
App (src/app/app.tscn, main scene, PROCESS_MODE_ALWAYS)
├── Screen              ← exactly one screen at a time, PROCESS_MODE_PAUSABLE
│   └── MainMenu | Interior | Exterior | WorldMap
├── SceneRouter         ← swaps the screen with a fade (FadeLayer, layer 100)
├── HudLayer (10)       ← Hud, visible only in boat areas
├── ModalLayer (20)     ← ModalStack: pause, settings, save/load, sleep, boatyard, confirmations
└── ToastLayer (30)     ← Toasts (notifications)
```

- **`App`** (`src/app/app.gd`) is the flow coordinator: new game, continue, load,
  return to menu, quit, opening and closing the chart, area changes, the menus,
  departure confirmation, sleeping and showing simulation events (warnings, arrival).
  It wires each new screen's signals in a setup callback before the screen's `_ready`.
- **`SceneRouter`** (`src/app/scene_router.gd`) removes and frees the old screen
  *before* instantiating the new one, so there is never a second player or screen.
  It ignores requests while a transition is running and calls `begin_exit()` on the
  outgoing screen if it has one, which stops player input during the fade.
- Screens and menus are registered in `app.tscn` as exported `PackedScene`s. Boat
  areas come from the active `VesselDefinition`
  (`GameSession.get_vessel_definition().get_area_scene(area)`). Scripts contain no
  scene paths, except the shared data files `PortCatalog.DEFAULT_PATH` and
  `VesselCatalog.DEFAULT_PATH`.

### UI layers and scaling

All UI lives in `UiScaleLayer` CanvasLayers (`src/ui/ui_scale_layer.gd`). The layer
is scaled by the *Interface scale* setting and resizes its direct Control children
to `viewport / scale`, so anchors and containers keep working at any scale. The game
world is not scaled.

The shared look comes from one Theme, `assets/ui/next_harbor_theme.tres` (the file
keeps its old name), set as the project's custom theme. It is generated by
`tools/build_theme.gd` (palette, fonts, type variations such as `BigButton`,
`HudPanel`, `ToastPanel`, `SlotButton`). Edit the generator and re-run it rather
than hand-editing the `.tres`.

**Typography (Visual Identity V01).** Barlow is the default and functional
font. The display font, Patrick Hand, is used only through three type
variations defined in the generator: `DisplayTagline` (the title screen's
tagline), `DisplayHeader` (decorative headings: the Captain's Log title and its
section headings) and `DisplayName` (a found secret achievement's name). Each
is a `FontVariation` with Barlow as fallback for the few characters Patrick
Hand lacks (arrows). Numbers, wind, distances, money, provisions, settings and
long text never use it. Harbour signs drawn in the boat scenes use it through
their own `LabelSettings` (see *Harbour presentation*).

**Name, version and folder.** The window title and saves' `game_version`
come from `project.godot` (`application/config/name` "Little Captain's Hat",
`application/config/version` "0.102a"). `GameVersion`
(`src/app/game_version.gd`) holds the version in one place (a test keeps
`project.godot` equal to it), a numbers-only form for tools, and the commit
(from an optional `build_info.json` written by `tools/write_build_info.py`, or
read from `.git`; no git process at runtime). It is also the one source of
the **development build identifier** (`ITERATION`, `STAGE`, `CHANNEL`,
`build_label()` → `LCH · i024 · DEV · 1a2b3c4`): `BuildLabel`
(`src/ui/build_label.gd`) shows it in the window's bottom-right corner on
its own `UiScaleLayer` (layer 128, added once by `App`), above every screen,
ignoring the mouse; the project setting `application/config/show_build_label`
(overridden to false for an export with the `public_release` feature) hides
it. How the values change per checkpoint: the Captain's Orders, *Major
iteration branches*; checked by `tests/suites/test_build_label.gd`. The save format version
(`SaveManager.SAVE_VERSION`) is independent. `application/config/use_custom_user_dir`
with `custom_user_dir_name` "Little Captains Hat" fixes `user://`, so the old
Next Harbor folder is never written to; `LegacySaves` (`src/persistence/legacy_saves.gd`)
finds saves there and copies them into free slots on request
(`SaveManager.import_file()` never overwrites).

### Input ownership

- **Esc** (`pause` action) is handled only in `App._unhandled_input`:
  top modal → `handle_back()`; otherwise a boat area → open pause menu; otherwise
  the screen's `handle_back()` (the chart closes). No other node reads Esc.
- **E** (`interact`) is read by the `Player` in `_unhandled_input`, so a focused
  menu control consumes input first.
- While any modal is open over gameplay, `App` sets `get_tree().paused = true`.
  The screen is pausable, so movement and interaction stop; the shell, menus,
  toasts and audio run with `PROCESS_MODE_ALWAYS`.

## Game state ownership

`SessionState` (`src/core/session_state.gd`) is a plain `RefCounted` with:

| Field | Meaning |
|---|---|
| `boat_area` | `&"interior"` or `&"exterior"` |
| `player_position` / `has_player_position` | position in the area's local space |
| `spawn_point` | marker to use when there is no position (new game, after moving between areas) |
| `location_id` | port id where the boat lies; empty while underway |
| `planned_route` | `PlannedRoute` planned in port, or `null` |
| `game_time` | authoritative clock: seconds since the Unix epoch, UTC (float) |
| `time_scale` | 1, 5 or 20 |
| `paused` | the player paused the simulation clock (UI keeps working); resuming continues at `time_scale` |
| `vessel_status` | `moored`, `underway` or `arrived` |
| `vessel_position` | Vector2(lon, lat); while underway always derived from the voyage |
| `propulsion` | `PropulsionState`: sail/engine mode, reason, speed, the controller's average and timers, last wind and angle, spinnaker |
| `wind_seed` | seed of the deterministic wind field (1 for every game so far) |
| `companion` | `CompanionState`: the ship's companion (kind, resting spot, schedule) |
| `voyage` | `Voyage` while underway, else `null` |
| `funds` | euros (int, never negative); a new game has 10,000 |
| `provisions` | `Provisions`: food and water in days, the warning already given |
| `vessel_conditions` | each boat's condition in % by vessel id; a missing id is 100 |
| `damage_applied_until` | weather damage has been applied up to this game time |
| `rescue_count` / `last_rescue` | rescues so far and the last one (time, fee, funds after, from where) |
| `hat` | `HatState`: the player's captain's hat (stored, worn, carried or lost), its wind strain, warning, checks, counts and history (Visual Identity V01) |

`GameSession` is the only writer. It exposes intent-level methods
(`start_new_session`, `enter_boat_area`, `set_player_position`, `plan_route_to`,
`set_planned_route`, `clear_planned_route`, `depart`, `change_course`,
`set_time_scale`, `replace_state`), hooks used only by `Simulation`
(`apply_simulation_step`, `set_propulsion`, `complete_voyage`,
`record_weather_warning`) and signals (`boat_area_changed`, `route_changed`,
`voyage_started`, `voyage_course_changed`, `voyage_arrived`, `propulsion_changed`,
`time_scale_changed`, `state_replaced`, `notice`, …). Read-only accessors for
presentation: `get_vessel_speed_kn()`, `get_propulsion()` (a copy), `is_motoring()`,
`are_sails_set()`, `get_vessel_profile()`, `get_wind_seed()`. Every
request that could break the rules (an unvalidated route, departing without a
course) is refused with a reason string instead of applied. `get_planned_route()` and
`get_state_snapshot()` return copies, so callers cannot modify state behind its back.
`has_unsaved_changes()` drives the "progress will be lost" confirmations.

The active `BoatArea` writes the player's position to `GameSession` every physics
frame. The session therefore always has the current position, even while the
chart is open and no boat scene exists.

## Boat scenes, player and interactions

- Each vessel has a deck (`Exterior`) and a cabin (`Interior`) scene in
  `src/vessels/<id>/`, both using `BoatArea` (`boat_area.gd`). Every one of them has
  the same structure (see *Vessels and the boatyard*):

  ```
  Exterior / Interior (BoatArea)
    Surroundings (deck: water, Mooring) | Backdrop (cabin: darkness)
    Visual       instance of the vessel's art-only scene (VesselVisual)
    Layout
      Collision        BoatFixture shapes, hull boundary (CollisionPolygon2D, segments)
      Stations         Interactables (companionway, helm, boatyard | nav_table, bed)
      SpawnPoints      Marker2D per spawn id
      SailMarkers      (deck) Mast, Tack, BoomEnd, Traveller, JibSheetLead, SpinnakerSheetLead
      CompanionSpots   (cabin) Marker2D per resting spot id
    SailRig (deck) | Companion (cabin)
    Player, Camera2D
  ```

- On `_ready`, `BoatArea` does the following:
  - it applies the active vessel's visual profile to `Visual` and the `SailRig`;
  - it places the player from the session (the saved position, or the named spawn
    under `Layout/SpawnPoints`; a restored position outside `walkable_bounds` falls
    back to the default spawn);
  - it connects every `Interactable` and starts the area's ambience.
- `BoatFixture` (`boat_fixture.gd`, `@tool`) is **collision only**: one rectangle or
  convex polygon, with `solid = false` for walkable things. It draws an outline in
  the editor and nothing in the game. Hull boundaries are `CollisionPolygon2D` in
  segment mode. **Collision is never derived from art.**
- `Player` (`src/player/`) is a `CharacterBody2D` (floating motion) using
  `Input.get_vector`, which normalizes diagonals. Physics layers: 1 world, 2 player,
  3 interactables.
- **Interaction framework** (`src/interaction/`):
  - `Interactable` (`Area2D`, layer 3): `interaction_id`, `prompt`, optional `message`,
    `enabled`, highlight of its parent while focused. It only emits `interacted`.
  - `InteractionSensor` (`Area2D` on the player) keeps one focused interactable, and
    E always uses that same one (the prompt is the action). `choose()` picks the
    nearest by centre distance, with ties broken by node name. Each step of
    `Interactable.focus_priority` below another counts as 60 px more distance.
    Stations, doors and the berth have priority 0, so among them nothing changed.
    The companion has −1, so a resting cat never takes the focus from the
    station the player stands at (October 24 playtest). When the player *faces*
    the companion (within ~45° of the facing arrow) that margin becomes a bonus,
    so turning to the cat pets it.
  - `BoatArea` routes by id:
    - `companionway` → `area_change_requested`;
    - `nav_table` → `chart_requested`;
    - `bed` → `sleep_requested`;
    - `helm` → `helm_requested` (App: depart, or report the autopilot course);
    - `boatyard` → `boatyard_requested` (App opens the boatyard);
    - `provisions` → `provisions_requested` (App opens the provisions panel);
    - `pet` → the companion;
    - anything with a `message` → notification.

    Stations have an empty `highlight_target`: the focused one draws a brass ring
    sized from its shape, so the feedback does not depend on the art. The
    boatyard station is enabled and visible only while `can_change_vessel()`.
  - The deck's `mooring` node (pontoon, lines, port name) is visible only in port.
    A new "flavour" object therefore needs no code, only an `Interactable` with a message.
- **Sail rig** (`src/boat/sail_rig.gd`, `SailRig` on deck, z below the player and
  labels). Its attachment points come from the deck's `Layout/SailMarkers` (the
  starter sloop's constants are only a fallback); the jib foot is mast→tack, and the
  spinnaker pole (×0.94) and depth (×1.945) scale with it. It draws the mainsail on its boom, the jib and the spinnaker
  from `GameSession.get_propulsion()` every frame. Sails lie to leeward
  (wind from starboard → sails to port; the deck has the bow at +x, port at −y).
  Boom angle = clamp(|twa| × 0.55 − 17°, 5°, 50°); jib = clamp(|twa| × 0.4 − 10°,
  6°, 38°). Motoring or in port, the main is furled on the boom (sail cover) and
  the jib rolled on the forestay. The spinnaker is drawn whenever the state says
  so: a crescent forward of the mast and beyond the bow, pole to windward, sheeted
  to the leeward quarter, swung to leeward on a broad reach and centred dead
  downwind; the jib is rolled away while it flies. Trim eases towards its target
  (time constant ≈ 0.6 s) and the spinnaker hoists/drops over ≈ 1.2 s; on entering
  the scene the rig snaps to the current state, so it never depends on which scene
  was open when the state changed.
  - **Geometry** (Iteration 003b) lives in `get_shape(time)`, which draws and tests
    share. The spinnaker hangs from coherent rigging points:
    - the **tack** is at the end of the pole from the mast (270 units on the
      Starling), 22° (reach) to 58° (run) to windward;
    - the **clew** is sheeted to the leeward quarter;
    - the **head** is joined to the mast by the halyard line;
    - the leading edge bellies 560 units forward of the tack–clew line (≈ x 680,
      the bow is at 500).

    While it flies, the deck camera eases 110 units forward so the whole sail stays
    in view.
  - **Motion** is cosmetic and runs on real time. Values are amplitudes at full set:

    | Sail | Angle | Fullness | Other |
    |---|---|---|---|
    | Mainsail | ±0.8° at 0.13 Hz | ±6 % at 0.21 Hz | leech ripple ≈ 1 px |
    | Jib | ±1.2° | ±8 % | leech ripple 2 px |
    | Spinnaker | swing ±2.5° | ±7 % | clew ±6 px |

    All motion scales with `set_amount` / `spinnaker_amount`, so furled sails do
    not move. It is never read by the simulation: speed and propulsion come only
    from `PropulsionState`.
- **Helm** (`BoatArea`): its prompt is "Take the helm" in port (departure) and "Check
  sail configuration" underway, which calls `Simulation.reassess_propulsion()` (see
  *Propulsion controller*). `App.describe_reassessment()` turns the result into the
  message shown.
- **Ship's companion** (`src/companion/`):
  - `ShipCompanion` is a node in the cabin scene only, so exactly one exists and it
    never appears on deck or on the chart.
  - **Pose art (Iteration 004b).** A kind may have a `CompanionVisualSet`
    (`src/companion/companion_visual_set.gd`, data in
    `data/companions/<kind>_visuals.tres`, looked up by `PATH_PATTERN`). The set
    holds:
    - `CompanionPoseArt` entries: pose name → image path, plus per-pose offset,
      scale and flip;
    - placement: `display_size` and `pivot` of the shared canvas;
    - loading options and behaviour timings.

    The cat's set uses the owner's files in `Visuals/Cat/` directly.
  - **Image preparation.** Images are read through the imported texture and scaled
    to `max_texture_size`. Opaque images get their border-connected background
    removed (flood fill from the edges, soft rim), so drawings on white paper work
    and enclosed white fur stays. Results are cached statically; the source files
    are never changed.
  - **Pose behaviour** in `ShipCompanion`, presentation only and never saved, on
    real time:
    - resting 25–60 s, then a nap (`sleeping`, 60–150 s) or a `stretching` (2.6 s);
    - a short `alert` when the player's focus reaches a resting companion (at most
      every 20 s);
    - `alert` with hearts and the sound when petted;
    - 0.25 s cross-fades and a tiny breathing swell, never rotated.

    Missing pose images fall back to the resting image. Without a usable resting
    image, or without a set (the dog), the original procedural top-down drawing
    (rotated per spot) is used. See
    [DEV_GUIDES/COMPANION_ANIMATION.md](../../DEV_GUIDES/COMPANION_ANIMATION.md).
  - It reads kind and resting spot from `GameSession.get_companion()` and moves
    instantly on `companion_moved` and `state_replaced`.
  - It has no collision; its `Interactable` (id `pet`, prompt "Pet cat/dog") is
    routed by `BoatArea` to `pet()`. That plays a sound on the SFX bus (purr, or
    soft panting) and a 1.6 s reaction (hearts, or a wagging tail).
  - **Resting spots.** `CompanionState.SPOTS` holds only semantic ids per kind (cat:
    `settee`, `nav_station`, `v_berth`; dog: `cabin_floor`, `companionway`,
    `seating`).
    - Each cabin places a `Marker2D` with that name under `Layout/CompanionSpots`,
      so the spot survives a change of boat and its position belongs to the vessel.
      Tests check that every cabin has all six.
    - On the Starling the spots are chosen so that the chart table, berth, wake-up
      spot and companionway stay the focused interaction (tested).
    - The `preview` flag reuses the drawing (or resting image) in the New Game
      dialog.

## Vessels and the boatyard

- **`VesselDefinition`** (`src/vessels/vessel_definition.gd`, one `.tres` per boat in
  `data/vessels/`) is what a boat is:
  - `id`: stable, saved; never the display name or a path;
  - `display_name`, `hull_type` (monohull, catamaran or trimaran), `description` and
    `specs`;
  - `performance`: a `VesselProfile` in `data/vessel/`, with polar, engine and
    controller thresholds;
  - `deck_scene` and `cabin_scene`;
  - `deck_visual_scene`: art only, used for the boatyard preview;
  - `visual_profile`.
- **`VesselCatalog`** (`data/vessels/vessel_catalog.tres`) lists the boats; the first
  one is the starter (`VesselCatalog.STARTER_ID`, `arctic_wanderer_26` since 0.100b,
  `starling_33` before). `SessionState.vessel_id` defaults to it, so every new game
  starts aboard it; a loaded save always keeps the id it names (the v4→v5 migration
  names `starling_33` literally, the starter of that era).
- **Ids are stable, names are display only.** 0.100b renamed three boats without
  touching their ids: `starling_33` is shown as **Wing 33**, `halcyon_40` as **Clam 40**,
  `petrel_36` as **Frogleap 36**. Saves, the Captain's Log records and the tests use
  the ids; the UI reads `display_name` from the catalog.
- **`GameSession`** owns which boat is active (`SessionState.vessel_id`):
  - `get_vessel_definition()` and `get_vessel_profile()`: the Simulation, the
    propulsion controller, the ETA and the helm reassessment all read the active
    profile;
  - `can_change_vessel()`: moored in a port, not underway;
  - `switch_vessel(id)`: refuses underway, outside a harbour or for an unknown id.
    Otherwise it sets the id, resets the propulsion state (stale rolling averages
    from another hull must not carry over), enters the deck at `from_boatyard` and
    emits `vessel_changed`. The Simulation then drops its cached ETA.
- `App._show_current_boat_area()` takes the scene from the active definition, so a
  switch is just a scene change; there are never two boat areas. Time, harbour,
  companion and route plans are kept.
- **Boatyard** (`src/ui/boatyard_menu.*`, a `ModalPanel`):
  - It lists the catalog.
  - It previews `deck_visual_scene` in a `SubViewport`, with the profile applied and
    no gameplay nodes.
  - It shows name, hull type, description and specs.
  - Its comparison table comes from each profile: `compare_rows()` gives the top
    speed, `sail_speed_kn(12 kn, 45°/90°/150°)` and the engine speed.
  - **Move aboard** emits `vessel_chosen`, which `App.switch_vessel()` handles.
    `App.open_boatyard()` refuses underway.
  - Since Iteration 005b it has a **fixed size**, like the chart sidebar.
    `PANEL_SIZE` is 1180×860, made smaller only to fit a small window. The
    boat details sit beside the preview in a scroll area, so selecting another
    boat changes text, never the panel's size or the button positions (tested
    for every boat, at 100 % and 130 %).
  - Each boat's own condition is shown. The services row offers **Repair
    vessel** (free) for the boat you are aboard, and a **Grocery store…** button
    that opens the grocery store on top (Iteration 005c).

| Vessel | Hull | Top speed | 12 kn at 45° / 90° / 150° | Engine | Spinnaker from |
|---|---|---|---|---|---|
| Arctic Wanderer 26 (`arctic_wanderer_26`) | monohull | 8.0 kn | 2.0 / 5.3 / 5.2 kn | 5.0 kn | 115° |
| Wing 33 (`starling_33`) | monohull | 10.0 kn | 2.6 / 6.8 / 6.9 kn | 5.0 kn | 115° |
| Clam 40 (`halcyon_40`) | catamaran | 11.0 kn | 1.1 / 7.0 / 6.8 kn | 6.5 kn | 100° |
| Frogleap 36 (`petrel_36`) | trimaran | 14.0 kn | 5.2 / 10.6 / 10.2 kn | 5.5 kn | 120° |

### Visual layer (sprite-ready)

- **`VesselVisual`** (`src/boat/visuals/vessel_visual.gd`) is the root of each art
  scene (`deck_visual.tscn`, `cabin_visual.tscn`). Its `canvas` (`Rect2`, in scene
  units) is the area the art covers.
- **`VisualSlot`** nodes are the named slots:
  - **deck:** ShadowVisual, HullBase, DeckBase, Coachroof, DeckDetails,
    RiggingVisual, MastVisual;
  - **cabin:** CabinBase, FurnitureVisual, CabinDetails.

  A slot shows **either** its procedural children (`ProceduralShape`, `Polygon2D`,
  `Line2D`, labels) **or** one full-canvas `Sprite2D`. The sprite has its top-left
  at `canvas.position` and is scaled uniformly to the canvas width; another aspect
  ratio only logs a warning.
- **`VesselVisualProfile`** (`data/vessels/<id>_visuals.tres`) resolves each slot in
  a fixed order: the texture assigned in the profile, then
  `<art_folder>/<deck|cabin>/<file>.png`, then procedural. A missing file can
  therefore never break a boat. `procedural_only` forces placeholders.
- Boom and sails (BoomVisual, MainSailVisual, HeadSailVisual, SpinnakerVisual) are
  drawn by the `SailRig`. A sprite is stretched over the live sail outline as a
  triangle strip (`canvas_item_add_triangle_array` with UVs), so trim, belly and
  breathing still apply.
- Coordinates: +x bow, −y port, origin at the middle of the boat; templates at 2 px
  per unit. See [DEV_GUIDES/VESSEL_ART.md](../../DEV_GUIDES/VESSEL_ART.md).
- Tooling (`tools/vessels/`):
  - `build_multihull_scenes.py` bootstrapped the catamaran and trimaran scenes. It
    is a one-time generator and refuses to overwrite without `--force`.
  - `render_art_templates.tscn` draws the landmark templates.
  - `make_demo_coachroof.py` drew the demo sprite.

## Developer guides and tools

- **`DEV_GUIDES/`** holds the practical developer instructions (sprites, companion
  poses, vessel art, audio, future modding). It is the single source for "how to"
  instructions: `docs/artwork/ART_PIPELINE.md` only points there. **Rule:** a change to an asset
  workflow or a documented system updates the matching guide in the same
  iteration. `tests/suites/test_dev_guides.gd` checks the links and the
  repository paths the guides mention.
- **In-game viewer** (`src/ui/dev_guides_menu.*`, `src/dev/dev_guides.gd`,
  `src/ui/markdown_lite.gd`):
  - The main menu shows a small **Developer guides** button only when
    `DevGuides.is_available()`: a debug build, with `res://DEV_GUIDES/*.md`
    present. In practice that means running from the editor or with
    `godot --path .`.
  - Exported games do not contain the Markdown files (Godot exports only
    resources), and release builds never show the button.
  - The viewer reads the `.md` files as they are and converts them with a small
    Markdown → BBCode converter into a scrolling `RichTextLabel`. There is no
    second copy of the text.
- **Halcyon 40 cabin** is generated by `tools/vessels/build_multihull_scenes.py`
  from one furniture list (`cat_furniture()`), which yields both the
  `BoatFixture` collision and the `ProceduralShape` art. Matching positions and
  shapes are tested.
  - Iteration 005b reworked its proportions with the cabin's own numbers
    (`CAB`). The hull cabins are 152 units wide (was 100; ~80 units per metre at
    the player's scale), the berths are 160×132 and 146×124, and counters,
    settees and desks are 44 units deep (was 26). The exit has a lit doorway,
    larger chevrons and a TO DECK label beside it. The camera zoom is 1.2.
  - The art templates were re-rendered.
- **Developer test tools** (Iteration 005b; `src/dev/dev_tools.gd`,
  `src/dev/dev_test_panel.gd`):
  - Enabled only by `DevTools.is_enabled()`: a debug build of the editor binary
    (`OS.has_feature("editor")`), unless started with `-- --no-dev-tools`.
    Exported games never have it.
  - **F10** (`App.toggle_dev_tests()`; F9 until Iteration 16) or the pause menu's button (added only
    when enabled) opens `DevTestPanel`.
  - It acts on the real game through public APIs:
    - weather scenarios are `WeatherFixtures` events in the one `WeatherModel`
      (a gale or severe storm at the boat, a severe squall cell, a storm 20 nm
      ahead on the course), at full strength at once;
    - condition presets go through `GameSession.set_condition_for_testing()`
      (never 0: losing the boat is left to the real damage path);
    - the rescue test sets 1 % and a storm, so the real damage and rescue
      follow;
    - stores and time go through `Simulation.advance()`.
  - Test weather is not session state: it is never saved, and
    `DevTools.on_session_changed()` removes it on new game, load and end.
  - `src/dev/weather_fixtures.gd` (moved from `tests/helpers/`) is shared by
    the tests and these tools.

## Map data structures

| Piece | File | Notes |
|---|---|---|
| `PortData` (Resource) | `src/navigation/port_data.gd`, `data/navigation/ports/*.tres` | stable `id`, name, country, latitude/longitude (WGS84), description |
| `PortCatalog` (Resource) | `port_catalog.gd`, `data/navigation/port_catalog.tres` | the 15 ports; `get_default()` is the shared instance |
| `PlannedRoute` | `planned_route.gd` | origin (port id or position at sea), destination, user waypoints, the calculated `path` and the waypoint indices in it |
| `Voyage` | `voyage.gd` | the route being sailed, `progress_nm`, course `revision`, warned weather keys |
| `VesselProfile` (Resource) | `vessel_profile.gd`, `data/vessel/starter_sloop.tres` | sailing performance (polar), spinnaker, engine speed and all propulsion-controller thresholds |
| `PropulsionState` / `PropulsionController` | `src/sailing/` | the saved sail/engine state and the pure decision logic |
| `WindField` | `src/weather/wind_field.gd`, `data/weather/wind_climate.json` | deterministic background wind for any position and time (read only through `WeatherModel`) |
| `GeoMath` | `geo_math.gd` | rhumb-line distance/interpolation, great-circle distance, formatting |
| `MapProjection` | `map_projection.gd` | spherical Mercator, geo ↔ chart map units (display) |
| `NavGrid` | `nav_grid.gd`, `data/navigation/europe_navmask.png/.json` | navigability raster and exact line checks |
| `SeaRouter` | `sea_router.gd`, `data/navigation/europe_route_graph.json` | route calculation and validation |
| Coastlines | `data/navigation/europe_land.json` | Natural Earth 10m land, clipped to Europe, simplified; whole rings plus fill tiles; chart labels |
| `WeatherModel`, `WeatherEvent`, `WeatherSample`, `WeatherExposure` | `src/weather/`, `data/weather/weather_events.json` | the one weather model: moving events, samples with gusts and hazard, the exposure record (see *Weather model*) |

All navigation data is generated by `tools/navigation/build_navigation_data.py`
from Natural Earth (see the script for inputs). Geographic coordinates are never
converted to pixels in data. `MapView` projects them to map units, and its
`Camera2D` handles zoom and pan. Port, waypoint and course picking is done in
screen space with fixed radii, so it works at any zoom. Markers and text are
drawn at a constant screen size. Land fill is pre-tiled (4° tiles) and
coastlines are drawn once as hairlines in spatial tiles, so off-screen geometry
is culled and only the light overlay is redrawn when the view moves.

## Simulation and the game clock

`Simulation` (autoload) is the only code that moves time forward:

- **Clock.** `SessionState.game_time` is UTC seconds. New games start on
  1 May 2026, 08:00 UTC (`SessionState.START_TIME_ISO`). Each frame,
  `Simulation.tick(delta)` advances it by
  `delta × game_seconds_per_real_second (60) × time_scale (1/5/20)`. The rate is a
  variable, so it can be rebalanced. The node is `PROCESS_MODE_PAUSABLE`: pause
  menus stop time; the cabin, deck and chart do not.
- **Player pause (I003b UI hotfix).** There is one shared pause:
  - It is stored as `SessionState.paused` and set through
    `GameSession.set_paused()`, which emits `pause_changed`.
  - `Simulation.tick()` does nothing while it is set, so the clock, the voyage,
    the wind (a function of game time) and the companion's schedule all stand
    still. The scene tree keeps running, so the chart, menus and movement on board
    stay usable.
  - It is not a scene-tree pause: that is used only while menus are open.
  - Choosing a speed (`set_time_scale`, also the same speed again) resumes;
    Pause again resumes at the kept speed.
  - The flag is part of the session, so scene changes keep it. It is saved
    (optional `clock.paused`; older saves load running), and a new game starts
    running.
  - **Sleep** is an explicit `Simulation.sleep()`. It works while paused, moves
    time on by the hours chosen, and leaves the pause as it was; the dialog and
    the wake-up message say so.
- **Shared time bar.** `TimeControls` (Pause, 1×, 5×, 20×) lives once, in the HUD's
  clock panel, with a PAUSED badge.
  - The HUD layer is shown on deck, in the cabin and on the chart.
  - On the chart, `Hud.set_chart_mode(true)` hides everything except the clock
    bar and centres it (and the notifications) over the map, clear of the sidebar.
  - A weather warning that arrives on the chart is kept and shown on returning to
    the boat.
- **Event-driven stepping.** `advance(seconds, stop_at_events)` computes the next
  event on the active voyage (arrival, the next route vertex, or the next
  wind/propulsion evaluation point, where the weather is also assessed),
  steps the clock and the voyage *exactly* to it, handles it, and repeats with the
  remaining time. Speed is constant between evaluation points, so every step is
  exact. Large steps (20×, eight hours of sleep) therefore produce the same
  position, time, sail/engine changes and events as many small steps (tested at
  1×, 5×, 20× and sleep). The cost is proportional to the number of evaluation
  points and events, not to the frame count.
- **Evaluation points** (where wind is sampled and propulsion re-decided) are
  fixed by the game, never by how time is chopped into frames:
  - an absolute grid every `EVALUATION_INTERVAL` = 300 game seconds;
  - every route vertex (the heading changes there);
  - departure, a change of course (which forces a controller reset) and loading
    a migrated save that has no controller state yet.

  The weather is assessed at every grid point and at departure (not at route
  vertices), so warnings never depend on the course's vertex layout or the step
  size.
- **Sleeping** is `Simulation.sleep(hours)`, the same `advance()` with
  `stop_at_events = true`: it stops at arrival or at a new weather warning and reports
  the elapsed time. There is no separate sleep timer or distance formula.
  - `SleepMenu` (1–12 h, arrows, default 6 h) only reports the chosen duration.
  - `App.open_sleep_menu()` is reached from the berth or the chart's Sleep button.
    It is refused at the chart while course edits are unapplied.
  - `App.sleep_for()` calls `Simulation.sleep()`, then `_wake_in_berth()`: the
    session enters the cabin at spawn `v_berth` (282, 0), clear of furniture.
    - Already in the cabin: the player is moved there without reloading the
      scene.
    - From the deck or the chart: the cabin is shown, which closes the chart.
- **The companion's schedule** runs on the same clock:
  `GameSession.apply_simulation_step()` calls `CompanionState.advance_to(time)`.
  - Every 2–5 game hours (interval and next spot picked deterministically from the
    kind and a move counter, intervals in whole minutes) it changes spot, emitting
    `companion_moved`.
  - It is a pure function of game time: one 48 h step and 2,880 one-minute steps
    give the same result (tested), and sleeping or 20× need no special handling.
- **Determinism.** Given the same state, course, wind seed and elapsed time,
  results are identical (up to floating-point rounding); no randomness is involved.
- No offline time: time only advances while the game runs; loading resumes at the
  saved `game_time`.

### Time passing on screen (The Well-Run Ship)

The simulation above is unchanged; these are presentation layers on top of it.

- **`TimePassage`** (`src/ui/time_passage.gd`, a CanvasLayer at 105): fades to
  Harbor Dusk's deepest ink, shows the date ("7 May 2026") and a weekday phrase
  ("a Thursday", "a Thursday evening"), runs the caller's `work` under the black,
  and fades back. The tree is paused while it shows. Any key or click skips
  ahead to the fade back. It never animates the simulation: the work is one
  normal call.
  - **Sleep**: `App.sleep_for()` fades to black, runs `Simulation.sleep()` once,
    then counts the ship's clock from the start hour by hour
    (`SLEEP_HOUR_SECONDS`), turning the date at midnight, and names an early
    waking ("Woken by a weather warning").
  - **Dawn and dusk**: `DayNightWatch` (child of App, pausable) looks at the sun
    each frame. A crossing seen in continuous play (the sun rising through -6°,
    or sinking through +4°, the interface's own day/night thresholds) asks
    `App.play_new_light()`. Under the black the twilight passes with
    `Simulation.advance(…, true)` (stores, weather, wear and events as always;
    an event stops it and reports itself). `App.snap_light()` then gives the
    interface and the boat's light the new hour at once.
    - Once per twilight. A jump in game time of more than 30 minutes between
      two looks (sleep, load, work, an outing ashore) is never a crossing.
    - Not over menus, during Long Passage, while sleeping, during a screen
      change or while another passage shows.
    - No card where the twilight lasts more than two hours (high latitudes in
      summer): the light then changes slowly, as before.
  - **Switches**: `TimePassage.enabled` (off in the test runner, so logic
    tests stay synchronous), `headless_ok` (tests of the presentation) and the
    `--no-time-passage` command-line argument (like-for-like benchmarks). When
    off, callers do the same work at once.
- **`VoyageMap`** (`src/ui/voyage_map.gd`, a CanvasLayer at 15, under menus and
  notifications): Long Passage as an illustrated atlas.
  - `Simulation.passage_started` opens it.
  - The boat scene below is hidden and not processed
    (`PROCESS_MODE_DISABLED`), and so is the HUD. Everything is restored when it
    closes.
  - The land is the cabin wall map's cached triangle batch
    (`CabinWorldMap.land_triangles()`), drawn three times across the Date Line
    with a draw transform. It is redrawn only when the view or the palette
    changes.
  - The route is the voyage's own path, unwrapped so it is one line across the
    Date Line; canal reaches are part of it. The boat is drawn at its real
    position.
  - The route and boat redraw 12 times a second. The simulation is unchanged
    (`Simulation._passage_tick`).
  - `passage_interrupted` shows the reason and the place, with *Back aboard*
    and, where resuming is possible, *Sail on*.
  - It closes at once on a load, a rescue or any screen change. An arrival waits
    for *Back aboard*; the docking scene then plays.
- **Interface recolouring is one theme change.** `UiTheme.set_blend()` blocks
  the project theme's signals while it recolours its style boxes and colours,
  then emits `changed` once. Before this, every colour set announced itself and
  each announcement refreshed every control in the game: about 280 whole-tree
  refreshes per dawn or dusk step, 0.7 s with the deck shown and 2.3 s at the
  chart, every quarter second through each twilight. Guarded by
  `test_well_run_ship` (`[theme]`).

## Voyage state

`SessionState.vessel_status` is a small explicit state model:

```
moored ──depart()──► underway ──arrival──► arrived ──depart()──► underway …
                       └─change_course()─┘ (stays underway)
```

`arrived` behaves like `moored` but tells the player where they arrived. While
underway, `voyage` holds the `Voyage` and `location_id` is empty. Between two
evaluation points the boat moves `speed_kn × elapsed / 3600` nm along the route. The vessel position is
`GeoMath.point_along(route.path, progress_nm)`, so chart, HUD, simulation and saves
cannot disagree.

**Departure** (`GameSession.depart()`) re-validates the planned route, creates the
`Voyage` from it and switches to `underway`; nothing is reloaded. **Arrival**
(`complete_voyage()`) sets the location to the destination, places the vessel at
the port coordinate and emits `voyage_arrived`; no new voyage starts automatically.

## Route calculation

Approach: **precomputed sea graph + A\* + string pulling, all checked against one
navigability raster**. It was chosen because it is deterministic, fast (European
routes in milliseconds via Godot's native `AStar2D`), works for any origin or
destination inside the coverage (ports, waypoints, positions at sea), and keeps one
definition of "navigable water" for routing and validation.

1. **Navigability raster** (`NavGrid`, 3720×4236 cells, 60 cells per Mercator degree:
   about 1.9 km E-W, and N-S about 1.1 km at 55°N). It is rasterised from exactly the
   coastline polygons the chart draws. A cell is navigable only if **no** land
   touches any part of it (checked at 1/4-cell precision). A second class,
   *approach* water (mostly water), exists only for harbour approaches.
2. **Sea graph** (offline, `build_navigation_data.py`): about 24,000 nodes on a
   multi-resolution lattice. Nodes are coarse in open water and denser near coasts,
   with extra nodes along the medial axis of narrow straits. About 110,000 edges each
   join two nodes with a clear straight line. Pieces that lie in the same body of
   water are stitched together with a raster search, so the graph is connected
   exactly where the water is.
3. **A leg** (`SeaRouter.find_leg`): if the two ends see each other, a straight
   segment. Otherwise each end is connected to up to 8 visible nearby graph nodes,
   `AStar2D` finds the node path (costs ≈ nautical miles via an azimuthal
   equidistant projection), and string pulling removes every point that a clear
   straight line can skip.
4. **Harbour approaches.** Port coordinates often lie on generalised coastline.
   `find_port_approach()` does a bounded breadth-first search over approach-class
   cells:
   - it may start up to 2 nm from the port (the "berth link");
   - it may not go further than 10 nm from the port, and stays inside a 61×61-cell
     window;
   - it ends at the first navigable cell that reaches open sea (a graph piece of at
     least 50 nodes, so dock basins don't count).

   This is the only place approach water is used, and it is documented as able to
   graze the simplified coastline.
5. **Waypoints** split a route into legs (origin → wp1 → … → destination). Each leg is
   routed independently, so waypoints are constraints, and moving one recalculates
   only its two legs (leg results are cached).
6. **Limits.** Every search is bounded:
   - fixed connection radii and candidate counts;
   - the approach window;
   - `MAX_PATH_NODES` on the A* result.

   Failure returns an explanation instead of a route. Unconnected waters (e.g. the
   Black Sea) fail in milliseconds.

The **coverage limits** follow from the data and resolution: straits narrower than
roughly two cells (the Bosporus, the Dardanelles, the Rio–Antirrio strait, the
Drøbak narrows, inner skerries) are closed. They are reported as "no sea route",
never crossed.

### Land validation

`SeaRouter.validate_route(route)` checks **complete segments**, not just points. Each
segment is a rhumb line, which is a straight line in the Mercator raster, so
`NavGrid.is_line_clear` walks *every* cell the segment touches (supercover traversal;
at exact corner crossings both side cells must be water). A segment is allowed if it
is:

- entirely in navigable cells;
- within 10 nm of the route's origin/destination port and entirely in approach cells
  (harbour approach); or
- the ≤ 2 nm berth link that starts exactly at a port coordinate.

Waypoints must be in navigable cells. The same raster and traversal produced the
graph edges (verified at runtime by a test that re-checks all 109,475 edges), so
routing and validation cannot disagree. `GameSession.set_planned_route()`,
`depart()` and `change_course()` all validate before changing state. Tests also
check every route segment against the vector coastline independently.

Depth, draft, tides and grounding are not modelled. "Navigable" is a property of
`NavGrid` cells only. A later restriction (depth, draft, exclusion zones) can be
added as another cell class or a per-vessel mask, without changing the router's
callers.

### Manual waypoint handling

The chart edits a **draft**; the committed course is untouched until **Apply**:

- `WorldMap` keeps the draft destination, its waypoints and its leg results.
- **Sidebar (I003b UI hotfix).** A fixed-size `SidePanel` (`SidebarPanel` theme
  variation) has three parts stacked in one `VBoxContainer`:
  - **Header** (always visible): "Chart", the voyage status, a progress bar, and
    distance to go plus ETA. These are single-line labels cut with an ellipsis
    (full text in the tooltip), so live values never change its height.
  - **Tabs** (`TabContainer`, fills the rest). Each tab is its own
    `ScrollContainer` with horizontal scrolling disabled and a *reserved* vertical
    gutter (`SCROLL_MODE_RESERVE`), so wrapping never changes when a scroll bar
    appears.
    - **Course:** destination, course, waypoint tools and editing help.
    - **Weather:** wind at the boat with sail/engine, and the weather along the
      course, the weather legend. Its title shows the number of hazards met
      along the course, e.g. "Weather (2)".
    - **Details:** position, projection, help and attribution.

    Clicking a port or editing the course on the map shows the Course tab; the
    warning's *View chart* opens the Weather tab.
  - **Footer** (always visible): Apply/Change course and Discard, Set sail and
    Sleep, Back. These are the actions needed from any tab. They never move, and
    are disabled rather than hidden when unusable.

  Long text wraps and scrolls inside its tab instead of being cut. Map controls
  (zoom, All Europe, Find boat, Wind) stay in the map toolbar. Time controls are
  not in the sidebar: the HUD's shared clock bar is shown on the chart (see
  *Simulation and the game clock*). Tests compare the panel, header, tabs, footer
  and footer buttons across tabs, 20× live updates, sail ↔ engine, destinations,
  drafts, 80 %/130 % scale and a 1366×768 window.
- `MapView` only reports presses and drags: on the course line, which inserts a
  waypoint into that leg and starts dragging it; on waypoints; and right-clicks.
- While dragging, the marker follows the mouse and the two affected legs are
  recalculated at most every 0.1 s, and again on release.
- An invalid draft (a waypoint on land, a blocked leg) is drawn with dashed red
  "BLOCKED" legs and crossed waypoints, and explained in the side panel. Its Apply
  button is disabled.
- Leaving the chart with unapplied changes asks first; Discard restores the
  committed course.
- The draft legs are the `SeaRouter` result itself, so the course shown is the course
  that will be sailed. In port, Apply calls `set_planned_route()`; at sea it calls
  `change_course()`.

### Geographic position interpolation

Route segments are rhumb lines (constant bearing). `GeoMath.rhumb_distance_nm`
gives segment lengths; route distance is their sum (so it follows the coast, not the
great circle). `GeoMath.rhumb_interpolate` places a point at a fraction of a
segment's *distance* (latitude linear in distance, longitude along the constant
bearing), consistent with the distance calculation. The same lines are straight on
the Mercator chart and in the raster, so drawing, validation and movement agree.
Screen space is never used to compute positions.

## Weather model

Iteration 005a replaced the static demonstration circles (`WeatherCondition`,
`WeatherCatalog`, `demo_conditions.tres`, all deleted) with **one** weather
model. There are no other sources of wind or hazardous weather.

```
WindField (background)  ─┐
weather_events.json ─► WeatherModel.sample(geo, time, seed, known_at) ─► WeatherSample
                         └ active_events(time, seed) ─► [WeatherEvent]
        ▲ read by: Simulation (propulsion, warnings, exposure, ETA), MapView overlay,
          WindLayer, WorldMap Weather tab, HUD, App weather audio
```

- **`WeatherModel`** (`src/weather/weather_model.gd`, `get_default()`): the query.
  `sample()` starts from the background wind (`WindField`, the Iteration 003
  climatology, unchanged) and applies every event active at that place and time.
- **`WeatherEvent`** (`weather_event.gd`): one gale area, thunderstorm-risk area,
  thunderstorm cell or tropical cyclone. Its centre (a curved track), heading,
  size, irregular outline (three drifting harmonics), lifecycle stage
  (developing → active → dissipating, `life_factor` rising and falling
  smoothly) and gust episodes (smooth sin² bursts in 20-minute slots) are
  closed-form functions of game time. `outline(time)` is what the chart draws.
- **`WeatherSample`** (`weather_sample.gd`) extends `WindField.Sample`:
  `from_deg`/`speed_kn` are the **sustained** wind the boat sails in (propulsion
  never uses gusts); plus `gust_kn`, `hazard`, `classification`, the dominant
  event (`event_id`, `event_kind`, `event_name`), `thunder_possible`,
  `thunder_active`, `cyclone_risk` and `cyclone_basin`.
- **Data** (`data/weather/weather_events.json`, `model_version` 1): six gale
  zones (North Atlantic, Biscay, North Sea, Baltic, Gulf of Lion Mistral, Aegean
  Meltemi) and five convective zones, each with an area, a rate per day, a
  12-month season, drift, size and strength ranges; cell parameters; seven
  tropical-cyclone basins (North Atlantic, East and West Pacific, North and South
  Indian, Australian, South Pacific) with genesis area, risk area, season, track
  and an optional limit (the North Atlantic basin ends cyclones that cross 36°N or
  36°W, so none reach the European chart).

### Quick samples (Turbocharge)

`WeatherModel.sample_hazard(geo, time, seed, known_at)` returns
`[from_deg, speed_kn, gust_kn, hazard]` (64-bit floats) computed by exactly
the same code as `sample()`, without building a `WeatherSample`, classifying it
or computing the cyclone risk.

- The route-ahead hazard scan (`Simulation.route_hazards`) uses it for every
  step and asks `sample()` only for the hazardous samples it keeps.
- The weather damage grid (`WeatherDamage.damage_between`) uses it too.
- Results are identical to the previous implementation (`test_turbocharge`
  compares both on Baltic, Suez, Panama, Pacific and canal routes, several
  dates and seeds). This is the bulk of a night's sleep underway and of Long
  Passage's simulation cost.

### Formation and determinism

- Each zone may form at most one event per **slot** (gales and risk areas 12 h,
  cyclones 24 h); whether it does, and all its parameters, come from a
  `RandomNumberGenerator` seeded with `hash([seed, kind, zone, slot])`.
  Thunderstorm cells are slots of 1 h inside a risk area's outline, seeded from
  the area. The seed is the session's wind seed.
- Only slots that can still hold a living event are visited (a bounded
  look-back), and events are cached per 15 game minutes. A year of weather is
  about 0.7 s to scan (headless).
- So `sample()` is a pure function of (position, time, seed): reading never
  changes the weather, opening the chart cannot move a storm, and 1×, 20×, one
  large step, sleeping, pausing and save/load all see the same weather (tested).
  A save needs only the seed and `model_version`.
- **`known_at`** limits a sample to events that had formed by then. Forecasts
  (route hazards, warnings, ETA) use `known_at = now`: weather that already
  exists is projected forward along its track; storms that have not formed yet
  are not foreseen.

### Strength, hazard and classification

- **Gale areas** pull the wind towards their flow direction and up to their peak
  inside the core, fading smoothly to the edge. Gusts ×1.35 (×1.25 elsewhere).
- **Thunderstorm cells** add an outflow (wind blowing out of the cell, along the
  track at the very centre) and gust bursts, weighted by distance and lifecycle.
  A cell whose peak plus gusts reach `SEVERE_STORM_KN` (40) is **severe squalls**
  and is at least Dangerous in its core.
- **Cyclones** use a Rankine-like vortex (calm eye, maximum at the eye wall,
  decay outside), turning counter-clockwise in the north, clockwise in the south,
  with 20° inflow; categories from tropical storm to category 5.
- **Hazard** = the worse of sustained wind (22 / 34 / 48 kn → Caution / Dangerous
  / Severe) and gusts (30 / 41 / 56 kn); a thunderstorm risk is at least Caution.
- **Classification** (for labels): calm, fair, strong wind, gale, storm,
  thunderstorm risk, thunderstorm, squall, tropical storm, hurricane.
- **Cyclone season risk** (`cyclone_risk(geo, time)`): 0–1 from the basin's
  risk area and month (by the game date and hemisphere), shown in the Weather
  tab when the boat is in such an area. Never above 0 in Europe.

### Warnings and exposure

`Simulation._assess_weather()` runs at every evaluation grid point while
underway and at departure:

1. records the weather at the boat in the **exposure record**
   (`WeatherExposure`: level, since when, classification, event, peak sustained
   wind and gusts; reset on departure and arrival; saved);
2. gives at most one new warning, in this order: hazardous weather **at the
   boat**; a thunderstorm cell within `NEARBY_STORM_NM` (15 nm) of its edge; the
   nearest hazard **ahead on the course** within `WARNING_HORIZON_HOURS` (6 h of
   sailing at the estimated speed, sampled every 2 nm at the time the boat would
   get there, `known_at = now`).

- **De-duplication:** keys `"<event id>><level>"` (or `"wind>…"` for the
  background wind) and `"<event id>>near"` are stored in
  `Voyage.warned_conditions`. An event is announced again only when it reaches a
  higher level. A change of course clears the list (as before).
- A warning emits `weather_warning`: `App` shows the HUD banner (View chart /
  Dismiss) and a notification, time drops to 1×, and a sleep stops
  (`STOP_WARNING`).
- Wind and gust figures in route warnings and the Weather tab are the expected
  strength (`Simulation.expected_strength`: the forecast on the course or the
  event's core strength at that time, whichever is more). Thunderstorm risk is
  described as a risk, not as wind.

### Presentation

- **Chart overlay** (`MapView`): every `WEATHER_REFRESH_SECONDS` (300 game s) the
  active events are projected once (outline, core ring, centre, label, strength)
  and drawn under the course. `WeatherStyle` (`src/navigation/weather_style.gd`)
  gives each kind a colour, fill, outline style (solid, dashed, dotted), glyph and
  label, so kinds are told apart without colour. `WeatherLegend` in the Weather
  tab draws the same styles.
- **Weather tab** (`WorldMap`): wind at the boat with gusts, label, hazard level
  and cyclone-season risk; nearby thunderstorms; hazards along the shown course
  (12 h horizon, cached per course and 5 game minutes); the legend.
- **HUD:** "Wind WSW 40 kn, gusts 54 · Gale" (gusts when ≥ 6 kn above the wind,
  the label from Caution).
- **Sound** (`App.update_weather_audio`, once per real second): a storm-wind loop
  on the Ambience bus from 20 kn (−30 dB) to 45 kn (−6 dB), 10 dB quieter below
  deck, and thunder now and then (8–25 s) when a thunderstorm is active at or
  near the boat. Only aboard; stops in menus.

### Tests and fixtures

`WeatherModel.fixture_events` adds hand-made events (built by
`src/dev/weather_fixtures.gd`); `generated_enabled = false`, or a
`WindField.test_override` (the calm-wind fixture), switches the generated
weather off so older suites keep exact numbers.

### Handoff to Iteration 005b (implemented, see *Boat condition, rescue, money and provisions*)

The interface I005b should build on (do not add a second weather source):

- `Simulation.get_weather_at_vessel()` / `get_weather_at(geo, time)` → `WeatherSample`
  (`speed_kn`, `gust_kn`, `hazard`, `classification`, `event_id`, `event_kind`).
- `GameSession.get_weather_exposure()` → `WeatherExposure` (`level`, `since`,
  `duration(now)`, `peak_sustained_kn`, `peak_gust_kn`, `event_id`), updated at
  every evaluation point, so it is step-size independent. Boat damage can be
  derived from it at the same points (e.g. in `_assess_weather`, after
  `update_weather_exposure`).
- `Simulation.weather_warning` (dict with `key`, `hazard`, `classification`,
  `event_id`, `hours`, `distance_nm`, `text`).
- Hazard levels `WeatherModel.HAZARD_*` and per-vessel thresholds (to add to
  `VesselProfile`) are the natural place to tune how much each boat can take.

## Boat condition, rescue, money and provisions

Iteration 005b. One owner per responsibility: the state is in `SessionState`,
every change goes through `GameSession`, time and weather come from
`Simulation` and `WeatherModel`, and the UI only reads.

### Condition and weather damage

- **Condition** is one general seaworthiness value per boat, 0-100 %
  (`SessionState.vessel_conditions` by vessel id). It is not split into hull,
  engine, sails or rigging. Switching boats never touches another boat's value.
  `VesselCondition` gives the bands: Sound 76-100, Worn 41-75, Damaged 16-40,
  Critical 1-15 (as shown, rounded up).
- **Damage** (`src/sailing/weather_damage.gd`, pure functions) is a rate in % per
  hour from a weather sample, times the boat's
  `VesselProfile.weather_damage_factor` (Starling 1.0, Halcyon 0.85, Petrel 1.15):

  ```
  sustained  0.06 × (wind − 28)^1.6     above 28 kn
  gusts      0.2  × (gust − 45)         above 45 kn
  ```

  | Weather (sustained / gusts) | Starling 33 | Over 6 h |
  |---|---|---|
  | 25 / 34 kn (fresh breeze) | 0 %/h | 0 % |
  | 30 / 40 kn (strong winds, caution) | 0.2 %/h | ~1 % |
  | 34 / 46 kn (gale threshold) | 1.3 %/h | ~8 % |
  | 40 / 54 kn (gale) | 5.0 %/h | ~30 % |
  | 48 / 65 kn (storm) | 11.2 %/h | ~67 % |
  | 60 / 78 kn (violent storm) | 22 %/h | lost in ~4.5 h |
  | 22 kn with squall bursts to 55 kn | ~2 %/h while bursts last | — |

- **Integration:** in `Simulation._assess_weather()`, at every evaluation point
  while underway (the absolute 300 s grid, plus departure), before the warnings.
  - The damage for (`damage_applied_until`, now] is the sum of the rate at the
    fixed sample times k × 60 s at the boat. Gust bursts last 8-20 minutes, so
    none falls between samples.
  - `GameSession.apply_weather_damage()` then moves `damage_applied_until` to
    now, so no stretch of time is counted twice. That holds across saves too,
    because the field is saved.
  - Because the sample times are fixed on the clock, the total is identical at
    1×, 5×, 20×, in one long `advance()`, while sleeping, and across a
    save/load. The tests compare the exact condition, position, stores and
    exposure.
- **No damage when not underway** (moored, arrived, after a rescue). The partial
  interval between the last evaluation point and an arrival (at most 5 minutes)
  is not charged.
- The `advance()` loop now treats a leftover below 1 µs as floating-point
  residue. Before, an evaluation point exactly at the end of a call was handled
  in that call after one big step but in the next call after many small steps.
- **Presentation:**
  - `VesselVisual.set_condition()` creates a `DamageOverlay` child. It holds
    deterministic marks placed inside the boat's own outline (its base slots'
    shapes), with more and heavier marks per band. It draws over the art and
    under `Layout`, so station rings and markers stay on top.
  - Drawn overlays can replace the procedural marks per band:
    `VesselVisualProfile.get_damage_texture()` looks for a texture in the
    profile, then `<art>/<deck|cabin>/damage_<band>.png`.
  - `BoatArea.show_condition()` follows `condition_changed`. The boatyard
    preview shows each boat's own damage. The HUD shows `Hull 87 % · Sound`.
- **Repair:** `GameSession.repair_vessel()`, harbour only (re-checked when
  called), free. It restores 100 % and emits `condition_changed`.

### Rescue

- When `apply_weather_damage()` brings the condition to 0, it calls
  `GameSession.rescue()`. This is **one transaction on the state**, before
  anything else can run or be saved:
  - the fee is `min(1000, funds)`, so funds are never negative;
  - the voyage and planned route are cleared, and the boat is moored in
    `HOME_PORT` (Copenhagen) at its position;
  - the propulsion and exposure are reset, `damage_applied_until` = now and the
    condition = 100;
  - the player is put in the cabin at spawn `start`, and time runs at 1×;
  - `rescue_count` and `last_rescue` are recorded.
  - It then emits `rescued(info)`.
- `rescue()` does nothing when not underway, so one incident can be rescued only
  once. A save made after a rescue is coherent, and loading it repeats nothing.
- `Simulation.advance()` stops at once with `STOP_RESCUE` (`result.rescued`),
  whatever was asked: no sleep, 20× frame or long advance continues along the
  abandoned voyage.
- `App._on_rescued()` clears the modals, shows the boat in harbour and pushes
  `RescueDialog` ("Rescued at Sea": Copenhagen, the fee, the funds left).
  - `_rescue_open` keeps gameplay paused, also during the screen change.
  - Continue un-pauses; time then runs at 1×, and a player pause stays as it
    was.
  - `App.sleep_for()` returns without the usual wake-up when the sleep ended in
    a rescue.
- The companion, provisions, other boats and the clock are kept.

### Money

Since Iteration 005c, **remote work** is the income:
- `Simulation.work(hours)` (1–8) works only when `GameSession.can_work_remotely()`
  (moored in harbour). It advances the normal simulation like sleeping: stores
  are used, it also works while paused and leaves the pause as it was.
- It then calls `GameSession.pay_remote_work(completed_hours)`:
  `REMOTE_WORK_PAY_PER_HOUR` = €25 for each completed hour.
- `WorkMenu` (`src/ui/work_menu.gd`) is opened from each cabin's `work` station:
  the Starling's saloon table, the Halcyon's desk in the owner's hull, the
  Petrel's saloon table.
- Nothing new is saved: funds and stores already are.

`SessionState.funds` holds whole euros: 10,000 for a new game, and the rescue
fee is the only transaction. `GameSession.get_funds()` reads it and
`format_money()` gives "€9,000". There is no income, no shop and no other
costs.

### Provisions

- **`Provisions`** (`src/core/provisions.gd`): `food_days`, `water_days`
  (capacity 14) and `warning_level`.
- **Consumption** is in `GameSession.apply_simulation_step()`: every advance of
  game time uses elapsed/86400 days of each, whether moored, underway or
  sleeping, and never below zero. A pause therefore uses nothing. Sleeping while
  paused uses the hours slept. Results are equal at any step size (to float
  rounding, tested to 1e-6).
- **Warnings** come at ≤ 3 days (low), ≤ 1 day (critical) and 0 (empty), each
  once until the stores change. `provisions_warning` → App shows a notification.
- **Empty stores** never hurt the player or the boat, and do not trigger a
  rescue. A voyage underway continues, but `depart()` refuses until the player
  buys provisions.
- **Buying provisions (Iteration 005c; free restocking was removed):**
  - `GameSession.buy_provisions()` is one transaction: it checks the harbour,
    checks that the stores are not full and that funds ≥ the price, then takes
    the price and fills food and water to 14 days. If any check fails, nothing
    changes and the reason is returned.
  - Price: `get_provisions_price()` = ⌈(14 − food + 14 − water) × €10⌉, with
    `PROVISIONS_PRICE_PER_DAY` = 10. It is the same in every harbour.
  - `GroceryMenu` (`src/ui/grocery_menu.gd`) is opened from:
    - the pontoon's `grocery` station on every deck (enabled only in harbour,
      like the boatyard);
    - the provisions panel;
    - the boatyard.
- **Presentation:**
  - Every cabin has a `provisions` station at the galley (`ProvisionsMenu`: Food
    / Water / Endurance in days, the level, the way to the grocery store).
  - A `ProvisionDisplay` node next to it draws four food crates and four water
    cans, each standing for 3.5 days. Empty ones are outlines; low stores are
    amber, empty ones red. It can be replaced by
    `<art>/cabin/provisions_<level>.png`.
  - The HUD shows `Food 12.5 d · Water 12.5 d`.

## Captain's Log (Iteration 006)

The player's sailing history, derived only from the authoritative voyage
events. There is no second voyage or arrival system.

- **Data:** `CaptainsLog` (`src/core/captains_log.gd`), plain data in
  `SessionState.captains_log`, saved as the `log` section:
  - totals: `total_nm` (voyages that have ended), `voyages_completed`,
    `arrivals`;
  - `longest`: the record of the longest completed passage;
  - `visited`: port id → `{first, arrivals}`;
  - `voyages`: the latest `MAX_VOYAGES` (50) records; older ones are dropped,
    while the totals keep counting.
  - Rescues are not repeated here: the log shows `SessionState.rescue_count`.
- **The voyage carries what the log needs** (`Voyage`): `departure_port_id`
  and position (kept through changes of course), `sailed_nm` (advanced in
  `GameSession.apply_simulation_step` from the progress the simulation makes,
  so it is identical in one step or many), `worst_hazard` (from
  `update_weather_exposure`) and `damage_percent` (from
  `apply_weather_damage`).
- **Events:** only two places write the log, both inside GameSession's own
  transactions:
  - `complete_voyage()`: an `arrived` record; the destination becomes visited;
  - `rescue()`: a `rescued` record. Its miles count, but it is not a completed
    voyage, an arrival or a visit (the tow home does not count).

  Both emit `voyage_logged(record, new_harbour)`. A new game lists its start
  harbour as visited (no arrival). Planning a course, passing a harbour,
  waiting, sleeping, working or loading never write the log. Loading cannot
  repeat an event, because the voyage is gone from the saved state once it
  has been logged.
- **Total distance shown:** `GameSession.get_total_nm_sailed()` is the log's
  total plus the voyage under way.
- **UI:** `CaptainsLogMenu` (L, or the pause menu's *Captain's Log*) is
  read-only, with Log and Harbours tabs, a fixed size, and scrolling lists.
  The application shows one short message on a first visit.

## Objectives and renown (Iteration 006)

Optional goals that are tracked automatically. There is no quest engine, no
accepting objectives and no story.

- **Data:** `data/progression/objectives.json`:
  - the handcrafted objectives (id, title, text, type, target/port/hazard,
    reward, repeatable, category);
  - the publishing rate (`euros_per_renown`);
  - the settings for the generated objectives.
- **`ObjectiveCatalog`** (`src/core/objective_catalog.gd`) loads the file,
  validates every entry and leaves out invalid ones with an error (for
  example an unknown harbour). It adds the generated ones: "Far horizons:
  <harbour>", `count` harbours at least `min_nm` from the start harbour,
  evenly spread by distance, with the reward scaled between `min_reward` and
  `max_reward`. They are built from the harbour catalogue, so they can only
  name harbours that exist.
- **Types:**
  - `voyage_count`, `total_distance`, `visit_count`: Captain's Log totals;
  - `visit_harbour`: an arrival at that harbour;
  - `passage_length`: one completed passage of at least N nm;
  - `clean_passage`: the same, without damage;
  - `weather_arrival`: arrived after meeting at least hazard N;
  - `new_harbour`: a first visit.

  The last three need a `fully_recorded` voyage, so a voyage migrated from
  an older save cannot qualify on weather it may not have met.
- **`ObjectiveProgress`** (`src/core/objective_progress.gd`), the `progress`
  save section, holds:
  - `lifetime_renown` (only ever increases);
  - `unpublished_renown`;
  - `completed`: id → `{count, first, last_event}`;
  - `recent`: the latest 20 rewards;
  - the publishing totals.
- **When:** GameSession evaluates objectives in `_award_objectives()`, called
  inside `complete_voyage()` and `rescue()` right after the log record. The
  reward is part of the same transaction as the record. `renown_awarded`
  follows `voyage_logged`.
- **Paying once:**
  - A one-time objective pays once.
  - A repeatable one pays only for a voyage that ended later than the one it
    last paid for (`ObjectiveProgress.can_pay`).
  - Re-evaluating an event, loading a save, waiting, sleeping and returning
    to a known harbour therefore pay nothing.
  - A lost (rescued) voyage counts only towards distance; passage, harbour
    and weather objectives need an arrival.
- **Secret achievements (Visual Identity V01):** objectives with
  `"secret": true` and six hat types (`hat_lost_count`, `hat_spent`,
  `hat_lost_soon`, `hat_weather_voyage`, `original_hat_voyages`,
  `hat_lost_offshore`). Hat events are evaluated by
  `ObjectiveCatalog.evaluate_hat_event()` inside `GameSession._lose_hat()`
  and `buy_hat()`; the two voyage ones by `evaluate()` (which now receives the
  hat). Same `ObjectiveProgress`, same pay-once rule, same save section. The
  Objectives tab hides everything about them until found (a count only).
  Awards carry `secret`, `text` and `tone`; `App` shows a secret one as its
  own notification with a soft chime.
- **UI:** the Captain's Log's Objectives tab lists open objectives (with
  their requirement, progress and reward; repeatable ones stay listed) and
  the completed ones. The Log tab shows lifetime and unpublished renown. The
  application shows one short "+N renown: …" message per voyage.

## Social-media income (Iteration 006)

Renown can be turned into money once, as an abstract "travel update". There
are no followers, platforms or sponsors.

- **Transaction:** `GameSession.publish_travel_update()`, in harbour only. In
  one step it takes all `unpublished_renown`, pays `renown ×
  euros_per_renown` (data file, €2), and adds to `publications`,
  `published_renown` and `published_euros`. Lifetime renown is untouched, so
  `lifetime = published + unpublished` always holds. With no unpublished
  renown, or at sea, it refuses and changes nothing.
- **Quote:** `get_publish_quote()` returns the renown, rate, euros, funds
  before and after, and the reason it is not possible. The dialogs show
  this; they never compute money themselves.
- **UI:** `PublishMenu` is the confirmation (renown, rate, earnings, funds
  before → after; *Publish for €X* / Cancel). It is reached from the Captain's
  Log (*Publish travel update…*) and from the cabin's work station dialog (the
  same online connection), so there is no new interactable on board. Remote
  work and the grocery store are unchanged.

## Captain's hat (Visual Identity V01)

One small personal object with its own state, owner and art, built on the
existing services. There is no inventory system.

- **State:** `HatState` (`src/core/hat_state.gd`) in `SessionState.hat`,
  saved as the `hat` section. Status `stored` (on its hook in the cabin),
  `worn`, `carried` (taken off, under the arm) or `lost`. It belongs to the
  player: `switch_vessel()`, `rescue()` and loading never touch it, so a boat
  switch shows a stored hat on the new cabin's hook and a lost hat stays lost.
- **Changes** go through `GameSession`: `use_hat_hook()` (the cabin's `hat`
  station: put on / hang up), `toggle_hat()` (the H key, `captains_hat`
  action, handled by `App` like L), `buy_hat()`, and the Simulation-only hooks
  `apply_hat_check()` and `recover_hat()`. Signals: `hat_changed`,
  `hat_warning`, `hat_lost`, `hat_bought`.
- **Wind:** `Simulation._check_hat()` runs after every step of `advance()`
  for the game time just simulated. Checks are on an absolute grid
  (`HatConfig.check_interval_s`, 60 s). Only while the hat is worn on deck
  (`GameSession.is_hat_exposed()`, and not during `sleep()` or `work()`) does
  a check sample the one `WeatherModel` at the boat. Underway, the boat's
  position at the check is interpolated along the course inside the step,
  which is exact because the speed is constant between evaluation points.
  `HatConfig.strain_per_minute()` turns the sample into strain; the first
  check with risk only warns (time drops to 1×, like a weather warning); the
  hat blows away at its own threshold (`HatConfig.threshold_for(seed,
  serial)`). Nothing is random per frame, so 1×, 20×, one long step and a
  save/load in between give the same moment of loss (tested).
- **Balancing** is data: `data/hat/hat_config.json` (see
  [DEV_GUIDES/CAPTAINS_HAT.md](../../DEV_GUIDES/CAPTAINS_HAT.md)).
- **Words:** `HatStory` writes the notifications and the log lines from real
  state only: the harbour the boat lies in, or the nearest harbour in the
  catalogue with its distance, and the sampled wind.
- **Purchase:** the grocery store's own hat row calls `buy_hat()`: harbour
  only, only when the hat is lost, refused without enough money; one payment
  of `price_eur`. The provisions figures are untouched.
- **Presentation (art only, no collision):** each cabin has
  `Layout/HatSpot` (where `BoatArea` puts the `HatHook` art node) and the
  `Layout/Stations/Hat` interactable. The player draws the hat through a
  `PlayerHat` child; the deck shows `HatBlowAway` when the hat is lost.
  `HatArt` (`data/hat/hat_art.tres`) resolves each slot: assigned texture,
  then `assets/hat/hat_<slot>.png`, then `HatDrawing`.

## Diagnostic session log (Visual Identity V01)

`SessionLog` writes one file per run, `user://diagnostics/session_<UTC time>.jsonl`
(Windows: `%APPDATA%\Little Captains Hat\diagnostics\`; Settings has a
*Diagnostic logs…* button that opens the folder). Each line is a JSON object
with `t` (UTC), `event` and, during a game, `game` (game time).

- **Events:** `session_start` (game version, commit, save format, engine, OS,
  renderer), `screen`, `game_started` / `game_loaded` / `game_ended`, `save`,
  `load` (with the result), `import_save`, `hat`, `hat_warning`, `hat_lost`,
  `hat_bought`, `achievement_unlocked`, `renown_awarded`, `travel_update`,
  `voyage_started`, `voyage_logged`, `rescued`, `vessel_changed`, `funds`,
  `error` (engine and script errors through a Godot `Logger`), `session_end`.
  It subscribes to GameSession's signals; SaveManager and App add the save,
  load and screen lines. Nothing is logged per frame or per hat check.
- **Bounds:** at most 5,000 lines or 1 MB per file (then a `log_truncated`
  line), the newest 10 files are kept. Every line is flushed immediately.
- **Privacy:** no names, no paths, no free text from the player.
- **Determinism:** it only reads; a test plays the same hat scenario with and
  without the log and gets the same result. `-- --no-session-log` turns it
  off. Tests write to `user://test_diagnostics`.

## A Boat of Your Own (I020, 0.107a)

Harbour trades and a cabin that feels like home. Report: `docs/iterations/i020/`.

- **Trades** (`src/harbour/harbour_trades.gd`, `HarbourTrades`, catalogue
  `data/harbours/trades/trades.json`): the fishmonger, the chandlery and the
  sailmaker are `HarbourFacilities` ids (`FISHMONGER`, `CHANDLERY`,
  `SAILMAKER`) offered from each harbour's existing facility data: the
  fishmonger with the grocery store, the other two with the boatyard. They
  appear in the chart's harbour previews and are reached from those
  stations (the grocery store's "To the fishmonger", the boatyard's
  "Sailmaker…" and "Chandlery…"). No pontoon station of their own.
- **One transaction per thing, in GameSession**: `sell_fish` / `sell_catch`
  (the fishmonger: the catalogue's price by weight, paid exactly once, the
  hold emptied, trophies and records kept), `buy_decor`, `buy_magic_anchor`
  (450; before, a free prototype), `order_sail_cloth`, and the existing
  `install_upgrade` and `perform_service` for the chandlery's gear (the
  boat-care catalogue's weather receiver, large cool box and gimballed
  stove: the yard's list leaves them out) and the sailmaker's rig service.
  Each checks the trade and the funds first and changes nothing when
  refused, so funds never go below zero and nothing is bought twice.
- **Home** (`src/core/home_state.gd`, `SessionState.home`, optional in
  saves): the cabin things the Captain owns (for any boat), and per vessel
  which are shown, its sailcloth and the cloths cut for it. Stable ids only;
  unknown ids are dropped on load.
- **Cabin things** (`src/aboard/cabin_decor.gd`, `CabinDecor`): drawn in
  code, no collision, no station. `BoatArea.setup_decor` places them from
  the cabin itself (`CabinDecor.place_all`: wall things along the hull
  sides, the rug on open floor clear of all furniture), always clear of
  every station, companion spot and fitted gear; rebuilt on `home_changed`.
  "Make it home" (action wheel, in the cabin; `CabinHomeMenu`) shows them or
  puts them away, the cabin visible beside the panel as the preview.
- **Sailcloth** (`SailRig.set_cloth`): the drawn sails' colours and a tint
  for sail sprites. A look only: performance profiles are untouched.
- **Shared UI**: `TradePanel` (title, intro, scrolling rows of name,
  description and one priced button, funds, Close) for all four panels.

## The Captain's Watch (I019, 0.106a)

Awareness at sea and a second language. Report: `docs/iterations/i019/`.

- **Traffic** (`src/navigation/traffic_model.gd`, `TrafficModel`): other
  vessels, made up where and when they are looked for, never simulated for
  the whole world and never saved. The sea is cut into 1° cells and 3 h
  windows; each (cell, window) holds up to 8 vessels (busier within 90 nm of
  harbours), each on a straight track through navigable water at a steady
  speed for its kind (cargo, tanker, ferry, fishing boat, sailing yacht),
  cut where it would meet land and kept when at least an hour long. A vessel
  is a pure function of (cell, window, slot, wind seed): the same ships after
  a load, while asleep and in Long Passage. Tracks are cached (bounded at
  4096 cells); positions are computed on demand. A ship whose track starts
  within 12 nm is not seen in its first hour (ships come over the horizon).
- **Collision awareness** (`Simulation.traffic_risks`, `risk_level`,
  `TrafficModel.approach`): closest point of approach and time to it from
  relative motion. *Collision risk*: passes within 0.3 nm in the next 30 min;
  *caution*: within 1 nm in 45 min; *nearby*: within 6 nm. Only a moving boat
  can be on a collision course (at anchor or moored, ships are only nearby).
  On the evaluation grid underway (`_assess_traffic`), a ship newly at
  collision risk is announced once per voyage (key `traffic>id` in the
  voyage's warned conditions, saved): signal `traffic_alert`, a warning on
  the HUD, and it stops sleep, accelerated time and Long Passage
  (`STOP_TRAFFIC`). Awareness only: there are no collisions and no penalties.
- **Radar** (`src/ui/radar_panel.gd`): a compact north-up scope on deck
  (3/6/12 nm), toggled from the action wheel and shown by itself while a ship
  is a caution or a collision risk underway; colours for nearby, caution and
  risk; up to three lines and what to do. Asks for traffic five times a
  second, never every frame (about 0.03–0.3 ms a query).
- **Anchor alarms** (`AnchorState.alarm_level`, `good_since`, optional in
  saves): 0 none, 1 holding poorly, 2 dragging. An alarm sounds only when the
  level rises; "holding well again" is said once; after an hour of good
  holding the next trouble is news again. Older saves take the level from the
  alarm. Magic Anchor uses the same model.
- **VHF calls** (`src/core/vhf_radio.gd`, `src/ui/vhf_dialog.gd`): at most one
  call per 6 h slot of a voyage, a pure function of (departure, slot, seed):
  a yacht asking a vessel to stand by (8 %, 16 % in hazardous weather) or a
  fishing boat asking for the forecast (12 %). Optional: declining is fine
  ("another vessel answers"), and a call not answered within an hour lapses.
  Answering an assist call stands the boat by (`Voyage.standby_until`,
  optional in saves; the simulation keeps the boat where it is until then,
  then the voyage goes on by itself). Thanks (renown 4/6 and €120/200, or
  renown 1 for the forecast) are paid once per call through the objective
  progress record (`vhf:<id>`), so no save and load pays twice. An assist
  call wakes the captain and stops Long Passage (`STOP_VHF`).
- **Localization**: English and Dansk, see `docs/technical/LOCALIZATION.md`
  (catalogue, `Loc` helpers, first-launch picker `LanguagePicker`, the
  Settings switch, tools and glossary).

## The World Awaits (Iteration 16, 0.103a)

How-tos: [DEV_GUIDES/CHART_REGIONS.md](../../DEV_GUIDES/CHART_REGIONS.md) (world
chart, Date Line, rebuilding, adding regions),
[DEV_GUIDES/HARBOURS.md](../../DEV_GUIDES/HARBOURS.md) (international harbours),
[DEV_GUIDES/WEATHER.md](../../DEV_GUIDES/WEATHER.md) (global wind).

- **One nested chart** (`NavGrid.load_world`): the world raster (12 cells per
  Mercator degree, wrapping columns) holds Europe as a region (factor 5), which
  holds Denmark (factor 6). `grid_at` / `child_at` / `all_grids` walk it;
  line checks cut at region edges and continue across the Date Line.
- **Routing** (`SeaRouter.load_world`): the world, Europe and Denmark graphs
  are merged recursively (`_merge`); A* runs on 3-D points on a sphere, so
  there is no seam or antipode. Approach limits scale with the cell size
  (`berth_radius_nm`, `approach_radius_nm`). `get_loaded()` answers without
  loading. Paths keep longitudes within ±180°; `GeoMath.wrap_delta`
  makes every distance, bearing and interpolation take the short way;
  `Voyage.position_at` returns normalized positions.
- **Drawing** (`MapView`): below 9 px per degree the world overview layer, above
  it Europe's own land plus the regional world layer; each 10° world tile is
  one triangle array and one line batch, shown only when in view; land, Europe
  and region shapes are prepared once and kept in static caches. Land near
  ±180° is drawn again one world-width away; markers, labels, courses and
  weather use the copy nearest the view. `land.res` (`WorldLand`) is the
  binary form of the world land.
- **Weather**: `WindField` adds a wrapping global lattice (latitude belts and
  regional anchors) and cross-fades its waves near the Date Line;
  `WeatherModel` keeps per-bucket reach boxes so a sample only looks at
  nearby events.
- **Long Passage** (`Simulation.start_passage`, `PassagePanel`): the same
  `advance()` in event-stopping chunks of `passage_rate` × frame time;
  `passage_interrupted(reason, text)` when it stops. Not saved. Since The
  Well-Run Ship it is shown on the `VoyageMap` (see *Time passing on screen*).
- **Passage stores**: `VesselDefinition.passage_stores_days`;
  `GameSession.buy_provisions(target)`; `Provisions` validates up to
  `MAX_STORE_DAYS`. Save format 12 unchanged.
- **Captain's Log firsts**: `GameSession._award_world_firsts` in
  `complete_voyage`, each paid once through `_award_once`.

## A bigger world, a better boat (Iteration 14, 0.102a)

Detailed regional charts (Denmark first) and boat care. How-tos:
[DEV_GUIDES/CHART_REGIONS.md](../../DEV_GUIDES/CHART_REGIONS.md),
[DEV_GUIDES/BOAT_CARE.md](../../DEV_GUIDES/BOAT_CARE.md).

- **Regions.** `data/navigation/regions.json` lists region packages
  (`region.json`, `navmask.png`, `land.json`, `graph.json`, built by
  `tools/navigation/build_region.py` from OSM land polygons). `NavGrid`
  keeps the base chart and holds the regions (`regions`, `grid_at()`,
  `region_id_at()`); `cell_class_at_geo()` and `is_geo_line_clear()` are
  composite and clip a line at region edges. `SeaRouter._load_graph()`
  disables base nodes inside a region, appends the region's nodes (in base
  cell units), adds seam edges and skips blocked base edges;
  `find_port_approach()` searches the finest grid. `MapView` clips base land
  and coast outside regions and adds an overview and a detail layer per region,
  switched by zoom (`_update_region_detail()`); a base label that a region
  also places is dropped. Godot's 32-bit `Vector2` sets the seam nudge and
  edge clamp (`SEAM_NUDGE`).
- **Recovery on load.** `GameSession.replace_state()` calls
  `_recover_location()`: an invalid voyage position, anchor or course is moved
  to `SeaRouter.nearest_navigable()` and re-planned; reported through
  `location_recovered` and `get_last_location_recovery()`.
- **Harbours.** 23 Danish ports; `HarbourFacilities` gains `haul_out` and
  `get_tier()` (small / larger / major); a port without a file hauls out when
  it has importance 1.
- **Boat care state.** `SessionState.boat_care` {vessel id → `BoatCareState`}
  (hull cleaned at, rig wear, engine hours, upgrades, history), created lazily
  per boat. Save format 12; `SaveManager._migrate_11_to_12` derives a starting
  record from the Log's miles.
- **Rules.** `BoatCare` (static): levels per area, wear (`rig_wear_for`,
  `fouling`), effects (speed and damage multipliers), quotes, the equipment
  catalogue (`data/boat/equipment.json`). `GameSession._wear()` runs in
  `apply_simulation_step`; `get_vessel_profile()` returns the base profile with
  the effects applied (cached by key), so sailing, the ETA and propulsion use
  it. Transactions: `perform_service`, `haul_out(extras)`, `install_upgrade`;
  refusals: `service_refusal`, `upgrade_refusal`. Equipment effects are read
  through small getters (`get_cool_box_capacity`, `get_calm_cooking_wind_kn`,
  `get_anchor_holding_bonus_kn`, `get_warning_horizon_hours`). Repairs are
  paid (`repair_vessel()` is the repair service).
- **Passage Readiness.** `PassageReadiness.assess(path)` (static) uses
  `Simulation.estimate_route_seconds()` and `route_hazards()`; shown by
  `WorldMap._update_readiness()` (cached by course, boat, stores and the half
  hour) and in `App.request_departure()`'s question. It never gates.
- **Presentation.** `BoatyardMenu` → **Boat care…** (`care_requested`) →
  `BoatCareMenu` (with `BoatCareView`) → `HaulOutPanel` (`HaulOutScene`). The
  App spends their time with `Simulation.spend_time_ashore`. The Captain's Log
  has a Boat tab (`TAB_BOAT`).
- **Diagnostics.** `location_recovered`, `boat_care_open`, `boat_service`,
  `upgrade_fitted`, `haul_out`, `readiness`, `save_migrated`.

## The catch and the cove (Iteration 13, 0.101a)

Fishing, the galley and the anchor, built on the existing systems; tunables
and the models are in [DEV_GUIDES/LIFE_ABOARD.md](../../DEV_GUIDES/LIFE_ABOARD.md).

- **State.** `SessionState` gains `fishing` (`FishingState`: rod, lures, the
  line, the cool box with unique fish ids, records, the five trophies),
  `galley` (`GalleyState`: well fed until, meals) and `anchor` (`AnchorState`:
  active, position, scope, set quality, holding, alarm, dragging). GameSession
  is the only writer. Save format 11; `SaveManager._migrate_10_to_11` adds the
  empty sections. Validation rejects a fish twice in the cool box, more fish
  than it holds, and an anchor down outside a voyage. While anchored the
  boat's position is the anchor's (dragging moves it), not the voyage's.
- **Time.** `Simulation.advance()` runs the new checks on fixed grids, so the
  outcome never depends on how time is chopped: bite checks every
  `FishingCatalog.check_interval_s` with the line out (moored, at anchor, or
  trolling along the course), and anchor checks on the weather's evaluation
  grid while anchored (the voyage waits; the weather is still assessed). A
  bite or an anchor alarm stops sleep (`STOP_BITE`, `STOP_ANCHOR`) and drops
  20× to 1×. `spend_time_aboard(minutes, sheltered)` is used for waiting at
  the rod, cooking and anchor work.
- **Rules.** `FishingCatalog` (data, regions, bite chance, the seeded pick,
  trophy score), `FishFight` (the real-time tension game), `Recipes`,
  `AnchorSite` (suitability from the land/water grid, the fetch upwind, the
  holding margin). All transactions are single GameSession calls
  (`finish_fight`, `cook`, `drop_anchor`, `adjust_anchor`, `raise_anchor`,
  `sell_fish`, `buy_lure`) that either complete or change nothing.
  Milestones use the ObjectiveProgress ledger (`_award_once`), and
  `get_aboard_moments()` turns them into Captain's Log notable moments.
- **Presentation.** `BoatArea._setup_aboard_gear()` places the rod holder,
  windlass, galley stove and trophy board (`src/aboard/`) from each boat's own
  outline and fixtures, each with a `HighlightProvider`; the panels are
  `FishingMenu`, `CookingMenu`, `AnchorMenu` and `TrophyMenu`; the HUD's
  `AboardBadge` shows "Fish on!", the line, the anchor's holding (red when
  dragging) and "Well fed". The App waits 45 s of play for the captain to reach
  a biting fish, and sounds `FishingSounds` cues, each with a visible
  counterpart. At anchor the sails are furled and the helm asks to raise the
  anchor first.
- **Companions.** The cat's and the dog's `CompanionVisualSet`s point at the
  illustrated art in `assets/companions/` (painted by
  `tools/companions/paint_companions.py`); the owner's drawings stay in
  `Visuals/Cat/`. `ShipCompanion` is a highlight provider for `pet`: the focus
  glow follows the silhouette of the pose shown (`ShipCompanion.silhouette`).
- **Eight directions.** In the course view `BoatArea.get_target_rotation()`
  uses `get_view_octant()`: the heading's octant with
  `OCTANT_HYSTERESIS_DEG` (8°). The simulation's heading is untouched. The
  camera follows the captain along the turned boat
  (`get_course_camera_target`), so on long north/south views the part of the
  deck they are on stays in view; movement stays screen-relative
  (`Player.view_rotation`).
- **Diagnostics.** Bounded events: `fishing_*`, `fish_landed`, `cooking`,
  `meal`, `galley_open`, `anchor`, `anchor_open`, `anchor_state`,
  `anchor_alarm`, `sleep`, `companion_pet`, `view_octant`.

## A little harbour life (Iteration 12, 0.100c)

- **Hat feedback.** `HatBadge` (`src/ui/hat_badge.gd`, in the HUD under the
  area panel) reads `GameSession.is_hat_at_risk()` (worn, warned, on deck) and
  the hat status: a fluttering hat with "Hold onto your hat! [H]", or "Hat
  missing" until a hat is bought. The hat's warning and loss toasts stay up 7 s
  and 9 s (`HatBadge.WARNING_SECONDS`, `LOST_SECONDS`); the loss reads "Hat
  overboard! …" and pulses the badge. Toasts sit above every panel
  (ToastLayer 30). `HatBlowAway` is larger and longer (2.8 s). No loss rule
  changed.
- **Shortcut strip.** The HUD's `Controls` is a dark translucent panel with key
  caps (`Hud.SHORTCUTS`); `get_controls_text()` gives it as text.
- **Highlights.** `Interactable` no longer draws a ring. While focused it draws
  a soft glow around `highlight_outline`, set by `BoatArea._resolve_highlights()`
  from `HighlightResolver`: a provider node in the `interaction_highlight` group
  (the hat hook, each harbour sign, both via `HighlightProvider`), else the
  nearest furniture fixture named for the interaction (`FIXTURES`: the chart
  table for `nav_table`, the berth for `bed`, …), else a small outline of the
  area itself. Interaction areas and focus priority are unchanged. F8 (with the
  developer tools) toggles `Interactable.debug_show_areas`.
- **Shore access.** `ShoreAccess` (`src/harbour/shore_access.gd`) is added by
  `BoatArea._setup_shore()` to decks with a pontoon, before the player is
  placed:
  - the gangplank lands at the boat's own `from_boatyard` spawn x;
  - in harbour the closed `Lifeline` polygon is disabled and replaced by the
    same outline with a gap where the plank crosses it, the plank's sides, and
    a shore strip on the pontoon (the back of the pontoon is kept for the
    signs);
  - `walkable_bounds` widens to include the shore;
  - underway the rail closes again, and a captain ashore is put at
    `from_boatyard`.

  The shore stations (`grocery`, `boatyard`, and `go_ashore`, created at
  runtime) are placed in `ShoreAccess.get_service_slots()`.
  `HarbourDressing` draws their signs there (Go Ashore with a compass icon),
  and the classic labels follow. When the captain is ashore the camera's
  `offset.y` glides down so the pontoon shows (`get_shore_camera_target()`).
- **Facilities.** `HarbourFacilities` (`src/harbour/harbour_facilities.gd`):
  `grocery`, `boatyard`, `go_ashore`, all true by default. Per-harbour files
  live in `data/harbours/facilities/<port_id>.tres`: Copenhagen (all) and
  Lohals (no boatyard). The harbour builder never touches them.
  `GameSession.has_facility()` / `facility_refusal()` guard:
  - `can_change_vessel()` (the boatyard), `switch_vessel()` and
    `repair_vessel()`;
  - `buy_provisions()` and `buy_hat()` (the grocery store);
  - the App's `open_boatyard()`, `open_grocery()` and `open_go_ashore()`.

  Unavailable stations are disabled, hidden and not monitorable; their signs
  and labels are hidden.
- **Lohals** (`lohals`, UN/LOCODE DK LOH) was added through
  `tools/navigation/harbours.csv` and `build_harbours.py`. It passes the
  harbour suite's checks: approach from open water, coast and route. The
  catalogue now has 164 harbours.
- **Go Ashore.** `ShoreEvents` (`src/harbour/shore_events.gd`) holds 8 generic
  events, plus one each for Copenhagen and Lohals.
  - `GameSession.get_shore_event()` offers events not yet enjoyed in this
    harbour first, in an order fixed per game (a hash of the wind seed, the
    port and the outings there), so reopening never re-rolls. After an outing
    the harbour "rests" for `REST_HOURS` (6 h).
  - `apply_shore_choice()` is one transaction. It pays the cost, records the
    outing in `ObjectiveProgress.completed` under `shore:<port>:<event>`
    (`ObjectiveProgress.mark()`, or `award()` with renown the first time), and
    emits `renown_awarded`. Using the existing, already-saved records means
    **the save format did not change**, and a reward can never be paid twice,
    even after loading.
  - `Simulation.spend_time_ashore()` passes the time, with the hat sheltered.
  - `GameSession.get_shore_moments()` feeds the Captain's Log's *Notable
    moments*, merged with the hat's story.
  - `GoAshoreMenu` (`src/ui/go_ashore_menu.gd`) is the panel.
- **Course view.** With `SettingsManager.get_course_view()` (default on,
  Settings → *Sailing view*), `BoatArea._update_camera()` turns the deck camera
  while underway so the bow points along the course, north up. The rotation is
  `deg_to_rad(90 − heading)`, from `get_view_heading()`: the voyage leg's
  course, or a test's `view_heading_override`, which is presentation only.
  - **Zoom** fits the turned boat in the screen minus `COURSE_SCREEN_MARGIN`,
    never below `COURSE_MIN_ZOOM` (0.78), so the deck stays readable at
    north/south headings. The camera centres on the boat. Rotation, zoom and
    position tween together (1.8 s) at departure, at each new leg
    (`voyage_course_changed`) and on arrival, so there is no per-frame motion.
  - **The rest follows the view.** The HUD is on its own layer and stays
    upright. `Player.view_rotation` makes the movement keys screen-relative.
    `WaterLife` reads the same view heading, so the waves keep their world
    direction, and computes its view rectangle from all four corners. The
    deck's water polygon is enlarged to fill a turned view. `SailRig` leaves
    the camera offset alone in the course view.
  - Moored, the deck is upright as before.
- **Diagnostics** (SessionLog): `hat_warning_shown`, `hat_lost_shown`,
  `gangplank` (to shore / boat), `facility` (opened / unavailable),
  `shore_event`, `shore_choice` and `course_view` (heading and zoom, once per
  deck).

## A living little world (0.100b)

All presentation; nothing here changes sailing, routing, weather, economy,
rescue, progression or saves.

- **Sailor.** `SailorDrawing` (`src/player/sailor_drawing.gd`) draws the
  top-down sailor (shoulders, arms, hands, head) for `Player._draw()`. The arm
  swing comes from `Player._walk_phase`, advanced by the distance actually
  walked (so it stops against a wall), and eases to rest. `Player.get_carry_point()`
  is the left hand, where `PlayerHat` draws a carried hat. Collision (radius 20),
  movement, interaction reach and the hat states are unchanged; no animation
  framework.
- **Living water.** `WaterLife` (`src/water/water_life.gd`), added by
  `BoatArea._setup_water_life()` to every deck's `Surroundings` right above
  `Water`, draws procedurally on real time with a fixed seed (moving while the
  game clock is paused, stopping when a menu pauses the tree). Moored: rings,
  wavelets and glints, lapping along the hull polygons named `*Hull*`/`*Ama*` in
  `Visual/HullBase` and along the pontoon, plus at most six drifters chosen by
  the harbour's broad atmosphere (`marina`, `coastal`, `urban`), from
  `HarbourArt.atmosphere` when set (Copenhagen: `urban`), else derived from the
  catalogue (island: coastal; importance 3: urban; otherwise marina). Underway:
  up to 70 crests across the WeatherModel wind at the boat, seen relative to the
  course, more and livelier with wind speed, white flecks from 20 kn, streaming
  aft with boat speed. Element counts are fixed (nothing accumulates); strokes
  are batched into one `draw_multiline_colors` call per line width. Classic art
  hides it and shows the old `Ripple*` strokes.
- **Underway framing.** `BoatArea._setup_camera()` (decks only) remembers the
  scene's camera zoom and tweens to `UNDERWAY_ZOOM_FACTOR` (0.86) of it on
  departure, back on arrival or rescue (`ZOOM_TRANSITION_S` 1.8 s, sine). The
  camera does not move, so there is no jitter; `SailRig` still owns `offset.x`
  for the spinnaker.
- **Illustrated boats.** Every boat has an `illustrated_visual_profile` with
  PNGs under `assets/vessels/<id>/illustrated/`. The Wing 33's are painted by
  `tools/vessels/paint_illustrated_starling.py`; the others by the generic
  `tools/vessels/paint_illustrated_vessel.py`, which reads each boat's own
  `deck_visual.tscn`/`cabin_visual.tscn` (so art and collision always line up)
  and maps the scene palette to materials. Both share `tools/vessels/illustrate.py`
  (ink, wobble, shading, and the marine teak helpers `teak_deck()`/`teak_sole()`).
- **Arctic Wanderer 26.** Scenes generated once by
  `tools/vessels/build_arctic_wanderer_26.py` (same conventions as the multihull
  builder, which it reuses): 770 units long, tiller cockpit with coamings,
  modest coachroof, single-level cabin. Profile `data/vessel/arctic_wanderer_26.tres`.
- **Tests.** New games start aboard the 26, so suites whose scripted walks or
  timings were written for the Wing 33 call `t.board(&"starling_33", app)` right
  after starting a game (having checked the game starts aboard the 26); the
  all-boats suites (vessels, hat, living, living world) include the 26.

## Harbour presentation and the illustrated prototype (Visual Identity V01)

- **Artwork setting.** `SettingsManager` has `art_style` (`illustrated`,
  default, or `classic`), saved in `settings.cfg` and offered in Settings as
  *Artwork*. `VesselDefinition.get_active_visual_profile()` returns
  `illustrated_visual_profile` when the setting asks for it and the boat has
  one (every boat since 0.100b), otherwise `visual_profile`. `BoatArea`, the
  boatyard preview and the provisions display use it; `BoatArea` re-applies it
  live on `art_style_changed` (for the boat it was built for).
- **Harbour.** `BoatArea` adds a `HarbourDressing` to the deck's
  `Surroundings/Mooring`, right above the pontoon shape, so it shows only in
  port, over the water and under the boat. It draws the illustrated pontoon,
  ropes, cleats, quay and water from the mooring's own nodes, wooden signs for
  the enabled `grocery` and `boatyard` stations, the harbour's name sign in the
  display font (the existing label with other `LabelSettings`) and the
  landmarks of `HarbourArt.for_port(location_id)` (at most three; none needed).
  It has no collision and hides itself under the Classic setting, which shows
  the original pontoon drawing.

## Harbour catalogue at scale (Iteration 006)

- **Records:** each `PortData` stays a small resource, with `importance`
  (1–3), `region`, `island` and `source` (where the coordinate comes from).
  Ids are stable and never renamed; saves refer to them.
- **Source of truth:** `tools/navigation/harbours.csv`.
  `tools/navigation/build_harbours.py` writes `data/navigation/ports/*.tres`
  and `port_catalog.tres`.
  - The 148 added harbours take their coordinates from UN/LOCODE (UNECE), to
    the arc-minute; the entry is named in `source`.
  - Candidates that failed validation are kept, with the reason, in
    `harbours_rejected.csv`.
- **Lookups:**
  - `PortCatalog.get_port()` uses an id dictionary (previously a list scan).
  - `ports_in_rect()` uses a 2° grid.
  - `search(text)` matches names and countries.
- **Routing needs no new data:** the sea graph is independent of ports. A
  harbour joins the network at runtime through `SeaRouter.find_port_approach`.
  `test_harbours` proves that every harbour:
  - has an approach;
  - lies on a coast;
  - lies within the chart;
  - routes to its nearest original harbour.

  It also runs representative coastal, island, offshore, narrow and long
  trips.
- **Chart:** `MapView._update_port_layout()` is recomputed only when the view
  changes.
  - It considers only the harbours in view (plus a margin).
  - It gives a marker to those whose importance the zoom shows:
    `PORT_MARKER_PX_PER_DEGREE` = 0 / 45 / 110 px per degree for importance
    1 / 2 / 3. The selected, destination and current harbours always get one.
  - It places labels in priority order on the first free side (right, left,
    above, below), so names never overlap.
  - Hidden harbours cannot be clicked, but the Course tab's *Find a harbour…*
    search lists every harbour. Choosing one selects it and zooms the chart
    until it shows. Typing there does not pan the chart.
- **Not built:** chunk loading and clustering. They are not needed at this
  size; the measured layout cost is in the I006 report.

## Mid-voyage rerouting

`SeaRouter.plan_route()` accepts either a port origin or an arbitrary origin
position (empty origin port id). At sea, `GameSession.change_course(destination,
waypoints)` plans from the vessel's *current* position using the same router and
validation as departures:

- On success it replaces the voyage's route and resets `progress_nm` to 0 on the new
  path, which starts exactly at the current position, so there is no jump. It also
  increments the revision and clears the warned list.
- The clock, boat area and player position are untouched.
- On failure nothing changes and the reason is returned.

The chart's draft may be a little behind a moving boat. That doesn't matter, because
`change_course()` always replans from the position at the moment of applying.

## Wind, sailing performance and propulsion

### Wind field

`WindField` (`src/weather/wind_field.gd`) is the **background** wind of the
weather model. The query is `sample(geo, game_time, seed) -> Sample{from_deg,
speed_kn}`. Since Iteration 005a nothing reads it directly except
`WeatherModel.sample()`; the simulation, ETA, chart, HUD and sails use
`Simulation.get_wind_at(geo)` / `get_weather_at()`, which return the full
`WeatherSample`.

- **Convention:** meteorological. `from_deg` is where the wind comes FROM
  (0 = north, 90 = east). Chart arrows point where it blows TO (`to_deg()`);
  `to_vector()` is the air movement as Vector2(east, north).
- **Climatology:** ~40 anchors in `data/weather/wind_climate.json` (Atlantic
  westerlies, Portuguese trades, Mistral, Meltemi, a lighter and changeable Baltic,
  …), blended with Gaussian weights (σ = 4°, longitude scaled by cos(lat)). The
  blend is precomputed once on a 0.5° lattice covering 27°W–39°E, 31–73°N
  (~0.3 s, lazily) and interpolated bilinearly, so the field is continuous with no
  region borders. Points outside the lattice clamp to its edge.
- **Weather on top:** three travelling sine waves veer/back the direction, two
  scale the speed (scaled by each place's variability) and a lull wave sweeps
  light-air patches across sea areas. All are pure functions of
  (position, time, seed).
- **Cost:** ~10–15 µs per sample (headless). The chart overlay caches samples per
  lattice point.
- **Tests:** `test_override` (a Callable) lets tests force a known wind; it is
  never set in normal play.

### Sailing performance

`VesselProfile.sail_speed_kn(tws, twa)` (the potential sail-only speed):

```
max_sail_speed_kn (10) × (1 − e^(−tws / 9)) × smoothstep(0.8, 3.0, tws)
  × angle_efficiency(|twa|) × (1.12 if spinnaker angle) , capped at 10 kn
```

- **Angle efficiency** (a `Curve`): 0 inside 35° (head to wind), 0.35 at 45°,
  0.85 at 80°, 1.0 at 110°, 0.66 dead downwind.
- **Examples at 12 kn of wind:** ≈2.6 kn at 45°, ≈7 kn on the beam, ≈7.8 kn at
  130° (with spinnaker), ≈5.4 kn running. 10 kn needs ≈25 kn of wind on a broad
  reach.
- **Relative wind angle:** `WindField.relative_angle(heading, wind_from)` is
  signed, in (−180, 180]: + = wind from starboard, − = from port.

### Propulsion controller

`PropulsionController.evaluate(state, profile, now, heading, wind, force_reset)`
runs at every evaluation point. It returns a new `PropulsionState`; sail and
engine are mutually exclusive. The thresholds below are all `VesselProfile`
exports:

| Rule | Value |
|---|---|
| Engine speed | 5 kn |
| Rolling average of the potential sail speed | exponential, time constant 3600 game s, updated with elapsed game time |
| Sail → engine (poor) | average < 3.5 kn, after ≥ 900 s under sail |
| Sail → engine (near stall) | potential < 0.5 kn continuously for ≥ 600 s (any average) |
| Engine → sail | average > 6.0 kn continuously for ≥ 1200 s, current potential > 6.0 kn, and ≥ 1800 s motoring |
| Course change > 30° (or a change of course) | average restarts from the new heading's potential; favourable timer resets; the stall timer resets only if the new heading is no longer becalmed |
| **Reassessment** (a change of course applied by the player, or the helm's "Check sail configuration") | engine → sail at once if the current potential > 6.0 kn (no 1200 s confirmation); sail → engine at once if the current potential < 3.5 kn (no wait for the average). The minimum times (900 s sailing, 1800 s motoring) still apply. A reassessment resets no timer. |
| Departure / first evaluation | engine (reason "start") if the potential < 3.5 kn, else sail |
| Spinnaker | sailing and \|twa\| ≥ 115° (bonus ×1.12 in the polar) |

The 3.5–6 kn gap plus the minimum times give the hysteresis; the potential is
also evaluated while motoring.

**Reassessment (Iteration 003b).** Iteration 003 already re-evaluated the controller
on a change of course and restarted the rolling average from the new heading. That
part was verified and kept. Two gaps remained:
- After turning from a beat into a good breeze while motoring, the engine still
  waited for the 20-minute confirmation.
- After turning into poor wind under sail, the boat waited for the average.

`PropulsionController.evaluate(…, reset_history, reassess)` now separates the two
ideas:
- `reset_history` (a turn) restarts the average;
- `reassess` lets clearly good or poor *current* conditions decide at once.

`Simulation._on_course_changed` uses both. `Simulation.reassess_propulsion()` (the
helm) uses only `reassess`, so repeated checks reset nothing. The minimum times in
each mode bound how often the mode can change, however often the player checks.
The HUD, sails and engine sound follow through `propulsion_changed`, as for any
other change. Speed is the engine speed or the potential sail
speed until the next evaluation point.

### ETA

`Simulation.estimate_route_seconds(path, from_nm, start_time, to_nm)` walks the
remaining route in 5 nm steps, sampling the wind expected at each point and
time. It uses a simple rule: sail if the potential is ≥ 3.5 kn, else motor at
5 kn. It is an estimate: it ignores the controller's averaging and hysteresis.
`get_eta()` caches the result per voyage, wind seed, 2 nm of progress and 30 game
minutes. The departure dialog, chart and HUD show it as "about …".

### Presentation

- **Chart** (`src/navigation/wind_layer.gd`): arrows (TO direction, coloured by
  speed band) on an absolute map lattice whose spacing is a power of two chosen
  for ~72 px on screen, skipped on land. A smooth speed tint (an image with one
  pixel per half-lattice point, linear filtering) lies between the water and the
  land fill. There is a legend and a **Wind** toggle in the toolbar; the cursor
  readout includes the wind there. Samples are cached per lattice point; the tint
  image covers the view plus a margin and is reused while panning; arrows are
  batched into four draw calls. Wind time refreshes every 600 game seconds.
- **HUD:** wind ("Wind WSW 14 kn · 135° starboard"), propulsion with reason
  ("Under sail · broad reach · 7.4 kn · spinnaker set",
  "Motoring · insufficient sailing performance · 5.0 kn",
  "Motoring · becalmed or head to wind · …"), speed, distance to go and ETA.
- **Sails:** see *Sail rig* above.
- **Engine sound:** see *Audio framework*.

### Extending it

- **Real weather / forecasts:** replace the climatology and waves behind
  `WindField.sample()` (background) or the event generation in `WeatherModel`;
  callers do not change.
- **Manual sail/engine control:** add an override field to `PropulsionState`
  that `PropulsionController` respects.
- **Tacking:** a router or controller concern. Today a head-to-wind leg is
  simply motored.
- **Currents:** add a drift vector to the speed over ground in `advance()`.

## Save/load architecture

```
GameSession.get_state_snapshot() ─► SaveManager.save_to_slot(slot, state)
SaveManager.load_from_slot(slot) ─► LoadResult{state | error} ─► App ─► GameSession.replace_state()
```

- File layout: `{format, version, game_version, saved_at_unix, saved_at_utc, session: SessionState.to_dict()}`,
  written with full float precision. Session sections: `boat`, `player`, `clock`,
  `wind` (seed), `vessel` (status, position, propulsion state), `navigation`
  (location, planned route with its path, active voyage with route, progress,
  revision and warned weather ids).
- **Version 10** (Visual Identity V01) adds the `hat` section (`HatState`).
  `_migrate_9_to_10` gives every older game the original hat on its hook,
  with hat checks starting at the saved game time.
- **Version 9** (Iteration 006) adds the `progress` section
  (`ObjectiveProgress`). `_migrate_8_to_9` starts it empty: no renown is paid
  for the past. Objectives are checked against the Captain's Log at the next
  voyage's end.
- **Version 8** (Iteration 006) adds the `log` section (`CaptainsLog`) and,
  in an active voyage, `departure_port_id`, `departure_position`,
  `sailed_nm`, `worst_hazard`, `damage_percent` and `fully_recorded`.
  `_migrate_7_to_8` invents nothing: no voyages, distance or arrivals. As
  visited (first visit unknown) it lists only Copenhagen, where every older
  game started, and the harbour the boat lies in. A voyage under way gets its
  course's origin, `sailed_nm` = progress and `fully_recorded = false` (its
  earlier weather and damage are unknown).
- **Version 7** (Iteration 005b) adds `economy.funds`, `provisions`, `rescue`
  (`count`, `last`), and in `vessel` the `conditions` by id and
  `damage_applied_until`, all required by `from_dict`. `_migrate_6_to_7` fills
  them as a new game would (€10,000, 14 days, every boat at 100 %, no rescues),
  with damage counted from the saved time. Voyages underway are kept.
  Development test weather is never part of the state.
- **Version 6** (Iteration 005a) adds the `weather` section:
  `{"model_version", "exposure"}` (`WeatherExposure.to_dict`), required by
  `from_dict`. `_migrate_5_to_6` adds it with a fresh Normal exposure at the saved
  time and clears `voyage.warned_conditions` (their ids named the retired
  demonstration areas). Nothing else changes: the weather is recomputed from
  `wind.seed`. Migration chains 1 → … → 6.
- **Version 5** (Iteration 004) adds `vessel.id`, which `from_dict` requires as a
  non-empty string. `_migrate_4_to_5` sets `starling_33`. An id the catalog does
  not know still loads: `GameSession.replace_state()` (`_check_vessel`) switches to
  the starter, resets the spawn to `start` and emits a `notice` naming the unknown
  boat. Migration chains 1 → 2 → 3 → 4 → 5.
- **Version 4** (Iteration 003b) adds the `companion` section: `kind`, `spot`,
  `next_move_time` and `moves`, validated by `CompanionState.from_dict`.
  `_migrate_3_to_4` gives older games the default companion: a cat in its first
  spot, with its schedule starting at the saved game time. Sail animation phases
  are not saved (cosmetic). Migration chains 1 → 2 → 3 → 4.
- **Version 3** (Iteration 003) adds `wind.seed` and `vessel.propulsion`.
  `_migrate_2_to_3` sets seed 1, removes the old constant `speed_kn` and adds an
  uninitialised controller state. On load, `Simulation` evaluates it at once
  from the wind at the saved position and time. No time passes and the boat
  does not move (no offline travel). Migration chains 1 → 2 → 3.
- **Version 2** (Iteration 002). `_migrate_1_to_2` upgrades Iteration 001 saves:
  - default clock (start time, 1×);
  - vessel moored at its port;
  - no voyage;
  - the old planned route keeps its destination and waypoints, with an empty path.

  `GameSession.replace_state()` then recalculates such a route as a sea route, or
  removes it and emits a `notice` if that is impossible.
- Underway saves are cross-checked: status ⇔ voyage ⇔ empty location, progress within
  the route, and the saved vessel position must match the position derived from the
  progress (≤ 0.001°). Loading continues from the saved progress, never from the
  departure port.
- Validation is complete before anything is applied: `SessionState.from_dict` builds
  a brand-new state or returns `null` with reasons. `App.load_slot` only touches the
  session and the scene after success, so a failed load leaves the game untouched.
- Slot statuses: `EMPTY`, `VALID`, `CORRUPTED` (unreadable, malformed or invalid
  content), `UNSUPPORTED` (version newer than the game or invalid).
- Safe writes: `slot.tmp` → read back and compare → old file to `slot.bak` → move
  `tmp` into place (restore `.bak` on failure). A slot whose main file is missing but
  has a `.bak` (interrupted write) loads from the backup.
- `SaveManager` knows nothing about scenes or `GameSession`, which makes it testable
  in isolation.

### Adding persistent state for a future system

1. Add the fields to `SessionState` (or a small data class it holds), in a **new
   top-level section** of `to_dict()` such as `"time": {...}` or `"vessel": {...}`.
2. Validate that section in `from_dict()` and return `null` on bad data.
3. Copy it in `duplicate_state()` and expose intent-level methods and signals on
   `GameSession`.
4. If older saves must stay loadable, bump `SaveManager.SAVE_VERSION` and add a
   step to `SaveManager._migrate()` that fills the new section with defaults.

Do not serialize nodes or scene trees. Scenes rebuild themselves from the state.

## Audio framework

- Buses (`default_bus_layout.tres`): Master ← Music, Ambience, SFX, UI.
- `AudioManager` keeps one music player, one ambience player and a pool of 8
  one-shot players (round-robin, oldest reused), so no nodes are created per sound.
  Looping is done by replaying on `finished`, so any stream can loop without
  editing its import settings. Playing the same ambience again is a no-op.
- **Named loops** (`play_loop(id, stream, volume_db, fade, bus)`, `stop_loop`,
  `is_loop_playing`): one player per id. Requesting a loop that already plays the
  same stream only fades its volume, so it never restarts.
- **Engine sound:** `App.update_engine_audio()` runs on `propulsion_changed`,
  screen changes and `state_replaced`. Two sample-aligned loops play on the SFX
  bus, so the SFX and Master volumes apply:
  - `engine_hum.wav`, open air;
  - `engine_hum_muffled.wav`, low-passed.

  Both start together and are only cross-faded (1.5 s):
  - on deck: open-air at −6 dB, muffled silent;
  - in the cabin and at the chart: muffled at −16 dB.

  They fade out when the sails are set, on arrival and in the main menu. The WAV
  imports use forward looping (`edit/loop_mode=2`). The 2 s files contain whole
  cycles of every component, so the loop is seamless.
- Volumes are set by `SettingsManager` directly on the buses (`linear_to_db`, with
  mute at 0%). `AudioManager` does not deal with volume.
- **Weather sounds** (Iteration 005a): `storm_wind.wav` as the named loop
  `storm_wind` and `thunder.wav` as one-shots, both on the Ambience bus (see
  *Weather model → Presentation*).
- Every `BaseButton` gets the UI click sound automatically (`App` listens to `node_added`).
- Boat areas export their `ambience` and `interaction_sound`. Settings has test
  buttons per bus. All current sounds are temporary placeholders.

## Settings system

`SettingsManager` setters apply immediately; `save()` persists; `snapshot()` and
`restore_snapshot()` let the settings menu preview changes and revert them;
`load_settings()` validates every value (type, range, known enum) and falls back to
defaults. The menu (`src/ui/settings_menu.gd`) builds the five audio rows from
`SettingsManager.AUDIO_BUSES`. Window-mode changes are skipped when headless or
embedded in the editor.

The language (I019) is a preference too: `get_language()`, `set_language()`
(applied at once with `TranslationServer.set_locale`, signal
`language_changed`), `has_chosen_language()` (empty until the first-launch
picker), stored as `[interface] language`. "Restore defaults" keeps it. The
test runner sets English before every suite.

## Integrating future systems

| Future system | Where it goes |
|---|---|
| Real weather, forecasts, currents, tacking, manual sail/engine control | See "Wind, sailing performance and propulsion → Extending it". |
| More weather (fog, rain, waves, real forecasts) | Extend `WeatherModel.sample()` and `WeatherSample`, with data in `weather_events.json`; bump `model_version` if old saves would see different weather. |
| Separate damage (hull, engine, sails), repair costs, insurance | Extend the condition model behind `GameSession.apply_weather_damage()` / `repair_vessel()`; charge through `funds`. |
| Shops, prices, more income | Transactions on `SessionState.funds` through `GameSession` methods (`buy_provisions`, `pay_remote_work` show the pattern); regional prices would change `get_provisions_price()` only. |
| Depth / draft limits | Another `NavGrid` cell class or a per-vessel mask; `SeaRouter` callers do not change. |
| Money, provisions, equipment, vessel condition | Each its own section in `SessionState` and small owner API on `GameSession` (or a dedicated service if it grows); UI panels subscribe to signals. |
| New interactions | Add an `Interactable` to a scene. Messages need no code; new behaviours add an id branch in `BoatArea` or, once there are many, a small handler resource. |
| More vessels | A `VesselDefinition` `.tres` with a new stable id, deck/cabin scenes with the standard structure (start from a copy, or extend `tools/vessels/build_multihull_scenes.py`), a `VesselProfile`, and an entry in the catalog. `tests/suites/test_vessels.gd` checks every catalog entry automatically. |
| Buying, upgrades, maintenance, decoration | A section in `SessionState` for owned boats or condition, and `GameSession` methods next to `switch_vessel()`. The boatyard is the natural UI; `VesselDefinition` can gain price or upgrade slots. Visual upgrades can be extra slots or profile variants. |
| More boat areas | Add the id to `SessionState.BOAT_AREAS` and a scene field to `VesselDefinition` (`get_area_scene()`), with the standard `Layout`. |
| More ports | New `PortData` resources in the catalog (a harbour approach is found automatically; tests check every port). |
| Larger regions | Regenerate the navigation data with other bounds; for worldwide coverage the raster and graph would need tiling. |
| Real audio | Replace the placeholder streams on the scenes and settings menu; buses stay the same. |
| A human crew member | Another `CompanionState` kind with its own spots, or, once it needs more (tasks, skills), its own small state class next to it. `ShipCompanion` stays the cabin presentation; nothing assumes a companion is an animal beyond the drawing and the petting sound. |

## Tests

`tests/test_runner.tscn` is a small built-in runner (no framework). Suites:
data model, routing (graph consistency, port approaches, land crossings against
the vector coastline, straits, all port pairs, waypoints, failures), simulation
(clock, voyages, step independence, sleep, weather warnings, rerouting), save
manager, voyage persistence (underway saves, migration, invalid saves), settings
and audio, wind (conventions, determinism, range, continuity, plausibility,
query speed, polar), sailing (controller rules and hysteresis, step independence
at 1×/5×/20×/sleep with sail↔engine changes, ETA accuracy, warnings with
variable speed, course changes, propulsion save/load and v2 migration),
sailing presentation (sails by wind side, spinnaker, furling, HUD, chart overlay
and toggle, engine audio across scenes), reassessment (course changes and helm
checks, hysteresis, no forced or rapid switching), life aboard (companion choice,
spots, schedule, petting, audio, persistence and migration; sleep dialog, sleeping
from cabin/deck/chart, interruptions, V-berth wake-up; chart panel geometry
stability; helm prompt and messages; sail motion and spinnaker geometry), and an
end-to-end gameplay flow driving
the real `App` with input events, including the Iteration 002 acceptance scenario.
Vessels (Iteration 004):
- **data:** the catalog, definitions and profiles;
- **scenes:** every scene instantiates, has every slot, station, spawn, sail marker
  and companion spot, and has no physics in `Visual`;
- **walking:** a flood fill with the real player shape shows that every spawn and
  station is reachable on all six areas;
- **boatyard:** opens by walking to it, preview, browsing, choosing, refused
  underway, no duplicate scenes;
- **life aboard each boat:** companionway, chart, sleep and wake at the berth,
  companion on the cabin's markers, speed from the boat's profile, sails, sail
  sprites, spinnaker and engine;
- **sprites:** the fallback order, the demo sprite with the layout unchanged;
- **time and persistence:** pause and 20× on another boat; save/load in the cabin,
  on deck, underway and after switching; v4 migration; an unknown id.
Iteration 004b:
- **`test_catamaran_cabin`:** the door to the deck (drawn where the interaction is,
  its prompt, E to deck); art matching collision; berth proportions; reaching both
  hulls with real movement input; nav station, sleep and wake, companion spots.
- **`test_companion_art`:**
  - the owner's four files and their mapping, background removal and consistent
    placement;
  - the four poses on screen, the idle behaviour over 30 minutes (no flicker), the
    approach and petting reactions with the purr;
  - fallbacks, replacing a pose image through data only;
  - all three boats, save/load and switching, the dog unchanged.
- **`test_dev_guides`:** files, links and repository paths in the guides; the
  Markdown conversion; the viewer (open, list, show, scroll, close, Esc); missing
  files.

Iteration 005a:
- **`test_weather`:** sampling (ranges, determinism, sampling never mutates),
  generated gales, risk areas and cells (lifecycle, movement, irregular shape,
  gust smoothness), cyclone risk by basin, hemisphere and month, generated
  cyclones (never in Europe), fixtures; sailing in a gale and a storm on all
  three boats; local, nearby and route warnings with de-duplication and
  escalation; identical results at 1×, 20×, large steps, sleep and across
  save/load; pause; v5 → v6 migration.
- **`test_weather_ui`:** the chart overlay equals the model's events (real
  outlines, labels, cores) through pan, zoom, pause and time; the Weather tab
  count, list and legend; the HUD in a gale; the storm sound; a sleep woken by a
  forming thunderstorm (cabin, position, pause kept, no repeat).

`--only=<name>` after `--` runs only the matching suites.
Suites written for the constant-speed model run with a **calm-wind fixture**
(`use_calm_wind()`): in a flat calm the boat motors at exactly 5 kn from
departure, so their timing expectations stay exact.
`tests/restart_check.tscn` verifies persistence across two separate processes.
Tests use scratch files under `user://test_*`, never the player's saves or settings.
