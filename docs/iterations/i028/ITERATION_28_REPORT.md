# I028 - Passages, People & Reputation

**Release classification: I028 Windows Playtest Release.** Commissioned with
all six tiers authorised (Lean Mode, no intermediate approvals). The Windows
and GPU checks are pending; nothing here has been verified on Windows.

*Travellers aboard, the passages they book, the dreams they bring, the
Captain's travel writing, and the wider sailing world: its history, its
network, its magazine, its rankings and its famous yachts.*

Version **0.114a**. Save format **12** is unchanged: two optional new
sections, `passages` (the passage trade) and `world` (the world's history,
travel writing, the magazine archive, meetings and invitations), both with
safe defaults; an older save starts an empty book and a fresh world.

| | |
|---|---|
| Starting commit | `ed7601a` (after the I027 regions and Captain Haddock work), saved as `backup/i028-start` |
| Iteration branch | `iteration/i028` |
| Checkpoint | `backup/i028-tier-3` = `6bd4620` (a playable passenger-transport experience) |
| Release branch | `release/i028`, at the final commit named in the delivery note. Commits after the tested code are documentation only |
| Build label | `BH · i028 · TEST` |
| Windows acceptance | **Pending.** See [WINDOWS_ACCEPTANCE.md](WINDOWS_ACCEPTANCE.md) |
| Career verification | [CAREER_FINDINGS.md](CAREER_FINDINGS.md) |

## What I028 contains

| Tier | What |
|---|---|
| 1 Passenger marketplace | The laptop's **Passages** app: the course planned on the chart (or chartplotter) published as a passage, with stops along it, a departure window and a price; travellers' requests (route, ETA, vessel, accommodation, berths, price, requirements); accept, decline or name a price once; ten persistent rival skippers who win some travellers, with a reason; multi-leg bookings with capacity per overlapping leg, overnight beds and private cabins counted |
| 2 Passengers | Travellers with a name, background, motivation, budget, comfort, privacy, weather temperament, timing, detour tolerance, pets and allergies (a severe allergy never books), talkativeness and review habits; groups within the boat's capacity and privacy; guests walk up the gangway, find a place on deck or a berth below, read, drink coffee, photograph, play with the pet, sleep below at night, and go ashore at their stop; "Talk with ..." and lines that suit each person; no meters, no chores |
| 3 Contracts | Terms per booking (identities, legs, window, expected arrival with a fair margin, fare, deposit, balance, refund terms, accommodation, alternate harbour), settled on what was really sailed: deposits, balances, refunds for an unexcused delay only (safe seamanship is never punished), tips, stars and a review; an alternate harbour agreed under way with an honest transfer note (near, regional, far, ferry; no taxis or flights); one authoritative voyage ledger; nothing paid twice, also after a save and load |
| 4 Dreams | Passengers' dreams (a night at sea, reach a place, scenic, island hopping, an ocean crossing; a partial leg is no crossing) and the Captain's Dreams of the Sea with explicit criteria (arrive, region, passage, transport, event, publish, renown): 18 dreams. Letters, photographs, gifts, recommendations and achievements, each once |
| 5 Writing and network | **Travel writing** replaces the little game: essays, journals, travelogues, adventure books and novels about real voyages, written in two-hour sessions with a chosen angle, published for a modest fee; the old game's progress migrated once. **The world's history**: one persistent ledger of departures, arrivals, expeditions, books and meetings of 24 memorable travellers, 19 yachts and 180 more sailors, advanced a whole day at a time, deterministic, never rewritten, a yacht in one place at a time at plausible speeds. **Traveller Network** on the laptop: posts read from that ledger, 24 painted atmospheric pictures (people as silhouettes) and text-only posts; following |
| 6 Magazine, renown, directory | **Sails & Sights**, one issue a month, frozen in an archive; renown **rankings** (deterministic, stable tie-break, no rubber-banding) with the Captain's place and Top 100/50/10/#1 ambitions; a searchable **yacht directory** of last public reports (unknown and stale marked); notable yachts on the radar's **AIS** (live, within range only, kept apart from the directory); **meetings** on the quay and at sea; **prestigious invitations** that need several qualifications and become real bookings. The end-to-end scenario: Freya Voss and Maya Wildshore sail Northern Promise to Greenland (Nuuk, a new harbour), consistent across every view |

## The commission's mandatory demonstrations (Tier 3)

