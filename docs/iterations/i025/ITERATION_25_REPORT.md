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

### Scale first

Measured on the painted boats, the art runs at about **1 cm per scene unit**
(the Starling 33's hull is 1000 units for 10 m; the Captain 40 units across
the shoulders), not the 2.5 cm the art guide said. Harbour houses, quay
fittings and neighbouring boats were 3-10 times too small; everything is now
drawn to the boats as painted (`HarbourDressing.METRE` = 100). The art guide
is corrected.

### Cabins (item 12)

All four cabins repainted as yacht interiors from their own scene shapes, by
one shared painter (`tools/vessels/cabin_joinery.py`): a gelcoat edge, pale
headlining and varnished battens on the hull band with frames about every
60 cm, a teak-and-holly sole with lift-out boards and brass finger rings,
rounded joinery with grain and fiddles, buttoned settee backs and piped
cushions with a lee cloth, berths with sheet, quilt and pillows, a stainless
stove and sink, the chart table's hinged lid and instruments, non-slip steps
with grab rails, louvred lockers. Per boat: the Arctic Wanderer 26 with three
portlights a side; the Wing 33 keeps its six windows and its black space aft
is now the cockpit above, behind a varnished bulkhead; the Frogleap 36's
floats are muted gelcoat instead of brown shapes; the Clam 40 has four large
saloon windows forward, wet heads with a teak grating, an L-settee and a
bunk with a bunk board. Walkable areas, collision, stations, spawn points,
companion spots and the laptop table are unchanged.

### Windows on every boat (item 15, revised by the Captain)

Every cabin has windows now, each in a framed recess painted into the wall:
portlights in the hull sides and, on the Clam 40, four saloon windows
forward; they sit under the furniture. Data in
`data/vessels/cabin_windows.json`.

During the iteration the windows first showed a live view of the world
outside (sky, sun, stars, the harbour's picture, sea crests, rain, turning
with the heading and with where the Captain stood). **The Captain then
changed his mind**, and the windows are now plain glass: smoked acrylic,
lighter at the outer edge where the daylight comes in, a soft reflection,
dark glass with a faint warm glint of the cabin lamps at night, dimmed with
the cabin by its own lighting. The panorama code was removed, not hidden:
nothing of the sea, harbour, other boats or weather is drawn through the
windows, nothing is redrawn as the Captain walks (it was redrawn on every
move before), and the glass reads the daylight once every 20 seconds. One
redraw of all six Wing 33 windows costs about 0.1 ms of CPU (the live view's
guide figure was about 0.35 ms). The faded sea round the hull, below, is a
separate treatment and stays.

### The water outside the cabin (item 16, kept)

The black void around the hull is gone: the deck's own sea (so wind,
weather, harbour shelter and the boat's speed all match) is drawn under a
night-blue veil, thinnest along the hull, a little stronger at night, with
the sun glints cut to a quarter; moored, the pontoon shows faintly to
starboard (`CabinSeaBackdrop`). It lies under all cabin art, the cabin lamps
do not light it, and the shader skips the floor the cabin art covers, so it
never reads as a transparent hull. Its cost is in the performance section.

### Harbour houses (item 13)

The generated town has building types per region instead of one recoloured
row: Nordic timber houses and gable-end boat sheds; Atlantic granite and
render terraces with slate roofs and chimney stacks; Mediterranean pantile
and hip roofs, roof terraces, shutters and umbrella pines; tropical tin
roofs, verandas, water tanks and palms. Roof materials at real size, detail
fading towards the back, a light haze. Quay fittings at real size (granite
coping 32, bollards r 14, a 75 cm life ring, lamps 34 × 22, ladders 44). All
fifteen painted looks and special harbours repainted at true scale - one or
two full-size buildings with real windows and doors and each region's
signature (a tarred boathouse, a stepped gable, a blue dome, Valletta's
coloured store doors, Essaouira's cannons, Lunenburg's ox-blood
warehouses) - with glazing bars, so the harbour moment still lights their
windows at night.

### Neighbouring boats (item 14)

A mix per region in real lengths - tenders 2.6-3.2 m, small sailboats
6-7.6 m, cruising yachts 9.5-12 m, large yachts, motor yachts, catamarans,
Nordic cutters, Atlantic crabbers, snekker, gozzi, tropical launches -
moored side by side and running on out of the picture, ends towards the
pontoon (bows in the Mediterranean, which moors stern-to), the far side
softly hazed. No magnifier circle. Collision, stations, the shore strip and
the clearance from the player's boat are unchanged.

Screenshots: `docs/screenshots/i025/visual/` (cabins before/after by day and
night, moored and underway; harbours and boats before/after for Copenhagen,
Kiel, Naples, Dingle, Dakar, Bergen, plus Le Marin).

### Found on the way

Since I017, every companion facing left was drawn one sprite width to the
right of where it stood (Godot draws a negative-width rectangle from its
position to the right; the old code shifted it once more). Its highlight
outline was always right, so tests never saw it; the dock animals' rendered
frames did. Fixed in `ShipCompanion._draw_texture_in`.

## Part III

### The name (item 17: discussion only, nothing renamed)

Asked to think about it, not to change it: the repository, save folders, app
identifier, metadata and file paths are all untouched.

| Candidate | For | Against |
|---|---|---|
| **Little Captain's Hat** (today) | Warm, personal, the hat is a real object in the game; it has history with the Captain and in the saves. | Sounds smaller and more childlike than the illustrated-realism direction; says nothing about sailing. |
| **LCH: Real Horizon** | Keeps the heritage and the build label's `LCH`, marks the new edition clearly. | A subtitle with a colon reads like an expansion pack; two names to remember. |
| **Real Horizon** | Short, calm, describes the look and the feeling of the sea; already the edition's name internally. | Loses the hat and the coziness; generic enough to collide with other products. |
| **WorldSailor** | Matches the repository (`WorldSailorSim`) and the world-wide sailing. | Sounds like a simulator brand, cooler than the game's heart; "Sim" expectations. |
| *Harbour Light* (new) | Cozy, evokes arriving somewhere safe at dusk, the lamps in the cabin, the golden harbours. | Less about the voyage itself. |
| *Fair Winds, Little Captain* (new) | Keeps "Little Captain", adds the sailor's blessing; gentle and specific. | Long for a title bar and a store tile. |

**Recommendation for the Captain's decision:** keep **Little Captain's Hat**
as the game's name for now, and use **Real Horizon** as the name of the
edition and art direction (as today) — a rename can wait until the store
page and the save folder questions are worth answering. If a new name is
wanted, *Fair Winds, Little Captain* keeps the most of what the game is.

**The laptop and the in-world interface** are kept as I024 left them; the
history gained its *Aboard* section. **Pet toys** are not built: nothing in
the companion code blocks them (an item would be one more interaction on the
companion node and one more pair-moment kind). **The build identifier**
reads `LCH · i025 · DEV` (and `TEST` on the release commit).

RESULTS_PLACEHOLDER
