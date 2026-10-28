# Operation One Clock: fast time, dawn and dusk

A focused diagnosis of the slowdown the Captain sees above 1×. **No game code
was changed.** One diagnostic scene was added for the Windows sea trial (F).

| | |
|---|---|
| Start commit | `2daf8e4f51f717e22e84d154b35a457411f74f84` (`claude/friendly-fermat-dey23f`) |
| Speeds in the game | 1×, 5×, 20× (`SessionState.TIME_SCALES`: 60, 300, 1,200 game seconds per second); Long Passage 1, 4, 12 h/s (separate, not the subject) |
| Machine | Linux, Godot 4.7.2, Compatibility renderer, **llvmpipe (software rendering on the CPU)**, 1600×900, vsync off. **Not a GPU, not Windows** |
| Tool | `tests/one_clock_sea_trial.tscn` (scenarios, per-system timing each frame); runs: all scenarios once, the long run and the trial again |

## A. Reproduction

- **Speed alone does not slow the game here.** Each state costs the same at
  1×, 5× and 20×, within run-to-run noise of about 5 ms (table below). No backlog builds up: at 20× a frame never
  handles more than one 5-minute evaluation point, and nothing grows over
  60 game hours at 20× (578 nodes at the start and at the end).
- **What is slow is the lit scene:** night at sea about 1.8× a day frame, and
  **the harbour at night about 3.5×**. It is the same at 1× and at 20×, so it
  is persistent, not a transition hitch.
- **Dawn and dusk:** by default a date card covers each twilight (Well-Run
  Ship): one interface recolouring, the twilight simulated under the black.
  Without the card (twilights over 2 h, high summer in the north), the
  interface eases over at most four steps a second: brief 4–8 ms hitches on
  deck, 20–24 ms at the chart. These are single hitches, not slow play.
- **Why 20× feels worse:** at 20× a whole day passes in 72 seconds. The
  Captain then spends half of every minute in the night lighting, meets a
  date card about every 36 seconds, and waiting in harbour at 20× means
  sitting in the most expensive scene. At 1× an evening lasts an hour.
- Not reproduced here: any slowdown that depends on the speed itself.

## B. Measurements (llvmpipe; frame median / p95 in ms; measured)

| Scenario | 1× | 5× | 20× |
|---|---|---|---|
| Open water, day | 37 / 48 | 36 / 46 | 38 / 48 |
| Open water, night | 64 / 77 | 69 / 82 | 69 / 89 |
| Harbour, night | 135 / 164 | | 130 / 154 |
| Harbour, night, all lights hidden | | | **57 / 69** |
| Through dusk, card on (default) | 59 / 75 | 47 / 79 | 42 / 79 |
| Through dusk, no card | | 37 / 71 | 45 / 72 |
| Chart open through dusk, no card | | 49 / 67 | 49 / 64 |
| 20× for 60 game hours, cards on | | | 46 / 85, worst 128 |

| Per-system cost (timed separately each frame) | Measured |
|---|---|
| Simulation (`Simulation.tick`: steps, weather, traffic, VHF, anchor) | 0.2 ms (1×) to 0.8 ms (20×) a frame; worst frame 9.7 ms; at most 1 evaluation point per frame |
| Interface recolouring (`UiTheme.set_blend`) | 4–7.5 ms a step on deck, 20–24 ms at the chart; 1 step per twilight with the card, 16–17 at 20× and 34–37 at 5× without |
| Boat light script (`BoatLighting._process`) | 0.06–0.11 ms a frame |
| Dawn/dusk watch (`DayNightWatch`) | ≤ 0.02 ms |
| Render time, harbour at night: lights on → hidden | 124 → 52 ms |
| Through dusk at 20×: theme frozen / lighting frozen / both | 67 / 42 / 42 ms (normal 66) |

The worst frames never coincide with an interface step or a simulation step.

## C. Root cause

- **Confirmed (here):** the clock and the speed system are not the
  bottleneck. Simulation, interface recolouring and the watch together cost
  about 1 ms a frame on average and at most about 10 ms in a frame, at any
  speed. The earlier theme stall (0.7–2.3 s per step) stays fixed.
- **Confirmed (here):** frame time follows the **boat and harbour lights**
  (`src/boat/boat_lighting.gd`: `PointLight2D` lamps, navigation lights, quay
  lamps). Hiding them halves the harbour night frame; the script itself costs
  0.1 ms. In harbour the lights fall on about 775 draw calls (the harbour
  dressing), against about 250 at sea.
- **Probable, not proven:** the Captain's slowdown above 1× is that cost (and
  the frequent cards), met far more often at 20×. Whether 2D lights are
  expensive on the Captain's GPU is **not known**: software rendering
  exaggerates lighting, and a GPU may draw them almost for free. If the
  Windows trial shows the harbour slow only with the lights on, this is the
  cause; if every row is fast there, the cause is elsewhere and the trial's
  per-system columns show where.

## D. Three options

| | 1. Fix live accelerated time | 2. 1× only, with time jumps | 3. Hybrid (1× and 5× live, jumps instead of 20×) |
|---|---|---|---|
| Expected performance | The real gain is in the **lights**, the same fix at every speed: fewer or cheaper lights (light range and item masks so a lamp lights only what is near, quay lamps as glow sprites rather than lights). The time system needs nothing measured | No gain on the measured cost: the harbour at night is just as slow at 1×. Fewer visible transitions | As 2 |
| Development effort | Small to medium (lighting; nothing in the clock) | Medium: the machinery exists (sleep and dawn cards: fade, `Simulation.advance(…, stop_at_events)`, fade); needs a jump control, its rules and texts in two languages | Medium |
| Gameplay impact | None; the look must be kept (Harbor Dusk) | Loses watching the coast go by at speed and the quick 5× trim; adds a menu step | Loses 20× sailing; keeps 5× |
| Correctness risk | Low (rendering only) | Low to medium: the simulation already gives the same result for one big step as for many small ones (`test_simulation`: 1 × 15 h = 900 × 1 min; warnings at the same point at 20× and asleep). The risk is in states a jump must refuse or end: rod out, at the helm near land, a VHF call waiting, traffic close by | As 2 |
| Recommendation | **Yes**, after the Windows trial confirms the lights | No: it does not touch the measured cost | No, unless the Captain wants it for its own sake |

## E. Captain's decision

**Keep live accelerated time; do not replace the time system.** The measured
evidence puts the cost in rendering the lit night and harbour scenes, not in
running time fast, and a time-jump design would leave that cost in place at
1×. The next step is the five-minute Windows sea trial below. If it confirms
the lights, a small follow-up assignment should make the boat and harbour
lights cheaper at the same look. If the trial shows a different column high
(simulation, interface), the fix is local to that system. Time jumps stay a
sound option for later: the simulation already supports them correctly.

## F. Windows verification (one short sea trial)

1. Download the branch ZIP, open `project.godot` in Godot as usual.
2. In the FileSystem panel open `tests/one_clock_sea_trial.tscn`, press **F6**
   (Run Current Scene), and leave the computer alone for about five minutes.
3. A table appears; it is already copied to the clipboard and saved as
   `one_clock_sea_trial.txt` (its folder is shown). Paste it into the next
   message.

It uses scratch saves and settings, and does nothing in normal play. The
answer it gives: whether `harbour_night_1x` is much slower than
`harbour_night_lights_off` (lights), whether 20× rows are slower than 1× rows
(speed), and the `sim`, `theme` and `gpu` columns (which system).
