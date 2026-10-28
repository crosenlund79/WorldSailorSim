# I024 - The Company We Keep

*Living companions, meaningful renown and a life aboard.* Version **0.110a**,
save format **12 (unchanged)**.

| | |
|---|---|
| Starting commit | `41130c04e168239a082202f3d147ace543620f55` (head of `claude/friendly-fermat-dey23f` after the Great Handover) |
| Iteration branch | `iteration/i024` |
| Release branch | `release/i024` (at the final tested commit; see the delivery note) |

## Companions

**Species.** New Game offers a **Ragdoll cat**, a **Pug** and a
**green-cheeked conure** (a small parrot, not a macaw), with an optional name
(up to 20 characters, tidied) and an optional gender (female, male or not
said). No name is ever made up: without one the game says "the cat". The
saved kinds stay `cat` and `dog`, so every older save keeps its companion,
now drawn as the Ragdoll or the Pug; the parrot is the new kind `parrot`.

**Scale.** The animals were too large. Drawn sizes for the 256 px canvas:
cat 100 → **66**, dog 116 → **56**, parrot **50** scene units (the Captain is
about 40 across); the pivot is the animal's ground point, so it stands where
it rests. Checked in play beside the Captain, the cockpit, the companionway,
the settee, the berth and the pontoon (screenshots). The companions still
have no collision and never block the Captain.

**Animation** (`tools/companions/paint_companion_clips.py`, 203 frames,
Real Horizon style, one command). Clips per kind:

| | Clips |
|---|---|
| Ragdoll | idle breathing with tail, walk, turn, sit, lie down, sleep, wake, stretch, groom, look at the Captain, petting response, settle by the berth |
| Pug | idle, walk (trot), turn, sit, lie down, sleep, wake, stretch (play bow), tail wag, head tilt, petting response, settle |
| Parrot | perched idle, blink, head turn, hop, takeoff, flight (wing beats), landing, feather ruffle, preen, sleep, wake, interaction response |

`ShipCompanion` plays the clips: transitions between poses (lie down after a
walk, wake after a nap, settle into a nap by the berth), facing the way it
goes (mirrored, with a real turn when it reverses), walking at the stride's
own speed so the feet do not slide (cat 20.5, dog 11 units/s), and short
cross-fades. Between rests the cat grooms, sits or stretches, the dog wags or
sits, the parrot preens, ruffles, turns its head and blinks. The Captain's
own drawings still win: a Sprite Workshop replacement replaces a whole clip
with the one drawing. Evidence: `tests/companion_animation_preview.tscn`
(every clip playing; `docs/screenshots/i024/animation/companion_clips.gif`)
and the in-game screenshots.

**The parrot aboard.** Free, never caged. It perches at the chart table, the
back of the settee, by the berth and on the companionway steps (the cabins'
own markers), and on deck at the safe deck places; it flies between them
(takeoff, a little height, landing, a faint shadow below) or hops a short
way, and chirps when petted or answering. No pathfinding, no bird-care
simulation; it never speaks.

## Ashore, and never sailing without them

Moored in a harbour, when the Captain walks down the gangplank the companion
follows a moment later (cat and Pug walk down the plank, the parrot flies) to
a place on the pontoon near the Captain, clear of the service stations;
coming back aboard it sometimes lingers on the pontoon for a while.

**Departure.** `GameSession.depart()` - the one way to cast off - refuses
while the companion is ashore, with a personal line ("Wait! Fido is still
ashore." / "Vent! Fido er stadig i land."). Setting sail from the helm or
the wheel first asks to fetch it ("Fido is still exploring the pontoon." -
*Call Fido aboard*), then asks the usual departure question; the deck's
action wheel offers *Call Fido aboard* while it is ashore. Recalling always
works. No softlocks: changing boats brings it along, bad weather or anything
that ends the harbour stay brings it aboard, and a game saved with it ashore
loads with it on deck (older saves have no shore state at all).

## Waking, and talking on long passages

**Waking.** After any sleep the companion is found by the berth (the
Ragdoll or Pug at its foot, the parrot on its perch beside it) - placed
there under the black, not walking over. About one morning in two after a
real sleep, a small line: "Fido licked your nose.", "A quiet purr came from
the end of the berth.", "Kiwi greeted the morning with a little chirp." The
line shows only when nothing important woke the Captain (alarms, warnings,
arrival and the anchor moments come first). The sleep clock, hazards and
interruptions are unchanged.

**Long passages.** The Captain talks to the companion a little more as the
days at sea add up: three stages by the voyage's own clock (the first two
days, several days, from day five) with 8, 10 and 12 lines plus a few per
kind and gender (41 in all), never in the first six hours, then at most one
remark per 14, 9 or 6 game hours and never within four real minutes, and
only in a quiet moment (aboard, no window, notice, warning or tip). After a
reload the next remark is a full gap away; time acceleration and sleep
cannot bring a flood. The companion answers with its own animation and a
short line (a slow blink, a tilt of the head, a chirp, a clicked "winch") -
or, sometimes, with nothing. No meter, nothing to earn, nothing lost by
silence. All of it lives in `CompanionRemarks`, the existing companion
dialogue place.

