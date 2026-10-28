# I026 "A World You Can Touch": UI inventory

Audit of the presentation layer as it stands on `iteration/i026` at
`670582f` (before any I026 work). Read-only: no code, scene, asset or test
was changed to write it. Every row is an interaction or panel that exists in
the code today, with `file:line` references. Line numbers are those at `670582f`.

**Categories**

| Code | Meaning |
|---|---|
| **A** | Should become a physical-world object (building, cabin object, equipment) |
| **B** | Physical-inspired focused display (an enlarged view of an instrument, logbook, laptop screen) |
| **C** | Keep conventional (the reason is given) |
| **D** | Redundant or removable |
| **E** | Already suitably physical |

**How things open today: the plumbing**

- **In-world stations**: `Interactable` areas under `Layout/Stations`, used with **E**.
  `BoatArea._on_interacted` (`src/boat/boat_area.gd:642-705`) maps each
  `interaction_id` to a signal, and `App._connect_boat_area`
  (`src/app/app.gd:1950-1966`) wires each signal to an `open_*` function.
  Stations come from three places: the vessel scenes (`companionway`,
  `nav_table`, `bed`, `provisions`, `work`, `hat`, `world_map` in every
  `cabin.tscn`; `companionway`, `helm`, `boatyard`, `grocery` in every `deck.tscn`, for example
  `src/vessels/starling_33/deck.tscn:551-581`), code (`fishing`, `anchor`,
  `cup_holder`, `cook`, `trophies`, `coffee_table`: `boat_area.gd:1011-1075`,
  `1148-1170`; `go_ashore`: `boat_area.gd:820-834`) and the companions (`pet`:
  `src/companion/ship_companion.gd:163`; `befriend`: `src/companion/dock_encounter_scene.gd:125`).
- **Hotkeys** (`project.godot [input]`, read in `App._unhandled_input`, `app.gd:399-463`):
  E interact, Q action wheel, T sail trim, R reel in / rod, P chartplotter, H hat,
  L Captain's Log, Esc pause/back, F1 Handbook, F5 quicksave, F9 quickload,
  F8/F10 developer only. On the chart: + / - zoom, M (anchorage waypoint toggle,
  `src/navigation/world_map.gd:218`), Delete removes a waypoint.
- **Action wheel** (Q): `ActionWheel` (`src/ui/action_wheel.gd`) shows the items from
  `App.get_wheel_actions()` (`app.gd:695-755`). The full per-area list is in
  *The action wheel per area* below.
- **Modals**: everything opened with `modals.push()` pauses gameplay
  (`app.gd:2014-2018`). Only the top modal is visible (`src/ui/modal_stack.gd`).
- **Screens**: the chart and the Dreamer's Map are a separate screen (`WorldMap`),
  not a modal. The boat scene is freed while they show (`app.gd:679-681`, `784-790`).

---

## 1. Harbour / pontoon

| # | Name (player sees) | Script(s) / scene(s) | How it is opened today | What it shows / does | Cat | Recommended I026 treatment |
|---|---|---|---|---|---|---|
| H1 | Gangplank and pontoon strip (walking ashore) | `src/harbour/shore_access.gd` (created in `boat_area.gd:804-841`) | Automatic on the deck while moored in harbour (`boat_area.gd:852-860`) | Opens the rail, adds a walkable gangplank and shore strip, and positions the service stations | E | Keep. It is the anchor for every new building. The strip is ±520 units (`shore_access.gd:25`), which limits how many storefronts fit (see Notes for the lead). |
| H2 | Grocery station + "Groceries" sign | Station `grocery` in each `deck.tscn` (e.g. `starling_33/deck.tscn:578-581`, prompt "Visit the grocery store"); sign: `GrocerySign` Label + `HarbourDressing` sign (`src/harbour/harbour_dressing.gd:97`) | E at the pontoon station (moved into a shore slot, `boat_area.gd:852-893`) | Opens **GroceryMenu** (§6) | A | **Grocery storefront on the quay** (awning, crates). E at its door opens the grocery as a shop-counter focused view. The sign art already exists (basket icon). |
| H3 | Boatyard station + "Boatyard · Repairs" sign | Station `boatyard` in each `deck.tscn` (prompt "Visit the boatyard"); `BoatyardSign` + HarbourDressing sign (wrench) | E at the pontoon station | Opens **BoatyardMenu**, which is the hub for boats, care, haul-out, chandlery, sailmaker and grocery (§6) | A | **Yard building / shed with a travel lift** (the lift only where `has(HAUL_OUT)`). Split the hub: the yard office (boats, care), plus separate chandlery and sail-loft doors (H5, H6). |
| H4 | Go Ashore station + "Go Ashore" sign | Interactable made in code when the scene lacks one (`boat_area.gd:820-834`); `GoAshoreSign` label duplicated from BoatyardSign (`boat_area.gd:835-840`); HarbourDressing sign (compass icon) | E at the pontoon station | Opens **GoAshoreMenu** (`src/ui/go_ashore_menu.gd`): one small harbour event with a picture, 1-2 priced choices and Return (`app.gd:1179-1203`) | A | **A path / gate into town at the quay end** (or a harbour notice board). Keep the event card as a B "story card" view. |
| H5 | Chandlery (no physical presence) | `src/ui/chandlery_menu.gd` (TradePanel) | **Only** the "Chandlery…" button in BoatyardMenu (`src/ui/boatyard_menu.gd:86`, `app.gd:1827`) | See §6 | A | **Chandlery storefront on the pontoon** that opens ChandleryMenu as a shop-counter focused view. Offered where `boatyard` is (`src/harbour/harbour_trades.gd:40-41`). |
| H6 | Sailmaker (no physical presence) | `src/ui/sailmaker_menu.gd` | **Only** "Sailmaker…" in BoatyardMenu (`boatyard_menu.gd:85`, `app.gd:1828`) | See §6 | A | **Sail loft** (rolled sailcloth in the doorway) beside the yard. |
| H7 | Fishmonger (no physical presence) | `src/ui/fishmonger_menu.gd` | **Only** a button in GroceryMenu (`grocery_menu.gd:17`, `app.gd:1133`) | See §6 | A | **Fish stall / fish-market counter** next to the grocery. Offered where `grocery` is (`harbour_trades.gd:38-39`). |
| H8 | Harbour signs (illustrated and classic) | `harbour_dressing.gd:97-99` (FACILITIES: text, icon, label), `:169-199`; classic labels `boat_area.gd:1000` (SIGN_LABELS) | Automatic; one per offered facility, at the slot's `sign` point | Marina sign board over each service | E | Keep. The sign table needs entries for each new storefront (there are 3 today). |
| H9 | Illustrated harbour (pontoon, quay, town, landmark strip) | `harbour_dressing.gd`, `harbour_art.gd`, `harbour_looks.gd`, `harbour_landmark.gd` | Automatic in harbour (`boat_area.gd:168-178`) | Art only, in four regional archetypes | E | Keep. This is the natural place to mount storefront facades along the quay line (`TOWN_FROM`, `harbour_dressing.gd:50`). Art-only rule: gameplay must not depend on it. |
| H10 | Mooring name "GUEST PONTOON · <PORT>" | `mooring_label`, `boat_area.gd:796-797`, `:841-846` | Automatic | Harbour name painted on the pontoon | E | Keep. |
| H11 | Dock encounter (box and stray animal; befriend) | `src/companion/dock_encounter_scene.gd`, `dock_box.gd`, `dock_girl.gd` | E on the animal (`befriend`, `dock_encounter_scene.gd:125`, `:167`); automatic placement at `BOX_OFFSET` 370 (`:26`) | A few kind gestures, then the animal follows the Captain | E | Keep. New storefronts must keep clear of x = ±370 from the plank. |
| H12 | Docking arrival | `boat_area.gd:725-760` (`play_docking_arrival`, `skip_docking`), `app.gd:1568-1587` | Automatic on arrival when aboard with no modal | The pontoon glides in, engine running, Captain at the helm; any key skips | E | Keep. |
| H13 | Arrival card / Golden Harbour Moment | `src/ui/toasts.gd:48` (`show_card`), `src/ui/harbour_moment.gd`; `app.gd:1546-1565`, `1616-1629` | Automatic on arrival (non-blocking, in the notice column) | Harbour picture, name and one line; a lit "first visit" memory | C | Keep as a notification: it never blocks and is a reward moment, not a control. |
| H14 | Facility refusal notices | `app.gd:1340-1345` (`_refuse_facility`), `GameSession.facility_refusal` | Automatic when a menu asks for a service the harbour lacks | Toast: "There is no … here" | C | Keep. With storefronts, absence becomes visible (no building), so these will be rarer. |

