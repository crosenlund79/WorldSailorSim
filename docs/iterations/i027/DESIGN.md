# I027 - The Cost of the Wind: design

Version 0.113a. It starts from `release/i026` (`51c247e`) on `iteration/i027`.
The work is organised in four tiers. A permanent checkpoint branch is made at each tier's tested commit,
following the repository's `backup/…` convention: `backup/i027-tier-N`. **The process
stops for the Captain's acceptance after Tier 2.**

The commission is *Between Horizons, I027 + I028*. I028 is out of scope here.

## What exists (audit, at `51c247e`)

The boat's sailing performance comes from one source, `VesselProfile`, a
simple polar model:

- the angle-efficiency curve is 0 below about 35°;
- there is a spinnaker downwind;
- the engine gives a fixed `engine_speed_kn`.

`PropulsionController` chooses between sail and engine automatically, with
hysteresis. `Simulation.advance` moves `voyage.progress_nm` along the planned
route at the propulsion speed, evaluating on a 300 s grid. The boat always
steers the leg bearing.

Upwind, the sails give nothing, so the engine starts and the boat motors
straight to windward. **There is no tacking, no fuel, no harbour fee and no
accommodation data.**

The ETA (`estimate_route_seconds`) uses the same rule, so an upwind leg gets
the engine's straight-line time.

## Tier 1 - Windward sailing, tacking and an honest ETA

**One model.** Tacking is a heading choice on top of the existing polar
model and propulsion controller. It is not a second performance model.

### The course maker (`CourseMaker`, pure, static)

For a leg bearing B, the wind and the boat's profile, it searches headings
B ± δ (δ from 0 to 90°, in 2° steps) on each side. It maximises VMC (velocity
made good on course): sail speed(heading) × cos δ.

- If the direct course (δ = 0) gives at least 97 % of the best VMC, the boat
  sails straight.
- Otherwise the leg is a beat (upwind) or a run with gybes (downwind). The
  boat sails the best angle on its current side and changes sides as below.

The same function serves the simulation, the ETA and the instruments.

### Where the boat really is

The voyage keeps its progress along the planned line. It adds a signed
**cross-track offset** (nm, perpendicular to the leg), which is saved
(optional, defaults to 0).

- Each step advances the progress by VMC × dt and the offset by the lateral
  speed × dt.
- The boat's position (`Voyage.get_position`) is the line point plus the
  offset, so the chart, plotter, HUD, traffic and saves all see the zigzag.
- Nothing is advanced along an impossible straight line: the distance sailed
  is boat speed × time, while progress is VMC × time.

### When it tacks or gybes (autopilot)

It tacks or gybes at an evaluation point when one of these holds:

- the offset reaches the **lane edge**: half-width = clamp(0.3 × remaining leg, 0.4 nm, 6 nm);
- the next step would put the boat on land (the land mask at the offset point);
- a wind shift makes the other side's VMC at least 15 % better, after at
  least 30 minutes on this tack (the hysteresis).

A tack costs a short loss of speed: the boat makes no progress for
`TACK_LOSS_S` (90 s; 60 s for the trimaran, 120 s for the catamaran), charged
within the evaluation interval. The lane shrinks towards the leg's end, so the
boat converges on the waypoint. At a vertex the offset is carried into the
next leg's frame. When the leg is sailable directly again, the boat steers
back to the line at up to 15° until the offset is gone.

### Manual tacking

The helm offers **Tack now** while beating or running with gybes. The wheel
item and the key `K` do the same.

- It switches sides at once, with the same speed loss.
- The autopilot keeps the new tack for at least 30 minutes, unless the lane
  edge or land says otherwise.

That keeps the player's choice without a minigame, and long passages never
need a hand on every tack.

### Engine

The controller keeps its rules. While beating, its "potential" is the boat
speed on the tack, so the sails stay drawing when the boat sails well
close-hauled.

The angle-efficiency curves get a believable close-hauled band (for example
45° → 0.55 rather than 0.35 on the default curve). Without that, a 26-foot
sloop in 12 knots of wind could not beat at all. The change is documented
and the sailing tests are rerun.

The engine stays the answer for calms and very poor VMC. The choice of
"motor straight into it, at a fuel cost" belongs to Tier 2.

### Deck and instruments

These need no new drawing:

- The heading becomes the tack heading. `Simulation.get_current_heading()`
  returns it, so the deck's sails, boom side and wind follow.
