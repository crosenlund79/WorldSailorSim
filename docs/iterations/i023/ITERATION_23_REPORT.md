# I023 — Steady Hands & Golden Harbours (0.109a)

Commissioned as the polish injection *Operation Steady Hands & Golden
Harbours* and developed on the integration branch. After delivery, the
Captain reclassified it as **Iteration 23**. Its branches were created
afterwards at the delivered commit: `iteration/i023` and the frozen
recovery snapshot `release/i023`, both at
`d4e2e7e56206b220f8839323186e0c06d2a4c589`. The next numbered iteration is I024.

Mission A (The Unshakeable Chartroom) came first, and Mission B (Golden
Harbour Moments) followed once A was green. Mission A found serious
problems, but they were fixed inside A, so B was delivered, not deferred.

| | |
|---|---|
| Approved branch | `claude/friendly-fermat-dey23f` (the integration branch; injections and polish are committed there, see `CAPTAINS_ORDERS.md`) |
| Start | `2baa01034fbaa956018c58e013b555be8213d77d` (I022 complete; `release/i022` and `iteration/i022` at the same commit, both left untouched) |
| Mission A | `190ae21dc6ee6858744dc3fef608fa24b9c37c76` |
| Mission B | `0672a05ef542a8dadb48dad654a063feea56d977` |
| Final (delivered) | `d4e2e7e56206b220f8839323186e0c06d2a4c589` |
| Branches | `iteration/i023` and `release/i023` at the delivered commit (created on reclassification) |
| Version / save format | 0.109a / 12, unchanged (no save fields added) |

## Mission A: The Unshakeable Chartroom

### What was inspected

