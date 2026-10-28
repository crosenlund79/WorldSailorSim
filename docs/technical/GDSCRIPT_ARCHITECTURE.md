# GDScript Architecture (developer reference)

The developer and coding-agent reference to the scripts of Little Captain's
Hat: one entry per `.gd` file with its role, real dependencies, signals,
state, lifecycle, persistence, performance notes, invariants, protecting
tests and change risks. The Captain's editions are
[GDSCRIPT_GUIDE_EN.md](GDSCRIPT_GUIDE_EN.md) (English) and
[GDSCRIPT_GUIDE_DA.md](GDSCRIPT_GUIDE_DA.md) (Danish). The narrative design
document is [ARCHITECTURE.md](ARCHITECTURE.md); localization details are in
[LOCALIZATION.md](LOCALIZATION.md); measured hot paths are in
[PERFORMANCE_OPPORTUNITIES.md](PERFORMANCE_OPPORTUNITIES.md).

**The code is the authority.** Entries were written from the source. A
relationship marked *(indirect)* is conceptual (a shared data file, a
signal relayed by another node), not a direct reference. Before changing a
script, read its entry *and* the script; run
`python tools/docs/check_gdscript_guides.py` after changing it (see
*Keeping this current* at the end of the overview).

## System overview

### Autoloads (8, `project.godot`)

| Autoload | Script | Owns |
|---|---|---|
| `SettingsManager` | `src/settings/settings_manager.gd` | Preferences in `user://settings.cfg` (audio, display, interface scale and light, accessibility, sleep hours, **language**). Applies them; signals `settings_applied`, `language_changed`, `ui_light_changed`, … |
| `AudioManager` | `src/audio/audio_manager.gd` | Buses, music, ambience, named loops, pooled one-shots. No game state. |
| `GameSession` | `src/core/game_session.gd` | The authoritative `SessionState` and every mutation of it, with change signals. |
| `Simulation` | `src/core/simulation.gd` | The single timeline: game clock, voyage movement, the 5-minute evaluation grid (wind, propulsion, weather warnings, anchor, fish, traffic, VHF), sleep, Long Passage, ETAs. |
| `SaveManager` | `src/persistence/save_manager.gd` | Save slots: JSON ↔ `SessionState`, validation, migrations 1→12. |
| `SessionLog` | `src/diagnostics/session_log.gd` | Diagnostic JSON-Lines log; reads the game, never changes it. |
| `UiTheme` | `src/ui/theme/ui_theme.gd` | The Vintage Chartroom / Harbor Dusk theme tokens and the day/night blend. |
| `MusicDirector` | `src/audio/music_director.gd` | Chooses and crossfades the soundtrack from game context. |

### Application shell and scene lifecycle

`App` (`src/app/app.gd`, main scene `src/app/app.tscn`) is the flow
coordinator. It has exactly one **screen** under `Screen`, swapped by
`SceneRouter` (old screen freed before the new one is created; the setup
callback wires signals before `_ready`), plus `HudLayer`, `ModalLayer`
(`ModalStack`) and `ToastLayer`. Boat areas come from the active
`VesselDefinition` (`deck_scene` / `cabin_scene`), all with `BoatArea`. The
tree is paused while a modal is open over gameplay; the shell, menus,
toasts and audio run `PROCESS_MODE_ALWAYS`.

### State ownership and mutation

`SessionState` (plain `RefCounted` data: voyage, propulsion, anchor,
fishing, galley, hat, companion, funds, provisions, boat care per vessel,
home per vessel, Captain's Log, progress/renown, warned conditions, …) is
written **only** by `GameSession`. Callers use intent methods that validate
and return a refusal string or a result dictionary (`depart()`,
`sell_catch()`, `answer_vhf()`), and observe signals (`state_replaced`,
`funds_changed`, `anchor_changed`, `home_changed`, `notice`, …).
`get_state_snapshot()`, `get_propulsion()`, `get_planned_route()` return
copies. `Simulation` mutates time and movement only through
`GameSession` hooks (`apply_simulation_step`, `set_propulsion`,
`complete_voyage`, `record_weather_warning`, `apply_anchor_check`, …).

### Signals and dependency flow

UI/screens → (signals) → `App` → services (`GameSession`, `Simulation`,
`SaveManager`, `SettingsManager`, `AudioManager`) → data classes and lazily
loaded data services (`PortCatalog`, `SeaRouter`, `NavGrid`,
`WeatherModel`, `WindField`, `VesselCatalog`, `FishingCatalog`,
`TrafficModel`, `HarbourTrades`). No service calls up into scenes; scenes
listen to service signals. Static `get_default()` singletons are released
on exit.

### Simulation and game time

`Simulation.advance(seconds, stop_at_events)` moves the session forward in
event-driven chunks. Evaluation points lie on a fixed 300 s grid
(`_next_grid_time`), so results do not depend on how time is chopped (1×,
20×, sleep, Long Passage, one large step: tested). At each point underway:
wind (`WindField`/`WeatherModel`), propulsion (`PropulsionController`),
route-ahead hazards (`route_hazards`, quick samples since Turbocharge),
weather damage, the hat, stores, traffic (`_assess_traffic`) and VHF
(`_assess_vhf`); at anchor: `GameSession.apply_anchor_check`. A
`stop_at_events` advance returns an `AdvanceResult` whose `stopped_by` says
why it stopped (`STOP_WARNING`, `STOP_ARRIVAL`, `STOP_TRAFFIC`, `STOP_VHF`, …).

### Weather and navigation

`WeatherModel` is a pure function of (position, time, wind seed):
climatology (`WindField`), gale and convective zones, tropical cyclones
from `data/weather/`. Navigation is WGS84 lon/lat throughout: harbours
(`PortCatalog`/`PortData`), the prebuilt world grid (`NavGrid`), routing
with canals (`SeaRouter`), coastal detail (`CoastalGeography`,
`DepthService`), the plan (`PlannedRoute`) and the voyage (`Voyage`). The
chart (`WorldMap`), chart plotter and voyage map are presentations.

### Save/load and migration

`SaveManager.save_to_slot` writes `SessionState.to_dict()` (format
`SAVE_VERSION` 12); `load_from_slot` validates (`SessionState.from_dict`
rejects malformed data with reasons) and migrates older files step by step
(`_migrate_1_to_2` … `_migrate_11_to_12`). Later additions are **optional
fields** read with defaults (anchor `alarm_level`/`good_since`, voyage
`standby_until`, `home`), so no format bump was needed.

### Localization

`Loc` (`src/core/loc.gd`) wraps `TranslationServer`: `Loc.t`, `Loc.n`
(plurals), `Loc.format` (Danish decimal comma), month/weekday/number
helpers. Catalogue `locale/da.po` from `locale/messages.pot`
(`tools/i18n/extract.py`, checked by `tools/i18n/check.py`). Control text
that is a whole msgid is auto-translated by Godot (live on locale change);
built text must call `Loc` before formatting. `SettingsManager.set_language`
→ `TranslationServer.set_locale` → `language_changed`.

### I019: traffic, radar, warnings, VHF

`TrafficModel` generates bounded, deterministic tracks per (1° cell, 3 h
window, slot, seed), cached; `Simulation.traffic_risks` computes CPA/TCPA
(`TrafficModel.approach`) and `risk_level`; `_assess_traffic` announces a
new collision risk once (`traffic>id` in the voyage's warned conditions),
emits `traffic_alert`, stops with `STOP_TRAFFIC`. `RadarPanel` polls
`traffic_risks` at 5 Hz. `VhfRadio.call_for_slot` is a pure function of
(departure, 6 h slot, seed); `_assess_vhf` emits `vhf_call`; `App` shows
`VhfDialog`; `GameSession.answer_vhf` pays once via the award record
`vhf:<id>` and sets `Voyage.standby_until`. Anchor alarms escalate through
`AnchorState.alarm_level`.

### I020: commerce, customization, equipment

`HarbourFacilities` gains `CHANDLERY`, `SAILMAKER`, `FISHMONGER`, offered by
`HarbourTrades.offered` from existing facility data. Purchases are
`GameSession` methods (`sell_catch`, `buy_decor`, `buy_magic_anchor`,
`order_sail_cloth`, plus existing `install_upgrade`/`perform_service`).
`HomeState` (in `SessionState.home`) holds owned decor and per-vessel decor
and sailcloth; `BoatArea.setup_decor` places `CabinDecor` nodes via
`CabinDecor.place_all`; `SailRig.set_cloth` tints the sails. UI:
`TradePanel` subclasses.

### Performance-sensitive paths

- `Simulation.advance` and everything on the evaluation grid (sleep and Long
  Passage run thousands of points): `route_hazards` (quick samples),
  `WeatherDamage.damage_between`, `_assess_traffic` (`TrafficModel` cache,
  flat pre-check), `WeatherModel` event caches.
- Chart open/zoom/pan (`WorldMap`, `WindLayer`, land drawing); the Dream
  World map.
- Day/night theme recolouring (`UiTheme` blend; Well-Run Ship fix).
- Per-frame `_process` in HUD panels, `ShipCompanion`, `SailRig`,
  `RadarPanel` (polls at 5 Hz).
See [PERFORMANCE_OPPORTUNITIES.md](PERFORMANCE_OPPORTUNITIES.md) for the
measured numbers.

## Cross-system flows

**New game → session → active boat.** `MainMenu.new_game_requested` →
`App.open_new_game_menu` (`NewGameMenu`, companion kind) →
`App.start_new_game` → `GameSession.start_new_session(kind)` (builds
`SessionState.create_new` in Copenhagen aboard `VesselCatalog.STARTER_ID`)
→ `App._show_current_boat_area` → `SceneRouter.change_screen` with the
vessel's area scene → `BoatArea._ready` (layout, aboard gear, companion,
decor).

**Input → interaction → App → state.** `Player` reads `interact` →
focused `Interactable` → `BoatArea` matches `interaction_id` and emits a
request signal (`chart_requested`, `boatyard_requested`, …) or calls a
`GameSession` method directly for small actions (hat hook, coffee) → `App`
opens a modal or calls the service → `GameSession` validates, mutates,
emits → HUD/menus refresh from signals.

**Time advance → weather → voyage → warnings.** `Simulation._process` →
`advance` → per grid point: wind/propulsion → `GameSession.apply_simulation_step`
(position along `Voyage`) → `_assess_weather` (`route_hazards`) →
`weather_warning` (once per condition via `record_weather_warning`) →
`App._on_weather_warning` (HUD warning, toast).

**Sleep → events → wake-up.** `App.open_sleep_menu` → `SleepMenu` →
`Simulation.sleep(hours)` (advance with `stop_at_events`) → `AdvanceResult.stopped_by`
→ `App._after_sleep` / `_wake_reason` (notice, `TimePassage` card, light snap).

**Long Passage → interruption → resume/arrival.** `Simulation.start_passage(rate)`
→ `_passage_tick` each frame (`advance` with stops) → `_interrupt_passage(reason, text)`
→ `passage_interrupted` → `VoyageMap` shows the reason; "Sail on" restarts;
arrival → `GameSession.complete_voyage` → `voyage_arrived` / `Simulation.arrived`.

**Traffic alert → simulation stop → radar.** grid point → `_assess_traffic`
→ `traffic_risks` (CPA/TCPA) → new `RISK_DANGER` key → `record_weather_warning("traffic>id")`
→ `traffic_alert` → `App._on_traffic_alert` (sound, HUD warning) and
`STOP_TRAFFIC` (sleep wakes, Long Passage stops, time scale drops) →
`RadarPanel` shows itself while the concern lasts.

**VHF encounter → decision → reward persistence.** grid point → `_assess_vhf`
(`VhfRadio.call_for_slot`, once per slot via `vhf>slot`) → `vhf_call` →
`App._on_vhf_call` (pending until no modal) → `VhfDialog` →
`GameSession.answer_vhf` → `_award_once("vhf:<id>")` (progress record,
saved) + funds + `Voyage.standby_until` → `Simulation` holds the boat
until then → notice and the voyage resumes.

**Localization selection → language refresh.** `LanguagePicker` (first
launch) or `SettingsMenu` → `SettingsManager.set_language` →
`TranslationServer.set_locale` → Godot re-translates control text that is a
msgid; `language_changed` → listeners rebuild built text (`MainMenu.refresh_saves`,
`SettingsMenu._retranslate`); other built text updates on its next refresh.

**Shop purchase → funds → owned item → save.** `TradePanel` row →
`GameSession.buy_decor` / `order_sail_cloth` / `install_upgrade` /
`sell_catch` (trade available? funds enough? not owned?) → mutate
`SessionState` (funds, `home`, `boat_care`, `fishing`) → `funds_changed`,
`home_changed` → panels refresh, `BoatArea._on_home_changed` (decor,
sailcloth) → saved with the next save (`home` record).

**Companion identity → petting response.** `CompanionState.kind` (chosen in
`NewGameMenu`, saved) → `ShipCompanion` (cabin/deck node, `kind`) → `E` on
its `Interactable` → `BoatArea` (`pet`; hands-full check) →
`ShipCompanion.pet()` (pose, hearts, purr/dog sound, walk pause) →
`GameSession.note_companion_petted` (evening moment at anchor).

### Keeping this current

Every script has one entry here and in both Captain's guides; the manifest
`docs/technical/gdscript_guides_manifest.json` records each script's
fingerprint when its entries were last reviewed. `python
tools/docs/check_gdscript_guides.py` reports missing, duplicate and orphan
entries and changed scripts; `--acknowledge PATH --note "..."` records a
review. Rules: [CAPTAINS_ORDERS.md](../../CAPTAINS_ORDERS.md) (Working rules).


## Application shell, core state and services

### `src/app/app.gd`

- **Role:** no class_name, extends Node; root script of `res://src/app/app.tscn` (project `run/main_scene`). Application shell and flow coordinator: wires screens/menus to services, owns all hotkey/Esc handling, turns service signals into toasts, sounds and modals. I021: `_on_arrived` calls `toasts.show_card(title, PortData.get_description(), HarbourLooks.picture_for(port))` instead of a plain notice (the title keeps the old "Arrived in %s." text, which tests read through `toasts.get_messages()`). I022: `switch_vessel` awaits `modals.confirm` and `GameSession.buy_vessel` for an unowned boat before switching; `start_new_game(companion, level)`; pause menu `difficulty_requested` pushes `DifficultyMenu.new()`. I022: `pass_time(work: Callable) -> Variant` (modals.clear, TimePassage.play_sleep with `interruption_reason(_stopped_by(result))`, snap_light, time scale back to 1; direct in tests), `interruption_reason(stopped_by)`, `open_postcards/make_postcard`, `open_game_dev/work_on_game(task_id, choice)`; `work_for` now awaits `pass_time(Simulation.work)` and names an interruption; wheel ids `postcards`, `game_dev` (interior). I022 Academy: `academy: AcademyGuide` on `AcademyLayer` (UiScaleLayer, layer 15); `start_new_game` → `offer_first_voyage` (deferred; waits for router idle and the loading screen; `modals.confirm` Begin/Skip) when `Academy.first_voyage_state() == NEVER_OFFERED` and `AcademyGuide.enabled`; `open_handbook(page)` (also over `PauseMenu`), `toggle_handbook()` on KEY_F1 in `_unhandled_input`; pause menu `handbook_requested`. Steady Hands: `_on_node_added` connects `AudioManager.play_ui` once per button (meta `ui_click`), so reparenting (FitScroll) no longer errors with a duplicate connection. Golden Harbours: `_on_voyage_logged` keeps `_new_harbour_id`/`_new_harbour_line` (no toast) when the new harbour has a picture; `_on_arrived` then calls `show_harbour_moment(port_id, picture)` (special = `HarbourLooks.is_special`, elevation = `Daylight.sun_elevation`, overcast = `BoatLighting.overcast_of(Simulation weather)`, `SessionLog` "harbour_moment") instead of `show_card`, and clears the id. `_on_renown_awarded` passes titles/texts through `Loc.t` (objective titles were stored in English).
- **Depends on:** autoloads `GameSession`, `Simulation`, `SaveManager`, `SettingsManager`, `AudioManager`, `SessionLog`, `UiTheme`; scene children `SceneRouter` ($SceneRouter), `Hud`, `ModalStack`, `Toasts`; creates `WeatherAudio`, `DayNightWatch`, `LoadingScreen`, `TimePassage`, `VoyageMap`; pushes modals (`NewGameMenu`, `PauseMenu`, `SleepMenu`, `SaveLoadMenu`, `BoatyardMenu`, `ProvisionsMenu`, `RescueDialog`, `GroceryMenu`, `FishmongerMenu`, `ChandleryMenu`, `SailmakerMenu`, `CabinHomeMenu`, `GoAshoreMenu`, `FishingMenu`, `CookingMenu`, `AnchorMenu`, `AnchoragePrompt`, `VhfDialog`, `TrophyMenu`, `WorkMenu`, `PublishMenu`, `CaptainsLogMenu`, `SailTrimPanel`, `ActionWheel`, `BoatCareMenu`, `HaulOutPanel`, `LanguagePicker`, `DevTestPanel`); static helpers `Loc`, `PortCatalog`, `VesselCatalog`, `PassageReadiness`, `LegacySaves`, `DevTools`, `DevGuides`, `HarbourFacilities`, `BoatCare`, `FishingSounds`, `HatBadge`, `AnchorSite`, `ChartPlotter`, `SailingPanel`, `RadarPanel`, `Interactable`; screen types `MainMenu`, `BoatArea`, `WorldMap`.
- **Signals:** declares none. Connects to `GameSession` (`notice`, `rescued`, `voyage_logged`, `renown_awarded`, `hat_warning`, `hat_lost`, `fish_bite`, `anchorage_reached`, `anchor_alarm`, `anchor_moment`, `fishing_warning`, `provisions_warning`, `propulsion_changed`, `state_replaced`, `session_started/ended` → `DevTools.on_session_changed`), `Simulation` (`weather_warning`, `traffic_alert`, `vhf_call`, `arrived`, `passage_started`), `router.screen_changed`, `modals.stack_changed`, `hud.*_requested`, `get_tree().node_added` (adds UI click sound to every BaseButton), and every BoatArea/WorldMap/MainMenu request signal in `_connect_*`.
- **State:** writes no game state directly; all changes go through `GameSession`/`Simulation`/`SaveManager` calls. Owns UI-only fields: `_rescue_open`, `_anchorage_prompt_due`, `_pending_vhf`, `_bite_wait`, companion follow timers, `_last_quick_msec`, `voyage_map`, `time_passage`. Sets `get_tree().paused` in `_on_modal_stack_changed` (paused while any modal is open in gameplay, or while the rescue report is open).
- **Lifecycle:** main scene, instanced by the engine at start; `process_mode = ALWAYS`, `$Screen` is PAUSABLE. Many test suites instance `app.tscn` themselves.
- **Persistence:** quicksave/quickload (F5/F9) via `SaveManager.QUICKSAVE_SLOT` with a 1000 ms cooldown; quicksave refused unless aboard, no modal, router idle and no Long Passage (`quicksave_blocker()`). `load_slot()` validates fully before `GameSession.replace_state()`.
- **Performance:** `_process` each frame: weather audio throttled to 1 s (`WEATHER_AUDIO_INTERVAL`), bite-wait countdown, companion follow, deferred anchorage prompt / VHF dialog checks. Cheap.
- **Invariants:** single Esc/hotkey handler (`_unhandled_input`); hotkey actions only when `is_in_gameplay()`, modals empty and router not busy; after any sleep the player wakes at `WAKE_SPAWN` (`v_berth`) unless the sleep ended in a rescue; actions needing a free hand go through `_hand_free()` (`GameSession.hands_refusal()`).
- **Tests:** indirect through suites that instance `app.tscn`, e.g. `tests/suites/test_gameplay_flow.gd`, `tests/suites/test_chart_and_pause.gd`, `tests/suites/test_anchor_life.gd`, `tests/suites/test_anchorage.gd`, `tests/suites/test_cozy_polish.gd`, `tests/suites/test_galley_and_anchor.gd` (most UI/flow suites do).
- **Change risks:** pause logic (`_on_modal_stack_changed` vs `_rescue_open` ordering in `_on_rescued`); deferred prompts must not open over another modal or during router transitions; `sleep_for` has two paths (with/without `TimePassage.is_shown()`), tests use the immediate one; adding a hotkey must keep the "one handler" rule.

### `src/app/game_version.gd`

- **Role:** class_name `GameVersion`, extends RefCounted; static version constants (`DISPLAY` "0.108a", `MACHINE` "0.108.1") and build commit lookup.
- **Depends on:** `res://build_info.json` (optional), else `res://.git/HEAD`, ref file or `packed-refs` (read as files, no git process).
- **State:** static `_commit` cache ("-" sentinel = unknown).
- **Lifecycle:** static helper.
- **Persistence:** independent of `SaveManager.SAVE_VERSION`; saves record `application/config/version`, which must equal `DISPLAY`.
- **Invariants:** `DISPLAY` == project.godot `application/config/version`; format `^0\.\d{3}[a-z]$`.
- **Tests:** `tests/suites/test_branding.gd` (version format and equality), `tests/suites/test_diagnostics.gd`.
- **Change risks:** bumping `DISPLAY` without project.godot (and the test's expected literal) fails tests. Run `python3 tools/write_build_info.py` before an export to embed the commit.

### `src/app/scene_router.gd`

- **Role:** class_name `SceneRouter`, extends Node; swaps the single active screen inside `host` with a fade.
- **Depends on:** child `$FadeLayer/Fade` (ColorRect); `host` export (in app.tscn: `../Screen`).
- **Signals:** `screen_changed(screen)` — after the new screen is added to the tree, before fade-in.
- **State:** `current_screen`, `_busy`; `fade_duration` (0.22 s; tests lower it).
- **Lifecycle:** child node of app.tscn; `process_mode = ALWAYS`; tween uses `TWEEN_PAUSE_PROCESS` so it runs while the tree is paused.
- **Invariants:** only one screen exists at a time; `setup` callable runs before the instance enters the tree (connections exist before `_ready`); calls while busy are ignored with a warning; calls `begin_exit()` on the outgoing screen if present.
- **Tests:** none direct; indirect via `app.router` in app-instancing suites (e.g. `tests/suites/test_anchor_life.gd`).
- **Change risks:** callers rely on `is_busy()` to gate input; ignored changes during a transition are silent (warning only); making it awaitable differently breaks tests that wait on `router.is_busy()`.

### `src/core/academy.gd`

- **Role:** class_name `Academy`, extends RefCounted, static only (I022). Data: `data()`, `categories()`, `pages()`, `page(id)`, `category_title`, `search(query)` (all words in Loc.t title + `fill(text)` + chapter). Keys: `key(action)` (InputMap events → `DisplayServer.keyboard_get_keycode_from_physical` except headless → `OS.get_keycode_string`, arrows/Esc via `ARROWS`; "move" = WASD / arrows; `FIXED_KEYS` handbook F1, quicksave F5, quickload F9, delete_waypoint Delete, anchorage_key M), `fill(text)` (Loc.t then `{name}` → `key(name)`). Progress: states `NEVER_OFFERED` "", `ACTIVE`, `SKIPPED`, `DONE`; `first_voyage_state`, `current_step`, `begin_first_voyage`, `skip_first_voyage`, `complete_step`, `steps()`, `tip(id)`, `is_tip_seen`, `mark_tip_seen`, `reset_tips`.
- **Depends on:** `data/academy/academy.json`, `SettingsManager.get_academy/set_academy`, `InputMap`, `DisplayServer`, `Loc`.
- **State:** static `_data` cache.
- **Lifecycle:** used by `AcademyGuide`, `HandbookMenu`, `App.offer_first_voyage/open_handbook`.
- **Tests:** `tests/suites/test_academy.gd` (`[handbook]`, `[keys]`, `[search]`, `[dansk]`, `[settings]`).
- **Change risks:** the extractor keeps strings with `{key}` placeholders (json-ish rule narrowed in `tools/i18n/extract.py`); translations must keep the placeholders. Fixed keys must match the key codes in `App._unhandled_input` / `WorldMap`.

### `src/core/anchor_state.gd`

- **Role:** class_name `AnchorState`, extends RefCounted; plain anchor data (active, position, scope, set_quality, holding, dragged_nm, alarm, alarm_level, good_since, anchored_at, checked_until, dragged_this_stay, moments, kind, depth_m, depth_source, bonus_kn).
- **Depends on:** nothing beyond built-ins.
- **State:** written only by `GameSession` (anchor actions and `apply_anchor_check`, called by `Simulation` on its grid).
- **Lifecycle:** Resource-like value object held by `SessionState.anchor`; `duplicate_state()` for snapshots.
- **Persistence:** "anchor" section via `to_dict()`/`from_dict()`. Required keys validated (scope ∈ `SCOPES` [3,5,7], holding ∈ `HOLDINGS`). Optional, defaulted when absent: `moments` (0.102b, capped `MAX_MOMENTS` 16), `kind`/`depth_m`/`depth_source`/`bonus_kn` (0.105b, bonus clamped to `MAGIC_BONUS_MAX_KN` 3.0), `alarm_level`/`good_since` (I019; old saves derive level from `alarm` + holding). Added by migration 10→11.
- **Invariants:** `alarm` and `alarm_level` are false/0 when not active; `SessionState.from_dict` rejects an active anchor when not underway.
- **Tests:** `tests/suites/test_galley_and_anchor.gd`, `tests/suites/test_magic_anchor.gd`, `tests/suites/test_captains_watch.gd`, `tests/suites/test_well_run_ship.gd`, `tests/suites/test_cozy_polish.gd`, `tests/suites/test_catch_and_cove_journey.gd`.
- **Change risks:** new fields must be added to `duplicate_state`, `to_dict` and `from_dict` (optional with default) or snapshots/saves silently lose them.

### `src/core/boat_care_state.gd`

- **Role:** class_name `BoatCareState`, extends RefCounted; per-boat wear record (hull_cleaned_at, rig_wear 0–100, engine_hours, upgrades, history ≤ `HISTORY_LIMIT` 12).
- **Depends on:** `BoatCare.get_upgrade()` (validation of upgrade ids on load).
- **State:** held in `SessionState.boat_care[vessel_id]`; written by `GameSession` (`_wear`, services, upgrades, weather rig wear).
- **Lifecycle:** value object; `create(now)`; created lazily by `SessionState.get_boat_care()`.
- **Persistence:** "boat_care" section (dict by vessel id). Unknown or duplicate upgrade id fails the load. Migration 11→12 synthesises a record for the active boat (hull 20 days old, wear from logged miles).
- **Tests:** `tests/suites/test_boat_care.gd`, `tests/suites/test_boat_of_your_own.gd`.
- **Change risks:** removing an upgrade id from `BoatCare.UPGRADES` makes saves that fitted it unloadable.

### `src/core/captains_log.gd`

- **Role:** class_name `CaptainsLog`, extends RefCounted; sailing history (total_nm, voyages_completed, arrivals, longest, visited, voyages ≤ `MAX_VOYAGES` 50).
- **Depends on:** `Voyage` (in `make_record`).
- **State:** written only by `GameSession` (`complete_voyage()`, `rescue()`) via `record_voyage()`; read by `ObjectiveCatalog`, `CaptainsLogMenu`.
- **Lifecycle:** value object in `SessionState.captains_log`; `create(start_port, time)` lists the start harbour with 0 arrivals.
- **Persistence:** "log" section; loaded records normalised (`_normalized`) to make_record's types/key order. Migration 7→8 seeds visited with `LEGACY_START_PORT` and current location, `first = UNKNOWN_TIME`.
- **Invariants:** rescues add distance and a record but no arrival/visit; `arrivals == voyages_completed`; distance comes from `Voyage.sailed_nm`, never recomputed.
- **Tests:** `tests/suites/test_captains_log.gd`, `tests/suites/test_objectives.gd`.
- **Change risks:** record keys are read by objectives (`complete`, `damage`, `worst_hazard`, `outcome`) and the log UI; changing them needs both plus `_is_record`.

### `src/core/difficulty.gd`

- **Role:** class_name `Difficulty`, extends RefCounted, static only (I022). `LEVELS` [`RELAXED`, `STANDARD`, `SEASONED`]; `valid(level)` (unknown → Standard), `value_of(level, key)`, `factor(key)` (the current game's level via `GameSession.get_difficulty()`), `display_name`, `describe` (Loc.t of the data's name/text), `starting_funds(level)`.
- **Depends on:** `data/progression/difficulty.json` (`levels.<id>`: name, text, starting_funds, provisions_use, wear, weather_damage, costs, rescue_fee), `GameSession`, `SessionState.STARTING_FUNDS`, `Loc`.
- **State:** static `_levels` cache (parsed once).
- **Lifecycle:** used by `SessionState.create_new` (funds), `GameSession` (`apply_simulation_step` consumption ×provisions_use, `_wear` ×wear, `service_quote` and `get_provisions_price` ×costs, rescue fee ×rescue_fee), `Simulation._assess_weather` (damage ×weather_damage), `DifficultyPicker`.
- **Tests:** `tests/suites/test_captains_other_life.gd` (`[difficulty]`, `[new game]`, `[dansk]`).
- **Change risks:** Standard must stay exactly 1.0 (existing tests compare exact numbers); names/texts come from data and are extracted for translation by `tools/i18n/extract.py`.

### `src/core/fishing_state.gd`

- **Role:** class_name `FishingState`, extends RefCounted; fishing data (rod, lures, lure, line_out/mode/since, checked_until, hold, next_uid, records, trophies, counters, keep_min_rarity, keep_min_grade, passage_posture, sharks_released, junk_caught).
- **Depends on:** `FishingCatalog` (rarity/grade ranks, `RARITY_ORDER`, `GRADES`).
- **State:** written only by `GameSession`; read by fishing UI, trophy board, aboard badge.
- **Lifecycle:** value object in `SessionState.fishing`.
- **Persistence:** "fishing" section. Validates unique `uid` < `next_uid`, hold ≤ `LARGE_HOLD_CAPACITY` (10), trophies cut to `TROPHY_COUNT` (5). Iteration 18 fields optional with defaults (format 12 unchanged). Pending bite and fight are not saved. Added by migration 10→11.
- **Invariants:** each landed fish has a unique uid so it can be kept/released/sold/cooked once.
- **Tests:** `tests/suites/test_fishing.gd`, `tests/suites/test_fishing2.gd`, `tests/suites/test_galley_and_anchor.gd`, `tests/suites/test_catch_and_cove_journey.gd`, `tests/suites/test_anchorage.gd`, `tests/suites/test_cozy_patch.gd`, `tests/suites/test_joy_journey.gd`.
- **Change risks:** lowering hold capacity rejects existing saves; new fields must be optional on load.

### `src/core/galley_state.gd`

- **Role:** class_name `GalleyState`, extends RefCounted; galley data (well_fed_until, meals_cooked, last_meal, last_meal_at, coffee mug place).
- **State:** in `SessionState.galley`; written by `GameSession` (cook, coffee, mug actions); `well_fed_until` read in `GameSession.apply_simulation_step` (food factor `WELL_FED_FOOD_FACTOR`).
- **Lifecycle:** value object.
- **Persistence:** "galley" section; `coffee` optional (Cozy Polish), only "", "carried", "holder", "table" accepted. Added by migration 10→11.
- **Tests:** indirect via `GameSession.get_galley()` in `tests/suites/test_galley_and_anchor.gd`; coffee via `tests/suites/test_cozy_polish.gd` (indirect).
- **Change risks:** new mug places must be added to the `from_dict` whitelist and `GameSession.COFFEE_*`.

### `src/core/game_session.gd`

- **Role:** no class_name, extends Node; autoload `GameSession`. Sole mutator of the active `SessionState`; game rules API (lifecycle, area/player, clock and pause, routes and voyages, propulsion/trim, weather exposure and damage, rescue, boat care and services, Captain's Log, objectives/renown/publishing, fishing, galley/coffee/hands, anchor and Magic Anchor, anchorages, VHF standby, Go Ashore, money, provisions, remote work, hat, location recovery, life at anchor). I022: signals `fleet_changed`, `difficulty_changed(level)`; `get_difficulty`, `set_difficulty`, `owns_vessel` (or `test_all_boats_owned`, set by the test runner), `get_owned_vessels`, `buy_vessel` (BOATYARD facility, price ≤ funds, not owned); `switch_vessel` refuses unowned boats; `start_new_session(companion, level)`; factors: consumption ×`provisions_use`, `_wear` ×`wear`, `service_quote`/`get_provisions_price` ×`costs` (ceil), rescue fee ×`rescue_fee`; `_check_vessel` owns the fallback starter. I022: `get_pastimes()`, `set_postcard_draft(kind, subject, caption, layout)` (keeps minutes for the same subject), `abandon_postcard()`, `postcard_minutes_left()`, `work_on_postcard(minutes)` → {done, award, card} (`_award_once(Pastimes.renown_key)`, scrapbook trimmed to `scrapbook_size`, SessionLog "postcard"), `work_on_game(task_id, choice, minutes)` → {points, done, milestone, award, euros} (points × share of task hours, `_award_once("gamedev:<id>")`, release_euros on the last milestone, SessionLog "game_dev"), `is_game_released()`.
- **Depends on:** `SessionState` and its sub-records; `Simulation` (weather queries, `invalidate_estimates`); `PortCatalog`, `SeaRouter`, `VesselCatalog`, `VesselProfile`, `BoatCare`, `HarbourFacilities`, `ObjectiveCatalog`, `FishingCatalog`, `HatConfig`, `AnchorLife`, `AnchorSite`, `SailTrim`, `GeoMath`, `NavGrid`, `WeatherAudio.rain_level`, `SessionLog`, `Loc`; `_exit_tree` clears catalogue singletons (`PortCatalog`, `ObjectiveCatalog`, `HatConfig`, `HatArt`, `SeaRouter`, `WeatherModel`, `WindField`, `VesselProfile`, `VesselCatalog`).
- **Signals:** declares ~45, incl. `session_started`, `session_ended`, `state_replaced`, `boat_area_changed`, `route_changed`, `time_scale_changed`, `pause_changed`, `voyage_started`, `voyage_course_changed`, `voyage_arrived`, `propulsion_changed`, `sail_trim_changed`, `anchorage_reached`, `vessel_changed`, `companion_moved`, `companion_area_changed`, `notice`, `condition_changed`, `funds_changed`, `provisions_changed`, `provisions_warning`, `rescued`, `voyage_logged`, `renown_awarded`, `travel_update_published`, `hat_*`, `coffee_changed`, `fish_bite`, `fishing_*`, `fish_landed`, `meal_cooked`, `anchor_changed`, `anchor_alarm`, `boat_care_changed`, `home_changed`, `location_recovered`, `anchor_life_changed`, `anchor_moment`. Connects only its own `anchor_changed` → `_update_anchor_life`.
- **State:** owns `_state`, `_has_unsaved_changes`; unsaved runtime: `_pending_bite`, `_settled`, `_asleep`, `_profile` cache, `_chart_region`, `_last_recovery`, fishing warning flags. Getters return copies (`duplicate_*`) or scalars.
- **Lifecycle:** autoload (project.godot), loaded after `SettingsManager`/`AudioManager`, before `Simulation`/`SaveManager`/`SessionLog`.
- **Persistence:** `replace_state()` duplicates the loaded state, then repairs: `_complete_legacy_route` (v1 routes), `_recover_location` (positions/routes invalid under the current chart moved/re-planned, anchored+motoring fixed to sail), `_check_vessel` (unknown vessel → starter). `get_state_snapshot()` for saving; `mark_saved()`.
- **Performance:** `get_vessel_profile()` caches a worn profile keyed on rounded wear effects; `apply_simulation_step` is called per Simulation step (not per frame when idle-heavy) and does provisions, companion schedule, wear, anchor life.
- **Invariants:** only GameSession mutates SessionState; `rescue()` is one atomic transaction and a no-op when not underway (one rescue per incident); objectives paid once per event via `ObjectiveProgress.can_pay`; notices from load repairs are emitted deferred.
- **Tests:** practically every suite; core ones `tests/suites/test_data_model.gd`, `tests/suites/test_gameplay_flow.gd`, `tests/suites/test_simulation.gd`, plus feature suites (`test_fishing.gd`, `test_galley_and_anchor.gd`, `test_hat.gd`, `test_boat_care.gd`, `test_objectives.gd`, `test_publishing.gd`, `test_upkeep.gd`, `test_anchorage.gd`, `test_captains_watch.gd`).
- **Change risks:** 3,100+ lines; signal emission order matters (`voyage_logged` before `renown_awarded` before `voyage_arrived`/`rescued`); forgetting `_has_unsaved_changes = true`; returning internal objects instead of copies; Simulation depends on `apply_*` hooks being side-effect exact for determinism.

### `src/core/hat_state.gd`

- **Role:** class_name `HatState`, extends RefCounted; the captain's hat (status STORED/WORN/CARRIED/LOST, strain, warned, warned_at, checked_until, serial, lost/bought counts, spent, bought_at, voyage_worn_hazard, voyage_lost, history ≤ `MAX_HISTORY` 30).
- **Depends on:** `WeatherModel.HAZARD_SEVERE` (clamp on load).
- **State:** written only by `GameSession` (`apply_hat_check`, `recover_hat`, toggle/hook/buy/lose); strain checks driven by `Simulation._check_hat` on an absolute grid.
- **Lifecycle:** value object in `SessionState.hat`; belongs to the player, not a boat (never reset on boat switch, rescue or load).
- **Persistence:** "hat" section; LOST with `lost_count == 0` is rejected. Added by migration 9→10 (`create(saved time)`).
- **Invariants:** strain/warning/checked_until saved so results are identical across time scales and save/load.
- **Tests:** `tests/suites/test_hat.gd`, `tests/suites/test_secret_achievements.gd`, `tests/suites/test_branding.gd`, `tests/suites/test_diagnostics.gd`, `tests/suites/test_cozy_polish.gd`.
- **Change risks:** `voyage_*` fields reset in `GameSession.depart()`; hat objectives read them.

### `src/core/home_state.gd`

- **Role:** class_name `HomeState`, extends RefCounted; "a boat of your own": `owned_decor` and per-vessel `{decor, sails, cloths}`.
- **Depends on:** `HarbourTrades` (`CLASSIC_CLOTH`, `get_decor_item`, `get_sail_cloth`).
- **State:** in `SessionState.home`; written by `GameSession` (`buy_decor`, `set_cabin_decor`, `order_sail_cloth`), read by `CabinHomeMenu`, `ChandleryMenu`.
- **Lifecycle:** value object.
- **Persistence:** "home" section, optional; `from_dict` never fails, silently drops unknown ids and decor not owned. Stable ids only.
- **Tests:** `tests/suites/test_boat_of_your_own.gd`.
- **Change risks:** renaming a decor/cloth id in `HarbourTrades` silently drops it from existing saves.

### `src/core/loc.gd`

- **Role:** class_name `Loc`, extends RefCounted; static localisation helpers: `t`, `n` (plurals), `format`/`format_plural`/`format_translated` (decimal mark), `month*`/`weekday*`, `thousands`, `decimal`, `is_danish`.
- **Depends on:** `TranslationServer` (catalogue `locale/da.po`, template `locale/messages.pot` from `tools/i18n/extract.py`).
- **State:** static cached RegEx `_placeholder_re`.
- **Lifecycle:** static helper; locale set by `SettingsManager._apply_language()`.
- **Invariants:** translate before formatting (`Loc.t("%d nm") % x`), so the extractor finds the literal; English is source and fallback.
- **Tests:** `tests/suites/test_localization.gd`.
- **Change risks:** `format_translated` only localises `%…f` placeholders; changing message keys orphans translations in `da.po`; tools in `tools/i18n/` parse `Loc.t`/`Loc.n` calls (indirect).

### `src/core/objective_catalog.gd`

- **Role:** class_name `ObjectiveCatalog`, extends RefCounted; objective definitions + evaluation (`evaluate`, `evaluate_hat_event`, `is_met`, `is_met_by_hat_event`, `get_progress`) and `euros_per_renown`.
- **Depends on:** `res://data/progression/objectives.json`, `PortCatalog`, `GeoMath`, `WeatherModel` hazard constants, `CaptainsLog`, `ObjectiveProgress`, `HatState`, `Loc`.
- **State:** static `_default` singleton (cleared by `clear_default()`, called from `GameSession._exit_tree`); read-only after load.
- **Lifecycle:** static helper/singleton; used by `GameSession` and `CaptainsLogMenu`.
- **Invariants:** pure evaluation, no state change; invalid entries are skipped with `push_error`; secret objectives cannot be repeatable; generated "far harbour" objectives are deterministic for a port catalogue.
- **Tests:** `tests/suites/test_objectives.gd`, `tests/suites/test_publishing.gd`, `tests/suites/test_secret_achievements.gd`.
- **Change risks:** objective ids are save keys in `ObjectiveProgress.completed`; renaming one re-awards it.

### `src/core/objective_progress.gd`

- **Role:** class_name `ObjectiveProgress`, extends RefCounted; renown and completed objectives (lifetime/unpublished renown, completed, recent ≤ `MAX_RECENT` 20, publication totals).
- **State:** in `SessionState.progress`; written only by `GameSession` (`award`, `mark`, publishing); `mark()` records repeated Go Ashore outings (keys `shore:<port>:<event>`, see `ShoreEvents`).
- **Lifecycle:** value object.
- **Persistence:** "progress" section; rejects `unpublished_renown > lifetime_renown`. Added by migration 8→9 (empty).
- **Invariants:** lifetime renown never decreases; `can_pay()` ensures one-time objectives pay once and repeatables at most once per event time.
- **Tests:** `tests/suites/test_objectives.gd`, `tests/suites/test_secret_achievements.gd`.
- **Change risks:** `last_event` comparisons use game time; events at identical times will not pay twice.

### `src/core/pastimes.gd`

- **Role:** class_name `Pastimes`, extends RefCounted, static only (I022). Postcards: `KINDS`, `LAYOUTS`, `postcard_minutes()`, `postcard_renown()`, `kind_name`, `layout_name`, `captions(kind)`, `subjects()` → [{kind, subject, title, args}], `args_for(kind, subject)` (caption names in the current language, also for old scrapbook cards), `weather_name(hazard)`, `where_now()`, `caption_text(kind, caption, args)`, `renown_key(kind, subject)` ("postcard:<kind>:<subject>"), `is_posted`. Game: `game_title`, `milestones`, `tasks`, `task(id)`, `session_points(task, choice)` (2 best / 1), `choice_order(task, sessions)` (rotated).
- **Depends on:** `data/pastimes/*.json`, `GameSession` (log, fishing, companion, position, time, objective progress), `PortCatalog`, `FishingCatalog.get_species_name`, `CompanionState.display_name`, `CaptainsLog.OUTCOME_ARRIVED` (voyage records), `Daylight.sun_elevation` (`LOW_SUN` −8..12°), `HatStory.describe_place`, `Loc`.
- **State:** static `_postcards`, `_game` caches.
- **Lifecycle:** read by `GameSession.set_postcard_draft/work_on_postcard/work_on_game`, `PostcardMenu`, `PostcardView`, `ScrapbookMenu`, `GameDevMenu`, `App.work_on_game`.
- **Tests:** `tests/suites/test_captains_other_life.gd` (`[postcards]`, `[game dev]`).
- **Change risks:** subject keys are saved (scrapbook, renown ids): voyage subjects are "<from>-<to>", weather "<from>-<to>:<hazard>"; port ids must not contain "-". Data strings are extracted via `DATA_KEYS` plus `LIST_KEYS` (captions, choices, done) and `MAP_KEYS` (weather_names) in `tools/i18n/extract.py`.

### `src/core/pastimes_state.gd`

- **Role:** class_name `PastimesState`, extends RefCounted. `postcards` [{kind, subject, caption, layout, time, place}], `draft` {kind, subject, caption, layout, minutes} or {}, `game` {points, milestone, sessions, task {id, choice, minutes} or {}, log [{milestone, time}]}; `duplicate_state()`, `to_dict()`, static `from_dict(data)` (never fails; validates types, drops malformed parts).
- **Depends on:** nothing but Variant checks (`_is_number`).
- **State:** the three fields above.
- **Lifecycle:** `SessionState.pastimes` (duplicate_state, to_dict "pastimes", from_dict); mutated only by `GameSession` pastime methods.
- **Tests:** `tests/suites/test_captains_other_life.gd` (`[saves]`, `[old saves]`).
- **Change risks:** optional save section, no SAVE_VERSION bump; adding a field means adding it to all three methods.

### `src/core/provisions.gd`

- **Role:** class_name `Provisions`, extends RefCounted; food/water days, `warning_level`, consumption, restock, warning thresholds, display levels.
- **Depends on:** `Loc` (format_days).
- **State:** in `SessionState.provisions`; changed via `GameSession` (`apply_simulation_step` → `consume`, `buy_provisions`, cooking, boat switch caps).
- **Lifecycle:** value object; constants used widely by UI (`CAPACITY_DAYS` 14, `LOW_DAYS` 3, `CRITICAL_DAYS` 1).
- **Persistence:** "provisions" section; values clamped to `MAX_STORE_DAYS` 60 on load. Added by migration 6→7.
- **Invariants:** consumption is time-based only (1 day per 86,400 game s); empty stores block departure, never harm.
- **Tests:** `tests/suites/test_upkeep.gd`, `tests/suites/test_upkeep_ui.gd`, `tests/suites/test_long_passage.gd`, `tests/suites/test_boat_care.gd`, `tests/suites/test_gameplay_flow.gd`, `tests/suites/test_world_voyage.gd`.
- **Change risks:** `level_of` uses `CAPACITY_DAYS` even for larger passage stores (display only).

### `src/core/session_state.gd`

- **Role:** class_name `SessionState`, extends RefCounted; the complete serialisable game state and save format (`to_dict`/`from_dict`), plus `create_new`, `duplicate_state`, per-boat condition and care accessors. I022: `owned_vessels` (saved as `fleet.owned`, always including the boat aboard: `_owned_for_save`/`owned_from`; missing section → every catalogue id) and `difficulty` (top-level `difficulty`, `Difficulty.valid`); `create_new(..., level)` sets funds from `Difficulty.starting_funds` and owns the starter; both copied in `duplicate_state`. No save version change. I022: `pastimes: PastimesState` (duplicate_state, to_dict "pastimes", from_dict via lenient `PastimesState.from_dict`; optional, no version bump).
- **Depends on:** `PortCatalog`, `PlannedRoute`, `Voyage`, `PropulsionState`, `WeatherExposure`, `CompanionState`, `VesselCatalog.STARTER_ID`, `CaptainsLog`, `ObjectiveProgress`, `HatState`, `FishingState`, `GalleyState`, `AnchorState`, `BoatCareState`, `HomeState`, `Provisions`, `VesselCondition`, `GeoMath`, `Loc`.
- **State:** pure data; no node references.
- **Lifecycle:** created by `GameSession.start_new_session()` or `SaveManager` load; owned by `GameSession`.
- **Persistence:** sections `boat`, `player`, `clock`, `wind`, `weather`, `companion`, `vessel` (incl. optional `sail_trim`), `economy`, `provisions`, `rescue`, `log`, `progress`, `hat`, `fishing`, `galley`, `anchor`, `boat_care`, `home` (optional), `navigation`. Unknown vessel id accepted here (GameSession falls back).
- **Invariants:** `from_dict` returns null on any error (never a partial state); location empty ⇔ underway ⇔ voyage present; underway position must match voyage progress (wrap-aware) unless anchored; new game starts 2026-05-01 08:00 UTC, €10,000, at the given port.
- **Tests:** `tests/suites/test_data_model.gd`, `tests/suites/test_save_manager.gd`, `tests/suites/test_voyage_persistence.gd`, and most feature suites round-trip it.
- **Change risks:** any required new field breaks older saves unless `SaveManager.SAVE_VERSION` is bumped with a migration or the field is optional; must be added to `duplicate_state` too.

### `src/core/simulation.gd`

- **Role:** no class_name, extends Node; autoload `Simulation`. The single timeline: converts real time to game time and advances clock, voyage and all timed checks; weather queries, ETA/route estimates, Long Passage, traffic and VHF, hat checks. Inner class `AdvanceResult`. I022: `_assess_weather` multiplies `WeatherDamage.damage_between(...)` by `Difficulty.factor("weather_damage")` (1.0 at Standard). I022: `work(hours)` also returns "stopped_by" (the AdvanceResult's) for `App.pass_time`.
- **Depends on:** `GameSession` (all reads and `apply_*` hooks), `WeatherModel`, `WeatherDamage`, `WeatherEvent`, `WindField`, `PropulsionController`, `SailTrim`, `GeoMath`, `HatConfig`, `FishingCatalog`, `TrafficModel`, `VhfRadio`, `PortCatalog`, `SessionLog`, `Loc`.
- **Signals:** `weather_warning(warning)`, `arrived(port_id)`, `passage_interrupted(reason, text)`, `passage_started(rate)`, `traffic_alert(info)`, `vhf_call(call)`. Connects to `GameSession.voyage_started`, `voyage_course_changed`, `state_replaced`, `vessel_changed`, `rescued`, `provisions_warning` and `notice` (the last two only flag Long Passage interruptions).
- **State:** writes game state only through `GameSession` hooks. Unsaved: `passage_rate`, `_passage_notice`, `_eta_key`/`_eta_seconds`, `_hat_sheltered`. Tunables: `game_seconds_per_real_second` (60), `auto_advance`, `sea_encounters`.
- **Lifecycle:** autoload, `PROCESS_MODE_PAUSABLE`; `_process` → `tick()` when `auto_advance`.
- **Performance:** `advance()` loops over evaluation points/events (grid `EVALUATION_INTERVAL` 300 s, route vertices, fish and hat ticks), not frames; guard of 1,000,000 iterations; ETA cached by revision/progress/30-min bucket; `route_hazards` uses `sample_hazard` quick path; Long Passage chunks capped at 0.1 real s × rate.
- **Invariants:** deterministic in (seed, time) and independent of how time is chopped (residue < 1e-6 s ignored); paused → `tick` does nothing, explicit advances (`sleep`, `work`, `spend_time_*`) still work and leave pause as is; a rescue always stops the advance; accelerated time drops to 1× on any attention event.
- **Tests:** `tests/suites/test_simulation.gd`, `tests/suites/test_sailing.gd`, `tests/suites/test_sailing_correctness.gd`, `tests/suites/test_weather.gd`, `tests/suites/test_long_passage.gd`, `tests/suites/test_captains_watch.gd`, `tests/suites/test_hat.gd`, `tests/suites/test_reassessment.gd`, `tests/suites/test_upkeep.gd`. The test runner applies calm wind and sets `sea_encounters` true only for `test_captains_watch.gd` and `test_localization.gd`.
- **Change risks:** anything that evaluates outside the fixed grid breaks step-size independence; changing check order inside `advance()` changes which event stops a sleep; turning `sea_encounters` on elsewhere shifts voyage timings in older suites.

### `src/core/vessel_condition.gd`

- **Role:** class_name `VesselCondition`, extends RefCounted; condition bands (sound/worn/damaged/critical) and display (`band_of`, `band_name`, `describe`); `FULL` = 100.
- **Depends on:** `Loc`.
- **State:** none; the value lives in `SessionState.vessel_conditions`, changed via `GameSession`.
- **Lifecycle:** static helper; used by HUD, `BoatyardMenu`, `PassagePanel`, damage visuals, `BoatCare`, `PassageReadiness`.
- **Invariants:** bands use the rounded-up shown value (76 % is sound, 15 % critical; 0 % only when lost).
- **Tests:** `tests/suites/test_upkeep.gd`, `tests/suites/test_upkeep_ui.gd`.
- **Change risks:** band edges drive visuals and readiness advice.

### `src/core/vhf_radio.gd`

- **Role:** class_name `VhfRadio`, extends RefCounted; deterministic VHF call generation (`call_for_slot`) and texts (`describe`, `describe_commitment`).
- **Depends on:** `TrafficModel.NAMES`, `WindField.compass_name`, `Loc`.
- **State:** none; delivered calls are recorded as `vhf>slot` keys in the voyage's warned conditions by `Simulation._assess_vhf`; answering/standby/rewards in `GameSession.answer_vhf`.
- **Lifecycle:** static helper.
- **Invariants:** pure in (departed_at, slot, seed, hazardous); at most one call per `SLOT_SECONDS` (6 h); assist chance 0.08 (0.16 hazardous), forecast 0.12.
- **Tests:** `tests/suites/test_captains_watch.gd`.
- **Change risks:** changing the RNG seeding or roll order changes every call in existing voyages.

### `src/diagnostics/session_log.gd`

- **Role:** no class_name, extends Node; autoload `SessionLog`. Bounded JSON Lines diagnostic log in `user://diagnostics/`; inner `_ErrorLogger` (Godot `Logger`) records engine/script errors.
- **Depends on:** `GameVersion`, `SaveManager.SAVE_VERSION`, `GameSession`, `Simulation` (format_game_time, weather at vessel).
- **Signals:** connects to many `GameSession` signals in `_connect_game()` (session, voyages, rescue, funds, renown, hat, fishing, meals, anchor, location recovery, anchor life).
- **State:** `_file`, `_path`, line/byte counters, `_truncated`, `_mutex`; `log_dir`, `enabled` (off with user arg `--no-session-log`).
- **Lifecycle:** autoload, `PROCESS_MODE_ALWAYS`; `restart()` opens a new file per session.
- **Performance:** event-driven only; each line flushed; limits `MAX_LINES` 5000, `MAX_BYTES` 1,000,000, `KEEP_FILES` 10.
- **Invariants:** `write()` is thread-safe and never raises; reads game state but never changes it; no personal data.
- **Tests:** `tests/suites/test_diagnostics.gd`.
- **Change risks:** `write()` is called from everywhere; error logger may run off-thread (must not read game state).

### `src/persistence/legacy_saves.gd`

- **Role:** class_name `LegacySaves`, extends RefCounted; finds and imports saves from the old "Next Harbor" user folder.
- **Depends on:** `SaveManager` (`check_file`, `is_slot_free`, `import_file`, `get_slot_bytes`, `SLOT_COUNT`, `Status`), `Loc`.
- **State:** static `legacy_dir_override` (tests).
- **Lifecycle:** static helper; called by `App.import_legacy_saves()` and `MainMenu` (Import button visibility).
- **Persistence:** copies files byte-for-byte; never writes or deletes the source; skips already-imported (same bytes) saves; own slot number first, else first free.
- **Tests:** `tests/suites/test_branding.gd`.
- **Change risks:** the legacy folder path is platform-specific (lower-case `godot` on Linux/BSD).

### `src/persistence/save_manager.gd`

- **Role:** no class_name, extends Node; autoload `SaveManager`. JSON save slots (1–3) and quicksave (slot 9, `quicksave.json`) under `user://saves`; inner classes `SlotInfo`, `LoadResult`, `_ReadResult`; enum `Status`.
- **Depends on:** `SessionState`, `PortCatalog`, `PropulsionState`, `CompanionState`, `WeatherExposure`, `Provisions`, `CaptainsLog`, `ObjectiveProgress`, `HatState`, `FishingState`, `GalleyState`, `AnchorState`, `BoatCareState`, `VesselCatalog`, `SessionLog`, `Loc`.
- **Signals:** `slots_changed` — after a successful save, import or delete (listened to by `MainMenu`, `SaveLoadMenu`).
- **State:** `save_dir` (tests redirect it); no game state.
- **Lifecycle:** autoload.
- **Persistence:** `FORMAT_ID` "next_harbor_save" (kept from old name), `SAVE_VERSION` 12; write = temp file → read-back verify → old file to `.bak` → rename; `.bak` used when the main file is missing; `_migrate` chains 1→2 … 11→12, each adding defaults only.
- **Invariants:** never touches the active session or scenes; load returns a complete validated state or an error; a quicksave never overwrites a manual slot.
- **Tests:** `tests/suites/test_save_manager.gd`, `tests/suites/test_voyage_persistence.gd`, plus save/load round trips in many feature suites.
- **Change risks:** any SessionState format change needs a version bump and migration; `get_slot_info()` fully parses each file (cost grows with save size, called by menus).

### `src/settings/settings_manager.gd`

- **Role:** no class_name, extends Node; autoload `SettingsManager`. Player preferences in `user://settings.cfg` (audio volumes, window mode, VSync, UI scale, art style, course view, reduce flashing, flash intensity, reduce motion, UI light, language, sleep hours). I022: `&"Wind"` in `AUDIO_BUSES` (after Ambience) and `DEFAULT_VOLUMES` (100 = 0 dB, the pre-I022 balance); stored as `[audio] wind`, read with the default (no migration). I022: `get/set_tips_enabled` (snapshot "tips", `[interface] tips`), `get_academy()`/`set_academy(data)` (saves at once; `_sanitize_academy`: first_voyage in ""/active/skipped/done, step ≥ 0, seen strings; `[academy] first_voyage/step/seen`), not part of the snapshot.
- **Depends on:** `AudioServer`, `DisplayServer`, `TranslationServer`, `ConfigFile`.
- **Signals:** `settings_applied`, `ui_scale_changed(scale)`, `art_style_changed(style)`, `course_view_changed(enabled)`, `ui_light_changed(mode)`, `language_changed(locale)` — emitted when values change or are re-applied.
- **State:** private preference fields; `settings_path` (tests redirect it).
- **Lifecycle:** autoload, first in the autoload list; `load_settings()` in `_ready`.
- **Persistence:** separate from saves; setters apply immediately, disk write only on `save()` (exception: `set_sleep_hours(persist=true)` saves itself). Invalid/missing values fall back to defaults; language empty until chosen (first launch asks via `App.show_language_picker`).
- **Invariants:** `restore_defaults()` keeps the chosen language; window/VSync changes skipped headless or embedded in the editor.
- **Tests:** `tests/suites/test_settings_and_audio.gd`, `tests/suites/test_localization.gd`, and others that toggle settings (`test_cozy_polish.gd`, `test_chartroom_ui.gd`, `test_visual_prototype.gd`).
- **Change risks:** the test runner redirects `settings_path` (`tests/test_runner.gd`); code that bypasses that would overwrite the player's file; new preferences must be added to `snapshot`, `restore_snapshot`, `save` and `load_settings`.

## Navigation and weather

### `src/navigation/anchorage_layer.gd`

- **Role:** class_name `AnchorageLayer`, extends Node2D; chart overlay (0.105b) that paints NORMAL (teal) / MAGIC (amber) anchorage cells at 1/60° resolution per 1° tile, by the same rule as `AnchorSite.evaluate` / `GameSession.anchorage_spot`.
- **Depends on:** `MapView` (`get_px_per_degree`, `get_visible_geo_rect`, `projection`, `_near_view`), `CoastalGeography` (`get_default`, `res`, `_index`, `is_land_cell`, `_cell_water`, `cell_center`, `cell_nm`, `shore_info`, `approach_max_nm`, TILES_*/NORTH/WATER_TILE), `DepthService` (`get_default`, `has_data`, `sample`, `estimate`, `SHORE_CAP_NM`), `SeaRouter` (`get_default`, `grid`, `is_point_navigable`), `NavGrid` (`grid_at`, `geo_to_cell`, `get_class_at`, `NAVIGABLE`), `AnchorSite` (MIN_SHORE_NM, MIN_DEPTH_M, NORMAL_MAX_DEPTH_M, COASTAL_NM).
- **Signals:** `tile_completed(key: Vector2i)` emitted in `_store()` after each tile is computed.
- **State:** `_tiles` (key → {texture, cells}), `_order` (LRU), `_wanted`, current `_job: TileJob`; profiling counters (`tiles_computed`, `cells_evaluated`, `max_frame_usec`, `frame_usec`, `last_stage_usec`, `max_step_usec`). Reads only; writes no game state.
- **Lifecycle:** Instanced as a field by `MapView` (`anchorage_layer := AnchorageLayer.new()`), added under `$Land` at index 2 in `MapView._ready`; toggled via `set_shown()` from `WorldMap.set_anchorages_shown`. `MapView._process` calls `refresh_view()` when the camera key changes. Inner class `TileJob` (RefCounted) is a resumable 5-stage job (land → clear+seeds → BFS reach → classify → texture).
- **Performance:** Active only when `shown` and px/deg ≥ `SHOW_PX_PER_DEG` (700). `_process` works within `FRAME_BUDGET_USEC` (3000 µs), nearest-centre tile first. Tiles with no non-water 1° tile in the 3×3 neighbourhood are skipped. `world_only` fast path when no regional grid touches the window (caches routing-cell navigability). At most `MAX_TILES` (48) kept; wanted tiles never evicted. Tiles never go stale (rule is time/weather independent). `complete_now()` computes synchronously (tests/benchmark).
- **Invariants:** `_classify` must stay equivalent to `AnchorSite`'s waypoint rule; `_shore_info` must return the same result as `CoastalGeography.shore_info` (max_nm = SHORE_CAP_NM, share 1.5 nm); BFS reach must equal `CoastalGeography.approach` (limit from `approach_max_nm`). Tile key = (lon+180, NORTH−1−lat) in CoastalGeography tile space.
- **Tests:** `tests/suites/test_anchorage_overlay.gd`; `tests/benchmark_105b.gd` (benchmark).
- **Change risks:** Drift from `AnchorSite`/`CoastalGeography` rules makes teal areas that refuse anchoring; window `margin` too small makes `_shore_info` fall back to the slow path; touching `CoastalGeography._index` private layout breaks the skip test.

### `src/navigation/coastal_geography.gd`

- **Role:** class_name `CoastalGeography`, extends RefCounted; near-shore water service on a fine 1/120° land raster (`data/navigation/coast/coast.bin`, built by `tools/navigation/build_coast.py`): `is_water`, `is_clear`, `shore_distance_nm`, `shore_info`, `is_line_clear`, `approach`, `fetch_nm`.
- **Depends on:** `SeaRouter` (`get_loaded` in `_water_at`, `get_default` in `approach`/`approach_max_nm`, `_cell_nm`), `NavGrid` (`grid_at`, `cell_class_at_geo`, `cells_per_degree`, `LAND`), `GeoMath` (`rhumb_distance_nm`, `normalize`), `AnchorSite.offset` (in `fetch_nm`).
- **Signals:** none.
- **State:** Static singleton `_default`; file bytes `_file`, tile `_index` (WATER/LAND/MIXED per 1° tile), `_offsets`, decoded bit-packed tiles `_tiles` with FIFO `_tile_order`; `tiles_decoded` counter.
- **Lifecycle:** Static helper singleton via `get_default()` (loads PATH on first use). Callers: `AnchorSite`, `GameSession`, `AnchorageLayer`, `DepthService`, `SeaRouter` (`is_point_reachable`, `is_afloat`, `_is_segment_allowed`, `_endpoint_path`).
- **Performance:** Tiles decompressed on first use, cache bounded at `CACHE_TILES` (512). `shore_info` scans outward Chebyshev rings with early exit. `approach` is a bounded BFS (limit from `approach_max_nm`) plus string-pulling with `is_line_clear` (0.1 nm sampling).
- **Invariants:** Water = fine raster water AND not LAND on a coarser regional grid; where the regional grid has ≥ 2× `res` cells/degree (Denmark) the region alone decides. Outside 72°S..80°N is land. Missing/invalid file → warning, `loaded = false`, `is_land_cell` returns false (fallback to routing chart). `approach` result starts at `geo`, ends in routing water, never passes a sub-cell-wide entrance.
- **Tests:** `tests/suites/test_coastal_depth.gd`, `tests/suites/test_anchorage_overlay.gd`; `tests/scratch/probe_points.gd` (probe).
- **Change risks:** Changing `res`, tile layout or MAGIC breaks the binary format and `AnchorageLayer` (which reads `_index` and `res` directly). Any change to `approach`/`shore_info` must be mirrored in `AnchorageLayer.TileJob`.

### `src/navigation/depth_data.gd`

- **Role:** class_name `DepthData`, extends RefCounted; reader for an optional bathymetry file ("LCHD" format: header, 152×360 tile index, offset table, deflated int16 elevations), tiers A/B of `DepthService`.
- **Depends on:** `DepthService` (SOURCE_REGIONAL / SOURCE_GLOBAL constants).
- **Signals:** none.
- **State:** `res`, `source`, `_index`, `_offsets`, `_file`, decoded `_tiles` (unbounded).
- **Lifecycle:** Created by `DepthData.load_from(path)` from `DepthService.load_data()`; returns null when the file is missing, has the wrong magic, or a tile count mismatch. No file ships (`data/navigation/depth/depth.bin` absent); produced by `tools/navigation/build_depth.py`.
- **Invariants:** `sample()` returns positive depth (−elevation) bilinearly; NAN if any of the four neighbours has no data. Row 0 = 79..80°N, column 0 = 180°W.
- **Tests:** `tests/suites/test_coastal_depth.gd` (synthetic data).
- **Change risks:** Format must stay in sync with `build_depth.py`; tile cache is unbounded (fine for bounded subsets only).

### `src/navigation/depth_service.gd`

- **Role:** class_name `DepthService`, extends RefCounted; the single depth query for anchoring (0.105b). Tiers: regional data, global data (via `DepthData`), else a deterministic game estimate `3 + 17·slope·shore_nm^0.9` (shore capped at 6 nm).
- **Depends on:** `CoastalGeography` (`is_water`, `shore_info`), `DepthData`, `Loc` (labels).
- **Signals:** none.
- **State:** Static `_default`; `coast`, optional `_data`. No mutable game state.
- **Lifecycle:** Static helper singleton via `get_default()` (wraps `CoastalGeography.get_default()`, tries `DATA_PATH`). Callers: `AnchorSite`, `AnchorState`, `GameSession`, `AnchorageLayer`, `src/ui/anchor_menu.gd`. Static `estimate`, `value_noise`, `source_label`, `describe_depth` used directly.
- **Invariants:** Estimate depends only on position, shore distance and land share — never on game seed, time or boat (`NOISE_SEED` = 105 fixed). `SHELF_SEAS` first match wins. Data is used only where it is > 0 and shore ≥ one data cell; otherwise the estimate. Land → depth 0, source "".
- **Tests:** `tests/suites/test_coastal_depth.gd`, `tests/suites/test_magic_anchor.gd`; also `tests/restart_105b.gd`, `tests/screenshots_105b.gd`.
- **Change risks:** Any change to the estimate or `SHELF_SEAS` moves NORMAL/MAGIC anchorage areas worldwide (overlay, `AnchorSite`, `GameSession.anchorage_spot`). `AnchorageLayer` calls `estimate()` directly with its own shore info, so the signature must stay.

### `src/navigation/geo_math.gd`

- **Role:** class_name `GeoMath`, extends RefCounted; static geodesy on Vector2(lon, lat): longitude normalising/wrapping, haversine `distance_nm`, rhumb distance/bearing/interpolation, path length, cumulative distances, `point_along`, `segment_index_at`, `distance_to_segment_nm`, `format_position`.
- **Depends on:** nothing (pure functions).
- **Signals:** none.
- **State:** none.
- **Lifecycle:** Static helper. Used widely: `SeaRouter`, `CoastalGeography`, `PlannedRoute`, `Voyage`, `VoyageDaydream`, `MapView`, `WindLayer`, `WorldMap`, `TrafficModel`, `WeatherModel`, `WindField`, `Simulation`, `GameSession`, `SessionState`, `PassageReadiness`, UI panels and others.
- **Invariants:** Route legs are rhumb lines (straight in Mercator, same as the NavGrid raster). Every longitude difference uses `wrap_delta` so paths past ±180° give the same results. `format_position` rounds to tenths of a minute before splitting (no "60.0′").
- **Tests:** `tests/suites/test_routing.gd` (main), `test_route_wrap.gd`, `test_world_voyage.gd`, `test_navigation_views.gd`, and many suites indirectly.
- **Change risks:** Used by routing, simulation progress, saves (`same_position` check on load in `SessionState`) and drawing; small numeric changes alter voyage positions and ETAs and can fail save validation.

### `src/navigation/map_projection.gd`

- **Role:** class_name `MapProjection`, extends RefCounted; spherical Mercator geo ↔ map-space conversion (`geo_to_map`, `map_to_geo`, `geo_polygon_to_map`), latitude clamped to ±85°.
- **Depends on:** nothing.
- **Signals:** none.
- **State:** `scale` (map units per degree of longitude).
- **Lifecycle:** Instanced by `MapView._ready` (`MapProjection.new(units_per_degree)`), by `CabinWorldMap`, and by `tools/navigation/world_land_to_res.gd`.
- **Invariants:** Map space is display-only; game data never stores it. Must stay consistent with the projection baked into `data/navigation/world/land.res` (scale 160).
- **Tests:** `tests/suites/test_data_model.gd`, `tests/suites/test_routing.gd`.
- **Change risks:** Changing the formula invalidates `land.res` (rebuild with the tool) and the dream shader parameters in `MapView`.

### `src/navigation/map_view.gd`

- **Role:** class_name `MapView`, extends Node2D; draws the navigation chart (water, world/Europe/regional land, coasts, labels, graticule, weather, canals, courses, ports, waypoints, anchorages, pins, boat) and converts input to chart events. Display only; `WorldMap` interprets events. I021: `_draw_port` adds `_draw_special_star` (8-point brass star, upper left of the pin) when `HarbourLooks.is_special(port.id)`; a dictionary lookup per drawn port, no new layout or per-frame work.
- **Depends on:** `MapProjection`, `PortCatalog`, `PortData`, `GeoMath`, `NavGrid.REGIONS_INDEX`, `WorldLand` (`land.res`), `WeatherModel.active_events`, `WeatherEvent`, `WeatherStyle`, `SeaRouter.get_loaded().canals`, `WindLayer`, `AnchorageLayer`, `GameSession` (game time, wind seed, `is_active`), `SessionLog`, `Loc`; preloads `assets/fonts/Barlow-SemiBold.ttf` and `src/navigation/shaders/dream_world.gdshader`; data `data/navigation/world/world.json`, `land.json`, region `land.json` files.
- **Signals:** declares `port_clicked`, `map_clicked`, `route_pressed` (drag past `CLICK_SLOP_PX` on a draft leg), `waypoint_pressed`, `waypoint_dragged`, `waypoint_released`, `waypoint_remove_requested` (right-click without move), `cursor_moved` (geo or null). Connects `$Overlay.draw`, `get_viewport().size_changed`.
- **State:** Display state set via `set_display()` (boat/selected/destination port, vessel geo, paths, draft legs, waypoints, anchorages, magic flags, invalid waypoints, selected waypoint, editing flag, next turn, visited pins); camera; `weather_time`, `_weather_shapes`; static caches `_world_cache`, `_europe_cache`, `_region_cache` (persist across chart openings).
- **Lifecycle:** Child node `$MapView` of `src/navigation/world_map.tscn`; owns `WindLayer` and `AnchorageLayer` children created in `_ready`.
- **Performance:** World land pre-triangulated into 10° tiles drawn in three wrap copies; tiles shown only when in view (`_update_world_tiles`, keyed on snapped camera). Regional world layer built lazily from `EUROPE_DETAIL_PX`. Coasts as hairline runs (≤128 points) in 400-unit tiles. Port layout recomputed only on view/highlight key change; weather reprojected every `WEATHER_REFRESH_SECONDS` (300 game s). Islets redrawn only on >15% zoom change.
- **Invariants:** Camera x stays in the main copy (wraps), y clamped so the view never shows past the chart's N/S edge; zoom never shows more than one world width. Labels never overlap (placement order by `_port_priority_before`). Dream style changes colours only, never geometry.
- **Tests:** `tests/suites/test_world_chart_render.gd`, `test_harbour_chart.gd`, `test_route_wrap.gd`, `test_regions.gd`, `test_weather_ui.gd`, `test_wind_overlay.gd`, `test_anchorage_overlay.gd`, `test_cozy_polish.gd`, `test_cockpit_ui.gd`, `test_gameplay_flow.gd`; benchmarks `tests/benchmark.gd`, `benchmark_17.gd`, `benchmark_wrs.gd`; `tests/screenshots_16.gd`.
- **Change risks:** Static caches keyed only on scale (stale data if files change at runtime). Child order under `$Land` (water, wind tint at 1, anchorages at 2, land) matters for what paints over land. `units_per_degree` must match `land.res` (160) or the JSON fallback is used (slow). Tests call private helpers (`_near_view`, `_free_view_size`, `_clamp_camera`).

### `src/navigation/nav_grid.gd`

- **Role:** class_name `NavGrid`, extends RefCounted; Mercator navigability raster (NAVIGABLE 255 / APPROACH 128 / LAND 0) with nested finer regions (world → Europe ×5 → Denmark ×6), wrapping at ±180° for the world grid.
- **Depends on:** PNG masks + JSON metadata (`data/navigation/world/navmask.png`, `world.json`, `europe_navmask.png/json`, `regions.json` and per-region `navmask.png`/`region.json`), `Loc` (Europe name). Built by `tools/navigation/build_navigation_data.py`, `build_region.py`, `build_world.py`.
- **Signals:** none.
- **State:** `columns`, `rows`, `cells_per_degree`, `west`, `mercator_north`, `_cells`, `regions`, region link data (`region_id`, `base_cell`, `base_size`, `factor`), `wraps`, `meta`. Immutable after load.
- **Lifecycle:** Created by `NavGrid.load_world()` / `load_from()` / `load_region()` from `SeaRouter.load_world` / `load_from`; reached elsewhere via `SeaRouter.grid` (`CoastalGeography`, `AnchorageLayer`, `WindLayer`, `GameSession`, `HatStory`, chart plotter).
- **Performance:** `is_line_clear` is a supercover DDA (corner crossings check both sides), bounded by a guard. Region lookup is recursive linear over a few rectangles.
- **Invariants:** Geographic queries (`cell_class_at_geo`, `is_navigable`, `is_geo_line_clear`, `grid_at`) recurse into regions; cell-index queries act on one grid. Lines crossing a region edge are split and nudged by `SEAM_NUDGE`. `is_line_clear` must mirror `segment_clear()` in the Python builder. Outside the grid = LAND.
- **Tests:** `tests/suites/test_routing.gd`, `test_regions.gd`, `test_harbours.gd`, `test_navigation_views.gd`, `test_wind_overlay.gd`; `tests/benchmark.gd`.
- **Change risks:** Divergence from the builder's line check makes the prebuilt route graph contain edges the runtime rejects (or vice versa). Region metadata size checks reject masks on mismatch (`push_error`, null).

### `src/navigation/planned_route.gd`

- **Role:** class_name `PlannedRoute`, extends RefCounted; a validated course: origin port/position, player waypoints, anchorage flags, destination, rhumb-line `path`, `waypoint_path_indices` splitting legs.
- **Depends on:** `GeoMath.path_length_nm`, `PortCatalog` (`describe`, `from_dict` validation), `Loc`.
- **Signals:** none.
- **State:** Plain data fields; `duplicate_route()` deep-copies.
- **Lifecycle:** Created by `SeaRouter.plan_route` (and `from_dict` on load); held by `SessionState.planned_route`, `Voyage.route`, `WorldMap._draft_route`; used by `GameSession`, `Hud`.
- **Persistence:** `to_dict()`: origin, origin_position {lon, lat}, destination, waypoints, path, waypoint_path_indices, anchorages (list of waypoint indices; optional, absent in pre-Iteration-18 saves). `from_dict` checks known ports, numeric/finite points (waypoints |lon| ≤ 180, path |lon| ≤ 540 for Date Line continuity), index ranges, and that a path starts at origin and ends at the destination port; a 1-point path is rejected; destination-only routes (no path) are allowed.
- **Invariants:** `path` is exactly what the chart draws and the voyage sails; `waypoint_path_indices.size() == waypoints.size()` when a path exists.
- **Tests:** `tests/suites/test_routing.gd`, `test_regions.gd`, `test_cozy_polish.gd`, `test_anchorage.gd`, `test_voyage_persistence.gd` (indirect, via saves); helper `make_route` in `tests/test_runner.gd`.
- **Change risks:** Save compatibility (field names, index semantics); loosening `from_dict` lets corrupted saves through.

### `src/navigation/port_catalog.gd`

- **Role:** class_name `PortCatalog`, extends Resource; the harbour set with id lookup, spatial buckets (2°) for `ports_in_rect`, and name/country `search`.
- **Depends on:** `PortData`; resource `data/navigation/port_catalog.tres` (generated by `tools/navigation/build_harbours.py`).
- **Signals:** none.
- **State:** `@export ports`; derived `_by_id`, `_buckets`, `_indexed_count` (rebuilt lazily when `ports.size()` changes).
- **Lifecycle:** Static singleton via `get_default()` (loaded on the loading screen); `clear_default()` called from `GameSession` shutdown. Used by `MapView`, `WorldMap`, `SeaRouter`, `TrafficModel`, `VoyageDaydream`, `PlannedRoute`, `Voyage`, `GameSession`, `SessionState`, `SaveManager`, `Simulation`, `App`, many UI and content catalogs.
- **Performance:** `ports_in_rect` falls back to a linear scan when the bucket count exceeds the port count (world zoom).
- **Invariants:** Index is keyed only on `ports.size()`; editing a port's position or id in place without changing the count leaves a stale index (call `rebuild_index()`).
- **Tests:** `tests/suites/test_harbours.gd`, `test_harbour_chart.gd`, `test_data_model.gd`, `test_routing.gd`, and many suites indirectly.
- **Change risks:** Shared singleton: session validation, saves and the map must agree on ids.

### `src/navigation/port_data.gd`

- **Role:** class_name `PortData`, extends Resource; one harbour: `id`, `display_name` (getter returns `Loc.t(name, "place")`), `country`, `latitude`, `longitude`, `description`, `importance` (1–3), `region`, `island`, `source`. I021: `get_description()` returns `Loc.t(description)` (the chart's details and the arrival card use it; the raw field stays English).
- **Depends on:** `Loc`.
- **Signals:** none.
- **State:** Exported fields only; `get_geo_position()` → Vector2(lon, lat).
- **Lifecycle:** Sub-resources of `port_catalog.tres`; produced by `tools/navigation/build_harbours.py` from `tools/navigation/harbours.csv`; names extracted for translation by `tools/i18n/extract.py`.
- **Persistence:** `id` is the save key for locations, routes and the Captain's Log ("Never rename once shipped").
- **Invariants:** Coordinates are WGS84 degrees, never screen/map units. `importance` drives `MapView.PORT_MARKER_PX_PER_DEGREE`.
- **Tests:** `tests/suites/test_harbours.gd`, `test_harbour_chart.gd`, `test_routing.gd`.
- **Change risks:** Renaming ids breaks saves; moving a port can strand its harbour approach (`SeaRouter.find_port_approach`).

### `src/navigation/sea_router.gd`

- **Role:** class_name `SeaRouter`, extends RefCounted; plans land-free routes (A* over a merged world/Europe/Denmark open-water graph on a 3D sphere, string pulling, harbour approaches, near-shore approaches, canals) and validates routes. Inner classes `Leg`, `RouteResult`.
- **Depends on:** `NavGrid`, `PortCatalog`/`PortData`, `PlannedRoute`, `CoastalGeography` (`approach`, `is_water`, `is_line_clear`, `approach_max_nm`), `GeoMath`, `Loc`, Godot `AStar3D`; data `data/navigation/world/graph.json`, `world/europe_link.json`, `europe_route_graph.json`, region `graph.json`, `data/navigation/canals.json`.
- **Signals:** none.
- **State:** Static `_default`; `grid`, `catalog`, AStar graph, node geo/cell/component arrays, `_component_size`, spatial `_buckets`, `_approach_cache` (per port id, unbounded), `_leg_cache` (cleared at `LEG_CACHE_LIMIT` 256), `canals`.
- **Lifecycle:** Static singleton: `get_default()` loads `load_world()` (fallback `load_from` Europe); built on a thread by `src/ui/loading_screen.gd`; `get_loaded()` never loads; `clear_default()` on `GameSession` shutdown. Callers: `GameSession` (plan/validate/change course), `WorldMap`, `VoyageDaydream`, `TrafficModel` (via `get_loaded`), `CoastalGeography`, `AnchorageLayer`, `WindLayer`, `MapView` (canals), `HatStory`, chart plotter.
- **Performance:** Load merges graphs recursively and runs union-find for components. Node search uses buckets and radii `CONNECT_RADII` (scaled to the first level below root); A* capped at `MAX_PATH_NODES`. Harbour approach BFS bounded by `APPROACH_WINDOW_CELLS` / `approach_radius_nm`.
- **Invariants:** Every result segment is checked; `validate_route` accepts only NAVIGABLE lines, canal reaches, short near-shore approaches clear on the fine raster, and APPROACH-class lines/berth links near the route's own ports. Approaches must reach a component of ≥ `MIN_SEA_COMPONENT_NODES` (50). Temp A* points use ids `node_count+1`/`+2` and are removed after each search.
- **Tests:** `tests/suites/test_routing.gd`, `test_regions.gd`, `test_harbours.gd`, `test_coastal_depth.gd`, `test_world_voyage.gd`, `test_navigation_views.gd`, `test_anchorage.gd`, `test_magic_anchor.gd`, `test_voyage_persistence.gd`, and others; `tests/benchmark.gd`, `benchmark_wrs.gd`.
- **Change risks:** Validation changes can invalidate saved routes on load. Graph/merge logic must match the Python builders (`build_region.py` seam and `blocked_base_edges`). Leg cache keys on stringified Vector2 values.

### `src/navigation/traffic_model.gd`

- **Role:** class_name `TrafficModel`, extends RefCounted; deterministic synthetic vessel traffic (I019) per (1° cell, 3 h window, slot, seed); plus static CPA/TCPA `approach()` and `kind_name()`.
- **Depends on:** `SeaRouter.get_loaded()` (`is_point_navigable`), `PortCatalog` (`ports_in_rect` for busyness), `GeoMath`, `ChartPlotter._geo_at` / `_nm_offset` (static helpers in `src/ui/chart_plotter.gd`), `Loc`.
- **Signals:** none.
- **State:** Static `_default`; `_tracks` and `_density` caches (each cleared at `CACHE_LIMIT` 4096). Nothing saved.
- **Lifecycle:** Static singleton via `get_default()`. Callers: `Simulation` (traffic warnings, `vessels_near`, `approach`), `src/ui/radar_panel.gd` (`kind_name`), `VhfRadio` (`NAMES`).
- **Performance:** `vessels_near` visits cells within range + max track reach, windows overlapping ±`LIFETIME_SECONDS`/2, with a cheap flat pre-check before the spherical position.
- **Invariants:** Pure function of (cell, window, slot, seed): same ships after load, during sleep and Long Passage. Returns [] without caching when the router is not loaded yet. Tracks end where they would meet land (checked at `TRACK_STEPS`); ships whose track began within `HIDDEN_START_NM` are hidden for their first hour.
- **Tests:** `tests/suites/test_captains_watch.gd`; `tests/scratch/probe_sleep_traffic.gd` (probe).
- **Change risks:** RNG draw order defines every ship; reordering calls changes all traffic. Depends on private `ChartPlotter` statics.

### `src/navigation/vessel_profile.gd`

- **Role:** class_name `VesselProfile`, extends Resource; per-boat performance: polar-style sail speed (`sail_speed_kn`, `angle_efficiency`, `wants_spinnaker`), engine speed, automatic propulsion thresholds, `weather_damage_factor`.
- **Depends on:** nothing at runtime; default resource `data/vessel/starter_sloop.tres`.
- **Signals:** none.
- **State:** Exported tuning fields only.
- **Lifecycle:** Resource; static `get_default()` / `clear_default()` (called on `GameSession` shutdown). Referenced by `VesselDefinition.performance`; `GameSession.get_vessel_profile()` duplicates a base profile; consumed by `PropulsionController`, `WeatherDamage`, boatyard menu.
- **Invariants:** `sail_speed_kn` is clamped to [0, `max_sail_speed_kn`] including the spinnaker bonus; light-air smoothstep between `light_air_min_kn` and `light_air_full_kn`.
- **Tests:** `tests/suites/test_sailing.gd`, `test_wind.gd`, `test_reassessment.gd`, `test_simulation.gd`.
- **Change risks:** Speeds drive ETAs, Passage Readiness hours and engine/fuel behaviour; test expectations use concrete numbers.

### `src/navigation/voyage.gd`

- **Role:** class_name `Voyage`, extends RefCounted; the active voyage: `route` + `progress_nm` (position derived), revision, warned conditions, departure info, Captain's Log figures (`sailed_nm`, `worst_hazard`, `damage_percent`, `fully_recorded`), anchorage holding (`holding_at`, `anchorages_done`), VHF `standby_until`.
- **Depends on:** `PlannedRoute`, `GeoMath` (`cumulative_distances`, `point_along`, `normalize`), `PortCatalog` (in `from_dict`).
- **Signals:** none.
- **State:** Plain data plus a cached `_cumulative` (rebuilt when path size changes).
- **Lifecycle:** Created by `Voyage.create()` / `from_dict()` in `GameSession` / `SessionState`; held in `SessionState.voyage`; read by `WorldMap`, `CaptainsLog`, `App`, `SaveManager`, `src/ui/voyage_map.gd`.
- **Persistence:** `to_dict()` keys: route, progress_nm, revision, warned_conditions, departed_at, departure_port_id, departure_position, sailed_nm, worst_hazard, damage_percent, fully_recorded, holding_at, anchorages_done, standby_until. Migration: without `sailed_nm` (pre-Iteration-006) departure = route origin, sailed = progress, `fully_recorded = false`; anchorage fields and `standby_until` optional.
- **Invariants:** `0 ≤ progress_nm ≤ total`; `get_position()` is normalised to ±180°; anchorage stops matched at exact waypoint distance (1e-6).
- **Tests:** `tests/suites/test_voyage_persistence.gd` (indirect), `test_regions.gd`, `test_magic_anchor.gd`, `test_simulation.gd` (indirect); `tests/restart_105b.gd`.
- **Change risks:** Save schema; `SessionState` checks that the voyage position equals the saved vessel position on load.

### `src/navigation/voyage_daydream.gd`

- **Role:** class_name `VoyageDaydream`, extends RefCounted; static, read-only "Imagine this voyage" text for the Dreamer's Map (Iteration 17): real route, up to three real harbours along it, templated text in one of five tones chosen by hash of the destination id.
- **Depends on:** `SeaRouter.plan_route`, `PortCatalog`, `PassageReadiness.assess` and its constants, `GameSession` (position, location, underway, vessel id), `GeoMath`, `Loc`.
- **Signals:** none.
- **State:** Static `_cache` (cleared above 64 entries), key = destination|position|origin port|vessel id.
- **Lifecycle:** Static helper; called by `WorldMap.imagine_voyage`.
- **Invariants:** Never changes the course, boat, clock, money or stores. Stops exclude origin/destination, only within 8–92% of the route, one per third (one on routes < 150 nm).
- **Tests:** `tests/suites/test_navigation_views.gd`.
- **Change risks:** Template strings are translation keys; stop selection is tested for order and distance limits.

### `src/navigation/weather_legend.gd`

- **Role:** class_name `WeatherLegend`, extends Control; legend rows (box, outline, glyph, name) for gale, thunder risk, thunderstorm, cyclone in the chart's Weather tab.
- **Depends on:** `WeatherStyle` (`style`, `draw_outline`, `draw_glyph`), `WeatherEvent` kind constants, `Loc`.
- **Signals:** none.
- **State:** `_font` only.
- **Lifecycle:** Instanced by `WorldMap._ready` (`WeatherLegend.new()`) next to `%WeatherLabel`.
- **Tests:** `tests/suites/test_weather_ui.gd`.
- **Change risks:** `KINDS` and `NAMES` are parallel arrays.

### `src/navigation/weather_style.gd`

- **Role:** class_name `WeatherStyle`, extends RefCounted; presentation table (`STYLES`: color, fill, outline, core, label per kind; `CYCLONE_RISK`) and static drawing helpers `label`, `draw_outline`, `draw_glyph`.
- **Depends on:** `WeatherEvent` (kinds, `display_name`, `peak_kn`, `gust_kn`, `cyclone_category`), `WeatherModel.SEVERE_STORM_KN`, `Loc`; draws on any `CanvasItem`.
- **Signals:** none.
- **State:** none.
- **Lifecycle:** Static helper; used by `MapView._draw_weather` / `set_weather_time`, `WeatherLegend`, `WorldMap._describe_weather`.
- **Invariants:** Kinds are distinguished by outline style, glyph and label, not colour alone. Unknown kinds fall back to the gale style.
- **Tests:** `tests/suites/test_weather_ui.gd`.
- **Change risks:** `core` flag controls whether `MapView` builds a core ring; label text is shown in the weather tab.

### `src/navigation/wind_layer.gd`

- **Role:** class_name `WindLayer`, extends Node2D; chart wind arrows plus a speed tint (separate `tint` node), from cached snapshots on a 30-min grid with a ±6 h navigator in 1 h steps (Iteration 17/18).
- **Depends on:** `MapView` (camera, `projection`, `screen_to_map`, `units_per_degree`), `WeatherModel.sample_wind`, `GameSession.get_wind_seed`, `SeaRouter.get_default().grid` / `NavGrid.cell_class_at_geo`, `GeoMath.normalize`, `Loc`, `RenderingServer`.
- **Signals:** `snapshot_changed` (emitted in `_retarget`), `detail_changed(hidden)` (zoom crosses `HIDE_PX_PER_DEG`/`SHOW_PX_PER_DEG`). Both connected by `WorldMap._build_wind_time_controls`.
- **State:** Static `_land` class cache (≤ `MAX_LAND_CHUNKS` 8000, shared); `_snapshots` (≤ `MAX_SNAPSHOTS` 14, ≤ `MAX_CHUNKS` 600 per snapshot), `_target`/`_shown`, `_offset`, tint texture; test counters `chunks_sampled`, `drawn_points`.
- **Lifecycle:** Instanced as a field by `MapView` and added as a child in `_ready` (its `tint` goes under `$Land` at index 1); `MapView._process` calls `update_time` and `refresh_view`. Toggled by `WorldMap.set_wind_shown`. `WindLayer.color_for` is also used by `src/ui/chart_plotter.gd`; `BANDS`/`OFFSET_STEP`/`MAX_OFFSET_STEPS` by `WorldMap`.
- **Performance:** Missing chunks sampled in `_process` within `FRAME_BUDGET_USEC` (3000 µs), centre first; the previous snapshot stays on screen until the new one is complete; Now snapshots throttled to one per `NOW_MIN_REAL_SECONDS`. Arrows drawn in four batched calls. View capped at `MAX_VIEW_POINTS` lattice points.
- **Invariants:** Display only; simulation wind never depends on it. Forecast snapshots pass `known_at` = Now so storms forming later are excluded. No arrows on land (SEA class only).
- **Tests:** `tests/suites/test_wind_overlay.gd`; `tools/weather/measure_wind_variation.gd` (measurement tool).
- **Change risks:** Static `_land` cache must be cleared (`clear_land_cache`) when the nav grid changes (tests). Snapshot-key arithmetic (`SNAPSHOTS_PER_OFFSET`) ties the navigator step to `SNAPSHOT_STEP`.

### `src/navigation/world_land.gd`

- **Role:** class_name `WorldLand`, extends Resource; pre-projected world land for the chart (Iteration 16): `scale`, overview/regional fill and coast rings, `islets`, `labels`.
- **Depends on:** nothing.
- **Signals:** none.
- **State:** Exported data only.
- **Lifecycle:** Written to `data/navigation/world/land.res` by `godot --headless --path . --script tools/navigation/world_land_to_res.gd` (reads `data/navigation/world/land.json` from `build_world.py`). Loaded by `MapView._world_data` and `CabinWorldMap`.
- **Invariants:** `scale` must equal `MapView.units_per_degree` (160); otherwise `MapView` falls back to parsing `land.json`.
- **Tests:** `tests/suites/test_routing.gd`.
- **Change risks:** Field changes require regenerating `land.res`.

### `src/navigation/world_map.gd`

- **Role:** class_name `WorldMap`, extends Node2D; the chart screen. MODE_STATION: course planning on a draft (plot, insert/move/remove waypoints, anchorages, Apply/Discard), sidebar tabs (Course/Weather/Details), harbour search, wind and anchorage overlays. MODE_DREAM: the cabin's Dreamer's Map (no weather, no editing, `VoyageDaydream`, visited pins). I021: both selection panels use `selected.get_description() + _special_line(id)`; static `_special_line` returns "\nSpecial harbour: <note>" from `HarbourLooks.special_note` or "".
- **Depends on:** `MapView`, `GameSession` (committed route/voyage, `change_course`, `set_planned_route`, `clear_planned_route`, `anchorage_spot`, `nearest_anchorage_spot`, `take_hint`, Captain's Log), `SeaRouter`, `PortCatalog`, `PlannedRoute`, `Simulation` (estimates, ETA, hazards, weather), `PassageReadiness`, `VoyageDaydream`, `AnchorSite`, `AnchorageLayer`, `WindLayer`, `WeatherLegend`, `WeatherStyle`, `WeatherModel`, `WeatherSample`, `WindField.compass_name`, `HarbourFacilities`, `Hud.describe_wind`, `PropulsionState`, `SettingsManager`, `SessionLog`, `Loc`.
- **Signals:** declares `close_requested`, `depart_requested`, `sleep_requested`, `plan_requested(port_id)` (Dreamer's Map → chart table). Connects all `MapView` signals, `GameSession.route_changed` / `voyage_started` / `voyage_course_changed` / `voyage_arrived`, `SettingsManager.ui_scale_changed`, `WindLayer.snapshot_changed` / `detail_changed`.
- **State:** Draft only (`_draft_destination`, `_draft_waypoints`, `_draft_anchorages`, `_draft_legs`, `_draft_route`, `_draft_dirty`); commits through `GameSession` on `apply_course()`. Static `wind_shown` persists the wind toggle for the run. `_spot_cache` (≤ 64) for anchorage checks.
- **Lifecycle:** Scene `src/navigation/world_map.tscn`, instanced by `App` (`world_map_scene` via `router.change_screen`; the Dreamer's Map sets `mode = MODE_DREAM` in the change_screen callback). `get_next_turn()` is static and used by `src/ui/chart_plotter.gd` and `src/ui/sailing_panel.gd`.
- **Performance:** UI refresh every `LIVE_REFRESH_INTERVAL` (0.25 s); drag recalculation throttled to `DRAG_RECALC_INTERVAL` (0.1 s); route hazards cached per course and 5 game minutes; Passage Readiness recomputed on course/boat/half-hour/stores key.
- **Invariants:** The committed course is untouched until Apply, and only a valid draft (plus valid anchorages) can be applied. Waypoints released on land snap to `nearest_navigable` within `WAYPOINT_SNAP_NM` or are removed. Dream mode samples no weather and changes nothing.
- **Tests:** `tests/suites/test_chartroom_ui.gd`, `test_navigation_views.gd`, `test_anchorage.gd`, `test_anchorage_overlay.gd`, `test_chart_and_pause.gd`, `test_gameplay_flow.gd`, `test_route_wrap.gd`, `test_regions.gd`, `test_weather_ui.gd`, `test_wind_overlay.gd`, `test_cozy_polish.gd`, `test_harbour_chart.gd`, and others; benchmarks `tests/benchmark*.gd`; screenshots `tests/screenshots_16/17/18.gd`.
- **Change risks:** Many tests drive it through public methods (`plot_course_to`, `insert_waypoint`, `apply_course`, `toggle_anchorage`, `search_harbours`) and node names (`HarbourSearch`, `AnchorageToggle`, `WindTimeLabel`); `_setup_dream` disconnects the first `map_clicked` connection by position.

### `src/weather/weather_event.gd`

- **Role:** class_name `WeatherEvent`, extends RefCounted; one hazardous event (KIND_GALE, KIND_THUNDER_RISK, KIND_THUNDERSTORM, KIND_CYCLONE) whose position, size, strength, outline, gusts and cyclone vortex are pure functions of game time.
- **Depends on:** `Loc` (display name getter, cyclone category).
- **Signals:** none.
- **State:** Fixed formation parameters (id, kind, start, lifetime, origin, speed/heading/turn, radius, peak/gust, flow, hemisphere, eye radius, shape harmonics, develop/dissipate fractions, seed, parent_id).
- **Lifecycle:** Created by `WeatherModel._make_gale` / `_make_risk` / `_cells_of` / `_make_cyclone`, and as fixtures by `src/dev/weather_fixtures.gd` (`WeatherModel.fixture_events`). Read by `MapView`, `WeatherStyle`, `WeatherLegend`, `Simulation`, `src/audio/weather_audio.gd`, dev tools.
- **Invariants:** Querying never mutates the event; results are independent of frame rate, time step and save/load. `gust_envelope` is a deterministic function of (seed, time) with no jumps between frames. Outline radius factor clamped to 0.6–1.4.
- **Tests:** `tests/suites/test_weather.gd`, `test_weather_ui.gd`, `test_wind_overlay.gd`.
- **Change risks:** Any formula change alters weather for every seed (saves continue with different weather); `reach_nm` must stay a conservative bound or `WeatherModel._reach_boxes` will drop events that still affect a point.

### `src/weather/weather_exposure.gd`

- **Role:** class_name `WeatherExposure`, extends RefCounted; record of the current weather exposure underway (hazard level, since, classification, event id, peak sustained/gust, updated_at).
- **Depends on:** `WeatherModel` (HAZARD_*, CLASS_FAIR), `WeatherSample`.
- **Signals:** none.
- **State:** Owned by `SessionState.weather_exposure`; mutated only via `GameSession.update_weather_exposure()` (called from `Simulation` on its evaluation grid) and `reset()` by `GameSession` on departure and arrival.
- **Lifecycle:** Plain data object created by `SessionState`; copied with `duplicate_exposure()` for `GameSession.get_weather_exposure()`.
- **Persistence:** Saved under `session.weather.exposure` (`to_dict`/`from_dict`); `from_dict` requires finite numbers for level, since, peaks, updated_at and clamps level to HAZARD_NORMAL..HAZARD_SEVERE. `SaveManager` migration writes a reset exposure for old saves.
- **Invariants:** A new exposure starts when hazard level or responsible event changes (peaks reset).
- **Tests:** `tests/suites/test_weather.gd` (exposure identical across time-acceleration modes), `test_voyage_persistence.gd`, `test_simulation.gd`, `test_upkeep.gd` (indirect via `GameSession`); `tests/restart_check.gd`.
- **Change risks:** Save schema; must stay updated only on the fixed evaluation grid to remain speed-independent.

### `src/weather/weather_model.gd`

- **Role:** class_name `WeatherModel`, extends RefCounted; the authoritative weather query: `sample()` → `WeatherSample`, `sample_hazard()` → PackedFloat64Array, `sample_wind()` → Vector2(from, speed), `active_events()`, `cyclone_risk()`, `event_strength()`, hazard/class names.
- **Depends on:** `WindField` (background wind, `test_override`), `WeatherEvent`, `WeatherSample`, `GeoMath`, `Loc`; data `data/weather/weather_events.json` (gale zones, convective zones, cyclone basins, names).
- **Signals:** none.
- **State:** Static `_default`; zone data; `fixture_events`, `generated_enabled`; caches `_slot_cache`, `_bucket_cache`, `_bucket_reach`, `_cell_cache` (each cleared above `MAX_CACHE` 4096); `sample_count` profiling counter; `_scratch` sample reused by `sample_hazard`.
- **Lifecycle:** Static singleton via `get_default()`; `clear_default()` on `GameSession` shutdown. Callers: `Simulation`, `GameSession`, `MapView`, `WindLayer`, `WorldMap`, `PassageReadiness`, `WeatherDamage`, `Hud`, weather audio, boat lighting, `HatStory`, `HatState`, `ObjectiveCatalog`, `SessionState`, `SaveManager`, dev tools; `tools/weather/measure_wind_variation.gd`.
- **Persistence:** `model_version` is written to saves by `SessionState` (`session.weather.model_version`); a save needs only the seed and version to continue the same weather.
- **Performance:** Events collected per 15-min `BUCKET` with a bounded look-back per slot length; per-bucket reach boxes let `_events_near` skip distant events (Iteration 16). `sample_hazard`/`sample_wind` skip building samples/classification.
- **Invariants:** Pure function of (position, time, seed[, known_at]); `sample`, `sample_hazard` and `sample_wind` share `_compose` so they agree exactly (64-bit floats). Generation is off while `WindField.test_override` is set or `generated_enabled` is false (fixtures still apply). Cyclones are cut off once they leave their basin limit (never reach Europe).
- **Tests:** `tests/suites/test_weather.gd`, `test_weather_ui.gd`, `test_wind_overlay.gd`, `test_turbocharge.gd`, `test_navigation_views.gd`, `test_simulation.gd`, `test_atmosphere.gd`, `test_world_voyage.gd`, `test_upkeep.gd`, `test_upkeep_ui.gd`, and others; `tests/restart_17.gd`, `tests/restart_check.gd`, `tests/benchmark_17.gd`, `benchmark_wrs.gd`.
- **Change risks:** RNG draw order and hash strings define every event; any reordering changes the weather of existing saves. Cache keys include the seed. `_reach_boxes` must remain conservative.

### `src/weather/weather_sample.gd`

- **Role:** class_name `WeatherSample`, extends `WindField.Sample`; weather at one place/time: sustained effective `from_deg`/`speed_kn` (inherited), `gust_kn`, background wind, `hazard`, `classification`, responsible event id/kind/name, thunder flags, cyclone risk/basin.
- **Depends on:** `WindField.Sample`, `WeatherModel` (`hazard_name`, `class_label`).
- **Signals:** none.
- **State:** Plain data.
- **Lifecycle:** Created by `WeatherModel.sample()`; consumed by `Simulation`, `GameSession` (`update_weather_exposure`), `WeatherExposure`, `AnchorSite`, `Hud`, `WorldMap`, `HatStory`, weather audio.
- **Invariants:** `speed_kn` excludes gusts; `gust_kn ≥ speed_kn`. Being a `WindField.Sample` keeps propulsion, sails, HUD and chart working unchanged.
- **Tests:** `tests/suites/test_weather.gd`, `test_atmosphere.gd`, `test_turbocharge.gd`, `test_hat.gd`.
- **Change risks:** Field renames break `to_dict()` consumers in tests and the inheritance contract with `WindField.Sample`.

### `src/weather/wind_field.gd`

- **Role:** class_name `WindField`, extends RefCounted; deterministic background wind: European anchor climatology on a 0.5° lattice blended into a global belt/anchor lattice (2.5°, wrapping), plus travelling direction/speed waves and a lull wave; inner class `Sample` (from_deg, speed_kn, `to_deg`, `to_vector`). Static helpers `from_to_to`, `relative_angle`, `compass_name`.
- **Depends on:** `GeoMath` (`normalize`, `wrap_delta`), `Loc` (compass names); data `data/weather/wind_climate.json`.
- **Signals:** none.
- **State:** Static `_default`; anchors, belts, waves, lull; lazily built `_lattice` and `_global_lattice`; `test_override` Callable.
- **Lifecycle:** Static singleton via `get_default()`; `clear_default()` (also clears `test_override`) on `GameSession` shutdown and in `tests/test_runner.gd`. Main caller `WeatherModel`; also `PropulsionController`, `Simulation`, `GameSession`, `AnchorSite`, `Hud`, `VhfRadio`, radar and sailing panels, `WorldMap`.
- **Performance:** Lattices computed once on first use (Gaussian blend over all anchors per lattice point); per-sample cost is two bilinear lookups plus a few sine waves.
- **Invariants:** Pure function of (position, time, seed); continuous in space (no region borders) and across the Date Line (waves cross-faded within `DATELINE_FADE_DEG`). Speed factor never below `MIN_SPEED_FACTOR`. `from_deg` is meteorological (FROM).
- **Tests:** `tests/suites/test_wind.gd`, `test_weather.gd`, `test_wind_overlay.gd`, `test_sailing.gd`, `test_sailing_correctness.gd`, `test_world_voyage.gd`, `test_localization.gd` (compass names), and many suites that use the test runner's `test_override` helper (fixed calm or steady wind) in `tests/test_runner.gd`.
- **Change risks:** Changes alter wind for every save and seed, and with it all speeds/ETAs and test expectations; a test that sets `test_override` must clear it or later suites inherit the forced wind (and generated weather events stay off).

## Boats, decks, cabins and world

### `src/aboard/anchor_ambience.gd`

- **Role:** class_name `AnchorAmbience`, extends Node2D; computes the settled-at-anchor tint and cabin-lamp strength (no longer rendered since Iteration 17).
- **Depends on:** `GameSession` (`is_active`, `get_day_phase`, `is_settled_at_anchor`), `AnchorLife` (`TINTS`, `LAMP`, `PHASE_DAY`).
- **State:** Reads GameSession only. `lamps: Array[Vector3]` (x, y, radius) set by `BoatArea._setup_anchor_ambience` (cabin centre + galley stove; empty on deck). Private `_tint/_target/_lamp/_lamp_target`.
- **Lifecycle:** Instanced by `BoatArea._setup_anchor_ambience()` in every boat area as child "AnchorAmbience"; `_ready` sets `visible = false` and `refresh(true)`.
- **Performance:** `refresh()` every 0.5 s; per-frame lerp; `_draw` (18 rings per lamp) is skipped in practice because the node is hidden.
- **Invariants:** Must stay invisible: BoatLighting owns the area's CanvasModulate (two would fight). `is_active()` == target tint != white.
- **Tests:** `tests/suites/test_anchor_life.gd` (via `BoatArea.get_anchor_ambience()`).
- **Change risks:** Making it visible again double-tints the scene; `get_tint`/`get_lamp_strength` are test-facing API.

### `src/aboard/anchor_life.gd`

- **Role:** class_name `AnchorLife`, extends RefCounted; pure static rules and texts for life at anchor (revision 0.102b).
- **Depends on:** `CompanionState` (`KIND_CAT`, `KIND_DOG` keys in `PET_LINES`).
- **State:** None; constants (`PHASE_*`, `SETTLED_WIND_KN` 18, `SETTLE_DELAY_S` 20 min, `WAKE_MIN_SLEEP_S` 3 h, `TINTS`, `LAMP`, line arrays).
- **Lifecycle:** Static helper. Used by `GameSession` (`get_local_hour`, `get_day_phase`, settled check, moment recording, wake/pet/coffee lines), `AnchorAmbience`, `AboardBadge`.
- **Invariants:** `local_hour` = fposmod(time/3600 + lon/15, 24) (solar hour, game time is UTC); `phase_at` boundaries 5/9/18/22.5; `pick(lines, seed)` deterministic (posmod), so reloads show the same line; `local_day` keys once-a-day moments.
- **Persistence:** None directly; GameSession records moment keys on the anchor state (indirect).
- **Tests:** `tests/suites/test_anchor_life.gd`.
- **Change risks:** Changing `local_day`/`pick` changes which moment keys/lines existing saves have already recorded; phase boundaries also drive AboardBadge text and the coffee-at-anchor line in GameSession. Note this is a separate clock from `Daylight` (sun elevation).

### `src/aboard/cabin_decor.gd`

- **Role:** class_name `CabinDecor`, extends Node2D; draws one cabin decor item (I020) and provides the static placement algorithm. I021 adds `model_ship`, `sea_glass` (shelf) and `barometer` (wall) to the `_draw()` match; Operation Paperwork adds `compass` (wall) and a second placement pass: wall items left over by the first pass (unchanged) retry `_wall_spot` from start lines y = 0 and bounds centre ± 0.35 height (the Clam 40's hull cabins) at `SPACING`, then `SECOND_SPACING` 56. With all ten things every cabin places ten (the Arctic Wanderer 26 and Clam 40 first-pass capacity is seven wall spots).
- **Depends on:** `HarbourTrades.get_decor_item(id)` (`place`: "wall"/"floor"), `Geometry2D`.
- **State:** `item_id` ("rug", "herbs", "chart_print", "oil_lamp", "books", "bunting", and since I021 "model_ship", "sea_glass", "barometer"; "compass"), `side` (+1 starboard, -1 port, 0 floor).
- **Lifecycle:** Instanced by `BoatArea.setup_decor()` (cabin only), which frees and rebuilds all CabinDecor on `GameSession.home_changed`; the rug goes under `Visual` after `CabinBase`, wall items before `Layout`.
- **Performance:** `place_all` is a one-off scan: `_floor_spot` 10 px grid over hull bounds with 12-point rug test per fixture; `_wall_spot` 41 candidates with 2 px wall walk (up to 3 start lines x 2 sides x 2 spacings more per left-over item).
- **Invariants:** Deterministic for the same hull/fixtures/avoid (no RNG). Wall items keep `CLEARANCE` 46 from avoid points and `SPACING` 70 from each other (only second-pass items may be 56 from a neighbour); rug keeps `RUG_RADIUS + 24` and lies fully inside hull and outside all fixtures. Items with no clear place are omitted.
- **Tests:** `tests/suites/test_boat_of_your_own.gd` (also `tests/scratch/probe_decor.gd`).
- **Change risks:** Avoid list is assembled in BoatArea (stations, CompanionSpots, TrophyBoard, GalleyStove, TableMug, HatSpot); new gear not added there can be overlapped. `_wall_y(hull, x, side, start)` walks from `start` (default 0) and returns NAN where that point is outside the hull.

### `src/aboard/coffee_mug.gd`

- **Role:** class_name `CoffeeMug`, extends Node2D; presentation of the mug at the deck cup holder or the cabin table (Cozy Polish).
- **Depends on:** `GameSession` (`get_coffee`, `coffee_changed`, `state_replaced`).
- **Signals:** Connects `GameSession.coffee_changed` and `state_replaced` -> `queue_redraw`.
- **State:** `place` (`&"holder"` / `&"table"`; BoatArea assigns `GameSession.COFFEE_HOLDER` / `COFFEE_TABLE`). `has_mug()` = `GameSession.get_coffee() == place`.
- **Lifecycle:** Instanced by `BoatArea._setup_aboard_gear()` ("CupHolder" on deck via `cup_holder_position` or `Layout/CupHolderSpot`) and `_setup_table_mug()` ("TableMug" in cabin). Static `draw_mug()` is also used by `SailorDrawing`.
- **Tests:** `tests/suites/test_cozy_polish.gd`.
- **Change risks:** `draw_mug` signature is shared with SailorDrawing; place values must match GameSession constants.

### `src/aboard/galley_stove.gd`

- **Role:** class_name `GalleyStove`, extends Node2D; drawn galley stove that steams after cooking (Iteration 13).
- **Depends on:** `GameSession.meal_cooked`, `HighlightResolver.rounded_rect`.
- **Signals:** Connects `GameSession.meal_cooked` -> `steam()`.
- **State:** `_steam` (real seconds left, default 12), `_time`.
- **Lifecycle:** Instanced by `BoatArea._setup_aboard_gear()` (cabin) beside the Provisions station; BoatArea adds a `HighlightProvider` child with `outline()` for interaction `&"cook"`.
- **Performance:** `_process` redraws every frame only while steaming.
- **Tests:** `tests/suites/test_galley_and_anchor.gd`.
- **Change risks:** `outline()` drives the cook station highlight; z_index 3 ordering vs. player.

### `src/aboard/rod_holder.gd`

- **Role:** class_name `RodHolder`, extends Node2D; drawn fishing rod on the stern rail (Iteration 13).
- **Depends on:** `GameSession` (`is_line_out`, `get_pending_bite`, `fishing_changed`, `fish_bite`).
- **Signals:** Connects `fishing_changed` and `fish_bite` -> `queue_redraw`.
- **State:** `_time` only.
- **Lifecycle:** Instanced by `BoatArea._setup_aboard_gear()` (deck) at `BoatArea.rod_holder_position()`; HighlightProvider for `&"fishing"` from `outline()`.
- **Performance:** Redraws every frame while the line is out.
- **Tests:** `tests/suites/test_fishing.gd`.
- **Change risks:** Coordinates assume deck frame (+x bow, -y port); `TIP` also shapes the highlight outline.

### `src/aboard/trophy_board.gd`

- **Role:** class_name `TrophyBoard`, extends Node2D; cabin trophy board with `FishingState.TROPHY_COUNT` slots (Iteration 13/18).
- **Depends on:** `GameSession.get_fishing().trophies`, `FishingState.TROPHY_COUNT`, `FishArt.thumbnail`, `HighlightResolver.rounded_rect`.
- **Signals:** Connects `GameSession.fishing_changed` and `state_replaced` -> `refresh()`.
- **State:** One `Sprite2D` child per slot ("Fish%d"); fallback colours in `FISH_COLOURS`.
- **Lifecycle:** Instanced by `BoatArea._setup_aboard_gear()` (cabin) at `BoatArea.trophy_place()`; HighlightProvider for `&"trophies"`.
- **Invariants:** Pictures must be Sprite2D children, not `draw_texture_rect` in `_draw` (fix after 0.105b: undrawn thumbnails rendered as white rectangles).
- **Tests:** `tests/suites/test_fishing.gd`, `tests/suites/test_cozy_patch.gd` (also `tests/scratch/test_zz_trophy.gd`).
- **Change risks:** Reverting to `_draw`-based textures reintroduces the white-rectangle bug; `get_picture(i)` is test API.

### `src/aboard/windlass.gd`

- **Role:** class_name `Windlass`, extends Node2D; drawn foredeck windlass, chain and stowed anchor (Iteration 13).
- **Depends on:** `GameSession` (`is_anchored`, `get_anchor().holding`, `anchor_changed`, `state_replaced`), `AnchorState.HOLDING_DRAGGING`, `HighlightResolver.rounded_rect`.
- **Signals:** Connects `anchor_changed`, `state_replaced` -> `queue_redraw`.
- **State:** `bow` (set by BoatArea from the hull's bow x), `_time`.
- **Lifecycle:** Instanced by `BoatArea._setup_aboard_gear()` (deck) at `BoatArea.windlass_position()`; HighlightProvider for `&"anchor"`.
- **Performance:** Redraws every frame while anchored.
- **Tests:** `tests/suites/test_galley_and_anchor.gd`.
- **Change risks:** Purely visual; the dragging ring is the only on-deck alarm cue here.

### `src/boat/anchor_signals.gd`

- **Role:** class_name `AnchorSignals`, extends Node2D; anchor ball, rode and marker buoy on deck while anchored (Iteration 18; Magic Anchor look 0.105b).
- **Depends on:** `BoatArea` (`walkable_bounds`, `SailRig` node), `BoatLighting.boat_bounds()`, `SailRig.mast`, `ArtworkResolver.get_artwork` (`BUOY_ID`, `BALL_ID`), `GameSession` (`is_active`, `is_anchored`, `get_anchor()`), `AnchorState` (`KIND_MAGIC`, `HOLDING_DRAGGING`, `scope`), `SettingsManager.get_reduce_motion`.
- **Signals:** Connects `GameSession.anchor_changed`, `state_replaced` -> `_refresh`.
- **State:** Reads GameSession only; nothing saved. `bow`, `mast`, `_clock`, replacement textures.
- **Lifecycle:** Created in `BoatArea._setup_lighting()` (deck only) and `setup(area, lighting)` called; z_index 24 absolute.
- **Performance:** `set_process(visible)`: per-frame redraw only while anchored.
- **Invariants:** Visible only when anchored (not moored, not underway, not merely holding at an anchorage). Buoy distance = 70 + 6*scope (Magic: fixed 64), x0.8 when dragging. Boat coordinates, so it rotates with the course view.
- **Tests:** `tests/suites/test_sprite_workshop.gd`, `tests/suites/test_companion_deck.gd`, `tests/suites/test_joy_journey.gd`, `tests/suites/test_solar_panels.gd` (via `BoatArea.get_anchor_signals()`).
- **Change risks:** Must be added after BoatLighting and with SailRig present to get correct mast/bow; replacement art is centred on the same points.

### `src/boat/boat_area.gd`

- **Role:** class_name `BoatArea`, extends Node2D; root script of every vessel's `deck.tscn` / `cabin.tscn`; places the player, builds aboard presentation, routes interactions to signals. I022: `_setup_water_look` (Surroundings/Water colour via `_recolour_water`, connected to voyage_started / voyage_arrived (`_on_arrived_recolour_water`) / anchor_changed; `ShallowWater` as a child of Water), `_setup_cabin_windows` (interior; `CabinWindows.setup`; sibling after the `CabinBase` slot), `_update_cabin_windows` (visible only with an illustrated CabinBase texture; also on art style change), `get_cabin_windows()`.
- **Depends on:** `GameSession`, `Simulation` (heading, weather), `SettingsManager`, `AudioManager`, `SessionLog`, `Loc`, `Player`, `Interactable`, `VesselVisual`, `VesselVisualProfile`, `VesselDefinition`, `SailRig`, `FenderStowage`, `HarbourDressing`, `WaterLife`, `AnchorAmbience`, `BoatLighting`, `WeatherVisuals`, `AnchorSignals`, `DeckCompanionSpots`, `ShipCompanion`, `CompanionRemarks` (pet: `take_remark()` → `message_requested`; hands full: `hands_full()`), `ShoreAccess`, `HarbourFacilities`, `RodHolder`, `Windlass`, `CoffeeMug`, `GalleyStove`, `TrophyBoard`, `CabinDecor`, `HarbourTrades`, `HighlightProvider`, `HighlightResolver`, `HatHook`, `HatBlowAway`, `HatState`, `BoatFixture`.
- **Signals:** Declares `area_change_requested(area, spawn_point)`, `chart_requested`, `world_map_requested`, `sleep_requested`, `helm_requested`, `boatyard_requested`, `provisions_requested`, `work_requested`, `grocery_requested`, `go_ashore_requested`, `fishing_requested`, `anchor_requested`, `cooking_requested`, `trophies_requested`, `message_requested(text)`, `interaction_prompt_changed(prompt)`, `docking_finished` — emitted from `_on_interacted` by `interaction_id`, prompt changes, and the end of `play_docking_arrival`. Connected in `App._connect_boat_area`. Connects to many GameSession signals (`condition_changed`, `voyage_started`, `voyage_arrived`, `voyage_course_changed`, `state_replaced`, `rescued`, `hat_changed`, `hat_lost`, `home_changed`, `coffee_changed`) and `SettingsManager.art_style_changed` / `course_view_changed`.
- **State:** Writes `SessionState.player_position` via `GameSession.set_player_position` every physics frame (unless leaving); reads spawn point / restored position on `_place_player`. Hat/coffee actions go through `GameSession.use_hat_hook`, `put_coffee_down`, `pick_up_coffee`. Owns camera tween, shore station map, docking tween.
- **Lifecycle:** Instanced scene (per vessel, via `VesselDefinition.get_area_scene`) by App's screen router. `_ready` order matters: visual profile -> shore (before player placement) -> aboard gear -> player -> interactable connections -> mooring -> harbour dressing -> water life -> anchor ambience -> camera -> lighting (+weather, anchor signals, deck companion) -> overhead z -> hat hook; highlights resolved deferred.
- **Persistence:** Player position is area-relative; `is_valid_player_position` rejects positions outside `walkable_bounds`, outside the Lifeline polygon (deck) unless on an active pontoon — falls back to spawn.
- **Performance:** `_process`: view-key compare each frame (re-turns camera when octant changes without a signal), course-view follow lerp, shore camera lerp. Placement helpers scan the hull polygon in 2–6 px steps once at setup.
- **Invariants:** Presentation only: never changes scenes or opens UI itself; docking arrival changes no game state and is skippable by any key. Octant view uses `OCTANT_HYSTERESIS_DEG` 8°. Gear placement derived from each boat's own Lifeline/Hull polygons and fixtures (no per-boat offsets). Stations added at runtime after `_ready` (e.g. deck companion's "Pet") must be connected to `_on_interacted` manually.
- **Tests:** Very broad; principal suites: `tests/suites/test_gameplay_flow.gd`, `test_galley_and_anchor.gd`, `test_fishing.gd`, `test_cozy_polish.gd`, `test_cozy_patch.gd`, `test_companion_remarks.gd`, `test_eight_directions.gd`, `test_navigation_views.gd`, `test_harbour_life.gd`, `test_hat.gd`, `test_boat_of_your_own.gd`, `test_vessels.gd`, `test_catamaran_cabin.gd`, `test_lighting.gd`, `test_atmosphere.gd`, `test_anchor_life.gd`, `test_companion_deck.gd`, `test_presentation.gd`, `test_upkeep_ui.gd` (plus screenshot/benchmark scripts in `tests/`).
- **Change risks:** `_ready` ordering (shore before `_place_player`; lighting before anchor signals); node-path conventions (`Visual`, `Layout/Collision/Hull|Lifeline/CollisionPolygon2D`, `Layout/Stations`, `Layout/SpawnPoints`, `Layout/HatSpot`, `Layout/CupHolderSpot`, `Surroundings/Water`, `SailRig`, `Camera2D`) are relied on by many helpers and tests; `get_lighting()` looks up `^"Lighting"` while BoatLighting names itself `Loc.t("Lighting")`; interaction ids are a string contract with scenes.

### `src/boat/boat_fixture.gd`

- **Role:** `@tool`, class_name `BoatFixture`, extends StaticBody2D; collision of one piece of furniture/fitting from `size` (centred rect) or `polygon`.
- **Depends on:** Godot physics only (`ConvexPolygonShape2D`, shape owners).
- **State:** Exports `size`, `polygon`, `solid` (setters rebuild). `get_points()` is the shared outline accessor.
- **Lifecycle:** Placed in vessel scenes under `Layout/Collision`; also runs in the editor (draws translucent outline only when `Engine.is_editor_hint()`).
- **Invariants:** Draws nothing at runtime; art lives in `Visual` (VesselVisual). Non-solid fixtures have no shape. Polygon must be convex (ConvexPolygonShape2D).
- **Tests:** `tests/suites/test_vessels.gd`, `tests/suites/test_catamaran_cabin.gd`, `tests/suites/test_visual_prototype.gd`; `tests/helpers/walkability.gd`. Also read by `tools/vessels/render_art_templates.gd`.
- **Change risks:** Fixture node names are a contract with `BoatLighting.CABIN_LAMPS`, `HighlightResolver.FIXTURES`, BoatArea's `_nearest_fixture` (Galley, SaloonTable/Table, VBerth…), shadows skip "Hull"/"Lifeline". Concave polygons give wrong collision.

### `src/boat/boat_lighting.gd`

- **Role:** class_name `BoatLighting`, extends Node2D; time-of-day light, lamps, nav/anchor/quay lights and soft shadows for one boat area (Iteration 17/18). Inner classes `Lamps`, `FixtureShadows`, `CornerShade`, `ContactShadow`. Golden Harbours: static `overcast_of(weather: WeatherSample) -> float` (0.8 thunder/squall/storm classes, 0.5 gale or thunder possible, 0.25 strong wind, else 0; 0 for null), used by `_process`, `CabinWindows` and `App.show_harbour_moment`.
- **Depends on:** `BoatArea` (`area_id`, `walkable_bounds`, `player`, `get_shore_access`, `get_harbour_dressing`, layout nodes), `BoatFixture`, `Interactable` (companionway lookup; writes static `Interactable.light_compensation`), `SailRig.mast`, `HarbourDressing` (`get_lamp_positions`, `get_pontoon_light_positions`), `ShipCompanion`, `Daylight` (`sun_elevation`, `inside_colour`, `outside_colour`, `daylight`), `GameSession` (time, position, underway, anchored), `Simulation.get_weather_at_vessel`, `WeatherModel` classes, `SettingsManager.get_flash_intensity`, `SessionState.AREA_INTERIOR`.
- **State:** `_lights` entries `{light, energy, when, lamp}` with `when` in dark/night/day/harbour/underway/anchor; `_colour`, `_darkness`, `_overcast`, `_flash`. Static shared gradient textures. Adds a `CanvasModulate` "Ambient" to the area.
- **Lifecycle:** Created by `BoatArea._setup_lighting()` (every area) then `setup(area)`; `GameSession.state_replaced` -> `update_now`. `flash()` called by `WeatherAudio` via App's `lighting_provider`.
- **Performance:** One colour blend + loop over a handful of PointLight2D per frame; weather sampled when game time moves ≥ `WEATHER_REFRESH` (600 game s). Shadows/corner shade drawn once; only alpha animates.
- **Invariants:** The only CanvasModulate in the scene (AnchorAmbience is hidden for this). Light follows clock with `FOLLOW_RATE` 2.5/s (no strobe at Long Passage speed); `update_now()` snaps. Nav lights only underway and not anchored; anchor light only anchored; harbour lights only moored. Cabin lamps keyed by fixture names, not art.
- **Tests:** `tests/suites/test_lighting.gd`, `tests/suites/test_companion_deck.gd`, `tests/suites/test_atmosphere.gd`; `tests/cabin_light_18.gd`.
- **Change risks:** The node name is the literal "Lighting" (never translated: `BoatArea.get_lighting()`, `App.snap_light()` and WeatherAudio's flash find it by name; in Danish it was "Belysning" until the Engine Room pass, checked by `test_localization`); renaming fixtures silently drops lamps; changing `light_compensation` affects all highlights; AnchorSignals depends on `boat_bounds()`.

### `src/boat/cabin_windows.gd`

- **Role:** class_name `CabinWindows`, extends Node2D (I022). static `windows_for(vessel_id)` (data/vessels/cabin_windows.json `windows.<id>`: at, length, thickness, angle, side), `setup(area, vessel_id) -> bool`, `viewer_position()`, `view_of(window, viewer)` → {centre (compass: heading + outward angle from the bow + atan2 offset of the captain), fov (2·atan(half length / depth), 16–80°), right, outward}, `_sample_world()` (heading: `Simulation.get_current_heading()` underway else 90°, elevation, sun bearing from `Daylight.local_solar_hours`, daylight, overcast as BoatLighting, `WeatherAudio.rain_level`, wind, hazard, moored, `HarbourLooks.picture_for(location)`, `WaterLook.water_colour`), `_draw` → per window `draw_set_transform_matrix(Transform2D(right, -outward, at))` + `_draw_window` (sky gradient, stars on a 6° grid, sun + glow, `_draw_shore` quay at heading+90° ±40° and far shore at heading−90° ±22°, sea + crests on a 4° grid drifting with game time, rain, glass `GLASS_TINT`·`glass_strength`, frame). `last_draw_usec`. Golden Harbours: overcast via `BoatLighting.overcast_of(sample)` (was a local copy of the same thresholds).
- **Depends on:** `BoatArea.player`, `Simulation`, `Daylight`, `WeatherModel` classes, `WeatherAudio.rain_level`, `HarbourLooks`, `WaterLook`.
- **State:** `windows`, `world`, `_viewer`, `_refresh_left`, static `_data`, static `glass_strength`.
- **Lifecycle:** created by `BoatArea._setup_cabin_windows` (interior only, inserted right after the `CabinBase` slot of `Visual`, under `FurnitureVisual`); `_update_cabin_windows` hides it with the classic art.
- **Tests:** `tests/suites/test_cabin_windows.gd`.
- **Change risks:** everything is drawn inside each opening's rectangle (clamped), so nothing bleeds onto walls; the quay is assumed starboard (as the deck scenes lie alongside); only boats listed in the data get windows.

### `src/boat/cabin_world_map.gd`

- **Role:** class_name `CabinWorldMap`, extends Node2D; framed world chart on the cabin wall (Iteration 17), and static Mercator/land helpers shared with the voyage map.
- **Depends on:** `MapView.WORLD_LAND_RES`, `WorldLand` (`overview_fill`, `scale`), `MapProjection.map_to_geo`, `GameSession` (`get_captains_log().get_visited_ids()`, `get_vessel_position`), `PortCatalog`, `HighlightResolver` (`GROUP`, `META_FOR`), `RenderingServer.canvas_item_add_triangle_array`.
- **State:** Static caches `_triangles`, `_built`, `_indices`, `_white` (unit-square land triangles).
- **Lifecycle:** Scene `src/boat/cabin_world_map.tscn` instanced in all four vessels' `cabin.tscn`; the scene's `Interactable` with `interaction_id = &"world_map"` makes BoatArea emit `world_map_requested`. Registers itself as a highlight provider for `&"world_map"`.
- **Performance:** Land triangulated once per run (static); draw is a single triangle batch; pins redrawn only on redraw (cabin entry).
- **Invariants:** Crop NORTH 78 / SOUTH −58 Mercator; `to_unit`/`aspect` must match what `VoyageMap` expects.
- **Tests:** `tests/suites/test_navigation_views.gd`.
- **Change risks:** `VoyageMap` uses `to_unit`, `aspect`, `land_triangles`, `land_indices`, `land_colours`; changing crop or projection moves both maps. Static cache is never invalidated (land data assumed fixed per run).

### `src/boat/fender_stowage.gd`

- **Role:** class_name `FenderStowage`, extends RefCounted; static detection/removal of fenders painted into deck art (Iteration 17).
- **Depends on:** `VesselVisual.get_slot`, `VisualSlot` (`is_sprite`, `get_sprite`), Image/ImageTexture.
- **State:** Static `_cache` texture -> `{rects, stowed}`. Uses sprite meta `&"art_texture"` to remember the original texture.
- **Lifecycle:** Static helper; `apply(visual, out)` called by `BoatArea.update_fenders()` (deck only) from `apply_visual_profile` and `_update_mooring`.
- **Performance:** One pixel scan per texture (bottom `BAND` 16%, `STEP` 2 px, flood fill), cached for the run ("a few tens of milliseconds once").
- **Invariants:** Never modifies art files; only slots `DeckBase` and `DeckDetails`; fenders are light blobs within `MIN_SIZE`..`MAX_SIZE`.
- **Tests:** `tests/suites/test_presentation.gd`.
- **Change risks:** Threshold changes may erase other light art in the band; the `art_texture` meta logic must detect reloaded art (Artwork setting switch) correctly.

### `src/boat/provision_display.gd`

- **Role:** `@tool`, class_name `ProvisionDisplay`, extends Node2D; cabin presentation of food/water stores (4 food items + 4 jugs, Cozy Polish).
- **Depends on:** `GameSession` (`get_food_days`, `get_water_days`, `is_active`, `provisions_changed`, `state_replaced`, `get_vessel_definition`), `Provisions` (`CAPACITY_DAYS`, `level_of`, `LEVEL_*`), `VesselVisualProfile` (`art_folder`, `procedural_only`), `Loc`.
- **Signals:** Connects `provisions_changed`, `state_replaced` -> `refresh`.
- **State:** `food_days`, `water_days` (last shown), optional `_sprite` for `<art_folder>/cabin/provisions_<level>.png`.
- **Lifecycle:** Placed as node "ProvisionDisplay" in each vessel's `cabin.tscn`; BoatArea refreshes it on art-style change.
- **Performance:** `_process` compares filled-item counts/level each frame; redraws only on change.
- **Invariants:** `DAYS_PER_ITEM = CAPACITY_DAYS / ITEMS`; `filled_items` rounds up; level shown is that of the scarcer supply.
- **Tests:** `tests/suites/test_upkeep_ui.gd`, `tests/suites/test_visual_prototype.gd`.
- **Change risks:** Editor-hint guards must stay (tool script would otherwise touch GameSession in the editor).

### `src/boat/sail_rig.gd`

- **Role:** class_name `SailRig`, extends Node2D; procedural/textured mainsail, jib and spinnaker on deck, pure presentation of propulsion state.
- **Depends on:** `GameSession` (`is_active`, `is_underway`, `is_anchored`, `is_holding_at_anchorage`, `get_propulsion()` -> `initialised`, `sails_set()`, `true_wind_angle`, `spinnaker`), `VesselVisualProfile.get_texture`, `HarbourTrades.sail_colours`, `RenderingServer` triangle arrays, viewport `Camera2D`.
- **State:** Attachment points from `Layout/SailMarkers` (Mast, Tack, BoomEnd, Traveller, JibSheetLead, SpinnakerSheetLead) or sloop defaults; pose (`main_angle_deg`, `jib_angle_deg`, `set_amount`, `spinnaker_amount`), `animation_time`; textures and cloth colours; `see_through` (player, set by BoatArea). Writes `camera.offset.x` (spinnaker framing) unless camera meta `course_view`.
- **Lifecycle:** Node "SailRig" in each vessel's `deck.tscn`; `apply_profile` and `set_cloth` from BoatArea; `snap()` on ready.
- **Performance:** Rebuilds geometry and redraws every frame (bounded bezier point counts).
- **Invariants:** Never feeds the simulation: motion is cosmetic, real time. Sails furled in harbour, at anchor and holding at an anchorage. Leeward rule: twa ≥ 0 -> sails to port. Textured sail strips need equal-length outer/inner edges. `_inner` drops endpoints to avoid duplicate vertices in polygon triangulation.
- **Tests:** `tests/suites/test_sailing_presentation.gd`, `tests/suites/test_vessels.gd`, `tests/suites/test_presentation.gd`, `tests/suites/test_companion_deck.gd`, `tests/suites/test_life_aboard.gd`, `tests/suites/test_boat_of_your_own.gd`; `tests/screenshots_17.gd`.
- **Change risks:** `get_shape()`, `mast`, `covers()` are used by tests, BoatLighting/AnchorSignals (mast) and BoatArea (view bounds); camera offset interacts with BoatArea's course view.

### `src/boat/visuals/damage_overlay.gd`

- **Role:** class_name `DamageOverlay`, extends Node2D; cosmetic wear/damage marks by `VesselCondition` band.
- **Depends on:** `VesselVisual` (`canvas`, `profile`, `get_slot`), `VesselCondition` (`BAND_*`, `band_of`, `FULL`), `VesselVisualProfile.get_damage_texture`, `ProceduralShape.get_points`.
- **State:** `condition`, `band`, `area` ("deck"/"cabin"), outlines from base slots (`CabinBase` or `HullBase`+`DeckBase`), up to 60 marks, optional sprite.
- **Lifecycle:** Created lazily by `VesselVisual.set_condition()` (called from `BoatArea.show_condition`, keyed `"<vessel_id>/<area_id>"`).
- **Performance:** Marks placed once (≤ 4000 attempts); draw loops ≤ 60 marks.
- **Invariants:** Deterministic in key (RNG seeded with `hash(key)`); earlier marks are milder (first 14 only scuff/rust), so bands nest. Never touches slot sprites; no collision.
- **Tests:** `tests/suites/test_visual_prototype.gd`.
- **Change risks:** Changing mark order/kinds or `MARKS_PER_BAND` changes every boat's look; outlines rely on base slot child Polygon2D/ProceduralShape nodes.

### `src/boat/visuals/procedural_shape.gd`

- **Role:** `@tool`, class_name `ProceduralShape`, extends Node2D; placeholder art shape with outline and optional label.
- **Depends on:** Barlow-SemiBold font (preload).
- **State:** Exports `size`, `polygon`, `fill_color`, `outline_color`, `label`, `label_color`, `label_size`.
- **Lifecycle:** Placed inside `VisualSlot`s in vessel `*_visual.tscn` scenes; editor-live.
- **Invariants:** Visual only; matching collision is a `BoatFixture`. `get_points()` mirrors BoatFixture's contract.
- **Tests:** `tests/suites/test_catamaran_cabin.gd`.
- **Change risks:** DamageOverlay uses `get_points()` for boat outlines.

### `src/boat/visuals/solar_panels.gd`

- **Role:** class_name `SolarPanels`, extends Node2D; decorative solar panels (0.105b), no gameplay.
- **Depends on:** `ArtworkResolver.get_artwork(SPRITE_ID)` (`&"boat.shared.solar_panel"`).
- **State:** `panels: Array[Rect2]` (boat coordinates), optional replacement texture. Nothing saved.
- **Lifecycle:** Created by `VesselVisual._apply_solar_panels()` from the exported `VesselVisual.solar_panels` (e.g. set in `halcyon_40/deck_visual.tscn`); placed after `DeckDetails`.
- **Invariants:** Panels lie aft of the walkable deck; never affects collision or walkability.
- **Tests:** `tests/suites/test_solar_panels.gd`, `tests/suites/test_sprite_workshop.gd`.
- **Change risks:** Panel rects defined per deck visual scene; z order relative to rigging set by VesselVisual.

### `src/boat/visuals/vessel_visual.gd`

- **Role:** class_name `VesselVisual`, extends Node2D; root of `deck_visual.tscn` / `cabin_visual.tscn`, chooses sprite vs procedural per `VisualSlot`.
- **Depends on:** `VisualSlot`, `VesselVisualProfile` (`get_texture`, `procedural_only`, `SLOT_FILES`), `ArtworkResolver.get_artwork` (Sprite Workshop id `boat.<vessel>.<deck|cabin>.<layer>`), `SolarPanels`, `DamageOverlay`.
- **State:** Exports `canvas` (shared art canvas, scene units), `solar_panels`; `profile`.
- **Lifecycle:** Instanced as `Visual` in each gameplay scene; `apply()` called by `BoatArea.apply_visual_profile`; also instanced alone by `BoatyardMenu` previews and `tools/vessels/render_art_templates.gd`.
- **Invariants:** No collision/interaction under Visual. Workshop id derives from `scene_file_path` (folder = vessel id, file name prefix "cabin" vs deck). Workshop replacements apply only when profile is not `procedural_only`.
- **Tests:** `tests/suites/test_vessels.gd`, `test_visual_prototype.gd`, `test_presentation.gd`, `test_upkeep_ui.gd`, `test_sprite_workshop.gd`, `test_solar_panels.gd`, `test_living_world.gd`.
- **Change risks:** Moving visual scene files changes Workshop ids; `_apply_solar_panels` uses `free()` (immediate) on the old node.

### `src/boat/visuals/vessel_visual_profile.gd`

- **Role:** class_name `VesselVisualProfile`, extends Resource; per-vessel art assignment with fallback inspector -> conventional PNG -> procedural.
- **Depends on:** `VesselCondition.BAND_SOUND`, `ResourceLoader`.
- **State:** `art_folder`, `procedural_only`, per-slot Texture2D exports, per-area/band damage textures. Data in `data/vessels/*_visuals*.tres`.
- **Lifecycle:** Resource referenced by `VesselDefinition.visual_profile` / `illustrated_visual_profile`.
- **Invariants:** Slot names and `SLOT_FILES` (property, filename) are the art-pipeline contract (`docs/artwork/ART_PIPELINE.md`); `DECK_SLOTS`/`CABIN_SLOTS` decide the deck/cabin subfolder. Missing files never hide a slot.
- **Tests:** `tests/suites/test_vessels.gd`.
- **Change risks:** Renaming a slot/file breaks drop-in art, VesselVisual Workshop ids, SailRig textures (`MainSailVisual`, `HeadSailVisual`, `SpinnakerVisual`, `BoomVisual`) and ProvisionDisplay/DamageOverlay path conventions.

### `src/boat/visuals/visual_slot.gd`

- **Role:** class_name `VisualSlot`, extends Node2D; one named art layer toggling between procedural children and a canvas-sized Sprite2D.
- **Depends on:** None beyond Godot (`Sprite2D`).
- **State:** `slot` (defaults to node name), `_sprite`.
- **Lifecycle:** Placed in vessel `*_visual.tscn`; driven by `VesselVisual.apply`.
- **Invariants:** Sprite placed at canvas top-left, scaled uniformly to canvas width; warns if aspect differs >1%.
- **Tests:** None found by class name; exercised indirectly through VesselVisual suites (`test_vessels.gd`, `test_visual_prototype.gd`, `test_sprite_workshop.gd`).
- **Change risks:** `FenderStowage` swaps `get_sprite().texture` directly and relies on `is_sprite()`; `show_procedural` frees the sprite (losing FenderStowage meta).

### `src/boat/shallow_water.gd`

- **Role:** class_name `ShallowWater`, extends Node2D (I022). `PATCHES` 9 soft polygons (plus a fainter rim) within `SPREAD` 1500, alpha `ALPHA` 0.07·translucency, seeded by `hash(location id)` moored (else the position); `refresh()` (visibility = `WaterLook.is_shallow()` and translucency > 0), connected to `voyage_started`, `voyage_arrived` (`_on_arrived`), `anchor_changed`.
- **Depends on:** `WaterLook`, `GameSession`.
- **State:** `_seed`.
- **Lifecycle:** added by `BoatArea._setup_water_look` as a child of `Surroundings/Water` (decks only), so it draws over the water and under `WaterLife`, which stays the Water's next sibling.
- **Tests:** `tests/suites/test_cabin_windows.gd` (deck water screenshots).
- **Change risks:** method connections (not lambdas) so they disconnect when the deck scene is freed.

### `src/boat/water_look.gd`

- **Role:** class_name `WaterLook`, extends RefCounted, static only (I022). `DEEP` (the old Surroundings/Water colour), `SEABED`, `OPEN_SEA` 0.12, `SHALLOW_EXTRA` 0.1, static `translucency` (1 default, 0 = old water), `water_colour(shallow)` (DEEP.lerp(SEABED, share·translucency), max 0.6), `is_shallow()` (moored or anchored).
- **Depends on:** `GameSession.is_underway/is_anchored`.
- **State:** static `translucency`.
- **Lifecycle:** read by `BoatArea._setup_water_look/_recolour_water`, `ShallowWater`, `CabinWindows._sample_world`.
- **Tests:** `tests/suites/test_cabin_windows.gd` (`[water]`, before/after screenshots).
- **Change risks:** independent from `CabinWindows.glass_strength` by design (the addendum asks for separate controls).

### `src/boat/weather_visuals.gd`

- **Role:** class_name `WeatherVisuals`, extends Node2D; deck wind streaks and rain (Iteration 17).
- **Depends on:** `BoatArea.walkable_bounds`, `GameSession` (`is_active`, `is_underway`), `Simulation` (`get_weather_at_vessel` -> `from_deg`, `speed_kn`; `get_current_heading`), `WeatherAudio.rain_level`.
- **State:** `wind_direction` (boat frame), `wind_kn`, `rain`; streak/drop arrays; RNG seed 7.
- **Lifecycle:** Created by `BoatArea._setup_lighting()` on decks only; `setup(area)`; z_index 40.
- **Performance:** Weather sampled every 0.5 s; per-frame update/draw bounded by `MAX_STREAKS` 40 and `MAX_DROPS` 260.
- **Invariants:** Samples the weather at the boat only (never a field). Rain follows the same rule as rain audio. Moored heading assumed 90° (bow east).
- **Tests:** `tests/suites/test_atmosphere.gd`.
- **Change risks:** Moored-heading convention differs from WaterLife and `BoatArea.wind_direction_on_deck` (both use 0° when moored); check before unifying.

### `src/interaction/highlight_provider.gd`

- **Role:** class_name `HighlightProvider`, extends Node2D; invisible outline source for a drawn object (Iteration 12).
- **Depends on:** `HighlightResolver` (`GROUP`, `META_FOR`).
- **State:** `outline` (local points).
- **Lifecycle:** `HighlightProvider.create(id, outline)` used by `BoatArea._add_gear` (RodHolder, Windlass, GalleyStove, TrophyBoard) and `HarbourDressing`.
- **Tests:** `tests/suites/test_visual_prototype.gd`.
- **Change risks:** Must keep group + meta or HighlightResolver ignores it.

### `src/interaction/highlight_resolver.gd`

- **Role:** class_name `HighlightResolver`, extends RefCounted; static resolution of a station's highlight outline, plus outline helpers.
- **Depends on:** `Interactable`, `BoatFixture`, SceneTree group `interaction_highlight`.
- **State:** None; `FIXTURES` map (nav_table, bed, provisions, work, helm, companionway), `MAX_FIXTURE_DISTANCE` 90.
- **Lifecycle:** Static helper; `resolve()` called from `BoatArea._resolve_highlights()` for stations with empty `highlight_target`. `rounded_rect`/`circle` used by gear, `HatHook`, `ShipCompanion`, `HarbourDressing`, `Interactable`.
- **Invariants:** Priority: group provider in the same area -> nearest named fixture within 90 -> empty (station area). Never changes interaction ranges.
- **Tests:** `tests/suites/test_navigation_views.gd`.
- **Change risks:** `FIXTURES` names are shared with BoatArea (`FIXTURES[&"provisions"]` for the stove) and vessel scenes.

### `src/interaction/interactable.gd`

- **Role:** class_name `Interactable`, extends Area2D; a station on physics layer 3 that emits `interacted` and draws its focus highlight.
- **Depends on:** `HighlightResolver.rounded_rect`.
- **Signals:** `interacted(interactable, actor)` emitted by `interact()` when `enabled`.
- **State:** Exports `interaction_id`, `prompt`, `message`, `enabled`, `focus_priority`, `highlight_target`; `highlight_outline`; static `debug_show_areas` (set by App's F8 dev view) and `light_compensation` (written by BoatLighting).
- **Lifecycle:** Placed in vessel scenes (`Layout/Stations`) and created at runtime by BoatArea (`_add_station`, GoAshore), `ShipCompanion`, harbour code.
- **Performance:** `_process` only while focused or debug view on.
- **Invariants:** Owns no behaviour; owner routes by `interaction_id`. `collision_layer = 1 << 2`, monitorable, not monitoring.
- **Tests:** Many: `tests/suites/test_gameplay_flow.gd`, `test_galley_and_anchor.gd`, `test_navigation_views.gd`, `test_hat.gd`, `test_fishing.gd`, `test_upkeep_ui.gd`, `test_lighting.gd`, `test_cozy_polish.gd`, `test_vessels.gd`, others.
- **Change risks:** Layer constant shared with InteractionSensor mask; non-empty `highlight_target` switches to tinting instead of drawn outline.

### `src/interaction/interaction_sensor.gd`

- **Role:** class_name `InteractionSensor`, extends Area2D; keeps exactly one focused Interactable for its owner.
- **Depends on:** `Interactable`; owner's optional `get_facing()`.
- **Signals:** `focus_changed(interactable)` emitted on focus change (re-emitted by `Player.focus_changed`).
- **State:** `focused`.
- **Lifecycle:** Child of `src/player/player.tscn` (reach circle radius 46).
- **Performance:** `_update_focus` every physics frame over overlapping areas.
- **Invariants:** `choose()` deterministic: distance minus `focus_priority * 60`, margin dropped for negative priority when faced (cos ≥ 0.7), ties (±0.5) by node name. `interact()` re-evaluates focus first, so prompt == action.
- **Tests:** `tests/suites/test_gameplay_flow.gd`, `tests/suites/test_upkeep_ui.gd`, `tests/suites/test_hat.gd`.
- **Change risks:** Changing margin/facing logic changes which of station vs companion wins (pet vs station tests).

### `src/player/player.gd`

- **Role:** class_name `Player`, extends CharacterBody2D; keyboard-moved captain with collision and interaction.
- **Depends on:** `InteractionSensor` (`$InteractionSensor`), `PlayerHat`, `SailorDrawing`, `HatState.CARRIED`, `GameSession` (`coffee_changed`, `state_replaced`, `is_carrying_coffee`), Input actions `move_*`, `interact`.
- **Signals:** `focus_changed(interactable)` (forwarded from sensor; BoatArea emits `interaction_prompt_changed`).
- **State:** `speed` 250, `input_enabled`, `view_rotation` (set by BoatArea from camera each physics frame), `_facing`, walk phase/amount. Group `player`.
- **Lifecycle:** Scene `src/player/player.tscn` (body radius 20, layer 2, mask 1), instanced as `Player` in every boat scene; adds "PlayerHat" child at ready.
- **Invariants:** Movement rotated by `view_rotation` so keys are screen-relative; walk animation never affects movement/collision. Input ignored when paused (unhandled input) or disabled.
- **Tests:** `tests/suites/test_vessels.gd` (by class); used via `area.player` in many suites (e.g. `test_gameplay_flow.gd`, `test_harbour_life.gd`, `test_catamaran_cabin.gd`, `test_eight_directions.gd`).
- **Change risks:** `RADIUS` mirrors the scene's collision; `get_carry_point`/`get_facing` used by hat and sensor.

### `src/player/sailor_drawing.gd`

- **Role:** class_name `SailorDrawing`, extends RefCounted; static top-down drawing of the captain (0.100b).
- **Depends on:** `CoffeeMug.draw_mug`.
- **State:** None.
- **Lifecycle:** Static helper called from `Player._draw` and `Player.get_carry_point`.
- **Invariants:** Deterministic in (facing, swing, carrying, mug); head centre at origin (PlayerHat draws there).
- **Tests:** `tests/suites/test_living_world.gd`.
- **Change risks:** Moving the head off origin misplaces the hat; `hand_position` is the hat carry point.

### `src/vessels/vessel_catalog.gd`

- **Role:** class_name `VesselCatalog`, extends Resource; ordered list of `VesselDefinition`s with starter fallback.
- **Depends on:** `VesselDefinition`; `data/vessels/vessel_catalog.tres`.
- **State:** Static `_default` cache; `vessels`.
- **Lifecycle:** Resource loaded lazily by `get_default()`; `clear_default()` called by GameSession. Used by GameSession, SaveManager (fallback id), SessionState (default `vessel_id`), App, BoatyardMenu, CaptainsLogMenu, LoadingScreen (preload step), `tools/vessels/render_art_templates.gd`.
- **Persistence:** `STARTER_ID` `&"arctic_wanderer_26"` is the default/fallback vessel id in saves.
- **Tests:** `tests/suites/test_vessels.gd` and many others that read it (`test_galley_and_anchor.gd`, `test_fishing.gd`, `test_long_passage.gd`, `test_weather.gd`, `test_upkeep.gd`, …).
- **Change risks:** `get_starter()` falls back to `vessels[0]`; reordering changes boatyard order; changing `STARTER_ID` changes the migration fallback.

### `src/vessels/vessel_definition.gd`

- **Role:** class_name `VesselDefinition`, extends Resource; pure data per boat (one `.tres` in `data/vessels/`). I022: `@export var price := 0` (euros; data: Arctic Wanderer 6,000, Wing 14,000, Frogleap 22,000, Clam 32,000); the old "Guide price" spec was removed.
- **Depends on:** `VesselProfile` (performance), `VesselVisualProfile`, `SettingsManager` (`get_art_style`, `ART_ILLUSTRATED`), `SessionState.AREA_INTERIOR`, `Loc`.
- **State:** `id`, `display_name`, `hull_type` (+ `HULL_*` constants), `description`, `specs`, `performance`, `deck_scene`, `cabin_scene`, `deck_visual_scene`, `visual_profile`, `illustrated_visual_profile`, `passage_stores_days` (14–60).
- **Lifecycle:** Resource in `VesselCatalog.vessels`; read via `GameSession.get_vessel_definition()`.
- **Persistence:** Saves store only `id`; it must never change once released.
- **Tests:** None found by class name; covered indirectly via `GameSession.get_vessel_definition()` in `tests/suites/test_vessels.gd`, `test_visual_prototype.gd`, `test_life_aboard.gd` and others.
- **Change risks:** `get_area_scene` is how App loads deck/cabin; `validate()` problems are localised strings.

### `src/water/water_life.gd`

- **Role:** class_name `WaterLife`, extends Node2D; cosmetic animated water on decks (0.100b; sea drifters Cozy Polish).
- **Depends on:** `BoatArea` (`mooring/Pontoon`, `Visual/HullBase` polygons, `get_view_heading`), `GameSession` (`is_underway`, `is_active`, `get_location_id`, `get_vessel_speed_kn`), `Simulation.get_weather_at_vessel`, `HarbourArt.for_port`, `PortCatalog` (`island`, `importance`), `SettingsManager.get_art_style`.
- **State:** Fixed pools (`MAX_WAVES` 70, `WAVELETS` 34, `MAX_RINGS` 8, `MAX_DRIFTERS` 6, `SEA_DRIFTERS` 16), wind/boat speed, atmosphere, view rect, lap points; RNG seed 2024.
- **Lifecycle:** Created by `BoatArea._setup_water_life()` under `Surroundings` after `Water` (decks with water); `refresh()` on arrival and art-style change.
- **Performance:** Per-frame update and draw while visible; strokes batched per line width into `draw_multiline_colors`; wind read every 0.5 s; nothing accumulates.
- **Invariants:** Visible only with illustrated art (toggles sibling `Ripple*` Line2Ds the other way). Real-time, own seed; reads game, never writes. Respawned sea drifters avoid the hull beam band.
- **Tests:** `tests/suites/test_living_world.gd`, `tests/suites/test_cozy_polish.gd`, `tests/suites/test_harbour_life.gd`.
- **Change risks:** `atmosphere_for` is referenced in HarbourArt's documentation (indirect); frame-time sensitive (draw call count).

### `src/world/day_night_watch.gd`

- **Role:** class_name `DayNightWatch`, extends Node; detects dawn/dusk crossings in continuous play and asks App to pass the twilight under a date card (The Well-Run Ship).
- **Depends on:** `Daylight.sun_elevation`, `GameSession` (`is_active`, `get_game_time`, `get_vessel_position`, `is_asleep`, `state_replaced`, `session_started`), `Simulation.is_passage_running`, `TimePassage.is_shown`, `app` (`play_new_light`, `can_show_time_passage`).
- **Signals:** Connects `GameSession.state_replaced`, `session_started` -> `forget`.
- **State:** `_last_time`, `_last_elevation`.
- **Lifecycle:** Created by `App` ("DayNightWatch", `app = self`); `PROCESS_MODE_PAUSABLE`.
- **Performance:** One elevation per frame; `twilight_end` loops in 60 s steps up to 2 h (≤ 120 iterations) only on a crossing.
- **Invariants:** Thresholds `NIGHT_BELOW` −6°, `DAY_ABOVE` 4° match UiTheme. Gaps > 1800 game s or backwards time are jumps, never crossings. Twilight longer than `MAX_SKIP_SECONDS` -> no card.
- **Tests:** `tests/suites/test_well_run_ship.gd`.
- **Change risks:** Threshold drift from UiTheme makes UI and card disagree; `can_show()` gates prevent cards during menus/Long Passage.

### `src/world/daylight.gd`

- **Role:** class_name `Daylight`, extends RefCounted; static approximate sun model and light colours (Iteration 17/18).
- **Depends on:** None.
- **State:** None; `OUTSIDE` colour ramp, phase constants.
- **Lifecycle:** Static helper used by `BoatLighting`, `DayNightWatch`, `UiTheme`, `MusicDirector`.
- **Invariants:** Pure and deterministic in (geo, unix_time); local solar time = UTC + lon/15; declination −23.44°·cos(2π(doy+10)/365); phases night < −6°, day > 6°; `daylight()` = smoothstep(−8, 10, elevation).
- **Tests:** `tests/suites/test_lighting.gd`, `tests/suites/test_well_run_ship.gd`.
- **Change risks:** Affects lighting, UI day/night theme, music and dawn/dusk cards at once; `inside_colour` night luminance tuned (~0.36) to keep corners off black.

## Life aboard and ashore (companion, fishing, galley, hat, harbour, sailing, boat care, anchor, audio, art, dev)

### `src/anchor/anchor_site.gd`

- **Role:** class_name `AnchorSite`, extends RefCounted; static anchorage evaluator: reachability, depth suitability (normal vs Magic Anchor), shelter by fetch, and the holding model.
- **Depends on:** `CoastalGeography.get_default()` (`is_water`, `is_clear`, `approach`, `fetch_nm`, `shore_distance_nm`), `DepthService.get_default().sample` / `describe_depth`, `WindField.Sample`, `WeatherSample` (gust), `AnchorState.HOLDING_*`, `Loc`.
- **State:** none; all static. `evaluate()` returns a Dictionary with keys class, ok, kind, reason, land_nm, fetch_nm, shelter, water, reachable, depth_m, depth_source, depth_label, normal_ok, magic_ok, offshore, approach.
- **Lifecycle:** static helper; called from `GameSession`, `App`, `WorldMap`, `AnchorageLayer`, `CoastalGeography`, `AnchorMenu`, `FishingMenu`, `Hud`, `AboardBadge`.
- **Performance:** `at_boat=false` adds an approach search (`coast.approach`); `shelter_at` is the cheap path for recurring anchor checks; offshore (>= `COASTAL_NM`) skips the fetch scan.
- **Invariants:** the three questions (reachable / depth / shelter) stay separate; the holding model has no depth term (Magic Anchor uses it unchanged); `MIN_DEPTH_M`..`NORMAL_MAX_DEPTH_M` for the normal anchor, wind limits `MAX_ANCHORING_WIND_KN` (34) / `MAX_MAGIC_WIND_KN` (55); gust = max(speed, 0.8·gust) scaled by `EXPOSURE[shelter]`.
- **Tests:** `tests/suites/test_anchorage.gd`, `test_anchorage_overlay.gd`, `test_anchor_life.gd`, `test_magic_anchor.gd`, `test_coastal_depth.gd`, `test_galley_and_anchor.gd`, `test_regions.gd`, `test_denmark_views.gd`, `test_boat_care.gd`, `test_catch_and_cove_journey.gd`, `test_joy_journey.gd`.
- **Change risks:** `describe_for_chart` branches on `reason.begins_with("Too close")`, but `reason` is already passed through `Loc.t`, so in a translated locale a too-close spot likely falls through to the "No safe approach" text; tuning constants shifts which coves are good and when anchors drag; result keys are read by many UI callers.

### `src/anchor/magic_anchor_deployment.gd`

- **Role:** class_name `MagicAnchorDeployment`, extends RefCounted; rules for the Magic Anchor timing mini-game around a shared `TimingCheck`.
- **Depends on:** `TimingCheck` (RESULT_LANDED / RESULT_ESCAPED, `perfects`, `checks_needed`, `line_control`). Number of checks comes from the caller (`GameSession.magic_anchor_checks`, indirect); success handed to `GameSession.drop_magic_anchor` by `AnchorMenu` (indirect).
- **State:** `check: TimingCheck`, `attempts` (each `start()` increments and offsets the seed).
- **Lifecycle:** instantiated by `src/ui/anchor_menu.gd` per deployment.
- **Invariants:** arc 70/58/48° for 1/2/≥3 checks; `MISSES_ALLOWED` = 3 via `line_control`; `MISS_MINUTES` = 5 game minutes per miss (applied by caller); `set_quality()` in [0.6, 1.0] = 0.6 + 0.4·perfects/checks; no randomness beyond the seeded arc placement.
- **Tests:** `tests/suites/test_magic_anchor.gd` (also `tests/restart_105b.gd`).
- **Change risks:** reusing `line_control` as the miss budget couples it to `TimingCheck` semantics; changing `set_quality` shifts holding via `AnchorState.MAGIC_BONUS_MAX_KN` (indirect).

### `src/art/artwork_resolver.gd`

- **Role:** class_name `ArtworkResolver`, extends RefCounted; Sprite Workshop loader that swaps procedural/built-in art for validated PNGs listed in `art_replacements/**/manifest.csv`.
- **Depends on:** `DirAccess`, `FileAccess` (CSV), `ResourceLoader`/`load`, `Image.load_from_file`, `ImageTexture`, `ProjectSettings.globalize_path`, `Loc`.
- **State:** static vars `root` (overridable by tests), `_entries` (asset_id → row + "folder"/"path"), `_indexed`, `_cache` (asset_id → Texture2D or null), `_warnings`, `_warned`, `loads` counter.
- **Lifecycle:** static helper; callers include `HatArt`, `FishArt`, `CompanionVisualSet`, `VesselVisual`, `SolarPanels`, `AnchorSignals`; `tests/helpers/art_fixtures.gd`.
- **Performance:** manifests indexed once (recursive, sorted), each asset resolved once and cached (including negative results); `loads` lets tests assert no per-frame loading.
- **Invariants:** only `integration_status == READY` rows resolve; PNG only; aspect within 2% of `source_width_2x:source_height_2x`, scale 0.5–4.0× of the 2x size; first duplicate asset_id / output path wins; failures warn once (`push_warning` + `get_warnings()`) and fall back, never error; no hot reload (`reload()` for tests).
- **Tests:** `tests/suites/test_sprite_workshop.gd` (also `tests/restart_105b.gd`, `tests/screenshots_105b.gd`).
- **Change risks:** `REQUIRED_FIELDS` must match the manifest headers or a whole manifest is skipped; cache must be cleared (`reload()`) between tests that change `root`.

### `src/audio/audio_manager.gd`

- **Role:** no class_name; extends Node; autoload `AudioManager`. Bus-aware playback service for music, ambience, named loops and pooled one-shots; owns no gameplay state.
- **Depends on:** Godot audio only (`AudioStreamPlayer`, tweens). Buses `Music`, `Ambience`, `SFX`, `UI` (constants); loops may target other buses (e.g. `WeatherAudio.OUTSIDE_BUS`).
- **Signals:** connects each player's `finished` to re-play when looping is requested (looping done here, not on the stream resource).
- **State:** `_music`, `_ambience`, `_one_shots` (8, round-robin), `_loops` (id → {player, target_db, tween, stopping}).
- **Lifecycle:** autoload (project.godot), `process_mode = ALWAYS` so sound continues while paused.
- **Performance:** players created once and reused; when all one-shot players are busy the oldest-started is reused.
- **Invariants:** `play_loop` with the same stream already playing only fades (never restarts); `play_ambience` with the current stream is a no-op; null stream stops the loop/ambience.
- **Tests:** `tests/suites/test_settings_and_audio.gd`, `test_atmosphere.gd`, `test_soundtrack.gd`, `test_presentation.gd`, `test_sailing_presentation.gd`, `test_life_aboard.gd`, `test_companion_art.gd`, `test_vessels.gd`.
- **Change risks:** `SILENT_DB` (-60) is the "off" sentinel for loop state; `stop_all()` assumes every child is an `AudioStreamPlayer`; bus names must match the bus layout and `SettingsManager.AUDIO_BUSES`.

### `src/audio/music_director.gd`

- **Role:** no class_name; extends Node; autoload `MusicDirector`. Chooses among three music tracks (home / sailing / night) and crossfades between them.
- **Depends on:** `GameSession` (`is_active`, `get_vessel_position`, `get_game_time`, `is_underway`, `is_anchored`, `is_holding_at_anchorage`, `get_boat_area`), `SessionState.AREA_EXTERIOR`, `Daylight.sun_elevation`, `Simulation.passage_rate`, `AudioManager.BUS_MUSIC`; assets `res://assets/audio/music/*.ogg` plus `.json` sidecars (`phrases`, `loop_seconds`).
- **Signals:** `track_changed(track)` emitted when a crossfade to another piece starts.
- **State:** one `AudioStreamPlayer` per track, `_current`, `_candidate`, timers, night hysteresis flag `_night`, `_changes` counter; tunables `settle_seconds`, `min_stay_seconds`, `crossfade_seconds`, `enabled` (false with user arg `--no-music`).
- **Lifecycle:** autoload, `process_mode = ALWAYS`; read by `src/ui/settings_menu.gd` (`is_playing`).
- **Performance:** context checked every 0.5 s (`CHECK_SECONDS`); muted Music bus pauses all players.
- **Invariants:** night below -4° sun, day again above -1° (hysteresis); change only after `SETTLE` (3 s) of a stable candidate and ≥ `MIN_STAY` (25 s) since the last change; day/night changes suppressed while `Simulation.passage_rate > 0`; left tracks are paused (not stopped) and resume at the phrase start ≤ playback position.
- **Tests:** `tests/suites/test_soundtrack.gd`.
- **Change risks:** removing the hysteresis or passage-rate guard causes flapping; sidecar phrase data must match the audio files.

### `src/audio/weather_audio.gd`

- **Role:** class_name `WeatherAudio`, extends Node; weather soundscape (wind/water/rain/storm loops), lightning flashes and delayed thunder, plus below-deck muffling on the `Outside` bus. I022: `WIND_BUS` (&"Wind", sends to `Outside`); `_loop(..., bus := OUTSIDE_BUS)` takes the bus; `WIND_LOOP` and `STORM_LOOP` use `WIND_BUS`, water and rain stay on `OUTSIDE_BUS` (thunder one-shots too).
- **Depends on:** `AudioManager` (`play_loop`, `stop_loop`, `play_one_shot`), `GameSession` (`get_vessel_speed_kn`, `get_vessel_position`, `get_game_time`), `WeatherSample`, `WeatherModel.CLASS_*`, `WeatherEvent` (`offset_nm`, `radius_nm`), `SettingsManager.get_reduce_flashing`, `BoatLighting.flash` via `lighting_provider` Callable; preloaded WAVs in `res://assets/audio/weather/` and `placeholder/storm_wind.wav`.
- **State:** `place` ("deck" / "inside" / ""), muffle level, strike/thunder timers, pending `_flashes`, `levels` dict and `strikes` counter (tests/diagnostics); `_rng` is cosmetic only.
- **Lifecycle:** instanced by `src/app/app.gd`, which calls `update(here, place, underway, storms)` once per real second; `PROCESS_MODE_PAUSABLE`.
- **Performance:** loop levels once a second; `_process` only advances timers and the low-pass cutoff.
- **Invariants:** static `rain_level(sample)` is the single rain rule (also used by `WeatherVisuals` and `GameSession`'s companion-on-deck check); storms beyond `STORM_RANGE_NM` (25 nm) are ignored; SFX/UI buses are never filtered; reduce-flashing gives one soft flash.
- **Tests:** `tests/suites/test_atmosphere.gd`.
- **Change risks:** bus effect index 0 on `Outside` is assumed to be an `AudioEffectLowPassFilter`; changing `rain_level` changes visuals and companion behaviour too; `App.STORM_LOOP` aliases `STORM_LOOP`.

### `src/boat_care/boat_care.gd`

- **Role:** class_name `BoatCare`, extends RefCounted; static rules for wear levels (hull/fouling, rig, engine, equipment), speed/damage effects, service quotes and care wording.
- **Depends on:** `BoatCareState` (`hull_cleaned_at`, `rig_wear`, `engine_hours`, `upgrades`, `has_upgrade`), `VesselCondition` (`band_of`, `describe`, `FULL`), `PortCatalog.get_default().get_display_name`, `GameSession.format_money`, `Loc`; data `res://data/boat/equipment.json` (`upgrades[]` with `id`, `name`, `price_per_ft`).
- **State:** static `_upgrades` cache (loaded once, never reset). Otherwise pure functions of `(care, condition, now, length_ft)`.
- **Lifecycle:** static helper; used by `GameSession`, `BoatCareState`, `App`, `PassageReadiness` and UI (`BoatCareMenu`, `BoatCareView`, `BoatyardMenu`, `ChandleryMenu`, `SailmakerMenu`, `HaulOutPanel`, `PassagePanel`, `CaptainsLogMenu`).
- **Persistence:** none of its own; history entries it formats use `kind` values `repair`, `engine_service`, `rig_service`, `haul_out`, `upgrade:<id>`, `haul_out_extra:<id>` (stored by the care state).
- **Invariants:** levels ordered by `LEVELS`; hull level = worse of fouling and condition band; speed loss bounded (fouling ≤ 6 %, rig ≤ 5 %, engine ≤ 10 %); `effects()` returns {sail, engine, damage}, damage ≤ 1.3 (× 0.9 with stainless rigging); prices scale by `size_factor` = max(length,10)/30, haul-out by length directly.
- **Tests:** `tests/suites/test_boat_care.gd`, `test_upkeep.gd`, `test_upkeep_ui.gd`, `test_boat_of_your_own.gd`, `test_living.gd`, `test_solar_panels.gd`.
- **Change risks:** `PassageReadiness` calls the private `_level` directly; upgrade ids (`hard_antifouling`, `stainless_rigging`) are string literals that must match `equipment.json`; tuning shifts sailing speed globally.

### `src/boat_care/passage_readiness.gd`

- **Role:** class_name `PassageReadiness`, extends RefCounted; advisory pre-departure assessment of a planned path (never blocks departure).
- **Depends on:** `GameSession` (`get_vessel_definition`, `get_base_vessel_profile`, `get_condition`, `get_boat_care`, `get_game_time`, `get_provisions`, `get_passage_store_days`), `Simulation` (`estimate_route_seconds`, `route_hazards`, `describe_when`, `format_duration`), `GeoMath.path_length_nm`, `BoatCare` (incl. private `_level`), `VesselCondition`, `WeatherModel.HAZARD_*`, `Provisions.format_days`, `Loc`.
- **State:** none; `assess(path)` returns {level, summary, items[{topic, level, text}], hours, nm}; `describe(result, max_lines)` formats it.
- **Lifecycle:** static helper; called from `App`, `WorldMap`, `VoyageDaydream`.
- **Invariants:** levels OK(0) < NOTE(1) < CONSIDER(2), overall = max of items; forecast consulted for at most `FORECAST_HOURS` (24) and the result says so beyond it; stores need passage days + 1 margin (NOTE under +2).
- **Tests:** `tests/suites/test_boat_care.gd`, `test_long_passage.gd`, `test_world_voyage.gd`.
- **Change risks:** `SUMMARIES` strings are not passed through `Loc` here (callers must translate if needed); item `topic` strings may be matched by tests; `route_hazards` cost grows with path length.

### `src/companion/companion_pose_art.gd`

- **Role:** class_name `CompanionPoseArt`, extends Resource; one pose entry (pose name, `image_path`, `offset`, `scale`, `flip_h`) of a `CompanionVisualSet`.
- **Depends on:** nothing (pure data).
- **Lifecycle:** Resource, embedded in `data/companions/*_visuals.tres`; read by `CompanionVisualSet` and `ShipCompanion._draw_pose_texture` (flip).
- **Invariants:** `image_path` is a path (not a preloaded texture) so a missing PNG never fails loading the set.
- **Tests:** indirectly via `tests/suites/test_companion_art.gd`, `test_sprite_workshop.gd` (no direct reference found).
- **Change risks:** renaming exported properties breaks the existing `.tres` files.

### `src/companion/companion_remarks.gd`

- **Role:** class_name `CompanionRemarks`, extends RefCounted; static catalogue and selection of petting remarks (Engine Room & companion polish).
- **Depends on:** `CompanionState` (`KINDS`, `kind`; optional `name`/`gender` read with `"name" in companion`), `Loc.t`.
- **State:** none. `identity(companion)` → `{kind, name, gender}` read from the authoritative `CompanionState` (fields it lacks are empty: today only `kind` exists).
- **Lifecycle:** static helper; called by `ShipCompanion.take_remark()` and `BoatArea._on_interacted` (hands full).
- **Invariants:** `lines(who)` is ordered and deterministic; `remark(who, turn)` returns line `turn mod n`, so consecutive turns differ (every list has ≥ 2 lines); English line = msgid, translated at call time (a language switch applies to the next remark); a name is inserted with `%` unchanged; no line names a specific animal.
- **Tests:** `tests/suites/test_companion_remarks.gd`.
- **Change risks:** new lines must be added to `locale/da.po` (`tools/i18n/check.py`); a list with one line would repeat; the `%s` lines must only be used when a name exists (`lines()` chooses `NAMED` only then).

### `src/companion/companion_state.gd`

- **Role:** class_name `CompanionState`, extends RefCounted; saved companion data (kind, cabin spot, deterministic move schedule, cabin/deck area and deck spot).
- **Depends on:** nothing beyond built-ins (`hash`). Spot ids correspond to `Layout/CompanionSpots` markers in cabin scenes (indirect); `deck_spot` indexes `DeckCompanionSpots` (indirect).
- **State:** `kind`, `spot`, `next_move_time`, `moves`, `area` (`cabin`/`deck`), `deck_spot` (0..2).
- **Lifecycle:** owned by `SessionState.companion`; mutated only through `GameSession` (`advance_to` called from `GameSession` each time step; area changes via `set_companion_area`); read by `ShipCompanion`, `AnchorLife`, `App`, `NewGameMenu`.
- **Persistence:** `to_dict`/`from_dict` keys `kind`, `spot`, `next_move_time`, `moves`, `area`, `deck_spot`; `area`/`deck_spot` optional (default cabin / 0, clamped); invalid kind, spot or schedule returns null with an error. `SaveManager` migration v3→v4 inserts a default cat via `create()`.
- **Performance:** `advance_to` catches up at most `MAX_CATCH_UP_MOVES` (64), then reschedules from now.
- **Invariants:** deterministic in (kind, moves): spot and interval from `hash("kind:n")`; intervals 2–5 game hours rounded to whole minutes so JSON round-trips exactly; a move always goes to a different spot.
- **Tests:** `tests/suites/test_life_aboard.gd`, `test_companion_deck.gd`, `test_companion_art.gd`, `test_cozy_patch.gd`, `test_catamaran_cabin.gd`, `test_vessels.gd`, `test_hat.gd`, `test_weather.gd`, `test_upkeep.gd`, `test_upkeep_ui.gd`, `test_joy_journey.gd`, `test_sprite_workshop.gd`; restart checks `tests/restart_check.gd`, `restart_18.gd`, `restart_105b.gd`.
- **Change risks:** `hash()` of a String must stay stable across engine versions or schedules change after load; `ALL_SPOT_IDS` is documented as required by `VesselDefinition.validate()` but no code reference was found; `display_name` returns untranslated "cat"/"dog".

### `src/companion/companion_visual_set.gd`

- **Role:** class_name `CompanionVisualSet`, extends Resource; per-kind pose art, placement (`display_size`, `pivot`), loading options and idle-behaviour timings.
- **Depends on:** `CompanionPoseArt`, `ArtworkResolver.get_artwork("<workshop_id>.<pose>")`, `ResourceLoader`/`Image`; files `res://data/companions/<kind>_visuals.tres` (cat and dog exist).
- **State:** exported settings; static `_cache` of prepared textures keyed by path + loading options (workshop replacements keyed separately); `clear_cache()` for tests.
- **Lifecycle:** Resource loaded by `for_kind()` from `ShipCompanion`; `ShipCompanion.use_visual_set` overrides it in tests/tools.
- **Performance:** images downscaled to `max_texture_size` (320) once and cached; background removal is a border flood fill over the image data (load time only).
- **Invariants:** all poses share one logical canvas; background removal only when the border has no transparency, and only colour connected to the border (enclosed light areas stay); missing images warn and return null (pose falls back).
- **Tests:** `tests/suites/test_companion_art.gd`, `test_sprite_workshop.gd`, `test_cozy_patch.gd`, `test_anchor_life.gd`.
- **Change risks:** cache key omits pose-level fields, so changing art files at runtime needs `clear_cache()`; renaming exports breaks the `.tres` files.

### `src/companion/deck_companion_spots.gd`

- **Role:** class_name `DeckCompanionSpots`, extends Node2D; computes three safe deck resting places (`deck_0..2`), the `deck_entry` point and aboard-only walking paths for the deck companion.
- **Depends on:** `BoatArea` (`walkable_bounds`, nodes `Layout/Collision/Lifeline/CollisionPolygon2D`, `Layout/Collision` `BoatFixture` children with `solid`, `Layout/Stations/Helm`, `Layout/Stations/Companionway`), `Interactable` (station positions), `Geometry2D`.
- **State:** `area`, lifeline polygon `_aboard`, grown fixture outlines `_fixtures`, child `Marker2D`s, lazily built BFS grid `_grid`.
- **Lifecycle:** created by `BoatArea._setup_deck_companion()` under `Layout` and `setup(self)` called; read by the deck `ShipCompanion` (`get_spot`, `get_entry`, `path`).
- **Performance:** `compute_spots`/`nearest_safe` scan the walkable bounds on an 8-unit grid calling `is_safe` (once at setup); the path grid is built once on first non-straight `path()`; `_line_ok` samples every 3 units.
- **Invariants:** a place is safe if the whole body disc (`BODY_RADIUS` + margin) is inside the lifeline and outside solid fixtures; resting places also keep `HELM_CLEARANCE` (85) and `STATION_CLEARANCE` (55); planning uses `PLAN_MARGIN` beyond `is_safe`; diagonal steps never cut corners.
- **Tests:** `tests/suites/test_companion_deck.gd`, `test_cozy_patch.gd`, `test_solar_panels.gd`.
- **Change risks:** depends on node names in every vessel's deck layout; without a lifeline polygon `is_aboard` only checks bounds; if no path is found it returns a straight line (could cross fixtures).

### `src/companion/ship_companion.gd`

- **Role:** class_name `ShipCompanion`, extends Node2D; presentation of the cat/dog in the cabin or on deck: pose sprites or procedural drawing, petting, walking between areas, highlight outline.
- **Depends on:** `GameSession` (`get_companion`, `note_companion_petted`, `is_settled_at_anchor`), `CompanionState`, `CompanionVisualSet`, `DeckCompanionSpots`, `AudioManager.play_sfx`, `Interactable`, `HighlightResolver`, `SessionLog.write`, `Loc`; preloads `assets/audio/placeholder/companion_purr.wav`, `companion_dog_pant.wav`.
- **Remarks:** `take_remark()` returns `CompanionRemarks.remark(identity, turn)` or "" within `REMARK_COOLDOWN_MS` (15 s, real time, `Time.get_ticks_msec`); static `_remark_turn`/`_last_remark_ms` are shared by all companion nodes in the run (not saved); `reset_remark_cooldown()` for tests.
- **Signals:** declares `petted(kind)` (on `pet()`), `pose_changed(pose)`, `settled_changed(settled)`; connects `GameSession.companion_area_changed`, `companion_moved`, `state_replaced`, `anchor_life_changed`.
- **State:** presentation only (pose, timers, walk path, `settled`, `on_deck`); reads but never writes `CompanionState` (petting goes through `GameSession`). Static `_hulls` silhouette cache per texture.
- **Lifecycle:** instanced in each vessel's `cabin.tscn` and `NewGameMenu` (`preview = true`, no session); deck instance created by `BoatArea._setup_deck_companion()` with `on_deck`, `deck_spots`, `spots_path`.
- **Performance:** `queue_redraw()` every frame; walking is a glide along a precomputed path (no per-frame pathfinding); silhouettes cached.
- **Invariants:** exactly one cabin companion per cabin scene; visible only in the area matching `CompanionState.area`; sprite mode requires a `resting` texture, else procedural fallback; idle RNG is cosmetic (seeded from kind + spot).
- **Tests:** `tests/suites/test_life_aboard.gd`, `test_companion_art.gd`, `test_companion_deck.gd`, `test_companion_remarks.gd`, `test_cozy_patch.gd`, `test_anchor_life.gd`, `test_catamaran_cabin.gd`, `test_hat.gd`, `test_sprite_workshop.gd`, `test_upkeep_ui.gd`, `test_vessels.gd`.
- **Change risks:** `_sync` dereferences `interactable` (null in preview mode, which never calls it); the deck instance's `Pet` interactable must be connected by `BoatArea` after creation; missing spot markers only warn and keep the current position.

### `src/dev/dev_guides.gd`

- **Role:** class_name `DevGuides`, extends RefCounted; lists and reads the Markdown guides in `res://DEV_GUIDES` for the in-game viewer.
- **Depends on:** `DirAccess`, `FileAccess`, `OS.is_debug_build`.
- **State:** static `guides_dir` (default `res://DEV_GUIDES`; tests override).
- **Lifecycle:** static helper; used by `MainMenu` (button visibility), `DevGuidesMenu` (`list_guides`, `read`, `title_of`), `App` (`is_available`).
- **Invariants:** `README.md` sorts first, others by natural case-insensitive order; available only in debug builds with at least one `.md` file; the Markdown files are the only source.
- **Tests:** `tests/suites/test_dev_guides.gd`.
- **Change risks:** `list_guides()` reads every file to get titles (fine for a small folder); exported builds lack the files by design.

### `src/dev/dev_test_panel.gd`

- **Role:** class_name `DevTestPanel`, extends `ModalPanel`; developer-only modal with weather/condition/rescue/provisions/time buttons and a live status label.
- **Depends on:** `DevTools` (scenarios, `set_condition`, `prepare_rescue`, `set_provisions`, `advance_hours`, `describe_weather_here`), `GameSession`, `Provisions`, `VesselCondition`, `Simulation.format_game_time`, `ModalPanel.notify`/`close`.
- **State:** `_status` label, `_buttons` by node name (`get_button` for tests).
- **Lifecycle:** created by `App` (F10, `modals.push(DevTestPanel.new())`) and via the pause menu, only when `DevTools.is_enabled()`.
- **Performance:** `refresh()` every frame while visible (string formatting only).
- **Invariants:** strings are deliberately English-only (developer tool, no `Loc`); every button also triggers `refresh`.
- **Tests:** `tests/suites/test_upkeep_ui.gd`.
- **Change risks:** button node names (`Gale`, `Condition40`, `Stores0`, `CloseButton`, ...) are looked up by tests.

### `src/dev/dev_tools.gd`

- **Role:** class_name `DevTools`, extends RefCounted; developer-only test actions (weather scenarios, condition, provisions, rescue, time advance).
- **Depends on:** `WeatherFixtures` (`gale`, `thunderstorm`, `use`, `clear`), `WeatherEvent`, `GameSession` (`is_active`, `get_vessel_position`, `get_game_time`, `get_voyage`, `is_underway`, `set_condition_for_testing`, `set_provisions_for_testing`), `GeoMath` (`point_along`, `cumulative_distances`), `Simulation` (`advance`, `get_weather_at_vessel`).
- **Signals:** none declared; `App` connects `GameSession.session_started`, `state_replaced`, `session_ended` to `on_session_changed`.
- **State:** static `scenario` (active SCENARIO_*), static `force_enabled` (tests: null = auto).
- **Lifecycle:** static helper; used by `App`, `DevTestPanel`, `PauseMenu`; `GameSession` hosts the `*_for_testing` setters.
- **Persistence:** test weather is never saved; cleared on session start/load/end.
- **Invariants:** enabled only for debug + `editor` feature and without user arg `--no-dev-tools`; scenarios are deterministic for the same state; `develop_fraction` capped so test weather is at full strength at once; `prepare_rescue` sets 1 % then a storm so the real damage/rescue path runs.
- **Tests:** `tests/suites/test_boat_care.gd`, `test_upkeep_ui.gd`.
- **Change risks:** forgetting `restore_normal_weather` leaves `WeatherModel.generated_enabled`/fixtures altered; `advance_hours` runs the full simulation (can be slow for 24 h).

### `src/dev/weather_fixtures.gd`

- **Role:** class_name `WeatherFixtures`, extends RefCounted; builds deterministic `WeatherEvent`s (gale, thunderstorm, thunder risk, cyclone) and installs them as `WeatherModel.fixture_events`.
- **Depends on:** `WeatherModel.get_default()` (`fixture_events`, `generated_enabled`, `clear_cache`), `WeatherEvent` (KIND_* and fields), `Simulation.invalidate_estimates`.
- **State:** none of its own; mutates the shared `WeatherModel`.
- **Lifecycle:** static helper for tests and `DevTools`; never used by normal gameplay.
- **Invariants:** `use(events, generated=false)` replaces fixtures and by default disables generated weather; `clear()` restores generated weather; both clear the model cache and route estimates; event seed = `hash(id)`; fixtures > 48 h develop/dissipate almost at once.
- **Tests:** used by many suites, e.g. `tests/suites/test_weather.gd`, `test_weather_ui.gd`, `test_atmosphere.gd`, `test_sailing.gd`, `test_sailing_correctness.gd`, `test_simulation.gd`, `test_upkeep.gd`, `test_upkeep_ui.gd`, `test_hat.gd`, `test_life_aboard.gd`, `test_living.gd`, `test_captains_log.gd`, `test_gameplay_flow.gd`, `test_objectives.gd`, `test_publishing.gd`, `test_secret_achievements.gd`, `test_voyage_persistence.gd`; also `tests/screenshots_17.gd`.
- **Change risks:** suites that forget `clear()` leak fixtures into later suites; changing defaults (shape, display names, develop fractions) shifts many test expectations.

### `src/fishing/fish_art.gd`

- **Role:** class_name `FishArt`, extends RefCounted; resolves fish/shark/junk picture layers and metadata.
- **Depends on:** `res://data/fishing/fish_art.json` (`art` → id → {canvas, kind, tail_pivot, eye}), textures `res://assets/fishing/<id>/<layer>.png`, `ArtworkResolver.get_artwork("fish.<id>.<layer>", original)`.
- **State:** static `_meta`, `_loaded` (loaded once; error pushed if invalid).
- **Lifecycle:** static helper; used by `FishPortrait`, `FishingMenu`, `TrophyMenu`, `TrophyBoard`.
- **Invariants:** layers `body`, `tail`, `lid` for animated kinds, `art` for junk, `thumb` for every catch; `is_animated` = kind != "junk"; replacements share the same canvas. Art is painted by `tools/fishing/paint_fish.py` (per the file's notes).
- **Tests:** `tests/suites/test_fishing2.gd`, `test_cozy_patch.gd`, `test_sprite_workshop.gd`.
- **Change risks:** `layer()` calls `load()` on each call (relying on Godot's resource cache); ids must match `fishing.json` species/junk ids.

### `src/fishing/fish_portrait.gd`

- **Role:** class_name `FishPortrait`, extends Control; large animated catch portrait (blink, tail flick, bob) built from `FishArt` layers.
- **Depends on:** `FishArt` (`get_canvas`, `is_animated`, `layer`, `get_tail_pivot`), `SettingsManager.get_reduce_motion`.
- **State:** `species_id`, `animated`, child `Stage` with `Tail`/`Body`/`Lid` `TextureRect`s, timers, per-instance RNG seeded from id + instance id (cosmetic).
- **Lifecycle:** instanced by `src/ui/fishing_menu.gd` (reel and result portraits); `set_species(id)` rebuilds the stage.
- **Performance:** `_process` only while visible, in tree and animated; no tweens or timers.
- **Invariants:** reduce motion keeps tail and body still but still blinks; junk is never animated.
- **Tests:** `tests/suites/test_fishing2.gd` (also `tests/screenshots_18.gd` via `pose_tail`/`force_blink`).
- **Change risks:** `advance()` assumes `_lid`/`_tail` exist when animated (guarded in `_process` only by `_tail`).

### `src/fishing/fishing_catalog.gd`

- **Role:** class_name `FishingCatalog`, extends RefCounted; singleton-style data and rules for fishing (lures, species, junk, regions, bite chance, picking, grades, reel profile, score, price, strength).
- **Depends on:** `res://data/fishing/fishing.json`; `PortCatalog.get_default()` (`ports_in_rect`), `PortData`, `GeoMath.distance_nm`, `HatStory.open_water_nm` (coastal test), `FishingState.MODE_TROLLING`, `Loc`.
- **State:** static `_default` instance holding the parsed data (`bite_chance_per_check`, `check_interval_s`, `coastal_nm`, `max_trolling_kn`, `lures`, `species`, `rarities`, `junk`, `junk_chance`).
- **Lifecycle:** lazy singleton via `get_default()`; used by `GameSession`, `Simulation`, `FishingState`, `ReelTiming` (doc only), `TrophyBoard` and UI (`FishingMenu`, `FishmongerMenu`, `GroceryMenu`, `ChandleryMenu`, `TrophyMenu`, `CatchBadge`, `AboardBadge`).
- **Performance:** `region_at` widens a port search (3°, 8°, 40° boxes); `candidates`/`suitability` loop all species; lookups by id are linear scans.
- **Invariants:** deterministic given the caller-seeded RNG; grades by relative weight only (0.35/0.6/0.8); reel checks/arc by rarity (1/72°, 2/60°, 3/50°, 4/42°; junk 1/84°); `landed_kg` never exceeds the species max and never changes species/rarity; bite chance 0 when trolling > `max_trolling_kn`, ×0.6 above 22 kn, clamped ≤ 0.6.
- **Tests:** `tests/suites/test_fishing.gd`, `test_fishing2.gd`, `test_regions.gd`, `test_cozy_patch.gd`, `test_boat_of_your_own.gd`, `test_chartroom_ui.gd`; benchmarks `tests/benchmark_18.gd`, `tests/benchmark_105b.gd`.
- **Change risks:** `rarity_label`/`grade_label` capitalize ids rather than translating (except "Ordinary"); `strength()` dereferences `fish.kg` without an empty check; changing pick order or RNG draws changes every seeded bite (tests rely on determinism).

### `src/fishing/fishing_sounds.gd`

- **Role:** class_name `FishingSounds`, extends RefCounted; static accessors for placeholder SFX streams (cast, bite, reel, splash, snap, sizzle, chain, warning) and their volume `DB` (-8).
- **Depends on:** files in `res://assets/audio/placeholder/` (generated by `tools/generate_placeholder_audio.py`, per the file's notes).
- **Lifecycle:** static helper; callers pass the streams to `AudioManager.play_sfx` (`App`, `FishingMenu`, `CookingMenu`, `AnchorMenu`).
- **Invariants:** every cue has a visible counterpart (no information by sound alone).
- **Tests:** none found.
- **Change risks:** `load()` per call (relies on the resource cache); renamed files return null silently (`play_sfx` ignores null).

### `src/fishing/reel_timing.gd`

- **Role:** class_name `ReelTiming`, extends `TimingCheck`; no members of its own: the fishing name for the shared dial (documentation of the fishing encounter rules).
- **Depends on:** `TimingCheck` (all behaviour). Checks/arc come from `FishingCatalog.reel_profile`, Perfect weight nudge from `FishingCatalog.landed_kg` (both applied by `FishingMenu`, indirect).
- **State:** inherited from `TimingCheck`.
- **Lifecycle:** created by `src/ui/fishing_menu.gd` as `ReelTiming.new(checks, arc_deg, hash("species|time"))`; drawn by `src/ui/reel_dial.gd`.
- **Invariants:** as `TimingCheck`: constant needle speed, 3 misses (`LINE_CONTROL`) or 60 s idle fails, seeded arc placement.
- **Tests:** `tests/suites/test_fishing2.gd`, `test_magic_anchor.gd`; helper `tests/helpers/reel.gd`; screenshots `tests/screenshots_18.gd`, `screenshots_chartroom.gd`.
- **Change risks:** adding fishing-specific state here is the intended extension point; changes to `TimingCheck` affect both fishing and the Magic Anchor.

### `src/galley/recipes.gd`

- **Role:** class_name `Recipes`, extends RefCounted; constant list of galley dishes and the fish-to-food-days rule.
- **Depends on:** nothing.
- **State:** const `LIST` (id, name, text, fish, groceries, per_kg, bonus, minutes, well_fed_hours); `MAX_FISH_DAYS` = 3.
- **Lifecycle:** static helper; `GameSession` (cooking: `get_recipe`, `food_gained`) and `src/ui/cooking_menu.gd`.
- **Invariants:** grocery-only dishes gain 0 food days; fish dishes gain `per_kg·kg + bonus`, capped at 3 days.
- **Tests:** recipe ids used in `tests/suites/test_galley_and_anchor.gd`, `test_world_voyage.gd`, `test_catch_and_cove_journey.gd`.
- **Change risks:** recipe ids are referenced by tests and `GameSession` lookups; `name`/`text` are English source strings (any translation happens at the caller).

### `src/harbour/harbour_art.gd`

- **Role:** class_name `HarbourArt`, extends Resource (`@tool`); optional per-harbour art: up to 3 `HarbourLandmark`s and a water `atmosphere` (auto/marina/coastal/urban).
- **Depends on:** `HarbourLandmark`; files `res://data/harbours/<port_id>.tres` (currently `copenhagen.tres`).
- **State:** exported `port_id`, `landmarks`, `atmosphere`.
- **Lifecycle:** Resource loaded by `for_port()` from `HarbourDressing.refresh()` and `src/water/water_life.gd` (atmosphere).
- **Invariants:** a file whose `port_id` does not match its name is ignored with a warning; landmarks without texture skipped; more than `MAX_LANDMARKS` (3) warned and truncated; art never affects collision, mooring or interaction.
- **Tests:** `tests/suites/test_visual_prototype.gd`, `test_living_world.gd`.
- **Change risks:** `for_port` uses `load()` per call (resource cache); renaming exports breaks `copenhagen.tres`.

### `src/harbour/harbour_dressing.gd`

- **Role:** class_name `HarbourDressing`, extends Node2D; illustrated harbour scenery (pontoon, ropes, cleats, quay with bollards/lamps, water strokes, facility signs, landmarks) over the classic mooring drawing. I021: `refresh()` takes `_art` from `HarbourLooks.get_default().art_for(port_id)` (own HarbourArt with landmarks, else the look's shared HarbourArt, else null) instead of `HarbourArt.for_port`.
- **Depends on:** `BoatArea` (`mooring_label`, `Layout/Stations` `Interactable`s with `interaction_id`, optional meta `sign_at`), mooring nodes (`Pontoon`, `*Line` Line2Ds, `Cleat*` polygons, `Plank*`, sign labels `GrocerySign`/`BoatyardSign`/`GoAshoreSign`), `SettingsManager.get_art_style`/`ART_ILLUSTRATED`, `GameSession.get_location_id`, `HarbourArt`, `HarbourLandmark`, `HighlightProvider.create`, `HighlightResolver.rounded_rect`, project theme font `DisplayHeader`.
- **State:** cached pontoon rect, lines, cleats, `_signs`, `_landmarks`, `_sign_classic` (original label text/settings for restoring Classic).
- **Lifecycle:** created by `BoatArea` under `Surroundings/Mooring` and `setup(area, mooring)` called; `refresh()` called by `BoatArea` on harbour/setting/station changes; accessed via `BoatArea.get_harbour_dressing()`.
- **Performance:** `_draw` uses a fixed-seed RNG (17) so the drawing is stable; redraw only on `queue_redraw()` from `refresh()`.
- **Invariants:** art only: toggles visibility of classic `Plank*`/`Cleat*`/`*Line` nodes but never touches collision, stations, spawns or the mooring itself; `get_lamp_positions()` must mirror `_draw_quay`'s post placement (every third post).
- **Tests:** `tests/suites/test_visual_prototype.gd`, `test_harbour_life.gd`, `test_boat_care.gd` (via `get_harbour_dressing`).
- **Change risks:** depends on mooring node naming conventions; `_sign_classic` is keyed by label name; changing post spacing in `_draw_quay` without `get_lamp_positions` misplaces night lights.

### `src/harbour/harbour_facilities.gd`

- **Role:** class_name `HarbourFacilities`, extends Resource; per-harbour services (grocery, boatyard, go_ashore, haul_out), derived trades, tier and service summaries.
- **Depends on:** `PortCatalog.get_default().get_port` (`importance`), `HarbourTrades.offered`, `Loc`; optional files `res://data/harbours/facilities/<port_id>.tres`.
- **State:** exported booleans; static `_cache` (port_id → resource or null, plus `@major` shared instance), static `_default`; `clear_cache()`.
- **Lifecycle:** Resource; `for_port()` used by `GameSession`, `App`, `BoatArea`, `WorldMap`, `HarbourTrades` and UI menus (`GoAshoreMenu`, `GroceryMenu`, `ProvisionsMenu`, `BoatyardMenu`, `BoatCareMenu`, `ChandleryMenu`, `SailmakerMenu`, `FishmongerMenu`, `FishingMenu`).
- **Invariants:** no file → all services; importance-1 ports also haul out; `haul_out` requires `boatyard`; fishmonger follows grocery, chandlery/sailmaker follow boatyard; tier major (haul-out) / larger (boatyard) / small; facility ids equal shore station `interaction_id`s; `ALL` is shore order.
- **Tests:** `tests/suites/test_harbour_life.gd`, `test_boat_care.gd`, `test_boat_of_your_own.gd`, `test_denmark_views.gd`, `test_presentation.gd`, `test_visual_prototype.gd`.
- **Change risks:** shared default/`@major` instances must not be mutated by callers; adding a service needs entries in `has()`, `describe()` and `PREVIEW`.

### `src/harbour/harbour_landmark.gd`

- **Role:** class_name `HarbourLandmark`, extends Resource (`@tool`); one landmark illustration (`title`, `texture`, `offset` from the quay anchor, drawn `width`).
- **Depends on:** nothing.
- **Lifecycle:** embedded in `HarbourArt` resources; drawn by `HarbourDressing._draw_landmark` at `get_quay_anchor() + offset`.
- **Invariants:** art only, no collision.
- **Tests:** `tests/suites/test_visual_prototype.gd`.
- **Change risks:** renaming exports breaks existing harbour `.tres` files.

### `src/harbour/harbour_looks.gd`

- **Role:** class_name `HarbourLooks`, extends RefCounted (I021); per-harbour look (archetype) table, the special-harbour list, and the art drawn beyond the pontoon. Static `get_default()` (loaded once).
- **Depends on:** `res://data/harbours/harbour_looks.json` (`looks` {id: {title, texture, about}}, `harbours` {port id: look id}, `special` {port id: {text}}), `HarbourArt.for_port`, `HarbourLandmark`, `Loc`.
- **State:** `looks`, `harbours`, `special` dictionaries; `_art_cache` look id -> shared `HarbourArt` (one landmark at `OFFSET` (0, 79), `WIDTH` 1150, like the Nyhavn strip) or null when the image is missing.
- **API:** `look_of(id)`, `look_title(look)` (translated), `is_special(id)`, `special_note(id)` (translated), `art_for(id)` (own HarbourArt with landmarks > look art (merged into a duplicate when the harbour file has only an atmosphere) > own/null), `picture_for(id)` (first landmark texture).
- **Lifecycle:** used by `HarbourDressing.refresh()`, `MapView._draw_port`, `WorldMap._special_line`, `App._on_arrived`.
- **Performance:** textures loaded lazily via `load()` on first use of a look and kept (nine looks at most, ~0.3 MB each as imported); no per-frame work; a chart redraw does one dictionary lookup per drawn port.
- **Invariants:** looks are chosen per harbour (data), never derived from continent/region at runtime; `special` keys equal the harbours whose `data/harbours/<id>.tres` has landmarks (`test_wider_world`); a missing look or image falls back to the plain quay with a warning.
- **Tests:** `tests/suites/test_wider_world.gd`, `tests/suites/test_visual_prototype.gd`.
- **Change risks:** renaming a look id requires the table's `harbours` entries to follow; a special harbour without its own art (or the reverse) fails the suite; art is painted by `tools/harbours/paint_harbour_looks.py`.

### `src/harbour/harbour_trades.gd`

- **Role:** class_name `HarbourTrades`, extends RefCounted; static catalogue access for trades (decor, sail cloths, chandlery upgrades, Magic Anchor price, fishmonger names) and which harbours offer them.
- **Depends on:** `res://data/harbours/trades/trades.json` (`decor`, `sail_cloths`, `chandlery.{upgrades, magic_anchor_price}`, `fishmongers`), `HarbourFacilities`.
- **State:** static `_data` (lazy; falls back to an empty structure if parsing fails).
- **Lifecycle:** static helper; used by `HarbourFacilities.has`, `GameSession`, `HomeState`, `CabinDecor`, `BoatArea` (decor), `SailRig` (`sail_colours`), UI menus (chandlery, sailmaker, fishmonger, boat care, cabin home).
- **Invariants:** fishmonger ⇔ grocery, chandlery/sailmaker ⇔ boatyard; prices rounded to tens (`price_per_ft · ft / 10`, ×10); unknown cloth falls back to `classic`; fishmonger name deterministic from `hash(port_id)`; Magic Anchor price default 450.
- **Tests:** `tests/suites/test_boat_of_your_own.gd`, `test_magic_anchor.gd`; `tests/scratch/shots_i020.gd`.
- **Change risks:** a failed parse yields an empty catalogue that is cached (never retried); decor ids are kept in saves through `HomeState.owned_decor` and per-vessel decor lists (indirect), so renaming ids in `trades.json` orphans owned items.

### `src/harbour/shore_access.gd`

- **Role:** class_name `ShoreAccess`, extends Node2D; gangplank, opened rail and shore strip so the player can walk from the deck onto the pontoon; offers service slots.
- **Depends on:** `BoatArea` (`walkable_bounds`, `Surroundings/Mooring/Pontoon`, `Layout/Collision/Lifeline/CollisionPolygon2D`, `Layout/SpawnPoints/from_boatyard`), `SessionLog.write("gangplank", ...)`, `GameSession` (`get_vessel_id`, `get_location_id`).
- **State:** pontoon/shore rects, plank x, rail crossing points, own `StaticBody2D` "ShoreCollision" of `SegmentShape2D`s, `_active`, `_ashore`, `_valid`; it writes `BoatArea.walkable_bounds` while active.
- **Lifecycle:** created by `BoatArea` (decks with a mooring), `setup(area)` returns false if the layout lacks pontoon/rail/boarding point; `set_active(true)` in harbour, false underway; accessed via `BoatArea.get_shore_access()`.
- **Invariants:** active ⇒ original rail disabled and replacement segments enabled (both via `set_deferred`); inactive ⇒ original rail and bounds restored; slots never on the plank's path and ≥ 80 units from the strip ends.
- **Tests:** `tests/suites/test_harbour_life.gd`, `test_world_voyage.gd`.
- **Change risks:** the gap direction heuristic in `_build_body` assumes a reasonably convex rail; deferred collision toggles mean one physics frame of transition; vessel layouts must keep the node paths.

### `src/harbour/shore_events.gd`

- **Role:** class_name `ShoreEvents`, extends RefCounted; constant library of Go Ashore events (generic, per region, per harbour) and helpers.
- **Depends on:** `PortCatalog.get_default().get_port` (region).
- **State:** consts `GENERIC`, `BY_REGION` (atlantic_islands, caribbean, central_america, pacific), `BY_HARBOUR` (copenhagen, lohals); `REST_HOURS` = 6.
- **Lifecycle:** static helper; `GameSession` (`get_shore_event`, `apply_shore_choice`, per the file's notes) and `src/ui/go_ashore_menu.gd`.
- **Persistence:** first choice per (port, event) recorded in `ObjectiveProgress.completed` as `shore:<port>:<event>` (`record_id`) by `GameSession`.
- **Invariants:** order generic → region → harbour; `{harbour}` placeholder filled by `fill()`; renown only the first time.
- **Tests:** `tests/suites/test_harbour_life.gd`.
- **Change risks:** changing event ids or port ids orphans saved records (event offered as new again); texts are English source strings translated by the caller, if at all.

### `src/hat/hat_art.gd`

- **Role:** class_name `HatArt`, extends Resource (`@tool`); hat artwork slots (`stored`, `worn`, `blowing`) with texture resolution and drawing.
- **Depends on:** `HatDrawing.draw_hat` (fallback), `ArtworkResolver.get_artwork("character.captain.hat_<slot>", own)`; default resource `res://data/hat/hat_art.tres`; optional `<art_folder>/hat_<slot>.png` (default folder `res://assets/hat`, currently only a README).
- **State:** exported textures, sizes, `art_folder`, `procedural_only`; static `_default` (cleared by `clear_default()`, called from `GameSession`).
- **Lifecycle:** Resource singleton via `get_default()`; used by `HatHook`, `PlayerHat`, `HatBlowAway`, `src/ui/hat_badge.gd`.
- **Invariants:** resolution order assigned texture → folder PNG (Workshop replacement wins over it) → procedural; art only, never affects hat state or collision; worn/blowing art is top-down with the peak toward +x.
- **Tests:** `tests/suites/test_sprite_workshop.gd`, `test_visual_prototype.gd`.
- **Change risks:** `get_texture` calls `load()` each draw when no texture is assigned (resource cache); `draw_slot` resets the canvas transform to identity afterwards.

### `src/hat/hat_blow_away.gd`

- **Role:** class_name `HatBlowAway`, extends Node2D; cosmetic hat-loss effect (accelerating tumble downwind with flutter, streaks and echoes, fade).
- **Depends on:** `HatArt.get_default().draw_slot(SLOT_BLOWING)`.
- **State:** `direction`, `_elapsed`, `_start`.
- **Lifecycle:** created by `BoatArea` (`effect.setup(player.position, wind_direction_on_deck())`); frees itself after `DURATION` (2.8 s).
- **Performance:** redraws every frame for its short life.
- **Invariants:** real time, not saved; the loss itself belongs to `GameSession`.
- **Tests:** `tests/suites/test_hat.gd`.
- **Change risks:** low; `get_progress()` is read by tests.

### `src/hat/hat_config.gd`

- **Role:** class_name `HatConfig`, extends RefCounted; hat balancing from `res://data/hat/hat_config.json` and pure strain functions.
- **Depends on:** the JSON file only.
- **State:** `price_eur`, `check_interval_s`, `gust_allowance_kn`, `bands`, `gust_bands`, `harbour_factor`, `recovery_per_min`, `warning_repeat_min`, `threshold_min`/`max`; static `_default` (`clear_default()` from `GameSession`).
- **Lifecycle:** lazy singleton; read by `Simulation` (hat check grid at `check_interval_s`), `GameSession` (price, strain application), `HatState` (doc).
- **Invariants:** effective wind = max(sustained, gust − allowance); strain 0 below the first band; gust bands not cumulative (strongest reached); harbour multiplies by `harbour_factor`; `threshold_for(seed, serial)` is deterministic via `hash([seed, "captains_hat", serial])`; invalid file falls back to default bands with `push_error`.
- **Tests:** `tests/suites/test_hat.gd`, `test_gameplay_flow.gd`, `test_secret_achievements.gd`.
- **Change risks:** `risk_from_kn()` assumes `bands` is non-empty (guaranteed by the loader); changing the hash input changes every saved game's hat thresholds.

### `src/hat/hat_drawing.gd`

- **Role:** class_name `HatDrawing`, extends RefCounted; procedural top-down captain's hat drawing.
- **Depends on:** `CanvasItem` drawing API only.
- **Lifecycle:** static helper; called by `HatArt.draw_slot` when a slot has no texture.
- **Invariants:** deterministic outline (wobble from fixed seeds, not time); peak toward `angle`.
- **Tests:** none found directly (exercised through `HatArt`).
- **Change risks:** low; visual only.

### `src/hat/hat_hook.gd`

- **Role:** class_name `HatHook`, extends Node2D; cabin hat hook, draws the stored hat; highlight target for the `hat` station.
- **Depends on:** `GameSession` (`hat_changed`, `state_replaced`, `is_active`, `get_hat_status`), `HatState.STORED`, `HatArt`, `HighlightResolver` (`GROUP`, `META_FOR`, `circle`, `rounded_rect`).
- **Signals:** connects `GameSession.hat_changed` and `GameSession.state_replaced` to `refresh`.
- **State:** `_stored`.
- **Lifecycle:** created by `BoatArea` at `Layout/HatSpot` (when present); accessed via `BoatArea.get_hat_hook()`.
- **Invariants:** art only, no collision; the interaction lives on the cabin's `hat` station.
- **Tests:** `tests/suites/test_hat.gd`, `test_living_world.gd`, `test_visual_prototype.gd` (via `get_hat_hook`).
- **Change risks:** lambda connection to `hat_changed` is never disconnected explicitly (freed with the node).

### `src/hat/hat_story.gd`

- **Role:** class_name `HatStory`, extends RefCounted; hat-loss wording (place description, loss messages, log line) and the shared `open_water_nm` measure.
- **Depends on:** `PortCatalog` (`get_port`, `ports`), `PortData`, `GeoMath` (`distance_nm`, `format_position`), `SeaRouter.get_default().grid` (composite chart, `grid_at`, `cell_class_at_geo`), `NavGrid.NAVIGABLE`, `WeatherSample`, `WeatherModel.HAZARD_*`, `Loc`.
- **Lifecycle:** static helper; `GameSession` (hat loss, `describe_place`), `FishingCatalog.is_coastal` (`open_water_nm`).
- **Performance:** `describe_place` scans all ports when not in harbour; `open_water_nm` scans a cell window sized by `max_nm` with early-out on distance.
- **Invariants:** facts only from real state; cells outside the chart count as land (conservative); loss messages cycle by `lost_count`.
- **Tests:** `tests/suites/test_hat.gd`, `test_secret_achievements.gd`.
- **Change risks:** `LOSS_MESSAGES` are returned without `Loc.t` here; `open_water_nm` also drives fishing's coastal rule, so changes affect bites.

### `src/hat/player_hat.gd`

- **Role:** class_name `PlayerHat`, extends Node2D; draws the hat worn (rotated to facing) or carried on the player token.
- **Depends on:** `GameSession` (`hat_changed`, `state_replaced`, `get_hat_status`, `is_active`), `HatState` (`WORN`, `CARRIED`, `STORED`), `HatArt`; parent player's optional `get_facing()` / `get_carry_point()`.
- **Signals:** connects `GameSession.hat_changed` and `state_replaced` to `refresh`.
- **State:** `_status`, `_facing`.
- **Lifecycle:** created by `src/player/player.gd` as child `PlayerHat` (exposed via `get_hat_visual()`); `SailorDrawing` refers to it in its notes only (indirect).
- **Performance:** `_process` only redraws when facing changes.
- **Invariants:** visual only; no effect on collision or movement.
- **Tests:** `tests/suites/test_hat.gd`.
- **Change risks:** relies on duck-typed parent methods.

### `src/sailing/propulsion_controller.gd`

- **Role:** class_name `PropulsionController`, extends RefCounted; pure sail/engine decision with time-based EMA, stall detection and hysteresis.
- **Depends on:** `PropulsionState`, `VesselProfile` (`sail_speed_kn`, `engine_speed_kn`, `averaging_time_s`, `engine_start_below_kn`, `engine_stop_above_kn`, `stall_below_kn`, `stall_delay_s`, `min_sail_time_s`, `min_engine_time_s`, `engine_stop_confirm_s`, `heading_reset_deg`, `wants_spinnaker`), `WindField` (`Sample`, `relative_angle`).
- **State:** none; `evaluate()` returns a new `PropulsionState` (input duplicated).
- **Lifecycle:** static; called from `Simulation` with `SailTrim.factor` as `trim_factor`.
- **Invariants:** independent of frame rate and time acceleration (dt from game time); trim scales only sailing `speed_kn`, never potential or decisions; turns > `heading_reset_deg` or `reset_history` reset the average but keep a continuing stall timer; `reassess` may switch immediately on clear thresholds but minimum mode times still apply and no timer is reset.
- **Tests:** `tests/suites/test_sailing.gd`, `test_reassessment.gd`, `test_sailing_presentation.gd`.
- **Change risks:** EMA uses the previous potential over the elapsed interval (order matters); altering minimum-time checks can cause engine cycling.

### `src/sailing/propulsion_state.gd`

- **Role:** class_name `PropulsionState`, extends RefCounted; saved propulsion data and controller memory; HUD description helpers.
- **Depends on:** `Loc`.
- **State:** `mode`, `engine_reason`, `initialised`, `average_potential_kn`, `potential_kn`, `speed_kn`, `mode_seconds`, `stall_seconds`, `favorable_seconds`, `last_evaluation_time`, `heading_deg`, `wind_from_deg`, `wind_speed_kn`, `true_wind_angle`, `spinnaker`.
- **Lifecycle:** owned by `SessionState.propulsion`; replaced by `PropulsionController.evaluate` via `Simulation`/`GameSession`; read by `Hud`, `SailingPanel`, `SailTrimPanel`, `SailRig`, `WorldMap`, `App`.
- **Persistence:** saved under the vessel's `propulsion` key (`to_dict`); `from_dict` validates types, finiteness, mode in `MODES`, `speed_kn` 0..50, `mode_seconds` ≥ 0; `SaveManager` migration writes a fresh default for older saves.
- **Invariants:** `duplicate_state()` round-trips through `to_dict`; all keys required on load.
- **Tests:** `tests/suites/test_sailing.gd`, `test_reassessment.gd`, `test_sailing_presentation.gd`, `test_wind.gd`, `test_vessels.gd`, `test_life_aboard.gd`, `test_magic_anchor.gd`; `tests/restart_105b.gd`.
- **Change risks:** adding a field requires updating `to_dict`, `from_dict_unchecked`, the validation list and a save migration; `point_of_sail_name` returns untranslated "running" (others use `Loc.t`).

### `src/sailing/sail_trim.gd`

- **Role:** class_name `SailTrim`, extends RefCounted; pure sail-trim rules (best setting, error, speed factor, feedback, percent).
- **Depends on:** `Loc`.
- **State:** none; the setting (`trim_auto`, `trim_value`) lives in `SessionState` (saved as `sail_trim: {auto, value}`).
- **Lifecycle:** static; `Simulation` (factor passed to `PropulsionController.evaluate`), `GameSession`, `SessionState`, `SailTrimPanel`, `SailingPanel`.
- **Invariants:** pure in (auto, trim, angle, wind); auto ⇒ factor 1.0; factor in [0.90, 1.06]; within `WELL` (0.15) = "Well trimmed"; never affects potential or engine choice.
- **Tests:** `tests/suites/test_sail_trim.gd`.
- **Change risks:** changing `best()` shifts every manual-trim player's speed; keep factor bounds modest.

### `src/sailing/weather_damage.gd`

- **Role:** class_name `WeatherDamage`, extends RefCounted; heavy-weather condition loss rate and integration over game time.
- **Depends on:** `WeatherModel.get_default().sample_hazard(geo, t, seed)` ([.., speed, gust]).
- **State:** none.
- **Lifecycle:** static; `Simulation` calls `damage_between(GameSession.get_damage_applied_until(), now, ...)` while underway, with `VesselProfile.weather_damage_factor` (indirect); `GameSession` applies it.
- **Performance:** one `sample_hazard` per 60 s of game time in the interval (an 8 h sleep = 480 samples).
- **Invariants:** samples on the absolute grid k·`SUBSTEP`, so totals are independent of step size; zero below 28 kn sustained and 45 kn gusts; rate = 0.06·(w−28)^1.6 + 0.2·(g−45), times factor.
- **Tests:** `tests/suites/test_upkeep.gd`, `test_turbocharge.gd`; `tests/scratch/probe_weather_cost.gd`.
- **Change risks:** must stay consistent with `WeatherModel.sample()` (uses the fast `sample_hazard` path); tuning changes rescue frequency.

### `src/skills/timing_check.gd`

- **Role:** class_name `TimingCheck`, extends RefCounted; shared circular timing-check state machine (needle, arc, Perfect zone, misses, idle timeout).
- **Depends on:** nothing (own seeded `RandomNumberGenerator`).
- **State:** `checks_needed`, `line_control`, `arc_deg`, `angle`, `target_deg`, `hits`, `perfects`, `misses`, `elapsed`, `result`, `last_press`, cooldown/idle timers.
- **Lifecycle:** instantiated via `ReelTiming` (fishing, `FishingMenu`) and `MagicAnchorDeployment` (`AnchorMenu`); drawn by `src/ui/reel_dial.gd`; `step(delta)` with real time by the menus.
- **Invariants:** constant `SPEED_DEG` (200°/s); arc clamped 10..180°; Perfect = max(30 % of arc, 10°); fails at `line_control` misses or `IDLE_SECONDS` (60 s) without a press; `DEBOUNCE` 0.15 s; first arc 150–230° ahead, later arcs 130–250° ahead; deterministic for a seed.
- **Tests:** `tests/suites/test_magic_anchor.gd`, `test_fishing2.gd` (via `ReelTiming`).
- **Change risks:** `RESULT_LANDED`/`RESULT_ESCAPED` names are shared by both encounters; RNG draw order defines arc placement (seeded tests depend on it).

## User interface

### `src/ui/aboard_badge.gd`

- **Role:** class_name `AboardBadge`, extends `VBoxContainer`; HUD stack of non-audio status rows (bite, anchor, line, fed).
- **Depends on:** `GameSession` (is_active, get_pending_bite, is_anchored, get_anchor, is_settled_at_anchor, get_day_phase, is_line_out, get_fishing_mode, get_vessel_speed_kn, is_well_fed), `AnchorState`, `AnchorSite.holding_text`, `AnchorLife` phase constants, `FishingState.MODE_TROLLING`, `FishingCatalog.get_default().max_trolling_kn`, `UiTheme.tint`, `Loc`.
- **Signals:** none declared or connected.
- **State:** read-only on GameSession; owns `_rows` (id -> PanelContainer) and `_time` (pulse clock).
- **Lifecycle:** created in code by `Hud._ready` (`hud.gd`, node name "AboardBadge"); `Hud` positions it.
- **Performance:** `_process` calls `refresh()` every frame, which calls static `lines_for_game()` (a handful of GameSession queries) and `find_child` per visible row.
- **Invariants:** `lines_for_game()` is static and returns `{id: [text, role, key_shown]}` for visible rows only; ids are the fixed set `bite, anchor, line, fed`. Urgent rows (bite, or role `RED`) pulse via `modulate`. Presentation only, nothing saved.
- **Tests:** `tests/suites/test_galley_and_anchor.gd`, `tests/suites/test_fishing.gd`, `tests/suites/test_fishing2.gd`, `tests/suites/test_anchor_life.gd` (via `aboard_badge` / `lines_for_game`).
- **Change risks:** Tests compare exact row texts (`get_texts()`, `lines_for_game()`); changing wording or row ids breaks them. Theme role names (`caution`, `warning`) must exist in `UiTheme`.

### `src/ui/academy_guide.gd`

- **Role:** class_name `AcademyGuide`, extends Control (mouse ignored), child of App's `AcademyLayer` (UiScaleLayer, layer 15). static `enabled` (false in `test_runner`). `card` (PanelContainer "AcademyCard", bottom-right; `MARGIN_CHART` 540 at `WorldMap`), Heading/Text labels, SkipButton/MoreButton/CloseButton (focus none). `queue_tip(id)`, `queued_tips()`, `shown_tip()`, `update_card()` (every `CHECK_SECONDS` 0.25 from `_process`), `is_free()` (game active, BoatArea/WorldMap, no modal, router idle, no time_passage/voyage_map/loading, no HUD warning), `step_done(id)`, `dismiss()` (starts `TIP_GAP_SECONDS` 20), `read_more()`, `skip_first_voyage()`, `begin_first_voyage()`. Tips auto-close after `TIP_SECONDS` 25; the farewell "!done" after `DONE_SECONDS`. Night tip polled every 2 s (`Daylight.sun_elevation` < −6°).
- **Depends on:** `App` (router, modals, hud, time_passage, voyage_map, is_loading, open_handbook, notify), `Academy`, signals `GameSession.voyage_started/fish_bite/anchor_changed/provisions_warning/hat_warning/renown_awarded/boat_area_changed`, `Simulation.arrived/weather_warning/traffic_alert/vhf_call/passage_started`, `HarbourFacilities.BOATYARD`, `ActionWheel`, `CaptainsLogMenu`, `WorldMap`, `BoatArea`.
- **State:** `_queue`, `_tip`, `_tip_left`, `_gap_left`, `_moved`, timers.
- **Lifecycle:** created in `App._ready`; lives for the whole run.
- **Tests:** `tests/suites/test_academy.gd` (`[first voyage]`, `[tips]`).
- **Change risks:** `_input` only reads move actions (never handles input); a tip id must exist in `academy.json` `tips`.

### `src/ui/action_wheel.gd`

- **Role:** class_name `ActionWheel`, extends `ModalPanel`; radial modal menu of context actions (Q).
- **Depends on:** `ModalPanel` (close, stack), `UiTheme.color(&"backdrop")`, theme icons `checked`/`unchecked` of `CheckBox`; items come from `App.get_wheel_actions()`.
- **Signals:** declares `action_chosen(id: StringName)`, emitted in `choose()` after `close()`. Connects each button's `pressed`, `mouse_entered`, `focus_entered`, and its own `resized` -> `_layout`.
- **State:** `items: Array[Dictionary]` (`id`, `label`, `action: Callable`, optional `checked: Callable`), `_selected`. "checked" is read once in `_ready` (never cached state).
- **Lifecycle:** `ActionWheel.new()` + `setup(actions, title)` + `modals.push()` in `App.open_action_wheel()` (only in gameplay, router idle, no other modal).
- **Invariants:** `setup()` must run before `_ready()` builds buttons (title stored via meta if `_title` is not built yet). The chosen action is `call_deferred` after the wheel closes, so actions open their own modals on an empty stack. Input via `_unhandled_input` (move_*, interact/ui_accept, action_wheel).
- **Tests:** `tests/suites/test_cozy_polish.gd`, `tests/suites/test_cockpit_ui.gd`.
- **Change risks:** Calling the action synchronously (not deferred) would push onto the closing wheel's stack. Button node names `Action_<id>` are used by tests. Layout is absolute (`_layout` on resize).

### `src/ui/anchor_menu.gd`

- **Role:** class_name `AnchorMenu`, extends `SimplePanel`; windlass panel: anchorage evaluation, scope, set-timing bar, raise/reset/alarm, Magic Anchor deployment dial.
- **Depends on:** `GameSession` (is_anchored, anchoring_refusal, get_anchor, evaluate_anchorage, drop_anchor, adjust_anchor, raise_anchor, acknowledge_anchor_alarm, has_magic_anchor, magic_anchor_checks, drop_magic_anchor, MAGIC_ANCHOR_NAME/TEXT, get_game_time), `Simulation.get_weather_at_vessel`, `Hud.describe_wind`, `AnchorState` (SCOPES, HOLDING_*, KIND_MAGIC), `AnchorSite` (holding_text, CLASS_*, MIN_DEPTH_M, NORMAL_MAX_DEPTH_M), `DepthService.describe_depth`, `MagicAnchorDeployment`, `TimingCheck` press constants, `ReelDial`, `AudioManager` + `FishingSounds`, `SessionLog`, `SettingsManager.get_reduce_flashing`, `UiTheme`, `Loc`.
- **Signals:** declares `time_requested(minutes)` (emitted after drop/adjust/raise, Magic Anchor miss and success). Connects `GameSession.anchor_changed` -> `refresh`; also inherits `notification_requested` via `notify()`.
- **State:** all anchor changes via GameSession; local `_setting`, `_setting_for_drop`, `_marker`, `_deployment`, `_flourish`, `_time`.
- **Lifecycle:** `AnchorMenu.new()` in `App.open_anchor()`; App connects `time_requested` to `Simulation.spend_time_aboard(minutes, false)`. Reached from the windlass station, `AnchoragePrompt`, the action wheel and `BoatArea.anchor_requested`.
- **Performance:** `_process` redraws the set bar while setting and steps the magic dial while deploying (only when top of stack).
- **Invariants:** set quality is `set_quality_at(marker) = 1 - |marker-0.5|*2` clamped; `catch_set(at)` accepts an explicit marker for tests. Magic Anchor: misses cost `MagicAnchorDeployment.MISS_MINUTES`; cancel leaves the boat unanchored. Depth texts are labelled GAME ESTIMATES.
- **Tests:** `tests/suites/test_galley_and_anchor.gd`, `tests/suites/test_catch_and_cove_journey.gd`, `tests/suites/test_magic_anchor.gd`; screenshots in `tests/screenshots_105b.gd`.
- **Change risks:** Input is polled with `Input.is_action_just_pressed(&"interact")` in `_process`, not event-driven; moving it can double-fire with button focus. `FLOURISH_SECONDS`/`BRASS` are declared at the bottom of the file. Time-cost constants affect simulation time spent.

### `src/ui/anchorage_prompt.gd`

- **Role:** class_name `AnchoragePrompt`, extends `SimplePanel`; one-shot arrival question at an anchorage waypoint.
- **Depends on:** `GameSession.evaluate_anchorage`, `Loc`.
- **Signals:** declares `anchor_requested` and `sail_on_requested` (each emitted after `close()` from its button). App connects them to `open_anchor.call_deferred()` and `GameSession.sail_on_from_anchorage()`.
- **State:** none written; static `describe_site()` reads the anchorage reason.
- **Lifecycle:** `App.show_anchorage_prompt()` pushes it when `GameSession.is_holding_at_anchorage()` and no modal is open (flag `_anchorage_prompt_due` set by `_on_anchorage_reached`).
- **Invariants:** never anchors by itself; "Not yet" just closes (the boat keeps holding; wheel still offers anchor/sail on). Not re-shown on load.
- **Tests:** `tests/suites/test_anchorage.gd`, `tests/suites/test_joy_journey.gd`, `tests/suites/test_magic_anchor.gd`.
- **Change risks:** Button node names (`AnchorButton`, `WaitButton`, `SailOnButton`) are used by tests; emitting before `close()` would open the anchor menu while the prompt is still on the stack.

### `src/ui/boat_care_menu.gd`

- **Role:** class_name `BoatCareMenu`, extends `SimplePanel`; boatyard services (repair, rig, engine, haul-out) and yard-fitted upgrades. Steady Hands: `Loc.t` on the upgrade name in the "%s fitted" notice.
- **Depends on:** `BoatCareView`, `GameSession` (service_quote, service_refusal, perform_service, has_upgrade, upgrade_refusal, upgrade_price, install_upgrade, has_facility, get_harbour_facilities, has_magic_anchor, format_money, MAGIC_ANCHOR_*), `BoatCare` (SERVICE_*, SERVICE_NAMES, get_upgrades, get_upgrade), `HarbourFacilities` (HAUL_OUT, TIER_NAMES), `HarbourTrades.is_chandlery_upgrade`, `SessionLog`, `Loc`.
- **Signals:** declares `time_requested(minutes)` (after a service or upgrade) and `haul_out_requested` (HaulOutButton). Connects `GameSession.boat_care_changed` -> `refresh`, `GameSession.funds_changed` -> `_on_funds_changed`.
- **State:** writes only through `GameSession.perform_service` / `install_upgrade`.
- **Lifecycle:** `App.open_boat_care()` (moored, boatyard facility) on top of `BoatyardMenu`; App connects `time_requested` -> `_spend_yard_time` (spends time ashore, refreshes the yard) and `haul_out_requested` -> `open_haul_out`.
- **Invariants:** chandlery upgrades are skipped here; haul_out-yard upgrades only shown where `HAUL_OUT` exists (or already fitted). Magic Anchor row is display-only (always disabled; sold at the chandlery).
- **Tests:** `tests/suites/test_boat_care.gd`, `tests/suites/test_magic_anchor.gd`, `tests/suites/test_upkeep_ui.gd`, `tests/suites/test_chartroom_ui.gd`.
- **Change risks:** Button labels depend on refusal text (`begins_with("Not enough")` -> "Too expensive"); changing GameSession refusal wording changes UI. Node names `<Service>Button`, `Fit_<id>`, `HaulOutButton` are used by tests.

### `src/ui/boat_care_view.gd`

- **Role:** class_name `BoatCareView`, extends `VBoxContainer`; read-only grid of care areas with level, description and advice.
- **Depends on:** `GameSession` (get_boat_care, get_condition, get_game_time), `BoatCare` (AREAS, AREA_NAMES, area_level, LEVEL_NAMES, LEVEL_ROLES, advice, describe_area, AREA_EQUIPMENT), `UiTheme.tint`, `Loc`.
- **Signals:** none.
- **State:** read-only; `_rows` (area -> [level label, text label]).
- **Lifecycle:** created with `.new()` by `BoatCareMenu` (node "Overview") and `CaptainsLogMenu` Boat tab; `refresh()` is called by the owner (BoatCareMenu on its signals; the log builds once).
- **Invariants:** equipment row shows the upgrade count, not a level.
- **Tests:** `tests/suites/test_boat_care.gd` (via `get_overview().get_level_text()`).
- **Change risks:** Shared by two screens; layout widths affect both. `refresh()` is a no-op before `_ready`.

### `src/ui/boatyard_menu.gd`

- **Role:** class_name `BoatyardMenu`, extends `ModalPanel`; vessel browser/switcher with SubViewport deck preview, spec list, performance comparison and yard-service buttons. I022: list buttons and a `Price` spec row from `_ownership()` ("(your boat)"/"Yours"/price); `_choose` reads "Move aboard…", "Buy the %s (%s)…" or "%s needed to buy it" (disabled when unaffordable); still emits `vessel_chosen`. Steady Hands: `FitScroll.wrap([Body, CompareTitle, Comparison], _panel)` in `_ready`.
- **Depends on:** scene `src/ui/boatyard_menu.tscn` (unique nodes `%VesselList`, `%PreviewViewport`, `%NameLabel`, `%HullLabel`, `%Description`, `%Specs`, `%Comparison`, `%ChooseButton`, `%Panel`, `%ConditionLabel`, `%ServiceStatus`, `%CareButton`, `%GroceryButton`, `%CloseButton`), `VesselCatalog`, `VesselDefinition` (performance profile, specs, deck_visual_scene, get_active_visual_profile), `VesselVisual`, `VesselCondition`, `GameSession`, `BoatCare.overall_level`, `Provisions.format_days`, `HarbourFacilities`, `Loc`.
- **Signals:** declares `vessel_chosen(vessel_id)`, `care_requested`, `grocery_requested`, `chandlery_requested`, `sailmaker_requested`. App connects them to `switch_vessel`, `open_boat_care`, `open_grocery`, `open_chandlery`, `open_sailmaker`.
- **State:** `selected: VesselDefinition`; no writes (switching is `App.switch_vessel` -> GameSession).
- **Lifecycle:** instanced from `App.boatyard_menu_scene` (exported, set in `app.tscn`) in `App.open_boatyard()` (moored, `can_change_vessel`). App's `_spend_yard_time` calls `refresh_condition()`.
- **Performance:** `_process` runs `_update_services()` every frame while visible (several GameSession queries and string formats). `select()` frees and re-instantiates the preview scene each time.
- **Invariants:** panel fixed at `PANEL_SIZE` (shrunk only to fit window); comparison values come from `VesselProfile` (`compare_rows`, static). Up/Down in `_input` cycle boats before GUI focus navigation.
- **Tests:** `tests/suites/test_vessels.gd`, `tests/suites/test_boat_care.gd`, `tests/suites/test_denmark_views.gd`, `tests/suites/test_upkeep_ui.gd`, `tests/suites/test_visual_prototype.gd`, `tests/suites/test_solar_panels.gd`, `tests/suites/test_harbour_life.gd`.
- **Change risks:** Renaming unique nodes in the .tscn breaks `@onready`. Tests compare `get_panel_rect()` across selections (size must not change). Preview depends on each vessel's `deck_visual_scene` and `visual.canvas`.

### `src/ui/cabin_home_menu.gd`

- **Role:** class_name `CabinHomeMenu`, extends `TradePanel`; toggles which owned cabin decor items are shown on the current boat. Steady Hands: explicit right-column anchors; `_fit_column` sets `offset_left = -(minimum width + SAFE_MARGIN)` deferred and on `minimum_size_changed` (a preset in `_ready` used the unsized modal and a 700 px column for a 737 px panel).
- **Depends on:** `TradePanel` (`_build_trade`, `_row`, `_rows`), `HarbourTrades.get_decor`, `GameSession` (get_cabin_decor, set_cabin_decor, get_home().owns_decor, get_vessel_definition, get_vessel_id, format_money), `SessionLog`, `Loc`.
- **Signals:** none declared; inherits TradePanel's connections to `GameSession.funds_changed`, `home_changed`, `boat_care_changed`.
- **State:** writes per-vessel decor visibility via `GameSession.set_cabin_decor` (persisted in the home state; placement is done by `CabinDecor` in `BoatArea`, indirect).
- **Lifecycle:** `App.open_cabin_home()` (interior area, empty stack), offered as `cabin_home` on the action wheel.
- **Invariants:** non-modal look: hides the inherited `Dim` and anchors the panel right so the cabin stays visible. Unowned items are disabled with a chandlery price.
- **Tests:** `tests/suites/test_boat_of_your_own.gd`.
- **Change risks:** Relies on node names from `SimplePanel._build` (`Dim`, the `CenterContainer` child). Row ids are decor ids (no prefix), unlike the chandlery's `decor_<id>`.

### `src/ui/captains_log_menu.gd`

- **Role:** class_name `CaptainsLogMenu`, extends `SimplePanel`; read-only Captain's Log with tabs Log, Harbours, Objectives, Boat.
- **Depends on:** `GameSession` (get_captains_log, get_total_nm_sailed, get_rescue_count, get_lifetime_renown, get_unpublished_renown, get_publish_quote, is_underway, get_voyage_destination_id, get_voyage_sailed_nm, get_hat().history, get_shore_moments, get_objective_progress, get_vessel_definition, get_boat_care, get_condition, get_game_time, format_money), `CaptainsLog`, `PortCatalog`/`PortData`, `ObjectiveCatalog`, `ObjectiveProgress`, `VesselCatalog`, `BoatCare`, `BoatCareView`, `Simulation.format_game_time`/`format_duration`, `UiTheme.tint`, `Loc`.
- **Signals:** declares `publish_requested` (PublishButton); App connects it to `open_publish_menu`.
- **State:** read-only on GameSession. Static `harbour_filter` and `_country_open` persist for the process lifetime (not saved).
- **Lifecycle:** `App.open_captains_log()` (L via `toggle_captains_log`, pause menu `log_requested`, action wheel); node name "CaptainsLogMenu".
- **Performance:** all tabs are built once in `_ready`; harbour list rebuilt on filter change (iterates all ports).
- **Invariants:** secret objectives reveal nothing until completed (only a count). Notable moments merge hat history and shore moments, newest `MAX_MOMENTS` shown. Content is not refreshed while open.
- **Tests:** `tests/suites/test_captains_log.gd`, `tests/suites/test_objectives.gd`, `tests/suites/test_secret_achievements.gd`, `tests/suites/test_publishing.gd`, `tests/suites/test_boat_care.gd`, `tests/suites/test_branding.gd`; screenshots in `tests/screenshots_17.gd`.
- **Change risks:** Tests find labels by node name (`DistanceValue`, `Passage0`, `Secret_<id>`, `Country_<key>`, `Filter_<id>`...). Static filter state leaks between test cases unless reset. Theme variations `DisplayHeader`/`DisplayName` must exist in the theme.

### `src/ui/catch_badge.gd`

- **Role:** class_name `CatchBadge`, extends `HBoxContainer`; rarity pips + grade medal widget with text labels.
- **Depends on:** `FishingCatalog` (rarity_label, rarity_index, RARITY_ORDER, grade_label, GRADE_NONE).
- **Signals:** none declared; connects its two drawing controls' `draw`.
- **State:** `_rarity`, `_grade` (`&"?"` means grade not yet known).
- **Lifecycle:** created with `.new()` by `FishingMenu` (reel, result, cool-box rows) and `TrophyMenu`; `set_catch(rarity, grade, show_grade)` may be called before `_ready` (`_update` guards on null labels).
- **Invariants:** never colour-only: always a text label next to pips/medal. Junk (`rarity == ""`) shows neither.
- **Tests:** `tests/suites/test_fishing2.gd`.
- **Change risks:** `get_text()` output format is asserted in tests; medal colours keyed by grade ids `bronze/silver/gold`.

### `src/ui/chandlery_menu.gd`

- **Role:** class_name `ChandleryMenu`, extends `TradePanel`; shop for chandlery upgrades, the Magic Anchor, lures and cabin decor.
- **Depends on:** `TradePanel`, `HarbourTrades` (get_chandlery_upgrades, get_magic_anchor_price, get_decor, get_decor_item), `BoatCare.get_upgrade`, `FishingCatalog` lures, `GameSession` (has_facility, get_funds, has_upgrade, upgrade_price, upgrade_refusal, install_upgrade, has_magic_anchor, buy_magic_anchor, buy_lure, get_fishing, get_home().owns_decor, buy_decor), `HarbourFacilities.CHANDLERY`, `SessionLog`, `Loc`.
- **Signals:** declares `time_requested(minutes)` (after fitting an upgrade); App connects it to `_spend_yard_time`.
- **State:** writes via GameSession purchase transactions only.
- **Lifecycle:** `App.open_chandlery()` -> `_open_trade(HarbourFacilities.CHANDLERY, ...)` (refused and freed if the harbour lacks one); opened from `BoatyardMenu.chandlery_requested`.
- **Invariants:** row ids: upgrade id, `magic_anchor`, `lure_<id>`, `decor_<id>`. Buttons disabled when closed or price > funds; purchases are whole-or-nothing in GameSession.
- **Tests:** `tests/suites/test_boat_of_your_own.gd`, `tests/suites/test_magic_anchor.gd`.
- **Change risks:** Row ids are used by tests; the Magic Anchor price lives in `HarbourTrades`, not here.

### `src/ui/chart_plotter.gd`

- **Role:** class_name `ChartPlotter`, extends `PanelContainer`; on-deck north-up mini plotter with coast raster, course, next turn and wind.
- **Depends on:** `GameSession` (is_active, is_underway, is_anchored, get_vessel_position, get_voyage), `Simulation` (get_current_heading, get_wind_at), `SeaRouter.get_default().grid` / `NavGrid.cell_class_at_geo`, `GeoMath` (normalize, segment_index_at), `WorldMap.get_next_turn` (static), `WindLayer.color_for`, `Hud.describe_wind`, `Loc`.
- **Signals:** none declared; connects ZoomIn/ZoomOut `pressed` -> `change_range`, plot `draw` -> `_draw_plot`.
- **State:** static `shown` and `range_index` (per run, not saved; `App.toggle_chartplotter` flips `shown`); `on_deck: Callable` set by `Hud`; raster `_image`/`_texture` and build cursor.
- **Lifecycle:** created by `Hud._ready`; toggled by App (P key, action wheel item `chartplotter` with `checked` reading `ChartPlotter.shown`).
- **Performance:** raster `RASTER`x`RASTER` (96²) rebuilt `ROWS_PER_FRAME` (8) rows per frame, only when the boat moved `REBUILD_FRACTION` of range or the range changed; `NavGrid` fetched lazily on first build. Route drawing stops once a point is > 3x range away. Redraws every visible frame.
- **Invariants:** coast comes from the router's own nav grid (shows exactly the navigable water). Local flat projection in nm east/north.
- **Tests:** `tests/suites/test_cozy_polish.gd`, `tests/suites/test_cockpit_ui.gd`; screenshots in `tests/screenshots_17.gd`.
- **Change risks:** `_nm_offset` and `_geo_at` are static helpers also called by `src/navigation/traffic_model.gd`; changing them alters AI traffic motion. Static `shown` persists across tests. `is_raster_ready()` is what tests wait on.

### `src/ui/confirm_dialog.gd`

- **Role:** class_name `ConfirmDialog`, extends `ModalPanel`; generic yes/no modal.
- **Depends on:** scene `src/ui/confirm_dialog.tscn` (unique nodes `%Title`, `%Message`, `%ConfirmButton`, `%CancelButton`).
- **Signals:** declares `answered(confirmed: bool)`, emitted exactly once, then `close()`.
- **State:** `_texts`, `_answered`.
- **Lifecycle:** instanced by `ModalStack.confirm()` from its `confirm_dialog_scene` (set in `app.tscn`); callers `await stack.confirm(...)` (App load/quicksave/main menu/import/leave chart/set sail, `SettingsMenu`, `SaveLoadMenu`).
- **Invariants:** `setup()` before `_ready`; Esc (`handle_back`) answers false; default focus on Cancel.
- **Tests:** `tests/suites/test_branding.gd`, `tests/suites/test_gameplay_flow.gd`.
- **Change risks:** Emitting `answered` more than once or not at all would hang or double-resume awaiting callers. Default focus on Cancel is a safety choice for destructive confirms.

### `src/ui/cooking_menu.gd`

- **Role:** class_name `CookingMenu`, extends `SimplePanel`; galley: recipe list, detail, cook animation, coffee. Steady Hands: `Loc.t` on `recipe.text` and `recipe.name` (Cook %s).
- **Depends on:** `GameSession` (cooking_refusal, recipe_refusal, coffee_refusal, cook, make_coffee, get_fishing, get_food_days, COFFEE_MINUTES), `Recipes` (LIST, MAX_FISH_DAYS), `Provisions.format_days`, `Simulation.format_game_time`, `AudioManager` + `FishingSounds.sizzle`, `SessionLog`, `UiTheme`, `Loc`.
- **Signals:** declares `cooked(result)` (after a successful `serve()`) and `coffee_made(result)` (after `pour_coffee()`). App connects both to `Simulation.spend_time_aboard(minutes, true)` (cooked via `_on_meal_cooked`, which reports interruptions).
- **State:** writes via `GameSession.cook` / `make_coffee` only; local timers `_cooking`, `_brewing`, `_steam_until`, `_last_result`.
- **Lifecycle:** `App.open_cooking()` (gameplay, empty stack, hand free); reached from the galley stove station.
- **Performance:** `_process` redraws the pan every frame.
- **Invariants:** a refused dish changes nothing; `serve()` / `pour_coffee()` are the transaction points (tests call them directly). `_best_index` order assumes `Recipes.LIST` has 5 entries with fish dishes at 2..4.
- **Tests:** `tests/suites/test_galley_and_anchor.gd`, `tests/suites/test_catch_and_cove_journey.gd`, `tests/suites/test_anchor_life.gd`, `tests/suites/test_cozy_polish.gd`.
- **Change risks:** Hard-coded recipe index order in `_best_index`; changing `Recipes.LIST` length or order breaks it. `refresh()` is not tied to GameSession signals.

### `src/ui/dev_guides_menu.gd`

- **Role:** class_name `DevGuidesMenu`, extends `ModalPanel`; developer-only reader for `DEV_GUIDES/` Markdown.
- **Depends on:** scene `src/ui/dev_guides_menu.tscn` (`%GuideList`, `%GuideTitle`, `%Content`, `%CloseButton`), `DevGuides` (list_guides, read, title_of, guides_dir), `MarkdownLite.to_bbcode`, `UiTheme.palette_changed`, `TextServerManager`, `Loc`.
- **Signals:** connects `UiTheme.palette_changed` -> `_on_palette_changed` (re-renders, keeps scroll).
- **State:** `guides`, `current_path`, `_shown_path`.
- **Lifecycle:** instanced from `App.dev_guides_menu_scene` in `App.open_dev_guides()` (only if `DevGuides.is_available()`), triggered by `MainMenu.dev_guides_requested`.
- **Invariants:** disables `liga`/`calt`/`dlig` on the content fonts so `--` stays two hyphens.
- **Tests:** `tests/suites/test_dev_guides.gd`.
- **Change risks:** Not gameplay; risks are limited to dev builds. Button node names derive from guide file basenames.

### `src/ui/difficulty_menu.gd`

- **Role:** class_name `DifficultyMenu`, extends `SimplePanel` (I022). Built in `_ready`: title "Difficulty", note label, `picker` (DifficultyPicker, starts at `GameSession.get_difficulty()`), buttons `CancelButton`/`ApplyButton`; Apply calls `GameSession.set_difficulty(picker.level)` and `notify()`s a change, then `close()`.
- **Depends on:** `SimplePanel` (`_build`, `_label`, `_button`), `DifficultyPicker`, `Difficulty`, `GameSession`.
- **Lifecycle:** pushed by App when `PauseMenu.difficulty_requested` fires (on top of the pause menu; closing returns to it).
- **Tests:** `test_captains_other_life` `[menus]`.
- **Change risks:** `focus_default` looks the Apply button up by name.

### `src/ui/difficulty_picker.gd`

- **Role:** class_name `DifficultyPicker`, extends VBoxContainer (I022). `_init` builds a `Levels` row of toggle buttons named `Relaxed`/`Standard`/`Seasoned` (ButtonGroup) and a `Description` label; `select(id)` sets `level`, relabels the buttons via `Difficulty.display_name`, sets the description and emits `changed(level)`; re-selects on `NOTIFICATION_TRANSLATION_CHANGED`.
- **Depends on:** `Difficulty`.
- **State:** `level` (StringName), `_buttons`, `_text`.
- **Lifecycle:** created in code by `NewGameMenu._ready` (inserted before its Buttons row) and `DifficultyMenu`.
- **Tests:** `test_captains_other_life` `[menus]` (clicks `Seasoned`, `Relaxed`).
- **Change risks:** tests find the buttons by node name.

### `src/ui/fishing_menu.gd`

- **Role:** class_name `FishingMenu`, extends `SimplePanel`; rod panel with three faces (rod, reel, result). Steady Hands: `Loc.t` on `lure.name` in the lure list.
- **Depends on:** `GameSession` (get_fishing, get_fishing_mode, get_vessel_position, get_vessel_speed_kn, is_anchored, is_line_out, set_line, select_lure, set_keep_preferences, set_passage_posture, release_fish, sell_fish, has_facility, get_pending_bite, finish_fight, get_anchor, format_money; signals `fishing_changed`, `fish_bite`), `FishingCatalog`, `FishingState` (MODE_TROLLING, PASSAGE_*), `ReelTiming`, `ReelDial`, `FishPortrait`, `FishArt.thumbnail`, `CatchBadge`, `Simulation` (AdvanceResult, STOP_*, format_duration), `AnchorSite.holding_text`, `HarbourFacilities.GROCERY`, `AudioManager` + `FishingSounds`, `SessionLog`, `Loc`.
- **Signals:** declares `wait_requested(minutes)` (Wait button, `WAIT_MINUTES`=60). Connects `GameSession.fishing_changed` -> `refresh`, `GameSession.fish_bite` -> `_start_reel_if_bite`, `ReelDial.pressed` -> `press_reel`.
- **State:** writes via GameSession only; local `_reel`, `_reel_bite`, `_reel_done`, `_last_result`.
- **Lifecycle:** `App.open_fishing()` (gameplay, empty stack, hand free) from the rod holder station / R; App connects `wait_requested` -> `_on_fishing_wait` (spends time aboard, then `show_wait_result`).
- **Performance:** `_process` steps the reel only while reeling and on top of the stack; `refresh()` rebuilds cool-box rows (thumbnails, badges) on every `fishing_changed`.
- **Invariants:** reel seed is `hash("species|time")` (deterministic per bite); needle and presses pause when another modal is on top; Esc while reeling = `let_go()` (escape). `step_reel`/`press_reel` are test entry points.
- **Tests:** `tests/suites/test_fishing.gd`, `tests/suites/test_fishing2.gd`, `tests/suites/test_catch_and_cove_journey.gd`, `tests/suites/test_joy_journey.gd`, `tests/suites/test_chartroom_ui.gd`, `tests/suites/test_cozy_polish.gd`; helper `tests/helpers/reel.gd`; also `tests/restart_18.gd`, `tests/screenshots_18.gd`, `tests/screenshots_chartroom.gd`, benchmarks.
- **Change risks:** Cool-box "Sell" buttons are gated on `HarbourFacilities.GROCERY`, while `FishmongerMenu` gates on `FISHMONGER`; keep the two consistent if selling rules change. Option indices map to `RARITY_CHOICES`/`GRADE_CHOICES`/`POSTURE_CHOICES` order.

### `src/ui/fishmonger_menu.gd`

- **Role:** class_name `FishmongerMenu`, extends `TradePanel`; sells cool-box fish singly or all at once.
- **Depends on:** `TradePanel`, `HarbourTrades.fishmonger_name`, `FishingCatalog` (price, get_species_name, rarity_name), `GameSession` (get_location_id, get_fishing, sell_fish, sell_catch, has_facility, format_money), `HarbourFacilities.FISHMONGER`, `SessionLog`, `Loc`.
- **Signals:** none declared; connects `GameSession.fishing_changed` -> `_rebuild` (plus TradePanel's connections).
- **State:** writes via `GameSession.sell_fish` / `sell_catch`.
- **Lifecycle:** `App.open_fishmonger()` -> `_open_trade(FISHMONGER, ...)`; only reached from `GroceryMenu.fishmonger_requested`.
- **Invariants:** row id = fish uid; `SellAllButton` created once and moved to the front of the button row; each fish is paid exactly once (GameSession).
- **Tests:** `tests/suites/test_boat_of_your_own.gd`.
- **Change risks:** `_rebuild` frees rows with `queue_free` and clears `_rows`; the sell-all total is recomputed here from catalog prices and must match GameSession's `sell_catch`.

### `src/ui/fit_scroll.gd`

- **Role:** class_name `FitScroll`, extends ScrollContainer (Steady Hands). static `wrap(nodes, window_panel)` (moves the given siblings into a VBox "Content" inside a new FitScroll placed where the first was; `reparent(keep_global=false)` keeps owners), `fit()` (height = content minimum, capped at viewport height ÷ canvas scale − the rest of the parent box's minimum − the frame's stylebox − 2·`MARGIN`, at least `MIN_HEIGHT`), `is_scrolling()`. `_queue_fit` (deferred, once per change) on `viewport.size_changed`, `SettingsManager.ui_scale_changed` and the content's `minimum_size_changed`.
- **Depends on:** `SettingsManager.ui_scale_changed`.
- **State:** `frame`, `_fit_queued`.
- **Lifecycle:** created by `SettingsMenu._ready` (AudioSection + DisplaySection) and `BoatyardMenu._ready` (Body + CompareTitle + Comparison).
- **Tests:** `tests/suites/test_steady_hands.gd` (sweep at 1280×720 100/130 %, 1024×768, 2560×1080).
- **Change risks:** reparenting re-enters buttons into the tree; `App._on_node_added` connects the click sound once per button (meta `ui_click`).

### `src/ui/game_dev_menu.gd`

- **Role:** class_name `GameDevMenu`, extends `SimplePanel`. Signal `work_requested(task_id, choice)`. Nodes: Progress, Devlog, Task OptionButton ("name (N h)"), Question, Choices (toggle buttons Choice0..2 in `Pastimes.choice_order` order, locked for an interrupted task), Note, CancelButton, WorkButton (disabled until a choice). `selected_task()`, `pick(position)` (tests).
- **Depends on:** `Pastimes`, `GameSession.get_pastimes/is_game_released`, `Simulation.format_duration/format_game_time`.
- **State:** `choice`, `_order`.
- **Lifecycle:** pushed by `App.open_game_dev()`; App connects `work_requested` → `App.work_on_game` (deferred), which runs `pass_time` + `GameSession.work_on_game`.
- **Tests:** `tests/suites/test_captains_other_life.gd` (`[menus]`, screenshot i022_game_dev).
- **Change risks:** the interrupted task's choice is fixed (points count for the share worked with that choice).

### `src/ui/go_ashore_menu.gd`

- **Role:** class_name `GoAshoreMenu`, extends `SimplePanel`; harbour shore event with drawn icon and choices. Steady Hands: `_describe_choice` uses `Loc.t(choice.label)` and `Loc.t("free")`.
- **Depends on:** `GameSession` (get_location, get_shore_event, get_funds, facility_refusal, format_money), `ShoreEvents.fill`, `HarbourFacilities.GO_ASHORE`, `Loc`.
- **Signals:** declares `choice_made(event_id, choice_index)`; App connects it to `_on_shore_choice` (applies `GameSession.apply_shore_choice`, spends time via `Simulation.spend_time_ashore`, then calls `show_outcome(result)`).
- **State:** `_offer` (read once in `_ready`); no direct writes.
- **Lifecycle:** `App.open_go_ashore()` (gameplay, empty stack, facility present).
- **Performance:** `_process` redraws the icon every frame (small bob animation).
- **Invariants:** three offer states: `resting`, `event`, or none (facility refusal text). Choices costing more than funds are disabled. After an outcome only Return remains.
- **Tests:** `tests/suites/test_harbour_life.gd`; screenshots in `tests/screenshots_16.gd`, `tests/screenshots_chartroom.gd`.
- **Change risks:** Icon ids in `_draw_icon` must match `ShoreEvents` data; unknown ids fall back to a dot. `get_choice_buttons()` skips queued-for-deletion buttons (tests rely on this after `show_outcome`).

### `src/ui/grocery_menu.gd`

- **Role:** class_name `GroceryMenu`, extends `SimplePanel`; harbour store for provisions, passage stock-up, replacement hat and lures, with a link to the fishmonger. Steady Hands: `Loc.t` on `lure.name` in the tackle list.
- **Depends on:** `GameSession` (get_location, get_provisions, get_provisions_price, get_funds, get_missing_provision_days, is_moored_in_harbour, buy_provisions, get_passage_store_days, get_vessel_definition, get_hat_price, get_hat, buy_hat, buy_lure, get_fishing, has_facility, format_money, PROVISIONS_PRICE_PER_DAY, REMOTE_WORK_PAY_PER_HOUR), `Provisions` (CAPACITY_DAYS, format_days), `FishingCatalog`, `HarbourFacilities.FISHMONGER`, `Loc`.
- **Signals:** declares `fishmonger_requested` (FishmongerButton); App connects it to `open_fishmonger`.
- **Signals (in):** `GameSession.funds_changed` (`_on_funds_changed`) and `fishing_changed` -> `refresh()`.
- **State:** writes via `GameSession.buy_provisions(days?)`, `buy_hat`, `buy_lure`.
- **Lifecycle:** `App.open_grocery()` (moored, GROCERY facility), from `ProvisionsMenu.grocery_requested`, `BoatyardMenu.grocery_requested` and `BoatArea.grocery_requested`.
- **Invariants:** everyday fill to `Provisions.CAPACITY_DAYS`; stock-up to `get_passage_store_days()`; the hat row is separate so provisions figures are unaffected.
- **Tests:** `tests/suites/test_hat.gd`, `tests/suites/test_living.gd`, `tests/suites/test_upkeep_ui.gd`, `tests/suites/test_visual_prototype.gd`, `tests/suites/test_boat_of_your_own.gd` (refresh after a fishmonger sale).
- **Change risks:** a new figure shown here that other screens can change needs its signal connected too (funds and catch are). Buy/BuyHat/StockUp buttons are exposed via getters used by tests.

### `src/ui/handbook_menu.gd`

- **Role:** class_name `HandbookMenu`, extends `SimplePanel` (1160 wide). Signal `first_voyage_requested`. Nodes: Search (LineEdit), Pages (ItemList: chapter headers disabled with empty metadata, pages with their id), PageTitle, PageText (in a ScrollContainer), FirstVoyageButton, TipsButton, CloseButton. `search(query)`, `listed()`, `show_page(id)`, `shown_page()`.
- **Depends on:** `Academy.search/page/category_title/fill/begin_first_voyage/reset_tips`.
- **State:** `_ids`, `_shown`.
- **Lifecycle:** pushed by `App.open_handbook(page)` (also over the pause menu); `App.toggle_handbook` (F1) closes it when on top.
- **Tests:** `tests/suites/test_academy.gd` (`[handbook]`).
- **Change risks:** none beyond the modal stack.

### `src/ui/harbour_moment.gd`

- **Role:** class_name `HarbourMoment`, extends PanelContainer (Golden Harbours). Properties set before `_ready`: `port_id`, `first_visit`, `special`, `picture`, `elevation`, `overcast`, `log_line`. `_ready` builds Stamp (MutedLabel: "✦ Special harbour · " if special, "First visit · <date>"), the inner `HarbourScene` (WIDTH−24 × `PICTURE_HEIGHT`) and centred labels (header "Arrived in %s.", description, log line). `_gui_input` left click → `dismiss()` (0.25 s fade, `TWEEN_PAUSE_PROCESS`, emits `dismissed`). static `light_of(elevation, morning)` → `&"night"` < −6°, `&"dawn"`/`&"dusk"` < 8°, else `&"day"`. static `window_spots(texture)` → `Array[Rect2]` (UV) cached in `_window_cache` by resource path: samples the middle `CROP` (0.42) every `SAMPLE_STEP` px, at most `MAX_WINDOWS`, one per 18 px cell; `_is_window` = 5 dark opaque samples (luminance ≤ 0.33) with opaque light wall (> 0.42) at `WALL_REACH` (12) px on ≥ 3 of 4 sides (rejects palm leaves against the sky).
- **Depends on:** `HarbourLooks` (through App), `PortCatalog`, `Simulation.format_game_time`, `Daylight.local_solar_hours`/`outside_colour`, `WaterLook.water_colour`, `GameSession`.
- **State:** the properties above; static `_window_cache`.
- **Lifecycle:** created by `App.show_harbour_moment`, added by `Toasts.show_moment` (`MOMENT_DURATION` 14 s, then fade and free).
- **Performance:** `HarbourScene._draw` only on show/resize; window sampling once per picture (~18 ms for four pictures, then ~0.01 ms cached, measured headless).
- **Tests:** `tests/suites/test_golden_harbours.gd`.
- **Change risks:** `get_messages()` reads its labels (tests look for the Log line inside it); a picture with pale windows (Symi) gets no lit windows by design.

### `src/ui/hat_badge.gd`

- **Role:** `class_name HatBadge`, extends PanelContainer; HUD indicator for hat state (`STATE_NONE` / `STATE_AT_RISK` / `STATE_MISSING`).
- **Depends on:** `GameSession` (`is_active`, `get_hat_status`, `is_hat_at_risk`), `HatState.LOST`, `HatArt.get_default().draw_slot`, `UiTheme.tint`, `Loc`.
- **Signals:** none declared; connects its child icon's `draw` to `_draw_icon`.
- **State:** read-only on GameSession; owns `_state`, `_time`, `_pulse`. Presentation only, nothing saved.
- **Lifecycle:** instanced in code by `Hud._ready()` (`hud.hat_badge`); `App` calls `hud.hat_badge.pulse()` on hat loss and uses `WARNING_SECONDS`, `LOST_SECONDS`, `LOST_HEADLINE` for its toasts.
- **Performance:** `_process` calls `refresh()` (a few GameSession reads) every frame and redraws the icon while visible.
- **Invariants:** `state_for_game()` is static and derives state solely from GameSession; visible iff state != `STATE_NONE`.
- **Tests:** `tests/suites/test_hat.gd`.
- **Change risks:** constants are shared with `App` toasts and asserted in test_hat (`AT_RISK_TEXT`, `LOST_HEADLINE`); `Hud.set_chart_mode` finds it by node name "HatBadge".

### `src/ui/haul_out_panel.gd`

- **Role:** `class_name HaulOutPanel`, extends `SimplePanel`; haul-out choice + animation + result dialog. Steady Hands: `Loc.t` on the upgrade name in the option list.
- **Depends on:** `GameSession` (`get_location`, `get_vessel_definition`, `get_boat_care`, `get_haul_out_extras`, `upgrade_price`, `service_quote`, `haul_out_quote`, `haul_out`, `format_money`, `get_funds`), `BoatCare` (`fouling`, `FOULING_NEEDED`, `get_upgrade`, `SERVICE_NAMES`), `VesselDefinition.HULL_CATAMARAN`, `HaulOutScene`, `SessionLog`, `Loc`.
- **Signals:** declares `time_requested(minutes)` (emitted in `_finish` with `_result.minutes`); App connects it to `_spend_yard_time` (→ `Simulation.spend_time_ashore`).
- **State:** writes game state only through `GameSession.haul_out(extras)` (the single transaction); logs `haul_out` to SessionLog. Owns `_options`, `_result`, `_finished`.
- **Lifecycle:** created by `App.open_haul_out()` (after `GameSession.service_refusal(BoatCare.SERVICE_HAUL_OUT)` check) and pushed on `ModalStack`.
- **Invariants:** `_finish` runs once (`_finished` guard); confirm disabled when quote cost > funds; after finishing the confirm button is rewired from `_on_confirm` to `close`.
- **Tests:** `tests/suites/test_boat_care.gd` (uses `set_option`, `finish_now`).
- **Change risks:** tween timing (`LIFT_SECONDS`, `SCRUB_SECONDS`) vs. tests that call `finish_now()`; the day is spent only via the signal, so disconnecting it silently skips time.

### `src/ui/haul_out_scene.gd`

- **Role:** `class_name HaulOutScene`, extends Control; procedural illustration of a travel lift raising the boat.
- **Depends on:** nothing outside Godot.
- **State:** `lift` (0..1) and `fouled` (0..1) with clamping setters that `queue_redraw()`; `catamaran`; `_drips` timer.
- **Lifecycle:** created and tweened only by `HaulOutPanel` (`_scene`, exposed via `get_scene()`).
- **Performance:** `_process` redraws only while lifting or for ~3 s after fully lifted.
- **Tests:** none found directly; exercised (indirect) through `tests/suites/test_boat_care.gd` via HaulOutPanel.
- **Change risks:** property names `lift` / `fouled` are tweened by string in HaulOutPanel.

### `src/ui/hud.gd`

- **Role:** `class_name Hud`, extends Control; gameplay overlay (area/location, clock + PAUSED, route/voyage, status line, wind, warning panel, prompt, shortcut strip) and host of sub-panels. Steady Hands: `_stack_right_column()` (from `refresh` and `_set_route_lines`): route width = `ROUTE_PANEL_WIDTH` with a course else `ROUTE_PANEL_COMPACT`, capped by the room right of `ClockPanel`; `sailing_panel.offset_top` = route bottom + `COLUMN_GAP` (independent of the warning); `WarningPanel` below Trip Details (or the route panel) with `offset_bottom = offset_top` (sizes to content; was a fixed 124 px under which Trip Details was pushed). `_keep_prompt_clear()` (from `_process`) shifts `PromptPanel` by the overlap with `ChartPlotter`/`RadarPanel`. Offsets are written only when they change.
- **Depends on:** `hud.tscn` (unique-name nodes, `TimeControls` inside `ClockPanel`), `GameSession`, `Simulation` (`format_game_time`, `get_wind_at`, `get_eta`, `estimate_route_seconds`, `format_duration`), `PortCatalog`, `PlannedRoute.describe`, `AnchorSite.holding_text`, `PropulsionState.wind_side`, `VesselCondition`, `Provisions`, `WindField`, `WeatherSample`/`WeatherModel.HAZARD_CAUTION`, `SessionState`, `Loc`; creates `HatBadge`, `AboardBadge`, `PassagePanel`, `SailingPanel`, `ChartPlotter`, `RadarPanel`.
- **Signals:** declares `menu_requested`, `chart_requested` (warning chart button or PassagePanel), `save_requested` (PassagePanel Save). App connects them to `open_pause_menu`, `open_chart_from_warning`, `open_save_menu`.
- **State:** read-only on game state; caches `_planned_seconds` (re-estimated when route key changes or after 1800 game-seconds), `_chart_mode`, `_warning_pending`.
- **Lifecycle:** instanced scene under `HudLayer` (a `UiScaleLayer`) in `app.tscn`; App calls `set_area`, `set_prompt`, `show_warning`, `hide_warning`, `set_chart_mode`.
- **Performance:** `refresh()` every frame while visible; route-time estimate cached.
- **Invariants:** static `describe_wind()` / `describe_status()` are reused by `PassagePanel`, `SailingPanel`, `ChartPlotter`, `AnchorMenu`, `WorldMap`; `CHART_SIDEBAR_WIDTH` is also used by App for toast placement.
- **Tests:** `tests/suites/test_cockpit_ui.gd`, `test_chartroom_ui.gd`, `test_long_passage.gd`, `test_cozy_polish.gd`, `test_branding.gd`; `app.hud` is read in many more suites.
- **Change risks:** `set_chart_mode` toggles children by node name strings; changing `describe_wind` text ("Wind " prefix is trimmed by SailingPanel) ripples into other panels and string-matching tests.

### `src/ui/language_picker.gd`

- **Role:** `class_name LanguagePicker`, extends `SimplePanel`; first-launch language choice.
- **Depends on:** `Loc.LANGUAGES`, `SettingsManager` (`set_language`, `save`), `OS.get_locale_language` (default focus).
- **Signals:** declares `chosen(locale)` (emitted after close); App does not connect it.
- **State:** writes the language to settings (settings.cfg via SettingsManager.save), never to a save game.
- **Lifecycle:** created by `App.show_language_picker()` (deferred from `_connect_main_menu` when `SettingsManager.has_chosen_language()` is false and no modal is open).
- **Invariants:** `handle_back()` is a no-op (Esc cannot dismiss); its labels/buttons disable auto-translation.
- **Tests:** `tests/suites/test_localization.gd`.
- **Change risks:** a picker that cannot close blocks the main menu on first launch.

### `src/ui/loading_screen.gd`

- **Role:** `class_name LoadingScreen`, extends CanvasLayer (layer 100, `PROCESS_MODE_ALWAYS`); start-up splash that warms caches. I022: `_night` is always true; the sky and sea are drawn as two vertex-coloured polygons with the main menu's gradient (`SKY_TOP/SKY_LOW/SEA_TOP/SEA_LOW`, horizon `HORIZON` 0.62) and the night logo `LOGO` (480) at 400×188; tagline and status take `ink_soft` night colours. project.godot's boot splash: navy `bg_color`, `stretch_mode=0` (native size), `little_captains_hat_logo_240.png`.
- **Depends on:** `UiTheme.color_at(role, 1.0)` (night colours only), `PortCatalog.get_default()`, `SeaRouter.get_default()` (on `WorkerThreadPool`), `VesselCatalog.get_default()`, branding PNGs (preloaded), `Loc`.
- **Signals:** declares `finished` (after fade, before `queue_free`).
- **State:** static `shown` (once per process); `_step`, `_task`, `_done`.
- **Lifecycle:** created by `App._ready()` when `LoadingScreen.wanted()` (not shown yet and display is not headless); frees itself.
- **Performance:** redraws its canvas every frame; the SeaRouter build runs on a worker thread and is polled with `is_task_completed`.
- **Invariants:** steps run in order; no artificial wait; mouse ignored so input reaches the menu below.
- **Tests:** `tests/suites/test_cozy_polish.gd`.
- **Change risks:** `SeaRouter.get_default()` on a worker thread must stay thread-safe; never shown headless, so most tests do not cover it.

### `src/ui/main_menu.gd`

- **Role:** `class_name MainMenu`, extends `UiScaleLayer`; title screen that only emits intents.
- **Depends on:** `main_menu.tscn`, `SaveManager` (`slots_changed`, `get_most_recent_valid_slot`, `get_slot_info`, `get_all_slot_info`), `SettingsManager.language_changed`, `DevGuides.is_available`, `GameVersion`, `LegacySaves.count_importable`, `SaveLoadMenu.format_timestamp`, `Loc`.
- **Signals:** declares `new_game_requested`, `continue_requested`, `load_requested`, `settings_requested`, `quit_requested`, `dev_guides_requested`, `import_requested`; App wires all in `_connect_main_menu`.
- **State:** read-only.
- **Lifecycle:** scene loaded by `App.show_main_menu()` via the screen router (`main_menu_scene`); App calls `refresh_saves()`/`focus_default()` when the modal stack empties.
- **Tests:** `tests/suites/test_gameplay_flow.gd`, `test_branding.gd`, `test_dev_guides.gd`, `test_localization.gd`, `test_life_aboard.gd`.
- **Change risks:** Continue enablement depends on SaveManager status; calls `super._ready()` (UiScaleLayer) and must keep doing so.

### `src/ui/markdown_lite.gd`

- **Role:** `class_name MarkdownLite`, extends RefCounted; static Markdown → BBCode converter.
- **Depends on:** `UiTheme.color` (`code`, `ink_soft`, `link`), `RegEx`.
- **State:** none (all static).
- **Lifecycle:** static helper used by `DevGuidesMenu`.
- **Invariants:** `[` is escaped as `[lb]` before any tags are added; code spans are masked with `CODE_MARK` during emphasis processing; wrapped lines are joined.
- **Performance:** compiles RegEx objects per call (fine for guide-sized text).
- **Tests:** `tests/suites/test_dev_guides.gd`.
- **Change risks:** the emphasis regexes and the `[lb]` escaping interact; link regex expects the escaped form `[lb]text](url)`.

### `src/ui/modal_panel.gd`

- **Role:** `class_name ModalPanel`, extends Control; base class for every dialog on the `ModalStack`.
- **Depends on:** `ModalStack` (typed `stack` field).
- **Signals:** declares `closed` (from `close()`), `notification_requested(text)` (from `notify()`); the stack connects both.
- **State:** `stack` (set by `ModalStack.push`).
- **Lifecycle:** abstract base; subclasses include `SimplePanel`, `PauseMenu`, `SettingsMenu`, `SaveLoadMenu`, `SleepMenu`, `NewGameMenu`, `ProvisionsMenu`, `RescueDialog`, `ConfirmDialog`, `ActionWheel`, `BoatyardMenu`, `DevGuidesMenu`, `DevTestPanel`.
- **Invariants:** `handle_back()` defaults to `close()`; `focus_default()` is called deferred by the stack. `UiTheme` recolours a child `ColorRect` named "Dim" of any ModalPanel.
- **Tests:** referenced in `tests/suites/test_chartroom_ui.gd`, `test_upkeep_ui.gd`, `test_catch_and_cove_journey.gd`; (indirect) every UI suite.
- **Change risks:** signature changes break all dialogs; closing must go through `close()` so the stack cleans up.

### `src/ui/modal_stack.gd`

- **Role:** `class_name ModalStack`, extends Control; stack of open `ModalPanel`s (only top visible).
- **Depends on:** `ModalPanel`, `ConfirmDialog` (via exported `confirm_dialog_scene`).
- **Signals:** declares `stack_changed(depth)` (push/close/clear), `notification_requested(text)` (forwarded from modals). App connects them to `_on_modal_stack_changed` (pauses the tree while depth > 0 in gameplay) and `notify`.
- **State:** `_modals: Array[ModalPanel]`.
- **Lifecycle:** node `ModalLayer/ModalStack` in `app.tscn` (`app.modals`); App calls `push`, `clear`, `handle_back` (Esc), `confirm`, `get_top`.
- **Invariants:** closed modal is removed and freed; the one below is re-shown and refocused only if the closed one was on top; `closed` is connected `CONNECT_ONE_SHOT`.
- **Tests:** `tests/suites/test_gameplay_flow.gd`; `app.modals` is used by most UI suites.
- **Change risks:** game pausing depends on `stack_changed`; `confirm()` is awaited by SettingsMenu, SaveLoadMenu and App flows.

### `src/ui/new_game_menu.gd`

- **Role:** `class_name NewGameMenu`, extends `ModalPanel`; companion selection for a new game. I022: builds `difficulty` (DifficultyPicker) and a question label before `Center/Panel/VBox/Buttons`; `start_requested(companion_kind, level)`.
- **Depends on:** `new_game_menu.tscn` (`%CatButton`, `%DogButton`, `%Preview`, `%Description`, `%StartButton`, `%CancelButton`), `CompanionState` (`DEFAULT_KIND`, `KIND_CAT`, `KIND_DOG`), `ShipCompanion.show_kind`, `Loc`.
- **Signals:** declares `start_requested(companion_kind)`; App connects it to `start_new_game`.
- **State:** `companion_kind`.
- **Lifecycle:** instantiated from `new_game_menu_scene` by `App.open_new_game_menu()` and pushed on the stack.
- **Tests:** `tests/suites/test_gameplay_flow.gd`, `test_companion_art.gd`, `test_life_aboard.gd`.
- **Change risks:** companion kind feeds the new session's state.

### `src/ui/passage_panel.gd`

- **Role:** `class_name PassagePanel`, extends PanelContainer; Long Passage deck panel with passage-rate controls.
- **Depends on:** `GameSession` (voyage, position, provisions, condition, care levels, `take_quiet_nibbles`, `voyage_started`), `Simulation` (`PASSAGE_RATES`, `start_passage`, `stop_passage`, `passage_rate`, `passage_interrupted`, `get_eta`, `get_hazards_ahead`, `DISPLAY_HORIZON_HOURS`, `get_wind_at`), `Hud.describe_wind`, `GeoMath.format_position`, `Provisions`, `BoatCare`, `VesselCondition`, `PortCatalog`, `Loc`.
- **Signals:** declares `chart_requested`, `save_requested` (both stop the passage first; Hud re-emits them). Connects `Simulation.passage_interrupted` and `GameSession.voyage_started`.
- **State:** writes only via `Simulation.start_passage/stop_passage`; consumes `GameSession.take_quiet_nibbles()` on interruption. Caches outlook text per voyage revision / 1800 game-seconds.
- **Lifecycle:** created in code by `Hud._ready()` (`hud.passage_panel`).
- **Performance:** `refresh()` every frame while visible; hazards query throttled.
- **Invariants:** `should_show()` = active, underway, not anchored, total ≥ `LONG_VOYAGE_NM` (60). `RATE_LABELS` and static `_thousands` are reused by `VoyageMap`; VoyageMap also reads `get_stopped_text()` and expects the "Normal time: " prefix.
- **Tests:** `tests/suites/test_long_passage.gd`, `test_cockpit_ui.gd`.
- **Change risks:** `RATE_LABELS` size must match `Simulation.PASSAGE_RATES`; the "Normal time: " prefix is parsed by VoyageMap.

### `src/ui/pause_menu.gd`

- **Role:** `class_name PauseMenu`, extends `ModalPanel`; in-game pause menu that only emits intents. I022: `difficulty_requested` signal; a code-built `DifficultyButton` after `SettingsButton`. I022: `HandbookButton` built in code after `DifficultyButton`; signal `handbook_requested`.
- **Depends on:** `pause_menu.tscn`, `DevTools.is_enabled`.
- **Signals:** declares `save_requested`, `log_requested`, `load_requested`, `settings_requested`, `main_menu_requested`, `dev_tests_requested`; App wires them in `open_pause_menu()`.
- **Lifecycle:** instantiated from `pause_menu_scene` by `App.open_pause_menu()` (Esc or `Hud.menu_requested`).
- **Tests:** `tests/suites/test_gameplay_flow.gd`, `test_upkeep_ui.gd`; opened via `open_pause_menu` in `test_hat.gd`, `test_captains_log.gd`, `test_localization.gd`, `test_well_run_ship.gd` and others.
- **Change risks:** the dev button is added only when DevTools is enabled.

### `src/ui/postcard_menu.gd`

- **Role:** class_name `PostcardMenu`, extends `SimplePanel`. Signals `make_requested` (after `GameSession.set_postcard_draft`), `scrapbook_requested`. Nodes: Subject/Caption/Layout OptionButtons, Preview (`PostcardView`), Note, buttons ScrapbookButton, AbandonButton (only with a draft), CancelButton, MakeButton. `chosen_card()`, `selected_subject()`, `choose(index, caption, layout)` (tests), `_resume_draft()`.
- **Depends on:** `Pastimes`, `GameSession.get_pastimes/postcard_minutes_left/set_postcard_draft/abandon_postcard`, `Simulation.format_duration`.
- **State:** `_subjects` (snapshot of `Pastimes.subjects()` at open).
- **Lifecycle:** pushed by `App.open_postcards()`; App connects `make_requested` → `make_postcard` (deferred) and `scrapbook_requested` → push `ScrapbookMenu`.
- **Tests:** `tests/suites/test_captains_other_life.gd` (`[menus]`).
- **Change risks:** Esc closes (ModalPanel); `make_requested` closes all modals through `App.pass_time`.

### `src/ui/postcard_view.gd`

- **Role:** class_name `PostcardView`, extends Control (600×390 minimum, mouse ignored). `card` setter (finds the picture, redraws), `caption()`; `_draw` per layout ("classic", "snapshot", "banner"), `_draw_scene` (gradient sky/sea per kind, rain lines for weather, sun for sunset, `_draw_boat` for voyage/weather/sunset), the art fitted into the picture box.
- **Depends on:** `Pastimes.caption_text/args_for`, `HarbourLooks.picture_for`, `FishArt.thumbnail/has_art`, `CompanionVisualSet.for_kind(...).get_texture(&"resting")`.
- **State:** `card`, `_picture`.
- **Lifecycle:** child of `PostcardMenu` (Preview) and `ScrapbookMenu` (Card).
- **Tests:** `tests/suites/test_captains_other_life.gd` (`[menus]`, screenshots i022_postcard, i022_scrapbook).
- **Change risks:** draw calls only, redrawn on change, not per frame.

### `src/ui/provisions_menu.gd`

- **Role:** `class_name ProvisionsMenu`, extends `ModalPanel`; provisions locker read-out.
- **Depends on:** `provisions_menu.tscn`, `GameSession` (`get_provisions`, `get_vessel_definition`, `is_moored_in_harbour`, `has_facility`, `get_passage_store_days`, `get_provisions_price`, `get_location`, `format_money`), `Provisions`, `HarbourFacilities.GROCERY`, `Loc`.
- **Signals:** declares `grocery_requested`; App connects it to `open_grocery`.
- **State:** read-only; refreshes every frame while visible.
- **Lifecycle:** instantiated by `App.open_provisions()` (from the cabin's provision station, `ProvisionDisplay`).
- **Tests:** `tests/suites/test_upkeep_ui.gd` (`get_values`).
- **Change risks:** grocery button visibility/disabled rules mirror facility and fullness logic.

### `src/ui/publish_menu.gd`

- **Role:** `class_name PublishMenu`, extends `SimplePanel`; confirmation for publishing a travel update.
- **Depends on:** `GameSession` (`get_publish_quote`, `get_lifetime_renown`, `format_money`), `Loc`.
- **Signals:** declares `publish_confirmed`; App connects it to `publish_travel_update` (which calls `GameSession.publish_travel_update`).
- **State:** read-only; the quote is taken once in `_ready`.
- **Lifecycle:** created by `App.open_publish_menu()` from `CaptainsLogMenu.publish_requested` or `WorkMenu.publish_requested`.
- **Tests:** `tests/suites/test_publishing.gd`.
- **Change risks:** publish button disabled iff `quote.error` non-empty; the quote does not refresh while open.

### `src/ui/radar_panel.gd`

- **Role:** `class_name RadarPanel`, extends PanelContainer; north-up traffic scope with up to three advice lines. `should_show()` requires `GameSession.is_underway()` (the wheel's Radar item exists only underway; before, `shown` kept it up in harbour with no way to close it); `shown` is kept for the next voyage, and traffic is only queried underway.
- **Depends on:** `Simulation` (`traffic_risks`, `RISK_NONE/CAUTION/DANGER`, `get_current_heading`), `GameSession`, `TrafficModel.kind_name`, `WindField.compass_name`, `Loc`.
- **State:** static `shown` and `range_index` (per run, not saved); `on_deck` Callable set by Hud; `_risks` cache.
- **Lifecycle:** created in code by `Hud._ready()` (`hud.radar_panel`); App's action wheel toggles `RadarPanel.shown`.
- **Performance:** traffic queried every `REFRESH_SECONDS` (0.2 s), not per frame; scope redrawn at that rate.
- **Invariants:** `should_show()` = active and on deck and (shown or underway with concern ≥ caution); `_risks` assumed sorted most urgent first (`get_concern` reads `[0]`).
- **Tests:** `tests/suites/test_captains_watch.gd`.
- **Change risks:** static state persists across sessions in the same process (tests); offsets are read as `offset_nm` with y north-up.

### `src/ui/reel_dial.gd`

- **Role:** `class_name ReelDial`, extends Control; draws a `TimingCheck` (ring, target arc, Perfect zone, needle, checks, line grip).
- **Depends on:** `TimingCheck` (`target_deg`, `arc_deg`, `get_perfect_deg`, `angle`, `checks_needed`, `hits`, `line_control`, `get_line_control`), `ReelTiming.PRESS_*`, `SettingsManager.get_reduce_flashing`, `Loc`.
- **Signals:** declares `pressed` (left click on the dial).
- **State:** `timing` (set by owner), `_flash` timer.
- **Lifecycle:** created in code by `FishingMenu` (node "Dial") and `AnchorMenu` (magic anchor); the menus step the timing.
- **Performance:** redraws every frame.
- **Tests:** `tests/suites/test_chartroom_ui.gd`.
- **Change risks:** angle convention is 0 = top, clockwise (draw subtracts 90°).

### `src/ui/rescue_dialog.gd`

- **Role:** `class_name RescueDialog`, extends `ModalPanel`; report after `GameSession.rescue()`.
- **Depends on:** `rescue_dialog.tscn`, `PortCatalog`, `GameSession` (`get_vessel_definition`, `format_money`), `Loc`.
- **State:** `info` dict (`port_id`, `fee`, `funds_after`) set via `setup()` before `_ready`.
- **Lifecycle:** instantiated by `App._on_rescued()` (connected to `GameSession.rescued`) after `modals.clear()`; App sets `_rescue_open` and clears it on `closed` so the tree un-pauses.
- **Tests:** `tests/suites/test_upkeep_ui.gd`.
- **Change risks:** `setup()` must be called before adding to the tree.

### `src/ui/sail_trim_panel.gd`

- **Role:** `class_name SailTrimPanel`, extends `SimplePanel`; manual sail-trim dialog with slider, sketch and feedback.
- **Depends on:** `GameSession` (`get_sail_trim`, `set_sail_trim`, `get_propulsion`, `sail_trim_changed`, `propulsion_changed`), `SailTrim` (`feedback`, `percent`, `best`), `PropulsionState`, `UiTheme.color`, `Loc`.
- **Signals:** none declared; connects `GameSession.sail_trim_changed` and `propulsion_changed` to `refresh`.
- **State:** writes trim only via `GameSession.set_sail_trim(auto, value)`.
- **Lifecycle:** created by `App.open_sail_trim()` (underway, not anchored, no other modal).
- **Invariants:** handles `move_left/right`, `ui_left/right`, `ui_accept`, `sail_trim` in `_unhandled_input`; slider uses `set_value_no_signal` on refresh to avoid feedback loops.
- **Tests:** `tests/suites/test_sail_trim.gd`.
- **Change risks:** the GameSession signal connections are not disconnected explicitly (relies on freeing).

### `src/ui/sailing_panel.gd`

- **Role:** `class_name SailingPanel`, extends PanelContainer; underway instrument panel (speed, heading, wind, trim, next leg, turn, remaining).
- **Depends on:** `GameSession`, `Simulation` (`get_wind_at`, `get_current_heading`, `get_weather_at`, `format_duration`, `format_game_time`, `get_eta`), `WorldMap.get_next_turn()`, `Hud.describe_wind`, `PropulsionState`, `SailTrim`, `GeoMath.segment_index_at`, `WindField`, `PortCatalog`, `SettingsManager.get_reduce_flashing`, `UiTheme.color`, `Loc`.
- **State:** static `collapsed` (per run); `_course_key`, `_last_course`, cached forecast keyed by voyage revision, turn and half hour.
- **Lifecycle:** created in code by `Hud._ready()` (`hud.sailing_panel`).
- **Performance:** `refresh()` every frame while underway; forecast throttled to once per leg/half hour; labels only rewritten on change.
- **Invariants:** `should_show()` = active and underway; a heading pulse fires only on segment change with > `COURSE_CHANGE_DEG` difference (not on the first observation).
- **Tests:** `tests/suites/test_cockpit_ui.gd`, `test_sail_trim.gd`, `test_anchorage.gd`, `test_cozy_polish.gd`, `test_chartroom_ui.gd`.
- **Change risks:** row keys used by `get_value()` in tests; `_short_time` assumes the `format_game_time` word layout.

### `src/ui/sailmaker_menu.gd`

- **Role:** `class_name SailmakerMenu`, extends `TradePanel`; rig service plus cosmetic sailcloth.
- **Depends on:** `GameSession` (`service_refusal`, `service_quote`, `perform_service`, `get_sail_cloth`, `sail_cloth_price`, `order_sail_cloth`, `has_facility`, `get_funds`), `BoatCare.SERVICE_RIG`, `HarbourTrades.get_sail_cloths/get_sail_cloth`, `HarbourFacilities.SAILMAKER`, `SessionLog`, `Simulation.format_duration`, `Loc`.
- **Signals:** declares `time_requested(minutes)` (after a service); App connects it to `_spend_yard_time`.
- **State:** writes via `GameSession.perform_service` and `GameSession.order_sail_cloth`; logs `boat_service` / `sail_cloth`.
- **Persistence:** sail cloth is per-vessel game state (owned by GameSession).
- **Lifecycle:** created by `App.open_sailmaker()` → `_open_trade(HarbourFacilities.SAILMAKER, …)` (freed if the facility is missing).
- **Invariants:** service is the same BoatCare rig service as the boatyard's (no second model); cloth is cosmetic only.
- **Tests:** `tests/suites/test_boat_of_your_own.gd`.
- **Change risks:** row ids `service` and `cloth_<id>` are used by `get_row_button` in tests.

### `src/ui/save_load_menu.gd`

- **Role:** `class_name SaveLoadMenu`, extends `ModalPanel`; slot list in SAVE or LOAD mode.
- **Depends on:** `save_load_menu.tscn`, `SaveManager` (`get_all_slot_info`, `get_slot_info`, `QUICKSAVE_SLOT`, `Status`, `SlotInfo`, `save_to_slot`, `slots_changed`), `GameSession` (`get_state_snapshot`, `mark_saved`), `ModalStack.confirm` (via `stack`), `Loc`.
- **Signals:** declares `load_requested(slot)` (LOAD mode); App handles the load.
- **State:** SAVE mode writes `GameSession.get_state_snapshot()` to a slot via SaveManager and calls `mark_saved()`.
- **Lifecycle:** instantiated from `save_load_menu_scene` by App (`setup(Mode.SAVE|LOAD)` before adding).
- **Persistence:** writes save slots; never saves to the quicksave slot (quicksave is listed only in LOAD mode).
- **Invariants:** asks before overwriting a non-empty slot; on failure keeps the previous save and reports `error_string(err)`. Static `format_timestamp` (local time) is reused by `MainMenu`.
- **Tests:** `tests/suites/test_gameplay_flow.gd`, `test_long_passage.gd`.
- **Change risks:** `setup()` must precede `_ready`; `_refresh` rebuilds all buttons on `slots_changed`.

### `src/ui/scrapbook_menu.gd`

- **Role:** class_name `ScrapbookMenu`, extends `SimplePanel`. `page`, `view` (`PostcardView` "Card"), `turn(delta)`, When label, PreviousButton/NextButton/CloseButton; ui_left/ui_right and move_left/move_right turn pages.
- **Depends on:** `GameSession.get_pastimes().postcards`, `Simulation.format_game_time`.
- **State:** `page` (0 = newest).
- **Lifecycle:** pushed by App from `PostcardMenu.scrapbook_requested`.
- **Tests:** `tests/suites/test_captains_other_life.gd` (`[menus] the scrapbook opens on the newest card`).
- **Change risks:** none beyond the modal stack.

### `src/ui/settings_menu.gd`

- **Role:** `class_name SettingsMenu`, extends `ModalPanel`; shared settings dialog with live preview and Apply/Discard. I022: `BUS_LABELS` has `Wind`; `_play_test_sound(&"Wind")` plays `WIND_TEST` (wind_breeze.wav, not looping) as a one-shot on the Wind bus. I022: `_tips` CheckBox ("Tips" row after Reduce motion) → `SettingsManager.set_tips_enabled`; synced in `_sync_controls`. Steady Hands: `FitScroll.wrap([AudioSection, DisplaySection], $Center/Panel)` at the end of `_ready`.
- **Depends on:** `settings_menu.tscn`, `SettingsManager` (snapshot/restore, volumes, window mode, vsync, UI scale, art style, course view, reduce flashing, flash intensity, reduce motion, UI light, language, save, defaults), `Loc.LANGUAGES`, `SessionLog.get_folder`, `AudioManager`, `MusicDirector`, `ModalStack.confirm`.
- **State:** `_saved` snapshot for unapplied-change detection; all writes go through SettingsManager.
- **Lifecycle:** instantiated from `settings_menu_scene` by `App.open_settings()` (from main menu and pause menu).
- **Persistence:** Apply → `SettingsManager.save()` (settings file, not the game save).
- **Invariants:** leaving with unapplied changes asks, then `restore_snapshot(_saved)`; UI scale applied on drag end or when the mouse is not pressed.
- **Tests:** `tests/suites/test_gameplay_flow.gd`, `test_visual_prototype.gd`; opened via `open_settings` in `test_localization.gd`, `test_soundtrack.gd`, `test_chartroom_ui.gd`.
- **Change risks:** rows are appended to the grid found via `_ui_scale.get_parent().get_parent()` (scene-structure dependent); option indices must match `SettingsManager` arrays.

### `src/ui/simple_panel.gd`

- **Role:** `class_name SimplePanel`, extends `ModalPanel`; code-built centred dialog helpers (`_build`, `_label`, `_button`).
- **Depends on:** Godot controls only; its "Dim" ColorRect is recoloured by `UiTheme` (indirect).
- **State:** `_box`, `_buttons`.
- **Lifecycle:** base class for `WorkMenu`, `GroceryMenu`, `CookingMenu`, `TrophyMenu`, `AnchoragePrompt`, `AnchorMenu`, `HaulOutPanel`, `PublishMenu`, `SailTrimPanel`, `LanguagePicker`, `BoatCareMenu`, `GoAshoreMenu`, `VhfDialog`, `CaptainsLogMenu`, `FishingMenu`, `TradePanel`.
- **Invariants:** `_build()` must run before `_label`/`_button`; node names ("Title", "Buttons", "Panel", "Dim") are looked up by subclasses, tests and UiTheme.
- **Tests:** none found directly; (indirect) every suite that opens one of its subclasses.
- **Change risks:** layout or naming changes hit many dialogs at once.

### `src/ui/sleep_menu.gd`

- **Role:** `class_name SleepMenu`, extends `ModalPanel`; choose 1–12 hours of sleep.
- **Depends on:** `sleep_menu.tscn`, `SettingsManager` (`get_sleep_hours`, `set_sleep_hours`), `GameSession` (`is_underway`, `is_paused`, `get_game_time`), `Simulation.format_game_time`, `Loc`.
- **Signals:** declares `sleep_requested(hours)`; App connects it to `sleep_for`.
- **State:** `hours`; remembered via SettingsManager (`set_sleep_hours(hours, false)` while changing, persisted on Sleep).
- **Lifecycle:** instantiated by `App.open_sleep_menu()` (from BoatArea or WorldMap `sleep_requested`, or the action wheel).
- **Tests:** `tests/suites/test_gameplay_flow.gd`, `test_chart_and_pause.gd`, `test_cozy_polish.gd`, `test_vessels.gd`, `test_catamaran_cabin.gd`, `test_life_aboard.gd`.
- **Change risks:** bounds `MIN_HOURS`/`MAX_HOURS` clamp the stored preference.

### `src/ui/theme/ui_theme.gd`

- **Role:** no class_name, extends Node; autoload `UiTheme` that rebuilds and recolours the project Theme from day/night role palettes. Steady Hands: `_target_blend()` is now a switch (1 below `SWITCH_AT` −1° ± `HYSTERESIS` 0.5°, chosen by `is_night()`), not `1 − smoothstep(−6°, +4°)`; the old blend parked the interface half-way for the whole twilight with ink ≈ surface (1.0:1). `color_at()` snaps `TEXT_ROLES` to the nearer end (≥ 2.5:1 mid-fade); `color()` delegates to it. `MAX_RATE` still eases each change over ≈ 4 s.
- **Depends on:** `ThemeDB.get_project_theme()`, Barlow fonts, `SettingsManager` (`get_ui_light`, `ui_light_changed`), `GameSession` (position, time), `Daylight.sun_elevation`, `ModalPanel` (for "Dim" detection).
- **Signals:** declares `palette_changed` (after every applied blend); connects `SettingsManager.ui_light_changed` → `set_mode` and `get_tree().node_added` → `_on_node_added`.
- **State:** `theme`, `blend` (0 day … 1 night), `_mode`, style-box/colour specs, weak refs to dims and tinted controls.
- **Lifecycle:** autoload (`project.godot`: `UiTheme="*res://src/ui/theme/ui_theme.gd"`).
- **Persistence:** none; the mode comes from SettingsManager (settings file).
- **Performance:** re-evaluates every `CHECK_SECONDS` (0.25 s), applies only steps ≥ `MIN_STEP`, rate-limited by `MAX_RATE`; one `theme.emit_changed()` per blend with theme signals blocked during the rebuild.
- **Invariants:** style boxes are created once in `_build()` and only recoloured; unknown roles return MAGENTA; `tint()` is idempotent per role.
- **Tests:** `tests/suites/test_well_run_ship.gd`, `test_chartroom_ui.gd`.
- **Change risks:** removing the signal blocking causes whole-tree refresh storms; `App.snap_light()` calls the private `_target_blend()`; many drawings read `color(role)` and `blend` directly.

### `src/ui/time_controls.gd`

- **Role:** `class_name TimeControls`, extends HBoxContainer; Pause / 1× / 5× / 20× bar.
- **Depends on:** `GameSession` (`set_paused`, `set_time_scale`, `is_paused`, `get_time_scale`, signals `time_scale_changed`, `pause_changed`, `state_replaced`, `session_started`), `SessionState.TIME_SCALES`, `Loc`.
- **State:** writes pause and time scale through GameSession only.
- **Lifecycle:** node in `hud.tscn` (`ClockPanel/HBox/TimeControls`).
- **Invariants:** buttons use `FOCUS_NONE`; `_sync` uses `set_pressed_no_signal` so syncing never re-triggers actions.
- **Tests:** `tests/suites/test_chart_and_pause.gd` (only checks no second instance exists in the chart sidebar).
- **Change risks:** speed button tooltips index by position in `SessionState.TIME_SCALES` (three entries assumed).

### `src/ui/time_passage.gd`

- **Role:** `class_name TimePassage`, extends CanvasLayer (layer 105, `PROCESS_MODE_ALWAYS`); fade-to-black date/clock card for sleep and dawn/dusk.
- **Depends on:** `Loc` (`t`, `month`, `weekday`), `Time`, the scene tree pause.
- **Signals:** declares `finished` (after fade-in, before `queue_free`).
- **State:** static `enabled` (false in tests), static `headless_ok`; `_running`, `_skip`, `_was_paused`.
- **Lifecycle:** created by `App.sleep_for()` (`play_sleep`) and `App.play_new_light()` (`play_card`, triggered by `DayNightWatch`); frees itself.
- **Invariants:** pure presentation; the caller's `work` Callable performs the simulation once under the black; restores the tree's prior pause state; `is_shown()` false when disabled, headless (unless `headless_ok`) or `--no-time-passage`. `NIGHT_INK` is reused by `VoyageMap`; static `date_text` by VoyageMap.
- **Tests:** `tests/suites/test_well_run_ship.gd`, `test_localization.gd`; `tests/test_runner.gd` sets `enabled = false`.
- **Change risks:** awaits on tweens/frames; a missing `finished` would leave App awaiting forever and the tree paused.

### `src/ui/toasts.gd`

- **Role:** `class_name Toasts`, extends VBoxContainer; transient notification stack. I021: `show_card(title, text, picture)` adds an "ArrivalCard" panel (AtlasTexture crop of the middle two-fifths of the strip, `CARD_DURATION` 6 s, mouse ignored); `get_messages()` now joins every Label in a panel, so cards and plain notices read the same. Golden Harbours: `show_moment(moment, duration = MOMENT_DURATION)` (14 s) adds a `HarbourMoment` with the same `MAX_VISIBLE` eviction and a fade tween.
- **Depends on:** theme variation `ToastPanel`.
- **State:** child panels (max `MAX_VISIBLE` = 3; oldest removed first).
- **Lifecycle:** node `ToastLayer/ToastArea/Toasts` in `app.tscn` (`app.toasts`); App routes `notify()` and hat/anchor messages through `show_message`.
- **Invariants:** `PROCESS_MODE_ALWAYS` and tweens with `TWEEN_PAUSE_PROCESS`, so toasts work while paused; `get_messages()` skips panels queued for deletion.
- **Tests:** `tests/suites/test_hat.gd`; `app.toasts.get_messages()` is read in many suites (e.g. `test_anchor_life.gd`, `test_captains_log.gd`, `test_chart_and_pause.gd`).
- **Change risks:** tests assert message text and counts; changing the cap or durations can break them.

### `src/ui/trade_panel.gd`

- **Role:** `class_name TradePanel`, extends `SimplePanel`; shared harbour-trade layout (rows with one price button).
- **Depends on:** `GameSession` (`funds_changed`, `home_changed`, `boat_care_changed`, `get_funds`, `format_money`), `Loc`.
- **Signals:** connects `GameSession.funds_changed`, `home_changed`, `boat_care_changed` → `refresh`.
- **State:** `_rows` (id → Button), `_list`, `_funds`.
- **Lifecycle:** base for `ChandleryMenu`, `SailmakerMenu`, `FishmongerMenu`, `CabinHomeMenu`; opened via `App._open_trade` (facility check) or directly (CabinHomeMenu).
- **Invariants:** subclasses override `refresh()` and call `super.refresh()`; `get_row_button(id)` / `get_row_ids()` are the test-facing API.
- **Tests:** `tests/suites/test_boat_of_your_own.gd`, `test_magic_anchor.gd`.
- **Change risks:** `refresh` may be called before `_build_trade` (guarded by `_funds` null check); subclasses must guard `_rows` likewise.

### `src/ui/trophy_menu.gd`

- **Role:** `class_name TrophyMenu`, extends `SimplePanel`; trophy board plaques and fishing record.
- **Depends on:** `GameSession.get_fishing()` (`trophies`, `records`, totals), `FishingCatalog` (`get_species_name`, `rarity_name`, `rarity_of`, `grade`), `FishArt.thumbnail`, `CatchBadge`, `Loc`.
- **State:** read-only.
- **Lifecycle:** created by `App.open_trophies()` (from the cabin `TrophyBoard`).
- **Invariants:** static `describe_trophies()` / `describe_record()`; plaques pair with `describe_trophies()` lines by index.
- **Tests:** `tests/suites/test_fishing.gd`.
- **Change risks:** line format is asserted in tests (`"1.  <species>"`).

### `src/ui/ui_scale_layer.gd`

- **Role:** `class_name UiScaleLayer`, extends CanvasLayer; applies `SettingsManager` UI scale to the layer and fits direct Control children to the scaled viewport.
- **Depends on:** `SettingsManager` (`ui_scale_changed`, `get_ui_scale`).
- **Signals:** connects `SettingsManager.ui_scale_changed`, viewport `size_changed`, own `child_entered_tree`.
- **Lifecycle:** script on `HudLayer`, `ModalLayer`, `ToastLayer` in `app.tscn`, used in `world_map.tscn`, and base class of `MainMenu`.
- **Invariants:** direct Control children are forced to top-left anchors at position 0 with size = viewport / scale.
- **Tests:** none found directly; (indirect) `tests/suites/test_branding.gd` changes the UI scale.
- **Change risks:** subclasses must call `super._ready()`; anchors on direct children are overwritten.

### `src/ui/vhf_dialog.gd`

- **Role:** `class_name VhfDialog`, extends `SimplePanel`; VHF channel 16 call with Answer/Decline.
- **Depends on:** `VhfRadio` (`describe`, `describe_commitment`, `KIND_ASSIST`), `GameSession.answer_vhf`, `Loc`.
- **Signals:** declares `answered(result)` (after close); App connects it to `notify(result.text)`.
- **State:** `call` dict (set by App before adding); answering writes via `GameSession.answer_vhf(call, accept)`.
- **Lifecycle:** created by `App.show_vhf_dialog(call)` when `GameSession.can_answer_vhf(call)` and no modal is open; logged as `vhf_dialog`.
- **Tests:** none found for the dialog; (indirect) VHF logic in `tests/suites/test_captains_watch.gd`.
- **Change risks:** `call` must be set before `_ready`; closing via Esc does not answer (default `handle_back`).

### `src/ui/voyage_map.gd`

- **Role:** `class_name VoyageMap`, extends CanvasLayer (layer 15, `PROCESS_MODE_ALWAYS`); atlas view while the passage clock runs.
- **Depends on:** `Simulation` (`start_passage`, `stop_passage`, `passage_rate`, `PASSAGE_RATES`, `passage_interrupted`, `STOP_*`, `get_eta`, `format_game_time`), `GameSession` (voyage, progress, position, `state_replaced`, `rescued`), `CabinWorldMap` (`to_unit`, `aspect`, `land_triangles/indices/colours`), `GeoMath.segment_index_at`, `PortCatalog`, `UiTheme` (`palette_changed`, `blend`, `color`, `theme`), `TimePassage` (`NIGHT_INK`, `date_text`), `PassagePanel` (`RATE_LABELS`, `_thousands`, `get_stopped_text` via `hud.passage_panel`), `Loc`.
- **Signals:** declares `closed` (from `_finish`); connects `Simulation.passage_interrupted`, `GameSession.state_replaced` → `close_now`, `GameSession.rescued`, `UiTheme.palette_changed`, viewport `size_changed`.
- **State:** hides and disables `screen`, `hud_layer`, `hud` (set by App before adding) and restores them on close; route cache keyed by voyage revision + path size.
- **Lifecycle:** created by `App._on_passage_started` (only when `TimePassage.is_shown()` and underway); App calls `close_now()` on screen changes.
- **Performance:** land drawn as one cached triangle batch (three copies for Date Line) only on view changes; track/boat redrawn at `TRACK_FPS` (12/s).
- **Invariants:** route unwrapped so consecutive points are within half a world; boat placed on the same unwrapped copy; `_closing` guard makes close idempotent.
- **Tests:** `tests/suites/test_well_run_ship.gd` (with `TimePassage.enabled`/`headless_ok`; screenshots `wrs_voyage_map*`).
- **Change risks:** must always restore the hidden screen/HUD (including when closed mid-fade); `_on_interrupted` awaits a frame so PassagePanel can append nibbles first; relies on PassagePanel's private `_thousands`.

### `src/ui/work_menu.gd`

- **Role:** `class_name WorkMenu`, extends `SimplePanel`; remote-work duration picker.
- **Depends on:** `GameSession` (`REMOTE_WORK_PAY_PER_HOUR`, `REMOTE_WORK_MIN_HOURS`, `REMOTE_WORK_MAX_HOURS`, `get_unpublished_renown`, `get_funds`, `get_game_time`, `format_money`), `Simulation.format_game_time`, `Provisions.format_days`, `Loc`.
- **Signals:** declares `work_requested(hours)` and `publish_requested`; App connects them to `work_for` (`Simulation.work`) and `open_publish_menu`.
- **State:** `hours` (default 4); read-only on game state.
- **Lifecycle:** created by `App.open_work_menu()` (only when `GameSession.can_work_remotely()`), from `BoatArea.work_requested`.
- **Tests:** `tests/suites/test_publishing.gd`, `test_living.gd`.
- **Change risks:** displayed pay is computed locally and must match `Simulation.work`'s actual pay.

## Test suites

### `tests/suites/test_academy.gd`

- **Role:** extends RefCounted; I022 suite. `_test_data` (chapters, page links, `{placeholder}` validity via RegEx, no "press X" letters, 8 steps), `_test_keys_and_search` (E/Esc/L/F1, move, fill, search, Danish completeness and search "anker"), `_test_settings` (sanitizing, save/load, restore_defaults keeps progress), then with `app.tscn` and `AcademyGuide.enabled = true`: `_test_offer` (ConfirmDialog on the first new game, Esc = skip, once, `load_slot` never offers), `_test_first_voyage` (drives each step: InputEventAction move_up into `_input`, wheel, log, deck, chart, `plan_route_to`, `depart`, time scale 5), `_test_tips` (pause menu and HUD warning defer; close + 20 s gap; once; tips off; Read more → `HandbookMenu.shown_page`), `_test_handbook` (F1 via `_unhandled_input`, search, pause menu button, Close back to the pause menu, FirstVoyageButton). Screenshots i022_academy_offer, _first_voyage, _chart_step, _tip, i022_handbook.
- **Depends on:** `app.tscn`, `SaveManager.save_to_slot(3)`, runner helpers.
- **Lifecycle:** in `test_runner.gd` `SUITES` after `test_captains_other_life`; resets `AcademyGuide.enabled` and the progress at the end.
- **Change risks:** sets the private `_queue`/`_gap_left` of the guide to make tip timing deterministic.

### `tests/suites/test_anchor_life.gd`

- **Role:** extends RefCounted; test suite for 0.102b life at anchor. Covers `AnchorLife` rules (local solar hour, phases, tints), harbour coffee (no award), settling at a CLASS_GOOD anchorage on Copenhagen→Malmö, one-shot `settled`/`evening`/`pet`/`wake` moments, anchor ambience (tint, cabin lamp), the anchor-morning coffee award (+2 renown, once), save/load (slot 3, incl. a save stripped of `anchor.moments`), and unsettling in 24–30 kn wind.
- **Depends on:** `src/app/app.tscn`, `tests/helpers/walkability.gd` (preloaded, unused), `GameSession`, `Simulation`, `AnchorLife`, `AnchorSite`, `CookingMenu`, `ShipCompanion`, `CompanionVisualSet`, `BoatArea`, `SaveManager`, `SessionState`.
- **Signals:** connects to `GameSession.anchor_moment` (disconnected at the end).
- **State:** `Simulation.auto_advance = false` during the run; edits save JSON in `SaveManager._slot_path(3)` directly.
- **Lifecycle:** test suite; `run(runner)` called by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** depends on reaching a CLASS_GOOD anchorage within 200×300 s from Copenhagen at 90°/8 kn. Exact message counts per kind. Screenshots `0102b_*`.

### `tests/suites/test_anchorage.gd`

- **Role:** extends RefCounted; test suite for Iteration 18 anchorage waypoints (ANCH-1..8). Covers marking on the chart (`toggle_anchorage`, M key, refusal for land or too-deep water plus a suggestion, a once-only hint), the planned route flag and save round-trip, Long Passage stopping with `STOP_ANCHORAGE`, the `AnchoragePrompt` asked once (also after load), the normal anchoring checks, "Sail on", `change_course` with flags, Date Line flags (Papeete→Auckland), anchorages off New Zealand, and loading a 0.104a voyage without anchorage fields.
- **Depends on:** `src/app/app.tscn`, `WorldMap`, `MapView`, `GameSession`, `Simulation` (`start_passage`, `_passage_tick`, `PASSAGE_RATES`), `SeaRouter`, `PortCatalog`, `PlannedRoute`, `SessionState`, `AnchorSite`, `AnchoragePrompt`, `SailingPanel`, `FishingState`, `SaveManager`, `GeoMath`.
- **Signals:** connects to `Simulation.passage_interrupted` temporarily.
- **State:** replaces session state via `GameSession.replace_state` (helper `_moor`); save slot 3.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** wind fixed at 200°/10 kn. Relies on an offshore point on the Gothenburg course being too deep (0.105b depth rule). Uses private `world._select_waypoint`. Prompt text is compared exactly. Loop guards (20000 ticks, 400 steps). Screenshots `18_anchorage_*`.

### `tests/suites/test_anchorage_overlay.gd`

- **Role:** extends RefCounted; test suite for the 0.105b chart anchorage overlay. Covers the zoom gate (no work at world zoom, "Zoom in" note), filling only visible tiles around Antigua within `AnchorageLayer.FRAME_BUDGET_USEC`, teal/amber cells agreeing with `GameSession.anchorage_spot(…, true)` (400 seeded samples, seed 18), hover texts (`inspect_anchorage`), tile reuse and the `MAX_TILES` bound, Date Line tiles near Fiji, and waypoints in teal/amber with and without `fit_magic_anchor()`, dragged onto land.
- **Depends on:** `src/app/app.tscn`, `WorldMap`, `MapView` (`anchorage_layer`, `anchorage_magic`, `invalid_waypoints`, `waypoint_dragged`), `AnchorageLayer` (reads private `_wanted`), `CoastalGeography`, `GameSession`, `AnchorSite`, `GeoMath`.
- **State:** wind 90°/12 kn; clears private `world._spot_cache`.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Performance:** asserts the p95 per-frame layer work is ≤ budget + 1.5 ms and the maximum is < 12 ms. Prints timing details.
- **Tests:** —
- **Change risks:** timing assertions are machine-sensitive. Tile keys x==0 / x==359 are hard-coded for the Date Line. Waits of up to 60 s. Screenshots `rb_01`–`rb_08`.

### `tests/suites/test_atmosphere.gd`

- **Role:** extends RefCounted; test suite for Iteration 17 weather audio and visuals. Covers asset files plus README provenance in `assets/audio/weather/`, the Outside bus (low-pass, sends to Ambience) and the unfiltered SFX bus, `WeatherAudio.rain_level` per classification, the wind/water/rain loops and storm audio in a gale fixture, cabin muffling, lightning flashes on the scene lighting (flash intensity 0, reduce flashing), thunder delay with distance, and deck `WeatherVisuals` streaks and drops. I022: `[buses]` checks `WIND_BUS` sends to `OUTSIDE_BUS` (index after it); `[loops]` checks the wind loop on `WIND_BUS`, water on `OUTSIDE_BUS`.
- **Depends on:** `src/app/app.tscn`, `WeatherAudio` (reads private `_strike_in`, `_thunder_near`, `_flashes`), `AudioManager`, `AudioServer`, `WeatherFixtures`, `WeatherSample`, `WeatherModel`, `WeatherVisuals`, `SettingsManager`, `Simulation`, `GameSession`.
- **State:** changes the flash settings and restores the defaults; clears `WeatherFixtures`.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** uses real-time `create_timer` waits (0.6–1.0 s) for muffling, flash decay and visuals. Luminance thresholds. Screenshot `17_deck_rain_and_wind`.

### `tests/suites/test_boat_care.gd`

- **Role:** extends RefCounted; test suite for Iteration 14 boat care. Covers the upgrade catalogue and prices, hull fouling per day and its speed loss, rig wear per nm (faster in strong wind), engine hours, determinism, yard availability (Lohals none, Korsør no haul-out, Copenhagen haul-out), quotes scaling with damage and boat size, the first haul-out award and history, upgrade effects (cool box, stove, heavy anchor, weather receiver, stainless rigging, hard antifouling), `PassageReadiness` (advice only), save migration format 11→12, and the UI (`BoatCareMenu`, `HaulOutPanel`, Log Boat tab, `ReadinessLabel` on the chart).
- **Depends on:** `src/app/app.tscn`, `BoatCare`, `BoatCareState`, `GameSession`, `Simulation`, `PassageReadiness`, `DevTools` (`set_condition`, `set_provisions`), `AnchorSite`, `WindField`, `HarbourFacilities`, `BoatyardMenu`, `BoatCareMenu`, `HaulOutPanel`, `CaptainsLogMenu`, `WorldMap`, `SaveManager`, `Provisions`.
- **State:** many `GameSession.start_new_session()` / `end_session()` cycles; `t.board(&"halcyon_40")`; save slot 3 is rewritten as format 11.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Persistence:** verifies the migration of a save without `boat_care` (20 days in the water; rig and engine wear derived from `captains_log.total_nm`).
- **Tests:** —
- **Change risks:** exact constants (6→10 fish, 18→26 kn cooking, +5 kn holding, 6→10 h warnings). The I020 split between yard and chandlery items. Screenshots `14_*`.

### `tests/suites/test_boat_of_your_own.gd`

- **Role:** extends RefCounted; test suite for I020 "A Boat of Your Own". Covers `HarbourFacilities` trades per port (counts across the catalogue), the fishmonger opened from the grocery store (single sale, the `GroceryMenu` under it refreshed with the new funds, sell all, no double sale, reload undoes a sale, none at sea), the chandlery (upgrade = boat-care upgrade, decor, never below zero funds, none without a yard), the sailmaker (sail cloth per vessel, free to switch back, look only, `SailRig.sail_colour`, the rig service = `BoatCare.SERVICE_RIG`), decor placement on all four vessels (clearance from stations, no collisions), save tolerance (missing `home`, unknown decor or sails dropped), and the Danish UI fitting on screen. I021: the Danish fit check measures the `Scroll` container against the screen and rows inside it only for width. `_test_cabins` also checks `placed.has("compass")` per vessel and the Danish name of `compass` (Operation Paperwork).
- **Depends on:** `src/app/app.tscn`, `HarbourFacilities`, `HarbourTrades`, `TradePanel`, `GameSession`, `FishingCatalog`, `CabinDecor`, `SailRig`, `BoatCare`, `BoatCareState`, `SessionState`, `SaveManager`, `SettingsManager`, `Loc`, `Interactable`.
- **State:** injects fish into `state.fishing.hold` (uids 9000+) via `replace_state`; sets funds; sets the language to `da` and back to `en`.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Persistence:** checks the `home` block (owned_decor, per-vessel sails and decor) round-trips and is tolerant of bad data.
- **Tests:** —
- **Change risks:** catalogue ids (`rug` €40, `oil_lamp`, `magic_anchor`, `lure_spinner`). "Skibshandel" title. Decor clearance `CabinDecor.CLEARANCE * 0.6`. Screenshots `i020_cabin_*`.

### `tests/suites/test_branding.gd`

- **Role:** extends RefCounted; test suite for Visual Identity V01, Checkpoint C. Covers project settings (name, description mentions Next Harbor, version = `GameVersion.DISPLAY`, icon), `GameVersion` (DISPLAY "0.108a", MACHINE "0.108.1", commit format, `describe`), `SaveManager.SAVE_VERSION == 12` and `FORMAT_ID`, branding asset files, the custom user dir "Little Captains Hat" vs the legacy `app_userdata/Next Harbor`, fonts and the OFL licence, theme font variations (Patrick Hand headings with Barlow fallback, Barlow body), `LegacySaves` copy-only import (free-slot mapping, originals untouched, exact copies, v9 save upgraded in memory, already-imported, no free slot), the main menu (logo, tagline, version label, credits, fits at 130 %), the import button with `ConfirmDialog`, and Captain's Log and HUD typography.
- **Depends on:** `src/app/app.tscn`, `assets/ui/next_harbor_theme.tres`, `GameVersion`, `SaveManager`, `LegacySaves`, `GameSession`, `HatState`, `MainMenu`, `ConfirmDialog`, `CaptainsLogMenu`, `Hud`, `SettingsManager`, `ProjectSettings`.
- **State:** writes v9 legacy saves under `user://test_legacy_userdata/saves` via `LegacySaves.legacy_dir_override` (reset and cleaned at the end); deletes save slots 1–3.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Persistence:** verifies the import never overwrites a used slot or the source files.
- **Tests:** —
- **Change risks:** pins the version strings, save version and asset paths, so every release bump needs this test updated. Tagline text is compared exactly. Screenshots `130_*`–`134_*`.

### `tests/suites/test_cabin_windows.gd`

- **Role:** extends RefCounted; I022 suite. `_test_data_in_the_walls` (each opening's corners +1.5 frame sampled in `cabin_base.png`: alpha ≥ 0.9 and r ≤ 0.35 = wall paint), `_test_water_look`, `_test_in_the_cabin` (`_aboard` sets vessel/time via `replace_state`; node order after `CabinBase`; `view_of` port north / starboard south moored, aft offset, fov up close; `last_draw_usec` median of 30 redraws; ≤ 2 redraws standing still for 60 frames; dusk 18:42 and night 22:30 UTC; underway heading −90°; classic art hides), `_test_other_cabins`, `_test_deck_water` (translucency 0/1 × moored/underway screenshots).
- **Depends on:** `app.tscn`, `Image.load_from_file` of the cabin art, runner helpers.
- **Lifecycle:** in `test_runner.gd` `SUITES` after `test_academy`; restores `WaterLook.translucency` and `CabinWindows.glass_strength`.
- **Change risks:** the time-of-day checks assume Copenhagen on the default start date.

### `tests/suites/test_captains_log.gd`

- **Role:** extends RefCounted; test suite for Iteration 006 Captain's Log. Covers the start harbour, arrival records, change of course (one record, both legs), rescue (a gale fixture with condition 1 %), determinism (9 h in one step vs 540 steps), the bounded history (`MAX_VOYAGES`, save size < 20000 chars), save/load equality, rejection of a negative distance, migration of version 7 saves (in port and underway), and the `CaptainsLogMenu` UI (L key, statistics, tabs, country groups and filters, pause-menu button). Golden Harbours: `_test_log_panel` accepts the Log line inside the Gothenburg `HarbourMoment` (exactly one message contains it).
- **Depends on:** `src/app/app.tscn`, `GameSession`, `CaptainsLog`, `Simulation`, `SaveManager`, `SessionState`, `WeatherFixtures`, `WeatherModel`, `PortCatalog`, `CaptainsLogMenu`.
- **Signals:** connects to `GameSession.voyage_logged`.
- **State:** writes raw save wrappers (`next_harbor_save`, version 7) into `SaveManager.save_dir` slot 3; uses slot 2.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Persistence:** verifies v7→current migration: visited = Copenhagen plus the current port with `UNKNOWN_TIME`; underway voyages get `sailed_nm = progress_nm` and `fully_recorded = false`.
- **Tests:** —
- **Change risks:** exact toast text "New harbour in the Captain's Log: … (3 of N visited)." and node names (`DistanceValue`, `Harbour_kiel`, `Country_Germany`). Screenshots `108_*`, `109_*`.

### `tests/suites/test_captains_other_life.gd`

- **Role:** extends RefCounted; I022 suite. `_test_prices_and_new_games`, `_test_old_saves` (erases `fleet`/`difficulty` from a save dict; unknown ids and levels), `_test_buying` (sets `GameSession.test_all_boats_owned = false`, restores it), `_test_difficulty_factors` (a day of food, provisions price, engine service quote per level; `set_difficulty`; Danish names), `_test_menus` (App: New Game picker → Seasoned start; pause menu `DifficultyButton` → `DifficultyMenu` → Relaxed). I022: `_test_postcards`, `_test_game_dev`, `_test_pastime_saves`, `_test_pastimes_on_the_clock` (Copenhagen→Helsingør measured, then a card started ~1 h out is stopped by STOP_ARRIVAL), `_test_pastime_menus` (wheel ids, PostcardMenu/ScrapbookMenu/GameDevMenu, screenshots).
- **Depends on:** `app.tscn`, `GameSession`, `SessionState.from_dict`, `VesselCatalog`, `Difficulty`, runner helpers (`click`, `frames`, `wait_until`, `screenshot`).
- **Lifecycle:** in `test_runner.gd` `SUITES` after `test_wider_world`.
- **Change risks:** prices and starting funds are read from data, not hard-coded; the ownership switch must be restored for later suites.

### `tests/suites/test_captains_watch.gd`

- **Role:** extends RefCounted; test suite for I019 The Captain's Watch. Covers `TrafficModel` (deterministic, navigable, bounded by `MAX_PER_CELL`, ships moving, query < 2 ms), `TrafficModel.approach` CPA/TCPA, `Simulation.risk_level`, `traffic_alert` fairness (tcpa ≥ 0.15 h, once per ship, ≤ 1 per 10 h), sleep and Long Passage stopping (`STOP_TRAFFIC`/`STOP_WARNING`), `RadarPanel.describe`/`colour_for`, anchor alarm levels and `AnchorState` compatibility, and `VhfRadio` (deterministic per slot, answering and declining, standby, once-only reward across a round trip, the expiry window). `_test_radar` also checks `RadarPanel.should_show()` on a standalone panel: on at sea, off when moored, on again after `_depart`.
- **Depends on:** `GameSession`, `Simulation`, `TrafficModel`, `SeaRouter`, `PortCatalog`, `RadarPanel`, `VhfRadio`, `AnchorState`, `SessionState`.
- **Signals:** connects to `Simulation.traffic_alert`, `Simulation.passage_interrupted`, `Simulation.vhf_call`, `GameSession.anchor_alarm`, `GameSession.notice`.
- **State:** no app scene. `app = runner.get("app")` is null with the current runner, so the HUD radar check is skipped. Sets `Simulation.passage_rate` directly.
- **Lifecycle:** test suite run by `tests/test_runner.gd`; the runner sets `Simulation.sea_encounters = true` for this file only (and for `test_localization.gd`).
- **Tests:** —
- **Change risks:** results depend on traffic seeded by time and route (it searches several routes for an alert). Timing assertion on the radar query. Long simulated voyages (up to 240 h).

### `tests/suites/test_catamaran_cabin.gd`

- **Role:** extends RefCounted; test suite for the Iteration 004b Halcyon 40 cabin. Covers the saloon door art matching the `Companionway` station, the "TO DECK" label and the "Go on deck" prompt, art/collision parity (`BoatFixture` vs `ProceduralShape`), the required fixtures and berth sizes, a minimum hull width (140 units) and furniture depth (40 units), walkability into both hulls with held input, the nav station opening `WorldMap`, sleeping (wake at the `v_berth` spawn), and reachable `CompanionState.ALL_SPOT_IDS`.
- **Depends on:** `src/app/app.tscn`, `tests/helpers/walkability.gd`, `GameSession.switch_vessel`, `BoatArea`, `BoatFixture`, `ProceduralShape`, `Interactable`, `SleepMenu`, `WorldMap`, `ShipCompanion`, `CompanionState`.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** hard-coded node paths and coordinates (hull openings x = -20 / 82, |y| > 170). Walking uses physics frames and `Input.action_press`. Screenshots `50_*`–`52_*`.

### `tests/suites/test_catch_and_cove_journey.gd`

- **Role:** extends RefCounted; end-to-end test suite for Iteration 13 "The Catch & The Cove" through the stations: troll to Malmö, bite, land the fish with `Reel.land`, save/load (fish kept once), anchor via `AnchorMenu` (scope 5, catch 0.48), cook `pan_fried_fish` at anchor (evening outcome text), sleep 9 h, raise the anchor, an exact save/load round trip. Then a rough evening: anchoring and cooking refused in 38 kn, and a rising-wind `WindField.test_override` until the anchor alarm wakes the captain.
- **Depends on:** `src/app/app.tscn`, `tests/helpers/reel.gd`, `tests/helpers/walkability.gd`, `GameSession`, `Simulation`, `FishingMenu`, `FishingState`, `AnchorMenu`, `AnchorSite`, `AnchorState`, `CookingMenu`, `SaveManager`, `WindField`.
- **State:** save slot 3; overrides `WindField.get_default().test_override` (reset by `t.use_calm_wind()`).
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** probabilistic waits (a bite within 120×300 s), exact outcome text, toast wording ("anchor alarm", "Go up to the windlass"). Very broad, so it breaks for many upstream changes.

### `tests/suites/test_chart_and_pause.gd`

- **Role:** extends RefCounted; test suite for the I003b chart sidebar and shared Pause. Covers the sidebar layout (header, tabs, footer stacked and on screen; stable across tabs, at 20×, with changing wind, at UI scales 0.8 / 1.3, and in a 1366×768 window when not headless), map controls outside the sidebar, the Weather tab ("Weather (1)" on the way to Kiel), course editing at sea, zoom/centre/drag/wind toggle, pause on chart, cabin and deck (time, progress, wind and companion frozen), picking a speed resumes, the chart usable while paused, sleep while paused, and pause persistence (the `clock.paused` flag, older saves, invalid values).
- **Depends on:** `src/app/app.tscn`, `WorldMap`, `MapView`, HUD (`Pause`, `Speed*`, `PausedBadge`, `ClockPanel`), `GameSession`, `Simulation` (`tick`, `evaluate_propulsion`), `SettingsManager`, `SleepMenu`, `SessionState`, `SaveManager`, `GeoMath`.
- **State:** toggles `Simulation.auto_advance` to run frame-driven time; save slot 2; resizes the window.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Persistence:** checks `clock.paused` (missing → unpaused; non-bool → rejected).
- **Tests:** —
- **Change risks:** pixel-rect comparisons (0.5 px tolerance). The weather-tab count depends on the default weather along Copenhagen→Kiel. Calls private `map._refresh()` and `app._on_area_change_requested`. Screenshots `33_*`–`38_*`.

### `tests/suites/test_chartroom_ui.gd`

- **Role:** extends RefCounted; test suite for the Chartroom UI theme. Covers `UiTheme` roles in `PALETTES`, theme type variations, fonts (Patrick Hand headings, Barlow body), WCAG contrast ≥ 4.5 by day and night, the `ui_light` modes saved in settings.cfg `[interface]` and never in the save, Automatic following the boat's local daylight with an eased blend and no idle `palette_changed`, an open Settings window surviving a mood change, HUD slimming in port and underway, the chart map-button variations and a compact destination summary, the boat care menu, an unobstructed fishing `ReelDial`, and the `UiTheme.tint` adapter.
- **Depends on:** `src/app/app.tscn`, `UiTheme` (incl. private `_target_blend`), `SettingsManager`, `GameSession` (injects private `_pending_bite`), `Hud`, `WorldMap`, `BoatCareMenu`, `FishingMenu`, `ReelDial`, `FishingCatalog`, `ModalPanel`.
- **Signals:** connects to `UiTheme.palette_changed` temporarily.
- **State:** writes the test settings file; resets `ui_light` to AUTO at the end.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** real-time easing checks (blend after 0.6 s between 0 and 0.5; up to 15 s to settle). Font resource paths. Label-width fit for the waypoint buttons.

### `tests/suites/test_coastal_depth.gd`

- **Role:** extends RefCounted; headless test suite (no app) for 0.105b coastal geography, depth and anchoring rules. Covers the `CoastalGeography` raster (res 120), `approach` into near-shore water off Antigua and a router course through it, synthetic coasts (a 1-cell gap is blocked, a 3-cell gap passes), the `DepthService` estimate (GAME ESTIMATE label, deterministic, rounded text, smooth, varied, not tied to proximity, enclosed bays shallower), loading a synthetic `DepthData` file, wind-dependent shelter vs fixed depth, `AnchorSite.evaluate` rules (land, too deep, Magic Anchor offshore), and six acceptance areas with an anchorage plus a route.
- **Depends on:** `CoastalGeography`, `DepthService`, `DepthData`, `SeaRouter`, `PortCatalog`, `AnchorSite`, `WindField`, `GameSession` (`nearest_anchorage_spot`, `anchorage_spot`), `GeoMath`.
- **State:** writes `user://test_synthetic_coast.bin` and `user://test_synthetic_depth.bin` (the `LCHC`/`LCHD` formats, built by hand).
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** the synthetic file layouts mirror the binary formats exactly (header sizes, tile index, offset table). Assumes no real depth data is installed. Hard-coded coordinates and ports (`nyborg`, `a_coruna`, `las_palmas`, `falmouth_antigua`, `papeete`, `whangarei`).

### `tests/suites/test_cockpit_ui.gd`

- **Role:** extends RefCounted; test suite for the Iteration 17 cockpit (HUD, NAV-8). Covers `SailingPanel` values underway to Las Palmas (speed, heading "planned course", wind, next leg "(estimate)", turn, remaining), no overlap with the route or Long Passage panels, collapse, "No more turns" on the last leg (set via `replace_state` of `voyage.progress_nm`), the course-change pulse (> `COURSE_CHANGE_DEG`) ending by itself, `ChartPlotter` (P key, deck and underway only, raster ready, no `MapView` built, range change), and `ActionWheel` (Q, helm/cabin item ids, keyboard select with D/E, Esc not opening the pause menu, mouse choosing `dream_map` → `WorldMap.MODE_DREAM`).
- **Depends on:** `src/app/app.tscn`, `SailingPanel`, `ChartPlotter`, `ActionWheel`, `Hud` (`describe_wind`), `WorldMap` (`get_next_turn`), `GameSession`, `Simulation`.
- **State:** resets the statics `ChartPlotter.shown` and `SailingPanel.collapsed` at the end.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** real-time 2 s timers around the pulse. Text-prefix formats (`%03d°`, `%.1f kn`). The turn search depends on the Las Palmas route geometry. Screenshots `17_sailing_panel`, `17_chartplotter`, `17_action_wheel_helm`.

### `tests/suites/test_companion_art.gd`

- **Role:** extends RefCounted; test suite for companion artwork. Covers the cat and dog PNGs and their mapping in `CompanionVisualSet`, MD5 checks of the owner's `Visuals/Cat/*.png`, background removal (`prepare_image`, on the owner's drawings and synthetic images), the shared draw rect, the New Game preview (cat/dog), pose textures in the cabin, 30 minutes of pose behaviour (occasional changes, minimum hold of `stretch_seconds`), approach and alert, the outline highlight and `focus_priority` -1, petting with purr on the SFX bus, fallbacks (a missing pose, then procedural), replacing art through data (a PNG in `user://test_companion_art`), all vessels, persistence (poses not saved), and the dog.
- **Depends on:** `src/app/app.tscn`, `tests/helpers/walkability.gd`, `CompanionVisualSet`, `ShipCompanion` (sets private `_alert_ready_at`), `NewGameMenu`, `CompanionState`, `VesselCatalog`, `GameSession`, `AudioManager` (`BUS_SFX`), `SaveManager`, `BoatArea`.
- **Signals:** connects to `ShipCompanion.pose_changed` temporarily.
- **State:** clears the `CompanionVisualSet` cache at the start and end; save slot 2.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Persistence:** asserts the save JSON contains no "pose" or art paths.
- **Tests:** —
- **Change risks:** the hard-coded MD5s of the owner's files. Pixel thresholds. Real-time waits (0.7 s, up to 5 s). Screenshots `13_*`, `53_*`–`59_*`.

### `tests/suites/test_companion_deck.gd`

- **Role:** extends RefCounted; test suite for Iteration 18 PET / ANCH-9..11 / LIGHT-3. Covers `DeckCompanionSpots` on all four boats (three safe, aboard spots clear of the helm, ordered aft→forward), following with a delay via `app._update_companion_follow`, every walk frame `is_safe`, save/load with the companion on deck, going below on departure and in 26 kn wind, anchor signals (ball between mast and bow, buoy ahead) only at anchor, `BoatLighting.get_lit_lamps()` (none by day, white anchor light at night at anchor, three nav lights underway with red to port and green to starboard in 8 view orientations, none moored).
- **Depends on:** `src/app/app.tscn`, `DeckCompanionSpots`, `ShipCompanion`, `CompanionState`, `GameSession`, `Simulation`, `SailRig`, `BoatLighting`, `BoatArea` (`view_heading_override`, `get_anchor_signals`, `get_lighting`), `PortCatalog`, `SaveManager`.
- **State:** sets `game_time` to `MAY_1` plus a local-noon offset via `replace_state`; save slot 3.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** walk loops are bounded by wall-clock time (30 s). The camera-rotation wait. Depends on reaching an anchorage on the way to Malmö. Screenshots `18_*`.

### `tests/suites/test_companion_remarks.gd`

- **Role:** test suite: petting remarks: per-kind lines, no immediate repeat, gender/name variants (injected identities, since `CompanionState` has no name or gender yet), names with Danish letters and punctuation, Danish translations and a language switch, cabin petting for cat and dog through `BoatArea._on_interacted` (reaction, one remark, cooldown, next line), hands full (hat carried + coffee carried), save round trip unchanged.
- **Depends on:** `CompanionRemarks`, `ShipCompanion` (`take_remark`, `reset_remark_cooldown`, `is_reacting`), `BoatArea`, `GameSession`, `SettingsManager`, `SessionState`, `App` scene.
- **Tests:** —.
- **Change risks:** uses `ShipCompanion.reset_remark_cooldown()` instead of waiting the 15 s real-time cooldown; restores English, hat worn and no coffee at the end.

### `tests/suites/test_cozy_patch.gd`

- **Role:** extends RefCounted; test suite for the post-0.105b patch. Covers petting the deck companion while it walks in, just after it arrives, and while it walks out (pause, one `petted`, walk resumes, reaches the spot), `TrophyBoard` pictures (`FishArt.thumbnail` per species, empty slots null, `Sprite2D` width = `TrophyBoard.PICTURE.x`), 0.105a trophy dicts loading, a new kept catch added once and shown, and Dreamer's Map style (`is_dream_style`) vs the navigation chart.
- **Depends on:** `src/app/app.tscn`, `ShipCompanion` (`REACTION_SECONDS`), `DeckCompanionSpots`, `CompanionState`, `CompanionVisualSet`, `TrophyBoard`, `FishArt`, `FishingState`, `FishingCatalog`, `GameSession` (injects `_pending_bite`, `finish_fight`), `WorldMap`, `MapView`.
- **Signals:** connects to `ShipCompanion.petted`.
- **State:** calls the private `area.player._sensor.interact` to pet through the real sensor path.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** real-time timers (0.3–0.6 s plus `REACTION_SECONDS`) remain around the petting; the walks themselves are stepped synchronously by `_walk_on` (`ShipCompanion._process(1/60)`, ≤ 3600 steps), and `app.set_process(false)` holds `App._update_companion_follow` during the walk-out. Before the Engine Room pass the walk-out (2.9–10.4 s by deck spot) raced the 2.5–5 s follow timer while waiting real frames (intermittent "then she goes below"). Screenshots `patch_*`.

### `tests/suites/test_cozy_polish.gd`

- **Role:** extends RefCounted; test suite for "Injection 1, Cozy Polish". Covers canal links in `SeaRouter.canals` (Kiel, Suez, Bab-el-Mandeb), route lengths (Kiel→Cuxhaven < 120 nm, Limassol→Noumea < 10000 nm, Colón→Panama City < 60 nm), Baltic routes, `is_canal_segment` limits, sailing the Kiel Canal afloat with a mid-canal state round trip, the minimum chart zoom staying within -72.5..80.5°, Palermo→Limassol replanning (no click waypoint, land waypoint moved or removed), `WaterLife` sea drifters passing astern in proportion to speed and never spawned over the beam, action wheel labels and `checked` meta, coffee/hat/hands and cup holders on all vessels, sleep hours remembered and clamped in settings, `visited_pins` and pin grouping on the Dreamer's Map only, compact HUD sizes, `LoadingScreen` steps, and `galley.coffee` save compatibility.
- **Depends on:** `src/app/app.tscn`, `SeaRouter`, `PortCatalog`, `PlannedRoute`, `GeoMath`, `WorldMap`, `MapView`, `WaterLife` (private `_boat_kn`, `_wind_kn`, `_move_waves`, `_respawn_sea_drifter`, `_beam`), `ActionWheel`, `ChartPlotter`, `SailingPanel`, `CoffeeMug`, `HatState`, `VesselCatalog`, `BoatArea` (`_lifeline_polygon`, `CUP_HELM_CLEARANCE`), `SleepMenu`, `SettingsManager`, `LoadingScreen`, `Hud`, `SessionState`, `SaveManager`.
- **State:** edits the test settings file directly (`sleep_hours` = 99); changes the art style and course view (restores the course view).
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Persistence:** asserts `SaveManager.SAVE_VERSION == 12` and `galley.coffee` round-trips (missing → `&""`).
- **Tests:** —
- **Change risks:** the pinned save version. Pixel-size limits for compact panels (`AreaPanel` < 533×101, `ClockPanel` < 520). Real-time drifter sampling (0.6 s / 1 s). Distance bounds on the routes. Screenshots `cozy_*`.

### `tests/suites/test_data_model.gd`

- **Role:** extends RefCounted; synchronous test suite (`run(t)`). Covers `PortCatalog` (≥ 150 ports, stable ids), `GeoMath.distance_nm` Copenhagen–Kiel (105–125 nm), the `MapProjection` round trip and north-up, the `SessionState` JSON round trip (incl. a waypoint route and the spawn point without a position), rejection of 12 malformed session payloads, and `GameSession` route planning, clearing and ending a session.
- **Depends on:** `PortCatalog`, `GeoMath`, `MapProjection`, `SessionState`, `GameSession`, `runner.make_route`.
- **Lifecycle:** test suite; first in `tests/test_runner.gd` SUITES.
- **Tests:** —
- **Change risks:** the invalid-case dictionary keys mirror the save schema paths (`boat.area`, `player.position`, `navigation.planned_route.*`, `clock.time_scale`, `vessel.status`); a schema rename silently changes what is tested.

### `tests/suites/test_denmark_views.gd`

- **Role:** extends RefCounted; mostly a screenshot suite for Iteration 14 Danish waters. Covers `MapView.is_region_detail_shown("denmark")` at 8 view centres and scales (ports or GeoNames positions) and its absence at world zoom, a valid Copenhagen→Svendborg course plotted by clicks, sailing underway at 250°/12 kn, anchoring > 3 nm from any harbour, and the Svendborg quay boatyard station and `BoatyardMenu`.
- **Depends on:** `src/app/app.tscn`, `WorldMap`, `MapView`, `SeaRouter`, `PortCatalog`, `GameSession`, `Simulation`, `AnchorSite`, `GeoMath`, `HarbourFacilities`, `BoatArea`, `BoatyardMenu`.
- **Lifecycle:** test suite run by `tests/test_runner.gd`; pictures only with `--screenshots=DIR`.
- **Tests:** —
- **Change risks:** the expected detail-layer flags in `VIEWS`. Click positions depend on map projection and zoom. Screenshots `14_01`–`14_19b`.

### `tests/suites/test_dev_guides.gd`

- **Role:** extends RefCounted; test suite for `DEV_GUIDES/` and the in-game viewer. Covers the 12 guide files and their index links, links in `LINKED_DOCS` plus the guides resolving on disk, backticked repo paths under `PATH_ROOTS` existing (guides only), `MarkdownLite.to_bbcode` conversions, the viewer from `MainMenu` (`DevGuidesButton`, titles, content, ligatures off, scrolling, close, Esc), and missing-guides behaviour (`DevGuides.guides_dir` redirected).
- **Depends on:** `src/app/app.tscn`, `src/ui/dev_guides_menu.tscn`, `DevGuides`, `DevGuidesMenu`, `MarkdownLite`, `MainMenu`; reads `README.md`, `docs/**`, `DEV_GUIDES/*.md`.
- **State:** temporarily sets `DevGuides.guides_dir` and restores `DEFAULT_DIR`.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** any doc edit can break it (link or path checks). The hard-coded `GUIDES` and `LINKED_DOCS` lists. Content strings ("Where things belong", "--only=companion"). Screenshot `60_dev_guides_viewer`.

### `tests/suites/test_diagnostics.gd`

- **Role:** extends RefCounted; test suite for the `SessionLog` diagnostics (Visual Identity V01, Checkpoint E). Covers the JSONL file per session, the `session_start` line (version, commit, save_format 12, engine 4.7, UTC time), game events (game_started, hat, hat_warning, hat_lost, achievement_unlocked, hat_bought, funds, save, load ok/failed) in a 48 kn hat-loss scenario, no per-frame spam, `push_error` captured as `error`, no HOME or user name in the log, determinism with the log on or off, `KEEP_FILES` rotation, `MAX_LINES` truncation, and `MAX_BYTES`.
- **Depends on:** `SessionLog`, `GameVersion`, `GameSession`, `Simulation`, `SaveManager`, `HatState`.
- **State:** points `SessionLog.log_dir` at `user://test_diagnostics_suite`, cleans it and restores the previous dir; toggles `SessionLog.enabled`.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Invariants:** the log must not affect the simulation (same hat-loss time with or without it).
- **Tests:** —
- **Change risks:** pins `GameVersion.DISPLAY == "0.108a"` and save format 12, so every version bump needs this test updated. The expected `error` line depends on `push_error` capture.

### `tests/suites/test_eight_directions.gd`

- **Role:** extends RefCounted; test suite for the Iteration 13 eight-direction deck view. Covers `BoatArea.octant_for` (45° sectors, wrap, hysteresis 30.5° / 14.5°, no flip under ±5° wobble), the camera rotation for the course octant while the simulation keeps the full heading, the bow on screen for 8 headings, a mid-tween turn, W moving up the screen at 45° and 225°, the camera following the captain on the Petrel 36 (target within `_boat_view_bounds`), all four boats at NE, and the fixed-view setting.
- **Depends on:** `src/app/app.tscn`, `BoatArea` (`view_heading_override`, private `_update_camera`, `_boat_view_bounds`, `ZOOM_TRANSITION_S`, `COURSE_MIN_ZOOM`), `SettingsManager` (course view), `GameSession`, `Simulation`.
- **State:** sets `course_view` true and restores `DEFAULT_COURSE_VIEW`.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** real-time waits based on `ZOOM_TRANSITION_S`. The mid-tween angle window (10°–125°). `hold_actions` input timing. Screenshots `13_view_*`.

### `tests/suites/test_fishing.gd`

- **Role:** extends RefCounted; test suite for Iteration 13 "The Catch". Covers the `FishingCatalog` data (4 lures, ≥ 8 species, regions valid, Baltic at Copenhagen, lure spread, no trolling bites above `max_trolling_kn`, deterministic `pick`, trophy scoring), the line and bites on a fixed `check_interval_s` grid and independent of step size, landing and records (one-time renown, `HOLD_CAPACITY`, releases when full, `TROPHY_COUNT` ranked board, bonito exceptional, a broken line costs a lure), release and sale, lure purchase, the fishing round trip and duplicate-uid rejection, rod and trophy stations on every vessel, the panel flow with `Reel.land`, an unattended bite timing out, trolling underway, and `TrophyMenu` plus trophy persistence.
- **Depends on:** `src/app/app.tscn`, `tests/helpers/walkability.gd`, `tests/helpers/reel.gd`, `FishingCatalog`, `FishingState`, `PortCatalog`, `GameSession` (injects `_pending_bite`, `finish_fight`, `BITE_WAIT_SECONDS`), `VesselCatalog`, `BoatArea` (`ROD_HELM_CLEARANCE`), `FishingMenu`, `TrophyMenu`, `SessionState`, `SaveManager`.
- **State:** save slot 3; calls private `app._update_bite_wait`.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** bite timing depends on the catalogue RNG and check grid (waits up to 24 h). Exact prompt and HUD texts ("Fishing rod", "Fish on! Reel in", "1.  Atlantic bonito"). Screenshots `13_fishing_*`, `13_trophy_*`.

### `tests/suites/test_fishing2.gd`

- **Role:** extends RefCounted; test suite for Iteration 18 Fishing 2.0. Covers `FishingCatalog.REEL` checks and arcs by rarity, constant `ReelTiming` needle speed, press outcomes (Perfect, hit, miss, debounce, escape after 3 misses or `IDLE_SECONDS`), fairness by simulation (seed 18: careful ≥ 99 %, sloppy common ≥ 85 %, a careful 4-check catch < 12 s), weights within species ranges and grade thresholds (35/60/80 %), the `landed_kg` Perfect nudge, `FishArt` coverage, kinds and silhouette uniqueness (< 93 % overlap), `FishPortrait` blink and tail flick (no timers, reduce motion, hidden stops), keep preferences and release, sharks always released, junk discarded (~3–9 %), `reel_in` access from the cabin, the menu reveal and result, the persistence of keep and posture fields plus 0.104a defaults, fishing at anchor, and fast-time `PASSAGE_KEEPERS` and `FAST_BITE_COOLDOWN_S`.
- **Depends on:** `src/app/app.tscn`, `tests/helpers/reel.gd`, `ReelTiming`, `FishingCatalog`, `FishingState`, `FishArt`, `FishPortrait`, `FishingMenu`, `CatchBadge`, `GameSession` (injects `_pending_bite`, emits `fish_bite`), `Simulation` (`STOP_BITE`), `SettingsManager` (reduce motion), `SessionState`.
- **State:** resets keep preferences, passage posture, time scale and line at the end.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Persistence:** asserts the fishing keep, posture and counter fields round-trip, a 0.104a save gets the defaults, and `pending_bite` is never saved.
- **Tests:** —
- **Change risks:** "not in step" compares the two portraits' blink schedules over 30 simulated seconds (`_note_blink`): fails only if every blink of the second coincides (≤ 0.05 s) with one of the first. The earlier first-blink-only comparison failed by chance about 2 % of runs (44 of 2,000 pairs measured). Statistical thresholds depend on the seeds and the catalogue data. Image-overlap metric. Long simulated loops (up to 300×300 s for a bite at anchor).

### `tests/suites/test_galley_and_anchor.gd`

- **Role:** extends RefCounted; suite (I13 "The Cove"). Verifies the `AnchorSite.holding`/`holding_margin` model (more scope/better set/shelter hold better; rising wind steps well → fair → poor → dragging; too deep offshore, not on land). Also checks a stove and windlass reachable on every vessel (walkability), cooking via `CookingMenu` (fish refusal, oldest fish used, cooking time, well-fed), the underway "Too lively" stove rule, anchoring off Malmö via `AnchorMenu` (scope, set-quality dial, voyage paused, stationary fishing), dragging with `anchor_alarm`, sleeping at anchor, raising, and save/load at anchor.
- **Depends on:** `src/app/app.tscn`, `tests/helpers/walkability.gd`, `GameSession`, `Simulation`, `AnchorSite`, `AnchorState`, `WindField`, `SeaRouter`, `GeoMath`, `PortCatalog`, `VesselCatalog`, `CookingMenu`, `AnchorMenu`, `SaveManager`, `SessionState`.
- **Signals:** connects to `GameSession.anchor_alarm` during the drag test.
- **State:** `auto_advance = false`; calm wind, then `t.set_wind`; a `WindField.test_override` lambda rises to 30 kn mid-night; sets `GameSession._pending_bite` directly; uses save slot 3 (deleted).
- **Lifecycle:** test suite, instanced by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Anchoring needs `_sail_to_anchorage` (wind 90°/8 kn, up to 200×300 s) to reach an anchorable spot; later tests early-return if not anchored. The drag test picks the longest-fetch direction, so coastline data changes alter its path. Screenshots `13_*`.

### `tests/suites/test_gameplay_flow.gd`

- **Role:** extends RefCounted; end-to-end suite through real input (`press_action`, `click`, pushed mouse drags). Covers the main menu, new game (Arctic Wanderer 26), movement normalisation and collisions, interaction focus/prompts, the sleep menu, the chart (zoom/pan, port pick, plot/clear, waypoint drag/invalid/remove, unapplied-changes confirm), companionway round trips and the helm confirm. Also covers the pause menu with UI scale, settings apply/discard, save/overwrite/load, a damaged-save load, return to menu/Continue, and a first voyage to Kiel (20× time, sleep, save underway, gale warning via `WeatherFixtures.gale`, reroute at sea with no teleport, arrival). Ends with `_test_quit`. Steady Hands: the round-trip check records area and prompt before each E (diagnostics only). Steady Hands: `_to_hatch(spot, prompt)` moves `Companion` 400 px aside when the prompt is not the hatch's (root cause of the intermittent "ended on deck": E petted the cat). "No teleport": distance ≤ elapsed game time × 12 kn + 10 m (was a fixed 1e-3°, about 110 m, which ~43 s of sailing reached; failed 2/2 on the committed Mission A state).
- **Depends on:** `src/app/app.tscn`, `GameSession`, `Simulation`, `SaveManager`, `SettingsManager`, `SeaRouter`, `WeatherFixtures`, `HatConfig`, `Provisions`, `MainMenu`, `NewGameMenu`, `SleepMenu`, `WorldMap`, `MapView`, `PauseMenu`, `SettingsMenu`, `SaveLoadMenu`, `ConfirmDialog`, `AudioServer`.
- **State:** writes `t.TEST_SETTINGS_PATH` and save slots 1–3 under the test save dir; toggles `Simulation.auto_advance` for exact comparisons.
- **Lifecycle:** test suite; last entry in the runner's `SUITES` because pressing Quit ends the process (only when `t.failed == 0`).
- **Invariants:** `_same_state` allows real-time clock drift (stores and `hat.checked_until` follow the drift; numbers compared to 1e-9 relative, after the I17 JSON-precision flake).
- **Tests:** —
- **Change risks:** Most timing-sensitive suite: real-time clock runs during waits, fixed pixel coordinates for collisions, ordering-dependent (must stay last). Screenshots `01_*`–`18_*`.

### `tests/suites/test_golden_harbours.gd`

- **Role:** extends RefCounted; Golden Harbours suite. `_test_light_and_windows` (`light_of`; `window_spots` on helsingor/symi/bequia/valletta: ≥ 3 with ≥ 6 spots, all ≤ `MAX_WINDOWS`; first < 400 ms, cached < 2 ms). Sets `root.size` 1280×720, `Simulation.auto_advance = false`. `_arrive(from, to, hour_utc)` (new session, real `plan_route_to`/`depart`/`Simulation.advance`, then waits for `UiTheme.blend == _target_blend()`), `_hop_hours`. `_test_first_and_repeat` (Copenhagen→Helsingør 09:00 UTC: one moment, labels, no separate Log toast, no modal/pause, click dismiss; back to Copenhagen → one "ArrivalCard"; Helsingør again → none), `_test_quiet_places` (load slot 3 in Symi; interior and back), `_test_dusk_and_night` (Marmaris→Symi ~17.4 UTC in Danish: special stamp, dusk/dawn light, inside the screen; Castries→Bequia ~03 UTC: night). Screenshots `golden_helsingor_day_en`, `golden_symi_dusk_da`, `golden_bequia_night_en`.
- **Depends on:** `app.tscn`, `HarbourLooks`, `PortCatalog`, `SaveManager`, runner helpers.
- **Lifecycle:** in `test_runner.gd` `SUITES` after `test_steady_hands`; restores language, window size and `auto_advance`.

### `tests/suites/test_harbour_chart.gd`

- **Role:** extends RefCounted; suite (I006 checkpoint D). Verifies chart decluttering: only importance-1 harbours at world zoom, at least `MapView.DECLUTTER_PX` apart; regional zoom (60 px/°) and close zoom (140 px/°) show the right harbours; viewport culling; non-overlapping labels; hidden markers not pickable. Also covers harbour search UI (select, zoom, plot, sidebar size stable, WASD ignored while typing) and layout/lookup benchmarks at 15/50/100/all real and 1,000 synthetic harbours.
- **Depends on:** `src/app/app.tscn`, `WorldMap`, `MapView` (incl. private `_port_layout_key`, `_update_port_layout`), `PortCatalog`, `PortData`.
- **State:** temporarily swaps `map.catalog` for benchmark catalogues and restores the real one; `benchmark` array of rows.
- **Performance:** asserts worst layout < 50 ms at 1,000 harbours (machine-dependent).
- **Lifecycle:** test suite.
- **Tests:** —
- **Change risks:** Relies on specific ports (Visby, Mariehamn, Kalmar, Paros, Naxos, Korčula) and their importance values; benchmark threshold can flake on slow CI. Screenshots `114_*`–`117_*`.

### `tests/suites/test_harbour_life.gd`

- **Role:** extends RefCounted; suite (I12 "A Little Harbour Life", extended I14/I16). Headless: `HarbourFacilities.for_port` (Copenhagen major with haul-out; Lohals and the small Danish/island ports lack a boatyard; Kiel keeps `ALL`; fewer than half the ports can haul out; tiers). App part: on every vessel, the gangplank is active, walkable to the pontoon and back, every facility station is ashore and reachable, there are 3 signs, the camera follows ashore. Also: object highlights (no `debug_show_areas`), the Lohals refusals (switch vessel, repair, boatyard), Go Ashore (`GoAshoreMenu`, cost/renown/minutes, shore moment, resting state, no double pay, `REST_HOURS`, the record persists in a save), departure retracting the plank, save/load ashore, and the course view (camera rotation by `BoatArea.octant_for`, HUD upright, waves keep world direction, screen-relative walking, upright again in harbour or when the setting is off). I021: the expected no-boatyard list adds `dingle`, `isafjordur`, `symi`, `essaouira`, `st_helena` (the `small` tier of `add_i021_harbours.py`).
- **Depends on:** `src/app/app.tscn`, `tests/helpers/walkability.gd`, `HarbourFacilities`, `ShoreEvents`, `GoAshoreMenu`, `BoatArea`, `Interactable`, `PortCatalog`, `VesselCatalog`, `GameSession`, `Simulation`, `SaveManager`, `SettingsManager`.
- **State:** `_moor_in` relocates the boat via `replace_state`; toggles `SettingsManager` course view and restores the default; slot 3 (deleted).
- **Lifecycle:** test suite.
- **Tests:** —
- **Change risks:** Real-time `hold_actions` walks and timers (`ZOOM_TRANSITION_S`); the expected no-boatyard port list is hard-coded; the event choice depends on which `ShoreEvents` event is offered. Screenshots `172_*`–`179_*`.

### `tests/suites/test_harbours.gd`

- **Role:** extends RefCounted; data suite (I006 D/E, extended I16) with no app scene. Verifies the catalogue: ≥150 ports, unique `^[a-z][a-z0-9_]*$` ids, complete records, valid importance/region, 15 original ids, regional spread. Every port lies inside `CHART`, has a `find_port_approach`, and has land within 3 nm (Colón/Panama City exempt). Every added port has a valid route to its nearest original port. Also covers 17 representative voyages with nm bounds plus `validate_route`, `ports_in_rect` vs a scan, and `search`. I021: `REGIONS` adds north_america, west_africa, south_atlantic, indian_ocean, southeast_asia; 239 harbours.
- **Depends on:** `PortCatalog`, `PortData`, `SeaRouter` (`plan_route`, `validate_route`, `find_port_approach`, `grid`), `NavGrid`, `GeoMath`.
- **Performance:** routes every non-original port (prints elapsed ms); one of the heavier pure-data suites.
- **Lifecycle:** test suite.
- **Tests:** —
- **Change risks:** Distance bounds and `REGIONS` list must track catalogue/land-mask changes; the coast check depends on the finest grid's cell size.

### `tests/suites/test_hat.gd`

- **Role:** extends RefCounted; suite (Visual Identity V01 A). Core rules run headless: start state, hook/H toggle with `hat_changed` order, `HatConfig` strain bands and per-hat thresholds, light wind safe, warning then loss (`hat_warning`/`hat_lost`), recovery below deck, step-size independence moored and underway, and save/load mid-exposure. Also: shelter while sleeping/working, the warning drops time scale to 1×, no vessel damage, rescue keeps the hat, vessel switching, `buy_hat` refusals/charging, v9 migration and invalid states, and `HatStory` text. App part: hook in every cabin, companion-spot clearance, player hat visual, blow-away effect and `HatBadge` states, grocery hat row.
- **Depends on:** `src/app/app.tscn`, `tests/helpers/walkability.gd`, `GameSession`, `Simulation`, `HatState`, `HatConfig`, `HatStory`, `HatBadge`, `Toasts`, `SaveManager`, `SessionState`, `WeatherFixtures`, `t.make_route`.
- **Signals:** connects to `GameSession.hat_changed`, `hat_warning`, `hat_lost`, `hat_bought`, `funds_changed` during checks.
- **Persistence:** checks the current `SaveManager.SAVE_VERSION`, v9→current migration (`checked_until = game_time`), and rejection of unknown/inconsistent hat states.
- **Invariants:** hat checks run on fixed game-minute boundaries, so the loss time is identical for 1 s, 20 s, 137.3 s and single large steps.
- **Lifecycle:** test suite.
- **Tests:** —
- **Change risks:** Exact constants asserted (EUR 15, 60 s interval, strain values, funds set to 100 in the shop test); wall-clock waits for the effect's self-removal.

### `tests/suites/test_joy_journey.gd`

- **Role:** extends RefCounted; scripted 18-step integration (I18 SAVE-4). Steps: anchorage waypoint toward Gothenburg via `WorldMap.insert_waypoint`/`toggle_anchorage`/`use_anchorage_suggestion`, depart, manual trim, trolling bite injected via `_pending_bite`, reel landing with release by keep preferences, Long Passage via `Simulation._passage_tick` until `is_holding_at_anchorage`, `AnchoragePrompt`, `drop_anchor`, anchor signals, `make_coffee`, companion follow to deck, save/load (fishing/anchor/navigation/companion/log JSON-identical, no prompts or repeat walk), raise, and arrival without a second `STOP_ANCHORAGE`.
- **Depends on:** `src/app/app.tscn`, `tests/helpers/reel.gd`, `WorldMap`, `GameSession`, `Simulation`, `SeaRouter`, `AnchorSite`, `FishingMenu`, `FishingState`, `AnchoragePrompt`, `CompanionState`, `SaveManager`.
- **State:** wind 200°/9 kn; `auto_advance = false`; calls private `app._update_companion_follow`; save slot 3 (deleted).
- **Lifecycle:** test suite.
- **Tests:** —
- **Change risks:** Strictly ordered; an early failure cascades. The offshore point search depends on the route geometry and `AnchorSite.MAX_LAND_NM`; the companion walk waits up to 30 s.

### `tests/suites/test_life_aboard.gd`

- **Role:** extends RefCounted; suite (I003b). Verifies the new-game cat/dog choice, companion spots and step-independent schedule, petting (SFX bus, mute), `SleepMenu` limits (1–12 h, default 6), sleep from cabin and chart, the wake spot clear of furniture, and chart sidebar geometry stable across states, destinations and UI scales. Also: weather-warning-interrupted sleep (`WeatherFixtures.gale`), arrival ends sleep, the helm sail check (engine loop stops), sail motion bounds/leeward side, spinnaker geometry, companion persistence, v3 save migration, and a dog game.
- **Depends on:** `src/app/app.tscn`, `GameSession`, `Simulation`, `NewGameMenu`, `SleepMenu`, `WorldMap`, `SailRig`, `ShipCompanion`, `CompanionState`, `PropulsionState`, `AudioManager`, `SaveManager`, `WeatherFixtures`.
- **State:** boards `starling_33` via `t.board` (walks written for that cabin); writes a raw v3 `slot_3.json`; slots 2–3 deleted.
- **Lifecycle:** test suite.
- **Tests:** —
- **Change risks:** Hard-coded cabin coordinates (`WAKE_MARKER = (282, 0)`) and pixel bounds for sail motion; real-time sampling of sail movement over 10 s.

### `tests/suites/test_lighting.gd`

- **Role:** extends RefCounted; suite (I17 LGT). Pure `Daylight` checks: noon/midnight elevation in Copenhagen, the Tromsø midnight sun, longitude-based phase, phase order, peak at local solar noon, colour steps < 0.06 per 5 min. App part: for four boats, night lamps (≥3, pool textures), ambient luminance band, `Interactable.light_compensation`, `FixtureShadows`, `ContactShadow`, `CornerShade`, and day state. Also: deck/harbour/night light groups moored vs underway, warm dusk, Long Passage-pace smoothness (< 0.12 per frame), and the light snapping after a state replace.
- **Depends on:** `src/app/app.tscn`, `Daylight`, `BoatLighting`, `Interactable`, `GameSession`, `Simulation`, `SessionState`.
- **State:** sets `game_time` and `vessel_id` via `GameSession.replace_state`.
- **Lifecycle:** test suite.
- **Tests:** —
- **Change risks:** Numeric colour/luminance thresholds; light group names (`"dark"`, `"day"`, `"harbour"`, `"night"`). Screenshots `17_*`, `31_*`.

### `tests/suites/test_living.gd`

- **Role:** extends RefCounted; suite (I005c). Headless rules: `Simulation.work` (1–8 h clamp, EUR 25/h, uses stores like idle time, works while paused, refused at sea); `get_provisions_price`/`buy_provisions` (EUR 10 per missing day, rounding up, refusal without funds or at sea, same price in all ports); no `restock_provisions`; repair charges `service_quote`; save/load of funds and stores. App part: work station and `WorkMenu` on four boats, grocery station and `GroceryMenu` (prices, not-enough-money note, gone underway).
- **Depends on:** `src/app/app.tscn`, `tests/helpers/walkability.gd`, `GameSession`, `Simulation`, `BoatCare`, `SaveManager`, `PortCatalog`, `WorkMenu`, `GroceryMenu`, `WeatherFixtures`.
- **State:** edits `funds`/provisions via `replace_state` and `set_provisions_for_testing`; slot 2 (deleted).
- **Lifecycle:** test suite.
- **Tests:** —
- **Change risks:** Asserts exact euro amounts that depend on starting funds (EUR 10,000) and 14-day stores.

### `tests/suites/test_living_world.gd`

- **Role:** extends RefCounted; presentation suite (0.100b). Verifies `WaterLife.atmosphere_for` by harbour kind; sailor arm swing (`SailorDrawing.hand_position`, `get_swing`) with unchanged collision radius 20; moored water (drifters ≤ max, laps, no collision nodes, z-order, hides classic ripples, moves while paused, off in Classic art); and illustrated deck/cabin sprites plus hat hook on every vessel. Underway: waves follow the wind relative to heading and scale with wind (≤ `MAX_WAVES`), the camera zooms by `BoatArea.UNDERWAY_ZOOM_FACTOR` with an eased transition and returns on arrival. Steady Hands: walks `move_right` from (250, 0) with the companion moved aside, up to two `Player.STRIDE` (cap 3 s), and checks walked ≥ one stride and range > 0.6. From the start spot (−252, 0) the walk hit fittings after 31 px down or 52 px forward (< one stride), so the range topped out at 0.59–0.60.
- **Depends on:** `src/app/app.tscn`, `WaterLife`, `HarbourArt`, `PortCatalog`, `SailorDrawing`, `VesselVisual`, `VesselCatalog`, `BoatArea`, `SettingsManager`, `GameSession`, `Simulation`.
- **State:** sets art style Illustrated and course view off, restores course view default.
- **Lifecycle:** test suite.
- **Tests:** —
- **Change risks:** Real-time `Input.action_press` and timers; sprite resource paths (`/<id>/illustrated/deck/`). Screenshots `160_*`–`166_*`.

### `tests/suites/test_localization.gd`

- **Role:** extends RefCounted; suite (I019). Parses `locale/messages.pot` and verifies that every msgid (> 2,000) has a Danish entry with identical placeholders, including plurals. Also covers `Loc.decimal`/`thousands`, `format_money`, `format_game_time`, `compass_name`, `format_duration`, `TimePassage.date_text` in en/da, and the first-launch `LanguagePicker` (Esc cannot skip; choice applied and persisted; not asked again). Also: the Settings language option, Danish overflow check of main menu/settings/HUD/pause, `BoatArea.get_lighting()` found in Danish (the node name is not translated), and language-neutral saves.
- **Depends on:** `src/app/app.tscn`, `Loc`, `SettingsManager`, `TranslationServer`, `locale/da.po`, `LanguagePicker`, `MainMenu`, `GameSession`, `Simulation`, `WindField`, `TimePassage`, `SaveManager`.
- **State:** resets/saves settings language (test settings file); opens and frees the app several times; slot 3.
- **Lifecycle:** test suite; the runner sets `Simulation.sea_encounters = true` for it.
- **Tests:** —
- **Change risks:** Any new user-facing string without a da.po entry fails it; the overflow check is resolution-dependent.

### `tests/suites/test_long_passage.gd`

- **Role:** extends RefCounted; suite (I16). Verifies Copenhagen→Gothenburg with real wind gives the same Captain's Log record (end time, nm, hazard, condition) in 20-min `advance` steps and in `PASSAGE_RATES[2]` ticks. Also covers `passage_interrupted` stops (stores, bite, arrival), refusals (harbour, unsupported rate), pause, stop, and reset on `replace_state`. Further: per-vessel `passage_stores_days` and buying passage stores, `PassageReadiness` (forecast/stores items, advisory only), a Suva→Avarua save just past the Date Line, world firsts (`world:*` objectives, no double renown, `_is_atlantic_crossing`), and the HUD `passage_panel`.
- **Depends on:** `src/app/app.tscn`, `Simulation`, `GameSession`, `WindField`, `VesselCatalog`, `Provisions`, `PassageReadiness`, `SaveManager`, `PortCatalog`, `GeoMath`, `Hud`, `SaveLoadMenu`.
- **Signals:** connects to `Simulation.passage_interrupted`.
- **State:** clears `WindField.test_override` for the equivalence test; sets `wind_seed = 7`; slot 3.
- **Invariants:** Long Passage time is not saved; the voyage is the same at any rate.
- **Lifecycle:** test suite.
- **Tests:** —
- **Change risks:** Long guard loops (up to 100,000 ticks) make it slow; the equivalence check uses the real weather, so weather-model changes may show up here first.

### `tests/suites/test_magic_anchor.gd`

- **Role:** extends RefCounted; suite (0.105b MAGIC/SKILL/NANCH). Covers `TimingCheck` (deterministic arc, constant needle speed, perfect/miss, `ReelTiming` subclass) and `MagicAnchorDeployment` (checks by wind level, arc widths, misses allowed). Purchase: Boat care points to the chandlery, bought once via `TradePanel` at `HarbourTrades.get_magic_anchor_price()`, kept across vessels. Deployment at `OPEN_SEA (-30, 30)`: normal anchor too deep, cancel, three misses cost time, retry, two perfects give `bonus_kn = 2`, depth kept as `DepthService.SOURCE_ESTIMATE`. Engine: anchoring stops it, `engine_start_refusal` at anchor, raising doesn't start it, an old save at anchor with the engine on loads stopped. Offshore save/load, dragging in 50 kn with 1–2 alarms, never on land.
- **Depends on:** `src/app/app.tscn`, `TimingCheck`, `ReelTiming`, `MagicAnchorDeployment`, `AnchorMenu`, `BoatCareMenu`, `TradePanel`, `HarbourTrades`, `AnchorSite`, `AnchorState`, `DepthService`, `PlannedRoute`, `Voyage`, `PropulsionState`, `SeaRouter`, `GameSession`, `SaveManager`.
- **Signals:** connects to `GameSession.anchor_alarm`.
- **State:** builds an underway state directly (`_underway_at`) via `replace_state`; slot 3 (deleted).
- **Lifecycle:** test suite.
- **Tests:** —
- **Change risks:** Sets the dial angle directly; a 1.3 s real timer for the brass flourish. Screenshots `rb_09`–`rb_12`.

### `tests/suites/test_navigation_views.gd`

- **Role:** extends RefCounted; suite (I17 NAV). Verifies a `CabinWorldMap` frame and `world_map` station in every cabin (focusable, 4-point highlight via `HighlightResolver`). Dreamer's Map (`WorldMap.MODE_DREAM`): no wind layer/weather/toggle, panning across the Date Line samples no wind chunks (≤ 2 point queries per frame), search, and selection details with visited status. `VoyageDaydream`: a real route to Papeete, 1–3 real stops in order near the route, cached repeat (< 2 ms), state unchanged, short-hop and tone variety. Also: "Plan it at the chart table" opens `MODE_STATION` with the same router path; the station chart is regional (300–500 nm across) in Copenhagen and Papeete; underway, the next turn and course match the voyage, and wind arrows are never on land.
- **Depends on:** `src/app/app.tscn`, `WorldMap`, `MapView`, `CabinWorldMap`, `HighlightResolver`, `VoyageDaydream`, `WeatherModel`, `SeaRouter`, `NavGrid`, `PortCatalog`, `GeoMath`, `GameSession`, `Simulation`.
- **State:** relocates the boat via `replace_state`; wind 270°/14 kn for the underway part.
- **Performance:** asserts wind-sampling counts and daydream cache timing.
- **Lifecycle:** test suite.
- **Tests:** —
- **Change risks:** Uses private `MapView` members (`_free_view_size`, `_clamp_camera`); the timing check (< 2 ms) can flake. Screenshots `17_*`.

### `tests/suites/test_objectives.gd`

- **Role:** extends RefCounted; suite (I006 B). Verifies `ObjectiveCatalog`: 10–20 regular objectives, valid/unique, all types used, set rewards, 3 deterministic generated distant-harbour objectives, `euros_per_renown == 2`, invalid definitions refused. Rewards: the first voyage to Kiel pays 100 once at arrival, repeat trips pay only `voyages_5`, `blue_water` repeats per voyage, `evaluate` is idempotent. Also: a rescue pays only distance (25), `heavy_weather` vs `clean_150`, save/load and repeated loads pay nothing, unpublished > lifetime is rejected, v8 migration (no back-pay, log kept), and the Captain's Log renown/Objectives tab UI.
- **Depends on:** `src/app/app.tscn`, `ObjectiveCatalog`, `ObjectiveProgress`, `CaptainsLog`, `CaptainsLogMenu`, `GameSession`, `Simulation`, `SaveManager`, `SessionState`, `WeatherFixtures`, `WeatherModel`, `PortCatalog`, `GeoMath`.
- **Signals:** connects to `GameSession.renown_awarded` (records into `awarded`).
- **Persistence:** writes a raw v8 `slot_3.json`; uses slots 2–3 (deleted).
- **Lifecycle:** test suite.
- **Tests:** —
- **Change risks:** Exact renown sums and objective id lists; voyages are finished in 24 h `advance` steps, so speed/route changes shift distances (e.g. "900–1,000 nm" progress).

### `tests/suites/test_presentation.gd`

- **Role:** extends RefCounted; test suite (Iteration 17): fenders out in harbour / stowed underway on all four boats (`FenderStowage.find_fenders` on deck art; art file MD5 unchanged; restored after loading slot 3); `SailRig` z-order above player and see-through (`modulate.a`) when `rig.covers()` the player; `HarbourFacilities.describe_services` matches `HarbourFacilities.PREVIEW`/`for_port` data for every port, no "Fuel"; docking arrival from the cabin (deck shown, engine loop, Space skips, one `Simulation.arrived`, log arrival +1, food unchanged).
- **Depends on:** `res://src/app/app.tscn`, `GameSession`, `Simulation`, `SaveManager`, `AudioManager`, `BoatArea`, `VesselVisual`, `FenderStowage`, `SailRig`, `HarbourFacilities`, `PortCatalog`, `SessionState`.
- **Signals:** temporarily connects to `Simulation.arrived`.
- **State:** `Simulation.auto_advance = false` (restored); wind via `t.set_wind`; ends with `GameSession.end_session()` and `t.use_calm_wind()`.
- **Lifecycle:** test suite, preloaded in `tests/test_runner.gd` `SUITES`; `run(runner)` awaited by the runner.
- **Tests:** —
- **Change risks:** Real-time waits (`BoatArea.DOCKING_SECONDS`, 0.6 s fades) and physics frames make it timing-sensitive; the under-the-boom spot search depends on deck walkability; screenshots `17_*`.

### `tests/suites/test_publishing.gd`

- **Role:** extends RefCounted; test suite (Iteration 006 C): `GameSession.get_publish_quote()` / `publish_travel_update()` (renown → euros at `ObjectiveCatalog.euros_per_renown`, default 2; harbour only; no double pay; lifetime = published + unpublished), persistence via slot 2, `Simulation.work` and `buy_provisions` unaffected; UI: `CaptainsLogMenu` PublishButton/PublishHint/RenownValue, `PublishMenu` labels and Cancel/confirm, toast text, `WorkMenu` PublishButton.
- **Depends on:** `GameSession`, `Simulation`, `SaveManager`, `ObjectiveCatalog`, `WeatherFixtures`, app scene (`open_captains_log`, `open_work_menu`, `modals`, `toasts`).
- **Signals:** connects to `GameSession.travel_update_published` during the logic tests.
- **State:** Temporarily mutates `ObjectiveCatalog.get_default().euros_per_renown` (restored); calm wind, `WeatherFixtures.use([])`.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Hard-coded amounts (start funds 10000, 100 renown at Kiel, €50 for 2 h work) and exact UI strings; `_sail_to` loops `Simulation.advance(24 h, true)` up to 60 times; screenshots `112_*`, `113_*`.

### `tests/suites/test_reassessment.gd`

- **Role:** extends RefCounted; test suite (Iteration 003b): `PropulsionController.evaluate` with reassessment flags decides at once in clear conditions but keeps min engine/sailing times and hysteresis; a heading change keeps the stall timer while becalmed; `GameSession.change_course` mid-voyage re-evaluates without moving the vessel or time; `Simulation.reassess_propulsion()` never forces a mode nor resets timers, returns empty in port; `describe_reassessment` message prefixes.
- **Depends on:** `PropulsionController`, `PropulsionState`, `VesselProfile`, `WindField.Sample`, `GameSession`, `Simulation`, `res://src/app/app.gd` (static `describe_reassessment`), `PortCatalog`.
- **State:** Boards `starling_33` via `t.board` (timings tuned to its speeds); toggles `Simulation.auto_advance`.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** `_wind_for` bisects wind speed against `profile.sail_speed_kn`, so polar/profile changes shift setups; checks exact message prefixes ("Sailing conditions favourable", "Light wind", "Insufficient sailing performance", "Sails are drawing well").

### `tests/suites/test_regions.gd`

- **Role:** extends RefCounted; test suite (Iterations 14/16): nested nav grids (world/europe/denmark; factor 6, 360 cells/deg; `grid_at`, `region_id_at`, `child_at`), region.json licence metadata, inland GeoNames towns are `NavGrid.LAND`, straits navigable, 25 Danish harbours have `find_port_approach`, 8 Danish voyages valid and < 3 × direct + 10 nm, anchoring/coastal fishing off Danish harbours, location recovery in `GameSession.replace_state` (voyage on land moved < 15 nm and re-planned; anchor on land moved; planned route across land re-planned; valid voyage untouched), performance (fresh `SeaRouter.load_from` < 15 s, cold route < 3 s, zoom < 50 ms), chart detail by zoom (`MapView.is_region_detail_shown`).
- **Depends on:** `SeaRouter`, `NavGrid`, `PortCatalog`, `GeoMath`, `PlannedRoute`, `Voyage`, `SessionState`, `GameSession`, `AnchorSite`, `WindField`, `FishingCatalog`, `WorldMap`, `MapView`, app scene; reads `res://data/navigation/regions/denmark/region.json`.
- **State:** Reads `GameSession.get_last_location_recovery()` (`kind`, `moved_nm`, `replanned`).
- **Lifecycle:** test suite in `tests/test_runner.gd`; prints a measurements table.
- **Tests:** —
- **Change risks:** Loads a second full `SeaRouter` (slow, memory); wall-clock thresholds; zoom checks depend on `units_per_degree`; port id list must match the catalogue.

### `tests/suites/test_route_wrap.gd`

- **Role:** extends RefCounted; test suite (Iteration 18, finding I17-S3): a planned route stays drawn while panning the chart 53 × 15° each way. Brute-force expected screen samples over world copies k = −3..3 vs `MapView._path_copies`; no drawn segment longer than half `_world_width`; route fingerprint (waypoints, legs, destination, distance, vessel, unsaved flag) unchanged; when rendered, samples pixels for `MapView.BRASS`/`SEAFOAM`. Cases: Middelfart→Papeete (whole world, regional, 3 waypoints), Papeete→Auckland with a waypoint at 179.9°, committed course underway, Dreamer's Map daydream.
- **Depends on:** app scene (`open_chart`, `open_dream_map`, `close_chart`), `WorldMap` (`plot_course_to`, `insert_waypoint`, `apply_course`, `imagine_voyage`, `discard_changes`), `MapView` (camera, `projection`, private `_free_view_size`, `_clamp_camera`, `_path_copies`, `_world_width`), `GeoMath.unwrap_path`, `GameSession`, `Simulation`.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Relies on private `MapView` members; pixel check only when not headless (colour tolerance 0.18, ≥ 40 % hits); slow (many frames); screenshot `18_route_after_panning_west`.

### `tests/suites/test_routing.gd`

- **Role:** extends RefCounted; test suite (geographic routing, Iteration 16 world chart): all precomputed graph edges pass `is_segment_navigable` (canal links excepted), ≥ 150 ports with bounded approaches (`approach_radius_nm`), Copenhagen→Kiel avoids Zealand, representative European routes and straits (axis-crossing windows), all European port pairs and every international port from Copenhagen, waypoint validation ("Waypoint 1" errors, blocked legs), `GameSession.set_planned_route`/`depart` refuse land-crossing routes, safe failures (Black Sea, Caspian, inland, unknown port), world passages incl. Panama, Date Line crossings the short way (`GeoMath.wrap_delta`). Independently checks segments against vector land (europe_land.json clipped by region bounds + region `land.json` fill tiles + `WorldLand.regional_fill`).
- **Depends on:** `SeaRouter`, `PortCatalog`, `PortData`, `GeoMath`, `PlannedRoute`, `MapProjection`, `NavGrid.REGIONS_INDEX`, `WorldLand`, `GameSession`, runner `t.make_route`; reads `res://data/navigation/europe_land.json`, `res://data/navigation/world/land.res`, region folders.
- **Performance:** All-pairs European loop is the heaviest part; per-route thresholds 1500 ms, failures < 3000 ms.
- **Lifecycle:** test suite in `tests/test_runner.gd` (second in `SUITES`).
- **Tests:** —
- **Change risks:** Hard-coded strait windows, `PANAMA_PASSAGE` rect and distance ratios (≤ 1.6 × + 60 nm) break when nav data is rebuilt; wall-clock limits on slow machines.

### `tests/suites/test_sail_trim.gd`

- **Role:** extends RefCounted; test suite (Iteration 18 TRIM): `SailTrim.best` by TWA/strength and symmetric on both tacks; `SailTrim.factor` = 1.0 when auto, bounded by `BONUS`/`PENALTY`; `SailTrim.feedback` strings; underway (6 h, re-trimmed every 5 min) gain ≤ BONUS, loss ≥ −PENALTY, identical propulsion modes, potential/food/wear unaffected, no stacking, no effect under engine; 5 s vs 1 h steps equal; persistence (`trim_auto`, `trim_value`; save without `vessel.sail_trim` → auto); setting kept across wind change; UI: `SailingPanel.get_value("trim")`, wheel action `sail_trim`, `SailTrimPanel` slider/feedback, `move_left` eases, `ui_accept` hands back to crew, T closes.
- **Depends on:** `SailTrim`, `GameSession` (`set_sail_trim`, `get_sail_trim`), `Simulation` (`evaluate_propulsion`, `advance`), `SessionState`, app scene (`hud`, `get_wheel_actions`, `modals`), `SailingPanel`, `SailTrimPanel`.
- **State:** Snapshot `_start` (10 min out of Copenhagen towards Las Palmas, wind 270°/14 kn) is replaced before each case.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Gain/loss thresholds (> 2 %, < −4 %) depend on the polar and route geometry; feedback strings; screenshots `18_sail_trim_*`.

### `tests/suites/test_sailing.gd`

- **Role:** extends RefCounted; test suite: pure `PropulsionController.evaluate` behaviour (initial choice, sustained poor wind → `REASON_POOR` within 1–2 h, stall → `REASON_STALL` after `stall_delay_s`, brief dips ignored, engine stop after `engine_stop_confirm_s`, 3.5/6 kn hysteresis, no cycling over 48 h, course change > 30° resets average, spinnaker state); timeline step independence on Lisbon→Gibraltar with a deterministic `WindField.test_override` (one step, 1×/5×/20× ticks, `Simulation.sleep`) giving identical progress and switch times; wind-aware `Simulation.get_eta` within 5 %; calm ETA = motoring at engine speed; `Simulation.weather_warning` with a `WeatherFixtures.gale`; course change re-evaluates; save/load restores propulsion and `wind_seed`, rejects invalid mode/negative speed; v2 save migration (slot 3 file written by hand).
- **Depends on:** `PropulsionController`, `PropulsionState`, `VesselProfile`, `WindField`, `Simulation`, `GameSession`, `SessionState`, `SaveManager`, `WeatherFixtures`, `PortCatalog`.
- **Signals:** connects to `GameSession.propulsion_changed`, `Simulation.arrived`, `Simulation.weather_warning` temporarily.
- **Persistence:** Exercises `vessel.propulsion` and `wind` save fields and v2→current migration.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** The 1× pattern ticks at 1/60 s for 12 game hours (slow, guard 2,000,000); `starling_33` boarded for timings; expected mode sequence [engine, sail] depends on the scripted wind.

### `tests/suites/test_sailing_correctness.gd`

- **Role:** extends RefCounted; test suite (Iteration 17 BOAT-1, SAVE-1..3): course-view deck orientation follows heading octant (`BoatArea.get_view_octant`, `octant_for`) through autopilot turns at amidships/bow/stern and after the cabin; save/load underway round trips (helm, bow, stern, cabin, after `change_course`, at anchor, gale at night via `WeatherFixtures`) compare full `to_dict()` to 1e-9 relative and player position relative to the boat; off-deck saved position falls back to spawn; same save sailed twice gives identical weather/position/condition; F5 quicksave (one write, manual slots untouched, refused with a modal open), F9 asks then restores exactly, repeated F9 ignored, no quicksave → message only.
- **Depends on:** app scene (`load_slot`, `quicksave`, `quickload`, `open_pause_menu`, `_last_quick_msec`, `_show_current_boat_area`), `BoatArea` (private `_boat_view_bounds`), `GameSession`, `Simulation`, `SaveManager` (`QUICKSAVE_SLOT`, `get_slot_bytes`, `slots_changed`), `SettingsManager.set_course_view`, `SessionState`, `WindField`, `WeatherFixtures`.
- **State:** Forces course view on (restored to `DEFAULT_COURSE_VIEW`); clears slots 1–3 and quicksave.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Real-time waits (`BoatArea.ZOOM_TRANSITION_S`); `_sail_to_next_octant` depends on the Las Palmas route turning; touches private app fields; prints diffs on mismatch; screenshot `17_deck_turned_with_heading`.

### `tests/suites/test_sailing_presentation.gd`

- **Role:** extends RefCounted; test suite: presentation of propulsion with forced states (`_force` builds a `PropulsionState` and calls `GameSession.set_propulsion`): `SailRig` sail side to leeward, main eased more on a beam reach, spinnaker visible at 150° and taken down at 100°, furled under engine; engine loops (`ENGINE_LOOP`, `ENGINE_MUFFLED_LOOP`) on SFX bus, loud on deck / muffled inside without restart, stop when sailing, on `complete_voyage` and in main menu; HUD `PropulsionLabel`/`WindLabel`/`RouteDetail` texts; chart wind overlay (`wind_layer`, `WindLegend`, `WindToggle`, cursor readout) and panning cost < 100 ms/frame.
- **Depends on:** app scene (`hud`, `open_chart`, `show_main_menu`, `_on_area_change_requested`, engine constants), `SailRig`, `BoatArea`, `AudioManager`, `GameSession`, `Simulation`, `PropulsionController`, `PropulsionState`, `WindField`, `WorldMap`.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Exact HUD string prefixes ("Motoring", "Under sail · broad reach"); waits for rig animations (5 s timeouts); real wind field enabled for the overlay; screenshots `19_*`–`24_*`.

### `tests/suites/test_save_manager.gd`

- **Role:** extends RefCounted; test suite: `SaveManager` slots — EMPTY/out-of-range (0, 4) rejected, `save_to_slot` writes `slot_N.json` atomically (no `.tmp` left), slot info metadata (area, location, destination, timestamp), round trip equals `to_dict()`, `version == SAVE_VERSION`, `get_most_recent_valid_slot`, `.bak` on overwrite and fallback to it, CORRUPTED (garbage, invalid area, empty file), UNSUPPORTED (version 99), missing session rejected, failed write (directory blocked by a file) leaves the existing save intact.
- **Depends on:** `SaveManager` (`save_dir`, `Status`, `SAVE_VERSION`), `SessionState.create_new`, runner `TEST_SAVE_DIR`, `t.make_route`.
- **Persistence:** Exercises the slot file format and backup/atomic-write strategy.
- **Lifecycle:** test suite in `tests/test_runner.gd`; `run(t)` uses the runner directly.
- **Tests:** —
- **Change risks:** Waits 1.1 s real time so slot 2 is newer; temporarily reassigns `SaveManager.save_dir`; expects display names "Deck"/"Cabin"/"Copenhagen"/"Kiel".

### `tests/suites/test_secret_achievements.gd`

- **Role:** extends RefCounted; test suite (Visual Identity V01 B): 7 secret objectives in `ObjectiveCatalog` (secret, not repeatable, reward ≤ 40; 16 regular unchanged; `ObjectiveCatalog.validate` refuses bad hat objective); triggers via hat loss in wind: Captain No-Hat (+10, completion time = loss), Hat Trick (3rd loss, +15), exactly once after JSON reload, Hat Tax (spent ≥ €100), Last Straw (`is_met_by_hat_event` 300 s window; in-game with a seed found via `HatConfig.threshold_for`), Hold Onto Your Hat (kept/lost/never worn), Captain of Distinction (10th voyage with original hat), Sea Wears a Hat (`HatStory.open_water_nm` ≥ 20 nm, Aberdeen→Stavanger); no farming (12 losses → 35 renown, worth less than hats). UI: `CaptainsLogMenu` objectives tab hides titles/text, "N secret achievements are still to discover", `Secret_<id>` entry after discovery, toast text, Log tab `Moments`/`Passages`.
- **Depends on:** `ObjectiveCatalog`, `PortCatalog`, `GameSession` (hat API, `renown_awarded`), `Simulation`, `SessionState`, `HatState`, `HatConfig`, `HatStory`, `WeatherFixtures`, app scene (`open_captains_log`, `toasts`), `CaptainsLogMenu`.
- **Signals:** connects to `GameSession.renown_awarded` during logic tests.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Depends on hat loss thresholds at 36/48 kn and hat price €15; exact titles/texts from objectives.json; seed search loop (≤ 500); screenshots `125_*`–`127_*`.

### `tests/suites/test_settings_and_audio.gd`

- **Role:** extends RefCounted; test suite: `SettingsManager` defaults on missing file, `AUDIO_BUSES` exist and route to Master, `set_volume` → bus dB / mute / clamp, save/load round trip (volumes, VSync, window mode, UI scale), `snapshot`/`restore_snapshot`, invalid/unparseable config values fall back or clamp; non-headless only: window modes map to `DisplayServer` modes, VSync (skipped if unsupported), windowed size; `AudioManager` fixed one-shot player pool, bus routing, ambience start/replace/stop, music play/stop. I022: Wind default 100, `set_volume(&"Wind", 35)` sets the bus dB, save/restore_defaults/load round trip.
- **Depends on:** `SettingsManager`, `AudioManager`, `AudioServer`, `DisplayServer`; placeholder audio under `res://assets/audio/placeholder/`; runner `TEST_SETTINGS_PATH`.
- **Persistence:** Writes/deletes the test settings config file.
- **Lifecycle:** test suite in `tests/test_runner.gd`; `run(t)` uses the runner directly.
- **Tests:** —
- **Change risks:** Hard-coded defaults (Music 70, Master 80, Ambience 70); window/VSync checks are driver-dependent.

### `tests/suites/test_simulation.gd`

- **Role:** extends RefCounted; test suite: clock (start "Fri 1 May 2026, 08:00 UTC", 1×/5×/20× = 60/300/1200 game s per real s, stops while tree paused), voyage basics (2 h at 5 kn = 10 nm, position on route, motoring in calm), step independence (1 × 15 h vs 900 × 1 min), arrival once and exactly at distance/speed, `STOP_ARRIVAL`, next voyage from arrival port, `Simulation.sleep` (8 h = 40 nm, stops on arrival, in port only time), weather warnings with a `WeatherFixtures.gale` "test_strong_winds" on the Copenhagen→Kiel course (one warning ~`WARNING_HORIZON_HOURS` ahead, same point at 20×, drops to 1×, sleep woken at same point, wind/propulsion/exposure inside the area), `change_course` at sea (refused on land, no teleport, revision 2, area/player preserved, new destination).
- **Depends on:** `Simulation`, `GameSession`, `SessionState`, `WeatherFixtures`, `WeatherModel`, `SeaRouter`, `PortCatalog`, `GeoMath`, `VesselProfile`, `Voyage`.
- **Signals:** connects to `Simulation.weather_warning` and (temporarily) `Simulation.arrived`.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Assumes calm wind (default runner fixture) and 5 kn engine speed; real-time 0.3 s timers for the pause check; fixture area position must stay on the routed course.

### `tests/suites/test_solar_panels.gd`

- **Role:** extends RefCounted; test suite (0.105b §14A B): `VesselVisual.get_solar_panels()` on all four boats with 1/2/2/3 panels and area ordered by size; panel rects free of walkable cells (`TestWalkability.walkable_cells`), stations and `DeckCompanionSpots`; no collision nodes; z-order under the player; stay aft through heading overrides 45°/200°; no processing; visible moored, at anchor (with anchor signals) and in `BoatyardMenu` preview; nothing "solar/battery/charging" in the save; not in `BoatCare.get_upgrades()`.
- **Depends on:** app scene (`start_new_game`, `open_boatyard`, `hud`, `toasts`), `BoatArea` (`view_heading_override`, private `_update_camera`), `VesselVisual`, `SolarPanels`, `TestWalkability` (tests/helpers), `DeckCompanionSpots`, `BoatCare`, `BoatyardMenu`, `GameSession`, `SettingsManager`, `PlannedRoute`, `Voyage`.
- **State:** Forces course view on (restored to default).
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Real-time waits (`ZOOM_TRANSITION_S + 0.4`); depends on node paths `Visual`, `Layout/Stations`, `Layout/DeckCompanionSpots`; screenshots `rb_13_*`–`rb_15_*`.

### `tests/suites/test_soundtrack.gd`

- **Role:** extends RefCounted; test suite (music injection): `MusicDirector.TRACKS` OGGs load, loop, > 8 min and match `get_loop_seconds` sidecars; `phrase_start_before`; audible RMS via an `AudioEffectCapture` on the Music bus (passes trivially when the dummy driver mixes nothing); context choice (title → HOME; day moored/cabin → HOME; day on deck underway → SAILING; night → NIGHT on deck and below), settle delay, crossfade (both below full, then one, other paused), phrase-aligned resume, no flicker around dusk, no restart for pause menu/chart/settings, `Simulation.passage_rate = 43200` causes no switching, mute pauses player while SFX independent.
- **Depends on:** `MusicDirector` (`_process`, `_current`, `settle_seconds`, `min_stay_seconds`, `crossfade_seconds`, `get_player`, `audible_count`, `get_change_count`), `AudioManager.BUS_MUSIC`/`BUS_SFX`, `AudioServer`, `SettingsManager`, `GameSession`, `Simulation`, app scene.
- **State:** Shortens director timings (restored to `SETTLE`, `MIN_STAY`, `CROSSFADE`); `_set_local_hour` rewrites `game_time` by longitude.
- **Lifecycle:** test suite in `tests/test_runner.gd`; drives the director clock manually with `_tick`.
- **Tests:** —
- **Change risks:** Real-time timers (0.25–1 s) around crossfades; touches private director members; audio-driver dependent.

### `tests/suites/test_sprite_workshop.gd`

- **Role:** extends RefCounted; test suite (0.105b Sprite Workshop Phase 1): manifests (≥ 10 manifests, ≥ 100 entries, no warnings, README files, READY/ADAPTER_REQUIRED/REFERENCE_ONLY present, no installed PNGs); resolver (unknown/missing → fallback, non-READY never resolved, `validate_size` rule, cached: one load for 51 requests); every READY entry reaches its consumer via `_consumer_shows` (boat slots, shared solar panel, pets, fish, hat, anchor equipment); three in-game examples, each original → valid replacement (size/pivot) → removed → wrong shape / unreadable refused with warning: anchor buoy (`AnchorSignals`), Snøvs resting (`ShipCompanion`, state/spot unchanged), Arctic Wanderer 26 coachroof layer (covers `visual.canvas`, walkable cells unchanged).
- **Depends on:** `ArtworkResolver`, `res://tests/helpers/art_fixtures.gd` (`TestArtFixtures`), `res://tests/helpers/walkability.gd` (`TestWalkability`), `CompanionVisualSet`, `CompanionState`, `ShipCompanion`, `AnchorSignals`, `VesselVisual`, `VesselCatalog`, `SolarPanels`, `FishArt`, `HatArt`, `BoatArea`, `GameSession`, app scene; loads `res://src/vessels/<id>/<id>_visual.tscn`.
- **State:** Installs and removes fixture PNGs under the art replacements root; resets `ArtworkResolver` and `CompanionVisualSet` caches at the end.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** A crash mid-suite can leave fixture PNGs installed (final check catches it next run); depends on entry ids and slot names (`Coachroof`, `DeckBase`); screenshots `rb_16_*`–`rb_21_*`.

### `tests/suites/test_steady_hands.gd`

- **Role:** extends RefCounted; Steady Hands suite. Sets `get_tree().root.size` (the runner's 64 px window otherwise "expands" to a 1920×1920 canvas; restored at the end). `_test_weather_does_not_move_trip_details` (4 texts × 3 rounds, en/da, 10:00/23:00, `SailingPanel.collapsed`), `_test_long_texts` (les_sables→boulogne, 130 %), `_test_transitions` (sail trim then moored, wheel + warning, settings + language switch, load with pause menu open), then `SWEEPS` (1280×720 en/da 100/130 %, 1024×768 da, 2560×1080 da) → `_sweep` (openers list; `check_window`: interface controls only (`get_canvas_layer_node()`), skip contents of ScrollContainer/ItemList/RichTextLabel and `Dim`; on screen ± `EPS`; Esc via `modals.handle_back` (`NO_ESC`: LanguagePicker); raw `%s`/`%d`/`{…}`; Danish: non-auto-translated text with a translation, and `english_phrase` for composed text), `_check_hud` (`HUD_PAIRS`, Danish English-phrase check, screenshots), `_check_screens` (main menu, new game, language, load, chart, dream map), `_check_no_hidden_click_catchers` (STOP controls > 20 % of the screen). `_test_dusk_readability` (144 × 600 s moored from 00:00 UTC: `_target_blend()` ∈ {0, 1}, exactly 2 switches; `_contrast` of ink/surface, ink/surface_hud, ink/sidebar, button_text/button, action_text/action at blends 0…1 ≥ 2.5:1).
- **Depends on:** `app.tscn`, `VhfRadio.call_for_slot`, `SaveManager`, runner helpers.
- **Lifecycle:** in `test_runner.gd` `SUITES` after `test_cabin_windows`.
- **Change risks:** `english_phrase` uses the Danish catalogue's two-word-plus messages; a deliberate English proper name of that shape would need an exemption.

### `tests/suites/test_turbocharge.gd`

- **Role:** extends RefCounted; test suite (performance pass): `WeatherModel.sample_hazard()` equals `sample()` exactly (8 places × 3 dates × 3 seeds × 40 × 2 `known_at`); `Simulation.route_hazards()` equals an inline copy of the pre-Turbocharge implementation on 5 routes × seeds × dates × start fractions and is faster in total; `WeatherDamage.damage_between()` equals per-`SUBSTEP` summation of `rate_per_hour`; two identical 3-night `Simulation.sleep` runs Copenhagen→Reykjavik end identically.
- **Depends on:** `WeatherModel`, `WeatherSample`, `Simulation` (`route_hazards`, `FORECAST_STEP_NM`, `MIN_ESTIMATE_SPEED_KN`, `DISPLAY_HORIZON_HOURS`), `WeatherDamage`, `SeaRouter`, `PortCatalog`, `GameSession`, `GeoMath`, `WindField`, `VesselProfile` (via `get_vessel_profile`).
- **State:** Disables the calm-wind override to use real weather (restored with `t.use_calm_wind()`).
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** The reference implementation must be updated deliberately if route-hazard semantics change; the speed check is a loose wall-clock comparison.

### `tests/suites/test_upkeep.gd`

- **Role:** extends RefCounted; test suite (Iteration 005b, logic only; UI in `test_upkeep_ui.gd`): start state (€10,000, 14/14 days, all boats 100 %, "100 % · Sound"), provisions use (1 day/day, not while paused, sleeping uses them, same at 1×/20×/one step), `provisions_warning` levels LOW/CRITICAL/EMPTY once each, no departure when empty, `buy_provisions` (€10 per missing day), `WeatherDamage.rate_per_hour` bands and resilience scaling, weather damage (ordinary passage ≥ 90 %, caution small, gale grows with time, squall gusts, none moored), identical outcome across 1×/5×/20×/large/sleep/save, per-boat condition and repair via `service_quote(BoatCare.SERVICE_REPAIR)`, resilience order Halcyon < Starling < Petrel, rescue (to Copenhagen, €1,000 fee, cabin `RESCUE_SPAWN`, once, also during sleep/20×/long advance, arrival xor rescue), money floor €0, persistence of condition/funds/stores/`damage_applied_until`, v6 save migration.
- **Depends on:** `GameSession`, `Simulation`, `WeatherDamage`, `WeatherFixtures` (`gale`, `thunderstorm`), `WeatherModel`, `Provisions`, `VesselCondition`, `VesselCatalog`, `BoatCare`, `CompanionState`, `SaveManager`, `SessionState`, `PortCatalog`, `WindField`.
- **Signals:** connects to `GameSession.rescued` and `GameSession.provisions_warning`; temporarily `Simulation.arrived`.
- **Persistence:** Exercises `economy`, `provisions`, `rescue`, `vessel.conditions`, `vessel.damage_applied_until` and v6 migration (hand-written slot 3).
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Many hard-coded damage bands and money amounts; the ordinary-weather passage uses the real wind field (seed-dependent); test setters (`set_provisions_for_testing`, `set_condition_for_testing`).

### `tests/suites/test_upkeep_ui.gd`

- **Role:** extends RefCounted; test suite (Iteration 005b UI): HUD `StatusLabel` (hull, funds, food, water) not overlapping clock/route panels; cabin `provisions` station → `ProvisionsMenu` (pauses tree, values after `app.sleep_for(12)`, `GroceryButton` → `GroceryMenu`, €10 per missing day); `ProvisionDisplay` levels/filled crates via `DevTools.set_provisions`; provisions station and display on Starling/Halcyon/Petrel cabins, Halcyon "TO DECK" door label and "Go on deck" prompt; damage overlay mark counts by `DevTools.CONDITION_PRESETS` on deck and cabin, cleared by repair; `BoatyardMenu` fixed panel rect at UI scale 1.0/1.3, buttons inside, repair via `BoatCareMenu` + restock (€180); rescue via `DevTools.prepare_rescue` → `RescueDialog` (text, pause, no time), also during sleep; `DevTestPanel` on F10 (buttons, StormAhead needs a course, chart weather shapes, squall warning, sidebar size stable), test weather never saved and removed on load; production isolation (`DevTools.force_enabled = false`); companion never blocks stations at any cat spot (`InteractionSensor.choose`), prompts "Check provisions"/"Pet cat".
- **Depends on:** app scene, `GameSession`, `Simulation`, `DevTools`, `WeatherModel`, `WeatherFixtures`, `SettingsManager`, `Provisions`, `VesselCondition`, `BoatCare`, `CompanionState`, `ShipCompanion`, `Interactable`, `InteractionSensor`, `WorldMap`, menus (`ProvisionsMenu`, `GroceryMenu`, `BoatyardMenu`, `BoatCareMenu`, `RescueDialog`, `DevTestPanel`, `PauseMenu`), `res://tests/helpers/walkability.gd`.
- **Signals:** temporarily connects to `Simulation.weather_warning`.
- **State:** Resets `DevTools.force_enabled = null`, `restore_normal_weather()`, UI scale 1.0 at the end.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Many exact UI strings and node names; `_use_station` relies on walkability search (≤ 40 tries); private `WorldMap._refresh`; screenshots `80`–`101`.

### `tests/suites/test_vessels.gd`

- **Role:** extends RefCounted; test suite (Iteration 004, updated 0.100b): `VesselCatalog` (4 boats, starter `arctic_wanderer_26`, official display names, 3 hull types, `validate()`), deck/cabin scenes (visual slots except sail slots, no collision in `Visual`, stations, spawns, sail markers, companion spots, player/camera), performance profiles ordering and `BoatyardMenu.compare_rows`, `VesselVisualProfile` texture source fallback (profile → file → procedural, `procedural_only`, conventional paths), sprite scaling in `VesselVisual.apply`; reachability of every spawn and station on all boats (own flood fill, finer `TestWalkability` grid fallback); boatyard browse/choose/refuse underway; life aboard each boat (companionway, companion spots and petting, nav table → chart, berth sleep 2 h, profile speeds, `SailRig` on markers, sail sprites keep shape, spinnaker on pole, engine loop); demo coachroof sprite leaves layout/collision unchanged; time controls on the trimaran; save/load per boat/area, vessel id in save, v4 save → `starling_33`, unknown id → starter with toast.
- **Depends on:** `VesselCatalog`, `VesselVisual`, `VesselVisualProfile`, `res://data/vessels/starling_33_visuals_demo.tres`, `BoatArea`, `BoatFixture`, `Interactable`, `SailRig`, `ShipCompanion`, `CompanionState`, `PropulsionState`, `BoatyardMenu`, `SleepMenu`, `WorldMap`, `AudioManager`, `SaveManager`, `SessionState`, `GameSession`, `Simulation`, `TestWalkability`, app scene.
- **Persistence:** Exercises `session.vessel.id`, v4 migration (no vessel id → Starling) and unknown-id fallback.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Long and slow (all boats × areas, flood fills); hard-coded display names and ids; station/spawn/marker node paths; screenshots `40_*`–`46_*`.

### `tests/suites/test_visual_prototype.gd`

- **Role:** extends RefCounted; test suite (Visual Identity V01 D): owner cat PNG MD5s unchanged; Starling/Halcyon/Petrel `illustrated_visual_profile` in `<id>/illustrated` with all deck/cabin slots sourced from "file", classic profiles unchanged; `HatArt` slot fallback/assignment/`procedural_only`; `HarbourArt.for_port` (Copenhagen → one "Nyhavn" landmark, `MAX_LANDMARKS`, image-less landmarks skipped); art style switch (`SettingsManager.ART_CLASSIC`/`ART_ILLUSTRATED`) keeps `Layout` (collision, stations, spawns, markers) identical on deck and cabin, hat hook, provisions display, damage overlay; harbour dressing (signs = `HarbourFacilities.for_port` ids, Patrick Hand name sign, z-order, no collision, grocery/boatyard usable, Classic restores old pontoon), generic harbour at Kiel, none at sea, Nyhavn after arrival; other boats illustrated/classic; Settings `ArtStyle` option applied and saved to config `display/art_style`. I021: the generic-harbour check expects Kiel's look (one landmark titled "Gabled harbour town"), still with its own sign and three facility signs.
- **Depends on:** app scene (`open_settings`), `t.board`, `VesselCatalog`, `VesselVisual`, `BoatArea` (`get_harbour_dressing`, `mooring`, `mooring_label`, `get_hat_hook`), `BoatFixture`, `HatArt`, `HarbourArt`, `HarbourLandmark`, `HarbourFacilities`, `HighlightProvider`, `GroceryMenu`, `BoatyardMenu`, `SettingsMenu`, `SettingsManager`, `TestWalkability`, `GameSession`, `Simulation`, `PortCatalog`.
- **State:** Writes the art style to the test settings file; leaves it Illustrated.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Hard-coded MD5s of `res://Visuals/Cat/*.png`; exact sign texts ("Groceries", "GROCERY STORE"); harbour node names (`Plank0`, `Pontoon`, `GrocerySign`); screenshots `140_*`–`150_*`.

### `tests/suites/test_voyage_persistence.gd`

- **Role:** extends RefCounted; test suite: underway save/load round trip with a "test_strong_winds" gale fixture (clock, time scale 20, position, progress, route path, destination, area, player position, `is_weather_warned("test_strong_winds>1")`, exposure; no repeated warning; arrives in Kiel); Iteration 001 (v1) save migration (start time, 1×, moored at Copenhagen, player kept, straight course re-planned as a valid sea route, settings file untouched); invalid voyage saves (progress beyond route, position off route, underway with port location, wrong destination, unsupported time scale) are CORRUPTED and leave the active session unchanged.
- **Depends on:** `SaveManager`, `SessionState`, `GameSession`, `Simulation`, `WeatherFixtures`, `SettingsManager`, `SeaRouter`, `PortCatalog`.
- **Signals:** temporarily connects to `Simulation.weather_warning`.
- **Persistence:** Exercises save validation rules and v1 migration.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Hand-written v1 JSON and save-field paths (`session.navigation.voyage...`) must follow format changes; slot metadata string "At sea".

### `tests/suites/test_weather.gd`

- **Role:** extends RefCounted; test suite (Iteration 005a, unified weather model): sampling determinism (same input, fresh `WeatherModel.load_from`, seed-dependent), background = `WindField` outside events, gusts ≥ sustained; generated gale areas (count, lifecycle stages, coherent motion, irregular evolving outline at normalized distance 1, European zones stay in Europe, ocean zones exist); thunderstorm risk areas and cells (summer-heavy, inside parent, mostly mild, 2–5 h); cyclone risk by basin/season (none in Europe) and generated cyclones; fixtures: gale conventions (FROM 270°, caution, `GALE_GUST_FACTOR`, monotonic falloff), thunderstorm stages/gust envelope, cyclone rotation by hemisphere and eye wall; all vessels sail Copenhagen→Kiel through a gale (propulsion wind = weather wind, ≤ 6 mode changes); warnings dedup and escalation keys (`fx_level>1`, `>2`); time-step consistency (1×, 20×, large, sleep, save); pause freezes weather; save `weather` section (model_version 1, exposure, no outline) and v5 migration.
- **Depends on:** `WeatherModel`, `WeatherEvent`, `WeatherSample`, `WeatherFixtures` (`gale`, `thunderstorm`, `cyclone`), `WindField`, `Simulation`, `GameSession`, `SaveManager`, `SessionState`, `VesselCatalog`, `CompanionState`, `PortCatalog`, `GeoMath`; data `weather_events.json` (indirect).
- **Signals:** temporarily connects to `Simulation.weather_warning` and `GameSession.propulsion_changed`.
- **Persistence:** `weather.model_version`, `weather.exposure`; v5 → current drops `voyage.warned_conditions`.
- **Performance:** Year-long event scans (`_year_events`, 3 years for cyclones) make it one of the slower logic suites.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Statistical thresholds on generated weather (seed 1) break when `weather_events.json` or generation changes; `EUROPEAN_GALE_ZONES = 6` assumes zone order in the data.

### `tests/suites/test_weather_ui.gd`

- **Role:** extends RefCounted; test suite (I005a UI): chart overlay with three fixtures (`ui_gale` on the course, `ui_risk` thunder risk, `ui_storm` cell): `MapView.weather_time` snapped to `WEATHER_REFRESH_SECONDS`, legacy `WeatherCatalog`/`WeatherCondition`/demo data absent, `get_weather_shapes()` = active events with their real `WeatherEvent.outline`, irregular gale, labels ("GALE", "THUNDERSTORM"/"SEVERE SQUALLS"), core only for gale, stable under pan/zoom and pause, moves after 1 h; Weather tab title "Weather (N)", `WeatherLabel` text, `WeatherLegend` four kinds, `WeatherStyle` distinct (thunder risk dashed); HUD `WindLabel` shows gale + gusts; `app.update_weather_audio`/`is_storm_audio_playing` (on in gale, off when calm and in main menu); sleep woken by a thunderstorm forming 20 nm ahead (toasts, HUD warning, position on route, pause kept, no second wake).
- **Depends on:** app scene (`open_chart`, `close_chart`, `sleep_for`, `hud`, `toasts`, `show_main_menu`), `WorldMap` (private `_refresh`), `MapView`, `WeatherLegend`, `WeatherStyle`, `WeatherEvent`, `WeatherModel`, `WeatherFixtures` (`gale`, `thunder_risk`, `thunderstorm`), `GameSession`, `Simulation`, `GeoMath`, `PortCatalog`, `ProjectSettings` class list.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Exact label/tab strings; toggles `Simulation.auto_advance` for 30 frames while paused; screenshots `70_*`–`72_*`.

### `tests/suites/test_well_run_ship.gd`

- **Role:** extends RefCounted; test suite (Injection 2): `TimePassage.date_text`/`weekday_phrase`/`clock_text`; `DayNightWatch.twilight_end` (Copenhagen May dawn ≤ `MAX_SKIP_SECONDS`, no card at Tromsø midsummer); `UiTheme.set_blend` emits exactly one `theme.changed` per step and < 500 ms with the chart open; six rounds of deck/cabin/chart/sleep/day-night keep node count, root autoload signal connections, audio players and orphans equal (tweens ≤ +2); sleep passage (clock 21:00→05:00, date/weekday turn at midnight, 3–9 s real time, stores used, toast "You slept 8 h", Space skips, no double sleep); dawn/dusk card once per twilight under normal simulation, none after a time jump or over a menu, evening card then night theme; Long Passage `VoyageMap` (boat on drawn route, `Simulation._interrupt_passage` → stop text + `SailOn`, load closes map, `TakeHelm`), through the Kiel Canal (`SeaRouter.canal_at`) to Cuxhaven with `BackAboard`, Nouméa→Papeete Date Line unwrap with no jumps, planned anchorage stop without Sail on.
- **Depends on:** app scene (`time_passage`, `voyage_map`, `day_night_watch`, `snap_light`, `_hud_layer`, `sleep_for`), `TimePassage` (`enabled`, `headless_ok`), `DayNightWatch`, `Daylight`, `UiTheme`, `VoyageMap`, `Simulation` (`start_passage`, `stop_passage`, `PASSAGE_RATES`, `_interrupt_passage`), `GameSession`, `SessionState`, `AnchorState`, `SeaRouter`, `WorldMap`, `PortCatalog`, `Performance` monitors.
- **State:** Enables `TimePassage.enabled`/`headless_ok` during the suite (reset after).
- **Performance:** This suite is itself the regression guard for theme recolouring cost and scene-change leaks.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Real-time pacing checks (sleep 3–9 s, skip < 2.5 s) and wall-clock theme limit; global structure counts are sensitive to any new autoload connection or lingering node; private app/Simulation members; screenshots `wrs_*`.

### `tests/suites/test_wind.gd`

- **Role:** extends RefCounted; test suite: `WindField` conventions (`from_to_to`, `Sample.to_vector`, `relative_angle` sign/wrap, `compass_name`), `PropulsionState.wind_side`/`point_of_sail_name`; determinism (same input, fresh `WindField.load_from`, seed-dependent), range 0–45 kn and finite outside the region, spatial (0.1°) and temporal (5 min) continuity, climatology over 30 days (Atlantic westerlies, Portugal northerlies, Aegean Meltemi, Gulf of Lion Mistral, Baltic calm fraction and lighter than Atlantic), query cost < 100 µs; `VesselProfile.get_default()` polar (no speed < 35° TWA or in calm, top ≈ 10 kn, symmetric tacks, monotonic in TWS, spinnaker angles 115–180°, bonus ≤ 15 % only above the spinnaker angle).
- **Depends on:** `WindField`, `PropulsionState`, `VesselProfile`, `SessionState`; data `res://data/weather/wind_climate.json` (indirect, via `WindField.DEFAULT_PATH`).
- **State:** Clears `WindField.test_override` to sample the real wind (does not restore the calm fixture itself).
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Climatology sectors and polar numbers are tuned to current data and the default profile; wall-clock query limit.

### `tests/suites/test_wind_overlay.gd`

- **Role:** extends RefCounted; test suite (Iteration 17 WND, updated Iteration 18): `WeatherModel.sample_wind` equals `sample()` (speed/direction, with and without `known_at`) across gales, thunderstorms and cyclones; `WindLayer` snapshot cache (regional snapshot completes, arrows only on SEA lattice points vs `NavGrid.LAND`, stationary chart samples no chunks, small pan reuses, `_fill` within `FRAME_BUDGET_USEC` + 15 ms, old snapshot shown until next complete, cached snapshots reused); zoom detail (`detail_hidden` + `WindZoomNotice` at world zoom, hysteresis between `HIDE_PX_PER_DEG`/`SHOW_PX_PER_DEG`, lattice points ≤ `MAX_VIEW_POINTS` × 1.2); time navigator (`WindNext`/`WindPrevious`/`WindNow`, 1 h steps to ±`MAX_OFFSET_STEPS` = 6, labels NOW / FORECAST / PAST MODEL SNAPSHOT, forecast note, game state unchanged, forecast uses `known_at` = now, all 13 times cached); fast clock limited by `NOW_MIN_REAL_SECONDS` (`snapshot_changed`); closing the chart stops the layer.
- **Depends on:** `WeatherModel`, `WeatherEvent`, `WindField`, `WindLayer` (many private members: `_lattice`, `_land`, `_point_at`, `_fill`, `_shown`, `_target`, `_snapshots`), `MapView`, `WorldMap`, `SeaRouter`, `NavGrid`, `GeoMath`, `GameSession`, `Simulation`, app scene.
- **Signals:** temporarily connects to `WindLayer.snapshot_changed`.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Heavy reliance on private `WindLayer` internals and exact label/button texts ("1 h ▶", "Estimated conditions. Actual wind may differ."); frame-budget timing; screenshots `17_wind_*`, `34_*`.

### `tests/suites/test_wider_world.gd`

- **Role:** extends RefCounted; test suite for I021. Covers the 16 new harbours (catalogue count 239, description, GeoNames source, grocery, tiers, Danish name/description), the look table (every port has a look with an existing texture; NZ = Norway, Willemstad = Copenhagen, Hobart = Aberdeen; six European harbours with six looks; Essaouira/Zanzibar share stone town, Dakar does not; shared cached art; Danish look title), specials (== ports with own landmarks, 6; ordinary stay ordinary; notes and `WorldMap._special_line` in both languages), missing-art fallback (a broken `HarbourLooks` instance returns null, own art still shown), the 10 new fish (catalogue, `FishArt.has_art`, regions exist on the chart, candidates at Lunenburg/Zanzibar/Langkawi/Valletta/Ísafjörður/Dakar/St Helena/Stornoway, none off Kiel, prices, Danish names, a record round-trips), the three decor items (prices, Danish), old saves and a save in Zanzibar, then in the app: the moored deck's landmark title at Valletta/Dingle/Zanzibar/Copenhagen/Suva/Nuku'alofa (node count stable over repeated moorings), the arrival card (ArrivalCard with Picture, text, mouse ignored, Danish), and a route across the date line (Suva to Nuku'alofa).
- **Depends on:** `src/app/app.tscn`, `HarbourLooks`, `HarbourArt`, `HarbourDressing`, `WorldMap`, `PortCatalog`, `FishingCatalog`, `FishingState`, `FishArt`, `HarbourTrades`, `SessionState`, `SaveManager`, `SeaRouter`, `SettingsManager`, `Loc`.
- **State:** replaces the session state to moor in harbours; switches the language to `da` and back.
- **Lifecycle:** test suite run by `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** catalogue count (239), specific look assignments and landmark titles, Danish strings ("Kapstaden", "Nordisk træhavn", "Helleflynder").

### `tests/suites/test_world_chart_render.gd`

- **Role:** extends RefCounted; test suite (Iteration 17 MAP): 53 × 15° camera pans (2.2 turns) both ways at world zoom and regional zoom (14 px/deg at −25° and −15°), checking `MapView.is_world_land_drawn_at` for every on-screen copy (k = −1..1) of 8 inland reference points (> 40 checks, camera stays within one world); `geo_to_screen`/`screen_to_geo` round trip across the Date Line < 0.01°; after 72 pans `pick_port` finds Papeete and `select_port(&"auckland")` works.
- **Depends on:** app scene (`open_chart`), `WorldMap`, `MapView` (camera, `projection`, private `_free_view_size`, `_clamp_camera`), `GeoMath.wrap_delta`.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Depends on private `MapView` members and the three-copy world layer approach; screenshot `17_map_australia_regional`.

### `tests/suites/test_world_voyage.gd`

- **Role:** extends RefCounted; test suite (Iteration 16 "Copenhagen to Paradise"): Arctic Wanderer 26 sails 7 legs Copenhagen → Las Palmas → Castries → Colón → Panama City → Puerto Ayora → Taiohae → Papeete on real weather (`wind_seed = 16`) in Long Passage (`Simulation.start_passage(43200)`, ticks of 0.1 s); per leg: `buy_provisions(get_passage_store_days())`, spoon lure, `PassageReadiness.assess`/`describe` (honest beyond `FORECAST_HOURS`, never a gate), arrival and stores > 0; daily fishing (`set_line`, `finish_fight`) and cooking (`cook("pan_fried_fish")`, `spend_time_aboard`); mid-Atlantic save/reload on leg 2 (slot 3); ashore at Las Palmas and Papeete (`get_shore_access`, `get_shore_event`, `apply_shore_choice`, `spend_time_ashore`); regions denmark/europe/world visited, no Date Line jumps, no rescue.
- **Depends on:** app scene, `GameSession`, `Simulation` (`passage_interrupted`), `PassageReadiness`, `Provisions`, `SeaRouter.get_loaded`, `SaveManager`, `WeatherModel.clear_cache`, `WindField`, `PortCatalog`, `GeoMath`, `BoatArea`.
- **Signals:** connects to `Simulation.passage_interrupted` (counts reasons, printed).
- **Performance:** Longest suite: up to 200,000 ticks per leg; whole-ocean simulation on real weather.
- **Lifecycle:** test suite in `tests/test_runner.gd`.
- **Tests:** —
- **Change risks:** Outcome depends on the seeded real weather, routing, boat speeds, provisions and fishing rules all together; any change there can make a leg fail (e.g. stores or a rescue); screenshots `16_paradise_*`.

## Test runner, probes and tools

### `tests/benchmark.gd`

- **Role:** extends Node (root of `tests/benchmark.tscn`); Iteration 16 performance probe: navigation load, cold routes (Europe + world), app startup, chart open/ready/reopen, chart frame times at three zooms + pan, deck frames, 10-day simulated session with chart cycles and memory, save/parse/apply timings.
- **Depends on:** `app.tscn` (preload), `SeaRouter.load_from(NavGrid.DEFAULT_MASK, NavGrid.DEFAULT_META, SeaRouter.DEFAULT_GRAPH)`, `SeaRouter.load_world` (only if `WORLD_GRAPH` exists, looked up at run time), `PortCatalog`, `GameSession`, `Simulation`, `SaveManager`, `WorldMap`/`MapView` (calls private `_clamp_camera`, `_overlay`), `GameVersion.DISPLAY`.
- **State:** sets `SaveManager.save_dir = "user://test_saves"`, `Simulation.auto_advance = false`; saves/loads/deletes slot 3; ends with `GameSession.end_session()`.
- **Lifecycle:** tool scene, run by hand: `godot --headless --path . res://tests/benchmark.tscn -- --out=/tmp/bench.json` (rendered without `--headless`). Prints `BENCH {json}`; `--out=` writes pretty JSON; exits 0.
- **Tests:** — (not in `test_runner.gd`).
- **Change risks:** "routes_cold" reuse one router (`var fresh := router`), so only the first route is truly cold; result keys must stay stable to compare with earlier runs; touches private MapView members.

### `tests/benchmark_105b.gd`

- **Role:** extends Node; Revision 0.105b frame-time benchmark (copy of `benchmark_18.gd` plus the chart anchorage overlay and provenance fields `commit`, `commit_source`, `label`, `measured_at`).
- **Depends on:** `app.tscn`, `GameSession`, `Simulation`, `WindField` (fixed 200°/8 kn override, cleared for the wind navigator), `SessionState`, `BoatArea`, `WorldMap`/`MapView` (`wind_layer`, `anchorage_layer`), `fishing_catalog.gd` (loaded at run time), `GameVersion.get_commit()`.
- **State:** test save dir; boards `starling_33` via `replace_state`; sets game time to local midnight from base `1777593600`; writes `GameSession._pending_bite` via `set()`; vsync off, `Engine.max_fps = 0`.
- **Lifecycle:** rendered tool scene: `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/benchmark_105b.tscn -- --out=/tmp/b.json --label=after [--commit=<id>]`. Prints `BENCH105B {json}`.
- **Performance:** each `_measure` = 30 warm-up + 240 timed frames (mean/p95/worst); wind navigator swept twice over `±MAX_OFFSET_STEPS`; anchorage fill waits up to 6000 frames.
- **Tests:** —.
- **Change risks:** uses `has_method` guards so older builds run it; renames of `wind_layer`/`anchorage_layer`/`is_complete`/`tiles_computed`/`max_frame_usec` silently drop sections or break; duplicated code with `benchmark_18.gd`.

### `tests/benchmark_17.gd`

- **Role:** extends Node; Iteration 17 benchmark of chart wind overlay and weather cost: chart first open/reopen x8 with memory, frame cost per view (`world`, `continental`, `denmark_region`, `coastal`) x wind on/off x stationary/pan/zoom, wind re-sample cost, 20x clock, sim ms per sailed day, Long Passage ms per game day, deck frames, save/load.
- **Depends on:** `app.tscn`, `WorldMap`, `MapView` (`projection`, `camera`, `_clamp_camera`, `wind_layer.force_snapshot` or `update_time` fallback), `WeatherModel.sample_count` (optional), `Simulation` (`start_passage`, `PASSAGE_RATES[2]`, `tick`), `GameSession`, `SaveManager`.
- **State:** test save dir; clears `WindField` override (real weather); slot 3 saved, loaded, deleted.
- **Lifecycle:** tool scene: `godot --headless --path . res://tests/benchmark_17.tscn -- --out=/tmp/b.json` (CPU) or without `--headless` (rendered). Prints `BENCH17 {json}`.
- **Performance:** 60 frames per measurement; 4 views x 2 x 3 modes.
- **Tests:** —.
- **Change risks:** relies on optional APIs via `"x" in obj`/`has_method`; result keys must stay stable for comparisons.

### `tests/benchmark_18.gd`

- **Role:** extends Node; Iteration 18 rendered frame-time benchmark: cabin night, deck night moored/underway/at anchor (companion on deck where available), fishing reel, wind time navigator sweeps, chart wind overlay.
- **Depends on:** same as `benchmark_105b.gd` minus anchorage overlay and commit provenance.
- **State:** test save dir; fixed wind 200°/8 kn until the navigator part; `GameSession._pending_bite` via `set()`.
- **Lifecycle:** `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/benchmark_18.tscn -- --out=/tmp/b18.json`. Prints `BENCH18 {json}`.
- **Performance:** 30 warm-up + 240 timed frames per scene.
- **Tests:** —.
- **Change risks:** keep in step with `benchmark_105b.gd` (same scenes so numbers compare).

### `tests/benchmark_wrs.gd`

- **Role:** extends Node; "The Well-Run Ship" probe: frame stats (mean/median/p95/p99/worst, stalls > `STALL_MS` 50 ms, process time, draw calls) plus a structure snapshot per scenario (nodes, objects, orphans, autoload signal connections, tweens, audio players, timers, theme/weather/router cache sizes, log lines). Scenarios: walking deck/cabin, day/night at 20x in harbour/chart/underway, chart open/close x12, sleeps across midnight/sunrise/sunset, Long Passage to Reykjavik, 20-round session. `--presented` runs only the TimePassage/voyage-map presentations; `--turbo` adds sleep-underway, debris, chart zoom/pan, dream map, fishing rod and 10 save/load rounds.
- **Depends on:** `app.tscn` (`sleep_for`, `open_chart`, `open_dream_map`, `open_fishing`, `_show_current_boat_area`, `time_passage`, `voyage_map`), `GameSession`, `Simulation`, `Daylight.sun_elevation`, `UiTheme` (`set_blend`, private `_target_blend`, `_tints`, `_dims`), `WeatherModel` private caches (`_slot_cache`, `_bucket_cache`, `_cell_cache`), `SeaRouter.get_loaded()._leg_cache`, `SessionLog._lines`, `SettingsManager.set_art_style`, `SaveManager`, `PortCatalog`.
- **State:** test save dir (turbo saves slot 1 and does not delete it); fixed wind 200°/8 kn; boards `starling_33`; drives `Input.action_press` for `move_*`.
- **Lifecycle:** `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/benchmark_wrs.tscn -- --out=/tmp/w.json --label=before [--presented] [--turbo --no-time-passage]` (`--no-time-passage` is read by `src/ui/time_passage.gd`). Prints `WRS {json}`.
- **Performance:** long run (thousands of frames); `_time_before_crossing` scans up to 2 days in 1-minute steps.
- **Tests:** —.
- **Change risks:** reads many private fields by name; `weather_cache` sums `.size()` of `get()` results with no null guard, so renaming those WeatherModel fields crashes the probe; scenario labels must stay stable for before/after.

### `tests/cabin_light_18.gd`

- **Role:** extends Node; Iteration 18 (LIGHT-1) lighting measurement: for `arctic_wanderer_26`, `starling_33`, `petrel_36`, `halcyon_40` at Copenhagen, local midnight, saves the cabin image (HUD hidden) and prints `CABIN <label> <id> pools … floor-corners … pool/corner … p10 … p90 … captain …`.
- **Depends on:** `app.tscn`, `GameSession`, `SessionState`, `BoatArea` (`walkable_bounds`, `Layout/Collision` fixtures named in `POOLS`, `Player`), `BoatLighting.update_now`.
- **State:** test save dir; fixed wind 200°/6 kn; writes `cabin_<label>_<id>.png` to `--out` (default `user://cabin_light`).
- **Lifecycle:** `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/cabin_light_18.tscn -- --out=DIR --label=before`.
- **Tests:** —.
- **Change risks:** fixture names in `POOLS` and node paths `Lighting`, `Layout/Collision` must match the cabin scenes; with no match the pool value silently reads 0; a cabin without a `Player` node prints captain -1.

### `tests/helpers/art_fixtures.gd`

- **Role:** class_name `TestArtFixtures`, extends RefCounted; static helpers for Sprite Workshop tests: `install(entry, size, scale)` writes a magenta/yellow check PNG (2 px transparent border) at `entry.path`; `is_fixture(texture)`; `install_garbage(entry)`; `remove(entry)` (PNG and `.import`); `installed_pngs(dir := ArtworkResolver.ROOT)`.
- **Depends on:** `ArtworkResolver.ROOT`; manifest entries (`path`, `source_width_2x`, `source_height_2x`).
- **State:** writes/removes files under the art replacements tree.
- **Lifecycle:** static helper, preloaded as `F` by callers.
- **Invariants:** fixtures must be removed after use; `installed_pngs()` is expected empty after tests.
- **Tests:** used by `tests/suites/test_sprite_workshop.gd`, `tests/restart_105b.gd`, `tests/screenshots_105b.gd`.
- **Change risks:** a test that fails mid-way can leave a PNG installed that the game then picks up; `is_fixture` colour thresholds tied to `TEST_COLOUR`.

### `tests/helpers/reel.gd`

- **Role:** extends RefCounted (no class_name); `static land(menu: FishingMenu, where := "perfect") -> bool` reels through the dial: `step_reel(ReelTiming.DEBOUNCE + 0.01)`, sets `reel.angle` to target (or arc edge), `press_reel()`, up to 50 steps; returns `get_last_result().landed`.
- **Depends on:** `FishingMenu` (`is_reeling`, `get_reel`, `step_reel`, `press_reel`, `get_last_result`), `ReelTiming.DEBOUNCE`, reel fields `arc_deg`, `target_deg`, `angle`.
- **Lifecycle:** static helper, preloaded as `Reel`.
- **Tests:** used by `tests/suites/test_fishing.gd`, `test_fishing2.gd`, `test_joy_journey.gd`, `test_catch_and_cove_journey.gd`, `tests/restart_18.gd`, `tests/screenshots_18.gd`.
- **Change risks:** changes to reel API/debounce break every fishing suite.

### `tests/helpers/walkability.gd`

- **Role:** class_name `TestWalkability`, extends RefCounted; flood fill of reachable player positions using a 20-unit circle against real physics (`walkable_cells`), plus `distance_to_station`, `use_points` (≤ `USE_DISTANCE` 40), `nearest`, `distance_to_fixture`.
- **Depends on:** `BoatArea` (`player`, `walkable_bounds`, world 2D space), `Interactable` (`CollisionShape2D` circle/rect), `BoatFixture.get_points`.
- **Lifecycle:** static helper.
- **Performance:** one physics shape query per grid cell, bounded by `walkable_bounds.grow(60)`; finer `grid` costs quadratically.
- **Invariants:** `PLAYER_RADIUS` (20) and `USE_DISTANCE` (40, player reach 46) must track the player's real collision and reach.
- **Tests:** used by `tests/suites/test_vessels.gd`, `test_visual_prototype.gd`, `test_solar_panels.gd`.
- **Change risks:** stale radius/reach values give false passes/failures for layouts.

### `tests/pacing_18.gd`

- **Role:** extends Node; Iteration 18 (PASS) probe counting Long Passage interruptions by reason on Copenhagen to Las Palmas (real wind, `PASSAGE_RATES[2]`, ≤ 12 game days) for: no line, line + `FishingState.PASSAGE_ALL`, line + `PASSAGE_KEEPERS` (keep rare). Prints `PACE {…}` per run.
- **Depends on:** `app.tscn`, `GameSession` (passage posture, keep preferences, `set_line`, `expire_bite`, `take_quiet_nibbles`), `Simulation` (`passage_interrupted` signal, `start_passage`, private `_passage_tick`), `WindField`, `FishingState`.
- **Signals:** connects `Simulation.passage_interrupted`.
- **Lifecycle:** `godot --headless --path . res://tests/pacing_18.tscn`.
- **Tests:** —.
- **Change risks:** line 26 had an empty `if line:` (a parse error) from I018 until the Engine Room pass; it now puts the line out (`set_line(true, "spinner")`) before departure, as the loop below already does after each stop. Local `var f` unused.

### `tests/restart_105b.gd`

- **Role:** extends Node; multi-process save/restore check for Revision 0.105b. A (slot 1): normal anchor off Antigua (engine stopped, depth `DepthService.SOURCE_ESTIMATE`), one hour at anchor reproduces. B (slot 2): Magic Anchor offshore at (-20, 28.5) after a two-Perfect `MagicAnchorDeployment`, 50 kn blow drag reproduces. C: Sprite Workshop replacement for `pet.snovs.resting` installed, imported, used by a new process, removed, original restored.
- **Depends on:** `app.tscn` (`load_slot`, `is_anchorage_prompt_due`, `_show_current_boat_area`), `GameSession`, `SaveManager`, `PlannedRoute`, `Voyage`, `PropulsionState`, `AnchorState`, `MagicAnchorDeployment`, `TimingCheck`, `ArtworkResolver`, `ShipCompanion`, `CompanionVisualSet`, `TestArtFixtures`.
- **State:** `user://test_restart105b_saves`, `user://test_restart105b_expect.json`, `user://test_restart105b_diagnostics`; wind override 200° at `wind_kn` (10, then 50).
- **Lifecycle:** separate processes: `godot --headless --path . res://tests/restart_105b.tscn -- --phase=write`, `--phase=read`, `--phase=art_install`, then `godot --headless --path . --import`, `--phase=art_read`, `--phase=art_after`. Exit 0 only if all checks pass; 2 for a bad phase. Prints `RESTART105B ok|FAIL …`.
- **Persistence:** verifies anchor dict (kind, depth, source, bonus), propulsion mode and game time round-trip.
- **Tests:** —.
- **Change risks:** phases must run in order; the expectation file from write is not deleted by read; determinism across processes required.

### `tests/restart_17.gd`

- **Role:** extends Node; Iteration 17 (SAVE-4) two-process check: three saves underway to Las Palmas (deck near bow, cabin, poor weather found by searching ≤ 400 half-hours) then +6 h; read phase loads each and checks area, player position (0.5 tolerance, valid), vessel position/time/progress/destination, weather string, and identical position/weather after +6 h.
- **Depends on:** `app.tscn` (`load_slot`, `_show_current_boat_area`), `BoatArea` (`_boat_view_bounds`, `is_valid_player_position`), `GameSession`, `Simulation.get_weather_at_vessel`, `WeatherModel.HAZARD_CAUTION`, `SaveManager`.
- **State:** `user://test_restart17_saves`, `user://test_restart17_expect.json`, `user://test_restart17_diagnostics`; real wind.
- **Lifecycle:** `godot --headless --path . res://tests/restart_17.tscn -- --phase=write`, then `-- --phase=read`. Prints `RESTART17 …`; exit 0 only on pass.
- **Invariants:** weather deterministic across processes for the same seed.
- **Tests:** —.
- **Change risks:** depends on real seasonal weather (poor-weather case may not be found, reported not failed); saves in slots 1–3 of its own folder are not deleted.

### `tests/restart_18.gd`

- **Role:** extends Node; Iteration 18 (SAVE) two-process check. A (slot 1): keep preferences uncommon/silver, cod kept, herring auto-released, sea trout kept then released; read compares hold/trophies/records/preferences/counts. B (slot 2): chart course to Gothenburg with an anchorage waypoint (suggested), sailed to, anchored, companion on deck; read checks anchor, `anchorages_done`, `holding_at == -1`, course, companion shown, no prompt, identical arrival. C (slot 3): manual sail trim 0.6, underway to Las Palmas +6 h; read checks trim, factor, speed, weather, stores and +6 h result.
- **Depends on:** `app.tscn` (`open_fishing`, `open_chart`, `_update_companion_follow`, `is_anchorage_prompt_due`, `load_slot`), `reel.gd`, `FishingCatalog`, `FishingMenu`, `WorldMap` (draft route, `insert_waypoint`, `toggle_anchorage`, `use_anchorage_suggestion`, `apply_course`), `SeaRouter`, `AnchorSite.MAX_LAND_NM`, `GeoMath`, `CompanionState`, `GameSession`, `Simulation`, `SaveManager`.
- **State:** `user://test_restart18_saves`, `user://test_restart18_expect.json`, `user://test_restart18_diagnostics`; wind override 200°/10 kn in both processes; writes `GameSession._pending_bite` directly.
- **Lifecycle:** `godot --headless --path . res://tests/restart_18.tscn -- --phase=write`, then `-- --phase=read`. Prints `RESTART18 …`; read deletes slots 1–3.
- **Tests:** —.
- **Change risks:** companion walk wait up to 2000 frames; JSON string comparison of dicts is key-order sensitive (`sort_keys` used).

### `tests/restart_check.gd`

- **Role:** extends Node; original two-process restart check. Write: settings (Ambience 33, Master 0, vsync off, UI scale 0.9, classic art), new game with dog, voyage to Gothenburg, hat lost twice via `apply_hat_check` (Captain No-Hat), bought and worn, travel update published, `switch_vessel(&"petrel_36")`, player position set, underway to Kiel 3 h, condition 64, time scale 5, slot 2 saved; expectations JSON. Read: verifies all of it plus weather snapshot/events, exposure, hat (serial 2, lost 1, spent 15), secret achievement, diagnostic log contents, funds/food/water, per-boat condition, `damage_applied_until`.
- **Depends on:** `SettingsManager`, `SaveManager`, `GameSession`, `Simulation`, `WeatherModel`, `SessionLog`, `HatState`, `CompanionState`, `SessionState`, `AudioServer`. No app scene.
- **State:** `user://test_restart_settings.cfg`, `user://test_restart_saves`, `user://test_restart_expect.json`, `user://test_restart_diagnostics`; read restores `SettingsManager.DEFAULT_PATH` and `SessionLog.DEFAULT_DIR` and deletes all scratch files.
- **Lifecycle:** `godot --headless --path . res://tests/restart_check.tscn -- --phase=write`, then `-- --phase=read` (exit 0 pass, 1 fail, 2 bad phase).
- **Persistence:** broadest save round-trip check (settings + `SessionState` fields).
- **Tests:** —.
- **Change risks:** any new save field affecting these values, or hat pricing/serial rules, changes expectations; real wind affects the voyage (values recorded in write).

### `tests/screenshots_105b.gd`

- **Role:** extends Node; Revision 0.105b rendered evidence with checks: `rb_22` normal anchor off Antigua, `rb_23` Magic Anchor on a deep non-offshore coast off Madeira, `rb_24` at anchor at night, `rb_25` buoy replacement removed (fallback), `rb_26` wrongly sized replacement with its warning shown on an overlay.
- **Depends on:** `app.tscn` (`open_anchor`, `hud.hide_warning`), `BoatArea` (`view_heading_override`, `_update_camera`, `ZOOM_TRANSITION_S`, `get_anchor_signals().uses_buoy_replacement()`), `GameSession`, `AnchorSite.evaluate`, `SeaRouter.is_point_reachable`, `DepthService`, `ArtworkResolver` (`get_entry`, `reload`, `get_warnings`), `TestArtFixtures`.
- **State:** test save dir; fixed wind 200°/9 kn; installs/removes `equipment.anchor.buoy` replacement.
- **Lifecycle:** `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshots_105b.tscn -- --out=DIR`. Prints `SHOTS105B …`; exit 0 when all hold.
- **Tests:** —.
- **Change risks:** a failure before `F.remove` can leave the buoy replacement installed; Madeira spot search is coastline/depth dependent.

### `tests/screenshots_16.gd`

- **Role:** extends Node; renders Iteration 16 review screenshots (01–20) of the world chart, routes (Europe to Atlantic, around Antilles, Date Line, via Mindelo), readiness, Long Passage UI and save, Papeete arrival and go ashore; combines `19a–c` into `19_zoom_world_to_regional.png`.
- **Depends on:** `app.tscn`, `WorldMap`, `MapView`, `Hud.passage_panel` (`Rate1`, `Save` buttons), `GameSession` (`set_provisions_for_testing`, `buy_provisions`), `Simulation`, `PortCatalog`, `Provisions.CAPACITY_DAYS`.
- **State:** test save dir and `user://test_diagnostics`; wind seed 16, funds 20000; writes into `res://docs/screenshots/iteration16` (repository files).
- **Lifecycle:** `godot --path . --resolution 1600x900 res://tests/screenshots_16.tscn` (rendered, e.g. Xvfb).
- **Tests:** —.
- **Change risks:** overwrites committed doc screenshots; moors by state replacement (fixtures), voyages are covered by `test_world_voyage.gd`.

### `tests/screenshots_17.gd`

- **Role:** extends Node; renders Iteration 17 review screenshots (01–30): cabin world map per boat, Dreamer's Map, chart/harbour facilities/wind time, cabin and deck at noon/dusk/night, fenders, cockpit chart plotter, action wheel, heading turn, captain under the sail, rain/lightning on deck and in cabin, harbours by country, docking. `--only=` filters by file-name substring.
- **Depends on:** `app.tscn` (`open_dream_map`, `open_action_wheel`, `toggle_captains_log`, `update_weather_audio`, `weather_audio.strike`), `Daylight`, `WeatherFixtures` (`src/dev/weather_fixtures.gd`), `ChartPlotter.shown`, `SailRig`, `CaptainsLogMenu.TAB_HARBOURS`, `BoatArea` (`octant_for`, `DOCKING_SECONDS`), `GameSession`, `Simulation`, `WindField`.
- **State:** test save dir and diagnostics dir; writes into `res://docs/screenshots/iteration17`.
- **Lifecycle:** `godot --path . --resolution 1600x900 res://tests/screenshots_17.tscn [-- --only=cabin]`.
- **Tests:** —.
- **Change risks:** timing-based waits (`_wait`) for transitions; overwrites committed screenshots.

### `tests/screenshots_18.gd`

- **Role:** extends Node; Iteration 18 fishing evidence: reel dial (common/rare, perfect, missed), results (kept with grade, auto-release, manual release, shark), cool box and keep preferences, trophies, fish art per species, posed blink/tail frames, a 48-frame animation strip, all-species sheet, anchorage waypoint icon and drag (valid and onto land).
- **Depends on:** `app.tscn` (`open_fishing`, `open_trophies`, `open_chart`), `reel.gd`, `FishingMenu` (`ReleaseCatch`, `BackToRod`, `KeepRarity` nodes), `FishingCatalog`, `FishPortrait`, `ReelTiming`, `WorldMap`, `MapView.waypoint_dragged` (emitted directly), `SeaRouter`, `AnchorSite`.
- **State:** test save dir; fixed wind 200°/8 kn; writes PNGs to `--out`.
- **Lifecycle:** `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshots_18.tscn -- --out=DIR`. Prints `SHOT …`.
- **Tests:** —.
- **Change risks:** finds UI by node name; `_shot` does not await `frame_post_draw` (unlike other screenshot scripts).

### `tests/screenshots_chartroom.gd`

- **Role:** extends Node; Captain's Chartroom UI evidence: main menu day/night, then per mood (local 12:30 / 23:30) deck, action wheel, cabin, trophies, boat care, grocery, boatyard, go ashore, Captain's Log, sleep, galley, warning + tooltip, chart course to Kiel, deck underway, sail trim, fishing reel/result, Dreamer's Map, pause, settings, dev guides, toast.
- **Depends on:** `app.tscn` (many `open_*` methods via `call`), `SettingsManager` (`set_ui_light`), `UiTheme` (`blend`, `set_blend`, `_target_blend`), `GameSession`, `Simulation`, `FishingCatalog`, `FishingMenu`, `ReelTiming`, `PortCatalog`.
- **State:** `user://test_saves`, `SettingsManager.settings_path = "user://test_settings.cfg"`; fixed wind 220°/11 kn; output default `res://docs/screenshots/chartroom_ui`, or `--out=`.
- **Lifecycle:** `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshots_chartroom.tscn -- --out=DIR [--only=day|night]`. Prints `CHARTROOM SHOTS DONE`.
- **Tests:** —.
- **Change risks:** method names passed as strings to `app.call`; 1.2 s timer for tooltip.

### `tests/screenshots_i021.gd`

- **Role:** extends Node; I021 evidence: the moored deck at a harbour of each look (Svolvær, Marstal, Dingle, Naples, Mykonos, Zanzibar, Dakar, Bora Bora, Horta) and each special harbour (Copenhagen, Valletta, Symi, Essaouira, Lunenburg, St Helena) at local 12:30; the arrival card (`App._on_arrived`) at Valletta and, in Danish, Zanzibar; the navigation chart by day and night (`open_chart_for_port(&"valletta")`, framed on Malta and on Symi with `select_port`) and the Dreamer's Map.
- **Depends on:** `app.tscn`, `HarbourLooks`, `PortCatalog`, `GameSession` (`replace_state`, `enter_boat_area`), `UiTheme`, `SettingsManager`, `WindField.test_override`, `MapView.frame_geo_points`, `WorldMap.select_port`.
- **State:** `user://test_saves`, `user://test_settings.cfg`; fixed wind 220°/8 kn; output `res://docs/screenshots/i021` or `--out=`.
- **Lifecycle:** `xvfb-run godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tests/screenshots_i021.tscn -- --out=DIR`. Prints `I021 SHOTS DONE`.
- **Tests:** —.
- **Change risks:** file names are referenced from the I021 report; harbour ids and framing rectangles are hard-coded.

### `tests/one_clock_sea_trial.gd`

- **Role:** extends Node (root of `one_clock_sea_trial.tscn`, `PROCESS_MODE_ALWAYS`); Operation One Clock diagnostic. Turns off `Simulation`, `UiTheme` and `app.day_night_watch` processing (and the current area's `Lighting` each frame) and calls `Simulation.tick(dt)`, `day_night_watch._process(dt)`, `UiTheme._process(dt)` and `Lighting._process(dt)` itself once per frame with the measured real delta, timing each; also records `viewport_get_measured_render_time_gpu/cpu`, evaluation points crossed (`EVALUATION_INTERVAL`), blend steps, `palette_changed` count, card/pause state, sun elevation, visible `PointLight2D` count, darkness, draw calls and render objects. Scenarios: `TRIAL` by default; `--all` adds 1x/5x/20x day/night, dawn/dusk with/without `TimePassage`, chart, isolation (`freeze_theme`/`freeze_lighting`), rapid speed changes, harbour dusk; `--only=a,b`, `--long_seconds=N`, `--out=FILE` (JSON, then quits).
- **Depends on:** `app.tscn` (`start_new_game`, `router`, `modals`, `toasts`, `_show_current_boat_area`, `open_chart`, `close_chart`, `snap_light`, `time_passage`, `day_night_watch`), `GameSession` (`replace_state`, `plan_route_to(&"bergen")`, `depart`, `set_time_scale`, `set_paused`), `SessionState.TIME_SCALES`, `TimePassage.enabled`, `DayNightWatch.DAY_ABOVE/NIGHT_BELOW`, `BoatLighting` private `_darkness`, `UiTheme.blend`, `PortCatalog`, `GameVersion.describe()`.
- **State:** scratch saves/settings (`user://test_saves`, `user://test_settings.cfg`); fixed wind 200°/11 kn; boards `starling_33`; writes `user://one_clock_sea_trial.txt` and sets the clipboard.
- **Lifecycle:** F6 in the editor (results stay on screen until the window is closed) or command line with `--out` (quits). About five minutes for `TRIAL`.
- **Tests:** none (diagnostic tool).
- **Change risks:** depends on private App/BoatLighting names; a renamed member stops the trial, not the game. Must not stay in a build's normal flow (it is a separate scene).

### `tests/test_runner.gd`

- **Role:** extends Node (root of `tests/test_runner.tscn`); self-contained test framework. Runs the 79 preloaded suites in `SUITES` (each `script.new()`, `await suite.run(self)`), counts checks, prints failures, exits 1 if any failed. I021: registers `test_wider_world.gd` after `test_companion_remarks.gd`. I022: `test_captains_other_life` in `SUITES`; sets `GameSession.test_all_boats_owned = true` with `TimePassage.enabled = false`. I022: `AcademyGuide.enabled = false` at start; `test_academy` in SUITES after `test_captains_other_life`. `test_cabin_windows` in SUITES after `test_academy`. `test_steady_hands` in SUITES after `test_cabin_windows`. Golden Harbours: `test_golden_harbours` in `SUITES` after `test_steady_hands`.
- **Depends on:** all `tests/suites/test_*.gd`; `SaveManager`, `SessionLog`, `SettingsManager`, `TimePassage`, `WindField`, `Simulation`, `GameSession`, `PortCatalog`, `SeaRouter`.
- **State:** redirects `SaveManager.save_dir = user://test_saves`, `SessionLog.log_dir = user://test_diagnostics`, `SettingsManager.settings_path = user://test_settings.cfg`; `TimePassage.enabled = false`; language forced to `en` before each suite; before each suite `use_calm_wind()` and `Simulation.sea_encounters` true only for `test_captains_watch.gd` and `test_localization.gd`; scratch saves/settings deleted at start and end; `_exit_tree` calls `WindField.clear_default()`.
- **Lifecycle:** `godot --headless --path . res://tests/test_runner.tscn [-- --only=a,b] [--skip=a,b] [--screenshots=DIR]` (filters match suite file-name substrings; screenshots only when rendered). `process_mode = ALWAYS`.
- **Invariants:** suite API used by suites: `check`, `check_eq`, `frames`, `physics_frames`, `wait_until`, `press_action`, `press_key`, `hold_actions`, `click`, `click_at`, `make_route`, `screenshot`, fixtures `use_calm_wind`, `set_wind` (calls `Simulation.invalidate_estimates()`), `board(vessel_id, app)`; fields `passed`, `failed`, `current_suite`, `screenshot_dir`.
- **Tests:** —.
- **Change risks:** a new suite file must be added to `SUITES` or it never runs; suite order matters (shared autoload state between suites); the doc comment for `hold_actions` sits above `press_key`; `_reset_scratch_files` removes only files and empty subfolders.

### `tools/art/capture_previews.gd`

- **Role:** extends Node (root of `capture_previews.tscn`); The Captain's Illustrated Catalogue. Renders previews of `_draw()` art through the game: `decor_<id>` (one `CabinDecor` per `HarbourTrades.get_decor()` item on a `FLOOR` ColorRect, scale 2/3, 6-column grid), `boat_<id>_{moored,cabin,underway}` (whole screen resized to 1280 x 720; moored at Copenhagen 12:30 local, then all decor bought and shown, then `plan_route_to(&"gothenburg")` + `depart()` + `Simulation.advance(1800)` under a fixed 220°/11 kn `WindField.test_override` so the boats sail), and `chart_<symbol>_<day|night>` crops at `MapView.geo_to_screen` positions (Syracuse→Valletta route with one waypoint; Dreamer's Map with `visited_pins`). `_crop` scales canvas units (1920 x 1080 canvas) to image pixels.
- **Depends on:** `src/app/app.tscn` (`start_new_game`, `router`, `modals`, `toasts`, `_show_current_boat_area`, `open_chart_for_port`, `open_dream_map`, `close_chart`), `GameSession` (`replace_state`, `buy_decor`, `set_cabin_decor`, `enter_boat_area`, `plan_route_to`, `depart`), `SessionState`, `PortCatalog`, `UiTheme._target_blend`, `WorldMap.get_map_view`, `MapView.frame_geo_points`/`visited_pins`; `SaveManager.save_dir`/`SettingsManager.settings_path` redirected to `user://test_*`.
- **Lifecycle:** tool scene, needs a display: `xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1600x900 res://tools/art/capture_previews.tscn -- --out=DIR` (default `res://docs/art/previews`); quits after "PREVIEWS DONE". Output is read by `tools/art/build_contact_sheets.py`.
- **Tests:** none (documentation tool); its output is checked by eye in `docs/art/ART_CONSISTENCY_REVIEW.md`.
- **Change risks:** follows App/MapView internals (private `_show_current_boat_area`, `_target_blend`); a renamed method stops the capture, not the game. Crops assume the chart framing in `_capture_chart`.

### `tools/build_theme.gd`

- **Role:** extends SceneTree; generates `res://assets/ui/next_harbor_theme.tres` (palette NAVY/TEAL/SEAFOAM/CREAM/BRASS, Barlow fonts, Patrick Hand display variations `DisplayTagline`/`DisplayHeader`/`DisplayName`, type variations `TitleLabel`, `HeaderLabel`, `MutedLabel`, `KeyLabel`, `BigButton`, `SlotButton`, `HudPanel`, `PromptPanel`, `ToastPanel`, `SidebarPanel`, `SectionPanel`, tabs, sliders, popups, scroll bars).
- **Depends on:** fonts in `res://assets/fonts/`; output is set as `gui/theme/custom` in `project.godot` (indirect consumer: every Control; `UiTheme` documents it).
- **Lifecycle:** tool: `godot --headless --path . -s res://tools/build_theme.gd` (after `godot --headless --path . --import` on a fresh checkout). Exit 0 on save OK.
- **Tests:** `tests/suites/test_branding.gd` loads the theme resource (indirect).
- **Change risks:** the `.tres` is generated: hand edits to it are overwritten on the next run; type-variation names are referenced by UI code.

### `tools/export_branding.gd`

- **Role:** extends SceneTree; rasterises `res://assets/branding/<name>.svg` to `res://assets/branding/png/<name>_<height>.png` for the heights in `EXPORTS` (logo, logo on light, symbol, icon) with Godot's SVG renderer. I022: `little_captains_hat_logo` also at 240 (the boot splash image); the existing PNGs re-export byte-identically.
- **Depends on:** the branding SVGs.
- **Lifecycle:** tool: `godot --headless --path . -s res://tools/export_branding.gd`; exit 1 on any missing/failed SVG.
- **Tests:** `tests/suites/test_branding.gd` checks `png/little_captains_hat_logo_480.png` exists (indirect); `src/ui/loading_screen.gd` preloads `little_captains_hat_logo_480.png` and `little_captains_hat_logo_on_light_480.png`.
- **Change risks:** removing a listed height breaks the loading screen preloads.

### `tools/navigation/world_land_to_res.gd`

- **Role:** extends SceneTree; converts `res://data/navigation/world/land.json` (from `build_world.py`) to compressed `res://data/navigation/world/land.res` (`WorldLand`: overview/regional fill and coast rings, islets, labels) projected with `MapProjection.new(160.0)`.
- **Depends on:** `MapProjection`, `WorldLand`; consumer `MapView.WORLD_LAND_RES` (falls back to JSON per `world_land.gd`).
- **Lifecycle:** tool, work done in `_init`: `godot --headless --path . --script tools/navigation/world_land_to_res.gd`; exit 1 on unreadable JSON or save error.
- **Invariants:** `SCALE` (160) must equal `MapView.units_per_degree` default (160.0).
- **Tests:** none found directly.
- **Change risks:** regenerate whenever `land.json` or the projection changes, else the chart draws stale land.

### `tools/vessels/render_art_templates.gd`

- **Role:** extends Node (root of `render_art_templates.tscn`); for each vessel in `VesselCatalog`, renders `deck|cabin_reference.png` (procedural art + landmarks) and `deck|cabin_guide.png` (landmarks only) at `SCALE` 2 px/unit over `VesselVisual.canvas`, into `<art_folder>/templates/` with a `.gdignore`. Inner class `Overlay` draws grid, collision, walkable fixtures, stations, spawns, companion spots, sail markers.
- **Depends on:** `VesselCatalog`, vessel `visual_profile.art_folder`, `deck_scene`, `cabin_scene`, `deck_visual_scene`, sibling `cabin_visual.tscn`, `VesselVisual.apply`, `BoatFixture`, `Interactable`, `CollisionPolygon2D`, `Marker2D` under `SpawnPoints`/`CompanionSpots`/`SailMarkers`.
- **Lifecycle:** tool scene, needs a display: `godot --path . --rendering-driver opengl3 res://tools/vessels/render_art_templates.tscn`.
- **Tests:** none found.
- **Change risks:** depends on scene node names (`Layout`, marker parents); see `docs/artwork/ART_PIPELINE.md`.

### `tools/weather/measure_wind_variation.gd`

- **Role:** extends SceneTree; Iteration 18 analysis of wind change over time-navigator steps: samples `WeatherModel.sample_wind(geo, time, 7, known)` on 5x5 grids in 5 areas x 40 start times, for offsets 0.5/1/2/3/6 h, in "actual" (`known = INF`) and "forecast" (`known = now`) modes; prints mean/p90 vector, speed and direction change and colour-band change rate.
- **Depends on:** `WeatherModel.get_default()`; `BAND_LIMITS` mirrors `WindLayer.BANDS` (comment; referenced from `src/navigation/wind_layer.gd`).
- **Lifecycle:** tool, work in `_init`: `godot --headless --path . -s res://tools/weather/measure_wind_variation.gd`. Print-only.
- **Performance:** 2 x 5 offsets x 5,000 pairs of samples.
- **Tests:** none found.
- **Change risks:** `BAND_LIMITS` can drift from the overlay's real bands.
