# I026 - A World You Can Touch

*The living world and the physical interface.*

Version **0.112a**, save format **12** (unchanged; one optional new section).

| | |
|---|---|
| Starting commit | `3a27956e1bc7fb6cea11e205615b0455504793dd` (`release/i025`; `claude/friendly-fermat-dey23f` fast-forwarded to it before the start) |
| Iteration branch | `iteration/i026` |
| Release branch | `release/i026` (at the final tested commit; see the delivery note) |
| Build label | `LCH · i026_01 · DEV` while developed, `LCH · i026_06 · TEST` on the release commit |

The work was planned and built in these documents:

- the design: [DESIGN.md](DESIGN.md)
- an audit of every button and panel: [UI_INVENTORY.md](UI_INVENTORY.md) (100 rows; A 19, B 6, C 37, D 3, E 35)
- the electronics details: [STAGE_03_MARINE_ELECTRONICS.md](STAGE_03_MARINE_ELECTRONICS.md)

The technical description lives in [PHYSICAL_INTERFACE.md](../../technical/PHYSICAL_INTERFACE.md):

- the interaction language
- the mapping from old buttons to new places
- shop assignments, opening hours and townsfolk routines
- the focused screens
- the instruments' data sources and package persistence
- save compatibility and performance
- the conventional UI kept on purpose

## Stages

| Stage | What | Commits |
|---|---|---|
| 01 | Identity (0.112a, `i026_01`), the UI inventory and the design | `670582f`, `3518f3b` |
| 02 | Living harbours: the quay, storefronts, hours, townsfolk, café, office, noticeboard | `18331ff`, `b2354da`, `05398de` (merged `26c00aa`) |
| 03 | Marine electronics: SKERRY packages, cluster, focused views, cockpit instruments, the helm's plotter | `92449bf`, `0d2bcd8` (merged `e7236a4`) |
| 04 | Life aboard: logbook, VHF set, switch panel, sea chest, postcard, focus frames, the winch | `923783f`, `cc074b6`, `b264048`, `761e68d`, `6dca1d5` |
| 05 | Integration and polish | `26c00aa`, `46aefc3`, and the traffic warning's title fix |
| 06 | Evidence, guides, docs, benchmark, release | `d69f064`, `258bc70`, the closing commits |

Stages 02 and 03 were built in parallel and merged; each merge kept both
sides. A container restart interrupted stage 02 before its tests were
committed. It was recovered from its worktree, finished, tested, and merged
with stages 03–04.

## Part I - The living harbour

**The quay.** The guest pontoon's three service signs became one walkway, *To
the quay*. At its head is a walkable waterfront. Every business stands in its
own building, in the harbour's regional style (nordic, atlantic,
mediterranean, tropical), and only where the harbour offers it:

- the boatyard, with a travel lift where the yard hauls out
- the sail loft and the chandlery
- the harbour office, with the noticeboard by the walkway
- the café
- the grocery and the fishmonger's stall
- the lane into town (Go Ashore)

Ordinary houses fill the gaps. The same harbour always has the same quay. The
storefronts are separate but the backend is shared: each door opens the
menu that already existed, drawn behind as that shop's interior
(`ShopCounter`). Prices, stock and services are unchanged.

**Opening hours** follow the harbour's local solar time on the one clock:

- The café opens at 07:00.
- The sail loft opens late.
- The yard, chandlery and sail loft rest on Sundays.
- A Mediterranean quay stays open into the evening.
- A small harbour keeps shorter hours.

You can see the hours on the quay itself: the hours plate and OPEN/CLOSED sign
on every door, the prompt, lit windows, a shopkeeper locking up, and every
business's hours in the harbour office. A closed door offers *Wait until it
opens*. The harbour office's hatch is always staffed and sells the essentials
(food and water, an emergency hull repair), so nobody is stranded by the
clock.

**Townsfolk.** There are 3, 6 or 8 people by harbour size, fewer in bad
weather and nearly none at night. They walk, pause at shop windows and
benches, shop (only in open shops), and sit at the café. A fisherman works in
the morning and a late walker comes out at night. Who is about is a pure
function of the harbour, the day and the hour. It is reconstructed after
sleep or a time skip and never simulated while away. People have no physics
body and step round the Captain.