These were inspected at 1280×720, 1600×900 and 1920×1080 (all three give
the same 1920×1080 canvas under the project's `expand` stretch), 1024×768,
2560×1080 and interface sizes 100 % and 130 %, in English and Danish:

- the HUD and its panels: status, clock, wind, route, Trip Details, warning, prompt, chartplotter, radar and notices;
- the main screens: main menu, new game, language picker, load, chart and dream map;
- all 34 windows the game opens from its own entry points, moored and underway. These cover pause, settings, sleep, the Q wheel, the Captain's Log, fishing, galley, groceries, Go Ashore, boat care, haul-out, the Boatyard and its shops, Make it home, the Academy, postcards, game development, the VHF call, sail trim, anchor, confirm dialogs and the rest.

The 37 modal classes and the HUD pieces are listed in `test_steady_hands`
(its openers and `HUD_PAIRS`).

### The Captain's bug: the weather report moved Trip Details

- **Cause:** `Hud.refresh` placed Trip Details (the sailing panel) under the weather warning whenever one showed, with a fixed 124 px warning height. Every warning pushed Trip Details down by about 136 px, and a long Danish warning ran over it and hid its buttons.
- **Fix:** Trip Details now hangs only from the route panel. The warning sits below it and is as tall as its text needs (`Hud._stack_right_column`).
- **Proof:** `[trip details]` shows, updates and hides a warning 12 times per combination: English and Danish, day and night, Trip Details collapsed and expanded, short and very long texts. Trip Details never moves (0 px), and the warning never covers it.
- **Screenshots:** before and after are in [`steady_hands/`](../../screenshots/steady_hands/) (`before_/after_trip_details_with_warning_da.png`).

### Other bugs found and fixed

| Problem | Fix |
|---|---|
| Settings was taller than a 1080-line screen: its title and Apply / Back were cut off, worse at 130 % | `FitScroll`: the middle scrolls, title and buttons stay |
| The Boatyard was taller than the screen at 130 % | `FitScroll` |
| Make it home's right column was 37 px off screen | Column anchored to the panel's real width |
| The route panel ran under the clock at 130 % | It narrows to fit; the compact rule is kept |
| The radar and chartplotter covered the interaction prompt at 130 % | The prompt steps aside |
| Danish screens showed English: "Moored at"/"Arrived at", lure, recipe and upgrade names, Go Ashore choices, "free" | Through `Loc.t` (new: "gratis") |
| Renown notices listed milestone names in English in Danish ("Cast off", "New horizons") | `App._on_renown_awarded` translates titles |
| **At every dusk and dawn the whole interface sat half-way between its day and night colours for the full twilight, many game minutes, and text and panel became the same grey (contrast 1.0:1)** | The interface switches mood once, at the middle of the twilight (sun −1°, ±0.5° so it never flickers), and still eases over a few seconds. Text colours change at the middle of that fade instead of mixing (worst moment 2.5:1, was 1.0:1) |
| Reparenting a button connected its click sound twice (error) | Connected once per button |
| Every earlier layout test ran on a 1920×1920 canvas (the test runner's 64 px window) | Layout suites set a real window size and restore it |

The dusk problem came from before this work (the Chartroom theme pass). It
showed up in the Mission B screenshots: Symi at dusk, before the fix, had a
washed-out HUD and an unreadable notice.

### Test-reliability fixes (investigated, not hidden)

| Test | Root cause | Fix |
|---|---|---|
| `test_gameplay_flow` "ended on deck after round trips" (about 1 run in 7) | The new diagnostics showed it: the ship's cat sometimes sat at the hatch, so E petted it instead of using the companionway and every later trip was off by one | The round trip moves the companion aside when the prompt is not the hatch's |
| `test_gameplay_flow` "[voyage] no teleport" | Not a teleport. About 43 s of game time passes while the chart opens (the clock check allows 120 s), and the boat honestly sails about 110 m, right at the old fixed 1e-3° limit. It failed 2 of 2 times on the committed Mission A state | Limit = what the boat can sail in the elapsed time (12 kn) + 10 m; the message gives metres and seconds |
| `test_living_world` "[sailor] walking swings the arms" (0.00 … 0.59/0.60, in the full run and every time alone) | Diagnostics showed the walk from the start spot, beside the companionway, stopped at deck fittings after 31 px (less than one 46 px stride), so the swing never passed its first half and topped out right at the 0.6 limit. A first guess (a slow first frame) was wrong and is not the fix | The walk starts on the open foredeck and is measured by distance; the check needs at least one stride walked (now 72 px, swing −0.98 … 0.61, 3/3) |
| Several suites | `Simulation.auto_advance` left off for the next suite | Restored |

### The maintainable UI suite: `test_steady_hands`

It holds explicit invariants and named exemptions, not pixel diffs:

- **Windows:** on screen within 1.5 px; Esc closes (exempt: `LanguagePicker`, first launch, which closes only by choosing a language); no raw `%s`/`{…}`; no English phrase that has a Danish translation while Danish is chosen.
- **HUD:** named pairs never overlap (overlap elsewhere is deliberate: modal dim, notices).
- **Screen:** nothing invisible catches the mouse.
- **Context:** a change of context under an open window leaves it closable; loading leaves nothing behind.
- **Dusk:** never parked half-way, and text readable through the change.
- **New windows:** add one opener to `_openers()`.

## Mission B: Golden Harbour Moments (delivered)

The first arrival in a harbour that has a picture (the I021 harbour looks
and the six special harbours) now shows a small illustrated card in the
notice column:

- **Picture:** the harbour's own I021 picture, set in a sky and a sea for the hour.
  - **Day:** the picture as drawn.
  - **Dawn:** a pale sky and a little mist on the water.
  - **Dusk:** a warm sky; the picture warmed and its own windows starting to glow; lanterns along the quay with short reflections.
  - **Night:** the picture dimmed under a starry sky (stars only when the sky is clear); windows lit; lanterns.
- **Weather:** overcast greys the sky (the same rule as the boat and cabin lights, `BoatLighting.overcast_of`).
- **Windows:** the lit windows are the painting's own dark window panes, found once per picture (dark filled shapes set in a lighter wall on at least three sides, so palm leaves against the sky are not lit). No art was added or invented.
- **Text:** the harbour's name, its one-line description and the Captain's Log line ("New harbour in the Captain's Log: …"), which replaces the separate notice (one card, not two). A stamp reads "First visit · date", or "✦ Special harbour · First visit · date". English and Danish ("Særlig havn", "Første besøg", "Klik for at lægge det væk").
- **Quieter repeat:** a known harbour keeps the I021 small card, and a second visit shows no moment.
- **No spam:** loading a game moored in a new harbour, and going below and back, show nothing, because the card comes only from a real arrival (`voyage_logged` with a new harbour, then `arrived`).
- **No exploit:** no reward is attached; renown and the Log are unchanged.
- **Unobtrusive:** dismissed with a click and gone by itself after 14 s; it never pauses the game, opens a window or takes the keyboard.
- **Cost:** drawn once when shown (no per-frame redraw, no shader). Finding the windows took 18 ms for four pictures the first time and 0.01 ms cached (headless).

Limitations, stated plainly:

- Symi's painted windows are pale, not dark, so none are found. Symi keeps the warm sky and the lanterns.
- Harbours without a picture keep their plain arrival as before.

Screenshots, all in the real game interface at 1280×720, in
[`steady_hands/`](../../screenshots/steady_hands/):

| Screenshot | Time | Archetype | Language |
|---|---|---|---|
| `golden_helsingor_day_en.png` | day | Nordic gabled waterfront (Helsingør) | English |
| `golden_symi_dusk_da.png` | dusk | Mediterranean, a special harbour (Symi) | Danish |
| `golden_bequia_night_en.png` | night | Caribbean tropical island (Bequia) | English |

## Performance

- **Theme switch:** fewer theme steps per twilight (at most 16 instead of up to 50); step cost unchanged.
- **Harbour Moment:** no per-frame work.
- **HUD layout:** reflows only when a value changes.
- **FitScroll:** recomputes only on a window, interface-size or content change.

The [Performance Opportunity Register](../../technical/PERFORMANCE_OPPORTUNITIES.md) is
updated (#2, and a row under *Measured and rejected*).

## Tests and checks

- `test_steady_hands`: 63 checks. `test_golden_harbours`: 20 checks.
- Targeted regression of the arrival and flow suites: 426/426 (`test_wider_world`, `test_captains_log`, `test_steady_hands`, `test_living_world`, `test_gameplay_flow`, `test_golden_harbours`). Theme suites: 95/95 (`test_chartroom_ui`, `test_well_run_ship`, `test_golden_harbours`).
- Full suite, rendered (xvfb, 1600×900), on `0672a05`: 5016 passed, 3 failed.
  - `test_living_world` arm swing: root-caused and fixed (table above), then 3/3 alone.
  - `test_navigation_views` "[dream] after panning across the Date Line the land is still drawn".
  - `test_settings_and_audio` "window mode 'fullscreen' is applied (expected 4, got 0)".

  The last two are not caused by this work. They fail the same way at the start commit `2baa010`, checked out separately and run in the same container, although both passed in earlier runs here. They depend on the environment: exclusive fullscreen under xvfb without a window manager, and the dream chart's land after a fast pan. They are left unchanged and reported, not weakened. Fullscreen is part of the Windows checks below.
- Content checker: no FAIL. Links: OK. i18n: extract and check with 0 errors, Danish 2636/2636. GDScript guides: every script has entries in English, Danish and the architecture reference, all reviewed.

## Windows acceptance tasks for the Captain

Nothing here has been tried on Windows; these checks wait for the Captain's own trial.

1. Sail with a weather warning showing. Open, update and dismiss it, and confirm Trip Details stays exactly where it is (Trip Details open and closed).
2. Settings and the Boatyard at 1280×720, at interface size 100 % and 130 %. The title and buttons should be visible, and the middle should scroll with the mouse wheel.
3. Play through a dusk and a dawn at 1×. The interface should change from day to night once, within a few seconds, and stay readable throughout.
4. Danish: renown notices, groceries, the galley, Go Ashore and the HUD should all be in Danish.
5. Arrive in a new illustrated harbour by day, and another at dusk or night. Check the card's look and that a click puts it away. Then return to a harbour you know (small card only), load a game, and go below and back (no card).
6. Resize the game window (smaller than 1280×720, and ultra-wide) with a window open. Nothing should leave the screen, and Esc should still close it.
7. Settings, Fullscreen: the game should go fullscreen. In the dream chart, pan east across the Date Line: the land should still be drawn (both could not be confirmed under the cloud test display, see above).
