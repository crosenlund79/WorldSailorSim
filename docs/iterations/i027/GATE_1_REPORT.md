# I027 - Captain's acceptance gate 1 (after Tier 2)

The commission's first stop: *tacking, fuel and the real operating economy
must feel sensible before further expansion*. Tiers 3 and 4 wait for the
Captain's go-ahead.

| | |
|---|---|
| Iteration branch | `iteration/i027` (from `release/i026` = `51c247e`) |
| Tier 1 checkpoint | `backup/i027-tier-1` = `93244d2` (full regression 5,587 / 0) |
| Tier 2 checkpoint | `backup/i027-tier-2` (the tested commit below; see the delivery note) |
| Build label | `BH · i027_02 · DEV` |
| Version | 0.113a, save format 12 (unchanged; optional new sections only) |

Design: [DESIGN.md](DESIGN.md). Tier 2 notes:
[TIER_02_COST_OF_OWNERSHIP.md](TIER_02_COST_OF_OWNERSHIP.md). Career
findings: [TIER_02_CAREER_FINDINGS.md](TIER_02_CAREER_FINDINGS.md).

## Tier 1 - sailing to windward

When a leg cannot be sailed straight, the autopilot **beats** (or **gybes**
downwind) on the boat's best angle. It uses the existing polar model through
one new function, `CourseMaker`; there is no second sailing model.

**The boat really zigzags.**
- The voyage keeps the boat's offset from the course line, so its position on
  the chart, the plotter, traffic and saves is off the line.
- Progress towards the waypoint is the velocity made good. The distance
  sailed is boat speed × time.

**When it tacks**
- At the edge of a lane round the line. The lane narrows towards the
  waypoint, and tacks are at least 10 minutes apart.
- Before land: the whole corridor back to the line must be open water.
- On a lasting wind shift: 15 % better, after 30 minutes on a tack.

Each tack costs a little time: 60 s on the trimaran, 90 s on the monohulls,
120 s on the catamaran.

**By hand:** **K**, or **Tack now** / **Gybe now** on the action wheel, takes
the other tack at once. The autopilot keeps that tack for 30 minutes.

**In a harbour's approach** the boat keeps to its line and motors if the line
is to windward, as a skipper does.

**The deck** turns with the tack heading: the sails and boom cross over and
the wind swings.

**The instruments** name the tack ("starboard tack, beating to windward") and
show the progress made good and the next tack in about how long.

**The ETA** uses the same model. A 10 nm leg dead to windward is estimated at
4 h 05 min, not the straight line's 1 h 18 min, and the beat took 3 h 50 min.

**The boats differ.** Six hours to windward in 14 knots made good:

| Boat | Made good |
|---|---|
| Trimaran | 33 nm |
| 26 ft sloop | 17 nm |
| Catamaran | 16 nm |