## 2. Deck / sailing HUD

### 2a. Deck interactions and panels

| # | Name | Script(s) / scene(s) | How opened | What it shows / does | Cat | Recommended I026 treatment |
|---|---|---|---|---|---|---|
| D1 | Helm | Station `helm` in every `deck.tscn`; prompts `boat_area.gd:67-68`, `:784-785`; `App._on_helm_requested` `app.gd:863-870` | E at the helm | In port: the departure question (D2). Underway: a re-assessment of the sail configuration, as a toast. At anchor: a hint toast | E | Keep. This is the obvious place to mount the cockpit instruments (D7-D9). |
| D2 | Departure confirmation ("Set sail for X?") with Passage Readiness | `app.gd:823-860`; `ConfirmDialog` (`src/ui/confirm_dialog.gd`); `src/boat_care/passage_readiness.gd` | Helm (D1), wheel `set_sail` (`app.gd:733`), chart footer "Set sail" (`world_map.tscn:337`) | Distance, estimate, readiness advice; Set sail / Cancel. Fetches companions first (`:828-841`) | C | Keep a conventional confirmation (a commitment with safety advice). Could be styled as a logbook entry later. |
| D3 | Companionway (Go below / Go on deck) | Station `companionway` in every cabin/deck scene; wheel `go` (`app.gd:742-745`) | E, or the wheel | Changes area (adoption question first if an animal follows, `app.gd:1693-1714`) | E | Keep. The wheel item `go` is a quick action (C). |
| D4 | Fishing rod (RodHolder) | `src/aboard/rod_holder.gd`; station `fishing` `boat_area.gd:1019-1026`; `app.gd:1207-1220` | E at the rod, **R** (`app.gd:442-446`), wheel `fishing` / `reel_in` (`app.gd:705`, `:741`) | Opens **FishingMenu** (`src/ui/fishing_menu.gd`): lure, line out/in, wait, cool box, keep rules; reel-in with ReelDial (`src/ui/reel_dial.gd`) | E (rod) / B (menu) | Rod: keep. Menu: restyle as a focused rod-and-reel view (ReelDial is already instrument-styled). Keep R as a quick action (a bite times out, `app.gd:1245-1255`). |
| D5 | Windlass (anchor) | `src/aboard/windlass.gd`; station `anchor` `boat_area.gd:1027-1034`; `app.gd:1310-1323` | E at the windlass, wheel `anchor` (`app.gd:726-727`) | Opens **AnchorMenu** (`src/ui/anchor_menu.gd`): site quality, scope, set-it timing bar, alarm seen, raise, Magic Anchor dial (`src/anchor/magic_anchor_deployment.gd`) | E (windlass) / B (menu) | Windlass: keep. Menu: a focused windlass / chain-counter view with a depth estimate. Keep the wheel item (quick action at anchor). |
| D6 | Sail trim | `src/ui/sail_trim_panel.gd`; `app.gd:758-768` | **T** (`app.gd:437-441`), wheel `sail_trim` (`app.gd:724-725`). **No in-world station** | Slider Eased ↔ Sheeted, boom sketch, "Well trimmed", crew takes over | A | **Sheet winch / mainsheet station in the cockpit** that opens a focused winch-and-boom view. Keep T and the wheel item as quick actions. |
| D7 | Sailing panel ("Sailing" / "At anchor") | `src/ui/sailing_panel.gd`, built in `hud.gd:94-99`; `should_show` `sailing_panel.gd:89-90` | Automatic underway (also **in the cabin**: no area check); collapse with its header button (`:50`, `:108`) or the wheel `sailing_panel` (`app.gd:720`) | Speed, drive, heading versus course, wind and angle, next leg forecast, next course change | A | **Cockpit instrument pod at the helm** (multifunction display). E opens an enlarged B view. Keep a compact HUD fallback (a setting) for accessibility and for the cabin. |
| D8 | Chartplotter | `src/ui/chart_plotter.gd`, built in `hud.gd:100-106`; `static var shown` `:33`; `should_show` `:92-93` | **P** (`app.gd:447-451`, `686-689`), wheel `chartplotter` (`app.gd:718-719`); deck only, underway | North-up plotter: coast raster, course, next turn, wind; +/- range | A | **Chartplotter mounted at the helm** (visible in the deck art). E or P opens an enlarged B view. Keep P. |
| D9 | Radar | `src/ui/radar_panel.gd`, built in `hud.gd:107-113`; `should_show` `:97-103` | Wheel `radar` toggle (`app.gd:722-723`); **automatic** while a vessel is a caution or collision risk | Range rings, targets coloured by concern, up to 3 target lines | A (manual) / C (auto) | **Radar display beside the plotter at the helm** for the manual toggle. **Keep the automatic pop-up in the HUD**: it is a safety warning (collision risk) and must appear wherever the Captain is. |
| D10 | Anchorage prompt ("We've arrived at our anchorage") | `src/ui/anchorage_prompt.gd`; `app.gd:1288-1307` | Automatic when an anchorage waypoint is reached; then the wheel offers `anchor` / `sail_on` (`app.gd:726-731`) | Drop anchor / wait / sail on | C | Keep: a critical navigation alert that the boat has stopped. |
| D11 | Anchor alarm | `app.gd:1326-1330`; AboardBadge line "Anchor dragging! Go to the windlass" (`src/ui/aboard_badge.gd:7-9`) | Automatic | Double beep, toast, red HUD line | C | Keep: a safety warning. An optional blinking alarm LED on the plotter would be a bonus. |
| D12 | Anchor signals (ball, rode, buoy) | `src/boat/anchor_signals.gd` | Automatic at anchor | The day shape, the chain into the water, a marker buoy | E | Keep. |
| D13 | Cup holder / coffee | `src/aboard/coffee_mug.gd`; station `cup_holder` `boat_area.gd:1035-1050`; `boat_area.gd:681-687` | E at the holder; wheel `coffee_down` / `coffee_finish` / `coffee_take` (`app.gd:747-752`) | Set the mug down, pick it up, drink | E | Keep. Keep the wheel items as quick actions (C). |
| D14 | Weather on deck (wind streaks, rain), sail rig, fenders | `src/boat/weather_visuals.gd`, `sail_rig.gd`, `fender_stowage.gd` | Automatic | Presentation of the wind, rain and sails | E | Keep. |
| D15 | Voyage map (Long Passage atlas) | `src/ui/voyage_map.gd`; `app.gd:1029-1038` | Automatic when fast passage time starts (passage panel rate buttons) | Full-screen chartplotter-style atlas; Back aboard / Sail on / Take the helm / rates (`voyage_map.gd:140-154`) | E | Keep. It is already a chartplotter look; reuse its style for D8's enlarged view. |

