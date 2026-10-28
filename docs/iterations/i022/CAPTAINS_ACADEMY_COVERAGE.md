# The Captain's Academy: feature audit and tutorial coverage (I022)

This is the reference for what the Academy teaches and where. It has two parts:

1. The audit: every player-facing feature in the game at the end of I022.
2. The coverage: for each feature, the layer that teaches it.

The Academy has three layers. All text is in `data/academy/academy.json`, in English and Danish.

- **A. First Voyage.** Eight steps, from walking about to letting time run. The first new game on a computer offers it once, with Begin or Skip. Loading a saved game never offers it. The card can be skipped at any time, and the Handbook can start it again.
- **B. Contextual tips.** A short tip the first time something happens. Each tip:
  - shows once per computer;
  - never shows over an open window, a warning, a time passage, the voyage map or the loading screen;
  - waits 20 s after the previous tip;
  - can be closed, or followed to its Handbook page;
  - can be turned off in Settings → Tips.
- **C. Captain's Handbook.** 27 pages in 7 chapters, with a search box. Open it with F1 or with Captain's Handbook in the pause menu.

The texts never name a key directly. A `{action}` placeholder is filled in from the game's own InputMap bindings, as the keyboard labels them. The only fixed keys are the ones handled by key code in the code: F1, F5, F9, Delete and M. A test checks every placeholder (`tests/suites/test_academy.gd`, `[keys]`).

## Where the Academy keeps its state

| What | Where | Notes |
|---|---|---|
| First Voyage state (never offered / active / skipped / done) and the step reached | `user://settings.cfg` `[academy]` | Per computer. A save file is never involved, so old saves are untouched. |
| Tips already shown | `user://settings.cfg` `[academy] seen` | Handbook → Show the tips again clears it. |
| Tips on or off | `user://settings.cfg` `[interface] tips` | Settings → Tips. Restore defaults turns tips back on and keeps the progress. |

## Audit and coverage

The legend for the columns:

- **FV**: the First Voyage step that teaches the feature.
- **Tip**: the contextual tip id.
- **Page**: the Handbook page id.
- **—**: none.

### Controls and getting around

| Feature | Keys / where | FV | Tip | Page |
|---|---|---|---|---|
| Walking | move keys (WASD / arrows) | walk | — | controls |
| Interacting with lit objects | interact (E) | deck | cabin | controls, cabin |
| Action wheel (Q menu) | action_wheel (Q) | wheel | cabin | wheel |
| Captain's Log | captains_log (L) | log | renown | controls, money |
| Pause menu, closing windows | pause (Esc) | wheel (close it) | — | controls |
| Captain's Handbook | F1, pause menu | farewell | — | settings |
| Cabin ↔ deck (companionway) | interact, wheel "Go on deck/below" | deck | — | cabin |
| Time controls (pause, 1×, 5×, 20×) | HUD buttons | speed | underway | time |
| One clock: sleep, work and pastimes pass hours under a fade, with interruptions | — | — | night | time, sleep |

### Sailing and navigation

| Feature | FV | Tip | Page |
|---|---|---|---|
| Chart: harbours, harbour search, planning a course | chart, course | chart | chart |
| Waypoints: drag to add, Delete to remove | — | chart | chart |
| Chart tabs: Course, Weather, Details; the wind time navigator | — | chart, weather | chart, weather |
| Chart zoom | — | — | chart |
| Setting sail; the boat follows the course | sail | underway | sailing |
| Chart plotter (P) | — | underway | sailing |
| Sailing details panel, radar (wheel) | — | — | wheel, sailing |
| Sail trim (T) | — | underway | sailing |
| Long Passage panel and voyage map | — | passage | long_passage |
| Anchoring: windlass, anchor alarm | — | anchor | anchor |
| Anchorage waypoints (M on the chart), the "anchor or sail on" prompt | — | — | anchor |
| Dreamer's world map in the cabin | — | — | home |
| Arrival and the docking card | — | arrival | harbour |

### Weather and safety

| Feature | FV | Tip | Page |
|---|---|---|---|
| Wind and weather, the forecast along the course | — | weather | weather |
| Weather warnings; they stop fast time and sleep | — | weather | weather, time |
| Wear, weather damage, rescue (and its fee) | — | — | condition |
| Traffic, collision warnings, radar | — | traffic | traffic |
| VHF calls (assistance, forecast) | — | vhf | traffic |
| Food and water, low-stores warnings | — | provisions | provisions |
| The hat and the wind (H) | — | hat | hat |

### Harbours, boats and money

| Feature | FV | Tip | Page |
|---|---|---|---|
| Harbour services differ per port | — | arrival | harbour |
| Grocery: food, water, a hat, lures, the fishmonger | — | provisions | harbour, provisions |
| Boatyard: boat care, haul-out, chandlery, sailmaker | — | boatyard | harbour, condition |
| Buying boats (I022); owned boats; moving aboard | — | boatyard | boats |
| Go Ashore | — | arrival | harbour |
| Remote work (harbour) | — | arrival | money |
| Renown, objectives, publishing travel updates | — | renown | money |

### Life aboard

| Feature | FV | Tip | Page |
|---|---|---|---|
| Fishing: rod, lures, bite, reel (R), cool box, release, sell | — | bite | fishing |
| Galley cooking; coffee, the mug and cup holders | — | — | galley |
| Sleeping 1–12 h | — | night | sleep |
| Companion: following, petting | — | — | companion |
| Postcards from the Sea (I022) | — | cabin | postcards |
| A Game Developer at Sea (I022) | — | cabin | game_dev |
| Make it home (cabin things), trophy board | — | — | home, cabin |

### The game

| Feature | FV | Tip | Page |
|---|---|---|---|
| Save slots, quicksave F5, quickload F9 | — | — | saving |
| Difficulty (I022) and changing it during a game | — | — | difficulty |
| Settings: volumes (incl. wind), display, size, light, language, accessibility, tips | — | — | settings |

## Not taught, on purpose

- **Developer tools:** F8, F10 and the developer guides. They exist only in development builds.
- **Main menu actions:** Import from Next Harbor, Load and Continue. These are self-explanatory buttons on the main menu.
- **Fine detail inside a window:** keep preferences, grades and the trophy rules. The window itself explains them.

The Handbook stays short ("less is more"). Its pages point to where a feature lives, and the game's own windows give the detail.

## Keeping it current

When a feature is added:

1. Add or extend a Handbook page.
2. If the feature has a first moment worth a word, add a tip id in `academy.json` and its trigger in `AcademyGuide._ready`.
3. Write any key as a `{action}` placeholder.
4. Add a row to this document.
5. Run `tools/i18n/extract.py` and translate the new strings.

`test_academy` fails on:

- a broken page link;
- an unknown key placeholder;
- a key letter written straight into a text;
- a Danish text that is missing.
