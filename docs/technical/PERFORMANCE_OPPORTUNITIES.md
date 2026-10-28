# Performance Opportunity Register

A permanent list of the game's known performance opportunities: what is slow,
how we know, what could be done, and what it would cost. It is kept current by
every iteration that measures or changes performance (see *Captain's Orders*,
working rules).

**How to read it.**
- *Verified* entries are backed by a measurement in this repository: a probe,
  a benchmark file or a report. *Hypotheses* are not.
- Frame times come from Linux software rendering (llvmpipe), which puts the
  GPU's work on the CPU. Use them to compare builds, not to judge Windows
  performance.
- Status values: suspected, measured, approved, implemented, deferred,
  rejected.

**Benchmark commands** (Godot 4.7.2; frame times rendered at 1600×900):

```
# Turbocharge / Well-Run Ship probe (sleep, dawn and dusk, chart, Long Passage,
# growth over a session; --turbo adds sleep underway, chart zoom/pan, Dream
# World, fishing, debris, and a save/load + Long Passage session):
xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver opengl3 \
  --resolution 1600x900 res://tests/benchmark_wrs.tscn -- \
  --out=/tmp/run.json --label=after --no-time-passage --turbo
# The new presentations as the Captain sees them:
#   ... res://tests/benchmark_wrs.tscn -- --out=/tmp/p.json --presented
# Quick-path correctness and cost guard (headless):
godot --headless --path . res://tests/test_runner.tscn -- --only=turbocharge
```

---

## Verified bottlenecks

### 1. Route-ahead weather scan in sleep and Long Passage

- **System:** `Simulation._assess_weather` → `_route_warning` →
  `route_hazards`; `WeatherModel.sample`; `WeatherDamage.damage_between`.
- **Inefficiency:**
  - At every 5-minute evaluation point underway, the route ahead (6 h, a
    sample every 2 nm) is scanned with full weather samples. Each full sample
    builds a `WeatherSample` object, classifies it and computes the cyclone
    risk, although only the rare hazardous samples are kept.
  - The weather damage grid uses full samples for speed and gust only.
- **Evidence:** Turbocharge profile (`tests/scratch` probe, headless).
  - One scan costs 1.18–1.31 ms; one full sample 0.051 ms; damage per point
    0.23–0.26 ms.
  - An 8-hour sleep underway costs 120–200 ms in one call.
  - Long Passage costs about 9 ms of simulation per frame at 12 h/s.
- **Improvement:** `WeatherModel.sample_hazard()`, the same wind, gust and
  hazard code without the object, classification or cyclone risk. The scan
  and the damage grid use it, and ask `sample()` only for the hazardous
  samples they keep. Results are bit-identical (64-bit floats; tested against
  the previous implementation).
- **Assessment:** confidence high; effort small; risk low (identity test
  `test_turbocharge`). Benefit-to-cost: good.
- **Status:** implemented (Turbocharge; commit in
  `TURBOCHARGE_PERFORMANCE_REPORT.md`). Measured benefit, two runs each on
  software rendering:
  - an 8-hour sleep underway: 78–93 ms → 56–61 ms per call (about −30 %);
  - Long Passage simulation at 12 h/s: 8.3–9.1 ms → 5.8–6.3 ms per frame
    (about −30 %);
  - one route scan: about 20–25 % less; one quick sample costs 0.033 ms
    against 0.044 ms.
- **Next action:** none. See #6 for a larger follow-up.

### 2. Interface recolouring at dawn and dusk

- **System:** `UiTheme.set_blend`.
- **Inefficiency (before):** about 280 separate theme change notifications per
  step, each refreshing every control: 0.7 s on deck and 2.3 s at the chart.
- **Improvement:** blocked signals and one `changed` per step.
- **Status:** implemented (The Well-Run Ship, `7862607`). Measured benefit:
  0.7 s → 4 ms and 2.3 s → 11 ms per step. Guarded by `test_well_run_ship`
  `[theme]`.
- **Steady Hands (readability, also fewer steps):** the interface no longer
  follows the twilight blend (which parked it half-way, with text and panel
  the same grey, for the whole twilight, stepping whenever the blend moved
  by `MIN_STEP` 0.02). It now switches once at the middle of the twilight and
  eases over `MAX_RATE` as before: at most 1 / (0.25 × 0.25 s) = 16 steps per
  dusk or dawn, instead of up to 50 spread over the twilight. Step cost
  unchanged. Guarded by `test_steady_hands` `[dusk]`.

