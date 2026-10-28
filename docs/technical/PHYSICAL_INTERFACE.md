# The physical interface (I026, A World You Can Touch)

How the game's places and objects replace buttons and panels, and what stayed
conventional on purpose. Design: [docs/iterations/i026/DESIGN.md](../iterations/i026/DESIGN.md);
audit of every button and panel: [UI_INVENTORY.md](../iterations/i026/UI_INVENTORY.md);
electronics details: [STAGE_03_MARINE_ELECTRONICS.md](../iterations/i026/STAGE_03_MARINE_ELECTRONICS.md).

## 1. The interaction language

One language everywhere, aboard and ashore:

1. **A thing in the world** is an `Interactable` (an `Area2D` with a shape, an
   `interaction_id`, a `prompt`, a `focus_priority`). The Captain's
   `InteractionSensor` focuses the nearest one in reach (facing and priority
   break ties).
2. **Focus** shows the thing's own outline glowing (`set_highlight_outline_global`)
   and its prompt in the HUD ("Chandlery · open until 17:30", "Trim the sails").
3. **E** (or a click) uses it. The area (`BoatArea`, `HarbourFront`) only
   *routes*: it emits a signal and `App` opens the existing menu or action.
4. **The focused view** is the menu brought close, drawn as the object it
   belongs to (section 6). **Esc** always closes it; mouse and keyboard
   focus work exactly as before because the frame never takes input.

Quick actions stay (the action wheel Q, the keys T, P, I, L, F5), so nobody has
to walk to the cabin to trim the sails in a squall: the physical way is the
cozy, discoverable way, not the only one.

## 2. Old button to new place

| Before (I025) | Now (I026) |
|---|---|
| Pontoon stations: grocery, boatyard, Go Ashore (three signs on the pontoon) | One walkway sign on the pontoon, *To the quay*: up to `HarbourFront`, where every business has its own storefront and door |
| Chandlery and Sailmaker: buttons inside BoatyardMenu | The **chandlery** and the **sail loft**: their own buildings beside the yard |
| Fishmonger: a button inside GroceryMenu | The **fishmonger's stall** beside the grocery |
| Grocery button in BoatyardMenu | Removed (the grocery has its own door; the cabin's provisions locker still leads to it in harbour) |
| Go Ashore station on the pontoon | The **lane into town** at the quay's town end |
| Haul-out: BoatCareMenu only | Also the **travel lift** on the quay (major harbours), opening Boat care |
| (none) | The **harbour office** (hours of every business, the place, the forecast in words) with an after-hours **hatch**; the **noticeboard**; the **café** |
| Sailing panel (HUD, underway) | **Removed** (`sailing_panel.gd` deleted): the fitted instrument cluster on the HUD and the focused instrument view (I; wheel *Instruments*; E at the cockpit instruments) |
| Chartplotter HUD panel (P) | The helm's plotter on every deck; P / E opens the focused `PlotterView` |
| Sail trim: T and the wheel only | Also the **sheet winch** on the cockpit coaming (`WinchProp`) |
| Captain's Log: L, pause menu, wheel | Also the **logbook** at the nav station (the same Captain's Log, framed as a book) |
| VHF: only the pop-up when a call comes | Also the **VHF set** at the nav station: its lamp blinks while a call waits; answer it there; the weather broadcast in words |
| (none) | The **switch panel** (`SystemsView`): only what the game keeps (care survey, fitted gear, sails, food and water, instruments) |
| "Make it home": wheel only | Also the **sea chest** by the berth |
| Scrapbook: laptop only | Also the newest **postcard** on the saloon table (once one is made) |

Panels removed: the sailing panel, the HUD chartplotter panel, the wheel's
"Sailing details" item, the pontoon's grocery/boatyard/Go Ashore stations.
Functions not converted (they stay where they were): see section 10.

## 3. Shop assignments (shared backend, separate storefronts)

Each door opens the **existing** menu; prices, stock, services and the economy
are unchanged (`HarbourFacilities` and `HarbourTrades` decide where each
exists, exactly as before).

| Storefront | Opens | Where |
|---|---|---|
| Boatyard | `BoatyardMenu` (boats, Boat care) | Harbours with a yard |
| Travel lift | `BoatCareMenu` (haul-out) | Yards that haul out |
| Chandlery | `ChandleryMenu` (gear, Magic Anchor, cabin things, **Electronics**) | With the yard |
| Sail loft | `SailmakerMenu` | With the yard |
| Grocery | `GroceryMenu` | Harbours with a grocery |
| Fishmonger | `FishmongerMenu` | With the grocery |
| Café | `CafeMenu` (a coffee, EUR 4 x the difficulty's cost factor) | Every harbour |
| Harbour office | `HarbourOfficeMenu` | Every harbour |
| Noticeboard | `NoticeboardMenu` (`HarbourNotes`: local colour, no quests) | Every harbour |
| Lane into town | `GoAshoreMenu` | Harbours with Go Ashore |

`ShopCounter` draws each shop's interior behind its menu (presentation only).
`QuayLayout` places only what the harbour offers, in a fixed order from the
working end to the town end, deterministic per harbour id.

## 4. Opening hours

`BusinessHours` with `data/harbours/business_hours.json`:

- Per business type: an opening and a closing hour and the weekdays it rests
  (the yard, chandlery and sail loft rest on Sundays; the café opens at 07:00).
- Nudged by the harbour's region (`HarbourDressing.archetype_for`: a
  Mediterranean quay closes two hours later) and tier (small harbours keep
  shorter hours, major ones longer).
