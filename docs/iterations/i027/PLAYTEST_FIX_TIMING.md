# I027 playtest fixes: the 17 findings, and how long they took

An official development update after the Captain's Windows playtest of
`release/i027`. It is not a release branch: `release/i027` and every tier
checkpoint are unchanged.

| | |
|---|---|
| Starting point | `8a24d0f` (`release/i027`), branch `iteration/i027`, clean tree |
| Backup | `backup/i027-before-playtest-fixes` = `8a24d0f`, verified on GitHub before any edit |
| Development branch | `claude/captains-hat-visual-redesign-cgoy5o` |
| Build label | `BH · i027_04 · TEST · <commit>` (unchanged identity; version 0.113a, save format 12) |
| Timing record | [playtest_fix_timing.jsonl](playtest_fix_timing.jsonl), written by `tools/qa/timing_mark.sh`; summarised by `tools/qa/timing_report.py` |

## The 17 findings

All 17 are **completed**. None is partial or blocked.

| # | Finding | What changed |
|---|---|---|
| 01 | Physical way to the quay | Walking into the walkway's passage at the back of the pontoon takes the Captain up to the quay, with no key and no question. Two painted chevrons on the planks show the way. Walking down the quay's walkway returns aboard as before. Both passages wait until the movement keys have been let go after arriving, so holding a key never bounces the Captain back. E at the sign still works |
| 02 | A more compact quay | Copenhagen's quay is **35 m** (it was 58 m; 87 m in I026). The walk from the walkway to the boatyard takes **5.0 s** (it was 7.3 s). Frontages are about a third narrower, gaps are small, there are no decorative end houses, and the promenade is half a metre shallower. People, doors, the walkway and the pump keep their true size. Each business keeps its own front and sign. Access was checked by the suite, and the townsfolk routines are unchanged |
| 03 | The quay's action wheel | Q lists every place on the quay: each business, marked "(closed)" when it is shut, plus the noticeboard, the fuel berth and the lane into town. Choosing one walks the Captain there along the open walking lane and uses it on arrival. A closed shop offers to wait until it opens. A movement key stops the walk. There is no pathfinding system: the route is the lane, plus a step round the noticeboard or the terrace |
| 04 | Shift runs | Running is 1.75 × walking speed, with no stamina. The stride lengthens (×1.3), so the step rate rises less than the speed. The key bar shows "Shift run" |
| 05 | Cockpit benches | The benches' collision is 40 % shallower and 15 % shorter, keeping their outboard and aft edges, on all four boats. The art is unchanged |
| 06 | Cockpit instruments | On the monohulls, the instrument displays moved from the companionway to the starboard coaming behind the bench, by the helm. The catamaran's helm layout is unchanged |
| 07 | Reaching the equipment | The tiller boat's plotter moved to the port coaming. The plotter and the instruments each have a place to stand on the cockpit floor ("Use the chartplotter", "Read the instruments"). Neither overlaps "Go below" any more, and they compete on plain distance, so the nearest thing gets E. Checked on the 26 ft and the Wing 33 |
| 08 | Pet boarding | The dock animal following the Captain aims for the deck once the Captain is aboard, so it comes up the gangplank instead of waiting below it. Before the companionway question it is brought to the Captain's side, so a welcomed animal is really aboard. The question, "Not now" and the girl's farewell are unchanged |
| 09 | The fishing rod | Redrawn in the illustrated style: a tapered blank with a highlight and guides, a cork grip, a spinning reel seen from above, and a stainless holder, with light ink. The tip and its nod are unchanged |
| 10 | The trophy board | **It would not open:** a lower focus priority let the keepsakes further along take E. It now competes on plain distance. Each plaque says "In the cool box now" or "On record: sold or eaten since". The board already kept sold and eaten catches across save and load, without duplicates |
| 11 | Fishing filters | A fish the keep preferences would put back, on rarity **or** size grade, no longer starts the reel-in at any time speed; it nibbles and swims off. Before, this applied only in fast time and only to rarity. With the default (keep everything) nothing changes |
| 12 | Silver and Gold only outside harbours | When moored in a harbour (the game's own `is_moored_in_harbour`), fish are drawn below the Silver grade. Open water is unchanged |
| 13 | Wind volume | The deck's open-air wash, which is what you hear as wind in harbour, played on the Ambience bus. It now plays on the Wind bus, so the Wind slider governs it on deck, the pontoon and the quay. The cabin's bed, water, rain and harbour sounds stay on Ambience |
| 14 | A wake | A restrained wake while under way: a soft stirred band astern, two faint arms and a little white at the bow, growing with speed. There is none when moored, anchored or becalmed. It is a few lines drawn per frame, only while under way |
| 15 | Developer menu | New F10 rows: Money; Fuel; Fishing (lures, a rare Gold fish on the line); Pets (cat, Pug or conure on the dock); Harbour (to 07:00, 10:00 or 20:00 local); Passage (plan a short passage, fulfil the next dream). They act on existing systems through test-only setters, only in an editor debug run. The rows scroll at 130 % |
| 16 | Woken by a near collision | The wake-up names the vessel, how close it passes, in how long and from where. It says the radar on deck shows it, and that View chart on the warning lets you change course, or you can keep a lookout while it passes |
| 17 | Where is the coffee? | Pouring says the mug is in your hand and how to drink it or set it down (Q). The cup holder and the table mug are easy to reach (plain-distance focus). When the mug waits in the other area, the wheel's "Your coffee" says where |

Danish is complete: 3,181 messages, 0 errors.

## Validation (essential, Linux)

| Check | Result |
|---|---|
| Fishing, cockpit electronics, walk (`test_fishing`, `test_fishing2`, `test_catch_and_cove_journey`, `test_marine_electronics`, `test_living_world`; rendered) | 409 passed, 0 failed |
| Quay (`test_living_harbours`; rendered) | 104 passed, 0 failed (after the integration fix below) |
| Pets (`test_more_room_aboard`; rendered) | 114 passed, 0 failed |
| Flows, saves, coffee, audio, dev panel, watch and sleep, screen sweep in English and Danish (13 suites; rendered) | 742 passed, 2 failed. Both are environmental and pass headless: fullscreen can't apply under Xvfb, and an 8-hour sleep took 10.7 s on llvmpipe |
| The same two suites, headless | 82 passed, 0 failed |
| Launch smoke test (rendered, 12 s) | Starts to the title screen; no script or loading errors |
| Rendered probes (`tests/playtest_probe.tscn`) | Each finding seen and exercised: the walkway both ways, all 8 quay places by the wheel, a closed shop, running, cockpit focus on two boats, the trophy board's focus, the wake under way, the F10 panel |
| Localisation / GDScript guides / links / content | 0 errors / 387 scripts reviewed / 0 broken / 0 FAIL |

Not run, as ordered: the full regression, a full rendered regression,
career simulations and benchmarks.

## Measured time

Times are machine-recorded. Each mark carries wall-clock time (ISO 8601,
UTC) and CLOCK_MONOTONIC (`/proc/uptime`); the machine did not restart in
between. Nothing here is estimated.

- **Start:** 2026-10-29 22:18:10 UTC, at `8a24d0f`.
- **Total elapsed, first mark to the end of validation:** **75 min 18 s**
  (22:18:10 to 23:33:28). The commit, push and handover after that are in
  the JSON record's last marks.

| Category | Measured | Note |
|---|---|---|
| Preflight and backup | 0 min 10 s | Backup branch pushed and verified |
| Implementation (17 findings) | 58 min 21 s | The sum of the finding windows below. These did not overlap |
| Validation | 16 min 04 s | Includes waiting for the rendered suites and the guides agent, and the first two commits and pushes (`da569b3`, `84388b0`), which the stop hook asked for mid-validation |
| Git and administration | in the record | Timing report, final commit, push, verification |
| Parallel agent effort | 7 min 21 s | A helper agent updated the three GDScript guides. It **overlaps** validation and is not added to the elapsed total |
| Untracked gaps | 0 min 39 s | Between marks (preflight to finding 02, 12 to 13) |

| Finding | Duration | Status |
|---|---|---|
| 02 compact quay | 4 min 41 s | completed |
| 01 physical walkway | 6 min 33 s | completed |
| 03 quay wheel and auto-walk | 4 min 20 s | completed |
| 04 run | 1 min 08 s | completed |
| 05–07 cockpit (worked together: same code) | 5 min 53 s | completed |
| 08 pet boarding | 3 min 08 s | completed |
| 09 fishing rod | 19 min 51 s | completed (see note) |
| 10 trophy board | 2 min 39 s | completed |
| 11 fishing filters | 0 min 30 s | completed |
| 12 Silver/Gold outside harbours | 0 min 26 s | completed |
| 13 wind volume | 0 min 54 s | completed |
| 14 wake | 1 min 32 s | completed |
| 15 developer menu | 5 min 34 s | completed (see note) |
| 16 near-collision wake-up | 0 min 29 s | completed |
| 17 coffee | 0 min 43 s | completed |

**Notable interruptions.** These were not timestamped separately, so they
are not split out:
- **Finding 09's window** also holds the integration work for finding 08,
  which was investigated while the rod was being drawn. The pet suite's
  "Not now" checks needed the adoption dialog to settle before clicking.
  09's own figure is therefore an upper bound.
- **Finding 15's window** holds the integration fix for finding 02. The
  compact quay's boat ashore and the lift dock had closed the way to the
  travel lift, so the hull was made slimmer and higher and the dock
  shallower. The fix ended at the `debug_integration` mark (23:13:46).

## Known limitations

- **Windows:** nothing here has been checked on Windows or a GPU yet.
- **The quay wheel's walk:** it follows the walking lane and steps round
  the noticeboard and the café terrace. It is not general pathfinding:
  a person standing in the way stops it, with a short note.
- **`tests/pacing_18.gd`** (a measurement tool, not a suite) counts
  fishing interruptions under each keep setting. Finding 11 may change its
  figures. It was not re-run.
- **The two rendered-only failures** above are environmental. They pass
  headless and need no change.
