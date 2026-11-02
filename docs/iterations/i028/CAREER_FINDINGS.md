# I028 career verification - eight archetypes, 5 to 100 hours

**What this is:** 24 careers (eight archetypes x seeds 1-3) played by the
career simulator (`tests/career/career_sim.gd`) on the real game rules,
through `GameSession` and `Simulation` only: real voyages between real
harbours in the seeded weather, remote work, provisions, fuel, harbour dues,
the boatyard, published passages and the travellers who book them, travel
writing, invitations - nothing the game would not give. Each career runs
to **100 estimated human hours**, and its state is recorded at 5, 10, 20, 40,
80 and 100 hours (`horizons.csv`; one row per career in `summary.csv`).

**Four clocks, kept apart:**

| Clock | Total for the 24 careers | Notes |
|---|---|---|
| Wall-clock (the simulator's run time) | 11,947 s (3.3 h of CPU, about 1.1 h elapsed on 4 cores) | measured |
| In-game time | 29,178 game days | measured |
| Estimated human time | 2,402 h (100 per career) | **an estimate**, the simulator's labelled model: 8 min per harbour stop, 1 min per work session, 3 min per published passage, 0.5 min per answered request, 2 min per writing session, 3 s per game hour under way at 20x |
| Measured human time | **none** | no human has played these hours; the Windows playtest is pending |

Build `BH · i028 · TEST` on `iteration/i028` (commits `ef247e1`..`5bf413d`;
the final rows for prestige hunter and the seed-1 rows of the professional
skipper, comfortable cruiser, hobbyist and pet lover were re-run after the
two fixes below). Raw per-career JSON and telemetry (about 2 MB each) are
kept out of the repository; `tools/qa/summarize_i028_careers.py` rebuilds the
tables from them, `tests/career/world_thresholds.tscn` the world's renown
thresholds (`world_thresholds.csv`).

## The archetypes

| Archetype | Policy |
|---|---|
| frugal coastal | 4 h remote work a day, 2 days a stop, short hops (15-50 nm), sails to windward, buys late |
| professional skipper | 2 h work, 1-day stops, hops 30-110 nm, motors to windward, publishes every hop as a passage (going rate), boatyard care |
| independent explorer | 3 h work, 2-day stops, long hops (80-240 nm), sails |
| comfortable cruiser | 3 h work, motors to windward, keeps the tanks and stores full, boatyard care |
| hobbyist traveller | 3 h work and a two-hour writing session each harbour day |
| difficult luck | **Seasoned** difficulty (less starting money), 4 h work, 1-day stops, hops 40-140 nm |
| pet lover | starts with a dog; 4 h work; publishes passages at 0.9x (allergic travellers never book) |
| prestige hunter | 2 h work, passages at 1.15x, writing, accepts invitations, hops 60-200 nm, care |

## Medians by archetype and horizon

| Archetype | Horizon (est. h) | Game days | Funds € | Voyages | Harbours | Passengers | Dreams | Works | Renown | Rank |
|---|---|---|---|---|---|---|---|---|---|---|
| comfortable_cruiser | 5 | 58 | 10891 | 28 | 25 | 0 | 1 | 0 | 496 | 133 |
| comfortable_cruiser | 10 | 116 | 11596 | 56 | 41 | 0 | 1 | 0 | 676 | 113 |
| comfortable_cruiser | 20 | 235 | 12973 | 112 | 59 | 0 | 2 | 0 | 939 | 88 |
| comfortable_cruiser | 40 | 469 | 15587 | 225 | 75 | 0 | 2 | 0 | 1127 | 75 |
| comfortable_cruiser | 80 | 941 | 21046 | 451 | 87 | 0 | 2 | 0 | 1231 | 68 |
| comfortable_cruiser | 100 | 1177 | 23373 | 564 | 88 | 0 | 2 | 0 | 1251 | 67 |
| difficult_luck | 5 | 61 | 6000 | 28 | 25 | 0 | 1 | 0 | 518 | 129 |
| difficult_luck | 10 | 128 | 4638 | 55 | 43 | 0 | 1 | 0 | 757 | 104 |
| difficult_luck | 20 | 259 | 1317 | 109 | 70 | 0 | 2 | 0 | 1109 | 73 |
| difficult_luck | 40 | 486 | 40 | 196 | 96 | 0 | 2 | 0 | 1428 | 39 |
| difficult_luck | 80 | 925 | 0 | 343 | 122 | 0 | 2 | 0 | 1693 | 26 |
| difficult_luck | 100 | 1148 | 84 | 419 | 126 | 0 | 2 | 0 | 1729 | 24 |
| frugal_coastal | 5 | 59 | 13017 | 28 | 24 | 0 | 0 | 0 | 475 | 136 |
| frugal_coastal | 10 | 116 | 15886 | 56 | 38 | 0 | 1 | 0 | 642 | 116 |
| frugal_coastal | 20 | 238 | 21342 | 113 | 53 | 0 | 1 | 0 | 885 | 93 |
| frugal_coastal | 40 | 478 | 31899 | 224 | 87 | 0 | 2 | 0 | 1230 | 63 |
| frugal_coastal | 80 | 953 | 53385 | 449 | 95 | 0 | 2 | 0 | 1310 | 58 |
| frugal_coastal | 100 | 1194 | 64397 | 561 | 115 | 0 | 2 | 0 | 1570 | 34 |
| hobbyist_traveller | 5 | 55 | 11413 | 20 | 18 | 0 | 2 | 9 | 568 | 123 |
| hobbyist_traveller | 10 | 103 | 12881 | 40 | 30 | 0 | 3 | 12 | 834 | 98 |
| hobbyist_traveller | 20 | 210 | 15687 | 79 | 58 | 0 | 3 | 19 | 1256 | 55 |
| hobbyist_traveller | 40 | 429 | 20921 | 158 | 82 | 0 | 3 | 32 | 1831 | 17 |
| hobbyist_traveller | 80 | 851 | 31356 | 315 | 115 | 0 | 3 | 58 | 2733 | 5 |
| hobbyist_traveller | 100 | 1054 | 37467 | 394 | 126 | 0 | 3 | 71 | 3091 | 2 |
| independent_explorer | 5 | 103 | 9047 | 23 | 21 | 0 | 1 | 0 | 610 | 122 |
| independent_explorer | 10 | 201 | 8204 | 45 | 36 | 0 | 2 | 0 | 885 | 93 |
| independent_explorer | 20 | 399 | 6109 | 90 | 64 | 0 | 2 | 0 | 1316 | 54 |
| independent_explorer | 40 | 827 | 1101 | 176 | 99 | 0 | 2 | 0 | 1910 | 17 |
| independent_explorer | 80 | 1594 | 0 | 326 | 129 | 0 | 2 | 0 | 2659 | 11 |
| independent_explorer | 100 | 1976 | 73 | 397 | 135 | 0 | 2 | 0 | 3014 | 10 |
| pet_lover | 5 | 52 | 13805 | 21 | 17 | 20 | 4 | 0 | 618 | 119 |
| pet_lover | 10 | 106 | 17077 | 43 | 33 | 31 | 6 | 0 | 874 | 93 |
| pet_lover | 20 | 217 | 23383 | 85 | 53 | 64 | 6 | 0 | 1078 | 76 |
| pet_lover | 40 | 444 | 37112 | 168 | 79 | 133 | 6 | 0 | 1426 | 37 |
| pet_lover | 80 | 888 | 64650 | 337 | 104 | 262 | 6 | 0 | 1674 | 23 |
| pet_lover | 100 | 1117 | 77631 | 421 | 106 | 326 | 6 | 0 | 1733 | 24 |
| prestige_hunter | 5 | 59 | 11134 | 15 | 16 | 6 | 5 | 8 | 706 | 106 |
| prestige_hunter | 10 | 122 | 12403 | 31 | 28 | 10 | 6 | 10 | 967 | 86 |
| prestige_hunter | 20 | 243 | 12405 | 61 | 52 | 18 | 6 | 15 | 1459 | 33 |
| prestige_hunter | 40 | 490 | 15766 | 122 | 80 | 44 | 7 | 25 | 2162 | 6 |
| prestige_hunter | 80 | 978 | 16830 | 245 | 117 | 76 | 7 | 46 | 3104 | 2 |
| prestige_hunter | 100 | 1210 | 20498 | 307 | 123 | 101 | 7 | 56 | 3552 | 1 |
| professional_skipper | 5 | 40 | 10299 | 23 | 23 | 10 | 4 | 0 | 561 | 124 |
| professional_skipper | 10 | 80 | 10593 | 45 | 37 | 20 | 4 | 0 | 749 | 104 |
| professional_skipper | 20 | 164 | 10091 | 90 | 63 | 37 | 6 | 0 | 1206 | 62 |
| professional_skipper | 40 | 323 | 8707 | 180 | 90 | 71 | 6 | 0 | 1529 | 30 |
| professional_skipper | 80 | 659 | 6377 | 360 | 121 | 144 | 6 | 0 | 1868 | 18 |
| professional_skipper | 100 | 828 | 3970 | 449 | 128 | 172 | 6 | 0 | 1945 | 18 |

| Archetype | Careers | Wall s (median) | Income at end: work / passengers / writing (median €) | Min funds (lowest) | Stranded |
|---|---|---|---|---|---|
| comfortable_cruiser | 3 | 311 | 84750 / 0 / 0 | 10000 | 0 |
| difficult_luck | 3 | 556 | 57400 / 0 / 0 | 0 | 0 |
| frugal_coastal | 3 | 304 | 112400 / 0 / 0 | 10000 | 0 |
| hobbyist_traveller | 3 | 358 | 59250 / 0 / 18940 | 10000 | 0 |
| independent_explorer | 3 | 983 | 68400 / 0 / 0 | 0 | 0 |
| pet_lover | 3 | 365 | 84200 / 33440 / 0 | 10000 | 0 |
| prestige_hunter | 3 | 652 | 30700 / 33640 / 14660 | 9433 | 0 |
| professional_skipper | 3 | 440 | 22500 / 27140 / 0 | 2459 | 0 |

## What the careers found, and what was done

1. **The world's renown was on the wrong scale (fixed).** The first batch
   put every Captain at rank 1 within about 10 estimated hours: the notable
   travellers started at 290-620 renown and the population at 20-300, while
   the Captain's own renown total (the I024-I027 system, unchanged) is about
   650 at 10 hours and 1,500-3,000 at 100. The world was re-scaled to the
   Captain's: notables x4 (1,160-2,480), the population 30-1,600 skewed low,
   books and small accomplishments x4; voyages unchanged so the leaders do
   not run away. Thresholds over 1,200 days (`world_thresholds.csv`, median
   of 3 seeds): #100 765 -> 890, #50 1,260 -> 1,410, #10 1,640 -> 2,430,
   #1 2,480 -> 3,330. Result (table above): **Top 100 at 10-20 h** for
   every archetype; **Top 50 at 20-40 h** for active ones; **Top 10** only
   for long-distance sailors (explorer, about 100 h), prolific writers
   (about 60 h) and the prestige hunter (about 40 h); **#1** for the prestige
   hunter at about 100 h (all three seeds) and one hobbyist seed. Coastal
   cruisers settle between 33 and 75. Ranks are deterministic (renown, then
   id); nothing pulls the Captain up or the others down.

2. **Travel writing paid far more than "modest" (fixed).** A writer earned
   more from writing than from remote work (EUR 68,390 against 59,100 at
   100 h; a novel paid about EUR 37 an hour of writing against EUR 25 for
   remote work) and its renown ran away (4,428). Every form now pays about
   EUR 20 a two-hour session (EUR 10 an hour, +-20% by the angle) and less
   renown per work: the hobbyist now earns about EUR 19,000 from writing
   against 59,000 from work, and is still the most famous of the coastal
   archetypes.

3. **A new game after a long one had a frozen world (fixed, a real bug).**
   The world's hourly checkpoint outlived its game, so the second career in
   a run - and a player's new game or loaded earlier save - saw no news, no
   magazine and rank 1 until its clock passed the old one. The checkpoint now
   resets with each game, and the world starts when the game starts.
   Regression check in `test_world_network`.

4. **Simulator flaw (fixed, not the game's):** the professional skipper's
   one-day stays answered requests before any had arrived and withdrew every
   passage; the policy now looks again before the guests board.

## Balance questions

| Question | Answer from the careers |
|---|---|
| Can every archetype live? | Five of eight end richer than they began. The frugal coastal sailor (EUR 64,000) and pet lover (EUR 78,000) do best; the comfortable cruiser keeps EUR 22,000-24,500 despite motoring and full care; the prestige hunter EUR 17,000-22,000 |
| Is the passage trade worth it? | Yes as a second income: the pet lover earns EUR 33,440 in fares (326 guests, 4.6 stars) beside remote work; the prestige hunter EUR 33,640 at higher prices (EUR 328 a guest). Alone, on the 26 ft starter with motoring and care, it does not pay its way (dead end C) |
| Do pets harm the trade? | No: allergic travellers simply never book; the pet lover carried the most guests (326) with the best reviews |
| Are dreams reachable? | 2-8 per career; passenger and writing archetypes fulfil the most (6-8) |
| Invitations | Rare and earned: 1-2 for the prestige hunter, 1 for the professional skipper, none for the others (they need renown, reviews and a long passage) |
| The world's pace | 26-65 magazine issues (one a month), 4-10 meetings with notable crews per career |
| Fuel and costs | Motoring archetypes spend EUR 18,000-21,000 on fuel over 100 h; sailing archetypes EUR 15,000 (longer coastal careers) |

## Dead ends and outliers (proposals for the Captain, not applied)

- **A. Independent explorer runs out of money at 40-80 h** (all seeds; 465-500
  days under EUR 200, ending at EUR 73-106). Long passages earn nothing
  (remote work needs a harbour) while provisions and fuel go on. It never
  stops sailing: it keeps moving with a near-empty purse. *Proposal:* an
  in-game hint when funds run low ("passengers or writing could help on long
  passages"), and/or let a long-range package allow a short remote-work
  session at sea. No numbers changed.
- **B. Difficult luck (Seasoned) is broke from about 40 h** (EUR 7,000 start, 4 h
  work, 1-day stops: 340-365 days under EUR 200). That is Seasoned working as
  designed for a sailor who never takes passengers or writes. *Proposal:* keep;
  revisit the Seasoned start money only if the Windows playtest finds it
  harsh.
- **C. Professional skipper on the starter boat slowly loses money** (EUR 10,000
  -> 2,500-9,000 at 100 h; fares EUR 27,140 + work 22,500 against costs of
  EUR 57,000, mostly motoring and boatyard care). The 26 ft boat sleeps two
  guests overnight. *Proposal (needs evidence first):* add an upgrading
  skipper policy that buys the Starling 33 and re-run, before considering any
  rise in the passage rate (EUR 1.40 /nm/person).
- **Outlier:** the explorer takes about twice the game days per human hour
  (1,970 days at 100 h) because long passages count little human time.
