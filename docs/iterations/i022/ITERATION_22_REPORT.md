# I022 — The Captain's Other Life (0.109a)

- **Version:** 0.109a.
- **Save format:** 12 (unchanged). Every new part of a save is optional and read leniently, and saves from 0.108a load as before.
- **Branches:** developed on `iteration/i022`; the immutable recovery snapshot is `release/i022`.
- **Testing:** everything below was run on Linux with Godot 4.7.2. **Windows was not tested**; the checklist is [WINDOWS_ACCEPTANCE_22.md](WINDOWS_ACCEPTANCE_22.md).

## 1. Commits and branches

| Step | Commit |
|---|---|
| Starting point (integration head after the radar fix) | `c4ff2550784d2729e7e4d2b44ff537b70ae507b9` |
| Loading screen and boot splash in the menu's navy | `5ae53ad` |
| A separate wind volume | `08a2533` |
| Boat prices and ownership; Relaxed / Standard / Seasoned Captain | `c694144` |
| Postcards from the Sea, A Game Developer at Sea, the one clock for hours-long tasks | `8b0b27a` |
| The Captain's Academy (First Voyage, tips, Handbook) | `0cc71b2` |
| Cabin windows, softer water, version, report | the final commit (§16) |

**Branch procedure** (CAPTAINS_ORDERS.md, major iteration policy):

1. `iteration/i022` was created at the verified integration head `c4ff255`. It was checked with `git ls-remote` and through the GitHub API before the first change.
2. All I022 work was committed and pushed only there. Each push was verified with `git ls-remote`.
3. At the end, `release/i022` was created at the final tested commit and verified the same two ways. It is never moved.
4. `claude/friendly-fermat-dey23f` was brought forward to the same commit by a fast-forward-only push.

What was left alone:

- The backup branches (`backup/post-turbocharge-pre-i019` `5b6474a`, `backup/post-i019-pre-i020` `ba0cacf`, `backup/post-engine-room-pre-i021` `ec84cfa`) and `release/i021` (`04a7623`) were not touched.
- No force-push, reset or history rewrite.
- The Captain's originals in `Visuals/Cat` are unchanged.

## 2. What was built and what was deferred

| Section | Status |
|---|---|
| 1 One authoritative clock for hours-long activities | **Done.** Postcards, the little game and remote work (sleep already did) |
| 2 Postcards from the Sea | **Done** |
| 3 A Game Developer at Sea | **Done** |
| 4 Boat prices, starter boat, old saves keep their boats | **Done** |
| 4 Two new boats | **Deferred** (§7) |
| 5 Difficulty: Relaxed / Standard / Seasoned | **Done** |
| 6 Loading screen in the main menu's style | **Done** |
| 7 Wind volume slider | **Done** |
| 8 Cabin windows (view-dependent) | **Proof of concept on one cabin** (Starling 33). The other three are not extended (§12). |
| 9 Softer, more translucent water | **Done** (colour blend, separate from the glass tint) |
| 10 Captain's Academy: audit, First Voyage, contextual tips, Handbook | **Done.** [Coverage reference](CAPTAINS_ACADEMY_COVERAGE.md) |

## 3. One authoritative clock (section 1)

There is one path for an activity that takes hours: `App.pass_time(work)`. It runs as follows:

1. The screen fades to black (`TimePassage.play_sleep`).
2. The normal simulation runs once under the black (`Simulation.spend_time_aboard`, or `Simulation.work` for remote work), with event stops on.
3. The clock counts the hours.
4. If an event stopped it, one line says why ("Interrupted: the boat has arrived").
5. The screen fades back in at **×1**.

Like sleep, it works while paused and leaves the pause as it was.

- **Events that interrupt:** arrival, a weather warning, a bite, the anchor alarm, the anchorage, traffic, a VHF call and rescue. They are the same stops as sleep, because it is the same `Simulation.advance(…, stop_at_events = true)`.
- **Partial progress:**
  - A postcard keeps the minutes already spent on it.
  - A game session keeps its task, its answer and the minutes worked; the points for the share worked count at once.
  - Remote work pays the full hours worked.
- **Continue or abandon:** both menus offer it.
  - Postcards: "Finish the card (1 h 2 min)" or "Throw away the unfinished card".
  - The little game: the interrupted task waits, showing "Go on working (…)".

The step-size invariance of the simulation was already proven by existing tests (one 15 h step equals 900 one-minute steps, and warnings fall at the same moment at 20× and in sleep). Running a pastime as one advance is therefore the same world as playing through it.

The test suite stops a postcard with a real arrival. It measures the hop from Copenhagen to Helsingør, starts a card an hour before arriving, checks that the card stopped part-way and was kept, and then finishes it later.

## 4. Postcards from the Sea (section 2)

Open it in the cabin: Q → **Write a postcard**.

