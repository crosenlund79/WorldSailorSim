# I027 Tier 2 - Fuel and the cost of ownership

**Status: waiting for the Captain's acceptance (gate 1).** Design:
[DESIGN.md](DESIGN.md).

## What a player meets

**Fuel**
- Every boat has a tank. The engine burns fuel at its cruising rate in the
  same simulation step that moves the boat under engine; under sail it burns
  nothing.
- At a quarter of a tank the Captain is told how far it still goes. When the
  tank runs dry the boat sails on under sail alone: no free motoring. When
  becalmed it waits for wind, and the existing VHF and rescue paths are
  unchanged.
- Fuel is bought at the **fuel berth**, a pump by the walkway's head on
  every quay. It is open at any hour, and E opens the pump. You can fill up
  or add 10 litres, as much as the money allows.

**Harbour dues**
- Dues are paid once, when you leave, for the nights moored (local
  midnights on the harbour's clock).
- A stop under 6 hours is free, and anchoring is always free.
- If the money is short, what can be paid is paid and the harbourmaster
  waives the rest, so nobody is held in harbour by dues.

**The choice to windward**
- By default a leg to windward is beaten under sail (Tier 1).
- **Motor to windward** on the action wheel makes the engine motor straight
  up such legs while there is fuel: faster, at a cost.
- In the tests, four hours to windward in 13 knots made 11.2 nm on 0.9 litres
  beating against 20 nm on 8.8 litres (about €17) motoring.

**Running costs**
- The harbour office shows the dues here, the fuel price and the boat's range
  under engine, and the last 30 days' costs by kind.
- The status line shows the fuel; the switch panel shows the fuel and its
  range.

**Relaxed** pays 75 % of fuel and dues, through the existing *costs* factor.

## The balance file

Everything tunable for Tier 2 lives in `data/economy/economy.json`, read only
by `Economy`. The difficulty's costs factor is applied by `GameSession`.

| Item | Value | Assumption |
|---|---|---|
| Fuel per litre | Nordic €2.05, Atlantic €1.95, Mediterranean €1.90, Tropical €1.60 | Marina diesel, rounded; region from `HarbourDressing.archetype_for` |
| Small-harbour factor | ×1.10 (major ×0.97) | Small harbours: one pump, a little dearer |
| Arctic Wanderer 26 | 45 L tank, 2.2 L/h | Small diesel at about 5 kn: about 100 nm range |
| Wing 33 | 120 L, 3.2 L/h | About 190 nm |
| Frogleap 36 (trimaran) | 70 L, 4.0 L/h | Outboard at 5.5 kn: about 95 nm |
| Clam 40 (catamaran) | 380 L, 7.0 L/h | Twin diesels at 6.5 kn: about 350 nm |
| Dues per metre and night | small €1.60, larger €2.40, major €3.20 | Typical guest-berth rates |
| Region factor | Mediterranean ×1.35, Tropical ×1.10, else ×1.0 | |
| Grace | 6 hours | A lunch stop is free |

Examples:
- **26 ft in Copenhagen (major, Nordic):** €26 a night.
- **40 ft in a major Mediterranean harbour:** about €53 a night.

**Not changed, measured first** (the commission's order: measure before
repricing):
- provisions (€10 a day);
- boat care (repair, services, haul-out);
- equipment and boats;
- the chandlery and instruments;
- remote work (€25 an hour);
- fishing, publishing, VHF assists.

The career runs below show how they behave together.

## The career's books

`CareerLedger` records every euro by source. All 20 former changes to the
money in `GameSession` now pass through one `_money(amount, source)`. It also
records:
- fuel bought and burned;
- miles under sail and under engine;
- each voyage's own figures (miles, fuel, tacks, costs under way).

It is real data from the real game, the foundation of the career tests
(Part VII), and the harbour office reads it.

## Career playtesting, Mode A (first run)

`tests/career/career_sim.tscn` plays careers on the real rules:
- a new game on a seed;
- a policy for remote work, provisions, fuel and stays;
- real voyages between real harbours 20–90 nm apart, in the seeded weather;
- dues on leaving.

No money, voyages or awards are injected. Three clocks are reported
separately:
- wall-clock time of the run;
- in-game days;
- an **estimate** of a player's active time (a labelled model, not a
  measurement).

Results (median, range, failures) are in the gate report:
[TIER_02_CAREER_FINDINGS.md](TIER_02_CAREER_FINDINGS.md).

## Save compatibility

`SAVE_VERSION` stays 12. New optional sections:
- `fuel`: missing means a full tank;
- `ledger`: missing means empty books;
- `moored_since`: missing means counting starts at load, never backwards;
- `motor_upwind`: missing means beating.

`test_cost_of_wind` loads an older save without them.