### 2b. What the HUD permanently shows

The HUD is `src/ui/hud.tscn` + `src/ui/hud.gd` on `HudLayer` (layer 10). It is
visible only in boat areas and on the chart (`app.gd:1981`). On the chart only
the clock bar shows (`hud.gd:186-206`).

| # | Element (node) | Script | When visible (sailing / harbour / cabin) | Shows | Cat | Recommended I026 treatment |
|---|---|---|---|---|---|---|
| U1 | **AreaPanel**: `AreaLabel`, `LocationLabel`, `StatusLabel` + symbol | `hud.tscn:17-59`; `hud.gd:276-292`, `:368-372` | Always in boat areas | Area name ("Cabin"/"Deck"); "Moored at X" / "Underway to X" / "At anchor, …"; the status line "Hull 87 % · Sound   €9,000   Food 12.5 d · Water 12.5 d", amber when hull ≤ 40 % or stores low | C | Keep the location (orientation) and the amber alarm. Food and water are already physical (ProvisionDisplay, C3). Money and hull could leave the HUD later (a wallet, a hull-check at the yard), but the alarm colour must stay. |
| U2 | **ClockPanel**: `ClockLabel`, `PausedBadge`, `TimeControls` (Pause / 1× / 5× / 20×) | `hud.tscn:61-95`; `src/ui/time_controls.gd` | Always, including the chart | Game time and date, pause, time scale | C | Keep: time control is a game control, not a world object. A ship's clock in the cabin could be decor (E). |
| U3 | **RoutePanel**: `RouteCaption`, `RouteLabel`, `RouteDetail`, `PropulsionLabel`, `WindLabel`, `VoyageProgress`, **MenuButton** | `hud.tscn:97-165`; `hud.gd:296-347` | Always; compact (wind + Menu) with no course planned (`:347-349`) | Underway: destination, nm to go, ETA, progress (holding at anchor). In port: planned route + estimate, or "Plot a course at the chart table", and the wind | C | Keep: critical navigation information. Its speed and wind duplicate the sailing panel underway (already hidden there, `:312-315`). The Menu button duplicates Esc (keep it for mouse users). |
| U4 | **WarningPanel** ("Weather warning", WarningText, "View chart", "Dismiss") | `hud.tscn:167-211`; `hud.gd:225-240`; `app.gd:1508-1520` | When a weather **or traffic** warning arrives; pending while on the chart | The warning text; View chart opens the chart on the Weather tab (`app.gd:801-806`) | C | Keep: safety-critical. Fix the title for traffic alerts (Notes for the lead). |
| U5 | **PromptPanel** ("E" + prompt) | `hud.tscn:213-243`; `hud.gd:216-222`, `:161-172` | When a station is in range | The focused station's prompt | C | Keep: the core interaction affordance (it will matter more with more buildings). |
| U6 | **Controls** shortcut strip | `hud.gd:40-41` (`SHORTCUTS`), `:117-135` | Always in boat areas | "WASD move · E interact · Q actions · R rod · H hat · L Captain's Log · Esc menu" | C | Keep: keyboard shortcuts. Consider a setting to hide it once learned. |
| U7 | **HatBadge** | `src/ui/hat_badge.gd`; `hud.gd:76-79` | Only when the hat is at risk or lost | "Hold onto your hat!  H" / "Hat missing" | C | Keep: an accessibility warning (never depend on sound). |
| U8 | **AboardBadge** | `src/ui/aboard_badge.gd`; `hud.gd:80-82` | When a line applies | "Fish on! Reel in R", "Line out · trolling", anchor holding / dragging, "Well fed" | C | Keep the alerts. "Well fed" is cosmetic and could become a companion or cabin cue (D candidate). |
| U9 | **PassagePanel** (Long Passage) | `src/ui/passage_panel.gd`; `hud.gd:83-93`; `should_show` `:118-120` | Underway, not anchored, voyage ≥ LONG_VOYAGE_NM; **also in the cabin** | Position, outlook, stores, rates Normal / 1 h/s / 4 h/s / 12 h/s, **Chart**, **Save…** (`passage_panel.gd:73-92`) | C | Keep the fast-time control (abstract time control). The Chart and Save buttons duplicate other paths (D, see Notes for the lead). |
| U10 | **SailingPanel**, **ChartPlotter**, **RadarPanel** | see D7-D9 | Underway | see D7-D9 | A | See D7-D9. |
| U11 | **Toasts** (notice column) | `src/ui/toasts.gd`; ToastLayer 30 | Automatic | Notices, arrival cards, harbour moments | C | Keep. |
| U12 | **AcademyGuide** card | `src/ui/academy_guide.gd`; AcademyLayer 15 (`app.gd:320-327`) | First Voyage steps and one-off tips | Skip / Read more / Close (`academy_guide.gd:84-86`) | C | Keep: onboarding and accessibility. Its steps reference stations, so they must be updated if stations move. |
| U13 | **BuildLabel** | `src/ui/build_label.gd`; layer 128 | Development builds | "LCH · i0xx · DEV · sha" | C | Keep (development only). |

