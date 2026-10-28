# I026 stage 03 - marine electronics: what moved where

The design is in [DESIGN.md](DESIGN.md) (*Stage 03*); the audit rows are D7-D9,
U3, U10 and W3 of [UI_INVENTORY.md](UI_INVENTORY.md). Screenshots:
`docs/screenshots/i026/instruments/` (made by `tests/screenshots_i026_instruments.tscn`).

## The packages

| Package | Look | HUD | Focused view | Price |
|---|---|---|---|---|
| Classic (SKERRY Classic) | Analogue dials in a satin housing, ivory markings, a red needle, a grey-green LCD repeater; red at night | Speed, heading and wind dials; the repeater with the route, ETA and next turn | The dials and the repeater with four pages (route, next turn, weather, sail trim) | Free, fitted to every boat |
| Modern Cruiser (SKERRY Cruise 4) | Three square black-glass displays, white figures, a pale blue accent; red at night | The three displays, each on its page | The displays with their page keys; each display chooses within its slot (speed / heading / trim, wind / weather, route / next turn) so the essentials stay on the HUD | EUR 680 |
| Offshore Navigator (SKERRY Navigator 12) | One wide multifunction display, aluminium rim, cyan accent; dimmed at night | The display on its layout (with a data bar of the essentials on every layout but the overview) | Layout keys: overview, sailing, navigation, weather | EUR 1,480 |

SKERRY is a fictional maker. All three draw from one reading
(`InstrumentData`) of the authoritative data; nothing is calculated twice.
Not simulated, so not shown: apparent wind (only the true wind and its angle)
and an echo sounder (the depth appears only at anchor: the anchor's own
depth, a game estimate). Prices: boat gear costs EUR 150-1,200 (at the
chandlery the weather receiver EUR 312-480 and the Magic Anchor EUR 450; at
the yard new rigging up to EUR 1,200), a new game starts with EUR 10,000 (EUR
7,000 for a Seasoned Captain) and remote work
pays EUR 25 an hour, so Modern Cruiser is a modest upgrade and Offshore
Navigator a considered one; neither is needed to sail safely.

Save: one optional section, `instruments` (`InstrumentState`):
`{"owned": [...], "fitted": {vessel id: package id}, "pages": {package id:
[page per display]}}`. Absent (older saves): Classic everywhere, nothing
owned. Unknown ids are dropped quietly. `SaveManager.SAVE_VERSION` stays 12.
A package once bought is the Captain's for every boat and is never lost.

## What moved where

| Before | Now |
|---|---|
| Sailing panel (right, underway; "Sailing details" on the wheel, its collapse button) | **Removed** (`sailing_panel.gd` deleted). Its readouts are the instruments on the HUD (`InstrumentCluster`) and, in words, the focused view's lines (next turn, next leg forecast, sails and engine, sail trim, outlook). The wheel item is now **Instruments** (the focused view); it is also offered in the cabin underway. |
| Route panel underway: destination, nm to go, ETA, progress, speed, wind, anchor holding and scope | On the instruments (the route, distance, ETA and next turn on every package; at anchor the holding, chain and depth; the instruction "Raise the anchor at the windlass" / "Drop the anchor, or sail on (Q)" as the cluster's status line). The route panel keeps only its **Menu** button underway; in port it is unchanged (planned route, estimate, wind). |
| Chartplotter HUD panel (P, wheel on/off) | The helm's plotter: drawn at the helm on every deck; **P**, the wheel's **Chart plotter** and E at the plotter (or a click on it) open the focused `PlotterView` with its range keys. Available aboard everywhere (deck or cabin, in port or at sea). Course planning stays at the chart table and the wheel's Charts. |
| Radar | Unchanged: the wheel's on/off item and the automatic pop-up on a caution or collision risk (a safety warning) stay in the HUD. |
| Weather | Forecast pages on the instruments (now and +3 / +6 / +12 h at the boat, an estimate; the outlook along the course). Warnings stay in the HUD. |
| Cockpit | Every deck draws the fitted package at the helm (`CockpitInstruments`): the plotter on the pedestal (Wing 33, Frogleap 36), on the bulkhead by the wheel (Clam 40) or beside the companionway (Arctic Wanderer 26), and three displays on the bulkhead to starboard of the companionway. Screens glow at night. |
| Chandlery | A new **Electronics** section: buy and fit, or fit an owned package again for nothing. The focused view's **Fitted** selector does the same anywhere. |
| Keys | **I** (new action `instruments`) opens the focused instrument view; **P** opens the plotter view; Esc closes both. |

## Notes for the lead

- The three GDScript guides were not edited (new: `instrument_package.gd`,
  `instrument_state.gd`, `instrument_data.gd`, `instrument_face.gd`,
  `instrument_cluster.gd`, `instrument_view.gd`, `plotter_view.gd`,
  `cockpit_instruments.gd`, `test_marine_electronics.gd`,
  `screenshots_i026_instruments.gd`; removed: `sailing_panel.gd`).
- Shared files touched in separate, marked blocks: `app.gd` (*Marine
  electronics*), `boat_area.gd` (two signals, one line in `_ready`, one
  match arm, a block at the end), `game_session.gd` (a signal, a block at the
  end), `session_state.gd` (the field and three lines), `hud.gd`,
  `chandlery_menu.gd` (one call in `_ready`, one in `refresh`, a block at the
  end), `project.godot` (the `instruments` action).