### 3. Chart zoom and pan: wind arrows rebuilt on every view change

- **System:** `MapView._process` → `WindLayer.refresh_view`.
- **Inefficiency:** every frame the view changes, the wind arrows are rebuilt
  for the new view.
- **Evidence (Turbocharge, headless):**
  - Zoom frames cost 13.9 ms, against 8.3 ms with the wind layer hidden and
    6.7 ms idle.
  - Pan frames cost 11–20 ms (noisy).
- **Improvement:** refresh the arrows when the view settles (for example
  0.1 s after the last change), or reuse them while panning by shifting them.
- **Expected gain:** about 5 ms of CPU per frame while the chart moves; none
  at rest.
- **Assessment:** confidence medium; effort small–medium; risk low–medium
  (the arrows would lag briefly; `test_wind_overlay` checks redraws).
  Benefit-to-cost: moderate.
- **Status:** measured, deferred: the Captain has not reported chart jank
  since the theme fix.
- **Next action:** measure on Windows; do it if panning feels heavy there.

### 4. Opening the chart builds about 7,560 land nodes each time

- **System:** `MapView` (world land as three copies of 1,199 tile nodes for
  the Date Line wrap, plus the Europe and Denmark polygons).
- **Evidence:**
  - Opening takes about 65 ms (software rendering, 12 opens).
  - At rest the nodes cost nothing measurable: idle chart frames equal idle
    cabin frames, 6.7 ms headless.
  - They were the reason the old theme stall was four times worse at the
    chart.
- **Improvement:** keep the land layer alive between opens, or draw each world
  copy as a few batched canvas items instead of 1,199 nodes.
- **Expected gain:** a faster open (tens of ms); fewer nodes for any future
  whole-tree work.
- **Assessment:** confidence medium; effort medium–large (a land rendering
  rework); risk medium (LOD, regions, the Dream World tint, picking).
  Benefit-to-cost: low at present.
- **Status:** measured, deferred.
- **Next action:** reconsider if the chart's opening is reported as slow on
  Windows.

### 5. Night 2D lights under software rendering

- **System:** `BoatLighting` (point lights and shadows).
- **Evidence:** night deck frames take about 120 ms against about 55 ms by
  day on llvmpipe. Hiding the lighting saves about 38 ms. The cost is the
  same with time stopped, so it is rendering, not script.
- **Improvement:** only if Windows shows a real cost. Fewer shadow-casting
  lights, or baked shading for static fixtures, at the same look.
- **Assessment:** confidence low that it matters on a GPU.
- **Status:** measured (software only), deferred.
- **Next action:** measure on Windows first. Harbor Dusk's lighting is not
  compromised for software-rendering numbers.
- **Operation One Clock (2026-10-27):** the same cost is now the leading
  explanation of the Captain's slowdown above 1×. Harbour at night: 130–135 ms
  with the lights, 57 ms with them hidden (render time 124 → 52 ms); open
  water at night 64–69 ms against 37 ms by day; all equal at 1×, 5× and 20×.
  In harbour the lights fall on about 775 draw calls (about 250 at sea).
  Status: measured (software only); **next action:** the Windows sea trial
  (`tests/one_clock_sea_trial.tscn`, F6). If it confirms, a lighting
  follow-up: light range and item masks, quay lamps as glow sprites, at the
  same look. See `ONE_CLOCK_PERFORMANCE_INVESTIGATION.md`.

### 9. Traffic queries on the evaluation grid (I019)

- **System:** `TrafficModel.vessels_near` (`_cell_tracks`), called by
  `Simulation._assess_traffic` at every 5-minute evaluation point underway
  and by the radar five times a second.
- **Inefficiency:** a query visits about 45 (cell, window) pairs; a new cell
  generates up to 8 tracks, each checked on water at several points.
- **Evidence:** headless probe (`tests/scratch/probe_sleep_traffic.gd`,
  not committed): an 8-hour sleep underway (Copenhagen to Reykjavik) costs
  about 115–150 ms with traffic off and about 150–215 ms with it on before
  tuning; a cold query 18 ms, a warm one 0.31 ms. After a flat pre-check per
  track and 4 instead of 8 water checks each way: cold 8 ms, warm 0.19 ms,
  sleep about +25–30 % instead of +45 %. Rendered `--turbo` probe
  (`docs/benchmarks/i019_after1_rendered.json`, before this tuning): sleep
  8 h underway 48–106 ms against 56–58 ms for Turbocharge; every frame-time
  scenario equal or a little lower.
