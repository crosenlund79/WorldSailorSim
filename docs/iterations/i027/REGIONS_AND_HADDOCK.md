# Between Horizons: Detailed Cruising Regions and Captain Haddock

An official development update after I027, on the playtest-fix build. It is
not a release and not I028: no passenger system was built.
`release/i027` and every tier checkpoint are unchanged.

| | |
|---|---|
| Starting point | `ef6aed4` (the I027 playtest fixes), clean tree |
| Backup | `backup/i027-before-regions-haddock` = `ef6aed4`, verified on GitHub before any edit |
| Development branch | `claude/captains-hat-visual-redesign-cgoy5o` |
| Build label | `BH · i027_04 · TEST · <commit>` (identity unchanged; version 0.113a) |
| Save format | **12, unchanged**: one optional new field, `captain_name` (default ""); no migration |
| Timing record | [regions_haddock_timing.jsonl](regions_haddock_timing.jsonl) (`tools/qa/timing_mark.sh`, `tools/qa/timing_report.py`) |
| Screenshots | [regions_haddock/](regions_haddock/) |

## Part A: Detailed Cruising Regions

Three areas of the world now have many more local destinations. "Detailed
Cruising Region" is now an official concept, defined as data:
- the regions themselves are in `data/cruising/regions.json`;
- their destinations are in `data/cruising/destinations.json`;
- the code that answers questions about them is `CruisingRegions`;
- the chart mark and info are drawn by `MapView` and `WorldMap`.

The rest of the world is presented as it was. Nothing calls any part of it
unfinished.

| Region | Title in the game | Info text (English; Danish in `locale/da.po`) |
|---|---|---|
| Denmark | Denmark — Home Waters | Discover a rich network of island harbours, sheltered passages and welcoming coastal communities. |
| Sweden | Sweden — The Archipelagos | Explore winding archipelagos, island villages and quiet anchorages along Sweden's remarkable coastline. |
| New Zealand | New Zealand — The Long White Cloud | Discover sheltered bays, remote anchorages and memorable coastal passages across New Zealand's two main islands. |

### Destinations

| Region | Before | After (harbours) | Anchorages added | Total destinations |
|---|---|---|---|---|
| Denmark | 26 harbours, 0 named anchorages | 76 (+50: 22 full-service, 22 guest harbours, 6 fishing villages) | 12 | **88** |
| Sweden | 8 harbours, 0 named anchorages | 60 (+52: 7 full-service, 23 guest harbours, 22 fishing villages) | 20 | **80** |
| New Zealand | 4 harbours, 0 named anchorages | 37 (+33: 20 full-service, 7 guest harbours, 6 fishing villages) | 15 | **52** |
| **All three** | **38** | **173** (+135) | **47** | **220** |

"Before" counts the catalogue's harbours inside each region's outline. Luleå
and Sundsvall, in the Gulf of Bothnia, are Swedish but outside the region.
The catalogue now has 374 harbours.

**Classes.**
- **Full-service harbour:** every facility and a haul-out.
- **Guest harbour and fishing village:** groceries and the shore; a boatyard
  only where the listing names repairs.
- **Natural anchorage:** a position, a description and the harbour to sail on
  to. It has no shore facilities and is never moored at. Anchoring uses the
  game's own anchoring flow (Iteration 18).

The facilities are gameplay abstractions, not claims about businesses.

**How each destination was verified.**
- **Research.** Three research passes compiled candidates from cruising
  guides and harbour listings (Danish, Swedish and New Zealand sources). Each
  row's `source` names them.
- **Limit of the research.** The research could not open Wikipedia,
  OpenStreetMap or the LINZ gazetteer directly from this environment. Its
  coordinates come from guide listings quoted in search results, cross-checked
  where two sources agreed.
- **Check against the game's charts.** Every candidate was then checked with
  `tools/qa/check_destinations.gd`:
  - a harbour needs a harbour approach from open water (the same rule as
    `test_harbours`) and a sea route to its hub;
  - an anchorage must pass the game's anchoring rule.