**The café.** A coffee costs EUR 4 (scaled by difficulty like every cost). The
Captain sits at a terrace table with a mug, companions settle nearby, and
other customers come and go. It earns nothing: it is just a coffee by the
water.

## Part II - Marine electronics

The instruments come from **SKERRY**, a fictional maker, in three packages:

- **Classic**: analogue dials and an LCD repeater. Free, fitted to every boat.
- **Modern Cruiser**: three glass displays with selectable pages. EUR 680.
- **Offshore Navigator**: one wide MFD with layouts. EUR 1,480.

Packages are bought and fitted at the chandlery (Electronics). A package
bought is owned for every boat, and the fitted package and its pages are
saved.

- **On the HUD:** the instrument cluster replaces the sailing panel.
- **Close up:** I, the wheel's *Instruments*, or E at the cockpit instruments.
- **The chartplotter:** at the helm on every deck. P or E opens it focused.
- **Warnings:** these stay in the HUD.

Every display reads one snapshot of the game's own data. There is no apparent
wind, no echo sounder, and no battery or fuel: nothing is invented to justify
an instrument. Details:
[STAGE_03_MARINE_ELECTRONICS.md](STAGE_03_MARINE_ELECTRONICS.md).

## Part III - Life aboard

Every boat's cabin now has the things a sailor uses, each placed so the
Captain can reach it. Each opens framed as the object (`FocusFrame`), and Esc
puts it back.

- **The logbook** at the nav station is the Captain's Log itself, as a bound
  book. L still opens it.
- **The VHF set** has a lamp that blinks while a call waits. You can answer
  the call there. The weather broadcast is put into words from the game's
  weather and the forecast on the course.
- **The switch panel** shows only what the game keeps: the care survey, what
  the yard fitted, the sails, food and water, and the instruments.
- **The sea chest** by the berth opens "Make it home".
- **The newest postcard** lies on the saloon table once one is made, and
  opens the scrapbook.
- **The sheet winch** on the cockpit coaming of every deck trims the sails, as
  T does. Moored, it says why not.
- **Existing cabin menus** are framed as their objects: the provisions locker
  (teak), the stove (steel), the trophy board (teak) and the berth's alarm
  (teak).

Companions live alongside all of this: the companion suites, from deck and
cabin places to shore visits, pass with the new objects in place.

## Part IV - Quality

- **One interaction language.** Focus glow, prompt, E, the focused view, Esc.
  Quick actions stay, so nothing became a chore.
- **Save compatibility.** `SAVE_VERSION` stays 12. Old saves load: Classic is
  fitted, and a quay save loads aboard by the walkway.
- **Danish.** 3,057 messages, 0 missing.
- **Fit.** Every focused view fits at 1280×720 and 1024×768, at 100 % and
  130 %, in both languages (tested).
- **Polish.** From the audit: a traffic alert is now titled *Traffic warning*
  (it said "Weather warning"). Stale postcard hints now point to the laptop.

### Conversions

What became physical:

- the shops: boatyard, chandlery, sail loft, grocery, fishmonger, the café, the harbour office, the noticeboard, Go Ashore and the haul-out
- the instruments and the plotter
- sail trim (the winch)
- the Captain's Log (the logbook)
- the VHF set
- the switch panel
- "Make it home" (the sea chest)
- the scrapbook (the postcard)

Already physical and now framed: the provisions locker, the stove, the trophy
board and the berth.

**Panels removed:**

- the sailing panel (`sailing_panel.gd`)
- the HUD chartplotter panel
- the wheel's *Sailing details*
- the pontoon's grocery, boatyard and Go Ashore stations and their signs
- the grocery, chandlery and sailmaker buttons inside the boatyard
- the fishmonger button inside the grocery

**Kept conventional, on purpose:**

- the pause menu, settings, save and load
- the handbook and academy
- the clock and time controls
- warnings and the radar's pop-up
- the prompt, the shortcut strip and the action wheel
- the build label, the status line and the Long Passage controls
- course planning at the chart table, which is already the physical thing

**Not converted:**