| Demonstration | Where |
|---|---|
| A normal passage | `test_passages` (offer, requests, bargaining, boarding, settlement, review) |
| A delayed passage | `test_passages` (refund for an unexcused delay; none after caution) |
| An alternate harbour | `test_passages` (Korsør: honest transfer band, acceptance, settlement at the new harbour) |
| A multi-leg passage | `test_passages` (two board at the start, one leaves at the stop, one joins there; capacity per leg and overnight) |
| Save and load with people aboard | `test_passages` (capacity, payments and responses kept; the balance paid once, the deposit never again) |
| Freya Voss / Greenland end to end | `test_world_renown` (ledger, network post, directory report, AIS alongside, the meeting in Lerwick, the magazine, the rankings; an invitation booked and sailed) |

## Career verification (Section 9)

24 careers, eight archetypes, three seeds each, to 100 estimated human hours:
[CAREER_FINDINGS.md](CAREER_FINDINGS.md). They found and fixed three things
in this iteration: the world's renown scale (everyone was first within ten
hours), travel writing that paid far more than "modest", and a real bug where
a new game or a loaded earlier save had a frozen world. Three dead ends are
proposed to the Captain, not changed: the long-distance explorer and the
Seasoned "difficult luck" sailor run out of money without passengers or
writing, and a professional skipper on the 26 ft starter boat slowly loses
money. Four clocks are kept apart there: wall-clock, in-game, **estimated**
human hours, and measured human hours (none).

## Tests on the release candidate

All runs are on Linux, in a container without a GPU.

| Run | Commit | Result |
|---|---|---|
| Focused I028 suites during the tiers (`test_passages`, `test_world_network`, `test_world_renown`, saves, dreams, localisation, branding) | during the iteration | green at each step (Tier 3 checkpoint focused suites; 519/0 across 13 suites after Tier 6) |
| Full regression (headless, all 99 suites), first | `9cb0290` | 6,027 passed, **43 failed** - investigated and fixed (see below) |
| Full regression (headless, all 99 suites), after the fixes | `8dad67d` | RESULT_FULL_2 |
| Rendered checks (xvfb, OpenGL 3 on llvmpipe, 1600×900) | during Tiers 1-6 | guests boarding over the gangway; the Passages, Network and World apps in English and Danish |
| Content / localisation / GDScript guides / links | release candidate | 0 FAIL / 4,042 messages, 0 errors / 414 scripts reviewed / 0 broken |

**What the first full run found** (all fixed in `8dad67d`): the laptop's
eight tabs pushed its screen past the window at 130% UI scale; the
instruments' next-leg forecast stayed in English after switching to Danish (a
cache without the language, latent since I026); the achievement collection
grew past the small collection I024 asked for (four I028 achievements kept,
the Top 50/10/#1 goals became Dreams); a game saved in Danish did not reload
byte-identical (the world's numbers are now held as the save holds them); two
pre-I028 suites that count renown exactly met the new quay meetings (they now
run with a quiet world, a test-only switch like the fuel one).

**Known and not I028's:** three pet-petting checks in `test_cozy_patch` fail
at the I028 starting commit `ed7601a` as well (they broke between
`release/i027` and the regions work); not changed here.

## Elapsed time

From the I028 timing log (`i028_timing.jsonl`, monotonic clock of one
session; marks were written at milestones). Wall-clock elapsed, not effort:
the career simulator ran four processes in parallel, and two helper agents
worked beside the main thread (the Danish translations, about 4 minutes; the
GDScript guides, about 14 minutes).

| Stretch | Elapsed |
|---|---|
| Pre-flight (backup, iteration branch, system map) and the core of Tiers 1-3 | 17 min (one mark covers both; the split was not recorded) |
| Tier 3 finish, rendered checks and the checkpoint | 20 min |
| Tier 4 | 2 min (built alongside Tier 3, committed after the checkpoint) |
| Tiers 5-6 | 26 min |
| Career verification (three rounds after two fixes; 3.3 h of CPU on 4 cores), Danish, guides | 133 min |
| Regression, fixes, report and release | ELAPSED_TAIL |
| **Total** | TOTAL_ELAPSED |

## Known limitations

- **Windows and GPU checks are pending** (the list in
  [WINDOWS_ACCEPTANCE.md](WINDOWS_ACCEPTANCE.md)).
- The radar's AIS diamonds were checked headless (`test_world_renown`); no
  rendered screenshot of them yet.
- Sails & Sights issues are written in the language active when they were
  published; switching language later does not rewrite the archive.
- The world's news for a day is written when that day is over: a yacht's
  public report can be up to a day behind.
- The three career dead ends above are proposals awaiting the Captain.
- No installer or update package: the release is the branch ZIP, as for I027
  (there is no export pipeline in this environment).
