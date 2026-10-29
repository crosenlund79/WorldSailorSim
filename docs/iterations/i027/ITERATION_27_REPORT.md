# I027 - The Cost of the Wind

*Sailing to windward, what a boat costs to run, what it offers people
aboard, and the first steps of Between Horizons.*

Version **0.113a**. Save format **12** is unchanged: two optional new
sections, the career's books and Dreams, both with safe defaults.

| | |
|---|---|
| Starting commit | `51c247e` (`release/i026`) |
| Iteration branch | `iteration/i027` |
| Tier checkpoints | `backup/i027-tier-1` = `93244d2`, `-tier-2` = `2460371`, `-tier-3` = `73473b4`, `-tier-4` = `4807b6c` |
| Release branch | `release/i027`, at the final commit named in the delivery note. Commits after the tested code are documentation only |
| Build label | `BH · i027_0N · DEV` during the tiers; `BH · i027_04 · TEST` on the release |
| Windows acceptance | **Pending.** See [WINDOWS_ACCEPTANCE.md](WINDOWS_ACCEPTANCE.md) |

The plan: [DESIGN.md](DESIGN.md). Each tier has its own report.

## What I027 contains

| Tier | What | Details |
|---|---|---|
| 1 | Sailing to windward: the autopilot beats and gybes on the polar's best angles; manual tacking (**K**, the action wheel); the instruments name the tack; an ETA that counts the zigzag | [GATE_1_REPORT.md](GATE_1_REPORT.md) |
| 2 | Fuel (a tank per boat, burn under engine, the pump on every quay), harbour dues, **Motor to windward**, running costs, a fuel-aware ETA, the career's books, one balance file | [GATE_1_REPORT.md](GATE_1_REPORT.md), [TIER_02_COST_OF_OWNERSHIP.md](TIER_02_COST_OF_OWNERSHIP.md), [TIER_02_CAREER_FINDINGS.md](TIER_02_CAREER_FINDINGS.md) |
| 3 | What each boat offers people aboard, checked against its drawn cabin; booking queries for I028; the boatyard's comparison; the fuel note in passage readiness; careers that look after and buy boats | [TIER_03_ACCOMMODATION.md](TIER_03_ACCOMMODATION.md), [TIER_03_CAREER_FINDINGS.md](TIER_03_CAREER_FINDINGS.md) |
| 4 | Dreams of the Sea; the `PassagePlan` contract; AIS preparation; telemetry foundations; the opening story and the working title; the commissioned character polish; the compact waterfront; F10 on the quay; the engine hand-over fix | [TIER_04_REPORT.md](TIER_04_REPORT.md), [TIER_04_OPENING.md](TIER_04_OPENING.md), [TIER_04_CHARACTERS.md](TIER_04_CHARACTERS.md), [TIER_04_WATERFRONT_AND_FIXES.md](TIER_04_WATERFRONT_AND_FIXES.md) |

## The commission's ten acceptance items

| # | Item | Built | Checked on Linux | Windows |
|---|---|---|---|---|
| 1 | New-game opening | Tier 4 | `test_opening` (rendered): pages, Continue and click, Skip, Esc, Danish, never on load or Continue, ends in the cabin | pending |
| 2 | Captain's Dreams | Tier 4 | `test_dreams`: choose up to three, fulfilled from real play, quiet on load, the laptop app | pending |
| 3 | Fuel purchase | Tier 2 | `test_cost_of_wind`: the pump, fill and +10 L, price, never below zero money | pending |
| 4 | Fuel consumption | Tier 2 | `test_cost_of_wind`, `test_world_voyage`: burn under engine only, empty tank means sails, notices | pending |
| 5 | Operating costs | Tier 2 | `test_cost_of_wind`: dues on leaving, the Harbour Office's list, the books | pending |
| 6 | Manual and automatic tacking | Tier 1 | `test_windward` and `test_sailing`: beats on the best angle, K and the wheel, the deck crosses over | pending (the tack's feel) |
| 7 | Realistic ETA | Tiers 1-2 | `test_windward`, `test_cost_of_wind`: windward and fuel-aware estimates against the sailed time | pending |
| 8 | Two distinct yacht layouts | Tier 3 | `test_accommodation`: four boats; the 26 ft / 33 ft (saloon and V-berth) and the Clam 40 (owner's and guest cabins, two heads) differ in data and art | pending |
| 9 | Save and load | all | the save suites; `test_gameplay_flow`; old saves load (format 12) | pending |
| 10 | The I026 waterfront still works | Tier 4 (compacted) | `test_living_harbours`, `test_waterfront_walkthrough`, café and shop suites | pending |

## Tests on the release candidate

RESULTS

## Performance

PERFORMANCE

## Build identity and save compatibility

- **Build label:**
  - `BH · i027_04 · TEST · <commit>` (`GameVersion`, checked by
    `test_build_label`);
  - the version is `0.113a`;
  - the window title is the working title, Between Horizons.
- **Saves:**
  - `SAVE_VERSION` 12 is unchanged;
  - an I026 save loads where it was, with its money, boats, companions,
    journals and difficulty;
  - the books start empty, dues count from the load, and Dreams catch up
    quietly with what was already done;
  - loading never shows the opening;
  - the save folder (`Little Captains Hat`) and the format id are unchanged.
- **Languages:** every message is in English and Danish.

## Known limitations

- **Windows:** nothing in this iteration has been verified on Windows yet.
  The release is a playtest build, not a Windows-approved release.
- **Between Horizons** is a creative working title. A released game has
  that name, so the Captain decides before any public metadata. No
  substitute has been chosen.
- **Remote work** is still the only material income, unchanged as ordered.
  A cap or diminishing returns comes after I028's passenger income can be
  compared.
- **The 26 ft on the longest ocean leg** is tight on stores. Its storage is
  unchanged as ordered, and the readiness says so honestly.
- **No tack animation:** a tack has no slowdown animation of its own (on the
  polish list). Manual tacking is a decision, not free steering.
- **The walk:** at full speed the planted foot creeps back a little (feet
  kept subtle).
- **AIS** has no display. Passengers, fares and the yacht directory are
  I028, which has not been started.
- **Career playtesting** uses automated strategies on the real rules: not
  human play, and not proof of full-career balance.
- **Linux only:** the chart-panning time and Long Passage frame times were
  measured in a container without a GPU, so they need Windows readings.