- Always on the harbour's **local solar time** from the one authoritative
  clock (`GameSession` game time via `Daylight.local_solar_hours`); nothing is
  saved.
- Shown physically: the hours plate and OPEN/CLOSED sign on every door, the
  door's prompt ("open until 17:30", "closed · opens Monday 07:00"), lit
  windows and a shopkeeper locking up at closing time; every business's hours
  in the harbour office.
- Never stranded: a closed door offers **Wait until it opens** (time passes
  ashore like any wait, interruptible as usual) or Not now; the harbour
  office's **hatch** is always staffed and sells food and water (where there is
  a grocery) and arranges an emergency hull repair (where there is a yard),
  at the usual prices.

## 5. Townsfolk routines

`HarbourLife` (and `TownsfolkDrawing`): a handful of people, 3 in a small
harbour, 6 in a larger one, 8 in a major one, fewer in bad weather and nearly
none at night.

- **Deterministic and reconstructed, never simulated while away.** The roster
  is a pure function of the harbour id, the local day and the hour
  (`roster_at`). It is checked every 2 real seconds while the quay is on
  screen; after sleep or a time skip the quay just shows who is about at the
  new hour.
- **Roles:**
  - walkers (shop windows, benches, the quay's edge)
  - shoppers (into an open shop and out again)
  - café customers (only while the café is open)
  - a fisherman with nets in the morning
  - the shopkeeper locking up at closing time
  - a late walker at night
- **Movement:** real time at a walking pace, along the promenade's walking
  line. They have no physics bodies, never stop in a doorway or at the
  walkway's head, and step round the Captain.

## 6. Focused screens

| View | Frame |
|---|---|
| Captain's Log (logbook, L) | `FocusFrame.BOOK`: green cloth boards, page block, ribbon |
| VHF set | `FocusFrame.RADIO`: graphite moulding, lit channel window, grille |
| Provisions locker, trophy board, berth (alarm), postcard (scrapbook) | `FocusFrame.TEAK` |
| Stove (cooking) | `FocusFrame.STEEL` with a fiddle rail |
| Switch panel | `FocusFrame.ELECTRIC` with breakers |
| Shops | `ShopCounter`: the shop's interior and sign |
| Instruments, plotter | `InstrumentView` / `PlotterView`: the package's own bezel |

A frame is attached after the modal opens, as a direct child of the modal
under its panel (never inside a container). It grows the panel in for 0.18 s
and is otherwise inert: no input, no per-frame work.

## 7. Instruments: data sources and package persistence

All packages read one `InstrumentData` snapshot per refresh from authoritative
state:
- speed and heading from the vessel;
- true wind from `Simulation.get_weather_at_vessel()`;
- route, distance, ETA and next turn from the voyage;
- forecast pages from `WeatherModel` (estimates);
- trim from the sail state;
- at anchor, holding, chain and depth from the anchorage state.

Nothing is invented: no apparent wind, no echo sounder, no battery or fuel.

The package is saved in the optional save section `instruments`
(`InstrumentState`):

```json
{"owned": [...], "fitted": {"<vessel id>": "<package id>"}, "pages": {"<package id>": ["<page per display>"]}}
```

Absent (any older save): Classic fitted everywhere, nothing owned. Unknown ids
are dropped. Packages are bought and fitted at the chandlery (Electronics); one
bought is owned for every boat.

## 8. Save compatibility

`SaveManager.SAVE_VERSION` stays **12**. The only new save data is the
optional `instruments` section above (safe defaults when missing). The quay
is a transient screen, not a boat area: a save made there records the Captain
on deck, on the pontoon by the walkway, and loads aboard there. The café,
hours, townsfolk and cabin objects keep nothing in the save. All existing
fields and content ids are untouched (`test_save_manager`, the
electronics suite's old-save checks and the quay suite's save check).

## 9. Performance

- The quay is built once per visit. People are a handful of `Node2D`s with no
  physics and no scans: each looks only at its own target and the Captain.
  The roster is compared with the clock every 2 s, not every frame.
- Instruments refresh from one shared snapshot at the HUD's own cadence. The
  removed sailing panel no longer updates while hidden.
- Cabin objects have no `_process` except the VHF lamp's blink (only while a
  call waits) and the postcard's 2 s check.
- Frames draw only on open and resize.

Measurements: [PERFORMANCE_OPPORTUNITIES.md](PERFORMANCE_OPPORTUNITIES.md) (I026 entry).

## 10. Retained conventional UI (on purpose)

These stay buttons and panels:
- the pause menu, settings, save and load
- the handbook and academy
- the clock and time controls
- the warnings (weather, collision, radar pop-up)
- the interaction prompt
- the shortcut strip
- the action wheel
- the build label
- the status line
- the Long Passage controls
- the chart table's course planning

They are about the game, not the boat. Or they are safety information that
must never wait for a walk. Or they are already the physical thing (the chart
table).