**Subjects** come from the game's own records:

- each harbour visited;
- each species caught;
- the companion;
- each voyage made;
- the weather met on a voyage (rough or heavy weather, a storm);
- the evening light where the boat is, when the sun is low.

**Composing a card:**

- Three captions per kind, filled with the subject's names.
- Three layouts: Classic, Snapshot and Banner.
- A preview shows the card as it will look (`PostcardView`), drawn from the game's art:
  - the harbour's landmark (`HarbourLooks`, I021);
  - the fish art;
  - the companion's resting pose;
  - for voyages, weather and sunsets, a small painted sea and sky with a boat.

**Time and rewards:**

- The menu says before starting that a card takes **about 2 hours** of game time. Publishing then runs on the one clock.
- **Renown: 3, once per subject** (`postcard:<kind>:<subject>`). The same subject again makes a card for the scrapbook, with no reward. The list marks posted subjects with ✓.
- **Scrapbook:** up to 40 cards, newest first, with the date each was sent.

Screenshots: `pastimes_postcard`, `pastimes_scrapbook`.

## 5. A Game Developer at Sea (section 3)

The game is *Tiny Lighthouse* ("Lille Fyrtårn" in Danish). Open it in the cabin: Q → **Work on your little game**.

**Tasks:** there are five: a tiny feature, a funny bug, balance, arranging the scene, and an update.

- Each shows its length (**2–4 h**) before starting.
- Each asks one small question with three answers, shown in a changing order.
- The wise answer counts 2 points, any other 1. The points count for the share of the hours worked.

**Milestones:** six, from "The keeper walks" to "Release: Tiny Lighthouse 1.0".

- Each fills the devlog with its own entry and earns **4 renown once**.
- The release brings **€300** "first sales".
- After the release, small updates can still be made, with no repeated rewards.

Screenshot: `pastimes_game_dev`.

## 6. Boats, prices and old saves (section 4)

| Boat | Price |
|---|---|
| Arctic Wanderer 26 (starter) | €6,000 |
| Wing 33 | €14,000 |
| Frogleap 36 | €22,000 |
| Clam 40 | €32,000 |

**Buying:**

- A new game owns only the starter.
- Buying happens at a boatyard: never twice, never with money you do not have.
- A boat bought stays yours, and you can move aboard any boat you own at a boatyard.

**Old saves** have no `fleet` section, and every boat in the catalogue stays theirs: the boats were free to switch until now, so nothing is taken away and the money is unchanged.

**The save** gains `"fleet": {"owned": [...]}`, which always includes the boat aboard.

## 7. Two new boats: deferred

Assessed and deferred, for the same reasons as in I021:

- Each boat needs four scenes, three data resources, seven painted art layers and a full cabin layout with stations and collision.
- About 25 test suites name the boats.
- The assignment forbids placeholders.

The prices and ownership above make adding boats later straightforward: a catalogue entry plus a price.

## 8. Difficulty (section 5)

All values live in `data/progression/difficulty.json`:

| | Relaxed | Standard | Seasoned Captain |
|---|---|---|---|
| Starting money | €15,000 | €10,000 | €7,000 |
| Food and water used | ×0.8 | ×1 | ×1.2 |
| Wear | ×0.6 | ×1 | ×1.4 |
| Weather damage | ×0.6 | ×1 | ×1.3 |
| Harbour costs (boat care, provisions) | ×0.75 | ×1 | ×1.25 |
| Rescue fee | ×0.5 | ×1 | ×2 |

- **The weather itself is the same at every level.**
- **Where it is chosen:** in New Game. The level is saved as `"difficulty"`, and old saves are Standard.
- **Changing it during a game:** pause menu → Difficulty…. The new level counts from then on; nothing is retroactive and the money is unchanged.
- **Names:** English and Danish (Afslappet / Standard / Erfaren skipper).

Screenshot: `difficulty_dialog`.

## 9. Loading screen and wind volume (sections 6 and 7)

**Loading screen:**

- **Before:** the boot splash was beige, with the 1025×480 logo stretched over the window, so it was blurry and cut off. The loading screen after it followed the time of day, so it was beige by day.
- **After:** the boot splash is the menu's navy, with the logo at its own size. The loading screen is always the main menu's sky and sea gradient with the night logo.
- Screenshots `loading_before_*` and `loading_after_*` cover 1600×900, 1920×1080 and 1280×720.

**Wind volume:**

- The breeze and storm wind now play on their own **Wind** bus. It still passes through the muffled Outside bus below deck and sits under Ambience.
- Settings has a Wind slider with a breeze as its test sound.
- The default is 100 % (0 dB), which keeps the earlier balance exactly.

## 10. The Captain's Academy (section 10)

The audit of every player-facing feature, and where each is taught, is in **[CAPTAINS_ACADEMY_COVERAGE.md](CAPTAINS_ACADEMY_COVERAGE.md)**.

