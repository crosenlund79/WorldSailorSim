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

## Tests and results

All on Linux (Godot 4.7.2; headless, screenshots and benchmark with Xvfb
and software OpenGL). Not Windows acceptance.

- **Full regression** on the TEST checkpoint `8184bd8` (82 suites):
  **5310 checks passed, 0 failed, no script errors**. On the way: the new
  suite left the old-save fixture in slot 3, which made `test_gameplay_flow`
  (it expects empty slots) fail in the full run; it now removes it. The
  rendered dock frames revealed the mirrored-companion bug (above), and the
  rendered laptop frame a doubled note when two companions of the same name
  were called aboard ("Both are back aboard." now).
- **New suite** `test_more_room_aboard` (about 115 checks): a new game
  alone (cabin, deck, sleep, wheel, laptop, save as an empty list); the real
  pre-I024 save and an I024 save keep their companion exactly, no adoption
  invented, the old field still written; encounter odds over 40 simulated
  careers (one in about four arrivals, never more than ten apart; the same
  arrival always gives the same answer; damaged data → safe defaults);
  trust, adoption (kind, name, gender, time, harbour), no renown; a second
  Pug with the same name (two ids), no third; saving while it follows and
  loading; casting off leaves it on its dock, never back after loading;
  declining; two-companion lines; Danish; in the game: the box, the animal
  at it (the conure on the rim), the gestures, following along the pontoon,
  the companionway question (Esc decides nothing), naming and the welcome
  (once), the girl for all three kinds (the conure on her shoulder), two
  companions side by side on one spot, a pair moment, both by the berth,
  two conures ashore, the departure refused and both called back, the
  laptop's *Aboard* line.
- **Updated suites** (behaviour changed on purpose, not weakened): New Game
  without a companion (`test_company_we_keep`, `test_companion_art`,
  `test_life_aboard`, `test_gameplay_flow`), companion counts that now
  count visible companions (`test_vessels`, `test_companion_art`), the first
  companion node by name (`test_anchor_life`), the cabin windows on every
  boat and then as plain glass (`test_cabin_windows`).
- **Saves:** `SAVE_VERSION` 12 unchanged; new fields optional; the save
  suites, the pre-I024 fixture and an I024-shaped save pass.
- **Content checker:** 31/31 PASS, 0 FAIL. **Languages:** 2899 messages,
  all in Danish, 0 errors. **Guides:** 328 scripts reviewed; **links:** 0
  broken.
- **Performance:** register #12 in
  [PERFORMANCE_OPPORTUNITIES.md](../../technical/PERFORMANCE_OPPORTUNITIES.md)
  (same session: before / live windows / plain glass). The plain-glass
  windows are 4-7 % cheaper in the cabin than the live views; the faded sea
  round the hull is most of I025's cabin cost on a CPU rasterizer (+25-40 %),
  to be read on the Captain's GPU. Two companions add lightweight nodes and
  no per-frame scans (pair moments every 80-180 s; following re-plans at
  most every 0.45 s).

**Release checklist** ([RELEASE_READINESS.md](../../technical/RELEASE_READINESS.md)):
1 content 0 FAIL ✓ · 2 English/Danish ✓ · 3 assets (checker, import) ✓ ·
4 saves ✓ · 5 full regression ✓ · 6 same-session performance ✓ · 7 guides
and links, report, index and Captain's Orders ✓ · 8 Windows acceptance
written, **pending** · 9 `iteration/i025` from the recorded start and
`release/i025` at the final commit, verified remotely, nothing
force-pushed ✓ · 10 limitations below ✓

## Screenshots and motion

From the running game at the TEST checkpoint (the corner reads
`LCH · i025 · TEST · 8184bd8`), in [`docs/screenshots/i025/`](../../screenshots/i025/):
01 the Captain alone at a new game · 02-04 the Ragdoll, the Pug and the
conure at the box · 05 the decision at the companionway (05b naming) · 06
a newly adopted conure exploring the cabin · 07 two companions greeting ·
08 two resting side by side (08b by the berth) · 09 the girl with the cat
· 10 the girl leaving with the Pug · 11 the conure on her shoulder · 12 two
companions ashore · 13 cabin realism (13b, 13c other boats) · 14 a harbour
before/after (Naples) · 15 neighbouring boats at scale (Kiel) · 16 the
cabin windows as plain glass by day and night · 17 the faded water
outside the cabin · 18 the laptop with the *Aboard* history · 19 the
build identifier. More harbours and boats before/after in `visual/`,
with every cabin before (`cabin_<boat>_before_*`) and after
(`i025_cabin_<boat>`; the Wing 33 in 16/16b). The first cabin "after"
images, taken while the windows still showed the outside, were replaced
when the Captain chose plain glass. Motion (`motion/`): frame strips of the girl's
three resolutions (the conure's flight to her shoulder), the welcome home
and a pair moment; reproducible by running `test_more_room_aboard` with
`--screenshots=DIR` and `tools/qa/film_strip.py`.

## Windows acceptance

**Pending** (the Captain's own trial): [WINDOWS_ACCEPTANCE_25.md](WINDOWS_ACCEPTANCE_25.md),
sections A (adoption), B (two companions), C (visual realism), D (existing
functionality).

## Known limitations and deferred

- **Pet toys** are not built (as ordered); a toy would be one more
  interaction on the companion node and one more pair-moment kind.
- One pair moment from the brief is not there: one companion gently taking
  the other's favourite spot. They visit, watch each other and nap together.
- The dock animals and the girl are seen at the deck's camera distance, so
  they are small on screen; the encounter reads best when the Captain walks
  up to it.
- The faded sea round the hull is the main cabin cost on a software
  renderer (register #12); a Windows reading decides whether to make it
  cheaper.
- The harbour's true scale has no automated test, only the rendered
  evidence; the HUD panels cover much of the far side, and on the Petrel 36
  and Halcyon 40 little of the far side or the town shows.
- At night the faded sea is very faint.
- New Game no longer offers a companion; `App.start_new_game()` and
  `GameSession.start_new_session()` still default to the cat for tools and
  tests.
- Small dead data left in place: `DockEncounters.recent` (kept in saves,
  read by nothing), and the older `HarbourDressing.STYLES` keys.