- **Proposed improvement:** keep the last query's candidate tracks and
  only re-collect when the boat or the 3-hour window moves on (the query
  position moves about 0.5 nm per evaluation point).
- **Expected benefit:** most of the remaining traffic cost in sleep and Long
  Passage (tens of ms per 8 h). **Confidence:** medium. **Effort:** small.
  **Regression risk:** low (pure function; compare with the uncached query).
- **Status:** measured; first step implemented (I019, pre-check and fewer
  water checks); candidate cache deferred.
- **Next action:** implement the candidate cache if Long Passage or sleep
  feels slower on Windows.

## Measured and rejected (no worthwhile gain)

| System | Evidence | Why rejected |
|---|---|---|
| Per-frame HUD text refreshes (`Hud`, `SailingPanel`, `PassagePanel`, badges) | Every script's `_process` timed headless: 0.09–0.63 ms per frame in total for all scripts, the largest 0.18 ms (`SailingPanel`) | Not a bottleneck: throttling would save at most 0.3 ms |
| Floating sea debris (Injection 1) | A fixed pool of 16, no per-frame allocation; sailing frame times unchanged (34 → 33 ms median) | Not a cause |
| Long-session growth (nodes, connections, orphans, audio players, tweens, caches, memory) | Flat across 20 rounds (The Well-Run Ship) and 10 rounds with save/load and Long Passage (Turbocharge) | No leak shown. This does not prove none can exist: keep the growth rows in the probe |
| Weather, router, daydream and spot caches | All bounded (`MAX_CACHE`, `LEG_CACHE_LIMIT`, 64-entry limits) | No unbounded growth |
| I020 trade panels and cabin things | No per-frame work (panels built on open, freed on close; cabin things drawn once, redrawn on change); `--turbo` probe equal to I019 re-run in the same session (`docs/benchmarks/i019_rerun_rendered.json`, `i020_after1_rendered.json`) | Nothing to gain. Note for future comparisons: this machine drifted 3–10 % between runs hours apart; compare against a baseline re-run in the same session |
| I021 harbour looks, special stars, arrival card | One shared texture per look, loaded on first use and cached (`HarbourLooks`); the chart star is one dictionary lookup per drawn pin; the card is a short-lived toast. `--turbo` probe before and after in the same session (`docs/benchmarks/i021_before_rendered.json`, `i021_after_rendered.json`): equal or faster in every scenario (drift), memory +0.1 MB; repeated moorings keep the node count steady | Nothing to gain |
| Time acceleration itself (1×, 5×, 20×) and the dawn/dusk machinery (Operation One Clock) | Per frame at any speed: simulation 0.2–0.8 ms (worst 9.7 ms, at most one evaluation point), interface recolouring 4–7.5 ms per step on deck and 20–24 ms at the chart (one step per twilight with the date card, at most four a second without), boat light script 0.1 ms, dawn/dusk watch ≤ 0.02 ms; 60 game hours at 20× with no growth (578 nodes) | Not the bottleneck: frame time follows the lit scene (#5), not the speed |
| Golden Harbour Moments (Steady Hands & Golden Harbours) | The card is drawn once when shown (no per-frame redraw); the painting's window spots are found once per picture and cached: 18 ms for four pictures the first time, 0.01 ms after (headless, `test_golden_harbours` `[performance]`); one card per first visit, gone after 14 s | Nothing to gain |
| Disk writes during play | No autosave; one flushed log line per meaningful event; logs capped | Not a responsiveness factor |

## Hypotheses and larger rework candidates (not yet measured or approved)

### 6. Incremental route-hazard forecasts (larger rework)

- **What it would change:** consecutive evaluation points scan almost the
  same stretch of route. A forecast kept per route revision and updated
  incrementally (dropping what was passed, adding the new end) could cut
  sleep and Long Passage weather work several-fold more.
- **Risk:** high for correctness. Warnings must stay identical however time
  is chopped, and the forecast's sample times depend on the start of each
  scan. Not approved.
- **Status:** suspected.
- **Next action:** only if #1's result is not enough.

### 7. Simulation step batching for very fast Long Passage

- Batching a whole frame's chunks before redrawing is already the design: the
  voyage map redraws 12 times a second and the simulation runs per frame.
- **Status:** suspected, low value after #1.

### 8. Chart label rendering

- **What it would change:** labels and markers drawn in one overlay instead of
  separate controls.
- **Status:** suspected. The overlay already draws most of them, and the node
  count is land tiles, not labels.
- **Next action:** do not pursue unless measured.
