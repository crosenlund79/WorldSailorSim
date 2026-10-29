# I027 Tier 3 - Yacht accommodation and commercial capability

**Status: done.** Built under the Captain's conditional approval of Tiers
1-2. No passenger marketplace (that is I028). Design: [DESIGN.md](DESIGN.md).

| | |
|---|---|
| Checkpoint | `backup/i027-tier-3` = `73473b4` |
| Build label | `BH · i027_03 · DEV` |
| Full regression | **5,651 passed, 0 failed** at `73473b4` (89 suites, headless Linux; Tier 2 had 5,628) |
| `test_accommodation` | 23 checks (data, art, queries, classes, the Pacific, the boatyard in English and Danish) |
| Danish | 3,125 messages, 0 errors |

## What each boat offers, as its cabin is drawn

One data file, `data/vessels/accommodation.json`, read by one class,
`Accommodation`.
- Every sleeping place, cabin and heads in it names the node that draws it in
  the boat's cabin.
- `test_accommodation` checks it both ways: nothing in the data that is not
  drawn, and the drawn cabins, heads and showers all in the data.

| | Arctic Wanderer 26 | Wing 33 | Frogleap 36 | Clam 40 |
|---|---|---|---|---|
| Size class | small | medium | medium | large |
| Safe aboard (skipper included) | 4 | 6 | 5 | 8 |
| Guests by day | 3 | 5 | 4 | 7 |
| Guests overnight | 2 | 2 | 2 | 4 |
| Sleeping places | V-berth (2), 2 settees | V-berth (2), 2 settees | V-berth (2), 2 settees | owner's double, guest double, bow bunk, saloon settee |
| Private guest cabins | none | none | none | 1 |
| Skipper's own cabin | no (open V-berth) | no | no | yes, with en-suite |
| Heads (enclosed) | none drawn | none drawn | none drawn | 2 |
| Comfort | simple and snug | comfortable | simple and snug | spacious |
| Suited to | offshore; oceans by island harbours | ocean | offshore; oceans by island harbours | ocean |
| Passage stores | 32 days | 36 days | 34 days | 45 days |

How the numbers were set:
- **Berths are not capacity.** The 26 ft sleeps four, but the V-berth is the
  skipper's and has no door. So it takes two guests overnight, on the saloon
  settees, and three by day.
- **The safe numbers** are the most people a boat of that size and type
  carries comfortably under way. The trimaran's (5) is below the Wing 33's (6)
  because a light trimaran is sensitive to weight.
- **Quality:**
  - settees and the Clam's bow bunk are basic (narrow);
  - the V-berths and the guest double are good;
  - the owner's double is fine.
- **Nothing was redrawn.** The interiors are I025's. Window treatment and
  every art path are unchanged.

## The booking queries (for I028)

All static, by boat id:

| Query | Answers |
|---|---|
| `safe_persons` | The most people the boat safely carries, the skipper included |
| `safe_guest_count` | Guests by day |
| `overnight_guest_count` | Guests who can sleep aboard (never the skipper's berth; never above the safe count) |
| `private_guest_cabins` | Cabins with a door for guests |
| `skipper_has_privacy` | Whether the skipper sleeps in a cabin of their own |
| `comfort_tier` | simple, comfortable or spacious |
| `passage_suitability` and `suits_passage(kind)` | coastal, offshore or ocean |
| `size_class` | small, medium or large |
| `heads_count` | Enclosed heads aboard |
| `sleeping_places` | Everyone the boat can sleep |

A boat missing from the file answers as the skipper alone, coastal: it never
offers a guest a berth it does not have.

## Meaningful differences (the most expensive is not the best)

- **Arctic Wanderer 26:** cheapest to buy and run (€6,000; 2.2 L/h; about €26
  a night in Copenhagen), intimate, adventurous.
- **Wing 33:** comfortable all-rounder, fitted for oceans, and still no
  private cabin.
- **Frogleap 36:** the fastest by far (8.7 kn at 50° in 14 kn), but spartan.
  Light, and fewer people aboard.
- **Clam 40:** the only boat with private cabins, an en-suite and two heads,
  for high-tier guests later. It also points worst (4.2 kn at 50°) and costs
  most to buy (€32,000), fuel (7 L/h) and berth.

The test checks the order: each class up is longer, dearer to buy, dearer in
dues and burns more. The Clam is the roomiest but not the best sailer.

## The boatyard shows it

The boatyard shows it in two places, in English and Danish:
- **The comparison of all four boats ("How they sail")** gains three rows
  under the speeds: *Guests by day / overnight* (3 / 2, 5 / 2, 7 / 4, 4 / 2),
  *Private guest cabins* (only the Clam 40: 1) and *Suited to* (Offshore,
  Ocean).
- **The selected boat's details** gain two rows:
  - *Sleeps*: the count and the berths, e.g. "4: V-berth, 2 × Saloon
    settee";
  - *Aboard*: comfort, the skipper's own cabin and the heads, e.g. "Simple
    and snug, no enclosed heads".

The free-text "Accommodation" line in the boats' specs was replaced by these
rows, so it cannot disagree with the data. On a small screen at 130 % the
boatyard scrolls, as it did before.

Screenshots: `docs/screenshots/i027/tier3`.

## The Pacific, as the Captain asked

The longest leg of the world voyage, Galápagos → Marquesas (3,090 nm), on the
world voyage's weather (seed 16). Each boat has a full tank, estimated with
the Tier 2 fuel-aware ETA:

| Boat | Estimated | Stows | Days to spare |
|---|---|---|---|
| Arctic Wanderer 26 | 27.9 d | 32 d | about 4 |
| Wing 33 | 20.7 d | 36 d | about 15 |
| Frogleap 36 | 14.8 d | 34 d | about 19 |
| Clam 40 | 18.2 d | 45 d | about 27 |

The estimate depends on the departure date. The world voyage's own crossing
on the 26 ft (a later date) took 31.3 days with 0.6 days to spare.

So the alternatives the Captain asked about exist, and nothing was made
easier:

- **A more suitable yacht.** The Wing 33 makes the same crossing with two
  weeks in hand.
- **Preparation.** On a fifth of a tank the 26 ft's estimate is 29.5 days
  against 27.9 on a full tank. The passage readiness now says so ("The fuel
  tank is 20 % full. A full tank carries her through calms and can shorten
  the passage").
- **Fishing on the way** adds food, though not water. This already existed.
- **The 26 ft keeps its 32 days of stores, unchanged.** Its readiness now
  answers a too-long passage plainly: "a stop on the way would break it up;
  a bigger boat stows more".

## Career testing: boat care and a real boat purchase

The career harness (Mode A) gained two policies. The Tier 2 policies are
unchanged, so their results stay comparable.

- **keeper:** the frugal life, plus every service the boatyard advises
  (recommended or needed) where there is one, and a haul-out when the bottom
  wants it.
- **upgrader:** 6 hours of work a day, the same care, and saving for the
  Wing 33. It buys the boat and moves aboard once the money covers the price
  plus a €3,000 reserve.

Results: [TIER_03_CAREER_FINDINGS.md](TIER_03_CAREER_FINDINGS.md).

## Recorded for the Captain

- **No heads drawn on three boats.** The 26 ft, the Wing 33 and the Frogleap
  36 draw no heads compartment, so the data says "no enclosed heads". A real
  cruising boat of that size has one. Drawing it is an art task for the
  Captain to commission. When it is drawn, the data gains it in one line, and
  the test will insist.
- **Character polish.** The Captain's later requirement (characters, the hat
  and a proper walk cycle) is scheduled for Tier 4 (see DESIGN.md).

## Save compatibility

Nothing is saved: accommodation is part of the boat. `SAVE_VERSION` stays 12.