**Layer A, the First Voyage.** Eight steps, each ticked off by what the player really does:

1. walk;
2. open the action wheel (Q);
3. open the Captain's Log (L);
4. go on deck;
5. open the chart;
6. plan a course;
7. set sail;
8. let time run at 5× or 20×.

How it is offered:

- The first new game on a computer asks once: Begin or Skip (Esc skips).
- **A loaded game is never interrupted**, so existing saves are not forced through it.
- The card always has "Skip the First Voyage", and the Handbook can begin it again.

**Layer B, contextual tips.** 15 first moments, including:

- underway, a harbour, a boatyard, the cabin, the chart;
- a weather warning, a bite, traffic, a VHF call;
- anchoring, low stores, the hat, renown, a long passage, nightfall.

How tips behave:

- Each shows once per computer, in a small card at the lower right.
- A tip **never shows over an open window, a warning, a time passage, the voyage map or the loading screen**. It waits until the way is clear.
- There is a 20 s gap between tips.
- Each has "Got it" and "Read more" (its Handbook page), and closes by itself after 25 s.
- Settings → Tips turns them off. The Handbook's "Show the tips again" brings them back.

**Layer C, the Captain's Handbook.**

- 27 pages in 7 chapters, with a search box.
- Search works in the current language: "anker" finds anchoring in Danish.
- Open it with **F1** or pause menu → Captain's Handbook.
- Close, Esc and F1 all close it.

**Keys are never written into the texts.**

- `{interact}` and the like are filled in from the InputMap bindings, as the keyboard labels them.
- The only fixed keys are the ones the code handles by key code: F1, F5, F9, Delete and M.
- The test rejects an unknown placeholder or a key letter written into a text.

**Where its state is kept:** progress lives in `settings.cfg [academy]` (per computer, never in a save), and tips in `[interface] tips`. Restore defaults turns tips back on and keeps the progress.

**Rule check:** nothing in the Academy is a window that cannot be closed.

- The card has its buttons, and it is not modal.
- The offer is a normal confirm dialog that Esc answers.
- The Handbook has Close.

