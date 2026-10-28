# I021 — A Wider, Warmer World (0.108a)

Content expansion, distinctive harbours and illustrated arrivals. Version
**0.108a**, save format **12 (unchanged)**. More world, not more complexity:
everything new is data and art in systems that already existed (the harbour
catalogue, the harbour art beyond the quay, the chart's pins, the fishing
catalogue, the cabin things), plus one small new class (`HarbourLooks`) and one
new kind of notice (the arrival card). **Windows was not tested**; everything
below was run on Linux (Godot 4.7.2).

## 1. Commits

| | Commit |
|---|---|
| Starting point (Engine Room complete) | `ec84cfa466defea556c64bf3335c9c659f35eaea` |
| Harbour data | `91934a4` |
| Harbour art, look selection, arrival card | `bd88d5a` |
| Special harbours on the chart | `6d6bf66` |
| Fish and their art | `1864d62` |
| Cabin things | `631c234` |
| Tests, version, guides, documentation, screenshots | `cc70f75` |
| Test and benchmark results (this report's final version) | the branch head after `cc70f75` |

The final I021 commit is `04a76231581f5a6d0af22ce2c2c138842b869453`. It is kept
on the recovery branch `release/i021`, created afterwards under the Captain's
major iteration branch policy (`CAPTAINS_ORDERS.md`) and verified on GitHub.

## 2. The checkpoint before I021

- **Backup branch:** `backup/post-engine-room-pre-i021` at
  `ec84cfa466defea556c64bf3335c9c659f35eaea`, the remotely verified head of the
  completed Engine Room assignment, created before the first I021 change.
- **Verified remotely** twice: with `git ls-remote` and through the GitHub API
  (branch list), both reporting that exact SHA. It contains no I021 change (it is
  the Engine Room head itself).
- **Tag** `checkpoint/post-engine-room-pre-i021`: created locally (annotated); the
  push was rejected by the environment's git proxy, as for the earlier
  checkpoint tags. The branch is the recovery point.
- `backup/post-turbocharge-pre-i019` (`5b6474a`) and `backup/post-i019-pre-i020`
  (`ba0cacf`) were not touched. No force-push, no history rewritten.

## 3. New harbours (16; 239 in all)

Chosen to fill gaps along real cruising routes. Positions: GeoNames (CC BY 4.0;
the town's point, to four decimals), cross-checked against the UN/LOCODE entry
where it has a coordinate; recorded per harbour in `tools/navigation/harbours.csv`
(`source`). Essaouira's UN/LOCODE point lies 25 km inland, so GeoNames is used
throughout. Every one has a harbour approach to open water on the chart and a
valid sea route to its nearest original harbour (`test_harbours`). Facility
tiers follow I016's: small (groceries, Go Ashore), larger (+ boatyard), major
(+ haul-out). Tool: `tools/navigation/add_i021_harbours.py`.

| Harbour | Country | Lat, lon | Sea area | Tier | Look |
|---|---|---|---|---|---|
| Dingle | Ireland | 52.1408, -10.2689 | british_isles | small | Stone harbour of the Atlantic coast |
| Stornoway | United Kingdom | 58.2093, -6.3865 | british_isles | larger | Stone harbour of the Atlantic coast |
| Ísafjörður | Iceland | 66.0748, -23.1350 | north_atlantic | small | Nordic timber harbour |
| Lunenburg | Canada | 44.3785, -64.3166 | north_america | larger | Nordic timber harbour (special) |
| St. John's | Canada | 47.5649, -52.7093 | north_america | larger | Nordic timber harbour |
| Valletta | Malta | 35.8997, 14.5148 | mediterranean | major | Mediterranean harbour town (special) |
| Symi | Greece | 36.6155, 27.8362 | aegean | small | Aegean island harbour (special) |
| Essaouira | Morocco | 31.5125, -9.7700 | west_africa | small | Stone town harbour (special) |
| Dakar | Senegal | 14.6937, -17.4441 | west_africa | larger | Tropical harbour town |
| Jamestown (St Helena) | Saint Helena | -15.9249, -5.7182 | south_atlantic | small | Volcanic island harbour (special) |
| Cape Town | South Africa | -33.9258, 18.4232 | south_atlantic | major | Gabled harbour town |
| Zanzibar | Tanzania | -6.1639, 39.1979 | indian_ocean | larger | Stone town harbour |
| Port Louis | Mauritius | -20.1619, 57.4989 | indian_ocean | larger | Tropical harbour town |
| Galle | Sri Lanka | 6.0461, 80.2103 | indian_ocean | larger | Tropical harbour town |
| Langkawi (Kuah) | Malaysia | 6.3265, 99.8432 | southeast_asia | larger | Tropical harbour town |
| Hobart | Australia | -42.8794, 147.3294 | pacific | larger | Stone harbour of the Atlantic coast |

**Tried and left out:** Picton (New Zealand), at the head of Queen Charlotte
Sound: more than the approach limit from water on the coarse world chart (like
Opua in I016); recorded in `harbours_rejected.csv`.

Each has one plain sentence about the place as a sailor finds it ("Valletta,
Malta, where honey-coloured bastions rise straight out of the water of Grand
Harbour."), shown in the chart's details and on the arrival card, in English
and Danish. Five new sea areas: north_america, west_africa, south_atlantic,
indian_ocean, southeast_asia. Ids are new; no existing harbour changed.

## 4. New fish (10; 26 in all)

Real fish in the regions where they really live (game values for size and
price, within the old catch's range). Existing fish were added to the new sea
areas where they live too (cod, herring, mackerel and flounder off Atlantic
Canada; mahi-mahi, skipjack and yellowfin in the Indian Ocean, Southeast Asia,
West Africa and the South Atlantic; and so on).

| Fish (Dansk) | Rarity | Size | Price | Where |
|---|---|---|---|---|
| Pollack (Lubbe) | uncommon | 0.5–6 kg | €7/kg | North Sea, Scandinavia, British Isles, Channel, Biscay, North Atlantic |
| Atlantic halibut (Helleflynder) | very rare | 5–60 kg | €16/kg | North Atlantic, Scandinavia, North America |
| Striped red mullet (Stribet mulle) | common | 0.1–0.6 kg | €14/kg | Mediterranean seas, Iberia, Biscay, Channel, West Africa (coastal) |
| Common dentex (Tandbrasen) | rare | 1–10 kg | €15/kg | Mediterranean seas, Iberia, West Africa |
| Bluefish (Blåfisk) | uncommon | 0.5–6 kg | €6/kg | Mediterranean, Aegean, Levant, Iberia, West Africa, South Atlantic, North America |
| Striped bass (Stribet bars) | rare | 1–15 kg | €9/kg | North America (coastal) |
| Giant trevally (Kæmpehestemakrel) | rare | 5–40 kg | €5/kg | Indian Ocean, Southeast Asia, Pacific (coastal) |
| Wahoo (Wahoo) | rare | 6–35 kg | €13/kg | Tropical and subtropical open ocean |
| Narrow-barred Spanish mackerel (Smalstribet kongemakrel) | uncommon | 2–20 kg | €12/kg | Indian Ocean, Southeast Asia |
| Dusky grouper (Brun havaborre) | rare | 2–20 kg | €15/kg | Mediterranean seas, Iberia, West Africa, South Atlantic (coastal) |

Painted by `tools/fishing/paint_fish.py` from their own features (the pollack's
arched lateral line and jutting jaw, the halibut's long flat body, the mullet's
barbels and yellow stripes, the dentex's blue spots, the striped bass's lines,
the wahoo's bars, the grouper's pale blotches), with the blink and tail flick
of every fish. No two species share a silhouette (the closest pair is still the
existing bonito and skipjack). Records, trophies and the fishmonger use them
like any fish; a record of a new fish saves and loads.

## 5. Harbour looks and where they are used

Nine looks, each one original illustration in the Nyhavn strip's hand-drawn
style, chosen per harbour by what the place looks like. The full mapping
(every harbour) is in [HARBOUR_LOOKS.md](HARBOUR_LOOKS.md), generated from
`data/harbours/harbour_looks.json`.

| Look | Harbours | Examples |
|---|---|---|
| Nordic timber harbour | 36 | Norway, the Faroes, Iceland, timber towns of Sweden and Finland, small Danish fishing harbours (Gilleleje, Lohals, Rødvig), Lunenburg, St. John's, **New Zealand** |
| Gabled harbour town | 45 | Danish and German harbour towns, the Hanseatic Baltic, the Low Countries, **Willemstad**, **Cape Town** |
| Stone harbour of the Atlantic coast | 33 | Scotland, Ireland, Wales, Brittany, Normandy, Galicia, the Channel Islands, Helsinki, **Hobart** |
| Mediterranean harbour town | 81 | Italy, southern France and the French Atlantic's limestone towns, Spain, Portugal, Croatia, mainland Greece, Türkiye, Cyprus, Valletta |
| Aegean island harbour | 7 | Mykonos, Paros, Naxos, Santorini, Skiathos, Hydra, Symi |
| Stone town harbour | 2 | Essaouira, Zanzibar |
| Tropical harbour town | 20 | The Caribbean, Dakar, Mindelo, Panama, Port Louis, Galle, Langkawi, Papeete, Suva, Honolulu |
| Tropical island harbour | 6 | Bora Bora, Raiatea, Fakarava, Avarua, Nuku'alofa, Bequia |
| Volcanic island harbour | 9 | The Azores, Funchal, Lanzarote, the Galápagos, the Marquesas, Pago Pago, St Helena |

Not by continent: New Zealand looks like Norway, Willemstad and Cape Town have
gables, Hobart's sandstone docks look like Aberdeen, Dakar does not look like
Morocco, and six European harbours (Copenhagen, Bergen, Oban, Naples, Mykonos,
Horta) have six different looks (all checked by `test_wider_world`).

**How it is shown.** Moored, the deck shows the harbour's illustration beyond
the quay (where Copenhagen's Nyhavn always was), in both light themes and under
the game's own day and night lighting. On arrival a small **arrival card**
appears in the notices' corner: a picture of the harbour (the middle of its
illustration), "Arrived in …" and the harbour's sentence. It never blocks
(clicks pass through) and fades after six seconds. Nothing else in the mooring
flow changed. A harbour whose picture is missing shows the plain quay.

**Art and its limits.** The illustrations are drawn by
`tools/harbours/paint_harbour_looks.py` (original, deterministic; no traced or
copied source). They follow the existing Nyhavn strip closely: flat colours,
a wobbly ink outline, facades facing the water with their roofs or the land
behind. That is the established standard, and a modest one. They are not
painterly scenes. See [the contact sheet](../../screenshots/i021/harbour_illustrations.png).

## 6. Special harbours

| Harbour | Its own illustration | Why (shown on the chart) |
|---|---|---|
| Copenhagen | Nyhavn (Visual Identity V01) | an illustrated arrival at Nyhavn's painted harbour houses |
| Valletta | Grand Harbour bastions: the limestone wall with angled bastions and a sentry box, the city's flat roofs and coloured balconies, the Carmelite dome | an illustrated arrival beneath the bastions of Grand Harbour |
| Symi | Gialos: tiers of pastel neoclassical houses with pediments, the clock tower | an illustrated arrival among the tiers of neoclassical houses at Gialos |
| Essaouira | The Skala: the sea bastion with its embrasures and cannon, the north tower, the white medina behind | an illustrated arrival below the Skala, the old sea bastion |
| Lunenburg | The red waterfront buildings, and the painted houses on the hill | an illustrated arrival at the red waterfront of the old fishing town |
| St Helena | Jamestown: one street of Georgian houses in a valley between dark cliffs, Jacob's Ladder | an illustrated arrival in Jamestown's valley between the cliffs |

A harbour is special only because it has its own illustration: the `special`
list in `harbour_looks.json` must equal the harbours with their own art (tested).
New harbours are not special by default (Dingle, Zanzibar and the rest are
ordinary). On the chart a special harbour's pin carries a **small brass compass
star** on its upper-left shoulder, outside the selection ring and clear of the
label and of the Dreamer's Map's red visited pins; it is drawn with the pin, so
clustering, zoom levels and visited state are unchanged and there is no new
per-frame work. The harbour's details add one line: "Special harbour: an
illustrated arrival beneath the bastions of Grand Harbour" (Danish: "Særlig
havn: …").

## 7. Screenshots

In [`docs/screenshots/i021/`](../../screenshots/i021/):

- every look, moored at a harbour of that look: `deck_nordic_timber_svolvaer`,
  `deck_gabled_waterfront_marstal`, `deck_atlantic_stone_dingle`,
  `deck_mediterranean_naples`, `deck_aegean_island_mykonos`,
  `deck_stone_town_zanzibar`, `deck_tropical_town_dakar`,
  `deck_tropical_island_bora_bora`, `deck_volcanic_island_horta`;
- every special harbour: `deck_special_copenhagen`, `…_valletta`, `…_symi`,
  `…_essaouira`, `…_lunenburg`, `…_st_helena`;
- `harbour_illustrations.png`: all fifteen illustrations on one sheet;
- the arrival card: `arrival_card_valletta`, `arrival_card_zanzibar_da` (Danish);
- the special star on the chart by day (Vintage Chartroom) and by night (Harbor
  Dusk): `chart_special_valletta_day/night`, `chart_special_symi_day/night`;
  and on the Dreamer's Map with its red visited pin: `dream_map_specials`.

Note: on the deck the illustration sits at the bottom edge of the screen (as
Nyhavn always has), so only its top band shows while walking the deck; the
arrival card and the screenshots' contact sheet show it whole.

## 8. Cabin things (3)

A **model ship** (€70), a **jar of sea glass** (€20) and a **brass barometer**
(€65), sold at the chandlery and shown or put away per boat with "Make it home",
drawn in the cabin's own manner and placed by I020's rules (clear of every
station, berth and the companion's spots). With these, nine things in all: the
two of the cabins (Arctic Wanderer 26 and Clam 40) have room for eight at
once, as I020's rule allows (all but one); the Wing 33 and Frogleap 36 show all
nine (measured: 8, 9, 9, 8 of 9). **Two more, patterned cushions and a
folded wool blanket, were drawn and then left out**: with eleven things those
two cabins would have shown only eight of them, and the "Make it home" menu has no
way yet to say "no room aboard". Saves are unaffected (owned things are ids;
new ones start unowned).

## 9. Additional boats: deferred

Not safely possible as content in this iteration. Each of the four boats is
four scenes (deck, cabin and their illustrated visuals), twelve illustrated art
layers painted from those scenes, a performance profile, a cabin layout that
must provide every station, the six companion spots, the hat hook, cup holders,
decor placement and walkable outline, plus mooring, sail and boatyard data. 25
test suites name the four boats. A fifth boat is a new set of all of these and
the art, not a data row; a half-made boat would be selectable but not fully
usable. Recommended as its own assignment, with the art first.

## 10. Parrot and hamster: feasibility

Deferred, for these concrete reasons:

- **Kinds and places.** `CompanionState.KINDS` is cat and dog; each kind has
  resting spots that every cabin and deck provides by name
  (`ALL_SPOT_IDS`). A parrot needs perches (a rail, the companionway, a
  shoulder) and a hamster a cage that is itself a cabin fixture on all four
  boats. Neither fits the walk-to-a-spot model.
- **Movement.** `ShipCompanion` walks paths on deck (`DeckCompanionSpots`) and
  follows the captain up and down; a parrot would fly or ride along, and a
  hamster should never be on deck. These are new behaviours, not new art.
- **Art and sound.** Each kind is four painted poses (resting, sleeping,
  alert, stretching) and a sound; a parrot would also need flight frames.
- **Name and gender.** The game still has no name or gender for the companion
  (the Engine Room's petting lines are ready to use them if they are added);
  the brief's "custom name, male/female/other" would be a New Game change.

A sensible order, if the Captain wants them: first the companion's name and
gender in the New Game menu (small, and every animal benefits), then the
parrot with a perch model, then the hamster with a cage fixture.

## 11. Saves and languages

- Save format 12, unchanged. Nothing new is saved: the looks and specials are
  data; new fish and things appear as ids only when caught or bought. An old
  save loads unchanged, a save made in one of the new harbours loads there, and
  a new fish's record round-trips (`test_wider_world`).
- Every new text is in `locale/da.po`: harbour names (context "place";
  Cape Town is "Kapstaden"), the 16 descriptions, the look names, the special
  notes and "Særlig havn: %s", the fish names, the three things and their
  descriptions, and the landmark titles. `tools/i18n/check.py`: 2,373
  messages, all translated, 0 errors.
- The chart's harbour sentence was shown untranslated before (it used the raw
  field); it now follows the language everywhere (`PortData.get_description()`).
- **Danish names to confirm.** "Kæmpehestemakrel" (giant trevally),
  "Smalstribet kongemakrel" (narrow-barred Spanish mackerel) and "Brun
  havaborre" (dusky grouper) are reasonable renderings, but common Danish usage
  could not be confirmed here. Candidates for the glossary.

## 12. Tests

- **Full regression** on the final code: all **74 suites, 4,762 checks passed,
  0 failed** (headless Linux, Godot 4.7.2).
- **New suite `test_wider_world`: 46 checks**, all passing: the 16 harbours
  (catalogue, sentence, source, groceries, tiers, Danish), every harbour's look
  and its image, looks by place not continent, a look's art shared, the six
  special harbours equal to those with their own art, ordinary harbours staying
  ordinary, the "why" in both languages, a missing picture showing the plain
  quay, the 10 fish (art, real regions, caught where they live and not in the
  Baltic, prices, Danish names, a record saved and loaded), the cabin things,
  an old save and a save in Zanzibar, eight moorings in a row with the node
  count steady (443–444), Suva and Nuku'alofa on both sides of the date line,
  the arrival card (picture, words, never blocking, Danish), and a route across
  the date line.
- **Updated existing checks** where I021 changed the expected result, never to
  hide a fault: Kiel now shows its look (`test_visual_prototype`), the small new
  harbours have no boatyard (`test_harbour_life`), five new sea areas
  (`test_harbours`), the trades' Danish fit check treats a row scrolled out of
  view as scrolled (`test_boat_of_your_own`), version 0.108a (`test_branding`,
  `test_diagnostics`).
- **Found and fixed by the tests during the work:** the halibut, the pollack and
  the striped bass were first drawn too like the flounder, the cod and the sea
  bass (silhouette check); five new cabin things did not fit the two tightest
  cabins (reduced to three).
- **Checked against the starting commit** (a worktree at `ec84cfa`): two checks
  that failed once in a busy, larger run (wind arrows on the chart, "Continue is
  disabled") pass on both the starting build and the final build when run alike;
  they were load and order effects of that run, not I021 changes.
- Tools: `check_gdscript_guides.py` passes (281 scripts), `check_links.py`
  passes, `tools/i18n/check.py` passes (2,373 messages, all translated).
- Earlier in the same session, the Engine Room's 25 repeated runs of the
  fish-blink and companion-walk suites all passed.

## 13. Performance

Same machine, same session, rendered (llvmpipe, 1600 × 900), the `--turbo`
probe of `benchmark_wrs`: `docs/benchmarks/i021_before_rendered.json` (the
starting build, measured before any I021 change) and `i021_after_rendered.json`
(the final build). Frame times in ms:

| Scenario | before median | after median | before p95 | after p95 |
|---|---|---|---|---|
| chart_open_close_x12 | 76.6 | 70.5 | 90.1 | 91.2 |
| chart_open_idle | 56.4 | 52.5 | 69.3 | 64.9 |
| turbo_chart_zoom_pan | 69.0 | 62.0 | 89.2 | 82.8 |
| turbo_dream_map_idle | 116.8 | 99.9 | 132.0 | 116.4 |
| walk_deck_harbour_day | 65.8 | 55.3 | 79.3 | 66.2 |
| harbour_night_still | 64.2 | 53.4 | 75.9 | 61.9 |
| walk_cabin_day | 79.2 | 67.1 | 91.8 | 79.9 |
| turbo_fishing_rod | 75.0 | 66.3 | 88.0 | 78.3 |
| sailing_1x | 42.0 | 38.9 | 49.6 | 45.9 |
| long_passage_12h_per_s | 71.8 | 65.8 | 84.7 | 82.7 |
| sleep_4h_across_sunrise | 78.0 | 75.0 | 94.7 | 96.1 |
| daynight_harbour_walk_20x | 72.3 | 62.1 | 164.7 | 141.7 |

Everything is equal or faster after I021, which the work cannot explain (no
I021 change touches chart drawing or deck frames beyond one dictionary lookup
per drawn pin): this machine drifts 3–10 % between runs (see the Performance
Opportunity Register), so the honest reading is **no measurable regression**.
Memory at the end of a 20-round session: 234.9 MB vs 234.8 MB, 3,022 vs 3,002
objects, nodes equal. The harbour art is one shared texture per look, loaded on
first use and kept (at most nine looks plus six special views); mooring eight
times in a row leaves the node count steady (`test_wider_world`). Nothing new
runs per frame. No optimisation was needed or attempted.

## 14. Known limitations and deferred content

- **Windows was not tested.** The Captain's Windows trial is pending (checklist:
  [WINDOWS_ACCEPTANCE_21.md](WINDOWS_ACCEPTANCE_21.md)).
- The harbour illustrations are in the simple style of the existing Nyhavn
  strip; a richer painted set would be a job for the Sprite Workshop
  (`art_replacements/08_harbours_and_towns`), and the look table already maps
  every harbour to one image per look.
- On the deck the illustration is at the screen's bottom edge, so only its top
  band shows; the arrival card shows it whole.
- Hobart is in the chart's broad "pacific" sea area, like New Zealand's
  harbours, so it shares their fish (including tropical ones); sea areas are
  the fishing model's coarse regions.
- Two cabin things (cushions, a blanket) deferred until "Make it home" can
  say when there is no room aboard.
- Additional boats and the parrot and hamster: deferred (sections 9 and 10).
- No second UI overhaul; broader UI ideas were not pursued.