The catamaran points worst (54° off the wind against the trimaran's 44°).

**One model change:** the close-hauled band of the polar curves (40–65°) was
raised to what cruising boats do to windward. Before, a 26-footer could not
beat at all and always motored.

## Tier 2 - fuel and the cost of ownership

- **Fuel.**
  - Each boat has a tank:

    | Boat | Tank | Burn | Range under engine |
    |---|---|---|---|
    | 26 ft | 45 L | 2.2 L/h | about 100 nm |
    | 33 ft | 120 L | 3.2 L/h | |
    | Trimaran | 70 L | 4.0 L/h | |
    | Catamaran | 380 L | 7.0 L/h | about 350 nm |

  - The engine burns fuel in the same step that moves the boat under engine;
    under sail it burns nothing.
  - An empty tank means sails only. Becalmed, the boat waits for wind; it is
    never stranded and never motors for free.
- **The fuel berth.** A pump by the walkway's head on every quay, open at any
  hour, with the price in its prompt. It fills up, or adds 10 litres, as far
  as the money goes.
- **Harbour dues.** Charged once, on leaving, for the nights moored (€26 a
  night for the 26 ft in Copenhagen). A short stop and anchoring are free.
  Beyond the money they are waived.
- **The choice to windward.** **Motor to windward** on the wheel. Four hours
  in 13 knots: beating made 11.2 nm on 0.9 L, motoring 20 nm on 8.8 L (about
  €17).
- **Running costs** in the harbour office, fuel on the status line and the
  switch panel.
- **The career's books.** Every euro now passes one place and is recorded by
  source, with fuel, miles and each voyage.
- **One central balance file:** `data/economy/economy.json`. Existing prices
  are unchanged; they were measured first.

## What the economy measurements say (Mode A, not human play)

These are 25 automated careers of 90 in-game days on the real rules (details
in the findings):

- **Nobody stranded,** and no low-money days.
- **A frugal life on the 26 ft costs about €48 a day:** fuel €13, dues €15,
  food and water €19.
- **Motoring to windward and moving daily** costs about €32 a day in fuel. It
  ends behind (−€1,450) at 3 hours of work a day.
- **Remote work (€25/h, up to 8 h a day) is the only material income.** It
  needs attention before passengers arrive in I028: as is, it would make them
  optional. A proposal is in the findings; **nothing has been changed**.
- **Not yet exercised:** boat care, upgrades, boat purchases and the bigger
  boats' running costs. That is the next step for the career harness.

## Windows: launch and a short walkthrough

1. Download the iteration at its tested commit:
   https://github.com/crosenlund79/WorldSailorSim/archive/refs/heads/backup/i027-tier-2.zip
   (or choose the branch `backup/i027-tier-2` on GitHub → Code → Download ZIP)
   and extract it.
2. In Godot 4.7.x: Import → the extracted `project.godot` → Edit. Wait for the
   first import, then press **F5**. The bottom-right label reads
   `BH · i027_02 · DEV`.
3. **New Game** → Start. You are in the cabin in Copenhagen.
4. **Fuel.** Walk on deck, along the pontoon, and up the walkway to the quay.
   - The red **pump** stands by the walkway's head ("Fuel berth · €1.99 a
     litre"). E shows the tank and *Fill up*. The status line shows "Fuel %".
   - The **Harbour Office** lists the running costs (scroll down in its list).
5. **Tacking.** Back aboard, plan a course to **Gothenburg** at the chart
   table and set sail.
   - Once clear of the harbour, look at the deck: when the wind is ahead the
     boat points about 45° off it. **I** shows "… tack, beating to windward"
     and the next tack.
   - Press **K** to tack by hand: the sails cross over.
   - **Q** shows **Tack now** and **Motor to windward** (try it: faster, and
     the fuel goes down).
6. **Harbour dues.** Stay a night in a harbour (the berth's alarm), then set
   sail. A note shows the dues paid.
7. **Save and load** (F5 / F9) mid-tack: the boat is where it was, on the same
   tack, with the same fuel.

What to judge (the gate):
- Does beating feel right?
- Is the fuel cost noticeable but not a chore?
- Are the dues fair?
- Does the 26 ft feel like a boat you can live on?

## Tests

- **Tier 1:** full regression at `93244d2`: 5,587 passed, 0 failed.
  `test_windward` 33 checks.
- **Tier 2:** full regression at the tested commit: see the delivery note.
  - `test_cost_of_wind`: 40 checks, including the wheel layout at
    1280×720 / 1024×768, 100 / 130 %.
  - Danish complete; content checker 31 PASS; guides and links clean.

## Performance

- The new work per evaluation (every 5 game minutes) is small:
  - one heading search (90 polar look-ups);
  - when beating, an open-water corridor check (at most 13 look-ups);
  - fuel arithmetic.
- The ETA walks the route with the same search.
- A same-session benchmark against `release/i026` is in the delivery note.

## Known limitations

- **Tack-loss timing.** A tack's lost time is charged within the 5-minute
  evaluation; the speed through the tack is not animated separately.
- **Manual tacking is a decision, not steering.** The autopilot still sails
  the angles; there is no free helm by design (no minigame).
- **Pump size.** The pump is small at true scale.
- **Boat care in the careers.** The career harness does not yet service the
  boat or buy upgrades.