- The instruments show the tack ("port tack · beating"), the VMC to the
  waypoint and the next tack ("tack in about 40 min").
- The plotter draws the real track.

### ETA

`estimate_route_seconds` walks the route with `CourseMaker`'s VMC (engine
speed where sailing would be too poor, as before), plus an estimate of the
tacking loss. A waypoint straight upwind therefore gets a beating time.

## Tier 2 - Fuel and the cost of ownership

The central balance file is `data/economy/economy.json`. It holds fuel
prices by region, consumption, harbour fees, and pointers to the existing
provisions, care and upgrade prices. Tier 2 does not reprice those: it
measures first.

### Fuel

- Each boat gets a tank size in litres and a burn rate in litres per hour at
  cruise (catalogue data).
- Fuel is saved as an optional section; old saves get a full tank.
- The engine burns fuel in the same simulation step that moves the boat
  under engine.
- An empty tank means sails only. Becalmed, the boat waits; the existing VHF
  and rescue paths still apply, so nothing is stranded for good.
- Fuel is bought at a **fuel berth**: a physical station on the pontoon or
  quay where the harbour has a yard or tier "larger" or above, with regional
  prices.

### Running costs

- **Harbour dues** are paid per night moored in a harbour, by tier and boat
  length, in one place and once. Anchoring is free.
- **Running costs** are shown in the harbour office, together with fuel range
  and fuel cost.

### Low money

Remote work, fishing and anchoring stay free paths. Dues can be deferred
rather than pushing money below zero. Relaxed difficulty is gentler, through
the `Difficulty` factors.

### Telemetry start

A `CareerLedger` records every change of money with a source or sink tag
(ring-buffered and saved), plus fuel bought and burned, and voyages. This is
real data, the foundation of Part VII.

**STOP: the Captain's gate.**

## Tier 3 - Accommodation (after the gate)

Each boat gets data that matches its drawn interior:

- safe capacity;
- berths and their quality;
- private cabins and skipper privacy;
- amenities and passage suitability.

Booking queries for I028 come from that data: `Accommodation`
(`src/vessels/accommodation.gd`, `data/vessels/accommodation.json`). Built:
[TIER_03_ACCOMMODATION.md](TIER_03_ACCOMMODATION.md).

## Tier 4 - Dreams, passage plans, telemetry and the opening (after the gate)

- **Dreams of the Sea:** a journal on the laptop.
- **`PassagePlan`:** a data contract built from the chart's planned route.
- **AIS:** an integration surface over `TrafficModel`.
- **The opening:** a skippable new-game story, plus the title source for the
  working title.

## Added requirement: characters that belong to the world (the Captain, after the Tier 2 gate)

Recorded as it was given, without interrupting Tier 3.

- **What it asks for:**
  - The Captain and the townsfolk drawn with believable proportions and
    restrained shading, matching the illustrated boats and harbours.
  - The Captain's hat redrawn with credible shape, material, scale and
    shading, still recognisable.
  - A walk cycle with the arms opposite the legs (today both arms swing
    together), subtle swing, slightly visible grounded feet, a little
    weight transfer, every direction, and a natural settle into idle.
  - One reusable human walk, with each person's clothes, silhouette and
    gait kept.
  - The animals' animations untouched.
- **What it is not:** a redesign of the character system, or new mechanics.
- **When:** I027 Tier 4, the core-integration stage, before `release/i027`.
  The Captain and the townsfolk get the shared walk and the new hat there.
  I028 Tier 2 (people aboard) then gives the passengers the same walk.
  Tier 3's gate and checkpoints are unaffected.
- **Acceptance:**
  - normal and diagonal walking; starting, stopping and turning;
  - cadence matched to speed;
  - 100 % and 130 % interface scale;
  - cabins, decks, pontoons, the quay, shops and the café;
  - no regression in collision, NPC paths, boarding or interactions;
  - before and after screenshots and a short moving capture.
- **Art rules:** `Visuals/` and `art_replacements/` are never touched; a
  Captain's replacement still wins (ArtworkResolver). Generated character
  art keeps its paths and canvases.

## Save compatibility

`SAVE_VERSION` stays 12. Everything new is optional with safe defaults:

- the voyage's cross-track offset, tack side and tack time;
- fuel;
- the ledger;
- later: dreams and the intro-seen flag.

The suites `test_save_manager` and `test_save_compatibility`-style checks run
in every tier.