## 3. Navigation (chart, plotter, trip planning)

| # | Name | Script(s) / scene(s) | How opened | What it shows / does | Cat | Recommended I026 treatment |
|---|---|---|---|---|---|---|
| N1 | The chart (navigation station's working chart) | `src/navigation/world_map.gd` + `world_map.tscn` (MODE_STATION), `map_view.gd`, `wind_layer.gd`, `anchorage_layer.gd` | Station `nav_table` in every cabin (`boat_area.gd:651-653`, prompt "Open chart"); wheel `chart` in the cabin ("Chart table", `app.gd:709`) **and on deck** ("Charts", `app.gd:739`); HUD warning "View chart"; PassagePanel "Chart"; Dreamer's Map "Plan it at the chart table" (`app.gd:793-798`) | A full screen: sidebar with header, tabs Course / Weather / Details, footer Apply / Discard / Set sail / Sleep / Back (`world_map.tscn:304-361`); toolbar + / - / World / Find boat / Wind / Anchorages (`:364-411`, `world_map.gd:1095`); wind legend with ◀ 1 h / Now / 1 h ▶ (`:1210-1230`) | B | **A focused chart-table view**: paper chart on the table, dividers and a pencil, the sidebar as a notebook. Keep the precision controls (they need a big, exact view). Arrive from the nav table. Keep "View chart" from a warning (C). |
| N2 | Course planning (waypoints, anchorage waypoints, Apply / Discard) | `world_map.gd` (draft model, `:58-77`; anchorage `:682-700`); `src/navigation/planned_route.gd`, `sea_router.gd` | Inside N1 | Plot a course, drag waypoints, mark anchorages (M), readiness label (`:970`) | B | Part of N1's focused view. |
| N3 | Dreamer's Map | `world_map.gd:403-455` (MODE_DREAM); `src/boat/cabin_world_map.gd` (framed wall map with visited pins) | Station `world_map` on the framed map in every cabin (`boat_area.gd:654-656`); wheel `dream_map` "World map" (`app.gd:708`) | The whole world, harbour stories, "Imagine this voyage" (`src/navigation/voyage_daydream.gd`), "Plan it at the chart table" | E (frame) / B (view) | Keep the frame. Restyle the screen as the framed wall chart enlarged (B). |
| N4 | Set sail (three entry points) | Helm (D1), wheel `set_sail` (`app.gd:732-733`), chart footer `SetSailButton` | see D2 | Departure question | D (duplicates) | Make the helm the home of "Set sail". Keep the wheel item as a quick action (C). The chart footer button could stay as a convenience. |
| N5 | Destination services preview | `HarbourFacilities.describe_services` (`src/harbour/harbour_facilities.gd:141-150`), used in the chart and Dreamer's Map (`world_map.gd:892`) | Selecting a harbour on the chart | "Major service harbour: Groceries · Boatyard · …" | C | Keep (information). Add the new storefronts if new facility ids appear. |
| N6 | Chartplotter / radar | see D8, D9 | | | A | |

## 4. Weather / VHF

| # | Name | Script(s) | How opened | What it shows / does | Cat | Recommended I026 treatment |
|---|---|---|---|---|---|---|
| W1 | Weather warning | HUD WarningPanel (U4); `Simulation.weather_warning` → `app.gd:1508-1510` | Automatic | Warning text, View chart, Dismiss | C | Keep: safety-critical. |
| W2 | Chart Weather tab, wind overlay, wind time navigator | `world_map.tscn:193-246`; `world_map.gd:1195-1240`; `src/navigation/weather_legend.gd`, `weather_style.gd` | Inside the chart; "View chart" opens it on this tab | Wind at the boat, weather along the course, forecast steps | B | Part of the chart-table view. A weather fax / NAVTEX printout at the nav table is a possible physical cue (no such system exists). |
| W3 | Wind readouts | HUD route panel `WindLabel` (`hud.gd:293`, `:378-388`), sailing panel | Automatic | "Wind WSW 14 kn, gusts …" | C / A | In port: keep in the HUD. Underway: the cockpit instrument pod (D7). |
| W4 | VHF call | `src/ui/vhf_dialog.gd`; `src/core/vhf_radio.gd`; `app.gd:1524-1543`, deferred in `_process` `app.gd:368-372` | **Automatic** as soon as nothing else is open (it also drops the time scale to ×1) | What is heard, Answer / Decline | A (+C) | **A VHF set at the nav station** (crackle, a lit call LED, E to answer, a focused handset view). Keep a short HUD/toast "Call on the radio" so a call is never missed (a safety and assist call). |
| W5 | Traffic alert | `app.gd:1515-1520`; radar auto-show (D9) | Automatic | Alarm, the HUD warning panel, a toast, the radar | C | Keep: safety. |
| W6 | Weather audio | `src/audio/weather_audio.gd` | Automatic | Wind, rain, thunder | E | Keep. |
| W7 | Brass barometer and brass compass (cabin decor) | `src/aboard/cabin_decor.gd:6`, `:69-72` | Bought at the chandlery, shown via "Make it home" | **Art only**: no reading. No barometer or pressure data exists in `src/` | E (today) | Optional A: make the barometer readable (an E-glance at the weather trend from WeatherModel). It needs a design decision: there is no pressure model. |

## 5. Cabin

| # | Name | Script(s) / scene(s) | How opened | What it shows / does | Cat | Recommended I026 treatment |
|---|---|---|---|---|---|---|
| C1 | Berth → Sleep | Station `bed` (prompt "Sleep"); `src/ui/sleep_menu.gd` + `.tscn`; `app.gd:897-908` | E at the berth, wheel `sleep` (`app.gd:707`), chart footer "Sleep" (`world_map.tscn:347`) | Choose 1-12 h, then sleep | E (berth) / B | Keep the berth. Restyle the dialog as a ship's alarm clock by the pillow (B). The chart's Sleep button is a duplicate (D, optional). |
| C2 | Time passing (sleep, dawn, dusk) | `src/ui/time_passage.gd`; `src/world/day_night_watch.gd`; `app.gd:1401-1421` | Automatic | Fade, date card, clock | E | Keep. |
| C3 | Provisions locker | Station `provisions` (prompt "Check provisions"); `src/boat/provision_display.gd` (art from the real quantities); `src/ui/provisions_menu.gd` + `.tscn`; `app.gd:1112-1118` | E at the locker, wheel `provisions` (`app.gd:710`) | Food and water days; "Grocery store (€)…" button in harbour | E (display) / B (menu) | Keep the display. A focused "open locker" view. The button to the grocery from the cabin is a duplicate path (D, see Notes for the lead). |
| C4 | Galley stove → Cooking / coffee | `src/aboard/galley_stove.gd`; station `cook` (`boat_area.gd:1052-1062`); `src/ui/cooking_menu.gd`; `app.gd:1262-1273` | E at the stove **only** (no wheel item, no hotkey) | Dishes from fish and stores, Make coffee | E (stove) / B (menu) | A focused stove-top view (the pan already steams in the world). |
| C5 | Trophy board | `src/aboard/trophy_board.gd`; station `trophies` (`boat_area.gd:1064-1074`); `src/ui/trophy_menu.gd`; `app.gd:1333-1336` | E at the board **only** | Five best catches on plaques, fishing record | E (board) / B | A focused, enlarged board view. |
| C6 | Hat hook | `src/hat/hat_hook.gd`; station `hat` (`boat_area.gd:666-667`, prompts `:70-75`) | E at the hook; **H** anywhere (`app.gd:427-431`, `1660-1661`) | Put on / hang up / the empty hook | E | Keep. H stays as a quick action (C). |
| C7 | Saloon-table mug | station `coffee_table` (`boat_area.gd:1148-1170`) | E when a mug is there | Pick up the coffee | E | Keep. |
| C8 | "Make it home" | `src/ui/cabin_home_menu.gd` (TradePanel); `app.gd:1169-1176` | **Wheel only** (`cabin_home`, `app.gd:711`); a side panel with no dimming (the cabin is the preview) | Show or put away the Captain's cabin things | A | **A sea chest / keepsake locker in the cabin**: E opens the same side panel. |
| C9 | Laptop (work station) | `src/boat/laptop_prop.gd`; station `work` (prompt "Use the laptop", `boat_area.gd:452-457`); `src/ui/laptop/laptop_view.gd`; `app.gd:1348-1360` | E at the cabin table, wheel `laptop` (`app.gd:714`) | The laptop up close with Home / Publications / Achievements / Voyage history (R3) | E | Already physical (I024). The model for B views. |
| C10 | Companion pet | `pet` station on ShipCompanion (`boat_area.gd:688-701`) | E on the companion | Pet animation, sometimes a remark | E | Keep. |
| C11 | Cabin windows, sea backdrop, lighting, decor | `cabin_windows.gd`, `cabin_sea_backdrop.gd`, `boat_lighting.gd`, `src/aboard/cabin_decor.gd` | Automatic | Art | E | Keep. |

## 6. Commerce

| # | Name | Script(s) | How opened | What it shows / does | Cat | Recommended I026 treatment |
|---|---|---|---|---|---|---|
| M1 | Grocery store | `src/ui/grocery_menu.gd`; `app.gd:1122-1137` | Pontoon `grocery` station (H2); **ProvisionsMenu** "Grocery store…" (`provisions_menu.gd:22`, `app.gd:1116`); **BoatyardMenu** "Grocery" (`boatyard_menu.gd:83`, `app.gd:1825`) | Fill food and water to 14 d, stock up for a long passage, replacement hat, lures/tackle, button to the fishmonger | A | A shop-counter focused view from the grocery storefront. Remove the boatyard's grocery button (D). Keep the provisions-locker link only if wanted. |
| M2 | Fishmonger | `src/ui/fishmonger_menu.gd`; `app.gd:1140-1141` | GroceryMenu button only | Sell fish from the cool box | A | Its own stall (H7). |
| M3 | Boatyard (boats) | `src/ui/boatyard_menu.gd` + `.tscn`; `app.gd:1813-1832` | Pontoon `boatyard` station | Browse the 4 boats (SubViewport preview of the real deck art), buy or switch; buttons Boat care / Grocery / Chandlery / Sailmaker (`boatyard_menu.gd:82-86`) | A + B | Yard office building. Keep the boat browser as a focused "yard office" view (B): the SubViewport preview is hard to make physical. |
| M4 | Boat care | `src/ui/boat_care_menu.gd`, `boat_care_view.gd`; `app.gd:1835-1847` | BoatyardMenu "Boat care…" only | Condition overview, repairs, services, equipment, haul-out | A / B | A yard workshop counter or a yard foreman at the shed (focused view). |
| M5 | Haul-out | `src/ui/haul_out_panel.gd`, `haul_out_scene.gd`; `app.gd:1850-1857` | BoatCareMenu only (major harbours) | Choose work, then the travel-lift animation, a day ashore | B | Already a schematic display. Optional A: a real travel lift on the quay in harbours with `HAUL_OUT`. |
| M6 | Chandlery | `src/ui/chandlery_menu.gd`; `app.gd:1145-1148` | BoatyardMenu only | Gear upgrades, Magic Anchor, lures, cabin things | A | Its own storefront (H5). |
| M7 | Sailmaker | `src/ui/sailmaker_menu.gd`; `app.gd:1152-1155` | BoatyardMenu only | Rig/sail service, sailcloth colours | A | Sail loft (H6). |
| M8 | Go Ashore events (they spend money) | `src/ui/go_ashore_menu.gd` | H4 | Priced choices | A / B | See H4. |
| M9 | Shared trade layout | `src/ui/trade_panel.gd` | (base class for M2, M6, M7, C8) | Title, who serves, rows with price buttons, funds, Close | B | Restyle once as a "shop counter" focused view so every trade follows. |

## 7. Records (log, laptop, postcards, renown)

| # | Name | Script(s) | How opened | What it shows / does | Cat | Recommended I026 treatment |
|---|---|---|---|---|---|---|
| R1 | Captain's Log | `src/ui/captains_log_menu.gd`; `app.gd:1745-1765` | **L** (aboard or on the chart, `app.gd:423-426`); pause menu "Captain's Log (L)" (`pause_menu.tscn:63-67`); wheel `log` (labelled "log" in port, "Captain's Log" underway, `app.gd:753`) | Tabs Log / Harbours / Objectives / Boat; stats, renown, passages, visited harbours, objectives and secrets, BoatCareView; "Publish travel update…" | B | **A physical logbook on the nav table**: E opens a focused open-book view. Keep L and the pause-menu entry (C: quick access). |
| R2 | Publish travel update | `src/ui/publish_menu.gd`; `app.gd:1768-1786` | Captain's Log button (`app.gd:1761`); laptop Publications (`laptop_view.gd:353`, `:369`); WorkMenu "Publish travel update…" inside the laptop (`work_menu.gd:50`, `laptop_view.gd:332`) | Renown → income, confirm | D (2 of 3 paths) | Keep it on the laptop (Publications) only. Remove the Log button and the WorkMenu button. |
| R3 | Laptop apps: Home, Publications, Achievements, Voyage history | `laptop_view.gd:27-32`, `:213-232`, `:376`, `:565` | C9 | Renown tiles, recent achievements, postcards, remote work, the little game, achievements filter, voyage records | E | Already physical. |
| R4 | Postcards / scrapbook | `src/ui/postcard_menu.gd`, `postcard_view.gd`, `scrapbook_menu.gd` | Inside the laptop (`laptop_view.gd:351-352`) | Make and publish a postcard (~2 h); browse the cards | E | Keep. Fix the stale hints (Notes for the lead). Optional: a pinboard of made postcards in the cabin (A, decor). |
| R5 | Remote work | `src/ui/work_menu.gd`; `app.gd:1376-1394` | Laptop Home "Remote work…" (`laptop_view.gd:321`) | 1-8 h of work in harbour | E | Keep. |
| R6 | The little game (Game Developer at Sea) | `src/ui/game_dev_menu.gd`; `app.gd:1484-1505` | Laptop Home "Your little game…" (`laptop_view.gd:325`) | Tasks, sessions, devlog | E | Keep. |
| R7 | Renown, secret achievements, new-harbour notices | `app.gd:1590-1647` | Automatic toasts + a chime | "+N renown", secret found | C | Keep (notifications). |
| R8 | Achievements / renown / voyage stats shown twice | Captain's Log Objectives and Log tabs versus laptop Achievements and Voyage history | — | The same records in two places | D (partly) | Decide one home per record: the log for passages and harbours, the laptop for renown and achievements. |

## 8. Companions

| # | Name | Script(s) | How opened | What it shows / does | Cat | Recommended I026 treatment |
|---|---|---|---|---|---|---|
| P1 | Companions aboard and ashore (follow, wander) | `app.gd:85-139`; `src/companion/ship_companion.gd`, `deck_companion_spots.gd` | Automatic | Up to two companions move between cabin, deck and pontoon | E | Keep. New storefronts must leave room for `ShipCompanion.SHORE_OFFSETS` (`app.gd:157`). |
| P2 | Pet | see C10 | E | | E | Keep. |
| P3 | Call aboard | Wheel `call_aboard` (`app.gd:734-738`), `recall_companion` `app.gd:168`; also inside the departure question (`app.gd:828-841`) | Wheel (deck, while a companion is ashore) | Fetches the companions at once | C | Keep as a quick action. Optional A: a ship's bell or whistle at the gangplank. |
| P4 | Dock encounter / befriend | H11 | E on the animal | | E | Keep. |
| P5 | Adoption dialog | `src/ui/adoption_dialog.gd`; `app.gd:1693-1723` | Automatic at the companionway when the animal follows | Adopt (name, she/he) / Not now | C | Keep: a narrative choice with text input. |
| P6 | Pair moments, welcome home | `src/companion/pair_moments.gd`, `welcome_home.gd` | Automatic | Animations | E | Keep. |
| — | Companion info / menu | — | **Does not exist** | Companion names show only in remarks, postcards and the laptop | — | Nothing to convert. |

## 9. Meta (pause, settings, save, handbook, academy)

| # | Name | Script(s) | How opened | What it shows / does | Cat | Recommended I026 treatment |
|---|---|---|---|---|---|---|
| X1 | Main menu | `src/ui/main_menu.gd` + `.tscn` | Start, or Return to Main Menu | New / Continue / Load / Import Next Harbor saves / Settings / Quit / Developer guides (dev) | C | Keep: outside the world. |
| X2 | Loading screen, language picker | `src/ui/loading_screen.gd`, `language_picker.gd`; `app.gd:1942-1947` | Automatic (the picker on first launch) | | C | Keep. |
| X3 | New game (difficulty) | `src/ui/new_game_menu.gd`, `difficulty_picker.gd` | Main menu | | C | Keep. |
| X4 | Pause menu | `src/ui/pause_menu.gd` + `.tscn`; `app.gd:1726-1742` | **Esc** in a boat area (`app.gd:452-463`); HUD **Menu** button (`hud.gd:68`) | Resume, Captain's Log, Save, Load, Settings, Difficulty…, Captain's Handbook (F1), Return to Main Menu, Developer tests (dev) | C | Keep: pause and safety. |
| X5 | Settings | `src/ui/settings_menu.gd` + `.tscn` | Main menu, pause menu | Audio buses, display, interface scale, Artwork, Sailing view, Flashing, Lightning flash, Motion, Tips, Interface light, Language (`settings_menu.gd:131-235`) | C | Keep (accessibility). It is the home for a future "instruments in HUD" fallback toggle. |
| X6 | Save / Load | `src/ui/save_load_menu.gd` + `.tscn`; `app.gd:1914-1925`; quicksave/quickload `app.gd:599-640` | Pause menu; **F5** / **F9**; PassagePanel "Save…" (`passage_panel.gd:92`) | Slot lists | C | Keep. The passage panel's Save is a duplicate (D, optional). |
| X7 | Difficulty | `src/ui/difficulty_menu.gd` | Pause menu | | C | Keep. |
| X8 | Captain's Handbook | `src/ui/handbook_menu.gd`; `app.gd:535-553` | **F1**, pause menu, the Academy card's "Read more" | Chapters and search; restart the First Voyage | C | Keep (help and accessibility). Optional: a handbook on the cabin shelf as an extra physical entry. |
| X9 | Academy (First Voyage, tips) | U12 | | | C | Keep. Update its step texts if stations move. |
| X10 | Confirm dialogs | `src/ui/confirm_dialog.gd` | From flows | Yes/no | C | Keep. |
| X11 | Rescue dialog | `src/ui/rescue_dialog.gd`; `app.gd:1096-1108` | Automatic after a loss at sea | Rescue report, fee | C | Keep: the outcome of a safety event. |
| X12 | Developer tools | `src/dev/dev_test_panel.gd` (F10, pause menu), F8 interaction areas, `src/ui/dev_guides_menu.gd` | Development builds only | | C | Out of scope. |
| X13 | Action wheel | `src/ui/action_wheel.gd` | **Q** | Context quick actions (next section) | C | Keep as the quick-action layer. Trim the items that duplicate a nearby station (see Notes for the lead). |

---

## The action wheel per area

From `App.get_wheel_actions()` (`app.gd:695-755`), in order. Title: "In the cabin" /
"At anchor" / "At the helm" (underway) / "On deck" (`app.gd:776-777`).

| Area / state | Items (id: label) |
|---|---|
| Any area, a fish on the line | `reel_in`: "Reel in!" first (`:704-705`) |
| **Cabin** (moored or underway) | `sleep` Sleep · `dream_map` World map · `chart` Chart table · `provisions` Provisions · `cabin_home` Make it home · `laptop` Laptop · `go` Go on deck · coffee items · `log` |
| **Deck, underway at sea** | `chartplotter` Chart plotter ☑ · `sailing_panel` Sailing details ☑ · `radar` Radar ☑ · `sail_trim` Trim sails · `anchor` Anchor (when anchoring is allowed) · `call_aboard` (if ashore) · `chart` Charts · `fishing` Fishing rod · `go` Go below · coffee items · `log` Captain's Log |
| **Deck, at anchor / holding at an anchorage** | as underway, without `sail_trim`; `anchor`; `sail_on` "Sail on from the anchorage" while holding (`:728-731`) |
| **Deck, moored in harbour** | `set_sail` Set sail (only with a planned route, `:732-733`) · `call_aboard` "Call … aboard" (companion ashore) · `chart` Charts · `fishing` Fishing rod · `go` Go below · coffee items · `log` "log" (lowercase, intentional: `tests/suites/test_cozy_polish.gd:355`) |
| Coffee items | carrying: `coffee_down` ("Coffee in the holder" on deck / "Set coffee down" below) + `coffee_finish`; mug set down here: `coffee_take` (`:747-752`) |

There are **no** wheel items for: cooking, trophies, any harbour service (grocery,
boatyard, Go Ashore, trades), the VHF, or the hat (H key). Some labels are plain
strings rather than `Loc.t` ("Sleep", "Provisions", "Make it home", "Radar", "Anchor",
"Charts", "log": `:707`, `:710`, `:711`, `:722`, `:727`, `:739`, `:753`). They depend on
Button auto-translation; check them in Danish.

## Harbour services today: how they are presented

- **Facilities model**: `HarbourFacilities` (`src/harbour/harbour_facilities.gd`).
  There are three shore-station facilities, `ALL = [grocery, boatyard, go_ashore]` (`:25`).
  `haul_out` is a boatyard service (`:26`, `:93`). The I020 trades `chandlery`, `sailmaker`
  and `fishmonger` (`:30-32`) are derived: fishmonger with grocery, chandlery and sailmaker
  with boatyard (`src/harbour/harbour_trades.gd:34-42`). The defaults give everything; 77
  per-port overrides are in `data/harbours/facilities/`. Tiers: small, larger, major (`:100-104`).
  There is no fuel dock (`:123`), no harbour office, no mooring fees and no harbour master.
- **Stations on the pontoon**: only **three** Interactables: `Grocery` and `Boatyard`
  (from each vessel's `deck.tscn`, under `Layout/Stations`) and `GoAshore` (made in code if
  missing, `boat_area.gd:820-834`). `BoatArea._update_shore()` (`boat_area.gd:852-893`)
  takes the harbour's offered ids in `ALL` order, asks `ShoreAccess.get_service_slots(count)`,
  moves each offered station to `slot.station`, gives it a 180 × 64 collision box, records
  `sign_at`, and hides the stations that are not offered (`_set_station_available`, `:896`).
- **Slot positions**: `ShoreAccess.SLOT_OFFSETS = [-215, 215, 430, -430]`
  (`src/harbour/shore_access.gd:29`), the distance from the gangplank in order of preference.
  `get_service_slots()` (`:140-149`) skips a slot within 80 units of the shore strip's ends.
  It returns `sign` (back of the pontoon, `SIGN_BAND` 38) and `station` (the walkable
  front edge). With all three: grocery at -215 (left of the plank), boatyard at +215,
  Go Ashore at +430. The 4th slot (-430) is unused today. The dock box sits at
  ±370 (`dock_encounter_scene.gd:26`), and companions use `ShipCompanion.SHORE_OFFSETS`.
- **Signs**: `HarbourDressing` draws a marina sign per enabled station at `sign_at`
  (`harbour_dressing.gd:183-199`): "Groceries" (basket), "Boatyard · Repairs" (wrench),
  "Go Ashore" (compass). With classic artwork the mooring's Labels show instead
  (`GrocerySign`, `BoatyardSign`, `GoAshoreSign`; `boat_area.gd:1000`).
- **Shared "shop" stations (yes, combined commerce)**:
  - The **boatyard station** is a hub. BoatyardMenu has buttons for **Boat care** (then
    **Haul-out**), **Grocery**, **Chandlery** and **Sailmaker** (`boatyard_menu.gd:82-86`;
    wired in `app.gd:1824-1828`). Five services behind one station.
  - The **grocery station** also hides the **fishmonger** (`grocery_menu.gd:17`,
    `app.gd:1133`).
  - The grocery is also reachable from the **cabin provisions locker** (in harbour).
  - **Chandlery, sailmaker, fishmonger, boat care and haul-out have no physical presence or
    sign at all.**

---

## Notes for the lead

1. **Five services have no place in the world.** Chandlery, sailmaker, fishmonger,
   boat care and haul-out are menus nested in the boatyard or grocery menu. They are the
   clearest I026 wins (storefronts). The pontoon strip has four slots and ~1040 units of
   width (`WALK_HALF` 520). It must also leave room for the dock box at ±370 and the
   companions' shore spots. Six or more storefronts need either more slots / two rows
   (a quay frontage beyond the pontoon via HarbourDressing's `TOWN_FROM` line), or
   grouping (the yard: office, sail loft and chandlery as one building with three doors).
   Note that HarbourDressing is art only, so new stations must remain `Interactable`s on
   the walkable strip.
2. **Duplicated paths to the same thing** (candidates for D):
   - Chart: nav table, wheel in the cabin, **wheel on deck ("Charts", which bypasses the
     table)**, HUD warning "View chart", PassagePanel "Chart", Dreamer's Map "Plan it…"
     (six entries).
   - Grocery: pontoon, provisions locker, boatyard menu.
   - Publish travel update: Captain's Log, laptop Publications, WorkMenu inside the laptop.
   - Set sail: helm, wheel, chart footer. Sleep: berth, wheel, chart footer.
   - Save: pause menu, F5, PassagePanel "Save…". Handbook: F1, pause menu, Academy.
   - Captain's Log: L, pause menu, wheel. Renown, achievements and voyage stats appear in
     both the Captain's Log and the laptop.
3. **Inconsistent entry points.** Cooking and the trophy board have a station but no
   wheel item. Sail trim and "Make it home" have a wheel item and no station. The
   chartplotter and radar have neither: they are HUD toggles.
4. **The sailing panel and passage panel also show in the cabin** (their `should_show`
   has no area check: `sailing_panel.gd:89-90`, `passage_panel.gd:118-120`), while the
   plotter and radar are deck-only. A cockpit-mounted instrument would change what the
   Captain sees below. Decide whether the cabin keeps a HUD readout (a nav-station
   repeater would be the physical answer).
5. **Traffic alerts reuse the "Weather warning" panel.** `_on_traffic_alert` calls
   `hud.show_warning` (`app.gd:1518`), but the title is a fixed "Weather warning"
   (`hud.tscn:187`), and no script changes it.
6. **Stale hints**: "finish it later from the cabin (Q, Write a postcard)" (`app.gd:1472`)
   and "Make one at the cabin table: Q, then Write a postcard." (`scrapbook_menu.gd:57`).
   The wheel has had no such item since I024 (postcards moved to the laptop, `app.gd:712-714`).
7. **Helpers used only by tests**: `App.open_work_menu()`, `open_postcards()` and
   `open_game_dev()` (`app.gd:1363`, `1453`, `1477`) are called only from test suites
   (e.g. `tests/suites/test_captains_other_life.gd`, `test_publishing.gd`). In-game,
   everything goes through the laptop.
8. **Systems the brief might assume but that do not exist**: a barometer or pressure
   reading (the brass barometer is cabin decor only), a depth sounder display (depths
   appear only as estimates in AnchorMenu), a compass instrument, a harbour office or
   fees, a fuel dock, a companion menu, a weather board or forecast in harbour, and
   VHF channel tuning (a call is a dialog).
9. **Hard to make physical, and why**:
   - Time controls and fast-passage rates: an abstract game control. The clock bar is
     the one shared time control, also on the chart.
   - The chart's planning UI: it needs a large, precise view, mouse drag and zoom. A
     focused B view, not an in-world object.
   - Radar auto-popup, weather and traffic warnings, the anchor alarm, the hat badge
     and "Fish on!": safety and accessibility cues that must reach the Captain anywhere.
     Keep them in the HUD (the project rule that nothing depends on sound,
     `hat_badge.gd:3`, `aboard_badge.gd:3-4`).
   - The boatyard's boat browser renders each vessel's deck in a SubViewport: keep it
     as a focused view.
   - Go Ashore events and the adoption dialog are narrative choice cards.
   - Save/load, settings, pause, handbook, difficulty: meta.
10. **Gameplay-safety caveat for the plan.** Moving a menu behind a station changes how
    and when it can be reached (for example, the sail trim currently works from
    anywhere on deck with T, and VHF calls open by themselves). Per CLAUDE.md §11, any
    change that alters gameplay reach needs the Captain's decision. Keeping the hotkeys
    and the wheel items as quick actions avoids most of that.

## Counts

These count 100 rows by their primary category. Cross-reference rows U10 and N6 are
not counted.

| Category | Rows | Which |
|---|---|---|
| A (physical object) | 19 | H2-H7, D6, D7, D8, D9 (manual), W4, C8, M1, M2, M3, M4, M6, M7, M8 |
| B (focused display) | 6 | N1, N2, W2, M5, M9, R1 |
| C (keep conventional) | 37 | H13, H14, D2, D10, D11, U1-U9, U11-U13, N5, W1, W3, W5, R7, P3, P5, X1-X13 |
| D (redundant / removable) | 3 | N4, R2, R8, plus the duplicate buttons in note 2 (wheel "Charts" on deck, PassagePanel Chart and Save, the boatyard's Grocery button, the chart's Sleep button) |
| E (already physical) | 35 | H1, H8-H12, D1, D3, D4, D5, D12-D15, N3, W6, W7, C1-C7, C9-C11, R3-R6, P1, P2, P4, P6 |

**Secondary B.** Ten E or A rows have a physical station today but open a plain menu
that should become a focused view: D4 (rod), D5 (windlass), N3 (Dreamer's Map), C1
(sleep), C3 (provisions), C4 (galley), C5 (trophies), M3 (yard boats), M4 (boat care)
and M8 (Go Ashore).