- **Radar.** It stays a HUD toggle and pop-up, because it is safety information.
- **Remote work, postcards and the game project.** They stay on the laptop,
  which is already an object.
- **Fishing.** It is already physical.
- **Anchoring.** The windlass and the existing flow are unchanged.
- **The duplicate ways to open the chart.** They were kept as quick actions.

## Tests

| Run | Result |
|---|---|
| Full regression (85 suites, headless Linux, at `26c00aa`) | 5,522 passed, 2 failed. Both failures were the new academy strings, run before their Danish was added in the same session. Re-run below. |
| `test_localization`, `test_academy`, `test_living_harbours`, `test_cabin_objects`, `test_gameplay_flow` after the Danish and the new layout checks | 420 passed, 0 failed |
| `test_cabin_objects`, `test_captains_watch`, `test_localization` after the warning-title fix | 145 passed, 0 failed |
| Stage suites, as they were built | `test_living_harbours` 99/0 alone; the affected older suites with it, 1,303/0; `test_marine_electronics` and `test_cabin_objects` as reported in their stages |
| Save | `test_save_manager` and the old-save checks of the electronics and quay suites are in the full run (pass) |
| Content | `check_game_content.py`: 31 PASS, 0 FAIL |
| Docs | `check_gdscript_guides.py`: every script reviewed. `check_links.py`: 0 broken |

**Test changes.** No test was weakened. Some existing checks had to follow
the move of the shops up to the quay, so they now walk up the walkway and use
the door (`tests/helpers/quay.gd`). Those checks are in the pontoon sign tests
and the trade, care and vessel suites. The "two interactables in reach" check
of `test_gameplay_flow` now requires the companionway and the chart table,
and also allows the nav station's own logbook, VHF set and switch panel.

**Fixed while testing.** These were found by the tests:

- closed days compared a JSON float to an int, so Sunday never closed
- the next opening landed a rounding error before the hour
- the travel lift's door stood in the boatyard building
- a bench blocked the only lane past the yard
- a suite left a save in slot 1

## Performance

Measured in the same session against `release/i025`, on an otherwise idle
machine. The results are in the
[PERFORMANCE_OPPORTUNITIES.md](../../technical/PERFORMANCE_OPPORTUNITIES.md) I026 entry:

- the WRS benchmark, two runs each
- the quay's own probe: deck against quay at noon, and the quay at 20×

## Evidence

All under `docs/screenshots/i026/`:

- **`harbour/` 01–25:**
  - the pontoon walkway and the quay's arrival
  - each entrance and its highlight, and the shop counters
  - the noticeboard
  - people at noon and in the morning
  - a closed chandlery and *Wait until it opens*
  - the café with customers, and a companion resting there
  - a shopkeeper locking up, and the quay at night
  - regional variants (Svendborg, Naples, Hydra, Castries, Dingle, Lohals)
- **`instruments/`:**
  - the HUD before and after
  - the three packages by day and night
  - the focused views, the plotter, the cockpits and the chandlery
- **`motion/` strips:** made by `tests/screenshots_i026_motion.tscn` and `tools/qa/film_strip.py`.
  - the quay through a day (NPC routines)
  - people walking at noon
  - the café (ordering, sitting, drinking)
  - a walk into the chandlery (shop interaction)
  - the instruments' pages switching
  - the logbook brought close (the focused-view transition)
- **The test runner's own screenshots:** the cabin objects on every boat, every framed view, and the winch.

## Windows

[WINDOWS_ACCEPTANCE.md](WINDOWS_ACCEPTANCE.md): a morning in harbour, a day
at sea, an evening aboard. Linux results are not Windows acceptance: these
checks are pending.

## Known limitations

- **The shortcut strip** is the same everywhere. It still lists R (rod) and H
  (hat) on the quay, where R does nothing.
- **People on the quay** are small at true scale, like the Captain. They are
  readable but not detailed.
- **The instruments on the HUD** are small at sailing zoom. Their focused view
  is the place to read them.
- **The chartplotter's coast** is a raster and looks blocky up close.
- **I (the instruments)** is not in the shortcut strip.
- **"Sunday"** is the harbour's own solar weekday. A long eastward passage
  can shift it by a day from the UTC date.
