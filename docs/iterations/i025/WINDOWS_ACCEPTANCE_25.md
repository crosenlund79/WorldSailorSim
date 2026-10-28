# Windows acceptance: I025, A Little More Room Aboard

**Status: pending** (the Captain's own trial). Download `release/i025` (or
`iteration/i025`) from `crosenlund79/WorldSailorSim` (Code → Download ZIP),
open `project.godot` in Godot 4.7 and run. Linux test results are not Windows
acceptance. The build label in the bottom-right corner should read
`LCH · i025 · TEST` on the release commit.

## A. Adoption

1. New game: no companion is offered and none is aboard; the cabin and deck
   are quiet; sleep, the wheel and the laptop work without one.
2. Sail between harbours until a small cardboard box appears on the pontoon
   (on average about one arrival in four or five, never dozens). Check that
   it can be a Ragdoll (sitting in the box), a Pug (beside it) or a conure
   (perched on the open rim) over several finds.
3. Say hello, offer a treat, play (E); or simply sit nearby for a while. No
   meter appears; after a few gestures the animal follows you along the
   pontoon and up the gangplank (cat walks, Pug trots, conure flies).
4. Save and load while it waits or follows: it is still there, waiting by
   its box, and it does not appear twice. Walk to the cabin and back: it
   does not respawn elsewhere.
5. At the companionway the question appears: **Adopt / Not now**. Esc closes
   it without deciding (it keeps following).
6. Adopt: give a name (try a long one and a Danish one, e.g. "Æblegrød"),
   choose a gender or none, Welcome aboard. Below, its welcome plays once
   (cat explores and settles, Pug trots and sniffs, conure flutters and
   chirps). Go up and down again: it does not replay.
7. Not now: it goes back to its box, a little girl walks along the pontoon,
   it goes to her (the conure onto her shoulder), she picks up the box and
   they leave together. No message, no penalty; the box does not return.
8. Cast off while an animal still waits: it stays on its dock.
9. The laptop's Voyage history: "Welcomed <name> aboard in <harbour>" with
   the date; "Welcome aboard" in the achievements (no renown paid).

## B. Two companions

1. Adopt a second animal (try the same kind twice and the same name twice).
   Both appear in the cabin, each with its own place; no third animal is
   offered while two live aboard.
2. Watch for a few minutes: now and then they notice each other (a visit, a
   look across the cabin, a nap at the same time), never often.
3. Both on deck and both ashore: casting off is refused naming both, with
   **Call ... aboard** for both.
4. Sleep: both by the berth, side by side, one combined morning line.
5. A long passage: remarks to one of them or about both, not twice as often.
6. Save and load with two: names, kinds, places and adoption history kept.
7. Load an I024 save with its companion: kept exactly, no adoption date
   invented ("aboard from the start").

## C. Visual realism

1. Each cabin (Arctic Wanderer 26, Starling 33, Petrel 36, Halcyon 40):
   proportions, joinery, berths and lighting; the laptop, galley and berth
   still work.
2. Cabin windows on every boat show the outside world (harbour by day and
   night, open sea), port and starboard different, nothing bleeding through
   the hull.
3. The faded water outside the cabin never looks like a transparent hull.
4. Harbour houses: believable scale and regional character (Nordic,
   Mediterranean, Atlantic, tropical), no oversized buildings.
5. Neighbouring boats at believable sizes, naturally cropped, no circular
   "magnifier" look.

## D. Existing functionality

1. Sailing, the chart, fishing, cooking, the hat, anchoring and the laptop
   apps as before.
2. Save in each slot, load, and quit to the menu; a pre-I024 save loads.
3. Danish throughout the new dialog and lines; a large interface size.
4. The frame rate on deck in harbour and under way (Performance register
   #10, #11 and #12), and in the cabin with two companions.
5. The build label in the corner on every screen.
