# I028 Windows acceptance - Passages, People & Reputation

**Status: pending.** The Linux checks passed (see the
[iteration report](ITERATION_28_REPORT.md)). None of this list has been run on
Windows yet. These checks are the Captain's own.

## Setup

1. Download and extract the release ZIP:
   https://github.com/crosenlund79/WorldSailorSim/archive/refs/heads/release/i028.zip
2. In Godot 4.7.x, Import the extracted `project.godot` (not the ZIP), then
   Edit, and wait for the first import.
3. Press **F5**. The bottom-right label reads `BH · i028 · TEST · <commit>`;
   the title screen says version 0.114a.
4. Play at 1280×720 or larger. Do the Passages app and one passage once in
   English and once in Danish (Settings → Language).

Mark each line **pass**, **fail** (with a note), or **not tried**.

## Passengers (Tiers 1-3)

| # | Check | How | Result |
|---|---|---|---|
| 1 | Publish a passage | Plan a course on the chart (e.g. Copenhagen → Svendborg). Cabin laptop (E) → **Passages**: tick a stop, choose a departure window and a price, **Publish** | |
| 2 | Requests | Travellers' requests appear with their traits, group, pets and budget. **Accept**, **Decline**, or name a price once (**Ask**). Some go to a rival skipper, with a reason | |
| 3 | Boarding | At the departure window the guests walk up the gangway and find a place on deck or below. Nobody starts over the water | |
| 4 | Life aboard | Under way they read, drink coffee, take photographs, play with the pet, sleep below at night; **Talk with …** gives a line that suits them. No meters, no chores | |
| 5 | Legs and stops | A passenger for the first leg goes ashore at the stop; one for the second boards there. The next leg is plotted for you | |
| 6 | Settlement | On arrival: the balance, a tip if they were happy, a review (stars). Money appears once only | |
| 7 | Delay and caution | Turn back or shelter in bad weather: the guests thank you and no refund is taken for the caution. A late arrival without reason refunds a little | |
| 8 | Another harbour | Under way, propose a different harbour to a passenger (booking card). The honest transfer note (near / regional / far / ferry) shows, and they accept or decline | |
| 9 | Save mid-passage | F5 with guests aboard, quit, Continue: the same guests are aboard, and the passage settles once | |

## Dreams, writing and the wider world (Tiers 4-6)

| # | Check | How | Result |
|---|---|---|---|
| 10 | Dreams | Laptop → **Dreams**: 15 dreams, letters and keepsakes from passengers below. A passenger's dream (e.g. a night at sea) can come true on your passage | |
| 11 | Travel writing | Laptop → Home → **Travel writing…** (replaces the little game). Begin an essay about a voyage you made; write sessions with an angle; it is published with a small fee. An old save keeps its game release in the list | |
| 12 | Traveller Network | Laptop → **Network**: posts with pictures (silhouettes, harbours, ice, cafés) and some text-only. **Follow** someone and switch to **Following** | |
| 13 | Sails & Sights | Laptop → **World** → Sails & Sights: after the first month, an issue with a cover, stories and the top ten. **Older issue** shows earlier ones unchanged | |
| 14 | Rankings | World → **Rankings**: your place, the ten best-known, those around you, the memorable travellers | |
| 15 | Yacht directory | World → **Yacht directory**: search "Freya" or "Northern"; last public reports, old ones marked stale | |
| 16 | AIS | At sea near a notable yacht (Q → radar): an open diamond with its name, and an "AIS:" line. The directory never shows live positions | |
| 17 | Meeting and invitation | Moored where Northern Promise arrives (watch the directory: Bergen, Lerwick, Tórshavn, Reykjavik, Nuuk): a notice of coffee on the quay. With enough renown and good reviews an invitation appears in World; accepting books Freya Voss & Maya Wildshore as passengers | |
| 18 | Danish | All of the above in Danish: texts fit their buttons and cards | |

## Performance on the graphics card (Linux could not measure these)

| Check | How | Result |
|---|---|---|
| Guests aboard | Deck and cabin with 3-4 guests and a pet: smooth? | |
| Laptop apps | Network and World with a long history (many posts): scrolling smooth? | |
| Long Passage | A long voyage with guests at 12 h per second: smooth? | |

## Known and accepted (not defects)

- **Between Horizons is a working title only.**
- Magazine issues are written in the language that was active when they
  were published; switching language later does not rewrite the archive.
- The world's news for a day is written when the day is over, so a yacht's
  report can be up to a day behind (the directory says so: last report).
