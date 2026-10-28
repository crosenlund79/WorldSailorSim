# I025 - A Little More Room Aboard

*Found companions, shared lives and a more believable Real Horizon.* Version
**0.111a**, save format **12 (unchanged)**.

| | |
|---|---|
| Starting commit | `cfc9b52b9541fd024d6eb3c7bde3c836bd947439` (I024 and the build identifier, fast-forwarded onto `claude/friendly-fermat-dey23f` before the start) |
| Iteration branch | `iteration/i025` |
| Release branch | `release/i025` (at the final tested commit; see the delivery note) |
| Build label | `LCH · i025 · DEV` while developed, `LCH · i025 · TEST` on the release commit |

Pre-flight: I024 was released (`release/i024` = `52a7f6b`) and tested, and the
build identifier (`cfc9b52`) sat on top of it on
`claude/captains-hat-visual-redesign-cgoy5o`; the integration branch was still
at the handover head, so it was fast-forwarded to `cfc9b52` (a strict
ancestor; nothing rewritten) and `iteration/i025` was created there and
verified with `git ls-remote`.

## Part I - Found companions

### No pet at the start

New Game asks only how forgiving the sea should be ("Your boat is ready and
the sea is waiting. Who knows who you will meet along the way?"). Every place
that assumed a companion was audited and now works with none, one or two:
the cabin and deck nodes (one per slot; an empty slot shows nothing), sleep
and waking (no line with nobody aboard), the departure guard and the wheel's
*call aboard*, long-passage talk (silent alone), the rescue dialog's wording,
pastimes' postcard subjects, the laptop's history, the "a week at sea"
record, saving and loading. Existing saves keep their companion exactly.

### The box on the dock

Arriving in a harbour, now and then a small open cardboard box stands on the
pontoon, a little way downstream of the gangplank (clear of the services and
of the harbour's painted name): a Ragdoll sitting in it, a Pug beside it, or
a green-cheeked conure perched on its open rim - never a closed box or a
cage. It is drawn procedurally (`DockBox`: inside, flaps, tape, a soft
shadow; a back part under the animal and a front wall over it, so the cat
really sits *in* the box) and the animal is a stray `ShipCompanion`, so it
has every clip the companions have.

**Odds** (`DockEncounters`): decided once, at the arrival, from the game's
wind seed, the harbour and the arrival time - so loading, walking below or
opening the chart never rolls again - with a chance that starts at 10 % and
grows by 8 % with every arrival without one (at most 60 %). Over 40 simulated
careers this gives one in about four arrivals, never more than ten apart. Not
tied to any harbour; none while two companions live aboard; casting off ends
it (it stays on its dock) and it never comes back after a reload.

### Trust, without a meter

Three kind gestures with E - a hello, a free treat from the Captain's pocket,
a little play - each with its own line and answer per kind (the Ragdoll
pounces on a trailing rope and purrs, the Pug brings the rope knot back very
proud, the conure whistles a tune back nearly right); sitting quietly nearby
for a while also counts once. No shop, no meter. Then it follows: the cat
walks briskly, the Pug trots (its walk clip faster with its stride, so the
feet never slide), the conure flies short hops - along the pontoon, up the
gangplank and across the deck, around the fittings.

### At the companionway

Just before going below: *"The little Pug has followed you all the way home.
Would you like to welcome it aboard?"* **Adopt / Not now** (Esc decides
nothing; it keeps following). Adopt asks for a name and she/he/not said
(both optional, as in I024), then **Welcome aboard** and the cabin. The
companion records its kind, name, gender, a stable id, the game time of the
adoption, the harbour and the boat's position. A note says "Welcomed Pippa
aboard in Copenhagen."

### The welcome home

Once, the first time it is seen in the cabin, never replayed (`welcomed`,
saved): the cat looks round a couple of places, stretches and settles; the
Pug trots about, wags and sniffs; the conure flutters to a perch, chirps,
ruffles and flies on before settling. With a companion already aboard in the
cabin, the newcomer goes to it first and they greet (each pairing its own
way), then both settle.

### Not now: the little girl

The animal goes back to its box. A little girl in a muted red raincoat with
two short braids walks along the pontoon, stops and waves; the cat comes to
her, the Pug trots to her heels wagging, the conure flies to her shoulder.
She picks up the box and they walk away together and fade at the end of the
pontoon. No words, no sad music, no penalty; the encounter is recorded and
no new box appears in that harbour visit. She is drawn like the Captain
(`GirlDrawing`, seen from above, form by tone, a soft ink line), about 0.7 of
his shoulder width - not a full NPC: walk, stand, wave, carry, a shoulder.

### Two companions

Up to two, any kinds, the same kind twice and the same name twice included:
each has its own id, kind, name, gender, place, schedule, area, animation
and save record; signals name a companion by id. Sharing a spot (the settee,
the berth on waking) the second lies beside the first, never on top of it.
Now and then (every 80-180 s of real time at most, only while both rest
awake and time runs normally) they notice each other: a visit and a
greeting, a look across the cabin, a nap at the same time - specific per
pairing, never predatory (the cat watches the conure, it never stalks it).

Ashore both follow the Captain to different places on the pontoon; the
boat will not cast off while either is ashore, the question names them
("Wait! Snowy and Fido are still ashore.") and **Call Snowy and Fido aboard**
fetches both. Asleep: both by the berth, side by side, with one combined
morning line ("Snowy had claimed your pillow, and Fido was asleep at your
feet."). On long passages the Captain speaks to one of them, or about both
("Well, you two seem to have this voyage figured out.") - one remark per
gap, never twice as many.

### History and renown

The laptop's Voyage history has an *Aboard* section: "Welcomed Biscuit aboard
in Helsingør · <date>", from the companion's own record only; an older
companion says it has been aboard from the start (no date or place
invented). One new achievement, **Welcome aboard** (first adoption, no
renown); petting, gestures and attempts pay nothing. Renown, achievements
and their metadata are untouched.

### Saves (format 12, unchanged)

`companions` (a list, empty for nobody), `next_companion_id` and `encounters`
are new optional fields; the old `companion` field is still written for the
first companion, so an older build reads the save as before. Loading prefers
the list, falls back to the old field, caps at two, makes ids unique, and
gives safe defaults for anything missing or damaged. A following animal is
saved waiting by its box. Old companions get id 1, origin "start", no
adoption record, already welcomed.

## Part II - A more believable Real Horizon

(See the visual sections below: cabins, harbours, neighbouring boats,
windows and the water outside the cabin.)

VISUALS_PLACEHOLDER

## Part III

TITLE_PLACEHOLDER

**The laptop and the in-world interface** are kept as I024 left them; the
history gained its *Aboard* section. **Pet toys** are not built: nothing in
the companion code blocks them (an item would be one more interaction on the
companion node and one more pair-moment kind). **The build identifier**
reads `LCH · i025 · DEV` (and `TEST` on the release commit).

RESULTS_PLACEHOLDER