Screenshots: `academy_offer`, `academy_first_voyage`, `academy_chart_step` (the card stays clear of the chart's buttons), `academy_tip`, `handbook`.

## 11. Softer water (section 9)

The water's colour now comes from `WaterLook`, which blends a little of a sandy sea-bed colour into the old deep blue-green:

- 12 % at sea;
- 22 % in harbour or at anchor, where the water is shallow.

When moored or anchored, `ShallowWater` adds a few very faint sandy patches. They are drawn once and redrawn only when the boat leaves or returns.

- **No shader, no transparency, no per-frame work.**
- The day and night light, the crests and the ripples still lie over the water, so dawn, night, calm and storm stay as distinct as before.
- **Independently controllable:**
  - `WaterLook.translucency`: 0 gives exactly the old water, 1 is the default.
  - `CabinWindows.glass_strength`: the window glass tint.

  The test checks that changing one leaves the other alone.
- Before/after screenshots, moored and underway: `water_moored_before/after`, `water_underway_before/after`.

## 12. The world beyond the windows (section 8)

**The architecture found.** The cabin is seen from straight above. The illustrated cabins have no windows painted at all; their hull walls are a solid band about 25 units thick, and the space outside the hull is plain dark. So there is no glass to look through in the usual sense, and no 3D camera to aim.

**Rendering method.** `CabinWindows` (a Node2D right above the cabin's wall art and under its furniture) draws openings in that wall band.

- Each opening shows a slice of one shared, cheap **360° panorama** around the boat. The slice is flattened into the opening with "up" pointing out of the boat: sky at the outer edge, then the horizon, then the sea nearer the cabin.
- The window frames are drawn over the scenery, and the furniture stays in front.
- Everything is drawn inside each opening's rectangle. A test samples the cabin art and checks that every corner of every opening, with its frame, lies on wall paint, never on the floor or outside the hull.

**How the view depends on the viewer.** The slice's compass bearing is the sum of three things:

1. the boat's heading;
2. the window's side and the wall's slope;
3. the angle from the captain through the window.

Its width is the angle the opening covers seen from where the captain stands: about 17° from the middle of the cabin, about 45° from the settee beside the window, and at most 80°.

- **Port and starboard** show different things; moored heading east, they look north and south respectively.
- **Walking past a window turns its view.** Seen from 200 units aft, it swings more than 20° towards the bow.
- Screenshots from two viewpoints: `windows_view_aft` (captain by the galley) and `windows_view_close` (captain at the port settee). The slices in the windows differ visibly.

**What the panorama holds, and how scenery is selected**, all from the game's state:

- **Sky:** the colours of the sun's elevation (day, dusk, night) and the weather, grey when overcast.
- **Sun:** at its real bearing.
- **Stars:** at night.
- **Sea:** the `WaterLook` colour, lit by the hour, with crests that grow and whiten with the wind and the weather's hazard.
- **Rain:** streaks on the glass.
- **Glass:** a faint tint.
- **Moored:** the harbour's own I021 landmark art on the quay side. Starboard is the quay side, as the deck scenes lie alongside. The far shore shows small across the water to port, with lit windows at night.
- **Underway:** open sea on both sides.

Screenshots: `windows_dusk`, `windows_night`, `windows_underway`.

**Performance.**

- One redraw of all six windows costs a **median of 0.35 ms of CPU** (max 0.52 ms).
- They redraw only when the captain moves or every 2 s. The test counted **2 redraws in 60 frames standing still**.
- There is no shader, viewport, second world or theme work.
- The window sampling does nothing during the dawn/dusk card, beyond its 2 s refresh.

**Supported boats.** Only the **Starling 33 (Wing 33)**: three windows each side above the saloon settees, clear of the world map. This is the proof of concept the addendum asked for first.

The other three cabins are left unchanged (a test checks they have no windows node), because their walls differ:

- Each cabin's wall band and furniture are laid out differently.
- The Frogleap 36 trimaran has thin walls.
- The Clam 40 catamaran has its saloon between two hulls.

Each needs its own measured openings and a check that they stay inside its wall art. The data file and the wall test are ready for that.

**Limitations, honestly.**

- This is a 2D approximation of looking out, not optics. From above, a real window would be a slit, so the view is drawn as a small picture within the opening.
- Near the coast underway, the land is not drawn (open sea only).
- The quay side is taken as starboard rather than computed.
- With the classic (procedural) artwork the windows are not shown, because its walls are different shapes.

## 13. Saves and languages

**Saves:** format 12, unchanged. New optional sections:

| Section | Contents |
|---|---|
| `fleet.owned` | the boats owned |
| `difficulty` | the level |
| `pastimes` | scrapbook, draft, game |

A 0.108a save (none of these) loads with all boats owned, Standard difficulty, an empty scrapbook and a game not yet begun. Malformed sections are dropped quietly. The Academy keeps nothing in saves.

**Languages:** English and Danish. All strings found by the extractor are translated. Notes:

- The extractor now also reads `game_title`, `question`, `log` and lists of captions, choices and done-texts.
- It keeps strings containing `{key}` placeholders. Its "json-ish" rule was narrowed for this.
- That change also caught one shore-event line from an earlier iteration that had never been translated; it is now Danish too.
- Translations keep the placeholders, and the Academy test checks every one.

## 14. Tests

- **New suites:**
  - `test_academy`: 46 checks.
  - `test_cabin_windows`: 26 checks.
  - `test_captains_other_life`: 68 checks (prices, difficulty, pastimes, the one clock, menus).
- **Full regression** (all suites, headless, Linux): **4911 checks passed, 1 failed**.
  - The failure was `test_living_world` "[water] drawn over the water, under the boat": the new `ShallowWater` had been inserted between the water and `WaterLife`.
  - It is fixed by making `ShallowWater` a child of the water polygon (`e1c3b34`).
  - The affected suites were then rerun on the final code: `test_living_world`, `test_cabin_windows`, `test_branding` and `test_diagnostics` (the version is now 0.109a), `test_captains_other_life` and `test_academy`. Result: **274 checks passed, 0 failed**.
- **Also clean:**
  - the content checker (`tools/qa/check_game_content.py`): no FAIL;
  - links (`tools/docs/check_links.py`): 0 broken;
  - localization (`tools/i18n/check.py`): 0 errors;
  - the GDScript guides: every script reviewed in all three guides.

## 15. Performance

| Feature | Cost |
|---|---|
| Cabin windows | 0.35 ms median per redraw; redraws only on movement or every 2 s (§12) |
| Softer water | none per frame: one colour set when the scene opens or the boat leaves, arrives or anchors; shallow patches drawn once |
| Academy card | one cheap check every 0.25 s (state comparisons); the night tip reads the sun's elevation every 2 s |
| Pastimes | they use the same single advance as sleep |

Nothing was added to the day/night transition or the theme refresh.

## 16. Final state

The final commit, its tests and the release branch are recorded in the delivery note that accompanies this report. They are verified with `git ls-remote` and the GitHub API.

- **Iteration ZIP:** https://github.com/crosenlund79/LittleCaptainsHat/archive/refs/heads/iteration/i022.zip
- **Release ZIP:** https://github.com/crosenlund79/LittleCaptainsHat/archive/refs/heads/release/i022.zip
- **Windows checklist:** [WINDOWS_ACCEPTANCE_22.md](WINDOWS_ACCEPTANCE_22.md) (pending: not run on Windows).