- **Anchorages moved.** The researched points sit in the bays themselves,
  closer to the shore than the game's 0.5 nm coastal raster allows. So 42 of
  the 47 anchorages were moved to the nearest spot the rule accepts:
  0.25–1.5 nm, 0.69 nm on average, i.e. "anchoring off" the bay. The research
  position and the offset are kept in the data (`research_position`,
  `adjusted_nm`).

**Omitted: 67 candidates**, each with its reason, in
[`tools/navigation/cruising_destinations_omitted.csv`](../../../tools/navigation/cruising_destinations_omitted.csv):
- **60 at research**:
  - 19 without a verifiable position;
  - 13 verified but redundant (within about 2 nm of a kept place);
  - the rest: private, unconfirmed anchoring, or part of an existing harbour.
- **7 at the game check**:
  - Dyvig, Ship Cove, Endeavour Inlet, Portage Bay and Deep Cove (Doubtful
    Sound): no spot within 1.5 nm the anchoring rule accepts (narrow water at
    the chart's resolution);
  - Moturua: the same spot as Otehei Bay;
  - Henån: an approach, but its fjord reaches the sea only through sounds the
    chart closes, so it has no route.

**Positions to check on a chart** (the research's own flags):
- Harbours:
  - Houhora, the weakest position;
  - Barsebäckshamn, known only to the whole minute;
  - Avernakø, Svaneke and Gedser;
  - several Swedish harbours placed at a nearby facility rather than the
    guest pontoon (Smögen, Marstrand, Käringön and others).
- Anchorages: all positions are game positions, as above.

### Charts

New detail charts, with OpenStreetMap coastlines (geo-maps earth-lands-100m,
ODbL) as for Denmark:
- **Sweden:** Bohuslän and the east coast, from Västervik to the Stockholm
  archipelago. Both are regions of Europe's chart, six times finer.
- **New Zealand:** two regions of the world chart itself, the first of their
  kind, 18 times finer than the world (216 cells per Mercator degree). They
  cover the North Island with Cook Strait, the Marlborough Sounds and Tasman
  Bay; and the South Island with Stewart Island.

The builder now refines either Europe's chart or the world chart.
`NavGrid.load_world` attaches world-level regions beside Europe. The chart
paints them over the world's own land.

Two drawing faults found while checking New Zealand by eye are fixed:
- the coarse overview layer lost the top of the South Island, so these
  regions now always draw in detail;
- a ring the renderer could not triangulate was dropped. Such rings are now
  split into quarters, which helps every region.

### On the chart

- **The mark.** Zoomed out, each region shows a quiet mark that fades out by
  60 px per degree, where its own harbours take over:
  - a small brass ring with a four-point star;
  - its name (from 8 px per degree; the whole-world view keeps to the
    symbols);
  - a dashed accent along its waters.
- **Info.** Hovering the mark shows the region's title and info text.
  Clicking it moves the chart over the region.
- **Legend.** "Detailed Cruising Region: An area with more local harbours,
  anchorages and coastal destinations to explore." It shows at the top left
  while the marks do.
- **One-time hint.** On the first chart opening of a career, the hint "Explore
  the world at your own pace. Sail between destinations across the globe, or
  discover the hidden harbours and anchorages of our Detailed Cruising
  Regions." shows. It is kept with the game's other hints in the save.
- **Named anchorages.**
  - A small anchor appears from the zoom of the smallest harbours, and its
    name from 200 px per degree where there is room, never over a harbour
    name.
  - Hovering describes the anchorage.
  - Clicking plans a course to its harbour with the anchorage as an anchoring
    stop on the way, using Iteration 18's flow.
- **Density.**
  - New harbours appear at the zoom of the smallest harbours (importance 3).
    Ten larger ones (Tauranga, Napier, Picton, Lyttelton, Gisborne, Opua,
    Helsingborg, Nexø, Vaxholm, Lysekil) appear one step earlier.
  - Labels are placed by the existing collision rules, so names never
    overlap.
  - No new global algorithm runs: the marks and anchorages are a handful of
    shapes per frame, only those in view.
- **Harbour details.** A harbour in a region adds a line with its class and
  region, for example "Guest harbour · Sweden — The Archipelagos".

### Looks

Each region gets its own waterfront palette in the town drawn beyond the quay.
The existing modular art is reused and the compact quay is unchanged:
- **Danish:** colour-washed ochre, white, pale rose and brick houses under red
  tile.
- **Swedish:** falu-red and white timber, with gable-end boathouses.
- **New Zealand:** painted weatherboard under corrugated iron, among
  pōhutukawa in crimson flower.

The new harbours take their illustration from the existing looks table:
- Danish and Swedish town harbours get the gabled waterfront;
- island, guest and fishing harbours get Nordic timber;
- New Zealand gets timber, like its older harbours.

Prices and opening hours still follow the old regional archetype, so nothing
in the economy moved. People keep their size.

### Prepared for I028 (not built)

`data/cruising/destinations.json` gives every destination:
- a stable id, its country and region;
- its coordinates and class;
- its services and overnight suitability;
- scenic tags (island, archipelago, fjord, wildlife…);
- region membership;
- a vessel note (river bars, shallow entrances, exposed coasts, remote
  Fiordland).

`CruisingRegions.destinations_in(region)` lists a region's destinations, its
older harbours included. Another region is another entry in the two files,
plus a detail chart if its coast needs one (DEV_GUIDES/CHART_REGIONS.md).

### Representative voyages (from `test_cruising_regions`)

| Voyage | Distance |
|---|---|
| South Funen Archipelago: Svendborg to Lyø | 20 nm |
| Øresund and the Baltic to Christiansø | 110 nm |
| **Stockholm archipelago: Vaxholm to Sandhamn** | 39 nm |
| **Bohuslän, inside the skerries: Marstrand to Smögen** | 47 nm |
| The Swedish east coast: Nynäshamn to Arkösund | 48 nm |
| Hauraki Gulf to the Bay of Islands (Auckland to Opua) | 125 nm |
| Across Cook Strait (Picton to Wellington) | 64 nm |
| Foveaux Strait to Stewart Island (Bluff to Oban) | 21 nm |
| Bay of Plenty to the Coromandel (Tauranga to Whitianga) | 63 nm |
| Vaxholm to Finnhamn, anchoring at Grinda Hästholmssundet | 24.0 nm |
| Svendborg to Lyø, anchoring at Lyø Anchorage | 20.4 nm |
| Paihia to Russell, anchoring at Roberton Island | 12.8 nm |
| Nelson to Port Motueka, anchoring at Torrent Bay | 33.6 nm |

Each route is checked as valid on the detailed chart.

## Part B: Captain Haddock

- **The rule.** The developer menu (F10) opens in any build, an exported
  Windows game included, when the Captain's name is exactly "Haddock",
  ignoring case and spaces around it. "Captain Haddock", "Haddock123" and
  "Haddocks" do not open it.
- **One rule.** It lives in `DevTools.is_enabled()`, alongside the editor's
  own access, which is unchanged.
- **Where the name lives.** It is the game's own Captain's name, a new
  optional field of the saved game:
  - it is given on the New Game screen ("Your name, Captain (optional)") or
    changed in the pause menu ("Captain's name");
  - it is never the vessel, the save slot or the computer's user;
  - it follows the save, so loading another game or renaming the Captain
    decides again;
  - it is never a global setting.
- **The panel.** Outside the editor it is headed "Captain's Tools", with no
  scene and no penalty. Its actions go through the game's own systems:
  weather fixtures, `GameSession`'s setters, the simulation.
- **Packaging.** An export packs `src/dev/*.gd` like any other script; the
  menu is built in code, with no scenes of its own.

### Verified in an exported build (Linux release template)

A Linux release export of this commit, made with Godot 4.7.2's official
release template (not a debug build, no editor), ran `tests/haddock_probe.tscn`.
It typed each name into the real New Game window and pressed the real F10 key.
**20 of 20 scenarios passed:**

| # | Scenario | Result |
|---|---|---|
| 1 | "Haddock" at New Game: F10 opens the tools and closes them | opens, closes |
| 2 | "haddock" and "  HADDOCK  " | open, close |
| 3 | "Captain Haddock" | does not open |
| 4 | "Haddock123" | does not open |
| 5 | "Haddocks" | does not open |
| 6 | Another name, or none | does not open |
| 7 | As Haddock, on the cabin, deck, quay and chart | opens and closes on all four |
| 8 | Save and load Haddock's game; then load another Captain's save | opens; then does not |
| 9 | Rename in the pause menu to "haddock", then to "Captain Haddock" | opens; then does not |
| 10 | The heading, a cheat (+ €1,000 through the game's money), the settings file | "Captain's Tools"; +1,000; no name in the settings |

The probe build overrides the main scene through a feature tag, because
official templates refuse a scene path on the command line. The game's own
build is exported without it. The same probe in the editor shows the editor's
access (the tools open for every name) and `test_captain_tools` (16 checks)
keeps the rule and its save round trip.

**Not verified: a Windows export.** It needs the Captain's PC (see the
checklist below).

## Tests

All runs were on Linux, in a container without a GPU.

| Check | Result |
|---|---|
| Full headless regression (96 suites, three parallel shards; shards 1 and 2 repeated on the final code) | **5,932 passed, 12 failed** in the shards. 4 then passed: the 2 pause-menu checks after their fix (209 passed, 0 failed with the related suites) and the 2 load effects run alone. **8 remain, none from this work** (below) |
| `test_cruising_regions` (new): registry, texts, membership, destinations, charts, voyages, looks, the chart's marks, hint and anchorage planning | 59 passed, 0 failed |
| `test_captain_tools` (new): the rule's truth table, the name in the save, an older save, rename | 16 passed, 0 failed |
| `test_harbours`: every new harbour has an approach and a route to its hub | 34 passed, 0 failed |
| `test_routing`: **all 46,056 European harbour pairs** and the 70 international harbours from Copenhagen | passed (the pairs took 31.8 min, up from about 12, as the European harbours grew from about 180 to about 280) |
| Exported Linux release build, `tests/haddock_probe.tscn` | **20 of 20** (twice: after the feature and after the pause-menu fix) |
| `tools/qa/check_destinations.gd` (every destination against the game's charts) | 182 of 182 |
| Content / localisation / GDScript guides / links | 0 FAIL / 3,593 messages, 0 errors / 392 scripts reviewed / 0 broken |

**The 8 regression failures, all accounted for:**
- **3 in `test_cozy_patch`** (a pet's reactions when petted): they also fail on
  the starting commit `ef6aed4`, run alone. They come from the earlier
  playtest fixes (finding 08, pet boarding), not this update, and remain open.
- **5 in `test_navigation_views`, `test_settings_and_audio` and
  `test_chart_and_pause`** (wind arrows, the wind overlay switch, audio buses):
  - they fail only when `test_route_wrap` runs before them, as it did in the
    shard;
  - the same sequence on `ef6aed4` gives the same 5 failures;
  - run alone or in the runner's normal order, they pass (159 passed, 0
    failed).

  This is an order dependence between suites, not a defect of this update.

**Found and fixed by the regression:**
- **The pause menu.** With the Captain's name row it was 18 px too tall at
  1280×720 with a 130 % interface (`test_steady_hands`). Its middle rows now
  sit in the project's `FitScroll`; at normal sizes nothing scrolls.
- **Two existing checks** counted harbours by fixed lists. Each now adds the
  cruising regions' harbours by rule:
  - the boatyard list: guest harbours and fishing villages without listed
    repairs;
  - the catalogue size: 239 plus the regions' harbours.
- **Harbour looks.** Every new harbour now has a look in the looks table.
- **Two place names.** Råå and Rörö now have their Danish catalogue entries.

**Load effects, not failures:** a frame-budget check (`test_anchorage_overlay`,
3.2 ms against 3 ms) and an audio level check (`test_soundtrack`) missed
under the three parallel shards. They pass when run alone.

**Not run:**
- the full rendered regression;
- a same-session benchmark. Nothing per frame changed except the chart's
  marks (a few shapes, only in view and only zoomed out) and the anchorage
  markers (only those in view).

## Measured time

Every mark is machine-recorded (ISO time and CLOCK_MONOTONIC, one boot), in
[regions_haddock_timing.jsonl](regions_haddock_timing.jsonl). Where two stages
were closed by one mark, the boundary between them is the commit that ended
the first (its time is in Git). Nothing is estimated.

- **Start:** 2026-10-30 07:49:01 UTC, at `ef6aed4`.
- **To the end of validation:** **141 min 20 s** (07:49:01 to 10:10:20).
  Commit and handover are the last marks in the record.

| Stage | Measured | Window |
|---|---|---|
| Preflight and backup | 0 min 18 s | 07:49:01–07:49:19 |
| Research (main thread: audit and design) | 4 min 31 s | 07:49:19–07:53:50 |
| Navigation (Swedish and New Zealand charts, world-level regions) | 17 min 15 s | 07:53:50 to commit `c0a04a9` (08:11:05) |
| Data import and regional looks (interleaved, not separable) | 9 min 50 s | 08:11:05 to commit `bbe0d9c` (08:20:55) |
| Chart presentation | 15 min 31 s | 08:20:55–08:36:26 (`170f84a`) |
| Captain Haddock (including the Linux export) | 15 min 44 s | 08:36:26–08:52:10 (`3b42e2a`) |
| Validation (regression, fixes, guides, docs, screenshots) | 78 min 10 s | 08:52:10–10:10:20 |
| Commit and handover | in the record | the last marks |

**Inside validation:**
- **Waiting on the regression:** about 40 min. The every-pair routing check
  alone took 31.8 min.
- **One lost run:** about 30 min. The third shard's process was reaped by the
  container at 08:53, unnoticed until 09:23, and was then run again.
- Other validation work went on in parallel with both.

**Parallel work** overlaps the elapsed time and is not added to it:
- three research agents for Denmark, Sweden and New Zealand: 18 min 30 s
  (07:52:34–08:11:04), alongside the navigation work;
- the Danish translation helper: 1 min 9 s;
- the GDScript guides helper: 6 min 28 s.

## The Captain's Windows checklist

1. **Export.** Export a Windows build as usual. If your preset uses "Export
   selected resources", make sure `src/dev/` is included; "Export all
   resources" includes it.
2. **New game as Haddock.** Start a new game named **Haddock**, then press
   F10 in the cabin, on deck, on the quay and on the chart: "Captain's Tools"
   opens and F10 closes it.
3. **Near misses.** Start new games named **Captain Haddock**, **Haddock123**
   and **Haddocks**: F10 does nothing.
4. **Saves.** Save as Haddock and load it: F10 works. Load an older save
   (no name): F10 does nothing. In the pause menu, type **haddock** as the
   Captain's name: F10 works.
5. **The chart, zoomed out.** Each of the three regions shows its small mark
   and name. Hovering shows the info text, and the legend sits at the top
   left. A new career shows the one-time hint once.
6. **The regional charts.** Zoom into the Stockholm archipelago, Bohuslän,
   the South Funen Archipelago, the Bay of Islands and the Marlborough Sounds.
   Look for crisp coastlines, no gaps in the land, and no names on top of
   each other.
7. **An anchorage.** Click an anchor in the Stockholm archipelago (for
   example Grinda Hästholmssundet), apply the course and sail. The boat stops
   there for the anchor, and the course continues to the harbour.
8. **The new harbours.** Moor at a few (Lyø, Vaxholm, Picton) and look at the
   waterfront: the Danish, Swedish and New Zealand palettes.
9. **Danish.** Switch to Danish and check the region texts, the legend, the
   hint and the New Game field.
10. **Performance.** Pan and zoom the chart over Denmark and New Zealand on
    the GPU, for frame time.

## Known limitations

- **Windows:** nothing here has been checked on Windows or on a GPU.
- **Research access:** coordinates were taken from guide listings quoted in
  search results. Wikipedia, OpenStreetMap and LINZ could not be opened from
  this environment. Every destination passes the game's own checks, but the
  flagged positions above deserve a look on a nautical chart.
- **Anchorages are game positions:**
  - at the chart's 0.5 nm coastal resolution, the narrowest coves cannot be
    entered, so most anchorages lie just off their bays;
  - Port Pegasus's harbour is about 35 nm away (remote, as it is).
- **The dashed region accent** follows a rough outline of the region's waters,
  not the coast.
- **The info panel** follows the mouse; it is not a native tooltip.
- **The waterfront palettes** colour the generated town beside the look's
  illustration. The quay's own storefronts are unchanged, as ordered.
