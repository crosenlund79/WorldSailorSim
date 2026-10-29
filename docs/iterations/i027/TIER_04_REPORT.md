# I027 Tier 4 - Report to the Captain

Tier 4 was authorised with Tier 3's approval. It also brought the
commissioned character polish and two fixes from the Captain's Windows
playtesting.

| | |
|---|---|
| Iteration branch | `iteration/i027` |
| Tier 3 checkpoint | `backup/i027-tier-3` = `73473b4` (full regression 5,651 / 0) |
| Tier 4 checkpoint | `backup/i027-tier-4` = `TBD` (full regression: TBD) |
| Build label | `BH · i027_04 · DEV` |
| Version | 0.113a. Save format 12 is unchanged: Dreams is an optional new section with safe defaults |

## What Tier 4 delivered

| Item | Where it is described |
|---|---|
| The developer menu (F10) opens on the quay; regression test | [TIER_04_WATERFRONT_AND_FIXES.md](TIER_04_WATERFRONT_AND_FIXES.md) §1 |
| The compact waterfront: believable human scale, compressed buildings (Copenhagen's quay 87 → 58 m, the walk to the boatyard 10.5 → 7.3 s) | [TIER_04_WATERFRONT_AND_FIXES.md](TIER_04_WATERFRONT_AND_FIXES.md) §2 |
| Characters: proportions, the hat, one shared alternating walk (`HumanGait`) | [TIER_04_CHARACTERS.md](TIER_04_CHARACTERS.md) |
| Dreams of the Sea: eight dreams, three pursued at a time, on the laptop; those needing I028 are shown as "later" | `src/core/dreams.gd`, `data/progression/dreams.json` |
| `PassagePlan`: a versioned data contract from the chartplotter's course | `src/navigation/passage_plan.gd` |
| AIS preparation: local contacts with CPA/TCPA over the existing traffic, no new screen | `src/electronics/ais_receiver.gd` |
| Telemetry foundations: snapshots and a recorder (JSON lines and CSV), used by the career harness | `src/core/career_telemetry.gd` |
| The opening story and the working title, Between Horizons (the naming conflict is flagged) | [TIER_04_OPENING.md](TIER_04_OPENING.md) |

## A bug found on the way: the engine on a beam reach

- **The bug:** the engine stayed on whenever the wind could not drive the
  boat past 6 kn, but the 26 ft's engine only makes 5 kn. So on a good
  beam reach in moderate wind it kept motoring. Copenhagen to Kiel ran
  102 nm under engine.
- **The fix:** the engine now hands over to the sails at the lower of the
  two speeds. The same passage now runs 7 nm under engine.
- **Career impact:** the career batches were run again on the fixed
  build. Only the cruiser, which motors to windward, moved noticeably. The
  Tier 2 and Tier 3 findings stand
  ([TIER_02_CAREER_FINDINGS.md](TIER_02_CAREER_FINDINGS.md),
  [TIER_03_CAREER_FINDINGS.md](TIER_03_CAREER_FINDINGS.md), "Re-measured").

A second fix: Dreams now counts the boat aboard as owned, as a save
already does, so loading a game never changes it. `test_gameplay_flow`
found it.

## Tests

- **Full regression:** TBD.
- **New suites:** `test_dreams`, `test_passage_plan`, `test_ais`,
  `test_telemetry`, `test_opening`.
- **Extended suites:** `test_upkeep_ui` (F10 everywhere),
  `test_living_harbours` (lane and compact quay), `test_living_world`
  (walk), `test_sailing` (engine hand-over) and `test_branding` (working
  title).
- **Documentation checks:**
  - three GDScript guides: 385 scripts, all reviewed;
  - links: 0 broken;
  - content: 0 FAIL;
  - localisation: 3,168 messages, all in Danish.
- **Known environmental failure:** `test_sailing_presentation`'s chart
  panning time exceeds 100 ms under this container's software renderer
  (llvmpipe). It fails the same way on `release/i026` and on Tier 3 and
  passes headless, so it needs a reading on Windows with a GPU.

## Still to check on Windows

1. F10 on the quay, the deck and in the cabin.
2. Walking the compact quay at normal speed (100 % and 130 %).
3. The walk cycle on a real display: start, stop, turn, diagonals.
4. The opening story from New Game: pacing, Skip/Esc, Danish.
5. The earlier findings, still open:
   - tacking feel;
   - fuel-pump visibility;
   - interface scaling;
   - Long Passage GPU performance.

## Known limitations

- **Between Horizons** is a working title only. A released game has that
  name, so the Captain must decide before any public metadata.
- The walk cycle's planted foot creeps back slightly at full speed (a
  deliberate compromise for subtle feet). The tack slowdown animation
  remains on the polish list.
- AIS has no display yet. Passengers, fares and the yacht directory belong
  to I028, which has not been started.
- Career playtesting is automated strategies on the real rules: not human
  playtesting, and not proof of full-career balance.

## Next

I027's final step: Windows acceptance of the ten items in the commission,
then `release/i027`. I028 is not started without a separate go-ahead.