## Renown: the audit

*Answer to the Captain's question:* **No - before I024 there was no renown
for boat speed.** Nothing measured sustained speed, and no objective used it.

**What existed** (inspected in code and data):

- 20 hand-made objectives in `data/progression/objectives.json` (7 of them
  secret hat achievements) and 3 generated "Far horizons" harbour goals:
  rewards 10-50 renown, categories (introduction, exploration, sailing,
  challenge, weather, secret) used only in data, no icons. Unlock: a voyage
  logged, or a hat event.
- About 25 one-off renown records awarded in code (`_award_once`): 7 world
  firsts, first fish and per-species and exceptional fish, galley, coffee,
  anchoring, haul-out, game milestones, VHF calls; plus per-subject
  postcards and per-harbour outings ashore.
- Storage: `progress.completed[id] = {count, first, last_event}` - the date
  of the first completion was always kept; **place and boat were not**.
- Filler and duplicates: *Across the Western Baltic* (Kiel), *The first
  hundred miles*, *Harbour hopper* (5), *Regular passages* (5 voyages),
  *Offshore passage* (200 nm) and the repeatable *Blue-water passage* sat
  beside stronger versions of themselves; *Long haul* (500 nm) and the world
  first *offshore crossing* (500 nm) were the same event twice; *Hat Trick*,
  *The Hat Tax* and *The Last Straw* were three variations on one joke. No
  objective depended on a removed feature.

**What changed.** A curated **achievement collection** of **35**
(`data/progression/achievements.json`, `AchievementCatalog`) in seven
categories, none empty: Voyages & Exploration (9), Seamanship (8), Sailing
Performance (4), Life Aboard (4), Companionship (3), Discoveries &
Collections (3), Reputation & Publications (4). An achievement is a *view*
on the existing renown records (consolidations: *Long haul* = 500 nm passage
or offshore crossing; *Far horizons* = any of the distant harbours; *Field
guide* = 8 species; *Postcards from the sea* = 5 subjects; *Local
knowledge* = 5 outings), so it pays nothing itself and **nothing is ever
paid twice**.

**Retired from the collection** (9): the six filler goals above plus the
three hat variations. They are no longer presented as goals (not in the
collection, not in the Captain's Log's open goals); once earned they appear
discreetly under *Earlier honours* in the Voyage history. **Renown
preservation:** they still pay their small renown as renown events, so the
renown economy, every test of it and every save are unchanged - no id was
renamed, nothing was confiscated or recalculated, totals stay exactly as
they were.

**Sailing speed** (new, credible, sailing only). Measured on the
simulation's own steps: the distance sailed in the last full hour (and the
last 24 hours) while the sails alone drive the boat without a break.
Motoring, anchoring, arriving or loading starts the count again; it is never
an instantaneous value, and time acceleration and sleep change nothing (the
simulation is the same at every speed). Physics unchanged. Thresholds from
the boats' real top speeds under sail (8, 10, 11 and 14 kn):

| Achievement | Requirement | Who can |
|---|---|---|
| Seven knots, sustained (10) | 7 kn for an hour under sail | every boat, in a fresh breeze |
| Nine knots under canvas (20) | 9 kn for an hour | not the Arctic Wanderer 26 (said in the text) |
| Flying (30) | 12 kn for an hour | only the Frogleap 36 trimaran (said) |
| A 150-mile day (25) | 150 nm under sail in 24 hours | every boat in steady wind |

The best hour and best 24 hours under sail are kept as personal records
(value, time, boat) and shown in the Voyage history.

**Companionship** (substantial, not farmable): *Shore leave* (ashore
together in 5 harbours, 10), *Ports of call* (3 countries, 15), *Just the
two of us* (a passage of 7 days or more, 25). Nothing for petting, talking,
sleeping, chirps or walking about.

**Unlock history.** New records keep where and on which boat they happened
(`at`: harbour id or rounded position, and the boat) and the renown they
paid, compact and without translated text; the game time was always kept.
The detail shows "Unlocked: Sat 2 May 2026, 14:16", "In Kiel, Germany" or
"At sea, 40.2°N 20.5°W", and "Aboard the Wing 33". Records from before I024
keep their real date and say *Location not recorded*; milestones passed
before their record existed (renown 250, a first travel update) say
*Previously unlocked* - nothing is invented.

**Badges.** 36 illustrated badges (`tools/achievements/paint_badges.py`):
steel rim, a disc in the category's muted colour, a clear pictogram; the
speed badges are one dial series. Locked: greyed and dimmed **and** marked
with a small padlock, so locked reads without colour; undiscovered secrets
show a sealed envelope and only a hint.

## The cabin laptop

The cabin's work station became **the Captain's laptop**: a drawn laptop on
the table in every cabin (Arctic Wanderer, Wing, Frogleap, Clam), its screen
lit a little brighter at night. Using it (E, or *Laptop* on the wheel) dims
the cabin and brings the laptop up close: graphite lid, bezel and camera,
the keyboard below in perspective, and **everything on its screen**. Four
apps in a tab row: **Home** (renown, achievements and publications at a
glance, recent achievements and postcards, remote work and the little
game), **Publications** (the existing postcard composer, scrapbook and
travel update, unchanged in time, rules, saves and renown), **Achievements**
(the collection: unlocked first, newest at the top, then locked; a category
filter; a detail panel with when, where and which boat), and **Voyage
history** (voyages, distance, harbours, longest passage, best hour and day
under sail, travel updates, recent passages, earlier honours). The existing
dialogs run inside the screen (`SimplePanel.embedded`), so there is no
second application framework and no double counting. Esc closes an open
task, then the laptop; the × closes at once; mouse and keyboard throughout;
English and Danish; the screen scales with the window and scrolls when the
interface is large. No browser, no fake operating system.

## Less floating interface

Audit and recommendations: [UI_PANEL_AUDIT.md](UI_PANEL_AUDIT.md). Done in
I024: postcards, scrapbook, travel update, remote work and the little game
moved onto the laptop; the cabin wheel has one *Laptop* item instead of two
pastime items; the Captain's Log no longer lists retired goals and points to
the laptop. Instruments, warnings, Trip Details, settings and pause stay
overlays; the I023 fixes (no overlaps, Trip Details steady, Esc, Danish)
are kept and tested.

## Handbook and languages

The Captain's Handbook: the companion page (three companions, names, shore
visits, why departure may wait, waking, conversations), the cabin, the
wheel, money and renown, postcards and the little game (now on the laptop),
and a new page *The laptop and your achievements* (apps, categories, unlock
history, speed records). The cabin tip mentions the laptop. No new tutorial
steps. English and Danish: 2841 messages, all translated (`check.py`: 0
errors).

## Tests and results

RESULTS_PLACEHOLDER

## Screenshots

From the running game (`tests/screenshots_i024.tscn`, Linux, software
OpenGL), in [`docs/screenshots/i024/`](../../screenshots/i024/):
01 Ragdoll beside the Captain, 02 Pug aboard, 03 parrot perched, 04 parrot in
flight, 05 companion ashore (05b departure waits), 06 the companion by the
berth on waking, 07 a remark on a long passage, 08 the laptop on the cabin
table, 09 the laptop open, 10 achievements with grey locked badges, 11 a
detail with date and place, 12 the postcard composer on the laptop, 13 a
category (with unlocked-first sorting), 14 voyage history, 15 Danish.
Close-ups (`…b_…closeup`) are enlarged crops of the same frames. Animation:
`animation/companion_clips.gif` and `tests/companion_animation_preview.tscn`.

## Windows acceptance (pending, the Captain's own trial)

1. New game with each companion (name and gender, or none); the animals'
   size beside the Captain and the furniture.
2. Watch each animal for a few minutes in the cabin and on deck: walking,
   turning, sitting, grooming or preening, sleeping and waking; the parrot
   flying between perches.
3. Walk ashore in a harbour; the companion follows; try to set sail - the
   game asks to call it aboard first.
4. Sleep a night: the companion by the berth, sometimes a morning line.
5. A passage of several days: the Captain's remarks now and then, never
   over a warning.
6. The laptop in each cabin: open, the four apps, a postcard, a travel
   update, Esc; Danish; a large interface size.
7. Load an I023 save: the companion (now a Ragdoll or Pug), its name if it
   had one, money, renown, achievements (dated, "Location not recorded"),
   postcards.

## Known limitations

- The camera does not move into the laptop; the laptop is brought up close
  as a view over the dimmed cabin (readability first).
- At very large interface sizes the laptop's apps scroll inside the screen.
- The parrot on deck uses the deck's resting places (cockpit and coachroof),
  not dedicated perches; it flies straight between them.
- The Pug's curled-tail wag is subtle at game size; the cat's face is mostly
  hidden while grooming.
- Speed records start counting from I024: earlier fast sailing was never
  measured, so it is not shown.
